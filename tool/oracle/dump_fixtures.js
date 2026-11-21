/* ============================================================
 * tool/oracle/dump_fixtures.js — 用原 JS 生成等价性测试的期望值
 *
 * 用法： node tool/oracle/dump_fixtures.js
 * 输出： test/fixtures/*.json
 *
 * 核心做法（见任务书第 3 条）：
 *   1. 在 Node 沙箱里原样加载老 JS（不修改任何一个字符）；
 *   2. 对**确定性输入集**调用规则函数，把返回值 dump 成 JSON；
 *   3. 每个 case 都记录 seed 与「消耗了几个随机数」——
 *      Dart 侧用同一个 LCG 复现同一条随机序列，并把消耗数也断言一遍。
 *      消耗数对不上说明两边的随机调用顺序产生了分歧（这本身就是 bug）。
 *
 * 所以这里的写法要克制：不要为了「让 case 好写」去改数据结构，
 * 直接把 JS 原生返回值原样 JSON 化。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const { createSandbox } = require('./load');

const { sandbox: S } = createSandbox();
const OUT = path.resolve(__dirname, '../../test/fixtures');

/** JSON 化：丢掉 undefined / 函数（与原码返回的对象形状保持一致） */
function J(v) {
  if (v === undefined) return null;
  return JSON.parse(JSON.stringify(v));
}

let seq = 0;
function nextSeed() {
  return (++seq) * 2654435761 % 4294967296;
}

/** 纯函数调用 */
function pure(fnName, args, fn) {
  const seed = nextSeed();
  S.__setSeed(seed);
  let out, error = null;
  try {
    out = fn();
  } catch (e) {
    // 原码在个别分支上会抛异常（例如 validatePointBuy 里引用了未定义的 ATT_MAP）。
    // 这些 case 仍然记录下来，Dart 侧跳过并单独统计 —— 不改原码，但要留证据。
    error = String(e && e.message ? e.message : e);
  }
  return {
    name: `${fnName}#${seq}`,
    fn: fnName,
    args: J(args),
    expect: error ? null : J(out),
    randUsed: S.__randUsed(),
    seed,
    error,
  };
}

/** 改一张卡（输入卡原样留在 args 里，输出是函数返回值或改完的卡） */
function mutate(fnName, card, fn, extraArgs) {
  const seed = nextSeed();
  const input = J(card);
  S.__setSeed(seed);
  const c = JSON.parse(JSON.stringify(card));
  let out, error = null;
  try {
    out = fn(c);
  } catch (e) {
    error = String(e && e.message ? e.message : e);
  }
  return {
    name: `${fnName}#${seq}`,
    fn: fnName,
    args: J(Object.assign({ card: input }, extraArgs || {})),
    expect: error ? null : J(out === undefined ? c : out),
    randUsed: S.__randUsed(),
    seed,
    error,
  };
}

const write = (file, domain, cases) => {
  fs.mkdirSync(OUT, { recursive: true });
  const body = {
    domain,
    oracle: 'coc7th-card-app/web/js',
    note: '由 tool/oracle/dump_fixtures.js 生成；请勿手改。',
    count: cases.length,
    cases,
  };
  fs.writeFileSync(path.join(OUT, file), JSON.stringify(body, null, 1), 'utf8');
  const bad = cases.filter((c) => c.error);
  console.log(
    `${file.padEnd(22)} ${String(cases.length).padStart(4)} 例` +
      (bad.length ? `  ⚠️ 原码抛异常 ${bad.length} 例：${bad.map((c) => c.name + ' → ' + c.error).slice(0, 3).join(' | ')}` : ''),
  );
};

/* ============================================================
 * 0. 造卡的公共工具
 * ============================================================ */
const num = (v) => parseInt(v, 10) || 0;

function mkCard(opts) {
  const o = opts || {};
  const c = S.Store.newCharacter();
  if (o.id) c.id = o.id;
  if (o.name !== undefined) c.characterName = o.name;
  if (o.player !== undefined) c.playerName = o.player;
  const age = o.age === undefined ? 30 : o.age;
  c.age = age;
  c.basicInfo.age = age;
  const attrs = o.attrs || {};
  const keys = ['str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu', 'luck'];
  keys.forEach((k) => {
    if (attrs[k] !== undefined) c.attributes[k] = attrs[k];
  });
  if (o.occupationId !== undefined) c.occupationId = o.occupationId;
  if (o.picks) c.occupationPicks = o.picks;
  if (o.skills) c.skills = o.skills;
  if (o.status) Object.assign(c.status, o.status);
  if (o.assets) Object.assign(c.assets, o.assets);
  if (o.eduProgress) c.eduProgress = o.eduProgress;
  if (o.background) Object.assign(c.background, o.background);
  if (o.madness) c.madness = o.madness;
  if (o.skillCap !== undefined) c.skillCap = o.skillCap;
  if (o.skillCapOcc !== undefined) c.skillCapOcc = o.skillCapOcc;
  if (o.skillCapInterest !== undefined) c.skillCapInterest = o.skillCapInterest;
  if (o.sanLoss !== undefined) c.sanLoss = o.sanLoss;
  if (o.baseMaxSAN !== undefined) c.baseMaxSAN = o.baseMaxSAN;
  if (o.raw) Object.assign(c, o.raw);
  return c;
}

