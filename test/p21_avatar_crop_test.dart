// ============================================================
// test/p21_avatar_crop_test.dart — 头像圆形缩放裁切（纯函数 / 控制器）验收
//
// 覆盖（全部普通 test，不依赖 widget / fake-async，真编解码）：
//   · cropSquareToPng 输出永远是 512×512 PNG；
//   · 取景框中心像素 = 原图中心像素（无缩放无平移时居中对齐）；
//   · 放大后同一取景框中心取到原图更靠外的像素（真的放大了）；
//   · 平移后中心像素来自原图不同位置（真的平移了）；
//   · controller 夹紧：scale=1 时强平移不露空（offset 被夹回 0）；
//   · zoomBy 边界：scale 被夹在 [1, 6]；reset 回到 1 倍居中。
// ============================================================

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dice_realm/ui/widgets/avatar_cropper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一张「四象限不同色」的 PNG，便于验证裁切取到了哪个区域的像素。
/// 左上红、右上绿、左下蓝、右下黄。尺寸 [w]×[h]。
Future<Uint8List> _quadPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final hw = w / 2;
  final hh = h / 2;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, hw, hh),
    Paint()..color = const Color(0xFFFF0000), // 左上 红
  );
  canvas.drawRect(
    Rect.fromLTWH(hw, 0, hw, hh),
    Paint()..color = const Color(0xFF00FF00), // 右上 绿
  );
  canvas.drawRect(
    Rect.fromLTWH(0, hh, hw, hh),
    Paint()..color = const Color(0xFF0000FF), // 左下 蓝
  );
  canvas.drawRect(
    Rect.fromLTWH(hw, hh, hw, hh),
    Paint()..color = const Color(0xFFFFFF00), // 右下 黄
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 读回 PNG 指定坐标（相对左上）的像素颜色。
Future<Color> _pixelAt(Uint8List png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final idx = (y * image.width + x) * 4;
  final r = bytes!.getUint8(idx);
  final g = bytes.getUint8(idx + 1);
  final b = bytes.getUint8(idx + 2);
  image.dispose();
  codec.dispose();
  return Color.fromARGB(255, r, g, b);
}

/// 造一张水平渐变 PNG（横向灰阶随 x 单调增加 0→255）。
Future<Uint8List> _gradientPng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..shader = ui.Gradient.linear(
      Offset.zero,
      Offset(w.toDouble(), 0),
      const <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
    );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    paint,
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<(int, int)> _pngSize(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final size = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return size;
}

/// 通道近似比较（PNG 编解码可能有 ±2 的误差）。
void _expectColor(Color actual, Color expected, {String? reason}) {
  int ch(double v) => (v * 255).round();
  final dr = (ch(actual.r) - ch(expected.r)).abs();
  final dg = (ch(actual.g) - ch(expected.g)).abs();
  final db = (ch(actual.b) - ch(expected.b)).abs();
  expect(dr <= 6 && dg <= 6 && db <= 6, isTrue,
      reason: reason ?? '颜色应接近 $expected，实际 $actual');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List quad; // 600×600 四象限

  setUpAll(() async {
    quad = await _quadPng(600, 600);
  });

  group('cropSquareToPng 纯函数', () {
    test('输出恒为 512×512', () async {
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      );
      final out = await cropSquareToPng(quad, ctl);
      expect(out, isNotNull);
      final (w, h) = await _pngSize(out!);
      expect((w, h), (512, 512));
    });

    test('正方形图默认（1 倍居中）：取景框中心 = 原图中心（四色交汇处附近）',
        () async {
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      );
      final out = await cropSquareToPng(quad, ctl);
      // 输出正中心 (256,256) 恰好落在四象限交汇点，取哪个象限都行；
      // 稍微偏移一点确认它来自原图中心而非边角。
      final justRightTop = await _pixelAt(out!, 300, 200);
      // 中心偏右上 ⇒ 原图右上象限 ⇒ 绿。
      _expectColor(justRightTop, const Color(0xFF00FF00),
          reason: '中心偏右上应取到原图右上（绿）象限');
      final justLeftBottom = await _pixelAt(out, 200, 300);
      // 中心偏左下 ⇒ 原图左下象限 ⇒ 蓝。
      _expectColor(justLeftBottom, const Color(0xFF0000FF),
          reason: '中心偏左下应取到原图左下（蓝）象限');
    });

    test('放大后取景框中心取到原图更靠外的像素（真的放大了）', () async {
      // 用水平渐变图：横向像素值随 x 单调变化。放大后取景框某点对应的原图
      // x 会离中心更远 ⇒ 采到的灰阶不同（四象限图在同象限内都是纯色，测不出）。
      final grad = await _gradientPng(600, 600);
      final ctl1 = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      );
      final out1 = await cropSquareToPng(grad, ctl1);

      final ctl2 = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      )..zoomBy(2.0);
      final out2 = await cropSquareToPng(grad, ctl2);

      final p1 = await _pixelAt(out1!, 40, 256);
      final p2 = await _pixelAt(out2!, 40, 256);
      // 放大后同一输出点对应的原图更靠左（x 更小 ⇒ 更暗），灰阶应不同。
      expect(p1.r != p2.r || p1.g != p2.g || p1.b != p2.b, isTrue,
          reason: '放大应改变取景框边缘像素来源（渐变图灰阶应变）');
    });

    test('平移后取景框中心像素改变（真的平移了）', () async {
      final base = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      );
      // 先放大到 2 倍（否则 1 倍无空隙、平移被夹回 0）。
      base.zoomBy(2.0);
      final outA = await cropSquareToPng(quad, base);
      final centerA = await _pixelAt(outA!, 256, 256);

      final moved = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      )..zoomBy(2.0);
      moved.panBy(const Offset(-80, -80)); // 往左上拖
      final outB = await cropSquareToPng(quad, moved);
      final centerB = await _pixelAt(outB!, 256, 256);

      final same = (centerA.r == centerB.r) &&
          (centerA.g == centerB.g) &&
          (centerA.b == centerB.b);
      expect(same, isFalse, reason: '平移后取景框中心应取到不同的原图区域');
    });

    test('非图片字节返回 null', () async {
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      );
      final out = await cropSquareToPng(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
        ctl,
      );
      expect(out, isNull);
    });
  });

  group('AvatarCropController 夹紧 / 边界', () {
    test('scale=1 时强平移被夹回（不露空）', () {
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      );
      ctl.panBy(const Offset(500, 500));
      expect(ctl.offset, Offset.zero,
          reason: '1 倍时图正好铺满取景框，任何平移都该被夹回 0');
    });

    test('放大后平移有上限：不超过 (显示边长-取景框)/2', () {
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      )..zoomBy(2.0);
      // 600×600 cover 到 300 取景框：基准 coverScale=0.5 ⇒ 1 倍显示 300，
      // 2 倍显示 600。可平移范围 = (600-300)/2 = 150。
      ctl.panBy(const Offset(9999, 9999));
      expect(ctl.offset.dx, closeTo(150, 0.5));
      expect(ctl.offset.dy, closeTo(150, 0.5));
    });

    test('zoomBy 把 scale 夹在 [1, 6]', () {
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      );
      ctl.zoomBy(0.1); // 想缩到 0.1 倍
      expect(ctl.scale, 1.0, reason: '最小 1 倍（不能比铺满更小）');
      ctl.zoomBy(100); // 想放到 100 倍
      expect(ctl.scale, AvatarCropController.maxScale,
          reason: '最大 ${AvatarCropController.maxScale} 倍');
    });

    test('reset 回到 1 倍居中', () {
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 600,
        imageHeight: 600,
      )
        ..zoomBy(3.0)
        ..panBy(const Offset(20, 20));
      ctl.reset();
      expect(ctl.scale, 1.0);
      expect(ctl.offset, Offset.zero);
    });

    test('横图 cover：1 倍时图片高度铺满、宽度溢出（长边被裁）', () {
      // 1200×600 横图 cover 到 300 正方形：coverScale = max(300/1200, 300/600)=0.5。
      // 显示尺寸 = 600×300 ⇒ 高正好铺满、宽 600 溢出。
      final ctl = AvatarCropController(
        viewportSide: 300,
        imageWidth: 1200,
        imageHeight: 600,
      );
      final rect = ctl.imageRectOnScreen();
      expect(rect.height, closeTo(300, 0.5), reason: '高度铺满');
      expect(rect.width, closeTo(600, 0.5), reason: '宽度溢出（横图左右被裁）');
      expect(rect.top, closeTo(0, 0.5));
      expect(rect.left, closeTo(-150, 0.5));
    });
  });
}
