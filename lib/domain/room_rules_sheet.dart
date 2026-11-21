// ============================================================
// room_rules_sheet.dart — SAN / 伤势 / 角色卡取值 / 场景步骤
// （对应 room-rules.js 第 8、9、12、13 节，P0-R10 / R11 / R14 部分）
//
// 全部只「算」，不改任何角色对象 —— 落库由调用方（repo 适配层）负责。
// ============================================================
part of 'room_rules.dart';

// ------------------------------------------------------------
// 8. 理智（SAN）
// ------------------------------------------------------------

/// 解析 SAN 损失格式 `成功损失/失败损失`，如 `0/1D6`。
Map<String, Object?> _parseSanLoss(Object? expr) {
  final raw = (expr == null ? '' : jsStr(expr)).trim();
  if (raw.isEmpty) {
    return <String, Object?>{'ok': false, 'reason': '理智损失格式为空（应形如 0/1D6）'};
  }
  final parts = raw.split('/');
  if (parts.length != 2) {
    return <String, Object?>{
      'ok': false,
      'reason': '理智损失需要写成「成功损失/失败损失」，例如 0/1D6',
      'expr': raw,
    };
  }
  final onOk = _parseExpr(parts[0]);
  final onFail = _parseExpr(parts[1]);
  if (onOk['ok'] != true) {
    return <String, Object?>{
      'ok': false,
      'reason': '成功损失不合法：${jsStr(onOk['reason'])}',
      'expr': raw,
    };
  }
  if (onFail['ok'] != true) {
    return <String, Object?>{
      'ok': false,
      'reason': '失败损失不合法：${jsStr(onFail['reason'])}',
      'expr': raw,
    };
  }
  return <String, Object?>{
    'ok': true,
    'expr': raw,
    'onSuccess': onOk,
    'onFail': onFail,
  };
}

/// 结算一次 SAN 检定：成功 → 斜线**前**的损失；失败 → 斜线**后**的损失。
Map<String, Object?> _resolveSanCheck(Map<String, Object?> opts) {
  final parsed = _parseSanLoss(opts['lossExpr']);
  if (parsed['ok'] != true) {
    return <String, Object?>{'ok': false, 'reason': parsed['reason']};
  }

  final Map<String, Object?> chk;
  final provided = opts['checkResult'];
  if (provided is Map) {
    chk = asMap(provided);
  } else {
    chk = _check(<String, Object?>{
      'base': _num(opts['currentSan']),
      'difficulty': 'regular',
      'kind': 'san',
      'label': '理智检定',
      'rng': opts['rng'],
      'critMax': opts['critMax'],
      'fumbleMin': opts['fumbleMin'],
    });
  }
  final passed = jsTruthy(chk['passed']);
  final branch = asMap(passed ? parsed['onSuccess'] : parsed['onFail']);
  final rolled = _rollExpr(branch, _rngOf(opts['rng']));
  if (rolled['ok'] != true) {
    return <String, Object?>{'ok': false, 'reason': rolled['reason']};
  }

  final before = _num(opts['currentSan']) < 0 ? 0 : _num(opts['currentSan']);
  final maxSanRaw = opts['maxSan'];
  final maxSan = maxSanRaw == null
      ? 99
      : (_num(maxSanRaw) < 0 ? 0 : _num(maxSanRaw));
  var after = before - _num(rolled['total']);
  if (after < 0) after = 0;
  if (after > maxSan) after = maxSan; // 只做上限约束，不清空、不编造后果

  return <String, Object?>{
    'ok': true,
    'check': chk,
    'lossExpr': parsed['expr'],
    'usedBranch': passed ? 'onSuccess' : 'onFail',
    'branchText': passed ? '成功' : '失败',
    'lossTerms': passed ? parsed['onSuccess'] : parsed['onFail'],
    'roll': rolled,
    'loss': rolled['total'],
    'before': before,
    'after': after,
    'maxSan': maxSan,
  };
}

