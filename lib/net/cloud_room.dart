// ============================================================
// net/cloud_room.dart — 公网中继（云端 /room）的控制层
//
// ★ 为什么需要这一层（P10 第 1 期 B5，用户要求「公网开房加回」）：
//   局域网那条路的权威端是 KP 手机上的 `LanServer`；公网那条路的权威端
//   **还是** KP 手机，云端只做「鉴权 + 转发 + 房间目录」，不持有游戏状态。
//   所以两边**应用层协议完全一样**（`SendPlan` / `RoomEnvelope`），差别只在
//   「谁来转发」：本文件就是那条「别人替我转发」的通道。
//
// 协议依据（只读核实，不是猜的）：
//   服务端 `coc7th-card-app/tools/room_server.py`（线上 `/opt/coc-room/room_server.py`
//   同名同源，1815 行）头部注释与路由表：
//     POST /api/rooms                → {code, hostToken, wsBase}
//     POST /api/rooms/<code>/join    → {code, mtoken, wsUrl, role, ...}
//     WS   /ws?code=..&t=..&d=..     → 升级后服务端推 {k:'ready'|'host.ok'|...}
//     KP  → 中继：{k:'hub.send',cid,text} / {k:'hub.broadcast',text} /
//                  {k:'hub.close',cid} / {k:'hub.meta',meta}
//     中继 → KP：{k:'peer.open',cid,seat,role,nickname} /
//                  {k:'peer.close',cid,seat} / {k:'peer.msg',cid,text}
//   关键一句（服务端注释原文）：「其余：中继只是**原样透传**的字节，不解析」。
//   ⇒ 应用层载荷就是一个字符串，本 App 放的就是 `RoomFrame.toJson()` 的 JSON，
//     与局域网帧**同一套**编码，服务端不需要任何改动。
//
// ★ 红线（与局域网一致）：出站只用 `SendPlan.toJson()`，
//   **绝不**用 `LogRecord.toWireJson()`（含明文 `p`）。
//
// ★ 可测性：三条注入点（HTTP / WebSocket / 设备标识）都是可替换的，
//   普通 `test` 用内存替身就能把「注册 → 握手 → 转发 → 踢人」整条走一遍，
//   不需要真网络（`testWidgets` 里更不会有真 socket）。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/js_compat.dart' show asMap, asList, jsStr;
import '../repo/cloud_device_id.dart'
    show deviceIdStorage, isValidDeviceId, newStableDeviceId;
import '../domain/room_model_client.dart' show RoomClient;
import '../domain/room_model_host_core.dart' show RoomHost;
import '../domain/room_model_host_intent.dart' show RoomHostIntent;
import '../domain/room_ports.dart' show AttachPeerResult;
import '../domain/room_types.dart' show RoomIntent, RoomRole, SendPlan;
import 'room_frame.dart';

// ------------------------------------------------------------
// 0. 注入点
// ------------------------------------------------------------

/// 一条 HTTP 响应（只要 JSON，够用即可）。
class CloudHttpResponse {
  const CloudHttpResponse({
    required this.ok,
    this.status = 0,
    this.json = const <String, Object?>{},
    this.error = '',
  });

  final bool ok;
  final int status;
  final Map<String, Object?> json;
  final String error;

  String get errorCode => jsStr(json['error'] ?? '');
}

/// 云端 HTTP 端口（可注入）。
abstract class CloudHttpTransport {
  Future<CloudHttpResponse> postJson(Uri url, Map<String, Object?> body);
}

/// 生产实现：`dart:io` 的 HttpClient（零新增依赖）。
class IoCloudHttpTransport implements CloudHttpTransport {
  const IoCloudHttpTransport({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;

  @override
  Future<CloudHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    final HttpClient http = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest req = await http
          .postUrl(url)
          .timeout(timeout);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final HttpClientResponse res = await req.close().timeout(timeout);
      final String text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      Map<String, Object?> json = const <String, Object?>{};
      try {
        final Object? decoded = jsonDecode(text);
        if (decoded is Map) json = decoded.cast<String, Object?>();
      } catch (_) {
        // 非 JSON 响应（网关 502 之类）—— 交给调用方按 status 报错
      }
      return CloudHttpResponse(
        ok: res.statusCode >= 200 && res.statusCode < 300,
        status: res.statusCode,
        json: json,
        error: json.isEmpty ? 'HTTP ${res.statusCode}' : '',
      );
    } catch (e) {
      return CloudHttpResponse(ok: false, error: '$e');
    } finally {
      http.close(force: true);
    }
  }
}

