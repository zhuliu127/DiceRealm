// ============================================================
// test/p6_lan_discovery_test.dart — P6 发现层与地址工具
//
// 两类测试：
//   · 地址工具（纯函数）—— 这里是旧版 16 个地址函数的核心，
//     最容易在移植时被简化成「一个 base 变量」，所以规则要逐条钉住；
//   · UDP 广播/发现（真 socket）—— 用 127.0.0.1 单播代替广播，
//     避免防火墙/容器环境收不到包造成的假红。
// ============================================================

import 'package:dice_realm/net/lan_discovery.dart';
import 'package:dice_realm/net/room_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('地址工具（旧版 16 个地址函数的核）', () {
    test('normalize：去空白、去尾斜杠、补 http://', () {
      expect(RoomEndpoint.normalize(' 192.168.1.7:4211/ '), 'http://192.168.1.7:4211');
      expect(RoomEndpoint.normalize('http://a.b:4211/'), 'http://a.b:4211');
      expect(RoomEndpoint.normalize('https://a.b'), 'https://a.b');
      expect(RoomEndpoint.normalize('   '), '', reason: '空 = 没配，不要补默认值');
    });

    test('looksValid：只认 http/https 且 host 非空', () {
      expect(RoomEndpoint.looksValid('192.168.1.7:4211'), isTrue);
      expect(RoomEndpoint.looksValid('http://192.168.1.7:4211'), isTrue);
      expect(RoomEndpoint.looksValid(''), isFalse);
      expect(RoomEndpoint.looksValid('ftp://x.y'), isFalse);
      expect(RoomEndpoint.looksValid('http://'), isFalse);
    });

    test('isPrivateHost：私网 / 回环 / 链路本地', () {
      for (final h in <String>[
        'localhost',
        '127.0.0.1',
        '10.1.2.3',
        '192.168.1.7',
        '172.16.0.1',
        '172.31.255.254',
        '169.254.1.1',
      ]) {
        expect(RoomEndpoint.isPrivateHost(h), isTrue, reason: '$h 应判为私网');
      }
      for (final h in <String>['8.8.8.8', '172.32.0.1', '172.15.0.1', 'example.com']) {
        expect(RoomEndpoint.isPrivateHost(h), isFalse, reason: '$h 应判为公网');
      }
    });

    test('split：逗号 / 分号 / 中文标点 / 空白都能拆，且过滤无效项', () {
      final got = RoomEndpoint.split('http://a.b:4211, 10.0.0.2:4211；not-a-url 192.168.1.1:4211');
      expect(got, contains('http://a.b:4211'));
      expect(got, contains('http://10.0.0.2:4211'));
      expect(got, contains('http://192.168.1.1:4211'));
    });

    test('candidates：注入优先 > 手填 > 预设，且去重', () {
      final c = RoomEndpoint.candidates(
        injected: 'http://192.168.1.7:4211',
        user: '192.168.1.7:4211, http://10.0.0.2:4211',
        presets: <String>['http://10.0.0.2:4211', 'http://1.2.3.4:4211'],
      );
      expect(c.first, 'http://192.168.1.7:4211',
          reason: '注入的必须排第一 —— 它代表「这台手机现在就是服务器」，'
              '用户设置里的旧地址不该盖过它');
      expect(c.length, 3, reason: '去重后剩 3 个');
      expect(c.last, 'http://1.2.3.4:4211');
    });

    test('wsUrlFor：http→ws / https→wss，路径 /ws', () {
      expect(RoomEndpoint.wsUrlFor('http://192.168.1.7:4211'), 'ws://192.168.1.7:4211/ws');
      expect(RoomEndpoint.wsUrlFor('https://room.example.com'), 'wss://room.example.com/ws');
      expect(RoomEndpoint.wsUrlFor(''), '');
    });

    test('isLanOnly：私网地址只能同网段访问', () {
      expect(RoomEndpoint.isLanOnly('http://192.168.1.7:4211'), isTrue);
      expect(RoomEndpoint.isLanOnly('http://8.8.8.8:4211'), isFalse);
    });
  });

  group('房间摘要', () {
    test('编解码往返，wifi 缺省为 true（旧客户端兼容）', () {
      const a = RoomAnnounce(
        code: 'ABC123',
        base: 'http://192.168.1.7:4211',
        name: '洋馆之夜',
        kpName: '老王',
        players: 3,
        spectators: 1,
        wifi: false,
      );
      final back = RoomAnnounce.parse(a.toJson());
      expect(back, isNotNull);
      expect(back!.code, 'ABC123');
      expect(back.players, 3);
      expect(back.wifi, isFalse, reason: 'wifi:false 必须透出去，否则界面不会提示「只有自己能进」');

      // 缺 wifi 字段（旧版本）按 true 处理，不要因为缺字段就报警
      final legacy = RoomAnnounce.parse(<String, Object?>{
        'code': 'X',
        'base': 'http://1.2.3.4:4211',
      });
      expect(legacy!.wifi, isTrue);
    });

    test('缺少 code / base 的摘要直接丢弃', () {
      expect(RoomAnnounce.parse(<String, Object?>{'code': 'A'}), isNull);
      expect(RoomAnnounce.parse(<String, Object?>{'base': 'http://x.y'}), isNull);
      expect(RoomAnnounce.parse('garbage'), isNull);
      expect(RoomAnnounce.parse(null), isNull);
    });
  });

  group('UDP 广播 / 发现（真 socket）', () {
    test('广播一次 → 扫描能收到，字段完整', () async {
      // 用一个不常用的高位端口，避开真实 4210
      const int port = 24310;

      final LanBroadcaster b = LanBroadcaster(
        targetPort: port,
        targetAddress: '127.0.0.1', // 测试用单播，避免广播被防火墙拦
      );
      addTearDown(b.stop);

      final bool started = await b.start(
        () => const RoomAnnounce(
          code: 'T-01',
          base: 'http://127.0.0.1:4211',
          name: '测试房',
          kpName: 'KP',
          players: 2,
          spectators: 0,
          status: 'RECRUITING',
        ),
        every: const Duration(milliseconds: 150),
      );
      expect(started, isTrue, reason: '广播器应能启动');

      final List<RoomAnnounce> got = await LanDiscoverer.scan(
        listenPort: port,
        timeout: const Duration(milliseconds: 900),
      );

      expect(got, isNotEmpty, reason: '应该收到至少一条摘要');
      final RoomAnnounce first = got.firstWhere((RoomAnnounce a) => a.code == 'T-01');
      expect(first.players, 2);
      expect(first.name, '测试房');
      expect(first.updatedAt, isNotNull, reason: '本机应打上收到时刻（用于判过期）');

      await b.stop();
    });

    test('没有广播时，扫描到点返回空列表而不是挂住', () async {
      const int port = 24311;
      final Stopwatch sw = Stopwatch()..start();
      final List<RoomAnnounce> got = await LanDiscoverer.scan(
        listenPort: port,
        timeout: const Duration(milliseconds: 300),
      );
      sw.stop();
      expect(got, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: '必须在超时后返回 —— 界面不能一直转圈');
    });

    test('同 code 的重复广播只保留一条（人数以最新为准）', () async {
      const int port = 24312;
      int players = 1;
      final LanBroadcaster b = LanBroadcaster(
        targetPort: port,
        targetAddress: '127.0.0.1',
      );
      addTearDown(b.stop);
      await b.start(
        () => RoomAnnounce(
          code: 'DUP',
          base: 'http://127.0.0.1:4211',
          players: players,
        ),
        every: const Duration(milliseconds: 100),
      );
      players = 3; // 第 2 次心跳起人数变 3

      final List<RoomAnnounce> got = await LanDiscoverer.scan(
        listenPort: port,
        timeout: const Duration(milliseconds: 700),
      );
      final List<RoomAnnounce> same = got.where((RoomAnnounce a) => a.code == 'DUP').toList();
      expect(same, hasLength(1), reason: '同 code 不该重复出现，否则界面会列出两行');
      expect(same.single.players, 3, reason: '应以最后一次广播为准');

      await b.stop();
    });
  });
}
