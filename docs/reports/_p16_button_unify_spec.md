# P16 · 房间游戏页「栏位内按钮统一尺寸 + 重排」可执行规格

- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`（v2.27.0+97）
- 角色：架构师（高见远） / **只读产出**，未改任何源码、配置、测试
- 上游输入：`_p16_button_audit.md`（526 行，全文逐节使用）
- 本文地位：工程师施工的唯一依据。文中所有「估算」均已标注，凡标 **[实测]** 的必须在施工时用测试实测校准并回填。

---

## 0. 结论先看（6 行）

| 项 | 结论 |
|---|---|
| **统一机制** | **方案 B**：新增 `RoomTapTile`（`SizedBox(W,H)` 包 `RoomTap`，新文件、`RoomTap` 一行不改）+ `RoomTapEqualRow`（`Row`+`Expanded` 等分，仅用于宽窄不可预置的组）。**只改 `minSize` 做不到严格等宽**（原文证明见 §1.1） |
| **高度档位** | **按栏位分别统一**：工具栏族 = **40**（骰子条 8/14 已是 40，且 48 会顶 `kToolbarMaxShare`）；面板族 = **48**（素材行被测试钉死 ≥48）；`gpPlCharCard` = 40；`gpStatus` = 36。**不做全局 48**（理由 §4） |
| **需改栏位** | 9 个：`gpToolbar`(+骰子条+扩展)、`gpKpTools`、`gpKpLeft`、`gpScene`、`gpPlScene`、`gpPlCharCard`、`gpFeeds`(trailing+输入行)、`gpPriv`、`gpStatus`(仅间距) |
| **保留原样** | 5 个：`gpMapStage`、`gpPlNotes`、`gpPlSketch`、`gpPlMates`、`gpTopbar`；**另：`gpCombat` 宽度不动**（§6） |
| **测试改动** | **既有断言值改 0 条**（44 条全部原样绿）；**新增 13 条正向断言**（`test/p16_button_unify_test.dart`）；1 处注释更新 |
| **增行** | **零增行**（唯一行数变化是 `gpKpTools` 少 1 行）→ 不需要用户拍板「增行是否可接受」 |

---

## 1. 统一化的技术手段（先定机制）

### 1.1 ★ 关键问题：只改 `minSize` 能否真正等宽？——**不能**

`RoomTap` 的实际尺寸链（`room_panel_kit.dart:210-229`，逐行核对）：

```
ConstrainedBox(minWidth: minSize.width, minHeight: minSize.height)   // :210-214
  → Align(alignment: center, widthFactor: 1, heightFactor: 1)        // :220-223
    → Padding(horizontal: 6) → Row(mainAxisSize: min)
```

- `ConstrainedBox` 只给**下限**（`minWidth/minHeight`），**没有上限**；
- `Align(widthFactor: 1)` 的语义是「按内容收紧 = 内容宽」；
- 两者叠加 ⇒ **实际宽 = max(内容宽, minSize.width)**。

所以：`其他骰子`（内容 86）传 `minSize: 76` 时实测仍是 86；`奖励 5`（内容 70.7）传 76 才是 76。
**只改 `minSize` 只能消除「比下限更窄」的那部分差异，无法消除「文案更长」造成的撑开。**

### 1.2 方案比较

| 方案 | 做法 | 严格等宽? | 风险 | 判定 |
|---|---|---|---|---|
| A | 每栏位定义 `static const Size`，全部传同一 `minSize` | ❌ 内容比 W 长的那个仍会撑开 | 最低 | **必要但不充分**，作为「尺寸来源」保留 |
| B | 新增上层包装 `RoomTapTile`：`SizedBox(W,H)` 紧约束包 `RoomTap` | ✅ `SizedBox` 给 tight 约束 → `Align` 在紧约束下按约束尺寸，`RoomTap` 精确 W×H | 低：内容 > W 时**内部**`Row` 会 RenderFlex overflow（`Row.mainAxisSize.min` 装不下） | ✅ **推荐** |
| C-1 | `Row` + `Expanded` 等分（`RoomTapEqualRow`） | ✅ 宽度 = 栏位可用宽 / N，非魔数 | 中：内容 > 1/N 时 overflow；宽度随屏宽变（不能写进 `static const`） | ✅ 用于「按钮数固定、文案长度已知」的组（`gpScene` 6 档可备用） |
| C-2 | `FittedBox(scaleDown)` 包 `RoomTap` | ✅ 且永不 overflow | 中：字号被等比缩小（13→9.x），一组里字号不一致比宽度不齐更难看 | ⚠️ 仅作**防御兜底**，不作为主手段 |

**最终机制 = B 为主 + C-1 兜底**：

```dart
// 新文件：lib/ui/room/widgets/room_button_size.dart
// ★ 零改动 RoomTap：只在其外面套一层紧约束。

/// 栏位按钮尺寸族（唯一真源；不许在调用点写裸 Size）。
class RoomBtnSize {
  const RoomBtnSize._();
  // —— 工具栏族（高 40）——
  static const Size toolbarTile = Size(80, 40);   // gpToolbar 主组 4 个
  static const Size diceTile    = Size(90, 40);   // gp_dice_bar 8 个
  static const Size diceLong    = Size(104, 40);  // BGM 场景（唯一长按钮）
  // —— 面板族（高 48）——
  static const Size toolsTile   = Size(90, 48);   // gpKpTools / gpKpLeft
  static const Size assetTile   = Size(48, 48);   // 素材三按钮（测试钉死）
  static const Size sceneTile   = Size(104, 48);  // gpScene 8 个
  static const Size charTile    = Size(90, 40);   // gpPlCharCard 4 短
  static const Size scenePlTile = Size(90, 32);   // gpPlScene 技能 chip（最小宽）
  // —— 行内小控件 ——
  static const Size trailingSm  = Size(44, 32);   // 新 / 全屏（trailing）
  static const Size chatIcon    = Size(48, 44);   // 聊天输入行 3 个
  static const double gap       = 4;              // Wrap spacing（既有口径）
  static const double gapTight  = 3;              // 骰子条 spacing（既有口径）
}

/// 严格等宽按钮：SizedBox 紧约束 + RoomTap 原样。
/// ★ 只在「该组所有文案都确定 ≤ W」时使用（见 §2 每行的余量列）。
/// ★ 绝不改 RoomTap 内部；Key 仍挂在 RoomTap 上，T-30 探针与
///   `getSize(find.byKey(...))` 都读到精确 W×H。
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
  });

  final Size size;
  final String label;
  final IconData? icon;
  final String? pngIcon;
  final bool enabled;
  final String? hint;
  final VoidCallback? onTap;
  /// 语义 key 仍交给内部 RoomTap（保证 `find.byKey` 量到的是 RoomTap 自身）
  final Key? roomKey;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size.width,
        height: size.height,
        child: RoomTap(
          key: roomKey,
          label: label,
          icon: icon,
          pngIcon: pngIcon,
          enabled: enabled,   // ★ 必须原样透传：T-30 读的就是它
          hint: hint,
          onTap: onTap,
          minSize: size,      // 双保险：即使父级约束变松也仍是 size 起步
        ),
      );
}

