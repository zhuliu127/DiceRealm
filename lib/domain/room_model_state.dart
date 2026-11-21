// ============================================================
// room_model_state.dart — 房间状态的构造 / 深拷贝 / 可见性 / 取值助手（D10）
//
// 这一层是「纯数据」：不持有 log、不发事件、不改任何全局。
// 所有键一律用 Map 字面量按旧版赋值顺序写入（LinkedHashMap 保序），
// 因为 `_act` 的 pending 去重靠 `jsonEncode(p)` 做签名（K2）。
// ============================================================

import 'js_compat.dart';
import 'room_ports.dart';
import 'room_types.dart';

/// room-model.js 的 `num(v, dflt)`：`Number(v)` 语义（**不是** parseInt）。
///
/// ⚠️ 与 [jsNum] 的区别：`num('12abc', 0)` 在旧版是 0（Number 得 NaN → 回落），
///    而 `jsNum('12abc')` 是 12（parseInt 前缀解析）。房间层一律用本函数。
num roomNumber(Object? v, [num dflt = 0]) {
  final n = _toNumber(v);
  if (n == null || n.isNaN || n.isInfinite) return dflt;
  return n;
}

num? _toNumber(Object? v) {
  if (v == null) return 0;
  if (v is num) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    if (t.toLowerCase().startsWith('0x')) {
      final h = int.tryParse(t.substring(2), radix: 16);
      return h;
    }
    final d = double.tryParse(t);
    if (d == null) {
      // JS Number('12abc') === NaN
      return double.nan;
    }
    return d == d.truncateToDouble() ? d.toInt() : d;
  }
  return double.nan;
}

/// 房间初始状态。**18 个顶层键，顺序固定**（旧版 `emptyState`）。
Map<String, Object?> emptyRoomState([Map<String, Object?>? meta]) {
  final m = meta ?? const <String, Object?>{};
  final crit = m['critThreshold'];
  final fumble = m['fumbleThreshold'];

  return <String, Object?>{
    'meta': <String, Object?>{
      'code': jsTruthy(m['code']) ? m['code'] : '',
      'name': jsTruthy(m['name']) ? m['name'] : '',
      'rules': jsTruthy(m['rules']) ? m['rules'] : 'coc7',
      'kpName': jsTruthy(m['kpName']) ? m['kpName'] : '',
      // `(meta && meta.maxPlayers) || 4`：0 / '' 也会退回默认值
      'maxPlayers': jsTruthy(m['maxPlayers']) ? m['maxPlayers'] : 4,
      // 只有「给了 meta」才读 allowSpectate；meta 为 null 时默认允许旁观
      'allowSpectate': meta == null ? true : jsTruthy(m['allowSpectate']),
      'status': jsTruthy(m['status']) ? m['status'] : RoomStatus.recruiting,
      'mode': jsTruthy(m['mode']) ? m['mode'] : RoomMode.exploration,
      'round': jsTruthy(m['round']) ? m['round'] : 0,
      // 自定义大成功 / 大失败阈值；缺省 1 / 100（100 = 未自定义，走动态规则）
      'critThreshold':
          (crit == null) ? 1 : roomNumber(crit, 1),
      'fumbleThreshold':
          (fumble == null) ? 100 : roomNumber(fumble, 100),
      // 每周重伤恢复判定 / 精神治疗冷却的座位基准表（随快照与存档走）
      'hpWeek': m['hpWeek'] is Map
          ? roomClone(m['hpWeek'])
          : <String, Object?>{},
      'psychoRound': m['psychoRound'] is Map
          ? roomClone(m['psychoRound'])
          : <String, Object?>{},
    },
    'members': <Object?>[],
    'chats': <Object?>[],
    'logs': <Object?>[],
    'dice': <Object?>[],
    'scene': null,
    'combat': null,
    'privates': <Object?>[],
    'rewind': null,
    'requests': <Object?>[],
    'board': null,
    'sceneCheck': null,
    'archive': null,
    'lastState': null,
    'alert': null,
    'opposed': null,
    'seq': 0,
    'version': 1,
  };
}

/// 深拷贝（数组/对象递归，标量原样返回）。**保持键的插入顺序**。
Object? roomClone(Object? x) {
  if (x is Map) {
    final out = <String, Object?>{};
    for (final e in x.entries) {
      out['${e.key}'] = roomClone(e.value);
    }
    return out;
  }
  if (x is List) return x.map(roomClone).toList();
  return x;
}

