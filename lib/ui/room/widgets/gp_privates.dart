// ============================================================
// widgets/gp_privates.dart — 块 10(KP) / 9(PL)：只给你看的信息
//
// 数据来自 `state.privates`（权威端已按座位裁剪好），只取最近 12 条、**正序**
// （最新在最后）。每条只渲染 `text`（§0.2 / C6）—— 不解析、不还原结构化字段，
// 也不显示「点击查看结果」这类暗示可以还原的入口。
//
// 交互三件：
//   · 新条高亮（P2-05：只做高亮，不做弹跳/播报）；
//   · 点某条 → 弹层给全文（长文本不挤压块高）；
//   · ⛶ 全屏 → 弹层列出全部 12 条。
//
// ★ 新条判定**不再自造**（P10 第 2 期 B）：与聊天 / 公开记录同源，一律交给
//   `FeedFlashTracker.check()` 裁定（三条规则：首帧不闪 / 自己发的不闪 /
//   没有新条目不闪）。本组件只负责「选数据 + 画结果」。
//   `syncEpoch` 变化（断线补拉）时重置基线，与 `GpFeeds` 同一套接法。
//   零 Timer、零 AnimationController：角标是纯派生状态标记。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_types.dart' show kHostSeat;
import '../../widgets/avatar_picker.dart' show AvatarThumb;
import '../room_feed_flash.dart' show FeedFlashTracker;
import '../room_scope.dart';
import '../sheets/room_sheet.dart';
import '../view/feed_view.dart' show feedAvatarOfSeat, privRowsOf;
import 'gp_feeds.dart' show kChatInputRowHeight;
import 'room_button_size.dart' show RoomBtnSize;
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 私密栏内部稳定 key。
class GpPrivatesKeys {
  const GpPrivatesKeys._();

  static const Key list = ValueKey<String>('gpPriv/list');
  static const Key fullscreen = ValueKey<String>('gpPriv/fullscreen');
  static const Key empty = ValueKey<String>('gpPriv/empty');

  /// 全屏弹层里那份**订阅式**私密列表的根（PV-3）。与 `gp_feeds.dart` 的
  /// `GpFeedsKeys.liveBody` 同形态：测试用它把查找限定在弹层内，避免主页
  /// 列表与全屏列表的 `list` key 同时命中。
  static const Key liveBody = ValueKey<String>('gpPriv/liveBody');

  /// 有新消息的角标（与 `GpFeedsKeys.flash` 同形态）。没有新消息时整块
  /// 不渲染，所以 `findsNothing` 是有效断言。
  static const Key flash = ValueKey<String>('gpPriv/flash');

  /// 单条派生 key（`gpPriv/row/<seq>`）。
  static Key row(int seq) => ValueKey<String>('gpPriv/row/$seq');

  /// 条目左侧的 KP 头像（`gpPriv/avatar`）。没有头像时整块不渲染，
  /// 所以 `findsNothing` 是有效断言（P10 第 2 期 A）。
  static const Key avatar = ValueKey<String>('gpPriv/avatar');
}

/// 私密栏（最近 12 条、正序、新条高亮）。
class GpPrivates extends StatefulWidget {
  const GpPrivates({
    super.key,
    this.limit = 12,
    // ★ P16 KP-5：拉长到与聊天/游戏记录一致（gp_feeds.dart 默认 220），
    //   填满中排空隙；中排 flex:1 本就等高，不动布局。
    this.height = 220,
    this.flashTracker,
  });

  /// 上限（块 10/9 固定 12；参数只为测试/复用留口）。
  final int limit;

  /// 可视高度（块在固定网格里没有外部高度约束）。
  final double height;

  /// 可注入的闪烁判据（接线测试用）；null → 本块自建一个实例。
  final FeedFlashTracker? flashTracker;

  @override
  State<GpPrivates> createState() => _GpPrivatesState();
}

class _GpPrivatesState extends State<GpPrivates> {
  /// 闪烁判据（与聊天 / 公开记录同一个类，同一套输入）。
  late FeedFlashTracker _tracker;

