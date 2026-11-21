// ============================================================
// test/p9_combat_skill_test.dart — P9（需求 9）
//
//   ① 自动车卡时，战斗技能必须跟着**实际携带的武器**走：
//      带手枪 → 射击（手枪）；带黄铜指虎 → 格斗（斗殴）；
//      没武器 → 保底斗殴（徒手也能打）；别的战斗技能不该被额外点名。
//   ② 闪避的基础值 = DEX ~/ 2：学闪避是在这个基础值上**加**，不是从 0 加。
//
// 反向自证伪（报告 `_p9_combat_skill_report.md` 里写明做法）：
//   把 `combat_skill_map.dart#weaponSkillAlias` 里的 `手枪` 改成 `斗殴`，
//   或把 `unarmedCombatSkillKey` 改成 `fighting::刀剑`，本文件立刻红。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/combat_skill_map.dart';
import 'package:dice_realm/domain/data/skills.dart';
import 'package:dice_realm/domain/data/weapons.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/preset_gen.dart'
    show legacyWeaponSkillMatchForOracle, redistributePoints;
import 'package:dice_realm/domain/rules_coc7.dart' show effectiveAttrs;
import 'package:dice_realm/domain/skillmodel.dart';
import 'package:dice_realm/ui/card_edit/combat_logic.dart' as card_edit;
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/* ---------------- 造卡 ---------------- */

Character _card({
  String occupationId = 'occ67', // 法官：本职里没有战斗技能，观察点更干净
  int attrValue = 60,
  int? dex,
}) {
  final c = Character(newCharacter());
  c.raw['id'] = 'p9combat';
  c.raw['occupationId'] = occupationId;
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
  for (final k in <String>[
    'str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu', 'luck',
  ]) {
    c.attributes[k] = attrValue;
  }
  if (dex != null) c.attributes['dex'] = dex;
  recalc(c);
  syncSkills(c);
  return c;
}

/// 往卡里塞一把武器（只用 `skill` 字段参与对齐，其余字段照武器表的样子填）
void _addWeapon(Character c, String name, String skill) {
  asList(c.raw['weapons']).add(<String, Object?>{
    'name': name,
    'skill': skill,
    'damage': '',
    'range': '',
    'pierce': '×',
    'perRound': '1',
    'ammo': '',
    'malfunction': '',
    'era': '现代',
    'price': '',
    'category': '自定义',
    'note': '',
    'qty': 1,
  });
}

/// 按 key 取技能实例
Map<String, Object?>? _skill(Character c, String key) {
  for (final s in c.skills.map(asMap)) {
    if (jsStr(s['key']) == key) return s;
  }
  return null;
}

int _intOf(Character c, String key) => jsNum(_skill(c, key)?['int']);
int _occOf(Character c, String key) => jsNum(_skill(c, key)?['occ']);
int _totalOf(Character c, String key) => jsNum(_skill(c, key)?['total']);

/// 卡上所有「战斗分类」技能实例的 key
List<String> _combatKeys(Character c) => c.skills
    .map(asMap)
    .map((s) => jsStr(s['key']))
    .where(isCombatSkillKey)
    .toList();