/// 一条 WS 连接（可注入）。
abstract class CloudSocket {
  Future<void> connect(String url);
  void send(String text);
  Future<void> close();

  /// 收到一条文本帧。
  set onText(void Function(String text)? v);

  /// 连接被关闭。
  set onClosed(void Function()? v);
}

/// 生产实现：`dart:io` 的 WebSocket。
class WsCloudSocket implements CloudSocket {
  WsCloudSocket({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;
  WebSocket? _ws;
  void Function(String)? _onText;
  void Function()? _onClosed;

  @override
  set onText(void Function(String text)? v) => _onText = v;

  @override
  set onClosed(void Function()? v) => _onClosed = v;

  @override
  Future<void> connect(String url) async {
    final WebSocket ws = await WebSocket.connect(url).timeout(timeout);
    _ws = ws;
    ws.listen(
      (Object? raw) {
        if (raw is String) {
          _onText?.call(raw);
        } else if (raw is List<int>) {
          _onText?.call(utf8.decode(raw));
        }
      },
      onDone: () => _onClosed?.call(),
      onError: (Object _) => _onClosed?.call(),
      cancelOnError: true,
    );
  }

  @override
  void send(String text) {
    try {
      _ws?.add(text);
    } catch (_) {
      // 对端已经没了：由 onClosed 统一处理
    }
  }

  @override
  Future<void> close() async {
    final ws = _ws;
    _ws = null;
    if (ws == null) return;
    try {
      await ws.close(WebSocketStatus.normalClosure, 'bye');
    } catch (_) {}
  }
}

/// 全局可替换工厂（测试换成内存 socket）。
CloudSocket Function() cloudSocketFactory = () => WsCloudSocket();

/// 全局可替换 HTTP（测试换成内存实现）。
CloudHttpTransport cloudHttp = const IoCloudHttpTransport();

/// 设备标识（云端用它认「同一个人重连回原座」）。
///
/// ★ P20：改为走 `repo/cloud_device_id.dart` 的持久化端口。生产在 `main()`
///   注入 `FileDeviceIdStorage`（`.room_credentials/device_id.txt`），App
///   重启后仍读到同一个 `fl-`+16hex，服务端 `device_seats` 绑定继续命中 →
///   玩家回原座。未注入时用内存实现（flutter test 零 I/O、同进程内稳定）。
///   `cloudDeviceId` 仍是进程内缓存 + 可注入点（测试可预设 `'fl-test'`）。
String cloudDeviceId = '';

/// 取（必要时生成）设备标识：缓存 → 持久化读 → 校验 → `Random.secure()` 生成并写回。
String ensureCloudDeviceId() {
  if (cloudDeviceId.isNotEmpty) return cloudDeviceId;
  final String stored = deviceIdStorage.read().trim();
  if (isValidDeviceId(stored)) {
    cloudDeviceId = stored;
    return cloudDeviceId;
  }
  final String fresh = newStableDeviceId();
  deviceIdStorage.write(fresh);
  cloudDeviceId = fresh;
  return cloudDeviceId;
}

/// ★ P20 N-1：云端房号规范化（**小写纯函数**）。
///
/// 线上 `CODE_ALPHA`（room_server.py:194）与全部路由正则都是 `[a-z0-9]{4,12}`，
/// 而 LAN 用 `normalizeRoomCode()`（`room_boot.dart:64`）转大写 —— 两种模式
/// 的房号天然分叉。云端 HTTP 路径 / WS query / 凭据键一律用本函数产出的
/// 小写值；LAN 仍用大写，**且绝不改服务端正则**（会破坏老客户端）。
/// 本函数是纯函数、幂等（对已小写值不变），不 I/O、不改全局。
String cloudRoomCode(String raw) => raw.trim().toLowerCase();

/// 规范化中继地址：去空格 / 去尾斜杠；空串保持空（= 未配置）。
String normalizeCloudBase(String raw) {
  var s = raw.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// 这个地址看起来是不是「公网中继」（而不是局域网直连）。
///
/// ★ P12 真机 bug：原实现只认 `http(s)://` 前缀，但局域网 UDP 广播里的
///   base 本身就是 `http://192.168.x.x:4211`（`lan_server.dart#_baseFor`），
///   手输完整 URL 时也是这个形状。于是「附近的房间」选中后被误判成公网
///   中继 → 朝局域网 IP 发云端 API → HTTP 404 →「公网加入失败」，
///   而且每次都这样（跟是否配置过公网服务器无关）。
///
/// 现在按**主机**判定：本机 / RFC1918 私有网段 / 链路本地一律是局域网，
/// 只有公网域名或公网 IP 才算中继。
bool isCloudBase(String raw) {
  final String s = raw.trim().toLowerCase();
  if (!s.startsWith('http://') && !s.startsWith('https://')) return false;
  final String h = (Uri.tryParse(s)?.host ?? '').toLowerCase();
  if (h.isEmpty) return false;

  // 本机与回环（含 Android 模拟器的宿主别名 10.0.2.2，落在下面的 10. 段）。
  if (h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]') {
    return false;
  }
  // RFC1918 私有网段 + 链路本地。
  if (h.startsWith('10.') ||
      h.startsWith('192.168.') ||
      h.startsWith('169.254.')) {
    return false;
  }
  final RegExpMatch? m = RegExp(r'^172\.(\d+)\.').firstMatch(h);
  if (m != null) {
    final int? n = int.tryParse(m.group(1) ?? '');
    if (n != null && n >= 16 && n <= 31) return false;
  }
  return true;
}

/// 把 `https://host/room` 变成 `https://host/room/api/...`。
Uri cloudApiUri(String base, String path) => Uri.parse('$base$path');

/// 把 HTTP(S) 基地址变成 WS(S) 地址。
///
/// ★ P20 N-2 防御（保持默认行为不变，`p10_t1_cloud_room_test.dart:350–362` 全绿）：
///   · `wss` 输入不再被降级成 `ws`（真机服务端 `ws_base()` 返回 `wss://…/room`）；
///   · 若 base 路径已经以 `/ws` 结尾（误把服务端返回的**完整** `wsUrl` 当 base
///     喂进来），先去掉尾部 `/ws` 再拼，避免产出 `/room/ws/ws` 双 `/ws`。
///   · [deviceId] 可选：不传时沿用 `ensureCloudDeviceId()`（与原口径一致）。
///   对普通 base（如 `https://relay.example.com/room`）产出与改造前逐字一致。
String cloudWsUrl(
  String wsBase, {
  required String code,
  required String token,
  String? deviceId,
}) {
  var b = wsBase.trim();
  if (b.isEmpty) b = '';
  final Uri u = Uri.parse(b);
  // https / wss 都产出 wss；http / ws 产出 ws（wss 不再被误降级）。
  final String scheme = (u.scheme == 'https' || u.scheme == 'wss') ? 'wss' : 'ws';
  String basePath = u.path;
  while (basePath.endsWith('/')) {
    basePath = basePath.substring(0, basePath.length - 1);
  }
  // 去掉尾部 /ws（生产形态 wsUrl 误当 base 时的兜底），避免双 /ws。
  if (basePath.endsWith('/ws')) {
    basePath = basePath.substring(0, basePath.length - 3);
  }
  final String d = (deviceId != null && deviceId.isNotEmpty)
      ? deviceId
      : ensureCloudDeviceId();
  return Uri(
    scheme: scheme,
    host: u.host,
    port: u.hasPort ? u.port : null,
    path: '$basePath/ws',
    queryParameters: <String, String>{
      'code': code,
      't': token,
      'd': d,
    },
  ).toString();
}

// ------------------------------------------------------------
// 1. KP 侧：注册房间 + 当权威端
// ------------------------------------------------------------

/// 开局结果（失败时 [error] 是给用户看的一句人话）。
class CloudHostStart {
  const CloudHostStart({
    required this.ok,
    this.code = '',
    this.token = '',
    this.wsBase = '',
    this.base = '',
    this.error = '',
  });

  final bool ok;
  final String code;

  /// 房主凭据（`hostToken`）：关房 / 续玩要用，**不落日志**。
  final String token;
  final String wsBase;
  final String base;
  final String error;
}

/// KP 侧的中继通道：把 `List<SendPlan>` 变成 `hub.send` / `hub.broadcast`，
/// 把 `peer.open` / `peer.close` / `peer.msg` 变成对 `RoomHost` 的调用。
class CloudRoomHostLink {
  CloudRoomHostLink({
    required this.base,
    required this.host,
    this.code = '',
    this.hostToken = '',
    // ★ P20：KP 侧 WS 的 `d=` 也用凭据里的原 deviceId（与玩家侧同源）。
    //   不传时回退 ensureCloudDeviceId()，p10 既有用例行为不变。
    this.deviceId = '',
    CloudSocket? socket,
    this.onPlans,
  }) : _socket = socket ?? cloudSocketFactory();

  /// 中继基地址（`https://host/room`）。
  final String base;

  /// 权威端（KP 那台「设备」）。
  final RoomHost host;

  /// 收到的权威端计划要投给谁（本机会话 / 网络）。由 HostingSession 注入。
  void Function(List<SendPlan> plans)? onPlans;

  final CloudSocket _socket;

  String code;
  String hostToken;
  final String deviceId;
  String _wsBase = '';
  bool _started = false;
  bool _disposed = false;

  /// cid → seat（中继给的投递地址 → 应用层座位）。
  final Map<String, String> _seatOfCid = <String, String>{};
  final Map<String, String> _cidOfSeat = <String, String>{};

  /// 建连等待器（`host.ok` 到达才算真的进去了）。
  Completer<CloudHostStart>? _ready;

  bool get running => _started;

  /// **只做 HTTP 登记**：拿到房间号与 hostToken。
  ///
  /// 为什么把「登记」与「连 WS」拆开：房间号是**中继分配**的，而 `RoomHost`
  /// 的 meta 里必须有房号（界面 / 存档 / 广播都用它）。所以顺序必须是
  /// 先登记拿号 → 再用这个号建 `RoomHost` → 最后连 WS。拆开之后
  /// `room_boot.dart` 不必事后再去改 host 的 meta（那是权威状态写入）。
  static Future<CloudHostStart> registerRoom({
    required String base,
    required String name,
    required String kpName,
    int maxPlayers = 6,
    bool allowSpectate = true,
  }) async {
    final String cleanBase = normalizeCloudBase(base);
    final CloudHttpResponse res = await cloudHttp.postJson(
      cloudApiUri(cleanBase, '/api/rooms'),
      <String, Object?>{
        'name': name.isEmpty ? '无名房间' : name,
        'kpName': kpName.isEmpty ? 'KP' : kpName,
        'maxPlayers': maxPlayers,
        'allowSpectate': allowSpectate,
      },
    );
    if (!res.ok) {
      return CloudHostStart(ok: false, base: cleanBase, error: _friendly(res));
    }
    final String code = jsStr(res.json['code'] ?? '');
    final String token = jsStr(res.json['hostToken'] ?? '');
    if (code.isEmpty || token.isEmpty) {
      return CloudHostStart(
        ok: false,
        base: cleanBase,
        error: '中继返回的房间信息不完整',
      );
    }
    return CloudHostStart(
      ok: true,
      code: code,
      token: token,
      wsBase: jsStr(res.json['wsBase'] ?? ''),
      base: cleanBase,
    );
  }

  /// 注册（若还没注册过）并连上中继的实时通道。
  Future<CloudHostStart> start({
    required String name,
    required String kpName,
    int maxPlayers = 6,
    bool allowSpectate = true,
  }) async {
    if (_disposed) {
      return const CloudHostStart(ok: false, error: '已关闭');
    }
    if (code.isEmpty || hostToken.isEmpty) {
      final CloudHostStart reg = await registerRoom(
        base: base,
        name: name,
        kpName: kpName,
        maxPlayers: maxPlayers,
        allowSpectate: allowSpectate,
      );
      if (!reg.ok) return reg;
      code = reg.code;
      hostToken = reg.token;
      _wsBase = reg.wsBase;
    }
    final waiter = Completer<CloudHostStart>();
    _ready = waiter;
    _socket.onText = _onText;
    _socket.onClosed = _onClosed;
    try {
      await _socket.connect(
        cloudWsUrl(_wsBase.isEmpty ? base : _wsBase,
            code: code,
            token: hostToken,
            deviceId: deviceId.isNotEmpty ? deviceId : ensureCloudDeviceId()),
      );
    } catch (e) {
      _ready = null;
      return CloudHostStart(ok: false, code: code, base: base, error: '连不上中继：$e');
    }
    final CloudHostStart ok = await waiter.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => CloudHostStart(
        ok: false,
        code: code,
        base: base,
        error: '中继没有回应（房间已登记，但实时通道没连上）',
      ),
    );
    _ready = null;
    _started = ok.ok;
    return ok;
  }

  /// 权威端出站计划 → 中继。
  void pump(List<SendPlan> plans) {
    if (!_started || _disposed) return;
    for (final SendPlan p in plans) {
      // ★ 红线：只发 SendPlan.toJson()（已按 vis/to 脱敏）
      final String text = jsonEncode(p.msg.toJson());
      if (p.to == '*') {
        _send(<String, Object?>{'k': 'hub.broadcast', 'text': text});
      } else {
        final String? cid = _cidOfSeat[p.to];
        if (cid == null) continue; // 这个座位还没连上中继
        _send(<String, Object?>{'k': 'hub.send', 'cid': cid, 'text': text});
      }
    }
  }

  /// 主动断开某个人（踢人 / 关房时用）。
  void kickPeer(String seat) {
    final String? cid = _cidOfSeat[seat];
    if (cid == null) return;
    _send(<String, Object?>{
      'k': 'hub.close',
      'cid': cid,
      'text': '你已被房主移出房间',
    });
  }

  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    _socket.onText = null;
    _socket.onClosed = null;
    await _socket.close();
  }

