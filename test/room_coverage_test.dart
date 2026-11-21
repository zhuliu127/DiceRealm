// ============================================================
// test/room_coverage_test.dart — 覆盖矩阵可追溯（T01 判据 3 / 4）
//
// 断言的是「fixture 的 tag 集合覆盖了应该覆盖的全部成员」，不是断言业务行为：
//   · CocRules 53 导出（8 常量 + 45 方法）
//   · RoomModel 41 导出对应的常量组 / 28 EVT / 13 INTENT / 62 POLICY（× 3 角色）
//   · 28 个 reduce 分支（26 个有分支 + TEMP_COMMIT / SAVE_SYNC 刻意走 default）
//   · §5.11 实测边界值（阈值 / 骰值 / 大成功大失败自定义）
//   · 序列类：S:seq / S:skip / S:canFill / S:rollback / S:q1 / S:status / S:intent / S:legacy
//
// 白名单断言（U6）：恰好 1 条，且字段齐全、allowedPaths 非空。
// ============================================================

import 'package:dice_realm/domain/room_rules.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_oracle.dart';
import 'support/room_oracle_whitelist.dart';

const List<String> _cocRulesMethods = <String>[
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

const List<String> _cocRulesConstants = <String>[
  'version', 'LEVEL', 'LEVEL_TEXT', 'LEVEL_KEY',
  'DIFFICULTY', 'OUTCOME', 'JAM_TYPES', 'limits',
];

const List<String> _modelHelperTags = <String>[
  // ⚠️ ruleOptsOf 未被旧版导出（不在 41 个导出里）→ 无法 oracle，
  //    改由 room_model_core_test.dart 的 Dart-only 用例覆盖。
  'M:hasSecret', 'M:scrub', 'M:bodyView', 'M:bodyForHp',
  'M:migrateBodyStatus', 'M:validCode', 'M:cleanText', 'M:inviteLink',
  'M:readInvite', 'M:emptyState', 'M:clone', 'M:syncMsg', 'M:evtMsg',
  'M:skipMsg', 'M:intentMsg', 'M:parse', 'M:logScript', 'M:rosterScript',
  'M:sanitizeSheet', 'M:sanitizeSceneSteps', 'M:parseSave',
  'M:applyStateToCard', 'M:restoreHost', 'M:playerViewFromSave',
];

const List<String> _sequenceTags = <String>[
  'S:seq', 'S:skip', 'S:canFill', 'S:rollback', 'S:q1', 'S:status',
  'S:intent', 'S:legacy',
];

/// 从 room_rules fixture 里找一条 `check` 用例，其 opts 满足 [predicate]
bool _hasCheck(
  List<Map<String, Object?>> cases,
  bool Function(Map<String, Object?> opts) predicate,
) {
  for (final c in cases) {
    if (c['fn'] != 'check') continue;
    final args = c['args'];
    if (args is! Map) continue;
    final opts = args['opts'];
    if (opts is! Map) continue;
    if (predicate(opts.cast<String, Object?>())) return true;
  }
  return false;
}

void main() {
  final rules = RoomOracleFixture.load('room_rules.json');
  final model = RoomOracleFixture.load('room_model.json');
  final seqs = RoomOracleFixture.load('room_sequences.json');

  test('fixture 规模：455/517/121，合计 ≥1000', () {
    expect(rules.cases.length, greaterThanOrEqualTo(420));
    expect(model.cases.length, greaterThanOrEqualTo(460));
    expect(seqs.cases.length, greaterThanOrEqualTo(120));
    expect(
      rules.cases.length + model.cases.length + seqs.cases.length,
      greaterThanOrEqualTo(1000),
    );
  });

  test('CocRules 53 导出成员全覆盖（8 常量 + 45 方法）', () {
    expect(_cocRulesConstants.length, 8);
    expect(_cocRulesMethods.length, 45);
    expect(_cocRulesConstants.length + _cocRulesMethods.length, 53);

    final tags = rules.tags;
    for (final name in _cocRulesConstants) {
      expect(tags, contains('R:const:$name'), reason: '缺常量用例 $name');
    }
    for (final fn in _cocRulesMethods) {
      expect(tags, contains('R:$fn'), reason: '缺方法用例 $fn');
    }
    // 运行时校验：常量表与实现一致
    expect(CocRules.LEVEL.length, 6);
    expect(CocRules.DIFFICULTY.length, 3);
    expect(CocRules.OUTCOME.length, 4);
    expect(CocRules.JAM_TYPES.length, 4);
    expect(CocRules.limits['MAX_DICE'], 100);
    expect(CocRules.limits['MAX_SIDES'], 1000);
  });

  test('EVT 28 / INTENT 13 / POLICY 62 逐项覆盖', () {
    final tags = model.tags;
    expect(RoomEvt.values.length, 28);
    expect(RoomIntent.values.length, 13);
    expect(kRoomPolicy.length, 62);

    for (final v in RoomEvt.values) {
      expect(tags, contains('EVT:$v'), reason: '缺 EVT 常量用例 $v');
    }
    for (final v in RoomIntent.values) {
      expect(tags, contains('INTENT:$v'), reason: '缺 INTENT 常量用例 $v');
    }
    for (final action in kRoomPolicy.keys) {
      expect(tags, contains('P:$action'), reason: '缺 POLICY 用例 $action');
      for (final role in RoomRole.values) {
        expect(
          tags,
          contains('N:$action:$role'),
          reason: '缺 needs($role, $action) 用例',
        );
      }
    }
  });

  test('28 个 reduce 分支全覆盖（26 有分支 + TEMP_COMMIT / SAVE_SYNC 走 default）', () {
    final tags = model.tags;
    for (final v in RoomEvt.values) {
      expect(
        tags,
        contains('M:reduce:${v.toUpperCase()}'),
        reason: '缺 reduce 分支用例 $v',
      );
    }
    // 每个分支至少 3 组输入
    for (final v in RoomEvt.values) {
      final n = model.cases
          .where((c) => c['tag'] == 'M:reduce:${v.toUpperCase()}')
          .length;
      expect(n, greaterThanOrEqualTo(3), reason: 'reduce $v 的输入组数不足 3');
    }
  });

  test('RoomModel 状态/可见性/存档助手全覆盖', () {
    final tags = model.tags;
    for (final t in _modelHelperTags) {
      expect(tags, contains(t), reason: '缺助手用例 $t');
    }
    for (final name in <String>[
      'ROLE', 'STATUS', 'STATUS_TEXT', 'MODE', 'REWIND', 'CONFIRM', 'VIS',
      'SECRET_KEYS', 'HOST_SEAT',
    ]) {
      expect(tags, contains('M:const:$name'), reason: '缺常量组用例 $name');
    }
  });

  test('序列类 tag 全覆盖（seq / skip / canFill / rollback / Q1 / status / intent / legacy）', () {
    final tags = seqs.tags;
    for (final t in _sequenceTags) {
      expect(tags, contains(t), reason: '缺序列用例 $t');
    }
    // 27 个事件都走了 emit 路径（与 reduce 分支互为交叉验证）
    for (final v in RoomEvt.values) {
      expect(tags, contains('S:emit:${v.toUpperCase()}'));
    }
  });

  test('§5.11 实测边界值全部有用例', () {
    // 阈值：55 的困难阈值 27 / 极难阈值 11（向下取整）
    expect(_hasCheck(rules.cases, (o) => o['base'] == 55 && o['difficulty'] == 'hard' && o['value'] == 27), isTrue);
    expect(_hasCheck(rules.cases, (o) => o['base'] == 55 && o['difficulty'] == 'hard' && o['value'] == 28), isTrue);
    // 常规检定的成功边界（45 vs 46）
    expect(_hasCheck(rules.cases, (o) => o['base'] == 45 && o['value'] == 45), isTrue);
    expect(_hasCheck(rules.cases, (o) => o['base'] == 45 && o['value'] == 46), isTrue);
    // 大成功 / 大失败 / 100
    expect(_hasCheck(rules.cases, (o) => o['value'] == 1), isTrue);
    expect(_hasCheck(rules.cases, (o) => o['value'] == 96), isTrue);
    expect(_hasCheck(rules.cases, (o) => o['value'] == 100), isTrue);
    // 自定义阈值
    expect(_hasCheck(rules.cases, (o) => o['critMax'] == 5), isTrue);
    expect(_hasCheck(rules.cases, (o) => o['fumbleMin'] == 90), isTrue);
    // 00+0 = 100 的骰面组合
    final hasDoubleZero = rules.cases.any((c) {
      if (c['fn'] != 'rollD100') return false;
      final args = c['args'];
      if (args is! Map) return false;
      final opts = args['opts'];
      if (opts is! Map) return false;
      final ft = opts['forcedTens'];
      return opts['ones'] == 0 && ft is List && ft.isNotEmpty && ft.first == 0;
    });
    expect(hasDoubleZero, isTrue);
    // 奖励骰「先组合再比大小」的关键用例（十位骰 1/0 + 个位 0）
    final hasBonusEdge = rules.cases.any((c) {
      if (c['fn'] != 'rollD100') return false;
      final args = c['args'];
      if (args is! Map) return false;
      final opts = args['opts'];
      if (opts is! Map) return false;
      final ft = opts['forcedTens'];
      return ft is List && ft.length >= 2;
    });
    expect(hasBonusEdge, isTrue);
  });

  test('白名单恰好 2 条，字段齐全（U6 + F3 裁决 A）', () {
    // S:q1 的 14 条路径一条未动；S:trim 是 F3 修复带来的第 2 条有意偏离。
    expect(kRoomOracleWhitelist.length, 2);
    for (final d in kRoomOracleWhitelist) {
      expect(d.caseId, isNotEmpty);
      expect(d.legacyRef, contains('room-model.js'));
      expect(d.reproInput, contains('rollback'));
      expect(d.legacyBehavior, isNotEmpty);
      expect(d.dartBehavior, isNotEmpty);
      expect(d.allowedPaths, isNotEmpty);
      expect(d.forbiddenKeys,
          containsAll(<String>['hp', 'hpMax', 'secret', 'kpOnly', 'attrs']));
    }
    final q1 = kRoomOracleWhitelist.firstWhere((d) => d.caseId == 'S:q1');
    final trim = kRoomOracleWhitelist.firstWhere((d) => d.caseId == 'S:trim');
    expect(q1.allowedPaths.length, greaterThanOrEqualTo(5));
    expect(trim.allowedPaths, <String>[kTrimAllowedPath]);
    // 该用例确实存在于 fixture（否则白名单就是死登记）
    expect(
      seqs.cases.any((c) => q1.coversCase(c)),
      isTrue,
      reason: '白名单登记的 S:q1 在 room_sequences.json 里不存在',
    );
    // 登记在册的 tag / caseId 恰好两条（F3 裁决 A 批准新增 S:trim）。
    final whitelistedTags =
        kRoomOracleWhitelist.map((d) => d.caseId).toSet();
    expect(whitelistedTags, <String>{'S:q1', 'S:trim'});
    // S:trim 只登记 QA 现造 oracle 的 F:4#900001（靠 exactCaseNames 精确点名），
    // 在 room_sequences.json 里零命中 —— 所以实际命中集合仍只有 S:q1。
    expect(seqs.cases.any((c) => trim.coversCase(c)), isFalse,
        reason: 'S:trim 不应在 room_sequences.json 里蹭到任何用例');
    final matchedTags = seqs.cases
        .where((c) => kRoomOracleWhitelist.any((d) => d.coversCase(c)))
        .map((c) => c['tag'])
        .toSet();
    expect(matchedTags, <Object?>{'S:q1'});
  });
}
