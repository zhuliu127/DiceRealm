// ============================================================
// ai_caps.dart — AI / 预设卡共用的「房规数值上限」（纯规则，无网络）
// 逐行对应 `core/ai.js` 里的 `caps()` / `applyAttrCap()` / `capsText()`
//
// 为什么单独一个文件：preset.js 通过 `global.AIGen.applyAttrCap` 复用同一套
// 压缩算法，P3-B 的 AI 车卡也要用同一份 —— 两边共用才能保证
// 「随机卡」与「AI 卡」被上限压出来的形态完全一致。
//
// 语义（别改）：
//   attrCap  属性总和上限（九项含幸运 / 八项不含幸运，看 withLuck）
//   occCap   每项**本职技能最终值**的上限（不是压缩点数池！）
//   intCap   每项**兴趣技能最终值**的上限
//   0 一律表示「不限」。
//
// ★ P7 真机反馈修复（2026-11-10，依据用户真机实测有意偏离旧版）：
//   旧版 `applyAttrCap` 用「等比压缩 + floor + 逐项 +1」，输出是**任意整数**，
//   不是 5 的倍数；车卡向导的 `attrFieldError` 要求 `v % 5 == 0`，于是 AI 卡 /
//   随机卡一旦被压缩，进「继续完善」必被「必须是 5 的倍数」卡死，无法点下一步。
//   生产路径现在改走 [_applyAttrCapGrid]：**在 5 的倍数网格上压缩**。
//   逐字等价旧 JS 的原始算法保留在 [applyAttrCapLegacy]，专供 P3/P4 预言机
//   比对（开关 [legacyAttrCapForOracle]，默认 false = 生产走新算法）。
// ============================================================

import 'js_compat.dart';
import 'rules_coc7.dart' show genMax, genMin, genStep;

/// 房规数值上限
class AiCaps {
  const AiCaps({
    this.attrCap = 0,
    this.withLuck = true,
    this.occCap = 0,
    this.intCap = 0,
  });

  /// 从任意 Map 形状读入（`{attrCap, withLuck, occCap, intCap}`）
  factory AiCaps.fromMap(Map? m) {
    if (m == null) return const AiCaps();
    return AiCaps(
      attrCap: jsNum(m['attrCap']),
      withLuck: m['withLuck'] != false,
      occCap: jsNum(m['occCap']),
      intCap: jsNum(m['intCap']),
    );
  }

  /// 属性总和上限（0 = 不限）
  final int attrCap;

  /// true = 含幸运，false = 不含幸运
  final bool withLuck;

  /// 每项本职技能最终值上限（0 = 不限）
  final int occCap;

  /// 每项兴趣技能最终值上限（0 = 不限）
  final int intCap;

  /// 上限是否生效（界面提示用）
  bool get active => attrCap > 0 || occCap > 0 || intCap > 0;

  Map<String, Object?> toMap() => <String, Object?>{
    'attrCap': attrCap,
    'withLuck': withLuck,
    'occCap': occCap,
    'intCap': intCap,
  };

  /// 翻译成一句人话（界面显示「本次会按这些上限生成」）
  String get text {
    final parts = <String>[];
    if (attrCap > 0) {
      parts.add('属性总和 ≤ $attrCap（${withLuck ? '含幸运' : '不含幸运'}）');
    }
    if (occCap > 0) parts.add('每项本职技能 ≤ $occCap');
    if (intCap > 0) parts.add('每项兴趣技能 ≤ $intCap');
    return parts.join(' · ');
  }
}

/// 从设置表里读上限（`ai.js#caps`）
///
/// 每次生成时现读 —— 玩家改完设置再点「换一批」立刻生效。
AiCaps capsFromSettings(Map<String, Object?>? settings) {
  final s = settings ?? <String, Object?>{};
  final a = jsNum(s['aiAttrCap']);
  final o = jsNum(s['aiOccPtsCap']);
  final i = jsNum(s['aiIntPtsCap']);
  return AiCaps(
    attrCap: a > 0 ? a : 0,
    withLuck: s['aiAttrCapWithLuck'] != false,
    occCap: o > 0 ? o : 0,
    intCap: i > 0 ? i : 0,
  );
}

const List<String> _attrKeys = <String>[
  'str',
  'con',
  'siz',
  'dex',
  'app',
  'int',
  'pow',
  'edu',
];

/// 旧版压缩算法的属性区间（`core/ai.js` 里 ATTR_MIN=15 / ATTR_MAX=99）。
/// ⚠️ 只有 legacy 用它们；生产算法一律用 rules_coc7 的 genMin/genMax/genStep。
const int _legacyAttrMin = 15;
const int _legacyAttrMax = 99;

/// 预言机兼容开关（默认 false）。
///
/// 只有 `test/oracle_preset_test.dart` 在比对冻结 fixture（旧版 JS 输出）时置 true，
/// 让 [applyAttrCap] 委托给 [applyAttrCapLegacy]。生产与全部其它测试保持 false，
/// 走 5 倍数网格新算法。绝不靠改 fixture 期望值把测试「变绿」。
bool legacyAttrCapForOracle = false;