  // ---- 入站 ----

  void _onText(String text) {
    Map<String, Object?> msg = const <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) msg = decoded.cast<String, Object?>();
    } catch (_) {
      return;
    }
    final String k = jsStr(msg['k'] ?? '');
    switch (k) {
      case 'host.ok':
        final w = _ready;
        if (w != null && !w.isCompleted) {
          w.complete(CloudHostStart(
            ok: true,
            code: code,
            wsBase: _wsBase,
            base: base,
          ));
        }
        return;
      case 'peer.open':
        _onPeerOpen(msg);
        return;
      case 'peer.close':
        _onPeerClose(msg);
        return;
      case 'peer.msg':
        _onPeerMsg(msg);
        return;
      default:
        return;
    }
  }

  void _onClosed() {
    _started = false;
    final w = _ready;
    if (w != null && !w.isCompleted) {
      w.complete(CloudHostStart(ok: false, code: code, base: base, error: '连接被关闭'));
    }
  }

  void _onPeerOpen(Map<String, Object?> msg) {
    final String cid = jsStr(msg['cid'] ?? '');
    String seat = jsStr(msg['seat'] ?? '');
    if (cid.isEmpty) return;
    // ★ P16 P-1(a) 按 cid 稳定复用：同一设备重连（即使中继这次给的
    //   seat 不同 / 为空，或旧座仍是 online 幽灵）都归一到该 cid 之前的
    //   旧座，避免「只修局域网、云端仍出现 2 个玩家」。
    //   先查中继自己的 cid→seat 映射，再查权威端花名册里同 cid 的成员。
    String bound = _seatOfCid[cid] ?? '';
    if (bound.isEmpty) {
      for (final s in host.roster.order) {
        final m = host.roster.bySeat[s];
        if (m != null && jsStr(m['cid']) == cid) {
          bound = s;
          break;
        }
      }
    }
    if (bound.isNotEmpty) seat = bound;
    if (seat.isEmpty) return;
    _seatOfCid[cid] = seat;
    _cidOfSeat[seat] = cid;
    // ★ 「谁在房间里」仍然由权威端（room_model_host_core#attachPeer）说了算，
    //   中继只是报告「有个连接来了」。rejoin（同座重连）不动 ready 状态。
    final AttachPeerResult added = host.attachPeer(<String, Object?>{
      'seat': seat,
      'cid': cid, // ★ 传 cid：roster 记录 + attachPeer 幂等兜底
      'role': jsStr(msg['role'] ?? RoomRole.player),
      'nickname': jsStr(msg['nickname'] ?? seat),
      'at': 1,
    });
    if (added.rejected) {
      // 被踢过的座位 / 无效座位：直接让中继把这条连接关掉，别留个幽灵。
      _send(<String, Object?>{
        'k': 'hub.close',
        'cid': cid,
        'text': '这个座位已不可用',
      });
      return;
    }
    // attachPeer 可能把 seat 归一到别的旧座（cid 幂等兜底），以返回值为准。
    final String effective = added.seat.isNotEmpty ? added.seat : seat;
    _seatOfCid[cid] = effective;
    _cidOfSeat[effective] = cid;
    onPlans?.call(added.out);
  }

  void _onPeerClose(Map<String, Object?> msg) {
    final String seat = jsStr(msg['seat'] ?? '');
    final String cid = jsStr(msg['cid'] ?? '');
    if (cid.isNotEmpty) {
      final String? s = _seatOfCid.remove(cid);
      if (s != null) _cidOfSeat.remove(s);
    }
    if (seat.isEmpty) return;
    // 中继说这条连接没了：花名册只标记离线（他随时能重连回原座）。
    onPlans?.call(host.detachPeer(seat));
  }

  void _onPeerMsg(Map<String, Object?> msg) {
    final String cid = jsStr(msg['cid'] ?? '');
    final String seat = _seatOfCid[cid] ?? '';
    if (seat.isEmpty) return;
    final String text = jsStr(msg['text'] ?? '');
    if (text.isEmpty) return;
    RoomFrame? frame;
    try {
      frame = RoomFrame.parse(jsonDecode(text));
    } catch (_) {
      return;
    }
    if (frame == null) return;
    switch (frame.kind) {
      case RoomFrameKind.intent:
      case RoomFrameKind.act:
        final d = frame.data ?? const <String, Object?>{};
        final op = jsStr(d['op'] ?? '');
        if (op.isEmpty) return;
        onPlans?.call(host.intent(seat, <String, Object?>{
          'op': op,
          'p': asMap(d['p']),
        }));
        return;
      case RoomFrameKind.sync:
        onPlans?.call(<SendPlan>[
          SendPlan(seat, host.syncFor(seat)),
        ]);
        return;
      case RoomFrameKind.bye:
        onPlans?.call(host.detachPeer(seat));
        return;
      default:
        return;
    }
  }

  void _send(Map<String, Object?> frame) {
    if (_disposed) return;
    _socket.send(jsonEncode(frame));
  }

  static String _friendly(CloudHttpResponse res) {
    final String code = res.errorCode;
    switch (code) {
      case 'bad_request':
        return '中继拒绝了这次创建（参数不合法）';
      case 'too_many_rooms':
        return '中继上的房间太多了，稍后再试';
      default:
        break;
    }
    if (res.error.isNotEmpty) return '连不上中继：${res.error}';
    return '中继返回失败（HTTP ${res.status}）';
  }
}

