// ============================================================
// engine.dart — 角色数据重算调度
// 逐行对应 `core/engine.js`（287 行，`Engine`）
//
//   任何原始数据变化后调用 recalc()，保证派生数据始终一致
// ============================================================

import 'character.dart';
import 'js_compat.dart';
import 'occupation.dart';
import 'rules_coc7.dart';
import 'skillmodel.dart';

/* 缓存指纹用的「规则版本」。开发期规则一改就 +1，
   改了 ageAdjust 的算法却忘了清缓存时，这个数字会兜住。 */
const int coc7RuleSig = 4; // 4: 原始 EDU 变化时作废旧的教育进步检定

Character recalc(Character character) {
  final a = character.attributes;

  // 同步基本信息顶层字段
  character.raw['age'] = character.basicInfo['age'];

  /* ---------- 教育进步检定的基准守卫 ----------
   * 检定的前提是「掷数 ≤ 当时的 EDU」。原始教育一旦变了，
   * 之前那几次检定的判定条件就不成立了，旧的增益必须作废 ——
   * 否则 eduBonus 会继续加在**新**教育上，生效教育被旧增益抬着，
   * 表现为「改了教育还是套用之前的检定结果」。
   *
   * ⚠️ 这段必须放在 recalc 里（数据层），不能只放在界面层：
   * 改属性的路径太多（手动输入 / 随机接受 / 天命选定 / 预设方案 /
   * 外部直接赋值），界面上逐个补总会漏 —— 之前两版就是漏在
   * 「随机接受」和「天命选定」这两条不走 commit() 的路径上。
   * recalc 是所有变更的唯一必经之地，守在这里就一次都不会漏。 */
  dropStaleEduChecks(character);

  // 0) 年龄调整：算出「生效属性」，后续派生属性 / 技能基础值 / 界面全部用它。
  //    原始属性保持玩家输入值不变（购点校验、掷骰结果都依赖它）。
  //    教育进步检定的增益（eduBonus）也只落在生效值上。
  final adj = ageAdjust(<String, Object?>{
    'str': a['str'],
    'con': a['con'],
    'siz': a['siz'],
    'dex': a['dex'],
    'app': a['app'],
    'int': a['int'],
    'pow': a['pow'],
    'edu': a['edu'],
    'luck': a['luck'],
    'age': character.basicInfo['age'],
    'eduBonus': eduBonusOf(character),
  });
  character.raw['ageAdj'] = adj;
  character.raw['effAttributes'] = adj['eff'];
  /* 同步缓存指纹：否则 effAttrs/ageAdjustOf 会因为「指纹对不上」
     而重新算一遍（结果一样，只是白费一次），更重要的是保证
     之后任何一侧改数据都能被正确判定为失效。 */
  final sig = attrSig(character);
  character.raw['_effSig'] = sig;
  character.raw['_adjSig'] = sig;

  // 1) 派生属性（内部同样按调整后的属性计算）
  final d = derived(<String, Object?>{
    'str': a['str'],
    'con': a['con'],
    'siz': a['siz'],
    'dex': a['dex'],
    'app': a['app'],
    'int': a['int'],
    'pow': a['pow'],
    'edu': a['edu'],
    'age': character.basicInfo['age'],
  });
  character.raw['derivedStats'] = d;

  // 2) 技能基础值随属性变化（母语=EDU，闪避=DEX/2）
  for (final sRaw in character.skills) {
    final s = asMap(sRaw);
    if (jsTruthy(s['custom'])) continue;
    final nb = baseValue(character, jsStr(s['id']), jsStr(s['sub']));
    if (!(s['base'] is num && s['base'] == nb)) {
      s['base'] = nb;
      recompute(s);
    }
  }

  // 3) 理智上限 = 意志（POW，取自生效属性）。
  //    另外单独记下「99 − 克苏鲁神话」的硬性削减值：它只作为提示信息，
  //    不再用来夹当前理智 —— 当前理智允许暂时高于上限。
  Map<String, Object?>? cth;
  for (final sRaw in character.skills) {
    final s = asMap(sRaw);
    if (jsStr(s['id']) == 'cthulhu') {
      cth = s;
      break;
    }
  }
  final cthVal = cth != null ? jsNum(cth['total']) : 0;
  final mSan = maxSan(cthVal);
  character.raw['sanMythosCap'] = mSan;

  // 4) 状态值：属性齐备后才做首次初始化；之前不锁定，避免把空属性当基准
  final st = character.status;

  /* 理智上限 = 意志（POW）− 累计的永久减损。
     施放神话法术、与克苏鲁神话生物接触都可能让调查员「永久失去一部分 SAN 上限」
     （规则书里是 -1D5 / -1D10）。这个减损必须与「当前 SAN」分开存：
       baseMaxSAN —— 未减损时的上限（跟着意志走）
       sanLoss    —— 累计减损，玩家在状态管理里手动加/减
     maxSAN 只是这两者的差，是**展示用**的派生值。 */
  final baseMaxSan = character.raw['baseMaxSAN'];
  if (baseMaxSan == null) {
    character.raw['baseMaxSAN'] = d['maxSAN'];
  }
  if (!jsTruthy(character.raw['sanLoss'])) character.raw['sanLoss'] = 0;
  final sanLoss = clamp(character.raw['sanLoss'], 0, 99);
  character.raw['sanLoss'] = sanLoss;
  final effMaxSan = jsMax(<int>[0, jsNum(d['maxSAN']) - sanLoss]);

  st['maxHP'] = d['maxHP'];
  st['maxMP'] = d['maxMP'];
  st['maxSAN'] = effMaxSan; // 生效上限 = 意志 − 永久减损
  st['baseMaxSAN'] = d['maxSAN']; // 减损前的上限，界面上要一起显示
  st['sanLoss'] = sanLoss;

  final ready = jsNum(d['maxHP']) > 0 && jsNum(d['maxMP']) > 0;
  if (ready && !jsTruthy(st['_inited'])) {
    // 首次有效初始化：HP/MP 取满值，SAN 初始值 = POW（规则书：意志=初始理智）
    st['currentHP'] = d['maxHP'];
    st['currentMP'] = d['maxMP'];
    st['currentSAN'] = d['san'];
    st['currentLuck'] = jsNum(a['luck']);
    st['_inited'] = true;
  } else if (!ready) {
    // 属性尚未填好，仅清空占位，不标记已初始化
    if (!jsTruthy(st['currentHP'])) st['currentHP'] = 0;
    if (!jsTruthy(st['currentMP'])) st['currentMP'] = 0;
    if (!jsTruthy(st['currentSAN'])) st['currentSAN'] = 0;
  } else {
    st['currentHP'] = clamp(st['currentHP'], 0, jsNum(d['maxHP']));
    st['currentMP'] = clamp(st['currentMP'], 0, jsNum(d['maxMP']));
    /* v2.1.5（用户第 1 项）：当前理智**不得超过上限**（意志 − 永久减损）。
       旧实现只夹 0-99（允许突破上限），于是出现「SAN 60/59」这类当前值高于
       上限的矛盾显示。上限归零时当前 SAN 也随之归零。 */
    st['currentSAN'] = clamp(st['currentSAN'], 0, effMaxSan);
    st['currentLuck'] = clamp(st['currentLuck'], 0, 99);
  }

  // 幸运：只要玩家没有在状态栏手动改过，就跟随幸运属性
  if (!jsTruthy(st['_luckTouched'])) {
    st['currentLuck'] = clamp(jsNum(a['luck']), 0, 99);
  }
  // 属性后填的情况：补一次初始化（未手动改动过才补）
  if (ready && jsNum(st['currentHP']) == 0 && !jsTruthy(st['_hpTouched'])) st['currentHP'] = d['maxHP'];
  if (ready && jsNum(st['currentMP']) == 0 && !jsTruthy(st['_mpTouched'])) st['currentMP'] = d['maxMP'];
  if (ready && jsNum(st['currentSAN']) == 0 && !jsTruthy(st['_sanTouched'])) st['currentSAN'] = d['san'];

  return character;
}

