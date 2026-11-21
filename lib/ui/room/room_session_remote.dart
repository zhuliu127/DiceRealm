// ============================================================
// ui/room/room_session_remote.dart — P6 远端会话（玩家 / 旁观）
//
// 与 `LocalLoopbackSession` 的关系：**同一个抽象的两个实现**。
//   · LocalLoopback：`List<SendPlan>` 直接喂本机 `client.receive()`；
//   · Remote       ：同样的消息经 WebSocket 过来，再喂 `client.receive()`。
// 所以 UI 层完全不知道自己在跑哪种会话 —— 这正是 P5 留 `RoomSession`
// 端口的目的（旧版注释那句「局域网不是另一条链路」的落地）。
//
// ★ 与 Loopback 的三处**刻意差异**：
//   1. `hostRead` 恒 null —— 玩家/旁观没有权威只读面（拿不到就是拿不到）；
//   2. `exportSave` 恒 null / `importSave` no-op —— 存档是 KP 的事；
//   3. `rollback` 返回空结果 —— UI 永不提供回退入口（K1），
//      但契约要求有返回值，给一个「没回退任何东西」的结果而不是抛异常，
//      免得某个诊断路径上把页面打崩。
// ============================================================

import '../../domain/js_compat.dart' show asMap, asList, jsStr;
import '../../domain/room_ports.dart' show RollbackResult;
import '../../domain/room_types.dart';
import '../../net/lan_client.dart';

import 'room_session.dart';

// 私有字段（_client / _code）无法作为命名初始化形参，只能走初始化列表。
// ignore_for_file: prefer_initializing_formals

/// 远端视角会话：一份网络连接对应一个实例。
class RemoteSession extends RoomSession {
  RemoteSession({
    required LanClient client,
    required String roomCode,
  })  : _client = client,
        _code = roomCode {
    _client.onChange = _notify;
    _client.onMsg = _captureNotice;
  }

  final LanClient _client;
  final String _code;
  final SessionSendLog _sent = SessionSendLog();

  String? _lastNotice;

  @override
  String get code => _code;

  @override
  String get seat => _client.seat;

  @override
  String get role => _client.role;

  @override
  Map<String, Object?> get state => _client.client.state;

  @override
  RoomLinkState get link => _client.link;

  @override
  int get lastSeq => _client.client.lastSeq;

  /// ★ 连接层显式补拉信号：透出 [LanClient.syncEpoch]。
  ///
  /// 重连时本对象不换（座位不变 → client 不重建，`onChange` 只通知），
  /// 所以 UI 没法靠 `identical(session, old)` 感知补拉；信息流闪烁改由
  /// 这个世代值的变化触发 `reset()`。每完成一份全量 sync 就 +1。
  @override
  int get syncEpoch => _client.syncEpoch;

  @override
  String? get lastNotice => _lastNotice;

  /// 玩家/旁观没有权威只读面。
  @override
  RoomHostRead? get hostRead => null;

  @override
  SessionSendLog get sent => _sent;

