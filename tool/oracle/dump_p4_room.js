/* ============================================================
 * tool/oracle/dump_p4_room.js — 用旧 JS 生成 P4 房间层的期望值
 *
 * 用法： node tool/oracle/dump_p4_room.js
 * 输出： test/fixtures/room_rules.json  （≥420 例，CocRules 53 导出）
 *        test/fixtures/room_model.json  （≥460 例，RoomModel 41 导出 + reduce/needs）
 *        test/fixtures/room_sequences.json（≥120 例，seq / skip / rollback / 可见性）
 *
 * 每个 case 的形状（与既有 oracle 一致，另加 `tag` 供覆盖矩阵断言）：
 *   { name, fn, args, seed, expect, randUsed, tag, error }
 *
 * ⚠️ 原则：原码只读。所有 case 都是「确定性输入 → 原样 dump 输出」，
 *    不为了好写而改数据结构；randUsed 一并记录，Dart 侧必须相等。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const { createRoomSandbox } = require('./load_p4_room');

const { sandbox: S, CocRules: R, RoomModel: M } = createRoomSandbox();
const OUT = path.resolve(__dirname, '../../test/fixtures');

/** JSON 化：丢掉 undefined / 函数（与原码返回的对象形状保持一致） */
function J(v) {
  if (v === undefined) return null;
  return JSON.parse(JSON.stringify(v));
}

let seedSeq = 0;
function nextSeed() {
  seedSeq += 1;
  return (seedSeq * 2654435761) % 4294967296;
}

let caseSeq = 0;

const R_CASES = [];
const M_CASES = [];
const S_CASES = [];

/**
 * 登记一个用例。
 * @param {Array} bucket 目标数组
 * @param {string} fn Dart 侧 handler 名
 * @param {*} args 输入（会被 JSON 化后写进 fixture）
 * @param {string} tag 覆盖矩阵标签
 * @param {Function} thunk 真正调用旧 JS 的闭包
 * @param {number} [seedOverride] 需要钉死随机序列时显式给 seed
 */
function add(bucket, fn, args, tag, thunk, seedOverride) {
  const seed = seedOverride === undefined ? nextSeed() : seedOverride;
  S.__setSeed(seed);
  let out = null;
  let error = null;
  try {
    out = thunk();
  } catch (e) {
    // 原码在个别分支会抛异常；照样记录，Dart 侧跳过并单独统计（不改原码）
    error = String(e && e.message ? e.message : e);
  }
  caseSeq += 1;
  bucket.push({
    name: `${tag}#${caseSeq}`,
    fn,
    args: J(args),
    seed,
    expect: error ? null : J(out),
    randUsed: S.__randUsed(),
    tag,
    error,
  });
}

const R_ = (fn, args, tag, thunk, seed) => add(R_CASES, fn, args, tag, thunk, seed);
const M_ = (fn, args, tag, thunk, seed) => add(M_CASES, fn, args, tag, thunk, seed);
const S_ = (fn, args, tag, thunk, seed) => add(S_CASES, fn, args, tag, thunk, seed);

/* ============================================================
 * 一、room_rules.json —— CocRules 53 导出
 * ============================================================ */

// ---- 常量 8 项 ----
for (const name of [
  'version', 'LEVEL', 'LEVEL_TEXT', 'LEVEL_KEY',
  'DIFFICULTY', 'OUTCOME', 'JAM_TYPES', 'limits',
]) {
  R_('const', { name }, `R:const:${name}`, () => R[name]);
}

// ---- 1. 阈值与成功等级 ----
for (const base of [0, 1, 5, 27, 30, 49, 50, 55, 99, 100, 120, -3, '45', 'abc', null]) {
  R_('thresholds', { base }, 'R:thresholds', () => R.thresholds(base));
}

for (const base of [50, 55, 1, 99, 0]) {
  for (const difficulty of ['regular', 'hard', 'extreme', 'bogus']) {
    R_('targetOf', { base, difficulty }, 'R:targetOf', () => R.targetOf(base, difficulty));
  }
}

for (const d of ['regular', 'hard', 'extreme', '', null, 'HARD', 'Hard']) {
  R_('normDifficulty', { d }, 'R:normDifficulty', () => R.normDifficulty(d));
}

for (const target of [20, 49, 50, 51, 99]) {
  for (const opts of [{}, { fumbleMin: 95 }, { fumbleMin: 0 }]) {
    R_('fumbleRange', { target, opts }, 'R:fumbleRange', () => R.fumbleRange(target, opts));
  }
}

for (const value of [1, 50, 95, 96, 99, 100]) {
  for (const target of [20, 50]) {
    R_('isFumble', { value, target, opts: {} }, 'R:isFumble',
      () => R.isFumble(value, target, {}));
  }
}

for (const value of [1, 2, 5, 11, 19, 20, 27, 28, 50, 55, 96, 99, 100]) {
  for (const base of [55, 20, 1, 100]) {
    R_('levelOf', { value, base, target: null, opts: {} }, 'R:levelOf',
      () => R.levelOf(value, base, undefined, {}));
  }
}
for (const opts of [{ critMax: 5 }, { fumbleMin: 95 }, { critMax: 3, fumbleMin: 90 }]) {
  R_('levelOf', { value: 3, base: 50, target: 25, opts }, 'R:levelOf',
    () => R.levelOf(3, 50, 25, opts));
}

for (const opts of [{}, { critMax: 1 }, { critMax: 5 }, { critMax: 100 }, { critMax: 'abc' }, { critMax: 0 }]) {
  R_('critThresholdOf', { opts }, 'R:critThresholdOf', () => R.critThresholdOf(opts));
}
for (const opts of [{}, { fumbleMin: 0 }, { fumbleMin: 96 }, { fumbleMin: 200 }, { fumbleMin: 'x' }, { fumbleMin: -5 }]) {
  R_('fumbleThresholdOf', { opts }, 'R:fumbleThresholdOf', () => R.fumbleThresholdOf(opts));
}

// ---- 2. 掷骰 ----
const ROLL_OPTS = [
  {},
  { bonus: 1 },
  { bonus: 2 },
  { penalty: 1 },
  { bonus: 1, penalty: 1 },
  { bonus: 3, penalty: 1 },
  { ones: 0, forcedTens: [0] },
  { ones: 0, forcedTens: [1] },
  { ones: 5, forcedTens: [3, 0], bonus: 1 },
  { ones: 0, forcedTens: [1, 0], penalty: 1 },
  { ones: 7, forcedTens: [0], bonus: 3 },
];
ROLL_OPTS.forEach((opts, i) => {
  R_('rollD100', { opts }, 'R:rollD100', () => R.rollD100(opts));
});
// Q4：RNG 三组合 × 3 seed（钉死 randUsed 2 / 4 / 0）
for (const seed of [7, 12345, 4294967295]) {
  R_('check', { opts: { base: 50, value: 42 } }, 'R:rng:value', () => R.check({ base: 50, value: 42 }), seed);
  R_('check', { opts: { base: 50, value: 42, bonus: 2 } }, 'R:rng:bonus2', () => R.check({ base: 50, value: 42, bonus: 2 }), seed);
  R_('check', { opts: { base: 50, value: 42, ones: 3, forcedTens: [2] } }, 'R:rng:noDraw',
    () => R.check({ base: 50, value: 42, ones: 3, forcedTens: [2] }), seed);
}
for (const [tens, ones] of [[0, 0], [0, 5], [3, 0], [9, 9], [10, 0]]) {
  R_('combine', { tens, ones }, 'R:combine', () => R.combine(tens, ones));
}

// ---- 3. 检定 ----
const CHECK_OPTS = [
  { base: 50 },
  { base: 55 },
  { base: 25 },
  { base: 1 },
  { base: 0 },
  { base: 99 },
  { base: 120 },
  { base: -5 },
  { base: 55, difficulty: 'hard' },
  { base: 55, difficulty: 'extreme' },
  { base: 55, difficulty: 'hard', value: 27 },
  { base: 55, difficulty: 'hard', value: 28 },
  { base: 55, bonus: 1 },
  { base: 55, bonus: 2 },
  { base: 55, penalty: 1 },
  { base: 55, bonus: 2, penalty: 1 },
  { base: 50, value: 42 },
  { base: 50, value: 1 },
  { base: 50, value: 100 },
  { base: 50, value: 96 },
  { base: 50, value: 0 },
  { base: 50, value: 200 },
  { base: 50, ones: 0, forcedTens: [0] },
  { base: 50, ones: 0, forcedTens: [1], bonus: 1 },
  { base: 50, kind: 'san' },
  { base: 50, kind: 'luck' },
  { base: 50, kind: 'combat' },
  { base: 50, kind: 'attribute', label: '力量' },
  { base: 50, secret: true, label: '侦查' },
  { base: 50, critMax: 5 },
  { base: 50, fumbleMin: 90 },
  { base: 50, difficulty: 'regular', value: 96 },
  { base: 45, value: 45 },
  { base: 45, value: 46 },
];
CHECK_OPTS.forEach((opts) => {
  R_('check', { opts }, 'R:check', () => R.check(opts));
});
CHECK_OPTS.slice(0, 8).forEach((opts) => {
  R_('describeCheck', { opts }, 'R:describeCheck', () => R.describeCheck(R.check(opts)));
});

