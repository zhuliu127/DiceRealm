/* ============================================================
 * tool/gen_legacy_export.js — 用**旧版真实代码**生成导入/导出 fixture
 *
 * 做法：把旧版 `core/store.js` 原样加载进 Node（只补一个假的
 * `window` + `localStorage`），随机数与时钟固定，然后调用
 * `Store.exportCharacter()` / `Store.listCharacters()` 拿到**旧版逐字节输出**。
 *
 * 为什么不"照着格式手写一份"：手写的样本只能证明「我认为旧版长这样」，
 * 而这里生成的是旧版代码真的吐出来的东西 —— 导入能吃掉它，才算兼容。
 *
 * 产物：
 *   test/fixtures/legacy_card_export.json        单卡（coc7-card v1）
 *   test/fixtures/legacy_bundle_export.json      全量（coc7-bundle v1）
 *   test/fixtures/legacy_card_blocks_export.json P2-B2：带经历/伙伴/神话/法术的单卡
 *
 * 跑法：node tool/gen_legacy_export.js
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const OLD_JS = path.resolve(
  __dirname,
  '../../coc7th-card-app/web/js'
);
const OUT_DIR = path.resolve(__dirname, '../test/fixtures');

/* 按旧版 index.html 的加载顺序加载必要模块 ——
   只有把 Engine / CocMadness 一起装起来，`listCharacters()` 才会像真机那样
   先 normalize + recalc 再吐数据（否则导出的卡是「没算过的半成品」）。 */
const MODULES = [
  'data/skills.js',
  'data/occupations.js',
  'data/madness.js',
  'data/spells.js',
  'core/dice.js',
  'core/rules-coc7.js',
  'core/occupation.js',
  'core/skillmodel.js',
  'core/engine.js',
  'core/store.js',
  'core/madness.js'
];

/* ---------- 确定性随机 / 时钟（与 tool/oracle/load.js 同款 LCG） ---------- */
let seed = 20081108;
function lcg() {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 4294967296;
}
const FIXED_NOW = 1700000000000;

/* ---------- 最小浏览器环境 ---------- */
const storage = new Map();
const sandbox = {
  console,
  Math: Object.create(Math),
  Date: class extends Date {
    static now() {
      return FIXED_NOW;
    }
  },
  localStorage: {
    getItem: (k) => (storage.has(k) ? storage.get(k) : null),
    setItem: (k, v) => storage.set(k, String(v)),
    removeItem: (k) => storage.delete(k)
  },
  setTimeout,
  clearTimeout
};
sandbox.Math.random = lcg;
sandbox.window = sandbox;
sandbox.global = sandbox;

vm.createContext(sandbox);
for (const m of MODULES) {
  const file = path.join(OLD_JS, m);
  vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox, { filename: file });
}
sandbox.global = sandbox;
sandbox.window = sandbox;

const Store = sandbox.Store;
if (!Store) throw new Error('旧版 Store 没挂到 window 上');

/* ============================================================
 * 造一张「有真实内容」的旧卡：
 *   · 属性齐备（否则 recalc 不会初始化状态值）
 *   · 一条职业点 + 一条兴趣点
 *   · 背景里带一条**症状表里真实存在**的恐惧症文本 ——
 *     这样 normalize 的「背景文本 → 结构化症状」迁移路径也会被 fixture 覆盖
 * ============================================================ */
const c = Store.newCharacter('coc7');
c.id = 'legacy01';
c.characterName = '旧版调查员';
c.playerName = '老玩家';
c.basicInfo.age = 32;
c.basicInfo.gender = '女';
c.basicInfo.residence = '阿卡姆 · 洛根街 12 号';
c.basicInfo.birthplace = '波士顿';
c.basicInfo.occupationName = '记者';
c.occupationId = 'occ67';

const attrs = ['str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu', 'luck'];
attrs.forEach((k) => {
  c.attributes[k] = 50;
});

c.skills = [
  {
    key: 'library_use',
    id: 'library_use',
    name: '图书馆使用',
    sub: '',
    base: 20,
    growth: 0,
    occ: 40,
    int: 0,
    total: 60,
    custom: false,
    desc: ''
  },
  {
    key: 'spot_hidden',
    id: 'spot_hidden',
    name: '侦查',
    sub: '',
    base: 25,
    growth: 0,
    occ: 0,
    int: 35,
    total: 60,
    custom: false,
    desc: ''
  }
];

c.background.description = '衣着略显褶皱的风衣，领口别着一支钢笔。';
c.background.ideology = '信仰 / 人生观 / 价值观 / 政治观点 / 人生目标：\n真相必须被记录。';
c.background.significantPeople = '主编老陈｜报社上司｜他给了我第一份工作｜严厉但护短。';
c.background.meaningfulPlaces = '报社资料室｜堆满旧报纸的房间｜我在这里查到过改变一生的线索。';
c.background.treasuredPossessions = '祖父的钢笔｜笔身有裂痕｜祖父遗物｜提醒我为什么开始写作。';
c.background.traits = '固执、习惯性怀疑权威、咖啡成瘾';
c.background.wounds = '右手掌有一道旧烫伤。';
c.background.phobias = '【恐惧症】幽闭恐惧症：对密闭空间有强烈不适。';

