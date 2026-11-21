// ============================================================
// test/p10_t2_tempcommit_test.dart — P10 第 2 期 A：推回合自动保存对齐老 APP
//
// 老 APP v2.9.0 的口径（逐行抠自 `core/room-model.js#_advanceRound`）：
//   ① `_push(emit(EVT.ROUND))`
//   ② `out = out.concat(_onRoundBoundary())`   ← 濒死每轮 CON
//   ③ `out = out.concat(_onDayWeekTick())`      ← 天/周恢复（重伤每周回血）
//   ④ **最后** `_push(emit(EVT.TEMP_COMMIT))`   ← 临时卡生效 → 玩家自行落库
//   老 APP 原注释：必须等 ③ 之后才发，否则玩家会把「恢复前」的旧值覆盖回原卡。
//
// 覆盖：
//   1. **顺序**：计划里 tempCommit 必须排在 round 与 dayweek/state **之后**，
//      且是本批计划的最后一条（核心）
//   2. 触发：`round.next` / `rollback.round` / `combat.next` **整轮折返**触发；
//      `combat.next` 非折返**不**触发
//   3. `room.start`（开局）不触发
//   4. roomCode 隔离：另一间房推进回合，本房不落库
//   5. 幂等：同一 round 应用两次只保存一次
//   6. 存档**不含** tempCommit
//   7. 客户端收到后生效：覆盖原卡（数值来自权威端）
//
// 铁律：全内存后端；零 Timer / Future.delayed / AnimationController。
// ============================================================

import 'dart:convert' show jsonEncode;

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart' show asMap;
import 'package:dice_realm/domain/room_model_host_core.dart' show RoomHost;
import 'package:dice_realm/domain/room_model_rollback.dart' show RoomHostRollback;
import 'package:dice_realm/domain/room_model_save.dart' show RoomHostSave;
import 'package:dice_realm/domain/room_types.dart'
    show RoomEvt, RoomRole, SendPlan, kHostSeat;
import 'package:dice_realm/repo/character_repo.dart' show CharacterRepo;
import 'package:dice_realm/repo/room_state_writer.dart'
    show CharacterRepoRoomCardSink;
import 'package:dice_realm/theme.dart' show Palette;
import 'package:dice_realm/ui/room/room_card_saver.dart' show RoomCardSaver;
import 'package:dice_realm/ui/room/room_controller.dart' show RoomController;
import 'package:dice_realm/ui/room/room_net_factory.dart' show RoomNetFactory;
import 'package:dice_realm/ui/room/room_session.dart' show RoomSession;
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' show newMemoryRepo;
import 'support/room_fakes.dart' show roomHostOpts;
import 'support/room_ui_harness.dart' show RoomUiFixture;

/// 出站信封里的 `t`（只读诊断用）。
///
/// 两种输入都收：`sentLog` 里的 `SendPlan.toJson()`（Map），
/// 以及 domain 级 `nextTurn()` 直接返回的 [SendPlan]。
String _t(Object? plan) {
  Object? raw = plan;
  if (plan is SendPlan) raw = plan.toJson();
  if (raw is! Map) return '';
  // 两种形状都要认：`{to, msg:{k,t,...}}`（SendPlan）与 `{k,t,...}`（信封本身）
  final outer = asMap(raw);
  final m = outer['msg'] is Map ? asMap(outer['msg']) : outer;
  if (m['k'] != 'evt') return '';
  final t = m['t'];
  return t is String ? t : '';
}

/// 「改临时卡」的事件类型：天/周恢复与濒死检定都会产生这两类。
const Set<String> _kStatefulEvts = <String>{
  RoomEvt.state,
  RoomEvt.dice,
};

/// 断言「tempCommit 排在所有改临时卡的事件之后」（老 APP 的核心顺序要求）。
///
/// 注意：`round.next` 在统一出口之后还会追加一条系统播报（`EVT.LOG`），
/// 所以 tempCommit **不是**整批计划的最后一条 —— 老 APP 也一样。
/// 真正的要求是：它必须在 `round` 与所有 `state`/`dice` 之后。
void _expectCommitAfterStateful(List<String> types) {
  final int iRound = types.indexOf(RoomEvt.round);
  final int iCommit = types.lastIndexOf(RoomEvt.tempCommit);
  expect(iRound, greaterThanOrEqualTo(0), reason: '本批必须有 round 事件');
  expect(iCommit, greaterThanOrEqualTo(0), reason: '本批必须有 tempCommit 事件');
  expect(iCommit, greaterThan(iRound),
      reason: '老 APP 顺序硬要求：ROUND 先发，TEMP_COMMIT 后发');
  for (var j = 0; j < types.length; j++) {
    if (j == iCommit) continue;
    if (!_kStatefulEvts.contains(types[j])) continue;
    expect(j, lessThan(iCommit),
        reason: '★ 所有会改临时卡的事件（重伤周回血 / 濒死检定）必须在 '
            'TEMP_COMMIT 之前，否则玩家把「恢复前」的旧值覆盖回原卡');
  }
  // tempCommit 之后只允许出现系统播报（EVT.LOG）
  for (var j = iCommit + 1; j < types.length; j++) {
    expect(types[j], RoomEvt.log,
        reason: 'tempCommit 之后不该再有状态类事件（收到 $types）');
  }
}

