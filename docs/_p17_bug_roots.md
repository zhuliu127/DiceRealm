# P17 真机「点了没反应」两 bug 根因研究报告（只读）

- 研究员：`researcher-bugs-p17`
- 工程根：`$P = C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 版本：v2.29.0+99（P16 全量 2235 例全绿之后）
- 声明：**全程只读**。未修改 `lib/**`、`test/**`、`pubspec.*` 任何一行；未跑 `flutter test`（按施工单要求）。只跑了 `grep` / `sed` / 只读 `Read`。本报告是唯一写入文件。
- 用途：给施工单写「一次改对」的修复方案 + 验收用例。结论分三档标注：**【已证】**（有静态代码硬证据）、**【强疑】**（代码有明确隐患但需真机/夹具确认）、**【存疑·真机层】**（纯代码看不出错，必须靠真机/几何/焦点验证）。

---

## 0. 元结论（先读这一节）

**两个 bug 能一起漏过 2235 例全绿，是同一个方法论原因：现有 widget test 全部是「孤立夹具」，从来没有把下面两条真机前置条件串进一个用例。**

1. **连续时序**：现有推送弹窗测试（`p10_t6_room_fixes_test.dart:430` 组、`room_ui_confirm_flow_test.dart:97` 组、`room_ui_kp_test.dart:412`、`room_ui_player_test.dart:298`）都是「挂一个 `RoomRequestWatcher` → 弹一次 → 点同意/拒绝/屏障关闭 → 结束」。**没有任何一个用例在推送弹窗关闭之后再打开第二个业务弹层**（治疗弹层 / 全屏编辑器）。治疗弹层测试（`p16_wave1_sheets_test.dart:567`）则反过来，用一个纯 `_OpenButton` 夹具单独打开 `openTreatSheet`，头顶根本没有 `RoomRequestWatcher`。
2. **真机几何**：全屏编辑器的发送用例（`p10_t7_c_feeds_test.dart:458` 的「⑥」）用 `_host(f, kHostSeat, const GpFeeds(pane: FeedPane.chat))` —— **把 `GpFeeds` 单独挂在一个裸 host 里**，不是挂在 `RoomGamePage` 的 dock 有界高度格子里。因此 `_slotView` 的 `ClipRect` + `SingleChildScrollView`（`room_game_page.dart:750-795`）、KP dock 中排 flex 41→46（`room_layout.dart:100-152`）、真机软键盘 `viewInsets` 这三者**在测试里全都不存在**。

> 施工单第一条硬要求：**验收用例必须重建夹具，不能复用现有 `_host(...)` / `_OpenButton` / 纯 `RoomRequestWatcher` 夹具**。具体夹具步骤见 §2.7 / §3.7。

**用户描述与代码行为不符的三处硬事实（先摆出来，避免施工方照着错误前提改）：**
- **A**：KP 视角**结构上没有治疗按钮**。`openTreatSheet` 全库仅一处调用点，在 `room_game_page.dart:1064-1065`，且被 `if (!isKp)`（`room_game_page.dart:1056`）包住。KP 工具栏只有「KP / BGM 场景」，玩家工具栏才有「治疗」。所以「KP 点治疗按钮」这句在 KP 视角不成立。
- **B**：治疗弹层第一步的 3 个「选方式」按钮 `onTap` 是**纯 `setState`**（`sheet_treat.dart:157-160`），`RoomTap` 默认 `enabled:true`、无 `throttle`、无 `gate`、无 early return；`p16_wave1_sheets_test.dart:584-589` 已实测「点 kind → 点 target → 点 submit 发出 action」全绿。弹层自身逻辑没有「点了没反应」的代码路径。
- **C**：全屏编辑器的「发送」链路**纯代码是自洽的**，且 `p10_t7_c_feeds_test.dart:458-496` 用 **`kHostSeat`（正是 KP 视角）** 专门验过「点发送 → 发出 1 条 `RoomIntent.chat` + 清草稿 + 关全屏 + 清空原输入框」全部通过。KP 发 chat 在 domain 也是放行的（`room_types.dart:243` POLICY `[kp, player]` 免确认；`room_model_host_intent.dart:174-188` KP 自己发言走 `to:'*'` 广播）。**代码层没有"KP 发不出去"的分支**。

---

## 1. 全链路事实地图（统一证据，后文引用）

### 1.1 推送弹窗链路
- `RoomRequestWatcher` 挂在 `RoomGamePage` 根节点**最外层**，`KeyedSubtree`（key = `pageKeyOf(role, inGame)`）之外：`room_game_page.dart:319-337`。它跨子树重建持续监听，`build` 只返回 `widget.child`（`room_request_watcher.dart:395`），零 RenderObject。
- 数据源 `collectRoomPushRequests(s)`：`room_request_watcher.dart:157-210`。KP 读 `hostRead.pending`（高危动作，CONFIRM，`id = 'pending:$op:$by'`，**line 170**）与 `hostRead.requestsBySeat`（状态变更请求，CONSENT，`id = r['id']` 即 `r$localSeq`，**line 183-190**）；玩家读自己裁剪态 `state['requests']`（line 196-207）。
- 监听 `_onSession`：`room_request_watcher.dart:265-277`。`if (_seen.add(r.id)) _queue.add(r)`（**line 270**），`if (_queue.isEmpty || _draining) return`（**line 272**），`_draining = true`（**line 273**），`addPostFrameCallback` 里 `unawaited(_drain())`（line 274-276）。
- `_drain`：`room_request_watcher.dart:283-309`。`while (mounted && _queue.isNotEmpty)` 里 `await showGeneralDialog<void>(context: context, barrierDismissible: true, ...)`（**line 287-305**）；`try/finally` 复位 `_draining = false`（line 307-309）。
- `_reply`：`room_request_watcher.dart:383-392`。`_controller?.sendIntent(op, {...r.payload, 'agree': agree})` 然后 `Navigator.of(ctx).pop()`（**line 391**）。`ctx` 是 `pageBuilder` 的 context（`_body(ctx, r)`，line 301）。

### 1.2 治疗弹层链路
- 入口：`room_game_page.dart:1056-1066`，`if (!isKp)` → `openTreatSheet(context, ctl: RoomScope.read(context).controller)`。
- `openTreatSheet`：`sheet_treat.dart:72-84` → `showRoomSheet<void>` → `showModalBottomSheet`（`room_sheet.dart:42`）。
- `showRoomSheet`：`room_sheet.dart:33-81`。外层 `ValueListenableBuilder<int>(_topSheetTick)` + `StatefulBuilder`，body 每次刷新重新构建（line 46-74）；`scope` 在 body 外用 `RoomScope` 重新提供（line 67-74）。
- `TreatSheet` 第一步 3 个 kind 按钮：`sheet_treat.dart:151-161`，`onTap: () => setState(() { _kind = k; _targetSeat = ''; })`。第二步（`if (kind != null)`）：「重选」+ 队友列表 + `TextField(checkValue)` + 「提交申请」按钮，line 165-219。
- `_submit`：`sheet_treat.dart:110-124`。校验 `_kind != null && _targetSeat.isEmpty` 则 `ctl.notice('请先选择治疗方式与队友'); return;`（line 112-115）；否则 `ctl.hostAction(kind.op, payload)`（**line 122**）→ `Navigator.of(context).pop()`（line 123）。
- `aid.apply` / `aid.psycho` POLICY = `[player, kp] + RoomConfirm.kp`：`room_types.dart:311-318`。权威端 `aidApply`（`room_model_actions_sheet.dart:1565+`）、`aidPsycho`（1689+）：需要施救者已绑卡且有技能值（`skillBaseOf`），失败只 `sysTo`（定向系统提示），**不弹模态、不进聊天栏**。

### 1.3 全屏聊天编辑器链路
- `ChatInputRow`（`gp_feeds.dart:690-823`）是 `GpFeeds(pane: chat)` 的子件：`gp_feeds.dart:356`。**KP / 玩家 / 旁观共用**（`_bodyOf` 里 `gpChat`、`gpPlChat` 都返回 `const GpFeeds(pane: FeedPane.chat)`，`room_game_page.dart:830-832`）。
- 输入框 `onTap: editable ? () => _openComposer(context) : null`（`gp_feeds.dart:778`，`editable = role != spectator`，line 763）。输入行另有一个「发送」按钮 `GpFeedsKeys.send` → `onTap: _send`（line 812-819）。
- `_send`（输入行）：`gp_feeds.dart:717-724`。`RoomScope.read(context)` → `text = _text.text.trim()` → `if (text.isEmpty) return;`（**line 720**）→ `setChatDraft('')` → `_text.clear()` → `sendIntent(RoomIntent.chat, {'text': text})`（**line 723**）。
- `_openComposer`：`gp_feeds.dart:736-758`。`await showChatComposer(context, initialText, onChanged: scope.local.setChatDraft, onSend: (text) { _text.text = text; _text.selection = ...; _send(); })`（**line 740-749**）。返回后 `if (!mounted) return;`（line 750），`draft = result ?? local.chatDraft`（**line 754**），`_text.text = draft`、`local.setChatDraft(draft)`（line 755-757）。
- `showChatComposer`：`sheet_chat_composer.dart:53-69`，`Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, ...))` —— **独立路由，在 `RoomScope` 子树之外**（该文件 line 8-10 明确「本页不读 RoomScope」）。
- `ChatComposerPage._send`：`sheet_chat_composer.dart:124-129`。`if (_closed) return; _closed = true;` → `widget.onSend(_draft.text)`（**line 127**）→ `Navigator.of(context).pop<String>()`（**line 128**，pop 出 `null`）。
- `ChatComposerPage.build`：`sheet_chat_composer.dart:132-197`。`Scaffold` + `AppBar`（关闭按钮 = `_finish`）+ `body: SafeArea > Padding > Column[ Expanded(TextField(autofocus:true, maxLines:null, expands:true)), SizedBox(10), Row(完成/发送, minSize 96×44) ]`（line 146-191）。**没有 `resizeToAvoidBottomInset` 显式设置，没有把底部 Row 包进可滚动容器**。
- `RoomUiLocal.setChatDraft`：`room_ui_local.dart:194-196`，**只赋值不 `notifyListeners()`**（设计如此，草稿不进事件流）。
- `RoomScope.read/of`：`room_scope.dart:37-48`，靠 `getInheritedWidgetOfExactType` / `dependOnInheritedWidgetOfExactType` 向上找；找不到会 `assert` 失败（debug）。

### 1.4 出站 / 收件人 / 刷新链路
- `RoomController.sendIntent/hostAction`：`room_controller.dart:65-80`，只是 `try/catch` 包 `session.*`，**没有全局 busy、没有全局 throttle**。`throttle`（line 106-115）是**按 key 分桶的 400ms**，全库只有两处调用：`gp_pl_char_card.dart:256`（`aid.apply` 急救按钮）与 `:358`（`madness.advance`）。**`sheet_treat.dart` 的 `_submit` 完全没用 throttle**；`ChatInputRow._send` 也没用。
- KP 侧刷新本机 UI：`HostingLocalSession` 构造里 `server.onHostPlans = pumpPlans`（`room_session_hosting.dart:37`）；`pumpPlans` 末尾 `_hub.notifyAll()`（`room_session_local.dart:184`）→ `session.notifyListeners()` → 驱动 `_onSession`。
- `plan(rec)` 收件人：`room_model_host_core.dart:320-380`。`RoomVis.seat` 事件**只发 `to` 目标玩家**，给其他在线玩家发 `SkipEnvelope`，**KP（host）不在 `roster`，收不到**（line 325-340）；`RoomVis.kp` 直接 `return out`（line 323）。默认广播 `to:'*'`（line 378）。
- `state.request` 写入 `requestsBySeat` + `pending`：`room_model_actions_sheet.dart:660-689`，`id = 'r$localSeq'`（**line 666**，唯一），`pending` 里那条 `kind:'state.request'` **没有 `op` 字段**（line 681-688），所以 `collectRoomPushRequests` 的 `if (op.isEmpty) continue`（`room_request_watcher.dart:168`）跳过它、不误弹。
- `chat` intent：`room_model_host_intent.dart:174-188`，`emit(RoomEvt.chat, ..., to:'*')`；`collectChats` 读 `state['chats']`（`feed_view.dart:144-161`）。KP 自己发言走同一条路（注释 line 173）。

### 1.5 KP dock 布局（只在 KP 侧成立的几何）
- `room_layout.dart:100-152`：P16 KP-3 **删掉最底 `gpStatus`（原 flex 5）**、**右列删 `gpCombat`（原 flex 32）**、**中排 41 → 46**；中排下段 `gpChat / gpLog / gpPriv` 各 `flex: 1`（line 148-152）。玩家档中排 `flex: 26`（line 190），`gpPlChat flex: 1`，另保留 `gpStatus flex: 7`（line 197）。
- `_slotView`：`room_game_page.dart:750-795`。`gpMap / gpPlMap / gpKpLeft` 走**紧约束** `ClipRect(child: body)`（line 774-778）；**`gpChat` 不在紧约束分支**，走 `SingleChildScrollView` + `ClipRect`，`tooNarrow` 时再叠一层横向 `SingleChildScrollView`（line 779-791）。
- 注释 `room_game_page.dart:770-772` 明确：这批「KP-3 删掉待办栏后，左栏底端 = 中排聊天栏底端」。

---

## 2. Bug 1（KP-1）

> 用户原话：「KP 被推送一次申请之后，再点击治疗按钮（弹窗后的 3 个按钮），就都没有反应了。其他玩家推送的申请好像也没反应。」

### 2.1 「被推送一次申请」之后，什么状态被改变了？

按证据逐项裁定：

| 候选状态 | 是否被改 | 证据 / 结论 |
|---|---|---|
| 请求队列 `_queue` | 是（消费 1 条） | `room_request_watcher.dart:286` `_queue.removeAt(0)` |
| `_seen` 去重集合 | 是（加入该 id，**永不移除**） | `room_request_watcher.dart:270` `_seen.add(r.id)`；只有 `didChangeDependencies` 里会话对象更换才 `clear()`（line 253-255） |
| `_draining` | 是（`true` → `finally` 里 `false`） | `room_request_watcher.dart:273, 308` |
| `_busy` / 全局 throttle | **否** | `room_controller.dart` 无全局 busy；throttle 按 key 分桶且治疗弹层/聊天发送都不调用（§1.4） |
| `RoomUiLocal` | 否 | 推送链路不碰 local |
| `gate` | 否 | `RoomGate` 无缓存、只读 POLICY（`room_controller.dart:28-36`） |
| **路由栈** | **是（关键）** | 推送弹窗是 `showGeneralDialog` 推的一条 `RawDialogRoute` + `ModalBarrier`（`room_request_watcher.dart:287-305`）。关闭靠 `_reply` 里的 `Navigator.of(ctx).pop()`（line 391）。**弹窗生命周期内，最顶上一直压着这条 modal route** |
| `FocusScope` | 是（弹窗抢焦点） | `Dialog` route 默认会把焦点挪进弹窗；关闭后焦点归还时机由框架决定 |
| 权威态 `pending` / `requestsBySeat` | 是（新增项；点同意才清） | `room_model_actions_sheet.dart:680-688`；`settleRequest` 在 `consent/confirm` 里清（`room_model_host_intent.dart:378-399`） |

**结论【已证】**：推送一次真正持久改变的，是 **`_seen` 里多了一个 id + 路由栈上多/少一条 modal route + `_draining` 的一次翻转**。其中 `_seen` 不去重键唯一性、`_draining` 是否复位、modal route 是否彻底出栈，是后面三节所有假设的公共底座。

### 2.2 治疗弹层的 3 个按钮各自 `onTap` 现在做了什么？为什么「都没反应」？

「弹窗后的 3 个按钮」按最贴合代码的解读 = `sheet_treat.dart:151-161` 的 3 个「选治疗方式」按钮（急救 / 医学 / 精神分析）：

- 每个 `onTap: () => setState(() { _kind = k; _targetSeat = ''; })`（`sheet_treat.dart:157-160`）。
- `RoomTap` 的点击门是 `InkWell(onTap: enabled ? onTap : null)`（`room_panel_kit.dart:230-234`），`enabled` 默认 `true`（line 160），这 3 个按钮**没有传 `enabled`**，所以恒可点。
- 回调里**没有 early return、没有 `hostAction`、没有 domain 调用**——纯本地 `setState`。`_submit`（提交按钮）才发包，且 `hostAction`（`room_controller.dart:74-80`）是 `void` 异步、`try/catch` 转 `notice`，不会阻塞。
- `p16_wave1_sheets_test.dart:584-589` 已实测这 3 个 kind 按钮点得动。

**因此「都没反应」在代码层不可能是 `enabled:false`、回调 early return、或 hostAction 被 domain 拒**（这三条对 3 个 kind 按钮都不成立）。能成立的只剩两类：

1. **【强疑·主因】点击没命中**：上一条 modal route（`showGeneralDialog`）没彻底出栈，残留的 `ModalBarrier` / 半透明遮罩盖在 `showModalBottomSheet` 的治疗弹层之上，吞掉所有 `InkWell` 命中；或 `FocusScope` 没归还，第一次点击只被当成「失焦/收键盘」消费掉。这与「被推送一次申请之后」这个时序前缀严丝合缝。
2. **【存疑·真机层】弹层根本没重建 / 没打开**：`showRoomSheet` 的 body 被 `SingleChildScrollView` + `ConstrainedBox(maxHeight: 0.72 屏高)` 包住（`room_sheet.dart:62-75`），KP dock 的格子高度本就被 flex 压过；若推送弹窗关闭动画与 bottom sheet 打开动画交叠，真机上可能出现「弹层出来了但按钮落在裁切区 / 命中区外」。

> 另有一个**语义层面的「没反应」【已证】**：即便提交成功，`aid.apply/aid.psycho` 是 `RoomConfirm.kp`（`room_types.dart:311-318`），权威端只把请求放进 `pending` 等 KP 点「同意」，不会立刻结算；UI 只在 `sheet_treat.dart:112-114` 对「没选方式/没选队友」给 `notice`，**提交成功后没有任何反馈**（既无 notice、也无「已提交待同意」提示），且 **`aid.apply` 失败只 `sysTo` 定向提示**（`room_model_actions_sheet.dart:1573/1577/1583/1588/1592/...`），KP 侧看不到聊天栏变化。用户很容易把「已提交但需确认、无提示」当成「点了没反应」。

### 2.3 「其他玩家推送的申请没反应」是否与 Bug 1 同一根因？

**不是单一根因，是三条独立断链叠加，其中一条与 Bug 1 共享底座（`_seen`/`_draining`），另两条是独立链路：**

- **共享底座**：`_draining` 若因 `showGeneralDialog` 的 future 未正常完成而没复位（或 route 未出栈），`_onSession` 的 `if (_queue.isEmpty || _draining) return`（`room_request_watcher.dart:272`）会让**之后所有新申请只入队、永不弹窗**。这同时解释「按钮没反应」和「新申请不弹」。见假设 B1-2。
- **独立断链①（去重键不唯一）【已证】**：`collectRoomPushRequests` 给 `hostRead.pending` 的高危动作生成 `id = 'pending:$op:$by'`（`room_request_watcher.dart:170`）。这个 id **只含 op + 发起人座位，不含该 pending 项自身的 `r$localSeq` 唯一编号**（对比 `room_model_actions_sheet.dart:666` 的 `id = 'r$localSeq'`）。同一玩家连续发起**两个同 op** 的高危动作（例如两次 `aid.apply`、两次 `state.edit.self`），两条 pending 项得到**完全相同的 id**；`_seen.add(r.id)` 第二次返回 `false`（`room_request_watcher.dart:270`），第 2 条**永远不入队、永远不弹窗**。这与「被推送一次申请之后……其他玩家推送的申请好像也没反应」字面吻合。
- **独立断链②（收件人裁剪 / 刷新口径）【已证·但本批有补偿】**：`state.request` / 高危动作的定向事件是 `RoomVis.seat` / `RoomVis.kp`，`plan()` 只发目标玩家、不给 KP（`room_model_host_core.dart:323-340`）；KP 能否刷新全靠 `HostingLocalSession` 的 `server.onHostPlans = pumpPlans`（`room_session_hosting.dart:37`）→ `pumpPlans` 末尾 `_hub.notifyAll()`（`room_session_local.dart:184`）。**真机公网/云房若走的不是 `HostingLocalSession`（`room_session_cloud.dart` / `room_session_remote.dart`），或 `onHostPlans` 未挂/被覆盖，KP 的 session 就不会 notify，`_onSession` 根本不跑** —— 这是「成员裁剪 `RoomVis`、`syncMembers`、`plan()` 收件人、`state['members']` 去重键 seat」这条线索真正指向的位置。需施工方确认真机用的到底是哪个 session 实现。
- **独立断链③（KP 无治疗入口）【已证】**：`room_game_page.dart:1056` `if (!isKp)`。KP 视角没有「治疗」按钮可点，也没有第二个 `openTreatSheet` 调用点（全库 grep 确认）。

### 2.4 至少 2 个互相独立、可证伪的假设

#### 假设 B1-1【已证·确定性静态 bug】`pending:$op:$by` 去重键不唯一 → 同玩家连续两次同 op 申请只弹一次
- **证据行号**：`room_request_watcher.dart:170`（`id: 'pending:$op:$by'`）、`:270`（`_seen.add(r.id)`）；对照 `room_model_actions_sheet.dart:666`（`id='r$localSeq'` 唯一）、`:680-688`（`pending.add` 不含唯一 id 之外的区分）。
- **若成立应该观察到**：让 `p1` 连续两次 `hostAction('aid.apply', {...})`（或两次 `state.edit.self` 不同值）→ `hostRead.pending.length == 2`，但 `collectRoomPushRequests(kpSession)` 里 `reply==confirm` 的条目**只有 1 个**（两条 id 相同被 `_seen` 合并）；`RoomPushKeys.root` 只弹 1 次，第 2 次无论怎么 `session.refresh()` 都不弹。
- **最小证伪**：在 `p10_t6_room_fixes_test.dart` 的「5 推送请求」组加一条最小用例：`mountRoom(tester, f, kHostSeat)` → `p1` 连发 2 次同 op 高危 action → `pumpAndSettle` → 断言 `collectRoomPushRequests(f.sessionOf(kHostSeat)).where((r)=>r.reply==RoomPushReply.confirm).length == 2`。**当前代码会红（得到 1）**；把 id 改成 `'pending:${roomText(q['id'])}:$op:$by'` 后转绿。这条改动同时证伪"是 domain 收件人丢包"（因为 pending 里明明有 2 条，只是 UI 去重键撞了）。
- **独立性**：只依赖 `collectRoomPushRequests` 的纯函数 + `_seen`，与路由栈 / 弹层生命周期 / 键盘完全无关。可在**纯函数层**单独证伪。

#### 假设 B1-2【强疑·需夹具】推送弹窗 route 未彻底出栈 / `_draining` 未复位 → 后续所有点击被 modal barrier 吞、新申请不再弹
- **证据行号**：`room_request_watcher.dart:287-305`（`showGeneralDialog` + `await`）、`:273`（`_draining=true`）、`:272`（`_draining` 时直接 return）、`:307-309`（`finally` 复位）、`:391`（`Navigator.of(ctx).pop()` 用的是 `pageBuilder` 的 `ctx`，而 `showGeneralDialog` 用的是 `_RoomRequestWatcherState.context`）。
- **若成立应该观察到**：推送弹窗点「同意」或点屏障关闭后，`Navigator` 栈里仍残留一条 `RawDialogRoute`（`tester` 里可用 `find.byKey(RoomPushKeys.root)` 之外再查 `ModalBarrier` 数量 / `Navigator` 的 route 数），或 `_draining` 仍为 `true`；此后打开 `openTreatSheet` 点第一个 kind 按钮，`_kind` 不变（第二步不出现）；再触发一条新申请，`RoomPushKeys.root` 不再出现。
- **最小证伪**：写一条**连续时序** widget 用例（步骤见 §2.7）：先弹一次推送 → 关闭 → 再开治疗弹层 → 点 `TreatSheetKeys.kind('急救')` → 断言第二步出现。**当前代码若红，即证明假设成立**；再在 `_drain` 的 `finally` 前加一行诊断打点（打印 `_draining` 与当前 route 数）确认是哪一环没复位。若该用例绿、而纯函数用例（B1-1）也绿，则假设被证伪，"按钮没反应"必须去真机焦点/键盘层找。
- **独立性**：只依赖 Navigator 路由栈与 `_draining` 生命周期，与去重键、domain 收件人无关。

#### 假设 B1-3【存疑·真机层，兜底】KP 视角会话未 notify / 用户其实在玩家侧
- **证据行号**：`room_session_hosting.dart:37`（`onHostPlans = pumpPlans`）、`room_session_local.dart:184`（`notifyAll`）、`room_model_host_core.dart:323-340`（KP 不在 roster）、`room_game_page.dart:1056`（KP 无治疗入口）。
- **若成立应该观察到**：真机 KP 侧 `hostRead.pending` 已经多了 1 条，但 `_RoomRequestWatcherState._onSession` 从未被调用（可在 `_onSession` 打点）；或用户操作截图里工具栏根本没有「治疗」按钮（说明报告里的"KP"其实是玩家视角/切过视角）。
- **最小证伪**：真机上在 `RoomRequestWatcher._onSession` 与 `collectRoomPushRequests` 各加一条临时日志，重现一次「玩家提交申请」，看 KP 端有没有进 `_onSession`；同时确认设备当前 `role`。**若日志进来了、pending 也变了、却仍不弹**，则证伪本假设、回到 B1-1/B1-2。

### 2.5 建议修复方案（精确到文件:行号）

按优先级，**先修 B1-1（确定 bug），再补 B1-2 的兜底，最后处理语义反馈**：

1. **`lib/ui/room/room_request_watcher.dart:170`** — `id: 'pending:$op:$by'` 改为带 pending 项自身唯一编号，例如 `id: 'pending:${roomText(q['id'])}:$op:$by'`（`q['id']` 即 `r$localSeq`，`room_model_actions_sheet.dart:666`）。**`payload` 保持 `{'op': op, 'by': by}` 不变**（domain 的 `confirm` 按 `op+by` 定位待办，`room_model_host_intent.dart` 的 CONFIRM 分支），否则会撞确认链路。同时补三件配套，否则「改了 UI 也一次改不对」：
   - **第二处 id 撞车（交叉验证补入）**：`checkRequest` 的 `id = 'c$localSeq'`（`room_model_actions_combat.dart:1327`）在 `for (final t in targets)` 循环**外**只生成一次，全体推送时所有 target 共用同一 id（`:1338-1359` 把同一 `id` 写进每个 `requestsBySeat[t]`）。KP 读 `hostRead.requestsBySeat` **全量**（`room_request_watcher.dart:181-193`），一次全体检定会拿到 N 条同 id 的 `RoomPushRequest` → `_seen.add` 只认第一条 → **KP 只弹 1 次**。修法要么在 UI 侧把 id 与 `entry.key`（seat）组合（`id: '${entry.key}:$id'`，最小、不碰 domain），要么在 domain 侧给每个 target 生成独立 id —— **但后者必须同步改 `RoomEvt.request` 定向事件里的 `id`（`room_model_actions_combat.dart:1362`），因为 `consent` 按 `id` 定位（`room_model_host_intent.dart:355`），只改一处会让玩家点同意时找不到卡片**。
   - **红线：`_seen` 不要动**。`_seen` 不去重是 P10 第 6 期刻意设计，被 `p10_t6_room_fixes_test.dart:562`「5D 去重：首屏已有 id 不弹；同一 id 只弹一次」钉死。要改的是**去重键的构造**（`:170` 与上面的组合），不是给 `_seen` 加 remove / 定期清理 —— 那样会把 5D 弄红并重弹历史待办（watcher 注释 `room_game_page.dart:313-318` 就是防这个）。
   - **连锁残留风险**：domain `confirmPending`（`room_model_host_intent.dart:482-491`）按 `op+by` 定位且循环**不 break**（`:484-486` 的 `idx` 会被覆写成最后一个匹配）。同 `by` 同 `op` 两条不同参数的 pending 时，KP 点「同意」只摘掉最后一条，第一条**永久残留**。所以 UI 去重键改对、两条都能弹出来之后，必须同步修 `:484-486`（加 `break` 或改用唯一 id 定位），否则用户会看到「弹了两条、同意了一条、另一条再也消不掉」。
2. **`lib/ui/room/room_request_watcher.dart:283-309`** — 给 `_drain` 加硬兜底：`await` 的 dialog 关闭与 `_draining` 复位解耦（例如用 `whenComplete`/超时，或在 `_onSession` 里检测「`_draining` 为 true 但栈顶已无 `RoomPushKeys.root`」时强制 `_draining=false` 并重新排一次 drain）；`_reply` 的 `Navigator.of(ctx).pop()`（line 391）改用与 `showGeneralDialog` 同一个 Navigator 引用，避免嵌套 Navigator 下 pop 错对象。
3. **`lib/ui/room/sheets/sheet_treat.dart:110-124`**（**本条已按交叉验证修正，勿按旧稿理解**）— domain **已经有**「已提交，等待确认」的 `sysTo` 定向提示（`room_model_host_intent.dart:331-339`，进 `act()` 的 `confirm` 分支时发），所以**不是「零反馈」**，而是「反馈只发给发起玩家（`sysTo` → `EVT.PRIVATE`），KP 侧看不到、且发起者本地也没有 block 级 banner」。`ctl.notice`（`room_controller.dart:155`）仍是合理的补充，但：① 它写的是 `local.notice`（本机 banner），与 domain 的 `sysTo` 是**两条不同通道、不冲突也不重复**；② `aid.apply` 失败时 domain 会另发 `sysTo`（`room_model_actions_sheet.dart:1573/1577/1583/1588/1592`），别叠出两条提示；③ 真正要向用户解释的是「提交后进入 `pending` 等 KP 同意，不会立刻结算」（`room_types.dart:311-318`），**建议改为在按钮文案 / 提交后本地提示里把「等 KP 同意」说清楚，而不是新增第二条成功提示**。
4. **`lib/ui/room/room_game_page.dart:1056`** — 若产品确认 KP 也要「治疗」入口：把 `if (!isKp)` 放开（`aid.apply/aid.psycho` POLICY 已含 kp，`gate.can` 允许）；**否则在施工单里明确回应用户「KP 通过推送弹窗同意玩家的治疗申请，不另设治疗按钮」**，别让施工方凭这句话去加一个本来不该存在的按钮。
5. **不改 domain**：`aid.apply/aid.psycho` 的 `RoomConfirm.kp`、`plan()` 收件人裁剪、`syncMembers` 口径都是 P10/P16 反复对拍过的既有契约，本批不要动。

**会不会撞到既有测试（可能转红的用例名）**：
- 改 `room_request_watcher.dart:170` 的 id：**高危**
  - `test/p10_t6_room_fixes_test.dart:677`「5F 两条数据源分别验：KP 走 hostRead.pending(CONFIRM)，玩家走 state[requests](CONSENT)」——它断言 `kpReqs.any(reply==confirm)`、`details` 含技能字段（line 695-699），不直接断言 id 字符串，**大概率不红**；但若施工方顺手改了 `title`/`details` 就会红。
  - `test/p10_t6_room_fixes_test.dart:562`「5D 去重：首屏已有 id 不弹；同一 id 只弹一次」——用的是 `pushRequest`（唯一 `r$localSeq`，走 `state['requests']` 路径，**不受 pending id 改动影响**），应保持不变；但要确认新用例不会让"同一 id 只弹一次"这条语义被误改。
  - `test/room_ui_confirm_flow_test.dart:98`「玩家提交 HP=7 → 入队且不生效 → KP 弹窗点「同意」→ 权威态真变 7」、`:154`「KP 弹窗点「拒绝」→ 数值不变，待办同样被消费」、`:181`「旁观者打开同一弹层：看不到队列」——都挂 `RoomRequestWatcher`，改 id 后需重跑确认。
  - `test/room_ui_kp_test.dart:406`「弹层不再有待处理区块；确认仍由居中弹窗走同一 confirm 载荷」、`test/room_ui_player_test.dart:169`「完整链路：绑卡 → … → 改状态请求 → KP 同意 → 数值生效」。
- 改 `sheet_treat.dart`：`test/p16_wave1_sheets_test.dart:567` 组三条 —— `:610`「急救 → aid.apply（skill=急救）」、`:615`「医学 → aid.apply（skill=医学）」、`:620`「精神分析 → aid.psycho（不带 skill）」。补 `notice` 不改变 `hostAction` 载荷，理论上不红；但 `:605` `expect(tester.takeException(), isNull)` 要保证 `ctl.notice` 在纯夹具里不抛。
- 改 `room_game_page.dart:1056`：**会撞工具栏结构断言**，需检索 `gpToolbar/treat`、`treatKey` 相关用例（本批新增的 P16 波2 总装用例），玩家档「治疗」按钮数量/顺序断言可能转红。

### 2.6 用户描述与代码行为不符（明确列出）

- **KP 视角没有治疗按钮**（§0-A）。这是最硬的一处不符。怀疑层面：① 用户实际在**玩家侧**操作（或同一设备切过视角，`KeyedSubtree` key = `pageKeyOf(role, inGame)` 会整棵子树重建，`room_game_page.dart:336`）；② 用户把**推送弹窗里的「同意 / 拒绝」**当成了「治疗按钮」；③ 真机上 KP 通过某个我们没找到的入口（全库 grep `openTreatSheet` 仅 1 处，可排除 lib 内，但需排除 `toolbarExtensions` 注入的扩展按钮）。
- **3 个 kind 按钮代码无阻塞**（§0-B）。怀疑层面：真机 **modal barrier 残留 / 焦点未归还 / 键盘命中层**（§2.2），而非 `enabled` / early return / domain 拒绝。
- **提交成功本来就「看不到反应」**（§2.2 末）：`RoomConfirm.kp` + 无 notice。怀疑层面：这可能才是用户真正想报的「没反应」，与「被推送一次申请」只是时间上碰巧相邻。

### 2.7 如何用 widget test 复现（最小夹具，给验收用例）

**要点：必须把 `RoomRequestWatcher` 和 `openTreatSheet` 放进同一棵 widget 树，构造「推送 → 关闭 → 再开弹层」的连续时序。现有 `p16_wave1_sheets_test.dart` 的 `_OpenButton` 夹具和 `p10_t6` 的纯 watcher 夹具都不满足。**

```dart
// 夹具骨架（复用 RoomUiFixture / mountRoom / _settle，见 p10_t6_room_fixes_test.dart）
final f = RoomUiFixture();
await f.boot(inGame: true);
useRoomScreen(tester, 900, 1600);          // 让 dock 生效（真机横屏档）
// 挂：RoomScope > RoomRequestWatcher > [一个能打开治疗弹层的最小宿主]
//     （宿主里放一个 RoomTap，onTap: () => openTreatSheet(ctx, ctl: f.controllerOf('p1'))）
await mountRoom(tester, f, kHostSeat);       // KP 视角

// ① 先制造一次「被推送一次申请」
await f.plSessions['p1']!.hostAction('aid.apply',
    <String, Object?>{'seat':'p1','targetSeat':'p1','skill':'急救'});
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsOneWidget);   // 第一次弹出

// ② 关闭推送（点「同意」；也可用 tapAt(Offset(4,4)) 点屏障）
await tester.tap(find.byKey(RoomPushKeys.agree));
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsNothing);

// ③ 再打开治疗弹层，点第一个 kind 按钮
await tester.tap(find.byKey(/* 宿主打开按钮 */));
await _settle(tester);
expect(find.byKey(TreatSheetKeys.root), findsOneWidget);
await tester.tap(find.byKey(TreatSheetKeys.kind('急救')));
await tester.pump();