const normalized = Store.normalize(c);
Store.upsertCharacter(normalized);
/* 旧版「我的角色」列表每条都会 normalize + recalc（store.js#listCharacters）。
   真机导出前一定经过这一步，所以 fixture 也必须先过一遍 —— 否则导出的
   是「派生值还没算」的半成品，不能代表老玩家手里的卡。 */
Store.listCharacters();

/* ---------- 用旧版代码导出（这就是「旧版真实输出」） ---------- */
const cardJson = Store.exportCharacter('legacy01');
if (!cardJson) throw new Error('Store.exportCharacter 返回 null');

/* app.js:561 的同一句（全量导出） */
const bundleJson = JSON.stringify(
  { format: 'coc7-bundle', version: 1, characters: Store.listCharacters() },
  null,
  2
);

if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(path.join(OUT_DIR, 'legacy_card_export.json'), cardJson + '\n', 'utf8');
fs.writeFileSync(path.join(OUT_DIR, 'legacy_bundle_export.json'), bundleJson + '\n', 'utf8');

console.log('已生成：');
console.log('  test/fixtures/legacy_card_export.json   ', cardJson.length, 'bytes');
console.log('  test/fixtures/legacy_bundle_export.json ', bundleJson.length, 'bytes');
console.log('单卡 id =', JSON.parse(cardJson).data.id, '· 名称 =', JSON.parse(cardJson).data.characterName);

/* ============================================================
 * 第二张卡：P2-B2 的四块内容（经历 / 伙伴 / 克苏鲁神话 / 已学法术）
 *
 * 键名与「新增一条时初始化成什么」全部来自旧版源码里那两个字面量：
 *   steps-d.js:495  c.history.push({ title:'', date:'', description:'',
 *                                    sanChange:'', hpChange:'', skillChanges:'',
 *                                    moneyChange:'', itemsObtained:'', notes:'' })
 *   steps-d.js:500  c.companions.push({ name:'', avatar:'', identity:'',
 *                                       age:'', relationship:'', description:'' })
 *   steps-d.js:463  spells().push({ id:'custom_'+..., name, category, cost,
 *                                   time, effect, condition, custom:true })
 * 法术条目本身用旧版数据表 COC_SPELLS 深拷贝（steps-d.js:385 同款），
 * 这样 fixture 里那条法术就是**旧版真的会存进去的形状**。
 * ============================================================ */
const c2 = Store.newCharacter('coc7');
c2.id = 'legacy02';
c2.characterName = '旧版博学者';
c2.playerName = '老玩家';
c2.basicInfo.age = 41;
c2.basicInfo.gender = '男';
c2.basicInfo.residence = '普罗维登斯';
c2.basicInfo.birthplace = '金斯波特';
c2.basicInfo.occupationName = '神秘学者';
c2.occupationId = 'occ67';
attrs.forEach((k) => { c2.attributes[k] = 50; });

// ① 经历（9 个键）
c2.history = [
  {
    title: '阿卡姆调查事件',
    date: '1925-03',
    description: '在旧宅地下室发生了不该发生的事。',
    sanChange: '-5',
    hpChange: '-2',
    skillChanges: '侦查 +3',
    moneyChange: '0',
    itemsObtained: '神秘古书',
    notes: '那一夜之后我开始做同一个梦。'
  },
  {
    title: '金斯波特郊外的仪式',
    date: '1925-07',
    description: '',
    sanChange: '-1D6',
    hpChange: '',
    skillChanges: '',
    moneyChange: '-20',
    itemsObtained: '',
    notes: ''
  }
];

// ② 伙伴（6 个键）
c2.companions = [
  {
    name: '约翰·万斯',
    avatar: '',
    identity: '大学教授',
    age: '45',
    relationship: '调查搭档',
    description: '两年前认识的考古学家。'
  }
];

// ③ 克苏鲁神话：knowledge + notes（mythos.skill 旧版从不写，保持 0）
c2.mythos.knowledge = '已知的神话学识：达贡、克苏鲁的星位。';
c2.mythos.notes = '古籍 / 魔法 / 神话生物 / 第三类接触 / 梦境 / 其他：在梦中见过拉莱耶。';

// ④ 已学法术：一条来自旧版数据表（深拷贝），一条是自定义
const catalogSpell = JSON.parse(JSON.stringify(sandbox.COC_SPELLS[0]));
c2.mythos.spells = [
  catalogSpell,
  {
    id: 'custom_m0legacy',
    name: '旧版自定义法术',
    category: '自定义',
    cost: '8 点魔法值',
    time: '1 轮',
    effect: '让灯芯自己点燃。',
    condition: '',
    custom: true
  }
];

Store.upsertCharacter(Store.normalize(c2));
Store.listCharacters();

const blocksJson = Store.exportCharacter('legacy02');
if (!blocksJson) throw new Error('Store.exportCharacter(legacy02) 返回 null');
fs.writeFileSync(path.join(OUT_DIR, 'legacy_card_blocks_export.json'), blocksJson + '\n', 'utf8');
console.log('  test/fixtures/legacy_card_blocks_export.json', blocksJson.length, 'bytes');
console.log('  四块：history', JSON.parse(blocksJson).data.history.length,
            '· companions', JSON.parse(blocksJson).data.companions.length,
            '· spells', JSON.parse(blocksJson).data.mythos.spells.length);
