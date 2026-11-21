// ============================================================
// assets_logic_test.dart — 资产 / 信用评级的纯逻辑
//
// 钉住的硬约束：
//   · 硬约束 2：信用评级越界 / 非数字**不许写进模型**（空输入 ≠ 0）
//   · 硬约束 1：卡片数据契约不变（assets 的 6 个键名照旧）
//   · 信用评级 ↔ credit 技能双向同步、占用职业点
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/skillmodel.dart';
import 'package:dice_realm/ui/card_edit/assets_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// 属性齐备 + 选了「法官」（信用区间 50-80）
Character _card({String occupationId = 'occ67'}) {
  final c = Character(newCharacter());
  for (final k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
    'luck',
  ]) {
    c.attributes[k] = 50;
  }
  c.basicInfo['age'] = 32;
  c.raw['age'] = 32;
  c.raw['occupationId'] = occupationId;
  c.basicInfo['occupationName'] = jsStr(
    getOccupationById(occupationId)?['name'],
  );
  recalc(c);
  syncSkills(c);
  return c;
}

void main() {
  group('硬约束 2：信用评级非法值不写进模型', () {
    test('空串 → 不写（空输入 ≠ 0），只给「尚未分配」提示', () {
      final c = _card();
      final before = jsNum(c.assets['creditRating']);
      final r = commitCreditRating(c, '');
      expect(r.written, isFalse);
      expect(r.hint, contains('尚未分配'));
      expect(jsNum(c.assets['creditRating']), before);
    });

    test('非数字 → 不写，给可读错误', () {
      final c = _card();
      final r = commitCreditRating(c, 'abc');
      expect(r.written, isFalse);
      expect(r.error, contains('必须是数字'));
      expect(jsNum(c.assets['creditRating']), 0);
    });

    test('超出职业允许区间 → 不写，错误里带区间', () {
      final c = _card();
      final range = creditRange(c)!;
      final r = commitCreditRating(c, '${range.max + 1}');
      expect(r.written, isFalse);
      expect(r.error, contains(range.text));
      expect(jsNum(c.assets['creditRating']), 0, reason: '越界值绝不能落库');
    });

    test('低于职业下限同样拦住', () {
      final c = _card();
      final range = creditRange(c)!;
      final r = commitCreditRating(c, '${range.min - 1}');
      expect(r.written, isFalse);
      expect(jsNum(c.assets['creditRating']), 0);
    });

    test('合法值 → 写入并同步到 credit 技能', () {
      final c = _card();
      final range = creditRange(c)!;
      final r = commitCreditRating(c, '${range.mid}');
      expect(r.written, isTrue);
      expect(r.value, range.mid);
      expect(jsNum(c.assets['creditRating']), range.mid);
      final credit = c.skills
          .map(asMap)
          .firstWhere((s) => jsStr(s['id']) == 'credit');
      expect(jsNum(credit['occ']), range.mid);
      expect(jsNum(credit['total']), range.mid);
    });

    test('没选职业时只夹 0-99，不报越界', () {
      final c = _card(occupationId: '');
      expect(creditRange(c), isNull);
      expect(commitCreditRating(c, '88').written, isTrue);
      expect(commitCreditRating(c, '500').value, 99, reason: '0-99 硬上限');
    });
  });

  group('信用评级 ↔ credit 技能（双向同步 + 占职业点）', () {
    test('改资产 → 技能：occupationPoints.used 增加同样的点数', () {
      final c = _card();
      final range = creditRange(c)!;
      final usedBefore = jsNum(occupationPoints(c)['used']);
      setCreditRating(c, range.mid);
      expect(jsNum(occupationPoints(c)['used']), usedBefore + range.mid);
      expect(creditPointsOf(c), range.mid);
    });

    test('改技能 → 资产：资产还是 0 时采纳技能里的点数', () {
      final c = _card();
      final credit = c.skills
          .map(asMap)
          .firstWhere((s) => jsStr(s['id']) == 'credit');
      credit['occ'] = 30;
      recompute(credit);
      expect(jsNum(c.assets['creditRating']), 0);

      expect(adoptCreditFromSkill(c), isTrue);
      expect(jsNum(c.assets['creditRating']), 30);
      expect(jsStr(c.assets['spendingLevel']), isNotEmpty);
    });

    test('资产已有值时不采纳技能值（避免覆盖玩家输入）', () {
      final c = _card();
      setCreditRating(c, 60);
      final credit = c.skills
          .map(asMap)
          .firstWhere((s) => jsStr(s['id']) == 'credit');
      credit['occ'] = 30;
      recompute(credit);
      expect(adoptCreditFromSkill(c), isFalse);
      expect(jsNum(c.assets['creditRating']), 60);
    });

    test('credit 技能不存在时会自动补一个（旧版渲染前 syncSkills 同效）', () {
      final c = _card();
      c.raw['skills'] = <Object?>[];
      expect(hasCreditSkill(c), isFalse);
      setCreditRating(c, 55);
      expect(hasCreditSkill(c), isTrue);
      expect(creditPointsOf(c), 55);
    });
  });

  group('生活水平 / 货币 / 参考数值（由信用评级推出）', () {
    test('六档生活水平按区间归位', () {
      expect(jsStr(livingLevelOf(0)['level']), '身无分文');
      expect(jsStr(livingLevelOf(5)['level']), '拮据');
      expect(jsStr(livingLevelOf(30)['level']), '标准');
      expect(jsStr(livingLevelOf(60)['level']), '小康');
      expect(jsStr(livingLevelOf(95)['level']), '富裕');
      expect(jsStr(livingLevelOf(99)['level']), '富豪');
    });

    test('spendingLevel / currency 自动跟随（旧版 paintLevel 的副作用）', () {
      final c = _card();
      setCreditRating(c, 30);
      expect(jsStr(c.assets['spendingLevel']), '标准');
      expect(jsStr(c.assets['currency']), '\$');

      c.basicInfo['era'] = '1920年代';
      syncAssetDerived(c);
      expect(jsStr(currencyOf(c)['era']), '1920年代');
    });

    test('参考数值：低于阈值的按信用评级倍乘，高于阈值的取固定值', () {
      final c = _card();
      setCreditRating(c, 30); // 现代 · 标准档 [40, 1000]
      final s = suggestedAmountsOf(c)!;
      expect(s.cash, 40 * 30); // 40 不大于 100 → 倍乘
      expect(s.assets, 1000 * 30); // 1000 不大于 1000 → 倍乘

      setCreditRating(c, 60); // 小康档 [100, 10000]
      final s2 = suggestedAmountsOf(c)!;
      expect(s2.cash, 100 * 60); // 100 不大于 100 → 倍乘
      expect(s2.assets, 10000); // 10000 > 1000 → 固定值
    });

    test('信用评级为 0 时不显示参考数值（旧版同款）', () {
      final c = _card();
      expect(suggestedAmountsOf(c), isNull);
    });

    test('「采用建议数值」写入 cash 与 assetsDescription', () {
      final c = _card();
      setCreditRating(c, 30);
      final s = suggestedAmountsOf(c)!;
      adoptSuggestedAmounts(c, s);
      expect(jsNum(c.assets['cash']), s.cash);
      expect(jsStr(c.assets['assetsDescription']), contains('总价值约'));
    });
  });

  group('现金 / 资产分类', () {
    test('现金空串与非数字不写（同口径）', () {
      final c = _card();
      c.assets['cash'] = 500;
      expect(commitCash(c, ''), isFalse);
      expect(commitCash(c, 'abc'), isFalse);
      expect(jsNum(c.assets['cash']), 500);
      expect(commitCash(c, '0'), isTrue);
      expect(jsNum(c.assets['cash']), 0);
    });

    test('5 个资产分类各写一条 {cat, desc}，清空即删除', () {
      final c = _card();
      expect(assetCategories.length, 5);
      setAssetDesc(c, '住所', '波士顿公寓一套');
      setAssetDesc(c, '交通工具', '福特 A 型车');
      expect(asList(c.assets['assets']).length, 2);
      expect(asMap(asList(c.assets['assets']).first)['cat'], '住所');
      expect(assetDescOf(c, '交通工具'), '福特 A 型车');

      setAssetDesc(c, '住所', '');
      expect(asList(c.assets['assets']).length, 1);
      expect(assetDescOf(c, '住所'), '');
    });
  });

  group('硬约束 1：卡片数据契约不变', () {
    test('assets 仍是那 6 个键，元素结构也不变', () {
      final c = _card();
      setCreditRating(c, 55);
      setAssetDesc(c, '住所', '公寓');
      expect(c.assets.keys.toSet(), <String>{
        'creditRating',
        'cash',
        'spendingLevel',
        'assetsDescription',
        'assets',
        'currency',
      });
      final item = asMap(asList(c.assets['assets']).single);
      expect(item.keys.toSet(), <String>{'cat', 'desc'});
    });
  });
}