// ④ 断言（bug 存在时这两条会红）
expect(find.textContaining('当前：急救'), findsOneWidget,
    reason: 'setState 后必须进入第二步');
expect(find.byKey(TreatSheetKeys.target('p2')), findsOneWidget);

// ⑤ 再推一条新申请，断言推送弹窗还能弹（验 B1-1 / B1-2）
await f.plSessions['p1']!.hostAction('aid.apply',
    <String, Object?>{'seat':'p1','targetSeat':'p1','skill':'医学'});
await _settle(tester);
expect(find.byKey(RoomPushKeys.root), findsOneWidget,
    reason: '同玩家第二次同 op 申请也必须弹（B1-1）');
expect(tester.takeException(), isNull);
```

**能稳定触发的关键**：`_settle` 要含 `tester.pumpAndSettle()` 让 `addPostFrameCallback` 的 `_drain` 与 dialog 关闭动画都走完；两次 `aid.apply` 必须是**同一 `by`、同一 `op`**（否则 B1-1 的 id 不会撞）。若 ④ 红 → 证明 B1-2；若 ⑤ 红而 ④ 绿 → 证明 B1-1；若都绿 → 两个假设都被证伪，转真机层 B1-3。

---

## 3. Bug 2（KP-5）

> 用户原话：「KP 现在点击聊天栏的输入框后进入全屏，编辑要发送的信息之后，点击发送没有任何反应，信息没有发送到聊天栏，已编辑的文字也还在保留着没有消失。」

### 3.1 从「点输入框」→「进全屏编辑」→「点发送」的完整调用链，及 `Navigator.pop` 与发包、清文本的先后顺序

```
点输入框 (TextField.onTap, gp_feeds.dart:778)
  └─ _openComposer(context)                         gp_feeds.dart:736
       ├─ scope = RoomScope.read(context)           :737  （捕获 controller/local）
       ├─ initial = _text.text 或 chatDraft         :738-739
       └─ await showChatComposer(...)               :740-749
            └─ Navigator.push(fullscreenDialog)     sheet_chat_composer.dart:59-68
                 └─ ChatComposerPage(autofocus:true) :132-197
                      · onChanged → setChatDraft      :166（逐字同步，不 notify）
                      · 点「发送」RoomTap            :182-189
                           └─ _ChatComposerPageState._send()   :124-129
                                ① _closed=true                :126
                                ② widget.onSend(_draft.text)  :127
                                     └─ _openComposer 的 onSend 闭包  gp_feeds.dart:744-748
                                          ├─ _text.text = text        :745
                                          ├─ _text.selection = ...    :746
                                          └─ _send()                  gp_feeds.dart:717-724
                                               a. RoomScope.read(context)      :718
                                               b. text=_text.text.trim()      :719
                                               c. if(text.isEmpty) return     :720  ← 唯一 early return
                                               d. setChatDraft('')            :721
                                               e. _text.clear()               :722
                                               f. sendIntent(chat,{text})    :723  ← 发包
                                ③ Navigator.of(context).pop<String>()  :128  ← pop 出 null
       └─ result = null → draft = result ?? local.chatDraft = ''       :750-754
            → _text.text = '' / setChatDraft('')                :755-757  （二次对齐，仍是空）