void main() {
  /* ============================================================
   * ① 武器 → 战斗技能映射表
   * ============================================================ */
  group('武器 → 战斗技能映射（CoC 7e 口径）', () {
    test('近战：指虎/徒手/小刀 → 斗殴；剑→刀剑；鞭子→鞭；绞具→绞索；链枷/电锯→链锯连枷', () {
      expect(combatSkillKeyOfWeaponSkill('斗殴'), 'fighting::斗殴');
      expect(combatSkillKeyOfWeaponSkill('剑'), 'fighting::刀剑');
      expect(combatSkillKeyOfWeaponSkill('鞭子'), 'fighting::鞭');
      expect(combatSkillKeyOfWeaponSkill('绞具'), 'fighting::绞索');
      expect(combatSkillKeyOfWeaponSkill('链枷'), 'fighting::链锯/连枷');
      expect(combatSkillKeyOfWeaponSkill('电锯'), 'fighting::链锯/连枷');
      expect(combatSkillKeyOfWeaponSkill('斧'), 'fighting::斧');
      expect(combatSkillKeyOfWeaponSkill('矛'), 'fighting::矛');
    });

    test('火器：手枪 / 步枪霰弹枪 / 冲锋枪 / 机枪重武器 → 各自射击专攻', () {
      expect(combatSkillKeyOfWeaponSkill('手枪'), 'firearms::手枪');
      expect(combatSkillKeyOfWeaponSkill('步枪/霰弹枪'), 'firearms::步枪/霰弹枪');
      expect(combatSkillKeyOfWeaponSkill('步枪'), 'firearms::步枪/霰弹枪');
      expect(combatSkillKeyOfWeaponSkill('霰弹枪'), 'firearms::步枪/霰弹枪');
      expect(combatSkillKeyOfWeaponSkill('冲锋枪'), 'firearms::冲锋枪');
      expect(combatSkillKeyOfWeaponSkill('机枪'), 'firearms::机枪/重武器/火焰喷射器');
      expect(combatSkillKeyOfWeaponSkill('重武器'), 'firearms::机枪/重武器/火焰喷射器');
      expect(combatSkillKeyOfWeaponSkill('喷射器'), 'firearms::机枪/重武器/火焰喷射器');
      expect(combatSkillKeyOfWeaponSkill('弓'), 'firearms::弓');
      expect(combatSkillKeyOfWeaponSkill('弩'), 'firearms::弓');
    });

    test('投掷 / 爆破 / 炮术 是独立技能（id 当 key）', () {
      expect(combatSkillKeyOfWeaponSkill('投掷'), 'throw');
      expect(combatSkillKeyOfWeaponSkill('爆破'), 'demolitions');
      expect(combatSkillKeyOfWeaponSkill('炮术'), 'artillery');
    });

    test('武器表 104 条：每条 skill 都能落到一个真实技能上（不漏映射）', () {
      for (final w in cocWeapons) {
        final skill = jsStr(w['skill']);
        if (skill.isEmpty) continue;
        expect(skillKeyOfName(canonicalWeaponSkillName(skill)), isNotNull,
            reason: '武器「${jsStr(w['name'])}」的 skill「$skill」归一后查不到技能');
      }
    });

    test('与展示层别名表（card_edit/combat_logic.dart）逐条一致', () {
      card_edit.weaponSkillAlias.forEach((from, to) {
        expect(canonicalWeaponSkillName(from), to,
            reason: '规则层与展示层对「$from」的归一必须一致');
      });
    });

    test('雷管（skill=电气维修）不是战斗技能，闸门不认它', () {
      expect(combatSkillKeyOfWeaponSkill('电气维修'), 'elec_repair');
      expect(isCombatSkillKey('elec_repair'), isFalse);
      final c = _card();
      _addWeapon(c, '雷管', '电气维修');
      expect(requiredCombatSkillKeys(c), <String>{unarmedCombatSkillKey},
          reason: '非战斗技能的武器不该把斗殴挤掉');
    });

    test('没有武器 → 闸门里只有斗殴', () {
      final c = _card();
      expect(requiredCombatSkillKeys(c), <String>{'fighting::斗殴'});
      expect(requiredCombatSkillNames(c), <String>['斗殴']);
    });

    test('多把武器 → 各自的战斗技能都在闸门里', () {
      final c = _card();
      _addWeapon(c, '黄铜指虎', '斗殴');
      _addWeapon(c, '手枪', '手枪');
      expect(requiredCombatSkillKeys(c),
          <String>{'fighting::斗殴', 'firearms::手枪'});
    });
  });

  /* ============================================================
   * ② 一键分配：战斗技能跟着武器走
   * ============================================================ */
  group('一键分配（autoSpendPoints）按武器对齐战斗技能', () {
    test('带手枪 → 射击（手枪）有点数，其它战斗技能一个点都不给', () {
      final c = _card();
      _addWeapon(c, '手枪', '手枪');
      final left = autoSpendPoints(c, rng: () => 0.42);

      expect(left[0], 0, reason: '职业点要花完');
      expect(left[1], 0, reason: '兴趣点要花完');
      expect(_intOf(c, 'firearms::手枪'), greaterThan(0),
          reason: '带手枪就必须学射击（手枪）');
      for (final key in <String>[
        'fighting::斗殴',
        'fighting::刀剑',
        'fighting::斧',
        'fighting::矛',
        'fighting::绞索',
        'fighting::鞭',
        'fighting::链锯/连枷',
        'firearms::步枪/霰弹枪',
        'firearms::冲锋枪',
        'firearms::机枪/重武器/火焰喷射器',
        'firearms::弓',
        'throw',
        'artillery',
        'demolitions',
      ]) {
        expect(_intOf(c, key), 0, reason: '没带对应武器，不该给「$key」点兴趣点');
      }
    });

    test('带黄铜指虎 → 格斗（斗殴）有点数，射击各门类一个点都没有', () {
      final c = _card();
      _addWeapon(c, '黄铜指虎', '斗殴');
      autoSpendPoints(c, rng: () => 0.42);

      expect(_intOf(c, 'fighting::斗殴'), greaterThan(0));
      for (final key in <String>[
        'firearms::手枪',
        'firearms::步枪/霰弹枪',
        'firearms::冲锋枪',
        'firearms::机枪/重武器/火焰喷射器',
        'firearms::弓',
        'fighting::刀剑',
        'fighting::斧',
        'throw',
      ]) {
        expect(_intOf(c, key), 0, reason: '只带指虎却学了「$key」= 白扔点');
      }
    });

    test('没有武器 → 保底学斗殴（徒手也能打）', () {
      final c = _card();
      autoSpendPoints(c, rng: () => 0.42);

      expect(_intOf(c, 'fighting::斗殴'), greaterThan(0),
          reason: '「没武器就只能斗殴」是明确要求，斗殴必须有点数');
      for (final key in <String>[
        'firearms::手枪',
        'firearms::步枪/霰弹枪',
        'firearms::冲锋枪',
        'firearms::弓',
        'fighting::刀剑',
        'fighting::斧',
        'fighting::矛',
        'fighting::绞索',
        'fighting::鞭',
        'fighting::链锯/连枷',
        'throw',
      ]) {
        expect(_intOf(c, key), 0, reason: '没武器时不该点名「$key」');
      }
    });

    test('带剑 → 学刀剑（别名归一后真的对得上，不再退回斗殴）', () {
      final c = _card();
      _addWeapon(c, '中型剑(佩剑等)', '剑');
      autoSpendPoints(c, rng: () => 0.42);
      expect(_intOf(c, 'fighting::刀剑'), greaterThan(0));
      expect(_intOf(c, 'fighting::斗殴'), 0);
    });

    test('带投石 → 学投掷（独立技能 id=throw 也要能命中）', () {
      final c = _card();
      _addWeapon(c, '投石', '投掷');
      autoSpendPoints(c, rng: () => 0.42);
      expect(_intOf(c, 'throw'), greaterThan(0));
      expect(_intOf(c, 'fighting::斗殴'), 0);
    });

    test('分配完：除武器对应的战斗技能外，没有别的战斗技能拿到点数', () {
      for (final weapon in <List<String>>[
        <String>['黄铜指虎', '斗殴'],
        <String>['手枪', '手枪'],
        <String>['猎枪', '步枪/霰弹枪'],
        <String>['长鞭', '鞭子'],
        <String>['电锯', '电锯'],
      ]) {
        final c = _card();
        _addWeapon(c, weapon[0], weapon[1]);
        autoSpendPoints(c, rng: () => 0.42);
        final gate = requiredCombatSkillKeys(c);
        final stray = <String>[];
        for (final key in _combatKeys(c)) {
          if (gate.contains(key)) continue;
          if (_intOf(c, key) > 0 || _occOf(c, key) > 0) stray.add(key);
        }
        expect(stray, isEmpty,
            reason: '${weapon[0]}：这些战斗技能拿点却没配套武器 $stray');
      }
    });

    test('本职战斗技能属于职业设定，本身不因为「没带对应武器」被清零', () {
      // 警察：本职含 格斗（斗殴）与 射击（手枪）
      final c = _card(occupationId: 'occ224');
      final occSet = occupationalSet(c);
      expect(occSet.containsKey('fighting::斗殴'), isTrue,
          reason: 'occ224 警察的本职应含斗殴，测试前提不成立就要改用例');
      expect(occSet.containsKey('firearms::手枪'), isTrue);

      _addWeapon(c, '黄铜指虎', '斗殴');
      autoSpendPoints(c, rng: () => 0.42);
      // 职业点照规则花在本职战斗技能上（不因为「没带手枪」就清空）
      expect(_occOf(c, 'firearms::手枪') + _occOf(c, 'fighting::斗殴'),
          greaterThan(0));
      // 但额外的兴趣点仍然只给武器对得上的那门
      expect(_intOf(c, 'fighting::斗殴'), greaterThan(0));
      expect(_intOf(c, 'firearms::手枪'), 0);
    });
  });

  /* ============================================================
   * ③ 先分配、后挑武器（向导里技能步在战斗步之前）
   * ============================================================ */
  group('alignCombatSkillsToWeapons：换武器后把兴趣点搬回来', () {
    test('先无武器分配（点落在斗殴），再给手枪 → 搬到手枪，斗殴清零', () {
      final c = _card();
      autoSpendPoints(c, rng: () => 0.42);
      final before = _intOf(c, 'fighting::斗殴');
      expect(before, greaterThan(0));

      _addWeapon(c, '手枪', '手枪');
      final moved = alignCombatSkillsToWeapons(c);

      expect(moved, before, reason: '斗殴上的兴趣点应全部搬走');
      expect(_intOf(c, 'fighting::斗殴'), 0);
      expect(_intOf(c, 'firearms::手枪'), greaterThan(0));
      expect(jsNum(interestPoints(c)['remain']), 0, reason: '点数仍要花完');
    });

    test('幂等：没有可搬的点时返回 0，卡片不变', () {
      final c = _card();
      _addWeapon(c, '手枪', '手枪');
      autoSpendPoints(c, rng: () => 0.42);
      final snapshot = c.skills
          .map(asMap)
          .map((s) => '${jsStr(s['key'])}=${jsNum(s['int'])}')
          .toList();
      expect(alignCombatSkillsToWeapons(c), 0);
      expect(
        c.skills.map(asMap).map((s) => '${jsStr(s['key'])}=${jsNum(s['int'])}'),
        snapshot,
      );
    });

    test('本职战斗技能上的点数（职业设定）原地不动', () {
      final c = _card(occupationId: 'occ224'); // 警察：斗殴 / 手枪 都是本职
      autoSpendPoints(c, rng: () => 0.42);
      _addWeapon(c, '手枪', '手枪'); // 有手枪 → 斗殴不再是武器技能
      final brawlOcc = _occOf(c, 'fighting::斗殴');
      final brawlTotal = _totalOf(c, 'fighting::斗殴');
      expect(brawlOcc + _intOf(c, 'fighting::斗殴'), greaterThan(0));

      final moved = alignCombatSkillsToWeapons(c);

      expect(moved, 0, reason: '斗殴是本职技能，它的点不算「额外分配」，不该被搬走');
      expect(_occOf(c, 'fighting::斗殴'), brawlOcc,
          reason: '本职技能上的职业点是职业设定，不该被这条规则清掉');
      expect(_totalOf(c, 'fighting::斗殴'), brawlTotal);
      // 手枪本来就有职业点（本职），照样能打
      expect(_totalOf(c, 'firearms::手枪'), greaterThan(0));
    });
  });

  /* ============================================================
   * ④ 闪避基础值 = DEX ~/ 2
   * ============================================================ */
  group('闪避基础值 = DEX ~/ 2（CoC 7e）', () {
    test('多组 DEX：含奇数一律向下取整', () {
      const cases = <int, int>{
        60: 30,
        55: 27,
        50: 25,
        61: 30, // 30.5 → 30
        65: 32, // 32.5 → 32
        41: 20,
        1: 0,
        99: 49,
      };
      cases.forEach((dex, expected) {
        final c = _card(dex: dex);
        final dodge = _skill(c, 'dodge');
        expect(dodge, isNotNull);
        expect(jsNum(dodge!['base']), expected,
            reason: 'DEX $dex → 闪避基础值应为 $expected（DEX ~/ 2）');
        expect(jsNum(dodge['total']), expected,
            reason: '还没投入点数时，最终值就等于基础值');
      });
    });

    test('基础值来自属性表本身，不是写死的 0', () {
      // 逐条核对技能数据里的 dyn 标注
      Map<String, Object?>? def;
      for (final d in cocSkills) {
        if (jsStr(d['id']) == 'dodge') def = d;
      }
      expect(def, isNotNull);
      expect(jsStr(def!['dyn']), 'dex2',
          reason: '闪避必须标 dyn=dex2，否则 baseValue 会退回 base=0');
    });

    test('学闪避 → 最终值 = 基础值 + 投入（不是只有投入）', () {
      final c = _card(dex: 55); // 基础 27
      final dodge = _skill(c, 'dodge')!;
      final r = applyPoint(c, dodge, 'int', 20);
      expect(jsTruthy(r['ok']), isTrue, reason: '${r['reason']}');
      expect(jsNum(dodge['base']), 27);
      expect(jsNum(dodge['int']), 20);
      expect(jsNum(dodge['total']), 47, reason: '应当是 27 + 20，而不是 20');
    });

    test('基础值不算「玩家投入」：点数池的 used 只统计 occ/int', () {
      final c = _card(dex: 60); // 基础 30
      final dodge = _skill(c, 'dodge')!;
      applyPoint(c, dodge, 'int', 15);
      expect(jsNum(interestPoints(c)['used']), 15,
          reason: 'DEX/2 的 30 点是规则给的基础值，不该占用兴趣点');
      expect(jsNum(interestPoints(c)['remain']),
          jsNum(interestPoints(c)['total']) - 15);
    });

    test('上限判断基于「基础值 + 投入」的最终值', () {
      final c = _card(dex: 60); // 基础 30
      c.raw['skillCapInterest'] = 40;
      final dodge = _skill(c, 'dodge')!;
      // 30 + 10 = 40 正好到顶
      expect(jsTruthy(applyPoint(c, dodge, 'int', 10)['ok']), isTrue);
      expect(jsNum(dodge['total']), 40);
      // 再多 5 点就超上限
      final bad = applyPoint(c, dodge, 'int', 5);
      expect(jsTruthy(bad['ok']), isFalse);
      expect(jsStr(bad['reason']), contains('上限'));
    });

    test('年龄调整后跟着生效属性走（60 岁 DEX 减档，闪避基础值同步降）', () {
      final young = _card(dex: 60);
      final old = _card(dex: 60);
      old.basicInfo['age'] = 60;
      old.raw['age'] = 60;
      recalc(old);
      final youngBase = jsNum(_skill(young, 'dodge')!['base']);
      final oldBase = jsNum(_skill(old, 'dodge')!['base']);
      expect(oldBase, lessThan(youngBase),
          reason: 'DEX 被年龄扣了，闪避基础值必须跟着降（否则年龄调整等于没生效）');
      expect(oldBase, jsNum(effectiveAttrs(old)['dex']) ~/ 2);
    });
  });

  /* ============================================================
   * ⑤ 自动车卡（preset_gen）同样按武器对齐
   * ============================================================ */
  group('preset_gen 的生产口径（非预言机）', () {
    test('legacy 开关默认关闭（生产走归一后的映射）', () {
      expect(legacyWeaponSkillMatchForOracle, isFalse);
    });

    test('带手枪 → 点只落在射击（手枪），斗殴一分不给', () {
      final c = _card(occupationId: 'occ224'); // 警察：斗殴 + 手枪 都是本职
      _addWeapon(c, '手枪', '手枪');
      redistributePoints(c);

      expect(_occOf(c, 'firearms::手枪') + _intOf(c, 'firearms::手枪'),
          greaterThan(0));
      expect(_occOf(c, 'fighting::斗殴') + _intOf(c, 'fighting::斗殴'), 0,
          reason: '带了手枪就不该再往斗殴里扔点（旧版这里是按原样字符串匹配）');
      expect(jsNum(interestPoints(c)['remain']), 0);
    });

    test('带投石（skill=投掷）→ 真的给投掷加点，不再退回斗殴（连跑 20 次）', () {
      // preset_gen 的分点用了随机步长，单次跑可能恰好没抽到目标技能 ——
      // 连跑 20 次，任何一次没拿到都算失败（预支机制保证它必然有点）。
      for (var i = 0; i < 20; i++) {
        final c = _card(occupationId: 'occ224');
        _addWeapon(c, '投石', '投掷');
        redistributePoints(c);

        expect(_intOf(c, 'throw') + _occOf(c, 'throw'), greaterThan(0),
            reason: '第 $i 次：旧口径用「投掷」比对 id=throw 永远对不上，P9 已修');
        expect(_intOf(c, 'fighting::斗殴'), 0, reason: '第 $i 次');
        expect(jsNum(interestPoints(c)['remain']), 0, reason: '第 $i 次');
      }
    });

    test('没有武器 → 随机卡也保底学斗殴', () {
      for (var i = 0; i < 10; i++) {
        final c = _card(occupationId: 'occ224');
        redistributePoints(c);
        expect(_intOf(c, 'fighting::斗殴') + _occOf(c, 'fighting::斗殴'),
            greaterThan(0), reason: '第 $i 次：徒手也要能打');
      }
    });
  });
}
