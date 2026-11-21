// QA 独立复核用：dump Dart 侧 newCharacter() 的完整键树，类型名映射成 JS 口径，
// 以便与 tool/qa/legacy_probe.js 的 NEW_CHARACTER_TREE 做全等比对。
//
// 用法: dart run tool/qa/dump_tree.dart
import 'dart:io';

import 'package:dice_realm/domain/character.dart';

String typeName(Object? v) {
  if (v == null) return 'null';
  if (v is String) return 'string';
  if (v is num) return 'number';
  if (v is bool) return 'boolean';
  if (v is List) return 'array';
  if (v is Map) return 'object';
  return v.runtimeType.toString();
}

List<String> keyTree(Object? v, String prefix, List<String> out) {
  out.add('$prefix : ${typeName(v)}');
  if (v is List) {
    final seen = <String>{};
    for (final item in v) {
      final t = typeName(item);
      if (!seen.add(t)) continue;
      keyTree(item, '$prefix[]', out);
    }
    return out;
  }
  if (v is Map) {
    for (final k in v.keys) {
      keyTree(v[k], prefix.isEmpty ? '$k' : '$prefix.$k', out);
    }
  }
  return out;
}

void main() {
  final c = newCharacter();
  final out = keyTree(c, '', <String>[])..sort();
  stdout.writeln('### NEW_CHARACTER_TREE');
  for (final line in out) {
    stdout.writeln(line);
  }
  stdout.writeln('### END');
}
