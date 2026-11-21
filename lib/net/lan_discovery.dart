// ============================================================
// net/lan_discovery.dart — P6 房间发现（UDP 广播，端口 4210）
//
// 对应旧版 `RoomLan.discover()` + 外壳的 `lanDiscover()`。
// 旧版这两件事都在 Java 外壳里做（网页层开不了 UDP），Dart 侧直接自己做。
//
// ★ 旧版踩过的三个坑，这里逐个处理：
//   1. `wifi: false` 必须在摘要里透出去 —— 服务端只拿到回环地址时，
//      这间房只有自己能进，邀请链接对同伴是死路。界面要在**建房之前**
//      就提示，而不是让用户拿两台手机试半天。
//   2. 扫描超时要在**调用方**兜底 —— 这里 scan() 自己保证不超时挂住，
//      但调用方仍应再套一层（权限被拒时 socket 可能静默失败）。
//   3. 「发现了但刚关了」是常态 —— 摘要带 1 秒心跳，2 秒没心跳就当过期，
//      界面不能一直显示一间已经消失的房。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'multicast_lock.dart' show MulticastLock;
import 'room_frame.dart' show kRoomDiscoverPort, kRoomFrameVersion;

/// 一条房间摘要（广播出去 / 被发现的形状）。
///
/// 字段对齐旧版 `RoomLan.asRoomEntry()`，多一个 `base`（用来拼「加入」地址）
/// 和 `wifi`（是不是真的连了 WiFi）。
class RoomAnnounce {
  const RoomAnnounce({
    required this.code,
    required this.base,
    this.name = '',
    this.kpName = '',
    this.needPwd = false,
    this.players = 0,
    this.spectators = 0,
    this.maxPlayers = 4,
    this.status = 'RECRUITING',
    this.wifi = true,
    this.updatedAt,
  });

  final String code;

  /// 服务地址，形如 `http://192.168.1.7:4211`。
  final String base;

  final String name;
  final String kpName;
  final bool needPwd;
  final int players;
  final int spectators;
  final int maxPlayers;
  final String status;

  /// 服务端是否拿到了真正的局域网地址（false = 只有回环，别人进不来）。
  final bool wifi;

  /// 本机收到这条摘要的时刻（只在本机用，不序列化）。
  final DateTime? updatedAt;