/// 疯狂提示。**只提示，不自动编剧情后果**（需求 §7.5）。
///
/// 第 ② 条用「累计 × 5 ≥ 当日开始 SAN」比较，不做除法取整 ——
/// 取整会让 1/5 的边界在奇数上忽左忽右，玩家会认为系统算错了。
Map<String, Object?> _insanityFlags(Map<String, Object?> opts) {
  final loss = _num(opts['loss']) < 0 ? 0 : _num(opts['loss']);
  final dayStart = _num(opts['dayStartSan']) < 0 ? 0 : _num(opts['dayStartSan']);
  final dayLossSoFar =
      _num(opts['dayLossSoFar']) < 0 ? 0 : _num(opts['dayLossSoFar']);
  final dayTotal = dayLossSoFar + loss;

  final temporary = loss >= 5;
  final indefinite = dayStart > 0 && dayTotal * 5 >= dayStart;
  final flags = <String, Object?>{
    'loss': loss,
    'dayStartSan': dayStart,
    'dayTotal': dayTotal,
    'temporary': temporary,
    'temporaryReason': temporary
        ? '单次理智损失 $loss 点（≥ 5），按规则应进行 INT 检定判定临时疯狂'
        : '',
    'indefinite': indefinite,
    'indefiniteReason': '',
    'threshold': dayStart > 0 ? (dayStart / 5).ceil() : 0,
  };
  if (indefinite) {
    flags['indefiniteReason'] = '当天累计理智损失 $dayTotal 点，'
        '达到当天开始理智（$dayStart）的五分之一（${flags['threshold']} 点），'
        '应判定不定性疯狂';
  }
  return flags;
}

// ------------------------------------------------------------
// 9. 生命值与伤势
// ------------------------------------------------------------

const Map<String, String> _damageStateText = <String, String>{
  'normal': '存活',
  'unconscious': '昏迷',
  'dying': '濒死',
  'dead': '死亡',
};

/// 单次伤害结算。**只算状态与提示，不改角色对象**。
///
///   · 单次伤害 ≥ 最大 HP 的一半 → 重大伤口，需做 CON 检定
///   · 单次伤害 **> 最大 HP** → 致死（恰等于上限 → 重伤 → 濒死）
///   · HP 归零且**有**重大伤口 → 濒死；**没有** → 昏迷
Map<String, Object?> _damageFlags(Map<String, Object?> opts) {
  final dmg = _num(opts['damage']) < 0 ? 0 : _num(opts['damage']);
  final maxHP = _num(opts['maxHP']) < 1 ? 1 : _num(opts['maxHP']);
  final before = _num(opts['currentHP']) < 0 ? 0 : _num(opts['currentHP']);
  final hadMajor = jsTruthy(opts['majorWound']);

  final majorWound = dmg * 2 >= maxHP;
  final hasMajor = hadMajor || majorWound;
  final lethal = dmg > maxHP;
  var after = before - dmg;
  if (after < 0) after = 0;

  var state = 'normal';
  if (lethal) {
    state = 'dead';
  } else if (after == 0) {
    state = hasMajor ? 'dying' : 'unconscious';
  }

  return <String, Object?>{
    'damage': dmg,
    'before': before,
    'after': after,
    'maxHP': maxHP,
    'majorWound': majorWound,
    'hasMajorWound': hasMajor,
    'lethal': lethal,
    'needsConCheck': majorWound && !lethal,
    'state': state,
    'stateText': _damageStateText[state],
    'requireFirstAid': state == 'dying' || state == 'unconscious',
    'summary': _buildDamageSummary(
      dmg,
      before,
      after,
      maxHP,
      majorWound,
      lethal,
      _damageStateText[state]!,
    ),
  };
}

String _buildDamageSummary(
  int dmg,
  int before,
  int after,
  int maxHP,
  bool major,
  bool lethal,
  String stateText,
) {
  var s = '受到 $dmg 点伤害，HP $before → $after（上限 $maxHP）';
  if (lethal) {
    s += '　·　单次伤害达到最大生命值，触发致死结算';
  } else if (major) {
    s += '　·　单次伤害达到最大生命值的一半，构成重大伤口，需做 CON 检定';
  }
  s += '　·　当前状态：$stateText';
  return s;
}

/// 濒死角色的每轮 CON 检定解读：成功 → 本轮稳定；失败 → 死亡。
Map<String, Object?> _dyingRoundCheck(Object? con, [JsRng? rng]) {
  final r = _check(<String, Object?>{
    'base': _num(con),
    'difficulty': 'regular',
    'kind': 'combat',
    'label': '濒死 CON 检定',
    'rng': rng,
  });
  final passed = jsTruthy(r['passed']);
  return <String, Object?>{
    'check': r,
    'stable': passed,
    'dead': !passed,
    'summary': passed ? 'CON 检定成功，本轮伤势稳定，仍处于濒死' : 'CON 检定失败 —— 死亡',
  };
}

