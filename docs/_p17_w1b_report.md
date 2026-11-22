# P17 波1-B 施工报告（v2.30.0）· KP-4 三栏等高 + KP-5 全屏编辑发送

- 施工：**p17-w1b（寇豆码）**
- 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`（基线 v2.29.0+99）
- 独占文件集（只改这三个）：`lib/ui/room/widgets/gp_feeds.dart`、`lib/ui/room/widgets/gp_privates.dart`、`lib/ui/room/sheets/sheet_chat_composer.dart`
- 静态自检：`dart analyze` 三文件 **No issues found!**
- 未跑 `flutter test`（并发写码期纪律）；未改任何既有测试、未新建测试文件；未碰 `pubspec.*` / `app_version.dart` / `room_game_page.dart` / `room_layout.dart` / `room_panel_kit.dart`。

---

## 0. 一句话结论

KP-4 的真因是「聊天块多一行 `ChatInputRow`」而不是 flex / 220：改成 **记录栏 / 私密栏各补一条与输入行等高的纯空白占位**，三块 `Card` 的 `Rect.height` 变为**严格相等（差值 0）**；KP-5 把全屏发送改成 **`onSend` 只碰打开前捕获的 `RoomController` / `RoomUiLocal`（不碰旧 State 的 `_text` / `context`）+ 发送成功清草稿 + 弹层 `pop` 放进 `finally` + 键盘/小屏布局加固**，因此不再依赖底层 `ChatInputRowState` 是否存活。

> **主理人裁决（2026-11-14）**：KP-4 按「等高占位」交付，**不改** `LayoutBuilder + Expanded`（用户要的是「和聊天栏一致」= 等高）。取舍、现状与改动禁区详见 §2.3。

---

## 1. 逐文件改动

> ★ **行号口径**：§1 表里的行号是「KP-4 / KP-5 交付时」的快照；G-1 追加后 `gp_feeds.dart` 整体下移（最终行号与哈希以 §6 / §1.1 首行为准，`gp_privates.dart` 与 `sheet_chat_composer.dart` 未受 G-1 影响、行号仍有效）。

### 1.1 `lib/ui/room/widgets/gp_feeds.dart`

- sha256：`27b5a4e0c8153368f884d8d210e9f903736992b7ac548056684101ddc0dc26cd`（G-1 + 裁决 A 注释订正后的最终值；G-1 初版为 `55d888ca…3909a5`，KP-4/KP-5 交付时为 `d7670e5b…ac3b20`；三次变更均未增删任何逻辑行）
- 行数：933（P17 本批前 824；KP-4/KP-5 后 889；G-1 追加后 933）

| 行号 | 改动 |
|---|---|
| `:34` | import 增补 `clampBtnText`（`room_button_size.dart`，字号缩放钳制的唯一真源） |
| `:299-382` | `_GpFeedsState.build`：`SectionBox.child` 的 `Column` 由 `[SizedBox(height, FeedList)] + if(chat) ChatInputRow` 改为 `[SizedBox(height, FeedList)] + if(chat) ChatInputRow else SizedBox(height: kChatInputRowHeight)`；整段注释写清「根因 + 为什么本批只做等高、不做吃满格子」 |
| `:716` | 新增公开常量 `const double kChatInputRowHeight = 48;`（单一真源，`gp_privates.dart` 复用它） |
| `:781-819` | `_openComposer` 重写：打开前捕获 `scope.controller` / `scope.local` / 初始草稿，`onSend` 内不再写 `_text`、不再调 `_send()`；新增 `bool sent` 判定「真发出去了」；回填改成 `draft = sent ? '' : (result ?? local.chatDraft)` |
| `:829` | `ChatInputRow.build`：把原来的 `return Row(...)` 改成 `final Widget row = Row(...)` |
| `:887` | `return SizedBox(height: kChatInputRowHeight, child: clampBtnText(row));` —— 行高定死 + 只钳本子树字号 |

> **G-1 追加批次**（同日，`gp_feeds.dart` 归本 worker）：`:118-125 / :150` 给 `GpFeeds` 加 `locked`，`:736 / :745` 给 `ChatInputRow` 加 `locked`，`:385-387` 只往 chat 分支递值，`:858` 起 4 个入口按 `writable` 禁用，`:774 / :809` 两处兜底守卫。详见 **§6**（最终哈希 `27b5a4e0…dc26cd`，933 行；与初版只差两处注释用词，行号零漂移）。

关键片段（`:374-378`，KP-4 的唯一实质改动）：

```dart
          if (pane == FeedPane.chat)
            const ChatInputRow()
          else
            // 记录栏没有输入行：补一条等高占位（纯空白，不渲染任何控件）。
            const SizedBox(height: kChatInputRowHeight),
```

关键片段（`:789-802`，KP-5 的闭包解耦）：

```dart
    bool sent = false;
    final String? result = await showChatComposer(
      context: context,
      initialText: initial,
      onChanged: local.setChatDraft,
      onSend: (String text) {
        final String trimmed = text.trim();
        if (trimmed.isEmpty) { local.setChatDraft(''); return; }
        controller.sendIntent(RoomIntent.chat, <String, Object?>{'text': trimmed});
        sent = true;
        local.setChatDraft('');
      },
    );
```

### 1.2 `lib/ui/room/widgets/gp_privates.dart`

- sha256：`dc64eaa17057c313c8c6dcc7bc329d8787cfaf33ace735a69dfecfda3ae6e16e`
- 行数：330（改前 310）

| 行号 | 改动 |
|---|---|
| `:28` | `import 'gp_feeds.dart' show kChatInputRowHeight;`（无循环依赖：`gp_feeds` 不 import `gp_privates`） |
| `:156-169` | 注释：KP-4 同口径说明 + 「默认 height 220 一个字都不改」的约束记录 |
| `:170-193` | 把列表 / 空态主体提成局部 `content`（内容逐字未变，只是从内联位置搬出来） |
| `:194-227` | `SectionBox.child` 由 `SizedBox(height, content)` 改为 `Column(min)[SizedBox(height, content), SizedBox(height: kChatInputRowHeight)]` |

```dart
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(height: widget.height, child: content),
          // 与聊天输入行等高：三块 Card 才等高（纯空白，不渲染控件）。
          const SizedBox(height: kChatInputRowHeight),
        ],
      ),
