# P10 第 7 期 C 批 A 组交付报告（聊天输入框全屏 + 公开信息栏最新 4 条 / 实时）

- 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 执行人：工程师 寇豆码（software-engineer-7）
- 模式：快速模式（本批代码 + 测试 + 报告 + 自检一次性完成）
- 环境：Flutter 3.47.9 / Dart 3.13.7；Flutter SDK `/d/dev/flutter/bin`
- 每条 `flutter test` 前 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy` + `export NO_PROXY=127.0.0.1,localhost`；每条 flutter 命令后立刻 `cp pubspec.lock.t7bak pubspec.lock`
- 全程未跑 adb / 模拟器 / 真机；未执行 `flutter clean`；未删改 `build/` 实目录

---

## 一、用户原话与根因（按主理人定位，未重新猜测）

> 5. 聊天框，文字输入框，改为点击文字输入框（焦点在输入框），输入框变为全屏，好让玩家可以方便检查自己写了什么。
> 6. 公开信息栏，现在显示不出来最新的 4 条消息。全屏公开信息栏之后，不实时更新最新消息。

| # | 根因 | 修复 |
|---|------|------|
| 1 | `gp_feeds.dart` 全屏按钮 body 捕获 `build` 里的局部 `items` 快照，会话再通知也不刷新 | 换成订阅式 `_LiveFeedBody`，`build` 内 `RoomScope.of(context)` 重新派生 items |
| 2 | `collectFeeds/collectChats` 时间正序（最新在最后），`ListView` 首帧从第 0 条画起 | `_FeedListState` 首次有 items 时 `addPostFrameCallback` → `jumpTo(maxScrollExtent)` |
| 3 | `didUpdateWidget` 用 `length != old.length` 判跟随；cap 打满后长度不变就再也不跟随 | 换锚为「末条 seq 变化」`widget.items.last.seq != old.items.last.seq`，空列表边界仍按长度判 |
| 4 | 单行 `TextField` 无法回看长发言 | 原输入框 `onTap` + 独立「全屏编辑」入口 → 全屏多行编辑器 |

---

## 二、文件清单 + SHA256（最终态）

| 文件 | 状态 | 行数 | SHA256 |
|---|---|---|---|
| `lib/ui/room/widgets/gp_feeds.dart` | 修改（独占） | 819 | `43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75` |
| `lib/ui/room/sheets/sheet_chat_composer.dart` | 新建（独占） | 198 | `f6821c29922fcd9544a18bd851cfe58a0d9deaa2ba3617ba655082abe7ac214c` |
| `test/p10_t7_c_feeds_test.dart` | 新建（独占） | 559 | `c5a52e8147cbb61a5de7245e67f903736fd8ef8938bbc008ff49e939b5cad475` |
| `_p10_transport10_ca.md` | 新建（本报告） | — | — |
| `pubspec.lock` | 每次 flutter 命令后恢复，保持与 `.t7bak` 一致 | — | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` |
| `pubspec.lock.t7bak` | 干净备份，未改动 | — | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` |

**未触碰**（硬约束核对）：`pubspec.yaml`（`be110a37b56db8c7769f1e8ee4f26c28e740a91b2a2446068b7f4f239d33d887`）、`lib/app_version.dart`（`7dead8a9992cda6c1f6f20ec46832230bf4428080bd0415f5c5c5381cbf783b5`）、`lib/domain/**`、`lib/ui/room/room_game_page.dart`、`gp_kp_left.dart`、`gp_kp_tools.dart`、`room_layout.dart`、`gp_toolbar.dart`、`sheet_combat.dart`、`gp_combat_list.dart`、`test/` 下任何既有文件、GENERATED FILE、`oracle_*`、门禁 `FROZEN = 4`、`build/`。

### 各文件改动要点

**`gp_feeds.dart`**
- `GpFeedsKeys` 新增稳定 key：`chatFullscreen`、`chatComposer` / `chatComposerField` / `chatComposerDone` / `chatComposerSend`（别名到 `ChatComposerKeys`）、`liveBody`、`latestHint`。既有 `list` / `fullscreen` / `send` / `empty` / `aiRp` / `flash(pane)` / `row(seq)` / `avatar(seq)` / `luck(seq)` / `push(seq)` **逐字保留**。
- `SectionBox.trailing` 加一个 `Text('最新 4 条', key: GpFeedsKeys.latestHint)` 小标签（在 flash 之前，不遮挡 flash 角标）；主列表一行未删、数据未截断。
- 全屏按钮 `showRoomSheet` 调用保留，`body` 改为 `_LiveFeedBody(pane: pane, limit: widget.limit)`。
- 新增 `_LiveFeedBody`（`StatelessWidget`）：`build` 里 `getInheritedWidgetOfExactType<RoomScope>()` 做空防御，有作用域时 `RoomScope.of(context)` 订阅 session，重新 `collectFeeds / collectChats(state, limit: limit ?? RoomTheme.feedCap/chatCap)`；用 `KeyedSubtree(key: GpFeedsKeys.liveBody)` 包住 `SizedBox(0.6h) > FeedList`。
- `_FeedListState`：新增 `_initialJumpDone` + `_scheduleInitialJump()`（首帧 `addPostFrameCallback` 贴底，只在首次做）；`didUpdateWidget` 先调 `_scheduleInitialJump()` 覆盖「空→非空」，再按 `_tailChanged()`（末条 seq）判断跟随；`!_atBottom()` 早退**一字未改**（P0-06 口径）。`ListView.builder` 显式 `padding: EdgeInsets.zero` 让贴底几何确定。
- `ChatInputRow`：原 `TextField` 保留 `RoomKeys.gpChatInput` / `controller` / `enabled` / `onChanged` / `onSubmitted`，新增 `onTap: editable ? () => _openComposer(context) : null`；新增独立 `GpFeedsKeys.chatFullscreen` 图标按钮（旁观者不渲染）；新增 `_openComposer()` 处理草稿双向同步、完成回填（selection 移到末尾）、发送复用 `_send()`；AI RP 的 `openAiRpSheet(onFilled:)` 只填不发行为**未改**。

**`sheet_chat_composer.dart`（新建）**
- `ChatComposerKeys`：`root / field / done / send / close`，字面量统一 `gpFeeds/` 命名空间，避免与 `gp_feeds.dart` 循环 import。
- `showChatComposer(...)`：`Navigator.push(MaterialPageRoute<String>(fullscreenDialog: true, ...))`，返回草稿文本（`null` = 已发送 / 系统返回）。
- `ChatComposerPage`：`Scaffold` + `SafeArea` + `AppBar('编辑发言' + 关闭)` + `maxLines: null, expands: true, autofocus` 多行 `TextField` + 底部「完成」「发送」`RoomTap`。
- 本页**不读 RoomScope**（弹层/新路由是页面路由的兄弟，`RoomScope` 在页面路由内）；草稿与发包全由调用方回调传入，避免作用域断言并消除循环依赖。

---

## 三、测试

### 新建用例（`test/p10_t7_c_feeds_test.dart`，共 **10** 个 `testWidgets`）

| 编号 | 覆盖 |
|---|---|
| ① | 造 8 条 → 首帧贴底；`getRect` 实测最后 4 条完整落在视口 Rect 内、更早 4 条在视口上方；同时断言 `latestHint` / `fullscreen` / `list` / `gpChatInput` 均在、`pixels == maxScrollExtent` |
| ② | 同长度（cap 满）、末条 seq 8→9 且内容变高 → `maxScrollExtent` 变大后仍 `pixels == maxScrollExtent`，新末条完整可见 |
| ②b | 真实 `GpFeeds(limit: 8)` cap 边界：追加第 9 条后长度仍 8、末条 seq 前进，主栏仍贴底显示新末条 |
| ⑦ | **P0-06 逐字保留**：上滚回看（`jumpTo(0)`）后新消息不抢滚动位置 |
| ③ | **硬验收时序**：先打开全屏弹层 → 在弹层打开状态下注入新消息 → `pump` → `find.descendant(of: liveBody, matching: row(newSeq))` 必须 `findsOneWidget`，弹层行数 +1 |
| ④ | 全屏内每个 seq 至多一份（无重复/陈旧行）；屏障关闭后 `liveBody` 消失、主栏 `list` / `fullscreen` / `gpChatInput` 仍在 |
| ⑤ | `tap(RoomKeys.gpChatInput)` → 出现 `chatComposer` 全屏页；`chatComposerField` 输入长文本 → `chatDraft` 同步 → 「完成」→ 原输入框文本 == 输入内容、selection 在末尾、草稿同步、`f.sent` 无 chat（只回填不发） |
| ⑥ | 独立 `chatFullscreen` 入口也能开；「发送」→ 仅 1 条 `RoomIntent.chat`、trim 语义、草稿清空、全屏页关闭、原输入框清空 |
| ⑥b | 旁观者：`chatFullscreen` `findsNothing`、`TextField.enabled == false`、`onTap == null`、点输入框不弹全屏 |
| ⑧ | 回归口径：`enterText`（非 tap）不弹全屏、文本 `abc` 保留、AI RP 与发送键仍在、点发送真发包 |

### 测试结果（全部 `--concurrency=1`）

| 命令 | 结果 | 用例数 |
|---|---|---|
| `flutter test test/p10_t7_c_feeds_test.dart --concurrency=1` | **All tests passed!** | 10 |
| `flutter test test/room_ui_feeds_test.dart --concurrency=1` | **All tests passed!** | 14 |
| `flutter test test/qa_p5_priv_probe_test.dart --concurrency=1` | **All tests passed!** | 13 |
| `flutter test test/room_feed_flash_test.dart --concurrency=1` | **All tests passed!** | 14 |
| `flutter test test/room_feed_flash_wiring_test.dart --concurrency=1` | **All tests passed!** | 10 |
| **合计** | **全绿** | **61** |

`dart analyze`（**全工程**，非仅本批文件）：`No issues found!`（EXIT=0）。
针对本批三文件的 `dart analyze` 亦为 `No issues found!`。

**既有断言未放宽**：未删用例、未 `skip`、未改恒真、`findsOneWidget` 未降级；既有 4 个测试文件一字未改，全部保持原样通过。`FeedFlashTracker` / `_deriveFlash` / `syncEpoch` 判定链完全未动（P2-05 契约）；`_atBottom()` 判据逐字未改（P0-06 契约）。

### 口径加严说明（只加断言，不放宽）

- ① 新增「首帧 `pixels == maxScrollExtent`」与「最后 4 条完整在视口 Rect 内、更早 4 条在视口上方」的几何正向断言；行高由 `FeedRow` 实测得出，不写死数值。
- ② 新增「长度不变 + `maxScrollExtent` 变大 → 仍贴底」的断言，专门钉死 cap 打满后不再跟随的旧 bug。
- ③ 新增「弹层打开后再注入」的真实时序断言，把 `find` 用 `find.descendant(of: liveBody, ...)` 限定在弹层内，避免主栏同 seq 行造成假绿。

---

## 四、反向证伪（只在本批文件集内改坏 → 跑红 → 恢复）

备份：`cp lib/ui/room/widgets/gp_feeds.dart gp_feeds.dart.ca_bak`（备份 sha256 = `43018cef...`），改坏→跑红→`cp` 恢复→核 sha256→复跑全绿；临时备份已在交付前删除。

### 证伪 1：把 `_LiveFeedBody` 换回 `FeedList(items: items)` 快照

- 改法：`body:` 换成 `KeyedSubtree(key: GpFeedsKeys.liveBody, child: SizedBox(... FeedList(items: items, ...)))`（保留 `liveBody` key，确保红在「实时」断言本身而不是「key 不存在」）。
- 命令：`flutter test test/p10_t7_c_feeds_test.dart --concurrency=1 --plain-name "全屏弹层打开状态下注入新消息"`
- 结果：**EXIT=1 红**。失败点 `test/p10_t7_c_feeds_test.dart:321`：
  `Expected: exactly one matching candidate / Actual: Found 0 widgets with key [<'gpFeeds/row/8'>] descending from [<'gpFeeds/liveBody'>]`
  —— 即「★★ 全屏弹层必须实时出现刚注入的新行」。
- 恢复后 sha256：`43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75`（与备份一致）。

### 证伪 2：去掉首帧贴底

- 改法：摘掉 `initState()` 里的 `_scheduleInitialJump();` 与 `didUpdateWidget` 里的 `if (_scheduleInitialJump()) return;`。
- 命令：`flutter test test/p10_t7_c_feeds_test.dart --concurrency=1 --plain-name "造 8 条"`
- 结果：**EXIT=1 红**。失败点 `test/p10_t7_c_feeds_test.dart:155`：
  `Expected: a numeric value within <1.0> of <88.0> / Actual: <0.0>`（列表停在顶部，没贴底）——「★ 首帧必须贴底」。
- 恢复后 sha256：`43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75`（与备份一致）。

### 恢复后复跑（全部绿）

`p10_t7_c_feeds_test(10)` / `room_ui_feeds_test(14)` / `qa_p5_priv_probe_test(13)` / `room_feed_flash_test(14)` / `room_feed_flash_wiring_test(10)` → 61 例全绿，EXIT 全 0。

### 恢复后 sha256 清单（每条 flutter 命令后 `cp` 的核账）

| 项 | 值 |
|---|---|
| `pubspec.lock`（每次命令后） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` |
| `pubspec.lock.t7bak`（基准） | `fa69e59604415960b7449e0b5827fb5ec7eec0926a607d6078edca176504d86c` |
| `grep -c pub.dev pubspec.lock` | `82` |
| `gp_feeds.dart`（两次证伪恢复后） | `43018cef55441d2630dbe5c926c59dc0904d7e13e8c647bd0d8512e57319af75` |
| `sheet_chat_composer.dart` | `f6821c29922fcd9544a18bd851cfe58a0d9deaa2ba3617ba655082abe7ac214c` |
| `test/p10_t7_c_feeds_test.dart` | `c5a52e8147cbb61a5de7245e67f903736fd8ef8938bbc008ff49e939b5cad475` |

---

## 五、全局一致性审查

1. **跨文件 import**：`gp_feeds.dart` 单向 import `sheets/sheet_chat_composer.dart`；`sheet_chat_composer.dart` 只 import `material.dart` + `widgets/room_panel_kit.dart`，**不回引** `gp_feeds.dart` → 无循环依赖。新增 `room_ui_local.dart`（`RoomUiLocal`）为显式类型标注，缺一不可，已补。`RoomScope` / `RoomTheme` / `collectFeeds` / `collectChats` / `FeedItem` / `FeedList` 全部已 import。
2. **接口契约**：`showChatComposer(context, initialText, onChanged, onSend)` 与 `_openComposer` 调用点命名/类型一致；`ChatComposerPage(initialText, onChanged, onSend)` 与 `showChatComposer` 构造一致；`GpFeedsKeys.chatComposer*` 别名到 `ChatComposerKeys.*`，key 值全局唯一。
3. **数据流**：`_LiveFeedBody` 与 `_GpFeedsState.build` 用**同一组口径**（`pane` 分支、`widget.limit ?? RoomTheme.feedCap/chatCap`、`scrollable: true`），不会两处派生出不同列表；`FeedList` 的 `didUpdateWidget` 拿到的是新派生 List，`_tailChanged` 读 `last.seq` 类型正确（空列表已先短路）。
4. **无重复实现**：跟随逻辑只在 `_FeedListState.didUpdateWidget` 一处；闪烁判定仍只在 `_deriveFlash` → `FeedFlashTracker.check`；草稿写入只有 `setChatDraft` 一条路径。
5. **挂载点未动**：`GpFeeds` 的构造参数（`pane/height/limit/title/flashTracker`）签名未改，`room_game_page.dart` 无需改动；全屏按钮与 `showRoomSheet` 调用保留。
6. **既有回归**：4 个既有测试文件 51 例全绿，含 `RoomKeys.gpChatInput` 的 `enterText` / `state` / `enabled` 用例与 P2-05 全链路。

**IS_PASS: YES**

---

## 六、相对设计的最小偏差（均已说明）

1. `ListView.builder` 加 `padding: EdgeInsets.zero`：让首帧贴底与「最新 4 条」几何可确定，不被设备状态栏 `MediaQuery.padding` 整体下推；既有断言未依赖该 padding，4 个回归文件全绿。
2. `_LiveFeedBody` 外包一层 `KeyedSubtree(key: GpFeedsKeys.liveBody)`：给测试一个把查找限定在弹层内的稳定锚点，不渲染任何可见内容、不影响布局。
3. 全屏编辑器用 `Navigator.push<String>(fullscreenDialog: true)` 并**返回草稿文本**，而不是在页内直接调用 `onDone` 回调：为了让系统返回键 / AppBar 关闭也能保留草稿（结果 `null` 时由调用方从 `chatDraft` 回填），同时让新路由完全不依赖 `RoomScope`。「完成」写回原 `_text` + selection 到末尾、「发送」复用 `_send()` 的语义均按要求实现。
4. 「最新 4 条」以**可见提示标签 + 列表贴底**实现，**未截断数据**（主列表一行未删），避免动到既有行数断言；用户看到的是最新若干条，最新 4 条必定在可视区内（用例 ① 用 `getRect` 钉死）。

---

## 七、遗留问题

1. `ListView.builder` 的 `SliverList` 对未布局子项用估算 `maxScrollExtent`；首帧 `jumpTo(maxScrollExtent)` 在**行高差异极大**的极端数据下可能需要 1 帧收敛。当前所有行高一致的用例（含 120 条懒构建回归）稳定贴底；若后续聊天允许超长多行消息，可考虑给 `FeedList` 增加「二次贴底」或固定 `itemExtent`，本次按主理人「只在首次做」的口径未加。
2. 某条消息高度**超过整个面板**时，贴底后只能看到该条的下半部分（底部对齐），这是「跟随最新」的正确行为，但「完整可见」不再成立；用例 ② 已把长文本控制在面板高度内。
3. 全屏编辑器的「系统返回键」路径（`pop` 结果为 `null` → 从 `chatDraft` 回填）已按设计实现，但未写专门用例；已覆盖「完成」「发送」「旁观者」三条主路径。
4. `RoomGamePage`（其他 worker 文件集）里的 `GpFeeds` 挂载点本批未动；本批只靠 `GpFeeds` 自身实现需求，接线回归由 `qa_p5_priv_probe_test.dart` 的整页用例覆盖并全绿。
5. 主理人统一升版本 / 出包 / AOT 排雷不在本批范围；`pubspec.yaml` 与 `lib/app_version.dart` 未改。
