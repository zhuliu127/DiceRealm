// ============================================================
// sheet_ai_rp_test.dart — AI RP 弹层
//
// 最要紧的一条不是「能生成」，而是 **生成后不会自动发送**：
// 模型输出可能 OOC、可能替 KP 宣布了裁定、可能带设定错误。
// 自动发出去就等于替玩家做了发言决定，而且已经进了所有人可见的 chats。
//
// 所以每条成功用例都要额外断言 `f.sent` 零增加。
//
// AiClient 用 `extends` + override `chat` 注入（它是具体类，
// 但 `chat` 是可覆盖的实例方法，不需要为它抽接口）。
// ============================================================

import 'dart:async' show Completer;

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/net/ai_client.dart'
    show
        AiChatMeta,
        AiChatResult,
        AiClient,
        AiConfig,
        AiErrorKind,
        AiException,
        aiDefaultMaxTokens,
        aiDefaultTimeout;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:dice_realm/ui/room/sheets/sheet_ai_rp.dart'
    show AiRpKeys, AiRpSheet;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 可控的假客户端。
class _FakeAi extends AiClient {
  _FakeAi({this.reply = '', this.error, this.gate})
    : super(
        configProvider: () =>
            const AiConfig(base: 'https://example.test', model: 'm', key: 'k'),
      );

  final String reply;
  final Object? error;

  /// 非空时 `chat` 会等它完成（用来验「生成中按钮禁用」）。
  final Completer<void>? gate;

  final List<List<Map<String, String>>> calls =
      <List<Map<String, String>>>[];
  double? lastTemperature;
  int? lastMaxTokens;
  Duration? lastTimeout;

  @override
  Future<AiChatResult> chat(
    List<Map<String, String>> messages, {
    double temperature = 0.9,
    int maxTokens = aiDefaultMaxTokens,
    Duration timeout = aiDefaultTimeout,
    void Function(AiChatMeta meta)? onMeta,
  }) async {
    calls.add(messages);
    lastTemperature = temperature;
    lastMaxTokens = maxTokens;
    lastTimeout = timeout;
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return AiChatResult(text: reply, meta: const AiChatMeta());
  }
}

