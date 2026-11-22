# QA 独立复核报告 · P10 第 3 期 A 批

- 复核人：严过关（QA / software-qa-engineer-4）
- 工程：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 被复核交付：工程师 寇豆码（software-engineer-5）报告 `_p10_transport4.txt`（294 行）
- 复核时间：2026-11-11 凌晨（本报告所有数字均为**我自己跑出来的**，不引用工程师输出）
- 基线口径：上批 `qa_p10_3_report.md`（1853 全绿 / APK `c3740fd7…` 70,001,068 B）

---

## 0. 一句话结论

**PASS（Send To: NoOne）**。五项自检逐项复现（全量 **1871** 全绿、串行 1871 全绿、`dart analyze` 零、P4 13/13、P5 14/14），**独立出包与工程师逐字节一致**（70,001,068 B / `531e80ac…`），账目 1853 + 18 = 1871 算得平。

本批最像「掩盖问题」的两处，我都给了硬结论：

- **K3 探针从 `label` 搬到 `privates`**：搬家本身**正当**（`label` 是老 APP 直接渲染的公开字段），但搬完**确实留下一条没人守的缺口** —— 「暗骰 / 秘密检定的技能名不得进第三人视角」。原守卫在新口径下已经失效。**我补了独立反证用例（R1/R1b），实测生产代码不泄漏**，并另外发现一处**机械闸门缺口**（`reduce` 不看 `vis`，登记 P3）。
- **给既有 widget 用例加 `setUp` 替身**：替身是「同步化」（返回空串）而不是「返回同形态 PNG」，因此其中一条既有断言（`room_ui_entry_test:589`）**前提已经陈旧**，现在属于「假绿」。但它掩盖不了任何东西 —— 新行为被 C4/C5/C6 与我的 R4 四路覆盖。判定**接受 + 下一批改文案（P3）**。

另外给出一处对工程师**自检说法的修正**（对他有利）：他写「既有 avatar oracle 全绿 ⇒ `make()` 字节不变」，我最初怀疑该 oracle 只断言 `isNotEmpty`；实测 `oracle_preset_test` 走 `_expectJsonMatch` **整卡深比**，所以他的说法**成立** —— 但这条是我自己跑出来的，不是采信。

---

## 1. 五项自检独立重跑（原始输出）

| # | 项 | 命令 | 我的实测 | 与工程师报告 |
|---|----|------|---------|-------------|
| 1 | 全量测试（默认并发） | `flutter test` | `01:06 +1879: All tests passed!`（**工程师树 1871** + 我新增 8） | ✅ 1871 复现 |
| 2 | 全量测试（串行） | `flutter test --concurrency=1` | `04:42 +1871: All tests passed!` | ✅ 一致，无顺序依赖 |
| 3 | 静态分析 | `dart analyze` | `Analyzing dice-realm... No issues found!` | ✅ 零 |
| 4 | P4 门禁 | `node tool/qa/qa_p4_gate.js` | `==== 合计 13 条，失败 0 条 ====` / `P4_GATE IS_PASS: YES` | ✅ 13/13 |
| 5 | P5 UI 门禁 | `node tool/qa/qa_p5_ui.js` | `==== 合计 14 条，失败 0 条 ====` / `P5_UI_GATE IS_PASS: YES`；`jsStr(` 实测 **14 处**（`room_session_local×3 / room_session_remote×3 / room_text×1 / gp_combat_list×5 / gp_scene_check_pl×1 / gp_status×1`，白名单外 0） | ✅ 14/14、预算未扩 |

### 1.1 独立出包（只走 `bash tool/build_apk.sh`）

```
[2/3] 校验 AOT 产物
  8782728  1981-01-01 01:01   lib/arm64-v8a/libapp.so
  9749064  1981-01-01 01:01   lib/armeabi-v7a/libapp.so
  9044872  1981-01-01 01:01   lib/x86_64/libapp.so
===== 出包成功 =====
-rw-r--r-- 1 60965 197609 70001068 2026-11-11 02:35 .../app-release.apk
531e80ac9d8fd7793b46a9741b7052c264847f2820f3275fd19d832464b07a59 *.../app-release.apk
签名：debug（可侧载安装、不可上架）
```

