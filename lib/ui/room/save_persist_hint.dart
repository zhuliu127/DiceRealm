// ============================================================
// save_persist_hint.dart — 存档持久化能力的说明文案
//
// 为什么单独一个文件：这句话在**两处**出现（入口页续玩区、存档槽弹层），
// 写两份一定会漂。更要紧的是它必须**跟着后端能力变**：
//
//   · 内存后端  → 「关闭 App 后不保留」（这是事实，不能装作能存）
//   · 文件后端  → 「不卸载就一直有效」
//   · 未来远端  → 自己实现 `PersistentSaveStore` 即可自动用后一句
//
// 写死任何一句，换后端那天就变成骗用户 —— 这个项目对「不骗用户」
// 的要求是硬约束（连不上就说连不上、要 KP 同意就说要同意）。
// ============================================================

import '../../domain/room_ports.dart' show RoomSaveStore;
import '../../repo/room_save_store.dart' show PersistentSaveStore;

/// 当前存档后端的持久化说明。
///
/// [store] 可空 —— 远端会话（玩家/旁观）根本没有存档后端，
/// 这时要说「没有可用的存档后端」，而不是假装能存。
String savePersistHintOf(RoomSaveStore? store) {
  if (store == null) return '当前连接不支持本机存档（只有房主能保存）';
  return store is PersistentSaveStore
      ? '存档保存在本机文件里：只要不卸载 App 就一直有效'
      : '存档在本机内存里：关闭 App 后不保留';
}

/// 是否为持久化后端（少数地方要分支显示，例如「清空」按钮的说明）。
bool isPersistentSaveStore(RoomSaveStore? store) =>
    store is PersistentSaveStore;
