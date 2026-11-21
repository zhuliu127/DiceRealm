// ============================================================
// widgets/room_notice_overlay.dart — 提示浮层 + 关键事件全屏遮罩
//
// ★ 这个文件修的是一个**真缺陷**：`RoomUiLocal.showNotice` 之前只把文本
//   写进 `local.notice`，`lib/` 里从来没有人渲染它 —— 也就是说
//   「操作失败：…」「已自动脱敏 N 条」「已填入聊天框」这些提示，
//   **用户一个字也看不到**（测试却大量断言它们，逻辑全对，只是没上屏）。
//
//   其中「旧存档含历史明文记录，已自动脱敏 N 条」是 K4 的**安全告知**，
//   不显示等于没告知。
//
// 顺带它就是 PRD P2-05 的「操作播报（居中 2 秒）」：ttl 默认 2 秒由
// `showNotice` 保证，本文件只负责「怎么显示」。
//
// ★ PV-1a：`ListenableBuilder` 现在**同时读 `notice` / `optoasts` /
//   `banners`**，三条通路互不共享队列与 ttl：
//   · 单条 `notice` 的卡片渲染（含 root / text 两个 key）逐字保留；
//   · `optoasts` 是独立的操作播报队列，最多 `kOptoastMax` 条按序错峰竖排；
//   · `banners` 是**全屏关键事件遮罩**（P21 改版，见下）。
//
// ------------------------------------------------------------
// P21：横幅从「居中卡片」改成「全屏遮罩」，层次也重新排过
// ------------------------------------------------------------
// 改前三者挤在同一个 `Column` 里（notice → optoasts → banners）。
// 改后横幅要**铺满全屏**，塞进 Column 是不可能的（Column 会给它无界高度/
// 宽度约束），所以拆成浮层内 `Stack` 的两层：
//
// ```dart
// Stack(
//   children: [
//     Positioned.fill(child: 提示列 IgnorePointer(Align(Column(notice, optoasts)))),
//     Positioned.fill(child: _BannerMaskLayer(...)),   // 全屏关键事件遮罩
//   ],
// )
// ```
//
// ★ 为什么「横幅层」必须**常驻**（不能 `if (banners.isNotEmpty)` 才建）：
//   淡出动画由 `_BannerMaskLayer` 内部的 `AnimatedSwitcher` 负责。最后一条
//   被点掉时数据层立刻变空，如果此时把整层从树里摘掉，`AnimatedSwitcher`
//   连一帧都活不到 —— 遮罩会「啪」一下消失，正是用户不要的效果。
//   常驻的代价是零：没有横幅时它内部只有一个 `SizedBox.shrink()`，
//   没有手势层、没有 RenderObject 体积。
//
// ★ 没有提示 / 播报 / 遮罩时**仍然是零占位零拦截**：提示列退化成
//   `SizedBox.shrink()` 且包在 `IgnorePointer` 里；遮罩层退化成
//   `SizedBox.shrink()`（`onDismiss == null` 时连 `GestureDetector` 都不建）。
//   `test/room_notice_overlay_test.dart:108-141`（浮层不吃点击）与
//   `:50-60`（没有提示时整块不渲染）两条口径**原样成立**。
//
// 设计要点（不变的部分）：
//   · `Semantics(liveRegion: true)` —— 让读屏软件把提示念出来；
//   · 自己订阅 `local` —— 本块挂在缩放宿主**外**的 Stack 里，
//     父级不保证重建，必须自己监听；
//   · notice / optoast 最长 3 行 + 省略 + `maxWidth: 420`。
// ============================================================

import 'package:flutter/material.dart';

import '../feed_optoast_tracker.dart' show kOptoastMax;
import '../room_scope.dart' show RoomScope;
import '../room_ui_local.dart' show RoomOptoastItem;
import 'room_event_banner.dart' show RoomBannerItem, RoomEventBanner;

/// 提示浮层的稳定 key。
class RoomNoticeKeys {
  const RoomNoticeKeys._();

