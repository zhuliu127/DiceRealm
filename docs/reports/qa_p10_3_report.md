# QA 独立复核报告 · P10 第 2 期 B（房间布局重构）

> QA：严过关（Edward）· 2026-11-11 02:0x · 全程中文
> 复核对象：工程师寇豆码交付的 P10 第 2 期 B（`lib/ui/room/widgets/room_layout.dart` 新增 + 两档布局 + 工具栏改 Column 末格 + 三栏闪烁同源）
> 参照：`_p10_transport3.txt`(314 行) / `_manual_test_checklist.md` / `qa_p10_2_report.md`（口径延续）
> 原则：**自己跑、自己怀疑、自己证伪**。所有证伪改完都逐字节恢复并复核 sha256。

---

## 0. 结论摘要

| 项 | 结论 |
|---|---|
| 五项自检独立重跑 | 全量 **1853 全绿**（并行 + `--concurrency=1` 串行各一遍）；`dart analyze` 零；P4 **13/13**；P5 UI **14/14**；APK 独立出包 **70,001,068 B / `c3740fd7…a3aaa0` / 三 ABI 与工程师逐字节一致** |
| 账目 1834 → 1853 | **算得平**（+5 / +1 / +13，三个文件用例数我独立数过） |
| ★ 档位改动是否放宽 | **覆盖未降，接受**。7 处档位改动的语义都是「必须让全部槽位摊成真块」，改前改后都在「全部真块」档；断言原样未动。但**另发现一条用例已与生产路径脱钩**（`roomOrderedContentSlots` 无调用点），见 §3.3 |
| ★ 布局几何是否真钉住「栏位对齐」 | **真钉住**。渲染侧行列取自**同一个 `gap` 参数**；用例是 `getRect` **几何实测**（不是常量自比）。我分别把横向 / 纵向 gap 各 +3 → **各自独立变红**（Expected 8.0±0.6 / Actual 11.0）⇒ 两个方向都被真正测量 |
| 折叠档 / 工具栏是否真对 | **真对**。方块摘要随真实数据变（`聊天 · 0 条` → `聊天 · 2 条`）；点开全屏渲染**真实正文**（RichText 命中「玩家1的调查员：真实正文-ABCD」+ 输入框在）；玩家侧收起/放回都能走通；工具栏「不遮挡」断言能抓住写死过高的工具栏（证伪变红） |
| 反向验证是否成立 | **成立 3/3**（我独立做的 E1/E2/E3 全部先红后绿，见 §6） |
| 最终判定 | **PASS（Send To: NoOne）**，附 5 条 P2/P3 级发现（1 条建议下一批给 Engineer：死代码 + 一条用例脱钩） |

---

## 1. 五项自检独立重跑（原始输出末几行）

### 1.1 全量测试（默认并发）
```
00:00 +0: loading .../test/ai_client_test.dart
...
01:15 +1852: .../test/step_background_test.dart: 疯狂表第 9 条（恐惧症）点开 100 条子表
01:17 +1853: All tests passed!
```
`grep -c "^\[E\]\|Some tests failed"` → **0**。

### 1.2 全量测试（`--concurrency=1` 串行）
```
04:50 +1852: .../test/wizard_steps_test.dart: 校验函数（从页面搬出来后行为不变） 非必填步骤永远放行
04:50 +1853: All tests passed!
EXIT=0
```

### 1.3 `dart analyze lib test`
```
Analyzing lib, test...
No issues found!
```

### 1.4 静态门禁
```
node tool/qa/qa_p4_gate.js
==== 合计 13 条，失败 0 条 ====
P4_GATE IS_PASS: YES

node tool/qa/qa_p5_ui.js
[OK]   jsStr( 命中 ≤ 14 且只在白名单 6 文件
       实际 14 处：room_session_local.dart×3, room_session_remote.dart×3, room_text.dart×1,
                  gp_combat_list.dart×5, gp_scene_check_pl.dart×1, gp_status.dart×1；白名单外 无
[OK]   弹层不走裸 showDialog —— 扫描 68 个文件，零命中
==== 合计 14 条，失败 0 条 ====
P5_UI_GATE IS_PASS: YES
```

