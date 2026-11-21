// ============================================================
// step_background_test.dart — 车卡第 5 步「角色背景」（P1 跳过的那一步）
//
// 对齐 `ui/steps-d.js#background`：
//   · 8 项背景文本（键名与 domain 的 background 结构逐字一致）
//   · 10 套预设背景
//   · 疯狂表（1D10 即时症状 / 总结症状 + 100 条子表）
//
// 顺带钉住「背景症状 → 结构化 madness → 派生『疯狂症状』」这条链路，
// 也就是硬约束 2 的另一面：**症状只在显式点击时产生**。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/rules_coc7.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 走到第 5 步（角色背景）—— 规则 → 基础 → 属性 → 技能 → 背景
Future<void> _gotoBackground(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('fab_new_card')));
  await tester.pumpAndSettle();
  // ★ P9 需求 5：先选规则；向导跳过 rules 步，直接落在「基本资料」。
  await tapKey(tester, 'rule_pick_coc7');

  await tester.enterText(find.byKey(const Key('field_name')), '背景测试');
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
  await tapKey(tester, 'btn_next'); // 3 → 4（技能）

  await tapKey(tester, 'btn_auto_spend');
  await tapKey(tester, 'btn_next'); // 4 → 5（战斗装备）
  await tapKey(tester, 'btn_next'); // 5 → 6（随身物品）
  await tapKey(tester, 'btn_next'); // 6 → 7（角色背景）
}

void main() {
  testWidgets('「角色背景」在向导里是第 7 步（P9 跳过规则步后共 8 步）', (tester) async {
    await pumpApp(tester);
    await _gotoBackground(tester);
    expect(find.text('角色背景'), findsWidgets);
    expect(find.text('7 / 8'), findsOneWidget);
    expect(find.byKey(const Key('bg_field_ideology')), findsOneWidget);
  });

  testWidgets('背景 8 项可填，且保存后落进 background（键名不变）', (tester) async {
    final repo = await pumpApp(tester);
    await _gotoBackground(tester);

    await tester.enterText(
      find.byKey(const Key('bg_field_ideology')),
      '真相必须被记录。',
    );
    await tester.enterText(
      find.byKey(const Key('bg_field_treasuredPossessions')),
      '祖父的钢笔',
    );
    await tester.enterText(
      find.byKey(const Key('bg_field_wounds')),
      '右手掌有一道旧烫伤。',
    );
    await tester.pumpAndSettle();

    await tapKey(tester, 'btn_next'); // 7 → 8（概要）
    await tapKey(tester, 'btn_next'); // 保存

    final saved = repo.alive.single;
    expect(jsStr(saved.background['ideology']), '真相必须被记录。');
    expect(jsStr(saved.background['treasuredPossessions']), '祖父的钢笔');
    expect(jsStr(saved.background['wounds']), '右手掌有一道旧烫伤。');
    // 6 个既有键一个都没改名（这是卡片数据契约的一部分）
    for (final k in <String>[
      'description',
      'ideology',
      'significantPeople',
      'meaningfulPlaces',
      'treasuredPossessions',
      'traits',
      'wounds',
      'phobias',
    ]) {
      expect(
        saved.background.containsKey(k),
        isTrue,
        reason: 'background.$k 必须存在',
      );
    }
  });

  testWidgets('预设背景：点第 1 套 → 8 项文本一次性写入', (tester) async {
    await pumpApp(tester);
    await _gotoBackground(tester);

    await tester.tap(find.byKey(const Key('bg_preset_0')));
    await tester.pumpAndSettle();

    // 预设把姓名为空的情况补上（旧版行为：c.characterName 为空才填）
    final field = tester.widget<TextField>(
      find.byKey(const Key('bg_field_ideology')),
    );
    expect(field.controller!.text, contains('真相必须被记录'));
    final people = tester.widget<TextField>(
      find.byKey(const Key('bg_field_significantPeople')),
    );
    expect(people.controller!.text, contains('主编老陈'));
    expect(
      people.controller!.text,
      contains('｜'),
      reason: '重要之人用 关系｜经过｜现状 的分段格式',
    );
  });

  testWidgets('「重要之人」分段填写：三段拼回同一个键（不新增键名）', (tester) async {
    final repo = await pumpApp(tester);
    await _gotoBackground(tester);

    await tapKey(tester, 'btn_bg_people_segments');
    await tester.enterText(find.byKey(const Key('bg_people_seg_0')), '主编老陈');
    await tester.enterText(find.byKey(const Key('bg_people_seg_1')), '报社上司');
    await tester.enterText(
      find.byKey(const Key('bg_people_seg_2')),
      '他给了我第一份工作',
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('bg_field_significantPeople')),
    );
    expect(field.controller!.text, '主编老陈｜报社上司｜他给了我第一份工作');

    await tapKey(tester, 'btn_next');
    await tapKey(tester, 'btn_next');
    expect(
      jsStr(repo.alive.single.background['significantPeople']),
      '主编老陈｜报社上司｜他给了我第一份工作',
    );
    expect(
      repo.alive.single.background.keys.contains('significantPeopleRelation'),
      isFalse,
      reason: '不许自创键名',
    );
  });

  testWidgets('疯狂表：点「随机」→ 写入「疯狂症状」文本 + 结构化症状', (tester) async {
    final repo = await pumpApp(tester);
    await _gotoBackground(tester);

    await scrollTo(tester, 'btn_madness_table');
    await tapKey(tester, 'btn_madness_table');
    expect(find.text('疯狂表'), findsOneWidget);
    // 主表 10 行 × 两列都在
    expect(find.byKey(const Key('madness_bout_1')), findsOneWidget);
    expect(find.byKey(const Key('madness_sum_10')), findsOneWidget);

    await tapKey(tester, 'btn_madness_random');

    final field = tester.widget<TextField>(
      find.byKey(const Key('bg_field_phobias')),
    );
    expect(field.controller!.text, isNotEmpty);
    expect(field.controller!.text, contains('【'), reason: '格式是 【类型】名字：描述');

    await tapKey(tester, 'btn_next');
    await tapKey(tester, 'btn_next'); // 保存

    final saved = repo.alive.single;
    expect(jsStr(saved.background['phobias']), isNotEmpty);
    expect(asList(saved.raw['madness']).length, 1, reason: '选中的症状同时进结构化数组');
    // 背景症状 → normalize 派生「疯狂症状」（旧版 v2.7.0 行为）
    expect(asList(saved.status['mental']).map(jsStr), contains(mentalSymptom));
  });

  testWidgets('疯狂表第 9 条（恐惧症）点开 100 条子表', (tester) async {
    await pumpApp(tester);
    await _gotoBackground(tester);
    await scrollTo(tester, 'btn_madness_table');
    await tapKey(tester, 'btn_madness_table');

    await tester.tap(find.byKey(const Key('madness_bout_9')));
    await tester.pumpAndSettle();
    expect(find.text('恐惧症表（100 条）'), findsOneWidget);
    expect(
      find.byKey(const Key('btn_madness_sub_random_phobia')),
      findsOneWidget,
    );
  });
}
