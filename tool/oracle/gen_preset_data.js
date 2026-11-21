/* ============================================================
 * tool/oracle/gen_preset_data.js — 预设卡「人设底座」数据 JS → Dart const
 *
 * 用法： node tool/oracle/gen_preset_data.js
 * 输出： lib/domain/data/personas.dart
 *       lib/domain/data/easter_egg.dart
 *
 * 为什么单独一个脚本（不并进 gen_data.js）：
 *   gen_data.js 走的是 `createSandbox()`（P0 口径，只加载规则层）。
 *   这里的数据挂在 personas.js / easter-egg.js 这两个模块**内部**，
 *   必须先 `createSandbox({ withPreset: true })` 才能读到，
 *   硬并进去会改变 P0 的加载顺序。工具脚本的少量重复比「改坏 P0」划算。
 *
 * 数据搬运原则与 gen_data.js 一致：键名、值、嵌套形状逐字保留，
 * 不做任何语义清洗 —— 这些池子是查表与抽样的输入，改了就等于换了一套人设。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const { createSandbox, SRC_ROOT } = require('./load');

const OUT_DIR = path.resolve(__dirname, '../../lib/domain/data');

/** Dart 字符串字面量（单引号；转义 \ ' $ 与不可见字符） */
function dartStr(s) {
  let out = "'";
  for (const ch of s) {
    switch (ch) {
      case '\\': out += '\\\\'; break;
      case "'": out += "\\'"; break;
      case '$': out += '\\$'; break;
      case '\n': out += '\\n'; break;
      case '\r': out += '\\r'; break;
      case '\t': out += '\\t'; break;
      default: {
        const code = ch.codePointAt(0);
        if (code < 0x20) {
          out += '\\u{' + code.toString(16) + '}';
        } else {
          out += ch;
        }
      }
    }
  }
  return out + "'";
}

function dartVal(v, indent) {
  const pad = '  '.repeat(indent);
  const padIn = '  '.repeat(indent + 1);
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'string') return dartStr(v);
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) throw new Error('非有限数: ' + v);
    return String(v);
  }
  if (typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) {
    if (v.length === 0) return '<Object?>[]';
    const lines = v.map((x) => padIn + dartVal(x, indent + 1) + ',');
    return '[\n' + lines.join('\n') + '\n' + pad + ']';
  }
  if (typeof v === 'object') {
    const keys = Object.keys(v);
    if (keys.length === 0) return '<String, Object?>{}';
    const lines = keys.map((k) => padIn + dartStr(k) + ': ' + dartVal(v[k], indent + 1) + ',');
    return '<String, Object?>{\n' + lines.join('\n') + '\n' + pad + '}';
  }
  throw new Error('不支持的类型: ' + typeof v);
}

const HEADER = [
  '// GENERATED FILE — 请勿手改。',
  '// 由 tool/oracle/gen_preset_data.js 从原 Web 版 JS 数据表生成；',
  '// 键名与值逐字保留，仅供规则层（personas / preset_gen）读取。',
  '// ignore_for_file: prefer_single_quotes',
  '',
];

function writeTable(file, consts) {
  const chunks = [HEADER.join('\n')];
  for (const c of consts) {
    chunks.push('/// ' + c.doc);
    chunks.push('const ' + c.type + ' ' + c.name + ' = ' + dartVal(c.value, 0) + ';');
    chunks.push('');
  }
  const text = chunks.join('\n');
  fs.writeFileSync(path.join(OUT_DIR, file), text, 'utf8');
  console.log(`${file.padEnd(20)} ${(Buffer.byteLength(text) / 1024).toFixed(1)} KB`);
}