### 1.5 独立出包（`bash tool/build_apk.sh`，未删 junction、未 `flutter clean`）
```
[2/3] 校验 AOT 产物
  8782728  1981-01-01 01:01   lib/arm64-v8a/libapp.so
  9749064  1981-01-01 01:01   lib/armeabi-v7a/libapp.so
  9044872  1981-01-01 01:01   lib/x86_64/libapp.so
===== 出包成功 =====
-rw-r--r-- 1 60965 197609 70001068 2026-11-11 01:59 build/app/outputs/flutter-apk/app-release.apk
c3740fd7c572c82b0250c2623c6e928c678b72f56827e8faaeb6aa08b8a3aaa0 *...app-release.apk
签名：debug
EXIT=0
```
- **字节数 70,001,068 与工程师报告逐字节一致；SHA256 `c3740fd7…a3aaa0` 也与工程师完全一致**（本批**未出现**上一批「同源不同哈希」现象，可复现性反而更强）；三 ABI 尺寸 `8,782,728 / 9,749,064 / 9,044,872` 三项全等。
- `flutter config --list` → **`enable-native-assets: true`** ✓（出包后已恢复）。
- **AOT 字面量实证**（证明本批新 Dart 代码真进了包）：Dart AOT 的中文是 UTF-16LE，故用 UTF-8 `grep` 会全 0（我第一遍就是这么误判的），改用 UTF-16LE 搜 `lib/arm64-v8a/libapp.so`：
  ```
  展开到面板      utf16le=1
  公开素材 ·      utf16le=1
  画笔与放置工具   utf16le=1
  聊天 ·         utf16le=1
  只给你看 ·      utf16le=1
  ```
  全部命中 ⇒ 折叠方块摘要 / 「展开到面板」抓手这些本批新增文案确实在 AOT 里。

---

## 2. 账目核对（1834 → 1853）

| 文件 | 用例数（我独立数，`grep -cE "^\s+(test|testWidgets)\("`） | 与报告 |
|---|---|---|
| `test/room_ui_layout_test.dart` | **17** | 12 → 17，+5 ✓ |
| `test/room_ui_wiring_test.dart` | **11** | 10 → 11，+1 ✓ |
| `test/p10_t3_layout_test.dart`（新增） | **13** | +13 ✓ |
| 合计 | 1834 + 5 + 1 + 13 = **1853** | 与 `+1853` 实测吻合 ✓ |

- 三个文件内**没有** `for` 动态注册用例（唯一带循环的是 p10_t3 的「三档 × 两角色」，循环写在**单个** `testWidgets` 内部，注册数仍为 1）；因此「文件内注册数之和 == 运行数」成立。
- 旁证：`qa_p10_2_report.md` 记录上一批实测基线正是 **1834**（`01:15 +1834` / `04:50 +1834`），账目起点可信。

---

## 3. ★★ 档位改动是否「为绿放宽」——硬结论

先说结论：**覆盖未降，接受**。但**另有一条用例与生产路径脱钩**（§3.3），这一条比档位更值得改。

### 3.1 四个被改测试文件的逐条核对

本批（11-11 00:52 之后）测试文件 mtime：`room_ui_shell_test`(01:24) / `room_ui_wiring_test`(01:25) / `room_ui_permission_test`(01:28) / `p7_lobby_gate_test`(01:29) / `qa_p5_priv_probe_test`(01:29) / `p10_t3_layout_test`(01:37) / `room_ui_layout_test`(01:38)。非 git 仓库，故用「mtime + 逐条读断言 + 语义等价性」判定，不靠 diff。

关键前提（我核过 `RoomGridSpec.of`）：**900×2200 在本批之后已从「多列网格」变成「折叠档」**（`wideEnough = w>=820` 成立 → `grid=true`，但 `landscape=false` ⇒ `dock=false` ⇒ `mode=folded`）。也就是说，若**不**改档位，这些用例会变成「在只剩 3 块真块的折叠档里断言全部块都在」——它们会直接红，而工程师为了「不变红」有两种改法：改档位（正解）或删断言（放水）。逐条看下来，**他选的是前者**：

| 文件 / 用例 | 原档 | 新档 | 断言内容有没有变 | 判定 |
|---|---|---|---|---|
| `p7_lobby_gate_test` 「IN_GAME 且 KP 视角：GpStatus / GpDiceBar / KP 工具 / 探索舞台 / KP 面板入口全部 findsOneWidget」 | 900×2200 竖屏 | 1280×800 | **没变**：仍是 5 个 `findsOneWidget` + `takeException()==null`。语义仍是「全都在」 | 不改就红（折叠档里 `GpKpTools` 是方块）⇒ 必要适配，**不是放宽** |
| `qa_p5_priv_probe_test` A-2「块 3 工具窄栏：整块 + 全部按钮对玩家/旁观 findsNothing」 | 900×2200 | 1280×800 | **没变**：KP 侧 `GpKpToolsKeys.root/mark/draw/erase/upload/clear` 逐个断言 + `enabledOf == gate.can(op)`；玩家/旁观侧 7 个 key `findsNothing` | 同上。★ 这里反而是**变强**：若留在 900×2200，玩家侧「不该有 map.* 入口」会变成**永真**（折叠档玩家根本不建 `gpKpTools`），断言会失去意义 |
| `qa_p5_priv_probe_test` A-3 / A-4 / T-20 / T-06（共 5 处） | 900×2200 | 1280×800 | **没变**（6 档 level 禁用、`stateBtn`→弹层→真发 `state.self`、撕卡后 4 个入口 `findsNothing`、旁观点遍全页零发包） | 必要适配 |
| `room_ui_permission_test` 页面级用例（`_boot(tester, w:kPageW, h:kPageH)`）+ T-30「每个 op 都在运行时被真的找到」 | 900×2200 | 1280×800 | **没变**：`expectGateEquivalence` 逐 op 比对 `enabled == gate.can(op)`，`missing/extra` 双向为空 | 必要适配 |
| `room_ui_permission_test` 大厅 / 弹层用例（`_boot(tester)` 默认 900×2200） | 900×2200 | **未改** | — | 大厅页自己有布局，不受影响 ✓ |
| `room_ui_shell_test`「折叠组」三条 | 见 §3.2 | | | |
| `room_ui_wiring_test` 默认档改平板横屏 + 新增折叠档接线用例 | — | — | 新增 1 条 | 只增不减 ✓ |

