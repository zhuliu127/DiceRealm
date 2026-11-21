// ============================================================
// room_model_host_core.dart — 权威端 `RoomHost` 核心（D14）
//
// ★★ 本文件的核心是 `apply(RoomEvent evt, {bool persist = true})`：
//    它是**唯一**的状态变更入口（C9 + Q1）。初始 `emit` 与 `rollback` 重放
//    都调它、都传**持久化的完整事件对象**（含 vis/to/seq）；
//    `persist` 只控制簿记（入日志 / 私有累计 / 回合边界 / 快照），
//    **不参与任何归约判定**，重放路径不写任何补丁分支。
//
// ⚠️ `reduceRoomState(` 在本文件只出现 1 次（就在 apply 里）。
// ⚠️ 为何内部容器是 public 字段而不是 `_xxx`：状态机的主体分布在
//    `extension on RoomHost`（D15~D19/D21）里，而 Dart 的私有性是**按库**的 ——
//    另一个库的 extension 访问不到 `_field`。所以这些容器必须公开（命名上
//    仍保持「这是内部实现」的语义，改它们只能走 apply / 收口方法）。
// ============================================================

import 'js_compat.dart';
import 'madness_state.dart' as mental_state;
import 'room_model_envelope.dart';
import 'room_model_log.dart';
import 'room_model_reduce.dart';
// `detachPeer` 要在掉线时中止进行中的回退表决（需求 §9）：`rollbackAbortIfVoting`
// 是 `extension RoomHostRollback on RoomHost`，扩展方法必须 import 定义库才可见。
// 与 rollback → host_core 构成库环，Dart 允许（库环只影响初始化顺序，不影响
// 扩展解析；两边都没有 const 依赖对方的顶层初始化）。
import 'room_model_rollback.dart';
import 'room_model_state.dart';
import 'room_ports.dart';
import 'room_types.dart';

/// 「参数没传」的哨兵（`syncFor` 与 `_makeSync` 需要区分「没传」与「传了 null」）。
class _Undef {
  const _Undef();
}

const Object _kUndef = _Undef();

/// Host 构造参数。C3：随机源/时钟**只从 js_compat 取**，不另造注入点。
class RoomHostOptions {
  RoomHostOptions({
    this.meta = const <String, Object?>{},
    this.logCap = 400,
    this.snapshotEvery = 20,
    this.snapshotLimit = 20,
    JsClock? now,
    JsRng? rng,
    this.rules,
    this.madness,
    this.saveStore,
  })  : now = now ?? nowClock,
        rng = rng ?? nowRng;

  final Map<String, Object?> meta;
  final int logCap;
  final int snapshotEvery;
  final int snapshotLimit;
  final JsClock now;
  final JsRng rng;
  final RoomRulesPort? rules;
  final RoomMadnessPort? madness;
  final RoomSaveStore? saveStore;
}

/// 权威端（KP 那台设备）。所有对外方法返回 `List<SendPlan>`，不发包。
class RoomHost {
  RoomHost(RoomHostOptions opts)
      : log = RoomLog(cap: opts.logCap),
        now = opts.now,
        rng = opts.rng,
        rules = opts.rules,
        madness = opts.madness,
        saveStore = opts.saveStore,
        snapshotEvery = opts.snapshotEvery > 0 ? opts.snapshotEvery : 20,
        snapshotLimit = opts.snapshotLimit > 0 ? opts.snapshotLimit : 20 {
    state = emptyRoomState(opts.meta);
    roster = RoomRoster();
    snapshots.add(RoomSnapshot(0, _cloneMap(state)));
  }

  /// 权威状态。**只能经 [apply] 修改**（`save`/`adoptSave` 重建时除外）。
  late Map<String, Object?> state;

  late RoomRoster roster;
  final RoomLog log;

  /// 回退用快照。第 0 条永远是建团时的空状态 —— 回退到最开头也有东西可恢复。
  final List<RoomSnapshot> snapshots = <RoomSnapshot>[];

  /// 已剥离私有字段 / SEAT 缺收件人等异常（正常路径必须为空）。
  final List<RoomWarning> warnings = <RoomWarning>[];

  /// KP 私密备忘（**不占共享序号**，永不外发）。
  int localSeq = 0;
  final List<LogRecord> local = <LogRecord>[];

  /// 角色卡写回的独立单调序号（`stateApply` 每次 +1，客户端据此幂等）。
  int stateSeq = 0;

  /// 回合边界表 `[{round, seq}]`（回退点从这里取）。
  final List<Map<String, Object?>> roundStarts = <Map<String, Object?>>[];

  /// 逐 seat 的私有累计（重连全量同步要靠它恢复）。
  final Map<String, List<Object?>> privateBySeat =
      <String, List<Object?>>{};
  final Map<String, List<Map<String, Object?>>> requestsBySeat =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Map<String, Object?>> boardBySeat =
      <String, Map<String, Object?>>{};

