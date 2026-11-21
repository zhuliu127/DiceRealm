// ============================================================
// repo/file_room_save_store.dart — 房间存档的文件后端
//
// 解决什么问题：`InMemoryRoomSaveStore` 是纯内存的，**杀进程即丢**。
// 长团打到一半切个后台被系统回收，续玩列表就空了。P5 的界面上
// 已经如实写了「关闭 App 后不保留」，本文件把这句话变成历史。
//
// ---------------------------------------------------------------
// 为什么是「内存缓存 + 异步落盘」而不是直接读写文件
// ---------------------------------------------------------------
// `RoomSaveStore` 端口的签名是**同步**的（`void put` / `Map? get` /
// `List<String> list`），而它属 domain、已冻结。文件 I/O 异步，
// 不可能硬塞进同步签名。
//
// 所以：
//   · 启动时 `loadSync()` 一次性读进内存（同步，之后 list/get 立刻有货，
//     续玩列表首屏就有东西）
//   · `put` / `remove` 改内存 + **排队**异步写盘（调用方不等待）
//   · `flush()` 供测试与「退出前确保落盘」使用
//
// ---------------------------------------------------------------
// 三个必须守住的点
// ---------------------------------------------------------------
// 1. **原子写**：先写 `.tmp` 再覆盖目标。写到一半掉电会留下半截 JSON，
//    那份存档就再也读不出来了 —— 存档损坏比丢一次保存严重得多。
// 2. **单文件损坏不影响其他**：`loadSync()` 逐文件 try/catch，
//    坏的那个跳过（记进 `lastError`），其余照常可用。
// 3. **路径穿越防护**：槽键会被拼进文件名，`../` 能写到任意位置。
//    所以键必须过白名单（见 `isSafeKey`）。
// 4. **结构化槽键可落盘**：`auto/<code>/<reason-ts>` 与 `share/<code>/latest`
//    是 syncer 的滚动档 / 收档槽，含 `/` 不能直接做文件名。这里对**仅这两种
//    形状**做可逆十六进制编码（见 `isStructuredSlotKey` / `_fileNameKeyOf`），
//    `list()/get()` 对外仍返回原始逻辑键；`isSafeKey` 的白名单语义一字不改，
//    `../evil` 等任意路径键依然被拒（PRD §2.3 #8 路径穿越防线不放宽）。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/js_compat.dart' show asMap;
import 'room_save_store.dart'
    show
        InMemoryRoomSaveStore,
        PersistentSaveStore,
        RoomSaveStoreMutable;

/// 文件后端：一个槽一个 `<key>.json`。
///
/// [dir] 由调用方给（生产用 `path_provider` 的应用文档目录；
/// 测试用临时目录）—— 这里不自己去找目录，因为插件在 `flutter test`
/// 下不可用，构造期去拿会让整个测试套跑不起来。
class FileRoomSaveStore implements RoomSaveStoreMutable, PersistentSaveStore {
  FileRoomSaveStore(this.dir);

  final Directory dir;

  final Map<String, Map<String, Object?>> _mem =
      <String, Map<String, Object?>>{};

  /// 每个槽一条写盘链。同一槽连续 put 会排队，避免两个写并发抢同一文件。
  final Map<String, Future<void>> _writes = <String, Future<void>>{};

  bool _loaded = false;

  /// 是否已经 loadSync 过（没加载过就 list 会返回空，容易被误判成「没存档」）。
  bool get isLoaded => _loaded;

  /// 最近一次 I/O 错误（诊断用，不抛给 UI）。
  Object? lastError;

  /// 槽数。
  int get length => _mem.length;

  // ----------------------------------------------------------
  // 槽键白名单（防路径穿越）
  // ----------------------------------------------------------

