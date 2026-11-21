// ============================================================
// test/room_intent_dark_dice_privacy_test.dart — B1-F1 暗骰隐私回归
//
// 缺陷（QA 复验 B1 实测）：`diceDirect` 的暗骰分支 emit 了两条
// `EVT.DICE`(VIS.SEAT, to=本人/KP)，而 `reduceRoomState` 的 DICE 分支
// **不看 evt.vis**，一律 push 进公共 `state.dice`；`makeSync` / `save()`
// 又全量下发 `dice`，于是暗骰结果被其他玩家、旁观点与存档读到，
// 与公共日志承诺的「只有他/她与 KP 可见」直接矛盾。
// 旧版 room-model.js:612-618 / :1290 同源，是 B1 接线后才首次可达的潜伏缺陷。
//
// 修法（team-lead 裁决方案 ②：只在 diceDirect 侧分流）：
//   · 暗骰改发 `EVT.PRIVATE`(VIS.SEAT) 给本人与 KP，完整结果只进
//     `privateBySeat`（syncFor 按 seat 裁剪），`state.dice` 只承载公开骰；
//   · 公共侧只留一句脱敏 LOG（文案沿用旧版）；
//   · 公开骰路径一字不动，reduce 的 DICE 分支 / makeSync / save 均不动。
//
// 本文件为 Dart-only 行为测试 + 静态源码探针，不参与 oracle 比较、
// 不登记白名单、不改任何 fixture。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

/// 固定 seed 的双人房：两次 attach 占 seq1/seq2，后续 emit 从 seq3 起。
RoomHost _host({int seed = 4}) {
  final h = RoomHost(roomHostOpts(seed: seed));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  return h;
}

/// 玩家暗骰（B1 接线后可直达 `diceDirect`）。
Map<String, Object?> _dark() => <String, Object?>{
      'op': RoomIntent.dice,
      'p': <String, Object?>{
        'expr': '1D100',
        'label': '偷袭',
        'base': 50,
        'direct': true,
        'secret': true,
      },
    };

/// 玩家公开骰（回归基线：行为必须与 B1-F1 之前完全一致）。
Map<String, Object?> _open() => <String, Object?>{
      'op': RoomIntent.dice,
      'p': <String, Object?>{
        'expr': '1D6',
        'label': '明骰',
        'direct': true,
      },
    };

/// 每条发送计划的收件人。
List<String> _tos(List<SendPlan> out) =>
    out.map((SendPlan s) => jsStr(s.toJson()['to'])).toList();

/// 信封里的 `state` 视图。
Map<String, Object?> _stateOf(Object? envelope) =>
    asMap(asMap(envelope)['state']);