  /// KP 的「开战前候选池」与「未公开素材库」（不进事件流，但要进存档）。
  final List<Map<String, Object?>> localActors = <Map<String, Object?>>[];
  final List<Map<String, Object?>> localAssets = <Map<String, Object?>>[];

  /// 待确认队列（owner / all 类操作）。
  final List<Map<String, Object?>> pending = <Map<String, Object?>>[];

  /// 当前回退投票（一次只允许一个；Q6 休眠保留）。
  Map<String, Object?>? rewind;

  /// 本回合每个玩家的 SAN 损失累计 + 回合开始 SAN。
  final Map<String, int> sanLostThisRound = <String, int>{};
  final Map<String, int> roundStartSan = <String, int>{};

  /// 「潜在疯狂」态下的「本回合任意损失即复发」武装开关。
  ///
  /// 语义对齐老 APP `room-model.js:884-887 _fadedArm`：潜在疯狂期间该开关为
  /// true（本回合任意 SAN 损失即复发），回合推进时对**仍处潜在**的座位置
  /// false（disarm），使复发需重新累计 ≥ ceil(maxSAN/5) 或下一次明确损失。
  final Map<String, bool> fadedArm = <String, bool>{};

  /// 本轮「某玩家 + 某武器」已发射次数（连发惩罚骰依据）。
  final Map<String, int> fireUsed = <String, int>{};

  final JsClock now;
  final JsRng rng;
  final RoomRulesPort? rules;
  final RoomMadnessPort? madness;
  final RoomSaveStore? saveStore;
  final int snapshotEvery;
  final int snapshotLimit;

  Map<String, Object?> _cloneMap(Object? v) => cloneRoomMap(v);

  // ==========================================================
  // ★ 唯一写口
  // ==========================================================

  /// 归约一条事件并（可选）入日志。
  ///
  /// `persist: true`  —— `emit` 调用：分配 seq → 归约 → 簿记（私有累计/回合边界/快照）
  /// `persist: false` —— `rollback` 重放：直接用日志里的 `rec.evt`（vis/to/seq 完整）
  ///                     → **同一个** reduce → 不写日志、不拍快照
  ///
  /// ⚠️ `persist` 不出现在任何「怎么归约」的判断里；两条路径喂给 reduce 的
  ///    是完全同构的 `RoomEvent`。这就是 Q1 修正的全部机械内容。
  LogRecord apply(RoomEvent evt, {bool persist = true}) {
    final LogRecord rec;
    if (persist) {
      rec = log.push(evt);
    } else {
      final s = evt.seq;
      if (s == null) {
        throw StateError('apply(persist:false) 需要带 seq 的持久化事件');
      }
      rec = LogRecord(s, evt);
    }
    reduceRoomState(state, rec.evt);
    // ★ P10 第 3 期 B：把 reduce 侧机械闸门产生的告警汇进权威端既有的
    //   `warnings`（与 `emit()` scrub / SEAT 缺收件人告警同一出口）。
    //   重放（persist:false）只清空、不重复记，避免回退一次告警翻倍。
    if (reduceGateWarnings.isNotEmpty) {
      if (persist) warnings.addAll(reduceGateWarnings);
      reduceGateWarnings.clear();
    }
    if (persist) {
      _accumulatePrivate(rec);
      _onRoundBoundary(rec);
      _maybeSnapshot(rec.seq);
    }
    return rec;
  }

  /// SEAT 私密事件按收件人累积（否则重连 /sync 的 privates 恒为空）。
  void _accumulatePrivate(LogRecord rec) {
    final evt = rec.evt;
    if (evt.vis != RoomVis.seat || !jsTruthy(evt.to)) return;
    if (evt.t != RoomEvt.private_) return;
    final to = evt.to!;
    final list = privateBySeat.putIfAbsent(to, () => <Object?>[]);
    list.add(<String, Object?>{
      'seq': rec.seq,
      'title': jsTruthy(evt.p['title']) ? evt.p['title'] : '',
      'text': jsTruthy(evt.p['text']) ? evt.p['text'] : '',
      'at': jsTruthy(evt.p['at']) ? evt.p['at'] : 0,
      'kind': jsTruthy(evt.p['kind']) ? evt.p['kind'] : 'info',
    });
    if (list.length > 100) list.removeAt(0);
  }

