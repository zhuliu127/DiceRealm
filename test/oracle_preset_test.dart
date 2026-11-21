// ============================================================
// oracle_preset_test.dart — preset_gen 与原版 core/preset.js 的等价性
//
// fixture：test/fixtures/preset.json（node tool/oracle/dump_preset_fixtures.js）
//
// 三道闸门，缺一不可：
//   1. **整张卡的 JSON 逐字段深比较** —— 同一 seed 必须出来同一张卡
//      （属性/职业/技能/装备/资产/背景/头像全部在内）；
//   2. **随机数消耗数必须相等** —— 卡面一致但消耗数不同，说明随机调用
//      顺序已经分叉，换个 seed 立刻出现两张不同的卡；
//   3. **生成结果必须合法** —— validate 无 error、checkList 全过。
//      这是「AI 车卡出来的卡一定能用」的保证。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/easter_egg.dart' as egg;
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/personas.dart' as per;
import 'package:dice_realm/domain/preset_gen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart';

/// 从 fixture 的 args 复原 Dart 侧 opts（与 dump 脚本里的 `optsFrom` 逐字对应）
PresetOptions? _optsFrom(Map args) {
  if (args['noOpts'] == true) return null;
  final o = PresetOptions();
  final sid = args['settingId'];
  if (sid != null) o.setting = per.getById(sid);
  final pf = args['profile'];
  if (pf is Map) o.profile = Map<String, Object?>.from(pf);
  final caps = args['caps'];
  if (caps is Map) o.caps = AiCaps.fromMap(caps);
  final ptsCap = args['ptsCap'];
  if (ptsCap is Map) o.ptsCap = Map<String, Object?>.from(ptsCap);
  return o;
}

