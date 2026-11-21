// ============================================================
// test/qa_p4_b1_authority_test.dart — B1 补丁复验（一）：三条「玩家可触发」结算的权威性
//
// B1 把三个原本 no-op 的 INTENT 分支接到了已实现的结算函数上：
//   INTENT.DICE{direct:true} → diceDirect      （QA 上轮的 F4 同源风险面）
//   INTENT.SAN_CHECK         → playerSanCheck  → settleSanCheck
//   INTENT.OPPOSED           → opposed         → opposedPlayerRequest / opposedPlayerTarget
//
// 本文件的判据只有一条：**权威端的数字必须由规则服务算出来**，客户端能影响的
// 只有「报什么」而不是「算成什么」。
//   · 骰面（total / rolls / level）→ 与独立用 CocRules + 同种子算出的结果逐字段相等；
//   · 客户端自报 `result` / `loss` / `success` / `a` / `b` / `winner` → 一律不参与；
//   · 客户端能选「目标值 base」（技能不在卡上时）—— 这是**旧版明确记录的既有语义**
//     （room-model.js:3025「伪造的只是目标值…朋友间跑团够用了」），本文件如实区分，
//     不当作 B1 的新缺陷。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_rules.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show Lcg;
import 'support/room_fakes.dart';

const CocRules _rules = CocRules();

RoomHost _host({int seed = 1}) {
  final h = RoomHost(roomHostOpts(seed: seed));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  return h;
}

/// 给成员挂一张最小可用卡（SAN / 武器 / 技能）。
void _giveSheet(
  RoomHost h,
  String seat, {
  num san = 50,
  num maxSan = 60,
  List<Object?> weapons = const <Object?>[],
  List<Object?> skills = const <Object?>[],
}) {
  h.roster.get(seat)!['sheet'] = <String, Object?>{
    'name': '甲',
    'status': <String, Object?>{
      'currentHP': 10,
      'maxHP': 10,
      'currentSAN': san,
      'maxSAN': maxSan,
      'body': '正常',
      'dying': false,
      'unconscious': false,
    },
    'mental': <Object?>['正常'],
    'madness': <Object?>[],
    'tempStatus': <Object?>[],
    'items': <Object?>[],
    'weapons': weapons,
    'skills': skills,
    'db': '0',
  };
}

Map<String, Object?> _lastDice(RoomHost h) =>
    asMap(asList(h.state['dice']).last);

/// 按 label 前缀取**第一条**骰子记录。
///
/// ⚠️ 不能用「末条」：SAN Check 之后可能紧跟一条「临时疯狂 INT 检定」的骰子，
///    用末条会张冠李戴（本探针首版就踩了这个坑）。
Map<String, Object?> _diceLabeled(RoomHost h, String prefix) => asMap(
      asList(h.state['dice'])
          .map(asMap)
          .firstWhere((d) => jsStr(d['label']).startsWith(prefix)),
    );

