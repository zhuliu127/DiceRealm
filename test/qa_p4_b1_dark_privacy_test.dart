// ============================================================
// test/qa_p4_b1_dark_privacy_test.dart — B1-F1 修复后的暗骰隐私矩阵
//
// 修复方案 ②（`diceDirect` 侧分流）：暗骰不再发 `EVT.DICE`，改发
// `EVT.PRIVATE`（`vis: seat`）给**本人**与**KP**；公共侧只留一条脱敏 LOG。
// `reduceRoomState` 的 DICE 分支 / `makeSync` / `syncFor` / `save` 零改动，
// 因此「暗骰不进公共 dice」必须靠**事件类型**保证，而不是靠下游过滤。
//
// 本文件独立验五件事（不复用 authority 文件里的那条用例）：
//   ① 隐私矩阵：state.dice / 他人 syncFor / save().dice / playerViewFromSave 全空，
//      且别人的同步载荷里连「明细」字样都没有（字节级）；
//   ② 本人与 KP 都拿得到：live evt 有结构化 total/levelText/label，
//      privateBySeat 的 text 也带骰面（重连可还原）；
//   ③ 公开骰没被带崩：仍 EVT.DICE + to:'*' + 进 state.dice；
//   ④ 混合场景：先公开后暗骰 → state.dice 只剩公开那条；
//   ⑤ 多次暗骰 / KP 自己暗骰的边界；三闸与 warning 不受影响。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

RoomHost _host({int seed = 4}) {
  final h = RoomHost(roomHostOpts(seed: seed));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  return h;
}

/// 掷一次（`secret` 控制明骰 / 暗骰）。
List<SendPlan> _roll(
  RoomHost h,
  String seat, {
  bool secret = false,
  String label = '攻击',
}) =>
    h.intent(seat, <String, Object?>{
      'op': RoomIntent.dice,
      'p': <String, Object?>{
        'expr': '1D100',
        'label': label,
        'base': 50,
        'direct': true,
        if (secret) 'secret': true,
      },
    });

