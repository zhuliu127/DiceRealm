// ============================================================
// room_model_rollback.dart — 回退、生命周期与休眠项（D15，T04 · S4.1）
//
// ★ Q1 修正的落点就在这个文件：
//   旧版 `rollback()`(:3450) 重放日志时只传 `{t,seq,p}`，丢掉 `vis/to` →
//   :685 的 CHECK 脱敏判据把秘密检定当 PUBLIC 写进 state.logs、:762 的
//   PRIVATE 守卫失效，明文经 syncFor 广播给每个玩家。Dart 侧重放统一走
//   **`RoomHost.apply(rec.evt, persist:false)`**：日志里的事件对象本来就
//   持久化了 t/seq/p/vis/to（见 RoomLog.push / RoomEvent.withSeq），
//   于是「初始 emit」与「回退重放」喂给 reduce 的是完全同构的对象。
//
// ⚠️ 本文件**没有、也绝不允许有** `reduceRoomState(` 调用点：唯一的归约口
//    是 RoomHost.apply。重放路径没有任何「补丁分支」，persist 只管簿记。
//
// S4.3 追加：nextTurn / advanceRound（设计 §3.1 挂 D15）。
//   · 回合推进统一走 emit(EVT.ROUND) → apply 的簿记（roundStarts /
//     fireUsed / sanLostThisRound / fadedArm 由 host_core 自动维护）；
//   · 濒死每轮 CON、重伤每周 CON、自然回血经规则服务结算，
//     D18/D19 的 diceRoll / stateApply / applyHpChange 落事件流；
//   · 本文件同样不出现第二处归约口。
//
// P11 修 1：closeRoom / endSession 除 pending 外还要清「房间本轮进行态」
//   （state.combat + requestsBySeat）—— 终态房间仍可续玩，战斗态与幽灵
//   待办卡片不能跟着续到下一场（见 _clearTransientOnLifecycleEnd）。
// P11 修 2：rollback 重算回合内累计型字段（sanLostThisRound / roundStartSan /
//   fireUsed / fadedArm）—— 它们不进快照，只能按幸存日志重扫（见
//   _realignRoundScopedState）。改前回退后仍带着「未来那一回合」的累计。
// ============================================================

import 'js_compat.dart';
import 'madness_state.dart' as mental_state;
import 'room_model_actions_combat.dart';
import 'room_model_actions_room.dart';
import 'room_model_actions_sheet.dart';
import 'room_model_host_core.dart';
import 'room_model_state.dart';
import 'room_ports.dart';
import 'room_types.dart';

extension RoomHostRollback on RoomHost {
  // ----------------------------------------------------------
  // ★ 回退
  // ----------------------------------------------------------

