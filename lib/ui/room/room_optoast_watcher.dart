// ============================================================
// room_optoast_watcher.dart — 操作播报（遮罩）的页面级旁路监听（PV-1a）
//
// 挂在 `RoomGamePage` 根节点外层（`room_game_page.dart:345` 同层，由 T03
// 负责挂 `const RoomOptoastWatcher()`）。对齐既有 `RoomRequestWatcher` 的
// 订阅范式：StatefulWidget + didChangeDependencies 绑定 session + addListener，
// `build` 只返回 `SizedBox.shrink()` —— **零 RenderObject / 零布局影响**，
// 不弹 Dialog、不占 Stack 位置、不改变任何 LayoutBuilder 约束与几何。
//
// 数据流（每次 session 通知）：
//   collectFeeds(session.state) → FeedOptoastTracker.sync(..., syncEpoch)
//   → 逐条 RoomUiLocal.pushOptoast(text)
//
// ★ C14：**本文件不出现任何裸 Timer**。2 秒自消完全由
//   `RoomUiLocal.pushOptoast` 内部走可注入的 `scheduleDismiss` 驱动
//   （`gp_feeds.dart:113-116` 的 testWidgets / FakeAsync 口径），否则测试里
//   推进 2 秒也不会触发消失。
//
// ★ 协议零改动：6 类目标事件的结果本就以 PUBLIC `RoomEvt.log/dice/check`
//   广播进 `state['logs'] / ['dice']`，各端 reduce 出同一条带全局 seq 的
//   记录；本 watcher 只是**读**合并后的公开信息流，不新增任何网络消息
//   类型 / 事件 / 意图，不写权威态。
//
// ★ D7 解耦：只负责把 tracker 判出的文案推给遮罩层，绝不改记录栏条数。
// ============================================================

import 'package:flutter/widgets.dart';

import 'feed_optoast_tracker.dart' show FeedOptoastTracker;
import 'room_scope.dart' show RoomScope;
import 'room_session.dart' show RoomSession;
import 'room_ui_local.dart' show RoomUiLocal;
import 'view/feed_view.dart' show FeedItem, collectFeeds;

/// 页面级全局监听：把「新产生的公开记录 / 公开骰」逐条推给遮罩队列。
///
/// 无参构造（`const RoomOptoastWatcher()`），本身不渲染任何可见内容；
/// 真正的上屏由 `RoomNoticeOverlay` 读 `RoomUiLocal.optoasts` 完成。
class RoomOptoastWatcher extends StatefulWidget {
  const RoomOptoastWatcher({super.key});

  @override
  State<RoomOptoastWatcher> createState() => _RoomOptoastWatcherState();
}

class _RoomOptoastWatcherState extends State<RoomOptoastWatcher> {
  /// 跨重建持有基线（与 `GpFeeds` 的 FeedFlashTracker 同理）。
  final FeedOptoastTracker _tracker = FeedOptoastTracker();

  RoomSession? _session;
  RoomUiLocal? _local;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `of` 会订阅 session（InheritedNotifier）；换会话 / 换作用域时能重新绑定。
    final RoomScope scope = RoomScope.of(context);
    final RoomSession s = scope.session;
    _local = scope.local;
    if (identical(s, _session)) {
      // 会话未变（含「每次 notify 触发的 didChangeDependencies」）：
      // 只刷新引用，**不重置 tracker 基线**，否则会把刚播过的再算一遍。
      return;
    }
    _session?.removeListener(_onSession);
    _session = s;
    _tracker.reset();
    s.addListener(_onSession);
    // ★ 首次挂载 / 换会话：立刻登记首屏基线，把「进房时已有的历史」记成
    //   已读（不播）。若把这一步留到第一条新消息的 notify，那条新消息会被
    //   连同历史一起当成基线吞掉 —— 老 APP 也是每次重绘都跑 optoastCheck。
    _syncNow(push: false);
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _session = null;
    _local = null;
    super.dispose();
  }

  /// session 通知回调：不在 build 期间，调到 `local.pushOptoast` 是安全的。
  void _onSession() {
    if (!mounted) return;
    _syncNow(push: true);
  }

  /// 跑一次判据。[push] = false 时只登记基线、丢弃产出（挂载用）。
  void _syncNow({required bool push}) {
    final RoomSession? s = _session;
    final RoomUiLocal? local = _local;
    if (s == null || local == null) return;
    final List<FeedItem> items = collectFeeds(s.state);
    final List<String> texts = _tracker.sync(items, syncEpoch: s.syncEpoch);
    if (!push) return;
    for (final String text in texts) {
      if (text.isEmpty) continue;
      local.pushOptoast(text);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
