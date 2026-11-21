// ============================================================
// test/p12_join_routing_test.dart — 加入房间别再被「公网配置」带偏
//
// 用户 2026-11-11 真机报：
//   点过一次「开公网房间」后，再用「搜索附近的房间」加入，提示
//   「公网加入失败：加入失败 HTTP404」，杀进程重进也一样，怀疑
//   「配置了公网服务器，所以加入房间都走公网加入」。
//
// 真因（比猜测更直接）：局域网 UDP 广播里的 base 是
//   `http://192.168.x.x:4211`（lan_server.dart#_baseFor），
//   而 isCloudBase() 原来只看 `http(s)://` 前缀 → 把局域网地址误判成
//   公网中继 → 朝局域网 IP 发云端 API → 404。跟配置过公网服务器无关，
//   只是「附近的房间」自动填的地址一定带 http:// 前缀。
//
// 双保险：
//   ① isCloudBase 按主机判定，私有/本机网段一律算局域网；
//   ② shouldJoinCloud(fromDiscovery: true) 时无条件走局域网 ——
//      UDP 广播只能发现同网段，与地址长什么样无关。
// ============================================================

import 'package:dice_realm/net/cloud_room.dart' show isCloudBase;
import 'package:dice_realm/ui/room/room_entry_page.dart' show shouldJoinCloud;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('局域网发现到的房间必定走局域网', () {
    const List<String> lanBases = <String>[
      'http://192.168.1.7:4211',
      'http://10.0.2.16:4211',
      'http://10.0.2.2:4211',
      'http://172.20.5.9:4211',
      'http://127.0.0.1:4211',
      'http://localhost:4211',
      '192.168.1.7:4211',
    ];

    for (final String base in lanBases) {
      test('$base：发现来的 → 不走公网', () {
        expect(shouldJoinCloud(base, fromDiscovery: true), isFalse);
      });
      test('$base：手输的 → 也不走公网', () {
        expect(shouldJoinCloud(base, fromDiscovery: false), isFalse);
        expect(isCloudBase(base), isFalse);
      });
    }
  });

  group('公网中继仍可正常加入', () {
    test('手输 https 中继 → 走公网', () {
      const String base = 'https://relay.example.com/room';
      expect(isCloudBase(base), isTrue);
      expect(shouldJoinCloud(base, fromDiscovery: false), isTrue);
    });

    test('公网域名 http → 走公网', () {
      const String base = 'http://relay.example.com/room';
      expect(isCloudBase(base), isTrue);
      expect(shouldJoinCloud(base, fromDiscovery: false), isTrue);
    });

    test('即使是公网形状的地址，只要来自 UDP 发现也不走公网', () {
      // 广播只能来自同网段；这条是「来源」这道保险，与地址无关。
      expect(
        shouldJoinCloud('https://relay.example.com/room',
            fromDiscovery: true),
        isFalse,
      );
    });
  });

  test('空地址 / 无 scheme 一律不算公网', () {
    expect(isCloudBase(''), isFalse);
    expect(isCloudBase('   '), isFalse);
    expect(isCloudBase('10.0.2.2:4211'), isFalse);
    expect(shouldJoinCloud('', fromDiscovery: false), isFalse);
  });
}