| 项 | 工程师 | 我 | 判定 |
|----|--------|-----|------|
| 字节数 | 70,001,068 | **70,001,068** | ✅ |
| SHA256 | `531e80ac…b07a59` | **`531e80ac…b07a59`** | ✅ **逐字节一致**（比 team-lead 要求的「字节数 + 三 ABI」更强） |
| 三 ABI | 8,782,728 / 9,749,064 / 9,044,872 | **完全相同** | ✅ |
| 与上批比 | 字节数巧合相同、SHA 不同 | 上批 `c3740fd7…` | ✅ 同一字节数不同内容，属良性巧合 |
| `enable-native-assets` | true | `flutter config --list` → **`enable-native-assets: true`** | ✅ 出包后恢复 |
| `build` junction | 未删 | `build -> /d/dev/dice-build` 仍在；全程未 `flutter clean` | ✅ |

**AOT 字面量实证**（从 APK 里取出 `lib/arm64-v8a/libapp.so`，8,782,728 B，按 UTF-16LE / UTF-8 双编码统计）：

```
kPotential(潜在疯狂)      utf-16-le hits=8      utf-8 hits=0
relapse(不定疯狂复发)      utf-16-le hits=1      utf-8 hits=0
pngPrefix(data:image/png;base64,)  utf-8 hits=1
svg stop-color="                    utf-8 hits=3
```

⇒ 本批新代码（自动头像 PNG 前缀、潜在疯狂判据）**确实进了 AOT**。中文是 UTF-16LE，用 `grep -a` 搜中文会全 0，别误判成「没进包」。

---

## 2. 账目核对（1853 + 18 = 1871）

| 项 | 我的独立计数方式 | 结果 |
|----|-----------------|------|
| 新文件 `test/p10_t3_broadcast_potential_png_test.dart` 用例数 | `grep -cE "^\s+(test|testWidgets)\("` + 逐条列出（A1-A5 / B1-B5 / C1-C8） | **18** |
| 是否有 `for` 动态注册 | 逐条看：唯一循环在 `C1`（4 个名字）与 `B5`（扫目录）**函数体内**，注册数各仍为 1 | **无动态注册** ⇒ 文件内注册数 == 运行数 |
| 5 个被改既有文件的用例数 | `p10_t2_avatar_test` **19**（与上批清单记载的 19 相同）、`room_history_export_test` **24**（K3 组 3 条都在）、`room_ui_entry` 22 / `room_ui_lobby` 18 / `room_ui_player` 3 | 未见「整组消失」 |
| 总量 | 1871（工程师树实测）− 18（新文件）= **1853** = 上批 QA 独立复核的基线 | **算得平** |
| 我新增的 QA 用例 | `test/qa_p10_4_verify_test.dart` **8** 条 | 现全量 **1879** 全绿（`00:00 +8: All tests passed!` / `01:06 +1879`） |

⇒ **没有既有用例被删**（若删了，1871 这个数不可能正好等于 1853 + 18；且 5 个被改文件的组结构与断言我逐条读过，见 §3）。

---

## 3. ★★ 既有测试改动裁决（本批最高风险）

### 3a. 加 `setUp(_stubAutoAvatarPng)`（4 个文件，6 处）

替身实际实现（三份一字不差）：

```dart
void _stubAutoAvatarPng() {
  final saved = autoAvatarPngEncoder;
  addTearDown(() => autoAvatarPngEncoder = saved);
  autoAvatarPngEncoder = (spec) async => '';
}
```

**注意：它返回的是空串，不是「同形态 PNG」。** team-lead 要我判断的正是这一点，逐条结论：

