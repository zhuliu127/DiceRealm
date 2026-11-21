/* ============================================================
 * tool/qa/qa_p4_fresh_oracle.js — 复核用：**现造**旧版对照（不复用现成 fixture）
 *
 * 为什么要有它：`test/fixtures/room_sequences.json` 是工程师按自己挑的场景生成的，
 * 它证明的是「我认为该测的都测了」。复核需要的是「我也能拿旧版当预言机，
 * 但我造的是**随机序列**，覆盖到工程师没想到的组合」。
 *
 * 做法：用旧版 room-model.js（只读源码，经 load_p4_room.js 沙箱加载）跑
 * 可复现的随机 hostScript，把期望值落到 test/fixtures/qa_p4_fresh_oracle.json。
 *
 * ⚠️ 刻意**不生成** SEAT 秘密事件 + rollback 的组合：那是 Q1 唯一允许偏离
 *    oracle 的地方（旧版缺陷），放在这里会让严格比较必然为红，
 *    反而掩盖其他差异。Q1 由 qa_p4_secret_egress_test.dart 单独覆盖。
 * ⚠️ 只生成**不消耗随机数**的操作（attach/emit/syncFor/rollback/intent/
 *    setStatus/closeRoom/endSession/kick/detach/save），这样 randUsed 恒为 0，
 *    不会因为两边规则服务注入方式不同而假红。
 *
 * 用法：node tool/qa/qa_p4_fresh_oracle.js
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');

const { createRoomSandbox } = require('../oracle/load_p4_room.js');

const { S, RoomModel: M } = createRoomSandbox();

/** 与 load.js / test/support/oracle.dart 逐位一致的 LCG（用于**造脚本**，不是给 Host 用） */
function makeLcg(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const pick = (rnd, arr) => arr[Math.floor(rnd() * arr.length) % arr.length];
const intIn = (rnd, lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));

/** 生成一段随机 hostScript（不含 SEAT 秘密事件、不含消耗随机数的动作） */
function makeOps(rnd) {
  const ops = [
    { op: 'attach', m: { seat: 'p1', nickname: '甲', at: 1 } },
    { op: 'attach', m: { seat: 'p2', nickname: '乙', at: 2 } },
  ];
  if (rnd() < 0.5) ops.push({ op: 'attach', m: { seat: 'p3', nickname: '丙', at: 3 } });
  if (rnd() < 0.3) ops.push({ op: 'detach', seat: 'p2' });

  const seats = ['p1', 'p2', 'p3', 'host', 'ghost'];
  let i = 0;
  for (let k = 0; k < 14; k++) {
    i++;
    const r = rnd();
    if (r < 0.16) {
      ops.push({
        op: 'emit',
        t: 'chat',
        vis: 'public',
        to: null,
        p: { seat: pick(rnd, ['p1', 'p2', 'host']), nickname: '甲', text: 'c' + i, at: i, kind: 'user' },
        plan: rnd() < 0.5,
      });
    } else if (r < 0.3) {
      ops.push({
        op: 'emit',
        t: 'log',
        vis: 'public',
        to: null,
        p: { seat: '', text: 'l' + i, at: i, kind: pick(rnd, ['info', 'sys', 'state']) },
      });
    } else if (r < 0.4) {
      ops.push({
        op: 'emit',
        t: 'dice',
        vis: 'public',
        to: null,
        p: {
          seat: 'p1',
          nickname: '甲',
          expr: '1D100',
          rolls: [intIn(rnd, 1, 100)],
          total: intIn(rnd, 1, 100),
          level: intIn(rnd, 0, 5),
          levelText: '成功',
          label: '',
          at: i,
        },
      });
    } else if (r < 0.46) {
      ops.push({ op: 'emit', t: 'round', vis: 'public', to: null, p: { round: intIn(rnd, 1, 3) } });
    } else if (r < 0.52) {
      ops.push({ op: 'emit', t: 'status', vis: 'public', to: null, p: { status: 'IN_GAME', mode: 'COMBAT' } });
    } else if (r < 0.58) {
      ops.push({
        op: 'emit',
        t: 'request',
        vis: 'public',
        to: null,
        p: { self: true, done: false, id: 'r' + i, op: 'sheet.damage', payload: { amount: 1 }, from: 'KP', reason: 'r', at: i },
      });
    } else if (r < 0.64) {
      ops.push({ op: 'emit', t: 'archive', vis: 'public', to: null, p: { seq: i, savedAt: i, ok: true } });
    } else if (r < 0.7) {
      ops.push({ op: 'emit', t: 'turnalert', vis: 'public', to: null, p: { kind: 'turn', round: 1, turn: 0, name: '甲', seat: 'p1', at: i } });
    } else if (r < 0.76) {
      ops.push({
        op: 'emit',
        t: 'asset',
        vis: 'public',
        to: null,
        p: { assets: [{ id: 'a' + i, kind: 'map', name: '素材', data: '', revealed: true, at: i }] },
      });
    } else if (r < 0.82) {
      ops.push({ op: 'emit', t: 'board', vis: 'public', to: null, p: { seat: 'p1', at: i, strokes: [{ p: 1 }], thumb: 't', self: true } });
    } else if (r < 0.88) {
      ops.push({ op: 'syncFor', seat: pick(rnd, seats) });
    } else if (r < 0.94) {
      const seat = pick(rnd, ['p1', 'p2', 'host']);
      const which = rnd();
      let msg;
      if (which < 0.4) msg = { op: 'chat', p: { text: 'hi' + i } };
      else if (which < 0.8) msg = { op: 'sync', p: { lastSeq: intIn(rnd, 0, 6) } };
      else msg = { op: 'ready', p: { ready: rnd() < 0.5 } };
      ops.push({ op: 'intent', seat, msg });
    } else {
      ops.push({ op: 'rollback', before: intIn(rnd, 1, 9) });
    }
  }
  if (rnd() < 0.5) ops.push({ op: 'setStatus', s: 'SUSPENDED' });
  if (rnd() < 0.3) ops.push({ op: 'kick', seat: 'p2' });
  if (rnd() < 0.2) ops.push({ op: 'closeRoom' });
  if (rnd() < 0.2) ops.push({ op: 'endSession' });
  ops.push({ op: 'save' });
  return ops;
}

