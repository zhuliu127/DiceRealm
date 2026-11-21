// ============================================================
// skillmodel.dart — 角色技能实例模型
// 逐行对应 `core/skillmodel.js`（273 行，`SkillModel`）
//
//   负责：技能列表构建、基础值动态计算、加点、校验、分类统计
//   所有 COC 规则数值来自 rules_coc7 / occupation，此处不硬编码公式
//
// 技能实例的形状（与 JS 完全一致）：
//   { key, id, name, sub, base, growth, occ, int, total, custom, desc }
//   key = id + '::' + sub（自定义技能为 'custom::<name>'）
// ============================================================

import 'character.dart';
import 'data/skills.dart';
import 'js_compat.dart';
import 'occupation.dart';
import 'rules_coc7.dart';

String keyOf(String? id, String? sub) =>
    (sub != null && sub.isNotEmpty) ? '$id::$sub' : jsStr(id);

/// `Math.random().toString(36).slice(2, 8)`
///
/// ⚠️ 已知微小偏差：V8 的 `Number#toString(36)` 会做「最短可往返」舍入，
/// 这里逐位乘 36 截断。仅在「自定义技能没给名字」这一兜底分支里用到，
/// 生成的是 6 位随机后缀，不参与任何规则计算。原码同名逻辑也只在
/// UI 传空名时才会走到。
String _randBase36Suffix([JsRng? rng]) {
  final r = rng ?? nowRng;
  var v = r();
  var out = '';
  for (var i = 0; i < 6; i++) {
    v = v * 36;
    final digit = v.floor();
    v = v - digit;
    out += '0123456789abcdefghijklmnopqrstuvwxyz'[digit % 36];
  }
  return out;
}

/// 动态基础值：母语 = EDU，闪避 = DEX/2，其余取数据库基础值。
/// 注意取的是「年龄调整后的生效属性」——60 岁的人力量和敏捷被扣了，
/// 闪避基础值自然要跟着降，否则年龄调整就等于没生效。
int baseValue(Character character, String? id, String? sub) {
  final a = effectiveAttrs(character);
  final def = skillById(id);
  if (def != null && jsStr(def['dyn']) == 'edu') return jsNum(a['edu']);
  if (def != null && jsStr(def['dyn']) == 'dex2') return (jsNum(a['dex']) / 2).floor();
  // 兜底（防止数据未标注 dyn）
  if (id == 'language_own') return jsNum(a['edu']);
  if (id == 'dodge') return (jsNum(a['dex']) / 2).floor();
  if (def != null &&
      jsTruthy(def['special']) &&
      sub != null &&
      sub.isNotEmpty) {
    for (final sRaw in asList(def['subskills'])) {
      final s = asMap(sRaw);
      if (jsStr(s['name']) == sub) return jsNum(s['base']);
    }
  }
  return def != null ? jsNum(def['base']) : 0;
}

String displayName(String? id, String? sub) {
  final def = skillById(id);
  final nm = def != null ? jsStr(def['name']) : jsStr(id);
  return (sub != null && sub.isNotEmpty) ? '$nm（$sub）' : nm;
}

String categoryOf(String? id) {
  final def = skillById(id);
  return def != null ? jsStr(def['category']) : '自定义';
}

/// 生成一个技能实例
Map<String, Object?> makeSkill(
  Character character,
  String? id,
  String? sub, [
  Map<String, Object?>? custom,
  JsRng? rng,
]) {
  final inst = <String, Object?>{
    'key': keyOf(id, sub),
    'id': id,
    'name': displayName(id, sub),
    'sub': sub ?? '',
    'base': baseValue(character, id, sub),
    'growth': 0,
    'occ': 0,
    'int': 0,
    'total': 0,
    'custom': custom != null,
    'desc': '',
  };
  if (custom != null) {
    final cname = jsStr(custom['name']);
    inst['name'] = cname.isNotEmpty ? cname : '自定义技能';
    inst['base'] = jsNum(custom['base']);
    inst['desc'] = jsTruthy(custom['desc']) ? jsStr(custom['desc']) : '';
    inst['key'] =
        'custom::${cname.isNotEmpty ? cname : _randBase36Suffix(rng)}';
    inst['id'] = 'custom';
  }
  recompute(inst);
  return inst;
}

int recompute(Map<String, Object?> s) {
  final total =
      jsNum(s['base']) + jsNum(s['growth']) + jsNum(s['occ']) + jsNum(s['int']);
  s['total'] = total;
  return total;
}

