// ============================================================
// widgets/avatar_picker.dart — 头像选择器 / 头像缩略图（P10）
//
// 三件事，一个文件：
//   ① [AvatarPicker]：圆形预览 + 「选择图片 / 更换」+「移除」；
//   ② [AvatarThumb]：按相对路径显示圆形缩略图，拿不到图就退化成首字圆点；
//   ③ [AvatarPickerPort]：「弹系统选图」这一层抽成端口，widget 测试可换假实现。
//
// ★ 零新增依赖：选图复用 `pubspec.yaml` 里已有的 `file_picker`（13.x 静态
//   方法 + `PlatformFile.readAsBytes()`），与 `ui/room/room_image_picker.dart`
//   完全同一套 API。**没有**引 `image_picker`。
//
// ★ 为什么「选图」要抽端口：文件选择是平台通道，widget 测试跑在 fake-async
//   区域里，通道的 Future 永远不会返回，整条用例会挂死（与 `cardTransferIo`
//   同一教训）。测试里换成 `FakeAvatarPicker` 即可。
//
// ★ 图片**不**进角色卡 JSON：选完走 `avatarImageImporter` 落盘，角色卡里只写
//   相对路径（见 `repo/avatar_store.dart`）。
// ============================================================

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/js_compat.dart' show asMap, jsStr;
import '../../repo/avatar_store.dart';
import '../../repo/avatar_thumb.dart' show avatarDataUriBytes;
import '../../repo/repo_scope.dart' show RepoScope;
import '../../theme.dart';
import 'avatar_cropper.dart';

/// 选图端口（返回原始字节；用户取消返回 null）。
abstract class AvatarPickerPort {
  Future<Uint8List?> pickImageBytes({String? title, int maxBytes});
}

/// 裁切端口：拿到原始字节后，弹裁切界面，返回裁切后的 PNG 字节
/// （用户取消返回 null）。抽成端口是为了 widget 测试能换成「直接返回原字节」
/// 的假实现 —— 真裁切要做引擎解码，fake-async 区域里 Future 不会完成。
typedef AvatarCropperPort = Future<Uint8List?> Function(
  BuildContext context,
  Uint8List bytes,
);

/// 默认裁切实现：打开全屏圆形裁切界面（[AvatarCropScreen]）。
Future<Uint8List?> defaultAvatarCropper(
  BuildContext context,
  Uint8List bytes,
) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute<Uint8List>(
      fullscreenDialog: true,
      builder: (BuildContext _) => AvatarCropScreen(srcBytes: bytes),
    ),
  );
}

/// 全局可替换裁切实例（测试用完在 tearDown 还原）。
AvatarCropperPort avatarCropper = defaultAvatarCropper;

/// 全局可替换实例（测试用完在 tearDown 还原）。
AvatarPickerPort avatarPicker = const FilePickerAvatarPicker();

/// 生产实现：`file_picker` 的图片选择器。
class FilePickerAvatarPicker implements AvatarPickerPort {
  const FilePickerAvatarPicker();

  /// 20MB：再大就不是「头像」了，解码也会把内存顶爆。
  static const int defaultMaxBytes = 20 * 1024 * 1024;

  @override
  Future<Uint8List?> pickImageBytes({
    String? title,
    int maxBytes = defaultMaxBytes,
  }) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: title ?? '选择头像图片',
      type: FileType.image,
    );
    if (picked == null) return null; // 用户取消
    final known = picked.lengthSync();
    if (maxBytes > 0 && known != null && known > maxBytes) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return null;
    if (maxBytes > 0 && bytes.length > maxBytes) return null;
    return bytes;
  }
}

/// 圆形头像缩略图：有图显示图，没图显示 [fallback]（默认首字圆点）。
///
/// ★ 三层优先级（P10 第 2 期 A；顺序即代码里的分支顺序）：
///   ① **本机相对路径** `avatars/<cardId>.png` → 走文件（`FileImage`，原图高清，
///      512px）。同一台设备上的自己 / 本地团成员走这条；
///   ② **`data:image/*;base64,` 缩略图** → 走内存（`MemoryImage`）。这是跨设备
///      的唯一来源：远端的自定义头像被压成 64px 缩略图随公开 sheet 广播过来，
///      他那条相对路径在你这台设备上根本不存在，只有这条能显示；
///   ③ 都没有（或文件丢了 / 解码失败）→ [fallback]，默认 `AvatarDot` 首字圆点。
///
/// ★ 为什么「本机路径」优先于 dataURI：同一个人的头像在本机有原图（512px），
///   dataURI 只是 64px 缩略图。先读文件能保住清晰度，不至于为了统一而下采样。
///
/// 读盘是异步的（要先解析应用目录），所以这里自己管一个 Future，只在
/// `relPath` 变化时重取 —— 不能用 `FutureBuilder` 现造 Future，否则每次
/// 重建都会新起一次读盘，列表里几十行会互相打架。
/// dataURI 分支是**同步**解码的：列表里几十行各解一次，不能每行挂 Future
/// （widget 测试跑在 fake-async 下，真实 I/O 的 Future 永不完成）。
class AvatarThumb extends StatefulWidget {
  const AvatarThumb({
    super.key,
    required this.relPath,
    required this.size,
    this.name = '',
    this.fallback,
    this.border = true,
    this.revision = 0,
  });