/// 造一张卡（供自动保存断言「真的落盘了」）。
Character _card(String id, String name, {num hp = 12}) {
  final c = Character(newCharacter());
  c.raw['id'] = id;
  c.raw['characterName'] = name;
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
  c.raw['occupationName'] = '记者';
  final status = c.status;
  status['maxHP'] = hp;
  status['currentHP'] = hp;
  status['maxMP'] = 10;
  status['currentMP'] = 10;
  status['maxSAN'] = 99;
  status['currentSAN'] = 60;
  return c;
}

/// 从某个视角的 state 里取某座位成员的当前 HP（裁剪态里就是 `sheet.status.currentHP`）。
num _hpOf(Map<String, Object?> state, String seat) {
  for (final row in (state['members'] as List<Object?>? ?? const <Object?>[])) {
    final m = asMap(row);
    if (m['seat'] != seat) continue;
    final v = asMap(asMap(m['sheet'])['status'])['currentHP'];
    if (v is num) return v;
  }
  return -1;
}

RoomController _controllerWithRepo(RoomUiFixture f, String seat, CharacterRepo repo) {  final RoomSession session = f.sessionOf(seat);
  return RoomController(
    session: session,
    local: f.localOf(seat),
    notes: f.notes,
    imagePicker: f.picker,
    saveStore: f.saves,
    nowMs: () => f.nowMs,
    cardSink: CharacterRepoRoomCardSink(repo),
  );
}

