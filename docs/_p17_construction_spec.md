# P17 施工单 · v2.30.0（17 项）· team-lead 定稿

> **唯一依据**。实现 worker 开工前**必须通读本文件**，再按 §2 各条去读对应研究报告的指定章节。
> 四份只读研究报告（行号以 **v2.29.0+99** 源码为准）：
> - `_p17_oldapp_research.md`（老 APP 2.13.13 口径，639 行，定稿）
> - `_p17_kp_landing.md`（KP 8 项落点，392 行，四次修订版，**以此为准**）
> - `_p17_player_common_landing.md`（玩家 4 + 全模式 4 + 首页 1，435 行）
> - `_p17_bug_roots.md`（KP-1 / KP-5 根因，含可证伪假设与夹具）
>
> ⚠️ 三份报告有过修订：**KP-1 与 KP-5 不是同一根因**，不要合并修；**KP-3 不需要新增技能反查**（权威端已具备）；**「武器对抗」不是独立功能**（是玩家战斗对抗的旧入口）。详见 §2。

---

## 0. 总原则与红线

1. **用户口径 > 老 APP**。本批有 6 处用户明确要求与老 APP 不同（§2 逐项标注「⚠️ 差异」）。
2. **一次交付 1 个 `v2.30.0` APK**；内部按文件集切波，对外不分批。
3. **档位范围（硬）**：
   - KP 改动**只落平板横屏 dock**（`roomDockPlanOf(isKp: true)`）。
   - 玩家改动落**非平板横屏**（手机竖/横、平板竖 folded）。**平板横屏玩家档不动**。
   - 玩家侧布局树的 `gpStatus flex:7`、中排 `flex:26` 等**一律不动**。
4. **禁止改动的文件/契约（违反即返工）**：
   - `lib/domain/data/skills.dart`、`occupations.dart`（**GENERATED**）
   - 所有 `oracle_*` 测试与 `test/fixtures/room_actions.json`、`room_model.json`（**逐字节契约**）
   - `lib/domain/room_rules_combat.dart` 的**计算式**（`:24-94` 排序、`max(0,raw-armor)` 等）；**只读**。KP-7 重排只能改 `order` 数组本身，不能碰排序算法。
   - `lib/domain/room_types.dart` 的 `kRoomPolicy` **不得新增 action**（`test/room_ui_permission_test.dart:342` 钉死 `kRoomPolicy.length == 61`）。
   - `lib/ui/room/widgets/unit_picker.dart` 契约（P16 定稿，别为 KP-3 改）。
   - `lib/domain/room_rules_sheet.dart` 的 `_skillValue` / `_skillAlias` / `_normSkillName`、`lib/domain/room_rules.dart:284`（KP-3 依赖它们取技能值，不改）。
5. **测试口径（硬）**：不放宽断言、不 `skip`、不删用例、不改恒真、`findsOneWidget` 不许降级 `findsWidgets`。
   - 产品行为真变了时**允许且应当**同步更新测试，只要**更强或等价**（保留核心不变量逐字断言 + 新增正向断言）。
   - **「补了断言」必须自证咬得住**：新增守卫后要自己做一次反向证伪（改坏 → 必须红 → 逐字节恢复 → 必须绿）。P16 踩过：三条「怪物 hp>0」断言因 `combatRows` 有 fallback 而全部恒真。
6. **门禁**：
   - `lib/ui/room/**` 源码零 emoji（**只匹配代理对 U+1F300–1FAFF**；`⚔️` 等 BMP 变体选择符不违规，别顺手删）。
   - `jsStr(` 预算冻结——新代码**不许写 `jsStr(`**，复用 `roomText` / `asMap` / `asList`。
   - `pubspec.lock` 必须与 `pubspec.lock.t7bak` 逐字节一致（82 处 `pub.dev`）。