/// 等分一行（宽度 = 可用宽 / N，无魔数）。仅用于「N 固定、文案确定 ≤ 1/N」。
class RoomTapEqualRow extends StatelessWidget {
  const RoomTapEqualRow({super.key, required this.children, this.gap = 4});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: children[i]),
          ],
        ],
      );
}
```

> ⚠️ `RoomTapEqualRow` 里的 `Expanded` 给的是**紧宽**，`RoomTap` 会自动填满（`Align` 在紧约束下不收缩）—— 这正是 §6.9 说的「不要给 `RoomTap` 加 `width: infinity`」的正确替代。

### 1.3 ★ 竖排等宽：`Column(stretch)` 还是 `SizedBox(width: infinity)`？

| 场景 | 用什么 | 为什么 |
|---|---|---|
| 一行里多个按钮等宽（`Wrap` 内） | **`SizedBox(W,H)` 定宽**（`RoomTapTile`） | `Wrap` 没有交叉轴拉伸；给 `RoomTap` 加 `width: infinity` 会退化成「一个按钮一行」= P10-2B 修过的 bug |
| 竖排 / 独占一行的单个按钮要「拉满整行」 | **`SizedBox(width: double.infinity)` 包住 `RoomTap`** | 父级（`Column(stretch)`）已经是紧宽，`SizedBox` 取 `maxWidth` 后传给 `RoomTap` 的就是紧约束 → `Align(widthFactor:1)` 不收缩 → 精确满宽 |
| 已有 `Column(crossAxisAlignment: stretch)` 且子件**就是** `RoomTap` | 直接用（去掉外层 `Align(centerLeft)`） | 紧宽直接传给 `RoomTap` |

**明确禁止**：给 `RoomTap` 自身加 `width: double.infinity`（破坏 `Wrap` 多列，P10-2B 回归）。
**注意**：目前「单按钮行」都写成 `Align(alignment: centerLeft, child: RoomTap)`——`Align` **没有** `widthFactor` 时会填满并让 `RoomTap` 收缩居中，所以**必须换成** `SizedBox(width: double.infinity, ...)` 才能满宽。

### 1.4 ★ 文字过长的策略（不许 overflow、不许硬裁）

`RoomTap` 内部是 `Text(label)` 无 `maxLines`/`overflow`，且**不许改**。因此三层策略：

| 层 | 做法 | 适用 |
|---|---|---|
| ① 定宽留余量（主策略） | W = 组内最长文案 + **≥4dp 余量**；§2 每行都给出「文案估算 / 余量」两列 | 静态文案组（等级 6 档、工具 5 个、素材 3 个、骰式、扩展） |
| ② 不定宽（动态文案） | 保持 `minSize` + 内容自适应（`Wrap` 天然不溢出） | `gpPlScene` 技能 chip（技能名来自角色卡，长度不可预置）、`gpPlayers` 行内按钮 |
| ③ 拉满整行 | 该栏位唯一的长按钮 → `SizedBox(width: infinity)`，可用宽恒 ≥ 内容宽 | `gpKpTools`/`gpKpLeft` 上传素材、`gpPlCharCard` 保存/推进、`gpPlScene` 检定按钮 |

**兜底（若施工实测某文案超估算）**：把该组的 W 上调到 `实测 + 4`，并**同步**改 `test/p16_button_unify_test.dart` 里的期望 `Size`（属「等价更新」，精度不降）。**禁止**用 `ClipRect` 硬裁，也**禁止**为了塞进定宽而改文案（`find.text('更多工具')` 等 6 处测试依赖字面文案）。

**文案宽度估算模型**（全篇算术的唯一口径，施工时以实测校准）：
`内容宽 = 12(左右 padding 6+6) + [icon:22 | pngIcon:20] + 文本宽`，
CJK = 13.0/字、ASCII 数字字母 = 7.2、`(`/`)` = 6.5、空格 = 3.5、`▶`/`＋` = 13。

---

## 2. ★ 逐栏位目标尺寸表（核心交付物）

**可用宽口径**（两种都算，取更紧的）：
- **[下限]** `roomDockMinWidthOf(slot) − 28`（`room_layout.dart:228-273`；28 = `Card` margin 4×2 + `Padding` 10×2）。这是 `_slotView` 的 tooNarrow 兜底宽度，**任何统一都必须在这里也放得下**。
- **[1280]** 用 `p10_t6_layout_test.dart:432-441` 的官方算式实测：`右列 = 1256×0.83 = 1042.5`、`上排可用 = 1026.5`、`kpTools = 246.4 / map = 513.2 / 右列 = 266.9`；玩家侧 `charCard = 251.2 / 右列 = 351.8 / 中排 = 498.4`。

| 栏位 | 当前按钮数与尺寸（审计 §2） | **统一后 W×H** | 长按钮（哪个/多宽） | 换行/排布策略 | 依据（算术） | 风险 |
|---|---|---|---|---|---|---|
| **gpToolbar 主组**（4） | zoomPercent 65×48、reset 48×48、下一轮 73×48、转战斗 73×48 | **80×40** | 无 | `Wrap(spacing:4)` 不变，仍 1 行 | 内容 max=73（下一轮/转战斗）；360dp 可用 348：`4×80+3×4 = 332 ≤ 348` ✅；412：`332 ≤ 400` ✅ | 低。仅高度 48→40（**变矮**→ 高度类断言更宽松） |
| **gpDiceBar**（8 + 1 TextField） | 奖励/惩罚 52×40、D100 48×40、其他骰子 **88×40**、rollCustom 48×40、暗骰 64×40、战技/对抗 56×40；TextField 固定 68 | **90×40** | **无**（`其他骰子` 内容 86 ≤ 90，归入同一档） | 窄档 `_balancedRows` 3/3/3（**不变**）；宽档单 `Wrap` 不变 | 内容 max=86（其他骰子，余量 4）；360：`3×90+2×3 = 276 ≤ 340` ✅；412：行宽 `276 ≤ 392` ✅；`maxPerRow` 见 §5，360/412 均 = 3/4 → 3 行 | 低。除数 88 必须换成 `90+3`（§5） |
| **gpToolbar 扩展**（KP / 更多工具 / BGM） | KP 56×40、BGM **104×40**、更多工具 **96×40** | KP / 更多工具 **90×40**；BGM **104×40** | **BGM 场景 104×40**（内容 88.5，全栏唯一长按钮） | 独立 `Wrap(extensions)`，1 行 | 更多工具内容 86 ≤ 90（余量 4）；`90+4+104 = 198` 远小于 348 | 低。`find.text('更多工具')` 等依赖文案 → **只改尺寸不改字** |
| **gpKpTools**（6 + 1 长 + 1 二次确认） | 加怪 48(实 60)、标点/画笔/橡皮 73、放单位/放玩家 73、上传素材 86、ConfirmTwice 86↔112 | 6 个 **90×48**；上传素材**满宽×48**；ConfirmTwice **保持默认（特殊）** | 上传素材（满宽）、ConfirmTwice（86↔112 两态） | 6 个改 **2 列网格**（`roomTapWrap2(...)`：`Wrap(spacing:4)` + 每个 `RoomTapTile(90×48)`；栏宽不足时自动掉成 1 列而不裁切）；上传素材仍独占一行并满宽 | 内容 max=86 ≤ 90；[下限] 212：`2×90+4 = 184 ≤ 212` ✅；3 列需 `3×90+8 = 278 > 212/218` ❌ → **只能 2 列** | 中：行数 5→4（**少 1 行**，格子更松，无 overflow 风险） |
| **gpKpLeft**（1+3+1+2） | 加怪 48(实 60)、移除 48、上传素材 86、公开/封面/删除 48×48 | 加怪 **90×48**；移除 / 素材三按钮 **48×48**（不变）；上传素材**满宽×48** | 上传素材（满宽） | 素材三按钮 `Wrap(spacing:2)` 保持 1 行 | [下限] 172：`3×48+2×2 = 148 ≤ 172` ✅ 1 行（不变）；`90 ≤ 172` ✅ | 低。素材三按钮**必须**保持 48×48（`p10_t7:427-430`/`p10_t7_b:394-397` 要 ≥47.5） |
| **gpScene**（KP，8） | 等级 6 档 57.5~83.5（宽差 26dp）、快速推送 86、检定编辑器 99 | **全 8 个 104×48** | 无（`检定编辑器` 99 ≤ 104，与等级档同宽） | 6 档 **2 列**（3 行）+ 2 个推送 **2 列**（1 行）；用 `RoomTapEqualRow(2)` | 内容 max=83.5（极难/困难成功）→ 104 余量 20.5；[下限] 232：`2×104+4 = 212 ≤ 232` ✅；3 列需 `3×104+8 = 320 > 232/239` ❌ | 低。今日也是 2 列 3 行（83.5×3+8 = 258.5 > 239）→ **行数不变 0 增行** |
| **gpPlScene**（玩家） | 技能 chip 72×32（长名会撑开，最宽 ≈95）、检定按钮 140×40（宽随技能名跳） | chip **minSize 90×32**（内容自适应）；检定按钮**满宽×40** | 检定按钮（满宽） | chip 保持 `Wrap`（**不定宽**，理由见 §1.4②） | [下限] 260：`2×90+4 = 184 ≤ 260` ✅；3 个 `3×90+8 = 278 > 260` → 2 个/行 | 中：chip 是**唯一不能严格等宽**的组（数据驱动文案）→ 断言用「≥90 且高 ==32」，见 §7 |
| **gpCombat**（trailing） | 下一个行动 ▶ 96（**实测内容 115.5**，已超声明值）、＋加入 80×32 | **不动**（96/80×32 保持） | `下一个行动 ▶` 是长按钮 → 按用户规则「特殊」 | `SectionBox.trailing` 结构不动 | 见 §6：`2×115.5+4 = 235 > [下限]192` → 任何「等宽到长按钮」都会 overflow | **高（因此不改）** |
| **gpStatus**（2） | 同意 56×36、拒绝 56×36，**中间 0 间距** | **56×36 不变**，仅加 `SizedBox(width:6)` | 无（已等宽） | `Row` 不变 | 已等宽；唯一问题是贴在一起像「一个被劈开的按钮」 | 极低（纯间距） |
| **gpPlCharCard**（4+2） | 状态管理 84(实 86)、急救/物品/AI RP 64、保存 128×40、推进 112×40 | 4 短 **90×40**；2 长**满宽×40** | 保存到已保存 / 推进 1 轮（满宽） | 4 短 → **2 列**（2 行）；2 长各占一行满宽 | 内容 max=86 ≤ 90；[下限] 202：`2×90+4 = 184 ≤ 202` ✅；3 列 `3×90+8 = 278 > 223` ❌ | 低。行数 2→2（今日 3+1，改后 2+2，**无孤行**） |
| **gpFeeds trailing**（2 个 + 文本） | 新 40×32、全屏 44×32 | **44×32 ×2** | 无 | `Row` 不变 | trailing 无界宽不换行；`44+44 = 88` vs 今日 84（+4），实际栏宽 314（1280）远大于此 | 低。**不改结构**（§6） |
| **gpFeeds 输入行**（3） | AI RP 48×44、全屏编辑 44×44、发送 48×44 | **48×44 ×3** | 无 | `Row[Expanded(TextField), 3 按钮]` 不变 | 360dp：`3×48 = 144`，输入框剩 ~180 ✅ | 低 |
| **gpPriv trailing**（2） | 新 40×32、全屏 44×32 | **44×32 ×2** | 无 | `Row` 不变 | 同上 | 低 |
| **gpMapStage**（4） | 36×32 ×4，**已等宽** | **保持 36×32** | — | `Positioned`+`Row` 不变 | 见 §3（浮层控件） | — |
| **gpPlNotes**（2） | add 48×44、删除 36×30 | **保持** | — | — | 见 §3（行内控件） | — |
| **gpPlSketch**（2+1） | 笔/擦 48×32（已等宽）、ConfirmTwice | **保持** | ConfirmTwice | — | 已等宽 | — |
| **gpPlMates**（1） | 44×32 | **保持** | — | — | 单按钮无可统一 | — |
| **gpTopbar**（1） | 观众 56×32 | **保持**（`p10_t6:198-199` 要 ≥56×32） | — | — | 单按钮；其余是 `_flexChip`（非 RoomTap） | — |
| **gpPlayers**（2/成员） | 详情 48、全屏 73 | **保持** | 全屏 | `Row[Expanded(Text), RoomTap]` | **独立复核结论：右边缘本来已对齐**（两个按钮都在行尾），不齐的是左边缘且紧邻变长文本 → 视觉无感（与审计 §3.8 不同意见） | — |

**增行汇总：零增行。** 唯一行数变化 = `gpKpTools` 从 5 行降到 4 行（少 1 行）。因此**不需要用户就「增行是否可接受」拍板**。

**高度影响汇总**：`gpToolbar` 主组 48→40（工具栏**变矮 8**，`p10_t3:268-287`、`room_ui_layout:547` 全部更宽松）；其余栏位高度不变。

---

## 3. 三处「不该强行统一」的裁定（独立复核）

| 栏位 | 审计建议 | **我的裁定** | 可直接转给用户的解释 |
|---|---|---|---|
| `gp_map_stage`（4×36×32） | 保留 | ✅ **同意保留** | 「舞台右下角那 4 个是**压在画面上的浮层控件**（放大/缩小/复位/全屏），不是栏位里的按钮组；它们本来就一模一样大，再放大就会盖住你的地图。」 |
| `gp_feeds` 花幸运 / 推动（132×30） | 保留 | ✅ **同意保留**（且**不加高**） | 「『花幸运 / 推动』是贴在**每条消息行尾**的行内小按钮，加高会把每条消息的行距从 34 撑到 52，整个信息流会瞬间变稀。」 |
| `gp_pl_notes` 删除（36×30） | 保留 | ✅ **同意保留** | 「笔记每行末尾的删除按钮属于**高密度列表**，一个 48dp 的红叉会把一行笔记挤成两行。」 |

**共性口径（写进 PRD 结论）**：用户说的「栏位里的按钮」= 栏位**按钮组**；浮层控件（舞台缩放条）、行内控件（消息行尾、列表行尾）不属于按钮组，保持原尺寸。

**补充裁定（审计未提，我新增）**：
- `gpCombat` trailing 的 `下一个行动 ▶`：`SectionBox.trailing` 里的按钮**也不属于「按钮组」**（它是标题栏右上的操作），且见 §6 的技术约束 → **宽度保留**。
- `gpPlCharCard` / `gpFeeds` / `gpPlSketch` 的 `SectionBox.trailing` 图标（44×32 / 44×32 / ConfirmTwice）：同属标题栏控件 → **保留**。

---

## 4. 高度统一的关键裁决

**问题**：`48/40/44/32` 四种高度混排是视觉噪声主因，但 `gpKpLeft` 素材三按钮被 `p10_t7:427-430` + `p10_t7_b:394-397` 钉死 **≥47.5 高** ⇒ 「全局统一到 40」被堵死。

### 裁决：**按栏位分别统一高度**（不做全局 48）

| 方案 | 满足「同一栏位大小相同」 | 风险 | 说明 |
|---|---|---|---|
| 全局统一 48 | 同样满足 | **高** | ① 骰子条 3 行 ×+8 = **+24dp**，主组 +8 → 工具栏在 360/412 上多占 ~32dp，直接顶 `kToolbarMaxShare = 0.62`（`room_game_page.dart:372-376`）与 `viewport.height > 120`（`room_ui_layout:547`）；② 十字滑块条从「紧凑条」变「大按钮墙」，与 P10-7 特意压薄的意图相反；③ 素材行 ≥48 只是**下限**，不需要全局值就是 48 |
| **按栏位分别统一** | **同样是「同一栏位内完全一致」**（这正是用户原话的口径） | **低** | 每个栏位取其**主流高度**：工具栏族 40（8/14 已是 40）、面板族 48（13 处默认就是 48）、`gpPlCharCard` 40（6 处全是 40）、`gpStatus` 36（2 处已是 36） |

**为什么最终不选 48（对用户可直接说）**：「竖屏手机上工具栏只有那一条，压到 40 高能让你一屏看到更多内容；栏位卡片里的按钮保持 48，手指更好点。跨区域的『条』和『卡』不需要一样大 —— 你要的是**同一栏位里面**一样大，这个做到了。」

**工具栏高度算进决策**：主组 48→40 **让工具栏变矮**，`kToolbarMaxShare` 方向同向收紧，三条高度测试（`p10_t3:268-287`、`p10_t3:297`、`room_ui_layout:547`）**只会更绿**。这是本批唯一「白送」的收益。

---

## 5. `gp_dice_bar.dart:348` 魔数 88 的处理

### 5.1 现状

```dart
maxPerRow = ((outer.maxWidth - 16) / 88).floor().clamp(2, 4)   // :348
```
`88` 是「按钮平均宽」的**魔数**，与任何 `minSize` 无关联。

### 5.2 新公式（把魔数换成「统一宽 + spacing」的符号式）

```dart
// gp_dice_bar.dart 顶部（供测试直接调用的纯函数）
/// 骰子条统一定宽（与 RoomBtnSize.diceTile.width 同源）
const double kDiceTileW = 90;
const double kDiceTileGap = 3;

