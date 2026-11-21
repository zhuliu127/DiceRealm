// ============================================================
// combat_skill_map.dart — 「武器 → 战斗技能」的唯一事实源（纯 Dart）
//
// 需求（P9-9）：
//   自动车卡时，角色点的战斗技能必须和它**实际携带的武器**对得上 ——
//   带黄铜指虎就该学「格斗（斗殴）」，带手枪就该学「射击（手枪）」，
//   别的战斗技能学了也用不上，不该占点数。没有武器时徒手也能打，
//   所以只保底学「斗殴」。
//
// 三层口径：
//   ① 武器表（`data/weapons.dart`）里的 `skill` 字段是**人类写法**，
//      与技能表的专攻名并不一致（`剑` vs `刀剑`、`鞭子` vs `鞭`、
//      `绞具` vs `绞索`、`链枷`/`电锯` vs `链锯/连枷`、`机枪`/`重武器`/`喷射器`
//      vs `机枪/重武器/火焰喷射器`）。先过 [canonicalWeaponSkillName] 归一。
//   ② 归一后的名字去技能表里查真实实例 key：组技能是 `id::专攻`
//      （`fighting::斗殴`），非组技能就是 id（`throw`）。
//   ③ 只有 `category == '战斗'` 的才算「战斗技能」；`雷管` 的
//      `电气维修` 不是战斗技能，不进武器对齐的闸门。
//
// ⚠️ 与 `lib/ui/card_edit/combat_logic.dart#weaponSkillAlias` 的关系：
//   那份别名表是**展示层**（下拉清单里归一成功率），这份是**规则层**。
//   两者必须一致，由 `test/p9_combat_skill_test.dart` 逐条比对锁死。
//
// 纯 Dart 规则层：不引 UI 框架，不碰文件系统 / 画布。
// ============================================================

import 'character.dart';
import 'data/skills.dart';
import 'js_compat.dart';

/// 武器表写法 → 技能表专攻名。
///
/// 前 8 条与旧版 `WEAPON_SKILL_ALIAS`（`ui/card_edit/combat_logic.dart`）
/// 逐字一致；后几条是把「拆开的写法」折回技能表的合并名，避免自定义武器
/// 填了 `霰弹枪` / `连枷` / `火焰喷射器` 就只能归到 0 点。
const Map<String, String> weaponSkillAlias = <String, String>{
  '剑': '刀剑',
  '鞭子': '鞭',
  '绞具': '绞索',
  '链枷': '链锯/连枷',
  '电锯': '链锯/连枷',
  '机枪': '机枪/重武器/火焰喷射器',
  '重武器': '机枪/重武器/火焰喷射器',
  '喷射器': '机枪/重武器/火焰喷射器',
  // —— 合并名的拆写归一 ——
  '连枷': '链锯/连枷',
  '链锯': '链锯/连枷',
  '绞绳': '绞索',
  '步枪': '步枪/霰弹枪',
  '霰弹枪': '步枪/霰弹枪',
  '弓弩': '弓',
  '弩': '弓',
  '火焰喷射器': '机枪/重武器/火焰喷射器',
};

/// 徒手也能打出来的战斗技能：没有武器时的唯一保底。
const String unarmedCombatSkillName = '斗殴';

/// 斗殴的实例 key（`fighting` 组 `flat:true`，`syncSkills` 时一定存在）。
const String unarmedCombatSkillKey = 'fighting::$unarmedCombatSkillName';

/// 归一：武器表的写法 → 技能表的专攻名。空串归一为空串。
String canonicalWeaponSkillName(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  return weaponSkillAlias[t] ?? t;
}

/// 组技能 id（`fighting` / `firearms` / …）是否属于「战斗」分类。
///
/// 走数据表的 `category`，不在这里写死名单 —— 加技能时不用改这张表。
bool isCombatSkillId(String id) {
  for (final d in cocSkills) {
    if (jsStr(d['id']) != id) continue;
    return jsStr(d['category']) == '战斗';
  }
  return false;
}

/// 技能实例 key（`fighting::斗殴` / `throw`）是否属于「战斗」分类。
bool isCombatSkillKey(String key) {
  final id = key.contains('::') ? key.split('::').first : key;
  return isCombatSkillId(id);
}

/// 专攻名 / 技能名 → 技能实例 key。查不到返回 null。
///
/// 组技能（格斗 / 射击 / 科学 / 技艺…）返回 `id::专攻`，
/// 独立技能（投掷 / 爆破 / 炮术 / 电气维修…）返回 id。
String? skillKeyOfName(String name) {
  final target = name.trim();
  if (target.isEmpty) return null;
  for (final d in cocSkills) {
    final id = jsStr(d['id']);
    if (!jsTruthy(d['special'])) {
      if (jsStr(d['name']) == target) return id;
      continue;
    }
    for (final subRaw in asList(d['subskills'])) {
      final sub = jsStr(asMap(subRaw)['name']);
      if (sub == target) return '$id::$target';
    }
  }
  return null;
}

/// 一把武器的 `skill` 字段 → 技能实例 key（可能是非战斗技能，见 `电气维修`）。
String? combatSkillKeyOfWeaponSkill(String weaponSkill) =>
    skillKeyOfName(canonicalWeaponSkillName(weaponSkill));

/// 角色身上全部武器要求的那几门战斗技能（key 集合）。
///
/// · 只收 `category == '战斗'` 的技能 —— 雷管的「电气维修」不算战斗技能；
/// · 集合为空（没带武器 / 武器技能认不出来）时保底 [unarmedCombatSkillKey]，
///   因为「徒手斗殴」不需要任何武器。
Set<String> requiredCombatSkillKeys(Character character) =>
    requiredCombatSkillKeysFromWeapons(asList(character.raw['weapons']));

/// [requiredCombatSkillKeys] 的纯列表版本（便于单测，不依赖 Character）。
Set<String> requiredCombatSkillKeysFromWeapons(List<Object?> weapons) {
  final out = <String>{};
  for (final wRaw in weapons) {
    final key = combatSkillKeyOfWeaponSkill(jsStr(asMap(wRaw)['skill']));
    if (key == null) continue;
    if (!isCombatSkillKey(key)) continue;
    out.add(key);
  }
  if (out.isEmpty) out.add(unarmedCombatSkillKey);
  return out;
}

/// 与 [requiredCombatSkillKeys] 同口径的**显示名**（斗殴 / 手枪 / 投掷…）。
List<String> requiredCombatSkillNames(Character character) {
  final out = <String>[];
  for (final key in requiredCombatSkillKeys(character)) {
    if (key.contains('::')) {
      out.add(key.split('::')[1]);
    } else {
      out.add(nameOfSkillId(key));
    }
  }
  out.sort();
  return out;
}

/// 技能 id → 显示名（组技能返回组名本身）。查不到就回 id。
String nameOfSkillId(String id) {
  for (final d in cocSkills) {
    if (jsStr(d['id']) == id) return jsStr(d['name']);
  }
  return id;
}
