// ============================================================
// test/room_legacy_migrate_test.dart — P5/T01 S1.3 旧存档 K4 脱敏迁移
//
// 被测对象：`lib/domain/room_legacy_migrate.dart#migrateLegacySave`
// （纯函数，零 I/O，Map → Map）。
//
// 命中条件（保守，只打旧版 buggy rollback 重放的真缺陷产物）：
//   kind=='check' 且 opp==null 且 seat!='' 且 text 含「秘密检定」
//
// 本文件全部是**纯 Dart 断言**：不起 widget 树、不 pump、不依赖屏幕尺寸。
// 相关铁律：T6（断言数据形状，不断言 UI 文案）。
//
// 覆盖：
//   · 命中 → 就地脱敏行（seat 空 / 统一文案 / redacted:true）
//   · 四种不命中（各自独立用例）：已脱敏 / 公开对抗 / text 不含 / kind 不对
//   · 幂等（连续两次迁移结果逐字节相同，第二次 migrated==0）
//   · 保留 seq / at（不打乱时间轴与水位）与其余自定义键
//   · 边界：空 logs / logs 非数组 / 元素非对象 / 缺 logs 键 / 深层嵌套
//   · 深拷贝语义：入参（含其内层行对象）绝不被就地改写
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_legacy_migrate.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart' show roomHostOpts;

// ------------------------------------------------------------
// 夹具：只造存档形状，不碰 Host / Client / UI
// ------------------------------------------------------------

/// 一条**命中**条件的明文秘密检定行（旧版 Q1 缺陷产物）。
///
/// `opp` 键显式写 null，是旧存档最常见的形状；另有一个用例覆盖「键不存在」。
Map<String, Object?> _plaintextRow({
  Object? seq = 7,
  Object? at = 1700000000123,
}) =>
    <String, Object?>{
      'seq': seq,
      'at': at,
      'seat': 'p1',
      'kind': 'check',
      'opp': null,
      'text': '秘密检定：骰出 07，极难成功',
      // 自定义键：迁移不得丢字段（否则 UI 会读不到等级文案）
      'extra': <String, Object?>{
        'levelText': '极难成功',
        'tags': <Object?>['侦查', '夜间'],
      },
    };

/// 一条**合规**的脱敏行（P4 的 `redact` 产物，`seat` 恒为空串）。
Map<String, Object?> _redactedRow({Object? seq = 8, Object? at = 1700000000456}) =>
    <String, Object?>{
      'seq': seq,
      'at': at,
      'seat': '',
      'kind': 'check',
      'opp': null,
      'text': 'KP 秘密进行了一次检定',
      'redacted': true,
    };

/// 一条公开骰（`kind=='dice'`，与检定无关）。
Map<String, Object?> _diceRow() => <String, Object?>{
      'seq': 9,
      'at': 1700000000789,
      'seat': 'p2',
      'kind': 'dice',
      'text': '1D100 = 42',
    };

/// 一份形状齐全的 20 键存档（只填本用例关心的键）。
Map<String, Object?> _save({List<Object?>? logs}) => <String, Object?>{
      'v': 2,
      'code': 'p5t01',
      'seq': 9,
      'meta': <String, Object?>{
        'code': 'p5t01',
        'name': 'T01 测试团',
        'status': 'IN_GAME',
        'mode': 'EXPLORATION',
        'round': 2,
      },
      'members': <Object?>[
        <String, Object?>{'seat': 'p1', 'nickname': '甲', 'role': 'player'},
        <String, Object?>{'seat': 'p2', 'nickname': '乙', 'role': 'player'},
      ],
      'logs': logs ?? <Object?>[_plaintextRow()],
      'chats': <Object?>[],
      'dice': <Object?>[],
      'privates': <Object?>[],
      'scene': null,
      'combat': null,
      'board': null,
      'sceneCheck': null,
    };

/// 取迁移结果里的 logs 列表（纯读，不写回任何东西）。
List<Map<String, Object?>> _logsOf(LegacyMigrateResult r) =>
    asList(r.save['logs']).map(asMap).toList();

