// ============================================================
// room_image_picker.dart — 素材 / 头像图片端口（Q-P5-2）
//
// 零新增依赖：`file_picker: ^13.3.2` 已在 `pubspec.yaml:39`
// （`lib/ui/card_transfer_io.dart` 正在用），**不引 image_picker**。
// 产出 base64 dataURL（`data:image/<ext>;base64,...`），与旧版
// `FileReader.readAsDataURL` 同形状，可直接进 `asset.add` 的载荷。
//
// ★ 与旧版 API 的差异（实读 file_picker 13.3.2 源码后按真实签名落地）：
//   设计 §0.3 写的是 `FilePicker.platform.pickFiles(withData: true)`，
//   那是 file_picker 8.x 的形态；13.3.2 已改为静态方法
//   `FilePicker.pickFile(type: FileType.image)` + `PlatformFile.readAsBytes()`
//   （项目里 `card_transfer_io.dart:75-84` 的注释也确认了这一点）。
//   `withData` 参数在 13.x 不存在，硬写会编译失败 —— 故按真实 API 落地，
//   语义完全等价（仍是「选一张图 → 拿字节 → base64」），依赖一行不改。
//
// ★ 全局可替换实例：widget 测试在 fake-async 区域里平台通道永不返回，
//   必须能换成 `FakeImagePicker`（范式同 `cardTransferIo`）。
// ============================================================

import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// 图片选择端口（§3.9）。返回 dataURL 或 null（用户取消 / 超限）。
abstract class ImagePickerPort {
  Future<String?> pickImage({int maxBytes = 2 * 1024 * 1024});
}

/// 全局可替换实例。测试里 `roomImagePicker = FakeImagePicker(...)`，
/// 用完在 tearDown 还原（与 `cardTransferIo` 同一套路）。
ImagePickerPort roomImagePicker = const FilePickerImagePicker();

/// 生产实现：基于已有的 `file_picker`。
class FilePickerImagePicker implements ImagePickerPort {
  const FilePickerImagePicker();

  @override
  Future<String?> pickImage({int maxBytes = 2 * 1024 * 1024}) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择图片素材',
      type: FileType.image,
    );
    if (picked == null) return null; // 用户取消
    final bytes = await picked.readAsBytes();
    if (maxBytes > 0 && bytes.length > maxBytes) return null; // S9：2MB 上限
    final ext = _mimeExt(picked.extension);
    return 'data:image/$ext;base64,${base64Encode(bytes)}';
  }

  /// 扩展名 → dataURL 的 mime 子类型。未知一律按 png（1×1 假图也是 png）。
  static String _mimeExt(String? raw) {
    final e = (raw ?? '').toLowerCase();
    switch (e) {
      case 'jpg':
      case 'jpeg':
      case 'jpe':
        return 'jpeg';
      case 'gif':
        return 'gif';
      case 'webp':
        return 'webp';
      case 'bmp':
        return 'bmp';
      case 'svg':
        return 'svg+xml';
      default:
        return 'png';
    }
  }
}