const ATTR_SETS = {
  mid: { str: 50, con: 50, siz: 50, dex: 50, app: 50, int: 50, pow: 50, edu: 50, luck: 50 },
  low: { str: 15, con: 15, siz: 15, dex: 15, app: 15, int: 15, pow: 15, edu: 15, luck: 15 },
  high: { str: 90, con: 85, siz: 80, dex: 75, app: 70, int: 65, pow: 60, edu: 55, luck: 50 },
  mixed: { str: 80, con: 40, siz: 60, dex: 45, app: 35, int: 70, pow: 55, edu: 65, luck: 45 },
  zero: { str: 0, con: 0, siz: 0, dex: 0, app: 0, int: 0, pow: 0, edu: 0, luck: 0 },
  // 3 是「低于 15 下限」的极端值：扣减应当被下限挡住（unapplied > 0）
  tiny: { str: 3, con: 3, siz: 3, dex: 3, app: 3, int: 3, pow: 3, edu: 3, luck: 3 },
};

const AGES = [15, 19, 20, 25, 30, 39, 40, 45, 49, 50, 55, 59, 60, 65, 69, 70, 75, 79, 80, 85, 89, 90];

/* ============================================================
 * 1. 骰子
 * ============================================================ */
function dumpDice() {
  const cases = [];

  // 成功等级：掷值 × 技能值 全组合（含 01 / 100 / 96-100 动态阈值边界）
  const rolls = [1, 2, 3, 5, 6, 10, 25, 49, 50, 51, 94, 95, 96, 99, 100];
  const skills = [0, 1, 4, 5, 9, 10, 24, 25, 49, 50, 51, 60, 94, 95, 99, 100, 120];
  rolls.forEach((r) => {
    skills.forEach((sk) => {
      cases.push(pure('successLevel', [r, sk], () => S.COCDice.successLevel(r, sk)));
    });
  });

  // 奖励骰 / 惩罚骰
  [-5, -3, -2, -1, 0, 1, 2, 3, 5].forEach((b) => {
    cases.push(pure('d100Bonus', [b], () => S.COCDice.d100Bonus(b)));
  });

  // 掷骰表达式
  [
    '', '3D6', '2D6+6', '1D10+1D4+2', '4D6/3码', '1D100', 'D6', '-2D6+4',
    '（1D6）2D6+3', '无', '1d4+1d6+1', '2D10-1', '3D6+1D6', '1D3', '10D10',
  ].forEach((e) => {
    cases.push(pure('parse', [e], () => S.COCDice.parse(e)));
  });

  // roll / d / d100
  cases.push(pure('roll', [3, 6], () => S.COCDice.roll(3, 6)));
  cases.push(pure('roll', [0, 6], () => S.COCDice.roll(0, 6)));
  cases.push(pure('d', [20], () => S.COCDice.d(20)));
  cases.push(pure('d100', [], () => S.COCDice.d100()));

  write('dice.json', 'dice', cases);
}

/* ============================================================
 * 2. 规则：年龄 / 派生 / 上限 / 校验
 * ============================================================ */
