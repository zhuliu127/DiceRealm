// ============================================================
// widgets/avatar_cropper.dart — 头像圆形缩放裁切（类似微信 / QQ 上传头像）
//
// 三件事，一个文件：
//   ① [cropSquareToPng]：**纯函数**，把「原图字节 + 变换状态」渲成一张
//      正方形 PNG（最终落盘再由 AvatarStore 缩到 512）。不碰文件系统、
//      不碰平台通道，可直接喂字节做单测。
//   ② [AvatarCropController]：取景的纯数据（缩放倍数 + 平移偏移），
//      以及把「屏幕手势」映射成「图片变换」的数学（夹紧边界，保证
//      圆形取景框永远被图覆盖，不会露出空白角）。
//   ③ [AvatarCropScreen]：全屏预览 + 圆形取景框 + 双指缩放 / 拖动 +
//      取消 / 确定。确定时用 ① + ② 的当前状态产出裁切后的字节。
//
// ★ 零新增依赖：裁切只用 `dart:ui`（Canvas + PictureRecorder + 缩放 +
//   PNG 编码），与 avatar_store.dart 同一套路。**不引 image / crop_your_image**。
//
// ★ 为什么裁切要抽成纯函数 + 控制器：屏幕手势是平台通道 + 帧驱动的，
//   widget 测试跑在 fake-async 区域里 `toImage()` 的 Future 永不完成；
//   把数学与渲帧拆出来，几何 / 夹紧 / 输出尺寸都能用普通 test 逐字节验，
//   屏幕只负责把 GestureDetector 接到控制器上。
// ============================================================

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// 头像最终落盘的边长（像素）。圆形预览按这个边长出图即可，够清晰。
const int kAvatarCropOutputSide = 512;

/// 裁切后的正方形 PNG 输出边长上限（默认 512）。
/// 圆形取景框是正方形视口的内切圆，所以最终出图是**正方形**，落盘时
/// AvatarStore 还会再按 maxSide 兜一次底（已经 ≤512 就不会再缩）。

/// 取景状态：图片相对取景框的缩放（≥1）与平移（屏幕像素）。
///
/// 坐标系约定：取景框是边长 [viewportSide] 的正方形；图片按 `BoxFit.cover`
/// 铺满取景框后，再乘 [scale]、平移 [offset]（像素）。这样「scale=1、
/// offset=0」就是铺满、居中、无裁切的最小状态（此时正好填满取景框）。
class AvatarCropController {
  AvatarCropController({
    required this.viewportSide,
    required this.imageWidth,
    required this.imageHeight,
  })  : assert(viewportSide > 0),
        assert(imageWidth > 0 && imageHeight > 0);

  /// 取景框（正方形）边长，屏幕像素。
  final double viewportSide;

  /// 原图像素尺寸（决定 cover 的基准缩放）。
  final double imageWidth;
  final double imageHeight;

  double _scale = 1.0;
  Offset _offset = Offset.zero;

  double get scale => _scale;
  Offset get offset => _offset;

  /// 最大缩放倍数：够放大看清纹理，又不至于糊成马赛克。
  static const double maxScale = 6.0;

  /// cover 基准：让图完整盖住正方形取景框所需的最小缩放（相对原图像素）。
  /// 长边方向的缩放取短板，保证短边也铺满。
  double get _coverScale =>
      math.max(viewportSide / imageWidth, viewportSide / imageHeight);

  /// 图片在屏幕上的实际边长（乘了 cover 与用户缩放）。
  double get _displayedW => imageWidth * _coverScale * _scale;
  double get _displayedH => imageHeight * _coverScale * _scale;

  /// 把平移夹在「图片边缘不离开取景框」的范围内：每个方向能多的位移
  /// = (显示边长 − 取景框边长) / 2，为负则说明该方向还有空隙（取 0）。
  Offset _clamp(Offset raw) {
    final maxX = math.max(0.0, (_displayedW - viewportSide) / 2);
    final maxY = math.max(0.0, (_displayedH - viewportSide) / 2);
    return Offset(
      raw.dx.clamp(-maxX, maxX),
      raw.dy.clamp(-maxY, maxY),
    );
  }

