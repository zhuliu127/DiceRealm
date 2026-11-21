// ============================================================
// test/p11_lifecycle_test.dart — P11：房间规则层「生命周期 / 回退」两处缺陷的回归靶子
//
//   缺陷 1（`closeRoom` / `endSession`）：结团 / 关房后只 `pending.clear()`，
//     不清 `state['combat']` 与 `requestsBySeat`。`closed` / `ended` 是终态但
//     **房间对象还在**（续玩、导出历史都靠它），于是续玩同一间房时房间仍停在
//     战斗态、玩家侧还挂着一张「待你确认」的幽灵卡片（重连 /sync 原样推回去）。
//
//   缺陷 2（`rollback`）：回退恢复 state 后不重算三张「回合内累计型」表：
//     · `sanLostThisRound` / `roundStartSan`（不定疯狂阈值 ceil(maxSAN/5) 的分母侧）
//     · `fireUsed`（连发惩罚骰依据）
//     · `fadedArm`（潜在疯狂「本回合任意损失即复发」的武装开关）
//     它们不进快照（`RoomSnapshot` 只有 seq + state），只能按幸存日志重扫。
//     不重算 → 回退后仍带着「未来那一回合」的累计：阈值判高、回退后这一枪打
//     不出去、该复发的不复发。
//
// ★ 铁律：全内存后端（`roomHostOpts()` 固定时钟 + LCG + 确定性规则/疯狂表）、
//   零真实 I/O、不用 Future.delayed、不放宽任何断言。
// ★ 反向自证伪（见报告 `_p11_lifecycle_report.md`）：把 `_clearTransientOnLifecycleEnd`
//   的 combat 清理行去掉 / 把 `_realignRoundScopedState` 调用去掉 → 本文件必须变红。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsNum;
// 这几个方法都是 `extension ... on RoomHost`，必须 import 定义库才可见。
import 'package:dice_realm/domain/room_model_actions_sheet.dart'
    show RoomHostActionsSheet;
import 'package:dice_realm/domain/room_model_host_core.dart' show RoomHost;
import 'package:dice_realm/domain/room_model_rollback.dart' show RoomHostRollback;
import 'package:dice_realm/domain/room_model_save.dart' show RoomHostSave;
import 'package:dice_realm/domain/room_types.dart'
    show kHostSeat, RoomEvt, RoomStatus, RoomVis, SendPlan;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

// ------------------------------------------------------------
// 脚手架（形状抄自 p11_fix2_sheet_test.dart / p10_t3b_rule_diff_test.dart）
// ------------------------------------------------------------

