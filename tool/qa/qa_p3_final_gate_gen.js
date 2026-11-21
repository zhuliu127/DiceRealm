/* ============================================================
 * QA P3 最终闸门 · 独立预言机（第 3 批，只服务于「主动推翻修复」探针）
 *
 * 用法： node tool/qa/qa_p3_final_gate_gen.js   （生成脚本，不是测试）
 * 输出： test/fixtures/qa_p3_final_gate_oracle.json
 *
 * 与 qa_p3_oracle_gen.js 的区别：那批是 16:20 收敛前的探针期望值；
 * 这批专门针对工程师 17:49 落盘的 6 项修复，造更刁的输入：
 *   · core/share.js#buildPayload 的 unitName 全部 falsy 变体
 *     （缺字段 / null / '' / false / 0 / 空白串 / 正常职业名），
 *     抓真实 fetch body 做逐字节对照；
 *   · core/ai.js#toProfile 的 occupationSkills 混合 falsy 数组
 *     （复刻 `String(x || '').trim()` + filter(Boolean) + slice(0,8)）。
 *
 * 绝不修改旧版只读源码；所有期望值来自 vm 沙箱真实执行。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { createSandbox, SRC_ROOT } = require('../oracle/load');

const OUT = path.resolve(__dirname, '../../test/fixtures');
const { ctx, sandbox: S } = createSandbox({ withPreset: true });

function J(v) { return JSON.parse(JSON.stringify(v === undefined ? null : v)); }

const CAP_ZERO = {
  aiAttrCap: 0, aiAttrCapWithLuck: true, aiOccPtsCap: 0, aiIntPtsCap: 0,
};

/* 复用已验证过的完整卡形状：B 套「完整卡逐字节一致」用例已证明
   Dart buildSharePayload 与旧版 CocShare.create 对这个形状逐字一致，
   以它为底座只改 basicInfo.occupationName，避免自造卡形状引入无关差异。 */
const base = JSON.parse(
  fs.readFileSync(path.join(OUT, 'qa_p3_share_oracle.json'), 'utf8')
).cards[0];

vm.runInContext(
  fs.readFileSync(path.join(SRC_ROOT, 'core/share.js'), 'utf8'),
  ctx,
  { filename: 'core/share.js' },
);

const captures = [];
S.BuildConfig = { shareBase: '' };
S.Store.setSettings({ shareBase: 'http://127.0.0.1:9/coc' });
S.fetch = function (url, opts) {
  captures.push({ url, method: opts.method, headers: opts.headers, body: opts.body });
  return Promise.resolve({
    ok: true, status: 200,
    json: () => Promise.resolve({ id: 'sh_qa', url: 'https://s.example/c/sh_qa', delToken: 'tok_qa' }),
    text: () => Promise.resolve(''),
  });
};

const VARIANTS = [
  { id: 'missing', del: true },
  { id: 'null', value: null },
  { id: 'empty', value: '' },
  { id: 'false', value: false },
  { id: 'zero', value: 0 },
  { id: 'spaces', value: '  ' },     // JS truthy：空白串不是 falsy，应原样保留
  { id: 'truthy', value: '考古学家' },
];

(async () => {
  const unitNameCases = [];
  for (const v of VARIANTS) {
    const c = J(base);
    if (v.del) delete c.basicInfo.occupationName;
    else c.basicInfo.occupationName = v.value;
    captures.length = 0;
    await S.CocShare.create(c);
    const body = captures[0].body;
    const parsed = JSON.parse(body);
    unitNameCases.push({
      id: v.id,
      card: c,
      body: body,
      unitName: parsed.data.unitName,
    });
  }

  /* toProfile：混合 falsy / 需 trim / 数字 / 8 项上限。
     旧版 `String(x || '').trim()` + filter(Boolean) + slice(0, 8)。 */
  S.Store.setSettings(CAP_ZERO);
  const raw = {
    occupationName: '自定义职业',
    occupationSkills: [
      false, 0, null, '', '  ', '侦查', ' 图书馆 ',
      0, 1, '  潜行  ', '妙手', '话术', '历史', '医学', '法律',
    ],
    name: '张三', gender: '男', age: 30,
  };
  const profileExpect = J(S.AIGen.toProfile(raw));

  fs.writeFileSync(
    path.join(OUT, 'qa_p3_final_gate_oracle.json'),
    JSON.stringify({
      source: 'coc7th-card-app/web/js/core/share.js (vm sandbox fetch captured) '
        + '+ core/ai.js#toProfile',
      unitNameCases,
      toProfile: { raw, expect: profileExpect },
    }),
    'utf8',
  );
  console.log('QA final-gate oracle written: unitName', unitNameCases.length,
    '/ toProfile.occupationSkills',
    (profileExpect.occupationSkills || []).length,
    '/ unitNames', unitNameCases.map((c) => JSON.stringify(c.unitName)).join(','));
})().catch((e) => { console.error(e); process.exit(1); });
