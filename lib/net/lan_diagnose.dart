// ============================================================
// net/lan_diagnose.dart — 局域网分步自检
//
// 目的不是「报个错」，而是把「连不上」拆成**几个可行动的原因**。
// 旧版 room-net.js:418 `lanDiagnose` 的核心价值就在这里：6 种 verdict
// 各自对应一句「你该做什么」，而不是统一一句「连接失败」。
//
// Dart 版比旧版多一件事：**能列出所有网卡**（浏览器里拿不到）。
// 这直接解决了「选错网卡」这个最难自查的问题 —— 我本人就被
// Clash 的 TUN 网卡（198.18.0.1）坑过一次：服务"启动成功"、
// 界面显示"已连接"，但广播出去的地址同伴根本连不上。
//
// 纯逻辑：不依赖 Flutter，只依赖 dart:io 与 http_io。可单测。
// ============================================================

import 'dart:io' show NetworkInterface, InternetAddressType;

import 'http_io.dart' show HttpResult, httpRequest, decodeJsonOrNull;

/// 自检结论。每一种都对应一句可执行的处置，不是笼统的「失败」。
enum LanVerdict {
  /// 局域网地址可达 —— 同伴能连。
  lanOk,

  /// 本机还没起局域网服务（没建房，或建房时服务起失败了）。
  lanDown,

  /// 回环通、局域网地址不通。
  ///
  /// 服务是活的，但**这个 IP 走不通**。典型原因：
  /// AP 隔离 / 访客网络 / 系统防火墙拦了 4211 / 选中了 VPN 虚拟网卡。
  lanBlocked,

  /// 两次探测都超时。多半是防火墙丢包（不是拒绝，是静默丢弃）。
  lanTimeout,

  /// 两次探测都失败且不是超时。服务可能崩了，或端口被别的程序抢了。
  lanDead,
}

/// 一步诊断的结果。
class LanDiagStep {
  const LanDiagStep({
    required this.name,
    required this.ok,
    required this.text,
    this.ms = 0,
  });

  final String name;
  final bool ok;

  /// 给人看的一句话。失败时这句话要能指导下一步动作。
  final String text;

  /// 耗时（毫秒）。服务端没答上来时为 0。
  final int ms;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'ok': ok,
    'text': text,
    'ms': ms,
  };
}

/// 一块网卡（诊断「选错网卡」用）。
class LanIface {
  const LanIface({
    required this.name,
    required this.address,
    required this.score,
    required this.chosen,
  });

  final String name;
  final String address;

  /// 打分：0 = 肯定不能用（链路本地 / VPN 基准段），100 = 典型家用 WiFi。
  final int score;

  /// 是否是服务实际选中的那块。
  final bool chosen;

  bool get usable => score > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'address': address,
    'score': score,
    'chosen': chosen,
  };
}

/// 自检总结果。
class LanDiagResult {
  const LanDiagResult({
    required this.verdict,
    required this.steps,
    this.ifaces = const <LanIface>[],
    this.base = '',
    this.loopBase = '',
  });

  final LanVerdict verdict;
  final List<LanDiagStep> steps;
  final List<LanIface> ifaces;

  /// 被诊断的局域网地址（空串 = 没起服务）。
  final String base;

  /// 回环对照地址。
  final String loopBase;

  bool get ok => verdict == LanVerdict.lanOk;

  /// 一句话结论（弹层标题下方那句）。
  String get verdictText {
    switch (verdict) {
      case LanVerdict.lanOk:
        return '局域网正常：同 WiFi 的同伴可以加入。';
      case LanVerdict.lanDown:
        return '本机还没开局域网服务。先建房（「创建并进入」），再回来自检。';
      case LanVerdict.lanBlocked:
        return '服务是活的，但这个地址走不通。常见原因：WiFi 开了「AP 隔离」/'
            '当前是访客网络 / 系统防火墙拦了端口 / 选中了 VPN 虚拟网卡。';
      case LanVerdict.lanTimeout:
        return '两次探测都超时。多半是防火墙静默丢包（不是拒绝）。'
            '试着临时关掉防火墙或换一个 WiFi。';
      case LanVerdict.lanDead:
        return '服务没应答。可能它已经崩了，或端口被别的程序占用。'
            '退出房间重新创建一次。';
    }
  }

