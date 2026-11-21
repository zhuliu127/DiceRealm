// ============================================================
// avatar_store.dart — 角色头像的本地存储（落盘，不塞 JSON）
//
// 为什么落盘而不是 base64 进角色卡：
//   一张手机照片 3-8MB，base64 还要涨 33%，`characters.json` 里十几张卡就会
//   变成几十 MB —— 每次保存都要全量重写这个文件，卡列表也就再也读不快了。
//   所以图片存在**应用私有目录**，角色卡里只留**相对路径**（`avatars/<cardId>.png`）。
//
// 目录布局（与 `character_repo.dart` 同根，跟着「角色档案」走）：
//   <应用文档目录>/dice_realm/
//     ├─ characters.json
//     └─ avatars/<cardId>.png        ← 本文件负责的
//
// 为什么统一存 PNG：`dart:ui` 只提供 PNG 编码（`ImageByteFormat.png`），
//   不引第三方图片库就只能写 PNG。512px 的 PNG 通常在 150-400KB，可接受；
//   文件名固定 `.png`，这样「扩展名与实际字节一致」，不会出现 jpg 里装 png。
//
// ★ 注入点两条（与 `cardTransferIo` 同一套路，理由也相同）：
//   · [avatarStore]：测试把根目录换到 `Directory.systemTemp` 的临时目录，
//     不碰 path_provider 的平台通道；
//   · [avatarImageImporter]：「选图 → 落盘」这一步要走 `dart:ui` 解码，
//     而 widget 测试跑在 fake-async 区域里，引擎回调的 Future 不会完成 ——
//     widget 级用例只验「选完之后字段变了」，编解码由普通 test 覆盖。
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// 「字节 → 相对路径」的导入函数（可注入）
typedef AvatarImageImporter = Future<String?> Function(
  Uint8List bytes,
  String cardId,
);

/// 头像文件存储。
class AvatarStore {
  AvatarStore({String? rootOverride}) : _baseOverride = rootOverride;

  /// 相对路径前缀（角色卡里存的就是 `<relativeDir>/<cardId>.png`）
  static const String relativeDir = 'avatars';

  /// 缩放上限：最长边不超过这个像素数
  static const int maxSide = 512;

  String? _baseOverride;
  Directory? _base;

  /// 测试用：把落盘根目录换到临时目录（传 null 还原成平台文档目录）。
  set rootOverride(String? dir) {
    _baseOverride = dir;
    _base = null;
  }

  /// 已解析的根目录（尚未解析时为 null）。
  String? get resolvedBasePath => _base?.path;

  /// 同步可用的根目录：测试注入的覆盖值立刻就可用；生产要等 [baseDir] 解析过
  /// 一次（首帧走异步，之后的每一帧都能同步拼路径）。
  String? get syncBasePath => _base?.path ?? _baseOverride;

  /// 同步版 provider：只做一次 `existsSync`（本地小文件，代价可忽略）。
  ///
  /// 为什么需要它：widget 测试跑在 fake-async 区域里，真实 I/O 的 Future
  /// 不会完成 —— 头像这种「列表里几十行各查一次」的读盘必须有一条同步路径，
  /// 否则整屏都显示不出图，用例只能靠 `runAsync` 打补丁。
  /// 根目录未知（生产首帧）时返回 null，调用方再走异步。
  ImageProvider? providerForSync(String? relPath) {
    final rel = localAvatarRel(relPath);
    final base = syncBasePath;
    if (rel == null || base == null) return null;
    try {
      final sep = Platform.pathSeparator;
      final file = File('$base$sep${rel.split('/').join(sep)}');
      return file.existsSync() ? FileImage(file) : null;
    } catch (_) {
      return null;
    }
  }

