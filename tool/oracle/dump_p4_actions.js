/* ============================================================
 * tool/oracle/dump_p4_actions.js — S4.3 动作分发专用等价性 fixture
 *
 * 用法： node tool/oracle/dump_p4_actions.js
 * 输出： test/fixtures/room_actions.json（**第 4 个独立 fixture**）
 *
 * 为什么单独一个文件：
 *   T01~T03 的三个 fixture（room_rules / room_model / room_sequences）是基线，
 *   硬约束要求一行不动、保持 1093 例。S4.3 新增的 61 action 主干等价验证
 *   需要一个可由「旧版 JS 当预言机」复跑的期望数据集，故新增独立文件，
 *   不触碰三个基线 fixture。
 *
 * case 形状与既有 fixture 完全一致：
 *   { name, fn, args, seed, expect, randUsed, tag, error }
 *   fn 分组：actionScript（主干动作逐字段等价）
 *            behaviorScript（needs 矩阵 / pending 去重 / 伪造 ACT / locked 白名单）
 *
 * ⚠️ 原则：原码只读；每个 case 都是「确定性输入 → 原样 dump 输出」。
 *    seed 固定 1，与 Dart 侧 RoomOracleFixture 的 Lcg(seed) 同序列；
 *    randUsed 用 S.__randUsed()（__setSeed 会清零，与 Lcg.used 同口径）。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const { createRoomSandbox } = require('./load_p4_room');

const { sandbox: S, RoomModel: M } = createRoomSandbox();
const OUT = path.resolve(__dirname, '../../test/fixtures');

/** JSON 化：丢掉 undefined / 函数（与旧版返回对象形状一致） */
function J(v) {
  if (v === undefined) return null;
  return JSON.parse(JSON.stringify(v));
}

const CASES = [];
let caseSeq = 0;

function add(fn, args, tag, thunk, seed) {
  const s = seed === undefined ? 1 : seed;
  S.__setSeed(s);
  let out = null;
  let error = null;
  try {
    out = thunk();
  } catch (e) {
    error = String((e && e.message) ? e.message : e);
  }
  caseSeq += 1;
  CASES.push({
    name: `${tag}#${caseSeq}`,
    fn,
    args: J(args),
    seed: s,
    expect: error ? null : J(out),
    randUsed: S.__randUsed(),
    tag,
    error,
  });
}

/** 带两名在线玩家的最小房间（与 runHostScript 的 twoPeerOps 一致） */
function newHost(args) {
  const a = args || {};
  const h = new M.Host({
    meta: J(a.meta) || {},
    snapshotEvery: a.snapshotEvery || 20,
    logCap: a.logCap || 400,
  });
  h.attachPeer({ seat: 'p1', nickname: '甲', at: 1 });
  h.attachPeer({ seat: 'p2', nickname: '乙', at: 2 });
  return h;
}

/** 旧版真实入口：ACT 类动作走 applyAction，INTENT 级动作走 intent */
function runActionScript(a) {
  const h = newHost(a);
  const out = a.entry === 'intent'
    ? h.intent(a.seat, J(a.msg))
    : h.applyAction(a.seat, J(a.p));
  return {
    steps: J(out),
    state: J(h.state),
    logSeq: h.log.seq,
    warnings: J(h.warnings),
    roundStarts: J(h.roundStarts),
    snapshotSeqs: h.snapshots.map((s) => s.seq),
  };
}

