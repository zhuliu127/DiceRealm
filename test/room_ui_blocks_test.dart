// ============================================================
// test/room_ui_blocks_test.dart — P5/T03 S3.1 / S3.4 / S3.5 块级验收
//
// 铁律：T1（全内存后端）、T5（按真实档位 pump 块）、T6（断言权威侧 / sent）、
//      T8（跨视角用 stateOf 建的会话）、T7（KP 本地态走 hostRead，不在 state 里找）。
//
// 覆盖：
//   · 骰子条：奖惩骰互斥（走**发出的 intent 载荷**）/ 上限 5 / 暗骰 secret /
//     自定义骰式 / 旁观全禁用 / 客户端不自算结果 / 扩展按钮按角色渲染；
//   · 战斗列表：`hpPublic==false` → 「隐藏」、`hpMax>0` 判活守卫、
//     玩家侧不渲染「下一个行动」、请求卡同意/拒绝；
//   · 状态条：KP 空态 + 请求卡同意链、PL 空态；
//   · 素材舞台：`MapStageController` 六成员状态机、归一化坐标纯函数、
//     标点落点 / 画笔一次下发 / 只读不落点。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList;
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_controller.dart' show RoomGate;
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/widgets/gp_combat_list.dart';
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart';
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart';
import 'package:dice_realm/ui/room/widgets/gp_status.dart';
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 块的独立宿主：MaterialApp + RoomScope + Scaffold（同 feeds 测试）。
Widget _host(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: f.scoped(seat, child: child),
        ),
      ),
    );

/// 最近一条某 op 的 intent 载荷。
Map<String, Object?>? _lastP(RoomUiFixture f, String op) {
  for (var i = f.sent.length - 1; i >= 0; i--) {
    final e = f.sent[i];
    if (e['op'] == op) return (e['p']! as Map).cast<String, Object?>();
  }
  return null;
}

/// 用 `adoptSave` 灌一份指定 combat 的存档（比伪造事件更接近真实数据形状）。
Future<void> _seedCombat(
  RoomUiFixture f,
  Map<String, Object?> combat,
) async {
  final save = f.host.save();
  save['combat'] = combat;
  f.host.adoptSave(save);
  for (final seat in f.clientSeats) {
    await f.kpSession.pullSync(seat);
  }
}

/// 一份含三种「HP 可见性」形状的战斗顺序表。
Map<String, Object?> _combatFixture() => <String, Object?>{
      'round': 3,
      'turn': 0,
      'order': <Object?>[
        <String, Object?>{
          'id': 'a1',
          'name': '甲的调查员',
          'kind': 'player',
          'seat': 'p1',
          'totalSlots': 1,
          'public': <String, Object?>{
            'hpPublic': true,
            'hp': 10,
            'hpMax': 12,
            'state': '正常',
          },
        },
        <String, Object?>{
          'id': 'm1',
          'name': '深潜者',
          'kind': 'monster',
          'seat': '',
          'totalSlots': 1,
          // 玩家看不到 HP；KP 侧靠 secret 补全
          'public': <String, Object?>{'hpPublic': false},
          'secret': <String, Object?>{'hp': 30, 'hpMax': 30},
        },
        <String, Object?>{
          'id': 'm2',
          'name': '未初始化怪',
          'kind': 'monster',
          'seat': '',
          'totalSlots': 1,
          // hp = 0 但 hpMax = 0：**不许**判死（S5 守卫）
          'public': <String, Object?>{
            'hpPublic': true,
            'hp': 0,
            'hpMax': 0,
            'state': '正常',
          },
        },
      ],
    };