7. **固定尺寸控件必须过 `textScaler` 1.3/1.5/2.0**；修法只能是 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)` **只包该控件子树**，禁止 `ClipRect` 硬裁、禁止抬到页面/Theme 层。
8. **不跑 adb / 模拟器 / 真机**（用户统一测）。真机待测项由 QA 登记清单。

---

## 1. 工程与环境

- 工程根 `$P = C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`。
- 每条命令前：
  ```bash
  source /d/dev/env.sh
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
  export NO_PROXY=127.0.0.1,localhost
  ```
- 测试一律 `flutter test --no-pub <file>`（裸 `flutter test` 会触发 pub get 污染 lock）。
- **禁止 `flutter clean`**；`build` 是实目录，绝不删、绝不改 junction。
- 版本升 `2.30.0+100`：`pubspec.yaml` 的 `version:` 与 `lib/app_version.dart` 的 `kAppVersion`/`kAppBuildNumber` **同时改**（`test/app_version_test.dart` 逐字比对）。由**波4 总装 worker**执行。
- 出包 `bash tool/build_apk.sh`（已内置 `--no-pub` + 出包前后双向锁校验；timeout 600s，前台 + `dangerouslyDisableSandbox`）。出包前解析 `HTTP_PROXY` 拿当前端口，改 `android/gradle.properties` 两处 `systemProp.*.proxyPort`，出完 `cmp -s` 恢复。出包后必验 AOT 真重编（三 ABI `libapp.so` SHA，逐字节相同 = 没进包）。

---

## 2. 逐项最终口径（17 项）

### KP 视角（平板横屏 dock，8 项）

#### KP-1 ★ 申请推送后失灵（真 bug，最高优先级）
用户原话：「KP 被推送一次申请之后，再点击治疗按钮（弹窗后的 3 个按钮），就都没有反应了。其他玩家推送的申请好像也没反应。」

**根因（已证，改法唯一）**：
1. `lib/ui/room/room_request_watcher.dart:170` 推送去重键 `id: 'pending:$op:$by'` **不含 pending 项自身的唯一 id**（对比 `room_model_actions_sheet.dart:666` 用 `'r$localSeq'`）。同一玩家连续两次同 op 的高危动作 → 两条 pending id 相同 → `_seen.add`（`:270`）第二次返回 false → **第二条申请永不弹窗**。同理 `lib/domain/room_model_actions_combat.dart:1327` 的 `c$localSeq` 在循环外只生成一次，N 个 target 共用同一 id（全体推送）。
   - **改法**：只改**去重键构造**，让 id 唯一（把 pending 项自身的序列/id 拼进去）。`payload` 仍保持 `{op, by}`（domain CONFIRM 按 op+by 定位）。
   - **红线**：**不许给 `_seen` 加 remove/清理**。`_seen` 不去重是 P10 刻意设计，被 `test/p10_t6_room_fixes_test.dart:562`「同一 id 只弹一次」钉死。
2. **必须同步修** `lib/domain/room_model_host_intent.dart:484-486` 的 `confirmPending`：该 `for` 循环**不 break**，`idx` 会被覆写成最后一个匹配项。若改了去重键让两条 pending 都弹出，KP 点同意只会摘最后一条，第一条**永久残留**。
   - ⚠️ 这是 **domain 冻结文件**（P10/P16 反复对拍），改动必须**单独挂一轮 QA 全量回归**。
3. **KP 侧「收不到新申请弹窗」是 bug，不是设计**：KP 读 `hostRead.requestsBySeat` 全量，本就该看到所有 seat 待办。`SEAT` 定向裁剪（`p10_t6_room_fixes_test.dart:646-660`）**只约束玩家视角**，别把 KP 侧一起放过。
4. **治疗弹层本身没坏**：`sheet_treat.dart:151-161` 三个 kind 按钮是纯 `setState`，无 `enabled`/`gate`/`throttle`；`p16_wave1_sheets_test.dart:584-589` 已实测全绿。**不要去改它的按钮逻辑**。
5. 消除「提交成功但无反馈」的误判：domain 已有 `sysTo`「已提交，等待确认」（`room_model_host_intent.dart:331-339`），但**只发发起玩家、KP 看不到**。→ 在 `sheet_treat.dart` 提交后补一条 `ctl.notice(...)` 本机反馈即可，**不要再叠第二条 domain 提示**。
6. ⚠️ **用户口径与代码不符**：`openTreatSheet` 全库仅一处调用（`room_game_page.dart:1065`），被 `if (!isKp)` 包住 —— **KP dock 结构上没有治疗按钮**。此点已列入 §6 待拍板项，**worker 不许自行加按钮**，等 §6 结论。

**验收用例（必须重建夹具，不许复用现有最小 shell）**：
- 甲变体：完整 `RoomGamePage` + `RoomRequestWatcher` + dock → 先弹一次推送并正常关闭 → 再打开治疗弹层点第一个按钮 → 必须仍有反应。
- 乙变体：连续两次同玩家同 op 申请 → 必须弹两次（当前漏第二次）。
- 断言：`_seen` 语义不变（同 id 仍只弹一次）。

#### KP-2 场景检定「检定方式」改四档
用户口径：① 选全体玩家还是某个玩家 ② 输入框输入要检定的技能 ③ 选成功需要的检定等级（大成功 / 成功 / 困难成功 / 极难成功）④ 点推送 → 推送到指定玩家 → **系统自动检定**。

**事实**：
- 老 APP 2.13.13 **没有**「检定方式/检定等级」（`检定方式|检定等级` 全库 0 命中）。现有两套是：难度 3 档 `REGULAR/HARD/EXTREME`；6 档**裁定结果** level（与新 APP `gp_scene_check_kp.dart:38-45` 逐字一致）。
- 新 APP「检定方式」四档**未实现**；domain 只有 `REGULAR/HARD/EXTREME` 三档（`room_model_actions_room.dart:426`），UI 全硬编码 `'REGULAR'`（`sheet_scene.dart:87/:358`、`gp_scene_check_kp.dart:80`）。
- 判定阈值（老 APP `room-rules.js:34-58/120-123/181-192`）：`LEVEL {CRITICAL:5, EXTREME:4, HARD:3, REGULAR:2, FAIL:0, FUMBLE:-1}`；`thresholds(base) = {regular: base, hard: floor(base/2), extreme: floor(base/5)}`；大成功 = 掷出 01。

**★ 独立必做项（不等拍板）**：**难度大小写统一**。老 APP UI/载荷发大写 `HARD`/`EXTREME`，domain `DIFFICULTY` 键小写，`normDifficulty` 对未知值回退 `regular` → 困难/极难**静默退化成常规**。新 APP 同样混用（`sheet_scene.dart:87` 大写、`gp_scene_check_kp.dart:80` 小写、`room_model_actions_room.dart:426` 白名单认大写、`room_rules.dart:51-53` 大写键）。必须统一一套并补端到端用例验证 `HARD` 真按 ÷2、`EXTREME` 真按 ÷5 生效。**不许改 `room_rules_combat.dart` 计算式绕过。**

**待拍板（§6-Q1）**：四档是「结果等级当成功阈值」还是「新造第 4 个难度档」。答案决定 `difficulty` 白名单与阈值计算，**未定前只做大小写统一 + UI 骨架，不写判定**。

#### KP-3 对抗改造
用户口径：① 先选**通用对抗**（可输入战斗技能）或**攻击对抗**（玩家方下拉选武器→用武器的战斗技能自动检定；怪物/NPC 方下拉选反击/闪避；反击要再输入**检定等级** + **伤害骰式**（支持 `2D6+D4+1`）；闪避只输入检定等级）② 选甲乙双方单位 + 技能 + 数值，推送后系统自动检定；玩家方输入技能要能套用车卡的技能近义词/缩写自动取数值 ③ **删除武器对抗**。

**事实（三处修正，务必按此，不要照旧结论）**：
1. 「武器对抗」**不是独立功能** —— 老 APP「战斗对抗」按钮 = `playerOpposedSheet` = 弹层标题「武器对抗」，是**同一个玩家功能**，走 `INTENT.OPPOSED`。→ **删的是重复入口**（`sheet_opposed.dart:144-153` 的按钮 + `OpposedSheetKeys.weapon:40`），**但 `INTENT.OPPOSED` / domain `opposed()`（`room_model_actions_combat.dart:2440-2461`）整条链路必须保留**，否则把玩家战斗对抗本身删没了。玩家侧收成**一个入口**。
2. **技能取值不需要新增任何反查、不改 `skill_synonyms.dart`**：权威端 `room_rules_sheet.dart:369-421` `_skillValue` 已实现老 APP 4 档归一（精确名 → 别名 → 基名 → 子类名，歧义返回 null），`_skillAlias:297-314` 16 条与老 APP `SKILL_ALIAS:1180-1197` 逐条对应；链路 `checkOpposed:1549 → resolveActorSkill:1634 → skillBaseOf:1744 → rules.skillValue`（`room_rules.dart:284`）已通。**只缺 UI**：`sheet_opposed.dart` 没有 `aSkill`/`bSkill` 输入框、也没放进载荷。
3. **不要给 `resolveActorSkill:1651-1660` 加 `pc:` 前缀**：它已支持 `p:`/`a:`/`mo:`，老 APP `core/` 里 `pc:` 0 命中（只是 UI 下拉 value，提交前被剥）。
4. **载荷对齐老 APP**：`check.opposed {aSeat, aSkill, aBase, bSeat, bSkill, bBase}`（攻击对抗再加 `attack:true` / `attacker` / `defender`）。**删掉自造的 `kind:'general'` 与裸 `base`**。`difficulty` / `aBonus` / `aPenalty` 是老 APP 协议预留、UI 从不发，别照抄。
5. **domain 一行不用改**（除 §6-Q3 若选「反击伤害新增字段」外），天然避开 `oracle_*` 红线。
6. 武器→战斗技能 = 武器对象的 `skill` 字段（老 APP `data/weapons.js`，如「弓箭→弓」「黄铜指虎→斗殴」）。新 APP 侧对应表需 worker 自查（`lib/domain/data/` 下武器数据），**查不到就在报告里写明并按「下拉选武器后带出 skill 名到技能框」实现**。
7. `secret` 秘密对抗：新 APP 已 1:1 落地（`room_model_actions_combat.dart:1390-1416`），**本批不施工**，仅登记。
8. 反击/闪避的成功失败逻辑（老 APP `room-rules.js:489-531` `opposedAttack`）：**反击同级 → 攻方胜（`mode_fightback_tie`）；闪避同级 → 攻方败/免伤（`mode_dodge_tie`）**；等级高者胜；同级比 base；逐轮重掷 ≤10 轮。伤害 `applied = max(0, raw - armor)`；反击胜的伤害打在**攻击方**身上；闪避胜/落空 `damage = null` 不扣血。

**待拍板（§6-Q2）**：反击的「检定等级 + 伤害骰式」是**取代**原来的对抗值 1-100，还是**与之并存**；伤害是新增防守方字段还是复用攻方武器伤害。**未定前只做：删武器对抗入口 + 补两个技能输入框 + 载荷改成 `aSeat/aSkill/aBase/bSeat/bSkill/bBase`。**

#### KP-4 「游戏记录」「只给你看」比聊天栏短
**根因**：不是 flex、也不是 `GpPrivates` 的 220 高度。是 `gp_feeds.dart:356` `if (pane == FeedPane.chat) const ChatInputRow()` 让聊天 Card 多约 48dp；三块 `SectionBox` 用 `Column(mainAxisSize.min)`（`room_panel_kit.dart:77`），`stretch` 只保证格子等高。
**改法**：让 `GpFeeds(record)` / `GpPrivates` 也吃满格子高度（参考 `gp_combat_list.dart:171-230` 的 `LayoutBuilder` + `Expanded` 范式），**不动 dock 树、不动 `SectionBox` 共用件**。
- ⚠️ **不要改 `GpPrivates` 默认 height**：`p16_wave1_theme_test.dart:100-103` 钉死 220。
- 验收：1280×800 KP dock 下三块 Rect 高度相等（差值 ≤ 1dp）。

#### KP-5 聊天栏全屏编辑发送无反应
**根因（B2-1，与 KP-1 不同因，分开修）**：全屏打开期间底层 `ChatInputRowState` 可能因 `KeyedSubtree` key 含 `inGame` 换 key 被销毁（`room_game_page.dart:336`）→ `onSend` 闭包里 `_text.text = text`（`gp_feeds.dart:745`）对已 dispose 的 controller 赋值抛 `used-after-dispose` → `sheet_chat_composer.dart:127` 抛异常 → `:128` 的 `Navigator.pop` 被跳过 → 弹窗不关、文字还在、没发包。

**改法**：
1. `gp_feeds.dart:736-758`：`onSend` 里**不再碰 `_text` / 旧 State.context**，直接用打开前捕获的 controller / `RoomController` 发包并清草稿。
2. `sheet_chat_composer.dart:124-129`：`onSend` 用 `try/finally` 包住，**`Navigator.pop` 放 finally**（不依赖具体抛点的无条件兜底）。
3. `gp_feeds.dart:754` 的 `draft = result ?? local.chatDraft` 会**回填旧草稿**，确认发送成功后应清空（按实际语义处理）。
4. ⚠️ **debug ≠ 真机**：widget test（debug、assert 开启）能稳定复现 disposed-controller；release 包 assert 被裁，抛点可能不同。→ 甲乙变体在 debug 夹具裁定，**真机另跑一轮**；`try/finally` 是必须做的兜底。
- 验收：甲（先弹推送关闭 → 再全屏发送）/ 乙（全屏打开后插入底层重建 → 再点发送）两变体，乙必须绿；甲也必须绿。

#### KP-6 KP 定向指令补输入
现状：`sheet_kp_directives.dart` 的 `kpDirectivePayload:113-162` 全部硬编码常量、无输入框 → 「只能选目标没输入效果」。
**要补的输入**（老 APP 载荷字段，`room-panels.js:2393-2416`）：
| 按钮 | 载荷 | 需要输入的字段 |
|---|---|---|
| 造成伤害 | `sheet.damage{seat,amount,kind}` | `amount`（数值）、`kind`（伤害类型，老 APP 下拉） |
| 临时状态 | `sheet.tempstatus{seat,text}` | `text` |
| 给物品 | `sheet.item{seat,name,qty,note}` | `name` / `qty` / `note` |
| SAN Check | `sheet.sancheck{seat,okLoss,loss,reason}` | `okLoss` / `loss`（可含骰式）/ `reason` |
| 急救/医学 | `aid.apply{seat,targetSeat,skill:'急救'\|'医学'}` | **只需技能下拉，检定值从角色卡取**（老 APP 无「检定数值」输入，用户口径有偏差） |
| 精神分析 | `aid.psycho{seat,targetSeat}` | **无数值**（老 APP 是玩家申请，不是 KP 按钮） |
| 治愈疯狂 | `madness.cure{seat}` | 无输入，系统自动判定 |
| 治愈重伤 | `sheet.healwound{seat}` | 无输入，系统自动判定 |
| SAN 大失败追加 | `sheet.sanloss{seat}` | **待拍板 §6-Q4**（老 APP 是一键掷 1D10、不记录多次） |

**删除**：「暗骰」`kKpDirectives:44`（工具栏已有）、「请求修改状态」`kKpExtraDirectives:76`（玩家请求会直接弹窗）。删后 key 常量保留。
⚠️ 老 APP 无「急救/医学检定数值」「精神分析检定数值」——施工时**不要凭空造这两个输入**，按上表。

#### KP-7 战斗行动顺序可自定义
现状：order 由 `combatStart` 一次性生成（`room_model_actions_combat.dart:170-300`，`initiativeOrder:230`），排序在 `room_rules_combat.dart:24-94`（**红线只读**）；`nextTurn` 只推 `turn` 游标（`room_model_rollback.dart:432-492`）。**全库无 reorder action/UI**。老 APP 也**没有**这个功能（新需求）。
**改法**：
- 复用已登记的 `combat.set`（`room_model_actions_combat.dart:29-32`，POLICY `room_types.dart:277` = `[kp]`）——**不许新增 action**（`kRoomPolicy.length == 61`）。
- UI 在 `gp_combat_list.dart` 的顺序 tab 行（`:154-166`）/ `gp_combat_strip.dart:98-119` 加 KP 专属「上移/下移」（只在 `isKp` 渲染）。
- **reduce 侧 `RoomEvt.combat` 是整体替换**（`room_model_reduce.dart:153-155`），改 order 必须连 `turn` / `done` / `movedToTail` 一起正确维护。
- **不许改排序算法本身**（只改 order 数组顺序）。

#### KP-8 音乐控制台按钮上移一级
- `sheet_misc.dart:259-266` 删该 `RoomTap`（**保留 key 常量 `:56`**，测试兼容）。
- `sheet_kp_panel.dart`（KpPanel，由 `room_game_page.dart:1021-1028` 打开）加按钮 + `import openMusicSheet`。
- 必红：`test/room_ui_entry_test.dart:751-761`（`musicEntry` findsOneWidget + onTap 非空）→ 改成「更多工具不含音乐入口」+「KP 工具含音乐入口」。

### 玩家视角（非平板横屏，4 项）

#### P-1 角色卡缺 luck
`gp_pl_char_card.dart:194-201` 属性 Wrap 只画 8 项（`sheet_view.dart:73-75` `_attrLabels`）；`vitals.luck`（`:103`、`sheet_view.dart:69` `currentLuck`）已取到未用。
**改法**：Wrap 加一行 LUK。**别改共享纯函数 `attrRows`**。

#### P-2 战斗信息栏自动展开到置顶
`_bodyOf` 的 `gpPlCombat` 只返回 `GpCombatList()`（`room_game_page.dart:827-829`）；folded 展开白名单 `kPlExpandedSlots`（`:105-108`）**不含它**。工程无 pin/置顶机制。
**改法**：把它加进 `kPlExpandedSlots` 并排最前 + **战斗态忽略 `isFolded`**（自动展开）。**不动 `roomDockPlanOf` / `_bodyOf` 的其它分支**。

#### P-3 玩家申请治愈 + 昏迷/疯狂锁定
**申请按钮**：domain 已有 `madness.cure`（`room_types.dart:269-272`）/ `sheet.healwound`（`:307-310`），均 `[player,kp] + RoomConfirm.kp`，载荷 `{'seat': seat}`（对齐 `sheet_kp_directives.dart:157-160`）。**放 `sheet_misc.dart:255-286`「更多工具」弹层**（同时满足锁定期间仍可打开）。
**锁定（现状不符合，必须改）**：`operationLocked`（`member_view.dart:167-175`）只锁角色卡 4 个短按钮；「保存到已保存」（`gp_pl_char_card.dart:317-344`）与**整棵工具栏**零判定。
→ 权威端 `_passSelf`（`room_model_host_intent.dart:95-111`）已拦，UI 未同步。

**锁定态可用白名单（Q6 拍板，唯一口径，不许各 worker 自行增删）**：
1. 角色卡「推进 1 轮」= `madness.advance`（`gp_pl_char_card.dart:358` 那处 throttle）——**这是玩家侧独立按钮，不是工具栏的「下一轮」**，必须保留且锁定态可点。
2. 工具栏「更多工具」= `RoomGamePage.miscToolsKey`，锁定态**恒可点**。
3. 「更多工具」弹层内的「申请治愈疯狂状态」「申请治愈重伤」两个按钮。
4. 纯视图操作（不改变游戏状态）：缩放 `−/%/+`、全屏/折叠展开、列表滚动。

其余**全部禁用**（含骰子条：D100 / 其他骰子 / 自定义骰 / 奖励·惩罚骰 / 暗骰 / 战技；工具栏：治疗 / AI RP / BGM；角色卡：保存到已保存 / 其它短按钮；聊天发送；KP 定向指令等）。

→ ⚠️ 统一禁用若叠加 `!locked`，会撞 T-30「`enabled` 恰好等于 `gate.can`」契约（`room_ui_permission_test.dart` 探针）→ **必须同步改探针口径**（更强：`gate.can && !locked`，并保留白名单项的独立正向断言）。
→ 实现契约：`GpToolbar({..., bool locked = false})`、`GpDiceBar({..., bool locked = false})` 由 `room_game_page.dart#_buildToolbar` 计算并传入；两个组件内部对每个按钮叠加 `!locked`，白名单项除外。

