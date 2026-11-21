// ============================================================
// chargen_logic.dart — 车卡向导的**纯逻辑**（无 BuildContext、可单测）
//
// 只做三件事：
//   1. 属性输入的「前置闸门」（挡住会触发原码 ATT_MAP 异常的值）
//   2. 职业限定技能的勾选读写
//   3. 「一键分配剩余点数」（让硬约束「点数必须用完」在手机上可完成）
//
// 规则数值一律来自 lib/domain，这里不写死任何公式。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/combat_skill_map.dart';
import 'package:dice_realm/domain/dice.dart' show roll;
import 'package:dice_realm/domain/edu_check.dart'
    show eduCap, eduCheck, eduCheckAllowance;
import 'package:dice_realm/domain/engine.dart' show recalc;
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/rules_coc7.dart';
import 'package:dice_realm/domain/skillmodel.dart';

import '../attr_meta.dart';

/// 单个属性输入的基础校验：返回错误文案，null 表示合法。
///
/// ⚠️ 必须在调用 domain 的 `validatePointBuy` **之前**跑。
/// 原码 `validatePointBuy` 内部引用了未定义的 `ATT_MAP`（见 _p0_report.txt 坑 A），
/// 一旦传入「非 15-90」或「非 5 的倍数」的值就直接抛 ReferenceError。
/// 所以 UI 先在这里拦住非法值，绝不让用户走进异常路径。
String? attrFieldError(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '未填写';
  if (!RegExp(r'^\d+$').hasMatch(t)) return '必须是整数';
  final v = int.parse(t);
  if (v < genMin || v > genMax) return '必须在 $genMin-$genMax 之间';
  if (v % genStep != 0) return '必须是 $genStep 的倍数';
  return null;
}

/// 购点上限：与 domain 的 `Coc7.pointBuyCap` 同源
int pointBuyCap({required bool includeLuck}) =>
    includeLuck ? Coc7.pointBuyCap['withLuck']! : Coc7.pointBuyCap['noLuck']!;

/// 属性体检结果
class AttrCheck {
  const AttrCheck({
    required this.errors,
    required this.sum,
    required this.cap,
    required this.filled,
    required this.enforceCap,
  });

  /// key → 错误文案（空表示全部合法）
  final Map<String, String> errors;
  final int sum;
  final int cap;

  /// 已填写的必填项个数（0..8）
  final int filled;

  /// 是否适用「总和不得超过上限」（只有点数分配模式适用；随机模式不设总上限）
  final bool enforceCap;

  int get remain => cap - sum;

  bool get allCoreFilled => filled == coreAttrKeys.length;

  bool get ok => errors.isEmpty && allCoreFilled && (!enforceCap || sum <= cap);

  /// 是否超上限（用于文案）
  bool get over => enforceCap && sum > cap;
}

/// 体检整张卡的属性输入。
///
/// [pointBuy] 为 true 时额外校验「总和不超过上限」；随机模式下只要 8 项合法即可。
AttrCheck checkAttributes(
  Character card, {
  required bool pointBuy,
  required bool includeLuck,
}) {
  final errors = <String, String>{};
  final keys = <String>[...coreAttrKeys, if (pointBuy && includeLuck) 'luck'];
  var sum = 0;
  var filled = 0;

  for (final k in keys) {
    final raw = jsStr(card.attributes[k] ?? '');
    final err = attrFieldError(raw);
    if (err != null) {
      errors[k] = err;
    } else {
      sum += int.parse(raw.trim());
      if (coreAttrKeys.contains(k)) filled++;
    }
  }

  final cap = pointBuyCap(includeLuck: includeLuck);
  if (pointBuy && errors.isEmpty && sum > cap) {
    errors['__sum'] = '属性总和 $sum 超出上限 $cap，请减少 ${sum - cap} 点';
  }
  return AttrCheck(
    errors: errors,
    sum: sum,
    cap: cap,
    filled: filled,
    enforceCap: pointBuy,
  );
}

/// 取某个需求块的已选项
List<Map<String, Object?>> picksOf(Character card, String reqId) {
  return asList(card.occupationPicks[reqId]).map(asMap).toList();
}

void setPicks(Character card, String reqId, List<Map<String, Object?>> picks) {
  card.occupationPicks[reqId] = picks
      .map((p) => Map<String, Object?>.from(p))
      .toList();
}

