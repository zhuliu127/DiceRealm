// ============================================================
// net/lan_client.dart — P6 房间客户端（玩家 / 旁观侧）
//
// 与旧版 room-net.js 的 PlayerSide 对应，但**更薄**：
//   · 收帧 → `RoomClient.receive()`（P4 已实现的序号闸门 + 裁剪态回放）
//   · gap → 立刻发 `sync` 补拉（旧版也这么做，不能等下一次增量）
//   · 断线 → 指数退避重连，重连后必补一次全量
//
// ★ 这一层不做任何裁剪：客户端拿到的就是 `plan()` 已经按 vis/to 算好的
//   信封。C2「不是靠 UI 隐藏」在这里成立 —— 搜不到的字段压根没收到。
//
// ⚠️ `link` 的四档与 UI 顶栏共用同一枚举（RoomLinkState），不要自造状态。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../domain/js_compat.dart' show asMap, jsStr;
import '../domain/room_model_client.dart';
import '../domain/room_types.dart';
import '../ui/room/room_session.dart' show RoomLinkState;

import 'cloud_room.dart' show ensureCloudDeviceId;
import 'room_frame.dart';

/// 重连延迟（毫秒）。旧版 RECONNECT_DELAYS 的同款思路：先快后慢，封顶。
const List<int> kReconnectDelays = <int>[500, 1000, 2000, 4000, 8000];

/// 房间客户端：连一台已经在跑 [LanServer] 的设备。
class LanClient {
  LanClient({
    required this.base,
    required this.seat,
    required this.code,
    this.role = RoomRole.player,
    this.cid = '',
  }) : client = RoomClient(seat: seat, role: role);

  /// 服务地址，形如 `http://192.168.1.7:4211`（不带尾斜杠）。
  final String base;

  /// 当前座位。**非 final**：发空 seat 时服务端会分配一个，joined 后要更新。
  String seat;

  final String code;
  final String role;

  /// ★ P16 P-1(a)：稳定设备标识，随 hello 上送供服务端按 cid 幂等复连。
  /// 空串时回退 [ensureCloudDeviceId]（进程内稳定、重启即变，见交付报告）。
  final String cid;

  /// P4 的裁剪态容器。UI 读它的 `state`。
  /// **非 final**：座位变了要重建（裁剪口径是按 seat 算的）。
  RoomClient client;

  RoomLinkState link = RoomLinkState.connecting;

  /// 全量同步世代：每「应用完成」一份 sync envelope 就 +1。
  ///
  /// 这是连接层给 UI 的**显式补拉信号**，取代「靠全局 seq 差值猜补拉」：
  /// 断线重连 / gap 自愈 / 显式 pullSync 三条路径，最终都由服务端回一个
  /// plan 帧，帧里的 msg 是 sync envelope，进 [RoomClient.receive] 整体替换
  /// state 后返回 kind=='sync' —— 只有到这一步数据才真的落地。自增发生在
  /// 已有的 onChange 通知之前，UI 同一次 build 就能读到新世代；不新增通知。
  /// 本机会话没有这个概念，恒 0；由 RemoteSession 透出给信息流闪烁使用。
  int syncEpoch = 0;

  /// 状态变化回调（由 RemoteSession 挂成 notifyListeners）。
  void Function()? onChange;

  /// 每条入站消息的原始回调（RemoteSession 用它抓 `sysTo` 定向提示）。
  /// 在 `receive()` **之前**调用，所以即使 receive 判重/判序丢弃，提示也不丢。
  void Function(Map<String, Object?> msg)? onMsg;

  WebSocket? _ws;
  StreamSubscription<Object?>? _sub;
  Timer? _retryTimer;
  int _retry = 0;
  bool _disposed = false;

  /// 断线期间缓存待发帧（对齐旧版「发送队列」）。
  final List<String> _queue = <String>[];

  bool get connected => link == RoomLinkState.connected;
  int get queued => _queue.length;

  // ----------------------------------------------------------
  // 连接
  // ----------------------------------------------------------

