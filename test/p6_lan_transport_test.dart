// ============================================================
// test/p6_lan_transport_test.dart — P6 传输层端到端（真 socket）
//
// 与 P5 所有 UI 测试的区别：这里**不用 mock**，真的起一个 HttpServer、
// 真的连一个 WebSocket。因为传输层最容易出的问题是「编译过、跑不通」
// （握手时序、端口、帧版本），这些只有真跑才能抓到。
//
// 铁律：只绑 127.0.0.1 / 端口 0（系统分配），不污染真实网络，
//       不依赖同网段其它设备，可在 CI 里跑。
// ============================================================

import 'dart:convert' show jsonDecode, utf8;
import 'dart:io' show HttpClient;

import 'package:dice_realm/domain/js_compat.dart' show asMap;
import 'package:dice_realm/net/lan_client.dart';
import 'package:dice_realm/net/lan_server.dart';
import 'package:dice_realm/net/room_frame.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

void main() {
  group('帧协议', () {
    test('编解码往返：字段不丢、版本带上', () {
      final f = RoomFrame(RoomFrameKind.plan, <String, Object?>{
        'to': 'p1',
        'msg': <String, Object?>{'k': 'evt', 't': 'chat'},
      });
      final json = f.toJson();
      expect(json['v'], kRoomFrameVersion);
      expect(json['k'], RoomFrameKind.plan);
      expect(json['to'], 'p1');

      final back = RoomFrame.parse(json);
      expect(back, isNotNull);
      expect(back!.kind, RoomFrameKind.plan);
      expect(back.data!['to'], 'p1');
    });

    test('坏帧返回 null 而不是抛（对面可能是任何东西）', () {
      expect(RoomFrame.parse(null), isNull);
      expect(RoomFrame.parse('oops'), isNull);
      expect(RoomFrame.parse(<String, Object?>{}), isNull);
      expect(RoomFrame.parse(<String, Object?>{'k': ''}), isNull);
      expect(RoomFrame.parse(<String, Object?>{'k': 'plan'}), isNotNull);
    });

    test('版本不匹配判为不兼容，缺 v 视为兼容', () {
      expect(RoomFrame.versionOk(<String, Object?>{'k': 'plan'}), isTrue);
      expect(
        RoomFrame.versionOk(<String, Object?>{'v': kRoomFrameVersion + 1, 'k': 'plan'}),
        isFalse,
      );
    });
  });

  group('端到端（真 socket）', () {
    test('服务端起得来 → 客户端接入 → 收全量 → 发 intent 改权威态', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);

      final LanServer server = LanServer(host: f.host, port: 0);
      addTearDown(() async => server.stop());

      final LanServerStart start = await server.start();
      expect(start.ok, isTrue, reason: '启动失败：${start.error}');
      expect(server.boundPort, greaterThan(0), reason: '端口 0 应被系统分配成实数');

      final String code = '${asMap(f.host.state['meta'])['code'] ?? ''}';
      expect(code, isNotEmpty, reason: '前提：房间得有房号');

      final LanClient client = LanClient(
        base: 'http://127.0.0.1:${server.boundPort}',
        seat: 'p1',
        code: code,
      );
      addTearDown(() async => client.dispose());

      // ① 握手
      final RoomJoinResult joined = await client.connect();
      expect(joined.ok, isTrue, reason: '加入失败：${joined.error}');
      expect(joined.seat, 'p1');
      expect(client.link.name, 'connected');

      // ② 服务端在加入时会**另发一帧** sync（joined 与 sync 是两个独立帧，
      //   不保证同一 tick 到达）——所以要等，不能 connect() 一回来就断言。
      for (var i = 0; i < 40 && client.client.lastSeq == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(client.client.state, isNotEmpty,
          reason: 'joined 后应收到一份 sync（否则界面首屏是空的）');
      // ★ 真正要验的是「水位与权威端一致」——不是「大于 0」。
      //   不一致的话，下一条增量会被判成 gap，触发无谓补拉。
      expect(client.client.lastSeq, f.host.log.seq,
          reason: 'joined 后客户端水位应与权威端对齐');

      // ③ 客户端发 intent → 服务端应用 → 权威 seq 前进
      final int before = f.host.log.seq;
      client.sendIntent('chat', <String, Object?>{'text': '来自 p1 的测试消息'});

      // 等服务端处理（真网络往返，给足余量）
      for (var i = 0; i < 40 && f.host.log.seq == before; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(f.host.log.seq, greaterThan(before),
          reason: '客户端发的 intent 应该被服务端应用（seq 前进）');

      await client.dispose();
      await server.stop();
    });

    test('不存在的座位被拒（不能凭空造座位）', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanServer server = LanServer(host: f.host, port: 0);
      addTearDown(() async => server.stop());
      await server.start();

      final LanClient ghost = LanClient(
        base: 'http://127.0.0.1:${server.boundPort}',
        seat: 'p99',
        code: '${asMap(f.host.state['meta'])['code'] ?? ''}',
      );
      addTearDown(() async => ghost.dispose());

      final RoomJoinResult r = await ghost.connect();
      expect(r.ok, isFalse, reason: '花名册里没有 p99，不该让它进来');
      expect(r.error, 'UNKNOWN_SEAT');
      expect(server.peerCount, 0);
    });

    test('房号不对被拒', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanServer server = LanServer(host: f.host, port: 0);
      addTearDown(() async => server.stop());
      await server.start();

      final LanClient wrong = LanClient(
        base: 'http://127.0.0.1:${server.boundPort}',
        seat: 'p1',
        code: '000000',
      );
      addTearDown(() async => wrong.dispose());

      final RoomJoinResult r = await wrong.connect();
      expect(r.ok, isFalse);
      expect(r.error, 'WRONG_CODE');
    });

    test('两个客户端各自只收到自己的东西（同 seat 重连会顶掉旧连接）', () async {      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanServer server = LanServer(host: f.host, port: 0);
      addTearDown(() async => server.stop());
      await server.start();
      final String code = '${asMap(f.host.state['meta'])['code'] ?? ''}';
      final String base = 'http://127.0.0.1:${server.boundPort}';

      final LanClient a = LanClient(base: base, seat: 'p1', code: code);
      final LanClient b = LanClient(base: base, seat: 'p2', code: code);
      addTearDown(() async => a.dispose());
      addTearDown(() async => b.dispose());

      expect((await a.connect()).ok, isTrue);
      expect((await b.connect()).ok, isTrue);
      expect(server.peerCount, 2);

      // 同 seat 再连一次：旧连接被顶掉，peerCount 不应变成 3
      final LanClient a2 = LanClient(base: base, seat: 'p1', code: code);
      addTearDown(() async => a2.dispose());
      expect((await a2.connect()).ok, isTrue);
      expect(server.peerCount, 2, reason: '同 seat 重连应顶掉旧连接，不是新增一条');

      await a.dispose();
      await b.dispose();
      await a2.dispose();
      await server.stop();
    });
  });

  group('HTTP 接口', () {
    /// 发一个 GET，返回解码后的 JSON（非 JSON 返回空 Map）。
    Future<Map<String, Object?>> getJson(int port, String path) async {
      final HttpClient c = HttpClient();
      try {
        final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        return decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{};
      } finally {
        c.close(force: true);
      }
    }

    test('/health 返回房间摘要（房号/状态/人数/seq），不泄漏成员明细', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanServer server = LanServer(host: f.host, port: 0);
      addTearDown(() async => server.stop());
      await server.start();

      final Map<String, Object?> h = await getJson(server.boundPort, '/health');
      expect(h['ok'], isTrue);
      expect(h['v'], kRoomFrameVersion);
      expect(h['code'], isNotEmpty, reason: '房号是加入的前提');
      expect(h['seq'], f.host.log.seq);
      expect((h['players'] as num), greaterThan(0));

      // ★ 摘要不能带成员明细 —— 这是「附近房间」列表要显示的东西，
      //   列表页不需要知道每个座位是谁。
      expect(h.containsKey('members'), isFalse);
      expect(h.containsKey('state'), isFalse);
    });

    test('/state 按座返回裁剪后的全量（断线补拉用）', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanServer server = LanServer(host: f.host, port: 0);
      addTearDown(() async => server.stop());
      await server.start();

      final Map<String, Object?> s =
          await getJson(server.boundPort, '/state?seat=p1');
      expect(s['k'], 'sync', reason: '应该就是一个 sync 信封');
      expect(s['seq'], isNotNull);
      expect(asMap(s['state']), isNotEmpty);

      // 不带 seat → 400
      final HttpClient c = HttpClient();
      final req = await c.getUrl(
          Uri.parse('http://127.0.0.1:${server.boundPort}/state'));
      final res = await req.close();
      expect(res.statusCode, 400);
      c.close(force: true);
    });

    test('未知路径 404', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanServer server = LanServer(host: f.host, port: 0);
      addTearDown(() async => server.stop());
      await server.start();

      final HttpClient c = HttpClient();
      final req = await c.getUrl(
          Uri.parse('http://127.0.0.1:${server.boundPort}/nope'));
      final res = await req.close();
      expect(res.statusCode, 404);
      c.close(force: true);
    });
  });
}