// ---- 4. 推动 / 幸运 ----
const CANPUSH_RESULTS = [
  { kind: 'skill', passed: false, fumble: false, level: 0 },
  { kind: 'skill', passed: true, fumble: false, level: 2 },
  { kind: 'skill', passed: false, fumble: true, level: -1 },
  { kind: 'combat', passed: false, fumble: false, level: 0 },
  { kind: 'san', passed: false, fumble: false, level: 0 },
  { kind: 'luck', passed: false, fumble: false, level: 0 },
  { kind: 'attribute', passed: false, fumble: false, level: 0 },
  { kind: 'weird', passed: false, fumble: false, level: 0 },
  null,
];
CANPUSH_RESULTS.forEach((result) => {
  R_('canPush', { result }, 'R:canPush', () => R.canPush(result, result ? result.kind : 'skill'));
});
for (const kind of ['skill', 'luck', 'san', 'sanity', 'sanloss', 'damage', 'opposed']) {
  R_('luckAllowed', { kind }, 'R:luckAllowed', () => R.luckAllowed(kind));
}
[
  { amount: 10, luckAvailable: 50 },
  { amount: 0, luckAvailable: 50 },
  { amount: 60, luckAvailable: 50 },
  { amount: 42, luckAvailable: 99 },
  { amount: 1, luckAvailable: 1 },
].forEach((extra) => {
  const checkOpts = { base: 50, value: 42 };
  R_('spendLuck', { checkOpts, ...extra }, 'R:spendLuck', () => {
    const r = R.check(checkOpts);
    return R.spendLuck({ result: r, amount: extra.amount, luckAvailable: extra.luckAvailable });
  });
});
// 大失败 / 大成功 / 不可花幸运的类型
['san', 'luck'].forEach((kind) => {
  R_('spendLuck', { checkOpts: { base: 50, value: 42, kind }, amount: 5, luckAvailable: 50 },
    'R:spendLuck', () => R.spendLuck({
      result: R.check({ base: 50, value: 42, kind }), amount: 5, luckAvailable: 50,
    }));
});
R_('spendLuck', { checkOpts: { base: 50, value: 1 }, amount: 5, luckAvailable: 50 },
  'R:spendLuck', () => R.spendLuck({ result: R.check({ base: 50, value: 1 }), amount: 5, luckAvailable: 50 }));
R_('spendLuck', { checkOpts: { base: 50, value: 100 }, amount: 5, luckAvailable: 50 },
  'R:spendLuck', () => R.spendLuck({ result: R.check({ base: 50, value: 100 }), amount: 5, luckAvailable: 50 }));

// ---- 5. 对抗 ----
const OPP_PAIRS = [
  [{ base: 50, value: 10 }, { base: 50, value: 40 }],
  [{ base: 60, value: 10 }, { base: 60, value: 40 }],
  [{ base: 50, value: 10 }, { base: 50, value: 10 }],
  [{ base: 80, value: 10 }, { base: 40, value: 10 }],
  [{ base: 40, value: 10 }, { base: 80, value: 10 }],
  [{ base: 50, value: 96 }, { base: 50, value: 100 }],
];
OPP_PAIRS.forEach(([a, b]) => {
  R_('opposed', { a, b }, 'R:opposed', () => R.opposed(R.check(a), R.check(b)));
});
for (const [aRoll, bRoll] of [[10, 20], [20, 10], [30, 30], [1, 100], [100, 1]]) {
  R_('opposedReroll', { aRoll, bRoll }, 'R:opposedReroll', () => R.opposedReroll(aRoll, bRoll));
}
for (const mode of ['fightback', 'dodge', 'none']) {
  for (const pair of [[{ base: 50, value: 10 }, { base: 50, value: 10 }],
    [{ base: 60, value: 10 }, { base: 50, value: 10 }],
    [{ base: 50, value: 10 }, { base: 60, value: 10 }]]) {
    R_('opposedAttack', { a: pair[0], b: pair[1], o: { mode } }, 'R:opposedAttack',
      () => R.opposedAttack(R.check(pair[0]), R.check(pair[1]), { mode }));
  }
}
// 通用重掷（同级同值 → 逐轮重掷）
[1, 2, 3].forEach((rerollMax) => {
  R_('opposedFull', { a: { base: 50, value: 10 }, b: { base: 50, value: 10 }, o: { rerollMax } },
    'R:opposedFull', () => R.opposedFull(R.check({ base: 50, value: 10 }),
      R.check({ base: 50, value: 10 }), { rerollMax }));
});

// ---- 6. 骰式 ----
['1D6', '2D10-1', '1D6+1', 'D4', '3D6', '0', '100D1000', '101D6', '1D1', '1D6*2', 'abc', '', ' 1d6 + 2 ', '1D6+', '9999', '10001', null].forEach((expr) => {
  R_('parseExpr', { expr }, 'R:parseExpr', () => R.parseExpr(expr));
});
['1D6', '2D10-1', '1D6+1', '3D6', '0', 'abc', '1D4+2', '2D6-2'].forEach((expr) => {
  R_('rollExpr', { expr }, 'R:rollExpr', () => R.rollExpr(expr));
});
['+1D4', '-2', '0', '', '1D6', '+2D4-1'].forEach((expr) => {
  R_('rollDamageBonus', { expr }, 'R:rollDamageBonus', () => R.rollDamageBonus(expr));
});
['1D6', '2D10-1', '1D6+1', '0', 'abc', '3D6+2', '1D4'].forEach((expr) => {
  R_('maxOfExpr', { expr }, 'R:maxOfExpr', () => R.maxOfExpr(expr));
});
['+1D4', '-2', '0', '', '1D6', '+2D4-1'].forEach((expr) => {
  R_('maxOfDamageBonus', { expr }, 'R:maxOfDamageBonus', () => R.maxOfDamageBonus(expr));
});
[['1D6', '+1D4'], ['2D6', '-2'], ['1D10', '0'], ['abc', '0'], ['1D4', '+1D6']].forEach(([expr, db]) => {
  R_('impaleDamage', { expr, db }, 'R:impaleDamage', () => R.impaleDamage(expr, db));
});

// ---- 7. 连发 / 故障 ----
['1', '2', '3', '1(3)', '1(2)', '1 or 2', '1或2', '3连射', '全自动', '1/4', 'N/A', '', null, '——'].forEach((perRound) => {
  R_('burstMaxOf', { perRound }, 'R:burstMaxOf', () => R.burstMaxOf(perRound));
});
['1', '3', '1(3)', 'N/A', ''].forEach((perRound) => {
  R_('isBurstWeapon', { perRound }, 'R:isBurstWeapon', () => R.isBurstWeapon(perRound));
});
[{ malfunction: '96' }, { malfunction: '100' }, { malfunction: '0' }, { malfunction: '——' },
  { malfunction: 'N/A' }, { malfunction: '' }, { malfunction: null }, { malfunction: '101' }, {}].forEach((weapon) => {
  R_('malfunctionThresholdOf', { weapon }, 'R:malfunctionThresholdOf',
    () => R.malfunctionThresholdOf(weapon));
});
[
  { weapon: { malfunction: '96' }, rollValue: 96, opts: {} },
  { weapon: { malfunction: '96' }, rollValue: 95, opts: {} },
  { weapon: { malfunction: '96' }, rollValue: 100, opts: { critical: true } },
  { weapon: { malfunction: '——' }, rollValue: 100, opts: {} },
  { weapon: { malfunction: '100' }, rollValue: 100, opts: {} },
  { weapon: {}, rollValue: 50, opts: {} },
].forEach(({ weapon, rollValue, opts }) => {
  R_('malfunctionOf', { weapon, rollValue, opts }, 'R:malfunctionOf',
    () => R.malfunctionOf(weapon, rollValue, opts));
});
[
  { name: '点38左轮', perRound: '1' },
  { name: '冲锋枪', perRound: '3连射' },
  { name: '步枪', perRound: '1' },
  { name: '转轮机枪', perRound: '全自动' },
  {},
].forEach((weapon) => {
  R_('defaultMalfunctionType', { weapon }, 'R:defaultMalfunctionType',
    () => R.defaultMalfunctionType(weapon));
});
[
  { weapon: { name: '左轮' }, type: 'jam' },
  { weapon: { name: '左轮' }, type: 'dud' },
  { weapon: { name: '冲锋枪' }, type: 'feed' },
  { weapon: { name: '冲锋枪' }, type: 'burst' },
  { weapon: { name: '步枪' }, type: 'bogus' },
  { weapon: {}, type: '' },
].forEach(({ weapon, type }) => {
  R_('malfunctionEffect', { weapon, type }, 'R:malfunctionEffect',
    () => R.malfunctionEffect(weapon, type));
});

// ---- 8. SAN ----
['0/1D6', '1/1D4', '1D3/1D10', '0/999D999', '1D6', '', 'x/1D6', '1D6/x', null].forEach((expr) => {
  R_('parseSanLoss', { expr }, 'R:parseSanLoss', () => R.parseSanLoss(expr));
});
[
  { currentSan: 50, maxSan: 99, lossExpr: '0/1D6' },
  { currentSan: 50, maxSan: 99, lossExpr: '1/1D4' },
  { currentSan: 5, maxSan: 99, lossExpr: '1D6/1D10' },
  { currentSan: 5, maxSan: 3, lossExpr: '0/1D6' },
  { currentSan: 0, maxSan: 0, lossExpr: '0/1D6' },
  { currentSan: 50, lossExpr: '0/1D6' },
  { currentSan: 50, maxSan: 99, lossExpr: 'bad' },
].forEach((opts) => {
  R_('resolveSanCheck', { opts }, 'R:resolveSanCheck', () => R.resolveSanCheck(opts));
});
// 用已掷好的检定结果（省一次掷骰）
R_('resolveSanCheck', {
  opts: { currentSan: 50, maxSan: 99, lossExpr: '0/1D6' },
  checkResult: { passed: false, value: 77, base: 50, level: 0, levelText: '失败' },
}, 'R:resolveSanCheck', () => R.resolveSanCheck({
  currentSan: 50, maxSan: 99, lossExpr: '0/1D6',
  checkResult: R.check({ base: 50, value: 77 }),
}));

[
  { loss: 5, dayStartSan: 50, dayLossSoFar: 0 },
  { loss: 4, dayStartSan: 50, dayLossSoFar: 0 },
  { loss: 10, dayStartSan: 50, dayLossSoFar: 0 },
  { loss: 3, dayStartSan: 50, dayLossSoFar: 7 },
  { loss: 1, dayStartSan: 0, dayLossSoFar: 0 },
  { loss: 0, dayStartSan: 9, dayLossSoFar: 0 },
].forEach((opts) => {
  R_('insanityFlags', { opts }, 'R:insanityFlags', () => R.insanityFlags(opts));
});

