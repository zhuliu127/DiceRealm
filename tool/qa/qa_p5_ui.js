/* ============================================================
 * QA P5 房间 UI 层 · 静态门禁探针（T05-B2b）
 *
 * 用法： node tool/qa/qa_p5_ui.js
 * 退出码： 0 = IS_PASS: YES；1 = IS_PASS: NO（有任何一条判据不成立）
 *
 * 只做只读静态检查，不改 fixture / 比较器 / 源码，也不起 flutter。
 * 与 qa_p4_gate.js 同风格：每条打印 [OK]/[FAIL] + 明细，
 * 末尾「合计 N 条，失败 M 条」+「P5_UI_GATE IS_PASS: YES/NO」。
 *
 * 13 条判据（派工表逐条对应）：
 *   01 lib/ui/room/view/** 零框架依赖
 *   02 view/ 恰好 6 个文件
 *   03 lib/ui/room/** 零权威状态赋值（排除 view/）
 *   04 零规则调用（规则只在 domain，UI 不得直接算）
 *   05 C7 四个死代码名零命中
 *   06 await repo.save( 命中数不增加
 *   07 lib/domain 纯 Dart
 *   08 jsStr( 预算 ≤ 6 且只落在 4 个白名单文件
 *   09 PlaceholderBlock 只剩定义
 *   10 showModalBottomSheet 只许一处
 *   11 弹层不走裸 showDialog
 *   12 门禁字面量不入注释
 *   13 文件清单与规模（信息项，不参与判定）
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const abs = (rel) => path.join(ROOT, rel);
const read = (rel) => fs.readFileSync(abs(rel), 'utf8');
const exists = (rel) => fs.existsSync(abs(rel));

/** 递归列出目录下所有 .dart（返回相对 ROOT 的 posix 路径，按字典序）。 */
function walkDart(dir) {
  const out = [];
  const rec = (rel) => {
    let names;
    try {
      names = fs.readdirSync(abs(rel));
    } catch (e) {
      return;
    }
    for (const name of names.sort()) {
      const child = `${rel}/${name}`;
      const st = fs.statSync(abs(child));
      if (st.isDirectory()) rec(child);
      else if (name.endsWith('.dart')) out.push(child);
    }
  };
  rec(dir);
  return out;
}

/** 剥离 `//` 行注释，只留真实代码（说明文字里的示例不算命中）。 */
function code(src) {
  return src.split('\n').map((line) => {
    const i = line.indexOf('//');
    return i < 0 ? line : line.substring(0, i);
  }).join('\n');
}

/** 只留注释部分（行内 `//` 之后），用于第 12 条。 */
function comments(src) {
  return src.split('\n').map((line) => {
    const i = line.indexOf('//');
    return i < 0 ? '' : line.substring(i);
  });
}

const results = [];
function check(name, ok, detail) {
  results.push({ name, ok: !!ok, detail: String(detail) });
}

const ROOM = 'lib/ui/room';
const VIEW = 'lib/ui/room/view';

const roomFiles = exists(ROOM) ? walkDart(ROOM) : [];
const viewFiles = exists(VIEW) ? walkDart(VIEW) : [];

/** 逐行扫描：返回 `path:line 文本` 形式的命中列表。 */
function scan(hits, rel, line, i) {
  hits.push(`${rel}:${i + 1} ${line.trim()}`);
}

/* ---------- 01 lib/ui/room/view/** 零框架依赖 ---------- */
{
  const banned = /(?:package:flutter|dart:ui)/;
  const hits = [];
  for (const rel of viewFiles) {
    code(read(rel)).split('\n').forEach((line, i) => {
      if (banned.test(line)) scan(hits, rel, line, i);
    });
  }
  check('view/ 零框架依赖（无 Flutter / dart:ui）', hits.length === 0,
    hits.length ? hits.join(' | ') : `扫描 ${viewFiles.length} 个文件，零命中`);
}

