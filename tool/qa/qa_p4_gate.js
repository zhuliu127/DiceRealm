/* ============================================================
 * QA P4 房间规则层 · 静态门禁探针（T05）
 *
 * 用法： node tool/qa/qa_p4_gate.js
 * 退出码： 0 = IS_PASS: YES；1 = IS_PASS: NO（有任何一条判据不成立）
 *
 * 只做只读静态检查，不改 fixture / 比较器 / 源码，也不起 flutter。
 * 覆盖 team-lead 的 7 条复核项：
 *   ① lib/domain 纯 Dart（零 package:flutter / dart:io / dart:ui）
 *   ② reduceRoomState( 恰好 2 调用 + 1 声明，且调用点固定
 *   ③ 白名单恰好 2 条（S:q1 9 条 + S:trim 1 条），无通配
 *   ④ 三基线 fixture 455/517/121 = 1093、第 4 fixture 256；零 error
 *   ⑤ room_sequences.json 121 例全实跑（hostScript 94 / clientScript 27，
 *      宿主测试无 only）
 *   ⑥ 房间写回路径唯一 await repo.save(；save() 恰好 20 键
 *   ⑦ 61 个 POLICY action 在三个 dispatch 文件里全部分支零缺口
 * 另加：Q6 休眠项三件保留、Client.receive 返回体无 gapFrom 键、
 *       三个禁改文件未被反向依赖、T05 新增门禁文件齐全。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');
const exists = (rel) => fs.existsSync(path.join(ROOT, rel));
const dartFiles = (dir) => fs.readdirSync(path.join(ROOT, dir))
  .filter((f) => f.endsWith('.dart'))
  .map((f) => `${dir}/${f}`);

/** 剥离 `//` 行注释，只留真实代码（说明文字里的示例不算命中）。 */
function code(src) {
  return src.split('\n').map((line) => {
    const i = line.indexOf('//');
    return i < 0 ? line : line.substring(0, i);
  }).join('\n');
}

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok: !!ok, detail: String(detail) });
}

/* ---------- ① lib/domain 纯 Dart ---------- */
{
  const banned = /(?:package:flutter|'dart:io'|'dart:ui'|"dart:io"|"dart:ui")/;
  const hits = [];
  for (const rel of dartFiles('lib/domain')) {
    const lines = code(read(rel)).split('\n');
    lines.forEach((line, i) => {
      if (banned.test(line)) hits.push(`${rel}:${i + 1} ${line.trim()}`);
    });
  }
  check('lib/domain 纯 Dart（零 Flutter/IO/UI）', hits.length === 0,
    hits.length ? hits.join(' | ') : `扫描 ${dartFiles('lib/domain').length} 个 .dart，零命中`);
}

