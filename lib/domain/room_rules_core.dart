// ============================================================
// room_rules_core.dart — 阈值 / 成功等级 / 百分骰 / 检定 / 推动 / 幸运
// （对应 room-rules.js 第 1–5 节，P0-R01~R07）
//
// 全部函数都是纯函数；随机源只在 `_rollD100` 里被消费。
// ============================================================
part of 'room_rules.dart';

// ------------------------------------------------------------
// 小工具（本 library 内共享：其余 part 一律经这里取值）
// ------------------------------------------------------------

/// 原码 `num(v)`：`parseInt(v, 10) || 0`
int _num(Object? v) => jsNum(v);

/// 原码 `pickRng(rng)`：传了函数就用，否则回落全局 `Math.random`
JsRng _pickRng(JsRng? rng) => rng ?? nowRng;

/// 从 opts Map 里取出可注入随机源
JsRng? _rngOf(Object? v) => v is JsRng ? v : null;

/// 十面骰：0-9。
int _die10(JsRng? rng) => _clampDie10((_pickRng(rng)() * 10).floor());

/// 兜住 rng 返回 1 的自定义测试源，以及直接传进来的骰面
int _clampDie10(Object? v) {
  final n = _num(v);
  if (n < 0) return 0;
  if (n > 9) return 9;
  return n;
}

/// 十位骰与个位骰组合成百分骰：00 与 0 → 100，其余正常解释为 1-99。
int _combine(Object? tens, Object? ones) {
  final v = _num(tens) * 10 + _num(ones);
  return v == 0 ? 100 : v;
}

int _clampValue(Object? v) {
  final n = _num(v);
  if (n < 1) return 1;
  if (n > 100) return 100;
  return n;
}

// ------------------------------------------------------------
// 1. 阈值与成功等级
// ------------------------------------------------------------

/// 三个阈值：常规 = 技能值；困难 = 技能值 ÷ 2；极难 = 技能值 ÷ 5。
///
/// 规则书（Pg.82-83）明确「二分之一与五分之一**向下取整**」，
/// 所以 55% 的困难阈值是 27、极难阈值是 11，不是 27.5 / 11。
Map<String, Object?> _thresholds(Object? base) {
  final b = _num(base) < 0 ? 0 : _num(base);
  return <String, Object?>{
    'base': b,
    'regular': b,
    'hard': b ~/ 2,
    'extreme': b ~/ 5,
  };
}

String _normDifficulty(Object? d) =>
    CocRules.DIFFICULTY.containsKey(d) ? jsStr(d) : 'regular';

int _targetOf(Object? base, Object? difficulty) =>
    _num(_thresholds(base)[_normDifficulty(difficulty)]);

/// 大成功阈值：默认 1（即只有 01）；>100 夹到 100。
int _critThresholdOf(Map<String, Object?>? opts) {
  final c = jsParseInt(opts == null ? null : opts['critMax']);
  if (c == null || c < 1) return 1;
  if (c > 100) return 100;
  return c;
}

/// 大失败阈值：0 = 未设置 → 走动态规则（见 [_fumbleRange]）。
int _fumbleThresholdOf(Map<String, Object?>? opts) {
  final f = jsParseInt(opts == null ? null : opts['fumbleMin']);
  if (f == null || f <= 0) return 0;
  if (f > 100) return 100;
  return f;
}

/// 大失败范围 —— ⚠️ 取决于「本次检定**实际要求**的成功阈值」，不是技能原值。
Map<String, Object?> _fumbleRange(
  Object? target, [
  Map<String, Object?>? opts,
]) {
  final fm = _fumbleThresholdOf(opts);
  if (fm > 0) {
    return <String, Object?>{'min': fm, 'max': 100};
  }
  return _num(target) < 50
      ? <String, Object?>{'min': 96, 'max': 100}
      : <String, Object?>{'min': 100, 'max': 100};
}

bool _isFumble(
  Object? value,
  Object? target, [
  Map<String, Object?>? opts,
]) {
  // 100 永远是敌人（旧版是严格相等：'100' 不算）
  if (value is num && value == 100) return true;
  final r = _fumbleRange(target, opts);
  final v = _num(value);
  return v >= _num(r['min']) && v <= _num(r['max']);
}

