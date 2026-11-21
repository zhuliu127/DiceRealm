// ============================================================
// room_session_local.dart — 同进程环回会话（P5 玩家/旁观视角的前提）
//
// PRD §9.4 Q-P5-1：P5 不做 P6 传输，但玩家视图必须来自**真正被裁剪过的
// 数据**，不能拿 host.state 假装。做法是把 `host.intent()` 产出的
// `List<SendPlan>` 逐条喂给本机注册的 `RoomClient.receive()`：
//   · `to == '*'`  → 全员投递；
//   · `to == seat` → 单发；
//   · 其余座位由权威端 `plan()` 自己发 `skip` 水位（照投即可）。
// 这样 `plan()` 的裁剪、`skip` 消费、`receive()` 的序号闸门全都被真实跑到。
//
// ★ 一个房间可以有**多份视角**（KP + N 玩家 + M 旁观），它们共享同一个
//   host / clients 注册表 / 发送记录 / 通知，由 [RoomLoopbackHub] 承载；
//   [viewFor] 派生共享视图。任一视角发 intent → 一次泵 → 所有视角重建。
//
// ⚠️ 本文件是 UI 层**唯一**持有 `RoomHost` 的地方（连同 RoomController 通过
//    端口间接持有）；widget / view / painter / sheets 一律不碰 Host。
// ============================================================

import '../../domain/js_compat.dart';
import '../../domain/room_model_client.dart';
import '../../domain/room_model_envelope.dart' show cloneRoomMap;
import '../../domain/room_model_host_core.dart';
import '../../domain/room_model_host_intent.dart';
import '../../domain/room_model_rollback.dart';
import '../../domain/room_model_save.dart';
import '../../domain/room_ports.dart';
import '../../domain/room_types.dart';

import 'room_session.dart';

/// 一个环回房间的共享内核。多个 [LocalLoopbackSession] 视角引用同一份，
/// 保证「一次泵 → 所有 client 都被投递 + 所有视角都收到通知」。
///
/// 设计 §3.3 把 `clients` / `sentLog` 写成 session 自己的字段；这里把它们
/// 做成指向 hub 的**同一个 Map/List 引用**，字段名与类型一字不改。
class RoomLoopbackHub {
  RoomLoopbackHub(this.host);

  final RoomHost host;

  /// seat → client（含玩家与旁观；KP 不注册，直接读 host.state）。
  final Map<String, RoomClient> clients = <String, RoomClient>{};

  /// 权威端出站信封记录（`SendPlan.toJson()` 原样）。
  final List<Map<String, Object?>> sentLog = <Map<String, Object?>>[];

  /// UI 侧发出的 intent / action 记录（§6.1 `sent` 的来源）。
  final SessionSendLog sent = SessionSendLog();

  /// 所有已派生视角（泵完统一通知）。
  final List<LocalLoopbackSession> views = <LocalLoopbackSession>[];

  /// 连接态（三档）。
  RoomLinkState link = RoomLinkState.connected;

  /// 上一次 rollback 实际使用的 beforeSeq（K1 守卫断言用）。
  int lastRollbackBeforeSeq = 1;

  /// 防止 gap 自愈无限递归。
  int resyncDepth = 0;

  /// 泵完统一通知，避免某个视角没重建。
  void notifyAll() {
    for (final v in views) {
      v.refresh();
    }
  }
}

/// 同进程环回会话：**把 `List<SendPlan>` 直接喂给 `client.receive()`**。
class LocalLoopbackSession extends RoomSession {
  LocalLoopbackSession({
    required this.host,
    required this.seat,
    required this.role,
    RoomClient? client,
    RoomLoopbackHub? hub,
    void Function(Map<String, Object?> save)? onSharedSave,
  }) : _hub = hub ?? RoomLoopbackHub(host) {
    if (client != null) _hub.clients[seat] = client;
    _hub.views.add(this);
    // ★ P20 M9：改赋值到基类继承字段（RoomSession.onSharedSave）。
    //   语义与改造前完全一致；不能用 this.onSharedSave 形参初始化继承字段。
    this.onSharedSave = onSharedSave;
  }

  /// 内部派生（共享 hub）；对外走 [viewFor]。
  LocalLoopbackSession._(this.host, this.seat, this.role, this._hub) {
    _hub.views.add(this);
  }

  /// KP 与所有 player client 共处一进程（设计 §3.3 的 public 字段）。
  final RoomHost host;

  @override
  final String seat;

  @override
  final String role;

  final RoomLoopbackHub _hub;

  // ★ P20 M9：onSharedSave 字段已上提到基类 RoomSession（默认 null）。
  //   _captureNotice 的 savesync 分支仍按 role 判断，KP 自己跳过重复落盘。

  /// seat → client（设计 §3.3 签名；实际是 hub 里那一份）。
  late final Map<String, RoomClient> clients = _hub.clients;

  /// 测试断言用：所有**出站**信封（设计 §3.3 签名）。
  late final List<Map<String, Object?>> sentLog = _hub.sentLog;

