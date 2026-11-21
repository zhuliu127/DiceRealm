// ============================================================
// room_ui_local.dart — 旧版 `UI_STATE` 的 Dart 对应物（设计 §3.5）
//
// 纯 UI 本地态：**不进 state、不进存档、不参与任何规则**。对应旧版
// `room-panels.js:58` 的 `UI_STATE` 全集 + 散落在模块变量里的折叠态 /
// 缩放 / 草稿。这是 UI 层唯一允许「不进事件流」的可变数据。
//
// ★ 与 session 分开订阅（§1.4）：session 变化频繁（每条事件），
//   local 变化稀疏（点 tab / 折叠）；合成一个会让「点一下折叠」重算整页。
// ============================================================

import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'feed_optoast_tracker.dart' show kOptoastMax, kOptoastTtl;
import 'widgets/room_event_banner.dart'
    show RoomBannerItem, kBannerDefaultTtl;

// ★ P20 需求 2：`RoomBannerItem` 的**唯一定义处**在
//   `widgets/room_event_banner.dart`（那边是它的唯一渲染方，定义在那里不产生
//   反向依赖）。本文件只 import + re-export，**绝不在这里重复定义同名类** ——
//   两份同名类会让 `banners` 与 `RoomEventBanner` 的类型对不上，且必然出现
//   「重复类」编译错误。对外符号与契约完全一致：
//   `import 'room_ui_local.dart'` 也能拿到 `RoomBannerItem`。
export 'widgets/room_event_banner.dart'
    show RoomBannerItem, kBannerDefaultTtl;

/// KP 工具窄栏（块 3）的模式。
///
/// ★ P12：`pan`（「拖动素材」）为末尾追加成员；既有 6 个成员（含
///   `placePlayer`，虽已失去 UI 使用点）一个不删 —— 删符号会让既有调用点
///   与用例在编译期假红（设计 §3.1 / §7.1 R9）。
enum RoomToolMode { none, mark, draw, erase, placeActor, placePlayer, pan }

/// 玩家手绘板（块 10）的模式。
enum BoardMode { draw, erase }

/// 一条操作播报（PV-1a / 契约 I9）。
///
/// 与单条 [RoomUiLocal.notice] 分开的独立队列元素。[id] 稳定且递增，
/// 供 `RoomNoticeKeys.optoast(id)` 定位、供到点自消按 id 精确移除。
/// [at] 是入队时刻（纯记录，不参与任何判据 / 规则 / 存档）。
class RoomOptoastItem {
  /// 位置参数构造，与架构设计 §7 的 `RoomOptoastItem(this.id, this.text, this.at)`
  /// 逐字对齐（三个字段全必填，无需命名参数）。
  const RoomOptoastItem(this.id, this.text, this.at);

  final int id;
  final String text;
  final DateTime at;
}

/// 纯 UI 本地态。`ChangeNotifier` 让每块能用 `ListenableBuilder` 局部重建。
class RoomUiLocal extends ChangeNotifier {
  // ---- 面板 tab（P1-01：切 tab 不丢滚动位置，ScrollController 由各块持） ----
  // ★ P13 MAP-1：删「地图」tab 后范围收紧到 0..1；旧值 2（素材）落到 1。
  int leftTab = 0; // 0 NPC·怪物 / 1 素材
  int combatTab = 0; // 0 顺序 / 1 怪物信息
  int logTab = 0;
  int feedTab = 0;

  // ---- 折叠（P0-17：折叠态重绘后保持） ----
  final Set<String> folded = <String>{};

  /// KP「战斗信息」面板是否收起（P16 KP-4②）。
  ///
  /// 战斗信息栏搬进**素材舞台格**后，同一格里既要有战斗列表、又要能一键回到
  /// 舞台摆位，所以给格内那条细标题行配一个「展开 / 收起」开关。
  /// 纯本地态：不进 state、不同步给其他端、重绘后保持（与 [folded] 同一档）。
  /// `false` = 展开（默认看战斗列表），`true` = 收起（回到素材舞台）。
  bool combatPanelCollapsed = false;