#### P-4 工具栏删「下一轮」「转战斗」+ 重排
- 删 `gp_toolbar.dart:147-155`（`round.next`）、`:156-174`（`scene.mode`）。
- ⚠️ **Q6 拍板**：玩家工具栏这个「下一轮」是**灰色不可点、没有用**的按钮，与角色卡的「推进 1 轮」（`madness.advance`）**是两个不同的按钮**。→ 工具栏的删掉；角色卡的保留并作为锁定态白名单项。
- ⚠️ 这两个按钮目前在 **kp/player/spectator 三视角恒渲染**（玩家侧 `enabled=false`），`room_ui_permission_test.dart:625-640` 有断言 → 删后须同步改口径（KP 侧仍应保留？**不保留**：KP 的「下一轮」在战斗信息栏 `combat.next`，工具栏这个直接删）。
- 重排参考用户截图（现状 5 行 4/3/3/2/2，用户嫌不整齐）：目标**手机竖屏 4/3/3/3 共 4 行**，「更多工具 / 治疗」上提主组，统一 `RoomBtnSize` 档位。具体以 `p16_button_unify_test.dart` 分组表为准一次改到位。
- 受连坐：`diceBalancedRowSizes(9,…)`、`_balancedRows`、`p16_button_unify_test.dart:431-466`。