/// 一行最多放几个（纯函数，可单测）。
int diceMaxPerRow(double availableWidth) =>
    ((availableWidth - 16) / (kDiceTileW + kDiceTileGap)).floor().clamp(2, 4);

/// 均衡切行后每行的按钮数（纯函数，供「无孤行」断言直接调用）。
List<int> diceBalancedRowSizes(int itemCount, int maxPerRow) { /* 同 _balancedRows 的算术 */ }
```

`-16` 保留（既有保守口径：padding 4×2 + 安全 8），除数 = `90 + 3 = 93`。

### 5.3 三档验算（`_kGroupBelowWidth = 600` 以下走此公式；9 项）

| 屏宽 | `outer.maxWidth` | `(w-16)/93` | `maxPerRow` | 行数 = `ceil(9/per)` | 每行个数 | 行宽 = `3×90+2×3` | 是否放得下 |
|---|---|---|---|---|---|---|---|
| 360 | 348 | 3.568 | 3 | 3 | **3/3/3** | 276 | ✅ ≤ 340 |
| 412 | 400 | 4.129 | 4 | 3 | **3/3/3** | 276 | ✅ ≤ 392 |
| 1280（宽档） | 1268 | —（≥600 走单 `Wrap`） | — | 1 | 9 | 834 | ✅ ≤ 1256 |

### 5.4 为什么三档都不会产生孤行（结构性论证，不靠实测）

1. `_balancedRows` 的分配是 `rowCount = ceil(n/per)`、`base = n ~/ rowCount`、`extra = n % rowCount`。对 **n = 9**：
   - `per = 3` → `rowCount = 3` → `base = 3, extra = 0` → **3/3/3**；
   - `per = 4` → `rowCount = 3` → `base = 3, extra = 0` → **3/3/3**；
   - 只有 `per = 2` 才会退化成 `rowCount = 5 → 2/2/2/2/1`（孤行）。
2. `per = 2` 需要 `(w-16)/93 < 3` ⇒ `w < 295`。工具栏可用宽 = 屏宽 − 12 ≥ 308（最小屏 320） ⇒ **per ≥ 3 恒成立**，`per = 2` 不可达。
3. 战技（第 8 项）恒落在第 3 行 `[暗骰, 战技, 对抗]` → `p10_t6:350`「与战技同 centerY 的按钮 ≥1」恒成立。
4. **行为等价性**：旧除数 88 与新除数 93 在 360/412/560 分别给出 `floor` 值 3/4/6→4 与 3/4/5→4，**clamp 上限 4 让三档取值完全相同** ⇒ 本公式**不改变今天任何档位的切行**，只是把魔数语义化 + 与统一宽同步。

> 因此「行数 ≤4」「每行 ≥2」「战技不孤行」三条**今日绿、改后仍绿**。

---

## 6. `SectionBox.trailing` 无界宽陷阱：本次**不动**结构

### 事实核对

`room_panel_kit.dart:79-97`：`Row(children: [Expanded(Text(title)), ?trailing])`。
`trailing` 在 `Row` 里拿到的是**无界宽**约束 ⇒ 其内部 `Wrap` **永不换行**。

### 裁决：**本次不动 `trailing` 的布局**（不改 `Row` → `Row[Expanded, Flexible]`，不引入换行）

| 理由 | 说明 |
|---|---|
| ① 收益 ≪ 风险 | 动 `trailing` 会改变**所有 12 个栏位**的标题行布局（`SectionBox` 是共用件），`p10_t6:551` 的 `takeException` 是全局闸门，一次改错就是 5 个测试文件一起红 |
| ② `gpCombat` 的算术本来就无解 | `下一个行动 ▶` 实际宽 **115.5**（内容 ≥ 声明 96）；[下限] 192 下 `2×115.5+4 = 235 > 192` ⇒ **任何「等宽到长按钮」的做法都必然 overflow**。唯一出路是改文案（`find.text` 有 6 处依赖）→ 不做 |
| ③ 结构语义 | `trailing` 是**标题栏操作位**，不是「按钮组」；用户诉求针对的是按钮组（§3 口径） |

### 那 `trailing` 里的按钮怎么「安全统一」？

**只朝「不变宽」的方向统一**：
- `gpFeeds` / `gpPriv`：`40×32` 与 `44×32` → 统一到 **`44×32`**（+4dp/栏位，实际栏宽 314/470，安全）；
- `gpCombat`：两按钮高度已一致（32）→ **宽度不动**；
- `gpPlCharCard` / `gpPlMates` / `gpPlSketch`：`trailing` 只有 1 个控件 → 无可统一，不动。

**若未来必须让 `gpCombat` 两按钮等宽**，唯一低风险路径（本次不做，记录备用）：
把两个按钮从 `trailing` 移到 `SectionBox.child` 的 `Column(stretch)` 里，用 `RoomTapEqualRow(2)` → 每个 = `(可用宽-4)/2` ≥ 94（[下限] 192）。**代价**：`下一行动 ▶` 文案需缩到 ≤ 4 字（当前 5 字 + 箭头 = 内容 115.5 > 94），会打红 `room_ui_blocks_test:336` 附近对文案的阅读，需同步改测试 → **收益不足，不做**。

---

## 7. ★ 测试口径更新清单

### 7.1 44 条逐条判定总表

**A 类：必须逐字不动（22 条）**

| # | 文件:行 | 内容 | 为什么不动 |
|---|---|---|---|
| 1 | `p12_emoji_b:256` | 裸 `RoomTap(label:'好')` 精确 `Size(48,48)` | **`RoomTap` 契约**，本次零改动 → 恒绿 |
| 2 | `p12_emoji_b:273` | 显式 `minSize: Size(96,40)` 精确 `96×40` | 同上（证明 `RoomTap` 行为未变） |
| 15 | `p10_t7:427-430` / `p10_t7_b:394-397` | 素材三按钮 `w≥47.5 && h≥47.5` 且不越格 | 我们**保持 48×48** → 恒绿（这是「为什么不能全局 40」的锚） |
| 16 | `p10_t7:416` / `p10_t7_b:382` | 格矩形来源 `RoomSlot.gpKpLeft` | 格里不动 |
| 17 | `p10_t5:351-358` | `sheet_misc` 5 档缩放同一行 | 弹层不在范围 |
| 18 | `p10_t5:395` | 字面扫描 `sheet_misc.dart` 含 `Size(54, 34)` | 弹层不在范围 |
| 19 | `p10_t5:401-404` | 字面扫描 `gp_toolbar.dart` 含 `'点按切换缩放档位`、`Wrap(`，不含 `zoomLabel` | ⚠️ **施工红线**：`gp_toolbar.dart` 里的 `hint: '点按切换缩放档位（60%–100%）'` **逐字保留**；`Wrap(` 保留（我们只改 `minSize`） |
| 20 | `p10_t5:387` | `GpToolbarKeys.quickRow` 必须是 `Wrap` | 施工红线：**不许**把工具栏改成 `Row`/`GridView`；定宽用 `RoomTapTile` 而非等分 |
| 26–36 | `room_ui_blocks:253-288,347`；`room_ui_permission:254-265,304-346,358-487,494-515,535-591`；`p10_t7_b:417/433/444` | T-30 / T-22 `enabled` 与「结构不渲染」 | 我们**只改尺寸不改 `enabled`/不改 `if` 条件**。⚠️ 施工红线：`RoomTapTile` 必须原样透传 `enabled`，且**不许**把 `if (gate.can(...))` 改成 `enabled:false` |
| 21,25,29,30,31 | `p12_game_e2e:83-88`；`p12_emoji_b:149-181`；`p10_t7_c:296-300,168-176` | 数量/皮肤/文案/toggle icon | 不删按钮、不动文案（`⚔️ 战斗部署完毕` 属弹层） |