  /// KP-5「玩家 / 队友」面板收起态（契约 I8，W-E 消费）。
  ///
  /// ★ 与 [combatPanelCollapsed] **严格隔离**：两块各收各的，复用同一字段会
  ///   让「战斗信息」与「玩家列表」同时收起 / 同时展开（KP-5 的真实缺陷）。
  /// 纯本地态：不进 state、不同步给其他端、重绘后保持。
  /// `false` = 展开（默认），`true` = 收起（只控 `GpKpPlayers` 子树，
  /// 绝不卸载 `GpSceneCheckKp` —— 由消费方保证，本字段只表达意图）。
  bool playersPanelCollapsed = false;

  /// 玩家侧「战斗栏」是否收起（P20 需求 3③）。
  ///
  /// 玩家侧那块「战斗信息」栏收起后回到素材舞台，默认 [true] = 收起
  /// （玩家绝大多数时间在看舞台，而不是看战斗列表）。
  ///
  /// ★ 与 [combatPanelCollapsed]（KP 战斗信息栏）、[playersPanelCollapsed]
  ///   （KP 玩家信息栏）**三方严格隔离** —— 复用同一个字段会让两处面板
  ///   同时收起 / 同时展开（P11 已踩过这个坑）。
  /// 纯本地态：不进 state、不同步给其他端、重绘后保持。
  bool plCombatPanelCollapsed = true;

  // ---- KP 工具窄栏（块 3）：纯本地 ----
  RoomToolMode toolMode = RoomToolMode.none;

  /// 工具标识串（**不再渲染**：P12 起按钮上的图标一律是 `Icons.xxx`）。
  ///
  /// 旧版用它画「工具光标」上的 emoji，现在只作为纯标识保留，取值改成
  /// 无表情的名字；仍由 [setTool] 透传，既有调用点与用例不必改。
  String toolIcon = 'draw';
  int toolColorIndex = 0; // 索引进 `kDrawColors`（6 色，见 room_theme.dart）

  // KP 左窄栏的本地候选怪（不进事件流，随 combat.start 送）。
  final List<Map<String, Object?>> pendingActors = <Map<String, Object?>>[];

  // ---- 手绘板（块 10 PL） ----
  BoardMode boardMode = BoardMode.draw;
  int boardPage = 0;

  // ---- 骰子条草稿（S3 / S4：必须分开两个字段，传 net 会丢信息） ----
  int bonus = 0;
  int penalty = 0;
  bool darkRoll = false;

  // ---- 放置单位 / 玩家选中的目标（块 3 → 块 4 落点） ----
  String? pendingActorName;
  String? pendingPlayerSeat;

  // ---- 队友列表展开态（PL 块 8） ----
  //
  // ★ 2.42.0 / P20 需求 3⑤：**默认收起**（改前 true）。
  //
  // 为什么必须是 false —— 摊开整条因果链，别只记结论：
  //   ① 玩家 dock 右列现在是 `RoomStackNode([gpPlScene flex100, gpPlMates flex1])`
  //      （需求 3⑤ 的「场景检定栏拉长 + 队友栏叠在上层」）；
  //   ② `RoomStackNode` 给每个子级下发的是 `Positioned.fill` ⇒ **紧约束**
  //      （min == max，横向纵向都给满格）；
  //   ③ 展开态的 `GpPlMates` 走 `SectionBox`，其 `Card` 是 `Material`
  //      （`hitTestSelf == true`）且在本格高度内**按内容撑到整格**；
  //   ④ 于是默认展开 = 一进房间队友栏就与场景检定栏**逐像素同 rect**
  //      （1280×800 实测两边都是 `LTRB(920.2, 38.0, 1272.0, 403.7)`），
  //      上层把下层整格盖死：玩家点不到「场景检定 / 掷骰」。
  //   ⑤ 用户需求原话是「场景检定栏拉长占据空位、**队友栏在上层可收起**」——
  //      换成产品语义就是「默认让位给场景栏」，也就是 false。
  //
  // 需要「一进来就必须看到队友列表」的场景只有一种：折叠档点开队友方块走
  // 全屏路由（没有叠放语境）—— 那条路径由 `GpPlMates.forceOpen: true` 解决，
  // **不靠改这个默认值**（否则又回到「盖死场景栏」）。
  bool matesOpen = false;

  // ---- 缩放（60–100%，只缩小不放大） ----
  double zoom = 1.0;
  static const double zoomMin = 0.6;
  static const double zoomMax = 1.0;
  static const List<int> zoomSteps = <int>[60, 70, 80, 90, 100];