```

**先后顺序【已证】：发包（f） → 清输入行文本（e） → 清草稿（d） → `Navigator.pop`（③） → 回调用 `chatDraft` 二次对齐（仍空）。** 即「先发包、后 pop」，且**清文本发生在 pop 之前**。`ChatComposerPage` 自己的 `_draft`（全屏编辑器里的文字）不显式清空，它随 `Navigator.pop` 后整页 dispose（`sheet_chat_composer.dart:111-114`）一起消失。

### 3.2 「文字还在、没发出去」说明哪一步没执行？给证据行号

「文字还在 + 全屏没关 + 聊天栏没新消息」三者同时成立，能反推的**唯一代码级结论**：**`widget.onSend(_draft.text)`（`:127`）没有正常跑完**，或**`RoomTap(send)` 的 `onTap` 根本没触发**。因为：
- 若 `:127` 正常执行且 `text` 非空，`_send()` 必然走到 `:723` 发包、`:722` 清 `_text`、`:721` 清草稿；
- 发包后 `:128` 必然 `Navigator.pop`，全屏页必然消失（`:487` 的既有断言就是这么验的）；
- `text.isEmpty`（`:720`）是唯一 early return，但用户「编辑了要发送的信息」，正常情况下非空。

因此可能且仅可能：
1. **点击没命中「发送」按钮** —— `InkWell.onTap` 没被调用（真机键盘 / 焦点 / 几何 / 命中层）。`RoomTap` 本身 `enabled:true`（`sheet_chat_composer.dart:182-189` 未传 enabled），不是 `enabled:false`。
2. **`onSend` 回调抛异常** —— 一旦 `:127` 抛，`:128` 的 `Navigator.pop` **被跳过**，全屏页留在屏上、`_draft` 文字还在、`sendIntent` 也没发。最可能的抛点是 `onSend` 闭包里的 `_text`（`gp_feeds.dart:745`）：`_text` 属于**底层 `ChatInputRow` 的 State**，而全屏编辑器打开期间，若底层子树因 `KeyedSubtree`（`room_game_page.dart:336`，key 含 `inGame = isInGame(state)`）换 key 而重建，旧 State 已 `dispose()`（`gp_feeds.dart:711-715` 会 `_text.dispose()`），对已 dispose 的 `TextEditingController` 赋值会抛 `FlutterError`。
3. **`_closed` 已为 true**（`sheet_chat_composer.dart:125`），第二次点直接 return —— 但用户是第一次点发送，且 `_closed` 只在 `_finish`/`_send` 里置位，概率低。

### 3.3 这个全屏弹层是 KP 独有还是 KP / 玩家共用？如果共用，为什么用户只在 KP 侧报？

**【已证】共用**：`ChatInputRow` 挂在 `GpFeeds(pane: FeedPane.chat)` 里（`gp_feeds.dart:356`），`_bodyOf` 对 `gpChat` 与 `gpPlChat` 都返回 `const GpFeeds(pane: FeedPane.chat)`（`room_game_page.dart:830-832`），`showChatComposer` 也是一个全局函数、不判 role。KP、玩家都走同一份代码；只有 **spectator** 被 `editable` 挡掉（`gp_feeds.dart:763, 778, 803, 812-819`）。domain 侧 `chat` POLICY 也是 `[kp, player]`（`room_types.dart:243`），双方一致。

**所以「只在 KP 侧报」用代码逻辑解释不成立。** 能成立的差异只有三类，按可能性排序：

1. **【强疑】KP dock 几何 + 真机键盘**：KP 档中排 flex 41→46、删了 `gpStatus`/`gpCombat`（`room_layout.dart:100-152`），`gpChat` 落在 `_slotView` 的 `ClipRect + SingleChildScrollView`（`room_game_page.dart:779-791`）里；玩家档中排 flex 26 且保留 `gpStatus flex 7`（`room_layout.dart:190-197`），几何完全不同。**注意：全屏编辑器是独立路由，本身不受 dock 布局影响** —— 所以 dock 只能解释「聊天输入行被裁 / 用户点到的位置」这一半，不能解释「全屏页里的发送按钮点不动」。真正能解释「只在 KP 侧」的是**使用频次**（KP 写长段主持词、频繁用全屏，玩家几乎不用）+ **KP 侧会话事件更密集**（`inGame` 状态变化、推送、成员广播更容易触发底层子树重建 → 命中假设 3.2 的第 2 条）。
2. **【强疑】`onSend` 闭包引用的旧 State 失效**：KP 视角 `KeyedSubtree` key = `pageKeyOf(role, inGame)`（`room_game_page.dart:336`），`inGame = isInGame(state)` 随权威态翻转；KP 是权威端，state 变化最频繁，全屏编辑器打开期间底层 `ChatInputRow` 被重建的概率远高于玩家侧 → `onSend` 里 `_text.text = text` 抛异常 → pop 与发包全跳过。这能同时解释「只在 KP 侧」「文字还在」「没发出去」。
3. **【存疑·真机层】软键盘 / 焦点**：`ChatComposerPage` 的 `TextField` `autofocus:true`（`sheet_chat_composer.dart:156`）+ `maxLines:null` + `expands:true`，`Scaffold` 用默认 `resizeToAvoidBottomInset`（未显式设，line 134），底部 `Row(完成/发送)` 没有包进可滚动容器、没有 `SafeArea(bottom:true)`。真机键盘弹出后，第一次点「发送」常被 IME / 失焦手势消费（「点一下没反应、要点两下」），或底部 Row 被顶到键盘命中区之外。这与平台（Android/iOS）、键盘高度、`fullscreenDialog` 呈现方式强相关，widget test 的 FakeAsync + 固定 `viewInsets` 复现不出来。

> **与 team-lead 线索「dock 删节点 / `_slotView` 紧约束 / flex 41→46」的关系【已证】**：`_slotView` 的**紧约束分支只对 `gpMap/gpPlMap/gpKpLeft` 生效**（`room_game_page.dart:774-778`），`gpChat` 走的是**滚动 + ClipRect** 分支（line 779-791）。所以「紧约束」不是聊天栏的直接原因；但 flex 41→46 改变了 `gpChat` 格的实际高度，配合 `ClipRect` 会让 `ChatInputRow`（`GpFeeds` 默认 `height:220` + 标题行 + 输入行，`gp_feeds.dart:343-358`）更容易落到需要滚动才能完整触达的位置。这只影响「进全屏之前」的点击，不影响全屏页内的发送按钮。施工单不要把这个当主因改布局。

### 3.4 可证伪假设 + 最小证伪方法

#### 假设 B2-1【强疑·主因】`onSend` 闭包捕获的 `_ChatInputRowState` 在全屏页打开期间失效 → `_text.text = text` 抛异常 → `Navigator.pop` 被跳过
- **证据行号**：`gp_feeds.dart:744-748`（闭包引用 `_text` / `_send`）、`:711-715`（`dispose` 里 `_text.dispose()`）、`room_game_page.dart:335-336`（`KeyedSubtree` key 含 `inGame`）、`sheet_chat_composer.dart:127-128`（`onSend` 抛则 pop 不执行）、`gp_feeds.dart:750`（`if (!mounted) return`）。
- **若成立应该观察到**：全屏页开着时，让底层会话触发一次会让 `inGame` 翻转 / 整页重建的事件（例如 `f.sessionOf(kHostSeat).refresh()` 前先改 `state` 让 `isInGame` 变化，或直接 `pumpWidget` 重建宿主），再点发送 → `tester.takeException()` **非 null**（"A TextEditingController was used after being disposed" 或 "setState on unmounted"），且 `find.byKey(ChatComposerKeys.root)` 仍 `findsOneWidget`、`sent` 里 `RoomIntent.chat` 为 0。
- **最小证伪**：在 `p10_t7_c_feeds_test.dart` 的「⑥」用例里，于「打开全屏」与「点发送」之间插入一次 `await tester.pumpWidget(/* 重建宿主，模拟 inGame 翻转 */)`；**若 `takeException()` 非 null 且全屏不关，假设成立**。改法：把 `onSend` 改成不碰 `_text` —— 在 `_openComposer` 里用**捕获的 `scope.controller` / `scope.local`** 直接发包清草稿（见 §3.5），改完该插入重建的用例转绿即证伪。
- **独立性**：只依赖 State 生命周期与闭包捕获，与键盘、domain、路由几何无关；可在纯 widget test 里证伪。

#### 假设 B2-2【存疑·真机层】软键盘 / 焦点导致「发送」点击未命中 InkWell
- **证据行号**：`sheet_chat_composer.dart:156`（`autofocus:true`）、`:152-168`（`Expanded(TextField(expands:true))`）、`:170-191`（底部 Row 未包滚动 / 未 `SafeArea(bottom:true)`）、`:134`（`Scaffold` 未设 `resizeToAvoidBottomInset`）、`room_panel_kit.dart:230-234`（`InkWell.onTap`）。
- **若成立应该观察到**：真机上第一次点「发送」无反应、第二次点才有；或 `ChatComposerKeys.send` 的 `getRect` 落在 `MediaQuery.viewInsets.bottom` 覆盖区 / 屏幕外；widget test 里用 `tester.view.viewInsets` 注入真实键盘高度后，`tester.tap(..., warnIfMissed:false)` 的命中数变 0。
- **最小证伪**：widget test 里 `addTearDown(() => tester.view.resetViewInsets())`，用 `tester.view.viewInsets = FakeViewPadding(bottom: 320)` 模拟键盘，`pump` 后断言 `tester.getRect(find.byKey(ChatComposerKeys.send)).bottom <= 屏高 - 320`；**若按钮 rect 落在键盘区，假设成立**。最小改动证伪：给 `Scaffold` 加 `resizeToAvoidBottomInset:false` 或把底部 Row 包进 `SingleChildScrollView` / `SafeArea(bottom:true)`，注入同样键盘后按钮 rect 回到可视区且 `tap` 命中成功。
- **独立性**：只依赖平台键盘 / 几何，与 State 生命周期、去重键、domain 无关；需真机或 viewInsets 注入才能证伪。

#### 假设 B2-3【已证伪·排除项，写出来防止施工方走错】「KP 发 chat 被 domain 拒 / 被 throttle 吞」
- **证据行号**：`room_types.dart:243`（chat POLICY `[kp, player]` 免确认）、`room_model_host_intent.dart:97-110`（`_passSelf` 白名单含 `RoomIntent.chat`）、`:128-133`（`locked` 只对非 host 且 `_passSelf` 放行）、`:174-188`（KP 自己发言走 `to:'*'`）、`room_controller.dart:106-115`（throttle 按 key 分桶，`ChatInputRow._send` 不调用）。
- **结论**：**此路已排除**。KP 发 chat 不会被 POLICY 拒、不会被全局锁拦、不会被 throttle 吞；`p10_t7_c_feeds_test.dart:460-496` 用 `kHostSeat` 已实测发出且只发出 1 条。施工方**不要**去改 domain 的 chat 分支或 `RoomController.throttle`。

### 3.5 用户描述与代码行为不符（明确列出）

- **代码层发送链路无缺陷【已证，§0-C / §3.1】**，且先有 KP 视角专门测试通过。「点发送没反应、文字还在」在纯代码层找不到对应分支 —— 差异一定在**真机层**：键盘/焦点（B2-2）、路由栈与底层 State 生命周期（B2-1）、或用户实际点的是**输入行里的 `GpFeedsKeys.send`**（`gp_feeds.dart:812-819`）而非全屏页里的 `ChatComposerKeys.send`。
- **「已编辑的文字还在」的两种可能**：① 全屏页没关（`Navigator.pop` 被跳过，`_draft` 还在）；② 全屏页关了，但 `_openComposer` 的 `result ?? local.chatDraft`（`gp_feeds.dart:754`）把**没被清掉的 `chatDraft` 回填**到了原输入框。后者对应 `setChatDraft` 不 `notifyListeners()`（`room_ui_local.dart:194-196`）这一设计 —— 若 `onChanged` 逐字把草稿写进 `chatDraft` 而 `_send()` 因异常没执行 `setChatDraft('')`，`result=null` 时就会把整段草稿回填。这两条都能产生「文字还在」，验收用例要分别断言 `ChatComposerKeys.root` 是否消失、以及 `RoomKeys.gpChatInput` 的 controller.text 是否为空，才能区分。

### 3.6 建议修复方案（精确到文件:行号）

1. **`lib/ui/room/widgets/gp_feeds.dart:736-758`（主修，针对 B2-1）** — 把 `_openComposer` 的 `onSend` 与底层 `_ChatInputRowState` 解耦：在打开前捕获 `final controller = scope.controller; final local = scope.local;`，`onSend` 里**不再**写 `_text` / 不调 `_send()`，改为直接 `final t = text.trim(); if (t.isEmpty) return; local.setChatDraft(''); controller.sendIntent(RoomIntent.chat, {'text': t});`。`await` 返回后同理只对齐 `local.chatDraft`，并用 `if (!mounted) return` 保护。**这样发包/清草稿不再依赖可能已 dispose 的 `_text` 与旧 State.context**。注意保持「先发包、后 pop、再对齐」的顺序不变（`p10_t7_c_feeds_test.dart:483-495` 验的就是这个顺序与结果）。
2. **`lib/ui/room/sheets/sheet_chat_composer.dart:124-129`** — 给 `_send` 加 `try/finally`：`finally { Navigator.of(context).pop<String>(); }`，保证**即便 `onSend` 抛异常，全屏页也一定关闭**（不会留下「文字还在、弹层不关」的僵尸态）；异常本身仍应上报（`FlutterError.reportError` 或让 `tester.takeException()` 可见），不要静默吞。
3. **`lib/ui/room/sheets/sheet_chat_composer.dart:134-195`（针对 B2-2）** — `Scaffold` 设 `resizeToAvoidBottomInset: false`（或把 `body` 的 Column 包进 `SingleChildScrollView` 并把底部 `Row` 放进 `SafeArea(bottom: true)`），保证软键盘弹出后「完成 / 发送」Row 始终在可视命中区；`autofocus` 可保留（既有 `⑤` 用例依赖打开即可打字）。
4. **不改**：`room_ui_local.dart:194-196`（`setChatDraft` 不 notify 是设计）、`room_model_host_intent.dart:174`（KP chat 分支）、`room_controller.dart` 的 `throttle`（与 chat 无关）。

**会不会撞到既有测试（可能转红的用例名）**：
- 改 `gp_feeds.dart` 的 `_openComposer` / `_send`：**高危**，直接命中
  - `test/p10_t7_c_feeds_test.dart:406`「⑤ tap 聊天输入框 → 全屏编辑页；长文本「完成」写回原输入框 + 草稿同步」（验 `result` 非 null 时回填 `_text`）；
  - `:458`「⑥ 全屏「发送」→ RoomIntent.chat 发出、草稿清空、全屏页关闭」（`_host(f, kHostSeat, ...)`，断言 `:483-495`：发出且只发出 1 条、trim、`chatDraft==''`、`chatComposer` 消失、原输入框清空）；
  - `:500`「⑥b 旁观者：不渲染全屏入口、点输入框也不弹全屏」；
  - `:522`「⑧ 回归口径：enterText 不弹全屏、AI RP 与发送键都还在」；
  - `test/room_ui_feeds_test.dart:266-315` 的既有输入用例（`gp_feeds.dart:730` 注释明确点名：不能挂 `FocusNode.onFocusChange`，否则这批全崩）。
- 改 `sheet_chat_composer.dart` 的 `build` / `Scaffold`：`test/p10_t7_c_feeds_test.dart:418-442`（`chatComposer*` key 定位、`findsNothing` 断言、完成按钮写回）、`:470-496`（发送）。加 `resizeToAvoidBottomInset` 不改 key、不改按钮，理论上不红；但 `⑤`/`⑥` 的 `_settle` 与 `pump` 次数要重跑。
- **不要**动 `GpFeedsKeys.send`（`gp_feeds.dart:812-819`）的 `onTap: _send` 签名，否则 `:523` 组「AI RP 与发送键都还在」及输入行单测会红。

### 3.7 如何用 widget test 复现（最小夹具，给验收用例）

**要点：现有「⑥」夹具（`_host(f, kHostSeat, const GpFeeds(...))`）是绿的，不能复用。要么把它升级成完整 `RoomGamePage` dock 夹具，要么在「⑥」里插入一个能触发 B2-1 的重建，并注入真机 viewInsets 覆盖 B2-2。**

```dart
final f = RoomUiFixture()..bootSync();
useRoomScreen(tester, 1280, 800);            // 平板横屏 → 触发 KP dock（room_layout.dart:100-152）
await tester.pumpWidget(/* RoomScope > RoomGamePage(role: kp, ...) */);  // 完整页，含 RoomRequestWatcher + _slotView
await tester.pumpAndSettle();
f.clearSent();

