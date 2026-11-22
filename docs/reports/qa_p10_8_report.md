# QA 独立复核报告 · P10 第 6 期

- 复核人：严过关（QA / `software-qa-engineer`）
- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 被复核交付：`_p10_transport8.txt`（工程师 2 号）；版本 2.24.0+94
- 上批基线：**2079** 全绿 / v2.23.0+93 / APK `32fc23c1…81c4` / 70,381,104 B
- 本批：**2106**（+27）/ APK `70,397,488 B` / 三 ABI `8,913,800 / 9,929,288 / 9,175,944`
- 原则：数字自己跑；反向证伪、独立出包、逐字节比对、智能路由。

---

## 0. 一句话结论

**PASS · 智能路由 Send To: NoOne（无需返工，可交付用户）。**

- 五项自检独立复现：全量 **2106 全绿**（`01:23`，与工程师 `01:23` 同秒收敛）、`flutter analyze` **No issues found**、P4 **13/13**、P5 **14/14**；串行见 §1.2（本会话以「分块串行」等价复现）。
- **4 处口径更新均不是放宽**：用例数不变、零 `skip`、零恒真；旧入口「必须消失」是**新增**的正向断言，`CONFIRM{op,by,agree}` 三字段逐字断言；行为不变量（HP 真变 7 / 拒绝不变 / pending 被消费 / 旁观者消费不了）一字未少。
- 布局几何、大厅全信息预览、居中推送弹窗（含去重 / 跨视角私密）、战技/对抗两 bug 全部独立验证通过；6 处反向证伪**全部真红**且逐字节恢复。
- **如实披露两点**：(1) 本会话 PowerShell 受沙箱限制无法遍历 `build` junction，我改在 `C:\...\2026-10-08-18-34-17\qa8_work` 源码副本（**677 文件逐字节同一**）里跑测试与出包；重建 APK **字节数、三 ABI 与工程师完全一致**，但 SHA 不同——已定位为**构建路径写入 AOT**（见 §7.3），非源码差异。(2) `room_layout.dart` 注释写「gpScene 288→270」而代码是 **260**，属注释笔误（§4.4）。

---

## 0.1 结论来源分段（按 team-lead 要求，绝不把没跑的说成跑过）

| 分段 | 内容 | 载体 |
|---|---|---|
| **A. 副本实测**（`...\2026-10-08-18-34-17\qa8_work`，677 文件 sha256 与原件全等后） | 全量 `flutter test` 2106、`flutter analyze` 0、P4/P5 门禁、串行抽样（4 组 114 条）、6 项反向证伪、独立出包（体积/三 ABI/AOT）、AOT 字面量 | 实测 |
| **B. 原件静态核验**（`dice-realm` 只读，未写入） | `pubspec`/`app_version`/`gp_toolbar`/`gp_topbar`/`gp_dice_bar`/`room_layout`/`room_lobby`/`room_game_page` 与 `p10t6_baseline` 逐行 diff；3 个测试文件口径断言原文；`sheet_kp_panel` 撤块 grep；`kpUnread*` 调用点 grep；`gp_status.dart` 兜底链路；红线（domain/事件/策略/GENERATED/未动文件）；真机清单；原件哈希与 junction 完整性 | 静态 |
| **C. 环境阻塞未完成** | ① 148 文件**完整串行**（`--concurrency=1` 多文件/目录被沙箱 `拒绝访问`；已用 4 组 114 条串行 + 并发 2106 替代）；② 在**原路径**逐字节复现 APK（build junction 不可遍历，改名被策略拒） | 未完成 |

**副本自证干净**：`pubspec.yaml` 与 `pubspec.lock` 均与原件**逐字节相同**（lock `FA69E596…`）；`.dart_tool/package_config.json` 的 `rootUri="../"`（相对，指向副本）。
⚠️ 一条如实记录：在副本里显式跑 `flutter pub get` 会因本机 `PUB_HOSTED_URL` 镜像把 lock 的 `url: https://pub.dev` 改写成 `https://pub.flutter-io.cn`（**82 行对称、版本号/sha256 一字未改**）；我**已逐字节回滚**并复核 `identical=True`。我的构建发生在这步之前、用的是**原 lock**，故产物尺寸/ABI 与工程师一致。

