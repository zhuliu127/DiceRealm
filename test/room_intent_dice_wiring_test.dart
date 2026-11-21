// ============================================================
// test/room_intent_dice_wiring_test.dart — P4 补丁 B1：四个 intent 接线回归
//
// 缺陷（P5 PRD 实读定位）：`RoomHost.intent` 的四个分支在 S4.2 是空壳 ——
//   · INTENT.DICE            只 emit 一条「请求掷 X」日志（direct:true 被吞）
//   · INTENT.SAN_CHECK / OPPOSED / BOARD   直接落 `default: break`
// 四个结算函数在 S4.3 已实现，却从未被意图入口调用，玩家端对应按钮全死。
//
// 修法（team-lead 裁决 A 方案）：在 intent() 四个 case 里直接调用
//   diceDirect / playerSanCheck / opposed / boardSelf，本层只汇总
//   List<SendPlan>；结算函数内部统一走 emit() → apply() 单一写口。
//
// 硬约束（本文件逐项钉死）：
//   ① 四个 op 绝不进 kRoomPolicy（权限面仍恰好 62 条，P19 +save.share）；
//   ② 既有分支（ACT 的 needs() 链 / CHAT / STATE / CHAR）一字未动；
//   ③ reduceRoomState( 仍恰好 2 调用 + 1 声明；
//   ④ 可见性三闸不变：VIS.KP 空计划 / VIS.SEAT 单发+skip / 秘密检定脱敏。
//
// 本文件全部为 Dart-only 行为测试与静态源码探针，不参与 oracle 比较、
// 不登记白名单、不改任何 fixture。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_state.dart' show needs;
import 'package:dice_realm/domain/room_rules.dart' show CocRules;
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show Lcg, oracleNowMs;
import 'support/room_fakes.dart';

/// 固定 seed 的双人房：两次 attach 占 seq1/seq2，后续 emit 从 seq3 起。
RoomHost _host({int seed = 1}) {
  final h = RoomHost(roomHostOpts(seed: seed));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  return h;
}

/// ACT 通道的动作消息（供 check.opposed 端到端用例使用）。
Map<String, Object?> _act(String op, Map<String, Object?> p) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

/// 直接掷骰意图：夹带一份客户端自报的伪造结果，用来证明权威端复算。
Map<String, Object?> _diceDirect({String expr = '1D6'}) =>
    <String, Object?>{
      'op': RoomIntent.dice,
      'p': <String, Object?>{
        'direct': true,
        'expr': expr,
        'result': <String, Object?>{
          'value': 999,
          'levelText': '伪造',
          'rolls': <Object?>[999],
        },
      },
    };

/// 最小人物卡（带 currentSAN，供 SAN Check 结算读取）。
Map<String, Object?> _sheet(int san) => <String, Object?>{
      'name': '张三',
      'status': <String, Object?>{
        'currentSAN': san,
        'maxSAN': 99,
        'currentHP': 10,
        'maxHP': 12,
      },
      'mental': <Object?>[],
    };

/// 自助 SAN Check 的标准入参（成功损失 0 / 失败损失 1D6）。
Map<String, Object?> _sanIntent() => <String, Object?>{
      'op': RoomIntent.sanCheck,
      'p': <String, Object?>{'okLoss': '0', 'loss': '1D6'},
    };

/// 读权威人物卡的 currentSAN（stateApply 会把扣减写回这里）。
num _sanOf(RoomHost h, String seat) {
  final mem = h.roster.get(seat)!;
  final status = asMap(asMap(mem['sheet'])['status']);
  return jsNum(status['currentSAN']);
}

/// 公共日志文本列表。
List<String> _texts(RoomHost h) => asList(h.state['logs'])
    .map((Object? e) => jsStr(asMap(e)['text']))
    .toList();

/// 每条发送计划的收件人。
List<String> _tos(List<SendPlan> out) =>
    out.map((SendPlan s) => jsStr(s.toJson()['to'])).toList();

