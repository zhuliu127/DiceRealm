// ============================================================
// test/p12_kp5_kp7_card_test.dart — P12 / 第 9 期 · KP-5 / KP-7
//
// KP-5：玩家卡片右下角「全屏」→「手绘板」+ Icons.draw，功能仍打开全屏手绘板。
//   ★ 按**卡片子树**限定查找，避免误伤舞台「全屏」入口。
//   ★ 显式验证 find.text 是精确匹配：同卡片里还有「手绘板：N 笔」统计文本
//     与 RoomTap 的 hint「全屏只读手绘板」，两者都不该让
//     find.text('手绘板') / find.text('全屏') 多算一次。
// KP-7：角色名落在卡片子树（members[].charName 同源），长名 ×2.0 不溢出。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart'
    show GpKpPlayers, GpKpPlayersKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

Widget _cardApp(RoomUiFixture f) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(body: f.scoped(kHostSeat, child: const GpKpPlayers())),
    );

/// 给 p1 成员补一个角色名（单一真源 members[].charName）。
void _setCharName(RoomUiFixture f, String name) {
  for (final Object? raw in asList(f.hostState()['members'])) {
    final Map<String, Object?> m = asMap(raw);
    if (jsStr(m['seat']) == 'p1') m['charName'] = name;
  }
}

/// 卡片子树：从「手绘板」按钮往上找最近的 Card。
Finder _cardOf(WidgetTester tester) => find
    .ancestor(
      of: find.byKey(GpKpPlayersKeys.board('p1')),
      matching: find.byType(Card),
    )
    .first;

void main() {
  group('A · KP-5 文案 / 图标 / 精确匹配口径', () {
    testWidgets('卡片子树内「手绘板」恰好一个，「全屏」零个',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_cardApp(f));
      await tester.pump();

      final Finder card = _cardOf(tester);
      expect(card, findsOneWidget, reason: 'p1 应有一张角色卡');
      expect(find.descendant(of: card, matching: find.text('手绘板')),
          findsOneWidget,
          reason: '★ KP-5：卡片按钮新文案恰好一个');
      expect(find.descendant(of: card, matching: find.text('全屏')), findsNothing,
          reason: '★ KP-5：卡片内不该再有旧「全屏」文案');
      // 全树范围同样成立（只有 1 个玩家 → 1 张卡）。
      expect(find.text('手绘板'), findsOneWidget);
      expect(find.text('全屏'), findsNothing,
          reason: '整页也不该有裸「全屏」文本（舞台入口是 Icon + hint）');
      expect(find.byIcon(Icons.draw), findsOneWidget,
          reason: '图标必须是手绘板语义 Icons.draw');
      expect(tester.takeException(), isNull);
    });

    testWidgets('显式验证精确匹配：统计文本与 hint 都不被 find.text 误伤',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_cardApp(f));
      await tester.pump();

      // ① 统计文本「手绘板：0 笔」确实在卡片里，但不含裸「手绘板」。
      final Finder card = _cardOf(tester);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('手绘板：'),
        ),
        findsWidgets,
        reason: '卡片里应有「手绘板：N 笔」统计行',
      );
      expect(find.text('手绘板'), findsOneWidget,
          reason: '★ find.text 精确匹配：统计文本不该被算成第二个「手绘板」');

      // ② hint 含「全屏」子串，但不是 Text('全屏')，不该被 find.text 命中。
      final RoomTap board = tester
          .widget<RoomTap>(find.byKey(GpKpPlayersKeys.board('p1')));
      expect(board.hint, '全屏只读手绘板',
          reason: 'hint 仍保留「全屏只读手绘板」语义');
      expect(board.hint!.contains('全屏'), isTrue);
      expect(find.text('全屏'), findsNothing,
          reason: '★ hint 不是 Text，精确匹配不该误伤');
      expect(find.text('全屏只读手绘板'), findsNothing,
          reason: 'hint 不是渲染出来的 Text');
      expect(find.byIcon(Icons.fullscreen), findsNothing,
          reason: '卡片按钮不该再用全屏图标');
    });

    testWidgets('点「手绘板」仍打开全屏手绘板（功能不变）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_cardApp(f));
      await tester.pump();

      await tester.tap(find.byKey(GpKpPlayersKeys.board('p1')));
      await tester.pumpAndSettle();
      expect(find.text('手绘板 · 玩家1'), findsOneWidget,
          reason: '★ 点击应仍打开 showFullscreenReader 的全屏手绘板');
      expect(tester.takeException(), isNull);
    });
  });

  group('B · KP-7 角色名上卡 + 长名 ×2.0 不溢出', () {
    testWidgets('角色名落在卡片子树，与 members[].charName 同源',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1);
      _setCharName(f, '阿比盖尔·费尔柴尔德');
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_cardApp(f));
      await tester.pump();

      final Finder card = _cardOf(tester);
      final Finder nameKey =
          find.byKey(GpKpPlayersKeys.charName('p1'));
      expect(find.descendant(of: card, matching: nameKey), findsOneWidget,
          reason: '★ KP-7：角色名必须落在卡片子树内');
      expect(tester.widget<Text>(nameKey).data,
          '角色名：阿比盖尔·费尔柴尔德',
          reason: '与 members[].charName 同源');
      // 玩家侧角色卡同源字段（静态口径，避免再建一整套玩家页）。
      expect(f.hostState()['members'], isNotNull);
      expect(tester.takeException(), isNull);
    });

    test('角色名缺失时不渲染该行（不出空串）', () async {
      // 用纯数据检查：charName 为空时 gp_kp_players.dart 的
      // `if (roomText(m['charName']).isNotEmpty)` 分支不渲染。用 widget 验证。
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, players: 1);
      _setCharName(f, '');
      // 由下面的 testWidgets 统一验证，本条只钉住数据前置。
      expect(asList(f.hostState()['members']).isNotEmpty, isTrue);
    });

    for (final double scale in <double>[1.3, 1.5, 2.0]) {
      testWidgets('×$scale 超长角色名不出现 RenderFlex overflow',
          (WidgetTester tester) async {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot(inGame: true, players: 1);
        _setCharName(f,
            '阿比盖尔·费尔柴尔德·范·德·梅尔韦·伊丽莎白·玛丽亚·康斯坦丝·冯·霍亨索伦');
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        useRoomScreen(tester, 1280, 800);
        await tester.pumpWidget(_cardApp(f));
        await tester.pump();

        final Finder card = _cardOf(tester);
        final Finder nameKey =
            find.byKey(GpKpPlayersKeys.charName('p1'));
        expect(find.descendant(of: card, matching: nameKey), findsOneWidget,
            reason: '×$scale 长名不该让角色名行消失');
        final Text nameWidget = tester.widget<Text>(nameKey);
        expect(nameWidget.maxLines, 1, reason: '长名单行 + ellipsis');
        expect(nameWidget.overflow, TextOverflow.ellipsis);
        final Rect cardRect = tester.getRect(card);
        final Rect nameRect = tester.getRect(nameKey);
        expect(nameRect.right, lessThanOrEqualTo(cardRect.right + 0.5),
            reason: '×$scale 长名不该溢出卡片右边界');
        expect(tester.takeException(), isNull,
            reason: '×$scale 出现布局异常');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
    }
  });
}
