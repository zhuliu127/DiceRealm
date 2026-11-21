// ============================================================
// test/p6_lan_room_host_test.dart — 服务端编排门面
//
// 验的是「生命周期」而不是传输细节：
//   · 起服务失败时不能留下半启动状态（否则别人能搜到一间连不进的房）；
//   · stop 必须把广播一起停（否则会留下幽灵房）；
//   · announce 只能带公开字段（广播是明文的，同网段谁都能收）。
// ============================================================

import 'package:dice_realm/net/lan_client.dart';
import 'package:dice_realm/net/lan_discovery.dart';
import 'package:dice_realm/net/lan_room_host.dart';
import 'package:dice_realm/net/lan_server.dart' show LanServerStart;
import 'package:dice_realm/net/room_frame.dart' show RoomJoinResult;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

void main() {
  group('LanRoomHost 生命周期', () {
    test('启动 → 服务与广播都起；announce 字段正确；能被搜到；客户端能加入', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);

      final LanRoomHost lrh = LanRoomHost(
        host: f.host,
        servicePort: 0, // 系统分配，避免和真实 4211 抢端口
        discoverPort: 24320,
        discoverTarget: '127.0.0.1',
        beatEvery: const Duration(milliseconds: 120),
      );
      addTearDown(lrh.stop);

      final res = await lrh.start();
      expect(res.ok, isTrue, reason: '启动失败：${res.error}');
      expect(lrh.running, isTrue);
      expect(lrh.base, isNotEmpty);

      // ---- announce 只带公开字段
      final RoomAnnounce a = lrh.announce();
      expect(a.code, isNotEmpty, reason: '房号必须有，否则搜到了也没法加入');
      expect(a.base, lrh.base);
      expect(a.players, greaterThan(0), reason: '至少 KP 本人算一个玩家');
      expect(a.toJson().containsKey('members'), isFalse,
          reason: '广播是明文的，绝不能夹带成员明细/场景/日志');

      // ---- 能被发现
      final List<RoomAnnounce> found = await LanDiscoverer.scan(
        listenPort: 24320,
        timeout: const Duration(milliseconds: 900),
      );
      final Iterable<RoomAnnounce> mine =
          found.where((RoomAnnounce x) => x.code == a.code);
      expect(mine, isNotEmpty, reason: '广播后应该能搜到自己的房');

      // ---- 客户端能真的加进来
      // 用 127.0.0.1 而不是 lrh.base：base 是按「真局域网网卡」挑的，
      // 本机自连时走回环更稳定（也不会被代理/VPN 网卡干扰）。
      final LanClient c = LanClient(
        base: 'http://127.0.0.1:${lrh.port}',
        seat: 'p1',
        code: a.code,
      );
      addTearDown(c.dispose);
      final RoomJoinResult joined = await c.connect();
      expect(joined.ok, isTrue, reason: '加入失败：${joined.error}');
      expect(lrh.peerCount, 1);

      await c.dispose();
      await lrh.stop();
      expect(lrh.running, isFalse);
    });

    test('stop 后不再被搜到（不留幽灵房）', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanRoomHost lrh = LanRoomHost(
        host: f.host,
        servicePort: 0,
        discoverPort: 24321,
        discoverTarget: '127.0.0.1',
      );

      final LanServerStart res = await lrh.start();
      expect(res.ok, isTrue);
      final String code = lrh.announce().code;
      await lrh.stop();
      expect(lrh.running, isFalse);

      final List<RoomAnnounce> after = await LanDiscoverer.scan(
        listenPort: 24321,
        timeout: const Duration(milliseconds: 500),
      );
      expect(
        after.where((RoomAnnounce x) => x.code == code),
        isEmpty,
        reason: '停服后还搜得到 = 幽灵房，用户会反复点一个连不上的房',
      );
    });

    test('重复 start 幂等；stop 幂等', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync(inGame: true);
      final LanRoomHost lrh = LanRoomHost(
        host: f.host,
        servicePort: 0,
        discoverPort: 24322,
        discoverTarget: '127.0.0.1',
      );
      addTearDown(lrh.stop);

      final LanServerStart r1 = await lrh.start();
      final LanServerStart r2 = await lrh.start();
      expect(r1.ok, isTrue);
      expect(r2.ok, isTrue);
      expect(r1.base, r2.base, reason: '重复启动不该换个地址');

      await lrh.stop();
      await lrh.stop(); // 第二次不应抛
      expect(lrh.running, isFalse);
    });

    test('端口被占用时启动失败，且不留半启动状态', () async {
      final RoomUiFixture f1 = RoomUiFixture()..bootSync(inGame: true);
      final RoomUiFixture f2 = RoomUiFixture()..bootSync(inGame: true);

      // 先占住一个固定端口
      final LanRoomHost a = LanRoomHost(
        host: f1.host,
        servicePort: 24330,
        discoverPort: 24323,
        discoverTarget: '127.0.0.1',
      );
      addTearDown(a.stop);
      expect((await a.start()).ok, isTrue);

      // 第二个用同一端口 —— 应该失败
      final LanRoomHost b = LanRoomHost(
        host: f2.host,
        servicePort: 24330,
        discoverPort: 24324,
        discoverTarget: '127.0.0.1',
      );
      addTearDown(b.stop);
      final LanServerStart rb = await b.start();
      expect(rb.ok, isFalse, reason: '同一端口不该能起两个服务');
      expect(b.running, isFalse);

      // 关键：它也不该广播（否则会搜到一间连不进去的房）
      final List<RoomAnnounce> found = await LanDiscoverer.scan(
        listenPort: 24324,
        timeout: const Duration(milliseconds: 500),
      );
      expect(found, isEmpty, reason: '起服务失败就不该广播');

      await b.stop();
      await a.stop();
    });
  });
}
