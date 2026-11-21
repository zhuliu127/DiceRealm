// ============================================================
// domain/skill_synonyms.dart — 车卡技能搜索的**近义词标签**（P10 第 4 期）
//
// 用户原话：「给每个技能都加上一些近义词标签（不显示近义词，只为搜索功能
//   服务），让玩家在搜索技能时也能通过近义词搜索到。特殊：取悦，旧版技能
//   为魅惑，让搜索的时候这两种词都能搜索到该技能」。
//
// ★ 两条硬约束：
//   1) 这张表**只参与 `skillMatchesKeyword` 的匹配字段**，绝不参与任何渲染
//      文本（不进 name / desc / sub / hintText / 任何 Text）。「不显示近义词」
//      是结构上保证的，而不是靠调用方自觉。
//   2) 技能数据 `domain/data/skills.dart` / `occupations.dart` 是 GENERATED
//      FILE（源 `data/skills.js`，由 `tool/oracle/gen_data.js` 生成），**禁止
//      往技能数据里加字段**（会动到 oracle 夹具与逐卡深比）。近义词另开此表，
//      按技能 `id` 索引，与生成数据完全解耦。
//
// ★ 覆盖 `cocSkills` 全部 54 条（含 8 条 `special:true` 组技能），由
//   `test/p10_t4_synonym_request_done_test.dart` 一条用例逐 id 断言非空，
//   防止「只给几个常用技能加」。
// ★ P10 第 5 期：上批登记的遗留「组技能子类名暂无独立近义词」已由
//   `skill_subskill_synonyms.dart` 补齐（按「组 id + 子类名」外挂，覆盖
//   8 组全部子类行）。本表**仍只管组级**，两级词刻意不重复、分层查询，
//   `skillSynonymIdOf` 的三级回退继续只解析组 id，语义一字未动。
//
// ★ 与 `domain/occupation.dart` 的边界：那边有一套 `alias` /
//   `skillSearchText` / `skillMatches`，是**职业解析与职业搜索**用的
//   （`searchTextOfOccupation` 会把每个技能的索引并进职业文本）。本表默认
//   **不并入**职业搜索：近义词面宽，并进去会显著抬高职业搜索的误命中率。
//   `occupation.dart` 里 `'魅惑'/'取悦' → charm` 的别名是职业数据解析用，
//   语义不动；本表只是让**车卡技能搜索框**也能用旧译搜到「取悦」，两者不冲突。
//
// ⚠️ 纯 Dart：零引擎 / 零文件 / 零 UI 依赖，只 import 生成数据与 js_compat。
// ============================================================

import 'data/skills.dart' show cocSkills;
import 'js_compat.dart' show jsStr;

