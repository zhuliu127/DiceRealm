// ============================================================
// room_rules_combat.dart — 行动顺序 / 攻击结算（P0-R12 / R13）
// （对应 room-rules.js 第 10、11 节）
//
// rng 消耗顺序（测试构造确定性骰源时依赖此顺序）：
//   ① 攻击方检定 2 次  ② 防御方检定 2 次（mode ≠ none）
//   ③ 伤害主掷 ④ 伤害加值 ⑤ 贯穿追加骰 ⑥ 平局重掷（每轮 4 次，最多 10 轮）
// ============================================================
part of 'room_rules.dart';

/// 契约 §4.1 要求的 level 取值：常规成功写作 'success'（区别于 LEVEL_KEY 的 'regular'）。
const Map<String, String> _attackLevelKey = <String, String>{
  '5': 'critical',
  '4': 'extreme',
  '3': 'hard',
  '2': 'success',
  '0': 'fail',
  '-1': 'fumble',
};

/// 默认行动顺序：按 DEX 从高到低；已**准备好**的枪械按 DEX+50 计算。
///
/// 每轮多次行动的单位**必须展开成多个行动槽**，不能完成一次行动就永久消失。
Map<String, Object?> _initiativeOrder(
  Object? actors, [
  Map<String, Object?>? opts,
]) {
  final o = opts ?? const <String, Object?>{};
  final useReady = o['useReadyFirearm'] != false;

  final list = <Map<String, Object?>>[];
  for (final aRaw in asList(actors)) {
    final a = asMap(aRaw);
    final dex = _num(a['dex']);
    final ready = jsTruthy(a['readyFirearm']);
    final effDex = (useReady && ready) ? dex + 50 : dex;
    final apRaw = _num(a['actionsPerRound']);
    final ap = apRaw == 0 ? 1 : apRaw;
    final actions = ap < 1 ? 1 : ap;
    final moRaw = a['manualOrder'];
    final manual = (moRaw == null || jsStr(moRaw).trim().isEmpty)
        ? null
        : _num(moRaw);
    final name = a['name'];
    list.add(<String, Object?>{
      'id': a['id'],
      'name': jsTruthy(name) ? jsStr(name) : '',
      'dex': dex,
      'readyFirearm': ready,
      'effDex': effDex,
      'actionsPerRound': actions,
      'manualOrder': manual,
      'manual': manual != null,
      'note': (useReady && ready) ? '已准备枪械：按 DEX+50 行动' : '',
    });
  }

  list.sort((x, y) {
    final xm = x['manual'] == true;
    final ym = y['manual'] == true;
    if (xm && ym) return _num(x['manualOrder']) - _num(y['manualOrder']);
    if (xm) return -1;
    if (ym) return 1;
    final xe = _num(x['effDex']);
    final ye = _num(y['effDex']);
    if (ye != xe) return ye - xe;
    final xd = _num(x['dex']);
    final yd = _num(y['dex']);
    if (yd != xd) return yd - xd;
    return jsStr(x['name']).compareTo(jsStr(y['name']));
  });

  final queue = <Map<String, Object?>>[];
  for (final a in list) {
    final total = _num(a['actionsPerRound']);
    for (var i = 0; i < total; i++) {
      queue.add(<String, Object?>{
        'id': a['id'],
        'name': a['name'],
        'dex': a['dex'],
        'readyFirearm': a['readyFirearm'],
        'effDex': a['effDex'],
        'actionsPerRound': a['actionsPerRound'],
        'manualOrder': a['manualOrder'],
        'manual': a['manual'],
        'note': a['note'],
        'slot': i + 1,
        'totalSlots': total,
        // 是否该角色本轮的最后一次行动
        'lastSlot': i + 1 == total,
      });
    }
  }

  final summary = <String>[];
  for (var i = 0; i < queue.length; i++) {
    final q = queue[i];
    final extra = _num(q['totalSlots']) > 1
        ? '，第 ${q['slot']}/${q['totalSlots']} 次行动'
        : '';
    summary.add(
      '${i + 1}. ${jsTruthy(q['name']) ? q['name'] : q['id']}'
      '（DEX ${q['dex']}$extra）',
    );
  }

  return <String, Object?>{
    'order': queue,
    'actors': list,
    'manualCount': list.where((a) => a['manual'] == true).length,
    'summary': summary.join('　'),
  };
}

/// 推进到下一个行动项。一轮走完回到队首、回合号 +1。**不删任何条目**。
Map<String, Object?> _advanceTurn(
  Object? index,
  Object? round,
  Object? queueLength,
) {
  final nRaw = _num(queueLength);
  final n = nRaw < 1 ? 1 : nRaw;
  var i = _num(index);
  final rRaw = _num(round);
  var r = rRaw == 0 ? 1 : rRaw;
  if (r < 1) r = 1;
  i++;
  var wrapped = false;
  if (i >= n) {
    i = 0;
    r++;
    wrapped = true;
  }
  return <String, Object?>{
    'index': i,
    'round': r,
    'roundWrapped': wrapped,
  };
}

