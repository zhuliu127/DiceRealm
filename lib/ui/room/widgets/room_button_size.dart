// ============================================================
// widgets/room_button_size.dart — P16：栏位内按钮统一尺寸的唯一真源
//
// 用户诉求（2026-11 真机反馈）：
//   「跑团房间-游戏中，玩家和 KP 视角，**同一栏位的按钮，都改成大小相同的
//     （宽高相同）**，如果一个栏位有一个比其他的按钮都长的按钮，那就让这一个
//     特殊一点，让其他按钮改成相同大小，然后**重新排布一下，让按钮更整齐**。」
//
// ★ 为什么「只改 minSize」做不到严格等宽（本文件存在的全部理由）：
//   `RoomTap` 内部是
//     ConstrainedBox(minWidth/minHeight) → Align(widthFactor:1,heightFactor:1)
//   ⇒ 实际宽 = max(内容宽, minSize.width)。文案长的那一个会被内容撑开。
//   只有在外层给**紧约束**（`SizedBox(W,H)`）才能精确 W×H：
//   紧约束下 `Align` 不再按内容收缩，`RoomTap` 拿到什么尺寸就是什么尺寸。
//
// ★ 硬边界（P16 施工铁律，违反即验收失败）：
//   · 本文件是**新文件**：不改 `room_panel_kit.dart` 一个字节
//     （`RoomTap` / `ConfirmTwice` 的类体零改动）；
//   · 不给 `RoomTap` 自身加 `width: double.infinity`
//     （会让 `Wrap` 退化成「一个按钮一行」，是 P10 第 2 期 B 修过的 bug）；
//   · 语义 `key` 一律交给**内部 RoomTap**（`roomKey`），
//     这样 `find.byKey(k).getSize()` 量到的就是 RoomTap 自身尺寸，
//     T-30 权限探针读到的也仍是 `RoomTap.enabled`；
//   · `enabled` 必须**原样透传**，绝不在这里叠加任何业务条件；
//   · 调用点不许写裸 `Size(...)`，一律取 [RoomBtnSize] 里的常量。
//
// ★ 高度双档（不做全局 48，理由见规格 §4）：
//   工具栏族（条）= 40：骰子条 8/14 本来就是 40，提到 48 会顶「工具栏最大
//     高度占比」约束（竖屏会多占 ~32dp）；
//   面板族（卡）= 48：素材行被 `p10_t7:427-430` 钉死 ≥47.5。
//   「同一栏位内完全一致」是用户原话的口径，跨区域的「条」和「卡」不必一样高。
// ============================================================

import 'package:flutter/material.dart';

import 'room_panel_kit.dart' show RoomTap;

/// 栏位按钮尺寸族：全工程唯一真源。
///
/// 命名口径：`<栏位族><Tile>`，一眼能看出「这个常量给谁用」。
class RoomBtnSize {
  const RoomBtnSize._();

  // ---- 工具栏族（高 40）----

  /// `gpToolbar` 主组 4 个（缩放百分比 / 复位 / 下一轮 / 转战斗）。
  static const Size toolbarTile = Size(80, 40);

  /// `gpToolbar` 扩展里除「BGM 场景」外的两个（KP / 更多工具）。
  ///
  /// 与 [toolbarTile] 同高、更宽：`更多工具` 的内容宽 86，80 装不下。
  static const Size toolbarWide = Size(90, 40);

  /// `gp_dice_bar` 8 个（奖惩 / D100 / 其他骰子 / 自定义掷 / 暗骰 / 战技 / 对抗）。
  static const Size diceTile = Size(90, 40);

  /// 工具栏唯一的长按钮：`BGM 场景`（全栏最长，按用户规则「特殊」）。
  ///
  /// ★ 这是**下限，不是固定宽**：该按钮走 `minSize`（不套 `RoomTapTile`），
  ///   没有任何用例钉住它的宽度，实际宽度由内容决定 ——
  ///   实测 `BGM 场景` = **113.5×40**（测试字体，每字 13.25dp）；
  ///   真机 Roboto 下约 104~110。写死 104 会与实测不符，故只作下限用。
  static const Size diceLong = Size(104, 40);

