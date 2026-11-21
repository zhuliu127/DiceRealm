// ============================================================
// QA P3 独立探针 · C：H5（P3 没弄坏 P2） + 结构性风险 1（Scope 断言/顺序）
//
// 全部走真实 DiceRealmApp 宿主（不是「裸宿主补 Scope」）。
// 只改 test/ 下内容，不改 lib/。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/normalize.dart';
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/repo/card_transfer.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/repo_scope.dart';
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:dice_realm/ui/create/steps/step_summary.dart';
import 'package:dice_realm/ui/create/wizard_checks.dart';
import 'package:dice_realm/ui/share_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 一张属性齐备、已 recalc 的老存档形状卡
Character qaCard({int hp = 7, int san = 40}) {
  final c = Character(newCharacter());
  c.raw['id'] = 'qaH5Card';
  c.raw['characterName'] = 'QA回归卡';
  c.raw['playerName'] = 'QA';
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
  for (final k in <String>[
    'str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu', 'luck',
  ]) {
    c.attributes[k] = 50;
  }
  recalc(c);
  c.status['currentHP'] = hp;
  c.status['currentSAN'] = san;
  c.status['_inited'] = true;
  return c;
}

void main() {
  // ==========================================================
  group('H5-1 P2 的 D1：导入 HP=0 的濒死卡不被 recalc 治活（真实文件后端）', () {
    test('导入 → 落盘 → 新 repo 实例读回 → HP 仍为 0', () async {
      final dir = await Directory.systemTemp.createTemp('qa_p3_h5_');
      addTearDown(() => dir.delete(recursive: true));

      final src = qaCard(hp: 10);
      src.status['currentHP'] = 0;
      src.status.remove('_hpTouched');
      final json = exportCardJson(src);

      final repo = CharacterRepo(directory: dir);
      await repo.load();
      final imported = await importIntoRepo(repo, json);
      expect(jsNum(imported.first.status['currentHP']), 0);

      // 关键：换一个全新的 repo 实例（重新读盘），不是复用内存里那份
      final fresh = CharacterRepo(directory: dir);
      await fresh.load();
      final back = fresh.all.firstWhere((c) => c.characterName == 'QA回归卡');
      expect(jsNum(back.status['currentHP']), 0,
          reason: 'P2 修过的 D1：濒死卡读回后被治活了');
      recalc(back);
      recalc(back);
      expect(jsNum(back.status['currentHP']), 0);

      // 反面守卫仍在：不打标记时确实会补满（证明不是「被注释掉的假守卫」）
      final control = qaCard(hp: 10);
      control.status['currentHP'] = 0;
      control.status.remove('_hpTouched');
      recalc(control);
      expect(jsNum(control.status['currentHP']), greaterThan(0));
    });
  });

  // ==========================================================
  group('H5-2 单卡导出与旧版 JSON.stringify 逐字节一致', () {
    test('2 张 QA 自选卡（含中文 / 数组 / 空串）→ 逐字节相同', () {
      final oracle = jsonDecode(
        File('test/fixtures/qa_p3_export_oracle.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = (oracle['cases'] as List).cast<Map<String, Object?>>();
      expect(cases.length, 2);
      for (final c in cases) {
        final card = Character(Map<String, Object?>.from(c['card'] as Map));
        expect(exportCardJson(card), c['expect'],
            reason: '单卡导出格式与旧版 store.js#exportCharacter 漂移');
      }
      // 全量导出形状也对
      final bundle = exportBundleJson(<Character>[
        Character(Map<String, Object?>.from(cases.first['card'] as Map)),
      ]);
      expect(bundle, startsWith('{\n  "format": "coc7-bundle",\n  "version": 1,'));
    });
  });

  // ==========================================================
  group('H5-3 P2 的 D2：「职业限定技能选择完成」的去修复 → 技能页', () {
    Character incompleteOccCard() {
      final c = qaCard();
      normalize(c);
      c.raw['occupationId'] = 'occ2'; // 会计师：限定技能「任意其他两项」未满足
      recalc(c);
      syncSkills(c);
      materializeOccupationalSkills(c);
      return c;
    }

    test('纯逻辑：该检查项 stepId 必须是 skills（不是 basics）', () {
      final c = incompleteOccCard();
      final row = wizardChecks(c)
          .firstWhere((x) => x.label == '职业限定技能选择完成');
      expect(row.ok, isFalse, reason: '构造前提失败：这一项应标红');
      expect(row.stepId, 'skills',
          reason: '跳到 ${row.stepId} = P2 的 D2 回归');
    });

    testWidgets('真实 DiceRealmApp 宿主下，点「去修复 →」真的回调 skills',
        (tester) async {
      String? jumpedTo;
      final c = incompleteOccCard();
      await pumpApp(
        tester,
        home: Scaffold(
          body: StepSummary(draft: c, onJumpTo: (id) => jumpedTo = id),
        ),
      );
      // 完成页本身能构建（SharePanel 已塞进来，ShareScope 必须已挂）
      expect(find.byType(StepSummary), findsOneWidget);
      expect(find.byType(SharePanel), findsOneWidget);
      expect(find.byKey(const Key('share_unconfigured')), findsOneWidget);
      final key = const Key('fix_职业限定技能选择完成');
      expect(find.byKey(key), findsOneWidget, reason: '该检查项应有「去修复」按钮');
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(jumpedTo, 'skills');
    });
  });

  // ==========================================================
  group('H5-4 真实 DiceRealmApp 宿主下完成页能正常构建（ShareScope 已挂）', () {
    testWidgets('StepSummary 在 DiceRealmApp 里构建无异常，SharePanel 可见',
        (tester) async {
      final c = qaCard();
      await pumpApp(
        tester,
        home: Scaffold(body: StepSummary(draft: c)),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(StepSummary), findsOneWidget);
      expect(find.byType(SharePanel), findsOneWidget);
      expect(find.byKey(const Key('share_unconfigured')), findsOneWidget);
    });

    testWidgets('未配置分享：UI 给「去设置」引导、不摆上传按钮、零请求',
        (tester) async {
      final api = FakeShareApi(base: '');
      final share = await useFakeShare(api);
      await pumpApp(
        tester,
        share: share,
        home: Scaffold(
          body: SingleChildScrollView(child: SharePanel(card: qaCard())),
        ),
      );
      expect(find.byKey(const Key('share_unconfigured')), findsOneWidget);
      expect(find.byKey(const Key('share_go_settings')), findsOneWidget);
      expect(find.byKey(const Key('share_create')), findsNothing);
      expect(find.textContaining('去设置里填写服务地址'), findsOneWidget);
      expect(api.createCalls, 0, reason: '未配置时一个请求都不能发');
      await tapKey(tester, 'share_go_settings');
      expect(find.byKey(const Key('settings_ai_base')), findsOneWidget,
          reason: '「去设置」应真的跳到设置页，而不是静默失败');
    });

    testWidgets('Scope 层级顺序 RepoScope → SettingsScope → ShareScope',
        (tester) async {
      await pumpApp(tester, home: const SizedBox.shrink());
      expect(find.byType(RepoScope), findsOneWidget);
      expect(find.byType(SettingsScope), findsOneWidget);
      expect(find.byType(ShareScope), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(ShareScope),
          matching: find.byType(SettingsScope),
        ),
        findsOneWidget,
        reason: 'ShareScope 必须在 SettingsScope 之内',
      );
      expect(
        find.ancestor(
          of: find.byType(SettingsScope),
          matching: find.byType(RepoScope),
        ),
        findsOneWidget,
        reason: 'SettingsScope 必须在 RepoScope 之内',
      );
    });
  });

  // ==========================================================
  group('结构性风险 1：wrapWithScopes 会不会掩盖真实配置错误', () {
    test('repo_scope.dart:73-77 的 ShareScope.of assert 原样保留', () {
      final src = File('lib/repo/repo_scope.dart').readAsStringSync();
      final lines = src.split('\n');
      // 行号 73-77（1-based）
      final block = lines.skip(72).take(5).join('\n');
      expect(block, contains('static ShareService of(BuildContext context)'));
      expect(block, contains('assert(scope != null'));
      expect(block, contains('ShareScope 未挂载'));
      expect(block, contains('return scope!.service;'),
          reason: '不能改成宽容返回 / 兜底默认值');
      // 三个 Scope 的 assert 都还在
      for (final name in <String>['RepoScope', 'SettingsScope', 'ShareScope']) {
        expect(src, contains("assert(scope != null, '$name 未挂载"),
            reason: '$name.of 的断言被弱化');
      }
      expect(src.contains('scope?.') || src.contains('scope ??'), isFalse,
          reason: '出现了宽容返回写法');
    });

    test('wrapWithScopes 的 Scope 顺序与 app.dart:39-53 一致', () {
      final app = File('lib/app.dart').readAsStringSync();
      final harness = File('test/support/app_harness.dart').readAsStringSync();
      int order(String s, String w) => s.indexOf(w);
      expect(order(app, 'RepoScope(') < order(app, 'SettingsScope('), isTrue);
      expect(order(app, 'SettingsScope(') < order(app, 'ShareScope('), isTrue);
      // helper 里是链式 child 写法，按出现顺序同样是 Repo → Settings → Share
      final start = harness.indexOf('Future<Widget> wrapWithScopes');
      final body = harness.substring(start);
      expect(order(body, 'RepoScope(') < order(body, 'SettingsScope('), isTrue);
      expect(order(body, 'SettingsScope(') < order(body, 'ShareScope('), isTrue);
      expect(body, contains('ShareScope(service: share, child: child)'));
    });

    testWidgets('裸宿主（没挂 Scope）调 ShareScope.of 会当场炸，不会被静默吞掉',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            ShareScope.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      final e = tester.takeException();
      expect(e, isNotNull, reason: '断言被改成了宽容返回？');
      expect('$e', contains('ShareScope 未挂载'));
    });
  });
}