```

★ **`GpPrivates.height` 默认值仍是 220**（`p16_wave1_theme_test.dart:100-103` 继续绿）。

### 1.3 `lib/ui/room/sheets/sheet_chat_composer.dart`

- sha256：`8149b4601f785271497c2889abeb3a8baf953f0eb35152365476a30afc8bf7ed`
- 行数：247（改前 198）

| 行号 | 改动 |
|---|---|
| `:123-149` | `_send`：`onSend` 用 `try/catch` 包住（异常 `FlutterError.reportError` 上报、不静默吞），`Navigator.pop` 放进 `finally` |
| `:154-245` | `build`：`Scaffold(resizeToAvoidBottomInset: true)`；`body` 改为 `SafeArea(bottom:false) > LayoutBuilder > SingleChildScrollView > Column[SizedBox(fieldHeight, TextField), SizedBox(10), SafeArea(bottom) Row(完成/发送)]`；编辑区高度按可用高算、下限 96dp |

★ 所有 key 一个没动：`ChatComposerKeys.root/field/done/send/close`，按钮文案与 `Size(96,44)` 也没动。

---

## 2. KP-4 前后尺寸计算

### 2.1 改前（逐项实测口径）

| 项 | 文件:行号 | 值 |
|---|---|---|
| dock 中排三格 | `room_layout.dart:146-154` | `flex: 46` 行内 `gpChat/gpLog/gpPriv` 各 `flex:1` → **格子等高** |
| 交叉轴拉伸 | `room_layout.dart:325-328` | `Flex(crossAxisAlignment: CrossAxisAlignment.stretch)` → 只保证**格子**等高 |
| SectionBox 骨架 | `room_panel_kit.dart:68-103` | `Card(margin 4) > Padding(10) > Column(min)[ 标题行, SizedBox(8), child ]` |
| 标题行高 | — | `max(titleSmall ≈20, trailing 44×32)` = **32**（三块 trailing 同档、标题都单行） |
| 槽位外壳 | `room_game_page.dart:779-791` | gpChat/gpLog/gpPriv **走竖向 `SingleChildScrollView`** ⇒ 块体 `maxHeight == infinity`，Card 只能按内容撑高 |
| 聊天 child | `gp_feeds.dart:343-358`（改前） | `SizedBox(220) + ChatInputRow(自然高 ≈44~48)` |
| 记录 child | 同上 | 只有 `SizedBox(220)` |
| 私密 child | `gp_privates.dart:179-205`（改前） | 只有 `SizedBox(220)` |

Card 高 = `10 + 32 + 8 + child + 10` = `60 + child`：

- 聊天 ≈ `60 + 220 + 46` ≈ **326**
- 记录 ≈ `60 + 220` = **280**
- 私密 ≈ **280**
- **差值 ≈ 46dp（就是一行 `ChatInputRow`）** —— 与用户「游戏记录 / 只给你看比聊天栏短」逐字吻合（`_p17_kp_landing.md` §KP-4 的 48dp 估算同源）。

### 2.2 改后

- `ChatInputRow` 高度**定死** `kChatInputRowHeight = 48`（`SizedBox(48) + clampBtnText`，字号钳到 1.0 ⇒ 1.3/1.5/2.0 档不变高）。
- 记录栏补 `SizedBox(height: 48)`；私密栏补 `SizedBox(height: 48)`。

| 块 | 改后 Card 高 |
|---|---|
| 聊天 | `60 + 220 + 48` = **328** |
| 记录 | `60 + 220 + 48` = **328** |
| 私密 | `60 + 220 + 48` = **328** |

- **差值 = 0（≤1dp 达标）**；聊天块的绝对高只从「自然 ≈46」变成「定死 48」，相对改前漂移 ≤4dp（不引入新的裁切风险：格子 ≈344 > 328）。
- 顺带把**玩家档**同一处差异也抹平（`gpPlChat` / `gpPlLog` 同 row）：玩家布局树一个字没动，只是两块的 Card 等高。

### 2.3 §取舍：等高 vs 填满

> **主理人裁决（2026-11-14）**：按「等高占位」方案交付，**不改** `LayoutBuilder + Expanded`。用户诉求原话是「变得和现在的聊天栏一致」——要的是**等高**，不是填满格子；Δ=0 已达成。以下为存档的取舍记录。

#### A. 为什么没落 `LayoutBuilder + Expanded`（施工单建议的 `gp_combat_list.dart:171-230` 范式）

施工单建议参考 `c.hasBoundedHeight ? Expanded(...) : column`。核过后**不采用**，两条硬理由：

1. **在 dock 里格子高度是无界的**：`_slotView` 对 gpChat/gpLog/gpPriv 包了竖向 `SingleChildScrollView`（`room_game_page.dart:779-791`），块体拿到的 `maxHeight == infinity` → `Expanded` 直接断言失败。也就是说有界分支在**生产路径上是死代码**，只在测试宿主里会生效。
2. **「有界就展开」会抢占 `GpFeeds.height` 参数语义**：`GpFeeds(height:)` 是公开参数，`p10_t7_c_feeds_test.dart:141 / 241 / 275` 正是靠 `height: h*4` 把列表视口钳成 4 行来验「首帧贴底 / cap 打满仍跟随 / 上滚不拉底」。一旦有界就展开，这三条（含 `:159 / :218` 的 `getRect(GpFeedsKeys.list)` 视口断言）**必红**，而且那是**放宽语义**、不是产品行为变更 —— 违反「不放宽断言」。

#### B. 现状（如实记录，勿当成已解决）

- 三块 Card 的 `Rect.height` **严格相等**：328 / 328 / 328（**Δ = 0**）。
- 但**三块都未填满格子底端**：格子实测 ≈344，Card ≈328（含 Card margin 4×2 后外框 ≈336），仍有约 8~16dp 的格内留白。这个留白**改前就存在**（改前聊天 326、记录/私密 280，三块各自留白还互不相同），本批**只把「三块不一致」修成「三块一致」，没有改变「块不贴格底」这一既有观感**。
- 留白的来源是结构性的：`_slotView` 给这三格包了竖向 `SingleChildScrollView` ⇒ 块体无界 ⇒ `SectionBox` 的 `Column(mainAxisSize.min)` 只能按内容撑高。

**后续路径（若主理人日后要「贴满格底」）**：
1. 由 **W2-A** 在 `_slotView`（`room_game_page.dart:774-791`）给 `gpChat / gpLog / gpPriv` 换成**紧约束分支**（同 `gpMap / gpPlMap / gpKpLeft` 的 `ClipRect(child: body)`），块体才会拿到确定高度；
2. 三块内部再改 `Expanded` + 单层滚动（`SectionBox.child` 必须直接是 `Expanded`，不能套 Builder —— 见 `gp_combat_list.dart:221-230` 的注释）；
3. **必须同步重写** `p10_t7_c_feeds_test.dart:141 / 241 / 275`（`height: h*4` 钳视口）与 `:159 / :218` 的 `getRect(GpFeedsKeys.list)` 视口断言 —— 改成「外层 `SizedBox` 定高 + 块内展开」或换独立定高宿主，否则那批「首帧贴底 / cap 打满仍跟随 / 上滚不拉底」用例会因口径失效而红。
4. 届时可把本批的 `kChatInputRowHeight` 占位一并删掉（因为 `Expanded` 已经让三块等高），**但必须与 1~3 同一批次做**，否则会立刻退回「记录/私密比聊天矮 48dp」。

#### C. `kChatInputRowHeight` 与占位的定位：**等高空占位，不是布局重构**（改动禁区登记）

本批三条实现点**只解决「高度不一致」**，不含任何 dock 树 / flex / `SectionBox` 改动。为免被后续批次误当「可随手清理的冗余代码」或「隐式契约」，逐点登记如下（代码侧已配中文注释，行号为准）：

| 位置 | 作用 | 动它的后果 / 前提 |
|---|---|---|
| `gp_feeds.dart:710-719` `const double kChatInputRowHeight = 48;` | 三块等高的**唯一耦合点**（单一真源）。文档注释已写明「为什么必须定死」「取值 = chatIcon 44 + 上下各 2dp」 | 改数值 = 三块同时变高但**仍等高**（允许）；前提是聊天行内容高度 ≤ 该值（主题 `contentPadding` 12+12 + `bodySmall` 18.1 ≈ 44，48 留 4dp；不够就调到 52 兜底）。**禁止**改成「按内容自适应」——那等于退回改前的不等高 |
| `gp_feeds.dart:374-378` `else const SizedBox(height: kChatInputRowHeight)` | 记录栏专属等高占位（纯空白，不渲染任何控件） | **删掉 = 记录栏立刻比聊天栏矮 48dp**，用户报的原 bug 当场复现。改记录栏 UI 时不要顺手删它 |
| `gp_privates.dart:218-226` `Column(min)[SizedBox(height, content), SizedBox(height: kChatInputRowHeight)]` | 私密栏专属等高占位 | 同上（矮 48dp）。`GpPrivates.height` 默认 **220 不动**（`p16_wave1_theme_test.dart:100-103` 钉死） |
| `gp_feeds.dart:887` `SizedBox(height: kChatInputRowHeight, child: clampBtnText(row))` | 聊天行定高 + **只钳本子树**字号缩放（P16 纪律） | 去掉 `clampBtnText` = 1.3/1.5/2.0 档行被文字撑高、三块重新不等高。禁止改用 `ClipRect` 硬裁、禁止把钳制抬到页面/主题层 |

一句话：**这是「用等高空占位换高度一致」，不是布局重构**；真正的布局重构（贴满格底）走 B 段那 4 步，且必须与用例口径同批。

---

## 3. KP-5 修复点逐条对照 B2-1 / B2-2

### 3.1 B2-1（主因）：`onSend` 闭包持有已 dispose 的 `ChatInputRowState`

| 环节 | 改前 | 改后 |
|---|---|---|
| 发包所依赖对象 | `_text`（State 的 controller）+ `_send()`（内部再 `RoomScope.read(context)`） | 打开前捕获的 `controller`（`RoomController`）与 `local`（`RoomUiLocal`） |
| 写文本 | `_text.text = text`（`:745`）→ 已 dispose 即抛 used-after-dispose | **完全不再写 `_text`** |
| 发 chat | `_send()` 内部 `sendIntent` | `controller.sendIntent(RoomIntent.chat, {'text': trimmed})`（同一条 intent、同一 trim 语义） |
| 清草稿 | `_send()` 里 `setChatDraft('')` | `onSend` 内 `local.setChatDraft('')` |
| 回填草稿 | `draft = result ?? local.chatDraft`（发送失败时把整段原文**回填**回输入框，用户看到「文字还在」） | `draft = sent ? '' : (result ?? local.chatDraft)` —— **只有没发送才回填** |
| await 之后 | `if (!mounted) return;` 后写 `_text` | 保留同一守卫；且此时 `_text` 只在 `mounted` 为真时触碰 |
| 弹层关闭 | `widget.onSend(...)` 之后才 `Navigator.pop` → 回调抛异常时 **pop 被跳过** | `pop` 在 `finally` → **无条件关闭** |

**为什么不再依赖底层 State**：`onSend` 里出现的两个标识符 `controller` / `local` 都是 `_openComposer` 在 `await` **之前**从 `RoomScope.read(context)` 取出的**普通对象引用**（`RoomController` / `RoomUiLocal`，不是 `BuildContext`、不是 `State` 成员）。`ChatInputRowState.dispose()` 只会 `_text.dispose()` 并让 `context` 失效，对这两个引用没有任何影响。所以「全屏打开期间底层子树被 `KeyedSubtree` 换 key 重建」这一条对发送链路**彻底失效**。

**顺带修掉的第二个「文字还在」来源（H2）**：`setChatDraft` 不 `notifyListeners()`，改前若 `onSend` 抛异常，`_send()` 来不及清 `chatDraft`，`result == null` 时 `draft = result ?? chatDraft` 就把整段原文写回输入框。改后 `sent` 为真一律 `''`，这条路径也不存在了。

### 3.2 B2-2（真机层）：软键盘把「发送」顶出命中区

| 加固点 | 改后 |
|---|---|
| `Scaffold.resizeToAvoidBottomInset` | **显式 `true`**（不再依赖默认值，Dart 侧可搜可审） |
| 编辑区高度 | `fieldHeight = (可用高 - 12*2 - 10 - 44).clamp(96, ∞)`，随键盘弹起**连续收缩**，不做双档切换（避免「切档丢焦点 → 键盘收起 → 再切回」的振荡） |
| 整页可滚 | `SingleChildScrollView` 兜底：极小档（横屏手机 + 大键盘把 body 压到几十 dp）按钮行滚一下一定够得着，绝不半截落在键盘命中区 |
| 底部 Row | 包进自己的 `SafeArea(top:false, minimum: bottom 8)`；外层 `SafeArea(bottom:false)` 把底部 inset 让给它（**不重复吃**，也不是空转代码） |

★ 4 条 key / 文案 / `Size(96,44)` 全部原样，既有 `chatComposer*` 定位用例不受影响。

### 3.3 debug ≠ 真机（已按施工单要求落实）

- `try/finally` 是**不依赖具体抛点**的兜底，所以即便 release 包 assert 被裁、抛点换位置，弹层也一定关；
- 异常仍走 `FlutterError.reportError`（测试里 `tester.takeException()` 可见），不静默吞；
- 真机须另跑一轮验收（下面 §4 的甲乙变体在 debug 夹具裁定，真机再跑一轮）。

---

## 4. 给波4 的验收用例口径

### 4.1 ① 三栏等高断言（KP dock，1280×800）

**夹具必须是完整页**（`f.pageBuilder = (s, r) => const RoomGamePage();` + `useRoomScreen(tester, 1280, 800)` + `f.pageOf(kHostSeat)`，即 `p10_t7_layout_test.dart:46-56` 的 `_bootPage`），**不能**用 `p10_t7_c_feeds_test.dart:462-497` 的 `_host` 最小 shell（那里没有 dock 的 `_slotView` 无界外壳，看不出真因）。

**Rect 取法**：三块 Card 没有对外 key（本批不许新增/改名 key，`SectionBox` 是共用件），所以按「槽位 key → 后代的 `Card` 」取：

```dart
Rect cardOf(RoomSlot slot) {
  final Finder f = find.descendant(
    of: find.byKey(RoomKeys.keyOfSlot(slot)),
    matching: find.byType(Card),   // SectionBox 的根就是 Card
  );
  expect(f, findsOneWidget, reason: '${slot.name} 格内应恰好一张 SectionBox Card');
  return tester.getRect(f);        // 含 Card 自带 margin 4（三块同值，不影响比较）
}

