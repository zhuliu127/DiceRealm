// ============================================================
// test/p10_t4_synonym_request_done_test.dart — P10 第 4 期
//
// A 组：consent 对非 check.request 状态请求改走 settleRequest
//       （对齐老 APP room-model.js:1569 + :3138-3151），跨视角验证
//       REQUEST-done SEAT 定向 / pending 清零 / 既有文案不变。
// B 组：车卡技能搜索框的近义词标签（54/54 覆盖、两处搜索框形状、
//       取悦↔魅惑、原有模糊能力不回归、近义词不显示、不接职业搜索）。
//
// ★ 铁律 T1：全内存后端（roomHostOpts 的 LCG / InMemoryRoomSaveStore /
//   确定性规则），零 Timer / Future.delayed / AnimationController / 真实 I/O。
// ★ A 的跨视角：SendPlan 按 to 分发进两个真实 RoomClient，不只读权威端 state。
// ============================================================

import 'package:dice_realm/domain/character.dart' show Character, newCharacter;
import 'package:dice_realm/domain/data/skills.dart' show cocSkills;
import 'package:dice_realm/domain/engine.dart' show recalc;
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart'
    show getRequirements, skillMatches, skillSearchText;
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/domain/skill_synonyms.dart';
import 'package:dice_realm/domain/skillmodel.dart' hide find;
import 'package:dice_realm/ui/attr_meta.dart' show allAttrKeys;
import 'package:dice_realm/ui/create/chargen_logic.dart';
import 'package:dice_realm/ui/create/skill_groups.dart';
import 'package:dice_realm/ui/create/steps/step_skills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

// ------------------------------------------------------------
// A 组脚手架
// ------------------------------------------------------------

RoomHost _host() {
  final h = RoomHost(roomHostOpts(seed: 11));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  h.roster.get('p1')!['sheet'] = <String, Object?>{
    'name': '甲',
    'status': <String, Object?>{
      'currentHP': 10,
      'maxHP': 12,
      'currentSAN': 50,
      'maxSAN': 60,
      'body': '正常',
    },
    'mental': <Object?>['正常'],
    'madness': <Object?>[],
    'tempStatus': <Object?>[],
    'skills': <Object?>[
      <String, Object?>{'name': '侦查', 'total': 60},
    ],
  };
  return h;
}

Map<String, Object?> _act(String op, Map<String, Object?> p) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

Map<String, RoomClient> _clients() => <String, RoomClient>{
      'p1': RoomClient(seat: 'p1'),
      'p2': RoomClient(seat: 'p2'),
    };

void _boot(RoomHost h, Map<String, RoomClient> cs) {
  for (final e in cs.entries) {
    e.value.receive(h.syncFor(e.key).toJson());
  }
}

void _deliver(List<SendPlan> plans, Map<String, RoomClient> cs) {
  for (final p in plans) {
    final wire = p.msg.toJson();
    if (p.to == '*') {
      for (final c in cs.values) {
        c.receive(wire);
      }
    } else {
      cs[p.to]?.receive(wire);
    }
  }
}

Map<String, Object?>? _evt(SendPlan p, String t) {
  final m = p.msg.toJson();
  if (m['k'] != 'evt' || m['t'] != t) return null;
  return asMap(m['p']);
}

List<Map<String, Object?>> _evts(List<SendPlan> plans, String t) =>
    <Map<String, Object?>>[
      for (final p in plans)
        if (_evt(p, t) != null) _evt(p, t)!,
    ];

/// 发一条 state.request，返回它的 id，并把两个视角对齐到「有 1 张待办卡」。
String _issueStateRequest(RoomHost h, Map<String, RoomClient> cs) {
  h.intent(kHostSeat, _act('state.request', <String, Object?>{
    'seat': 'p1',
    'change': <String, Object?>{'hp': 5},
    'reason': '剧本效果',
  }));
  final id = jsStr(h.requestsBySeat['p1']!.single['id']);
  expect(h.pending.any((x) => x['id'] == id), isTrue,
      reason: '前置：权威端 pending 里确实有这条 state.request 记账');
  _boot(h, cs);
  expect(asList(cs['p1']!.state['requests']), hasLength(1),
      reason: '前置：玩家视角真的有 1 张待办卡，否则「卡片消失」是空断言');
  return id;
}

