// ============================================================
// room_model_client.dart — 玩家端确定性回放 `RoomClient`（D20，T04 · S4.1）
//
// 计划内容（见 _p4_design.md §2.1 D20 / §0.3）：
//   receive / gate（evt 与 skip **共用**）/ filledMark / resyncIntent / resyncDiag /
//   applySheetState / intent / member / isReady / onChange
//
// ⚠️ §0.3：`receive()` 返回体里**没有** `gapFrom` 字段（用的是 `from`）；
//    `gapFrom` 是内部字段，返回体严禁凭空加键（会触发键集合不一致）。
// ⚠️ `reduceRoomState(` 在本文件**只能出现 1 次**（在 receive 里，客户端传
//    `vis:null` 复刻旧版「undefined → PUBLIC」，Q1 设计 §1.4）。
//    全库两个调用点：RoomHost.apply / RoomClient.receive。
// ============================================================

import 'js_compat.dart';
import 'room_model_envelope.dart';
import 'room_model_reduce.dart';
import 'room_model_state.dart';
import 'room_ports.dart';
import 'room_types.dart';

void _noopOnChange(Map<String, Object?> state) {}

/// 玩家 / 旁观者端：把权威端下发的事件**按序号**重放进自己的状态副本。
///
/// 为什么必须有序号闸门：WebSocket 重连补拉必然出现重复与乱序；没有闸门，
/// 重放一次聊天就变成两条。`skip` 与 `evt` 必须共用同一套闸门，否则会出现
/// 「skip 跳号被放过、evt 跳号被拦住」这种只有一半正确的状态机。
class RoomClient {
  RoomClient({
    required this.seat,
    this.role = RoomRole.player,
    Map<String, Object?>? meta,
    JsClock? now,
    void Function(Map<String, Object?>)? onChange,
  })  : state = emptyRoomState(meta),
        now = now ?? nowClock,
        onChange = onChange ?? _noopOnChange;

  final String seat;
  final String role;

  /// `sync` 时会整体替换，故非 final。
  Map<String, Object?> state;

  final JsClock now;
  final void Function(Map<String, Object?>) onChange;

  /// 已应用的最后一个全局序号。
  int lastSeq = 0;

  /// >0 表示检测到丢包、需要补拉（**内部字段**，不进 receive 返回体）。
  int gapFrom = 0;

  /// 补拉可观测性：本次补拉的起点序号 / 累计次数。
  int resyncFromSeq = 0;
  int resyncCount = 0;

  /// 被丢弃的重复/过期事件数（诊断用）。
  int rejected = 0;

  /// 角色卡状态写回的独立单调序号（幂等用）。
  int lastStateSeq = 0;

  /// 最近一次应用到本机的角色卡状态（供界面显示 / 断线后重放）。
  Map<String, Object?>? sheetState;

  /// 需要用户确认的改状态请求（KP 要求改我，我要点同意）。
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  // ----------------------------------------------------------
  // 接收
  // ----------------------------------------------------------

  /// 收到中继传来的原始消息（字符串或已解析对象）。
  ///
  /// 返回体有 6 种不同键集合，全部由 [ReceiveResult] 的具名工厂收口：
  ///   ignore / sync / skip-ok / evt-ok / skip-rejected / evt-rejected。
  /// ⚠️ 拒绝分支用 `from`（值 = lastSeq），**不加** `gapFrom` 键（§0.3）。
  ReceiveResult receive(Object? raw) {
    final m = parseRoomRaw(raw);
    if (m == null) return ReceiveResult.ignore();
    if (m['k'] == 'intent') return ReceiveResult.ignore();

    if (m['k'] == 'sync') {
      final st = asMap(m['state']);
      // 旧版 `emptyState(st.meta)`：meta 缺失（undefined）与 meta={} 的
      // allowSpectate 默认值不同，必须区分 null 与空 Map。
      final meta = st['meta'] is Map ? asMap(st['meta']) : null;
      final next = emptyRoomState(meta);
      for (final e in st.entries) {
        next[e.key] = roomClone(e.value);
      }
      state = next;
      lastSeq = jsNum(m['seq']);
      state['seq'] = lastSeq;
      gapFrom = 0;
      onChange(state);
      return ReceiveResult.sync(lastSeq);
    }

    final seq = jsNum(m['seq']);

    // 水位标记：不改变状态，只把 lastSeq 推上去。
    if (m['k'] == 'skip') {
      final prevGap = gapFrom;
      final g = gate(seq);
      if (!g.ok) {
        return ReceiveResult.rejected('skip', g.dup, g.gap, lastSeq, seq);
      }
      return ReceiveResult.skipOk(seq, filledMark(prevGap));
    }

    // 增量事件。⚠️ 全库第 2 个也是最后一个 reduce 调用点：
    //    客户端没有权威端的可见性信息，传 vis:null 复刻旧版
    //    `reduce(state, {t, seq, p})` 的「undefined → PUBLIC」口径（§1.4）。
    final prevGap = gapFrom;
    final g = gate(seq);
    if (!g.ok) {
      return ReceiveResult.rejected('evt', g.dup, g.gap, lastSeq, seq);
    }
    final t = jsStr(m['t']);
    reduceRoomState(
      state,
      RoomEvent(t: t, seq: seq, p: asMap(m['p']), vis: null),
    );
    onChange(state);
    return ReceiveResult.evtOk(seq, t, filledMark(prevGap));
  }