int clamp(Object? v, int lo, int hi) {
  final n = jsParseInt(v);
  final x = n ?? lo;
  return jsMax(<int>[
    lo,
    jsMin(<int>[hi, x]),
  ]);
}

/// 所有属性是否已填写
bool attrsReady(Character character) {
  final a = character.attributes;
  for (final k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
  ]) {
    final v = jsParseInt(a[k]);
    if (v == null || v <= 0) return false;
  }
  return true;
}

/// 取角色当前「生效属性」（已含年龄调整）。
///
/// ⚠️ 缓存必须带「失效标记」而不是无条件短路。
/// 早先写成 `if (character.effAttributes) return character.effAttributes;`，
/// 只要算过一次就永远返回旧值 —— 于是：
///   · 改了原始属性但没跑 recalc 时，界面显示的还是上一轮的数字
///   · 清掉 eduProgress.bonus（教育进步检定作废）之后，
///     Engine.effAttrs() 仍然返回带旧增益的结果，
///     表现为「改了教育还是套用之前的检定结果」。
/// 现在改成：只要检测到「缓存是旧输入算出来的」就重算。
/// 输入很便宜（一次 ageAdjust），换来的是永远拿最新值，不会再有幽灵缓存。
Map<String, Object?> effAttrs(Character character) {
  final sig = attrSig(character);
  final cached = character.raw['effAttributes'];
  if (character.raw.containsKey('_effSig') &&
      character.raw['_effSig'] == sig &&
      cached != null) {
    return asMap(cached);
  }
  final a = <String, Object?>{...character.attributes};
  a['age'] = character.basicInfo['age'];
  a['eduBonus'] = eduBonusOf(character);
  final eff = asMap(ageAdjust(a)['eff']);
  character.raw['_effSig'] = sig;
  return eff;
}

