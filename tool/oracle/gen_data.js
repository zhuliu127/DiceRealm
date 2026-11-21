/* ============================================================
 * tool/oracle/gen_data.js — 数据表 JS → Dart const
 *
 * 用法： node tool/oracle/gen_data.js
 * 输出： lib/domain/data/<table>.dart
 *
 * 键名、值、类型（int / String / bool / null / 嵌套数组）逐字保留，
 * 不做任何清洗 —— 数据里的脏值与怪写法是后续规则解析的输入，
 * 改了就等于换了一套输入。唯一处理是：结构分层（按表拆文件）。
 * ============================================================ */
'use strict';

const fs = require('fs');
const path = require('path');
const { createSandbox, SRC_ROOT } = require('./load');

const OUT_DIR = path.resolve(__dirname, '../../lib/domain/data');

/** 表定义：JS 全局名 → (Dart 标识符, 文件, 顶层类型名) */
const TABLES = [
  { js: 'COC_SKILLS', dart: 'cocSkills', file: 'skills.dart', kind: 'list', src: 'data/skills.js' },
  { js: 'COC_OCCUPATIONS', dart: 'cocOccupations', file: 'occupations.dart', kind: 'list', src: 'data/occupations.js' },
  { js: 'COC_WEAPONS', dart: 'cocWeapons', file: 'weapons.dart', kind: 'list', src: 'data/weapons.js' },
  { js: 'COC_ARMORS', dart: 'cocArmors', file: 'armors.dart', kind: 'list', src: 'data/armors.js' },
  { js: 'COC_VEHICLES', dart: 'cocVehicles', file: 'vehicles.dart', kind: 'list', src: 'data/vehicles.js' },
  { js: 'COC_SPELLS', dart: 'cocSpells', file: 'spells.dart', kind: 'list', src: 'data/spells.js' },
  { js: 'COC_MADNESS', dart: 'cocMadnessTable', file: 'madness.dart', kind: 'map', src: 'data/madness.js' },
  { js: 'COC_ASSETS', dart: 'cocAssets', file: 'assets.dart', kind: 'map', src: 'data/assets.js' },
];

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
    return Number.isInteger(v) ? String(v) : String(v);
  }
  if (typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) {
    if (v.length === 0) return '<Object?>[]';
    const lines = v.map((x) => padIn + dartVal(x, indent + 1) + ',');
    // 不写显式元素类型：顶层由声明类型（List<Map<String, Object?>>）做上下文推断，
    // 嵌套列表按元素推断 —— 这样既能 const，也不会在赋值处报 List<Object?> 不匹配。
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

function main() {
  const { sandbox } = createSandbox();
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const counts = [];
  for (const t of TABLES) {
    const val = sandbox[t.js];
    if (val === undefined) throw new Error('沙箱里没有 ' + t.js);
    const dartType = t.kind === 'list' ? 'List<Map<String, Object?>>' : 'Map<String, Object?>';
    const header = [
      '// GENERATED FILE — 请勿手改。',
      '// 源: ' + t.src + '（' + t.js + '）',
      '// 由 tool/oracle/gen_data.js 生成；键名与值逐字保留，仅供规则层读取。',
      '// ignore_for_file: prefer_single_quotes',
      '',
      '/// 原 `' + t.js + '`，' + (t.kind === 'list' ? val.length + ' 条记录' : Object.keys(val).length + ' 个顶层键') + '。',
      'const ' + dartType + ' ' + t.dart + ' = ' + dartVal(val, 0) + ';',
      '',
    ].join('\n');
    const outFile = path.join(OUT_DIR, t.file);
    fs.writeFileSync(outFile, header, 'utf8');
    const n = t.kind === 'list' ? val.length : Object.keys(val).length;
    counts.push({ file: t.file, name: t.dart, records: n, bytes: Buffer.byteLength(header) });
    console.log(`${t.file.padEnd(18)} ${String(n).padStart(4)} 条  ${(Buffer.byteLength(header) / 1024).toFixed(1)} KB`);
  }
  console.log('源目录:', SRC_ROOT);
  console.log('合计', counts.reduce((a, b) => a + b.records, 0), '条记录');
}

main();