  /// 上次绑定的会话对象 / 连接层同步世代（换房间、补拉时重置基线）。
  Object? _boundSession;
  int _boundEpoch = -1;

  /// 上次判过的末条 seq（同一批数据重绘不重复判）。
  int _checkedSeq = -1;

  /// 当前是否显示「新」角标（纯派生状态，无定时器、无动画）。
  bool _flash = false;

  /// 本帧要标记为「新条」的 seq 集合（行内高亮，随角标同源派生）。
  Set<int> _fresh = <int>{};

  @override
  void initState() {
    super.initState();
    _tracker = widget.flashTracker ?? FeedFlashTracker();
  }

  @override
  void didUpdateWidget(covariant GpPrivates old) {
    super.didUpdateWidget(old);
    if (!identical(old.flashTracker, widget.flashTracker)) {
      _tracker = widget.flashTracker ?? FeedFlashTracker();
      _checkedSeq = -1;
      _flash = false;
      _fresh = <int>{};
    }
  }

  static int _seqOf(Map<String, Object?> row) =>
      (row['seq'] is num) ? (row['seq']! as num).toInt() : 0;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final int epoch = scope.session.syncEpoch;
    // 换房间 / 连接层完成一次全量补拉 → 重置基线（这批不是新消息）。
    if (!identical(scope.session, _boundSession) || epoch != _boundEpoch) {
      _boundSession = scope.session;
      _boundEpoch = epoch;
      _tracker.reset();
      _checkedSeq = -1;
      _flash = false;
      _fresh = <int>{};
    }

    final rows = privRowsOf(scope.session.state, scope.session.seat,
        limit: widget.limit);
    // P10 第 2 期 A：私密信息是**权威端（KP）**发下来的，所以条目左侧画 KP
    // 的头像。私密行结构只有 `{seq,title,text,at,kind}` 五键（`collectPrivates`
    // 的契约，故意不带 seat），所以头像只能按 `kHostSeat` 反查成员表 ——
    // 拿不到就是空串，整块不渲染（绝不虚构一个发送者头像）。
    final avatar = feedAvatarOfSeat(scope.session.state, kHostSeat);

    // 只把「末条 seq / 归属 / 我的座位」交给 tracker，判据不在本文件里重复一次。
    final lastSeq = rows.isEmpty ? 0 : _seqOf(rows.last);
    if (lastSeq != _checkedSeq) {
      final prev = _tracker.lastSeq ?? -1;
      _checkedSeq = lastSeq;
      _flash = _tracker.check(
            lastSeq: lastSeq,
            // 私密信息恒由 KP 发出；`mySeat == kHostSeat` 时「自己发的不闪」。
            lastSeat: rows.isEmpty ? '' : kHostSeat,
            mySeat: scope.session.seat,
          ) ==
          true;
      _fresh = _flash
          ? <int>{
              for (final r in rows)
                if (_seqOf(r) > prev) _seqOf(r),
            }
          : <int>{};
    }