  /// 头像值：本机相对路径（`avatars/xxx.png`）或跨设备缩略 dataURI。
  /// null / 非法 → 一律走 [fallback]。字段名沿用 `relPath` 是为了不改动
  /// 既有调用点与测试；语义见类注释的三层优先级。
  final String? relPath;
  final double size;

  /// 没图时圆点里显示的首字（空 → `?`）
  final String name;

  /// 没图时的自定义占位（不传就用首字圆点，与房间的 `AvatarDot` 观感一致）
  final Widget? fallback;

  /// 是否画一圈avatar 边框
  final bool border;

  /// 刷新代次：路径不变但**内容被替换**（如「更换」上传了新图，仍写回同一个
  /// `avatars/<cardId>.png`）时，靠这个递增让缩略图强制重载 —— 仅比 relPath
  /// 变化就会漏刷新，且 FileImage 以路径为缓存键，不 evict 会读到旧字节。
  final int revision;

  @override
  State<AvatarThumb> createState() => _AvatarThumbState();
}

class _AvatarThumbState extends State<AvatarThumb> {
  ImageProvider? _provider;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AvatarThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relPath != widget.relPath ||
        oldWidget.revision != widget.revision) {
      _reload();
    }
  }

  void _reload() {
    final token = ++_token;
    // ★ 换了图 / 同路径覆盖写：先把旧 provider 从 ImageCache 里摘掉，
    //   否则 FileImage 以「路径」为缓存键，会继续吐旧字节。
    final old = _provider;
    if (old is FileImage) {
      imageCache.evict(old);
    }
    // ② dataURI：同步解字节，fake-async 下也立刻可用。
    final inline = avatarDataUriBytes(widget.relPath);
    if (inline != null) {
      _provider = MemoryImage(inline);
      return;
    }
    // ① 本机相对路径：走文件（高清）。
    final rel = localAvatarRel(widget.relPath);
    if (rel == null) {
      _provider = null;
      return;
    }
    // 根目录已知（测试注入 / 生产已解析过一次）→ 同步一次 stat 就够，
    // 列表里几十行不会各挂一个 Future。
    if (avatarStore.syncBasePath != null) {
      _provider = avatarStore.providerForSync(rel);
      return;
    }
    // 生产首帧：目录还没解析，先按「暂无图」渲染，读到再换成图片。
    _provider = null;
    avatarStore.providerFor(rel).then((ImageProvider? p) {
      if (!mounted || token != _token) return;
      if (p == null) return;
      setState(() => _provider = p);
    });
  }

  Widget _placeholder() {
    final custom = widget.fallback;
    if (custom != null) return custom;
    final trimmed = widget.name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Palette.surface3,
        shape: BoxShape.circle,
        border: widget.border ? Border.all(color: Palette.border) : null,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: widget.size * 0.42,
          color: Palette.textDim,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: _placeholder(),
      );
    }
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: widget.border
            ? Border.all(color: Palette.gold.withValues(alpha: 0.55))
            : null,
      ),
      child: ClipOval(
        child: Image(
          image: provider,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // 文件在「显示之后」被删 / 损坏：退回首字，不留一个报错方块
          errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
              _placeholder(),
        ),
      ),
    );
  }
}

/// 头像选择器：圆形预览 + 选择 / 更换 / 移除。
///
/// [keyPrefix] 决定三个稳定的 Key（测试与自动化都按名找）：
///   `<prefix>`（根）、`<prefix>_pick`、`<prefix>_clear`。
class AvatarPicker extends StatefulWidget {
  const AvatarPicker({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.name,
    required this.onChanged,
    this.cardId,
    this.size = 76,
    this.label = '头像',
    this.hint = '点「选择图片」从本机挑一张图（可裁成圆形显示）',
  });

  /// `basics_avatar` / `ai_avatar` / `random_avatar`
  final String keyPrefix;

  /// 当前头像相对路径（null / 空 = 没有头像）
  final String? value;

  /// 圆形里的首字（没图时显示）
  final String name;

  /// 改完回调：给了新路径，或清除时给 null
  final ValueChanged<String?> onChanged;

  /// 落盘文件名用的 id（向导里是草稿 id；AI / 随机页是页面自己的临时 id）
  final String? cardId;

  final double size;
  final String label;
  final String hint;

  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  bool _busy = false;

  /// 每次成功导入新图都 +1：即便写回同一个 `avatars/<cardId>.png`（路径不
  /// 变），也要让 [AvatarThumb] 重载并 evict 旧缓存，否则「更换」不生效。
  int _thumbRevision = 0;

