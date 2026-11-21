// ============================================================
// test/p8_madness_state_test.dart — P8 精神状态（需求 6 / 7）验收
//
// 覆盖：
//   ① 精神状态选项里**没有「昏迷」**，且新增「潜在疯狂」；
//   ② 纯状态机真值表（不定 → 潜在 → 复发 / 临时 → 正常 / 治愈 / 背景标记）；
//   ③ 互斥：不定疯狂 ↔ 潜在疯狂；永久疯狂 / 正常 的旧互斥不回归；
//   ④ 跑团侧真的接线：临时/不定疯狂期间 SAN Check 被拦、不掉 SAN、不新增症状；
//      潜在疯狂掉 1 SAN → 立刻回不定疯狂且**多一条**新症状；
//      治愈按钮清掉不定/潜在；背景「疯狂症状」治愈无效。
//
// 反向自证伪（见 _p8_rules_report.md）：删掉 madness_state.dart 里
// 「潜在疯狂 → 不定疯狂 + spawnSymptom」分支后，本文件 ②④ 两组会红；
// 删掉 normalize 的背景派生后，③ 组会红。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/madness.dart' as mad;
import 'package:dice_realm/domain/madness_state.dart' as ms;
import 'package:dice_realm/domain/normalize.dart';
import 'package:dice_realm/domain/room_model_actions_sheet.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/domain/rules_coc7.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

Character _card() {
  final c = Character(newCharacter());
  c.raw['id'] = 'p8card';
  c.status['currentSAN'] = 40;
  c.status['maxSAN'] = 40;
  c.status['currentHP'] = 10;
  c.status['maxHP'] = 10;
  return c;
}

RoomHost _host({int seed = 1}) {
  final h = RoomHost(roomHostOpts(seed: seed));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  return h;
}

Map<String, Object?> _sheet(
  int san,
  List<Object?> mental, {
  List<Object?> madness = const <Object?>[],
}) =>
    <String, Object?>{
      'name': '张三',
      'status': <String, Object?>{
        'currentSAN': san,
        'maxSAN': 99,
        'currentHP': 10,
        'maxHP': 12,
      },
      'mental': List<Object?>.from(mental),
      'madness': List<Object?>.from(madness),
    };

Map<String, Object?> _sanIntent() => <String, Object?>{
      'op': RoomIntent.sanCheck,
      'p': <String, Object?>{'okLoss': '0', 'loss': '1D6'},
    };

/// SendPlan 里的提示文案（私有提示不进公共日志，只能从计划里取）。
List<String> _planTexts(List<SendPlan> out) => out.map((SendPlan p) {
      final msg = asMap(p.toJson()['msg']);
      final inner = asMap(msg['p']);
      final innerText = jsStr(inner['text']);
      return innerText.isNotEmpty ? innerText : jsStr(msg['text']);
    }).toList();

List<String> _mentalOf(RoomHost h) =>
    asList(asMap(h.roster.get('p1')!['sheet'])['mental']).map(jsStr).toList();

List<Object?> _madnessOf(RoomHost h) =>
    asList(asMap(h.roster.get('p1')!['sheet'])['madness']);

