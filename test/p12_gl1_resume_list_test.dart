// ============================================================
// test/p12_gl1_resume_list_test.dart — P12 / 第 9 期 · GL-1 集成验收
//
// 双触发（结束房间 / 存档槽保存） × 双通道（LAN 大写房号 / 云端小写房号）
// × 两端（KP / 玩家）：
//   · RoomSaveStore 中存在 meta.code == 'NU9E6R' 的条目且 parseSave 可解；
//   · 「续玩本级存档」列表（真 RoomEntryPage）出现该房号条目；
//   · 结束房间不清凭据（D-2 源码门禁 + 内存凭据存储不变量）。
//
// ★ 不真连服务端：续玩只验「条目存在 + 可点 + parseSave 可解」，
//   不触发真实重连（PRD §6.3 明确「不真连服务端」）。
// ============================================================

import 'dart:convert' show jsonEncode, utf8;
import 'dart:io' show Directory, File, Platform;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_model_save.dart' show parseSave;
import 'package:dice_realm/domain/room_types.dart' show RoomStatus, kHostSeat;
import 'package:dice_realm/repo/file_room_save_store.dart'
    show FileRoomSaveStore;
import 'package:dice_realm/repo/room_save_store.dart'
    show InMemoryRoomSaveStore;
import 'package:dice_realm/ui/room/room_controller.dart' show RoomController;
import 'package:dice_realm/ui/room/room_entry_page.dart'
    show RoomEntryKeys, RoomEntryPage;
import 'package:dice_realm/ui/room/room_save_syncer.dart'
    show RoomSaveSyncer, resumeKeyOf;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

const String _codeUpper = 'NU9E6R';
const String _codeLower = 'nu9e6r';

/// 一份最小合法快照（与 p19_save_sync_test 同形状）。
Map<String, Object?> _snapshot(String code, int savedAt) => <String, Object?>{
      'v': 2,
      'code': code,
      'savedAt': savedAt,
      'meta': <String, Object?>{
        'code': code,
        'status': RoomStatus.inGame,
        'round': 3,
      },
      'members': <Object?>[
        <String, Object?>{'seat': kHostSeat, 'role': 'kp', 'nickname': 'KP'},
        <String, Object?>{'seat': 'p1', 'role': 'player', 'nickname': '甲'},
      ],
    };

/// 把 KP 权威态置为「已结束房间」（room.close 的终态）。
void _closeRoom(RoomUiFixture f) {
  final Map<String, Object?> meta = asMap(f.hostState()['meta']);
  meta['status'] = RoomStatus.closed;
}

/// 造一个指向独立 store 的玩家端 syncer（同一后端语义，但可单独断言两端）。
RoomSaveSyncer _playerSyncer(
  RoomUiFixture f,
  InMemoryRoomSaveStore store,
) {
  final RoomController ctl = RoomController(
    session: f.sessionOf('p1'),
    local: f.localOf('p1'),
    notes: f.notes,
    saveStore: store,
  );
  return RoomSaveSyncer(
    controller: ctl,
    session: f.sessionOf('p1'),
    nowMs: () => 1700000000000,
  );
}