  /// 派生同一房间的另一个视角（共享 host / clients / sentLog / 通知）。
  LocalLoopbackSession viewFor(String viewSeat, String viewRole) =>
      LocalLoopbackSession._(host, viewSeat, viewRole, _hub);

  /// 供 hub 统一通知（绕开 `notifyListeners()` 的 @protected 限制）。
  void refresh() => notifyListeners();

  @override
  String get code => jsStr(asMap(host.state['meta'])['code'] ?? '');

  @override
  Map<String, Object?> get state {
    if (role == RoomRole.kp) return host.state;
    final c = clients[seat];
    // 未注册时给空态而不是抛异常：房间页/入口页在 attach 之前也可能读。
    return c == null ? const <String, Object?>{} : c.state;
  }

  @override
  RoomLinkState get link => _hub.link;

  /// 设置连接态（P6 的 RemoteSession / 测试用）。
  void setLink(RoomLinkState value) {
    if (_hub.link == value) return;
    _hub.link = value;
    _hub.notifyAll();
  }

  @override
  int get lastSeq =>
      role == RoomRole.kp ? host.log.seq : (clients[seat]?.lastSeq ?? 0);

  @override
  String? get lastNotice => _lastNotice;
  String? _lastNotice;

  @override
  RoomHostRead? get hostRead =>
      role == RoomRole.kp ? RoomHostRead(host) : null;

  @override
  SessionSendLog get sent => _hub.sent;

  @override
  List<String> get seats => <String>[
        kHostSeat,
        for (final s in clients.keys)
          if (s != kHostSeat) s,
      ];

  /// 注册一个客户端视图（玩家/旁观）。重复注册同 seat 覆盖。
  void attach(String clientSeat, RoomClient c) {
    _hub.clients[clientSeat] = c;
  }

  void detach(String clientSeat) => _hub.clients.remove(clientSeat);

  /// ★ 唯一泵：把权威端产出的计划投递到本机所有注册 client。
  ///
  /// 顺序必须与 seq 一致（`planAll` 已保证），否则玩家端会判成乱序。
  void pumpPlans(List<SendPlan> plans) {
    for (final p in plans) {
      _hub.sentLog.add(p.toJson());
      if (p.to == '*') {
        for (final c in clients.values) {
          _deliver(c, p.msg);
        }
      } else {
        // KP 的 plan 也可能 to:'host'；没注册 client 时静默跳过。
        final c = clients[p.to];
        if (c != null) _deliver(c, p.msg);
      }
      // 定向提示按「收件人视角」分别抓取：泵可能由任一视角发起，
      // 但只有收件人自己的 banner 该显示这条 sysTo（K7 不弹模态）。
      for (final view in _hub.views) {
        view._captureNotice(p);
      }
    }
    _hub.notifyAll(); // ★ KP 侧 state 已变，必须通知（K2 第 1 条）
  }

  /// 单条投递 + 缺口自愈。`receive()` 的返回体里只有两种要动作：
  ///   · `gap:true` → 立刻自报 `INTENT.SYNC` 补拉（P6 网络版也要这一手）；
  ///   · `dup:true` → 忽略（正常，重连补拉必然有重复）。
  void _deliver(RoomClient c, RoomEnvelope msg) {
    final result = c.receive(msg.toJson());
    final body = result.toJson();
    if (body['gap'] != true) return;
    if (_hub.resyncDepth >= 2) return; // 防御：补拉又出缺口时不再递归
    _hub.resyncDepth += 1;
    try {
      final plans = host.intent(
        c.seat,
        <String, Object?>{
          'op': RoomIntent.sync,
          'p': <String, Object?>{'lastSeq': c.lastSeq},
        },
      );
      pumpPlans(plans);
    } finally {
      _hub.resyncDepth -= 1;
    }
  }

  /// 权威端是否给我发过 KICK（见 [RoomSession.kickedByHost]）。
  @override
  bool get kickedByHost => _kicked;
  bool _kicked = false;

  /// 最近一次 TEMP_COMMIT 的回合号（见 [RoomSession.lastTempCommitRound]）。
  @override
  int get lastTempCommitRound => _tempCommitRound;
  int _tempCommitRound = 0;