// ---- 9. 伤势 ----
[
  { damage: 5, maxHP: 10, currentHP: 10 },
  { damage: 6, maxHP: 10, currentHP: 10 },
  { damage: 10, maxHP: 10, currentHP: 10 },
  { damage: 11, maxHP: 10, currentHP: 10 },
  { damage: 5, maxHP: 10, currentHP: 5 },
  { damage: 5, maxHP: 10, currentHP: 5, majorWound: true },
  { damage: 0, maxHP: 10, currentHP: 3 },
  { damage: 3, maxHP: 10, currentHP: 1 },
].forEach((opts) => {
  R_('damageFlags', { opts }, 'R:damageFlags', () => R.damageFlags(opts));
});
[50, 30, 1].forEach((con) => {
  R_('dyingRoundCheck', { con }, 'R:dyingRoundCheck', () => R.dyingRoundCheck(con));
});
[65, 30, 0].forEach((intValue) => {
  R_('temporaryInsanityCheck', { intValue }, 'R:temporaryInsanityCheck',
    () => R.temporaryInsanityCheck(intValue));
});
[0, 1, 2, 3].forEach(() => {
  R_('boutRounds', {}, 'R:boutRounds', () => R.boutRounds());
});

// ---- 10. 行动顺序 ----
const ACTOR_SETS = [
  [{ id: 'a', name: 'Alfa', dex: 50 }, { id: 'b', name: 'Beta', dex: 70 }],
  [{ id: 'a', name: 'Alfa', dex: 50 }, { id: 'b', name: 'Beta', dex: 70, readyFirearm: true }],
  [{ id: 'a', name: 'Alfa', dex: 50, actionsPerRound: 3 }],
  [{ id: 'a', name: 'Alfa', dex: 50, manualOrder: 2 }, { id: 'b', name: 'Beta', dex: 70, manualOrder: 1 }],
  [{ id: 'a', name: 'Alfa', dex: 50 }, { id: 'b', name: 'Bravo', dex: 50 }],
  [],
];
ACTOR_SETS.forEach((actors) => {
  R_('initiativeOrder', { actors, opts: {} }, 'R:initiativeOrder', () => R.initiativeOrder(actors, {}));
});
R_('initiativeOrder', { actors: ACTOR_SETS[1], opts: { useReadyFirearm: false } }, 'R:initiativeOrder',
  () => R.initiativeOrder(ACTOR_SETS[1], { useReadyFirearm: false }));

[[0, 1, 3], [1, 1, 3], [2, 1, 3], [0, 2, 1], [5, 3, 3], [0, 0, 0]].forEach(([index, round, queueLength]) => {
  R_('advanceTurn', { index, round, queueLength }, 'R:advanceTurn',
    () => R.advanceTurn(index, round, queueLength));
});

// ---- 11. 攻击结算 ----
const ATTACKS = [
  { attack: { value: 50, roll: 10 }, defense: { mode: 'none' }, damage: { expr: '1D6', db: '0' } },
  { attack: { value: 50, roll: 10 }, defense: { mode: 'none' }, damage: { expr: '1D6', db: '+1D4' }, impale: true },
  { attack: { value: 50, roll: 10 }, defense: { mode: 'dodge', value: 40, roll: 5 }, damage: { expr: '1D6', db: '0' } },
  { attack: { value: 50, roll: 10 }, defense: { mode: 'dodge', value: 40, roll: 20 }, damage: { expr: '1D6', db: '0' } },
  { attack: { value: 50, roll: 10 }, defense: { mode: 'fightback', value: 40, roll: 5 }, damage: { expr: '1D6', db: '0' } },
  { attack: { value: 50, roll: 90 }, defense: { mode: 'dodge', value: 40, roll: 5 }, damage: { expr: '1D6', db: '0' } },
  { attack: { value: 50, roll: 10 }, defense: { mode: 'fightback', value: 40, roll: 5 }, ranged: true, damage: { expr: '1D6', db: '0' } },
  { attack: { value: 50, roll: 10 }, defense: { mode: 'none' }, damage: { expr: '1D6', db: '0' }, armor: { value: 3 } },
  { attack: { value: 50, roll: 10 }, defense: { mode: 'none' }, damage: { expr: '1D6', db: '0' }, maxHP: 10, currentHP: 10 },
  { attack: { value: 50, roll: 1 }, defense: { mode: 'none' }, damage: { expr: '1D6', db: '0' }, maxHP: 12, currentHP: 2, impale: true },
];
ATTACKS.forEach((o) => {
  R_('resolveAttack', { o }, 'R:resolveAttack', () => R.resolveAttack(o));
});

// ---- 12. 角色卡取值 ----
const SHEET = {
  skills: [
    { name: '侦查', value: 60, total: 65 },
    { name: '格斗（斗殴）', value: 50, total: 55 },
    { name: '射击(手枪)', value: 40 },
    { name: '图书馆使用', value: 70, total: 70 },
  ],
  attrs: { str: 60, con: '55', dex: 70, int: 65 },
};
[
  ['侦查'], ['斗殴'], ['格斗'], ['手枪'], ['射击'], ['射击(手枪)'], ['图书馆'], ['不存在'], [''], ['格斗(斗殴)'],
].forEach(([name]) => {
  R_('skillValue', { sheet: SHEET, name }, 'R:skillValue', () => R.skillValue(SHEET, name));
});
R_('skillValue', { sheet: null, name: '侦查' }, 'R:skillValue', () => R.skillValue(null, '侦查'));
R_('skillValue', { sheet: { skills: [] }, name: '侦查' }, 'R:skillValue',
  () => R.skillValue({ skills: [] }, '侦查'));
[
  'str', 'STR', '力量', 'con', 'CON', '体质', 'dex', 'luck', 'nope', '',
].forEach((key) => {
  R_('attrValue', { sheet: SHEET, key }, 'R:attrValue', () => R.attrValue(SHEET, key));
});

// ---- 13. 场景步骤 ----
const STEPS = [
  { id: 's1', title: '开门', desc: '推开木门', targetSeat: 'p1', skill: '侦查', difficulty: 'regular', onSuccess: { note: '看到血迹', next: 's2' }, onFailure: { damage: '1D3', note: '被碎片割伤' } },
  { id: 's2', skill: '力量', difficulty: 'hard', bonus: 1, penalty: 0, onSuccess: { next: 'end' }, onFailure: { next: 's1' } },
  { id: 's3', onSuccess: { next: 'done' }, onFailure: { next: '' } },
  {},
];
STEPS.forEach((step) => {
  R_('sceneStepPlan', { step }, 'R:sceneStepPlan', () => R.sceneStepPlan(step));
});
STEPS.slice(0, 3).forEach((step) => {
  [5, 4, 3, 2, 0, -1, 'hard', 'EXTREME', null].slice(0, 4).forEach((level) => {
    R_('sceneStepResolve', { step, level }, 'R:sceneStepResolve',
      () => R.sceneStepResolve(step, level));
  });
});

/* ============================================================
 * 二、room_model.json —— RoomModel 41 导出 + reduce / needs
 * ============================================================ */

// ---- 常量组 ----
for (const name of ['ROLE', 'STATUS', 'STATUS_TEXT', 'MODE', 'REWIND', 'CONFIRM', 'VIS', 'SECRET_KEYS', 'HOST_SEAT']) {
  M_('Mconst', { name }, `M:const:${name}`, () => M[name]);
}
for (const key of Object.keys(M.EVT)) {
  M_('MconstMember', { group: 'EVT', key }, `EVT:${M.EVT[key]}`, () => M.EVT[key]);
}
for (const key of Object.keys(M.INTENT)) {
  M_('MconstMember', { group: 'INTENT', key }, `INTENT:${M.INTENT[key]}`, () => M.INTENT[key]);
}
for (const action of Object.keys(M.POLICY)) {
  M_('MconstMember', { group: 'POLICY', key: action }, `P:${action}`, () => M.POLICY[action]);
}

// ---- needs / allowed：61 action × 3 角色 ----
const ROLES = [M.ROLE.KP, M.ROLE.PLAYER, M.ROLE.SPECTATOR];
for (const action of Object.keys(M.POLICY)) {
  for (const role of ROLES) {
    M_('needs', { role, action }, `N:${action}:${role}`, () => M.needs(role, action));
  }
}
for (const action of ['chat', 'room.close', 'nope', 'rollback.turn']) {
  for (const role of ROLES) {
    M_('allowed', { role, action }, `M:allowed:${action}:${role}`, () => M.allowed(role, action));
  }
}
// 未登记 action 一律拒绝（含 Q6 已摘除的 rollback.turn）
M_('needs', { role: 'kp', action: 'rollback.turn' }, 'N:rollback.turn:kp', () => M.needs('kp', 'rollback.turn'));
M_('needs', { role: 'kp', action: '__unknown__' }, 'N:__unknown__:kp', () => M.needs('kp', '__unknown__'));

