// ============================================================
// create_flow_widget_test.dart — 新建角色向导的端到端（widget 级）
//
// 覆盖四条业务约束：
//   ① 九步能走完（含资产 / 战斗 / 随身物品 / 背景），保存后落到 repo 并出现在首页
//   ② 非法属性输入在提交前就被拦住（不会走进原码 ATT_MAP 的异常路径）
//   ③ 技能点没分完不能进下一步
//   ④ 撕卡（死亡 / 永久疯狂）的卡只出现在英灵殿
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/ui/art.dart' show Art, ArtImage;
import 'package:dice_realm/ui/create/rule_pick_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 9 项属性全部填成同一个值（默认 50 → 合计 450，落在 540 上限内）
Future<void> _fillAttrs(WidgetTester tester, [String value = '50']) async {
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
    await tester.enterText(find.byKey(Key('attr_$k')), value);
  }
  await tester.pumpAndSettle();
}

/// 第 2 步：填完基础信息并选职业（默认用法官 —— 本职技能全是固定项，无需勾选）
Future<void> _fillBasics(
  WidgetTester tester, {
  String name = '阿米蒂奇',
  String player = '老王',
  String age = '32',
  String occ = '法官',
}) async {
  await tester.enterText(find.byKey(const Key('field_name')), name);
  await tester.enterText(find.byKey(const Key('field_player')), player);
  await tester.enterText(find.byKey(const Key('field_age')), age);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('btn_pick_occupation')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('field_occ_search')), occ);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, occ).first);
  await tester.pumpAndSettle();
}

/// 从首页进新建向导，走到「属性分配」那一步
///
/// ★ P9 需求 5：首页入口先到「选择规则系统」页，选完 COC 才进向导
///   （规则已在选择页选定，向导的 rules 步被跳过 → 共 8 步）。
Future<void> _gotoAttrs(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('fab_new_card')));
  await tester.pumpAndSettle();
  await tapKey(tester, 'rule_pick_coc7'); // 规则选择页 → 向导（首步 = 基本资料）
  await _fillBasics(tester);
  await tapKey(tester, 'btn_next'); // 基础信息 → 属性
}