**B 类：等价更新（0 条 —— 本次无需改任何既有断言值）**

| # | 文件:行 | 判定 |
|---|---|---|
| 3,4,5 | `p10_t6:317/340/350` | **保持绿**。§5.4 证明 3/3/3 不变 → 行数 3 ≤ 4 ✅、每行 3 ≥ 2 ✅、战技有同伴 ✅。**若施工把骰子定宽改到 ≥128 而未同步 `maxPerRow`，这三条会红**（这正是证伪链 2） |
| 6 | `p10_t6:356-363` | 保持绿（`Wrap` 不横向溢出；没有改 `Row`/固定宽版） |
| 7 | `p10_t3:268-287` | 保持绿（主组高度 48→40，行数不变 → 工具栏更矮，10 个 key 更不会越界） |
| 8 | `p10_t3:297` | 保持绿（360 档 ~229 − 8；1280 档 ~90 → 仍 `1280 < 360`） |
| 9 | `room_ui_layout:547` | 保持绿（工具栏变矮 → 内容区更高） |
| 10,11 | `room_ui_layout:543/560-563`、`p10_t6:383`、`p10_t3:329` | 保持绿 |
| 12 | `p10_t6:530-538` | 保持绿（`gpScene` 仍 `Wrap`/等分，不越格） |
| 13,14 | `p10_t6:198-199/161/190` | 保持绿（顶栏按钮**不动**） |
| 22,23,24 | `p12_game_e2e:96-115/146-172/68-72` | **不确定 → 先跑**：`takeException()` 是 overflow 总闸门。我们的定宽都留了 ≥4dp 余量，理论不溢；**若红，唯一合法处置 = 把该组 W 上调后重跑，禁止加 `skip`** |
| 27,28,37–44 | 其余 | 保持绿（`RoomGridSpec`/落位表/折叠档一律不动） |

