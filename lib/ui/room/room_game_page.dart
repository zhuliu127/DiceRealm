// ============================================================
// room_game_page.dart — 游戏页壳体（设计 §2.3 / §5 T02）
//
// 职责（只有四件）：
//   ① 视角路由：`role == 'kp'` → KP 骨架（12 槽位），其余 → PL 骨架（13 槽位）；
//      旁观者复用 PL 骨架，容器数同样是 13。
//   ② 网格：`RoomGridSpec.of(w, h, landscape)`（纯函数唯一真相源）决定
//      多列 / 单列 / compact；单列时私密栏提到内容区第一位（旧版 order:-1）。
//   ③ 缩放：`Transform.scale` **只包内容区**；工具栏与顶栏是它的兄弟节点。
//   ④ 折叠：单列（竖屏）档每块带 `FoldHeader`，折叠态存在 `RoomUiLocal`，
//      重绘后保持（P0-17）。
//
// ★ 12 / 13 个槽位在 T03/T04/T05 依次换成了真块，本文件已无占位块
//   （K-01：本文件零占位块构造，可用类型名零命中核对）。
//
// ★ 整页重建的抓手：最外层 `KeyedSubtree(key: 'gp/<role>/<inGame>')` ——
//   `meta.status` 翻转或角色切换时这个 key 变化，框架丢弃整棵子树重建，
//   于是「切视角不残留上一视角的本地 State」在结构上成立。
//
// ★ 只画、只发动作：本文件零权威端引用、零规则调用、零状态写入。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/room_types.dart';
import '../../theme.dart' show Palette;
import '../art.dart';
import 'room_event_banner_watcher.dart' show RoomEventBannerWatcher;
import 'room_keys.dart';
import 'room_optoast_watcher.dart' show RoomOptoastWatcher;
import 'room_request_watcher.dart' show RoomRequestWatcher;
import 'room_scope.dart';
import 'room_theme.dart';
import 'room_ui_local.dart';
import 'sheets/room_sheet.dart';
import 'sheets/sheet_history_export.dart' show kRoomHistoryExportPolicyOp;
import 'sheets/sheet_kp_panel.dart' show openKpSheet, showKpPanel;
import 'sheets/sheet_misc.dart' show openMiscSheet;
import 'sheets/sheet_music.dart' show MusicSheetKeys, openMusicSceneQuickSheet;
import 'sheets/sheet_opposed.dart' show showPlayerOpposedRequestSheet;
import 'sheets/sheet_san_check.dart' show showSanCheckSheet;
import 'sheets/sheet_scene.dart' show showSceneSheet, showClueSheet;
import 'view/member_view.dart' show bodyViewOf, isRipped, operationLocked;
import 'view/room_view.dart';
import 'view/scene_view.dart' show NormPoint;
import 'widgets/gp_combat_list.dart';
import 'widgets/gp_dice_bar.dart';
import 'widgets/gp_feeds.dart';
import 'widgets/gp_kp_left.dart';
import 'widgets/gp_kp_players.dart';
import 'widgets/gp_kp_tools.dart';
import 'widgets/gp_map_stage.dart';
import 'widgets/gp_pl_char_card.dart';
import 'widgets/gp_pl_mates.dart';
import 'widgets/gp_pl_notes.dart';
import 'widgets/gp_pl_sketch.dart';
import 'widgets/gp_privates.dart';
import 'widgets/gp_scene_check_kp.dart';
import 'widgets/gp_scene_check_pl.dart';
import 'widgets/gp_status.dart';
import 'widgets/gp_toolbar.dart';
import 'widgets/gp_topbar.dart';
import 'widgets/room_layout.dart';
import 'widgets/room_button_size.dart' show RoomBtnSize, clampBtnText;
import 'widgets/room_panel_kit.dart';

// ------------------------------------------------------------
// 纯函数（缩略成可断言的三条，测试不必量像素也能锁死语义）
// ------------------------------------------------------------

/// 内容区槽位顺序。顶栏与工具栏由页面钉住（不参与滚动），故先剔除；
/// 单列档把私密栏提到第一位（等价旧版 CSS `order:-1`）。
///
/// ★ P10 第 2 期 B 之后：平板横屏走**固定网格**（顺序由 `roomDockPlanOf`
///   声明，本函数不参与）；本函数服务**折叠档**的真实方块平铺顺序
///   （`_foldedContent` 接线，P10 第 3 期 B）：剔除顶栏/工具栏、单列档
///   把私密栏提到第一位、多列档保持槽位表原序。
List<RoomSlot> roomOrderedContentSlots(
  List<RoomSlot> slots,
  RoomGridSpec spec,
) {
  final content = <RoomSlot>[
    for (final s in slots)
      if (s != RoomSlot.gpTopbar && s != RoomSlot.gpToolbar) s,
  ];
  if (spec.grid) return content;
  if (!content.contains(RoomSlot.gpPriv)) return content;
  return <RoomSlot>[
    RoomSlot.gpPriv,
    for (final s in content)
      if (s != RoomSlot.gpPriv) s,
  ];
}

/// 折叠档「默认展开」的槽位（用户口述 ② 的两串白名单）。
///
/// KP：地图怪物 / npc 素材栏（[RoomSlot.gpKpLeft]）、公开素材图片栏
///     （[RoomSlot.gpMap]，含手绘与战斗轮次信息）、场景检定（[RoomSlot.gpScene]）、
///     工具窄栏（[RoomSlot.gpKpTools]）。
/// 玩家 / 旁观：角色信息面板（[RoomSlot.gpPlCharCard]）、场景检定
///     （[RoomSlot.gpPlScene]）。
/// 工具栏不在内容区（它被钉在最下方），不参与这里的判定。
///
/// ★ P20 需求 4①（方案 A / D9）：**追加 `gpKpTools`** —— 折叠档里它不再是
///   一个 104dp 方块，而是吸附在素材舞台格下沿的「组合格」里常驻展开
///   （`_foldedContent` 的组合格分支 `_kpStageToolsCell`）。
///   ★ 它进了白名单 ⇒ `roomFoldedSlots` 不再把 `gpKpTools` 排进方块区，
///     所以「`gpKpTools` 容器 key 全库恰好一次」靠组合格那一处保证。
///   ★ `RoomKeys.kpSlots` 一个元素都不删（契约：枚举元素不删，只从声明树
///     里删节点）。
const List<RoomSlot> kKpExpandedSlots = <RoomSlot>[
  RoomSlot.gpKpLeft,
  RoomSlot.gpMap,
  RoomSlot.gpKpTools,
  RoomSlot.gpScene,
];

/// ★ P17 P-2：玩家侧战斗信息栏（[RoomSlot.gpPlCombat]）也登记进这张表，且
///   **排在首位** —— 战斗态要把它顶到「所有信息流（聊天 / 记录 / 私密）最上方」。
///   ★ 它**不是**无条件展开：`roomExpandedSlots` 会按 `state` 过滤 ——
///     战斗态（[isCombat]）才算展开并提到首位；非战斗态照旧留在方块区
///     （收成方块、点击展开 / 全屏），与 P16 行为逐字一致。
const List<RoomSlot> kPlExpandedSlots = <RoomSlot>[
  RoomSlot.gpPlCombat,
  RoomSlot.gpPlCharCard,
  RoomSlot.gpPlScene,
];

/// 该视角「默认展开」的槽位表（只保留确实在本视角槽位表里的）。
///
/// [state] 只被玩家侧的 [RoomSlot.gpPlCombat] 使用（P17 P-2）：
///   · 战斗态 → 计入并**提到首位**（置顶到所有信息流最上方）；
///   · 非战斗态 / 未传 [state] → 不计入（留在方块区）。
///   `roomExpandedSlots` 的既有调用方（单测、[RoomKeys.plSlots] 静态推导）
///   拿到的仍是「角色卡 + 场景」两块，语义不变。
List<RoomSlot> roomExpandedSlots(
  List<RoomSlot> slots,
  String role, {
  Map<String, Object?>? state,
}) {
  final want = role == RoomRole.kp ? kKpExpandedSlots : kPlExpandedSlots;
  final combat = role != RoomRole.kp && state != null && isCombat(state);
  final expanded = <RoomSlot>[
    for (final s in slots)
      if (want.contains(s) && (s != RoomSlot.gpPlCombat || combat)) s,
  ];
  // 战斗信息栏必须排首位（`plSlots` 里它在第 6 位，直接遍历排不出来）。
  if (expanded.remove(RoomSlot.gpPlCombat)) {
    expanded.insert(0, RoomSlot.gpPlCombat);
  }
  return expanded;
}

/// 折叠档里「收成方块」的槽位（槽位表顺序；剔除顶栏 / 工具栏 / 展开区）。
List<RoomSlot> roomFoldedSlots(
  List<RoomSlot> slots,
  String role, {
  Map<String, Object?>? state,
}) {
  final expanded = roomExpandedSlots(slots, role, state: state);
  return <RoomSlot>[
    for (final s in slots)
      if (s != RoomSlot.gpTopbar &&
          s != RoomSlot.gpToolbar &&
          !expanded.contains(s))
        s,
  ];
}

/// compact 档收紧块间距（矮屏才有意义；grid 关闭时 compact 恒为假）。
double roomBlockGap(RoomGridSpec spec) =>
    spec.compact ? 4.0 : RoomTheme.panelGap;

/// 内容区左右留白（网格与折叠档共用一处，避免两套边距各算一次）。
const double kRoomSidePadding = 8;

/// P20 需求 4①：「素材舞台 · 工具窄栏」组合格里，舞台与工具栏之间的**细缝**。
///
/// ★ 刻意不用 `roomBlockGap(spec)`（4 / 8）：用户要的是「工具窄栏**吸附**在
///   素材舞台下沿」，共用 gap 会让两块看起来是两个独立面板。4dp 只起分隔
///   作用，读起来仍是一整格。
const double kKpStageToolsSeam = 4;

/// 底部工具栏最多占可用高度的比例（剩下的留给内容区，极矮屏才生效）。
const double kToolbarMaxShare = 0.62;

/// 槽位标题（折叠头与占位文案共用；块号只用于对照 PRD，不参与逻辑）。
String roomSlotTitle(RoomSlot slot) {
  switch (slot) {
    case RoomSlot.gpTopbar:
      return '顶栏';
    case RoomSlot.gpKpLeft:
      return '左窄栏（成员 / 怪物）';
    case RoomSlot.gpKpTools:
      return '工具窄栏';
    case RoomSlot.gpMap:
      return '素材舞台';
    case RoomSlot.gpScene:
      return '场景';
    case RoomSlot.gpCombat:
      return '战斗';
    case RoomSlot.gpPlayers:
      return '玩家 / 队友';
    case RoomSlot.gpChat:
      return '聊天';
    case RoomSlot.gpLog:
      return '记录';
    case RoomSlot.gpPriv:
      return '私密栏';
    case RoomSlot.gpToolbar:
      return '工具栏';
    case RoomSlot.gpStatus:
      return '状态条';
    case RoomSlot.gpPlCharCard:
      return '我的角色卡';
    case RoomSlot.gpPlMap:
      return '素材舞台';
    case RoomSlot.gpPlChat:
      return '聊天';
    case RoomSlot.gpPlLog:
      return '记录';
    case RoomSlot.gpPlCombat:
      return '战斗';
    case RoomSlot.gpPlScene:
      return '场景';
    case RoomSlot.gpPlMates:
      return '队友';
    case RoomSlot.gpPlSketch:
      return '手绘板';
    case RoomSlot.gpPlNotes:
      return '笔记';
    case RoomSlot.gpCombatStrip:
      return '战斗速览条';
  }
}