// ---- reduce：27 事件 × 3 输入 ----
const COMBAT_PRE = { combat: { order: [{ id: 'm1', name: '怪', slot: 1 }], turn: 0, round: 1 } };
const REDUCE_VARIANTS = {
  hello: [
    { p: { meta: { name: '房间A' } }, pre: {} },
    { p: { meta: { status: 'IN_GAME', mode: 'COMBAT' } }, pre: {} },
    { p: {}, pre: {} },
  ],
  members: [
    { p: { members: [{ seat: 'p1', role: 'player' }] }, pre: {} },
    { p: { members: [] }, pre: {} },
    { p: {}, pre: {} },
  ],
  chat: [
    { p: { seat: 'p1', nickname: '甲', text: 'hi', at: 1, kind: 'user' }, pre: {} },
    { p: { seat: '', text: '系统', at: 2 }, pre: {} },
    { p: {}, pre: {} },
  ],
  dice: [
    { p: { seat: 'p1', expr: '1D6', rolls: [{ count: 1, sides: 6, sign: 1, dice: [3] }], total: 3, level: 2, levelText: '常规成功', label: '侦查', at: 1 }, pre: {} },
    { p: { seat: 'p2', expr: '1D100', total: 42, at: 2 }, pre: {} },
    { p: {}, pre: {} },
  ],
  log: [
    { p: { seat: '', text: '推进', at: 1, kind: 'info' }, pre: {} },
    { p: { seat: 'p1', text: '自定义', kind: 'sys' }, pre: {} },
    { p: {}, pre: {} },
  ],
  scene: [
    { p: { scene: { title: 't', image: '', assets: [], marks: [], strokes: [] } }, pre: {} },
    { p: { scene: null }, pre: {} },
    { p: {}, pre: {} },
  ],
  combat: [
    { p: { combat: { order: [], turn: 0, round: 1 } }, pre: {} },
    { p: { combat: null }, pre: COMBAT_PRE },
    { p: {}, pre: {} },
  ],
  turn: [
    { p: { round: 2, turn: 1, order: [{ id: 'm1' }] }, pre: COMBAT_PRE },
    { p: { round: 3 }, pre: COMBAT_PRE },
    { p: {}, pre: {} },
  ],
  status: [
    { p: { status: 'IN_GAME', mode: 'COMBAT' }, pre: {} },
    { p: { status: 'SUSPENDED' }, pre: {} },
    { p: {}, pre: {} },
  ],
  kick: [{ p: {}, pre: {} }, { p: { seat: 'p1' }, pre: {} }, { p: {}, pre: COMBAT_PRE }],
  closed: [{ p: {}, pre: {} }, { p: { by: 'kp' }, pre: {} }, { p: {}, pre: COMBAT_PRE }],
  private: [
    { p: { text: '线索A', title: '只给p1', at: 1, kind: 'clue' }, vis: 'seat', to: 'p1', pre: {} },
    { p: { text: 'KP 备忘', at: 1 }, vis: 'public', pre: {} },
    { p: { text: 'KP 私密', at: 1 }, vis: 'seat', to: 'host', pre: {} },
  ],
  board: [
    { p: { seat: 'p1', self: true, strokes: [{ x: 1, y: 2 }], at: 1, thumb: 'x' }, pre: {} },
    { p: { seat: 'p2', strokes: [{ x: 3 }], at: 2 }, pre: {} },
    { p: {}, pre: {} },
  ],
  asset: [
    { p: { assets: [{ id: 'a1', kind: 'image', name: '图' }] }, pre: {} },
    { p: { assets: [] }, pre: {} },
    { p: {}, pre: {} },
  ],
  actor: [
    { p: { actor: { id: 'm1', name: '怪2' } }, pre: COMBAT_PRE },
    { p: { actor: { id: 'm2', name: '新怪' } }, pre: COMBAT_PRE },
    { p: {}, pre: {} },
  ],
  turnstate: [
    { p: { turn: 2, round: 3, order: [{ id: 'm1' }] }, pre: COMBAT_PRE },
    { p: { turn: 0 }, pre: COMBAT_PRE },
    { p: {}, pre: {} },
  ],
  check: [
    { p: { summary: '侦查成功', seat: 'p1', at: 1, kind: 'skill' }, vis: 'public', pre: {} },
    { p: { summary: '秘密检定：骰出 07，极难成功', seat: 'p1', at: 2, kind: 'check' }, vis: 'seat', to: 'p1', pre: {} },
    { p: { summary: '对抗结果', kind: 'opposed', winner: 'a', tie: false, a: { level: 3 }, b: { level: 2 }, decidedBy: 'level', rounds: [], damage: { applied: 3 } }, vis: 'public', pre: {} },
  ],
  request: [
    { p: { self: true, id: 'r1', op: 'sheet.damage', payload: { a: 1 }, from: 'KP', reason: 'x', at: 1 }, pre: {} },
    { p: { self: true, done: true, id: 'r1' }, pre: {} },
    { p: { self: false, id: 'r2' }, pre: {} },
  ],
  rewind: [
    { p: { rewind: { id: 'w', state: 'VOTING', votes: {} } }, pre: {} },
    { p: { rewind: null }, pre: {} },
    { p: {}, pre: {} },
  ],
  round: [{ p: { round: 3 }, pre: {} }, { p: { round: null }, pre: {} }, { p: {}, pre: {} }],
  tempcommit: [{ p: { any: 1 }, pre: {} }, { p: {}, pre: {} }, { p: { seq: 9 }, pre: COMBAT_PRE }],
  ended: [{ p: {}, pre: {} }, { p: { by: 'kp' }, pre: {} }, { p: {}, pre: COMBAT_PRE }],
  archive: [
    { p: { seq: 7, savedAt: 1, ok: true }, pre: {} },
    { p: { seq: 8, savedAt: 2, ok: false }, pre: {} },
    { p: {}, pre: {} },
  ],
  scenecheck: [
    { p: { id: 'sc1', title: 't', steps: [], cursor: 0, results: [] }, pre: {} },
    { p: { id: null }, pre: {} },
    { p: {}, pre: {} },
  ],
  state: [
    { p: { seat: 'p1', seq: 3, status: { currentHP: 5 }, at: 1 }, pre: {} },
    { p: { seat: 'p1', seq: 4, status: {}, at: 2 }, pre: {} },
    { p: {}, pre: {} },
  ],
  turnalert: [
    { p: { kind: 'turn', round: 2, turn: 1, name: '甲', seat: 'p1', at: 1 }, pre: {} },
    { p: {}, pre: {} },
    { p: { kind: 'round', round: 3 }, pre: {} },
  ],
  opposed: [
    { p: { id: 'o1', by: 'p1', phase: 'await_kp', weapon: '棍', db: '0', targetId: 'm1', targetName: '怪', at: 1 }, pre: {} },
    { p: { id: 'o1', phase: 'rejected' }, pre: {} },
    { p: {}, pre: {} },
  ],
};

Object.keys(M.EVT).forEach((key) => {
  const t = M.EVT[key];
  const variants = REDUCE_VARIANTS[t] || [{ p: {}, pre: {} }];
  variants.forEach((v, i) => {
    const args = {
      meta: {},
      state: v.pre || {},
      evt: { t, seq: i + 1, p: v.p || {}, vis: v.vis, to: v.to },
    };
    M_('reduce', args, `M:reduce:${t.toUpperCase()}`, () => {
      const st = M.emptyState(args.meta);
      Object.keys(args.state).forEach((k) => { st[k] = M.clone(args.state[k]); });
      return M.reduce(st, args.evt);
    });
  });
});

// ---- 状态 / 可见性助手 ----
[
  { text: 'x' }, { secret: 1 }, { a: { kpOnly: true } }, { a: [{ truth: 1 }] },
  { list: [1, 2] }, null, 'abc',
].forEach((p) => {
  M_('hasSecret', { p }, 'M:hasSecret', () => M.hasSecret(p));
});
[
  { text: 'x' }, { text: 'x', secret: 'leak' }, { a: { kpOnly: true, b: 2 } },
  { a: [{ truth: 1, ok: 2 }] }, null, 'abc',
].forEach((p) => {
  M_('scrub', { p }, 'M:scrub', () => M.scrub(p));
});
// ⚠️ ruleOptsOf 是 room-model.js 的**内部函数**（不在 41 个导出里），
//    无法经预言机取值 → 改由 Dart-only 用例覆盖（见 room_model_core_test.dart）。
[
  { body: '正常' }, { body: '重伤' }, { body: '死亡', dying: true }, { body: '轻伤', dying: true, unconscious: true },
  { unconscious: true }, null,
].forEach((status) => {
  M_('bodyView', { status }, 'M:bodyView', () => M.bodyView(status));
});
[[10, 10], [5, 10], [4, 10], [0, 10], [5, 0], [null, null]].forEach(([hp, maxHP]) => {
  M_('bodyForHp', { hp, maxHP }, 'M:bodyForHp', () => M.bodyForHp(hp, maxHP));
});
[
  { body: '濒死', currentHP: 3, maxHP: 10 },
  { body: '昏迷', currentHP: 8, maxHP: 10 },
  { body: '昏迷', currentHP: 2, maxHP: 10 },
  { body: '重伤', dying: true },
  { body: '正常' },
  null,
].forEach((status) => {
  M_('migrateBodyStatus', { status }, 'M:migrateBodyStatus', () => {
    const st = status === null ? null : M.clone(status);
    return M.migrateBodyStatus(st);
  });
});
['abcd', 'ABC123', 'ab', 'a'.repeat(13), '', null, 'a-b_cd', 'x9y8'].forEach((c) => {
  M_('validCode', { c }, 'M:validCode', () => M.validCode(c));
});
[['hi', null], ['hi', 2], ['  a\u0001b  ', null], ['', null], [null, null], ['x'.repeat(10), 3]].forEach(([s, max]) => {
  M_('cleanText', { s, max }, 'M:cleanText', () => M.cleanText(s, max));
});
[
  ['http://x/y', 'abcd', ''],
  ['http://x/y?a=1', 'abcd', 'http://h:8080'],
  ['', 'zzzz', ''],
  ['http://x/y#frag', 'abcd', ''],
].forEach(([pageUrl, code, serverBase]) => {
  M_('inviteLink', { pageUrl, code, serverBase }, 'M:inviteLink',
    () => M.inviteLink(pageUrl, code, serverBase));
});
[
  'COC7ROOM|1.2.3.4:8080|abcd',
  'COC7ROOM|1.2.3.4:8080|',
  'http://h/x?room=abcd&srv=http://s:1',
  '?room=abcd',
  'http://h:8080',
  '1.2.3.4:8080',
  'abcd',
  '',
  'zz',
  null,
].forEach((s) => {
  M_('readInvite', { s }, 'M:readInvite', () => M.readInvite(s));
});
[[{}], [{ code: 'abcd', name: '房间' }], [{ status: 'IN_GAME', mode: 'COMBAT' }],
  [{ critThreshold: 5, fumbleThreshold: 95, maxPlayers: 6 }], [null]].forEach(([meta]) => {
  M_('emptyState', { meta }, 'M:emptyState', () => M.emptyState(meta));
});
[{ a: 1, b: [1, { c: 2 }] }, [1, [2]], 'x', null].forEach((x) => {
  M_('clone', { x }, 'M:clone', () => M.clone(x));
});

