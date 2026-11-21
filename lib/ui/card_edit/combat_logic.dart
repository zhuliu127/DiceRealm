// ============================================================
// combat_logic.dart — 战斗装备的**纯逻辑**（无 BuildContext）
//
// 逐行对齐旧版 `ui/steps-c.js#combat` 里那段「武器使用技能清单」：
//
//   只列真正能拿来打人的技能：格斗各门类 + 射击各门类 + 投掷 / 炮术 / 爆破。
//   之前这里是个**自由文本框**，能填出「心理学」这种根本打不了架的技能 ——
//   现在必须是受约束的下拉清单（硬约束 4）。
//
// ⚠️ 武器库里的写法与技能表里的专攻名不完全一致（`剑` vs `刀剑`、
//   `机枪` vs `机枪/重武器/火焰喷射器`…），所以有一张别名表 [weaponSkillAlias]。
//   这张表必须**照抄**：归一错了，武器的成功率就会显示成 0%。
//
// ⚠️ 伤害加值 DB / 体格由 STR+SIZ 决定（`domain/derived`），这里只读
//   `derivedStats`，不自己算 —— 也**不允许**手填（旧版是只读展示）。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/data/skills.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/skillmodel.dart';

/// 武器表写法 → 技能表专攻名（旧版 `WEAPON_SKILL_ALIAS`，逐字照抄）
const Map<String, String> weaponSkillAlias = <String, String>{
  '剑': '刀剑',
  '鞭子': '鞭',
  '绞具': '绞索',
  '链枷': '链锯/连枷',
  '电锯': '链锯/连枷',
  '机枪': '机枪/重武器/火焰喷射器',
  '重武器': '机枪/重武器/火焰喷射器',
  '喷射器': '机枪/重武器/火焰喷射器',
};

/// 清单外补充的战斗技能（旧版 `EXTRA_COMBAT_SKILLS`）
const List<String> extraCombatSkills = <String>['投掷', '炮术', '爆破'];

/// 一个「武器使用技能」选项
class WeaponSkillOption {
  const WeaponSkillOption({
    required this.value,
    required this.total,
    required this.occ,
    this.syntheticLabel,
  });

  /// 技能名（写进 `weapon.skill` 的值）
  final String value;

  /// 角色当前该技能的最终值（0 = 没有任何加成，只有基础值也照实显示）
  final int total;

  /// 是否本职技能
  final bool occ;

  /// 非空时用它当文案（用于「武器自带」这种清单外的历史值）
  final String? syntheticLabel;

  /// 下拉框文案：「斗殴　45%（本职）」
  String get label {
    final suffix = occ ? '（本职）' : '';
    return syntheticLabel ?? '$value　$total%$suffix';
  }

  /// 成功率三点提示：「斗殴：常规 45%　困难 22%　极难 9%（本职技能）」
  String get chanceText {
    final s = occ ? '（本职技能）' : '';
    return '$value：常规 $total%　困难 ${(total / 2).floor()}%　极难 ${(total / 5).floor()}%$s';
  }
}

bool _isCombatGroup(Object? id) => id == 'fighting' || id == 'firearms';

/// 战斗类技能名清单（不含角色数据）：格斗各门类 + 射击各门类 + 投掷/炮术/爆破
List<String> combatSkillNames() {
  final out = <String>[];
  final seen = <String>{};
  for (final def in cocSkills) {
    if (!_isCombatGroup(def['id'])) continue;
    for (final subRaw in asList(def['subskills'])) {
      final name = jsStr(asMap(subRaw)['name']);
      if (name.isEmpty || !seen.add(name)) continue;
      out.add(name);
    }
  }
  for (final x in extraCombatSkills) {
    if (seen.add(x)) out.add(x);
  }
  return out;
}

/// 该名称是不是合法的「武器使用技能」
bool isValidWeaponSkill(String name) => combatSkillNames().contains(name);