  /// 建连并完成 hello/joined 握手。失败返回 `ok:false`（不抛）。
  Future<RoomJoinResult> connect() async {
    if (_disposed) return RoomJoinResult.denied;
    _setLink(RoomLinkState.connecting);
    try {
      final ws = await WebSocket.connect(_wsUrl()).timeout(
        const Duration(seconds: 6),
      );
      _ws = ws;
      _retry = 0;
      _sub = ws.listen(_onData, onDone: _onClosed, onError: (Object _) => _onClosed(), cancelOnError: true);

      // ★ 先备好 waiter，再发 hello —— 服务端可能回得比我们挂监听还快，
      //   先发后挂会丢掉 joined（这类时序 bug 在真机上偶发，极难复现）。
      final waiter = Completer<RoomJoinResult>();
      _joinWaiter = waiter;
      _sendRaw(jsonEncode(RoomFrame(RoomFrameKind.hello, <String, Object?>{
        'code': code,
        'seat': seat,
        'role': role,
        // ★ P16 P-1(a)：补稳定设备标识，服务端据此复用旧座（无视 online），
        //   避免同一设备重连被分配第二个座位。
        'cid': cid.isNotEmpty ? cid : ensureCloudDeviceId(),
      }).toJson()));

      final joined = await waiter.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => RoomJoinResult(ok: false, error: 'JOIN_TIMEOUT'),
      );
      _joinWaiter = null;

      if (!joined.ok) {
        // ★ 只关连接、**不**置 _disposed —— 否则下面的 _scheduleRetry 永远重连不上。
        await _closeSocket();
        _setLink(RoomLinkState.offline);
        _scheduleRetry();
        return joined;
      }
      _setLink(RoomLinkState.connected);
      _flushQueue();
      return joined;
    } on Object catch (e) {
      _setLink(RoomLinkState.offline);
      _scheduleRetry();
      return RoomJoinResult(ok: false, error: '$e');
    }
  }

  /// 握手结果由单次 Completer 承接（joined / error 任一到达即完成）。
  Completer<RoomJoinResult>? _joinWaiter;

  /// 只关套接字，不动 `_disposed`（重连路径要用）。
  Future<void> _closeSocket() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      try {
        await ws.close(WebSocketStatus.normalClosure, 'close');
      } catch (_) {}
    }
  }

  String _wsUrl() {
    var b = base.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    final u = Uri.parse(b);
    final scheme = (u.scheme == 'https') ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: u.host,
      port: u.hasPort ? u.port : kRoomServicePort,
      path: '/ws',
    ).toString();
  }

  // ----------------------------------------------------------
  // 收帧
  // ----------------------------------------------------------

  void _onData(Object? raw) {
    final RoomFrame? f;
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final obj = jsonDecode(text);
      if (!RoomFrame.versionOk(obj)) {
        _setLink(RoomLinkState.offline);
        return;
      }
      f = RoomFrame.parse(obj);
    } catch (_) {
      return; // 坏帧丢弃，不崩连接
    }
    if (f == null) return;

    switch (f.kind) {
      case RoomFrameKind.joined:
        final r = RoomJoinResult.fromJson(f.data ?? const <String, Object?>{});
        // ★ 我们发空 seat 时，座位是服务端分配的 —— 必须换过来，
        //   否则 RoomClient 会按错座位裁剪（看到别人的数据或什么都看不到）。
        final assigned = r.seat ?? '';
        if (assigned.isNotEmpty && assigned != seat) {
          seat = assigned;
          client = RoomClient(seat: seat, role: role);
        }
        final w = _joinWaiter;
        if (w != null && !w.isCompleted) w.complete(r);
        return;

      case RoomFrameKind.error:
        final err = jsStr((f.data ?? const {})['error'] ?? 'ERROR');
        final w = _joinWaiter;
        if (w != null && !w.isCompleted) {
          w.complete(RoomJoinResult(ok: false, error: err));
        } else {
          _setLink(RoomLinkState.offline);
        }
        return;

      case RoomFrameKind.plan:
        final d = f.data ?? const <String, Object?>{};
        final msg = asMap(d['msg']);
        if (msg.isEmpty) return;
        _deliver(msg);
        return;

      case RoomFrameKind.bye:
        _setLink(RoomLinkState.offline);
        return;

      default:
        return;
    }
  }

  /// 投递给 P4 客户端；gap 立刻补拉（这是断线重连能自愈的关键）。
  void _deliver(Map<String, Object?> msg) {
    onMsg?.call(msg);
    final result = client.receive(msg);
    final body = result.toJson();
    // ★ 显式补拉信号：只有当 P4 客户端真的「应用完成」一份全量 sync
    //   （kind=='sync'，state 已被整体替换）时才推进世代。三条补拉路径
    //   （自动重连 / gap 自愈 / 显式 pullSync）最终都由这一帧汇入，不靠
    //   seq 差猜，也不把 resync→connected 误当成「已应用」。
    //   必须在任何 onChange 通知之前自增 —— UI 同一次 build 就能读到新值；
    //   下方已有通知逻辑不重复添加。
    if (result.kind == 'sync') {
      syncEpoch += 1;
      // ★ P14 P0：全量补拉落地 = 链路已经健康，把「补拉窗口内积压的意图」
      //   补发出去。旧的队列只在 connect() 成功后 flush，玩家在缺口期间点的
      //   按钮（攻击 / 掷骰）会永远滞留在 _queue 里，界面看起来「点了没反应」。
      //   ⚠️ 只在 socket 还在时 flush：`_sendRaw` 对 null socket 是静默丢弃
      //   （离线期的缓存必须留到重连后由 connect() 统一 flush）。
      if (_ws != null && _queue.isNotEmpty) _flushQueue();
    }
    if (body['gap'] == true) {
      _setLink(RoomLinkState.resync);
      requestSync();
      return;
    }
    if (link != RoomLinkState.connected) _setLink(RoomLinkState.connected);
    onChange?.call();
  }

  /// 仅供测试：把一帧**已解包的应用层消息**直接喂进 [_deliver]，用于验证
  /// 连接层显式补拉信号 [syncEpoch]，而不必起真 socket、不碰传输帧协议。
  /// 生产路径永远是 [_onData] 的 plan 分支 → [_deliver]；三条补拉路径
  /// （自动重连 / gap 自愈 / 显式 pullSync）最终都由服务端回的同一份
  /// sync envelope 汇入这里，所以这一个投帧口即可覆盖它们的共同落点。
  @visibleForTesting
  void deliverForTest(Map<String, Object?> msg) => _deliver(msg);

  // ----------------------------------------------------------
  // 发帧
  // ----------------------------------------------------------

  void sendIntent(String op, Map<String, Object?> p) {
    _send(jsonEncode(RoomFrame(RoomFrameKind.intent, <String, Object?>{
      'op': op,
      'p': p,
    }).toJson()));
  }

  void sendAct(String action, Map<String, Object?> p) {
    // ★ 与 LocalLoopbackSession.hostAction 同形状：外层 act，内层 p['op']。
    final inner = <String, Object?>{...p, 'op': action};
    _send(jsonEncode(RoomFrame(RoomFrameKind.act, <String, Object?>{
      'op': RoomIntent.act,
      'p': inner,
    }).toJson()));
  }

  void requestSync() {
    final String text =
        jsonEncode(RoomFrame(RoomFrameKind.sync, <String, Object?>{
      'lastSeq': client.lastSeq,
    }).toJson());
    // ★★ P14 P0（本单最关键的一行语义）：补拉请求必须**绕过**「connected 才
    //   发」的闸门。
    //   自愈路径是 `_deliver` 里的「先 _setLink(resync) → 再 requestSync()」，
    //   此时 `connected`（= link == connected）已经是 false，旧实现的 `_send`
    //   把这条 sync 请求塞进 `_queue`；而 `_queue` 只在 `connect()` 成功之后
    //   `_flushQueue()`。于是：检测到缺口 → 请求发不出去 → 永远收不到全量 →
    //   玩家侧常驻「补拉中」，KP 之后的 turnstate/combat 全部被序号闸门拒绝，
    //   轮次永久停在缺口那一轮（重进房 = 重新 connect → flush → 立刻补齐）。
    //   只要 socket 还在（握手早已完成，缺口只可能发生在收到过 evt/sync 之后），
    //   控制帧就直接写；socket 真的没了才排队等重连 flush（老的断线缓存语义）。
    if (_ws != null) {
      _sendRaw(text);
    } else {
      _queue.add(text);
    }
  }

  void _send(String text) {
    if (connected) {
      _sendRaw(text);
    } else {
      _queue.add(text);
    }
  }

  void _sendRaw(String text) {
    try {
      _ws?.add(text);
    } catch (_) {
      _queue.add(text);
    }
  }

  void _flushQueue() {
    final pending = List<String>.of(_queue);
    _queue.clear();
    for (final t in pending) {
      _sendRaw(t);
    }
  }

  // ----------------------------------------------------------
  // 断线 / 重连
  // ----------------------------------------------------------

  void _onClosed() {
    if (_disposed) return;
    _setLink(RoomLinkState.offline);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retryTimer?.cancel();
    final ms = kReconnectDelays[_retry.clamp(0, kReconnectDelays.length - 1)];
    _retry = (_retry + 1).clamp(0, kReconnectDelays.length - 1);
    _retryTimer = Timer(Duration(milliseconds: ms), () async {
      if (_disposed) return;
      final r = await connect();
      // 重连成功后必补一次全量：断线期间漏掉的事件不能靠增量补回来。
      if (r.ok) requestSync();
    });
  }

  void _setLink(RoomLinkState v) {
    if (link == v) return;
    link = v;
    onChange?.call();
  }

  // ----------------------------------------------------------
  // 关闭
  // ----------------------------------------------------------

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _closeSocket();
    _queue.clear();
  }
}