  /// 建议动作（给用户下一步）。
  List<String> get advice {
    switch (verdict) {
      case LanVerdict.lanOk:
        return const <String>[
          '把「服务地址」连同房间号一起发给同伴',
          '同伴搜不到时，让他手输这个地址',
        ];
      case LanVerdict.lanDown:
        return const <String>['返回大厅前先建房', '如果建房时提示端口被占，重启手机再试'];
      case LanVerdict.lanBlocked:
        return const <String>[
          '检查 WiFi 是不是「访客网络」（访客网络通常隔离设备）',
          '关掉路由器上的「AP 隔离」选项',
          '看下面「网卡」一栏：如果选中的是 198.18/198.19 或 169.254 网段，'
              '那是 VPN 虚拟网卡，关掉 VPN 再重建房',
        ];
      case LanVerdict.lanTimeout:
        return const <String>[
          '临时关掉手机上的防火墙/安全软件',
          '换一个 WiFi 试（有些企业 WiFi 完全禁止设备互访）',
        ];
      case LanVerdict.lanDead:
        return const <String>['退出房间并重新创建', '仍不行就重启 App'];
    }
  }
}

/// 跑一次自检。
///
/// [lanBase] 传 `RoomSession.lanBase`：非空表示本机已起局域网服务。
/// [timeout] 单次探测超时；诊断场景宁可短一点（2 秒），用户等不起。
Future<LanDiagResult> diagnoseLan({
  required String lanBase,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final steps = <LanDiagStep>[];
  final base = lanBase.trim();

  // ---- 第 1 步：本机有没有起服务
  if (base.isEmpty) {
    steps.add(
      const LanDiagStep(
        name: '局域网服务',
        ok: false,
        text: '未启动（本机没有在监听端口）',
      ),
    );
    final ifaces = await listIfaces(chosenIp: '');
    return LanDiagResult(
      verdict: LanVerdict.lanDown,
      steps: steps,
      ifaces: ifaces,
    );
  }
  steps.add(LanDiagStep(name: '局域网服务', ok: true, text: base));

  // ---- 第 2 步：网卡清单（选错网卡是最难自查的问题）
  final chosenIp = _ipOf(base);
  final ifaces = await listIfaces(chosenIp: chosenIp);
  final chosen = ifaces.where((i) => i.chosen).toList();
  if (chosen.isNotEmpty) {
    final c = chosen.first;
    steps.add(
      LanDiagStep(
        name: '网卡选择',
        ok: c.usable,
        text: c.usable
            ? '${c.name} · ${c.address}'
            : '${c.name} · ${c.address} —— 这块网卡不像真局域网'
                  '（链路本地或 VPN 虚拟网卡），同伴很可能连不上',
      ),
    );
  } else {
    steps.add(
      const LanDiagStep(
        name: '网卡选择',
        ok: false,
        text: '没找到对应的网卡（地址可能是手动填的）',
      ),
    );
  }

  // ---- 第 3 步 & 第 4 步：串行两探
  //
  // 串行而非并发：先打局域网地址（同伴真正要用的那个），再打回环做对照。
  // 「局域网不通但回环通」这个组合本身就是结论 —— 服务活着，是这个 IP 走不通。
  final r1 = await _ping('$base/health', timeout);
  steps.add(
    LanDiagStep(
      name: '局域网地址 $base',
      ok: r1.ok,
      text: r1.ok ? '正常 · ${r1.ms}ms · ${r1.detail}' : '${r1.message}（${r1.ms}ms）',
      ms: r1.ms,
    ),
  );

  final loopBase = _swapHost(base, '127.0.0.1');
  final r2 = await _ping('$loopBase/health', timeout);
  steps.add(
    LanDiagStep(
      name: '回环地址 $loopBase',
      ok: r2.ok,
      text: r2.ok ? '正常 · ${r2.ms}ms · ${r2.detail}' : '${r2.message}（${r2.ms}ms）',
      ms: r2.ms,
    ),
  );

  // ---- 判读
  final verdict = judge(
    lanOk: r1.ok,
    loopOk: r2.ok,
    anyTimeout: r1.timedOut || r2.timedOut,
  );

  return LanDiagResult(
    verdict: verdict,
    steps: steps,
    ifaces: ifaces,
    base: base,
    loopBase: loopBase,
  );
}

/// 判读：把「两次探测的结果」翻译成结论。
///
/// 抽成纯函数是刻意的 —— 这是整个自检的**核心价值**，
/// 而它只需要三个布尔值就能决定。留在 I/O 流程里就只能靠真网络去测，
/// 那种测试在「拒绝」与「超时」上会因操作系统而异，钉不死。
///
/// 判读顺序有讲究：
/// 1. 局域网地址通 → 好（不必看回环）
/// 2. 回环通但局域网不通 → `lanBlocked`。**这条必须先于超时判断**：
///    服务活着是更确凿的信息，比「某一探超时了」更能定位问题。
/// 3. 任一探超时 → `lanTimeout`（防火墙静默丢包的特征）
/// 4. 其余 → `lanDead`（服务没应答）
LanVerdict judge({
  required bool lanOk,
  required bool loopOk,
  required bool anyTimeout,
}) {
  if (lanOk) return LanVerdict.lanOk;
  if (loopOk) return LanVerdict.lanBlocked;
  if (anyTimeout) return LanVerdict.lanTimeout;
  return LanVerdict.lanDead;
}

/// 列出所有 IPv4 网卡并打分，标出哪块是服务选中的。
///
/// 独立成公开函数：自检弹层要显示它，测试也要能单独钉它。
Future<List<LanIface>> listIfaces({required String chosenIp}) async {
  final out = <LanIface>[];
  try {
    final list = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: true,
    );
    for (final i in list) {
      for (final a in i.addresses) {
        out.add(
          LanIface(
            name: i.name,
            address: a.address,
            score: ipScore(a.address),
            chosen: chosenIp.isNotEmpty && a.address == chosenIp,
          ),
        );
      }
    }
  } catch (_) {
    // 拿不到网卡列表不是致命错误 —— 自检继续往下走（两探仍然有效）。
  }
  // 分高的排前面，让「该用哪块」一眼可见。
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// 地址「像不像真局域网」的打分。与服务端选网卡用同一套标准。
///
/// 0 分 = 肯定不能用。198.18/198.19 是 RFC 2544 基准测试段，
/// Clash / 部分 VPN 拿它当 TUN 网卡 —— 选中它就会「启动成功但同伴连不上」。
int ipScore(String ip) {
  if (ip.startsWith('169.254.')) return 0; // 链路本地
  if (ip.startsWith('198.18.') || ip.startsWith('198.19.')) return 0; // VPN TUN
  if (ip.startsWith('192.168.')) return 100; // 典型家用 WiFi
  if (ip.startsWith('10.')) return 90; // 常见内网
  if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) return 80;
  return 10; // 其它公网/少见网段：能用但不优先
}

