// ============================================================
// feed_optoast_tracker.dart — 操作播报（遮罩）的「新增判据 + 文案」（PV-1a）
//
// ★ 纯 Dart：零 Flutter 依赖，便于纯逻辑单测（契约 I9）。本文件只 import
//   `view/feed_view.dart`（其自身亦为零框架依赖的纯派生层：domain/js_compat、
//   room_model_state、avatar_uri、room_text 全部纯 Dart），故 [FeedItem] /
//   [diceLine] / [checkLine] 可直接复用，不需要另造一份轻量记录结构。
//
// 逐字对齐老 APP `room-ui.js:3764-3872`（optoastCheck / optoastText）：
//   · 首次绘制只登记基线、不弹历史；
//   · 「同设备自己做的动作也要弹」——★ 与 `FeedFlashTracker.check` 相反
//     （后者「自己发的不闪」、只看末条）；本 tracker 不读 seat、逐条产出；
//   · 一次新增 > `kOptoastFlood` 条 → 视为断线重连全量同步，直接不刷屏；
//   · 同屏最多 `kOptoastMax` 条、单条 `kOptoastTtl` 自消（由 RoomUiLocal 管）；
//   · 文案 `\s+`→单空格、> `kOptoastMaxChars` 字截断为 39 + '…'。
//
// ★ D7 解耦：KP-6c 一次产生 M×N 条 `kind:'check'` 公开记录，游戏记录栏
//   **照出 M×N 条**；本层仅靠 flood 守卫兜住遮罩不刷屏，绝不为了遮罩好看
//   去削减记录条数，也不触碰任何 domain / 协议逻辑。
//
// ★ C13：播报严格绑「新产生的公开记录 / 公开骰条目」——排除 `chat`；
//   `redacted` 行只取公开 `text`、不还原 opp / dice 结果；本期不新增任何
//   画笔 / 清屏公开 log（老 APP `room-model.js:2396-2403` 用户明确要求去掉）。
// ============================================================

import 'room_text.dart' show roomText;
import 'view/feed_view.dart' show FeedItem, FeedKind, checkLine, diceLine;

/// 同屏最多错峰堆叠条数（老 APP `OPTOAST_MAX = 3`）。
const int kOptoastMax = 3;

/// 一次新增超过此数视为全量补拉 / 重连，直接不刷屏（老 APP `OPTOAST_FLOOD = 6`）。
const int kOptoastFlood = 6;

/// 单条文案最大字数（老 APP `optoastTrim` 的 40）。
const int kOptoastMaxChars = 40;

/// 单条展示时长（老 APP `OPTOAST_MS = 2000`）。
/// 自消由 `RoomUiLocal.scheduleDismiss` 驱动，本类不持有任何 Timer。
const Duration kOptoastTtl = Duration(seconds: 2);

/// 操作播报的判据与文案。
///
/// 一个实例对应一份**会话视图**（`RoomOptoastWatcher` 持一个）。[sync] 每次
/// 会话通知调用一次，返回「这一批应该播报的文案」；播报的排队 / 上屏 / 自消
/// 全部交给 `RoomUiLocal.pushOptoast`，本类不碰 UI、不碰权威态。
class FeedOptoastTracker {
  /// ★ 兼容架构设计 §7 的类内访问写法（`FeedOptoastTracker.kOptoastTtl` 等）：
  ///   与文件顶层同名常量是**同一冻结值**的两个访问入口，永久相等；二者都是
  ///   编译期常量，不存在两份会各自漂移的实现。顶层常量供 `RoomUiLocal` /
  ///   `RoomNoticeOverlay` 直接 import，类内常量供按类限定名访问的调用方使用。
  static const int kOptoastMax = 3;
  static const int kOptoastFlood = 6;
  static const int kOptoastMaxChars = 40;
  static const Duration kOptoastTtl = Duration(seconds: 2);

  int? _lastSeq;
  bool _initialized = false;
  int? _epoch;

  /// 已登记的基线 seq（测试 / 诊断用）。
  int? get lastSeq => _lastSeq;

  /// 基线是否已登记（首次 [sync] 前为 `false`）。
  bool get initialized => _initialized;

  /// 换房间 / 断线补拉时重置基线（新的一批历史不算「新产生」）。
  ///
  /// 调用方无需手动判世代：[sync] 收到变化的 `syncEpoch` 会自行调用本方法。
  void reset() {
    _lastSeq = null;
    _initialized = false;
    _epoch = null;
  }

