// ============================================================
// dice.dart — 骰子工具
// 逐行对应 `core/dice.js`（62 行，`COCDice`）
// ============================================================

import 'js_compat.dart';

/// 掷 n 个 s 面骰之和（`roll`）
///
/// 注：sides 为 0 时每颗骰子恒为 1 —— 这是原码的行为（`1 + floor(r*0)`），
/// 保留不动。
int roll(int n, int sides, [JsRng? rng]) {
  final r = rng ?? nowRng;
  var sum = 0;
  for (var i = 0; i < n; i++) {
    sum += 1 + (r() * sides).floor();
  }
  return sum;
}

// 只在这里出现一次：JS 正则的字符类原样照抄
final RegExp _parenGroup = RegExp(r'[（(].*?[)）]');
final RegExp _trailingUnit = RegExp(r'[A-Za-z\u4e00-\u9fa5/码米步].*$');
final RegExp _diceToken = RegExp(r'-?\d*[Dd]\d+|\d+');
final RegExp _hasD = RegExp(r'[Dd]');

/// 掷骰表达式：`"3D6"` `"2D6+6"` `"1D10+1D4+2"` `"4D6/3码"`
///
/// 解析规则（原码如此）：先去掉括号内容、再从第一个单位/字母/汉字处截断，
/// 然后逐 token 求和。非骰 token 直接当常数。
int parse(String? expr, [JsRng? rng]) {
  if (expr == null || expr.isEmpty) return 0;
  final clean = expr.replaceAll(_parenGroup, '').replaceAll(_trailingUnit, '');
  final tokens = _diceToken.allMatches(clean).map((m) => m.group(0)!).toList();
  if (tokens.isEmpty) return 0;
  var total = 0;
  for (final tok in tokens) {
    if (_hasD.hasMatch(tok)) {
      final p = tok.toLowerCase().split('d');
      final n = (p[0].isEmpty || p[0] == '-') ? 1 : (jsParseInt(p[0]) ?? 0);
      total += roll(n.abs(), jsParseInt(p.length > 1 ? p[1] : '') ?? 0, rng);
    } else {
      total += jsParseInt(tok) ?? 0;
    }
  }
  return total;
}

/// 单颗 dN
int d(int sides, [JsRng? rng]) => roll(1, sides, rng);

/// 单颗 d100
int d100([JsRng? rng]) => roll(1, 100, rng);

/// COC 奖励骰/惩罚骰：十位骰多掷 n 次取最优/最劣
///
/// ⚠️ 注意个位骰只掷一次，`0` 结果折算成 100。
/// `bonus == 0` 时走的是 max（与 JS 三元表达式的写法一致），
/// 但因为 tens 只有一项，结果等同于普通 d100。
int d100Bonus(int bonus, [JsRng? rng]) {
  final ones = d(10, rng) - 1; // 0-9 个位
  final tens = <int>[d(10, rng) - 1];
  final n = bonus.abs();
  for (var i = 0; i < n; i++) {
    tens.add(d(10, rng) - 1);
  }
  final t = bonus > 0 ? jsMin(tens) : jsMax(tens);
  final v = t * 10 + ones;
  return v == 0 ? 100 : v;
}

/// 成功等级判定
///
/// 返回 5 大成功 / 4 极难 / 3 困难 / 2 常规 / 0 失败 / -1 大失败。
/// 边界全部按规则书的动态阈值：
///   · 掷出 01 → 大成功
///   · 掷出 100 → 大失败
///   · 技能 < 50 时，96-100 也是大失败（技能 ≥ 50 时只有 100 才是）
///   · 极难 = ⌊技能/5⌋，困难 = ⌊技能/2⌋
int successLevel(int rollVal, num skill) {
  if (rollVal == 1) return 5; // 大成功
  if (rollVal == 100 || (skill < 50 && rollVal >= 96)) return -1; // 大失败
  if (rollVal <= (skill / 5).floor()) return 4; // 极难成功
  if (rollVal <= (skill / 2).floor()) return 3; // 困难成功
  if (rollVal <= skill) return 2; // 常规成功
  return 0; // 失败
}

/// 等级文案。键是**字符串**（原码是 JS 对象的键，'-1' 也在其中）。
const Map<String, String> levelText = <String, String>{
  '5': '大成功',
  '4': '极难成功',
  '3': '困难成功',
  '2': '成功',
  '0': '失败',
  '-1': '大失败',
};

/// 取等级文案；未知等级返回空串
String levelTextOf(int level) => levelText['$level'] ?? '';