final Rect chat = cardOf(RoomSlot.gpChat);
final Rect log  = cardOf(RoomSlot.gpLog);
final Rect priv = cardOf(RoomSlot.gpPriv);

expect((chat.height - log.height).abs(),  lessThanOrEqualTo(1.0), reason: '聊天与游戏记录 Card 必须等高');
expect((chat.height - priv.height).abs(), lessThanOrEqualTo(1.0), reason: '聊天与「只给你看」Card 必须等高');
expect(chat.top,    moreOrLessEquals(log.top,    epsilon: 0.6));   // 同排同顶
expect(chat.bottom, moreOrLessEquals(priv.bottom, epsilon: 0.6));  // 同排同底
```

**咬得住性（反向证伪，波5 照做）**：删掉 `gp_feeds.dart:376-378` 的 `else const SizedBox(height: kChatInputRowHeight)`（或 `gp_privates.dart:223-224` 那条）→ 对应高度差 ≈48dp → **必红**；逐字节恢复 → 必绿。

建议同时补两条正向断言（防「三块一起变矮」的假绿）：
- `expect(chat.height, greaterThan(300))`（守住 220 内容 + 标题 + 输入行，不许靠压缩三块等高）；
- 固定尺寸控件过字号：`scale ∈ {1.3,1.5,2.0}` 下 `expect(tester.takeException(), isNull)` + 上面三条等高断言仍成立（`kChatInputRowHeight` 已把输入行钳到 1.0，记录 / 私密的占位是纯 `SizedBox`，天然不随字号变）。

### 4.2 ② 甲 / 乙 两变体（KP-5 主因裁定 + 回归）

共同前置（**完整夹具**）：

```dart
final f = RoomUiFixture();
await f.boot(inGame: true);
f.pageBuilder = (String s, String r) => const RoomGamePage();  // 含 RoomRequestWatcher + dock
useRoomScreen(tester, 1280, 800);
await tester.pumpWidget(f.pageOf(kHostSeat));
await tester.pump();
f.clearSent();
```

**甲：先弹一次推送并正常关闭，再走全屏发送**

```dart
// ① 玩家提交一个需 KP 确认的动作 → watcher 居中弹窗
await f.plSessions['p1']!.hostAction('state.edit.self', <String, Object?>{'skill': '侦查', 'value': 70});
await tester.pumpAndSettle();
expect(find.byKey(RoomPushKeys.root), findsOneWidget);
// ② 正常关闭（与 p10_t6_room_fixes_test.dart:700-703 同口径）
await tester.tapAt(const Offset(4, 4));
await tester.pumpAndSettle();
expect(find.byKey(RoomPushKeys.root), findsNothing);
// ③ 全屏编辑 → 发送
await tester.tap(find.byKey(RoomKeys.gpChatInput));
await tester.pumpAndSettle();
await tester.enterText(find.byKey(ChatComposerKeys.field), '甲变体·主持词');
await tester.pump();
await tester.tap(find.byKey(ChatComposerKeys.send));
await tester.pumpAndSettle();
```

**乙：全屏打开后插入底层子树重建，再发送**（覆盖 B2-1）

```dart
// 前置改成 await f.boot(inGame: false);（招募中起步）再 pump 完整页
await tester.tap(find.byKey(RoomKeys.gpChatInput));
await tester.pumpAndSettle();
expect(find.byKey(ChatComposerKeys.root), findsOneWidget);
await tester.enterText(find.byKey(ChatComposerKeys.field), '乙变体·主持词');
await tester.pump();
// ★ 关键一击：KP 开团 → meta.status 翻成 inGame → KeyedSubtree key
//   gp/kp/false → gp/kp/true（room_game_page.dart:228/335-336）→ 底层整棵子树重建
await f.startGame();
await tester.pump();
await tester.pump();
expect(find.byKey(ChatComposerKeys.root), findsOneWidget,
    reason: '全屏是独立路由，底层重建不该把它带走');