function dumpRules() {
  const cases = [];

  // 年龄调整：全年龄 × 5 组属性
  AGES.forEach((age) => {
    Object.keys(ATTR_SETS).forEach((setName) => {
      const a = Object.assign({ age }, ATTR_SETS[setName]);
      cases.push(pure('ageAdjust', [a], () => S.COC7.ageAdjust(a)));
    });
  });

  // 教育进步增益（eduBonus 只落在生效值上）
  [
    { age: 45, eduBonus: 0 },
    { age: 45, eduBonus: 7 },
    { age: 45, eduBonus: 40 },
    { age: 70, eduBonus: 30 },
    { age: 20, eduBonus: 5 },
  ].forEach((patch) => {
    const a = Object.assign({}, ATTR_SETS.mixed, patch);
    cases.push(pure('ageAdjust', [a], () => S.COC7.ageAdjust(a)));
  });

  // ageRule / ageProgressChecks
  [0, 1, 15, 19, 20, 39, 40, 49, 50, 59, 60, 69, 70, 79, 80, 89, 90, 200, 999, 1000].forEach((age) => {
    cases.push(pure('ageRule', [age], () => S.COC7.ageRule(age)));
    cases.push(pure('ageProgressChecks', [age], () => S.COC7.ageProgressChecks(age)));
  });

  // spreadLoss / lossCapOf
  [
    [5, ['str', 'siz'], { str: 35, siz: 35 }],
    [5, ['str', 'con', 'dex'], { str: 35, con: 35, dex: 35 }],
    [20, ['str', 'con', 'dex'], { str: 35, con: 5, dex: 0 }],
    [80, ['str', 'con', 'dex'], { str: 75, con: 75, dex: 75 }],
    [80, ['str', 'con', 'dex'], { str: 5, con: 0, dex: 0 }],
    [0, ['str'], { str: 10 }],
    [-5, ['str'], { str: 10 }],
    [10, ['str'], {}],
    [7, ['str', 'con'], { str: 3, con: 3 }],
  ].forEach(([total, keys, caps]) => {
    cases.push(pure('spreadLoss', [total, keys, caps], () => S.COC7.spreadLoss(total, keys, caps)));
  });
  // lossCapOf 未挂在 COC7 上（内部函数），已由 ageAdjust 的用例覆盖

  // 派生属性
  AGES.forEach((age) => {
    Object.keys(ATTR_SETS).forEach((setName) => {
      const a = Object.assign({ age }, ATTR_SETS[setName]);
      cases.push(pure('derived', [a], () => S.COC7.derived(a)));
    });
  });

  // DB / 体格表（含 444 以上的外推）
  [0, 1, 2, 63, 64, 65, 84, 85, 124, 125, 164, 165, 204, 205, 284, 285, 364, 365, 443, 444,
    445, 500, 524, 525, 604, 605, 1000].forEach((v) => {
    cases.push(pure('dbBuild', [v], () => S.COC7.dbBuild(v)));
  });

  // 理智上限
  [0, 1, 5, 20, 49, 99, 100].forEach((v) => {
    cases.push(pure('maxSan', [v], () => S.COC7.maxSan(v)));
  });

  // 技能上限（本职 / 兴趣 / 母语 / 信用评级 / 基础值兜底）
  const capCards = [
    mkCard({ skillCap: 99 }),
    mkCard({ skillCap: 80 }),
    mkCard({ skillCap: 60, skillCapOcc: 90, skillCapInterest: 70 }),
    mkCard({ skillCap: 60, skillCapOcc: '', skillCapInterest: '' }),
    mkCard({ skillCap: 0, skillCapOcc: 0, skillCapInterest: 0 }),
  ];
  const capSkills = [
    { key: 'dodge', id: 'dodge', name: '闪避', base: 45 },
    { key: 'language_own', id: 'language_own', name: '母语', base: 65 },
    { key: 'credit', id: 'credit', name: '信用评级', base: 0 },
    { key: 'spot_hidden', id: 'spot_hidden', name: '侦查', base: 25 },
    { key: 'library', id: 'library', name: '图书馆使用', base: 90 },
    { key: 'fighting::斗殴', id: 'fighting', name: '格斗（斗殴）', base: 25 },
  ];
  capCards.forEach((card, ci) => {
    const occSet = { 'fighting::斗殴': true, library: true };
    capSkills.forEach((sk) => {
      cases.push(
        pure('skillCapOf', [J(card), sk, occSet], () => S.COC7.skillCapOf(card, sk, occSet)),
      );
      cases.push(
        pure('skillCapOf', [J(card), sk, null], () => S.COC7.skillCapOf(card, sk, null)),
      );
    });
  });
  ['language_own', 'credit', 'dodge', 'fighting'].forEach((id) => {
    cases.push(pure('capExempt', [id], () => S.COC7.capExempt(id)));
    cases.push(pure('isGrowthOnly', [id], () => S.COC7.isGrowthOnly(id)));
  });

  // 教育进步检定（掷骰判定：> 当前 EDU 才 +1D10）
  [0, 1, 25, 50, 65, 80, 95, 99, 100].forEach((edu) => {
    cases.push(pure('eduImproveCheck', [edu], () => S.COC7.eduImproveCheck(edu)));
  });

  // 属性生成器
  for (let i = 0; i < 6; i++) cases.push(pure('genRandom', [], () => S.COC7.generators.random()));
  ['str', 'siz', 'edu', 'luck', 'unknown'].forEach((k) => {
    cases.push(pure('genRandomOne', [k], () => S.COC7.generators.randomOne(k)));
  });

  // 购点校验
  const pb = [
    [ATTR_SETS.mid, 460, false],
    [ATTR_SETS.mid, 460, true],
    [ATTR_SETS.low, 460, false],
    [Object.assign({}, ATTR_SETS.mid, { str: 95 }), 460, false],
    [Object.assign({}, ATTR_SETS.mid, { str: 53 }), 460, false],
    [Object.assign({}, ATTR_SETS.high, { luck: '' }), 0, true],
    [{}, 480, true],
  ];
  pb.forEach(([attrs, cap, inc]) => {
    cases.push(
      pure('validatePointBuy', [attrs, cap, inc], () => S.COC7.generators.validatePointBuy(attrs, cap, inc)),
    );
  });

  // 雷达图
  const radarCard = mkCard({ attrs: ATTR_SETS.high });
  const radarSkills = [
    { id: 'spot_hidden', base: 25, total: 60 },
    { id: 'listen', base: 20, total: 20 },
    { id: 'library', base: 20, total: 75 },
    { id: 'fighting', base: 25, total: 120 },
    { id: 'dodge', base: 30, total: 30 },
    { id: 'custom', base: 0, total: 40 },
  ];
  cases.push(pure('radar', [radarSkills], () => S.COC7.radar(radarSkills, S.COC_SKILLS)));
  cases.push(pure('radar', [[]], () => S.COC7.radar([], S.COC_SKILLS)));

  // 三项纯校验器
  const validCards = [
    mkCard({}),
    mkCard({ name: '  ', player: '', age: 0 }),
    mkCard({ name: '张三', player: '李四', age: 30 }),
    mkCard({ name: '张三', player: '李四', age: 201 }),
    mkCard({ name: '张三', player: '李四', age: '30', attrs: ATTR_SETS.mid }),
    mkCard({ name: '张三', player: '李四', age: 30, attrs: Object.assign({}, ATTR_SETS.mid, { str: '', luck: 0 }) }),
    mkCard({ name: '张三', player: '李四', age: 30, attrs: Object.assign({}, ATTR_SETS.mid, { str: 1000 }) }),
  ];
  validCards.forEach((card, i) => {
    cases.push(mutate('validatorsAttributes', card, (c) => S.COC7.validators.attributes(c)));
    cases.push(mutate('validatorsBasicInfo', card, (c) => S.COC7.validators.basicInfo(c)));
    cases.push(mutate('validatorsOccupationSelected', card, (c) => S.COC7.validators.occupationSelected(c)));
  });

  // attrByName
  ['力量', 'STR', 'int', '灵感', '教育', '不存在', ' 敏捷 '].forEach((n) => {
    cases.push(pure('attrByName', [n], () => S.COC7.attrByName(n)));
  });

  write('rules.json', 'rules_coc7', cases);
}

/* ============================================================
 * 3. 职业模型
 * ============================================================ */