  /// 序号闸门：重复直接丢、跳跃报缺口、连续才放行。
  /// [skip] 与 [evt] 必须共用这一套判据。
  GateResult gate(int seq) {
    if (seq <= lastSeq) {
      rejected += 1;
      return GateResult(ok: false, dup: true, lastSeq: lastSeq);
    }
    if (seq != lastSeq + 1) {
      gapFrom = lastSeq;
      return GateResult(ok: false, gap: true, lastSeq: lastSeq);
    }
    lastSeq = seq;
    // 收到连续序号 = 缺口补上了，必须清标记；漏了界面会永远挂着「正在补齐」。
    gapFrom = 0;
    return GateResult(ok: true, lastSeq: lastSeq);
  }

  /// 本次通过闸门是否意味着「之前的缺口补上了」。
  /// [prev] 是进入 [gate] **之前**的 gapFrom。
  bool filledMark(int prev) {
    if (prev == 0) return false;
    return lastSeq > prev;
  }

  // ----------------------------------------------------------
  // 补拉 / 回执
  // ----------------------------------------------------------

  /// 生成补拉意图（带 lastSeq；起点 = gapFrom 或 lastSeq）。
  IntentEnvelope resyncIntent() {
    resyncFromSeq = gapFrom != 0 ? gapFrom : lastSeq;
    resyncCount += 1;
    return intentMsg(
      RoomIntent.sync,
      <String, Object?>{'lastSeq': resyncFromSeq},
    );
  }

  /// 补拉进度诊断 `{from, last, filled, holes, count}`。
  ResyncDiag resyncDiag() => ResyncDiag(
        from: resyncFromSeq,
        last: lastSeq,
        filled: lastSeq - resyncFromSeq < 0 ? 0 : lastSeq - resyncFromSeq,
        holes: gapFrom != 0 ? 1 : 0,
        count: resyncCount,
      );

  /// 玩家 → KP 的意图信封（本端只造信封，不发包）。
  IntentEnvelope intent(String op, Map<String, Object?> p) => intentMsg(op, p);

  /// 把权威端写回的角色卡状态应用到本机（**幂等**：同一 seq 只生效一次）。
  ApplySheetResult applySheetState(Object? seq, Map<String, Object?>? patch) {
    final s = jsNum(seq);
    if (s <= 0) return ApplySheetResult(false, s);
    if (s <= lastStateSeq) return ApplySheetResult(false, s, true);
    lastStateSeq = s;
    sheetState = patch == null ? null : asMap(roomClone(patch));
    return ApplySheetResult(true, s);
  }

  // ----------------------------------------------------------
  // 读视图
  // ----------------------------------------------------------

  Map<String, Object?>? member([String? seat]) {
    final target = seat ?? this.seat;
    for (final m in asList(state['members'])) {
      if (m is Map && '${m['seat']}' == target) return asMap(m);
    }
    return null;
  }

  bool isReady() {
    final m = member();
    return m != null && jsTruthy(m['ready']);
  }
}