/* ============================================================
 * 一、actionScript —— 主干动作与旧版逐字段等价
 *
 * entry='applyAction'：旧版 applyAction(:1702-1862) 真实有分支的 action。
 * entry='intent'     ：POLICY 登记但旧版走 intent() 的 INTENT 级 action
 *                      （chat / dice.request / ready.set / char.share）。
 *                      直调 applyAction 在旧版是空返回，不是真实入口。
 *
 * ⚠️ 刻意不纳入的 action（在 room_actions_test.dart 里用 Dart-only 断言覆盖）：
 *    · rollback.turn / rollback.commit：Q6 休眠项，设计 §1.5 要求「休眠保留」，
 *      旧版 applyAction 直调会产生提示事件，Dart 按设计返回空 —— 属设计裁决差异；
 *    · room.close / room.end / combat.roll / check.push / state.edit.self：
 *      **旧版 applyAction(:1702-1862) 根本没有这些 op 的分支**（只有 POLICY 登记，
 *      真实入口是传输层直调或 INTENT 链路），直调旧版返回空数组。Dart 按 U4
 *      「全量分发」补齐了这些别名分支，故不能用「直调 applyAction」做等价比较，
 *      否则等于拿旧版未实现的入口当基准。改由 Dart-only 断言验证「分支存在 +
 *      真实结算非空」，不放水也不删实现；
 *    · char.share（INTENT）与 locked:char：旧版 char 意图会完整跑 sanitizeSheet
 *      生成整张角色卡（含 runtime 键）；S4.4 / D21 落地后已补回等价用例
 *      （见 INTENT_CASES / LOCKED_MSGS），由 RoomHostSave.shareSheet 承接；
 *    · 依赖 CocMadness 掷骰 / 深层战斗结算的 action：Dart 测试注入确定性替身，
 *      与旧版 CocMadness 随机序列不同，不能做逐字段等价（避免假绿）。
 * ============================================================ */
const APPLY_CASES = [
  ['room.start', { op: 'room.start' }],
  ['room.kick', { op: 'room.kick', seat: 'p2' }],
  // room.close / room.end：旧版 applyAction 无分支（见上方注释），不纳入等价集
  ['session.end', { op: 'session.end' }],
  ['room.suspend', { op: 'room.suspend' }],
  ['room.resume', { op: 'room.resume' }],
  ['room.rules', { op: 'room.rules', critThreshold: 5, fumbleThreshold: 90 }],
  ['scene.set', { op: 'scene.set', scene: { title: '废弃教堂', image: '' } }],
  ['scene.mode', { op: 'scene.mode', mode: 'COMBAT' }],
  ['scene.clue', { op: 'scene.clue', seat: 'p1', title: '线索', text: '一张纸条' }],
  ['asset.add', { op: 'asset.add', asset: { name: '旧地图', kind: 'map' } }],
  ['asset.reveal', { op: 'asset.reveal', id: 'a1', revealed: true }],
  ['asset.cover', { op: 'asset.cover', id: 'a1' }],
  ['asset.del', { op: 'asset.del', id: 'a1' }],
  ['item.del', { op: 'item.del', seat: 'p1', id: 'i1' }],
  ['map.mark', { op: 'map.mark', x: 0.5, y: 0.6, label: '门' }],
  ['map.stroke', { op: 'map.stroke', points: [{ x: 0.1, y: 0.1 }, { x: 0.2, y: 0.2 }] }],
  ['map.clear', { op: 'map.clear' }],
  ['map.strokes.set', { op: 'map.strokes.set', strokes: [] }],
  ['board.self', { op: 'board.self', strokes: [{ x: 0.1, y: 0.2 }] }],
  ['combat.set', { op: 'combat.set', combat: { order: [], turn: 0, round: 1 } }],
  ['combat.prepare', { op: 'combat.prepare' }],
  ['combat.pool.set', { op: 'combat.pool.set', actors: [{ id: 'm1', name: '怪物', kind: 'monster', dex: 60, hp: 12, hpMax: 12 }] }],
  ['combat.start', { op: 'combat.start', actors: [{ id: 'm1', name: '怪物', kind: 'monster', dex: 60, hp: 12, hpMax: 12 }] }],
  ['combat.actor', { op: 'combat.actor', actor: { id: 'm1', name: '怪物', kind: 'monster' } }],
  ['combat.enqueue', { op: 'combat.enqueue', actor: { id: 'm2', name: '怪2', kind: 'monster' } }],
  ['combat.end', { op: 'combat.end' }],
  ['combat.next', { op: 'combat.next' }],
  ['combat.turnState', { op: 'combat.turnState', turn: 1, round: 1 }],
  ['dice.roll', { op: 'dice.roll', expr: '1D100', label: '侦察', result: { value: 42, level: 2, levelKey: 'REGULAR', levelText: '成功', rolls: [42] } }],
  // combat.roll：旧版 applyAction 无分支（只有 dice.roll），不纳入等价集
  ['dice.dark', { op: 'dice.dark', count: 2, sides: 6, reason: '暗骰' }],
  ['check.request', { op: 'check.request', skill: '侦查', desc: '找线索' }],
  // check.push：旧版 applyAction 无分支（只有 check.request），不纳入等价集
  // state.edit.self：旧版 applyAction 无分支（只有 state.self），不纳入等价集
  ['state.self', { op: 'state.self', seat: 'p1', status: { currentHP: 9 } }],
  // 注意用旧版真实契约键 `change`（不是 patch）：payload 应带出实际变更内容
  ['state.request', { op: 'state.request', seat: 'p1', change: { status: { currentHP: 7 } } }],
  ['sheet.tempstatus', { op: 'sheet.tempstatus', seat: 'p1', text: '受惊' }],
  ['sheet.item', { op: 'sheet.item', seat: 'p1', name: '手电筒', qty: 1 }],
  ['round.next', { op: 'round.next' }],
  ['rollback.round', { op: 'rollback.round' }],
  ['__unknown__', { op: '__unknown__' }],
];