  /// 回退到 `beforeSeq` 之前（丢弃 `>= beforeSeq` 的事件）。
  ///
  /// 三件事缺一不可：找最近快照 → 重放 `(snap.seq, target]` 的事件 →
  /// 裁日志 / 裁快照 / 重建 roundStarts。只裁日志会让 KP 内部状态还留着
  /// 被撤销的伤害，只换快照会丢掉快照之后仍有效的事件。
  ///
  /// Q1：重放用 [RoomHost.apply] 的 `persist:false` 路径，事件对象带 vis/to，
  /// 因此秘密检定在回退后**仍然只落脱敏行**、定向私密仍不进 state.privates。
  ///
  /// ⚠️ F3（旧版 room-model.js:3437-3439 / :3468 的缺陷修正）：旧版无条件
  ///    以 `snapshots[0]` 起步，快照表打满被裁（或 adoptSave 只留存档点
  ///    一条）后，所有留存快照的 seq 都比 target 大，于是拿「未来状态」
  ///    当基准 → 状态不退、state.seq 与 log.seq 分叉；`removeWhere` 再把
  ///    快照表清空，下一次回退 `snapshots.first` 直接抛 StateError。
  ///    这里改为：只在 `seq <= target` 里挑最近快照；一条都没有就退化为
  ///    「从建团空状态 seq0 重放 (0, target]」，并永远保留一条基线快照。
  RollbackResult rollback(int beforeSeq) {
    final target = beforeSeq - 1;
    final meta = asMap(state['meta']);
    final prevStatus = meta['status'];

    // 最近一个 seq <= target 的快照；没有则 from=0（虚拟建团基线）。
    // 绝不能像旧版那样拿 snapshots.first 兜底 —— 那条可能是「未来」状态。
    RoomSnapshot? snap;
    for (final s in snapshots) {
      if (s.seq <= target && (snap == null || s.seq > snap.seq)) {
        snap = s;
      }
    }
    final from = snap?.seq ?? 0;

    // 用快照重建状态（逐键深拷贝，保持插入序；emptyRoomState 保证 18 键齐全）。
    final rebuilt = emptyRoomState(
      snap != null && snap.state['meta'] is Map
          ? asMap(snap.state['meta'])
          : meta,
    );
    if (snap != null) {
      for (final e in snap.state.entries) {
        rebuilt[e.key] = roomClone(e.value);
      }
    }
    rebuilt['seq'] = from;
    state = rebuilt;

    // ★ Q1：同一 apply 单口、同一份持久化事件对象（含 vis/to/seq）。
    //   persist:false 不写日志、不拍快照、不重复累计私有栏与回合边界。
    for (final r in log.items) {
      if (r.seq > from && r.seq <= target) {
        apply(r.evt, persist: false);
      }
    }

    // 生命周期只进不退：回退前已在游戏中、快照却还是招募中 → 保持游戏中。
    // 否则 paintPanels 只认 IN_GAME，KP 工具会全部消失（真机实测「变旁观者」）。
    final nowMeta = asMap(state['meta']);
    if (prevStatus == RoomStatus.inGame &&
        nowMeta['status'] == RoomStatus.recruiting) {
      nowMeta['status'] = RoomStatus.inGame;
    }

    // 成员表是「谁现在连着」的现实，不是游戏历史 —— 用当前花名册覆盖回来，
    // 否则回退到建团时刻会把所有在线玩家从名单里抹掉。
    state['members'] = members();

    // ★ F3：log.seq 会被 rollbackBefore 设成 target；reduce 末尾写的却是
    //   最后一条重放事件的 seq（logCap 裁掉早期事件时可能偏小）。显式对齐，
    //   保证「状态水位 == 日志水位」，不再出现 state.seq > log.seq。
    state['seq'] = target < 0 ? 0 : target;

    // ★ P11 修 2：回合内累计型字段必须跟着回退点重算 —— 见
    //   [_realignRoundScopedState] 的说明（它们不进快照，只能按日志重算）。
    _realignRoundScopedState(target);

    final dropped = log.rollbackBefore(beforeSeq);
    snapshots.removeWhere((s) => s.seq > target);
    if (snapshots.isEmpty) {
      // 基线快照永不缺席：旧版在这里会把表清空，下一次深回退直接崩溃。
      snapshots.add(RoomSnapshot(0, asMap(roomClone(emptyRoomState(meta)))));
    }
    rebuildRoundStarts();
    return RollbackResult(dropped: dropped, seq: log.seq, from: from);
  }

  /// 回退并广播纠正结果。
  ///
  /// ⚠️ 给每个在线者**重发全量 sync**，而不是再发一条反向事件：客户端收到的
  ///    是已归约过的结果，没有反向操作可用。补一条「撤销事件」只会越滚越歪。
  List<SendPlan> rollbackPlan(int beforeSeq) {
    final r = rollback(beforeSeq);
    final out = <SendPlan>[];
    for (final m in roster.list()) {
      if (jsTruthy(m['online'])) {
        out.add(SendPlan(jsStr(m['seat']), syncFor(jsStr(m['seat']))));
      }
    }
    // 全量同步先发，最后补一条系统日志（与旧版 :3490 顺序一致）。
    pushInto(out, sys('已回退到第 ${r.seq} 条事件（撤销 ${r.dropped} 条）'));
    return out;
  }

