// ============================================================
// widgets/gp_toolbar.dart — 块 11 / 12（两侧共用）工具栏壳（设计 §2.5 / T02-S2.4）
//
// 只做三件事：**缩放控件** + **快捷动作行** + **扩展插槽**。
//
// ★ 为什么工具栏不在缩放容器里（结构约束，不靠样式）：
//   旧版 `transform:scale()` 会生成 containing block，导致底部工具条跟着缩放/
//   定位失效，才把它挪到缩放容器之外（room-ui.js:2683-2686）。P5 保留这个
//   **可见结果**：`room_game_page.dart` 里 `Transform.scale` 只包内容区，
//   本组件是它的**兄弟节点**。测试用「反查祖先里没有 Transform」钉死这一点。
//
// ★ 跨任务编译边界（T02 不 import 任何 T03/T04/T05 文件）：
//   骰子条（T03 的 GpDiceBar）、KP 工具扩展（T04）、手绘板入口（T05）一律经
//   [extensions] 插槽注入。T02 当时只传占位块，T03–T05 已全部换成真块。
//
// ★ T-30 契约：凡挂了 `RoomKeys.action(op)` 的按钮，`enabled` 必须**恰好**
//   等于 `gate.can(op)`（= POLICY 判定），不许叠加业务前置条件 ——
//   否则表驱动探针会把「可点性」判成漂移。业务前置条件请写进 `hint`。
//   ★ P17 修订（唯一例外，施工单 §2-P-3）：昏迷/疯狂「锁定态」是**跨按钮的
//     统一闸门**（权威端 `room_model_host_intent.dart#_passSelf` 已在拦），
//     所以 `enabled` 允许且必须叠加 `!locked`；探针口径同步改为
//     `gate.can(op) && !locked`（波4 统一改）。本文件当前**没有** `act/`
//     按钮（见下方 P17 说明），故这条修订落在 `gp_dice_bar.dart`。
//
// ★ P10 第 6 期（布局专项，用户原话「下方玩家工具栏按钮也很乱，你重新
//   排布一下」）：手机竖屏 412dp 下主按钮行 + 骰子条 + 尾随扩展割裂成
//   4~5 行。本批只收紧「外壳」的间距与内边距，把两处 Wrap 的 spacing 从
//   6 收到 4、外层左右留白从 8 收到 6，让扩展组与主按钮组贴得更紧；
//   骰子条内部的按钮重排在 gp_dice_bar.dart 里做。
//   ★ 不改任何按钮的 minSize —— RoomButtonSkin 的 48×48 热区与
//     foregroundDecoration 描边不占尺寸口径（P12）一字不动。
//
// ★ P17 P-4（用户原话「下一轮」是灰色不可点、没有用的按钮）：
//   · **删掉** 主组里的「下一轮」（`act/round.next`）与「转战斗/转探索」
//     （`act/scene.mode`）两个 `RoomTapTile`。
//     理由（施工单 §6-Q6 拍板）：玩家工具栏这个「下一轮」不是玩家侧那个
//     「推进 1 轮」（`madness.advance`，在角色卡上），它恒灰、无用途；KP 的
//     回合推进在战斗信息栏的 `combat.next`，不靠这里。三视角一起去掉。
//     `RoomKeys.action('round.next')` / `RoomKeys.action('scene.mode')` 这两个
//     **key 构造器**属 `room_keys.dart`（含 POLICY oracle 契约），保留不动，
//     只是本文件**不再有 UI 使用点**（P17 起）。
//   · 删后主组只剩「缩放百分比 + 重置缩放」两个 —— 二者都是**纯视图操作**，
//     属施工单 §2-P-3 锁定态白名单第 4 条，所以 `locked` 在本文件**不叠加**
//     到它们身上（见 [GpToolbar.locked] 的说明）。
// ============================================================

import 'package:flutter/material.dart';

import '../room_scope.dart';
import '../room_ui_local.dart';
import '../room_keys.dart';
import '../../art.dart';
import '../../../theme.dart' show Palette;
import 'room_button_size.dart'
    show RoomBtnSize, RoomTapTile, clampBtnText;
import 'room_panel_kit.dart' show RoomTap;

/// 工具栏内部的稳定 key（容器 key 由页面挂在槽位上，见 RoomKeys）。
class GpToolbarKeys {
  const GpToolbarKeys._();

  static const Key zoomPercent = ValueKey<String>('gpToolbar/zoomPercent');
  static const Key quickRow = ValueKey<String>('gpToolbar/quickRow');
  static const Key extensions = ValueKey<String>('gpToolbar/extensions');
}

/// 块 11：底部工具条（缩放 + 快捷动作 + 扩展插槽）。
class GpToolbar extends StatelessWidget {
  const GpToolbar({
    super.key,
    this.extensions = const <Widget>[],
    this.mainActions = const <Widget>[],
    this.locked = false,
  });

