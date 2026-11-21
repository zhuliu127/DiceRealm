// ============================================================
// p8_skill_step_test.dart — 需求 11 后半：第 5 步「职业技能」
//
// 用户原话：
//   「下面技能加点处，给所有技能分类（常用/战斗/社交/生存/语言/技艺/生活，
//     分类你来优化），同一个技能可以出现在多个分类里，但同一个技能**已加点是共享的**。
//     增加**搜索（模糊搜索）**技能功能。有的职业有「任意选择 N 项技能」，
//     点「+选择技能」后弹窗里**自动过滤掉已有的职业技能**，
//     而不是还能选已有职业技能再提示。」
//
// 钉住五件事：
//   ① 分组表不漏技能（每个技能至少在一个分类里），且允许跨组
//   ② 分类 chip 真能筛（点「战斗」只剩战斗类，点「全部」恢复）
//   ③ 模糊搜索：搜「侦」命中「侦查」，中文输入法打不出全名也能搜到
//   ④ **加点共享**：同一技能在两个分类里看到的是同一个数字
//   ⑤ 「+选择技能」弹窗里不再出现本职业已有的技能
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/ui/attr_meta.dart' show allAttrKeys;
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:dice_realm/ui/create/skill_groups.dart';
import 'package:dice_realm/ui/create/steps/step_skills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 技能页只依赖 Material 祖先（弹层 / SnackBar 由 Scaffold 提供）
class _Host extends StatefulWidget {
  const _Host({required this.card});

  final Character card;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: StepSkills(
          draft: widget.card,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }
}

/// 把窗口开得**很高**，让技能列表整段都建出来。
///
/// 为什么：`ListView` 是懒构建的，屏幕外的技能行根本不在树里 ——
/// 那样「某分类里不该出现某技能」的断言会因为「行没被建」而假通过。
/// 窗口够高 = 列表全量在树里，存在性断言才算数。
Future<void> _pumpSkills(WidgetTester tester, Character card) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_Host(card: card));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 读技能行右侧的「最终值」
String _totalOf(WidgetTester tester, String skillKey) {
  final f = find.byKey(Key('skill_total_$skillKey'));
  expect(f, findsOneWidget, reason: '技能行 $skillKey 不在当前列表里');
  return tester.widget<Text>(f).data ?? '';
}

/// 一张属性齐备、职业技能已按职业补齐的卡（默认会计师：有「任意两项」块）
Character _card({String occ = 'occ2'}) {
  final c = Character(newCharacter());
  c.raw['id'] = 'skills01';
  c.raw['characterName'] = '技能测试';
  c.raw['playerName'] = '老王';
  c.basicInfo['age'] = 32;
  c.raw['age'] = 32;
  c.raw['occupationId'] = occ;
  for (final k in allAttrKeys) {
    c.attributes[k] = 50;
  }
  recalc(c);
  syncSkills(c);
  materializeOccupationalSkills(c);
  return c;
}

Map<String, Object?> _skill(Character c, String key) =>
    c.skills.map(asMap).firstWhere((s) => jsStr(s['key']) == key);