APPLY_CASES.forEach(([name, p]) => {
  const args = {
    entry: 'applyAction',
    seat: 'host',
    p: J(p),
    meta: { code: 'abcd' },
    snapshotEvery: 20,
    logCap: 400,
  };
  add('actionScript', args, `A:apply:${name}`, () => runActionScript(args));
});

/* INTENT 级 action：旧版真实入口是 intent()，不是 applyAction */
const INTENT_CASES = [
  ['chat', 'host', { op: 'chat', p: { text: 'KP 说话' } }],
  ['dice.request', 'p1', { op: 'dice', p: { expr: '1D6' } }],
  ['ready.set', 'p1', { op: 'ready', p: { ready: false } }],
  // S4.4 / D21 落地后补回：旧版 char 意图会跑 sanitizeSheet 生成整张角色卡
  ['char.share', 'p1', { op: 'char', p: { name: '调查员', id: 'c1' } }],
];

INTENT_CASES.forEach(([name, seat, msg]) => {
  const args = {
    entry: 'intent',
    seat,
    msg: J(msg),
    meta: { code: 'abcd' },
    snapshotEvery: 20,
    logCap: 400,
  };
  add('actionScript', args, `A:intent:${name}`, () => runActionScript(args));
});

/* ============================================================
 * 二、behaviorScript —— 权限矩阵 / pending 去重 / 伪造 ACT / locked 白名单
 * ============================================================ */

// 2.1 needs()：61 个 POLICY action × 3 角色 + 未登记 action × 3 角色
const ROLES = ['kp', 'player', 'spectator'];
const POLICY_ACTIONS = Object.keys(M.POLICY);
const UNREGISTERED = ['rollback.turn', '__unknown__', 'fake.action', ''];

POLICY_ACTIONS.forEach((action) => {
  ROLES.forEach((role) => {
    const args = { kind: 'needs', action, role };
    add('behaviorScript', args, `A:needs:${action}:${role}`,
      () => J(M.needs(role, action)));
  });
});
UNREGISTERED.forEach((action) => {
  ROLES.forEach((role) => {
    const args = { kind: 'needs', action, role };
    add('behaviorScript', args, `A:needs-unregistered:${action}:${role}`,
      () => J(M.needs(role, action)));
  });
});

// 2.2 pending 去重：同一 (by, op, p) 连续两次，第二次不许重复入队
['madness.cure', 'sheet.healwound', 'aid.apply'].forEach((actOp) => {
  const args = { kind: 'pending', actOp };
  add('behaviorScript', args, `A:pending:${actOp}`, () => {
    const h = newHost(args);
    const mem = h.roster.get('p1');
    const p = { op: actOp, seat: 'p1' };
    const first = J(h._act('p1', mem, 'player', J(p)));
    const n1 = h.pending.length;
    const second = J(h._act('p1', mem, 'player', J(p)));
    const n2 = h.pending.length;
    return { first, second, pendingAfterFirst: n1, pendingAfterSecond: n2 };
  });
});

// 2.3 伪造 ACT / 越权 ACT：一律被 needs() 挡下并回定向提示
const FORGED_MSGS = [
  ['rollback.turn', { op: 'rollback.turn', turns: 1 }],
  ['unknown', { op: '__unknown__' }],
  ['room.start', { op: 'room.start' }],
  ['room.kick', { op: 'room.kick', seat: 'p2' }],
  ['dice.dark', { op: 'dice.dark', count: 1, sides: 6 }],
];