| 文件 / 用例 | 断言有没有变 | 替身让断言验的是同一件事吗 | 裁决 |
|---|---|---|---|
| `p10_t2_avatar_test` E1「没有头像 → 不存在 avatar 键」 | 一字未改（`containsKey('avatar') isFalse`） | **语义漂了**：改前「没有上传头像」天然等于「没有可广播头像」；现在生产会给自动 PNG，本用例只有在替身返回空串时才成立。它实际验的是「生成器拿不到东西 → 删键」 | 接受（降级路径仍被测，且 E3 已覆盖「两条都抛」），**P3 建议改名** |
| E2「有头像 → sheet.avatar 就是缩略 dataURI」 | 未改 | 是（走的是 ① 缩略链路，替身根本不参与） | ✅ 无影响 |
| E3「缩略图抛异常也不挡绑卡」 | 未改（还把自动头像那步也改成抛） | 是，范围还**变宽**了 | ✅ 反而更严 |
| `room_ui_entry_test` / `room_ui_player_test` / `room_ui_lobby_test` 各一处 `setUp` | 未改 | player / lobby：文件内**零头像断言** → 纯同步化，无影响 | ✅ 无影响 |
| 同上 · `room_ui_entry_test:589` | **未改（是上批 P10-2A 加的）** | **不是同一件事了**：`expect(containsKey('avatar'), isFalse)` 注释写「没有头像 → 不带该键」，而本批之后**没上传头像的玩家就是会带键（自动 PNG）**。这条现在靠替身返回空串才绿 | **接受但记 P3**：属「前提陈旧的假绿」，不属「掩盖缺陷」（新行为被 C5/C6/C4 + 我的 R4 覆盖） |

**「是不是把不可测的路径绕过去」**：不是。`picture.toImage()` 是引擎真异步，fake-async 区域永不完成，这与既有 `avatarThumbEncoder` 的可注入端口是**同一套既有规矩**（`repo/avatar_thumb.dart:109-117` 的 typedef + 全局实例 + `addTearDown` 还原），不是本批为过关新发明的开关。判断依据：**端口是生产代码里既有的可注入点，且 C4 用 `tester.runAsync` 跑了真编解码**（前缀 / PNG 魔数 / 解码 / ≤20000 全断言）——真路径没有被绕过，只是不在 widget fake-async 里跑。

### 3b. ★ `room_history_export_test` K3 探针搬家 —— **有缺口，我已补钉**

**先确认搬家本身正当**：老 APP `ui/room-panels.js:1593-1601` 的骰行是两行 `🎲 昵称 · expr ＝ total` / `levelText · label`，`d.label` 是**公开渲染字段**。旧用例把 `DARK_ROLL_LABEL` 藏在公开骰的 `label` 里当「秘密探针」，是「label 反正不显示」的副产物 —— 那条断言原本守的是「导出不得含 label」，与「label 里的东西是秘密」是两件事。所以「label 不再当探针」这个决定**成立**。

**但搬完之后，原来那条保证没有接班人**。风险点变成：

1. 现在 `label` 会显示（`diceLine` 前置 + `FeedRow` 印昵称）⇒ **暗骰 / KP 暗骰 / 秘密检定的 label 会不会出现在公开记录或导出文本里？**
2. 谁来守？—— 全量 1871 里**没有一条用例**用「带敏感 label 的暗骰」验证过第三人视角。工程师的 A4 造了 `secret:true` 的暗骰，但**没给 `label`**（`test/p10_t3_broadcast_potential_png_test.dart:232-235` 只有 `expr/direct/secret`）；K3 的新正例只钉「公开技能名必须出现」。⇒ **确实是覆盖缺口**。

**我自己动手补了并跑通**（`test/qa_p10_4_verify_test.dart`，属测试文件，按分工允许）：