function dumpOccupation() {
  const cases = [];

  // 全部 230 个职业的本职技能描述解析
  S.COC_OCCUPATIONS.forEach((occ, i) => {
    cases.push(pure('parseSkillText', [occ.skillText], () => S.CocOccupation.parseSkillText(occ.skillText)));
  });

  // 技能名解析（别名 / 长名优先 / 组名）
  [
    '侦查', '侦察', '图书馆', '图书馆使用', '魅惑', '取悦', '母语', '外语', '驾驶：船',
    '格斗', '射击', '步枪', '科学', '艺术', '手艺', '信用评级', '克苏鲁神话', 'cm',
    '天文', '医学', '心理', '心理学', '法律', '电脑', '计算机使用', '重型操作',
    '不存在的技能', '', ' 掌  ', '速记', '摄影', '自行车驾驶', '拉丁语', '语言',
    '会计学', '考古', '急救', '自然', '博物学', '导航', '领航', '锁匠', '撬锁',
  ].forEach((n) => {
    cases.push(pure('resolveSkillId', [n], () => S.CocOccupation.resolveSkillId(n)));
  });

  // 属性点公式
  const formulas = [
    '教育×4', '教育×2+敏捷×2', '力量×2+体质×2', '智力×2+教育×2', '外貌×2+教育×2',
    '意志×2+教育×2', '力量×2+敏捷×2', '', '无', '敏捷×4', '力量或敏捷×2',
    '教育×2＋智力×2', '教育*4', '教育 x 4', '魅力×2',
  ];
  const formulaAttrs = [
    ATTR_SETS.high,
    ATTR_SETS.mixed,
    Object.assign({}, ATTR_SETS.mixed, { edu: '65', dex: '' }),
    ATTR_SETS.zero,
  ];
  formulas.forEach((f) => {
    formulaAttrs.forEach((a) => {
      cases.push(pure('evalFormula', [f, a], () => S.CocOccupation.evalFormula(f, a)));
    });
  });

  // 职业查询 / 搜索
  S.COC_OCCUPATIONS.slice(0, 12).forEach((o) => {
    cases.push(pure('getOccupationById', [o.id], () => S.CocOccupation.getById(o.id)));
  });
  ['会计', '医生', '格斗', '计算机', '魅惑', '考古', '不存在的职业', ''].forEach((kw) => {
    cases.push(pure('searchOccupations', [kw], () => S.CocOccupation.search(kw).map((o) => o.id)));
  });

  // getRequirements（带 picks）
  const pickIdx = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 40, 60, 80, 100, 120, 150, 180, 200, 220, 229];
  pickIdx.forEach((i) => {
    const occ = S.COC_OCCUPATIONS[i];
    const base = S.CocOccupation.parseSkillText(occ.skillText);
    // 给前两个 choice/free 块填一些 picks，覆盖「已选 / 未选」两条分支
    const picks = {};
    base.forEach((r, ri) => {
      if (r.type === 'choice' || r.type === 'free') {
        if (ri % 2 === 0) {
          picks[r.id] = [{ skill: 'spot_hidden', sub: null, name: '侦查' }];
        }
      }
      if (r.type === 'alt') {
        picks[r.id] = [Object.assign({}, (r.options && r.options[0]) || {})];
      }
    });
    const card = mkCard({ attrs: ATTR_SETS.high, occupationId: occ.id, picks });
    cases.push(mutate('getRequirements', card, (c) => S.CocOccupation.getRequirements(c)));
    cases.push(mutate('occupationalSet', card, (c) => S.CocOccupation.occupationalSet(c)));
    cases.push(mutate('occupationPoints', card, (c) => S.CocOccupation.occupationPoints(c)));
    cases.push(mutate('interestPoints', card, (c) => S.CocOccupation.interestPoints(c)));
    cases.push(mutate('pointsFull', card, (c) => S.CocOccupation.pointsFull(c)));
    cases.push(mutate('validatorsOccupationChoices', card, (c) => S.COC7.validators.occupationChoices(c, S.CocOccupation)));
  });

  // 点数用超 / 信用评级越界
  const skillRow = (o) => Object.assign({
    key: 'spot_hidden', id: 'spot_hidden', name: '侦查', sub: '', base: 25,
    growth: 0, occ: 0, int: 0, total: 25, custom: false, desc: '',
  }, o);
  const ptsCards = [
    mkCard({
      attrs: ATTR_SETS.high, occupationId: 'occ2',
      skills: [skillRow({ occ: 100, total: 125 }), skillRow({ key: 'listen', id: 'listen', int: 200, total: 220 })],
    }),
    mkCard({
      attrs: ATTR_SETS.high, occupationId: 'occ2', assets: { creditRating: 50 },
      skills: [skillRow({ occ: 0, total: 25 })],
    }),
    mkCard({ attrs: ATTR_SETS.high, occupationId: 'occ2', assets: { creditRating: 500 } }),
    mkCard({ attrs: ATTR_SETS.high, occupationId: 'occ2', assets: { creditRating: 30 } }),
    mkCard({ attrs: ATTR_SETS.mid, occupationId: 'occ1' }),
    mkCard({ attrs: ATTR_SETS.mid, occupationId: '' }),
  ];
  ptsCards.forEach((card) => {
    cases.push(mutate('validatorsSkillPoints', card, (c) => S.COC7.validators.skillPoints(c, S.CocOccupation)));
    cases.push(mutate('validatorsCreditRating', card, (c) => S.COC7.validators.creditRating(c, S.CocOccupation)));
    cases.push(mutate('validatorsSkillCap', card, (c) => S.COC7.validators.skillCap(c)));
  });

  // 「任选 X 项」去重校验
  const dupOcc = S.COC_OCCUPATIONS[1]; // 会计师：有 free 块
  const dupReqs = S.CocOccupation.parseSkillText(dupOcc.skillText);
  const freeId = (dupReqs.find((r) => r.type === 'free') || {}).id;
  const dupCards = freeId
    ? [
        mkCard({
          attrs: ATTR_SETS.high, occupationId: dupOcc.id,
          picks: { [freeId]: [{ skill: 'spot_hidden', sub: null, name: '侦查' }, { skill: 'spot_hidden', sub: null, name: '侦查' }] },
        }),
        mkCard({
          attrs: ATTR_SETS.high, occupationId: dupOcc.id,
          picks: { [freeId]: [{ skill: 'library', sub: null, name: '图书馆使用' }] },
        }),
        mkCard({
          attrs: ATTR_SETS.high, occupationId: dupOcc.id,
          picks: { [freeId]: [{ skill: 'fighting', sub: '斗殴', name: '斗殴' }] },
        }),
        mkCard({
          attrs: ATTR_SETS.high, occupationId: dupOcc.id,
          picks: { [freeId]: [{ skill: 'listening', sub: null, name: '聆听' }] },
        }),
      ]
    : [];
  dupCards.forEach((card) => {
    cases.push(mutate('validatorsOccupationChoices', card, (c) => S.COC7.validators.occupationChoices(c, S.CocOccupation)));
  });

  write('occupation.json', 'occupation', cases);
}

