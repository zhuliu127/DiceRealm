// ============================================================
// test/p10_t7_layout_test.dart — P10 第 7 期 A「横屏布局重排 + 视觉」几何验收
//
// 覆盖用户本批 6 条诉求里可几何断言的部分：
//   ① 横屏网格重排：无空隙（相邻格间距 == 同一个 gap 8）、无横向裁切、
//      底部三块等高、10 格夹在顶栏~工具栏之间；
//   ⑤ 公开素材舞台严格 16:9（AspectRatio 节点实测 rect 比例）；
//   ② 栏位标题亮/暗两套都跟随主题（onSurface），与卡片底色对比足够；
//   ⑥ 骰子文案去前导 1 + D4~D20 收进「其他骰子」弹窗，点 D6 仍发 1D6；
//   ③ 顶栏「角色：…」「服务：…」已撤除（反向断言）；
//   ④ 素材管理只留一处：工具窄栏不再有「未公开素材」列表与隐藏/删除。
//
// ★ 全部用 tester.getRect 量真实 Rect；不用 findsOneWidget 冒充几何验证。
// ★ T1：全内存后端（RoomUiFixture），零真实 I/O；flutter test 必须带 NO_PROXY。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart' show RoomIntent, kHostSeat;
import 'package:dice_realm/theme.dart' show Palette, buildTheme;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart'
    show GpDiceBarKeys, kDiceExprs;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart'
    show GpKpLeft, GpKpLeftKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart' show GpKpToolsKeys;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart' show GpMapStageKeys;
import 'package:dice_realm/ui/room/widgets/gp_topbar.dart' show GpTopbarKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart'
    show RoomUiFixture, kFakePngDataUrl, useRoomScreen;

/// 两档真实平板横屏 dp（用户机型 GT2 Pro 与通用 1280×800）。
const List<List<double>> _screens = <List<double>>[
  <double>[1280, 800],
  <double>[1524, 1016],
];

/// 整页（真骨架）并跑到稳定帧。
Future<RoomUiFixture> _bootPage(
  WidgetTester tester, {
  required double w,
  required double h,
  String seat = kHostSeat,
}) async {
  final f = RoomUiFixture();
  await f.boot(inGame: true);
  f.pageBuilder = (String s, String r) => const RoomGamePage();
  useRoomScreen(tester, w, h);
  await tester.pumpWidget(f.pageOf(seat));
  await tester.pump();
  return f;
}

