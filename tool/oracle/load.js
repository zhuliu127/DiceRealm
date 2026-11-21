/* ============================================================
 * tool/oracle/load.js — 把原 Web 版的规则层原样加载进 Node 沙箱
 *
 * 目的：把老 JS 当成**预言机（oracle）**，用它算出期望值，
 *       存成 JSON fixture，再由 Dart 测试逐字段比对。
 *
 * ⚠️ 原则：**绝不修改原码**（coc7th-card-app/web/js 只读）。
 *   所有为了可复现做的改造都发生在沙箱这一侧：
 *     · Math.random → 可复位的 LCG（seed 注入）
 *     · Date.now    → 固定时间戳（madness 的 at / uid、store 的 uid）
 *     · window / localStorage → 极简替身
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

/** 原 Web 版 js 根目录（相对 dice-realm/tool/oracle） */
const SRC_ROOT = path.resolve(__dirname, '../../../coc7th-card-app/web/js');

/* 加载顺序 = index.html 里的 <script> 顺序（见 _port_audit.md §A.5） */
const DATA_FILES = [
  'data/skills.js',
  'data/occupations.js',
  'data/weapons.js',
  'data/armors.js',
  'data/vehicles.js',
  'data/spells.js',
  'data/madness.js',
  'data/assets.js',
];

const CORE_FILES = [
  'core/dice.js',
  'core/rules-coc7.js',
  'core/occupation.js',
  'core/skillmodel.js',
  'core/engine.js',
  'core/madness.js',
  'core/store.js',
];

/**
 * P3 追加层：随机预设卡生成链（preset.js 的直接依赖）。
 *
 * 顺序不能乱：
 *   personas.js   世界设定 / 姓名池 / 通用文本池（preset 的「人设底座」）
 *   avatar.js     自动头像（preset.build() 最后一步会 ensure 一张）
 *   easter-egg.js 彩蛋抽签（preset.generate() 的批级彩蛋计划）
 *   ai.js         **只为了 applyAttrCap / caps** —— 房规数值上限的权威实现，
 *                 preset.js 通过 global.AIGen 复用压缩算法。ai.js 是纯定义，
 *                 加载时不发请求（fetch 只在 chat() 被调用时才用）。
 *   preset.js     被验证的对象
 *
 * ⚠️ 这几个文件只在 `createSandbox({ withPreset: true })` 时加载 ——
 *    P0 的 fixture 是这批文件不存在时 dump 出来的，加载顺序保持原样才能
 *    保证既有 1621 例的期望值一字不变。
 */
const PRESET_FILES = [
  'core/personas.js',
  'core/avatar.js',
  'core/easter-egg.js',
  'core/ai.js',
  'core/preset.js',
];

/**
 * 建立一个「干净」的沙箱，并把规则层全部加载进来。
 * 每次调用都是全新上下文 —— 模块内的 `var cache = {}`（occupation.js 的
 * getRequirements 缓存）不会跨用例串味。
 *
 * @param {{withPreset?: boolean}} [opts] 是否加载 P3 的预设卡生成链
 */
function createSandbox(opts) {
  const withPreset = !!(opts && opts.withPreset);
  const sandbox = {
    console: { log() {}, warn() {}, error() {} },
    setTimeout: () => 0,
    clearTimeout: () => {},
  };
  const ctx = vm.createContext(sandbox);
  vm.runInContext(
    `(function(){
       var seed = 1, used = 0;
       Math.random = function(){
         /* Numerical Recipes LCG，32 位截断 —— 只要 seed 一样，序列就一样 */
         used++;
         seed = (seed * 1664525 + 1013904223) >>> 0;
         return seed / 4294967296;
       };
       Date.now = function(){ return 1700000000000; };
       this.__setSeed = function(n){ seed = (n >>> 0); used = 0; };
       this.__randUsed = function(){ return used; };
       this.__now = function(){ return 1700000000000; };
     }).call(this);`,
    ctx,
  );

  // window 就是沙箱自身：原码统一走 `(function(global){...})(window)`
  sandbox.window = sandbox;
  // localStorage 替身：内存实现（store.js 只在 load 时 read 一次，读写都包了 try/catch）
  const store = new Map();
  sandbox.localStorage = {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => { store.set(k, String(v)); },
    removeItem: (k) => { store.delete(k); },
  };

  for (const rel of [...DATA_FILES, ...CORE_FILES]) {
    const file = path.join(SRC_ROOT, rel);
    const code = fs.readFileSync(file, 'utf8');
    try {
      vm.runInContext(code, ctx, { filename: rel });
    } catch (e) {
      throw new Error(`加载 ${rel} 失败: ${e.message}`);
    }
  }
  if (withPreset) {
    for (const rel of PRESET_FILES) {
      const file = path.join(SRC_ROOT, rel);
      const code = fs.readFileSync(file, 'utf8');
      try {
        vm.runInContext(code, ctx, { filename: rel });
      } catch (e) {
        throw new Error(`加载 ${rel} 失败: ${e.message}`);
      }
    }
  }
  return { ctx, sandbox };
}

module.exports = { createSandbox, SRC_ROOT, DATA_FILES, CORE_FILES, PRESET_FILES };
