// ============================================================
// room_session.dart — P5 的「会话端口」（UI 层，不是 domain）
//
// 为什么要有这一层（PRD §9.4 Q-P5-1）：P5 不做 P6 传输，但玩家/旁观视角
// 必须来自**真正被裁剪过的数据**，不能拿 host.state 假装。所以 UI 不直接
// 持有 RoomHost / RoomClient，只认 RoomSession：
//   · P5 用 LocalLoopbackSession（同进程环回，见 room_session_local.dart）；
//   · P6 只加一个 RemoteSession extends RoomSession，UI 一行不改。
//
// 设计 §1.3 铁律：UI 的**唯一出入口**是 RoomController；RoomSession 是
// 控制器背后被持有的那一个对象。RoomScope 只是把「已经配好的三件套」
// （session / local / controller）沿 widget 树传下去，不产生第二个写口。
//
// ★ 兼容性说明（T01/S1.1）：本文件在 09:20 已有一份预置稿，其成员
//   （linkState / sendAction / pullSync(seat) / stateFor / seats /
//    rollback / lastRollbackBeforeSeq / sent / changes / onNotice）全部保留，
//   另按设计 §3.1 补齐 link / lastSeq / lastNotice / hostAction /
//   clampBeforeSeq，以及 §3.4 的 saveNow/openSave 所需的 exportSave /
//   importSave 两个端口方法。两组签名并存，任何调用方都不必改。
//
// ⚠️ 本文件在 lib/ui/room/ 根层，允许引入框架的 foundation 库
//    （ChangeNotifier）；但 view/ 子目录必须零框架依赖，见 view/room_view.dart。
// ============================================================

import 'package:flutter/foundation.dart';

import '../../domain/room_model_host_core.dart';
import '../../domain/room_ports.dart';
import '../../domain/room_types.dart';

/// 连接态三档（§3.1）。游戏页顶栏**始终可见**（P0-04），不允许只画两档。
///
/// `resync` 是「补拉中」的中间态（预置稿已有），`online` 是 `connected`
/// 的兼容别名 —— 两者指向同一个枚举值，不制造第四档语义。
enum RoomLinkState {
  /// 连接中：还没拿到首份全量同步。
  connecting,

  /// 在线：增量/全量都正常。
  connected,

  /// 补拉中：检测到序号缺口，正在向权威端要数据。
  resync,

  /// 离线：本机视图仍可只读展示，但发出的 intent 不会被送达。
  offline;

  /// 兼容预置稿的 `RoomLinkState.online` 写法。
  static const RoomLinkState online = RoomLinkState.connected;
}

/// KP 专属只读面（PRD §6.4 陷阱：手绘板缩略图恒空，要读本机权威副本）。
///
/// ★ 设计 §3.2 用 `abstract class` 表达「只读」意图；这里落成具体类 +
///   `unmodifiable` 视图，约束等价且调用方（T04 的 KP 面板）可直接构造。
///   §3.2 的 6 个 getter（state / pending / localActors / localAssets /
///   boardBySeat / requestsBySeat）全部具备。
///
/// 刻意不暴露 `RoomHost.apply`：UI 拿不到写口，也拿不到 `state` 的可写
/// 引用（C1）。KP 面板需要的本机候选池 / 未公开素材 / 逐 seat 手绘板都从
/// 这里按 getter 取，和 P4 的存档口径保持一致。
class RoomHostRead {
  const RoomHostRead(this.host);

  /// 仅 KP 视角可持有；构造方负责保证不把它交给玩家 / 旁观者。
  final RoomHost host;

  /// 只读房间快照（调用方只读，禁止写入 —— C1 铁律）。
  Map<String, Object?> get state => host.state;

  /// 待确认队列（owner / all 类高危动作）。
  List<Map<String, Object?>> get pending =>
      List<Map<String, Object?>>.unmodifiable(host.pending);

  /// 开战前候选池（不进事件流，随 save() 落存档）。
  List<Map<String, Object?>> get localActors =>
      List<Map<String, Object?>>.unmodifiable(host.localActors);

  /// 未公开素材库。
  List<Map<String, Object?>> get localAssets =>
      List<Map<String, Object?>>.unmodifiable(host.localAssets);

  /// 各玩家手绘板（`boardBySeat[seat]['strokes']`，全屏查看用）。
  Map<String, Map<String, Object?>> get boardBySeat =>
      Map<String, Map<String, Object?>>.unmodifiable(host.boardBySeat);

  /// 待玩家同意的改状态请求（逐 seat）。
  Map<String, List<Map<String, Object?>>> get requestsBySeat =>
      Map<String, List<Map<String, Object?>>>.unmodifiable(
          host.requestsBySeat);

  /// 某个座位的完整手绘板（本机权威副本）。
  Map<String, Object?>? boardOf(String seat) => host.boardBySeat[seat];

