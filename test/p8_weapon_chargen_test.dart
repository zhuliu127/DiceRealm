// ============================================================
// test/p8_weapon_chargen_test.dart — P8 数值 bug（朋友 bug 1 / bug 2）
//
// 朋友 bug 1：自定义武器故障值可以超过 100 → 必须 1..99（100 表示不故障）。
// 朋友 bug 2：一键分配把兴趣点 5 点一份摊给 20 门语言、单个技能还可能超上限
//            → 单技能不超上限、非母语语言最多一门、常用技能优先。
//
// 反向自证伪：把 autoSpendPoints 里的语言筛选删掉，本文件的「语言只有一门」会红；
// 把 weaponMalfunctionError 的区间判断删掉，「100/120/-1 被拦」会红。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/rules_coc7.dart' show isGrowthOnly;
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/domain/weapon_rules.dart';
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Character _card({int attrValue = 60}) {
  final c = Character(newCharacter());
  c.raw['id'] = 'p8logic';
  c.raw['occupationId'] = 'occ67';
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
  for (final k in <String>[
    'str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu', 'luck',
  ]) {
    c.attributes[k] = attrValue;
  }
  recalc(c);
  syncSkills(c);
  return c;
}

/// 常用技能集合（与 chargen_logic#skillUseWeight 的口径一致，只取 ≥6 的项）
const Set<String> _usefulIds = <String>{
  'spot_hidden', 'listen', 'library', 'stealth', 'dodge', 'psychology',
  'first_aid', 'fighting', 'firearms', 'medicine', 'persuade', 'fast_talk',
  'intimidate', 'charm', 'climb', 'drive_auto', 'psychoanalysis',
};

void main() {
  group('朋友 bug 1：自定义武器故障值必须 1..99', () {
    test('100 / 120 / -1 / 0 / 小数 / 字母 被拦', () {
      for (final raw in <String>['100', '120', '-1', '0', '99.5', 'abc', '9 7']) {
        expect(weaponMalfunctionError(raw), isNotNull, reason: raw);
      }
      expect(weaponMalfunctionError('100'), contains('1-99'));
      expect(weaponMalfunctionError('120'), contains('1-99'));
    });

    test('97 / 1 / 99 通过；空与「——」= 不会故障，也放行', () {
      for (final raw in <String>['97', '1', '99', ' 97 ']) {
        expect(weaponMalfunctionError(raw), isNull, reason: raw);
      }
      expect(weaponMalfunctionError(''), isNull);
      expect(weaponMalfunctionError('——'), isNull);
      expect(weaponMalfunctionError('  '), isNull);
    });

    test('表单保存前真的调用了校验（源码探针，避免只加了函数没接线）', () {
      final src = File('lib/ui/create/steps/step_combat.dart').readAsStringSync();
      expect(src.contains('weaponMalfunctionError('), isTrue,
          reason: '自定义武器 _save 必须调用 domain 校验，否则仍能存 120');
    });
  });

  group('朋友 bug 2：一键分配算法', () {
    test('两池都花完，且每个技能都不超各自上限', () {
      final c = _card();
      final left = autoSpendPoints(c, rng: () => 0.42);
      expect(left[0], 0, reason: '职业点必须分配完');
      expect(left[1], 0, reason: '兴趣点必须分配完');
      for (final s in c.skills.map(asMap)) {
        expect(jsNum(s['total']), lessThanOrEqualTo(capOf(c, s)),
            reason: '${jsStr(s['name'])} 超出 ${capOf(c, s)}');
        // 职业点 / 兴趣点各自也不能出现负数或越过单技能额度
        expect(jsNum(s['occ']), greaterThanOrEqualTo(0));
        expect(jsNum(s['int']), greaterThanOrEqualTo(0));
      }
    });

    test('非母语语言最多只有一门被加兴趣点', () {
      final c = _card();
      autoSpendPoints(c, rng: () => 0.42);
      final langs = c.skills
          .map(asMap)
          .where((s) => jsStr(s['id']) == 'language_other')
          .where((s) => jsNum(s['int']) > 0)
          .toList();
      expect(langs.length, lessThanOrEqualTo(1),
          reason: '一般人只学一门非母语语言；实际：'
              '${langs.map((s) => jsStr(s['sub'])).toList()}');
      // 母语按规则豁免，不该被一键分配灌点
      final own = c.skills
          .map(asMap)
          .where((s) => jsStr(s['id']) == 'language_own')
          .toList();
      for (final s in own) {
        expect(jsNum(s['int']), 0);
        expect(jsNum(s['occ']), 0);
      }
    });

    test('兴趣候选池里语言最多一门（20 门语言实例逐一收敛）', () {
      final c = _card(attrValue: 90);
      final pool = interestCandidates(c, rng: () => 0.42);
      final langs = pool.where((s) => jsStr(s['id']) == 'language_other');
      expect(langs.length, lessThanOrEqualTo(1),
          reason: '别的技能都该进池，语言只能留一门');
      expect(pool.any((s) => jsStr(s['id']) == 'language_other'), isTrue,
          reason: '仍应允许学一门非母语语言');
      expect(pool.any((s) => jsStr(s['id']) == 'language_own'), isFalse,
          reason: '母语按规则豁免，不进兴趣池');
      expect(pool.any((s) => isGrowthOnly(s['id'])), isFalse);
    });

    test('兴趣点溢出时也不会摊到多门语言（上限压紧的压力场景）', () {
      // 兴趣上限压到 40：焦点 6 项很快封顶，剩余点数会向兜底项外溢 ——
      // 旧实现正是在这一步把 20 门语言各喂 5 点。
      final c = _card(attrValue: 90);
      c.raw['skillCapInterest'] = 40;
      autoSpendPoints(c, rng: () => 0.42);
      final langs = c.skills
          .map(asMap)
          .where((s) => jsStr(s['id']) == 'language_other')
          .where((s) => jsNum(s['int']) > 0)
          .toList();
      expect(langs.length, lessThanOrEqualTo(1),
          reason: '实际被加点语言：${langs.map((s) => jsStr(s['sub'])).toList()}');
      // 溢出后点数仍要花完
      expect(jsNum(interestPoints(c)['remain']), 0);
    });

    test('常用技能吃到的兴趣点显著高于冷门技能', () {
      final c = _card();
      autoSpendPoints(c, rng: () => 0.42);
      var useful = 0;
      var cold = 0;
      for (final s in c.skills.map(asMap)) {
        final id = jsStr(s['id']);
        if (id == 'language_other' || id == 'language_own') continue;
        final pts = jsNum(s['int']);
        if (_usefulIds.contains(id)) {
          useful += pts.toInt();
        } else {
          cold += pts.toInt();
        }
      }
      expect(useful, greaterThan(0));
      expect(useful, greaterThan(cold),
          reason: '常用 $useful / 冷门 $cold —— 不应把点数摊给冷门技能');
    });

    test('固定 rng 下结果可复现（同输入同输出）', () {
      final a = _card();
      final b = _card();
      autoSpendPoints(a, rng: () => 0.42);
      autoSpendPoints(b, rng: () => 0.42);
      final sa = a.skills.map(asMap).map((s) => '${jsStr(s['key'])}:${jsNum(s['int'])}').toList();
      final sb = b.skills.map(asMap).map((s) => '${jsStr(s['key'])}:${jsNum(s['int'])}').toList();
      expect(sa, sb);
    });
  });
}
