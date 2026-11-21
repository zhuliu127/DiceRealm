// ============================================================
// test/room_ui_roll_test.dart — P5/T05-B2b · 掷骰链路验收（T-60 ~ T-63）
//
// ★ 教训（P4 B1）：**只看 `sent` 会假绿** —— 意图发出去了不等于权威端真结算。
//   本文件因此一律以 `host.state` 为准：骰子条点了之后必须看到
//   `state.dice` 真长出一条带 `total` / `levelText` 的记录，
//   SAN 必须真的掉，暗骰必须真的不进公共账。
//
// 四条判据：
//   T-60 D100：`state.dice` 新增一条含 `total` + `levelText` 的记录
//              （不是「请求掷 1D100」那种日志）；`total ∈ 1..100`；
//              与 `CocRules` 的成功等级映射表 + 同种子复算一致。
//   T-61 SAN Check：该座位 `currentSAN` **实际下降**。
//   T-62 奖惩骰：`bonus` / `penalty` 两字段分开传，不传 net；
//              local 侧互斥（设奖励会清惩罚）。
//   T-63 暗骰：`state.dice` 零新增，本人与 KP 的 `privateBySeat` 各 +1。
//   另：旁观者骰子条禁用、点了零新增（T-05）。
//
// 铁律：T1 内存后端零 I/O；T5 `useRoomScreen`；T8 三视角各用自己那份 state。
// ★ 不用 `pumpAndSettle()`：夹具里 400ms 节流靠 `f.nowMs` 手动推进，
//   settle 会等一个永不结束的调度循环。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_rules.dart' show CocRules;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart'
    show GpDiceBar, GpDiceBarKeys;
import 'package:dice_realm/ui/room/sheets/sheet_san_check.dart'
    show SanCheckSheet, SanCheckSheetKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart' show DeterministicRoomRules;
import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 夹具
// ------------------------------------------------------------

Future<RoomUiFixture> _boot(WidgetTester tester) async {
  final RoomUiFixture f = RoomUiFixture();
  await f.boot(inGame: true);
  useRoomScreen(tester, 900, 900);
  return f;
}

/// 宿主：作用域挂在 Navigator 之上；内容装进可滚动容器，Wrap 子项全部建出。
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

/// `state.dice` 的当前条数。
int _diceCount(RoomUiFixture f) => asList(f.hostState()['dice']).length;

/// `state.dice` 的最后一条（不存在则 fail）。
Map<String, Object?> _lastDice(RoomUiFixture f) {
  final List<Object?> dice = asList(f.hostState()['dice']);
  expect(dice, isNotEmpty, reason: 'state.dice 是空的：权威端根本没结算这一掷');
  return asMap(dice.last);
}

/// 从子表里取整型 SAN（兼容两套来源），取不到返回 null。
///
/// harness 的成员有两套数值来源：`sheet.status.currentSAN`（分享卡里的
/// 正式状态）与 `runtime.san`（运行时累加）。谁先出现用谁。
int? _intOfStatus(Object? v) {
  final Map<String, Object?> m = asMap(v);
  for (final String key in <String>['currentSAN', 'san']) {
    final Object? raw = m[key];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
  }
  return null;
}

/// 该座位当前 SAN（从权威态取，避免跨视角裁剪干扰）。
int _sanOf(RoomUiFixture f, String seat) {
  for (final Object? m in asList(f.hostState()['members'])) {
    final Map<String, Object?> mem = asMap(m);
    if (jsStr(mem['seat']) != seat) continue;
    final int? fromSheet = _intOfStatus(asMap(mem['sheet'])['status']);
    if (fromSheet != null) return fromSheet;
    return _intOfStatus(mem['runtime']) ?? -1;
  }
  return -1;
}

/// `levelKey`（如 `regular`）→ 中文文案，用规则层两张静态表反查（真复算）。
String? _textOfLevelKey(String key) {
  for (final MapEntry<String, String> e in CocRules.LEVEL_KEY.entries) {
    if (e.value != key) continue;
    return CocRules.LEVEL_TEXT[e.key];
  }
  return null;
}