Widget _scopedApp(RoomUiFixture f, Widget body, {String seat = kHostSeat}) =>
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) =>
          f.scoped(seat, child: child ?? const SizedBox.shrink()),
      home: Scaffold(body: SingleChildScrollView(child: body)),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  group('AI RP 弹层', () {
    testWidgets('★ 打开就有「结果只填输入框、不会自动发送」的明示', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      await tester.pumpWidget(
        _scopedApp(f, AiRpSheet(onFilled: (String _) {}, client: _FakeAi())),
      );
      await _settle(tester);

      final hint = tester.widget<Text>(find.byKey(AiRpKeys.hint)).data ?? '';
      expect(hint.contains('不会自动发送'), isTrue,
          reason: '★ 不写这句，用户会以为点生成就已经发出去了');
      expect(find.byKey(AiRpKeys.idea), findsOneWidget);
      expect(find.byKey(AiRpKeys.generate), findsOneWidget);
    });

    testWidgets('★ 空输入 → 只提示「先写一句」，不打网络', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);
      final ai = _FakeAi(reply: '不该被调用');

      await tester.pumpWidget(
        _scopedApp(f, AiRpSheet(onFilled: (String _) {}, client: ai)),
      );
      await _settle(tester);

      await tester.tap(find.byKey(AiRpKeys.generate));
      await _settle(tester);

      expect(ai.calls, isEmpty, reason: '★ 空想法不该发请求（白花钱还没用）');
      expect(f.localOf(kHostSeat).notice, contains('先写一句'));
    });

    testWidgets('★★ 生成成功 → 回填文本、关闭弹层、且**零发包**（不自动发送）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      String? filled;
      // 模型返回带包装的文本，验证清洗确实生效
      final ai = _FakeAi(reply: 'RP：「我按住门把，听见里面有人在数数。」');
      final int sentBefore = f.sent.length;

      await tester.pumpWidget(
        _scopedApp(
          f,
          AiRpSheet(onFilled: (String t) => filled = t, client: ai),
        ),
      );
      await _settle(tester);

      await tester.enterText(find.byKey(AiRpKeys.idea), '我想听听门后');
      await tester.pump();
      await tester.tap(find.byKey(AiRpKeys.generate));
      await _settle(tester);

      expect(filled, '我按住门把，听见里面有人在数数。',
          reason: '★ 前缀与外层引号都要被清洗掉');
      expect(f.sent.length, sentBefore,
          reason: '★★ 只填输入框，绝不自动发送 —— 这是 PRD P1-12 的硬约束');
      expect(f.localOf(kHostSeat).notice, contains('改完再点'));
    });

    testWidgets('传给模型的参数与旧版一致（0.85 / 1200 / 60s）', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);
      final ai = _FakeAi(reply: '一段 RP');

      await tester.pumpWidget(
        _scopedApp(f, AiRpSheet(onFilled: (String _) {}, client: ai)),
      );
      await _settle(tester);
      await tester.enterText(find.byKey(AiRpKeys.idea), '动作');
      await tester.pump();
      await tester.tap(find.byKey(AiRpKeys.generate));
      await _settle(tester);

      expect(ai.lastTemperature, 0.85, reason: 'RP 比车卡（0.9）稍稳');
      expect(ai.lastMaxTokens, 1200);
      expect(ai.lastTimeout, const Duration(seconds: 60));
    });

    testWidgets('★ 模型返回空内容 → 明确报错，不回填空串', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      String? filled;
      // 只有包装没有正文
      final ai = _FakeAi(reply: 'RP：');

      await tester.pumpWidget(
        _scopedApp(f, AiRpSheet(onFilled: (String t) => filled = t, client: ai)),
      );
      await _settle(tester);
      await tester.enterText(find.byKey(AiRpKeys.idea), '动作');
      await tester.pump();
      await tester.tap(find.byKey(AiRpKeys.generate));
      await _settle(tester);

      expect(filled, isNull, reason: '★ 空串回填进输入框等于把玩家已打的字清空');
      final status = tester.widget<Text>(find.byKey(AiRpKeys.status)).data ?? '';
      expect(status.contains('空内容'), isTrue);
    });

    testWidgets('★ AI 未配置 → 直接说「去设置里填」，不是笼统「生成失败」',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      final ai = _FakeAi(
        error: AiException(AiErrorKind.notConfigured, '还没填写接口地址，请先到「设置」里配置'),
      );

      await tester.pumpWidget(
        _scopedApp(f, AiRpSheet(onFilled: (String _) {}, client: ai)),
      );
      await _settle(tester);
      await tester.enterText(find.byKey(AiRpKeys.idea), '动作');
      await tester.pump();
      await tester.tap(find.byKey(AiRpKeys.generate));
      await _settle(tester);

      final status = tester.widget<Text>(find.byKey(AiRpKeys.status)).data ?? '';
      expect(status.contains('设置'), isTrue,
          reason: '★ 用户需要知道下一步去哪，而不是「失败了」');
    });

    testWidgets('★ 生成中按钮禁用（防连点烧 token）', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      final gate = Completer<void>();
      final ai = _FakeAi(reply: '一段 RP', gate: gate);

      await tester.pumpWidget(
        _scopedApp(f, AiRpSheet(onFilled: (String _) {}, client: ai)),
      );
      await _settle(tester);
      await tester.enterText(find.byKey(AiRpKeys.idea), '动作');
      await tester.pump();
      await tester.tap(find.byKey(AiRpKeys.generate));
      await tester.pump();

      expect(ai.calls.length, 1);
      final btn = tester.widget<RoomTap>(find.byKey(AiRpKeys.generate));
      expect(btn.enabled, isFalse, reason: '★ 生成中再点一次就是重复扣费');
      expect(find.text('生成中…'), findsWidgets);

      // 再点一次也不该发第二个请求
      await tester.tap(find.byKey(AiRpKeys.generate), warnIfMissed: false);
      await tester.pump();
      expect(ai.calls.length, 1);

      gate.complete();
      await _settle(tester);
    });

    testWidgets('KP 与玩家的说明文案不同（KP 写场景 / 玩家演自己）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      await tester.pumpWidget(
        _scopedApp(f, AiRpSheet(onFilled: (String _) {}, client: _FakeAi())),
      );
      await _settle(tester);
      final kpHint = tester.widget<Text>(find.byKey(AiRpKeys.hint)).data ?? '';
      expect(kpHint.contains('场景描写'), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _scopedApp(
          f,
          AiRpSheet(onFilled: (String _) {}, client: _FakeAi()),
          seat: 'p1',
        ),
      );
      await _settle(tester);
      final plHint = tester.widget<Text>(find.byKey(AiRpKeys.hint)).data ?? '';
      expect(plHint.contains('调查员'), isTrue);
    });
  });
}