// ---- 信封 ----
M_('syncMsg', { seq: 3, state: { meta: { code: 'abcd' }, seq: 3 } }, 'M:syncMsg',
  () => M.syncMsg(3, { meta: { code: 'abcd' }, seq: 3 }));
M_('evtMsg', { rec: { seq: 4, evt: { t: 'chat', p: { text: 'hi' }, vis: 'public', to: null } } }, 'M:evtMsg',
  () => M.evtMsg({ seq: 4, evt: { t: 'chat', p: { text: 'hi' }, vis: 'public', to: null } }));
M_('skipMsg', { seq: 5 }, 'M:skipMsg', () => M.skipMsg(5));
M_('intentMsg', { op: 'chat', p: { text: 'hi' } }, 'M:intentMsg', () => M.intentMsg('chat', { text: 'hi' }));
[
  '{"k":"sync","seq":1,"state":{}}',
  '{"k":"evt","seq":2,"t":"chat","p":{}}',
  '{"k":"skip","seq":3}',
  '{"k":"intent","op":"chat","p":{}}',
  '{"k":"host.gone"}',
  '{"k":"unknown"}',
  'not json',
  '[]',
  '"str"',
  '',
].forEach((raw) => {
  M_('parse', { raw }, 'M:parse', () => M.parse(raw));
});

// ---- Log / Roster 脚本 ----
function runLogScript(ops) {
  const log = new M.Log(ops.cap || undefined);
  const out = [];
  ops.ops.forEach((op) => {
    if (op.op === 'push') out.push(log.push(op.evt));
    else if (op.op === 'since') out.push(log.since(op.fromSeq));
    else if (op.op === 'canFill') out.push(log.canFill(op.fromSeq));
    else if (op.op === 'rollbackBefore') out.push(log.rollbackBefore(op.beforeSeq));
    else throw new Error('unknown log op ' + op.op);
  });
  return { out: J(out), seq: log.seq, truncated: log.truncated, items: log.items.map((r) => r.seq) };
}
const LOG_SCRIPTS = [
  { cap: 400, ops: [{ op: 'push', evt: { t: 'chat', p: {} } }, { op: 'push', evt: { t: 'log', p: {} } }, { op: 'since', fromSeq: 0 }, { op: 'since', fromSeq: 1 }, { op: 'canFill', fromSeq: 0 }, { op: 'canFill', fromSeq: 2 }] },
  { cap: 2, ops: [{ op: 'push', evt: { t: 'chat', p: {} } }, { op: 'push', evt: { t: 'log', p: {} } }, { op: 'push', evt: { t: 'log', p: {} } }, { op: 'canFill', fromSeq: 0 }] },
  { cap: 400, ops: [{ op: 'push', evt: { t: 'chat', p: {} } }, { op: 'push', evt: { t: 'log', p: {} } }, { op: 'rollbackBefore', beforeSeq: 2 }, { op: 'since', fromSeq: 0 }] },
  { cap: 400, ops: [{ op: 'rollbackBefore', beforeSeq: 1 }] },
  { cap: 400, ops: [{ op: 'push', evt: { t: 'round', p: { round: 2 } } }, { op: 'rollbackBefore', beforeSeq: 5 }] },
  { cap: 1, ops: [{ op: 'push', evt: { t: 'a', p: {} } }, { op: 'push', evt: { t: 'b', p: {} } }, { op: 'push', evt: { t: 'c', p: {} } }] },
  { cap: 3, ops: [{ op: 'push', evt: { t: 'a', p: {} } }, { op: 'canFill', fromSeq: 1 }, { op: 'canFill', fromSeq: 3 }] },
  { cap: 400, ops: [{ op: 'since', fromSeq: 99 }, { op: 'canFill', fromSeq: 99 }] },
];
LOG_SCRIPTS.forEach((ops) => {
  M_('logScript', { ops }, 'M:logScript', () => runLogScript(ops));
});
// ---- 恢复：入参 evt 携带 vis/to 的 6 组 logScript（M:logScript:visTo）----
// 前一版为绕开「Dart 出站 evt 多了 {vis,to}」的差异，把这一整组用例删掉了
// （room_model.json 517 → 511，tag 359 → 358）。本轮在 domain 层把「内部
// RoomEvent（带 vis/to/seq，供 Q1 重放）」与「对外 wire 形状（旧版 Log.push
// 原样保存入参）」分开后，这组用例可以逐字段严格等价，故原样恢复。
// 旧版 Log.push(:370-379) 不规范化入参：evt 的键集合 = push 入参的键集合，
// 所以这 6 组同时覆盖「带 vis/to」「只带 vis」「不带」以及 since/rollback/cap。
const VIS_TO_LOG_SCRIPTS = [
  { cap: 400, ops: [
    { op: 'push', evt: { t: 'chat', p: { text: 'hi' }, vis: 'public', to: null } },
    { op: 'since', fromSeq: 0 },
  ] },
  { cap: 400, ops: [
    { op: 'push', evt: { t: 'check', p: { summary: '秘密检定：骰出 07' }, vis: 'seat', to: 'p1' } },
    { op: 'since', fromSeq: 0 },
    { op: 'canFill', fromSeq: 0 },
  ] },
  { cap: 400, ops: [
    { op: 'push', evt: { t: 'chat', p: {}, vis: 'public', to: null } },
    { op: 'push', evt: { t: 'log', p: { text: 'x' } } },
    { op: 'push', evt: { t: 'private', p: { text: 'y' }, vis: 'seat', to: 'p2' } },
    { op: 'since', fromSeq: 1 },
  ] },
  { cap: 2, ops: [
    { op: 'push', evt: { t: 'a', p: {}, vis: 'public', to: null } },
    { op: 'push', evt: { t: 'b', p: {} } },
    { op: 'push', evt: { t: 'c', p: {}, vis: 'kp', to: null } },
    { op: 'since', fromSeq: 0 },
    { op: 'canFill', fromSeq: 0 },
  ] },
  { cap: 400, ops: [
    { op: 'push', evt: { t: 'chat', p: {}, vis: 'public', to: null } },
    { op: 'push', evt: { t: 'log', p: {} } },
    { op: 'rollbackBefore', beforeSeq: 2 },
    { op: 'since', fromSeq: 0 },
  ] },
  { cap: 400, ops: [
    { op: 'push', evt: { t: 'log', p: { text: 'z' }, vis: 'kp' } },
    { op: 'since', fromSeq: 1 },
    { op: 'canFill', fromSeq: 99 },
  ] },
];
VIS_TO_LOG_SCRIPTS.forEach((ops) => {
  M_('logScript', { ops }, 'M:logScript:visTo', () => runLogScript(ops));
});

function runRosterScript(ops) {
  const r = new M.Roster();
  const out = [];
  ops.forEach((op) => {
    if (op.op === 'open') out.push(r.open(op.m));
    else if (op.op === 'markOffline') out.push(r.markOffline(op.seat));
    else if (op.op === 'remove') out.push(r.remove(op.seat));
    else if (op.op === 'get') out.push(r.get(op.seat));
    else if (op.op === 'list') out.push(r.list());
    else if (op.op === 'players') out.push(r.players());
    else if (op.op === 'spectators') out.push(r.spectators());
    else if (op.op === 'onlinePlayers') out.push(r.onlinePlayers());
    else if (op.op === 'allReady') out.push(r.allReady());
    else if (op.op === 'dump') out.push(r.dump());
    else throw new Error('unknown roster op ' + op.op);
  });
  return { out: J(out), order: r.order, kicked: Object.keys(r.kicked), bySeat: J(r.bySeat) };
}
const ROSTER_SCRIPTS = [
  [{ op: 'open', m: { seat: 'p1', nickname: '甲', at: 1 } }, { op: 'open', m: { seat: 'p2', role: 'spectator', at: 2 } }, { op: 'list' }, { op: 'players' }, { op: 'spectators' }, { op: 'dump' }],
  [{ op: 'open', m: { seat: 'p1', at: 1 } }, { op: 'markOffline', seat: 'p1' }, { op: 'onlinePlayers' }, { op: 'allReady' }],
  [{ op: 'open', m: { seat: 'p1', at: 1 } }, { op: 'remove', seat: 'p1' }, { op: 'dump' }, { op: 'remove', seat: 'p1' }],
  [{ op: 'open', m: { seat: 'p1', at: 1 } }, { op: 'get', seat: 'host' }, { op: 'get', seat: 'p1' }],
  [{ op: 'allReady' }],
  [{ op: 'open', m: { seat: 'p1', at: 1 } }, { op: 'open', m: { seat: 'p1', role: 'player', nickname: '新名' } }, { op: 'list' }],
  [{ op: 'open', m: { cid: 'c1', at: 1 } }, { op: 'list' }],
  [{ op: 'open', m: {} }],
];
ROSTER_SCRIPTS.forEach((ops) => {
  M_('rosterScript', { ops }, 'M:rosterScript', () => runRosterScript(ops));
});

// ---- sanitizeSheet / sanitizeSceneSteps ----
const SHEET_PAYLOADS = [
  { sheet: { name: '张三', charId: 'c1', attrs: { str: 50 }, status: { currentHP: 10, maxHP: 12 }, skills: [{ name: '侦查', total: 60 }], mental: ['正常'], madness: [], db: '+1D4' } },
  { sheet: { name: '', status: { body: '濒死', currentHP: 0, maxHP: 10 }, madness: [{ type: 'phobia', name: '恐高', permanent: true, bg: true }], weapons: [{ name: '棍', pierce: '√', perRound: '1' }] } },
  { sheet: { name: '李四', avatar: 'data:image/png;base64,AAA', tempStatus: [{ text: '中毒', by: 'kp', at: 1 }], items: [{ id: 'i1', name: '手电', qty: 2 }] } },
  { name: '王五' },
  {},
  { sheet: { mental: ['正常', '永久疯狂'], madness: [{ type: 'bout', name: '狂躁', permanent: false, rounds: 3 }] } },
];
SHEET_PAYLOADS.forEach((p) => {
  M_('sanitizeSheet', { p }, 'M:sanitizeSheet', () => M.sanitizeSheet(J(p)));
});
const SCENE_STEP_PAYLOADS = [
  [{ id: 's1', title: 't', onSuccess: { damage: '1D3', note: 'n', next: 'end' } }],
  [{}, { targetSeat: 'p1', bonus: 9, penalty: -2 }],
  [],
  [{ difficulty: 'HARD' }, { difficulty: 'EXTREME' }, { difficulty: 'bogus' }],
];
SCENE_STEP_PAYLOADS.forEach((arr) => {
  M_('sanitizeSceneSteps', { arr }, 'M:sanitizeSceneSteps', () => M.sanitizeSceneSteps(J(arr)));
});