**「竖屏/单列档的这些行为还有没有别的用例覆盖」**——我逐条找了替代覆盖：

1. **权限闸门（可点性 == POLICY）在竖屏档**：仍有 `room_ui_shell_test`「★ 快捷按钮可点性 == POLICY（三角色逐一比对）」跑 **360×640**（工具栏按钮在折叠档也恒在）+ `qa_p5_priv_probe_test` 的弹层用例（900×2200，档位无关）。**折叠档里「展开块的闸门」**由 p10_t3 A 组表驱动（4 档 × 2 角色，断言展开/方块的**种类**）+ `room_ui_shell_test` 12/13 容器同时兜住。⇒ 无缺口。
2. **12/13 容器 key**：`room_ui_shell_test` 三条仍在 **360×640** 跑（`_expectSlots` 全量），p10_t3 A 组在 4 档 × 2 角色全量跑 ⇒ 无缺口。
3. **折叠行为**：`room_ui_layout_test` 仍在 **360×640 / 780×320 / 780×400** 跑折叠档（展开白名单、方块落位、compact 几何、收起/放回）⇒ 竖屏档没被放弃。

### 3.2 `room_ui_shell_test` 折叠组重写：变强还是变弱？

旧语义（本批前）是「每个内容槽位都有折叠头，收起后块体消失」。新语义只有 3 个 KP / 2 个玩家块有折叠头（其余是方块，本就不在展开区），所以旧断言**必须**重写。重写后的强度逐条看：

| 用例 | 现在断言 | 相对旧版 |
|---|---|---|
| 「竖屏：展开区有折叠头；收起后退回方块」 | ① `foldKey(gpKpLeft)` **findsOneWidget**；② 容器 key findsOneWidget；③ 点头 → `local.isFolded()==true`；④ **`GpKpLeft` 块体 findsNothing**（真块必须消失，不是只变灰）；⑤ 容器 key 仍在；⑥ 折叠抓手仍在（两种形态同一 key） | **变强**：新增了 ④「真块从树上消失」这种正向证据，旧版只断言折叠头存在 |
| 「★ 折叠态在会话重绘后保持（T-08）」 | 收起 gpMap → `GpMapStage` 消失 → 一条权威事件重绘 → 仍折叠 + `GpMapStage` 仍消失 + **反证 gpKpLeft 仍在** | 等价（多了一条反证） |
| 「平板横屏固定网格：不显示折叠头」 | `foldKey(gpChat)/foldKey(gpKpLeft)` findsNothing + 12 容器全在 | 新增口径，合理 |

⇒ **不是「只断言 widget 存在」**，是断言了「真块消失 + 抓手仍在 + 重绘不丢」。**判定：强度未降**。

### 3.3 ★ 但我发现一条用例已经「测不到产品」

`lib/ui/room/room_game_page.dart:69` 的纯函数 `roomOrderedContentSlots`：

- **全库调用点 = 0**（`grep -rn "roomOrderedContentSlots(" lib/` 只有定义那一行）。它的 docstring 却写着「**本函数仍服务折叠档的方块平铺顺序**」——**不成立**：折叠档走的是 `roomFoldedSlots()`，那个函数直接按槽位表顺序遍历，根本没经过它。
- 而 `test/room_ui_layout_test.dart:193-212`「单列档私密栏提到内容区第一位；多列档保持原序」**仍在断言它的行为**（`ordered.first == gpPriv`、`length==10/11`）。⇒ 这条用例 100% 绿，但保护不到任何上架界面。
- 连带一个**行为变更**（用户可见、非缺陷）：旧单列档把「只给你看」提到第一位（等价旧 CSS `order:-1`），新折叠档里它是**排在方块区末尾的方块**。补偿是方块上的「新」角标（消息来了会亮）。**需真机确认可接受**（已写进清单）。

**建议（下一批给 Engineer，P2，不阻塞本批）**：要么让 `roomFoldedSlots` 真的调用它（并让 `spec.mode==folded` 时保留「私密优先」），要么删掉这个函数 + 把那条用例改写成断言**真实**的折叠顺序（展开白名单顺序 + 方块顺序），别留「测死代码」的假覆盖。