  // ---- 面板族（高 48）----

  /// `gpKpTools` / `gpKpLeft` 的工具按钮（加怪 / 标点 / 画笔 / 橡皮 / 放单位 / 放玩家）。
  static const Size toolsTile = Size(90, 48);

  /// `gpKpLeft` 素材三按钮（公开 / 封面 / 删除）。
  ///
  /// ★ 必须保持 48×48：`p10_t7_layout_test:427-430` 与
  ///   `p10_t7_b_assets_actors_test:394-397` 钉死「热区 ≥47.5」。
  static const Size assetTile = Size(48, 48);

  /// `gpScene`（KP 场景检定）2 个：推送检定 + 检定编辑器。
  ///
  /// ★ 2.34.0 / KP-6b：6 档结果裁定按钮已移除，本组只剩这两个动作按钮；
  ///   仍是 2 个 108×48 的 `roomTapWrap2` 网格（1 行 × 2 列，不塌陷、无占位）。
  /// ★ 实测校准（测试字体每字 13.25dp，比真机 Roboto 宽，取更紧的那一侧）：
  ///   当前最长标签是 `检定编辑器`（5 字，含 `Icons.edit` 与左右 12dp padding
  ///   实测远小于 108），`推送检定`（4 字）更短；改前的校准依据是 6 档里
  ///   最长的 `极难成功(4)` 一类 7 字档（92.75 + 12 = 104.75，104 会
  ///   overflow 0.75px ⇒ 上调到 108，实测 + 3.25 余量）。
  ///   108 在 1280/1524 档（内容宽 238.9）是 2 列：`2×108 + 4 = 220 ≤ 238.9`。
  ///   412dp 竖屏是单列通栏（格宽 396）⇒ 2 个按钮同排，无孤行、不算错。
  /// ★ 尺寸值 `Size(108, 48)` **逐字不动**（`p16_button_unify_test.dart` 钉住），
  ///   只同步校准依据文案；1.3 / 1.5 / 2.0 三档文字缩放由 `RoomTapTile` 内部
  ///   `clampBtnText` 钳到 1.0，定宽按钮不会被撑破。
  static const Size sceneTile = Size(108, 48);

  /// `gpPlCharCard` 4 个短按钮（状态管理 / 急救 / 物品 / AI RP）。
  ///
  /// ★ 实测校准：本组最宽的是 `AI RP`（测试字体 5 字 → 实测 100.25，
  ///   已含左右 12 padding）⇒ 需要 ≥ 101，故上调到 104（余量 3.75）。
  ///   `状态管理` 87、`急救` / `物品` 60.5 都远小于 104。
  ///   104 仍是 2 列：`2×104 + 4 = 212 ≤ 1280 档内容宽 223.2`。
  static const Size charTile = Size(104, 40);

  /// `gpPlScene` 技能 chip 的**最小**宽（高度恒定 32）。
  ///
  /// ★ 唯一不定宽的组：技能名来自角色卡数据，长度不可预置。
  ///   定宽会把长技能名挤成 RenderFlex overflow，所以这里只给下限。
  static const Size scenePlTile = Size(90, 32);

  // ---- 行内小控件 ----

  /// `gpFeeds` / `gpPrivates` 的 `SectionBox.trailing` 小图标（新 / 全屏）。
  static const Size trailingSm = Size(44, 32);

  /// `gpFeeds` 聊天输入行 3 个图标（AI RP / 全屏编辑 / 发送）。
  static const Size chatIcon = Size(48, 44);

  // ---- 满宽长按钮（宽 0 表示「由 fullWidth 拉满」，高是唯一语义）----

  /// 独占一行、拉满栏位可用宽的面板按钮（上传素材，高 48）。
  static const Size fullRow48 = Size(0, 48);

  /// 独占一行、拉满栏位可用宽的面板按钮（保存 / 推进 / 检定，高 40）。
  static const Size fullRow40 = Size(0, 40);

  // ---- 间距（沿用既有口径，不新造数值）----