// ---- parseSave / restoreHost / playerViewFromSave / applyStateToCard ----
const SAVE_FIXTURE = {
  v: 2, code: 'abcd', rules: 'coc7', savedAt: 1700000000000, seq: 3, stateSeq: 1,
  meta: { code: 'abcd', name: '房间', status: 'IN_GAME' },
  members: [{ seat: 'p1', role: 'player', online: false, sheet: { name: '甲', status: { body: '濒死', currentHP: 0, maxHP: 10 } } }],
  chats: [{ seq: 1, seat: 'p1', text: 'hi', at: 1, kind: 'user' }],
  logs: [], dice: [], scene: null, combat: null, sceneCheck: null,
  roundStarts: [{ round: 1, seq: 1 }], privateBySeat: { p1: [{ seq: 2, text: '线索' }] },
  requestsBySeat: [{ seat: 'p1', payload: { a: 1 } }],
  boardBySeat: { p1: { strokes: [] } }, localAssets: [], localActors: [],
};
M_('parseSave', { payload: SAVE_FIXTURE }, 'M:parseSave', () => M.parseSave(J(SAVE_FIXTURE)));
M_('parseSave', { payload: JSON.stringify(SAVE_FIXTURE) }, 'M:parseSave',
  () => M.parseSave(JSON.stringify(SAVE_FIXTURE)));
M_('parseSave', { payload: 'not json' }, 'M:parseSave', () => M.parseSave('not json'));
M_('parseSave', { payload: '' }, 'M:parseSave', () => M.parseSave(''));
M_('parseSave', { payload: null }, 'M:parseSave', () => M.parseSave(null));
[
  { storeState: { characters: { c1: { id: 'c1', status: {} } }, current: null }, charId: 'c1', patch: { status: { currentHP: 3 } } },
  { storeState: { characters: {}, current: { id: 'cur', status: {} } }, charId: 'c9', patch: { status: { currentHP: 3 } } },
  { storeState: { characters: {}, current: { id: 'cur', status: {} } }, charId: null, patch: { status: { currentHP: 3 } } },
  { storeState: { characters: {}, current: null }, charId: null, patch: {} },
  { storeState: null, charId: 'c1', patch: {} },
  { storeState: { characters: { c1: { id: 'c1', status: {} } }, current: null }, charId: 'c1', patch: { status: { body: '重伤' }, madness: [], tempStatus: [{ text: 'x' }] } },
].forEach(({ storeState, charId, patch }) => {
  M_('applyStateToCard', { storeState, charId, patch }, 'M:applyStateToCard', () => {
    let saved = 0;
    const store = storeState === null ? null : {
      getState: () => J(storeState),
      saveNow: () => { saved += 1; },
    };
    const res = M.applyStateToCard(store, charId, J(patch));
    return { res, saved };
  });
});

/* ============================================================
 * 三、room_sequences.json —— seq / skip / rollback / 可见性
 * ============================================================ */

function runClientScript(args) {
  const c = new M.Client({ seat: args.seat || '', role: args.role || 'player', meta: args.meta || {} });
  const steps = [];
  for (const op of args.ops) {
    switch (op.op) {
      case 'receive': steps.push(c.receive(op.raw)); break;
      case 'intent': steps.push(c.intent(op.k, op.p)); break;
      case 'resyncIntent': steps.push(c.resyncIntent()); break;
      case 'resyncDiag': steps.push(c.resyncDiag()); break;
      case 'applySheetState': steps.push(c.applySheetState(op.seq, op.patch)); break;
      case 'member': steps.push(c.member(op.seat)); break;
      case 'isReady': steps.push(c.isReady()); break;
      default: throw new Error('unknown client op ' + op.op);
    }
  }
  return {
    steps: J(steps),
    lastSeq: c.lastSeq,
    gapFrom: c.gapFrom,
    rejected: c.rejected,
    lastStateSeq: c.lastStateSeq,
    state: J(c.state),
    sheetState: J(c.sheetState),
  };
}

function runHostScript(args) {
  const h = new M.Host({
    meta: args.meta || {},
    snapshotEvery: args.snapshotEvery || 20,
    logCap: args.logCap || 400,
  });
  const steps = [];
  let saveOut = null;
  for (const op of args.ops) {
    switch (op.op) {
      case 'attach': steps.push(h.attachPeer(op.m)); break;
      case 'detach': steps.push(h.detachPeer(op.seat)); break;
      case 'emit': {
        const rec = h.emit(op.t, J(op.p || {}), op.vis, op.to);
        const plans = op.plan ? h.plan(rec) : null;
        steps.push({ seq: rec.seq, plan: plans });
        break;
      }
      case 'emitLocal': {
        const rec = h.emitLocal(op.t, J(op.p || {}));
        steps.push({ seq: rec.seq, evt: rec.evt });
        break;
      }
      case 'syncFor': steps.push(h.syncFor(op.seat)); break;
      case 'makeSync': steps.push(h._makeSync(op.seat, undefined, undefined)); break;
      case 'intent': steps.push(h.intent(op.seat, J(op.msg))); break;
      case 'rollback': steps.push(h.rollback(op.before)); break;
      case 'rollbackPlan': steps.push(h.rollbackPlan(op.before)); break;
      case 'setStatus': steps.push(h.setStatus(op.s)); break;
      case 'closeRoom': steps.push(h.closeRoom()); break;
      case 'endSession': steps.push(h.endSession()); break;
      case 'kick': steps.push(h.kick(op.seat)); break;
      case 'nextTurn': steps.push(h.nextTurn()); break;
      case 'applyAction': steps.push(h.applyAction(op.seat, J(op.p || {}))); break;
      case 'save': saveOut = h.save(); steps.push(null); break;
      default: throw new Error('unknown host op ' + op.op);
    }
  }
  return {
    steps: J(steps),
    state: J(h.state),
    logSeq: h.log.seq,
    log: h.log.items.map((r) => ({ seq: r.seq, t: r.evt.t, vis: r.evt.vis, to: r.evt.to })),
    warnings: J(h.warnings),
    snapshotSeqs: h.snapshots.map((s) => s.seq),
    roundStarts: J(h.roundStarts),
    save: J(saveOut),
    saveKeys: saveOut ? Object.keys(saveOut) : null,
  };
}

/** 两个玩家在线的最小房间 */
function twoPeerOps() {
  return [
    { op: 'attach', m: { seat: 'p1', nickname: '甲', at: 1 } },
    { op: 'attach', m: { seat: 'p2', nickname: '乙', at: 2 } },
  ];
}

// ---- S:seq —— Client 序号闸门 ----
const SEQ_SCRIPTS = [
  [{ op: 'receive', raw: { k: 'evt', seq: 1, t: 'log', p: { text: 'a' } } },
    { op: 'receive', raw: { k: 'evt', seq: 1, t: 'log', p: { text: 'a' } } },
    { op: 'receive', raw: { k: 'evt', seq: 3, t: 'log', p: { text: 'c' } } },
    { op: 'receive', raw: { k: 'evt', seq: 2, t: 'log', p: { text: 'b' } } }],
  [{ op: 'receive', raw: { k: 'evt', seq: 2, t: 'log', p: {} } },
    { op: 'receive', raw: { k: 'evt', seq: 1, t: 'log', p: {} } }],
  [{ op: 'receive', raw: { k: 'sync', seq: 5, state: { meta: {}, logs: [], seq: 5 } } },
    { op: 'receive', raw: { k: 'evt', seq: 5, t: 'log', p: {} } },
    { op: 'receive', raw: { k: 'evt', seq: 6, t: 'log', p: {} } }],
  [{ op: 'receive', raw: { k: 'skip', seq: 1 } },
    { op: 'receive', raw: { k: 'skip', seq: 1 } },
    { op: 'receive', raw: { k: 'skip', seq: 3 } },
    { op: 'receive', raw: { k: 'evt', seq: 3, t: 'log', p: {} } }],
  [{ op: 'receive', raw: { k: 'intent', op: 'chat', p: {} } },
    { op: 'receive', raw: '{"k":"unknown"}' },
    { op: 'receive', raw: 'not json' }],
  [{ op: 'receive', raw: { k: 'skip', seq: 2 } },
    { op: 'receive', raw: { k: 'evt', seq: 1, t: 'log', p: {} } },
    { op: 'receive', raw: { k: 'evt', seq: 2, t: 'log', p: {} } }],
  [{ op: 'resyncIntent' }, { op: 'resyncDiag' }],
  [{ op: 'receive', raw: { k: 'evt', seq: 1, t: 'log', p: {} } },
    { op: 'receive', raw: { k: 'evt', seq: 4, t: 'log', p: {} } },
    { op: 'resyncIntent' }, { op: 'resyncDiag' },
    { op: 'receive', raw: { k: 'evt', seq: 2, t: 'log', p: {} } },
    { op: 'receive', raw: { k: 'evt', seq: 3, t: 'log', p: {} } },
    { op: 'resyncDiag' }],
  [{ op: 'applySheetState', seq: 1, patch: { status: { currentHP: 5 } } },
    { op: 'applySheetState', seq: 1, patch: { status: { currentHP: 5 } } },
    { op: 'applySheetState', seq: 2, patch: { status: { currentHP: 4 } } },
    { op: 'applySheetState', seq: 0, patch: {} },
    { op: 'applySheetState', seq: -1, patch: {} }],
  [{ op: 'receive', raw: { k: 'evt', seq: 1, t: 'members', p: { members: [{ seat: 'p1', ready: true }] } } },
    { op: 'member', seat: 'p1' }, { op: 'isReady' }, { op: 'member' }],
];
SEQ_SCRIPTS.forEach((ops) => {
  S_('clientScript', { seat: 'p1', role: 'player', meta: {}, ops }, 'S:seq', () => runClientScript({ seat: 'p1', role: 'player', meta: {}, ops }));
});
// 乱序 / 重复 / 补拉：参数化生成
for (let n = 1; n <= 6; n++) {
  const ops = [];
  for (const s of [1, 2, 3, 4, 5, 6].slice(0, n)) {
    ops.push({ op: 'receive', raw: { k: 'evt', seq: s, t: 'log', p: { text: `e${s}` } } });
  }
  ops.push({ op: 'resyncDiag' });
  S_('clientScript', { seat: 'p1', ops }, 'S:seq', () => runClientScript({ seat: 'p1', ops }));
}

