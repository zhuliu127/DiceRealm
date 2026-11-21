// ============================================================
// room_keys.dart — 稳定 key 常量 + 槽位枚举（设计 §0.4 / §7.2 K1）
//
// ★ 容器 key 是**唯一标识**：KP 与 PL 的块号各自独立编号，同一块号在
//   两侧含义完全不同（块 2 在 KP 是「左窄栏」、在玩家是「我的角色卡」），
//   所以这里不做跨视角块号对齐，块号只出现在注释里。
//
// ★ 计数：KP **12** 容器 / 玩家（含旁观）**13** 容器（PRD 附录 A）。
//   `gpCombatStrip` 是 PL 块 3 内部的附属条，不计入 13 个主容器。
//
// ★ 两种常量并存（兼容设计里两种写法）：
//   · `RoomKeys.gpChat` 是 String → 配 `ValueKey(RoomKeys.gpChat)`（§1.4）
//   · `RoomKeys.kpStartGame` 是 Key → 可直接 `key: RoomKeys.kpStartGame`（§1.6）
//   · `RoomKeys.action(op)` 返回 Key → 表驱动权限探针 T-30 的抓手
// ============================================================

import 'package:flutter/foundation.dart';

/// 房间容器的槽位枚举。枚举名与 [RoomKeys] 的容器 key 字符串一一对应。
enum RoomSlot {
  // KP 视角 12 块（PRD 附录 A.1）
  gpTopbar,
  gpKpLeft,
  gpKpTools,
  gpMap,
  gpScene,
  gpCombat,
  gpPlayers,
  gpChat,
  gpLog,
  gpPriv,
  gpToolbar,
  gpStatus,

  // 玩家 / 旁观视角独有容器（PRD 附录 A.2）
  gpPlCharCard,
  gpPlMap,
  gpCombatStrip,
  gpPlChat,
  gpPlLog,
  gpPlCombat,
  gpPlScene,
  gpPlMates,
  gpPlSketch,
  gpPlNotes,
}

/// 全部稳定 key。
class RoomKeys {
  const RoomKeys._();

  // ---- KP 12 容器（块号见注释，只用于对照 PRD，不参与逻辑） ----
  static const String gpTopbar = 'gpTopbar'; // 块 1（两侧共用）
  static const String gpKpLeft = 'gpKpLeft'; // 块 2
  static const String gpKpTools = 'gpKpTools'; // 块 3
  static const String gpMap = 'gpMap'; // 块 4
  static const String gpScene = 'gpScene'; // 块 5
  static const String gpCombat = 'gpCombat'; // 块 6
  static const String gpPlayers = 'gpPlayers'; // 块 7
  static const String gpChat = 'gpChat'; // 块 8
  static const String gpLog = 'gpLog'; // 块 9
  static const String gpPriv = 'gpPriv'; // 块 10（两侧共用）
  static const String gpToolbar = 'gpToolbar'; // 块 11（两侧共用，缩放容器外）
  static const String gpStatus = 'gpStatus'; // 块 12（两侧共用）

  // ---- 玩家 / 旁观容器 ----
  static const String gpPlCharCard = 'gpPlCharCard'; // 块 2
  static const String gpPlMap = 'gpPlMap'; // 块 3 主体
  static const String gpCombatStrip = 'gpCombatStrip'; // 块 3 附属条（不计 13）
  static const String gpPlChat = 'gpPlChat'; // 块 4
  static const String gpPlLog = 'gpPlLog'; // 块 5
  static const String gpPlCombat = 'gpPlCombat'; // 块 6
  static const String gpPlScene = 'gpPlScene'; // 块 7
  static const String gpPlMates = 'gpPlMates'; // 块 8
  static const String gpPlSketch = 'gpPlSketch'; // 块 10
  static const String gpPlNotes = 'gpPlNotes'; // 块 11

  // ---- 常用控件 key（直接给 widget.key 用） ----
  static const Key kpStartGame = ValueKey<String>('kpStartGame');
  static const Key gpChatInput = ValueKey<String>('gpChatInput');
  static const Key gpFeedList = ValueKey<String>('gpFeedList');
  static const Key gpPrivList = ValueKey<String>('gpPrivList');
  static const Key kpScenePush = ValueKey<String>('kpScenePush');
  static const Key gpDiceBar = ValueKey<String>('gpDiceBar');
  static const Key gpZoomReset = ValueKey<String>('gpZoomReset');
  static const Key gpPlSketchClear = ValueKey<String>('gpPlSketchClear');
  static const Key gpPlNotesAdd = ValueKey<String>('gpPlNotesAdd');

  /// 表驱动权限探针（T-30）：按 action 名稳定取 key。
  static Key action(String op) => ValueKey<String>('act/$op');

  /// 槽位 → 容器 key 字符串。
  static String slotKey(RoomSlot slot) => slot.name;

  /// 槽位 → 可直接使用的 [ValueKey]。
  static Key keyOfSlot(RoomSlot slot) => ValueKey<String>(slot.name);

  /// KP 视角的 12 个槽位（顺序 = 附录 A.1 块 1–12）。
  static const List<RoomSlot> kpSlots = <RoomSlot>[
    RoomSlot.gpTopbar,
    RoomSlot.gpKpLeft,
    RoomSlot.gpKpTools,
    RoomSlot.gpMap,
    RoomSlot.gpScene,
    RoomSlot.gpCombat,
    RoomSlot.gpPlayers,
    RoomSlot.gpChat,
    RoomSlot.gpLog,
    RoomSlot.gpPriv,
    RoomSlot.gpToolbar,
    RoomSlot.gpStatus,
  ];

  /// 玩家 / 旁观视角的 13 个槽位（顺序 = 附录 A.2 块 1–13；
  /// `gpCombatStrip` 是块 3 内的附属条，不单列）。
  static const List<RoomSlot> plSlots = <RoomSlot>[
    RoomSlot.gpTopbar,
    RoomSlot.gpPlCharCard,
    RoomSlot.gpPlMap,
    RoomSlot.gpPlChat,
    RoomSlot.gpPlLog,
    RoomSlot.gpPlCombat,
    RoomSlot.gpPlScene,
    RoomSlot.gpPlMates,
    RoomSlot.gpPriv,
    RoomSlot.gpPlSketch,
    RoomSlot.gpPlNotes,
    RoomSlot.gpToolbar,
    RoomSlot.gpStatus,
  ];

  /// C7 死代码清单由 T05 的静态门禁文件单独持有；本目录内**不出现**
  /// 那些遗留面板名（机械门禁要求零命中），故此处刻意不列字面量。
}
