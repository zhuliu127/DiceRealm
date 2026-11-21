// ============================================================
// create_extra_steps_test.dart — 资产 / 战斗装备 / 随身物品三步（widget 级）
//
// 钉住的硬约束：
//   · 硬约束 1：卡片数据契约不变（三类数据写进既有数组）
//   · 硬约束 2：信用评级越界不写进模型（拦在输入层，且输入框不重建）
//   · 硬约束 3：「去修复 →」跳到正确步骤
//   · 硬约束 4：非法武器使用技能不可选
//   · 硬约束 5：9 步全流程保存后 normalize → recalc → 落盘读回一致
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/normalize.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/ui/create/steps/step_summary.dart';
import 'package:dice_realm/ui/create/wizard_checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 走到第 4 步（资产与信用评级）
Future<void> _gotoAssets(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('fab_new_card')));
  await tester.pumpAndSettle();
  // ★ P9 需求 5：先选规则，向导跳过 rules 步，直接落在「基本资料」。
  await tapKey(tester, 'rule_pick_coc7');

  await tester.enterText(find.byKey(const Key('field_name')), '装备测试');
  await tester.enterText(find.byKey(const Key('field_player')), '老王');
  await tester.enterText(find.byKey(const Key('field_age')), '32');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn_pick_occupation')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('field_occ_search')), '法官');
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, '法官').first);
  await tester.pumpAndSettle();
  await tapKey(tester, 'btn_next'); // 1 → 2

  for (final k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
    'luck',
  ]) {
    await tester.enterText(find.byKey(Key('attr_$k')), '50');
  }
  await tester.pumpAndSettle();
  await tapKey(tester, 'btn_next'); // 2 → 3（资产）
}

/// 从资产页一路走到保存（中间各步都接受默认，不做额外操作）
Future<void> _walkToSave(WidgetTester tester, {bool spendPoints = true}) async {
  await tapKey(tester, 'btn_next'); // → 技能
  if (spendPoints) await tapKey(tester, 'btn_auto_spend');
  await tapKey(tester, 'btn_next'); // → 战斗
  await tapKey(tester, 'btn_next'); // → 物品
  await tapKey(tester, 'btn_next'); // → 背景
  await tapKey(tester, 'btn_next'); // → 概要
  await tapKey(tester, 'btn_next'); // 保存
}

