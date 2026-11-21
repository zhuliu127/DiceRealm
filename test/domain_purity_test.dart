// 硬性约束的守卫：lib/domain/ 必须是**纯 Dart**（禁止 import package:flutter）。
//
// 为什么值得一条测试：domain 层的价值就在于「不装 Flutter 也能跑」——
// 一旦有人顺手 import 了 flutter/material，规则层的单测就必须起 flutter_tester，
// 变成几秒起步的重活，也没法在 CI 的纯 Dart 环境里跑。
// 这条断言比 lint 更直接：它扫的是真实文件内容。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/domain 下不得出现 package:flutter', () {
    final dir = Directory('lib/domain');
    expect(dir.existsSync(), isTrue, reason: '找不到 lib/domain');

    final offenders = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('package:flutter')) {
          offenders.add('${f.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'domain 层被 Flutter 污染了：\n${offenders.join('\n')}',
    );
  });

  test('lib/domain 下不得 import dart:ui / dart:io（保持跨端可移植）', () {
    final dir = Directory('lib/domain');
    final offenders = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final banned in <String>[
        "'dart:ui'",
        '"dart:ui"',
        "'dart:io'",
        '"dart:io"',
      ]) {
        if (text.contains(banned)) offenders.add('${f.path} → $banned');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('lib/domain 下每个文件都有中文模块头注释', () {
    final dir = Directory('lib/domain');
    final missing = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.contains('${Platform.pathSeparator}data${Platform.pathSeparator}')) continue;
      final head = f.readAsStringSync().split('\n').take(3).join('\n');
      if (!head.contains('====')) missing.add(f.path);
    }
    expect(missing, isEmpty, reason: '缺模块头注释：$missing');
  });
}