    // ★ P17 KP-4（用户：「只给你看」比聊天栏短）：与 `gp_feeds.dart` 同一口径。
    //   dock 三格本就等高（room_layout.dart:146-154 三块 flex:1、:325-328
    //   stretch），但 `_slotView` 给 gpChat / gpLog / gpPriv 包了一层竖向
    //   `SingleChildScrollView`（room_game_page.dart:779-791）⇒ 块体拿到的
    //   `maxHeight == infinity`，而 `SectionBox` 内层是
    //   `Column(mainAxisSize.min)`（room_panel_kit.dart:75-77）——Card 只按
    //   内容撑高。聊天块多一个 `ChatInputRow`，于是比本块高出一行。
    //   修法：本块补一条与 [kChatInputRowHeight] 等高的**纯空白占位**，
    //   三块 Card 由「内容等高」天然等高（实测差值 0）。
    //   （无界约束下让 Card「吃满格子」需要 `Expanded`，那会忽略本 widget 的
    //   `height` 参数 —— 既有 feeds 用例靠它钳列表视口；且真要填满得改
    //   `_slotView`，不归本批。）
    //   ★ 默认 `height`（220）一个字都不改：`p16_wave1_theme_test.dart:100-103`
    //     把 `const GpPrivates().height` 钉死在 220。
    // ★ PV-3：`privRowsOf` / `collectPrivates` 是**正序、最新在最后**
    //   （`test/room_ui_feeds_test.dart:353-354` 钉死 `rows.last.text`），
    //   裸 `ListView.builder` 会从 index 0（最旧）画起 —— 格子有限时用户
    //   看到的全是旧条。改用 [_PrivatesList]：自带 `ScrollController`，
    //   首帧贴底 + 末条 seq 变化跟随，**保持正序口径逐字不动**（绝不用
    //   `reverse: true` 偷懒，那会打破 `rows.last` 断言）；并保留 P0-06：
    //   用户主动上滚看历史时不强制拉回。
    final Widget content = rows.isEmpty
        ? Center(
            child: Text(
              '暂无私密信息',
              key: GpPrivatesKeys.empty,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        : _PrivatesList(
            rows: rows,
            avatar: avatar,
            fresh: _fresh,
            onRowTap: _openOne,
          );
    return SectionBox(
      title: '只给你看',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 克制的一次性反馈：一个小「新」角标（与聊天 / 记录三栏一致）。
          if (_flash)
            RoomTap(
              key: GpPrivatesKeys.flash,
              label: '新',
              hint: '本块有新消息，点一下收起',
              // ★ P16：与「全屏」统一 44×32（`gp_feeds` 同口径）。
              minSize: RoomBtnSize.trailingSm,
              onTap: () => setState(() => _flash = false),
            ),
          RoomTap(
            key: GpPrivatesKeys.fullscreen,
            icon: Icons.fullscreen,
            hint: '全屏查看私密信息',
            minSize: RoomBtnSize.trailingSm,
            onTap: () => _openFullscreen(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(height: widget.height, child: content),
          // 与聊天输入行等高：三块 Card 才等高（纯空白，不渲染控件）。
          const SizedBox(height: kChatInputRowHeight),
        ],
      ),
    );
  }

  void _openOne(BuildContext context, Map<String, Object?> row) {
    final String title = roomText(row['title']);
    final String text = roomText(row['text']);
    // ★ 2.36.0 / Q5：全文弹层不截断、显式取 `colorScheme.onSurface`。
    //   改前裸 `Text` 无 style，依赖 DefaultTextStyle；而列表行用的
    //   `bodySmall` 被 `theme.dart:251` 写死 `Palette.textMute`
    //   （暗色 0xFF66748C），压在 surface 0xFF161F2E 上对比度不足，正是用户
    //   「深色主题深色字看不见」的真因。空正文时回落显示标题，保证
    //   「有新消息」必然有可见内容。
    final String full = text.trim().isEmpty
        ? (title.trim().isEmpty ? '（无线索内容）' : title)
        : text;
    showRoomSheet<void>(
      context: context,
      title: title.isEmpty ? '私密信息' : title,
      body: (BuildContext ctx) => Text(
        full,
        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              color: Theme.of(ctx).colorScheme.onSurface,
            ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    // ★ PV-3：改前把 `build` 派生的 `rows` / `avatar` 当参数传进来，body
    //   闭包直接捕获那份不可变 `List<Map>` ⇒ 弹层开着时新私密信息一条都
    //   不会出现（快照）。现在 body 内订阅 `RoomScope.of(context)` 并
    //   **重新派生** `privRowsOf(state, seat, limit: widget.limit)`，与
    //   `gp_feeds.dart` 的 `_LiveFeedBody` 同一套订阅式写法。
    //   标题里的条数只是打开瞬间的派生值（`showRoomSheet.title` 是 String，
    //   不能订阅；用 `RoomScope.read` 只取不订阅，避免在回调里建依赖）；
    //   它不参与 body 取数，不会造成快照问题。
    final RoomScope scope = RoomScope.read(context);
    final int count = privRowsOf(scope.session.state, scope.session.seat,
            limit: widget.limit)
        .length;
    showRoomSheet<void>(
      context: context,
      title: '只给你看（$count）',
      body: (BuildContext _) => _LivePrivatesBody(limit: widget.limit),
    );
  }
}

/// 全屏弹层里的**订阅式**私密列表 body（PV-3）。
///
/// 改前全屏按钮把 `build` 派生的 `rows` 快照塞进裸 `ListView`，闭包捕获
/// 一份不可变旧 List —— 会话再怎么通知，弹层里画的还是打开那一刻的几条。
/// `showRoomSheet` 已经在 body 之外重新提供了 `RoomScope`
/// （`room_sheet.dart:69-74`，`InheritedNotifier<RoomSession>`），所以这里
/// 在 `build` 里用 `RoomScope.of(context)` **订阅会话并重新派生** rows：
/// 每来一条新私密信息，本 widget 就重建，交给 [_PrivatesList] 的永远是
/// 当前最新数据 —— 全屏「更新」按钮因此变成冗余但无害（GL-2b：按钮保留、
/// 改自动实时；全局壳 `room_sheet.dart` 零 diff、不动 `refreshTopSheet()`）。
///
/// 与主页 `GpPrivates` 口径完全一致：`limit` 透传、`feedAvatarOfSeat`
/// 反查 KP 头像、`privRowsOf` / `collectPrivates` **正序、最新在最后**
/// 逐字不动；[_PrivatesList] 负责首帧贴底 + 末条 seq 跟随（保留 P0-06）。
///
/// ★ 纯弹层单测可能不提供 RoomScope（页面里 GpPrivates 自身必须有作用域，
///   生产路径不会出现），这里做一次可空防御：无作用域时渲染空列表而不是
///   命中断言。有作用域时才走 `RoomScope.of` 建立订阅。
/// ★ GL-2b 失效点 3（与 `gp_feeds.dart` `_LiveFeedBody` 同处理）：全局壳
///   `room_sheet.dart:66` 的外层 `SingleChildScrollView` 一旦可滚会掩盖
///   内层贴底。C8 禁改全局壳，所以在弹层内用 `LayoutBuilder` 把内层高度
///   钳在父约束内（有界取 min、无界仍用 0.6H），并用
///   `NotificationListener` 只消费内层 overscroll，避免外层接力回弹。
class _LivePrivatesBody extends StatelessWidget {
  const _LivePrivatesBody({required this.limit});

  final int limit;

  @override
  Widget build(BuildContext context) {
    final RoomScope? maybe =
        context.getInheritedWidgetOfExactType<RoomScope>();
    final List<Map<String, Object?>> rows;
    final String avatar;
    if (maybe == null) {
      rows = const <Map<String, Object?>>[];
      avatar = '';
    } else {
      // 订阅：session.notifyListeners() 会触发本 widget 重建。
      final RoomScope scope = RoomScope.of(context);
      final Map<String, Object?> state = scope.session.state;
      rows = privRowsOf(state, scope.session.seat, limit: limit);
      // 私密信息恒由 KP 发出：头像按 kHostSeat 反查成员表（与主页同口径）。
      avatar = feedAvatarOfSeat(state, kHostSeat);
    }
    final double screenH = MediaQuery.of(context).size.height;
    return KeyedSubtree(
      key: GpPrivatesKeys.liveBody,
      child: LayoutBuilder(
        builder: (BuildContext _, BoxConstraints constraints) {
          final double bounded = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : screenH * 0.6;
          final double height =
              screenH * 0.6 > bounded ? bounded : screenH * 0.6;
          return NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) =>
                n is OverscrollNotification,
            child: SizedBox(
              height: height,
              child: rows.isEmpty
                  ? const Text('暂无私密信息')
                  : _PrivatesList(rows: rows, avatar: avatar),
            ),
          );
        },
      ),
    );
  }
}

/// 私密栏的**正序贴底列表**（主页 / 全屏共用，PV-3）。
///
/// `privRowsOf` / `collectPrivates` 返回**时间正序、最新在最后**
/// （`test/room_ui_feeds_test.dart:353-354` 钉死 `rows.last`），绝不能用
/// `reverse: true` 偷懒改口径。这里显式挂 `ScrollController`，首帧贴底 +
/// 末条 seq 变化时跟随，与 `gp_feeds.dart` 的 `FeedList` 完全同一套判据
/// （含「成功 jumpTo 之后才置首帧 flag」「二次 postframe 校正懒构建低估」
/// 两条 GL-2b 修复）。
///
/// ★ 保留 P0-06：`didUpdateWidget` 只在「本来贴底」时跟随；用户主动
///   上滚看历史时 `_atBottom()` 为 false，绝不抢滚动位置。
class _PrivatesList extends StatefulWidget {
  const _PrivatesList({
    required this.rows,
    required this.avatar,
    this.fresh = const <int>{},
    this.onRowTap,
  });