/// 载荷里是否含私有字段（递归）。命中即可判定「这条不该广播」。
bool hasSecret(Object? p) {
  if (p is Map) {
    for (final e in p.entries) {
      if (kSecretKeys.contains(e.key)) return true;
      if (hasSecret(e.value)) return true;
    }
    return false;
  }
  if (p is List) {
    for (final v in p) {
      if (hasSecret(v)) return true;
    }
    return false;
  }
  return false;
}

/// 剥掉私有字段（返回副本，不修改入参）。
Object? scrub(Object? p) {
  if (p is Map) {
    final out = <String, Object?>{};
    for (final e in p.entries) {
      final k = '${e.key}';
      if (kSecretKeys.contains(k)) continue;
      out[k] = scrub(e.value);
    }
    return out;
  }
  if (p is List) return p.map(scrub).toList();
  return p;
}

/// 角色能否执行该 action（**只查登记表**，不看房间现状）。
bool allowed(String role, String action) {
  final entry = kRoomPolicy[action];
  if (entry == null) return false;
  return entry.roles.contains(role);
}

/// 权限判定结果。⚠️ 未登记 action 一律 `allowed:false, confirm:null`。
///
/// 这也是 Q6 的落点：`rollback.turn` 已从 POLICY 摘除 → 伪造的 ACT 会被这里拒绝。
NeedsResult needs(String role, String action) {
  final entry = kRoomPolicy[action];
  if (entry == null || !entry.roles.contains(role)) {
    return const NeedsResult(false, null);
  }
  return NeedsResult(true, entry.confirm);
}

/// 把房间 meta 的自定义阈值翻成规则服务需要的 `{critMax, fumbleMin}`。
///
/// ⚠️ 语义铁律：只有落在 **1-99** 的值才下发；其余（100 / 0 / 空 / 非法）
///    一律不下发 → 规则层走默认（大成功 01、大失败动态 96-100 或仅 100）。
Map<String, Object?> ruleOptsOf(Map<String, Object?>? meta) {
  final out = <String, Object?>{};
  if (meta == null) return out;
  final c = jsParseInt(meta['critThreshold']);
  if (c != null && c >= 1 && c <= 99) out['critMax'] = c;
  final f = jsParseInt(meta['fumbleThreshold']);
  if (f != null && f >= 1 && f <= 99) out['fumbleMin'] = f;
  return out;
}

/// 身体状态视图。优先级：**死亡 > dying > unconscious > body**。
///
/// 所有「读 body 做显示 / 判定」的地方一律走这里，避免两处口径漂移。
String bodyView(Map<String, Object?>? st) {
  final raw = st?['body'];
  final b = jsTruthy(raw) ? jsStr(raw) : '正常';
  if (b == '死亡') return '死亡';
  if (st != null && jsTruthy(st['dying'])) return '濒死';
  if (st != null && jsTruthy(st['unconscious'])) return '昏迷';
  return b;
}

/// 按 HP 猜测伤级（**老卡迁移专用**的保守推断）。
///
/// ⚠️ 不能拿去推导 healWound / aidApply 的归位结果：那两处的口径是
///    「HP ≥ 上限 → 正常，否则轻伤」，套用本函数会把「HP ≥ 半血」误判成重伤。
String bodyForHp(Object? hp, Object? maxHP) {
  final max = roomNumber(maxHP, 0);
  final cur = roomNumber(hp, 0);
  if (max > 0 && cur >= max) return '正常';
  if (max > 0 && cur * 2 >= max) return '重伤';
  return '轻伤';
}

/// 老卡身体状态的**一次性迁移**（幂等）。
///
/// body 白名单从 6 值收敛为 4 值后，老存档里的 '濒死' / '昏迷' 必须翻译成
/// 「4 值 body + 布尔标记」，否则会被白名单过滤成 '正常' —— 伤势凭空消失。
void migrateBodyStatus(Map<String, Object?> st) {
  if (st['body'] == '濒死') {
    st['body'] = '重伤';
    st['dying'] = true;
  } else if (st['body'] == '昏迷') {
    st['unconscious'] = true;
    final curHp = st['currentHP'] ?? st['hp'];
    st['body'] = bodyForHp(curHp, st['maxHP']);
  }
}