// ------------------------------------------------------------
// 2. 玩家侧：加入公网房间
// ------------------------------------------------------------

/// 加入结果。
class CloudJoinResult {
  const CloudJoinResult({
    required this.ok,
    this.seat = '',
    this.error = '',
    // ★ P20 M5：服务端 joinKind（'reconnect' | 'new'），客户端据此判身份。
    this.joinKind = '',
  });

  final bool ok;
  final String seat;
  final String error;
  final String joinKind;
}

/// 玩家侧的云端连接：与 `LanClient` 同一个职责（收帧 → `RoomClient`）。
///
/// 刻意不继承 `LanClient`：那边是「直连一台已经在跑 LanServer 的设备」，
/// 握手是 `hello/joined`；云端是「先 HTTP join 拿 token，再由中继推 ready」。
/// 两者唯一相同的是**应用层载荷**，所以这里只复用 [RoomClient]。
class CloudRoomClient {
  CloudRoomClient({
    required this.base,
    required this.code,
    this.role = RoomRole.player,
    this.nickname = '调查员',
    // ★ P20 M5：稳定设备标识（续玩时传凭据里的原值，保证 device_seats 命中
    //   → joinKind='reconnect'、复用原座）。空串时由 ensureCloudDeviceId() 兜底。
    this.deviceId = '',
    CloudSocket? socket,
  })  : _socket = socket ?? cloudSocketFactory(),
        client = RoomClient(seat: '', role: role);

