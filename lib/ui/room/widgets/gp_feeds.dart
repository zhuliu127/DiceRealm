// ============================================================
// widgets/gp_feeds.dart — 块 8/9（KP）/ 4/5（PL）：聊天与游戏记录
//
// 三件东西：
//   · [FeedList]  懒构建列表（`ListView.builder`）+ 上滚不停底；
//   · [FeedRow]   五类分派（sys / chat / dice / check / opposed，note 归 sys 侧）；
//   · [ChatInputRow] 输入行 —— **建页挂一次**：草稿与光标存在自己的 State 里，
//     会话重绘（别人的消息进来）不会重建它，也就不会吞掉正在打的字（T-10）。
//
// ★ C6 / T-11：`redacted` 行**只渲染 text**，不解析、不还原、不加「点击查看」。
// ★ §0.2 / T-12：一切文案都来自 view/feed_view.dart 的纯函数，绝不出现
//   原始 JSON 键名（例如 t / vis / p 这类线上的信封字段）。
// ★ T-43：所有可点元素走 RoomTap；输入行是唯一允许的裸 TextField。
// ★ P2-05：新消息角标由 `FeedFlashTracker.check()` 单独裁定，本文件只负责
//   「怎么把结果画出来」，绝不在这里另写一套「该不该闪」的判断。
//   连接层「补拉世代」(RoomSession.syncEpoch) 变化只用来 reset 基线 ——
//   那是「这批是历史/补课」的连接层事实，不是第二条闪烁判据。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_types.dart';
import '../../widgets/avatar_picker.dart' show AvatarThumb;
import '../room_feed_flash.dart' show FeedFlashTracker;
import '../room_keys.dart';
import '../room_scope.dart';
import '../room_theme.dart';
import '../room_ui_local.dart' show RoomUiLocal;
import '../sheets/room_sheet.dart';
import '../sheets/sheet_ai_rp.dart' show openAiRpSheet;
import '../sheets/sheet_chat_composer.dart'
    show ChatComposerKeys, showChatComposer;
import '../view/feed_view.dart';
import 'room_button_size.dart' show RoomBtnSize, clampBtnText;
import 'room_panel_kit.dart';

/// 信息流来源：记录（logs+dice 合并）/ 聊天（chats）。
enum FeedPane { record, chat }

/// 信息流里可被测试 / 块层引用的稳定 key。
class GpFeedsKeys {
  const GpFeedsKeys._();

  static const Key list = ValueKey<String>('gpFeeds/list');
  static const Key fullscreen = ValueKey<String>('gpFeeds/fullscreen');
  static const Key send = ValueKey<String>('gpFeeds/send');
  static const Key empty = ValueKey<String>('gpFeeds/empty');

  /// AI RP 入口（PRD P1-12：聊天输入行的魔棒图标，结果**只填输入框不发**）。
  static const Key aiRp = ValueKey<String>('gpFeeds/aiRp');

  /// P2-05 新消息角标（`gpFeeds/flash/<pane>`）。按 pane 区分，两个信息流
  /// 同屏时不会撞 key，测试也能逐列断言「只有该闪的那列闪」。
  /// 没有新消息时整块不渲染，所以 `findsNothing` 是有效断言。
  /// 它是「新增角标」，不是持续动画：不持有定时器、不持有动画控制器。
  static Key flash(FeedPane pane) =>
      ValueKey<String>('gpFeeds/flash/${pane.name}');

  /// 单行的派生 key（`gpFeeds/row/<seq>`），断言「某条在不在」用。
  static Key row(int seq) => ValueKey<String>('gpFeeds/row/$seq');

  /// 单行左侧头像（`gpFeeds/avatar/<seq>`）。没有头像时整块不渲染，
  /// 所以 `findsNothing` 是有效断言（P10 第 2 期 A）。
  static Key avatar(int seq) => ValueKey<String>('gpFeeds/avatar/$seq');

  /// ★ P11：一条未结算检定上的「花 N 点幸运改为成功」按钮。
  /// 不可花时**整块不渲染** → `findsNothing` 是有效断言。
  static Key luck(int seq) => ValueKey<String>('gpFeeds/luck/$seq');

  /// ★ P11：同一条上的「推动检定（重掷一次）」按钮。
  static Key push(int seq) => ValueKey<String>('gpFeeds/push/$seq');

  // ---- P10 第 7 期 C 批 A：全屏编辑 / 实时全屏 ----
  //   （GL-2a / I13 已移除「最新 4 条」提示标签及其 key，取数上限不动）

  /// 聊天输入行旁的独立「全屏编辑」入口（旁观者不渲染）。
  ///
  /// 为什么要第二个入口：输入框自身的 `onTap` 已经能开全屏，但用户未必知道；
  /// 一个常驻图标把「可以放大检查」这件事显式化。
  static const Key chatFullscreen = ValueKey<String>('gpFeeds/chatFullscreen');

  /// 全屏编辑页根（`ChatComposerKeys.root` 的别名，避免两套 key）。
  static const Key chatComposer = ChatComposerKeys.root;

  /// 全屏编辑页的多行输入框。
  static const Key chatComposerField = ChatComposerKeys.field;

  /// 全屏编辑页「完成」。
  static const Key chatComposerDone = ChatComposerKeys.done;

  /// 全屏编辑页「发送」。
  static const Key chatComposerSend = ChatComposerKeys.send;

  /// 全屏页里那份**订阅式**列表的根（测试用它把查找限定在全屏页内）。
  ///
  /// ★ P20 需求 3⑥b：全屏壳从 `showRoomSheet`（底部弹层）换成
  ///   `showFullscreenReader`（真路由），键名与语义保持不变。
  static const Key liveBody = ValueKey<String>('gpFeeds/liveBody');

  // ★ GL-2a / I13：原 `latestHint`（SectionBox 上「最新 4 条」标签的 key）
  //   已随文案一并删除，不留孤儿键。取数上限 `RoomTheme.feedCap=120` /
  //   `chatCap=60` 与 `collectFeeds(state, limit:)` / `_tail(out, limit)`
  //   **一个字节都没动** —— 列表仍实时显示全部最新消息。
}

