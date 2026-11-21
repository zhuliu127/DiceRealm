// ============================================================
// view/sheet_view.dart — 角色卡只读派生（设计 §3.6）
//
// ★ 纯 Dart：零 UI 框架依赖。
// ★ 键名严格照 `raSanitizeSheet` 白名单：attrs 用 kRaAttrKeys、
//   skills 项形如 `{name,total}`（不是 value）、status 是 10 键块。
// ★ 他人视图的 sheet 已被 `_cropMember` 裁掉 attrs/skills，
//   这里必须容忍整块缺失，绝不回退成 0 冒充真实数值。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_actions_room.dart'
    show kRaAttrKeys;
import 'package:dice_realm/domain/room_model_state.dart'
    show roomClone, roomNumber;

import 'member_view.dart';
import '../room_text.dart';

/// 角色卡六项数值（不可变值对象）。
class Vitals {
  const Vitals({
    required this.hp,
    required this.hpMax,
    required this.mp,
    required this.mpMax,
    required this.san,
    required this.sanMax,
    required this.luck,
  });

  final num hp, hpMax, mp, mpMax, san, sanMax, luck;
}

/// 一行键值（属性表 / 详情表的通用只读数据）。
class KeyValue {
  const KeyValue(this.k, this.v);

  final String k;
  final String v;
}

/// 技能检定弹层的候选行。
class SkillRow {
  const SkillRow(this.name, this.value, {this.isCustom = false});

  final String name;
  final int value;
  final bool isCustom;
}

Map<String, Object?> _sheetOf(Map<String, Object?>? mem) =>
    asMap(mem?['sheet']);

String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// 生命 / 精神数值（复用 [memberStats] 的双源回退，避免两处口径漂移）。
Vitals vitalsOf(Map<String, Object?>? mem) {
  final s = memberStats(mem);
  final st = asMap(_sheetOf(mem)['status']);
  return Vitals(
    hp: s.hp,
    hpMax: s.hpMax,
    mp: s.mp,
    mpMax: s.mpMax,
    san: s.san,
    sanMax: s.sanMax,
    luck: roomNumber(st['currentLuck'], 0),
  );
}

const List<String> _attrLabels = <String>[
  'STR', 'CON', 'SIZ', 'DEX', 'APP', 'INT', 'POW', 'EDU',
];

/// 八项属性行；键被裁掉时显示「—」，不显示 0（K4 缺键 ≠ 0）。
List<KeyValue> attrRows(Map<String, Object?>? mem) {
  final attrs = asMap(_sheetOf(mem)['attrs']);
  final out = <KeyValue>[];
  for (var i = 0; i < _attrLabels.length && i < kRaAttrKeys.length; i++) {
    final raw = attrs[kRaAttrKeys[i]];
    out.add(KeyValue(
      _attrLabels[i],
      (raw == null || raw == '') ? '—' : _fmt(roomNumber(raw, 0)),
    ));
  }
  return out;
}

/// 技能行：优先 `total`，兼容老卡的 `value`；`custom` 标记自定义技能。
List<SkillRow> skillRows(Map<String, Object?>? sheet) {
  final out = <SkillRow>[];
  for (final sRaw in asList(asMap(sheet)['skills'])) {
    final s = asMap(sRaw);
    final name = roomText(s['name']);
    if (name.isEmpty) continue;
    final raw = s['total'] ?? s['value'];
    final value = roomNumber(raw, 0).toInt();
    final custom = jsTruthy(s['custom']) || jsTruthy(s['isCustom']);
    out.add(SkillRow(name, value, isCustom: custom));
  }
  return out;
}

/// 角色状态文案：'正常 / 轻伤 / 重伤·濒死'（死亡 → 撕卡）。
String charStatusText(Map<String, Object?>? mem) {
  if (mem == null) return '正常';
  final st = asMap(_sheetOf(mem)['status']);
  // ★ 用 status 的**原始 body**（'正常/轻伤/重伤'），不要用 bodyViewOf：
  //   后者优先级是「死亡 > 濒死 > 昏迷 > body」，重伤+濒死会被归一成「濒死」。
  final rawBody = roomText(st['body']);
  final view = bodyViewOf(mem);
  if (rawBody == '死亡' || view == '死亡') return '撕卡';
  if (jsTruthy(st['unconscious']) || view == '昏迷') return '昏迷';
  final dying = jsTruthy(st['dying']) || view == '濒死';
  if (rawBody == '重伤' && dying) return '重伤·濒死';
  if (dying) return '濒死';
  return rawBody.isEmpty ? view : rawBody;
}

/// 精神状态多选文本。
String mentalText(Map<String, Object?>? mem) {
  final rows = <String>[];
  for (final v in asList(_sheetOf(mem)['mental'])) {
    final s = roomText(v);
    if (s.isNotEmpty) rows.add(s);
  }
  return rows.isEmpty ? '正常' : rows.join('、');
}

/// 临时状态（`{text,by,at}`），只读深拷贝。
List<Map<String, Object?>> tempStatusOf(Map<String, Object?>? mem) =>
    <Map<String, Object?>>[
      for (final x in asList(roomClone(_sheetOf(mem)['tempStatus']))) asMap(x),
    ];

