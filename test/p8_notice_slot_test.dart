// ============================================================
// test/p8_notice_slot_test.dart — 需求 9：疯狂消息广播「覆盖 + 2 秒」
//
// 原实现直接 showSnackBar：Flutter 的 SnackBar 是队列，连点「推进 1 轮」
// 会排队（每条默认 4 秒），后来的消息要等前面的全部播完 —— 用户看到
// 「消息广播很久才消失、新消息排在后面」。
//
// 修法：StatusEditor 的提示统一走 [showSlotNotice]（先 removeCurrentSnackBar
// 再 show，duration: 2s）。本文件用真实 widget 时钟验证：
//   ① 连续两条提示，屏幕上只出现新的那条（旧的被立刻移除）；
//   ② 2 秒后提示自动消失；
//   ③ 状态编辑面板里没有「昏迷」chip，有「潜在疯狂」chip。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/madness.dart' as mad;
import 'package:dice_realm/ui/card_edit/status_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('新提示直接覆盖旧提示，不再排队', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: ElevatedButton(
                key: const Key('go'),
                onPressed: () {
                  showSlotNotice(ctx, '第一条：推进 1 轮，没有临时疯狂到期');
                  showSlotNotice(ctx, '第二条：1 条疯狂症已消退');
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('第二条：1 条疯狂症已消退'), findsOneWidget);
    expect(find.textContaining('第一条'), findsNothing,
        reason: '旧消息必须被立刻移除，不能排在队列里');
  });

  testWidgets('提示仅显示 2 秒', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => Center(
              child: ElevatedButton(
                key: const Key('go'),
                onPressed: () => showSlotNotice(ctx, '两秒后消失'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('两秒后消失'), findsOneWidget);

    // 1.5 秒时还在（证明不是 0.5 秒一闪而过）
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('两秒后消失'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('两秒后消失'), findsNothing, reason: 'ttl 是 2 秒');
  });

  testWidgets('精神状态面板：没有「昏迷」，有「潜在疯狂」', (tester) async {
    final card = Character(newCharacter());
    card.raw['id'] = 'p8notice';
    card.status['currentSAN'] = 40;
    card.status['maxSAN'] = 40;
    card.status['currentHP'] = 10;
    card.status['maxHP'] = 10;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatusEditor(card: card, onChanged: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('status_chip_昏迷')), findsNothing);
    expect(find.byKey(const Key('status_chip_潜在疯狂')), findsOneWidget);
    expect(find.byKey(const Key('status_chip_疯狂症状')), findsOneWidget);
    // 身体状态里的「昏迷」开关必须还在（那是 unconscious 标记）
    expect(find.byKey(const Key('switch_unconscious')), findsOneWidget);

    // 需求 6：进入「临时疯狂」时自动获得一条会随轮次消失的疯狂症
    final chip = find.byKey(const Key('status_chip_临时疯狂'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(mad.list(card).length, 1);
    expect(mad.list(card).any((x) => !jsTruthy(asMap(x)['permanent'])), isTrue);
    expect(asList(card.status['mental']).map(jsStr), contains('临时疯狂'));
  });
}
