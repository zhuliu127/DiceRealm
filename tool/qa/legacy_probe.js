/* ============================================================
 * tool/qa/legacy_probe.js — QA 独立复核用的旧版探针
 *
 * 用途（只读旧版原码，不修改它）：
 *   1) dump 旧版 `Store.newCharacter()` 的**完整键树**（含嵌套、含数组元素键）
 *   2) dump 旧版 `Store.exportCharacter()` 的**逐字输出**，用于与 Dart 侧比对
 *   3) dump 旧版武器「使用技能」清单（ui/steps-c.js 的那套逻辑）
 *   4) dump 旧版 `Engine.checkList()` 的 (label, step) 全集
 *
 * 用法: node tool/qa/legacy_probe.js [tree|export|combat|checks|all]
 * ============================================================ */
'use strict';

const path = require('path');
const { createSandbox } = require('../oracle/load');

/* ---- 键树：把对象/数组摊平成 "路径 : 类型" 的有序列表 ---- */
function typeName(v) {
  if (v === null) return 'null';
  if (v === undefined) return 'undefined';
  if (Array.isArray(v)) return 'array';
  return typeof v;
}

function keyTree(v, prefix, out) {
  const t = typeName(v);
  out.push(`${prefix} : ${t}`);
  if (Array.isArray(v)) {
    const seen = new Set();
    for (const item of v) {
      const it = typeName(item);
      if (seen.has(it)) continue;
      seen.add(it);
      keyTree(item, `${prefix}[]`, out);
    }
    return out;
  }
  if (v && typeof v === 'object') {
    for (const k of Object.keys(v)) {
      keyTree(v[k], prefix ? `${prefix}.${k}` : k, out);
    }
  }
  return out;
}

function main() {
  const what = process.argv[2] || 'all';
  const { ctx } = createSandbox();

  if (what === 'tree' || what === 'all') {
    const c = ctx.Store.newCharacter();
    const out = keyTree(c, '', []).sort();
    console.log('### NEW_CHARACTER_TREE');
    console.log(out.join('\n'));
    console.log('### END');
  }

  if (what === 'export' || what === 'all') {
    /* 造一张「有内容」的卡：属性齐备 + 技能实例 + 武器 / 物品 / 历史 / 法术，
       然后 normalize + syncSkills + recalc，再用**旧版自己的** exportCharacter 输出。 */
    const c = ctx.Store.newCharacter();
    c.characterName = '探针·张三';
    c.playerName = 'QA';
    c.basicInfo.age = 30;
    c.attributes = { str: 60, con: 55, siz: 65, dex: 50, app: 45, int: 70, pow: 60, edu: 75, luck: 40 };
    c.occupationId = 'antiquarian';
    c.history.push({ id: 'h1', title: '第一次冒险', sanChange: '-1D6', hpChange: -2, at: 1700000000000 });
    c.history.push({ id: 'h2', title: '第二次冒险', sanChange: '-5', hpChange: 0, at: 1700000000001 });
    c.mythos.skill = 7;
    c.mythos.spells.push({ name: 'Contact Deity', cost: '1D4', note: '不可描述' });
    c.mythos.entries.push({ title: '纳克特抄本', at: 1700000000002 });
    c.weapons.push({ name: '匕首', skill: '斗殴', damage: '1D4+DB', range: '接触', pierce: '×', perRound: '1', ammo: '', malfunction: '', era: '现代', price: '10', category: '近战', note: '', qty: 1 });
    c.items.push({ name: '手电筒', quantity: 2, description: '' });
    c.companions.push({ name: '老猎犬', note: '朋友的狗' });
    const norm = ctx.Store.normalize(c);
    if (ctx.SkillModel && ctx.SkillModel.syncSkills) ctx.SkillModel.syncSkills(norm);
    ctx.Engine.recalc(norm);
    ctx.Store.getState().characters[norm.id] = norm;
    console.log('### EXPORT_TEXT');
    console.log(ctx.Store.exportCharacter(norm.id));
    console.log('### END');
  }

  if (what === 'combat' || what === 'all') {
    /* 复刻 ui/steps-c.js#weaponSkillOptions 的清单构造（不依赖 DOM） */
    const names = [];
    const seen = {};
    const add = (n) => {
      if (!n || seen[n]) return;
      seen[n] = true;
      names.push(n);
    };
    (ctx.COC_SKILLS || []).forEach((def) => {
      if (def.id === 'fighting' || def.id === 'firearms') {
        (def.subskills || []).forEach((sub) => add(sub.name));
      }
    });
    ['投掷', '炮术', '爆破'].forEach(add);
    console.log('### COMBAT_SKILLS');
    console.log(JSON.stringify(names, null, 2));
    console.log('count=' + names.length);
    console.log('### END');
  }

  if (what === 'checks' || what === 'all') {
    const c = ctx.Store.newCharacter();
    ctx.Store.normalize(c);
    ctx.Engine.recalc(c);
    const rows = ctx.Engine.checkList(c).map((r) => ({ label: r.label, step: r.step, ok: r.ok }));
    console.log('### CHECK_LIST');
    console.log(JSON.stringify(rows, null, 2));
    console.log('### END');
  }
}

main();
