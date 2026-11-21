// ============================================================
// room_model_envelope.dart — 4 类应用层信封与解析（D13）
//
// 两层协议别混（K8）：中继层（hub.* / peer.*）不认识应用层字段；
// 应用层只有 4 个 `k`：`sync` / `evt` / `skip` / `intent`。
//
// `parseRoom` 只放行这 4 类；非法 JSON / 非对象 / 未知 k（例如中继自己的
// `host.gone`）一律返回 null —— 「不认识就当没收到」，绝不猜。
//
// ★ 出站形状收口（Q1 修正的边界）：
//   · 内部事件对象 `RoomEvent`（t/seq/p/vis/to）只在 apply / rollback 重放 /
//     reduce 里用，旧版 :961 把 vis/to 写进 log.items，Dart 必须保留它们；
//   · 但对外的「增量 evt」只取 t/p，键集合恒为 `{k:'evt',seq,t,p}`
//     （旧版 :795 `evtMsg` 同样只取 `t`/`p`），**绝不带 vis/to**；
//   · 日志记录的对外形状 `{seq,evt}` 由 `LogRecord.toWireJson()` 复刻旧版
//     `Log.push` 原样保存入参的语义。
//   把这三层混成一份 `RoomEvent.toJson()` 会让出站 evt 多出 `{vis,to,seq}`，
//   既破坏逐字段等价，又会把可见性级别泄漏给客户端。
// ============================================================

import 'dart:convert';

import 'js_compat.dart';
import 'room_model_state.dart';
import 'room_types.dart';

/// 深拷贝成 JSON 对象（非 Map 时给空对象）。
Map<String, Object?> cloneRoomMap(Object? v) {
  final c = roomClone(v);
  if (c is Map) return c.cast<String, Object?>();
  return <String, Object?>{};
}

/// KP → 玩家：全量同步（重连、首连）。
SyncEnvelope syncMsg(int seq, Map<String, Object?> state) =>
    SyncEnvelope(seq, cloneRoomMap(state));

/// KP → 玩家：增量事件。⚠️ 只带 `{k,seq,t,p}` —— **不带 vis/to**。
///
/// 这里刻意不读 `rec.evt.vis` / `rec.evt.to` / `rec.evt.seq`：可见性是权威端
/// 的内部判定依据（决定发不发、发给谁），一旦写进出站对象就等于把「谁在做
/// 秘密检定」广播出去。旧版 :795 逐字段同样只取 `t` 与 `p`。
EvtEnvelope evtMsg(LogRecord rec) =>
    EvtEnvelope(rec.seq, rec.evt.t, cloneRoomMap(rec.evt.p));

/// KP → 玩家：序号水位标记（这条事件与你无关，但你要把 lastSeq 推到 seq）。
SkipEnvelope skipMsg(int seq) => SkipEnvelope(seq);

/// 玩家 → KP：意图。
IntentEnvelope intentMsg(String op, [Map<String, Object?>? p]) =>
    IntentEnvelope(op, cloneRoomMap(p ?? const <String, Object?>{}));

/// 解析应用层消息的**原始对象**（4 类之外返回 null）。
///
/// 为什么保留「原始对象」形态：旧版 `parse()` 返回的就是 `JSON.parse` 的结果，
/// 多余字段（例如 `evt` 里前端附加的 `nickname`）必须原样保留 ——
/// fixture 是逐字段比较的，包成信封会丢字段。
Map<String, Object?>? parseRoomRaw(Object? raw) {
  Object? m;
  if (raw is String) {
    try {
      m = jsonDecode(raw);
    } catch (_) {
      return null;
    }
  } else {
    m = raw;
  }
  if (m is! Map) return null;
  final map = m.cast<String, Object?>();
  final k = map['k'];
  if (k == 'sync' || k == 'evt' || k == 'skip' || k == 'intent') return map;
  return null;
}

/// 解析成类型化信封（§3.1 的签名）。不认识返回 null。
///
/// ⚠️ 走网络分发时用 [parseRoomRaw]（保留多余字段）；本函数给「只关心结构」的
///    调用方用（例如 P6 传输层要做类型分支时）。
RoomEnvelope? parseRoom(Object? raw) {
  final m = parseRoomRaw(raw);
  if (m == null) return null;
  switch (m['k']) {
    case 'sync':
      return SyncEnvelope(
        jsNum(m['seq']),
        asMap(m['state']),
      );
    case 'evt':
      return EvtEnvelope(
        jsNum(m['seq']),
        jsTruthy(m['t']) ? jsStr(m['t']) : '',
        asMap(m['p']),
      );
    case 'skip':
      return SkipEnvelope(jsNum(m['seq']));
    case 'intent':
      return IntentEnvelope(
        jsTruthy(m['op']) ? jsStr(m['op']) : '',
        asMap(m['p']),
      );
    default:
      return null;
  }
}
