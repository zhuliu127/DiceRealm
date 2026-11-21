// ============================================================
// room_session_cloud.dart — 公网中继的两个会话实现（P10 第 1 期 B5）
//
// 与局域网那两个实现**一一对应**，只是转发者从「本机 LanServer」换成
// 「云端中继」：
//
//   KP    ：LocalLoopbackSession → HostingLocalSession（+ LanServer）
//                               → CloudHostingSession（+ CloudRoomHostLink）
//   玩家  ：RemoteSession（+ LanClient）
//                               → CloudRemoteSession（+ CloudRoomClient）
//
// 为什么单独写两个类而不是在既有类里加分支：
//   `room_session_hosting.dart` 的注释已经把这条理由写清楚了 —— 往成熟的
//   局域网路径里插分支，一旦网络出问题就会连累单机玩法。分开写，两条路
//   互不影响，各自的失败模式也只影响自己。
//
// ★ 三者对 UI 完全同形（都实现 `RoomSession`），所以页面不用知道自己
//   在跑局域网还是公网。
// ============================================================

import '../../domain/js_compat.dart' show asMap, asList;
import '../../domain/room_ports.dart' show RollbackResult;
import '../../domain/room_types.dart' show RoomEvt, SendPlan;
import '../../net/cloud_room.dart' show CloudRoomClient, CloudRoomHostLink;
import 'room_text.dart' show roomText;

// 私有字段无法作为命名初始化形参，只能走初始化列表（同 room_session_remote.dart）。
// ignore_for_file: prefer_initializing_formals

import 'room_session.dart';
import 'room_session_local.dart';

/// KP 视角（本机 + 公网中继双投递）。
class CloudHostingSession extends LocalLoopbackSession {
  CloudHostingSession({
    required super.host,
    required super.seat,
    required super.role,
    required this.cloudLink,
    super.client,
    super.hub,
  }) {
    // 中继送来的玩家动作 / 加入 → 权威端已经算出计划，这里接回来继续泵：
    // 一份给本机（KP 界面立刻更新），一份再经 cloudLink 发回中继。
    cloudLink.onPlans = pumpPlans;
  }

  /// ⚠️ 不能叫 `link`：`RoomSession.link` 是「连接态」getter，同名会撞车。
  final CloudRoomHostLink cloudLink;

  /// 公网中继基地址（界面「邀请同伴」要展示这个）。
  String get cloudBase => cloudLink.base;

  /// 房间号（云端分配 / 本机预分配，两者一致）。
  String get cloudCode => cloudLink.code;

  bool _closed = false;

  @override
  void pumpPlans(List<SendPlan> plans) {
    // 先走本机（单机玩法不因网络退化），再发中继。
    super.pumpPlans(plans);
    cloudLink.pump(plans);
  }

  /// 关房：先断中继再销毁本机会话（顺序反了会让中继里还留着连接）。
  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    await cloudLink.stop();
    super.dispose();
  }

  /// 与 [HostingLocalSession] 同一约定：UI 走同步 `dispose()`，
  /// 所以这里也必须发起停链路（幂等）。
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    cloudLink.stop();
    super.dispose();
  }
}

/// 玩家 / 旁观视角（经云端中继）。
class CloudRemoteSession extends RoomSession {
  CloudRemoteSession({required CloudRoomClient client, required String roomCode})
      : _client = client,
        _code = roomCode {
    // 回调在这里统一挂（与 `RemoteSession` 同口径：连接层只通知，不改状态）。
    _client.onChange = _notify;
    _client.onMsg = _captureNotice;
  }

  final CloudRoomClient _client;
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
  RoomLinkState get link =>
      _client.connected ? RoomLinkState.connected : RoomLinkState.offline;

  @override
  int get lastSeq => _client.client.lastSeq;

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
  List<String> get seats => <String>[
        for (final m in asList(state['members']))
          if (roomText(asMap(m)['seat']).isNotEmpty)
            roomText(asMap(m)['seat']),
      ];

  @override
  Future<void> sendIntent(String op, Map<String, Object?> p) async {
    _sent.add('intent', op, p);
    _client.sendIntent(op, p);
  }

  @override
  Future<void> hostAction(String action, [Map<String, Object?>? p]) async {
    final inner = <String, Object?>{
      ...(p ?? const <String, Object?>{}),
      'op': action,
    };
    _sent.add('action', action, inner);
    _client.sendAct(action, p ?? const <String, Object?>{});
  }

  @override
  Future<void> pullSync([String? targetSeat]) async {
    if (targetSeat != null && targetSeat != seat) return;
    _client.requestSync();
  }

  @override
  Map<String, Object?> stateFor(String targetSeat) {
    if (targetSeat == seat) return state;
    return const <String, Object?>{};
  }

  @override
  RollbackResult rollback(int beforeSeq) {
    final clamped = clampBeforeSeq(beforeSeq);
    _lastRollbackBeforeSeq = clamped;
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

  void _notify() => notifyListeners();

  /// 权威端是否给我发过 KICK（见 [RoomSession.kickedByHost]）。
  @override
  bool get kickedByHost => _kicked;
  bool _kicked = false;

  /// 最近一次 TEMP_COMMIT 的回合号（见 [RoomSession.lastTempCommitRound]）。
  @override
  int get lastTempCommitRound => _tempCommitRound;
  int _tempCommitRound = 0;

  void _captureNotice(Map<String, Object?> msg) {
    if (msg['k'] == 'evt' && msg['t'] == RoomEvt.kick) {
      _kicked = true;
      return;
    }
    // TEMP_COMMIT：与局域网远端同一口径（见 RemoteSession._captureNotice）。
    if (msg['k'] == 'evt' && msg['t'] == RoomEvt.tempCommit) {
      final round = asMap(msg['p'])['round'];
      if (round is num && round > 0) _tempCommitRound = round.toInt();
      return;
    }
    // ★ P20 N-3：KP 分发的存档快照（save.share → RoomEvt.saveSync）。
    //   真实联网玩家会话此前不处理该事件 → share/<code>/latest 从未落盘。
    //   exportSave()==null / importSave() no-op 的玩家非权威契约逐字不动。
    if (msg['k'] == 'evt' && msg['t'] == RoomEvt.saveSync) {
      final Map<String, Object?> save = asMap(asMap(msg['p'])['save']);
      if (save.isNotEmpty) {
        onSharedSave?.call(Map<String, Object?>.from(save));
      }
      return;
    }
    if (msg['k'] != 'evt' || msg['t'] != RoomEvt.private_) return;
    final p = asMap(msg['p']);
    if (roomText(p['kind']) != 'sys') return;
    final text = roomText(p['text']);
    if (text.isNotEmpty) _lastNotice = text;
  }

  bool _disposed = false;

  /// 离开房间时真的关掉中继连接（幂等）。理由同 `RemoteSession.closeConnection`。
  Future<void> closeConnection() async {
    _client.onChange = null;
    _client.onMsg = null;
    await _client.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.onChange = null;
    _client.onMsg = null;
    super.dispose();
  }
}