void main() {
  group('S1.3 · 命中：就地改成脱敏行', () {
    test('明文秘密检定行 → seat 空串 / 统一文案 / redacted:true', () {
      final input = _save();
      final r = migrateLegacySave(input);

      expect(r.migrated, 1);
      expect(r.changed, isTrue);

      final row = _logsOf(r).single;
      expect(row['seat'], '', reason: '已脱敏行的 seat 必须是空串');
      expect(row['text'], 'KP 秘密进行了一次检定',
          reason: '统一文案必须是 reduce 侧的常量（否则前端文案会分叉）');
      expect(row['redacted'], isTrue);
      expect(row['kind'], 'check', reason: 'kind 不改，记录类型仍是检定');

      // 入参原样（深拷贝语义）
      expect(jsonEncode(input).contains('秘密检定：骰出 07'), isTrue,
          reason: '入参绝不能被就地改写');
      expect(identical(r.save, input), isFalse);
      expect(identical(asList(input['logs']).single, row), isFalse,
          reason: '行对象也必须是副本');
    });

    test('保留 seq / at：时间轴与水位逐字节不变', () {
      final input = _save();
      final r = migrateLegacySave(input);
      final row = _logsOf(r).single;

      // 「逐字节不变」：类型 + 序列化结果都相同（num 的 7 与 7.0 会被区分）
      expect(jsonEncode(<String, Object?>{'seq': row['seq']}),
          jsonEncode(<String, Object?>{'seq': 7}));
      expect(jsonEncode(<String, Object?>{'at': row['at']}),
          jsonEncode(<String, Object?>{'at': 1700000000123}));
      expect(row['seq'], isA<int>(), reason: 'seq 不得被转成 double');
      expect(row['at'], isA<int>(), reason: 'at 不得被转成 double');
    });

    test('其余自定义键原样保留（含嵌套对象与数组）', () {
      final r = migrateLegacySave(_save());
      final extra = asMap(_logsOf(r).single['extra']);
      expect(extra['levelText'], '极难成功');
      expect(asList(extra['tags']), <Object?>['侦查', '夜间']);
    });

    test('混合批次：只改命中行，顺序与其余行完全不动', () {
      final r = migrateLegacySave(_save(logs: <Object?>[
        _plaintextRow(seq: 1),
        _redactedRow(seq: 2),
        _diceRow(),
        _plaintextRow(seq: 4, at: 1700000000999),
      ]));

      expect(r.migrated, 2);
      final rows = _logsOf(r);
      expect(rows.map((x) => x['seq']).toList(), <Object?>[1, 2, 9, 4],
          reason: '迁移不得重排日志（时间轴顺序就是回放顺序）');
      expect(rows[0]['seat'], '');
      expect(rows[1]['seat'], '', reason: '本来就合规的行保持原样');
      expect(rows[2]['text'], '1D100 = 42', reason: 'kind 非 check 的行不动');
      expect(rows[3]['seat'], '');
    });

    test('opp 键缺省（旧存档无该键）同样命中', () {
      final row = _plaintextRow()..remove('opp');
      final r = migrateLegacySave(_save(logs: <Object?>[row]));
      expect(r.migrated, 1,
          reason: '`opp == null` 必须同时覆盖「键不存在」与「显式 null」');
      expect(_logsOf(r).single['seat'], '');
    });
  });

  group('S1.3 · 不命中（四种，各自独立用例）', () {
    test('已脱敏：seat 为空串 → 不命中（幂等的根）', () {
      final r = migrateLegacySave(_save(logs: <Object?>[_redactedRow()]));
      expect(r.migrated, 0);
      expect(r.changed, isFalse);
      expect(_logsOf(r).single['text'], 'KP 秘密进行了一次检定');
    });

    test('公开对抗：opp 非 null → 不命中（即使文案里带「秘密检定」）', () {
      final row = _plaintextRow()
        ..['opp'] = <String, Object?>{'seat': 'p2', 'level': 'win'};
      final r = migrateLegacySave(_save(logs: <Object?>[row]));
      expect(r.migrated, 0, reason: '公开对抗是正常产物，不得误伤');
      expect(_logsOf(r).single['seat'], 'p1');
      expect(_logsOf(r).single['text'], '秘密检定：骰出 07，极难成功');
    });

    test('文案不含「秘密检定」→ 不命中', () {
      final row = _plaintextRow()..['text'] = '常规检定：骰出 42，成功';
      final r = migrateLegacySave(_save(logs: <Object?>[row]));
      expect(r.migrated, 0);
      expect(_logsOf(r).single['text'], '常规检定：骰出 42，成功');
    });

    test('kind 不是 check → 不命中', () {
      for (final kind in <String>['dice', 'chat', 'log', 'opposed', '']) {
        final row = _plaintextRow()..['kind'] = kind;
        final r = migrateLegacySave(_save(logs: <Object?>[row]));
        expect(r.migrated, 0, reason: 'kind=$kind 不属于检定行');
      }
      // kind 缺键（纯旧形状）也不命中
      final noKind = _plaintextRow()..remove('kind');
      expect(migrateLegacySave(_save(logs: <Object?>[noKind])).migrated, 0);
    });

    test('seat 为 null → 保守不命中（不误伤形状怪异的行）', () {
      final row = _plaintextRow()..['seat'] = null;
      expect(migrateLegacySave(_save(logs: <Object?>[row])).migrated, 0);
    });
  });

  group('S1.3 · 幂等', () {
    test('连续迁移两次：第二次零改动，结果逐字节相同', () {
      final input = _save(logs: <Object?>[
        _plaintextRow(seq: 1),
        _diceRow(),
        _redactedRow(seq: 3),
      ]);

      final first = migrateLegacySave(input);
      expect(first.migrated, 1);

      final second = migrateLegacySave(first.save);
      expect(second.migrated, 0, reason: '脱敏后 seat 为空串 → 不再命中');
      expect(second.changed, isFalse);
      expect(jsonEncode(second.save), jsonEncode(first.save),
          reason: '幂等：重复导入必须零变化（否则每次续玩都会提示一次）');

      // 第三次也一样（不是「两次之后才稳定」）
      final third = migrateLegacySave(second.save);
      expect(third.migrated, 0);
      expect(jsonEncode(third.save), jsonEncode(first.save));
    });
  });

  group('S1.3 · 边界（不崩 + 语义正确）', () {
    test('空 logs：迁移 0 条，logs 仍是空数组', () {
      final r = migrateLegacySave(_save(logs: <Object?>[]));
      expect(r.migrated, 0);
      expect(asList(r.save['logs']), isEmpty);
    });

    test('logs 不是数组：不崩，迁移 0 条，入参原值不受影响', () {
      final input = <String, Object?>{
        'v': 2,
        'code': 'p5t01',
        'logs': '不是数组',
      };
      final r = migrateLegacySave(input);
      expect(r.migrated, 0);
      expect(input['logs'], '不是数组',
          reason: '入参保持原值（深拷贝只影响返回值）');
    });

    test('★ 非 Map 元素被归一成空 Map（原值不保留，记录现状而非放水）', () {
      // 语义钉子：`asMap` 对非 Map 返回空 Map，所以 logs 里的脏元素会变成 {}。
      // 这是**有意保留**的现状：logs 正常都是对象数组，异常数据不崩优先。
      // 若将来改成「原值透传」，这个用例会红，提醒改这里而不是悄悄漂移。
      final input = _save(logs: <Object?>['oops', 42, null]);
      final r = migrateLegacySave(input);

      expect(r.migrated, 0);
      expect(_logsOf(r), hasLength(3));
      for (final row in _logsOf(r)) {
        expect(row, isEmpty, reason: '非 Map 元素 → 空 Map');
      }
      // 入参仍是原值（深拷贝语义）
      expect(asList(input['logs']), <Object?>['oops', 42, null]);
    });

    test('元素不是对象（字符串 / 数字 / null）：不崩，迁移 0 条', () {
      final r = migrateLegacySave(_save(logs: <Object?>[
        'oops',
        42,
        null,
        _plaintextRow(),
      ]));
      expect(r.migrated, 1, reason: '只有真对象那一行命中');
      // 保留下来的有效行仍被脱敏
      final hit = _logsOf(r).where((x) => x['kind'] == 'check').single;
      expect(hit['seat'], '');
    });

    test('缺 logs 键：不凭空造键（避免给非房间存档加 20 键形状）', () {
      final input = <String, Object?>{'v': 2, 'code': 'p5t01'};
      final r = migrateLegacySave(input);
      expect(r.migrated, 0);
      expect(r.save.containsKey('logs'), isFalse,
          reason: '只有确实存在 logs 键时才写回');
    });

    test('深层嵌套（logs 在 state 下一层）：顶层取不到 → 不崩、不误伤', () {
      final nested = <String, Object?>{
        'v': 2,
        'code': 'p5t01',
        'state': <String, Object?>{
          'logs': <Object?>[_plaintextRow()],
        },
      };
      final r = migrateLegacySave(nested);
      expect(r.migrated, 0, reason: '本函数只认顶层 logs（落点由接线方决定）');
      expect(r.save.containsKey('logs'), isFalse);
      // 嵌套内容原样深拷贝，不被改写
      expect(asMap(r.save['state'])['logs'], isA<List<Object?>>(),
          reason: '嵌套层的形状不得被破坏');
      final raw = asList(asMap(r.save['state'])['logs']).single;
      expect(asMap(raw)['seat'], 'p1', reason: '嵌套层不得被迁移触碰');
    });

    test('★ 接线链路：顶层 logs 迁移后经 adoptSave 进 state.logs（嵌套层无需处理）',
        () {
      // 设计意图钉子：`adoptSave` 会把**顶层** logs 搬进 state.logs
      // （room_model_save.dart:`adoptSave` 的 `state['logs'] = ...`），
      // 所以迁移只看顶层就够了；嵌套在 state 下的旧副本会被顶层覆盖。
      final host = RoomHost(roomHostOpts(
        meta: <String, Object?>{'code': 'p5t01'},
      ));
      final dirty = <String, Object?>{
        'v': 2,
        'code': 'p5t01',
        'seq': 5,
        'meta': <String, Object?>{'code': 'p5t01', 'name': '旧团'},
        'members': <Object?>[],
        'logs': <Object?>[_plaintextRow(seq: 3)],
        // 嵌套的旧副本：迁移不看它，adoptSave 也不会读它
        'state': <String, Object?>{
          'logs': <Object?>[_plaintextRow(seq: 90)],
        },
      };

      final r = migrateLegacySave(dirty);
      expect(r.migrated, 1);

      host.adoptSave(r.save);

      final logs = asList(host.state['logs']);
      expect(logs, hasLength(1));
      final row = asMap(logs.single);
      expect(row['seat'], '', reason: 'state.logs 里必须是脱敏行');
      expect(row['text'], 'KP 秘密进行了一次检定');
      expect(row['redacted'], isTrue);
      expect(jsonEncode(host.state['logs']).contains('秘密检定：骰出 07'), isFalse,
          reason: '★ 明文不得随 adoptSave 复活');
      expect(row['seq'], 3, reason: 'seq 保留（水位与时间轴不打乱）');
      // 反向确认嵌套层确实没被迁移（也不需要被迁移）
      final nested = asList(asMap(dirty['state'])['logs']);
      expect(asMap(nested.single)['seat'], 'p1',
          reason: '迁移只动顶层，嵌套层保持原样（会被 adoptSave 忽略）');
    });

    test('日志字段全缺：同一份空对象行不崩', () {
      final r = migrateLegacySave(_save(logs: <Object?>[
        <String, Object?>{},
      ]));
      expect(r.migrated, 0);
      expect(_logsOf(r), hasLength(1));
    });

    test('结果可序列化（toJson 两键，供日志/诊断使用）', () {
      final r = migrateLegacySave(_save());
      final json = r.toJson();
      expect(json.keys.toSet(), <String>{'save', 'migrated'});
      expect(json['migrated'], 1);
      expect(asList(asMap(json['save'])['logs']), hasLength(1));
      expect(() => jsonEncode(json), returnsNormally);
    });
  });
}