  // ============================================================
  // ---- P12 素材舞台本机态（KP-1c / KP-2b / PL-3c；设计 §3.1 / §7.2）----
  //
  // ★ 本机态口径：以下四个值只活在本 ChangeNotifier 里，绝不进 state、
  //   绝不进存档 JSON、绝不进出站 SendPlan / hostAction / sendIntent 载荷、
  //   绝不广播；只由局部 ListenableBuilder 消费。
  // ★ 严格隔离：mapZoom 是「素材舞台」缩放（0.5–3.0），与上面的 zoom
  //   （页面整体缩放，0.6–1.0）是两套独立字段 / 独立常量 / 独立 setter，
  //   不复用、不互相赋值、不共字段名。
  // ============================================================

  /// 舞台自身缩放范围（由 `gp_map_stage.dart` 的 `_zoom` 上提到本机态）。
  static const double mapZoomMin = 0.5;
  static const double mapZoomMax = 3.0;

  /// KP-1c / PL-3c：是否处于「素材舞台真全屏」覆盖层。
  /// 进入全屏置 true；退出全屏 / 切场景 / 页面销毁由 [resetMapView] 复位。
  bool mapFullscreen = false;

  /// KP-2b：拖动素材的本机平移量（逻辑像素）。
  /// 四层（底图 + 笔迹 + 标点 / 单位标记）共用同一 Transform.translate。
  /// 「最小可见比例」钳制由舞台渲染侧完成（需要视口尺寸），本字段只保存
  /// 已钳制后的值；退出全屏 / 切场景由 [resetMapView] 归零。
  Offset mapPanOffset = Offset.zero;

  /// KP-1c / KP-2b：素材舞台缩放，夹 [mapZoomMin]..[mapZoomMax]。
  /// 主页与真全屏共享同一份，退出由 [resetMapView] 回到 1.0。
  double mapZoom = 1.0;

  /// KP-2b：「拖动素材」是否激活。
  ///
  /// ★ 刻意做成 [toolMode] 的派生 getter 而非独立 bool：激活态天然与
  ///   mark / draw / erase / placeActor / placePlayer 互斥，切到其它工具时
  ///   自动变 false 且**保留** [mapPanOffset]（PRD §5.2 状态机）。
  ///   激活走 `setTool(RoomToolMode.pan)`（设计 §4.4），也可用
  ///   [setPanArmed] 便利方法；本 getter 只读，不另存第二份状态。
  bool get panArmed => toolMode == RoomToolMode.pan;

  // ---- 草稿（输入行重建不丢，S12） ----
  String chatDraft = '';
  String notesDraft = '';

  // ---- 一次性提示（K7：不弹模态、不乐观提示成功） ----
  String? notice;
  Timer? _noticeTimer;

  // ---- 操作播报（PV-1a）：独立错峰队列，与单条 notice 完全分开 ----
  // ★ C14：`String? notice` 是单条语义（全库 20+ 调用点与大量断言依赖），
  //   绝不改成 List；播报另起 `optoasts`，两者各管各的、互不干扰。
  final List<RoomOptoastItem> optoasts = <RoomOptoastItem>[];
  int _optoastSeq = 0;
  final Map<int, Timer?> _optoastTimers = <int, Timer?>{};

  /// 持续时间后可注入（测试里换成立即 / 不触发，避免 fake-async 挂死）。
  /// 返回 Timer 供 [clearNotice] / [dispose] 取消。
  Timer? Function(Duration, void Function()) scheduleDismiss =
      (ttl, fn) => Timer(ttl, fn);

  /// 显示一条块级 banner 提示，[ttl] 后自动清除（默认 2s）。
  void showNotice(String text, {Duration ttl = const Duration(seconds: 2)}) {
    _noticeTimer?.cancel();
    notice = text;
    notifyListeners();
    if (ttl <= Duration.zero) {
      _noticeTimer = null;
      return;
    }
    _noticeTimer = scheduleDismiss(ttl, () {
      if (notice == text) {
        notice = null;
        notifyListeners();
      }
    });
  }