/// 从 `http://ip:port` 里取 IP（取不到返回空串）。
String _ipOf(String base) {
  final m = RegExp(r'^[a-zA-Z]+://([^:/]+)').firstMatch(base);
  return m?.group(1) ?? '';
}

/// 把 URL 的 host 换掉（保留 scheme 与端口）。
///
/// ★ 必须用 `replaceFirstMapped`：Dart 的 `replaceFirst` **不认** `$1`
///   捕获组语法（那是 JS 的），会把 `$1` 当字面文本拼进去，
///   拼出 `http://$1127.0.0.1:4211` 这种废 URL —— 于是回环探测永远失败，
///   「局域网不通但回环通」这条最有价值的判读就永远走不到。
String _swapHost(String base, String host) {
  return base.replaceFirstMapped(
    RegExp(r'^([a-zA-Z]+://)[^:/]+'),
    (Match m) => '${m.group(1)}$host',
  );
}

class _Ping {
  const _Ping({
    required this.ok,
    required this.ms,
    required this.timedOut,
    required this.detail,
    required this.message,
  });

  final bool ok;
  final int ms;
  final bool timedOut;

  /// 成功时的附加信息（服务名 / 房号）。
  final String detail;

  /// 失败时的一句话。
  final String message;
}

Future<_Ping> _ping(String url, Duration timeout) async {
  final sw = Stopwatch()..start();
  final HttpResult r = await httpRequest(
    url,
    'GET',
    const <String, String>{'Accept': 'application/json'},
    '',
    timeout: timeout,
  );
  sw.stop();
  final ms = sw.elapsedMilliseconds;
  final timedOut = r.error?.contains('Timeout') ?? false;

  if (!r.ok) {
    return _Ping(
      ok: false,
      ms: ms,
      timedOut: timedOut,
      detail: '',
      message: r.error ?? 'HTTP ${r.status}',
    );
  }

  // 能答 200 就说明服务活着；再顺手读一眼房号，出问题时好对账。
  final j = decodeJsonOrNull(r.body);
  String detail = '骰境房间服务';
  if (j is Map) {
    final code = '${j['code'] ?? ''}';
    final status = '${j['status'] ?? ''}';
    if (code.isNotEmpty) detail = '房号 $code${status.isEmpty ? '' : ' · $status'}';
  }
  return _Ping(ok: true, ms: ms, timedOut: false, detail: detail, message: '');
}