  /// 浮层本体（没有提示时整块不渲染，所以 `findsNothing` 也是有效断言）。
  static const Key root = ValueKey<String>('roomNotice/root');

  /// 文本。
  static const Key text = ValueKey<String>('roomNotice/text');

  /// 一条操作播报卡片的稳定 key（按 [id] 区分，供测试逐条定位）。
  static Key optoast(int id) => ValueKey<String>('roomNotice/optoast/$id');

  /// 全屏遮罩层的容器（常驻；没有横幅时里面有且只有一个
  /// `SizedBox.shrink()`）。
  static const Key bannerLayer = ValueKey<String>('roomNotice/bannerLayer');

  /// 遮罩层里「没有横幅」时的零尺寸占位（淡出动画跑完后落回这一颗）。
  static const Key emptyBannerSlot = ValueKey<String>('roomNotice/bannerNone');
}

/// 提示浮层 + 关键事件全屏遮罩。
///
/// 挂在 `RoomScope` **之下**（要读 `local`）、内容区**之上**（用 `Stack`）。
/// 挂载点在 `room_entry_page.dart` 的
/// `Stack[_RoomStageSwitch(), RoomNoticeOverlay()]` —— 覆盖大厅与游戏页、
/// 三视角都生效，本批不改动挂载点。
class RoomNoticeOverlay extends StatelessWidget {
  const RoomNoticeOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final local = RoomScope.of(context).local;
    final theme = Theme.of(context);