  /// 双指缩放：以 [focal]（相对取景框中心）为锚点放大 / 缩小，并重新夹紧。
  void zoomBy(double factor, {Offset focal = Offset.zero}) {
    final next = (_scale * factor).clamp(1.0, maxScale);
    // 以焦点为锚：图片上「焦点处」的那个点缩放前后应重合。简化处理——
    // 先把平移按缩放比例反推，再叠加焦点补偿，最后夹紧。
    final ratio = next / _scale;
    final newOffset = (Offset.zero - focal) * ratio + focal + _offset * ratio;
    _scale = next;
    _offset = _clamp(newOffset);
  }

  /// 单指拖动：整体平移并夹紧。
  void panBy(Offset delta) {
    _offset = _clamp(_offset + delta);
  }

  /// 复位（1 倍、居中）。
  void reset() {
    _scale = 1.0;
    _offset = Offset.zero;
  }

  /// 图片在屏幕上的绘制矩形（取景框中心为原点，左上加 offset 再减半边长）。
  Rect imageRectOnScreen() {
    final w = _displayedW;
    final h = _displayedH;
    final left = viewportSide / 2 + _offset.dx - w / 2;
    final top = viewportSide / 2 + _offset.dy - h / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  /// 换算到「输出正方形」的像素坐标：取景框边长 [outputSide] 对应 viewportSide。
  double get _pxPerScreen => kAvatarCropOutputSide / viewportSide;

  /// 用纯 Canvas 把当前取景状态渲成一张正方形 PNG。
  ///
  /// 做法：把画布缩放到 outputSide/viewportSide，平移使取景框左上到画布原点，
  /// 再按 imageRectOnScreen 把原图画到对应位置；取景框外自然被裁掉。圆形
  /// 裁切在显示侧用 ClipOval 呈现，但**存盘保留正方形**（圆外像素填主背景，
  /// 这样即使某个显示点没套 ClipOval 也不会漏出原图零碎像素——稳妥）。
  ///
  /// [image] 必须是已经解码好的 ui.Image（调用方负责 decoded 与 dispose）。
  Future<Uint8List?> renderCroppedPng(ui.Image image) async {
    final side = kAvatarCropOutputSide;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // 背景：圆外的像素填主题底色，避免透明像素在个别渲染路径变黑边。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..color = Palette.surface,
    );
    // 把屏幕坐标映射到输出像素坐标。
    final s = _pxPerScreen;
    final imgRectScreen = imageRectOnScreen();
    final dst = Rect.fromLTWH(
      imgRectScreen.left * s,
      imgRectScreen.top * s,
      imgRectScreen.width * s,
      imgRectScreen.height * s,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    // 圆形遮罩：圆外一律还原成主题底色（干净的头像圆）。
    final center = Offset(side / 2, side / 2);
    final r = side / 2;
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble())),
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawPath(mask, Paint()..color = Palette.surface);
    final picture = recorder.endRecording();
    final out = await picture.toImage(side, side);
    picture.dispose();
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      out.dispose();
    }
  }
}

