// ============================================================
// net/lan_server.dart — P6 房间服务端（HTTP + WebSocket 同端口）
//
// 职责边界（刻意压到最小）：
//   · 只做「收发」：把客户端帧转成 `host.intent()` 调用，把产出的
//     `List<SendPlan>` 转成帧发回去；
//   · **不做裁剪、不做鉴权、不做业务判断** —— 这三件事全在 P4 的
//     `plan()` / `needs()` 里，传输层再判一次只会产生第二套真相。
//
// 与旧版 room-net.js 的对应关系：
//   HostSide.connect()   ←→ 本文件的 start() + WebSocket 注册
//   HostSide 发 plan     ←→ 本文件的 pump()
//   客户端 HTTP 拉全量     ←→ 本文件的 GET /state
//
// ★ K3：只转发 `SendPlan.toJson()`（出站信封）；绝不碰
//   `LogRecord.toWireJson()`（含明文 p，走中继会绕开 Q1 修正）。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/js_compat.dart' show asList, asMap, jsStr, jsTruthy;
import '../domain/room_model_host_core.dart';
import '../domain/room_ports.dart' show AttachPeerResult;
import '../domain/room_model_host_intent.dart'; // host.intent(...) 是这里的 extension
import '../domain/room_types.dart';

import 'room_frame.dart';

/// 启动结果（字段与旧版 room-lan.js 的 start() 对齐）。
class LanServerStart {
  const LanServerStart({
    required this.ok,
    this.base = '',
    this.ip = '',
    this.port = 0,
    this.wifi = true,
    this.error,
  });

  final bool ok;
  final String base;
  final String ip;
  final int port;

  /// `false` 表示只拿到回环地址 —— 这间房**只有自己能进**，
  /// 邀请链接对同伴是死路。旧版犯过这个错（v1.18.4 修），
  /// 界面必须在建房之前就提示，而不是让用户拿两台手机试。
  final bool wifi;

  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        'base': base,
        'ip': ip,
        'port': port,
        'wifi': wifi,
        if (error != null) 'error': error,
      };
}

/// 房间服务端：一台设备当服务器，其他人连它。
class LanServer {
  LanServer({required this.host, this.port = kRoomServicePort});

  final RoomHost host;
  final int port;

  HttpServer? _http;

  /// 实际绑定的端口。传 `port: 0` 时由系统分配（测试用），
  /// 所以要另存一份而不是直接读 [port]。
  int? _actualPort;

  int get boundPort => _actualPort ?? port;

  /// 对外服务地址（`http://<网卡地址>:<实际监听端口>`）。
  ///
  /// ★ 必须**现算**，不能缓存成字符串：界面横幅、局域网自检、UDP 广播
  ///   三处都读这里，一旦缓存值与 socket 真值分叉，用户照着念的地址就是
  ///   死址（真机踩过：显示端口与实际监听端口不是同一个数）。
  String get base => _baseFor(_cachedIp);

  /// seat → 已升级的 WebSocket。KP 自己不在表里（它直接读写 host）。
  final Map<String, WebSocket> _peers = <String, WebSocket>{};

  /// 反查：连接 → seat（清理时用）。
  final Map<WebSocket, String> _seatOf = <WebSocket, String>{};

  /// 坏帧计数（诊断用，不参与业务）。
  int badFrames = 0;

  /// 权威端计划的下游（由 `HostingLocalSession` 注入）。
  ///
  /// ★ 为什么要这个：远端玩家加入/发动作时，产出的 `SendPlan` 必须同时
  ///   通知**本机 KP 侧 UI**（否则「成员」永远是 0，而服务端数据已经变了）。
  ///   `HostingLocalSession.pumpPlans` 正好做「本机投递 + 通知 + 网络投递」，
  ///   所以把它挂上来，而不是在这里自己 `pump()`。
  ///   未注入时（单测里直接 new LanServer）退回直接 pump 到网络。
  void Function(List<SendPlan>)? onHostPlans;

  /// 把权威端计划交给下游（有 UI 下游就走 UI，没有就直发网络）。
  void _dispatchHostPlans(List<SendPlan> plans) {
    final h = onHostPlans;
    if (h != null) {
      h(plans);
    } else {
      pump(plans);
    }
  }

  bool get running => _http != null;
  int get peerCount => _peers.length;

  /// 已连上的座位（不含 KP）。
  List<String> get peerSeats => _peers.keys.toList(growable: false);

  // ----------------------------------------------------------
  // 生命周期
  // ----------------------------------------------------------

