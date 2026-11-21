// ============================================================
// parchment.dart — 「纯色 + 羊皮纸质感」的卡面底（**零资源文件**）
//
// ★ 为什么要有这个文件（P10 第 1 期 A1，用户原话）：
//   「平板视角的一键出卡页，角色信息栏位背景图改成纯色（带羊皮纸纹）的吧，
//     左右各有两道竖线很不好看」
//
// 根因不是 App 画的线，而是**底纹图自己**：候选卡原来用
// `b_card/b1_card_face_3x4`（3:4 竖图）当底，那张图上画了一圈**双线金框**。
//   · 手机上卡片窄高 → `BoxFit.cover` 按高度铺满，左右被裁 → 竖线看不见；
//   · 平板上卡片宽扁 → cover 按宽度铺满，左右竖线正好落在卡片左右边缘内侧，
//     于是「左右各有两道竖线」。
// 只把顶部淡出（P11 那套 ShaderMask）解决不了左右两条，因为它们是**竖**线。
//
// 所以这里给一个**不依赖任何图片**的纸面：底色 + 极轻受光渐变 + 纸纤维噪点 +
// 暗角。全部由 Canvas 现画，不新增资源文件（包体不变），也不受图片比例影响
// —— 宽卡窄卡都不会出现任何一条直线。
//
// ★ 为什么噪点用固定种子：底纹每次重建都要一样。用随机种子的话，同一张卡在
//   重绘后纹理会「跳」一下；固定种子 = 稳定纹理，也方便以后做 golden。
// ============================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart' show Palette;

/// 候选卡 / 面板的「羊皮纸」底。
///
/// 纯色打底 + 三层极轻叠加（受光渐变 / 纸纤维 / 四角暗角）。
/// [intensity] 控制整体浓度（0 = 只有底色，1 = 默认纸面）。
class ParchmentSurface extends StatelessWidget {
  const ParchmentSurface({
    super.key,
    this.seed = 20261110,
    this.intensity = 1,
    this.grain = true,
    this.vignette = true,
  });

  /// 纸纤维的随机种子（固定 → 每次重建纹理一致）。
  final int seed;

  /// 浓度系数（0~1.4 之间取值有意义）。
  final double intensity;

  /// 是否画纸纤维噪点。
  final bool grain;

  /// 是否画四角暗角。
  final bool vignette;

  /// 羊皮纸底色。
  ///
  /// 暗色皮肤下不能直接用亮米色（会在深色页面上糊成一块白斑），
  /// 所以取皮肤表面色再按金色微调一点点暖度 —— 「纸」是观感，不是色号。
  static Color baseColor() {
    final Color warm = Palette.gold.withValues(alpha: Palette.isDark ? 0.05 : 0.07);
    return Color.alphaBlend(warm, Palette.surface);
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Palette.isDark;
    final double k = intensity.clamp(0.0, 1.4);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // ① 纯色底（用户要的「纯色」就是这一层，其余都是极轻叠加）
        ColoredBox(color: baseColor()),
        // ② 受光渐变：左上偏亮、右下偏沉。羊皮纸的「厚度感」全靠这一层。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                (dark ? Colors.white : Colors.white)
                    .withValues(alpha: 0.045 * k),
                Colors.transparent,
                (dark ? Colors.black : const Color(0xFF6B4A1E))
                    .withValues(alpha: 0.06 * k),
              ],
              stops: const <double>[0, 0.45, 1],
            ),
          ),
        ),
        // ③ 纸纤维：确定性随机的小点，只做质感、不抢正文
        if (grain)
          CustomPaint(
            painter: ParchmentGrainPainter(
              seed: seed,
              dark: dark,
              intensity: k,
            ),
          ),
        // ④ 暗角：四边极轻压暗，卡片不会「平得像色块」
        if (vignette)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.9,
                colors: <Color>[
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.10 * k),
                ],
                stops: const <double>[0.62, 1],
              ),
            ),
          ),
      ],
    );
  }
}

/// 纸纤维噪点画笔。
///
/// 为什么自己写 LCG 而不是 `Random(seed)`：`Random` 的序列在不同 Dart 版本上
/// 不保证一致，而这里的纹理位置必须**跨版本可复现**（将来接 golden 才不会
/// 因为升级 SDK 就全红）。LCG 六行就能钉死。
class ParchmentGrainPainter extends CustomPainter {
  ParchmentGrainPainter({
    required this.seed,
    required this.dark,
    this.intensity = 1,
  });

  final int seed;
  final bool dark;
  final double intensity;

  /// 每 10000 平方逻辑像素画多少个点（手机一张卡 ≈ 30~80 个）。
  static const double densityPer10k = 26;

  /// 单点最大半径。
  static const double maxDotRadius = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final double area = size.width * size.height;
    if (area <= 0) return;
    final int count = (area / 10000 * densityPer10k * intensity)
        .round()
        .clamp(0, 900);
    if (count == 0) return;

    final Paint paint = Paint()..style = PaintingStyle.fill;
    final double lightA = (dark ? 0.05 : 0.045) * intensity;
    final double darkA = (dark ? 0.06 : 0.05) * intensity;
    // LCG 常量取自 Numerical Recipes（32 位状态足够，且不依赖 dart:math.Random）
    int state = (seed & 0x7fffffff) | 1;

    double next() {
      state = (state * 1664525 + 1013904223) & 0x7fffffff;
      return state / 0x7fffffff;
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < count; i++) {
      final double x = next() * size.width;
      final double y = next() * size.height;
      final double r = 0.25 + next() * (maxDotRadius - 0.25);
      final bool light = next() > 0.5;
      paint.color = (light ? Colors.white : Colors.black)
          .withValues(alpha: light ? lightA : darkA);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ParchmentGrainPainter old) =>
      old.seed != seed || old.dark != dark || old.intensity != intensity;

  /// 供测试断言用：给定面积该画多少个点（不想让用例去数 Canvas 调用）。
  static int dotsFor(Size size, {double intensity = 1}) {
    final double area = size.width * size.height;
    if (area <= 0) return 0;
    return (area / 10000 * densityPer10k * intensity).round().clamp(0, 900);
  }
}

/// 小工具：给一个 DecoratedBox 级别的「纸面」boxDecoration（不含纤维 / 暗角）。
///
/// 用在只需要底色 + 受光渐变的轻量场合（例如面板内的小标题底）。
BoxDecoration parchmentDecoration({double radius = 12, double intensity = 1}) {
  final bool dark = Palette.isDark;
  return BoxDecoration(
    color: ParchmentSurface.baseColor(),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Palette.gold.withValues(alpha: 0.20)),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Colors.white.withValues(alpha: 0.04 * intensity),
        Colors.transparent,
        (dark ? Colors.black : const Color(0xFF6B4A1E))
            .withValues(alpha: 0.05 * intensity),
      ],
      stops: const <double>[0, 0.45, 1],
    ),
  );
}

/// 只给「数值」用的小助手：把 [0,1] 的浓度映射成 0~255 的 alpha 字节。
int parchmentAlphaByte(double intensity) =>
    (intensity.clamp(0.0, 1.0) * 255).round().clamp(0, 255);

/// 数学常量复用到 `math.pi` 的场合（保持本文件只依赖一个 dart 库）。
double get parchmentHalfTurn => math.pi;
