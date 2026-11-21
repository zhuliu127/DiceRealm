// ============================================================
// widgets/room_layout.dart — 布局骨架（P10 第 2 期 B）
//
// 这一段只做**摆位**，绝不重做任何块的内部 UI（用户原话：
// 「UI 现在版本就很好不用改，只改布局」）。所以本文件只出现三件事：
//
//   ① [RoomLayoutNode] / [roomDockPlanOf] —— 平板横屏的固定比例网格
//      **声明**（纯数据，零像素）。复刻老 APP 2.13.13 的两张红块图：
//      玩家「角色卡通高 / 素材图最大 / 场景·队友·手绘·笔记等在右窄列」，
//      KP「素材栏通高 / KP 工具竖条 / 素材图最大 / 右侧场景·战斗·玩家」。
//      ★ 列间距与行间距**取自同一个 gap**，所以「栏位没对齐」在结构上不可能
//      再发生（老 APP 的图是手摆的，格子本身不齐）。
//
//   ② [RoomSlotSquare] —— 折叠档里被收起的那一格：只有标题 + 一行摘要 +
//      （有新消息时）一个「新」角标；点一下 → 走 [openRoomSlotFullscreen]
//      全屏显示真块。**不裸 showDialog**（门禁第 11 条）。
//
//   ③ [RoomFlashBoard] —— 折叠档的闪烁判据源：聊天 / 公开记录 / 只给你看
//      三块**共用同一个判据类**（[FeedFlashTracker]），零 Timer、
//      零 AnimationController。折叠成方块时块体没建，闪烁判据只能上提到
//      页面级，否则「收起后新消息没有任何提示」。
//
// ★ 为什么判据要能在块外跑：`FeedFlashTracker` 的输入只有
//   「展示序末条的 seq / seat / 我的 seat」，三者都能从 state 纯派生
//   （`collectChats` / `collectFeeds` / `privRowsOf`），所以提到页面级
//   不会把判据拆成第二套口径。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_types.dart' show kHostSeat;
import '../room_feed_flash.dart' show FeedFlashTracker;
import '../room_keys.dart';
import '../room_theme.dart';
import '../sheets/room_sheet.dart' show showFullscreenReader;
import '../view/feed_view.dart' show collectChats, collectFeeds, privRowsOf;
import '../view/room_view.dart' show membersOf;
import '../view/scene_view.dart' show publicAssets;
import 'room_panel_kit.dart';

// ------------------------------------------------------------
// ① 固定网格声明（纯数据）
// ------------------------------------------------------------

/// 网格节点：叶子是「槽位 + flex 权重」，分叉是「行 / 列 + 子节点」。
///
/// 用声明式而不是直接写嵌套 Row/Column：布局是**可断言的**（测试能对角
/// 色取到「槽位落位表」并逐格比对），而渲染只有 [buildRoomLayout] 一处。
sealed class RoomLayoutNode {
  const RoomLayoutNode({required this.flex});

  /// 在父级里的伸缩权重（同一父级下才可比）。
  final int flex;
}

/// 叶子：一个槽位。
class RoomSlotNode extends RoomLayoutNode {
  const RoomSlotNode(this.slot, {required super.flex});

  final RoomSlot slot;
}

/// 分叉：一行或一列。
class RoomSplitNode extends RoomLayoutNode {
  const RoomSplitNode({
    required this.axis,
    required this.children,
    super.flex = 1,
  });

  /// `Axis.horizontal` = Row（宽度按 flex 分）；`Axis.vertical` = Column。
  final Axis axis;
  final List<RoomLayoutNode> children;
}

/// 分叉：两格**共 rect 叠放**（P11 KP-5 / 契约 I7）。
///
/// 与 [RoomSplitNode] 的差别只在渲染方式：[RoomSplitNode] 用 `Flex` 按 flex
/// 把父框切成互不重叠的几块；本节点用 `Stack` + `Positioned.fill`，让每个
/// 子节点都拿到**同一份**父框约束 —— 于是两格 Rect 逐边相等，一起拉长占满
/// 整个右列，底端仍与同排 `gpMap` 对齐（用户拍板 D5「空隙 = 右列内部」）。
///
/// ★ 子节点仍保留 `gpScene` / `gpPlayers` 的命名与 flex（56 / 44），只为让
///   [roomLayoutSlotsOf] 的 12 槽 DFS 顺序与 [roomLayoutFlexPathsOf] 的 flex
///   链落位表**逐字不变**；叠放渲染本身不消费子节点 flex，也不插入 `gap`
///   （叠放不是相邻格，插 gap 反而会破坏「逐边相等」）。
class RoomStackNode extends RoomLayoutNode {
  const RoomStackNode({
    required this.children,
    required super.flex,
  });