### 所有模式（4 项）

#### C-1 删角色卡 AI RP 与急救按钮
- `GpPlCharCardKeys.aiBtn`（`gp_pl_char_card.dart:45/281-297`）、`RoomKeys.action('aid.apply')`（`:245-268`）删除。
- ⚠️ 用户说「聊天栏和玩家工具栏有相同的按钮」**不属实**：聊天栏有 AI RP 真入口（`gp_feeds.dart:50/785-800`），工具栏**没有** AI RP、也**没有**急救（只有「治疗」弹层入口）。删除仍安全（功能有去处），但**报告里要写清**。
- `roomTapFixedGrid2` 固定 2 列（`:231`/`:298`）删 2 个按钮后只剩 2 个，布局要复查。

#### C-2 舞台单位名字看不清
`stroke_painter.dart:114` `TextStyle(color: Color(0xff222222))` 写死（`MarksPainter`）。
**改法**：按**画布底色**取对比色（见 C-4 白板：无素材时画布为白，标签必须深色；有素材时按素材明暗或加描边/半透明底衬）。
- ⚠️ **别误改 `:135`** 的 `DoodlePainter` 默认笔色 `0xff000000`（P16 已改，`p16_wave1_theme_test.dart:64` 钉死）。
- `room_theme.dart:11-17` 的 `kDrawColors` 是画笔色且纯 Dart，**不能放 Theme 取色**。

