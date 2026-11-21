// ============================================================
// test/room_ui_save_test.dart — P5/T05-B2b · K4 旧存档脱敏 + 存档槽
//
// 五条判据：
//   ① K4 脱敏：造一份含明文秘密检定行的旧存档 → `openSave` → 权威态
//      `logs` 里不再有明文（改写为 `seat:''` + `redacted:true` 的合规行）；
//   ② 幂等：把已迁移的存档再导入一次，迁移条数 == 0；
//   ③ 一次性提示：「已自动脱敏 N 条」在迁移 > 0 时出现**恰好一次**，
//      迁移 == 0 的第二次导入**不再提示**；
//   ④ 深拷贝边界：`put` 侧别名、`get` 侧别名都改不到仓库存的那份，
//      且 `identical(get(), get()) == false`；
//   ⑤ `remove` / `clear` 属 `RoomSaveStoreMutable` 的扩展能力：
//      可变后端下删除按钮渲染，纯端口后端下 `findsNothing` 并给出说明。
//
// 铁律：T1 全内存后端（`InMemoryRoomSaveStore`，零文件读写）；
//      T5 `useRoomScreen`；T6 提示条数按 notice 发射次数数，不看文案猜。
// ★ 本文件**不碰**真实文件系统：`FileRoomSaveStore` 属后续期，这里不引入。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
// `RoomHost.save()` 是扩展方法，必须把扩展所在库带进作用域
import 'package:dice_realm/domain/room_model_save.dart' show RoomHostSave;
import 'package:dice_realm/domain/room_ports.dart' show RoomSaveStore;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/repo/room_save_store.dart' as repo_save
    show InMemoryRoomSaveStore, RoomSaveStoreMutable;
import 'package:dice_realm/ui/room/sheets/sheet_save_slots.dart'
    show SaveSlotsKeys, SaveSlotsSheet;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 夹具与工具
// ------------------------------------------------------------

Future<RoomUiFixture> _boot(WidgetTester tester) async {
  final RoomUiFixture f = RoomUiFixture();
  await f.boot(inGame: true);
  useRoomScreen(tester, 900, 1200);
  return f;
}

Widget _hostApp(RoomUiFixture f, String seat, Widget body) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => f.scoped(
      seat,
      child: child ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: SingleChildScrollView(child: body)),
  );
}

/// 明文标记：迁移后必须**整串消失**。
const String kPlainMarker = '隐藏线索在书架夹层';

/// 造一份「旧版 Q1 缺陷重放产物」的存档：从当前权威态存档出发，
/// 往 `logs` 里塞一条明文秘密检定行（`kind:check` / `opp` 缺省 / `seat` 非空）。
Map<String, Object?> legacySaveWithPlaintext(RoomUiFixture f) {
  final Map<String, Object?> save = f.host.save();
  final List<Object?> logs = asList(save['logs']);
  logs.add(<String, Object?>{
    'seq': 9001,
    'seat': 'p1',
    'nickname': '玩家1',
    'kind': 'check',
    'text': 'p1 的秘密检定（侦查 70）：$kPlainMarker',
    'at': 1,
  });
  save['logs'] = logs;
  return save;
}

/// 权威态 `logs` 里是否还有明文标记。
bool hasPlaintext(RoomUiFixture f) =>
    f.hostState()['logs'].toString().contains(kPlainMarker);

/// 权威态 `logs` 里合规脱敏行的条数。
int redactedRows(RoomUiFixture f) {
  var n = 0;
  for (final Object? e in asList(f.hostState()['logs'])) {
    final Map<String, Object?> row = asMap(e);
    if (row['redacted'] == true && jsStr(row['seat']).isEmpty) n += 1;
  }
  return n;
}

/// 纯端口存档后端：只实现 `RoomSaveStore` 的 put / get / list。
///
/// 刻意**不**实现 `RoomSaveStoreMutable` —— 用来验证「后端不支持删时，
/// 界面不渲染删除按钮」这条能力边界（不是靠运行时置灰）。
class PurePortSaveStore implements RoomSaveStore {
  PurePortSaveStore([Map<String, Map<String, Object?>>? seed])
      : _byCode = seed ?? <String, Map<String, Object?>>{};

  final Map<String, Map<String, Object?>> _byCode;

  @override
  void put(String code, Map<String, Object?> data) {
    _byCode[code] = <String, Object?>{...data};
  }

  @override
  Map<String, Object?>? get(String code) {
    final Map<String, Object?>? hit = _byCode[code];
    return hit == null ? null : <String, Object?>{...hit};
  }

