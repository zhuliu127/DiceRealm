// ============================================================
// test/p10_t1_cloud_room_test.dart — P10 第 1 期 B5（公网开房）
//
// 这一批**不碰真网络**：`cloudHttp` / `cloudSocketFactory` 两个注入点换成
// 内存替身，把「云端 /room 中继」的控制协议在进程内实现一遍，于是
// 「登记 → 握手 → 转发 → 踢人」整条链路都能被普通 test 跑到，而且逐帧可断言。
//
// 为什么要这么测（而不是只测 UI 有没有按钮）：
//   用户要的是「公网开房**加回来**」，最容易犯的错恰恰是「给一个点下去连不上
//   的入口」。所以这里必须证明：KP 侧的 `SendPlan` 真的经中继送到了玩家侧，
//   玩家侧的 intent 也真的回到了权威端，且两侧用的都是 `SendPlan.toJson()`。
//
// 协议口径详见 `lib/net/cloud_room.dart` 头部（依据服务端 room_server.py）。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_model_host_core.dart'
    show RoomHost, RoomHostOptions;
import 'package:dice_realm/domain/room_types.dart' show RoomIntent, RoomRole;
import 'package:dice_realm/net/cloud_room.dart';
import 'package:dice_realm/theme.dart' show Palette;
import 'package:dice_realm/ui/room/room_session_cloud.dart'
    show CloudHostingSession, CloudRemoteSession;
import 'package:dice_realm/ui/room/room_boot.dart' show roomSaveSlots;
import 'package:dice_realm/ui/room/room_entry_page.dart'
    show RoomEntryKeys, RoomEntryPage;
import 'package:dice_realm/ui/room/room_net_factory.dart' show RoomNetFactory;
import 'package:dice_realm/ui/room/room_session_local.dart' show RoomLoopbackHub;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' show newMemorySettings, pumpApp;

// ------------------------------------------------------------
// 内存替身：HTTP + WebSocket + 一个最小的"中继"
// ------------------------------------------------------------

/// 中继上的一条连接。
class RelayPeer {
  RelayPeer(this.cid, this.token, this.socket);

  final String cid;
  final String token;
  final FakeCloudSocket socket;
  String? seat;
}

/// 一个**只做转发**的中继（与 room_server.py 的控制层同形）。
///
/// ★ 它不解析应用层载荷，只认 `hub.*` 控制帧 —— 这正是服务端的行为。
class FakeRelay {
  FakeRelay({this.code = 'AB12CD'});

  final String code;
  final List<RelayPeer> peers = <RelayPeer>[];
  int _seq = 0;

  /// 登记次数（断言"只登记一次"）。
  int registrations = 0;

  /// 关房调用次数（`hub.close`）。
  int closes = 0;

  /// 收到的应用层载荷（原样文本），用来断言"发的是 SendPlan.toJson"。
  final List<String> forwarded = <String>[];
  final List<Map<String, Object?>> hubFrames = <Map<String, Object?>>[];

  CloudHttpResponse post(Uri url, Map<String, Object?> body) {
    final String path = url.path;
    if (path.endsWith('/api/rooms')) {
      registrations += 1;
      return CloudHttpResponse(
        ok: true,
        status: 200,
        json: <String, Object?>{
          'code': code,
          'hostToken': 'host-token',
          'wsBase': 'https://relay.example.com/room',
        },
      );
    }
    final RegExp joinRe = RegExp(r'/api/rooms/([A-Z0-9]+)/join$');
    final RegExpMatch? m = joinRe.firstMatch(path);
    if (m != null) {
      if (m.group(1) != code) {
        return const CloudHttpResponse(
          ok: false,
          status: 404,
          json: <String, Object?>{'error': 'not_found'},
        );
      }
      return CloudHttpResponse(
        ok: true,
        status: 200,
        json: <String, Object?>{
          'ok': true,
          'code': code,
          'mtoken': 'member-token',
          'wsUrl': 'https://relay.example.com/room',
          'role': RoomRole.player,
        },
      );
    }
    return const CloudHttpResponse(
      ok: false,
      status: 404,
      json: <String, Object?>{'error': 'not_found'},
    );
  }

