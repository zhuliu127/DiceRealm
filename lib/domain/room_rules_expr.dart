// ============================================================
// room_rules_expr.dart — 骰式 / 伤害 / 连发 / 武器故障（P0-R09 / R14 部分）
// （对应 room-rules.js 第 7、14 节）
//
// 为什么自己解析而不复用 dice.js#parse：
//   ① parse 内部直接调 Math.random，测试无法注入随机源；
//   ② parse 会静默吞掉不认识的内容（返回 0），校验场景需要明确报错。
// ============================================================
part of 'room_rules.dart';

final RegExp _reDiceTerm = RegExp(r'^(\d*)D(\d+)$');
final RegExp _reConstTerm = RegExp(r'^\d+$');
final RegExp _reTokens = RegExp(r'[+-]?[^+-]+');
final RegExp _reSpaces = RegExp(r'\s+');
final RegExp _reParenBurst = RegExp(r'[（(]\s*(\d+)\s*[)）]');
final RegExp _reBurstCn = RegExp(r'(\d+)\s*连射');
final RegExp _reOrN = RegExp(r'(?:or|或)\s*(\d+)');
final RegExp _rePureInt = RegExp(r'^\d+$');
final RegExp _reDashOnly = RegExp(r'^[-—–~～\s]+$');
final RegExp _reRevolver = RegExp(r'左轮|转轮|revolver', caseSensitive: false);

/// 全角 → 半角归一化（骰式输入容错）。
///
/// 用户常在中/英输入法下敲出全角符号：`Ｄ` `ｄ`、全角数字 `０-９`、
/// `＋`（U+FF0B）、`－`（U+FF0D）、`＊` 等。旧实现只在开头 `toUpperCase`，
/// 而分词正则 `[+-]?[^+-]+` 只认半角 `+`/`-`，于是 `D6＋D10` 的 `＋`
/// 不被当作分隔符，整串被当成一个 token → 「骰式里有无法识别的片段」。
/// 这里把常见全角字符统一映射到半角，再交给原有解析逻辑，等价于「用户敲
/// 全角也照样能掷」。只做字符映射，不改任何解析语义。
String _normalizeExprInput(String s) {
  final StringBuffer b = StringBuffer();
  for (final int cu in s.codeUnits) {
    int out = cu;
    if (cu >= 0xFF01 && cu <= 0xFF5E) {
      // 全角 ASCII 可见字符区：整体平移到半角。
      out = cu - 0xFEE0;
    } else if (cu == 0x3000) {
      // 全角空格 → 半角空格。
      out = 0x20;
    }
    b.writeCharCode(out);
  }
  // 中文输入法常见的破折号/连字符变体统一成 `-`（减号语义）。
  return b.toString().replaceAll(RegExp(r'[—–−－~～]'), '-');
}

/// 解析并校验骰式：支持 `NdM`、纯数字，以及它们的加减组合（`1D6+1`、`2D10-1`）。
/// 不支持乘除与括号 —— 本项目用不到，少支持一种语法就少一个注入面。
Map<String, Object?> _parseExpr(Object? expr) {
  final rawSrc = (expr == null ? '' : jsStr(expr)).trim();
  if (rawSrc.isEmpty) {
    return <String, Object?>{'ok': false, 'reason': '骰式为空', 'expr': ''};
  }
  final s = _normalizeExprInput(rawSrc).replaceAll(_reSpaces, '').toUpperCase();
  final matches = _reTokens.allMatches(s).toList();
  if (matches.isEmpty) {
    return <String, Object?>{
      'ok': false,
      'reason': '骰式无法解析：$rawSrc',
      'expr': rawSrc,
    };
  }

  final terms = <Map<String, Object?>>[];
  for (final m0 in matches) {
    var tk = m0.group(0)!;
    var sign = 1;
    if (tk.startsWith('+')) {
      tk = tk.substring(1);
    } else if (tk.startsWith('-')) {
      sign = -1;
      tk = tk.substring(1);
    }
    final md = _reDiceTerm.firstMatch(tk);
    if (md != null) {
      final count = md.group(1)!.isEmpty ? 1 : _num(md.group(1));
      final sides = _num(md.group(2));
      if (count < 1 || count > CocRules.limits['MAX_DICE']!) {
        return <String, Object?>{
          'ok': false,
          'reason': '骰子数量需在 1-${CocRules.limits['MAX_DICE']} 之间',
          'expr': rawSrc,
        };
      }
      if (sides < 2 || sides > CocRules.limits['MAX_SIDES']!) {
        return <String, Object?>{
          'ok': false,
          'reason': '骰子面数需在 2-${CocRules.limits['MAX_SIDES']} 之间',
          'expr': rawSrc,
        };
      }
      terms.add(<String, Object?>{
        'sign': sign,
        'count': count,
        'sides': sides,
      });
    } else if (_reConstTerm.hasMatch(tk)) {
      final c = _num(tk);
      if (c > 10000) {
        return <String, Object?>{
          'ok': false,
          'reason': '常数值过大',
          'expr': rawSrc,
        };
      }
      terms.add(<String, Object?>{
        'sign': sign,
        'count': 0,
        'sides': 0,
        'constant': c,
      });
    } else {
      return <String, Object?>{
        'ok': false,
        'reason': '骰式里有无法识别的片段「$tk」',
        'expr': rawSrc,
      };
    }
  }
  if (terms.isEmpty) {
    return <String, Object?>{
      'ok': false,
      'reason': '骰式无法解析：$rawSrc',
      'expr': rawSrc,
    };
  }
  return <String, Object?>{'ok': true, 'expr': rawSrc, 'terms': terms};
}