await tester.tap(find.byKey(ChatComposerKeys.send));
await tester.pumpAndSettle();
```

> 乙的备选触发（若 `startGame` 在测试里连带弹层，可换这条，同样只换 key 不动语义）：`await tester.pumpWidget(f.shell(kHostSeat, RoomRole.player)); await tester.pump();` —— `pageKeyOf(role, inGame)` 由 `gp/kp/true` 变 `gp/player/true`，底层 `ChatInputRow` 同样被销毁，全屏路由仍在。

**甲乙共用四条断言（任一红即定位到具体环节）**

```dart
expect(find.byKey(ChatComposerKeys.root), findsNothing, reason: '★ 发送后全屏页必须关闭（pop 不许被跳过）');
expect(f.sent.where((e) => e['op'] == RoomIntent.chat), hasLength(1), reason: '★ 必须发出且只发出一条 chat');
expect(f.localOf(kHostSeat).chatDraft, '', reason: '★ 发完清草稿，不许回填');
expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput)).controller!.text, '',
    reason: '★ 原输入行清空（区分「弹层没关」与「草稿被回填」两种「文字还在」）');
expect(tester.takeException(), isNull, reason: 'onSend 不许抛 used-after-dispose');
```

**B2-2 几何断言（真机层，widget 用 viewInsets 注入）**

```dart
addTearDown(() => tester.view.resetViewInsets());
tester.view.viewInsets = const FakeViewPadding(bottom: 320);   // 模拟键盘
await tester.pumpAndSettle();
final Rect sendRect = tester.getRect(find.byKey(ChatComposerKeys.send));
expect(sendRect.bottom, lessThan(800 - 320 + 0.001), reason: '发送按钮必须落在键盘区之上');
await tester.tap(find.byKey(ChatComposerKeys.send), warnIfMissed: false);
```

**结论口径**：本批判定为 **B2-1 成立**（甲绿、乙修复后绿）。若乙仍红，说明还有第三条抛点，需回到 `try/finally` + `takeException` 详情继续查，不要回退本批改动。

### 4.3 已知边界（写进清单，不算回归）

- 乙变体里底层 `ChatInputRow` 是**新建**的 State：它 `didChangeDependencies` 只恢复一次草稿（T-10 契约，绝不覆盖用户正在打的字）。所以「子重建期间用**完成**关闭」时新输入行可能显示空（草稿仍在 `local.chatDraft`，切块/重进可恢复）；「发送」路径不受影响（草稿被清 `''`，新行本来就是空）。这是 P10 就有的契约边界，本批不动。
- `kChatInputRowHeight = 48` 的余量：应用主题 `inputDecorationTheme.contentPadding = vertical 12`（`lib/theme.dart:329`）+ `bodySmall 12.5×1.45` ⇒ 输入框实测 ≈44dp，48 有 4dp 余量。若波4 在某个字号/主题下看到 `RenderFlex overflowed`（只在聊天行），把那一个常量调到 52 即可（**单点修改，三块仍等高**）。

---

## 5. 预计受影响的既有测试 + 建议口径（交波4）

| 测试 | 本批影响 | 建议口径 |
|---|---|---|
| `test/p10_t7_c_feeds_test.dart:406`（⑤ 完成写回） | **应保持绿**（`_finish` 未改；`!mounted` 守卫原样） | 不动；可补 `expect(tester.takeException(), isNull)` 变强 |
| `test/p10_t7_c_feeds_test.dart:458`（⑥ 全屏发送） | **应保持绿**（1 条 chat / trim / `chatDraft==''` / 弹层关 / 输入框清空，五条语义全保留） | 不动；建议补两条：`takeException isNull` + 「回收一条 chat 且 payload 无多余键」（等价加强） |
| `test/p10_t7_c_feeds_test.dart:500`（⑥b 旁观者） | 绿（入口 / `onTap` / `enabled` 未改） | 不动 |
| `test/p10_t7_c_feeds_test.dart:522`（⑧ enterText 不弹全屏） | 绿（仍只在 `TextField.onTap` 挂全屏） | 不动 |
| `test/room_ui_feeds_test.dart:266-315`（T-10 输入行 / 空文本丢弃 / 旁观者禁用） | 绿（State 复用、`_send`、`enabled` 均未动；新增的只是外层 `SizedBox(48)+clampBtnText`） | 不动；建议加一条「行高 == `kChatInputRowHeight`」+ textScaler 1.3/1.5/2.0 不溢出（把本批新守卫钉死） |
| `test/p16_wave1_theme_test.dart:100-103`（`const GpPrivates().height == 220`） | **绿**（默认高度没改） | 不动；建议在此文件新增「私密栏卡片 = 220 内容 + 48 等高占位」与「与 `kChatInputRowHeight` 同源」两条 |
| `test/p16_wave1_theme_test.dart:108+`（私密行 textScaler 1.3/1.5/2.0） | 绿（`GpPrivatesRow` 未改） | 不动 |
| `test/p10_t6_layout_test.dart:437`（`gpChat == [83,46,1]`）/`:480-486`/`:519-551` | 绿（dock flex 树、槽位 Rect 全未动；`takeException` 也不受影响——块体仍在 `SingleChildScrollView` 内，超高只会滚动不会 overflow） | 不动 |
| `test/p10_t7_layout_test.dart:98-102`（底部三块**格子**等高） | 绿（格子几何未动） | 建议追加 §4.1 的 **Card** 等高断言（这才是用户看到的那层） |
| `test/p10_t7_c_feeds_test.dart:130-300`（①②②b⑦ `height: h*4` 滚动窗口） | 绿（`height` 参数语义**未被抢占**，这正是放弃「有界即展开」的原因） | 不动 |
| `test/room_feed_flash_wiring_test.dart:214-215`（`GpFeeds(height: 140)` 双列） | 绿（record 列多 48 占位，角标判定与行渲染无关） | 不动 |
| `test/qa_p5_priv_probe_test.dart:463-484`（撕卡后 `gpChatInput findsOneWidget`，reason 写「撕卡后仍能聊天」） | **裁决 A 后：断言与 reason 都不必改**（撕卡不在锁定范围内，仍可聊天 ⇒ `TextField.enabled == true` 保持），本条**零改动** | **不新增/不改本条**。另**新增一条「昏迷态」用例**（靶子从撕卡挪到昏迷，见 §6.8）：让 p1 进入昏迷（`sheet.damage` 打到 `dying` 或 `madness.advance` 到发作），pump 完整页后断言 `TextField.enabled isFalse`、`GpFeedsKeys.send` / `chatFullscreen` / `aiRp` 三个 `RoomTap.enabled isFalse`、输入行仍 `findsOneWidget`（不隐藏、守等高）、点发送后 `sent` 里 chat 为 0 |
| `test/room_ui_blocks_test.dart` 等整页/块用例 | 绿（块内控件、key、文案全未改） | 不动 |

> 一句话：**本批不预期任何既有用例转红**（自检面已按「不改契约、不改 key、不抢占 `height` 语义」逐条核过）；真正需要新增的是 §4.1 的「Card 等高」和 §4.2 的「甲乙变体」两组**更强**用例。

---

## 6. §G-1 聊天锁定态（追加批次，2026-11-14）

> 需求来源（用户口径）：「玩家昏迷或疯狂时什么都不能操作，只能点『推进 1 轮』和『更多工具』」。`locked` 判据原本只接在工具栏与骰子条上，**聊天发送漏网**；本批裁决为「锁定态禁用聊天发送，历史仍可看」。
> 只改 `lib/ui/room/widgets/gp_feeds.dart`（`:privates` / `:sheet_chat_composer` 一行未动，哈希不变）。

### 6.1 新增参数（放在现有参数**之后**，必填参数顺序不变）

| 位置 | 声明 |
|---|---|
| `gp_feeds.dart:118-125` `GpFeeds` 构造 | `this.locked = false,`（追加在 `flashTracker` 之后；`pane` 仍是唯一必填项） |
| `gp_feeds.dart:150` | `final bool locked;`（文档注释：只对 `pane == chat` 生效、默认 false 逐字不变） |
| `gp_feeds.dart:736` `ChatInputRow` 构造 | `const ChatInputRow({super.key, this.locked = false});` |
| `gp_feeds.dart:745` | `final bool locked;`（文档注释：只做「不能输入 / 不能发」，不清草稿 / 不禁滚动 / 不隐藏） |

### 6.2 `ChatInputRow` 的禁用点（一条门禁 `writable`）

`gp_feeds.dart:858`：`final bool writable = editable && !widget.locked;` —— 与既有「旁观者禁言」合并成**同一条**判据，不新增第二套规则。`writable` **只决定能不能产生文本 / 能不能发，不决定渲染什么**。

| 位置 | 改前 | 改后 |
|---|---|---|
| `:869` 输入框 `enabled` | `editable` | `writable` |
| `:873-876` 输入框 `hintText` | `editable ? '说点什么…' : '旁观中（不能发言）'` | 三档：`说点什么…` / **`锁定中（不能发言）`** / `旁观中（不能发言）`（锁定档特意取短文案，窄栏里不会被撑） |
| `:881` 输入框 `onTap` | `editable ? … : null` | `writable ? … : null`（**锁定态进不了全屏编辑器**） |
| `:894` AI RP `enabled` | 无（恒可用） | `writable`（渲染但禁用） |
| `:914` 全屏编辑 `enabled` | 无（恒可用） | `writable`（渲染但禁用） |
| `:925` 发送 `enabled` | `editable` | `writable` |
| `:774` `_send()` 首行 | — | `if (widget.locked) return;`（兜底，连 `onSubmitted` 也断掉） |
| `:809` `_openComposer()` 首行 | — | `if (widget.locked) return;`（兜底） |

★ **为什么要多禁 AI RP 与「全屏编辑」（团队口径只点了两处）**：全屏编辑器是**独立路由**，它的 `onSend` 直接走打开前捕获的 `RoomController` 发包（见 §3.1），**不经过输入行任何一个按钮**——只禁 `onTap` 而留着 `chatFullscreen` 图标，就是一个现成的绕过口。AI RP 不发货但它往输入框写文本，锁定态下属于「能操作」，一并禁用；两者都**只改 `enabled`、不隐藏**，所以行宽逐像素不变。
★ **不做的三件事**（用户「别让布局跳」）：不清 `_text` / `local.chatDraft`、不禁 `FeedList` 滚动、不隐藏输入行。锁定前后 `ChatInputRow` 仍是同一个 `SizedBox(kChatInputRowHeight=48)`，三块 Card 的等高关系（§2）不受影响。

### 6.3 `pane != chat` 一律忽略

`gp_feeds.dart:385-387`：只有 chat 分支把值递下去 —— `if (pane == FeedPane.chat) ChatInputRow(locked: widget.locked)`；record 分支仍是 `else const SizedBox(height: kChatInputRowHeight)`，**从不读 `widget.locked`**。所以 `GpFeeds(pane: record, locked: true)` 与不传**完全等价**（记录 / 私密面板没有输入行，也没有任何「发送」概念）。

### 6.4 「不传 `locked` 时行为逐字不变」的证据

`locked == false` ⇒ `writable == editable`，改动前后**执行路径等价**（4 个 `enabled` 与 `hint`/`onTap` 的值逐字相同；两个 `if (widget.locked) return;` 在 false 时是空操作）。唯一结构性差异：`ChatInputRow` 从 `const ChatInputRow()` 变成 `ChatInputRow(locked: widget.locked)`，仍是**同 type、同位置**（`GpFeeds.child` 的 Column 第 2 个孩子），Element 复用 ⇒ `_ChatInputRowState` 与其 `_text` 不被重建。

| 既有调用点 / 用例 | 为什么不红 |
|---|---|
| 生产 `room_game_page.dart:832/835/837`（`const GpFeeds(pane: chat/record)` / `const GpPrivates()`） | 不传 → `false`；`writable == editable`，禁用态分支全部不进 |
| `p10_t7_c_feeds_test.dart` ⑤⑥⑧（`:412 / :464 / :528`） | 同上：`enabled=true`、`onTap != null`、hint 仍是「说点什么…」 |
| `p10_t7_c_feeds_test.dart` ⑥b 旁观者（`:506-520`） | `editable=false → writable=false`，与改前一致：`field.enabled isFalse`、`field.onTap isNull`、`chatFullscreen findsNothing`（`if (editable)` 未动）、`send.enabled isFalse` |
| `room_ui_feeds_test.dart:263-318`（T-10 State 复用 / 空文本丢弃 / 旁观者） | State 复用靠「同位置同 type」，非 const 不影响；`_send` 新加的 `locked` 守卫在 false 时直接跳过 |
| `p16_button_unify_test.dart:230-250 / 735-750`（gpFeeds 四键尺寸 48×44 / 44×32） | 只量尺寸；`RoomTap(enabled:false)` 只把 `InkWell.onTap` 置 null，`ConstrainedBox(minSize)`+`Align(factor:1)` 一字未动 ⇒ 尺寸不变 |
| `room_ui_entry_test.dart:778` | 只断言源码里仍含 `GpFeedsKeys.aiRp`（key 未改名未删） |
| `p11_luck_push_test` / `room_feed_flash_wiring_test`（record/chat 块） | 一律不传 `locked`，`FeedList`/角标/行渲染路径零改动 |

### 6.5 字号（textScaler 1.3 / 1.5 / 2.0）

本批**只加禁用态，没加任何尺寸**：`ChatInputRow` 仍然是 `SizedBox(height: kChatInputRowHeight)` + `clampBtnText`（钳到 1.0），三按钮仍是 `RoomBtnSize.chatIcon`（48×44）。唯一的文案变化是锁定态 hint（9 字，比改前「旁观中（不能发言）」更短），窄栏更安全。⇒ 1.3/1.5/2.0 档不会新增溢出。

### 6.6 建议波4 补的用例（锁定态，`locked: true`）

```dart
await tester.pumpWidget(_host(f, 'p1', const GpFeeds(pane: FeedPane.chat, locked: true)));
await tester.pump();
final TextField field = tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput));
expect(field.enabled, isFalse, reason: '锁定态不能输入');
expect(field.onTap, isNull, reason: '锁定态点输入框不进全屏');
expect(tester.widget<RoomTap>(find.byKey(GpFeedsKeys.send)).enabled, isFalse);
expect(tester.widget<RoomTap>(find.byKey(GpFeedsKeys.aiRp)).enabled, isFalse);
expect(tester.widget<RoomTap>(find.byKey(GpFeedsKeys.chatFullscreen)).enabled, isFalse);
expect(find.byKey(GpFeedsKeys.chatFullscreen), findsOneWidget, reason: '★ 不隐藏，布局不跳');
await tester.tap(find.byKey(GpFeedsKeys.send), warnIfMissed: false);
await tester.pump();
expect(f.sent.where((e) => e['op'] == RoomIntent.chat), isEmpty, reason: '锁定态一条 chat 都不许发');
expect(find.byKey(GpFeedsKeys.chatComposer), findsNothing);
// 历史仍可看：FeedList 未禁用
expect(find.byKey(GpFeedsKeys.list), findsOneWidget);
// textScaler 1.3/1.5/2.0：同一条用例循环 pump，断言 takeException() == null
```

> 反向证伪（咬得住）：把 `:858` 的 `!widget.locked` 去掉 → 上面 `enabled/hint` 三条必红；把 `:925` 的 `enabled` 改回 `editable` → 点击后 `sent` 里出现 chat，断言必红。

### 6.7 调用侧已落地（W2-A 直连确认，2026-11-14）

`lib/ui/room/room_game_page.dart`（W2-A 独占，sha256 `61f58635242eb33c3fc921b3de9b0764ad1403a50820763a5cec2469e70ff34f`，1215 行）已按本契约接好，**签名逐字对齐、无需再改**：

```dart
// :863-875
      case RoomSlot.gpChat:
      case RoomSlot.gpPlChat:
        return GpFeeds(
          pane: FeedPane.chat,
          locked: _chatLockedOf(context, role),   // ← 裁决 A 的专用判据
        );
      case RoomSlot.gpLog:
      case RoomSlot.gpPlLog:
        return const GpFeeds(pane: FeedPane.record);   // 记录栏不传、保持 const