/// 该选项是否已被选中
bool isPicked(List<Map<String, Object?>> picks, Object? skill, Object? sub) {
  for (final p in picks) {
    if (jsStr(p['skill']) == jsStr(skill) && jsStr(p['sub']) == jsStr(sub)) return true;
  }
  return false;
}

/// 勾选 / 取消一个选项。返回是否有变化（超额时返回 false，调用方提示即可）
bool togglePick(
  Character card,
  Map<String, Object?> req,
  Map<String, Object?> option, {
  required int max,
}) {
  final reqId = jsStr(req['id']);
  final picks = picksOf(card, reqId);
  final skill = option['skill'];
  final sub = option['sub'];
  final exists = isPicked(picks, skill, sub);
  if (exists) {
    picks.removeWhere(
      (p) => jsStr(p['skill']) == jsStr(skill) && jsStr(p['sub']) == jsStr(sub),
    );
  } else {
    if (picks.length >= max) return false;
    picks.add(<String, Object?>{
      'skill': skill,
      'sub': sub,
      if (jsTruthy(option['name'])) 'name': option['name'],
    });
  }
  setPicks(card, reqId, picks);
  return true;
}

/// 技能实例（按 key 查），没有就按 id/sub 新建并挂到卡上
Map<String, Object?>? findSkill(Character card, String key) => find(card, key);

/// 按**技能实例 key**（`fighting::斗殴` / `throw`）补实例
Map<String, Object?> _ensureSkillByKey(Character card, String key) {
  final exists = find(card, key);
  if (exists != null) return exists;
  final parts = key.split('::');
  return ensureSkill(card, parts[0], parts.length > 1 ? parts[1] : '');
}

Map<String, Object?> ensureSkill(Character card, String id, [String? sub]) {
  final key = keyOf(id, sub);
  final exists = find(card, key);
  if (exists != null) return exists;
  final s = makeSkill(card, id, sub == null || sub.isEmpty ? '' : sub);
  asList(card.raw['skills']).add(s);
  // 新建的实例要立刻按当前属性校准基础值
  s['base'] = baseValue(card, id, sub == null || sub.isEmpty ? '' : sub);
  recompute(s);
  return s;
}

/// 把 `occupationalSet` 里的技能实例补齐（组技能会带 `::专攻`）
void materializeOccupationalSkills(Character card) {
  final set = occupationalSet(card);
  for (final key in set.keys) {
    final parts = key.split('::');
    ensureSkill(card, parts[0], parts.length > 1 ? parts[1] : '');
  }
}