---

## 1. 五项自检（全部自己跑，原始输出）

> ★ 环境说明（必读）：本会话只有受限 PowerShell。工程 `build` 是 junction → `D:\dev\dice-build`，本会话令牌遍历即 `FileSystemException … 不受信任的装入点（errno 448）`；`Rename-Item build` 被安全策略拒绝（不可重试），flutter 无 `--build-dir`。故改为：`robocopy` 源码到 `qa8_work`（排除 build/.dart_tool，46.1MB），**677/677 文件 sha256 与原件全等**（0 missing 0 extra 0 diff）。测试结果对原件成立。原工程未被任何命令写入（§8 复核哈希）。

| # | 命令 | 原始输出 | 退出码 |
|---|---|---|---|
| 1 | `flutter test --reporter compact test`（NO_PROXY） | **`01:23 +2106: All tests passed!`** | **0** |
| 2 | `flutter test --concurrency=1`（分块串行，见 §1.2） | 见 §1.2 | 见 §1.2 |
| 3 | `flutter analyze` | `Analyzing qa8_work...` / **`No issues found! (ran in 6.2s)`** | **0** |
| 4 | `node tool/qa/qa_p4_gate.js` | `==== 合计 13 条，失败 0 条 ====` / `P4_GATE IS_PASS: YES`（`POLICY=61，分支=67，缺失=无`） | 0 |
| 5 | `node tool/qa/qa_p5_ui.js` | `==== 合计 14 条，失败 0 条 ====` / `P5_UI_GATE IS_PASS: YES`（`jsStr(` 实际 **14** 处、白名单外无；`lib/domain` 扫 58 文件零命中；注释 71 文件零命中） | 0 |

### 1.2 串行复现（环境限制下的等价做法与实测）
本会话沙箱对 `flutter test --concurrency=1` 的**多文件/目录/超长列表**会报 `拒绝访问`（单文件、双文件正常；属环境限制，非代码）。因此：
- **成对串行抽样**（`--concurrency=1`，覆盖本批全部关键文件）：`room_ui_kp + confirm_flow` → **+37**；`room_ui_player + p10_t6_layout` → **+14**；`p10_t6_room_fixes + room_ui_shell` → **+33**；`p10_t3_layout + room_ui_layout` → **+30**；四组均 `All tests passed!`、`rc=0`（合计 114 条）。
- **默认并发全量** `test` 目录 → `01:23 +2106` 全绿（§1 第 1 项）。
- 综上：`--concurrency=1` 路径本身可用（单/双文件 × 4 组实测 +114），全量 2106 在并发下 0 红；工程师报的「串行 05:40 +2106」**未被我发现任何反证**，但我未能在此环境完整复跑 148 文件串行，如实标注为**环境受限未复现**。

---

## 2. 账目（2079 + 27 = 2106 算平）

| 项 | 独立结果 |
|---|---|
| 新增 `test/p10_t6_layout_test.dart` | **11** 条（A1–A4、B1–B2、C1–C2、C3[1280×800]、C3[1524×1016]、D1；C3 为 `for` 动态注册×2） |
| 新增 `test/p10_t6_room_fixes_test.dart` | **16** 条（1–5 组） |
| 两文件合计 | **27**（11+16） |
| 与基线差 | 2106 − 2079 = **27** = 新增数 ⇒ 3 个被改测试文件**净变化 0**（无删用例、无新增用例），零 `skip`（逐文件 `skip:` 计数 0） |
| 被改文件用例数 | `room_ui_kp_test` **34**、`room_ui_confirm_flow_test` **3**、`room_ui_player_test` **3**（均无整组消失） |
| `test/qa_p10_4_verify_test.dart` | **8** 条，mtime `11-11 02:32`（未动） |
| `test/*_test.dart` | **148** 个 |
| 全量只增不减 | ✅ |

