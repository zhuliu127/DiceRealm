// ============================================================
// test/p13_save_file_backend_test.dart — P13 T2 / SAVE-1 第 10 项
//
// 生产后端同款测试：真实 dart:io FileRoomSaveStore + 临时目录，
// 与内存后端行为比对。P22/P13 真机铁证表明「测试全绿、真机全丢」的
// 根因是内存/生产后端行为分叉，所以本文件**必须走真实文件后端**，
// 内存替身只作对照，不得反向替代。
//
// ★ 另把真机发现的边界钉死为中文自定义键被拒 + 房号键兜底：
//   isSafeKey 未放宽、isStructuredSlotKey 只放行 auto/share/<code>/<tail>，
//   任意中文槽名仍被拒且 lastError 可见（P13「消除静默失败」口径）。
// ============================================================

import 'dart:io' show Directory, Platform;

import 'package:dice_realm/domain/js_compat.dart' show asMap, jsStr;
import 'package:dice_realm/domain/room_model_save.dart' show parseSave;
import 'package:dice_realm/domain/room_types.dart' show kRoomPolicy, RoomEvt, RoomIntent;
import 'package:dice_realm/repo/file_room_save_store.dart'
    show FileRoomSaveStore;
import 'package:dice_realm/repo/room_save_store.dart'
    show InMemoryRoomSaveStore;
import 'package:flutter_test/flutter_test.dart';

const String _code = 'CWA694';

Map<String, Object?> _snapshot(String code, int savedAt) => <String, Object?>{
      'v': 2,
      'code': code,
      'savedAt': savedAt,
      'meta': <String, Object?>{
        'code': code,
        'name': '洋馆惊魂',
        'status': 'IN_GAME',
      },
      'members': <Object?>[
        <String, Object?>{'seat': 'host', 'role': 'kp'},
        <String, Object?>{'seat': 'p1', 'role': 'player'},
      ],
    };

void main() {
  late Directory dir;
  late FileRoomSaveStore file;
  late InMemoryRoomSaveStore mem;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('p13_save_backend_');
    file = FileRoomSaveStore(dir);
    mem = InMemoryRoomSaveStore();
  });

  tearDown(() async {
    await file.flush();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('A · 键白名单未放宽（P22/P13 现场机制零回退）', () {
    test('isSafeKey 仍只接受 [A-Za-z0-9_-]；三段结构化键由 isStructuredSlotKey 放行',
        () {
      expect(FileRoomSaveStore.isSafeKey(_code), isTrue);
      expect(FileRoomSaveStore.isSafeKey('$_code · 第1轮'), isFalse,
          reason: '中文/间隔号自定义键仍被拒（真机同样），房号键兜底');
      expect(FileRoomSaveStore.isSafeKey('auto/$_code/close-1'), isFalse);
      expect(FileRoomSaveStore.isSafeKey('share/$_code/latest'), isFalse);
      expect(FileRoomSaveStore.isSafeKey('../escape'), isFalse);
      expect(FileRoomSaveStore.isSafeKey('NUL'), isFalse);

      expect(FileRoomSaveStore.isStructuredSlotKey('auto/$_code/close-1'), isTrue);
      expect(FileRoomSaveStore.isStructuredSlotKey('share/$_code/latest'), isTrue);
      expect(FileRoomSaveStore.isStructuredSlotKey('$_code · 第1轮'), isFalse,
          reason: '任意中文名不在结构化豁免范围');
    });

    test('中文自定义槽键被拒且 lastError 可见；随后房号键仍可落盘（真机同款）', () async {
      file.put('$_code · 第1轮', _snapshot(_code, 1));
      expect(file.lastError, isNotNull,
          reason: 'P13 消除静默失败：拒写必须留下可见 lastError');
      expect(file.list(), isEmpty, reason: '非法键不得进 _mem/list');

      file.put(_code, _snapshot(_code, 2));
      expect(file.get(_code), isNotNull,
          reason: '房号键兜底必须成功（真机 BVTPTJ.json 668B→22258B）');
      await file.flush();
      expect(jsStr(asMap(parseSave(file.get(_code))!['meta'])['code']), _code);
    });
  });

  group('B · 生产文件后端与内存后端行为比对（SAVE-1 第 10 项）', () {
    test('同一组键：list/get/解析结果逐字一致（含 ~sk~ 编码三段键）', () async {
      const List<String> keys = <String>[
        _code,
        'auto/$_code/close-1794841858549',
        'auto/$_code/interval-1794841545099',
        'share/$_code/latest',
      ];
      for (var i = 0; i < keys.length; i++) {
        final Map<String, Object?> data = _snapshot(_code, 100 + i);
        file.put(keys[i], data);
        mem.put(keys[i], data);
      }
      await file.flush();

      final List<String> fl = file.list()..sort();
      final List<String> ml = mem.list()..sort();
      expect(fl, ml, reason: '★ 生产/内存后端 list 必须一致：$fl vs $ml');
      for (final String k in keys) {
        expect(jsStr(asMap(parseSave(file.get(k))!['meta'])['code']), _code);
        expect(file.get(k), mem.get(k), reason: '键 $k 的 get 结果必须一致');
      }
      // ~sk~<hex> 可逆编码文件确实存在（真机 room_saves 目录同款）。
      final List<String> names = dir
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();
      expect(names.any((String n) => n.startsWith('~sk~')), isTrue,
          reason: '三段结构化键必须编码成 ~sk~<hex>.json，实测 $names');
      expect(names.length, keys.length);
    });

    test('flush + loadSync 后仍可读（重进 App 档仍在，PRD 第 9 项）', () async {
      file.put('auto/$_code/end-1794842442075', _snapshot(_code, 42));
      file.put(_code, _snapshot(_code, 43));
      await file.flush();

      final FileRoomSaveStore reopened = FileRoomSaveStore(dir);
      expect(reopened.loadSync(), 2, reason: '两份都应落盘并可重载');
      expect(reopened.list(), contains(_code));
      expect(reopened.list(), contains('auto/$_code/end-1794842442075'));
      expect(
        jsStr(asMap(parseSave(reopened.get(_code))!['meta'])['code']),
        _code,
      );
      expect(reopened.lastError, isNull, reason: '干净重载不应有 lastError');
    });
  });

  group('C · 契约零漂移', () {
    test('62 / 28 / 13 不变，且 San Check 不新增协议', () {
      expect(kRoomPolicy.length, 62);
      expect(RoomEvt.values.length, 28);
      expect(RoomIntent.values.length, 13);
      expect(RoomIntent.values.contains(RoomIntent.sanCheck), isTrue);
    });
  });
}