function main() {
  const { sandbox: S } = createSandbox({ withPreset: true });
  const PER = S.CocPersonas;
  const EGG = S.CocEasterEgg;
  if (!PER) throw new Error('沙箱里没有 CocPersonas（personas.js 未加载）');
  if (!EGG) throw new Error('沙箱里没有 CocEasterEgg（easter-egg.js 未加载）');
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const pools = PER.pools;
  writeTable('personas.dart', [
    {
      name: 'personaSettings',
      type: 'List<Map<String, Object?>>',
      doc: '`personas.js#SETTINGS` —— 世界设定包，' + PER.list.length + ' 个世界。',
      value: PER.list,
    },
    {
      name: 'personaNamePools',
      type: 'Map<String, Object?>',
      doc: '`personas.js#NAMES` —— 姓名池，按世界设定的 nameKey 取用。',
      value: PER.namePools,
    },
    {
      name: 'personaBeliefs',
      type: 'List<Object?>',
      doc: '`personas.js#BELIEFS` —— 信念池。',
      value: pools.beliefs,
    },
    {
      name: 'personaTreasure',
      type: 'List<Object?>',
      doc: '`personas.js#TREASURE` —— 宝贵之物池。',
      value: pools.treasure,
    },
    {
      name: 'personaTraits',
      type: 'List<Object?>',
      doc: '`personas.js#TRAITS` —— 个人特质池。',
      value: pools.traits,
    },
    {
      name: 'personaWounds',
      type: 'List<Object?>',
      doc: '`personas.js#WOUNDS` —— 创伤池。',
      value: pools.wounds,
    },
    {
      name: 'personaLookBody',
      type: 'List<Object?>',
      doc: '`personas.js#LOOK_BODY` —— 身形描述池。',
      value: pools.lookBody,
    },
    {
      name: 'personaLookDress',
      type: 'List<Object?>',
      doc: '`personas.js#LOOK_DRESS` —— 衣着描述池。',
      value: pools.lookDress,
    },
    {
      name: 'personaLookFace',
      type: 'List<Object?>',
      doc: '`personas.js#LOOK_FACE` —— 神态描述池。',
      value: pools.lookFace,
    },
    {
      name: 'personaPeopleRel',
      type: 'List<Object?>',
      doc: '`personas.js#PEOPLE_REL` —— 重要之人：关系。',
      value: pools.peopleRel,
    },
    {
      name: 'personaPeopleMid',
      type: 'List<Object?>',
      doc: '`personas.js#PEOPLE_MID` —— 重要之人：经过。',
      value: pools.peopleMid,
    },
    {
      name: 'personaPeopleEnd',
      type: 'List<Object?>',
      doc: '`personas.js#PEOPLE_END` —— 重要之人：现状。',
      value: pools.peopleEnd,
    },
    {
      name: 'personaPlaceTpl',
      type: 'List<Object?>',
      doc: '`personas.js#PLACE_TPL` —— 意义非凡之地模板（含 {city} / {site}）。',
      value: pools.placeTpl,
    },
    {
      name: 'personaHistoryTpl',
      type: 'List<Object?>',
      doc: '`personas.js#HISTORY_TPL` —— 入行经历模板（含 {occ}）。',
      value: pools.historyTpl,
    },
    {
      name: 'personaEntryTail',
      type: 'List<Object?>',
      doc: '`personas.js#ENTRY_TAIL` —— 入行经历尾句（含 {treasure}）。',
      value: pools.entryTail,
    },
    {
      name: 'personaPhobiaLead',
      type: 'List<Object?>',
      doc: '`personas.js#PHOBIA_LEAD` —— 心理症状引子池。',
      value: pools.phobiaLead,
    },
  ]);

  writeTable('easter_egg.dart', [
    {
      name: 'eggCelebrities',
      type: 'List<Map<String, Object?>>',
      doc: '`easter-egg.js#CELEBRITIES` —— 名人彩蛋，' + EGG.celebrities.length + ' 位。',
      value: EGG.celebrities,
    },
    {
      name: 'eggFriends',
      type: 'List<Map<String, Object?>>',
      doc: '`easter-egg.js#FRIENDS` —— 跑团成员彩蛋，' + EGG.friends.length + ' 位。',
      value: EGG.friends,
    },
  ]);

  console.log('设定数:', PER.list.length,
    '/ 名人:', EGG.celebrities.length,
    '/ 朋友:', EGG.friends.length,
    '/ 批级概率:', JSON.stringify(EGG.rates));
  console.log('源目录:', SRC_ROOT);
}

main();
