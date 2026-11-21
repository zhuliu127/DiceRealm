// ============================================================
// card_view.dart — 角色卡的「展示口径」（首页 / 详情页共用）
//
// 所有取值都来自卡片上的权威字段，不在这里计算规则数值 ——
// 派生值只读 `derivedStats` / `status`（由 domain 的 recalc 写入）。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/repo/avatar_store.dart' show localAvatarRel;

/// 本机头像文件的相对路径（`avatars/<cardId>.png`）。
///
/// 老卡没有 `avatar` 字段、自动 SVG 头像（`data:image/svg+xml,...`）、
/// 云端 URL 一律返回 null —— 名册 / 卡面据此显示占位首字，不做二次猜测。
String? avatarImageRel(Character c) => localAvatarRel(c.raw['avatar']);

/// 有没有「可以画出来的」头像（只认本机文件，不认 dataURI）
bool hasAvatarImage(Character c) => avatarImageRel(c) != null;

/// 职业名：优先用 id 反查职业表（老卡可能只存了 occupationName 文本）
String occupationLabel(Character c) {
  final occ = getOccupationById(c.occupationId);
  if (occ != null) return jsStr(occ['name']);
  final txt = jsStr(c.basicInfo['occupationName']);
  return txt.isEmpty ? '未选择职业' : txt;
}

String ageLabel(Character c) {
  final age = jsNum(c.basicInfo['age']);
  return age > 0 ? '$age 岁' : '年龄未填';
}

String genderLabel(Character c) {
  final g = jsStr(c.basicInfo['gender']);
  final custom = jsStr(c.basicInfo['genderCustom']);
  if (g == '其他' && custom.isNotEmpty) return custom;
  return g.isEmpty ? '—' : g;
}

/// `7 / 12`
String pairLabel(Object? cur, Object? max) => '${jsNum(cur)} / ${jsNum(max)}';

String hpLabel(Character c) =>
    pairLabel(c.status['currentHP'], c.status['maxHP']);
String mpLabel(Character c) =>
    pairLabel(c.status['currentMP'], c.status['maxMP']);
String sanLabel(Character c) =>
    pairLabel(c.status['currentSAN'], c.status['maxSAN']);
String luckLabel(Character c) => jsNum(c.status['currentLuck']).toString();

/// 属性值（字符串或数字）→ 显示文本
String attrText(Character c, String key) {
  final v = c.attributes[key];
  final n = jsNum(v);
  return (v == null || jsStr(v).trim().isEmpty) ? '—' : '$n';
}

/// 年龄调整后的生效属性（界面并排展示「原始 → 生效」用）
int effAttr(Character c, String key) {
  final adj = c.raw['ageAdj'];
  if (adj is Map) {
    final eff = adj['eff'];
    if (eff is Map) return jsNum(eff[key]);
  }
  return jsNum(c.attributes[key]);
}

/// 精神状态（多选数组；老卡可能是字符串）
List<String> mentalList(Character c) {
  final m = c.status['mental'];
  if (m is List) {
    return m.map(jsStr).where((s) => s.isNotEmpty).toList();
  }
  if (m == null || jsStr(m).isEmpty) return <String>['正常'];
  return <String>[jsStr(m)];
}

String mentalText(Character c) => mentalList(c).join('　');

/// 身体状态（四态 + dying / unconscious 两个标记合成视图）
///
/// 与老产品 `bodyView` 的优先级一致：死亡 > 濒死 > 昏迷 > body。
String bodyView(Character c) {
  final body = jsStr(c.status['body']);
  if (body == '死亡') return '死亡';
  if (jsTruthy(c.status['dying'])) return '濒死';
  if (jsTruthy(c.status['unconscious'])) return '昏迷';
  return body.isEmpty ? '正常' : body;
}

/// 技能列表按「最终值 + 是否本职」排序后的展示数据
List<Map<String, Object?>> skillRows(
  Character c, {
  required Set<String> occKeys,
}) {
  final rows = c.skills.map(asMap).toList();
  rows.sort((a, b) {
    final ao = occKeys.contains(jsStr(a['key']));
    final bo = occKeys.contains(jsStr(b['key']));
    if (ao != bo) return ao ? -1 : 1;
    return jsNum(b['total']).compareTo(jsNum(a['total']));
  });
  return rows;
}
