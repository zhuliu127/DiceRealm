// ============================================================
// test/p11_fix2_sheet_test.dart — P11 修 2：规则层两处缺陷的回归靶子
//
//   F1 `afterSanLoss`：临时 / 不定疯狂期间「不获得新疯狂症」被错误地实现成
//      「不累计 SAN 损失」—— 累计整段写在 `madActive` 早退之后。
//      症状：疯狂期受的损失不进 `sanLostThisRound`，④ 的
//      「不定疯狂阈值 = ceil(maxSAN/5)」基于错的累计，
//      「症状消退 → 潜在疯狂 → 复发」链上阈值跨回合漂移。
//
//   F2 `detachPeer`：成员掉线时漏接 `rollbackAbortIfVoting`（需求 §9
//      「回退表决期间有人掉线 → 该次表决作废」）。方法是现成的（D15 已落），
//      只是没接线，表决会挂着等一个已经不在的人。
//
// ★ 铁律：全内存后端（`roomHostOpts()` 的固定时钟 + LCG + 确定性规则/疯狂表）、
//   零真实 I/O、不用 Future.delayed。
// ★ 每个用例都先断言「前提成立」，再断言目标行为；反向自证伪见报告
//   `_p11_fix2_sheet_report.md`：把累计移回早退之后 / 注释掉
//   `rollbackAbortIfVoting` → F1 / F2 必须变红。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
// afterSanLoss 是 `extension ... on RoomHost`，必须 import 定义库才可见。
import 'package:dice_realm/domain/room_model_actions_sheet.dart'
    show RoomHostActionsSheet;
import 'package:dice_realm/domain/room_model_host_core.dart' show RoomHost;
import 'package:dice_realm/domain/room_types.dart'
    show kHostSeat, RoomEvt, RoomRewind, SendPlan;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

// ------------------------------------------------------------
// 脚手架（形状抄自 p10_t3b_rule_diff_test.dart，只保留本文件要用的部分）
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

/// 只取一条出站 evt 的 `{t,p}`（跳过 sync / skip）。
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

/// 出站计划的事件类型序列（非 evt 的用 `k` 顶替）。
List<String> _kinds(List<SendPlan> plans) => <String>[
      for (final p in plans)
        () {
          final m = p.msg.toJson();
          return '${m['k'] == 'evt' ? m['t'] : m['k']}';
        }(),
    ];

List<String> _logTexts(List<SendPlan> plans) => <String>[
      for (final l in _evts(plans, RoomEvt.log)) jsStr(l['text']),
    ];