  final List<Map<String, Object?>> rows;
  final String avatar;

  /// 本帧要标记为「新条」的 seq 集合（主页高亮用；全屏传空集）。
  final Set<int> fresh;

  /// 点某条 → 弹层给全文。主页传 `_openOne`；全屏不传（只读）。
  final void Function(BuildContext context, Map<String, Object?> row)? onRowTap;

  @override
  State<_PrivatesList> createState() => _PrivatesListState();
}

class _PrivatesListState extends State<_PrivatesList> {
  final ScrollController _sc = ScrollController();

  /// 首帧贴底是否**已成功执行**（成功后不再抢用户的滚动位置）。
  bool _initialJumpDone = false;

  /// 已排入队但尚未跑完的首帧贴底回调（避免同帧多次 rebuild 重复排帧）。
  bool _initialJumpPending = false;

  /// 上一次成功贴底时用过的 max（供二次校正判断「用户没动过位置」）。
  double _lastStickExtent = -1;

  @override
  void initState() {
    super.initState();
    _scheduleInitialJump();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  static int _seqOf(Map<String, Object?> row) =>
      (row['seq'] is num) ? (row['seq']! as num).toInt() : 0;

  bool _jumpToBottom() {
    if (!mounted || !_sc.hasClients) return false;
    _lastStickExtent = _sc.position.maxScrollExtent;
    _sc.jumpTo(_lastStickExtent);
    return true;
  }

  /// 二次 postframe 校正：懒构建首帧会低估 `maxScrollExtent`（多行长文本
  /// 真实高度 > 估算），jumpTo 后 max 变大 ⇒ 再补一次才真贴底。
  /// 只在「pixels 仍停在上次贴底位置」时补跳 —— 用户一旦改过滚动位置，
  /// 立刻放弃，绝不把位置抢回来（P0-06）。
  void _correctBottomAfterLayout() {
    if (!mounted || !_sc.hasClients) return;
    final pos = _sc.position;
    if (_lastStickExtent < 0 || (pos.pixels - _lastStickExtent).abs() > 1.0) {
      return;
    }
    if (pos.maxScrollExtent - pos.pixels > 0.5) _jumpToBottom();
  }

  void _scheduleInitialJump() {
    if (_initialJumpDone || _initialJumpPending || widget.rows.isEmpty) {
      return;
    }
    _initialJumpPending = true;
    WidgetsBinding.instance
        .addPostFrameCallback((Duration _) => _tryInitialJump());
  }

  void _tryInitialJump() {
    if (_initialJumpDone) {
      _initialJumpPending = false;
      return;
    }
    if (!mounted) {
      _initialJumpPending = false;
      return;
    }
    // ★ GL-2b 失效点 1/2：改前在 `addPostFrameCallback` **之前**就置
    //   `_initialJumpDone = true`，回调里 `!_sc.hasClients`（bottom sheet
    //   入场动画 / 首帧未 attach）直接 return ⇒ flag 已 true、
    //   `didUpdateWidget` 不再补跳、且 `_atBottom()` 在 pixels≈0 时为
    //   false ⇒ 永久停在顶部。现在只在**成功 jumpTo 之后**置位，失败保留
    //   flag 待下帧重试。
    if (!_sc.hasClients || !_jumpToBottom()) {
      _initialJumpPending = false;
      _scheduleInitialJump();
      return;
    }
    _initialJumpDone = true;
    _initialJumpPending = false;
    // 二次 postframe 校正（懒构建低估 max）。
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _correctBottomAfterLayout();
    });
  }