/// 临时疯狂发作判定（单次 SAN 损失 ≥ 5 时触发）。
///
/// 只做 INT 检定与「是否理解」的判定 —— **症状表抽取**由调用方负责。
Map<String, Object?> _temporaryInsanityCheck(Object? intValue, [JsRng? rng]) {
  final chk = _check(<String, Object?>{
    'base': _num(intValue),
    'difficulty': 'regular',
    'kind': 'attribute',
    'label': '临时疯狂 INT 检定',
    'rng': rng,
  });
  final passed = jsTruthy(chk['passed']);
  return <String, Object?>{
    'check': chk,
    'understood': passed,
    'summary': passed
        ? 'INT 检定成功（掷 ${jsStr(chk['value'])} ≤ ${jsStr(chk['base'])}）'
            '—— 理解了眼前的事，进入疯狂发作'
        : 'INT 检定失败（掷 ${jsStr(chk['value'])} > ${jsStr(chk['base'])}）'
            '—— 未能理解，暂时压抑',
  };
}

/// 疯狂发作的持续轮数：规则书 1D10。
int _boutRounds([JsRng? rng]) => 1 + (_pickRng(rng)() * 10).floor();

// ------------------------------------------------------------
// 12. 角色卡取值
// ------------------------------------------------------------

/// 属性中文名 / 缩写 → key（与 rules-coc7.js 的 CN2KEY 同口径）。
const Map<String, String> _attrCn2Key = <String, String>{
  '力量': 'str',
  'str': 'str',
  'STR': 'str',
  '体质': 'con',
  'con': 'con',
  'CON': 'con',
  '体型': 'siz',
  'siz': 'siz',
  'SIZ': 'siz',
  '敏捷': 'dex',
  'dex': 'dex',
  'DEX': 'dex',
  '外貌': 'app',
  'app': 'app',
  'APP': 'app',
  '智力': 'int',
  '灵感': 'int',
  'int': 'int',
  'INT': 'int',
  '意志': 'pow',
  'pow': 'pow',
  'POW': 'pow',
  '教育': 'edu',
  'edu': 'edu',
  'EDU': 'edu',
  '幸运': 'luck',
  '运气': 'luck',
  'luck': 'luck',
  'LUCK': 'luck',
};

/// 技能别名白名单（保守）。别名**值**一律用半角括号；匹配前会归一括号宽度。
const Map<String, String> _skillAlias = <String, String>{
  '斗殴': '格斗(斗殴)',
  '擒抱': '格斗(擒抱)',
  '踢击': '格斗(踢)',
  '踢': '格斗(踢)',
  '射击': '射击(手枪)',
  '手枪': '射击(手枪)',
  '步枪': '射击(步枪)',
  '霰弹枪': '射击(霰弹枪)',
  '冲锋枪': '射击(冲锋枪)',
  '机枪': '射击(机枪)',
  '弓': '射击(弓)',
  '弩': '射击(弩)',
  '侦察': '侦查',
  '图书馆': '图书馆使用',
  '计算机': '计算机使用',
  '开锁': '锁匠',
};

final RegExp _reOpenBrackets = RegExp(r'[（【〔〖［｛]');
final RegExp _reCloseBrackets = RegExp(r'[）】〕〗］｝]');
final RegExp _reSquareOpen = RegExp(r'\[');
final RegExp _reSquareClose = RegExp(r'\]');
final RegExp _reAllSpace = RegExp(r'[\s\u3000]');
final RegExp _reLeadPunct = RegExp(r'^[·.．、,，;；:：\-—_/｜|]+');
final RegExp _reTailPunct = RegExp(r'[·.．、,，;；:：\-—_/｜|]+$');
final RegExp _reSkillSplit = RegExp(r'[（(【〔〖［｛\[]|[｜|]');
final RegExp _reSpecs =
    RegExp(r'[（(【〔〖［｛\[]([^）)】〕〗］｝\]]*)[）)】〕〗］｝\]]');
final RegExp _reSpecSplit = RegExp(r'[｜|／/、,，]');

/// 技能名归一：括号宽度统一成半角 `()`，去所有空白与首尾分隔标点，小写。
String _normSkillName(Object? s) {
  var str = s == null ? '' : jsStr(s);
  str = str
      .replaceAll(_reOpenBrackets, '(')
      .replaceAll(_reCloseBrackets, ')')
      .replaceAll(_reSquareOpen, '(')
      .replaceAll(_reSquareClose, ')');
  str = str.replaceAll(_reAllSpace, '');
  str = str.replaceFirst(_reLeadPunct, '').replaceFirst(_reTailPunct, '');
  return str.toLowerCase();
}