- **R1**：`p1` 掷 `secret:true` + `label: 'SENTINEL_LBL'` → 逐项断言 **p2 / p3 三个视角**：① `collectFeeds`+日志+私密栏全部文本搜不到；② `buildRoomHistoryExportText` 导出文本搜不到；③ **整份 `jsonEncode(state)` 兜底搜不到**；④ 公共侧仍有一条「暗骰了一次」脱敏提示。
  同时**加了探针前置**：`p1` 自己的私密栏与 KP 视角**必须**搜得到 `SENTINEL_LBL` —— 否则「没泄漏」是空话（这条前置当场抓到我自己的一个 bug：哨兵串 26 字符被 `cleanText(label,20)` 截断变成「搜不到」，是**假绿**；改成 12 字符后才有意义）。
- **R1b**：KP 秘密对抗（`check.opposed secret`）的 `skill` 也带哨兵 → p2/p3 视角同样零命中。
- **R2 正例**：公开检定 → p2 **与 p3** 的记录栏都拿到「甲 + 侦查：前缀 + 1D100 →」（防止有人用「谁都不显示」骗过 R1）。

**结果：全绿**（暗骰/秘密检定的 label 现在确实不泄漏）。**反向证伪**：把 `diceDirect` 的 `if (jsTruthy(p['secret']))` 改成 `if (false && …)`（= 暗骰走公开链路）→ **R1 立即红**（`Expected: false / Actual: <true>`），其余 7 条不受影响 ⇒ 这条用例是真的在守。

**另外发现一处机械闸门缺口（潜在，不是本批引入，P3 登记）**：
`apply()`（`room_model_host_core.dart:151-162`）对**所有**事件无条件 `reduceRoomState`，而 `reduce` 的 DICE 分支（`room_model_reduce.dart:90-107`）**完全不看 `evt.vis`**。`emit()` 的唯一闸门是「非 SEAT 且 payload 含 `kSecretKeys`（`secret/hidden/kpOnly/truth/clue/spoiler/answer`）才 scrub」——`label` 不在其中。
⇒ 若将来有人 `emit(RoomEvt.dice, {..., label}, vis: RoomVis.kp)` 且 payload 不带 `secret` 键，技能名会直接进公共 `state.dice` → **记录栏 + 导出都能看到**。今天安全**只因为没有任何这种调用点**（`diceRoll` 恒 `vis: public`，暗骰走 `RoomEvt.private_`）。建议下一批在 `reduce` 侧对非 public 的 DICE 直接丢弃 + 记 warning（机械防呆），而不是靠约定。

---

## 4. 「呈现层缺口」这个诊断是否成立 —— **成立**

三条证据链，互不依赖：

1. **老 APP 口径**（`ui/room-panels.js:1583-1601`，我读的原文）：`dice` 行 = `feedAvatar` + `🎲 (nickname) · (d.expr)` + `＝ total` + 次行 `levelText · label`。⇒ 老 APP **同时**显示昵称与技能名。
2. **新 APP 改后代码**：`feed_view.dart#diceLine`（`:206-224`）在 `label` 非空时前置 `'$label：'`；`collectFeeds`（`:124-137`）为 dice 行填 `nickname`；`gp_feeds.dart#FeedRow`（`:326-336`）的 `showWho` 条件包含 `item.kind == FeedKind.dice`（注释写明改前只在聊天栏印）。⇒ 三件事（**谁 / 什么技能 / 成功等级**）现在都在。
3. **跨会话实证**（不是读权威端 state）：我的 **R2** 把 `SendPlan` 按 `to` 分别投进 p2、p3 两个真实 `RoomClient`，断言两侧 `collectFeeds` 都出现「昵称 + 技能名前缀 + 掷值」。**证人 = p2/p3 收到的分发的产物**。

**「改前是否真的『已 PUBLIC 但无昵称/无 label』」**：`SharePlan` 侧我没法翻改前源码（无 git），但我能确认两件事：① 改后 `FeedRow` 的 `showWho` 是**在既有条件上 `|| item.kind == FeedKind.dice`**（新增项），② `diceLine` 的 `label` 分支带注释「改前只剩 `1D100 → xx`」。加上老 APP 有昵称 + label 而用户抱怨"看不出是谁"，诊断自洽。
⚠️ 这一条严格说是**代码自洽 + 老 APP 对拍**，不是「改前二进制对拍」；如果下一批要更强的证据，需要保留一版改前 APK 做同一操作的录屏对比。