  /// 逐 seat 私有累计（重连全量同步靠它恢复）。
  Map<String, List<Object?>> get privateBySeat =>
      Map<String, List<Object?>>.unmodifiable(host.privateBySeat);

  /// 按可见性裁剪后的战斗视图（KP 传 [kHostSeat] 拿全量）。
  Map<String, Object?>? combatFor(String seat) => host.combatFor(seat);

  /// 首连 / 重连的全量同步信封（裁剪规则与增量共用）。
  SyncEnvelope syncFor(String seat) => host.syncFor(seat);

  /// 权威端当前全局序号。UI 只用于诊断，不拿它做逻辑（PRD §6.4）。
  int get seq => host.log.seq;

  /// 「已剥离私有字段」等异常（正常路径必须为空）。
  List<RoomWarning> get warnings =>
      List<RoomWarning>.unmodifiable(host.warnings);
}

/// 一条「UI 发出的操作」记录，供测试断言「点了有没有反应」。
class SessionSendLog {
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];

  /// [kind] 只能是 `'intent'`（13 个 INTENT）或 `'action'`（INTENT.ACT 的内层 op）。
  void add(String kind, String op, Map<String, Object?> p) {
    entries.add(<String, Object?>{
      'kind': kind,
      'op': op,
      'p': <String, Object?>{...p},
      'at': entries.length,
    });
  }

  int get length => entries.length;

  bool get isEmpty => entries.isEmpty;

  /// 按 op 过滤（保留记录顺序）。
  List<Map<String, Object?>> whereOp(String op) =>
      entries.where((e) => e['op'] == op).toList();

  /// 按 kind 过滤。
  List<Map<String, Object?>> whereKind(String kind) =>
      entries.where((e) => e['kind'] == kind).toList();

  void clear() => entries.clear();
}

/// 房间会话抽象：一份**视角**对应一个实例。
///
/// `state` 是该视角「真正收到的数据」——KP 是权威态，玩家/旁观者是
/// `RoomClient.receive()` 回放出来的裁剪态。这样 C2「不是靠 UI 隐藏」
/// 在结构上成立：搜不到的字段，客户端压根没收到。
abstract class RoomSession extends ChangeNotifier {
  /// 房间号（顶栏显示）。
  String get code;

  /// 当前视角座位号；KP 恒为 [kHostSeat]。
  String get seat;

  /// 当前视角角色（kp / player / spectator）。**唯一权威**，UI 不自己推。
  String get role;

  /// 当前视角的**只读**状态快照。调用方不得写入。
  Map<String, Object?> get state;

  /// 连接态三档（§3.1 命名）。
  RoomLinkState get link;

  /// 连接态三档（预置稿命名，与 [link] 同一个值）。
  RoomLinkState get linkState => link;

  /// 已应用的最后全局序号，**仅诊断用**（PRD §6.4：不得据此做业务逻辑）。
  int get lastSeq;

  /// 连接层「全量同步世代」：每完成一次全量 sync（首连 / 自动重连补拉 /
  /// gap 自愈补拉 / 显式补拉）自增一次。UI 只把它当作「补拉已发生」的
  /// **显式信号**来重置闪烁基线，绝不拿它或 [lastSeq] 去推算业务语义。
  ///
  /// 这是 Round 2 的根因修复：早期用「全局 seq 差值」猜「是不是断线补拉」，
  /// 差值会被多列交错放大、又在短断线时太小，两头都判错。现在补拉由连接层
  /// 直接告知，判据侧不再猜。
  ///
  /// 本机会话（LocalLoopback / Hosting）没有断线重连概念，默认恒 0，无需
  /// 覆盖；P6 的远端会话会覆盖成真实世代。带默认实现，既有实现零改动。
  int get syncEpoch => 0;

  /// 权威端最近一次的定向提示（`sysTo`），供块级 banner 显示。
  /// 不弹模态、不阻断（K7 错误口径）。
  String? get lastNotice;

  /// 权威端是否**专门给我**发过 KICK。
  ///
  /// 为什么需要这个信号（P10 第 1 期 B4 的根因）：
  ///   被踢时 `meta.status` 也会变成 CLOSED（旧客户端把它当终止），与
  ///   「房主关房 / 结团」在状态上**完全一样**。而「我还在不在成员表」这条
  ///   判据也靠不住 —— KICK 之后花名册就没有我了，`plan()` 的收件人列表
  ///   也随之少了我，于是**后面那条 members 广播根本不会发给我**：
  ///   被踢者手里的成员表永远是旧的（还含自己）。
  ///   所以只能认「我收到过 kick 信封」这一条硬信号。
  ///
  /// 默认 false（KP 视角永远收不到给自己的 KICK）。
  bool get kickedByHost => false;