**C 类：新增更强的正向断言（13 条，新文件 `test/p16_button_unify_test.dart`）**

> 这是**本次诉求的正向证据**：不是「没变红」，而是「同一栏位内所有非长按钮尺寸集合恰好等于 {W×H}」。

```dart
// test/p16_button_unify_test.dart（骨架，施工时按实测尺寸回填期望值）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart';
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart';
import 'package:dice_realm/ui/room/widgets/room_button_size.dart';
// …（+ RoomUiFixture / useRoomScreen 沿用既有夹具）

/// ★ 正向判据：把一组按钮的**尺寸集合**与期望集合做精确比较。
///   集合比较 = 同时证明「彼此相等」+「等于规格值」，比 `every(==)` 更强。
void expectUniformSizes(WidgetTester t, String label, List<Key> keys, Size expected) {
  final actual = <Size>{ for (final k in keys) t.getSize(find.byKey(k)) };
  expect(actual, <Size>{expected},
      reason: '$label：同栏位按钮尺寸必须恰好 {${expected.width}×${expected.height}}，'
              '实测 $actual');
}

void main() {
  // T01 · gpToolbar 主组 + 扩展（KP）
  testWidgets('P16-01 工具栏主组 4 个 = 80×40；扩展 KP = 90×40；BGM = 104×40（长按钮）',
      (t) async { /* boot 1280×800 KP；expectUniformSizes(...) */ });

  // T02 · gpDiceBar 8 个 = 90×40（条内 100% 同宽，无例外）
  testWidgets('P16-02 骰子条 8 个按钮全部 90×40', (t) async { ... });

  // T03 · 骰子条切行纯函数：三档行数/每行数（§5.4 的结构性证明落成用例）
  test('P16-03 diceMaxPerRow(348)=3 / (400)=4 / (546)=4；'
       '9 项切行恒为 3/3/3，每行 ≥2', () { ... });

  // T04 · gpKpTools 6 个 = 90×48；上传素材满宽；ConfirmTwice 特殊（不断言等宽）
  testWidgets('P16-04 工具窄栏 6 个 90×48 + 上传素材满宽', (t) async { ... });

  // T05 · gpKpLeft 素材三按钮 48×48（与测试 #15 双向自洽）+ 加怪 90×48
  testWidgets('P16-05 左窄栏素材三按钮 48×48、加怪 90×48', (t) async { ... });

  // T06 · gpScene 8 个全 104×48
  testWidgets('P16-06 场景检定 8 个按钮全 104×48', (t) async { ... });

  // T07 · gpPlScene 技能 chip 高恒 32 且宽 ≥ 90（动态文案例外，见 §1.4②）
  testWidgets('P16-07 玩家场景：chip 高==32 且宽≥90；检定按钮满宽', (t) async { ... });

  // T08 · gpPlCharCard 4 短 = 90×40；2 长 == 同宽（满宽）且相等
  testWidgets('P16-08 角色卡 4 短 90×40、2 长彼此等宽', (t) async { ... });

  // T09 · gpStatus 两按钮等宽等高 + 间距 > 0
  testWidgets('P16-09 状态条 同意/拒绝 尺寸相等且间距 6', (t) async { ... });

  // T10 · gpFeeds trailing 44×32 ×2 + 输入行 48×44 ×3
  testWidgets('P16-10 信息流 trailing 与输入行等宽', (t) async { ... });

  // T11 · gpPriv trailing 44×32 ×2
  testWidgets('P16-11 私密栏 trailing 等宽', (t) async { ... });

  // T12 · 反向总闸门：6 档屏 × 2 角色，整页 takeException == null
  testWidgets('P16-12 全档位零异常（定宽后无 RenderFlex overflow）', (t) async { ... });

  // T13 · 长按钮「满宽」判据：宽 == 所在栏位内容宽（±0.5）
  testWidgets('P16-13 满宽长按钮的宽度恰好等于栏位内容宽', (t) async { ... });
}
```