/// 房间号口子：只允许 4-12 位小写字母数字（与服务端正则保持一致）。
bool validCode(Object? c) {
  final s = jsTruthy(c) ? jsStr(c) : '';
  return RegExp(r'^[a-z0-9]{4,12}$').hasMatch(s);
}

final RegExp _reControl = RegExp(r'[\u0000-\u0008\u000b-\u001f]');

/// 文本净化：去控制字符、去首尾空白、可截断。
String cleanText(Object? s, [int? max]) {
  var t = jsStr(s ?? '').replaceAll(_reControl, '').trim();
  if (max != null && max > 0 && t.length > max) t = t.substring(0, max);
  return t;
}

/// 邀请链接：把服务地址一并带上，加入方不用再猜地址（局域网尤其重要）。
String inviteLink(String pageUrl, String code, [String? serverBase]) {
  var u = pageUrl;
  final hash = u.indexOf('#');
  if (hash >= 0) u = u.substring(0, hash);
  final sep = u.contains('?') ? '&' : '?';
  var out = '$u${sep}room=${Uri.encodeComponent(code)}';
  if (jsTruthy(serverBase)) {
    out += '&srv=${Uri.encodeComponent(serverBase!)}';
  }
  return out;
}

final RegExp _reCompact =
    RegExp(r'^COC7ROOM\s*[|｜]\s*([^|｜]*)\s*[|｜]\s*([A-Za-z0-9]*)',
        caseSensitive: false);
final RegExp _reQueryRoom = RegExp(r'(^|[&])room=');
final RegExp _reHttp = RegExp(r'^https?://', caseSensitive: false);
final RegExp _reBareAddr = RegExp(r'^[\w.-]+:\d+(/.*)?$');

/// 解析「加入信息」字符串 —— 宽容解析，尽量把房间号与服务地址都抠出来。
///
/// 识别顺序（先匹配到谁就用谁）：
///   ① `COC7ROOM|<host:port>|<code>` 紧凑串（分隔符兼容全角竖线）
///   ② 带查询串的链接 / 纯查询串（`?room=xx&srv=yy`，旧版邀请链接）
///   ③ 裸地址（`host:port` 或 `http(s)://host[:port][/path]`）
///   ④ 裸房间号（4-12 位小写字母数字）
Map<String, Object?> readInvite(Object? str) {
  final out = <String, Object?>{'code': '', 'serverBase': ''};
  final s = jsStr(str ?? '').trim();
  if (s.isEmpty) return out;

  final m = _reCompact.firstMatch(s);
  if (m != null) {
    out['serverBase'] = normalizeServerBase(m.group(1));
    out['code'] = (m.group(2) ?? '').toLowerCase();
    return out;
  }

  var qs = s;
  final qi = s.indexOf('?');
  if (qi >= 0) qs = s.substring(qi + 1);
  if (qi >= 0 || _reQueryRoom.hasMatch(s)) {
    final q = <String, String>{};
    for (final kv in qs.split('&')) {
      if (kv.isEmpty) continue;
      final i = kv.indexOf('=');
      final k = i < 0 ? kv : kv.substring(0, i);
      final raw = i < 0 ? '' : kv.substring(i + 1);
      // 旧版 `decodeURIComponent(v.replace(/\+/g,' '))`
      q[k] = Uri.decodeComponent(raw.replaceAll('+', ' '));
    }
    return <String, Object?>{
      'code': (q['room'] ?? '').toLowerCase(),
      'serverBase': normalizeServerBase(q['srv'] ?? ''),
    };
  }

  if (_reHttp.hasMatch(s) || _reBareAddr.hasMatch(s)) {
    out['serverBase'] = normalizeServerBase(s);
    return out;
  }

  final lower = s.toLowerCase();
  if (validCode(lower)) out['code'] = lower;
  return out;
}

final RegExp _reHostLike = RegExp(r'^[\w.-]+(:\d+)?(/.*)?$');
final RegExp _reTrailingSlash = RegExp(r'/+$');

/// 规范化「服务器地址」片段：缺协议头就补 `http://`，并去掉结尾多余的斜杠。
String normalizeServerBase(Object? v) {
  var t = jsStr(v ?? '').trim();
  if (t.isEmpty) return '';
  if (!_reHttp.hasMatch(t) && _reHostLike.hasMatch(t)) t = 'http://$t';
  return t.replaceAll(_reTrailingSlash, '');
}
