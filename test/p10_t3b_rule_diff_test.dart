// ============================================================
// test/p10_t3b_rule_diff_test.dart — P10 第 3 期 B
//
// 「按老 APP 抹平跑团房间差异」实施批的**等价回归靶子 + 技术债反证**。
//
// 立场（team-lead 明确）：14 条里 12 条已判等价 —— 等价不是待改，
//   为凑工作量去动它们只会引入回归。所以本文件的主体是把老 APP 的
//   判据 / 顺序 / 载荷形状钉成断言，防未来漂移；只有对拍中发现的
//   真不等价（consent 的 check.request 分支）与技术债才改生产代码。
//
// ★ 铁律 T1：全部内存后端（roomHostOpts 的 LCG / InMemoryRoomSaveStore /
//   确定性规则），零 Timer / Future.delayed / AnimationController / 真实 I/O。
// ★ 跨视角：SendPlan 按 to 分发进两个真实 RoomClient，不只读权威端 state。
// ★ 探针前置：哨兵串先断言「本人 + KP 收得到」，再断言「第三人搜不到」，
//   长度刻意 < cleanText(label, 20) 的上限，避免被截断成假绿。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/character.dart' show newCharacter, Character;
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/madness_state.dart' as mental_state;
import 'package:dice_realm/domain/room_model_actions_combat.dart';
import 'package:dice_realm/domain/room_model_actions_room.dart'
    show raDeriveBodyFromHp;
import 'package:dice_realm/domain/room_model_actions_sheet.dart';
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_reduce.dart'
    show reduceGateWarnings, reduceRoomState;
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/repo/avatar_thumb.dart' show avatarThumbEncoder;
import 'package:dice_realm/ui/room/room_game_page.dart'
    show roomFoldedSlots, roomOrderedContentSlots;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/sheets/card_sheet_payload.dart'
    show cardToRoomSheetForReport;
import 'package:dice_realm/ui/room/view/room_view.dart' show RoomGridSpec;
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart'
    show autoAvatarPngEncoder;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

// ------------------------------------------------------------
// 脚手架
// ------------------------------------------------------------

Map<String, Object?> _sheet({
  num san = 50,
  num maxSan = 60,
  num hp = 10,
  num maxHp = 12,
  String body = '正常',
  List<Object?> mental = const <Object?>['正常'],
}) =>
    <String, Object?>{
      'name': '甲',
      'status': <String, Object?>{
        'currentHP': hp,
        'maxHP': maxHp,
        'currentSAN': san,
        'maxSAN': maxSan,
        'body': body,
        'dying': false,
        'unconscious': false,
      },
      'mental': mental,
      'madness': <Object?>[],
      'tempStatus': <Object?>[],
      'skills': <Object?>[
        <String, Object?>{'name': '侦查', 'total': 60, 'base': 60},
      ],
    };

