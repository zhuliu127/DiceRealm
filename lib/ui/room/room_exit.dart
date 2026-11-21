// ============================================================
// room_exit.dart — 「这间房还容得下我吗？」的**唯一判定**（P10 第 1 期 B3/B4）
//
// 用户报的两个问题（原话）：
//   · 「结团 / 解散房间点了没反应，也不退出房间」；
//   · 「踢人后玩家不离开；离开后无法重新加入」。
//
// 第一个的根因是**没有人把页面带走**：domain 里 `room.close` / `room.end`
// 都有实现（`closeRoom()` / `endSession()`），事件也真的 reduce 成了
// `meta.status = CLOSED`，但 UI 只是在原地重画了一遍 —— 用户看到的就是
// 「点了没反应」。
//
// 所以把「该不该离开、离开时说什么」抽成一个**纯函数**（零 Flutter 依赖），
// 由房间里唯一的壳体 `_RoomShell` 监听会话变化后调用。这样：
//   · KP 关房 / 结团 → 自己离开；
//   · 远端玩家收到 CLOSED / ENDED / KICK → 也离开（同一套判据）；
//   · 判据与 UI 解耦，普通 `test` 就能穷举，不需要渲染整页。
//
// ★ 判定顺序（很重要）：
//   ① `meta.ended == true` → 结团（KP 主动结束整团，存档里的终止标记）
//   ② `meta.status == CLOSED`：
//        · 我不在成员表里 → 我被踢了；
//        · 我还在成员表里（或我是 KP）→ 房主关房。
//   KICK 事件在 reduce 里也会把 status 置 CLOSED（旧客户端把它当终止），
//   所以「踢」与「关」只能靠「我还在不在名单里」区分 —— 这也是旧版
//   `room-lan.js` 的做法。
// ============================================================

import '../../domain/js_compat.dart' show asMap, asList, jsTruthy;
import '../../domain/room_types.dart' show RoomRole, RoomStatus, kHostSeat;

import 'room_text.dart' show roomText;

/// 离开房间的原因。
enum RoomExitKind {
  /// 不离开（房间还在，或还没收到第一份全量同步）。
  none,

  /// 房主关闭了房间（`room.close`）。
  closed,

  /// 房主结团（`room.end` / `session.end`）。
  ended,

  /// 我被房主移出房间（`room.kick`）。
  kicked,
}

/// 判定结果（不可变值对象）。
class RoomExit {
  const RoomExit(this.kind, this.message);

  /// 不离开。
  static const RoomExit none = RoomExit(RoomExitKind.none, '');

  final RoomExitKind kind;

  /// 回入口页后要显示的那句话（不弹模态，K7）。
  final String message;

  bool get shouldLeave => kind != RoomExitKind.none;

  @override
  String toString() => 'RoomExit($kind)';
}

/// 判定当前视角是否该离开房间。
///
/// 参数取会话的**原始** state / seat / role（本机与远端同一个口径）：
///   · [state]：当前视角的裁剪态；
///   · [seat]：我坐哪（KP 是 `host`）；
///   · [role]：kp / player / spectator。
RoomExit roomExitOf({
  required Map<String, Object?> state,
  required String seat,
  required String role,
  bool kickedByHost = false,
}) {
  final meta = asMap(state['meta']);
  final status = roomText(meta['status']);
  // 还没收到第一份同步（成员表与 meta 都是空的）→ 什么都不判断。
  if (meta.isEmpty && asList(state['members']).isEmpty) return RoomExit.none;

  final bool ended = jsTruthy(meta['ended']);
  final bool closed = status == RoomStatus.closed;
  // 挂起（SUSPENDED）**不算离开**：房间还能复活，人留在原地看得到提示。
  if (!ended && !closed) return RoomExit.none;

  if (ended) {
    return const RoomExit(
      RoomExitKind.ended,
      'KP 已结团，房间已结束（本机已退出房间）',
    );
  }

  // 到这里一定是 CLOSED。判定「被踢」只有一条硬信号：**我收到过 KICK**。
  //
  // ⚠️ 不能用「我还在不在成员表里」当判据（这是第一版踩的坑）：
  //    KICK 之后花名册立刻少了我，而 `plan()` 的收件人是从花名册算的 ——
  //    紧跟着那条 `members` 广播根本不会发给我，被踢者手里的名单永远是旧的。
  //    于是「不在名单里」对谁都成立不了，踢人会被误判成"房主关房"。
  final bool isKp = role == RoomRole.kp || seat == kHostSeat;
  if (!isKp && kickedByHost) {
    return const RoomExit(
      RoomExitKind.kicked,
      '你已被房主移出房间',
    );
  }
  return const RoomExit(
    RoomExitKind.closed,
    'KP 已结束房间（本机已退出房间）',
  );
}

/// 我的座位是否还在成员表里（**仅供诊断/报告用**，不作为「被踢」判据）。
///
/// 原因见 [roomExitOf] 里的注释：被踢者收不到那条 members 广播。
bool inRoomMembers(Map<String, Object?> state, String seat) {
  if (seat.isEmpty) return false;
  for (final m in asList(state['members'])) {
    if (roomText(asMap(m)['seat']) == seat) return true;
  }
  return false;
}