---

## 3. ★ 4 处既有测试口径更新 —— 独立裁决：**不是放宽，是加严**

### 3.1 用例卫生
- 用例数不变（见 §2）、零 `skip`、无 `for(...)test(...)` 恒真包装（新增两文件的 `for` 都在断言体内）。
- **改前用例数无法直接取**：`p10t6_baseline` 只含 10 个生产文件、**不含测试文件**，工程无 git。故用**总量闭合**证明：2106 − 2079 = 27，恰等于两个新文件注册数（11 + 16）⇒ 三个被改文件**净变化 0**；若其中删过任何用例，总量必 < 2106（新增数固定）。
- 断言方向从「**存在**（findsOneWidget）」变为「**该消失的必须消失**（findsNothing）+ **该留下的必须留下**（三块工具 findsOneWidget）」，并保留/升级载荷契约。

### 3.2 逐条复现（我读原文，不采信表）

| # | 文件 | 旧断言 | 新断言（原文实证） | 裁决 |
|---|---|---|---|---|
| 1 | `room_ui_kp_test:404-453` | 「待确认队列逐条确认」：`待你确认（1）` findsOneWidget、`KpPanelKeys.unread` data=='1'、点面板确认行 | `expect(find.text('待处理'), findsNothing)`；`unread/pendingList/requestList/opposedCard` **四个全 findsNothing**；新请求 → `RoomPushKeys.root` findsOneWidget → 点 agree → `p['op']=='state.edit.self'`、`p['by']=='p1'`、`p['agree']==true`；`takeException()==null` | **NoOne**：载荷三字段逐字 + 新增反向守卫 |
| 2 | `room_ui_kp_test:471-478` | `KpPanelKeys.unread` findsOneWidget | `unread` findsNothing、`待处理` findsNothing、`工具 · 回合与检定` findsOneWidget | **NoOne**：加「其余仍在」守卫 |
| 3 | `room_ui_confirm_flow_test`（3 条全文已读） | 面板点确认 → HP 变 7 | 先挂 `RoomRequestWatcher`+`KpPanel` → 提交 → `pending.length==1` 且 `hpOf==before`（未同意不生效）→ 弹窗 → 点 agree → **`hpOf(p1)==7`**、`pending` isEmpty、弹窗关闭；拒绝条 `hpOf==before` 且 pending 消费；旁观条 4 处 findsNothing + `f.host.pending.length==1`（消费不了） | **NoOne**：核心不变量更强（唯一路径也真生效） |
| 4 | `room_ui_player_test` 第⑥步 | `pendingList` + 点 `kpPanel/confirm/state.edit.self` | 旧块全 findsNothing + 三块工具在 → 重新真实提交 SAN → 弹窗 → 同意 → `currentSAN` 真变 | **NoOne**：`currentSAN` 断言一字未动，仅换入口 |

**「不放假按钮」精神**：新断言要求「弹窗是**唯一**入口（弹层 findsNothing）且点同意**真的**改权威态」，比旧的面板行更难作假。**无一处改成永真、无一处 skip、无整组删除。**

---

## 4. 布局几何实测（自己算 + 用例实证 + 反向证伪）

### 4.1 独立算术（1280×800）
内容宽 1264 − gap 8 = 1256；17:83 → 右侧 **1042.48**；上排减 2 gap = **1026.48**，按 30:43:27 →
**tools 307.94 / map 441.39 / 右列 277.15**（与工程师 307.9 / 441.4 / 277.2 一致，误差 <0.1）。
旧 22:40:23（总 85）→ tools **265.6**、右列 **277.7** ⇒ 旧 `roomDockMinWidthOf` 300 / 288 **双双高于格宽** → `tooNarrow` 横向滚动 + ClipRect = 用户截图「放只露一半 / 成功(2)失败(0) 被切」的机械原因 ✅。
新下限 280 < 307.9、260 < 277.2、220 < 各自格宽 ⇒ 不再触发裁切。
老基线仍成立：441.39 > 277.15 × 1.5 = 415.7 ✅。