#### C-3 奖励骰/惩罚骰加减与归零
`gp_dice_bar.dart:234-251` 只能 `setX(+1)`；`setBonus/setPenalty`（`room_ui_local.dart:159-172`）传 0 即归零，逻辑现成只缺 UI。
**改法**：每项加「−1」与「归零」两个可点区（或长按归零），保留既有 key；新增控件过 `clampBtnText` + textScaler。

#### C-4 无公开素材时舞台改白板
`gp_map_stage.dart:268-269` + `:301-303` 两处 `surfaceContainerHighest` → **无公开素材时改 `Colors.white`（硬白，不半透明）**，空态文字色同步。
- 不影响 P16 的「KP 战斗态 gpMap 换战斗列表」（`room_game_page.dart:818-820` / `_combatStageCell`）。
- 与 C-2 **强冲突**：白板后标签不能按主题 `onSurface` 取色。

### APP 首页（1 项）

#### H-1 头图文字
`lib/ui/home_page.dart`：
- 删 `COC 7th`（`:574-581`）与 `克苏鲁的呼唤 第七版 · 车卡器`（`:650-657`）。
- 版本号现在在第三行（`:662-670`，`key: home_app_version`，真源 `lib/app_version.dart:24`）→ **移到 Header 第二行**（原「COC 7th」位置语义：`骰境TRPG` 下方、`开始冒险` 上方）。
- ⚠️ 用户说「COC 7th 在骰境TRPG 下方」**不符**：两者在同一 `Row`（标题右侧）。按**位置语义**施工，不按字面行内位置。
- `app_version_test.dart:47-57` 不断言位置 → 保留 key + 文案即绿。