/// 查角色当前某技能的值（旧版 `skillTotalOf`）。
///
/// 先按别名把武器表的写法归一到技能表写法，再在角色的技能列表里找；
/// 找不到就退回数据库基础值（技能列表还没建起来时也不至于显示 0）。
WeaponSkillOption skillTotalOf(Character c, String name) {
  final target = weaponSkillAlias[name] ?? name;
  final occSet = occupationalSet(c);
  for (final sRaw in c.skills) {
    final s = asMap(sRaw);
    final sName = jsStr(s['name']);
    final sSub = jsStr(s['sub']);
    final hit =
        sName == target ||
        sSub == target ||
        (sSub.isNotEmpty && sName.contains('（$target）'));
    if (!hit) continue;
    final key = jsStr(s['key']);
    final id = jsStr(s['id']);
    return WeaponSkillOption(
      value: target,
      total: jsNum(s['total']),
      occ: (occSet[key] ?? false) || (occSet[id] ?? false),
    );
  }
  for (final def in cocSkills) {
    if (jsTruthy(def['special'])) {
      for (final subRaw in asList(def['subskills'])) {
        final sub = asMap(subRaw);
        if (jsStr(sub['name']) == target) {
          return WeaponSkillOption(
            value: target,
            total: jsNum(sub['base']),
            occ: false,
          );
        }
      }
    } else if (jsStr(def['name']) == target) {
      return WeaponSkillOption(
        value: target,
        total: baseValue(c, jsStr(def['id']), ''),
        occ: false,
      );
    }
  }
  return WeaponSkillOption(value: target, total: 0, occ: false);
}

/// 武器「使用技能」下拉清单（硬约束 4：只有这些能被选中）
List<WeaponSkillOption> weaponSkillOptions(Character c) {
  return combatSkillNames().map((name) => skillTotalOf(c, name)).toList();
}

/// 编辑一把**已有**武器时用的清单：
/// 旧数据 / 武器库里出现了清单外的写法（如「电气维修」）时保留原值，
/// 否则一保存就被改掉（旧版同款兜底）。
List<WeaponSkillOption> weaponSkillOptionsFor(
  Character c,
  String? currentSkill,
) {
  final list = weaponSkillOptions(c);
  final cur = (currentSkill ?? '').trim();
  if (cur.isEmpty) return list;
  final exists = list.any(
    (o) => o.value == cur || o.value == (weaponSkillAlias[cur] ?? ''),
  );
  if (exists) return list;
  final total = skillTotalOf(c, cur).total;
  return <WeaponSkillOption>[
    WeaponSkillOption(
      value: cur,
      total: total,
      occ: false,
      syntheticLabel: '$cur（武器自带）',
    ),
    ...list,
  ];
}

/// 空武器条目（自定义武器用；键名与武器库的条目完全一致）
Map<String, Object?> newWeaponEntry({
  String name = '',
  String skill = '斗殴',
  String category = '自定义',
  String damage = '',
  String range = '',
  String pierce = '×',
  String perRound = '',
  String ammo = '',
  String malfunction = '',
  String note = '',
}) {
  return <String, Object?>{
    'name': name,
    'skill': skill,
    'damage': damage,
    'range': range,
    'pierce': pierce,
    'perRound': perRound,
    'ammo': ammo,
    'malfunction': malfunction,
    'era': '',
    'price': '',
    'category': category,
    'note': note,
    'qty': 1,
  };
}

/// 从武器库条目复制一条（数量默认 1，与旧版 `push({...w, qty:1})` 一致）
Map<String, Object?> weaponFromLibrary(Map<String, Object?> lib) {
  final out = <String, Object?>{};
  lib.forEach((k, v) => out[k] = v);
  out['qty'] = 1;
  return out;
}

/// 武器数量加减（下限 1，旧版 `Math.max(1, qty-1)`）
void stepWeaponQty(Map<String, Object?> w, int delta) {
  final next = jsNum(w['qty']) + delta;
  w['qty'] = next < 1 ? 1 : next;
}

/// 近战修正展示（DB / 体格 / 力量+体型）—— 只读，来自 `derivedStats`
class MeleeSummary {
  const MeleeSummary({
    required this.db,
    required this.build,
    required this.strSiz,
  });

  final String db;
  final int build;
  final int strSiz;

  static MeleeSummary of(Character c) {
    final d = c.derivedStats;
    return MeleeSummary(
      db: jsStr(d['db']).isEmpty ? '0' : jsStr(d['db']),
      build: jsNum(d['build']),
      strSiz: jsNum(c.attributes['str']) + jsNum(c.attributes['siz']),
    );
  }
}

/// 随身物品的 10 个快捷预设（旧版 `steps-c.js#gear` 逐字照抄）
const List<String> gearPresets = <String>[
  '手电筒',
  '手机',
  '钱包',
  '打火机',
  '急救包',
  '相机',
  '笔记本',
  '绳索',
  '瑞士军刀',
  '雨伞',
];

/// 新增一条随身物品（`quantity` 默认 1；键名与旧版一致）
Map<String, Object?> newItemEntry([String name = '']) => <String, Object?>{
  'name': name,
  'quantity': 1,
  'description': '',
};

/// 数量输入：非法或空 → 1（与旧版 `parseInt(x,10) || 1` 完全一致）
int normalizeItemQuantity(Object? raw) {
  final n = jsParseInt(raw);
  return (n == null || n == 0) ? 1 : n;
}
