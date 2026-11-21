// ============================================================
// test/room_rules_oracle_test.dart — F01 全量等价性（CocRules 53 导出）
//
// 判据（T02）：
//   1) ≥420 例逐字段深比较全绿，且每例 `Lcg.used == randUsed`；
//   2) Q4 三种组合恒定：check(value:42)=2 / bonus:2=4 / ones+forcedTens=0，
//      各 3 个 seed，断言写死在这里；
//   3) 45 个方法 + 8 个常量 = 53 个导出成员 100% 有 handler。
//
// ⚠️ 禁止 contains / 模糊匹配 / 跳过字段（K14）：比较一律走 expectJsonMatch。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show Lcg;
import 'support/room_oracle.dart';

const CocRules _r = CocRules();

/// fixture 的 `const` 用例：按名字取常量
Object? _constOf(String name) {
  switch (name) {
    case 'version':
      return CocRules.version;
    case 'LEVEL':
      return CocRules.LEVEL;
    case 'LEVEL_TEXT':
      return CocRules.LEVEL_TEXT;
    case 'LEVEL_KEY':
      return CocRules.LEVEL_KEY;
    case 'DIFFICULTY':
      return CocRules.DIFFICULTY;
    case 'OUTCOME':
      return CocRules.OUTCOME;
    case 'JAM_TYPES':
      return CocRules.JAM_TYPES;
    case 'limits':
      return CocRules.limits;
    default:
      throw ArgumentError('未知常量 $name');
  }
}

Map<String, Object?> _m(Object? v) => asMap(v);