List<SendPlan> _consent(RoomHost h, String id, bool agree) =>
    h.intent('p1', <String, Object?>{
      'op': RoomIntent.consent,
      'p': <String, Object?>{'id': id, 'agree': agree},
    });

// ------------------------------------------------------------
// B 组脚手架（沿用 p8_skill_step_test 的窗口开高夹具）
// ------------------------------------------------------------

class _Host extends StatefulWidget {
  const _Host({required this.card});

  final Character card;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: StepSkills(
            draft: widget.card,
            onChanged: () => setState(() {}),
          ),
        ),
      );
}

Future<void> _pumpSkills(WidgetTester tester, Character card) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_Host(card: card));
  await tester.pumpAndSettle();
}

Character _card() {
  final c = Character(newCharacter());
  c.raw['id'] = 'skills04';
  c.raw['characterName'] = '第四期测试';
  c.raw['playerName'] = '老王';
  c.basicInfo['age'] = 32;
  c.raw['age'] = 32;
  c.raw['occupationId'] = 'occ2';
  for (final k in allAttrKeys) {
    c.attributes[k] = 50;
  }
  recalc(c);
  syncSkills(c);
  materializeOccupationalSkills(c);
  return c;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 第一个搜索框的形状：`c.skills` 实例（有 id / key / name / sub）。
Map<String, Object?> _defShape(String id) =>
    Map<String, Object?>.from(cocSkills.firstWhere((s) => jsStr(s['id']) == id));

/// 第二个搜索框的形状：任选技能弹窗 `_FreePickerState._options`
/// （`step_skills.dart:1024-1035`）—— **没有 `id` 键**，技能 id 在 `skill` 键。
Map<String, Object?> _pickerShape(String id) {
  final def = _defShape(id);
  return <String, Object?>{
    'skill': id,
    'sub': null,
    'name': jsStr(def['name']),
  };
}

void main() {
  // ========================================================
  // A · consent 非 check.request 分支（老 APP :1569 对齐）
  // ========================================================
  group('A · 状态变更请求的 REQUEST-done 收尾', () {
    test('A1 同意：玩家端待办卡消失 + 确有 REQUEST-done SEAT 定向事件', () {
      final h = _host();
      final cs = _clients();
      final id = _issueStateRequest(h, cs);

      final plans = _consent(h, id, true);
      _deliver(plans, cs);

      // ① 玩家视角的卡片真的没了（不是「权威端表空了」）
      expect(asList(cs['p1']!.state['requests']), isEmpty,
          reason: '客户端 state.requests 只由 REQUEST(self && done) 裁剪');
      // ② 出站确实有一条 SEAT→p1 的 REQUEST-done
      final done = <SendPlan>[
        for (final p in plans)
          if (_evt(p, RoomEvt.request) != null &&
              _evt(p, RoomEvt.request)!['done'] == true)
            p,
      ];
      expect(done, hasLength(1));
      expect(done.single.to, 'p1');
      expect(_evt(done.single, RoomEvt.request)!['id'], id);
      // ③ 第三人收不到这条定向事件（只收 skip 水位）
      final toP2 = plans.where((p) => p.to == 'p2').toList();
      expect(toP2.any((p) => _evt(p, RoomEvt.request) != null), isFalse);
      expect(toP2.any((p) => p.msg.toJson()['k'] == 'skip'), isTrue);
      // ④ 既有同意文案 / syncMembers 一字未动
      final logs = _evts(plans, RoomEvt.log)
          .map((l) => jsStr(l['text']))
          .toList();
      expect(logs.any((t) => t.contains('KP 调整了')), isTrue);
      expect(logs.any((t) => t.contains('拒绝了状态变更请求')), isFalse);
      expect(plans.any((p) => _evt(p, RoomEvt.members) != null ||
              p.msg.toJson()['k'] == 'skip'),
          isTrue);
      // ⑤ check.request 分支不受影响（老 APP 三段式仍独立）
      expect(h.requestsBySeat['p1'], isEmpty);
    });

    test('A2 同意：权威端 pending 不再残留 state.request 记账', () {
      final h = _host();
      final cs = _clients();
      final id = _issueStateRequest(h, cs);
      expect(h.pending.length, greaterThanOrEqualTo(1));
      _consent(h, id, true);
      expect(h.pending.any((x) => x['id'] == id), isFalse,
          reason: 'QA qa_p10_5_report.md §8.2 探针：改前 pending=1 残留');
      expect(h.pending.any((x) => jsStr(x['kind']) == 'state.request'), isFalse);
    });

    test('A3 拒绝：待办卡消失 + pending 清 + 不掷骰 + 拒绝提示仍在', () {
      final h = _host();
      final cs = _clients();
      final id = _issueStateRequest(h, cs);
      final plans = _consent(h, id, false);
      _deliver(plans, cs);

      expect(asList(cs['p1']!.state['requests']), isEmpty);
      expect(h.pending.any((x) => x['id'] == id), isFalse);
      expect(_evts(plans, RoomEvt.dice), isEmpty, reason: '拒绝不该掷骰');
      expect(
          _evts(plans, RoomEvt.log).any((l) =>
              jsStr(l['text']).contains('拒绝了状态变更请求')),
          isTrue,
          reason: '既有拒绝公共文案必须保留');
      final done = <SendPlan>[
        for (final p in plans)
          if (_evt(p, RoomEvt.request) != null &&
              _evt(p, RoomEvt.request)!['done'] == true)
            p,
      ];
      expect(done, hasLength(1));
      expect(done.single.to, 'p1');
    });

    test('A4 计划数变更影响：新增的恰是 1 条 SEAT REQUEST-done + 非目标水位', () {
      final h = _host();
      final cs = _clients();
      final id = _issueStateRequest(h, cs);
      final plans = _consent(h, id, true);
      final donePlans = <SendPlan>[
        for (final p in plans)
          if (_evt(p, RoomEvt.request) != null &&
              _evt(p, RoomEvt.request)!['done'] == true)
            p,
      ];
      expect(donePlans, hasLength(1),
          reason: '相对改前只多这 1 条定向 evt（外加 plan() 给非目标座位的 skip 水位）');
      expect(donePlans.single.to, 'p1');
      // 同意路径的公共事件仍是「KP 调整了…的状态」这一条 LOG
      final publicLogs = _evts(plans, RoomEvt.log)
          .where((l) => jsStr(l['text']).contains('KP 调整了'))
          .toList();
      expect(publicLogs, hasLength(1));
      // 不多发 verb 公共 sys（settleRequest 的 verb 传 null）
      expect(
          _evts(plans, RoomEvt.log).any((l) =>
              jsStr(l['text']).contains('同意并完成了') ||
              jsStr(l['text']).contains('忽略了检定请求')),
          isFalse);
    });

    test('A5 秘密口径回归：状态请求全程没有 PUBLIC 的私密字段', () {
      final h = _host();
      final cs = _clients();
      final id = _issueStateRequest(h, cs);
      final plans = _consent(h, id, true);
      _deliver(plans, cs);
      for (final p in plans.where((x) => x.to == '*')) {
        final payload = p.msg.toJson()['p'];
        expect(payload is Map ? asMap(payload).containsKey('secret') : false,
            isFalse);
      }
      expect(asList(cs['p2']!.state['dice']), isEmpty);
    });
  });

  // ========================================================
  // B · 近义词标签
  // ========================================================
  group('B · 近义词表（只服务搜索，不显示）', () {
    test('B1 覆盖 cocSkills 全部 54 条，含 8 条 special 组技能', () {
      expect(cocSkills, hasLength(54));
      final ids = <String>[for (final s in cocSkills) jsStr(s['id'])];
      for (final id in ids) {
        expect(skillSynonyms.containsKey(id), isTrue, reason: '技能 $id 缺近义词');
        expect(skillSynonyms[id], isNotEmpty, reason: '技能 $id 近义词为空');
      }
      expect(skillSynonyms.length, 54,
          reason: '表里不该有 cocSkills 之外的多余 id');
      final special = cocSkills
          .where((s) => jsTruthy(s['special']))
          .map((s) => jsStr(s['id']))
          .toList();
      expect(special, hasLength(8));
      for (final id in special) {
        expect(skillSynonyms[id], isNotEmpty, reason: '组技能 $id 也要有近义词');
      }
    });

    test('B2 第一搜索框形状：搜「取悦」/「魅惑」都命中 charm', () {
      final charm = _defShape('charm');
      expect(jsStr(charm['name']), '取悦');
      expect(skillMatchesKeyword(charm, '取悦'), isTrue);
      expect(skillMatchesKeyword(charm, '魅惑'), isTrue);
      expect(synonymsOf(charm).contains('魅惑'), isTrue,
          reason: '必须显式收进表，不许只靠 desc 里那句偶然文案');
    });

    test('B3 第二搜索框形状（无 id 键，技能 id 在 skill 键）：搜「魅惑」也命中', () {
      final opt = _pickerShape('charm');
      expect(opt.containsKey('id'), isFalse, reason: '复刻弹窗真实形状');
      expect(opt['skill'], 'charm');
      expect(skillSynonymIdOf(opt), 'charm');
      expect(synonymsOf(opt).contains('魅惑'), isTrue);
      expect(skillMatchesKeyword(opt, '魅惑'), isTrue);
      expect(skillMatchesKeyword(opt, '取悦'), isTrue);
      // 只给 name、连 skill 键也没有的极简形状 → 按 name 反查也要命中
      expect(skillSynonymIdOf(<String, Object?>{'name': '取悦'}), 'charm');
      // ★ 组技能的子类行：`name` 是显示名「格斗（斗殴）」，**不等于** cocSkills
      //   里的正式名「格斗」，按 name 反查不到 —— 只能靠 `skill` 键解析。
      //   这条专门钉住「第二级回退」，防止有人把它删了还全绿。
      final subOpt = <String, Object?>{
        'skill': 'fighting',
        'sub': '斗殴',
        'name': '格斗（斗殴）',
      };
      expect(skillSynonymIdOf(subOpt), 'fighting');
      expect(synonymsOf(subOpt).contains('近战'), isTrue);
      expect(skillMatchesKeyword(subOpt, '近战'), isTrue);
      // 8 条 special 组技能的子类行逐个走一遍（任选弹窗会全量列出）
      for (final def in cocSkills.where((d) => jsTruthy(d['special']))) {
        final id = jsStr(def['id']);
        for (final subRaw in asList(def['subskills'])) {
          final subName = jsStr(asMap(subRaw)['name']);
          final row = <String, Object?>{
            'skill': id,
            'sub': subName,
            'name': '${jsStr(def['name'])}（$subName）',
          };
          expect(skillSynonymIdOf(row), id, reason: '$id / $subName');
        }
      }
    });

    test('B4 反向：搜「魅惑」不带出相邻社交技能，且全表只有 charm 收了魅/惑', () {
      expect(synonymOwnersOf('魅'), <String>['charm']);
      expect(synonymOwnersOf('惑'), <String>['charm']);
      for (final shape in <String>['def', 'picker']) {
        final hits = <String>[
          for (final s in cocSkills)
            if (skillMatchesKeyword(
                shape == 'def'
                    ? _defShape(jsStr(s['id']))
                    : _pickerShape(jsStr(s['id'])),
                '魅惑'))
              jsStr(s['id']),
        ];
        expect(hits, <String>['charm'],
            reason: '$shape 形状搜「魅惑」不应带出话术/说服/恐吓等相邻技能');
      }
      for (final id in <String>['fast_talk', 'persuade', 'intimidate']) {
        expect(skillMatchesKeyword(_pickerShape(id), '魅惑'), isFalse);
      }
    });

    test('B5 原有模糊能力一个都没回归', () {
      expect(skillMatchesKeyword(_defShape('spot_hidden'), '侦'), isTrue,
          reason: '子串');
      expect(skillMatchesKeyword(_defShape('spot_hidden'), 'spot'), isTrue,
          reason: '去分隔符 / 英文 id 片段');
      expect(skillMatchesKeyword(_defShape('library'), '图书使'), isTrue,
          reason: '顺序子序列');
      // 近义词新增能力（区别于原有能力）
      expect(skillMatchesKeyword(_defShape('spot_hidden'), '搜寻'), isTrue);
      expect(skillMatchesKeyword(_pickerShape('charm'), '讨好'), isTrue);
      expect(skillMatchesKeyword(_defShape('spot_hidden'), '这技能不存在'),
          isFalse);
    });

    testWidgets('B6 近义词不显示：结果行与搜索框都不出现近义词词表',
        (WidgetTester tester) async {
      await _pumpSkills(tester, _card());
      await tester.enterText(find.byKey(const Key('skill_search')), '魅惑');
      await tester.pumpAndSettle();
      // 命中「取悦」这一行（近义词生效）
      expect(find.byKey(const Key('skill_row_charm')), findsOneWidget,
          reason: '搜魅惑要能找到取悦');
      // 结果行文本里只有正式名，不含任何近义词
      final rowTexts = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('skill_row_charm')),
            matching: find.byType(Text),
          ))
          .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
          .join('\n');
      for (final word in <String>['魅惑', '讨好', '恭维', '迷人', 'charm']) {
        expect(rowTexts.contains(word), isFalse,
            reason: '近义词「$word」不该显示在界面上');
      }
      expect(rowTexts.contains('取悦'), isTrue);
      // 搜索框本身也不该把近义词写进 hintText / label
      final searchField = tester.widget<TextField>(
          find.byKey(const Key('skill_search')));
      final deco = searchField.decoration;
      final label = deco?.hintText ?? deco?.labelText ?? '';
      for (final word in <String>['魅惑', '讨好', '恭维', '迷人']) {
        expect(label.contains(word), isFalse);
      }
    });

    testWidgets('B7 任选技能弹窗（第二搜索框）也能用「魅惑」搜到「取悦」',
        (WidgetTester tester) async {
      final card = _card();
      final free = getRequirements(card)
          .firstWhere((r) => jsStr(r['type']) == 'free');
      final reqId = jsStr(free['id']);
      await _pumpSkills(tester, card);
      await _tapKey(tester, 'btn_pick_free_$reqId');
      expect(find.byKey(const Key('free_picker_search')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('free_picker_search')), '魅惑');
      await tester.pumpAndSettle();
      final tiles = find.byType(CheckboxListTile);
      expect(tiles, findsOneWidget,
          reason: '第二个搜索框必须真的生效（形状差异是本批最容易踩的坑）');
      expect(
          find.descendant(of: tiles, matching: find.text('取悦')),
          findsOneWidget);
      expect(
          find.descendant(of: tiles, matching: find.text('话术')),
          findsNothing);
      // 结果行不显示近义词
      final texts = tester
          .widgetList<Text>(find.descendant(
            of: tiles,
            matching: find.byType(Text),
          ))
          .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
          .join('\n');
      expect(texts.contains('魅惑'), isFalse);
      expect(texts.contains('讨好'), isFalse);
    });

    test('B8 结论：近义词不并入职业搜索（skillSearchText 保持原口径）', () {
      // 职业搜索 `occupation.dart#skillSearchText` 不会被本表污染：
      // 新增的近义词「search」在职业索引里搜不到，但在车卡技能搜索里能命中。
      final spot = _defShape('spot_hidden');
      expect(skillMatches(spot, 'search'), isFalse,
          reason: '职业搜索不应因近义词扩大索引（误命中会增多）');
      expect(skillMatchesKeyword(spot, 'search'), isTrue);
      expect(skillSearchText(spot).contains('search'), isFalse);
      // 职业解析里的「魅惑→charm」别名语义保持不动
      expect(skillMatches(_defShape('charm'), '魅惑'), isTrue,
          reason: '职业侧既有别名（occupation.dart:96）语义不变');
    });
  });
}
