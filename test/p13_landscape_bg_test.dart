// ============================================================
// test/p13_landscape_bg_test.dart — 横屏游戏页背景（P13 · A1）接入断言
//
// 背景：`Art.gameBgLand`（16:9 横版）此前已声明、素材也已在包内，但全库
//   零渲染；`room_game_page.dart` 恒用 9:16 竖版 `BoxFit.cover` 铺满整页，
//   平板横屏（约 1524×1016）上下各裁约 31%，只剩中间一条暗带，星云构图全丢。
//   本次给 `Art.gameBgFor` 加可选 `landscape`，调用点按屏幕宽高比传值。
//
// 本文件是**纯函数单测**：不加载素材、不 pumpWidget、不依赖 asset bundle，
//   只锁死 `Art.gameBgFor(b, {landscape})` 的四格语义 + 资源实体在包内：
//     · 默认 / landscape:false 与接入前逐字等价（回归钉子）；
//     · 横屏暗色 → 16:9 横版（本次核心正向断言，对应覆盖点 2）；
//     · 横屏亮色 → 专属亮色横版 `gameBgLandLight`（P15 起不再回退竖版，
//       仍不出现深紫补丁）；
//     · `gameBgLand` / `gameBgLandLight` 指向的文件真实存在且非空；
//     · 四张游戏页背景两两不等。
//
// 反向自证伪（本项目惯例，参照 p12_banner_inset_test.dart）：把 `art.dart`
//   横屏取图行临时改回 `return pick(gameBgLand, gameBgLight, b);`
//   （假装没接亮色横版），本文件覆盖点 3 用例必须变红；末尾守卫用例
//   证明「未接入」的返回值确实不同于横版断言，不是恒真的假保护。
//   恢复后源码须逐字节一致。
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/ui/art.dart' show Art;
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

/// 工程内素材相对路径（`flutter test` 的 cwd 为包根）。
const String kLandAssetRel = 'assets/images/e_game/e2_game_bg_land_16x9.webp';
const String kLandLightAssetRel =
    'assets/images/e_game/e2_game_bg_land_light_16x9.webp';

void main() {
  // 覆盖点 1：默认行为逐字不变。省略参数与显式 false 都走原来那条
  // `pick(gameBg, gameBgLight, b)`，接入前后返回值必须一模一样。
  test('默认行为：省略 / landscape:false 时仍是暗竖亮竖', () {
    expect(Art.gameBgFor(Brightness.dark), Art.gameBg);
    expect(Art.gameBgFor(Brightness.light), Art.gameBgLight);
    expect(Art.gameBgFor(Brightness.dark, landscape: false), Art.gameBg);
    expect(Art.gameBgFor(Brightness.light, landscape: false), Art.gameBgLight);
  });

  // 覆盖点 2：本次接入的核心正向断言。
  // 反向证伪（把横屏分支改回竖版）时，这条必须变红。
  test('横屏暗色 → 16:9 横版 gameBgLand', () {
    expect(
      Art.gameBgFor(Brightness.dark, landscape: true),
      Art.gameBgLand,
      reason: '横屏暗色仍取 9:16 竖版，说明 A1 没接上（或被人改回去了）',
    );
  });

  // 覆盖点 3：P15 起横屏亮色有了专属亮色横版，不再回退亮色竖版；
  // 原来两条「不出现暗色横版 / 暗色竖版」的不变量逐字保留并新增一条。
  test('横屏亮色 → 亮色横版 gameBgLandLight', () {
    final String path = Art.gameBgFor(Brightness.light, landscape: true);
    expect(path, Art.gameBgLandLight);
    expect(path, isNot(Art.gameBgLand),
        reason: '亮色横屏不能出现暗色横版补丁（用户明确提过「黑色补丁」）');
    expect(path, isNot(Art.gameBg));
    expect(path, isNot(Art.gameBgLight),
        reason: '亮色横屏不得再回退亮色竖版');
  });

  // 覆盖点 4：路径常量与磁盘实体一致。ArtImage 缺图是静默不显示的，
  // 只有钉住文件真实存在，上面的路径断言才有意义。
  test('gameBgLand 指向的素材文件真实在包内', () {
    expect(Art.gameBgLand, kLandAssetRel);
    final File asset = File(kLandAssetRel);
    expect(asset.existsSync(), isTrue,
        reason: '缺图时 ArtImage 静默不显示，必须钉住素材实体存在');
    expect(asset.lengthSync(), greaterThan(0),
        reason: '零字节素材等同缺图');
  });

  // 覆盖点 6（P15 新增）：亮色横版素材实体在包内。ArtImage 缺图是静默
  // 不显示的，只有钉住文件真实存在，横屏亮色的路径断言才有意义。
  test('gameBgLandLight 指向的素材文件真实在包内', () {
    expect(Art.gameBgLandLight, kLandLightAssetRel);
    final File asset = File(kLandLightAssetRel);
    expect(asset.existsSync(), isTrue,
        reason: '缺图时 ArtImage 静默不显示，必须钉住亮色横版素材实体存在');
    expect(asset.lengthSync(), greaterThan(0),
        reason: '零字节素材等同缺图');
  });

  // 覆盖点 7（P15 新增，更强）：四张游戏页背景两两不等，
  // 防止新增常量被误写成已有别名、或某张图被悄悄复用。
  test('四张游戏页背景两两不等', () {
    final Set<String> all = <String>{
      Art.gameBg,
      Art.gameBgLight,
      Art.gameBgLand,
      Art.gameBgLandLight,
    };
    expect(all.length, 4,
        reason: '四张背景必须是四个互不相同的资源路径');
  });

  // 覆盖点 5 的用例化守卫（p12「反向自证伪」写法）：模拟「没接入」的实现，
  // 证明第 2 条不是恒真的假保护 —— 若未接入的返回值恰好等于横版，
  // 那第 2 条断言就抓不住回归，这条守卫会先红。
  test('反向自证伪：假装没接入时第 2 条断言确实抓得住', () {
    final String notWired =
        Art.pick(Art.gameBg, Art.gameBgLight, Brightness.dark);
    expect(notWired, Art.gameBg,
        reason: '未接入的横屏暗色应仍是 9:16 竖版');
    expect(notWired, isNot(Art.gameBgLand),
        reason: '若未接入的返回值恰好是横版，第 2 条断言就是恒真的假保护');
    expect(Art.gameBg, isNot(Art.gameBgLand),
        reason: '竖版与横版必须是两张不同的资源');
  });
}
