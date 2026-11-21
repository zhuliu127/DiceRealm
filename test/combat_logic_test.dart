// ============================================================
// combat_logic_test.dart — 战斗装备 / 随身物品的纯逻辑
//
// 钉住的硬约束：
//   · 硬约束 4：非法武器使用技能不可选（「心理学」不在候选里）
//   · 硬约束 1：数据契约不变（weapons / armors / vehicles / items 的键名照旧）
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/skillmodel.dart';
import 'package:dice_realm/ui/card_edit/combat_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Character _card() {
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
  c.raw['occupationId'] = 'occ67';
  recalc(c);
  syncSkills(c);
  return c;
}

void main() {
  group('硬约束 4：武器使用技能是受约束的清单', () {
    test('清单 = 格斗各门类 + 射击各门类 + 投掷/炮术/爆破（共 15 项）', () {
      final names = combatSkillNames();
      expect(names.length, 15);
      for (final must in <String>['斗殴', '刀剑', '斧', '矛', '绞索', '鞭', '链锯/连枷']) {
        expect(names, contains(must), reason: '格斗门类缺 $must');
      }
      for (final must in <String>['手枪', '步枪/霰弹枪', '冲锋枪', '弓', '机枪/重武器/火焰喷射器']) {
        expect(names, contains(must), reason: '射击门类缺 $must');
      }
      expect(names, containsAll(<String>['投掷', '炮术', '爆破']));
    });

    test('「心理学」不在候选里（旧版这里能自由填文本，正是要修的 bug）', () {
      final c = _card();
      final options = weaponSkillOptions(c);
      final values = options.map((o) => o.value).toList();
      expect(values, isNot(contains('心理学')));
      expect(isValidWeaponSkill('心理学'), isFalse);
      expect(isValidWeaponSkill('斗殴'), isTrue);
      // 连 Dropdown 的文案里也不该出现
      expect(options.any((o) => o.label.contains('心理学')), isFalse);
    });

    test('每个选项都带角色当前值（下拉里直接看得到成功率）', () {
      final c = _card();
      final options = weaponSkillOptions(c);
      final brawl = options.firstWhere((o) => o.value == '斗殴');
      final skill = c.skills
          .map(asMap)
          .firstWhere((s) => jsStr(s['sub']) == '斗殴');
      expect(brawl.total, jsNum(skill['total']));
      expect(brawl.label, contains('${brawl.total}%'));
      expect(brawl.chanceText, contains('常规'));
      expect(brawl.chanceText, contains('困难'));
      expect(brawl.chanceText, contains('极难'));
    });
  });

  group('武器表写法 → 技能表专攻名（别名归一，逐条）', () {
    test('7 条别名全部照旧版', () {
      const expected = <String, String>{
        '剑': '刀剑',
        '鞭子': '鞭',
        '绞具': '绞索',
        '链枷': '链锯/连枷',
        '电锯': '链锯/连枷',
        '机枪': '机枪/重武器/火焰喷射器',
        '重武器': '机枪/重武器/火焰喷射器',
        '喷射器': '机枪/重武器/火焰喷射器',
      };
      expected.forEach((from, to) {
        expect(weaponSkillAlias[from], to, reason: '$from 应归一为 $to');
      });
    });

    test('归一后取到的是技能表里的那一项，不是 0', () {
      final c = _card();
      // 让「刀剑」有一个非零值
      final sword = c.skills
          .map(asMap)
          .firstWhere((s) => jsStr(s['sub']) == '刀剑');
      sword['occ'] = 20;
      recompute(sword);

      final byAlias = skillTotalOf(c, '剑');
      expect(byAlias.value, '刀剑');
      expect(byAlias.total, jsNum(sword['total']));
      expect(byAlias.total, greaterThan(0));
    });

    test('旧数据里清单外的写法要保留（否则一保存就被改掉）', () {
      final c = _card();
      final options = weaponSkillOptionsFor(c, '电气维修');
      expect(options.first.value, '电气维修');
      expect(options.first.syntheticLabel, contains('武器自带'));
      // 清单内的写法不会重复插入
      expect(weaponSkillOptionsFor(c, '斗殴').first.value, '斗殴');
    });
  });

  group('硬约束 1：武器 / 防具 / 载具 / 物品的数据契约', () {
    test('自定义武器条目含武器库同款键，数量默认 1', () {
      final w = newWeaponEntry(name: '左轮手枪', damage: '1D10');
      expect(w['name'], '左轮手枪');
      expect(w['skill'], '斗殴');
      expect(w['pierce'], '×');
      expect(w['qty'], 1);
      for (final k in <String>[
        'name',
        'skill',
        'damage',
        'range',
        'pierce',
        'perRound',
        'ammo',
        'malfunction',
        'era',
        'price',
        'category',
        'note',
        'qty',
      ]) {
        expect(w.containsKey(k), isTrue, reason: '缺键 $k（会与旧版结构不一致）');
      }
    });

    test('从武器库复制一条：qty 强制 1，其余字段原样', () {
      final lib = <String, Object?>{
        'id': 'w1',
        'name': '弓箭',
        'skill': '弓',
        'damage': '1D6+半DB',
        'qty': 9,
      };
      final w = weaponFromLibrary(lib);
      expect(jsNum(w['qty']), 1);
      expect(w['id'], 'w1');
      expect(w['name'], '弓箭');
    });

    test('武器数量加减：下限 1', () {
      final w = newWeaponEntry();
      stepWeaponQty(w, -1);
      expect(jsNum(w['qty']), 1);
      stepWeaponQty(w, 1);
      expect(jsNum(w['qty']), 2);
    });

    test('随身物品条目：{name, quantity, description}', () {
      final item = newItemEntry('手电筒');
      expect(item.keys.toSet(), <String>{'name', 'quantity', 'description'});
      expect(item['quantity'], 1);
    });

    test('数量口径 = parseInt(v,10) || 1（空 / 非法 / 0 都变 1）', () {
      expect(normalizeItemQuantity(''), 1);
      expect(normalizeItemQuantity('abc'), 1);
      expect(normalizeItemQuantity('0'), 1);
      expect(normalizeItemQuantity(null), 1);
      expect(normalizeItemQuantity('3'), 3);
      expect(normalizeItemQuantity('3 个'), 3);
    });

    test('10 个随身物品预设逐字照抄旧版', () {
      expect(gearPresets, <String>[
        '手电筒',
        '手机',
        '钱包',
        '打火机',
        '急救包',
        '相机',
        '笔记本',
        '绳索',
        '瑞士军刀',
        '雨伞',
      ]);
    });
  });

  group('近战修正只读（来自 derivedStats）', () {
    test('DB / 体格 / 力量+体型 与规则层一致', () {
      final c = _card();
      final m = MeleeSummary.of(c);
      expect(m.db, jsStr(c.derivedStats['db']));
      expect(m.build, jsNum(c.derivedStats['build']));
      expect(m.strSiz, 100);
    });
  });
}