void main() {
  // ==========================================================
  // 1) INTENT.DICE{direct:true} —— 骰面必须复算
  // ==========================================================
  group('B1-1 diceDirect：玩家不能伪造骰面', () {
    test('客户端 result{value:1,大成功,rolls:[1]} 完全不参与；结果 == CocRules 复算值', () {
      // 技能刻意不在卡上 → base 回落客户端值（旧版既有语义），
      // 这样「目标值」被钉死，只剩骰面可比，避免被技能解析差异干扰。
      const base = 50;
      const seed = 7;
      final expected = _rules.check(<String, Object?>{
        'kind': 'skill',
        'base': base,
        'difficulty': 'REGULAR',
        'bonus': 0,
        'penalty': 0,
        'label': '攻击',
        'rng': Lcg(seed).call,
      });
      final h = _host(seed: seed);
      _giveSheet(h, 'p1');
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'label': '攻击',
          'skill': '不存在的技能',
          'base': base,
          'direct': true,
          'result': <String, Object?>{
            'value': 1,
            'level': 5,
            'levelKey': 'CRITICAL',
            'levelText': '大成功',
            'rolls': <Object?>[1],
            'detail': '1',
          },
        },
      });
      expect(out, isNotEmpty, reason: 'B1：INTENT.DICE{direct} 必须产生结算');
      final rec = _lastDice(h);
      expect(rec['total'], expected['value'],
          reason: 'B1：骰面必须等于 CocRules 复算值（客户端自报 1 被采用了？）');
      expect(rec['levelText'], expected['levelText']);
      expect(rec['total'], isNot(1), reason: 'seed=$seed 下权威复算值恰好不是 1，可用来证伪');
      // 客户端自报的 rolls:[1] 不得成为权威 rolls
      expect(asList(rec['rolls']).toList(), isNot(<Object?>[1]),
          reason: 'B1：权威 rolls 照搬了客户端 result.rolls');
      expect(asList(rec['rolls']).toList(), asList(expected['rolls']).toList());
    });

    test('换种子 → 骰面跟着变；同种子 → 完全可复现（证明真在掷，不是回显）', () {
      List<num> totalsForSeeds(List<int> seeds) {
        final out = <num>[];
        for (final s in seeds) {
          final h = _host(seed: s);
          _giveSheet(h, 'p1');
          h.intent('p1', <String, Object?>{
            'op': RoomIntent.dice,
            'p': <String, Object?>{
              'expr': '1D100',
              'label': '攻击',
              'base': 50,
              'direct': true,
              // 每次都塞同一个伪造结果：如果它被采用，三次都会是 1
              'result': <String, Object?>{'value': 1, 'levelText': '大成功'},
            },
          });
          out.add(jsNum(_lastDice(h)['total']));
        }
        return out;
      }

      final a = totalsForSeeds(<int>[1, 2, 3, 4, 5]);
      expect(a.toSet().length, greaterThan(1),
          reason: 'B1：换 5 个种子骰面完全相同 → 根本没有在掷');
      expect(a.contains(1), isFalse,
          reason: 'B1：出现了伪造值 1（或与伪造值撞车，需要换种子重测）');
      final b = totalsForSeeds(<int>[1, 2, 3, 4, 5]);
      expect(b, a, reason: 'B1：同种子不可复现 → 随机源被污染或结果来自客户端');
    });

    test('同一房内连续两次：骰面随随机流推进而变化（不是常量）', () {
      final h = _host(seed: 11);
      _giveSheet(h, 'p1');
      final totals = <num>[];
      for (var i = 0; i < 4; i++) {
        h.intent('p1', <String, Object?>{
          'op': RoomIntent.dice,
          'p': <String, Object?>{
            'expr': '1D100',
            'label': '攻击',
            'base': 50,
            'direct': true,
            'result': <String, Object?>{'value': 1},
          },
        });
        totals.add(jsNum(_lastDice(h)['total']));
      }
      expect(totals.toSet().length, greaterThan(1),
          reason: 'B1：连续 4 次骰面完全一致 → 结果不是掷出来的');
      expect(totals.contains(1), isFalse);
    });

    test('非 1D100 骰式也走权威 rollExpr（客户端 result 同样无效）', () {
      const seed = 3;
      final expected = _rules.rollExpr('3D6', Lcg(seed).call);
      final h = _host(seed: seed);
      _giveSheet(h, 'p1');
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '3D6',
          'label': '伤害',
          'direct': true,
          'result': <String, Object?>{'value': 999, 'levelText': '大成功'},
        },
      });
      final rec = _lastDice(h);
      expect(rec['total'], expected['total'],
          reason: 'B1：3D6 的结果不等于权威 rollExpr（客户端自报 999 被采用了？）');
      expect(rec['total'], isNot(999));
      expect(asList(rec['rolls']).toList(),
          asList(expected['rolls']).toList());
      expect(jsNum(rec['total']), inInclusiveRange(3, 18));
    });

    test('旁观者（未入座）不能掷骰，且不产生任何事件', () {
      final h = _host();
      final before = h.log.seq;
      final out = h.intent('ghost', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{'expr': '1D100', 'direct': true},
      });
      // SEAT 事件：给 ghost 1 条 evt + 给两个在线玩家各 1 条 skip 水位
      final evts = out
          .map((p) => p.toJson())
          .where((j) => asMap(j['msg'])['k'] == 'evt')
          .toList();
      expect(evts, hasLength(1), reason: '只应有一条定向提示 evt');
      expect(evts.single['to'], 'ghost');
      expect(asMap(evts.single['msg'])['t'], RoomEvt.private_);
      // 不得产生掷骰
      expect(asList(h.state['dice']), isEmpty);
      expect(h.log.seq, before + 1, reason: '只允许那条定向提示进日志');
    });

    test('KP 走同一入口也是复算（result 同样无效）——与 ACT combat.roll 的差别要记清', () {
      final h = _host(seed: 5);
      h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'label': '攻击',
          'base': 50,
          'direct': true,
          'result': <String, Object?>{'value': 1, 'levelText': '大成功'},
        },
      });
      final rec = _lastDice(h);
      expect(rec['total'], isNot(1),
          reason: 'B1：KP 的 INTENT.DICE{direct} 也应复算（diceDirect 从不读 result）');
      // 对照：ACT 通道的 combat.roll 对 KP 仍采用自报 result（F4 裁决：KP 是权威端）
      h.intent(kHostSeat, <String, Object?>{
        'op': RoomIntent.act,
        'p': <String, Object?>{
          'op': 'combat.roll',
          'result': <String, Object?>{'value': 1, 'levelText': '大成功'},
        },
      });
      expect(jsNum(_lastDice(h)['total']), 1,
          reason: 'ACT combat.roll 对 KP 的既有语义（F4 裁决）被改变了');
    });

    test('夹带 target/hp/slotId/damage：不改广播目标、不产生附带结算', () {
      final h = _host(seed: 9);
      _giveSheet(h, 'p1');
      h.applyAction(kHostSeat, <String, Object?>{
        'op': 'combat.set',
        'combat': <String, Object?>{
          'order': <Object?>[
            <String, Object?>{
              'id': 'pc-p1',
              'kind': 'pc',
              'seat': 'p1',
              'public': <String, Object?>{'hp': 10, 'hpMax': 10, 'hpPublic': true},
            },
          ],
          'turn': 0,
          'round': 1,
        },
      });
      final combatBefore = asMap(h.state['combat']).toString();
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'label': '攻击',
          'base': 50,
          'direct': true,
          'target': 'p2',
          'hp': -99,
          'slotId': 'pc-p1',
          'damage': 999,
        },
      });
      expect(out, hasLength(1), reason: 'B1：夹带字段产生了额外事件');
      expect(out.single.to, '*', reason: 'B1：广播目标被夹带字段改变');
      expect(out.where((p) => p.to == 'p2').toList(), isEmpty);
      expect(asMap(h.state['combat']).toString(), combatBefore,
          reason: 'B1：夹带 slotId/damage 改了战斗槽');
      expect(jsNum(asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentHP']),
          10,
          reason: 'B1：夹带 hp 改了角色卡');
    });

    test('夹带 secret 会切成暗骰（旧版 :3060 的既有语义，如实记录）', () {
      final h = _host(seed: 4);
      _giveSheet(h, 'p1');
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'label': '偷袭',
          'base': 50,
          'direct': true,
          'secret': true,
        },
      });
      // ★ B1-F1 修复后（方案 ②）：暗骰改发 EVT.PRIVATE（SEAT 定向）
      //   本人 1 条 + KP 1 条（同一份结构化结果），其余人 skip；
      //   公共侧只留一句脱敏提示，state.dice 只承载公开骰。
      final toSelf = out
          .map((p) => p.toJson())
          .where((j) => j['to'] == 'p1' && asMap(j['msg'])['k'] == 'evt')
          .toList();
      expect(toSelf, hasLength(1), reason: '本人应收到恰好 1 条暗骰结果');
      final selfMsg = asMap(toSelf.single['msg']);
      expect(selfMsg['t'], RoomEvt.private_,
          reason: 'B1-F1：暗骰应走 PRIVATE，不再发 EVT.DICE');
      final selfP = asMap(selfMsg['p']);
      expect(selfP['kind'], 'dice-dark');
      expect(jsStr(selfP['label']), '偷袭');
      expect(jsStr(selfP['levelText']), isNotEmpty);
      // 暗骰的骰面同样必须由权威端复算（独立用 CocRules + 同种子）
      final expected = _rules.check(<String, Object?>{
        'kind': 'skill',
        'base': 50,
        'difficulty': 'REGULAR',
        'bonus': 0,
        'penalty': 0,
        'label': '偷袭',
        'rng': Lcg(4).call,
      });
      expect(selfP['total'], expected['value'],
          reason: 'B1-F1：暗骰的骰面不是权威复算值');
      expect(selfP['levelText'], expected['levelText']);
      expect(jsNum(selfP['total']), inInclusiveRange(1, 100));

      // 隐私面：公共 dice 全空（权威态 / 他人同步 / 存档 / 裁剪视图）
      expect(asList(h.state['dice']), isEmpty,
          reason: 'B1-F1：暗骰仍落进公共 state.dice');
      expect(asList(asMap(h.syncFor('p2').toJson()['state'])['dice']), isEmpty,
          reason: 'B1-F1：暗骰出现在其他玩家的全量同步里');
      expect(asList(asMap(h.syncFor('ghost').toJson()['state'])['dice']), isEmpty,
          reason: 'B1-F1：暗骰出现在陌生座位的全量同步里');
      expect(asList(asMap(h.save())['dice']), isEmpty,
          reason: 'B1-F1：暗骰写进了 save()');
      final view = playerViewFromSave(h.save(), 'p2')!;
      expect(asList(asMap(view.toJson()['state'])['dice']), isEmpty,
          reason: 'B1-F1：重连/旁观者的裁剪视图里还有暗骰');
      // 字节级：别人的全量同步里连「明细」字样都不该出现
      expect(h.syncFor('p2').toJson().toString().contains('明细'), isFalse,
          reason: 'B1-F1：暗骰明文经别的字段泄漏到 p2 的同步里');

      // 本人与 KP 都要能拿到完整结果（重连可补回：privateBySeat 带文本）
      expect(h.privateBySeat['p1'], hasLength(1));
      expect(h.privateBySeat[kHostSeat], hasLength(1));
      final selfText = jsStr(asMap(h.privateBySeat['p1']!.single)['text']);
      expect(selfText, contains('暗骰 1D100'));
      expect(selfText, contains('偷袭'));
      expect(selfText, contains('${jsNum(selfP['total'])}'),
          reason: 'B1-F1：privateBySeat 的文本里没有骰面，重连后无法还原');
      expect(jsStr(asMap(h.privateBySeat[kHostSeat]!.single)['text']), selfText);

      // 公共日志：脱敏，且**不含骰面**
      final logRow = asMap(asList(h.state['logs']).last);
      expect(logRow['kind'], 'dice-dark');
      expect(jsStr(logRow['text']), contains('暗骰'));
      expect(jsStr(logRow['text']), contains('只有他/她与 KP 可见'));
      expect(jsStr(logRow['text']).contains('${jsNum(selfP['total'])}'), isFalse,
          reason: 'B1-F1：公共日志里出现了骰面');
      // KP 必须能收到完整结果（否则没法裁定），且与本人那份一致
      final toHost = out
          .map((p) => p.toJson())
          .where((j) => j['to'] == kHostSeat && asMap(j['msg'])['k'] == 'evt')
          .toList();
      expect(toHost, hasLength(1), reason: '暗骰结果没有发给 KP');
      expect(asMap(toHost.single['msg'])['t'], RoomEvt.private_);
      expect(asMap(asMap(toHost.single['msg'])['p'])['total'], selfP['total']);
    });
  });

  // ==========================================================
  // 2) INTENT.SAN_CHECK —— 检定与扣减都走规则服务
  // ==========================================================
  group('B1-2 playerSanCheck：SAN 检定由权威端算', () {
    /// 独立复算：[san, maxSan, lossExpr] → resolveSanCheck 的预期。
    Map<String, Object?> expectedSan(
      int seed,
      num san,
      num maxSan,
      String lossExpr,
    ) =>
        _rules.resolveSanCheck(<String, Object?>{
          'currentSan': san,
          'maxSan': maxSan,
          'lossExpr': lossExpr,
          'rng': Lcg(seed).call,
        });

    test('检定值 / 损失 / 分支：与 CocRules.resolveSanCheck 逐字段一致', () {
      const seed = 6;
      const san = 50;
      const maxSan = 60;
      final exp2 = expectedSan(seed, san, maxSan, '0/1D6');
      final h = _host(seed: seed);
      _giveSheet(h, 'p1', san: san, maxSan: maxSan);
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.sanCheck,
        'p': <String, Object?>{'okLoss': '0', 'loss': '1D6', 'reason': '见到怪物'},
      });
      expect(out, isNotEmpty, reason: 'B1：SAN_CHECK 必须产生结算');
      final check = asMap(exp2['check']);
      final rec = _diceLabeled(h, 'SAN Check（');
      expect(rec['total'], check['value'],
          reason: 'B1：SAN 检定值不等于规则服务复算值');
      expect(rec['levelText'], check['levelText']);
      // SAN 扣减 = 规则服务给出的 loss
      final after = jsNum(
          asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentSAN']);
      expect(after, san - jsNum(exp2['loss']),
          reason: 'B1：SAN 扣减与规则服务的 loss 不一致');
      if (jsNum(exp2['loss']) > 0) {
        expect(h.sanLostThisRound.containsKey('p1'), isTrue,
            reason: 'B1：有 SAN 损失却没记进本回合累计（疯狂判定会失效）');
        expect(h.sanLostThisRound['p1'], greaterThanOrEqualTo(jsNum(exp2['loss'])));
      }
    });

    test('单次损失 ≥5 → 临时疯狂判定，且 INT 检定也由权威端掷', () {
      const seed = 6;
      final exp2 = expectedSan(seed, 50, 60, '0/1D6');
      expect(jsNum(exp2['loss']), greaterThanOrEqualTo(5),
          reason: '前置：seed=$seed 下这次损失应 ≥5（规则书触发临时疯狂）');
      final h = _host(seed: seed);
      _giveSheet(h, 'p1', san: 50, maxSan: 60);
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.sanCheck,
        'p': <String, Object?>{'okLoss': '0', 'loss': '1D6'},
      });
      final mental = asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
      expect(mental, contains('临时疯狂'),
          reason: 'B1：损失 ≥5 未进入临时疯狂（afterSanLoss 的阈值分支没走）');
      // 疯狂发作的 INT 检定必须是权威端掷出来的
      final intCheck = _diceLabeled(h, '临时疯狂 INT 检定');
      expect(jsNum(intCheck['total']), inInclusiveRange(1, 100));
      expect(asList(asMap(h.roster.get('p1')!['sheet'])['madness']), isNotEmpty,
          reason: 'B1：临时疯狂没有掷出症状（madness 为空）');
    });

    test('客户端自报 loss / success / passed / roll 一律被忽略', () {
      const seed = 6;
      final exp2 = expectedSan(seed, 50, 60, '0/1D6');
      final h = _host(seed: seed);
      _giveSheet(h, 'p1', san: 50, maxSan: 60);
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.sanCheck,
        'p': <String, Object?>{
          'okLoss': '0',
          'loss': '1D6',
          // 全是伪造：想让自己「成功且不掉 SAN」
          'success': true,
          'passed': true,
          'lossValue': 0,
          'sanLoss': 0,
          'roll': 1,
          'value': 1,
          'levelText': '大成功',
        },
      });
      expect(jsNum(_diceLabeled(h, 'SAN Check（')['total']),
          jsNum(asMap(exp2['check'])['value']),
          reason: 'B1：客户端自报 roll 被采用');
      final after = jsNum(
          asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentSAN']);
      expect(after, 50 - jsNum(exp2['loss']),
          reason: 'B1：客户端自报 loss=0 被采用');
    });

    test('SAN 归零 → 永久疯狂（走 afterSanLoss 的规则分支）', () {
      final h = _host(seed: 1);
      _giveSheet(h, 'p1', san: 1, maxSan: 60);
      // 反复掷到扣减为止：SAN=1 时任意正损失都会归零
      for (var i = 0; i < 6; i++) {
        h.intent('p1', <String, Object?>{
          'op': RoomIntent.sanCheck,
          'p': <String, Object?>{'okLoss': '1D6', 'loss': '1D6'},
        });
        final mental =
            asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
        if (mental.contains('永久疯狂')) break;
      }
      final mental =
          asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
      expect(mental, contains('永久疯狂'),
          reason: 'B1：SAN 归零未触发永久疯狂（afterSanLoss 没接上）');
      expect(jsNum(asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentSAN']),
          0);
      // 撕卡后再点一次也不得把 SAN 抬回去（仍走规则服务，只做 0 下限夹取）
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.sanCheck,
        'p': <String, Object?>{'okLoss': '0', 'loss': '1D6'},
      });
      expect(jsNum(asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentSAN']),
          0);
    });

    test('未绑定角色卡 / 旁观者：拒绝且零副作用', () {
      final h = _host();
      final rosterBefore = h.roster.dump().toString();
      for (final seat in <String>['p2', 'ghost']) {
        final out = h.intent(seat, <String, Object?>{
          'op': RoomIntent.sanCheck,
          'p': <String, Object?>{'okLoss': '0', 'loss': '1D6'},
        });
        final evts = out
            .map((p) => p.toJson())
            .where((j) => asMap(j['msg'])['k'] == 'evt')
            .toList();
        expect(evts, hasLength(1), reason: '$seat：应只回一条提示');
        expect(asMap(evts.single['msg'])['t'], RoomEvt.private_);
      }
      // 只允许那两条定向提示进日志；不掷骰、不动角色卡
      expect(asList(h.state['dice']), isEmpty);
      expect(h.roster.dump().toString(), rosterBefore);
      // 定向提示进收件人自己的 privateBySeat；**不进** KP 的 state.privates
      // （reduce 的 PRIVATE 守卫：vis=seat 且 to != host 时不写 state.privates）
      expect(h.privateBySeat['p2']?.length, 1);
      expect(h.privateBySeat['ghost']?.length, 1);
      expect(asList(h.state['privates']), isEmpty,
          reason: '别人的定向提示不应混进 KP 的私密栏');
    });

    test('损失格式非法：拒绝且不扣 SAN', () {
      final h = _host();
      _giveSheet(h, 'p1', san: 40);
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.sanCheck,
        'p': <String, Object?>{'okLoss': '???', 'loss': '@@@'},
      });
      expect(
        out.where((p) => asMap(p.toJson()['msg'])['k'] == 'evt').length,
        1,
        reason: '非法损失式应只回 1 条定向提示',
      );
      expect(jsNum(asMap(asMap(h.roster.get('p1')!['sheet'])['status'])['currentSAN']),
          40);
      expect(asList(h.state['dice']), isEmpty);
    });
  });

  // ==========================================================
  // 3) INTENT.OPPOSED —— 玩家两阶段都只报「选什么」，数值全来自权威态
  // ==========================================================
  group('B1-3 opposed：玩家不能自报对抗数值', () {
    RoomHost combatHost({int seed = 1}) {
      final h = _host(seed: seed);
      _giveSheet(
        h,
        'p1',
        weapons: <Object?>[
          <String, Object?>{
            'name': '手枪',
            'skill': '射击',
            'damage': '1D10',
            'pierce': '0',
            'perRound': '1',
            'malfunction': '98',
            'ammo': '8',
            'broken': false,
          },
        ],
        skills: <Object?>[
          <String, Object?>{'id': 'firearms', 'name': '射击', 'total': 70},
        ],
      );
      // 战斗：0 号槽是 p1（所以 isMyActionTurn 成立），1 号槽是怪物
      h.state['combat'] = <String, Object?>{
        'order': <Object?>[
          <String, Object?>{
            'id': 'pc-p1',
            'actorId': 'pc-p1',
            'kind': 'pc',
            'seat': 'p1',
            'name': '甲',
            'public': <String, Object?>{'hp': 10, 'hpMax': 10, 'hpPublic': true},
          },
          <String, Object?>{
            'id': 'm1',
            'actorId': 'm1',
            'kind': 'monster',
            'name': '食尸鬼',
            'public': <String, Object?>{'hp': 20, 'hpMax': 20, 'hpPublic': false},
          },
        ],
        'turn': 0,
        'round': 1,
      };
      return h;
    }

    test('申请阶段：武器伤害/skill/db 取自角色卡，客户端自报被忽略', () {
      final h = combatHost();
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.opposed,
        'p': <String, Object?>{
          'weapon': <String, Object?>{
            'name': '手枪',
            // 伪造字段：不得覆盖卡上的值
            'damage': '99D99',
            'skill': '神圣打击',
          },
          'targetId': 'm1',
          'db': '99D99',
          'shots': 9,
          // 伪造裁定结果
          'a': <String, Object?>{'value': 1, 'levelText': '大成功'},
          'b': <String, Object?>{'value': 100, 'levelText': '大失败'},
          'winner': 'a',
        },
      });
      expect(out, isNotEmpty);
      final st = asMap(h.state['opposed']);
      expect(st['phase'], 'await_kp', reason: 'B1：玩家申请应进入待 KP 处理');
      expect(asMap(st['weapon'])['damage'], '1D10',
          reason: 'B1：武器伤害式被客户端自报覆盖');
      expect(asMap(st['weapon'])['skill'], '射击',
          reason: 'B1：武器技能被客户端自报覆盖');
      expect(st['db'], '0', reason: 'B1：伤害加成被客户端自报覆盖');
      expect(st.containsKey('win'), isFalse,
          reason: 'B1：申请阶段就出现了客户端伪造的裁定结果');
      expect(st['shots'], 1, reason: 'B1：perRound=1 的武器只允许 1 发');
    });

    test('目标阶段：a/b 数值与等级取自权威 win，客户端自报被忽略', () {
      final h = combatHost(seed: 2);
      // 权威端裁定：与真机同一条链（CocRules.check ×2 → opposedFull），
      // 再按 opposedAttackResolve 写入 state.opposed 的形状组装。
      final rng = Lcg(2).call;
      final aRes = _rules.check(<String, Object?>{
        'kind': 'opposed', 'base': 70, 'difficulty': 'REGULAR',
        'bonus': 0, 'penalty': 0, 'label': '甲', 'rng': rng,
      });
      final bRes = _rules.check(<String, Object?>{
        'kind': 'opposed', 'base': 60, 'difficulty': 'REGULAR',
        'bonus': 0, 'penalty': 0, 'label': '食尸鬼', 'rng': rng,
      });
      final verdict = _rules.opposedFull(aRes, bRes, <String, Object?>{'rng': rng});
      final win = <String, Object?>{
        'a': <String, Object?>{
          'name': '甲',
          'value': aRes['value'],
          'level': aRes['level'],
          'levelText': aRes['levelText'],
        },
        'b': <String, Object?>{
          'name': '食尸鬼',
          'value': bRes['value'],
          'level': bRes['level'],
          'levelText': bRes['levelText'],
        },
        'reaction': '',
        'decidedBy': verdict['decidedBy'] ?? '',
        'rounds': asList(verdict['rounds']),
        'fallback': verdict['fallback'] == true,
      };
      h.state['opposed'] = <String, Object?>{
        'id': 'op1',
        'by': 'p1',
        'byName': '甲',
        'phase': 'await_target',
        'weapon': <String, Object?>{'name': '手枪', 'skill': '射击'},
        'dmgExpr': '1D10',
        'db': '0',
        'armor': 0,
        'pierce': false,
        'secret': false,
        'win': win,
      };
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.opposed,
        'p': <String, Object?>{
          'phase': 'target',
          'targetId': 'm1',
          // 伪造：想改成「乙方赢、伤害 999」
          'winner': 'b',
          'a': <String, Object?>{'value': 1, 'levelText': '大成功'},
          'b': <String, Object?>{'value': 100, 'levelText': '大失败'},
          'damage': 999,
        },
      });
      expect(out, isNotEmpty);
      final check = out
          .map((p) => p.toJson())
          .map((j) => asMap(j['msg']))
          .firstWhere((m) => m['t'] == RoomEvt.check);
      expect(asMap(check['p'])['winner'], 'a',
          reason: 'B1：客户端自报的 winner 被采用');
      final pa = asMap(asMap(check['p'])['a']);
      final pb = asMap(asMap(check['p'])['b']);
      expect(pa['value'], asMap(win['a'])['value'],
          reason: 'B1：甲方掷值不是权威 win 的值');
      expect(pb['value'], asMap(win['b'])['value'],
          reason: 'B1：乙方掷值不是权威 win 的值');
      expect(pa['levelText'], asMap(win['a'])['levelText']);
      expect(pb['levelText'], asMap(win['b'])['levelText']);
      // 伤害由权威 rollExpr 算：不可能是客户端自报 999
      final dmg = asMap(asMap(check['p'])['damage']);
      expect(jsNum(dmg['raw']), lessThan(999),
          reason: 'B1：伤害采用了客户端自报 999');
      expect(jsNum(dmg['applied']), lessThanOrEqualTo(jsNum(dmg['raw'])));
      expect(h.state['opposed'], isNull, reason: '结算后应清空待处理态');
    });

    test('秘密对抗：公共日志脱敏（无 opp 键）、明文只进 KP 的私密栏', () {
      final h = combatHost(seed: 2);
      final rng = Lcg(2).call;
      final aRes = _rules.check(<String, Object?>{
        'kind': 'opposed', 'base': 70, 'difficulty': 'REGULAR',
        'bonus': 0, 'penalty': 0, 'label': '甲', 'rng': rng,
      });
      final bRes = _rules.check(<String, Object?>{
        'kind': 'opposed', 'base': 60, 'difficulty': 'REGULAR',
        'bonus': 0, 'penalty': 0, 'label': '食尸鬼', 'rng': rng,
      });
      final verdict = _rules.opposedFull(aRes, bRes, <String, Object?>{'rng': rng});
      final win = <String, Object?>{
        'a': <String, Object?>{'name': '甲', 'value': aRes['value'], 'level': aRes['level'], 'levelText': aRes['levelText']},
        'b': <String, Object?>{'name': '食尸鬼', 'value': bRes['value'], 'level': bRes['level'], 'levelText': bRes['levelText']},
        'reaction': '',
        'decidedBy': verdict['decidedBy'] ?? '',
        'rounds': asList(verdict['rounds']),
        'fallback': verdict['fallback'] == true,
      };
      h.state['opposed'] = <String, Object?>{
        'id': 'op1',
        'by': 'p1',
        'byName': '甲',
        'phase': 'await_target',
        'weapon': <String, Object?>{'name': '手枪', 'skill': '射击'},
        'dmgExpr': '1D10',
        'db': '0',
        'armor': 0,
        'pierce': false,
        'secret': true,
        'win': win,
      };
      h.intent('p1', <String, Object?>{
        'op': RoomIntent.opposed,
        'p': <String, Object?>{'phase': 'target', 'targetId': 'm1'},
      });
      // 公共日志：只有脱敏行，且**没有** opp 键
      final rows = asList(h.state['logs']).map(asMap).toList();
      final last = rows.last;
      expect(last['kind'], 'check');
      expect(last['text'], 'KP 秘密进行了一次对抗检定');
      expect(last.containsKey('opp'), isFalse,
          reason: 'B1：秘密对抗的公共日志带了 opp 明细');
      // 明文只进 privates（KP 栏），且不广播
      final privs = asList(h.state['privates']).map(asMap).toList();
      expect(privs, isNotEmpty, reason: 'B1：秘密对抗的明文没有进 KP 私密栏');
      final hit = privs.where((p) => jsStr(p['text']).contains('攻击'));
      expect(hit, isNotEmpty);
      // 定向 to:'host' —— 明文只进 KP 的 privateBySeat
      expect(h.privateBySeat[kHostSeat], isNotNull,
          reason: 'B1：秘密对抗没有定向到 KP');
      expect(
        h.privateBySeat[kHostSeat]!.any((x) =>
            jsStr(asMap(x)['text']).contains('用「手枪」攻击')),
        isTrue,
      );
      expect(h.privateBySeat['p1'], isNull,
          reason: 'B1：秘密对抗的明文也发给了发起人（应只给 KP）');
      for (final seat in <String>['p1', 'p2', 'ghost']) {
        final view = h.syncFor(seat).toJson().toString();
        expect(view.contains('KP 秘密进行了一次对抗检定'), isTrue,
            reason: 'syncFor($seat)：应看到脱敏行');
        expect(view.contains('用「手枪」攻击'), isFalse,
            reason: 'syncFor($seat)：泄漏了秘密对抗明文');
      }
    });
  });
}