void main() {
  final fixture = OracleFixture.load('preset.json');

  // ★ P7：冻结 fixture 是旧版 JS `applyAttrCap` 的输出（非 5 倍数），
  //   而生产算法已按用户 2026-11-10 真机反馈改成「5 倍数网格压缩」。
  //   预言机的职责是逐字证明「移植 == 旧版」，故这里显式启用原始算法，
  //   **不修改任何 fixture 期望值**；生产与全部其它测试仍走新算法。
  //   影响面与理由写在 _p7_transport2.txt。
  //
  // ★ P9（需求 9）：旧版 `weaponCombatSet` 只按原样字符串匹配武器的 skill 字段，
  //   不做别名归一（`剑` vs `刀剑`、`鞭子` vs `鞭`、`投掷` vs `throw`），
  //   带这些武器的卡会把战斗点扔回「斗殴」。生产侧已改成归一后的
  //   `requiredCombatSkillKeys`，同一套双路径办法：预言机测试显式打开旧口径，
  //   逐字复现 fixture；新口径的正确性由 test/p9_combat_skill_test.dart 守。
  late bool savedLegacyAttrCapForOracle;
  late bool savedLegacyWeaponMatch;
  setUp(() {
    savedLegacyAttrCapForOracle = legacyAttrCapForOracle;
    legacyAttrCapForOracle = true;
    savedLegacyWeaponMatch = legacyWeaponSkillMatchForOracle;
    legacyWeaponSkillMatchForOracle = true;
  });
  tearDown(() {
    legacyAttrCapForOracle = savedLegacyAttrCapForOracle;
    legacyWeaponSkillMatchForOracle = savedLegacyWeaponMatch;
  });

  group('preset.js → preset_gen.dart 等价性', () {
    fixture.run(<String, Object? Function(Object? args)>{
      'generateOne': (args) {
        final o = _optsFrom((args as Map).cast<String, Object?>());
        final c = generateOne(o);
        return c?.raw;
      },
      'generate': (args) {
        final a = (args as Map).cast<String, Object?>();
        final o = _optsFrom(a);
        final n = (a['n'] as num?)?.toInt();
        return generate(n, o).map((c) => c.raw).toList();
      },
    });
  });

  group('生成结果合规性（这是「AI 车卡出来的卡一定能用」的地基）', () {
    /// 逐例重跑 Dart 侧，检查规则自检
    void checkAll(String fn) {
      final list = fixture.cases
          .where((c) => c['fn'] == fn && c['error'] == null)
          .toList();
      expect(list, isNotEmpty);
      var checked = 0;

      for (final c in list) {
        final name = c['name'];
        final rng = Lcg((c['seed'] as num).toInt());
        setRng(rng.call);
        setClock(() => oracleNowMs);
        uidDeterministic = true;

        final args = (c['args'] as Map).cast<String, Object?>();
        final o = _optsFrom(args);
        final List<Character> cards;
        if (fn == 'generateOne') {
          final one = generateOne(o);
          cards = <Character>[?one];
        } else {
          cards = generate((args['n'] as num?)?.toInt(), o);
        }

        for (final card in cards) {
          final errs = validate(card);
          expect(errs, isEmpty, reason: '$name：validate 有 error → $errs');

          final list2 = checkList(card);
          final bad = list2.where((x) => x['ok'] != true).toList();
          expect(
            bad,
            isEmpty,
            reason: '$name：checkList 未全过 → ${bad.map((x) => x['label'])}',
          );

          // 关键字段不能是占位/空值（否则「合法」只是空壳）
          expect(card.raw['characterName'], isNotEmpty, reason: '$name：缺姓名');
          expect(card.raw['occupationId'], isNotEmpty, reason: '$name：缺职业');
          expect(card.basicInfo['residence'], isNotEmpty, reason: '$name：缺居住地');
          expect(card.raw['avatar'], isNotEmpty, reason: '$name：缺头像');
          expect(card.skills, isNotEmpty, reason: '$name：缺技能表');
          expect(card.raw['weapons'], isNotEmpty, reason: '$name：缺武器');
          expect(
            card.background['description'],
            isNotEmpty,
            reason: '$name：缺个人描述',
          );
          expect(card.raw['history'], isNotEmpty, reason: '$name：缺入行经历');
          expect(card.raw['companions'], isNotEmpty, reason: '$name：缺关系人');

          // 职业点 / 兴趣点不得超额
          final occUsed = (card.skills)
              .map((s) => (s as Map)['occ'])
              .fold<int>(0, (a, b) => a + ((b as num?)?.toInt() ?? 0));
          final pointErrs = validateSkillPoints(card)
              .where(
                (e) =>
                    e['target'] == 'occPoints' ||
                    e['target'] == 'interestPoints',
              )
              .toList();
          expect(
            pointErrs,
            isEmpty,
            reason: '$name：点数超额（used=$occUsed）→ $pointErrs',
          );

          // 每项技能最终值不得超过它对应的上限
          final capErrs = validateSkillCap(card);
          expect(capErrs, isEmpty, reason: '$name：技能超上限 → $capErrs');
          checked++;
        }
      }
      expect(checked, greaterThan(0));
      // ignore: avoid_print
      print('✅ $fn 合规性：$checked 张卡全部通过 validate / checkList');
    }

    test('generateOne 全部分支', () => checkAll('generateOne'));
    test('generate 批量', () => checkAll('generate'));
  });

  group('随机可复现（同一 seed → 逐字节相同）', () {
    test('generateOne 两次结果完全一致', () {
      for (var i = 0; i < 12; i++) {
        final seed = (i + 1) * 2654435761 % 4294967296;

        String run() {
          final rng = Lcg(seed);
          setRng(rng.call);
          setClock(() => oracleNowMs);
          uidDeterministic = true;
          final c = generateOne();
          return jsonEncode(c?.raw);
        }

        expect(run(), run(), reason: 'seed=$seed 两次生成结果不一致');
      }
    });

    test('generate(5) 两次结果完全一致', () {
      for (var i = 0; i < 4; i++) {
        final seed = (i + 7) * 2654435761 % 4294967296;

        String run() {
          final rng = Lcg(seed);
          setRng(rng.call);
          setClock(() => oracleNowMs);
          uidDeterministic = true;
          return jsonEncode(generate(5).map((c) => c.raw).toList());
        }

        expect(run(), run(), reason: 'seed=$seed 两批结果不一致');
      }
    });

    test('生产随机源（不注入 seed）也能出合法卡 —— 但结果不固定', () {
      setRng(() => DateTime.now().microsecondsSinceEpoch % 1000000 / 1000000.0);
      setClock(() => DateTime.now().millisecondsSinceEpoch);
      uidDeterministic = false;
      final c = generateOne();
      expect(c, isNotNull);
      expect(validate(c!), isEmpty);
    });
  });

  group('边界', () {
    setUp(() {
      final rng = Lcg(12345);
      setRng(rng.call);
      setClock(() => oracleNowMs);
      uidDeterministic = true;
    });

    test('generate(0) 与旧版一致 → 退化成 5 张', () {
      // 原码 `parseInt(n,10) || 5`：0 是 falsy，所以 0 张的请求会变成 5 张。
      // 这不是"合理"，是**既有行为**；改了会让 UI 的「0 张」语义悄悄变化。
      expect(generate(0).length, 5);
    });

    test('generate 负数 → 0 张', () {
      expect(generate(-1), isEmpty);
    });

    test('职业名找不到时回落到加权随机，不会返回 null', () {
      final c = generateOne(
        PresetOptions(
          profile: <String, Object?>{'occupationName': '根本不存在的职业名'},
        ),
      );
      expect(c, isNotNull);
      expect(c!.raw['occupationId'], isNotEmpty);
    });

    test('指定设定时不抽彩蛋（彩蛋只在整批随机时出现）', () {
      final cards = generate(
        5,
        PresetOptions(setting: per.getById('cn-modern')),
      );
      expect(cards.length, 5);
      expect(cards.every((c) => c.raw['isEasterEgg'] != true), isTrue);
    });

    test('批量生成：世界设定不重复、姓名不重复', () {
      final cards = generate(5);
      final names = cards.map((c) => c.raw['characterName']).toSet();
      expect(names.length, cards.length, reason: '同一批出现重名');
      final worlds = cards.map((c) => c.raw['worldId']).toSet();
      expect(worlds.length, cards.length, reason: '同一批出现重复世界设定');
    });

    test('彩蛋 profile 会打上标记且不被改名', () {
      final all = egg.all();
      final target = all.firstWhere((e) => !e.isFriend);
      final c = generateOne(PresetOptions(profile: egg.toProfile(target)));
      expect(c, isNotNull);
      expect(c!.raw['isEasterEgg'], isTrue);
      expect(c.raw['characterName'], target.data['name']);
      expect(validate(c), isEmpty);
    });
  });

  group('房规数值上限真的落地', () {
    setUp(() {
      final rng = Lcg(999);
      setRng(rng.call);
      setClock(() => oracleNowMs);
      uidDeterministic = true;
    });

    test('属性总和上限 → 压到上限以内且写进卡里', () {
      const cap = 420;
      for (var i = 0; i < 6; i++) {
        final c = generateOne(
          PresetOptions(
            caps: const AiCaps(
              attrCap: cap,
              withLuck: true,
              occCap: 0,
              intCap: 0,
            ),
          ),
        );
        expect(c, isNotNull);
        final sum = attrSum(c!, includeLuck: true);
        expect(sum, lessThanOrEqualTo(cap), reason: '属性总和 $sum 超过上限 $cap');
        expect(c.raw['attrCapSetting'], cap);
      }
    });

    test('每项技能上限 → 没有任何一项超过它', () {
      for (var i = 0; i < 5; i++) {
        final c = generateOne(
          PresetOptions(
            caps: const AiCaps(
              attrCap: 0,
              withLuck: true,
              occCap: 70,
              intCap: 60,
            ),
          ),
        );
        expect(c, isNotNull);
        for (final sRaw in c!.skills) {
          final s = (sRaw as Map).cast<String, Object?>();
          final total = (s['total'] as num?)?.toInt() ?? 0;
          // 母语 / 信用评级 / 基础值本身高于上限的技能按规则豁免
          if (s['id'] == 'language_own' || s['id'] == 'credit') continue;
          final base = (s['base'] as num?)?.toInt() ?? 0;
          if (base > 60) continue;
          expect(
            total,
            lessThanOrEqualTo(70),
            reason: '技能「${s['name']}」最终值 $total 超过本职上限 70',
          );
        }
      }
    });
  });
}