**D 类：不确定项的处理方式**

| 项 | 处置 |
|---|---|
| `p12_game_e2e:96-115`（遍历点所有 RoomTap） | **先跑**。若红，先看是哪个按钮的 overflow，回 §1.4 调 W；**禁止** `findsWidgets`/`skip`/删用例 |
| `p10_t6:530-538`、`p10_t6:551` | 先跑；红则说明 `gpScene` 等分宽不足 → 把 104 上调（当前余量 20.5，几乎不可能红） |
| `p10_t3:268-287` | 先跑；理论更绿（工具栏变矮）。若红，优先怀疑「骰子条因定宽多出一行」→ 查 `maxPerRow` 是否同步 |

**E 类：注释/文档级更新（2 处，非断言）**

1. `p10_t6_layout_test.dart:311-312` 注释「13 个按钮宽 48~98dp」→ 改为「9 项，宽 68~90dp」（纯注释）。
2. `gp_dice_bar.dart:99-105` 的 `_balancedRows` 文档注释里「13 个 → 4/3/3/3」→ 补一句「当前实际 9 项（P10-7 收起 D4–D20 后），per ∈ {3,4} 时恒为 3/3/3」。

---

## 8. 反向证伪方案（证明新断言真能抓回归）

### 链 1：栏位内等宽断言能抓住「某个按钮被改回旧尺寸」

| 步骤 | 操作 | 预期 |
|---|---|---|
| 1 | 记录基线：`flutter test` 全量 → 0 red | 绿 |
| 2 | 独占窗口下把 `gp_kp_tools.dart` 里 `标点` 的 `RoomTapTile(size: RoomBtnSize.toolsTile)` 改回裸 `RoomTap(label:'标点', icon: Icons.place, ...)`（等价于旧 73 宽） | **仅 `P16-04` 红**：`尺寸集合 = {Size(90,48), Size(73,48)}`，期望 `{Size(90,48)}`。其余 12 条新用例 + 全部既有用例绿 |
| 3 | 恢复 | 13/13 全绿 |

**预期红/绿条数**：红 1（P16-04），绿 其余全部（含 44 条既有）。
**关键**：若这一步**不红**，说明新断言是「恒真」的假证据 → 必须重写断言（不许保留）。

### 链 2：骰子条切行回归能被抓住

| 步骤 | 操作 | 预期 |
|---|---|---|
| 1 | 基线绿 | 绿 |
| 2 | 把 `kDiceTileW` 从 `90` 改成 **`132`**（模拟「统一宽改大」）**且不同步 `maxPerRow`** | **红 2 条**：① `p10_t6:317` `_rowCount(rects) ≤ 4` 失败（每行 `Wrap` 只能装 `3×132+6 = 402 > 392` → 实际 1~2 个/行 → 真实行数 ≈ 6~7）；② `P16-02` 尺寸集合 ≠ `{90×40}` |
| 3 | 恢复 | 全绿 |
| 4 | 把 `kDiceTileW` 改回 `88` 但**保留**新除数 `(W+3)` → 断言仍绿 | 说明「符号化」本身不改变行为（预期绿，用于证明改动的**行为等价性**） |

**预期红/绿条数**：红 2（`p10_t6` B1 + `P16-02`），绿 其余。

### 证伪纪律（硬要求）

> ⚠️ **本工程目录不是 git 仓库**（`git status` 报 `not a git repository`）⇒ 不能用 `git checkout` 恢复。必须用「字节级备份 + 校验和」：

1. **独占窗口**：证伪期间不许任何其他 worker 写 `lib/`、`test/`。
2. **先备份被改文件（改之前，不是改之后）**：
   ```bash
   mkdir -p _p16_bak
   cp lib/ui/room/widgets/gp_dice_bar.dart   _p16_bak/gp_dice_bar.dart
   cp lib/ui/room/widgets/gp_kp_tools.dart   _p16_bak/gp_kp_tools.dart
   md5sum _p16_bak/*.dart > _p16_bak/md5.before
   ```
3. **逐字节恢复 + 校验**：
   ```bash
   cp _p16_bak/gp_dice_bar.dart lib/ui/room/widgets/gp_dice_bar.dart
   cp _p16_bak/gp_kp_tools.dart lib/ui/room/widgets/gp_kp_tools.dart
   md5sum -c _p16_bak/md5.before      # 必须两行 OK
   ```
4. **每条链都要贴「红的那条 reason 原文」**，否则证据无效。
5. 恢复后必须**再跑一次全量**并贴绿；证伪结束删除 `_p16_bak/`（不许留在仓库里）。

---

## 9. 有序任务列表

### 推荐：**1 个 worker 串行做全部**（不拆）

