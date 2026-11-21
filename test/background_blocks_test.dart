// ============================================================
// background_blocks_test.dart — 角色背景「剩余四块」
//   （调查员经历 / 调查员伙伴 / 克苏鲁神话 / 已学法术）
//
// 钉住的硬约束：
//   1 卡片契约：history/companions/mythos 的键名与元素键集合与旧版完全一致
//   2 法术是**深拷贝**：改卡不能污染 `cocSpells` 静态表
//   3 数字型字段照抄字符串（不转成 0 / NaN）
//   4 老存档兼容：旧版真实导出的卡，四块内容逐字段读回相等
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/data/spells.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/normalize.dart';
import 'package:dice_realm/repo/card_transfer.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/ui/card_edit/background_editor.dart';
import 'package:dice_realm/ui/card_edit/background_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

String _readFixture() =>
    File('test/fixtures/legacy_card_blocks_export.json').readAsStringSync();

/// 造一张属性齐备的卡（只关心背景四块，不依赖随机）
Character _card() {
  final c = Character(newCharacter());
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
    c.attributes[k] = 50;
  }
  c.basicInfo['age'] = 32;
  c.raw['age'] = 32;
  recalc(c);
  return c;
}

/// 把背景编辑器挂起来（页面本体是个 Column，外面套 ListView 才能滚）
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
        body: ListView(
          children: <Widget>[
            BackgroundEditor(
              card: widget.card,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pumpEditor(WidgetTester tester, Character card) async {
  useTallScreen(tester);
  await tester.pumpWidget(_Host(card: card));
  await tester.pumpAndSettle();
}

/// 滚到某个控件再点（Column 不是懒构建，但屏幕装不下全部）
Future<void> _revealAndTap(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView).first,
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('硬约束 1：键名与旧版完全一致', () {
    test('新增经历：9 个键一个不少、一个不多，且都是空字符串', () {
      final e = newHistoryEntry();
      expect(e.keys.toSet(), historyKeys.toSet());
      expect(historyKeys, <String>[
        'title',
        'date',
        'description',
        'sanChange',
        'hpChange',
        'skillChanges',
        'moneyChange',
        'itemsObtained',
        'notes',
      ]);
      for (final k in historyKeys) {
        expect(e[k], '', reason: '$k 初值应为空字符串');
      }
    });

    test('新增伙伴：6 个键（name/avatar/identity/age/relationship/description）', () {
      final c = newCompanionEntry();
      expect(c.keys.toSet(), companionKeys.toSet());
      expect(companionKeys, <String>[
        'name',
        'avatar',
        'identity',
        'age',
        'relationship',
        'description',
      ]);
      for (final k in companionKeys) {
        expect(c[k], '');
      }
    });

    test('自定义法术：8 个键 + custom:true + id 前缀 custom_', () {
      final sp = newCustomSpell(name: '测试法术', effect: ' 效果 ');
      expect(sp.keys.toSet(), customSpellKeys.toSet());
      expect(sp['custom'], isTrue);
      expect(jsStr(sp['id']).startsWith('custom_'), isTrue);
      expect(sp['name'], '测试法术');
      expect(sp['category'], '自定义', reason: '空分类落到「自定义」');
      expect(sp['cost'], '—', reason: '空消耗落占位符（旧版 sp.cost || —）');
      expect(sp['effect'], '效果', reason: '值会 trim');
    });

    test('mythos 只多一个旧版已写过的 notes 键，没有别的自造键', () {
      final c = _card();
      expect(c.mythos.keys.toSet(), <String>{
        'skill',
        'knowledge',
        'entries',
        'spells',
      });
      c.mythos['knowledge'] = '已知学识';
      c.mythos['notes'] = '神话相关经历';
      // 归一化后仍只有这 5 个键（notes 是旧版已写，不算新增契约）
      normalize(c);
      expect(c.mythos.keys.toSet(), <String>{
        'skill',
        'knowledge',
        'entries',
        'spells',
        'notes',
      });
    });

    test('mythos.skill 与技能表里的 cthulhu 是两套：只读不写', () {
      final c = _card();
      c.raw['skills'] = <Object?>[
        <String, Object?>{
          'key': 'cthulhu',
          'id': 'cthulhu',
          'name': '克苏鲁神话',
          'sub': '',
          'base': 0,
          'growth': 0,
          'occ': 0,
          'int': 12,
          'total': 12,
          'custom': false,
          'desc': '',
        },
      ];
      expect(mythosSkillTotal(c), 12);
      expect(jsNum(c.mythos['skill']), 0, reason: '读技能值，不写 mythos.skill');
    });
  });

  group('硬约束 2：法术是深拷贝', () {
    test('copySpell 与源表不是同一个对象，改拷贝不影响 cocSpells', () {
      final before = jsonEncode(cocSpells);
      final copy = copySpell(cocSpells.first);
      expect(identical(copy, cocSpells.first), isFalse);
      expect(
        identical(copy['variants'], cocSpells.first['variants']),
        isFalse,
        reason: 'variants 也必须深拷贝，否则改一个变体就污染整张表',
      );

      // 改拷贝（含嵌套的 variants）
      copy['name'] = '被改过的名字';
      asMap(asList(copy['variants']).first)['note'] = '被改过的备注';
      expect(jsonEncode(cocSpells), before, reason: '静态数据表一个字节都不许变');
    });

    test('UI 里从法术表加一条后，改卡上的法术不会污染源表', () async {
      final before = jsonEncode(cocSpells);
      final c = _card();
      c.mythos['spells'] = <Object?>[copySpell(cocSpells.first)];
      final mine = asMap(spellsOf(c).single);
      mine['name'] = '卡上的法术';
      asMap(asList(mine['variants']).first)['note'] = '卡上的备注';
      expect(jsonEncode(cocSpells), before);
      expect(jsStr(cocSpells.first['name']), isNot('卡上的法术'));
    });
  });

  group('硬约束 3：数字型字段照抄字符串', () {
    test('非数字输入原样存成字符串（不会变 NaN / 0）', () {
      final e = newHistoryEntry();
      setText(e, 'sanChange', 'abc');
      expect(e['sanChange'], 'abc');
      expect(e['sanChange'], isA<String>());

      setText(e, 'hpChange', '-');
      expect(e['hpChange'], '-');

      setText(e, 'moneyChange', '');
      expect(e['moneyChange'], '');
    });

    test('老卡里的数字型值读回保持原样（-5 与 5 都不改类型）', () {
      final e = asMap(<String, Object?>{
        'sanChange': '-5',
        'hpChange': 5,
        'moneyChange': '0',
      });
      expect(textOf(e, 'sanChange'), '-5');
      expect(textOf(e, 'hpChange'), '5', reason: '旧卡可能是数字，读出来当字符串显示');
      expect(textOf(e, 'moneyChange'), '0');
    });
  });

  group('硬约束 4：老存档四块内容逐字段读回', () {
    test('旧版真实导出的卡：history / companions / mythos 全部对得上', () async {
      final parsed = parseCardImport(_readFixture());
      expect(parsed.count, 1);
      final raw = parsed.cards.first;

      final history = asList(raw['history']).map(asMap).toList();
      final companions = asList(raw['companions']).map(asMap).toList();
      final mythos = asMap(raw['mythos']);

      expect(history.length, 2);
      expect(history.first.keys.toSet(), historyKeys.toSet());
      expect(history[0]['title'], '阿卡姆调查事件');
      expect(history[0]['sanChange'], '-5');
      expect(history[0]['itemsObtained'], '神秘古书');
      expect(history[1]['sanChange'], '-1D6', reason: '骰子表达式也是原样字符串');
      expect(history[1]['description'], '');

      expect(companions.length, 1);
      expect(companions.first.keys.toSet(), companionKeys.toSet());
      expect(companions[0]['name'], '约翰·万斯');
      expect(companions[0]['avatar'], '');
      expect(companions[0]['age'], '45');

      expect(mythos['knowledge'], contains('克苏鲁'));
      expect(mythos['notes'], contains('拉莱耶'));
      final spells = asList(mythos['spells']).map(asMap).toList();
      expect(spells.length, 2);
      expect(
        spells[0].keys.toSet(),
        cocSpells.first.keys.toSet(),
        reason: '目录法术键集合与 cocSpells 一致',
      );
      expect(spells[0]['name'], cocSpells.first['name']);
      expect(spells[1]['custom'], isTrue);
      expect(jsStr(spells[1]['id']).startsWith('custom_'), isTrue);

      // 导入仓库 → normalize 幂等，四块内容一字不变
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final imported = (await importIntoRepo(repo, _readFixture())).single;
      expect(jsonEncode(imported.raw['history']), jsonEncode(raw['history']));
      expect(
        jsonEncode(imported.raw['companions']),
        jsonEncode(raw['companions']),
      );
      expect(jsonEncode(imported.raw['mythos']), jsonEncode(raw['mythos']));

      final before = jsonEncode(imported.raw);
      normalize(imported);
      expect(jsonEncode(imported.raw), before, reason: 'normalize 幂等');
    });
  });

  group('UI：三块列表 + 空态 + 计数 + 折叠', () {
    testWidgets('空态文案与三个「添加」按钮', (tester) async {
      await _pumpEditor(tester, _card());
      expect(find.text('还没有经历记录'), findsOneWidget);
      expect(find.text('用于保存角色成长历史'), findsOneWidget);
      expect(find.text('还没有伙伴记录'), findsOneWidget);
      expect(find.text('还没有学会法术'), findsOneWidget);
      expect(find.text('从法术表选择，或按格式自定义一个'), findsOneWidget);

      // 计数
      expect(find.text('0 条 · 用于保存角色成长历史'), findsOneWidget);
      expect(find.text('0 位'), findsOneWidget);
      expect(find.text('0 个'), findsOneWidget);
    });

    testWidgets('添加 / 删除经历：元素键集合与旧版一致', (tester) async {
      final c = _card();
      await _pumpEditor(tester, c);

      await _revealAndTap(tester, find.byKey(const Key('btn_add_history')));
      expect(historyOf(c).length, 1);
      expect(asMap(historyOf(c).single).keys.toSet(), historyKeys.toSet());
      expect(find.text('还没有经历记录'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('history_0_title')),
        '阿卡姆调查事件',
      );
      await tester.pumpAndSettle();
      expect(asMap(historyOf(c).single)['title'], '阿卡姆调查事件');

      await _revealAndTap(tester, find.byKey(const Key('history_remove_0')));
      expect(historyOf(c), isEmpty);
      expect(find.text('还没有经历记录'), findsOneWidget);
    });

    testWidgets('添加伙伴：6 个字段都能写进卡里', (tester) async {
      final c = _card();
      await _pumpEditor(tester, c);

      await _revealAndTap(tester, find.byKey(const Key('btn_add_companion')));
      expect(companionsOf(c).length, 1);

      await tester.enterText(find.byKey(const Key('companion_0_name')), '约翰');
      await tester.enterText(
        find.byKey(const Key('companion_0_identity')),
        '大学教授',
      );
      await tester.enterText(find.byKey(const Key('companion_0_age')), '45');
      await tester.enterText(
        find.byKey(const Key('companion_0_relationship')),
        '调查搭档',
      );
      await tester.enterText(
        find.byKey(const Key('companion_0_avatar')),
        '🧑‍🔬',
      );
      await tester.enterText(
        find.byKey(const Key('companion_0_description')),
        '两年前认识。',
      );
      await tester.pumpAndSettle();

      final cp = asMap(companionsOf(c).single);
      expect(cp.keys.toSet(), companionKeys.toSet());
      expect(cp['name'], '约翰');
      expect(cp['identity'], '大学教授');
      expect(cp['age'], '45');
      expect(cp['relationship'], '调查搭档');
      expect(cp['avatar'], '🧑‍🔬');
      expect(cp['description'], '两年前认识。');
    });

    testWidgets('折叠按钮：收起后内容隐藏，再展开恢复（数据不受影响）', (tester) async {
      final c = _card();
      addHistory(c, newHistoryEntry());
      await _pumpEditor(tester, c);
      expect(find.text('还没有经历记录'), findsNothing);
      expect(find.byKey(const Key('btn_add_history')), findsOneWidget);

      await _revealAndTap(tester, find.byKey(const Key('btn_toggle_history')));
      expect(find.byKey(const Key('btn_add_history')), findsNothing);
      expect(historyOf(c).length, 1, reason: '折叠只是显示，不动数据');

      await _revealAndTap(tester, find.byKey(const Key('btn_toggle_history')));
      expect(find.byKey(const Key('btn_add_history')), findsOneWidget);
    });
  });

  group('UI：克苏鲁神话 + 法术', () {
    testWidgets('知识 / 经历写入 mythos，技能值只读展示', (tester) async {
      final c = _card();
      c.raw['skills'] = <Object?>[
        <String, Object?>{
          'key': 'cthulhu',
          'id': 'cthulhu',
          'name': '克苏鲁神话',
          'sub': '',
          'base': 0,
          'growth': 0,
          'occ': 0,
          'int': 12,
          'total': 12,
          'custom': false,
          'desc': '',
        },
      ];
      await _pumpEditor(tester, c);

      // StatTile 是 RichText（数值 + 后缀两段），要用 findRichText 才能匹配
      expect(
        find.text('12%', findRichText: true),
        findsOneWidget,
        reason: '只读展示技能表里的克苏鲁神话值',
      );

      await tester.enterText(
        find.byKey(const Key('mythos_knowledge')),
        '已知的神话学识',
      );
      await tester.enterText(
        find.byKey(const Key('mythos_notes')),
        '在梦中见过拉莱耶。',
      );
      await tester.pumpAndSettle();

      expect(c.mythos['knowledge'], '已知的神话学识');
      expect(c.mythos['notes'], '在梦中见过拉莱耶。');
      // 没有「克苏鲁神话技能值」输入框（只读）
      expect(find.byKey(const Key('mythos_skill')), findsNothing);
    });

    testWidgets('从法术表选一条 → 进数组 → 删除', (tester) async {
      final c = _card();
      await _pumpEditor(tester, c);

      await _revealAndTap(tester, find.byKey(const Key('btn_pick_spell')));
      expect(find.textContaining('法术表（61 个）'), findsOneWidget);

      // 搜索定位到「请神术」，取第一条
      await tester.enterText(find.byKey(const Key('spell_search')), '请神术');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spell_lib_0')));
      await tester.pumpAndSettle();

      expect(spellsOf(c).length, 1);
      final sp = asMap(spellsOf(c).single);
      expect(sp.keys.toSet(), cocSpells.first.keys.toSet());
      expect(sp['name'], '请神术');
      expect(identical(sp, cocSpells.first), isFalse, reason: '必须是深拷贝');
      expect(find.text('请神术'), findsOneWidget);

      await _revealAndTap(tester, find.byKey(const Key('spell_remove_0')));
      expect(spellsOf(c), isEmpty);
      expect(find.text('还没有学会法术'), findsOneWidget);
    });

    testWidgets('已失传的法术（61 条表里没有）照样能显示与删除', (tester) async {
      final c = _card();
      c.mythos['spells'] = <Object?>[
        <String, Object?>{
          'id': 'custom_lost',
          'name': '已失传的法术',
          'category': '旧版本',
          'cost': '3 点魔法值',
          'time': '2 轮',
          'effect': '效果描述来自卡片本身。',
          'condition': '',
          'custom': true,
        },
      ];
      await _pumpEditor(tester, c);

      // 渲染只读卡片上的字段（不回查 61 条表），所以失传法术也能显示
      expect(find.text('已失传的法术'), findsOneWidget);
      expect(find.text('旧版本'), findsOneWidget);
      expect(find.textContaining('消耗：3 点魔法值'), findsOneWidget);

      await _revealAndTap(tester, find.byKey(const Key('spell_remove_0')));
      expect(spellsOf(c), isEmpty);
    });

    testWidgets('变体可展开（键名 variants → name / cost / note）', (tester) async {
      final c = _card();
      c.mythos['spells'] = <Object?>[copySpell(cocSpells.first)];
      await _pumpEditor(tester, c);

      expect(find.text('变体 7 种 ▾'), findsOneWidget);
      await _revealAndTap(tester, find.byKey(const Key('spell_variants_0')));
      expect(find.text('收起 ▴'), findsOneWidget);
      // 第一条变体是「阿撒托斯」，其 note 来自 cocSpells
      expect(find.text('阿撒托斯'), findsOneWidget);
      expect(
        find.text(
          jsStr(asMap(asList(cocSpells.first['variants']).first)['note']),
        ),
        findsOneWidget,
      );
    });

    testWidgets('自定义法术：空名拦下，填名后 custom:true', (tester) async {
      final c = _card();
      await _pumpEditor(tester, c);

      await _revealAndTap(tester, find.byKey(const Key('btn_custom_spell')));
      await _revealAndTap(tester, find.byKey(const Key('custom_spell_save')));
      expect(
        find.byKey(const Key('custom_spell_error')),
        findsOneWidget,
        reason: '名称不能为空',
      );
      expect(spellsOf(c), isEmpty);

      await tester.enterText(
        find.byKey(const Key('custom_spell_name')),
        '阿撒托斯的号角',
      );
      await tester.enterText(
        find.byKey(const Key('custom_spell_cost')),
        '8 点魔法值',
      );
      await tester.enterText(
        find.byKey(const Key('custom_spell_effect')),
        '吹响它。',
      );
      await _revealAndTap(tester, find.byKey(const Key('custom_spell_save')));

      expect(spellsOf(c).length, 1);
      final sp = asMap(spellsOf(c).single);
      expect(sp.keys.toSet(), customSpellKeys.toSet());
      expect(sp['name'], '阿撒托斯的号角');
      expect(sp['custom'], isTrue);
      expect(sp['cost'], '8 点魔法值');
      expect(sp['effect'], '吹响它。');
      expect(find.text('阿撒托斯的号角'), findsOneWidget);
    });
  });
}
