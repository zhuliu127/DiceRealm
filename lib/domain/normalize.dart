// ============================================================
// normalize.dart — `core/store.js#normalize()` 的幂等字段迁移
//
// 角色卡**没有 schema 版本号**，结构演进全靠这里的**幂等字段探测**。
// 移植时原样保留这个策略，不要发明 schemaVersion。
//
// ⚠️ 幂等性是硬要求：normalize() 会被 listCharacters / beginEdit /
//   commitEdit / importCharacter / savePreset / upsertCharacter 反复调用。
//   第二遍跑必须**不产生任何变化**（测试里有 property-based 断言）。
//
// ⚠️ 执行顺序不能改：迁移必须在「补默认值」之前做（否则会被 base 的 99 覆盖），
//   背景症状入结构化的迁移必须在最后（此时 background / madness 都已补过默认值）。
// ============================================================

import 'character.dart';
import 'js_compat.dart';
import 'madness.dart' as madness;
import 'madness_state.dart' as mental_state;
import 'rules_coc7.dart' show mentalNormal, mentalPermanent, mentalSymptom;

/// 精神状态数组的收敛（丢「昏迷」/ 翻译老「潜在疯狂」/ 互斥）。
/// 统一走 madness_state 的纯函数，本文件不另写一套 if。
List<Object?> msNormalized(List<Object?> raw) =>
    mental_state.normalizeMentalList(raw).cast<Object?>();

/* v2.10.0（身体状态模型）：HP → 身体状态的**归位判据**（纯函数，仅用于老卡迁移）。
   ⚠️ 房间侧 room-model.js#bodyForHp 为**老卡迁移专用**；治愈伤势 healWound / 队友
   施救 aidApply 另用 v2.8.0 F3 冻结的 2 值判据（hp>=maxHP ? '正常' : '轻伤'），勿混用。
   这里是单机车卡侧的独立实现，与房间侧语义一致（本侧多一层 parseInt/isFinite 强制化）：
     · maxHP > 0 且 hp >= maxHP     → '正常'（满血）
     · maxHP > 0 且 hp * 2 >= maxHP → '重伤'（至多一半血）
     · 其余（含 maxHP 未知 / 为 0） → '轻伤' */
String bodyForHp(Object? hp, Object? maxHP) {
  final h = jsParseInt(hp) ?? 0;
  final m = jsParseInt(maxHP) ?? 0;
  if (m > 0 && h >= m) return '正常';
  if (m > 0 && h * 2 >= m) return '重伤';
  return '轻伤';
}