/** 与 dump_p4_room.js 的 runHostScript 同口径（只保留本脚本会生成的 op） */
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
        const rec = h.emit(op.t, JSON.parse(JSON.stringify(op.p || {})), op.vis, op.to);
        steps.push({ seq: rec.seq, plan: op.plan ? h.plan(rec) : null });
        break;
      }
      case 'syncFor': steps.push(h.syncFor(op.seat)); break;
      case 'intent': steps.push(h.intent(op.seat, JSON.parse(JSON.stringify(op.msg)))); break;
      case 'rollback': steps.push(h.rollback(op.before)); break;
      case 'setStatus': steps.push(h.setStatus(op.s)); break;
      case 'closeRoom': steps.push(h.closeRoom()); break;
      case 'endSession': steps.push(h.endSession()); break;
      case 'kick': steps.push(h.kick(op.seat)); break;
      case 'save': saveOut = h.save(); steps.push(null); break;
      default: throw new Error('unknown host op ' + op.op);
    }
  }
  const J = (v) => JSON.parse(JSON.stringify(v === undefined ? null : v));
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

/* ---------------- 生成 6 段随机脚本 ---------------- */
const cases = [];
const SEEDS = [11, 2024, 77777, 424242, 900001, 1234567];
SEEDS.forEach((scriptSeed, idx) => {
  const args = {
    meta: idx % 2 === 0 ? { code: 'abcd' } : {},
    snapshotEvery: [1, 2, 3, 20][idx % 4],
    logCap: [3, 8, 400][idx % 3],
    ops: makeOps(makeLcg(scriptSeed)),
  };
  // 旧版 Host 侧用固定随机序列（本脚本不消耗随机数，但保持与其它 fixture 一致）
  S.__setSeed(scriptSeed);
  const before = S.__randUsed ? S.__randUsed() : 0;
  const expect = runHostScript(args);
  const randUsed = (S.__randUsed ? S.__randUsed() : 0) - before;
  cases.push({
    name: 'F:' + idx + '#' + scriptSeed,
    fn: 'hostScript',
    args,
    seed: scriptSeed,
    expect,
    randUsed,
    tag: 'F:random',
    error: null,
  });
});

const out = {
  source: 'qa_p4_fresh_oracle.js（复核现造对照，非工程师 fixture）',
  cases,
};
const target = path.resolve(__dirname, '../../test/fixtures/qa_p4_fresh_oracle.json');
fs.writeFileSync(target, JSON.stringify(out, null, 1), 'utf8');
console.log('✅ 写出 ' + cases.length + ' 例 → ' + target);
console.log('   randUsed: ' + cases.map((c) => c.randUsed).join(','));