/// 结算一次攻击（契约 §4.1）。
///
///   · 攻击方没成功 → 一律落空；
///   · 无人防御 → 纯命中；闪避/反击 → 模式敏感对抗裁定；
///   · 远程目标不能反击（fightback 降级为 dodge）；
///   · 贯穿：攻击方极难/大成功时伤害取最大值并追加一次伤害骰；
///   · 护甲在应用前扣除，最低 0。
Map<String, Object?> _resolveAttack(Map<String, Object?> o) {
  final attackSpec = asMap(o['attack']);
  final defenseSpec = asMap(o['defense']);
  final rng = _rngOf(o['rng']);

  final attackLabel = attackSpec['name'];
  // ① 攻击方检定 —— kind:'combat'（不可推动、不可花幸运）
  final attack = _check(<String, Object?>{
    'base': _num(attackSpec['value']),
    'difficulty': o['difficulty'],
    'bonus': o['bonus'],
    'penalty': o['penalty'],
    'kind': 'combat',
    'label': jsTruthy(attackLabel) ? attackLabel : '攻击',
    'secret': jsTruthy(o['secret']),
    'value': attackSpec['roll'],
    'rng': o['rng'],
    'critMax': o['critMax'],
    'fumbleMin': o['fumbleMin'],
  });

  // 远程目标不能反击：把 fightback 降级为 dodge
  final ranged = o['ranged'] == true || attackSpec['ranged'] == true;
  final requestedMode = _normMode(defenseSpec['mode']);
  var mode = requestedMode;
  var coercedFromFightback = false;
  if (ranged && mode == 'fightback') {
    mode = 'dodge';
    coercedFromFightback = true;
  }

  // ② 防御方检定（闪避 / 反击都按常规难度）
  Map<String, Object?>? defense;
  if (mode != 'none') {
    final defLabel = defenseSpec['name'];
    defense = _check(<String, Object?>{
      'base': _num(defenseSpec['value']),
      'difficulty': 'regular',
      'kind': 'combat',
      'label': jsTruthy(defLabel) ? defLabel : (mode == 'dodge' ? '闪避' : '反击'),
      'value': defenseSpec['roll'],
      'rng': o['rng'],
      'critMax': o['critMax'],
      'fumbleMin': o['fumbleMin'],
    });
  }

  // 结局判定（模式敏感的 opposedAttack 自己跑完重掷循环）
  String outcome;
  Map<String, Object?>? compare;
  List<Object?> rerolls = <Object?>[];
  if (jsTruthy(attack['passed']) != true) {
    outcome = CocRules.OUTCOME['MISS']!;
  } else if (mode == 'none') {
    outcome = CocRules.OUTCOME['HIT']!;
  } else {
    compare = _opposedAttack(attack, defense, <String, Object?>{
      'mode': mode,
      'rng': o['rng'],
    });
    rerolls = asList(compare['rounds']);
    if (compare['winner'] == 'a') {
      outcome = CocRules.OUTCOME['ATTACKER_WINS']!;
    } else if (mode == 'dodge') {
      outcome = CocRules.OUTCOME['MISS']!; // 闪避胜出 → 免伤
    } else {
      outcome = CocRules.OUTCOME['DEFENDER_WINS']!; // 反击胜出 → 反击方造成伤害
    }
  }

  final attackerDeals = outcome == CocRules.OUTCOME['HIT'] ||
      outcome == CocRules.OUTCOME['ATTACKER_WINS'];
  final defenderDeals = outcome == CocRules.OUTCOME['DEFENDER_WINS'];
  final String? damageBy = attackerDeals ? 'attacker' : (defenderDeals ? 'defender' : null);

  // ③④⑤ 伤害结算。反击时优先用防御方自己的伤害式。
  final Map<String, Object?> dmgSpec;
  if (defenderDeals && defenseSpec['damage'] is Map) {
    dmgSpec = asMap(defenseSpec['damage']);
  } else {
    dmgSpec = asMap(o['damage']);
  }
  final exprRaw = dmgSpec['expr'];
  final expr = (exprRaw == null || jsStr(exprRaw).trim().isEmpty)
      ? '0'
      : jsStr(exprRaw);
  final db = dmgSpec['db'];
  final armorRaw = asMap(o['armor'])['value'];
  final armorValue = _num(armorRaw) < 0 ? 0 : _num(armorRaw);
  final attackLevel = _num(attack['level']);
  final impaleApplies = attackerDeals &&
      jsTruthy(o['impale']) &&
      (attackLevel == CocRules.LEVEL['EXTREME'] ||
          attackLevel == CocRules.LEVEL['CRITICAL']);

  final damage = <String, Object?>{
    'raw': 0,
    'expr': expr,
    'dbDice': null,
    'impale': false,
    'armor': armorValue,
    'applied': 0,
  };
  if (attackerDeals || defenderDeals) {
    final main = _rollExpr(expr, rng);
    final dbRoll = _rollDamageBonus(db, rng);
    damage['main'] = main;
    damage['dbDice'] = dbRoll;
    var raw = _num(main['total']) + _num(dbRoll['total']);
    if (impaleApplies) {
      // 贯穿 = 武器伤害**最大值** + **最大 DB** + 追加一次伤害骰
      final imp = _impaleDamage(expr, db, rng);
      if (imp['ok'] == true) {
        damage['extra'] = imp['extra'];
        damage['impale'] = true;
        damage['impaleDbMax'] = imp['dbMax'];
        raw = _num(imp['raw']);
      }
    }
    damage['raw'] = raw;
    final applied = raw - armorValue;
    damage['applied'] = applied < 0 ? 0 : applied;
  }

  // flags 复用 damageFlags（需要目标 HP；缺省时给出 unknown 占位）
  final target = asMap(o['target']);
  final maxHPRaw = o.containsKey('maxHP') ? o['maxHP'] : target['maxHP'];
  final currentHPRaw =
      o.containsKey('currentHP') ? o['currentHP'] : target['currentHP'];
  final maxHP = _num(maxHPRaw);
  final currentHP = _num(currentHPRaw);
  final Map<String, Object?> flags;
  if (maxHP > 0) {
    final df = _damageFlags(<String, Object?>{
      'damage': damage['applied'],
      'maxHP': maxHP,
      'currentHP': currentHP,
      'majorWound': jsTruthy(target['majorWound']),
    });
    flags = <String, Object?>{
      'majorWound': df['hasMajorWound'],
      'dying': df['state'] == 'dying',
      'unconscious': df['state'] == 'unconscious',
      'dead': df['state'] == 'dead',
      'state': df['state'],
      'stateText': df['stateText'],
      'needsConCheck': df['needsConCheck'],
      'lethal': df['lethal'],
      'detail': df,
    };
  } else {
    flags = <String, Object?>{
      'majorWound': false,
      'dying': false,
      'unconscious': false,
      'dead': false,
      'unknown': true,
    };
  }

  final level = _attackLevelKey['${_num(attack['level'])}'] ?? 'fail';

  final result = <String, Object?>{
    'attack': attack,
    'defense': defense,
    'outcome': outcome,
    'damage': damage,
    'level': level,
    'flags': flags,
    'mode': mode,
    'ranged': ranged,
    'coercedFromFightback': coercedFromFightback,
    'compare': compare,
    'rerolls': rerolls,
    'damageBy': damageBy,
  };
  result['summary'] = _buildAttackSummary(result);
  return result;
}