  String? get _rel => localAvatarRel(widget.value);

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await avatarPicker.pickImageBytes(title: '选择${widget.label}图片');
      if (!mounted) return;
      if (bytes == null) return; // 用户取消：什么都不改
      // ★ 选图后先裁切（圆形缩放 / 拖动），用户取消裁切 = 放弃本次，不落盘。
      final cropped = await avatarCropper(context, bytes);
      if (!mounted) return;
      if (cropped == null) return;
      final rel = await avatarImageImporter(
        cropped,
        widget.cardId ?? widget.keyPrefix,
      );
      if (!mounted) return;
      if (rel == null) {
        _toast('这张图读不出来（可能不是常见图片格式），换一张试试');
        return;
      }
      // 路径可能与旧值相同（更换时写回同一个文件）—— 仍要 bump 代次，强制刷新。
      setState(() => _thumbRevision++);
      widget.onChanged(rel);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    if (_busy) return;
    widget.onChanged(null);
  }

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Palette.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final has = _rel != null;
    return Container(
      key: Key(widget.keyPrefix),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          AvatarThumb(
            key: Key('${widget.keyPrefix}_thumb'),
            relPath: _rel,
            size: widget.size,
            name: widget.name,
            revision: _thumbRevision,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: Key('${widget.keyPrefix}_pick'),
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.image_outlined, size: 16),
                      label: Text(has ? '更换' : '选择图片'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    if (has)
                      TextButton.icon(
                        key: Key('${widget.keyPrefix}_clear'),
                        onPressed: _busy ? null : _clear,
                        icon: const Icon(Icons.close, size: 15),
                        label: const Text('移除'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          foregroundColor: Palette.textDim,
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 房间成员行 / 名册行用：求这一行该显示哪个头像文件（**只返回本机相对路径**）。
///
/// 取数顺序（**只读卡片/成员自己的数据**，不猜全局状态）：
///   ① 成员角色卡摘要里的 `sheet.avatar`（同一台设备上的本地团能直接用）；
///   ② 摘要里没有 → 用 `member.charId` 到本机角色库里回查那张卡的
///      `raw.avatar`（`sanitizeSheet` 不搬这个字段的路径形态，所以这条几乎是
///      实际生效的那条；KP 与玩家在同一台设备上时都能命中）；
///   ③ 都没有 → null，显示首字圆点。
///
/// ★ 跨设备场景请用 [memberAvatarValue]（本函数看不到 `data:image/` 缩略图）。
String? memberAvatarRel(BuildContext context, Map<String, Object?> member) {
  final sheet = asMap(member['sheet']);
  // ★ 传原始值、不过 jsStr：`jsStr(null)` 是字符串 'null'（JS 语义）
  final fromSheet = localAvatarRel(sheet['avatar']);
  if (fromSheet != null) return fromSheet;

  final charId = jsStr(member['charId']).trim();
  if (charId.isEmpty) return null;
  final scope = context.getInheritedWidgetOfExactType<RepoScope>();
  final card = scope?.notifier?.get(charId);
  if (card == null) return null;
  return localAvatarRel(card.raw['avatar']);
}

/// 房间成员行 / 名册行用：求这一行该显示哪个头像值（本机路径**或** dataURI）。
///
/// 取数顺序（P10 第 2 期 A 的核心修复）：
///   ① 成员摘要里的 `sheet.avatar` 如果解析得出**本机文件且文件真的在** →
///      返回该相对路径（原图高清，同机成员走这条）；
///   ② 否则返回 `sheet.avatar` 里的**缩略 dataURI**（`data:image/...;base64,`）。
///      这是**跨设备**的唯一来源：远端玩家的自定义头像被压成 64px 缩略图随
///      公开 sheet 广播过来；他那条相对路径在你这台设备上不存在，所以第 ① 步
///      必然落空 —— 老实现卡在这里，于是整桌远端玩家都退化成首字圆点。
///   ③ 都拿不到 → null（[AvatarThumb] 自己退化成首字圆点）。
///
/// ★ 不猜全局状态：只读这个成员自己的 `sheet`，以及（同机时）用 `charId`
///   回查本机角色库。
String? memberAvatarValue(BuildContext context, Map<String, Object?> member) {
  final sheet = asMap(member['sheet']);
  final raw = sheet['avatar'];

  // ① 本机文件优先（原图高清）。文件必须真的存在，否则会盖掉第 ② 步的缩略图。
  String? localRel = localAvatarRel(raw);
  if (localRel == null) {
    final charId = jsStr(member['charId']).trim();
    if (charId.isNotEmpty) {
      final scope = context.getInheritedWidgetOfExactType<RepoScope>();
      localRel = localAvatarRel(scope?.notifier?.get(charId)?.raw['avatar']);
    }
  }
  if (localRel != null &&
      avatarStore.syncBasePath != null &&
      avatarStore.providerForSync(localRel) != null) {
    return localRel;
  }

  // ② 跨设备缩略图（广播来的 dataURI）
  if (avatarDataUriBytes(raw) != null) return raw is String ? raw.trim() : null;

  // ③ 退回首字圆点：把本机相对路径交回去，让 AvatarThumb 自己判「文件不在」
  return localRel;
}