/// 一键把剩余职业技能点 / 兴趣技能点分配掉。
///
/// 为什么需要：本版把「点数必须用完」做成了硬约束（原版也是），
/// 而职业点动辄 200+ —— 手机上一点点加不现实。
///
/// P8（朋友 bug 2）重做口径：
///   ① **单技能不超上限**：全部走 `applyPoint` / `canAdd`，本职走本职上限、
///      非本职走兴趣上限，绝不用「先加再看」的方式绕过；
///   ② **语言最多一门**：`其他语言` 是 flat 组（20 门语言各是一个实例），
///      旧实现按轮转给每门语言各 5 点 —— 现实中没人这样学语言。这里只挑
///      一门非母语语言进兴趣池，母语（`language_own`）按规则豁免、不进池；
///   ③ **常用实用技能加权**：侦查 / 聆听 / 图书馆 / 急救 / 医学 / 潜行 /
///      话术 / 说服 / 魅惑 / 恐吓 / 斗殴 / 手枪 / 闪避 / 心理学 / 攀爬 /
///      汽车驾驶等先吃满，冷门技能只在常用项封顶后兜底（保证点数仍能用完）；
///   ④ 与「自动车卡」（preset_gen）表现对齐：先集中、再摊平、最后兜底；
///   ⑤ **战斗技能跟着武器走**（P9-9）：只有角色实际携带的武器对应的那门战斗
///      技能才配拿「额外分配」的点 —— 带手枪就学射击（手枪），带指虎就学斗殴，
///      没武器也保底学斗殴（徒手能打）。别的战斗技能学了也没机会用。
///      本职技能上的**职业点**属于职业设定，这条只约束兴趣点的额外分配。
///
/// [rng] 可注入（测试用固定序列断言「语言只有一门」「常用占比更高」）。
/// 返回 [occtLeft, intLeft]（分配不完的余数，正常情况下是 0）。
List<int> autoSpendPoints(Character card, {JsRng? rng}) {
  materializeOccupationalSkills(card);

  /* 需求 9：先把「武器用得上的那几门战斗技能」补成实例，再拿这份闸门去
     约束兴趣池（没有武器时闸门里只有斗殴）。 */
  final combatGate = requiredCombatSkillKeys(card);
  for (final key in combatGate) {
    _ensureSkillByKey(card, key);
  }

  final occSet = occupationalSet(card);
  final occSkills = <Map<String, Object?>>[];
  for (final key in occSet.keys) {
    final s = find(card, key);
    // 母语 / 信用评级按规则豁免上限，不参与自动灌点（与 preset_gen 一致）
    if (s != null && !capExempt(jsStr(s['id'])) && !isGrowthOnly(s['id'])) {
      occSkills.add(s);
    }
  }
  // 本职技能先按「武器对得上 > 实用权重」排，再按原本的加点量排（避免总堆在第一个技能）
  occSkills.sort((a, b) {
    final g = _gateRank(b, combatGate).compareTo(_gateRank(a, combatGate));
    if (g != 0) return g;
    final w = _weightOf(b).compareTo(_weightOf(a));
    if (w != 0) return w;
    return jsNum(a['occ']).compareTo(jsNum(b['occ']));
  });

  final allSkills = card.skills
      .map(asMap)
      .where((s) => jsStr(s['id']) != 'custom')
      .where((s) => !isGrowthOnly(s['id']))
      .toList();

  _spend(card, 'occ', occSkills);
  _spendInterest(card, allSkills, rng ?? nowRng, combatGate: combatGate);

  final occ = occupationPoints(card);
  final itr = interestPoints(card);
  return <int>[jsNum(occ['remain']), jsNum(itr['remain'])];
}

/// 常用技能权重（越大越先吃兴趣点）。口径：CoC 7e 常用调查 / 生存技能。
/// 未列出的技能按 [defaultSkillWeight] 处理；语言权重最低（只作背景）。
const Map<String, int> skillUseWeight = <String, int>{
  'spot_hidden': 10, // 侦查
  'listen': 10, // 聆听
  'library': 9, // 图书馆使用
  'stealth': 9, // 潜行
  'dodge': 9, // 闪避
  'psychology': 8, // 心理学
  'first_aid': 8, // 急救
  'fighting': 8, // 格斗（斗殴等）
  'firearms': 8, // 射击（手枪等）
  'medicine': 7, // 医学
  'persuade': 7, // 说服
  'fast_talk': 7, // 话术
  'intimidate': 7, // 恐吓
  'charm': 6, // 魅惑
  'climb': 6, // 攀爬
  'drive_auto': 6, // 汽车驾驶
  'psychoanalysis': 6, // 精神分析
  'lore': 5, // 神秘学 / 传说
  'occult': 5, // 神秘学
  'navigate': 5, // 导航
  'survival': 5, // 生存
  'throw': 5, // 投掷
  'track': 4, // 追踪
  'jump': 4, // 跳跃
  'swim': 3, // 游泳
  'language_other': 2, // 其他语言（只允许一门）
};

/// 未列出的技能权重（会计 / 历史 / 考古…这类冷门项兜底用）。
const int defaultSkillWeight = 2;

int _weightOf(Map<String, Object?> skill) {
  final id = jsStr(skill['id']);
  // 战斗组：斗殴比斧/链枷更常用
  if (id == 'fighting') {
    return jsStr(skill['sub']) == '斗殴' ? skillUseWeight[id]! : 4;
  }
  // 射击组：手枪 / 步枪优先
  if (id == 'firearms') {
    final sub = jsStr(skill['sub']);
    if (sub == '手枪') return skillUseWeight[id]!;
    if (sub.contains('步枪')) return 6;
    return 3;
  }
  return skillUseWeight[id] ?? defaultSkillWeight;
}

/// 武器对得上的技能排前面（1 = 闸门内，0 = 闸门外）
int _gateRank(Map<String, Object?> skill, Set<String> gate) =>
    gate.contains(jsStr(skill['key'])) ? 1 : 0;

