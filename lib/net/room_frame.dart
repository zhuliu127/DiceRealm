// ============================================================
// net/room_frame.dart — P6 房间帧协议（局域网传输的最小信封）
//
// 设计原则（沿用旧版 room-net.js 的核心洞察）：
//   「局域网不是另一条链路，只是地址从哪来的问题。」
//   ⇒ 帧里只装 P4 已经算好的东西（`SendPlan.toJson()` / `RoomEnvelope`），
//     **不在传输层做任何裁剪或业务判断**。裁剪是 `plan()` 的职责，
//     这里照抄就对了。
//
// ★ K3 红线：本层只转发 `SendPlan`（出站信封，已按 vis/to 脱敏），
//   **禁止**碰 `LogRecord.toWireJson()`（那是日志记录，含明文 p）。
//
// ★ 协议版本独立于 app 版本：`v` 不匹配时对端应拒绝连接而不是硬解析，
//   否则一次升级就会让旧客户端拿到半懂的数据。
// ============================================================

/// 帧协议版本。加减字段可以不改；语义变了必须 +1。
const int kRoomFrameVersion = 1;

/// 房间服务端口（HTTP + WebSocket 同端口）。
const int kRoomServicePort = 4211;

/// 房间发现端口（UDP 广播）。
const int kRoomDiscoverPort = 4210;

/// 帧类型。
///
/// 只有 7 种，刻意做小：传输层不懂业务，懂业务的在 P4。
class RoomFrameKind {
  const RoomFrameKind._();

  /// 客户端 → 服务端：我要进这间房（带 code / seat / 昵称）。
  static const String hello = 'hello';

  /// 服务端 → 客户端：进来了，这是分给你的 seat + 当前水位。
  static const String joined = 'joined';

  /// 服务端 → 客户端：一条出站计划（`SendPlan.toJson()` 原样）。
  static const String plan = 'plan';

  /// 客户端 → 服务端：发一个 INTENT。
  static const String intent = 'intent';

  /// 客户端 → 服务端：发一个 ACTION（外层 act，内层 op）。
  static const String act = 'act';

  /// 客户端 → 服务端：断线补拉（带 lastSeq）。
  static const String sync = 'sync';

  /// 任一方：我要走了 / 已被踢。
  static const String bye = 'bye';

  /// 服务端 → 客户端：出错了（含 code，且**不夹带**任何房间状态）。
  static const String error = 'error';
}

/// 一条帧。
///
/// 刻意做成「扁平 + 可空 data」而不是嵌套 `{k, p:{...}}`：
/// 旧版 room-net.js 就是因为信封层层嵌套，排查时得多点两次才能看到内容。
class RoomFrame {
  const RoomFrame(this.kind, [this.data]);

  final String kind;
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() => <String, Object?>{
        'v': kRoomFrameVersion,
        'k': kind,
        ...?data,
      };

  @override
  String toString() => 'RoomFrame($kind, ${data ?? const {}})';

  /// 解析一条入站帧；形状不对返回 null（调用方丢弃，**不抛异常**）。
  ///
  /// 为什么不抛：网络对面可能是任何东西（旧版本、恶意脚本、半截 JSON）。
  /// 一条坏帧不该让整个连接崩掉，丢弃 + 计数才是对的。
  static RoomFrame? parse(Object? raw) {
    if (raw is! Map) return null;
    final k = raw['k'];
    if (k is! String || k.isEmpty) return null;
    final data = <String, Object?>{};
    for (final e in raw.entries) {
      final key = e.key;
      if (key is! String) continue;
      if (key == 'v' || key == 'k') continue;
      data[key] = e.value;
    }
    return RoomFrame(k, data);
  }

  /// 版本是否兼容。缺 `v` 视为兼容（旧版没这个字段时不该直接踢人）。
  static bool versionOk(Object? raw) {
    if (raw is! Map) return false;
    final v = raw['v'];
    if (v == null) return true;
    return v == kRoomFrameVersion;
  }
}

/// 服务端返回给客户端的「加入结果」。
class RoomJoinResult {
  const RoomJoinResult({
    required this.ok,
    this.seat,
    this.code,
    this.role,
    this.error,
    this.lastSeq = 0,
  });

  final bool ok;
  final String? seat;
  final String? code;
  final String? role;
  final String? error;
  final int lastSeq;

  static const RoomJoinResult denied = RoomJoinResult(
    ok: false,
    error: 'JOIN_DENIED',
  );

  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        if (seat != null) 'seat': seat,
        if (code != null) 'code': code,
        if (role != null) 'role': role,
        if (error != null) 'error': error,
        'lastSeq': lastSeq,
      };

  static RoomJoinResult fromJson(Map<String, Object?> m) {
    final seq = m['lastSeq'];
    return RoomJoinResult(
      ok: m['ok'] == true,
      seat: m['seat'] as String?,
      code: m['code'] as String?,
      role: m['role'] as String?,
      error: m['error'] as String?,
      lastSeq: seq is num ? seq.toInt() : 0,
    );
  }
}