  /// 回合边界簿记（由**事件**驱动，而不是命令式赋值）。
  ///
  /// 放在 apply 里（所有状态变更的唯一出口）而不是调用点，
  /// 这样 `nextTurn`（战斗）与「进入下一回合」（探索）两条路径都自动维护。
  void _onRoundBoundary(LogRecord rec) {
    final evt = rec.evt;
    if (evt.t != RoomEvt.round) return;
    final r = evt.p['round'];
    if (r == null) return;
    roundStarts.add(<String, Object?>{'round': r, 'seq': rec.seq});
    fireUsed.clear();
    sanLostThisRound.clear();
    roundStartSan.clear();
    // ⚠️ 不能简单清空：清空后键缺失 = 「武装」，等于回合推进后 FADED 仍然
    //    「任意损失即复发」。对当前仍处于 FADED 的座位显式置 false（disarm）。
    fadedArm.clear();
    for (final mm in roster.list()) {
      final sheet = mm['sheet'];
      final mental =
          sheet is Map ? asList(asMap(sheet)['mental']) : const <Object?>[];
      // ★ P10 第 3 期 A 批修复：这里原先硬编码老取值 `'不定疯狂（症状消失）'`，
      //   于是用户改名成「潜在疯狂」之后，仍处潜在疯狂的座位**永远 disarmed
      //   不了**（fadedArm 键缺失 → 判定为 true）→ 「本回合任意损失即复发」
      //   跨回合一直生效，与老 APP `room-model.js:984-1000` 的回合边界
      //   disarm 行为分叉。改走状态机判据，新旧两个取值一次覆盖。
      if (mental_state.isPotentialMadness(mental)) {
        fadedArm[jsStr(mm['seat'])] = false;
      }
    }
  }

  /// 每 `snapshotEvery` 条存一份深快照（回退用），只留最近 `snapshotLimit` 份。
  ///
  /// ⚠️ F3：第 0 条是构造时拍的**建团空状态**（seq=0），它是唯一能支撑
  ///    「回退到最早事件」的基准，也和 :80 的注释约定一致。旧版
  ///    room-model.js:1025 用 `snapshots.shift()` 无脑裁掉它，快照表打满后
  ///    深回退会拿一条 seq 比 target 还大的快照当基准 → 权威态不退、
  ///    `log.seq` 与 `state.seq` 分叉、快照表被清空、二次回退抛 StateError。
  ///    这里改成「保留首条基线 + 保留最近 snapshotLimit-1 条」：超限只裁
  ///    index 1 起的**非基线**快照，基线永不淘汰。
  void _maybeSnapshot(int seq) {
    if (snapshotEvery <= 0 || seq % snapshotEvery != 0) return;
    snapshots.add(RoomSnapshot(seq, _cloneMap(state)));
    while (snapshots.length > snapshotLimit && snapshots.length > 1) {
      snapshots.removeAt(1);
    }
  }

  // ==========================================================
  // 事件产生
  // ==========================================================

  /// 造一条事件并入库。
  ///
  /// ⚠️ 可见性三闸的第 ① 道：`vis != seat` 时自动 `scrub` 私有字段并记警告 ——
  ///    这是「不许先广播再隐藏」的机械保证（写错代码也漏不出去）。
  LogRecord emit(
    String t,
    Map<String, Object?> p, {
    String vis = RoomVis.public,
    String? to,
  }) {
    final v = jsTruthy(vis) ? vis : RoomVis.public;
    var payload = p;
    if (v != RoomVis.seat && hasSecret(payload)) {
      warnings.add(RoomWarning(t, '非 SEAT 事件携带私有字段，已剥离'));
      payload = asMap(scrub(payload));
    }
    return apply(RoomEvent(t: t, p: payload, vis: v, to: jsTruthy(to) ? to : null));
  }

  /// 只记在 KP 本地、永不外发。**不占共享序号。**
  LogRecord emitLocal(String t, Map<String, Object?> p) {
    localSeq += 1;
    final rec = LogRecord(
      localSeq,
      RoomEvent(t: t, p: p, vis: RoomVis.kp, to: null, seq: localSeq),
    );
    local.add(rec);
    if (local.length > 200) local.removeAt(0);
    return rec;
  }

  /// 系统提示（进公共事件流）。
  LogRecord sys(String text) => emit(
        RoomEvt.log,
        <String, Object?>{'seat': '', 'text': text, 'at': now(), 'kind': 'sys'},
      );

  /// 系统提示只发给一个人（越权提醒等），不污染公共流。
  LogRecord sysTo(String seat, String text) => emit(
        RoomEvt.private_,
        <String, Object?>{
          'title': '提示',
          'text': text,
          'at': now(),
          'kind': 'sys',
        },
        vis: RoomVis.seat,
        to: seat,
      );

  // ==========================================================
  // 分发计划（可见性三闸的第 ② 道）
  // ==========================================================

  static const Set<String> _combatEvts = <String>{
    RoomEvt.combat,
    RoomEvt.actor,
    RoomEvt.turnstate,
    RoomEvt.turn,
  };

  static const Set<String> _memberEvts = <String>{RoomEvt.members};