/// 兴趣点分配：加权焦点 → 兜底，语言最多一门。
///
/// [combatGate] 是「武器对应的战斗技能」key 集合：不在闸门里的战斗技能不进
/// 候选池（带指虎却点射击（步枪）= 白扔点）。非战斗技能不受影响。
void _spendInterest(
  Character card,
  List<Map<String, Object?>> allSkills,
  JsRng rng, {
  Set<String>? combatGate,
}) {
  final gate = combatGate ?? const <String>{};
  final usable = allSkills.where((s) {
    final key = jsStr(s['key']);
    if (!isCombatSkillKey(key)) return true; // 非战斗技能一律放行
    return gate.isEmpty || gate.contains(key);
  }).toList();
  final candidates = interestCandidates(card, allSkills: usable, rng: rng);
  if (candidates.isEmpty) return;
  candidates.sort((a, b) {
    final g = _gateRank(b, gate).compareTo(_gateRank(a, gate));
    if (g != 0) return g;
    final w = _weightOf(b).compareTo(_weightOf(a));
    if (w != 0) return w;
    return jsStr(a['key']).compareTo(jsStr(b['key'])); // 平权时稳定排序
  });

  // 焦点：权重最高的前 6 项先把点数吃掉（集中才有个性）；
  // 用完后仍要满足「点数必须用完」，再向其余技能兜底。
  final focusCount = candidates.length < 6 ? candidates.length : 6;
  _spend(card, 'int', candidates.take(focusCount).toList());
  _spend(card, 'int', candidates);

  if (jsNum(interestPoints(card)['remain']) <= 0) return;
  /* 兜底 1：闸门内的技能全到顶了 —— 先把点摊到**非战斗**技能上。
     兜底 2：连非战斗技能都满了，才允许回到闸门外的战斗技能（否则
     「点数必须用完」这条硬约束会破功、界面直接挡住下一步）。
     正常卡不可能走到兜底 2：非战斗技能有 50+ 项。 */
  final nonCombat = allSkills
      .where((s) => !isCombatSkillKey(jsStr(s['key'])))
      .toList();
  _spend(card, 'int', interestCandidates(card, allSkills: nonCombat, rng: rng));
  if (jsNum(interestPoints(card)['remain']) > 0) {
    _spend(card, 'int', interestCandidates(card, allSkills: allSkills, rng: rng));
  }
}

/// 兴趣点的**候选技能池**（纯函数，给测试直接断言口径）。
///
/// 规则：
///   · 剔除 克苏鲁神话 / 信用评级（isGrowthOnly）与 母语（capExempt）；
///   · `其他语言` 是 flat 组（20 门语言各自一个实例），**只保留一门**，
///     否则一键分配会把兴趣点摊成「每门语言 5 点」。
List<Map<String, Object?>> interestCandidates(
  Character card, {
  List<Map<String, Object?>>? allSkills,
  JsRng? rng,
}) {
  final pool = allSkills ??
      card.skills
          .map(asMap)
          .where((s) => jsStr(s['id']) != 'custom')
          .where((s) => !isGrowthOnly(s['id']))
          .toList();
  final candidates = <Map<String, Object?>>[];
  final languages = <Map<String, Object?>>[];
  for (final s in pool) {
    final id = jsStr(s['id']);
    if (id == 'custom' || isGrowthOnly(id) || capExempt(id)) continue;
    if (id == 'language_other') {
      languages.add(s); // 单独收集，稍后只挑一门
      continue;
    }
    candidates.add(s);
  }
  if (languages.isNotEmpty) {
    final r = rng ?? nowRng;
    var idx = languages.length == 1 ? 0 : (r() * languages.length).floor();
    if (idx < 0) idx = 0;
    if (idx >= languages.length) idx = languages.length - 1;
    candidates.add(languages[idx]);
  }
  return candidates;
}

