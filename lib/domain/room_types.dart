// ============================================================
// room_types.dart — P4 房间层的全部常量 / 枚举 / 值对象
//
// 为什么用「字符串常量类」而不是 Dart enum：
//   旧版（room-model.js）的 EVT / INTENT / POLICY 键值是**逐字节**进入
//   网络信封与存档 JSON 的。Dart enum 的 `.name` 是驼峰、`.index` 是数字，
//   一旦序列化就会与旧版漂移，旧存档无法无损导入。所以这里保持
//   「类 + static const String」，值一律沿用旧版小写原值。
//
// 本文件是 P4 的**唯一常量源**：状态机、规则服务、测试三方都从这里取。
// ============================================================

/// 角色。KP 不是花名册成员（见 [kHostSeat]）。
class RoomRole {
  const RoomRole._();

  static const String kp = 'kp';
  static const String player = 'player';
  static const String spectator = 'spectator';

  /// 顺序与旧版 `ROLE` 对象字面量一致（KP → PLAYER → SPECTATOR）
  static const List<String> values = <String>[kp, player, spectator];
}

/// 房主固定座位号。花名册里**没有**房主 —— 花名册记的是「有哪些玩家/旁观者」。
///
/// ⚠️ 凡是要「从座位推身份」的地方都必须先认这个常量：
///    不能拿 `roster.get(seat)` 拿到 null 就当旁观者（那样房主自己就发不了言）。
const String kHostSeat = 'host';

/// 房间生命周期状态。
///
/// ⚠️ 不要改 [closed] 的语义：旧客户端把它当终止；只有 [ended] 事件才写
///    `meta.ended = true`。
class RoomStatus {
  const RoomStatus._();

  static const String recruiting = 'RECRUITING';
  static const String inGame = 'IN_GAME';
  static const String closed = 'CLOSED';
  static const String suspended = 'SUSPENDED';

  static const List<String> values = <String>[
    recruiting,
    inGame,
    closed,
    suspended,
  ];

  /// 状态 → 中文文案（旧版 `STATUS_TEXT`，键序一致）
  static const Map<String, String> text = <String, String>{
    recruiting: '招募中',
    inGame: '游戏中',
    closed: '已结束',
    suspended: '已挂起（可续玩）',
  };
}

/// 游戏模式。与房间生命周期状态**分开**（需求 §2.4）。
class RoomMode {
  const RoomMode._();

  static const String exploration = 'EXPLORATION';
  static const String combat = 'COMBAT';

  static const List<String> values = <String>[exploration, combat];
}

/// 回退投票状态（Q6：全部**休眠保留**，供旧存档回放）。
class RoomRewind {
  const RoomRewind._();

  static const String idle = 'IDLE';
  static const String voting = 'VOTING';
  static const String done = 'DONE';
  static const String failed = 'FAILED';

  static const List<String> values = <String>[idle, voting, done, failed];
}

/// 确认策略。null 表示「直接执行」，所以这里不含 null 成员，用 `String?` 表达。
class RoomConfirm {
  const RoomConfirm._();

  static const String twice = 'twice';
  static const String kp = 'kp';
  static const String owner = 'owner';
  static const String all = 'all';

  static const List<String> values = <String>[twice, kp, owner, all];
}

/// 可见性。**这是安全边界，不是显示开关。**
///
///   [public] → 房间内所有人（含旁观者）
///   [kp]     → 只有 KP 端持有，根本不会出现在发给别人的字节里
///   [seat]   → 只有指定 seat 收得到（逐人单发，绝不广播）
class RoomVis {
  const RoomVis._();

  static const String public = 'public';
  static const String kp = 'kp';
  static const String seat = 'seat';

  static const List<String> values = <String>[public, kp, seat];
}

/// 私有字段名白名单。命中这些键的载荷**只允许**随 [RoomVis.seat] 下发。
///
/// 这一层是「不许先广播再隐藏」的机械保证：`emit` 非 SEAT 时自动 `scrub`。
const List<String> kSecretKeys = <String>[
  'secret',
  'hidden',
  'kpOnly',
  'truth',
  'clue',
  'spoiler',
  'answer',
];

/// 应用层事件类型（KP → 玩家），恰好 27 项（附录 A）。
class RoomEvt {
  const RoomEvt._();