/// 块 8/9/4/5 的外壳：标题 + 新消息角标 + 全屏 + 列表（+ 聊天输入行）。
///
/// 不自己订阅会话：调用方（`RoomGamePage`）的子树已经在 `RoomScope` 之下，
/// 而块内只做一次只读派生，成本可忽略；`local` 的变化由外层 ListenableBuilder 管。
///
/// ★ 为什么改成 StatefulWidget：[FeedFlashTracker] 必须跨重建记住基线，
///   而 `GpFeeds` 每次会话事件都会重建。一个 `GpFeeds` 实例 = 一个 pane =
///   一个 tracker —— 记录列与聊天列各自观察自己的展示序列，互不干扰（P2-05）。
///
/// ★ Round 2：断线补拉要显式重置基线。重连时 RemoteSession 对象不换
///   （座位不变 → client 不重建），`identical` 感知不到；改由连接层的
///   `syncEpoch` 世代变化触发 reset。不再用全局 seq 差值猜「是不是补拉」。
///
/// ★ 测试硬约束：`testWidgets` 跑在 FakeAsync 下，真实 Timer /
///   AnimationController 的 Future 永不完成。所以这里**没有**任何延时消退：
///   角标是「本次 build 派生的状态标记」，由下一条新消息重新判定、或用户
///   点一下收起而自然消失。判据本身可注入（[flashTracker]），测试可直接驱动。
class GpFeeds extends StatefulWidget {
  const GpFeeds({
    super.key,
    required this.pane,
    this.height = 220,
    this.limit,
    this.title,
    this.flashTracker,
    this.locked = false,
    this.fill = false,
  });

  final FeedPane pane;

  /// 列表可视高度（块在 Wrap 里没有外部高度约束，必须自带）。
  ///
  /// ★ 只在 [fill] == false 时生效。
  final double height;

  /// 覆盖默认上限（记录 120 / 聊天 60）。
  final int? limit;

  final String? title;

  /// 可注入的闪烁判据（接线测试用）；null → 本 pane 自建一个实例。
  /// 生产侧两列各自 new 一个，不需要外部注入。
  final FeedFlashTracker? flashTracker;

  /// P17 G-1：操作锁（昏迷 / 濒死 / 疯狂发作；**不含撕卡**）。
  ///
  /// ★ 用户口径：「玩家昏迷或疯狂时什么都不能操作，只能点『推进 1 轮』和
  ///   『更多工具』」。锁定判据本来只接到工具栏与骰子条，**聊天发送漏网**，
  ///   这里补上：锁定态只让「不能输入 / 不能发」，历史照常可看。
  /// ★ **只对 `pane == chat` 生效**：记录 / 私密面板不渲染输入行，传了也忽略
  ///   （`_GpFeedsState.build` 里只把值递给 `ChatInputRow`）。
  /// ★ 默认 `false`：不传时行为逐字不变；撕卡仍可聊天（裁决 A：`!ripped`）。
  final bool locked;

  /// 吃满父级高度模式（2.42.0 / P20 需求 3⑦）。
  ///
  /// · `false`（默认）：**旧路径逐字不变** —— 列表恒为
  ///   `SizedBox(height: widget.height)`，记录栏再补一条
  ///   [kChatInputRowHeight] 等高占位（P17 KP-4 的三块等高）。
  ///   `test/p10_t7_c_feeds_test.dart:141/241/275` 正是靠 `height: h*4`
  ///   把视口钳成 4 行来验首帧贴底 / 上滚不拉底 —— 一改这 3 条必红。
  /// · `true`：`Expanded(FeedList)` + 底部输入行（记录栏换成等高占位），
  ///   整块吃满父级高度，外层不再被迫滚（需求 3⑦ 的「输入行固定在底部」）。
  ///   必须配合 [SectionBox.expand]（本 widget 内部已传 `expand: fill`）。
  ///
  /// ★ 这是**开关而非改行为**：`gp_feeds.dart` 同时服务 KP 侧
  ///   （`gpChat` / `gpLog`）与玩家侧（`gpPlChat` / `gpPlLog`），KP 侧与
  ///   折叠档一个参数都不传 ⇒ 回归面为零。只有玩家 dock 的两个信息流传 true。
  /// ★ 调用约束：`fill` 要求父级给出**有界高度**（dock 格 / `Scaffold.body`）；
  ///   放进 `SingleChildScrollView` 这类无界父级会撞「unbounded height」断言。
  final bool fill;

  @override
  State<GpFeeds> createState() => _GpFeedsState();
}

class _GpFeedsState extends State<GpFeeds> {
  late FeedFlashTracker _tracker;

  /// 上次绑定的会话对象。换房间 / 会话重新装配时用它触发 `reset()`。
  Object? _boundSession;

  /// 上次绑定的连接层同步世代。断线补拉不换会话对象，靠世代 +1 触发
  /// `reset()` —— 这是修复「短断线补拉误闪」的关键信号。初值 -1 表示
  /// 尚未绑定，保证首屏一定走一次登记基线的分支。
  int _boundEpoch = -1;

  /// 上次判过的「展示序末条 seq」。同一批数据重绘不重复判，也不清角标。
  int _checkedSeq = -1;