/// 成功等级。
///
/// ⚠️ 成功等级看的是**技能值**的三档阈值，而「算不算大失败」看的是
/// 本次检定的**要求阈值** —— 这两件事用的是不同分母，别合并成一个参数。
int _levelOf(
  Object? value,
  Object? base, [
  Object? target,
  Map<String, Object?>? opts,
]) {
  final v = _clampValue(value);
  final t = _thresholds(base);
  final req = target == null ? _num(t['regular']) : _num(target);
  if (v <= _critThresholdOf(opts)) return 5;
  if (_isFumble(v, req, opts)) return -1;
  if (v <= _num(t['extreme'])) return 4;
  if (v <= _num(t['hard'])) return 3;
  if (v <= _num(t['regular'])) return 2;
  return 0;
}

// ------------------------------------------------------------
// 2. 掷骰（含奖励骰 / 惩罚骰）
// ------------------------------------------------------------

/// 百分骰，支持奖励骰与惩罚骰。
///
/// ⚠️ 实现顺序必须是「先把每个十位骰组合成百分数、再比大小」。
///    十位骰 {0,1} + 个位骰 0 时，两组组合是 00+0 → **100** 与 10。
///    奖励骰该给 10（更优）；若先对十位骰取 min 得到 0 再判「是不是 100」，
///    就会返回 100 —— 结果完全取反。`dice.dart` 里那个零调用的奖励骰预留实现，
///    正是后一种写法，所以本模块**另建实现**，绝不复用（C7）。
Map<String, Object?> _rollD100(Map<String, Object?> opts) {
  final rng = _rngOf(opts['rng']);
  final bonus = _num(opts['bonus']) < 0 ? 0 : _num(opts['bonus']);
  final penalty = _num(opts['penalty']) < 0 ? 0 : _num(opts['penalty']);
  final cancelled = bonus < penalty ? bonus : penalty;
  final net = bonus - penalty;
  final extra = net.abs();

  final onesRaw = opts['ones'];
  final ones = onesRaw == null ? _die10(rng) : _clampDie10(onesRaw);

  final List<int> tens;
  final ft = opts['forcedTens'];
  if (ft is List && ft.isNotEmpty) {
    tens = <int>[];
    for (var i = 0; i < ft.length && i < 1 + extra; i++) {
      tens.add(_num(ft[i]));
    }
    // 不足则补足，保证数量与净骰数一致
    while (tens.length < 1 + extra) {
      tens.add(tens[tens.length - 1]);
    }
  } else {
    tens = <int>[_die10(rng)];
    for (var i = 0; i < extra; i++) {
      tens.add(_die10(rng));
    }
  }

  final combos = tens.map((t) => _combine(t, ones)).toList();
  var picked = 0;
  for (var j = 1; j < combos.length; j++) {
    if (net > 0) {
      if (combos[j] < combos[picked]) picked = j; // 奖励取更低
    } else if (net < 0) {
      if (combos[j] > combos[picked]) picked = j; // 惩罚取更高
    }
  }

  return <String, Object?>{
    'tens': tens,
    'ones': ones,
    'combos': combos,
    'pickedTens': tens[picked],
    'pickedIndex': picked,
    'value': combos[picked],
    'bonus': bonus,
    'penalty': penalty,
    'cancelled': cancelled,
    'net': net,
    'detail': _describeDice(tens, ones, combos, picked, net),
  };
}

/// 给界面显示的一句话：「10 位骰 3/0，个位 5 → 取 05」
String _describeDice(
  List<int> tens,
  int ones,
  List<int> combos,
  int picked,
  int net,
) {
  String pad(int v) => v.toString().padLeft(2, '0');
  final all = <String>[
    for (var i = 0; i < combos.length; i++) '${pad(tens[i])}+$ones=${combos[i]}',
  ].join('　');
  final head = '个位骰 $ones；十位骰 ${tens.join('/')}';
  if (tens.length == 1) return '$head → ${combos[0]}';
  final tail = net > 0 ? '奖励骰取更低' : '惩罚骰取更高';
  return '$head　（$all）　$tail → ${combos[picked]}';
}

// ------------------------------------------------------------
// 3. 检定
// ------------------------------------------------------------

const Map<String, bool> _pushable = <String, bool>{
  'skill': true,
  'attribute': true,
  'characteristic': true,
};

const Map<String, String> _pushReason = <String, String>{
  'combat': '战斗检定不能推动（规则书：战斗、SAN、对抗检定都不可推动）',
  'san': '理智检定不能推动',
  'sanity': '理智检定不能推动',
  'opposed': '对抗检定不能推动',
  'luck': '幸运检定不能推动',
  'damage': '伤害骰不能推动',
  'sanloss': '理智损失骰不能推动',
};

