/* ============================================================
 * tool/oracle/load_p4_room.js — 把旧版「房间层」原样加载进 Node 沙箱
 *
 * 为什么单独一个文件：
 *   load.js 的加载顺序是 P0 的 fixture 约定，**一行都不能动**（改了会让既有
 *   1621 例的随机序列错位）。房间层（room-rules / room-model）不属于 P0，
 *   所以在 createSandbox() 拿到的**同一个 ctx** 里按顺序追加加载：
 *     core/room-rules.js → core/room-model.js
 *   room-model 的 Host 构造会读 `global.CocRules` / `global.CocMadness`，
 *   因此 room-rules 必须先加载（CocMadness 已由 load.js 的 CORE_FILES 带进来）。
 *
 * ⚠️ 原则不变：**绝不修改原码**；所有可复现改造都在沙箱侧。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const { createSandbox, SRC_ROOT } = require('./load');

/** 追加加载顺序（不能乱：room-model 依赖 room-rules 的全局） */
const ROOM_FILES = ['core/room-rules.js', 'core/room-model.js'];

/**
 * 建立带房间层的沙箱。每次调用都是全新上下文。
 * @returns {{ctx: object, sandbox: object, S: object,
 *            CocRules: object, RoomModel: object, CocMadness: object}}
 */
function createRoomSandbox() {
  const { ctx, sandbox } = createSandbox();
  for (const rel of ROOM_FILES) {
    const file = path.join(SRC_ROOT, rel);
    const code = fs.readFileSync(file, 'utf8');
    try {
      vm.runInContext(code, ctx, { filename: rel });
    } catch (e) {
      throw new Error(`加载 ${rel} 失败: ${e.message}`);
    }
  }
  return {
    ctx,
    sandbox,
    S: sandbox,
    CocRules: sandbox.CocRules,
    RoomModel: sandbox.RoomModel,
    CocMadness: sandbox.CocMadness,
  };
}

module.exports = { createRoomSandbox, ROOM_FILES };