void main() {
  group('硬约束 2：信用评级拦在输入层', () {
    testWidgets('超出职业区间 → 显示错误、输入框仍在（焦点不丢）、模型不写', (tester) async {
      final repo = await pumpApp(tester);
      await _gotoAssets(tester);

      await tester.enterText(find.byKey(const Key('credit_input')), '99');
      await tester.pumpAndSettle();

      // 错误来自职业区间（法官 50-80）
      expect(find.textContaining('信用评级需在'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('credit_input')),
      );
      expect(field.controller!.text, '99', reason: '非法值不该被吞掉，玩家要能接着改');

      await _walkToSave(tester);

      final saved = repo.alive.single;
      expect(jsNum(saved.assets['creditRating']), 0, reason: '越界值绝不能落库');
    });

    testWidgets('合法值写入模型并同步到 credit 技能（占职业点）', (tester) async {
      final repo = await pumpApp(tester);
      await _gotoAssets(tester);

      await tester.enterText(find.byKey(const Key('credit_input')), '60');
      await tester.pumpAndSettle();
      expect(find.textContaining('合法'), findsOneWidget);
      expect(find.textContaining('本次占用职业点 60 点'), findsOneWidget);

      await _walkToSave(tester);

      final saved = repo.alive.single;
      expect(jsNum(saved.assets['creditRating']), 60);
      expect(jsStr(saved.assets['spendingLevel']), '小康');
      final credit = saved.skills
          .map(asMap)
          .firstWhere((s) => jsStr(s['id']) == 'credit');
      expect(jsNum(credit['occ']), 60);
      expect(jsNum(occupationPoints(saved)['used']), greaterThanOrEqualTo(60));
    });

    testWidgets('现金清空不算 0：不写模型', (tester) async {
      final repo = await pumpApp(tester);
      await _gotoAssets(tester);

      await tester.enterText(find.byKey(const Key('cash_input')), '500');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cash_input')), '');
      await tester.pumpAndSettle();
      await _walkToSave(tester);

      expect(jsNum(repo.alive.single.assets['cash']), 500, reason: '清空只是"没提交"');
    });
  });

  group('硬约束 4：武器使用技能是受约束的清单', () {
    testWidgets('自定义武器表单里选不到「心理学」', (tester) async {
      await pumpApp(tester);
      await _gotoAssets(tester);
      await tapKey(tester, 'btn_next'); // → 技能
      await tapKey(tester, 'btn_auto_spend');
      await tapKey(tester, 'btn_next'); // → 战斗

      await tester.tap(find.byKey(const Key('btn_custom_weapon')));
      await tester.pumpAndSettle();
      expect(find.text('自定义武器'), findsOneWidget);

      await tester.tap(find.byKey(const Key('weapon_skill')));
      await tester.pumpAndSettle();

      expect(find.textContaining('心理学'), findsNothing);
      expect(find.textContaining('斗殴'), findsWidgets);
      expect(find.textContaining('手枪'), findsWidgets);
    });

    testWidgets('从武器库添加一把手枪：写进 weapons 且结构完整', (tester) async {
      final repo = await pumpApp(tester);
      await _gotoAssets(tester);
      await tapKey(tester, 'btn_next');
      await tapKey(tester, 'btn_auto_spend');
      await tapKey(tester, 'btn_next'); // → 战斗

      await tester.tap(find.byKey(const Key('btn_pick_weapon')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weapon_lib_search')), '左轮');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weapon_lib_0')));
      await tester.pumpAndSettle();

      await tapKey(tester, 'btn_next'); // → 物品
      await tapKey(tester, 'btn_next'); // → 背景
      await tapKey(tester, 'btn_next'); // → 概要
      await tapKey(tester, 'btn_next'); // 保存

      final weapons = asList(repo.alive.single.raw['weapons'])
          .map(asMap)
          .toList();
      expect(weapons.length, 1);
      final w = weapons.single;
      expect(jsStr(w['name']), contains('左轮手枪'));
      for (final k in <String>[
        'name',
        'skill',
        'damage',
        'range',
        'pierce',
        'perRound',
        'ammo',
        'malfunction',
        'qty',
      ]) {
        expect(w.containsKey(k), isTrue, reason: '武器条目缺键 $k');
      }
      expect(jsNum(w['qty']), 1);
    });
  });

  group('随身物品', () {
    testWidgets('空态文案 + 预设一键添加 + 数据落库', (tester) async {
      final repo = await pumpApp(tester);
      await _gotoAssets(tester);
      await tapKey(tester, 'btn_next');
      await tapKey(tester, 'btn_auto_spend');
      await tapKey(tester, 'btn_next'); // → 战斗
      await tapKey(tester, 'btn_next'); // → 物品

      expect(find.text('背包是空的'), findsOneWidget);
      await tapKey(tester, 'gear_preset_0'); // 手电筒
      expect(find.text('背包是空的'), findsNothing);

      await tapKey(tester, 'btn_next'); // → 背景
      await tapKey(tester, 'btn_next'); // → 概要
      await tapKey(tester, 'btn_next'); // 保存

      final items = asList(repo.alive.single.raw['items']).map(asMap).toList();
      expect(items.length, 1);
      expect(items.single.keys.toSet(), <String>{
        'name',
        'quantity',
        'description',
      });
      expect(jsStr(items.single['name']), '手电筒');
      expect(jsNum(items.single['quantity']), 1);
    });

    testWidgets('数量清空 → 回到 1（旧版 parseInt(v,10) || 1）', (tester) async {
      final repo = await pumpApp(tester);
      await _gotoAssets(tester);
      await tapKey(tester, 'btn_next');
      await tapKey(tester, 'btn_auto_spend');
      await tapKey(tester, 'btn_next');
      await tapKey(tester, 'btn_next'); // → 物品

      await tapKey(tester, 'btn_add_item');
      await tester.enterText(find.byKey(const Key('item_name_0')), '绳子');
      await tester.enterText(find.byKey(const Key('item_qty_0')), '5');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('item_qty_0')), '');
      await tester.pumpAndSettle();

      await tapKey(tester, 'btn_next');
      await tapKey(tester, 'btn_next');
      await tapKey(tester, 'btn_next');

      final item = asMap(asList(repo.alive.single.raw['items']).single);
      expect(jsStr(item['name']), '绳子');
      expect(jsNum(item['quantity']), 1);
    });
  });

  group('硬约束 3：「去修复 →」跳到正确步骤', () {
    testWidgets('概要页每一行都按映射跳到对应步骤 id（逐条点）', (tester) async {
      useTallScreen(tester);
      // 造一张「属性齐备、但信用评级没分、技能点超额、没有装备」的卡：
      // 这样规则层 10 项里的各项校验才会真正跑起来（attrsReady 才会校验技能/信用）
      final card = Character(newCharacter());
      for (final k in <String>[
        'str',
        'con',
        'siz',
        'dex',
        'app',
        'int',
        'pow',
        'edu',
        'luck',
      ]) {
        card.attributes[k] = 50;
      }
      card.basicInfo['age'] = 32;
      card.raw['age'] = 32;
      card.raw['occupationId'] = 'occ67';
      card.raw['skills'] = <Object?>[
        <String, Object?>{
          'key': 'spot_hidden',
          'id': 'spot_hidden',
          'name': '侦查',
          'sub': '',
          'base': 25,
          'growth': 0,
          'occ': 300,
          'int': 200,
          'total': 525,
          'custom': false,
          'desc': '',
        },
      ];
      recalc(card);

      final failing = wizardChecks(card)
          .where((c) => !c.ok && c.stepId != null)
          .toList();
      expect(failing.length, greaterThanOrEqualTo(6), reason: '这张卡应该有一堆问题');

      final jumped = <String>[];
      // StepSummary 内嵌 SharePanel（P3-B），裸 MaterialApp 宿主缺 ShareScope
      // 会命中断言；补上与 DiceRealmApp 同构的三个 Scope（仅修夹具）。
      final host = await wrapWithScopes(
        MaterialApp(
          home: Scaffold(
            body: StepSummary(draft: card, onJumpTo: jumped.add),
          ),
        ),
      );
      await tester.pumpWidget(host);
      await tester.pumpAndSettle();

      for (final check in failing) {
        final finder = find.byKey(Key('fix_${check.label}'));
        expect(finder, findsOneWidget, reason: '「${check.label}」应该有「去修复」按钮');
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expect(
          jumped.last,
          check.stepId,
          reason: '「${check.label}」应跳到 ${check.stepId}',
        );
      }

      // 跨页覆盖：basics / assets / skills / combat / gear 都点到了
      expect(
        jumped.toSet().containsAll(<String>[
          'basics',
          'assets',
          'skills',
          'combat',
          'gear',
        ]),
        isTrue,
      );
      // 明确几条代表性的映射（不是页序数字，而是步骤 id）
      final byLabel = <String, String>{};
      for (var i = 0; i < failing.length; i++) {
        byLabel[failing[i].label] = jumped[i];
      }
      expect(byLabel['角色姓名已填写'], 'basics');
      expect(byLabel['信用评级在职业范围内'], 'assets');
      expect(byLabel['职业技能点未超额'], 'skills');
      expect(byLabel['已添加武器'], 'combat');
      expect(byLabel['随身物品已填写'], 'gear');
    });

    testWidgets('真实向导里点「去修复」会切到那一页（进度条跟着变）', (tester) async {
      await pumpApp(tester);
      await _gotoAssets(tester);
      await tapKey(tester, 'btn_next'); // → 技能
      await tapKey(tester, 'btn_auto_spend');
      await tapKey(tester, 'btn_next'); // → 战斗
      await tapKey(tester, 'btn_next'); // → 物品
      await tapKey(tester, 'btn_next'); // → 背景
      await tapKey(tester, 'btn_next'); // → 概要（8 / 8）

      expect(find.text('8 / 8'), findsOneWidget);
      // 「已添加武器」不通过 → 应跳回第 6 步（战斗装备）
      await scrollTo(tester, 'fix_已添加武器');
      await tester.tap(find.byKey(const Key('fix_已添加武器')));
      await tester.pumpAndSettle();
      expect(find.text('5 / 8'), findsOneWidget);
    });
  });

  group('硬约束 5：9 步全流程 + 落盘读回一致', () {
    testWidgets('走完 9 步：三类数据都在，normalize → recalc 后读回不变', (tester) async {
      final repo = await pumpApp(tester);
      await _gotoAssets(tester);

      // 4 资产
      await tester.enterText(find.byKey(const Key('credit_input')), '60');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cash_input')), '500');
      await tapKey(tester, 'btn_next'); // → 技能

      // 5 技能
      await tapKey(tester, 'btn_auto_spend');
      await tapKey(tester, 'btn_next'); // → 战斗

      // 6 战斗装备：一把武器 + 一件防具 + 一辆载具
      await tester.tap(find.byKey(const Key('btn_pick_weapon')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weapon_lib_search')), '手枪');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weapon_lib_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_pick_armor')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('armor_lib_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_pick_vehicle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vehicle_lib_0')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'btn_next'); // → 物品

      // 7 随身物品
      await tapKey(tester, 'gear_preset_3'); // 打火机
      await tapKey(tester, 'btn_next'); // → 背景

      // 8 背景（留空也能走）
      await tapKey(tester, 'btn_next'); // → 概要
      // 概要 → 保存（保存后回首页，见 P9 需求 8）
      await tapKey(tester, 'btn_next');

      expect(repo.alive.length, 1);
      final saved = repo.alive.single;

      // ---- 三类数据都在 ----
      expect(asList(saved.raw['weapons']).length, 1);
      expect(asList(saved.raw['armors']).length, 1);
      expect(asList(saved.raw['vehicles']).length, 1);
      expect(asList(saved.raw['items']).length, 1);
      expect(jsNum(saved.assets['creditRating']), 60);
      expect(jsNum(saved.assets['cash']), 500);

      // ---- normalize 幂等、recalc 幂等（落盘后再读一遍不漂移）----
      final before = jsonEncode(saved.raw);
      final again = Character(saved.clone().raw);
      normalize(again);
      recalc(again);
      expect(
        jsonEncode(again.raw),
        before,
        reason: 'normalize + recalc 必须幂等，否则每次保存都会漂移',
      );
    });
  });
}