  /// 把一条事件翻译成「发给谁」的列表。**不碰网络**。
  ///
  /// · `VIS.KP`   → 空列表（根本不出门）
  /// · `VIS.SEAT` → 给 `to` 单发 evt；其余在线者收 `skip` 水位
  /// · PUBLIC     → 战斗类 / 成员表逐人裁剪，其余 `*` 广播
  List<SendPlan> plan(LogRecord rec) {
    final evt = rec.evt;
    final out = <SendPlan>[];
    if (evt.vis == RoomVis.kp) return out;

    if (evt.vis == RoomVis.seat) {
      if (jsTruthy(evt.to)) {
        final to = evt.to!;
        final pp = cropFor(evt.t, evt.p, to);
        out.add(SendPlan(to, EvtEnvelope(rec.seq, evt.t, _cloneMap(pp))));
      } else {
        // 没有收件人的 SEAT 事件是写错了 —— 悄悄丢掉最难查，记一条警告
        warnings.add(RoomWarning(evt.t, 'SEAT 事件缺少收件人 seat'));
      }
      for (final m in roster.list()) {
        final s = jsStr(m['seat']);
        if (s != evt.to && jsTruthy(m['online'])) {
          out.add(SendPlan(s, SkipEnvelope(rec.seq)));
        }
      }
      return out;
    }

    // 成员表：只有「确实有人挂了 sheet」时才逐人单发
    if (_memberEvts.contains(evt.t) &&
        _membersNeedCrop(asList(evt.p['members']))) {
      var any = false;
      for (final m in roster.list()) {
        final s = jsStr(m['seat']);
        if (!jsTruthy(m['online']) || s == kHostSeat) continue;
        any = true;
        out.add(SendPlan(
          s,
          EvtEnvelope(rec.seq, evt.t, cropFor(evt.t, evt.p, s)),
        ));
      }
      if (any) return out;
      // 没有在线玩家：退回「陌生人视角」的群发（**不能**直接 evtMsg(rec)，
      // 否则原始对象会进日志/回放）
      out.add(SendPlan(
        '*',
        EvtEnvelope(rec.seq, evt.t, cropFor(evt.t, evt.p, '__nobody__')),
      ));
      return out;
    }

    if (_combatEvts.contains(evt.t)) {
      for (final m in roster.list()) {
        final s = jsStr(m['seat']);
        if (!jsTruthy(m['online']) || s == kHostSeat) continue;
        out.add(SendPlan(
          s,
          EvtEnvelope(rec.seq, evt.t, cropFor(evt.t, evt.p, s)),
        ));
      }
      return out;
    }

    out.add(SendPlan('*', EvtEnvelope(rec.seq, evt.t, _cloneMap(evt.p))));
    return out;
  }

  /// 逐条事件的完整发送计划（顺序必须与 seq 一致，否则玩家端会判成乱序）。
  List<SendPlan> planAll(List<LogRecord> recs) {
    final out = <SendPlan>[];
    for (final rec in recs) {
      out.addAll(plan(rec));
    }
    return out;
  }

  /// 把一条事件的分发结果追加进 [out]（调用方已持有计划数组时用）。
  List<SendPlan> pushInto(List<SendPlan> out, LogRecord rec) {
    out.addAll(plan(rec));
    return out;
  }

  /// 按收件人裁剪一条事件的载荷。**syncFor 与增量共用同一套规则**。
  Map<String, Object?> cropFor(
    String t,
    Map<String, Object?> p,
    String seat,
  ) {
    if (_memberEvts.contains(t) && p['members'] != null) {
      final out = _cloneMap(p);
      out['members'] = _cropMembers(asList(p['members']), seat);
      return out;
    }
    if (!_combatEvts.contains(t)) return p;
    if (seat == kHostSeat) return p;
    final out = _cloneMap(p);
    if (t == RoomEvt.combat && out['combat'] is Map) {
      out['combat'] = _cropCombat(out['combat']);
    }
    if (t == RoomEvt.actor && out['actor'] is Map) {
      // ★ PL-1b（任务 A）：单条 actor 事件也按同口径隐藏未公开怪，
      //   保持「增量收到的」与「全量同步拿到的」是同一套可见性。
      final actor = asMap(out['actor']);
      final hidden = actor.containsKey('visibleToPlayers') &&
          !jsTruthy(actor['visibleToPlayers']) &&
          jsStr(actor['kind']) != 'pc';
      out['actor'] = hidden ? null : _cropSlot(out['actor']);
    }
    if ((t == RoomEvt.turnstate || t == RoomEvt.turn) && out['order'] is List) {
      // ★ P14 COMBAT-4：真实回合事件（载荷带 `turn`）一律**不再**按可见性
      //   过滤槽位 —— `turn` 是 `combat.order` 的**下标**，过滤会让下标与数组
      //   错位（玩家侧当前行动者错位 / `turn` 越界 → 「所有操作卡住」）。
      //   只有不带 `turn` 的最小载荷（老存档 / 手工构造）才沿用 P13 的过滤。
      out['order'] = _cropOrderForPlayer(out['order'],
          dropHidden: !_combatStarted(out));
    }

    return out;
  }