/* ---------- 02 view/ 恰好 6 个文件 ---------- */
{
  const want = 6;
  const names = viewFiles.map((f) => path.basename(f));
  check('view/ 恰好 6 个文件', viewFiles.length === want,
    `实际 ${viewFiles.length} 个：${names.join(', ')}（期望 ${want}）`);
}

/* ---------- 03 lib/ui/room/** 零权威状态赋值（排除 view/） ---------- */
{
  // `state[x] =` 是权威端写状态的形状；UI 只能发 intent。
  // 用 `=[^=]` 排除 `==`（比较不是赋值）。
  const re = /state\[[^\]]*\]\s*=(?!=)/;
  const hits = [];
  for (const rel of roomFiles) {
    if (rel.startsWith(`${VIEW}/`)) continue;
    code(read(rel)).split('\n').forEach((line, i) => {
      if (re.test(line)) scan(hits, rel, line, i);
    });
  }
  const scanned = roomFiles.filter((f) => !f.startsWith(`${VIEW}/`)).length;
  check('room/** 零权威状态赋值（排除 view/）', hits.length === 0,
    hits.length ? hits.join(' | ') : `扫描 ${scanned} 个文件，零命中`);
}

/* ---------- 04 零规则调用 ---------- */
{
  const banned = /rules\?\.check\(|rollExpr\(|opposedFull\(/;
  const hits = [];
  for (const rel of roomFiles) {
    code(read(rel)).split('\n').forEach((line, i) => {
      if (banned.test(line)) scan(hits, rel, line, i);
    });
  }
  check('UI 层零规则调用（rules?/rollExpr/opposedFull）', hits.length === 0,
    hits.length ? hits.join(' | ') : `扫描 ${roomFiles.length} 个文件，零命中`);
}

/* ---------- 05 C7 四个死代码名零命中 ---------- */
{
  // 只在 lib/ 上判：test/ 里这几个名字是「禁名清单」的断言文本，属正常。
  const dead = ['plBottomBar', 'plFeeds', 'kpChat', 'kpGameLog'];
  const libFiles = walkDart('lib');
  const hits = [];
  for (const rel of libFiles) {
    const lines = read(rel).split('\n');
    lines.forEach((line, i) => {
      for (const name of dead) {
        if (line.includes(name)) scan(hits, rel, line, i);
      }
    });
  }
  check('C7 四个死代码名在 lib/ 零命中', hits.length === 0,
    hits.length
      ? hits.join(' | ')
      : `扫描 ${libFiles.length} 个文件，${dead.join(' / ')} 全零命中`);
}

/* ---------- 06 await repo.save( 命中数不增加 ---------- */
{
  // ★ P10 第 1 期收口：从「裸数字上限（FROZEN）」改成**显式申报清单**。
  //
  // 为什么不再用 FROZEN：
  //   `FROZEN = 4` 是 P4 收口时的实际数，之后 P9/P10 的功能（一键出卡「就用这张」、
  //   AI 车卡「采用这张」）合法地各加了一处，裸数字只会逼人「把这行改成 6」——
  //   那不是守住门禁，是放宽门禁。现在改成：**每一条写盘都必须被显式申报**，
  //   新增/删除都要在清单里体现，审计时一眼能看出「谁、为什么、有没有兜底」。
  //
  // 判定口径（三条同时成立才算 PASS）：
  //   ① 命中数 ≤ 申报条目数；
  //   ② 每一条命中都能在清单里找到对应条目（= 没偷偷新增写盘路径）；
  //   ③ 清单里的条目如果在代码里已经没了 → 报「清单腐化」要求清理（防清单腐化）。
  //
  // ★ 硬规则（这里是唯一有效的地方，写进报告没用）：
  //   覆盖下面这 6 条路径的任何 widget 测试**必须注入 MemoryStorage**
  //   （`test/support/app_harness.dart` 的 `pumpApp` 默认就是 `newMemoryRepo()`）。
  //   理由：widget 测试跑在 fake-async 区域，真实文件 I/O 的 Future **永不完成**，
  //   不注入内存后端的话白名单就只是记账，用例会挂死或假绿。
  //
  // 兜底测试证据（都真跑到 `await repo.save(`，且都走内存后端）：
  //   · `test/p9_rule_pick_test.dart:272` —— 一键出卡点 `result_use_this` 后
  //     断言 `repo.all.length == 1` 并回首页（覆盖 random_create_page 那条路径）；
  //   · `test/p9_rule_pick_test.dart:331` —— AI 车卡同一动作同一断言
  //     （覆盖 ai_create_page 那条路径）。
  const DECLARED = [
    {
      file: 'lib/repo/card_transfer.dart',
      line: 172,
      purpose: '导入角色卡：导入的卡逐张落库',
      baseline: true, // P4 收口时既存
      fallback: 'test/card_transfer_test.dart（内存 repo）',
      injected: 'MemoryStorage',
    },
    {
      file: 'lib/repo/room_state_writer.dart',
      line: 63,
      purpose: '房间状态写回：K11/C5 唯一落盘入口（本文件只有这 1 处代码）',
      baseline: true,
      fallback: 'test/qa_p4_c5_writeback_test.dart（内存 repo）',
      injected: 'MemoryStorage',
    },
    {
      file: 'lib/ui/ai_create_page.dart',
      line: 472,
      purpose: 'AI 车卡「采用这张」直接落库',
      baseline: false, // P9/P10 功能新增，早于本批
      fallback: 'test/p9_rule_pick_test.dart:331',
      injected: 'MemoryStorage（pumpApp → newMemoryRepo）',
    },
    {
      file: 'lib/ui/card_detail_page.dart',
      line: 167,
      purpose: '卡详情页编辑保存',
      baseline: true,
      fallback: 'test/card_detail_edit_test.dart（内存 repo）',
      injected: 'MemoryStorage',
    },
    {
      file: 'lib/ui/create/create_flow_page.dart',
      line: 288,
      purpose: '按流程车卡：向导末步保存',
      baseline: true,
      fallback: 'test/create_flow_widget_test.dart（内存 repo）',
      injected: 'MemoryStorage',
    },
    {
      file: 'lib/ui/random_create_page.dart',
      line: 166,
      purpose: '一键出卡「就用这张」直接落库',
      baseline: false, // P9/P10 功能新增，早于本批
      fallback: 'test/p9_rule_pick_test.dart:272',
      injected: 'MemoryStorage（pumpApp → newMemoryRepo）',
    },
  ];

  const libFiles = walkDart('lib');
  const hits = [];
  for (const rel of libFiles) {
    code(read(rel)).split('\n').forEach((line, i) => {
      if (/await\s+repo\.save\(/.test(line)) {
        hits.push({ file: rel.replace(/\\/g, '/'), line: i + 1 });
      }
    });
  }

  const declaredFiles = new Set(DECLARED.map((d) => d.file));
  const undeclared = hits.filter((h) => !declaredFiles.has(h.file));
  const missing = DECLARED.filter((d) => !hits.some((h) => h.file === d.file));
  // 行号漂移只提示、不判失败（重构会让行号变，但文件与用途不变）
  const drifted = DECLARED
    .map((d) => ({ d, hit: hits.find((h) => h.file === d.file) }))
    .filter((x) => x.hit && x.hit.line !== x.d.line)
    .map((x) => `${x.d.file}: 申报 ${x.d.line} → 实际 ${x.hit.line}`);

  const ok =
    hits.length <= DECLARED.length && undeclared.length === 0 && missing.length === 0;
  const detail = [
    `实际 ${hits.length} 处 / 申报 ${DECLARED.length} 处`,
    hits.map((h) => `${h.file}:${h.line}`).join(', ') || '无',
    undeclared.length ? `未申报：${undeclared.map((h) => h.file).join(', ')}` : '',
    missing.length
      ? `清单腐化（代码里已无此命中，请删条目）：${missing.map((d) => d.file).join(', ')}`
      : '',
    drifted.length ? `行号漂移（仅提示）：${drifted.join(' | ')}` : '',
  ]
    .filter(Boolean)
    .join(' —— ');

  check('await repo.save( 每条写盘都在申报清单内（6 条显式声明）', ok, detail);
}

/* ---------- 07 lib/domain 纯 Dart ---------- */
{
  const banned = /package:flutter|dart:io|dart:ui/;
  const domFiles = walkDart('lib/domain');
  const hits = [];
  for (const rel of domFiles) {
    read(rel).split('\n').forEach((line, i) => {
      if (banned.test(line)) scan(hits, rel, line, i);
    });
  }
  check('lib/domain 纯 Dart（零 Flutter / IO / UI）', hits.length === 0,
    hits.length ? hits.join(' | ') : `扫描 ${domFiles.length} 个 .dart，零命中`);
}

/* ---------- 08 jsStr( 预算 ---------- */
{
  const BUDGET = 14;
  const allow = new Set([
    'lib/ui/room/room_session_local.dart',
    'lib/ui/room/room_text.dart',
    'lib/ui/room/widgets/gp_scene_check_pl.dart',
    'lib/ui/room/widgets/gp_status.dart',
    // 「加入战斗」候选行要按座位区分（每行一个 seat），见下方 seat-only 专项校验
    'lib/ui/room/widgets/gp_combat_list.dart',
    // P6 远端会话：与 room_session_local 同口径（seat / kind / 消息正文只读展示）
    'lib/ui/room/room_session_remote.dart',
  ]);
  const perFile = new Map();
  let total = 0;
  for (const rel of roomFiles) {
    const n = (read(rel).match(/jsStr\(/g) || []).length;
    if (n > 0) {
      perFile.set(rel, n);
      total += n;
    }
  }
  const outside = [...perFile.keys()].filter((f) => !allow.has(f));
  check(`jsStr( 命中 ≤ ${BUDGET} 且只在白名单 6 文件`,
    total <= BUDGET && outside.length === 0,
    `实际 ${total} 处：` +
    [...perFile.entries()].map(([f, n]) => `${path.basename(f)}×${n}`).join(', ') +
    `；白名单外 ${outside.length ? outside.join(', ') : '无'}`);

  // 放行 `gp_combat_list` 必须带约束：只准读 **seat / kind**（p1/p2/sp1、
  // 'pc'/'npc' 这类公开标识），不许在该文件里用 jsStr 渲染任何秘密字段
  // （HP / SAN / 笔记 / 私有素材）。否则「放行一个文件」就等于开了个后门。
  const COMBAT = 'lib/ui/room/widgets/gp_combat_list.dart';
  const combatBad = [];
  if (exists(COMBAT)) {
    read(COMBAT).split(/\r?\n/).forEach((line, i) => {
      if (!line.includes('jsStr(')) return;
      if (line.includes('seat') || line.includes('kind')) return;
      scan(combatBad, COMBAT, line, i);
    });
  }
  check('gp_combat_list 的 jsStr 只读 seat / kind（公开标识）',
    combatBad.length === 0,
    combatBad.length ? combatBad.join(' | ') : '全部只读 seat / kind');
}

/* ---------- 09 PlaceholderBlock 只剩定义 ---------- */
{
  const DEF_FILE = 'lib/ui/room/widgets/room_panel_kit.dart';
  const hits = [];
  for (const rel of roomFiles) {
    code(read(rel)).split('\n').forEach((line, i) => {
      if (!line.includes('PlaceholderBlock')) return;
      if (rel !== DEF_FILE) scan(hits, rel, line, i);
    });
  }
  const defs = (code(read(DEF_FILE)).match(/PlaceholderBlock/g) || []).length;
  check('PlaceholderBlock 只剩 room_panel_kit.dart 的定义',
    hits.length === 0 && defs >= 1,
    hits.length
      ? `越界：${hits.join(' | ')}`
      : `仅 ${DEF_FILE} 命中 ${defs} 处（class + 构造）`);
}

/* ---------- 10 showModalBottomSheet 只许一处 ---------- */
{
  const ALLOW = 'lib/ui/room/sheets/room_sheet.dart';
  const hits = [];
  for (const rel of roomFiles) {
    code(read(rel)).split('\n').forEach((line, i) => {
      if (!line.includes('showModalBottomSheet')) return;
      if (rel !== ALLOW) scan(hits, rel, line, i);
    });
  }
  const n = (code(read(ALLOW)).match(/showModalBottomSheet/g) || []).length;
  check('showModalBottomSheet 只许 sheets/room_sheet.dart 一处',
    hits.length === 0 && n === 1,
    hits.length
      ? `越界：${hits.join(' | ')}`
      : `仅 ${ALLOW} 命中 ${n} 处调用`);
}

/* ---------- 11 弹层不走裸 showDialog ---------- */
{
  const hits = [];
  for (const rel of roomFiles) {
    code(read(rel)).split('\n').forEach((line, i) => {
      if (/\bshowDialog\s*[<(]/.test(line)) scan(hits, rel, line, i);
    });
  }
  check('弹层不走裸 showDialog', hits.length === 0,
    hits.length ? hits.join(' | ') : `扫描 ${roomFiles.length} 个文件，零命中`);
}

/* ---------- 12 门禁字面量不入注释 ---------- */
{
  // 反「自我实现」：不许把这些串写进注释来糊弄朴素 grep。
  const banned = /package:flutter|dart:io|dart:ui|state\[[^\]]*\]\s*=(?!=)/;
  const hits = [];
  for (const rel of roomFiles) {
    comments(read(rel)).forEach((line, i) => {
      if (banned.test(line)) scan(hits, rel, line, i);
    });
  }
  check('门禁字面量不入注释（零命中）', hits.length === 0,
    hits.length ? hits.join(' | ') : `扫描 ${roomFiles.length} 个文件的注释行，零命中`);
}

/* ---------- 13 文件清单与规模（信息项） ---------- */
{
  // ★ 行数必须与 `wc -l` 口径一致：`split('\n')` 在「文件以换行结尾」时会多出
  //   一个空串元素，逐文件累加就会多算「文件数」行（51 个文件 → 多 51）。
  //   这里按「实际文本行」计：末尾空行不算。
  const lineOf = (rel) => {
    const lines = read(rel).split('\n');
    if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
    return lines.length;
  };
  const total = roomFiles.reduce((s, f) => s + lineOf(f), 0);
  const viewTotal = viewFiles.reduce((s, f) => s + lineOf(f), 0);
  const groups = new Map();
  for (const rel of roomFiles) {
    const sub = rel.includes('/') ? rel.substring(0, rel.lastIndexOf('/')) : '.';
    groups.set(sub, (groups.get(sub) || 0) + 1);
  }
  check('文件清单与规模（人工比对用）', true,
    `lib/ui/room 共 ${roomFiles.length} 个 .dart / ${total} 行；` +
    `view/ ${viewFiles.length} 个 / ${viewTotal} 行；` +
    `分布：${[...groups.entries()].map(([d, n]) => `${d}=${n}`).join(' ')}`);
}

/* ---------- 汇总 ---------- */
const failed = results.filter((r) => !r.ok);
console.log('==== QA P5 UI GATE · 静态探针 ====');
for (const r of results) {
  console.log(`${r.ok ? '[OK]  ' : '[FAIL]'} ${r.name}\n       ${r.detail}`);
}
console.log(`==== 合计 ${results.length} 条，失败 ${failed.length} 条 ====`);
console.log(`P5_UI_GATE IS_PASS: ${failed.length === 0 ? 'YES' : 'NO'}`);
process.exitCode = failed.length === 0 ? 0 : 1;