**给清单的落地提醒**（已写入）：用户若仍说「看不到广播」，**先查记录栏在该机型/布局下是否展开**（P10 第 2 期 B 把记录塞进折叠档），别重复诊断 domain。

---

## 5. 真 bug（disarm 硬编码旧取值）验证

**修法判定：正确。** `room_model_host_core.dart:204-216` 用的是状态机判据：

```dart
if (mental_state.isPotentialMadness(mental)) { fadedArm[seat] = false; }
```

而 `isPotentialMadness`（`madness_state.dart:214-215`）= `normalizeMentalList(mental).contains(kMentalPotential)`，`normalizeMentalList` 内部把历史取值 `'不定疯狂（症状消失）'` 翻成 `'潜在疯狂'`（`:68`）。
⇒ 是「**用判据覆盖新旧取值**」，**不是**「把硬编码字符串再加一个新值」。下次再改名只需动 `normalizeMentalList` 一处，这里自动跟随 —— 这正是我要的形态。

**行为级验证**（不只看键值，看后果）：

| 用例 | 配置 | 断言 | 结果 |
|---|---|---|---|
| R3-1 | 潜在疯狂 + `fadedArm['p1']=true`（上回合已武装）+ **推进回合** + 再损失 1 点 SAN（< ceil(60/5)=12） | `fadedArm['p1'] == false`；仍是**潜在疯狂**、**未**复发为不定疯狂 | ✅ |
| R3-2 对照 | 同上但**不**推进回合（仍武装） | 1 点损失**必须**复发为不定疯狂 | ✅（证明 R3-1 的绿灯不是「本来就永不复发」） |
| R3-3 老卡兼容 | mental = `'不定疯狂（症状消失）'` + 推进回合 | `fadedArm['p1'] == false` | ✅ |

**反向证伪**：把 `if (mental_state.isPotentialMadness(mental))` 换回硬编码 `if (mental.contains('不定疯狂（症状消失）'))` →
**R3-1 红**（`Expected: false / Actual: <null>`）、**B1 红**、**B3 红**、**B5 红**（静态扫描抓到代码里又出现旧字面量）。
逐字节恢复后 `be3a39a5…b080dee` `cmp -s` 一致。

---

## 6. 自动头像 PNG 化核对

| 核对项 | 我的做法 | 结果 |
|---|---|---|
| `specOf` 让 `make()` 的 SVG **字节不变** | ① 拿 **Nov 8 的 `test/fixtures/preset.json`** 当旧版 oracle（10 张自动头像的完整 dataURI 串）→ `oracle_preset_test` 走 `_expectJsonMatch` 整卡深比（含 avatar）**全绿**；② 我另写 **R5** 直接从夹具读 `expect.avatar`，与今天的 `avatar.make(name)` / `make(name,'warm')` **逐字符**比 → 全部相等 | ✅ 双重成立 |
| （对 `make()` 的反向证伪） | 把 `specOf` 的 `dots: 6 + (hv % 5)` 改成 `7 + …` → **R5 红**，且 `oracle_preset_test` **也红**（报错逐字符指出 dot 坐标差异） | ✅ 两条守卫都真实 |
| 生成的是**真 PNG** base64 | C4 在 `tester.runAsync` 里跑真编解码：前缀 `data:image/png;base64,` / PNG 魔数 `89 50 4E 47 0D 0A 1A 0A` / 解码非空 / 长度 >500 且 ≤20000 / `roomAvatarDataUri(uri)==uri`。我的 **R4** 用真编码器再验一次前缀 + 可解码 + ≤20000 | ✅ |
| **老卡 SVG 本机是否仍能显示**（别弄丢） | 卡里的 `avatar` 值不被覆盖：`avatar.ensure` 已有值时原样返回（C7 断言 `kept == svg`）；R5 证明老 SVG 串今天能被原样重建 ⇒ 老卡头像没有丢。本机显示侧对 SVG 的既有降级（首字圆点）不变、不抛不空白 | ✅ 无回归 |
| **没上传头像的玩家跨设备能看到图** | **R4**：真 `autoAvatarPng(specOf('张三'))` → 写进 `p1` 的 sheet → `syncFor('p2')` → `feedAvatarOfSeat(p2.state,'p1')` 拿到该 dataURI → 渲染 `AvatarThumb` 后 **`find.byType(Image)` 命中 1、`find.text('张')` 为 0**；**对照组**传空串则 `Image` 为 0、首字圆点命中 1（证明上面的断言不是恒真） | ✅ **p2 视角是图，不是圆点** |

