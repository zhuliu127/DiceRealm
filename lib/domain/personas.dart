// ============================================================
// personas.dart — 世界设定包（随机角色的「人设底座」）
// 逐行对应 `core/personas.js`（约 900 行，纯数据 + 6 个函数）
//
// 一张随机卡的所有「词」都从这里取：姓名 / 居住地 / 籍贯 / 时代 /
// 货币 / 装备口径 / 职业口味 / 背景文本。先定世界设定，再在设定内取词，
// 文化与年代就自然自洽 —— 这是「张子墨 · 现居因斯茅斯」那类错位的根治。
//
// 数据在 `data/personas.dart`（由 tool/oracle/gen_preset_data.js 生成），
// 本文件只放**逻辑**。
//
// ⚠️ 随机调用顺序与 JS 逐字一致（先取谁、取几次都算数）——
//    oracle 会断言 `randUsed`，顺序一分叉立刻不等。
// ============================================================

import 'data/personas.dart';
import 'js_compat.dart';

/// `Math.floor(Math.random() * n)`
int rnd(int n) => (nowRng() * n).floor();

/// 从池子里随机取一项（`pick(a) = a[rnd(a.length)]`）
///
/// 空池子在 JS 里会取到 undefined，这里返回 null —— 调用方按「取不到」处理。
Object? pickOne(List<Object?>? a) {
  if (a == null || a.isEmpty) return null;
  return a[rnd(a.length)];
}

/// 洗牌（Fisher-Yates，从末尾往前，与 `personas.js#shuffle` 逐字一致）
///
/// ⚠️ Dart 的 List 是可变引用，这里**先拷贝**再洗，调用方的池子不会被搅乱 ——
///    与 JS 的 `var out = a.slice();` 行为一致。
List<Object?> shuffle(List<Object?> a) {
  final out = List<Object?>.from(a);
  for (var i = out.length - 1; i > 0; i--) {
    final j = rnd(i + 1);
    final t = out[i];
    out[i] = out[j];
    out[j] = t;
  }
  return out;
}

/// 洗牌一个 String 列表（技能 key / 技能名这类）
List<String> shuffleStrings(List<String> a) {
  final out = List<String>.from(a);
  for (var i = out.length - 1; i > 0; i--) {
    final j = rnd(i + 1);
    final t = out[i];
    out[i] = out[j];
    out[j] = t;
  }
  return out;
}

/// 同批去重游标（对应 `preset.js#newCtx` / `personas.js#pickFrom` 的 `ctx`）
///
/// 一次生成 5 张卡时，把已经用过的下标记下来，下一张优先挑没用过的 ——
/// 这是「连着随机几张都长得差不多」的根治办法。
class PickCtx {
  /// key → (池内下标 → 已用过)
  final Map<String, Map<int, bool>> used = <String, Map<int, bool>>{};
}

/// 带「同批去重」的抽取（`personas.js#pickFrom`，与 `preset.js#pickFrom` 同源）
///
/// 池子抽空时重置该 key 的记录再抽 —— 保证永远不会返回 null。
Object? pickFrom(List<Object?>? pool, PickCtx? ctx, String key) {
  if (pool == null || pool.isEmpty) return null;
  if (ctx == null) return pickOne(pool);
  var u = ctx.used[key];
  if (u == null) {
    u = <int, bool>{};
    ctx.used[key] = u;
  }
  var avail = <int>[];
  for (var i = 0; i < pool.length; i++) {
    if (!(u[i] ?? false)) avail.add(i);
  }
  if (avail.isEmpty) {
    u = <int, bool>{};
    ctx.used[key] = u;
    avail = <int>[];
    for (var j = 0; j < pool.length; j++) {
      avail.add(j);
    }
  }
  final idx = avail[rnd(avail.length)];
  u[idx] = true;
  return pool[idx];
}

/// 全部世界设定（顺序即数据表顺序，加权抽样依赖它）
List<Map<String, Object?>> get list => personaSettings;

/// 按 id 取世界设定；找不到回落到第一个（`getById`）
Map<String, Object?> getById(Object? id) {
  final s = jsStr(id);
  for (final x in personaSettings) {
    if (jsStr(x['id']) == s) return x;
  }
  return personaSettings.first;
}

/// 按权重随机取一个世界设定（`pickSetting`）
///
/// [exclude] 是**要排除**的 id（注意与直觉相反：JS 里传的是被排除的那个）。
Map<String, Object?> pickSetting([Object? exclude]) {
  final ex = exclude == null ? '' : jsStr(exclude);
  final pool = personaSettings
      .where((s) => ex.isEmpty || jsStr(s['id']) != ex)
      .toList();
  var total = 0;
  for (final s in pool) {
    // JS: `a + (s.weight || 1)` —— 0 / 缺失都按 1 算
    total += jsTruthy(s['weight']) ? jsNum(s['weight']) : 1;
  }
  var r = nowRng() * total;
  for (final s in pool) {
    r -= jsTruthy(s['weight']) ? jsNum(s['weight']) : 1;
    if (r <= 0) return s;
  }
  return pool.last;
}