  /// 当前是否显示新消息角标（纯派生状态，无动画、无定时器）。
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    _tracker = widget.flashTracker ?? FeedFlashTracker();
  }

  @override
  void didUpdateWidget(covariant GpFeeds old) {
    super.didUpdateWidget(old);
    if (!identical(old.flashTracker, widget.flashTracker)) {
      _tracker = widget.flashTracker ?? FeedFlashTracker();
      _checkedSeq = -1;
      _flash = false;
    }
  }

  /// 取「展示序末条」的 seq / seat（与旧版 `feedFlashCheck` 取数组末条同口径），
  /// 然后**只**把判定交给 [FeedFlashTracker.check]。
  ///
  /// 不在这里写任何「首次 / 自己发的 / 无新增」判断 —— 三条规则全在 tracker
  /// 里；UI 只负责选数据 + 显示结果，也不比较 seq 差值的大小（那是全局事件
  /// 序号，差值不代表本列新增条数、更不代表是否补拉）。
  bool _deriveFlash(List<FeedItem> items, String mySeat) {
    final lastSeq = items.isEmpty ? 0 : items.last.seq;
    if (lastSeq == _checkedSeq) return _flash;
    _checkedSeq = lastSeq;
    final lastSeat = items.isEmpty ? '' : items.last.seat;
    _flash = _tracker.check(
          lastSeq: lastSeq,
          lastSeat: lastSeat,
          mySeat: mySeat,
        ) ==
        true;
    return _flash;
  }

  /// ★ P11：给「我自己最近一条失败检定」准备行尾动作区（花幸运 / 推动）。
  ///
  /// 判定全在纯视图函数 [checkActionOf] 里（与权威端同一口径），这里只负责
  /// 「谁是最近的」+「点了发什么」。**不可操作时返回空 map** → 一个按钮都不渲染。
  Map<int, Widget> _checkActionsOf(
    RoomScope scope,
    Map<String, Object?> state,
    List<FeedItem> items,
    FeedPane pane,
  ) {
    if (pane != FeedPane.record) return const <int, Widget>{};
    final mySeat = scope.session.seat;
    final role = scope.session.role;
    if (mySeat.isEmpty) return const <int, Widget>{};
    final luck = selfLuckOf(state, mySeat);
    // 权威端 `lastDiceOf(seat)` = 该座位最后一条骰；这里按同一口径算，
    // 避免「按钮亮着但点了被权威端拒绝」。
    final latestBySeat = <String, int>{};
    for (final it in items) {
      if (it.kind == FeedKind.dice) latestBySeat[it.seat] = it.seq;
    }
    final out = <int, Widget>{};
    for (final it in items) {
      final a = checkActionOf(
        it,
        mySeat: mySeat,
        role: role,
        isLatestOfSeat: latestBySeat[it.seat] == it.seq,
        luck: luck,
      );
      if (a == null) continue;
      out[it.seq] = _checkActionBar(scope, a);
    }
    return out;
  }

  Widget _checkActionBar(RoomScope scope, FeedCheckAction a) {
    final who = a.label.isEmpty ? '这次检定' : '「${a.label}」';
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (a.canLuck)
          RoomTap(
            key: GpFeedsKeys.luck(a.seq),
            label: a.luckLabel,
            icon: Icons.auto_fix_high,
            minSize: const Size(132, 30),
            hint: '花 ${a.luckAmount} 点幸运把$who的骰值压到目标值以内',
            onTap: () => scope.controller.sendIntent(
              RoomIntent.dice,
              <String, Object?>{'luck': true, 'amount': a.luckAmount},
            ),
          ),
        if (a.canPush)
          RoomTap(
            key: GpFeedsKeys.push(a.seq),
            label: FeedCheckAction.pushLabel,
            icon: Icons.refresh,
            minSize: const Size(132, 30),
            hint: '重掷一次·同一技能值与难度；推动失败的后果由 KP 加重',
            onTap: () => scope.controller.sendIntent(
              RoomIntent.dice,
              <String, Object?>{'push': true},
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final int epoch = scope.session.syncEpoch;
    // 会话对象被替换（换房间 / 会话重新装配），或连接层完成一次全量补拉
    // （syncEpoch +1）→ 重置基线：这两种情况接下来看到的一批都是「历史 /
    //  补课」，不是新消息。
    // ★ 断线重连时 RemoteSession 对象不换，只能靠世代变化感知；不再用
    //   全局 seq 差值猜补拉（差值被多列交错放大、又在短断线时太小，两头错）。
    // ★ 顺序要点：清 `_checkedSeq = -1` 让**本次** build 仍能重新走进
    //   `_deriveFlash`，由刚 reset 的 tracker 重新登记首屏基线（返回 null 不闪）；
    //   否则短路会跳过登记，补拉后第一条真消息反被当成首次而漏闪。
    if (!identical(scope.session, _boundSession) || epoch != _boundEpoch) {
      _boundSession = scope.session;
      _boundEpoch = epoch;
      _tracker.reset();
      _checkedSeq = -1;
      _flash = false;
    }

    final state = scope.session.state;
    final pane = widget.pane;
    final items = pane == FeedPane.chat
        ? collectChats(state, limit: widget.limit ?? RoomTheme.chatCap)
        : collectFeeds(state, limit: widget.limit ?? RoomTheme.feedCap);
    final label =
        widget.title ?? (pane == FeedPane.chat ? '聊天' : '游戏记录');
    final flashing = _deriveFlash(items, scope.session.seat);
    final actions = _checkActionsOf(scope, state, items, pane);

    // ★ P17 KP-4（用户：「游戏记录」「只给你看」比聊天栏短）：
    //   根因不是 flex、也不是 `GpPrivates` 的 220 —— dock 三格本就等高
    //   （room_layout.dart:146-154 三块 flex:1、:325-328 stretch）。真正的差值
    //   来自**聊天块多一个 `ChatInputRow`**，而 `SectionBox` 内层是
    //   `Column(mainAxisSize: MainAxisSize.min)`（room_panel_kit.dart:75-77），
    //   Card 只按内容撑高、不填满格子（stretch 只保证**格子**等高）。
    //   修法：记录栏补一条与 [kChatInputRowHeight] 等高的**纯空白占位**，
    //   三块 Card 由「内容等高」天然等高（实测差值 0）。
    //
    // ★ 为什么不用 `LayoutBuilder` + `Expanded` 让 Card「吃满格子」
    //   （gp_combat_list.dart:221-230 那种范式）：这里的格子高度是**无界**的 ——
    //   `_slotView` 给 gpChat / gpLog / gpPriv 包了一层竖向
    //   `SingleChildScrollView`（room_game_page.dart:779-791），块体拿到的
    //   `maxHeight == infinity`；无界约束下套 `Expanded` 直接断言失败。
    //   而「有界就展开」又会**忽略本 widget 的 `height` 参数** ——
    //   `p10_t7_c_feeds_test.dart:141/241/275` 正是靠 `height: h*4` 把列表
    //   视口钳成 4 行来验首帧贴底 / 上滚不拉底，一展开这 4 条必红。
    //   要真「填满格子」得改 `_slotView`（不归本批），故本批只保证**等高**。
    //
    // ★ 2.42.0 / P20 需求 3⑦ 补充：上面的结论只对**非 fill** 路径有效。
    //   `fill == true` 时改走 `SectionBox(expand: true)` +
    //   `Expanded(FeedList) + 底部输入行`，整卡吃满格高，外层
    //   `SingleChildScrollView` 不再被迫出现（= 用户说的「双层滚动 / 输入行
    //   被挤到看不见」）。非 fill 路径（KP 侧 + 折叠档 + 既有 3 条
    //   `height: h*4` 用例）**一个字节都没动**。
    final Widget feedList = FeedList(
      items: items,
      pane: pane,
      scrollable: true,
      actions: actions,
    );
    // 底部那一行：聊天栏是输入行；记录栏补一条等高占位（纯空白）。
    final Widget bottomRow = pane == FeedPane.chat
        ? ChatInputRow(locked: widget.locked)
        : const SizedBox(height: kChatInputRowHeight);
    return SectionBox(
      title: label,
      // ★ 只有 fill 模式才吃满高度；默认 false ⇒ 既有渲染逐字不变。
      expand: widget.fill,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ★ GL-2a / I13（用户拍板）：删掉「最新 4 条」这个**误导文案**与
          //   `GpFeedsKeys.latestHint` 键。实际取数上限是
          //   `RoomTheme.feedCap=120` / `chatCap=60`（`collectFeeds` /
          //   `collectChats` → `_tail(out, limit)` 裁的是最近 120/60 条），
          //   「4」只是贴底时视口约可见 4 行的视觉描述，与真实条数不符。
          //   全库没有 `.take(4)`；**若顺手删取数逻辑，反而会真只剩 4 条**，
          //   违背「一直实时更新并显示最新消息」。这里只删文案，主列表一行
          //   不删、`limit` / `feedCap` / `chatCap` / `_tail` 逐字不动。
          // 克制的一次性反馈：一个小「新」角标，不放烟花、不做持续脉冲。
          if (flashing)
            RoomTap(
              key: GpFeedsKeys.flash(pane),
              label: '新',
              hint: '本块有新消息，点一下收起',
              // ★ P16：与「全屏」统一 44×32（改前 40×32，两个 trailing
              //   控件差 4dp）。
              minSize: RoomBtnSize.trailingSm,
              onTap: () => setState(() => _flash = false),
            ),
          RoomTap(
            key: GpFeedsKeys.fullscreen,
            icon: Icons.fullscreen,
            hint: '全屏查看$label',
            minSize: RoomBtnSize.trailingSm,
            // ★ 改前传的是 build 里派生的 `items` 局部快照：闭包捕获后永不刷新，
            //   全屏后新消息一条都不出现。改成订阅式 body —— 全屏路由里
            //   重新提供了 RoomScope（InheritedNotifier），body 内每帧用
            //   `RoomScope.of` 重新派生 items 即可实时跟随会话。
            //
            // ★ 2.42.0 / P20 需求 3⑥b：全屏壳从 `showRoomSheet` 换成
            //   `showFullscreenReader`。旧壳是「底部弹层 + `maxHeight: 0.72H`
            //   + 外层 `SingleChildScrollView`」：不是真全屏，而且外层
            //   ScrollView 会抢内层列表的手势（用户：「全屏也不是全屏」）。
            //   新壳是**真路由**（`Scaffold` + AppBar + 关闭按钮）且会重新
            //   提供 `RoomScope`；`Scaffold.body` 给的是紧约束 ⇒
            //   `FeedList` 的 ListView 能吃满整屏 ⇒ `_scheduleInitialJump`
            //   自然首帧贴底。
            //   全屏里不挂花幸运 / 推动（`actions` 不传），避免第二次发包入口。
            onTap: () => showFullscreenReader<void>(
              context: context,
              title: label,
              child: _LiveFeedBody(pane: pane, limit: widget.limit),
            ),
          ),
        ],
      ),
      child: widget.fill
          // ★ fill：列表吃掉除输入行以外的全部高度 ⇒ 输入行恒在最底、
          //   整卡不超格高、外层不再出现第二个滚动条。
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: feedList),
                bottomRow,
              ],
            )
          // ★ 非 fill：旧路径逐字不变。
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: widget.height,
                  child: feedList,
                ),
                bottomRow,
              ],
            ),
    );
  }
}

