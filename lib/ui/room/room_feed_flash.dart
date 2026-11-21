// ============================================================
// room_feed_flash.dart — 信息流闪烁的判据（PRD P2-05）
//
// 对应旧版 `room-ui.js:3730 triggerFeedFlash` + `:3748 feedFlashCheck`。
// 抽成纯逻辑是因为**判据比动画难**：什么时候该闪，错了就是打扰用户。
//
// ★ Round 2 修复：把「靠 seq 差值猜补拉 / 猜涌入」的判据整个退役。
//
//   旧实现有一条 `lastSeq - prev > floodThreshold 就不闪`，想同时表达
//   「断线重连补拉」和「一次涌入太多别刷屏」。这两件事都不该由 seq 差推断：
//     · chats / logs / dice 每条记录的 seq 都是**全局事件序号**
//       （room_model_reduce 给三类事件写的是同一个 evt.seq），不是每列自己的
//       序号。于是「两条聊天之间夹了 7 条骰子」会让聊天列的差值虚高到 8，
//       正常在线的新消息被误判成补拉而漏闪（QA 限制 3）。
//     · 反过来，短断线只漏 3 个事件时差值又太小（10→13），够不到阈值，
//       补拉回来的一批照样被当成新消息误闪（QA 限制 2）。
//   同一个错误抽象的两面，靠调阈值或换 seq 口径都只是把出错场景挪位置。
//
//   现在「补拉」由**连接层显式信号**告诉 UI：RoomSession.syncEpoch 每完成
//   一份全量 sync 就 +1，GpFeeds 观察到世代变化即 reset() 重新登记首屏基线。
//   判据侧只回答「有没有新条目、是不是自己发的」，不再猜批次语义。
//
// 保留三条规则（前两条照旧版，第三条是纯数据守卫，与批次无关）：
//   1. **首次绘制不闪** —— 进房间时那几十条历史消息不是「新消息」，
//      全闪一遍等于给用户放烟花。
//   2. **自己发的不闪** —— 用户知道自己刚发了什么，闪了反而莫名其妙。
//   3. **没有新条目不闪** —— 同 seq 重绘 / seq 回退（补拉乱序、状态重建）
//      都不是新消息，提醒「有新消息」是反的。
//
// 补拉、涌入过多这类「批次」语义一律由外部 reset() 表达，判据不越界。
// ============================================================

/// 信息流闪烁判据。
///
/// 每个信息流（记录 / 聊天）各持一个实例 —— 它们各自观察自己的展示序列，
/// 互不干扰。判据不读取任何批次信息，也不引入阈值参数：换房间 / 断线补拉
/// 由调用方在世代信号变化时调 [reset]。
class FeedFlashTracker {
  int? _lastSeq;
  bool _initialized = false;

  /// 已记录的基线（测试/诊断用）。
  int? get lastSeq => _lastSeq;

  /// 判一次。
  ///
  /// 返回：
  ///   · `null` —— 首次调用，只登记基线，**不闪**（历史消息不算新）
  ///   · `true`  —— 该闪
  ///   · `false` —— 不该闪
  ///
  /// [lastSeq] 当前最后一条的 seq；[lastSeat] 它的座位（空串表示无归属，
  /// 例如系统消息）；[mySeat] 自己的座位。
  ///
  /// ★ 这里刻意**不比较 `lastSeq` 与基线的差值大小**：该值是全局事件序号，
  ///   差值既不代表本列新增条数，也不代表是否补拉。补拉不闪由外部在
  ///   连接层世代变化时调 [reset] 保证。
  bool? check({
    required int lastSeq,
    required String lastSeat,
    required String mySeat,
  }) {
    // 空流：不登记基线（否则第一条消息到达时会被当成「首次」而漏闪）。
    if (lastSeq <= 0) return false;

    final prev = _lastSeq ?? 0;
    _lastSeq = lastSeq;

    if (!_initialized) {
      _initialized = true;
      return null; // 首次：登记基线，不闪
    }
    if (lastSeq <= prev) return false; // 没有新条目（或回退）
    if (lastSeat.isNotEmpty && lastSeat == mySeat) return false; // 自己发的
    return true;
  }

  /// 换房间 / 断线补拉时重置基线（新的一批历史不算新消息）。
  ///
  /// 调用时机由连接层世代信号决定，不由 seq 差值决定。
  void reset() {
    _lastSeq = null;
    _initialized = false;
  }
}