// ① 点输入框进全屏
await tester.tap(find.byKey(RoomKeys.gpChatInput));
await tester.pumpAndSettle();
expect(find.byKey(GpFeedsKeys.chatComposer), findsOneWidget);

// ② 输入 + 注入真机软键盘（覆盖 B2-2）
await tester.enterText(find.byKey(ChatComposerKeys.field), 'KP 主持词');
tester.view.viewInsets = const FakeViewPadding(bottom: 320);  // addTearDown(resetViewInsets)
await tester.pumpAndSettle();

// ③ 可选：触发一次底层子树重建（覆盖 B2-1）—— 让 isInGame / 权威态翻转后 pumpWidget
//    （若施工方不愿重建整页，至少在「⑥」里插一次 pumpWidget 同构宿主）

// ④ 点发送（用 warnIfMissed:false 才能暴露「没命中」而不是直接测试失败）
await tester.tap(find.byKey(ChatComposerKeys.send), warnIfMissed: false);
await tester.pumpAndSettle();

// ⑤ 四条断言，任一红即定位到对应假设
expect(find.byKey(GpFeedsKeys.chatComposer), findsNothing,
    reason: '发送后全屏页必须关闭（pop 没被跳过）');
expect(f.sent.where((e) => e['op'] == RoomIntent.chat), hasLength(1),
    reason: '必须发出且只发出一条 chat');