  /// 末条 seq 是否推进（cap 打满、长度不变也要跟随）。
  bool _tailChanged(_PrivatesList old) {
    final List<Map<String, Object?>> now = widget.rows;
    final List<Map<String, Object?>> before = old.rows;
    if (now.isEmpty || before.isEmpty) return now.length != before.length;
    return _seqOf(now.last) != _seqOf(before.last);
  }

  bool _atBottom() {
    if (!_sc.hasClients) return true;
    final pos = _sc.position;
    return pos.maxScrollExtent - pos.pixels < 32;
  }

  @override
  void didUpdateWidget(covariant _PrivatesList old) {
    super.didUpdateWidget(old);
    // 空 → 非空，或首帧贴底还没成功（弹层入场动画未 attach）→ 补跳/重试。
    if (!_initialJumpDone && widget.rows.isNotEmpty) {
      _scheduleInitialJump();
      return;
    }
    // 只有本来就在底部才跟随；用户上滚回看时不抢滚动位置（P0-06）。
    if (!_tailChanged(old) || !_atBottom()) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!_jumpToBottom()) return;
      WidgetsBinding.instance.addPostFrameCallback((Duration __) {
        _correctBottomAfterLayout();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: GpPrivatesKeys.list,
      controller: _sc,
      primary: false,
      // 与 `gp_feeds.dart` 的 `FeedList` 同口径：贴底几何不被设备状态栏
      // 的 MediaQuery padding 整体下推。
      padding: EdgeInsets.zero,
      itemCount: widget.rows.length,
      itemBuilder: (BuildContext context, int i) {
        final Map<String, Object?> r = widget.rows[i];
        final int seq = _seqOf(r);
        return GpPrivatesRow(
          key: GpPrivatesKeys.row(seq),
          text: roomText(r['text']),
          title: roomText(r['title']),
          avatar: widget.avatar,
          highlighted: widget.fresh.contains(seq),
          onTap: widget.onRowTap == null
              ? null
              : () => widget.onRowTap!(context, r),
        );
      },
    );
  }
}