/// 折叠头 key（只在单列档存在）。
Key roomFoldKey(RoomSlot slot) => ValueKey<String>('gpFold/${slot.name}');

// ------------------------------------------------------------
// 页面
// ------------------------------------------------------------

/// 游戏页壳体。
///
/// 由调用方保证外面已经挂了 `RoomScope`（夹具的 `RoomUiFixture.shell` 已挂）。
class RoomGamePage extends StatefulWidget {
  const RoomGamePage({
    super.key,
    this.seat,
    this.role,
    this.toolbarExtensions = const <Widget>[],
    this.serviceBase = '',
  });

  /// 可选：视角座位。不传则取 `RoomScope` 里的当前会话视角。
  ///
  /// ★ 存在的理由：设计 §7 K15 规定的夹具注入写法是
  ///   `f.pageBuilder = (seat, role) => RoomGamePage(seat: seat, role: role)`
  ///   —— 这两个具名参数必须能收（否则 T03–T05 抄那段代码会编译失败）。
  /// ★ 生产路径**不要**传：页面与会话必须同源，传错会画出别人的骨架。
  final String? seat;

  /// 可选：视角角色（kp / player / spectator）。语义同 [seat]。
  final String? role;

  /// 工具栏扩展插槽（骰子条 / KP 工具 / 手绘板入口），由 T03–T05 注入。
  final List<Widget> toolbarExtensions;

  /// KP 顶栏的服务地址（P5 无传输层，空串 → 「本机进程内」）。
  final String serviceBase;

  /// 「整页重建」key 的唯一生成处（测试与实现共用，避免字面量漂移）。
  static String pageKeyOf(String role, bool inGame) => 'gp/$role/$inGame';

  /// 缩放容器的稳定 key（测试据此读 `Transform` 的 scale，并反查祖先链）。
  static const Key zoomKey = ValueKey<String>('gpZoomHost');

  /// 工具栏里「KP 工具」入口的 key（注意：它不是 POLICY action，
  /// 所以**不能**用 `RoomKeys.action(op)`，否则会被 T-30 探针误判）。
  static const Key kpPanelKey = ValueKey<String>('gpToolbar/kpPanel');

  /// 玩家工具栏里的「更多工具」入口。
  ///
  /// 杂项弹层此前只能从 KP 工具面板打开，玩家没有可达路径；P2-06 的导出
  /// 真入口装在杂项弹层里，因此这里给非 KP 视角补一条生产路径。
  /// 权限沿用同一闸门：旁观者权限不足时结构上不渲染。
  static const Key miscToolsKey = ValueKey<String>('gpToolbar/miscTools');

  /// 玩家工具栏里的「治疗」入口（P16 P-4，所有玩家档位都有）。
  ///
  /// ★ 不是 POLICY action（只打开本机弹层），所以**不能**用
  ///   `RoomKeys.action(...)` —— 那会被 T-30 表驱动探针当成权威动作。
  ///   也**不挂** `RoomKeys.action('aid.apply')`（那个 key 已被角色卡急救按钮钉死）。
  static const Key treatKey = ValueKey<String>('gpToolbar/treat');

  /// ★ 2.34.0 / KP-7（契约 I10 / I12）：递线索快捷入口。
  ///
  /// 与 [treatKey] 同款：只开本机弹层、不发 intent，所以**不挂**
  /// `RoomKeys.action(...)`，也禁用 `RoomKeys.action('scene.clue')`
  /// （避免 T-30 表驱动探针误判 + 与既有 action key 撞 `findsOneWidget`）。
  static const Key clueQuickKey = ValueKey<String>('roomGame/clueQuick');

  /// ★ 2.34.0 / PV-1b（契约 I11 / I12）：玩家主动对抗申请入口。
  ///
  /// 同样只开本机弹层（由 `sheet_opposed.dart` 按契约 I5 组载荷并经
  /// `RoomConfirm.kp` + pending + `RoomRequestWatcher` 走审批链路），
  /// **不挂** `RoomKeys.action('check.opposed')` —— 那个 key 已被
  /// `gp_dice_bar.dart:432` 的既有按钮占用，且 R1 门控 / 骰子条 9 项契约
  /// 要求玩家侧不能新出 `act/check.opposed` 锚点。
  static const Key playerOpposedKey =
      ValueKey<String>('roomGame/playerOpposed');

  /// ★ P12 PL-2（契约 I10 / R6）：San Check 按钮，与「主动对抗」在
  ///   `mainActions` 里**右侧相邻**。独立 `ValueKey<String>`，
  ///   不挂 `RoomKeys.action(...)` 锚点（不进 T-30 静态表）。
  static const Key sanCheckKey = ValueKey<String>('roomGame/sanCheck');

  /// ★ 2.34.0 / KP-6a：`gpScene` 槽里 [GpSceneCheckKp] 宿主的稳定 key。
  ///
  /// 与 W-A 在 `gp_scene_check_kp.dart` 内部加的 `PageStorageKey` +
  /// `AutomaticKeepAliveClientMixin` + 显式 `FocusNode` 组成稳定 key 链：
  /// 父链换形时尽量复用同一 State，避免 `_skill` 控制器被 dispose。
  /// ★ 值刻意不等于 `GpSceneCheckKeys.root`（那是内部 SectionBox 的 key）。
  static const Key sceneCheckHostKey =
      ValueKey<String>('roomGame/gpSceneCheckKpHolder');

  /// 素材舞台格里「战斗信息」细标题行的展开 / 收起开关（P16 KP-4②）。
  ///
  /// 同样是纯本地态开关，不是权威动作 → 用独立 key，不占 `RoomKeys.action`。
  static const Key combatToggleKey = ValueKey<String>('gpMap/combatToggle');

  /// ★ P20 需求 3②：`gpPlScene` 格内「我的手绘板 / 我的笔记」两个全屏入口。
  ///
  /// 它们只推**本机**全屏路由（`openRoomSlotFullscreen`），不发任何 intent、
  /// 不改权威状态 → 与 [treatKey] / [miscToolsKey] 同款：独立
  /// `ValueKey<String>`，**不挂** `RoomKeys.action(...)`
  /// （否则会被 T-30 表驱动权限探针当成权威动作）。
  static const Key plSketchKey = ValueKey<String>('roomGame/plSketch');
  static const Key plNotesKey = ValueKey<String>('roomGame/plNotes');

  /// 「退出房间」二次确认弹层里两个按钮的稳定 key（P16 P-1(a)）。
  ///
  /// 它们是**本机**确认按钮（不发 intent、不改权威状态），所以同样不挂
  /// `RoomKeys.action`，避免 T-30 探针误判成权威动作。
  static const Key leaveConfirmKey =
      ValueKey<String>('roomPage/leave/confirm');
  static const Key leaveCancelKey = ValueKey<String>('roomPage/leave/cancel');

  /// ★ 2.36.0 / Q6：从 `KpPanel` 弹层挪到工具栏主组的两个动作按钮。
  /// 只给它们独立 `ValueKey<String>`，**不挂** `RoomKeys.action(...)`：
  /// 表驱动权限探针（T-30）按 `act/` 锚点扫全库，这两个按钮若挂上会与
  /// `p10_t3_layout_test.dart:292` 的 `findsNothing` 契约冲突。
  static const Key nextRoundKey = ValueKey<String>('gpToolbar/nextRound');
  static const Key combatReadyKey = ValueKey<String>('gpToolbar/combatReady');

  /// 战斗信息标题行的高度（dp）。
  ///
  /// 固定高度控件：行内文字必须钳住缩放（见 [_combatHeader]），否则系统
  /// 大字体下这一行会撑破并把下面的舞台 / 列表挤掉。
  static const double combatHeaderHeight = 28;

  @override
  State<RoomGamePage> createState() => _RoomGamePageState();
}

class _RoomGamePageState extends State<RoomGamePage> {
  /// ★ 素材舞台的控制面：**页面级单实例**。
  ///
  /// 块 4（舞台，本文件）与块 3（KP 工具窄栏，`GpKpTools`）必须拿到同一份，
  /// 否则「点画笔」只改了块 3 的本地态，舞台不知道要收点。测试用
  /// `identical()` 钉死这一点。
  final MapStageControl stageControl = MapStageControl();

  /// 折叠档的闪烁板：聊天 / 公开记录 / 只给你看三栏共用同一判据类
  /// （`FeedFlashTracker`）。折叠成方块后块体没建，判据只能上提到页面级
  /// ——否则「收起后来了新消息，界面上一点提示都没有」。
  final RoomFlashBoard flashBoard = RoomFlashBoard();

  /// 「退出房间」二次确认弹层是否正在显示（P16 P-1(a)）。
  ///
  /// 只做去重：连点返回键 / 返回键与系统手势同时触发时，不该叠出两层确认。
  bool _leaveConfirming = false;

