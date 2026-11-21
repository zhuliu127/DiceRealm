// ============================================================
// test/p10_t7_c_combat_test.dart — P10 第 7 期 C 批 B（问题 10）验收
//
// 用户原话：「现在点『转战斗』进入战斗模式，没有让我选择哪些怪物和玩家
//   进入战斗，而且进入战斗模式，没有出现战斗轮次信息栏位。」
//
// 覆盖：
//   ① 工具栏「转战斗」→ 打开「战斗模式 · 选择参战单位」弹层，不发 scene.mode；
//   ② 玩家默认全勾 / 怪物默认全不勾 / 空手点部署的「至少 1 怪」门禁；
//   ③ 勾 1 怪 + 保留 2 玩家 → 载荷逐字段（含显式 PC 记录）；
//   ④ 载荷喂 domain → order 长度 = 怪槽 + PC 槽、同时有 pc/monster、首槽高亮；
//   ⑤ T-30：三视角 scene.mode / combat.start 的 enabled 恒等 gate.can；
//   ⑥ 战斗态点按钮走 combat.end（不是 scene.mode）；
//   ⑦ 轮次条：strip 可见 / header 口径 / 高亮右移 / 文案同步 / K4「隐藏」；
//   ⑧ 纯函数 initiativeText 与 roundText 原样保留；
//   ⑨ 主理人追加：弹层「加单位」填 DEX/HP/每轮次数/类型（B 批同款）；
//   ⑩ 主理人裁决：空池 hint 明示纯玩家战斗 + 非空池门禁严格生效。
//
// ★ T1：全内存后端（RoomUiFixture），零真实 I/O；零 Timer / Future.delayed。
// ★ 断言不放宽：findsOneWidget 不降级 findsWidgets，不 skip、不改恒真。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat, RoomMode;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/sheets/sheet_add_actor.dart'
    show AddActorSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_combat.dart'
    show CombatSheet, CombatSheetKeys;
import 'package:dice_realm/ui/room/view/combat_view.dart'
    show combatRows, initiativeText, roundText;
import 'package:dice_realm/ui/room/view/room_view.dart' show isCombat;
import 'package:dice_realm/ui/room/widgets/gp_combat_list.dart'
    show GpCombatKeys, GpCombatList;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart' show GpMapStage;
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart' show GpToolbar;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show RoomSheet, RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 造一个开团中的房间（真实 action 开团，不手改权威态）。
Future<RoomUiFixture> _boot(WidgetTester tester,
    {double w = 900, double h = 1600}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: true);
  useRoomScreen(tester, w, h);
  return f;
}

/// 独立宿主：`MaterialApp.builder` 把作用域挂在 Navigator 之上，
/// 于是 `showRoomSheet` 推出的弹层也能取到同一份作用域。
Widget _hostApp(
  RoomUiFixture f,
  Widget body, {
  String seat = kHostSeat,
  Key? appKey,
}) {
  return MaterialApp(
    key: appKey,
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => f.scoped(
      seat,
      child: child ?? const SizedBox.shrink(),
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: body),
    ),
  );
}

/// 滚动到可见再点（勾选行 / 部署按钮可能落在首屏之外）。
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// 往 KP 候选池塞一只怪（字段与 `addLocalActor` 白名单一致）。
void _addMonster(RoomUiFixture f, {String id = 'la1', String name = '哥布林'}) {
  f.localOf(kHostSeat).pendingActors.add(<String, Object?>{
    'id': id,
    'name': name,
    'kind': 'monster',
    'hp': 10,
    'hpMax': 10,
    'dex': 50,
    'actionsPerRound': 1,
  });
}

/// 从 sent 里取最近一条 `combat.start` 的内层载荷。
Map<String, Object?> _startPayload(RoomUiFixture f) {
  final sent = f.lastSent(action: 'combat.start');
  expect(sent, isNotNull, reason: '必须发出 combat.start');
  return asMap(sent!['p']);
}

/// G-1 夹具：把「带 hp」的怪塞进**权威候选池**，再用**不带 hp/hpMax** 的
/// `combat.start` 载荷开战。
///
/// 这是 KP-4① 的真机触发形状：怪物草稿没有 hp → 下游载荷也没有 hp →
/// 旧代码静默 `raNum(null, 0)` 写成 0，KP 侧看到「怪物 HP 全显示 0」。
/// 载荷里那张 `actors` 表**故意只有 `{id,name,kind,dex,actionsPerRound}`**，
/// 补给源只能是 `host.localActors`。
Future<void> _startCombatFromPoolWithoutHp(
  RoomUiFixture f, {
  num poolHp = 13,
}) async {
  final ctl = f.controllerOf(kHostSeat);
  await ctl.hostAction('combat.pool.set', <String, Object?>{
    'actors': <Object?>[
      <String, Object?>{
        'id': 'm9',
        'name': '深潜者',
        'kind': 'monster',
        'dex': 60,
        'hp': poolHp,
        'hpMax': poolHp,
        'actionsPerRound': 1,
      },
    ],
  });
  expect(f.host.localActors.length, 1, reason: '前置：候选池应恰好 1 只');
  expect(f.host.localActors.single['hp'], poolHp,
      reason: '前置：候选池必须先拿到 hp（它是唯一的补给源）');

  await ctl.hostAction('combat.start', <String, Object?>{
    'actorIds': <Object?>['m9'],
    'actors': <Object?>[
      <String, Object?>{
        'id': 'm9',
        'name': '深潜者',
        'kind': 'monster',
        'dex': 60,
        'actionsPerRound': 1,
      },
    ],
    'pcSeats': <Object?>[],
  });
}

