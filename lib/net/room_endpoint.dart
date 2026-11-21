// ============================================================
// net/room_endpoint.dart — 房间地址的规范化与候选排序
//
// 对应旧版 room-net.js 的「地址」那 16 个导出。它们是这一层最容易被
// **简化成「一个 base 变量」**的部分 —— 而一旦简化，局域网就会时通时不通：
//   · 同一台手机可能有多个网卡（WiFi + 热点 + VPN），只有一个能通；
//   · 用户可能手填 `192.168.1.7`（没写 http://）或带尾斜杠；
//   · 注入了局域网地址之后，用户设置里的地址不能反过来把注入的盖掉。
//
// 所以规则写死在这里，UI 与传输层都只问它，不各判一次。
// ============================================================

/// 地址工具（全部是纯函数，无状态、无 I/O）。
class RoomEndpoint {
  const RoomEndpoint._();

  /// 规范化：去空白、去尾斜杠、无 scheme 时补 `http://`。
  ///
  /// 空串返回空串（表示「没配」），**不要**返回默认地址 ——
  /// 「没配」和「配了个默认值」在界面上的提示完全不同。
  static String normalize(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return '';
    // ★ 只有 scheme、没有 host（`http://` / `http:`）—— 先拦掉。
    //   否则下面的「去尾斜杠」会把它变成 `http:/`，再被补成 `http://http:/`，
    //   于是 host 变成了字面量 "http"，looksValid 反而判成合法。
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:/*$').hasMatch(v)) return '';
    // 去尾斜杠（只去一个，`http://x//` 这种本身就不合法）
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    if (v.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(v)) {
      v = 'http://$v';
    }
    return v;
  }

  /// 是不是一个看起来能用 HTTP(S) 访问的地址。
  static bool looksValid(String raw) {
    final v = normalize(raw);
    if (v.isEmpty) return false;
    final uri = Uri.tryParse(v);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return true;
  }

  /// 私网 / 回环 / 链路本地地址判断。
  ///
  /// 用途：决定要不要提示「这个地址只有同一局域网的人能访问」。
  static bool isPrivateHost(String host) {
    if (host.isEmpty) return false;
    if (host == 'localhost') return true;
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
    if (m == null) return false; // 域名按「公网」处理，不猜
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    if (a == 10) return true;
    if (a == 127) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 169 && b == 254) return true; // 链路本地（多半跨设备不通）
    return false;
  }

  /// 拆分多地址输入（支持逗号、分号、空白分隔）。
  static List<String> split(String raw) {
    if (raw.trim().isEmpty) return const <String>[];
    final parts = raw.split(RegExp(r'[,;，；\s]+'));
    final out = <String>[];
    for (final p in parts) {
      final n = normalize(p);
      if (n.isNotEmpty && looksValid(n) && !out.contains(n)) out.add(n);
    }
    return out;
  }

  /// 候选地址列表（**按优先级排序，且去重**）。
  ///
  /// 顺序：注入的（局域网当服务端时）> 用户手填 > 内置预设。
  /// 注入的必须排第一 —— 它代表「这台手机现在就是服务器」，
  /// 用户设置里那个旧地址不该盖过它（旧版 injected() 注释专门强调过）。
  static List<String> candidates({
    String injected = '',
    String user = '',
    List<String> presets = const <String>[],
  }) {
    final out = <String>[];
    void add(String v) {
      final n = normalize(v);
      if (n.isEmpty || !looksValid(n) || out.contains(n)) return;
      out.add(n);
    }

    for (final v in split(injected)) {
      add(v);
    }
    for (final v in split(user)) {
      add(v);
    }
    for (final v in presets) {
      add(v);
    }
    return out;
  }

  /// 由 HTTP base 推导 WebSocket 地址（`http→ws` / `https→wss`，路径 `/ws`）。
  static String wsUrlFor(String base) {
    final n = normalize(base);
    if (n.isEmpty) return '';
    final uri = Uri.tryParse(n);
    if (uri == null || uri.host.isEmpty) return '';
    return Uri(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/ws',
    ).toString();
  }

  /// 取 host（用于私网判断与展示）。
  static String hostOf(String base) {
    final n = normalize(base);
    if (n.isEmpty) return '';
    return Uri.tryParse(n)?.host ?? '';
  }

  /// 这个地址是否只能同局域网访问（界面据此提示，而不是等用户试）。
  static bool isLanOnly(String base) {
    final h = hostOf(base);
    if (h.isEmpty) return false;
    return isPrivateHost(h);
  }
}