/// 组装一句人类可读的攻击结论（界面直接显示）。
String _buildAttackSummary(Map<String, Object?> r) {
  final s = <String>[];
  final attack = asMap(r['attack']);
  final defense = r['defense'] is Map ? asMap(r['defense']) : null;
  final damage = asMap(r['damage']);
  final flags = asMap(r['flags']);

  final label = jsTruthy(attack['label']) ? attack['label'] : '攻击';
  s.add('攻击方「$label」${jsStr(attack['levelText'])}'
      '（掷 ${jsStr(attack['value'])}，本次要求 ≤ ${jsStr(attack['target'])}）');
  if (r['coercedFromFightback'] == true) {
    s.add('远程攻击：目标不能反击，按闪避处理');
  }
  if (r['mode'] == 'none') {
    s.add('目标未做防御');
  } else if (defense != null) {
    s.add('防御方「${jsStr(defense['label'])}」${jsStr(defense['levelText'])}'
        '（掷 ${jsStr(defense['value'])}）');
  }

  final armor = _num(damage['armor']);
  final raw = _num(damage['raw']);
  final absorbed = armor < raw ? armor : raw;
  final outcome = r['outcome'];
  if (outcome == CocRules.OUTCOME['HIT'] ||
      outcome == CocRules.OUTCOME['ATTACKER_WINS']) {
    var t = '→ 命中，造成 ${jsStr(damage['applied'])} 点伤害'
        '（伤害骰 $raw，护甲 $armor 点，实际减免 $absorbed）';
    if (jsTruthy(damage['impale'])) {
      t += '，贯穿：伤害取最大值并追加一次伤害骰';
    }
    s.add(t);
  } else if (outcome == CocRules.OUTCOME['DEFENDER_WINS']) {
    s.add('→ 反击成功，由防御方造成 ${jsStr(damage['applied'])} 点伤害'
        '（伤害骰 $raw，护甲 $armor 点，实际减免 $absorbed）');
  } else if (r['mode'] == 'dodge' &&
      defense != null &&
      jsTruthy(defense['passed'])) {
    s.add('→ 闪避成功，攻击被躲开，未造成伤害');
  } else {
    s.add('→ 攻击落空，未造成伤害');
  }
  final st = flags['state'];
  if (st != null && st != 'normal') {
    s.add('目标状态：${jsStr(flags['stateText'])}');
  }
  return s.join('　·　');
}