/// 按解析结果掷骰，返回 `{ok, total, rolls:[...], detail}`。
Map<String, Object?> _rollExpr(Object? expr, [JsRng? rng]) {
  final Map<String, Object?> p;
  if (expr is String || expr is num) {
    p = _parseExpr(expr);
  } else if (expr is Map) {
    p = asMap(expr);
  } else {
    p = _parseExpr(expr);
  }
  if (p['ok'] != true) {
    return <String, Object?>{
      'ok': false,
      'reason': jsTruthy(p['reason']) ? p['reason'] : '骰式不合法',
      'total': 0,
      'rolls': <Object?>[],
    };
  }
  var total = 0;
  final rolls = <Object?>[];
  final detail = <String>[];
  for (final tRaw in asList(p['terms'])) {
    final t = asMap(tRaw);
    final sign = _num(t['sign']);
    final count = _num(t['count']);
    if (count == 0) {
      final c = _num(t['constant']);
      total += sign * c;
      detail.add('${sign < 0 ? '-' : '+'}$c');
      continue;
    }
    final sides = _num(t['sides']);
    final dice = <int>[];
    for (var i = 0; i < count; i++) {
      var v = 1 + (_pickRng(rng)() * sides).floor();
      if (v < 1) v = 1;
      if (v > sides) v = sides;
      dice.add(v);
      total += sign * v;
    }
    rolls.add(<String, Object?>{
      'count': count,
      'sides': sides,
      'sign': sign,
      'dice': dice,
    });
    detail.add(
      '${sign < 0 ? '-' : '+'}${count}D$sides[${dice.join(',')}]',
    );
  }
  final d = detail.join('');
  return <String, Object?>{
    'ok': true,
    'expr': p['expr'],
    'total': total,
    'rolls': rolls,
    'detail': d.isEmpty ? '0' : d,
  };
}

/// 伤害加值字符串（如 `+1D4`、`-2`、`0`）→ 掷骰结果。
Map<String, Object?> _rollDamageBonus(Object? dbStr, [JsRng? rng]) {
  var s = (dbStr == null ? '' : jsStr(dbStr)).trim();
  if (s.isEmpty || s == '0') {
    return <String, Object?>{
      'ok': true,
      'total': 0,
      'detail': '0（无伤害加值）',
      'rolls': <Object?>[],
    };
  }
  if (!s.startsWith('+') && !s.startsWith('-')) s = '+$s';
  return _rollExpr(s, rng);
}

/// 骰式的理论最大值（贯穿武器「极难成功取最大值」用）。非法骰式返回 0。
int _maxOfExpr(Object? expr) {
  final p = _parseExpr(expr);
  if (p['ok'] != true) return 0;
  var total = 0;
  for (final tRaw in asList(p['terms'])) {
    final t = asMap(tRaw);
    final sign = _num(t['sign']);
    final count = _num(t['count']);
    if (count == 0) {
      total += sign * _num(t['constant']);
    } else {
      total += sign * count * _num(t['sides']);
    }
  }
  return total;
}

/// 伤害加值（DB）字符串的**理论最大值**。
int _maxOfDamageBonus(Object? dbStr) {
  var s = (dbStr == null ? '' : jsStr(dbStr)).trim();
  if (s.isEmpty || s == '0') return 0;
  if (!s.startsWith('+') && !s.startsWith('-')) s = '+$s';
  return _maxOfExpr(s);
}

/// **贯穿伤害**的统一实现：武器伤害理论最大值 + 最大伤害加值 + 再投一次武器伤害骰。
Map<String, Object?> _impaleDamage(Object? expr, Object? db, [JsRng? rng]) {
  final extra = _rollExpr(expr, rng);
  if (extra['ok'] != true) {
    return <String, Object?>{
      'ok': false,
      'reason': jsTruthy(extra['reason']) ? extra['reason'] : '伤害式不合法',
    };
  }
  final base = _maxOfExpr(expr);
  final dbMax = _maxOfDamageBonus(db);
  return <String, Object?>{
    'ok': true,
    'extra': extra,
    'base': base,
    'dbMax': dbMax,
    'raw': base + _num(extra['total']) + dbMax,
  };
}