  final List<RoomLayoutNode> children;
}

/// 平板横屏的固定网格（用户给的两张红块图）。
///
/// 所有格子共用同一个 gap（渲染侧传入），于是**列与行天然对齐**。
/// [isKp] 为 true 取 KP 图，false（玩家 / 旁观）取玩家图。
///
/// ★ P10 第 6 期（布局专项，红块参考图 + KP 平板横屏实截图）：
///   旧值 `左17 | 上52[工具22 + 图40 + 右23(场景34/战斗36/玩家30)]
///   / 中26[聊天|记录] / 私密15 / 状态7` 有两个真机病：
///   · 上排里「工具窄栏 22 / 右侧列 23」在 1280dp 档只有 267 / 280dp，
///     分别低于 roomDockMinWidthOf 的 300 / 288 → `_slotView` 判定
///     tooNarrow，套横向 SingleChildScrollView + ClipRect，于是
///     「放（置单位）」只露一半、「成功(2)/失败(0)」被切。
///   · 私密栏独占一整行 15%（通宽大长条，内容却很少）→ 实截图里
///     「下方两大块空块」；顶栏占 3 行又进一步压缩上排。
///   新值把上排提到 60%、工具栏 30、右列 27、素材图 43（1280 档实测
///   工具 307.9 / 右列 277.2 / 素材图 441.4dp），配合把 `gpScene` 的
///   最小宽度从 288 收到 260，三个窄栏都不再触发 `_slotView` 的
///   tooNarrow 横向滚动 + ClipRect，于是「放」「成功(2)/失败(0)」
///   不再被裁掉一半；同时 441.4 > 277.2×1.5，老 APP「中间大块最大」
///   的几何口径仍成立。并把私密栏并进中排做成参考图的「底部三块：
///   聊天框 | 游戏公开信息记录 | 只给你看的信息」，状态条压到 6%。
///   槽位 DFS 顺序、数量、key 与 `RoomLayoutNode` 声明式树一律不变
///   （p10_t3 的落位表与 17/83/3 层 flex 链照旧成立）。
///
/// ★ P16 起 **KP 图**不再等同上面这段历史描述：待办状态条（gpStatus）与右列
///   战斗格（gpCombat）已按 KP-3 / KP-4② 移出，改动口径见 `isKp` 分支里的
///   逐条注释。
///
/// ★ P20（2.42.0）起 **玩家图**也改了右列与底部（需求 3②③④⑤），口径见
///   `isKp == false` 分支里的逐条注释。改的只有**节点声明**：
///   `RoomSlot` 枚举、`RoomKeys.plSlots`（13 项）、`keyOfSlot`、
///   `roomLayoutSlotsOf` / `roomLayoutFlexPathsOf` 的机制一律不动。
///   ★ 被删掉声明的四个槽位（`gpPlCombat` / `gpPlSketch` / `gpPlNotes` /
///     `gpStatus`）在**折叠档仍然各有一格**（折叠档走 `RoomKeys.plSlots`
///     + `roomExpandedSlots`，不读本函数），只有平板横屏的固定网格里不再出现。
RoomLayoutNode roomDockPlanOf({required bool isKp}) {
  if (isKp) {
    // KP：左侧竖条通高 → 右边上排「工具窄栏 + 中间大块 + 右上场景/玩家」，
    // 中排「聊天 | 记录 | 只给你看」三块。
    //
    // ★ P16 KP-3：**删掉最底那条「待办」状态条**（原 `gpStatus` flex 5）。
    //   为什么是删节点而不是渲染成 `SizedBox.shrink()`：`buildRoomLayout` 用
    //   `Expanded(flex: children[i].flex)` 分空间，flex 是**硬占**的 —— 子节点
    //   画成 0 尺寸只会在格内留一条空白带，那一截高度不会还回来。
    //   删节点 + 中排 41 → 46 之后：上排占比 44/(44+46) = 48.9%，与改前
    //   44/(44+41+5) = 44/90 = 48.9% **逐位相同** → 素材舞台几何零变化，
    //   空出来的正是原待办栏那一条，全部并入中排「聊天 / 记录 / 只给你看」。
    //   ★ `RoomSlot.gpStatus` 枚举、`RoomKeys.keyOfSlot`、槽位 DFS 机制一概不动；
    //     玩家图里的 `gpStatus flex: 7` 也原样保留（玩家档布局本批不许动）。
    //
    // ★ P16 KP-4②：**右列删掉 `gpCombat`（原 flex 32）** —— 战斗信息栏搬进
    //   素材舞台格（`gpMap`）。剩下两个按 38:30 等比放大到 100 →
    //   `gpScene` 56 / `gpPlayers` 44，右列不留空带；`gpKpTools` / `gpMap`
    //   的几何（24 / 50 / 26 与上排 44）完全不变。
    //   ★ P11 KP-5 续：这两个 56/44 现在只是 [RoomStackNode] 子节点的
    //     **落位表权重**（不再切分高度），实际渲染改为共 rect 叠放。
    return RoomSplitNode(
      axis: Axis.horizontal,
      children: <RoomLayoutNode>[
        const RoomSlotNode(RoomSlot.gpKpLeft, flex: 17),
        RoomSplitNode(
          axis: Axis.vertical,
          flex: 83,
          children: <RoomLayoutNode>[
            RoomSplitNode(
              axis: Axis.horizontal,
              flex: 44,
              children: <RoomLayoutNode>[
                const RoomSlotNode(RoomSlot.gpKpTools, flex: 24),
                const RoomSlotNode(RoomSlot.gpMap, flex: 50),
                // ★ P11 KP-5（契约 I7 / 用户拍板 D5）：右列「场景检定 /
                //   玩家信息」由 vertical 56/44 拆分改为**共 rect 叠放** ——
                //   两栏一起拉长占满整个右列，右列内部空隙自然消失、底端
                //   仍与 gpMap 对齐。原 56/44 的 flex 值保留，落位表 /
                //   DFS 顺序 / RoomSlot 命名逐字不变。
                RoomStackNode(
                  flex: 26,
                  children: <RoomLayoutNode>[
                    const RoomSlotNode(RoomSlot.gpScene, flex: 56),
                    const RoomSlotNode(RoomSlot.gpPlayers, flex: 44),
                  ],
                ),
              ],
            ),
            RoomSplitNode(
              axis: Axis.horizontal,
              flex: 46,
              children: <RoomLayoutNode>[
                const RoomSlotNode(RoomSlot.gpChat, flex: 1),
                const RoomSlotNode(RoomSlot.gpLog, flex: 1),
                const RoomSlotNode(RoomSlot.gpPriv, flex: 1),
              ],
            ),
          ],
        ),
      ],
    );
  }
  // 玩家：左列上「角色卡」下「只给你看」（上下分），右边上「素材图（最大）
  // + 右列叠放层（场景 / 队友）」，中「聊天 | 记录」。
  //
  // ★ 2.43.0 / P23 R2（用户原话：「只给你看栏移动到『我的角色卡』栏位下方的
  //   空隙中，为了能显示足够的信息，『我的角色卡』栏位可以拉短一些高度
  //   （可拖动栏位内部查看未显示的信息）；聊天栏、游戏记录栏都拉长高度，
  //   补满原来『只给你看』栏的空隙，高度一样、宽度一样」）：
  //   · **左列改成分栏**：`gpPlCharCard flex:55` / `gpPriv flex:45`。
  //     55/45 是角色卡与私密栏的**上下比例**（不是像素）。
  //   · 私密栏原来在右列占 `15/93`（≈16%），现在搬到左列吃 45% —— 它让出来
  //     的那段高度全给右列「聊天 | 记录」这一排（`26 + 15 = 41`）。
  //   · 角色卡变矮后**不需要新写滚动**：`room_game_page.dart#_slotView` 对
  //     非紧约束白名单槽位（`gpPlCharCard` / `gpPriv` 都不在名单里）一律套
  //     竖向 `SingleChildScrollView`，「可拖动栏位内部查看未显示的信息」
  //     因此天然成立。★ 反向红线：不许把这两格加进那个白名单。
  //   · 私密栏与角色卡**同宽**（都吃左列的 20%），所以
  //     `roomDockMinWidthOf(gpPriv)` 必须从 240 收到 230（= 角色卡的下限），
  //     否则 1024×768 dock 档私密栏判 tooNarrow → 格内横向滚动。
  //
  // ★ P20 需求 3⑤（用户：「场景那格太矮，拉长」）：右列由
  //   `vertical 22/20/20/20/18` 五格拆分改成 [RoomStackNode] 两层叠放 ——
  //   `gpPlScene` flex 100 吃满整列（拉长），`gpPlMates` flex 1 叠在上面。
  //   复用 KP-5（P11）同一套渲染路径（`Stack(fit: expand)` +
  //   `Positioned.fill`），不另写第二套叠放实现。
  //   收起队友后 `gpPlMates` 只返回 `Align + 28dp` 标题行（`hitTestSelf`
  //   为 false），指针穿透到下层场景检定栏。
  //
  // ★ P20 需求 3②③：右列删掉三个叶子 —— `gpPlCombat`（战斗信息栏搬进
  //   `gpPlMap` 格，同 KP-4② 的做法）、`gpPlSketch` / `gpPlNotes`（改为
  //   **玩家工具栏**里的两个全屏按钮，见 `room_game_page.dart` 的
  //   `_buildToolbar(dock: ...)`；P23 R1 起由场景格顶行搬进工具栏）。
  //   删节点而不是渲染成 0 尺寸：`Expanded(flex:)` 是
  //   **硬占**的，画成 0 尺寸只会留一条空白带。
  //
  // ★ P20 需求 3④（与 D6 一致）：删掉玩家 dock 的 `gpStatus` 叶子。
  //   与 P16 KP-3 删 KP 侧 `gpStatus` 同一口径 —— **只删声明节点**，
  //   `RoomSlot` 枚举 / `plSlots` / 折叠档与大厅里的状态条一概保留。
  //   删后右列两段的 flex 52 / 41（合计 93，其中 41 = 原 26 + 私密栏让出的
  //   15）由 `Expanded` 按比例重新分配 → 上排 ≈55.9% / 中排 ≈44.1%。
  //   左侧同理是 55 / 45 两段（合计 100）。
  return RoomSplitNode(
    axis: Axis.horizontal,
    children: <RoomLayoutNode>[
      // ★ P23 R2：左列 = 角色卡（上）+ 私密栏（下）。改前 `gpPlCharCard` 是
      //   通高叶子、私密栏挂在右列第 3 段；现在两者上下分，右列整列让位给
      //   「上排（素材图 + 场景/队友叠放）+ 聊天/记录排」。
      RoomSplitNode(
        axis: Axis.vertical,
        flex: 20,
        children: <RoomLayoutNode>[
          // ★ P23 R2：角色卡 55%（改前 100% 通高）。变矮后靠 `_slotView` 的
          //   竖向滚动兜底查看未显示内容 —— 该槽位**不在**紧约束白名单里，
          //   这一条是刻意的，不许把它加进去。
          const RoomSlotNode(RoomSlot.gpPlCharCard, flex: 55),
          // ★ P23 R2：私密栏 45%（改前在右列占 15/93 ≈16%）。
          const RoomSlotNode(RoomSlot.gpPriv, flex: 45),
        ],
      ),
      RoomSplitNode(
        axis: Axis.vertical,
        flex: 80,
        children: <RoomLayoutNode>[
          RoomSplitNode(
            axis: Axis.horizontal,
            flex: 52,
            children: <RoomLayoutNode>[
              const RoomSlotNode(RoomSlot.gpPlMap, flex: 55),
              // ★ P20 需求 3⑤：右列 = 场景（底层，吃满整列）+ 队友（上层叠放）。
              //   两层共用同一份父框（`Stack + Positioned.fill`），所以队友
              //   收起后场景检定栏的底端 = 整列底端，用户说的「太矮」解决。
              RoomStackNode(
                flex: 30,
                children: <RoomLayoutNode>[
                  const RoomSlotNode(RoomSlot.gpPlScene, flex: 100),
                  const RoomSlotNode(RoomSlot.gpPlMates, flex: 1),
                ],
              ),
            ],
          ),
          RoomSplitNode(
            axis: Axis.horizontal,
            // ★ P23 R2：26 + 15 = 41。私密栏让出来的高度**全部**给这一排，
            //   所以聊天栏与记录栏同时变高（两格 flex 相等 ⇒ 高度/宽度都一样，
            //   用户要的「高度一样、宽度一样」由这个 `flex: 1 / flex: 1`
            //   加同一个父框保证）。
            flex: 41,
            children: <RoomLayoutNode>[
              const RoomSlotNode(RoomSlot.gpPlChat, flex: 1),
              const RoomSlotNode(RoomSlot.gpPlLog, flex: 1),
            ],
          ),
        ],
      ),
    ],
  );
}

