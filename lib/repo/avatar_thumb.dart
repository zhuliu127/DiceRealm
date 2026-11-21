// ============================================================
// repo/avatar_thumb.dart — 头像 → **跨设备缩略 dataURI**（P10 第 2 期 A）
//
// 为什么需要这一层（用户需求原文：「显示头像缩略图让游戏中的玩家栏里面也
// 显示头像」）：
//   头像文件落在**本机私有目录**（`avatars/<cardId>.png`，见 `avatar_store.dart`），
//   角色卡里只存相对路径。房间协议不传文件，于是别人设备上那条相对路径
//   指向的文件根本不存在 → 远端玩家只能退化成首字圆点。
//   老 APP（v2.13.7）的解法是把头像压成 64px 缩略图，随公开 sheet 字段广播。
//   这里就是那一刻的 Flutter 版。
//
// ★ 与老 APP 的唯一实质差异（如实记录，不假装一样）：
//   老 APP 用 `canvas.toDataURL('image/jpeg', 0.72)`（64px JPEG ≈ 2-4KB）；
//   Flutter 的 `ui.Image.toByteData()` **只有 rawRgba 与 png** 两种格式，
//   没有 JPEG 编码器，而本批**不许改 `pubspec.yaml`**（不能引 `image` 包）。
//   所以这里输出 PNG。64×64 的 PNG base64 后实测 1-4K 字符（图形类头像往往
//   只有 1-2K），远低于老 APP 的 20000 字符上限；真超了会依次降到 48 / 32。
//
// ★ 裁剪口径与老 APP 逐行一致（`room-ui.js#avatarThumbDataUrl`）：
//     side = min(w, h)
//     sx = (w - side) / 2 , sy = (h - side) / 2   ← **短边居中裁正方形**
//     再等比缩到 size × size
//   只接受 `data:image/` 或本机相对路径；解码失败 / 无头像 → 空串。
//
// ★ 纯 `dart:ui`：不碰 `package:flutter`，也不进 `lib/domain/**`（domain 必须
//   保持零 UI / 零 IO 的纯度）。这一层归 repo。
//
// ★ 可注入（铁律 T1）：widget 测试跑在 fake-async 区域里，真实文件 I/O 与
//   引擎解码的 Future 永远不会完成。所以对外只暴露一个可替换的
//   [avatarThumbEncoder]，测试换成同步返回预置字符串的替身即可。
// ============================================================

import 'dart:convert' show base64Encode;
import 'dart:typed_data';

import 'dart:ui' as ui;

import '../domain/avatar_uri.dart';
import 'avatar_store.dart' show avatarStore, localAvatarRel;

// 口径常量与纯字符串判据在 domain（`domain/avatar_uri.dart`）—— 视图层也要用
// 同一份规则，但不该被 `dart:ui` 拖下水。这里原样转出，调用方只需 import 本文件。
export '../domain/avatar_uri.dart'
    show kAvatarThumbMaxChars, kAvatarThumbSize, roomAvatarDataUri, avatarDataUriBytes;

/// 体积超限时的降级阶梯（按顺序试，第一个不超限的胜出）。
const List<int> kAvatarThumbFallbacks = <int>[64, 48, 32];

/// 「这一行该显示哪个头像值」：本机相对路径原样返回，合法 dataURI 原样返回。
///
/// 供显示侧用（[AvatarThumb] 自己再分派：相对路径走文件、dataURI 走内存）。
/// 其它（自动 SVG 头像、http URL、绝对路径、空串）→ null。
String? avatarValueOf(Object? raw) {
  final rel = localAvatarRel(raw);
  if (rel != null) return rel;
  final uri = roomAvatarDataUri(raw);
  return uri.isEmpty ? null : uri;
}

/// 把任意图片字节裁成正方形、缩到 [size]，再编码成 PNG dataURI。
///
/// 顺序：短边居中裁正方形 → 等比缩到 size×size → PNG → base64。
/// 超 [maxChars] 就按 [kAvatarThumbFallbacks] 逐级降尺寸，全都超限 → 空串。
/// 解码失败 / 空字节 → 空串（绝不抛、绝不返回半截数据）。
Future<String> encodeAvatarThumb(
  Uint8List bytes, {
  int size = kAvatarThumbSize,
  int maxChars = kAvatarThumbMaxChars,
}) async {
  if (bytes.isEmpty) return '';
  final ladder = <int>[
    for (final s in kAvatarThumbFallbacks)
      if (s <= size) s,
  ];
  if (ladder.isEmpty) ladder.add(size);
  for (final side in ladder) {
    final png = await _squarePng(bytes, side);
    if (png == null || png.isEmpty) return '';
    final uri = 'data:image/png;base64,${base64Encode(png)}';
    if (uri.length <= maxChars) return uri;
  }
  return '';
}

/// 取一张图的「本机相对路径 → 缩略 dataURI」。
///
/// 输入可以是：
///   · 本机相对路径（`avatars/<cardId>.png`）→ 读 `avatarStore` 的绝对路径；
///   · 已经是 `data:image/*;base64,` 的 dataURI → 直接解字节（老卡 / 测试）。
/// 无头像 / 文件不存在 / 解码失败 → 空串。
Future<String> avatarThumbOf(Object? raw) async {
  final value = raw is String ? raw.trim() : '';
  if (value.isEmpty) return '';
  final inline = avatarDataUriBytes(value);
  if (inline != null) return encodeAvatarThumb(inline);

  final rel = localAvatarRel(value);
  if (rel == null) return '';
  try {
    final file = await avatarStore.fileOf(rel);
    if (file == null) return '';
    final bytes = await file.readAsBytes();
    return await encodeAvatarThumb(bytes);
  } catch (_) {
    return '';
  }
}

/// 「头像值 → 缩略 dataURI」的可注入端口。
///
/// 默认实现 [avatarThumbOf] 会读盘 + 解码（真实异步）。widget 测试换成
/// 同步返回预置字符串的替身（例如 `(_) async => kTestThumbUri`），
/// 否则 fake-async 下 Future 永不完成、整条用例挂死。
typedef AvatarThumbEncoder = Future<String> Function(Object? raw);

/// 全局实例（测试在 `setUp/tearDown` 里替换与还原）。
AvatarThumbEncoder avatarThumbEncoder = avatarThumbOf;

// ------------------------------------------------------------
// 内部：短边居中裁正方形 + 缩放 + PNG
// ------------------------------------------------------------

/// 解码 → 居中裁正方形 → 缩到 [side] → PNG 字节。失败返回 null。
Future<Uint8List?> _squarePng(Uint8List bytes, int side) async {
  ui.Codec? codec;
  ui.Image? src;
  ui.Image? out;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    src = frame.image;
    final w = src.width;
    final h = src.height;
    if (w <= 0 || h <= 0) return null;
    // ★ 与老 APP 同口径：短边居中
    final edge = w < h ? w : h;
    final srcRect = ui.Rect.fromLTWH(
      (w - edge) / 2.0,
      (h - edge) / 2.0,
      edge.toDouble(),
      edge.toDouble(),
    );
    final dstRect = ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, dstRect);
    canvas.drawImageRect(
      src,
      srcRect,
      dstRect,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    out = await picture.toImage(side, side);
    picture.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  } finally {
    out?.dispose();
    src?.dispose();
    codec?.dispose();
  }
}
