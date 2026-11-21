// ============================================================
// test/room_purity_test.dart — P4 静态不变式守卫（T10）
//
// 与 domain_purity_test.dart 同思路：扫真实文件内容，不看 lint 脸色。
//   ① lib/domain/room_*.dart 零 package:flutter / dart:io / dart:ui（C1/K7）
//   ② reduceRoomState( 恰好 2 个调用点 + 1 处声明（T05 已收紧）
//   ③ lib/domain/dice.dart / rules_coc7.dart **不得**引用任何 room_* 文件
//      （证明 P4 没有反向依赖既有两个模块；C7/Q8 要求这两份一行不动）
//   ④ 每个 room_*.dart 有中文模块头注释（与既有 domain 约定一致）
//   ⑤ T05 补齐：全 lib/domain（不只 room_*）零平台依赖；Q6 休眠项三件
//      保留；白名单 2 条 / 9+1 路径；三 fixture 1102 例；序列测试无 only
// ============================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/room_oracle.dart';
import 'support/room_oracle_whitelist.dart';

List<File> _roomFiles() {
  final dir = Directory('lib/domain');
  expect(dir.existsSync(), isTrue, reason: '找不到 lib/domain');
  return dir
      .listSync(recursive: false)
      .whereType<File>()
      .where((f) => f.path.contains('room_') && f.path.endsWith('.dart'))
      .toList();
}

/// 剥离 `//` 行注释，只数真实代码（说明文字里的示例不算污染）。
String _codeOnly(String src) => src
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  test('lib/domain/room_*.dart 零 package:flutter / dart:io / dart:ui', () {
    final files = _roomFiles();
    expect(files, isNotEmpty, reason: 'P4 文件不存在？');

    final offenders = <String>[];
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final banned in <String>[
          'package:flutter',
          "'dart:io'",
          '"dart:io"',
          "'dart:ui'",
          '"dart:ui"',
        ]) {
          if (line.contains(banned)) {
            offenders.add('${f.path}:${i + 1}  ${line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: 'domain 层被 Flutter/IO 污染：\n${offenders.join('\n')}');
  });

  test('reduceRoomState( 调用点 == 2（RoomHost.apply / RoomClient.receive）', () {
    var count = 0;
    final where = <String>[];
    for (final f in _roomFiles()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('///') || line.startsWith('//')) continue;
        if (!line.contains('reduceRoomState(')) continue;
        // 函数声明本身不是调用点（room_model_reduce.dart 的签名行）。
        if (line.trimLeft().startsWith('Map<String, Object?> reduceRoomState(')) {
          continue;
        }
        count++;
        where.add('${f.path}:${i + 1}');
      }
    }
    expect(
      count,
      2,
      reason: '归约口必须正好 2 处（RoomHost.apply / RoomClient.receive），实际 $where',
    );
  });

  test('dice.dart / rules_coc7.dart 未引用任何 room_*（P4 不得反向依赖）', () {
    for (final name in <String>['dice.dart', 'rules_coc7.dart']) {
      final f = File('lib/domain/$name');
      expect(f.existsSync(), isTrue, reason: '缺 lib/domain/$name');
      final text = f.readAsStringSync();
      expect(
        text.contains('room_'),
        isFalse,
        reason: '$name 出现了 room_ 引用 —— P4 不允许改动这两个文件的接口',
      );
    }
  });

  test('每个 room_*.dart 都有中文模块头注释', () {
    final missing = <String>[];
    for (final f in _roomFiles()) {
      final head = f.readAsStringSync().split('\n').take(3).join('\n');
      if (!head.contains('====')) missing.add(f.path);
    }
    expect(missing, isEmpty, reason: '缺模块头注释：$missing');
  });

  // ==========================================================
  // T05 补齐：全目录纯度 / Q6 休眠项 / 门禁基线
  // ==========================================================

  test('T05：lib/domain 全目录零平台依赖（不只 room_*）', () {
    final offenders = <String>[];
    for (final f in Directory('lib/domain').listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final body = _codeOnly(f.readAsStringSync());
      for (final banned in <String>[
        'package:flutter',
        "'dart:io'",
        '"dart:io"',
        "'dart:ui'",
        '"dart:ui"',
      ]) {
        if (body.contains(banned)) offenders.add('${f.path} → $banned');
      }
    }
    expect(offenders, isEmpty,
        reason: 'domain 层出现平台依赖：\n${offenders.join('\n')}');
  });

  test('T05：Q6 休眠项三件仍在（EVT.REWIND / state.rewind / rollback.turn）', () {
    final reduce = File('lib/domain/room_model_reduce.dart').readAsStringSync();
    final state = File('lib/domain/room_model_state.dart').readAsStringSync();
    final actions =
        File('lib/domain/room_model_actions_room.dart').readAsStringSync();
    final types = File('lib/domain/room_types.dart').readAsStringSync();
    expect(types.contains("static const String rewind = 'rewind';"), isTrue);
    expect(reduce.contains('case RoomEvt.rewind:'), isTrue);
    expect(state.contains("'rewind': null,"), isTrue);
    expect(actions.contains("case 'rollback.turn':"), isTrue);
    expect(types.contains("'rollback.turn': RoomPolicyEntry"), isFalse,
        reason: '入口必须仍是摘除状态');
  });

  test('T05：白名单 2 条 / 9+1 路径；三 fixture 1102 例；序列测试无 only', () {
    // F3 裁决 A：S:q1(9，终验收窄) + S:trim(1)，不许出现第 3 条。
    expect(kRoomOracleWhitelist.length, 2);
    final q1 = kRoomOracleWhitelist.firstWhere((d) => d.caseId == 'S:q1');
    final trim = kRoomOracleWhitelist.firstWhere((d) => d.caseId == 'S:trim');
    expect(q1.allowedPaths.length, 9);
    expect(trim.allowedPaths, <String>[kTrimAllowedPath]);

    final rules = RoomOracleFixture.load('room_rules.json');
    final model = RoomOracleFixture.load('room_model.json');
    final seqs = RoomOracleFixture.load('room_sequences.json');
    expect(rules.cases.length, 455);
    expect(model.cases.length, 525);
    expect(seqs.cases.length, 122);
    expect(rules.cases.length + model.cases.length + seqs.cases.length, 1102);
    expect(
      seqs.cases.where((c) => c['fn'] == 'hostScript').length,
      95,
      reason: '95 例 hostScript 必须已去除 only 遮挡',
    );
    expect(
      seqs.cases.where((c) => c['fn'] == 'clientScript').length,
      27,
    );
    final seqSrc = File('test/room_sequences_test.dart').readAsStringSync();
    expect(RegExp(r'\bonly\s*:').hasMatch(_codeOnly(seqSrc)), isFalse,
        reason: 'T05 之后不许再用 only 跳过 hostScript');
  });
}