void main() {
  // ----------------------------------------------------------
  // T-60 D100
  // ----------------------------------------------------------
  group('T-60 D100 直投', () {
    testWidgets('点骰子条 → host.state 真长出一条带 total + levelText 的骰记录',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'p1', const GpDiceBar()));
      await tester.pump();

      final int before = _diceCount(f);
      final int logsBefore = asList(f.hostState()['logs']).length;

      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();

      // ① 权威态真长了一条（不是只有 sent）
      expect(_diceCount(f), before + 1, reason: 'state.dice 没有新增：这一掷没被结算');

      final Map<String, Object?> entry = _lastDice(f);
      // ② 带 total 与 levelText —— 而不是「请求掷 1D100」那种纯日志
      expect(entry.containsKey('total'), isTrue,
          reason: '骰记录没有 total：$entry');
      expect(jsStr(entry['levelText']).isNotEmpty, isTrue,
          reason: '骰记录没有 levelText：$entry');
      expect(jsStr(entry['expr']), '1D100');
      expect(jsStr(entry['seat']), 'p1');

      // ③ total 落在 1..100
      final Object? totalRaw = entry['total'];
      expect(totalRaw, isA<int>(), reason: 'total 不是整数：$totalRaw');
      final int total = totalRaw! as int;
      expect(total, inInclusiveRange(1, 100));

      // ④ 与规则层的成功等级映射表复算一致
      final String levelKey = jsStr(entry['level']);
      expect(levelKey, isNotEmpty, reason: '骰记录没有 level：$entry');
      expect(_textOfLevelKey(levelKey), isNotNull,
          reason: '$levelKey 不在 CocRules.LEVEL_KEY 里');
      expect(jsStr(entry['levelText']), _textOfLevelKey(levelKey),
          reason: 'levelText 与 levelKey 不匹配：$entry');

      // ⑤ 同种子复算：确定性规则替身（同一 seed 的第一个 check）应掷出同一个数
      final Map<String, Object?> replay =
          DeterministicRoomRules(seed: 1).check(<String, Object?>{
        'kind': 'skill',
        'base': 100,
        'difficulty': 'REGULAR',
        'bonus': 0,
        'penalty': 0,
      });
      expect(replay['value'], total,
          reason: '同种子（seed=1）复算出的骰值与权威端不一致：'
              'replay=${replay['value']} / host=$total');

      // ⑥ 这不是「请求掷 1D100」—— 那种走的是 log + kind=dice-request
      final List<Object?> logs = asList(f.hostState()['logs']);
      final int requestLogs = logs.where((Object? e) {
        final Map<String, Object?> log = asMap(e);
        return jsStr(log['kind']) == 'dice-request' ||
            jsStr(log['text']).contains('请求掷');
      }).length;
      expect(requestLogs, 0,
          reason: '直投走了「请求掷」分支（logs 从 $logsBefore 增至 ${logs.length}）：'
              '导语应当只在非 direct 分支出现');
    });

    testWidgets('同种子两局复算一致（确定性可复现，排除偶然通过）',
        (WidgetTester tester) async {
      final List<int> totals = <int>[];
      for (var round = 0; round < 2; round += 1) {
        final RoomUiFixture f = await _boot(tester);
        await tester.pumpWidget(_hostApp(f, 'p1', const GpDiceBar()));
        await tester.pump();
        await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
        await tester.pump();
        totals.add(_lastDice(f)['total']! as int);
      }
      expect(totals.first, totals.last,
          reason: '同一 seed 两局的 D100 结果不同：$totals（随机源没被钉死）');
    });
  });

  // ----------------------------------------------------------
  // T-61 SAN Check
  // ★ 2.37.0 / Q4 等价迁移：入口从骰子工具弹层迁到专用 SanCheckSheet，
  //   原用例的核心行为不变量（SAN 真下降 / 留骰 / 不串座）逐字保留。
  // ----------------------------------------------------------
  group('T-61 SAN Check', () {
    /// 打开专用 SAN 弹层，填合法表达式并提交（替代旧的骰子工具按钮点按）。
    Future<void> submitSan(WidgetTester tester, RoomUiFixture f) async {
      await tester.pumpWidget(_hostApp(f, 'p1', const SanCheckSheet()));
      await tester.pump();
      await tester.enterText(find.byKey(SanCheckSheetKeys.field), '2/1');
      await tester.pump();
      await tester.tap(find.byKey(SanCheckSheetKeys.submit));
      await tester.pump();
    }

    testWidgets('点 SAN Check → 该座位 currentSAN 实际下降', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final int before = _sanOf(f, 'p1');
      expect(before, greaterThan(0), reason: '前置：p1 应有可读的 currentSAN');

      await submitSan(tester, f);

      final int after = _sanOf(f, 'p1');
      expect(after, lessThan(before),
          reason: 'SAN 没有下降：before=$before after=$after');
      final List<Object?> dice = asList(f.hostState()['dice']);
      expect(dice, isNotEmpty, reason: 'SAN Check 应在 state.dice 留下这次百分骰');
    });

    testWidgets('SAN Check 只动本人，不动队友（跨座位串扰）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final int before1 = _sanOf(f, 'p1');
      final int before2 = _sanOf(f, 'p2');

      await submitSan(tester, f);

      expect(_sanOf(f, 'p1'), lessThan(before1), reason: 'p1 自己的 SAN 应下降');
      expect(_sanOf(f, 'p2'), before2, reason: 'p2 的 SAN 不该被 p1 的检定带动');
    });
  });

  // ----------------------------------------------------------
  // T-62 奖惩骰
  // ----------------------------------------------------------
  group('T-62 奖惩骰（两字段分开，不传 net）', () {
    testWidgets('奖励 ×3 → bonus:3 / penalty:0', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'p1', const GpDiceBar()));
      await tester.pump();

      for (var i = 0; i < 3; i += 1) {
        await tester.tap(find.byKey(GpDiceBarKeys.bonus));
        await tester.pump();
      }
      expect(f.localOf('p1').bonus, 3, reason: '本地态没累加到 3');
      expect(f.localOf('p1').penalty, 0, reason: '奖励骰不该动惩罚骰');

      f.clearSent();
      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();

      final Map<String, Object?>? wire = f.lastSent(op: 'dice');
      expect(wire, isNotNull, reason: '没发出 dice 意图');
      final Map<String, Object?> p = asMap(wire!['p']);
      expect(p['bonus'], 3, reason: 'bonus 不是 3：$p');
      expect(p['penalty'], 0, reason: 'penalty 不是 0：$p');
      // 「不传 net」：载荷里不许出现 net 这种已折算过的键
      expect(p.containsKey('net'), isFalse,
          reason: '载荷里出现了 net（应两字段分开传）：$p');
      // 权威态侧：奖励骰确实参与了结算（total 落在 1..100 且等级有文案）
      final Map<String, Object?> entry = _lastDice(f);
      expect(entry['total'], inInclusiveRange(1, 100));
      expect(jsStr(entry['levelText']).isNotEmpty, isTrue);
    });

    testWidgets('惩罚 ×1 → bonus:0 / penalty:1', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'p1', const GpDiceBar()));
      await tester.pump();

      await tester.tap(find.byKey(GpDiceBarKeys.penalty));
      await tester.pump();
      expect(f.localOf('p1').penalty, 1);
      expect(f.localOf('p1').bonus, 0, reason: '惩罚骰不该动奖励骰');

      f.clearSent();
      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();

      final Map<String, Object?> p = asMap(f.lastSent(op: 'dice')!['p']);
      expect(p['bonus'], 0, reason: 'bonus 不是 0：$p');
      expect(p['penalty'], 1, reason: 'penalty 不是 1：$p');
      expect(p.containsKey('net'), isFalse, reason: '载荷里出现了 net：$p');
    });

    testWidgets('奖惩骰互斥：先奖励 3 再点惩罚 1 次 → bonus 归零', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'p1', const GpDiceBar()));
      await tester.pump();

      for (var i = 0; i < 3; i += 1) {
        await tester.tap(find.byKey(GpDiceBarKeys.bonus));
        await tester.pump();
      }
      await tester.tap(find.byKey(GpDiceBarKeys.penalty));
      await tester.pump();

      expect(f.localOf('p1').bonus, 0, reason: '互斥失效：奖励骰没被清零');
      expect(f.localOf('p1').penalty, 1);
    });
  });

  // ----------------------------------------------------------
  // T-63 暗骰
  // ----------------------------------------------------------
  group('T-63 暗骰（B1-F1 分流语义）', () {
    testWidgets('暗骰 → state.dice 零新增，本人与 KP 的 privateBySeat 各 +1',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'p1', const GpDiceBar()));
      await tester.pump();

      final int diceBefore = _diceCount(f);
      final int selfBefore = f.host.privateBySeat['p1']?.length ?? 0;
      final int kpBefore = f.host.privateBySeat[kHostSeat]?.length ?? 0;

      // 打开暗骰开关
      await tester.tap(find.byKey(GpDiceBarKeys.dark));
      await tester.pump();
      expect(f.localOf('p1').darkRoll, isTrue, reason: '暗骰开关没打开');

      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();

      // ① 公共账零新增
      expect(_diceCount(f), diceBefore,
          reason: '暗骰进了公共 state.dice（B1-F1 破防）');
      // ② 本人 +1，KP +1
      expect(f.host.privateBySeat['p1']?.length ?? 0, selfBefore + 1,
          reason: '本人 privateBySeat 没有收到暗骰结果');
      expect(f.host.privateBySeat[kHostSeat]?.length ?? 0, kpBefore + 1,
          reason: 'KP privateBySeat 没有收到暗骰结果');
      // ③ 队友私密账不受影响
      expect(f.host.privateBySeat['p2']?.length ?? 0, 0,
          reason: 'p2 的私密账里出现了别人的暗骰');
      // ④ 私密记录里带骰值（不是一句空提示）
      final Object? last = f.host.privateBySeat['p1']!.last;
      expect(asMap(last).toString().contains('暗骰'), isTrue,
          reason: '私密记录没有暗骰内容：$last');
    });

    testWidgets('明骰仍进公共账（暗骰分流没把明骰带崩）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'p1', const GpDiceBar()));
      await tester.pump();
      await tester.tap(find.byKey(GpDiceBarKeys.dark)); // 开
      await tester.pump();
      await tester.tap(find.byKey(GpDiceBarKeys.dark)); // 关
      await tester.pump();
      expect(f.localOf('p1').darkRoll, isFalse);

      final int before = _diceCount(f);
      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();
      expect(_diceCount(f), before + 1, reason: '关掉暗骰后明骰没进公共账');
    });
  });

  // ----------------------------------------------------------
  // 旁观者
  // ----------------------------------------------------------
  group('旁观者（T-05：骰子条全禁用）', () {
    testWidgets('旁观者骰子条控件全禁用，点了 sent 零增加、state.dice 零新增',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, 'sp1', const GpDiceBar()));
      await tester.pump();

      // ① 结构上看得见，但一律禁用
      for (final Key key in <Key>[
        GpDiceBarKeys.bonus,
        GpDiceBarKeys.penalty,
        GpDiceBarKeys.expr('1D100'),
        GpDiceBarKeys.rollCustom,
        GpDiceBarKeys.dark,
      ]) {
        final Finder finder = find.byKey(key);
        expect(finder, findsOneWidget, reason: '旁观者应看到 $key（只是禁用）');
        expect(tester.widget<RoomTap>(finder).enabled, isFalse,
            reason: '旁观者的 $key 竟然可点');
      }
      // ② 能力型扩展按钮结构上就不渲染
      expect(find.byKey(const ValueKey<String>('act/combat.roll')), findsNothing);
      expect(find.byKey(const ValueKey<String>('act/check.opposed')), findsNothing);

      // ③ 真去点：sent 零增加、state.dice 零新增
      final int sentBefore = f.sent.length;
      final int diceBefore = _diceCount(f);
      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();
      await tester.tap(find.byKey(GpDiceBarKeys.bonus));
      await tester.pump();
      expect(f.sent.length, sentBefore,
          reason: '旁观者点骰子条竟然发出了意图：${f.sent.sublist(sentBefore)}');
      expect(_diceCount(f), diceBefore, reason: '旁观者竟然掷出了骰子');
    });
  });
}
