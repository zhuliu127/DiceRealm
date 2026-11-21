// ============================================================
// ui/widgets/auto_avatar_png.dart — 自动头像 → **PNG dataURI**（P10 第 3 期 A）
//
// 为什么必须有这一层（上一批如实欠账，本批补齐）：
//   `domain/avatar.dart#make` 产出的是 `data:image/svg+xml;charset=utf-8,`。
//   而房间广播的头像判据（`domain/avatar_uri.dart`）只收
//   `data:image/(png|jpe?g|webp);base64,`，且 **`dart:ui` 不解码 SVG** ——
//   于是「没上传头像的玩家」在别人设备上只能退化成首字圆点。
//   老 APP 的口径是「每人一张 PNG 缩略图随公开 sheet 广播」，这里补上生成器。
//
// 三条硬约束：
//   1. `lib/domain/**` 保持纯度（零 `package:flutter` / `dart:io` / `dart:ui`）
//      → PNG 生成只能放 UI 层；SVG 生成**保留**（本机显示 + 老卡兼容）。
//   2. 视觉与 SVG 版**同源**：取色 / 首字 / 弧转角 / 圆点数全部来自
//      `domain/avatar.dart#specOf`（或 `specFromSvg` 从老卡反解），
//      本文件**不自己算任何散列**，也不可能散成第二套调色板。
//   3. 可注入：`picture.toImage()` / `toByteData()` 是真异步，widget 测试跑在
//      fake-async 区域里永不完成 → 对外暴露 [autoAvatarPngEncoder]，
//      测试换成同步替身即可。
//
// ★ 坐标系照抄 SVG 的 `viewBox="0 0 240 240"`，全部尺寸乘 `size / 240`，
//   所以 128 / 96 / 64 任意档位都是同一张图的等比缩放。
// ============================================================

import 'dart:convert' show base64Encode;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../domain/avatar.dart' show AvatarSpec, specOf;
import '../../domain/avatar_uri.dart' show kAvatarThumbMaxChars;

/// 默认边长（SVG 是 240；PNG 128 已足够 18–24px 的列表头像，且体积小）。
const int kAutoAvatarPngSize = 128;

/// 体积超限时的降级阶梯（与 `repo/avatar_thumb.dart` 同思路）。
const List<int> kAutoAvatarPngFallbacks = <int>[128, 96, 64, 48];

/// 「自动头像参数 → PNG dataURI」的可注入端口（铁律 T1）。
typedef AutoAvatarPngEncoder = Future<String> Function(AvatarSpec spec);

/// 默认实现：真画真编码。失败一律返回空串（绝不抛、绝不返回半截数据）。
Future<String> autoAvatarPng(AvatarSpec spec) async {
  for (final side in kAutoAvatarPngFallbacks) {
    final png = await _renderPng(spec, side);
    if (png == null || png.isEmpty) return '';
    final uri = 'data:image/png;base64,${base64Encode(png)}';
    if (uri.length <= kAvatarThumbMaxChars) return uri;
  }
  return '';
}

/// 全局实例（测试在 `setUp/tearDown` 里替换与还原）。
AutoAvatarPngEncoder autoAvatarPngEncoder = autoAvatarPng;

/// 便利入口：名字 → PNG（等价于 `autoAvatarPng(specOf(name, flavor))`）。
Future<String> autoAvatarPngOf(Object? name, {String flavor = ''}) =>
    autoAvatarPngEncoder(specOf(name, flavor));

// ------------------------------------------------------------
// 内部：照抄 SVG 的画法，只是换成 Canvas
// ------------------------------------------------------------

/// `#RRGGBB` → [Color]。解析失败给透明黑（不抛）。
Color _hexColor(String hex) {
  final s = hex.trim();
  if (s.length != 7 || !s.startsWith('#')) return const Color(0x00000000);
  final v = int.tryParse(s.substring(1), radix: 16);
  if (v == null) return const Color(0x00000000);
  return Color(0xFF000000 | v);
}

Future<Uint8List?> _renderPng(AvatarSpec spec, int side) async {
  if (side <= 0) return null;
  final s = side / 240.0;
  final fg = _hexColor(spec.foreground);
  final top = _hexColor(spec.bgTop);
  final bottom = _hexColor(spec.bgBottom);

  ui.Image? image;
  ui.Picture? picture;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    );

    // ① 渐变底：SVG 的 x1=0,y1=0 → x2=1,y2=1 即左上到右下。
    final bgPaint = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(0, 0),
        ui.Offset(side.toDouble(), side.toDouble()),
        <Color>[top, bottom],
      );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      bgPaint,
    );

    final c = ui.Offset(120 * s, 120 * s);

    // ② 外环 r=104，stroke-opacity .16，width 1
    canvas.drawCircle(
      c,
      104 * s,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..color = fg.withValues(alpha: 0.16)
        ..strokeWidth = (1 * s).clamp(0.5, 8.0),
    );

    // ③ 内环 r=88，stroke-opacity .42，width 2
    canvas.drawCircle(
      c,
      88 * s,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..color = fg.withValues(alpha: 0.42)
        ..strokeWidth = (2 * s).clamp(0.8, 12.0),
    );

    // ④ 上半弧：SVG `M60 120 A60 60 0 0 1 180 120`，再绕 (120,120) 转 rot 度。
    //    等价画法：绕圆心从 180° 顺时针扫 180°（canvas 的 0° 在 3 点方向）。
    final arcPaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..color = fg.withValues(alpha: 0.22)
      ..strokeWidth = (6 * s).clamp(1.0, 24.0)
      ..strokeCap = ui.StrokeCap.round;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(spec.rotationDegrees * math.pi / 180.0);
    canvas.drawArc(
      ui.Rect.fromCircle(center: ui.Offset.zero, radius: 60 * s),
      math.pi, // 180°（左端起点）
      math.pi, // 扫 180° → 到右端
      false,
      arcPaint,
    );
    canvas.restore();

    // ⑤ 外圈圆点：ang = 2πi/dots，中心 (120+100cos, 120+100sin)，r=2.2，opacity .55
    final dotPaint = ui.Paint()..color = fg.withValues(alpha: 0.55);
    for (var i = 0; i < spec.dots; i++) {
      final ang = (math.pi * 2 * i) / spec.dots;
      canvas.drawCircle(
        ui.Offset(
          (120 + 100 * math.cos(ang)) * s,
          (120 + 100 * math.sin(ang)) * s,
        ),
        (2.2 * s).clamp(0.6, 12.0),
        dotPaint,
      );
    }

    // ⑥ 首字：serif 98px 粗体，锚点 (120,124) 居中。
    //    TextPainter 的 drawParagraph 支持 `dominant-baseline:middle` 的等价做法：
    //    先 layout，再把「文字盒」的中心对到目标点。
    final painter = TextPainter(
      text: TextSpan(
        text: spec.initial,
        style: TextStyle(
          color: fg,
          fontFamily: 'serif',
          fontSize: 98 * s,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout();
    painter.paint(
      canvas,
      ui.Offset(120 * s - painter.width / 2, 124 * s - painter.height / 2),
    );
    painter.dispose();

    picture = recorder.endRecording();
    image = await picture.toImage(side, side);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    picture?.dispose();
  }
}