  /// 成员的对外视图：本人 / KP 全量；其他玩家只留公开部分。
  Map<String, Object?> _cropMember(Map<String, Object?> m, String self) {
    final out = _cloneMap(m);
    final sheet = out['sheet'];
    if (sheet is! Map) return out;
    final isKp = self == kHostSeat;
    final isSelf = self == out['seat'];
    if (isKp || isSelf) return out;

    final sh = asMap(sheet);
    final st = asMap(sh['status']);
    // ⚠️ 复刻 JS 的「undefined 键被 JSON.stringify 丢掉」语义（旧版 :1062-1092）：
    //    旧版写 `name: sh.name` / `currentHP: st.currentHP` 时，
    //      · 源对象**没有**该键 → 取到 undefined → 序列化后不出现在 JSON 里；
    //      · 源对象**有**该键且值为 null（如 sanitizeSheet 生成的完整卡）
    //        → 取到 null → 序列化后保留 `key: null`。
    //    Dart 里两者都读成 null，故必须用 containsKey 区分，不能按值判空：
    //    只看 `!= null` 会把完整卡里的显式 null 键误删。
    out['sheet'] = <String, Object?>{
      if (sh.containsKey('name')) 'name': sh['name'],
      // 头像对同席公开（桌上本来就看得到人）；症状名 / SAN 减损仍不外传
      'avatar': jsTruthy(sh['avatar']) ? sh['avatar'] : '',
      'status': <String, Object?>{
        if (st.containsKey('currentHP')) 'currentHP': st['currentHP'],
        if (st.containsKey('maxHP')) 'maxHP': st['maxHP'],
        if (st.containsKey('currentSAN')) 'currentSAN': st['currentSAN'],
        if (st.containsKey('currentMP')) 'currentMP': st['currentMP'],
        if (st.containsKey('maxMP')) 'maxMP': st['maxMP'],
        'body': jsTruthy(st['body']) ? st['body'] : '正常',
        'dying': jsTruthy(st['dying']),
        'unconscious': jsTruthy(st['unconscious']),
      },
      'mental': asList(sh['mental']).take(6).toList(),
      'madnessCount': asList(sh['madness']).length,
      // 上限可能暴露神话侵蚀程度；减损值是个人状况 —— 都不下发
      'sanLoss': null,
      'maxSAN': null,
    };
    return out;
  }

  bool _membersNeedCrop(List<Object?> members) =>
      members.any((m) => m is Map && jsTruthy(asMap(m)['sheet']));

  List<Object?> _cropMembers(List<Object?> members, String self) =>
      members.map((m) => _cropMember(asMap(m), self)).toList();

  /// 战斗槽位的玩家视图：怪物默认不公开 HP，KP 隐藏字段一律删掉。
  Map<String, Object?>? _cropSlot(Object? slotRaw) {
    if (slotRaw is! Map) return null;
    final slot = _cloneMap(slotRaw);
    if (slot['public'] is! Map) slot['public'] = <String, Object?>{};
    final pub = asMap(slot['public']);
    if (!jsTruthy(pub['hpPublic'])) {
      pub.remove('hp');
      pub.remove('hpMax');
    }
    slot.remove('secret');
    slot.remove('kpOnly');
    slot.remove('attrs');
    return slot;
  }

  /// 槽列表裁剪，**只剥属性、不删槽**（P14 COMBAT-4）。
  ///
  /// ★ 为什么不再过滤 `visibleToPlayers`：`combat.turn` 是 `combat.order` 的
  ///   **下标**（`combatStart` 写 0、`nextTurn` 写 `turn + 1`）。P13 在这里
  ///   删掉显式隐藏的怪物槽后，数组变短而下标仍是权威端的值 —— 玩家侧
  ///   `combatRows` 的 `isCurrent` / `curSlot` 全部错位，`turn` 越界时被
  ///   clamp 到末位，于是「该我行动」判成「不是我的回合」，玩家攻击按钮永久
  ///   置灰 = 用户报的「所有操作卡住」。
  /// ★ 语义依据（用户原话）：「进入战斗了玩家一定能看到」—— 参战即公开，
  ///   未参战的隐藏怪仍由 `visibleToPlayers` 控制（`makeSync.actors` 口径）。
  /// ★ 隐私不放松：`_cropSlot` 仍然删 `secret` / `kpOnly` / `attrs`，并在
  ///   `hpPublic != true` 时删 `public.hp` / `public.hpMax`；名字以外的属性
  ///   一个都不下发。
  ///
  /// [dropHidden] 为 true 时保留 P13 老口径（只给**未开打**的最小战斗包 /
  /// 老存档用：这类载荷没有 `turn`，不存在下标错位问题）。
  List<Object?> _cropOrderForPlayer(Object? orderRaw, {bool dropHidden = true}) {
    final out = <Object?>[];
    for (final slotRaw in asList(orderRaw)) {
      if (dropHidden && slotRaw is Map) {
        final slot = asMap(slotRaw);
        final hidden = slot.containsKey('visibleToPlayers') &&
            !jsTruthy(slot['visibleToPlayers']) &&
            jsStr(slot['kind']) != 'pc';
        if (hidden) continue;
      }
      out.add(_cropSlot(slotRaw) ?? slotRaw);
    }
    return out;
  }