  /// `Wrap` 的主轴间距：与工具栏 / 面板既有 `spacing: 4` 一致。
  static const double gap = 4;

  /// 骰子条的紧缩间距：与 `gp_dice_bar.dart` 既有 `spacing: 3` 一致。
  static const double gapTight = 3;
}

// ------------------------------------------------------------
// 文字缩放钳制（大字体不溢出）
// ------------------------------------------------------------

/// 房间按钮文字允许的最大缩放倍率。
///
/// ★ 为什么必须钳：`RoomTapTile` 用 `SizedBox(W,H)` 给的是**紧约束**，而
///   `RoomTap` 内部 `Text(fontSize: 13)` 默认跟随 `MediaQuery.textScaler`。
///   用户把系统字号调大 → 内容变宽 → 撑破定宽 → `RenderFlex overflowed`。
///   这是 P16 定宽化**新引入**的回归（改前裸 `RoomTap` 宽度自适应，不会溢出）。
///   QA 实测 1.3/1.5/2.0 三档字号 × 12 格 = 36 格红，最大溢 **87.8dp**。
///
/// ★ 为什么钳到 1.0 而不是给按钮加宽/加高：
///   这些是**固定尺寸的密集型工具栏**——文字只有 2~5 字、字号 13，按钮高
///   40~48 本身足够可读；而「360dp 上一行 4 个」是靠 80dp 定宽换来的，
///   按 2.0 倍字宽反推需要 160dp，一行只能放 2 个，用户抱怨的「堆成好几行」
///   会原样回来。所以这是一个**坐标明确的取舍**：按钮文字不跟随系统字号。
///
/// ★ 影响范围严格可控：只钳**按钮子树**。面板标题、正文、聊天、笔记、
///   私密信息等所有非按钮文字**完全不受影响**。
const double kBtnMaxTextScale = 1.0;

/// 把按钮子树的文字缩放钳到 [kBtnMaxTextScale] 以内（只影响该子树）。
///
/// 两处共用（`RoomTapTile` 内部 + 工具栏那个不定宽的缩放按钮），
/// 抽成一个函数是为了「以后改倍率只改一处、不会两份漂移」。
Widget clampBtnText(Widget child) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: kBtnMaxTextScale,
      child: child,
    );

/// 严格等宽等高按钮：`SizedBox(W,H)` 紧约束 + 原样 `RoomTap`。
///
/// ★ 只在「该组所有文案的实测内容宽都 ≤ W」时使用（每个常量的余量见
///   [RoomBtnSize] 的注释）。内容 > W 时 `RoomTap` 内部的 `Row` 会
///   RenderFlex overflow —— 那是唯一的使用禁忌，兜底办法是把 W 上调到
///   「实测 + 4」，**不是**加 `ClipRect` 硬裁、也**不是**改文案。
///
/// ★ `roomKey` 挂在内层 `RoomTap` 上，所以：
///   · `tester.getSize(find.byKey(roomKey))` = 精确 W×H（量到的是 RoomTap）；
///   · `tester.widget<RoomTap>(find.byKey(roomKey)).enabled` 仍可被 T-30 读取；
///   · 既有 `find.byKey(...)` 用例无需改动。
class RoomTapTile extends StatelessWidget {
  const RoomTapTile({
    super.key,
    required this.size,
    this.label = '',
    this.icon,
    this.pngIcon,
    this.enabled = true,
    this.hint,
    this.onTap,
    this.roomKey,
    this.fullWidth = false,
  });

  /// 目标尺寸（取 [RoomBtnSize] 里的常量；[fullWidth] 为 true 时只用其高度）。
  final Size size;

  final String label;
  final IconData? icon;
  final String? pngIcon;

  /// 原样透传给 [RoomTap]：T-30 表驱动权限探针读的就是它，不许改写。
  final bool enabled;

  final String? hint;
  final VoidCallback? onTap;

  /// 语义 key（挂在内层 `RoomTap` 上，不是挂在本 widget 上）。
  final Key? roomKey;

