// ============================================================
// test/room_session_test.dart — P5/T01 S1.1 会话端口 + 控制器 + 本地态
//
// 铁律（每个用例都遵守）：
//   T1 全部内存后端（roomHostOpts 的固定时钟 + Lcg + 内存存档，零 I/O）；
//   T6 断言「点了有没有反应」一律看权威侧 / sent，不看 UI 文案；
//   T8 跨视角用 session.stateFor(seat)（客户端真收到的裁剪态），
//      绝不拿 host.state 假装玩家视图。
//
// 覆盖：广播 / 单发 / skip 消费 / gap 自愈 / pullSync / 可见性裁剪 /
//      K1 守卫 / 双层 ACT / sent 记录 / 节流 / gate / openSave 顺序 /
//      RoomScope / RoomUiLocal / RoomKeys 12·13。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/repo/room_notes_store.dart';
import 'package:dice_realm/ui/room/room_controller.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/room_scope.dart';
import 'package:dice_realm/ui/room/room_session_local.dart';
import 'package:dice_realm/ui/room/room_ui_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

/// 造一个「KP + 2 玩家 + 1 旁观」的环回房间，并把四份客户端水位对齐。
Future<LocalLoopbackSession> _boot({
  int seed = 1,
  bool attachAll = true,
}) async {
  final h = RoomHost(roomHostOpts(
    seed: seed,
    meta: <String, Object?>{
      'code': 'p5t01',
      'name': 'T01 测试团',
      'kpName': '老 K',
    },
  ));
  final s = LocalLoopbackSession(host: h, seat: kHostSeat, role: RoomRole.kp);
  const specs = <List<String>>[
    <String>['p1', RoomRole.player, '甲'],
    <String>['p2', RoomRole.player, '乙'],
    <String>['ghost', RoomRole.spectator, '观'],
  ];
  if (attachAll) {
    for (final spec in specs) {
      s.attach(
        spec[0],
        RoomClientForTest(seat: spec[0], role: spec[1]).client,
      );
    }
    final plans = <SendPlan>[];
    for (final spec in specs) {
      plans.addAll(h.attachPeer(<String, Object?>{
        'seat': spec[0],
        'role': spec[1],
        'nickname': spec[2],
        'at': 1,
      }).out);
    }
    s.pumpPlans(plans);
    for (final spec in specs) {
      await s.pullSync(spec[0]);
    }
  }
  return s;
}

/// 薄封装：把 `RoomClient` 的类型藏在测试里，便于复用构造参数。
class RoomClientForTest {
  RoomClientForTest({required String seat, required String role})
      : client = RoomClient(seat: seat, role: role);

  final RoomClient client;
}

/// 深搜一个 JSON 对象里的所有字符串值（含键名），用于「搜不到明文」断言。
void _collectStrings(Object? v, List<String> out) {
  if (v is Map) {
    for (final e in v.entries) {
      out.add('${e.key}');
      _collectStrings(e.value, out);
    }
  } else if (v is List) {
    for (final x in v) {
      _collectStrings(x, out);
    }
  } else if (v is String) {
    out.add(v);
  }
}

List<String> _allStrings(Object? v) {
  final out = <String>[];
  _collectStrings(v, out);
  return out;
}

