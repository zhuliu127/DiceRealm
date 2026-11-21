// ============================================================
// test/p10_t6_layout_test.dart — P10 第 6 期「布局专项」几何验收
//
// 用户口述（本批授权改布局）：
//   ① 手机竖屏「最上方的标题很乱，而且文字没有匹配 ui」+「可以摆在一行，
//      但是占了 3 行，压缩了下方栏位的空间」→ 顶栏压成 1 行（宽档）/ 2 行（窄档）。
//   ② 手机竖屏「下方玩家工具栏按钮也很乱」→ 骰子条密集分组，战技不再单独一行。
//   ③ KP 平板横屏「布局和参考图差异还很大，很多栏位里面的内容都没显示
//      完全」「下方两大块空块」→ 按红块图重排 flex + 消除横向裁切。
//
// ★ 本文件全部用 tester.getRect 量**真实 Rect**（行数按 centerY 分组、
//   缝隙按相邻 rect 差值、裁切按子树内横向滚动容器 + 按钮 rect 边界），
//   不用 findsOneWidget 冒充几何验证。
// ★ 真实机型 dp：荣耀 Magic9 竖屏 412×915、荣耀平板 GT2 Pro 横屏
//   1524×1016、通用平板横屏 1280×800。
// ★ T1：全内存后端（RoomUiFixture），零真实 I/O；零 Timer / Future.delayed。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/theme.dart' show Palette, buildTheme;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/view/room_view.dart'
    show RoomGridSpec, RoomLayoutMode;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart'
    show GpDiceBarKeys, diceBalancedRowSizes, kDiceExprs;
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart'
    show GpKpPlayersKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart'
    show GpKpToolsKeys;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_kp.dart'
    show GpSceneCheckKeys;
import 'package:dice_realm/ui/room/widgets/gp_topbar.dart'
    show GpTopbar, GpTopbarKeys;
import 'package:dice_realm/ui/room/widgets/room_layout.dart'
    show roomDockMinWidthOf, roomDockPlanOf, roomLayoutFlexPathsOf,
        roomLayoutSlotsOf;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 三档真实机型（dp）。
const List<List<double>> _screens = <List<double>>[
  <double>[412, 915], // 荣耀 Magic9 竖屏 → folded
  <double>[1280, 800], // 平板横屏 → dock
  <double>[1524, 1016], // 荣耀平板 GT2 Pro 横屏 → dock
];