/* ============================================================
 * 4. 技能实例模型
 * ============================================================ */
function dumpSkillModel() {
  const cases = [];
  const card = mkCard({ attrs: ATTR_SETS.high });

  // 动态基础值
  const ids = [
    'spot_hidden', 'listen', 'library', 'dodge', 'language_own', 'credit', 'cthulhu',
    'fighting', 'firearms', 'science', 'art_craft', 'pilot', 'language_other',
    'accounting', 'psychology', 'stealth',
  ];
  const cardJ = J(card);
  ids.forEach((id) => {
    cases.push(pure('baseValue', [cardJ, id, ''], () => S.SkillModel.baseValue(card, id, '')));
  });
  ['斗殴', '射击', '手枪', '步枪', '生物学', '药学', '拉丁语', '驾驶（船）', '不存在'].forEach((sub) => {
    const gid = S.CocOccupation.subToGroup[sub] || 'fighting';
    cases.push(pure('baseValueSub', [cardJ, gid, sub], () => S.SkillModel.baseValue(card, gid, sub)));
    cases.push(pure('displayName', [gid, sub], () => S.SkillModel.displayName(gid, sub)));
  });
  ids.forEach((id) => {
    cases.push(pure('categoryOf', [id], () => S.SkillModel.categoryOf(id)));
    cases.push(pure('keyOf', [id, ''], () => S.SkillModel.keyOf(id, '')));
    cases.push(pure('keyOfSub', [id, '子'], () => S.SkillModel.keyOf(id, '子')));
  });

  // makeSkill / recompute / defaultSkillList
  ['spot_hidden', 'dodge', 'language_own', 'fighting'].forEach((id) => {
    cases.push(pure('makeSkill', [cardJ, id], () => S.SkillModel.makeSkill(card, id, '')));
  });
  const customDef = { name: '自定义', base: 15, desc: '自定' };
  cases.push(pure('makeSkillCustom', [cardJ, customDef], () => S.SkillModel.makeSkill(card, 'custom', '', customDef)));
  const recomputeIn = { base: 25, growth: 5, occ: 30, int: 10 };
  cases.push(pure('recompute', [recomputeIn], () => S.SkillModel.recompute(Object.assign({}, recomputeIn))));

  // syncSkills（数据库基础技能 + flat 组专攻 + 自定义技能保留）
  const syncCards = [
    mkCard({ attrs: ATTR_SETS.high }),
    mkCard({
      attrs: ATTR_SETS.high,
      skills: [
        { key: 'spot_hidden', id: 'spot_hidden', name: '侦查', sub: '', base: 25, growth: 5, occ: 20, int: 0, total: 50, custom: false, desc: '' },
        { key: 'fighting::斗殴', id: 'fighting', name: '格斗（斗殴）', sub: '斗殴', base: 25, growth: 0, occ: 30, int: 0, total: 55, custom: false, desc: '' },
        { key: 'custom::我的技能', id: 'custom', name: '我的技能', sub: '', base: 10, growth: 0, occ: 0, int: 5, total: 15, custom: true, desc: 'x' },
        { key: 'science::生物学', id: 'science', name: '科学（生物学）', sub: '生物学', base: 1, growth: 0, occ: 0, int: 20, total: 21, custom: false, desc: '' },
      ],
    }),
    mkCard({ attrs: ATTR_SETS.mid, skills: [] }),
  ];
  syncCards.forEach((c0) => {
    cases.push(mutate('syncSkills', c0, (c) => S.SkillModel.syncSkills(c)));
  });

  // 加点约束
  const occCard = mkCard({ attrs: ATTR_SETS.high, occupationId: 'occ2' });
  const addSkills = [
    { key: 'spot_hidden', id: 'spot_hidden', name: '侦查', sub: '', base: 25, growth: 0, occ: 0, int: 0, total: 25, custom: false, desc: '' },
    { key: 'cthulhu', id: 'cthulhu', name: '克苏鲁神话', sub: '', base: 0, growth: 0, occ: 0, int: 0, total: 0, custom: false, desc: '' },
    { key: 'credit', id: 'credit', name: '信用评级', sub: '', base: 0, growth: 0, occ: 0, int: 0, total: 0, custom: false, desc: '' },
    { key: 'dodge', id: 'dodge', name: '闪避', sub: '', base: 30, growth: 0, occ: 0, int: 0, total: 99, custom: false, desc: '' },
  ];
  const addTriples = [
    [0, 'occ', 5], [0, 'occ', 500], [0, 'int', 5], [0, 'int', 500],
    [0, 'occ', -50], [1, 'occ', 5], [1, 'growth', 5], [2, 'int', 5],
    [3, 'int', 5], [0, 'growth', 5],
  ];
  addTriples.forEach(([si, field, delta]) => {
    cases.push(
      mutate('canAdd', occCard, (c) => S.SkillModel.canAdd(c, addSkills[si], field, delta), { skill: addSkills[si], field, delta }),
    );
    cases.push(
      mutate('applyPoint', occCard, (c) => S.SkillModel.applyPoint(c, Object.assign({}, addSkills[si]), field, delta), { skill: addSkills[si], field, delta }),
    );
  });

  // stats / capOf / isOccSkill
  const statsCards = [
    mkCard({
      attrs: ATTR_SETS.high, occupationId: 'occ2',
      skills: [
        { key: 'spot_hidden', id: 'spot_hidden', name: '侦查', sub: '', base: 25, growth: 0, occ: 80, int: 0, total: 105, custom: false, desc: '' },
        { key: 'listen', id: 'listen', name: '聆听', sub: '', base: 20, growth: 0, occ: 0, int: 90, total: 110, custom: false, desc: '' },
      ],
    }),
    mkCard({ attrs: ATTR_SETS.mid, skillCapOcc: 70, skillCapInterest: 50, occupationId: 'occ2' }),
  ];
  const capOfSkill = { key: 'spot_hidden', id: 'spot_hidden', base: 25 };
  statsCards.forEach((c0) => {
    cases.push(mutate('stats', c0, (c) => S.SkillModel.stats(c)));
    cases.push(mutate('oscSkill', c0, (c) => S.SkillModel.isOccSkill(c, capOfSkill), { skill: capOfSkill }));
    cases.push(mutate('capOf', c0, (c) => S.SkillModel.capOf(c, capOfSkill), { skill: capOfSkill }));
  });

  write('skillmodel.json', 'skillmodel', cases);
}

