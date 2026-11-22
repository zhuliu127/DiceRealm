# P8 规则层 / 精神状态 / 数值 bug 报告（rules-dev）

> 分支范围：需求 6、7、9 + 朋友 bug 1、bug 2（需求 11 的权重部分）
> 环境：Flutter 3.47.9 stable / `flutter analyze` 无 issue / 全量测试见文末
> 红线遵守：`lib/domain/**` 零 Flutter / dart:ui / dart:io；未碰
> `home_page.dart` / `ai_create_page.dart` / `card_detail_page.dart` /
> `create_flow_page.dart` / `step_basics.dart` / `art.dart` / `roster_page.dart`。

---

## 0. 结论速览

| 项 | 结论 |
|---|---|
| 需求 6 精神状态模型 | ✅ 状态机落地（`madness_state.dart`），三处真实接线（车卡 / 跑团 SAN / 轮次 / 治愈） |
| 删除「昏迷」精神状态 | ✅ 卡片 chip、规则常量、房间白名单三处同步删除；**身体状态**的 `dying/unconscious` 未动 |
| 「潜在疯狂」新增 | ✅ 新值；老值「不定疯狂（症状消失）」幂等翻译成新值（老存档兼容） |
| 不定 ↔ 潜在 互斥 | ✅ 状态机规整 + 车卡 chip + 房间 sanitize 三处同一判据 |
| 临时 / 不定期间不掉 SAN、不长新症状 | ✅ SAN Check 入口锁 + `afterSanLoss` 二次守卫 + 精神分析失败对疯者不扣 SAN |
| 潜在疯狂掉 SAN 复发 + 新症状 | ✅ `nextMentalState(sanLost)` → `spawnSymptom=true`，房间侧按该标记真的掷一条新症状 |
| 治愈按钮 / 精神分析成功取消两状态 | ✅ 房间 `cureIndefinite` 与 `psychoAnalyze` 成功分支同时清「不定 + 潜在」 |
| 背景「疯狂症状」永久、不可治愈、不联动 | ✅ normalize 只从**背景来源**派生；治愈明确回「不可治愈」；跑团临时症状不再派生该标记 |
| 需求 9 广播覆盖 + 2 秒 | ✅ `showSlotNotice()`：先移除当前 SnackBar 再显示，`duration: 2s` |
| 朋友 bug 1 故障值 > 100 | ✅ `weapon_rules.dart` 校验 1..99（空 /「——」= 不会故障），自定义武器保存前拦截 |
| 朋友 bug 2 一键分配 | ✅ 单技能不超上限、非母语语言最多 1 门、常用技能加权优先、两池仍能花完 |

---

## 1. 需求 6 / 7：精神状态

### 1.1 单一事实源

新建 **`lib/domain/madness_state.dart`**（纯 Dart）：

- 取值常量：`正常 / 临时疯狂 / 不定疯狂 / 潜在疯狂 / 疯狂症状 / 永久疯狂 / 其他`
  —— **没有「昏迷」**；`kMentalChoices` 即 UI chip 顺序。
- 历史值兼容：`kMentalLegacyPotential = '不定疯狂（症状消失）'` → 读入翻译为「潜在疯狂」；
  `'昏迷'` 直接丢弃。
- `normalizeMentalList()`：幂等规整 + 互斥（永久疯狂 > 正常 > 不定疯狂）。
- `nextMentalState(current, event, {fromIndefinite})`：**唯一**状态迁移实现。
- `blockedByMadness / blockedFromNewSymptom / isPotentialMadness`：判据集中。

### 1.2 状态机真值表

| 当前状态 | 事件 | 新状态 | 生成新疯狂症 | 说明 |
|---|---|---|---|---|
| 不定疯狂 | symptomFaded(fromIndefinite) | 潜在疯狂 | 否 | 症状随轮次消失 → 潜在 |
| 临时疯狂 | symptomFaded | 正常（或保留其余项） | 否 | 临时不会变潜在 |
| 潜在疯狂 | sanLost | 不定疯狂 | **是** | 任意 SAN 损失即复发，必须加一条新症状 |
| 不定疯狂 | sanLost | 不定疯狂（不变） | 否 | 期间不掉 SAN / 不长症状（调用方拦截扣值） |
| 临时疯狂 | sanLost | 临时疯狂（不变） | 否 | 同上 |
| 不定 / 潜在 | cured | 正常（或保留其余项） | 否 | 治愈按钮 / 精神分析成功 |
| 疯狂症状 | cured | 疯狂症状（不变） | 否 | 背景标记，不可治愈（需求 7） |
| 永久疯狂 | cured | 永久疯狂（不变） | 否 | 撕卡级，不由治愈取消 |
| 任意（非永久） | backgroundMadness | + 疯狂症状 | 否 | AI / 随机 / 手动选表同一路径 |
| 任意 | sanZero | 永久疯狂 | 否 | 旧口径不变 |