---

## 3. 批次切分与文件独占

> 纪律：**同一文件只能有一个 worker 动**。重叠就串行。

### 波1（并行，5 组，文件集互不重叠）
| 组 | 独占文件 | 任务 |
|---|---|---|
| **W1-A 请求链路** | `room_request_watcher.dart`、`room_model_host_intent.dart`、`sheets/sheet_treat.dart` | KP-1 全部（去重键 + `confirmPending` + 通知反馈） |
| **W1-B 聊天栏** | `gp_feeds.dart`、`gp_privates.dart`、`sheets/sheet_chat_composer.dart` | KP-4 高度 + KP-5 全屏发送 |
| **W1-C 玩家角色卡** | `gp_pl_char_card.dart` | P-1 LUK、C-1 删两按钮、P-3 `保存到已保存` 加锁 |
| **W1-D 舞台取色** | `gp_map_stage.dart`、`painter/stroke_painter.dart` | C-2 标签取色 + C-4 白板（**必须同人同批**） |
| **W1-E 首页** | `lib/ui/home_page.dart` | H-1 |

### 波2（等波1，独占最热文件）
| 组 | 独占文件 | 任务 |
|---|---|---|
| **W2-A 页面总装** | `room_game_page.dart`、`room_layout.dart`（如确需）、`room_ui_local.dart` | P-2 战斗栏置顶、P-4 工具栏删按钮+重排、C-4 槽位核对、KP-1 的 watcher 挂载核对、§6-Q5 治疗入口 |
| **W2-B 骰子条与工具栏** | `gp_toolbar.dart`、`gp_dice_bar.dart` | P-3 统一禁用接入、P-4 重排落点、C-3 加减归零、KP-3 对抗入口核对 |
| **W2-C 更多工具与 KP 面板** | `sheets/sheet_misc.dart`、`sheets/sheet_kp_panel.dart` | P-3 两申请按钮、KP-8 音乐入口上移、KP-3 对抗入口核对 |