```

- `_lockedOf`（`:1057-1061`）= `role != player ? false : operationLocked(findMe(...))`，工具栏 `:1094` 仍在用（**含撕卡**，P10 行为不变）。
- `_chatLockedOf`（文档 `:1062-1072`，方法体 `:1073-1078`）= `role != player ? false : operationLocked(me) && !isRipped(me)`；`isRipped` 来自 `member_view.dart:163`（`bodyViewOf == '死亡' || mental 含「永久疯狂」`，与 `gp_pl_char_card` 的局部 `ripped` 同源），**没有新造判据**。**只喂 `GpFeeds.locked`。**
- `gpChat`/`gpPlChat` 已去掉 `const`（值是运行时算的）；`gpLog`/`gpPriv` 一律 `const` 未传 —— 与 §6.3「record 分支不读 locked」互补，两条路径都不受锁定影响。
- 页面层**没有**再套 `IgnorePointer` / `enabled`，禁用逻辑 100% 收敛在本文件的 `writable` 一处（避免两套判据漂移）。
- ✅ **裁决 A 全链路已验证**（2026-11-14 收口）：昏迷 / 濒死 / 疯狂发作 → 聊天禁用；撕卡 → 聊天仍可用、工具栏照旧锁定。

### 6.8 裁决 A：撕卡**不算**锁定态（2026-11-14，主理人定稿）

**裁决原文**：走 A。撕卡保留「只能聊天」，聊天锁定收窄为「昏迷 / 濒死 / 疯狂发作」三态，**不含撕卡**。理由：用户原话只覆盖「昏迷或疯狂」，没提撕卡；P10（T-20）刻意给撕卡留了社交口子，`gp_pl_char_card.dart:180-188` 的「已撕卡 / 无法行动：只能聊天」就是当时的契约；改成 B 等于推翻一条既有产品决策，且撕卡后连话不能说属明显体验倒退。

**语义边界（最终口径）**

| 触发态 | 参数锁定（工具栏 / 骰子条，`_lockedOf`） | 聊天锁定（`GpFeeds.locked`，`_chatLockedOf`） |
|---|---|---|
| 昏迷 / 濒死 / 疯狂发作 | 锁定 | **锁定**（本批新增） |
| 撕卡（死亡 / 永久疯狂） | 锁定（P10 既有） | **不锁定** —— 仍可聊天（P10 T-20 社交口子） |
| 存活正常 | 不锁 | 不锁 |
| KP / 旁观者 | 不锁（恒 false） | 不锁（恒 false） |

> ★ **撕卡态还能做什么（别写错）**：能**聊天**（输入 + 发送，A 案唯一开口）、能**全屏只读查看**（角色卡 / 记录 / 私密 / 手绘板 canvas）；**不能**保存角色卡（W1-C 的 `saveBtn` 叠的是含撕卡的 `operationLocked`）、**不能**「推进 1 轮」（`gp_pl_char_card.dart:354` 的 `!ripped` 条件使其**不渲染**）、不能掷骰 / 治疗 / 申请。即「撕卡 = 能聊天 + 只能看」，**不是**「只剩聊天且保存可用」。聊天与保存是**两个不同白名单**：撕卡玩家能聊天、不能保存。

**调用侧落点（W2-A，✅ 已落地并复核）**：`_lockedOf` 旁边新增 `_chatLockedOf`（`:1073-1077`，`operationLocked(me) && !isRipped(me)`，`isRipped` 复用 `member_view.dart:163`），**只喂 `GpFeeds.locked`**（`room_game_page.dart:873`）；工具栏 `:1094` 继续用含撕卡的 `_lockedOf` —— P10 的工具栏行为一个字不变。

**本 worker 侧改动**：**零逻辑改动**（`locked` 是纯布尔，两案兼容）；只订正两处文档注释用词，把「昏迷 / 濒死 / 疯狂发作 / 撕卡」里的「撕卡」去掉并注明「裁决 A：`!ripped`」——
- `gp_feeds.dart:142`（`GpFeeds.locked` 首行）
- `gp_feeds.dart:739`（`ChatInputRow.locked` 首行）

两处注释等行替换，**文件行数仍是 933、所有行号零漂移**（`:150 / :387 / :745 / :774 / :809 / :858 / :869 / :881 / :894 / :914 / :925` 全部不变）。

**波4 用例口径（把「禁止发言」的靶子从撕卡挪到昏迷）**

> ★ **夹具必须落到「昏迷」，不能用 `body='死亡'`**：A 案下死亡（撕卡）是**被放行**的那一态，若夹具做成死亡会得到**相反**结论。可用 `status.unconscious == true`、`dying == true`，或 `madness.advance` 到**发作**（临时疯狂）。
> ★ **反向同理：② 必须落到 `body == '死亡'` 或 `mental` 含「永久疯狂」**。`isRipped`（`member_view.dart:163`）= `bodyViewOf(mem) == '死亡' || _hasMental(mem,'永久疯狂')` —— **濒死 ≠ 撕卡**：只把血打到 0（`currentHP == 0` / `dying == true`，`body` 仍是「濒死」）属于 **①（禁聊天）**，② 会拿到 `enabled == false`。这正是 ② 前面那行 `expect(isRipped(...), isTrue)` 前置自检要挡住的错，reason 里已写明「② 的夹具必须 body=='死亡' 或永久疯狂，濒死属 ①」。
> ★ **断言方式**：一定要直读 `tester.widget<TextField>(...).enabled` / `RoomTap.enabled`；「点了没反应」这种写法**不许**当主断言 —— `RoomTap` 在 `enabled == false` 时把 `onTap` 置 null（`room_panel_kit.dart:230-234`），「没回调」与「点击被 `warnIfMissed` 吞掉」不可区分，会重演 P16 的恒真教训。下面那次 `tap` 只是**补充**（顺带验 `_send` 的兜底守卫），不是主证据。
> ★ **必须按 key 逐个读，禁止「本行内 `RoomTap` 数量 == N 且全 false」这种计数式断言**：`aiRp` / `chatFullscreen` 都包在 `if (editable)` 里，**旁观者只有 2 个图标**；将来谁加删一个图标，计数断言会静默变成「测了别的东西」而不报错。按 key 读时少一个就是 `findsNothing` → `widget<RoomTap>` 直接抛红。
> ★ 精确锚点（`gp_feeds.dart`，933 行 / sha256 `27b5a4e0…dc26cd`，G-1+裁决 A 终版）：`writable` `:858`；`TextField(key: RoomKeys.gpChatInput)` `:867`、`enabled: writable` `:869`、`onTap: writable ? … : null` `:881`（**锁定态连全屏编辑器都进不去**，这是最容易被误判成「点了没反应」的一处）；`aiRp` `:891-894`、`chatFullscreen` `:911-914`、`send` `:920-925`。**执行前先核对「行数 + sha256」**：若已变，用 `grep -n "final bool writable"` 重新定位，别按死行号改代码（本批已出现两次跨组引用过期行号）。W1-C 的 `_p17_w1c_report.md` §8.1 引用的就是这张表，两份可对账。

```dart
// 前置：p1 进昏迷（三选一，都走真实 action；★ 不要用 body='死亡'）
f.controllerOf(kHostSeat).hostAction('sheet.damage', <String, Object?>{
  'seat': 'p1', 'amount': 99, 'kind': '测试'});   // → dying / unconscious