void main() {
  // ----------------------------------------------------------
  // ① 工具栏「转战斗」→ 弹层（不直发 scene.mode）
  // ----------------------------------------------------------
  group('① 转战斗先选参战单位', () {
    testWidgets('P17 P-4：工具栏 scene.mode 已删；KP 工具点 combat.start → '
        '出现选择参战单位弹层，且 sent 无 scene.mode',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // ★ P17 P-4：工具栏的「转战斗」（act/scene.mode）已三视角删除。
      await tester.pumpWidget(_hostApp(f, const GpToolbar()));
      await tester.pump();
      expect(isCombat(f.sessionOf(kHostSeat).state), isFalse,
          reason: '前提：当前是探索态');
      expect(find.byKey(RoomKeys.action('scene.mode')), findsNothing,
          reason: 'P17 P-4：工具栏不再渲染恒灰的 scene.mode');

      // ★ 2.36.0 / Q6：「战斗准备」已从 KpPanel 弹层扁平迁入工具栏主组，
      //   改挂独立 ValueKey `RoomGamePage.combatReadyKey`（不挂 act/ 锚点）。
      //   本用例改经该**真入口**打开同一个战斗准备弹层；:176-184 的核心
      //   不变量（标题 / RoomSheet / sent 无 scene.mode）逐字保留。
      useRoomScreen(tester, 1280, 800);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      await tester.pumpWidget(f.pageOf(kHostSeat));
      await tester.pump();
      final Finder ready = find.byKey(RoomGamePage.combatReadyKey);
      expect(ready, findsOneWidget,
          reason: '★ Q6：工具栏「战斗准备」真入口必须在');
      expect(find.byKey(RoomKeys.action('combat.start')), findsNothing,
          reason: '★ Q6：新按钮绝不挂 act/combat.start 锚点');

      f.clearSent();
      await _tap(tester, ready);
      // 推进底部弹层入场动画，让标题挂进元素树。
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('战斗模式 · 选择参战单位'), findsOneWidget,
          reason: '点「战斗准备」应打开战斗准备弹层');
      expect(find.byType(RoomSheet), findsOneWidget,
          reason: '必须真的推出底部弹层壳');
      expect(
        f.sent.where((e) => e['kind'] == 'action' && e['op'] == 'scene.mode'),
        isEmpty,
        reason: '开战准备绝不能直发 scene.mode（仍由弹层 deploy 走 combat.start）',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('弹层标题 / 说明文案 / 部署计数 / 空池提示',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();

      expect(find.byKey(CombatSheetKeys.root), findsOneWidget);
      expect(find.byKey(CombatSheetKeys.prepare), findsOneWidget);
      expect(
        find.text('勾选要进入战斗的玩家与怪物/NPC（玩家默认全选）。'
            '系统按 CoC 7th 规则自动排行动顺序。'),
        findsOneWidget,
      );
      expect(find.text('候选池是空的。点左栏「NPC·怪物」先添加。'),
          findsOneWidget);
      expect(find.text('玩家（勾选进入战斗）'), findsOneWidget);
      expect(find.text('怪物 / NPC（勾选进入战斗）'), findsOneWidget);
      expect(find.byKey(CombatSheetKeys.deployCount), findsOneWidget);
      expect(find.byKey(CombatSheetKeys.deploy), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ② 默认勾选态 + 「至少 1 怪」门禁
  // ----------------------------------------------------------
  group('② 默认全选玩家 / 默认全不选怪物 + 门禁', () {
    testWidgets('玩家默认全勾、怪物默认全不勾', (WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();

      for (final seat in f.playerSeats) {
        final tap = tester.widget<RoomTap>(
            find.byKey(CombatSheetKeys.pcToggle(seat)));
        expect(tap.icon, Icons.check_box,
            reason: '$seat 玩家应默认勾选');
      }
      final monster = tester.widget<RoomTap>(
          find.byKey(CombatSheetKeys.monsterToggle('la1')));
      expect(monster.icon, Icons.check_box_outline_blank,
          reason: '怪物应默认全不选');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('空手点部署 → combat.start 未发 + local.notice 明确提示',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      f.clearSent();

      await _tap(tester, find.byKey(RoomKeys.action('combat.start')));
      expect(f.lastSent(action: 'combat.start'), isNull,
          reason: '门禁必须挡住发包');
      expect(f.localOf(kHostSeat).notice, contains('至少选择 1 个怪物/NPC'),
          reason: 'K7：点下去要有一次性提示');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('门禁不进 enabled：combat.start 可点性恒等闸门',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();

      final Finder btn = find.byKey(RoomKeys.action('combat.start'));
      expect(btn, findsOneWidget);
      expect(tester.widget<RoomTap>(btn).enabled,
          f.controllerOf(kHostSeat).gate.can('combat.start'),
          reason: '不许把「至少 1 怪」叠进 enabled（T-30）');
      expect(tester.widget<RoomTap>(btn).enabled, isTrue,
          reason: '前提：KP 有 combat.start 权限');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('历史路径：候选池完全为空时仍可部署纯 PC 战斗（门禁只管有怪可勾）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // 故意不塞任何候选怪：此时没有可勾的怪，门禁不适用。
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      expect(find.text('候选池是空的。点左栏「NPC·怪物」先添加。'),
          findsOneWidget);
      f.clearSent();

      await _tap(tester, find.byKey(RoomKeys.action('combat.start')));
      final p = _startPayload(f);
      expect(asList(p['actorIds']).isEmpty, isTrue);
      expect(asList(p['pcSeats']).map(jsStr).toList(), f.playerSeats);
      final actors = asList(p['actors']).map(asMap).toList();
      expect(actors.length, f.playerSeats.length);
      expect(actors.every((a) => jsStr(a['kind']) == 'pc'), isTrue);
      final order = asList(asMap(f.hostState()['combat'])['order']);
      expect(order.length, f.playerSeats.length,
          reason: '纯 PC 战斗也必须真的产生玩家槽');
      expect(f.localOf(kHostSeat).notice ?? '',
          isNot(contains('至少选择 1 个怪物/NPC')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ③ 载荷逐字段（显式 PC 记录）
  // ----------------------------------------------------------
  group('③ combat.start 载荷', () {
    testWidgets('勾 1 怪 + 保留 2 玩家 → actorIds / pcSeats / actors 逐字段',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      f.clearSent();

      await _tap(tester, find.byKey(CombatSheetKeys.monsterToggle('la1')));
      // 用 deploy 锚点点部署（验证该稳定 key 可点）。
      await _tap(tester, find.byKey(CombatSheetKeys.deploy));
      final p = _startPayload(f);

      final actorIds = asList(p['actorIds']).map(jsStr).toList();
      expect(actorIds, <String>['la1'], reason: 'actorIds 恰为勾选的怪物 id');
      final pcSeats = asList(p['pcSeats']).map(jsStr).toList();
      expect(pcSeats, f.playerSeats, reason: 'pcSeats 恰为默认全选的 2 个座位');
      expect(pcSeats.length, 2);

      final actors = asList(p['actors']).map(asMap).toList();
      final pcs = actors.where((a) => jsStr(a['kind']) == 'pc').toList();
      final monsters =
          actors.where((a) => jsStr(a['kind']) != 'pc').toList();
      expect(monsters.length, 1, reason: '1 条勾选的怪物记录');
      expect(jsStr(monsters.single['id']), 'la1');
      expect(pcs.length, 2, reason: '2 条显式构造的 PC 记录');
      for (final pc in pcs) {
        expect(jsStr(pc['seat']).isNotEmpty, isTrue);
        expect(jsStr(pc['id']), startsWith('p-'));
        expect(pc.containsKey('dex'), isTrue);
        expect(pc.containsKey('hp'), isTrue);
        expect(pc.containsKey('hpMax'), isTrue);
        expect(pc['actionsPerRound'], 1);
        // DEX / HP 真的从成员卡读到（不是编的 0 默认值）。
        expect((pc['dex'] as num) > 0, isTrue);
        expect((pc['hp'] as num) > 0, isTrue);
        expect((pc['hpMax'] as num) > 0, isTrue);
      }

      // 计数文案 + 按钮文案
      final count =
          tester.widget<Text>(find.byKey(CombatSheetKeys.deployCount));
      expect(count.data, contains('怪物 1'));
      expect(count.data, contains('玩家 2'));
      final deploy = tester.widget<RoomTap>(
          find.byKey(RoomKeys.action('combat.start')));
      expect(deploy.label, contains('⚔️ 战斗部署完毕'));
      expect(deploy.label, contains('怪物 1 · 玩家 2'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('取消一个玩家勾选 → pcSeats / PC 记录同步减少',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      f.clearSent();

      await _tap(tester, find.byKey(CombatSheetKeys.monsterToggle('la1')));
      await _tap(tester, find.byKey(CombatSheetKeys.pcToggle('p1')));
      await _tap(tester, find.byKey(RoomKeys.action('combat.start')));
      final p = _startPayload(f);

      expect(asList(p['pcSeats']).map(jsStr).toList(), <String>['p2']);
      final pcs = asList(p['actors'])
          .map(asMap)
          .where((a) => jsStr(a['kind']) == 'pc')
          .toList();
      expect(pcs.length, 1);
      expect(jsStr(pcs.single['seat']), 'p2');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ④ 载荷喂 domain → order
  // ----------------------------------------------------------
  group('④ domain 侧真实生效', () {
    testWidgets('点部署后 host.state.combat.order = 怪槽 + PC 槽，首槽 isCurrent',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      f.clearSent();
      await _tap(tester, find.byKey(CombatSheetKeys.monsterToggle('la1')));
      await _tap(tester, find.byKey(CombatSheetKeys.deploy));
      final p = _startPayload(f);

      // 再把同一份载荷显式喂一次权威端（loopback host 应用），双保险。
      await f.kpSession.hostAction('combat.start', p);
      await tester.pump();

      final combat = asMap(f.hostState()['combat']);
      final order = asList(combat['order']);
      expect(order.length, 1 + f.playerSeats.length,
          reason: 'order 长度 = 1 个怪槽 + 2 个 PC 槽');
      final kinds = order.map((s) => jsStr(asMap(s)['kind'])).toList();
      expect(kinds.contains('pc'), isTrue, reason: '必须真的有玩家槽');
      expect(kinds.contains('monster'), isTrue, reason: '必须真的有怪物槽');
      expect(combat['turn'], 0);
      expect(combat['round'], 1);
      expect(isCombat(f.hostState()), isTrue);

      final rows = combatRows(f.hostState(), isKp: true);
      expect(rows.length, order.length);
      expect(rows.first.isCurrent, isTrue, reason: '第一个槽高亮');
      expect(rows.where((r) => r.isCurrent).length, 1);

      // ★ P16 KP-4① 正面回归：combatStart 必须把候选池的 HP 补进 public，
      //   否则 KP 侧会看到「怪物 HP 0」（真机问题 4 的原始症状）。
      final monsterSlot =
          order.map(asMap).firstWhere((s) => jsStr(s['kind']) == 'monster');
      final monsterPub = asMap(monsterSlot['public']);
      expect(monsterPub['hp'], isNotNull,
          reason: 'KP-4①：怪物槽的 public 必须带 hp');
      expect((monsterPub['hp']! as num) > 0, isTrue,
          reason: 'KP-4①：怪物 HP 必须 > 0，不能是 0');
      expect((monsterPub['hpMax']! as num) > 0, isTrue);
      final monsterRow = rows.firstWhere((r) => r.kind == 'monster');
      expect(monsterRow.hp, greaterThan(0),
          reason: 'KP-4①：combatRows 读到的怪物 HP 必须 > 0');
      expect(monsterRow.hpMax, greaterThan(0));
      expect(monsterRow.hpHidden, isFalse, reason: 'KP 视角怪物 HP 不该隐藏');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑤ T-30：三视角可点性恒等闸门
  // ----------------------------------------------------------
  group('⑤ T-30 三视角 enabled ⟺ gate.can', () {
    testWidgets('P17 P-4：scene.mode（工具栏）三视角不渲染；combat.start（弹层）三视角都恒等',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      for (final seat in <String>[kHostSeat, 'p1', 'sp1']) {
        await tester.pumpWidget(_hostApp(f, const GpToolbar(), seat: seat));
        await tester.pump();
        final Finder modeBtn = find.byKey(RoomKeys.action('scene.mode'));
        expect(modeBtn, findsNothing,
            reason: 'P17 P-4：$seat 工具栏不再渲染恒灰的 scene.mode');

        await tester.pumpWidget(_hostApp(f, const CombatSheet(), seat: seat));
        await tester.pump();
        final Finder startBtn =
            find.byKey(RoomKeys.action('combat.start'));
        expect(startBtn, findsOneWidget);
        expect(tester.widget<RoomTap>(startBtn).enabled,
            f.controllerOf(seat).gate.can('combat.start'),
            reason: '$seat combat.start 可点性漂移');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑥ 战斗态 → combat.end
  // ----------------------------------------------------------
  group('⑥ 战斗态点按钮走 combat.end', () {
    testWidgets('P17 P-4：scene.mode 入口已删；战斗态经战斗弹层 combat.end 结束',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await f.kpSession.hostAction(
          'scene.mode', <String, Object?>{'mode': RoomMode.combat});
      // 工具栏（scene.mode 所在地）三视角已删。
      await tester.pumpWidget(_hostApp(f, const GpToolbar()));
      await tester.pump();
      expect(isCombat(f.sessionOf(kHostSeat).state), isTrue,
          reason: '前提：当前是战斗态');
      expect(find.byKey(RoomKeys.action('scene.mode')), findsNothing,
          reason: 'P17 P-4：战斗态也不渲染 scene.mode');

      // 结束战斗入口在战斗弹层（`sheet_combat.dart` 的 combat.end）。
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      expect(find.byKey(RoomKeys.action('combat.end')), findsOneWidget);

      f.clearSent();
      await _tap(tester, find.byKey(RoomKeys.action('combat.end')));
      expect(f.lastSent(action: 'combat.end'), isNotNull,
          reason: '老 APP :286-289 口径：结束战斗走 combat.end');
      expect(f.lastSent(action: 'scene.mode'), isNull,
          reason: '战斗态不许再直发 scene.mode');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑦ 轮次信息栏（老 APP initiativeBar）
  // ----------------------------------------------------------
  group('⑦ 战斗轮次信息栏', () {
    /// 用 UI 真实部署一场战斗（1 怪 + 2 PC），返回夹具。
    Future<RoomUiFixture> deployCombat(WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      await _tap(tester, find.byKey(CombatSheetKeys.monsterToggle('la1')));
      await _tap(tester, find.byKey(CombatSheetKeys.deploy));
      return f;
    }

    testWidgets('开战后 strip 可见 / header 老 APP 口径 / 首槽高亮 / next 后右移',
        (WidgetTester tester) async {
      final f = await deployCombat(tester);
      await tester.pumpWidget(_hostApp(f, const GpCombatList()));
      await tester.pump();

      expect(find.byKey(GpCombatKeys.strip), findsOneWidget,
          reason: '进入战斗后应能看到行动顺序条');
      final header0 = tester
          .widget<Text>(find.byKey(GpCombatKeys.stripHeader))
          .data;
      expect(header0, contains('第 1 轮 · 当前行动：'));
      expect(header0, isNot(contains('当前行动：—')),
          reason: '开战后必须有真实当前行动者');

      final rows0 = combatRows(f.hostState(), isKp: true);
      expect(rows0.length, 3);
      expect(find.byKey(GpCombatKeys.stripCurrent), findsOneWidget);
      final cur0 = tester.getRect(find.byKey(GpCombatKeys.stripCurrent));
      final first0 =
          tester.getRect(find.byKey(GpCombatKeys.stripSlot(rows0.first.id)));
      expect(cur0.left, moreOrLessEquals(first0.left, epsilon: 0.5),
          reason: '高亮应落在第一个槽');

      // combat.next 推进 → 高亮右移、文案同步
      await f.kpSession.hostAction('combat.next');
      await tester.pump();
      final rows1 = combatRows(f.hostState(), isKp: true);
      expect(rows1[1].isCurrent, isTrue, reason: 'turn 推进到第二个槽');
      final cur1 = tester.getRect(find.byKey(GpCombatKeys.stripCurrent));
      final second1 =
          tester.getRect(find.byKey(GpCombatKeys.stripSlot(rows1[1].id)));
      expect(cur1.left, moreOrLessEquals(second1.left, epsilon: 0.5),
          reason: '高亮应右移到第二个槽');
      expect(cur1.left, greaterThan(cur0.left + 0.5),
          reason: '高亮的横向位置确实右移了');
      final header1 = tester
          .widget<Text>(find.byKey(GpCombatKeys.stripHeader))
          .data;
      expect(header1, contains('第 1 轮 · 当前行动：'));
      expect(header1, isNot(header0), reason: '当前行动者变化后文案要同步');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('玩家侧 hpHidden 的怪物槽显示「隐藏」，绝不显示 HP 0',
        (WidgetTester tester) async {
      final f = await deployCombat(tester);
      await tester.pumpWidget(_hostApp(f, const GpCombatList(), seat: 'p1'));
      await tester.pump();

      expect(find.byKey(GpCombatKeys.strip), findsOneWidget);
      final playerRows = combatRows(f.stateOf('p1'), isKp: false);
      final monster = playerRows.firstWhere((r) => r.kind == 'monster');
      expect(monster.hpHidden, isTrue, reason: '前提：玩家侧怪物 HP 未公开');

      final texts = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(GpCombatKeys.stripSlot(monster.id)),
            matching: find.byType(Text),
          ))
          .map((Text t) => t.data ?? '')
          .toList();
      // ★ P13 COMBAT-1：玩家侧怪物/NPC 只显名字（不再用「隐藏」占位）。
      //   核心不变量「绝不把缺键当成 0 画出 HP 数字」逐字保留 +
      //   新增「名字确实可见」正向断言，不放宽。
      expect(texts, contains(monster.name),
          reason: '★ 玩家侧怪物应显示名字（COMBAT-1）');
      expect(texts, isNot(contains('隐藏')),
          reason: '★ 产品真变：不再用「隐藏」占位');
      expect(texts.any((String t) => t.startsWith('HP ')), isFalse,
          reason: '绝不能把缺键当成 0 画出 HP 数字');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑧ 纯函数：新增 initiativeText，roundText 原样保留
  // ----------------------------------------------------------
  group('⑧ 纯视图函数', () {
    test('initiativeText 读 combat.round + 当前槽名；roundText 口径不变', () {
      final state = <String, Object?>{
        'meta': <String, Object?>{'round': 1},
        'combat': <String, Object?>{
          'round': 3,
          'turn': 1,
          'order': <Object?>[
            <String, Object?>{'id': 'a', 'name': '先手', 'kind': 'pc'},
            <String, Object?>{'id': 'b', 'name': '哥布林', 'kind': 'monster'},
            <String, Object?>{'id': 'c', 'name': '调查员', 'kind': 'pc'},
            <String, Object?>{'id': 'd', 'name': '第四人', 'kind': 'pc'},
            <String, Object?>{'id': 'e', 'name': '第五人', 'kind': 'npc'},
          ],
        },
      };
      expect(initiativeText(state), '第 3 轮 · 当前行动：哥布林');
      expect(roundText(state), '第 3 轮 · 行动 2/5',
          reason: 'roundText 必须原样保留');

      final empty = <String, Object?>{
        'meta': <String, Object?>{},
        'combat': <String, Object?>{'order': <Object?>[]},
      };
      expect(initiativeText(empty), '第 1 轮 · 当前行动：—');
    });
  });

  // ----------------------------------------------------------
  // ⑨ 主理人追加：战斗弹层「加单位」也要能填数值（B 批同款口径）
  // ----------------------------------------------------------
  group('⑨ 主理人追加 · 加单位填数值（与 B 批逐字段一致）', () {
    /// 滚到可见后往指定输入框写入文本。
    Future<void> enterField(
        WidgetTester tester, Key key, String text) async {
      final Finder finder = find.byKey(key);
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.enterText(finder, text);
      await tester.pump();
    }

    /// ★ P16 KP-8：点发包按钮 → 加单位弹层里填六字段 → 确定 → 弹层关闭。
    ///
    /// 弹层是唯一入口（内联表单已删），所以这里顺带钉住：
    /// ① 弹层确实弹出来（按 key）；② 取消/确定后的关闭行为正确。
    Future<void> addViaSheet(
      WidgetTester tester,
      Key actionKey, {
      required String name,
      String dex = '50',
      String hp = '10',
      String actions = '1',
      String armor = '0',
      bool npc = false,
    }) async {
      await _tap(tester, find.byKey(actionKey));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(AddActorSheetKeys.root), findsOneWidget,
          reason: 'KP-8：必须先弹出六字段加单位弹层');
      await enterField(tester, AddActorSheetKeys.name, name);
      await enterField(tester, AddActorSheetKeys.dex, dex);
      await enterField(tester, AddActorSheetKeys.hp, hp);
      await enterField(tester, AddActorSheetKeys.actions, actions);
      await enterField(tester, AddActorSheetKeys.armor, armor);
      await _tap(
        tester,
        find.byKey(npc
            ? AddActorSheetKeys.kindNpc
            : AddActorSheetKeys.kindMonster),
      );
      await _tap(tester, find.byKey(AddActorSheetKeys.confirm));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(AddActorSheetKeys.root), findsNothing,
          reason: '确定后弹层必须关闭');
    }

    testWidgets('DEX 33 / HP 27 / 每轮 3 / NPC → combat.actor 载荷逐字段',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();

      // ★ P16 KP-8：内联表单已退役 —— 7 个字段 key 一个都不许再渲染。
      for (final Key k in <Key>[
        CombatSheetKeys.actorName,
        CombatSheetKeys.actorDex,
        CombatSheetKeys.actorHp,
        CombatSheetKeys.actorActions,
        CombatSheetKeys.actorKind,
        CombatSheetKeys.actorKindMonster,
        CombatSheetKeys.actorKindNpc,
      ]) {
        expect(find.byKey(k), findsNothing,
            reason: 'KP-8：内联表单 $k 已随弹层改造退役');
      }
      // 两个弹层入口仍都在（功能没丢，只是改成弹窗填写）。
      expect(find.byKey(RoomKeys.action('combat.actor')), findsOneWidget);
      expect(find.byKey(RoomKeys.action('combat.pool.set')), findsOneWidget);

      // ★ T-30：两个加单位按钮的 enabled 恰好恒等闸门。
      for (final String op in <String>['combat.actor', 'combat.pool.set']) {
        expect(
          tester.widget<RoomTap>(find.byKey(RoomKeys.action(op))).enabled,
          f.controllerOf(kHostSeat).gate.can(op),
          reason: '$op 可点性漂移',
        );
      }

      f.clearSent();
      await addViaSheet(
        tester,
        RoomKeys.action('combat.actor'),
        name: '追猎者',
        dex: '33',
        hp: '27',
        actions: '3',
        npc: true,
      );

      final sent = f.lastSent(action: 'combat.actor');
      expect(sent, isNotNull, reason: '弹层确定后必须发 combat.actor');
      final actor = asMap(asMap(sent!['p'])['actor']);
      expect(actor['dex'], 33);
      expect(actor['hp'], 27);
      expect(actor['hpMax'], 27, reason: 'HP 同值写 hpMax（老 APP 口径）');
      expect(actor['actionsPerRound'], 3);
      expect(jsStr(actor['kind']), 'npc');
      expect(jsStr(actor['name']), '追猎者');
      // ★ KP-8：护甲是新增契约字段，默认 0 必须出现在载荷里。
      expect(actor.containsKey('armor'), isTrue,
          reason: 'KP-8：combat.actor 载荷必须带 armor');
      expect(actor['armor'], 0, reason: 'KP-8：未填护甲时默认 0');
      expect(jsStr(actor['id']).isNotEmpty, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('非法数字静默回落默认（dex 50 / hp 10 / 每轮 1 / 护甲 0，不弹错）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();

      f.clearSent();
      await addViaSheet(
        tester,
        RoomKeys.action('combat.actor'),
        name: '非法怪',
        dex: 'abc',
        hp: 'x9',
        actions: '',
        armor: 'w',
      );

      final sent = f.lastSent(action: 'combat.actor');
      expect(sent, isNotNull);
      final actor = asMap(asMap(sent!['p'])['actor']);
      expect(actor['dex'], 50);
      expect(actor['hp'], 10);
      expect(actor['hpMax'], 10);
      expect(actor['actionsPerRound'], 1);
      expect(jsStr(actor['kind']), 'monster');
      expect(actor['armor'], 0, reason: 'KP-8：护甲非法值回落 0');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('每轮次数静默夹 1–10；combat.pool.set 仍是整体替换候选池',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      _addMonster(f); // 候选池里放 1 只，验证 pool.set 取的是候选池全量
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();

      f.clearSent();
      await addViaSheet(
        tester,
        RoomKeys.action('combat.actor'),
        name: '超频怪',
        actions: '99',
      );
      final actor =
          asMap(asMap(f.lastSent(action: 'combat.actor')!['p'])['actor']);
      expect(actor['actionsPerRound'], 10, reason: '超过 10 静默夹到 10');

      // ★ pool.set：先弹层、再发包；载荷 = 既有候选池 + 弹层这一只。
      f.clearSent();
      await addViaSheet(
        tester,
        RoomKeys.action('combat.pool.set'),
        name: '池怪',
        dex: '40',
        hp: '12',
        actions: '2',
        armor: '3',
      );
      final pool = asMap(f.lastSent(action: 'combat.pool.set')!['p']);
      final actors = asList(pool['actors']).map(asMap).toList();
      expect(actors.length, 2,
          reason: 'combat.pool.set 必须是「既有候选 1 + 弹层新增 1」的整体替换');
      // 既有候选原样保留在首位。
      expect(jsStr(actors.first['id']), 'la1');
      expect(jsStr(actors.first['name']), '哥布林');
      // 最后一项就是弹层里填的那只 —— 逐字段，不许降级成「非空/长度变了」。
      final added = actors.last;
      expect(jsStr(added['name']), '池怪');
      expect(jsStr(added['kind']), 'monster');
      expect(added['dex'], 40);
      expect(added['hp'], 12);
      expect(added['hpMax'], 12);
      expect(added['actionsPerRound'], 2);
      expect(added['armor'], 3, reason: 'KP-8：护甲必须一路传到 pool.set');
      expect(jsStr(added['id']).isNotEmpty, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑩ 主理人裁决：空池兼容口径的 hint 与 QA 复核要点
  // ----------------------------------------------------------
  group('⑩ 主理人裁决 · 空池兼容 hint', () {
    testWidgets('空池 → hint 明说纯玩家战斗；有怪未勾 → 门禁严格生效',
        (WidgetTester tester) async {
      final f = await _boot(tester);

      // 场景 A：候选池完全为空 → hint 必须明说「将以纯玩家战斗开始」，
      // 且不得出现「至少选择 1 个怪物/NPC」提示（裁决 QA 复核要点）。
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      final RoomTap emptyBtn = tester.widget<RoomTap>(
          find.byKey(RoomKeys.action('combat.start')));
      expect(emptyBtn.hint, contains('纯玩家战斗'),
          reason: '空池 hint 不能让用户以为点了没反应 / 莫名跳进战斗');
      expect(emptyBtn.hint, isNot(contains('至少选择 1 个怪物/NPC')),
          reason: 'QA 复核：空池时不得出现门禁提示');
      expect(emptyBtn.enabled,
          f.controllerOf(kHostSeat).gate.can('combat.start'),
          reason: 'hint 改动绝不许波及 enabled（T-30）');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // 场景 B：候选池非空但一只未勾 → 门禁严格生效（hint 提示 + notice）。
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      final RoomTap gatedBtn = tester.widget<RoomTap>(
          find.byKey(RoomKeys.action('combat.start')));
      expect(gatedBtn.hint, contains('至少选择 1 个怪物/NPC'),
          reason: 'QA 复核：候选池非空时门禁必须严格生效');
      expect(gatedBtn.enabled,
          f.controllerOf(kHostSeat).gate.can('combat.start'),
          reason: 'T-30：门禁只进 hint / onTap，不进 enabled');
      f.clearSent();
      await _tap(tester, find.byKey(RoomKeys.action('combat.start')));
      expect(f.lastSent(action: 'combat.start'), isNull,
          reason: '候选池非空却不勾怪，必须挡住发包');
      expect(f.localOf(kHostSeat).notice,
          contains('至少选择 1 个怪物/NPC'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑪ KP 战斗态：素材舞台格内「战斗信息 ⇄ 舞台」切换（P16 KP-4②）
  // ----------------------------------------------------------
  group('⑪ KP 战斗态 gpMap 格内的列表 / 舞台切换', () {
    testWidgets('默认显示战斗列表；点标题行开关切到舞台，再点切回',
        (WidgetTester tester) async {
      final f = await _boot(tester, w: 1280, h: 800);
      _addMonster(f);
      await tester.pumpWidget(_hostApp(f, const CombatSheet()));
      await tester.pump();
      await _tap(tester, find.byKey(CombatSheetKeys.monsterToggle('la1')));
      await _tap(tester, find.byKey(CombatSheetKeys.deploy));
      expect(isCombat(f.hostState()), isTrue, reason: '前置：已进入战斗态');

      f.pageBuilder = (String s, String r) => const RoomGamePage();
      await tester.pumpWidget(f.pageOf(kHostSeat));
      await tester.pump();

      final Finder mapSlot = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap));
      final Finder listInMap =
          find.descendant(of: mapSlot, matching: find.byType(GpCombatList));
      final Finder stageInMap =
          find.descendant(of: mapSlot, matching: find.byType(GpMapStage));

      // ① 默认（combatPanelCollapsed == false）→ 战斗列表。
      expect(f.localOf(kHostSeat).combatPanelCollapsed, isFalse,
          reason: '默认应是「展开看列表」');
      expect(listInMap, findsOneWidget,
          reason: 'KP-4②：战斗态下 gpMap 格默认渲染战斗列表');
      expect(stageInMap, findsNothing, reason: '列表展开时舞台不渲染');
      expect(
        find.descendant(of: mapSlot, matching: find.text('战斗信息')),
        findsOneWidget,
        reason: '格内要有「战斗信息」标题行',
      );
      expect(find.byKey(RoomGamePage.combatToggleKey), findsOneWidget,
          reason: '标题行里的展开/收起开关必须在');

      // ② 点「收起」→ 回到舞台（KP 才能摆位）。
      await _tap(tester, find.byKey(RoomGamePage.combatToggleKey));
      expect(f.localOf(kHostSeat).combatPanelCollapsed, isTrue);
      expect(stageInMap, findsOneWidget,
          reason: 'KP-4②：收起后应回到素材舞台');
      expect(listInMap, findsNothing);

      // ③ 再点一次 → 回到列表（开关是双向的，不是一次性）。
      await _tap(tester, find.byKey(RoomGamePage.combatToggleKey));
      expect(f.localOf(kHostSeat).combatPanelCollapsed, isFalse);
      expect(listInMap, findsOneWidget);
      expect(stageInMap, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑫ G-1（QA 复核后补强）：KP-4①「怪物 HP 全显示 0」的正面守卫
  //
  // QA 实测：把 `combatStart` 里「缺 hp/hpMax 时从 localActors 补全」改成
  // 恒写 0 后，本文件原 19 条**一条都不红** —— 原 ④ 组取到的值被
  // `combatRows` 兼容层 / PC 槽兜住了，断言恒真。所以这里补三条只咬
  // 「补全源消失」与「取值层级」的用例。
  // ----------------------------------------------------------
  group('⑫ G-1 怪物 HP 的正面守卫（缺 hp 补全 / 取值层级）', () {
    testWidgets('★ combat.start 载荷缺 hp/hpMax → 必须从权威候选池补 13，不是 0',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await _startCombatFromPoolWithoutHp(f, poolHp: 13);

      final order = asList(asMap(f.hostState()['combat'])['order']);
      expect(order.length, 1, reason: '前置：应只有 1 个战斗槽');
      final slot = asMap(order.single);
      expect(jsStr(slot['id']), 'm9');
      final pub = asMap(slot['public']);
      // 精确值，不是 greaterThan(0)：补给源是候选池的 13，别处没有兜底。
      expect(pub['hp'], 13,
          reason: 'KP-4①：缺 hp 必须补候选池原值 13（写成 0 就是用户报的 bug）');
      expect(pub['hpMax'], 13, reason: 'KP-4①：hpMax 同理');
    });

    testWidgets('★ 同一份权威态渲染：该行 HP 文本必须是「HP 13 / 13」，不是 0 也非「隐藏」',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await _startCombatFromPoolWithoutHp(f, poolHp: 13);

      // 派生层先钉死（渲染层的输入）。
      final row = combatRows(f.hostState(), isKp: true).single;
      expect(row.hp, 13);
      expect(row.hpMax, 13);
      expect(row.hpHidden, isFalse);

      await tester.pumpWidget(_hostApp(f, const GpCombatList()));
      await tester.pump();

      expect(find.byKey(GpCombatKeys.row('m9')), findsOneWidget);
      expect(find.text('HP 13 / 13'), findsOneWidget,
          reason: 'KP-4①：战斗列表必须显示真实 HP，不能是 0');
      expect(find.text('HP 0 / 0'), findsNothing,
          reason: '「怪物 HP 全显示 0」正是用户报的症状');
      expect(find.text('隐藏'), findsNothing,
          reason: 'KP 视角怪物 HP 不该是「隐藏」');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    test('★ combatRows：public 只带 hpPublic:false、hp 在顶层 → KP 取顶层值，不被抹成 0', () {
      // 形状：裁剪后的扁平槽 / 旧存档 —— `public` 存在但**没有 hp 键**，
      // 真值在顶层。旧实现在 KP 补全分支写 `roomNumber(secret['hp'], hp)`，
      // 而 `roomNumber(null, 7)` 恒得 0（`_toNumber(null) → 0` 不是 fallback），
      // 会把 7 抹成 0。这条就是那个修复的正面守卫。
      Map<String, Object?> slotWith(Map<String, Object?> extra) =>
          <String, Object?>{
            'id': 'm9',
            'name': '深潜者',
            'kind': 'monster',
            'hp': 7,
            'hpMax': 9,
            'public': <String, Object?>{'hpPublic': false},
            ...extra,
          };
      Map<String, Object?> stateOf(Map<String, Object?> slot) => <String, Object?>{
            'combat': <String, Object?>{
              'order': <Object?>[slot],
              'turn': 0,
            },
            'meta': <String, Object?>{},
          };

      final plain = combatRows(stateOf(slotWith(const <String, Object?>{})),
              isKp: true)
          .single;
      expect(plain.hp, 7,
          reason: 'KP-4①：secret/kpOnly 缺键时必须保持顶层 hp=7（写成 roomNumber(null, hp) 会得 0）');
      expect(plain.hpMax, 9);
      expect(plain.hpHidden, isFalse, reason: 'KP 侧补全后应展示真实值，不是「隐藏」');

      // 有 secret 时 secret 优先（覆盖，而不是叠成 0）。
      final withSecret = combatRows(
        stateOf(slotWith(<String, Object?>{
          'secret': <String, Object?>{'hp': 4},
        })),
        isKp: true,
      ).single;
      expect(withSecret.hp, 4, reason: 'KP-4①：secret.hp 有值时以 secret 为准');

      // 玩家视角绝不越权读顶层真值（结构上就看不到）。
      final playerRow = combatRows(
        stateOf(slotWith(const <String, Object?>{})),
        isKp: false,
      ).single;
      expect(playerRow.hpHidden, isTrue,
          reason: 'hpPublic:false 的槽在玩家侧必须「隐藏」，不能泄露 7');
    });
  });
}
