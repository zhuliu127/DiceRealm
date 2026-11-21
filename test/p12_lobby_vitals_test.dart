// ============================================================
// test/p12_lobby_vitals_test.dart — 招募大厅成员行不画「假 0 卡」
//
// 真机联调（双模拟器 A=KP / B=玩家，2026-11-11 v2.22.0）发现的 bug：
//   B 加入后，两端「成员（1）」那一行都显示 `HP 0 / 0 · SAN 0`，
//   而那个成员其实**一丁点卡数据都没有**。
//
// 根因与第 7 期「我的角色卡显示成横线」同源：memberStats 三源回退
// 取不到就静默给 0，把「未初始化」伪装成「真的是 0」。第 7 期修了
// 角色卡面板与玩家栏，**招募大厅成员行 + 成员详情弹层两处漏了**。
//
// 本文件钉死：
//   1. 没绑卡 → 显示「未绑卡」，绝不再出现 HP 0 / 0；
//   2. 绑了卡 → 显示真实数值；
//   3. 真的 0（status 键在、值为 0）仍是合法卡，不能被一起藏掉。
//
// 反向自证伪：把 room_lobby_page.dart 两处 hasCardVitals 判断去掉
//   → 用例 1 必红；把 hasCardVitals 改成恒 false → 用例 2 必红。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/view/member_view.dart' show hasCardVitals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

Widget _app(RoomUiFixture f) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(kHostSeat, child: const RoomLobbyPage()),
    );

Future<void> _pumpLobby(WidgetTester tester, RoomUiFixture f) async {
  useRoomScreen(tester, 900, 2400);
  await tester.pumpWidget(_app(f));
  await tester.pump();
}

void main() {
  testWidgets('没绑卡的成员：显示「未绑卡」，不再画 HP 0 / 0',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(); // KP + p1 + p2 + sp1，默认都没有卡
    await _pumpLobby(tester, f);

    expect(find.text('HP 0 / 0 · SAN 0'), findsNothing,
        reason: '未初始化的成员不该被画成一整张 0 的假卡');
    expect(find.textContaining('HP 0 / 0'), findsNothing);
    expect(find.text('未绑卡'), findsWidgets,
        reason: '要如实说明「没卡」，而不是给一串假数字');
  });

  testWidgets('绑了卡：显示真实数值，且不再出现「未绑卡」',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    await f.shareSheets(); // status: currentHP=12 / maxHP=12 / currentSAN=56...
    await _pumpLobby(tester, f);

    expect(find.textContaining('HP 12 / 12'), findsWidgets,
        reason: '有卡就该照实显示数值');
    // 精确钉 p1 那一行：它已经绑卡，绝不能再出现「未绑卡」。
    final Finder p1Row = find.byKey(RoomLobbyKeys.memberRow('p1'));
    expect(p1Row, findsOneWidget);
    expect(find.descendant(of: p1Row, matching: find.text('未绑卡')),
        findsNothing,
        reason: 'p1 已绑卡，不该再说没卡');
    // 旁观者 sp1 本来就不该有卡，它显示「未绑卡」是正确的，别误伤。
    expect(find.text('未绑卡'), findsOneWidget,
        reason: '只剩旁观者没卡');
  });

  test('hasCardVitals：status 里真的是 0 也算「有卡」', () {
    // 三处全空 = 未初始化
    expect(hasCardVitals(<String, Object?>{}), isFalse);
    expect(hasCardVitals(<String, Object?>{'sheet': null}), isFalse);

    // 键在、值为 0 = 合法卡（清空房卡数值后的形状），真 0 不能被吃掉
    expect(
      hasCardVitals(<String, Object?>{
        'sheet': <String, Object?>{
          'status': <String, Object?>{
            'currentHP': 0,
            'maxHP': 0,
            'currentSAN': 0,
          },
        },
      }),
      isTrue,
    );
  });
}
