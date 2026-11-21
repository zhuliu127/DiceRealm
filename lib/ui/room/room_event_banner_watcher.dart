// ============================================================
// room_event_banner_watcher.dart — 关键事件横幅的页面级旁路监听（P20 需求 2）
//
// 与 `room_optoast_watcher.dart` **同构**（照抄它的订阅范式，便于两处对照）：
// StatefulWidget + `didChangeDependencies` 绑定 session + `addListener`，
// `build` 只返回 `SizedBox.shrink()` —— **零 RenderObject / 零布局影响**，
// 不弹 Dialog、不占 Stack 位置、不改变任何 LayoutBuilder 约束与几何。
//
// 数据流（每次 session 通知）：
//   CriticalEventTracker.sync(session.state, syncEpoch: ..., mySeat: seat)
//   → 逐条 RoomUiLocal.pushBanner(title/subtitle/art)
//   → RoomNoticeOverlay 读 local.banners 上屏（P21：全屏遮罩，一次只显示
//     一条；队尾 4 秒、还有后续条目时 2.2 秒，点一下当前条即淡出）
//
// ★ 判据全在 `critical_event_tracker.dart`（纯 Dart、可纯逻辑单测）：按
//   **state diff** 判跃迁，不解析 log；首帧只登记基线、不弹历史；
//   `syncEpoch` 变化整机重置（补拉回来的历史一律不重播）。
//   本文件只做一件事：把判出来的事件推进遮罩队列。
//
// ★ C14：**本文件不出现任何裸 Timer**，也不持有任何 Timer。到点自消完全由
//   `RoomUiLocal.pushBanner` 内部走可注入的 `scheduleDismiss` 驱动
//   （与 `pushOptoast` 同源口径），否则 FakeAsync / testWidgets 里推进
//   4 秒也不会触发消失。
//
// ★ 协议零改动：只**读**合并后的公开 state 视图，不新增网络消息类型 /
//   事件 / 意图，不写权威态、不产生任何 `SendPlan`。
//
// ★ 5 张底图以 `lib/ui/art.dart` 的 `Art.e18Banner*` 为**单一真源**：
//   tracker 支持 `artOf` 注入，本文件注入 `Art` 常量，避免
//   `critical_event_tracker.dart` 里那份纯 Dart 镜像（`EventBannerArt`）
//   与本文件的实际取图悄悄跑偏。改路径时仍建议两处一起改。
// ============================================================

import 'package:flutter/widgets.dart';

import '../art.dart' show Art;
import 'critical_event_tracker.dart'
    show CriticalEvent, CriticalEventKind, CriticalEventTracker;
import 'room_scope.dart' show RoomScope;
import 'room_session.dart' show RoomSession;
import 'room_ui_local.dart' show RoomUiLocal;

/// 页面级全局监听：把「新发生的关键事件」逐条推给横幅队列。
///
/// 无参构造（`const RoomEventBannerWatcher()`），本身不渲染任何可见内容；
/// 真正的上屏由 `RoomNoticeOverlay` 读 `RoomUiLocal.banners` 完成。
///
/// 挂载点由另一路（`room_game_page.dart` / `room_layout.dart`）负责，本文件
/// 不自行挂载、不假设任何父级约束。
class RoomEventBannerWatcher extends StatefulWidget {
  const RoomEventBannerWatcher({super.key});

  @override
  State<RoomEventBannerWatcher> createState() => _RoomEventBannerWatcherState();
}

class _RoomEventBannerWatcherState extends State<RoomEventBannerWatcher> {
  /// 跨重建持有基线（与 `RoomOptoastWatcher` 的 FeedOptoastTracker 同理）。
  ///
  /// `artOf` 注入 `Art.e18Banner*`（单一真源）；未知 kind 退「疯狂」那张，
  /// 与 `EventBannerArt.of` 的默认分支同口径 —— 存在即安全，绝不抛异常。
  final CriticalEventTracker _tracker = CriticalEventTracker(
    artOf: (String kind) => switch (kind) {
      CriticalEventKind.combatStart => Art.e18BannerCombat,
      CriticalEventKind.combatEnd => Art.e18BannerCombatEnd,
      CriticalEventKind.death => Art.e18BannerDeath,
      CriticalEventKind.ripped => Art.e18BannerRipped,
      _ => Art.e18BannerMadness,
    },
  );

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
      // 只刷新引用，**不重置 tracker 基线**，否则会把刚弹过的再弹一遍。
      return;
    }
    _session?.removeListener(_onSession);
    _session = s;
    _tracker.reset();
    s.addListener(_onSession);
    // ★ 首次挂载 / 换会话：立刻登记首屏基线，把「进房时已有的历史」记成
    //   已读（不弹）。若把这一步留到第一条新消息的 notify，那条新消息会被
    //   连同历史一起当成基线吞掉。
    _syncNow(push: false);
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _session = null;
    _local = null;
    super.dispose();
  }

  /// session 通知回调：不在 build 期间，调到 `local.pushBanner` 是安全的。
  void _onSession() {
    if (!mounted) return;
    _syncNow(push: true);
  }

  /// 跑一次判据。[push] = false 时只登记基线、丢弃产出（挂载 / 换会话用）。
  void _syncNow({required bool push}) {
    final RoomSession? s = _session;
    final RoomUiLocal? local = _local;
    if (s == null || local == null) return;
    final List<CriticalEvent> evts = _tracker.sync(
      s.state,
      syncEpoch: s.syncEpoch,
      mySeat: s.seat,
    );
    if (!push) return;
    for (final CriticalEvent e in evts) {
      // 空标题由 `pushBanner` 自行丢弃（防御性：tracker 理论上不会产出）。
      local.pushBanner(
        title: e.title,
        subtitle: e.subtitle,
        art: e.art,
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