/// 修复/补全旧数据结构（幂等）
Character normalize(Character c) {
  // 对应 `newCharacter(c.ruleSystemId)`：undefined/空 → 'coc7'（见 character.dart）
  final rsRaw = c.raw['ruleSystemId'];
  final base = newCharacter(rsRaw == null ? null : jsStr(rsRaw));

  /* 迁移要放在「补默认值」之前做，否则会被 base 的 99 覆盖掉。
     旧版本只有一个 skillCap，现在拆成本职 / 兴趣两类。 */
  final legacyCap = jsParseInt(c.raw['skillCap']) ?? 0;
  final hasSplit =
      c.raw['skillCapOcc'] != null || c.raw['skillCapInterest'] != null;
  if (!hasSplit && legacyCap > 0) {
    c.raw['skillCapOcc'] = legacyCap;
    c.raw['skillCapInterest'] = legacyCap;
  }
  // 购点上限从没写过值的老卡：补一个真实初值，别让校验按 0 算
  final pbCap = c.raw['pbCap'];
  if (pbCap == null || pbCap == '') c.raw['pbCap'] = 480;

  base.forEach((k, v) {
    if (c.raw[k] == null) c.raw[k] = v;
  });

  if (c.raw['eduProgress'] is! Map) {
    c.raw['eduProgress'] = <String, Object?>{
      'base': null,
      'done': 0,
      'log': <Object?>[],
      'bonus': 0,
    };
  }
  final edu = c.eduProgress;
  if (!isArray(edu['log'])) edu['log'] = <Object?>[];
  if (edu['bonus'] == null) {
    // 兼容只有 log 的老数据
    var sum = 0;
    for (final r in asList(edu['log'])) {
      sum += jsNum(asMap(r)['gain']);
    }
    edu['bonus'] = sum;
  }
  edu['done'] = asList(edu['log']).length;

  // 天命 N 选一：老数据没有这个字段，补一份空状态（不能是 undefined，
  // 否则「已掷出」判定和 options 遍历都会炸）
  if (c.raw['fate'] is! Map) {
    c.raw['fate'] = <String, Object?>{
      'n': 5,
      'rolled': false,
      'options': <Object?>[],
      'picked': -1,
      'rolledAt': 0,
    };
  }
  final fate = c.fate;
  if (!isArray(fate['options'])) fate['options'] = <Object?>[];
  final fn = jsParseInt(fate['n']) ?? 0;
  fate['n'] = (fn >= 2 && fn <= 10) ? fn : 5;
  final fp = jsParseInt(fate['picked']) ?? -1;
  fate['picked'] = (fp >= 0 && fp < asList(fate['options']).length) ? fp : -1;
  fate['rolled'] =
      jsTruthy(fate['rolled']) && asList(fate['options']).isNotEmpty;

  for (final k in <String>[
    'basicInfo',
    'attributes',
    'status',
    'assets',
    'background',
    'mythos',
  ]) {
    c.raw[k] = _jsObjectAssign(asMap(base[k]), c.raw[k]);
  }
  for (final k in <String>[
    'skills',
    'weapons',
    'armors',
    'vehicles',
    'items',
    'history',
    'companions',
    'changeLog',
  ]) {
    if (!isArray(c.raw[k])) c.raw[k] = <Object?>[];
  }
  if (!jsTruthy(c.raw['occupationPicks'])) c.raw['occupationPicks'] = <String, Object?>{};

  // 已保存过的角色：状态值必须锁定，不能因为缺少标记而重新初始化
  final st = c.status;
  final anyStatus =
      jsTruthy(st['currentHP']) ||
      jsTruthy(st['currentMP']) ||
      jsTruthy(st['currentSAN']) ||
      jsTruthy(st['currentLuck']);
  if (anyStatus || jsNum(c.derivedStats['maxHP']) > 0) {
    st['_inited'] = true;
    // 幸运跟随标记：历史数据没有该标记时视为未手动改过
    if (st['_luckTouched'] == null) st['_luckTouched'] = false;
  }
  // 同步 age
  c.raw['age'] = c.basicInfo['age'];

  /* 精神状态：老卡是**单选字符串**（'正常' / '临时疯狂'…），
     现在改成**多选数组**（一个人可以同时有永久疯狂 + 临时疯狂）。
     这里做一次性迁移：字符串 → [字符串]；空 → ['正常']。
     必须幂等 —— 已经是数组就不再动。

     P8（用户第 6/7 项）：取值收敛交给 `madness_state.dart` ——
       · 丢掉「昏迷」（昏迷是身体状态，见下面的 dying / unconscious）；
       · 老值「不定疯狂（症状消失）」翻译成「潜在疯狂」；
       · 「不定疯狂」与「潜在疯狂」互斥。 */
  final ms = st['mental'];
  if (ms == null || ms == '') {
    st['mental'] = <Object?>[mentalNormal];
  } else if (!isArray(ms)) {
    st['mental'] = msNormalized(<Object?>[ms]);
  } else {
    st['mental'] = msNormalized(asList(ms));
  }

  /* v2.10.0（身体状态模型）：老卡身体状态迁移（幂等）。
     旧模型里「濒死 / 昏迷」是 body 的单选值；新模型把二者改为布尔标记：
       · body='濒死' → body='重伤' + dying=true
       · body='昏迷' → unconscious=true，body 按 HP 归位（bodyForHp）
     迁移后 body 只可能是 {正常, 轻伤, 重伤, 死亡}，第二遍跑不再命中 → 不漂移。
     ⚠️ 撕卡判据不变：仍只认 body === '死亡'（app.js#isRippedCard）。 */
  if (st['body'] == '濒死') {
    st['body'] = '重伤';
    st['dying'] = true;
  } else if (st['body'] == '昏迷') {
    st['unconscious'] = true;
    st['body'] = bodyForHp(st['currentHP'], st['maxHP']);
  }
  /* 标记位一律收敛为布尔：缺键时上面 Object.assign 已补 false，
     显式写成 undefined / null 的脏数据也在这里兜底（UI 读出来不能是 undefined）。 */
  st['dying'] = jsTruthy(st['dying']);
  st['unconscious'] = jsTruthy(st['unconscious']);

  /* 背景里的「恐惧症 / 狂躁症」老卡只有文本、没有结构化数组，
     这里做一次性迁移把它们补进 madness（永久疯狂）。幂等，重复跑不会重复加。
     放在最后：此时 background / madness 都已补过默认值。 */
  madness.fromBackground(c);

  /* v2.1.5（用户第 1 项）：「疯狂症状」精神状态的**派生同步**。

     P8（用户第 7 项）改口径：「疯狂症状」**只标记背景疯狂表选出的症状**
     （含 AI 车卡 / 随机出卡，它们与手动选表走同一条 preset 路径）。
     跑团里临时 / 不定疯狂发作获得的症状**不再**派生这个标记 ——
     它是「作为背景的疯狂症的永久标记」，和游戏内状态没有联动。
        · 角色持有**背景 / 永久症状**（madness 里有 bg===true 或 permanent===true 的条目）
          → 强制勾选「疯狂症状」，并**移除**「正常」（二者互斥）；
        · 「永久疯狂」互斥规则**优先**（有永久疯狂时仍只留它一项）；
        · 没有任何背景症状 → 摘掉「疯狂症状」，空了回落 ['正常']。 */
  final sym = mentalSymptom;
  final madList = madness.list(c);
  final mentalNow = asList(st['mental']);
  final hasPermanent = mentalNow.contains(mentalPermanent);
  /* 背景 / 永久症状：带 bg 标记，或 permanent（兼容更老的数据，见 madness.dart#make）。
     P8（需求 7）：背景文本里带疯狂表标记（【恐惧症】/【狂躁症】/【疯狂发作】）
     也算「从疯狂表选了疯狂状态」—— 随机出卡 8/10 是「疯狂发作」，
     它不会进 100 条恐惧症 / 狂躁症子表，只存在于背景文本里。 */
  final bgText = jsStr(c.background['phobias']);
  final hasBgMadnessText =
      RegExp(r'【(恐惧症|狂躁症|疯狂发作)】').hasMatch(bgText);
  final hasPermSymptom = hasBgMadnessText ||
      madList.any((x) {
        final m = asMap(x);
        return m['bg'] == true || m['permanent'] == true;
      });
  if (hasPermanent) {
    /* 「永久疯狂」是撕卡级互斥项：保持只留它一项，不加派生项。 */
    st['mental'] = <Object?>[mentalPermanent];
  } else if (hasPermSymptom) {
    /* 背景 / 永久症状 → 一定是「疯狂症状」，且与「正常」互斥。 */
    st['mental'] = <Object?>[
      ...mental_state.withBackgroundSymptom(mentalNow),
    ];
  } else {
    final without = mentalNow.where((x) => x != sym).toList();
    st['mental'] = msNormalized(without);
  }
  return c;
}