/// 全屏页里的**订阅式**信息流 body（P10 第 7 期 C 批 A；P20 需求 3⑥b 改造）。
///
/// 改前全屏按钮把 `_GpFeedsState.build` 的局部 `items` 快照塞进 `FeedList`，
/// 闭包捕获的是一份不可变旧 List —— 会话再怎么通知，弹层里画的还是打开
/// 那一刻的几条。`showFullscreenReader` 已经在页面之外重新提供了 `RoomScope`
/// （`InheritedNotifier<RoomSession>`），所以这里在 `build` 里用
/// `RoomScope.of(context)` **订阅会话并重新派生** items：每来一条新消息，
/// 本 widget 就重建，交给 [FeedList] 的永远是当前最新数据。
///
/// 与主页 `GpFeeds` 的口径完全一致：`limit` 透传、默认 `feedCap/chatCap`、
/// 同样 `scrollable: true`（首帧贴底 + 末条 seq 变化的跟随判据都生效）。
///
/// ★ 2.42.0 / P20 需求 3⑥b：body 不再自己钳高度、不再吞 overscroll 通知。
///   外壳换成 `showFullscreenReader`（真路由 + `Scaffold` + 关闭按钮）后，
///   `Scaffold.body` 给的是**紧**约束，ListView 直接吃满整屏：
///   · 删掉 `LayoutBuilder` 的 `min(0.6H, 父约束)` 高度钳制；
///   · 删掉 `NotificationListener<OverscrollNotification>` 的「阻止冒泡」补丁
///     —— 那是为了骗过 `showRoomSheet` 的外层 `SingleChildScrollView`，
///     新壳里根本没有那层 ScrollView，留着反而会吞掉别的观察者。
///
/// ★ 纯弹层单测可能不提供 RoomScope（页面里 GpFeeds 自身必须有作用域，
///   生产路径不会出现），这里做一次可空防御：无作用域时渲染空列表而不是
///   命中断言。有作用域时才走 `RoomScope.of` 建立订阅。
class _LiveFeedBody extends StatelessWidget {
  const _LiveFeedBody({required this.pane, this.limit});

  final FeedPane pane;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final RoomScope? maybe =
        context.getInheritedWidgetOfExactType<RoomScope>();
    final List<FeedItem> items;
    if (maybe == null) {
      items = const <FeedItem>[];
    } else {
      // 订阅：session.notifyListeners() 会触发本 widget 重建。
      final RoomScope scope = RoomScope.of(context);
      final Map<String, Object?> state = scope.session.state;
      items = pane == FeedPane.chat
          ? collectChats(state, limit: limit ?? RoomTheme.chatCap)
          : collectFeeds(state, limit: limit ?? RoomTheme.feedCap);
    }
    // `KeyedSubtree` 保留 `GpFeedsKeys.liveBody`：既有全屏用例（
    // `p10_t7_c_feeds_test.dart` ③④ / `p11_pv3_fullscreen_tail_test.dart`）
    // 用它把查找限定在「全屏页里那份列表」内，键名与语义都不变。
    return KeyedSubtree(
      key: GpFeedsKeys.liveBody,
      child: FeedList(items: items, pane: pane, scrollable: true),
    );
  }
}

/// 懒构建列表。上滚（未贴底）时不自动跟随最新，避免打断回看（P0-06）。
class FeedList extends StatefulWidget {
  const FeedList({
    super.key,
    required this.items,
    this.pane = FeedPane.record,
    this.scrollable = true,
    this.actions = const <int, Widget>{},
  });

  final List<FeedItem> items;
  final FeedPane pane;

  /// false 时是一次性铺开（弹层/纯断言用）。
  final bool scrollable;

  /// ★ P11：`seq → 该行尾部的动作区`（花幸运 / 推动检定）。
  /// 空 = 全部行都没有动作区（弹层全屏视图就传空，行为与改前一致）。
  final Map<int, Widget> actions;