  void clearNotice() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  /// 推入一条操作播报（默认 [kOptoastTtl] 自消，同屏最多 [kOptoastMax] 条）。
  ///
  /// ★ C14：2 秒自消**必须**走可注入的 [scheduleDismiss]（FakeAsync 口径，
  ///   见 `gp_feeds.dart:113-116`），本类不出现裸 `Timer` 构造。超时按 id
  ///   精确移除，不会误删后来入队的同文案条目。
  /// ★ 超过 [kOptoastMax] 条时挤掉最旧的一条（连同它的定时器一起取消），
  ///   保证队列长度恒定、不会随事件流无限增长。
  void pushOptoast(String text, {Duration ttl = kOptoastTtl}) {
    if (text.isEmpty) return;
    final int id = ++_optoastSeq;
    optoasts.add(RoomOptoastItem(id, text, DateTime.now()));

    while (optoasts.length > kOptoastMax) {
      final RoomOptoastItem dropped = optoasts.removeAt(0);
      _optoastTimers.remove(dropped.id)?.cancel();
    }

    notifyListeners();

    if (ttl <= Duration.zero) {
      _optoastTimers.remove(id);
      return;
    }
    _optoastTimers[id] = scheduleDismiss(ttl, () {
      _optoastTimers.remove(id);
      _dismissOptoast(id);
    });
  }

  /// 到点按 id 移除一条；只有确实移除了才通知（避免空转重绘）。
  void _dismissOptoast(int id) {
    final int before = optoasts.length;
    optoasts.removeWhere((RoomOptoastItem it) => it.id == id);
    if (optoasts.length != before) notifyListeners();
  }

  /// 清空整条播报队列并取消全部待触发的定时器。
  void clearOptoasts() {
    for (final Timer? t in _optoastTimers.values) {
      t?.cancel();
    }
    _optoastTimers.clear();
    if (optoasts.isEmpty) return;
    optoasts.clear();
    notifyListeners();
  }

  // ============================================================
  // ---- 关键事件横幅队列（P20 需求 2）----
  //
  // ★ 第三条独立通路：与单条 `notice`、操作播报 `optoasts` **完全不共享**
  //   队列 / 定时器 / ttl（C14 口径，`kOptoastTtl=2s` 被
  //   `test/p11_pv1a_optoast_tracker_test.dart:164` 锁死，本需求要 4 秒）。
  //   文案由 App 生成（`EventBannerCopy`），不由 domain log 原样转发。
  //
  // ★ 纯本机态：不进 `state`、不进存档、不出站、不广播；只有
  //   `RoomNoticeOverlay` 读它上屏。
  // ============================================================

  /// 关键事件横幅队列：**队首（`banners.first`）就是当前正在上屏的那一条**，
  /// 其余是等待队列（按入队顺序依次提升）。
  ///
  /// ★ P21 需求 4：**不再丢信息**。改前是「同屏最多 2 条（旧常量
  ///   `kBannerMax`），超出挤掉最旧的一条」，KP 用 SAN Check 让 5 个玩家
  ///   同时疯狂时，后 3 条会被直接丢掉（连日志都没有，用户根本不知道
  ///   发生过）。
  ///   改后同一时刻**只渲染 1 条**，队列本身**不限长**：上一条（到点或被
  ///   点掉）消费完再提升下一条，一条都不会丢。
  /// ★ 「当前条 + 等待队列」两个概念用**同一个 List** 表达（队首 = 当前条）：
  ///   对外仍是 `banners`，`RoomNoticeOverlay` 只读 `banners.first`，
  ///   不引入第二份状态，也就不会出现「当前条与队列不一致」的错位。
  final List<RoomBannerItem> banners = <RoomBannerItem>[];

  /// 横幅 id 自增序号（从 1 开始；0 永远不出现，避免与「默认值」混淆）。
  int _bannerSeq = 0;

  /// **当前条**的到点自消定时器（全队列同一时刻最多一个 —— 一次只显示一条）。
  Timer? _bannerTimer;

  /// 当前条已排定的 id / 时长（用于判断「后来者入队后要不要把当前条重排成
  /// 连发短时长」；`_bannerArmedId == null` 表示当前没有排定的条目）。
  int? _bannerArmedId;
  Duration _bannerArmedTtl = Duration.zero;

  /// 队列里只剩最后一条时的显示时长（P21 需求 3：默认 4 秒）。
  static const Duration kBannerTtl = kBannerDefaultTtl;