/* ---------- ② reduceRoomState( 调用点 ---------- */
{
  const hits = [];
  let decls = 0;
  for (const rel of dartFiles('lib/domain')) {
    code(read(rel)).split('\n').forEach((line, i) => {
      if (!line.includes('reduceRoomState(')) return;
      if (/^\s*Map<String, Object\?> reduceRoomState\(/.test(line)) decls += 1;
      else hits.push(`${rel}:${i + 1}`);
    });
  }
  const fixed = hits.some((h) => h.startsWith('lib/domain/room_model_host_core.dart')) &&
    hits.some((h) => h.startsWith('lib/domain/room_model_client.dart'));
  check('reduceRoomState( == 2 调用 + 1 声明',
    hits.length === 2 && decls === 1 && fixed,
    `调用 ${hits.length}（${hits.join(', ')}），声明 ${decls}`);
}

/* ---------- ③ 白名单 ---------- */
{
  // P4-QA 终验：2 条登记（S:q1 = 9 条精确路径，S:trim = 1 条）。
  // 冗余路径已按「一条不多」核算删除（qa_p4_whitelist_proof_test.dart），
  // 容器路径也不再享有「整棵子树」的空白支票（登记只放行该值本身）。
  const raw = read('test/support/room_oracle_whitelist.dart');
  const src = code(raw);
  // 以 `KnownDivergence(` 为界切块，逐块数 allowedPaths 条目。
  const blocks = src.split(/KnownDivergence\s*\(/).slice(1);
  const parsed = blocks.map((body) => {
    const id = (body.match(/caseId:\s*'([^']+)'/) || [])[1] || '';
    const m = body.match(/allowedPaths:\s*<String>\[([\s\S]*?)\n\s*\],/);
    const list = m ? m[1] : '';
    // 条目 = 行首 raw 字符串（r'...'）或常量引用（kXxx）
    const paths = (list.match(/^\s*(?:r'|k[A-Z]\w*)/gm) || []).length;
    return { id, paths, wildcard: /[*]/.test(list) };
  }).filter((e) => e.id !== ''); // 类的构造函数 `const KnownDivergence({` 也被切出来，丢掉
  const find = (id) => parsed.find((e) => e.id === id);
  const q1 = find('S:q1');
  const trim = find('S:trim');
  // S:trim 的唯一路径是常量引用，单独核对字面量（防被改成通配 / 子树）
  const trimConst = (raw.match(/const String kTrimAllowedPath\s*=\s*r'([^']+)'/) || [])[1];
  check('白名单恰好 2 条（S:q1 9 + S:trim 1），无通配',
    parsed.length === 2 && !!q1 && !!trim &&
    q1.paths === 9 && trim.paths === 1 &&
    !q1.wildcard && !trim.wildcard &&
    trimConst === '$.snapshotSeqs[0]',
    `entries=${parsed.length}，` +
      parsed.map((e) => `${e.id}:${e.paths}`).join(' / ') +
      `，kTrimAllowedPath=${trimConst}`);
}

/* ---------- ④ 四个 fixture 规模与形状 ---------- */
{
  const sizes = {
    'room_rules.json': 455,
    'room_model.json': 517,
    'room_sequences.json': 121,
    'room_actions.json': 256,
  };
  const bad = [];
  for (const [name, want] of Object.entries(sizes)) {
    const d = JSON.parse(read(`test/fixtures/${name}`));
    const keys = Object.keys(d).sort().join(',');
    const wantKeys = name === 'room_actions.json'
      ? 'cases,generatedAt,meta,tags,total'
      : 'cases,generatedAt,tags,total';
    const errors = d.cases.filter((c) => c.error).length;
    // expect: null 是合法期望值（旧版函数真的返回 null），只要求键存在。
    const missing = d.cases.filter((c) => !Object.prototype.hasOwnProperty.call(c, 'expect')).length;
    // 三个基线的 tags 是「tag → 例数」对象，动作 fixture 是 tag 数组，都合法。
    const tagsOk = d.tags !== null && typeof d.tags === 'object';
    if (d.total !== want || d.cases.length !== want || keys !== wantKeys ||
        errors !== 0 || missing !== 0 || !tagsOk) {
      bad.push(`${name}: total=${d.total} len=${d.cases.length} keys=${keys} error=${errors} noExpect=${missing}`);
    }
  }
  check('四 fixture 精确 455/517/121/256（三基线 1093），零 error',
    bad.length === 0,
    bad.length ? bad.join(' | ') : '455+517+121=1093，动作分发 256');
}

/* ---------- ⑤ room_sequences 121 例全实跑 ---------- */
{
  const d = JSON.parse(read('test/fixtures/room_sequences.json'));
  const host = d.cases.filter((c) => c.fn === 'hostScript').length;
  const client = d.cases.filter((c) => c.fn === 'clientScript').length;
  const src = read('test/room_sequences_test.dart');
  const seqCode = code(src);
  const noOnly = !/\bonly\s*:/.test(seqCode);
  const handlers = /'hostScript':\s*\(/.test(seqCode) && /'clientScript':\s*\(/.test(seqCode);
  check('room_sequences.json 121 例全实跑（hostScript 94 / clientScript 27）',
    d.cases.length === 121 && host === 94 && client === 27 && noOnly && handlers,
    `total=${d.cases.length} host=${host} client=${client} noOnly=${noOnly} handlers=${handlers}`);

  // 四个 fixture 的每个 fn 都要有 handler；only 只允许出现在两个已知文件。
  const testFiles = fs.readdirSync(path.join(ROOT, 'test'))
    .filter((f) => f.startsWith('room_') && f.endsWith('_test.dart'));
  let all = '';
  for (const f of testFiles) all += read(`test/${f}`) + '\n';
  const re = /^\s*'([^']+)':\s*(?:\(|[A-Za-z_][A-Za-z0-9_]*\s*,)/gm;
  const handlersSet = new Set();
  let m;
  while ((m = re.exec(all)) !== null) handlersSet.add(m[1]);
  const missing = new Set();
  for (const name of Object.keys({ 'room_rules.json': 1, 'room_model.json': 1, 'room_sequences.json': 1, 'room_actions.json': 1 })) {
    const dd = JSON.parse(read(`test/fixtures/${name}`));
    for (const c of dd.cases) if (!handlersSet.has(c.fn)) missing.add(`${name}/${c.fn}`);
  }
  // 只有真正调用 fixture.run 的 5 个宿主文件才可能用 only 跳过用例；
  // 门禁/静态扫描文件里的 `only:` 字样只是被检测的文本，不算 runner。
  const hostFiles = testFiles.filter((f) => /\.run\(/.test(code(read(`test/${f}`))));
  const onlyFiles = hostFiles.filter((f) => /\bonly\s*:/.test(code(read(`test/${f}`))));
  const allowedOnly = ['room_model_core_test.dart', 'room_save_test.dart'];
  check('每个 fn 有 handler；only 只在 2 个已知 runner',
    missing.size === 0 && hostFiles.length === 5 &&
      onlyFiles.length === 2 && onlyFiles.every((f) => allowedOnly.includes(f)),
    `handlers=${handlersSet.size} missing=${[...missing].join(',') || '无'} ` +
    `runners=${hostFiles.length} onlyFiles=${onlyFiles.join(',')}`);
}

/* ---------- ⑥ 房间写回唯一 / save() 20 键 ---------- */
{
  const pathFiles = [
    'lib/domain/character.dart',
    'lib/domain/room_model_save.dart',
    'lib/domain/room_ports.dart',
    'lib/repo/room_state_writer.dart',
  ];
  const hits = [];
  for (const rel of pathFiles) {
    const c = code(read(rel));
    for (const mm of c.matchAll(/await\s+\w+\.save\(/g)) hits.push(`${rel}:${mm.index}`);
  }
  check('房间写回路径恰好 1 处 await repo.save(',
    hits.length === 1 && hits[0].startsWith('lib/repo/room_state_writer.dart'),
    `命中 ${hits.length} 处：${hits.join(', ') || '无'}`);

  const saveSrc = read('lib/domain/room_model_save.dart');
  const block = saveSrc.match(/Map<String, Object\?> save\(\) \{([\s\S]*?)\n  \}/);
  const keys = block ? (block[1].match(/^\s*'([A-Za-z]+)':/gm) || []).length : -1;
  check('Host.save() 恰好 20 个顶层键', keys === 20, `解析到 ${keys} 个键`);
}

/* ---------- ⑦ 61 action 分支零缺口 ---------- */
{
  const types = code(read('lib/domain/room_types.dart'));
  const policy = [...types.matchAll(/^\s*'([^']+)':\s*RoomPolicyEntry\(/gm)].map((x) => x[1]);
  const cases = new Set();
  for (const rel of [
    'lib/domain/room_model_actions_room.dart',
    'lib/domain/room_model_actions_combat.dart',
    'lib/domain/room_model_actions_sheet.dart',
  ]) {
    for (const mm of code(read(rel)).matchAll(/case\s+'([^']+)'\s*:/g)) cases.add(mm[1]);
  }
  const missing = [...new Set(policy)].filter((a) => !cases.has(a));
  check('61 个 POLICY action 全部分支零缺口',
    new Set(policy).size === 61 && missing.length === 0,
    `POLICY=${new Set(policy).size}，分支=${cases.size}，缺失=${missing.join(',') || '无'}`);
}

/* ---------- 附加：Q6 休眠项 / receive 无 gapFrom / 禁改文件 / 门禁文件 ---------- */
{
  const reduce = code(read('lib/domain/room_model_reduce.dart'));
  const state = code(read('lib/domain/room_model_state.dart'));
  const actions = code(read('lib/domain/room_model_actions_room.dart'));
  const keep = reduce.includes('case RoomEvt.rewind:') &&
    state.includes("'rewind': null,") &&
    actions.includes("case 'rollback.turn':");
  check('Q6 休眠项三件保留（EVT.REWIND / state.rewind / rollback.turn）', keep,
    `reduce=${reduce.includes('case RoomEvt.rewind:')} state=${state.includes("'rewind': null,")} action=${actions.includes("case 'rollback.turn':")}`);

  const client = code(read('lib/domain/room_model_client.dart'));
  check('Client.receive() 返回体没有 gapFrom 键',
    !/'gapFrom'\s*:/.test(client), '扫描所有 map 字面量键');

  const dice = code(read('lib/domain/dice.dart'));
  const rules = code(read('lib/domain/rules_coc7.dart'));
  check('三个禁改文件存在，且 dice/rules_coc7 未被 P4 反向依赖',
    exists('pubspec.yaml') && !dice.includes('room_') && !rules.includes('room_'),
    `pubspec=${exists('pubspec.yaml')} dice.room_=${dice.includes('room_')} rules.room_=${rules.includes('room_')}`);

  const gateFiles = [
    'test/room_actions_test.dart',
    'test/room_save_test.dart',
    'test/room_card_writeback_test.dart',
    'test/room_equivalence_test.dart',
    'test/room_legacy_save_replay_test.dart',
    'test/room_purity_test.dart',
    'test/room_sequences_test.dart',
    'tool/qa/qa_p4_gate.js',
  ];
  const absent = gateFiles.filter((f) => !exists(f));
  check('T05 门禁文件齐全（8 个）', absent.length === 0,
    absent.length ? `缺 ${absent.join(', ')}` : `${gateFiles.length} 个齐全`);
}

/* ---------- 汇总 ---------- */
const failed = results.filter((r) => !r.ok);
console.log('==== QA P4 GATE · 静态探针 ====');
for (const r of results) {
  console.log(`${r.ok ? '[OK]  ' : '[FAIL]'} ${r.name}\n       ${r.detail}`);
}
console.log(`==== 合计 ${results.length} 条，失败 ${failed.length} 条 ====`);
console.log(`P4_GATE IS_PASS: ${failed.length === 0 ? 'YES' : 'NO'}`);
process.exit(failed.length === 0 ? 0 : 1);
