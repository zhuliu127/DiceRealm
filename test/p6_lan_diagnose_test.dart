// ============================================================
// p6_lan_diagnose_test.dart — 局域网自检（分步诊断）
//
// 为什么值得单独测：自检的价值全在**判读逻辑**上 ——
// 「服务活着但地址不通」和「服务压根没起」在用户眼里都是「连不上」，
// 但处置完全不同（查 AP 隔离 vs 去建房）。判错一次就把用户带偏。
//
// 用真 HttpServer 而不是 mock：诊断本身就是在打 HTTP，
// mock 掉就把要验的东西验没了。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io'
    show ContentType, HttpServer, HttpStatus, InternetAddress;

import 'package:dice_realm/net/lan_diagnose.dart';
import 'package:flutter_test/flutter_test.dart';

/// 起一个只会答 /health 的最小服务。
Future<HttpServer> _startFakeHealth(String code) async {
  final s = await HttpServer.bind(InternetAddress.anyIPv4, 0);
  s.listen((req) async {
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode(<String, Object?>{
        'ok': true,
        'code': code,
        'status': 'RECRUITING',
      }),
    );
    await req.response.close();
  });
  return s;
}

void main() {
  group('网段打分（选网卡的唯一标准）', () {
    test('★ 链路本地与 VPN 基准段一律 0 分 —— 选中它们必然「启动成功但连不上」', () {
      expect(ipScore('169.254.3.4'), 0, reason: '链路本地，跨设备不通');
      expect(ipScore('198.18.0.1'), 0,
          reason: 'RFC 2544 基准段，Clash/VPN 的 TUN 网卡常拿它 —— 这就是我踩过的那个坑');
      expect(ipScore('198.19.255.1'), 0, reason: '同一段的高位');
    });

    test('典型家用与内网高分，且常见家用最高', () {
      expect(ipScore('192.168.1.7'), 100);
      expect(ipScore('10.0.0.5'), 90);
      expect(ipScore('172.16.3.9'), 80);
      expect(ipScore('172.31.255.254'), 80, reason: '172.16–31 是私有段，31 是上界');
      expect(ipScore('172.32.0.1'), 10, reason: '172.32 已超出私有段');
      expect(ipScore('8.8.8.8'), 10, reason: '公网地址能用但不优先');
    });
  });

  group('分步诊断 · 判读', () {
    test('★ 本机没起服务 → lanDown（不是「连不上」，是「还没建房」）', () async {
      final r = await diagnoseLan(lanBase: '');
      expect(r.verdict, LanVerdict.lanDown);
      expect(r.ok, isFalse);
      expect(r.steps.first.name, '局域网服务');
      expect(r.steps.first.ok, isFalse);
      // 处置必须能指导动作：让用户去建房
      expect(r.verdictText.contains('创建'), isTrue);
    });

    test('★ 服务在本机活着 → lanOk，且步骤里带房号', () async {
      final s = await _startFakeHealth('AB12CD');
      addTearDown(() => s.close(force: true));

      final r = await diagnoseLan(
        lanBase: 'http://127.0.0.1:${s.port}',
        timeout: const Duration(seconds: 2),
      );
      expect(r.verdict, LanVerdict.lanOk);
      expect(r.ok, isTrue);
      // 三步都在：服务 / 网卡 / 局域网地址 / 回环
      expect(r.steps.length, greaterThanOrEqualTo(4));
      // 探测成功那一句要带房号，出问题时好对账
      final lanStep = r.steps.firstWhere((e) => e.name.startsWith('局域网地址'));
      expect(lanStep.ok, isTrue);
      expect(lanStep.text.contains('AB12CD'), isTrue,
          reason: '成功时应回显房号，便于确认打的是自己对的那间房');
      expect(lanStep.ms, greaterThanOrEqualTo(0));
    });

    test('★ 回环通、局域网地址不通 → lanBlocked（最有价值的那条判读）', () async {
      // 服务真在 0.0.0.0 上监听（所以 127.0.0.1 一定通），
      // 但 base 的 host 用一个不可路由的探测网段（RFC 5737 TEST-NET-1）。
      // 这正是「服务活着但这个 IP 走不通」的真实形态。
      final s = await _startFakeHealth('ZZ99YY');
      addTearDown(() => s.close(force: true));

      final r = await diagnoseLan(
        lanBase: 'http://192.0.2.1:${s.port}',
        timeout: const Duration(milliseconds: 600),
      );
      expect(r.verdict, LanVerdict.lanBlocked,
          reason: '回环通说明服务活着；局域网地址不通只能是网络层拦截');
      // 回环那一步必须是通的（这正是不误判成「服务崩了」的依据）
      final loopStep = r.steps.firstWhere((e) => e.name.startsWith('回环地址'));
      expect(loopStep.ok, isTrue);
      // 处置必须提到「AP 隔离 / 访客网络」这类真实原因
      expect(
        r.advice.any((a) => a.contains('AP 隔离') || a.contains('访客')),
        isTrue,
      );
      expect(r.advice.any((a) => a.contains('VPN')), isTrue,
          reason: '选错 VPN 网卡是常见原因之一，建议里必须提到');
    });

    test('★ 判读表：四种组合各归各位（纯逻辑，不依赖真实网络行为）', () {
      // 判读是自检的核心价值，但它只需要三个布尔值。
      // 用纯函数测才能钉死 —— 靠真 socket 造「拒绝 vs 超时」在各系统上结果不同。
      expect(judge(lanOk: true, loopOk: true, anyTimeout: false),
          LanVerdict.lanOk,
          reason: '局域网地址通就是好，不必看回环');
      expect(judge(lanOk: true, loopOk: false, anyTimeout: true),
          LanVerdict.lanOk,
          reason: '局域网通了，回环超时不影响结论');
      expect(judge(lanOk: false, loopOk: true, anyTimeout: false),
          LanVerdict.lanBlocked);
      expect(judge(lanOk: false, loopOk: true, anyTimeout: true),
          LanVerdict.lanBlocked,
          reason: '★ 服务活着这条信息优先于「某一探超时」——'
              '否则会把「AP 隔离」误报成「防火墙丢包」，处置方向就错了');
      expect(judge(lanOk: false, loopOk: false, anyTimeout: true),
          LanVerdict.lanTimeout);
      expect(judge(lanOk: false, loopOk: false, anyTimeout: false),
          LanVerdict.lanDead);
    });

    test('★ 两探都失败且服务已停 → 不是 lanOk（走真实链路兜底）', () async {
      // 先绑一个端口拿号，立刻关掉 —— 之后两次探测都不会成功。
      // 具体判成 lanDead 还是 lanTimeout 取决于系统行为（拒绝 vs 静默丢弃），
      // 两者处置相近（都指向「服务不在」），所以这里只钉「不通」。
      final probe = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = probe.port;
      await probe.close(force: true);

      final r = await diagnoseLan(
        lanBase: 'http://127.0.0.1:$port',
        timeout: const Duration(milliseconds: 600),
      );
      expect(r.ok, isFalse);
      expect(
        r.verdict,
        anyOf(LanVerdict.lanDead, LanVerdict.lanTimeout),
        reason: '服务不在时不该被判成「正常」或「服务活着但地址不通」',
      );
      expect(r.verdict, isNot(LanVerdict.lanBlocked),
          reason: '回环也不通就不能说「服务活着」');
    });

    test('自检从不抛异常：地址畸形也只给结论', () async {
      final r = await diagnoseLan(
        lanBase: '不是地址',
        timeout: const Duration(milliseconds: 300),
      );
      // 不抛就算过 —— 具体判成哪个 verdict 不重要，弹层不能崩。
      expect(r.steps, isNotEmpty);
      expect(r.ok, isFalse);
    });
  });

  group('网卡清单', () {
    test('★ 能列出网卡并标出选中的那块（旧版在浏览器里做不到）', () async {
      final ifaces = await listIfaces(chosenIp: '');
      // 环境可能没有非回环网卡（容器里），所以不硬断言数量，
      // 只验「有的话字段都对、按分降序」。
      for (final i in ifaces) {
        expect(i.name, isNotEmpty);
        expect(i.score, greaterThanOrEqualTo(0));
        expect(i.chosen, isFalse, reason: 'chosenIp 为空时不该有 chosen');
      }
      for (var k = 1; k < ifaces.length; k++) {
        expect(ifaces[k - 1].score, greaterThanOrEqualTo(ifaces[k].score),
            reason: '必须按分降序，否则「该用哪块」看不出来');
      }
    });

    test('给定 chosenIp 时只标记那一块', () async {
      final ifaces = await listIfaces(chosenIp: '8.8.8.8');
      expect(ifaces.where((i) => i.chosen), isEmpty,
          reason: '8.8.8.8 一般不在本机网卡上，不该命中');
    });
  });
}
