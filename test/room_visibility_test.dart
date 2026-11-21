// ============================================================
// test/room_visibility_test.dart — P0-M04 七条安全不变式 + T03 判据复核
//
// 与 oracle fixture 的分工：fixture 负责「逐字段等价」，本文件负责
// 「等价但结构必须安全」—— 断言的是「什么绝对不许出现在玩家载荷里」，
// 属于 Dart-only 安全不变式，不参与 oracle 比较，也不登记白名单（§6.4-3）。
//
// 七条（设计 §5 T03 判据 5）：
//   ① VIS.KP 的 plan() 为 []
//   ② VIS.SEAT 只给 to 发 evt、其余在线者发 skip
//   ③ PUBLIC 携带 secret 键被 scrub 剥离并记 1 条 warning
//   ④ 玩家/旁观者载荷无 hp/hpMax/secret/kpOnly/attrs
//   ⑤ syncFor 与增量同视图（共用 cropFor / combatFor，不二次过滤）
//   ⑥ 非 PUBLIC 的 CHECK 只落 redacted:true 脱敏行
//   ⑦ PRIVATE 的 SEAT 守卫生效（定向私密不进 state.privates）
//
// 另复核 T03 其余判据：出站 evt 形状收口、combatFor('host') 全量、
// parseRoom 只放行 4 类、reduceRoomState( 调用点本轮仍为 1、白名单恰好 2 条
// （F3 裁决 A 新增 S:trim）。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/room_model_envelope.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_log.dart';
import 'package:dice_realm/domain/room_model_reduce.dart';
import 'package:dice_realm/domain/room_model_state.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';
import 'support/room_oracle.dart' show expectJsonMatch;
import 'support/room_oracle_whitelist.dart';

const List<String> kForbidden = <String>[
  'hp',
  'hpMax',
  'secret',
  'kpOnly',
  'attrs',
];

/// 递归查找某个键是否出现在任意层级（字节级不允许出现）。
bool _hasKeyDeep(Object? v, String key) {
  if (v is Map) {
    for (final e in v.entries) {
      if ('${e.key}' == key) return true;
      if (_hasKeyDeep(e.value, key)) return true;
    }
    return false;
  }
  if (v is List) {
    for (final x in v) {
      if (_hasKeyDeep(x, key)) return true;
    }
  }
  return false;
}

void _expectNoForbiddenKeys(Object? payload, String why) {
  for (final k in kForbidden) {
    expect(_hasKeyDeep(payload, k), isFalse, reason: '$why：泄漏了 $k');
  }
}

/// 构造一个「怪物槽位带全部 KP 隐藏字段」的战斗载荷。
Map<String, Object?> _secretCombat() => <String, Object?>{
      'combat': <String, Object?>{
        'order': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': '怪',
            'slot': 1,
            'public': <String, Object?>{
              'hp': 10,
              'hpMax': 10,
              'name': '怪',
            },
            'secret': 'KP 才知道的弱点',
            'kpOnly': <String, Object?>{'note': '别给玩家'},
            'attrs': <String, Object?>{'str': 50},
          },
        ],
        'turn': 0,
        'round': 1,
      },
    };

/// 造一个带 3 个在线座位（p1/p2 玩家、p3 旁观者）的 Host。
RoomHost _hostWithPeers() {
  final h = RoomHost(roomHostOpts());
  h.attachPeer(<String, Object?>{'seat': 'p1', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'at': 2});
  h.attachPeer(<String, Object?>{
    'seat': 'p3',
    'role': RoomRole.spectator,
    'at': 3,
  });
  return h;
}

/// 把「权威端 state 里确实含 KP 隐藏字段」的战斗态注入 Host。
///
/// ⚠️ 必须走 [RoomHost.apply] 而不是 `emit(PUBLIC, ...)`：emit 的第 ① 道闸
///    会先 `scrub` 掉 `secret/kpOnly`，那样 `combatFor` / `cropFor` 的裁剪
///    就成了「本来就没东西可裁」，断言会平凡通过。这里要验的正是「即使是
///    权威端内部已有的隐藏字段，出站时也必须被机械删掉」。
LogRecord _injectSecretCombat(RoomHost h) => h.apply(
      RoomEvent(
        t: RoomEvt.combat,
        p: _secretCombat(),
        vis: RoomVis.public,
      ),
    );