void _spend(
  Character card,
  String field,
  List<Map<String, Object?>> candidates,
) {
  if (candidates.isEmpty) return;
  var guard = 0;
  while (guard++ < 4000) {
    final pts = field == 'occ' ? occupationPoints(card) : interestPoints(card);
    final remain = jsNum(pts['remain']);
    if (remain <= 0) return;
    var progressed = false;
    for (final s in candidates) {
      final now = field == 'occ'
          ? occupationPoints(card)
          : interestPoints(card);
      final left = jsNum(now['remain']);
      if (left <= 0) return;
      final delta = left >= genStep ? genStep : left;
      final r = applyPoint(card, s, field, delta);
      if (jsTruthy(r['ok'])) progressed = true;
    }
    if (!progressed) return; // 全部触到上限 / 不可加点，剩下的分配不出去
  }
}

/// 让「额外分配的战斗技能」跟着武器走（需求 9）。
///
/// 为什么需要单独一步：向导里「职业技能」在「战斗装备」**之前**（旧版顺序），
/// 玩家常常先点「一键分配」再去挑武器 —— 不搬的话就会出现
/// 「带黄铜指虎却把兴趣点扔进射击（步枪）」的老问题。
///
/// 搬移口径：
///   · 目标：武器对应的战斗技能（没有武器 = 斗殴），缺实例先补上；
///   · 源：**非本职**战斗技能上的兴趣点 —— 兴趣点本来就是自由选择，
///     改主意不需要理由；
///   · **本职**战斗技能上的职业点一概不动 —— 那是职业设定，不是额外分配；
///   · 搬出来的点先喂目标技能，喂满后往非战斗技能兜底，保证「点数必须用完」。
///
/// 幂等：没有可搬的点时返回 0，一个字节都不改。
int alignCombatSkillsToWeapons(Character card) {
  final gate = requiredCombatSkillKeys(card);
  for (final key in gate) {
    _ensureSkillByKey(card, key);
  }
  final strays = card.skills
      .map(asMap)
      .where((s) => isCombatSkillKey(jsStr(s['key'])))
      .where((s) => !gate.contains(jsStr(s['key'])))
      .where((s) => !isOccSkill(card, s))
      .where((s) => jsNum(s['int']) > 0)
      .toList();
  if (strays.isEmpty) return 0;

  var moved = 0;
  for (final s in strays) {
    final pts = jsNum(s['int']);
    s['int'] = 0;
    recompute(s);
    moved += pts;
  }

  final targets = card.skills
      .map(asMap)
      .where((s) => gate.contains(jsStr(s['key'])))
      .toList();
  _spend(card, 'int', targets);
  if (jsNum(interestPoints(card)['remain']) > 0) {
    final nonCombat = card.skills
        .map(asMap)
        .where((s) => !isCombatSkillKey(jsStr(s['key'])))
        .toList();
    _spend(card, 'int', interestCandidates(card, allSkills: nonCombat));
  }
  if (jsNum(interestPoints(card)['remain']) > 0) {
    _spend(card, 'int', interestCandidates(card));
  }
  return moved;
}

/// 是否还有技能能继续吸收点数（用于「点数没花完」的文案与放行判断）
bool canAbsorbMore(Character card, String field) {
  final pts = field == 'occ' ? occupationPoints(card) : interestPoints(card);
  if (jsNum(pts['remain']) <= 0) return false;
  final candidates = field == 'occ'
      ? occupationalSet(card).keys
            .map((k) => find(card, k))
            .whereType<Map<String, Object?>>()
      : card.skills
            .map(asMap)
            .where((s) => jsStr(s['id']) != 'custom' && !isGrowthOnly(s['id']));
  for (final s in candidates) {
    if (jsNum(s['total']) < capOf(card, s)) return true;
  }
  return false;
}

/// 职业显示名
String occupationNameOf(Character card) {
  final occ = getOccupationById(card.occupationId);
  if (occ != null) return jsStr(occ['name']);
  return jsStr(card.basicInfo['occupationName']);
}

/// 年龄（字符串或数字）→ int，非法返回 0
int ageOf(Character card) => jsNum(card.basicInfo['age']);

/// 把一整年的年龄写回卡（顶层 age 与 basicInfo.age 必须同步 —— 原码 recalc 会再同步一次）
void setAge(Character card, Object? value) {
  card.basicInfo['age'] = value;
  card.raw['age'] = value;
}