    // ★ 自己订阅：本块不在缩放宿主的 ListenableBuilder 覆盖范围内。
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) {
        final String? noticeText = local.notice;
        final List<RoomOptoastItem> toastRows = local.optoasts;
        // ★ 一次只显示一条：队首即当前条，其余按序等待（P21 需求 4）。
        final RoomBannerItem? banner =
            local.banners.isEmpty ? null : local.banners.first;

        return Stack(
          children: <Widget>[
            // ---- ① 提示列（notice + optoasts）----
            Positioned.fill(child: _noticeLayer(ctx, theme, noticeText, toastRows)),
            // ---- ② 关键事件全屏遮罩（常驻：见文件头「为什么必须常驻」）----
            Positioned.fill(
              child: _BannerMaskLayer(
                active: banner,
                onDismiss: banner == null
                    ? null
                    : () => local.dismissActiveBanner(id: banner.id),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 提示列：单条 notice 在上、操作播报按队列顺序错峰竖排（最多
  /// `kOptoastMax` 条）。没有内容时退化成零尺寸，且始终不可点击。
  Widget _noticeLayer(
    BuildContext ctx,
    ThemeData theme,
    String? noticeText,
    List<RoomOptoastItem> toastRows,
  ) {
    final String notice = noticeText ?? '';
    final bool hasNotice = notice.isNotEmpty;
    if (!hasNotice && toastRows.isEmpty) {
      // 与改前逐字同口径：整块不渲染（不占位、不挡东西）。
      return const SizedBox.shrink();
    }

    // 相邻卡片间插 8px 间距，对标 `.gp-optoast-host { gap: 8px }`。
    final List<Widget> children = <Widget>[];
    if (hasNotice) {
      children.add(_noticeCard(ctx, theme, notice));
    }
    final int toastCount = toastRows.length > kOptoastMax
        ? kOptoastMax
        : toastRows.length;
    for (int i = 0; i < toastCount; i++) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(_optoastCard(ctx, theme, toastRows[i]));
    }

    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }

  /// 单条 `notice` 卡片（**逐字保留**原渲染：root / text key、配色、
  /// `maxWidth: 420`、`maxLines: 3`、`Semantics(liveRegion)` 全不变）。
  Widget _noticeCard(BuildContext ctx, ThemeData theme, String text) {
    return Material(
      key: RoomNoticeKeys.root,
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface.withValues(
            alpha: 0.94,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        // 让读屏软件把提示念出来（视觉提示对看不见的人无效，这一行是白送的）。
        child: Semantics(
          liveRegion: true,
          child: Text(
            text,
            key: RoomNoticeKeys.text,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onInverseSurface,
            ),
          ),
        ),
      ),
    );
  }

  /// 一条操作播报卡片：胶囊造型（对标 `.gp-optoast`），同样可穿透、
  /// 同样 `maxWidth: 420` / `maxLines: 3` / `Semantics(liveRegion)`。
  Widget _optoastCard(
    BuildContext ctx,
    ThemeData theme,
    RoomOptoastItem item,
  ) {
    return Material(
      key: RoomNoticeKeys.optoast(item.id),
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.45),
          ),
        ),
        child: Semantics(
          liveRegion: true,
          child: Text(
            item.text,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onInverseSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 关键事件遮罩的「淡入 / 淡出」宿主。
///
/// 数据层是瞬时的（`RoomUiLocal.banners` 一点就前进一条），**动画只在这一层**
/// —— 这样调度逻辑完全可纯逻辑单测，而「点一下会淡出」是 UI 层的事。
///
/// 三种切换都由 `AnimatedSwitcher` 的默认 `FadeTransition` 覆盖：
///   · 无 → 有：淡入（220ms）；
///   · 有 → 有（上一条到点，下一条提升）：交叉淡化（220ms）；
///   · 有 → 无（最后一条被点掉 / 到点）：**淡出**（220ms）。
class _BannerMaskLayer extends StatelessWidget {
  const _BannerMaskLayer({required this.active, required this.onDismiss});

  /// 当前要显示的那一条；`null` = 没有横幅。
  final RoomBannerItem? active;

  /// 点击关闭回调；`null` = 不建手势层（没有遮罩就绝不拦点击）。
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final RoomBannerItem? cur = active;
    return AnimatedSwitcher(
      key: RoomNoticeKeys.bannerLayer,
      duration: RoomEventBanner.fadeDuration,
      // 消失走同一条时长：点击后必须是**看得见的淡出**，不是瞬消。
      reverseDuration: RoomEventBanner.fadeDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // ★ P21 裁定（主理人拍板）：**淡出这 220ms 里继续吃掉点击**。
      //
      // 为什么不再包 `IgnorePointer`（改前一版就是包的，当时理由是「点击
      // 不该被白吃 220ms」）：用户「点屏幕关闭」的本能是**连点两下**，
      // 第二下若穿透到房间，落点可能是「结束房间 / 结团 / 战斗」这类**不可
      // 逆**按钮。220ms 的死区远比误触一次结团便宜 —— 这条不该由用户承担。
      //
      // 叠放与命中顺序：`previous`（正在淡出的旧条）在下、`current`（当前条）
      // 在上。`RenderStack` 反向遍历子级做 hit-test ⇒ **当前条先吃到点击**，
      // 所以「有 → 有」交叉淡化期间点屏幕关的是**新条**，不会被旧层挡住
      // （`p21_event_banner_mask_test.dart` 的 `Q3 续 · 交叉淡化期间` 用例
      // 锁死这条，不靠「理论上不会抢」）。
      //
      // ★ `StackFit.loose`：遮罩自己会撑满（内部是 `Stack(fit: expand)`），
      //   而「没有横幅」那颗 `SizedBox.shrink()` 必须能真的保持 0×0 ——
      //   `StackFit.expand` 会把每一颗子级都强行拉到满屏，那颗占位盒就不再
      //   是零占位了（用例会直接量出来）。
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        fit: StackFit.loose,
        children: <Widget>[
          // ★ previous 在下、current 在上；两者都**保留自己的手势层**。
          ...previous,
          ?current,
        ],
      ),
      child: cur == null
          ? const SizedBox.shrink(key: RoomNoticeKeys.emptyBannerSlot)
          : RoomEventBanner(
              // 换条 → 换 key ⇒ 触发交叉淡化。
              key: ValueKey<String>('roomBanner/item/${cur.id}'),
              banner: cur,
              ttl: cur.ttl,
              onDismiss: onDismiss,
            ),
    );
  }
}
