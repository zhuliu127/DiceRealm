// ============================================================
// skill_groups.dart — 车卡「技能加点」页的**展示层分组表**
//
// ⚠️ 这里只有「怎么把技能归到一起给玩家筛选」，**不含任何规则数值**：
//   技能本体（基础值 / 上限 / 是否本职）仍全在 `lib/domain`，
//   本文件只引用 domain 的 `cocSkills` 里的 `id` 做归类。
//
// 为什么放在 UI 层：`lib/domain` 是逐行对齐旧版 JS 的冻结层，
// 「常用 / 战斗 / 社交」这种栏目名是产品展示口径，不该污染规则层。
//
// 两条硬约束：
//   1) **一个技能可以出现在多个分类里**（闪避既是「常用」也是「战斗」）；
//      但这只是**筛选视图**，加点数据始终是 `draft.skills` 里的同一个实例，
//      所以「已加点」在任何分类下看到的都是同一份，不会被复制/分叉。
//   2) **不能有技能漏在分类外**：显式分组没覆盖到的 id 会全部落进「其他」
//      （[uncoveredSkillIds] 就是给测试断言这件事用的）。
// ============================================================

import '../../domain/data/skills.dart';
import '../../domain/js_compat.dart';
import '../../domain/skill_synonyms.dart' show synonymsOf;
import '../../domain/skill_subskill_synonyms.dart' show subskillSynonymsOf;

/// 一个展示分组：`id` 用于 chip 的 Key，`label` 是给玩家看的名字。
class SkillGroup {
  const SkillGroup({
    required this.id,
    required this.label,
    required this.skillIds,
  });

  final String id;
  final String label;

  /// 属于本组的技能 id（不展开组技能的子技能 —— 子技能跟着父技能走）
  final Set<String> skillIds;

  bool contains(String skillId) => skillIds.contains(skillId);
}

/// 「全部」分组的 id（不做任何筛选）
const String skillGroupAllId = 'all';

/// 「其他」分组的 id（兜住所有没被显式分组的技能）
const String skillGroupOtherId = 'other';

/// 自定义技能在实例里的 id（`makeSkill` 用 'custom'）
const String _customSkillId = 'custom';

/// 显式分组。
///
/// 命名取「玩家会怎么找这个技能」，不是规则书目录：
///   · 常用 —— 一局里最常被点开的几项，开屏就能看到；
///   · 战斗 / 社交 / 探索 / 生存 —— 场景维度；
///   · 学识 / 语言 / 技艺 —— 知识维度；
///   · 行动 —— 载具与重机械的操作类（旧版散落在「其他」里，很不好找）。
const List<SkillGroup> _explicitGroups = <SkillGroup>[
  SkillGroup(
    id: 'common',
    label: '常用',
    skillIds: <String>{
      'spot_hidden',
      'listen',
      'library',
      'psychology',
      'dodge',
      'first_aid',
      'stealth',
      'persuade',
      'fighting',
      'firearms',
      'climb',
    },
  ),
  SkillGroup(
    id: 'combat',
    label: '战斗',
    skillIds: <String>{
      'fighting',
      'firearms',
      'dodge',
      'throw',
      'artillery',
      'demolitions',
    },
  ),
  SkillGroup(
    id: 'social',
    label: '社交',
    skillIds: <String>{
      'psychology',
      'persuade',
      'fast_talk',
      'intimidate',
      'charm',
      'disguise',
      'read_lips',
    },
  ),
  SkillGroup(
    id: 'explore',
    label: '探索',
    skillIds: <String>{
      'spot_hidden',
      'listen',
      'track',
      'stealth',
      'navigate',
      'locksmith',
      'sleight',
      'read_lips',
      'climb',
    },
  ),
  SkillGroup(
    id: 'survival',
    label: '生存',
    skillIds: <String>{
      'first_aid',
      'climb',
      'jump',
      'swim',
      'survival',
      'diving',
      'animal',
      'track',
    },
  ),
  SkillGroup(
    id: 'knowledge',
    label: '学识',
    skillIds: <String>{
      'library',
      'accounting',
      'anthropology',
      'appraise',
      'archaeology',
      'history',
      'law',
      'occult',
      'science',
      'lore',
      'cthulhu',
      'medicine',
      'psychoanalysis',
      'hypnosis',
      'natural_world',
      'electronics',
      'computer',
    },
  ),
  SkillGroup(
    id: 'language',
    label: '语言',
    skillIds: <String>{'language_own', 'language_other'},
  ),
  SkillGroup(
    id: 'craft',
    label: '技艺',
    skillIds: <String>{'art_craft', 'mech_repair', 'elec_repair', 'pilot'},
  ),
  SkillGroup(
    id: 'action',
    label: '行动',
    skillIds: <String>{'drive_auto', 'ride', 'pilot', 'op_heavy'},
  ),
];