/// 直接对「原图字节」做裁切渲染的纯函数封装（解码 → 渲 → 释放）。
///
/// 单测友好：喂一张 PNG 字节 + 期望的缩放 / 平移，读回输出 PNG 验尺寸与像素。
/// [controller] 需已按取景框尺寸建好并设好 scale/offset（用 zoomBy/panBy）。
Future<Uint8List?> cropSquareToPng(
  Uint8List srcBytes,
  AvatarCropController controller,
) async {
  ui.Image? image;
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(srcBytes);
    final frame = await codec.getNextFrame();
    image = frame.image;
    return await controller.renderCroppedPng(image);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// 全屏圆形裁切界面（类似微信 / QQ 换头像）：双指缩放、单指拖动、确定裁切。
///
/// 用法：`final cropped = await Navigator.push<Uint8List>(...)` 打开它，
/// 确定返回裁切后的 PNG 字节，取消返回 null。挑图与落盘仍在调用方。
///
/// ★ 解码失败（不是图片）直接返回 null，不进入界面 —— 与选择器一致地把
///   坏图挡在门外。
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.srcBytes});

  final Uint8List srcBytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  // 手势起始态（用于 onScaleStart 记基准，增量式更新）。
  double _startScale = 1.0;
  Offset _startFocal = Offset.zero;

  AvatarCropController? _ctl;
  ui.Image? _image;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.srcBytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        codec.dispose();
        return;
      }
      setState(() => _image = frame.image);
      codec.dispose();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails d) {
    final ctl = _ctl;
    if (ctl == null) return;
    _startScale = ctl.scale;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final ctl = _ctl;
    if (ctl == null) return;
    // 缩放：相对起始倍数换算成增量倍数。
    if (d.scale != 1.0 && _startScale > 0) {
      final factor = (d.scale * _startScale) / ctl.scale;
      ctl.zoomBy(factor);
    }
    // 平移：用 focalPoint 增量（同时覆盖单指拖动与双指移动）。
    ctl.panBy(d.focalPoint - _startFocal);
    _startFocal = d.focalPoint;
    setState(() {});
  }

  Future<void> _confirm() async {
    final ctl = _ctl;
    final image = _image;
    if (ctl == null || image == null || _busy) return;
    setState(() => _busy = true);
    try {
      final out = await ctl.renderCroppedPng(image);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('调整头像'),
        leading: IconButton(
          key: const Key('avatar_crop_cancel'),
          icon: const Icon(Icons.close),
          tooltip: '取消',
          onPressed: _busy ? null : () => Navigator.of(context).pop(null),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildViewport()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildViewport() {
    if (_failed) {
      return const Center(
        child: Text('这张图读不出来，换一张试试', style: TextStyle(color: Colors.white70)),
      );
    }
    final image = _image;
    if (image == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 取景框边长：取可用区域短边的 ~86%，留一圈暗色边距便于看清圆。
        final side = math.min(constraints.maxWidth, constraints.maxHeight) * 0.86;
        // 控制器按取景框尺寸与图像尺寸建一次（尺寸变了重建、保留状态）。
        final ctl = _ctl;
        if (ctl == null ||
            ctl.viewportSide != side ||
            ctl.imageWidth != image.width.toDouble() ||
            ctl.imageHeight != image.height.toDouble()) {
          final fresh = AvatarCropController(
            viewportSide: side,
            imageWidth: image.width.toDouble(),
            imageHeight: image.height.toDouble(),
          );
          // 尽量保留用户已经调好的缩放/位移（换屏 / 旋转时不重置）。
          if (ctl != null) {
            fresh.zoomBy(ctl.scale);
            fresh.panBy(ctl.offset);
          }
          _ctl = fresh;
        }
        final active = _ctl!;
        final rect = active.imageRectOnScreen();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: Center(
            child: SizedBox(
              width: side,
              height: side,
              child: ClipRect(
                child: Stack(
                  children: <Widget>[
                    // 图：把原图按控制器算出的屏幕矩形摆放（cover + 缩放 + 平移）。
                    Positioned.fromRect(
                      rect: rect,
                      child: RawImage(
                        image: image,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    // 圆形取景遮罩：圆外压暗（用四块遮罩拼一个圆洞）。
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CircleMaskPainter(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '双指缩放 · 拖动调整位置',
                style: TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ),
            TextButton(
              key: const Key('avatar_crop_reset'),
              onPressed: _busy
                  ? null
                  : () {
                      _ctl?.reset();
                      setState(() {});
                    },
              child: const Text('复位', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('avatar_crop_confirm'),
              onPressed: (_busy || _image == null || _failed) ? null : _confirm,
              style: FilledButton.styleFrom(backgroundColor: Palette.gold),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆形取景遮罩：圆外半透明黑，圆内透明；再描一圈白色细环提示边界。
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final circle = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    final full = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final outside = Path.combine(PathOperation.difference, full, circle);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _CircleMaskPainter oldDelegate) => false;
}