void main() {
  setUp(() {
    Palette.useBrightness(Brightness.dark);
    RoomNetFactory.discoveryEnabled = false;
    RoomNetFactory.networkEnabled = false;
  });

  tearDown(() {
    RoomNetFactory.discoveryEnabled = true;
    RoomNetFactory.networkEnabled = true;
  });

  // ==========================================================
  // 1. 顺序（核心）
  // ==========================================================
  group('1 · 回合出口顺序：round → 边界/天周 → tempCommit（最后）', () {
    test('tempCommit 排在 round 之后、且之后不再有状态类事件', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 2, spectators: 0);
      final int before = f.kpSession.sentLog.length;

      await f.kpSession.hostAction('round.next');

      final List<String> types =
          f.kpSession.sentLog.sublist(before).map(_t).toList();
      _expectCommitAfterStateful(types);
    });

    test('重伤玩家周恢复（改临时卡）发生在 tempCommit 之前', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);

      // 直接注入「重伤 + 缺 HP + 上次周检定在第 1 回合」的名册态：
      // 本用例只验**计划顺序**，不验规则数值（规则数值另有 oracle 用例覆盖）。
      final m = f.host.roster.get('p1')!;
      final sheet = asMap(m['sheet']);
      final status = asMap(sheet['status']);
      status['body'] = '重伤';
      status['currentHP'] = 5;
      status['maxHP'] = 12;
      status['dying'] = false;
      status['unconscious'] = false;
      final meta = asMap(f.host.state['meta']);
      meta['round'] = 4;
      meta['hpWeek'] = <String, Object?>{'p1': 1};

      final int before = f.kpSession.sentLog.length;
      await f.kpSession.hostAction('round.next');
      final List<String> types =
          f.kpSession.sentLog.sublist(before).map(_t).toList();

      final int iCommit = types.lastIndexOf(RoomEvt.tempCommit);
      final int iState =
          types.indexWhere((String t) => _kStatefulEvts.contains(t));
      expect(iState, greaterThanOrEqualTo(0),
          reason: '重伤每周 CON 检定会经 EVT.DICE / EVT.STATE 落事件（前提）');
      expect(iCommit, greaterThan(iState),
          reason: '★ 核心：tempCommit 必须在改临时卡之后');
      _expectCommitAfterStateful(types);
    });
  });

  // ==========================================================
  // 2. 触发面
  // ==========================================================
  group('2 · 触发面：round.next / rollback.round / combat.next（仅折返）', () {
    test('round.next → 玩家视角 lastTempCommitRound 变成新回合号', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      expect(f.sessionOf('p1').lastTempCommitRound, 0,
          reason: '开局（room.start）不触发，所以还没收到过');

      await f.kpSession.hostAction('round.next');
      expect(f.sessionOf('p1').lastTempCommitRound, greaterThan(0),
          reason: 'round.next 必须把 TEMP_COMMIT 送到玩家端');
    });

    test('rollback.round → 同样触发（走同一个统一出口）', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      await f.kpSession.hostAction('round.next');
      final int afterFirst = f.sessionOf('p1').lastTempCommitRound;

      await f.kpSession.hostAction('rollback.round');
      expect(f.sessionOf('p1').lastTempCommitRound, greaterThan(afterFirst),
          reason: '回退一个回合也是「回合变化」，必须同样发 TEMP_COMMIT');
    });

    test('combat.next 非折返 → 不触发；整轮折返 → 触发', () {
      // 纯 domain 级：直接调 nextTurn() 拿计划，不经网络
      final RoomHost host = RoomHost(roomHostOpts());
      host.state['combat'] = <String, Object?>{
        'round': 1,
        'turn': 0,
        'order': <Object?>[
          <String, Object?>{
            'seat': 'p1',
            'actorId': 'a1',
            'name': '甲',
            'done': false,
            'movedToTail': false,
          },
          <String, Object?>{
            'seat': 'p2',
            'actorId': 'a2',
            'name': '乙',
            'done': false,
            'movedToTail': false,
          },
        ],
      };

      // ① 同一轮内推进（turn 0 → 1）：round 不变 → 不得发 TEMP_COMMIT
      final withinRound = host.nextTurn().map(_t).toList();
      expect(withinRound.contains(RoomEvt.tempCommit), isFalse,
          reason: '非折返的 turnstate 推进不改变回合号，玩家不该落库');
      expect(asMap(host.state['combat'])['turn'], 1, reason: '前提：轮到乙了');

      // ② 再推一次 → 队尾折返、round 1 → 2 → 必须发 TEMP_COMMIT
      final wrapped = host.nextTurn().map(_t).toList();
      expect(wrapped.contains(RoomEvt.tempCommit), isTrue,
          reason: '整轮折返（round 变化）必须触发临时卡生效');
      expect(asMap(host.state['combat'])['round'], 2, reason: '前提：回合已 +1');
      expect(wrapped.indexOf(RoomEvt.round),
          lessThan(wrapped.lastIndexOf(RoomEvt.tempCommit)));
    });

    test('开局 room.start 不触发（它不走统一出口）', () async {
      final f = RoomUiFixture();
      await f.boot(players: 1, spectators: 0);
      final int before = f.kpSession.sentLog.length;
      await f.kpSession.hostAction('room.start');
      final types = f.kpSession.sentLog.sublist(before).map(_t).toList();
      expect(types.contains(RoomEvt.round), isTrue,
          reason: '开局会发 ROUND（首回合边界）');
      expect(types.contains(RoomEvt.tempCommit), isFalse,
          reason: '★ 开局不是「时间流逝」：老 APP 故意不走 _advanceRound');
      expect(f.sessionOf('p1').lastTempCommitRound, 0);
    });
  });

  // ==========================================================
  // 3. 客户端生效
  // ==========================================================
  group('3 · 客户端收到 TEMP_COMMIT → 把本房本卡写回已保存角色卡', () {
    test('自动保存：round.next 后落库一次（数值来自权威端）', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白', hp: 12));

      await f.kpSession.hostAction('sheet.damage', <String, Object?>{
        'seat': 'p1',
        'amount': 4,
        'reason': '测试伤害',
      });
      // 房间里 p1 的当前 HP（玩家视角收到的裁剪态）
      final num hurt = _hpOf(f.stateOf('p1'), 'p1');
      expect(hurt, lessThan(12), reason: '前提：房间里的 HP 已经掉了');

      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );
      await f.kpSession.hostAction('round.next');
      // ★ 回合出口里 `_onDayWeekTick` 会给未重伤者 +1 HP（1 回合 = 1 天）。
      //   落库必须发生在**恢复之后** —— 这正是老 APP 把 TEMP_COMMIT 放在
      //   `_onDayWeekTick()` 之后的原因（否则玩家把恢复前的旧值写回原卡）。
      final num healed = _hpOf(f.stateOf('p1'), 'p1');
      expect(healed, greaterThan(hurt), reason: '前提：本回合发生了自然恢复');

      await saver.onStateChanged();
      expect(saver.autoSaved, 1, reason: 'TEMP_COMMIT 后必须自动保存一次');
      final Character? saved = repo.get('c_p1');
      expect(saved, isNotNull);
      expect(saved!.status['currentHP'], healed,
          reason: '★ 存下去的是**恢复之后**的权威值（顺序错的话这里会是恢复前的 $hurt）');
      expect(saved.status['currentHP'], lessThan(12));
    });

    test('幂等：同一 round 通知两次只保存一次', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白'));

      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );
      await f.kpSession.hostAction('round.next');
      await saver.onStateChanged();
      await saver.onStateChanged();
      await saver.onStateChanged();
      expect(saver.autoSaved, 1, reason: '同一回合重复应用不叠加（幂等）');

      await f.kpSession.hostAction('round.next');
      await saver.onStateChanged();
      expect(saver.autoSaved, 2, reason: '下一个回合再存一次');
    });

    test('roomCode 隔离：别房推进回合，本房不落库', () async {
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白'));

      // 本房（不动）
      final RoomUiFixture mine = RoomUiFixture();
      await mine.boot(inGame: true, players: 1, spectators: 0, code: 'room-a');
      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(mine, 'p1', repo),
        session: mine.sessionOf('p1'),
      );

      // 另一间房（推进回合）
      final RoomUiFixture other = RoomUiFixture();
      await other.boot(inGame: true, players: 1, spectators: 0, code: 'room-b');
      await other.kpSession.hostAction('round.next');
      expect(other.sessionOf('p1').lastTempCommitRound, greaterThan(0));

      // 本房仍是「没收到过 → 不落库」
      await saver.onStateChanged();
      expect(saver.autoSaved, 0,
          reason: '本机可能同时留有多间房（续玩 / 多开），别房的 TEMP_COMMIT 绝不误伤本房');
      expect(mine.sessionOf('p1').lastTempCommitRound, 0);
    });

    test('本机没有「本房临时卡」→ 静默跳过（不报错、不写盘）', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0, withSheets: false);
      final CharacterRepo repo = await newMemoryRepo();
      final RoomCardSaver saver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'p1', repo),
        session: f.sessionOf('p1'),
      );
      await f.kpSession.hostAction('round.next');
      await saver.onStateChanged();
      expect(saver.autoSaved, 0);
      expect(repo.all, isEmpty, reason: '静默跳过：不写盘、不抛、不弹错');
      expect(saver.lastError, isEmpty);
    });
  });

  // ==========================================================
  // 4. 不进存档
  // ==========================================================
  group('4 · TEMP_COMMIT 不进存档', () {
    test('save() 里不出现 tempcommit（键与字面量都不许有）', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      await f.kpSession.hostAction('round.next');
      await f.kpSession.hostAction('round.next');

      final Map<String, Object?> save = f.host.save();
      final String text = jsonEncode(save);
      expect(text.contains('tempcommit'), isFalse,
          reason: 'reduce 无分支 + save 不含它：它是一次性广播信号，不是状态');
      expect(save.containsKey('tempCommit'), isFalse);
      expect(save.containsKey('tempcommit'), isFalse);
    });

    test('客户端 state 里也没有 tempCommit 残留（reduce 无分支）', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      await f.kpSession.hostAction('round.next');
      final st = f.stateOf('p1');
      expect(st.containsKey('tempCommit'), isFalse);
      expect(st.containsKey('tempcommit'), isFalse);
      expect(jsonEncode(st).contains('tempcommit'), isFalse);
    });
  });

  // ==========================================================
  // 5. 会话层信号本身
  // ==========================================================
  group('5 · RoomSession.lastTempCommitRound 的取值口径', () {
    test('KP 视角也能看到（同一份广播），但 KP 不落库', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 1);
      final CharacterRepo repo = await newMemoryRepo();
      await repo.save(_card('c_p1', '沈墨白'));

      final RoomCardSaver kpSaver = RoomCardSaver(
        controller: _controllerWithRepo(f, kHostSeat, repo),
        session: f.sessionOf(kHostSeat),
      );
      final RoomCardSaver spSaver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'sp1', repo),
        session: f.sessionOf('sp1'),
      );
      await f.kpSession.hostAction('round.next');
      await kpSaver.onStateChanged();
      await spSaver.onStateChanged();
      expect(kpSaver.autoSaved, 0, reason: 'KP 本机没有别人的卡，也不该写自己的');
      expect(spSaver.autoSaved, 0, reason: '旁观者没有角色卡');
      expect(f.sessionOf('p1').lastTempCommitRound, greaterThan(0));
    });

    test('回合号单调前进：两次推进 → 两个不同的回合号', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 0);
      await f.kpSession.hostAction('round.next');
      final int r1 = f.sessionOf('p1').lastTempCommitRound;
      await f.kpSession.hostAction('round.next');
      final int r2 = f.sessionOf('p1').lastTempCommitRound;
      expect(r2, greaterThan(r1));
    });

    test('角色不是玩家 → 即使收到也不落库（结构性约束）', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, players: 1, spectators: 1);
      final CharacterRepo repo = await newMemoryRepo();
      final RoomCardSaver spSaver = RoomCardSaver(
        controller: _controllerWithRepo(f, 'sp1', repo),
        session: f.sessionOf('sp1'),
      );
      expect(f.sessionOf('sp1').role, RoomRole.spectator);
      await f.kpSession.hostAction('round.next');
      await spSaver.onStateChanged();
      expect(spSaver.autoSaved, 0);
    });
  });
}