/// 网格里的槽位落位表（深度优先，行优先）。测试据此逐格断言，不必量像素。
List<RoomSlot> roomLayoutSlotsOf(RoomLayoutNode node) {
  switch (node) {
    case RoomSlotNode(:final RoomSlot slot):
      return <RoomSlot>[slot];
    case RoomSplitNode(:final List<RoomLayoutNode> children):
      return <RoomSlot>[
        for (final child in children) ...roomLayoutSlotsOf(child),
      ];
    // ★ KP-5：叠放层仍按 children 顺序做 DFS，12 槽落位表逐字不变。
    case RoomStackNode(:final List<RoomLayoutNode> children):
      return <RoomSlot>[
        for (final child in children) ...roomLayoutSlotsOf(child),
      ];
  }
}

/// 网格里每个槽位的 flex 链（从根到叶，`[15, 85, 52, 13]` 这类）。
///
/// 只服务诊断与测试：能证明「左窄栏与右侧内容区在根上按 15:85 分」。
Map<RoomSlot, List<int>> roomLayoutFlexPathsOf(RoomLayoutNode node) {
  final out = <RoomSlot, List<int>>{};

  // 根节点的 flex 恒为 1（没有父级可依），不进路径 —— 否则每条链前面都多一个 1。
  void walk(RoomLayoutNode n, List<int> path, {bool isRoot = false}) {
    final next = isRoot ? path : <int>[...path, n.flex];
    switch (n) {
      case RoomSlotNode(:final RoomSlot slot):
        out[slot] = next;
      case RoomSplitNode(:final List<RoomLayoutNode> children):
        for (final child in children) {
          walk(child, next);
        }
      // ★ KP-5：叠放层的 flex（26）已进 next，子节点 56/44 继续追加，
      //   gpScene / gpPlayers 的 flex 链与改前逐字相同。
      case RoomStackNode(:final List<RoomLayoutNode> children):
        for (final child in children) {
          walk(child, next);
        }
    }
  }

  walk(node, const <int>[], isRoot: true);
  return out;
}