**新发现（P3，登记不修）**：`card_sheet_payload.dart:139` 是把 **`localAvatarRel(card.raw['avatar'])`**（相对路径或 null）交给 `avatarThumbEncoder`，而 `avatarThumbOf` 本身能处理 `data:` URI（`repo/avatar_thumb.dart:94-95`）。于是「卡的 `avatar` 已经是一条 `data:image/png;base64,…`」时：`localAvatarRel` → null → thumb 空 → `autoAvatarSpecOf` 又因 `startsWith('data:image/')` 返回 null → **走删键**，把本来就能广播的 PNG 丢了。
今天**不可达**（全库写 `card.raw['avatar']` 的只有：`''`、`avatar.make()` 的 SVG、本机相对路径），所以不是 bug；但导入/迁移场景一旦出现就该修（把 `localAvatarRel(...)` 换成原始值即可，`avatarThumbOf` 已经写好）。

---

## 7. 规则差异清单抽查（14 条里抽 3 条，含 D14）

抽查方法：**两边都读原文**，老 APP 读 `coc7th-card-app/.../js/core/room-model.js` 与 `room-rules.js`，新 APP 读源码，不看报告结论。

| 条目 | 报告给的定位 | 我核到的真实位置 | 结论是否站得住 |
|---|---|---|---|
| **D03** 伤害 → 身体状态 | 老 `:2216-2270` / 新 `room_model_actions_sheet.dart:817-880` + `raDeriveBodyFromHp` | 老：`:2216-2270` 是**调用点**（`applyStatusJudgment`），规则真身是 **`:4275-4327`**；新：`sheet.dart:817-880` 也是**调用点**，真身是 **`room_model_actions_room.dart:246-296`** | **结论「等价」成立**（我逐分支对拍 6 条：即死 `amount>maxHP`、归零 `after<=0` 且 hadMajor 分流、重伤 `amount*2>=maxHP` 且 `needCon` 判据、濒死回血、重伤解除、昏迷不降级；`undefined = 不动` 的整包语义也一致）。**但行号指向调用点，不指向规则本体** —— 下一批照这张图施工会先落到调用点，建议补真身行号 |
| **D08/D09** 不定疯狂累计 / 潜在疯狂复发武装 | 老 `:5271 统一式`、`:884-887`、`:984-1000` / 新 `sheet.dart:1272-1279`、`host_core.dart:118-119,198-212` | 老：`_afterSanLoss` = `:5160-5271`（**函数范围对**），公式真身 **`:5242-5245`**；`_fadedArm` 文档 `:882-886`；回合边界 disarm **`:996-1001`**。新：`sheet.dart:1274-1279`（`fadedArmed = fadedArm[seat] != false`、`oneFifth=(maxSAN/5).ceil()`、`relapseNow=` 三行**逐字对应**） | **成立**。`!= false` 的「缺省=武装」语义两边一致（老 JS 注释也写明 undefined=武装）⇒ 报告 §2.1 那个真 bug 的描述准确 |
| **D14** 对抗检定 | 老 `:5803-5992` / 新 `combat.dart:1088-1110` + `room_rules_opposed.dart`，标「⚠未穷尽」 | 老 `_emitOpposedCheck` 真身 **`:5811-5824`**（5803 是文档注释头）；判定核心在 **`room-rules.js:489-539`**（`opposedAttack` / `opposedFull`）。新 `emitOpposedCheck` 真身 **`:1085-1110`**；核心 `room_rules_opposed.dart` `_opposedAttack` `:118-200` | **「⚠未穷尽」偏保守**：判定核心我逐分支对拍（`level` 高者胜 → `fightback` 同级攻方胜 → `dodge` 同级攻方败 → `base` 高者胜 → 重掷 ≤10 轮低者胜 → 兜底判发起方胜），**与老 APP 一致**。真正没对拍的是**载荷装配**（`damage/rounds/decidedBy/targets` 拼装）与攻击对抗分支 ⇒ 建议下一批把 D14 从 **P1 降级**为「只对拍载荷形状」，别把整块当高风险重做 |

