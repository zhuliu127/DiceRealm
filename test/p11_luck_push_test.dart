// ============================================================
// test/p11_luck_push_test.dart — P11「花幸运」与「推动检定」接线验收
//
// 背景（本文件钉死的东西）：
//   `CocRules.spendLuck` / `canPush` / `luckAllowed` 早就算得对，但全库**零调用方**
//   —— 规则层是完整的，玩家却用不了。本批把它们接到权威端：
//     · 花幸运：`INTENT.DICE{luck:true, amount:N}` → 扣 status.currentLuck
//       → 新增一条 EVT.DICE（新骰值/新等级）→ 公共播报
//     · 推动：`INTENT.DICE{push:true}` → 同技能同难度重掷 → 新记录带 pushed
//       → 公共播报（失败时明确「后果加重」，绝不自作主张施加后果）
//
// ★ 三条硬约束（对应交付要求）：
//   ① 不新增 RoomEvt（27 项被 fixture 锁死）—— 全用 DICE / LOG / STATE；
//   ② 不新增 POLICY action（61 条被 fixture 锁死）—— 走不过 needs() 的 DICE 通道；
//   ③ 只认「自己最近一条」记录，别人的 / 更早的都不许改。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_rules.dart' show CocRules;
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/view/feed_view.dart';
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';
import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 权威端脚手架
// ------------------------------------------------------------

Map<String, Object?> _sheet(int luck, {int san = 50}) => <String, Object?>{
      'name': '张三',
      'status': <String, Object?>{
        'currentHP': 10,
        'maxHP': 12,
        'currentSAN': san,
        'maxSAN': 99,
        'currentLuck': luck,
      },
      'mental': <Object?>[],
    };

/// 固定 seed=1：`rules.check` 的第一次掷值恒为 32。
/// · base 20 → 失败（32 > 20，且 32 < 96 不算大失败），差 12 点刚好成功；
/// · base 90 → 硬成功（不会出现任何按钮）。
RoomHost _host({
  int luck = 20,
  int san = 50,
  Map<String, Object?>? meta,
}) {
  final h = RoomHost(roomHostOpts(
    seed: 1,
    meta: meta ?? const <String, Object?>{},
  ));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  h.roster.get('p1')!['sheet'] = _sheet(luck, san: san);
  h.roster.get('p2')!['sheet'] = _sheet(luck, san: san);
  return h;
}

/// 玩家自助技能检定（与 DiceTools 面板同一载荷形状）。
List<SendPlan> _roll(RoomHost h, {String seat = 'p1', int base = 20}) =>
    h.intent(seat, <String, Object?>{
      'op': RoomIntent.dice,
      'p': <String, Object?>{
        'direct': true,
        'expr': '1D100',
        'label': '侦查',
        'base': base,
      },
    });

List<SendPlan> _luck(RoomHost h, [int? amount, String seat = 'p1']) =>
    h.intent(seat, <String, Object?>{
      'op': RoomIntent.dice,
      'p': <String, Object?>{
        'luck': true,
        'amount': ?amount,
      },
    });

List<SendPlan> _push(RoomHost h, {String seat = 'p1'}) =>
    h.intent(seat, <String, Object?>{
      'op': RoomIntent.dice,
      'p': <String, Object?>{'push': true},
    });

/// 最近一条公共骰记录。
Map<String, Object?> _lastDice(RoomHost h) =>
    asMap(asList(h.state['dice']).last);

List<Map<String, Object?>> _dice(RoomHost h) =>
    asList(h.state['dice']).map(asMap).toList();

/// 公共日志文本（`state.logs`）。
List<String> _logs(RoomHost h) => asList(h.state['logs'])
    .map((e) => jsStr(asMap(e)['text']))
    .toList();

/// 计划里所有**定向私密**事件的文本（越权提示走这条路，不进公共流）。
List<String> _privateTexts(List<SendPlan> out) {
  final res = <String>[];
  for (final plan in out) {
    final msg = asMap(plan.toJson()['msg']);
    if (msg['k'] != 'evt' || msg['t'] != RoomEvt.private_) continue;
    res.add(jsStr(asMap(msg['p'])['text']));
  }
  return res;
}