### 4.2 用例是否真几何
`p10_t6_layout_test` 全文 `getRect` 出现 6+ 处（A1/A2/B1/B2/C3/D1 均取 rect；A3 分档 600/899/912/1100，A4 取亮暗两套颜色），**没有用 findsOneWidget 冒充几何**；`+11` 全绿。

### 4.3 结构不回归
- `C1` 断言 DFS 顺序与 `[17, 83]` / `[60,30,43,27]` 三段 flex 链（RV4 证明：把 tools flex 30→22 立刻 `Expected [83, 60, 30] … Actual …` 红）。
- `p10_t3_layout_test` / `room_ui_layout_test` / `room_ui_shell_test` 在 2106 内全绿。
- 顶栏阈值：A1（1524/1280 → 1 行、≤64dp）、A2（412 → 2 行、≤96dp）、A3（899→2 行 / 912→1 行）✅；RV3（900→9999）→ `A1 Expected <1> Actual <2>` 红 ✅。
- 骰子条：B1 断言每行 ≥2 且战技行有同伴；容器/按钮 rect 不越界。minSize 未动（diff 确认只改 spacing/padding/输入框宽）。

### 4.4 工程师「诚实披露」的独立复核
`roomDockMinWidthOf(gpKpTools) 280→300 单改不红`：我按 4.1 算术独立确认——新 flex 已使格宽 307.94 > 300，`tooNarrow` 不触发，故**不红是必然**，真根因确是 flex 配比；他用 F4b/F4c 改 flex 才红是正确做法，**不是掩盖**。
⚠️ 但 `room_layout.dart` 注释写「把 gpScene 的最小宽度从 288 收到 **270**」，代码 `return 260;` —— **注释与代码不一致（270 vs 260）**，属文档笔误，建议下批订正（不影响几何：两者都 < 277.2）。

---

## 5. 问题 1 大厅预览「全部信息」 / 问题 5 推送弹窗

### 5.1 大厅预览
`room_lobby_page.dart` diff（逐行）：`_openMember` 从「座位 / HP·SAN / 卡名」三行改为：`if (!hasCardVitals(m))` → 只弹「未绑卡」（`P12` 不回退，**不画 0 卡**）；否则 `showCharViewSheet(context, seat: seat)`（P10-1 已存在的完整只读卡，`showRoomSheet` 自带超屏滚动）。数据取权威 `state` 里的 `m['sheet']`（跨设备可读），非本机卡文件。用例 1 断言 `CharViewKeys.root` + **14 个子 key**（status/basics/vitals/attrs/skills/background/history/mental/temp/items/weapons/assets/education/madness）全 findsOneWidget；无卡用例断言 `CharViewKeys.root` findsNothing ✅。

### 5.2 推送弹窗（新功能，逐条核代码）
`room_request_watcher.dart`（15,075 B）：
- **居中**：`showGeneralDialog` → `SafeArea > Center > Dialog`（非底部 sheet）✅；`LayoutBuilder` 取 `min(可用宽,340)`、`maxHeight 440` 可滚。
- **内容**：标题 + `_detailsOf`（顶层 + `p` + `payload` 三源，白名单键；`op` 为空的 `state.request` 记账被跳过，避免「待确认：null」）。
- **直接操作**：`INTENT.CONFIRM{op,by,agree}` / `INTENT.CONSENT{id,agree}`，发完 `pop`，无假成功提示。
- **去重**：`Set<String> _seen`，id = `pending:<op>:<by>` / 请求 id；`didChangeDependencies` **首次挂载把已有请求全记为已读**（不重弹历史）；会话未变不重置。
- **全局**：挂在 `RoomGamePage` 根节点**外层**（`KeyedSubtree` 之外），换 key 重建不丢 `_seen`。
- **零新增事件**：只 `sendIntent`，零 `RoomEvt` 新值（27 未变）。
用例：5A 几何 `center.dx≈450 / dy≈800`、宽 ≤340；5B/5C 同意/拒绝；5D 同 id 不再弹；5E 跨视角 `jsonEncode(state)` 中 p2/sp1 **零命中**密语、仅收件人弹；5F KP/玩家两条数据源分别验 CONFIRM / CONSENT。**RV6**（让 `_onSession` 直接 return）→ 5A `Found 0 widgets with key roomPush/root` 红 ✅。