  /// 权威端最近一次 **TEMP_COMMIT**（临时卡生效）广播里的回合号。
  ///
  /// 为什么需要这条信号（P10 第 2 期 A，对齐老 APP v2.9.0）：
  ///   老 APP 的顺序是硬要求 —— 回合出口先发 `EVT.ROUND`，再跑濒死检定
  ///   （`_onRoundBoundary`），**再跑天/周恢复**（`_onDayWeekTick`，重伤每周
  ///   回血会经 `EVT.STATE` 改临时卡），**最后**才发 `EVT.TEMP_COMMIT`。
  ///   各玩家客户端收到 TEMP_COMMIT 才把「本房本卡的临时卡」覆盖回原卡。
  ///   这个顺序保证玩家落库的是**恢复之后**的值；反过来（一看到回合号变就
  ///   存盘）会把「恢复前」的旧值写回原卡 —— 老 APP 的注释专门写了这条。
  ///
  /// 语义（与老 APP `room-net.js#_onTempCommit` 一致）：
  ///   · 只提交**本房**的临时卡（roomCode 隔离），别房绝不误伤；
  ///   · 本机没有本房临时卡 → 静默跳过（不报错、不提示、不阻断）；
  ///   · 生效 = 用临时卡覆盖原卡，幂等可重复；
  ///   · **不进存档**（reduce 无分支、`save()` 不含它）。
  ///
  /// 默认 0 = 从未收到（或本视角拿不到事件，例如没有注册 client 的空视角）。
  int get lastTempCommitRound => 0;

  /// KP 专属只读面；非 KP 视角恒为 null（拿不到就是拿不到）。
  RoomHostRead? get hostRead;

  /// 全库发送记录（测试用；生产侧只追加不读取）。
  SessionSendLog get sent;

  /// 与 `this` 同一个 Listenable（兼容 PRD §9.4 建议的 `changes` 命名）。
  Listenable get changes => this;

  /// 错误 / 提示文案的下游接收者（由 RoomController 挂上）。
  void Function(String)? onNotice;

  /// ★ P20 N-3：收到 KP 分发的存档快照（`RoomEvt.saveSync`）时的落盘回调。
  ///
  /// 从 `LocalLoopbackSession` 上提到基类（默认 null，加法式，不改变任何
  /// 既有实现），使 **RemoteSession / CloudRemoteSession** 这两个真实联网
  /// 玩家会话也能挂上 —— 否则 `share/<code>/latest` 从未落盘，③ 区根本
  /// 没有玩家续玩条目可点。由 `RoomSaveSyncer` 在构造期统一注入。
  void Function(Map<String, Object?> save)? onSharedSave;

  /// 已挂载的座位列表（含 host）。
  List<String> get seats;

  /// 发一个 13 个 INTENT 之一。信封形状由实现方组装，UI 只给 op + p。
  Future<void> sendIntent(String op, Map<String, Object?> p);

  /// 发一个 61 个 action 之一（§3.1 命名）。
  /// **双层**：外层 `INTENT.ACT`，内层 `p['op']` 才是 action 名。
  Future<void> hostAction(String action, [Map<String, Object?>? p]);

  /// 发一个 action（预置稿命名，委托给 [hostAction]）。
  Future<void> sendAction(String action, Map<String, Object?> p) =>
      hostAction(action, p);

  /// 断线补拉（§3.1 无参 / 预置稿带 seat，二者都兼容）。
  /// P5 loopback 直通一份全量同步；P6 换成向中继发 `INTENT.SYNC`。
  Future<void> pullSync([String? seat]);

  /// 取某个座位的裁剪态（测试做跨视角对比用；UI 不该跨视角读）。
  Map<String, Object?> stateFor(String seat);

  /// K1 守卫：适配层把 `beforeSeq < 1` 夹到 1 再交给 P4 rollback。
  /// 返回 P4 的原始结果，供断言「state.seq == log.seq」水位相等。
  RollbackResult rollback(int beforeSeq);

  /// 本次 rollback 实际使用的 beforeSeq（夹取后），供 K1 守卫断言。
  int get lastRollbackBeforeSeq;

  /// ★ K1 守卫（§3.1）：UI 永不提供回退入口，但适配层仍夹取 `>= 1`。
  /// 逻辑是纯函数，放这里而不是 P4 —— 不改 P4 冻结文件。
  int clampBeforeSeq(int v) => v < 1 ? 1 : v;

  /// 导出 20 键存档（KP 侧由实现覆盖；玩家/旁观恒 null）。
  /// 供 §3.4 `RoomController.saveNow` 使用，避免 UI 直接持 `RoomHost`。
  Map<String, Object?>? exportSave() => null;

  /// 局域网服务地址（P6）。null / 空串 = 本机没开局域网。
  ///
  /// 只给 KP 侧用（「复制邀请」要真实地址）；玩家/旁观恒 null。
  /// UI 据此决定是显示真实地址，还是如实说「这间房只有你自己能进」。
  String? get lanBase => null;

  /// 灌入一份（已迁移的）存档（KP 侧由实现覆盖）。
  /// 供 §3.4 `RoomController.openSave` 使用。
  void importSave(Map<String, Object?> save) {}
}