  /// 从（已裁剪的）日志重建回合边界表。被裁掉的边界不能继续留在表里，
  /// 否则下一次回退会算到一个已不存在的 seq。
  void rebuildRoundStarts() {
    roundStarts.clear();
    for (final r in log.items) {
      final e = r.evt;
      if (e.t == RoomEvt.round && e.p['round'] != null) {
        roundStarts.add(<String, Object?>{'round': e.p['round'], 'seq': r.seq});
      }
    }
  }

  /// 按「回退到的日志水位」重算**回合内累计型**字段（P11 修 2）。
  ///
  /// 为什么必须重算：这四张表**不进快照**（`RoomSnapshot` 只有 `seq + state`
  /// 两个字段，`state` 的 18 键形状又被逐字段 fixture 锁死），它们只活在
  /// `RoomHost` 的内存里、由命令式代码维护：
  /// · `sanLostThisRound` / `roundStartSan` —— `afterSanLoss` 累加，
  ///   每遇 ROUND 事件全清（host_core `_onRoundBoundary`），治愈 / 精神分析
  ///   成功另有一次单独归零；
  /// · `fireUsed` —— 连发惩罚骰依据，ROUND 事件清零；
  /// · `fadedArm` —— 潜在疯狂的「本回合任意损失即复发」武装开关：回合边界
  ///   对**仍处潜在疯狂**的座位写 false（disarm），不定疯狂症状消退转入
  ///   潜在疯狂时写 true，**缺键即「武装」**。
  ///
  /// 于是回退到旧水位后，这些表描述的仍是**被撤销掉的那一轮**：
  /// 「未来那一回合」的 SAN 累计会把 ④ 的 `ceil(maxSAN/5)` 阈值判高、
  /// 未来的射击计数会让回退后这一枪打不出去、方向的 fadedArm 会让该复发的
  /// 不复发。快照里没有它们的副本，唯一自洽的办法是按**幸存日志**从 seq0
  /// 重扫到 target，复刻上面三条生命周期规则。
  ///
  /// 口径（报告 `_p11_lifecycle_report.md` 有完整推导）：
  /// · `sanLostThisRound`：取「本回合窗口内 `RoomEvt.state` 里 currentSAN 的
  ///   净下降量」。真实链路（SAN Check / 精神分析失败 / 改 SAN 后判疯狂）都是
  ///   「先 stateApply 写新 currentSAN，再 afterSanLoss 累加同一个 loss」，
  ///   所以净下降量 == 当时累加的量。
  /// · `roundStartSan`：本回合第一次损失前的 SAN（`prev`），只记首值 ——
  ///   与 `afterSanLoss` 的 `currentSAN + lossTotal` 同值。
  /// · `fireUsed`：射击次数只存在于内存（CHECK 事件里只有摘要文本），日志
  ///   还原不出「座位+武器 → 已发几发」→ 一律按「本回合 0 发」重算。
  ///   宁可少算一次连发惩罚，也不能把已被撤销的那一枪继续算作「已发射」。
  /// · `fadedArm`：比较「最近一次进入潜在疯狂的水位」与「最近一条 ROUND
  ///   边界」——转入在边界之后 = 本回合内武装（true）；否则 = 边界已 disarm
  ///   （false）；进入水位落在日志窗口之外（日志已被 logCap 裁掉）则保持
  ///   缺键（= 武装，与改前的默认口径一致）。
  void _realignRoundScopedState(int target) {
    sanLostThisRound.clear();
    roundStartSan.clear();
    fireUsed.clear();
    fadedArm.clear();

    var roundStartSeq = 0; // 目标回合的起点水位（最后一条 ROUND 事件的 seq）
    final lastSan = <String, int>{}; // 逐座位「上一次已知 currentSAN」
    final mentalOf = <String, List<Object?>>{};
    final armed = <String, bool>{}; // 复刻 fadedArm 的置位 / 复位

    for (final r in log.items) {
      if (r.seq > target) break;
      final e = r.evt;
      if (e.t == RoomEvt.round) {
        roundStartSeq = r.seq;
        // 回合边界：此刻仍处「潜在疯狂」的座位一律 disarm（写 false）。
        for (final seat in mentalOf.keys.toList()) {
          if (mental_state.isPotentialMadness(mentalOf[seat]!)) {
            armed[seat] = false;
          }
        }
        continue;
      }
      if (e.t != RoomEvt.state) continue;
      final seat = jsStr(e.p['seat']);
      if (seat.isEmpty) continue;

      // ① 本回合 SAN 净下降量
      final cur = raFinite(asMap(e.p['status'])['currentSAN']);
      if (cur != null) {
        final nowSan = cur.toInt();
        final prev = lastSan[seat];
        if (prev != null && nowSan < prev && r.seq > roundStartSeq) {
          sanLostThisRound[seat] =
              (sanLostThisRound[seat] ?? 0) + (prev - nowSan);
          roundStartSan.putIfAbsent(seat, () => prev);
        }
        lastSan[seat] = nowSan;
      }

      // ② 「进入 / 离开潜在疯狂」的水位
      final mentalRaw = e.p['mental'];
      if (mentalRaw is List) {
        final mental = <Object?>[for (final x in mentalRaw) jsStr(x)];
        final was = mentalOf[seat] != null &&
            mental_state.isPotentialMadness(mentalOf[seat]!);
        final nowPotential = mental_state.isPotentialMadness(mental);
        if (nowPotential && !was) armed[seat] = true;
        if (!nowPotential && was) armed.remove(seat);
        mentalOf[seat] = mental;
      }
    }

    // ③ 目标态里仍处潜在疯狂的座位：按 ①② 与回合边界推出武装状态
    for (final m in roster.list()) {
      final seat = jsStr(m['seat']);
      final sheet = m['sheet'];
      final mental =
          sheet is Map ? asList(asMap(sheet)['mental']) : const <Object?>[];
      if (!mental_state.isPotentialMadness(mental)) continue;
      final a = armed[seat];
      if (a == false) {
        fadedArm[seat] = false; // 边界已 disarm
      } else if (a == true) {
        fadedArm[seat] = true; // 本回合内才转入潜在疯狂 → 立刻武装
      }
      // a == null：进入水位在日志窗口之外，无从判定 → 保持缺键（= 武装）
    }
  }