num _sanOf(RoomHost h) =>
    jsNum(asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentSAN']);

void main() {
  group('① 选项口径：昏迷删除 + 潜在疯狂新增', () {
    test('精神状态里不再有「昏迷」，且包含潜在疯狂 / 疯狂症状', () {
      expect(mentalStatus, isNot(contains('昏迷')));
      expect(mentalStatus, contains('潜在疯狂'));
      expect(mentalStatus, contains('疯狂症状'));
      expect(mentalStatus, contains('临时疯狂'));
      expect(mentalStatus, contains('不定疯狂'));
      expect(ms.kMentalChoices, mentalStatus, reason: '规则层与状态机同源');
      // 身体状态里的「昏迷」仍然保留（那是 dying/unconscious 的显示名）
      expect(bodyStatus, contains('昏迷'));
    });

    test('老卡的「昏迷」精神状态被丢弃，「不定疯狂（症状消失）」翻译成潜在疯狂', () {
      final c = _card();
      c.status['mental'] = <Object?>['昏迷'];
      normalize(c);
      expect(asList(c.status['mental']).map(jsStr).toList(), <String>['正常']);

      final c2 = _card();
      c2.status['mental'] = <Object?>['不定疯狂（症状消失）'];
      normalize(c2);
      expect(asList(c2.status['mental']).map(jsStr).toList(), <String>['潜在疯狂']);
    });
  });

  group('② 纯状态机真值表', () {
    test('不定疯狂 + 症状随轮次消失 → 潜在疯狂', () {
      final t = ms.nextMentalState(
        <Object?>['不定疯狂'],
        ms.MentalEvent.symptomFaded,
        fromIndefinite: true,
      );
      expect(t.mental, <String>['潜在疯狂']);
      expect(t.spawnSymptom, isFalse);
      expect(t.hasPotential, isTrue);
    });

    test('临时疯狂 + 症状消失 → 正常（不产生潜在疯狂）', () {
      final t = ms.nextMentalState(
        <Object?>['临时疯狂'],
        ms.MentalEvent.symptomFaded,
      );
      expect(t.mental, <String>['正常']);
      expect(t.hasPotential, isFalse);
    });

    test('潜在疯狂 + 掉 1 SAN → 立刻回不定疯狂，并要求新生成一条症状', () {
      final t = ms.nextMentalState(
        <Object?>['潜在疯狂'],
        ms.MentalEvent.sanLost,
      );
      expect(t.mental, <String>['不定疯狂']);
      expect(t.spawnSymptom, isTrue, reason: '必须真的加一条新疯狂症');

      final t2 = ms.nextMentalState(
        <Object?>['潜在疯狂', '其他'],
        ms.MentalEvent.sanLost,
      );
      expect(t2.mental, containsAll(<String>['不定疯狂', '其他']));
      expect(t2.spawnSymptom, isTrue);
    });

    test('临时 / 不定疯狂期间掉 SAN：状态不变，也不生成新症状', () {
      for (final m in <String>['临时疯狂', '不定疯狂']) {
        final t = ms.nextMentalState(<Object?>[m], ms.MentalEvent.sanLost);
        expect(t.mental, <String>[m]);
        expect(t.spawnSymptom, isFalse);
        expect(ms.blockedByMadness(<Object?>[m]), isTrue);
        expect(ms.blockedFromNewSymptom(<Object?>[m]), isTrue);
      }
      expect(ms.blockedByMadness(<Object?>['潜在疯狂']), isFalse,
          reason: '潜在疯狂必须**允许**掉 SAN，否则永远不复发');
    });

    test('治愈：清掉除「永久疯狂」「疯狂症状」外的**所有**异常状态', () {
      // P8 补充口径（用户明确）：治愈按钮 / 申请治愈 / 成功的精神分析，
      // 都能清除临时疯狂、不定疯狂、潜在疯狂，以及兜底的「其他」。
      for (final String abnormal in <String>[
        '临时疯狂',
        '不定疯狂',
        '潜在疯狂',
        '其他',
      ]) {
        expect(
          ms.nextMentalState(<Object?>[abnormal], ms.MentalEvent.cured).mental,
          <String>['正常'],
          reason: '「$abnormal」应被治愈清空',
        );
      }
      // 混合场景：一次清干净
      expect(
        ms.nextMentalState(
          <Object?>['临时疯狂', '潜在疯狂', '其他'],
          ms.MentalEvent.cured,
        ).mental,
        <String>['正常'],
      );
      // 两个不可治愈的仍然保留
      expect(
        ms.nextMentalState(
          <Object?>['不定疯狂', '疯狂症状'],
          ms.MentalEvent.cured,
        ).mental,
        <String>['疯狂症状'],
        reason: '治愈后只应剩下背景标记',
      );
      expect(
        ms.nextMentalState(
          <Object?>['潜在疯狂', '永久疯狂'],
          ms.MentalEvent.cured,
        ).mental,
        <String>['永久疯狂'],
        reason: '永久疯狂是撕卡级，不由此取消',
      );
      final bg = ms.nextMentalState(
        <Object?>['疯狂症状'],
        ms.MentalEvent.cured,
      );
      expect(bg.mental, <String>['疯狂症状'], reason: '背景疯狂症状不可治愈');
      final perm = ms.nextMentalState(
        <Object?>['永久疯狂'],
        ms.MentalEvent.cured,
      );
      expect(perm.mental, <String>['永久疯狂'], reason: '撕卡级状态不由此取消');
    });

    test('背景从疯狂表选症状 → 精神状态自动含「疯狂症状」', () {
      final t = ms.nextMentalState(<Object?>['正常'], ms.MentalEvent.backgroundMadness);
      expect(t.mental, <String>['疯狂症状']);
      final t2 = ms.nextMentalState(
        <Object?>['临时疯狂'],
        ms.MentalEvent.backgroundMadness,
      );
      expect(t2.mental, containsAll(<String>['临时疯狂', '疯狂症状']));
    });

    test('SAN 归零 → 永久疯狂', () {
      expect(
        ms.nextMentalState(<Object?>['潜在疯狂'], ms.MentalEvent.sanZero).mental,
        <String>['永久疯狂'],
      );
    });
  });

  group('③ 互斥与派生', () {
    test('不定疯狂 ↔ 潜在疯狂 互斥（规整后只剩一个，且保不定）', () {
      final list = ms.normalizeMentalList(<Object?>['不定疯狂', '潜在疯狂']);
      expect(list, <String>['不定疯狂']);
      expect(ms.normalizeMentalList(<Object?>['潜在疯狂', '不定疯狂']),
          <String>['不定疯狂']);
      // 状态机内部也守一道
      final t = ms.nextMentalState(
        <Object?>['不定疯狂', '潜在疯狂'],
        ms.MentalEvent.cured,
      );
      expect(t.hasIndefinite || t.hasPotential, isFalse);
    });

    test('「正常」「永久疯狂」的旧互斥不回归', () {
      expect(ms.normalizeMentalList(<Object?>['正常', '临时疯狂']), <String>['正常']);
      expect(ms.normalizeMentalList(<Object?>['永久疯狂', '潜在疯狂']),
          <String>['永久疯狂']);
    });

    test('背景文本来自疯狂表（含「疯狂发作」）→ 也派生「疯狂症状」', () {
      // 随机出卡 8/10 是「疯狂发作」，它不在 100 条恐惧症 / 狂躁症子表里，
      // 只存在于背景文本 → 需求 7 仍然要求精神状态自动变「疯狂症状」。
      for (final text in <String>[
        '【恐惧症】幽闭恐惧症：怕狭小空间',
        '【狂躁症】纵火癖：想点火',
        '【疯狂发作】失忆：不知何时到的这里。',
      ]) {
        final c = _card();
        c.background['phobias'] = text;
        normalize(c);
        expect(asList(c.status['mental']).map(jsStr), contains('疯狂症状'),
            reason: text);
      }
      // 反面对照：「暂无。」不是疯狂表选择
      final c2 = _card();
      c2.background['phobias'] = '暂无。';
      normalize(c2);
      expect(asList(c2.status['mental']).map(jsStr), isNot(contains('疯狂症状')));
    });

    test('临时疯狂不再派生「疯狂症状」；背景症状才派生', () {
      final c = _card();
      mad.add(c, mad.make('phobia', <String, Object?>{'name': '恐高', 'desc': ''}, false));
      normalize(c);
      expect(asList(c.status['mental']).map(jsStr), isNot(contains('疯狂症状')),
          reason: '需求 7：「疯狂症状」只作背景标记，不与游戏内临时症状联动');

      final c2 = _card();
      final bg = mad.make('phobia', <String, Object?>{'name': '恐水', 'desc': ''}, true)!;
      bg['bg'] = true;
      mad.add(c2, bg);
      normalize(c2);
      expect(asList(c2.status['mental']).map(jsStr), contains('疯狂症状'));
      expect(asList(c2.status['mental']).map(jsStr), isNot(contains('正常')));
    });
  });

  group('④ 跑团侧真的接线（SAN / 轮次 / 治愈）', () {
    test('不定疯狂期间 SAN Check 被拦：不掉 SAN、不新增症状', () {
      final h = _host(seed: 1);
      h.roster.get('p1')!['sheet'] = _sheet(16, <Object?>['不定疯狂']);
      final beforeMad = _madnessOf(h).length;
      final out = h.intent('p1', _sanIntent());
      expect(_sanOf(h), 16, reason: '临时/不定疯狂期间不得掉 SAN');
      expect(_mentalOf(h), <String>['不定疯狂']);
      expect(_madnessOf(h).length, beforeMad, reason: '不得获得新的疯狂症');
      expect(
        _planTexts(out).any((t) => t.contains('疯狂发作') || t.contains('推进 1 轮')),
        isTrue,
        reason: '必须给出「正处于疯狂发作，只能推进/申请治愈」的明确提示',
      );
    });

    test('临时疯狂期间同样被拦', () {
      final h = _host(seed: 1);
      h.roster.get('p1')!['sheet'] = _sheet(16, <Object?>['临时疯狂']);
      h.intent('p1', _sanIntent());
      expect(_sanOf(h), 16);
      expect(_madnessOf(h), isEmpty);
    });

    test('潜在疯狂掉 SAN → 立刻回不定疯狂且多一条新症状', () {
      final h = _host(seed: 1);
      h.roster.get('p1')!['sheet'] = _sheet(16, <Object?>['潜在疯狂']);
      final before = _madnessOf(h).length;
      h.intent('p1', _sanIntent());
      expect(_sanOf(h), lessThan(16), reason: '潜在疯狂必须允许掉 SAN');
      expect(_mentalOf(h), contains('不定疯狂'));
      expect(_mentalOf(h), isNot(contains('潜在疯狂')));
      expect(_madnessOf(h).length, before + 1, reason: '复发必须新生成一条疯狂症');
    });

    test('治愈按钮：清掉不定疯狂与潜在疯狂', () {
      for (final m in <String>['不定疯狂', '潜在疯狂']) {
        final h = _host();
        h.roster.get('p1')!['sheet'] = _sheet(40, <Object?>[m]);
        h.cureIndefinite(kHostSeat, <String, Object?>{'seat': 'p1'});
        expect(_mentalOf(h), <String>['正常'], reason: m);
      }
    });

    test('背景「疯狂症状」：治愈无效、状态保持不变', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = _sheet(40, <Object?>['疯狂症状'], madness: <Object?>[
        <String, Object?>{'type': 'phobia', 'name': '恐水', 'permanent': true, 'bg': true, 'rounds': 0},
      ]);
      final out = h.cureIndefinite(kHostSeat, <String, Object?>{'seat': 'p1'});
      expect(_mentalOf(h), <String>['疯狂症状']);
      expect(
        _planTexts(out).any((t) => t.contains('不可治愈')),
        isTrue,
        reason: '必须明确告知背景疯狂症状不可治愈',
      );
    });
  });
}
