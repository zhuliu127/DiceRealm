// ============================================================
// settings_page_test.dart — 设置页（内存后端 + 假探测，不联网）
//
// 覆盖：
//   · 首页右上角「数据」菜单 → 设置入口 → 设置页
//   · AI 三项保存 / 地址格式校验 / Key 显隐与脱敏展示
//   · 测试连接：成功 / Key 无效 / 模型不在列表里（三种要能分开）
//   · 数值上限保存与「全部清除」
//   · 分享 / 跑团地址的状态文案（留空 = 未配置；跑团明确标注 P4）
//   · 技能上限 / 自动保存
// ============================================================

import 'package:dice_realm/domain/ai_probe.dart';
import 'package:dice_realm/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 从首页进设置页
Future<void> openSettings(WidgetTester tester) async {
  await tapKey(tester, 'home_menu');
  await tapKey(tester, 'menu_settings');
  expect(find.byType(SettingsPage), findsOneWidget);
}

void main() {
  testWidgets('首页「数据」菜单里有设置入口，点了能进设置页', (tester) async {
    await pumpApp(tester);
    await tapKey(tester, 'home_menu');
    expect(find.byKey(const Key('menu_settings')), findsOneWidget);
    // 原有的两项还在（不能因为加设置而挤掉导出/导入）
    expect(find.byKey(const Key('menu_export_all')), findsOneWidget);
    expect(find.byKey(const Key('menu_import')), findsOneWidget);

    await tapKey(tester, 'menu_settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byKey(const Key('settings_ai_base')), findsOneWidget);
    // 默认值就是 DeepSeek（只补 Key 就能用）
    final base = tester.widget<TextField>(
      find.byKey(const Key('settings_ai_base')),
    );
    expect(base.controller!.text, 'https://api.deepseek.com/v1');
    final model = tester.widget<TextField>(
      find.byKey(const Key('settings_ai_model')),
    );
    expect(model.controller!.text, 'deepseek-flash');
  });

  testWidgets('AI 三项保存到仓库；地址格式不对时不保存', (tester) async {
    final settings = await newMemorySettings();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    // 格式不对 → 不保存
    await tester.enterText(
      find.byKey(const Key('settings_ai_base')),
      'api.example.com/v1',
    );
    await tapKey(tester, 'settings_save_ai');
    expect(settings.aiBase, 'https://api.deepseek.com/v1', reason: '非法地址不该被写入');

    // 正确保存
    await tester.enterText(
      find.byKey(const Key('settings_ai_base')),
      'https://api.example.com/v1',
    );
    await tester.enterText(
      find.byKey(const Key('settings_ai_model')),
      'my-model',
    );
    await tester.enterText(
      find.byKey(const Key('settings_ai_key')),
      'sk-abcdefghijklmnop',
    );
    await tapKey(tester, 'settings_save_ai');

    expect(settings.aiBase, 'https://api.example.com/v1');
    expect(settings.aiModel, 'my-model');
    expect(settings.aiKey, 'sk-abcdefghijklmnop');

    // 状态行给的是**脱敏**后的 Key
    final state = tester.widget<Text>(
      find.byKey(const Key('settings_ai_state')),
    );
    expect(state.data, contains('****'));
    expect(state.data, isNot(contains('abcdefghijklmnop')));
    expect(settings.aiConfigured, isTrue);
  });

  testWidgets('Key 默认是密码框，点「显示」才可见', (tester) async {
    final settings = await newMemorySettings();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    TextField keyField() =>
        tester.widget<TextField>(find.byKey(const Key('settings_ai_key')));
    expect(keyField().obscureText, isTrue);
    await tapKey(tester, 'settings_ai_key_toggle');
    expect(keyField().obscureText, isFalse);
    await tapKey(tester, 'settings_ai_key_toggle');
    expect(keyField().obscureText, isTrue);
  });

  testWidgets('测试连接：成功 → 结果卡显示「连接正常」', (tester) async {
    final probe = FakeAiProbe();
    final settings = await newMemorySettings(probe: probe);
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    // 三项齐全才允许测试
    await tester.enterText(
      find.byKey(const Key('settings_ai_base')),
      'https://api.example.com/v1',
    );
    await tester.enterText(
      find.byKey(const Key('settings_ai_model')),
      'my-model',
    );
    await tester.enterText(
      find.byKey(const Key('settings_ai_key')),
      'sk-abcdefghijklmnop',
    );
    await tapKey(tester, 'settings_test_conn');

    expect(probe.calls, 1);
    expect(probe.lastBase, 'https://api.example.com/v1');
    expect(probe.lastModel, 'my-model');
    expect(probe.lastKey, 'sk-abcdefghijklmnop');

    expect(find.byKey(const Key('settings_probe_result')), findsOneWidget);
    expect(find.text('连接正常'), findsOneWidget);
  });

  testWidgets('测试连接：Key 无效 / 模型不在列表里 要能分开显示', (tester) async {
    final probe = FakeAiProbe(
      result: const AiProbeResult(
        kind: AiProbeKind.badKey,
        via: 'models',
        message: 'API Key 不正确或已失效（401）',
      ),
    );
    final settings = await newMemorySettings(probe: probe);
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    await tester.enterText(
      find.byKey(const Key('settings_ai_base')),
      'https://api.example.com/v1',
    );
    await tester.enterText(
      find.byKey(const Key('settings_ai_model')),
      'my-model',
    );
    await tester.enterText(find.byKey(const Key('settings_ai_key')), 'sk-bad');
    await tapKey(tester, 'settings_test_conn');
    expect(find.text('Key 无效'), findsOneWidget);

    // 换成「模型不在列表里」
    probe.result = const AiProbeResult(
      kind: AiProbeKind.modelMissing,
      via: 'models',
      message: '地址与 Key 都通，但可用模型里没有「my-model」',
      models: <String>['deepseek-chat', 'deepseek-reasoner'],
      modelInList: false,
      hint: '该地址报告了 2 个模型',
    );
    await tapKey(tester, 'settings_test_conn');
    expect(find.text('模型不在列表里'), findsOneWidget);
    expect(find.textContaining('deepseek-chat'), findsOneWidget);
  });

  testWidgets('三项没填全时点测试 → 提示「三项都填好才能测试」，不打网络', (tester) async {
    final probe = FakeAiProbe();
    final settings = await newMemorySettings(probe: probe);
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    await tapKey(tester, 'settings_test_conn');
    expect(probe.calls, 0);
    expect(find.textContaining('三项都填好才能测试'), findsOneWidget);
  });

  testWidgets('数值上限：保存与「全部清除」', (tester) async {
    final settings = await newMemorySettings();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);

    await scrollTo(tester, 'settings_cap_attr');
    await tester.enterText(find.byKey(const Key('settings_cap_attr')), '420');
    await tester.enterText(find.byKey(const Key('settings_cap_occ')), '70');
    await tester.enterText(find.byKey(const Key('settings_cap_int')), '60');
    await tapKey(tester, 'settings_cap_luck_without');
    await tapKey(tester, 'settings_save_caps');

    expect(settings.aiAttrCap, 420);
    expect(settings.aiOccPtsCap, 70);
    expect(settings.aiIntPtsCap, 60);
    expect(settings.aiAttrCapWithLuck, isFalse);

    await tapKey(tester, 'settings_clear_caps');
    expect(settings.aiAttrCap, 0);
    expect(settings.aiOccPtsCap, 0);
    expect(settings.aiIntPtsCap, 0);
    expect(settings.aiAttrCapWithLuck, isTrue);
  });

  testWidgets('分享 / 跑团地址：留空即未配置（不再展示 P4 开发期说明）', (tester) async {
    final settings = await newMemorySettings();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);
    await scrollTo(tester, 'settings_share_base');

    final shareState = tester.widget<Text>(
      find.byKey(const Key('settings_share_state')),
    );
    expect(shareState.data, contains('未配置'));
    // 未配置时要说清「仍可用本机导出 / 长图」
    expect(shareState.data, contains('本机导出'));
    // ★ P10（用户要求）：设置页不再向用户展示「P4 才启用 / 本期只保存」这类
    //   开发期说明。这里反向钉住 —— 文案不许回来。
    expect(find.textContaining('P4'), findsNothing,
        reason: '开发期说明已从设置页移除，不该再出现');

    await tester.enterText(
      find.byKey(const Key('settings_share_base')),
      'https://share.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('settings_room_base')),
      'https://room.example.com',
    );
    await tapKey(tester, 'settings_save_services');

    expect(settings.shareBase, 'https://share.example.com');
    expect(settings.roomBase, 'https://room.example.com');
    expect(settings.shareConfigured, isTrue);
    final after = tester.widget<Text>(
      find.byKey(const Key('settings_share_state')),
    );
    expect(after.data, contains('https://share.example.com'));
  });

  testWidgets('技能上限保存 + 自动保存开关', (tester) async {
    final settings = await newMemorySettings();
    await pumpApp(tester, settings: settings);
    await openSettings(tester);
    await scrollTo(tester, 'settings_skill_cap');

    await tester.enterText(find.byKey(const Key('settings_skill_cap')), '88');
    await tapKey(tester, 'settings_save_misc');
    expect(settings.skillCap, 88);

    expect(settings.autoSave, isTrue);
    await scrollTo(tester, 'settings_auto_save');
    await tapKey(tester, 'settings_auto_save');
    expect(settings.autoSave, isFalse);
  });

  testWidgets('设置页不影响返回：返回后仍在首页', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('骰境TRPG'), findsOneWidget);
  });
}