/// 私密栏的一行（对外公开字段，供测试断言高亮与文案）。
class GpPrivatesRow extends StatelessWidget {
  const GpPrivatesRow({
    super.key,
    required this.text,
    this.title = '',
    this.avatar = '',
    this.highlighted = false,
    this.onTap,
  });

  final String text;
  final String title;

  /// 发送方（KP）的缩略 dataURI；空串 → 不渲染头像（对齐老 APP 的
  /// `feedAvatar`：没有成员记录又不给 label 时返回 null，不留空位）。
  final String avatar;

  /// 新条高亮（P2-05：只有高亮，没有动画播报）。
  final bool highlighted;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted ? scheme.primaryContainer : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (avatar.isNotEmpty) ...<Widget>[
            AvatarThumb(
              key: GpPrivatesKeys.avatar,
              relPath: avatar,
              name: 'KP',
              size: 16,
              border: false,
              fallback: AvatarDot(name: 'KP', size: 16),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              // ★ 2.36.0 / Q5：空正文（KP 只填标题就递）时至少显示标题，
              //   否则私密栏只剩一个红点、看不到任何消息内容。
              text.trim().isEmpty
                  ? (title.trim().isEmpty ? '（无线索内容）' : title)
                  : text,
              // ★ 2.36.0 / Q5：必须显式给 `onSurface`。`bodySmall` 被
              //   `theme.dart:251` 写死 `Palette.textMute`（暗色 0xFF66748C，
              //   亮色 0xFF8B8095），对比度不足；`onSurface` 亮/暗两套皮肤
              //   都是高对比正文色，与 `room_panel_kit.dart:83-92` 的
              //   SectionBox 标题同一套修法。
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                  ),
              // 列表行仍是 3 行摘要（不挤压 220dp 块高）；长正文由
              // `_openOne` 的全文弹层（不截断）完整呈现。
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: content);
  }
}
