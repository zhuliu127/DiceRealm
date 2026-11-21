// ============================================================
// p12_emoji_c_test.dart — P12 emoji → 矢量图标（C 线：AI 车卡页 + 车卡流程 + 角色卡编辑）
//
// 两条独立的证据链，缺一不可：
//   ① 源码级：我负责的文件里，**非注释代码**不再出现 emoji（注释里的 ★ ⚠️ 是工程笔记，不算 UI）
//   ② 渲染级：真正挂起来跑一遍，空态渲染出的是 `Icon`，整棵子树里没有任何 emoji 文本
//
// 唯一豁免：`背景 → 伙伴/头像` 的占位提示 `例：🧑‍🔬` —— 那个字段本身就是「头像（emoji / 文本）」，
// 它在演示输入格式，属于**内容**而不是图标，见 `_allowedContent`。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/ui/ai_create_page.dart';
import 'package:dice_realm/ui/card_edit/background_history.dart';
import 'package:dice_realm/ui/card_edit/background_mythos.dart';
import 'package:dice_realm/ui/card_edit/status_editor.dart';
import 'package:dice_realm/ui/create/steps/step_combat.dart';
import 'package:dice_realm/ui/create/steps/step_gear.dart';
import 'package:dice_realm/ui/create/steps/step_skills.dart';
import 'package:dice_realm/ui/random_create_page.dart';
import 'package:dice_realm/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 判 emoji 的字符集：只收「图形符号 / 星形 / 装饰符号 / 变体选择符」，
/// **不含** U+2190–U+21FF（→ ← 是流程说明里的内容，按规范保留）。
final RegExp _emoji = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]',
  unicode: true,
);

/// 「内容」而不是图标的两类东西：
///   · 头像字段的格式示例（🧑‍🔬 = U+1F9D1 U+200D U+1F52C）—— 该字段本身就收 emoji；
///   · 彩蛋角标（🎭 跑团成员 / 🥚 彩蛋）—— 由 `domain/easter_egg.dart` 的 `badge` 提供，
///     经 `ui/summary_card.dart` 渲染，**不在本线文件里**（已上报 team-lead）。
const String _allowedContent = '\u{1F9D1}\u{200D}\u{1F52C}';
const List<String> _contentPrefixes = <String>['🎭 ', '🥚 '];

/// 我这条线的文件（整个 card_edit / create 目录都扫，防止漏改）。
List<String> _myFiles() {
  final out = <String>[
    'lib/ui/ai_create_page.dart',
    'lib/ui/random_create_page.dart',
  ];
  for (final dir in <String>['lib/ui/card_edit', 'lib/ui/create']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.dart')) out.add(f.path.replaceAll('\\', '/'));
    }
  }
  return out;
}

/// 把 Dart 源码里的注释剥掉（保留字符串字面量里的 `//`，例如 URL）。
String _stripComments(String src) {
  final buf = StringBuffer();
  var i = 0;
  var line = false;
  var block = false;
  String? quote;

  void copy(int n) {
    buf.write(src.substring(i, i + n));
    i += n;
  }

  while (i < src.length) {
    final ch = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';

    if (line) {
      if (ch == '\n') {
        line = false;
        copy(1);
      } else {
        i++;
      }
      continue;
    }
    if (block) {
      if (ch == '*' && next == '/') {
        block = false;
        i += 2;
      } else {
        if (ch == '\n') buf.write('\n');
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (ch == '\\' && next.isNotEmpty) {
        copy(2);
        continue;
      }
      if (ch == quote) quote = null;
      copy(1);
      continue;
    }
    if (ch == '/' && next == '/') {
      line = true;
      i += 2;
      continue;
    }
    if (ch == '/' && next == '*') {
      block = true;
      i += 2;
      continue;
    }
    if (ch == "'" || ch == '"') quote = ch;
    copy(1);
  }
  return buf.toString();
}

/// 一串渲染出来的文本里挑出含 emoji 的（彩蛋角标等「内容」按前缀豁免）
List<String> _emojiIn(Iterable<String> texts) => texts
    .where((s) => _contentPrefixes.every((p) => !s.startsWith(p)))
    .where((s) => _emoji.hasMatch(s))
    .toList();

/// 整棵树里所有 Text / RichText 的纯文本（含 offstage）
List<String> _renderedTexts(WidgetTester tester) {
  final out = <String>[];
  for (final t in tester.widgetList<Text>(
    find.byType(Text, skipOffstage: false),
  )) {
    final d = t.data;
    if (d != null) out.add(d);
    final span = t.textSpan;
    if (span != null) out.add(span.toPlainText());
  }
  return out;
}

Character _emptyCard() {
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
  recalc(c);
  return c;
}

/// 背景编辑器本体是 Column，套一层 ListView 给它无限高（与既有用例同口径）。
Widget _hostScrollable(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: <Widget>[child])),
);

