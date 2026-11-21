// ============================================================
// ai_create_page_test.dart — ✨ AI 车卡 / 快速开始（widget）
//
// 全部注入假生成函数，**不联网**。重点覆盖旧版踩过的四个坑：
//   ① 未配置时给引导，不是报错；点「去配置」能进设置页
//   ② 生成中**可取消**、有秒数与阶段消息
//   ③ 失败必须能回退 —— 「改用规则生成」要**真的出卡**，不能只弹提示
//   ④ 生成成功 → 「就用这张」真的进 9 步向导（带着已填的卡）
// ============================================================

import 'dart:async';

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/net/ai_client.dart';
import 'package:dice_realm/net/ai_create.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/ui/ai_create_page.dart';
import 'package:dice_realm/ui/create/create_flow_page.dart';
import 'package:dice_realm/ui/create/rule_pick_page.dart';
import 'package:dice_realm/ui/random_create_page.dart';
import 'package:dice_realm/ui/settings_page.dart';
import 'package:dice_realm/ui/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/oracle.dart';

/// 造一张合法的成品卡（走真规则引擎，确定性）
Character makeCard({String name = '林晚'}) {
  final rng = Lcg(424242);
  setRng(rng.call);
  setClock(() => oracleNowMs);
  uidDeterministic = true;
  final c = preset.generateOne()!;
  c.raw['characterName'] = name;
  return c;
}

AiCreateResult resultFor(Character c) => AiCreateResult(
  character: c,
  profile: const <String, Object?>{'fromAI': true},
  raw: const <String, Object?>{},
  caps: const AiCaps(),
  attrScaled: false,
);

/// 已配置 AI 的设置仓库
Future<SettingsRepo> configuredSettings() async {
  final s = await newMemorySettings();
  s
    ..aiBase = 'https://api.example.com/v1'
    ..aiModel = 'm'
    ..aiKey = 'sk-abcdefghijklmnop';
  await s.save();
  return s;
}