  /// 每 `snapshotEvery` 条存一份深快照（对外暴露给回退/存档路径）。
  ///
  /// ⚠️ 不能直接转发 `host_core` 里的 `_maybeSnapshot`：Dart 私有性按库，
  ///    另一个库的 extension 访问不到下划线成员。这里复刻同一段簿记逻辑。
  ///    F3：与 `_maybeSnapshot` 完全一致 —— 保留 index 0 的建团基线，
  ///    超限只裁 index 1 起的非基线快照，两份实现不许分叉。
  void maybeSnapshot(int seq) {
    if (snapshotEvery <= 0 || seq % snapshotEvery != 0) return;
    snapshots.add(RoomSnapshot(seq, asMap(roomClone(state))));
    while (snapshots.length > snapshotLimit && snapshots.length > 1) {
      snapshots.removeAt(1);
    }
  }

  // ----------------------------------------------------------
  // 房间生命周期（事件驱动；reduce 的 CLOSED/ENDED 分支负责写 meta）
  // ----------------------------------------------------------

  /// 下发房间状态（SUSPENDED 与 CLOSED/IN_GAME 完全独立，不写 meta.ended）。
  List<SendPlan> setStatus(String s) => plan(
        emit(RoomEvt.status, <String, Object?>{'status': s},
            vis: RoomVis.public),
      );

  /// 关房：CLOSED 只置 meta.status，**不写** meta.ended（旧客户端把它当终止）。
  List<SendPlan> closeRoom() {
    final out = plan(
      emit(RoomEvt.closed, <String, Object?>{'at': now()}, vis: RoomVis.public),
    );
    _clearTransientOnLifecycleEnd();
    return out;
  }