  /// WS 升级：按 token 认角色，然后按服务端的行为推 ready / peer.open。
  void accept(FakeCloudSocket socket, Uri url) {
    final String token = url.queryParameters['t'] ?? '';
    final String cid = 'c${++_seq}';
    final RelayPeer peer = RelayPeer(cid, token, socket);
    peers.add(peer);
    socket.relay = this;
    socket.peer = peer;
    if (token == 'host-token') {
      peer.seat = '';
      socket.push(<String, Object?>{'k': 'host.ok'});
      // 房主（重）连接：把已在线的成员补发一遍 peer.open
      for (final RelayPeer p in peers) {
        if (p == peer || p.seat == null) continue;
        socket.push(<String, Object?>{
          'k': 'peer.open',
          'cid': p.cid,
          'seat': p.seat,
          'role': RoomRole.player,
          'nickname': '玩家 ${p.seat}',
        });
      }
      return;
    }
    // 成员：座位由 token 派生（这里固定 p1，够用）
    peer.seat = 'p1';
    socket.push(<String, Object?>{
      'k': 'ready',
      'cid': cid,
      'seat': 'p1',
      'role': RoomRole.player,
      'code': code,
    });
    for (final RelayPeer p in peers) {
      if (p.seat == '') {
        // 通知 KP：有人进来了
        p.socket.push(<String, Object?>{
          'k': 'peer.open',
          'cid': cid,
          'seat': 'p1',
          'role': RoomRole.player,
          'nickname': '远端调查员',
        });
      }
    }
  }

  /// 中继收到一条文本：KP 发的是 `hub.*`，成员发的是应用层载荷。
  void receive(RelayPeer from, String text) {
    Map<String, Object?> msg = const <String, Object?>{};
    try {
      final Object? d = jsonDecode(text);
      if (d is Map) msg = d.cast<String, Object?>();
    } catch (_) {
      return;
    }
    final String k = '${msg['k'] ?? ''}';
    if (from.seat == '') {
      // 权威端 → 中继
      hubFrames.add(msg);
      if (k == 'hub.broadcast') {
        final String body = '${msg['text'] ?? ''}';
        forwarded.add(body);
        for (final RelayPeer p in peers) {
          if (p.seat != null && p.seat!.isNotEmpty) p.socket.pushRaw(body);
        }
        return;
      }
      if (k == 'hub.send') {
        final String body = '${msg['text'] ?? ''}';
        forwarded.add(body);
        for (final RelayPeer p in peers) {
          if (p.cid == msg['cid']) p.socket.pushRaw(body);
        }
        return;
      }
      if (k == 'hub.close') {
        closes += 1;
        for (final RelayPeer p in peers) {
          if (p.cid == msg['cid']) p.socket.closedByHost();
        }
        return;
      }
      return;
    }
    // 成员 → 中继 → 权威端
    for (final RelayPeer p in peers) {
      if (p.seat == '') {
        p.socket.push(<String, Object?>{
          'k': 'peer.msg',
          'cid': from.cid,
          'text': text,
        });
      }
    }
  }

  void drop(RelayPeer peer) {
    peers.remove(peer);
    for (final RelayPeer p in peers) {
      if (p.seat == '') {
        p.socket.push(<String, Object?>{
          'k': 'peer.close',
          'cid': peer.cid,
          'seat': peer.seat ?? '',
        });
      }
    }
  }
}

/// 内存 socket（可注入）。
class FakeCloudSocket implements CloudSocket {
  FakeCloudSocket({this.relay, this.failConnect = false});

  FakeRelay? relay;
  final bool failConnect;

  RelayPeer? peer;
  void Function(String)? _onText;
  void Function()? _onClosed;
  bool closed = false;

  /// 发出去的原始文本（断言"应用层载荷 = RoomFrame JSON"）。
  final List<String> sent = <String>[];

  @override
  set onText(void Function(String text)? v) => _onText = v;