  /// 该 `combat` 包是否「已经开打」。
  ///
  /// `combatStart` 写 `turn/round/startedAt` 三键，`combatEnqueue` / `nextTurn`
  /// 必带 `turn`；只有老存档 / 手工构造的最小包是裸 `{'order': [...]}`
  /// （P13 的 `combatFor` 用例正是这种形状）。
  bool _combatStarted(Object? combatRaw) {
    if (combatRaw is! Map) return false;
    return combatRaw.containsKey('turn') ||
        combatRaw.containsKey('round') ||
        combatRaw.containsKey('startedAt');
  }

  Map<String, Object?>? _cropCombat(Object? cRaw) {
    if (cRaw is! Map) return null;
    final out = _cloneMap(cRaw);
    if (out['order'] is List) {
      out['order'] = _cropOrderForPlayer(out['order'],
          dropHidden: !_combatStarted(out));
    }
    return out;
  }

  /// 给某个 seat 的战斗视图（剥掉敏感属性；KP 拿全量）。
  ///
  /// 槽**列表**在开打后一律全量（参战即公开，见下方 P14 COMBAT-4），
  /// 未开打的骨架包才沿用 P13 的 `visibleToPlayers` 过滤。
  Map<String, Object?>? combatFor(String seat) {
    final c = state['combat'];
    if (c is! Map) return null;
    final out = _cloneMap(c);
    if (seat == kHostSeat) return out;
    final order = out['order'];
    if (order is List) {
      for (final slotRaw in order) {
        if (slotRaw is! Map) continue;
        final pub = slotRaw['public'] is Map
            ? asMap(slotRaw['public'])
            : <String, Object?>{};
        slotRaw['public'] = pub;
        if (!jsTruthy(pub['hpPublic'])) {
          pub.remove('hp');
          pub.remove('hpMax');
        }
        slotRaw.remove('secret');
        slotRaw.remove('kpOnly');
        slotRaw.remove('attrs');
      }
    }
    // ★ P14 COMBAT-4（用户问题 6 / 7）：**开打之后不再按 `visibleToPlayers`
    //   过滤战斗槽**。
    //   · 用户口径：「进入战斗了玩家一定能看到全部参战怪物，哪怕 KP 加怪时
    //     选了不显示」；
    //   · 技术口径：`turn` 是 order 下标，过滤必然错位（P13 引入，见
    //     `_cropOrderForPlayer` 注释）→ 玩家侧当前行动者错位 / 所有操作被
    //     `isMyTurn` 永久判假 = 「玩家侧所有操作卡住」。
    //   属性裁剪一个都不放松：`_cropSlot` 已在上面的循环里删掉
    //   `secret` / `kpOnly` / `attrs` 与未公开的 `public.hp / public.hpMax`。
    //   只有「未开打的最小战斗包」（无 turn/round/startedAt，老存档 / 单测
    //   手工构造）才保留 P13 的过滤，保证既有断言零漂移。
    final orderRaw = out['order'];
    if (orderRaw is List && !_combatStarted(out)) {
      final kept = <Object?>[];
      var filtered = false;
      for (final slotRaw in orderRaw) {
        final slot = asMap(slotRaw);
        final hidden = slot.containsKey('visibleToPlayers') &&
            !jsTruthy(slot['visibleToPlayers']) &&
            jsStr(slot['kind']) != 'pc';
        if (hidden) {
          filtered = true;
          continue;
        }
        kept.add(slotRaw);
      }
      if (filtered) out['order'] = kept;
    }
    return out;
  }

  /// 首连 / 重连：给某个 seat 的全量同步。
  ///
  /// ⚠️ 可见性裁剪发生在**事件产生时**（plan / emit），这里不再二次过滤 ——
  ///    否则「增量收到的」与「全量同步拿到的」会不是同一套，同一句话忽隐忽现。
  SyncEnvelope syncFor(String seat) =>
      makeSync(seat, roomClone(state['scene']));

