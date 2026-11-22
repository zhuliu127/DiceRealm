# P16 按钮尺寸统一 · 现状审计（只读，未改任何源码）

- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`（v2.27.0+97）
- 审计范围：`lib/ui/room/widgets/*.dart`（19 个含按钮的 widget）+ `lib/ui/room/sheets/*.dart`（17 个弹层，单独归类）+ `lib/ui/room/room_game_page.dart`（工具栏扩展 3 个按钮）
- 方法：grep / read 全文，未运行 `flutter test` / `build`
- 口径说明：`grep -c "RoomTap("` 会命中 `room_panel_kit.dart:155` 的**构造函数声明**，故 widgets 的 68 条命中里有 1 条是声明，实际调用点 **67** 条；渲染后按钮数还要加上循环生成（KP 场景 6 档、玩家技能 N 个）与 `ConfirmTwice` / `FoldHeader` 内部各 1 个。

## 0. 关键数字（先看这 6 行）

| 指标 | 数值 | 出处 |
|---|---|---|
| 槽位总数 | KP 12 / 玩家(含旁观) 13 | `room_keys.dart:99-130` |
| `RoomTap` 源码调用点 | **128**（widgets 68 / sheets 60） | 见 §2、§2.9 |
| 其中位于「栏位」内 | **67**（widgets）+ 3（工具栏扩展）= 70 | §2 |
| 渲染后实际按钮数（KP 首屏） | ≈ 80–90（含循环 + ConfirmTwice + 数据行） | §1 |
| 不同 `minSize` 取值 | **42 种**；高度 9 档（26/30/32/34/36/38/40/42/44） | `grep "Size("` |
| 「长按钮 / 主操作」 | **10 个**（另有 4 个弱判定） | §2 各行 |

> 没有任何「统一宽度」机制存在：全工程只有 `RoomTheme.tapMinSize = 48` 一个尺寸常量（`room_theme.dart:25`），宽度完全由 label 字符数决定。

---

## 1. 槽位 → widget 映射

### 1.1 KP 视角（`RoomKeys.kpSlots`，`room_keys.dart:99-112`）

| # | slot id | 中文标题（`room_game_page.dart:139-186`） | 渲染 widget | `RoomTap` 源码点数 | 渲染后可点数（含循环/复用） |
|---|---|---|---|---|---|
| 1 | `gpTopbar` | 顶栏 | `gp_topbar.dart` | 1 | 1 |
| 2 | `gpKpLeft` | 左窄栏（成员 / 怪物） | `gp_kp_left.dart` | 6 | 6 + 2×ConfirmTwice |
| 3 | `gpKpTools` | 工具窄栏 | `gp_kp_tools.dart` | 7 | 7 + 1×ConfirmTwice |
| 4 | `gpMap` | 素材舞台 | `gp_map_stage.dart` | 4 | 4（`showControls:true`） |
| 5 | `gpScene` | 场景 | `gp_scene_check_kp.dart` | 3 | **8**（等级 ×6 + 2） |
| 6 | `gpCombat` | 战斗 | `gp_combat_list.dart` | 3 | 2 + 2×待确认卡 |
| 7 | `gpPlayers` | 玩家 / 队友 | `gp_kp_players.dart` | 2 | 2 × 成员数 |
| 8 | `gpChat` | 聊天 | `gp_feeds.dart`（`pane: chat`） | 7 | 3 + 2×检定行 + 3（输入行） |
| 9 | `gpLog` | 记录 | `gp_feeds.dart`（`pane: record`） | 同 7 | 4 + 2×检定行 |
| 10 | `gpPriv` | 私密栏 | `gp_privates.dart` | 2 | 2 |
| 11 | `gpToolbar` | 工具栏 | `gp_toolbar.dart`(4) + `gp_dice_bar.dart`(8) + `room_game_page.dart`(2) | 14 | **14 + 1**（KP 多 BGM） |
| 12 | `gpStatus` | 状态条 | `gp_status.dart` | 2 | 2 × 待办条数 |

### 1.2 玩家 / 旁观视角（`RoomKeys.plSlots`，`room_keys.dart:116-130`）

| # | slot id | 中文标题 | 渲染 widget | `RoomTap` 点数 | 与 KP 的差异 |
|---|---|---|---|---|---|
| 1 | `gpTopbar` | 顶栏 | `gp_topbar.dart` | 1 | 同 |
| 2 | `gpPlCharCard` | 我的角色卡 | `gp_pl_char_card.dart` | 7 | KP 无此块 |
| 3 | `gpPlMap` | 素材舞台 | `gp_map_stage.dart`（`readOnly:true`） | 4 | 只撤销/复位/放大/全屏 |
| 4 | `gpPlChat` | 聊天 | `gp_feeds.dart` | 3 + 3 | 同 |
| 5 | `gpPlLog` | 记录 | `gp_feeds.dart` | 4 | 同 |
| 6 | `gpPlCombat` | 战斗 | `gp_combat_list.dart` | 0（`trailing:null`） | **玩家侧结构上不渲染**（T-22） |
| 7 | `gpPlScene` | 场景 | `gp_scene_check_pl.dart` | 2 | 技能 N 个 + 1 个检定 |
| 8 | `gpPlMates` | 队友 | `gp_pl_mates.dart` | 1 | KP 无 |
| 9 | `gpPriv` | 私密栏 | `gp_privates.dart` | 2 | 同 |
| 10 | `gpPlSketch` | 手绘板 | `gp_pl_sketch.dart` | 2 + 1×ConfirmTwice | KP 无 |
| 11 | `gpPlNotes` | 笔记 | `gp_pl_notes.dart` | 2 | KP 无 |
| 12 | `gpToolbar` | 工具栏 | 同 KP（扩展换成「更多工具」） | 13 | 少 BGM |
| 13 | `gpStatus` | 状态条 | `gp_status.dart` | 2 | 同 |

> `gpCombatStrip`（`gp_combat_strip.dart`）是块 6 的**附属条**，不单列，内部 **0 个 RoomTap**（纯展示槽位，宽度固定 104，`gp_combat_strip.dart:149`）。

---

## 2. 按钮清单（逐处 `RoomTap`）

列含义：`minSize` 列的「默认」= 未显式传值 → `Size(48,48)`（`room_panel_kit.dart:163`）；括号内为按 13px 字号 + 6dp 左右 padding 估算的**实际宽度**。

### 2.1 `gp_toolbar.dart`（槽位 gpToolbar，4 个）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_toolbar.dart:112` | icon `zoom_out_map` + `100%` | 默认（≈64 宽） | `Wrap(quickRow)`→`Padding`→`SingleChildScrollView`→`DecoratedBox`→`Material` | 否 | 否 |
| `gp_toolbar.dart:119` | icon `center_focus_strong`（无 label） | 默认 48×48 | 同上 | 否 | 否 |
| `gp_toolbar.dart:126` | icon `skip_next` + `下一轮` | 默认（≈73×48） | 同上 | 否 | 否 |
| `gp_toolbar.dart:134` | icon `swap_horiz` + `转战斗`/`转探索` | 默认（≈73×48） | 同上 | 否 | 否（两态等宽，安全） |

### 2.2 `gp_dice_bar.dart`（槽位 gpToolbar，9 个 / 条内 8）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_dice_bar.dart:182` | icon `add_circle_outline` + `奖励 N` | **52×40** | 窄档 `Column(stretch)`→`Padding`→`Wrap`；宽档单 `Wrap` | 否 | 否 |
| `gp_dice_bar.dart:191` | icon `remove_circle_outline` + `惩罚 N` | **52×40** | 同上 | 否 | 否 |
| `gp_dice_bar.dart:204` | png `dice/d100` + `D100` | **48×40** | 同上 | 否 | 否 |
| `gp_dice_bar.dart:213` | icon `casino_outlined` + `其他骰子` | **88×40** | 同上 | 否 | **是**（条内唯一 88 宽） |
| `gp_dice_bar.dart:244` | icon `casino`（无 label） | **48×40** | 同上 | 否 | 否 |
| `gp_dice_bar.dart:252` | icon `visibility_off_outlined` + `暗骰开/关` | **64×40** | 同上 | 否 | 否 |
| `gp_dice_bar.dart:279` | icon `gavel` + `战技` | **56×40** | 同上（`if gate.can`） | 否 | 否 |
| `gp_dice_bar.dart:300` | icon `compare_arrows` + `对抗` | **56×40** | 同上（`if gate.can`） | 否 | 否 |
| `gp_dice_bar.dart:407` | png `dice/d4..d20` + `D4..D20`（**弹层内** 6 个） | **64×40** | `Dialog`→`Wrap` | 否 | 否 |

**布局意图**：`LayoutBuilder`（`:316`）以 600dp 为界分两档（`_kGroupBelowWidth`, `:48`）；窄档用 `_balancedRows()`（`:106`）**显式**把 13 个按钮切成 4/3/3/3，每行一个 `Wrap`；宽档退回单 `Wrap` 一行流。`maxPerRow` 是**硬编码**的 `((outer.maxWidth - 16) / 88).floor().clamp(2, 4)`（`:348`）——88 是「按钮平均宽」的魔数，**改按钮宽度必须同步改它**，否则均衡切行立刻失效。

### 2.3 `gp_kp_tools.dart`（槽位 gpKpTools，7 + 1）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_kp_tools.dart:433` | `加怪` + `add` | 默认 48×48 | `Align(centerLeft)`（**独占一行**） | 否（Align 不拉伸 child） | 否 |
| `gp_kp_tools.dart:472` | `标点` + `place` | 默认（≈73×48） | `Wrap(spacing:4)` | 否 | 否 |
| `gp_kp_tools.dart:483` | `画笔` + `brush` | 默认（≈73×48） | 同上 | 否 | 否 |
| `gp_kp_tools.dart:491` | `橡皮` + `backspace` | 默认（≈73×48） | 同上 | 否 | 否 |
| `gp_kp_tools.dart:503` | `放单位` + `person_pin` | 默认（≈86×48） | 同上 | 否 | 否 |
| `gp_kp_tools.dart:518` | `放玩家` + `person_add` | 默认（≈86×48） | 同上 | 否 | 否 |
| `gp_kp_tools.dart:533`（`ConfirmTwice`→`room_panel_kit.dart:545`） | `清除笔迹` / `再点一次清除` + `warning_amber` | 默认（≈73 / ≈112） | 同上 `Wrap` | 否 | **弱**（2 字 vs 4–6 字，且按下会变宽） |
| `gp_kp_tools.dart:584` | `上传素材` + `upload_file` | 默认（≈99×48） | `Align(centerLeft)`（独占一行） | 否 | **弱** |

**布局意图**：`SectionBox` 的 `Column(crossAxisAlignment: stretch)`（`room_panel_kit.dart:76`）里依次是「表单 Wrap → Align(加怪) → 文字计数 → Wrap(5 工具) → Wrap(5 色 ActionChip) → Align(上传)」。**加怪 / 上传素材用 `Align` 单独一行**，是为了让它们不参与上面的 `Wrap` 流（历史原因：它们语义不同）；副作用就是**这两行只有 1 个按钮、且宽高与下面 Wrap 里的按钮完全不是一套尺寸**。

### 2.4 `gp_kp_left.dart`（槽位 gpKpLeft，6 + 2）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_kp_left.dart:177` | `加怪` + `add` | 默认 48×48 | `Align(centerLeft)` | 否 | 否 |
| `gp_kp_left.dart:206` | `移除`（纯文字） | 默认 48×48 | `Row[Expanded(Text), RoomTap]` | 否（是 Text 被拉伸） | 否 |
| `gp_kp_left.dart:309` | `上传素材` + `upload_file` | 默认（≈99×48） | `Align(centerLeft)` | 否 | **弱** |
| `gp_kp_left.dart:364` | `公开`/`隐藏`（纯文字，动态 2 字） | 默认 48×48 | `Wrap(spacing:2)` | 否 | 否 |
| `gp_kp_left.dart:377` | `封面` | 默认 48×48 | 同上 | 否 | 否 |
| `gp_kp_left.dart:387` | `删除` | 默认 48×48 | 同上 | 否 | 否 |
| `gp_kp_left.dart:134`（`ConfirmTwice`） | `清除笔迹与标记` / `再点一次清除` | 默认（≈124 / ≈112） | `Align(centerLeft)` | 否 | **是**（7 字） |

> 素材行的三个按钮（公开/封面/删除）是**唯一被测试钉死「宽 ≥48 且高 ≥48」的按钮组**，见 §4 第 15 条。

### 2.5 `gp_map_stage.dart`（槽位 gpMap / gpPlMap，4 个）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_map_stage.dart:344` | icon `remove` | **36×32** | `Positioned(right:4,bottom:4)`→`Row` | 否 | 否 |
| `gp_map_stage.dart:351` | icon `center_focus_strong` | **36×32** | 同上 | 否 | 否 |
| `gp_map_stage.dart:358` | icon `add` | **36×32** | 同上 | 否 | 否 |
| `gp_map_stage.dart:365` | icon `fullscreen` | **36×32** | 同上 | 否 | 否 |

**布局意图**：4 个纯图标按钮浮在舞台右下角（`Row` 无 spacing，天然等宽 36），是全页面**唯一已经整齐**的一组。

### 2.6 `gp_scene_check_kp.dart`（槽位 gpScene，3 → 渲染 8）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_scene_check_kp.dart:135` | `大成功(5)`…`大失败(-1)`（**循环 6 个**，`kKpSceneLevels` `:37`） | 默认（≈84×48） | `Wrap(spacing:4)` | 否 | 否 |
| `gp_scene_check_kp.dart:158` | `快速推送` + `send` | 默认（≈99×48） | 第二个 `Wrap(spacing:4)` | 否 | 否 |
| `gp_scene_check_kp.dart:173` | `检定编辑器` + `edit` | 默认（≈112×48） | 同上 | 否 | 否 |

### 2.7 `gp_scene_check_pl.dart`（槽位 gpPlScene，2 → 渲染 N+1）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_scene_check_pl.dart:132` | `${技能名} ${值}`（循环，≤6 个） | **72×32** | `Wrap(spacing:4)` | 否 | 否 |
| `gp_scene_check_pl.dart:144` | `用我的技能检定` / `用「X」检定`（动态名字） | **140×40** | `Align(centerLeft)` | 否 | **是**（且宽度随技能名变化） |

### 2.8 `gp_combat_list.dart`（槽位 gpCombat / gpPlCombat，3）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_combat_list.dart:123` | `下一个行动 ▶` + `play_arrow` | **96×32** | `SectionBox.trailing`→`Wrap(spacing:4)` | 否 | **是** |
| `gp_combat_list.dart:134` | `＋加入` + `person_add_alt` | **80×32** | 同上 | 否 | 否 |
| `gp_combat_list.dart:329` | `加入` + `add`（弹层 body 每行） | **72×40** | `Row[Expanded(Text), RoomTap]` | 否 | 否 |
| （间接）`gp_status.dart:86/94` | `同意`/`拒绝` | **56×36** | `Row`（无 spacing） | 否 | 否 |

### 2.9 `gp_kp_players.dart`（槽位 gpPlayers，2 × 成员数）

| 文件:行 | label | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_kp_players.dart:139` | `详情` | 默认 48×48 | `Row[Avatar, SizedBox(8), Expanded(Text), RoomTap]` | 否 | 否 |
| `gp_kp_players.dart:171` | `全屏` + `fullscreen` | 默认（≈73×48） | `Row[Expanded(Text), RoomTap]` | 否 | 否 |

### 2.10 `gp_feeds.dart`（槽位 gpChat / gpLog / gpPlChat / gpPlLog，7）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_feeds.dart:241` | `花 N 点幸运…` + `auto_fix_high` | **132×30** | 检定行的 `Wrap(spacing:6)`（在 `FeedList` 行内） | 否 | **是**（且 30 高，低于 48 热区） |
| `gp_feeds.dart:253` | `推动` + `refresh` | **132×30** | 同上 | 否 | 否 |
| `gp_feeds.dart:315` | `新`（纯文字） | **40×32** | `SectionBox.trailing`→`Row` | 否 | 否 |
| `gp_feeds.dart:322` | icon `fullscreen` | **44×32** | 同上 | 否 | 否 |
| `gp_feeds.dart:783` | icon `auto_awesome`（AI RP） | **48×44** | `Row[Expanded(TextField), …]`（`ChatInputRow`） | 否 | 否 |
| `gp_feeds.dart:801` | icon `open_in_full` | **44×44** | 同上 | 否 | 否 |
| `gp_feeds.dart:808` | icon `send` | **48×44** | 同上 | 否 | 否 |

### 2.11 `gp_privates.dart`（槽位 gpPriv，2）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_privates.dart:159` | `新` | **40×32** | `SectionBox.trailing`→`Row` | 否 | 否 |
| `gp_privates.dart:166` | icon `fullscreen` | **44×32** | 同上 | 否 | 否 |

### 2.12 `gp_status.dart`（槽位 gpStatus，2 × 卡片数）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_status.dart:86` | `同意` + `check` | **56×36** | `Row`（两张卡之间 **0 spacing**） | 否 | 否 |
| `gp_status.dart:94` | `拒绝` + `close` | **56×36** | 同上 | 否 | 否 |

### 2.13 `gp_pl_char_card.dart`（槽位 gpPlCharCard，7）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_pl_char_card.dart:116` | icon `fullscreen` | **44×32** | `SectionBox.trailing` | 否 | 否 |
| `gp_pl_char_card.dart:228` | `状态管理` + `edit_note` | **84×40** | `Wrap(spacing:4)` | 否 | 否 |
| `gp_pl_char_card.dart:238` | `急救` + `healing` | **64×40** | 同上 | 否 | 否 |
| `gp_pl_char_card.dart:253` | `物品` + `backpack_outlined` | **64×40** | 同上 | 否 | 否 |
| `gp_pl_char_card.dart:265` | `AI RP` + `auto_awesome` | **64×40** | 同上 | 否 | 否 |
| `gp_pl_char_card.dart:307` | `保存到已保存` + `save_outlined` | **128×40** | `Padding`→`Align(centerLeft)`（独占一行） | 否 | **是** |
| `gp_pl_char_card.dart:333` | `⏩ 推进 1 轮` + `skip_next` | **112×40** | `Padding`→`Align(centerLeft)`（独占一行） | 否 | **是** |

### 2.14 `gp_pl_sketch.dart`（槽位 gpPlSketch，2 + 1）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_pl_sketch.dart:212` | `笔` + `edit` | **48×32** | `Row`（后接 `Expanded(Text)`） | 否 | 否 |
| `gp_pl_sketch.dart:220` | `擦` + `auto_fix_normal` | **48×32** | 同上 | 否 | 否 |
| `gp_pl_sketch.dart:196`（`ConfirmTwice`） | `清空` / `再点一次确认` | 默认 | `SectionBox.trailing` | 否 | 否 |

### 2.15 `gp_pl_notes.dart`（槽位 gpPlNotes，2）

| 文件:行 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|
| `gp_pl_notes.dart:111` | icon `add` | **48×44** | `Row[Expanded(TextField), RoomTap]` | 否 | 否 |
| `gp_pl_notes.dart:145` | icon `delete_outline` | **36×30** | `Row[Expanded(Text), RoomTap]`（每行） | 否 | 否 |

### 2.16 其余（各 1 个）

| 文件:行 | 槽位 | label / icon | minSize | 外层容器 | 被 Expanded? | 长按钮 |
|---|---|---|---|---|---|---|
| `gp_pl_mates.dart:68` | gpPlMates | icon `expand_more/less` | **44×32** | `SectionBox.trailing` | 否 | 否 |
| `gp_topbar.dart:312` | gpTopbar | icon `visibility_outlined` + 观众数 | **56×32** | `Row`（一行流中的胶囊） | 否 | 否 |
| `room_layout.dart:425` | 折叠档方块 | icon `unfold_more` | **30×26** | `Stack`→`Positioned(right:0,top:0)` | 否 | 否 |
| `room_game_page.dart:763` | gpToolbar | `KP` + `tune` | **56×40** | `Wrap(extensions)` | 否 | 否 |
| `room_game_page.dart:772` | gpToolbar | `BGM 场景` + `library_music_outlined` | **104×40** | 同上 | 否 | **是** |
| `room_game_page.dart:782` | gpToolbar | `更多工具` + `more_horiz` | **96×40** | 同上 | 否 | **是** |

### 2.17 弹层（`lib/ui/room/sheets/*.dart`，60 处，**单独归类**）

弹层不是「栏位」，统一尺寸的收益/风险都低于栏位内；但**同类按钮的宽度不一致问题一模一样**，且已有 3 个测试钉死其中的尺寸（见 §4）。

| 文件 | 处数 | 典型 minSize | 备注 |
|---|---|---|---|
| `sheet_combat.dart` | 8 | 混合（`⚔️ 战斗部署完毕` 为长主操作） | 玩家/怪物多选 toggle 一排，宽度随名字变 |
| `sheet_music.dart` | 7 | 84×36 / 64×34 / 76×34 | 播放/暂停/停止 已同宽 84 |
| `sheet_scene.dart` | 6 | 混合 | — |
| `sheet_dice_tools.dart` | 5 | 默认 48 | 检定 / SAN Check / 掷骰 / 保存阈值 / 投暗骰 |
| `sheet_kp_panel.dart` | 5 | 默认 48 | `KpDangerAction` 危险动作二次确认 |
| `sheet_misc.dart` | 5 | **54×34**（5 个缩放档） | 被 `p10_t5` 源码扫描钉死 |
| `sheet_opposed.dart` | 5 | 默认 48 | 通用/攻击/武器对抗 + 裁定 + 选目标 |
| `sheet_self_state.dart` | 3 | 默认 48 | — |
| `room_sheet.dart` | 2 | 默认 48 | 弹层壳的重试/关闭 |
| `sheet_bind_char.dart` | 2 | 140×40 / 88×40 | — |
| `sheet_chat_composer.dart` | 2 | **96×44** ×2 | 完成 / 发送 |
| `sheet_history_export.dart` | 2 | **120×40** ×2 | 复制全文 / 系统分享 |
| `sheet_kp_directives.dart` | 2 | 默认 48 | — |
| `sheet_nearby_rooms.dart` | 2 | 76×38 / 110×40 | — |
| `sheet_save_slots.dart` | 2 | 默认 48 | — |
| `sheet_ai_rp.dart` | 1 | **150×42** | 生成 RP 内容（长主操作） |
| `sheet_lan_check.dart` | 1 | **110×40** | 重新探测 |

**结论**：弹层内 60 处按钮中，只有 `sheet_music`(3)、`sheet_chat_composer`(2)、`sheet_history_export`(2)、`sheet_misc`(5) 已经是「同组等宽」；其余全部随文字变宽。

---

## 3. 每个栏位的「不整齐」根因

### 3.1 gpToolbar（工具栏，块 11）★ 最乱

- **排布**：`Wrap` 多行（`gp_toolbar.dart:105`），高度由内容撑开，`SingleChildScrollView` 仅作极端兜底。
- **宽度差异来源**：14 个按钮里有**三套互不相干的尺寸体系**：① `gp_toolbar` 的 4 个用**默认 48×48**（高度 48）；② `gp_dice_bar` 的 8 个全部是 **40 高**（52/48/88/64/56 宽）；③ 扩展的 KP/BGM 是 **56/104 宽 × 40 高**。所以同一 `Wrap` 里高度 48 与 40 混排 → 虽然 `crossAxisAlignment.center` 让中心对齐，但**上下沿参差**，这就是肉眼「不整齐」的第一来源。
- **宽度差异来源 2**：`其他骰子`(88)、`BGM 场景`(104)、`更多工具`(96) 是显式加宽；`下一轮/转战斗`(≈73)、`暗骰关`(64)、`战技/对抗`(56) 靠文字长度；纯图标（重置/自定义掷）只有 48。宽度从 48 到 104 无规律跳动。
- **换行/溢出**：不横向滚动（这是 P10 特意修的，并被测试钉死）；窄档会换 4–5 行。
- **360dp**：`Wrap` 一行约放 4 个（48+73+73+48 ≈ 250，加 spacing）→ 14 个按钮 4 行 + 骰子条窄档自身 3–4 行 → 工具栏高度逼近 `kToolbarMaxShare = 0.62`（`room_game_page.dart:136`）上限，内容区被压到 `viewport.height > 120` 的边缘（测试 `room_ui_layout_test.dart:547` 就是守这条）。
- **1520dp**：一行能排下全部 14 个（约 950dp）→ 工具栏只有 ~44 高，**右侧留大片空白**，且按钮宽度不齐在宽屏上格外显眼。

### 3.2 gpDiceBar（骰子条，在 gpToolbar 内）

- **排布**：窄档（<600dp）显式切 4/3/3/3 行；宽档单 `Wrap`。
- **宽度差异**：`其他骰子` 88 是条内唯一的「长按钮」，其余 48–64。
- **换行点敏感**：`maxPerRow = ((w-16)/88).floor().clamp(2,4)`（`:348`）里的 **88 是魔数**；只要按钮平均宽变化，切行就会从 4/3/3/3 变成别的分组，`p10_t6` 的「无孤行 / 战技不独占一行」两条断言会直接测到。
- **高度**：全部 40，这一条内部是自洽的（这也是为什么它看起来比上面 `gp_toolbar` 那一行整齐）。

### 3.3 gpKpTools（工具窄栏，块 3）

- **排布**：竖排（`Column stretch`）。三块异构内容叠在一起：`Align(加怪)` 单按钮行 → `Wrap(5 个工具)` → `Wrap(5 个色块 ActionChip)` → `Align(上传素材)` 单按钮行。
- **宽度差异**：单按钮行里按钮只有自身宽（48 / 99），下面 `Wrap` 里是 48–86；**同一栏位里出现「一行 1 个窄按钮」和「一行 3 个窄按钮」两种节奏**，左边缘对齐但右侧参差，视觉上像三张不同的表。
- **无横向滚动**：`roomDockMinWidthOf(gpKpTools) = 240`（`room_layout.dart:238-241`），1280dp 实测格宽 246 → **刚好不触发 tooNarrow**。任何加宽（例如把 5 个工具统一成 88）都会让 `Wrap` 换行变多，把 246dp 高的一格撑破（格内竖向滚动兜底，不抛异常，但「一格塞不下」会变成新的用户抱怨）。
- **360dp**：折叠档整块通栏，宽度足够，问题反而消失。

### 3.4 gpKpLeft（左窄栏，块 2）

- **排布**：三个 tab 各自竖排；素材 tab 是「缩略图 + 名字一行」+「`Wrap(公开/封面/删除)` 一行」（`gp_kp_left.dart:343-398`）。
- **宽度差异**：素材三按钮全部默认 48×48（文字 2 字，天然等宽）→ **这一组本来就很齐**；乱的是 `加怪`(Align 单行) 与 `上传素材`(Align 单行) 与 `移除`（在 Row 尾部，48）三个孤立按钮，与上面那组不同尺寸。
- **1280dp 实测格宽 213dp**：`48*3 + 2*2 = 148` 放得下 → 一行。**若统一到 88 宽 → 268 > 213 → 换 2 行**，格子高度不够（格内竖向滚动），视觉更差。这是「不适合强行统一」的典型。
- **测试钉死**：三按钮必须 `width ≥ 48 && height ≥ 48`（见 §4 #15）。

### 3.5 gpMap（素材舞台）

- **排布**：4 个纯图标按钮浮在右下角 `Row`，**无 spacing**（彼此贴着，只有 skin 描边分隔）。
- **结论**：已经是「同尺寸」；唯一问题是 `Row` 之间 0 间距，看起来像一整块。

### 3.6 gpScene（KP 场景检定）

- **排布**：两段 `Wrap`：第一段 6 档裁定（`大成功(5)`…`大失败(-1)`，全 6 字，天然等宽 ≈84），第二段 `快速推送`(≈99) + `检定编辑器`(≈112)。
- **宽度差异**：**6 档内部极度整齐**（这是全工程最整齐的一栏）；乱的是第二段的 2 个按钮与第一段不等宽，且 6 档在高格宽下会排成 6 个一行（1280dp 格宽 288 → 3 个/行 × 2 行）。
- **溢出风险**：`roomDockMinWidthOf(gpScene) = 260`；6 档若统一加宽到 96，288dp 一行只能放 2 个 → 3 行，格子高度不够（格内滚动）。

### 3.7 gpCombat（战斗）

- **排布**：两个按钮在 `SectionBox.trailing` 的 `Wrap` 里 —— **但 `trailing` 在 `Row` 中拿到的是无界宽约束，`Wrap` 永远不会换行**（`room_panel_kit.dart:79-97`）。所以 96 + 80 + 4 = 180dp 必须一行塞下，窄格（`roomDockMinWidthOf = 220`）里标题会被挤到几乎为 0。
- **宽度差异**：`下一个行动 ▶`(96) vs `＋加入`(80)，高度 32（低于 48 热区）。
- **1520dp**：两个按钮贴在标题右侧，中间大片空白，与左边标题脱离。

### 3.8 gpPlayers（玩家信息）

- **排布**：每张成员卡里两行 `Row`，各自 `Expanded(Text)` + 1 个按钮。
- **宽度差异**：`详情` 48 vs `全屏+icon` ≈73；两行右边缘不齐（都靠右，但宽度不同）。
- **溢出**：不会（Text 有 `Expanded` 兜底）。

### 3.9 gpChat / gpLog（gpFeeds）

- **排布**：`SectionBox.trailing` 里 3 个元素（`最新 4 条` 文本 + `新`40 + `全屏`44）挤在 `Row`（非 Wrap）→ 无界宽，**不会换行**，窄格时标题被压缩。
- **输入行**：`Expanded(TextField)` + 3 个图标按钮（48/44/48，全 44 高）。**这是全页最整齐的一组之一**（图标按钮统一了高度 44）。
- **宽度差异**：真正乱的是列表内「花幸运/推动」两个 **132×30** 的长按钮 —— 30 高低于 48 热区（违反 §1.5 口径），且 132 宽在 240dp 宽的格子里一行只能放 1 个。
- **360dp**：输入行 `Expanded` 已被压到 ~150dp，若把 3 个图标按钮从 44/48 加宽到 64+，输入框会被压到 <80。

### 3.10 gpPriv（私密栏）

- 与 gpChat 的 trailing 同构：`新`40×32 + `全屏`44×32，两个不同宽的小按钮并排 → 右边不齐。
- 高度 32，是全页最矮的一档。

### 3.11 gpStatus（状态条）

- **排布**：`同意` + `拒绝` 在 `Row` 里，**中间连 spacing 都没有**（`gp_status.dart:84-102`）→ 两个按钮皮肤描边直接贴在一起，看着像一个被劈开的按钮。
- 尺寸 56×36，两者等宽（已统一），**只差一个间距**。

### 3.12 gpPlCharCard（我的角色卡）

- **排布**：`Wrap(状态管理 84 / 急救 64 / 物品 64 / AI RP 64)` 一行 → 然后 `保存到已保存`(128) 独占一行 → `推进 1 轮`(112) 独占一行。
- **宽度差异**：64/84/112/128 四档混在一栏，最右边缘四级台阶；且后两个独占行只有 1 个按钮，左边对齐、右边空白 → 视觉上「三张表叠在一起」。
- **360dp**：Wrap 里 84+64+64+64+12 = 288 → 一行 4 个刚好；若统一到 88 → 3 个/行 → 2 行，高度 +40（这一格是玩家首屏第二块，`roomDockMinWidthOf = 230`，格内可竖滚）。
- **1520dp**：整块很宽（玩家 dock 里更大），4 个按钮只占左上角一小条，右侧全空。

### 3.13 gpPlScene（玩家场景检定）

- 技能 chip `72×32` × N + 长按钮 `140×40`。
- 宽度差异：技能 chip 等宽（72，文字超长会被撑开！`label: '${s.name} ${s.value}'` 无 ellipsis → **长技能名会突破 72**），底部 140 的检定按钮宽度还随技能名变化（`用「侦查」检定` / `用「心理学」检定`）。
- 这是**唯一一个「同一个按钮宽度会随数据变化」**的栏位 → 用户每次选中不同技能，按钮宽度都会跳一下。

### 3.14 gpPlSketch / gpPlNotes / gpPlMates / gpTopbar

- 都是「1–2 个图标按钮 + 一段 Expanded 文本」，宽度不影响整齐度；`笔/擦` 已经同宽 48×32。
- `gp_pl_notes.dart:145` 的删除按钮 **36×30** 是全页最小的热区（低于 48 口径），藏在每行末尾。

### 3.15 窄屏 / 宽屏总结

| 栏位 | 360dp 表现 | 1520dp 表现 |
|---|---|---|
| gpToolbar | 4–5 行，逼近 62% 高度上限 | 1 行 950dp，右侧空白 |
| gpDiceBar | 走窄档，4/3/3/3 | 单 Wrap 一行 |
| gpKpTools | 折叠档通栏，正常 | 246dp 窄列，按钮左对齐右侧空 |
| gpKpLeft | 通栏，正常 | 213dp，素材三按钮刚好一行 |
| gpScene | 3 行 | 2 行，右侧空白 |
| gpCombat | trailing 挤压标题 | 两按钮贴右上，中间空白 |
| gpPlCharCard | Wrap 4 个/行 | 4 个按钮占左上角 |
| gpPlScene | 技能 chip 2–3 个/行 | 全在一行，仍不齐 |

---

## 4. 测试依赖（★ 改动后最可能打红的断言）

> 「会红」= 改按钮宽高后这条断言必然失败；「不确定」= 取决于统一后的具体数值/是否换行。

### 4.1 尺寸 / 几何类（最高风险）

| # | 文件:行 | 断言摘要 | 会红? |
|---|---|---|---|
| 1 | `test/p12_emoji_b_test.dart:256` | `expect(tester.getSize(find.byType(RoomTap)), const Size(48,48))` —— 单字 `RoomTap(label:'好')` 必须精确 48×48 | **会**（若改默认 `minSize`，或给 `RoomTap` 加固定宽/高） |
| 2 | `test/p12_emoji_b_test.dart:273` | `expect(getSize(...), const Size(96,40))` —— 显式 `minSize: Size(96,40)` 必须**精确等于**该值 | **会**（若在 `RoomTap` 内部「按栏位统一」覆盖显式 minSize，或 96×40 被 clamp 到别的值） |
| 3 | `test/p10_t6_layout_test.dart:317` | 412×915 玩家侧：骰子条按钮 `_rowCount(rects) <= 4` | **不确定→偏会**（加宽会让 8 个按钮多占一行；`maxPerRow` 的 88 魔数不改则必红） |
| 4 | `test/p10_t6_layout_test.dart:340` | `rowCounts.every((n) => n >= 2)` —— 每行 ≥2 个，不许孤行 | **会**（若某行只剩 1 个；长按钮更宽时极易出现） |
| 5 | `test/p10_t6_layout_test.dart:350` | `combat.roll` 与它同一 centerY 的按钮 ≥1（战技不许独占一行） | **会**（同上，战技若被挤到行尾独立成行） |
| 6 | `test/p10_t6_layout_test.dart:356-363` | 骰子条内每个按钮 `left/right/top/bottom` 都在 `RoomKeys.gpDiceBar` 矩形内 ±0.5 | **不确定**（`Wrap` 不会横向溢出；但若改成 `Row`/固定宽就会） |
| 7 | `test/p10_t3_layout_test.dart:268-287` | 360×640 工具栏：10 个 key 全部落在 `gpToolbar` 矩形内（上下左右 ±0.5） | **不确定→偏会**（工具栏再长高会被 `kToolbarMaxShare` 裁掉 → `r.bottom > bar.bottom`） |
| 8 | `test/p10_t3_layout_test.dart:297` | `bar.height(1280×800) < bar.height(360×640)` —— 横屏档必须更矮 | **会**（若统一加宽后 1280 档也换 2 行，就不再更矮） |
| 9 | `test/room_ui_layout_test.dart:547` | 360×640 下 `viewport.height > 120` —— 内容区不许被工具栏压成一条缝 | **会**（工具栏加高的直接后果） |
| 10 | `test/room_ui_layout_test.dart:543` / `p10_t6_layout_test.dart:383` / `p10_t3_layout_test.dart:329` | `viewport.bottom <= bar.top + 0.5`（工具栏不遮挡内容，3 个文件同一判据） | 不会（工具栏变高只会让这条更宽松） |
| 11 | `test/room_ui_layout_test.dart:560-563` | 缩放到 0.6 后工具栏 `top`/`height` 完全不变，且 `height > 56` | 不会（与按钮宽度无关） |
| 12 | `test/p10_t6_layout_test.dart:530-538` | 1280/1524 KP：`scene.check.level(5)` 与 `kpTools.placeActor` 的左右边界都在各自格子内 | **不确定**（`Wrap` 换行安全；若改 `Row` 立红） |
| 13 | `test/p10_t6_layout_test.dart:198-199` | 412 顶栏观众入口 `width >= 56`、`height >= 32` | **会**（若把它纳入统一并降到 48 宽） |
| 14 | `test/p10_t6_layout_test.dart:161` / `:190` | 顶栏 `_rowCount == 1`（1524/1280）、`== 2`（412） | **会**（若顶栏按钮变宽导致多一行，或变窄导致 412 只剩 1 行） |
| 15 | **`test/p10_t7_layout_test.dart:427-430`** 与 **`test/p10_t7_b_assets_actors_test.dart:394-397`** | 素材行「公开/封面/删除」三个按钮：`width >= 47.5` **且** `height >= 47.5`，且左右不越出 `gpKpLeft` 格 | **会**（最容易被忽略：统一到「40 高」是本次改造最自然的取值，而这三条要求 ≥48 高；两处测试各 4 条断言） |
| 16 | `test/p10_t7_layout_test.dart:416` / `p10_t7_b_assets_actors_test.dart:382` | 同上，格子矩形来源 `RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)` | 不会（格子不动） |
| 17 | `test/p10_t5_music_synonym_layout_test.dart:351-358` | 5 个缩放档按钮（`MiscSheetKeys.zoom(pct)`, **54×34**）在 320/360/480/700/900 五档宽度下 `top` 集合长度为 1（必须同一行），且外层必须是 `Wrap` | **会**（改 `sheet_misc` 里的 `Size(54,34)` 或 spacing 就红；弹层虽不在栏位内，但改「全局按钮尺寸」时极容易被连带） |
| 18 | `test/p10_t5_music_synonym_layout_test.dart:395` | 源码扫描：`sheet_misc.dart` 必须**字面包含** `Size(54, 34)`、`spacing: 3`、`key: MiscSheetKeys.zoomRow,` | **会**（重构写法即红，哪怕行为不变） |
| 19 | `test/p10_t5_music_synonym_layout_test.dart:401-404` | 源码扫描：`gp_toolbar.dart` 必须含 `'点按切换缩放档位`、`Wrap(`，且**不许**含 `zoomLabel` | **会**（若重写工具栏结构/加可见标签） |
| 20 | `test/p10_t5_music_synonym_layout_test.dart:387` | `tester.widget(find.byKey(GpToolbarKeys.quickRow))` 必须是 `Wrap` | **会**（若把工具栏改成 `Row`/`GridView` 做统一） |

### 4.2 存在性 / 数量 / 文案类

| # | 文件:行 | 断言摘要 | 会红? |
|---|---|---|---|
| 21 | `test/p12_game_e2e_test.dart:83-88` | `taps > 5`；`skins >= taps`（每个 `RoomTap` 都有 `RoomButtonSkin`） | 不会（除非删按钮或绕开 `RoomTap`） |
| 22 | `test/p12_game_e2e_test.dart:96-115` | 遍历**所有** `RoomTap`：`scrollUntilVisible` + `tap(warnIfMissed:false)`，每次点后 `takeException() == null`，`clicked > 3` | **不确定**：尺寸变小不红；但若统一后出现 `RenderFlex overflow`（固定宽 + 窄格）→ `takeException` 非空 → **会红** |
| 23 | `test/p12_game_e2e_test.dart:146-172` | 同上，遍历点开二级弹层，断言无异常 | 同上 |
| 24 | `test/p12_game_e2e_test.dart:68-72` | 6 档屏幕 × 2 角色：整页 `takeException() == null` + `find.byType(RoomTap) findsWidgets` | **不确定→偏会**（`takeException` 是溢出的总闸门） |
| 25 | `test/p12_emoji_b_test.dart:149-181` | 游戏页每个 `RoomButtonSkin` 的 `Container.decoration` 必须是 `surface2`、`foregroundDecoration` 描边 1dp，`checked >= 10` | 不会 |
| 26 | `test/room_ui_blocks_test.dart:253-256` | 旁观者侧 6 个骰子按钮 `enabled == false`；且 `combat.roll/check.opposed` `findsNothing` | 不会 |
| 27 | `test/room_ui_blocks_test.dart:284-288` | 三角色 × 2 op：不渲染 or `enabled == POLICY` | 不会 |
| 28 | `test/room_ui_blocks_test.dart:347` | KP 侧 `combat.next` 存在且 `enabled == true` | 不会 |
| 29 | `test/p10_t7_c_combat_test.dart:296-300` | `deploy.label contains '⚔️ 战斗部署完毕'` 且含 `'怪物 1 · 玩家 2'` | 不会（文案不动；**但若顺手把 emoji 去掉就会红**） |
| 30 | `test/p10_t7_c_combat_test.dart:168-176` | 玩家/怪物 toggle 的 `icon` 是 `check_box(_outline_blank)` | 不会 |
| 31 | `test/p10_t7_b_assets_actors_test.dart:417/433/444`、`p12_emoji_c` 等 | `RoomTap.enabled` 恒等闸门 | 不会 |

### 4.3 权限探针 T-30（`test/room_ui_permission_test.dart`）

| # | 文件:行 | 断言摘要 | 会红? |
|---|---|---|---|
| 32 | `:254-265` | `_enabledByOp()`：遍历 `tester.widgetList<RoomTap>()`，按 `key` 前缀 `act/` 收集 `tap.enabled` | **不会**（只读 `enabled` 字段，与尺寸无关） |
| 33 | `:304-346` | 静态扫描锚点表：`RoomKeys.action(op)` 的挂载点必须存在（`gp_dice_bar`/`gp_toolbar`/…） | **不会**（除非把按钮挪进别的 widget 导致扫描失配——扫描是按源码文件的，挪文件才红） |
| 34 | `:358-487` | 运行时：每个 op × {KP, 玩家, 旁观} `enabled == gate.can(op)` | 不会 |
| 35 | `:494-515` | `room.kick` 多个按钮的 enabled 集合恰好 `{gate.can}` | 不会 |
| 36 | `:535-591` | T-22 结构式边界：该角色不渲染的 op 必须 `findsNothing` | **不会**（只要保持「结构不渲染」策略；若为统一布局把它们改成 `enabled:false` 就会红） |

> 结论：**T-30 表对尺寸改动免疫**（只读 `enabled`），但**对「按钮数量/渲染条件」极度敏感**。

### 4.4 布局档位 / 槽位 / 分栏类（本次大概率不动，但要知道它们存在）

| # | 文件:行 | 断言摘要 |
|---|---|---|
| 37 | `test/room_ui_layout_test.dart:83-115` | `RoomGridSpec.of` 五档阈值（`wide=820` / `narrowLo=520` / `narrowHi=599` / `minH=290` / `compactH=360` / `dockShortSide=560`）逐个断言 |
| 38 | `test/p10_t6_layout_test.dart:399-426` | dock 声明式树：DFS 顺序、`gpKpLeft=[17]`、`gpKpTools=[83,44,24]`、`gpMap=[83,44,50]`、`gpStatus.last=5` |
| 39 | `test/p10_t6_layout_test.dart:428-441` | 三个 KP 窄栏下限 < 1280 档实测格宽（`toolsW > 240`、`sceneW > 260`、`mapW > sceneW*1.5`） |
| 40 | `test/p10_t6_layout_test.dart:519-528` | 5 个窄栏子树里**不许**出现横向 `SingleChildScrollView`（tooNarrow 判据） |
| 41 | `test/p10_t6_layout_test.dart:540-551` | 10 个格子都在「顶栏下沿 ~ 工具栏上沿」之间 + `takeException() == null` |
| 42 | `test/p10_t3_layout_test.dart:145-162` | `dock` 档不许出现 `RoomSlotSquare`；`folded` 档除展开槽外都必须是 `RoomSlotSquare` |
| 43 | `test/room_ui_layout_test.dart:237-330` | folded 档折叠/展开往返（`local.isFolded` + `RoomSlotSquare` 类型） |
| 44 | `test/p10_t3b_rule_diff_test.dart:753-760` | `RoomGridSpec` 纯函数三档判定 |

> 41 号（`takeException`）与 40 号（不许横向滚动）是**改按钮宽高时的隐性红线**：加宽 → 格宽不足 → `tooNarrow` → 出现横向滚动 → 40 号红；或溢出 → 41 号红。

### 4.5 测试依赖总览

- 直接与「按钮尺寸/几何」强耦合：**20 条**（#1–#20）
- 存在性/数量/文案：**11 条**（#21–#31）
- T-30 权限探针：**5 条**（#32–#36，**全部免疫**）
- 布局档位/槽位：**8 条**（#37–#44，间接受影响）
- **改高度比改宽度危险得多**（#1、#2、#15 三条精确/下限断言全在高度上）。

---

## 5. 现有可复用的统一化手段（不要新造轮子）

| 手段 | 位置 | 现状 | 可否复用 |
|---|---|---|---|
| `RoomTheme.tapMinSize = 48` | `room_theme.dart:25` | **唯一**尺寸常量，只被 `RoomTap` 默认值引用（`room_panel_kit.dart:163`） | ✅ 增补同类常量即可（如 `btnH`/`btnWNarrow`/`btnWide`），不必改 `RoomTap` 结构 |
| `RoomTap.minSize` 参数 | `room_panel_kit.dart:157/178` | 所有尺寸的**唯一入口**，43 处已显式传值 | ✅ **强烈推荐**：统一尺寸只需改调用点传入 `minSize`，零框架改动、零布局副作用 |
| `RoomButtonSkin` 零布局影响 | `room_panel_kit.dart:117-150`（注释 `:114-116`、`:133-136`） | 底色 + `foregroundDecoration` 描边，**不加 padding、不占尺寸** | ✅ 已经为「改尺寸不破坏视觉」铺好路；不要给 skin 加 padding |
| `SectionBox` 的 `Column(stretch)` | `room_panel_kit.dart:76` | 子件天然拿到**满宽紧约束** | ✅ 想让某栏位按钮「等宽铺满」时，直接放 `Column` 子件即可（`Expanded` 或 `SizedBox(width: double.infinity)`），无需新容器 |
| `SectionBox.trailing` | `room_panel_kit.dart:95` | `Row[Expanded(title), trailing]` | ⚠️ 可用但**有陷阱**：trailing 在 Row 中是无界宽，`Wrap` 不会换行（见 §3.7/§3.9） |
| `Radii.sm/md/lg = 9/14/20` | `theme.dart:208-213` | 全局圆角 token，`RoomTap` 用 `md` | ✅ 尺寸变化时圆角不必跟着变 |
| `RoomTheme.panelGap = 8` / `panelRadius = 12` | `room_theme.dart:23-24` | 面板间距/圆角 | ✅ 栏位内按钮间距可引用 `panelGap / 2 = 4`（多数 `Wrap` 已在用 4） |
| `roomBlockGap(spec)` / `kRoomSidePadding = 8` | `room_game_page.dart:129-133` | compact 档 4、正常 8；左右留白 8 | ✅ 栅格间距唯一来源 |
| `buildRoomLayout(node, gap, cellOf)` | `room_layout.dart:276-314` | 声明式 Flex 树，所有间距同一 `gap`，`crossAxisAlignment: stretch` | ✅ 改栏位排布时可复用它保证交叉处对齐 |
| `RoomGridSpec.of(w,h,landscape)` | `room_view.dart:130-174` | 五档断点唯一真相源（`820/520/599/290/360/560`） | ✅ 判断「窄屏/宽屏」时**必须**用它，不许在 widget 里写数字 |
| `roomDockMinWidthOf(slot)` | `room_layout.dart:228-273` | 每格最小可用宽（kpTools 240 / kpLeft 200 / gpScene 260 / gpPlScene 288 / combat·players 220 / priv·plCombat·mates·sketch·notes 240 / charCard 230 / chat 各类 120） | ✅ **加宽按钮前必须先查这张表**，否则 tooNarrow → 横向滚动 |
| `kToolbarMaxShare = 0.62` | `room_game_page.dart:136` | 工具栏最多占 62% 高 | ⚠️ 是工具栏加宽的硬上限 |
| `PanelTabs` / `ChipRow`（`ActionChip` + `Wrap`） | `room_panel_kit.dart:256/402` | tab 与多选 chip 已统一 `Wrap(spacing:6/4)` | ✅ 但**不参与**本次按钮统一（是 chip 不是 `RoomTap`） |

**已存在的「事实标准」尺寸族（没有常量，全靠复制）**：

```
高 48：默认（13 个栏位按钮在用）
高 44：gp_feeds 输入行 3 个 / gp_pl_notes add
高 40：gp_dice_bar 全部 / gp_pl_char_card 4+2 / 工具栏扩展 / gp_pl_combat 加入
高 36：gp_status 同意拒绝
高 32：gp_map_stage / gp_feeds trailing / gp_privates / gp_combat trailing / gp_topbar / gp_pl_mates / gp_pl_sketch / gp_pl_scene 技能
高 30：gp_feeds 花幸运 / 推动 / gp_pl_notes 删除
```

**建议**（不是本次改动内容，供架构决策）：在 `RoomTheme` 增 4 个常量 + 在 `RoomTap` 旁加一个 `RoomTapSize` 枚举（`icon` / `short` / `normal` / `wide`），**只让调用点改用枚举**，`RoomTap` 内部一行不改 —— 这样 `p12_emoji_b` 的两条精确尺寸断言仍绿。

---

## 6. 风险与建议（10 条以内）

1. **不要改 `RoomTap` 内部**（`room_panel_kit.dart:210-229`）。它是全局唯一抓手，`p12_emoji_b_test.dart:256/273` 用 `getSize` 精确钉死了「默认 48×48」「显式 minSize 精确生效」两条语义。统一的正确位置是**调用点传 `minSize`**，或新增一个上层包装组件。

2. **优先统一「高度」，再统一「宽度」**。当前真正的视觉噪声是 **48 / 40 / 44 / 32 四种高度混排**（工具栏里 48 与 40 直接相邻）。把同一栏位的高度收成一档，收益 80%；宽度收成等宽，收益 20% 但风险高（会改换行点）。**但注意**：`p10_t7_layout_test.dart:429` + `p10_t7_b_assets_actors_test.dart:396` 要求素材三按钮 **≥48 高**，所以「全局统一到 40」这条路直接被堵死；要么统一到 **48**，要么给素材行开例外。

3. **最不适合强行统一的 3 处**：
   - `gp_map_stage`（4 个 **36×32** 纯图标，浮在舞台上，放大到 48 会盖住画面）——保持原样。
   - `gp_feeds` 的 **132×30**「花幸运 / 推动」（贴在信息流行尾，加高会把行高从 ~34 拉到 ~52，整个信息流密度崩掉）——最多加宽，不要加高。
   - `gp_pl_notes` 的 **36×30** 删除按钮（每行末尾，属于高密度列表）——保持小尺寸，但应补 Tooltip（已有 `hint`）。

4. **统一收益最大的 4 处**（建议优先做）：
   - **gpToolbar**：把 `gp_toolbar` 的 4 个（48 高）与 `gp_dice_bar` 的 8 个（40 高）统一到**同一高度**（建议 40，因为骰子条 8 个是主体；但 40 < 48 会碰 §4 #1 的「默认值」断言吗？不会——`#1` 断的是 **不传 minSize** 的 `RoomTap`，只要显式传值就安全）。
   - **gpKpTools**：把「加怪 / 5 工具 / 上传素材」收成一档宽度（如 4 列 grid 或统一 `SizedBox(width: 84)`），消除「1 个按钮一行 vs 3 个按钮一行」的节奏跳变。
   - **gpPlCharCard**：4 个短按钮（64/64/64/84 → 统一 84）+ 2 个长按钮（128/112 → 统一 128），并把两行长按钮从 `Align(centerLeft)` 改成与 `Wrap` 同宽的一行（`Row[Expanded, Expanded]` 或 `Wrap` + `SizedBox`）。
   - **gpStatus**：两个 56×36 已经等宽，只差 `spacing`（`gp_status.dart:84`）——加个 `SizedBox(width: 6)` 立刻整齐，成本几乎为零。

5. **`SectionBox.trailing` 是无界宽陷阱**（`room_panel_kit.dart:79-97`）。gpCombat 的 96+80 与 gpFeeds 的 40+44 都放在 `Row` 的 trailing 里，`Wrap` 永不换行。若把这些按钮加宽到 ≥100，`gpCombat`（`roomDockMinWidthOf = 220`）会先挤掉标题，再 `RenderFlex overflow` → `p10_t6_layout_test.dart:551` 的 `takeException` 直接红。**改这些按钮前先把 trailing 从 `Row` 换成 `Row[Expanded(title), Flexible(trailing)]` 或允许换行的布局**。

6. **`gp_dice_bar.dart:348` 的 `88` 魔数必须同步改**。`maxPerRow = ((w - 16) / 88).floor().clamp(2, 4)` 假设按钮平均 88dp；一旦按钮统一到 72 或 96，4/3/3/3 的均衡切行会变成 5/4/4 或 3/3/3/4，`p10_t6_layout_test.dart` 的 **#3/#4/#5** 三条（行数 ≤4、每行 ≥2、战技不孤行）会立刻失守。建议把 88 换成「常量 = 统一后的按钮宽 + spacing」。

7. **`Wrap` 换行点变化是最大的连带影响**，且**不可局部预测**（`gp_toolbar.dart:56-65` 的注释已经写明「需要几行随宽度非单调」：360→278dp、480→234dp、700→148dp、780→190dp）。所以：
   - 不要试图用「宽度查表」决定行数（历史上已被证伪）；
   - 统一尺寸后**必须重跑** `p10_t3`(D 组)、`p10_t6`(B 组)、`p12_game_e2e`(A 组 6 档) 这三组，它们是「换行变化的探针」。

8. **`Expanded` 比例与横向滚动阈值**：`_slotView`（`room_game_page.dart:655-667`）用 `c.maxWidth < roomDockMinWidthOf(slot)` 判 tooNarrow → 一旦触发就出现**横向滚动**，`p10_t6_layout_test.dart:519-528` 会红。加宽按钮**不会**改变格宽，所以这条不会直接红；但如果你为了「让按钮排整齐」顺手把 `roomDockMinWidthOf` 调大，**立刻**会把 1280 档的三个 KP 窄栏推进 tooNarrow（它们当前 246 / 213 / 288 都只是刚好越过下限）。

9. **性能/一致性小坑**：`RoomTap` 的 `Align(widthFactor:1,heightFactor:1)`（`room_panel_kit.dart:220-228`）意味着**任何父级松约束下按钮都按内容收缩**。若想「竖排等宽」，正确做法是父级用 `Column(crossAxisAlignment: stretch)` 或 `SizedBox(width: double.infinity)` 包住，**而不是**给 `RoomTap` 加 `width: double.infinity`（会破坏 `Wrap` 的多列排布，正是 P10-2B 修过的 bug）。

10. **弹层不在用户诉求内，但会被「全局统一」连带打红**：`sheet_misc.dart` 的 `Size(54, 34)` 被 `p10_t5_music_synonym_layout_test.dart:395` **字面扫描**钉死，`gp_toolbar.dart` 里的 `'点按切换缩放档位` 也被字面钉死（`:401`）。若定义「全局按钮高度 44」并批量替换，这两条源码扫描断言会先红——**改动应限定在 `widgets/` 下指定栏位，不要做全仓库批量替换**。

---

## 附：本次审计的复现命令

```bash
# 所有按钮挂载点
grep -rn "RoomTap(" lib/ui/room/

# 每文件计数
for f in lib/ui/room/widgets/*.dart lib/ui/room/sheets/*.dart; do
  echo "$(grep -c 'RoomTap(' $f)  $f"; done

# 尺寸分布（42 种）
grep -rhno "Size([0-9]*, [0-9]*)" lib/ui/room/**/*.dart | sort | uniq -c | sort -rn

# 几何断言分布
grep -rn "getSize\|getRect\|getTopLeft\|getCenter" test/
```

> 全文只读审计，未修改任何 `.dart` 文件，未执行 `flutter test` / `flutter build`。