/* ============================================================
 * 5. Engine（recalc / 校验清单）
 * ============================================================ */
function dumpEngine() {
  const cases = [];

  const recalcCards = [
    mkCard({ attrs: ATTR_SETS.mid }),
    mkCard({ attrs: ATTR_SETS.high, age: 70 }),
    mkCard({ attrs: ATTR_SETS.low, age: 15 }),
    mkCard({ attrs: ATTR_SETS.mixed, age: 45 }),
    mkCard({ attrs: ATTR_SETS.zero }),
    mkCard({}),
    mkCard({ attrs: ATTR_SETS.mid, age: 30, status: { currentHP: 3, currentMP: 1, currentSAN: 20 } }),
    mkCard({ attrs: ATTR_SETS.mid, age: 30, status: { currentHP: 0, currentMP: 0, currentSAN: 0, _inited: true } }),
    mkCard({ attrs: ATTR_SETS.mid, age: 30, sanLoss: 10 }),
    mkCard({ attrs: ATTR_SETS.mid, age: 30, sanLoss: 200 }),
    mkCard({ attrs: ATTR_SETS.mid, age: 30, skills: [{ key: 'cthulhu', id: 'cthulhu', name: '克苏鲁神话', sub: '', base: 0, growth: 0, occ: 0, int: 0, total: 12, custom: false, desc: '' }] }),
    mkCard({
      attrs: ATTR_SETS.mid, age: 30,
      skills: [
        { key: 'dodge', id: 'dodge', name: '闪避', sub: '', base: 25, growth: 0, occ: 0, int: 0, total: 25, custom: false, desc: '' },
        { key: 'language_own', id: 'language_own', name: '母语', sub: '', base: 50, growth: 0, occ: 0, int: 0, total: 50, custom: false, desc: '' },
      ],
    }),
    // 教育进步检定：有效基准 → 不变
    mkCard({ attrs: ATTR_SETS.mid, age: 45, eduProgress: { base: 50, baseEdu: 50, done: 1, log: [{ before: 50, roll: 80, gain: 6 }], bonus: 6 } }),
    // 教育进步检定：EDU 变了 → 作废
    mkCard({ attrs: ATTR_SETS.mid, age: 45, eduProgress: { base: 50, baseEdu: 40, done: 1, log: [{ before: 40, roll: 80, gain: 6 }], bonus: 6 } }),
    // 没记基准但首条 before 与当前 EDU 一致 → 补记基准，不作废
    mkCard({ attrs: ATTR_SETS.mid, age: 45, eduProgress: { base: null, done: 1, log: [{ before: 50, roll: 80, gain: 6 }], bonus: 6 } }),
    // 没记基准且首条对不上 → 按过期处理
    mkCard({ attrs: ATTR_SETS.mid, age: 45, eduProgress: { base: null, done: 1, log: [{ before: 30, roll: 80, gain: 6 }], bonus: 6 } }),
  ];
  recalcCards.forEach((c0) => {
    cases.push(mutate('recalc', c0, (c) => S.Engine.recalc(c)));
  });

  // attrsReady / attrSum / attrSumEff / validate / checkList
  const miscCards = [
    mkCard({ attrs: ATTR_SETS.mid }),
    mkCard({}),
    mkCard({ attrs: Object.assign({}, ATTR_SETS.mid, { luck: '' }) }),
    mkCard({ name: '张三', player: '李四', age: 30, attrs: ATTR_SETS.high, occupationId: 'occ2', assets: { creditRating: 40 } }),
    mkCard({ name: '张三', player: '李四', age: 30, attrs: ATTR_SETS.mid, occupationId: 'occ2' }),
    mkCard({ name: '', player: '', age: 0 }),
  ];
  miscCards.forEach((c0) => {
    cases.push(mutate('attrsReady', c0, (c) => S.Engine.attrsReady(c)));
    cases.push(mutate('attrSum', c0, (c) => S.Engine.attrSum(c)));
    cases.push(mutate('attrSumNoLuck', c0, (c) => S.Engine.attrSum(c, false)));
    cases.push(mutate('attrSumEff', c0, (c) => S.Engine.attrSumEff(c)));
    cases.push(mutate('validate', c0, (c) => S.Engine.validate(c)));
    cases.push(mutate('checkList', c0, (c) => S.Engine.checkList(c)));
    cases.push(mutate('effAttrs', c0, (c) => S.Engine.effAttrs(c)));
    cases.push(mutate('ageAdjustOf', c0, (c) => S.Engine.ageAdjustOf(c)));
    cases.push(mutate('clamp', c0, (c) => S.Engine.clamp(c.attributes.str, 0, 99)));
  });

  write('engine.json', 'engine', cases);
}