int _luckOf(RoomHost h, {String seat = 'p1'}) =>
    jsNum(asMap(asMap(h.roster.get(seat)!['sheet'])['status'])['currentLuck'])
        .toInt();

void main() {
  // ==========================================================
  // 一、花幸运
  // ==========================================================
  group('花幸运 · spendLuck 接线', () {
    test('① 失败 → 花 12 点 → 常规成功；扣点 / 改写 / 公共播报三件事齐全', () {
      final h = _host();
      _roll(h);
      expect(_lastDice(h)['level'], 'fail', reason: 'seed=1 base=20 → 32 失败');
      expect(_lastDice(h)['total'], 32);

      final out = _luck(h, 12);
      expect(out, isNotEmpty);

      // ② 改写：新增一条骰记录，骰值 = target，等级 = 常规成功，可溯源。
      final rec = _lastDice(h);
      expect(rec['total'], 20, reason: '32 - 12 = 20 = 目标值');
      expect(rec['level'], 'regular');
      expect(rec['levelText'], '常规成功');
      expect(rec['luckSpent'], 12);
      expect(rec['luckFrom'], 32);
      expect(rec['target'], 20, reason: '附带信息要跟着新记录一起走');

      // ① 扣点
      expect(_luckOf(h), 8, reason: '20 - 12 = 8');

      // ③ 公共播报（金额 / 旧值 / 新值 / 新等级，缺一不可）
      final log = _logs(h).last;
      expect(log, contains('花 12 点幸运'));
      expect(log, contains('32 → 20'));
      expect(log, contains('常规成功'));
      expect(log, contains('剩 8 点'));
    });

    test('② 未给 amount 时按「刚好压到目标值」自动算 need', () {
      final h = _host();
      _roll(h);
      _luck(h);
      expect(_lastDice(h)['luckSpent'], 12);
      expect(_lastDice(h)['level'], 'regular');
      expect(_luckOf(h), 8);
    });

    test('③ 幸运点不足 → 拒绝，且骰记录 / 幸运点 / 公共流一个字节都不动', () {
      final h = _host(luck: 5);
      _roll(h);
      final before = _dice(h).length;
      final logs = _logs(h).length;
      final out = _luck(h, 12);
      expect(_privateTexts(out).join('\n'), contains('幸运点不足'));
      expect(_dice(h).length, before, reason: '不得追加骰记录');
      expect(_luckOf(h), 5, reason: '不得扣点');
      expect(_logs(h).length, logs, reason: '公共流不得新增（提示只给本人）');
    });

    test('④ 大失败 → 拒绝（规则书：不能被幸运抹掉）', () {
      // fumbleThreshold=1 → 本次掷骰一律判大失败。
      final h = _host(meta: <String, Object?>{'fumbleThreshold': 1});
      _roll(h);
      expect(_lastDice(h)['level'], 'fumble');
      final out = _luck(h, 1);
      expect(_privateTexts(out).join('\n'), contains('大失败不能被幸运点抹掉'));
      expect(_lastDice(h)['level'], 'fumble', reason: '结果不得被改写');
      expect(_luckOf(h), 20);
    });

    test('⑤ 大成功 → 拒绝', () {
      final h = _host(meta: <String, Object?>{'critThreshold': 99});
      _roll(h);
      expect(_lastDice(h)['level'], 'critical');
      final out = _luck(h, 1);
      expect(_privateTexts(out).join('\n'), contains('已经是大成功'));
      expect(_luckOf(h), 20);
    });

    test('⑥ 理智检定 → 拒绝（kind 不可花）', () {
      final h = _host(san: 16);
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.sanCheck,
        'p': <String, Object?>{'okLoss': '0', 'loss': '1D6'},
      });
      expect(_lastDice(h)['kind'], 'san');
      expect(_lastDice(h)['level'], 'fail', reason: '16 目标掷出 32 → 失败');
      final out = _luck(h, 1);
      expect(_privateTexts(out).join('\n'), contains('幸运点不能用来改理智检定'));
      expect(_lastDice(h)['total'], 32, reason: 'SAN 失败结果不得被幸运改');
    });

    test('⑦ 改别人的检定 → 拒绝（只能改自己最近一条）', () {
      final h = _host();
      _roll(h, seat: 'p2'); // 只有 p2 有记录
      final out = _luck(h, 4, 'p1');
      expect(_privateTexts(out).join('\n'), contains('找不到可结算的检定结果'));
      expect(_lastDice(h)['seat'], 'p2');
      expect(_lastDice(h)['total'], 32, reason: 'p2 的失败结果不得被 p1 改');
      expect(_luckOf(h, seat: 'p2'), 20, reason: 'p2 的点数也不得被动');
    });

    test('⑧ KP / 旁观者不能花幸运（没有可结算的玩家卡）', () {
      final h = _host();
      final out = h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{'luck': true, 'amount': 1},
      });
      expect(_privateTexts(out).join('\n'), contains('旁观者不能花幸运点'));
      expect(asList(h.state['dice']), isEmpty);
    });
  });

  // ==========================================================
  // 二、推动检定
  // ==========================================================
  group('推动检定 · canPush 接线', () {
    test('① 失败 → 重掷发生：新记录带 pushed，公共播报写明推动与失败后果', () {
      final h = _host();
      _roll(h);
      expect(_lastDice(h)['level'], 'fail');
      final out = _push(h);
      expect(out, isNotEmpty);
      final rec = _lastDice(h);
      expect(_dice(h).length, 2, reason: '原记录 + 重掷记录');
      expect(rec['pushed'], isTrue);
      expect(rec['pushFrom'], 32, reason: '要能看出推动前的骰值');
      expect(rec['total'], 75, reason: 'seed=1 的第二次 rules.check 掷值');
      expect(rec['level'], 'fail');
      final log = _logs(h).last;
      expect(log, contains('推动了「侦查」检定'));
      expect(log, contains('1D100 → 75'));
      expect(log, contains('推动失败，后果加重'),
          reason: 'CoC：推动失败的后果由 KP 加重，必须明确告知');
    });

    test('② 同一检定不能推动两次', () {
      final h = _host();
      _roll(h);
      _push(h);
      final out = _push(h);
      expect(_privateTexts(out).join('\n'), contains('已经推动过'));
      expect(_dice(h).length, 2, reason: '第二次推动不得再产生骰记录');
    });

    test('③ 战斗检定 → 拒绝（规则层 canPush 判死，宿主层也不给入口）', () {
      // 规则层：`_pushable['combat'] = false`
      final v = const CocRules().canPush(<String, Object?>{
        'kind': 'combat',
        'passed': false,
        'fumble': false,
      }, 'combat');
      expect(v['ok'], isFalse);
      expect(jsStr(v['reason']), contains('战斗检定不能推动'));

      // 宿主层：`combat.roll` 的记录不落检索附加信息（见 dispatchCombatAction），
      // 于是它连「可推动的检定结果」都算不上 → 拒绝，不会误推。
      final h = _host();
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.act,
        'p': <String, Object?>{'op': 'combat.roll', 'expr': '1D100', 'label': '攻击'},
      });
      expect(_lastDice(h).containsKey('target'), isFalse);
      final out = _push(h);
      expect(_privateTexts(out).join('\n'), contains('找不到可推动的检定结果'));
      expect(_dice(h).length, 1, reason: '不得产生重掷记录');
    });

    test('④ 已经成功的检定 → 拒绝（规则层的原话要透给玩家）', () {
      final h = _host();
      _roll(h, base: 90); // 32 ≤ 45 → 困难成功
      expect(_lastDice(h)['level'], isNot('fail'));
      final out = _push(h);
      expect(_privateTexts(out).join('\n'), contains('检定已经成功'));
      expect(_dice(h).length, 1);
    });

    test('⑤ 大失败 → 拒绝（立即生效，不能被推动抹掉）', () {
      final h = _host(meta: <String, Object?>{'fumbleThreshold': 1});
      _roll(h);
      final out = _push(h);
      expect(_privateTexts(out).join('\n'), contains('大失败立即生效'));
      expect(_dice(h).length, 1);
    });
  });

  // ==========================================================
  // 三、UI：按钮只在该出现时出现
  // ==========================================================
  group('UI · 按钮渲染', () {
    /// 造一条失败检定的 FeedItem（与权威端 state.dice 形状一致）。
    FeedItem diceItem({
      int seq = 7,
      String seat = 'p1',
      num total = 32,
      num target = 20,
      String level = 'fail',
      String kind = 'skill',
      bool pushed = false,
    }) =>
        FeedItem(
          seq: seq,
          at: 1,
          kind: FeedKind.dice,
          seat: seat,
          nickname: '甲',
          dice: <String, Object?>{
            'seq': seq,
            'seat': seat,
            'expr': '1D100',
            'total': total,
            'level': level,
            'levelText': '失败',
            'label': '侦查',
            'kind': kind,
            'base': target,
            'target': target,
            if (pushed) 'pushed': true,
          },
        );

    test('① 失败且点数够 → 两个动作都算得出来；need = 骰值 - 目标', () {
      final a = checkActionOf(
        diceItem(),
        mySeat: 'p1',
        role: RoomRole.player,
        isLatestOfSeat: true,
        luck: 20,
      );
      expect(a, isNotNull);
      expect(a!.luckAmount, 12);
      expect(a.luckLabel, '花 12 点幸运改为成功');
      expect(a.canPush, isTrue);
    });

    test('② 不可操作时一律返回 null（→ 一个按钮都不渲染）', () {
      // 大失败
      expect(
        checkActionOf(diceItem(level: 'fumble'),
            mySeat: 'p1',
            role: RoomRole.player,
            isLatestOfSeat: true,
            luck: 99),
        isNull,
      );
      // 已经成功
      expect(
        checkActionOf(diceItem(level: 'regular', total: 18),
            mySeat: 'p1',
            role: RoomRole.player,
            isLatestOfSeat: true,
            luck: 99),
        isNull,
      );
      // 不是最近一条
      expect(
        checkActionOf(diceItem(),
            mySeat: 'p1',
            role: RoomRole.player,
            isLatestOfSeat: false,
            luck: 99),
        isNull,
      );
      // 别人的检定
      expect(
        checkActionOf(diceItem(),
            mySeat: 'p2',
            role: RoomRole.player,
            isLatestOfSeat: true,
            luck: 99),
        isNull,
      );
      // 旁观者
      expect(
        checkActionOf(diceItem(),
            mySeat: 'p1',
            role: RoomRole.spectator,
            isLatestOfSeat: true,
            luck: 99),
        isNull,
      );
      // 已被推动过：推动按钮消失，但**花幸运仍可用**（推动出来的结果也可以花点数）
      final pushedAction = checkActionOf(
        diceItem(pushed: true),
        mySeat: 'p1',
        role: RoomRole.player,
        isLatestOfSeat: true,
        luck: 99,
      );
      expect(pushedAction, isNotNull);
      expect(pushedAction!.canPush, isFalse);
      // 理智检定（幸运不可改）
      expect(
        checkActionOf(diceItem(kind: 'san'),
            mySeat: 'p1',
            role: RoomRole.player,
            isLatestOfSeat: true,
            luck: 99),
        isNull,
      );
    });

    test('③ 点数不够：幸运按钮不出现，但推动按钮照旧（只降级不整体消失）', () {
      final a = checkActionOf(
        diceItem(),
        mySeat: 'p1',
        role: RoomRole.player,
        isLatestOfSeat: true,
        luck: 5,
      );
      expect(a, isNotNull);
      expect(a!.canLuck, isFalse);
      expect(a.luckAmount, 0);
      expect(a.canPush, isTrue);
    });

    // ---- 真渲染：块级（MaterialApp + RoomScope + Scaffold） ----

    /// p1 的卡：侦查 20（失败的检定）、幸运 20。
    void shareOwnSheet(RoomUiFixture f, {int scouting = 20, int luck = 20}) {
      unawaitedSend(f, <String, Object?>{
        'id': 'c_p1',
        'name': '甲的调查员',
        'sheet': <String, Object?>{
          'name': '甲的调查员',
          'attrs': <String, Object?>{'str': 50, 'dex': 60},
          'status': <String, Object?>{
            'currentHP': 12,
            'maxHP': 12,
            'currentMP': 10,
            'maxMP': 10,
            'currentSAN': 55,
            'maxSAN': 99,
            'currentLuck': luck,
          },
          'skills': <Object?>[
            // ⚠️ 清洗器只认 `total`（`value` 会被丢掉并回落 0）。
            <String, Object?>{'name': '侦查', 'total': scouting},
          ],
        },
      });
    }

    testWidgets('④ 失败检定上出现「花 12 点幸运改为成功」与「推动检定」；点了发出正确载荷',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      shareOwnSheet(f);
      f.controllerOf('p1').sendIntent(RoomIntent.dice, <String, Object?>{
        'direct': true,
        'expr': '1D100',
        'label': '侦查',
      });

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: f.scoped('p1', child: const GpFeeds(pane: FeedPane.record)),
          ),
        ),
      ));
      await tester.pump();

      final seq = asList(f.stateOf('p1')['dice']).length;
      expect(seq, 1);
      final diceSeq =
          jsNum(asMap(asList(f.stateOf('p1')['dice']).single)['seq']).toInt();

      expect(find.byKey(GpFeedsKeys.luck(diceSeq)), findsOneWidget,
          reason: '可花幸运时必须渲染按钮');
      expect(find.text('花 12 点幸运改为成功'), findsOneWidget);
      expect(find.byKey(GpFeedsKeys.push(diceSeq)), findsOneWidget);
      expect(find.text(FeedCheckAction.pushLabel), findsOneWidget);

      // 点「花幸运」→ 只发一条 INTENT.DICE{luck,amount}（不自己改任何状态）
      await tester.tap(find.byKey(GpFeedsKeys.luck(diceSeq)));
      await tester.pump();
      final sent = f.sent.last;
      expect(sent['op'], RoomIntent.dice);
      expect(asMap(sent['p'])['luck'], isTrue);
      expect(asMap(sent['p'])['amount'], 12);
    });

    testWidgets('⑤ 成功的检定上不渲染任何按钮（findsNothing）',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      shareOwnSheet(f, scouting: 90); // 32 ≤ 45 → 困难成功
      f.controllerOf('p1').sendIntent(RoomIntent.dice, <String, Object?>{
        'direct': true,
        'expr': '1D100',
        'label': '侦查',
      });

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: f.scoped('p1', child: const GpFeeds(pane: FeedPane.record)),
          ),
        ),
      ));
      await tester.pump();

      final diceSeq =
          jsNum(asMap(asList(f.stateOf('p1')['dice']).single)['seq']).toInt();
      expect(find.byKey(GpFeedsKeys.luck(diceSeq)), findsNothing);
      expect(find.byKey(GpFeedsKeys.push(diceSeq)), findsNothing);
      expect(find.text(FeedCheckAction.pushLabel), findsNothing);
    });

    testWidgets('⑥ 别人（KP 视角）的失败检定上没有我的按钮',
        (WidgetTester tester) async {
      final f = RoomUiFixture()..bootSync();
      shareOwnSheet(f);
      f.controllerOf('p1').sendIntent(RoomIntent.dice, <String, Object?>{
        'direct': true,
        'expr': '1D100',
        'label': '侦查',
      });

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: f.scoped(kHostSeat,
                child: const GpFeeds(pane: FeedPane.record)),
          ),
        ),
      ));
      await tester.pump();

      final diceSeq =
          jsNum(asMap(asList(f.stateOf(kHostSeat)['dice']).single)['seq'])
              .toInt();
      expect(find.byKey(GpFeedsKeys.luck(diceSeq)), findsNothing,
          reason: 'KP 不能改玩家的检定结果');
      expect(find.byKey(GpFeedsKeys.push(diceSeq)), findsNothing);
    });
  });
}

/// 夹具里分享角色卡（同步链路，`sendIntent` 返回的 Future 不 await）。
void unawaitedSend(RoomUiFixture f, Map<String, Object?> payload) {
  f.plSessions['p1']!.sendIntent(RoomIntent.char, payload);
}