  /// 组装全量同步信封。`scene` / `board` 不传时按 state 里的当前值兜底。
  SyncEnvelope makeSync(
    String seat, [
    Object? scene = _kUndef,
    Object? board = _kUndef,
  ]) {
    final st = state;
    final branch = (board != _kUndef && jsTruthy(board))
        ? board
        : boardBySeat[seat];
    final view = <String, Object?>{
      'meta': roomClone(st['meta']),
      // 成员表按收件人裁剪 —— 与增量 MEMBERS 必须用同一套规则
      'members': _cropMembers(members(), seat),
      'chats': roomClone(st['chats']),
      'logs': roomClone(st['logs']),
      'dice': roomClone(st['dice']),
      'scene': scene == _kUndef ? roomClone(st['scene']) : scene,
      'combat': combatFor(seat),
      'privates': privateBySeat[seat] != null
          ? roomClone(privateBySeat[seat])
          : <Object?>[],
      'rewind': roomClone(st['rewind']),
      'requests': _requestsView(seat),
      'board': jsTruthy(branch) ? roomClone(boardBySeat[seat]) : null,
      'seq': log.seq,
      'version': 1,
    };
    // ★ PL-1b：仅非 KP 的玩家同步视图下发裁剪后的 actors；KP 保持既有
    //   13 键全量视图逐字不变。只有本期数据（记录带 `visibleToPlayers`）
    //   才加键 —— 老存档 / oracle 形态不加，既有 13 键 view 零漂移。
    if (seat != kHostSeat) {
      final List<Object?>? visible = _visibleActorsView();
      if (visible != null) view['actors'] = visible;
    }
    return syncMsg(log.seq, view);
  }

  /// 收集权威端全部怪物 / NPC 记录（三个来源，按 id 去重）。
  ///
  /// 来源：`state['actors']`（同步态候选池）/ [localActors]（开战前候选池）
  /// / `combat.order`（战斗槽，用 `actorId` 归一去掉 `#N` 后缀）。
  /// 纯读取，**绝不改动 [state]**；PC 记录一律排除。
  List<Map<String, Object?>> _actorRecords() {
    final records = <Map<String, Object?>>[];
    final seen = <String>{};
    void add(Object? raw) {
      final rec = asMap(raw);
      if (jsStr(rec['kind']) == 'pc') return;
      final id = jsStr(rec['actorId']).isNotEmpty
          ? jsStr(rec['actorId'])
          : jsStr(rec['id']);
      if (id.isEmpty || !seen.add(id)) return;
      records.add(<String, Object?>{...rec, 'id': id});
    }

    for (final raw in asList(state['actors'])) {
      add(raw);
    }
    for (final raw in localActors) {
      add(raw);
    }
    for (final raw in asList(asMap(state['combat'])['order'])) {
      add(raw);
    }
    return records;
  }

  /// 玩家同步视图的 `actors` 键内容；返回 null = 不加键。
  ///
  /// ★ 只有任一记录**显式带** `visibleToPlayers`（本期新增字段）时才返回
  ///   列表：老存档 / oracle 形态返回 null → makeSync 视图形状逐字节不变。
  /// ★ 每条**仅 id + name**：hp / hpMax / dex / skill / value / armor /
  ///   attrs / secret / kpOnly 一律不下发（R7）。
  /// ★ 收录条件（P14 COMBAT-4）：
  ///   ① `visibleToPlayers == true`（未参战也能被 KP 公开，P12 语义不变）；
  ///   ② **已经在开打中的 `combat.order` 里**的槽 —— 参战即公开，哪怕加怪时
  ///      勾了「不显示」。否则玩家在对抗/攻击目标列表里选不到这只怪
  ///      （用户问题 6）。注意这里只放行「参战」这一个条件，属性照样不下发。
  List<Object?>? _visibleActorsView() {
    final records = _actorRecords();
    final bool hasMarker =
        records.any((Map<String, Object?> r) => r.containsKey('visibleToPlayers'));
    if (!hasMarker) return null;
    // 开打中：把 combat.order 里出现的单位（含 `#n` 多行动后缀的 base id）
    // 全部视为公开参战者。
    final Set<String> inCombat = <String>{};
    final Map<String, Object?> combat = asMap(state['combat']);
    if (_combatStarted(combat)) {
      for (final Object? raw in asList(combat['order'])) {
        final Map<String, Object?> slot = asMap(raw);
        for (final String key in const <String>['id', 'actorId']) {
          final String v = jsStr(slot[key]);
          if (v.isEmpty) continue;
          inCombat.add(v);
          final int hash = v.indexOf('#');
          if (hash > 0) inCombat.add(v.substring(0, hash));
        }
      }
    }
    final out = <Object?>[];
    for (final Map<String, Object?> rec in records) {
      final String id = jsStr(rec['id']);
      final int hash = id.indexOf('#');
      final bool joined = inCombat.contains(id) ||
          (hash > 0 && inCombat.contains(id.substring(0, hash)));
      if (!jsTruthy(rec['visibleToPlayers']) && !joined) continue;
      out.add(<String, Object?>{
        'id': id,
        'name': jsStr(rec['name']),
      });
    }
    return out;
  }