// 或：f.controllerOf('p1').hostAction('madness.advance', <String, Object?>{});
await tester.pumpWidget(appFor(f, 'p1', const RoomGamePage()));   // 完整页 + dock
await tester.pump();

// ① 昏迷态：禁用（本批新守卫的靶子）
final TextField field = tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput));
expect(field.enabled, isFalse, reason: '昏迷态不能输入');
expect(field.onTap, isNull, reason: '昏迷态点输入框不进全屏编辑器（最易被误判成"点了没反应"）');
// ★ 按 key 逐个读，别数 RoomTap 个数（aiRp/chatFullscreen 在 if(editable) 内，旁观者只有 2 个）
for (final Key k in <Key>[GpFeedsKeys.aiRp, GpFeedsKeys.chatFullscreen, GpFeedsKeys.send]) {
  expect(tester.widget<RoomTap>(find.byKey(k)).enabled, isFalse, reason: '${k} 昏迷态禁用');
}
expect(find.byKey(RoomKeys.gpChatInput), findsOneWidget, reason: '★ 不隐藏：行宽与三块等高不受影响');
expect(find.byKey(GpFeedsKeys.list), findsOneWidget, reason: '历史仍可看');
await tester.tap(find.byKey(GpFeedsKeys.send), warnIfMissed: false);
await tester.pump();
expect(f.sent.where((e) => e['op'] == RoomIntent.chat), isEmpty, reason: '昏迷态一条 chat 都不许发');