  @override
  List<String> list() => _byCode.keys.toList();
}

void main() {
  // ----------------------------------------------------------
  // ① K4 脱敏
  // ----------------------------------------------------------
  group('K4 旧存档明文脱敏', () {
    testWidgets('含明文秘密检定的旧存档 → 导入后权威态无明文',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final Map<String, Object?> legacy = legacySaveWithPlaintext(f);
      expect(legacy.toString().contains(kPlainMarker), isTrue,
          reason: '前置：构造的旧存档里必须有明文');

      final int before = redactedRows(f);
      final result =
          await f.controllerOf(kHostSeat).openSave(legacy);

      expect(result.migrated, 1, reason: '应命中 1 条明文行');
      expect(result.changed, isTrue);
      expect(hasPlaintext(f), isFalse,
          reason: '导入后权威态 logs 里还有明文：${f.hostState()['logs']}');
      expect(redactedRows(f), before + 1,
          reason: '没有生成合规脱敏行（seat:"" + redacted:true）');
    });

    testWidgets('迁移是深拷贝：入参存档本身不被改写', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final Map<String, Object?> legacy = legacySaveWithPlaintext(f);
      await f.controllerOf(kHostSeat).openSave(legacy);
      expect(legacy.toString().contains(kPlainMarker), isTrue,
          reason: '迁移把调用方传进来的那份也改了（应只改深拷贝副本）');
    });

    testWidgets('公开检定（有 opp 字段）不误伤', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final Map<String, Object?> save = f.host.save();
      asList(save['logs']).add(<String, Object?>{
        'seq': 9002,
        'seat': 'p1',
        'kind': 'check',
        'opp': 'npc_1',
        'text': '对抗检定 $kPlainMarker',
        'at': 1,
      });
      save['logs'] = asList(save['logs']);
      final result = await f.controllerOf(kHostSeat).openSave(save);
      expect(result.migrated, 0, reason: '带 opp 的公开检定不该被脱敏');
    });
  });

  // ----------------------------------------------------------
  // ② 幂等 + ③ 一次性提示
  // ----------------------------------------------------------
  group('迁移幂等与一次性提示', () {
    testWidgets('已迁移存档再导入 → 迁移条数 0，且不再提示',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);

      // 用 notice 发射次数当「出现几次」的判据（文案相同也算两次）。
      final List<String> notices = <String>[];
      f.sessionOf(kHostSeat).onNotice = notices.add;

      final Map<String, Object?> legacy = legacySaveWithPlaintext(f);
      final first = await f.controllerOf(kHostSeat).openSave(legacy);
      expect(first.migrated, 1);
      expect(notices.length, 1, reason: '第一次迁移应提示一次：$notices');
      expect(notices.single.contains('已自动脱敏'), isTrue,
          reason: '提示文案不对：${notices.single}');
      expect(notices.single.contains('1 条'), isTrue,
          reason: '提示里应带条数：${notices.single}');
      expect(f.localOf(kHostSeat).notice, notices.single,
          reason: '提示没有落到 local（块级 banner 拿不到）');

      // 幂等：把迁移后的那份（等价于再导出一遍）重新导入
      final Map<String, Object?> migratedSave = f.host.save();
      final second = await f.controllerOf(kHostSeat).openSave(migratedSave);
      expect(second.migrated, 0, reason: '第二次导入不该再迁移');
      expect(second.changed, isFalse);
      expect(notices.length, 1,
          reason: '迁移为 0 时不该再提示（一次性）：$notices');
      expect(hasPlaintext(f), isFalse);
    });
  });

  // ----------------------------------------------------------
  // ④ 深拷贝边界
  // ----------------------------------------------------------
  group('存档后端深拷贝边界', () {
    test('put 侧别名改不到仓库存的那份', () {
      final repo_save.InMemoryRoomSaveStore store =
          repo_save.InMemoryRoomSaveStore();
      final Map<String, Object?> data = <String, Object?>{
        'meta': <String, Object?>{'name': '原值'},
      };
      store.put('room1', data);

      // 写入后改入参（别名穿透）
      data['meta'] = <String, Object?>{'name': '被改了'};
      expect(asMap(store.get('room1')!['meta'])['name'], '原值',
          reason: 'put 没有深拷贝：入参与仓库是同一个引用');

      // 写入后改嵌套子表
      final Map<String, Object?> nested = <String, Object?>{'name': '再改'};
      data['meta'] = nested;
      expect(asMap(store.get('room1')!['meta'])['name'], '原值',
          reason: 'put 的嵌套表也没被隔离');
    });

    test('get 侧别名改不到仓库存的那份', () {
      final repo_save.InMemoryRoomSaveStore store =
          repo_save.InMemoryRoomSaveStore();
      store.put('room1', <String, Object?>{
        'meta': <String, Object?>{'name': '原值'},
      });

      final Map<String, Object?> read = store.get('room1')!;
      read['meta'] = <String, Object?>{'name': '从返回体改的'};
      asMap(read)['x'] = 1;
      expect(asMap(store.get('room1')!['meta'])['name'], '原值',
          reason: 'get 没有深拷贝：返回体与仓库是同一个引用');
      expect(store.get('room1')!.containsKey('x'), isFalse);
    });

    test('identical(get(), get()) == false', () {
      final repo_save.InMemoryRoomSaveStore store =
          repo_save.InMemoryRoomSaveStore();
      store.put('room1', <String, Object?>{'a': 1});
      expect(identical(store.get('room1'), store.get('room1')), isFalse,
          reason: '两次 get 返回了同一个引用（不是深拷贝）');
    });
  });

  // ----------------------------------------------------------
  // ⑤ remove / clear 的能力边界
  // ----------------------------------------------------------
  group('删除能力边界（RoomSaveStoreMutable）', () {
    test('可变后端：remove / clear 真的生效', () {
      final repo_save.InMemoryRoomSaveStore store =
          repo_save.InMemoryRoomSaveStore();
      expect(store, isA<repo_save.RoomSaveStoreMutable>());
      store.put('a', <String, Object?>{'v': 1});
      store.put('b', <String, Object?>{'v': 2});
      expect(store.list().length, 2);
      expect(store.remove('a'), isTrue);
      expect(store.remove('a'), isFalse, reason: '重复删同一个槽应返回 false');
      expect(store.list(), <String>['b']);
      store.clear();
      expect(store.list(), isEmpty);
    });

    testWidgets('可变后端下删除按钮渲染；纯端口后端下 findsNothing',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final Map<String, Object?> save = f.host.save();

      // ---- 可变后端 ----
      final repo_save.InMemoryRoomSaveStore mutable =
          repo_save.InMemoryRoomSaveStore();
      mutable.put('slotA', save);
      await tester.pumpWidget(_hostApp(
        f,
        kHostSeat,
        SaveSlotsSheet(store: mutable),
      ));
      await tester.pump();
      expect(find.byKey(SaveSlotsKeys.row('slotA')), findsOneWidget);
      expect(find.byKey(SaveSlotsKeys.load('slotA')), findsOneWidget);
      expect(find.byKey(SaveSlotsKeys.remove('slotA')), findsOneWidget,
          reason: '可变后端下应渲染删除按钮');

      // ---- 纯端口后端（不可变）----
      final PurePortSaveStore pure =
          PurePortSaveStore(<String, Map<String, Object?>>{'slotA': save});
      await tester.pumpWidget(_hostApp(
        f,
        kHostSeat,
        SaveSlotsSheet(store: pure),
      ));
      await tester.pump();
      expect(find.byKey(SaveSlotsKeys.row('slotA')), findsOneWidget);
      expect(find.byKey(SaveSlotsKeys.load('slotA')), findsOneWidget);
      expect(find.byKey(SaveSlotsKeys.remove('slotA')), findsNothing,
          reason: '纯端口后端下删除按钮必须 findsNothing（能力边界在结构上）');
      expect(find.textContaining('不支持删除'), findsOneWidget,
          reason: '不渲染删除按钮时应给出说明文案');
    });

    testWidgets('可变后端下点了删除，槽真的消失（一次点击 + 确认两段）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final repo_save.InMemoryRoomSaveStore mutable =
          repo_save.InMemoryRoomSaveStore();
      mutable.put('slotA', f.host.save());
      await tester.pumpWidget(_hostApp(
        f,
        kHostSeat,
        SaveSlotsSheet(store: mutable),
      ));
      await tester.pump();

      // ConfirmTwice：第一下只「上膛」，第二下才真删。
      await tester.tap(find.byKey(SaveSlotsKeys.remove('slotA')));
      await tester.pump();
      expect(mutable.list(), <String>['slotA'], reason: '第一下不该真删');

      await tester.tap(find.byKey(SaveSlotsKeys.remove('slotA')));
      await tester.pump();
      expect(mutable.list(), isEmpty, reason: '第二下应真删');
      expect(find.byKey(SaveSlotsKeys.row('slotA')), findsNothing);
    });
  });
}