/// 属性总和超限时的本地校准。
///
/// 生产路径（[legacyAttrCapForOracle] == false）：在 `genStep` 的倍数网格上做
/// 等比压缩，输出**每一项都是 5 的倍数、落在 [genMin, genMax]、总和不超过
/// [AiCaps.attrCap]**，且保持「原来强的仍强」。这是车卡向导 `attrFieldError`
/// 能放行的唯一合法形态。
///
/// 预言机路径（开关为 true）：逐字调用旧版算法 [applyAttrCapLegacy]。
///
/// [profile] 是形状为 `{attributes: {...}}` 的 Map（与 JS 完全一致，
/// 这样预设立场与 AI 立场可以共用同一个函数）。
///
/// @returns 是否真的动过（没超限就是 false，属性原样保留）
bool applyAttrCap(Map<String, Object?>? profile, AiCaps? cap) {
  if (legacyAttrCapForOracle) return applyAttrCapLegacy(profile, cap);
  return _applyAttrCapGrid(profile, cap);
}

/* ------------------------------------------------------------------
 * 5 倍数网格压缩（生产算法）
 *
 * 不变式（写在这里是为了让它不可能被绕过，测试逐条钉住）：
 *   I1 未超限（sum <= attrCap）→ 返回 false，属性一个字节都不改。
 *   I2 超限 → 每个输出值 v 满足 v % genStep == 0。
 *   I3 超限 → 每个输出值 v 满足 genMin <= v <= genMax。
 *   I4 超限 → 输出总和 total <= attrCap（宁可略低于上限，绝不因
 *      取整 / 补齐反弹超限；余数按 genStep 步长分配，不足一步的零头丢弃）。
 *   I5 相对高低不乱：按原始值降序排好后，输出值非增（相邻倒置交换回来；
 *      交换不改总和、不改 5 倍数）。
 *   I6 withLuck 两种口径都只对参与求和的 keys 生效，未参与求和的项不动。
 *
 * 物理下界（如实说明，不藏）：total 的最小可能值是 keys.length × genMin
 * （9 项含幸运 = 135，8 项 = 120）。当 attrCap 低于它时，I3 与 I4 无法
 * 同时成立 —— 本算法优先 I3（规则区间），把所有项压到 genMin 并停止扣减，
 * 此时 total 等于物理下界、返回 true（确实动过）。调用方不会拿到非法属性。
 * ------------------------------------------------------------------ */

