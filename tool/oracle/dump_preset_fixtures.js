/* ============================================================
 * tool/oracle/dump_preset_fixtures.js — 预设卡生成器的期望值
 *
 * 用法： node tool/oracle/dump_preset_fixtures.js
 * 输出： test/fixtures/preset.json
 *
 * 做法与 dump_fixtures.js 完全一致（P0 那一套）：
 *   1. 在 Node 沙箱里**原样**加载旧版 JS（不改任何一个字符）；
 *   2. 固定 seed 集，对每个 seed 调用 `PresetGen.generateOne` / `generate`；
 *   3. 把**整张卡的 JSON** 与「消耗了几个随机数」一起 dump 出来。
 *
 * 为什么整张卡逐字段比：
 *   preset.js 是「随机 → 规则落地」的整条链路（属性/职业/技能/装备/资产/背景），
 *   只比几个汇总值会漏掉大量字段级偏差。整卡比等价于一次性钉住
 *   「同一 seed 出来的是同一张卡」，比什么都强。
 *
 * ⚠️ `randUsed` 是比 JSON 更严格的一道闸门：
 *   卡面一致但消耗数不同 → 说明某处多掷/少掷了随机数（随机序列已经分叉），
 *   换个 seed 就会出现两张不同的卡。所以必须一起断言。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const { createSandbox } = require('./load');

const { sandbox: S } = createSandbox({ withPreset: true });
const OUT = path.resolve(__dirname, '../../test/fixtures');

/* 与 dump_fixtures.js 相同：确定性、互不相关的一串 seed */
let seq = 0;
function nextSeed() {
  return (++seq) * 2654435761 % 4294967296;
}

function J(v) {
  if (v === undefined) return null;
  return JSON.parse(JSON.stringify(v));
}

/** 从 args 复原 JS 侧 opts（Dart 侧有逐字对应的实现） */
function optsFrom(args) {
  if (!args || args.noOpts) {
    // 「调用方什么也没给」—— generateOne() 不带参数
    return args && args.noOpts ? undefined : {};
  }
  const o = {};
  if (args.settingId) o.setting = S.CocPersonas.getById(args.settingId);
  if (args.profile) o.profile = args.profile;
  if (args.caps) o.caps = args.caps;
  if (args.ptsCap) o.ptsCap = args.ptsCap;
  return o;
}

const cases = [];

/** 一张卡 */
function one(label, args) {
  const seed = nextSeed();
  S.__setSeed(seed);
  let out = null;
  let error = null;
  try {
    out = S.PresetGen.generateOne(optsFrom(args));
  } catch (e) {
    error = String((e && e.message) || e);
  }
  cases.push({
    name: label,
    fn: 'generateOne',
    args: J(args || {}),
    expect: error ? null : J(out),
    randUsed: S.__randUsed(),
    seed,
    error,
  });
}

/** 一批卡 */
function many(label, n, args) {
  const seed = nextSeed();
  S.__setSeed(seed);
  let out = null;
  let error = null;
  try {
    out = S.PresetGen.generate(n, optsFrom(args));
  } catch (e) {
    error = String((e && e.message) || e);
  }
  cases.push({
    name: label,
    fn: 'generate',
    args: J(Object.assign({ n: n }, args || {})),
    expect: error ? null : J(out),
    randUsed: S.__randUsed(),
    seed,
    error,
  });
}

/* ============================================================
 * 一、generateOne 默认分支 —— 60 个 seed
 * ============================================================ */
for (let i = 0; i < 60; i++) {
  one(`generateOne/default#${i + 1}`, {});
}

/* ============================================================
 * 二、指定世界设定 —— 覆盖三种装备口径（现代 / 1920s / 古代）
 *    以及 12 个世界的货币 / 城市 / 姓名池
 * ============================================================ */
const SETTING_IDS = S.CocPersonas.list.map((s) => s.id);
SETTING_IDS.forEach((id) => {
  one(`generateOne/setting:${id}`, { settingId: id });
});

/* ============================================================
 * 三、外部创意（AI / 彩蛋）注入
 * ============================================================ */
