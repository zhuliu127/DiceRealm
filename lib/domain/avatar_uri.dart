// ============================================================
// domain/avatar_uri.dart — 头像 dataURI 的**纯字符串口径**（P10 第 2 期 A）
//
// 为什么单独一个文件而不是塞进 `repo/avatar_thumb.dart`：
//   · 缩略图**生成**要用引擎的 2D 画布（解码 / 裁剪 / PNG 编码），只能放 repo 层；
//   · 但「这条头像值能不能进房间广播」是一条**纯字符串判据**，domain 与
//     view 层（`ui/room/view/feed_view.dart`）都要用同一份规则 ——
//     把判据放 repo 会把引擎依赖拖进纯 Dart 的视图派生层。
//   所以：判据在 domain（只用 SDK 的字符串 / 字节能力，零引擎、零文件系统），
//   编解码在 repo。
//
// 口径逐字对齐老 APP（`core/room-model.js:7306`、v2.13.7）：
//   `avatar` 必须是 `/^data:image\/(png|jpe?g|webp);base64,/` 且长度 ≤ 20000，
//   否则置空 —— 老 APP 卡这个上限是为了不把 WS 帧撑爆（原图可能几 MB）。
// ============================================================

import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

/// 缩略 dataURI 的字符数上限（与老 APP `sanitizeSheet` 的 20000 一致）。
const int kAvatarThumbMaxChars = 20000;

/// 缩略图边长（与老 APP 调用处一致：64）。
const int kAvatarThumbSize = 64;

final RegExp _kRoomAvatarRe =
    RegExp(r'^data:image/(png|jpe?g|webp);base64,', caseSensitive: false);

/// 「这是一条可以进房间广播的头像 dataURI」的判据。
///
/// 正则 + 长度两条全过才返回原串，否则返回**空串**（调用方据此「不带这个
/// 键」，而不是带一个空串去占广播体积）。
String roomAvatarDataUri(Object? raw) {
  if (raw is! String) return '';
  final s = raw.trim();
  if (s.isEmpty) return '';
  if (!_kRoomAvatarRe.hasMatch(s)) return '';
  if (s.length > kAvatarThumbMaxChars) return '';
  return s;
}

/// dataURI → 字节（**同步**）。不是 `data:image/*;base64,` 形态 → null。
///
/// 同步是关键：`AvatarThumb` 在列表里几十行各解一次，不能每行挂一个 Future
/// （widget 测试跑在 fake-async 区域里，真实 I/O 的 Future 永不完成）。
Uint8List? avatarDataUriBytes(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  final comma = s.indexOf(',');
  if (comma <= 0) return null;
  final head = s.substring(0, comma).toLowerCase();
  if (!head.startsWith('data:image/') || !head.contains('base64')) return null;
  try {
    final out = base64Decode(s.substring(comma + 1));
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}