  @override
  void dispose() {
    stageControl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    // 未注入时以会话为准（生产路径）；注入值优先（夹具 / 跨骨架对比用例）。
    final role = widget.role ?? scope.session.role;
    final inGame = isInGame(scope.session.state);
    final slots = role == RoomRole.kp ? RoomKeys.kpSlots : RoomKeys.plSlots;

    // 背景选图专用判据：横屏改用 16:9 横版，避免 9:16 竖图被 `BoxFit.cover`
    // 上下各裁约 31%。★ 只用于挑背景图，不参与 SafeArea → LayoutBuilder 内
    // `RoomGridSpec.of` 的栅格分栏（那里另有一个独立的 landscape 判据，
    // 本改动不碰）。尺寸读 `MediaQuery.of(context).size`（老 API，规避版本兼容风险）。
    final Size screenSize = MediaQuery.of(context).size;
    final bool landscape = screenSize.width > screenSize.height;

    // ★ P10 第 6 期 / 问题 5：把「新推送要求」的全局居中弹窗挂在页面根
    //   节点**外层**。必须在 KeyedSubtree 之外 —— 它在 meta.status 翻转 /
    //   切视角时换 key 重建整棵子树，watcher 放里面会连 _seen 去重集合一起
    //   丢掉，历史待办被全量重弹。放外面则跨重建持续监听。
    //   watcher 只画 child、零 RenderObject，不改变任何布局约束与几何；
    //   `gp_status` 的卡片原样保留为「已读后再看」入口。
    // ★ 2.34.0 / PV-1a（契约 I9）：遮罩广播 watcher 与页面根节点**同层**
    //   （`RoomScope` 之下、`KeyedSubtree(pageKeyOf)` 之外）。后者在
    //   meta.status 翻转 / 切视角时换 key 重建整棵子树，watcher 放里面会
    //   连 `FeedOptoastTracker` 的首屏基线一起丢掉、历史信息被全量重播。
    //   `Stack(fit: StackFit.expand)` 保证主内容仍拿到与改前一致的**紧约束**
    //   （`SafeArea → LayoutBuilder → RoomGridSpec.of` 几何零变化）；
    //   watcher 用 0×0 `Positioned`，零尺寸、不占 Stack 位置、不拦截点击、
    //   不新增影响布局的 RenderObject。
    return Stack(
      fit: StackFit.expand,
      // 显式非 directional 对齐：两个 child 都是 positioned，本就不参与
      // alignment，但显式给出可让 RenderStack 无需解析 Directionality。
      alignment: Alignment.topLeft,
      children: <Widget>[
        const Positioned(
          top: 0,
          left: 0,
          width: 0,
          height: 0,
          child: RoomOptoastWatcher(),
        ),
        // ★ P20 需求 2（D3 / D5）：5 类事件横幅的 watcher。
        //   **与 `RoomOptoastWatcher` 同层**（`RoomScope` 之下、
        //   `KeyedSubtree(pageKeyOf)` 之外），理由逐字同上面那段注释：
        //   `KeyedSubtree` 在 `meta.status` 翻转 / 切视角时换 key 重建整棵
        //   子树，放里面会连 `CriticalEventTracker` 的首帧基线 / 去重集合
        //   一起丢掉 → 历史事件被全量重播。
        //   ★ 零 RenderObject：`Positioned` 0×0 + watcher 只做「读 state →
        //     `local.pushBanner(...)`」，不占 Stack 位置、不拦截点击、不给
        //     主内容加任何约束；横幅本体由 `room_notice_overlay.dart` 画
        //     （P21：全屏遮罩，**只在有遮罩时**才建一层「点一下关当前条」的
        //     手势层，没有遮罩时连手势层都不建 —— 与 optoast 的
        //     `IgnorePointer` 全穿透是两条互补的规矩：不能点的不许吃点击，
        //     该点关的必须只吃一次）。
        //   ★ KP / 玩家 / 旁观三视角都挂 —— 本位置在角色分派之前，天然全覆盖。
        const Positioned(
          top: 0,
          left: 0,
          width: 0,
          height: 0,
          child: RoomEventBannerWatcher(),
        ),
        Positioned.fill(
          child: RoomRequestWatcher(
      // ★ P16 P-1(a)：系统返回键的**二次确认**（用户原话：「误点系统退出键
      //   退出房间，重连后 KP 视角出现 2 个玩家」）。服务端按 cid 幂等复用
      //   旧座位由波1-B 修好；客户端这一半要做的是「一次误触不该把人踢出去」。
      //   `canPop: false` → 系统手势 / 返回键不直接 pop，先落到
      //   `onPopInvokedWithResult`；确认后才走**既有那条**退出路径
      //   `Navigator.pop()`（= `_RoomShell.dispose() → onClose() →
      //   closeConnection()`），不另造一条退房链。
      //   ★ 只包本页：PopScope 只对**本路由**生效，放主题层 / 页面外层会拦到
      //     入口页与别的路由。
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          _confirmLeave();
        },
        // ★ KP-6a 核对（第二条独立换 key 路径，gp_feeds.dart:794-804
        //   同类事故）：`inGame` 只由 `isInGame(state)` = `meta.status` 派生，
        //   TextField 输入期间不写 meta.status，故本 key 不会在输入过程中
        //   翻转、不会额外丢弃 `GpSceneCheckKp` 的 State。此处只核对、
        //   不改 `pageKeyOf` 语义。
        child: KeyedSubtree(
      key: ValueKey<String>(RoomGamePage.pageKeyOf(role, inGame)),
      child: Scaffold(
        // ★ 2.34.0 / KP-6a（P0，**修根因不兜底**）：不随键盘 viewInsets
        //   压缩 body。改前 Scaffold 默认 `resizeToAvoidBottomInset: true`，
        //   TextField 获焦 → 键盘弹起 → body 高度骤降 → LayoutBuilder 的
        //   c.maxHeight 变小 → RoomGridSpec 翻 dock→folded → `_content`
        //   整条父链换形 → `_GpSceneCheckKpState.dispose()` / `_skill.dispose()`
        //   → 焦点丢 / 输入法收起 / 技能名回退「侦查」 / 栏位位置重置。
        //   ★ 红线 C9：`sheets/sheet_chat_composer.dart:168` 的聊天弹层
        //     `resizeToAvoidBottomInset: true` 逐字不动，本处只改游戏页。
        //   ★ 禁止：禁用滚动 / 循环 requestFocus / 延时重聚焦 / ClipRect
        //     硬裁 / 把 textScaler 抬到页面或 Theme 层。
        resizeToAvoidBottomInset: false,
        // 游戏页背景：按皮肤取图（暗色深紫星云 / 亮色羊皮卷），
        // 上面再压一层半透明渐变 —— 顶栏与工具条上的文字压在插图上时
        // 必须有足够对比，否则「连接中」这类小字会糊在星点上。
        //
        // 用 `Stack(fit: StackFit.expand)` 而不是裸 Stack：SafeArea 拿到
        // 的必须是**紧约束**，否则 `RoomGridSpec.of(w,h,landscape)` 读到的
        // 尺寸会变，栅格分栏跟着漂（P6 的分栏测试会直接红）。
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: ArtImage(
                Art.gameBgFor(Palette.brightness, landscape: landscape),
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Palette.bg.withValues(alpha: 0.62),
                      Palette.bg.withValues(alpha: 0.30),
                      Palette.bg.withValues(alpha: 0.66),
                    ],
                    stops: const <double>[0, 0.45, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final landscape = c.maxWidth > c.maxHeight;
                  // ★ KP-6a：dock 判据取页面根 `MediaQuery` 的屏幕短边
                  //   （`screenSize`，不受键盘 viewInsets 压缩），而不是
                  //   可能被压缩的 `c.maxHeight`。grid / compact 仍用真实
                  //   约束，五档档位语义与全部纯函数用例逐字不动。
                  final spec = RoomGridSpec.of(
                    w: c.maxWidth,
                    h: c.maxHeight,
                    landscape: landscape,
                    viewportShortSide: screenSize.shortestSide,
                  );
                  // 折叠档：方块上的「新」角标。判据类与块内一致
                  // （聊天 / 公开记录 / 只给你看同源），只在折叠档刷新。
                  final flash = spec.mode == RoomLayoutMode.folded
                      ? _foldFlash(scope, role)
                      : const <RoomSlot, bool>{};
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // 块 1：顶栏钉在顶部（P0-04：连接态三档始终可见）。
                      KeyedSubtree(
                        key: RoomKeys.keyOfSlot(RoomSlot.gpTopbar),
                        child: GpTopbar(
                          serviceBase: widget.serviceBase,
                          onSpectatorsTap: () => _showSpectators(context),
                        ),
                      ),
                      // 内容区：**剩下的高度全给它**。
                      //
                      // ★ P10 第 2 期 B 的结构变化（原来是 Stack +
                      //   Positioned(bottom:0) 把工具栏浮在内容上，再用
                      //   `GpToolbar.height + 8` 做避让）：
                      //   工具栏加高后「需要几行」随宽度非单调（见 gp_toolbar
                      //   的注释），任何固定避让常量都会在某档把最后一块盖住。
                      //   改成 Column 的最后一格后，工具栏高度由内容决定、
                      //   内容区自动拿到剩余高度 —— **结构上不可能遮挡**。
                      //   工具栏仍然是缩放容器的**兄弟节点**（不在 Transform 下），
                      //   这条结构约束不变。
                      Expanded(
                        child: _zoomHost(
                          context,
                          slotList: slots,
                          spec: spec,
                          role: role,
                          flash: flash,
                        ),
                      ),
                      // 块 11：工具栏通栏固定在屏幕最下方。
                      //
                      // 高度由内容决定（按钮全显示），但**最多占可用高度的
                      // 62%** —— 极矮屏（320dp 高手机横屏）上若不设上限，
                      // 顶栏 + 工具栏会把内容区挤成 0 并触发 RenderFlex 溢出。
                      // 上限生效时工具栏内部才会出现竖向滚动（见 gp_toolbar）。
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (c.maxHeight * kToolbarMaxShare)
                              .clamp(96.0, 640.0),
                        ),
                        child: KeyedSubtree(
                          key: RoomKeys.keyOfSlot(RoomSlot.gpToolbar),
                          // ★ P23 R1：`dock` 只在**平板横屏固定网格**（`spec.mode`
                          //   == `RoomLayoutMode.dock`）为 true —— 玩家侧据此把
                          //   「手绘板 / 笔记」两个全屏入口放进工具栏；折叠档
                          //   （单列 / 竖屏）里这两块本身就占着方块，不重复给入口。
                          child: _buildToolbar(
                            context,
                            role,
                            dock: spec.mode == RoomLayoutMode.dock,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
          ),
        ),
      ),
    ),
  ],
    );
  }

  /// 系统返回键的二次确认（P16 P-1(a)）。
  ///
  /// 确认后走**与顶栏退出按钮同一条**路径：`Navigator.of(context).pop()` 把房间
  /// 路由弹掉，`_RoomShell.dispose()` 里照常 `onClose()`（远端会
  /// `closeConnection()`）。本方法**不发任何 intent**、不改权威状态，
  /// 所以两个按钮只用本机 key，不挂 `RoomKeys.action`。
  ///
  /// ★ 刻意不自己清理 local / session：那两件事属于 `onClose`，多造一条
  ///   清理链就会和「被踢 / 结团」那条路径分叉。
  Future<void> _confirmLeave() async {
    if (_leaveConfirming || !mounted) return;
    _leaveConfirming = true;
    bool? leave;
    try {
      leave = await showRoomSheet<bool>(
        context: context,
        title: '退出房间？',
        body: (BuildContext ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('退出后需要重新加入，本机存档会保留。'),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                // 两个按钮等宽通栏一半：`Expanded` 给紧约束，文字缩放必须钳住
                // （`clampBtnText` = 只包按钮子树的 `withClampedTextScaling`），
                // 否则系统 2.0 倍字号会把「取消 / 退出」挤出按钮框。
                Expanded(
                  child: clampBtnText(
                    RoomTap(
                      key: RoomGamePage.leaveCancelKey,
                      icon: Icons.close,
                      label: '取消',
                      hint: '留在房间里',
                      minSize: RoomBtnSize.toolbarWide,
                      onTap: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: clampBtnText(
                    RoomTap(
                      key: RoomGamePage.leaveConfirmKey,
                      icon: Icons.logout,
                      label: '退出',
                      hint: '退出房间（本机存档保留）',
                      minSize: RoomBtnSize.toolbarWide,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      _leaveConfirming = false;
    }
    if (leave != true || !mounted) return;
    Navigator.of(context).pop();
  }

  /// 折叠档的三栏角标（聊天 / 公开记录 / 只给你看）。
  /// 换房间或连接层完成一次全量补拉（`syncEpoch +1`）时重置基线：
  /// 那批是历史 / 补课，不是新消息（与 `GpFeeds` 同一条规矩）。
  Map<RoomSlot, bool> _foldFlash(RoomScope scope, String role) {
    flashBoard.bindSession(
      sessionKey: scope.session,
      epoch: scope.session.syncEpoch,
    );
    return flashBoard.refresh(
      state: scope.session.state,
      mySeat: scope.session.seat,
      isKp: role == RoomRole.kp,
    );
  }

  /// 缩放宿主：`SingleChildScrollView > Transform.scale > 内容`。
  ///
  /// 只订阅 `local`（缩放 / 折叠变化稀疏）；会话变化由 RoomScope 的
  /// InheritedNotifier 自己触发重建 —— 两层分开订阅是 §1.4 的成本关键。
  ///
  /// ★ 两档高度语义不同（P10 第 2 期 B）：
  ///   · 平板横屏（dock）：内容高度**锁死**在可视区（减掉工具条避让），
  ///     固定网格才能按 flex 分出「大素材图 / 窄竖条」；
  ///   · 折叠档（folded）：内容自然向下长，外层滚动，小屏不溢出。
  Widget _zoomHost(
    BuildContext context, {
    required List<RoomSlot> slotList,
    required RoomGridSpec spec,
    required String role,
    required Map<RoomSlot, bool> flash,
  }) {
    final local = RoomScope.of(context).local;
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) {
        return LayoutBuilder(
          builder: (BuildContext ctx, BoxConstraints c) {
            final body = Transform.scale(
              key: RoomGamePage.zoomKey,
              scale: local.zoom,
              alignment: Alignment.topLeft,
              child: _content(
                ctx,
                slotList: slotList,
                spec: spec,
                local: local,
                role: role,
                flash: flash,
              ),
            );
            // ★ 工具栏在 Column 里占自己的高度，内容区拿到的就是「剩下的高度」，
            //   所以**不再需要底部避让常量**（也就不可能被工具条盖住）。
            if (spec.mode == RoomLayoutMode.dock) {
              return SingleChildScrollView(
                child: SizedBox(
                  height: c.maxHeight,
                  width: c.maxWidth,
                  child: body,
                ),
              );
            }
            return SingleChildScrollView(child: body);
          },
        );
      },
    );
  }

  /// 内容区：按 [RoomGridSpec.mode] 两档分派。
  ///
  /// ★ 两档都**不新建/不删除槽位**，也不改 `keyOfSlot` / `roomFoldKey` 的
  ///   命名 —— 12 / 13 个容器在两种布局里都恰好各出现一次，测试照旧能逐个点名。
  Widget _content(
    BuildContext context, {
    required List<RoomSlot> slotList,
    required RoomGridSpec spec,
    required RoomUiLocal local,
    required String role,
    required Map<RoomSlot, bool> flash,
  }) {
    if (spec.mode == RoomLayoutMode.dock) {
      return _dockContent(
        context,
        slotList: slotList,
        spec: spec,
        local: local,
        role: role,
      );
    }
    return _foldedContent(
      context,
      slotList: slotList,
      spec: spec,
      local: local,
      role: role,
      flash: flash,
    );
  }

  /// 平板横屏：老 APP（2.13.13）的固定比例网格。
  ///
  /// 布局**声明**在 `roomDockPlanOf`（纯数据），这里只负责把每个槽位渲染成
  /// 一格。所有格子共用 `roomBlockGap(spec)` 一个 gap，所以行列交叉处必然
  /// 对齐（用户抱怨的「手摆的栏位没对齐」在结构上被消除）。
  Widget _dockContent(
    BuildContext context, {
    required List<RoomSlot> slotList,
    required RoomGridSpec spec,
    required RoomUiLocal local,
    required String role,
  }) {
    final gap = roomBlockGap(spec);
    final plan = roomDockPlanOf(isKp: role == RoomRole.kp);
    // ★ 2.34.0 / KP-5：`plan` 的 KP 右列现在是 `RoomStackNode`（契约 I7）。
    //   `buildRoomLayout` 的 Stack + Positioned.fill 分支会为 `gpScene` /
    //   `gpPlayers` 各调一次 `cellOf` → 各走一次 `_slotView` → `_bodyOf`，
    //   两格 Rect 逐边相等、一起占满右列、底端仍与 `gpMap` 对齐。
    //   ★ 收起态只作用于 `gpPlayers` 子树；`gpScene` 是同 Stack 的另一个
    //     子节点，独立常驻，绝不因收起被卸载（KP-6a 红线）。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kRoomSidePadding),
      child: buildRoomLayout(
        node: plan,
        gap: gap,
        cellOf: (RoomSlot slot) =>
            _slotView(context, slot, spec, local, role),
      ),
    );
  }

  /// 平板竖屏 / 手机横竖屏：少数面板展开 + 其余收成方块平铺。
  Widget _foldedContent(
    BuildContext context, {
    required List<RoomSlot> slotList,
    required RoomGridSpec spec,
    required RoomUiLocal local,
    required String role,
    required Map<RoomSlot, bool> flash,
  }) {
    final gap = roomBlockGap(spec);
    // ★ P17 P-2：state 要参与「展开区」判定（战斗态把战斗信息栏提到首位），
    //   所以先取 state 再算 expanded。
    final state = RoomScope.of(context).session.state;
    final seat = RoomScope.of(context).session.seat;
    // 战斗态：战斗信息栏强制展开（忽略用户折叠态），且已在 expanded 首位。
    final bool combat = isCombat(state);
    final expanded = roomExpandedSlots(slotList, role, state: state);
    // ★ P10 第 3 期 B：把「内容区槽位顺序」纯函数真正接进渲染。
    //   改前 `roomOrderedContentSlots` 在 lib 内零调用，只有单测断言它 ——
    //   单列档「私密栏提到第一位（等价旧版 CSS order:-1）」这条语义
    //   是永久绿但保护不到真实界面。接进来之后折叠档真实方块顺序与
    //   `room_layout_test` 的断言同源。
    final squares = roomOrderedContentSlots(
      roomFoldedSlots(slotList, role, state: state),
      spec,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kRoomSidePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final slot in expanded)
            // ★ P20 需求 4①（方案 A / D9）：`gpKpTools` 进了
            //   `kKpExpandedSlots`，但它**不单独出面板** —— 它由 `gpMap`
            //   那一格的「组合格」`_kpStageToolsCell` 在舞台下沿渲染。
            //   所以这里必须 `continue`，否则 `gpKpTools` 的容器 key 会
            //   全库出现两次（`room_ui_layout_test.dart:262-265` /
            //   `p10_t3_layout_test.dart:164-166` 的「12 个 key 各
            //   findsOneWidget」会红）。
            if (slot != RoomSlot.gpKpTools)
              Padding(
                padding: EdgeInsets.only(bottom: gap),
                // ★ `gpMap` 走组合格（素材舞台 + 工具窄栏常驻吸附）；
                //   其余槽位维持「展开区也可收起」的原逻辑。
                child: slot == RoomSlot.gpMap
                    ? _kpStageToolsCell(
                        context,
                        local,
                        role,
                        flash,
                        state,
                        seat,
                      )
                    // 展开区也可收起（用户口述「也可收起」）：收起后退回方块区。
                    // ★ P17 P-2：战斗态下 `gpPlCombat` **强制展开** —— 折叠头
                    //   仍可点（只记用户偏好），但战斗期间一律按展开面板渲染。
                    : local.isFolded(slot.name) &&
                            !(combat && slot == RoomSlot.gpPlCombat)
                        ? _squareOf(
                            context, slot, local, role, flash, state, seat)
                        : _expandedPanel(context, slot, spec, local, role),
              ),
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: <Widget>[
              for (final slot in squares)
                _squareOf(context, slot, local, role, flash, state, seat),
            ],
          ),
        ],
      ),
    );
  }

  /// 共享 gap 的展开面板：折叠头（沿用 `RoomUiLocal.folded`）+ 真块。
  Widget _expandedPanel(
    BuildContext context,
    RoomSlot slot,
    RoomGridSpec spec,
    RoomUiLocal local,
    String role,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FoldHeader(
          key: roomFoldKey(slot),
          title: roomSlotTitle(slot),
          folded: false,
          onToggle: () => local.toggleFold(slot.name),
        ),
        KeyedSubtree(
          key: RoomKeys.keyOfSlot(slot),
          child: _bodyOf(context, slot, role),
        ),
      ],
    );
  }

  /// ★ P20 需求 4①（方案 A / D9）：「素材舞台 · 工具窄栏」组合格。
  ///
  /// 折叠档里 `gpMap` 与 `gpKpTools` **不再各自占一格**，而是并成一格：
  /// ```
  /// FoldHeader「素材舞台 · 工具窄栏」(key: roomFoldKey(gpMap), 收起两者)
  ///   → KeyedSubtree(key: keyOfSlot(gpMap))     → GpMapStage / 战斗信息格
  ///   → SizedBox(height: kKpStageToolsSeam)     → 4dp 细缝（不是共用 gap）
  ///   → KeyedSubtree(key: keyOfSlot(gpKpTools)) → GpKpTools
  /// ```
  /// ★ 为什么要「组合」而不是「复用 `_expandedPanel` 渲两个面板」：
  ///   用户原话是「工具窄栏**吸附**在素材舞台下方」，两个独立 `FoldHeader`
  ///   + 共用 gap 会读成两块互不相干的面板，且折叠头上会多出一行标题。
  ///   组合后只有一个折叠头，收起 / 展开是一次动作、两块一起动。
  ///
  /// ★ `gpMap` 自己**被用户收起**时（`local.isFolded('gpMap')`）：
  ///   上半换成 `_squareOf(gpMap)`（104dp 方块，自带标题 / 摘要 /
  ///   「展开到面板」抓手，`foldKey` 仍是 `roomFoldKey(gpMap)`），
  ///   但**下半的 `gpKpTools` 照旧渲染** —— 需求要的是工具窄栏「常驻展开」。
  ///   ★ `gpKpTools` 的容器 key 必须全库**恰好一次**：它只在
  ///     `_foldedContent` 的这个方法里出现（循环里那一条 `continue` 掉了，
  ///     `roomFoldedSlots` 也因白名单把它从方块区剔除），所以两条分支
  ///     各渲一次不会重复。
  Widget _kpStageToolsCell(
    BuildContext context,
    RoomUiLocal local,
    String role,
    Map<RoomSlot, bool> flash,
    Map<String, Object?> state,
    String seat,
  ) {
    final bool mapFolded = local.isFolded(RoomSlot.gpMap.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (mapFolded)
          _squareOf(context, RoomSlot.gpMap, local, role, flash, state, seat)
        else ...<Widget>[
          FoldHeader(
            key: roomFoldKey(RoomSlot.gpMap),
            title: '素材舞台 · 工具窄栏',
            folded: false,
            // 一次动作收起 / 展开**两块**：工具窄栏的展开态恒等于舞台的
            // 展开态，没有第二个独立开关（`local` 里也不该多一个字段）。
            onToggle: () => local.toggleFold(RoomSlot.gpMap.name),
          ),
          KeyedSubtree(
            key: RoomKeys.keyOfSlot(RoomSlot.gpMap),
            // ★ `_bodyOf` 在这里拿无界高度（折叠档 Column 高度自然向下长），
            //   所以**绝不传** `fill: true`；战斗态下 `_combatStageCell` 自己
            //   会走 `MainAxisSize.min` 分支。
            child: _bodyOf(context, RoomSlot.gpMap, role),
          ),
        ],
        const SizedBox(height: kKpStageToolsSeam),
        KeyedSubtree(
          key: RoomKeys.keyOfSlot(RoomSlot.gpKpTools),
          // ★ 同一个 `stageControl`：工具窄栏的画笔 / 橡皮 / 落点要作用到
          //   上面那一格的素材舞台（`_bodyOf` 里已是唯一构造处）。
          child: _bodyOf(context, RoomSlot.gpKpTools, role),
        ),
      ],
    );
  }

  /// 收起的一格：标题 + 一行摘要（+ 新消息角标），点开全屏显示真块。
  Widget _squareOf(
    BuildContext context,
    RoomSlot slot,
    RoomUiLocal local,
    String role,
    Map<RoomSlot, bool> flash,
    Map<String, Object?> state,
    String seat,
  ) {
    final restorable = roomExpandedSlots(
      role == RoomRole.kp ? RoomKeys.kpSlots : RoomKeys.plSlots,
      role,
    ).contains(slot);
    return RoomSlotSquare(
      key: RoomKeys.keyOfSlot(slot),
      slot: slot,
      title: roomSlotTitle(slot),
      summary: roomSlotSummary(slot, state, seat: seat),
      flashing: flash[slot] ?? false,
      foldKey: roomFoldKey(slot),
      onUnfold: restorable ? () => local.setFold(slot.name, false) : null,
      onOpen: () {
        // 点开即视为已读：角标是纯派生状态，无 Timer、无动画。
        flashBoard.dismiss(slot);
        // ★ 2.34.0 / PV-3 核对：`openRoomSlotFullscreen` →
        //   `showFullscreenReader`（`room_sheet.dart:121-142`，契约 C8
        //   全局壳禁改）会用 `getInheritedWidgetOfExactType<RoomScope>()`
        //   取到作用域并在新路由里**重提供** `RoomScope(session/local/
        //   controller)`，故 `Builder(builder: body)` 的 ctx 能拿到
        //   `RoomScope.of(ctx)`；`_bodyOf` 返回的是**订阅式真块**
        //   （如 `GpPrivates()`，其全屏订阅式 + 贴底由 W-C 在
        //   `gp_privates.dart` 内完成），不是 rows 快照。
        //   既然作用域已重提供，此处**不再补第二层 RoomScope**（避免
        //   InheritedNotifier 重复订阅 / 祖先链断言漂移）。
        openRoomSlotFullscreen(
          context,
          title: roomSlotTitle(slot),
          // ★ P20 需求 3⑤：全屏里没有「叠放」语境 —— `gpPlMates` 必须强制
          //   展开，否则点开队友方块只看到一条 28dp 标题行 + 「展开」按钮。
          //   其余 slot 忽略该参数（只有 `gpPlMates` 分支读它）。
          body: (BuildContext ctx) =>
              _bodyOf(ctx, slot, role, matesForcedOpen: true),
        );
      },
    );
  }

  /// 单个槽位（平板横屏的一格）：容器 key 恒在；块体超出格子时**格内滚动**，
  /// 绝不溢出到相邻格（固定网格最容易踩的就是这条）。
  ///
  /// ★ 两块兜底保护，都在**布局层**、都不动块内 UI：
  ///   · 高度超出格子 → 格内竖向滚动；
  ///   · 宽度窄于该块的最小可用宽度（见 `roomDockMinWidthOf`）→ 给出下限宽度
  ///     后格内横向滚动。否则像「KP 工具窄栏的五色板行」这种固定行会
  ///     `RenderFlex overflow`，把整格的布局判成异常。
  Widget _slotView(
    BuildContext context,
    RoomSlot slot,
    RoomGridSpec spec,
    RoomUiLocal local,
    String role,
  ) {
    return KeyedSubtree(
      key: RoomKeys.keyOfSlot(slot),
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
        // ★ P20 需求 3⑦：`fill: true` 只在**平板横屏固定网格**里成立
        //   （`_slotView` 只被 `_dockContent` 调用，且上面已把
        //   `gpPlChat` / `gpPlLog` 加进紧约束白名单）。
        //   折叠档的 `_expandedPanel` / `_squareOf` 走默认 `fill: false` ——
        //   那里高度无界，`SectionBox(expand: true)` 会断言失败。
        final body = _bodyOf(context, slot, role, fill: true);
        // ★ P10 第 7 期：素材舞台自己按 16:9 居中，必须拿到**紧约束**才能
        //   填满格子；包一层竖向 SingleChildScrollView 会让高度无界，舞台只能
        //   按宽度算高、格内剩下大片空白（用户「中间一大片空白」的真因之一）。
        //
        // ★ P16 KP-9：`gpKpLeft`（地图 / NPC / 素材栏）也走紧约束分支 ——
        //   用户要的是「左栏背景铺到栏位底端」。走竖向 SingleChildScrollView
        //   时高度**无界**，栏内块只能按内容撑高，底部必然留一条底色错位的空白。
        //   改后左栏拿到**有界高度**：栏内用 `Column + Expanded` 吃满即可。
        //   ★ 契约（给 `gp_kp_left.dart` 的施工方）：`_slotView` 已给
        //     `gpKpLeft` 紧约束（有界高度），左栏需用 Column + Expanded 拉伸吃满；
        //     配合 KP-3 删掉待办栏后，左栏底端 = 中排聊天栏底端，天然对齐。
        //   其余槽位沿用原滚动兜底（超内容不溢出到邻格）。
        //   ★ P20 需求 3⑦（D8）：`gpPlChat` / `gpPlLog` 也走紧约束分支 ——
        //     这两格里的 `GpFeeds(fill: true)` 用 `Expanded(FeedList)`
        //     + 底部输入行（`SectionBox(expand: true)`），**父级必须有界高度**；
        //     若仍被竖向 `SingleChildScrollView` 包住（`maxHeight == infinity`），
        //     无界约束下 `Expanded` 直接断言失败。
        //     ★ 这也是「双层滚动」的根因：改前整卡内容 ≈308dp > 格高 ≈130dp，
        //       外层被迫出现竖向 Scrollable，内层 220dp 的 `ListView` 又吃手势
        //       —— 用户说的「输入行被挤到看不见 / 滚不动」。
        //     ★ 顺序铁律：本白名单必须先落，任何地方才有资格传 `fill: true`。
        if (slot == RoomSlot.gpMap ||
            slot == RoomSlot.gpPlMap ||
            slot == RoomSlot.gpKpLeft ||
            slot == RoomSlot.gpPlChat ||
            slot == RoomSlot.gpPlLog ||
            // ★ 2.36.0 / Q2：KP 收起玩家信息栏后，本格不能再套
            //   SingleChildScrollView —— `Scrollable` 的 opaque 手势层会占满
            //   `Positioned.fill` 给的整格并吸收全部命中，导致共 rect 的底层
            //   gpScene（GpSceneCheckKp）按钮点不到、输入框获不了焦。
            //   收起态只留 `GpKpPlayers` 内部的 28dp 标题行 + ClipRect
            //   （两者 hitTestSelf 均为 false），其余区域整体穿透。
            //   ★ 外层 `_content` 已订阅 `local`（:646），收起切换会重建本格，
            //     故此处直接读 `local` 即可，不必再嵌一层 ListenableBuilder。
            (slot == RoomSlot.gpPlayers && local.playersPanelCollapsed) ||
            // ★ P20 需求 3⑤（D7 同一成因的玩家版）：`gpPlMates` 收起后只返回
            //   `Align + 28dp` 标题行，与 `gpPlScene` 共 rect。若本格仍被
            //   `SingleChildScrollView` 包住，Scrollable 的 opaque 手势层会把
            //   下层场景检定栏的 pointer 全吃掉 —— 正是用户提过的「收起后
            //   下层点不到」。
            (slot == RoomSlot.gpPlMates && !local.matesOpen)) {
          return ClipRect(child: body);
        }
        final minWidth = roomDockMinWidthOf(slot);
        final tooNarrow = c.maxWidth < minWidth;
          final column = SingleChildScrollView(
            child: tooNarrow ? SizedBox(width: minWidth, child: body) : body,
          );
          return ClipRect(
            child: tooNarrow
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: column,
                  )
                : column,
          );
        },
      ),
    );
  }

  /// 槽位 → 真块（设计 §2.3 / T02-T05 的接线表）。
  ///
  /// 已接：T03 的 6 块（舞台 / 战斗 / 聊天 / 记录 / 私密 / 状态条）
  ///      + T04 的 4 块（左窄栏 / 工具窄栏 / 场景检定 / 玩家信息）
  ///      + T05 的 5 块（角色卡 / 场景检定 / 队友 / 手绘板 / 笔记）。
  /// 顶栏与工具栏不走这里（它们被钉在 Column 顶部与 Stack 底部）。
  ///
  /// ★ 读 `local` 的块（`GpPlMates` / `GpPlSketch`）块内已自带
  ///   `ListenableBuilder(local)`，但这里仍**一律非 const** 构造 ——
  ///   `const` 实例会被元素树按身份（`identical`）跳过更新，连块内那层
  ///   订阅都轮不到执行，仍须每次新建。
  ///
  /// [fill]（P20 需求 3⑦ / D8）：只对 `gpPlChat` / `gpPlLog` 有意义 ——
  ///   `true` 时两个信息流转 `GpFeeds(fill: true)`（`Expanded(FeedList)` +
  ///   底部输入行，整卡吃满格高）。**只能由 `_slotView` 传 `true`**
  ///   （平板横屏固定网格，父级有界高度且已在紧约束白名单里）；
  ///   折叠档 / 全屏阅读器（高度无界）必须保持默认 `false`，否则
  ///   `SectionBox(expand: true)` 里的 `Expanded` 会断言失败。
  ///   KP 侧 `gpChat` / `gpLog` **一个参数都不传**（逐字维持旧渲染）。
  ///
  /// [matesForcedOpen]（P20 需求 3⑤）：只对 `gpPlMates` 有意义 ——
  ///   `true` 时传 `GpPlMates(forceOpen: true)`，**无视 `local.matesOpen`**
  ///   直接渲染队友列表。
  ///   · **只有折叠方块的「点开全屏」传 `true`**（`_squareOf` 的 `onOpen`）：
  ///     全屏路由里没有「叠放」语境，不强制展开就只剩一条 28dp 标题行；
  ///   · dock 叠放（`_slotView`）与折叠展开区（`_expandedPanel`）**保持默认
  ///     `false`**，一律吃 `local.matesOpen` —— 那两处是 `RoomStackNode`/
  ///     竖向 Column 的叠放语境，默认展开会与场景检定栏逐像素同 rect 并把它
  ///     盖死（1280×800 实测两边都是 `LTRB(920.2, 38.0, 1272.0, 403.7)`）。
  Widget _bodyOf(
    BuildContext context,
    RoomSlot slot,
    String role, {
    bool fill = false,
    bool matesForcedOpen = false,
  }) {
    final isKp = role == RoomRole.kp;
    switch (slot) {
      // ---- T03 ----
      case RoomSlot.gpMap: {
        // ★ P16 KP-4②：KP 进入战斗态后，这一格变成「战斗信息」格 ——
        //   顶部一条 28dp 细标题行，下面在「素材舞台（摆位）」与「战斗列表」
        //   之间切换（战斗信息栏从右列 gpCombat 搬到这里）。
        //   非战斗态仍是纯舞台（KP 要摆位）；玩家档不走这条分支。
        final scope = RoomScope.of(context);
        if (isKp && isCombat(scope.session.state)) {
          // ★ P20：KP 侧 `readOnly` 恒 false（摆位 / 画笔都归 KP）。
          return _combatStageCell(scope, context, readOnly: false);
        }
        // KP 侧与块 3 共用同一个 stageControl。
        return _mapStage(readOnly: false);
      }
      case RoomSlot.gpPlMap: {
        // ★ P20 需求 3③：玩家右列的 `gpPlCombat` 叶子已删，战斗信息栏搬进
        //   本格（与 KP-4② 完全同构）。判据两条：
        //     · `isCombat(state)` —— 非战斗态**不渲染任何标题行**，直接是舞台
        //       （用户：「平时就是素材图」）；
        //     · `!local.plCombatPanelCollapsed` —— 玩家档默认**收起**
        //       （`RoomUiLocal.plCombatPanelCollapsed = true`），所以进战斗后
        //       默认仍是素材舞台，点标题行「展开」才换成战斗列表。
        //   ★ 权限红线：`readOnly` 必须 `true` —— 漏了玩家就能在**公开素材**
        //     上作画 / 拖点，这是权限事故。`_mapStage(readOnly: true)` 与
        //     `_placeActor` / `_placePlayer` 的回调也保持 `null`。
        final scope = RoomScope.of(context);
        if (isCombat(scope.session.state) &&
            !scope.local.plCombatPanelCollapsed) {
          return _combatStageCell(scope, context, readOnly: true);
        }
        return _mapStage(readOnly: true);
      }
      case RoomSlot.gpCombat:
      case RoomSlot.gpPlCombat:
        return const GpCombatList();
      case RoomSlot.gpChat:
        // ★ P20 需求 3⑦：KP 侧**一个参数都不传**，渲染逐字维持旧口径。
        // ★ P17 P-3（G-1 裁决）：锁定态聊天**发送**要禁 —— 用户口径是
        //   「昏迷 / 疯狂时只能点『推进 1 轮』和『更多工具』」，聊天属于操作；
        //   求助路径已由「更多工具 → 申请治愈」承担。
        // ★ 判据用 [_chatLockedOf]（比工具栏少禁一态）：**撕卡仍可聊天**，
        //   保留 P10 T-20 的社交口子（角色卡文案也与之一致）。
        //   历史仍可滚动查看（只禁输入 / 发送，不禁看）。不能写 `const`。
        return GpFeeds(
          pane: FeedPane.chat,
          locked: _chatLockedOf(context, role),
        );
      case RoomSlot.gpPlChat:
        // ★ P20 需求 3⑦ + D8：玩家 dock 的聊天栏转 `fill` 模式
        //   （吃满格高，输入行常驻可见、不再双层滚动）。
        return GpFeeds(
          pane: FeedPane.chat,
          locked: _chatLockedOf(context, role),
          fill: fill,
        );
      case RoomSlot.gpLog:
        // 公开记录是只读信息流：没有输入行，锁定态照旧可看（不需要 locked）。
        return const GpFeeds(pane: FeedPane.record);
      case RoomSlot.gpPlLog:
        // ★ P20 需求 3⑦ + D8：同 `gpPlChat`，只有 `fill` 一个差异。
        return GpFeeds(pane: FeedPane.record, fill: fill);
      case RoomSlot.gpPriv:
        return const GpPrivates();
      case RoomSlot.gpStatus:
        return const GpStatus();

      // ---- T04 ----
      case RoomSlot.gpKpLeft:
        return const GpKpLeft();
      case RoomSlot.gpKpTools:
        // ★ 同一个 stageControl：块 3 的画笔/橡皮/落点要作用到块 4 的舞台。
        return GpKpTools(stage: stageControl);
      case RoomSlot.gpScene:
        // ★ KP-6a：稳定 key 链（配合 W-A 在 TextField 上的 PageStorageKey
        //   + AutomaticKeepAliveClientMixin + 显式 FocusNode），父链换形时
        //   尽量复用同一 State，避免 `_skill` 被 dispose 导致技能名回退。
        return GpSceneCheckKp(
          key: RoomGamePage.sceneCheckHostKey,
          onOpenEditor: (BuildContext ctx) => showSceneSheet<void>(ctx),
        );
      case RoomSlot.gpPlayers:
        // ★ KP-5 / 契约 I8、C12：**去 `const`** —— const 实例会被元素树按
        //   identical 跳过 build，块内 W-E 自带的
        //   `ListenableBuilder(local)` 订阅层就永远轮不到执行。
        //   ★ 收起 UI（28dp 标题行 + `GpKpPlayersKeys.collapseToggle` +
        //     `Offstage` body）**全部由 W-E 在 `gp_kp_players.dart` 内部
        //     实现**，本页只负责叠放接线，不再包第二层容器 / 标题行 / toggle
        //     —— 否则会出现双重标题行、双 toggle，且外层 Offstage 会把 W-E
        //     常驻的展开入口一起隐藏，收起后无法再展开。
        //   ★ 收起态只控 `GpKpPlayers` 子树；`GpSceneCheckKp` 是
        //     `RoomStackNode` 的另一个独立子节点，常驻、绝不卸载。
        return GpKpPlayers();

      // ---- T05：玩家专属 5 块 ----
      // ★ 一律**非 const**构造：`const` 实例会被元素树按身份（`identical`）
      //   复用、连 `build` 都不调，块内新加的 `local` 订阅层就永远轮不到执行。
      case RoomSlot.gpPlCharCard:
        return GpPlCharCard();
      case RoomSlot.gpPlScene:
        // ★ P20 需求 3②：`gpPlSketch` / `gpPlNotes` 两个 dock 叶子已删，
        //   但这两个功能必须仍有按钮入口。
        //   ★ P23 R1 修订：入口**已搬进玩家工具栏**（见 `_buildToolbar` 的
        //     `if (!isKp && dock)` 两段，key 仍是 `plSketchKey` / `plNotesKey`）。
        //     本格因此回到「纯 `GpSceneCheckPl()`」—— 格顶不再有一条 28dp
        //     按钮行把场景检定栏往下推，场景格顶边 = 右列顶边。
        //   ★ 非 const 构造不变（`GpSceneCheckPl` 块内要跑
        //     `ListenableBuilder(local)`，const 实例会被元素树按 identical
        //     跳过 build，订阅层永远轮不到执行）。
        return GpSceneCheckPl();
      case RoomSlot.gpPlMates:
        // ★ P20 需求 3⑤：`forceOpen` 只由折叠方块的「点开全屏」传入。
        //   dock 叠放 / 折叠展开区吃 `local.matesOpen`（默认 false = 收起）。
        //   ★ 非 const 构造：`const` 实例会被元素树按身份跳过 build，
        //     块内那层 `ListenableBuilder(local)` 就轮不到执行。
        return GpPlMates(forceOpen: matesForcedOpen);
      case RoomSlot.gpPlSketch:
        return GpPlSketch();
      case RoomSlot.gpPlNotes:
        return GpPlNotes();

      // ---- 由顶栏 / 工具栏 / 战斗条独立渲染，正常不会走到这里 ----
      // ★ K-01：占位块已全部替换，这里只留零尺寸兜底（不许再出现占位块）。
      // ★ 但「静默空白」比占位块更难排查，所以开发期直接炸出来：
      //   release 下 `assert` 被裁掉，行为仍是零尺寸兜底。
      case RoomSlot.gpTopbar:
      case RoomSlot.gpToolbar:
      case RoomSlot.gpCombatStrip:
        assert(false, '槽位 ${slot.name} 不该出现在内容区');
        return const SizedBox.shrink();
    }
  }

  /// 素材舞台的唯一构造处（P16 KP-11：把「放单位 / 放玩家」的落点回调接上）。
  ///
  /// ★ 改前这两个回调一个都没传，`GpMapStage._onTap` 里 `widget.onPlaceActor?.`
  ///   永远命中 null —— KP 点完「放单位」「放玩家」再点舞台是**空操作**。
  ///   只读侧（玩家 / 旁观）依旧不传：结构上不给落点能力。
  Widget _mapStage({required bool readOnly}) => GpMapStage(
        controller: stageControl,
        readOnly: readOnly,
        onPlaceActor: readOnly ? null : _placeActor,
        onPlacePlayer: readOnly ? null : _placePlayer,
        // ★ P12 KP-1c/PL-3c：主页舞台是半屏档（fullscreenMode=false）。
        //   「全屏」唯一入口在 GpMapStage 内部：点 GpMapStageKeys.fullscreen
        //   → showMapStageFullscreen 推独立路由，并在新路由内重包 RoomScope
        //   透传同一份 session / local / controller / stageControl。
        //   Navigator.pop 后本 State 不卸载 → 原栏位 / dock-folded 档位零漂移。
        fullscreenMode: false,
      );

  /// 战斗态的素材舞台格（P16 KP-4②；P20 需求 3③ 起玩家侧也走这里）。
  ///
  /// 细标题行 + 下方二选一：收起 → 回到舞台（摆位 / 只读），展开 → 战斗列表。
  ///
  /// [readOnly] 是**权限红线**，不是样式开关：
  ///   · KP 侧 `false` → 舞台可摆位、画笔可用、落点回调非 null；
  ///   · 玩家侧 `true` → 舞台只读，`onPlaceActor` / `onPlacePlayer` 均为 null。
  ///     **漏了这一个 `true`，玩家就能在公开素材上作画 / 拖点**。
  ///   构造函数里用 `required` 就是让每个调用点必须显式表态（编译器兜底）。
  ///
  /// 收起状态字段**按视角分流**（两块严格隔离，见 `RoomUiLocal` 注释）：
  ///   · KP → `local.combatPanelCollapsed`（默认 false = 展开，战斗优先）；
  ///   · 玩家 → `local.plCombatPanelCollapsed`（默认 true = 收起，素材优先）。
  ///
  /// ★ 两档高度语义（必须分开，否则折叠档会直接抛异常）：
  ///   · **dock**（有界高度）：标题行 + `Expanded`，舞台 / 列表吃掉剩余高度；
  ///   · **folded / 全屏阅读器**（高度无界）：`Expanded` 在无界约束下会
  ///     `RenderFlex children have non-zero flex…` 断言失败，所以退回
  ///     `MainAxisSize.min` 的自然高度列（舞台靠 `AspectRatio` 按宽度定高，
  ///     列表按自身内容高，外层本来就有滚动兜底）。
  Widget _combatStageCell(
    RoomScope scope,
    BuildContext context, {
    required bool readOnly,
  }) {
    final bool collapsed = readOnly
        ? scope.local.plCombatPanelCollapsed
        : scope.local.combatPanelCollapsed;
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        final Widget body = collapsed
            // ★ 收起态 = 素材舞台。`readOnly` 原样透传（权限红线）。
            ? _mapStage(readOnly: readOnly)
            : const GpCombatList();
        final Widget header = _combatHeader(
          context,
          collapsed: collapsed,
          // 收起状态的写入口也按视角分流，与上面的读同源。
          onToggle: () => readOnly
              ? scope.local.setPlCombatPanelCollapsed(!collapsed)
              : scope.local.setCombatPanelCollapsed(!collapsed),
        );
        if (!c.hasBoundedHeight) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[header, body],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[header, Expanded(child: body)],
        );
      },
    );
  }

  /// 「战斗信息」细标题行（固定 [RoomGamePage.combatHeaderHeight] dp）。
  ///
  /// [onToggle] 由调用方给（KP / 玩家写不同的本地字段，见
  /// [_combatStageCell]）—— 本方法只负责渲染，不碰 `RoomUiLocal`。
  ///
  /// ★ 固定尺寸控件必须能在系统大字体下不溢出：这里用
  ///   `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` **只包这一行
  ///   子树**（不用 `ClipRect` 硬裁，也不把钳制抬到页面 / Theme 层）。
  Widget _combatHeader(
    BuildContext context, {
    required bool collapsed,
    required VoidCallback onToggle,
  }) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(fontWeight: FontWeight.w600);
    return SizedBox(
      height: RoomGamePage.combatHeaderHeight,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.0,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '战斗信息',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            RoomTap(
              key: RoomGamePage.combatToggleKey,
              icon: collapsed ? Icons.expand_more : Icons.expand_less,
              label: collapsed ? '展开' : '收起',
              hint: collapsed ? '展开战斗信息列表' : '收起列表，回到素材舞台',
              // 高度必须**等于**标题行高，不能取 `RoomBtnSize`（那是工具栏族
              // 40 / 面板族 48 的档位，套进来会把这一行撑破）。
              minSize: const Size(72, RoomGamePage.combatHeaderHeight),
              onTap: onToggle,
            ),
          ],
        ),
      ),
    );
  }

  /// 「放单位」落点 → `map.mark`（P16 KP-11）。
  void _placeActor(String actorName, NormPoint at) =>
      _placeMark(kind: 'actor', label: actorName, at: at);

  /// 「放玩家」落点 → `map.mark`（P16 KP-11）。
  void _placePlayer(String playerSeat, NormPoint at) =>
      _placeMark(kind: 'player', label: playerSeat, at: at);

  /// 落点下发（**载荷口径已对着 domain 核过，不是猜的**）。
  ///
  /// ★ `map.mark` 的权威实现是 `room_model_actions_room.dart:905` 里的 `mapMark`
  ///   （`lib/domain/room_model_actions_room.dart:905`）只认
  ///   `x` / `y` / `kind` / `label` / `assetId` / `revealed` 六个键，
  ///   标点记录里**没有**「单位 / 玩家」的专有字段；POLICY 里的地图动作也只有
  ///   `map.mark` / `map.stroke` / `map.clear` / `map.strokes.set` 四个。
  ///   所以本批**不新造 domain op、不改 domain**：
  ///   · 坐标直接复用舞台自己发标点时的 `stagePointJson`（归一化 `{x, y}`）；
  ///   · 「放的是单位还是玩家」编码进 `kind`（`actor` / `player`）；
  ///   · 名字 / 座位编码进 `label`（权威端 `cleanText(..., 24)` 会裁长）。
  ///   视觉结果 = 舞台上多一个带名字的标点；这是现有 domain 能表达的那一半。
  ///
  /// ★ 权限口径与工具窄栏完全一致（`GpKpTools` 的「放单位 / 放玩家」两个
  ///   按钮判的就是 `gate.can('map.mark')`），不自造条件。
  void _placeMark({
    required String kind,
    required String label,
    required NormPoint at,
  }) {
    final RoomScope scope = RoomScope.read(context);
    if (!scope.controller.gate.can('map.mark')) return;
    scope.controller.hostAction('map.mark', <String, Object?>{
      ...stagePointJson(at),
      'kind': kind,
      'label': label,
      'revealed': true,
    });
  }

  /// 本人是否处于「锁定态」（P17 P-3 / G-1 的**单一真源**）。
  ///
  /// 计算链（与权威端 `_passSelf`、角色卡 `selfLocked` 同表达式）：
  /// `session.state` → `members` 里按 `session.seat` 找本人（`findMe`，
  /// 查不到 = 旁观者 → null）→ `operationLocked(mem)`
  /// （`view/member_view.dart:167`，与 `room_model_host_intent.dart` 的
  /// `_memberLocked` 同判据：死亡 / 濒死 / 昏迷 / 永久·临时·不定疯狂）。
  ///
  /// ★ 用途：工具栏 / 骰子条 / 治疗 —— 这些是**权威动作**，含撕卡在内全禁。
  /// 聊天另有更窄的一条，见 [_chatLockedOf]。
  /// ★ 只有玩家视角参与：KP 侧恒 false；旁观者按口径**不适用**（恒 false，
  ///   且第 3 步本就返回 null）。
  bool _lockedOf(BuildContext context, String role) {
    if (role != RoomRole.player) return false;
    final scope = RoomScope.read(context);
    return operationLocked(findMe(scope.session.state, scope.session.seat));
  }

  /// 聊天输入行专用：比 [_lockedOf] **少禁一态**（撕卡仍可聊天）。
  ///
  /// ★ 为什么聊天要比工具栏窄：`operationLocked` 含「死亡 / 永久疯狂」
  ///   （= 撕卡），而 P10 T-20 刻意给撕卡玩家留了社交口子 —— 角色卡文案
  ///   `gp_pl_char_card.dart:186` 就是「已撕卡 / 无法行动：**只能聊天**」，
  ///   `test/qa_p5_priv_probe_test.dart:483-484` 也钉着「撕卡后仍能聊天」。
  ///   用户本次口径只说了「昏迷或疯狂时什么都不能操作」，没要求收回这个口子。
  /// ★ 于是聊天只禁「昏迷 / 濒死 / 疯狂发作」三态：
  ///   `operationLocked(me) && !isRipped(me)`（撕卡判据复用
  ///   `member_view.dart:163` 的 `isRipped`，与角色卡同一份，不自己写判定）。
  bool _chatLockedOf(BuildContext context, String role) {
    if (role != RoomRole.player) return false;
    final scope = RoomScope.read(context);
    final me = findMe(scope.session.state, scope.session.seat);
    return operationLocked(me) && !isRipped(me);
  }

  /// 底部工具条：骰子条 + （KP）KP 工具弹层入口 + （玩家 dock）手绘板 / 笔记
  /// + 调用方注入的扩展。
  ///
  /// ★ 它在 `Stack` 里是缩放容器的**兄弟节点**，所以「工具栏不在 Transform
  ///   子树内」这条结构断言对新增内容继续成立（T02 判据 4）。
  /// ★ P23 R1（用户：「玩家视角（平板横屏布局）笔记和手绘板按钮放到玩家工具栏」）：
  ///   [dock] = 当前是不是**平板横屏固定网格**（`RoomGridSpec.mode ==
  ///   RoomLayoutMode.dock`）。只有 `!isKp && dock` 时才往 [GpToolbar] 的
  ///   `mainActions` 末尾追加「手绘板 / 笔记」两个全屏入口。
  ///   · 折叠档（单列 / 竖屏）**不渲染**这两个按钮 —— 那里 `gpPlSketch` /
  ///     `gpPlNotes` 本来就是独立方块（`_squareOf` / `_expandedPanel`），
  ///     再给一份工具栏入口就是双入口。
  ///   · 这两个按钮**不传 `enabled:`**（口径与旧 `_plExtrasRow` 逐字一致：
  ///     纯本机功能，与公开素材无关，锁定态仍可用），**也不挂**
  ///     `RoomKeys.action(...)`（本机弹层不是 POLICY action，挂了会被 T-30
  ///     表驱动探针误判成权威动作而要求 `enabled == gate.can(op)`）。
  Widget _buildToolbar(BuildContext context, String role, {bool dock = false}) {
    final isKp = role == RoomRole.kp;
    final scope = RoomScope.read(context);
    final gate = scope.controller.gate;
    final canOpenMisc = gate.can(kRoomHistoryExportPolicyOp);
    // ★ P17 P-3：锁定态（死亡 / 濒死 / 昏迷 / 三类疯狂）统一禁用。
    //   判定唯一来源是 [_lockedOf]（含撕卡）；聊天输入行用**更窄**的
    //   [_chatLockedOf]（撕卡仍可聊天，见 `_bodyOf` 与该方法注释）。
    //   ★ 不做全局 `IgnorePointer`：用户要求「只禁操作、不禁看」，
    //     且白名单项（「更多工具」等）必须保持可点 → 一律逐按钮叠加。
    final locked = _lockedOf(context, role);
    // ★ P10 第 5 期 A：KP 的 BGM 场景快捷入口。权限沿用既有口径
    //   `gate.can('scene.mode')`（POLICY = [kp]），不自造权限条件；
    //   这个按钮只打开本机弹层、不发 intent，所以**不挂** RoomKeys.action，
    //   T-30 表驱动探针不会把它误判成权威动作。
    //   5 个场景键收进弹层：工具栏空间紧，不把刚修好的自适应高度挤爆。
    final canQuickBgm = gate.can('scene.mode');
    return GpToolbar(
      // 契约（P16 P-3 / P17 P-3）：`GpToolbar({..., bool locked = false})`，
      // 组件内部对每个按钮叠加 `!locked`，白名单项除外。
      locked: locked,
      // ★ P17 P-4 重排：`mainActions` 是**扁平进主 Wrap** 的插槽（与两个缩放
      //   控件同一行）。为什么「更多工具 / 主组动作按钮」必须放这里而不是
      //   `extensions`：`extensions` 是嵌套 Wrap，而骰子条窄档宽
      //   `double.infinity`（`gp_dice_bar.dart` 的 narrow 分支）→ 嵌套 Wrap
      //   恒等于可用宽 → 它里面的按钮**永远不可能**和缩放按钮同处第 1 行，
      //   工具栏会多出一行。放进来后 412dp 档：80+80+90+90+3×4 = 352 ≤ 400
      //   ⇒ 第 1 行 4 个，整栏 4 行 = 4 / 3 / 3 / 3（用户截图要求的排布）。
      //   ★ 2.34.0：原「治疗」已按契约 I16 挪进 `GpDiceBar.tailGroup`，
      //     主组位置由 PV-1b 的「主动对抗」接替；本段骨架逐字不动。
      mainActions: <Widget>[
        if (!isKp && canOpenMisc)
          RoomTap(
            key: RoomGamePage.miscToolsKey,
            icon: Icons.more_horiz,
            label: '更多工具',
            hint: '规则参考 / 物品 / 缩放 / 观众名单 / 导出游戏历史',
            // ★ P17 P-3 **白名单项**：锁定态恒可点。（用户拍板 Q6：
            //   昏迷 / 疯狂时只放行「推进 1 轮」+「更多工具」+ 卡内申请治愈，
            //   而「申请治愈疯狂状态 / 申请治愈重伤」两个按钮就装在这个弹层里 ——
            //   所以这里**不叠** `!locked`，也不写 `enabled:`（默认恒可点）。
            //   本 key 不是 POLICY action，不受 T-30「enabled == gate.can」约束。）
            minSize: RoomBtnSize.toolbarWide,
            onTap: () => openMiscSheet(context),
          ),
        // ★ 2.34.0 / PV-2（契约 I16）：**「治疗」按钮已从 `mainActions`
        //   整块移除**，改由 W-B 在 `gp_dice_bar.dart` 的 `tailGroup`「战技」
        //   右侧加入（那里用 `ValueKey<String>('gpToolbar/treat')`，与这里
        //   保留的 [RoomGamePage.treatKey] 同值，Wave2 断言能命中）。
        //   ★ 必须如实记录：代码算术**不支持「工具栏少一行」**。条目 9→10
        //     后 per=3 档为 [3,3,2,2]（总 5 行，反而 +1）、per=4 档为
        //     [4,3,3]（持平）。本次**只挪按钮**：`_buildToolbar` 骨架、
        //     `gp_toolbar.dart` 的 Wrap 结构、`GpDiceBar` 的
        //     `width: double.infinity` 一律不动，不许包装成「已优化」。
        //   ★ 保留 `RoomGamePage.treatKey` 常量定义本身（不渲染），供 W-B /
        //     Wave2 引用；此处不再 import `sheet_treat.dart`，避免
        //     两个 `gpToolbar/treat` 并存把 `find.byKey` 变 `findsWidgets`。
        //
        // ★ 2.34.0 / PV-1b（契约 I5 / I11 / I12）：玩家主动对抗申请入口。
        //   占据原「治疗」的位置（主组「治疗」右侧 → 现为「更多工具」右侧），
        //   渲染条件 `if (!isKp)`、`enabled: !locked` 与「治疗」逐字同口径。
        //   只开本机申请弹层，载荷由 `sheet_opposed.dart` 按 I5 组装并经
        //   `RoomConfirm.kp` + pending + `RoomRequestWatcher` 走审批链路；
        //   **不挂** `RoomKeys.action('check.opposed')`（避免与 R1 门控、
        //   `gp_dice_bar.dart:432` 的既有按钮撞 key / 破 9 项契约）。
        if (!isKp)
          // ★ C7：`clampBtnText` = 零 RenderObject 的
          //   `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)`，
          //   只钳这一棵按钮子树的文字缩放，textScaler 1.3 / 1.5 / 2.0
          //   下不溢出；key 仍在内层 RoomTap 上，几何与既有按钮逐字一致。
          clampBtnText(
            RoomTap(
              key: RoomGamePage.playerOpposedKey,
              icon: Icons.compare_arrows,
              label: '主动对抗',
              hint: '向 KP 申请一次主动对抗检定（选技能与目标，技能值由角色卡读取）',
              // 与工具栏其它按钮对齐：锁定态（昏迷 / 疯狂 / 撕卡）禁用。
              enabled: !locked,
              minSize: RoomBtnSize.toolbarWide,
              onTap: () => showPlayerOpposedRequestSheet<void>(context),
            ),
          ),
        // ★ P12 PL-2（契约 I10 / R6）：San Check 必须紧接「主动对抗」
        //   右侧相邻，进 `mainActions` 扁平插槽 —— 不是 `extensions`、
        //   不是 `GpDiceBar` 第 10 项。玩家主组 4→5 会让
        //   `p10_t6_layout_test.dart` 几何断言真红，由 QA 按「更强或等价」
        //   改写；禁止为过测试而挪位。`showSanCheckSheet` 免审批
        //   （`RoomIntent.sanCheck` 不经 `RoomConfirm.kp` / pending）。
        //   保留 W-A 已做的 `_mapStage` 全屏接线 `fullscreenMode:false`，
        //   其余 7 路骨架逐字不动。
        if (!isKp)
          clampBtnText(
            RoomTap(
              key: RoomGamePage.sanCheckKey,
              icon: Icons.psychology,
              label: 'San Check',
              hint: '输入成功 / 失败扣值（如 2/1d6），免审批直接发起',
              enabled: !locked,
              minSize: RoomBtnSize.toolbarWide,
              onTap: () => showSanCheckSheet<void>(context),
            ),
          ),
        // ★ 2.36.0 / Q6：把原 `KpPanel` 弹层里的两个动作扁平进主 Wrap，
        //   落在 `RoomKeys.gpZoomReset` 右侧同一行（`...mainActions` 的语义
        //   就是「扁平进主组」；放 `extensions` 会被骰子条的
        //   `width: double.infinity` 挤到下一行）。
        //   · `enabled` **恰好**等于 `gate.can(op)`（T-30 契约），不叠 `!locked`；
        //   · 独立 ValueKey，绝不挂 `RoomKeys.action(...)` 锚点；
        //   · `clampBtnText` 只钳这一棵按钮子树的文字缩放（1.0/1.3/1.5/2.0）。
        if (isKp)
          clampBtnText(
            RoomTap(
              key: RoomGamePage.nextRoundKey,
              icon: Icons.skip_next,
              label: '下一回合',
              hint: '推进到下一回合',
              enabled: gate.can('round.next'),
              minSize: RoomBtnSize.toolbarWide,
              onTap: () => scope.controller.hostAction('round.next'),
            ),
          ),
        if (isKp)
          clampBtnText(
            RoomTap(
              key: RoomGamePage.combatReadyKey,
              icon: Icons.shield,
              label: '战斗准备',
              hint: '打开战斗准备面板',
              enabled: gate.can('combat.start'),
              minSize: RoomBtnSize.toolbarWide,
              onTap: () => openKpSheet(context, 'combat'),
            ),
          ),
        // ★ P23 R1（用户：「玩家视角（平板横屏布局）笔记和手绘板按钮放到玩家
        //   工具栏」）：玩家 dock 档在**主组末尾**追加「手绘板 → 笔记」。
        //
        // 为什么落在这里（改前它们在 `gpPlScene` 格顶部一条 28dp 行）：
        //   · 那条行把场景检定栏整格往下推，且和队友栏「展开」按钮抢同一角；
        //   · 用户明确要「放到玩家工具栏」，工具栏本来就是本机操作入口的归属地。
        //
        // 三条硬口径（改前逐字一致，别改）：
        //   · **不传 `enabled:`** —— 纯本机功能（本机绘制 / 本机笔记），
        //     与公开素材、与锁定态（昏迷 / 疯狂 / 撕卡）都无关，恒可点；
        //   · **不挂 `RoomKeys.action(...)`** —— 只开本机全屏路由、不发 intent，
        //     挂了会被 T-30 表驱动探针误判成权威动作；
        //   · 顺序 = **手绘板 → 笔记**。
        //   `minSize` 用 `RoomBtnSize.toolbarWide`（90×40）与主组其它按钮同档。
        //   折叠档不传 `dock`，故这里不渲染（折叠方块本来就各占一格，双入口无意义）。
        if (!isKp && dock)
          clampBtnText(
            RoomTap(
              key: RoomGamePage.plSketchKey,
              icon: Icons.gesture,
              label: '手绘板',
              hint: '全屏打开我的手绘板（本机绘制，与公开素材分开）',
              minSize: RoomBtnSize.toolbarWide,
              onTap: () => openRoomSlotFullscreen(
                context,
                title: '我的手绘板',
                body: (_) => const GpPlSketch(fill: true),
              ),
            ),
          ),
        if (!isKp && dock)
          clampBtnText(
            RoomTap(
              key: RoomGamePage.plNotesKey,
              icon: Icons.sticky_note_2_outlined,
              label: '笔记',
              hint: '全屏打开我的笔记（只存在本机）',
              minSize: RoomBtnSize.toolbarWide,
              onTap: () => openRoomSlotFullscreen(
                context,
                title: '我的笔记（本机）',
                body: (_) => const GpPlNotes(fill: true),
              ),
            ),
          ),
      ],
      extensions: <Widget>[
        // 骰子条整棵（D100 / 其他骰子 / 自定义 / 奖惩骰 / 暗骰 / 战技）
        // 都是「改变游戏状态」的操作 → 锁定态全禁，由组件内部叠加。
        // ★ 不能写 `const`（要传 locked）。
        GpDiceBar(locked: locked),
        if (isKp)
          RoomTap(
            key: RoomGamePage.kpPanelKey,
            icon: Icons.tune,
            label: 'KP',
            hint: '打开 KP 工具弹层',
            // ★ P16：扩展按钮与主组同档（90×40）。`KP` 内容仅 51，
            //   与 `更多工具`（86）同宽后才算「同一栏位一样大」。
            minSize: RoomBtnSize.toolbarWide,
            onTap: () => showKpPanel<void>(context, onOpen: openKpSheet),
          ),
        if (isKp && canQuickBgm)
          RoomTap(
            key: MusicSheetKeys.roomSceneQuick,
            icon: Icons.library_music_outlined,
            label: 'BGM 场景',
            hint: 'KP 场景快捷键：点一下先停旧曲再切到新场景 BGM（纯本机、不同步）',
            enabled: canQuickBgm,
            // ★ P16：全栏唯一的长按钮（内容 88.5）→ 按用户规则「让它特殊」。
            minSize: RoomBtnSize.diceLong,
            onTap: () => openMusicSceneQuickSheet(context),
          ),
        // ★ 2.34.0 / KP-7（契约 I10 / I12 / D2）：经 `extensions` 注入
        //   「递线索」按钮，与 [GpDiceBar] **平级**（不是骰子条第 10 项，
        //   9 项契约逐字保留）。跟同组的 KP / BGM 按钮一样按 `isKp` 门控，
        //   `scene.clue` 的 POLICY 本就是 `[kp]`，也避免玩家侧凭空多一个
        //   按钮改变工具栏行数 / 按钮数基线。
        //   ★ 只开本机弹层、不发 intent → 独立 [RoomGamePage.clueQuickKey]，
        //     **不挂** `RoomKeys.action(...)`，禁用
        //     `RoomKeys.action('scene.clue')`（T-30 探针防误判）。
        if (isKp)
          // ★ C7：同上，只钳这一棵按钮子树的文字缩放；key 在内层 RoomTap。
          clampBtnText(
            RoomTap(
              key: RoomGamePage.clueQuickKey,
              icon: Icons.mail_outline,
              label: '递线索',
              hint: '给指定玩家私下递一条线索',
              minSize: RoomBtnSize.toolbarWide,
              onTap: () => showClueSheet<void>(context),
            ),
          ),
        ...widget.toolbarExtensions,
      ],
    );
  }

  /// 点观众数 → 只读弹层（不改任何状态；观众列表按裁剪后的 state 取）。
  void _showSpectators(BuildContext context) {
    final scope = RoomScope.read(context);
    final state = scope.session.state;
    final rows = spectatorsOf(state);
    showRoomSheet<void>(
      context: context,
      title: '旁观者（${rows.length}）',
      body: (BuildContext _) {
        if (rows.isEmpty) return const Text('暂无旁观者');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final m in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    AvatarDot(name: '${m['nickname'] ?? m['seat'] ?? ''}'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${m['nickname'] ?? ''}'
                        '（${bodyViewOf(m)}）',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