### 波3（等 §6 拍板 + 弹层/domain）
| 组 | 独占文件 | 任务 |
|---|---|---|
| **W3-A 场景检定** | `sheets/sheet_scene.dart`、`gp_scene_check_kp.dart`、`domain/room_model_actions_room.dart`（难度部分） | KP-2（含大小写统一） |
| **W3-B 对抗** | `sheets/sheet_opposed.dart`、`domain/room_model_actions_combat.dart`（`checkOpposed`/`opposed`） | KP-3（删入口 + 技能框 + 载荷对齐） |
| **W3-C 定向指令** | `sheets/sheet_kp_directives.dart` | KP-6（补输入 + 删两按钮） |
| **W3-D 行动顺序** | `gp_combat_list.dart`、`gp_combat_strip.dart`、`domain/room_model_actions_combat.dart`（`combat.set` 路径） | KP-7 |
| **W3-E domain 战斗单批** | `domain/room_model_actions_combat.dart` | **W3-B 与 W3-D 共用该文件 → 必须同批串行，不许并行** |

> ⚠️ `domain/room_model_actions_combat.dart` 同时被 KP-2/3/7 碰，**只能一个 worker 串行改**。建议 W3-B → W3-D 顺序。

### 波4 · 总装与测试口径
**独占**：所有**既有测试文件**、`pubspec.yaml`、`lib/app_version.dart`、`pubspec.lock`。
任务：统一更新既有测试口径（更强或等价）、升 `2.30.0+100`、跑全量 `flutter test --no-pub` + `dart analyze`、逐文件哈希。

### 波5 · QA 独立复核 + 出包
独立跑全量、反向证伪（至少 5 处）、出包、AOT 三 ABI 校验、字面量字节级验证、更新 `_manual_test_checklist.md`。

---

## 4. 测试纪律（分批执行）

1. **波1/波2/波3 并发写码期**：只改自己文件集内的生产代码 + **新建** `test/p17_<组>_test.dart`；**不得修改任何既有测试文件**；**不得跑 `flutter test`**（并发争抢 `.dart_tool/flutter_build`）。静态自检只用 `dart analyze <自己文件>`。
2. 报告中列「预计会因本次行为变更转红的既有测试清单 + 建议口径」，交波4 统一处理。
3. **波4（独占串行验证期）**：引用各组产出，统一更新所有既有测试，独占跑全量 + `dart analyze`；报告逐文件哈希、改了哪几条、为什么更强或等价。
4. **波5 QA**：独立跑全量 + 定向反向证伪（改坏 → 跑红 → 逐字节恢复），报告恢复后 sha256 清单。
5. **新增守卫必须自证咬得住**：P16 踩过「三条断言因 fallback 恒真」。每加一条关键断言，自己做一次改坏 → 必须红 → 恢复。

### 4.1 已知「假绿」清单（波4 必须改写成真断言，不许留着当通过）