  final String base;
  final String code;
  final String role;
  final String nickname;
  final String deviceId;
  final CloudSocket _socket;

  /// P4 的裁剪态容器（UI 读它的 state）。
  RoomClient client;

  String seat = '';
  bool connected = false;
  int syncEpoch = 0;

  /// 状态变化 / 每条入站消息（与 LanClient 同签名，便于上层复用口径）。
  void Function()? onChange;
  void Function(Map<String, Object?> msg)? onMsg;

  final List<String> _queue = <String>[];
  Completer<CloudJoinResult>? _ready;
  bool _disposed = false;
  String _joinKind = '';

  /// 本次连接实际使用的稳定设备标识（join body 与 WS `d=` 必须是同一个值）。
  String get _effectiveDeviceId =>
      deviceId.isNotEmpty ? deviceId : ensureCloudDeviceId();

  /// join + WS 握手。失败返回 `ok:false`（不抛）。
  Future<CloudJoinResult> connect() async {
    if (_disposed) return const CloudJoinResult(ok: false, error: '已关闭');
    // ★ P20 N-1：HTTP 路径用 [code] 这一个变量。调用方（RoomNetFactory /
    //   resumeCloudRoom / RoomResumeService）已在构造本对象前用
    //   cloudRoomCode() 规范化为小写；这里**不再二次转换**，与下面的 WS query
    //   `code` 保持同一个值（设计 §8.1「禁止一处归一、一处原始值」）。
    final String did = _effectiveDeviceId;
    final CloudHttpResponse res = await cloudHttp.postJson(
      cloudApiUri(base, '/api/rooms/$code/join'),
      <String, Object?>{
        'nickname': nickname,
        'role': role,
        'deviceId': did,
      },
    );
    if (!res.ok) {
      return CloudJoinResult(
        ok: false,
        error: _joinError(res),
      );
    }
    final String token = jsStr(res.json['mtoken'] ?? '');
    // ★ P20 M5：服务端 joinKind（'reconnect' | 'new'）—— F7 判据。
    _joinKind = jsStr(res.json['joinKind'] ?? '');
    if (token.isEmpty) {
      return const CloudJoinResult(ok: false, error: '中继返回的入房信息不完整');
    }
    final waiter = Completer<CloudJoinResult>();
    _ready = waiter;
    _socket.onText = _onText;
    _socket.onClosed = _onClosed;
    try {
      // ★ P20 N-2：弃用服务端返回的**完整** wsUrl，改由 [base] 重建。
      //   真机 wsUrl 形如 `wss://…/ws?code=..&t=..&d=..`，当作 base 喂给
      //   cloudWsUrl 会 wss→ws 降级并拼出双 `/ws`；现有 FakeRelay 返回的是
      //   base 形态才掩盖了这个 bug。由 base 重建后两者一致，p10 用例不受影响。
      await _socket.connect(
        cloudWsUrl(base, code: code, token: token, deviceId: did),
      );
    } catch (e) {
      _ready = null;
      return CloudJoinResult(ok: false, error: '连不上中继：$e');
    }
    final CloudJoinResult r = await waiter.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => const CloudJoinResult(ok: false, error: '中继没有回应'),
    );
    _ready = null;
    if (r.ok) {
      connected = true;
      _flush();
    }
    return r;
  }

  void sendIntent(String op, Map<String, Object?> p) {
    _send(jsonEncode(RoomFrame(RoomFrameKind.intent, <String, Object?>{
      'op': op,
      'p': p,
    }).toJson()));
  }

  void sendAct(String action, Map<String, Object?> p) {
    final inner = <String, Object?>{...p, 'op': action};
    _send(jsonEncode(RoomFrame(RoomFrameKind.act, <String, Object?>{
      'op': RoomIntent.act,
      'p': inner,
    }).toJson()));
  }

  void requestSync() {
    _send(jsonEncode(RoomFrame(RoomFrameKind.sync, <String, Object?>{
      'lastSeq': client.lastSeq,
    }).toJson()));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _socket.onText = null;
    _socket.onClosed = null;
    await _socket.close();
    _queue.clear();
  }

  // ---- 内部 ----

  void _onText(String text) {
    Map<String, Object?> msg = const <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) msg = decoded.cast<String, Object?>();
    } catch (_) {
      return;
    }
    final String k = jsStr(msg['k'] ?? '');
    if (k == 'ready') {
      final String assigned = jsStr(msg['seat'] ?? '');
      if (assigned.isNotEmpty && assigned != seat) {
        seat = assigned;
        client = RoomClient(seat: seat, role: role);
      }
      final w = _ready;
      if (w != null && !w.isCompleted) {
        w.complete(CloudJoinResult(ok: true, seat: seat, joinKind: _joinKind));
      }
      return;
    }
    if (k == 'error') {
      final String e = jsStr(msg['message'] ?? msg['error'] ?? '中继返回错误');
      final w = _ready;
      if (w != null && !w.isCompleted) {
        w.complete(CloudJoinResult(ok: false, error: e));
      }
      return;
    }
    // 其余都是应用层载荷（本 App 的 RoomFrame JSON，原样透传）
    _deliverText(text);
  }

  void _onClosed() {
    connected = false;
    final w = _ready;
    if (w != null && !w.isCompleted) {
      w.complete(const CloudJoinResult(ok: false, error: '连接被关闭'));
    }
    onChange?.call();
  }

  void _deliverText(String text) {
    Map<String, Object?>? msg;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) msg = decoded.cast<String, Object?>();
    } catch (_) {
      return;
    }
    if (msg == null) return;
    // 两种形状都能进：整条信封（sync/evt/skip）或 `plan` 帧（{v,k:'plan',msg}）
    Map<String, Object?> env = msg;
    if (jsStr(msg['k'] ?? '') == RoomFrameKind.plan) {
      env = asMap(msg['msg']);
    }
    if (env.isEmpty) return;
    onMsg?.call(env);
    final result = client.receive(env);
    if (result.kind == 'sync') syncEpoch += 1;
    // ★ P14 P0（公网同一条洞）：这条路以前**完全不看** gap —— 中继偶发丢帧 /
    //   重连窗口里漏一帧，客户端就永久停在旧轮次（序号闸门此后拒绝一切增量，
    //   玩家侧表现为「轮次不跟随、点了没反应」且没有自愈）。与局域网同口径：
    //   缺口 → 立刻向权威端要全量（权威端 sync 分支回 `syncFor(seat)`，
    //   一份全量就能把 lastSeq 推到 log.seq，缺口清零）。
    if (asMap(result.toJson())['gap'] == true) requestSync();
    onChange?.call();
  }

  void _send(String text) {
    if (connected) {
      _socket.send(text);
    } else {
      _queue.add(text);
    }
  }

  void _flush() {
    final pending = List<String>.of(_queue);
    _queue.clear();
    for (final t in pending) {
      _socket.send(t);
    }
  }

  static String _joinError(CloudHttpResponse res) {
    switch (res.errorCode) {
      case 'not_found':
        return '中继上没有这间房（房号错了，或房间已过期）';
      case 'room_full':
        return '这间房人满了';
      case 'room_closed':
        return '房主已结束这间房';
      case 'room_suspended':
        return '这间房已挂起，等房主复活';
      case 'bad_pwd':
      case 'wrong_pwd':
        return '房间密码不对';
      default:
        break;
    }
    if (res.error.isNotEmpty) return '连不上中继：${res.error}';
    return '加入失败（HTTP ${res.status}）';
  }
}

/// 只为「成员列表」用的轻量视图：中继返回的 meta 里没有成员明细，
/// 全部成员信息仍然从 KP 那台设备的 sync 里来 —— 这里刻意什么都不做，
/// 免得有人误以为「云端也存了一份」。
int cloudMemberCountOf(Map<String, Object?> state) =>
    asList(state['members']).length;