  /// 判一次「公开记录新增」，逐条产出应播报的文案（按全局 seq 升序）。
  ///
  /// [items] 通常是 `collectFeeds(state)` 的返回（logs + dice 合并、时间正序）。
  /// [syncEpoch] 取 `RoomSession.syncEpoch`：每完成一次全量同步自增一次，
  /// 世代变化即 [reset] 并重登基线（本次返回空），避免补拉历史刷屏。
  ///
  /// 返回空列表的情形：首次登记基线 / seq 回退或无新增 / 一次涌入 >6 条 /
  /// 新增条目全被过滤为空文案。
  List<String> sync(List<FeedItem> items, {required int syncEpoch}) {
    // ① 世代变化（首连 / 重连补拉）：重置基线，本次只登记不弹。
    //    reset() 会清空 _epoch，故随后立刻记住当前世代。
    if (_epoch != syncEpoch) {
      reset();
      _epoch = syncEpoch;
    }

    // ② 只看「公开记录 / 公开骰」：聊天不是播报对象（C13）。
    //    maxSeq 也只在这批可见条目里取 —— 与老 APP optoastCheck 同源：
    //    它的 items 只由 st.logs + st.dice 组成，不含 st.chats。
    final List<FeedItem> visible = <FeedItem>[];
    int maxSeq = 0;
    for (final FeedItem it in items) {
      if (it.kind == FeedKind.chat) continue;
      visible.add(it);
      if (it.seq > maxSeq) maxSeq = it.seq;
    }

    // ③ 首次：只登记基线，不弹历史（老 APP `!_optoast.init` 分支）。
    if (!_initialized) {
      _initialized = true;
      _lastSeq = maxSeq;
      return <String>[];
    }

    final int from = _lastSeq ?? 0;
    // ④ seq 回退 / 同 seq 重绘（状态重建、补拉乱序）都不是「新产生」。
    if (maxSeq <= from) return <String>[];

    // ★ 先推进基线再判 flood：与老 APP 一致 —— 即使这一批被判为全量补拉
    //   而跳过，基线也已经吃到最新 seq，下一批不会把这批重弹一遍。
    _lastSeq = maxSeq;

    // ⑤ 逐条取出「seq 大于基线」的新条目（不是只看末条）。
    final List<FeedItem> fresh = visible
        .where((FeedItem it) => it.seq > from)
        .toList();

    // ⑥ 一次新增 >6 条 = 全量同步 / D7 的 M×N 批量检定 → 直接不刷屏。
    if (fresh.length > kOptoastFlood) return <String>[];

    // ⑦ 按全局 seq 升序逐条产出；**不比较 seat**，自己发出的也照弹
    //    （老 APP：「同设备自己产生的动作也要弹」，与 FeedFlashTracker 相反）。
    fresh.sort((FeedItem a, FeedItem b) => a.seq.compareTo(b.seq));
    final List<String> out = <String>[];
    for (final FeedItem it in fresh) {
      final String text = textOf(it);
      if (text.isEmpty) continue; // 对齐 optoastEnqueue 的 `if (!text) return`
      out.add(text);
    }
    return out;
  }

  /// 单条 feed → 播报文案（≤ [kOptoastMaxChars] 字）。
  ///
  /// 口径（老 APP `optoastText:3834-3850`）：
  ///   · `redacted` → **只取公开 `text`**，绝不还原 opp / dice 结果（隐私红线）；
  ///   · `dice` → 「昵称 掷 expr/label ＝ total levelText」（昵称取
  ///     [FeedItem.nickname]，即 `feed_view.dart:132` 的 `d['nickname']`）；
  ///     结构化骰字段缺失时退回该条公开文本 / [diceLine] 文案，不臆造数字；
  ///   · `opposed` → [checkLine]（在公开 text 上补「· X 胜 / · 平局」）；
  ///   · 其余（公开的 `check` / `sys` / `note` 日志）→ 直接用 `text` —
  ///     权威端组装时**已含动作者名**，不另加前缀（老 APP 同口径）；
  ///   · `chat` → 空串（双保险；[sync] 已在入口排除）。
  static String textOf(FeedItem it) {
    // ★ redacted 一律最先短路：只看公开 text，绝不碰 opp / dice 结果。
    if (it.redacted) return _trim(it.text);
    final FeedKind kind = it.kind;
    if (kind == FeedKind.dice) return _trim(_diceText(it));
    if (kind == FeedKind.opposed) return _trim(checkLine(it));
    if (kind == FeedKind.chat) return '';
    // check / sys / note：公开日志 text（权威端组装时已含动作者名）。
    // 用兜底分支而非 exhaustive switch，将来 FeedKind 扩值也自动走公开文本。
    return _trim(it.text);
  }

  /// 公开骰的播报行：昵称 + 掷 + expr/label + ＝total + levelText。
  static String _diceText(FeedItem it) {
    final String who = it.nickname.isNotEmpty ? it.nickname : '调查员';
    final Map<String, Object?>? d = it.dice;
    if (d == null) {
      // 无结构化骰数据：退回该条公开文本（collectFeeds 里即 diceLine(d)）。
      return '$who 掷 ${it.text}';
    }
    final String label = roomText(d['label']);
    final String expr = roomText(d['expr']);
    final Object? total = d['total'];
    // 关键字段全缺（老存档 / 快捷骰）：退回 feed 口径的 diceLine 文案，
    // 不臆造数字，也不丢技能名。
    if (label.isEmpty && expr.isEmpty && total is! num) {
      return '$who 掷 ${diceLine(d)}';
    }
    final StringBuffer buf = StringBuffer('$who 掷 ');
    buf.write(label.isNotEmpty ? label : (expr.isNotEmpty ? expr : '1D100'));
    if (total is num && total.isFinite) buf.write('＝${roomText(total)}');
    final String levelText = roomText(d['levelText']);
    if (levelText.isNotEmpty) buf.write(' $levelText');
    return buf.toString();
  }

  /// `\s+` → 单空格 + 首尾 trim + ≤40 字截断（超出取前 39 + '…'）。
  ///
  /// 与老 APP `optoastTrim` 逐字一致（JS `String.length` 与 Dart 同为 UTF-16
  /// code unit 数，`slice(0,39)+'…'` 对应 `substring(0, 39) + '…'`）。
  static String _trim(String raw) {
    final String collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= kOptoastMaxChars) return collapsed;
    return '${collapsed.substring(0, kOptoastMaxChars - 1)}…';
  }
}