/// 技能库里的全部 id（顺序与 `cocSkills` 一致，便于稳定展示）
List<String> allSkillIds() => <String>[
  for (final s in cocSkills) jsStr(s['id']),
];

/// 没被任何显式分组覆盖的技能 id。
///
/// 这些 id 会进「其他」组 —— 有它们在，就不可能出现「某个技能哪个分类都找不到」。
List<String> uncoveredSkillIds() {
  final covered = <String>{};
  for (final g in _explicitGroups) {
    covered.addAll(g.skillIds);
  }
  return allSkillIds().where((id) => !covered.contains(id)).toList();
}

/// 分组表（首位「全部」，末位「其他」）。模块级 `final`：只算一次。
final List<SkillGroup> skillGroups = _buildGroups();

List<SkillGroup> _buildGroups() {
  final all = allSkillIds();
  final other = <String>{...uncoveredSkillIds(), _customSkillId};
  return <SkillGroup>[
    SkillGroup(id: skillGroupAllId, label: '全部', skillIds: <String>{...all, _customSkillId}),
    ..._explicitGroups,
    SkillGroup(id: skillGroupOtherId, label: '其他', skillIds: other),
  ];
}

/// 按 id 取组（取不到返回「全部」组，绝不返回 null —— 调用方不用兜底）
SkillGroup skillGroupById(String id) {
  for (final g in skillGroups) {
    if (g.id == id) return g;
  }
  return skillGroups.first;
}

/// 某技能出现在哪些分组里（测试用；也可给「同组也加了点」这类提示用）
List<String> skillGroupIdsOf(String skillId) => <String>[
  for (final g in skillGroups)
    if (g.id != skillGroupAllId && g.contains(skillId)) g.id,
];

/// 技能行的模糊搜索：姓名 / id / 子类 / 描述 / **近义词** 任一命中即算。
///
/// - 中英文都不区分大小写；
/// - 先做子串匹配（搜「侦」命中「侦查」），
/// - 再去掉空格 / 下划线等分隔符匹配一次（搜「spot」命中 id `spot_hidden`），
/// - 最后退化成「按顺序出现」（搜「图书使」也能命中「图书馆使用」）。
///
/// ★ P10 第 4 期：把 `domain/skill_synonyms.dart` 的**组级**近义词并入参与
///   匹配的 `fields`。
/// ★ P10 第 5 期：再并入 `domain/skill_subskill_synonyms.dart` 的**子类级**
///   近义词（按「组 id + 子类名」索引，如搜 `pistol` 命中「射击（手枪）」）。
///   两级表各自独立、分别查询，互不串味；`subskillSynonymsOf` 复用上批的
///   三级回退只解析组 id。
///   近义词只出现在这一个 `fields` 局部列表里，绝不写回任何技能字段、
///   绝不进渲染文本 ⇒ 「不显示近义词，只为搜索服务」是结构性保证。
bool skillMatchesKeyword(Map<String, Object?> skill, String keyword) {
  final kw = _normalize(keyword);
  if (kw.isEmpty) return true;
  final fields = <String>[
    jsStr(skill['name']),
    jsStr(skill['id']),
    jsStr(skill['sub']),
    jsStr(skill['desc']),
    ...synonymsOf(skill),
    ...subskillSynonymsOf(skill),
  ];
  for (final f in fields) {
    if (f.isEmpty) continue;
    final hay = _normalize(f);
    if (hay.contains(kw)) return true;
    if (_isSubsequence(hay, kw)) return true;
  }
  return false;
}

String _normalize(String s) => s
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_\-/·（）()\[\]「」【】]'), '');

bool _isSubsequence(String haystack, String needle) {
  if (needle.isEmpty) return true;
  var i = 0;
  for (var j = 0; j < haystack.length && i < needle.length; j++) {
    if (haystack[j] == needle[i]) i++;
  }
  return i == needle.length;
}