### 1.3 落点（文件 → 规则）

| 文件 | 改动 |
|---|---|
| `lib/domain/madness_state.dart` | 新建：常量、规整、状态机、判据 |
| `lib/domain/rules_coc7.dart:784-801` | `mentalStatus = ms.kMentalChoices`；删「昏迷」，加「潜在疯狂」；新增 `mentalPotential/mentalTemporary/mentalIndefinite` 常量别名 |
| `lib/domain/normalize.dart:141-160, 184-222` | 精神状态迁移走 `normalizeMentalList`；「昏迷」丢弃、「症状消失」翻译；「疯狂症状」**只**由背景症状派生（含背景文本 `【疯狂发作】`，见下） |
| `lib/ui/status_ops.dart:153-190` | chip 点击互斥：不定 ↔ 潜在；废弃值点击无效；「疯狂症状」仍是派生项不可点 |
| `lib/ui/card_edit/status_editor.dart:176-297` | 进入临时/不定疯狂时自动掷一条会过期的疯狂症；「推进 1 轮」走 `nextMentalState`（不定→潜在、临时→正常）；提示条改单槽 |
| `lib/domain/room_model_actions_room.dart:37-70, 205-215` | 白名单删「昏迷」、加「潜在疯狂」；`kRaMentalIndefFaded` 作为旧名别名指向新值；`raMemberMadActive` 仍是「临时/不定」 |
| `lib/domain/room_model_actions_sheet.dart` | ① 精神状态 sanitize 走 `normalizeMentalValue`（老值翻译 + 互斥）；② `afterSanLoss` 对临时/不定直接返回「不获得新症状」；③ 潜在复发走 `nextMentalState` 且**按 `spawnSymptom` 才掷新症状**；④ `advanceMadness` 轮次迁移走状态机；⑤ `cureIndefinite` 同时清不定 + 潜在，背景症状回「不可治愈」；⑥ 精神分析失败对疯者不扣 SAN；⑦ `addSymptom` 不再给跑团症状加「疯狂症状」标记 |

### 1.4 需求 7 的两个入口

- **背景文本来源**：`normalize` 除了看 `madness` 数组的 `bg/permanent`，还认背景文本里的
  `【恐惧症】/【狂躁症】/【疯狂发作】` 标记 —— 随机出卡 8/10 是「疯狂发作」，
  它不在 100 条子表里，只存在于背景文本；不认它就会出现「背景有疯狂症、精神状态却没标记」。
- **AI 车卡 / 随机出卡**：两者都写 `background.phobias` 后经 `character_repo.save → normalize`，
  与手动选表走同一条 preset 路径，不需要各自写一份判定。

---

## 2. 需求 9：疯狂消息广播

- 根因：`status_editor` 直接 `ScaffoldMessenger.showSnackBar`，Flutter 的 SnackBar 是**队列**，
  默认 4 秒/条 —— 连点「推进 1 轮」会排队，新消息必须等旧消息播完。
- 修法：`lib/ui/card_edit/status_editor.dart:44-56` 新增 `showSlotNotice()`：
  `removeCurrentSnackBar()`（立即移除，不排队）→ `showSnackBar(duration: 2s)`；
  面板内 5 处提示全部改走它。
- 房间侧 `RoomUiLocal.showNotice` 本来就是单槽 + 2s（无需改），`RoomNoticeOverlay` 也是单槽渲染。
- 测试 `test/p8_notice_slot_test.dart`：连续两条只显示新的；1.5s 仍在、2.5s 已消失。

---

## 3. 朋友 bug 1：自定义武器故障值

- 新建 `lib/domain/weapon_rules.dart`：
  - `weaponMalfunctionError(raw)`：`1..99` 整数合法；`100/120/-1/0/小数/字母` 全部拒绝；
    空与「——」放行（官方武器表里表示「不会故障」，如近战武器）。
  - 错误文案明确写 `1-99` 与「100 以上表示不会故障」。
- 接线：`lib/ui/create/steps/step_combat.dart#_WeaponFormState._save` 保存前校验，
  失败写 `weapon_error` 并**拒绝保存**（1 处 domain 函数调用，未改 UI 结构）。
- 其它武器数值（伤害 / 射程 / 次数）是自由文本（`1D10+2`、`20/50`），不强行数字化；
  仅提供 `weaponTextFieldError` 长度闸门备用，未改变现有行为。

---

## 4. 朋友 bug 2 / 需求 11：一键分配

`lib/ui/create/chargen_logic.dart#autoSpendPoints` 重做：