// ② 撕卡态（裁决 A）：仍可聊天 —— 与 qa_p5_priv_probe_test:463-484 同口径
//    ★ 必须另起夹具（撕卡 = body=='死亡' 或永久疯狂），不要复用上面那个昏迷态，
//      否则 ② 退化成 ① 的重复，起不到「互相证伪」的作用。
await tester.pumpWidget(const SizedBox.shrink());
await tester.pump();
// …把 p1 打到撕卡（或直接用权威态置 body='死亡'）后重新 pump 完整页…
expect(isRipped(findMe(f.stateOf('p1'), 'p1')), isTrue,
    reason: '★ 前置自检：② 的夹具必须 body==死亡 或 永久疯狂；濒死（dying/currentHP==0）属 ①');
await tester.pumpWidget(appFor(f, 'p1', const RoomGamePage()));
await tester.pump();
expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput)).enabled, isTrue,
    reason: '★ 撕卡不在锁定范围：仍可聊天（A 案）');
expect(tester.widget<RoomTap>(find.byKey(GpFeedsKeys.send)).enabled, isTrue);
// 注意：撕卡时「保存 / 推进 1 轮」是**另一套白名单**（含撕卡的 operationLocked /
//   gp_pl_char_card 内的 !ripped），这里是 true、那里是 false，两者互不矛盾。