/// 静态判据用：剥掉 `//` 行注释，避免把说明文字里的示例当成代码。
String _codeOf(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .map((String line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  group('B1 · INTENT.DICE{direct:true} 接通权威掷骰', () {
    test('① KP 与两名 player 各发一次：落 state.dice、丢弃自报、广播 *', () {
      for (final seat in <String>[kHostSeat, 'p1', 'p2']) {
        final h = _host();
        final out = h.intent(seat, _diceDirect());
        expect(out, isNotEmpty, reason: 'B1 接线前该分支没有 dice 事件');
        expect(out.length, 1, reason: 'PUBLIC 事件只产生一条 * 计划');
        final dice = asList(h.state['dice']);
        expect(dice.length, 1, reason: '权威态新增一条掷骰记录');
        final rec = asMap(dice.single);
        expect(rec['seat'], seat);
        expect(rec['expr'], '1D6');
        expect(rec['total'], 2,
            reason: 'seed=1 的 rollExpr(1D6) 权威结果为 2');
        expect(rec['total'], isNot(999), reason: '不得照搬客户端 result.value');
        expect(rec['levelText'], isNot('伪造'),
            reason: '不得照搬客户端等级文本');
        expect(asList(rec['rolls']), isNotEmpty,
            reason: '骰组明细由规则服务产出，不是客户端的 [999]');
        expect(asList(rec['rolls']), isNot(<Object?>[999]));
        final msg = asMap(out.single.toJson()['msg']);
        expect(msg['k'], 'evt');
        expect(msg['t'], 'dice');
        expect(_tos(out), <String>['*'], reason: 'dice 走 PUBLIC 的 to:* 广播');
      }
    });

    test('② 两个不同骰式都走权威复算，结果落在合法区间', () {
      for (final expr in <String>['1D6', '2D6']) {
        final h = _host();
        h.intent('p1', _diceDirect(expr: expr));
        final rec = asMap(asList(h.state['dice']).single);
        expect(rec['expr'], expr);
        expect(rec['total'], isA<num>());
        expect(rec['total'] as num, greaterThanOrEqualTo(1));
        expect(rec['total'] as num, lessThanOrEqualTo(expr == '1D6' ? 6 : 12));
        expect(rec['total'], isNot(999), reason: '换骰式也不能把伪造值写进去');
      }
    });

    test('③ 非 direct 分支保持 S4.2 原语义（只记请求日志，不掷骰）', () {
      final h = _host();
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{'expr': '1D6'},
      });
      expect(asList(h.state['dice']), isEmpty,
          reason: '非 direct 不得触发 diceDirect');
      expect(_texts(h), <String>['甲 请求掷 1D6']);
      expect(_tos(out), <String>['*']);
      final p = asMap(asMap(out.single.toJson()['msg'])['p']);
      expect(p['kind'], 'dice-request');
      expect(p['expr'], '1D6');
    });
  });

  group('B1 · INTENT.SAN_CHECK 接通 SAN 结算与疯狂判定', () {
    test('④ 成功分支：SAN 不变、产出权威掷骰记录与成功日志', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = _sheet(60);
      final out = h.intent('p1', _sanIntent());
      expect(out, isNotEmpty, reason: 'B1 接线前该分支是空计划');
      expect(_sanOf(h, 'p1'), 60, reason: '成功分支无理智损失');
      final dice = asList(h.state['dice']);
      expect(dice.length, 1);
      final rec = asMap(dice.single);
      expect(rec['label'], 'SAN Check（对 60）');
      expect(rec['total'], 32, reason: 'seed=1 的 rules.check 掷值');
      expect(_texts(h).length, 1);
      expect(_texts(h).single, contains('成功 支 0，无理智损失'));
    });

    test('⑤ 失败分支：按 seed 扣减 SAN 并写回权威人物卡', () {
      final cases = <Map<String, Object?>>[
        <String, Object?>{'seed': 1, 'san': 16, 'loss': 4},
        <String, Object?>{'seed': 2, 'san': 18, 'loss': 2},
        <String, Object?>{'seed': 7, 'san': 16, 'loss': 4},
      ];
      for (final c in cases) {
        final h = _host(seed: c['seed']! as int);
        h.roster.get('p1')!['sheet'] = _sheet(20);
        final out = h.intent('p1', _sanIntent());
        expect(out, isNotEmpty);
        expect(_sanOf(h, 'p1'), c['san'], reason: 'seed=${c['seed']} 扣减落库');
        final texts = _texts(h);
        expect(texts[0], contains('失败 支 1D6，理智损失 ${c['loss']}'));
        expect(texts[1], contains('SAN Check 失败 -${c['loss']}'));
      }
      // 同一张卡换 seed 走成功分支：证明分支由权威掷值决定，不是恒定失败。
      final ok = _host(seed: 8);
      ok.roster.get('p1')!['sheet'] = _sheet(20);
      ok.intent('p1', _sanIntent());
      expect(_sanOf(ok, 'p1'), 20, reason: 'seed=8 掷 2（极难成功），SAN 不变');
      expect(_texts(ok).single, contains('成功 支 0'));
    });

    test('⑥ 单次损失 ≥5 触发 INT 检定与临时疯狂（afterSanLoss 已接线）', () {
      for (final seed in <int>[3, 6]) {
        final h = _host(seed: seed);
        h.roster.get('p1')!['sheet'] = _sheet(20);
        h.intent('p1', _sanIntent());
        expect(_sanOf(h, 'p1'), 14, reason: 'seed=$seed 损失 6');
        final texts = _texts(h);
        expect(texts[0], contains('理智损失 6，SAN 20 → 14'));
        expect(
          texts.any((String t) =>
              t.contains('INT 检定成功') && t.contains('进入疯狂发作')),
          isTrue,
          reason: '临时疯狂的 INT 检定分支被触发',
        );
        expect(
          texts.any((String t) =>
              t.contains('临时疯狂发作：恐高（持续 3 轮）')),
          isTrue,
          reason: '疯狂症状经 stateApply 写回权威态',
        );
        final mental =
            asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
        expect(mental, isNotEmpty, reason: '人物卡 mental 数组被写入');
      }
    });
  });

  group('B1 · INTENT.OPPOSED 接通对抗申请与裁定', () {
    test('⑦ 分支非 no-op：无武器时回定向提示（接线前是空计划）', () {
      final h = _host();
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.opposed,
        'p': <String, Object?>{'weapon': <String, Object?>{'name': '手枪'}},
      });
      expect(out, isNotEmpty, reason: 'B1 接线前该分支返回空列表');
      expect(h.state['opposed'], isNull);
      expect(_tos(out), <String>['p1', 'p2']);
      final p = asMap(asMap(out.first.toJson()['msg'])['p']);
      expect(p['text'], '你的角色卡里没有这把武器「手枪」，无法发起对抗');
      expect(asMap(out.last.toJson()['msg'])['k'], 'skip');
    });

    test('⑧ 完整申请链路把 await_kp 写进权威态，只给 KP 发 evt', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        'db': '0',
        'weapons': <Object?>[
          <String, Object?>{
            'name': '手枪',
            'skill': '射击',
            'damage': '1D10',
            'perRound': '1',
            'ammo': '6',
            'malfunction': '96',
            'pierce': false,
            'broken': false,
          },
        ],
        'skills': <Object?>[
          <String, Object?>{'name': '射击', 'total': 60},
        ],
      };
      // 夹具预置初始权威态（战斗轮到 p1），不是结算写入；结算仍只经 apply。
      h.state['combat'] = <String, Object?>{
        'order': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'actorId': 'p1',
            'kind': 'pc',
            'seat': 'p1',
            'name': '甲',
          },
          <String, Object?>{
            'id': 'm1',
            'actorId': 'm1',
            'kind': 'monster',
            'name': '深潜者',
            'public': <String, Object?>{'hp': 10},
          },
        ],
        'turn': 0,
      };
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.opposed,
        'p': <String, Object?>{
          'weapon': <String, Object?>{'name': '手枪'},
          'targetId': 'm1',
        },
      });
      final opp = asMap(h.state['opposed']);
      expect(opp['id'], 'op1');
      expect(opp['by'], 'p1');
      expect(opp['phase'], 'await_kp');
      expect(opp['targetId'], 'm1');
      expect(asMap(opp['weapon'])['name'], '手枪');
      expect(_tos(out), contains('host'), reason: '申请事件定向 KP');
      final first = asMap(out.first.toJson()['msg']);
      expect(first['t'], 'opposed');
      expect(first['k'], 'evt');
    });

    test('⑨ check.opposed 端到端裁定与 CocRules.opposed 完全一致', () {
      final h = _host();
      h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'aBase': 70,
        'bBase': 30,
        'aSkill': '侦查',
        'bSkill': '潜行',
        'aSeat': 'p1',
        'bSeat': 'p2',
      }));
      final rec = asMap(asList(h.state['logs']).single);
      expect(rec['kind'], 'check');
      expect(rec['text'], contains('⚔ 对抗'));
      final opp = asMap(rec['opp']);
      expect(asMap(opp['a'])['value'], 32);
      expect(asMap(opp['b'])['value'], 75);
      expect(opp['winner'], 'a');
      expect(opp['tie'], false);
      expect(opp['decidedBy'], 'level');

      // 用同一规则服务 + 同 seed 的 LCG 独立复算，逐字段对照。
      const rules = CocRules();
      final lcg = Lcg(1);
      final a = rules.check(<String, Object?>{
        'base': 70,
        'kind': 'opposed',
        'label': '甲',
        'rng': lcg.call,
      });
      final b = rules.check(<String, Object?>{
        'base': 30,
        'kind': 'opposed',
        'label': '乙',
        'rng': lcg.call,
      });
      final verdict = rules.opposed(a, b);
      expect(verdict['winner'], opp['winner']);
      expect(verdict['decidedBy'], opp['decidedBy']);
      expect(a['value'], asMap(opp['a'])['value']);
      expect(b['value'], asMap(opp['b'])['value']);
    });

    test('⑩ 秘密对抗仍脱敏：明文只进 privates/发 host，公共流只有占位日志', () {
      final h = _host();
      final out = h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'aBase': 70,
        'bBase': 30,
        'aSkill': '侦查',
        'bSkill': '潜行',
        'aSeat': 'p1',
        'bSeat': 'p2',
        'secret': true,
      }));
      final logs = asList(h.state['logs']);
      expect(logs.length, 1);
      final log = asMap(logs.single);
      expect(log['text'], 'KP 秘密进行了一次对抗检定');
      expect(log.containsKey('opp'), isFalse,
          reason: '公共流不得带裁定明细');
      expect(log['seat'], '');
      final privates = asList(h.state['privates']);
      expect(privates, isNotEmpty);
      final secret = asMap(privates.first);
      expect(secret['kind'], 'opposed');
      expect(jsStr(secret['text']), contains('⚔ 对抗'));
      // 明文 evt 只发 host，p1/p2 收 skip；占位 log 才广播 *。
      expect(_tos(out).first, 'host');
      expect(asMap(asMap(out.first.toJson()['msg'])['p'])['title'], '秘密对抗');
      expect(
        out
            .where((SendPlan s) => s.toJson()['to'] == 'p1')
            .any((SendPlan s) => asMap(s.toJson()['msg'])['k'] == 'skip'),
        isTrue,
      );
      expect(
        out.any((SendPlan s) =>
            s.toJson()['to'] == '*' &&
            asMap(asMap(s.toJson()['msg'])['p'])['text'] ==
                'KP 秘密进行了一次对抗检定'),
        isTrue,
      );
    });
  });

  group('B1 · INTENT.BOARD 接通手绘板落笔', () {
    test('⑪ 落笔写进 state.board / scene.boards / boardBySeat，且只回本人', () {
      final h = _host();
      final strokes = <Object?>[
        <String, Object?>{'x': 1, 'y': 2},
        <String, Object?>{'x': 3, 'y': 4},
      ];
      final out = h.intent('p1', <String, Object?>{
        'op': RoomIntent.board,
        'p': <String, Object?>{'strokes': strokes},
      });
      final board = asMap(h.state['board']);
      expect(asList(board['strokes']).length, 2);
      expect(asMap(asList(board['strokes']).first)['x'], 1);
      expect(asMap(asList(board['strokes']).last)['y'], 4);
      expect(board['at'], oracleNowMs);
      final boards = asMap(asMap(h.state['scene'])['boards']);
      final mine = asMap(boards['p1']);
      expect(mine['count'], 2);
      expect(mine['thumb'], '');
      expect(mine['at'], oracleNowMs);
      expect(asMap(h.boardBySeat['p1'])['at'], oracleNowMs);
      expect(asList(asMap(h.boardBySeat['p1'])['strokes']).length, 2);
      // 可见性：p1 收 evt，p2 只收 skip 水位。
      expect(_tos(out), <String>['p1', 'p2']);
      final msg = asMap(out.first.toJson()['msg']);
      expect(msg['t'], 'board');
      expect(asMap(msg['p'])['self'], true);
      expect(asMap(out.last.toJson()['msg'])['k'], 'skip');
    });
  });

  group('B1 · 接线后可见性三闸未被破坏', () {
    test('⑫ VIS.KP 空计划；VIS.SEAT 单发 evt + 其余在线者 skip', () {
      final h = _host();
      final kpRec = h.emit('x', <String, Object?>{'q': 1}, vis: RoomVis.kp);
      expect(h.plan(kpRec), isEmpty);
      final seatRec = h.emit(RoomEvt.private_, <String, Object?>{
        'title': 'T',
        'text': 'X',
        'at': 1,
      }, vis: RoomVis.seat, to: 'p1');
      final plans = h.plan(seatRec);
      expect(plans.length, 2);
      expect(_tos(plans), <String>['p1', 'p2']);
      expect(asMap(plans[0].toJson()['msg'])['k'], 'evt');
      expect(asMap(plans[1].toJson()['msg'])['k'], 'skip');
      expect(asMap(asMap(plans[0].toJson()['msg'])['p'])['text'], 'X');
    });
  });

  group('B1 · 权限面 / 单一写口 / 源码钉子', () {
    test('⑬ kRoomPolicy 仍恰好 62 条，四个 intent op 名一个都不在', () {
      expect(kRoomPolicy.length, 62,
          reason: 'B1 不得把四个 op 加进 POLICY；P19 +save.share 后总数 62'
              '（62 → 66 会打穿门禁）');
      for (final op in <String>[
        RoomIntent.dice,
        RoomIntent.sanCheck,
        RoomIntent.opposed,
        RoomIntent.board,
      ]) {
        expect(kRoomPolicy.containsKey(op), isFalse,
            reason: '$op 不在 POLICY');
      }
      // ACT 通道的既有别名仍在，证明没有误删既有登记。
      expect(kRoomPolicy.containsKey('dice.request'), isTrue);
      expect(kRoomPolicy.containsKey('board.self'), isTrue);
      expect(kRoomPolicy.containsKey('check.opposed'), isTrue);
      expect(kRoomPolicy.containsKey('sheet.sancheck'), isTrue);
      expect(needs(RoomRole.kp, 'check.opposed').allowed, isTrue);
    });

    test('⑭ reduceRoomState( 仍恰好 2 调用 + 1 声明，调用点固定', () {
      var calls = 0;
      var decls = 0;
      final callSites = <String>[];
      final dir = Directory('lib/domain');
      for (final entity in dir.listSync().whereType<File>()) {
        if (!entity.path.endsWith('.dart')) continue;
        final name = entity.uri.pathSegments.last;
        final lines = _codeOf(entity.path).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!line.contains('reduceRoomState(')) continue;
          if (RegExp(r'^\s*Map<String, Object\?> reduceRoomState\(')
              .hasMatch(line)) {
            decls += 1;
          } else {
            calls += 1;
            callSites.add(name);
          }
        }
      }
      expect(calls, 2, reason: '接线不得新增直接归约调用');
      expect(decls, 1);
      expect(callSites.contains('room_model_host_core.dart'), isTrue);
      expect(callSites.contains('room_model_client.dart'), isTrue);
    });

    test('⑮ 四个 case 的接线源码钉子 + 既有分支原文仍在', () {
      final src = _codeOf('lib/domain/room_model_host_intent.dart');
      expect(src.contains("if (jsTruthy(p['direct'])) {"), isTrue);
      expect(src.contains('out.addAll(diceDirect(seat, mem, role, p));'),
          isTrue);
      expect(src.contains('out.addAll(playerSanCheck(seat, mem, p));'), isTrue);
      expect(src.contains('out.addAll(opposed(seat, mem, role, p));'), isTrue);
      expect(src.contains('out.addAll(boardSelf(seat, p));'), isTrue);
      // 既有分支一字未动。
      expect(src.contains('out.addAll(act(seat, mem, role, p));'), isTrue);
      expect(src.contains('case RoomIntent.chat:'), isTrue);
      expect(src.contains('final verdict = needs(role, op);'), isTrue,
          reason: 'ACT 的 needs() 权限链保留');
      expect(src.contains("'kind': 'dice-request'"), isTrue,
          reason: 'DICE 非 direct 分支保留');
    });
  });
}