/// 缓存指纹：原始属性 + 年龄 + 教育增益 + 规则版本
String attrSig(Character character) {
  final at = character.attributes;
  final bi = character.basicInfo;
  return <String>[
    _sig(at['str']),
    _sig(at['con']),
    _sig(at['siz']),
    _sig(at['dex']),
    _sig(at['app']),
    _sig(at['int']),
    _sig(at['pow']),
    _sig(at['edu']),
    _sig(at['luck']),
    _sig(bi['age']),
    _sig(eduBonusOf(character)),
    _sig(coc7RuleSig),
  ].join('|');
}

/// JS 数组 join 里 undefined / null 都会变成空串，这里保持一致
String _sig(Object? v) => (v == null) ? '' : jsStr(v);

/// 原始 EDU 变了就把旧的教育进步检定**彻底作废**。
/// 由 recalc 调用，所以无论从哪条路径改属性都会走到这里。
/// @returns 是否真的作废过（界面据此显示一次提示）
bool dropStaleEduChecks(Character character) {
  final p = character.raw['eduProgress'];
  if (p is! Map) return false;
  final log = p['log'];
  if (!isArray(log) || asList(log).isEmpty) return false;
  final rawEdu = jsNum(character.attributes['edu']);

  /* 从来没有基准记录（老存档 / 外部构造的数据）：
     这不是「教育值变了导致检定过期」，而是「没记基准」。
     此时只补记基准、保留检定结果 —— 否则会误清掉合法的历史数据。
     判据是「log 里第一条记录的 before 就是当前 EDU」，说明它本来就是按这个值掷的。 */
  final baseEdu = p['baseEdu'];
  if (baseEdu == null) {
    final firstBefore = jsParseInt(asMap(asList(log).first)['before']);
    if (firstBefore != null && firstBefore == rawEdu) {
      p['baseEdu'] = rawEdu; // 补记基准，不作废
      return false;
    }
    /* 兜底：基准与首条记录都对不上 → 确实无法判定，按过期处理 */
  } else if (baseEdu == rawEdu) {
    // JS 用严格相等：数字与字符串不相等。Dart 的 == 在「数字 / 字符串」之间
    // 同样返回 false，只有 25 与 25.0 这种同为数字的情况会相等 —— 与 JS 一致。
    return false;
  }

  p['log'] = <Object?>[];
  p['bonus'] = 0;
  p['done'] = 0;
  p['staleFromEdu'] = baseEdu;
  p['baseEdu'] = rawEdu;
  p['resetAt'] = nowMillis(); // 供界面显示一次「检定已清空」的说明
  return true;
}