  static const String hello = 'hello';
  static const String members = 'members';
  static const String chat = 'chat';
  static const String dice = 'dice';
  static const String log = 'log';
  static const String scene = 'scene';
  static const String combat = 'combat';
  static const String turn = 'turn';
  static const String status = 'status';
  static const String kick = 'kick';
  static const String closed = 'closed';

  /// ⚠️ wire 值仍是 `'private'`；Dart 侧成员名加下划线只为规避保留字。
  static const String private_ = 'private';
  static const String board = 'board';
  static const String asset = 'asset';
  static const String actor = 'actor';
  static const String turnstate = 'turnstate';
  static const String check = 'check';
  static const String request = 'request';
  static const String rewind = 'rewind';
  static const String round = 'round';

  /// Q6：常量保留，reduce **无分支**（走 default），不进 `save()`。
  static const String tempCommit = 'tempcommit';
  static const String ended = 'ended';
  static const String archive = 'archive';
  static const String sceneCheck = 'scenecheck';
  static const String state = 'state';
  static const String turnAlert = 'turnalert';
  static const String opposed = 'opposed';

  /// ★ P19：KP 分发的**存档快照**（每回合 / 每 10 分钟 / 结束房间 / 结团 /
  ///   玩家加入时自动触发）。reduce **无分支**（走 default）—— 快照不参与
  ///   权威状态推导，玩家端在 session 层拦截落盘（`_captureNotice` 同款）。
  static const String saveSync = 'savesync';

  /// 恰好 28 项，顺序 = 旧版 `EVT` 字面量顺序（覆盖矩阵据此逐项断言）
  static const List<String> values = <String>[
    hello,
    members,
    chat,
    dice,
    log,
    scene,
    combat,
    turn,
    status,
    kick,
    closed,
    private_,
    board,
    asset,
    actor,
    turnstate,
    check,
    request,
    rewind,
    round,
    tempCommit,
    ended,
    archive,
    sceneCheck,
    state,
    turnAlert,
    opposed,
    saveSync,
  ];
}

/// 玩家意图（玩家 → KP），恰好 13 项（附录 A）。
class RoomIntent {
  const RoomIntent._();

  static const String sync = 'sync';
  static const String ready = 'ready';
  static const String chat = 'chat';
  static const String dice = 'dice';
  static const String char = 'char';
  static const String act = 'act';
  static const String board = 'board';
  static const String vote = 'vote';
  static const String consent = 'consent';
  static const String confirm = 'confirm';
  static const String stateSync = 'statesync';
  static const String sanCheck = 'sancheck';
  static const String opposed = 'opposed';

  static const List<String> values = <String>[
    sync,
    ready,
    chat,
    dice,
    char,
    act,
    board,
    vote,
    consent,
    confirm,
    stateSync,
    sanCheck,
    opposed,
  ];
}

/// 一条权限策略：允许的角色集合 + 确认类型（null = 直接执行）。
class RoomPolicyEntry {
  const RoomPolicyEntry(this.roles, this.confirm);

  final List<String> roles;
  final String? confirm;

  Map<String, Object?> toJson() => <String, Object?>{
        'roles': roles,
        'confirm': confirm,
      };
}

