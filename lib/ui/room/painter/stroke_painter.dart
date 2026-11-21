// ============================================================
// painter/stroke_painter.dart — 笔迹 / 标点 / 手绘板画笔（设计 §2.6）
//
// ★ 只画、不发 intent、不改 state：本文件零权威端调用。
// ★ K5：坐标换算只在这里做一次「归一化 → 像素」，**不乘 zoom**
//   （Transform.scale 会自动把 localPosition 变换回未缩放本地系）。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_state.dart' show roomNumber;
import 'package:flutter/material.dart';

import '../room_theme.dart';
import '../view/scene_view.dart';
import '../room_text.dart';

/// 归一化点 → 画布像素偏移。
Offset normToOffset(NormPoint p, Size size) =>
    Offset(clampNorm(p.x) * size.width, clampNorm(p.y) * size.height);

/// 笔迹宽度（脏数据夹到 1–24）。
double strokeWidthOf(Map<String, Object?> st) {
  final w = roomNumber(st['width'], 3).toDouble();
  if (w < 1) return 1;
  if (w > 24) return 24;
  return w;
}

int _strokeArgb(Map<String, Object?> st) {
  final raw = roomText(st['color']);
  return raw.isEmpty ? RoomTheme.drawColorArgb(0) : RoomTheme.colorArgb(raw);
}

Paint _strokePaint(Map<String, Object?> st, double extra) => Paint()
  ..color = Color(_strokeArgb(st))
  ..strokeWidth = strokeWidthOf(st) + extra
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Path _pathOf(List<NormPoint> pts, Size size) {
  final path = Path();
  if (pts.isEmpty) return path;
  final first = normToOffset(pts.first, size);
  path.moveTo(first.dx, first.dy);
  for (var i = 1; i < pts.length; i++) {
    final o = normToOffset(pts[i], size);
    path.lineTo(o.dx, o.dy);
  }
  // 单点笔迹也画成一个可见的圆点（drawPath 对零长度路径不落墨）。
  if (pts.length == 1) path.lineTo(first.dx + 0.1, first.dy);
  return path;
}

/// 地图笔迹（scene.strokes）。
class StrokesPainter extends CustomPainter {
  const StrokesPainter(this.strokes, {this.highlightIndex = -1});

  final List<Map<String, Object?>> strokes;
  final int highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < strokes.length; i++) {
      final st = strokes[i];
      final pts = strokePointsOf(st);
      if (pts.isEmpty) continue;
      canvas.drawPath(
        _pathOf(pts, size),
        _strokePaint(st, i == highlightIndex ? 2 : 0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant StrokesPainter old) =>
      old.strokes != strokes || old.highlightIndex != highlightIndex;
}

// ------------------------------------------------------------
// ★ P17 C-2：舞台标点标签的取色（纯函数，可单测、无 context 依赖）
//
// 为什么不能只按主题 onSurface 取色：C-4 把「无公开素材」的舞台改成了
// **硬白板**（`Colors.white`，亮/暗主题都白），暗色主题的 onSurface 是
// 近白色 —— 直接用它就是「白底白字」。
//
// 所以标签色一律按**画布类型**决定（不看主题）：
//   无公开素材（白板）→ 深灰标签 + 白色描边（描边在白底上看不见，但压住
//                        白板上的彩色笔迹/标点圆点时仍然是亮的，不会糊）；
//   有公开素材（底图）→ 近白标签 + 半透明黑描边（底图明暗不可控，靠描边
//                        保证「字边」永远与字色成强对比）。
// ------------------------------------------------------------

/// 舞台标点标签的**文字填充色**。
///
/// [hasCover] 为 true 表示画布上有公开素材底图（明暗不可控）→ 近白；
/// 为 false 表示无素材白板（亮暗主题都是硬白）→ 深灰。
Color stageMarkLabelColor(bool hasCover) =>
    hasCover ? const Color(0xfff5f5f5) : const Color(0xff222222);

/// 舞台标点标签的**对比描边色**（与 [stageMarkLabelColor] 成反调）。
Color stageMarkLabelHalo(bool hasCover) =>
    hasCover ? const Color(0xcc000000) : const Color(0xccffffff);

/// 地图标点（scene.marks）：实心圆 + 白色内芯 + 可选标签。
///
/// 标签默认色（`0xff222222`）保留给不传参的调用点；舞台侧（C-2）会按画布
/// 类型显式传 [labelColor] / [labelHalo]，见 `stageMarkLabelColor`。
class MarksPainter extends CustomPainter {
  const MarksPainter(
    this.marks, {
    this.labelColor = const Color(0xff222222),
    this.labelHalo = const Color(0xccffffff),
  });

  final List<Map<String, Object?>> marks;

  /// 标签文字色（默认深灰，与 P17 之前的写死值一致）。
  final Color labelColor;

  /// 标签描边色：先描边再填字，保证压在任何底色上都有「字边对比」。
  final Color labelHalo;

  Color _markColor(String kind) {
    switch (kind) {
      case 'pin':
        return const Color(0xff3498db);
      case 'note':
        return const Color(0xfff1c40f);
      default:
        return const Color(0xffe74c3c);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in marks) {
      final p = NormPoint(
        roomNumber(m['x'], 0).toDouble(),
        roomNumber(m['y'], 0).toDouble(),
      );
      final o = normToOffset(p, size);
      final color = _markColor(roomText(m['kind']));
      canvas.drawCircle(o, 8, Paint()..color = color);
      canvas.drawCircle(o, 3, Paint()..color = const Color(0xffffffff));

      final label = roomText(m['label']);
      if (label.isEmpty) continue;
      // ★ P17 C-2：标签分两层画 —— 先描边（[labelHalo]），再填字（[labelColor]）。
      //   描边层不设 `color`（TextStyle 的 color 与 foreground 互斥）。
      final fill = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: labelColor, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      final at = Offset(o.dx - fill.width / 2, o.dy + 10);
      if (labelHalo.a > 0) {
        final halo = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 11,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.5
                ..strokeJoin = StrokeJoin.round
                ..color = labelHalo,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width);
        halo.paint(canvas, at);
      }
      fill.paint(canvas, at);
    }
  }

  @override
  bool shouldRepaint(covariant MarksPainter old) =>
      old.marks != marks ||
      old.labelColor != labelColor ||
      old.labelHalo != labelHalo;
}