  /// 结团：ENDED 才写 meta.ended=true（reduce 的 ENDED 分支）。
  List<SendPlan> endSession() {
    final out = plan(
      emit(RoomEvt.ended, <String, Object?>{'at': now()}, vis: RoomVis.public),
    );
    _clearTransientOnLifecycleEnd();
    return out;
  }

  /// 关房 / 结团后清掉「房间本轮进行态」（P11 修 1）。
  ///
  /// 为什么必须清：`closed` / `ended` 是**终态**，但房间对象还在 —— 用户随时
  /// 可以续玩同一间房、也可以导出历史。改前只 `pending.clear()`，于是续玩时
  /// 房间仍停在战斗态，玩家侧还挂着一张「待你确认」的幽灵卡片
  /// （`requestsBySeat` 没清，重连 `/sync` 会把它原样推回去）。
  ///
  /// ⚠️ **只清这三样**：
  /// · `state['combat']` → 回到 `emptyRoomState()` 的初值 `null`（= 未开战）；
  /// · `pending`（待确认队列）与 `requestsBySeat`（逐座位待办请求表）。
  /// 花名册、日志、存档、场景、素材**一律保留** —— 结团后用户还要导出历史。
  ///
  /// ⚠️ 为什么不顺手清 `state['requests']`：那是 `REQUEST` 事件的归约镜像
  ///    （每个客户端各存一份），玩家侧卡片真正的数据源是 `/sync` 里的
  ///    `_requestsView(seat)` ← `requestsBySeat`，清掉后者就够了；而镜像本身
  ///    是逐字段 fixture 锁定的旧版行为（`F:1#2024` 的 `$.state.requests`），
  ///    动它等于改旧版等价性，超出本缺陷范围。
  ///
  /// ⚠️ 为什么不 `emit(RoomEvt.combat, {'combat': null})`：那会多出一条日志、
  ///    一个序号与一条发送计划，`closeRoom()` / `endSession()` 的出站形状是
  ///    fixture 逐条比对的（`S:status#1016/#1018`）。这里只是把权威态收敛回
  ///    「没有进行中的战斗」，不是一条新的房间事件。
  /// ⚠️ 幂等：全是 `clear()` / 置 `null`，重复调用不抛错、无副作用。
  void _clearTransientOnLifecycleEnd() {
    state['combat'] = null;
    pending.clear();
    requestsBySeat.clear();
  }

  /// 踢人：给被踢者单独发 KICK，其余人只看到成员表变化。
  List<SendPlan> kick(String seat) {
    final m = roster.get(seat);
    if (m == null) return <SendPlan>[];
    final out = <SendPlan>[];
    pushInto(
      out,
      emit(
        RoomEvt.kick,
        <String, Object?>{'reason': '你已被房主移出房间'},
        vis: RoomVis.seat,
        to: seat,
      ),
    );
    roster.remove(seat);
    out.addAll(syncMembers());
    pushInto(out, sys('${_nick(m, seat)} 已离开房间'));
    return out;
  }

  /// 公开信息栏优先显示角色名，其次昵称；KP 座位回落 meta.kpName / 'KP'。
  String _nick(Map<String, Object?>? m, String seat) {
    if (m != null && jsTruthy(m['charName'])) return jsStr(m['charName']);
    if (m != null && jsTruthy(m['nickname'])) return jsStr(m['nickname']);
    if (seat == kHostSeat) {
      final kp = asMap(state['meta'])['kpName'];
      return jsTruthy(kp) ? jsStr(kp) : 'KP';
    }
    return '某人';
  }

  // ----------------------------------------------------------
  // Q6 休眠项：**入口已摘除**，但方法/字段保留供旧存档回放
  // ----------------------------------------------------------

  /// 回退提议（Q6 休眠）：不产生任何事件或状态变更。
  List<SendPlan> rollbackPropose(String bySeat, int turns) =>
      const <SendPlan>[];