  /// 队列里**还有后续条目**时，当前条只显示这么久（P21 需求 4）。
  ///
  /// 取值理由（2.2 秒）：
  ///   · 下限：4 个字的标题 + 一行副行，正常人默读约 1.2–1.6 秒；2.2 秒留出
  ///     约 40% 余量，仍能读完，不至于「还没看清就翻页」；
  ///   · 上限：KP 的 SAN Check 一次可能连发 5 条（5 名玩家同时疯狂），
  ///     5 × 4s = 20 秒太久（玩家会以为卡死）；5 × 2.2s ≈ 11 秒，可接受；
  ///   · 与「交叉淡化 220ms」相比 2.2 秒足够长，动画不会显得在抢时间。
  static const Duration kBannerBurstTtl = Duration(milliseconds: 2200);

  /// 当前正在上屏的那一条（没有则 `null`）。
  RoomBannerItem? get activeBanner => banners.isEmpty ? null : banners.first;

  /// 当前条之后还排着几条（诊断 / 测试用，不参与渲染）。
  int get pendingBannerCount => banners.isEmpty ? 0 : banners.length - 1;

  /// 推入一条关键事件横幅（排在队尾；队首那一条上屏）。
  ///
  /// [title] 空白直接丢弃（空标题的遮罩毫无意义）。
  /// ★ 自消**必须**走可注入的 [scheduleDismiss]（FakeAsync 口径，与
  ///   [pushOptoast] 同源），本类不出现裸 `Timer` 构造 —— 否则用例里推进
  ///   4 秒也不会触发消失。
  /// ★ 到点 / 被点掉都按 id 精确移除，不会误删后来入队的同文案条目。
  /// ★ 本方法签名与 P20 保持一致（`room_event_banner_watcher.dart` 不用改）。
  void pushBanner({
    required String title,
    required String subtitle,
    required String art,
    Duration ttl = kBannerTtl,
  }) {
    if (title.trim().isEmpty) return;
    final int id = ++_bannerSeq;
    banners.add(RoomBannerItem(id, title, subtitle, art, DateTime.now(), ttl: ttl));

    // 当前条已经按「独占 4 秒」排定，而这一条让它变成了「还有后来者」：
    // 立刻把当前条重排成连发短时长，让后来者尽快轮到。
    // ★ 只在 `_bannerArmedTtl > kBannerBurstTtl` 时重排 ⇒ 只会**缩短**、
    //   绝不会把一条已经排成 2.2s 的条目再拉长；连发（同一帧内连续 push，
    //   KP 的 SAN Check 就是这种）时后续 push 一律命中不了这个分支，重排
    //   最多发生一次。
    final bool headWasLong =
        _bannerArmedId != null &&
        banners.isNotEmpty &&
        _bannerArmedId == banners.first.id &&
        _bannerArmedTtl > kBannerBurstTtl &&
        banners.length > 1;

    notifyListeners();
    if (_bannerArmedId == null || headWasLong) _armBannerHead();
  }

  /// 关闭**当前**这一条（点击遮罩 / 到点自消共用）。
  ///
  /// [id] 给出时只关「确实是它」的那一条 —— 淡出动画期间旧遮罩仍可能吃到
  /// 一次点击，带上 id 就不会误关刚刚提升上来的下一条。
  /// 关掉后自动提升队首的下一条（有的话）并按新队列长度重排时长。
  void dismissActiveBanner({int? id}) {
    if (banners.isEmpty) return;
    if (id != null && banners.first.id != id) return;
    banners.removeAt(0);
    _cancelBannerTimer();
    notifyListeners();
    _armBannerHead();
  }

  /// 当前条应该显示多久：**还有后来者 → 连发短时长；队尾 → 它自己声明的
  /// 时长（默认 4 秒）**。取 `min` 是为了让「调用方显式传了更短的 ttl」时
  /// 不被连发时长反向拉长。
  Duration _bannerTtlOf(RoomBannerItem head) {
    if (banners.length <= 1) return head.ttl;
    return head.ttl < kBannerBurstTtl ? head.ttl : kBannerBurstTtl;
  }

  /// 给队首那一条排定自消定时器（先取消旧的，保证全队列只有一个）。
  void _armBannerHead() {
    _cancelBannerTimer();
    if (banners.isEmpty) return;
    final RoomBannerItem head = banners.first;
    final Duration ttl = _bannerTtlOf(head);
    _bannerArmedId = head.id;
    _bannerArmedTtl = ttl;
    // ttl <= 0 保持老口径：不自动消失（只可能被点击 / clearBanners 收掉）。
    if (ttl <= Duration.zero) return;
    _bannerTimer = scheduleDismiss(ttl, () {
      _bannerTimer = null;
      dismissActiveBanner(id: head.id);
    });
  }

