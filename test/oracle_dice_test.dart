// oracle 等价性测试：骰子（core/dice.js）
import 'package:dice_realm/domain/dice.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

void main() {
  test('成功等级文案与 JS 逐字一致', () {
    expect(levelText, <String, String>{
      '5': '大成功',
      '4': '极难成功',
      '3': '困难成功',
      '2': '成功',
      '0': '失败',
      '-1': '大失败',
    });
  });

  OracleFixture.load('dice.json').run(<String, Object? Function(Object?)>{
    'successLevel': (args) {
      final a = args as List;
      return successLevel((a[0] as num).toInt(), a[1] as num);
    },
    'd100Bonus': (args) => d100Bonus(((args as List)[0] as num).toInt()),
    'parse': (args) => parse((args as List)[0] as String?),
    'roll': (args) {
      final a = args as List;
      return roll((a[0] as num).toInt(), (a[1] as num).toInt());
    },
    'd': (args) => d(((args as List)[0] as num).toInt()),
    'd100': (args) => d100(),
  });
}