---

## 6. 问题 3 战技 / 问题 4 对抗

- `gp_dice_bar.dart`：战技 `onTap` 发 `INTENT.DICE{'expr':'1D100','label':'战技','skill':'战技','direct':true,'bonus','penalty',...}`（diff 中原 `hostAction('combat.roll')` 已不存在）；用例 3A[host]/3A[p1] 断言四字段 + 权威 `state['dice']` 新增一条 `total` 非 null、`label=='战技'` 的公共骰；3B 旁观者结构上无该按钮。**RV2**（战技 `'direct': true` 改 false）→ `3A[host] Expected <true> Actual <false>` 红 ✅。
- 对抗：`onTap` 改 `showOpposedSheet<void>(context)`；用例 4A 断言 `OpposedSheetKeys.root` findsOneWidget 且 `f.lastSent(action:'check.opposed')` **isNull**（零空 action）；4B 玩家/旁观无按钮（POLICY=[kp] 未变）。

---

## 7. 撤「待处理」区块的合理性裁决 + 独立出包

### 7.1 撤块是否干净
- `grep 待处理` in `lib/`：仅剩 **注释**（sheet_kp_panel 3 处说明）+ 1 条 domain 系统消息（`room_model_actions_combat.dart:2453` 文本）+ 1 处 `sheet_opposed.dart:131` 的 title 文案（「被要求进行对抗…」），**没有 UI 区块标题**。
- `sheet_kp_panel.dart` 的 `title:` 只剩 **3 个 Tool SectionBox**（回合与检定 / 战斗与场景 / 房间管理）+ 2 个壳标题（人物卡 / KP 工具）。
- `kpUnreadCount*` 全族：仅出现在 `sheet_kp_panel.dart` 定义处（+测试 11 处直接单测），**lib 内零 UI 调用点** ⇒ 「纯函数保留供单测」成立，不是假保留；4 个 `KpPanelKeys`（unread/pendingList/opposedCard/requestList）保留但注释标明「不代表还有 UI 在用」，且被反向断言使用。

### 7.2 会不会漏待办（明确结论：**不会**，判合理）
1. **弹窗不是唯一兜底**（已读 `gp_status.dart` 原文核实，且该文件哈希=基线 `6d743aae…`、未动）：KP 侧渲染 `hostRead.pending`（`op` 非空）+ `read.requestsBySeat` 每条为一张 `RoomRequestCard`（`GpStatusKeys.request(id)`），同意/拒绝 → `_confirm` 发 `INTENT.CONFIRM{op,by,agree}`、`_consent` 发 `CONSENT{id,agree}`，并有 `GpStatusKeys.pending` 条数角标；玩家/旁观侧渲染 `state['requests']` →「需我同意」卡（同 `CONSENT`）。标题：KP「待办」/ PL「需我同意」，空态「暂无待办 / 没有需要你同意的请求」。
2. 弹窗被**点屏障关闭**不会消费请求（只有 `sendIntent` 才流转），`_seen` 只防重复弹，不删数据 ⇒ 待办仍在状态条可见。
3. 撤的是「KP 工具弹层里重复列一遍」，而弹窗对**每个新请求**都弹（`_seen` 只按 id 去重），不存在「错过就永远看不到」的窗口。
⇒ **撤块合理**；用户原话「推送消息弹窗后，kp工具箱里面的就不要有了」被准确落地。