  /// 全量同步里的 requests 形状必须与实时 reduce **完全一致**（键名 `p`，不是 `payload`）。
  List<Object?> _requestsView(String seat) {
    final list = requestsBySeat[seat];
    if (list == null) return <Object?>[];
    return list.map((r) => <String, Object?>{
          'id': r['id'],
          'op': r['op'],
          'p': roomClone(r['payload'] ?? const <String, Object?>{}),
          'from': jsTruthy(r['from']) ? r['from'] : 'KP',
          'reason': jsTruthy(r['reason']) ? r['reason'] : '',
          'at': jsTruthy(r['at']) ? r['at'] : 0,
        }).toList();
  }

  // ==========================================================
  // 花名册桥接
  // ==========================================================

  List<Map<String, Object?>> members() => roster.dump();

  /// 把成员表变更推给所有人。
  List<SendPlan> syncMembers() =>
      plan(emit(RoomEvt.members, <String, Object?>{'members': members()}));

  /// 中继报告有人上线。
  ///
  /// `blocked=true` 表示这个 seat 被踢过，调用方应直接断开他的连接。
  AttachPeerResult attachPeer(Map<String, Object?>? mRaw) {
    final m0 = mRaw ?? const <String, Object?>{};
    // ★ P16 P-1(a) 按 cid 幂等兜底：系统返回键未走 closeConnection 时同一
    //   设备重连，旧座可能仍 online=true；若调用方给的 seat 是空的 / 另一个
    //   新座，就把 seat 归一到该 cid 已绑定的旧座复用，避免新增第二个成员。
    //   ⚠️ 不推翻 RoomRoster 的 seat 键语义、不改 syncMembers 广播口径：
    //     这里只归一入参，去重 / 上线仍由 roster.open(seat) 完成。
    final cid = jsStr(m0['cid']);
    var m = m0;
    if (cid.isNotEmpty) {
      final requested = jsStr(m0['seat']);
      String? bound;
      for (final s in roster.order) {
        final mem = roster.bySeat[s];
        if (mem != null && jsStr(mem['cid']) == cid) {
          bound = s;
          break;
        }
      }
      if (bound != null && bound.isNotEmpty && bound != requested) {
        m = <String, Object?>{...m0, 'seat': bound};
      }
    }
    final seatRaw = jsTruthy(m['seat']) ? m['seat'] : m['cid'];
    if (!jsTruthy(seatRaw)) {
      return const AttachPeerResult(seat: '', rejected: true, blocked: false);
    }
    final seat = jsStr(seatRaw);
    if (roster.kicked.contains(seat)) {
      return AttachPeerResult(seat: seat, rejected: true, blocked: true);
    }
    // ⚠️ 必须在 open() **之前**取旧值：open() 会原地把 online 改成 true
    final prev = roster.get(seat);
    final existed = prev != null;
    final wasOffline = prev != null && prev['online'] == false;
    final member = roster.open(m);
    final out = <SendPlan>[];
    if (!existed || wasOffline) out.addAll(syncMembers());
    // 无论新老，都给这个座位推一份全量（他靠这条把自己的界面填满）
    out.add(SendPlan(seat, syncFor(seat)));
    return AttachPeerResult(
      seat: seat,
      rejected: false,
      blocked: false,
      member: member,
      out: out,
    );
  }

  /// 中继报告有人掉线：**只标记离线，不移除**（他还要重连回来）。
  ///
  /// 旧版 :3316-3320 在这里还会 `rollbackAbortIfVoting(seat)`：需求 §9
  /// 「回退表决期间有人掉线 → 该次表决作废」。否则表决会一直挂着等一个
  /// 已经不在的人。`rollbackAbortIfVoting` 在 [room_model_rollback.dart] 已
  /// 实现齐全（不在表决中 / 不在 `need` 名单里都返回空表），这里只是接线。
  /// 顺序：先 `markOffline`（副作用）→ 再中止表决（改 `state['rewind']`）
  /// → 最后广播成员表，保证成员表广播带的是已作废的 rewind。
  List<SendPlan> detachPeer(String seat) {
    final m = roster.markOffline(seat);
    if (m == null) return <SendPlan>[];
    final out = <SendPlan>[];
    out.addAll(rollbackAbortIfVoting(seat));
    out.addAll(syncMembers());
    return out;
  }
}
