// ============================================================
// attr_meta.dart — 属性 key / 中文名 / 缩写
//
// 中文名与缩写直接取自 domain 的属性表（`attributes`），
// 这里只做「按 key 查」的薄封装 —— 避免 UI 里再抄一份中文名导致两处不一致。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/rules_coc7.dart';

/// 8 项必填属性（幸运单列，可选计入购点）
const List<String> coreAttrKeys = <String>[
  'str',
  'con',
  'siz',
  'dex',
  'app',
  'int',
  'pow',
  'edu',
];

/// 9 项属性（含幸运）
const List<String> allAttrKeys = <String>[
  'str',
  'con',
  'siz',
  'dex',
  'app',
  'int',
  'pow',
  'edu',
  'luck',
];

String attrName(String key) {
  for (final a in attributes) {
    if (jsStr(a['key']) == key) return jsStr(a['name']);
  }
  return key;
}

String attrAbbr(String key) {
  for (final a in attributes) {
    if (jsStr(a['key']) == key) return jsStr(a['abbr']);
  }
  return key.toUpperCase();
}