/* ============================================================
 * 6. 疯狂
 * ============================================================ */
function dumpMadness() {
  const cases = [];

  for (let i = 0; i < 24; i++) {
    cases.push(pure('rollTable', [], () => S.CocMadness.rollTable()));
    cases.push(pure('rollSummary', [], () => S.CocMadness.rollSummary()));
  }
  ['any', 'phobia', 'mania', 'bout', 'unknown', ''].forEach((t) => {
    [true, false].forEach((perm) => {
      cases.push(pure('roll', [t, perm], () => S.CocMadness.roll(t, perm)));
    });
  });
  [null, '', '（来自人设）'].forEach((tail) => {
    cases.push(pure('backgroundText', [tail], () => S.CocMadness.backgroundText(tail)));
  });

  // lookup / 池子
  const names = S.COC_MADNESS.phobias.slice(0, 5).map((x) => x.name)
    .concat(S.COC_MADNESS.manias.slice(0, 5).map((x) => x.name))
    .concat(['不存在的症状', '幽闭恐惧症', '']);
  names.forEach((n) => {
    cases.push(pure('lookup', [n], () => S.CocMadness.lookup(n)));
    cases.push(pure('lookupPhobia', [n, 'phobia'], () => S.CocMadness.lookup(n, 'phobia')));
    cases.push(pure('lookupMania', [n, 'mania'], () => S.CocMadness.lookup(n, 'mania')));
  });
  cases.push(pure('poolSize', [], () => S.CocMadness.poolSize('phobia')));
  cases.push(pure('poolSizeMania', [], () => S.CocMadness.poolSize('mania')));
  cases.push(pure('labelOf', [], () => ['phobia', 'mania', 'bout', 'x'].map((t) => S.CocMadness.labelOf(t))));
  cases.push(pure('size', [], () => S.CocMadness.size));
  cases.push(pure('phobias', [], () => S.CocMadness.phobias().slice(0, 3)));
  cases.push(pure('manias', [], () => S.CocMadness.manias().slice(0, 3)));

  // make（含 rounds 兜底）
  const srcPhobia = S.COC_MADNESS.phobias[3];
  const srcMania = S.COC_MADNESS.manias[7];
  [
    ['phobia', srcPhobia, true, undefined],
    ['mania', srcMania, true, undefined],
    ['bout', srcPhobia, false, 5],
    ['bout', srcPhobia, false, 0],
    ['phobia', null, false, undefined],
  ].forEach(([t, src, perm, rounds]) => {
    cases.push(pure('make', [t, src, perm, rounds], () => S.CocMadness.make(t, src, perm, rounds)));
  });

  // 背景文本解析
  const bgTexts = [
    '【恐惧症】幽闭恐惧症：怕黑',
    '【狂躁症】' + S.COC_MADNESS.manias[0].name + '：描述',
    S.COC_MADNESS.phobias[0].name + '：直白写法',
    '自由文本没有症状\n第二行',
    '',
    '【恐惧症】不存在的症状：x\n【狂躁症】' + S.COC_MADNESS.manias[1].name,
    '【恐惧症】' + S.COC_MADNESS.phobias[1].name + '\n【恐惧症】' + S.COC_MADNESS.phobias[1].name,
  ];
  bgTexts.forEach((t) => {
    cases.push(pure('parseBackground', [t], () => S.CocMadness.parseBackground(t)));
  });

  // 数组操作
  const mad = (patch) => Object.assign({
    id: 'm1', type: 'phobia', name: '幽闭恐惧症', en: 'Claustrophobia',
    desc: 'x', rounds: 3, permanent: false, at: 1700000000000,
  }, patch);
  const madCards = [
    mkCard({ madness: [] }),
    mkCard({ madness: [mad({}), mad({ id: 'm2', rounds: 1 }), mad({ id: 'm3', permanent: true })] }),
    mkCard({ madness: [mad({ id: 'm4', rounds: null })] }),
  ];
  const bgCard = mkCard({ madness: [], background: { phobias: '【恐惧症】幽闭恐惧症：怕黑' } });
  cases.push(mutate('fromBackground', bgCard, (c) => S.CocMadness.fromBackground(c)));
  cases.push(mutate('fromBackgroundIdem', bgCard, (c) => {
    // 连跑两遍：第二遍不应再新增（幂等）
    S.CocMadness.fromBackground(c);
    return S.CocMadness.fromBackground(c);
  }));
  const addEntry = { id: 'mn', type: 'mania', name: '纵火狂', rounds: 2, permanent: false };
  madCards.forEach((c0, i) => {
    cases.push(mutate('advance', c0, (c) => S.CocMadness.advance(c, i + 1), { n: i + 1 }));
    cases.push(mutate('summary', c0, (c) => S.CocMadness.summary(c)));
    cases.push(mutate('fading', c0, (c) => S.CocMadness.fading(c, 2), { within: 2 }));
    cases.push(mutate('hasName', c0, (c) => S.CocMadness.hasName(c, 'phobia', '幽闭恐惧症'), { type: 'phobia', name: '幽闭恐惧症' }));
    cases.push(mutate('add', c0, (c) => S.CocMadness.add(c, Object.assign({}, addEntry)), { entry: addEntry }));
    cases.push(mutate('remove', c0, (c) => S.CocMadness.remove(c, 'm2'), { id: 'm2' }));
  });
  const pickedIn = [
    { name: '幽闭恐惧症', kind: '恐惧症' },
    { name: S.COC_MADNESS.manias[2].name, kind: '狂躁症' },
    { name: '失忆', kind: '疯狂发作', sum: true },
    { name: '', kind: '恐惧症' },
  ];
  cases.push(mutate('fromPicked', mkCard({}), (c) => S.CocMadness.fromPicked(c, pickedIn), { picked: pickedIn }));
  cases.push(mutate('clear', mkCard({ madness: [mad({})] }), (c) => {
    S.CocMadness.clear(c);
    return S.CocMadness.list(c);
  }));

  write('madness.json', 'madness', cases);
}