/// 需要出现在列表中的技能：数据库全量基础技能（组技能展开为可选）
List<Map<String, Object?>> defaultSkillList() {
  final out = <Map<String, Object?>>[];
  for (final d in cocSkills) {
    if (jsTruthy(d['special'])) continue; // 组技能由子类承担
    out.add(<String, Object?>{'id': d['id'], 'sub': ''});
  }
  return out;
}

/// 同步技能列表：保证数据库基础技能存在，且不丢用户已有数据与自定义技能
List<Object?> syncSkills(Character character) {
  final existing = <String, Map<String, Object?>>{};
  for (final sRaw in character.skills) {
    final s = asMap(sRaw);
    existing[jsStr(s['key'])] = s;
  }

  final list = <Object?>[];
  final seen = <String, bool>{};

  // 1) 数据库基础技能（非组）+ 已被使用/通用的组子类
  for (final d in cocSkills) {
    if (!jsTruthy(d['special'])) {
      final k = keyOf(jsStr(d['id']), '');
      final s = existing[k] ?? makeSkill(character, jsStr(d['id']), '');
      s['base'] = baseValue(character, jsStr(d['id']), '');
      s['name'] = displayName(jsStr(d['id']), '');
      recompute(s);
      list.add(s);
      seen[k] = true;
    } else {
      // 组技能（格斗/射击/科学/技艺…）：
      //   flat 组的所有专攻默认就进列表，保证「斗殴」「射击（手枪）」等不会看不见；
      //   非 flat 组仅在已有实例时保留。
      for (final subRaw in asList(d['subskills'])) {
        final subName = jsStr(asMap(subRaw)['name']);
        final k2 = keyOf(jsStr(d['id']), subName);
        if (!existing.containsKey(k2) && !jsTruthy(d['flat'])) continue;
        final s2 =
            existing[k2] ?? makeSkill(character, jsStr(d['id']), subName);
        s2['base'] = baseValue(character, jsStr(d['id']), subName);
        s2['name'] = displayName(jsStr(d['id']), subName);
        recompute(s2);
        list.add(s2);
        seen[k2] = true;
      }
    }
  }

  // 2) 用户自定义技能
  for (final sRaw in character.skills) {
    final s = asMap(sRaw);
    final key = jsStr(s['key']);
    if (seen[key] ?? false) continue;
    if (jsTruthy(s['custom']) || jsStr(s['id']) == 'custom') {
      if (!jsTruthy(s['base'])) s['base'] = 0;
      recompute(s);
      list.add(s);
      seen[key] = true;
    } else if (jsTruthy(s['id'])) {
      final ns = makeSkill(character, jsStr(s['id']), jsStr(s['sub']));
      ns['occ'] = jsNum(s['occ']);
      ns['int'] = jsNum(s['int']);
      ns['growth'] = jsNum(s['growth']);
      recompute(ns);
      list.add(ns);
      seen[jsStr(ns['key'])] = true;
    }
  }

  character.raw['skills'] = list;
  return list;
}

/// 新增组技能子类（如 技艺（摄影）、射击（手枪））
Map<String, Object?> addSubSkill(
  Character character,
  String groupId,
  String subName,
) {
  for (final sRaw in character.skills) {
    final s = asMap(sRaw);
    if (jsStr(s['key']) == keyOf(groupId, subName)) return s;
  }
  final s = makeSkill(character, groupId, subName);
  asList(character.raw['skills']).add(s);
  return s;
}

Map<String, Object?> addCustomSkill(
  Character character,
  Map<String, Object?> def,
) {
  final s = makeSkill(character, 'custom', '', def);
  asList(character.raw['skills']).add(s);
  return s;
}

void removeSkill(Character character, String key) {
  character.raw['skills'] = asList(character.raw['skills'])
      .where((x) => jsStr(asMap(x)['key']) != key)
      .toList();
}

Map<String, Object?>? find(Character character, String key) {
  for (final sRaw in character.skills) {
    final s = asMap(sRaw);
    if (jsStr(s['key']) == key) return s;
  }
  return null;
}

/// 某技能是否属于本职（职业开放）技能
bool isOccupational(Character character, Map<String, Object?>? skill) {
  final set = occupationalSet(character);
  if (skill == null) return false;
  if ((set[jsStr(skill['key'])] ?? false) || (set[jsStr(skill['id'])] ?? false)) return true;
  // 自由选择的职业技能（用户已指定）
  return false;
}