  /// 抓权威端的定向系统提示（`sysTo` → `EVT.PRIVATE` + `kind:'sys'`）。
  /// 玩家/旁观只记发给**本座位**的那条；KP 是权威端，能看到所有定向提示
  /// （设计 §3.1「权威端最近一次的定向提示」）。不弹模态、不阻断（K7）。
  void _captureNotice(SendPlan plan) {
    final mine = plan.to == seat || plan.to == '*' || role == RoomRole.kp;
    if (!mine) return;
    final m = plan.msg.toJson();
    // KICK 是**只发给我**的那一条：收到即「我被移出房间了」。
    if (plan.to == seat && m['k'] == 'evt' && m['t'] == RoomEvt.kick) {
      _kicked = true;
      return;
    }
    // TEMP_COMMIT（P10 第 2 期 A）：只认**广播**（to=='*'）的那条 —— 这是
    // 权威端在回合出口最后发的「临时卡生效」信号，玩家侧据此把本房本卡的
    // 临时卡覆盖回原卡（见 [`RoomSession.lastTempCommitRound`]）。
    if (m['k'] == 'evt' && m['t'] == RoomEvt.tempCommit) {
      final round = asMap(m['p'])['round'];
      if (round is num && round > 0) _tempCommitRound = round.toInt();
      return;
    }
    // ★ P19：KP 分发的存档快照 —— 交给回调落盘（见 [onSharedSave]）。
    //   KP 自己跳过：本机在 `saveNow` 里已写过同一份，重复写只是浪费。
    if (m['k'] == 'evt' && m['t'] == RoomEvt.saveSync) {
      final save = asMap(asMap(m['p'])['save']);
      if (save.isNotEmpty && role != RoomRole.kp) {
        onSharedSave?.call(Map<String, Object?>.from(save));
      }
      return;
    }
    if (m['k'] != 'evt' || m['t'] != RoomEvt.private_) return;
    final p = asMap(m['p']);
    if (jsStr(p['kind'] ?? '') != 'sys') return;
    final text = jsStr(p['text'] ?? '');
    if (text.isNotEmpty) _lastNotice = text;
  }

  @override
  Future<void> sendIntent(String op, Map<String, Object?> p) async {
    _hub.sent.add('intent', op, p);
    final plans = host.intent(
      seat,
      <String, Object?>{'op': op, 'p': cloneRoomMap(p)},
    );
    pumpPlans(plans);
  }

  @override
  Future<void> hostAction(String action, [Map<String, Object?>? p]) async {
    // ★ 双层：外层 op='act'，内层 p['op'] 才是 action 名（§0.1）。
    final inner = <String, Object?>{...cloneRoomMap(p ?? const {}), 'op': action};
    _hub.sent.add('action', action, inner);
    final plans = host.intent(
      seat,
      <String, Object?>{'op': RoomIntent.act, 'p': inner},
    );
    pumpPlans(plans);
  }

  @override
  Future<void> sendAction(String action, Map<String, Object?> p) async =>
      hostAction(action, p);

  @override
  Future<void> pullSync([String? targetSeat]) async {
    final s = targetSeat ?? seat;
    final c = clients[s];
    if (c == null) return;
    // sync 信封在 receive() 里走「整体替换 + 设 lastSeq」分支，跳过序号闸门，
    // 正是断线重连需要的语义（设计 §3.1 / 预置稿 pullSync(seat)）。
    c.receive(host.syncFor(s).toJson());
    _hub.notifyAll();
  }

  @override
  Map<String, Object?> stateFor(String clientSeat) {
    if (clientSeat == kHostSeat) return host.state;
    final c = clients[clientSeat];
    if (c != null) return c.state;
    // 未注册也能拿到「按 seat 裁剪过」的视图（夹具跨视角对比用）。
    return asMap(host.syncFor(clientSeat).toJson()['state']);
  }

  @override
  RollbackResult rollback(int beforeSeq) {
    final clamped = clampBeforeSeq(beforeSeq);
    _hub.lastRollbackBeforeSeq = clamped;
    final result = host.rollback(clamped);
    // 回退后给每个 client 重发全量，保证客户端水位与权威端一致。
    for (final s in clients.keys) {
      clients[s]!.receive(host.syncFor(s).toJson());
    }
    _hub.notifyAll();
    return result;
  }

  @override
  int get lastRollbackBeforeSeq => _hub.lastRollbackBeforeSeq;

  @override
  Map<String, Object?>? exportSave() =>
      role == RoomRole.kp ? host.save() : null;

  @override
  void importSave(Map<String, Object?> save) {
    // ★ P19 放宽：本机续玩的**玩家视角**也允许灌档。判定 = 存档带
    //   `meta.role` 标记（`RoomSaveSyncer._tagSave` 落盘时打的 —— 只有
    //   本机存档会有；远端会话 / 玩家随手造的裁剪态没有）。P16 的守卫
    //   防「玩家把裁剪态当权威写回」，P19 的玩家存档是 KP 广播的**全量
    //   快照**，本机 host 就是它自己的权威端，adopt 是安全的。
    final meta = asMap(save['meta']);
    final localResume = meta.containsKey('role');
    if (role != RoomRole.kp && !localResume) return;
    host.adoptSave(save);
    for (final s in clients.keys) {
      clients[s]!.receive(host.syncFor(s).toJson());
    }
    _hub.notifyAll();
  }

  @override
  void dispose() {
    // 本实现不向 client 注入 onChange（统一由 pumpPlans 通知），因此没有
    // 需要摘的回调；只需从共享 hub 摘掉自己，再走 ChangeNotifier 的清理。
    _hub.views.remove(this);
    super.dispose();
  }
}