/* ============================================================
 * 7. 迁移 normalize（含幂等性在 Dart 侧断言）
 * ============================================================ */
function dumpNormalize() {
  const cases = [];

  const legacy = [
    // 完全空对象（最极端的老数据）
    {},
    // 只有名字
    { characterName: '老卡', playerName: '老王' },
    // 旧 skillCap 未拆分
    { id: 'x1', skillCap: 80 },
    // skillCap 已拆 → 不覆盖
    { id: 'x2', skillCap: 80, skillCapOcc: 90, skillCapInterest: 70 },
    // mental 单选字符串
    { id: 'x3', status: { mental: '临时疯狂' } },
    // mental 空
    { id: 'x4', status: { mental: '' } },
    // mental 已永久疯狂（互斥）
    { id: 'x5', status: { mental: ['正常', '永久疯狂', '临时疯狂'] } },
    // mental 数组含空项
    { id: 'x6', status: { mental: ['临时疯狂', null, '', '疯狂症状'] } },
    // body 濒死
    { id: 'x7', status: { body: '濒死', currentHP: 0, maxHP: 12 } },
    // body 昏迷（按 HP 归位）
    { id: 'x8', status: { body: '昏迷', currentHP: 12, maxHP: 12 } },
    { id: 'x9', status: { body: '昏迷', currentHP: 6, maxHP: 12 } },
    { id: 'x10', status: { body: '昏迷', currentHP: 5, maxHP: 12 } },
    // dying / unconscious 脏数据（非布尔）
    { id: 'x11', status: { dying: 'yes', unconscious: 1 } },
    // 教育进步只有 log
    { id: 'x12', eduProgress: { log: [{ before: 50, gain: 6 }, { before: 56, gain: 3 }] } },
    // 教育进步 bonus 显式 null
    { id: 'x13', eduProgress: { log: [], bonus: null } },
    // 天命异常
    { id: 'x14', fate: { n: 99, rolled: true, options: [], picked: 3 } },
    { id: 'x15', fate: { n: 'abc', options: [{}, {}, {}], picked: 2, rolled: true } },
    // 背景症状文本 → 结构化
    { id: 'x16', background: { phobias: '【恐惧症】幽闭恐惧症：怕黑' } },
    // 背景症状 + 已有同名（幂等）
    {
      id: 'x17',
      background: { phobias: '【恐惧症】幽闭恐惧症：怕黑' },
      madness: [{ id: 'm0', type: 'phobia', name: '幽闭恐惧症', permanent: true, bg: true, rounds: 0, at: 1 }],
    },
    // 已保存过的卡（状态锁定）
    { id: 'x18', status: { currentHP: 7, currentSAN: 40 }, derivedStats: { maxHP: 12 } },
    // 数组字段被写成非数组
    { id: 'x19', skills: 'oops', weapons: null, items: 3 },
    // 基础对象字段被写成非对象
    { id: 'x20', basicInfo: null, attributes: 'x', status: 5, assets: [], background: 0, mythos: null },
    // 疯狂症状派生：有非永久症状 + mental 有「正常」
    { id: 'x21', status: { mental: ['正常'] }, madness: [{ id: 'm9', type: 'phobia', name: 'x', permanent: false, rounds: 2, at: 1 }] },
    // 疯狂症状派生：有永久症状 + mental 有「正常」
    {
      id: 'x22',
      status: { mental: ['正常'] },
      madness: [{ id: 'm8', type: 'mania', name: 'y', permanent: true, rounds: 0, at: 1 }],
    },
    // 老卡整体：字符串属性 + 旧字段
    {
      id: 'x23', ruleSystemId: 'coc7', characterName: '旧', playerName: '旧',
      age: '52', basicInfo: { age: '52', era: '' },
      attributes: { str: '55', con: '60', siz: '65', dex: '50', app: '45', int: '70', pow: '60', edu: '75', luck: '40' },
      skillCap: 75,
      status: { currentHP: 12, maxHP: 12, currentMP: 12, maxMP: 12, currentSAN: 60, maxSAN: 60, body: '濒死', mental: '临时疯狂' },
      background: { phobias: '【恐惧症】幽闭恐惧症：怕黑\n【狂躁症】' + S.COC_MADNESS.manias[0].name + '：描述' },
    },
  ];

  legacy.forEach((raw) => {
    const seed = nextSeed();
    S.__setSeed(seed);
    const c = JSON.parse(JSON.stringify(raw));
    let out, error = null;
    try {
      out = S.Store.normalize(c);
    } catch (e) {
      error = String(e && e.message ? e.message : e);
    }
    cases.push({
      name: `normalize#${seq}`,
      fn: 'normalize',
      args: { card: J(raw) },
      expect: error ? null : J(out),
      randUsed: S.__randUsed(),
      seed,
      error,
    });
  });

  write('normalize.json', 'normalize', cases);
}

/* ============================================================ */
dumpDice();
dumpRules();
dumpOccupation();
dumpSkillModel();
dumpEngine();
dumpMadness();
dumpNormalize();