/// 固定网格里每格的**最小可用宽度**。
///
/// 为什么需要它：这些块是为了「横向铺满的 Wrap」写的，部分内部固定行
/// （例如 KP 工具窄栏的五色板行、场景检定的等级按钮行）窄于这个宽度就会
/// `RenderFlex overflow`。本文件不改块内 UI（用户明确要求），所以窄格改成
/// **格内可横向滚动**（给出下限宽度后再滚），而不是让内容溢出到隔壁格。
double roomDockMinWidthOf(RoomSlot slot) {
  switch (slot) {
    // ★ P10 第 6 期：KP 上排把工具窄栏 / 右列配比调到 30 / 27 后，
    //   1280dp 档实测工具 307.9、右列 277.2。旧下限 300 / 288 / 240
    //   里，场景检定那格 277.2 < 288 会判 tooNarrow → 横向
    //   SingleChildScrollView + ClipRect，右侧「成功(2)/失败(0)」
    //   正好被裁掉一半（用户真机截图）。把三个 KP 窄栏的下限收到
    //   实测格宽以下，内容直接按真实宽度用 Wrap 换行铺开，不再裁切。
    //   ★ P10 第 6 期原先把这段写成「只动 KP 三格，玩家侧保持原值」。
    //     P20 需求 3⑤ 改了玩家右列的配比（`RoomStackNode` 叠放），
    //     所以 `gpPlScene` 必须跟着收到 260，理由与 `gpScene` 完全一样，
    //     见下方 `case RoomSlot.gpPlScene` 的注释。
    case RoomSlot.gpKpTools:
      // ★ P10 第 7 期：工具窄栏收窄到 24%（1280dp 实测 246dp），素材列表已
      //   全部收进左窄栏，这格只剩候选单位 + 工具 + 颜色 + 上传，240 够用。
      return 240;
    case RoomSlot.gpKpLeft:
      // ★ 左窄栏保持 17%（1280dp 实测 213dp），素材行改成「名字 + 按钮 Wrap」
      //   两行后不再需要 230；下限收到 200，避免 tooNarrow 横向滚动裁切。
      return 200;
    case RoomSlot.gpPlCharCard:
      return 230;
    case RoomSlot.gpScene:
      return 260;
    case RoomSlot.gpPlScene:
      // ★ P20 需求 3⑤：288 → 260，与 KP 的 `gpScene` 同值。
      //   1024×768 档实测右列 ≈279.5dp < 288 会判 tooNarrow → `_slotView` 套
      //   横向 `SingleChildScrollView` + `ClipRect`，场景检定栏右侧被裁掉一截。
      //   P10 第 6 期给 KP `gpScene` 修过一模一样的病（288 → 260，见上方注释），
      //   玩家侧这次因为 `gpPlScene` 从「右列 22% 小格」变成「吃满整列」，
      //   宽档位与 `gpScene` 完全同源，故取同一个下限。
      return 260;
    case RoomSlot.gpCombat:
    case RoomSlot.gpPlayers:
      return 220;
    case RoomSlot.gpPriv:
      // ★ 2.43.0 / P23 R2：240 → 230，与**同列**的 `gpPlCharCard` 取下限 230
      //   完全同值。理由：私密栏从「右列第 3 段（占右列整宽 80%）」搬到
      //   「左列下半（与角色卡同宽，20%）」，1024×768 dock 档左列实测
      //   ≈(1024-2×gap)×0.2 ≈ 199.6dp，比原来的整右列窄得多。若仍按下限 240
      //   判定，这一格会 `tooNarrow` → `_slotView` 套横向 `SingleChildScrollView`
      //   + `ClipRect`，私密栏内容被裁掉一截并多出格内横向滚动条。
      //   取 230 与角色卡一致：两格同宽，同一档位下要么都够、要么都不够，
      //   不会出现「左列上半不滚、下半横滚」的错位观感。
      return 230;
    case RoomSlot.gpPlCombat:
    case RoomSlot.gpPlMates:
    case RoomSlot.gpPlSketch:
    case RoomSlot.gpPlNotes:
      return 240;
    case RoomSlot.gpChat:
    case RoomSlot.gpLog:
    case RoomSlot.gpPlChat:
    case RoomSlot.gpPlLog:
    case RoomSlot.gpMap:
    case RoomSlot.gpPlMap:
    case RoomSlot.gpStatus:
    case RoomSlot.gpTopbar:
    case RoomSlot.gpToolbar:
    case RoomSlot.gpCombatStrip:
      return 120;
  }
}