Map<String, Object?> _sheet({
  num san = 50,
  num maxSan = 60,
  num hp = 10,
  num maxHp = 12,
  List<Object?> mental = const <Object?>['正常'],
  List<Object?> madness = const <Object?>[],
}) =>
    <String, Object?>{
      'name': '甲',
      'status': <String, Object?>{
        'currentHP': hp,
        'maxHP': maxHp,
        'currentSAN': san,
        'maxSAN': maxSan,
        'body': '正常',
        'dying': false,
        'unconscious': false,
      },
      'mental': mental,
      'madness': madness,
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

/// 从出站计划里挑第一个 SYNC 信封的内部 state（重连视角）。
Map<String, Object?>? _syncState(List<SendPlan> plans) {
  for (final p in plans) {
    final m = p.msg.toJson();
    if (m['k'] == 'sync') return asMap(m['state']);
  }
  return null;
}

/// 某一条出站 evt 的 `{t,p}`（跳过 sync / skip），用于断言「没多冒事件」。
List<Map<String, Object?>> _evts(List<SendPlan> plans, String t) => <Map<String, Object?>>[
      for (final p in plans)
        if (p.msg.toJson()['k'] == 'evt' && p.msg.toJson()['t'] == t)
          asMap(p.msg.toJson()['p']),
    ];

/// ROUND 事件的水位（`advanceRound` 之后按回合号反查，避免写死 seq）。
int _roundSeq(RoomHost h, int round) {
  for (var i = h.log.items.length - 1; i >= 0; i--) {
    final r = h.log.items[i];
    if (r.evt.t == RoomEvt.round && r.evt.p['round'] == round) return r.seq;
  }
  throw StateError('日志里没有第 $round 回合的 ROUND 事件');
}

/// 一次真实链路的 SAN 损失：先 stateApply 写新 currentSAN，再 afterSanLoss 判疯狂
/// （顺序与 `sanCheck` / 精神分析失败 / 改 SAN 后判疯狂完全一致）。
void _sanLoss(RoomHost h, int loss) {
  final m = h.roster.get('p1')!;
  final before = jsNum(asMap(asMap(m['sheet'])['status'])['currentSAN']);
  h.stateApply(
    'p1',
    <String, Object?>{
      'status': <String, Object?>{'currentSAN': before - loss},
    },
    <String, Object?>{'reason': 'SAN Check 0/1D6 -$loss'},
  );
  h.afterSanLoss(m, loss, kHostSeat);
}

/// 开一段最小战斗态（reduce 的 COMBAT 分支：`state['combat'] = clone(p['combat'])`）。
void _startCombat(RoomHost h) => h.emit(
      RoomEvt.combat,
      <String, Object?>{
        'combat': <String, Object?>{
          'round': 1,
          'turn': 0,
          'order': <Object?>[
            <String, Object?>{'actorId': 'a1', 'name': '甲', 'seat': 'p1', 'done': false},
          ],
        },
      },
      vis: RoomVis.public,
    );

/// 挂一张 KP 发起的「待你确认」请求（requestsBySeat + pending + state.requests 三处同时落）。
void _pendingRequest(RoomHost h) => h.stateRequest(kHostSeat, <String, Object?>{
      'seat': 'p1',
      'change': <String, Object?>{
        'status': <String, Object?>{'currentHP': 8},
      },
      'reason': '测试：待确认',
    });

void main() {
  // ==========================================================
  // 缺陷 1 — 结团 / 关房后清「房间本轮进行态」
  // ==========================================================
  group('L1 结团/关房：清战斗态与逐座位待办', () {
    test('L1-1 endSession：战斗态归 null、待办请求清空，成员/日志/ended 不受影响', () {
      final h = _host();
      _startCombat(h);
      _pendingRequest(h);
      final membersBefore = h.roster.dump().length;
      final logsBefore = h.log.items.length;

      // 前提：缺陷现场确实存在
      expect(h.state['combat'], isNotNull, reason: '前提：战斗进行中');
      expect(h.requestsBySeat['p1'], isNotEmpty, reason: '前提：p1 挂着待确认请求');
      expect(h.pending, isNotEmpty, reason: '前提：待确认队列非空');

      final out = h.endSession();

      expect(h.state['combat'], isNull,
          reason: '结团后房间仍在（续玩/导出），战斗态必须回到 emptyRoomState 的初值 null');
      expect(h.requestsBySeat, isEmpty, reason: '逐座位待办请求表必须清空');
      expect(h.pending, isEmpty);

      // 存档里也不许留：否则续玩 / adoptSave 会把战斗态与待办「复活」
      final saved = h.save();
      expect(asMap(saved['state'])['combat'], isNull,
          reason: '存档 state.combat 必须是 null');
      expect(asMap(saved['requestsBySeat']), isEmpty,
          reason: '存档 requestsBySeat 必须是空表');

      final meta = asMap(h.state['meta']);
      expect(meta['ended'], isTrue, reason: 'ENDED 才写 meta.ended（口径不变）');
      expect(meta['status'], RoomStatus.closed);
      expect(h.roster.dump().length, membersBefore,
          reason: '花名册是历史，不许被清（结团后用户还要看谁玩过）');
      expect(h.log.items.length, greaterThan(logsBefore),
          reason: '日志只增不减（历史导出靠它）');
      expect(_evts(out, RoomEvt.ended), hasLength(1),
          reason: '出站计划形状不变：一条 ENDED，不多冒第二条事件');
    });

    test('L1-2 closeRoom：同样清战斗态与待办，但 meta.ended 仍不置真', () {
      final h = _host();
      _startCombat(h);
      _pendingRequest(h);
      expect(h.state['combat'], isNotNull, reason: '前提：战斗进行中');

      h.closeRoom();

      expect(h.state['combat'], isNull);
      expect(h.requestsBySeat, isEmpty);
      expect(h.pending, isEmpty);
      final meta = asMap(h.state['meta']);
      expect(meta['status'], RoomStatus.closed);
      expect(meta.containsKey('ended'), isFalse,
          reason: 'CLOSED 语义不变：不写 meta.ended（旧客户端把它当终止）');
    });

    test('L1-3 幂等：closeRoom / endSession 连调两次不抛错、状态不变', () {
      final h = _host();
      _startCombat(h);
      _pendingRequest(h);

      h.closeRoom();
      final afterFirst = <String, Object?>{
        'combat': h.state['combat'],
        'requestsBySeat': jsonEncode(h.save()['requestsBySeat']),
        'members': jsonEncode(h.roster.dump()),
      };
      // 第二次（以及关房后再结团）都不许炸
      expect(() => h.closeRoom(), returnsNormally);
      expect(() => h.endSession(), returnsNormally);
      expect(() => h.endSession(), returnsNormally);

      expect(h.state['combat'], isNull);
      expect(h.requestsBySeat, isEmpty);
      expect(jsonEncode(h.save()['requestsBySeat']), afterFirst['requestsBySeat'],
          reason: '幂等：已空的待办表重复清一次仍是空表，不是 null / 不是被改坏');
      expect(jsonEncode(h.roster.dump()), afterFirst['members'],
          reason: '幂等：成员表不因重复调用而变化');
    });

    test('L1-4 续玩：结团后同一房间再连进来，sync 里没有战斗态也没有幽灵卡片', () {
      final h = _host();
      _startCombat(h);
      _pendingRequest(h);

      h.endSession();
      // 续玩：老玩家重连（attachPeer 会给该座位推一份全量 sync）
      final res = h.attachPeer(<String, Object?>{'seat': 'p1', 'at': 9});

      final view = _syncState(res.out);
      expect(view, isNotNull, reason: '前提：重连必须拿到一份全量 sync');
      expect(view!['combat'], isNull,
          reason: '续玩时还停在战斗态 —— 这就是缺陷症状');
      expect(asList(view['requests']), isEmpty,
          reason: '续玩时玩家侧还挂着「待你确认」的幽灵卡片 —— 这就是缺陷症状');
      expect(asList(view['members']), isNotEmpty,
          reason: '成员表照旧下发（房间还在，不是销毁）');
    });
  });

  // ==========================================================
  // 缺陷 2 — 回退后重算回合内累计型字段
  // ==========================================================
  group('L2 回退：重算本回合 SAN 累计', () {
    test('L2-1 跨回合回退：sanLostThisRound 回到「回退到的那个回合」的值', () {
      final h = _host();
      h.advanceRound(1); // 明确第 1 回合的边界
      h.stateApply('p1', <String, Object?>{
        'status': <String, Object?>{'currentSAN': 50},
      }, <String, Object?>{'reason': '回合开始记一笔'}); // 建立 currentSAN 基线
      _sanLoss(h, 7);
      expect(h.sanLostThisRound['p1'], 7, reason: '前提：第 1 回合损失 7');
      expect(h.roundStartSan['p1'], 50, reason: '前提：第 1 回合开始 SAN = 50');

      h.advanceRound(2);
      expect(h.sanLostThisRound, isEmpty, reason: '前提：回合边界清零');
      _sanLoss(h, 3);
      expect(h.sanLostThisRound['p1'], 3, reason: '前提：第 2 回合又损失 3');

      // 回退到第 2 回合的 ROUND 事件之前 → 水位落回第 1 回合末尾
      h.rollback(_roundSeq(h, 2));

      expect(asMap(h.state['meta'])['round'], 1,
          reason: '前提：回退后确实回到第 1 回合');
      expect(h.sanLostThisRound['p1'], 7,
          reason: '必须是第 1 回合该有的 7；改前留着第 2 回合的 3（阈值判定错）');
      expect(h.roundStartSan['p1'], 50,
          reason: '第 1 回合开始 SAN = 50；改前是第 2 回合的 46');
    });

    test('L2-2 同回合回退：被撤销的那次 SAN 损失不再算进累计', () {
      final h = _host();
      h.advanceRound(1);
      h.stateApply('p1', <String, Object?>{
        'status': <String, Object?>{'currentSAN': 50},
      }, <String, Object?>{'reason': '回合开始记一笔'});
      _sanLoss(h, 7);
      expect(h.sanLostThisRound['p1'], 7);

      final beforeSecond = h.log.seq + 1; // 第二条损失的第一条事件
      _sanLoss(h, 3);
      expect(h.sanLostThisRound['p1'], 10, reason: '前提：同回合累计 7+3');

      h.rollback(beforeSecond);

      expect(asMap(h.state['meta'])['round'], 1, reason: '前提：仍在第 1 回合');
      expect(h.sanLostThisRound['p1'], 7,
          reason: '撤销掉的那 3 点不许继续累计（改前是 10）');
      expect(h.roundStartSan['p1'], 50, reason: '回合开始 SAN 不变');
    });

    test('L2-3 回退到建团基线：累计表全部为空（不残留任何「未来」值）', () {
      final h = _host();
      h.advanceRound(1);
      h.stateApply('p1', <String, Object?>{
        'status': <String, Object?>{'currentSAN': 50},
      }, <String, Object?>{'reason': '回合开始记一笔'});
      _sanLoss(h, 9);
      expect(h.sanLostThisRound['p1'], 9);

      h.rollback(1); // 丢掉全部事件，回到 seq0

      expect(h.sanLostThisRound, isEmpty);
      expect(h.roundStartSan, isEmpty);
      expect(h.fireUsed, isEmpty);
      expect(h.fadedArm, isEmpty);
    });
  });

  group('L2 回退：重算 fireUsed 与 fadedArm', () {
    test('L2-4 fireUsed：回退到没射过的回合 → 连发计数从 0 起算（能再开枪）', () {
      final h = _host();
      const key = 'p1\u0000手枪';
      h.advanceRound(1);
      h.fireUsed[key] = 3; // 第 1 回合已发 3 发（真实写入口：连发结算）
      expect(h.fireUsed[key], 3);

      h.advanceRound(2);
      expect(h.fireUsed, isEmpty, reason: '前提：回合边界清零');
      h.fireUsed[key] = 2; // 第 2 回合又打了 2 发
      expect(h.fireUsed[key], 2);

      h.rollback(_roundSeq(h, 2));

      expect(h.fireUsed, isEmpty,
          reason: '回退到第 1 回合后，「本回合已发射」必须是 0 —— '
              '改前留着第 2 回合的 2，回退后这一枪打不出去');
    });

    test('L2-5 fireUsed：同回合回退也一律按「本回合 0 发」重算（不堵死再射击）', () {
      final h = _host();
      const key = 'p1\u0000手枪';
      h.advanceRound(1);
      final beforeFire = h.log.seq + 1;
      h.fireUsed[key] = 2;
      h.emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': '开了一枪',
        'at': 1,
        'kind': 'check',
      }, vis: RoomVis.public);

      h.rollback(beforeFire);

      expect(h.fireUsed, isEmpty,
          reason: '射击次数只存在于内存（CHECK 事件只有摘要文本），'
              '日志还原不出「已发几发」→ 一律按 0 起算，宁可少算一次惩罚骰');
    });

    test('L2-6 fadedArm：潜在疯狂在回合内武装、跨边界被 disarm，回退后重新武装', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = _sheet(
        san: 40,
        maxSan: 60,
        mental: <Object?>['不定疯狂'],
        madness: <Object?>[
          <String, Object?>{
            'name': '恐高',
            'from': '不定疯狂',
            'rounds': 1,
            'permanent': false,
            'bg': false,
          },
        ],
      );
      h.advanceRound(1);
      // 不定疯狂的症状随轮次消退 → 转入潜在疯狂，此时 fadedArm = true（本回合已武装）
      h.advanceMadness(kHostSeat, <String, Object?>{'seat': 'p1'});
      expect(asList(asMap(h.roster.get('p1')!['sheet'])['mental'])
          .contains('潜在疯狂'), isTrue, reason: '前提：已转入潜在疯狂');
      expect(h.fadedArm['p1'], isTrue, reason: '前提：转入时武装');

      h.advanceRound(2);
      expect(h.fadedArm['p1'], isFalse,
          reason: '前提：回合边界对仍处潜在疯狂的座位 disarm');

      h.rollback(_roundSeq(h, 2));

      expect(asList(asMap(h.roster.get('p1')!['sheet'])['mental'])
          .contains('潜在疯狂'), isTrue, reason: '前提：回退后仍是潜在疯狂');
      expect(h.fadedArm['p1'], isTrue,
          reason: '「转入潜在疯狂」发生在第 1 回合内 → 回退到第 1 回合必须重新武装；'
              '改前留着边界写下的 false，该复发的没复发');
    });

    test('L2-7 fadedArm：转入潜在疯狂发生在边界之前 → 回退后仍须是 disarm，不许被误武装',
        () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = _sheet(
        san: 40,
        maxSan: 60,
        mental: <Object?>['不定疯狂'],
        madness: <Object?>[
          <String, Object?>{
            'name': '恐高',
            'from': '不定疯狂',
            'rounds': 1,
            'permanent': false,
            'bg': false,
          },
        ],
      );
      h.advanceRound(1);
      h.advanceMadness(kHostSeat, <String, Object?>{'seat': 'p1'});
      expect(h.fadedArm['p1'], isTrue, reason: '前提：第 1 回合内转入潜在疯狂 → 武装');

      h.advanceRound(2);
      expect(h.fadedArm['p1'], isFalse, reason: '前提：边界 disarm');
      h.advanceRound(3);
      expect(h.fadedArm['p1'], isFalse, reason: '前提：仍处潜在疯狂，继续 disarm');

      // 回退到第 3 回合的 ROUND 事件之前 → 水位落在第 2 回合末
      h.rollback(_roundSeq(h, 3));

      expect(asList(asMap(h.roster.get('p1')!['sheet'])['mental'])
          .contains('潜在疯狂'), isTrue, reason: '前提：仍是潜在疯狂（花名册不被回退）');
      expect(h.fadedArm['p1'], isFalse,
          reason: '「转入潜在疯狂」在第 1 回合、第 2 回合边界就已 disarm → '
              '回退到第 2 回合末仍是 false。'
              '这条同时钉住「不许把 fadedArm 简化成 isPotentialMadness 就置 true」'
              '——那会让潜在疯狂永远「任意损失即复发」。');
    });

    test('L2-8 反向护栏：正常推进（不回退）时三个字段行为完全不变', () {
      final h = _host();
      h.advanceRound(1);
      h.stateApply('p1', <String, Object?>{
        'status': <String, Object?>{'currentSAN': 50},
      }, <String, Object?>{'reason': '回合开始记一笔'});
      _sanLoss(h, 7);
      h.fireUsed['p1\u0000手枪'] = 2;

      h.advanceRound(2);

      expect(h.sanLostThisRound, isEmpty, reason: '回合边界照旧清零');
      expect(h.roundStartSan, isEmpty);
      expect(h.fireUsed, isEmpty);
      expect(h.log.items, isNotEmpty, reason: '日志照旧');
    });
  });
}