---

## 4. ★ 布局几何是否真钉住「栏位对齐」（用户原始抱怨点）

### 4.1 渲染侧：确实是同一个 gap

`room_layout.dart:242-280` `buildRoomLayout()`：
```dart
widgets.add(axis == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap));
...
return Flex(direction: axis, crossAxisAlignment: CrossAxisAlignment.stretch, ...);
```
- 横向缝隙 `SizedBox(width: gap)`、纵向缝隙 `SizedBox(height: gap)` **用的是同一个形参 `gap`**，没有任何「各段各算」。
- 唯一来源：`room_game_page.dart:488` `final gap = roomBlockGap(spec);` → `roomBlockGap` = `spec.compact ? 4.0 : RoomTheme.panelGap`（一处三元）。**全库没有第二处行/列间距计算**。
- 另有 `crossAxisAlignment: CrossAxisAlignment.stretch`（工程师 §4 自述的坑）：`Expanded` 只压紧主轴，交叉轴必须显式 stretch，否则块会缩成自身高度、行又歪掉。**代码里确实写了**。

### 4.2 用例侧：是几何实测，不是常量自比

`room_ui_layout_test.dart:363-420` 用 `tester.getRect(find.byKey(keyOfSlot(...)))` 拿**真实矩形**再相减：
```dart
expect(kpTools.left - kpLeft.right, moreOrLessEquals(gap, epsilon: 0.6));
expect(map.left - kpTools.right,  moreOrLessEquals(gap, epsilon: 0.6));
expect(chat.top - map.bottom,     moreOrLessEquals(gap, epsilon: 0.6)); // 行间距 == 同一个 gap
expect(log.left - chat.right,     moreOrLessEquals(gap, epsilon: 0.6));
```
⇒ 是量像素，不是查常量相等。

### 4.3 我自己量了一遍（1280×800，探针实测矩形）

**KP**（`L/T/R/B` 单位 dp）：
```
gpKpLeft   L=8.0    T=78.0  R=221.5  B=696.0  W=213.5 H=618.0
gpKpTools  L=229.5  T=78.0  R=495.2  B=386.9  W=265.7 H=308.9
gpMap      L=503.2  T=78.0  R=986.2  B=386.9  W=483.0 H=308.9
gpScene    L=994.2  T=78.0  R=1272.0 B=177.6  W=277.8 H=99.6
gpCombat   L=994.2  T=185.6 R=1272.0 B=291.0  W=277.8 H=105.4
gpPlayers  L=994.2  T=299.0 R=1272.0 B=386.9  W=277.8 H=87.9
gpChat     L=229.5  T=394.9 R=746.8  B=549.3  W=517.2 H=154.4
gpLog      L=754.8  T=394.9 R=1272.0 B=549.3  W=517.2 H=154.4
gpPriv     L=229.5  T=557.3 R=1272.0 B=646.4  W=1042.5 H=89.1
gpStatus   L=229.5  T=654.4 R=1272.0 B=696.0  W=1042.5 H=41.6
gpToolbar  L=0.0    T=696.0 R=1280.0 B=800.0  W=1280.0 H=104.0
```
逐缝核对（全部 **8.0**）：`221.5→229.5`、`495.2→503.2`、`986.2→994.2`、`386.9→394.9`、`177.6→185.6`、`291.0→299.0`、`746.8→754.8`、`549.3→557.3`、`646.4→654.4`。
**左右边对齐**：`gpKpTools/gpChat/gpPriv/gpStatus` 的 `L` 全 = **229.5**；`gpPlayers/gpLog/gpPriv/gpStatus` 的 `R` 全 = **1272.0**。→ 用户抱怨的「栏位没对齐」在几何上确实被消掉了。

**玩家**：`charCard R=259.2 → map L=267.2`（8）、`map R=912.2 → scene L=920.2`（8）、`map B=378.2 → chat T=386.2`（8）、`scene/mates/combat/sketch/notes` 四缝各 8、`chat R=765.6 → log L=773.6`（8）、`chat B=545.4 → priv T=553.4`（8）、`priv B=645.2 → status T=653.2`（8）；`charCard` 通高 `T=60 B=696`，`map` 最大（645×318.2）。同样一致。

### 4.4 落位表 vs 用户给的红块图（逐块）

**玩家**（红块图：左角色信息通高 / 中上公开素材图 / 右上场景检定+队友信息 / 右中手绘板+笔记栏 / 中下聊天+公开记录 / 再下只给你看 / 底工具栏）