/// 顶栏单独泵一层壳（可精确切亮暗皮肤，不受夹具 ThemeData.dark 限制）。
Widget _topbarApp(
  RoomUiFixture f,
  Brightness brightness, {
  double? width,
}) {
  return MaterialApp(
    theme: buildTheme(brightness),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width ?? double.infinity,
          child: f.scoped(
            kHostSeat,
            child: GpTopbar(
              serviceBase: 'ws://127.0.0.1:9001',
              onSpectatorsTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

/// 整页（RoomGamePage 真骨架）。
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

/// 按垂直中心分组数「行数」：同一行里的控件垂直居中，centerY 相等。
/// 比 top 相等更准（各胶囊字号不同、高度不同，top 本来就不齐）。
int _rowCount(Iterable<Rect> rects, {double epsilon = 1.0}) {
  final centers = <double>[];
  for (final r in rects) {
    final cy = r.center.dy;
    if (centers.every((double c) => (c - cy).abs() > epsilon)) {
      centers.add(cy);
    }
  }
  return centers.length;
}

/// 顶栏所有信息 key（service 仅 KP；scene 依 state 可缺省，故单列）。
List<Key> _topbarKeys() => <Key>[
      GpTopbarKeys.roomName,
      GpTopbarKeys.roomCode,
      GpTopbarKeys.link,
      GpTopbarKeys.who,
      // ★ P10 第 7 期：role / service 两个胶囊已按用户要求撤除渲染，
      //   这里不能再用 getRect 找它们（会抛 null）。行数断言只看仍在的 key。
      GpTopbarKeys.mode,
      GpTopbarKeys.round,
      GpTopbarKeys.spectators,
    ];

List<Rect> _rectsOf(WidgetTester tester, List<Key> keys) => <Rect>[
      for (final k in keys) tester.getRect(find.byKey(k)),
    ];

/// 每个 KP 槽位子树里是否出现了「横向滚动」——出现即 `_slotView` 判了
/// tooNarrow，ClipRect 会把右侧内容裁掉一半（用户真机截图的病根）。
bool _hasHorizontalScroll(WidgetTester tester, Key slotKey) {
  return find
      .descendant(
        of: find.byKey(slotKey),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  // Palette 是全局静态皮肤，用例之间必须复位，避免把后续用例带成亮色。
  setUp(() => Palette.useBrightness(Brightness.dark));
  tearDown(() => Palette.useBrightness(Brightness.dark));

  // ========================================================
  // A · 顶栏：压成一行 + 文字与头图匹配（亮暗两套）
  // ========================================================
  group('A · 顶栏行数与高度（getRect 实测）', () {
    testWidgets('A1 宽档 1524 / 1280：全部信息同一行，顶栏高度 ≤ 64dp',
        (WidgetTester tester) async {
      for (final s in <List<double>>[
        <double>[1524, 1016],
        <double>[1280, 800],
      ]) {
        final f = RoomUiFixture();
        await f.boot(inGame: true);
        useRoomScreen(tester, s[0], s[1]);
        await tester.pumpWidget(_topbarApp(f, Brightness.dark));
        await tester.pump();

        final bar = tester.getRect(find.byType(GpTopbar));
        final rects = _rectsOf(tester, _topbarKeys());
        final label = '${s[0].toInt()}×${s[1].toInt()}';

        expect(_rowCount(rects), 1,
            reason: '$label 顶栏应压成 1 行，实测 centerY=${<double>[
                  for (final r in rects) r.center.dy
                ]}');
        expect(bar.height, lessThanOrEqualTo(64),
            reason: '$label 顶栏实测高 ${bar.height.toStringAsFixed(1)}dp');
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].top, greaterThanOrEqualTo(bar.top - 0.5),
              reason: '$label 第 $i 项被顶栏上沿裁掉');
          expect(rects[i].bottom, lessThanOrEqualTo(bar.bottom + 0.5),
              reason: '$label 第 $i 项被顶栏下沿裁掉');
        }
        expect(tester.takeException(), isNull, reason: '$label 有布局异常');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('A2 窄档 412：恰好 2 行，不再有第三行（旧版 3 行）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 412, 915);
      await tester.pumpWidget(_topbarApp(f, Brightness.dark));
      await tester.pump();

      final bar = tester.getRect(find.byType(GpTopbar));
      final rects = _rectsOf(tester, _topbarKeys());
      expect(_rowCount(rects), 2,
          reason: '412dp 应压成 2 行，实测 centerY=${<double>[
                for (final r in rects) r.center.dy
              ]}');
      expect(bar.height, lessThanOrEqualTo(96),
          reason: '实测高 ${bar.height.toStringAsFixed(1)}dp');
      // 观众数入口热区不小于既有口径 56×32
      final spec = tester.getRect(find.byKey(GpTopbarKeys.spectators));
      expect(spec.width, greaterThanOrEqualTo(56));
      expect(spec.height, greaterThanOrEqualTo(32));
      expect(tester.takeException(), isNull);
    });

    testWidgets('A3 分档阈值：900dp 以下两行、以上一行（几何反证）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      for (final w in <double>[600, 899, 912, 1100]) {
        useRoomScreen(tester, w, 900);
        await tester.pumpWidget(_topbarApp(f, Brightness.dark));
        await tester.pump();
        final rows = _rowCount(_rectsOf(tester, _topbarKeys()));
        // LayoutBuilder 在 Padding(horizontal: 6) 之内，可用宽 = w - 12。
        final available = w - 12;
        expect(rows, available < GpTopbar.oneLineMinWidth ? 2 : 1,
            reason: '宽度 $w（可用 $available）行数判错');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('A4 亮暗两套：底衬 / 文字对比 / 描边感 / 头图 opacity 实测',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1524, 1016);

      final luminance = <Brightness, double>{};
      final scrim = <Brightness, Color>{};
      final opacities = <Brightness, double>{};

      for (final b in Brightness.values) {
        Palette.useBrightness(b);
        await tester.pumpWidget(_topbarApp(f, b));
        await tester.pump();

        // ① 一行且零异常（亮色皮肤也不能挤出第二行）
        expect(_rowCount(_rectsOf(tester, _topbarKeys())), 1,
            reason: '$b 顶栏不该换行');
        expect(tester.takeException(), isNull, reason: '$b 有布局异常');

        // ② 整条底衬：读最外层 DecoratedBox 的 color + 头图 opacity
        final deco = tester.widget<DecoratedBox>(find
            .descendant(
              of: find.byType(GpTopbar),
              matching: find.byType(DecoratedBox),
            )
            .first);
        final box = deco.decoration as BoxDecoration;
        expect(box.color, isNotNull, reason: '$b 缺半透明底衬');
        expect(box.color!.a, greaterThanOrEqualTo(0.7),
            reason: '$b 底衬太透，压不住头图纹样');
        expect(box.image, isNotNull, reason: '$b 头图必须还在（不是删图）');
        scrim[b] = box.color!;
        opacities[b] = box.image!.opacity;
        expect(opacities[b]!, lessThan(0.34),
            reason: '$b 头图纹样过强，文字会糊在装饰上');

        // ③ 文字：高对比 + 描边阴影；胶囊底衬与不占尺寸的前景描边
        final text = tester.widget<Text>(find.byKey(GpTopbarKeys.roomName));
        expect(text.style!.color, isNotNull);
        expect(text.style!.shadows, isNotNull);
        expect(text.style!.shadows, isNotEmpty,
            reason: '$b 文字缺描边感（shadows）');
        luminance[b] = text.style!.color!.computeLuminance();

        final chip = tester.widget<Container>(find
            .ancestor(
              of: find.byKey(GpTopbarKeys.roomName),
              matching: find.byType(Container),
            )
            .first);
        expect((chip.decoration as BoxDecoration).color, isNotNull,
            reason: '$b 房间名缺胶囊底衬');
        expect(chip.foregroundDecoration, isA<BoxDecoration>(),
            reason: '$b 胶囊描边必须走 foregroundDecoration（不占尺寸）');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      // 两套皮肤的取色必须真的不同，且各自「文字 vs 底衬」对比够大
      expect(scrim[Brightness.dark], isNot(scrim[Brightness.light]));
      expect(luminance[Brightness.dark]!,
          greaterThan(luminance[Brightness.light]!),
          reason: '暗色皮肤文字应更亮');
      for (final b in Brightness.values) {
        final base = scrim[b]!.computeLuminance();
        expect((luminance[b]! - base).abs(), greaterThan(0.25),
            reason: '$b 文字与底衬对比不足');
      }
    });
  });

  // ========================================================
  // B · 手机竖屏工具栏：密集分组 + 战技不单独一行
  // ========================================================
  group('B · 412dp 工具栏几何', () {
    testWidgets('B1 骰子条整齐无孤行：每行 ≥2 个按钮，战技不再单独一行',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 412, h: 915, seat: 'p1');

      final keys = <Key>[
        GpDiceBarKeys.bonus,
        GpDiceBarKeys.penalty,
        // ★ P17 C-3：奖惩骰改三段式复合控件 `[−][奖励N(+1)][↺]`，
        //   新增 4 个子键（状态层零改动、夹取仍单点）—— 采样必须全覆盖，
        //   否则行宽变化会让「每行 ≥2」的断言采样不全。
        GpDiceBarKeys.bonusMinus,
        GpDiceBarKeys.bonusReset,
        GpDiceBarKeys.penaltyMinus,
        GpDiceBarKeys.penaltyReset,
        // ★ P10 第 7 期：工具栏只留 D100，其余骰式收进「其他骰子」弹窗
        //   （弹窗内仍用同一个 expr key，见 p10_t7 的收纳用例）。
        GpDiceBarKeys.expr(kDiceExprs.first),
        GpDiceBarKeys.otherDice,
        GpDiceBarKeys.customExpr,
        GpDiceBarKeys.rollCustom,
        GpDiceBarKeys.dark,
        RoomKeys.action('combat.roll'),
      ];
      final rects = _rectsOf(tester, keys);
      // ★ P16 注释更新（**仅注释，断言一字未改**）：骰子条现在是 **9 项**
      //   （8 个按钮 + 1 个自定义表达式输入框；D4–D20 在 P10 第 7 期已收进
      //   「其他骰子」弹窗），统一后按钮宽一律 90dp、输入框 68dp（合计 68~90dp）。
      //   412dp 下可用约 392dp，`per = 4` ⇒ 9 项切成 3/3/3，无孤行；
      //   用户真正抱怨的是「战技单独一行」的孤行，不是行数本身。
      expect(_rowCount(rects), lessThanOrEqualTo(4),
          reason: '实测 centerY=${<double>[
                for (final r in rects) r.center.dy
              ]}');
      // ★ 反孤行：按 centerY 分组后每一行至少 2 个按钮
      final rowCenters = <double>[];
      final rowCounts = <int>[];
      for (final r in rects) {
        final cy = r.center.dy;
        var idx = -1;
        // ★ P17 C-3：分组阈值 1.0 → 6.0。骰子条现在混排三种高度（RoomTap 48、
        //   自定义表达式 TextField ~40、stepper 子段 40），同一视觉行的
        //   centerY 最多差 ~5dp；按 1.0dp 分组会把同一行拆成「1 + N」的假孤行
        //   （实测 [7,1,4]，视觉上是 3 行）。6dp 仍在行高（40~48）的一半以下，
        //   相邻两行（间隔 ≥ 40）不可能被误并。
        for (var i = 0; i < rowCenters.length; i++) {
          if ((rowCenters[i] - cy).abs() <= 6.0) {
            idx = i;
            break;
          }
        }
        if (idx < 0) {
          rowCenters.add(cy);
          rowCounts.add(1);
        } else {
          rowCounts[idx] += 1;
        }
      }
      expect(rowCounts.every((int n) => n >= 2), isTrue,
          reason: '仍有孤行，实测每行按钮数 $rowCounts');

      // 战技不能独占一行：与它 centerY 相同的其它按钮至少还有 1 个
      final combat = tester.getRect(find.byKey(RoomKeys.action('combat.roll')));
      final peers = rects
          .where((Rect r) =>
              (r.center.dy - combat.center.dy).abs() <= 1.0 &&
              r != combat)
          .length;
      expect(peers, greaterThanOrEqualTo(1),
          reason: '战技仍是孤零零一行');

      // 所有按钮完整落在骰子条外框内（不被边框/裁剪切掉）
      final dice = tester.getRect(find.byKey(RoomKeys.gpDiceBar));
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].left, greaterThanOrEqualTo(dice.left - 0.5),
            reason: '按钮 $i 左越界');
        expect(rects[i].right, lessThanOrEqualTo(dice.right + 0.5),
            reason: '按钮 $i 右越界');
        expect(rects[i].top, greaterThanOrEqualTo(dice.top - 0.5),
            reason: '按钮 $i 上越界');
        expect(rects[i].bottom, lessThanOrEqualTo(dice.bottom + 0.5),
            reason: '按钮 $i 下越界');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('B2 412 / 1280 / 1524：工具栏不遮挡内容区',
        (WidgetTester tester) async {
      for (final s in _screens) {
        await _bootPage(tester, w: s[0], h: s[1]);
        final bar =
            tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpToolbar)));
        final viewport = tester.getRect(
          find
              .ancestor(
                of: find.byKey(RoomGamePage.zoomKey),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );
        final label = '${s[0].toInt()}×${s[1].toInt()}';
        expect(viewport.bottom, lessThanOrEqualTo(bar.top + 0.5),
            reason: '$label 内容区被工具栏压住');
        expect(bar.bottom, lessThanOrEqualTo(s[1] + 0.5),
            reason: '$label 工具栏越出屏幕');
        expect(tester.takeException(), isNull, reason: '$label 有异常');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  // ========================================================
  // C · KP 平板横屏：红块图落位、缝隙对齐、内容不被裁切
  // ========================================================
  group('C · KP dock 几何（1280 / 1524）', () {
    test('C1 声明式树：槽位 DFS 顺序与 17/83/3 层 flex 链不回归', () {
      final plan = roomDockPlanOf(isKp: true);
      // P16 KP-3 / KP-4②：gpStatus（待办条）与 gpCombat（右列战斗格）已移出
      // KP 平板横屏网格 → 落位表 10 项降为 8 项。
      expect(roomLayoutSlotsOf(plan), <RoomSlot>[
        RoomSlot.gpKpLeft,
        RoomSlot.gpKpTools,
        RoomSlot.gpMap,
        RoomSlot.gpScene,
        RoomSlot.gpPlayers,
        RoomSlot.gpChat,
        RoomSlot.gpLog,
        RoomSlot.gpPriv,
      ]);
      // 正向反证：被移除的两格确实不在落位表里。
      expect(roomLayoutSlotsOf(plan).contains(RoomSlot.gpStatus), isFalse);
      expect(roomLayoutSlotsOf(plan).contains(RoomSlot.gpCombat), isFalse);
      final paths = roomLayoutFlexPathsOf(plan);
      expect(paths[RoomSlot.gpKpLeft], <int>[17]);
      expect(paths[RoomSlot.gpKpTools]!.first, 83);
      expect(paths[RoomSlot.gpMap]!.length, 3);
      // ★ P10 第 7 期新配比：上排 44（降留白）、工具 24 / 素材 50 / 右列 26
      //   （舞台加宽以接近 16:9，消除中间空白）、中排 41 且含私密栏、状态条 5。
      //   DFS 顺序、槽位数、gpKpLeft [17]、gpKpTools.first==83、gpMap.length==3
      //   四条硬约束全部保留。
      expect(paths[RoomSlot.gpKpTools], <int>[83, 44, 24]);
      expect(paths[RoomSlot.gpMap], <int>[83, 44, 50]);
      expect(paths[RoomSlot.gpPriv]!.length, 3,
          reason: '私密栏已并进「底部三块」中排');
      // ★ P11 KP-5：叠放由 `RoomStackNode` + `Positioned.fill` 实现
      //   （`room_layout.dart:367-384`）；声明式树**刻意保留**两格原有的 56 / 44 flex 路径
      //   （`room_layout.dart:83/142/264` 注明「与改前逐字相同」），叠放语义由 C3 的
      //   Rect 逐边相等表达 ⇒ 这两条 flex 路径断言逐字保留（A 组性质，不许改成「路径相等」）。
      expect(paths[RoomSlot.gpScene], <int>[83, 44, 26, 56],
          reason: '右列第一格 38/100 → 56/100');
      expect(paths[RoomSlot.gpPlayers], <int>[83, 44, 26, 44],
          reason: '右列第二格 30/100 → 44/100');
      expect(paths[RoomSlot.gpChat], <int>[83, 46, 1],
          reason: '中排 flex 41 → 46，三块 1:1:1');
      expect(paths.containsKey(RoomSlot.gpStatus), isFalse,
          reason: '待办条节点已删，flex 链里不该再有它');
    });

    test('C2 三个 KP 窄栏下限低于 1280 档实测格宽（不再触发裁切）', () {
      // 1280 档：内容宽 1280-16=1264，根 gap 8 → 1256 按 17:83
      // → 右侧 1042.5；上排 2 gap → 1026.5 按 30:43:27。
      const rightColumn = 1256 * 83 / 100;
      const upperAvailable = rightColumn - 16;
      const toolsW = upperAvailable * 24 / 100;
      const mapW = upperAvailable * 50 / 100;
      const sceneW = upperAvailable * 26 / 100;
      expect(toolsW, greaterThan(roomDockMinWidthOf(RoomSlot.gpKpTools)));
      expect(sceneW, greaterThan(roomDockMinWidthOf(RoomSlot.gpScene)));
      // gpCombat 已不在 dock（其最小宽度语义由同列的 gpPlayers 承接）。
      expect(sceneW, greaterThan(roomDockMinWidthOf(RoomSlot.gpPlayers)),
          reason: '右列剩余两格（场景 / 玩家）都要高于下限');
      // 老基线：素材图仍比右列宽 1.5 倍以上
      expect(mapW, greaterThan(sceneW * 1.5));
    });

    for (final s in <List<double>>[
      <double>[1280, 800],
      <double>[1524, 1016],
    ]) {
      testWidgets('C3[${s[0].toInt()}×${s[1].toInt()}] 缝隙同源、底部三块、内容不裁切',
          (WidgetTester tester) async {
        await _bootPage(tester, w: s[0], h: s[1]);
        final label = '${s[0].toInt()}×${s[1].toInt()}';
        final spec = RoomGridSpec.of(
            w: s[0], h: s[1], landscape: s[0] > s[1]);
        expect(spec.mode, RoomLayoutMode.dock, reason: '$label 档位判错');
        const gap = 8.0; // RoomTheme.panelGap，非 compact

        Rect r(RoomSlot slot) =>
            tester.getRect(find.byKey(RoomKeys.keyOfSlot(slot)));
        final kpLeft = r(RoomSlot.gpKpLeft);
        final tools = r(RoomSlot.gpKpTools);
        final map = r(RoomSlot.gpMap);
        final scene = r(RoomSlot.gpScene);
        final players = r(RoomSlot.gpPlayers);
        final chat = r(RoomSlot.gpChat);
        final log = r(RoomSlot.gpLog);
        final priv = r(RoomSlot.gpPriv);
        final topbar = r(RoomSlot.gpTopbar);
        final toolbar = r(RoomSlot.gpToolbar);

        // ① 同一行顶边对齐
        expect(tools.top, moreOrLessEquals(kpLeft.top, epsilon: 0.6),
            reason: '$label 工具窄栏未与左栏对齐');
        expect(map.top, moreOrLessEquals(kpLeft.top, epsilon: 0.6));
        expect(scene.top, moreOrLessEquals(kpLeft.top, epsilon: 0.6));

        // ② 列间距 = 行间距 = 同一个 gap
        expect(tools.left - kpLeft.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 左栏→工具栏缝隙');
        expect(map.left - tools.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 工具栏→素材图缝隙');
        expect(scene.left - map.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 素材图→右列缝隙（参考图右上场景检定）');
        expect(chat.top - map.bottom, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 行间距必须与列间距同源');
        expect(log.left - chat.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 聊天→记录缝隙');

        // ③ 参考图「底部三块」：私密栏与聊天/记录同一行、等高、缝隙同源
        expect(priv.top, moreOrLessEquals(chat.top, epsilon: 0.6),
            reason: '$label 只给你看的信息应与聊天/记录并排（旧版独占一整行）');
        expect(priv.height, moreOrLessEquals(chat.height, epsilon: 0.6));
        expect(priv.left - log.right, moreOrLessEquals(gap, epsilon: 0.6),
            reason: '$label 记录→私密栏缝隙');
        // ★ P16 KP-3 / KP-4②：状态条与右列战斗格都不再渲染 —— 断言「确实不在」。
        expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpStatus)), findsNothing,
            reason: '$label KP dock 不该再有待办状态条（KP-3 已删）');
        expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpCombat)), findsNothing,
            reason: '$label KP dock 不该再有右列战斗格（KP-4② 已搬进素材舞台）');
        // ★ 2.34.0 / KP-5：场景检定与玩家信息叠放（同一格两层），四边逐边相等；
        //   叠放层吃满上排高度、底端与素材图对齐（不再 56:44 分高）。
        expect(players.left, moreOrLessEquals(scene.left, epsilon: 0.6),
            reason: '$label 叠放层 left 不一致');
        expect(players.top, moreOrLessEquals(scene.top, epsilon: 0.6),
            reason: '$label 叠放层 top 不一致');
        expect(players.right, moreOrLessEquals(scene.right, epsilon: 0.6),
            reason: '$label 叠放层 right 不一致');
        expect(players.bottom, moreOrLessEquals(scene.bottom, epsilon: 0.6),
            reason: '$label 叠放：两格 Rect 逐边相等');
        expect(players.width, moreOrLessEquals(scene.width, epsilon: 0.6));
        expect(players.height, moreOrLessEquals(scene.height, epsilon: 0.6));
        // 原 530/532 逐字保留：右列底端与素材图底端对齐、顶边与素材图同顶。
        expect(players.bottom, moreOrLessEquals(map.bottom, epsilon: 0.6),
            reason: '$label 右列底端必须与素材图底端对齐（不留空带）');
        expect(scene.top, moreOrLessEquals(map.top, epsilon: 0.6));
        // ★ 双底端对齐：叠放层 bottom 也必须 == map.bottom。
        expect(scene.bottom, moreOrLessEquals(map.bottom, epsilon: 0.6),
            reason: '$label 叠放层 bottom 也必须与素材图底端对齐');
        // ★ 拉长正向：叠放后场景检定栏应比旧 56% 分高更长（不是被压缩）。
        final double prevSceneHeight = map.height * 56 / 100;
        expect(scene.height, greaterThan(prevSceneHeight + 1),
            reason: '$label 叠放后场景检定栏应比旧 56% 分高更长');

        // ④ 中间大块仍是最大面积
        final mapArea = map.width * map.height;
        for (final entry in <MapEntry<String, Rect>>[
          MapEntry<String, Rect>('gpKpLeft', kpLeft),
          MapEntry<String, Rect>('gpKpTools', tools),
          MapEntry<String, Rect>('gpScene', scene),
          MapEntry<String, Rect>('gpPlayers', players),
          MapEntry<String, Rect>('gpChat', chat),
          MapEntry<String, Rect>('gpLog', log),
          MapEntry<String, Rect>('gpPriv', priv),
        ]) {
          expect(mapArea, greaterThan(entry.value.width * entry.value.height),
              reason: '$label ${entry.key} 不该比中间大块还大');
        }
        expect(map.width, greaterThan(scene.width * 1.5),
            reason: '$label 中间大块宽度口径');

        // ⑤ 内容不被裁切：三个窄栏子树里都没有横向滚动容器
        for (final slot in <RoomSlot>[
          RoomSlot.gpKpTools,
          RoomSlot.gpScene,
          RoomSlot.gpPlayers,
          RoomSlot.gpPriv,
        ]) {
          expect(_hasHorizontalScroll(tester, RoomKeys.keyOfSlot(slot)), isFalse,
              reason: '$label ${slot.name} 触发 tooNarrow 横向裁切');
        }
        // ★ W-A 删 6 档：先反向验证 6 个档位 key 全无（硬编码字面量），
        //   再对保留的两个动作按钮做原「右/左/下不越 scene 边」几何断言。
        for (final int lv in <int>[5, 4, 3, 2, 0, -1]) {
          expect(find.byKey(ValueKey<String>('gpSceneCheckKp/level/$lv')),
              findsNothing,
              reason: '$label 删 6 档后第 $lv 档按钮不得残留');
        }
        for (final Key k in <Key>[
          GpSceneCheckKeys.quickPush,
          GpSceneCheckKeys.editor,
        ]) {
          final Rect b = tester.getRect(find.byKey(k));
          expect(b.right, lessThanOrEqualTo(scene.right + 0.5),
              reason: '$label 场景检定保留按钮右半被裁');
          expect(b.left, greaterThanOrEqualTo(scene.left - 0.5));
        }
        // 工具窄栏「放单位」按钮完整落在格子内（用户截图「放」只露一半）
        final place = tester.getRect(find.byKey(GpKpToolsKeys.placeActor));
        expect(place.right, lessThanOrEqualTo(tools.right + 0.5),
            reason: '$label 放单位按钮右半被裁');
        expect(place.left, greaterThanOrEqualTo(tools.left - 0.5));

        // ⑥ 全部格子都在「顶栏下沿 ~ 工具栏上沿」之间，不越界
        for (final rect in <Rect>[
          kpLeft, tools, map, scene, players, chat, log, priv
        ]) {
          expect(rect.top, greaterThanOrEqualTo(topbar.bottom - 0.5),
              reason: '$label 格子被顶栏压住');
          expect(rect.bottom, lessThanOrEqualTo(toolbar.top + 0.5),
              reason: '$label 格子被工具栏压住');
          expect(rect.right, lessThanOrEqualTo(s[0] + 0.5),
              reason: '$label 格子右越界');
        }
        // ★ KP-5 正向：收起玩家信息栏后，场景检定栏不能被卸载（仍是同一格的两层）。
        await tester.ensureVisible(
            find.byKey(GpKpPlayersKeys.collapseToggle));
        await tester.tap(find.byKey(GpKpPlayersKeys.collapseToggle));
        await tester.pump();
        expect(find.byKey(GpSceneCheckKeys.modeSkill), findsOneWidget,
            reason: '$label 收起后场景检定栏的技能输入不该消失');
        expect(find.byKey(GpSceneCheckKeys.root), findsOneWidget,
            reason: '$label 收起后场景检定块不该被卸载');
        expect(tester.takeException(), isNull, reason: '$label 有布局异常');
      });
    }
  });

  // ========================================================
  // D · 全档位零回归：12 容器各一个 + 顶栏/工具栏仍钉在缩放容器之外
  // ========================================================
  group('D · 三档 × 两角色零异常', () {
    testWidgets('D1 玩家 dock 已删 4 叶子/其余容器各一个、顶栏与工具栏不在 Transform 下',
        (WidgetTester tester) async {
      for (final s in _screens) {
        for (final seat in <String>[kHostSeat, 'p1']) {
          final label = '${s[0].toInt()}×${s[1].toInt()}/$seat';
          await _bootPage(tester, w: s[0], h: s[1], seat: seat);
          expect(tester.takeException(), isNull, reason: '$label 有异常');
          // P16：KP 平板横屏（dock）已把 gpStatus / gpCombat 移出网格；
          // P20 需求 3②③④：玩家 dock 把 gpPlCombat / gpPlSketch / gpPlNotes / gpStatus
          // 四个叶子一并删掉。这两组在 **dock 档**必须确实不存在，其余槽位仍须各恰好一个
          // （折叠档里这四格仍有方块，不断言 findsNothing）。
          final bool isKpSeat = seat == kHostSeat;
          final bool dockMode = RoomGridSpec.of(
                  w: s[0], h: s[1], landscape: s[0] > s[1])
              .mode == RoomLayoutMode.dock;
          final Set<RoomSlot> absentInDock = switch ((isKpSeat, dockMode)) {
            (true, true) => <RoomSlot>{RoomSlot.gpCombat, RoomSlot.gpStatus},
            (false, true) => <RoomSlot>{
                RoomSlot.gpPlCombat,
                RoomSlot.gpPlSketch,
                RoomSlot.gpPlNotes,
                RoomSlot.gpStatus,
              },
            _ => const <RoomSlot>{},
          };
          for (final slot in (seat == kHostSeat
              ? RoomKeys.kpSlots
              : RoomKeys.plSlots)) {
            if (absentInDock.contains(slot)) {
              expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsNothing,
                  reason: '$label 的 dock 不该有容器 ${slot.name}');
              continue;
            }
            expect(find.byKey(RoomKeys.keyOfSlot(slot)), findsOneWidget,
                reason: '$label 缺容器 ${slot.name}');
          }
          for (final slot in <RoomSlot>[
            RoomSlot.gpTopbar,
            RoomSlot.gpToolbar,
          ]) {
            final el = tester.element(find.byKey(RoomKeys.keyOfSlot(slot)));
            var wrapped = false;
            el.visitAncestorElements((Element a) {
              if (a.widget is Transform) wrapped = true;
              return true;
            });
            expect(wrapped, isFalse,
                reason: '$label ${slot.name} 不该在缩放容器里');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    });
  });

  // ========================================================
  // E · P12 R6（「更强或等价」）：玩家主组 4→5 是产品行为真变。
  //   ★ 本文件 B 组的骰子条核心不变量（9 项、每行 ≥2、无孤行、
  //     diceBalancedRowSizes(9,3)==[3,3,3]、(9,4)==[3,3,3]）逐字保留、
  //     一条都没改；这里只**新增**正向断言，不放宽任何既有断言。
  // ========================================================
  group('E · R6 玩家主组新增 San Check', () {
    testWidgets('E1 San Check 紧跟主动对抗（index = 主动对抗 + 1）',
        (WidgetTester tester) async {
      await _bootPage(tester, w: 412, h: 915, seat: 'p1');
      final Finder opposed = find.byKey(RoomGamePage.playerOpposedKey);
      final Finder san = find.byKey(RoomGamePage.sanCheckKey);
      expect(opposed, findsOneWidget, reason: '玩家主动对抗按钮仍在');
      expect(san, findsOneWidget, reason: '★ R6：新增 San Check 按钮');

      // DFS 顺序 = mainActions 声明顺序；两个按钮之间不夹其它 RoomTap。
      final List<Element> taps = find.byType(RoomTap).evaluate().toList();
      int idxOf(Key k) =>
          taps.indexWhere((Element e) => e.widget.key == k);
      final int iOpposed = idxOf(RoomGamePage.playerOpposedKey);
      final int iSan = idxOf(RoomGamePage.sanCheckKey);
      expect(iOpposed, greaterThanOrEqualTo(0));
      expect(iSan, iOpposed + 1,
          reason: '★ San Check 必须紧贴主动对抗右侧（实测 $iOpposed / $iSan）');

      // ★ R6 真变：玩家主组 4→5 后，412dp 窄屏会**换行**（这正是「主组
      //   行数放宽」的产品行为），所以这里不强制同一行；只断言 San Check
      //   在渲染顺序上不早于「主动对抗」（同行右侧 / 下一行行首都合法）。
      //   「紧跟」的强判据是上面的 DFS index+1。
      final Rect rOpposed = tester.getRect(opposed);
      final Rect rSan = tester.getRect(san);
      expect(rSan.top, greaterThanOrEqualTo(rOpposed.top - 1.0),
          reason: 'San Check 不该排到主动对抗之前');
      expect(rSan.width, greaterThan(0));

      // ★ 逐字保留的核心不变量（与 B1 同源，一条都没放宽）。
      expect(diceBalancedRowSizes(9, 3), <int>[3, 3, 3]);
      expect(diceBalancedRowSizes(9, 4), <int>[3, 3, 3]);
      expect(kDiceExprs.isNotEmpty, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
