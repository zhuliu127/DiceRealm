// ============================================================
// room_model_log.dart — 事件日志 `RoomLog` 与花名册 `RoomRoster`（D12）
//
// 为什么必须有全局序号：WebSocket 断了会重连，补拉时一定会出现重复与乱序；
// 没有序号就只能「收到就应用」，重放一次聊天就变成两条。
//
// ⚠️ Q1 第一环：`push()` 返回的记录必须挂**完整事件对象**（含 vis/to/seq），
//    回退重放才能拿到可见性 —— 旧版 :3450 只传 {t,seq,p} 正是缺陷根源。
// ============================================================

import 'js_compat.dart';
import 'room_model_state.dart';
import 'room_types.dart';

/// 事件日志：序号分配 + 补拉窗口 + 回退裁剪。
class RoomLog {
  RoomLog({int cap = 400}) : cap = cap > 0 ? cap : 400;

  /// 保留窗口（超出后丢最旧的，并累计 [truncated]）
  final int cap;
  int seq = 0;

  /// 被丢弃的条数（补拉时据此判断「补不全了」）
  int truncated = 0;

  final List<LogRecord> items = <LogRecord>[];

  /// 追加一条事件：`++seq` → `evt.withSeq(seq)` → 超限 shift。
  ///
  /// [wire] 是旧版 `Log.push(evt)` **原样保存的入参对象**（对外形状，键集合 =
  /// 入参键集合）。`RoomHost.emit` 走内部事件对象，不传（由 `LogRecord` 推导成
  /// 四键 `{t,vis,to,p}`）；直接调用 `RoomLog.push` 的调用方按入参形状传入，
  /// 以便 `push` 返回值与 `since()` 结果逐字段复刻旧版（见 `LogRecord.toWireJson`）。
  ///
  /// ⚠️ 内部 [RoomEvent] 仍完整持久化 `vis/to/seq`（Q1 重放依赖），
  ///    [wire] 只影响**对外序列化**，绝不参与归约判定。
  LogRecord push(RoomEvent evt, {Map<String, Object?>? wire}) {
    seq += 1;
    final rec = LogRecord(seq, evt.withSeq(seq), wire);
    items.add(rec);
    while (items.length > cap) {
      items.removeAt(0);
      truncated += 1;
    }
    return rec;
  }

  /// `fromSeq` 之后的全部记录（升序）。
  List<LogRecord> since(int fromSeq) =>
      items.where((r) => r.seq > fromSeq).toList();

  /// 能否用增量补齐（false 表示必须发全量 sync）。
  bool canFill(int fromSeq) {
    if (fromSeq >= seq) return true;
    if (items.isEmpty) return false;
    return items.first.seq <= fromSeq + 1;
  }

  /// 回退到 `beforeSeq`：**丢弃事件本身**，返回被丢弃条数。
  ///
  /// 状态由调用方用「重放到 beforeSeq-1 的快照」替换 —— 只删界面文字不算回退。
  int rollbackBefore(int beforeSeq) {
    final kept = items.where((r) => r.seq < beforeSeq).toList();
    final dropped = items.length - kept.length;
    items
      ..clear()
      ..addAll(kept);
    seq = beforeSeq - 1;
    return dropped;
  }
}

/// 花名册：只记玩家/旁观者，**房主不在里面**（见 [kHostSeat]）。
class RoomRoster {
  /// seat → member（LinkedHashMap，顺序由 [order] 单独维护）
  final Map<String, Map<String, Object?>> bySeat =
      <String, Map<String, Object?>>{};

  /// 稳定顺序（= 入座顺序，界面就按它排）
  final List<String> order = <String>[];

  /// 被踢过的 seat。⚠️ 不记住就变成「踢了立刻又回来」，房主会觉得踢不掉。
  final Set<String> kicked = <String>{};

  /// 有人上线。`rejoin` 语义（断线期间他就在）由调用方保证不清 ready。
  Map<String, Object?>? open(Map<String, Object?>? mRaw) {
    final m = mRaw ?? const <String, Object?>{};
    final seatRaw = jsTruthy(m['seat']) ? m['seat'] : m['cid'];
    if (!jsTruthy(seatRaw)) return null;
    final seat = jsStr(seatRaw);

    final old = bySeat[seat];
    final mem = old ??
        <String, Object?>{
          'seat': seat,
          'role': jsTruthy(m['role']) ? m['role'] : RoomRole.player,
          'nickname': jsTruthy(m['nickname']) ? m['nickname'] : '',
          'online': true,
          'ready': false,
          'charId': null,
          'charName': '',
          'spec': false,
          'joinedAt': 0,
        };
    mem['cid'] = jsTruthy(m['cid']) ? m['cid'] : (mem['cid'] ?? '');
    mem['online'] = true;
    if (jsTruthy(m['nickname'])) mem['nickname'] = m['nickname'];
    if (jsTruthy(m['role'])) mem['role'] = m['role'];
    mem['spec'] = mem['role'] == RoomRole.spectator;
    if (old == null) {
      mem['joinedAt'] = jsTruthy(m['at']) ? m['at'] : 0;
      bySeat[seat] = mem;
      order.add(seat);
    }
    return mem;
  }

  /// 连接断了：**不移除成员**，只标记离线（要能重连回来）。
  Map<String, Object?>? markOffline(String seat) {
    final m = bySeat[seat];
    if (m != null) m['online'] = false;
    return m;
  }

  /// 真的移出（踢人 / 主动离开）。
  Map<String, Object?>? remove(String seat) {
    final m = bySeat.remove(seat);
    if (m == null) return null;
    order.remove(seat);
    kicked.add(seat);
    return m;
  }

  /// 取成员。⚠️ `'host'` 恒为 null —— **禁止**据此判旁观者。
  Map<String, Object?>? get(String seat) => bySeat[seat];

  List<Map<String, Object?>> list() => <Map<String, Object?>>[
        for (final s in order)
          if (bySeat[s] != null) bySeat[s]!,
      ];

  List<Map<String, Object?>> players() =>
      list().where((m) => m['role'] == RoomRole.player).toList();

  List<Map<String, Object?>> spectators() =>
      list().where((m) => m['role'] == RoomRole.spectator).toList();

  List<Map<String, Object?>> onlinePlayers() =>
      players().where((m) => jsTruthy(m['online'])).toList();

  /// 在线玩家是否全部准备好。没人 → false（旧版口径）。
  bool allReady() {
    final ps = onlinePlayers();
    if (ps.isEmpty) return false;
    return ps.every((m) => jsTruthy(m['ready']));
  }

  /// 给客户端用的快照（不含任何隐藏信息）。
  List<Map<String, Object?>> dump() => list()
      .map((m) => (roomClone(m)! as Map).cast<String, Object?>())
      .toList();
}