| 红块图 | 实现（`roomDockPlanOf(isKp:false)`） | 对齐 |
|---|---|---|
| 左角色信息通高 | `gpPlCharCard` flex 20，通高（60→696） | ✓ |
| 中上公开素材图 | `gpPlMap` flex 55（最大块，面积 205k dp²） | ✓ |
| 右上场景检定 + 队友信息 | 右列 `gpPlScene`(22) / `gpPlMates`(20) | ✓ |
| 右中手绘板 + 笔记栏 | 右列 `gpPlSketch`(20) / `gpPlNotes`(18) | ✓（中间多一格 `gpPlCombat`(20)：玩家确有战斗列表槽位，必须落位） |
| 中下聊天 + 公开记录 | `Row(gpPlChat 1 : gpPlLog 1)` | ✓ |
| 再下只给你看 | `gpPriv` flex 15，通宽 | ✓ |
| 底工具栏 | `gpToolbar`（Column 末格，通栏贴底） | ✓ |
| （红块图未标）连接状态条 | `gpStatus` flex 7，通宽 | 新增细条，合理 |

**KP**（红块图：左地图素材 / 中上公开素材图 / 右上场景检定 / 右中战斗列表+怪物信息+玩家信息 / 中下聊天+公开记录 / 右下只给你看 / 底 KP 工具栏）

| 红块图 | 实现 | 对齐 |
|---|---|---|
| 左地图素材 | `gpKpLeft` flex 17 通高 | ✓ |
| 中上公开素材图 | `gpMap` flex 40（最大块 483×308.9） | ✓ |
| 右上场景检定 | 右列 `gpScene`(34) | ✓ |
| 右中战斗列表 + 怪物信息 + 玩家信息 | `gpCombat`(36) + `gpPlayers`(30) | ✓（「怪物信息」是 `gpCombat` 内 `PanelTabs(['顺序','怪物信息'])` 的 tab，未新增 slot —— 工程师已如实说明，我核过 `gp_combat_list.dart` 确有该 tab） |
| 中下聊天 + 公开记录 | `Row(gpChat 1 : gpLog 1)` | ✓ |
| **右下只给你看** | `gpPriv` flex 15，**通宽**（229.5→1272）而非「右下」 | **偏差**（见下） |
| 底 KP 工具栏 | `gpToolbar` 末格 | ✓ |
| （红块图未标）KP 工具竖条 | `gpKpTools` flex 22，插在左栏与素材图之间 | **偏差但必要**（老 APP 有工具条，`gpKpTools` 是既有槽位，必须落位） |

⇒ **落位表整体与红块图吻合**（左通高 / 中上大素材 / 右列小格 / 聊天记录并排 / 私密 / 底工具栏，全部对上）。两处偏差需用户拍板（已写进清单，不算缺陷）：① KP 的「只给你看」是**通宽一条**而不是「右下角」；② KP 多一条工具竖条（红块图没画，但老 APP 有）。

### 4.5 自己证伪（见 §6 的 E1 / E2）：横向 gap 与纵向 gap 各 +3，**各自独立变红**

---

## 5. 折叠档与工具栏核对

### 5.1 折叠方块点开 = 真块 + 真内容（不是空壳）

工程师的用例只断言了「类型出现」：
- `p10_t3` B 组：`openSquare(gpChat, GpFeeds)`、`openSquare(gpPriv, GpPrivates)`、玩家 `gpPlMap → GpMapStage.readOnly==true`。
- 通关口径上「类型在了」已经能排除空壳，但**没验块内真内容**。我用探针补验（不改他的用例）：

| 我验的 | 实测 |
|---|---|
| 方块点开后渲染什么 | `GpFeeds` ×1、聊天输入框 `RoomKeys.gpChatInput` ×1 |
| 里面的**正文** | `RichText` 命中「玩家1的调查员：**真实正文-ABCD**」×1（`find.textContaining` 默认不搜 RichText，所以工程师若想加这条断言需 `findRichText: true`） |
| 玩家侧素材图 | `GpMapStage.readOnly == true`（只读，与 KP 区分） |
| 是否裸 showDialog | 否：`openRoomSlotFullscreen` → `showFullscreenReader`（真实路由 + 自带关闭），P5 门禁 `showDialog` 零命中 ✓ |

⇒ **是真块、真正文**，不是空壳/占位。

### 5.2 折叠摘要 = 真实数据（不是硬编码）

`roomSlotSummary()` 走 `collectChats/collectFeeds/privRowsOf/membersOf/publicAssets` 计数。探针实测：
```
首屏 chat 摘要=聊天 · 0 条
发 2 条聊天后 =聊天 · 2 条
log 摘要=公开记录 · 0 条   priv 摘要=只给你看 · 0 条   players 摘要=成员 · 2 人
```
⇒ 真数据、会随状态变。唯一「静态」的是几句口径文案（`战斗轮次与列表` / `手绘与标记` / `本机笔记` / `画笔与放置工具`）——这些块本来就没有可数的量，属合理。

### 5.3 展开区可收起 = 复用 `RoomUiLocal.folded`