void main() {
  testWidgets('① 九步走完并保存，卡片出现在首页「已保存的角色卡」', (tester) async {
    final repo = await pumpApp(tester);

    // 空态
    expect(find.text('骰境TRPG'), findsOneWidget);
    expect(find.text('还没有角色卡'), findsOneWidget);
    /* ★ P10 需求 4：英灵殿入口图里已经烧进标题与副标题，首页不再叠字，
       只留右下角一个极小计数；空态引导搬进名册的「英灵殿」栏。
       两个状态都断言（首页角标 + 进栏后的空态），没有放宽。 */
    expect(find.text('暂无长眠者'), findsOneWidget);
    await tapKey(tester, 'home_roster_valhalla');
    expect(find.text('还没有英雄长眠于此'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fab_new_card')));
    await tester.pumpAndSettle();
    // ★ P9 需求 5：先到规则选择页（卡片标题 = 规则全名）
    expect(find.text('克苏鲁的呼唤 第七版'), findsOneWidget);
    await tapKey(tester, 'rule_pick_coc7');
    // 规则已选好，向导直接从「基本资料」开始：8 步
    expect(find.text('1 / 8'), findsOneWidget);

    await _fillBasics(tester);
    expect(find.text('法官'), findsOneWidget); // 已选职业显示在按钮上

    await tapKey(tester, 'btn_next'); // 1 → 2（属性）
    await _fillAttrs(tester);
    expect(find.text('合计 450'), findsOneWidget);

    await tapKey(tester, 'btn_next'); // 2 → 3（资产与信用评级）
    expect(find.byKey(const Key('credit_input')), findsOneWidget);
    await tapKey(tester, 'btn_next'); // 3 → 4（职业技能）

    expect(find.text('技能点'), findsOneWidget);

    await tapKey(tester, 'btn_auto_spend'); // 把两池点数分配掉
    await tapKey(tester, 'btn_next'); // 4 → 5（战斗装备，全部非必填）
    await tapKey(tester, 'btn_next'); // 5 → 6（随身物品）
    await tapKey(tester, 'btn_next'); // 6 → 7（角色背景）
    await tapKey(tester, 'btn_next'); // 7 → 8（概要）

    // 概要页：派生值来自 recalc
    expect(find.text('完成度检查'), findsOneWidget);
    expect(find.text('生命 HP'), findsOneWidget);

    await tapKey(tester, 'btn_next'); // 保存
    await tester.pumpAndSettle();

    // 回到首页，卡片已落库
    expect(repo.alive.length, 1, reason: '保存后仓库里应有一张未撕卡的卡');
    final saved = repo.alive.first;
    expect(saved.characterName, '阿米蒂奇');
    expect(saved.playerName, '老王');
    expect(jsNum(saved.basicInfo['age']), 32);
    expect(saved.occupationId, 'occ67');
    expect(jsNum(saved.derivedStats['maxHP']), 10); // (50+50)/10
    expect(jsNum(saved.status['maxHP']), 10);
    // 职业技能点确实分配出去了
    expect(sortedOccUsed(saved), greaterThan(0));

    // ★ P8：卡片收进了二级页「角色档案」，点首页入口进名册再断言。
    //   断言本身（姓名 / 空态消失）没放宽，只是多了一跳导航。
    await tapKey(tester, 'home_roster_entry');
    expect(find.text('阿米蒂奇'), findsOneWidget);
    expect(find.text('还没有角色卡'), findsNothing);
  });

  testWidgets('② 非法属性（53）被本地闸门拦住，不进入下一步', (tester) async {
    await pumpApp(tester);
    await _gotoAttrs(tester);

    await _fillAttrs(tester); // 9 项都填 50
    await tester.enterText(find.byKey(const Key('attr_str')), '53');
    await tester.pumpAndSettle();

    await tapKey(tester, 'btn_next');

    // 仍停在第 3 步（P9 跳过规则步后 = 2 / 8），并给出明确原因
    expect(find.text('2 / 8'), findsOneWidget);
    expect(find.text('力量：必须是 5 的倍数'), findsOneWidget);
  });

  testWidgets('②b 越界值 95 被拦住', (tester) async {
    await pumpApp(tester);
    await _gotoAttrs(tester);
    await _fillAttrs(tester);
    await tester.enterText(find.byKey(const Key('attr_dex')), '95');
    await tester.pumpAndSettle();
    await tapKey(tester, 'btn_next');
    expect(find.text('2 / 8'), findsOneWidget);
    expect(find.text('敏捷：必须在 15-90 之间'), findsOneWidget);
  });

  testWidgets('③ 技能点没分完不能进下一步', (tester) async {
    await pumpApp(tester);
    await _gotoAttrs(tester);
    await _fillAttrs(tester);
    await tapKey(tester, 'btn_next'); // 属性 → 资产
    await tapKey(tester, 'btn_next'); // 资产 → 技能

    // 不做任何分配，直接下一步
    await tapKey(tester, 'btn_next');
    expect(find.text('4 / 8'), findsOneWidget);
    expect(find.textContaining('未分配'), findsOneWidget);
  });

  testWidgets('④ 已撕卡的卡只出现在「英灵殿」', (tester) async {
    final repo = await newMemoryRepo();
    final dead = Character(newCharacter());
    dead.raw['id'] = 'dead0002';
    dead.raw['characterName'] = '长眠者';
    dead.raw['playerName'] = '继承人';
    dead.basicInfo['age'] = 40;
    dead.raw['age'] = 40;
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
      dead.attributes[k] = 50;
    }
    recalc(dead);
    dead.status['body'] = '死亡';
    await repo.save(dead);

    await pumpApp(tester, repo: repo);

    // 首页只留计数 + 空态提示（P8：卡片全在二级页，首页不再铺卡；
    // P10 需求 4：英灵殿那张图自带标题，首页只留右下角的计数角标）
    expect(find.text('还没有角色卡'), findsOneWidget);
    expect(find.text('1 位长眠者'), findsOneWidget);

    // ★ P8：长眠的卡在「角色档案」二级页的「英灵殿」块里
    // ★ P10 需求 2：撕卡只在英灵殿那一栏，入口走英灵殿那张图
    await tapKey(tester, 'home_roster_valhalla');
    expect(find.text('长眠者'), findsOneWidget);
    expect(find.text('☠ 已撕卡'), findsOneWidget);
    // 反向：这一栏里不该出现「已保存」分区的任何东西（分栏真的生效）
    expect(find.text('已保存的角色卡'), findsNothing);

    // 点进详情：有死亡提示
    await tester.tap(find.text('长眠者'));
    await tester.pumpAndSettle();
    expect(find.text('这名调查员已经死亡，卡片已进入英灵殿。'), findsOneWidget);

    // ★ 用户 2026-11-11 真机：死亡提示条里原本并排两个骷髅
    //   （左边「圆圈+骷髅头」素材图 + 右边 ☠ emoji）。只保留左边那枚。
    expect(
      find.byWidgetPredicate(
          (Widget w) => w is Text && (w.data ?? '').trim() == '☠'),
      findsNothing,
      reason: '右侧 emoji 骷髅还在，会和左边印章并排成两个骷髅',
    );
    expect(
      find.byWidgetPredicate(
          (Widget w) => w is ArtImage && w.path == Art.rippedStamp),
      findsOneWidget,
      reason: '左侧「圆圈+骷髅头」图标要保留',
    );
  });

  testWidgets('⑤ 永久疯狂的卡同样进英灵殿', (tester) async {
    final repo = await newMemoryRepo();
    final mad = Character(newCharacter());
    mad.raw['id'] = 'mad00001';
    mad.raw['characterName'] = '疯狂者';
    mad.basicInfo['age'] = 30;
    mad.raw['age'] = 30;
    mad.status['mental'] = <Object?>['永久疯狂'];
    await repo.save(mad);

    await pumpApp(tester, repo: repo);
    // ★ P8：卡片在二级页「角色档案」；P10 需求 2：走英灵殿入口
    await tapKey(tester, 'home_roster_valhalla');
    expect(find.text('疯狂者'), findsOneWidget);
    expect(find.text('☠ 已撕卡'), findsOneWidget);
  });

  testWidgets('首页 FAB 进向导后可以取消返回', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('fab_new_card')));
    await tester.pumpAndSettle();
    // ★ P9 需求 5：入口先到规则选择页
    expect(find.byType(RulePickPage), findsOneWidget);
    await tapKey(tester, 'rule_pick_coc7');
    expect(find.text('基本资料'), findsWidgets);
    await tapKey(tester, 'btn_cancel');
    // ★ P9：取消 = 返回上一页（规则选择页）；再退一步就回首页。
    //   这是产品行为变更（原来取消直接回首页），不是放宽断言 ——
    //   真正的「保存成功后回首页」由需求 8 的用例守着。
    expect(find.byType(RulePickPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('骰境TRPG'), findsOneWidget);
  });
}

/// 职业点已用（详情页/概要页断言用）
int sortedOccUsed(Character c) {
  var used = 0;
  for (final s in c.skills.map(asMap)) {
    used += jsNum(s['occ']);
  }
  return used;
}