one('generateOne/profile:gender-age-女35', { profile: { gender: '女', age: 35 } });
one('generateOne/profile:gender-age-男50', { profile: { gender: '男', age: 50 } });
one('generateOne/profile:age-15', { profile: { age: 15 } });
one('generateOne/profile:age-80', { profile: { age: 80 } });
one('generateOne/profile:age-overrange', { profile: { age: 200 } });
// 「职业为空」：显式给一个不存在的职业名 → 必须回落到加权随机
one('generateOne/profile:occ-empty', { profile: { occupationName: '' } });
one('generateOne/profile:occ-unknown', { profile: { occupationName: '并不存在的职业' } });
one('generateOne/profile:occ-forced-id-unknown', { profile: { occupationId: 'no-such-occ' } });
one('generateOne/profile:occ-医生', { profile: { occupationName: '医生' } });
one('generateOne/profile:occ-记者', { profile: { occupationName: '记者' } });
one('generateOne/profile:occ-军官', { profile: { occupationName: '军官' } });
// 自定义职业（occ1）路径：AI 明确要求时才用，技能名只作建议
one('generateOne/profile:occ-custom', {
  profile: { occupationName: '自定义职业', occupationSkills: ['侦查', '聆听', '图书馆使用'] },
});
one('generateOne/profile:occ-custom-badskills', {
  profile: { occupationName: '自定义职业', occupationSkills: ['瞎写的', '也不存在'] },
});
// 姓名 / 籍贯 / 时代直接指定
one('generateOne/profile:name-place', {
  profile: { name: '测试角色', gender: '男', residence: '杭州', birthplace: '绍兴', era: '1920年代' },
});
one('generateOne/profile:era-custom', { profile: { era: '自定义', eraCustom: '近未来 · 赛博' } });
// 设定从 profile.setting 里来（AI 会给中文标签）
one('generateOne/profile:setting-民国', { profile: { setting: '民国' } });
one('generateOne/profile:setting-cn-ancient', { profile: { setting: 'cn-ancient' } });
// AI 口径的属性（宽松）：8 项在 15-99、合计 200-720 就收下
one('generateOne/profile:ai-attrs', {
  profile: {
    fromAI: true,
    attributes: { str: 55, con: 60, siz: 65, dex: 70, app: 60, int: 85, pow: 70, edu: 80, luck: 50 },
  },
});
one('generateOne/profile:ai-attrs-bad', {
  profile: { fromAI: true, attributes: { str: 5, con: 5, siz: 5, dex: 5, app: 5, int: 5, pow: 5, edu: 5 } },
});
// 彩蛋 profile（用真数据，但把 profile 作为字面量传进去 —— 两边拿到同一份）
const EGG_ALL = S.CocEasterEgg.all();
[0, 5, 11, 21, 22, 23, 25, 27, 29].forEach((i) => {
  if (i < EGG_ALL.length) {
    one(`generateOne/egg:${i}-${EGG_ALL[i].data.name}`, {
      profile: J(S.CocEasterEgg.toProfile(EGG_ALL[i])),
    });
  }
});

/* ============================================================
 * 四、房规数值上限（caps）—— 属性总和 / 本职 / 兴趣三类
 * ============================================================ */
const CAP_SETS = [
  { attrCap: 420, withLuck: true, occCap: 0, intCap: 0 },
  { attrCap: 380, withLuck: false, occCap: 0, intCap: 0 },
  { attrCap: 500, withLuck: true, occCap: 70, intCap: 60 },
  { attrCap: 0, withLuck: true, occCap: 80, intCap: 0 },
  { attrCap: 0, withLuck: true, occCap: 0, intCap: 70 },
  { attrCap: 0, withLuck: true, occCap: 60, intCap: 50 },
  { attrCap: 360, withLuck: true, occCap: 55, intCap: 45 },
];
CAP_SETS.forEach((caps, i) => {
  one(`generateOne/caps#${i + 1}`, { caps });
});
// 旧 ptsCap 写法（只给技能上限、不给属性上限）
one('generateOne/ptsCap#1', { ptsCap: { occ: 80, int: 60 } });
one('generateOne/ptsCap#2', { ptsCap: { occ: 0, int: 0 } });

/* ============================================================
 * 五、opts 完全缺省 —— generateOne() 不带参数
 * ============================================================ */
one('generateOne/no-opts', { noOpts: true });

/* ============================================================
 * 六、批量 generate(n)
 * ============================================================ */
many('generate/5#1', 5);
many('generate/5#2', 5);
many('generate/5#3', 5);
many('generate/5#4', 5);
many('generate/5#5', 5);
many('generate/5#6', 5);
many('generate/1#1', 1);
many('generate/1#2', 1);
many('generate/3#1', 3);
many('generate/3#2', 3);
many('generate/6#1', 6);
// n=0：原码 `parseInt(n,10) || 5` 会退化成 5 张 —— 这个坑必须钉住
many('generate/0->5', 0);
// 指定设定时**不抽彩蛋**（preset.generate 的 if 条件里有 !opts.setting）
many('generate/5-fixed-setting', 5, { settingId: 'cn-modern' });

/* ============================================================ */
const payload = {
  meta: {
    source: 'coc7th-card-app/web/js/core/preset.js',
    nowMs: 1700000000000,
    seedFormula: '(++seq) * 2654435761 % 4294967296',
    total: cases.length,
  },
  cases,
};

fs.writeFileSync(path.join(OUT, 'preset.json'), JSON.stringify(payload), 'utf8');

const bytes = fs.statSync(path.join(OUT, 'preset.json')).size;
console.log('cases:', cases.length,
  '/ generateOne:', cases.filter((c) => c.fn === 'generateOne').length,
  '/ generate:', cases.filter((c) => c.fn === 'generate').length,
  '/ errors:', cases.filter((c) => c.error).length);
console.log('preset.json', (bytes / 1024).toFixed(1), 'KB');
if (cases.some((c) => c.error)) {
  console.log('⚠️ 原码抛异常的用例：');
  cases.filter((c) => c.error).forEach((c) => console.log('  ', c.name, '→', c.error));
}