| 依据 | 说明 |
|---|---|
| 共享常量文件 | 所有栏位都 import 新的 `room_button_size.dart` → 拆 2 人会撞同一文件 |
| 同一套高度口径 | 工具栏 40 / 面板 48 的裁决是一次判断，两处落地必须同一人保持口径 |
| 回归成本 | 每次改动都要跑 `p10_t3 / p10_t6 / p10_t7 / p12 / room_ui` 五组；拆 2 人 = 双份 + 合并冲突 |
| 体量 | 10 个文件、每处 1~3 行 `minSize` + 2 处 `Wrap→RoomTapEqualRow` + 1 处 `Align→SizedBox` |

> 若主理人为赶时间必须并行，**唯一安全的切法**见文末「附 D」，但需接受 `T01` 的硬等待。

| ID | 任务 | 源文件 | 依赖 | 优先级 |
|---|---|---|---|---|
| **T01** | **新增尺寸族与两个包装件**（`RoomBtnSize` / `RoomTapTile` / `RoomTapEqualRow`），零改动 `RoomTap`/`ConfirmTwice` | `lib/ui/room/widgets/room_button_size.dart`(新) | — | **P0** |
| **T02** | **工具栏视觉系统**：主组 4 个 → `80×40`；扩展 KP/更多工具 → `90×40`，BGM 保持 `104×40`；**`hint` 文案逐字保留**、`quickRow` 仍是 `Wrap` | `lib/ui/room/widgets/gp_toolbar.dart`、`lib/ui/room/room_game_page.dart`(仅 `_buildToolbar` 的三个 `minSize`) | T01 | **P0** |
| **T03** | **骰子条**：8 个 → `90×40`（含 `其他骰子` 88→90）；抽出纯函数 `diceMaxPerRow` / `diceBalancedRowSizes`，除数改为 `kDiceTileW + kDiceTileGap`，**`clamp(2,4)` 保持不变** | `lib/ui/room/widgets/gp_dice_bar.dart` | T01 | **P0** |
| **T04** | **KP 两栏**：`gpKpTools` 6 个 → `90×48` 2 列网格 + 上传素材满宽（`Align→SizedBox(width:infinity)`）；`gpKpLeft` 加怪 `90×48`、上传满宽、**素材三按钮与移除保持 48×48** | `lib/ui/room/widgets/gp_kp_tools.dart`、`lib/ui/room/widgets/gp_kp_left.dart` | T01,T02(常量已定) | **P0** |
| **T05** | **场景两栏 + 角色卡**：`gpScene` 8 个 → `104×48`（`RoomTapEqualRow(2)`）；`gpPlScene` chip `minSize 90×32` + 检定按钮满宽；`gpPlCharCard` 4 短 `90×40` 2 列 + 2 长满宽 | `lib/ui/room/widgets/gp_scene_check_kp.dart`、`gp_scene_check_pl.dart`、`gp_pl_char_card.dart` | T01 | **P1** |
| **T06** | **信息流 / 私密 / 状态**：trailing `44×32`×2（两处）；输入行 3 个 `48×44`；`gpStatus` 加 6dp 间距 | `lib/ui/room/widgets/gp_feeds.dart`、`gp_privates.dart`、`gp_status.dart` | T01 | **P1** |
| **T07** | **新增正向断言 13 条 + 证伪链 1/2 + 全量回归** | `test/p16_button_unify_test.dart`(新)、`p10_t6` 注释 1 处 | T02–T06 | **P0** |

> **铁律**：T02–T06 每一步**只改尺寸/排布**，不碰 `enabled`、不碰 `if (gate.can(...))`、不碰 `Key`、不碰文案、不碰 `roomDockMinWidthOf`、不碰 `RoomGridSpec`、不碰 `kToolbarMaxShare`、不碰 `lib/ui/room/sheets/**`。

---

## 10. 风险与待明确

### 10.1 最可能翻车的 5 处（按概率×影响排序）

| # | 风险 | 触发条件 | 影响 | 缓解 |
|---|---|---|---|---|
| 1 | **文案宽度估算偏差**（模型见 §1.4） | 实测汉字 advance > 13.0（不同字体/`textScaleFactor`） | 定宽 < 内容 → **RenderFlex overflow** → `p12_game_e2e` 6 档 + `p10_t6:551` 一起红 | 每组留 ≥4dp 余量；**T07 第一件事就是跑 `P16-12` 零异常**；超了就上调 W 并同步新测试期望值（等价更新，不动既有断言） |
| 2 | **`其他骰子`/`更多工具` 的 86 估算** | 若实测 88~90 | `90×40` 定宽被撑破 | 这两个是唯一「紧边界」，施工时先单独量（`getSize`）再定；必要时 `kDiceTileW` 上到 96（此时 `(392-16)/99 = 3.79 → 3` → 仍 3 行，行数不变） |
| 3 | **`gpScene` 等分宽度** | 若某档实际栏宽 < 232 | 104 放不下 2 个 → 等分后 1 个/行 → `P16-06` 与「不孤行」类断言红 | 104 的余量 20.5（内容 83.5）很厚；若仍红，退回 `Wrap` + 定宽 104（不强制 2 列） |
| 4 | **误改 `trailing`/`SectionBox`** | 有人顺手把 `Row` 改 `Flexible` | 12 个栏位标题行一起变，`takeException` 全组红 | 规格 §6 明确「不动」；code review 只看 `room_panel_kit.dart` 是否 0 diff（除新增两个类在**新文件**里） |
| 5 | **顺手改文案** | 为了塞进定宽去缩短 `下一个行动 ▶`/`更多工具` | `find.text` 6 处红，且违反「不改文案」 | 规格硬禁；字面文案清单见 §7 A 类 #19 |

### 10.2 需要主理人 / 用户拍板的问题

| # | 问题 | 我的建议 | 若不拍板的默认 |
|---|---|---|---|
| Q1 | **工具栏 40 / 面板 48 的双档**，用户是否接受（他要的是「同一栏位相同」，我们已满足，但跨区仍不同高） | **接受**（§4 已论证全局 48 有 `kToolbarMaxShare` 风险且无收益） | 按双档执行 |
| Q2 | `gpPlScene` 的技能 chip **无法严格等宽**（技能名长度来自角色卡数据） | 接受「min 90 宽 + 高恒 32 + 超长名自适应」，并在验收话术里说明 | 按 §2 执行 |
| Q3 | `gpCombat` 的 `下一个行动 ▶`(115.5) 与 `＋加入`(80) **保持不等宽** | 接受（这是用户规则里「比其他的都长的按钮就让它特殊」的典型） | 宽度不动，只保留统一高度 32 |
| Q4 | `gpMapStage` / `gpFeeds` 行尾 / `gpPlNotes` 行尾**保持小尺寸** | 接受（浮层/行内控件 ≠ 按钮组，§3 已给用户话术） | 保持原样 |
| Q5 | 是否顺带把 `ConfirmTwice` 加一个可选 `minSize` 参数（消除「按下变宽」的跳变） | **本批不做**（P2 备选）。做法：`ConfirmTwice({... this.minSize})` → 透传给内部 `RoomTap`，默认 `null` = 今日行为，零回归；再在三个调用点传 `Size(116, 48)`（≥ `再点一次清除` 的 112） | 不做，列为下一批 |