- 代码：`_foldedContent` 里 `local.isFolded(slot.name) ? _squareOf(...) : _expandedPanel(...)`；`_expandedPanel` 的 `FoldHeader` 点一下 → `local.toggleFold(slot.name)`；方块上的「展开到面板」→ `local.setFold(slot.name,false)`。**没有第二套折叠状态。**
- 我补验**玩家侧**（工程师用例只覆盖 KP 的 gpScene/gpMap）：
```
gpPlScene     before=false folded=true isSquare=true unfolded=false
gpPlCharCard  before=false folded=true isSquare=true unfolded=false
```
⇒ 玩家两块都能收起→变方块→放回。

### 5.4 工具栏改 Column 末格

| 要核的 | 结论 / 证据 |
|---|---|
| 「内容区视口底边 ≤ 工具栏顶边」三档是几何实测吗 | **是**。`p10_t3` D 组 3 用 `getRect` 取内容区 `SingleChildScrollView` **视口**（不是被内容撑高的 Transform）与工具栏矩形相比；360×640 / 780×320 / 1280×800 三档。我实测：`360×640` 视口底 362.0 = 栏顶 362.0；`780×320` 130.0 = 130.0；`1280×800` 696.0 = 696.0 ⇒ **紧贴且不重叠** |
| 「工具栏不在缩放 `Transform` 子树内」还成立吗 | **成立**。结构是 `Column[顶栏, Expanded(_zoomHost→SingleChildScrollView→Transform.scale→内容), 工具栏]`，工具栏是 `Transform` 的**兄弟**（`room_ui_layout_test` 的祖先链反查断言 + 反证内容块确在 Transform 里，仍绿） |
| `kToolbarMaxShare=0.62` 在 320dp 高真的没把内容区挤成 0 吗 | **没挤成 0，但非常小**。我实测内容区视口高度：`780×320` = **52.0**、`640×320` = 52.0、`568×320` = **43.6**、`480×320` = **25.6**、`360×640` = 266.0、`820×1180` = 912.0。**全部 > 0 且 `takeException()==null`**（无 RenderFlex 溢出）。⚠️ 但 480/568×320 已接近不可用，见 §8-3 |
| 极矮屏按钮是否全可见 | `780×320 / 640×320 / 720×320 / 360×640 / 820×1180 / 890×411`：**0 个按钮越界**；`568×320` 与 `480×320`：**各有 1 个按钮落在栏外**（62% 上限生效 → 工具栏内部要竖滚）。工程师「≥360dp 高一次都不用滚」的说法成立，但「手机横屏 320dp 高」实际要滚 —— 已写进清单 |

### 5.5 自己证伪（见 §6 的 E3）：把工具栏**真正**钉死成 400 高 → 「不遮挡」用例变红

> 附一个方法论提醒（工程师与后续 QA 都容易踩）：`ConstrainedBox(maxHeight: 400)` **不是**固定高度（子件仍按内容收缩，我第一次这样改，1853 依然全绿，证伪无效）；要证伪必须给 `minHeight` 或 `SizedBox(height:)`。

---

## 6. 自证伪过程（逐字节恢复证据）

| # | 改了什么 | 结果 | 恢复 |
|---|---|---|---|
| **E1** | `room_layout.dart` 把**横向**缝隙改成 `SizedBox(width: gap + 3)` | `room_ui_layout_test` **2 红**：`1280×800 KP…列间距与行间距同源` / `1280×800 玩家…`，`Expected: 8.0 (±0.6) / Actual: <11.0>` | `cp` 回备份 → `cmp -s` 一致 → `sha256 = 991dfe85…086c3a9` |
| **E2** | 只把**纵向**缝隙改成 `SizedBox(height: gap + 3)` | **1 红**：同一条 KP 用例，reason = **「行间距必须与列间距同一个 gap」**，`Expected 8.0 / Actual 11.0` | 同上，回到 `991dfe85…086c3a9` |
| **E3** | `room_game_page.dart` 工具栏约束改成 `minHeight:maxHeight:400`（真钉死） | `p10_t3` D 组 **2 红**：`1280×800 横屏档工具栏比竖屏矮`（Expected <400 / Actual 400）+ `★ 工具栏不再覆盖内容`（780×320 档 `Expected ≤320.5 / Actual 478`，reason「工具栏必须贴在屏幕最下方且不越界」，并伴随 `RenderFlex overflowed by 158 pixels`） | `cp` 回备份 → `cmp -s` 一致 → `sha256 = 80bd86f5…c89951` |

- E1/E2 合计证明：**「列间距 == 行间距 == gap」不是查常量，两个方向各自被真正测量**，任一侧漂移都会红。
- E3 证明：**「工具栏不遮挡」不是结构性废话**，写死过高会在矮屏档翻红。
- **恢复后复核**：两个文件 `sha256` 回到 `991dfe85…` / `80bd86f5…`（与工程师 §5.4 记录的 `991dfe85…` 一致），`cmp -s` 全部 `RESTORE_OK`；三个临时探针文件（`test/_qa3_probe*_test.dart`）已删除，`ls test/_qa3*` 为空。**生产源码零残留改动**。
- **恢复后复跑**：`flutter test test/room_ui_layout_test.dart test/p10_t3_layout_test.dart test/room_ui_shell_test.dart test/qa_p5_priv_probe_test.dart` → **`+60: All tests passed!`**（覆盖几何、折叠、工具栏、档位改动四个重点文件）。

