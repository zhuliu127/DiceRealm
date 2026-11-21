// ============================================================
// test/p12_gl1_file_key_test.dart — P12 / 第 9 期 · GL-1（第 2 层根因证伪）
//
// 用**生产** FileRoomSaveStore + 临时目录验证：
//   · 2.36.0：`auto/<code>/…`、`share/<code>/latest` 含 `/` → isSafeKey 拒写，
//     只有房号键（resumeKeyOf）能落盘 —— 这是 GL-1 的原始根因；
//   · ★ 2.37.0 / Q1：新增 `isStructuredSlotKey` 只放行这两种三段槽键，
//     编码成 `~sk~<hex>` 文件名真落盘；房号键仍照旧落盘作续玩锚点/兜底。
//     `list()/get()` 对外仍返回原始逻辑键，parseSave 可解、meta.code 可续玩。
//
// ★ 这是「删掉任何一条 put 就真红」的用例：若把 RoomSaveSyncer.autoSave /
//   onShared / RoomController.saveNow 里的 `put(resumeKeyOf(code))` 删掉，
//   本文件「房号键落档」断言必红；若把结构化槽键编码删掉，auto/share
//   「重开仍可见」断言必红。
// ★ FileRoomSaveStore.isSafeKey 白名单语义一字未改（路径穿越防线未放宽，
//   PRD §2.3 #8）；结构化键走独立判据，任意路径键照样拒写。
// ============================================================

import 'dart:io' show Directory;

import 'package:dice_realm/domain/js_compat.dart' show asMap, jsStr;
import 'package:dice_realm/domain/room_model_save.dart' show parseSave;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/repo/file_room_save_store.dart'
    show FileRoomSaveStore;
import 'package:dice_realm/ui/room/room_controller.dart' show RoomController;
import 'package:dice_realm/ui/room/room_save_syncer.dart'
    show RoomSaveSyncer, resumeKeyOf;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture;

const String _code = 'NU9E6R';

/// 一份最小合法快照（save.share / parseSave 都认 meta.code）。
Map<String, Object?> _snapshot(String code, int savedAt) => <String, Object?>{
      'v': 2,
      'code': code,
      'savedAt': savedAt,
      'meta': <String, Object?>{
        'code': code,
        'status': 'IN_GAME',
        'round': 3,
      },
      'members': <Object?>[
        <String, Object?>{'seat': kHostSeat, 'role': 'kp', 'nickname': 'KP'},
        <String, Object?>{'seat': 'p1', 'role': 'player', 'nickname': '甲'},
      ],
    };

/// 把一个 controller 指到生产文件后端（其余沿用夹具的 session / local / notes）。
RoomController _controllerWith(
  RoomUiFixture f,
  String seat,
  FileRoomSaveStore store,
) =>
    RoomController(
      session: f.sessionOf(seat),
      local: f.localOf(seat),
      notes: f.notes,
      saveStore: store,
    );