**另两条「非规则发现」复核属实**：
- `room_model_actions_combat.dart:82-83` `case 'check.push'` 直接 `return checkRequest(...)`：确认是**同一实现**，暂无 UI 入口调用。
- `rollCheckRequest`（`:963`）：`grep -rn "rollCheckRequest" lib/` **只有定义、零调用点**（死代码）。
两条我都同意「留给下一批」，本批不动。

---

## 8. 自证伪过程（4 处，全部逐字节恢复）

| # | 改动 | 期望 | 实测 | 恢复 |
|---|---|---|---|---|
| ① | `diceDirect` 的 `if (jsTruthy(p['secret']))` → `if (false && …)`（暗骰走公开链路） | R1 红、其余绿 | ✅ **R1 红**（`Expected: false / Actual: <true>`），R2-R5 绿 | `cp` 回备份 → `sha256=995a0307…c72615`，`cmp -s` 一致 |
| ② | `host_core` disarm 退回硬编码 `'不定疯狂（症状消失）'` | R3-1 + B1 红 | ✅ **R3-1 / B1 / B3 / B5 共 4 红** | `sha256=be3a39a5…b080dee`，`cmp -s` 一致 |
| ③ | `specOf` 的 `dots` `6+` → `7+`（`make()` 字节变化） | R5 + oracle 红 | ✅ **R5 红**；`oracle_preset_test` 也红（逐字符指出圆点坐标差异） | `sha256=248724a5…795249`，`cmp -s` 一致 |
| ④ | （自证伪的反向）怀疑 `oracle_preset_test` 只断言 `isNotEmpty` | 若如此，则工程师「oracle 全绿 ⇒ 字节不变」是空话 | **我错了**：它走 `test/support/oracle.dart:173 _expectJsonMatch` **整卡深比**，第③处证伪时立刻红 ⇒ 工程师的说法成立 | 无需恢复 |

恢复后复跑：`flutter test test/qa_p10_4_verify_test.dart` → `+8: All tests passed!`；全量 → `+1879: All tests passed!`。

---

## 9. 红线扫描

| 红线 | 实测 |
|---|---|
| 不跑 adb / 模拟器 / 真机 | ✅ 全程未跑（无 `adb`、无 emulator、无设备） |
| 只走 `bash tool/build_apk.sh` 出包 | ✅ 唯一出包入口 |
| 不删 `build` junction / 不 `flutter clean` | ✅ `build -> /d/dev/dice-build` 完好，未 clean |
| `enable-native-assets` 出包后恢复 | ✅ true |
| 不改生产源码 | ✅ 3 个文件证伪后**逐字节**恢复（三份 sha256 与备份逐一 `cmp -s` 通过）；唯一新增的源码级文件是**测试** `test/qa_p10_4_verify_test.dart` |
| `pubspec.yaml` | ✅ 未改（mtime Nov 10 21:35，早于本批） |
| `RoomEvt.values` | ✅ 仍 **27** 项 |
| `kRoomPolicy` | ✅ 仍 **61** 条 |
| `jsStr(` 预算 | ✅ 仍 **14** 处、白名单外 0（P5 门禁实测） |
| P4/P5 门禁脚本 | ✅ 未改 |
| 临时文件 | `.qa4_bak/`、`.qa4_tmp/` 用完即删（不入库） |