/// 62 个唯一 action（附录 B）。`board.self` 在本版本源码中只定义一次 →
/// 源码 62 行 / 62 唯一 action（旧「61 / 定义两次」注释已过时，勿据此删行）。
///
/// ⚠️ `rollback.turn` **不在**此表（入口已摘除），但 `applyAction` 分支保留。
///    `needs()` 对未登记 action 返回 `{allowed:false, confirm:null}`。
const Map<String, RoomPolicyEntry> kRoomPolicy = <String, RoomPolicyEntry>{
  'chat': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null),
  'dice.request': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null),
  'ready.set': RoomPolicyEntry(<String>[RoomRole.player], null),
  'char.share': RoomPolicyEntry(<String>[RoomRole.player], null),
  'board.self': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null),
  'state.edit.self': RoomPolicyEntry(<String>[RoomRole.player], RoomConfirm.kp),
  'state.edit.other': RoomPolicyEntry(<String>[RoomRole.kp], RoomConfirm.owner),
  'room.start': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'room.kick': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'room.close': RoomPolicyEntry(<String>[RoomRole.kp], RoomConfirm.twice),
  'room.end': RoomPolicyEntry(<String>[RoomRole.kp], RoomConfirm.twice),
  'scene.set': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'scene.reveal': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'scene.clue': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'scene.mode': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'state.request': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'asset.add': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'asset.reveal': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'asset.cover': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'asset.del': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'item.del': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null),
  'state.self': RoomPolicyEntry(<String>[RoomRole.player, RoomRole.kp], null),
  'madness.advance': RoomPolicyEntry(<String>[
    RoomRole.player,
    RoomRole.kp,
  ], null),
  'madness.cure': RoomPolicyEntry(<String>[
    RoomRole.player,
    RoomRole.kp,
  ], RoomConfirm.kp),
  'map.mark': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'map.stroke': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'map.clear': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'map.strokes.set': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.set': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.start': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.next': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.actor': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.enqueue': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.pool.set': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.attack': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null),
  'combat.damage': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.end': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'combat.roll': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], null),
  'dice.roll': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'check.request': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'check.push': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'dice.dark': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'sheet.damage': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'sheet.sancheck': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'sheet.tempstatus': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'sheet.item': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'rollback.commit': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'round.next': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'rollback.round': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'session.end': RoomPolicyEntry(<String>[RoomRole.kp], RoomConfirm.twice),
  'combat.prepare': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'scene.check.push': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'scene.check.step': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'check.opposed': RoomPolicyEntry(<String>[RoomRole.kp, RoomRole.player], RoomConfirm.kp),
  'room.suspend': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'room.resume': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'room.rules': RoomPolicyEntry(<String>[RoomRole.kp], null),
  // ★ P19：KP 把本机存档快照分发给全员（每回合 / 每 10 分钟 / 结束房间 /
  //   结团 / 玩家加入时自动触发；玩家端落盘 + 角色卡联动）。
  'save.share': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'sheet.sanloss': RoomPolicyEntry(<String>[RoomRole.kp], null),
  'sheet.healwound': RoomPolicyEntry(<String>[
    RoomRole.player,
    RoomRole.kp,
  ], RoomConfirm.kp),
  'aid.apply': RoomPolicyEntry(<String>[
    RoomRole.player,
    RoomRole.kp,
  ], RoomConfirm.kp),
  'aid.psycho': RoomPolicyEntry(<String>[
    RoomRole.player,
    RoomRole.kp,
  ], RoomConfirm.kp),
};

// ============================================================
// 值对象
// ============================================================

/// ★ Q1 关键：事件对象**持久化** `vis` / `to` / `seq`。
///
/// `vis` 可空：null ≡ 旧版「客户端 reduce / 旧调用未传 vis」→ 按 PUBLIC 处理。
/// `RoomHost.emit` 必须显式赋 vis；`RoomHost.apply` 重放必须沿用日志里这个对象。
///
/// 旧版缺陷（room-model.js:3450）在重放时只传 `{t,seq,p}`、丢掉 `vis/to`，
/// 导致 SEAT 秘密检定在回退后被写成明文。Dart 侧靠「持久化整个事件对象」修正。
class RoomEvent {
  const RoomEvent({
    required this.t,
    required this.p,
    this.vis,
    this.to,
    this.seq,
  });

  final String t;
  final Map<String, Object?> p;
  final String? vis;
  final String? to;
  final int? seq;

  RoomEvent withSeq(int s) =>
      RoomEvent(t: t, p: p, vis: vis, to: to, seq: s);

  /// 键序与旧版日志项一致：`t, vis, to, p`（seq 由日志记录持有）
  Map<String, Object?> toJson() => <String, Object?>{
        't': t,
        'vis': vis,
        'to': to,
        'p': p,
        'seq': seq,
      };
}