  @override
  List<String> get seats {
    final out = <String>[];
    for (final m in asList(state['members'])) {
      final s = jsStr(asMap(m)['seat'] ?? '');
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  // ----------------------------------------------------------
  // 发送
  // ----------------------------------------------------------

  @override
  Future<void> sendIntent(String op, Map<String, Object?> p) async {
    _sent.add('intent', op, p);
    _client.sendIntent(op, p);
  }

  @override
  Future<void> hostAction(String action, [Map<String, Object?>? p]) async {
    // 与 LocalLoopback 同形状：外层 act、内层 p['op'] 才是 action 名。
    final inner = <String, Object?>{...(p ?? const <String, Object?>{}), 'op': action};
    _sent.add('action', action, inner);
    _client.sendAct(action, p ?? const <String, Object?>{});
  }

  // ----------------------------------------------------------
  // 补拉
  // ----------------------------------------------------------

  @override
  Future<void> pullSync([String? targetSeat]) async {
    // 远端只能补拉**自己**那份：别人的数据本来就没发给你（C2）。
    if (targetSeat != null && targetSeat != seat) return;
    _client.requestSync();
  }

  /// 远端只持有自己视角 —— 跨视角读在结构上不可能（不是被禁止，是拿不到）。
  @override
  Map<String, Object?> stateFor(String targetSeat) {
    if (targetSeat == seat) return state;
    return const <String, Object?>{};
  }

  // ----------------------------------------------------------
  // K1 / 存档（非 KP 侧不支持）
  // ----------------------------------------------------------

  @override
  RollbackResult rollback(int beforeSeq) {
    final clamped = clampBeforeSeq(beforeSeq);
    _lastRollbackBeforeSeq = clamped;
    // UI 侧没有回退入口；真被调到也只是「什么都没发生」。
    return RollbackResult(dropped: 0, seq: lastSeq, from: clamped);
  }

  int _lastRollbackBeforeSeq = 1;

  @override
  int get lastRollbackBeforeSeq => _lastRollbackBeforeSeq;

  @override
  Map<String, Object?>? exportSave() => null;

  @override
  void importSave(Map<String, Object?> save) {
    // 存档是 KP 的职责，这里刻意什么都不做。
  }

  // ----------------------------------------------------------
  // 内部
  // ----------------------------------------------------------

  void _notify() => notifyListeners();

  /// 权威端是否给我发过 KICK（见 [RoomSession.kickedByHost]）。
  @override
  bool get kickedByHost => _kicked;
  bool _kicked = false;

  /// 最近一次 TEMP_COMMIT 的回合号（见 [RoomSession.lastTempCommitRound]）。
  @override
  int get lastTempCommitRound => _tempCommitRound;
  int _tempCommitRound = 0;

  /// 抓权威端的定向提示（与 LocalLoopbackSession._captureNotice 同口径）。
  /// 不弹模态、不阻断（K7）。
  void _captureNotice(Map<String, Object?> msg) {
    if (msg['k'] == 'evt' && msg['t'] == RoomEvt.kick) {
      _kicked = true;
      return;
    }
    // TEMP_COMMIT（P10 第 2 期 A）：权威端在回合出口**最后**发的「临时卡生效」
    // 信号。玩家侧据此把本房本卡的临时卡覆盖回原卡（见 lastTempCommitRound）。
    if (msg['k'] == 'evt' && msg['t'] == RoomEvt.tempCommit) {
      final round = asMap(msg['p'])['round'];
      if (round is num && round > 0) _tempCommitRound = round.toInt();
      return;
    }
    // ★ P20 N-3：KP 分发的存档快照（save.share → RoomEvt.saveSync）。
    //   真实联网玩家会话此前不处理该事件 → share/<code>/latest 从未落盘，
    //   ③ 区无玩家续玩条目。交给 RoomSaveSyncer 构造期注入的落盘回调。
    //   exportSave()==null / importSave() no-op 的玩家非权威契约不变。
    if (msg['k'] == 'evt' && msg['t'] == RoomEvt.saveSync) {
      final Map<String, Object?> save = asMap(asMap(msg['p'])['save']);
      if (save.isNotEmpty) {
        onSharedSave?.call(Map<String, Object?>.from(save));
      }
      return;
    }
    if (msg['k'] != 'evt' || msg['t'] != RoomEvt.private_) return;
    final p = asMap(msg['p']);
    if (jsStr(p['kind'] ?? '') != 'sys') return;
    final text = jsStr(p['text'] ?? '');
    if (text.isNotEmpty) _lastNotice = text;
  }

  bool _disposed = false;

  /// 真的关掉底层连接（离开房间时调用；幂等）。
  ///
  /// 与 [dispose] 的分工：`dispose` 只摘回调（连接“可能”是共享的），
  /// 而**离开房间**必须把连接关掉 —— 否则：
  ///   · 被踢 / 主动退房后，服务端仍认为这个座位的 socket 还在，
  ///     玩家再点「加入」会开第二条连接，服务端按「同座重复连接」把新的顶掉
  ///     （真机表现就是「离开后再也进不去」）；
  ///   · KP 关房后，玩家侧的 socket 会一直重连到一个已经不存在的房间。
  Future<void> closeConnection() async {
    _client.onChange = null;
    _client.onMsg = null;
    await _client.dispose();
  }

  /// ★ 幂等：UI 里 `State.dispose()` 与路由 pop 常常会各调一次，
  ///   第二次直接 `super.dispose()` 会抛「used after being disposed」。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.onChange = null;
    _client.onMsg = null;
    // 连接由调用方负责关闭（可能是共享的），这里只摘回调。
    super.dispose();
  }
}