/// 技能名的「基名」：去掉括号及其内容，或用 ｜ 分隔的开头片段。
String _skillBase(Object? s) {
  final n = (s == null ? '' : jsStr(s)).trim();
  final m = _reSkillSplit.firstMatch(n);
  return (m == null ? n : n.substring(0, m.start)).trim();
}

/// 拆出技能名的**子类名**（括号里的内容，可能多个）。`'格斗（斗殴）'` → `['斗殴']`
List<String> _skillSpecs(Object? s) {
  final raw = s == null ? '' : jsStr(s);
  final specs = <String>[];
  for (final m in _reSpecs.allMatches(raw)) {
    for (final x in (m.group(1) ?? '').split(_reSpecSplit)) {
      final t = x.trim();
      if (t.isNotEmpty) specs.add(t);
    }
  }
  return specs;
}

int? _totalOfSkill(Object? s) {
  if (s is! Map) return null;
  final m = asMap(s);
  final v = m['total'] ?? m['value'];
  if (v == null) return null;
  return jsParseInt(v);
}

/// 从角色卡 sheet 按技能名取值。查不到返回 null。
///
/// 匹配档位（依次，命中多个即判为歧义 → null）：
///   ① 精确名 ② 别名 ③ 基名相等 ④ 子类名相等
int? _skillValue(Object? sheet, Object? skillName) {
  if (sheet is! Map) return null;
  final sh = asMap(sheet);
  final skillsRaw = sh['skills'];
  if (skillsRaw is! List || skillsRaw.isEmpty) return null;
  final q = _normSkillName(skillName);
  if (q.isEmpty) return null;

  // ① 精确名（忽略括号宽度、空白与大小写）
  final exact = skillsRaw
      .where((s) => s is Map && _normSkillName(asMap(s)['name']) == q)
      .toList();
  if (exact.length == 1) return _totalOfSkill(exact[0]);
  if (exact.length > 1) return null;

  // ② 别名（键先按原样、再按归一命中；别名值按归一比较 → 全/半角括号等价）
  final aliasKey = (skillName == null ? '' : jsStr(skillName)).trim();
  final alias = _skillAlias[aliasKey] ?? _skillAlias[q];
  if (alias != null) {
    final byAlias = skillsRaw
        .where((s) => s is Map && _normSkillName(asMap(s)['name']) == _normSkillName(alias))
        .toList();
    if (byAlias.length == 1) return _totalOfSkill(byAlias[0]);
    if (byAlias.length > 1) return null;
  }

  // ③ 基名相等 / ④ 子类名相等（并集；唯一命中才算，歧义仍返回 null）
  final qBase = _normSkillName(_skillBase(skillName));
  final cands = <Object?>[];
  for (final s in skillsRaw) {
    if (s is! Map) continue;
    final name = asMap(s)['name'];
    final sBase = _normSkillName(_skillBase(name));
    if (qBase.isNotEmpty && sBase.isNotEmpty && sBase == qBase) {
      cands.add(s);
      continue;
    }
    var hit = false;
    for (final spec in _skillSpecs(name)) {
      if (_normSkillName(spec) == q) {
        hit = true;
        break;
      }
    }
    if (hit) cands.add(s);
  }
  if (cands.length == 1) return _totalOfSkill(cands[0]);
  return null;
}

/// 从角色卡 sheet 按属性名取值。name 支持中文（'力量'）或 key（'str'）。
int? _attrValue(Object? sheet, Object? name) {
  if (sheet is! Map) return null;
  final sh = asMap(sheet);
  final attrsRaw = sh['attrs'];
  if (attrsRaw is! Map) return null;
  final attrs = asMap(attrsRaw);
  final raw = (name == null ? '' : jsStr(name)).trim();
  if (raw.isEmpty) return null;
  var key = _attrCn2Key[raw] ?? _attrCn2Key[raw.toUpperCase()];
  if (key == null) {
    if (attrs.containsKey(raw)) {
      key = raw;
    } else if (attrs.containsKey(raw.toLowerCase())) {
      key = raw.toLowerCase();
    } else if (attrs.containsKey(raw.toUpperCase())) {
      key = raw.toUpperCase();
    }
  }
  if (key == null || !attrs.containsKey(key)) return null;
  final v = attrs[key];
  if (v == null) return null;
  return jsParseInt(v);
}

// ------------------------------------------------------------
// 13. 场景检定步骤
// ------------------------------------------------------------

final RegExp _reEndToken = RegExp(r'^(end|done|结束)$', caseSensitive: false);