  /// 回退投票（Q6 休眠）：没有进行中的表决时旧版直接忽略。
  List<SendPlan> rollbackVote(String seat, bool agree) {
    final r = rewind;
    if (r == null || r['state'] != RoomRewind.voting) {
      // 旧版 :3321 —— 没有进行中的表决时回一条定向提示。
      // Q6 休眠的是「表决 / 回退提交」这条流程，不是把这句反馈也吞掉；
      // 否则玩家点投票后界面毫无反应。休眠分支仍不改 rewind 状态。
      final out = <SendPlan>[];
      pushInto(out, sysTo(seat, '当前没有回退投票'));
      return out;
    }
    return const <SendPlan>[];
  }

  /// 回退提交（Q6 休眠）：不产生任何事件或状态变更。
  List<SendPlan> rollbackCommit(String bySeat) => const <SendPlan>[];

  /// 表决期间有人掉线 → 旧版默认本次回退失败（Q6 休眠）。
  List<SendPlan> rollbackAbortIfVoting(String seat) {
    final r = rewind;
    if (r == null || r['state'] != RoomRewind.voting) {
      return const <SendPlan>[];
    }
    final need = asList(r['need']);
    if (!need.contains(seat)) return const <SendPlan>[];
    r['state'] = RoomRewind.failed;
    r['failReason'] = '有玩家在表决期间断线';
    final out = <SendPlan>[];
    pushInto(
      out,
      emit(RoomEvt.rewind, <String, Object?>{'rewind': roomClone(r)},
          vis: RoomVis.public),
    );
    pushInto(out, sys('回退失败：有玩家在表决期间断线'));
    return out;
  }

  // ----------------------------------------------------------
  // S4.3 —— 回合推进：nextTurn / advanceRound（设计 §3.1）
  // ----------------------------------------------------------

  /// 推进行动轮（多行动怪物在 order 里已是多个槽；旧版 :3534-3611）。
  List<SendPlan> nextTurn() {
    final out = <SendPlan>[];
    if (state['combat'] is! Map) {
      pushInto(out, sys('当前没有战斗，无法推进行动轮'));
      return out;
    }
    final c = asMap(state['combat']);
    if (c['order'] is! List || asList(c['order']).isEmpty) {
      pushInto(out, sys('当前没有战斗，无法推进行动轮'));
      return out;
    }
    final order = asList(c['order']);
    final len = order.length;
    final i = (c['turn'] == null) ? 0 : raNum(c['turn'], 0).toInt();
    final prevRound = raNum(c['round'], 1).toInt();
    if (i >= 0 && i < len && order[i] is Map) {
      asMap(order[i])['done'] = true;
    }
    final curActor = (i >= 0 && i < len)
        ? asMap(order[i])['actorId']
        : null;
    if (curActor != null) {
      var allMineDone = true;
      var othersPending = false;
      for (var k = 0; k < len; k++) {
        final s = asMap(order[k]);
        if (s['actorId'] == curActor) {
          if (!jsTruthy(s['done'])) allMineDone = false;
        } else if (!jsTruthy(s['done']) && !raSlotDown(s)) {
          othersPending = true;
        }
      }
      // P15：只写不读，保留是为存档键兼容；回绕不再重排（不做 movedToTail 下沉）。
      if (allMineDone && othersPending) {
        for (var m = 0; m < len; m++) {
          final s = asMap(order[m]);
          if (s['actorId'] == curActor) s['movedToTail'] = true;
        }
      }
    }
    var round = prevRound;
    var next = i + 1;
    var guard = 0;
    while (guard++ <= len) {
      if (next >= len) {
        next = 0;
        round += 1;
        for (final s in order) {
          asMap(s)
            ..['done'] = false
            ..['movedToTail'] = false;
        }
      }
      final cand = next < order.length ? order[next] : null;
      if (!jsTruthy(asMap(cand)['done']) && !raSlotDown(cand)) break;
      next += 1;
    }
    final target = (next >= 0 && next < order.length) ? order[next] : null;
    if (target == null || raSlotDown(target)) {
      pushInto(out, sys('没有可行动的单位了，请结束战斗或添加新单位'));
      return out;
    }
    if (round != prevRound) {
      advanceRoundInto(out, round);
    }
    pushInto(out, emit(RoomEvt.turnstate, <String, Object?>{
      'turn': next,
      'round': round,
      'order': order,
    }, vis: RoomVis.public));
    final cur = asMap(target);
    final name = jsStr(cur['name'] ?? '—');
    final totalSlots = raNum(cur['totalSlots'], 1).toInt();
    final slotNo = raNum(cur['slot'], 1).toInt();
    pushInto(out, sys('第 $round 轮 · 轮到 $name'
        '${totalSlots > 1 ? '（第 $slotNo/$totalSlots 次行动）' : ''}'));
    pushInto(out, emit(RoomEvt.turnAlert, <String, Object?>{
      'kind': 'turn',
      'round': round,
      'turn': next,
      'name': cur['name'] ?? '',
      'seat': cur['seat'] ?? '',
      'roundChanged': round != prevRound,
      'at': now(),
    }, vis: RoomVis.public));
    return out;
  }