/* ============================================================
 * 「天命 N 选一」（P7-E）
 *
 * 对齐旧版 `ui/steps-a.js:536-660` + `app.js:1233-1246`：
 *   fate = { n:2..10, rolled:bool, options:[{9 项属性}…], picked:int, rolledAt:int }
 *   · 一次掷出 N 组完整属性，**掷出后不可重掷**（要换只能新建卡）；
 *   · 选中写回 `c.attributes`（9 项，含幸运）+ `attributeMode='fate'`
 *     + `fate.picked=i`；
 *   · 每组显示 9 项属性与「总 X（不含幸运 Y）」。
 *
 * ★ 纯数据：全部落在 `card.raw['fate']`，widget 只负责画 ——
 *   刷新 / 重进向导不会丢（不带任何 widget state）。
 * ★ 随机源唯一：`genRandom()`（3D6×5 / (2D6+6)×5），不另造公式。
 *   逐项 assert 它是 5 的倍数且落在 [genMin, genMax]。
 * ★ 购点总上限只在 pointbuy 生效：fate 走 `checkAttributes(pointBuy:false)`，
 *   enforceCap=false，不会误套 460/540 的购点上界。
 * ============================================================ */

const int fateMinN = 2;
const int fateMaxN = 10;
const int fateDefaultN = 5;

/// 补齐 / 规整天命结构（幂等，与 normalize.dart 的口径一致）。
Map<String, Object?> ensureFate(Character card) {
  final raw = card.raw['fate'];
  if (raw is! Map) {
    card.raw['fate'] = <String, Object?>{
      'n': fateDefaultN,
      'rolled': false,
      'options': <Object?>[],
      'picked': -1,
      'rolledAt': 0,
    };
  }
  final f = asMap(card.raw['fate']);
  if (f['options'] is! List) f['options'] = <Object?>[];
  final n = jsParseInt(f['n']) ?? 0;
  f['n'] = isValidFateN(n) ? n : fateDefaultN;
  final picked = jsParseInt(f['picked']) ?? -1;
  final len = asList(f['options']).length;
  f['picked'] = (picked >= 0 && picked < len) ? picked : -1;
  f['rolled'] = jsTruthy(f['rolled']) && len > 0;
  f['rolledAt'] = jsNum(f['rolledAt']);
  return f;
}

bool isValidFateN(int n) => n >= fateMinN && n <= fateMaxN;

int fateN(Character card) =>
    jsParseInt(ensureFate(card)['n']) ?? fateDefaultN;

bool fateRolled(Character card) => jsTruthy(ensureFate(card)['rolled']);

int fatePicked(Character card) =>
    jsParseInt(ensureFate(card)['picked']) ?? -1;

List<Map<String, Object?>> fateOptions(Character card) =>
    asList(ensureFate(card)['options']).map(asMap).toList();

/// 一组的合计（含 / 不含幸运两种口径）。
int fateOptionSum(Map<String, Object?> opt, {required bool withLuck}) {
  var s = 0;
  for (final k in withLuck ? allAttrKeys : coreAttrKeys) {
    s += jsNum(opt[k]);
  }
  return s;
}

/// 掷出 N 组天命。已掷出 / N 非法 → false（一个字节都不改）。
bool rollFate(Character card, int n) {
  final f = ensureFate(card);
  if (jsTruthy(f['rolled'])) return false;
  if (!isValidFateN(n)) return false;
  final options = <Object?>[];
  for (var i = 0; i < n; i++) {
    final g = genRandom();
    assert(
      g.values.every(
        (int v) => v % genStep == 0 && v >= genMin && v <= genMax,
      ),
      '天命属性必须来自 genRandom()：5 的倍数且落在 $genMin-$genMax',
    );
    options.add(<String, Object?>{
      for (final e in g.entries) e.key: e.value,
    });
  }
  f['n'] = n;
  f['options'] = options;
  f['picked'] = -1;
  f['rolled'] = true;
  f['rolledAt'] = nowMillis();
  card.raw['attributeMode'] = 'fate';
  return true;
}

/// 选定第 [i] 组：写回 9 项属性 + 下标 + 模式。越界 / 没掷出 → false。
bool pickFate(Character card, int i) {
  final f = ensureFate(card);
  if (!jsTruthy(f['rolled'])) return false;
  final opts = asList(f['options']);
  if (i < 0 || i >= opts.length) return false;
  final opt = asMap(opts[i]);
  for (final k in allAttrKeys) {
    if (opt[k] != null) card.attributes[k] = opt[k];
  }
  f['picked'] = i;
  card.raw['attributeMode'] = 'fate';
  return true;
}

