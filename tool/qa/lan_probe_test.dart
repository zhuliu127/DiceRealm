// ============================================================
// tool/qa/lan_probe_test.dart — 对着**运行中的真实服务端**做探针
//
// 与 test/p6_* 的区别：
//   · 那些是「自己起服务自己连」的闭环测试；
//   · 这个是「连别人的服务」，用来验真实设备（模拟器/真机）上跑起来的
//     服务端能否接受外部连接并完成完整链路。
//
// 用法（服务端已在某处跑着，并已把端口转到宿主机）：
//   LAN_BASE=http://127.0.0.1:14211 LAN_CODE=MRUJZT \
//     flutter test tool/qa/lan_probe_test.dart
//
// 它会走：hello → joined（含座位分配）→ 收 sync → 发 chat → 确认服务端 seq 前进。
// ============================================================

import 'dart:io' show Platform;

import 'package:dice_realm/domain/js_compat.dart' show asList;
import 'package:dice_realm/net/lan_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final String base = Platform.environment['LAN_BASE'] ?? '';
  final String code = Platform.environment['LAN_CODE'] ?? '';

  test('对真实服务端：握手 → 分配座位 → 收全量 → 发消息', () async {
    expect(base, isNotEmpty, reason: '请设置 LAN_BASE，如 http://127.0.0.1:14211');
    expect(code, isNotEmpty, reason: '请设置 LAN_CODE（房号）');

    // seat 传空 = 让服务端分配（这是局域网加入的常态）
    final LanClient c = LanClient(base: base, seat: '', code: code);
    addTearDown(() async => c.dispose());

    final r = await c.connect();
    // ignore: avoid_print
    print('[probe] joined: ok=${r.ok} seat=${r.seat} role=${r.role} '
        'lastSeq=${r.lastSeq} err=${r.error}');
    expect(r.ok, isTrue, reason: '握手失败：${r.error}');
    expect(r.seat, isNotNull);
    expect(r.seat, isNotEmpty, reason: '服务端应分配一个座位');

    // 等首份 sync
    for (var i = 0; i < 60 && c.client.lastSeq == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final members = asList(c.client.state['members']).length;
    // ignore: avoid_print
    print('[probe] sync: lastSeq=${c.client.lastSeq} members=$members '
        'seat=${c.seat} link=${c.link.name}');
    expect(c.client.lastSeq, greaterThan(0), reason: '应收到全量同步');

    // 发一条聊天（验证「客户端 → 服务端」方向）
    final int before = c.client.lastSeq;
    c.sendIntent('chat', <String, Object?>{'text': '来自宿主探针的消息'});

    for (var i = 0; i < 60 && c.client.lastSeq <= before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // ignore: avoid_print
    print('[probe] after chat: lastSeq=${c.client.lastSeq}（发前 $before）');
    expect(c.client.lastSeq, greaterThan(before),
        reason: '客户端发的 chat 应被服务端应用并广播回来');

    // ignore: avoid_print
    print('[probe] PASS — 真实服务端全链路正常');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