  RoomAnnounce touched([DateTime? now]) => RoomAnnounce(
        code: code,
        base: base,
        name: name,
        kpName: kpName,
        needPwd: needPwd,
        players: players,
        spectators: spectators,
        maxPlayers: maxPlayers,
        status: status,
        wifi: wifi,
        updatedAt: now ?? DateTime.now(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'v': kRoomFrameVersion,
        'code': code,
        'base': base,
        'name': name,
        'kp': kpName,
        'needPwd': needPwd,
        'players': players,
        'spectators': spectators,
        'maxPlayers': maxPlayers,
        'status': status,
        'wifi': wifi,
      };

  static RoomAnnounce? parse(Object? raw) {
    try {
      final Object? obj = raw is String ? jsonDecode(raw) : raw;
      if (obj is! Map) return null;
      final code = obj['code'];
      final base = obj['base'];
      if (code is! String || code.isEmpty) return null;
      if (base is! String || base.isEmpty) return null;
      return RoomAnnounce(
        code: code,
        base: base,
        name: '${obj['name'] ?? ''}',
        kpName: '${obj['kp'] ?? ''}',
        needPwd: obj['needPwd'] == true,
        players: _int(obj['players']),
        spectators: _int(obj['spectators']),
        maxPlayers: _int(obj['maxPlayers'], 4),
        status: '${obj['status'] ?? 'RECRUITING'}',
        wifi: obj['wifi'] != false,
        updatedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
}

/// 广播器：服务端定期把自己的摘要发到 4210。
///
/// 用**随机源端口**发往固定目标端口 —— 这样同一台机器上既能广播又能监听，
/// 不会抢 4210（旧版外壳里没这个问题，因为收发都在 Java 层各管一摊）。
class LanBroadcaster {
  LanBroadcaster({
    this.targetPort = kRoomDiscoverPort,
    this.targetAddress = '255.255.255.255',
  });

  final int targetPort;

  /// 目标地址。生产用广播地址；测试传 `127.0.0.1`（广播在部分环境
  /// 或防火墙下收不到，单测里用一个确定能通的地址更稳）。
  final String targetAddress;

  RawDatagramSocket? _sock;
  Timer? _timer;

  bool get running => _sock != null;

  /// 启动心跳广播。[snapshot] 每次被调用时取当前房间状态 —— 
  /// 不要缓存它，否则人数变化广播不出去。
  Future<bool> start(
    RoomAnnounce Function() snapshot, {
    Duration every = const Duration(seconds: 1),
  }) async {
    if (_sock != null) return true;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.broadcastEnabled = true;
      _sock = s;
    } catch (_) {
      return false;
    }
    // ★ Android 的 WiFi 省电会丢广播包，必须持多播锁。
    //   拿不到也继续（建房不能因省电优化失败），但会少一层保障。
    await MulticastLock.acquire();
    _timer = Timer.periodic(every, (_) => beat(snapshot));
    beat(snapshot);
    return true;
  }

  /// 立刻发一次（房间状态变化时可以主动推，不等心跳）。
  void beat(RoomAnnounce Function() snapshot) {
    final s = _sock;
    if (s == null) return;
    try {
      final bytes = utf8.encode(jsonEncode(snapshot().toJson()));
      s.send(bytes, InternetAddress(targetAddress), targetPort);
    } catch (_) {
      // 广播发不出去不是致命错误（可能刚切网络），等下一次心跳。
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final s = _sock;
    _sock = null;
    try {
      s?.close();
    } catch (_) {}
    // 与 start() 的 acquire 严格配对（引用计数保护扫描器那一层）。
    await MulticastLock.release();
  }
}

/// 发现器：监听 4210，收集摘要。
class LanDiscoverer {
  const LanDiscoverer._();

  /// 扫描一段时间，返回去重后的房间列表。
  ///
  /// [staleAfter] 内的重复摘要会覆盖旧的（人数会变），不是简单追加。
  /// 超时一定返回（哪怕空列表），**绝不抛** —— 界面据此显示「附近没有房间」。
  static Future<List<RoomAnnounce>> scan({
    int listenPort = kRoomDiscoverPort,
    Duration timeout = const Duration(milliseconds: 1600),
  }) async {
    final Map<String, RoomAnnounce> found = <String, RoomAnnounce>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        listenPort,
        reuseAddress: true,
      );
    } catch (_) {
      return const <RoomAnnounce>[];
    }

    final Completer<void> done = Completer<void>();
    late final StreamSubscription<RawSocketEvent> sub;
    // ★ 收包才是真正需要多播锁的地方 —— 发送不会被 WiFi 省电过滤，
    //   接收会。不持锁时症状是「广播方一直发，扫描方永远收到 0 条」。
    await MulticastLock.acquire();
    try {
      sub = sock.listen((RawSocketEvent e) {
        if (e != RawSocketEvent.read) return;
        Datagram? dg;
        try {
          dg = sock!.receive();
        } catch (_) {
          return;
        }
        if (dg == null) return;
        final RoomAnnounce? a;
        try {
          a = RoomAnnounce.parse(utf8.decode(dg.data));
        } catch (_) {
          return;
        }
        if (a == null) return;
        // 同 code 覆盖（人数会变）；没有 code 时用地址兜底去重。
        found[a.code.isEmpty ? a.base : a.code] = a.touched();
        if (!done.isCompleted && found.length >= 32) done.complete();
      });

      await Future.any(<Future<void>>[
        Future<void>.delayed(timeout),
        done.future,
      ]);
    } finally {
      // 无论怎么退出都要配平：留一层锁不释放会让系统持续耗电。
      try {
        await sub.cancel();
      } catch (_) {}
      try {
        sock.close();
      } catch (_) {}
      await MulticastLock.release();
    }

    // 按「人数多 / 状态招募中」排一下，界面直接拿去渲染。
    final list = found.values.toList()
      ..sort((RoomAnnounce a, RoomAnnounce b) {
        final aOpen = a.status == 'RECRUITING' ? 0 : 1;
        final bOpen = b.status == 'RECRUITING' ? 0 : 1;
        if (aOpen != bOpen) return aOpen - bOpen;
        return b.players.compareTo(a.players);
      });
    return list;
  }
}
