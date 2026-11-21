// ============================================================
// room_rules_opposed.dart — 对抗检定（P0-R08）
// （对应 room-rules.js 第 6 节）
//
// 三条规则：
//   · 成功等级高者胜；同级则**对应技能值更高**者胜；
//   · 数值也相同 → 双方各重掷 1D100，**低者**胜；
//   · 攻击对抗**模式敏感**：反击同级 → 攻方胜；闪避同级 → 攻方败。
// ============================================================
part of 'room_rules.dart';

/// 归一化防御方式：只有 `dodge` / `fightback` 是有效防御，其余一律 `none`。
String _normMode(Object? mode) {
  final m = (mode == null ? '' : jsStr(mode)).trim().toLowerCase();
  if (m == 'dodge' || m == '闪避') return 'dodge';
  if (m == 'fightback' || m == 'fight_back' || m == 'fight back' || m == '反击') {
    return 'fightback';
  }
  return 'none';
}

/// 比较两方（通用对抗，不自行重掷：平局交调用方处理）。
Map<String, Object?> _opposed(Object? aRaw, Object? bRaw) {
  if (aRaw is! Map || bRaw is! Map) {
    return <String, Object?>{'ok': false, 'reason': '对抗检定需要两方的检定结果'};
  }
  final a = asMap(aRaw);
  final b = asMap(bRaw);
  final base = <String, Object?>{
    'ok': true,
    'aLevel': a['level'],
    'bLevel': b['level'],
    'aLevelText': a['levelText'],
    'bLevelText': b['levelText'],
  };
  final al = _num(a['level']);
  final bl = _num(b['level']);
  if (al > bl) {
    base['winner'] = 'a';
    base['decidedBy'] = 'level';
    base['reason'] = '成功等级更高（${jsStr(a['levelText'])} > ${jsStr(b['levelText'])}）';
    return base;
  }
  if (bl > al) {
    base['winner'] = 'b';
    base['decidedBy'] = 'level';
    base['reason'] = '成功等级更高（${jsStr(b['levelText'])} > ${jsStr(a['levelText'])}）';
    return base;
  }
  final ab = _num(a['base']);
  final bb = _num(b['base']);
  if (ab > bb) {
    base['winner'] = 'a';
    base['decidedBy'] = 'value';
    base['reason'] = '成功等级相同，技能值更高（${jsStr(a['base'])} > ${jsStr(b['base'])}）';
    return base;
  }
  if (bb > ab) {
    base['winner'] = 'b';
    base['decidedBy'] = 'value';
    base['reason'] = '成功等级相同，技能值更高（${jsStr(b['base'])} > ${jsStr(a['base'])}）';
    return base;
  }
  base['winner'] = null;
  base['tie'] = true;
  base['needsReroll'] = true;
  base['decidedBy'] = 'reroll';
  base['reason'] = '成功等级与技能值都相同，双方重掷 1D100，骰值**较低**者胜';
  return base;
}

/// 平局重掷的裁决：低者胜。掷出相同时继续重掷。
Map<String, Object?> _opposedReroll(Object? aRoll, Object? bRoll) {
  final a = _clampValue(aRoll);
  final b = _clampValue(bRoll);
  if (a == b) {
    return <String, Object?>{
      'winner': null,
      'tie': true,
      'needsReroll': true,
      'aRoll': a,
      'bRoll': b,
      'reason': '双方都掷出 $a，继续重掷',
    };
  }
  return <String, Object?>{
    'winner': a < b ? 'a' : 'b',
    'tie': false,
    'needsReroll': false,
    'aRoll': a,
    'bRoll': b,
    'reason': '骰值较低者胜（$a vs $b）',
  };
}