/// 技能 id → 近义词列表。
///
/// 收录口径：口语叫法 / 旧译 / 常见简称 / 英文常用词，语义要贴；
/// 不塞无关词，也**不把别的技能的正式名**塞进来（否则搜 A 会带出 B）。
/// 特别是 `charm` 显式收录旧译「魅惑」—— 不依赖 `desc` 里那句偶然出现的
/// 「（旧译「魅惑」）」：生成文件将来改文案，搜索能力不该跟着消失。
const Map<String, List<String>> skillSynonyms = <String, List<String>>{
  'spot_hidden': <String>['搜查', '搜寻', '观察', 'spot hidden', 'search'],
  'listen': <String>['听音', '听觉', '窃听', 'listen'],
  'library': <String>['查资料', '查文献', '翻阅', 'library use'],
  'psychology': <String>['读心', '察言观色', 'psychology'],
  'track': <String>['跟踪', '寻迹', '足迹', 'tracking'],
  'persuade': <String>['劝说', '游说', '辩论', 'persuasion'],
  'fast_talk': <String>['忽悠', '花言巧语', '巧辩', 'fast talk'],
  'intimidate': <String>['胁迫', '威胁', '威吓', 'intimidation'],
  // ★ 用户点名：正式名「取悦」，旧版技能名为「魅惑」，两个词都要搜得到。
  'charm': <String>['魅惑', '讨好', '恭维', '迷人', 'charm'],
  'disguise': <String>['伪装', '易容', '化装', 'disguise'],
  'language_own': <String>['本国语', '家乡话', 'own language'],
  // 组技能：本表只补**组名**近义；子类名（拉丁语 / 手枪…）的独立近义词
  // 在 `skill_subskill_synonyms.dart`，按「组 id + 子类名」分层外挂。
  'language_other': <String>['外语', '外国话', 'other language'],
  'fighting': <String>['近战', '肉搏', '徒手', 'brawl'],
  'firearms': <String>['枪械', '开枪', '枪法', 'gunplay'],
  'throw': <String>['抛掷', '扔东西', 'throwing'],
  'dodge': <String>['躲避', '回避', '躲闪', 'dodge'],
  'accounting': <String>['账目', '簿记', '查账', 'bookkeeping'],
  'anthropology': <String>['民俗', '人种', 'anthropology'],
  'appraise': <String>['鉴定', '估值', '鉴价', 'appraisal'],
  'archaeology': <String>['考古', '文物', '古物', 'archaeology'],
  'history': <String>['史学', '史籍', 'history'],
  'law': <String>['法学', '法规', '律法', 'law'],
  'occult': <String>['秘术', '玄学', 'occult'],
  'science': <String>['理科', '自然科学', 'science'],
  'lore': <String>['博闻', '典故', '地方知识', 'folklore'],
  'cthulhu': <String>['神话', '旧日', 'cthulhu mythos'],
  'first_aid': <String>['包扎', '止血', '应急救护', 'first aid'],
  'medicine': <String>['医术', '诊疗', '医药', 'medicine'],
  'psychoanalysis': <String>['心理治疗', '心理疏导', 'therapy'],
  'hypnosis': <String>['暗示', '催眠术', 'hypnosis'],
  'drive_auto': <String>['开车', '驾车', '驾驶汽车', 'drive auto'],
  'ride': <String>['骑马', '骑乘', 'riding'],
  'pilot': <String>['开飞机', '操舵', '航行', 'piloting'],
  'climb': <String>['攀登', '爬墙', 'climbing'],
  'jump': <String>['起跳', '跳远', 'jumping'],
  'swim': <String>['泅水', '游水', 'swimming'],
  'stealth': <String>['潜入', '悄悄', '隐蔽移动', 'sneak'],
  'navigate': <String>['导航', '定向', '辨向', 'navigation'],
  'survival': <String>['野外求生', '求生', 'wilderness'],
  'natural_world': <String>['动植物', '自然史', 'natural history'],
  'animal': <String>['驯养', '动物训练', 'animal handling'],
  'diving': <String>['深潜', '水下作业', 'scuba'],
  'artillery': <String>['火炮', '炮击', 'gunnery'],
  'demolitions': <String>['炸药', '爆破作业', 'explosives'],
  'mech_repair': <String>['修机械', '机修', 'mechanical repair'],
  'elec_repair': <String>['修电器', '电工', 'electrical repair'],
  'electronics': <String>['电路', '电子', 'circuits'],
  'computer': <String>['电脑', '计算机', 'computer use'],
  'op_heavy': <String>['重机', '开重型', 'heavy machinery'],
  'locksmith': <String>['开锁', '撬锁', '配钥匙', 'lockpicking'],
  'sleight': <String>['扒窃', '手法', '戏法', 'sleight of hand'],
  'read_lips': <String>['唇语', '读唇术', 'lip reading'],
  'art_craft': <String>['手艺', '艺术', '工艺', 'arts and crafts'],
  'credit': <String>['身价', '信誉', '社会地位', 'credit rating'],
};

/// 从「技能搜索框传进来的 Map」里解析出技能 id。
///
/// ★ 两个搜索框传的 Map **形状不同**，这是本批最容易踩的坑：
///   · `step_skills.dart:68 _matches` 传的是角色卡技能实例，技能 id 在
///     `'id'` 键（`'key'` 是带子类的复合键，如 `fighting::斗殴`，不能当 id 用）；
///   · `step_skills.dart:1039` 的「任选技能」弹窗传的是
///     `{'skill': s['id'], 'sub': ..., 'name': ...}`，**没有 `id` 键**。
/// 所以按 `id → skill → 按 name 反查生成表` 三级回退，两个框都能命中。
/// 都不认识 → null（调用方退回「无近义词」，绝不瞎猜）。
String? skillSynonymIdOf(Map<String, Object?> skill) {
  final byId = jsStr(skill['id']);
  if (byId.isNotEmpty && skillSynonyms.containsKey(byId)) return byId;
  final bySkillKey = jsStr(skill['skill']);
  if (bySkillKey.isNotEmpty && skillSynonyms.containsKey(bySkillKey)) {
    return bySkillKey;
  }
  final name = jsStr(skill['name']);
  if (name.isEmpty) return null;
  for (final def in cocSkills) {
    if (jsStr(def['name']) == name) {
      final id = jsStr(def['id']);
      return skillSynonyms.containsKey(id) ? id : null;
    }
  }
  return null;
}

/// 该技能参与搜索匹配的近义词（无则空表，**不返回 null**，调用方无需兜底）。
List<String> synonymsOf(Map<String, Object?> skill) {
  final id = skillSynonymIdOf(skill);
  if (id == null) return const <String>[];
  return skillSynonyms[id] ?? const <String>[];
}

/// 「魅惑」这个旧译是否只属于 `charm`（防止近义词表互相污染的工具函数）。
///
/// 被 `test/p10_t4_synonym_request_done_test.dart` 用来断言：
/// 全表里只有 `charm` 收录了含「魅」或「惑」的词。
bool synonymContains(String token) {
  for (final entry in skillSynonyms.entries) {
    for (final word in entry.value) {
      if (word.contains(token)) return true;
    }
  }
  return false;
}

/// 收录了指定 token 的技能 id 列表（诊断 / 防污染断言用）。
List<String> synonymOwnersOf(String token) => <String>[
      for (final entry in skillSynonyms.entries)
        if (entry.value.any((w) => w.contains(token))) entry.key,
    ];
