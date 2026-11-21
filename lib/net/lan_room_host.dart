// ============================================================
// net/lan_room_host.dart — 「这台设备当服务器」的编排门面
//
// 为什么要有这一层：
//   LanServer 只管收发；LanBroadcaster 只管广播；RoomAnnounce 只管形状。
//   如果让 UI 自己去 new 三个对象、自己保证「起服务失败就别广播」
//   「停服务必须连广播一起停」，迟早会出现「服务停了但还在被搜到」的幽灵房。
//
//   所以生命周期收在一个对象里：start() 要么全成，要么全不成；
//   stop() 一定把三样都收干净。
//
// ★ 对应旧版 room-lan.js 的 start()/stop()，但 Dart 侧不需要 AndroidBridge
//   —— 那层「委托给外壳」在这里消失了，因为 Dart 能直接开 socket。
// ============================================================

import '../domain/js_compat.dart' show asList, asMap, jsStr;
import '../domain/room_model_host_core.dart';
import '../domain/room_types.dart';

import 'lan_discovery.dart';
import 'lan_server.dart';
import 'room_frame.dart';

/// 一台设备当房间服务器的完整生命周期。
class LanRoomHost {
  LanRoomHost({
    required this.host,
    this.servicePort = kRoomServicePort,
    this.discoverPort = kRoomDiscoverPort,
    this.discoverTarget = '255.255.255.255',
    this.beatEvery = const Duration(seconds: 1),
  });

  final RoomHost host;
  final int servicePort;
  final int discoverPort;

  /// 广播心跳间隔。生产 1 秒够了；测试要调短，否则扫描窗口内可能
  /// 恰好错过一次心跳（第一次 beat 发生在调用方还没绑定监听端口时）。
  final Duration beatEvery;

  /// 广播目标地址（测试可传 127.0.0.1）。
  final String discoverTarget;

  LanServer? _server;
  LanBroadcaster? _caster;
  LanServerStart? _last;

  /// 权威端计划的下游（转给内部的 LanServer）。
  /// 构造时服务未必已启动，所以先缓存在这里，start() 后再应用。
  void Function(List<SendPlan>)? _onHostPlans;

  set onHostPlans(void Function(List<SendPlan>)? v) {
    _onHostPlans = v;
    _server?.onHostPlans = v;
  }

  bool get running => _server?.running == true;

  /// 当前服务地址（未启动时为空串）。
  ///
  /// ★ 运行中一律**问活的服务对象**：它按 socket 上的真端口现算。
  ///   `_last` 只是「启动那一刻的快照」，拿快照当唯一真相，一旦端口与
  ///   快照不同源，界面就会长期显示一个没人监听的地址。
  String get base {
    final LanServer? s = _server;
    if (s != null && s.running) return s.base;
    return _last?.base ?? '';
  }

  /// 实际绑定的端口（`servicePort: 0` 时由系统分配）。
  /// 本机自连/测试用这个，别用 [base] —— base 可能是别的网卡。
  int get port => _server?.boundPort ?? 0;

  /// 是否拿到了真正的局域网地址。
  /// `false` ⇒ 这间房只有自己能进，界面必须在建房前提示。
  bool get wifi => _last?.wifi ?? false;

  int get peerCount => _server?.peerCount ?? 0;

  /// 启动服务 + 广播。
  ///
  /// 失败时**不留下半启动状态**：服务起不来就不广播（否则别人能搜到一间
  /// 连不进去的房，比搜不到更糟）。
  Future<LanServerStart> start() async {
    if (running) {
      return _last ??
          const LanServerStart(ok: false, error: 'ALREADY_RUNNING');
    }

    final LanServer server = LanServer(host: host, port: servicePort);
    final LanServerStart res = await server.start();
    if (!res.ok) {
      await server.stop();
      _last = res;
      return res;
    }
    _server = server;
    _last = res;
    // 补上构造期就设置好的下游（见 _onHostPlans 注释）。
    server.onHostPlans = _onHostPlans;

    final LanBroadcaster caster = LanBroadcaster(
      targetPort: discoverPort,
      targetAddress: discoverTarget,
    );
    final bool ok = await caster.start(announce, every: beatEvery);
    if (ok) {
      _caster = caster;
    }
    // 广播起不来不算失败：同网段手输地址仍能加入，只是搜不到而已。
    return res;
  }

  /// 停服务（连广播一起停）。幂等。
  Future<void> stop() async {
    await _caster?.stop();
    _caster = null;
    await _server?.stop();
    _server = null;
    _last = null;
  }

  /// 权威端出站计划的泵（由 LocalLoopbackSession.pumpPlans 或控制器调用）。
  void pump(List<SendPlan> plans) => _server?.pump(plans);

  /// 房间状态变化后主动推一次广播，不等心跳（人数变了界面上要立刻看到）。
  void announceNow() => _caster?.beat(announce);

  /// 从权威态拼出对外摘要。
  ///
  /// ⚠️ 只放**公开**字段：房号、房名、KP 名、人数、状态、地址。
  ///    绝不带 members 明细 / 场景 / 日志 —— 广播是明文的，同网段谁都能收。
  RoomAnnounce announce() {
    final Map<String, Object?> meta = asMap(host.state['meta']);
    var players = 0;
    var spectators = 0;
    for (final Object? m in asList(host.state['members'])) {
      final String r = jsStr(asMap(m)['role'] ?? '');
      if (r == RoomRole.spectator) {
        spectators++;
      } else {
        players++;
      }
    }
    final Object? maxP = meta['maxPlayers'];
    return RoomAnnounce(
      code: jsStr(meta['code'] ?? ''),
      base: base,
      name: jsStr(meta['name'] ?? ''),
      kpName: jsStr(meta['kpName'] ?? ''),
      needPwd: jsStr(meta['pwd'] ?? '').isNotEmpty,
      players: players,
      spectators: spectators,
      maxPlayers: maxP is num ? maxP.toInt() : 4,
      status: jsStr(meta['status'] ?? ''),
      wifi: wifi,
    );
  }
}