/// 按 id 或标签找世界设定（AI 返回的设定名可能是中文标签）
///
/// 找不到返回 null（**不是**回落第一个 —— `build()` 依赖这个 null
/// 来决定「走加权随机」）。
Map<String, Object?>? resolve(Object? v) {
  if (!jsTruthy(v)) return null;
  final t = jsStr(v).trim();
  for (final s in personaSettings) {
    if (jsStr(s['id']) == t || jsStr(s['label']) == t) return s;
  }
  for (final h in _resolveHints) {
    if (t.contains(h[0])) return getById(h[1]);
  }
  return null;
}

/// 宽松关键词 → 设定 id（顺序敏感：先命中的优先）
const List<List<String>> _resolveHints = <List<String>>[
  <String>['民国', 'cn-republic'],
  <String>['古代', 'cn-ancient'],
  <String>['八十', 'cn-80s'],
  <String>['80 年代', 'cn-80s'],
  <String>['中国', 'cn-modern'],
  <String>['维多利亚', 'uk-victorian'],
  <String>['英国', 'uk-victorian'],
  <String>['1920', 'us-1920'],
  <String>['阿卡姆', 'us-1920'],
  <String>['美国', 'us-modern'],
  <String>['日本', 'jp-modern'],
  <String>['澳大利亚', 'au-modern'],
  <String>['澳洲', 'au-modern'],
  <String>['俄国', 'ru-19c'],
  <String>['沙俄', 'ru-19c'],
  <String>['苏联', 'ru-19c'],
  <String>['未来', 'nearfuture'],
  <String>['赛博', 'nearfuture'],
  <String>['近未来', 'nearfuture'],
  <String>['欧洲', 'eu-modern'],
  <String>['法国', 'eu-modern'],
  <String>['德国', 'eu-modern'],
];

/// 按世界设定的姓名池造一个名字（`makeName`）
///
/// ⚠️ 随机调用顺序：先取「名」，再取「姓」。反过来的话哪怕池子一样，
///    同一个 seed 出来的名字也会不同（oracle 会立刻发现）。
String nameFor(Object? poolKey, Object? gender) {
  final key = jsStr(poolKey);
  final p = asMap(personaNamePools[key] ?? personaNamePools['zhModern']);
  final givenPool = asList(jsStr(gender) == '女' ? p['f'] : p['m']);
  final given = jsStr(pickOne(givenPool));
  final surname = jsStr(pickOne(asList(p['s'])));
  return jsStr(p['order']) == 'fs' ? '$given·$surname' : '$surname$given';
}

/// 生成一句「个人描述」：三成概率用该世界设定的专属描述，否则三段式拼句
///
/// ⚠️ 注意 `looks.length > 0` 时才会消耗那次 `Math.random()` ——
///    没有专属描述的设定不会多消耗一个随机数，这点必须一模一样。
String buildLook(Map<String, Object?>? setting, PickCtx? ctx) {
  final looks = asList(setting?['looks']);
  if (looks.isNotEmpty && nowRng() < 0.32) {
    return jsStr(pickFrom(looks, ctx, 'lookSet'));
  }
  final body = jsStr(pickFrom(personaLookBody, ctx, 'lookBody'));
  final dress = jsStr(pickFrom(personaLookDress, ctx, 'lookDress'));
  final face = jsStr(pickFrom(personaLookFace, ctx, 'lookFace'));
  return '$body，$dress，$face';
}

/// 背景文本池集合（键名与 JS 的 `PER.pools` 逐字一致）
Map<String, List<Object?>> get pools => <String, List<Object?>>{
  'beliefs': personaBeliefs,
  'treasure': personaTreasure,
  'traits': personaTraits,
  'wounds': personaWounds,
  'lookBody': personaLookBody,
  'lookDress': personaLookDress,
  'lookFace': personaLookFace,
  'peopleRel': personaPeopleRel,
  'peopleMid': personaPeopleMid,
  'peopleEnd': personaPeopleEnd,
  'placeTpl': personaPlaceTpl,
  'historyTpl': personaHistoryTpl,
  'entryTail': personaEntryTail,
  'phobiaLead': personaPhobiaLead,
};

// ---- 常用池的直读入口（省得每个调用点都 `pools['x']!`）----
List<Object?> get beliefs => personaBeliefs;
List<Object?> get treasure => personaTreasure;
List<Object?> get traits => personaTraits;
List<Object?> get wounds => personaWounds;
List<Object?> get lookBody => personaLookBody;
List<Object?> get lookDress => personaLookDress;
List<Object?> get lookFace => personaLookFace;
List<Object?> get peopleRel => personaPeopleRel;
List<Object?> get peopleMid => personaPeopleMid;
List<Object?> get peopleEnd => personaPeopleEnd;
List<Object?> get placeTpl => personaPlaceTpl;
List<Object?> get historyTpl => personaHistoryTpl;
List<Object?> get entryTail => personaEntryTail;
List<Object?> get phobiaLead => personaPhobiaLead;

/// 设定清单（只要标签，供界面下拉使用）
List<String> get labels =>
    personaSettings.map((s) => jsStr(s['label'])).toList();