RoomHost _host({int seed = 3}) {
  final h = RoomHost(roomHostOpts(seed: seed));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  h.roster.get('p1')!['sheet'] = _sheet();
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

void _boot(RoomHost h, Map<String, RoomClient> cs) {
  for (final e in cs.entries) {
    e.value.receive(h.syncFor(e.key).toJson());
  }
}

/// 只取一条出站 evt 的 {t,p}（跳过 skip / sync）。
Map<String, Object?>? _evt(SendPlan p, String t) {
  final m = p.msg.toJson();
  if (m['k'] != 'evt' || m['t'] != t) return null;
  return asMap(m['p']);
}

List<Map<String, Object?>> _evts(List<SendPlan> plans, String t) => <Map<String, Object?>>[
      for (final p in plans)
        if (_evt(p, t) != null) _evt(p, t)!,
    ];

void main() {
  setUp(() {
    // 机械闸门的告警缓冲是模块级的，清掉避免用例间串味。
    reduceGateWarnings.clear();
  });

  // ========================================================
  // 第 1 梯队 · D14 载荷装配（唯一未穷尽项，只对拍载荷，不重做判定核心）
  // 老：room-model.js:5811-5824 _emitOpposedCheck
  //     room-model.js:6346-6361 _opposedCheckPayload 的 return 形状
  //     room-rules.js:489-539 判定核心（QA 已逐分支判等价，本批不动）
  // 新：room_model_actions_combat.dart:1085-1110 emitOpposedCheck
  //     :1278-1310 / :1677-1708 / :2333-2360 三处载荷装配
  // ========================================================
  group('T1 · D14 对抗载荷形状（等价靶子）', () {
    test('T1-1 非秘密对抗：CHECK PUBLIC 载荷字段与老 APP 逐项同形', () {
      final h = _host();
      final plans = h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'aBase': 70,
        'bBase': 30,
        'aSkill': '侦查',
        'bSkill': '潜行',
        'aSeat': 'p1',
        'bSeat': 'p2',
      }));
      final checks = _evts(plans, RoomEvt.check);
      expect(checks, hasLength(1), reason: '非秘密 → 恰好一条 CHECK PUBLIC');
      final p = checks.single;
      // 老 APP `_opposedCheckPayload` return 的键集合（:6346-6361）
      expect(p.keys.toSet(), <String>{
        'id', 'kind', 'targets', 'skill', 'difficulty', 'a', 'b',
        'winner', 'tie', 'reaction', 'decidedBy', 'rounds', 'fallback',
        'damage', 'summary', 'at',
      });
      expect(p['kind'], 'opposed');
      expect(p['targets'], <Object?>['p1', 'p2']);
      expect(p['tie'], isFalse);
      expect(p['fallback'], isA<bool>());
      expect(p['rounds'], isA<List>());
      expect(p['damage'], isNull, reason: '纯技能对抗不绑伤害');
      expect(jsStr(p['decidedBy']).isNotEmpty, isTrue);
      expect(jsStr(p['summary']).contains('⚔ 对抗'), isTrue);
      for (final side in <String>['a', 'b']) {
        expect(asMap(p[side]).keys.toSet(),
            <String>{'ref', 'name', 'value', 'level', 'levelText'},
            reason: '$side 侧形状');
      }
      expect(plans.any((x) => x.to == '*' && _evt(x, RoomEvt.check) != null),
          isTrue, reason: '必须全员广播');
    });

    test('T1-2 秘密对抗：完整结果只 SEAT 给 KP，公共侧无 CHECK 载荷', () {
      final h = _host();
      final plans = h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'secret': true,
        'aBase': 70,
        'bBase': 30,
        'aSkill': '侦查',
        'bSkill': '潜行',
        'aSeat': 'p1',
        'bSeat': 'p2',
      }));
      expect(_evts(plans, RoomEvt.check), isEmpty,
          reason: '秘密对抗不得发 CHECK PUBLIC');
      final privates = <SendPlan>[
        for (final p in plans)
          if (_evt(p, RoomEvt.private_) != null) p,
      ];
      // 完整结果那条必须是 SEAT→KP（其余可能是系统提示，别误当泄漏）
      final full = privates
          .where((p) => _evt(p, RoomEvt.private_)!['kind'] == 'opposed')
          .toList();
      expect(full, hasLength(1));
      expect(full.single.to, kHostSeat);
      expect(privates.every((p) => p.to != '*'), isTrue,
          reason: '任何私密载荷都不许走广播');
      final logs = _evts(plans, RoomEvt.log);
      expect(logs.any((l) => jsStr(l['text']).contains('KP 秘密进行了一次对抗检定')),
          isTrue);
      expect(logs.any((l) => jsStr(l['text']).contains('⚔ 对抗')), isFalse,
          reason: '公共日志不能带完整结果');
    });

    test('T1-4 targets 按老 APP `.filter(Boolean)` 口径滤空值（静态形状靶子）', () {
      // `aSeat` 为空时 `resolveActorSkill` 会先判「甲方无效」而提前返回，
      // 所以这条形状差异**在现有意图入口不可达**，只能靠源码靶子钉住：
      // 老 :5888 `[p.aSeat, p.bSeat].filter(Boolean)` vs 改前 Dart 的
      // `.where((x) => x != null)`（空串 / 0 / false 会留下）。
      final src = File('lib/domain/room_model_actions_combat.dart')
          .readAsStringSync();
      final start = src.indexOf("'targets': <Object?>[p['aSeat'], p['bSeat']]");
      expect(start, greaterThanOrEqualTo(0));
      final block = src.substring(start, start + 220);
      expect(block.contains('.where(jsTruthy)'), isTrue,
          reason: '必须按老 APP filter(Boolean) 口径滤 falsy');
      // 正常入参仍逐项落在 targets（行为正例，别只靠静态断言）
      final h = _host();
      final p = _evts(h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'aBase': 70,
        'bBase': 30,
        'aSkill': '侦查',
        'bSkill': '潜行',
        'aSeat': 'p1',
        'bSeat': 'p2',
      })), RoomEvt.check).single;
      expect(p['targets'], <Object?>['p1', 'p2']);
    });

    test('T1-5 秘密对抗兜底按老 APP `summary || … / at || now()` 的 falsy 口径', () {
      final h = _host();
      final out = <SendPlan>[];
      h.emitOpposedCheck(out, <String, Object?>{
        'summary': '', // Dart 的 `??` 不会兜底，老 APP 的 `||` 会
        'at': 0,
      }, true);
      final priv = _evts(out, RoomEvt.private_).single;
      expect(priv['text'], '（秘密对抗）');
      expect(priv['at'], isA<num>(), reason: 'at=0 应回落为当前时钟，不能是 0');
      expect(priv['at'], greaterThan(0));
      final log = _evts(out, RoomEvt.log).single;
      expect(log['at'], greaterThan(0));
    });

    test('T1-3 跨视角：p1/p2 两个真实 RoomClient 都拿到 9 键 opp 卡', () {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);
      final plans = h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'aBase': 70,
        'bBase': 30,
        'aSkill': '侦查',
        'bSkill': '潜行',
        'aSeat': 'p1',
        'bSeat': 'p2',
      }));
      _deliver(plans, cs);
      for (final entry in cs.entries) {
        final logs = asList(entry.value.state['logs']).map(asMap).toList();
        final row = logs.lastWhere((l) => jsStr(l['kind']) == 'check');
        expect(jsTruthy(row['redacted']), isFalse);
        final opp = asMap(row['opp']);
        // reduce 里钉住的 9 键，与老 APP 展示层同一口径
        expect(opp.keys.toSet(), <String>{
          'a', 'b', 'winner', 'tie', 'reaction', 'decidedBy',
          'fallback', 'rounds', 'damage',
        }, reason: '${entry.key} 视角');
        expect(asMap(opp['a'])['name'], isNotNull);
        expect(asMap(opp['b'])['name'], isNotNull);
      }
    });
  });

  // ========================================================
  // 第 1 梯队 · D03 伤害 → 身体状态（订正后真身）
  // 老：room-model.js:4275-4327 deriveBodyFromHp（:2216-2270 只是调用点）
  // 新：room_model_actions_room.dart:246-296 raDeriveBodyFromHp
  //     （sheet.dart:817-880 只是调用点）
  // ========================================================
  group('T2 · D03 伤害判定 7 分支（等价靶子）', () {
    test('T2-1 逐分支对拍老 APP :4275-4327', () {
      const unset = Object();
      Object? v(Map<String, Object?> r, String k) =>
          r.containsKey(k) ? r[k] : unset;

      // #1 即死：三键显式落位
      final r1 = raDeriveBodyFromHp('正常', 13, 0, 12);
      expect(v(r1, 'body'), '死亡');
      expect(v(r1, 'dying'), false);
      expect(v(r1, 'unconscious'), false);

      // #3a 归零且有重伤 → 濒死
      final r3a = raDeriveBodyFromHp('正常', 6, 0, 12);
      expect(v(r3a, 'body'), '重伤');
      expect(v(r3a, 'dying'), true);

      // #3b 归零且无重伤 → 昏迷
      final r3b = raDeriveBodyFromHp('正常', 2, 0, 12);
      expect(v(r3b, 'unconscious'), true);
      expect(v(r3b, 'body'), unset, reason: 'body 保持改前伤级');

      // #2 重伤 + 首次重伤要掷 CON；改前已重伤不再掷
      final r2 = raDeriveBodyFromHp('正常', 6, 6, 12);
      expect(v(r2, 'body'), '重伤');
      expect(v(r2, 'dying'), false);
      expect(r2['needCon'], true);
      expect(raDeriveBodyFromHp('重伤', 6, 6, 12)['needCon'], false);

      // #5 改前濒死且 after>0 → 脱离濒死；回血 ≥ 半血则轻伤/正常
      expect(v(raDeriveBodyFromHp('濒死', -1, 12, 12), 'body'), '正常');
      expect(v(raDeriveBodyFromHp('濒死', -1, 8, 12), 'body'), '轻伤');
      expect(v(raDeriveBodyFromHp('濒死', -1, 3, 12), 'body'), '重伤');

      // #6 改前重伤且回血 ≥ 半血 → 解除重伤；不足则「全保持」
      expect(v(raDeriveBodyFromHp('重伤', -1, 12, 12), 'body'), '正常');
      final r6 = raDeriveBodyFromHp('重伤', -1, 3, 12);
      expect(v(r6, 'body'), unset);
      expect(v(r6, 'dying'), unset);
      expect(v(r6, 'unconscious'), unset);

      // #7 昏迷不降级
      final r7 = raDeriveBodyFromHp('昏迷', 2, 10, 12);
      expect(v(r7, 'body'), unset);
      expect(r7['needCon'], false);

      // #8 其余：HP<上限 → 轻伤；≥上限 → 正常
      expect(v(raDeriveBodyFromHp('正常', 2, 10, 12), 'body'), '轻伤');
      expect(v(raDeriveBodyFromHp('正常', 0, 12, 12), 'body'), '正常');
    });
  });

  // ========================================================
  // 第 1 梯队 · D08/D09 疯狂链
  // 老：room-model.js:5160-5271（公式 :5242-5245）、:882-886 武装、
  //     :996-1001 回合边界 disarm
  // 新：room_model_actions_sheet.dart:1274-1279、:1912；
  //     room_model_host_core.dart:118-119 / 198-212
  // ========================================================
  group('T3 · D08/D09 疯狂链（等价靶子）', () {
    test('T3-1 潜在疯狂 + 武装 + 任意损失 → 复发并新生一条症状', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = _sheet(
          mental: <Object?>['潜在疯狂']);
      h.fadedArm['p1'] = true;
      h.intent(kHostSeat, _act('sheet.sanloss', <String, Object?>{
        'seat': 'p1',
        'loss': 1,
      }));
      final mental = asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
      expect(mental.contains('不定疯狂'), isTrue);
      expect(mental.contains('潜在疯狂'), isFalse, reason: '两者互斥');
      expect(asList(asMap(h.roster.get('p1')!['sheet'])['madness']), isNotEmpty,
          reason: '必须新生成一条疯狂症');
    });

    test('T3-3 潜在疯狂 + 单次损失 ≥5 → 只走复发，不叠加临时疯狂 INT 路径', () {
      // 老 APP v2.13.13 `room-model.js:5198` = `if (loss >= 5 && !isFaded)`；
      // 改前新工程少了 `!isFaded`，会同时触发 ②（临时疯狂）与 ④（复发）
      // 两条路径，一次拿到 2 个症状 + 临时疯狂标签。
      final h = _host();
      h.roster.get('p1')!['sheet'] = _sheet(
          mental: <Object?>['潜在疯狂']);
      h.fadedArm['p1'] = true;
      final plans = h.afterSanLoss(h.roster.get('p1')!, 6, kHostSeat);
      final labels = _evts(plans, RoomEvt.dice)
          .map((d) => jsStr(d['label']))
          .toList();
      expect(labels.any((l) => l.startsWith('临时疯狂 INT 检定')), isFalse,
          reason: '潜在疯狂态不得再触发临时疯狂 INT 路径（老 :5198）');
      // ④ 复发分支发的是公共 warn 日志（不是骰子），别用「有骰」当正例
      expect(
          _evts(plans, RoomEvt.log)
              .any((l) => jsStr(l['text']).contains('复发')),
          isTrue,
          reason: '④ 复发仍要发公共事件，不能整体静默');
      final mental = asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
      expect(mental.contains('不定疯狂'), isTrue);
      expect(mental.contains('临时疯狂'), isFalse);
      expect(asList(asMap(h.roster.get('p1')!['sheet'])['madness']), hasLength(1),
          reason: '只新生一条症状，不许双份');
    });

    test('T3-2 回合推进 disarm 后，1 点损失不再复发（新旧取值都覆盖）', () {
      for (final state in <String>['潜在疯狂', '不定疯狂（症状消失）']) {
        final h = _host();
        h.roster.get('p1')!['sheet'] = _sheet(mental: <Object?>[state]);
        h.fadedArm['p1'] = true;
        h.intent(kHostSeat, _act('round.next', const <String, Object?>{}));
        expect(h.fadedArm['p1'], isFalse, reason: '$state 应被 disarm');
        h.intent(kHostSeat, _act('sheet.sanloss', <String, Object?>{
          'seat': 'p1',
          'loss': 1,
        }));
        final mental = asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
        expect(mental.contains('不定疯狂'), isFalse,
            reason: '$state：1 点 < ceil(60/5)=12，不该复发');
      }
      // 状态机判据是唯一真相（不是把两个字面量各加一遍）
      expect(mental_state.isPotentialMadness(<Object?>['不定疯狂（症状消失）']),
          isTrue);
      expect(mental_state.isPotentialMadness(<Object?>['不定疯狂']), isFalse);
    });
  });

  // ========================================================
  // 第 1 梯队 · 其余 D 项等价靶子
  // ========================================================
  group('T4 · D01/D02/D04/D05/D06/D07/D10/D12/D13 等价靶子', () {
    test('T4-1 D01/D02 先攻顺序 + 多行动展开（老 :2423-2450）', () {
      final h = _host();
      final res = h.initiativeFallback(<Object?>[
        <String, Object?>{'id': 'a', 'name': 'A', 'dex': 40},
        <String, Object?>{'id': 'b', 'name': 'B', 'dex': 70, 'readyFirearm': true},
        <String, Object?>{'id': 'c', 'name': 'C', 'dex': 60, 'manualOrder': 0},
        <String, Object?>{'id': 'd', 'name': 'D', 'dex': 55, 'actionsPerRound': 2},
      ]);
      final order = asList(res['order']).map(asMap).toList();
      // manualOrder 优先 → effDex(备枪 +50) 降序 → dex 降序
      expect(order.map((x) => x['id']).toList(),
          <Object?>['c', 'b', 'd', 'd', 'a']);
      expect(asList(res['order']).last is Map, isTrue);
      final d1 = order[2];
      expect(d1['slot'], 1);
      expect(d1['totalSlots'], 2);
      expect(order[3]['slot'], 2);
      expect(asMap(order[1])['effDex'], 120);
    });

    test('T4-2 D04 重伤瞬间掷「避免昏迷」CON（老 :2265-2267）', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = _sheet(hp: 12, maxHp: 12);
      final plans = h.intent(kHostSeat, _act('sheet.damage', <String, Object?>{
        'seat': 'p1',
        'amount': 6,
      }));
      final dice = _evts(plans, RoomEvt.dice);
      expect(dice.any((d) => jsStr(d['label']).startsWith('重伤 CON 检定')),
          isTrue, reason: '净下降 ≥ 半血要掷 CON');
      expect(asMap(h.roster.get('p1')!['sheet'])['status'], isA<Object?>());
    });

    test('T4-3 D05/D06 天/周恢复：日 +1HP，重伤不做日恢复；advance 不触发', () {
      final h = _host();
      // 正常成员：每推进 1 回合 +1HP
      h.roster.get('p1')!['sheet'] = _sheet(hp: 8, maxHp: 12);
      h.advanceRound(1);
      expect(raMemberStatusValueForTest(h, 'p1', 'currentHP'), 9);
      // 重伤成员：不做日恢复
      h.roster.get('p2')!['sheet'] = _sheet(
          hp: 5, maxHp: 12, body: '重伤');
      h.advanceRound(2);
      expect(raMemberStatusValueForTest(h, 'p2', 'currentHP'), 5,
          reason: '重伤不每日恢复（老 :3695-3700）');
      // madness.advance 不 emit ROUND → 不触发天/周恢复
      final before = raMemberStatusValueForTest(h, 'p1', 'currentHP');
      h.intent(kHostSeat, _act('madness.advance', <String, Object?>{
        'seat': 'p1',
      }));
      expect(raMemberStatusValueForTest(h, 'p1', 'currentHP'), before);
    });

    test('T4-4 D07 单次 SAN 损失 ≥5 → INT 检定（老 :5160-5271）', () {
      final h = _host(seed: 5);
      // 直接调规则真身 `afterSanLoss`（`sheet.sanloss` 是骰式入口，损失量由
      // 权威端 rng 决定，不适合钉「≥5」这条分界）。
      final plans = h.afterSanLoss(h.roster.get('p1')!, 5, kHostSeat);
      final dice = _evts(plans, RoomEvt.dice);
      expect(dice.any((d) => jsStr(d['label']).startsWith('临时疯狂 INT 检定')),
          isTrue);
    });

    test('T4-5 D10 临时/不定疯狂期间不获新症状；D12 SAN 归零 → 永久疯狂', () {
      expect(mental_state.blockedFromNewSymptom(<Object?>['临时疯狂']), isTrue);
      expect(mental_state.blockedFromNewSymptom(<Object?>['不定疯狂']), isTrue);
      expect(mental_state.blockedFromNewSymptom(<Object?>['潜在疯狂']), isFalse);
      final h = _host();
      asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentSAN'] = 0;
      h.afterSanLoss(h.roster.get('p1')!, 60, kHostSeat);
      final sheet = asMap(h.roster.get('p1')!['sheet']);
      expect(asList(sheet['mental']).contains('永久疯狂'), isTrue);
    });

    test('T4-6 D13 技能表上限 200（信用评级不被截断，老 :7283-7298）', () {
      final skills = <Object?>[
        for (var i = 0; i < 205; i++)
          <String, Object?>{'name': '技能$i', 'total': 50},
      ];
      final out = raSanitizeSheet(<String, Object?>{
        'name': '甲',
        'skills': skills,
      }, null, 1);
      expect(asList(out['skills']), hasLength(200));
    });
  });

  // ========================================================
  // 第 2 梯队 · 技术债 5：reduce 侧 DICE 机械闸门
  // ========================================================
  group('T5 · reduce DICE 机械闸门（K3 安全项）', () {
    test('T5-1 非 PUBLIC 的 DICE 被丢弃并记 warning；PUBLIC/null 不受影响', () {
      final h = _host();
      // ① 非 PUBLIC（KP 本地）：不得进公共骰列
      h.emit(RoomEvt.dice, <String, Object?>{
        'seat': 'p1',
        'expr': '1D100',
        'label': 'SENTINEL_SKILL',
        'total': 42,
        'levelText': '常规成功',
        'at': 1,
      }, vis: RoomVis.kp);
      expect(asList(h.state['dice']), isEmpty,
          reason: '机械闸门：非 PUBLIC 不写 state.dice');
      expect(h.warnings.any((w) => w.t == RoomEvt.dice &&
              w.reason.contains('非 PUBLIC')),
          isTrue, reason: '必须留一条告警');
      expect(jsonEncodeForTest(h.state).contains('SENTINEL_SKILL'), isFalse);

      // ② 非 PUBLIC（SEAT）同样丢弃
      h.emit(RoomEvt.dice, <String, Object?>{
        'seat': 'p1',
        'expr': '1D100',
        'label': 'SENTINEL_SKILL',
        'at': 2,
      }, vis: RoomVis.seat, to: 'p1');
      expect(asList(h.state['dice']), isEmpty);

      // ③ PUBLIC 正常写入
      h.emit(RoomEvt.dice, <String, Object?>{
        'seat': 'p1',
        'expr': '1D6',
        'total': 3,
        'at': 3,
      }, vis: RoomVis.public);
      expect(asList(h.state['dice']), hasLength(1));

      // ④ vis == null（客户端回放 / 旧调用）保持旧口径：按 PUBLIC 处理
      reduceRoomState(h.state, RoomEvent(
        t: RoomEvt.dice,
        seq: 999,
        p: <String, Object?>{'seat': 'p1', 'expr': '1D6', 'at': 4},
      ));
      expect(asList(h.state['dice']), hasLength(2));
    });

    test('T5-2 不误伤正常秘密骰点：暗骰走 PRIVATE(SEAT)，本人+KP 收得到', () {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);
      // 探针前置：哨兵 12 字符，短于 cleanText(label,20) 上限，不会被截断成假绿
      const sentinel = 'SECRET_LBL';
      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'direct': true,
          'secret': true,
          'label': sentinel,
        },
      });
      _deliver(plans, cs);
      // 前置：本人 + KP 确实收得到完整结果
      expect(jsonEncodeForTest(cs['p1']!.state).contains(sentinel), isTrue,
          reason: '探针前置：本人必须收得到，否则「没泄漏」是空话');
      expect(jsonEncodeForTest(h.syncFor(kHostSeat).state).contains(sentinel),
          isTrue, reason: '探针前置：KP 必须收得到');
      // 第三人零命中
      expect(jsonEncodeForTest(cs['p2']!.state).contains(sentinel), isFalse);
      expect(asList(cs['p2']!.state['dice']), isEmpty);
      expect(asList(cs['p2']!.state['privates']), isEmpty);
      // 公共侧仍有脱敏提示
      final logs = asList(cs['p2']!.state['logs'])
          .map((e) => jsStr(asMap(e)['text']))
          .join('\n');
      expect(logs.contains('暗骰了一次'), isTrue);
      expect(logs.contains('只有他/她与 KP 可见'), isTrue);
    });

    test('T5-3 秘密对抗（check.opposed secret）第三人零命中', () {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);
      const sentinel = 'SECRET_SK';
      final plans = h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'secret': true,
        'skill': sentinel,
        'a': <String, Object?>{
          'side': 'pc',
          'seat': 'p1',
          'skill': sentinel,
        },
        'b': <String, Object?>{'side': 'monster', 'name': '怪', 'value': 40},
      }));
      _deliver(plans, cs);
      expect(jsonEncodeForTest(cs['p2']!.state).contains(sentinel), isFalse);
      expect(asList(cs['p2']!.state['dice']), isEmpty);
    });
  });

  // ========================================================
  // 第 2 梯队 · 技术债 6/7：data: URI 边界 / 陈旧前提
  // ========================================================
  group('T6 · 绑卡上报的 data: URI 与降级路径', () {
    test('T6-1 卡头像已是 PNG dataURI → 上报仍带该 avatar（不再误删）', () async {
      const png = 'data:image/png;base64,AAAB';
      const thumb = 'data:image/png;base64,AAAC';
      final saved = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = saved);
      Object? seen;
      avatarThumbEncoder = (Object? raw) async {
        seen = raw;
        return jsStr(raw) == png ? thumb : '';
      };
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      autoAvatarPngEncoder = (spec) async => '';

      final card = Character(newCharacter());
      card.raw['id'] = 'c20';
      card.raw['characterName'] = '张三';
      card.raw['avatar'] = png;
      final sheet = await cardToRoomSheetForReport(card);
      expect(seen, png, reason: '必须把原始值交给缩略链路，不要先过 localAvatarRel');
      expect(sheet['avatar'], thumb);
    });

    test('T6-2 降级路径：两条生成器都拿不到东西 → 删 avatar 键（不占广播体积）',
        () async {
      final saved = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = saved);
      avatarThumbEncoder = (Object? _) async => '';
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      autoAvatarPngEncoder = (spec) async => '';

      final card = Character(newCharacter());
      card.raw['id'] = 'c21';
      card.raw['characterName'] = '李四';
      card.raw['avatar'] = '';
      final sheet = await cardToRoomSheetForReport(card);
      expect(sheet.containsKey('avatar'), isFalse);
      expect(sheet['name'], isNotNull, reason: '其余字段照常上报，绑卡不失败');
    });
  });

  // ========================================================
  // 第 2 梯队 · 技术债 8：consent 的 check.request 分支（真差异，按老 APP 修）
  // 老：room-model.js:1546-1569 consent + :3106-3131 _rollCheckRequest
  // 新：room_model_host_intent.dart consent（本批接线）
  // ========================================================
  group('T7 · consent → rollCheckRequest（真差异修复）', () {
    test('T7-1 玩家同意检定请求 → 权威代掷 D100 并 PUBLIC 广播（跨视角）', () {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);
      h.intent(kHostSeat, _act('check.request', <String, Object?>{
        'seat': 'p1',
        'skill': '侦查',
        'difficulty': 'REGULAR',
      }));
      // check.request 自己也会产出 SEAT/skip 事件：把两个视角的水位重新对齐，
      // 否则接下来的 consent 增量会被 gate 判成跳号而整批丢弃。
      _boot(h, cs);
      final reqs = h.requestsBySeat['p1'];
      expect(reqs, isNotNull);
      expect(reqs, hasLength(1));
      final id = jsStr(reqs!.single['id']);

      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.consent,
        'p': <String, Object?>{'id': id, 'agree': true},
      });
      _deliver(plans, cs);

      // ① 结果骰：PUBLIC，label 为技能名，带成功等级
      final dice = _evts(plans, RoomEvt.dice);
      expect(dice, hasLength(1), reason: '同意后必须真的掷一次 D100');
      expect(jsStr(dice.single['label']), '侦查');
      expect(jsStr(dice.single['levelText']).isNotEmpty, isTrue);
      expect(plans.any((p) => p.to == '*' && _evt(p, RoomEvt.dice) != null),
          isTrue);
      // ② 跨视角：p2 也拿到这颗骰
      expect(asList(cs['p2']!.state['dice'])
              .any((e) => jsStr(asMap(e)['label']) == '侦查'),
          isTrue, reason: '结果广播全员（老 :3106-3131）');
      // ③ 摘卡：待办表空 + REQUEST-done 定向给本人
      expect(h.requestsBySeat['p1'], isEmpty);
      expect(plans.any((p) =>
              p.to == 'p1' &&
              _evt(p, RoomEvt.request) != null &&
              _evt(p, RoomEvt.request)!['done'] == true),
          isTrue);
      // ④ 公共日志说明「同意并完成了…检定」
      final logs = _evts(plans, RoomEvt.log);
      expect(logs.any((l) => jsStr(l['text']).contains('同意并完成了「侦查」检定')),
          isTrue);
      // ⑤ 绝不能退化成「KP 调整了…的状态」
      expect(logs.any((l) => jsStr(l['text']).contains('调整了')), isFalse);
    });

    test('T7-2 拒绝检定请求 → 不掷骰、只摘卡', () {
      final h = _host();
      h.intent(kHostSeat, _act('check.request', <String, Object?>{
        'seat': 'p1',
        'skill': '侦查',
      }));
      final id = jsStr(h.requestsBySeat['p1']!.single['id']);
      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.consent,
        'p': <String, Object?>{'id': id, 'agree': false},
      });
      expect(_evts(plans, RoomEvt.dice), isEmpty);
      expect(h.requestsBySeat['p1'], isEmpty);
    });

    test('T7-3 权威目标值：角色卡技能值优先于请求载荷 base', () {
      final h = _host();
      h.intent(kHostSeat, _act('check.request', <String, Object?>{
        'seat': 'p1',
        'skill': '侦查',
        'base': 10,
      }));
      // checkRequest 自己会先按权威角色卡解析 base
      final payload = asMap(h.requestsBySeat['p1']!.single['payload']);
      expect(payload['base'], 60,
          reason: '权威角色卡里的「侦查=60」应压过 KP 请求里手填的 base');
    });

    test('T7-4 check.push 与 check.request 同行为（老 APP 无处理器，保留增强）', () {
      final h = _host();
      h.intent(kHostSeat, _act('check.push', <String, Object?>{
        'seat': 'p1',
        'skill': '图书馆使用',
      }));
      expect(h.requestsBySeat['p1'], hasLength(1));
      expect(jsStr(h.requestsBySeat['p1']!.single['op']), 'check.request');
    });
  });

  // ========================================================
  // 第 3 梯队 · 技术债 9/10：折叠档顺序接线 + 视口高度
  // ========================================================
  group('T8 · 折叠档顺序接线与视口高度', () {
    test('T8-1 纯函数已接进 _foldedContent（不是只被单测调用的死代码）', () {
      final src = File('lib/ui/room/room_game_page.dart').readAsStringSync();
      expect(src.contains('final squares = roomOrderedContentSlots('), isTrue,
          reason: '接线回归靶子');
      final single = RoomGridSpec.of(w: 360, h: 640, landscape: false);
      final chain = roomOrderedContentSlots(
        roomFoldedSlots(RoomKeys.kpSlots, RoomRole.kp),
        single,
      );
      expect(chain.first, RoomSlot.gpPriv);
      expect(chain.contains(RoomSlot.gpToolbar), isFalse);
      final grid = RoomGridSpec.of(w: 780, h: 400, landscape: true);
      final gridChain = roomOrderedContentSlots(
        roomFoldedSlots(RoomKeys.kpSlots, RoomRole.kp),
        grid,
      );
      expect(gridChain.first, isNot(RoomSlot.gpPriv),
          reason: '多列档保持槽位表原序');
    });

    test('T8-2 视口最小高度判据已存在（压成一条缝不能算通过）', () {
      final src = File('test/room_ui_layout_test.dart').readAsStringSync();
      expect(src.contains('viewport.height, greaterThan(120)'), isTrue);
    });
  });
}