/* ============================================================
 * 教育进步检定（建卡期，CoC 7e · **次数由年龄决定**）
 *
 * 规则：掷 1D100，**严格大于**当前 EDU 才进步，EDU +1D10（上限 99）；
 *      一个角色能做的**次数** = [eduCheckAllowance]（年龄）——
 *      20–39 岁 1 次、40–49 岁 2 次、50–59 岁 3 次、60 岁以上 4 次
 *      （15–19 岁见 domain 里那张表的偏差说明）。
 *      ⚠️ 是「可以做 N 次**检定**」，不是「N 次成功」—— 失败也算用掉一次。
 *      次数用完就不能再掷（避免刷点）。判定本体是 domain 的纯函数
 *      [eduCheck]，这里只负责「掷骰 → 追加进 eduProgress.log → 重算」。
 *
 * ★ 为什么增益落在 `eduProgress.bonus` 而不是直接改 `attributes.edu`：
 *   这是本工程既有的、有测试兜住的设计（见 character.dart 的字段注释、
 *   rules_coc7.dart#ageAdjust、engine.dart#dropStaleEduChecks）——
 *     · 原始 EDU 是玩家「买」来的值，购点上限校验（460/540）只认它；
 *       直接把增益写进去，会让合法的卡忽然被判「超出上限」。
 *     · 年龄修正同样是「只作用于生效值」，EDU 增益跟它走同一条路，
 *       界面（概要页 `原始 → 生效`、角色卡、母语技能基础值、
 *       职业技能点）读的全是**生效值**，所以增益是真的生效了。
 *   `recalc()` 会把「原始 EDU 变过」的旧检定作废（防止旧增益抬着新教育），
 *   所以本文件写日志时必须记下 `baseEdu`。
 *
 * ★ 幂等：次数用完后 [runEduCheck] 返回 null 且一个字节都不改。
 *   这是「不能重掷」的落点 —— 由数据（`eduProgress.log` 的行数 vs 年龄允许的次数）
 *   判定，不依赖 widget state，所以退出向导再回来也不会多掷。
 * ============================================================ */

/// 补齐 / 规整教育进步检定的数据结构（幂等，与 normalize.dart 口径一致）
Map<String, Object?> ensureEduProgress(Character card) {
  final raw = card.raw['eduProgress'];
  if (raw is! Map) {
    card.raw['eduProgress'] = <String, Object?>{
      'base': null,
      'done': 0,
      'log': <Object?>[],
      'bonus': 0,
    };
  }
  final p = asMap(card.raw['eduProgress']);
  if (p['log'] is! List) p['log'] = <Object?>[];
  final log = asList(p['log']);
  p['done'] = log.length;
  var bonus = 0;
  for (final row in log) {
    bonus += jsNum(asMap(row)['gain']);
  }
  p['bonus'] = bonus;
  return p;
}

/// 这个年龄允许做几次教育进步检定。
///
/// 未填 / 非法年龄（0、负数、空串）按引擎的默认 25 岁处理
/// （`rules_coc7.dart#ageAdjust` 对 0 岁也是这么兜的），
/// 免得一张还没填年龄的半成品卡突然一次都不能检定。
int eduCheckAllowanceOf(Character card) {
  final age = jsNum(card.basicInfo['age']);
  return eduCheckAllowance(age > 0 ? age : 25);
}

/// **已经用掉**几次教育进步检定 = `eduProgress.log` 的行数。
///
/// 每次掷骰（无论成功失败）都追加一行，所以行数就是「做过的次数」。
int eduChecksUsed(Character card) =>
    asList(ensureEduProgress(card)['log']).length;

/// **还剩**几次教育进步检定（不会小于 0）。
///
/// 玩家中途把年龄改小（例如 60 岁做了 3 次又改回 30 岁）时会出现
/// 「已用 > 允许」，这里夹到 0 —— 剩下的次数只会是 0，不会变成负数。
int eduChecksRemaining(Character card) {
  final left = eduCheckAllowanceOf(card) - eduChecksUsed(card);
  return left < 0 ? 0 : left;
}

