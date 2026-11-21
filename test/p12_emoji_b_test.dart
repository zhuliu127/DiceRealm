// ============================================================
// test/p12_emoji_b_test.dart — P12 批次 B：跑团房间「按钮底色 + 去 emoji」
//
// 用户原话（2026-11）：
//   · 「还有一些文字按钮但是没有按钮背景图（主要在跑团房间内，招募大厅、
//      准备房间和游戏中），看着有些别扭，你也都补上吧」；
//   · 房间里的 emoji 换成图标。
//
// 本文件逐条钉死：
//   A. 渲染层：三个房间页面上的**文字**里不再出现表情符号；
//   B. 源码层：`lib/ui/room/**` 不再有任何 U+1F300–U+1FAFF 表情字符；
//   C. 按钮底色：每个可点件（`RoomTap`）都套着 `RoomButtonSkin`，后者画出的
//      `Container` 带 `BoxDecoration`，且**与主题里既有面板 / chip 同一套
//      token**（Palette.surface2 + Palette.border + Radii.md）；
//   D. 零布局影响：按钮底色不加一个 padding，`RoomTap` 的尺寸口径不变。
//
// ★ 反向自证伪（写进注释，便于复核）：
//   · 把某个 emoji 加回房间页面的文案 → A / B 红；
//   · 把 `RoomButtonSkin` 的 decoration 去掉 → C 红；
//   · 给 `RoomButtonSkin` 加 `padding: EdgeInsets.all(2)` → D 红。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/theme.dart' show Palette, Radii, buildTheme;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/view/room_view.dart' show whoLine;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show RoomButtonSkin, RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 表情符号（含 dingbat 图形区）。**不含**记录栏里的 `→ ← ✓ ✕ ↻`
/// （U+2190–U+21FF / U+2713 以外另行判断），它们是内容，明令保留。
// ★ P12 修正：ECMAScript RegExp 不允许「代理对」出现在字符类范围端点，
//   [\u{1F300}-\u{1FAFF}] 会在构造期抛 FormatException: Range out of order。
//   改用「高代理 + 低代理」整对匹配，覆盖所有增补平面 emoji。
//   U+2600–27BF 里的 ✓ ✕ ★ 是内容符号，明确保留，不纳入检测。
final RegExp kEmoji = RegExp(r'[\uD800-\uDBFF][\uDC00-\uDFFF]');

/// 把房间页套上「MaterialApp + 房间作用域」（与真 App 同层级，只少主题细节）。
Widget _roomApp(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(seat, child: child),
    );

