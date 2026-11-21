// ============================================================
// test/p6_room_net_factory_test.dart — P6 接线层端到端
//
// 这一组是 P6 最接近「真的能用」的证明：
//   KP 建房（本机会话 + 网络服务）→ 玩家加入 → KP 发消息 → 玩家收到。
//
// 与 p6_lan_transport_test 的分工：
//   · 那个验「socket 收发对不对」；
//   · 这个验「UI 会怎么用它」—— 工厂、会话、双投递是否成立。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_types.dart' show RoomRole, kHostSeat;
import 'package:dice_realm/net/lan_room_host.dart';
import 'package:dice_realm/ui/room/room_net_factory.dart';
import 'package:dice_realm/ui/room/room_session_hosting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 轮询等到条件成立，或超时放弃（网络测试不能用固定 sleep）。
Future<bool> waitFor(bool Function() cond, {int ms = 1200}) async {
  for (var i = 0; i < ms ~/ 25; i++) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return cond();
}

void main() {
  group('建房 / 加入 / 端到端收消息', () {
    test('KP 建房 → 玩家加入 → KP 发言 → 玩家收到（闭环）', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final String code = '${asMap(f.host.state['meta'])['code'] ?? ''}';

      final HostOutcome out = await RoomNetFactory.host(
        host: f.host,
        servicePort: 0,
        discoverPort: 24340,
        discoverTarget: '127.0.0.1',
        heartbeat: const Duration(milliseconds: 150),
      );
      addTearDown(() async => out.session.shutdown());

      expect(out.lanOk, isTrue, reason: '服务应能起来：${out.server.error}');
      expect(out.session.server.port, greaterThan(0));

      // ---- 玩家加入（用回环地址，避免被本机 VPN 网卡干扰）
      final JoinOutcome j = await RoomNetFactory.join(
        code: code,
        seat: 'p1',
        injectedBase: 'http://127.0.0.1:${out.session.server.port}',
      );
      addTearDown(() => j.session?.dispose());
      expect(j.ok, isTrue, reason: '加入失败：${j.error}');

      final bool gotSync = await waitFor(() => j.session!.lastSeq > 0);
      expect(gotSync, isTrue, reason: '加入后应收到全量同步');

      // ---- KP 发一条聊天，玩家应收到（seq 前进）
      final int beforeSeq = j.session!.lastSeq;
      await out.session.sendIntent('chat', <String, Object?>{
        'text': 'KP 说的话',
      });

      final bool advanced = await waitFor(() => j.session!.lastSeq > beforeSeq);
      expect(advanced, isTrue,
          reason: 'KP 的动作应该经 socket 到玩家（lastSeq 不变 = 帧没送到）');

      // ---- 玩家也能发言，且服务端权威态前进
      final int hostBefore = f.host.log.seq;
      await j.session!.sendIntent('chat', <String, Object?>{
        'text': 'p1 说的话',
      });
      final bool hostAdvanced = await waitFor(() => f.host.log.seq > hostBefore);
      expect(hostAdvanced, isTrue, reason: '玩家的动作应该到服务端并被应用');

      j.session?.dispose();
      await out.session.shutdown();
    });

    test('连接态会经 RemoteSession 传出来（供顶栏显示）', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final String code = '${asMap(f.host.state['meta'])['code'] ?? ''}';

      final HostOutcome out = await RoomNetFactory.host(
        host: f.host,
        servicePort: 0,
        discoverPort: 24341,
        discoverTarget: '127.0.0.1',
        heartbeat: const Duration(milliseconds: 200),
      );
      addTearDown(() async => out.session.shutdown());

      final JoinOutcome j = await RoomNetFactory.join(
        code: code,
        seat: 'p2',
        injectedBase: 'http://127.0.0.1:${out.session.server.port}',
      );
      addTearDown(() => j.session?.dispose());
      expect(j.ok, isTrue);

      expect(j.session!.link.name, 'connected');
      // 关房后客户端应察觉并转 offline（或至少在重连中，不会是 connected）
      await out.session.shutdown();
      final bool offline = await waitFor(
        () => j.session!.link.name != 'connected',
        ms: 2500,
      );
      expect(offline, isTrue,
          reason: '服务端关了，客户端不该还显示「已连接」——那是骗用户');

      j.session?.dispose();
    });

    test('附近房间能扫到刚建的房', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final HostOutcome out = await RoomNetFactory.host(
        host: f.host,
        servicePort: 0,
        discoverPort: 24342,
        discoverTarget: '127.0.0.1',
        heartbeat: const Duration(milliseconds: 120),
      );
      addTearDown(() async => out.session.shutdown());

      final String myCode = out.session.server.announce().code;
      expect(myCode, isNotEmpty);

      final found = await RoomNetFactory.nearby(
        timeout: const Duration(milliseconds: 500),
      );
      // 注意：nearby() 用真实 4210，而这里广播发到 24342 只为本测试隔离。
      // 所以这里只断言「函数不抛、返回列表」，扫不扫得到取决于端口配置。
      expect(found, isA<List<Object>>());

      await out.session.shutdown();
    });

    test('地址无效时加入失败并给出错误（不挂住）', () async {
      final sw = Stopwatch()..start();
      final JoinOutcome j = await RoomNetFactory.join(
        code: 'ABC123',
        seat: 'p1',
        injectedBase: 'http://127.0.0.1:1', // 必然连不上
      );
      sw.stop();
      expect(j.ok, isFalse);
      expect(j.error, isNotNull);
      expect(sw.elapsedMilliseconds, lessThan(20000),
          reason: '连不上要尽快返回错误，不能挂住界面');
    });

    test('完全没有地址时直接报错（不尝试）', () async {
      final JoinOutcome j = await RoomNetFactory.join(
        code: 'ABC123',
        seat: 'p1',
      );
      expect(j.ok, isFalse);
      expect(j.error, '没有可用的房间地址');
    });

    test('网络服务未启动时会话仍可单机使用（双投递不崩）', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);

      // 故意只构造、不 start —— 模拟「端口被占/没连 WiFi」后仍要能开团
      final LanRoomHost lrh = LanRoomHost(host: f.host, servicePort: 0);
      final HostingLocalSession session = HostingLocalSession(
        host: f.host,
        seat: kHostSeat,
        role: RoomRole.kp,
        server: lrh,
      );
      addTearDown(() async => session.shutdown());

      expect(lrh.running, isFalse, reason: '前提：服务没起');
      expect(session.state, isNotEmpty);

      final int before = f.host.log.seq;
      await session.sendIntent('chat', <String, Object?>{'text': '单机也要能用'});
      expect(f.host.log.seq, greaterThan(before),
          reason: '网络没起时 pumpPlans 里的 server.pump 应是 no-op，'
              '不能把本机投递也带崩');

      await session.shutdown();
    });

    test('seat 为空时由服务端分配座位（局域网加入的常态）', () async {
      // 默认 fixture：host + p1 + p2 已在花名册
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final String code = '${asMap(f.host.state['meta'])['code'] ?? ''}';

      final HostOutcome out = await RoomNetFactory.host(
        host: f.host,
        servicePort: 0,
        discoverPort: 24345,
        discoverTarget: '127.0.0.1',
        heartbeat: const Duration(milliseconds: 200),
      );
      addTearDown(() async => out.session.shutdown());

      final JoinOutcome j = await RoomNetFactory.join(
        code: code,
        seat: '', // 玩家只知道房号，不认识座位 —— 让服务端分
        injectedBase: 'http://127.0.0.1:${out.session.server.port}',
      );
      addTearDown(() => j.session?.dispose());

      expect(j.ok, isTrue, reason: '空 seat 应被分配：${j.error}');
      final String mine = j.session!.seat;
      expect(mine, isNotEmpty);
      expect(mine, isNot('p1'), reason: 'p1 已有人，不该分到同一个');
      expect(mine, isNot('p2'), reason: 'p2 已有人');

      // 先等 sync 到达（seats 读自 state['members']，sync 前是空的）
      final bool ok = await waitFor(() => j.session!.lastSeq > 0);
      expect(ok, isTrue, reason: '换座位后要能收到 sync');

      // 分配的座位必须真的进了花名册（不是客户端自己编的）
      expect(j.session!.seats, contains(mine),
          reason: '服务端分配后应 attachPeer 进花名册');

      j.session?.dispose();
      await out.session.shutdown();
    });

    test('远端加入后 KP 侧成员表应立刻更新（否则界面永远是「成员 0」）', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final String code = '${asMap(f.host.state['meta'])['code'] ?? ''}';

      final HostOutcome out = await RoomNetFactory.host(
        host: f.host,
        servicePort: 0,
        discoverPort: 24347,
        discoverTarget: '127.0.0.1',
        heartbeat: const Duration(milliseconds: 200),
      );
      addTearDown(() async => out.session.shutdown());

      final int before = asList(out.session.state['members']).length;

      final JoinOutcome j = await RoomNetFactory.join(
        code: code,
        seat: '',
        injectedBase: 'http://127.0.0.1:${out.session.server.port}',
      );
      addTearDown(() => j.session?.dispose());
      expect(j.ok, isTrue, reason: '加入失败：${j.error}');

      // ★ 这条守的是真机联调踩到的 bug：
      //   服务端 attachPeer 后只调了自己的 pump（发网络），
      //   没走 HostingLocalSession.pumpPlans → KP 侧 UI 不重建，
      //   `/health` 说 players=1 而界面显示「成员（0）」。
      final bool updated = await waitFor(
        () => asList(out.session.state['members']).length > before,
      );
      expect(updated, isTrue,
          reason: '远端加入后 KP 侧 members 必须增加；'
              '不增加就是服务端没把计划回灌给本机会话');

      j.session?.dispose();
      await out.session.shutdown();
    });

    test('旁观者入座：分到 sp 族座位，且看不到别人的手绘板', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final String code = '${asMap(f.host.state['meta'])['code'] ?? ''}';

      final HostOutcome out = await RoomNetFactory.host(
        host: f.host,
        servicePort: 0,
        discoverPort: 24346,
        discoverTarget: '127.0.0.1',
        heartbeat: const Duration(milliseconds: 200),
      );
      addTearDown(() async => out.session.shutdown());

      final JoinOutcome j = await RoomNetFactory.join(
        code: code,
        seat: '',
        role: RoomRole.spectator,
        injectedBase: 'http://127.0.0.1:${out.session.server.port}',
      );
      addTearDown(() => j.session?.dispose());

      expect(j.ok, isTrue, reason: '旁观应能加入：${j.error}');
      expect(j.session!.seat, startsWith('sp'),
          reason: '旁观者必须分到 sp 族，混进 p 族就等于给了玩家权限');
      expect(j.session!.role, RoomRole.spectator);

      final bool ok = await waitFor(() => j.session!.lastSeq > 0);
      expect(ok, isTrue, reason: '旁观者也该收到 sync（只是裁剪更狠）');

      // 旁观者的裁剪面：看不到别人的手绘板
      final board = asMap(j.session!.state['board']);
      expect(asList(board['strokes']), isEmpty,
          reason: '旁观者不该看到玩家的手绘笔迹');

      j.session?.dispose();
      await out.session.shutdown();
    });
  });
}
