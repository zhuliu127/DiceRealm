// ============================================================
// p8_wizard_nav_test.dart — 需求 8：九步向导可以**自由跳转**
//
// 用户原话：
//   「改为可以点击第 1-第 9 步的按钮自由选择 1～9 做哪一步，
//     现在只能点很多下上一步（比如我车到了第 8 步，但是想回去改第 4 步的内容，
//     只能不断点上一步，无法自由跳转）」
//
// 这里钉住四件事：
//   ① 顶部 9 段进度条真的能点，点第 N 段 = 跳第 N 步（`step_progress` 跟着变）
//   ② 往回跳 / 跳到数据还不全的步：不校验、不崩、内容正确
//   ③ 「步骤总览」列出的第 1-9 步点哪个跳哪个
//   ④ 自由跳转**不能变成绕过校验的后门**：从第 1 步直接跳到末步保存，
//      仍然会被拦回第一个不合格的步骤
//   ⑤ 第 2 步选完职业后，焦点不再自动跑到年龄输入框（需求 11 前半）
// ============================================================

import 'package:dice_realm/net/share_client.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/repo_scope.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/repo/share_store.dart';
import 'package:dice_realm/ui/create/create_flow_page.dart';
import 'package:dice_realm/ui/create/steps/step_attrs.dart';
import 'package:dice_realm/ui/create/steps/step_basics.dart';
import 'package:dice_realm/ui/create/steps/step_rules.dart';
import 'package:dice_realm/ui/create/steps/step_skills.dart';
import 'package:dice_realm/ui/create/steps/step_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只挂三个 Scope 的极简宿主（与 `DiceRealmApp` 同构）。
///
/// 故意不走 `app_harness.pumpApp`（那会拖进整个 `DiceRealmApp` / 首页）——
/// 本文件要测的是向导内部的跳转逻辑，跟首页无关。
/// 概要页内嵌了 SharePanel，所以 ShareScope 必须挂（分享用未配置的客户端，
/// 测试里绝不联网）。
Future<CharacterRepo> _pumpFlow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = CharacterRepo(storage: MemoryStorage());
  final settings = SettingsRepo(storage: MemorySettingsStorage());
  final store = ShareStore(storage: MemoryShareStorage());
  await repo.load();
  await settings.load();
  await store.load();
  final share = ShareService(
    client: ShareClient(baseProvider: () => ''),
    store: store,
  );

  await tester.pumpWidget(
    RepoScope(
      repo: repo,
      child: SettingsScope(
        repo: settings,
        child: ShareScope(
          service: share,
          child: const MaterialApp(home: CreateFlowPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// 读某个 key 的文本（不存在直接失败，避免「假通过」）
String _textOf(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  expect(f, findsOneWidget, reason: '找不到 $key');
  return tester.widget<Text>(f).data ?? '';
}

/// 当前有没有输入框处于 focused 状态
bool _anyEditableFocused(WidgetTester tester) {
  for (final state in tester.stateList<EditableTextState>(
    find.byType(EditableText),
  )) {
    if (state.widget.focusNode.hasFocus) return true;
  }
  return false;
}

/// 点某个 key 并等动画（不依赖 app_harness：本文件自带宿主）
Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('需求 8：点第 N 段进度条就跳到第 N 步', () {
    testWidgets('第 1 步 → 第 5 步 → 回第 2 步，进度文本与页面内容同步', (tester) async {
      await _pumpFlow(tester);
      expect(_textOf(tester, 'step_progress'), '1 / 9');
      expect(find.byType(StepRules), findsOneWidget);

      // 点第 5 段（0 基下标 4）= 职业技能
      await tapKey(tester, 'step_jump_4');
      expect(_textOf(tester, 'step_progress'), '5 / 9');
      expect(find.byType(StepSkills), findsOneWidget);
      // 还没选职业：技能页要给出空态，而不是崩 / 白屏
      expect(find.text('还没有选择职业'), findsOneWidget);
      expect(find.byKey(const Key('step_error')), findsNothing, reason: '跳转不该报校验错');

      // 回第 2 步（下标 1）：基本资料页的输入框在
      await tapKey(tester, 'step_jump_1');
      expect(_textOf(tester, 'step_progress'), '2 / 9');
      expect(find.byType(StepBasics), findsOneWidget);
      expect(find.byKey(const Key('field_name')), findsOneWidget);
      expect(find.byKey(const Key('field_age')), findsOneWidget);
    });

    testWidgets('跳到数据全空的步骤也能正常渲染（属性 / 概要）', (tester) async {
      await _pumpFlow(tester);

      await tapKey(tester, 'step_jump_2'); // 属性分配
      expect(_textOf(tester, 'step_progress'), '3 / 9');
      expect(find.byType(StepAttrs), findsOneWidget);
      expect(find.byKey(const Key('attr_str')), findsOneWidget);

      await tapKey(tester, 'step_jump_8'); // 概要
      expect(_textOf(tester, 'step_progress'), '9 / 9');
      expect(find.byType(StepSummary), findsOneWidget);

      // 再跳回第 1 步：状态没被重置（IndexedStack 保活）
      await tapKey(tester, 'step_jump_0');
      expect(_textOf(tester, 'step_progress'), '1 / 9');
      expect(find.byType(StepRules), findsOneWidget);
    });

    testWidgets('跳转不强制校验目标步（回去改内容不该被拦）', (tester) async {
      await _pumpFlow(tester);
      // 第 2 步全空 —— 若跳转会校验，跳第 3 步会被拦下来
      await tapKey(tester, 'step_jump_1');
      expect(_textOf(tester, 'step_progress'), '2 / 9');
      await tapKey(tester, 'step_jump_2');
      expect(_textOf(tester, 'step_progress'), '3 / 9');
      expect(find.byKey(const Key('step_error')), findsNothing);
    });

    testWidgets('「步骤总览」列出 1-9 步，点哪条跳哪条', (tester) async {
      await _pumpFlow(tester);

      await tapKey(tester, 'btn_step_overview');
      // 九条都在（带名字）
      for (var i = 0; i < 9; i++) {
        expect(
          find.byKey(Key('step_overview_$i')),
          findsOneWidget,
          reason: '总览缺第 ${i + 1} 步',
        );
      }
      expect(find.text('资产与信用评级'), findsWidgets);

      await tapKey(tester, 'step_overview_3'); // 第 4 步：资产
      expect(_textOf(tester, 'step_progress'), '4 / 9');
      expect(find.byKey(const Key('credit_input')), findsOneWidget);

      // 再来一次：跳到第 8 步（角色背景）
      await tapKey(tester, 'btn_step_overview');
      await tapKey(tester, 'step_overview_7');
      expect(_textOf(tester, 'step_progress'), '8 / 9');
    });

    testWidgets('自由跳转不是后门：直接跳到末步保存仍会被拦回第一个问题页', (tester) async {
      final repo = await _pumpFlow(tester);

      await tapKey(tester, 'step_jump_8'); // 直接跳概要
      expect(_textOf(tester, 'step_progress'), '9 / 9');

      await tapKey(tester, 'btn_next'); // 「保存角色卡」
      // 没落库，而且被送回第 2 步（姓名都没填）
      expect(repo.alive, isEmpty, reason: '不合格的卡绝不能保存');
      expect(_textOf(tester, 'step_progress'), '2 / 9');
      expect(find.byKey(const Key('step_error')), findsOneWidget);
      expect(find.text('请填写角色姓名'), findsOneWidget);
    });
  });

  group('需求 11 前半：选完职业后焦点不跑到年龄输入框', () {
    testWidgets('选职业前后都没有输入框被抢焦点，输入法不会自己弹出来', (tester) async {
      await _pumpFlow(tester);
      await tapKey(tester, 'step_jump_1'); // 第 2 步
      expect(find.byType(StepBasics), findsOneWidget);

      // 先制造「年龄输入框刚被聚焦过」的前置条件 —— 这正是用户复现的路径
      await tester.enterText(find.byKey(const Key('field_age')), '32');
      await tester.pumpAndSettle();
      expect(_anyEditableFocused(tester), isTrue, reason: '前置条件：年龄框刚才有焦点');

      await tapKey(tester, 'btn_pick_occupation');
      await tester.enterText(find.byKey(const Key('field_occ_search')), '法官');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '法官').first);
      await tester.pumpAndSettle();

      // 选上了
      expect(find.text('法官'), findsWidgets);
      // 关键断言：没有任何输入框还在 focused，输入法也没弹（isVisible=false）
      expect(
        _anyEditableFocused(tester),
        isFalse,
        reason: '选完职业后焦点不该落在任何输入框上',
      );
      expect(
        tester.testTextInput.isVisible,
        isFalse,
        reason: '选完职业后输入法不该弹出来',
      );
      // 数据确实写进去了（焦点修复不能顺手弄丢选择）
      expect(find.text('选择职业…'), findsNothing);
    });
  });
}