void main() {
  testWidgets('首页有「✨ AI 车卡」入口，点了先进规则选择页再进 AI 车卡页', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('fab_ai_create')), findsOneWidget);
    expect(find.byKey(const Key('fab_new_card')), findsOneWidget);
    await tapKey(tester, 'fab_ai_create');
    // ★ P9 需求 5：四个入口统一先到「选择规则系统」。
    expect(find.byType(RulePickPage), findsOneWidget);
    expect(find.byType(AiCreatePage), findsNothing);
    await tapKey(tester, 'rule_pick_coc7');
    expect(find.byType(AiCreatePage), findsOneWidget);
  });

  testWidgets('未配置 AI：给引导而不是报错；「去配置」能进设置页', (tester) async {
    await pumpApp(tester, settings: await newMemorySettings());
    await tapKey(tester, 'fab_ai_create');
    await tapKey(tester, 'rule_pick_coc7'); // P9：先选规则

    // 默认设置里 aiKey 为空 → 未配置
    expect(find.byKey(const Key('ai_go_settings')), findsOneWidget);
    expect(
      find.byKey(const Key('ai_desc')),
      findsNothing,
      reason: '未配置时不该给输入框',
    );

    await tapKey(tester, 'ai_go_settings');
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('已配置 AI：输入框 / 示例 / 世界设定 / 上限档位都在', (tester) async {
    final settings = await configuredSettings();
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, settings: settings);
    await tapKey(tester, 'fab_ai_create');
    await tapKey(tester, 'rule_pick_coc7'); // P9：先选规则

    expect(find.byKey(const Key('ai_desc')), findsOneWidget);
    expect(find.textContaining('一个在旧书店打工'), findsOneWidget);
    expect(find.byKey(const Key('ai_setting')), findsOneWidget);
    expect(find.byKey(const Key('ai_cap_不限')), findsOneWidget);
    expect(find.byKey(const Key('ai_cap_标准')), findsOneWidget);
    expect(find.byKey(const Key('ai_cap_严格')), findsOneWidget);

    final line = tester.widget<Text>(find.byKey(const Key('ai_caps_text')));
    expect(line.data, contains('暂未设置数值上限'));

    // 选「标准」→ 写回设置，文案立刻变成逐字的 capsText
    await tapKey(tester, 'ai_cap_标准');
    expect(settings.aiAttrCap, 460);
    expect(settings.aiOccPtsCap, 85);
    expect(settings.aiIntPtsCap, 70);
    final after = tester.widget<Text>(find.byKey(const Key('ai_caps_text')));
    expect(after.data, contains('属性总和 ≤ 460（含幸运）'));
    expect(after.data, contains('每项本职技能 ≤ 85'));
    expect(after.data, contains('每项兴趣技能 ≤ 70'));
  });

  testWidgets('描述为空时点生成 → 只提示，不调模型', (tester) async {
    var calls = 0;
    await pumpApp(
      tester,
      settings: await configuredSettings(),
      home: AiCreatePage(
        generate: (req, onStage) async {
          calls++;
          return resultFor(makeCard());
        },
      ),
    );
    await tester.tap(find.byKey(const Key('ai_generate')));
    await tester.pumpAndSettle();

    expect(find.textContaining('先写一句描述'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('生成成功 → 结果卡 + 「继续完善」进 8 步向导', (tester) async {
    final card = makeCard();
    await pumpApp(
      tester,
      settings: await configuredSettings(),
      home: AiCreatePage(generate: (req, onStage) async => resultFor(card)),
    );

    await tester.enterText(find.byKey(const Key('ai_desc')), '民国时期的私家侦探');
    await tapKey(tester, 'ai_generate');

    expect(find.byKey(const Key('ai_result_card')), findsOneWidget);
    expect(find.textContaining('林晚'), findsWidgets);

    // ★ P9 需求 6：按钮拆成「就用这张」/「继续完善」，这里走的是后者。
    await scrollTo(tester, 'result_continue_edit');
    await tapKey(tester, 'result_continue_edit');
    expect(
      find.byType(CreateFlowPage),
      findsOneWidget,
      reason: '「继续完善」必须真的进向导',
    );
  });

  testWidgets('生成中：显示秒数与阶段消息，并且可以取消', (tester) async {
    final completer = Completer<AiCreateResult>();
    var cancelled = 0;

    await pumpApp(
      tester,
      settings: await configuredSettings(),
      home: AiCreatePage(
        generate: (req, onStage) {
          onStage('模型回复被截断（思考链占用了太多额度），正在用更大额度重试…');
          return completer.future;
        },
        onCancel: () => cancelled++,
      ),
    );

    await tester.enterText(find.byKey(const Key('ai_desc')), '一个法医');
    await tester.tap(find.byKey(const Key('ai_generate')));
    await tester.pump(); // 进入 busy

    expect(find.byKey(const Key('ai_busy')), findsOneWidget);
    final stage = tester.widget<Text>(find.byKey(const Key('ai_stage')));
    expect(stage.data, contains('正在用更大额度重试'));

    // 秒数会跳动（不是转圈干等）
    await tester.pump(const Duration(seconds: 2));
    final elapsed = tester.widget<Text>(find.byKey(const Key('ai_elapsed')));
    expect(elapsed.data, contains('已用'));

    // 生成中有一个无限循环的进度圈，不能用 pumpAndSettle（会一直等）
    await tester.tap(find.byKey(const Key('ai_cancel')));
    await tester.pump();
    expect(cancelled, 1);

    // 收尾：让 future 完成，避免留下 pending timer
    completer.complete(resultFor(makeCard()));
    await tester.pumpAndSettle();
  });

  testWidgets('生成失败 → 错误卡 + 「改用一键出卡」真的能拿到 5 张卡', (tester) async {
    await pumpApp(
      tester,
      settings: await configuredSettings(),
      home: AiCreatePage(
        generate: (req, onStage) async =>
            throw AiException(AiErrorKind.serverError, '模型服务端出错（500），稍后再试'),
      ),
    );

    await tester.enterText(find.byKey(const Key('ai_desc')), '一个法医');
    await tapKey(tester, 'ai_generate');

    expect(find.byKey(const Key('ai_error')), findsOneWidget);
    final msg = tester.widget<Text>(find.byKey(const Key('ai_error_text')));
    expect(msg.data, contains('服务端出错'));

    // 一键回退：不许只弹提示，必须真的能拿到卡。
    // ★ P8：兜底从「就地出 5 张候选」改为跳到独立的一键出卡页 ——
    //   本页只负责 AI，随机卡整体搬到 /random。
    await scrollTo(tester, 'ai_fallback_random');
    await tapKey(tester, 'ai_fallback_random');

    expect(find.byType(RandomCreatePage), findsOneWidget);
    expect(
      find.byType(SummaryCard, skipOffstage: false),
      findsNWidgets(5),
      reason: '兜底必须真的出 5 张完整卡',
    );
    for (var i = 0; i < 5; i++) {
      // ★ P9 需求 6：每张候选卡两个按钮（键带下标区分卡片）。
      expect(
        find.byKey(Key('result_use_this_$i'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('result_continue_edit_$i'), skipOffstage: false),
        findsOneWidget,
      );
    }
  });

  testWidgets('「一键出卡」入口：跳随机页 → 选一张进向导；未选中的不落库',
      (tester) async {
    final repo = await newMemoryRepo();
    await pumpApp(
      tester,
      repo: repo,
      settings: await configuredSettings(),
      home: const AiCreatePage(generate: _neverCalled),
    );

    // P8：本页不再有随机候选卡 UI
    expect(
      find.byKey(const Key('preset_candidate_0'), skipOffstage: false),
      findsNothing,
      reason: 'AI 页只做 AI，候选卡 UI 已搬到 /random',
    );

    await scrollTo(tester, 'ai_entry_random');
    await tapKey(tester, 'ai_entry_random');
    expect(find.byType(RandomCreatePage), findsOneWidget);
    expect(
      find.byKey(const Key('random_candidate_0'), skipOffstage: false),
      findsOneWidget,
    );
    expect(repo.all, isEmpty, reason: '候选卡只存在内存里，没点「用这张」不该保存');

    await scrollTo(tester, 'result_continue_edit_0');
    await tapKey(tester, 'result_continue_edit_0');
    expect(find.byType(CreateFlowPage), findsOneWidget);
    expect(repo.all, isEmpty, reason: '进向导也还没保存（保存要走到末步）');
  });
}

Future<AiCreateResult> _neverCalled(
  AiGenerateRequest req,
  void Function(String) onStage,
) => Future<AiCreateResult>.error(
  AiException(AiErrorKind.notConfigured, '测试不该走到这里'),
);