void main() {
  late Directory dir;
  late FileRoomSaveStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('p12_gl1_file_key_');
    store = FileRoomSaveStore(dir);
  });

  tearDown(() async {
    await store.flush();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // 临时目录清理失败不影响断言结果。
    }
  });

  group('A · isSafeKey 白名单未放宽（路径穿越防线）', () {
    test('isSafeKey 仍拒 auto/share（白名单未放宽）；结构化判据只认两段前缀', () {
      // ★ 白名单本身一个字没改：含 / 的键 isSafeKey 依旧 false。
      expect(FileRoomSaveStore.isSafeKey('auto/$_code/close-1'), isFalse,
          reason: '★ isSafeKey 白名单语义未改（但结构化键由 isStructuredSlotKey 放行落盘）');
      expect(FileRoomSaveStore.isSafeKey('share/$_code/latest'), isFalse,
          reason: '★ isSafeKey 白名单语义未改（但结构化键由 isStructuredSlotKey 放行落盘）');
      expect(FileRoomSaveStore.isSafeKey('$_code'), isTrue,
          reason: '房号本身是 6 位大写字母数字，天然合法');
      expect(FileRoomSaveStore.isSafeKey('$_code · 第3轮'), isFalse,
          reason: '含中文/空格/间隔号的自定义槽名必须被拒');
      expect(FileRoomSaveStore.isSafeKey('../escape'), isFalse);
      expect(FileRoomSaveStore.isSafeKey(''), isFalse);
      expect(FileRoomSaveStore.isSafeKey('NUL'), isFalse,
          reason: 'Windows 保留设备名仍被拒');

      // ★ 2.37.0 新增：只放行 syncer 真正用的三段 auto/ share/ 槽。
      expect(FileRoomSaveStore.isStructuredSlotKey('auto/$_code/close-1'), isTrue);
      expect(FileRoomSaveStore.isStructuredSlotKey('share/$_code/latest'), isTrue);
      expect(FileRoomSaveStore.isStructuredSlotKey('../escape/x'), isFalse,
          reason: '路径穿越键绝不能被结构化判据放行');
      expect(FileRoomSaveStore.isStructuredSlotKey('auto/../x'), isFalse);
    });

    test('resumeKeyOf：trim + 大写归一（云端小写房号不产生第二条）', () {
      expect(resumeKeyOf(_code), _code);
      expect(resumeKeyOf('nu9e6r'), _code);
      expect(resumeKeyOf('  nu9e6r  '), _code);
      expect(FileRoomSaveStore.isSafeKey(resumeKeyOf(' nu9e6r ')), isTrue);
    });
  });

  group('B · 三条落盘路径在文件后端都留下 auto/ share/ 槽 + 房号键（改动前真红）', () {
    test('KP autoSave（结束房间）：auto/ 槽可落盘，房号键仍在且可解析', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(code: _code, inGame: true);
      final RoomController ctl = _controllerWith(f, kHostSeat, store);
      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: ctl,
        session: f.sessionOf(kHostSeat),
        nowMs: () => 1700000000000,
      );

      final bool ok = await syncer.autoSave(reason: 'close');
      expect(ok, isTrue, reason: 'KP 自动存档应成功，lastError=${syncer.lastError}');

      final List<String> keys = store.list();
      expect(keys.any((String k) => k.startsWith('auto/$_code/')), isTrue,
          reason: '★ 2.37.0：auto/ 结构化槽键现在能落盘、list() 对外返回逻辑键：$keys');
      expect(keys, contains(resumeKeyOf(_code)),
          reason: '★ 续玩可见的房号键仍然必须落盘（删掉它就是 GL-1 根因）：$keys');

      final Map<String, Object?>? parsed = parseSave(store.get(_code));
      expect(parsed, isNotNull, reason: '房号键存档必须能被 parseSave 解析');
      expect(jsStr(asMap(parsed!['meta'])['code']), _code,
          reason: 'parseSave 后 meta.code 必须是房号');
    });

    test('玩家 onShared：share/ 槽可落盘，tagged 房号键仍在且带本机视角标记', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(code: _code, inGame: true);
      final RoomController ctl = _controllerWith(f, 'p1', store);
      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: ctl,
        session: f.sessionOf('p1'),
        nowMs: () => 1700000000000,
      );

      await syncer.onShared(_snapshot(_code, 200));
      final List<String> keys = store.list();
      expect(keys, contains('share/$_code/latest'),
          reason: '★ 2.37.0：玩家收档 share/ 结构化槽键必须真落盘：$keys');
      expect(keys, contains(resumeKeyOf(_code)),
          reason: '★ 玩家端同样必须落房号键，才能进续玩列表：$keys');

      final Map<String, Object?>? parsed = parseSave(store.get(_code));
      expect(parsed, isNotNull);
      expect(jsStr(asMap(parsed!['meta'])['code']), _code);
      // _tagSave 的 meta.role/seat 一个都不能丢（P16 续玩落点靠它）。
      expect(asMap(parsed['meta'])['role'], isNotNull,
          reason: '玩家端存档必须带 meta.role');
      expect(asMap(parsed['meta'])['seat'], isNotNull,
          reason: '玩家端存档必须带 meta.seat');
    });

    test('存档槽保存：中文自定义名被拒，房号键兜底仍可续玩', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(code: _code, inGame: true);
      final RoomController ctl = _controllerWith(f, kHostSeat, store);

      final bool ok = await ctl.saveNow(name: '$_code · 第3轮');
      expect(ok, isTrue, reason: 'saveNow 应返回成功');
      final List<String> keys = store.list();
      expect(keys.any((String k) => k.contains('第3轮')), isFalse,
          reason: '中文槽名必须被 isSafeKey 拒写：$keys');
      expect(keys, contains(resumeKeyOf(_code)),
          reason: '★ saveNow 必须额外落一份房号键（存档槽路径的 GL-1 兜底）：$keys');
      expect(jsStr(asMap(parseSave(store.get(_code))!['meta'])['code']), _code);
    });
  });

  group('C · 真落盘：flush 后 loadSync 仍能列出 auto/ share/ + 房号键', () {
    test('三条槽写盘后重建 FileRoomSaveStore 全部读得到（不是只在内存里）', () async {
      store.put('auto/$_code/close-1', _snapshot(_code, 1));
      store.put('share/$_code/latest', _snapshot(_code, 2));
      store.put(resumeKeyOf(_code), _snapshot(_code, 3));
      await store.flush();

      final FileRoomSaveStore reopened = FileRoomSaveStore(dir);
      expect(reopened.loadSync(), 3,
          reason: '★ 2.37.0：auto/ share/ 经结构化编码落盘，三条都该读回');
      final List<String> keys = reopened.list();
      expect(keys, <String>[_code, 'auto/$_code/close-1', 'share/$_code/latest'],
          reason: '★ 重开后逻辑键原样可见（不是 ~sk~ 文件名）：$keys');
      expect(jsStr(asMap(parseSave(reopened.get(_code))!['meta'])['code']), _code);
      expect(jsStr(asMap(parseSave(reopened.get('auto/$_code/close-1'))!['meta'])['code']), _code);
      expect(jsStr(asMap(parseSave(reopened.get('share/$_code/latest'))!['meta'])['code']), _code);
      expect(reopened.isLoaded, isTrue);
    });
  });
}