const Map<String, String> _luckForbidden = <String, String>{
  'luck': '幸运点不能用来改幸运检定',
  'san': '幸运点不能用来改理智检定',
  'sanity': '幸运点不能用来改理智检定',
  'sanloss': '幸运点不能用来改理智损失',
  'damage': '幸运点不能用来改伤害骰',
};

/// 一次技能 / 属性检定。
Map<String, Object?> _check(Map<String, Object?> opts) {
  final kindRaw = opts['kind'];
  final kind = jsTruthy(kindRaw) ? jsStr(kindRaw) : 'skill';
  // ★ P17 KP-2：`difficulty` 上游一律是**全大写**（`REGULAR/HARD/EXTREME` +
  //   新增 `CRITICAL`），而 `DIFFICULTY` 键是小写 ⇒ 必须先转小写再归一，
  //   否则困难/极难静默退化成常规（老 APP `room-rules.js:124 normDifficulty`
  //   的坑）。只改调用点：`_normDifficulty` 本体与 `DIFFICULTY` 的键不动，
  //   `room_rules.json` 的 oracle 仍钉死 `normDifficulty('HARD') == 'regular'`。
  final difficulty = _normDifficulty(jsStr(opts['difficulty']).trim().toLowerCase());
  final base = _num(opts['base']) < 0 ? 0 : _num(opts['base']);
  final target = _targetOf(base, difficulty);
  final t = _thresholds(base);

  final dice = _rollD100(<String, Object?>{
    'bonus': opts['bonus'],
    'penalty': opts['penalty'],
    'rng': opts['rng'],
    'ones': opts['ones'],
    'forcedTens': opts['forcedTens'],
  });
  final valueRaw = opts['value'];
  final value = valueRaw == null ? _num(dice['value']) : _clampValue(valueRaw);
  final level = _levelOf(value, base, target, <String, Object?>{
    'critMax': opts['critMax'],
    'fumbleMin': opts['fumbleMin'],
  });
  final diff = CocRules.DIFFICULTY[difficulty]!;
  final required = _num(diff['required']);

  final passed = level >= required;
  final fumble = level == CocRules.LEVEL['FUMBLE'];
  final critical = level == CocRules.LEVEL['CRITICAL'];

  final labelRaw = opts['label'];
  final result = <String, Object?>{
    'v': 1,
    'kind': kind,
    'label': jsTruthy(labelRaw) ? jsStr(labelRaw) : '',
    'secret': jsTruthy(opts['secret']),
    // ---- 输入 ----
    'base': base,
    'difficulty': difficulty,
    'difficultyText': jsStr(diff['text']),
    'bonus': _num(dice['bonus']),
    'penalty': _num(dice['penalty']),
    // ---- 判定 ----
    'target': target,
    'required': required,
    'thresholds': t,
    'value': value,
    'dice': dice,
    'level': level,
    'levelKey': CocRules.LEVEL_KEY['$level'],
    'levelText': CocRules.LEVEL_TEXT['$level'],
    'passed': passed,
    'failed': !passed,
    'critical': critical,
    'fumble': fumble,
    'fumbleRange': _fumbleRange(target, <String, Object?>{
      'fumbleMin': opts['fumbleMin'],
    }),
    'critMax': _critThresholdOf(opts),
    'fumbleMin': _fumbleThresholdOf(opts),
  };
  // 后续可用动作要在 result 成形之后再算 —— canPush 需要看到 passed / fumble
  final push = _canPush(result, kind);
  final luck = _luckAllowed(kind);
  result['canPush'] = push['ok'];
  result['pushBlockReason'] = push['reason'];
  result['canSpendLuck'] =
      (level == CocRules.LEVEL['FAIL']) && jsTruthy(luck['ok']) && value > 1;
  result['luckBlockReason'] = luck['reason'];
  result['summary'] = _describeCheck(result);
  return result;
}