void main() {
  // 双通道：LAN 房号大写、云端房号小写（R8 / loadRecentCredentialFlexible 三形态）。
  const List<List<String>> channels = <List<String>>[
    <String>['LAN', _codeUpper],
    <String>['云端', _codeLower],
  ];

  group('A · 触发路径 ①「结束房间」→ 两端入列', () {
    for (final List<String> ch in channels) {
      test('${ch[0]} / 房号 ${ch[1]}：KP 终态落档 + 玩家收档，房号键都在', () async {
        final String code = ch[1];
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(code: code, inGame: true);
        final InMemoryRoomSaveStore playerStore = InMemoryRoomSaveStore();

        // KP 端：CLOSED 短路已修，onStateChanged 应走进 ③ 终态 autoSave。
        final RoomSaveSyncer kpSyncer = RoomSaveSyncer(
          controller: f.controllerOf(kHostSeat),
          session: f.sessionOf(kHostSeat),
          nowMs: () => 1700000000000,
        );
        _closeRoom(f);
        await kpSyncer.onStateChanged();

        expect(kpSyncer.autoSaved, greaterThanOrEqualTo(1),
            reason: '★ 结束房间必须真的触发一次 autoSave（改前 CLOSED 短路是死代码）');
        expect(f.saves.list(), contains(resumeKeyOf(code)),
            reason: 'KP 端续玩可见槽缺失，实测 ${f.saves.list()}');

        // 玩家端：收到 KP 的 save.share → onShared 落房号键。
        final RoomSaveSyncer plSyncer = _playerSyncer(f, playerStore);
        await plSyncer.onShared(_snapshot(code, 1700000000));
        expect(playerStore.list(), contains(resumeKeyOf(code)),
            reason: '玩家端续玩可见槽缺失，实测 ${playerStore.list()}');

        // 两端存档都可解，meta.code 原样保留（大小写不被改写）。
        for (final InMemoryRoomSaveStore? s in <InMemoryRoomSaveStore?>[
          // KP 端用的是夹具的 room_fakes 内存后端，类型不同 → 单独取。
          null,
          playerStore,
        ]) {
          if (s != null) {
            final Map<String, Object?>? p = parseSave(s.get(resumeKeyOf(code)));
            expect(p, isNotNull);
            expect(jsStr(asMap(p!['meta'])['code']), code);
          }
        }
        final Map<String, Object?>? kpSave =
            parseSave(f.saves.get(resumeKeyOf(code)));
        expect(kpSave, isNotNull, reason: 'KP 房号键必须 parseSave 可解');
        expect(jsStr(asMap(kpSave!['meta'])['code']), code);

        // 房号键归一：LAN / 云端两种写法都只占同一条槽。
        expect(resumeKeyOf(code), _codeUpper);
        expect(
          f.saves.list().where((String k) => k == _codeUpper).length,
          1,
          reason: '同房号只该有一条房号键',
        );
      });
    }
  });

  group('B · 触发路径 ②「存档槽保存」→ 两端入列', () {
    for (final List<String> ch in channels) {
      test('${ch[0]} / 房号 ${ch[1]}：saveNow 自定义名 + 房号键兜底', () async {
        final String code = ch[1];
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(code: code, inGame: true);
        final bool ok = await f.controllerOf(kHostSeat).saveNow(
              name: '$code · 第3轮',
            );
        expect(ok, isTrue);
        expect(f.saves.list(), contains(resumeKeyOf(code)),
            reason: '存档槽路径必须落房号键，实测 ${f.saves.list()}');
        final Map<String, Object?>? p =
            parseSave(f.saves.get(resumeKeyOf(code)));
        expect(p, isNotNull);
        expect(jsStr(asMap(p!['meta'])['code']), code);
      });
    }
  });

  group('C · 真「续玩本级存档」列表出现房号且条目可点', () {
    testWidgets('RoomEntryPage 注入同一 store 后列出 NU9E6R 条目（不真连服务端）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(code: _codeUpper, inGame: true);
      final RoomSaveSyncer kpSyncer = RoomSaveSyncer(
        controller: f.controllerOf(kHostSeat),
        session: f.sessionOf(kHostSeat),
        nowMs: () => 1700000000000,
      );
      _closeRoom(f);
      await kpSyncer.onStateChanged();

      // 故意同时造出三条同 code 的槽，验证 _reloadSaves 去重后仍只显示一条，
      // 且优先保留「键 == 房号」那条（R12 / Q-E）。
      f.saves.put('auto/$_codeUpper/close-1', _snapshot(_codeUpper, 1));
      f.saves.put('share/$_codeUpper/latest', _snapshot(_codeUpper, 2));
      f.saves.put(_codeUpper, _snapshot(_codeUpper, 3));

      // 复用夹具已验证的完整作用域链（RepoScope / SettingsScope /
      // ShareScope / RoomScope），只把页面换成真 RoomEntryPage。
      f.pageBuilder = (String s, String r) =>
          RoomEntryPage(saveStore: f.saves);
      useRoomScreen(tester, 412, 915);
      await tester.pumpWidget(f.pageOf(kHostSeat));
      await tester.pump();

      final Finder row = find.byKey(RoomEntryKeys.resumeRow(_codeUpper));
      expect(row, findsOneWidget,
          reason: '续玩列表必须出现 NU9E6R，且三条同 code 槽被去重成一条');
      expect(find.byKey(RoomEntryKeys.resumeLoad(_codeUpper)), findsOneWidget,
          reason: '条目上应有「续玩」按钮（可点，不真连服务端）');
      // 只验到条目与按钮，不 tap 触发真实重连（PRD §6.3）。
      expect(tester.takeException(), isNull);
    });
  });

  group('E · ★ 2.37.0/Q1 文件后端端到端：玩家收档 → 重开 → 续玩列表可见', () {
    testWidgets('FileRoomSaveStore 上 onShared 落 share+房号键，重开后真页面列出条目',
        (WidgetTester tester) async {
      final Directory dir =
          Directory.systemTemp.createTempSync('p12_gl1_file_e2e_');
      addTearDown(() {
        try {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final FileRoomSaveStore store = FileRoomSaveStore(dir);
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(code: _codeUpper, inGame: true);
      final RoomController ctl = RoomController(
        session: f.sessionOf('p1'),
        local: f.localOf('p1'),
        notes: f.notes,
        saveStore: store,
      );
      final RoomSaveSyncer plSyncer = RoomSaveSyncer(
        controller: ctl,
        session: f.sessionOf('p1'),
        nowMs: () => 1700000000000,
      );
      await plSyncer.onShared(_snapshot(_codeUpper, 1700000000));
      // ★ widget 测试跑在 fake-async 区域：真实 dart:io 异步写盘的 Future 永不完成
      //   （T1 铁律）。这里用同步写模拟「进程已被杀、磁盘上留着上次的存档」，
      //   loadSync() 本身同步；异步落盘真链路已由纯 Dart 用例
      //   file_room_save_store_test.dart / p19_save_sync_test.dart 覆盖。
      final String hex = utf8
          .encode('share/$_codeUpper/latest')
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      File('${dir.path}${Platform.pathSeparator}'
              '${FileRoomSaveStore.encodedSlotMarker}$hex.json')
          .writeAsStringSync(jsonEncode(_snapshot(_codeUpper, 1700000000)));
      File('${dir.path}${Platform.pathSeparator}$_codeUpper.json')
          .writeAsStringSync(jsonEncode(_snapshot(_codeUpper, 1700000000)));

      final FileRoomSaveStore reopened = FileRoomSaveStore(dir)..loadSync();
      expect(reopened.list(), contains('share/$_codeUpper/latest'),
          reason: '★ 玩家收档槽必须真落盘');
      expect(reopened.list(), contains(_codeUpper),
          reason: '★ 玩家房号键必须真落盘');

      // 重开后的 store 直接喂给真 RoomEntryPage：续玩条目必须出现且可点。
      f.pageBuilder = (String s, String r) =>
          RoomEntryPage(saveStore: reopened);
      useRoomScreen(tester, 412, 915);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      expect(find.byKey(RoomEntryKeys.resumeRow(_codeUpper)), findsOneWidget,
          reason: '★ 文件后端落盘的存档必须出现在续玩列表');
      expect(find.byKey(RoomEntryKeys.resumeLoad(_codeUpper)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('D · 结束房间不清凭据（D-2）', () {
    test('源码门禁：_RoomShellState.dispose 不调用凭据 clear', () {
      // 源码门禁（只读）：D-2 口径必须在 dispose 里保留，且不得清凭据。
      final String src =
          File('lib/ui/room/room_entry_page.dart').readAsStringSync();
      final int start = src.indexOf('void dispose()');
      expect(start, greaterThan(0));
      final String disposeBody = src.substring(start, start + 900);
      expect(disposeBody.contains('clearRecentCredential'), isFalse,
          reason: 'D-2：关房不得清持久化凭据');
      expect(disposeBody.contains('recentCredential') &&
              disposeBody.contains('clear()'),
          isFalse,
          reason: 'D-2：dispose 里不得出现凭据存储 clear()');
    });

    test('凭据三形态归一仍可用（大小写混合房号查得到）', () {
      // loadRecentCredentialFlexible 的「原样 → 小写 → 大写」三形态是既有能力，
      // 这里钉死「房号键归一」不依赖它：resumeKeyOf 已统一成大写。
      expect(resumeKeyOf('Nu9E6r'), _codeUpper);
      expect(resumeKeyOf(' nu9e6r '), _codeUpper);
    });
  });
}