/// 单次攻击最多发射数（连发上限）解析。恒 ≥ 1。
int _burstMaxOf(Object? perRound) {
  final s = (perRound == null ? '' : jsStr(perRound)).trim();
  if (s.isEmpty) return 1;
  var max = 1;
  final paren = _reParenBurst.firstMatch(s);
  if (paren != null) {
    final n = _num(paren.group(1));
    if (n > max) max = n;
  }
  final burst = _reBurstCn.firstMatch(s);
  if (burst != null) {
    final n = _num(burst.group(1));
    if (n > max) max = n;
  }
  final orN = _reOrN.firstMatch(s);
  if (orN != null) {
    final n = _num(orN.group(1));
    if (n > max) max = n;
  }
  if (s.contains('全自动') && max < 3) max = 3;
  if (_rePureInt.hasMatch(s)) {
    final n = _num(s);
    if (n > max) max = n;
  }
  if (max < 1) max = 1;
  return max;
}

/// 该武器是否「连发类」（每轮可发射数 > 1）。
bool _isBurstWeapon(Object? perRound) => _burstMaxOf(perRound) > 1;

/// 有效故障阈值（1-100）。空 / `——` / 非法 → 0（表示**永不故障**）。
int _malfunctionThresholdOf(Object? weapon) {
  final w = asMap(weapon);
  final s = (w['malfunction'] == null ? '' : jsStr(w['malfunction'])).trim();
  if (s.isEmpty) return 0;
  if (_reDashOnly.hasMatch(s)) return 0;
  if (!_rePureInt.hasMatch(s)) return 0;
  final n = _num(s);
  if (n < 1 || n > 100) return 0;
  return n;
}

/// 武器故障判定：大成功不故障；阈值 0 → 永不故障；否则「掷值 ≥ 阈值」即故障。
Map<String, Object?> _malfunctionOf(
  Object? weapon,
  Object? rollValue, [
  Map<String, Object?>? opts,
]) {
  final th = _malfunctionThresholdOf(weapon);
  if (th == 0) {
    return <String, Object?>{'jammed': false, 'threshold': 0};
  }
  if (opts != null && jsTruthy(opts['critical'])) {
    return <String, Object?>{'jammed': false, 'threshold': th};
  }
  final v = _num(rollValue);
  return <String, Object?>{'jammed': v >= th, 'threshold': th};
}

/// 该武器是否左轮 / 转轮（哑火时「浪费 1 回合重新扣扳机」）。
bool _isRevolver(Object? weapon) {
  final w = asMap(weapon);
  final name = jsTruthy(w['name']) ? jsStr(w['name']) : '';
  return _reRevolver.hasMatch(name);
}

/// 缺省故障类型：左轮 → 哑火；连发/全自动 → 供弹故障；其它 → 卡弹。
String _defaultMalfunctionType(Object? weapon) {
  if (_isRevolver(weapon)) return 'dud';
  final w = asMap(weapon);
  if (_isBurstWeapon(w['perRound'])) return 'feed';
  return 'jam';
}

/// 炸膛自伤（1D3−1，最低 0）。
int _burstSelfDamage(JsRng? rng) {
  final r = _rollExpr('1D3-1', rng);
  if (r['ok'] == true) {
    final t = _num(r['total']);
    return t < 0 ? 0 : t;
  }
  return 0;
}

/// 故障效果结算（纯函数，骰子走注入的 rng）。
Map<String, Object?> _malfunctionEffect(
  Object? weapon,
  Object? type, [
  JsRng? rng,
]) {
  final typeStr = type == null ? '' : jsStr(type);
  final t = CocRules.JAM_TYPES.containsKey(typeStr)
      ? typeStr
      : _defaultMalfunctionType(weapon);
  if (t == 'dud') {
    final rev = _isRevolver(weapon);
    return <String, Object?>{
      'type': 'dud',
      'label': '哑火',
      'clearRounds': 1,
      'damage': 0,
      'destroyed': false,
      'clearText': rev ? '（需浪费 1 回合重新扣扳机）' : '（自动武器需手动退弹，约 1 回合）',
      'summary': rev ? '哑火：浪费 1 回合重新扣扳机' : '哑火：需手动退弹',
    };
  }
  if (t == 'burst') {
    final dmg = _burstSelfDamage(rng);
    return <String, Object?>{
      'type': 'burst',
      'label': '炸膛',
      'clearRounds': 0,
      'damage': dmg,
      'destroyed': true,
      'clearText': '（武器彻底损坏）',
      'summary': '炸膛：武器彻底损坏，射手受 $dmg 点伤害（1D3−1）',
    };
  }
  if (t == 'feed') {
    final f = _rollExpr('1D4+2', rng);
    final fr = f['ok'] == true ? (_num(f['total']) < 0 ? 0 : _num(f['total'])) : 3;
    return <String, Object?>{
      'type': 'feed',
      'label': '供弹故障',
      'clearRounds': fr,
      'damage': 0,
      'destroyed': false,
      'clearText': '（需 $fr 轮清除：1D4+2）',
      'summary': '供弹故障：需 $fr 轮清除',
    };
  }
  final j = _rollExpr('1D6', rng);
  final jr = j['ok'] == true ? (_num(j['total']) < 0 ? 0 : _num(j['total'])) : 1;
  return <String, Object?>{
    'type': 'jam',
    'label': '卡弹',
    'clearRounds': jr,
    'damage': 0,
    'destroyed': false,
    'clearText': '（需 $jr 轮清除：1D6）',
    'summary': '卡弹：需 $jr 轮清除',
  };
}