String _describeCheck(Map<String, Object?> r) {
  final parts = <String>[];
  if (jsTruthy(r['label'])) parts.add(jsStr(r['label']));
  parts.add('目标 ${jsStr(r['base'])}%');
  if (r['difficulty'] != 'regular') {
    parts.add('${jsStr(r['difficultyText'])}（需 ≤ ${jsStr(r['target'])}）');
  }
  parts.add('掷出 ${jsStr(r['value'])}');
  parts.add(jsStr(r['levelText']));
  if (jsTruthy(r['fumble'])) {
    final fr = asMap(r['fumbleRange']);
    final tgt = _num(r['target']);
    parts.add('（大失败范围 ${jsStr(fr['min'])}-${jsStr(fr['max'])}，'
        '因要求阈值 $tgt ${tgt < 50 ? '< 50' : '≥ 50'}）');
  }
  return parts.join('　·　');
}

// ------------------------------------------------------------
// 4. 推动检定
// ------------------------------------------------------------

/// 能不能推动：只有**失败的技能 / 属性检定**可以。
Map<String, Object?> _canPush(
  Map<String, Object?>? result, [
  Object? kind,
]) {
  final kRaw = kind ?? result?['kind'] ?? 'skill';
  final k = jsTruthy(kRaw) ? jsStr(kRaw) : 'skill';
  if (_pushable[k] != true) {
    final reason = _pushReason[k];
    return <String, Object?>{
      'ok': false,
      'reason': reason ?? '「$k」类型的检定不能推动',
    };
  }
  if (result == null) {
    return <String, Object?>{'ok': false, 'reason': '没有可推动的检定结果'};
  }
  if (jsTruthy(result['passed'])) {
    return <String, Object?>{'ok': false, 'reason': '检定已经成功，不需要推动'};
  }
  if (jsTruthy(result['fumble'])) {
    return <String, Object?>{'ok': false, 'reason': '大失败立即生效，不能被推动抹掉'};
  }
  return <String, Object?>{'ok': true, 'reason': ''};
}

// ------------------------------------------------------------
// 5. 幸运点
// ------------------------------------------------------------

/// 该类型检定能否花幸运点（规则书 Pg.99）。
Map<String, Object?> _luckAllowed(Object? kind) {
  final k = kind == null ? 'null' : jsStr(kind);
  final reason = _luckForbidden[k];
  if (reason != null) return <String, Object?>{'ok': false, 'reason': reason};
  return <String, Object?>{'ok': true, 'reason': ''};
}

/// 花幸运点改结果（**原子性由调用方保证**，这里只算，不改任何状态）。
Map<String, Object?> _spendLuck(Map<String, Object?> opts) {
  final rRaw = opts['result'];
  if (rRaw is! Map) {
    return <String, Object?>{'ok': false, 'reason': '没有检定结果'};
  }
  final r = asMap(rRaw);
  final allowed = _luckAllowed(r['kind']);
  if (!jsTruthy(allowed['ok'])) {
    return <String, Object?>{'ok': false, 'reason': allowed['reason']};
  }
  if (jsTruthy(r['fumble'])) {
    return <String, Object?>{'ok': false, 'reason': '大失败不能被幸运点抹掉'};
  }
  if (jsTruthy(r['critical'])) {
    return <String, Object?>{'ok': false, 'reason': '已经是大成功，无需花费幸运点'};
  }

  final amount = _num(opts['amount']);
  if (amount <= 0) {
    return <String, Object?>{'ok': false, 'reason': '花费点数必须是正整数'};
  }
  final avail = _num(opts['luckAvailable']) < 0 ? 0 : _num(opts['luckAvailable']);
  if (amount > avail) {
    return <String, Object?>{'ok': false, 'reason': '幸运点不足（现有 $avail 点）'};
  }

  final before = _num(r['value']);
  // 最低只能压到 1（01 依然是大成功）
  final after = (before - amount) < 1 ? 1 : before - amount;
  final spent = before - after;
  final level = _levelOf(after, r['base'], r['target'], <String, Object?>{
    'critMax': r['critMax'],
    'fumbleMin': r['fumbleMin'],
  });
  final required = _num(CocRules.DIFFICULTY[_normDifficulty(r['difficulty'])]!['required']);

  return <String, Object?>{
    'ok': true,
    'amount': amount,
    'spent': spent,
    'refund': amount - spent,
    'before': before,
    'after': after,
    'beforeLevel': r['level'],
    'afterLevel': level,
    'afterLevelText': CocRules.LEVEL_TEXT['$level'],
    'passed': level >= required,
    // ⚠️ 花过幸运的检定**不得记技能成长勾选**（规则书 Pg.99）
    'growthEligible': false,
    'note': spent < amount ? '结果已压到 01 的边界，多花的 ${amount - spent} 点不予扣除' : '',
  };
}