### 7.3 独立出包（按项目既有口径判定）
- 我按脚本等价步骤构建（`flutter config --enable-native-assets` → `flutter build apk --release` → 校验三 ABI），gradle 端口临时 9194→2378 后**已恢复**（`gradle_restored=True`，原工程 `964d9ef7…84a1` 未动）。未改 `tool/build_apk.sh`。
- **强证据三项全等**：**字节数 70,397,488 B**（与工程师一致）、**三 ABI 8,913,800 / 9,929,288 / 9,175,944**（一致）、**AOT 字面量 UTF-16LE 全命中**（见下）⇒ **按项目口径判为同一份产物**。
- **SHA256 不同**：我 `250c1bf3…8e5c` vs 工程师 `9e72a887…3e21` —— **良性**（同尺寸/同 ABI/同 AOT）。定位：逐条目比对 181 条目，仅有 6 个 **native** 条目（3×`libapp.so` + 3×`libdartjni.so`）字节不同且**尺寸全同**，其余 175 条目（dex/资源/清单/签名）**逐字节一致**；差异源于 native 段内嵌**构建绝对路径**（工程师侧 `dice-realm`×5；我侧 `dice-realm`×4 + `qa8_work`×1），与「zip/签名时间戳」同属**构建环境差异**，**不是源码/功能差异、不是坏包**。
- 原工程内工程师 APK 未被触碰，仍是交付物（team-lead 已核 `9E72A887…3E21` 并另存 `dice-realm-v2.24.0.apk`）。
- 若要求**逐字节**复现，须在原路径 `dice-realm` 构建；本会话 junction 受限做不到（已列为 C 类未完成）。

---

## 8. 反向证伪（全部自己动手，顺序执行、逐字节恢复）

| # | 改坏点 | 目标用例 | 红证据（原文） | 恢复 |
|---|---|---|---|---|
| RV1 | 往 KP 工具弹层插回 `<Text>待处理</Text>` | `room_ui_kp_test` | `S4.2 … 弹层不再有待处理区块 … [E]`，`Expected: no matching candidates / Actual: Found 1 widget with text "待处理"` | sha `AA8FC6CC…` 回原 ✅ |
| RV2 | 战技 `'direct': true` → `false`（带 `'skill':'战技'` 上下文，唯一定位） | `p10_t6_room_fixes_test` | `3A[host] … [E]`，`Expected: <true> / Actual: <false>` | sha `C9925F2A…` 回原 ✅ |
| RV3 | `oneLineMinWidth 900 → 9999` | `p10_t6_layout_test` | `A1 宽档 1524/1280 … [E]`，`Expected: <1> / Actual: <2>` | sha `E3158383…` 回原 ✅ |
| RV4 | `gpKpTools flex 30 → 22` | `p10_t6_layout_test` | `C1 … [E]`、`B2 … RenderFlex overflowed by 20 pixels` | sha `05DDE01A…` 回原 ✅ |
| RV5 | 右列 `flex 27 → 23` | `p10_t6_layout_test` | `C3[1280×800] … [E]`，`Expected: false / Actual: <true>`（tooNarrow 复发） | sha `05DDE01A…` 回原 ✅ |
| RV6 | `RoomRequestWatcher._onSession()` 直接 return（弹窗失效） | `p10_t6_room_fixes_test` | `5A … [E]`，`Found 0 widgets with key [<'roomPush/root'>]` | sha `F77B01E3…` 回原 ✅ |

说明：首轮 6 项曾因第二副本 `.dart_tool` 缺 `package_graph.json`（+与串行抢 flutter 启动锁）产生**不可信红**，已识别并**全部作废**；上表为 `flutter pub get` 修复后**顺序重跑**的真实结果（每项都打印了断言级红证据）。RV6 用「让 watcher 失效」等价于「摘掉 watcher」，效果同一（弹窗为唯一被测行为）。