---

## 10. 智能路由

| 缺陷 | 类型 | 去向 |
|---|---|---|
| 暗骰 label 泄漏（若真发生） | — | **无**：实测不泄漏（R1/R1b 全绿），无需返工 |
| disarm 硬编码旧取值 | 真 bug | **已由工程师修好且修法正确**（判据覆盖，不是加字符串）。我复核通过，**无需返工** |
| `room_ui_entry_test:589` 前提陈旧（假绿） | 测试卫生 | **QA（我）**：不改断言（改了会和生产新口径打架），但已在报告 + 清单登记，下一批改文案/断言。**不阻塞发布** |
| `reduce` 不看 `vis` 的 DICE 潜在缺口 | 设计陷阱 | **下一批 Engineer**（机械闸门），本批登记技术债 |
| `card_sheet_payload` 对 `data:` URI 头像会删键 | 潜在边界 | 下一批 Engineer（一行改动），登记技术债 |
| D03 行号指向调用点 / D14 可降级 | 文档精度 | 下一批按修正后的定位施工 |

**最终判定：Send To: NoOne（PASS）**。

---

## 11. 真机清单更新点（本次已改进 `_manual_test_checklist.md`）

1. 头部 APK 指纹：`531e80ac…b07a59` / 70,001,068 B（旧值 `c3740fd7…` 保留为回滚行）。
2. 新增 **P0 · P10 第 3 期 A** 章节（5 条：公开记录能看到「谁·技能·结果·等级」/ SAN Check 全员可见 / 暗骰只有本人与 KP / 没上传头像跨设备是图 / 潜在疯狂回合推进后不再「任意损失即复发」）。
3. 技术债第 8 条「自动头像 PNG 未做」→ **已做**（改写，不留矛盾）。
4. 新增技术债：规则差异 14 条待修（下一批按清单施工，含 D03/D14 定位订正）、`rollCheckRequest` 死代码 + `check.push` 别名、`reduce` 不看 `vis` 的 DICE 闸门缺口、`card_sheet_payload` 的 `data:` URI 边界。
5. 尾部自动化数量 1853 → **1879**（工程师树 1871 = 1853 + 18，QA 独立复核另加 8）。
6. P10-2A 章节 D4「没设头像的人 → 首字圆点」加注：**P10-3A 起改为自动头像 PNG**。
7. P10-3A 章节写明：「用户若仍说看不到广播，**先查记录栏在该机型/布局下是否展开**（第 2 期 B 把记录塞进折叠档），别重复诊断 domain」。

---

## 12. 遗留（如实报）

1. **D14 载荷装配未对拍**（判定核心已对拍为等价）。建议下一批只对拍 `damage/rounds/decidedBy` 形状。
2. **D03 行号需订正**（老 `:4275-4327` / 新 `room.dart:246-296`）；表里其它条目的行号我只抽查了这 3 条，剩余 11 条**未逐条核行号**。
3. `room_ui_entry_test:589` 的陈旧前提：我**没有**改断言（改文案属工程师产线，且断言本身在"降级"语义下仍成立）。
4. 自动头像 PNG 的**精确字符数**仍只在测试里断言区间（`>500 且 ≤20000`），没打印实测值；C4 用的是真编码器，量级远低于上限不需要降档。
5. 未跑 adb / 模拟器 / 真机（按约定由用户统一测）。
6. QA 新增的 8 条用例已入库（`test/qa_p10_4_verify_test.dart`），因此**全量数字从 1871 变成 1879**；后续批次引用基线时请用 1879，勿当成工程师多写了 8 条。