int _floorToStep(num v) => (v / genStep).floor() * genStep;
int _ceilToStep(int v) => ((v + genStep - 1) ~/ genStep) * genStep;
int _clampGrid(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

bool _applyAttrCapGrid(Map<String, Object?>? profile, AiCaps? cap) {
  if (cap == null || cap.attrCap == 0) return false;
  if (profile == null) return false;
  final attrs = profile['attributes'];
  if (attrs is! Map) return false;
  final a = attrs.cast<String, Object?>();

  final keys = List<String>.from(_attrKeys);
  if (cap.withLuck) keys.add('luck');

  final orig = <String, int>{for (final k in keys) k: jsNum(a[k])};
  var sum = 0;
  for (final k in keys) {
    sum += orig[k]!;
  }
  // I1：没超限原样不动、返回 false。
  if (sum == 0 || sum <= cap.attrCap) return false;

  final lo = _ceilToStep(genMin); // 15
  final hi = _floorToStep(genMax); // 90
  final f = cap.attrCap / sum;

  final vals = <String, int>{};
  final fracs = <double>[];
  for (final k in keys) {
    final t = orig[k]! * f;
    final stepped = _floorToStep(t);
    vals[k] = _clampGrid(stepped, lo, hi);
    fracs.add(t - stepped);
  }
  var total = 0;
  for (final k in keys) {
    total += vals[k]!;
  }

  // ① 被 lo 抬高（或 f 很大）导致超上限：从最高的往下按 genStep 扣。
  var guard = 0;
  while (total > cap.attrCap && guard++ < 4000) {
    String? hiKey;
    for (final k in keys) {
      if (hiKey == null || vals[k]! > vals[hiKey]!) hiKey = k;
    }
    if (hiKey == null || vals[hiKey]! - genStep < lo) break;
    vals[hiKey] = vals[hiKey]! - genStep;
    total -= genStep;
  }

  // ② 余数按 genStep 步长补齐：每项最多补一步，且总和绝不越过上限。
  var rem = cap.attrCap - total;
  if (rem >= genStep) {
    final order = List<int>.generate(keys.length, (i) => i);
    // 稳定排序：小数部分相等时按原下标升序（V8 Array#sort 自 ES2019 稳定）。
    order.sort((x, y) {
      final c = fracs[y].compareTo(fracs[x]);
      return c != 0 ? c : x - y;
    });
    for (final oi in order) {
      if (rem < genStep) break;
      final k = keys[oi];
      if (vals[k]! + genStep <= hi) {
        vals[k] = vals[k]! + genStep;
        total += genStep;
        rem -= genStep;
      }
    }
  }

  // ③ 秩序修复：等比 + 网格取整难免出现「原来高的反而低了一格」的相邻倒置。
  //    按原始高低排好序，把倒置的相邻两项交换回来 —— 交换不改总和，
  //    且两项都在 5 倍数网格上，合法性不受影响。
  final byOrig = List<String>.from(keys);
  final origIdx = <String, int>{
    for (var i = 0; i < keys.length; i++) keys[i]: i,
  };
  byOrig.sort((x, y) {
    final c = orig[y]!.compareTo(orig[x]!);
    return c != 0 ? c : (origIdx[x] ?? 0) - (origIdx[y] ?? 0);
  });
  for (var pass = 0; pass < byOrig.length; pass++) {
    var swapped = false;
    for (var i = 0; i + 1 < byOrig.length; i++) {
      if (vals[byOrig[i]]! < vals[byOrig[i + 1]]!) {
        final tmp = vals[byOrig[i]]!;
        vals[byOrig[i]] = vals[byOrig[i + 1]]!;
        vals[byOrig[i + 1]] = tmp;
        swapped = true;
      }
    }
    if (!swapped) break;
  }

  for (final k in keys) {
    a[k] = vals[k]!;
  }
  return true;
}

/// 旧版 `core/ai.js#applyAttrCap` 的**逐字等价**实现。
///
/// ⚠️ 只给 P3/P4 预言机比对冻结 fixture 用（旧版输出本来就不是 5 的倍数），
/// 生产路径绝不调用：它会产生非 5 倍数的属性，让车卡向导卡死。
/// 等比压缩 + 最大余数法补齐 + 相邻倒置修复，一行未改。
bool applyAttrCapLegacy(Map<String, Object?>? profile, AiCaps? cap) {
  if (cap == null || cap.attrCap == 0) return false;
  if (profile == null) return false;
  final attrs = profile['attributes'];
  if (attrs is! Map) return false;
  final a = attrs.cast<String, Object?>();

  final keys = List<String>.from(_attrKeys);
  if (cap.withLuck) keys.add('luck');

  var sum = 0;
  for (final k in keys) {
    sum += jsNum(a[k]);
  }
  if (sum == 0 || sum <= cap.attrCap) return false;

  final f = cap.attrCap / sum;
  final vals = <String, int>{};
  final fracIdx = <int>[];
  final fracs = <double>[];
  var total = 0;
  for (var i = 0; i < keys.length; i++) {
    final k = keys[i];
    final v = jsNum(a[k]);
    final t = v * f;
    final b = jsMin(<int>[
      _legacyAttrMax,
      jsMax(<int>[_legacyAttrMin, t.floor()]),
    ]);
    vals[k] = b;
    total += b;
    fracIdx.add(i);
    fracs.add(t - t.floorToDouble());
  }

  final rem = cap.attrCap - total;
  if (rem > 0) {
    final order = List<int>.generate(fracIdx.length, (i) => i);
    order.sort((x, y) {
      final c = fracs[y].compareTo(fracs[x]);
      return c != 0 ? c : x - y;
    });
    var left = rem;
    for (var oi = 0; oi < order.length && left > 0; oi++) {
      final k = keys[fracIdx[order[oi]]];
      if ((vals[k] ?? 0) < _legacyAttrMax) {
        vals[k] = (vals[k] ?? 0) + 1;
        left--;
      }
    }
    var g2 = 0;
    while (left > 0 && g2++ < 4000) {
      var moved2 = false;
      for (var oi = 0; oi < order.length && left > 0; oi++) {
        final k = keys[fracIdx[order[oi]]];
        if ((vals[k] ?? 0) < _legacyAttrMax) {
          vals[k] = (vals[k] ?? 0) + 1;
          left--;
          moved2 = true;
        }
      }
      if (!moved2) break;
    }
  }
  var guard = 0;
  while (total > cap.attrCap && guard++ < 4000) {
    String? hi;
    for (final k in keys) {
      if (hi == null || (vals[k] ?? 0) > (vals[hi] ?? 0)) hi = k;
    }
    if (hi == null || (vals[hi] ?? 0) <= _legacyAttrMin) break;
    vals[hi] = (vals[hi] ?? 0) - 1;
    total--;
  }

  final byOrig = List<String>.from(keys);
  final origIdx = <String, int>{
    for (var i = 0; i < keys.length; i++) keys[i]: i,
  };
  byOrig.sort((x, y) {
    final c = jsNum(a[y]).compareTo(jsNum(a[x]));
    return c != 0 ? c : (origIdx[x] ?? 0) - (origIdx[y] ?? 0);
  });
  for (var pass = 0; pass < byOrig.length; pass++) {
    var swapped = false;
    for (var i = 0; i + 1 < byOrig.length; i++) {
      if ((vals[byOrig[i]] ?? 0) < (vals[byOrig[i + 1]] ?? 0)) {
        final tmp = vals[byOrig[i]] ?? 0;
        vals[byOrig[i]] = vals[byOrig[i + 1]] ?? 0;
        vals[byOrig[i + 1]] = tmp;
        swapped = true;
      }
    }
    if (!swapped) break;
  }

  for (final k in keys) {
    a[k] = vals[k];
  }
  return true;
}