  /// 启动服务。端口被占用时返回 `ok:false` 而不是抛异常 ——
  /// 调用方要能在界面上说「端口被占了，换一个房或稍后再试」。
  Future<LanServerStart> start() async {
    // ★ 必须先解析 IP：_baseFor / wifi 判断都依赖它，而 NetworkInterface.list
    //   是异步的。漏了这一步，返回的 base 会是 127.0.0.1，界面就会误报
    //   「只有自己能进」。
    await resolveIp();
    if (_http != null) {
      return LanServerStart(
        ok: true,
        base: _baseFor(_cachedIp),
        ip: _cachedIp,
        port: boundPort,
        wifi: _cachedIp.isNotEmpty,
      );
    }
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: false);
      _actualPort = _http!.port;
    } on Object catch (e) {
      // 端口占用是 SocketException；非法端口（如 >65535）是 ArgumentError。
      // 两者都要变成 ok:false，而不是让绑定异常冒到 UI 层。
      final msg = e is SocketException ? (e.osError?.message ?? e.message) : '$e';
      return LanServerStart(ok: false, error: '端口 $port 不可用：$msg');
    }

    _http!.listen(_onRequest, onError: (Object _) {});

    final ip = _cachedIp;
    return LanServerStart(
      ok: true,
      base: _baseFor(ip),
      ip: ip,
      port: boundPort,
      wifi: ip.isNotEmpty,
    );
  }

  Future<void> stop() async {
    for (final ws in _peers.values.toList()) {
      try {
        await ws.close(WebSocketStatus.normalClosure, 'server stopping');
      } catch (_) {
        // 关不掉就算了，反正下面整体关。
      }
    }
    _peers.clear();
    _seatOf.clear();
    final http = _http;
    _http = null;
    if (http != null) {
      try {
        await http.close(force: true);
      } catch (_) {}
    }
  }

  // ----------------------------------------------------------
  // 泵：权威端产出 → 分发给连接
  // ----------------------------------------------------------

  /// 把 `host.intent()` 产出的计划投递出去。
  ///
  /// 顺序必须与 seq 一致（`plan()` 已保证），否则客户端会判成乱序并触发补拉。
  void pump(List<SendPlan> plans) {
    for (final p in plans) {
      // ★ K3：这里用 SendPlan.toJson()（已裁剪的出站信封），
      //   不是 LogRecord.toWireJson()（含明文 p）。
      final payload = p.toJson();
      if (p.to == '*') {
        for (final ws in _peers.values) {
          _sendFrame(ws, RoomFrame(RoomFrameKind.plan, payload));
        }
      } else if (p.to != kHostSeat) {
        final ws = _peers[p.to];
        if (ws != null) _sendFrame(ws, RoomFrame(RoomFrameKind.plan, payload));
      }
      // to == host 的定向提示由服务端自己消费（UI 层读 hostRead），不转发。
    }
  }

  // ----------------------------------------------------------
  // HTTP 路由
  // ----------------------------------------------------------

  Future<void> _onRequest(HttpRequest req) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        await _onUpgrade(req);
        return;
      }

      final path = req.uri.path;
      if (path == '/health' || path == '/') {
        _writeJson(req.response, _healthJson());
        return;
      }
      if (path == '/state') {
        final seat = req.uri.queryParameters['seat'] ?? '';
        if (seat.isEmpty) {
          _writeJson(req.response, <String, Object?>{'ok': false, 'error': 'NO_SEAT'},
              status: HttpStatus.badRequest);
          return;
        }
        // 按 seat 裁剪后的全量（与 WS 的 sync 帧同一份数据源）。
        _writeJson(req.response, host.syncFor(seat).toJson());
        return;
      }

      _writeJson(req.response, <String, Object?>{'ok': false, 'error': 'NOT_FOUND'},
          status: HttpStatus.notFound);
    } catch (e) {
      try {
        _writeJson(req.response, <String, Object?>{'ok': false, 'error': '$e'},
            status: HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  Map<String, Object?> _healthJson() {
    final meta = asMap(host.state['meta']);
    final members = asList(host.state['members']);
    var players = 0;
    var spectators = 0;
    for (final m in members) {
      final r = jsStr(asMap(m)['role'] ?? '');
      if (r == RoomRole.spectator) {
        spectators++;
      } else {
        players++;
      }
    }
    return <String, Object?>{
      'ok': true,
      'v': kRoomFrameVersion,
      'code': jsStr(meta['code'] ?? ''),
      'status': jsStr(meta['status'] ?? ''),
      'mode': jsStr(meta['mode'] ?? ''),
      'players': players,
      'spectators': spectators,
      'seq': host.log.seq,
    };
  }

  void _writeJson(HttpResponse res, Map<String, Object?> body, {int status = 200}) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.headers.set('access-control-allow-origin', '*');
    res.write(jsonEncode(body));
    res.close();
  }

  // ----------------------------------------------------------
  // WebSocket
  // ----------------------------------------------------------

  Future<void> _onUpgrade(HttpRequest req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    String? seat;

    ws.listen(
      (Object? raw) {
        final frame = _decode(raw);
        if (frame == null) {
          badFrames++;
          return;
        }
        seat ??= _onHello(ws, frame);
        if (seat == null) return; // 还没加入，除 hello 外一律不理
        _onFrame(seat!, frame);
      },
      onDone: () {
        final s = seat;
        if (s != null) {
          _peers.remove(s);
          _seatOf.remove(ws);
        }
      },
      onError: (Object _) {
        final s = seat;
        if (s != null) {
          _peers.remove(s);
          _seatOf.remove(ws);
        }
      },
      cancelOnError: true,
    );
  }

  RoomFrame? _decode(Object? raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final obj = jsonDecode(text);
      if (!RoomFrame.versionOk(obj)) return null;
      return RoomFrame.parse(obj);
    } catch (_) {
      return null;
    }
  }

  /// 处理 `hello`：分配 seat 并回 `joined`。返回 seat，失败返回 null。
  String? _onHello(WebSocket ws, RoomFrame f) {
    if (f.kind != RoomFrameKind.hello) {
      _sendFrame(ws, RoomFrame(RoomFrameKind.error, <String, Object?>{'error': 'NEED_HELLO'}));
      return null;
    }
    final d = f.data ?? const <String, Object?>{};
    var wantSeat = jsStr(d['seat'] ?? '');
    final code = jsStr(d['code'] ?? '');
    final mine = jsStr(asMap(host.state['meta'])['code'] ?? '');
    final nick = jsStr(d['nickname'] ?? '');
    final wantRole = jsStr(d['role'] ?? RoomRole.player);
    // ★ P16 P-1(a)：客户端 hello 带稳定设备标识（cid / deviceId），供服务端
    //   按 cid 幂等复连（无视 online），根治「重连出现 2 个玩家」。
    final cid = jsStr(d['cid'] ?? d['deviceId'] ?? '');

    if (code.isNotEmpty && code != mine) {
      _sendFrame(ws, RoomFrame(RoomFrameKind.error, <String, Object?>{'error': 'WRONG_CODE'}));
      return null;
    }

    if (wantSeat.isEmpty) {
      // ★ 局域网加入的常态：玩家只知道房号，不知道有哪些座位 —— 由服务端分配。
      //   旧版是网页层先拉 /list 再自己挑座位，多一次往返且会挑到竞态座位。
      //
      // ★ P10 第 1 期 B4（「离开后无法重新加入」的根因之一）：
      //   旧实现只调一次 `attachPeer`，且**不看返回值**。被踢过的座位在
      //   `RoomRoster.kicked` 里，`attachPeer` 会 `rejected + blocked` 拒掉，
      //   但这里照旧发出 `joined` —— 客户端以为自己进房了，花名册里却没有他：
      //   界面上「进不去也退不出」，再也加不回来。
      //   现在按候选顺序逐个试：被踢座位直接跳过，全被拒才如实报错。
      // ★ P16 P-1(a)：系统返回键未走 closeConnection → 旧座 online=true，
      //   _seatCandidates 会跳过它、另分 fresh 新座 → KP 视角 2 个玩家。
      //   先按 cid 在成员表里查同设备旧座（无视 online），直接作为首选
      //   候选复用；查不到再退回 _seatCandidates（保持原契约）。
      String? reuseSeat;
      if (cid.isNotEmpty) {
        for (final mRaw in asList(host.state['members'])) {
          final m = asMap(mRaw);
          final s = jsStr(m['seat'] ?? '');
          if (jsStr(m['cid']) == cid &&
              s.isNotEmpty &&
              !host.roster.kicked.contains(s)) {
            reuseSeat = s;
            break;
          }
        }
      }
      final List<String> candidates = reuseSeat != null
          ? <String>[
              reuseSeat,
              ..._seatCandidates(wantRole).where((s) => s != reuseSeat),
            ]
          : _seatCandidates(wantRole);
      if (candidates.isEmpty) {
        _sendFrame(ws, RoomFrame(RoomFrameKind.error,
            <String, Object?>{'error': 'ROOM_FULL'}));
        return null;
      }
      String? assigned;
      AttachPeerResult? added;
      for (final String s in candidates) {
        final r = host.attachPeer(<String, Object?>{
          'seat': s,
          'cid': cid, // ★ 传 cid：roster 记录 + attachPeer 幂等兜底
          'role': wantRole,
          'nickname': nick.isEmpty ? s : nick,
          'at': 1,
        });
        if (r.rejected || r.blocked) continue;
        assigned = r.seat;
        added = r;
        break;
      }
      if (assigned == null || added == null) {
        _sendFrame(ws, RoomFrame(RoomFrameKind.error,
            <String, Object?>{'error': 'ROOM_FULL'}));
        return null;
      }
      wantSeat = assigned;
      _dispatchHostPlans(added.out);
    } else if (!_rosterSeats().contains(wantSeat)) {
      // 指定了座位但花名册里没有 —— 不能凭空造一个（P4 是权威）。
      _sendFrame(ws, RoomFrame(RoomFrameKind.error,
          <String, Object?>{'error': 'UNKNOWN_SEAT', 'seat': wantSeat}));
      return null;
    }
    // 同 seat 重复连接：踢掉旧连接（重连场景很常见）。
    final old = _peers[wantSeat];
    if (old != null) {
      try {
        old.close(WebSocketStatus.normalClosure, 'replaced');
      } catch (_) {}
      _seatOf.remove(old);
    }
    _peers[wantSeat] = ws;
    _seatOf[ws] = wantSeat;

    final role = _roleOf(wantSeat);
    _sendFrame(ws, RoomFrame(RoomFrameKind.joined, <String, Object?>{
      'ok': true,
      'seat': wantSeat,
      'code': mine,
      'role': role,
      'lastSeq': host.log.seq,
    }));
    // 加入即补一份全量：客户端不用再单独发 sync。
    _sendFrame(ws, RoomFrame(RoomFrameKind.plan, <String, Object?>{
      'to': wantSeat,
      'msg': host.syncFor(wantSeat).toJson(),
    }));
    return wantSeat;
  }

  void _onFrame(String seat, RoomFrame f) {
    switch (f.kind) {
      case RoomFrameKind.intent:
      case RoomFrameKind.act:
        final d = f.data ?? const <String, Object?>{};
        final op = jsStr(d['op'] ?? '');
        if (op.isEmpty) {
          badFrames++;
          return;
        }
        final p = asMap(d['p']);
        _dispatchHostPlans(
            host.intent(seat, <String, Object?>{'op': op, 'p': p}));
        return;

      case RoomFrameKind.sync:
        final ws = _peers[seat];
        if (ws == null) return;
        _sendFrame(ws, RoomFrame(RoomFrameKind.plan, <String, Object?>{
          'to': seat,
          'msg': host.syncFor(seat).toJson(),
        }));
        return;

      case RoomFrameKind.bye:
        final ws = _peers.remove(seat);
        if (ws != null) {
          _seatOf.remove(ws);
          try {
            ws.close(WebSocketStatus.normalClosure, 'bye');
          } catch (_) {}
        }
        // ★ B4：主动退房也要让权威端知道「这个人下线了」。
        //   旧实现只摘 socket，成员表里那条一直是 online:true ——
        //   座位不会被回收（再进来只能拿新座），KP 也一直看到他在线。
        //   `detachPeer` 只标记离线、不删成员（他还要能重连回原座）。
        _dispatchHostPlans(host.detachPeer(seat));
        return;

      default:
        badFrames++;
        return;
    }
  }

  void _sendFrame(WebSocket ws, RoomFrame f) {
    try {
      ws.add(jsonEncode(f.toJson()));
    } catch (e, st) {
      // ★ 不要静默吞：序列化失败会让「帧永远发不出去」，而调用方完全察觉不到
      //   （本机就是靠这条日志才定位到 send 阶段的编码异常）。
      // ignore: avoid_print
      print('[LanServer send ERROR] ${f.kind}: $e\n${st.toString().split('\n').take(3).join('\n')}');
    }
  }

  // ----------------------------------------------------------
  // 房间信息（只读，不写 host）
  // ----------------------------------------------------------

  List<String> _rosterSeats() {
    final out = <String>[];
    for (final m in asList(host.state['members'])) {
      final s = jsStr(asMap(m)['seat'] ?? '');
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  /// 找第一个空闲座位。玩家用 `p1..p6`，旁观用 `sp1..sp4`。
  ///
  /// 两族座位分开找，不能混用：旁观者是**裁剪更狠的视角**
  /// （看不到别人手绘板、看不到私有素材），分错族就等于给了错权限。
  ///
  /// 判断依据是**花名册**而不是 `_peers`：`attachPeer` 一执行座位就进花名册，
  /// 所以花名册才是「这个座位有人了」的唯一真相。
  /// 候选座位顺序（**按优先级排好**，调用方逐个试）。
  ///
  /// 两条规则，都来自 P10 第 1 期 B4 的真机反馈：
  ///  ① **先回收掉线者的旧座**：成员表里 `online == false` 的行是「断线 / 主动
  ///     退房」留下的，他们回来时应该坐回原座（准备状态、绑定卡都还在），
  ///     而不是每次重连都占一个新座、把房间堆满幽灵成员（`ROOM_FULL` 假满）。
  ///  ② **跳过被踢过的座位**：`RoomRoster.kicked` 里的座位是房主明确请出去的人
  ///     坐过的，再分配给他等于「踢不掉」。跳过之后踢人仍然有效，而被踢的人
  ///     换个座位可以回来（用户要的是「不能永久卡死」）。
  List<String> _seatCandidates(String role) {
    final List<String> order = <String>[
      if (role == RoomRole.spectator)
        for (var i = 1; i <= 4; i++) 'sp$i'
      else
        for (var i = 1; i <= 6; i++) 'p$i',
    ];
    final Set<String> kicked = host.roster.kicked;
    final Map<String, bool> online = <String, bool>{
      for (final m in asList(host.state['members']))
        jsStr(asMap(m)['seat'] ?? ''): jsTruthy(asMap(m)['online']),
    };
    final List<String> reclaim = <String>[];
    final List<String> fresh = <String>[];
    for (final String s in order) {
      if (kicked.contains(s)) continue;
      if (!online.containsKey(s)) {
        fresh.add(s);
      } else if (online[s] == false) {
        reclaim.add(s);
      }
      // online == true 的座位有人，跳过
    }
    return <String>[...reclaim, ...fresh];
  }


  String _roleOf(String seat) {
    if (seat == kHostSeat) return RoomRole.kp;
    for (final m in asList(host.state['members'])) {
      final mm = asMap(m);
      if (jsStr(mm['seat'] ?? '') == seat) {
        return jsStr(mm['role'] ?? RoomRole.player);
      }
    }
    return RoomRole.player;
  }

  /// 本机非回环 IPv4 的缓存（由 [resolveIp] 填充）。
  String _cachedIp = '';

  /// 在 start() 之前/之后调用都可以；结果缓存。
  ///
  /// ★ 不能「拿到第一个非回环 IPv4 就用」——本机装了代理/VPN/虚拟网卡时，
  ///   最先拿到的往往是那些网段：
  ///     · 198.18.0.0/15（RFC 2544 基准段，Clash TUN 常用）
  ///     · 169.254.0.0/16（链路本地，跨设备不通）
  ///   用它们当 base，广播出去别人连不上，界面却显示「已连接」。
  ///   所以按「像不像真局域网」打分，只选真私网地址。
  Future<String> resolveIp() async {
    if (_cachedIp.isNotEmpty) return _cachedIp;
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? best;
      var bestScore = 0; // 0 分不要：宁可用回环（界面会提示「只有自己能进」）
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final score = _ipScore(a.address);
          if (score > bestScore) {
            bestScore = score;
            best = a.address;
          }
        }
      }
      if (best != null) _cachedIp = best;
    } catch (_) {}
    return _cachedIp;
  }

  /// 地址「像不像真局域网」的打分。0 分 = 不能用。
  static int _ipScore(String ip) {
    if (ip.startsWith('169.254.')) return 0; // 链路本地
    if (ip.startsWith('198.18.') || ip.startsWith('198.19.')) return 0; // 基准测试段（VPN TUN）
    if (ip.startsWith('192.168.')) return 100;
    if (ip.startsWith('10.')) return 90;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) return 80;
    return 10; // 其它公网/少见网段：能用但不优先
  }

  /// 拼服务地址。
  ///
  /// ★ 端口只有一个真源：**已绑定 socket 的端口**（`_http.port`）。
  ///   绝不用常量、也不与本文件其它数值（帧版本、发现端口）相邻拼接 ——
  ///   `'$boundPort$kRoomFrameVersion'` 这种写法会拼出 `42111`，界面与自检
  ///   就会拿着一个没人监听的端口报「正常」。
  String _baseFor(String ip) {
    final int listenPort = _http?.port ?? boundPort;
    return 'http://${ip.isEmpty ? '127.0.0.1' : ip}:$listenPort';
  }
}