/// 玩家手绘板：既支持**分段笔迹** `[{id, pts:[{x,y},...]}, ...]`
/// （P13 T3，跨段不连线、全段绘制），也兼容旧**扁平点集** `[{x,y},...]`
/// （仍按 page/perPage 切片，保持旧行为）。两种载荷自动识别。
class BoardPainter extends CustomPainter {
  const BoardPainter(
    this.points, {
    this.page = 0,
    this.perPage = 200,
    // ★ P16 P-3：玩家手绘板默认纯黑（配合 gp_pl_sketch 的不透明白板）。
    //   只改这一处默认值，覆盖所有 BoardPainter(points) 调用点。
    this.color = 0xff000000,
  });

  final List<Map<String, Object?>> points;
  final int page;
  final int perPage;
  final int color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(color)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ★ 分段笔迹：每段各画一条 path（跨段不连线），且**全段绘制**不受
    //   page/perPage 限制 —— 旧版扁平点集只画前 perPage(200) 点，正是
    //   「画几笔后就什么都画不出来」的隐藏成因之一。
    final bool segmented =
        points.any((Map<String, Object?> s) => s.containsKey('pts'));
    if (segmented) {
      for (final raw in points) {
        final pts = <NormPoint>[];
        for (final pRaw in asList(asMap(raw)['pts'])) {
          final p = asMap(pRaw);
          pts.add(NormPoint(
            roomNumber(p['x'], 0).toDouble(),
            roomNumber(p['y'], 0).toDouble(),
          ));
        }
        if (pts.isEmpty) continue;
        canvas.drawPath(_pathOf(pts, size), paint);
      }
      return;
    }

    // 旧扁平点集：按页切片，逐字保留既有行为（兼容旧存档 / 旧 intent 载荷）。
    final start = page * perPage;
    if (start < 0 || start >= points.length) return;
    final end = (start + perPage) > points.length ? points.length : start + perPage;
    final slice = points.sublist(start, end);
    final pts = <NormPoint>[];
    for (final raw in slice) {
      final p = asMap(raw);
      pts.add(NormPoint(
        roomNumber(p['x'], 0).toDouble(),
        roomNumber(p['y'], 0).toDouble(),
      ));
    }
    if (pts.isEmpty) return;
    canvas.drawPath(_pathOf(pts, size), paint);
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.points != points || old.page != page || old.color != color;
}