  /// 扩展插槽：骰子条 / KP 工具扩展 / 手绘板入口……由 T03–T05 注入。
  final List<Widget> extensions;

  /// P17 P-4：**主组**动作（与两个缩放控件同处第 1 行、同一个 `Wrap`）。
  ///
  /// ★ 为什么需要这个插槽（纯布局事实，不是新功能）：[extensions] 是**嵌套**
  ///   `Wrap`，而骰子条在窄档是 `width: double.infinity`（`gp_dice_bar.dart`
  ///   的 `narrow` 分支）⇒ 嵌套 Wrap 的宽度恒等于可用宽，`Wrap` 会把它当成
  ///   一个整体换行 ⇒ `extensions` 里的按钮**永远不可能**和缩放按钮排在同一行。
  ///   把「更多工具 / 治疗」放在 [mainActions]（扁平进主 Wrap）后，手机竖屏
  ///   `80 + 80 + 90 + 90 + 3×4 = 352 ≤ 400` ⇒ 第 1 行恰好 4 个，
  ///   整个工具栏就是目标 **4 行 = 4 / 3 / 3 / 3**。
  /// ★ 注入方：`room_game_page.dart#_buildToolbar`（W2-A 的文件集）。
  ///   不传时行为与旧版完全一致（默认空列表）。
  final List<Widget> mainActions;

  /// P17 P-3：本人处于昏迷 / 疯狂 / 濒死 / 死亡等**锁定态**。
  ///
  /// ★ 契约（施工单 §2-P-3 逐字）：由 `room_game_page.dart#_buildToolbar`
  ///   计算后传入；组件内部对**黑名单**按钮的 `enabled` 叠加 `!locked`。
  /// ★ 本组件当前**没有黑名单按钮**：P-4 删掉「下一轮 / 转战斗」后，主组只剩
  ///   缩放百分比与重置缩放，二者属锁定态白名单第 4 条「纯视图操作」（缩放、
  ///   全屏、折叠展开、列表滚动）→ **故意不叠 `!locked`**。
  ///   真正需要锁的动作按钮由注入方给：`更多工具`（白名单，恒可点）与
  ///   `治疗`（黑名单，`enabled` 由注入方叠 `!locked`）→ 见 [mainActions]；
  ///   骰子条见 `GpDiceBar.locked`。
  /// ★ 参数必须存在：跨组编译契约（`room_game_page.dart` 会传 `locked:`），
  ///   缺了就是编译断裂。
  final bool locked;