  @override
  set onClosed(void Function()? v) => _onClosed = v;

  @override
  Future<void> connect(String url) async {
    if (failConnect) throw StateError('connect refused');
    relay!.accept(this, Uri.parse(url));
  }

  @override
  void send(String text) {
    sent.add(text);
    relay!.receive(peer!, text);
  }

  @override
  Future<void> close() async {
    closed = true;
    final p = peer;
    if (p != null) relay!.drop(p);
  }

  /// 中继 → 这条连接（一条**中继控制帧**）。
  void push(Map<String, Object?> frame) =>
      _onText?.call(jsonEncode(frame));

  /// 中继 → 这条连接（一条**应用层载荷**，原样透传）。
  void pushRaw(String text) => _onText?.call(text);

  /// 房主把这条连接踢掉。
  void closedByHost() {
    closed = true;
    _onClosed?.call();
  }
}

/// 内存 HTTP。
class FakeCloudHttp implements CloudHttpTransport {
  FakeCloudHttp(this.relay);

  final FakeRelay relay;

  @override
  Future<CloudHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async =>
      relay.post(url, body);
}

void main() {
  setUp(() => Palette.useBrightness(Brightness.dark));
  tearDown(() => Palette.useBrightness(Brightness.dark));

  /// 造一套「中继 + 注入点」。
  (FakeRelay, List<FakeCloudSocket>) installRelay() {
    final FakeRelay relay = FakeRelay();
    final List<FakeCloudSocket> sockets = <FakeCloudSocket>[];
    cloudHttp = FakeCloudHttp(relay);
    cloudSocketFactory = () {
      final FakeCloudSocket s = FakeCloudSocket(relay: relay);
      sockets.add(s);
      return s;
    };
    return (relay, sockets);
  }

  RoomHost newHost(String code) => RoomHost(RoomHostOptions(
        meta: <String, Object?>{
          'code': code,
          'name': '公网测试团',
          'kpName': '老 K',
          'maxPlayers': 6,
        },
      ));

  // ---------------------------------------------------------
  // 地址与协议口径
  // ---------------------------------------------------------
  group('B5 地址规范化与 WS 地址', () {
    test('normalizeCloudBase：去空格与尾斜杠；空串仍是空（= 未配置）', () {
      expect(normalizeCloudBase('  https://a.example.com/room/  '),
          'https://a.example.com/room');
      expect(normalizeCloudBase(''), '');
      expect(normalizeCloudBase('   '), '');
    });

    test('isCloudBase：公网域名才算中继；局域网 http 地址一律不算', () {
      expect(isCloudBase('https://relay.example.com/room'), isTrue);
      expect(isCloudBase('http://relay.example.com/room'), isTrue);

      // ★ P12 真机 bug 修正：原用例假设「局域网是裸 ip:port」，但 UDP 广播
      //   里的 base 实际是 `http://192.168.x.x:4211`（lan_server._baseFor），
      //   手输完整 URL 也是这个形状。只按 scheme 判会把它送进云端 → 404。
      //   isTrue → isFalse 是**收紧**判定，不是放宽断言。
      expect(isCloudBase('http://192.168.1.7:4211'), isFalse);
      expect(isCloudBase('http://10.0.2.16:4211'), isFalse); // 模拟器宿主
      expect(isCloudBase('http://10.0.2.2:4211'), isFalse);
      expect(isCloudBase('http://172.20.5.9:4211'), isFalse);
      expect(isCloudBase('http://172.32.5.9:4211'), isTrue); // 172.32 不是私有段
      expect(isCloudBase('http://127.0.0.1:4211'), isFalse);
      expect(isCloudBase('http://localhost:4211'), isFalse);
      expect(isCloudBase('http://169.254.3.8:4211'), isFalse);

      expect(isCloudBase('192.168.1.7:4211'), isFalse);
      expect(isCloudBase(''), isFalse);
    });

    test('cloudWsUrl：https → wss，并带上 code / t / d 三个参数', () {
      final String url = cloudWsUrl(
        'https://relay.example.com/room',
        code: 'AB12CD',
        token: 'tk',
      );
      final Uri u = Uri.parse(url);
      expect(u.scheme, 'wss');
      expect(u.path, '/room/ws');
      expect(u.queryParameters['code'], 'AB12CD');
      expect(u.queryParameters['t'], 'tk');
      expect(u.queryParameters['d'], isNotEmpty,
          reason: '服务端用 d= 设备标识认"同一个人重连回原座"');
    });
  });

  // ---------------------------------------------------------
  // 登记（HTTP）
  // ---------------------------------------------------------
  group('B5 中继登记', () {
    test('POST /api/rooms 拿回 code / hostToken / wsBase', () async {
      final (FakeRelay relay, _) = installRelay();
      final CloudHostStart r = await CloudRoomHostLink.registerRoom(
        base: 'https://relay.example.com/room',
        name: '公网团',
        kpName: '老 K',
      );
      expect(r.ok, isTrue);
      expect(r.code, relay.code);
      expect(r.token, 'host-token');
      expect(relay.registrations, 1);
    });

    test('中继不可达 → 如实报错（不返回假成功）', () async {
      cloudHttp = _DownHttp();
      final CloudHostStart r = await CloudRoomHostLink.registerRoom(
        base: 'https://relay.example.com/room',
        name: 'x',
        kpName: 'y',
      );
      expect(r.ok, isFalse);
      expect(r.code, isEmpty);
      expect(r.error, isNotEmpty);
    });
  });

  // ---------------------------------------------------------
  // 端到端：KP 开公网房 → 玩家加入 → 权威端计划真的送到玩家
  // ---------------------------------------------------------
  group('B5 KP ↔ 玩家：经中继的完整一轮', () {
    test('KP 的出站 SendPlan 经 hub.broadcast 到达玩家；玩家 intent 回到权威端',
        () async {
      final (FakeRelay relay, List<FakeCloudSocket> sockets) = installRelay();
      final RoomHost host = newHost('AB12CD');
      final RoomLoopbackHub hub = RoomLoopbackHub(host);
      final CloudRoomHostLink link = CloudRoomHostLink(
        base: 'https://relay.example.com/room',
        host: host,
        socket: FakeCloudSocket(relay: relay),
      );
      final CloudHostingSession kp = CloudHostingSession(
        host: host,
        seat: 'host',
        role: RoomRole.kp,
        cloudLink: link,
        hub: hub,
      );
      final CloudHostStart start =
          await link.start(name: '公网团', kpName: '老 K');
      expect(start.ok, isTrue, reason: 'start 失败：${start.error}');

      // 玩家侧：HTTP join + WS
      final CloudRoomClient client = CloudRoomClient(
        base: 'https://relay.example.com/room',
        code: 'AB12CD',
        nickname: '远端调查员',
        socket: FakeCloudSocket(relay: relay),
      );
      final CloudJoinResult join = await client.connect();
      expect(join.ok, isTrue, reason: '加入失败：${join.error}');
      expect(join.seat, 'p1', reason: '座位来自中继 ready 帧');

      final CloudRemoteSession player =
          CloudRemoteSession(client: client, roomCode: 'AB12CD');

      // ① 权威端真的把 p1 收进了花名册（走 attachPeer）
      expect(
        asList(host.state['members']).map(asMap).map((Map<String, Object?> m) => m['seat']),
        contains('p1'),
      );
      // ② attachPeer 产出的全量 sync 经中继送到了玩家手上
      expect(player.seat, 'p1');
      expect(asMap(player.state['meta'])['code'], 'AB12CD');
      expect(
        relay.forwarded,
        isNotEmpty,
        reason: 'B5：中继上必须出现过应用层载荷（否则玩家端永远是空房）',
      );
      // ③ 载荷是 SendPlan 里的信封 JSON（有 k 键），不是日志记录
      final Map<String, Object?> firstEnv =
          jsonDecode(relay.forwarded.first) as Map<String, Object?>;
      // 载荷必须是 `SendPlan.msg` 的信封形状：{k: sync|evt|skip, seq, ...}
      expect(firstEnv['k'], anyOf('sync', 'evt', 'skip'));
      expect(firstEnv['seq'], isNotNull);
      // 红线：**不是** `LogRecord.toWireJson()` 的 `{seq, evt}` 形状
      // （那是日志记录，会把明文 `p` 带出去）。
      expect(firstEnv.containsKey('evt'), isFalse,
          reason: '红线：只准发 SendPlan.toJson()，绝不准发 LogRecord.toWireJson()');
      expect(relay.forwarded.first.contains('"evt":'), isFalse);

      // ④ 玩家发 intent → 中继 → 权威端（绑定角色卡：权威端要真的落库）
      await player.sendIntent(RoomIntent.char, <String, Object?>{
        'id': 'c_p1',
        'name': '远端调查员',
        'sheet': <String, Object?>{
          'name': '远端调查员',
          'attrs': <String, Object?>{'str': 50},
          'status': <String, Object?>{'currentHP': 9, 'maxHP': 10},
        },
      });
      final List<Map<String, Object?>> p1 = asList(host.state['members'])
          .map(asMap)
          .where((Map<String, Object?> m) => m['seat'] == 'p1')
          .toList();
      expect(p1.first['charId'], 'c_p1',
          reason: 'B5：玩家经公网发的 intent 必须真的落到权威端');
      // 权威端算出的新计划也要回到玩家（binding 全流程闭环）
      expect(
        asMap(asMap(p1.first['sheet'])['status'])['currentHP'],
        9,
      );

      // ⑤ 关房：KP 侧 closeRoom → 玩家侧收到 CLOSED（B3 的远端那一半）
      //   ⚠️ `room.close` 是 RoomConfirm.twice：UI 走 controller.dangerAction
      //   （= 发动作 + 补一条我确认）。这里没有 controller，就按同一顺序拆开写；
      //   只发 action 的话会停在 pending 队列里，状态一点不变。
      await kp.hostAction('room.close');
      await kp.sendIntent(RoomIntent.confirm, <String, Object?>{
        'op': 'room.close',
        'by': kp.seat,
        'agree': true,
      });
      expect(asMap(player.state['meta'])['status'], 'CLOSED',
          reason: 'B5/B3：KP 关房后远端玩家也要看到 CLOSED');

      await link.stop();
      await client.dispose();
    });

    test('KP 踢人 → 中继关掉那条连接（被踢者立刻掉线）', () async {
      final (FakeRelay relay, _) = installRelay();
      final RoomHost host = newHost('AB12CD');
      final RoomLoopbackHub hub = RoomLoopbackHub(host);
      final CloudRoomHostLink link = CloudRoomHostLink(
        base: 'https://relay.example.com/room',
        host: host,
        socket: FakeCloudSocket(relay: relay),
      );
      final CloudHostingSession kp = CloudHostingSession(
        host: host,
        seat: 'host',
        role: RoomRole.kp,
        cloudLink: link,
        hub: hub,
      );
      await link.start(name: '公网团', kpName: '老 K');
      final FakeCloudSocket playerSocket = FakeCloudSocket(relay: relay);
      final CloudRoomClient client = CloudRoomClient(
        base: 'https://relay.example.com/room',
        code: 'AB12CD',
        socket: playerSocket,
      );
      expect((await client.connect()).ok, isTrue);

      await kp.hostAction('room.kick', <String, Object?>{'seat': 'p1'});
      // 权威端的 kick 会给被踢者一条 KICK 计划；这条计划经 hub.send 走中继
      expect(relay.forwarded, isNotEmpty);
      // 被踢者的花名册条目被清掉
      expect(
        asList(host.state['members'])
            .map(asMap)
            .where((Map<String, Object?> m) => m['seat'] == 'p1'),
        isEmpty,
      );
      await link.stop();
      await client.dispose();
    });

    test('中继连不上 → 开房失败如实返回，不产生半成品房间', () async {
      final FakeRelay relay = FakeRelay();
      cloudHttp = FakeCloudHttp(relay);
      cloudSocketFactory = () => FakeCloudSocket(relay: relay, failConnect: true);
      final RoomHost host = newHost('AB12CD');
      final CloudRoomHostLink link = CloudRoomHostLink(
        base: 'https://relay.example.com/room',
        host: host,
        socket: FakeCloudSocket(relay: relay, failConnect: true),
      );
      final CloudHostStart r = await link.start(name: 'x', kpName: 'y');
      expect(r.ok, isFalse);
      expect(r.error, isNotEmpty);
      expect(link.running, isFalse);
    });

    test('玩家加入时中继报错（房号错 / 人满）→ 把原因翻成人话', () async {
      final FakeRelay relay = FakeRelay();
      cloudHttp = _JoinErrorHttp('room_full');
      final CloudRoomClient client = CloudRoomClient(
        base: 'https://relay.example.com/room',
        code: 'ZZZZZZ',
        socket: FakeCloudSocket(relay: relay),
      );
      final CloudJoinResult r = await client.connect();
      expect(r.ok, isFalse);
      expect(r.error, contains('人满'));
    });
  });

  // ---------------------------------------------------------
  // UI 层：未配置 → 引导去设置；已配置 → 真的出现公网入口
  // ---------------------------------------------------------
  group('B5 入口页的两条路', () {
    setUp(() {
      roomSaveSlots.clear();
      RoomNetFactory.discoveryEnabled = false;
      RoomNetFactory.networkEnabled = false;
      RoomNetFactory.servicePortOverride = 0;
    });
    tearDown(() {
      RoomNetFactory.servicePortOverride = null;
      RoomNetFactory.networkEnabled = true;
      RoomNetFactory.discoveryEnabled = true;
    });

    testWidgets('未配置公网地址：不渲染「开公网房间」，只给「去设置」',
        (WidgetTester tester) async {
      final settings = await newMemorySettings();
      settings.roomBase = '';
      await pumpApp(
        tester,
        settings: settings,
        home: RoomEntryPage(saveStore: roomSaveSlots),
      );

      expect(find.byKey(RoomEntryKeys.createSubmit), findsOneWidget,
          reason: '局域网入口必须一直在');
      expect(find.byKey(RoomEntryKeys.createSubmitCloud), findsNothing,
          reason: 'K7：没配地址不许出现点下去必然失败的假按钮');
      expect(find.byKey(RoomEntryKeys.cloudSetupHint), findsOneWidget,
          reason: '要有一个真的「去设置」入口，而不是一条死路');
      expect(find.textContaining('公网开房需要先在'), findsOneWidget);
    });

    testWidgets('已配置：出现「开公网房间」，并如实展示中继地址',
        (WidgetTester tester) async {
      final settings = await newMemorySettings();
      settings.roomBase = 'https://relay.example.com/room';
      await pumpApp(
        tester,
        settings: settings,
        home: RoomEntryPage(saveStore: roomSaveSlots),
      );

      expect(find.byKey(RoomEntryKeys.createSubmitCloud), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.cloudSetupHint), findsNothing);
      expect(find.textContaining('relay.example.com/room'), findsWidgets,
          reason: '要告诉用户"这间房中继到哪儿"，不能只说"已配置"');
    });
  });
}

/// 中继直接不可达（DNS 挂了 / 端口不通）。
class _DownHttp implements CloudHttpTransport {
  @override
  Future<CloudHttpResponse> postJson(Uri url, Map<String, Object?> body) async =>
      const CloudHttpResponse(ok: false, error: 'connection refused');
}

/// 中继返回某个业务错误码（房间满 / 房号错 ……）。
class _JoinErrorHttp implements CloudHttpTransport {
  _JoinErrorHttp(this.code);

  final String code;

  @override
  Future<CloudHttpResponse> postJson(Uri url, Map<String, Object?> body) async =>
      CloudHttpResponse(
        ok: false,
        status: 403,
        json: <String, Object?>{'ok': false, 'error': code},
      );
}
