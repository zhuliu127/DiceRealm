// ============================================================
// test/p12_san_expr_test.dart — P12 / 第 9 期 · PL-2
//
// `SanCheckExpr`（lib/ui/room/san_check_expr.dart，纯 Dart / 零 Flutter）
// 的表驱动验收：合法输入的容错与归一、非法输入一律 null、
// `toIntentPayload()` 与 `sheet_dice_tools.dart` 的 sancheck 载荷同键名。
//
// ★ 表驱动而不是「跑几个样例」：合法/非法各一张表，逐条独立用例；
//   非法表里刻意放了 PRD §6.2 / 设计 §1.4 点名的 abc / 2/ / -1/1d6，
//   以及多段、0 值、小数、负号、大小写混排等真实脏输入。
// ============================================================

import 'package:dice_realm/ui/room/san_check_expr.dart' show SanCheckExpr;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('A · SanCheckExpr.parse 合法表驱动（容错 + 归一）', () {
    // raw → [期望 okLoss, 期望 loss]；骰子分隔符统一大写 D。
    const Map<String, List<String>> legal = <String, List<String>>{
      '2/1d6': <String>['2', '1D6'],
      '2/1D6': <String>['2', '1D6'],
      '2 / 1d6': <String>['2', '1D6'],
      '  2 / 1D6  ': <String>['2', '1D6'],
      '1/1d3': <String>['1', '1D3'],
      '100/2D6+1': <String>['100', '2D6+1'],
      '1d3/1D6': <String>['1D3', '1D6'],
      '2/1D100': <String>['2', '1D100'],
    };

    for (final MapEntry<String, List<String>> e in legal.entries) {
      test('合法「${e.key}」→ okLoss=${e.value[0]}, loss=${e.value[1]}', () {
        final SanCheckExpr? expr = SanCheckExpr.parse(e.key);
        expect(expr, isNotNull, reason: '「${e.key}」必须被接受，实际返回 null');
        expect(expr!.okLoss, e.value[0], reason: '「${e.key}」成功扣值错');
        expect(expr.loss, e.value[1], reason: '「${e.key}」失败扣值/归一错');
        // 载荷键名与 sheet_dice_tools.dart:138-141 的 sancheck 调用点逐字一致。
        expect(expr.toIntentPayload(), <String, Object?>{
          'okLoss': e.value[0],
          'loss': e.value[1],
        });
      });
    }
  });

  group('B · SanCheckExpr.parse 非法表驱动（一律 null）', () {
    const List<String> illegal = <String>[
      '',
      '   ',
      'abc',
      '2',
      '2/',
      '/1d6',
      '-1/1d6',
      '0/1d6',
      '2/0d6',
      '2/1d0',
      '2/1d6/3',
      '2//1d6',
      '2 / 1d6 / 3',
      '1.5/1d6',
      '2/1.5',
      '2/1d',
      '2/1d6+0',
      '2/1d6-1',
      'a/1d6',
      '2/abc',
      '+2/1d6',
      '2/1d6 ', // 尾部空格本身可容错，但 '/' 分段后仍合法 → 见下方说明
    ];

    // 上面最后一条 `'2/1d6 '` 实际是**合法**的（trim 后两段都合法），
    // 从非法表里剔除，单独在 C 组做「空格容错」的正向断言。
    for (final String raw in illegal.where((String s) => s != '2/1d6 ')) {
      test('非法「$raw」→ null', () {
        expect(SanCheckExpr.parse(raw), isNull,
            reason: '「$raw」不该通过解析；权威端会把脏载荷判成非法');
      });
    }
  });

  group('C · 边界与载荷契约', () {
    test('斜杠两侧空格属于容错范围，不算非法输入', () {
      final SanCheckExpr? expr = SanCheckExpr.parse('2/1d6 ');
      expect(expr, isNotNull, reason: '纯尾部空格应被 trim 后接受');
      expect(expr!.okLoss, '2');
      expect(expr.loss, '1D6');
    });

    test('toIntentPayload 恰好两个键，不多不少（不新增协议字段）', () {
      final Map<String, Object?> p =
          SanCheckExpr.parse('2/1d6')!.toIntentPayload();
      expect(p.keys.toSet(), <String>{'okLoss', 'loss'},
          reason: 'sancheck 载荷不许夹带第三键：$p');
      expect(p.length, 2);
      expect(p['okLoss'], isA<String>());
      expect(p['loss'], isA<String>());
    });

    test('骰式大小写归一：小写 d 一律变大写 D，其余字符原样', () {
      expect(SanCheckExpr.parse('2/1d6')!.loss, '1D6');
      expect(SanCheckExpr.parse('2/2d10+3')!.loss, '2D10+3');
      expect(SanCheckExpr.parse('1d3/1d6')!.okLoss, '1D3');
    });

    test('常量构造可直接使用（纯值对象，无隐藏状态）', () {
      const SanCheckExpr e = SanCheckExpr('2', '1D6');
      expect(e.okLoss, '2');
      expect(e.loss, '1D6');
      expect(e.toIntentPayload()['loss'], '1D6');
    });
  });
}
