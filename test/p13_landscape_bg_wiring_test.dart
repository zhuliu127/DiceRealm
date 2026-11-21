// ============================================================
// test/p13_landscape_bg_wiring_test.dart — 横屏游戏页背景「接线」验证
//
// 为什么需要这个文件（工程师如实登记的缺口）：
//   p13_landscape_bg_test.dart 只锁死 `Art.gameBgFor` 这个**纯函数**的四格
//   语义；p12_game_e2e_test.dart 只验证「布局不崩」，不验证背景图被选中。
//   若有人把 room_game_page.dart:301 改回 `Art.gameBgFor(Palette.brightness)`
//   （漏传 landscape），上述全部测试**依然全绿** —— 纯函数是对的，但页面
//   根本没把它接上。本文件补的就是这段「调用点 → 页面实际渲染」的空白。
//
// 验证口径（widget 级，不是纯函数级）：
//   · 复用 p12 的脚手架：RoomUiFixture.boot(inGame: true) 真实 action 开团，
//     f.scoped(seat, child: RoomGamePage()) 套房间作用域，useRoomScreen 设屏幕；
//   · 用 `find.byWidgetPredicate((w) => w is ArtImage && w.path == ...)`
//     精确定位页面里**实际渲染**的背景 ArtImage（ArtImage.path 是公开字段）；
//   · 期望路径**硬编码为 Art.gameBg / gameBgLand / gameBgLight 常量**，
//     绝不调用 Art.gameBgFor(...) 来生成期望值 —— 否则等于用被测实现验证
//     被测实现，接线回归时断言会跟着一起「正确」，变成恒真假保护。
//
// ★ 屏幕尺寸必须显式设定：widget test 默认视口 800×600 是**横屏**（宽>高），
//   会掩盖竖屏分支。useRoomScreen 设 physicalSize = w*3 × h*3、dpr = 3，
//   并在 addTearDown 里恢复。每条用例另加「屏幕方向守卫」把这点钉死。
//
// ★ 主题必须显式同步全局色板：room_game_page.dart:301 读的是
//   `Palette.brightness`（全局静态），不是 Theme.of(context).brightness。
//   本壳用 MaterialApp（同 p12），不经过 app.dart:76 的 DiceRealmApp 每帧重置，
//   所以 pumpWidget 前调 Palette.useBrightness(b) 可稳定生效；
//   setUp/tearDown 复位到 dark，避免污染同文件其它用例。
//
// 反向自证伪（针对「接线」，不是纯函数）：把 :301 的 `landscape: landscape`
//   临时去掉 → 四个横屏场景（暗色 1/2、亮色 3/6）各 2 条必须变红
//   （期望的横版变 findsNothing，且 forbidden 里出现实际渲染的竖版），
//   两个竖屏场景 4/5 按设计仍绿（竖屏本就 landscape=false）。
//   恢复后逐字节一致。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/theme.dart' show Palette;
import 'package:dice_realm/ui/art.dart' show Art, ArtImage;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 四张游戏页背景（用于「页面里恰好只有其中一张」的加固断言）。
/// P15 新增 `Art.gameBgLandLight`：集合扩到 4 张后，下面的
/// `rendered == <String>{c.expected}` 断言自动更强（不放宽）。
const Set<String> _kAllGameBg = <String>{
  Art.gameBg,
  Art.gameBgLight,
  Art.gameBgLand,
  Art.gameBgLandLight,
};

/// 一条接线场景：屏幕尺寸 + 皮肤 + 期望被选中的背景 + 绝不该出现的背景。
class _Case {
  const _Case(
    this.name,
    this.w,
    this.h,
    this.brightness,
    this.expected,
    this.forbidden,
  );

  final String name;
  final double w;
  final double h;
  final Brightness brightness;
  final String expected;
  final List<String> forbidden;

  bool get landscape => w > h;
}

/// 覆盖矩阵：三种横屏尺寸（含 2.156 极值）、两种竖屏尺寸，暗 / 亮都覆盖。
/// forbidden 一律列全不该出现的背景，锁定「四张里恰好一张」。
// 私有常量：类型是私有 _Case，若暴露成 public 名字会触发
// library_private_types_in_public_api（flutter analyze 全库守卫）。
const List<_Case> _kCases = <_Case>[
  // ① 任务要求的横屏暗色：证伪注入后这一格必须变红。
  _Case('横屏平板 1280×800 / 暗色', 1280, 800, Brightness.dark,
      Art.gameBgLand, <String>[Art.gameBg, Art.gameBgLight]),
  _Case('横屏小窗 780×320 / 暗色', 780, 320, Brightness.dark,
      Art.gameBgLand, <String>[Art.gameBg, Art.gameBgLight]),
  // ② 任务要求的横屏亮色（P15 更新）：期望专属亮色横版
  // `gameBgLandLight`；forbidden 在原有两项之上新增 `gameBgLight`，
  // 锁死「不再回退亮色竖版」。
  _Case('横屏平板 1280×800 / 亮色', 1280, 800, Brightness.light,
      Art.gameBgLandLight,
      <String>[Art.gameBgLand, Art.gameBg, Art.gameBgLight]),
  // ③ 任务要求的竖屏暗色：默认视口 800×600 是横屏，这条同时守住尺寸夹具。
  _Case('竖屏手机 360×640 / 暗色', 360, 640, Brightness.dark,
      Art.gameBg, <String>[Art.gameBgLand, Art.gameBgLight]),
  // ④ 补充：竖屏平板亮色，锁死「竖屏 + 亮色」不与横版混淆。
  _Case('竖屏平板 820×1180 / 亮色', 820, 1180, Brightness.light,
      Art.gameBgLight, <String>[Art.gameBgLand, Art.gameBg]),
  // ⑤ P15 新增：横屏手机 1080×500（≈2.16，Magic9 横屏极值），
  // 与场景 3 的 1.5 一起覆盖两个横屏比例极值。
  _Case('横屏手机 1080×500 / 亮色', 1080, 500, Brightness.light,
      Art.gameBgLandLight,
      <String>[Art.gameBgLand, Art.gameBg, Art.gameBgLight]),
];