---

## 7. 红线与「各块内部 UI 是否越界」

| 红线 | 结论 |
|---|---|
| `pubspec.yaml` 未动 | ✓ mtime `2026-11-10 21:35`（早于本批 00:52 开工），`version: 2.17.0+83` 未变 |
| `lib/domain/**` 零改动且纯净 | ✓ `find lib/domain -newermt "2026-11-11 00:52"` **为空**；`grep -rl "package:flutter" lib/domain` **为空**（仍是纯 Dart） |
| `RoomSlot` / `keyOfSlot` / `roomFoldKey` 命名未变 | ✓ `lib/ui/room/room_keys.dart` mtime `2026-11-09 12:40`（本批**没碰**）；23 个枚举值一个没增删（`kpSlots`=12 / `plSlots`=13 断言仍绿） |
| `jsStr(` 仍 14 处 | ✓ 门禁实测 14（白名单 6 文件内，白名单外 0） |
| 弹层无裸 `showDialog` | ✓ `grep showDialog lib/ui/room/` 只有 2 行**注释**；门禁「扫描 68 个文件，零命中」 |
| 出站无 `toWireJson()` | ✓ 只在 `lib/domain` 定义 + net/ui 的**注释**里出现，活代码零调用 |
| 零 `Timer` / `AnimationController`（活代码） | ✓ `gp_feeds` / `gp_privates` / `room_layout` / `room_feed_flash` 四文件 grep 零命中；p10_t3 E 组静态守卫仍绿 |
| **各块内部 UI 是否被改** | **没有越界**。本批（00:52 之后）`lib/ui/room/widgets/gp_*.dart` 只有 **2 个**：`gp_toolbar.dart`(01:37，用户点名的③，改的是滚动→`Wrap`+高度自适应，未改按钮视觉)、`gp_privates.dart`(01:40，只换了判据源 + 加「新」角标，行结构未动)。其余 18 个 gp_* 全部 mtime ≤ `2026-11-10 00:51`（上一批及更早）⇒ 用户的「只改布局不改块内 UI」被遵守 |
| 唯一共享组件改动 | `room_panel_kit.dart`(01:31) 的 `RoomTap`：`Center` → `Align(widthFactor:1, heightFactor:1)`。这是**布局层根因修复**（`Center` 在「宽度有界但松」的 `Wrap` 里会撑满整行 → 每个按钮一行、骰子条一度 622dp）。紧约束场景行为不变；1853 全绿即证不砸既有视觉/交互 |

### 闪烁与「只给你看」
- `_seenSeq` **全库零命中**（只有 p10_t3 的守卫用例里作为「必须不存在」的字面量出现一次）✓
- 三栏同源 `FeedFlashTracker`：`gp_feeds.dart:128/135`、`gp_privates.dart:93/99/137`、页面级 `RoomFlashBoard`（`room_layout.dart` 里 3 个 `_PaneFlash` 各持一个 `FeedFlashTracker`）✓；`gp_privates` 接上了 `syncEpoch` 变化 → `reset()` ✓
- 折叠成方块时判据上提到页面级：`room_game_page.dart:315` `spec.mode==folded ? _foldFlash(...) : {}`，`_squareOf` 里 `flash[slot]` → 方块左下「新」角标；点开 → `flashBoard.dismiss(slot)` ✓
- 一个**口径细节**（非缺陷）：`RoomFlashBoard` 的私密栏恒用 `lastSeat = kHostSeat`（私密信息由 KP 下发），因此「KP 视角自己写的私密不闪」是靠 `lastSeat==mySeat` 自然成立的；玩家视角恒 `!= mySeat` ⇒ 玩家永远闪（正确）。p10_t3 E 组第 3 条正是这么断言的 ✓

### 与 transport 报告不一致的表述（要求订正，不影响功能）
- `_p10_transport3.txt` §1 第 2 条：「**每个可折叠槽位恒有且只有一个 `roomFoldKey(slot)` 抓手**（两种形态共用一个 key）」——**不准确**：`RoomSlotSquare` 只有在 `onUnfold != null`（即该槽位属于默认展开白名单）时才挂 `foldKey`；平板横屏档 **0 个**折叠抓手。功能上没问题（非展开白名单的方块本来就不该能「放回展开区」），但报告措辞会误导下一批。
- `_p10_transport3.txt` §5.3：「`lib/ui/room` 68 个 .dart / **18146** 行」——实测 **18165** 行（差 19 行，`view/` 6 个 / 1191 行一致）。属记账时点差异（很可能写完报告后又改了 19 行才定稿），不是缺陷。