  /// 统一回合出口：发 ROUND + 濒死每轮 CON + 天/周恢复 + TEMP_COMMIT
  /// （旧版 :3674-3688）。返回全新的发送计划列表，供 applyAction 合并。
  List<SendPlan> advanceRound(int round) {
    final out = <SendPlan>[];
    advanceRoundInto(out, round);
    return out;
  }

  /// [advanceRound] 的原地累加版本（供 nextTurn 复用同一个 out）。
  void advanceRoundInto(List<SendPlan> out, int round) {
    pushInto(out,
        emit(RoomEvt.round, <String, Object?>{'round': round}, vis: RoomVis.public));
    out.addAll(onRoundBoundaryJudgments());
    out.addAll(onDayWeekTick());
    pushInto(out, emit(RoomEvt.tempCommit, <String, Object?>{
      'round': round,
      'at': now(),
    }, vis: RoomVis.public));
  }

  /// 回合边界结算：濒死成员每轮做一次 CON 检定（旧版 :3623-3659）。
  List<SendPlan> onRoundBoundaryJudgments() {
    final out = <SendPlan>[];
    for (final m in roster.players()) {
      if (m['sheet'] is! Map) continue;
      final st = asMap(asMap(m['sheet'])['status']);
      if (!jsTruthy(st['dying'])) continue;
      final seat = jsStr(m['seat']);
      final con = raMemberAttr(m, 'con');
      final chk = rules?.dyingRoundCheck(con ?? 50, rng);
      if (chk == null) continue;
      final seatName = raNick(this, m, seat);
      out.addAll(diceRoll(seat, <String, Object?>{
        'expr': '1D100',
        'label': '濒死 CON 检定（对 ${asMap(chk['check'])['base']}）',
        'result': chk['check'],
      }));
      if (chk['dead'] == true) {
        out.addAll(stateApply(seat, <String, Object?>{
          'status': <String, Object?>{'body': '死亡', 'dying': false},
        }, <String, Object?>{'reason': '濒死 CON 检定失败 → 死亡'}));
        out.addAll(syncBodyToCombatSlot(m));
        pushInto(out, emit(RoomEvt.log, <String, Object?>{
          'seat': '',
          'text': '$seatName 濒死 CON 检定失败 —— 死亡，撕卡',
          'at': now(),
          'kind': 'warn',
        }, vis: RoomVis.public));
      } else {
        pushInto(out, emit(RoomEvt.log, <String, Object?>{
          'seat': '',
          'text': '$seatName 濒死 CON 检定：${jsStr(chk['summary'])}',
          'at': now(),
          'kind': 'state',
        }, vis: RoomVis.public));
      }
    }
    return out;
  }

