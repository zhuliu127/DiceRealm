// ============================================================
// test/p11_authz_ready_test.dart — P11 越权修复的回归靶子（只补测试，不动生产代码）
//
// 被钉住的行为（`lib/domain/room_model_actions_room.dart`，修复已生效）：
//   · `roomActionReady(seat, p)`（:600-624）
//       若 `p['seat']` 非空且 != seat → `sysTo(seat, '只能设置自己的准备状态')` 并返回；
//       否则 `target = seat`。
//   · `roomActionCharShare(seat, p)`（:632-650）
//       同理，提示 `'只能上报自己的角色卡'`；否则 `target = seat`。
//
// 修复前的缺陷：`target` 直接读客户端传来的 `p['seat']`，于是
//   「任意玩家都能把别人强制设为已准备 / 换掉别人的角色卡」。
//   `ready.set` / `char.share` 的 POLICY 只放 `RoomRole.player`，KP 都无权调用，
//   所以「代他人操作」根本没有正当代路径。
//
// ★ 铁律：全内存后端、零真实 I/O。断言分两段 ——
//   ① 权威态（花名册）没被改；② 越权者收到定向提示。
//   两段都要断言，只断言 ① 会把「静默吞掉」当成功。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_model_actions_room.dart'
    show RoomHostActionsRoom;
import 'package:dice_realm/domain/room_model_host_core.dart' show RoomHost;
import 'package:dice_realm/domain/room_model_host_intent.dart'
    show RoomHostIntent;
import 'package:dice_realm/domain/room_model_state.dart' show needs;
import 'package:dice_realm/domain/room_types.dart'
    show kHostSeat, RoomEvt, RoomIntent, RoomRole, SendPlan;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

// ------------------------------------------------------------
// 脚手架（建房 + 加成员 + 拿 host，抄自 qa_p5 / p10_t3b）
// ------------------------------------------------------------

/// p1 / p2 是玩家（已领角色卡），sp1 是旁观者。
RoomHost _host() {
  final h = RoomHost(roomHostOpts(seed: 7));
  h.attachPeer(<String, Object?>{
    'seat': 'p1',
    'nickname': '甲',
    'role': RoomRole.player,
    'at': 1,
  });
  h.attachPeer(<String, Object?>{
    'seat': 'p2',
    'nickname': '乙',
    'role': RoomRole.player,
    'at': 2,
  });
  h.attachPeer(<String, Object?>{
    'seat': 'sp1',
    'nickname': '旁观',
    'role': RoomRole.spectator,
    'at': 3,
  });
  // `ready: true` 的前置是「已选角色卡」，先备好
  h.roster.get('p1')!['charId'] = 'c1';
  h.roster.get('p1')!['charName'] = '甲';
  h.roster.get('p2')!['charId'] = 'c2';
  h.roster.get('p2')!['charName'] = '乙';
  return h;
}

/// ACT 通道请求体。
Map<String, Object?> _act(String op, Map<String, Object?> p) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

/// 一条出站 evt 的 `{t,p}`（跳过 sync / skip）。
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

/// 定向系统提示（`sysTo` 走 PRIVATE 事件）的文本列表；[seat] 非空时只留发给他的。
List<String> _privTexts(List<SendPlan> plans, {String? to}) => <String>[
      for (final p in plans)
        if (p.to == to || to == null)
          if (_evt(p, RoomEvt.private_) != null)
            jsStr(_evt(p, RoomEvt.private_)!['text']),
    ];

/// 成员表事件里某人的字段（从最后一次 members 事件里取）。
Object? _memberField(List<SendPlan> plans, String seat, String key) {
  final evts = _evts(plans, RoomEvt.members);
  if (evts.isEmpty) return null;
  final members = asList(evts.last['members']);
  for (final raw in members) {
    final m = asMap(raw);
    if (jsStr(m['seat']) == seat) return m[key];
  }
  return null;
}