  /// ★ P10 第 2 期 B（用户口述「工具栏可以增加高度，让按钮显示全，不用拖动
  ///   找没显示到的按钮」）：
  ///   · 原来固定 56 高 + 内部**横向滚动**，手机上要横着拖才能看到后半截按钮；
  ///   · 现在改成 `Wrap` 多行 + **由内容决定高度**（不再写死高度、不再滚动）。
  ///
  /// 为什么不按宽度查表：实测「需要几行」随宽度**非单调**（360 要 278dp、
  /// 480 要 234dp、700 只要 148dp、780 又要 190dp —— 换行组合不同），任何
  /// 固定表都会在某档把按钮挤出可视区。所以工具栏高度交给布局自身：
  /// 页面把它放在 `Column` 的最后一格（通栏、贴底、不覆盖内容），
  /// 内容区自然拿到「剩下的高度」，既不用避让常量，也不可能被盖住。
  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    // ★ 必须自己订阅本地态：RoomScope 只订阅会话（InheritedNotifier），
    //   工具栏在缩放容器之外、也不在页面的内容区 ListenableBuilder 里，
    //   不单独订阅就会「点缩放按钮后百分比数字不刷新」。
    return ListenableBuilder(
      listenable: scope.local,
      builder: (BuildContext _, Widget? _) => _bar(context, scope),
    );
  }

  /// 工具条本体（订阅之后才构建，保证读到的 zoom / 模式都是最新的）。
  Widget _bar(BuildContext context, RoomScope scope) {
    final local = scope.local;
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 3,
      // 工具栏底纹（E16）：纯背景，不动按钮结构与任何 Key
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(Art.toolbar),
            fit: BoxFit.cover,
            opacity: Palette.isDark ? 0.32 : 0.16,
          ),
        ),
        // ★ 没有固定高度：高度由内容撑开，按钮全部直接铺出来（无横向滚动）。
        //   竖向滚动只是**极端兜底**：极矮屏（如 320dp 高的手机横屏）上页面
        //   会给工具栏一个高度上限，此时才需要滚 —— 正常档位（≥360dp 高）
        //   内容全部可见，滚动条不出现、也滚不动。
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Wrap(
              key: GpToolbarKeys.quickRow,
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                // ---- 缩放（60 / 70 / 80 / 90 / 100 循环，只缩小不放大） ----
                // ★ P16：主组按钮统一 80×40（`RoomBtnSize.toolbarTile`）。
                //   定宽走 `RoomTapTile`（`SizedBox` 紧约束）而不是只改 minSize：
                //   `RoomTap` 的宽 = max(内容宽, minWidth)，删掉的两个动作按钮
                //   内容就有 73.75，光给 minSize 挡不住文案撑开。高度 48→40
                //   让工具栏变矮（「工具栏最大高度占比」的方向同向收紧，三条
                //   高度用例只会更宽松）。
                // ★ P17 起主组只剩 **2 个**（缩放在前、重置在后）：删掉两个动作
                //   按钮后本组宽度从 4×80 掉到 2×80，竖屏第 1 行因此空出约
                //   168dp —— 正好由 `extensions` 里的「更多工具 / 治疗」补满
                //   （两者各 90×40，注入口在 `room_game_page.dart#_buildToolbar`，
                //   不属本文件）。目标行数：手机竖屏 **4 行 = 4 / 3 / 3 / 3**。
                //
                // ★ 唯一例外：`100%` 是缩小组**内容最长**的那一个 —— 实测内容宽
                //   **87 > 80**，所以它不能套 `RoomTapTile`（`SizedBox(80)` 紧约束
                //   会让内部 `Row` 溢出 7dp）。按用户原话「有一个比其他的按钮都
                //   长的，那就让这一个特殊一点」：缩放按钮只给 `minSize`，宽度由
                //   内容决定（真机 Roboto 下 `100%` 内容 ≈60 ⇒ 实际就是 80×40，
                //   与重置按钮逐像素同宽）。
                //   ★ 大字体：不定宽也会被字宽撑大、把主组挤出两行，所以要包
                //   `clampBtnText`（与 `RoomTapTile` 同一口径，按钮文字不缩放）。
                clampBtnText(
                  RoomTap(
                    key: GpToolbarKeys.zoomPercent,
                    icon: Icons.zoom_out_map,
                    label: '${(local.zoom * 100).round()}%',
                    hint: '点按切换缩放档位（60%–100%）',
                    minSize: RoomBtnSize.toolbarTile,
                    onTap: () => local.setZoom(_nextZoom(local.zoom) / 100),
                  ),
                ),
                RoomTapTile(
                  roomKey: RoomKeys.gpZoomReset,
                  size: RoomBtnSize.toolbarTile,
                  icon: Icons.center_focus_strong,
                  hint: '重置缩放',
                  onTap: () => local.setZoom(RoomUiLocal.zoomMax),
                ),
                // ---- 主组：P17 起只剩上面两个缩放控件（纯视图操作） ----
                // ★ P17 P-4：这里原本有「下一轮」`act/round.next` 与
                //   「转战斗 / 转探索」`act/scene.mode` 两个 `RoomTapTile`
                //   （P16 版 `gp_toolbar.dart:147-174`）。
                //   玩家工具栏的「下一轮」恒灰、点了没用（玩家侧 POLICY
                //   本来就不给 `round.next`），KP 的回合推进在战斗信息栏的
                //   `combat.next`；「转战斗」同属 KP 专属（`scene.mode`）。
                //   两处 UI 已按 §6-Q6 删除，三视角一并去掉。
                //   ⚠️ `RoomKeys.action('round.next')` / `('scene.mode')`
                //   的 key 构造器在 `room_keys.dart`，是 POLICY oracle 的锚点，
                //   保留不动 —— 只是全库不再有 UI 使用点（P17 起）。
                //   若将来要恢复，照 `RoomTapTile(roomKey: RoomKeys.action(op),
                //   enabled: gate.can(op), ...)` 的旧形态加回即可。
                //
                // ---- 主组动作（P17 新增插槽，见 [mainActions] 的注释） ----
                // 「更多工具 / 治疗」必须扁平地待在第 1 行，所以不能塞进下面那条
                // 嵌套 Wrap（骰子条是 `width: double.infinity`，会把整条 Wrap
                // 撑成整行宽度、逼着它自己换行）。
                ...mainActions,
                // ---- 扩展插槽（T03 骰子条 / T04 工具 / T05 手绘板入口） ----
                // 独立成一条 Wrap：扩展按钮内部自己换行，长度不挤压上面的
                // 主按钮，也不会把「KP / 更多工具」推出可视区。
                Wrap(
                  key: GpToolbarKeys.extensions,
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: extensions,
                ),
              ],
          ),
          ),
        ),
      ),
    );
  }

  /// 下一个缩放档位（百分数）。当前值不在档位上时回到最小档。
  static int _nextZoom(double zoom) {
    final percent = (zoom * 100).round();
    final steps = RoomUiLocal.zoomSteps;
    final i = steps.indexOf(percent);
    if (i < 0) return steps.first;
    return steps[(i + 1) % steps.length];
  }
}
