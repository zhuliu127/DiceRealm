// ============================================================
// background_logic.dart — 角色背景「剩余四块」的**纯逻辑**（无 BuildContext）
//
// 对应旧版 `ui/steps-d.js` 的后半段（约 240-530 行）：
//   ① 调查员经历   c.history[]      9 个键
//   ② 调查员伙伴   c.companions[]   6 个键
//   ③ 克苏鲁神话   c.mythos         knowledge + notes（+ 只读技能值）
//   ④ 已学法术     c.mythos.spells[] 来自 `cocSpells`（61 条）或自定义
//
// ⚠️ 键名是**契约**，逐字照抄旧版（steps-d.js:495 / :500 / :463 / :316-325）。
//   一个都不许改名、也不许多加 —— 老版本要能读回去。
//
// ⚠️ `mythos.notes` 说明：`newCharacter()` 里没有这个键，但旧版**真的写过它**
//   （steps-d.js:321-324），所以它是既有契约的一部分；本期照抄写入，不合并进
//   `knowledge`（两者语义不同：knowledge=已知神话学识，notes=神话相关经历）。
//
// ⚠️ 法术必须**深拷贝**：旧版是 `JSON.parse(JSON.stringify(src))`。
//   直接引用 `cocSpells` 里的 Map 会让「改一张卡」污染整张静态数据表。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';

/// 调查员经历的 9 个键（旧版 `steps-d.js:495` 的 push 字面量，逐字）
const List<String> historyKeys = <String>[
  'title',
  'date',
  'description',
  'sanChange',
  'hpChange',
  'skillChanges',
  'moneyChange',
  'itemsObtained',
  'notes',
];

/// 调查员伙伴的 6 个键（旧版 `steps-d.js:500`，逐字）
const List<String> companionKeys = <String>[
  'name',
  'avatar',
  'identity',
  'age',
  'relationship',
  'description',
];

/// 自定义法术的键（旧版 `steps-d.js:463` 的 push 字面量，逐字）
const List<String> customSpellKeys = <String>[
  'id',
  'name',
  'category',
  'cost',
  'time',
  'effect',
  'condition',
  'custom',
];

/// 新增一条经历：9 个键全部初始化为空字符串（与旧版一字不差）
Map<String, Object?> newHistoryEntry() => <String, Object?>{
  for (final k in historyKeys) k: '',
};

/// 新增一位伙伴：6 个键全部空字符串
Map<String, Object?> newCompanionEntry() => <String, Object?>{
  for (final k in companionKeys) k: '',
};

/// 自定义法术（旧版：`id: 'custom_' + Date.now().toString(36)`）
Map<String, Object?> newCustomSpell({
  required String name,
  String category = '自定义',
  String cost = '',
  String time = '',
  String effect = '',
  String condition = '',
  String? id,
}) => <String, Object?>{
  'id': id ?? 'custom_${nowMillis().toRadixString(36)}',
  'name': name,
  'category': category.trim().isEmpty ? '自定义' : category.trim(),
  'cost': cost.trim().isEmpty ? '—' : cost.trim(),
  'time': time.trim().isEmpty ? '—' : time.trim(),
  'effect': effect.trim(),
  'condition': condition.trim(),
  'custom': true,
};

/// 深拷贝一条法术（旧版 `JSON.parse(JSON.stringify(src))`）
///
/// ⚠️ 必须走这里，不要 `Map<String, Object?>.from(src)`：
///   后者是浅拷贝，`variants` 数组仍与静态表共享 → 改卡就改了表。
Map<String, Object?> copySpell(Map<String, Object?> src) {
  final out = <String, Object?>{};
  src.forEach((k, v) => out[k] = _deepCopy(v));
  return out;
}

Object? _deepCopy(Object? v) {
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, val) => out[jsStr(k)] = _deepCopy(val));
    return out;
  }
  if (v is List) return v.map(_deepCopy).toList();
  return v;
}

/// 经历 / 伙伴里的**数字型字段**
///
/// 旧版这些输入框是 `UI.input({type:'number'})`，但 `oninput` 里存的是
/// `this.value`（**字符串**）。所以这里照抄字符串：
///   · 不做 `int.parse` —— 半截输入（"-"、""）不会变成 0 或 NaN
///   · 老卡里是 `'-5'` / `5` 两种都可能存在，原样读写才读回一致
/// 「不许写 NaN」由「根本不转换」自然满足。
void setText(Object? map, String key, String value) {
  if (map is! Map) return;
  map[key] = value;
}

/// 读一个文本字段（null / 数字都能安全转成字符串）
String textOf(Object? map, String key) {
  if (map is! Map) return '';
  final v = map[key];
  return v == null ? '' : jsStr(v);
}

/// 经历 / 伙伴 / 法术列表（都挂在卡片上，统一取一次）
List<Object?> historyOf(Character c) => asList(c.raw['history']);

List<Object?> companionsOf(Character c) => asList(c.raw['companions']);

List<Object?> spellsOf(Character c) => asList(c.mythos['spells']);

/// 追加一条经历 / 伙伴（调用方给已构造好的 Map）
void addHistory(Character c, Map<String, Object?> entry) =>
    historyOf(c).add(entry);

void addCompanion(Character c, Map<String, Object?> entry) =>
    companionsOf(c).add(entry);

/// 删除第 [index] 条（越界安全）
void removeAt(Character c, List<Object?> list, int index) {
  if (index < 0 || index >= list.length) return;
  list.removeAt(index);
}

/// 克苏鲁神话技能值（**只读**）：来自技能表里的 `cthulhu`，与 `mythos.skill` 无关
int mythosSkillTotal(Character c) {
  for (final sRaw in c.skills) {
    final s = asMap(sRaw);
    if (jsStr(s['id']) == 'cthulhu') return jsNum(s['total']);
  }
  return 0;
}

/// 法术条目上的展示字段（缺失时给占位符，与旧版 `sp.cost || '—'` 一致）
String spellCost(Map<String, Object?> sp) {
  final v = jsStr(sp['cost'] ?? '').trim();
  return v.isEmpty ? '—' : v;
}

String spellTime(Map<String, Object?> sp) {
  final v = jsStr(sp['time'] ?? '').trim();
  return v.isEmpty ? '—' : v;
}

String spellCategory(Map<String, Object?> sp) {
  final v = jsStr(sp['category'] ?? '').trim();
  return v.isEmpty ? '自定义' : v;
}