---

## 9. 红线扫描

| 红线 | 独立结果 |
|---|---|
| 不跑 adb / 模拟器 / 真机 | ✅ 全程未跑；Q1–Q9 只登记 |
| `pubspec.yaml` 只改 version | ✅ diff 仅 `2.23.0+93 → 2.24.0+94`（+ 同步 `lib/app_version.dart` 2.24.0/94） |
| `lib/domain/**` 零 `package:flutter`·`dart:io`·`dart:ui`（含注释） | ✅ 58 文件 **0 命中** |
| `RoomEvt.values=27` | ✅ `room_coverage_test` 断言 `27`、P4 YES |
| `kRoomPolicy=61` | ✅ P4 `POLICY=61，分支=67，缺失=无` |
| `jsStr(` = 14、白名单外 0 | ✅ P5 实测 14 处 / 6 白名单文件 |
| `RoomSlot`/`RoomKeys` 不增删改 key | ✅ `room_keys.dart` 11 个 key、mtime `11-09 12:40`、sha `f014ea55…` |
| GENERATED 两文件 | ✅ skills `d8f39a90…` / occupations `e3bcb0a6…`（与上批相同，未动） |
| `tool/qa/*`、`qa_*_report.md`、`test/qa_p10_4_verify_test.dart`(8) | ✅ mtime 均早于本批（04:31 / 08:57 / 02:32） |
| 另一工作区 `overview.md` 未改 | ✅ 内容仍为 v2.23.0+93 / 2079（本批未回写），sha `a73d35fd…` |
| 全量只增不减 | ✅ 2079 + 27 = 2106 |
| 原工程未被 QA 写入 | ✅ `gp_topbar e3158383…` / `gp_dice_bar c9925f2a…` / `room_layout 05dde01a…` / `sheet_kp_panel aa8fc6cc…` / `room_request_watcher f77b01e3…` / `gradle.properties 964d9ef7…84a1`；`build` junction → `D:\dev\dice-build` 完好、D: 顶层 10 项不变 |

---

## 10. 真机清单核对

- `_manual_test_checklist.md` P0 · 第 6 期 **Q1–Q9 共 9 条**（预览全信息 / 潜在疯狂 / 手机顶栏 / 手机骰子条 / 战技 / 对抗 / 推送弹窗 / 撤待处理 / KP 平板重排），**只登记未执行**。
- 头部指纹 `9e72a887265e21c7b0e4b85b704b80cadf4e082d55e613b8f07f2c7204a43e21` / **70,397,488 字节** 与工程师报一致；上批回滚记录 `v2.23.0+93 / 70,381,104 B / 32fc23c1…81c4` 保留。
- 未跑 adb / 模拟器 / 真机。

---

## 11. 智能路由判定

**Send To: NoOne**

- 源码 bug：**无**（6 项反向证伪全部按预期变红 ⇒ 实现与断言互相钉死；三 ABI/体积与工程师完全一致）。
- 测试 bug（放宽）：**无**（4 处口径逐条复现，断言更强；用例数净变化 0、零 skip）。
- 非阻塞遗留（交 team-lead 汇总 / 下批）：
  1. **APK SHA 未逐字节复现**：仅因我在副本路径构建（AOT 写入 `qa8_work`），6 个 native 条目同尺寸不同字节，其余 175 条目全同；原工程 APK 未动。要逐字节复现须在原路径构建（本会话 junction 限制，已报备）。
  2. `room_layout.dart` 注释「288→270」与代码 `260` 不一致（文档笔误）。
  3. 本会话环境限制：`--concurrency=1` 多文件/目录会 `拒绝访问`，故串行用**成对抽样**（4 组 114 条全绿）+ 并发全量 2106 替代；148 文件完整串行**未在本会话复现**（已如实标注）。

**结论：可以交付用户（真机 Q1–Q9 由用户按约定验收）。**