void main() {
  // ==========================================================
  // F1 — afterSanLoss：疯狂期仍然累计 SAN 损失（但不发新症状）
  // ==========================================================
  group('F1 afterSanLoss：累计不被 madActive 早退吃掉', () {
    test('F1-1 临时疯狂 + 连续两次损失 → sanLostThisRound 累加两次，且不新增症状',
        () {
      final h = _host();
      final p1 = h.roster.get('p1')!;
      p1['sheet'] = _sheet(san: 40, maxSan: 60, mental: <Object?>['临时疯狂']);

      final first = h.afterSanLoss(p1, 3, kHostSeat);
      // 前提：确实处于「临时疯狂」，走的是早退分支（不是普通路径）
      expect(_logTexts(first).any((t) => t.contains('本次不获得新的疯狂症')),
          isTrue,
          reason: '前提：临时疯狂期必须命中「不获得新疯狂症」分支');
      expect(h.sanLostThisRound['p1'], 3,
          reason: '疯狂期第一次损失必须进累计（改前为 null / 0）');

      // 真实语义：currentSAN 已是被扣减后的值，第二次调用前再降 4
      asMap(asMap(p1['sheet'])['status'])['currentSAN'] = 36;
      final second = h.afterSanLoss(p1, 4, kHostSeat);

      expect(h.sanLostThisRound['p1'], 7,
          reason: '两次损失必须累加（改前第二次仍为 0，因为第一次压根没记）');
      expect(h.roundStartSan['p1'], 43,
          reason: '回合开始 SAN = 第一次损失前的值 40 + 累计 3 = 43；'
              '第二次不得重算（首值只记一次）');

      // ★ 需求 6 的原文只约束「发不发症状」，不约束「记不记损失」
      expect(asList(asMap(p1['sheet'])['madness']), isEmpty,
          reason: '疯狂期仍然不许新增疯狂症状');
      expect(asList(asMap(p1['sheet'])['mental']), <Object?>['临时疯狂'],
          reason: '精神状态不变；不许被顺手改成临时/不定疯狂发作');
      expect(_logTexts(second).any((t) => t.contains('本次不获得新的疯狂症')),
          isTrue,
          reason: '第二次仍在疯狂期，告警照发');
      // 早退要早得「够」：② 的 INT 检定路径整段不该跑
      expect(_evts(second, RoomEvt.dice), isEmpty,
          reason: '疯狂期不该触发 ② 的临时疯狂 INT 检定');
    });

    test('F1-2 疯狂期累计的损失能被 ④ 的不定疯狂阈值看到（改前永不达标）', () {
      final h = _host();
      final p1 = h.roster.get('p1')!;
      // maxSAN 60 → ceil(60/5) = 12
      p1['sheet'] = _sheet(san: 40, maxSan: 60, mental: <Object?>['临时疯狂']);

      final duringMadness = h.afterSanLoss(p1, 9, kHostSeat);
      expect(h.sanLostThisRound['p1'], 9, reason: '疯狂期必须记账（这是本缺陷的核心）');
      expect(asList(asMap(p1['sheet'])['madness']), isEmpty,
          reason: '疯狂期不新增症状（需求 6）');
      expect(_logTexts(duringMadness).any((t) => t.contains('达到最大理智值')),
          isFalse,
          reason: '疯狂期早退，④ 的阈值判定不该跑');

      /* 症状消退回到正常：消退路径本身由 p8 / T3-2 覆盖，这里只准备输入
         （临时疯狂 + 症状消退 → 正常，不产生潜在疯狂）。 */
      asMap(p1['sheet'])['mental'] = <Object?>['正常'];
      asMap(asMap(p1['sheet'])['status'])['currentSAN'] = 28;

      // 第二次损失 3（< 5，避开 ② 的临时疯狂 INT 路径，隔离出 ④）
      final afterFade = h.afterSanLoss(p1, 3, kHostSeat);

      expect(h.sanLostThisRound['p1'], 12, reason: '9 + 3 = 12');
      expect(asList(asMap(p1['sheet'])['mental']).contains('不定疯狂'), isTrue,
          reason: '累计 12 ≥ ceil(60/5)=12 → 不定性疯狂。'
              '改前疯狂期那 9 点没记，累计只有 3 —— 阈值永不达标，'
              '这就是「症状消退 → 潜在疯狂 → 复发」链上的阈值漂移。');
      expect(_logTexts(afterFade).any((t) => t.contains('达到最大理智值')),
          isTrue,
          reason: '④ 的公共事件必须发出去');
    });

    test('F1-3 SAN 归零（永久疯狂）不写累计 —— 与老 APP :5169-5176 同序', () {
      final h = _host();
      final p1 = h.roster.get('p1')!;
      p1['sheet'] = _sheet(san: 0, maxSan: 60, mental: <Object?>['正常']);

      final plans = h.afterSanLoss(p1, 60, kHostSeat);

      expect(asList(asMap(p1['sheet'])['mental']).contains('永久疯狂'), isTrue);
      expect(_logTexts(plans).any((t) => t.contains('永久疯狂')), isTrue);
      /* 老 APP 的 ① 归零分支在「② 累计」之前 return（:5169-5176），本工程
         保持同序：撕卡后角色不再参与回合判定，`maxSAN` 分母也失去意义。 */
      expect(h.sanLostThisRound.containsKey('p1'), isFalse,
          reason: '① 归零分支先返回，不写累计（对齐老 APP）');
      expect(h.roundStartSan.containsKey('p1'), isFalse);
    });
  });

  // ==========================================================
  // F2 — detachPeer：表决期间有人掉线 → 该次表决作废（需求 §9）
  // ==========================================================
  group('F2 detachPeer：掉线时中止进行中的回退表决', () {
    Map<String, Object?> votingRewind() => <String, Object?>{
          'state': RoomRewind.voting,
          'need': <Object?>['p1', 'p2'],
          'agree': <Object?>[],
          'turns': 1,
          'by': 'p1',
          'at': 1,
        };

    test('F2-1 投票者掉线 → rewind 置 FAILED + 公共提示 + 成员表照旧广播', () {
      final h = _host();
      h.rewind = votingRewind();
      expect(h.rewind!['state'], RoomRewind.voting, reason: '前提：表决进行中');

      final plans = h.detachPeer('p2');

      final r = h.rewind!;
      expect(r['state'], RoomRewind.failed,
          reason: '§9：表决期间有人掉线 → 该次表决作废');
      expect(jsStr(r['failReason']), contains('断线'));
      expect(jsStr(r['failReason']), '有玩家在表决期间断线',
          reason: '文案与老 APP `rollbackAbortIfVoting` 保持一致');

      // ---- 原有副作用不变：只标离线，**不移除**（他要能重连回原座）
      expect(h.roster.get('p2')!['online'], isFalse);
      expect(h.roster.list().map((m) => m['seat']).toList(),
          <Object?>['p1', 'p2'],
          reason: '掉线不得把成员从花名册里删掉');

      // ---- 事件：rewind 广播（载荷带已作废的状态）+ 公共系统提示 + 成员表
      final rewindEvts = _evts(plans, RoomEvt.rewind);
      expect(rewindEvts, hasLength(1), reason: '必须广播一次 rewind 状态变更');
      expect(jsStr(asMap(rewindEvts.single['rewind'])['state']), RoomRewind.failed,
          reason: '广播出去的载荷必须是 FAILED，不能是投票前的 VOTING');
      expect(_logTexts(plans).any((t) => t == '回退失败：有玩家在表决期间断线'),
          isTrue);
      expect(_evts(plans, RoomEvt.members), hasLength(1),
          reason: '成员表广播不能因为中止表决而丢掉');

      // ---- 顺序：先中止表决，再广播成员表（成员表带的是已作废的 rewind）
      expect(_kinds(plans), <String>['rewind', 'log', 'members'],
          reason: '副作用顺序：markOffline → 中止表决 → 广播成员表');
    });

    test('F2-2 不在表决中 → 不产生任何额外事件（行为与改前完全一致）', () {
      final h = _host();
      expect(h.rewind, isNull);

      final plans = h.detachPeer('p2');

      expect(h.rewind, isNull, reason: '没有表决就没有可作废的东西');
      expect(_evts(plans, RoomEvt.rewind), isEmpty,
          reason: '不该冒出一条 rewind 事件');
      expect(_evts(plans, RoomEvt.log), isEmpty,
          reason: '不该冒出一条「回退失败」系统提示');
      expect(_evts(plans, RoomEvt.members), isNotEmpty,
          reason: '原有的成员表广播必须还在');
      expect(h.roster.get('p2')!['online'], isFalse);
      expect(h.roster.list(), hasLength(2));
    });

    test('F2-3 掉线者不在 need 名单里 → 表决不受影响', () {
      final h = _host();
      h.attachPeer(<String, Object?>{'seat': 'p3', 'nickname': '丙', 'at': 3});
      h.rewind = <String, Object?>{
        'state': RoomRewind.voting,
        'need': <Object?>['p1', 'p2'],
        'agree': <Object?>[],
        'turns': 1,
        'by': 'p1',
        'at': 1,
      };

      final plans = h.detachPeer('p3');

      expect(h.rewind!['state'], RoomRewind.voting,
          reason: '老 APP：`need` 里没有这个人就不动表决');
      expect(_evts(plans, RoomEvt.rewind), isEmpty);
      expect(_evts(plans, RoomEvt.log), isEmpty,
          reason: '不该发「回退失败」提示');
      expect(_evts(plans, RoomEvt.members), isNotEmpty);
    });
  });
}