/// 教育进步检定是否**已经做完**（允许的次数全部用掉）。
///
/// P11 之前它的含义是「做过一次」；现在改成「次数用完了」，
/// 语义对齐 [eduChecksRemaining] == 0，调用点（未检定提示 / 按钮禁用）不用改。
bool eduChecked(Character card) => eduChecksRemaining(card) <= 0;

/// 检定用的「当前 EDU」：**生效值**（含年龄调整与此前增益），封顶 99。
///
/// 与界面「原始 EDU」不同 —— 检定要跟角色卡上真正生效的教育比大小，
/// 否则 40 岁以后年龄修正的场景会对不上；多次检定也必须逐次累加，
/// 所以第二次比的也是「上一次涨完之后」的教育。
int eduForCheck(Character card) {
  final eff = jsNum(effectiveAttrs(card)['edu']);
  return eff > eduCap ? eduCap : eff;
}

/// 做一次教育进步检定。
///
/// - 剩余次数为 0 → 返回 null（幂等，不累加、不消耗随机数）
/// - [rng] 可注入（测试用固定序列断言掷出的值）
/// - 每次掷骰都**追加一行** `eduProgress.log`（失败也追加 —— 失败同样用掉一次），
///   并刷新 `bonus` / `done` / `baseEdu`，
///   再跑 [recalc] + [syncSkills]，让生效 EDU、母语基础值、
///   职业技能点、闪避等全部跟着更新（走的是既有属性写入路径）
///
/// 返回 `{roll, before, gain, after, success, used, remaining}`，
/// 界面据此写结果文案与剩余次数。
Map<String, Object?>? runEduCheck(Character card, {JsRng? rng}) {
  if (eduChecksRemaining(card) <= 0) return null;
  final p = ensureEduProgress(card);
  final before = eduForCheck(card);
  // 掷骰顺序与 rules_coc7.dart#eduImproveCheck 一致：先 1D100，进步了才 1D10
  final d100 = roll(1, 100, rng);
  final d10 = d100 > before ? roll(1, 10, rng) : 0;
  final res = eduCheck(before, d100, d10);

  final log = asList(p['log']);
  log.add(<String, Object?>{
    'n': log.length + 1,
    'roll': res.roll,
    'd10': d10,
    'before': res.before,
    'gain': res.gain,
    'after': res.after,
  });
  p['log'] = log;
  p['done'] = log.length;
  var bonus = 0;
  for (final row in log) {
    bonus += jsNum(asMap(row)['gain']);
  }
  p['bonus'] = bonus;
  /* 基准 = 玩家输入的原始 EDU：engine.dart#dropStaleEduChecks 靠它判断
     「原始教育改了没有」，对不上就把这次检定作废（防止旧增益抬着新教育）。 */
  p['baseEdu'] = jsNum(card.attributes['edu']);

  recalc(card);
  syncSkills(card);

  return <String, Object?>{
    'roll': res.roll,
    'before': res.before,
    'gain': res.gain,
    'after': res.after,
    'success': res.success,
    // 第几次 / 还剩几次：界面写「第 2 次检定：…（还可检定 1 次）」
    'n': log.length,
    'used': log.length,
    'remaining': eduChecksRemaining(card),
  };
}

/// 检定结果文案（界面与测试共用一份，避免两处措辞漂移）
///
/// 成功：`掷出 63 > 教育 55 → 教育 +7，现为 62`
/// 封顶：`掷出 100 > 教育 95 → 教育 +4（上限 99），现为 99`
/// 失败：`掷出 12 ≤ 教育 55 → 没有进步，教育保持 55`
String eduCheckText(Map<String, Object?>? row) {
  if (row == null) return '';
  final roll = jsNum(row['roll']);
  final before = jsNum(row['before']);
  final gain = jsNum(row['gain']);
  final after = jsNum(row['after']);
  if (roll <= before || gain <= 0 && after == before) {
    return '掷出 $roll ≤ 教育 $before → 没有进步，教育保持 $before';
  }
  // 封顶：掷出的 1D10 比实际加到的点数大 → 是被 99 挡住的那部分
  final d10 = jsNum(row['d10']);
  final capped = after >= eduCap && d10 > gain;
  final tail = capped ? '（上限 $eduCap）' : '';
  return '掷出 $roll > 教育 $before → 教育 +$gain$tail，现为 $after';
}