1. **单技能不超上限**：全部走 `applyPoint → canAdd`，本职/兴趣两套上限口径由 domain 判定；
2. **语言最多一门**：`interestCandidates()` 把 `其他语言`（flat 组，20 个实例）收敛成一门，
   母语 / 信用评级按 `capExempt / isGrowthOnly` 排除（与 `preset_gen` 同口径）；
3. **常用技能加权**：`skillUseWeight`（侦查/聆听/图书馆/潜行/闪避/心理学/急救/格斗/射击/
   医学/说服/话术/恐吓/魅惑/攀爬/汽车驾驶/精神分析…），兴趣点先喂权重最高的 6 项，
   喂满后再向其余技能兜底，保证「点数必须用完」的硬约束；
4. 职业点同样按权重排序后轮转，仍以 `canAdd` 为准；
5. `rng` 可注入，固定序列下结果可复现。

---

## 5. 测试账目

新增：

| 文件 | 用例数 | 覆盖 |
|---|---|---|
| `test/p8_madness_state_test.dart` | 17 | 选项无昏迷 / 老值翻译 / 真值表全分支 / 互斥 / 背景派生 / 跑团 SAN 拦截 / 潜在复发新症状 / 治愈 / 背景不可治愈 |
| `test/p8_notice_slot_test.dart` | 3 | 覆盖式提示 / 2 秒过期 / 面板无昏迷 chip + 进临时疯狂自动得症状 |
| `test/p8_weapon_chargen_test.dart` | 8 | 故障值 100/120/-1 拦截、97 通过、保存前接线探针；一键分配不超上限 / 语言 ≤1 / 常用占比高 / 固定 rng 可复现 |

回归（全部绿）：`status_ops_test`、`qa_probe_test`、`chargen_logic_test`、`oracle_rules_test`、
`oracle_normalize_test`、`step_background_test`、`create_flow_widget_test`、`create_extra_steps_test`、
`room_intent_dice_wiring_test`、`room_ui_kp_test`、`room_ui_pl_test`、`room_ui_feeds_test`、
`room_view_test`、`room_ui_gap_fill_test`、`oracle_preset_test`、`repo_test`、`ai_gen_test`、
`room_actions_test`、`room_card_writeback_test`、`p6_lan_sheets_test` 等。

全量：`flutter test` → **1634 passed / 3 failed**，3 条失败均为 UI 线文件
（`card_detail_edit_test` 两条：删除后回首页找不到标题「骰境TRPG」、导入后首页列表找不到新卡；
`p8_home_ui_test` 一条：卡详情快捷分享滚动），
与规则层改动无关（本线未碰 `home_page.dart` / `card_detail_page.dart`，
且失败点都在首页渲染，不在精神状态 / SAN / 武器 / 加点路径）。

### 老测试改动

| 文件 | 改动 | 理由 |
|---|---|---|
| `test/oracle_rules_test.dart` | `mentalStatus` 期望删「昏迷」、加「潜在疯狂」 | 需求 6 明确精神状态没有昏迷；`bodyStatus` 的「昏迷」保持不动 |

其余老测试一行未改（不删断言、不降标准）。

---

## 6. 反向自证伪（真的做过）

1. **删掉复发分支**：把 `madness_state.dart` 里
   `sanLost + 潜在疯狂 → 不定疯狂 + spawnSymptom` 短路成 `return unchanged`
   → `p8_madness_state_test` 的「潜在疯狂 + 掉 1 SAN」与「跑团侧：潜在疯狂掉 SAN」**两条同时红**。
   （第一次只红了单元测试 → 说明跑团侧还在自己写 if，于是把房间侧改成消费 `spawnSymptom`，
   再变异后两条都红 —— 这一步反过来证明了「三处真的走同一个状态机」。）
2. **放开语言筛选**：把 `interestCandidates` 里 `language_other` 从「单独收集只挑一门」
   改回「全部直接进池」→ `p8_weapon_chargen_test`「兴趣候选池里语言最多一门」红。
3. **删故障值区间判断**（读代码/临时改常量即可验证）：`weaponMalfunctionError` 直接 `return null`
   → 「100/120/-1 被拦」红。

变异均已还原，仓库内无 `MUTATION` 残留（`grep -rn MUTATION lib/ test/` 为空）。

---

## 7. 已知边界 / 交给 UI 线的两条

1. 房间玩家自助状态面板仍只给「正常 / 临时疯狂 / 不定疯狂」
   （`lib/ui/room/sheets/sheet_self_state.dart`，非本线文件）；
   潜在疯狂由系统在轮次推进时置入，不需要玩家自选；显示与治愈已正常。
2. KP 定向卡上的按钮文案仍是「治愈不定疯狂」，实际 domain 侧已同时治愈不定 + 潜在；
   改文案属 UI 文件（`sheet_kp_directives.dart`），建议 UI 线顺手改成「治愈疯狂状态」。