/// 向导步骤本体自带 ListView，只能给**有界**高度。
Widget _hostPlain(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 空态必须：① 传了 icon ② 渲染出 Icon ③ 不再渲染 emoji 文本
void _expectEmptyStateIcon(WidgetTester tester, String title, IconData icon) {
  final all = tester
      .widgetList<EmptyState>(find.byType(EmptyState, skipOffstage: false))
      .toList();
  expect(all, isNotEmpty, reason: '「$title」用例应当出现空态');
  final target = all.firstWhere(
    (e) => e.title == title,
    orElse: () => throw StateError('没找到空态「$title」，实到 ${all.map((e) => e.title)}'),
  );
  expect(target.icon, icon, reason: '空态「$title」必须传矢量图标');
  expect(
    find.text(target.emoji, skipOffstage: false),
    findsNothing,
    reason: '空态「$title」不该再渲染 emoji「${target.emoji}」',
  );
  expect(
    find.descendant(
      of: find.byType(EmptyState, skipOffstage: false),
      matching: find.byIcon(icon, skipOffstage: false),
    ),
    findsWidgets,
    reason: '空态「$title」应当真的画出 Icon($icon)',
  );
}

Future<SettingsRepo> _configuredSettings() async {
  final s = await newMemorySettings();
  s
    ..aiBase = 'https://api.example.com/v1'
    ..aiModel = 'm'
    ..aiKey = 'sk-abcdefghijklmnop';
  await s.save();
  return s;
}

void main() {
  // ---------------- ① 源码级 ----------------

  group('源码：我负责的文件里，非注释代码不含 emoji', () {
    test('ai_create_page / random_create_page / card_edit/** / create/**', () {
      final files = _myFiles();
      expect(files.length, greaterThan(10), reason: '扫描清单不该是空的');

      final offenders = <String>[];
      for (final path in files) {
        // `EmptyState(emoji: '📜')` 的 emoji 形参是**兜底保留**项（规范要求不动它），
        // 真正换成矢量图标的是新加的 `icon:`，所以先把它从扫描面里摘掉。
        final code = _stripComments(File(path).readAsStringSync())
            .replaceAll(_allowedContent, '')
            .replaceAll(RegExp(r"emoji:\s*'[^']*'"), 'emoji: <kept>');
        final lines = code.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final hits = _emojiIn(<String>[lines[i]]);
          if (hits.isNotEmpty) {
            offenders.add('$path:${i + 1}: ${hits.join()} → ${lines[i].trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '这些地方还留着 emoji：\n${offenders.join('\n')}',
      );
    });

    test('反向自证伪：扫描器确实认得出 emoji（否则上面的绿是假绿）', () {
      expect(_stripComments("const a = '🎲 掷骰'; // ★ 注释里的 🎲 不算")
          .contains('🎲'), isTrue);
      expect(_stripComments("// 🎲 整行注释").contains('🎲'), isFalse);
      expect(_stripComments("/* 🎲 块注释 */ const b = 1;").contains('🎲'), isFalse);
      expect(_stripComments("final u = 'https://a.b/c'; // 🎲").contains('🎲'), isFalse);
      expect(_emojiIn(<String>['✨ 生成', '普通文本', '→ 流程']), <String>['✨ 生成']);
    });
  });

  // ---------------- ② 渲染级：空态出 Icon ----------------

  group('渲染：空态画 Icon，不画 emoji', () {
    testWidgets('经历记录空态 → description_outlined', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_hostScrollable(HistoryEditor(card: _emptyCard(), onChanged: () {})));
      await tester.pumpAndSettle();
      _expectEmptyStateIcon(tester, '还没有经历记录', Icons.description_outlined);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('伙伴记录空态 → people_outline', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_hostScrollable(CompanionsEditor(card: _emptyCard(), onChanged: () {})));
      await tester.pumpAndSettle();
      _expectEmptyStateIcon(tester, '还没有伙伴记录', Icons.people_outline);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('法术空态 → auto_stories_outlined；两个按钮也用图标', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_hostScrollable(SpellsEditor(card: _emptyCard(), onChanged: () {})));
      await tester.pumpAndSettle();
      _expectEmptyStateIcon(tester, '还没有学会法术', Icons.auto_stories_outlined);
      expect(find.text('从法术表选择'), findsOneWidget, reason: 'emoji 去掉、文字留着');
      expect(find.text('自定义法术'), findsOneWidget);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('疯狂状态空态 → psychology_outlined；掷骰/推进/清空都是图标', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_hostScrollable(StatusEditor(card: _emptyCard(), onChanged: () {})));
      await tester.pumpAndSettle();
      _expectEmptyStateIcon(tester, '当前没有疯狂状态', Icons.psychology_outlined);
      expect(find.text('掷临时疯狂'), findsOneWidget);
      expect(find.text('推进 1 轮'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);
      expect(find.byIcon(Icons.casino_outlined, skipOffstage: false), findsWidgets);
      expect(find.byIcon(Icons.skip_next, skipOffstage: false), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline, skipOffstage: false), findsOneWidget);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('战斗步：武器 / 防具 / 载具三个空态各自出图标', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_hostPlain(StepCombat(draft: _emptyCard(), onChanged: () {})));
      await tester.pumpAndSettle();
      _expectEmptyStateIcon(tester, '尚未添加武器', Icons.sports_martial_arts);
      _expectEmptyStateIcon(tester, '尚未装备防具', Icons.shield_outlined);
      _expectEmptyStateIcon(tester, '尚未拥有载具', Icons.directions_car_outlined);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('装备步：背包空态 → backpack_outlined', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_hostPlain(StepGear(draft: _emptyCard(), onChanged: () {})));
      await tester.pumpAndSettle();
      _expectEmptyStateIcon(tester, '背包是空的', Icons.backpack_outlined);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('技能步：没选职业的空态 → explore_outlined', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(_hostPlain(StepSkills(draft: _emptyCard(), onChanged: () {})));
      await tester.pumpAndSettle();
      _expectEmptyStateIcon(tester, '还没有选择职业', Icons.explore_outlined);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });
  });

  // ---------------- ② 渲染级：整页无 emoji ----------------

  group('渲染：页面级（AI 车卡 / 一键出卡）', () {
    testWidgets('AI 车卡页（未配置）：标题是图标 + 文字，整页无 emoji', (tester) async {
      await pumpApp(tester, settings: await newMemorySettings());
      await tapKey(tester, 'fab_ai_create');
      await tapKey(tester, 'rule_pick_coc7');
      expect(find.byType(AiCreatePage), findsOneWidget);

      expect(find.text('AI 车卡'), findsOneWidget);
      expect(find.text('去配置'), findsOneWidget);
      expect(find.text('用离线随机卡'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.auto_awesome),
        ),
        findsOneWidget,
        reason: '标题前的 ✨ 应换成 Icons.auto_awesome',
      );
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('AI 车卡页（已配置）：生成按钮也是图标 + 文字', (tester) async {
      await pumpApp(tester, settings: await _configuredSettings());
      await tapKey(tester, 'fab_ai_create');
      await tapKey(tester, 'rule_pick_coc7');

      expect(find.text('生成调查员'), findsOneWidget);
      expect(find.byKey(const Key('ai_generate')), findsOneWidget);
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });

    testWidgets('一键出卡页：标题是图标 + 文字，整页无 emoji', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'entry_random');
      await tapKey(tester, 'rule_pick_coc7');
      expect(find.byType(RandomCreatePage), findsOneWidget);

      expect(find.text('一键出卡'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.casino_outlined),
        ),
        findsOneWidget,
      );
      expect(_emojiIn(_renderedTexts(tester)), isEmpty);
    });
  });
}