// ---- S:skip —— SEAT 事件给其余在线者发水位 ----
const SKIP_SCRIPTS = [
  [...twoPeerOps(), { op: 'emit', t: 'private', p: { text: '只给 p1' }, vis: 'seat', to: 'p1', plan: true }],
  [...twoPeerOps(), { op: 'emit', t: 'check', p: { summary: 's', secret: 'x' }, vis: 'seat', to: 'p1', plan: true }],
  [...twoPeerOps(), { op: 'emit', t: 'private', p: { text: 'x' }, vis: 'seat', to: null, plan: true }],
  [...twoPeerOps(), { op: 'emit', t: 'chat', p: { text: 'hi' }, vis: 'public', plan: true }],
  [...twoPeerOps(), { op: 'emit', t: 'chat', p: { text: 'hi', secret: 'leak' }, vis: 'public', plan: true }],
  [...twoPeerOps(), { op: 'emit', t: 'log', p: { text: 'kp 内部' }, vis: 'kp', plan: true }],
  [...twoPeerOps(), { op: 'emit', t: 'members', p: { members: [{ seat: 'p1', sheet: { name: '甲', status: { currentHP: 5 } } }] }, vis: 'public', plan: true }],
  [...twoPeerOps(), { op: 'emit', t: 'combat', p: { combat: { order: [{ id: 'm1', public: { hp: 10, hpMax: 10 }, secret: 'x' }] } }, vis: 'public', plan: true }],
];
SKIP_SCRIPTS.forEach((ops) => {
  S_('hostScript', { meta: { code: 'abcd' }, ops }, 'S:skip', () => runHostScript({ meta: { code: 'abcd' }, ops }));
});

// ---- S:canFill —— 增量补齐 vs 全量 ----
for (const cap of [2, 3, 400]) {
  for (const emits of [1, 2, 5]) {
    const ops = [...twoPeerOps()];
    for (let i = 1; i <= emits; i++) ops.push({ op: 'emit', t: 'log', p: { text: `l${i}` }, vis: 'public' });
    ops.push({ op: 'intent', seat: 'p1', msg: { op: 'sync', p: { lastSeq: 0 } } });
    ops.push({ op: 'intent', seat: 'p2', msg: { op: 'sync', p: { lastSeq: emits } } });
    S_('hostScript', { meta: {}, logCap: cap, ops }, 'S:canFill', () => runHostScript({ meta: {}, logCap: cap, ops }));
  }
}

// ---- S:rollback —— 快照 + 重放 ----
for (const snapshotEvery of [1, 2, 5]) {
  for (const before of [2, 3, 4]) {
    const ops = [...twoPeerOps()];
    for (let i = 1; i <= 4; i++) ops.push({ op: 'emit', t: 'log', p: { text: `l${i}`, at: i }, vis: 'public' });
    ops.push({ op: 'rollback', before });
    ops.push({ op: 'rollbackPlan', before: 1 });
    S_('hostScript', { meta: {}, snapshotEvery, ops }, 'S:rollback', () => runHostScript({ meta: {}, snapshotEvery, ops }));
  }
}
// 回合边界 + 回退
for (const before of [3, 4]) {
  const ops = [...twoPeerOps(),
    { op: 'emit', t: 'round', p: { round: 1 }, vis: 'public' },
    { op: 'emit', t: 'log', p: { text: 'a' }, vis: 'public' },
    { op: 'emit', t: 'round', p: { round: 2 }, vis: 'public' },
    { op: 'emit', t: 'log', p: { text: 'b' }, vis: 'public' },
    { op: 'rollback', before },
  ];
  S_('hostScript', { meta: {}, snapshotEvery: 1, ops }, 'S:rollback', () => runHostScript({ meta: {}, snapshotEvery: 1, ops }));
}

// ---- S:q1 —— KP 秘密 CHECK + 回退（白名单场景）----
for (const snapshotEvery of [2, 3]) {
  const ops = [...twoPeerOps(),
    { op: 'emit', t: 'chat', p: { seat: 'host', nickname: 'KP', text: '开始', at: 1 }, vis: 'public' },
    { op: 'emit', t: 'log', p: { text: '场景一', at: 2 }, vis: 'public' },
    { op: 'emit', t: 'check', p: { summary: '秘密检定：骰出 07，极难成功', seat: 'p1', at: 3, kind: 'check' }, vis: 'seat', to: 'p1' },
    { op: 'emit', t: 'private', p: { text: '线索A', title: '只给p1', at: 4 }, vis: 'seat', to: 'p1' },
    { op: 'emit', t: 'chat', p: { seat: 'p1', text: '然后呢', at: 5 }, vis: 'public' },
    // ★ F5：twoPeerOps() 的两次 attach 占掉 seq1/seq2，5 条 emit 是 seq3..seq7，
    //   秘密 CHECK 在 **seq5**、定向 PRIVATE 在 seq6。原来 rollback(5) 的
    //   target=4 会把 CHECK/PRIVATE 一并裁掉，重放区间里根本没有秘密事件
    //   → 旧版 Q1 缺陷无法触发、白名单 14 条成了死登记。
    //   改成 rollback(6)（target=5）：snapshotEvery=2 命中 @4 快照、
    //   重放 (4,5] = seq5 CHECK；snapshotEvery=3 命中 @3 快照、
    //   重放 (3,5] = seq4 LOG + seq5 CHECK。两者都真正重放秘密 CHECK。
    { op: 'rollback', before: 6 },
    { op: 'syncFor', seat: 'p2' },
    { op: 'syncFor', seat: 'p1' },
  ];
  S_('hostScript', { meta: { code: 'abcd' }, snapshotEvery, ops }, 'S:q1', () => runHostScript({ meta: { code: 'abcd' }, snapshotEvery, ops }));
}
// PRIVATE 守卫：KP 定向（to=host）不进 state.privates 的重放验证
S_('hostScript', {
  meta: {},
  snapshotEvery: 1,
  ops: [...twoPeerOps(),
    { op: 'emit', t: 'private', p: { text: '暗骰：07', at: 1 }, vis: 'seat', to: 'host' },
    { op: 'emit', t: 'log', p: { text: 'x' }, vis: 'public' },
    { op: 'rollback', before: 3 },
    { op: 'syncFor', seat: 'p2' }],
}, 'S:q1', () => runHostScript({
  meta: {}, snapshotEvery: 1,
  ops: [...twoPeerOps(),
    { op: 'emit', t: 'private', p: { text: '暗骰：07', at: 1 }, vis: 'seat', to: 'host' },
    { op: 'emit', t: 'log', p: { text: 'x' }, vis: 'public' },
    { op: 'rollback', before: 3 },
    { op: 'syncFor', seat: 'p2' }],
}));

// ---- S:status —— CLOSED / ENDED / KICK / SUSPENDED ----
[
  { ops: [{ op: 'closeRoom' }] },
  { ops: [{ op: 'setStatus', s: 'SUSPENDED' }] },
  { ops: [{ op: 'setStatus', s: 'IN_GAME' }, { op: 'endSession' }] },
  { ops: [{ op: 'kick', seat: 'p1' }] },
  { ops: [{ op: 'kick', seat: 'ghost' }] },
  { ops: [{ op: 'setStatus', s: 'CLOSED' }] },
  { ops: [{ op: 'nextTurn' }] },
  { ops: [{ op: 'emitLocal', t: 'log', p: { text: '备忘' } }, { op: 'emitLocal', t: 'log', p: { text: '备忘2' } }] },
].forEach(({ ops }) => {
  const full = [...twoPeerOps(), ...ops];
  S_('hostScript', { meta: {}, ops: full }, 'S:status', () => runHostScript({ meta: {}, ops: full }));
});

// ---- S:intent —— 意图入口的权限拒绝 ----
[
  { role: 'p1', msg: { op: 'act', p: { op: 'room.start' } } },
  { role: 'p1', msg: { op: 'act', p: { op: 'rollback.turn' } } },
  { role: 'p1', msg: { op: 'act', p: { op: '__unknown__' } } },
  { role: 'p1', msg: { op: 'chat', p: { text: 'hi' } } },
  { role: 'host', msg: { op: 'chat', p: { text: 'hi' } } },
  { role: 'p3', msg: { op: 'chat', p: { text: 'hi' } } },
  { role: 'p1', msg: { op: 'ready', p: { ready: true } } },
  { role: 'p1', msg: { op: 'nope', p: {} } },
  { role: 'p1', msg: { op: 'act', p: { op: 'scene.mode', mode: 'COMBAT' } } },
  { role: 'host', msg: { op: 'act', p: { op: 'round.next' } } },
].forEach(({ role, msg }) => {
  const full = [...twoPeerOps(), { op: 'intent', seat: role, msg }];
  S_('hostScript', { meta: {}, ops: full }, 'S:intent', () => runHostScript({ meta: {}, ops: full }));
});