---

## 8. 发现清单（按严重度）

| # | 级别 | 发现 | 影响 | 建议 |
|---|---|---|---|---|
| 1 | **P2** | `roomOrderedContentSlots` 全库**零调用**，docstring 却称「仍服务折叠档方块顺序」；`room_ui_layout_test` 仍在断言它（§3.3） | 一条永久绿的用例保护不到任何上架界面；死代码留坑 | 下一批给 **Engineer**：接线或删除 + 用例改写 |
| 2 | **P2** | 1280×800 下 **3 格需要格内横向轻推**：`gpKpLeft` 实宽 213.5 < 最小 230、`gpKpTools` 265.7 < 300、`gpScene` 277.8 < 288 | 用户「按红块图逐块核对」时这三格会看到内容被切一点，要拖一下 | 工程师已如实披露（§3.4）；**真机确认是否可接受**。若不可接受，只能放宽对应块的内部固定行宽（= 动块内 UI，需用户点头） |
| 3 | **P2** | 极矮屏 480×320 / 568×320：工具栏 62% 上限生效 → **1 个按钮要竖滚**、内容区视口仅 **25.6 / 43.6 dp** | 老机型手机横屏体验差（730×320 / 640×320 则正常：0 越界、52dp） | 已写进清单「极矮屏」条；若用户不接受，需专门做「横屏超矮」档（如工具栏收成图标条） |
| 4 | **P3** | 自动化**没有**断言「内容区视口高度 > 0」（只断言底边 ≤ 栏顶）；`ConstrainedBox` 证伪不生效的坑也没写 | 极端档内容区可以被压到 25dp 而用例全绿 | 下一批加一条 `expect(viewport.height, greaterThan(40))`（320dp 高横屏档） |
| 5 | **P3** | transport 两处措辞不实（foldKey 恒在 / 18146 行） | 记账与文档准确性 | 报告已§7 订正，无需改代码 |

**没有发现功能性缺陷**：布局落位、缝隙一致、折叠/展开、点开全屏、工具栏不遮挡、三栏闪烁、红线，均通过。

---

## 9. 清单更新点（`_manual_test_checklist.md`）

1. **新增 `## P0 · P10 第 2 期 B（布局重构，必测）`**（放在 P10 第 2 期 A 之后、P11 之前），覆盖：平板横屏逐块核对 + 缝隙一致、竖屏/手机三档的展开/方块、方块点开真内容、展开区收起/放回、工具栏无横拖 + 不遮挡、三栏闪烁 + 「新」角标、极矮屏不挤成 0。**只登记不执行，不删任何既有条目。**
2. **头部 APK 指纹**订正为本次实测：`70,001,068 字节 / c3740fd7…a3aaa0 / 三 ABI 8,782,728 · 9,749,064 · 9,044,872`；旧的 `5f033883…0b1651`（69,919,088）**保留一行供回滚对照**。
3. 尾部「自动化已验证」：全量 **1834 → 1853**（1834 + 5 + 1 + 13）；补一行「本批档位改动 7 处均为必要适配、断言未动」；补一行「几何对齐证伪 E1/E2 / 工具栏证伪 E3」。
4. **技术债订正**：把「只给你看仍用 `_seenSeq`」标为 **已解决（本批统一到 `FeedFlashTracker`）**；新增 **「⑤ 自动头像 PNG 化未做（没上传头像的玩家跨设备仍显示圆点）」= 下一批第一优先**。
5. P2「信息流闪烁」章节里那段「只给你看仍用 `_seenSeq`、不要按 tracker 口径要求它」的旧口径**改为已统一**（否则真机验的人会按错口径判）。

---

## 10. 遗留（交给下一批）

1. **⑤ 自动头像 PNG 化**（工程师如实未做）：`lib/domain/avatar.dart#make()` 产 `data:image/svg+xml` → 跨设备缩略白名单只收 png/jpeg/webp → 没上传头像的玩家在别人设备仍是首字圆点。方案已在 transport §7 给出（`lib/ui/widgets/auto_avatar_png.dart` + `PictureRecorder`）。**下一批第一优先**。
2. 发现 #1（死代码 + 用例脱钩）。
3. 发现 #2/#3 的用户拍板（格内横推是否可接受 / 极矮屏体验）。
4. 发现 #4 的断言补强。

---

## 11. 智能路由

- **Send To: NoOne** —— 本批代码**没有**被测出的功能缺陷：1853 全绿（并行+串行）、analyze 零、门禁 27/27、三处反向验证先红后绿、几何/折叠/工具栏/闪烁均实测成立、红线全守。
- **附带下一批建议（转 Engineer，非本批打回）**：§8 的 #1（死代码/用例脱钩）+ #4（内容区高度断言）。
- 本批**未改任何生产源码**；改动仅限：本报告 + `_manual_test_checklist.md`。所有证伪均已逐字节恢复（sha256 见 §6）。