/// 归一化一个分支（onSuccess / onFailure）。
Map<String, Object?> _normBranch(Object? bRaw) {
  final b = asMap(bRaw);
  final next = b['next'];
  final hasNext = !(next == null || jsStr(next).trim().isEmpty);
  // 'end' / 'done' / '结束' 视为终止符；仍**原样回传** next（E 线继续用 next==='end' 判断）
  final isEnd = hasNext && _reEndToken.hasMatch(jsStr(next).trim());
  return <String, Object?>{
    'damage': (b['damage'] == null || jsStr(b['damage']).trim().isEmpty)
        ? null
        : jsStr(b['damage']),
    'note': b['note'] == null ? '' : jsStr(b['note']),
    'next': hasNext ? next : null,
    'done': !hasNext || isEnd,
  };
}

/// 求值一个场景检定步骤的执行计划：只决定「该谁掷、掷什么」，不掷骰。
Map<String, Object?> _sceneStepPlan(Object? stepRaw) {
  final step = asMap(stepRaw);
  final title = step['title'];
  final desc = step['desc'];
  final skill = step['skill'];
  return <String, Object?>{
    'id': step['id'],
    'title': jsTruthy(title) ? jsStr(title) : '',
    'desc': jsTruthy(desc) ? jsStr(desc) : '',
    'targetSeat': step['targetSeat'],
    'skill': jsTruthy(skill) ? jsStr(skill) : '',
    // ★ P17 KP-2：`difficulty` 在模型/载荷里是**全大写**（`REGULAR/HARD/EXTREME/
    //   CRITICAL`），而 `DIFFICULTY` 的键是**小写**，`_normDifficulty` 对未知值
    //   回落 `regular` ⇒ 不先转小写，困难/极难步会被静默当成常规步判成功
    //   （老 APP `room-rules.js` 同款退化）。这里只在**调用点**归一，
    //   `_normDifficulty` 本体与 `DIFFICULTY` 的键一字不动（`room_rules.json`
    //   的 oracle 逐字节钉死 `normDifficulty('HARD') == 'regular'`）。
    'difficulty': _normDifficulty(jsStr(step['difficulty']).trim().toLowerCase()),
    'bonus': _num(step['bonus']) < 0 ? 0 : _num(step['bonus']),
    'penalty': _num(step['penalty']) < 0 ? 0 : _num(step['penalty']),
    'branches': <String, Object?>{
      'success': _normBranch(step['onSuccess']),
      'failure': _normBranch(step['onFailure']),
    },
  };
}

/// 把 check() 的成功等级（数字）或字符串键归一成 LEVEL 数字。
num _toLevelNumber(Object? level) {
  if (level is num) return level;
  if (level == null) return CocRules.LEVEL['FAIL']!;
  final k = jsStr(level).trim().toUpperCase();
  if (CocRules.LEVEL.containsKey(k)) return CocRules.LEVEL[k]!;
  final lower = jsStr(level).trim().toLowerCase();
  for (final entry in CocRules.LEVEL_KEY.entries) {
    if (entry.value == lower) return jsParseInt(entry.key) ?? 0;
  }
  return CocRules.LEVEL['FAIL']!;
}

/// 按成功等级挑分支并给出后续动作。
Map<String, Object?> _sceneStepResolve(Object? step, Object? level) {
  final plan = _sceneStepPlan(step);
  final diff = _normDifficulty(plan['difficulty']);
  final required = _num(CocRules.DIFFICULTY[diff]!['required']);
  final lvl = _toLevelNumber(level);
  final success = lvl >= required;
  final branches = asMap(plan['branches']);
  final branch = asMap(branches[success ? 'success' : 'failure']);
  return <String, Object?>{
    'stepId': plan['id'],
    'level': lvl,
    'required': required,
    'success': success,
    'branch': success ? 'success' : 'failure',
    'critical': lvl == CocRules.LEVEL['CRITICAL'],
    'fumble': lvl == CocRules.LEVEL['FUMBLE'],
    // ⚠️ 必须走 `jsStr`：`lvl` 是 `num`，double 形态（如 4.0）用 `'$lvl'`
    // 会拼成 "4.0"，而 LEVEL_TEXT 的键是 '4' → 取到空串（文案丢等级名）。
    // 老 APP `room-rules.js:1399` 是 `LEVEL_TEXT[String(lvl)]`，JS 里
    // `String(4.0) === '4'`，`jsStr` 正是该语义。
    'levelText': CocRules.LEVEL_TEXT[jsStr(lvl)] ?? '',
    'damage': branch['damage'],
    'note': branch['note'],
    'next': branch['next'],
    'done': branch['done'],
  };
}