  /// true：宽度拉满父级可用宽（用于「独占一行的长按钮」）。
  ///
  /// ★ 用 `SizedBox(width: double.infinity)` 而不是给 `RoomTap` 加
  ///   `width: double.infinity`：后者会在 `Wrap` 里退化成一行一个。
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    // ★ 文字缩放必须在**内层** RoomTap 之上钳住：紧约束 + 放大字宽 = overflow。
    final Widget body = RoomTap(
      key: roomKey,
      label: label,
      icon: icon,
      pngIcon: pngIcon,
      enabled: enabled,
      hint: hint,
      onTap: onTap,
      // 双保险：即使将来父级约束被放松，尺寸也不会小于规格值。
      // 满宽时 minWidth 必须为 0 —— 真 Infinity 会与父级紧约束打架。
      minSize: Size(fullWidth ? 0 : size.width, size.height),
    );
    return SizedBox(
      width: fullWidth ? double.infinity : size.width,
      height: size.height,
      child: clampBtnText(body),
    );
  }
}

/// 等分一行：宽度 = 栏位可用宽 / N，无魔数。
///
/// 仅用于「按钮数固定、且每个文案都确定 ≤ 1/N」的组。给子件的是 `Expanded`
/// 的**紧宽**，`RoomTap` 在紧约束下不收缩 ⇒ 天然填满、天然等宽。
///
/// ★ 当前 P16 的栏位都用了定宽 [RoomTapTile]（需要精确值给测试断言），
///   本组件作为「宽度无法预置时的等价手段」保留给后续分组使用。
class RoomTapEqualRow extends StatelessWidget {
  const RoomTapEqualRow({
    super.key,
    required this.children,
    this.gap = RoomBtnSize.gap,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// 2 列网格：`Wrap` + 已定宽的 tile。
///
/// 为什么不写死「每行 2 个」：栏宽不足时 `Wrap` 会自动掉成 1 列
/// （例如 `gpKpTools` 在 240dp 格宽下的极端档），**不裁切、不 overflow**；
/// 栏宽够时又天然是 2 列，比 `Row`+`Expanded` 更耐窄。
///
/// ★ 传入的 tile 必须自带确定宽度（`RoomTapTile`），否则 `Wrap` 无法算列数。
Widget roomTapWrap2(List<Widget> tiles) => Wrap(
      spacing: RoomBtnSize.gap,
      runSpacing: 2,
      children: tiles,
    );

/// **固定 [columns] 列**网格：把栏位可用宽的上限钳到
/// 「`columns` 个 tile + 它们之间的间距」，于是再宽的栏位也只排 [columns] 列。
///
/// ★ 为什么需要它（P16 修复）：[roomTapWrap2] 是「能塞几个塞几个」。
///   `gpPlCharCard` 的 4 个短按钮（各 104）在 360dp（内容 316）与 1280dp
///   （内容 223.2）都是 2+2，但 **412dp 竖屏是单列通栏（内容 ≈368），
///   会排成 3+1** —— 最后那个 `AI RP` 孤零零一行，正是用户抱怨的
///   「不整齐」的原形态。用户要的是「重新排布一下，让按钮更整齐」，
///   所以这里把列数**钉死**，不允许窄档好看、宽档却翻车。
///
/// ★ 窄档不会裁切：`Wrap` 在钳制宽（212）放不下时自动掉成 1 列
///   （例如 `roomDockMinWidthOf` 的极端下限档），绝不 overflow。
///
/// ★ 为什么用 `Align` 包 `SizedBox`：`Column(stretch)` 给的是**紧宽**，
///   `SizedBox(width:)` / `ConstrainedBox` 在紧约束下都无法收窄；
///   `Align` 没有 `widthFactor` 时会把子件约束**放松**，`SizedBox` 才生效。
Widget roomTapFixedGrid2(
  List<Widget> tiles, {
  required double tileWidth,
  int columns = 2,
}) {
  return Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: columns * tileWidth + (columns - 1) * RoomBtnSize.gap,
      child: Wrap(
        spacing: RoomBtnSize.gap,
        runSpacing: 2,
        children: tiles,
      ),
    ),
  );
}