/// 取年龄调整摘要（同样带指纹校验）
Map<String, Object?> ageAdjustOf(Character character) {
  final sig = attrSig(character);
  final cached = character.raw['ageAdj'];
  if (character.raw.containsKey('_adjSig') &&
      character.raw['_adjSig'] == sig &&
      cached != null) {
    return asMap(cached);
  }
  final a = <String, Object?>{...character.attributes};
  a['age'] = character.basicInfo['age'];
  a['eduBonus'] = eduBonusOf(character);
  final adj = ageAdjust(a);
  character.raw['_adjSig'] = sig;
  return adj;
}

/// 属性原始值之和（9 项）；includeLuck=false 时不计幸运
int attrSum(Character character, {bool includeLuck = true}) {
  final a = character.attributes;
  final keys = <String>['str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu'];
  if (includeLuck) keys.add('luck');
  var t = 0;
  for (final k in keys) {
    t += jsNum(a[k]);
  }
  return t;
}

/// 属性生效值之和（9 项，含年龄调整）；includeLuck=false 时不计幸运
int attrSumEff(Character character, {bool includeLuck = true}) {
  final e = effAttrs(character);
  final keys = <String>['str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu'];
  if (includeLuck) keys.add('luck');
  var t = 0;
  for (final k in keys) {
    t += jsNum(e[k]);
  }
  return t;
}

/// 统一校验：返回问题列表
List<Map<String, Object?>> validate(Character character) {
  var errs = <Map<String, Object?>>[];
  errs = errs + validateBasicInfo(character);
  errs = errs + validateOccupationSelected(character);
  if (attrsReady(character)) {
    errs = errs + validateAttributes(character);
    errs = errs + validateOccupationChoices(character);
    errs = errs + validateSkillPoints(character);
    errs = errs + validateSkillCap(character);
    errs = errs + validateCreditRating(character);
  }
  return errs;
}

/// 校验项清单（含通过项，用于"完成角色卡"检查页）
List<Map<String, Object?>> checkList(Character character) {
  final out = <Map<String, Object?>>[];

  void add(String label, List<Map<String, Object?>> errs, int step) {
    out.add(<String, Object?>{
      'label': label,
      'ok': errs.isEmpty,
      'step': step,
      'detail': errs.isNotEmpty ? errs.first['text'] : '',
      'errors': errs,
    });
  }

  List<Map<String, Object?>> byTarget(String target) =>
      validateBasicInfo(character).where((e) => e['target'] == target).toList();

  add('角色姓名已填写', byTarget('characterName'), 0);
  add('玩家名称已填写', byTarget('playerName'), 0);
  add('年龄合法', byTarget('age'), 0);
  add('属性合法（15-90 且为 5 的倍数）', validateAttributes(character), 1);
  add('已选择职业', validateOccupationSelected(character), 2);
  add('职业限定技能选择完成', validateOccupationChoices(character), 2);
  add('信用评级在职业范围内', validateCreditRating(character), 3);
  add(
    '职业技能点未超额',
    validateSkillPoints(character)
        .where((e) => e['target'] == 'occPoints')
        .toList(),
    4,
  );
  add(
    '兴趣技能点未超额',
    validateSkillPoints(character)
        .where((e) => e['target'] == 'interestPoints')
        .toList(),
    4,
  );
  add('技能未超过上限', validateSkillCap(character), 4);
  return out;
}