  /// 根目录：测试覆盖值 > `<应用文档目录>/dice_realm`。
  Future<Directory> baseDir() async {
    final cached = _base;
    if (cached != null) return cached;
    final override = _baseOverride;
    Directory dir;
    if (override != null) {
      dir = Directory(override);
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory(
        '${docs.path}${Platform.pathSeparator}dice_realm',
      );
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return _base = dir;
  }

  /// 文件名的安全化：只留字母 / 数字 / `-` / `_`，其余一律 `_`。
  /// （cardId 本来是 8 位小写字母数字，这里是给「测试里传任意 id」兜底，
  ///   也顺手挡掉带着 `../` 的路径穿越。）
  static String safeName(String cardId) {
    final raw = cardId.trim();
    if (raw.isEmpty) return 'unnamed';
    final out = StringBuffer();
    for (final unit in raw.codeUnits) {
      final ok = (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5A) ||
          (unit >= 0x61 && unit <= 0x7A) ||
          unit == 0x2D ||
          unit == 0x5F;
      out.writeCharCode(ok ? unit : 0x5F);
    }
    return out.toString();
  }

  /// 把图片字节缩放后写入 `<根>/avatars/<cardId>.png`，返回相对路径。
  ///
  /// 失败（不是图片 / 解码失败 / 写不进去）返回 null —— 调用方据此提示，
  /// 绝不把一张坏图写成一个「有头像」的假状态。
  Future<String?> importBytes(Uint8List bytes, String cardId) async {
    if (bytes.isEmpty) return null;
    final png = await scaleToPng(bytes);
    if (png == null || png.isEmpty) return null;
    try {
      final base = await baseDir();
      final dir = Directory('${base.path}${Platform.pathSeparator}$relativeDir');
      if (!await dir.exists()) await dir.create(recursive: true);
      final name = '${safeName(cardId)}.png';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(png, flush: true);
      return '$relativeDir/$name';
    } catch (_) {
      return null;
    }
  }

  /// 从本地文件导入（测试 / 桌面拖进来的路径都走这条）。
  Future<String?> importFrom(File src, String cardId) async {
    try {
      if (!await src.exists()) return null;
      return await importBytes(await src.readAsBytes(), cardId);
    } catch (_) {
      return null;
    }
  }

  /// 删除头像文件（文件不在也算成功 —— 幂等）。
  Future<void> remove(String? relPath) async {
    final rel = localAvatarRel(relPath);
    if (rel == null) return;
    try {
      final file = await _resolve(rel);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删不掉不影响正确性：显示侧会按「文件不存在」退化
    }
  }

  /// 相对路径 → 真实文件；文件不存在 / 路径非法 → null。
  Future<File?> fileOf(String? relPath) async {
    final rel = localAvatarRel(relPath);
    if (rel == null) return null;
    try {
      final file = await _resolve(rel);
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// 显示用 ImageProvider；拿不到文件 → null（调用方退化成首字圆点）。
  Future<ImageProvider?> providerFor(String? relPath) async {
    final file = await fileOf(relPath);
    return file == null ? null : FileImage(file);
  }

  Future<File> _resolve(String rel) async {
    final base = await baseDir();
    final sep = Platform.pathSeparator;
    final tail = rel.split('/').join(sep);
    return File('${base.path}$sep$tail');
  }

  /// 把任意图片字节缩到最长边 ≤ [maxSide]，统一重编码为 PNG 返回。
  ///
  /// 已经足够小的图也会重编码一次：源文件可能是偏门格式（bmp / webp），
  /// 存成 `.png` 就必须真的是 PNG，否则某些平台的解码器会拒绝。
  Future<Uint8List?> scaleToPng(Uint8List bytes, {int maxSide = maxSide}) =>
      decodeScaledPng(bytes, maxSide: maxSide);

  /// 纯函数版（不碰文件系统，方便单测直接喂字节）。
  static Future<Uint8List?> decodeScaledPng(
    Uint8List bytes, {
    required int maxSide,
  }) async {
    ui.Image? probe;
    ui.Codec? probeCodec;
    try {
      probeCodec = await ui.instantiateImageCodec(bytes);
      final probeFrame = await probeCodec.getNextFrame();
      probe = probeFrame.image;
      final w = probe.width;
      final h = probe.height;
      int? targetW;
      int? targetH;
      if (maxSide > 0 && (w > maxSide || h > maxSide)) {
        // 只给一边，另一边由引擎按比例算 —— 不会把图拉变形
        if (w >= h) {
          targetW = maxSide;
        } else {
          targetH = maxSide;
        }
      }
      if (targetW == null && targetH == null) {
        final data = await probe.toByteData(format: ui.ImageByteFormat.png);
        return _bytesOf(data);
      }

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      return _bytesOf(data);
    } catch (_) {
      return null;
    } finally {
      probe?.dispose();
      probeCodec?.dispose();
    }
  }

  static Uint8List? _bytesOf(ByteData? data) {
    if (data == null) return null;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// 全局实例（测试可 `avatarStore.rootOverride = tempDir.path`）。
AvatarStore avatarStore = AvatarStore();

/// 「选完图 → 落盘」的默认实现（widget 测试里换成同步假实现）。
AvatarImageImporter avatarImageImporter =
    (Uint8List bytes, String cardId) => avatarStore.importBytes(bytes, cardId);

/// 把卡片 / 成员字段里的值判成「本机头像文件的相对路径」。
///
/// 老卡没有 `avatar` 字段（null）、自动头像（`data:image/svg+xml,...`）、
/// 云端 URL、空串一律返回 null —— 这些都不该当成文件路径去读盘。
String? localAvatarRel(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final lower = s.toLowerCase();
  if (lower.startsWith('data:') ||
      lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('blob:') ||
      lower.startsWith('file:')) {
    return null;
  }
  // 绝对路径（历史存档 / 桌面调试）不当相对路径用：换设备直接失效，
  // 与其读到一个"碰巧存在"的文件，不如老老实实退化成首字圆点。
  if (s.startsWith('/') || s.contains(':\\') || s.contains(':/')) return null;
  final parts = s.split('/');
  for (final p in parts) {
    if (p == '..' || p == '.') return null;
  }
  return s;
}