// ③ 解锁全开（回归，防「恒禁」假绿）：治疗/复活后重新 pump
expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput)).enabled, isTrue);
for (final Key k in <Key>[GpFeedsKeys.send, GpFeedsKeys.chatFullscreen, GpFeedsKeys.aiRp]) {
  expect(tester.widget<RoomTap>(find.byKey(k)).enabled, isTrue, reason: '${k} 解锁态必须可用');
}
```

> 三段（昏迷禁 / 撕卡可聊 / 解锁全开）缺一不可：只有 ① 会无法区分「永远禁用」的假绿，加 ③ 才咬得住。W2-A 的 `_p17_w2a_report.md` §6-⑥ 有同一组甲/乙/丙口径，可对拍。

> 反向证伪（咬得住）：把 `gp_feeds.dart:858` 的 `!widget.locked` 去掉 → ① 的 `enabled/onTap` 四条必红；把调用侧 `_chatLockedOf` 写成 `_lockedOf`（含撕卡）→ ② 撕卡仍可聊天必红 —— 两方向都能咬住 A 这条边界。

---

## 7. 声明

- 未运行 `flutter test`（并发写码期纪律），仅 `dart analyze` 三个文件 → `No issues found!`。
- 未修改任何既有测试、未新建测试文件。
- 只改了本批三个独占文件；`room_game_page.dart` / `room_layout.dart` / `room_panel_kit.dart` / `pubspec.yaml` / `pubspec.lock` / `app_version.dart` 一个字节未动。
- `lib/ui/room/**` 零 emoji（只匹配代理对 U+1F300–1FAFF，已 grep 复核）；未新增 `jsStr(`。
- 既有 key 全部保留：`GpFeedsKeys.*`、`GpPrivatesKeys.*`、`ChatComposerKeys.*`（`GpFeedsKeys.chatComposer*` 别名仍指向同一常量）。
- 新增固定尺寸控件（聊天输入行 48dp）已按纪律用 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` **只钳该子树**（`clampBtnText`），未抬到页面/主题层、未用 `ClipRect` 硬裁。
- **G-1 追加批次（§6）**：只改了 `gp_feeds.dart` 一个文件（`gp_privates.dart` / `sheet_chat_composer.dart` 哈希不变）；同样未跑 `flutter test`、未改既有测试、未新建测试文件；未动 domain（`_passSelf` 放行 chat 是既有行为，保持原样）；`GpFeeds.locked` 的调用侧由 W2-A 在 `room_game_page.dart` 的 `gpChat` / `gpPlChat` 传入（裁决 A 后改用 `_chatLockedOf`），跨组瞬态期间 `gpFeeds` 仍默认 `false`、行为不变。
- **裁决 A 后的收尾（§6.8）**：仅把 `:142` / `:739` 两处文档注释里的「撕卡」改成「（不含撕卡 —— 撕卡仍可聊天）」，**等行替换、零逻辑改动、行数 933 与全部行号不变**（哈希 `55d888ca…3909a5` → `27b5a4e0…dc26cd`）。