FORGED_MSGS.forEach(([name, p]) => {
  const args = { kind: 'forged', p: J(p) };
  add('behaviorScript', args, `A:forged:${name}`, () => {
    const h = newHost(args);
    return { steps: J(h.intent('p1', { op: 'act', p: J(p) })) };
  });
});

// 2.4 locked 全局操作锁：白名单放行、其余锁死（旧版 :1344-1369）
const LOCKED_MSGS = [
  ['chat', { op: 'chat', p: { text: 'hi' } }],
  ['sync', { op: 'sync', p: { lastSeq: 0 } }],
  ['ready', { op: 'ready', p: { ready: false } }],
  // char：S4.4 / D21 补回（旧版跑 sanitizeSheet，含 runtime 键）
  ['char', { op: 'char', p: { name: 'x' } }],
  ['statesync', { op: 'statesync', p: {} }],
  ['act-madness.cure', { op: 'act', p: { op: 'madness.cure', seat: 'p1' } }],
  ['act-sheet.healwound', { op: 'act', p: { op: 'sheet.healwound', seat: 'p1' } }],
  ['dice', { op: 'dice', p: { expr: '1D6' } }],
  ['act-room.start', { op: 'act', p: { op: 'room.start' } }],
  ['act-unknown', { op: 'act', p: { op: '__unknown__' } }],
  ['vote', { op: 'vote', p: { agree: true } }],
];

LOCKED_MSGS.forEach(([name, msg]) => {
  const args = { kind: 'locked', msg: J(msg) };
  add('behaviorScript', args, `A:locked:${name}`, () => {
    const hb = newHost(args);
    // ⚠️ 必须补 madness:[]：旧版 advanceMadness 直接读 m.sheet.madness，
    //    缺该键会抛 TypeError，导致整个 fixture 生成失败。
    hb.roster.get('p1').sheet = {
      status: { body: '死亡' }, mental: [], madness: [],
    };
    const blocked = J(hb.intent('p1', J(msg)));
    const hf = newHost(args);
    const free = J(hf.intent('p1', J(msg)));
    return { blocked, free };
  });
});

/* ============================================================
 * 三、写出 + 自检
 * ============================================================ */
fs.mkdirSync(OUT, { recursive: true });
const tags = [...new Set(CASES.map((c) => c.tag))].sort();
const payload = {
  // 顶层键形状与三个基线 fixture 完全一致（RoomOracleFixture.load 读 cases）
  generatedAt: '2026-11-09T00:00:00.000Z',
  total: CASES.length,
  tags,
  cases: CASES,
  meta: {
    generator: 'tool/oracle/dump_p4_actions.js',
    legacyRef: 'coc7th-card-app/web/js/core/room-model.js',
    note: 'S4.3 动作分发独立 fixture；三个基线 fixture 保持 1093 例未动',
  },
};
fs.writeFileSync(path.join(OUT, 'room_actions.json'),
  JSON.stringify(payload, null, 1), 'utf8');

const byFn = {};
for (const c of CASES) byFn[c.fn] = (byFn[c.fn] || 0) + 1;
const errors = CASES.filter((c) => c.error);
console.log(`room_actions.json: ${CASES.length} 例 / ${Object.keys(byFn).length} 类 fn`);
console.log('  按 fn:', JSON.stringify(byFn));
console.log('  按 tag 前缀:', JSON.stringify(
  [...new Set(CASES.map((c) => c.tag.split(':').slice(0, 2).join(':')))].sort()));
if (errors.length) {
  console.error('❌ 有 case 在旧版抛异常（Dart 侧会跳过，需检查输入）：');
  errors.forEach((e) => console.error(`  · ${e.name}: ${e.error}`));
  process.exit(1);
}
if (POLICY_ACTIONS.length !== 61) {
  console.error(`❌ POLICY action 数 ≠ 61（实际 ${POLICY_ACTIONS.length}）`);
  process.exit(1);
}
console.log(`✅ 61 个 POLICY action 全覆盖；needs 用例 ${POLICY_ACTIONS.length * 3} 条；零异常`);