void main() {
  final fixture = RoomOracleFixture.load('room_rules.json');

  test('F01 规模：≥420 例', () {
    expect(fixture.cases.length, greaterThanOrEqualTo(420));
  });

  final handlers = <String, Object? Function(Map<String, Object?> args)>{
    'const': (a) => _constOf(a['name']! as String),

    // ---- 阈值与成功等级 ----
    'thresholds': (a) => _r.thresholds(a['base']),
    'targetOf': (a) => _r.targetOf(a['base'], a['difficulty']),
    'normDifficulty': (a) => _r.normDifficulty(a['d']),
    'fumbleRange': (a) => _r.fumbleRange(a['target'], _m(a['opts'])),
    'isFumble': (a) => _r.isFumble(a['value'], a['target'], _m(a['opts'])),
    'levelOf': (a) => _r.levelOf(a['value'], a['base'], a['target'], _m(a['opts'])),
    'critThresholdOf': (a) => _r.critThresholdOf(_m(a['opts'])),
    'fumbleThresholdOf': (a) => _r.fumbleThresholdOf(_m(a['opts'])),

    // ---- 掷骰 ----
    'rollD100': (a) => _r.rollD100(_m(a['opts'])),
    'combine': (a) => _r.combine(a['tens'], a['ones']),

    // ---- 检定 ----
    'check': (a) => _r.check(_m(a['opts'])),
    'describeCheck': (a) => _r.describeCheck(_r.check(_m(a['opts']))),
    'canPush': (a) =>
        _r.canPush(a['result'] == null ? null : _m(a['result']), a['kind']),
    'luckAllowed': (a) => _r.luckAllowed(a['kind']),
    'spendLuck': (a) => _r.spendLuck(<String, Object?>{
          'result': _r.check(_m(a['checkOpts'])),
          'amount': a['amount'],
          'luckAvailable': a['luckAvailable'],
        }),

    // ---- 对抗 ----
    'opposed': (a) =>
        _r.opposed(_r.check(_m(a['a'])), _r.check(_m(a['b']))),
    'opposedReroll': (a) => _r.opposedReroll(a['aRoll'], a['bRoll']),
    'opposedAttack': (a) => _r.opposedAttack(
          _r.check(_m(a['a'])),
          _r.check(_m(a['b'])),
          _m(a['o']),
        ),
    'opposedFull': (a) => _r.opposedFull(
          _r.check(_m(a['a'])),
          _r.check(_m(a['b'])),
          _m(a['o']),
        ),

    // ---- 骰式与伤害 ----
    'parseExpr': (a) => _r.parseExpr(a['expr']),
    'rollExpr': (a) => _r.rollExpr(a['expr']),
    'rollDamageBonus': (a) => _r.rollDamageBonus(a['expr']),
    'maxOfExpr': (a) => _r.maxOfExpr(a['expr']),
    'maxOfDamageBonus': (a) => _r.maxOfDamageBonus(a['expr']),
    'impaleDamage': (a) => _r.impaleDamage(a['expr'], a['db']),

    // ---- 连发 / 故障 ----
    'burstMaxOf': (a) => _r.burstMaxOf(a['perRound']),
    'isBurstWeapon': (a) => _r.isBurstWeapon(a['perRound']),
    'malfunctionThresholdOf': (a) => _r.malfunctionThresholdOf(a['weapon']),
    'malfunctionOf': (a) =>
        _r.malfunctionOf(a['weapon'], a['rollValue'], _m(a['opts'])),
    'defaultMalfunctionType': (a) => _r.defaultMalfunctionType(a['weapon']),
    'malfunctionEffect': (a) =>
        _r.malfunctionEffect(a['weapon'], a['type']),

    // ---- SAN / 伤势 ----
    'parseSanLoss': (a) => _r.parseSanLoss(a['expr']),
    'resolveSanCheck': (a) {
      final opts = Map<String, Object?>.from(_m(a['opts']));
      final cr = a['checkResult'];
      if (cr != null) {
        // 复现 dump 脚本里的「用已掷好的检定结果」路径（同一条随机序列）
        final crm = _m(cr);
        opts['checkResult'] = _r.check(<String, Object?>{
          'base': crm['base'],
          'value': crm['value'],
        });
      }
      return _r.resolveSanCheck(opts);
    },
    'insanityFlags': (a) => _r.insanityFlags(_m(a['opts'])),
    'damageFlags': (a) => _r.damageFlags(_m(a['opts'])),
    'dyingRoundCheck': (a) => _r.dyingRoundCheck(a['con']),
    'temporaryInsanityCheck': (a) => _r.temporaryInsanityCheck(a['intValue']),
    'boutRounds': (a) => _r.boutRounds(),

    // ---- 行动顺序 / 战斗结算 ----
    'initiativeOrder': (a) => _r.initiativeOrder(asList(a['actors']), _m(a['opts'])),
    'advanceTurn': (a) =>
        _r.advanceTurn(a['index'], a['round'], a['queueLength']),
    'resolveAttack': (a) => _r.resolveAttack(_m(a['o'])),

    // ---- 角色卡取值 ----
    'skillValue': (a) => _r.skillValue(a['sheet'], a['name']),
    'attrValue': (a) => _r.attrValue(a['sheet'], a['key']),

    // ---- 场景步骤 ----
    'sceneStepPlan': (a) => _r.sceneStepPlan(a['step']),
    'sceneStepResolve': (a) => _r.sceneStepResolve(a['step'], a['level']),
  };

  fixture.run(handlers);

  test('53 个导出成员 100% 有 handler（未知集合为空）', () {
    const constants = <String>[
      'version', 'LEVEL', 'LEVEL_TEXT', 'LEVEL_KEY',
      'DIFFICULTY', 'OUTCOME', 'JAM_TYPES', 'limits',
    ];
    const methods = <String>[
      'thresholds', 'targetOf', 'normDifficulty', 'fumbleRange', 'isFumble',
      'levelOf', 'critThresholdOf', 'fumbleThresholdOf', 'rollD100', 'combine',
      'check', 'describeCheck', 'canPush', 'luckAllowed', 'spendLuck', 'opposed',
      'opposedReroll', 'opposedAttack', 'opposedFull', 'parseExpr', 'rollExpr',
      'rollDamageBonus', 'maxOfExpr', 'maxOfDamageBonus', 'impaleDamage',
      'burstMaxOf', 'isBurstWeapon', 'malfunctionThresholdOf', 'malfunctionOf',
      'defaultMalfunctionType', 'malfunctionEffect', 'parseSanLoss',
      'resolveSanCheck', 'insanityFlags', 'damageFlags', 'dyingRoundCheck',
      'temporaryInsanityCheck', 'boutRounds', 'initiativeOrder', 'advanceTurn',
      'resolveAttack', 'skillValue', 'attrValue', 'sceneStepPlan',
      'sceneStepResolve',
    ];
    expect(constants.length, 8);
    expect(methods.length, 45);
    expect(constants.length + methods.length, 53);

    final missing = methods.where((m) => !handlers.containsKey(m)).toList();
    expect(missing, isEmpty, reason: '这些导出成员没有 handler: $missing');
    expect(
      handlers.keys.where((k) => k != 'const').length,
      methods.length,
      reason: 'handler 数量与 45 个方法不一致',
    );
    // 常量经 'const' handler 逐一派生
    for (final name in constants) {
      expect(_constOf(name), isNotNull, reason: '常量 $name 取不到');
    }
  });

  test('Q4：RNG 消耗三组合恒定（2 / 4 / 0）× 3 seed', () {
    const seeds = <int>[7, 12345, 4294967295];
    for (final seed in seeds) {
      final rng = Lcg(seed);
      setRng(rng.call);

      _r.check(<String, Object?>{'base': 50, 'value': 42});
      expect(rng.used, 2, reason: 'check(value:42) 应消耗 2 次（个位骰 + 十位骰）');

      rng.used = 0;
      final r2 = Lcg(seed);
      setRng(r2.call);
      _r.check(<String, Object?>{'base': 50, 'value': 42, 'bonus': 2});
      expect(r2.used, 4, reason: 'bonus:2 应消耗 4 次（1 个位骰 + 3 个十位骰）');

      final r3 = Lcg(seed);
      setRng(r3.call);
      _r.check(<String, Object?>{
        'base': 50,
        'value': 42,
        'ones': 3,
        'forcedTens': <int>[2],
      });
      expect(r3.used, 0, reason: 'ones + forcedTens 全给应 0 次 RNG');
    }
  });

  test('奖励骰/惩罚骰必须先组合再比大小（dice.dart 的 d100Bonus 缺陷不复刻）', () {
    // 十位骰 {0,1} + 个位骰 0：组合是 100 与 10
    final bonus = _r.rollD100(<String, Object?>{
      'ones': 0,
      'forcedTens': <int>[0, 1],
      'bonus': 1,
    });
    expect(bonus['value'], 10, reason: '奖励骰应取更低的 10，而不是先取 min 得到 100');

    final penalty = _r.rollD100(<String, Object?>{
      'ones': 0,
      'forcedTens': <int>[1, 0],
      'penalty': 1,
    });
    expect(penalty['value'], 100, reason: '惩罚骰应取更高的 100');
  });
}
