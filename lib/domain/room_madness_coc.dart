// ============================================================
// room_madness_coc.dart — `RoomMadnessPort` 的生产实现（COC 7 版疯狂表）
//
// 为什么必须落在 domain：它是**规则实现**，由 `RoomHost` 在结算「临时疯狂发作 /
// 不定疯狂复发」时调用（`raRollSymptom(madness)`）。放在 UI 层的组合根里会让
// 「规则在 UI 层」重新出现，正是本工程一直在守的那条线的反面。
//
// 逐行对齐旧版 `coc7th-card-app/web/js/core/madness.js`：
//   · `roll(type, permanent, rng)`
//       - `type ∈ {'phobia','mania'}` → 直接从 100 条子表抽（`pool(type)`）；
//       - 其他（含 `'any'`，也就是 `raRollSymptom` 的调用方式）→ 走**即时症状表**
//         `rollTable(rng)`：1–8 得「发作行为（bout）」、9 恐惧症、10 狂躁症；
//   · `rounds = permanent ? 0 : 1 + floor(rand * 10)`（规则书：1D10 轮）——
//     与旧版 `1 + Math.floor(Math.random() * 10)` 同式；
//     区别只在于旧版这一处**没走注入的 rng**（直接吃 `Math.random`），这里统一用
//     注入源，测试才能钉死。
//   · `name/en/desc` 原样带出，`raRollSymptom` 只取这几个字段。
//
// ★ 纯 Dart：零 UI 框架、零 IO、零随机全局状态（随机源一律注入）。
// ============================================================

import 'js_compat.dart' show JsRng, asMap, jsStr, nowRng;
import 'madness.dart' as madness;
import 'room_ports.dart' show RoomMadnessPort;

/// COC 7 版疯狂表端口实现（无状态，可 const）。
class CocMadness implements RoomMadnessPort {
  const CocMadness();

  /// 临时疯狂持续轮数上限：规则书 1D10。
  static const int maxRounds = 10;

  @override
  Map<String, Object?>? roll(Object? type, bool permanent, [JsRng? rng]) {
    final r = rng ?? nowRng;
    final t = jsStr(type);

    Map<String, Object?> src;
    String kind;
    if (t == 'phobia' || t == 'mania') {
      // 手动指定表：直接从该表抽一条
      final pool = madness.pool(t);
      if (pool.isEmpty) return null;
      src = pool[_index(r, pool.length)];
      kind = t;
    } else {
      // 默认（`'any'`）：1D10 即时症状表 —— 1-8 发作行为、9 恐惧表、10 狂躁表
      final hit = madness.rollTable(r);
      kind = jsStr(hit['kind']);
      src = asMap(hit['src']);
      if (src.isEmpty) return null;
    }

    return <String, Object?>{
      'type': kind,
      'name': src['name'],
      'en': src['en'] ?? '',
      'desc': src['desc'] ?? '',
      'permanent': permanent,
      // 规则书：临时疯狂持续 1D10 轮（旧版同式）
      'rounds': permanent ? 0 : 1 + _index(r, maxRounds),
      'from': permanent ? '永久疯狂' : '临时疯狂',
      'bg': false,
      'sum': false,
    };
  }

  @override
  Map<String, Object?>? make(
    Object? type,
    bool permanent,
    String? name, [
    JsRng? rng,
  ]) {
    final rolled = roll(type, permanent, rng);
    if (rolled == null) return null;
    // KP 手填症状名时以手填为准，其余字段仍按表来
    final text = (name ?? '').trim();
    if (text.isNotEmpty) rolled['name'] = text;
    return rolled;
  }

  /// `0..n-1` 的安全取整（随机源理论上可能给 1.0 或负数）。
  static int _index(JsRng r, int n) {
    if (n <= 0) return 0;
    final v = (r() * n).floor();
    if (v < 0) return 0;
    return v >= n ? n - 1 : v;
  }
}