expect(f.localOf(kHostSeat).chatDraft, '', reason: '草稿必须清空');
expect(tester.widget<TextField>(find.byKey(RoomKeys.gpChatInput)).controller!.text, '',
    reason: '原输入框必须为空（不能被 result ?? chatDraft 回填）');
expect(tester.takeException(), isNull, reason: 'onSend 不许抛 used-after-dispose');

// ⑥ B2-2 的几何断言
final sendRect = tester.getRect(find.byKey(ChatComposerKeys.send));
expect(sendRect.bottom, lessThan(800 - 320 + 0.001),
    reason: '发送按钮必须落在键盘区之上');
```

---

## 4. 给施工单的落地顺序（一句话版）

1. **先修 B1-1**（`room_request_watcher.dart:170` 去重键带 `q['id']`）——这是唯一「静态代码确定错、改法唯一、可纯函数证伪」的点，且能解释「第一次推送之后，同类型申请不再弹」。
2. **再各写一条「连续时序 / 完整 dock 夹具」的验收用例**（§2.7 / §3.7），用它们来决定 B1-2、B2-1、B2-2 哪个在真机夹具里真的复现 —— **不要凭本报告直接改布局或 domain**。
3. **B2 的主修放在 `gp_feeds.dart:736-758` 的 `onSend` 解耦 + `sheet_chat_composer.dart:124-129` 的 `try/finally` pop**，这两处能同时兜住「文字还在、没发出去」的两种成因，且不碰既有 chat 语义与 2235 例里最敏感的 `⑤`/`⑥`/`⑧` 断言（改完必须重跑）。
4. **明确回应用户两处描述不符**：KP 视角没有治疗按钮（`room_game_page.dart:1056`）；KP 发 chat 在代码层是通的（已有 KP 视角专门测试）。避免施工方按字面去加一个本不该存在的按钮、或去改 domain 的 chat 分支。
5. **全程不要动** `aid.apply/aid.psycho` 的 `RoomConfirm.kp`、`plan()` 收件人裁剪、`syncMembers`、`RoomUiLocal.setChatDraft` 不 notify、`RoomController.throttle` —— 都是对拍过的既有契约。

---

## 5. 与 `researcher-kp-p17` 的交叉验证（结论对齐 / 一处分歧 / 报告增补）

> 来源：`researcher-kp-p17` 对齐消息（`_p17_kp_landing.md` §KP-1 / §KP-5）。本节是两份报告避免施工单采纳矛盾口径的裁定记录。本人结论**已通过 SendMessage 同步 team-lead**，任务 #57 已 completed，本报告是唯一写入文件。

### 5.1 一致并采纳（他补充了我没覆盖的证据）
- **`_seen` 去重 + `pending:$op:$by` 不唯一**：与我 B1-1 完全同构。他额外补了 **`checkRequest` 的 `id='c$localSeq'` 全体推送复用**（`room_model_actions_combat.dart:1327, 1338-1368`）—— 已核验成立，并已补进 §2.5 建议 1 作为「第二处 id 撞车」。这是 KP 侧读全量 `requestsBySeat` 时才会暴露的撞车，与 UI 自拼的 `pending:` 键是两类不同来源。
- **KP 治疗按钮只在 `!isKp`**（`room_game_page.dart:1056`）：与我 §0-A 一致。
- **「别的玩家看不到别人申请」是 SEAT 定向裁剪设计**：`p10_t6_room_fixes_test.dart:646-660` 的 `findsNothing` + `jsonEncode(state)` 断言钉死（`RoomVis.seat` → `plan()` 只发 `to`，`room_model_host_core.dart:325-340`）。**但必须区分**：这条只约束**玩家**；**KP 读 `hostRead.requestsBySeat` 全量，本就该看到所有待办**（`room_request_watcher.dart:181-193`），所以「KP 收不到新申请弹窗」不是设计、是 bug（对应我 §2.3 独立断链② + B1-1/B1-2）。施工单别把 KP 侧问题也当设计放过。
- **`act()` 的 pending 去重**（`room_model_host_intent.dart:307-323`）与 `confirmPending`（`:476-510`）：核验成立，已补进 §2.5 建议 1 的「连锁残留风险」。补两点修正：① `:309-311` 的判据含 `jsonEncode(q['p']) == sig`，**比 UI 的 `pending:$op:$by` 严格**，同 op 不同参数不会误吞，`:316-319` 明确回「请勿重复提交」—— 是**设计上的防重复提交**，不是把不同申请误吞；② **KP 自己发起时 `:304-305` 直接 `applyAction` 不进 pending**（`confirm == RoomConfirm.kp && seat == kHostSeat`），所以 C 只对「玩家提交」成立、对「KP 提交」不成立 —— 这反过来再次印证 §0-A（KP 无治疗入口）。

### 5.2 分歧（需施工单注意，勿采纳两套矛盾口径）

**他的 B 主张「watcher modal barrier / `_draining` 卡死」同时解释 KP-1 与 KP-5；我判定：对 KP-1（Bug1）成立且与我 B1-2 同构，但外推到 KP-5（Bug2）不成立。**

反证（均为用户操作序列 + 代码事实）：
1. 用户描述是「点聊天输入框 → **成功进入全屏** → **编辑文字** → 点发送」。若 watcher 的 modal barrier 仍挂在栈顶，用户**连第一步「点聊天输入框」都做不到**（barrier 吃全页点击，`room_request_watcher.dart:287-305`）。既然进全屏、编辑都成功，说明当时栈上**没有** watcher barrier。
2. 若 barrier 是在编辑期间才因新推送弹出，`showGeneralDialog` 会 push 到 root Navigator 栈顶、**盖在全屏编辑器 `ChatComposerPage` 之上**，用户看到的是居中对话框、`ChatComposerKeys.send` 被遮住，不会描述成「点击发送没反应、已编辑的文字还在」。
3. 他引的旁证 `p10_t6_room_fixes_test.dart:700-703` 必须 `tapAt(4,4)` 点屏障才能继续 —— 这恰好说明 **barrier 存在时连测试都要显式点掉才能往下走**；KP-5 用例（`p10_t7_c_feeds_test.dart:462-497`）能一路点到发送，正说明其夹具里 barrier 不在（`_host` 是最小 shell、不含 watcher，这点我与他一致）。
4. `_closed`（`sheet_chat_composer.dart:100, 125`）我也核过：只在 `_finish` / `_send` 里置位，用户第一次点发送时为 `false`，不是主因。

**我维持 KP-5 主因在 `onSend` 闭包层**：B2-1（全屏页打开期间底层 `ChatInputRowState` 因 `KeyedSubtree` key 含 `inGame` 而重建 → `_text.text = text` 抛 used-after-dispose → `Navigator.pop`(:128) 被跳过 → 文字还在 + 没发包）与 B2-2（真机键盘 / `autofocus` + `expands` 让底部「发送」Row 落进键盘命中区）。
**唯一能让 B 对 KP-5 成立的边界**：真机上弹窗关闭后残留一条**视觉透明但命中仍在**的 route（barrier 看不见却仍吞点击）。此为真机层低置信假设。

**裁定方式（写进施工单）**：用 §3.7 的完整夹具（完整 `RoomGamePage` + watcher + dock，而非 `_host` 最小 shell）跑两条变体 —— 变体甲：先弹一次推送并正常关闭，再走全屏发送；变体乙：在全屏打开后插入一次底层子树重建。若甲红、乙绿 → 他对（B 共因）；若甲绿、乙红 → 我对（B2-1）。**不要凭任一报告直接改布局或 domain。**

### 5.3 我报告的自我修正（已改上文）
- §2.5 建议 3 原写「已入 pending 但零反馈」—— **错**。domain 已有 `sysTo`「已提交，等待确认」（`room_model_host_intent.dart:331-339`），只是只发给发起玩家、KP 看不到。已改为「把『等 KP 同意』说清楚」而非新增第二条成功提示。
- §2.5 建议 1 原只提 `pending:$op:$by` 一处 —— 已补 `c$localSeq` 第二处、`_seen` 不可改的红线、`confirmPending` 不 break 的连锁残留（改对 UI 去重键后必须同步修，否则「弹两条、同意一条、另一条永久残留」）。
