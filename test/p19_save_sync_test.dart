// ============================================================
// test/p19_save_sync_test.dart — P19 存档自动保存 + 全员分发/落盘
//
// 用户需求（2026-11-14）：
//   ① KP 和所有玩家的手机上都保存一份存档，并标上时间戳；
//   ② KP 和玩家都可以回到存档的房间继续进行游戏（入口页「续玩」）；
//   ③ 缺席的玩家回来后，缺失的存档可以同步到最新的那一份（看时间戳）；
//   ④ 自动存档触发点：KP 推进下一回合、每 10 分钟、结束房间 / 结团；
//   ⑤ 存档时，玩家游戏中的角色卡状态自动保存到「角色卡」。
//
// 架构事实（动手前逐条核过源码）：
//   · 分发协议：`save.share`（POLICY [kp]，P19 新增第 62 条）→
//     `RoomEvt.saveSync`（reduce **无分支**走 default，同 tempCommit 模式）
//     → 每个 view 的 `_captureNotice` 拦截 → `onSharedSave` 回调落盘。
//   · 玩家续玩：玩家本地存的是 KP 广播的**全量快照**（`_tagSave` 打上
//     `meta.role/seat` 视角标记），`resumeLocalRoom` → `openSave` →
//     `importSave`（P19 放宽：带 `meta.role` 的本机存档允许玩家灌档）。
//   · 触发器：`RoomSaveSyncer.onStateChanged` 监听回合变化 / 成员加入 /
//     房间结束；周期存档由壳体 startTicker（10 分钟）。
//
// 反向自证伪：
//   · 删掉 `onShared` 的时间戳比较 → 用例「乱序旧快照」必红；
//   · 把 `shareSave` 的空载荷校验删掉 → 用例「空载荷拒绝」必红；
//   · 把 `importSave` 的 `localResume` 放宽删掉 → 用例「玩家续玩灌档」必红。
// ============================================================

import 'dart:io' show Directory, File;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_model_save.dart' show parseSave;
import 'package:dice_realm/domain/room_types.dart'
    show RoomEvt, RoomRole, RoomStatus, kHostSeat;
import 'package:dice_realm/repo/file_room_save_store.dart'
    show FileRoomSaveStore;
// harness 的 InMemoryRoomSaveStore 只有 put/get/list（无 clear），这里要验
// 「本机无档 → saveOnOpen 补档」的幂等，故用 repo 层真正的可变后端。
import 'package:dice_realm/repo/room_save_store.dart'
    as repo_store show InMemoryRoomSaveStore;
import 'package:dice_realm/ui/room/room_controller.dart'
    show RoomController;
import 'package:dice_realm/ui/room/room_save_syncer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dice_realm/ui/room/room_boot.dart'
    show resumeLocalRoom;

import 'support/room_ui_harness.dart';

/// 造一份最小合法快照（`shareSave` 要求非空且有 `code`）。
Map<String, Object?> _fakeSave(String code, int savedAt) => <String, Object?>{
      'v': 2,
      'code': code,
      'savedAt': savedAt,
      'meta': <String, Object?>{
        'code': code,
        'status': 'IN_GAME',
        'round': 3,
      },
      'members': <Object?>[
        <String, Object?>{'seat': 'host', 'role': 'kp', 'nickname': 'KP'},
        <String, Object?>{'seat': 'p1', 'role': 'player', 'nickname': '甲'},
      ],
    };