  @override
  State<FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<FeedList> {
  final ScrollController _sc = ScrollController();

  /// 首帧贴底是否**已经成功执行**（成功后不再抢用户的滚动位置）。
  /// ★ GL-2b 失效点 1：改前在 `addPostFrameCallback` **之前**就置 true，
  ///   回调里 `!_sc.hasClients`（bottom sheet 入场动画 / 首帧未 attach）
  ///   直接 return ⇒ flag 已 true、[didUpdateWidget] 不再补跳、且
  ///   `pixels ≈ 0` 被判成「不贴底」⇒ **永久停在顶部**。现在只在
  ///   「成功执行 jumpTo 之后」置位，失败保留 flag 待下帧重试。
  bool _initialJumpDone = false;

  /// 已排入队但尚未跑完的首帧贴底回调（避免同帧多次 rebuild 重复排帧）。
  bool _initialJumpPending = false;

  /// 「用户想跟着最新一条走」的显式状态（2.42.0 / P20 需求 3⑥a 根因 A）。
  ///
  /// ★ 为什么必须换成显式状态，而不是继续用几何阈值：
  ///   改前的跟随判据是 [didUpdateWidget] 里的 `_atBottom()`
  ///   （`maxScrollExtent - pixels < 32`）。用户点「花幸运」后权威端追加结算
  ///   行，**列表内容在同一帧里变高** ⇒ 旧的 `pixels` 与新的 `max` 立刻差出
  ///   32dp 以上 ⇒ 判据说「不在底部」⇒ 静默早退、永不跟随。更糟的是判据只在
  ///   「末条变了」时才被读一次，用户之后再怎么拖也**无法把这个状态救回来**
  ///   —— 这就是用户报的「花了幸运之后拖不到最新」。
  ///
  /// ★ 现在的语义（三条，QA 可据此写用例）：
  ///   ① 默认 `true`：进页面 / 首次贴底后即「想跟随」；
  ///   ② 任何一次滚动（用户拖动、点击后回弹、程序 jumpTo）都会按
  ///      `pixels >= maxScrollExtent - [_stickSlack]` **重新定值** ——
  ///      用户上滚就变 false（P0-06：不抢滚动位置），**拖回底部自动恢复** false→true；
  ///   ③ 用户点行内动作（花幸运 / 推动）视为「我在看最新」，立即置 true。
  ///
  /// ★ 不用 `setState`：它不参与渲染（只影响下一帧要不要跳），而且滚动通知
  ///   可能在布局 / 滚动的帧内**同步**派发，那里 setState 会撞
  ///   "setState() called during build"。
  bool _stick = true;

  /// 贴底容差（dp）。比旧 `_atBottom()` 的 32dp 收紧：32dp 在行高约 24dp 的
  /// 列表里等于「离底还剩一行半也算贴底」，用户刚上滚一行就被抢回底部；
  /// 8dp 只吸收浮点与像素取整误差。
  static const double _stickSlack = 8;

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

  /// 把滚动位置压到最新一条（当前 `maxScrollExtent`）。
  /// 返回是否真正执行了 jumpTo（未 attach / 已卸载都算失败）。
  bool _jumpToBottom() {
    if (!mounted || !_sc.hasClients) return false;
    _sc.jumpTo(_sc.position.maxScrollExtent);
    return true;
  }

  /// 滚动通知 → 维护 [_stick]。见 [_stick] 的三条语义说明。
  ///
  /// ★ 用 `NotificationListener<ScrollNotification>` 而不是只认
  ///   `UserScrollNotification`：`jumpTo()` 派发的是
  ///   `ScrollStartNotification(dragDetails: null)` + `ScrollUpdateNotification`
  ///   + `ScrollEndNotification`，**不派发** `UserScrollNotification`
  ///   （后者只在滚动方向变化时出现）。只看 User 那条会漏掉
  ///   `test/p10_t7_c_feeds_test.dart:295` 的 `position.jumpTo(0)`
  ///   ——用户「上滚回看」最直接的模拟——于是 P0-06 会假绿。
  ///
  /// ★ `depth == 0`：只认本列表自己的通知。祖先 / 兄弟滚动（玩家 dock 外层
  ///   曾经那层 `SingleChildScrollView`）与「本列表贴不贴底」无关。
  /// ★ 返回值恒 false：**不消费**通知，照常冒泡给祖先与测试探针。
  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth == 0) {
      final ScrollMetrics m = n.metrics;
      _stick = m.pixels >= m.maxScrollExtent - _stickSlack;
    }
    return false;
  }

  /// 二次 postframe 校正（GL-2b 失效点 3）：`ListView.builder` 懒构建时
  /// 首帧 `maxScrollExtent` 按已构建 children 估算，多行长文本的真实高度
  /// 会让估算偏小 ⇒ jumpTo 后 max 变大，没真正贴底。这里再压一次。
  ///
  /// ★ 2.42.0 / P20 需求 3⑥a：删掉旧版
  ///   `if (_lastStickExtent < 0 || (pos.pixels - _lastStickExtent).abs() > 1.0) return;`
  ///   这句「静默放弃」。它正是「花幸运后滚不到最新」的第二半成因：
  ///   内容一变高，`pixels` 与上次记录的 extent 立刻差出 > 1dp，
  ///   于是校正被无条件跳过，列表永远停在「差一点到底」。
  /// ★ 现在只由 [_stick] 把关：用户没动手（还想贴底）就校正；
  ///   用户上滚会被 [_onScrollNotification] **立刻**把 `_stick` 置 false
  ///   ⇒ P0-06「不抢滚动位置」原样成立。
  void _correctBottomAfterLayout() {
    if (!mounted || !_sc.hasClients || !_stick) return;
    final pos = _sc.position;
    if (pos.maxScrollExtent - pos.pixels > 0.5) _jumpToBottom();
  }

  /// ★ P10 第 7 期 C 批 A（用户问题 6）：`collectFeeds/collectChats` 返回
  ///   **时间正序**（最新在最后），而 `ListView.builder` 首帧从第 0 条画起
  ///   —— 格子高度有限时用户看到的全是最旧几条。首次拿到非空 items 时，
  ///   在首帧布局完成后贴底。
  /// ★ 只在「首次」做：用户之后上滚回看时，跟随判据 [_stick] 已被
  ///   [_onScrollNotification] 置 false，[didUpdateWidget] 早退，绝不抢滚动
  ///   位置（P0-06 逐字保留；改前那句判据是几何阈值 `_atBottom()`）。
  void _scheduleInitialJump() {
    if (_initialJumpDone ||
        _initialJumpPending ||
        !widget.scrollable ||
        widget.items.isEmpty) {
      return;
    }
    _initialJumpPending = true;
    WidgetsBinding.instance
        .addPostFrameCallback((Duration _) => _tryInitialJump());
  }

  /// 首帧贴底回调本体：容忍弹层入场动画期间 controller 尚未 attach。
  void _tryInitialJump() {
    if (_initialJumpDone) {
      _initialJumpPending = false;
      return;
    }
    if (!mounted) {
      _initialJumpPending = false;
      return;
    }
    if (!_sc.hasClients || !_jumpToBottom()) {
      // 尚未 attach：下一帧重试，flag 保持 false（不「置位后放弃」）。
      _initialJumpPending = false;
      _scheduleInitialJump();
      return;
    }
    // ★ 成功执行 jumpTo 之后才置位（GL-2b 失效点 1）。
    _initialJumpDone = true;
    _initialJumpPending = false;
    // ★ 二次 postframe 校正（失效点 3：懒构建低估 max）。
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _correctBottomAfterLayout();
    });
  }

  /// 末条 seq 是否推进。
  ///
  /// 改前用 `widget.items.length != old.items.length`：一旦条数打满 cap
  /// （记录 120 / 聊天 60），新消息只是把最旧一条顶掉、长度不变，于是
  /// 跟随逻辑永远不再触发 —— 这是「看不到最新消息」的第二个 bug。
  /// 换锚到「末条 seq」后，cap 打满也能继续跟随。空列表边界仍按长度判，
  /// 避免对空 list 取 `.last`。
  bool _tailChanged(FeedList old) {
    final List<FeedItem> now = widget.items;
    final List<FeedItem> before = old.items;
    if (now.isEmpty || before.isEmpty) return now.length != before.length;
    return now.last.seq != before.last.seq;
  }

  @override
  void didUpdateWidget(covariant FeedList old) {
    super.didUpdateWidget(old);
    // 空 → 非空，或首帧贴底还没成功（弹层入场动画未 attach）→ 补跳/重试。
    if (!_initialJumpDone && widget.scrollable && widget.items.isNotEmpty) {
      _scheduleInitialJump();
      return;
    }
    // ★ 2.42.0 / P20 需求 3⑥a：跟随判据由几何阈值 `_atBottom()` 换成显式
    //   `_stick`。差异只有一处但决定性：`_atBottom()` 是**瞬时几何**，
    //   内容变高的同一帧里必然读成 false；`_stick` 是**用户意图**，
    //   只有用户自己动手才会翻成 false。
    if (!_tailChanged(old) || !_stick) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!_jumpToBottom()) return;
      // 懒构建校正：新末条是多行长文本时，一次 jumpTo 后 max 仍可能低估，
      // 再补一帧压到真实底（与首帧二次校正同口径）。
      WidgetsBinding.instance.addPostFrameCallback((Duration __) {
        _correctBottomAfterLayout();
      });
    });
  }

  /// 行尾动作区 + 「点了行内动作 = 我在看最新」的贴底意图信号。
  ///
  /// ★ 2.42.0 / P20 需求 3⑥a：花幸运 / 推动都是「我要看这条的结算结果」。
  ///   用户此前上滚回看过（`_stick == false`），点完按钮权威端追加结算行时
  ///   若仍不跟随，用户看到的就是「点了没反应 / 滚不到最新」。
  ///   所以在 **pointer down**（早于 InkWell 的 onTap 与 `sendIntent`）把
  ///   `_stick` 置回 true。
  /// ★ 用 `Listener`（默认 `HitTestBehavior.deferToChild`）而不是
  ///   `GestureDetector`：**完全不改命中区与尺寸**，按钮的 InkWell 仍是唯一
  ///   手势识别者 —— `p16_button_unify_test.dart` 那批几何断言零影响。
  Widget? _trailingOf(FeedItem it) {
    final Widget? action = widget.actions[it.seq];
    if (action == null) return null;
    return Listener(
      // 参数类型交给上下文推断（`PointerDownEventListener`），不写死类名。
      onPointerDown: (_) {
        _stick = true;
      },
      child: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          widget.pane == FeedPane.chat ? '还没有人说话' : '暂无记录',
          key: GpFeedsKeys.empty,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (!widget.scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final it in widget.items)
            FeedRow(
              key: GpFeedsKeys.row(it.seq),
              item: it,
              pane: widget.pane,
              trailing: widget.actions[it.seq],
            ),
        ],
      );
    }
    // ★ 不消费通知（`_onScrollNotification` 恒返回 false），只借它维护 `_stick`。
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        key: GpFeedsKeys.list,
        controller: _sc,
        // ★ 显式清零 MediaQuery 内边距：贴底判据与「最后几条完整可见」的
        //   几何才能确定，不会被设备状态栏把内容整体下推（面板本来就不该吃
        //   这段 padding）。GL-2a 只删「最新 4 条」文案，此清零逻辑不动。
        padding: EdgeInsets.zero,
        itemCount: widget.items.length,
        itemBuilder: (BuildContext context, int i) {
          final it = widget.items[i];
          return FeedRow(
            key: GpFeedsKeys.row(it.seq),
            item: it,
            pane: widget.pane,
            trailing: _trailingOf(it),
          );
        },
      ),
    );
  }
}

