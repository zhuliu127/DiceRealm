// ============================================================
// view/member_view.dart — 成员只读派生（设计 §3.6）
//
// ★ 纯 Dart：零 UI 框架依赖。
// ★ S1：HP/MP/SAN 兼容两套来源（sheet.status 与 mem.runtime），逐个回退。
// ★ S5：判活必须带 `hpMax > 0` 守卫，否则 HP 未公开的怪物会被判「已死」。
// ★ C2：他人视图 `maxSAN` 被裁成 null → 只显当前值，不能出现 '/' 分隔。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_state.dart' show bodyView, roomNumber;
import '../room_text.dart';

/// 成员的生命 / 精神数值与身体状态（不可变值对象）。
class MemberStats {
  const MemberStats({
    required this.hp,
    required this.hpMax,
    required this.mp,
    required this.mpMax,
    required this.san,
    required this.sanMax,
    required this.hasMaxSan,
    required this.body,
    required this.dying,
    required this.unconscious,
  });

  final num hp, hpMax, mp, mpMax, san, sanMax;

  /// 他人视图的 `maxSAN` 被置 null → false；此时 [sanText] 不得输出上限。
  final bool hasMaxSan, dying, unconscious;
  final String body;
}

num? _finite(Object? v) {
  if (v is num && !v.isNaN && !v.isInfinite) return v;
  return null;
}

/// 逐个回退取值：status → runtime → sheet 顶层 → 默认值。
num _pick(Object? a, Object? b, Object? c, num dflt) =>
    _finite(a) ?? _finite(b) ?? _finite(c) ?? dflt;

Map<String, Object?> _sheetOf(Map<String, Object?>? mem) =>
    asMap(mem?['sheet']);

Map<String, Object?> _statusOf(Map<String, Object?>? mem) =>
    asMap(_sheetOf(mem)['status']);

Map<String, Object?> _runtimeOf(Map<String, Object?>? mem) =>
    asMap(mem?['runtime']);

String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// ★ S1：双源兼容。缺键 ≠ 0；缺失时逐项回退，绝不把整个数值块读成 0。
MemberStats memberStats(Map<String, Object?>? mem) {
  final sh = _sheetOf(mem);
  final st = _statusOf(mem);
  final rt = _runtimeOf(mem);

  final hp = _pick(st['currentHP'], rt['hp'], sh['hp'], 0);
  final hpMax = _pick(st['maxHP'], rt['maxHP'], sh['maxHP'], 0);
  final mp = _pick(st['currentMP'], rt['mp'], sh['mp'], 0);
  final mpMax = _pick(st['maxMP'], rt['maxMP'], sh['maxMP'], 0);
  final san = _pick(st['currentSAN'], rt['san'], sh['san'], 0);
  final maxSanRaw = _finite(st['maxSAN']) ?? _finite(sh['maxSAN']);

  final dying = jsTruthy(st['dying']) || jsTruthy(rt['dying']);
  final unconscious =
      jsTruthy(st['unconscious']) || jsTruthy(rt['unconscious']);

  return MemberStats(
    hp: hp,
    hpMax: hpMax,
    mp: mp,
    mpMax: mpMax,
    san: san,
    sanMax: maxSanRaw ?? 0,
    hasMaxSan: maxSanRaw != null,
    body: bodyViewOf(mem),
    dying: dying,
    unconscious: unconscious,
  );
}

/// 该成员有没有**真实的** HP/MP/SAN 数值（区别于 [memberStats] 的「取不到给 0」）。
///
/// ★ 为什么必须和 [memberStats] 分开：`memberStats` 的契约是「能取到多少报多少，
///   取不到回退 0」，它**回答不了**「这个人到底有没有卡数据」。两者混用，就会把
///   「进房了但还没绑卡 / 数值还没同步到」画成一张 `HP 0 / 0` 的假卡 ——
///   用户 2026-11-11 真机报的「HP / MP / SAN 三个数值都是空的，显示成 -」，
///   走的就是这条路径（三条 `StatBar` 的 ratio 恒 0 → 只剩一条空轨道）。
///
/// 判据与 [memberStats] 的三源完全同源（status → runtime → sheet 顶层），
/// 只要**任意一处**有有限数字就算「有数值」；`0` 是合法值（真的 0 点血），
/// 只有「三处都取不到」才算未初始化。
bool hasCardVitals(Map<String, Object?>? mem) {
  if (mem == null) return false;
  final sh = _sheetOf(mem);
  final st = _statusOf(mem);
  final rt = _runtimeOf(mem);
  // HP 是任何一张真卡都必有的项：现值 / 上限任一处有数就成立。
  for (final num? v in <num?>[
    _finite(st['currentHP']),
    _finite(st['maxHP']),
    _finite(rt['hp']),
    _finite(rt['hpMax']),
    _finite(sh['hp']),
    _finite(sh['maxHP']),
  ]) {
    if (v != null) return true;
  }
  return false;
}