void main() {
  // ==========================================================
  // ① VIS.KP 的 plan() 为 []
  // ==========================================================
  test('① VIS.KP 的 plan() 为 []：零出站，但权威端 state 仍归约', () {
    final h = RoomHost(roomHostOpts());
    final rec = h.emit(
      RoomEvt.log,
      <String, Object?>{'text': 'KP 内部备忘', 'at': 1},
      vis: RoomVis.kp,
    );
    expect(h.plan(rec), isEmpty, reason: 'KP 事件根本不出门');
    // 内部对象仍带完整 vis/to（Q1 重放依赖），但没有任何发送计划
    expect(rec.evt.vis, RoomVis.kp);
    expect(rec.evt.seq, rec.seq);
    // KP 自己界面也要看得到（归约进 state），否则重连同步的历史是空的
    final logs = h.state['logs']! as List<Object?>;
    expect(logs.length, 1);
    expect((logs.single! as Map)['text'], 'KP 内部备忘');
    expect(h.warnings, isEmpty, reason: '正常路径 warnings 必须为空');
  });

  // ==========================================================
  // ② VIS.SEAT 只给 to 发 evt、其余在线者发 skip
  // ==========================================================
  test('② VIS.SEAT 只给 to 发 evt，其余在线者收 skip 水位', () {
    final h = _hostWithPeers();
    final rec = h.emit(
      RoomEvt.private_,
      <String, Object?>{'text': '只给 p1', 'title': '线索', 'at': 1},
      vis: RoomVis.seat,
      to: 'p1',
    );
    final plan = h.plan(rec);
    expect(plan.length, 3, reason: '3 个在线座位各 1 条');

    final evts = plan.where((s) => s.msg.k == 'evt').toList();
    final skips = plan.where((s) => s.msg.k == 'skip').toList();
    expect(evts.length, 1);
    expect(evts.single.to, 'p1');
    expect(skips.length, 2);
    expect(skips.map((s) => s.to).toSet(), <String>{'p2', 'p3'});

    // ★ 出站 evt 形状：键集合恒为 {k,seq,t,p}，绝不夹带 vis/to/内部 seq
    final msg = evts.single.msg.toJson();
    expect(msg.keys.toSet(), <String>{'k', 'seq', 't', 'p'});
    expect(msg['k'], 'evt');
    expect(msg['seq'], rec.seq);
    expect(msg['t'], RoomEvt.private_);
    expect(msg['p'], <String, Object?>{
      'text': '只给 p1',
      'title': '线索',
      'at': 1,
    });
    for (final s in skips) {
      expect(s.msg.toJson(), <String, Object?>{
        'k': 'skip',
        'seq': rec.seq,
      });
    }
    expect(h.warnings, isEmpty, reason: 'SEAT 有收件人，不该记警告');
  });

  test('②b SEAT 缺收件人：不发 evt、记 1 条 warning（不静默丢）', () {
    final h = RoomHost(roomHostOpts());
    final rec = h.apply(
      const RoomEvent(
        t: RoomEvt.private_,
        p: <String, Object?>{'text': 'x'},
        vis: RoomVis.seat,
      ),
    );
    expect(h.plan(rec), isEmpty);
    expect(h.warnings.length, 1);
    expect(h.warnings.single.toJson(), <String, Object?>{
      't': RoomEvt.private_,
      'reason': 'SEAT 事件缺少收件人 seat',
    });
  });

  // ==========================================================
  // ③ PUBLIC 带 secret 键被 scrub 剥离并记 1 条 warning
  // ==========================================================
  test('③ PUBLIC + secret 被 scrub 剥离，记且只记 1 条 warning', () {
    final h = RoomHost(roomHostOpts());
    final rec = h.emit(
      RoomEvt.chat,
      <String, Object?>{
        'text': 'hi',
        'secret': 'leak',
        'kpOnly': <String, Object?>{'nested': true},
        'list': <Object?>[
          <String, Object?>{'truth': 1},
        ],
      },
      vis: RoomVis.public,
    );
    expect(h.warnings.length, 1);
    expect(h.warnings.single.toJson(), <String, Object?>{
      't': RoomEvt.chat,
      'reason': '非 SEAT 事件携带私有字段，已剥离',
    });
    // 内部事件对象里也已剥离（不是「先广播再隐藏」）
    expect(rec.evt.p.containsKey('secret'), isFalse);
    expect(rec.evt.p.containsKey('kpOnly'), isFalse);
    _expectNoForbiddenKeys(rec.evt.p, 'scrub 后的内部载荷');
    expect(rec.evt.p['text'], 'hi');

    final plan = h.plan(rec);
    expect(plan.length, 1, reason: 'PUBLIC 广播 1 条');
    expect(plan.single.to, '*');
    expect(plan.single.msg.toJson(), <String, Object?>{
      'k': 'evt',
      'seq': rec.seq,
      't': RoomEvt.chat,
      'p': <String, Object?>{
        'text': 'hi',
        'list': <Object?>[
          <String, Object?>{},
        ],
      },
    });
    _expectNoForbiddenKeys(plan.single.msg.toJson(), 'PUBLIC 出站载荷');
  });

  test('③b VIS.SEAT 不 scrub（定向私密允许带 secret），但不广播', () {
    final h = _hostWithPeers();
    final rec = h.emit(
      RoomEvt.check,
      <String, Object?>{'summary': '暗骰 07', 'secret': '底牌', 'seat': 'p1'},
      vis: RoomVis.seat,
      to: 'p1',
    );
    expect(h.warnings, isEmpty);
    expect(rec.evt.p['secret'], '底牌');
    final plan = h.plan(rec);
    expect(plan.where((s) => s.msg.k == 'evt').length, 1);
    expect(plan.where((s) => s.msg.k == 'skip').length, 2);
  });

  // ==========================================================
  // ④ 玩家/旁观者载荷无 hp/hpMax/secret/kpOnly/attrs
  // ==========================================================
  test('④ 玩家/旁观者载荷（增量 + 全量）无 hp/hpMax/secret/kpOnly/attrs', () {
    final h = _hostWithPeers();
    final rec = _injectSecretCombat(h);
    // 先确认「源头真的有隐藏字段」，否则下面的裁剪断言没有意义
    final srcSlot = (((h.state['combat']! as Map)['order']! as List).single! as Map);
    expect(srcSlot['secret'], 'KP 才知道的弱点');
    final plan = h.plan(rec);
    expect(plan.length, 3, reason: '战斗事件逐人单发裁剪');
    for (final s in plan) {
      _expectNoForbiddenKeys(s.msg.toJson(), '${s.to} 的增量载荷');
    }
    for (final seat in <String>['p1', 'p2', 'p3']) {
      final sync = h.syncFor(seat).toJson();
      _expectNoForbiddenKeys(sync, '$seat 的全量载荷');
      _expectNoForbiddenKeys(h.combatFor(seat), '$seat 的 combatFor');
    }
    // KP 自己拿全量（这是权威端视图，不是出站载荷）
    final hostView = h.combatFor(kHostSeat)!;
    final slot = ((hostView['order']! as List).single! as Map)['public']! as Map;
    expect(slot['hp'], 10);
    expect(slot['hpMax'], 10);
  });

  // ==========================================================
  // ⑤ syncFor 与增量同视图
  // ==========================================================
  test('⑤ syncFor 与增量同视图（共用 cropFor / combatFor，不二次过滤）', () {
    final h = _hostWithPeers();
    final rec = _injectSecretCombat(h);
    final plan = h.plan(rec);
    for (final s in plan) {
      final incremental = (s.msg.toJson()['p']! as Map)['combat'];
      final full = (h.syncFor(s.to).toJson()['state']! as Map)['combat'];
      expectJsonMatch(full, incremental, r'$',
          'syncFor(${s.to}) vs 增量 combat');
    }
    // 成员表也共用同一套 _cropMembers。
    // ⚠️ 必须让增量事件的 members 与 `syncFor` 内部的 `members()` 是同一份输入：
    //    把 sheet 挂到真实花名册上，再用 `h.members()` 作为事件载荷，
    //    否则比较的是「1 个虚构成员」与「3 个真实成员」，长度就对不上。
    h.roster.get('p1')!['sheet'] = <String, Object?>{
      'name': '甲',
      'status': <String, Object?>{'currentHP': 5, 'maxSAN': 90},
      'mental': <Object?>['恐高'],
    };
    final memberRec = h.apply(
      RoomEvent(
        t: RoomEvt.members,
        p: <String, Object?>{'members': h.members()},
        vis: RoomVis.public,
      ),
    );
    final memberPlan = h.plan(memberRec);
    expect(memberPlan.length, 3, reason: '挂了 sheet → 逐人单发裁剪');
    for (final s in memberPlan) {
      final incremental = (s.msg.toJson()['p']! as Map)['members'];
      final full = (h.syncFor(s.to).toJson()['state']! as Map)['members'];
      expectJsonMatch(full, incremental, r'$',
          'syncFor(${s.to}) vs 增量 members');
    }
  });

  // ==========================================================
  // ⑥ 非 PUBLIC 的 CHECK 只落 redacted:true 脱敏行
  // ==========================================================
  test('⑥ 非 PUBLIC 的 CHECK 只落 redacted:true 脱敏行，明文不上 state/未授权 sync', () {
    const plain = '秘密检定：骰出 07，极难成功';
    final h = _hostWithPeers();
    final rec = h.emit(
      RoomEvt.check,
      <String, Object?>{
        'summary': plain,
        'seat': 'p1',
        'at': 2,
        'kind': 'check',
      },
      vis: RoomVis.seat,
      to: 'p1',
    );
    final logs = h.state['logs']! as List<Object?>;
    expect(logs.length, 1);
    expect(logs.single, <String, Object?>{
      'seq': rec.seq,
      'seat': '',
      'text': 'KP 秘密进行了一次检定',
      'at': 2,
      'kind': 'check',
      'opp': null,
      'redacted': true,
    });
    expect(jsonEncode(h.state).contains(plain), isFalse, reason: '权威态不得有明文');
    for (final seat in <String>['p2', 'p3']) {
      final sync = h.syncFor(seat).toJson();
      expect(jsonEncode(sync).contains(plain), isFalse,
          reason: '$seat 不该收到明文');
      final syncLogs = (sync['state']! as Map)['logs']! as List<Object?>;
      expect((syncLogs.single! as Map)['redacted'], isTrue);
    }
    // 对照：PUBLIC CHECK 明文进 state（口径不变）
    final h2 = RoomHost(roomHostOpts());
    h2.emit(
      RoomEvt.check,
      <String, Object?>{'summary': '公开检定成功', 'seat': 'p1', 'at': 1},
      vis: RoomVis.public,
    );
    final pubLogs = h2.state['logs']! as List<Object?>;
    expect((pubLogs.single! as Map)['text'], '公开检定成功');
    expect((pubLogs.single! as Map).containsKey('redacted'), isFalse);
    // 客户端回放（vis:null ≡ 旧版 undefined）按 PUBLIC 处理
    final h3 = RoomHost(roomHostOpts());
    h3.apply(
      const RoomEvent(
        t: RoomEvt.check,
        p: <String, Object?>{'summary': 'S', 'seat': 'x', 'at': 1},
        seq: 1,
      ),
      persist: false,
    );
    expect(
      ((h3.state['logs']! as List).single! as Map)['text'],
      'S',
      reason: 'vis 缺失必须按 PUBLIC 处理（旧版 :685）',
    );
  });

  // ==========================================================
  // ⑦ PRIVATE 的 SEAT 守卫生效
  // ==========================================================
  test('⑦ PRIVATE 的 SEAT 守卫：定向私密不进 state.privates，只进 privateBySeat', () {
    final h = _hostWithPeers();
    h.emit(
      RoomEvt.private_,
      <String, Object?>{'text': '线索A', 'title': '只给p1', 'at': 4},
      vis: RoomVis.seat,
      to: 'p1',
    );
    expect(h.state['privates'], isEmpty, reason: '守卫：不得混进 KP 公共私有栏');
    expect(h.privateBySeat['p1'], isNotEmpty, reason: '但收件人重连仍要拿得到');
    final p1 = (h.syncFor('p1').toJson()['state']! as Map)['privates']! as List;
    expect(p1.length, 1);
    expect((p1.single! as Map)['text'], '线索A');
    for (final seat in <String>['p2', 'p3']) {
      final pv = (h.syncFor(seat).toJson()['state']! as Map)['privates']! as List;
      expect(pv, isEmpty, reason: '$seat 不该收到 p1 的定向私密');
    }
    // 对照：to == HOST_SEAT 的私密是给 KP 自己的，按旧版进 state.privates
    final h2 = RoomHost(roomHostOpts());
    h2.emit(
      RoomEvt.private_,
      <String, Object?>{'text': '暗骰：07', 'at': 1},
      vis: RoomVis.seat,
      to: kHostSeat,
    );
    expect(h2.state['privates']! as List, isNotEmpty);
  });

  // ==========================================================
  // 出站形状收口（本轮根因的回归钉子）
  // ==========================================================
  test('出站 evt 键集合恒为 {k,seq,t,p}：内部 vis/to 绝不外泄', () {
    final h = _hostWithPeers();
    final samples = <LogRecord>[
      h.emit(RoomEvt.chat, <String, Object?>{'text': 'a'}, vis: RoomVis.public),
      h.emit(RoomEvt.private_, <String, Object?>{'text': 'b'},
          vis: RoomVis.seat, to: 'p1'),
      _injectSecretCombat(h),
    ];
    for (final rec in samples) {
      // 内部对象必须带 vis（Q1 重放依赖），出站对象必须不带
      expect(rec.evt.vis, isNotNull);
      expect(rec.evt.seq, rec.seq);
      for (final s in h.plan(rec)) {
        final j = s.msg.toJson();
        if (j['k'] != 'evt') continue;
        expect(j.keys.toSet(), <String>{'k', 'seq', 't', 'p'});
        expect(j.containsKey('vis'), isFalse);
        expect(j.containsKey('to'), isFalse);
        expect((j['p']! as Map).containsKey('vis'), isFalse);
      }
    }
    // evtMsg() 直接收口：即使 rec.evt 带 vis/to/seq，也只输出 4 键
    final rec = samples.first;
    expect(evtMsg(rec).toJson(), <String, Object?>{
      'k': 'evt',
      'seq': rec.seq,
      't': RoomEvt.chat,
      'p': <String, Object?>{'text': 'a'},
    });
  });

  test('log 记录的 wire 形状按 push 入参收口（logScript 红用例的回归钉子）', () {
    final log = RoomLog();
    final bare = log.push(
      const RoomEvent(t: RoomEvt.log, p: <String, Object?>{}),
      wire: <String, Object?>{'t': RoomEvt.log, 'p': <String, Object?>{}},
    );
    final full = log.push(
      const RoomEvent(
        t: RoomEvt.check,
        p: <String, Object?>{'summary': 's'},
        vis: RoomVis.seat,
        to: 'p1',
      ),
      wire: <String, Object?>{
        't': RoomEvt.check,
        'p': <String, Object?>{'summary': 's'},
        'vis': RoomVis.seat,
        'to': 'p1',
      },
    );
    expect(bare.toWireJson(), <String, Object?>{
      'seq': 1,
      'evt': <String, Object?>{'t': RoomEvt.log, 'p': <String, Object?>{}},
    });
    expect(full.toWireJson(), <String, Object?>{
      'seq': 2,
      'evt': <String, Object?>{
        't': RoomEvt.check,
        'p': <String, Object?>{'summary': 's'},
        'vis': RoomVis.seat,
        'to': 'p1',
      },
    });
    // 内部事件对象仍完整（Q1 重放依赖），wire 不参与归约
    expect(full.evt.seq, 2);
    expect(full.evt.vis, RoomVis.seat);
    expect(full.evt.to, 'p1');
    expect(log.since(0).map((r) => r.toWireJson()).length, 2);
  });

  // ==========================================================
  // T03 其余判据复核
  // ==========================================================
  test('P0-M02：host 不在花名册（不得据此判旁观者）；combatFor(host) 全量', () {
    final h = _hostWithPeers();
    expect(h.roster.get(kHostSeat), isNull);
    expect(h.members().length, 3);
    _injectSecretCombat(h);
    final hostView = h.combatFor(kHostSeat)!;
    final slot = (hostView['order']! as List).single! as Map;
    expect(slot['secret'], 'KP 才知道的弱点');
    expect((slot['public']! as Map)['hp'], 10);
    final playerView = h.combatFor('p1')!;
    _expectNoForbiddenKeys(playerView, 'combatFor(p1)');
  });

  test('P0-M11：parseRoom 只放行 sync/evt/skip/intent 四类', () {
    expect(parseRoom('{"k":"sync","seq":1,"state":{}}')!.k, 'sync');
    expect(parseRoom('{"k":"evt","seq":2,"t":"chat","p":{}}')!.k, 'evt');
    expect(parseRoom('{"k":"skip","seq":3}')!.k, 'skip');
    expect(parseRoom('{"k":"intent","op":"chat","p":{}}')!.k, 'intent');
    for (final bad in <Object?>[
      '{"k":"host.gone"}',
      '{"k":"unknown"}',
      'not json',
      '[]',
      '"str"',
      '',
      null,
      42,
    ]) {
      expect(parseRoom(bad), isNull, reason: '不该放行 $bad');
    }
  });

  test('P0-M01 / Q1：apply 是唯一写口，reduceRoomState( 调用点 == 2', () {
    final dir = Directory('lib/domain');
    var calls = 0;
    final where = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.contains('room_') || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//') || line.contains('///')) continue;
        if (!line.contains('reduceRoomState(')) continue;
        // 排除函数声明本身
        if (line.trimLeft().startsWith('Map<String, Object?> reduceRoomState(')) {
          continue;
        }
        calls++;
        where.add('${f.path}:${i + 1}');
      }
    }
    expect(
      calls,
      2,
      reason: '必须正好 2 处（RoomHost.apply / RoomClient.receive），实际 $where',
    );
    expect(where.any((w) => w.contains('room_model_host_core.dart')), isTrue);
    expect(where.any((w) => w.contains('room_model_client.dart')), isTrue);
  });

  test('28 个 reduce 分支 + TEMP_COMMIT / SAVE_SYNC 无分支（Q6）', () {
    final before = emptyRoomState();
    final snapshot = roomClone(before)! as Map;
    reduceRoomState(
      before,
      const RoomEvent(t: RoomEvt.tempCommit, p: <String, Object?>{}, seq: 9),
    );
    snapshot['seq'] = 9;
    expectJsonMatch(before, snapshot);
    expect(RoomEvt.values.length, 28);
    expect(needs(RoomRole.kp, 'rollback.turn').allowed, isFalse);
  });

  test('白名单恰好 2 条（S:q1 / S:trim），allowedPaths 不含 logScript 相关 tag', () {
    // F3 裁决 A 批准新增第 2 条；不许出现第 3 条。
    expect(kRoomOracleWhitelist.length, 2);
    final q1 = kRoomOracleWhitelist.firstWhere((d) => d.caseId == 'S:q1');
    final trim = kRoomOracleWhitelist.firstWhere((d) => d.caseId == 'S:trim');
    expect(q1.caseId, 'S:q1');
    for (final p in q1.allowedPaths) {
      expect(p.contains('logScript'), isFalse);
      expect(p.contains('M:logScript'), isFalse);
    }
    expect(q1.forbiddenKeys, containsAll(kForbidden));
    // ★ S:trim 只放行一条精确路径，且不允许任何通配。
    expect(trim.allowedPaths, <String>[kTrimAllowedPath]);
    for (final p in trim.allowedPaths) {
      expect(p.contains('*'), isFalse, reason: 'S:trim 不得使用通配路径 $p');
    }
    expect(trim.forbiddenKeys, containsAll(kForbidden));
  });
}