/// 公共日志文本列表。
List<String> _texts(RoomHost h) => asList(h.state['logs'])
    .map((Object? e) => jsStr(asMap(e)['text']))
    .toList();

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
  group('B1-F1 · 暗骰结果不再进公共 state.dice', () {
    test('① state.dice 为空；公共日志只有脱敏行，不含明文 total/levelText', () {
      final h = _host();
      final warningsBefore = h.warnings.length;
      final out = h.intent('p1', _dark());
      expect(out, isNotEmpty, reason: '暗骰分支仍是死按钮');
      // 修复核心：暗骰不再 emit EVT.DICE → reduce 的 DICE 分支无从 push。
      expect(asList(h.state['dice']), isEmpty,
          reason: 'B1-F1：暗骰结果仍落进了公共 state.dice');
      // 公共流只留一句脱敏提示，且不含任何明文结果。
      expect(_texts(h), <String>['甲 暗骰了一次（结果只有他/她与 KP 可见）']);
      final logRow = asMap(asList(h.state['logs']).single);
      expect(logRow['kind'], 'dice-dark');
      expect(jsStr(logRow['text']), isNot(contains('偷袭')));
      expect(jsStr(logRow['text']), isNot(contains('失败')));
      expect(jsStr(logRow['text']), isNot(contains('62')));
      expect(jsStr(logRow['text']), isNot(contains('1D100')));
      // 两条 SEAT PRIVATE 都不该触发「非 SEAT 携带私有字段」的 scrub 警告。
      expect(h.warnings.length, warningsBefore,
          reason: '暗骰不该产生可见性警告（三闸未被绕开）');
    });

    test('② 本人与 KP 各拿到完整结果（privateBySeat），其他人拿不到', () {
      final h = _host();
      final out = h.intent('p1', _dark());
      // 实时：本人 + KP 各 1 条 PRIVATE evt，p2 只有 skip。
      final selfEvt = out
          .where((SendPlan s) =>
              s.toJson()['to'] == 'p1' &&
              asMap(s.toJson()['msg'])['k'] == 'evt')
          .toList();
      final hostEvt = out
          .where((SendPlan s) =>
              s.toJson()['to'] == kHostSeat &&
              asMap(s.toJson()['msg'])['k'] == 'evt')
          .toList();
      expect(selfEvt, hasLength(1), reason: '本人应收到 1 条暗骰结果');
      expect(hostEvt, hasLength(1), reason: 'KP 应收到 1 条暗骰结果');
      for (final plan in <SendPlan>[selfEvt.single, hostEvt.single]) {
        final msg = asMap(plan.toJson()['msg']);
        expect(msg['t'], RoomEvt.private_,
            reason: '暗骰必须走 EVT.PRIVATE，不能是 EVT.DICE');
        final p = asMap(msg['p']);
        expect(p['title'], '暗骰结果');
        expect(p['kind'], 'dice-dark');
        expect(p['secret'], true);
        // 结构化完整结果：UI 可直接渲染，不必解析 text。
        expect(p['total'], 62, reason: 'seed=4 权威复算结果');
        expect(p['levelText'], '失败');
        expect(p['label'], '偷袭');
        expect(p['expr'], '1D100');
        expect(jsStr(p['text']), contains('62'));
        expect(jsStr(p['text']), contains('失败'));
        expect(jsStr(p['text']), contains('偷袭'));
      }
      // 其余在线者只收 skip 水位，拿不到任何 evt。
      final p2Plans = out
          .where((SendPlan s) => s.toJson()['to'] == 'p2')
          .toList();
      expect(p2Plans, isNotEmpty);
      expect(
        p2Plans.every((SendPlan s) => asMap(s.toJson()['msg'])['k'] == 'skip'),
        isTrue,
        reason: 'p2 不应收到暗骰 evt',
      );
      // 重连 / 全量同步：privateBySeat 按 seat 裁剪。
      final p1Priv = asList(h.privateBySeat['p1']);
      final hostPriv = asList(h.privateBySeat[kHostSeat]);
      expect(p1Priv, hasLength(1));
      expect(hostPriv, hasLength(1));
      for (final priv in <Object?>[p1Priv.single, hostPriv.single]) {
        final row = asMap(priv);
        expect(jsStr(row['title']), '暗骰结果');
        expect(jsStr(row['kind']), 'dice-dark');
        final text = jsStr(row['text']);
        expect(text, contains('62'), reason: '重连后仍要能看到完整结果');
        expect(text, contains('失败'));
        expect(text, contains('偷袭'));
        expect(text, contains('1D100'));
      }
      expect(h.privateBySeat['p2'], isNull,
          reason: '其他玩家的私密表不该被写入');
      expect(h.privateBySeat['ghost'], isNull);
      expect(asList(_stateOf(h.syncFor('p1').toJson())['privates']),
          hasLength(1));
      expect(asList(_stateOf(h.syncFor(kHostSeat).toJson())['privates']),
          hasLength(1));
      expect(asList(_stateOf(h.syncFor('p2').toJson())['privates']), isEmpty,
          reason: 'p2 的全量同步不该带暗骰明文');
    });

    test('③ syncFor(p2/ghost) / save() / playerViewFromSave 全都读不到暗骰', () {
      final h = _host();
      h.intent('p1', _dark());
      expect(asList(_stateOf(h.syncFor('p2').toJson())['dice']), isEmpty,
          reason: '其他玩家全量同步里不该有暗骰');
      expect(asList(_stateOf(h.syncFor('ghost').toJson())['dice']), isEmpty,
          reason: '旁观者全量同步里不该有暗骰');
      expect(asList(asMap(h.save())['dice']), isEmpty,
          reason: '存档不该外带暗骰');
      final view = playerViewFromSave(h.save(), 'p2');
      expect(view, isNotNull);
      final vState = _stateOf(view!.toJson());
      expect(asList(vState['dice']), isEmpty,
          reason: '重连/旁观者裁剪视图不该有暗骰');
      expect(asList(vState['privates']), isEmpty);
      final serialized = jsonEncode(view.toJson());
      expect(serialized.contains('偷袭'), isFalse,
          reason: 'p2 视图泄漏了暗骰 label');
      expect(serialized.contains('暗骰结果'), isFalse,
          reason: 'p2 视图泄漏了暗骰私密标题');
      expect(serialized.contains('失败'), isFalse,
          reason: 'p2 视图泄漏了暗骰等级文本');
      // 公共脱敏行仍在（这是唯一允许 p2 看到的信息）。
      expect(serialized.contains('甲 暗骰了一次（结果只有他/她与 KP 可见）'),
          isTrue);
      // 存档里按 seat 保留私密明细，供本人/KP 续玩（不外带 dice）。
      final bySeat = asMap(h.save())['privateBySeat'];
      expect(asMap(bySeat).containsKey('p1'), isTrue);
      expect(asMap(bySeat).containsKey(kHostSeat), isTrue);
      expect(asMap(bySeat).containsKey('p2'), isFalse);
    });
  });

  group('B1-F1 · 公开骰行为完全不变', () {
    test('④ 公开骰仍 to:*、仍进 state.dice、其他人能看见', () {
      final h = _host();
      final out = h.intent('p1', _open());
      expect(out, hasLength(1));
      expect(_tos(out), <String>['*']);
      final msg = asMap(out.single.toJson()['msg']);
      expect(msg['t'], RoomEvt.dice);
      final dice = asList(h.state['dice']);
      expect(dice, hasLength(1));
      final rec = asMap(dice.single);
      expect(rec['expr'], '1D6');
      expect(rec['total'], 2, reason: 'seed=4 的 rollExpr(1D6)');
      expect(rec['label'], '明骰');
      expect(asList(rec['rolls']), isNotEmpty);
      // 其他玩家 / 旁观者的全量同步与存档都能看到公开骰（正常路径）。
      expect(asList(_stateOf(h.syncFor('p2').toJson())['dice']), hasLength(1));
      expect(asList(_stateOf(h.syncFor('ghost').toJson())['dice']), hasLength(1));
      expect(asList(asMap(h.save())['dice']), hasLength(1));
      final view = playerViewFromSave(h.save(), 'p2')!;
      expect(asList(_stateOf(view.toJson())['dice']), hasLength(1));
      expect(jsonEncode(view.toJson()).contains('明骰'), isTrue);
      // 公开骰不产生暗骰私密明细。
      expect(h.privateBySeat['p1'], isNull);
      expect(h.privateBySeat[kHostSeat], isNull);
      expect(_texts(h), isEmpty, reason: '公开骰不应写公共日志');
    });

    test('⑤ 混合场景：先公开骰再暗骰，state.dice 只有公开那条', () {
      final h = _host();
      h.intent('p1', _open());
      h.intent('p1', _dark());
      final dice = asList(h.state['dice']);
      expect(dice, hasLength(1), reason: '暗骰不得追加到公共 dice');
      final rec = asMap(dice.single);
      expect(rec['label'], '明骰');
      expect(rec['expr'], '1D6');
      expect(rec['total'], 2);
      expect(jsonEncode(dice).contains('偷袭'), isFalse);
      // 同步 / 存档同理：只有公开骰。
      expect(asList(_stateOf(h.syncFor('p2').toJson())['dice']), hasLength(1));
      expect(asList(asMap(h.save())['dice']), hasLength(1));
      final view = playerViewFromSave(h.save(), 'p2')!;
      expect(asList(_stateOf(view.toJson())['dice']), hasLength(1));
      expect(jsonEncode(view.toJson()).contains('偷袭'), isFalse);
      // 但本人与 KP 仍各自拿到那颗暗骰的完整结果。
      expect(asList(h.privateBySeat['p1']), hasLength(1));
      expect(asList(h.privateBySeat[kHostSeat]), hasLength(1));
      expect(h.privateBySeat['p2'], isNull,
          reason: 'asList(null) 会返回空列表，这里必须直接判键是否存在');
      expect(
        _texts(h).any((String t) => t.contains('只有他/她与 KP 可见')),
        isTrue,
      );
    });

    test('⑥ KP 自己暗骰：只发 1 条 PRIVATE 给 host，state.dice 仍为空', () {
      final h = _host();
      final out = h.intent(kHostSeat, _dark());
      expect(asList(h.state['dice']), isEmpty);
      final hostEvt = out
          .where((SendPlan s) =>
              s.toJson()['to'] == kHostSeat &&
              asMap(s.toJson()['msg'])['k'] == 'evt')
          .toList();
      expect(hostEvt, hasLength(1), reason: 'KP 自己暗骰不该重复发两条');
      expect(asMap(hostEvt.single.toJson()['msg'])['t'], RoomEvt.private_);
      expect(asList(h.privateBySeat[kHostSeat]), hasLength(1));
      expect(h.privateBySeat['p1'], isNull);
      expect(_texts(h), <String>['KP 暗骰了一次（结果只有他/她与 KP 可见）']);
      expect(asList(_stateOf(h.syncFor('p2').toJson())['dice']), isEmpty);
      expect(asList(asMap(h.save())['dice']), isEmpty);
    });
  });

  group('B1-F1 · 可见性三闸与不变式未被破坏', () {
    test('⑦ VIS.KP 空计划 / VIS.SEAT 单发+skip / PUBLIC 带 secret 仍被 scrub', () {
      final h = _host();
      expect(
        h.plan(h.emit('x', <String, Object?>{'q': 1}, vis: RoomVis.kp)),
        isEmpty,
      );
      final seatRec = h.emit(RoomEvt.private_, <String, Object?>{
        'title': 'T',
        'text': 'X',
        'at': 1,
      }, vis: RoomVis.seat, to: 'p1');
      final plans = h.plan(seatRec);
      expect(plans, hasLength(2));
      expect(_tos(plans), <String>['p1', 'p2']);
      expect(asMap(plans[0].toJson()['msg'])['k'], 'evt');
      expect(asMap(plans[1].toJson()['msg'])['k'], 'skip');
      // 第 ① 道闸门：PUBLIC 载荷带私有字段仍被剥且记 1 条 warning。
      final before = h.warnings.length;
      final rec = h.emit(RoomEvt.asset, <String, Object?>{
        'assets': <Object?>[
          <String, Object?>{'id': 'a1', 'kpOnly': 'x'},
        ],
      }, vis: RoomVis.public);
      expect(h.warnings.length, before + 1);
      expect(rec.evt.p.toString().contains('kpOnly'), isFalse);
    });

    // ★ P10 第 3 期 B：本条守卫的口径**升级**了，但原意（方案 ① 未被采用：
    //   SEAT 骰点绝不进公共 state.dice）不但没放宽，反而变成机械保证。
    //   改前靠「reduce 不看 vis + 暗骰压根不 emit EVT.DICE」这条**约定**；
    //   QA `qa_p10_4_report.md` §3b 指出：emit 的 scrub 只认 kSecretKeys，
    //   `label` 不在其中，将来一条 vis:kp 的 DICE 就能把技能名写进公共骰列。
    //   现改为 reduce 侧对「非 PUBLIC 的 DICE」直接丢弃 + 记 warning。
    //   行为级反证在 `test/p10_t3b_rule_diff_test.dart` T5-1/T5-2/T5-3；
    //   本条只钉源码结构，防止有人把闸门删回「只看约定」。
    test('⑧ 静态：reduce 的 DICE 分支有「非 PUBLIC 即丢弃」机械闸门', () {
      final src = _codeOf('lib/domain/room_model_reduce.dart');
      final start = src.indexOf('case RoomEvt.dice:');
      final end = src.indexOf('case RoomEvt.scene:', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final block = src.substring(start, end);
      expect(block.contains('evt.vis != null'), isTrue,
          reason: 'vis == null 是客户端回放，必须继续按 PUBLIC 处理');
      expect(block.contains('evt.vis != RoomVis.public'), isTrue,
          reason: '非 PUBLIC 必须被拦下');
      expect(block.contains('reduceGateWarnings.add'), isTrue,
          reason: '丢弃同时要留告警，不能静默吞掉');
      expect(block.contains('break;'), isTrue);
      expect(block.contains("dice.add(<String, Object?>{"), isTrue,
          reason: 'PUBLIC 骰点仍照原样落 state.dice（原文未改）');
    });

    test('⑨ 静态：diceDirect 暗骰侧不再 emit EVT.DICE，公开骰侧仍保留', () {
      final src = _codeOf('lib/domain/room_model_actions_combat.dart');
      // 边界用下一个方法签名（注释已被 _codeOf 剥掉，不能拿注释当锚点）。
      final fnStart = src.indexOf('List<SendPlan> diceDirect(');
      final fnEnd = src.indexOf('List<SendPlan> darkRoll(', fnStart);
      expect(fnStart, greaterThanOrEqualTo(0));
      expect(fnEnd, greaterThan(fnStart));
      final fn = src.substring(fnStart, fnEnd);
      final secretStart = fn.indexOf("if (jsTruthy(p['secret'])) {");
      final secretEnd = fn.indexOf('} else {', secretStart);
      final secretBlock = fn.substring(secretStart, secretEnd);
      expect(secretBlock.contains('RoomEvt.dice'), isFalse,
          reason: '暗骰分支不得再 emit EVT.DICE');
      // `emit(` 与事件名在源码里跨行，按 token 检索而非整串。
      expect(secretBlock.contains('RoomEvt.private_'), isTrue);
      expect(secretBlock.contains('vis: RoomVis.seat'), isTrue);
      expect(secretBlock.contains('to: kHostSeat'), isTrue);
      expect(fn.contains('out.addAll(diceRoll(seat, <String, Object?>{'), isTrue,
          reason: '公开骰路径必须保留');
      // 整个 combat 文件只剩 diceRoll 一处 emit EVT.DICE。
      expect('emit(RoomEvt.dice'.allMatches(src).length, 1);
    });

    test('⑩ 静态：kRoomPolicy 仍 62 条（P19 +save.share）、reduceRoomState( 仍 2 调用 + 1 声明', () {
      expect(kRoomPolicy.length, 62);
      for (final op in <String>['dice', 'sancheck', 'opposed', 'board']) {
        expect(kRoomPolicy.containsKey(op), isFalse);
      }
      var calls = 0;
      var decls = 0;
      final callSites = <String>[];
      for (final entity in Directory('lib/domain').listSync().whereType<File>()) {
        if (!entity.path.endsWith('.dart')) continue;
        final name = entity.uri.pathSegments.last;
        for (final line in _codeOf(entity.path).split('\n')) {
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
      expect(calls, 2);
      expect(decls, 1);
      expect(callSites.contains('room_model_host_core.dart'), isTrue);
      expect(callSites.contains('room_model_client.dart'), isTrue);
    });
  });
}