void main() {
  group('B1-F1 隐私矩阵：暗骰不进任何公共面', () {
    test('state.dice / 他人 sync / save / 裁剪视图 全空；本人与 KP 都拿得到', () {
      final h = _host();
      final out = _roll(h, 'p1', secret: true, label: '偷袭');

      // ① 公共面全空
      expect(asList(h.state['dice']), isEmpty);
      for (final seat in <String>['p2', 'ghost']) {
        final view = h.syncFor(seat).toJson();
        expect(asList(asMap(view['state'])['dice']), isEmpty,
            reason: 'syncFor($seat) 里出现了暗骰');
        expect(view.toString().contains('明细'), isFalse,
            reason: 'syncFor($seat) 的载荷里出现了暗骰明细（字节级泄漏）');
        expect(view.toString().contains('偷袭'), isFalse,
            reason: 'syncFor($seat) 的载荷里出现了暗骰 label');
      }
      final save = h.save();
      expect(asList(save['dice']), isEmpty, reason: 'save() 里带了暗骰');
      for (final seat in <String>['p1', 'p2', 'ghost']) {
        final view = playerViewFromSave(save, seat)!.toJson();
        expect(asList(asMap(view['state'])['dice']), isEmpty,
            reason: 'playerViewFromSave($seat) 里带了暗骰');
      }

      // ② 本人与 KP：live evt 结构化 + privateBySeat 文本
      Map<String, Object?> evtTo(String seat) => asMap(out
          .map((p) => p.toJson())
          .firstWhere((j) =>
              j['to'] == seat && asMap(j['msg'])['k'] == 'evt')['msg']);
      final selfEvt = evtTo('p1');
      final hostEvt = evtTo(kHostSeat);
      expect(selfEvt['t'], RoomEvt.private_);
      expect(hostEvt['t'], RoomEvt.private_);
      final selfP = asMap(selfEvt['p']);
      for (final k in <String>['total', 'levelText', 'label']) {
        expect(selfP.containsKey(k), isTrue, reason: '暗骰 evt 缺结构化字段 $k');
      }
      expect(selfP['label'], '偷袭');
      expect(jsNum(selfP['total']), inInclusiveRange(1, 100));
      expect(asMap(hostEvt['p'])['total'], selfP['total'],
          reason: 'KP 拿到的暗骰结果与本人不一致');
      expect(asMap(hostEvt['p'])['levelText'], selfP['levelText']);

      expect(h.privateBySeat['p1'], hasLength(1));
      expect(h.privateBySeat[kHostSeat], hasLength(1));
      final selfText = jsStr(asMap(h.privateBySeat['p1']!.single)['text']);
      expect(selfText, contains('${jsNum(selfP['total'])}'),
          reason: 'privateBySeat 文本里没有骰面（重连还原不了）');
      expect(selfText, contains('偷袭'));
      expect(selfText, contains(jsStr(selfP['levelText'])));
      expect(jsStr(asMap(h.privateBySeat[kHostSeat]!.single)['text']), selfText);

      // 公共日志：脱敏，且不含骰面
      final logRow = asMap(asList(h.state['logs']).last);
      expect(logRow['kind'], 'dice-dark');
      expect(jsStr(logRow['text']), contains('只有他/她与 KP 可见'));
      expect(jsStr(logRow['text']).contains('${jsNum(selfP['total'])}'), isFalse);
      // 其他人的实时计划只能是 skip
      expect(out.where((p) => p.to == 'p2').map((p) => p.msg.toJson()['k']).toList(),
          everyElement('skip'));
      expect(out.where((p) => p.to == '*').map((p) => p.msg.toJson()['t']).toList(),
          isNot(contains(RoomEvt.dice)));
    });

    test('暗骰不产生 scrub warning（VIS.SEAT 不触发 hasSecret 闸门）', () {
      final h = _host();
      final before = h.warnings.length;
      _roll(h, 'p1', secret: true);
      expect(h.warnings.length, before,
          reason: '暗骰是 SEAT 定向事件，不该被 scrub 记 warning');
    });

    test('连续多次暗骰：privateBySeat 各自累计，state.dice 始终为空', () {
      final h = _host();
      for (var i = 0; i < 3; i++) {
        _roll(h, 'p1', secret: true, label: '偷袭$i');
      }
      expect(h.privateBySeat['p1'], hasLength(3));
      expect(h.privateBySeat[kHostSeat], hasLength(3));
      expect(asList(h.state['dice']), isEmpty);
      final texts = h.privateBySeat['p1']!
          .map((x) => jsStr(asMap(x)['text']))
          .toList();
      expect(texts.any((t) => t.contains('偷袭0')), isTrue);
      expect(texts.any((t) => t.contains('偷袭2')), isTrue);
    });

    test('KP 自己的暗骰：只发 1 条给自己（不重复发），state.dice 仍空', () {
      final h = _host();
      final out = _roll(h, kHostSeat, secret: true);
      final hostEvts = out
          .map((p) => p.toJson())
          .where((j) => j['to'] == kHostSeat && asMap(j['msg'])['k'] == 'evt')
          .toList();
      expect(hostEvts, hasLength(1),
          reason: 'KP 自己暗骰应只收 1 条（不得自己发给自己两次）');
      expect(asMap(hostEvts.single['msg'])['t'], RoomEvt.private_);
      expect(asList(h.state['dice']), isEmpty);
      expect(h.privateBySeat[kHostSeat], hasLength(1));
    });
  });

  group('公开骰未被带崩', () {
    test('公开骰仍 EVT.DICE + to:* + 进 state.dice，其他玩家看得见', () {
      final h = _host();
      final out = _roll(h, 'p1', secret: false);
      final evt = out
          .map((p) => p.toJson())
          .firstWhere((j) => asMap(j['msg'])['k'] == 'evt');
      expect(evt['to'], '*');
      expect(asMap(evt['msg'])['t'], RoomEvt.dice);
      final dice = asList(h.state['dice']);
      expect(dice, hasLength(1));
      expect(asMap(dice.single)['seat'], 'p1');
      final other = asList(asMap(h.syncFor('p2').toJson()['state'])['dice']);
      expect(other, hasLength(1), reason: '公开骰应能被别人看到');
      expect(asMap(other.single)['total'], asMap(dice.single)['total']);
    });

    test('混合场景：先公开后暗骰 → state.dice 只剩公开那条', () {
      final h = _host();
      _roll(h, 'p1', secret: false, label: '明骰');
      final publicRec = asMap(asList(h.state['dice']).single);
      _roll(h, 'p1', secret: true, label: '暗骰');
      final dice = asList(h.state['dice']).map(asMap).toList();
      expect(dice, hasLength(1), reason: '暗骰被混进了公共 dice');
      expect(dice.single['label'], '明骰');
      expect(dice.single['total'], publicRec['total']);
      // 别人的同步里也只有那一条公开骰
      final other = asList(asMap(h.syncFor('p2').toJson()['state'])['dice']);
      expect(other, hasLength(1));
      expect(asMap(other.single)['label'], '明骰');
      // 暗骰只在本人 / KP 的私密栏
      expect(h.privateBySeat['p1'], hasLength(1));
      expect(h.privateBySeat[kHostSeat], hasLength(1));
      expect(jsStr(asMap(h.privateBySeat['p1']!.single)['text']),
          contains('暗骰'));
    });
  });
}