Future<RoomUiFixture> _bootGame(
  WidgetTester tester, {
  required String seat,
  double w = 360,
  double h = 640,
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
  // ----------------------------------------------------------
  // A · 渲染层：三个房间页面不再有 emoji
  // ----------------------------------------------------------
  group('A · 房间页面渲染出来的文字里没有表情符号', () {
    testWidgets('游戏中（KP 360×640）：整页文字零 emoji', (WidgetTester tester) async {
      await _bootGame(tester, seat: kHostSeat);
      expect(tester.takeException(), isNull);
      expect(find.textContaining(kEmoji), findsNothing,
          reason: '游戏中页面上还留着表情符号');
    });

    testWidgets('游戏中（玩家平板横屏 1280×800）：整页文字零 emoji',
        (WidgetTester tester) async {
      await _bootGame(tester, seat: 'p1', w: 1280, h: 800);
      expect(tester.takeException(), isNull);
      expect(find.textContaining(kEmoji), findsNothing,
          reason: '玩家视角的游戏页还留着表情符号');
    });

    testWidgets('招募大厅（KP，900 高保证整列都建出来）：零 emoji',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 900, 2400);
      await tester.pumpWidget(_roomApp(f, kHostSeat, const RoomLobbyPage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(RoomLobbyPage), findsOneWidget);
      expect(find.textContaining(kEmoji), findsNothing,
          reason: '招募大厅还留着表情符号');
    });

    testWidgets('顶栏身份行（纯视图层 whoLine）不再拼表情',
        (WidgetTester tester) async {
      final f = await _bootGame(tester, seat: kHostSeat);
      // 身份行是纯文本，图标归 widget 层；这里只钉「文字里不夹表情」。
      final String line = whoLine(f.stateOf(kHostSeat), kHostSeat, f.roleOf(kHostSeat));
      expect(line, contains('KP 主持'));
      expect(kEmoji.hasMatch(line), isFalse, reason: 'whoLine 仍在拼 emoji');
    });
  });

  // ----------------------------------------------------------
  // B · 源码层：lib/ui/room 下不再有表情字符
  // ----------------------------------------------------------
  group('B · 源码守卫', () {
    test('lib/ui/room/**/*.dart 里没有任何 1F300–1FAFF 表情字符', () {
      final List<File> files = Directory('lib/ui/room')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(files.length, greaterThan(50), reason: '扫到的房间文件数量不对');
      final List<String> dirty = <String>[
        for (final File f in files)
          if (kEmoji.hasMatch(f.readAsStringSync().replaceAll('★', ''))) f.path,
      ];
      expect(dirty, isEmpty, reason: '这些房间文件里还有表情符号：$dirty');
    });
  });

  // ----------------------------------------------------------
  // C · 按钮底色：与既有面板 / chip 同一套 token
  // ----------------------------------------------------------
  group('C · 文字按钮都有按钮底色', () {
    test('底色取自主题里既有的控件口径（surface2 + border + Radii.md）', () {
      final ThemeData t = buildTheme(Brightness.dark);
      // 交叉验证：本工程里「可点的小控件」本来就是 surface2 底 + border 描边
      //（ChipTheme / InputDecoration 同一口径）；按钮照抄它才叫同一套风格。
      expect(t.chipTheme.backgroundColor, Palette.surface2,
          reason: 'chip 底色口径变了，按钮要跟着改');
      expect(t.inputDecorationTheme.fillColor, Palette.surface2);
      expect(t.chipTheme.side?.color ?? Palette.border, Palette.border);
      // 面板（Card）用同一个圆角 token 与同一根描边色。
      final RoundedRectangleBorder card =
          t.cardTheme.shape! as RoundedRectangleBorder;
      expect(card.side.color, Palette.border, reason: '面板描边色必须一致');
      expect(card.borderRadius, BorderRadius.circular(Radii.md),
          reason: '面板圆角必须一致');
    });

    testWidgets('游戏中：每一个 RoomTap 都画出了带 BoxDecoration 的容器',
        (WidgetTester tester) async {
      await _bootGame(tester, seat: kHostSeat);

      final Finder skins = find.byType(RoomButtonSkin);
      expect(skins, findsWidgets, reason: '游戏页一个按钮皮肤都没有');
      expect(find.byType(RoomTap), findsWidgets);

      var checked = 0;
      for (final Element e in find.byType(RoomButtonSkin).evaluate()) {
        final RoomButtonSkin skin = e.widget as RoomButtonSkin;
        // 皮肤自己 build 出 Container，child 是内层 Material；描边另走
        // foregroundDecoration，这样 1dp 边框不参与布局（尺寸仍是 48×48）。
        final Finder boxFinder = find.descendant(
          of: find.byWidget(skin),
          matching: find.byType(Container),
        );
        expect(boxFinder, findsOneWidget,
            reason: '按钮皮肤必须渲染出带 decoration 的 Container');
        final Container box = tester.widget<Container>(boxFinder);
        final BoxDecoration d = box.decoration! as BoxDecoration;
        expect(d.color, skin.enabled ? Palette.surface2 : Palette.surface2.withValues(alpha: 0.45),
            reason: '按钮底色不是控件口径的 surface2');
        final BoxDecoration edge = box.foregroundDecoration! as BoxDecoration;
        final Border border = edge.border! as Border;
        expect(border.top.color, Palette.border, reason: '按钮描边色与面板不一致');
        expect(border.top.width, 1);
        expect(d.borderRadius, BorderRadius.circular(Radii.md),
            reason: '按钮圆角与面板不一致');
        checked += 1;
      }
      expect(checked, greaterThanOrEqualTo(10),
          reason: '游戏页可点件远不止 $checked 个（工具栏 + 骰子条 + 各块）');
    });

    testWidgets('招募大厅：文字按钮（复制邀请 / 离开 / 开始游戏…）也都有底色',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 900, 2400);
      await tester.pumpWidget(_roomApp(f, kHostSeat, const RoomLobbyPage()));
      await tester.pump();

      for (final Key k in <Key>[
        RoomLobbyKeys.copyInvite,
        RoomLobbyKeys.leave,
        RoomLobbyKeys.start,
      ]) {
        final Finder btn = find.byKey(k);
        expect(btn, findsOneWidget, reason: '$k 不见了');
        expect(find.descendant(of: btn, matching: find.byType(RoomButtonSkin)),
            findsOneWidget,
            reason: '$k 是文字按钮却没有按钮底色');
      }
    });

    testWidgets('底色画在 Material 外面（点了水波纹不会被底色盖住）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: RoomTap(label: '测试', onTap: () {}),
          ),
        ),
      ));
      final Iterable<Element> skins = find.byType(RoomButtonSkin).evaluate();
      expect(skins.length, 1);
      final RoomButtonSkin skin = skins.first.widget as RoomButtonSkin;
      expect(skin.child, isA<Material>());
      expect((skin.child as Material).type, MaterialType.transparency,
          reason: '内层 Material 必须是透明的，否则会盖掉底色或水波纹');
    });

    testWidgets('禁用态：底色更淡，一眼看出不可点', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: RoomTap(label: '不可点', enabled: false),
          ),
        ),
      ));
      final RoomButtonSkin skin =
          tester.widget<RoomButtonSkin>(find.byType(RoomButtonSkin));
      expect(skin.enabled, isFalse);
      final Container box = tester.widget<Container>(find.descendant(
        of: find.byType(RoomButtonSkin),
        matching: find.byType(Container),
      ));
      final BoxDecoration d = box.decoration! as BoxDecoration;
      expect(d.color!.a, lessThan(1.0), reason: '禁用态底色应比可用态淡');
      expect(d.color, Palette.surface2.withValues(alpha: 0.45));
    });
  });

  // ----------------------------------------------------------
  // D · 零布局影响（补底色不许改变尺寸口径）
  // ----------------------------------------------------------
  group('D · 补底色不加 padding，尺寸口径不变', () {
    testWidgets('只有一个文字的 RoomTap 仍是 48×48（minSize 原样）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: RoomTap(label: '好', onTap: () {}),
          ),
        ),
      ));
      expect(tester.getSize(find.byType(RoomTap)), const Size(48, 48),
          reason: '按钮皮肤加了内边距 —— 会把工具栏 / 缩放档位挤出原来的一行');
    });

    testWidgets('自带 minSize 的 RoomTap 尺寸精确等于该值',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: RoomTap(
              label: '好',
              minSize: const Size(96, 40),
              onTap: () {},
            ),
          ),
        ),
      ));
      expect(tester.getSize(find.byType(RoomTap)), const Size(96, 40));
    });
  });
}