// ---- S:legacy —— 旧存档回放（CUT-1）----
[
  { ops: [{ op: 'save' }] },
  { ops: [{ op: 'save' }, { op: 'emit', t: 'chat', p: { text: 'after' }, vis: 'public' }, { op: 'save' }] },
].forEach(({ ops }) => {
  const full = [...twoPeerOps(), ...ops];
  S_('hostScript', { meta: { code: 'abcd' }, ops: full }, 'S:legacy', () => runHostScript({ meta: { code: 'abcd' }, ops: full }));
});
M_('restoreHost', { save: SAVE_FIXTURE }, 'M:restoreHost', () => {
  const h = M.restoreHost(J(SAVE_FIXTURE));
  return h ? { state: J(h.state), logSeq: h.log.seq, members: J(h.roster.dump()) } : null;
});
M_('restoreHost', { save: 'not json' }, 'M:restoreHost', () => M.restoreHost('not json'));
M_('playerViewFromSave', { save: SAVE_FIXTURE, seat: 'p1' }, 'M:playerViewFromSave',
  () => M.playerViewFromSave(J(SAVE_FIXTURE), 'p1'));
M_('playerViewFromSave', { save: SAVE_FIXTURE, seat: 'p2' }, 'M:playerViewFromSave',
  () => M.playerViewFromSave(J(SAVE_FIXTURE), 'p2'));

// ---- hostScript 覆盖 26 reduce 分支（emit 路径）----
Object.keys(M.EVT).forEach((key, i) => {
  const t = M.EVT[key];
  const v = (REDUCE_VARIANTS[t] || [{ p: {} }])[0];
  const ops = [...twoPeerOps(), { op: 'emit', t, p: v.p || {}, vis: v.vis || 'public', to: v.to, plan: true }];
  S_('hostScript', { meta: {}, ops }, `S:emit:${t.toUpperCase()}`, () => runHostScript({ meta: {}, ops }));
});

// ---- 追加：seq 全排列 / skip 与 evt 交错（覆盖「乱序、重复、跳跃、补拉」组合）----
const PERMS3 = [[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]];
PERMS3.forEach((perm) => {
  const ops = perm.map((s) => ({ op: 'receive', raw: { k: 'evt', seq: s, t: 'log', p: { text: `e${s}` } } }));
  ops.push({ op: 'resyncDiag' });
  S_('clientScript', { seat: 'p1', ops }, 'S:seq', () => runClientScript({ seat: 'p1', ops }));
});
[
  [{ k: 'skip', seq: 1 }, { k: 'evt', seq: 2, t: 'log', p: {} }],
  [{ k: 'evt', seq: 1, t: 'log', p: {} }, { k: 'skip', seq: 2 }],
  [{ k: 'skip', seq: 1 }, { k: 'skip', seq: 2 }, { k: 'evt', seq: 3, t: 'chat', p: {} }],
  [{ k: 'evt', seq: 2, t: 'log', p: {} }, { k: 'skip', seq: 1 }],
  [{ k: 'skip', seq: 1 }, { k: 'sync', seq: 9, state: { meta: {}, seq: 9 } }, { k: 'evt', seq: 10, t: 'log', p: {} }],
].forEach((raws) => {
  const ops = raws.map((raw) => ({ op: 'receive', raw }));
  S_('clientScript', { seat: 'p1', ops }, 'S:seq', () => runClientScript({ seat: 'p1', ops }));
});

// ---- 追加：三层回退点 / 掉线重连 / 三人在线广播 ----
for (const before of [1, 2, 3, 4, 5, 6]) {
  const ops = [...twoPeerOps()];
  for (let i = 1; i <= 6; i++) ops.push({ op: 'emit', t: 'log', p: { text: `l${i}` }, vis: 'public' });
  ops.push({ op: 'rollback', before });
  S_('hostScript', { meta: {}, snapshotEvery: 1, ops }, 'S:rollback',
    () => runHostScript({ meta: {}, snapshotEvery: 1, ops }));
}
[
  [...twoPeerOps(), { op: 'detach', seat: 'p1' }],
  [...twoPeerOps(), { op: 'detach', seat: 'ghost' }],
  [...twoPeerOps(), { op: 'detach', seat: 'p1' }, { op: 'attach', m: { seat: 'p1', nickname: '甲', at: 9 } }],
  [...twoPeerOps(), { op: 'attach', m: { seat: 'p1', nickname: '甲', at: 9 } }],
  [...twoPeerOps(), { op: 'attach', m: { seat: 'p3', role: 'spectator', at: 3 } },
    { op: 'emit', t: 'chat', p: { text: 'hi' }, vis: 'public', plan: true }],
  [...twoPeerOps(), { op: 'attach', m: {} }],
].forEach((ops) => {
  S_('hostScript', { meta: {}, ops }, 'S:skip', () => runHostScript({ meta: {}, ops }));
});

// ---- 追加：存档往返（旧存档回放 CUT-1）----
[
  [...twoPeerOps(), { op: 'save' }, { op: 'emit', t: 'round', p: { round: 1 }, vis: 'public' }, { op: 'save' }],
  [...twoPeerOps(), { op: 'emit', t: 'private', p: { text: '线索' }, vis: 'seat', to: 'p1' }, { op: 'save' }],
  [...twoPeerOps(), { op: 'emit', t: 'scene', p: { scene: { title: 't' } }, vis: 'public' }, { op: 'save' }],
  [...twoPeerOps(), { op: 'emit', t: 'private', p: { text: 'x' }, vis: 'seat', to: 'host' }, { op: 'save' }],
].forEach((ops) => {
  S_('hostScript', { meta: { code: 'abcd' }, ops }, 'S:legacy',
    () => runHostScript({ meta: { code: 'abcd' }, ops }));
});

/* ============================================================
 * 四、落盘 + 覆盖矩阵自检
 * ============================================================ */

function write(name, cases) {
  const tags = {};
  cases.forEach((c) => { tags[c.tag] = (tags[c.tag] || 0) + 1; });
  const payload = {
    generatedAt: Date.now(),
    total: cases.length,
    tags,
    cases,
  };
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, name), JSON.stringify(payload, null, 1), 'utf8');
  console.log(`${name}: ${cases.length} 例 / ${Object.keys(tags).length} 个 tag`);
  return cases.length;
}

const nR = write('room_rules.json', R_CASES);
const nM = write('room_model.json', M_CASES);
const nS = write('room_sequences.json', S_CASES);

/* ---- 覆盖矩阵自检（缺口直接失败，避免「fixture 少一截却没人发现」）---- */
const problems = [];
function need(label, cond) { if (!cond) problems.push(label); }

need(`room_rules ≥420（实际 ${nR}）`, nR >= 420);
need(`room_model ≥460（实际 ${nM}）`, nM >= 460);
need(`room_sequences ≥120（实际 ${nS}）`, nS >= 120);
need(`合计 ≥1000（实际 ${nR + nM + nS}）`, nR + nM + nS >= 1000);

const rTags = new Set(R_CASES.map((c) => c.tag));
for (const name of [
  'version', 'LEVEL', 'LEVEL_TEXT', 'LEVEL_KEY', 'DIFFICULTY', 'OUTCOME', 'JAM_TYPES', 'limits',
]) {
  need(`CocRules.${name} 无用例`, rTags.has(`R:const:${name}`));
}
const RULE_FNS = [
  'thresholds', 'targetOf', 'normDifficulty', 'fumbleRange', 'isFumble', 'levelOf',
  'critThresholdOf', 'fumbleThresholdOf', 'rollD100', 'combine', 'check', 'describeCheck',
  'canPush', 'luckAllowed', 'spendLuck', 'opposed', 'opposedReroll', 'opposedAttack',
  'opposedFull', 'parseExpr', 'rollExpr', 'rollDamageBonus', 'maxOfExpr', 'maxOfDamageBonus',
  'impaleDamage', 'burstMaxOf', 'isBurstWeapon', 'malfunctionThresholdOf', 'malfunctionOf',
  'defaultMalfunctionType', 'malfunctionEffect', 'parseSanLoss', 'resolveSanCheck',
  'insanityFlags', 'damageFlags', 'dyingRoundCheck', 'temporaryInsanityCheck', 'boutRounds',
  'initiativeOrder', 'advanceTurn', 'resolveAttack', 'skillValue', 'attrValue',
  'sceneStepPlan', 'sceneStepResolve',
];
for (const fn of RULE_FNS) {
  need(`CocRules.${fn} 无用例`, R_CASES.some((c) => c.fn === fn));
}
need('CocRules 导出成员数 ≠ 53', 8 + RULE_FNS.length === 53);

const mTags = new Set(M_CASES.map((c) => c.tag));
for (const key of Object.keys(M.EVT)) {
  need(`EVT:${M.EVT[key]} 无用例`, mTags.has(`EVT:${M.EVT[key]}`));
  need(`M:reduce:${M.EVT[key].toUpperCase()} 无用例`, mTags.has(`M:reduce:${M.EVT[key].toUpperCase()}`));
}
for (const key of Object.keys(M.INTENT)) {
  need(`INTENT:${M.INTENT[key]} 无用例`, mTags.has(`INTENT:${M.INTENT[key]}`));
}
for (const action of Object.keys(M.POLICY)) {
  need(`P:${action} 无用例`, mTags.has(`P:${action}`));
  for (const role of ROLES) {
    need(`N:${action}:${role} 无用例`, mTags.has(`N:${action}:${role}`));
  }
}
need(`POLICY 唯一 action 数 ≠ 61（实际 ${Object.keys(M.POLICY).length}）`, Object.keys(M.POLICY).length === 61);
need('EVT 数 ≠ 27', Object.keys(M.EVT).length === 27);
need('INTENT 数 ≠ 13', Object.keys(M.INTENT).length === 13);

const sTags = new Set(S_CASES.map((c) => c.tag));
for (const t of ['S:seq', 'S:skip', 'S:canFill', 'S:rollback', 'S:q1', 'S:status', 'S:intent', 'S:legacy']) {
  need(`${t} 无用例`, sTags.has(t));
}

if (problems.length) {
  console.error('\n❌ 覆盖矩阵存在缺口：');
  problems.forEach((p) => console.error('  · ' + p));
  process.exit(1);
}
console.log('\n✅ 覆盖矩阵零缺口；合计 ' + (nR + nM + nS) + ' 例');