/// 单行渲染：五类分派。**所有文本都来自纯视图层**，本类不解析任何载荷。
class FeedRow extends StatelessWidget {
  const FeedRow({
    super.key,
    required this.item,
    this.pane = FeedPane.record,
    this.trailing,
  });

  final FeedItem item;
  final FeedPane pane;

  /// ★ P11：行尾动作区（花幸运 / 推动检定）。**只加不挪** ——
  /// 有动作时在原有一行下面另起一行，原 Row 的槽位 / flex / 尺寸一字不动，
  /// 文字宽度也不被挤压（记录栏里「谁·什么技能·掷了多少」是最该读全的一行）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String tag, IconData icon, Color? tint) = _badgeOf(item, theme);
    final text = _textOf(item);
    final who = item.nickname.isNotEmpty
        ? item.nickname
        : (item.seat == kHostSeat ? 'KP' : item.seat);
    // ★ P10 第 3 期 A 批：**骰行也要显示是谁掷的**。
    //   老 APP `room-panels.js:1594` 的骰子块是「昵称 · 1D100 ＝ 42」（行首带一个骰子图标）；
    //   本工程改前只在聊天栏印发言人，于是广播到记录栏的骰行看起来
    //   是「一堆匿名数字」—— 用户据此认为「roll 点没有广播」。
    //   检定 / 对抗行的 text 里权威端已经带了昵称（如「甲 做 SAN Check：…」），
    //   再前置一次会重复，所以只给骰行补。
    final showWho = who.isNotEmpty &&
        (pane == FeedPane.chat || item.kind == FeedKind.dice);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // P10 第 2 期 A（对齐老 APP `feedAvatar`）：条目左侧显示**发言人**的
          // 缩略头像。数据来自 `FeedItem.avatar`（view 层按 seat 反查成员表得来，
          // 是跨设备 dataURI），没有就完全不占位 —— 系统提示 / 无 seat 的条目不画。
          if (item.avatar.isNotEmpty) ...<Widget>[
            AvatarThumb(
              key: GpFeedsKeys.avatar(item.seq),
              relPath: item.avatar,
              name: who,
              size: 18,
              border: false,
              fallback: AvatarDot(name: who, size: 18),
            ),
            const SizedBox(width: 4),
          ],
          SizedBox(
            width: 22,
            child: Icon(icon, size: 14, color: tint),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall,
                children: <InlineSpan>[
                  if (tag.isNotEmpty)
                    TextSpan(
                      text: '[$tag] ',
                      style: theme.textTheme.bodySmall?.copyWith(color: tint),
                    ),
                  if (showWho)
                    TextSpan(
                      text: '$who：',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (trailing == null) return row;
    // 动作区另起一行，左缩进 = 图标槽 22 + 头像可能的 22，尽量与正文左缘对齐。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        row,
        Padding(
          padding: EdgeInsets.only(
            left: item.avatar.isNotEmpty ? 26 : 22,
            right: 4,
            bottom: 4,
          ),
          child: trailing,
        ),
      ],
    );
  }