void main() {
  group('分类表本身（不等 UI）', () {
    test('每个技能都至少落在一个分类里（不漏项）', () {
      final ids = allSkillIds();
      expect(ids.length, 54, reason: '技能库条数变了，分类表要跟着改');
      for (final id in ids) {
        expect(
          skillGroupIdsOf(id),
          isNotEmpty,
          reason: '技能 $id 哪个分类都找不到 —— 玩家在分类视图里会永远看不到它',
        );
      }
    });

    test('一个技能可以在多个分类里（闪避 = 常用 + 战斗 + 探索外）', () {
      expect(skillGroupIdsOf('dodge'), containsAll(<String>['common', 'combat']));
      expect(
        skillGroupIdsOf('spot_hidden'),
        containsAll(<String>['common', 'explore']),
      );
    });

    test('首位是「全部」，末位是「其他」，没被显式分组的都进「其他」', () {
      expect(skillGroups.first.id, skillGroupAllId);
      expect(skillGroups.last.id, skillGroupOtherId);
      final other = skillGroupById(skillGroupOtherId);
      for (final id in uncoveredSkillIds()) {
        expect(other.contains(id), isTrue, reason: '$id 应该落在「其他」里');
      }
      // 「其他」= 没被显式分组的那些，不多不少
      expect(
        other.skillIds.difference(uncoveredSkillIds().toSet()),
        <String>{'custom'},
        reason: '「其他」里只该多一个自定义技能的占位 id',
      );
    });
  });

  group('需求 11：分类 chip 能筛', () {
    testWidgets('11 个分类 chip 都在，点「战斗」只剩战斗类，点「全部」恢复', (tester) async {
      await _pumpSkills(tester, _card());

      for (final g in skillGroups) {
        expect(
          find.byKey(Key('skill_cat_${g.id}')),
          findsOneWidget,
          reason: '缺分类 chip：${g.label}',
        );
      }

      // 未筛时：本职「侦查」一定在；没加过点的「斗殴」按原有省流规则
      // 收在「其他技能 · 显示全部」后面（不筛的时候只列有加点的）
      expect(find.byKey(const Key('skill_row_spot_hidden')), findsOneWidget);
      expect(find.byKey(const Key('skill_row_fighting::斗殴')), findsNothing);

      await _tapKey(tester, 'skill_cat_combat');
      expect(find.byKey(const Key('skill_row_fighting::斗殴')), findsOneWidget);
      expect(
        find.byKey(const Key('skill_row_spot_hidden')),
        findsNothing,
        reason: '「侦查」不属于战斗分类，筛完不该还在列表里',
      );
      expect(find.textContaining('· 战斗'), findsOneWidget);

      // 一旦进入筛选，省流开关让位：该组的技能全部列出（含还没加点的）
      await _tapKey(tester, 'skill_cat_all');
      expect(find.byKey(const Key('skill_row_spot_hidden')), findsOneWidget);
      expect(find.byKey(const Key('skill_row_fighting::斗殴')), findsNothing);
    });

    testWidgets('点「语言」只留语言类（母语 + 其他语言）', (tester) async {
      await _pumpSkills(tester, _card());

      await _tapKey(tester, 'skill_cat_language');
      expect(find.byKey(const Key('skill_row_language_own')), findsOneWidget);
      // 其他语言的子专攻也在（切到语言分类就是为了找它们）
      expect(
        find.byKey(const Key('skill_row_language_other::拉丁语')),
        findsOneWidget,
      );
      // 本职「侦查」不在语言组 —— 它要是漏出来就说明筛选没生效
      expect(find.byKey(const Key('skill_row_spot_hidden')), findsNothing);
      expect(find.byKey(const Key('skill_row_fighting::斗殴')), findsNothing);
    });
  });

  group('需求 11：模糊搜索', () {
    testWidgets('搜「侦」命中「侦查」，并把不匹配的藏起来', (tester) async {
      await _pumpSkills(tester, _card());

      await tester.enterText(find.byKey(const Key('skill_search')), '侦');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skill_row_spot_hidden')), findsOneWidget);
      expect(find.byKey(const Key('skill_row_fighting::斗殴')), findsNothing);
      expect(find.byKey(const Key('skill_row_listen')), findsNothing);
    });

    testWidgets('搜英文 id 片段也能命中（spot → 侦查），搜不到给空态', (tester) async {
      await _pumpSkills(tester, _card());

      await tester.enterText(find.byKey(const Key('skill_search')), 'spot');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill_row_spot_hidden')), findsOneWidget);
      expect(find.byKey(const Key('skill_row_dodge')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('skill_search')),
        '这技能不存在',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill_none')), findsOneWidget);
      expect(find.byKey(const Key('skill_row_spot_hidden')), findsNothing);
    });

    testWidgets('分类 + 搜索叠加：战斗里搜「斗」只剩格斗（斗殴）', (tester) async {
      await _pumpSkills(tester, _card());

      await _tapKey(tester, 'skill_cat_combat');
      await tester.enterText(find.byKey(const Key('skill_search')), '斗');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skill_row_fighting::斗殴')), findsOneWidget);
      expect(find.byKey(const Key('skill_row_dodge')), findsNothing);
    });
  });

  group('需求 11：同一个技能跨分类的加点是同一份', () {
    testWidgets('闪避在「战斗」里看到的数字，和「常用」里是同一个', (tester) async {
      final card = _card();
      await _pumpSkills(tester, card);

      // 初始基础值 = DEX/2 = 25
      await _tapKey(tester, 'skill_cat_combat');
      final before = _totalOf(tester, 'dodge');
      expect(before, '25');

      // 直接在数据层加点（等价于玩家在弹层里点「+」）
      final dodge = _skill(card, 'dodge');
      final r = applyPoint(card, dodge, 'int', 10);
      expect(jsTruthy(r['ok']), isTrue, reason: '加点被规则拒绝了：${r['reason']}');

      // 重新渲染（切一次分类就够）
      await _tapKey(tester, 'skill_cat_common');
      expect(
        _totalOf(tester, 'dodge'),
        '35',
        reason: '在「战斗」里加的点，切到「常用」必须还是 35（同一份数据）',
      );

      await _tapKey(tester, 'skill_cat_combat');
      expect(_totalOf(tester, 'dodge'), '35', reason: '切回「战斗」不该回到 25');

      await _tapKey(tester, 'skill_cat_all');
      expect(_totalOf(tester, 'dodge'), '35');

      // 数据侧：只有一个闪避实例，且 occ/int 就是那一份
      final rows = card.skills
          .map(asMap)
          .where((s) => jsStr(s['key']) == 'dodge')
          .toList();
      expect(rows.length, 1, reason: '分类是视图，不能在卡里造出第二个闪避');
      expect(jsNum(rows.single['int']), 10);
    });

    testWidgets('每个分类里都只列一次同一个技能（不重复出行）', (tester) async {
      await _pumpSkills(tester, _card());
      // 「常用」里闪避只出现一次
      await _tapKey(tester, 'skill_cat_common');
      expect(find.byKey(const Key('skill_row_dodge')), findsOneWidget);
    });
  });

  group('需求 11：「+选择技能」弹窗自动过滤已有的职业技能', () {
    testWidgets('会计师的「任意两项」里选不到侦查 / 会计等本职技能', (tester) async {
      final card = _card();
      final free = getRequirements(
        card,
      ).firstWhere((r) => jsStr(r['type']) == 'free');
      final reqId = jsStr(free['id']);
      await _pumpSkills(tester, card);

      await _tapKey(tester, 'btn_pick_free_$reqId');
      expect(find.byKey(const Key('btn_free_confirm')), findsOneWidget);

      // 弹窗里**不再列出**本职业已有的技能（会计 / 法律 / 图书馆使用 / 聆听 / 说服 / 侦查）
      final pickTile = find.byType(CheckboxListTile);
      expect(pickTile, findsWidgets, reason: '弹窗没列出任何可选项，前提不成立');
      for (final name in <String>['侦查', '会计', '法律', '聆听', '说服']) {
        expect(
          find.descendant(of: pickTile, matching: find.text(name)),
          findsNothing,
          reason: '「$name」已经是本职业技能，不该出现在任选弹窗里',
        );
      }

      // 非本职的照常可选
      expect(
        find.descendant(
          of: pickTile,
          matching: find.textContaining('格斗（斗殴）'),
        ),
        findsOneWidget,
      );
      // 并且明说「隐藏了几项」，而不是让玩家自己纳闷
      expect(
        find.byKey(const Key('free_picker_hidden_hint')),
        findsOneWidget,
      );
    });

    testWidgets('已经勾过的仍显示（能取消），只是不能再选第二遍', (tester) async {
      final card = _card();
      final free = getRequirements(
        card,
      ).firstWhere((r) => jsStr(r['type']) == 'free');
      final reqId = jsStr(free['id']);
      // 先预置一个本块的已选（斗殴）
      setPicks(card, reqId, <Map<String, Object?>>[
        <String, Object?>{'skill': 'fighting', 'sub': '斗殴'},
      ]);
      materializeOccupationalSkills(card);
      await _pumpSkills(tester, card);

      await _tapKey(tester, 'btn_pick_free_$reqId');
      final pickTile = find.byType(CheckboxListTile);
      expect(
        find.descendant(
          of: pickTile,
          matching: find.textContaining('格斗（斗殴）'),
        ),
        findsOneWidget,
        reason: '本块已勾的技能必须还在，否则取消不掉',
      );
    });
  });
}