---

## 附 A：文案宽度估算表（施工校准用）

| 按钮 | 文案 | 图标 | 内容宽（估算） | 落入组 | 组定宽 | 余量 |
|---|---|---|---|---|---|---|
| zoomPercent | `100%` | Icon | 64.6 | toolbar 主组 | 80 | +15.4 |
| zoomReset | — | Icon | 30 | toolbar 主组 | 80 | +50 |
| round.next | `下一轮` | Icon | 73 | toolbar 主组 | 80 | +7 |
| scene.mode | `转战斗` | Icon | 73 | toolbar 主组 | 80 | +7 |
| dice bonus | `奖励 5` | Icon | 70.7 | dice | 90 | +19.3 |
| dice penalty | `惩罚 5` | Icon | 70.7 | dice | 90 | +19.3 |
| D100 | `D100` | png | 60.8 | dice | 90 | +29.2 |
| **其他骰子** | `其他骰子` | Icon | **86** | dice | 90 | **+4 ⚠️最紧** |
| rollCustom | — | Icon | 30 | dice | 90 | +60 |
| dark | `暗骰开` | Icon | 73 | dice | 90 | +17 |
| combat.roll | `战技` | Icon | 60 | dice | 90 | +30 |
| check.opposed | `对抗` | Icon | 60 | dice | 90 | +30 |
| KP | `KP` | Icon | 51 | 扩展 | 90 | +39 |
| **更多工具** | `更多工具` | Icon | **86** | 扩展 | 90 | **+4 ⚠️最紧** |
| BGM 场景 | `BGM 场景` | Icon | 88.5 | 扩展 | **104（特殊）** | +15.5 |
| 上传素材 | `上传素材` | Icon | 86 | 满宽 | ≥172 | 大 |
| 加怪 | `加怪` | Icon | 60 | tools | 90 | +30 |
| 标点/画笔/橡皮 | 2 字 | Icon | 73 | tools | 90 | +17 |
| 放单位/放玩家 | 3 字 | Icon | 73 | tools | 90 | +17 |
| 大成功(5) | | — | 83.5 | scene | 104 | +20.5 |
| 极难/困难成功(4/3) | | — | 83.5 | scene | 104 | +20.5 |
| 成功(2)/失败(0) | | — | 57.5 | scene | 104 | +46.5 |
| 大失败(-1) | | — | 76.2 | scene | 104 | +27.8 |
| 快速推送 | 4 字 | Icon | 86 | scene | 104 | +18 |
| 检定编辑器 | 5 字 | Icon | 99 | scene | 104 | +5 |
| 状态管理 | 4 字 | Icon | 86 | charCard | 90 | +4 ⚠️ |
| 急救/物品 | 2 字 | Icon | 60 | charCard | 90 | +30 |
| AI RP | | Icon | 73.5 | charCard | 90 | +16.5 |
| 保存到已保存 | 6 字 | Icon | 112 | 满宽 | ≥202 | 大 |
| 推进 1 轮 | | Icon | ~75 | 满宽 | ≥202 | 大 |
| 素材 公开/封面/删除 | 2 字 | — | 38 | assets | **48（测试钉死）** | +10 |
| 同意/拒绝 | 2 字 | Icon | 60 | status | 56（现状） | −4 ⚠️ **现状即已撑到 60** |

> ⚠️ 最后一行是**审计未发现的事实**：`gpStatus` 的 `同意`+`close` 图标内容宽约 60 > 声明 56 ⇒ 实际是 60×36。若两条断言要用「尺寸集合相等」，先实测（`getSize`）再写期望值；或者把 `minSize` 提到 60 让两个按钮同宽（等价更新，风险极低，建议采用）。

## 附 B：新增常量/接口清单（供 T01 直接落码）

```
lib/ui/room/widgets/room_button_size.dart   （新文件，~90 行）
  class RoomBtnSize                          // 尺寸族唯一真源（10 个 const）
  class RoomTapTile extends StatelessWidget   // SizedBox 紧约束 + RoomTap（透传 enabled/key）
  class RoomTapEqualRow extends StatelessWidget // Row + Expanded 等分
  Widget roomTapWrap2(List<Widget> tiles)     // 2 列网格（Wrap + 定宽，自动换行）
```

**不新增**：任何 `RoomTheme` 常量（避免动 `room_theme.dart`）、任何 `RoomSlot`/`RoomKeys` 成员、任何 `roomDockMinWidthOf` 数值。

## 附 C：施工自检清单（T07 逐项打勾）

1. `grep -c "RoomTap(" lib/ui/room/widgets/room_panel_kit.dart` 仍 = 1（只有构造函数声明）→ 证明 `RoomTap` 类体未改。
2. `lib/ui/room/widgets/room_panel_kit.dart` 的**修改时间与字节数**与改动前一致（该工程无 git，用 `md5sum` 记录；**结论要求：此文件 0 字节变更**）。
3. `lib/ui/room/sheets/` 下所有文件 `md5sum` 与改动前一致（**0 字节变更**）。
4. `grep -n "roomDockMinWidthOf\|kToolbarMaxShare\|kRoomSidePadding\|roomBlockGap" -r lib/ | wc -l` 与改前一致。
5. `gp_toolbar.dart` 仍含 `'点按切换缩放档位` 与 `Wrap(`、不含 `zoomLabel`（`p10_t5:401-404`）。
6. `gp_toolbar.dart` 的 `quickRow` 仍是 `Wrap`（`p10_t5:387`）。
7. 所有 `RoomKeys.action(op)` 的 `enabled` 仍**恰好** `gate.can(op)`（T-30 `:358-487`）。
8. 未新增任何 `if (can...)`/`else` 分支（按钮数量不变）。
9. `p16_button_unify_test.dart` 的证伪链 1、2 各贴出「红的那条 reason 原文」。
10. 全量绿（含 `p10_t3 / p10_t5 / p10_t6 / p10_t7 / p12_game_e2e / room_ui_*`）。

## 附 D：若必须并行（2 worker）的唯一安全切法

| worker | 文件集（**互不重叠**） | 前置 |
|---|---|---|
| **A** | `room_button_size.dart`(新,仅 A 建) + `gp_toolbar.dart` + `gp_dice_bar.dart` + `room_game_page.dart`(`_buildToolbar`) + `test/p16_a_toolbar_test.dart`(新) | — |
| **B** | `gp_kp_tools.dart` + `gp_kp_left.dart` + `gp_scene_check_kp.dart` + `gp_scene_check_pl.dart` + `gp_pl_char_card.dart` + `gp_feeds.dart` + `gp_privates.dart` + `gp_status.dart` + `test/p16_b_panels_test.dart`(新) | **blockedBy A 的 `room_button_size.dart` 落地**（B 只读该文件，不再写） |

不重叠证据：A 的 4 个源文件与 B 的 8 个源文件**交集为空**；测试文件按 `_a_`/`_b_` 分文件（不共写同一测试文件）；`room_panel_kit.dart`、`room_layout.dart`、`lib/ui/room/sheets/**` 两侧都**只读**。