  /// 文案：redacted 恒为 text；公开骰用单行文案；对抗附结论。
  String _textOf(FeedItem it) {
    switch (it.kind) {
      case FeedKind.dice:
        return it.dice == null ? it.text : diceLine(it.dice!);
      case FeedKind.check:
      case FeedKind.opposed:
        return checkLine(it);
      case FeedKind.chat:
      case FeedKind.note:
      case FeedKind.sys:
        return it.text;
    }
  }

  (String, IconData, Color?) _badgeOf(FeedItem it, ThemeData theme) {
    switch (it.kind) {
      case FeedKind.sys:
        return ('系统', Icons.info_outline, theme.colorScheme.outline);
      case FeedKind.note:
        return ('备注', Icons.sticky_note_2_outlined, theme.colorScheme.outline);
      case FeedKind.chat:
        return ('', Icons.chat_bubble_outline, null);
      case FeedKind.dice:
        return ('骰', Icons.casino_outlined, theme.colorScheme.primary);
      case FeedKind.check:
        // ★ redacted 行只显脱敏文案（C6 / T-11）——标签也不含结果信息。
        return (it.redacted ? '私密' : '检定', Icons.rule,
            theme.colorScheme.secondary);
      case FeedKind.opposed:
        return ('对抗', Icons.compare_arrows, theme.colorScheme.tertiary);
    }
  }
}

/// 聊天输入行的固定高度（P17 KP-4）。
///
/// ★ 为什么必须定死：`GpFeeds(pane: record)` 与 `GpPrivates` 要按**同一个值**
///   补一条等高占位，三块 Card 才会等高（用户：「游戏记录」「只给你看」比
///   聊天栏短）。若让输入行按内容自然撑高，记录栏的占位就只能猜一个魔数，
///   系统字号一变两边就又不等高了 —— 所以把「这一行多高」变成单一真源。
/// ★ 取值：行内三个 `RoomBtnSize.chatIcon`（48×44）的 44 + 上下各 2dp。
///   子树同时钳住字号缩放（见 [ChatInputRow.build]），否则 1.3/1.5/2.0 档
///   会把这一行撑出定高。
const double kChatInputRowHeight = 48;

/// 聊天输入行。
///
/// ★ 只在自己的 State 里持有 `TextEditingController`，草稿另存一份到
///   `RoomUiLocal.chatDraft`（切块/整页重建后还能恢复）。
/// ★ 旁观者禁用（`TextField.enabled == false`），且 `chat` 不在其 POLICY 里。
class ChatInputRow extends StatefulWidget {
  const ChatInputRow({super.key, this.locked = false});

  /// P17 G-1：操作锁（昏迷 / 濒死 / 疯狂发作；**不含撕卡** —— 撕卡仍可聊天）。
  ///
  /// ★ 只做「不能输入 / 不能发」三件事：输入框 `enabled=false` + `onTap=null`、
  ///   三个会产生文本的入口（AI RP / 全屏编辑 / 发送）`enabled=false`。
  /// ★ **不**清草稿、**不**禁列表滚动、**不**隐藏输入行 —— 隐藏会让三块 Card
  ///   高度当场跳变（P17 KP-4 刚刚把它们调成等高），锁定态下布局必须与解锁态
  ///   逐像素一致。
  final bool locked;

  @override
  State<ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<ChatInputRow> {
  final TextEditingController _text = TextEditingController();
  bool _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    // 只在首次挂载时恢复草稿：之后的输入以本 State 为准（不覆盖用户正在打的字）。
    final draft = RoomScope.read(context).local.chatDraft;
    if (draft.isNotEmpty) _text.text = draft;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    // ★ P17 G-1：锁定态兜底 —— 按钮已 `enabled:false`、输入框已禁用，
    //   这里再断一次，保证「锁定态发不出任何 chat」不依赖上层是否漏传 `locked`。
    if (widget.locked) return;
    final scope = RoomScope.read(context);
    final text = _text.text.trim();
    if (text.isEmpty) return; // 空文本静默丢弃（与权威端口径一致）
    scope.local.setChatDraft('');
    _text.clear();
    scope.controller.sendIntent(RoomIntent.chat, <String, Object?>{'text': text});
  }