/// 随身物品（`{id,name,qty,note}`），只读深拷贝。
List<Map<String, Object?>> itemsOf(Map<String, Object?>? mem) =>
    <Map<String, Object?>>[
      for (final x in asList(roomClone(_sheetOf(mem)['items']))) asMap(x),
    ];

/// 武器（`{name,skill,damage,...}`），只读深拷贝。
List<Map<String, Object?>> weaponsOf(Map<String, Object?>? mem) =>
    <Map<String, Object?>>[
      for (final x in asList(roomClone(_sheetOf(mem)['weapons']))) asMap(x),
    ];

/// 疯狂症状明细（`{type,name,permanent,rounds,from,bg,sum}`），只读深拷贝。
List<Map<String, Object?>> madnessOf(Map<String, Object?>? mem) =>
    <Map<String, Object?>>[
      for (final x in asList(roomClone(_sheetOf(mem)['madness']))) asMap(x),
    ];

// ============================================================
// P10 第 1 期 B1：审卡的「完整角色卡」派生
//
// 招募页 KP 点「详情」时原来只有 数值/属性/技能/精神/临时/物品/武器/疯狂，
// 车卡器产出的 基本资料 / 背景 / 经历 / 装备与资产 / 教育进步 全都看不到。
//
// ★ 口径：只读 `sheet` 里**公开**的白名单字段（`raSanitizeSheet` 的产物），
//   不碰 `privates` / 明文 `p`。整块缺失（他人视图被裁 / 老卡没这些键）时
//   一律返回空列表，**绝不用 0 或 '—' 冒充真实数据**。
// ============================================================

/// 基本资料一行（`k` 是中文标签，`v` 是值）。
List<KeyValue> basicsOf(Map<String, Object?>? mem) {
  final sh = _sheetOf(mem);
  final out = <KeyValue>[];
  void add(String label, Object? raw) {
    final s = roomText(raw);
    if (s.isEmpty) return;
    out.add(KeyValue(label, s));
  }

  // 角色名：弹层标题显示的是**玩家昵称**，卡上的角色名要单独列一行
  add('角色名', sh['name']);
  add('性别', sh['gender']);
  final age = roomNumber(sh['age'], 0);
  if (age > 0) out.add(KeyValue('年龄', '${age.toInt()} 岁'));
  add('时代', sh['era']);
  add('居住地', sh['residence']);
  add('籍贯', sh['birthplace']);
  add('职业', sh['occupation']);
  add('世界', sh['world']);
  return out;
}

/// 背景条目（外貌 + 七项背景），空值不产生行。
///
/// 键名与车卡器 `background` 分区一致（`summary_card.dart` 同一批来源）。
List<KeyValue> backgroundOf(Map<String, Object?>? mem) {
  final sh = _sheetOf(mem);
  final bg = asMap(sh['background']);
  final out = <KeyValue>[];
  void add(String label, Object? raw) {
    final s = roomText(raw);
    if (s.isEmpty) return;
    out.add(KeyValue(label, s));
  }

  add('外貌', sh['look']);
  add('思想与信念', bg['ideology']);
  add('重要之人', bg['significantPeople']);
  add('意义非凡之地', bg['meaningfulPlaces']);
  add('宝贵之物', bg['treasuredPossessions']);
  add('特质', bg['traits']);
  add('伤口与疤痕', bg['wounds']);
  add('恐惧症与狂躁症', bg['phobias']);
  return out;
}

/// 经历条目（`{title,date,description,notes}`），只读深拷贝。
List<Map<String, Object?>> historyOf(Map<String, Object?>? mem) => <Map<String, Object?>>[
      for (final x in asList(roomClone(_sheetOf(mem)['history']))) asMap(x),
    ];

/// 防具名（字符串数组），空串与非法项跳过。
List<String> armorsOf(Map<String, Object?>? mem) => <String>[
      for (final x in asList(_sheetOf(mem)['armors']))
        if (roomText(x).isNotEmpty) roomText(x),
    ];

/// 装备与资产条目（信用 / 现金 / 消费水平 / 资产说明）。
List<KeyValue> gearAssetsOf(Map<String, Object?>? mem) {
  final a = asMap(_sheetOf(mem)['assets']);
  final out = <KeyValue>[];
  final credit = roomNumber(a['creditRating'], -1);
  if (credit >= 0) out.add(KeyValue('信用评级', '${credit.toInt()}'));
  final cash = roomNumber(a['cash'], -1);
  if (cash >= 0) {
    final cur = roomText(a['currency']);
    out.add(KeyValue('现金', cur.isEmpty ? '${cash.toInt()}' : '$cur${cash.toInt()}'));
  }
  final spend = roomText(a['spendingLevel']);
  if (spend.isNotEmpty) out.add(KeyValue('消费水平', spend));
  final desc = roomText(a['description']);
  if (desc.isNotEmpty) out.add(KeyValue('资产说明', desc));
  return out;
}

/// 教育进步：返回 `(检定次数, 教育加成)`；缺键时给 `(0,0)` 由调用方判空。
(int, int) eduOf(Map<String, Object?>? mem) {
  final e = asMap(_sheetOf(mem)['eduProgress']);
  return (
    roomNumber(e['checks'], 0).toInt(),
    roomNumber(e['bonus'], 0).toInt(),
  );
}