void main() {
  // ==========================================================
  // ready.set
  // ==========================================================
  group('R ready.set：只能设置自己的准备状态', () {
    test('R-1 玩家 A 指自己 ready:true → A 变已准备', () {
      final h = _host();
      expect(h.roster.get('p1')!['ready'], isFalse, reason: '前提：初始未准备');

      final plans =
          h.intent('p1', _act('ready.set', <String, Object?>{'seat': 'p1', 'ready': true}));

      expect(h.roster.get('p1')!['ready'], isTrue,
          reason: '正常路径必须生效（修复不许把合法操作一起挡掉）');
      expect(_privTexts(plans, to: 'p1'), isEmpty,
          reason: '合法操作不该收到越权提示');
      expect(_memberField(plans, 'p1', 'ready'), isTrue,
          reason: '成员表广播里 p1 应为已准备');
      expect(_memberField(plans, 'p2', 'ready'), isFalse,
          reason: '别人的准备状态不许被顺带改掉');
    });

    test('R-2 玩家 A 指 B → B 状态不变，A 收到「只能设置自己的准备状态」', () {
      final h = _host();

      final plans =
          h.intent('p1', _act('ready.set', <String, Object?>{'seat': 'p2', 'ready': true}));

      // ① 权威态：B 一个字节都没动
      expect(h.roster.get('p2')!['ready'], isFalse,
          reason: '越权请求不得改动 B 的准备状态（修复前的缺陷正是这里）');
      // ② 越权者必须收到定向提示，不能静默吞掉
      expect(_privTexts(plans, to: 'p1'), contains('只能设置自己的准备状态'));
      // ③ 拒绝得「干净」：不发成员表（否则客户端会以为改了）
      expect(_evts(plans, RoomEvt.members), isEmpty,
          reason: '越权分支 return 在 syncMembers 之前');
    });
  });

  // ==========================================================
  // char.share
  // ==========================================================
  group('C char.share：只能上报自己的角色卡', () {
    test('C-1 玩家 A 指自己 → A 的 charName 变了', () {
      final h = _host();

      final plans = h.intent(
          'p1',
          _act('char.share', <String, Object?>{
            'seat': 'p1',
            'name': '甲·改',
            'id': 'c1',
          }));

      expect(h.roster.get('p1')!['charName'], '甲·改');
      expect(_privTexts(plans, to: 'p1'), isEmpty,
          reason: '合法上报不该收到越权提示');
      expect(_memberField(plans, 'p1', 'charName'), '甲·改',
          reason: '成员表广播里应带上新名字');
    });

    test('C-2 玩家 A 指 B → B 的 charName 不变，A 收到「只能上报自己的角色卡」', () {
      final h = _host();

      final plans = h.intent(
          'p1',
          _act('char.share', <String, Object?>{
            'seat': 'p2',
            'name': '被顶替',
            'id': 'c9',
          }));

      expect(h.roster.get('p2')!['charName'], '乙',
          reason: '越权请求不得改掉 B 的角色卡名（修复前的缺陷正是这里）');
      expect(h.roster.get('p2')!['charId'], 'c2',
          reason: '连 charId 也不许被顶替');
      expect(_privTexts(plans, to: 'p1'), contains('只能上报自己的角色卡'));
      expect(_evts(plans, RoomEvt.members), isEmpty);
    });
  });

  // ==========================================================
  // 旁观者 / 空 seat
  // ==========================================================
  group('S 旁观者与空 seat', () {
    test('S-1 旁观者指自己 → 提示「旁观者不能设准备状态」', () {
      final h = _host();

      // 真实入口：INTENT.ready（sp1 的角色在花名册里是 spectator）
      final viaIntent = h.intent(
        'sp1',
        <String, Object?>{
          'op': RoomIntent.ready,
          'p': <String, Object?>{'seat': 'sp1', 'ready': true},
        },
      );
      expect(_privTexts(viaIntent, to: 'sp1'),
          contains('旁观者不能设准备状态'));
      expect(h.roster.get('sp1')!['ready'], isFalse,
          reason: '旁观者的权威态不该被改动');

      /* ACT 通道的角色分支：`ready.set` 的 POLICY 只放 player，旁观者走
         `intent()` 会在闸门就被拒（提示「你没有权限执行该操作」）。
         要看 `roomActionReady` 自己的角色守卫，只能直呼真身。 */
      final viaAct =
          h.roomActionReady('sp1', <String, Object?>{'seat': 'sp1', 'ready': true});
      expect(_privTexts(viaAct, to: 'sp1'),
          contains('旁观者不能设准备状态'));
      expect(h.roster.get('sp1')!['ready'], isFalse);
    });

    test('S-2 空 p[\'seat\'] → 视为本人，正常生效', () {
      final h = _host();

      // 不带 seat 键
      final a = h.intent(
          'p1', _act('ready.set', <String, Object?>{'ready': true}));
      expect(h.roster.get('p1')!['ready'], isTrue,
          reason: '缺省 seat 应回落到发起者本人');
      expect(_privTexts(a, to: 'p1'), isEmpty);

      // 显式空串同样按本人处理
      h.roster.get('p1')!['ready'] = false;
      final b = h.intent('p1',
          _act('ready.set', <String, Object?>{'seat': '', 'ready': true}));
      expect(h.roster.get('p1')!['ready'], isTrue,
          reason: '空串 seat 也应回落到发起者本人，不得被当成越权');
      expect(_privTexts(b, to: 'p1'), isEmpty);

      // char.share 的空 seat 同理
      final c = h.intent(
          'p1', _act('char.share', <String, Object?>{'name': '甲·空 seat'}));
      expect(h.roster.get('p1')!['charName'], '甲·空 seat');
      expect(_privTexts(c, to: 'p1'), isEmpty);
    });
  });

  // ==========================================================
  // 守门：KP 走 ACT 通道也拿不到 ready.set（POLICY 只放 player）
  // ==========================================================
  group('K 闸门兜底', () {
    test('K-1 KP 伪造 ACT ready.set 指别人 → 被 needs() 拒绝，无任何状态变更', () {
      final h = _host();
      expect(needs(RoomRole.kp, 'ready.set').allowed, isFalse,
          reason: '前提：POLICY 里 ready.set 只放 player');

      final plans =
          h.intent(kHostSeat, _act('ready.set', <String, Object?>{'seat': 'p1', 'ready': true}));

      expect(h.roster.get('p1')!['ready'], isFalse);
      expect(_privTexts(plans, to: kHostSeat), contains('你没有权限执行该操作'));
      expect(asList(h.roster.list()), isNotEmpty);
    });
  });
}