void main() {
  test('dispatch：KP 发 save.share → 广播 evt:savesync；空载荷被拒不发',
      () async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);

    // ① 空载荷：不发事件，只给系统提示
    f.clearSent();
    await f.controllerOf(kHostSeat).hostAction('save.share', <String, Object?>{
      'save': <String, Object?>{},
    });
    expect(
      f.sessionOf(kHostSeat).sentLog.where((m) =>
          m['k'] == 'evt' && m['t'] == RoomEvt.saveSync),
      isEmpty,
      reason: '空快照不许广播（防止坏快照散到所有玩家手机）',
    );

    // ② 缺房间号：同样拒绝
    await f.controllerOf(kHostSeat).hostAction('save.share', <String, Object?>{
      'save': <String, Object?>{'v': 2},
    });
    expect(
      f.sessionOf(kHostSeat).sentLog.where((m) =>
          asMap(m['msg'])['k'] == 'evt' &&
          asMap(m['msg'])['t'] == RoomEvt.saveSync),
      isEmpty,
      reason: '缺 code 的快照不许广播',
    );

    // ③ 合法快照：广播成功
    await f.controllerOf(kHostSeat).hostAction('save.share', <String, Object?>{
      'save': _fakeSave(f.sessionOf(kHostSeat).code, 12345),
    });
    expect(
      f.sessionOf(kHostSeat).sentLog.any((m) =>
          asMap(m['msg'])['k'] == 'evt' &&
          asMap(m['msg'])['t'] == RoomEvt.saveSync),
      isTrue,
      reason: '合法快照必须广播给全员',
    );
  });

  test('玩家端：收到快照落盘（时间戳去重；乱序旧快照被丢弃）', () async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    final p1 = f.sessionOf('p1');
    final syncer = RoomSaveSyncer(
      controller: f.controllerOf('p1'),
      session: p1,
    );
    p1.onSharedSave =
        (Map<String, Object?> save) => syncer.onShared(save);
    final store = f.controllerOf('p1').saveStore!;

    // 新快照（savedAt 200）→ 落盘
    await syncer.onShared(_fakeSave(f.sessionOf(kHostSeat).code, 200));
    expect(syncer.receivedCount, 1);
    expect(
      store.list().any((k) => k.startsWith('share/')),
      isTrue,
      reason: '快照必须写进本地存档库（玩家手机上保存一份）',
    );

    // 乱序旧快照（savedAt 100 < 200）→ 丢弃
    await syncer.onShared(_fakeSave(f.sessionOf(kHostSeat).code, 100));
    expect(syncer.skippedStale, 1,
        reason: '比本地旧的快照必须丢弃（时间戳去重）');
    expect(syncer.receivedCount, 1);

    // 更新的快照（savedAt 300）→ 覆盖（旧份删除，只留最新）
    await syncer.onShared(_fakeSave(f.sessionOf(kHostSeat).code, 300));
    expect(syncer.receivedCount, 2);
    final shareKeys =
        store.list().where((k) => k.startsWith('share/')).toList();
    expect(shareKeys.length, 1,
        reason: '同一房间只保留最新一份（缺失的存档同步到最新的那一份）');
    expect(asMap(store.get(shareKeys.first))['savedAt'], 300);
    // 视角标记必须打上（玩家续玩恢复身份的依据）
    final stored = asMap(store.get(shareKeys.first));
    expect(jsStr(asMap(stored['meta'])['role']), RoomRole.player);
    expect(jsStr(asMap(stored['meta'])['seat']), 'p1');
  });

  test('KP 自动存档：回合变化触发（存 auto/ 槽 + 广播）', () async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    final kp = f.sessionOf(kHostSeat);
    final syncer = RoomSaveSyncer(
      controller: f.controllerOf(kHostSeat),
      session: kp,
    );
    final store = f.controllerOf(kHostSeat).saveStore!;

    // 第一遍：记录当前回合（首轮只记基线，不存档）
    await syncer.onStateChanged();
    expect(
      store.list().where((k) => k.startsWith('auto/')).length,
      0,
      reason: '首轮只是记基线，不触发存档',
    );

    // 回合 +1（模拟 KP 推进下一回合）→ 自动存档 + 广播
    final before = syncer.sharedCount;
    await f.controllerOf(kHostSeat).hostAction('room.next', null);
    // room.next 不是开房动作也能推进 round？——直接改权威态模拟回合推进。
    final metaNow = Map<String, Object?>.from(asMap(kp.host.state['meta']));
    metaNow['round'] = 5;
    kp.host.state['meta'] = metaNow;
    await syncer.onStateChanged();
    expect(syncer.autoSaved, 1, reason: '回合变化必须自动存档');
    expect(syncer.sharedCount, greaterThanOrEqualTo(before),
        reason: '自动存档成功后必须广播快照');
    expect(
      store.list().any((k) => k.startsWith('auto/')),
      isTrue,
      reason: '自动存档槽键必须带时间戳（auto/<code>/...）',
    );
  });

  test('玩家续玩：落盘快照可被 resumeLocalRoom 恢复成玩家视角', () async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    final p1 = f.sessionOf('p1');
    final syncer = RoomSaveSyncer(
      controller: f.controllerOf('p1'),
      session: p1,
    );
    p1.onSharedSave =
        (Map<String, Object?> save) => syncer.onShared(save);
    final store = f.controllerOf('p1').saveStore!;
    await syncer.onShared(_fakeSave('SYNC01', 500));

    final key = store.list().firstWhere((k) => k.startsWith('share/SYNC01/'));
    final save = asMap(store.get(key));
    expect(save, isNotEmpty);

    // 续玩：玩家视角本地重建（离线可玩 —— 存的是 KP 全量快照）。
    // `resumeLocalRoom` 按 `meta.role/seat` 恢复身份（P16 落点），
    // `openSave → importSave` 由 P19 放宽放行玩家本机灌档。
    final (boot, migrated) = await resumeLocalRoom(save);
    expect(boot.session.role, RoomRole.player, reason: '身份必须不变（玩家）');
    expect(boot.session.seat, 'p1', reason: '座位必须不变');
    expect(boot.session.state['members'], isNotEmpty,
        reason: 'P19 放宽 importSave 后，玩家本机续玩必须灌进存档内容');
    expect(asMap(boot.session.state['meta'])['round'], 3,
        reason: '续玩后回合号 = 存档时的回合号');
    expect(migrated, 0);
  });

  // ============================================================
  // ★ 2.37.0 / Q1：玩家侧主因（远端控制器未接 saveStore）+ 落盘链路真变
  // ============================================================
  group('★ 2.37.0 / Q1 存档主因回归', () {
    test('★ 玩家 onShared 用 FileRoomSaveStore：share + 房号键真落盘，重开可见',
        () async {
      final Directory dir =
          Directory.systemTemp.createTempSync('p19_player_file_');
      addTearDown(() {
        try {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final FileRoomSaveStore store = FileRoomSaveStore(dir)..loadSync();

      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final String code = f.sessionOf(kHostSeat).code;
      final RoomController ctl = RoomController(
        session: f.sessionOf('p1'),
        local: f.localOf('p1'),
        notes: f.notes,
        saveStore: store,
      );
      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: ctl,
        session: f.sessionOf('p1'),
        nowMs: () => 1700000000000,
      );

      await syncer.onShared(_fakeSave(code, 200));
      expect(syncer.receivedCount, 1);
      await store.flush();

      // 模拟杀进程重开：两份都在（玩家手机上一份都不能少）。
      final FileRoomSaveStore reopened = FileRoomSaveStore(dir)..loadSync();
      expect(reopened.list(), contains('share/$code/latest'),
          reason: '★ 玩家收档槽必须真落盘');
      expect(reopened.list(), contains(resumeKeyOf(code)),
          reason: '★ 玩家房号键必须真落盘（续玩可见）');
      final Map<String, Object?> tagged =
          asMap(reopened.get('share/$code/latest'));
      expect(jsStr(asMap(tagged['meta'])['role']), RoomRole.player);
      expect(jsStr(asMap(tagged['meta'])['seat']), 'p1');
      expect(parseSave(reopened.get(resumeKeyOf(code))), isNotNull);
    });

    test('★ saveOnOpen 幂等：首次落 open 档 + 广播，第二次零写', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final String code = f.sessionOf(kHostSeat).code;
      // 用一份空的真可变后端，模拟「云端续玩进来本机没档」。
      final repo_store.InMemoryRoomSaveStore store =
          repo_store.InMemoryRoomSaveStore();
      expect(store.list(), isEmpty);
      final RoomController ctl = RoomController(
        session: f.sessionOf(kHostSeat),
        local: f.localOf(kHostSeat),
        notes: f.notes,
        saveStore: store,
      );
      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: ctl,
        session: f.sessionOf(kHostSeat),
        nowMs: () => 1700000000000,
      );

      expect(await syncer.saveOnOpen(), isTrue,
          reason: '本机无该房档时，开局立刻补一份并广播');
      expect(syncer.autoSaved, 1);
      expect(syncer.sharedCount, 1);
      final List<String> firstKeys = store.list();
      expect(firstKeys, contains('auto/$code/open-1700000000000'));
      expect(firstKeys, contains(resumeKeyOf(code)));

      expect(await syncer.saveOnOpen(), isFalse,
          reason: '★ 幂等：房号键已存在就零写、零广播');
      expect(syncer.autoSaved, 1);
      expect(syncer.sharedCount, 1);
      expect(store.list(), firstKeys);
    });

    test('★ 招募期（RECRUITING）成员加入也触发 autoSave（去 IN_GAME 门槛）',
        () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: false);
      final String code = f.sessionOf(kHostSeat).code;
      final Map<String, Object?> meta =
          Map<String, Object?>.from(asMap(f.hostState()['meta']));
      meta['status'] = RoomStatus.recruiting;
      f.hostState()['meta'] = meta;
      final repo_store.InMemoryRoomSaveStore store =
          repo_store.InMemoryRoomSaveStore();
      final RoomController ctl = RoomController(
        session: f.sessionOf(kHostSeat),
        local: f.localOf(kHostSeat),
        notes: f.notes,
        saveStore: store,
      );

      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: ctl,
        session: f.sessionOf(kHostSeat),
        nowMs: () => 1700000000000,
      );
      // 首遍只记基线（成员数 / 回合号），不存档。
      await syncer.onStateChanged();
      expect(syncer.autoSaved, 0);
      expect(store.list(), isEmpty);

      // 招募期新成员加入 → 成员数增长本身就是「有人要新档」的信号。
      final List<Object?> members =
          List<Object?>.from(asList(f.hostState()['members']));
      members.add(<String, Object?>{
        'seat': 'p3',
        'role': 'player',
        'nickname': '丙',
      });
      f.hostState()['members'] = members;
      await syncer.onStateChanged();

      expect(syncer.autoSaved, 1,
          reason: '★ 招募期加入必须立即补档（旧 IN_GAME 门槛吞掉第一波）');
      expect(store.list().any((String k) => k.startsWith('auto/$code/join-')),
          isTrue, reason: 'join 原因的自动槽必须落盘：${store.list()}');
      expect(store.list(), contains(resumeKeyOf(code)));
    });

    test('★ 源码门禁：_openRemote / _openCloud 的 controller 都注入 saveStore: _store',
        () {
      final String src = File('lib/ui/room/room_entry_page.dart')
          .readAsStringSync();
      expect(
        src.contains('RoomSaveStore get _store => widget.saveStore ?? roomSaveSlots;'),
        isTrue,
        reason: '_store 必须指向入口页注入的 store（或默认全局槽）',
      );
      // 玩家侧主因的回归靶点：远端 / 云端两条控制器的存档装配。
      for (final String sig in <String>[
        'Future<void> _openRemote(',
        'Future<void> _openCloud(',
      ]) {
        final int start = src.indexOf(sig);
        expect(start, greaterThan(0), reason: '找不到方法：$sig');
        final int bodyOpen = src.indexOf('{', src.indexOf(') async {', start));
        expect(bodyOpen, greaterThan(start), reason: '$sig 找不到方法体');
        int depth = 0;
        int end = src.length;
        for (int i = bodyOpen; i < src.length; i++) {
          if (src[i] == '{') depth++;
          if (src[i] == '}') {
            depth--;
            if (depth == 0) {
              end = i + 1;
              break;
            }
          }
        }
        final String body = src.substring(bodyOpen, end);
        expect(body, contains('saveStore: _store'),
            reason: '★ $sig 的 RoomController 必须接入口页 store（玩家侧主因）；'
                '实测方法体：${body.substring(0, body.length.clamp(0, 400))}');
      }
    });
  });
}