void main() {
  group('S1.1 · LocalLoopbackSession 泵与信封消费', () {
    test('host.intent 的 SendPlan 被喂进 client.receive（广播 + sent 记录）',
        () async {
      final s = await _boot();
      expect(s.clients.length, 3);
      expect(s.seats, <String>[kHostSeat, 'p1', 'p2', 'ghost']);

      await s.sendIntent(RoomIntent.chat, <String, Object?>{'text': '大家好'});

      // T6：断言权威侧状态，而不是 UI 文案。
      expect(asList(s.host.state['chats']).length, 1);
      for (final seat in <String>['p1', 'p2', 'ghost']) {
        expect(asList(s.stateFor(seat)['chats']).length, 1,
            reason: '$seat 应收到广播的聊天事件');
        expect(s.clients[seat]!.lastSeq, s.host.log.seq,
            reason: '$seat 水位应与权威端一致');
      }
      expect(s.sent.whereKind('intent'), hasLength(1));
      expect(s.sent.whereOp(RoomIntent.chat).single['p'],
          <String, Object?>{'text': '大家好'});
      expect(s.sentLog.isNotEmpty, isTrue, reason: '出站信封也要记账');
    });

    test('SEAT 单发只给收件人 evt，其余在线者消费 skip 水位', () async {
      final s = await _boot();
      final rec = s.host.emit(
        RoomEvt.private_,
        <String, Object?>{
          'title': '提示',
          'text': '只给甲看',
          'at': 3,
          'kind': 'sys',
        },
        vis: RoomVis.seat,
        to: 'p1',
      );
      final before = <String, int>{
        for (final e in s.clients.entries) e.key: e.value.lastSeq,
      };
      s.pumpPlans(s.host.plan(rec));

      expect(asList(s.stateFor('p1')['privates']).length, 1,
          reason: 'p1 应收到定向私密');
      expect(asList(s.stateFor('p2')['privates']).isEmpty, isTrue);
      expect(asList(s.stateFor('ghost')['privates']).isEmpty, isTrue);
      for (final e in s.clients.entries) {
        expect(e.value.lastSeq, before[e.key]! + 1,
            reason: '${e.key} 无论收 evt 还是 skip，水位都要推进');
      }
      expect(s.lastNotice, '只给甲看', reason: '定向 sysTo 应被会话抓取');
    });

    test('断线 pullSync 用 sync 信封整体替换并把水位拉齐', () async {
      final s = await _boot();
      await s.sendIntent(RoomIntent.chat, <String, Object?>{'text': '第一句'});
      s.clients['p2']!.lastSeq = 0; // 模拟掉线期间的陈旧水位
      s.clients['p2']!.state['chats'] = <Object?>[];

      await s.pullSync('p2');

      expect(asList(s.stateFor('p2')['chats']).length, 1);
      expect(s.clients['p2']!.lastSeq, s.host.log.seq);
    });

    test('序号跳号时自报 INTENT.SYNC 补拉，不丢状态', () async {
      final s = await _boot();
      await s.sendIntent(RoomIntent.chat, <String, Object?>{'text': 'A'});
      await s.sendIntent(RoomIntent.chat, <String, Object?>{'text': 'B'});
      s.clients['p1']!.lastSeq = 0; // 制造 gap

      final rec = s.host.emit(
        RoomEvt.log,
        <String, Object?>{'seat': '', 'text': '系统', 'at': 9, 'kind': 'sys'},
      );
      s.pumpPlans(s.host.plan(rec));

      expect(s.clients['p1']!.lastSeq, s.host.log.seq,
          reason: 'gap 自愈后应被全量同步拉齐');
      expect(asList(s.stateFor('p1')['chats']).length, 2);
    });

    test('★ 玩家视图里搜不到他人 sheet.attrs 与秘密检定明文', () async {
      final s = await _boot();

      // ★ 必须**用 p1 视角**发 char：权威端 shareSheet 只放行
      //   `role == player`（KP 视角发会被 sysTo 拒绝、不产生裁剪事件）。
      final p1View = s.viewFor('p1', RoomRole.player);
      await p1View.sendIntent(RoomIntent.char, <String, Object?>{
        'id': 'c1',
        'name': '甲的调查员',
        'sheet': <String, Object?>{
          'name': '甲的调查员',
          'attrs': <String, Object?>{'dex': 77, 'str': 55},
          'status': <String, Object?>{
            'currentHP': 12,
            'maxHP': 12,
            'currentSAN': 60,
            'maxSAN': 99,
          },
          'skills': <Object?>[
            <String, Object?>{'name': '侦查', 'value': 70},
          ],
        },
      });

      // 秘密检定：VIS.SEAT 定向 p1，公共侧只落脱敏行。
      final rec = s.host.emit(
        RoomEvt.check,
        <String, Object?>{
          'summary': '秘密检定：骰出 07，极难成功',
          'seat': 'p1',
          'at': 7,
          'kind': 'check',
        },
        vis: RoomVis.seat,
        to: 'p1',
      );
      s.pumpPlans(s.host.plan(rec));

      // 权威端公共日志只有脱敏行（Q1 保证）。
      final hostLogs = jsonEncode(s.host.state['logs']);
      expect(hostLogs.contains('秘密检定：骰出 07'), isFalse);
      expect(hostLogs.contains('KP 秘密进行了一次检定'), isTrue);

      // T8：p2 / ghost 是客户端真收到的裁剪态，不是 host.state。
      for (final seat in <String>['p2', 'ghost']) {
        final strings = _allStrings(s.stateFor(seat));
        expect(strings.where((x) => x.contains('秘密检定：骰出 07')).isEmpty,
            isTrue,
            reason: '$seat 视图不得出现明文秘密检定');
        expect(strings.contains('attrs'), isFalse,
            reason: '$seat 视图不得出现他人 sheet.attrs 键');
        expect(strings.contains('maxSAN'), isTrue,
            reason: '他人视图保留 maxSAN 键但值被置 null（C2）');
        final others = asList(s.stateFor(seat)['members'])
            .map(asMap)
            .where((m) => m['seat'] == 'p1')
            .toList();
        expect(others, hasLength(1));
        expect(asMap(others.single['sheet']).containsKey('attrs'), isFalse);
      }

      // 发起人本人能看到自己的结果（p1 收的是定向 evt）。
      final p1Strings = _allStrings(s.stateFor('p1'));
      expect(p1Strings.where((x) => x.contains('秘密检定：骰出 07')).isNotEmpty,
          isTrue, reason: '只有发起人收全文（PRD C2）');

      // 重新全量同步后，公共栏仍只有脱敏行。
      await s.pullSync('p2');
      expect(jsonEncode(s.stateFor('p2')['logs'])
          .contains('秘密检定：骰出 07'), isFalse);
    });

    test('★ K1 守卫：beforeSeq < 1 夹到 1，rollback(0) 不产生水位不等',
        () async {
      final s = await _boot();
      await s.sendIntent(RoomIntent.chat, <String, Object?>{'text': 'A'});
      await s.sendIntent(RoomIntent.chat, <String, Object?>{'text': 'B'});

      expect(s.clampBeforeSeq(0), 1);
      expect(s.clampBeforeSeq(-7), 1);
      expect(s.clampBeforeSeq(3), 3);

      final result = s.rollback(0);
      expect(s.lastRollbackBeforeSeq, 1);
      expect(result.from, 0, reason: '夹到 1 → target=0，从虚拟基线重放');
      expect(s.host.state['seq'], s.host.log.seq,
          reason: '★ K1：state.seq 与 log.seq 必须相等');
      for (final e in s.clients.entries) {
        expect(e.value.lastSeq, s.host.log.seq,
            reason: '${e.key} 客户端水位也要跟着对齐');
      }
    });

    test('hostAction 是双层信封（外层 act / 内层 op）并记入 sent', () async {
      final s = await _boot();
      await s.hostAction('chat', <String, Object?>{'text': 'KP 说话'});

      final actions = s.sent.whereKind('action');
      expect(actions, hasLength(1));
      expect(actions.single['op'], 'chat');
      expect(asMap(actions.single['p'])['op'], 'chat');
      expect(asMap(actions.single['p'])['text'], 'KP 说话');
      expect(asList(s.host.state['chats']).length, 1,
          reason: '双层信封若写错，act 会被 needs/intent 拒掉、公共聊天为空');

      // 预置稿命名的 sendAction 必须等价。
      await s.sendAction('chat', <String, Object?>{'text': '第二句'});
      expect(s.sent.whereKind('action'), hasLength(2));
      expect(asList(s.host.state['chats']).length, 2);
    });

    test('多视角共享 hub：任一视角发 intent，四份视图都重建', () async {
      final main = await _boot();
      final kp = main.viewFor(kHostSeat, RoomRole.kp);
      final p1 = main.viewFor('p1', RoomRole.player);
      final ghost = main.viewFor('ghost', RoomRole.spectator);
      var kpHits = 0;
      var p1Hits = 0;
      var ghostHits = 0;
      kp.addListener(() => kpHits++);
      p1.addListener(() => p1Hits++);
      ghost.addListener(() => ghostHits++);

      await p1.sendIntent(RoomIntent.chat, <String, Object?>{'text': '跨视角'});

      expect(kpHits > 0, isTrue);
      expect(p1Hits > 0, isTrue);
      expect(ghostHits > 0, isTrue);
      expect(asList(kp.state['chats']).length, 1);
      expect(asList(p1.state['chats']).length, 1);
      expect(asList(ghost.state['chats']).length, 1);
      expect(p1.hostRead, isNull, reason: '玩家视角拿不到 KP 只读面');
      expect(kp.hostRead, isNotNull);
      expect(kp.hostRead!.state, same(kp.host.state));
      expect(p1.role, RoomRole.player);
      expect(p1.seat, 'p1');
      expect(p1.code, 'p5t01');
    });
  });

  group('S1.1 · RoomController / RoomGate / RoomUiLocal', () {
    test('gate 与 POLICY 同源，intent 通道恒 false', () {
      expect(RoomGate(RoomRole.kp).can('room.start'), isTrue);
      expect(RoomGate(RoomRole.player).can('room.start'), isFalse);
      expect(RoomGate(RoomRole.spectator).can('room.start'), isFalse);
      expect(RoomGate(RoomRole.kp).confirmOf('room.close'), RoomConfirm.twice);
      expect(RoomGate(RoomRole.kp).confirmOf('room.start'), isNull);
      expect(RoomGate(RoomRole.kp).can(RoomIntent.dice), isFalse,
          reason: '13 个 INTENT 不经 POLICY，needs() 未登记 → false');
      expect(RoomGate(RoomRole.kp).can('rollback.turn'), isFalse);
    });

    test('400ms 节流按 key 分桶（注入时钟，确定性）', () {
      var now = 1000;
      final s = _bareSession();
      final local = RoomUiLocal();
      final ctl = RoomController(
        session: s,
        local: local,
        notes: RoomNotesStore(MemoryNotesStorage()),
        nowMs: () => now,
      );
      expect(ctl.throttle('round.next'), isTrue);
      expect(ctl.throttle('round.next'), isFalse, reason: '同一 key 窗口内被吞');
      expect(ctl.throttle('combat.next'), isTrue, reason: '不同 key 独立分桶');
      now = 1399;
      expect(ctl.throttle('round.next'), isFalse);
      now = 1400;
      expect(ctl.throttle('round.next'), isTrue);
      ctl.resetThrottle();
      expect(ctl.throttle('round.next'), isTrue);
    });

    test('controller 是唯一出口：sendIntent/hostAction 转发且失败转 notice',
        () async {
      final s = await _boot();
      final local = RoomUiLocal()
        ..showNotice('x', ttl: Duration.zero);
      local.clearNotice();
      final ctl = RoomController(
        session: s,
        local: local,
        notes: RoomNotesStore(MemoryNotesStorage()),
      );
      await ctl.sendIntent(RoomIntent.chat, <String, Object?>{'text': 'C'});
      await ctl.hostAction('chat', <String, Object?>{'text': 'D'});
      expect(s.sent.length, 2);
      expect(asList(s.host.state['chats']).length, 2);
      ctl.notice('测试提示');
      expect(local.notice, '测试提示');
      expect(s.onNotice, isNull, reason: '未挂 sink 时不应抛');
      local.clearNotice();
    });

    test('★ openSave 顺序：先 K4 迁移、再 adopt、再 pullSync、再一次性提示',
        () async {
      final s = await _boot();
      final local = RoomUiLocal();
      final ctl = RoomController(
        session: s,
        local: local,
        notes: RoomNotesStore(MemoryNotesStorage()),
      );
      final legacy = <String, Object?>{
        'v': 2,
        'code': 'p5t01',
        'seq': 5,
        'meta': <String, Object?>{'code': 'p5t01', 'name': '旧团'},
        'members': <Object?>[],
        'logs': <Object?>[
          <String, Object?>{
            'seq': 3,
            'seat': 'p1',
            'text': '秘密检定：骰出 07，极难成功',
            'at': 111,
            'kind': 'check',
            'opp': null,
          },
          <String, Object?>{
            'seq': 4,
            'seat': '',
            'text': 'KP 秘密进行了一次检定',
            'at': 222,
            'kind': 'check',
            'opp': null,
            'redacted': true,
          },
        ],
      };
      final result = await ctl.openSave(legacy);
      expect(result.migrated, 1);
      expect(result.changed, isTrue);
      final logs = jsonEncode(s.host.state['logs']);
      expect(logs.contains('秘密检定：骰出 07'), isFalse);
      expect(logs.contains('KP 秘密进行了一次检定'), isTrue);
      expect(local.notice, '旧存档含历史明文记录，已自动脱敏 1 条。');
      // 入参未被改动（深拷贝语义）。
      expect(jsonEncode(legacy).contains('秘密检定：骰出 07'), isTrue);
      local.clearNotice();
    });

    test('saveNow 走 exportSave → saveStore.put，20 键不新增', () async {
      final s = await _boot();
      final store = InMemoryRoomSaveStore();
      final local = RoomUiLocal();
      final ctl = RoomController(
        session: s,
        local: local,
        notes: RoomNotesStore(MemoryNotesStorage()),
        saveStore: store,
      );
      expect(await ctl.saveNow(), isTrue);
      final saved = store.get('p5t01');
      expect(saved, isNotNull);
      expect(saved!.length, 20, reason: 'Host.save() 恰好 20 个顶层键');
      expect(await ctl.saveNow(name: 'slotA'), isTrue);
      expect(store.get('slotA'), isNotNull);
      final pl = s.viewFor('p1', RoomRole.player);
      final plCtl = RoomController(
        session: pl,
        local: local,
        notes: RoomNotesStore(MemoryNotesStorage()),
        saveStore: store,
      );
      expect(await plCtl.saveNow(), isFalse, reason: '玩家不能导出房间存档');
      local.clearNotice();
    });
  });

  group('S1.1 · RoomUiLocal / RoomKeys / RoomScope', () {
    test('UI 本地态：奖惩骰互斥 0–5、缩放夹取、折叠保持', () {
      final l = RoomUiLocal();
      l.setBonus(3);
      expect(l.bonus, 3);
      expect(l.penalty, 0);
      l.setPenalty(2);
      expect(l.penalty, 2);
      expect(l.bonus, 0, reason: 'S3：切边清空另一侧');
      l.setBonus(99);
      expect(l.bonus, 5);
      l.setPenalty(-3);
      expect(l.penalty, 0);
      l.setZoom(2);
      expect(l.zoom, 1.0);
      l.setZoom(0.3);
      expect(l.zoom, 0.6);
      l.setZoom(0.723456789);
      expect(l.zoom, 0.723457);
      expect(l.isFolded('kpCombat'), isFalse);
      l.toggleFold('kpCombat');
      expect(l.isFolded('kpCombat'), isTrue);
      l.toggleFold('kpCombat');
      expect(l.isFolded('kpCombat'), isFalse);
      l.setTool(RoomToolMode.erase, icon: '🧽', colorIndex: 3);
      expect(l.toolMode, RoomToolMode.erase);
      expect(l.toolIcon, '🧽');
      expect(l.toolColorIndex, 3);
    });

    test('容器数：KP 12 / 玩家（含旁观）13，且不做跨视角块号对齐', () {
      expect(RoomKeys.kpSlots.length, 12);
      expect(RoomKeys.plSlots.length, 13);
      expect(RoomKeys.slotKey(RoomSlot.gpChat), RoomKeys.gpChat);
      expect(RoomKeys.keyOfSlot(RoomSlot.gpPriv), const ValueKey<String>('gpPriv'));
      expect(RoomKeys.action('room.start'),
          const ValueKey<String>('act/room.start'));
      expect(RoomKeys.kpSlots.toSet().length, 12);
      expect(RoomKeys.plSlots.toSet().length, 13);
    });

    testWidgets('RoomScope.of / read 能取到 session·local·controller 三件套',
        (WidgetTester tester) async {
      final s = await _boot();
      final local = RoomUiLocal();
      final ctl = RoomController(
        session: s,
        local: local,
        notes: RoomNotesStore(MemoryNotesStorage()),
      );
      late RoomScope ofScope;
      late RoomScope readScope;
      await tester.pumpWidget(MaterialApp(
        home: RoomScope(
          session: s,
          local: local,
          controller: ctl,
          child: Builder(builder: (BuildContext context) {
            ofScope = RoomScope.of(context);
            readScope = RoomScope.read(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(ofScope.session, same(s));
      expect(ofScope.local, same(local));
      expect(ofScope.controller, same(ctl));
      expect(readScope.session, same(s));
      expect(RoomScope.controllerOf(
              tester.element(find.byType(SizedBox).first)).session,
          same(s));
      // session 通知会触发依赖它的子树重建（InheritedNotifier 语义）。
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: RoomScope(
          session: s,
          local: local,
          controller: ctl,
          child: Builder(builder: (BuildContext context) {
            RoomScope.of(context);
            builds++;
            return const SizedBox.shrink();
          }),
        ),
      ));
      final before = builds;
      s.pumpPlans(<SendPlan>[]);
      await tester.pump();
      expect(builds, greaterThan(before));
    });
  });
}

/// 不 attach 任何 client 的最小会话（只测控制器纯逻辑时用）。
LocalLoopbackSession _bareSession() {
  final h = RoomHost(roomHostOpts(
    meta: <String, Object?>{'code': 'p5t01', 'name': 'T01'},
  ));
  return LocalLoopbackSession(host: h, seat: kHostSeat, role: RoomRole.kp);
}