/// ★ S2：战斗敏捷只认 `sheet.attrs.dex`；用 derivedStats 会与 KP 视角不一致。
num memberDex(Map<String, Object?>? mem) =>
    _finite(asMap(_sheetOf(mem)['attrs'])['dex']) ?? 0;

/// 身体状态视图：死亡 > 濒死 > 昏迷 > body（复用 domain 的 bodyView）。
/// status 缺布尔键时用 runtime 兜底，避免老卡丢标记。
String bodyViewOf(Map<String, Object?>? mem) {
  final st = <String, Object?>{..._statusOf(mem)};
  final rt = _runtimeOf(mem);
  if (!st.containsKey('dying') && jsTruthy(rt['dying'])) st['dying'] = true;
  if (!st.containsKey('unconscious') && jsTruthy(rt['unconscious'])) {
    st['unconscious'] = true;
  }
  return bodyView(st);
}

/// ★ S5：判活失败。`hpMax <= 0` 表示 HP 未公开 / 未初始化，直接返回 false，
///   绝不把「隐藏」当成「已死」。
bool isDown(Map<String, Object?>? mem) {
  if (mem == null) return false;
  final s = memberStats(mem);
  if (s.hpMax <= 0) return false;
  return s.hp <= 0 || s.body == '死亡' || s.dying || s.unconscious;
}

String hpText(MemberStats s, {required bool full}) =>
    full ? 'HP ${_fmt(s.hp)} / ${_fmt(s.hpMax)}' : 'HP ${_fmt(s.hp)}';

String mpText(MemberStats s, {required bool full}) =>
    full ? 'MP ${_fmt(s.mp)} / ${_fmt(s.mpMax)}' : 'MP ${_fmt(s.mp)}';

/// ★ C2：即便调用方传了 `full:true`，只要 `hasMaxSan == false` 就只显当前值。
String sanText(MemberStats s, {required bool full}) =>
    (full && s.hasMaxSan)
        ? 'SAN ${_fmt(s.san)} / ${_fmt(s.sanMax)}'
        : 'SAN ${_fmt(s.san)}';

bool _hasMental(Map<String, Object?>? mem, String name) {
  for (final v in asList(_sheetOf(mem)['mental'])) {
    if (roomText(v) == name) return true;
  }
  return false;
}

/// 撕卡：死亡或永久疯狂（S8）。
bool isRipped(Map<String, Object?>? mem) =>
    bodyViewOf(mem) == '死亡' || _hasMental(mem, '永久疯狂');

/// ★ S7：与 Host `_memberLocked` 同判据（死亡 / 濒死 / 昏迷 / 三类疯狂）。
bool operationLocked(Map<String, Object?>? mem) {
  if (mem == null) return false;
  final st = _statusOf(mem);
  if (st['body'] == '死亡') return true;
  if (jsTruthy(st['dying']) || jsTruthy(st['unconscious'])) return true;
  return _hasMental(mem, '永久疯狂') ||
      _hasMental(mem, '临时疯狂') ||
      _hasMental(mem, '不定疯狂');
}

/// KP 定向目标过滤：已撕卡的角色不再作为目标。
bool targetBlocked(Map<String, Object?>? mem) => isRipped(mem);

/// 本人看症状名明细；他人只看到计数（K4：缺键 ≠ 0，不假设拿到全量卡）。
String madnessText(Map<String, Object?>? mem, {required bool self}) {
  final sh = _sheetOf(mem);
  if (self) {
    final names = <String>[];
    for (final mRaw in asList(sh['madness'])) {
      final n = roomText(asMap(mRaw)['name']);
      if (n.isNotEmpty) names.add(n);
    }
    if (names.isNotEmpty) return names.join('、');
    final mental = <String>[];
    for (final v in asList(sh['mental'])) {
      final s = roomText(v);
      if (s.isNotEmpty) mental.add(s);
    }
    return mental.isEmpty ? '无异常' : mental.join('、');
  }
  final count = roomNumber(sh['madnessCount'], 0).toInt();
  return count <= 0 ? '无异常' : '不定疯狂 ×$count';
}