/// 日志记录：序号与（已带 seq 的）事件对象，二者恒等（由 `apply` 保证）。
///
/// ⚠️ 三层形状必须分清（Q1 修正的**序列化边界**，也是 `logScript` 等价性的关键）：
///   ① [evt] 是**内部事件对象**：`t/seq/p/vis/to` 五字段，只供 `RoomHost.apply` /
///      `rollback` 重放 / `reduceRoomState` 判定权限使用。旧版 :3450 重放时只传
///      `{t,seq,p}` 丢掉 vis/to，才让秘密检定在回退后变成明文；Dart 靠它修正。
///   ② [wireEvt] 是**旧版 `Log.push(evt)` 原样保存的入参对象**，即 log.items[].evt
///      与 `Log.since()` 返回的 evt：`{t[,vis,to],p}`，**不带 seq**，键集合完全
///      取决于 push 入参（旧版 :370-379 没有做任何规范化）。
///   ③ 网络出站 evt 是 [EvtEnvelope]：`{k:'evt',seq,t,p}`（旧版 :795 的
///      `evtMsg` 只取 `t`/`p`），**永远不带 vis/to**。
///
/// 本类只负责 ① 与 ②；③ 由 `evtMsg` / `RoomHost.plan` 收口。把 ② 直接写成
/// `evt.toJson()` 会多出 `{vis,to,seq}` 三个键 —— 这正是出站形状串味的根源。
class LogRecord {
  const LogRecord(this.seq, this.evt, [this.wireEvt]);

  final int seq;
  final RoomEvent evt;

  /// 旧版 `Log.push(evt)` 原样保存的入参对象（对外形状）。
  /// 为 null 时按 [evt] 推导成 `Host.emit` 的四键形状 `{t,vis,to,p}`。
  final Map<String, Object?>? wireEvt;

  /// `Log.push` / `Log.since` 对外返回的记录形状：`{seq, evt}`。
  /// evt 里**没有 seq**，也不含任何出站信封字段。
  Map<String, Object?> toWireJson() => <String, Object?>{
        'seq': seq,
        'evt': wireEvt ??
            <String, Object?>{
              't': evt.t,
              'vis': evt.vis,
              'to': evt.to,
              'p': evt.p,
            },
      };
}

/// 回退用状态快照。
class RoomSnapshot {
  const RoomSnapshot(this.seq, this.state);

  final int seq;
  final Map<String, Object?> state;
}

/// 一条「已剥离私有字段」的警告（正常路径必须为空）。
class RoomWarning {
  const RoomWarning(this.t, this.reason);

  final String t;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{'t': t, 'reason': reason};
}

// ============================================================
// 应用层信封：**只有 4 类** k（K8：两层协议不混）
// ============================================================

sealed class RoomEnvelope {
  const RoomEnvelope();

  /// 信封类型键：`sync` / `evt` / `skip` / `intent`
  String get k;

  Map<String, Object?> toJson();
}

/// KP → 玩家：全量同步（重连、首连）
class SyncEnvelope extends RoomEnvelope {
  const SyncEnvelope(this.seq, this.state);

  final int seq;
  final Map<String, Object?> state;

  @override
  String get k => 'sync';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'k': 'sync',
        'seq': seq,
        'state': state,
      };
}

/// KP → 玩家：增量事件
class EvtEnvelope extends RoomEnvelope {
  const EvtEnvelope(this.seq, this.t, this.p);

  final int seq;
  final String t;
  final Map<String, Object?> p;

  @override
  String get k => 'evt';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'k': 'evt',
        'seq': seq,
        't': t,
        'p': p,
      };
}

/// KP → 玩家：序号水位标记（这条事件与你无关，但你要把 lastSeq 推到 seq）
class SkipEnvelope extends RoomEnvelope {
  const SkipEnvelope(this.seq);

  final int seq;

  @override
  String get k => 'skip';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'k': 'skip', 'seq': seq};
}

/// 玩家 → KP：意图
class IntentEnvelope extends RoomEnvelope {
  const IntentEnvelope(this.op, this.p);

  final String op;
  final Map<String, Object?> p;

  @override
  String get k => 'intent';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'k': 'intent',
        'op': op,
        'p': p,
      };
}

/// 一条发送计划：`to` 为 `'*'` 表示广播；`msg` 是**应用层信封**。
///
/// K8：Host 对外方法一律返回 `List<SendPlan>`，不返回事件记录、不发包。
class SendPlan {
  const SendPlan(this.to, this.msg);

  final String to;
  final RoomEnvelope msg;

  Map<String, Object?> toJson() => <String, Object?>{
        'to': to,
        'msg': msg.toJson(),
      };
}
