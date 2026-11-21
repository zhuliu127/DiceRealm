// ============================================================
// room_save_store.dart — 房间存档仓库的内存后端（R02 / C6 双后端）
//
// domain 只声明 RoomSaveStore 端口（put / get / list 三个纯方法），
// 落地实现必须出 domain：这一层是 I/O 边界，后续期把它换成
// FileRoomSaveStore（dart:io）或云端实现时，domain 一行都不用改。
//
// 本期只交付内存后端：供测试注入、也供「预览态 / 未登录态」使用。
// 文件后端的构造位留在这里（不实现、不引入 dart:io），见文末注释。
// ============================================================

import '../domain/js_compat.dart';
import '../domain/room_ports.dart';

/// 标记接口：这个后端会把存档**落盘**（进程退出后仍在）。
///
/// 为什么需要它：界面必须**按后端能力说真话**。
/// 内存后端要说「关闭 App 后不保留」，文件后端要说「不卸载就一直有效」。
/// 写死任何一句，换后端时就变成骗用户。
///
/// 用标记接口而不是 `store is FileRoomSaveStore`：UI 不必知道具体实现，
/// 将来加「远端存档」也能直接实现这个标记。
///
/// 用法：`final persistent = store is PersistentSaveStore;`
abstract class PersistentSaveStore {}

/// 支持删除的存档后端（`RoomSaveStore` 端口之外的**可选**能力）。
///
/// 端口语义是「可换实现的纯 Map 仓库」，删除不属于所有后端都有的能力
/// （将来换成只追加的远端存储就没有），所以做成独立接口 + 运行时判断，
/// 而不是往 domain 端口里加方法（端口属 domain，冻结）。
///
/// 用法：`final removable = store is RoomSaveStoreMutable;`
abstract class RoomSaveStoreMutable implements RoomSaveStore {
  /// 删除一个槽；键不存在返回 false。
  bool remove(String code);

  /// 清空全部槽（测试隔离 + 「清空本机存档」入口用）。
  void clear();
}

/// 纯内存存档后端：code → 存档 Map。
///
/// 每次 put / get 都做深拷贝，避免调用方拿到内部引用后原地改写，
/// 造成「存档还没落盘就被改」的幽灵差异（K2 键序同样由 roomClone 保持）。
class InMemoryRoomSaveStore implements RoomSaveStoreMutable {
  final Map<String, Map<String, Object?>> _byCode =
      <String, Map<String, Object?>>{};

  @override
  void put(String code, Map<String, Object?> data) {
    _byCode[code] = asMap(roomCloneSafe(data));
  }

  @override
  Map<String, Object?>? get(String code) {
    final hit = _byCode[code];
    return hit == null ? null : asMap(roomCloneSafe(hit));
  }

  @override
  List<String> list() => _byCode.keys.toList();

  /// 已经存过的房间数（超出 MAX_SAVES 的淘汰策略属后续期）。
  int get length => _byCode.length;

  /// 删除一个槽。
  ///
  /// `RoomSaveStore` 端口（domain）只有 `put / get / list`，没有删除；存档槽弹层
  /// 需要它，所以作为 [RoomSaveStoreMutable] 的**扩展能力**提供，端口签名一个字没改。
  /// 删除成功返回 true；键不存在返回 false。
  @override
  bool remove(String code) => _byCode.remove(code) != null;

  /// 清空全部槽（测试隔离 + 「清空本机存档」入口用）。
  @override
  void clear() => _byCode.clear();

  /// 与 domain 的 `roomClone` 同语义，但这里不 import domain 的房间实现细节，
  /// 只用 dart:convert 做一次 JSON 往返（纯 JSON 数据，零 I/O）。
  static Object? roomCloneSafe(Object? v) {
    if (v is Map) {
      final out = <String, Object?>{};
      v.forEach((k, x) => out['$k'] = roomCloneSafe(x));
      return out;
    }
    if (v is List) return v.map(roomCloneSafe).toList();
    return v;
  }
}

// ------------------------------------------------------------
// 后续期（Q5 / 设计 §2.3）：FileRoomSaveStore implements RoomSaveStore
//   · 构造位：FileRoomSaveStore({required Directory directory, int maxSaves = 8})
//   · put → 写 <directory>/<code>.json（临时文件 + rename 原子替换）
//   · get → 读回并 jsonDecode；list → 目录扫描按 mtime 排序
//   · MAX_SAVES=8 的淘汰 + saveRoom()/saveNow()/listRoomSaves() 一并落地
//   ⚠️ dart:io 只允许出现在本文件（repo 层），domain 保持纯 Dart。
// ------------------------------------------------------------