void main() {
  group('S3.5 · 骰子条', () {
    testWidgets('★ 奖惩骰互斥：走发出的 intent 载荷断言（不是 UI 数字）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpDiceBar()));
      await tester.pump();
      f.clearSent();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(GpDiceBarKeys.bonus));
        await tester.pump();
      }
      await tester.tap(find.byKey(GpDiceBarKeys.penalty));
      await tester.pump();
      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();

      final p = _lastP(f, RoomIntent.dice);
      expect(p, isNotNull);
      expect(p!['expr'], '1D100');
      expect(p['direct'], isTrue, reason: '直接掷必须带 direct:true（B1 分流）');
      expect(p['bonus'], 0, reason: '★ 惩罚骰一落地，奖励骰必须归 0');
      expect(p['penalty'], 1);
      expect(p.containsKey('secret'), isFalse, reason: '没开暗骰时不带 secret 键');
    });

    testWidgets('上限 5：连点 7 次也只到 5（夹取在 RoomUiLocal 一处实现）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpDiceBar()));
      await tester.pump();
      f.clearSent();

      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(GpDiceBarKeys.bonus));
        await tester.pump();
      }
      expect(f.localOf(kHostSeat).bonus, 5);

      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();
      expect(_lastP(f, RoomIntent.dice)!['bonus'], 5);
      expect(_lastP(f, RoomIntent.dice)!['penalty'], 0);
    });

    testWidgets('★ 暗骰：发 secret:true，且结果只进私有账（不进公共骰栏）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpDiceBar()));
      await tester.pump();
      f.clearSent();

      await tester.tap(find.byKey(GpDiceBarKeys.dark));
      await tester.pump();
      expect(f.localOf(kHostSeat).darkRoll, isTrue);

      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();

      expect(_lastP(f, RoomIntent.dice)!['secret'], isTrue);
      expect(f.hostState()['dice']! as List<Object?>, isEmpty);
      expect(f.host.privateBySeat[kHostSeat], isNotEmpty);
      // ★ 公共侧只允许一句脱敏提示（权威端就是这么写的），不得有骰值明细。
      final p2 = f.stateOf('p2');
      expect(asList(p2['dice']), isEmpty, reason: '暗骰不进公共骰栏');
      expect(asList(p2['privates']), isEmpty, reason: '他人收不到私密事件');
      final p2State = p2.toString();
      expect(p2State.contains('结果只有他/她与 KP 可见'), isTrue,
          reason: '公共侧只有脱敏提示');
      expect(p2State.contains('1D100 →'), isFalse,
          reason: '★ 不得出现骰值明细（T8：p2 真收到的裁剪态）');
    });

    testWidgets('公开骰进公共栏（对照组：不开暗骰时 dice 有内容）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpDiceBar()));
      await tester.pump();

      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();
      expect(f.hostState()['dice']! as List<Object?>, hasLength(1));
      expect(f.stateOf('p2')['dice']! as List<Object?>, hasLength(1),
          reason: '公开骰必须广播到玩家视图');
    });

    testWidgets('客户端不自算结果：载荷里没有 result / total / rolls',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpDiceBar()));
      await tester.pump();
      f.clearSent();

      // ★ P10 第 7 期：D6 已收进「其他骰子」弹窗；先打开弹窗再点。
      await tester.tap(find.byKey(GpDiceBarKeys.otherDice));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D6')));
      await tester.pump();

      final p = _lastP(f, RoomIntent.dice)!;
      for (final banned in <String>['result', 'total', 'rolls', 'value']) {
        expect(p.containsKey(banned), isFalse,
            reason: '客户端不得自报 $banned（F4 的同一保证）');
      }
    });

    testWidgets('自定义骰式：输入什么就发什么；空表达式不发包',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpDiceBar()));
      await tester.pump();
      f.clearSent();

      await tester.enterText(find.byKey(GpDiceBarKeys.customExpr), '3D6+1');
      await tester.tap(find.byKey(GpDiceBarKeys.rollCustom));
      await tester.pump();
      expect(_lastP(f, RoomIntent.dice)!['expr'], '3D6+1');

      await tester.enterText(find.byKey(GpDiceBarKeys.customExpr), '   ');
      await tester.tap(find.byKey(GpDiceBarKeys.rollCustom));
      await tester.pump();
      expect(_lastP(f, RoomIntent.dice)!['expr'], '3D6+1', reason: '空表达式不发新包');
    });

    testWidgets('★ 旁观者：骰子条全部禁用，且 POLICY 不允许的按钮不渲染（T-05 / T-22）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, 'sp1', const GpDiceBar()));
      await tester.pump();
      f.clearSent();

      final keys = <Key>[
        GpDiceBarKeys.bonus,
        GpDiceBarKeys.penalty,
        GpDiceBarKeys.dark,
        GpDiceBarKeys.rollCustom,
        // ★ P10 第 7 期：工具栏只留 D100；其余骰式在「其他骰子」弹窗里。
        GpDiceBarKeys.expr(kDiceExprs.first),
        GpDiceBarKeys.otherDice,
      ];
      for (final k in keys) {
        final tap = tester.widget<RoomTap>(find.byKey(k));
        expect(tap.enabled, isFalse, reason: '旁观者侧 $k 必须禁用');
      }
      // 旁观者既无 combat.roll 也无 check.opposed 权限 → 结构上不渲染
      expect(find.byKey(RoomKeys.action('combat.roll')), findsNothing);
      expect(find.byKey(RoomKeys.action('check.opposed')), findsNothing);

      await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
      await tester.pump();
      expect(f.sent, isEmpty, reason: '禁用按钮点了不能出载荷');
    });

    testWidgets('★ 扩展按钮：结构渲染 == 允许且非 KP-only，enabled == POLICY（三角色）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      const ops = <String>['combat.roll', 'check.opposed'];
      // ★ R1（2.34.0 / PV-1b）：`check.opposed` 是本期唯一「权限放宽但渲染仍 KP-only」
      //   的 op（`gp_dice_bar.dart` 渲染条件 `if (isKp && gate.can(...))`）。
      //   因此把旧假设「有权限 ⇒ 必渲染」拆成两层：结构渲染 vs 权限。
      const Set<String> structuralKpOnly = <String>{'check.opposed'};
      for (final entry in <String, String>{
        kHostSeat: RoomRole.kp,
        'p1': RoomRole.player,
        'sp1': RoomRole.spectator,
      }.entries) {
        await tester.pumpWidget(_host(f, entry.key, const GpDiceBar()));
        await tester.pump();
        for (final op in ops) {
          final Finder finder = find.byKey(RoomKeys.action(op));
          final bool allowed = RoomGate(entry.value).can(op);
          final bool kp = entry.value == RoomRole.kp;
          final bool renders = allowed && (!structuralKpOnly.contains(op) || kp);
          if (!renders) {
            expect(finder, findsNothing,
                reason: '${entry.value} / $op → 结构上不渲染');
            // ★ 新增正向：玩家对 check.opposed「有权限但不渲染」，
            //   证明这是结构门控（R1）而不是没权限（比旧断言更强）。
            if (op == 'check.opposed' && entry.value == RoomRole.player) {
              expect(allowed, isTrue,
                  reason: 'PV-1b：玩家确有该权限，只是骰子条入口 KP-only');
            }
            continue;
          }
          final RoomTap tap = tester.widget<RoomTap>(finder);
          expect(tap.enabled, allowed,
              reason: '${entry.value} / $op 可点性与 POLICY 漂移');
        }
      }
    });
  });

  group('S3.4 · 战斗列表', () {
    testWidgets('玩家侧：hpPublic==false 显示「隐藏」；KP 侧被 secret 补全',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await _seedCombat(f, _combatFixture());

      // 玩家侧（T8：p1 真收到的裁剪态）
      await tester.pumpWidget(_host(f, 'p1', const GpCombatList()));
      await tester.pump();
      expect(find.byKey(GpCombatKeys.list), findsOneWidget);
      final playerText = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .join('\n');
      // ★ P13 COMBAT-1：玩家侧怪物只显名字（不再有「HP 隐藏」占位）。
      //   核心不变量「玩家不得看到怪物真实 HP」逐字保留 + 新增名字可见断言。
      expect(playerText.contains('深潜者'), isTrue,
          reason: '★ 玩家侧应看到参战怪物名字（COMBAT-1）');
      expect(playerText.contains('HP '), isFalse,
          reason: '★ 产品真变：玩家侧怪物不再显示 HP 字样');
      expect(playerText.contains('30 / 30'), isFalse, reason: '★ 玩家不得看到怪物真实 HP');

      // KP 侧：secret 里的 HP 被补全
      await tester.pumpWidget(_host(f, kHostSeat, const GpCombatList()));
      await tester.pump();
      final kpText = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .join('\n');
      expect(kpText.contains('30 / 30'), isTrue, reason: 'KP 侧补全真实 HP');
    });

    testWidgets('★ hpMax == 0 守卫：hp=0 但上限未知的单位不判「已倒下」',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await _seedCombat(f, _combatFixture());

      await tester.pumpWidget(_host(f, kHostSeat, const GpCombatList(height: 240)));
      await tester.pump();

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .join('\n');
      expect(text.contains('未初始化怪'), isTrue);
      expect(text.contains('已倒下'), isFalse,
          reason: '★ hpMax==0 表示「未初始化 / 未公开」，不是「已死」');
    });

    testWidgets('★ 玩家侧不渲染「下一个行动」，KP 侧渲染且可点（T-22）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await _seedCombat(f, _combatFixture());

      await tester.pumpWidget(_host(f, 'p1', const GpCombatList()));
      await tester.pump();
      expect(find.byKey(RoomKeys.action('combat.next')), findsNothing);

      await tester.pumpWidget(_host(f, kHostSeat, const GpCombatList()));
      await tester.pump();
      final tap = tester.widget<RoomTap>(find.byKey(RoomKeys.action('combat.next')));
      expect(tap.enabled, isTrue);
    });

    testWidgets('切到「怪物信息」tab 后多出类型 / 行动数（本地态，不发包）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await _seedCombat(f, _combatFixture());
      await tester.pumpWidget(_host(f, kHostSeat, const GpCombatList(height: 240)));
      await tester.pump();
      f.clearSent();

      final tabs = tester.widget<PanelTabs>(find.byKey(GpCombatKeys.tabs));
      tabs.onChanged(1);
      await tester.pump();

      expect(f.localOf(kHostSeat).combatTab, 1);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .join('\n');
      expect(text.contains('monster'), isTrue);
      expect(text.contains('行动 1'), isTrue);
      expect(f.sent, isEmpty, reason: '切 tab 是纯本地态，不许发包');
    });

    testWidgets('请求卡：同意后待办出队，同意链发出 confirm intent（T-33）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      // 权威端待确认队列（T7：KP 从 hostRead 读，不在 state 里找）
      f.host.pending.add(<String, Object?>{
        'by': 'p1',
        'op': 'room.close',
        'p': <String, Object?>{},
        'need': RoomConfirm.twice,
        'at': 1,
      });
      f.kpSession.pumpPlans(<dynamic>[].cast());

      await tester.pumpWidget(_host(f, kHostSeat, const GpCombatList()));
      await tester.pump();

      final id = 'combat-pending:room.close:p1';
      expect(find.byKey(GpCombatKeys.row(id)), findsOneWidget);
      f.clearSent();

      await tester.tap(find.byKey(GpStatusKeys.agree(id)));
      await tester.pump();

      final p = _lastP(f, RoomIntent.confirm);
      expect(p, isNotNull, reason: '同意必须发 INTENT.CONFIRM');
      expect(p!['op'], 'room.close');
      expect(p['by'], 'p1');
      expect(p['agree'], isTrue);
      expect(f.host.pending, isEmpty, reason: '权威端待办已被消费');
    });
  });

  group('S3.4 · 状态条', () {
    testWidgets('KP 空态：暂无待办（块 12 恒空是合法状态）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, kHostSeat, const GpStatus()));
      await tester.pump();
      expect(find.byKey(GpStatusKeys.root), findsOneWidget);
      expect(find.byKey(GpStatusKeys.empty), findsOneWidget);
      expect(find.text('暂无待办'), findsOneWidget);
    });

    testWidgets('★ KP 待办卡：同意 → 发 confirm intent 且待办出队', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      // 权威端待确认队列（T7：KP 从 hostRead 读，不在 state 里找）
      f.host.pending.add(<String, Object?>{
        'by': 'p1',
        'op': 'room.close',
        'p': <String, Object?>{},
        'need': RoomConfirm.twice,
        'at': 1,
      });
      f.kpSession.pumpPlans(<dynamic>[].cast());

      await tester.pumpWidget(_host(f, kHostSeat, const GpStatus()));
      await tester.pump();
      const id = 'pending:room.close:p1';
      expect(find.byKey(GpStatusKeys.request(id)), findsOneWidget);
      expect(find.byKey(GpStatusKeys.pending), findsOneWidget,
          reason: '有待办时显示角标条数');
      f.clearSent();

      await tester.tap(find.byKey(GpStatusKeys.agree(id)));
      await tester.pump();

      final p = _lastP(f, RoomIntent.confirm);
      expect(p, isNotNull, reason: 'KP 的确认走 INTENT.CONFIRM');
      expect(p!['op'], 'room.close');
      expect(p['by'], 'p1');
      expect(p['agree'], isTrue);
      expect(f.host.pending, isEmpty, reason: '同意后待办出队');
      expect(find.byKey(GpStatusKeys.empty), findsOneWidget);
    });

    testWidgets('★ PL 需我同意：KP 发起 state.request → 玩家侧出卡 → 同意发 consent',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      // 真实链路：KP 请求改 p1 的状态 → 权威端记账 + 定向 REQUEST 事件给 p1
      await f.controllerOf(kHostSeat).hostAction('state.request', <String, Object?>{
        'seat': 'p1',
        'change': <String, Object?>{'hp': 5},
        'reason': '剧本效果',
      });
      expect(f.host.requestsBySeat['p1'], hasLength(1));

      await tester.pumpWidget(_host(f, 'p1', const GpStatus()));
      await tester.pump();
      // 玩家侧读自己那份裁剪态里的 requests（不要越权读 hostRead）
      final req = asList(f.stateOf('p1')['requests']).first as Map;
      final id = '${req['id']}';
      expect(find.byKey(GpStatusKeys.request(id)), findsOneWidget);
      f.clearSent();

      await tester.tap(find.byKey(GpStatusKeys.agree(id)));
      await tester.pump();

      final p = _lastP(f, RoomIntent.consent);
      expect(p, isNotNull, reason: '玩家的同意走 INTENT.CONSENT');
      expect(p!['id'], id);
      expect(p['agree'], isTrue);
      expect(f.host.requestsBySeat['p1'], isEmpty, reason: '同意后请求出队');
    });

    testWidgets('拒绝路径：confirm 的 agree=false，待办同样出队', (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      f.host.pending.add(<String, Object?>{
        'by': 'p1',
        'op': 'room.close',
        'p': <String, Object?>{},
        'need': RoomConfirm.twice,
        'at': 1,
      });
      f.kpSession.pumpPlans(<dynamic>[].cast());

      await tester.pumpWidget(_host(f, kHostSeat, const GpStatus()));
      await tester.pump();
      f.clearSent();

      await tester.tap(find.byKey(GpStatusKeys.reject('pending:room.close:p1')));
      await tester.pump();
      expect(_lastP(f, RoomIntent.confirm)!['agree'], isFalse);
      expect(f.host.pending, isEmpty);
    });

    testWidgets('PL 空态：没有需要你同意的请求',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      await tester.pumpWidget(_host(f, 'p1', const GpStatus()));
      await tester.pump();
      expect(find.text('没有需要你同意的请求'), findsOneWidget);
    });
  });

  group('S3.1 · 素材舞台：归一化坐标（纯函数，T-13）', () {
    test('stageNormOf：中心 → (0.5, 0.5)，越界夹到 [0,1]，零尺寸不出 NaN', () {
      const size = Size(200, 100);
      final mid = stageNormOf(const Offset(100, 50), size);
      expect(mid.x, closeTo(0.5, 1e-9));
      expect(mid.y, closeTo(0.5, 1e-9));

      final over = stageNormOf(const Offset(500, 500), size);
      expect(over.x, 1.0);
      expect(over.y, 1.0);

      final under = stageNormOf(const Offset(-20, -20), size);
      expect(under.x, 0.0);
      expect(under.y, 0.0);

      final zero = stageNormOf(const Offset(10, 10), Size.zero);
      expect(zero.x.isNaN, isFalse);
      expect(zero.y.isNaN, isFalse);

      // JSON 形状：{x, y}，权威端 mapStroke 认这个键
      final json = stagePointJson(mid);
      expect(json.keys.toSet(), <String>{'x', 'y'});
    });

    test('MapStageControl：六个成员的状态机（§3.9 契约）', () {
      final c = MapStageControl();
      expect(c.mode, MapStageMode.none);
      expect(c.awaitingTap, isFalse);

      c.beginStroke(color: '#e74c3c', width: 5);
      expect(c.mode, MapStageMode.stroke);
      expect(c.strokeColor, '#e74c3c');
      expect(c.strokeWidth, 5);
      expect(c.awaitingTap, isFalse, reason: '画笔不是「等一次点击」');

      c.beginErase();
      expect(c.mode, MapStageMode.erase);

      c.beginMark(kind: 'pin', label: '门');
      expect(c.mode, MapStageMode.mark);
      expect(c.markKind, 'pin');
      expect(c.markLabel, '门');
      expect(c.awaitingTap, isTrue);

      c.beginPlace(actorName: '深潜者');
      expect(c.mode, MapStageMode.placeActor);
      expect(c.actorName, '深潜者');
      expect(c.awaitingTap, isTrue);

      c.beginPlace(playerSeat: 'p2');
      expect(c.mode, MapStageMode.placePlayer);
      expect(c.playerSeat, 'p2');

      c.cancel();
      expect(c.mode, MapStageMode.none);
      expect(c.awaitingTap, isFalse);
      expect(c.actorName, isNull);
      expect(c.playerSeat, isNull);
    });

    testWidgets('KP 标点落点：点一下 → map.mark 带归一化坐标 + kind/label',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      final control = MapStageControl();
      await tester.pumpWidget(
        _host(f, kHostSeat, GpMapStage(controller: control)),
      );
      await tester.pump();
      f.clearSent();

      control.beginMark(kind: 'pin', label: '门');
      await tester.pump();
      expect(control.awaitingTap, isTrue);

      await tester.tap(find.byKey(GpMapStageKeys.canvas));
      await tester.pump();

      final p = _lastP(f, 'map.mark');
      expect(p, isNotNull, reason: '标点必须发 map.mark');
      final x = (p!['x']! as num).toDouble();
      final y = (p['y']! as num).toDouble();
      expect(x, inInclusiveRange(0.0, 1.0));
      expect(y, inInclusiveRange(0.0, 1.0));
      expect(x, closeTo(0.5, 0.2), reason: '点中心 → 归一化 x 应接近 0.5');
      expect(p['kind'], 'pin');
      expect(p['label'], '门');
      expect(p['revealed'], isTrue);
      // 单次工具态：落一次就复位
      expect(control.awaitingTap, isFalse);

      // 权威端真的落了标点
      final scene = f.hostState()['scene']! as Map<String, Object?>;
      expect((scene['marks']! as List<Object?>), hasLength(1));
    });

    testWidgets('画笔：一次拖拽 → 恰好一条 map.stroke，点全在 [0,1]',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      final control = MapStageControl();
      await tester.pumpWidget(
        _host(f, kHostSeat, GpMapStage(controller: control)),
      );
      await tester.pump();
      f.clearSent();

      control.beginStroke(color: '#3498db', width: 4);
      await tester.pump();

      final center = tester.getCenter(find.byKey(GpMapStageKeys.canvas));
      await tester.dragFrom(center - const Offset(40, 0), const Offset(80, 0));
      await tester.pump();

      final strokes = f.sent.where((e) => e['op'] == 'map.stroke').toList();
      expect(strokes, hasLength(1), reason: '手势末尾只发一次');
      final p = (strokes.single['p']! as Map).cast<String, Object?>();
      expect(p['color'], '#3498db');
      expect(p['width'], 4);
      final pts = (p['pts']! as List<Object?>).cast<Map<String, Object?>>();
      expect(pts.length, greaterThanOrEqualTo(2));
      for (final q in pts) {
        expect((q['x']! as num).toDouble(), inInclusiveRange(0.0, 1.0));
        expect((q['y']! as num).toDouble(), inInclusiveRange(0.0, 1.0));
      }
      // 权威端落笔
      final scene = f.hostState()['scene']! as Map<String, Object?>;
      expect((scene['strokes']! as List<Object?>), hasLength(1));
    });

    testWidgets('橡皮：段级删除 + 手势末尾一次全量 map.strokes.set',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      final control = MapStageControl();
      await tester.pumpWidget(
        _host(f, kHostSeat, GpMapStage(controller: control)),
      );
      await tester.pump();

      // 先画一条横线：用多段 moveTo 造出「多点」笔迹（dragFrom 只有起止两点，
      // 段级擦除只按「点是否落在擦除路径附近」判命中，两点书就没得可擦）。
      control.beginStroke(color: '#e74c3c', width: 4);
      await tester.pump();
      final center = tester.getCenter(find.byKey(GpMapStageKeys.canvas));
      final g = await tester.startGesture(center - const Offset(60, 0));
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(center - const Offset(60, 0) + Offset(i * 10.0, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();
      final before = (f.hostState()['scene']! as Map<String, Object?>)['strokes']!
          as List<Object?>;
      expect(before, hasLength(1));

      f.clearSent();
      control.beginErase();
      await tester.pump();

      // 从上往下擦过那条线：pan 需要越过 18px 才触发，所以用多段 moveTo
      // 造一条**穿过**线的擦除路径（单点路径的容差只有 2%，会擦不中）。
      final eg = await tester.startGesture(center - const Offset(0, 40));
      for (var i = 1; i <= 8; i++) {
        await eg.moveTo(center - const Offset(0, 40) + Offset(0, i * 10.0));
        await tester.pump();
      }
      await eg.up();
      await tester.pump();

      final sets = f.sent.where((e) => e['op'] == 'map.strokes.set').toList();
      expect(sets, hasLength(1), reason: '★ 手势末尾只发一次全量');
      final next = ((sets.single['p']! as Map)['strokes']! as List<Object?>);
      // 段级删除：被命中的点消失 → 剩下来的总点数严格变少
      var afterPts = 0;
      for (final st in next) {
        afterPts += ((st! as Map)['pts']! as List<Object?>).length;
      }
      var beforePts = 0;
      for (final st in before) {
        beforePts += ((st! as Map)['pts']! as List<Object?>).length;
      }
      expect(afterPts, lessThan(beforePts), reason: '橡皮必须真的删掉点');
    });

    testWidgets('只读舞台（玩家侧 / 全屏）：任何手势都不发包',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      final control = MapStageControl();
      await tester.pumpWidget(
        _host(f, 'p1', GpMapStage(controller: control, readOnly: true)),
      );
      await tester.pump();
      f.clearSent();

      control.beginMark(kind: 'pin', label: '门');
      await tester.pump();
      await tester.tap(find.byKey(GpMapStageKeys.canvas));
      await tester.pump();

      control.beginStroke(color: '#e74c3c', width: 4);
      await tester.pump();
      final center = tester.getCenter(find.byKey(GpMapStageKeys.canvas));
      await tester.dragFrom(center - const Offset(20, 0), const Offset(40, 0));
      await tester.pump();

      expect(f.sent, isEmpty, reason: '只读舞台不得发出任何动作');
    });
  });
}
