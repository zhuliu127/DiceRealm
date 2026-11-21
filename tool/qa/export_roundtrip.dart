// QA 独立复核：把旧版 Store.exportCharacter() 的真实输出喂给 Dart 侧，
// 再让 Dart 用 exportCardJson 重新导出，逐字节比对（键序 / 2 空格缩进 / 中文不转义）。
//
// 用法: dart run tool/qa/export_roundtrip.dart <legacy_export.json>
import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/repo/card_transfer.dart';

void main(List<String> args) {
  final legacyText = File(args[0]).readAsStringSync();
  final obj = jsonDecode(legacyText) as Map<String, Object?>;
  final data = Map<String, Object?>.from(obj['data'] as Map);
  final dartText = exportCardJson(Character(data));

  final same = dartText == legacyText;
  stdout.writeln('legacy bytes=${legacyText.length} dart bytes=${dartText.length}');
  stdout.writeln('BYTE_IDENTICAL=${same ? 'YES' : 'NO'}');
  if (!same) {
    final a = legacyText.split('\n');
    final b = dartText.split('\n');
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final la = i < a.length ? a[i] : '<missing>';
      final lb = i < b.length ? b[i] : '<missing>';
      if (la != lb) {
        stdout.writeln('first diff at line ${i + 1}:');
        stdout.writeln('  legacy: $la');
        stdout.writeln('  dart  : $lb');
        break;
      }
    }
  }
}