/// 精确命中「path == [path]」的 ArtImage。
Finder _bg(String path) => find.byWidgetPredicate(
      (Widget w) => w is ArtImage && w.path == path,
      description: 'ArtImage(path: $path)',
    );

/// 页面壳：同步全局色板（页面选图读 Palette.brightness），
/// theme 同步亮/暗以免 ArtImage 的兜底色与断言口径不一致。
Widget _app(RoomUiFixture f, String seat, Brightness b) {
  Palette.useBrightness(b);
  return MaterialApp(
    theme: b == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true),
    home: f.scoped(seat, child: const RoomGamePage()),
  );
}

Future<void> _boot(
  WidgetTester tester, {
  required String seat,
  required double w,
  required double h,
  required Brightness brightness,
}) async {
  final RoomUiFixture f = RoomUiFixture();
  await f.boot(inGame: true); // 真实 action 开团 + 玩家带完整卡（同 p12）
  useRoomScreen(tester, w, h); // 内部 addTearDown 恢复 physicalSize / dpr
  await tester.pumpWidget(_app(f, seat, brightness));
  await tester.pump();
}

void main() {
  // Palette 是全局可变状态：每条用例起点一致，结束复位，不污染其它用例。
  setUp(() => Palette.useBrightness(Brightness.dark));
  tearDown(() => Palette.useBrightness(Brightness.dark));

  for (final _Case c in _kCases) {
    for (final String seat in <String>[kHostSeat, 'p1']) {
      final String who = seat == kHostSeat ? 'KP' : '玩家';
      final String short = c.expected.split('/').last;

      testWidgets('$who · ${c.name} → 实际渲染 $short',
          (WidgetTester tester) async {
        // Arrange：显式设屏幕尺寸 + 皮肤，pump 真游戏页。
        await _boot(
          tester,
          seat: seat,
          w: c.w,
          h: c.h,
          brightness: c.brightness,
        );

        final BuildContext ctx =
            tester.element(find.byType(RoomGamePage).first);
        final String tag = '${c.name} / $who';

        // 守卫 1：页面确实渲染出来了，且没抛异常（否则后续断言无意义）。
        expect(find.byType(RoomGamePage), findsOneWidget,
            reason: '$tag：游戏页没渲染出来，背景断言无意义');
        expect(tester.takeException(), isNull,
            reason: '$tag：游戏页渲染时抛异常（布局溢出会在这里冒出来）');

        // 守卫 2：显式尺寸真的生效。默认视口 800×600 是横屏，若
        // useRoomScreen 没生效，竖屏用例会在这里先红，避免「竖屏分支被
        // 默认横屏掩盖、断言因别的原因偶然绿」的假绿。
        final Size mq = MediaQuery.of(ctx).size;
        expect(mq.width > mq.height, c.landscape,
            reason: '$tag：页面实际读到的 MediaQuery.size = '
                '${mq.width}×${mq.height}，方向与用例声明的 '
                '${c.landscape ? '横屏' : '竖屏'} 不符 —— '
                'useRoomScreen 没生效或默认 800×600 横屏没被覆盖');

        // 守卫 3：皮肤真的切到位。页面选图读全局 Palette.brightness，
        // 若没切，下面断言测的其实是另一套皮肤。
        expect(Palette.brightness, c.brightness,
            reason: '$tag：全局色板没切到 ${c.brightness}，'
                '背景断言测的不是目标皮肤');
        expect(Theme.of(ctx).brightness, c.brightness,
            reason: '$tag：MaterialApp theme 与目标皮肤不一致');

        // Act + Assert：精确口径，不放宽成 findsWidgets。
        expect(_bg(c.expected), findsOneWidget,
            reason: '$tag：页面里应恰好有 1 个 path == ${c.expected} 的 '
                'ArtImage；findsNothing 说明 room_game_page.dart:301 没把 '
                'landscape 传进去（选图回退到旧竖版 / 漏接 A1）');

        for (final String p in c.forbidden) {
          expect(_bg(p), findsNothing,
              reason: '$tag：不该出现 path == $p 的背景 —— '
                  '接线错、方向判据错或皮肤回退错');
        }

        // 加固（更强，非放宽）：四张游戏页背景里恰好只有期望那一张被渲染，
        // 杜绝「两张背景叠在一起」或「选了集合外的背景」这类漏网情形。
        final Set<String> rendered = find
            .byWidgetPredicate(
              (Widget w) => w is ArtImage && _kAllGameBg.contains(w.path),
              description: '游戏页背景 ArtImage',
            )
            .evaluate()
            .map((Element e) => (e.widget as ArtImage).path)
            .toSet();
        expect(rendered, <String>{c.expected},
            reason: '$tag：页面实际渲染的游戏页背景集合为 $rendered，'
                '应恰好只有 ${c.expected} 一张');
      });
    }
  }
}