/// 该技能的最终值上限：本职技能走「本职技能上限」，非本职走「兴趣技能上限」。
/// 判定依据与界面一致 —— 用 occupationalSet 判断是否本职。
int capOf(Character character, Map<String, Object?>? skill) {
  final set = occupationalSet(character);
  return skillCapOf(character, skill, set);
}

/// 该技能是否属于本职（职业开放）技能
bool isOccSkill(Character character, Map<String, Object?>? skill) {
  final set = occupationalSet(character);
  if (skill == null) return false;
  return (set[jsStr(skill['key'])] ?? false) ||
      (set[jsStr(skill['id'])] ?? false);
}

/// 加点约束
///   1) 不能为负
///   2) 最终值不得超过该技能对应的上限（本职 / 兴趣 两类）
///   3) 职业点 / 兴趣点各自不能透支
///   4) 克苏鲁神话等「只能靠成长」的技能，职业点与兴趣点都不给加
Map<String, Object?> canAdd(
  Character character,
  Map<String, Object?> skill,
  String field,
  int delta,
) {
  final cap = capOf(character, skill);
  final cur = jsNum(skill[field]);
  final next = cur + delta;
  if (next < 0) return <String, Object?>{'ok': false, 'reason': '该项不能为负数'};
  if (delta > 0 && isGrowthOnly(skill['id']) && field != 'growth') {
    return <String, Object?>{
      'ok': false,
      'reason': '「${skill['name']}」车卡时不能加点',
      'detail': '只能通过「成长」栏增加（遭遇神话事件后）',
    };
  }
  if (delta > 0 && jsNum(skill['total']) + delta > cap) {
    final kind = isOccSkill(character, skill) ? '本职' : '兴趣';
    return <String, Object?>{
      'ok': false,
      'reason': '技能「${skill['name']}」最多到 $cap%（$kind技能上限）',
      'detail': '当前 ${skill['total']}，加 $delta 会超出上限',
    };
  }
  if (delta > 0) {
    if (field == 'occ') {
      final p = occupationPoints(character);
      if (jsNum(p['used']) + delta > jsNum(p['total'])) {
        return <String, Object?>{
          'ok': false,
          'reason': '职业技能点不足',
          'detail': '剩余 ${jsNum(p['total']) - jsNum(p['used'])} 点，需要 $delta 点',
        };
      }
    }
    if (field == 'int') {
      final it = interestPoints(character);
      if (jsNum(it['used']) + delta > jsNum(it['total'])) {
        return <String, Object?>{
          'ok': false,
          'reason': '兴趣技能点不足',
          'detail':
              '剩余 ${jsNum(it['total']) - jsNum(it['used'])} 点，需要 $delta 点',
        };
      }
    }
  }
  return <String, Object?>{'ok': true};
}

Map<String, Object?> applyPoint(
  Character character,
  Map<String, Object?> skill,
  String field,
  int delta,
) {
  final chk = canAdd(character, skill, field, delta);
  if (!jsTruthy(chk['ok'])) return chk;
  final next = jsNum(skill[field]) + delta;
  skill[field] = next < 0 ? 0 : next;
  recompute(skill);
  return <String, Object?>{'ok': true};
}

/// 职业点是否可以加到该技能：组技能需已选定子类
bool canUseOcc(Map<String, Object?> skill) {
  if (jsTruthy(skill['custom'])) return false;
  return true; // 具体限制由 UI 依据 occupationalSet 提示
}

/// 汇总统计：分别统计超出本职上限与超出兴趣上限的技能
Map<String, Object?> stats(Character character) {
  final occ = occupationPoints(character);
  final it = interestPoints(character);
  final capOccRaw = jsNum(character.raw['skillCapOcc']);
  final shared = jsNum(character.raw['skillCap']);
  final occCap = capOccRaw != 0
      ? capOccRaw
      : (shared != 0 ? shared : defaultOccSkillCap);
  final capIntRaw = jsNum(character.raw['skillCapInterest']);
  final intCap = capIntRaw != 0
      ? capIntRaw
      : (shared != 0 ? shared : defaultInterestSkillCap);
  final over = character.skills
      .map(asMap)
      .where((s) => jsNum(s['total']) > capOf(character, s))
      .toList();
  return <String, Object?>{
    'occ': occ,
    'interest': it,
    'overCap': over,
    'cap': occCap,
    'occCap': occCap,
    'interestCap': intCap,
    // 兼容旧字段：单一的 cap 现在等同本职上限
    'caps': <String, Object?>{'occ': occCap, 'interest': intCap},
  };
}