  /// Windows 保留设备名。
  ///
  /// `CON.json` 这类名字在 Windows 上会被当成**设备**而不是文件 ——
  /// 写入会静默失败或跑到控制台去。它们全是大写字母，光靠字符白名单挡不住。
  static const Set<String> _reservedNames = <String>{
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5',
    'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5',
    'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// 允许的槽键：字母数字下划线短横线，1–64 位，且不是 Windows 保留名。
  ///
  /// 房间号是 6 位大写字母数字；存档槽名也可能是用户可见的短名。
  /// 只要不含 `/` `\` `.` `:` 就不可能逃出 [dir]；
  /// 排除保留名是防 Windows 把文件名当设备。
  static bool isSafeKey(String key) {
    if (key.isEmpty || key.length > 64) return false;
    if (!RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(key)) return false;
    if (_reservedNames.contains(key.toUpperCase())) return false;
    return true;
  }

  /// 结构化槽键的逻辑前缀（与 `RoomSaveSyncer` 的 auto/share 槽一一对应）。
  static const String autoSlotPrefix = 'auto/';
  static const String sharedSlotPrefix = 'share/';
  static const String autoSlotNamespace = 'auto';
  static const String sharedSlotNamespace = 'share';

  /// 编码文件名前缀。`~` 不在 [isSafeKey] 白名单里，历史安全键绝不会撞名。
  static const String encodedSlotMarker = '~sk~';

  /// 结构化槽键最大逻辑长度（编码后文件名 < 200 字符，低于常见 255 上限）。
  static const int maxStructuredSlotKeyLength = 96;

  static final RegExp _slotSegment = RegExp(r'^[A-Za-z0-9_\-]+$');

  /// 只放行 syncer 真正使用的两种分层槽：`auto/<code>/<tail>` /
  /// `share/<code>/<tail>`。三段、段内只有字母数字下划线短横线 —— `..`、
  /// 反斜杠、多余 `/`、任意中文槽名都不可能通过，路径穿越面零扩大。
  static bool isStructuredSlotKey(String key) {
    if (key.isEmpty || key.length > maxStructuredSlotKeyLength) return false;
    final parts = key.split('/');
    if (parts.length != 3) return false;
    if (parts[0] != autoSlotNamespace && parts[0] != sharedSlotNamespace) {
      return false;
    }
    return _slotSegment.hasMatch(parts[1]) && _slotSegment.hasMatch(parts[2]);
  }

  /// 逻辑键 → 文件名主干。安全键原样返回（旧存档文件名零漂移）；
  /// 结构化键编码成 `~sk~<hex(utf8)>`；其余非法键原样返回，由 [put] 拒绝。
  static String _fileNameKeyOf(String key) {
    if (isSafeKey(key)) return key;
    if (!isStructuredSlotKey(key)) return key;
    final hex = utf8
        .encode(key)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$encodedSlotMarker$hex';
  }

  /// 文件名主干 → 逻辑键。非编码文件原样返回（历史兼容）；
  /// 编码文件解码后必须仍是合法结构化槽键，否则当作外来文件跳过。
  static String? _decodeFileNameKey(String name) {
    if (!name.startsWith(encodedSlotMarker)) return name;
    final String hex = name.substring(encodedSlotMarker.length);
    if (hex.isEmpty || hex.length.isOdd) return null;
    final List<int> bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      final int? byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) return null;
      bytes.add(byte);
    }
    try {
      final String key = utf8.decode(bytes);
      return isStructuredSlotKey(key) ? key : null;
    } catch (_) {
      return null;
    }
  }

  File _fileFor(String key) =>
      File('${dir.path}${Platform.pathSeparator}${_fileNameKeyOf(key)}.json');

  // ----------------------------------------------------------
  // 加载
  // ----------------------------------------------------------

  /// 同步读入全部槽。**启动时调一次**。
  ///
  /// 返回成功载入的槽数。读不到的单个文件只跳过，不整体失败。
  int loadSync() {
    _mem.clear();
    var n = 0;
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.isEmpty ? '' : f.uri.pathSegments.last;
        if (!name.endsWith('.json')) continue; // 跳过 .tmp 等中间文件
        final rawKey = name.substring(0, name.length - '.json'.length);
        final String? key = _decodeFileNameKey(rawKey);
        if (key == null) continue; // 编码损坏 / 外来怪文件不认
        if (!isSafeKey(key) && !isStructuredSlotKey(key)) continue;
        try {
          final raw = jsonDecode(f.readAsStringSync());
          if (raw is Map) {
            _mem[key] = asMap(
              InMemoryRoomSaveStore.roomCloneSafe(raw),
            );
            n++;
          }
        } catch (e) {
          // ★ 单个存档损坏不拖垮全部 —— 其余槽仍然可用。
          lastError = e;
        }
      }
    } catch (e) {
      // 目录都读不了（权限/磁盘）：退化成空列表，App 仍能起来。
      lastError = e;
    }
    _loaded = true;
    return n;
  }

  // ----------------------------------------------------------
  // RoomSaveStore
  // ----------------------------------------------------------

  @override
  void put(String code, Map<String, Object?> data) {
    // ★ P13：**先清掉上一次的失败残留**。
    //   调用方（`[SAVE]` 诊断、存档槽 UI）是「put 之后立刻读 lastError」
    //   判断本次成败的；不清就会把上一槽的拒绝（例如中文槽名被
    //   [isSafeKey] 拒写）读成本次失败 —— 真机上表现为：`saveNow
    //   key=BVTPTJ` 明明落盘成功，日志却跟着一条 `put FAILED ...
    //   lastError=非法存档槽键：BVTPTJ · 第1轮`（假红）。
    //   清空之后，`put` 返回时 `lastError != null` 恰好等价于「**本次**被拒」。
    lastError = null;
    if (!isSafeKey(code) && !isStructuredSlotKey(code)) {
      // 非法键直接拒（不抛：上层可能从存档里读到怪名字，不该让整个保存失败）。
      // 结构化槽键走编码文件名落盘；任意含 / \ .. 的路径键依旧拒写。
      // ★ 白名单语义一字不改 —— 这里清的是「上一槽」的残留，不是放宽防线。
      lastError = ArgumentError('非法存档槽键：$code');
      return;
    }
    // 与 InMemory 同语义：存快照，调用方事后改源对象不影响存档。
    _mem[code] = asMap(InMemoryRoomSaveStore.roomCloneSafe(data));
    _enqueueWrite(code);
  }

  @override
  Map<String, Object?>? get(String code) {
    final hit = _mem[code];
    // 取出时也深拷贝：调用方就地改不能污染存档（与 InMemory 同口径）。
    return hit == null ? null : asMap(InMemoryRoomSaveStore.roomCloneSafe(hit));
  }

  @override
  List<String> list() => _mem.keys.toList()..sort();

  @override
  bool remove(String code) {
    final had = _mem.remove(code) != null;
    if (!had) return false;
    _enqueueWrite(code); // 排队里会看到 _mem 已无该键 → 删文件
    return true;
  }

  @override
  void clear() {
    final keys = _mem.keys.toList();
    _mem.clear();
    for (final k in keys) {
      _enqueueWrite(k);
    }
  }

  // ----------------------------------------------------------
  // 落盘
  // ----------------------------------------------------------

  /// 等所有排队中的写盘完成。测试与「退出房间前确保落盘」用。
  Future<void> flush() async {
    // 排队的写可能又追加了新写，所以循环到没有未完成的。
    while (_writes.isNotEmpty) {
      final pending = _writes.values.toList();
      _writes.clear();
      await Future.wait(pending);
    }
  }

  void _enqueueWrite(String code) {
    final prev = _writes[code] ?? Future<void>.value();
    // ★ 链式排队：同一槽的两次 put 不会并发写同一个文件。
    final next = prev.then((_) => _writeNow(code));
    _writes[code] = next;
    // 写完后把自己从表里摘掉（只摘自己那一环，别误删后来追加的）。
    next.whenComplete(() {
      if (identical(_writes[code], next)) _writes.remove(code);
    });
  }

  Future<void> _writeNow(String code) async {
    final file = _fileFor(code);
    final data = _mem[code];

    // 内存里没有 = 这个槽被删了（remove / clear）。
    if (data == null) {
      try {
        if (file.existsSync()) await file.delete();
      } catch (e) {
        lastError = e;
      }
      return;
    }

    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      // 先写临时文件再覆盖：写到一半掉电只毁 tmp，原存档还完整。
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.copy(file.path);
      try {
        await tmp.delete();
      } catch (_) {
        // tmp 删不掉不影响正确性，下次 put 会覆盖它。
      }
    } catch (e) {
      // ★ 写盘失败不抛：内存里还有数据，本次游玩不受影响。
      //   真机上磁盘满/无权限时，用户至少不会看到崩溃。
      lastError = e;
    }
  }

  /// 让某个槽的写盘立刻完成并等待（测试用，避免依赖 flush 的全局语义）。
  Future<void> flushOne(String code) async {
    while (_writes.containsKey(code)) {
      final f = _writes[code]!;
      await f;
      if (identical(_writes[code], f)) _writes.remove(code);
    }
  }
}