// ------------------------------------------------------------
// 小工具
// ------------------------------------------------------------

/// 从权威端成员表里读一个 status 值（避免 import 内部 ra* 私有函数）。
Object? raMemberStatusValueForTest(RoomHost h, String seat, String key) {
  final sheet = h.roster.get(seat)?['sheet'];
  return sheet is Map ? asMap(asMap(sheet)['status'])[key] : null;
}

String jsonEncodeForTest(Object? v) => const JsonLikeEncoder().encode(v);

/// 不用 dart:convert 的 jsonEncode：这里只需要「把整棵 state 展平成可搜字符串」，
/// 用递归拼接即可（List/Map/num/String/bool/null 全覆盖，无循环引用）。
class JsonLikeEncoder {
  const JsonLikeEncoder();

  String encode(Object? v) {
    final buf = StringBuffer();
    _write(buf, v);
    return buf.toString();
  }

  void _write(StringBuffer b, Object? v) {
    if (v == null) {
      b.write('null');
    } else if (v is Map) {
      b.write('{');
      for (final e in v.entries) {
        b.write('${e.key}:');
        _write(b, e.value);
        b.write(',');
      }
      b.write('}');
    } else if (v is Iterable) {
      b.write('[');
      for (final e in v) {
        _write(b, e);
        b.write(',');
      }
      b.write(']');
    } else {
      b.write(v.toString());
    }
  }
}