| # | 位置 | 为什么是假绿 | 怎么改 |
|---|---|---|---|
| 1 | `room_ui_entry_test.dart:778-786` | 断言 `card.contains('GpPlCharCardKeys.aiBtn')`（**源码里搜 key 名**），而本批按纪律**保留了 key 常量定义**、只删渲染 → 删了功能测试反而更绿 | 改成「渲染点零命中」：`find.byKey(GpPlCharCardKeys.aiBtn)` → `findsNothing`，并新增「聊天行 / 工具栏的 AI RP 真入口仍在」正向断言 |
| 2 | `room_ui_permission_test.dart` T-30 探针 | 锁定态断言若写成「`enabled` 等于 `gate.can(op)`」，在 `locked=false` 夹具下恒成立，锁不锁都绿 | 新增**锁定态夹具**：`locked=true` 时断言 `enabled == (gate.can(op) && !locked)`，并保留白名单项（更多工具 / 推进1轮 / 缩放）的 `enabled == true` 正向断言 |
| 3 | 任何「点了没反应」类断言 | `RoomTap` 禁用时 `onTap` 置 null，与 `warnIfMissed` 吞掉点击**不可区分** | 不许用「点击后无异常」当断言；必须直读控件字段（`enabled` / `TextField.enabled` / `onTap == null`）+ 断言「零发包」 |
| 4 | 战斗信息栏「控件存在」类断言 | 战斗列表移到 gpMap 格后，若只断言 `GpCombatList` findsOneWidget，探索态（不渲染）与战斗态都可能有别的实例 → 分不清 | 必须按**槽位后代**取：`find.descendant(of: keyOfSlot(gpMap), matching: ...)`，并成对断言「探索态该槽位是 `GpMapStage`」「战斗态默认是列表、点 `combatToggleKey` 后是舞台」 |
| 5 | 等高类断言（KP-4） | 只断言「三块都存在」无法证明等高 | 必须取三个 `Card` 的 `Rect.height` 断言两两差 ≤1dp，并断言 top/bottom 对齐 |
| 6 | 难度四档（KP-2） | 只断言「界面有四个按钮」不能证明规则生效 | 必须端到端：`HARD` 阈值 ÷2、`EXTREME` ÷5、`CRITICAL` 只有 01 过；并加反向证伪（把归一去掉必须红） |
| 7 | 定向指令输入（KP-6） | 只断言「有输入框」不能证明值进了载荷 | 断言载荷字段精确值；留空时必须断言 `p.keys` **不含** `base` 等可选键 |

---

## 5. 交付

- `dice-realm-v2.30.0.apk`（SHA256 + 字节数写入 `_manual_test_checklist.md` 顶部）。
- 真机待测项登记（重点：KP-1 连续申请、KP-2 四档、KP-3 攻击对抗、KP-4 三栏等高、KP-5 全屏发送、KP-6 定向指令输入、KP-7 插队、P-3 昏迷锁定、C-3 奖惩骰、C-4 白板、H-1 首页）。
- 不跑真机 / adb / 模拟器。

---

## 6. 用户已拍板结果（2026-11-14）

| # | 决策 | 施工口径 |
|---|---|---|
| **Q1** | **KP-2 四档 = 结果等级当「成功阈值」** | 选「成功」= 掷骰 ≤ 技能值；「困难成功」= ≤ floor(base/2)；「极难成功」= ≤ floor(base/5)；「大成功」= 只有掷出 01 才算成功。`difficulty` 白名单扩为 `REGULAR/HARD/EXTREME/CRITICAL` 四档（统一大写入库、domain 侧大小写归一必须做对）。**不改 `room_rules_combat.dart` 计算式**；阈值计算复用 `room-rules.js:120-123` 的 `regular/hard/extreme` 三档 + `CRITICAL` 特判（`== 1`）。 |
| **Q2** | **KP-3 反击 = 取代原对抗值** | 怪物/NPC 防守方：选「反击」→ 输入**检定等级** + **伤害骰式**（支持 `2D6+D4+1`）；选「闪避」→ 只输入检定等级。**去掉原来的 1-100 对抗值输入框**。载荷按 §2-KP-3 的 `aSeat/aSkill/aBase/bSeat/bSkill/bBase` + 反击 `counter` 分支的等级/伤害字段；伤害结算复用现有 `max(0, raw - armor)`，**不改规则计算式**。 |
| **Q3** | **KP 不需要治疗按钮** | 用户的真实意思是：**玩家点「治疗」提交申请后，KP 视角没收到推送、无法同意**。→ 不加 KP 治疗入口；KP-1 的修复重点改为「**玩家 `aid.apply` / `aid.psycho` 申请必须真的到达 KP 并弹窗**」，不只是「第二条被去重吞掉」。W1-A 已追加核查完整链路。 |
| **Q4** | **KP-6 SAN 大失败追加 = 只追加最近一次** | **不新增任何存储结构**（不碰存档快照）。复用现有 `sheet.sanloss{seat}`（老 APP 一键掷 1D10）。若房间状态里已有「最近一次 SC 大失败」的记录就直接用其数值，没有则按老 APP 掷 1D10 追加。按钮 UI 只需「选目标 → 确认」，无数字输入。 |
| **Q5** | 「更多工具」在昏迷/疯狂时放行 | 按用户口径：锁定态只放行「推进 1 轮」+「更多工具」，其余全禁（含整棵工具栏、骰子条、保存按钮）。老 APP 里更多工具是被锁的一方，此为用户明确改动。 |