void main() {
  // ========================================================
  // T1 · 横屏网格：无空隙 / 无裁切 / 舞台严格 16:9
  // ========================================================
  group('T1 · KP dock 网格几何（1280 / 1524）', () {
    for (final s in _screens) {
      testWidgets('T1[${s[0].toInt()}×${s[1].toInt()}] 间距同源 / 底部等高 / '
          '舞台 16:9 / 零溢出', (WidgetTester tester) async {
        await _bootPage(tester, w: s[0], h: s[1]);
        final label = '${s[0].toInt()}×${s[1].toInt()}';
        const gap = 8.0;

        Rect r(RoomSlot slot) =>
            tester.getRect(find.byKey(RoomKeys.keyOfSlot(slot)));

        final kpLeft = r(RoomSlot.gpKpLeft);
        final tools = r(RoomSlot.gpKpTools);
        final map = r(RoomSlot.gpMap);
        final scene = r(RoomSlot.gpScene);
        final chat = r(RoomSlot.gpChat);
        final log = r(RoomSlot.gpLog);
        final priv = r(RoomSlot.gpPriv);
        final topbar = r(RoomSlot.gpTopbar);
        final toolbar = r(RoomSlot.gpToolbar);

        // ① 无空隙：所有相邻格间距 == 同一个 gap（列与行同源）。
        expect(tools.left - kpLeft.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 左栏→工具窄栏缝隙');
        expect(map.left - tools.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 工具窄栏→舞台缝隙');
        expect(scene.left - map.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 舞台→右列缝隙');
        expect(chat.top - map.bottom, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 行间距必须与列间距同源');
        expect(log.left - chat.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 聊天→记录缝隙');
        expect(priv.left - log.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 记录→只给你看缝隙');

        // ② 底部三块等高、同一行。
        expect(priv.top, moreOrLessEquals(chat.top, epsilon: 0.6),
            reason: '$label 底部三块必须并排');
        expect(priv.height, moreOrLessEquals(chat.height, epsilon: 0.6),
            reason: '$label 底部三块必须等高');
        expect(log.height, moreOrLessEquals(chat.height, epsilon: 0.6));

        // ③ 舞台严格 16:9（AspectRatio 节点实测比例，误差 ≤1dp 换算）。
        final stage = tester.getRect(find.byKey(GpMapStageKeys.stage));
        expect(stage.width / stage.height, closeTo(16 / 9, 0.02),
            reason: '$label 公开素材舞台不是严格 16:9'
                '（实测 ${stage.width.toStringAsFixed(1)}×'
                '${stage.height.toStringAsFixed(1)}）');

        // ④ 所有格子夹在「顶栏下沿 ~ 工具栏上沿」之间，右不越屏。
        final regionTop = topbar.bottom;
        final regionBottom = toolbar.top;
        for (final entry in <MapEntry<String, Rect>>[
          MapEntry<String, Rect>('gpKpLeft', kpLeft),
          MapEntry<String, Rect>('gpKpTools', tools),
          MapEntry<String, Rect>('gpMap', map),
          MapEntry<String, Rect>('gpScene', scene),
          MapEntry<String, Rect>('gpChat', chat),
          MapEntry<String, Rect>('gpPriv', priv),
        ]) {
          final Rect v = entry.value;
          expect(v.top, greaterThanOrEqualTo(regionTop - 0.6),
              reason: '$label ${entry.key} 越过顶栏下沿');
          expect(v.bottom, lessThanOrEqualTo(regionBottom + 0.6),
              reason: '$label ${entry.key} 越过工具栏上沿');
          expect(v.right, lessThanOrEqualTo(s[0] + 0.6),
              reason: '$label ${entry.key} 右越屏');
        }

        // ★ P16 KP-3 / KP-4②：状态条与右列战斗格都不再渲染（正向反证）。
        expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpStatus)), findsNothing,
            reason: '$label KP dock 不该再有待办状态条（KP-3 已删）');
        expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpCombat)), findsNothing,
            reason: '$label KP dock 不该再有右列战斗格（KP-4② 已搬进素材舞台）');

        // ⑤ 零异常：任何 RenderFlex overflow 都会在这里显形（本轮真修过一处）。
        expect(tester.takeException(), isNull, reason: '$label 有布局异常');
      });
    }
  });

  // ========================================================
  // T2 · 栏位标题跟随主题（亮 / 暗都可读）
  // ========================================================
  testWidgets('T2 亮暗两套：SectionBox 标题色 == colorScheme.onSurface 且对比足够',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    useRoomScreen(tester, 1280, 800);

    for (final b in Brightness.values) {
      Palette.useBrightness(b);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(b),
          home: Scaffold(
            body: f.scoped(kHostSeat, child: const GpKpLeft()),
          ),
        ),
      );
      await tester.pump();

      // ★ P13 MAP-1：标题按产品真变由「地图 / NPC / 素材」改为「NPC / 素材」；
      //   下面的颜色 / 对比度核心断言逐字不动。
      final title = tester.widget<Text>(find.text('NPC / 素材'));
      final expected = buildTheme(b).colorScheme.onSurface;
      expect(title.style!.color, expected,
          reason: '$b 栏位标题必须取 onSurface（亮色下不能是白字）');
      // 与卡片底色的亮度差足够（≥0.45 近似 4.5:1 的可读档）。
      final cardLum = buildTheme(b).cardColor.computeLuminance();
      final titleLum = title.style!.color!.computeLuminance();
      expect((cardLum - titleLum).abs(), greaterThan(0.45),
          reason: '$b 标题与卡片底色对比不足');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  // ========================================================
  // T3 · 骰子：文案去 1 + D4~D20 收进「其他骰子」弹窗
  // ========================================================
  testWidgets('T3 工具栏只留 D100 + 其他骰子；弹窗 6 个；点 D6 发 1D6',
      (WidgetTester tester) async {
    final f = await _bootPage(tester, w: 1280, h: 800);

    // ① 工具栏：D4/D6/D8/D10/D12/D20 都不在。
    for (final e in kDiceExprs) {
      if (e == kDiceExprs.first) continue;
      expect(find.byKey(GpDiceBarKeys.expr(e)), findsNothing,
          reason: '工具栏不该再直接放 $e（已收进其他骰子）');
    }
    expect(find.byKey(GpDiceBarKeys.expr(kDiceExprs.first)), findsOneWidget);
    // 显示文案去掉前导 1：D100（内部表达式仍是 1D100，见下方 ③）。
    expect(find.text('D100'), findsWidgets);
    expect(find.text('1D100'), findsNothing,
        reason: '工具栏必须显示 D100，不能仍显示 1D100');
    expect(find.byKey(GpDiceBarKeys.otherDice), findsOneWidget);

    // ② 点「其他骰子」→ 弹窗里 6 个骰式都在。
    await tester.tap(find.byKey(GpDiceBarKeys.otherDice));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    for (final e in kDiceExprs) {
      if (e == kDiceExprs.first) continue;
      expect(find.byKey(GpDiceBarKeys.expr(e)), findsOneWidget,
          reason: '弹窗里必须有 $e');
    }

    // ③ 点 D6 → 表达式仍是内部值 1D6（规则层一字不动）。
    f.clearSent();
    await tester.tap(find.byKey(GpDiceBarKeys.expr('1D6')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final sent = f.lastSent(op: RoomIntent.dice);
    expect(sent, isNotNull, reason: '点 D6 必须真的发出 INTENT.DICE');
    expect(asMap(sent!['p'])['expr'], '1D6',
        reason: '载荷表达式必须仍是 1D6（显示文案去 1 不影响内部值）');
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // T4 · 顶栏去重：角色 / 服务 两项已撤除（反向断言）
  // ========================================================
  testWidgets('T4 顶栏不再有「角色：…」「服务：…」两个重复胶囊',
      (WidgetTester tester) async {
    await _bootPage(tester, w: 1280, h: 800);
    expect(find.byKey(GpTopbarKeys.role), findsNothing,
        reason: '身份行 whoLine 已含角色，独立「角色：…」必须撤除');
    expect(find.byKey(GpTopbarKeys.service), findsNothing,
        reason: '用户明确要求删掉「服务：本机进程内（未联网）」');
    // 身份行仍在（语义未丢）。
    expect(find.byKey(GpTopbarKeys.who), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // T5 · 素材管理只留一处：工具窄栏不再重复列表
  // ========================================================
  testWidgets('T5 工具窄栏不再有「未公开素材」列表；上传入口仍在',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    f.host.localAssets.add(<String, Object?>{
      'id': 'seedAsset',
      'kind': 'map',
      'name': '旧地图',
      'data': '',
      'revealed': false,
      'at': 1,
    });
    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: f.scoped(kHostSeat, child: const GpKpLeft()),
        ),
      ),
    );
    await tester.pump();

    // 左窄栏素材 tab：隐藏 / 封面 / 删除 都在（功能可达）。
    f.localOf(kHostSeat).setTab('left', 2);
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('gpKpLeft/upload')), findsOneWidget);
    expect(find.text('旧地图'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ★ 正向补齐（用例名承诺的那一半）：整页里工具窄栏**不再**重复素材管理，
    //   只保留「上传素材」这一个入口；旧文案「未公开素材」必须消失。
    f.pageBuilder = (String s, String r) => const RoomGamePage();
    await tester.pumpWidget(f.pageOf(kHostSeat));
    await tester.pump();
    final toolsSlot = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpTools));
    // ★ P16 KP-10：上传入口整块搬进左窄栏素材 tab，工具窄栏不再渲染它。
    expect(
      find.descendant(
        of: toolsSlot,
        matching: find.byKey(GpKpToolsKeys.upload),
      ),
      findsNothing,
      reason: 'P16 KP-10：工具窄栏不再有「上传素材」按钮',
    );
    // 正向：上传入口在左窄栏仍在（功能没有丢，只是唯一化了）。
    expect(
      find.descendant(
        of: find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)),
        matching: find.byKey(GpKpLeftKeys.upload),
      ),
      findsOneWidget,
      reason: '左窄栏素材 tab 必须保留唯一的上传入口',
    );
    expect(find.text('未公开素材'), findsNothing,
        reason: '素材管理只留左窄栏一处，工具窄栏不许再列一遍');
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // T6 · 公开素材**真的**画进舞台（不是只留 Image 组件壳）
  // ========================================================
  // 真因（本批修复）：舞台 Stack 里「底图」画在最下层，而紧邻其上的
  // `Container(color: surfaceContainerHighest)` 是不透明铺满 —— 会把底图
  // 整块盖住，肉眼看到的就是「素材图根本没渲染」。修法：有底图时该层透明。
  testWidgets('T6 公开素材渲染：Image.memory 拿到真字节 + 上层容器不再遮盖',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    await f.controllerOf(kHostSeat).hostAction('asset.add', <String, Object?>{
      'asset': <String, Object?>{
        'kind': 'map',
        'name': '底图',
        'data': kFakePngDataUrl,
      },
    });
    final String assetId = '${f.host.localAssets.last['id']}';
    await f.controllerOf(kHostSeat).hostAction('asset.reveal', <String, Object?>{
      'id': assetId,
      'revealed': true,
    });

    f.pageBuilder = (String s, String r) => const RoomGamePage();
    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(f.pageOf(kHostSeat));
    await tester.pump();

    final mapSlot = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap));
    final img = find.descendant(of: mapSlot, matching: find.byType(Image));
    expect(img, findsOneWidget, reason: '舞台里必须有一张素材底图');
    final widget = tester.widget<Image>(img);
    final provider = widget.image;
    expect(provider, isA<MemoryImage>(),
        reason: '底图应来自 dataURL 解出的字节（MemoryImage）');
    expect((provider as MemoryImage).bytes.isNotEmpty, isTrue,
        reason: '底图字节为空 ⇒ 只是组件壳，等于没渲染');
    expect(widget.fit, BoxFit.contain, reason: '不改形不裁切');

    // 关键回归点：盖在底图上的那层 Container 不能再是不透明底色。
    // （Container 是 canvas 手势层的**子节点**，它铺满整个舞台。）
    final coverBox = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(GpMapStageKeys.canvas),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = coverBox.decoration as BoxDecoration;
    expect(deco.color == null || deco.color == Colors.transparent ||
        deco.color!.a == 0, isTrue,
        reason: '有底图时上层容器必须透明，否则会把素材整块盖住（本批真 bug）');
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // T7 · 公开后素材列表不重复（同一 id 只一行）
  // ========================================================
  // 真因：已公开素材同时存在于 scene.assets（广播副本）与 host.localAssets
  // （私有原件，reveal 只改标记不删），原实现 `[...public, ...localAssets]`
  // 直接拼接 → 用户看到的「公开后素材栏多了一个」。
  testWidgets('T7 公开后左栏素材列表按 id 去重（一行、计数正确）',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    await f.controllerOf(kHostSeat).hostAction('asset.add', <String, Object?>{
      'asset': <String, Object?>{
        'kind': 'map',
        'name': '重复素材',
        'data': kFakePngDataUrl,
      },
    });
    final String id = '${f.host.localAssets.last['id']}';
    await f.controllerOf(kHostSeat).hostAction('asset.reveal', <String, Object?>{
      'id': id,
      'revealed': true,
    });

    // 前置：两份数据里确实都有这条（否则去重断言没意义）。
    expect(f.host.localAssets.where((a) => a['id'] == id).length, 1,
        reason: '私有库仍保留原件（reveal 只改标记）');
    expect(f.sessionOf(kHostSeat).state, isNotNull);

    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: f.scoped(kHostSeat, child: const GpKpLeft()),
        ),
      ),
    );
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 2);
    await tester.pump();

    expect(find.text('重复素材'), findsOneWidget,
        reason: '同一 id 的素材只能出现一行（旧实现会出现两行）');
    final count = tester.widget<Text>(
        find.byKey(const ValueKey<String>('gpKpLeft/assetCount')));
    expect(count.data, '公开 1 · 未公开 0',
        reason: '计数必须按去重后的行算，且公开/未公开不重叠');
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // T8 · 左窄栏「素材行」按钮完整落在格内 + 48 热区不减
  // ========================================================
  // 用户截图原话：素材那一行「隐藏 / 封面 / 删除」右半边被裁掉。
  // 真因：左窄栏 17%（1280dp 实测 213dp）放不下「名字 + 3 个按钮」一行。
  // 本批改成「名字一行 + 按钮 Wrap」，这里用真实 Rect 钉死：
  // 每个按钮都必须完整落在 gpKpLeft 格内，且各自 ≥48×48。
  // ★ P16 KP-2：「封面」按钮已删除，故只剩 公开/隐藏 + 删除 两个；
  //   顺带断言「封面」这个文案在本栏确实不存在（旧按钮没有残留壳）。
  testWidgets('T8 1280 档：左栏素材行按钮不出格、热区 ≥48×48',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    f.host.localAssets.add(<String, Object?>{
      'id': 't8asset',
      'kind': 'map',
      'name': '测试底图',
      'data': '',
      'revealed': false,
      'at': 1,
    });
    f.pageBuilder = (String s, String r) => const RoomGamePage();
    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(f.pageOf(kHostSeat));
    await tester.pump();

    f.localOf(kHostSeat).setTab('left', 2);
    await tester.pump();

    final cell = tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)));
    for (final key in <Key>[
      GpKpLeftKeys.reveal('t8asset'),
      GpKpLeftKeys.delete('t8asset'),
    ]) {
      final r = tester.getRect(find.byKey(key));
      expect(r.left, greaterThanOrEqualTo(cell.left - 0.5),
          reason: '$key 左越出左窄栏');
      expect(r.right, lessThanOrEqualTo(cell.right + 0.5),
          reason: '$key 右越出左窄栏（用户截图「右半边被裁」）');
      expect(r.width, greaterThanOrEqualTo(48 - 0.5),
          reason: '$key 热区宽度被压到 48 以下');
      expect(r.height, greaterThanOrEqualTo(48 - 0.5),
          reason: '$key 热区高度被压到 48 以下');
    }
    // ★ P16 KP-2 正向反证：封面按钮已删（key 与文案都不得残留）。
    expect(find.byKey(GpKpLeftKeys.cover('t8asset')), findsNothing,
        reason: 'P16 KP-2：素材行不再有「封面」按钮');
    expect(find.text('封面'), findsNothing,
        reason: '素材行不再出现「封面」文案');
    // 两个按钮仍各占 48 宽，且同行或换行都在左栏内 —— 补一条几何关系断言。
    final revealRect =
        tester.getRect(find.byKey(GpKpLeftKeys.reveal('t8asset')));
    final deleteRect =
        tester.getRect(find.byKey(GpKpLeftKeys.delete('t8asset')));
    expect((revealRect.center.dy - deleteRect.center.dy).abs(),
        lessThanOrEqualTo(1.0),
        reason: '公开 / 删除 应并排在同一行（Wrap 未异常换行）');
    expect(deleteRect.left, greaterThan(revealRect.right),
        reason: '删除应在公开右侧');
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // T9 · P16 KP-2：公开互斥（舞台上永远只有最后公开的那一张）
  // ========================================================
  testWidgets('T9 公开 A 再公开 B：A 自动取消公开、舞台只留 B',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    final ctl = f.controllerOf(kHostSeat);

    Future<String> add(String name) async {
      await ctl.hostAction('asset.add', <String, Object?>{
        'asset': <String, Object?>{
          'kind': 'map',
          'name': name,
          'data': kFakePngDataUrl,
        },
      });
      return '${f.host.localAssets.last['id']}';
    }

    final String idA = await add('图A');
    final String idB = await add('图B');
    await ctl.hostAction('asset.reveal', <String, Object?>{
      'id': idA,
      'revealed': true,
    });

    f.pageBuilder = (String s, String r) => const RoomGamePage();
    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(f.pageOf(kHostSeat));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 2);
    await tester.pump();

    String revealLabel(String id) =>
        tester.widget<RoomTap>(find.byKey(GpKpLeftKeys.reveal(id))).label;
    expect(revealLabel(idA), '隐藏', reason: 'A 已公开 → 按钮变成「隐藏」');
    expect(revealLabel(idB), '公开');

    // 公开 B → A 必须被自动取消公开（KP-2 互斥）。
    await ctl.hostAction('asset.reveal', <String, Object?>{
      'id': idB,
      'revealed': true,
    });
    await tester.pump();

    // ① KP 侧列表：只有 B 的 revealed 为 true。
    final revealed = f.host.localAssets
        .where((Map<String, Object?> a) => a['revealed'] == true)
        .toList();
    expect(revealed.length, 1, reason: '同时只能有一张素材公开');
    expect('${revealed.single['id']}', idB);

    // ② 左栏两行按钮文案同步：A 回到「公开」，B 是「隐藏」。
    expect(revealLabel(idA), '公开', reason: 'A 被互斥隐藏后按钮必须变回「公开」');
    expect(revealLabel(idB), '隐藏');

    // ③ 广播出去的公开列只剩 B。
    final assets = asList(asMap(f.hostState()['scene'])['assets']);
    expect(assets.length, 1, reason: 'scene.assets 只保留最后公开的一张');
    expect('${asMap(assets.single)['id']}', idB);

    // ④ 舞台上只画一张图（不是 A、B 叠在一起）。
    final mapSlot = find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpMap));
    expect(find.descendant(of: mapSlot, matching: find.byType(Image)),
        findsOneWidget,
        reason: '舞台上只该有最后公开的那一张');

    // ⑤ 计数文案：公开 1 · 未公开 1（互斥后仍是一张公开）。
    final count = tester
        .widget<Text>(find.byKey(const ValueKey<String>('gpKpLeft/assetCount')));
    expect(count.data, '公开 1 · 未公开 1');
    expect(tester.takeException(), isNull);
  });
}