/// 攻击对抗的**模式敏感**裁定。
///
/// 与 [_opposed] 的区别：本函数**自己**跑完重掷循环并把逐轮明细写进 `rounds[]`，
/// 调用方无需再循环 —— 这样「反击/闪避同级短路、不重掷」的规则才不会被
/// 调用方的通用重掷循环抹掉。
Map<String, Object?> _opposedAttack(
  Object? aRaw,
  Object? bRaw, [
  Map<String, Object?>? oRaw,
]) {
  final o = oRaw ?? const <String, Object?>{};
  final rec = <Map<String, Object?>>[];
  final nReroll = _num(o['rerollMax']);
  final rr = nReroll == 0 ? 10 : nReroll;
  final max = rr < 1 ? 1 : rr;

  if (aRaw is! Map || bRaw is! Map) {
    return <String, Object?>{
      'winner': null,
      'decidedBy': 'none',
      'rounds': rec,
      'reason': '对抗需要两方的检定结果',
    };
  }
  final a = asMap(aRaw);
  final b = asMap(bRaw);
  final al = _num(a['level']);
  final bl = _num(b['level']);
  if (al > bl) {
    return <String, Object?>{
      'winner': 'a',
      'decidedBy': 'level',
      'rounds': rec,
      'reason': '成功等级更高（${jsStr(a['levelText'])} > ${jsStr(b['levelText'])}）',
    };
  }
  if (bl > al) {
    return <String, Object?>{
      'winner': 'b',
      'decidedBy': 'level',
      'rounds': rec,
      'reason': '成功等级更高（${jsStr(b['levelText'])} > ${jsStr(a['levelText'])}）',
    };
  }
  final mode = _normMode(o['mode']);
  if (mode == 'fightback') {
    return <String, Object?>{
      'winner': 'a',
      'decidedBy': 'mode_fightback_tie',
      'rounds': rec,
      'reason': '反击：双方成功等级相同 → 攻击方（发起方）胜',
    };
  }
  if (mode == 'dodge') {
    return <String, Object?>{
      'winner': 'b',
      'decidedBy': 'mode_dodge_tie',
      'rounds': rec,
      'reason': '闪避：双方成功等级相同 → 攻击方败（被躲开、免伤）',
    };
  }
  final ab = _num(a['base']);
  final bb = _num(b['base']);
  if (ab > bb) {
    return <String, Object?>{
      'winner': 'a',
      'decidedBy': 'value',
      'rounds': rec,
      'reason': '成功等级相同，技能值更高（${jsStr(a['base'])} > ${jsStr(b['base'])}）',
    };
  }
  if (bb > ab) {
    return <String, Object?>{
      'winner': 'b',
      'decidedBy': 'value',
      'rounds': rec,
      'reason': '成功等级相同，技能值更高（${jsStr(b['base'])} > ${jsStr(a['base'])}）',
    };
  }
  for (var i = 0; i < max; i++) {
    final ar = _rollD100Value(o['rng']);
    final br = _rollD100Value(o['rng']);
    final String? w = (ar == br) ? null : (ar < br ? 'a' : 'b');
    rec.add(<String, Object?>{
      'round': i + 1,
      'aRoll': ar,
      'bRoll': br,
      'winner': w,
    });
    if (w != null) {
      return <String, Object?>{
        'winner': w,
        'decidedBy': 'reroll',
        'rounds': rec,
        'reason': '重掷：骰值较低者胜（$ar vs $br）',
      };
    }
  }
  return <String, Object?>{
    'winner': 'a',
    'decidedBy': 'reroll_fallback',
    'fallback': true,
    'rounds': rec,
    'reason': '达到重掷上限，按规则兜底判发起方胜',
  };
}

/// 通用对抗（技能/属性）：等价于 [opposedAttack] 的「无模式」分支。
Map<String, Object?> _opposedFull(
  Object? a,
  Object? b, [
  Map<String, Object?>? oRaw,
]) {
  final o = oRaw ?? const <String, Object?>{};
  final rm = o['rerollMax'];
  return _opposedAttack(a, b, <String, Object?>{
    'mode': 'none',
    'rng': o['rng'],
    'rerollMax': jsTruthy(rm) ? rm : 10,
  });
}

/// 掷一个百分骰并只取结果值（平局重掷用）。
int _rollD100Value(Object? rng) =>
    _num(_rollD100(<String, Object?>{'rng': rng})['value']);