  /// 天/周恢复判定：1 回合 = 1 天，3 回合 = 1 周（旧版 :3705-3770）。
  List<SendPlan> onDayWeekTick() {
    final out = <SendPlan>[];
    final meta = asMap(state['meta']);
    if (meta['hpWeek'] is! Map) meta['hpWeek'] = <String, Object?>{};
    final week = asMap(meta['hpWeek']);
    final round = raNum(meta['round'], 0).toInt();
    final levelMap = rules?.levelMap ?? const <String, int>{};
    for (final m in roster.players()) {
      if (m['sheet'] is! Map) continue;
      final st = asMap(asMap(m['sheet'])['status']);
      final seat = jsStr(m['seat']);
      final body = jsTruthy(st['body']) ? jsStr(st['body']) : '正常';
      if (body == '死亡' ||
          jsTruthy(st['dying']) ||
          jsTruthy(st['unconscious'])) {
        week.remove(seat);
        continue;
      }
      final maxHP = raMemberStatusValue(m, 'maxHP');
      final hp = raMemberStatusValue(m, 'currentHP');
      if (maxHP == null || !(maxHP > 0) || hp == null) {
        week.remove(seat);
        continue;
      }
      if (body == '重伤') {
        final base = week[seat];
        if (base == null || raNum(base, 0) > round) {
          week[seat] = round;
          continue;
        }
        if (round - raNum(base, 0) < 3) continue;
        week[seat] = round;
        final con = raMemberAttr(m, 'con');
        final chk = rules?.check(<String, Object?>{
          ...ruleOptsOf(meta),
          'base': con ?? 50,
          'difficulty': 'regular',
          'kind': 'attribute',
          'label': '重伤每周 CON 检定',
          'rng': rng,
        });
        if (chk == null) continue;
        out.addAll(diceRoll(seat, <String, Object?>{
          'expr': '1D100',
          'label': '重伤每周 CON 检定（对 ${chk['base']}）',
          'result': chk,
        }));
        final who = raNick(this, m, seat);
        if (chk['passed'] != true) {
          pushInto(out, emit(RoomEvt.log, <String, Object?>{
            'seat': '',
            'text': '$who 重伤每周 CON 检定失败（掷 ${jsStr(chk['value'])}），本周没有恢复',
            'at': now(),
            'kind': 'state',
          }, vis: RoomVis.public));
          continue;
        }
        final lvl = raNum(chk['level'], 0).toInt();
        final isExtreme = lvl == (levelMap['EXTREME'] ?? 4) ||
            lvl == (levelMap['CRITICAL'] ?? 5);
        final rr = rules?.rollExpr(isExtreme ? '2D3' : '1D3', rng);
        final healAmt = (rr != null && rr['ok'] == true)
            ? (raNum(rr['total'], 0) > 0 ? raNum(rr['total'], 0) : 0)
            : 0;
        if (healAmt > 0) {
          out.addAll(applyHpChange(m, healAmt,
              '重伤每周 CON ${isExtreme ? '极难成功' : '成功'}恢复 ${healAmt.toInt()}',
              <String, Object?>{}));
        }
        if (isExtreme) {
          final hAfter = raMemberStatusValue(m, 'currentHP');
          final clearBody = (hAfter != null && maxHP > 0 && hAfter >= maxHP)
              ? '正常'
              : '轻伤';
          out.addAll(stateApply(seat, <String, Object?>{
            'status': <String, Object?>{'body': clearBody},
          }, <String, Object?>{'reason': '重伤每周 CON 极难成功 → 清除重伤'}));
          out.addAll(syncBodyToCombatSlot(m));
        }
        pushInto(out, emit(RoomEvt.log, <String, Object?>{
          'seat': '',
          'text': '$who 重伤每周 CON 检定${isExtreme ? '极难成功' : '成功'}'
              '（掷 ${jsStr(chk['value'])}），恢复 ${healAmt.toInt()} 点生命',
          'at': now(),
          'kind': 'state',
        }, vis: RoomVis.public));
        continue;
      }
      if (hp < maxHP) {
        out.addAll(applyHpChange(m, 1, '自然恢复（每日 +1 HP）',
            <String, Object?>{}));
      }
    }
    return out;
  }
}