/// 还原 `Object.assign({}, base, extra)` 的**完整**语义（含 JS 的怪癖）。
///
/// ⚠️ 这不是多余的工程化：`normalize()` 里这一句是
/// `c[k] = Object.assign({}, base[k], c[k] || {})`，而老存档的 `c[k]`
/// 完全可能是字符串 / 数字 / 数组（历史 bug 写坏的字段）。JS 的行为是：
///   · 对象   → 复制自有可枚举键（后者覆盖前者）
///   · 字符串 → 把**每个字符**当成下标键塞进去（{ '0': 'x' }）
///   · 数组   → 把下标当键塞进去
///   · 数字 / 布尔 / null / undefined → 什么也不做
/// 如果这里只处理 Map，遇到 `attributes: 'x'` 这种脏数据，Dart 会静默丢掉
/// 那个 `'0'` 键 —— 与老行为不一致。所以照抄 JS 语义。
Map<String, Object?> _jsObjectAssign(Map<String, Object?> base, Object? extra) {
  final merged = <String, Object?>{};
  base.forEach((k, v) => merged[k] = v);
  if (extra == null) return merged;
  if (extra is Map) {
    extra.forEach((k, v) => merged[jsStr(k)] = v);
  } else if (extra is String) {
    for (var i = 0; i < extra.length; i++) {
      merged['$i'] = extra[i];
    }
  } else if (extra is List) {
    for (var i = 0; i < extra.length; i++) {
      merged['$i'] = extra[i];
    }
  }
  return merged;
}
