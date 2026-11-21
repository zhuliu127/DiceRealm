// ============================================================
// p6_multicast_lock_test.dart — Android 多播锁
//
// 这个模块的风险不在「能不能拿到锁」，而在**引用计数泄漏**：
// 广播器与扫描器各持一层，任一方多持或少放，症状分别是
//   · 少放 → 系统持续不允许省电，白耗电（用户看不到，但真实伤害）
//   · 多放 → 另一方还以为是持着的，结果收不到广播（更难查）
//
// 平台通道用 `setMockMethodCallHandler` 替身，能精确断言
// 「平台被调用了几次」——这是纯 no-op 测试做不到的。
// ============================================================

import 'package:dice_realm/net/lan_discovery.dart'
    show LanBroadcaster, LanDiscoverer, RoomAnnounce;
import 'package:dice_realm/net/multicast_lock.dart' show MulticastLock;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _ch = MethodChannel('dice_realm/multicast');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 记录平台被调用的方法名。
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    MulticastLock.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, (MethodCall call) async {
      calls.add(call.method);
      return call.method == 'acquire' ? true : null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, null);
    MulticastLock.debugReset();
  });

  group('非 Android 环境（flutter test 默认）', () {
    test('★ 全部 no-op，一次都不碰平台通道', () async {
      // 测试跑在桌面 VM 上，Platform.isAndroid 为 false。
      expect(await MulticastLock.acquire(), isFalse);
      await MulticastLock.release();
      await MulticastLock.release(); // 多放也不能崩
      expect(calls, isEmpty, reason: '非 Android 不该向平台发任何调用');
      expect(MulticastLock.refCount, 0);
    });
  });

  group('引用计数（Android 路径）', () {
    setUp(() => MulticastLock.debugForceSupported = true);

    test('★ 两层持锁时平台只被 acquire 一次 —— 第二层不重复拿', () async {
      expect(await MulticastLock.acquire(), isTrue);
      expect(await MulticastLock.acquire(), isTrue);
      expect(calls, <String>['acquire'],
          reason: '引用计数应该在 Dart 层挡住重复的 acquire');
      expect(MulticastLock.refCount, 2);
    });

    test('★ 放一层不真释放 —— 还剩别的持有者（广播器/扫描器会同时持）', () async {
      await MulticastLock.acquire();
      await MulticastLock.acquire();
      await MulticastLock.release();

      expect(calls, <String>['acquire'],
          reason: '还有一层持有，不该调平台的 release');
      expect(MulticastLock.refCount, 1);
      expect(MulticastLock.held, isTrue);
    });

    test('★ 最后一层才真释放，且只释放一次', () async {
      await MulticastLock.acquire();
      await MulticastLock.acquire();
      await MulticastLock.release();
      await MulticastLock.release();

      expect(calls, <String>['acquire', 'release']);
      expect(MulticastLock.refCount, 0);
      expect(MulticastLock.held, isFalse);
    });

    test('★ 多放不会把计数放成负数（否则下一次 acquire 会被误判为「已持有」）',
        () async {
      await MulticastLock.acquire();
      await MulticastLock.release();
      await MulticastLock.release(); // 多余的
      await MulticastLock.release();
      expect(MulticastLock.refCount, 0, reason: '计数不能变负');
      expect(calls, <String>['acquire', 'release'],
          reason: '多余 release 不该反复调平台');

      // 再来一轮必须能正常重新拿到 —— 这是计数被放成负数后最典型的坏症状。
      expect(await MulticastLock.acquire(), isTrue);
      expect(calls, <String>['acquire', 'release', 'acquire']);
    });

    test('平台拿不到锁（返回 false）时不崩，也不留下假状态', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_ch, (MethodCall call) async {
        calls.add(call.method);
        return false; // 模拟权限缺失
      });

      expect(await MulticastLock.acquire(), isFalse);
      expect(MulticastLock.held, isFalse);
      // 放的时候不该调平台（本来就没拿到）
      await MulticastLock.release();
      expect(calls, <String>['acquire']);
    });
  });

  group('与发现层的配对（这才是泄漏的真正来源）', () {
    setUp(() => MulticastLock.debugForceSupported = true);

    test('★ 广播器 start/stop 严格配对 —— 不停广播器就等于一直持锁', () async {
      final b = LanBroadcaster(targetPort: 24390, targetAddress: '127.0.0.1');
      addTearDown(b.stop);

      final ok = await b.start(
        () => const RoomAnnounce(code: 'AB12CD', base: 'http://127.0.0.1:1'),
        every: const Duration(milliseconds: 100),
      );
      expect(ok, isTrue);
      expect(MulticastLock.refCount, 1);

      await b.stop();
      expect(MulticastLock.refCount, 0, reason: '★ stop 必须把广播器那一层放掉');
    });

    test('★ 重复 start 不重复持锁（幂等）', () async {
      final b = LanBroadcaster(targetPort: 24391, targetAddress: '127.0.0.1');
      addTearDown(b.stop);

      RoomAnnounce snap() =>
          const RoomAnnounce(code: 'AB12CD', base: 'http://127.0.0.1:1');
      await b.start(snap, every: const Duration(milliseconds: 100));
      await b.start(snap, every: const Duration(milliseconds: 100));
      expect(MulticastLock.refCount, 1, reason: '已经在跑就不该再持一层');

      await b.stop();
      expect(MulticastLock.refCount, 0);
    });

    test('★ 扫描结束后一定释放 —— 哪怕一条都没收到', () async {
      final list = await LanDiscoverer.scan(
        listenPort: 24392,
        timeout: const Duration(milliseconds: 200),
      );
      expect(list, isEmpty);
      expect(MulticastLock.refCount, 0,
          reason: '★ scan 用 try/finally 配平，超时退出也要放锁');
    });

    test('★ 扫描与广播同时进行：两层叠加，一方结束不影响另一方', () async {
      // 这正是真实场景：KP 一边广播自己的房，一边开着「附近的房间」扫描。
      final b = LanBroadcaster(targetPort: 24393, targetAddress: '127.0.0.1');
      addTearDown(b.stop);
      await b.start(
        () => const RoomAnnounce(code: 'AB12CD', base: 'http://127.0.0.1:1'),
        every: const Duration(milliseconds: 100),
      );
      expect(MulticastLock.refCount, 1);

      final fut = LanDiscoverer.scan(
        listenPort: 24394,
        timeout: const Duration(milliseconds: 200),
      );
      // 扫描期间应当叠到两层
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(MulticastLock.refCount, 2,
          reason: '扫描器自己持一层，不该复用广播器那一层');

      await fut;
      expect(MulticastLock.refCount, 1,
          reason: '★ 扫描结束只放自己那层，广播器仍然持有');
      expect(MulticastLock.held, isTrue);

      await b.stop();
      expect(MulticastLock.refCount, 0);
    });
  });
}