  /// 取消当前条的定时器并清掉排定记录（不动队列）。
  void _cancelBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _bannerArmedId = null;
    _bannerArmedTtl = Duration.zero;
  }

  /// 清空整条横幅队列并取消待触发的定时器（退房 / 换会话时调用）。
  void clearBanners() {
    _cancelBannerTimer();
    if (banners.isEmpty) return;
    banners.clear();
    notifyListeners();
  }

  void toggleFold(String id) {
    if (!folded.add(id)) folded.remove(id);
    notifyListeners();
  }

  bool isFolded(String id) => folded.contains(id);

  void setFold(String id, bool value) {
    if (value ? folded.add(id) : folded.remove(id)) notifyListeners();
  }

  /// KP 战斗信息面板的收起态（P16 KP-4②）。变了才通知。
  void setCombatPanelCollapsed(bool value) {
    if (combatPanelCollapsed == value) return;
    combatPanelCollapsed = value;
    notifyListeners();
  }

  /// KP-5 玩家面板收起态（契约 I8）。只在值变化时通知。
  ///
  /// ★ 刻意不复用 [setCombatPanelCollapsed]：两者是**互相独立**的字段，
  ///   复用会让两处面板同时收起 / 同时展开。
  void setPlayersPanelCollapsed(bool value) {
    if (playersPanelCollapsed == value) return;
    playersPanelCollapsed = value;
    notifyListeners();
  }

  /// 玩家侧「战斗栏」收起态（P20 需求 3③）。只在值变化时通知。
  ///
  /// ★ 与 [setCombatPanelCollapsed] / [setPlayersPanelCollapsed] 三向隔离：
  ///   三个面板各收各的，共用会让它们联动收起。
  void setPlCombatPanelCollapsed(bool value) {
    if (plCombatPanelCollapsed == value) return;
    plCombatPanelCollapsed = value;
    notifyListeners();
  }

  void setTab(String which, int index) {
    switch (which) {
      case 'left':
        // ★ P13 MAP-1：地图 tab 删除后 leftTab 只保留 0=NPC·怪物 / 1=素材。
        //   越界值（含旧值 2=素材）统一钳到 1，避免落到空白面板。
        leftTab = index.clamp(0, 1);
        break;
      case 'combat':
        combatTab = index;
        break;
      case 'log':
        logTab = index;
        break;
      case 'feed':
        feedTab = index;
        break;
      default:
        return;
    }
    notifyListeners();
  }

  void setTool(RoomToolMode m, {String? icon, int? colorIndex}) {
    toolMode = m;
    if (icon != null) toolIcon = icon;
    if (colorIndex != null) toolColorIndex = colorIndex;
    notifyListeners();
  }

  /// ★ S3：奖惩骰**互斥**，切边清空另一侧，各自 0–5。
  void setBonus(int v) {
    final n = v < 0 ? 0 : (v > 5 ? 5 : v);
    bonus = n;
    if (n > 0) penalty = 0;
    notifyListeners();
  }

  void setPenalty(int v) {
    final n = v < 0 ? 0 : (v > 5 ? 5 : v);
    penalty = n;
    if (n > 0) bonus = 0;
    notifyListeners();
  }

  void setDarkRoll(bool v) {
    darkRoll = v;
    notifyListeners();
  }

  void setBoardMode(BoardMode m) {
    boardMode = m;
    notifyListeners();
  }

  void setBoardPage(int p) {
    boardPage = p < 0 ? 0 : p;
    notifyListeners();
  }

  void setMatesOpen(bool v) {
    matesOpen = v;
    notifyListeners();
  }

  void setChatDraft(String v) {
    chatDraft = v;
  }

  void setNotesDraft(String v) {
    notesDraft = v;
  }

  void setPendingActorName(String? v) {
    pendingActorName = v;
    notifyListeners();
  }

  void setPendingPlayerSeat(String? v) {
    pendingPlayerSeat = v;
    notifyListeners();
  }

  /// 夹到 [0.6, 1.0]，6 位小数收口（避免 0.7000000000000001 漂移）。
  void setZoom(double v) {
    var z = v;
    if (z < zoomMin) z = zoomMin;
    if (z > zoomMax) z = zoomMax;
    final rounded = double.parse(z.toStringAsFixed(6));
    if (rounded == zoom) return;
    zoom = rounded;
    notifyListeners();
  }

  // ============================================================
  // ---- P12 素材舞台本机态 setter（纯本地，绝不触达 session / 出站）----
  // ============================================================

  /// KP-1c / PL-3c：进入 / 退出「素材舞台真全屏」。变了才通知。
  ///
  /// 只写本机态：不产生任何 `RoomEvt` / `SendPlan`，不同步给其他端。
  void setMapFullscreen(bool v) {
    if (mapFullscreen == v) return;
    mapFullscreen = v;
    notifyListeners();
  }

  /// KP-2b：写入拖动平移量（仅本机显示）。变了才通知。
  ///
  /// 舞台渲染侧先按「最小可见比例」钳制再传入（本类拿不到视口尺寸）；
  /// 这里只兜底拒绝非有限值，避免 NaN / Infinity 污染 Transform。
  /// 写入不产生 `SendPlan` / `RoomEvt`，state 与存档零变化。
  void setMapPanOffset(Offset v) {
    if (!v.dx.isFinite || !v.dy.isFinite) return;
    if (mapPanOffset == v) return;
    mapPanOffset = v;
    notifyListeners();
  }

  /// KP-1c / KP-2b：夹到 [mapZoomMin]..[mapZoomMax]，6 位小数收口。
  /// 变了才通知。★ 只动 [mapZoom]，绝不触碰既有 [zoom]（页面整体缩放）。
  /// NaN 无法比较故直接拒绝；±Infinity 按上下界夹住（与舞台侧 `_setZoom` 同口径）。
  void setMapZoom(double v) {
    var z = v;
    if (z.isNaN) return;
    if (z < mapZoomMin) z = mapZoomMin;
    if (z > mapZoomMax) z = mapZoomMax;
    final rounded = double.parse(z.toStringAsFixed(6));
    if (rounded == mapZoom) return;
    mapZoom = rounded;
    notifyListeners();
  }

  /// KP-2b：「拖动素材」激活 / 取消的便利入口。
  ///
  /// 主口径（设计 §4.4）是直接 `setTool(RoomToolMode.pan)`；本方法只是
  /// 等价封装：激活时切到 [RoomToolMode.pan]，取消时回到
  /// [RoomToolMode.none]，互斥性仍由 [toolMode] 单一真源保证。
  /// 不改变 [mapPanOffset]（切工具保留 offset，PRD §5.2）。
  void setPanArmed(bool v) {
    setTool(v ? RoomToolMode.pan : RoomToolMode.none);
  }

  /// 退出全屏 / 切场景 / 页面销毁时一次性复位全部舞台本机态：
  /// `mapFullscreen=false` + `mapPanOffset=Offset.zero` + `mapZoom=1.0`
  /// + 工具态回 [RoomToolMode.none]（即 [panArmed] 变 false）。
  ///
  /// 四个字段只发一次通知，避免逐条 setter 造成多次重绘；任一项有变化
  /// 才通知。★ 不触碰 [zoom] / [notice] / [optoasts] 等既有成员。
  void resetMapView() {
    final bool changed = mapFullscreen ||
        mapPanOffset != Offset.zero ||
        mapZoom != 1.0 ||
        toolMode != RoomToolMode.none;
    mapFullscreen = false;
    mapPanOffset = Offset.zero;
    mapZoom = 1.0;
    toolMode = RoomToolMode.none;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
    for (final Timer? t in _optoastTimers.values) {
      t?.cancel();
    }
    _optoastTimers.clear();
    // ★ P20/P21 需求：横幅定时器同样必须在销毁时全部取消 —— 漏一个就是
    //   `setState() called after dispose` / 「Timer is still pending」类假红，
    //   且到点回调还会去动一个已销毁的 notifier。
    //   这里直接取消、**不**调 [clearBanners]（本方法不该再 notifyListeners）。
    //   P21 起全队列同一时刻只有一个定时器（一次只显示一条），所以这里从
    //   遍历 Map 收成取消单个 Timer。
    _cancelBannerTimer();
    banners.clear();
    super.dispose();
  }
}