/// 按声明渲染：所有间距都用同一个 [gap]，所以列/行交叉处必然对齐。
Widget buildRoomLayout({
  required RoomLayoutNode node,
  required double gap,
  required Widget Function(RoomSlot slot) cellOf,
}) {
  switch (node) {
    case RoomSlotNode(:final RoomSlot slot):
      return cellOf(slot);
    case RoomSplitNode(:final Axis axis, :final List<RoomLayoutNode> children):
      final widgets = <Widget>[];
      for (var i = 0; i < children.length; i++) {
        if (i > 0) {
          widgets.add(
            axis == Axis.horizontal
                ? SizedBox(width: gap)
                : SizedBox(height: gap),
          );
        }
        widgets.add(
          Expanded(
            flex: children[i].flex,
            child: buildRoomLayout(
              node: children[i],
              gap: gap,
              cellOf: cellOf,
            ),
          ),
        );
      }
      // ★ stretch：`Expanded` 只把**主轴**变成紧约束，交叉轴默认仍是松的。
      //   固定网格要求每格**填满**分配到的框（否则块会缩成自身高度并在格内
      //   垂直居中，行列就又不齐了）。所以这里必须显式 stretch。
      return Flex(
        direction: axis,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      );
    // ★ P11 KP-5：共 rect 叠放层。Positioned.fill 让每个子节点都拿到与
    //   Stack 完全相同的紧约束 → 两格 Rect 逐边相等、一起占满整个右列；
    //   不插入 gap（叠放不是相邻格）。Stack 自身由父级 Expanded(flex:26)
    //   撑满，故叠放层 bottom 恒等于同排 gpMap 的 bottom。
    case RoomStackNode(:final List<RoomLayoutNode> children):
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (final child in children)
            Positioned.fill(
              child: buildRoomLayout(
                node: child,
                gap: gap,
                cellOf: cellOf,
              ),
            ),
        ],
      );
  }
}