  /// 打开全屏「编辑发言」页（用户问题 5）。
  ///
  /// ★ 刻意只在 [TextField.onTap] 挂，不挂 `FocusNode.onFocusChange`：
  ///   `tester.enterText` 也会聚焦输入框，用焦点监听会把
  ///   `test/room_ui_feeds_test.dart:266-315` 的既有输入用例全部弄崩。
  ///   `onTap` 只在真实点击时触发，`enterText` / `onSubmitted` 完全不受影响。
  ///
  /// 草稿双向同步：打开时取当前草稿，编辑器里 `onChanged` 逐字写
  /// `RoomUiLocal.chatDraft`；「完成」返回文本 → 写回原 `_text` 并把光标挪到末尾；
  /// 「发送」直接发包 + 清草稿（见下）。
  ///
  /// ★ P17 KP-5（用户：全屏编辑后点发送没有任何反应，文字还在）：
  ///   改前 `onSend` 闭包写的是 `_text.text = text` 再调 `_send()` —— 也就是
  ///   **持有本 State 的 controller 与 context**。全屏是独立路由，打开期间
  ///   底层 `RoomGamePage` 若因 `KeyedSubtree` 换 key 重建
  ///   （room_game_page.dart:335-336，key 含 `inGame`），本 State 已被
  ///   `dispose()`、`_text` 已释放 → 赋值抛 used-after-dispose →
  ///   `sheet_chat_composer.dart` 的 `onSend` 抛异常 → 紧随其后的
  ///   `Navigator.pop` 被跳过 → 弹层不关、文字还在、chat intent 也没发。
  ///   修法：**发包需要的三样东西（controller / local / 初始草稿）在打开前
  ///   全部捕获**，`onSend` 只碰这两个普通对象引用，不写 `_text`、不读旧
  ///   State 的 context —— 发包与关页因此都不再依赖本 State 是否存活。
  Future<void> _openComposer(BuildContext context) async {
    // ★ P17 G-1：锁定态不开全屏编辑器 —— 它是独立路由，`onSend` 直接走
    //   捕获的 controller 发包，不经过输入行任何按钮，是唯一能绕过禁用态的
    //   口子。入口（输入框 onTap / 全屏图标）已禁用，这里再兜一层。
    if (widget.locked) return;
    final RoomScope scope = RoomScope.read(context);
    final controller = scope.controller;
    final RoomUiLocal local = scope.local;
    final String initial =
        _text.text.isNotEmpty ? _text.text : local.chatDraft;
    // 本次是否**真的发出去了**：只有「没发送就关页」（完成 / 系统返回）
    // 才把草稿回填进输入行。
    bool sent = false;
    final String? result = await showChatComposer(
      context: context,
      initialText: initial,
      onChanged: local.setChatDraft,
      onSend: (String text) {
        final String trimmed = text.trim();
        if (trimmed.isEmpty) {
          // 空文本静默丢弃（与 [_send] 同口径），但草稿要清掉。
          local.setChatDraft('');
          return;
        }
        controller.sendIntent(
          RoomIntent.chat,
          <String, Object?>{'text': trimmed},
        );
        sent = true;
        local.setChatDraft('');
      },
    );
    if (!mounted) return;
    // ★ 已发送 → 输入行与草稿一律清空。改前这里是
    //   `draft = result ?? local.chatDraft`：发送失败（onSend 抛异常）时
    //   `_send()` 还没来得及清草稿，`chatDraft` 仍是整段原文，于是被**回填**
    //   到输入框 —— 用户看到的「已编辑的文字还保留着」的另一半成因。
    //   未发送（完成 / 系统返回）→ 才把草稿写回输入行。
    final String draft = sent ? '' : (result ?? local.chatDraft);
    _text.text = draft;
    _text.selection = TextSelection.collapsed(offset: draft.length);
    local.setChatDraft(draft);
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final editable = scope.session.role != RoomRole.spectator;
    // ★ P17 G-1：操作锁（昏迷 / 濒死 / 疯狂发作 / 撕卡）。
    //   与「旁观者禁言」合并成同一条门禁，避免两套判据漂移：
    //   `writable` 只决定「能不能产生文本 / 能不能发」，不决定**渲染什么** ——
    //   输入行（含三个图标）照常渲染，锁定态与解锁态逐像素同尺寸，
    //   三块 Card 的等高关系（P17 KP-4）不会因为锁定跳变。
    final bool writable = editable && !widget.locked;
    // ★ P17 KP-4：整行高度定死成 [kChatInputRowHeight]（记录栏 / 私密栏据此
    //   补等高占位）。定高控件必须把**本子树**的字号缩放钳住（P16 纪律：
    //   `MediaQuery.withClampedTextScaling` 只包这一行，不抬到页面 / 主题层、
    //   不用 ClipRect 硬裁），否则 1.3/1.5/2.0 档会把行撑出定高。
    final Widget row = Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: RoomKeys.gpChatInput,
            controller: _text,
            enabled: writable,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              hintText: writable
                  ? '说点什么…'
                  : (editable ? '锁定中（不能发言）' : '旁观中（不能发言）'),
              border: const OutlineInputBorder(),
            ),
            // ★ 点输入框即放大为全屏编辑器；禁用（旁观 / 锁定）时不弹。
            //   锁定态必须在这里就断掉：全屏编辑器是**独立路由**，它的
            //   `onSend` 直接走捕获的 controller 发包，不经过本行任何按钮。
            onTap: writable ? () => _openComposer(context) : null,
            // ★ P12 KP-3：点输入行以外收起软键盘（与全屏编辑器的
            //   onTapOutside / GestureDetector 兜底同口径）。
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onChanged: scope.local.setChatDraft,
            onSubmitted: (String _) => _send(),
          ),
        ),
        // AI RP（魔棒图标）：让 AI 写一段，结果**只填回这个输入框**，不自动发送。
        // 旁观者不渲染（既不发言也不用 AI 写发言）；锁定态**渲染但禁用**
        // （不隐藏，避免输入行宽度变化）。
        if (editable)
          RoomTap(
            key: GpFeedsKeys.aiRp,
            icon: Icons.auto_awesome,
            hint: writable ? 'AI RP：写一段，只填进输入框' : '昏迷 / 疯狂发作期间不能发言',
            enabled: writable,
            minSize: RoomBtnSize.chatIcon,
            onTap: () => openAiRpSheet(
              context,
              onFilled: (String text) {
                // 只回填 + 聚焦到末尾，发送仍由玩家自己决定。
                _text.text = text;
                _text.selection = TextSelection.collapsed(offset: text.length);
                scope.local.setChatDraft(text);
              },
            ),
          ),
        // ★ 显眼的独立「全屏编辑」入口（用户未必知道输入框可点）。
        //   旁观者不渲染：既不发言，也不需要放大检查草稿。
        //   锁定态渲染但禁用 —— 同一个理由：全屏编辑器能绕过输入行直接发包。
        if (editable)
          RoomTap(
            key: GpFeedsKeys.chatFullscreen,
            icon: Icons.open_in_full,
            hint: writable ? '全屏编辑发言，方便检查写了什么' : '昏迷 / 疯狂发作期间不能发言',
            enabled: writable,
            // ★ P16：3 个图标统一 48×44（改前 48/44/48 差 4dp）。
            minSize: RoomBtnSize.chatIcon,
            onTap: () => _openComposer(context),
          ),
        RoomTap(
          key: GpFeedsKeys.send,
          icon: Icons.send,
          hint: writable
              ? '发送'
              : (editable ? '昏迷 / 疯狂发作期间不能发言' : '旁观者不能发言'),
          enabled: writable,
          minSize: RoomBtnSize.chatIcon,
          onTap: _send,
        ),
      ],
    );
    return SizedBox(height: kChatInputRowHeight, child: clampBtnText(row));
  }
}