// ------------------------------------------------------------
// ② 折叠档：方块
// ------------------------------------------------------------

/// 折叠方块的边长（「方块」= 正方形，平铺在剩余空位）。
const double kRoomSquareSide = 104;

/// 被收起的一格：标题 + 一行摘要（+ 有新消息时的「新」角标）。
///
/// 点整块 → [openRoomSlotFullscreen] 全屏显示真块（用户口述的「点击后才
/// 弹窗展开并全屏显示」）；若这一格**本该展开**（只是被用户收起），
/// 右上角另给一个 `unfold` 抓手把它放回展开区（用户口述的「也可收起」）。
class RoomSlotSquare extends StatelessWidget {
  const RoomSlotSquare({
    super.key,
    required this.slot,
    required this.title,
    this.summary = '',
    this.flashing = false,
    this.onOpen,
    this.foldKey,
    this.onUnfold,
  });

  final RoomSlot slot;
  final String title;
  final String summary;

  /// 有新消息（只对聊天 / 公开记录 / 只给你看三格有意义）。
  final bool flashing;

  final VoidCallback? onOpen;

  /// 「放回展开区」抓手的 key（`roomFoldKey(slot)`，测试据此找得到）。
  final Key? foldKey;
  final VoidCallback? onUnfold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: kRoomSquareSide,
      height: kRoomSquareSide,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RoomTheme.panelRadius),
        ),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (flashing)
              Positioned(
                left: 6,
                bottom: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    child: Text(
                      '新',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            if (onUnfold != null)
              Positioned(
                right: 0,
                top: 0,
                child: RoomTap(
                  key: foldKey,
                  icon: Icons.unfold_more,
                  hint: '展开到面板',
                  minSize: const Size(30, 26),
                  onTap: onUnfold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 打开某一格的全屏视图（折叠档的「点开」、以及需要看全文的场景共用）。
///
/// ★ 走 [showFullscreenReader]（真实路由 + 自带关闭按钮），
///   **不裸 showDialog**、也不自己造第二个弹层壳。
Future<void> openRoomSlotFullscreen(
  BuildContext context, {
  required String title,
  required WidgetBuilder body,
}) async {
  await showFullscreenReader<void>(
    context: context,
    title: title,
    child: Builder(builder: body),
  );
}

// ------------------------------------------------------------
// ③ 折叠档的闪烁判据源（三栏同源）
// ------------------------------------------------------------

/// 单栏判据：一个 [FeedFlashTracker] + 上次判过的末条 seq + 当前角标。
class _PaneFlash {
  final FeedFlashTracker tracker = FeedFlashTracker();
  int checkedSeq = -1;
  bool flash = false;

  /// 与 `GpFeeds._deriveFlash` 同口径：只把「末条 seq / 末条 seat / 我的 seat」
  /// 交给 tracker，自己不做第二条判据。
  bool judge({
    required int lastSeq,
    required String lastSeat,
    required String mySeat,
  }) {
    if (lastSeq == checkedSeq) return flash;
    checkedSeq = lastSeq;
    flash = tracker.check(
          lastSeq: lastSeq,
          lastSeat: lastSeat,
          mySeat: mySeat,
        ) ==
        true;
    return flash;
  }

  void reset() {
    tracker.reset();
    checkedSeq = -1;
    flash = false;
  }
}

/// 折叠档的闪烁板：聊天 / 公开记录 / 只给你看三栏，判据类同源。
///
/// ★ 只在需要时（折叠档）刷新；展开档由块内自己的 tracker 负责，
///   两边用的是同一个判据类、同一套输入，不会出现「同一个新消息一处闪一处不闪」。
/// ★ 无 Timer、无 AnimationController：角标是纯派生状态。
class RoomFlashBoard {
  final _PaneFlash _chat = _PaneFlash();
  final _PaneFlash _record = _PaneFlash();
  final _PaneFlash _priv = _PaneFlash();

  Object? _boundSession;
  int _boundEpoch = -1;

  /// 换房间 / 连接层完成一次全量补拉 → 重置三栏基线（这批不是新消息）。
  void bindSession({required Object? sessionKey, required int epoch}) {
    if (identical(sessionKey, _boundSession) && epoch == _boundEpoch) return;
    _boundSession = sessionKey;
    _boundEpoch = epoch;
    _chat.reset();
    _record.reset();
    _priv.reset();
  }

  /// 刷新三栏角标；返回「槽位 → 是否闪」。
  ///
  /// 只认 KP / 玩家两套槽位里的三个信息流；其余槽位恒 false。
  Map<RoomSlot, bool> refresh({
    required Map<String, Object?> state,
    required String mySeat,
    required bool isKp,
    int chatCap = RoomTheme.chatCap,
    int feedCap = RoomTheme.feedCap,
  }) {
    final chats = collectChats(state, limit: chatCap);
    final feeds = collectFeeds(state, limit: feedCap);
    final privs = privRowsOf(state, mySeat);

    final chatFlash = _chat.judge(
      lastSeq: chats.isEmpty ? 0 : chats.last.seq,
      lastSeat: chats.isEmpty ? '' : chats.last.seat,
      mySeat: mySeat,
    );
    final recordFlash = _record.judge(
      lastSeq: feeds.isEmpty ? 0 : feeds.last.seq,
      lastSeat: feeds.isEmpty ? '' : feeds.last.seat,
      mySeat: mySeat,
    );
    // 私密信息是**权威端（KP）**发下来的，末条的归属恒为 KP 座位。
    final privFlash = _priv.judge(
      lastSeq: privs.isEmpty ? 0 : _seqOf(privs.last),
      lastSeat: privs.isEmpty ? '' : kHostSeat,
      mySeat: mySeat,
    );

    return <RoomSlot, bool>{
      (isKp ? RoomSlot.gpChat : RoomSlot.gpPlChat): chatFlash,
      (isKp ? RoomSlot.gpLog : RoomSlot.gpPlLog): recordFlash,
      RoomSlot.gpPriv: privFlash,
    };
  }

  /// 点开某一格 → 视为已读，角标立刻消失（纯状态标记，无动画）。
  void dismiss(RoomSlot slot) {
    final cell = switch (slot) {
      RoomSlot.gpChat || RoomSlot.gpPlChat => _chat,
      RoomSlot.gpLog || RoomSlot.gpPlLog => _record,
      RoomSlot.gpPriv => _priv,
      _ => null,
    };
    cell?.flash = false;
  }

  static int _seqOf(Map<String, Object?> row) {
    final v = row['seq'];
    return v is num ? v.toInt() : 0;
  }
}

// ------------------------------------------------------------
// 折叠方块的摘要文案（一行，标题下方的「简要信息」）
// ------------------------------------------------------------

/// 方块摘要：`聊天 · 12 条` / `公开记录 · 8 条` / `只给你看 · 3 条`……
///
/// 口径全部来自 view 层纯函数（不解析载荷、不显示秘密字段），
/// 拿不到计数时退化成一句静态说明，绝不显示空串方块。
String roomSlotSummary(
  RoomSlot slot,
  Map<String, Object?> state, {
  String seat = '',
}) {
  switch (slot) {
    case RoomSlot.gpChat:
    case RoomSlot.gpPlChat:
      return '聊天 · ${collectChats(state, limit: RoomTheme.chatCap).length} 条';
    case RoomSlot.gpLog:
    case RoomSlot.gpPlLog:
      return '公开记录 · ${collectFeeds(state, limit: RoomTheme.feedCap).length} 条';
    case RoomSlot.gpPriv:
      return '只给你看 · ${privRowsOf(state, seat).length} 条';
    case RoomSlot.gpCombat:
    case RoomSlot.gpPlCombat:
      return '战斗轮次与列表';
    case RoomSlot.gpPlayers:
    case RoomSlot.gpPlMates:
      return '成员 · ${membersOf(state).length} 人';
    case RoomSlot.gpPlSketch:
      return '手绘与标记';
    case RoomSlot.gpPlNotes:
      return '本机笔记';
    case RoomSlot.gpMap:
    case RoomSlot.gpPlMap:
      return '公开素材 · ${publicAssets(state).length} 个';
    case RoomSlot.gpKpLeft:
      return '怪物 / NPC 素材';
    case RoomSlot.gpKpTools:
      return '画笔与放置工具';
    case RoomSlot.gpScene:
    case RoomSlot.gpPlScene:
      return '场景检定';
    case RoomSlot.gpPlCharCard:
      return '我的角色';
    case RoomSlot.gpStatus:
      return '连接与回合状态';
    case RoomSlot.gpTopbar:
      return '房间信息';
    case RoomSlot.gpToolbar:
      return '底部工具条';
    case RoomSlot.gpCombatStrip:
      return '战斗速览';
  }
}
