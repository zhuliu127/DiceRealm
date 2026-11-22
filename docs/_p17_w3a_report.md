# P17 波 3-A · KP-2 场景检定「检定方式」四档 · 交付报告

> worker：`p17-w3a`（寇豆码）　工程根：`$P = C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 依据：`_p17_construction_spec.md` §0/§1/§2-KP-2/§4/§6-Q1、`_p17_kp_landing.md` KP-2 节、`_p17_oldapp_research.md` A 节
> 文件集：原本独占 3 个（`sheet_scene.dart` / `gp_scene_check_kp.dart` / `room_model_actions_room.dart`），
> **team-lead 2026-11-14 批准追加 3 处**（`room_rules_sheet.dart` / `room_rules_core.dart` / `gp_scene_check_pl.dart`，各 1 处），
> 目的是让「HARD 真按 ÷2」在规则层真正生效 + 玩家侧 `CRITICAL` 文案不再回落成「常规」。

---

## 0. 一句话结论

四档「检定方式」的 **UI 骨架 + 载荷 + 阈值算式 + 大小写归一 + 规则层生效** 已全部落地，`dart analyze lib` / `dart analyze test` 双绿。
规则层只在**调用点**加了 `.trim().toLowerCase()`（`_normDifficulty` 本体、`DIFFICULTY` 键、`room_rules_combat.dart` 计算式一字未动），
逐输入验证：**除大写输入外，全部结果逐字节相同**（见 §2.1）；大写输入从「静默退化成常规」变成「真正 ÷2 / ÷5」（见 §2.2）。
未跑 `flutter test`（并发期禁跑），等价性由静态论证 + 临时 dart 脚本实测支撑，最终由波4 全量确认。

---

## 1. 逐项落点

### 1.1 `lib/domain/room_model_actions_room.dart`（难度唯一真源）
sha256 `7c180bab1a023e076d920a2673150a6d92fda67d4e7df4350da7ae1bcd27c61d`

| 行 | 内容 |
|---|---|
| `:417-429` | 四个常量 `kRaDifficultyRegular/Hard/Extreme/Critical`（`REGULAR/HARD/EXTREME/CRITICAL`，**全大写**） |
| `:432-437` | `kRaDifficultyLevels` 四档全序（由易到难）——白名单 / UI / 测试的唯一真源 |
| `:443-457` | `raNormSceneDifficulty()`：**大小写归一 + 未知值回落常规**的唯一入口 |
| `:460-477` | `raDifficultyThreshold(base, difficulty)`：**四档阈值算式**（见 §3） |
| `:479-486` | `raDifficultyPasses(value, base, difficulty)`：`value ∈ 1..100 && value <= 阈值`（CRITICAL 走 `==1` 语义） |
| `:489-501` | `raDifficultyRequiredLevel()`：四档 → 结果等级下限 2/3/4/5 |
| `:532` | `raSanitizeSceneSteps` 的 `difficulty` 改走 `raNormSceneDifficulty`（原 `:426` 的 `(HARD\|EXTREME)?diff:REGULAR`） |
| `:549` | `raDefaultSceneResolve` 的成功门槛从写死 `>= 2` 改成 `>= raDifficultyRequiredLevel(step['difficulty'])` |

> `raSanitizeSceneSteps` 输出对 `HARD`/`EXTREME`/`bogus` **逐字节不变**（`fixtures/room_model.json#M:sanitizeSceneSteps#957` 绿），
> 新增 `CRITICAL` 透传、小写 `hard` 归一成 `HARD`。

### 1.2 `lib/ui/room/widgets/gp_scene_check_kp.dart`（KP 场景检定栏）
sha256 `c2c40b09a14b34564ddcfbb84738db211c2c962ba25ad5d8f021bd234592354d`

| 行 | 内容 |
|---|---|
| `:79-94` | `KpSceneMode`（value/label/hint）；value 直接引用 domain 常量，**不写难度字面量** |
| `:96-101` | `kKpSceneModes` 四档文案表（成功 / 困难成功 / 极难成功 / 大成功 + 阈值说明） |
| `:104-109` | `kpSceneModeOf(value)`：未知值回落首档（防御历史存档） |
| `:132-147` | 新增 key：`modeRoot` / `modeTarget` / `modeSkill` / `mode(value)`；**既有 `root/progress/quickPush/editor/level(int)` 全部原样保留** |
| `:157-168` | `kpQuickSceneStep({skill, targetSeat, difficulty})` 参数化（默认值与改前一致），`difficulty` 默认取 domain 常量 |
| `:171-179` | `GpSceneCheckKp` 由 `StatelessWidget` → **`StatefulWidget`**（要持有 ①②③ 的本地草稿）；构造签名 `const GpSceneCheckKp({key, onOpenEditor})` 不变 |
| `:201-218` | ④ `_push()`：技能为空 → `ctl.notice('请先填写要检定的技能')`（不静默失败）；否则发 `scene.check.push`，steps 里带所选 `targetSeat` / `skill` / `difficulty` |
| `:243-291` | 新「检定方式」子块：`① 目标`（`UnitPickerField`，`allowAll: true` → 保留 `*=全体`）/ `② 技能 / 属性`（**纯文本框**，对齐老 APP `room-panels.js:1880`）/ `③ 四档`（4 个 `RoomTapTile`，选中项带 `Icons.check`）/ 当前阈值说明行 |
| `:274` | ① 目标那一行单独 `clampBtnText(...)`（只钳该按钮子树） |
| `:330-372` | 既有 8 格（6 档裁定 + 推送 + 编辑器）**结构、顺序、key、108×48 定宽全部不变**；只把「快速推送」文案改「推送检定」、行为改成发 ①②③ 选好的那一档 |

### 1.3 `lib/ui/room/sheets/sheet_scene.dart`（场景检定编辑器弹层）
sha256 `f553b2d3ae86771a6f758f9e11ac47728b0d91ed1a861738801cf7e8a382ca91`

| 行 | 内容 |
|---|---|
| `:5-8` | 头注释：难度「三档」→「四档」+ 说明取值来自 domain 常量 |
| `:27-40` | import：domain 常量 + `kKpSceneModes` + `RoomTapTile/clampBtnText` |
| `:68-77` | 新增 key：`stepMode(i)` / `stepModeValue(i,v)` / `requestMode` / `requestModeValue(v)`；**既有 `SceneSheetKeys` 全部保留** |
| `:87-126` | `_ModePicker`：四档分段按钮（复用 `kKpSceneModes`，不重复写文案），`RoomTapTile` 内部已 `clampBtnText` |
| `:143` | `_StepDraft.difficulty`（默认常规档） |
| `:190` | `_checkDifficulty`（「要求检定」的成功阈值档） |
| `:250-310` | 每个步骤行下挂一个 `_ModePicker`（原 `:87` 写死的 `'difficulty': 'REGULAR'` → `difficulty` 字段） |
| `:435-441` | 「要求检定」组加 `_ModePicker`（原 `:358` 写死的 `'difficulty': 'REGULAR'` → `_checkDifficulty`） |

### 1.4 team-lead 批准追加的 3 处（各 1 处，全部是「调用点归一」）

| 文件 | 改动前 sha256 | 改动后 sha256 |
|---|---|---|
| `lib/domain/room_rules_sheet.dart` | `7115a27184b4b01fd7e178197e6155f76a4982a21907e0848c0583b054066955` | `049735992591dd181795a821bc1a0e73a27de2e178b3deb584949b51f760dffb` |
| `lib/domain/room_rules_core.dart` | `1c84ee9e0ff2dc8507e70803a67621f0bcfffedf75d3cc2231106fb9b4e5a43c` | `20e33140b5cd74de61981c43472fd8917872979eae8ffbd6c24085cfa76383b8` |
| `lib/ui/room/widgets/gp_scene_check_pl.dart` | `2655fdf974abc5270e0268498ae5e39b517c94eea67c24e6ffc8de82743244c4` | `0723de832dc200da832d6a2f4c216bd8ab1e5a40bc337b95664f05e269860bf3` |

1. **`room_rules_sheet.dart` `_sceneStepPlan`**（`:489`）
   改前 `_normDifficulty(step['difficulty'])`
   改后 `_normDifficulty(jsStr(step['difficulty']).trim().toLowerCase())`
   ⇒ 场景检定步骤的 `required` 不再把大写 `HARD/EXTREME` 当常规。
2. **`room_rules_core.dart` `_check`**（`:253`）
   改前 `final difficulty = _normDifficulty(opts['difficulty']);`
   改后 `final difficulty = _normDifficulty(jsStr(opts['difficulty']).trim().toLowerCase());`
   ⇒ `rules.check()`（`diceDirect` / `rollCheckRequest` / `checkOpposed` / 场景自动判定 / 战斗检定全走这里）对大写难度生效。
3. **`gp_scene_check_pl.dart` `sceneDifficultyText`**（`:47`）
   由 `switch (jsStr(raw)) { 'HARD' / 'EXTREME' / default '常规' }`
   改为 `switch (raNormSceneDifficulty(raw)) { HARD→困难 / EXTREME→极难 / CRITICAL→大成功 / default 常规 }`
   ⇒ 四档与 `kRaDifficultyLevels` 一一对应；顺带让小写 `hard` 与 ` Hard ` 也能正确显示。
   ⚠️ 已 grep 全库：`lib/ui/**` 里按 `HARD/EXTREME` 二选一取文案的**只有这一处**（`grep -rn "'HARD'|'EXTREME'|'REGULAR'" lib/ui` 只命中此文件），无遗漏。
   该文件因不再用 `jsStr(` 一并去掉了 `show jsStr`（`jsStr` 预算只会变少，不会破 13 的上限）。

> 三处都**只动调用点**：`_normDifficulty` 本体（`room_rules_core.dart:64-65`）、`CocRules.DIFFICULTY` 的键、`room_rules_combat.dart` 的任何计算式 **一字未改**。

---

## 2. 大小写统一：前后对照表

统一口径：**模型 / 载荷里只有大写 `REGULAR|HARD|EXTREME|CRITICAL`**；规则层内部键仍是小写 `regular|hard|extreme`（`CocRules.DIFFICULTY` 不动）。
归一只允许经过 `raNormSceneDifficulty()`（模型侧）+ 规则层的**调用点** `.trim().toLowerCase()`（见 §1.4）。

| 位置（改前） | 改前字面量 | 改后 | 说明 |
|---|---|---|---|
| `gp_scene_check_kp.dart:80`（`kpQuickSceneStep`） | `'regular'` **小写** | `difficulty` 参数，调用方传 `kRaDifficulty*` | 小写是「困难/极难退化」的直接来源之一 |
| `sheet_scene.dart:87`（`_StepDraft.toPayload`） | `'REGULAR'` 写死 | `_StepDraft.difficulty`（四档） | 步骤再也发不出「非本步所选」的难度 |
| `sheet_scene.dart:358`（`check.request`） | `'REGULAR'` 写死 | `_checkDifficulty`（四档） | 同上 |
| `room_model_actions_room.dart:426`（`raSanitizeSceneSteps`） | `(diff=='HARD'\|\|diff=='EXTREME') ? diff : 'REGULAR'` | `raNormSceneDifficulty(diff)` | 白名单从 3 档扩 4 档，并**大小写归一**（`hard`→`HARD`） |
| `room_model_actions_room.dart:439`（`raDefaultSceneResolve`） | `>= 2` 写死 | `>= raDifficultyRequiredLevel(step['difficulty'])` | 兜底求值也不再「一切按常规」 |
| `room_rules_sheet.dart:489`（`_sceneStepPlan`） | `_normDifficulty(step['difficulty'])` → 大写退化成 `regular` | 先 `.trim().toLowerCase()` 再归一 | **§1.4-①**，规则层生效点 |
| `room_rules_core.dart:253`（`_check`） | `_normDifficulty(opts['difficulty'])` → 大写退化成 `regular` | 先 `.trim().toLowerCase()` 再归一 | **§1.4-②**，`rules.check` 生效点 |
| `gp_scene_check_pl.dart:47`（`sceneDifficultyText`） | 只认 `HARD`/`EXTREME`，`CRITICAL` 落「常规」 | 走 `raNormSceneDifficulty`，四档一一对应 | **§1.4-③**，玩家侧文案 |
| `room_rules.dart:77-81`（`DIFFICULTY`） | 小写键 `regular/hard/extreme` | **未改（只读）** | 规则层内部符号；加 `CRITICAL` 档会打红 `check.required` 一类 oracle |
| `room_rules_core.dart:64-65`（`_normDifficulty`） | `containsKey(d) ? d : 'regular'` | **未改（oracle 钉死）** | `room_rules.json` 逐字节钉死 `normDifficulty('HARD')=='regular'` |

### 2.1 全量输入对照（`room_rules.json` 受影响函数 × 10 种输入）

实测方式：临时 dart 脚本（`/tmp`，未入库）直调 `CocRules`；
「改前」= `_normDifficulty(raw)`（原实现，等价于未改的 `rules.normDifficulty`），「改后」= `_normDifficulty(raw.trim().toLowerCase())`。
`check` 用 `base=50, value=26`（固定骰值，不依赖 rng），`sceneStepResolve` 用 `level=2`。

| 输入 | 改前归一 | 改后归一 | `check.target` | `check.passed` | `stepResolve.required` | `stepResolve.success` | 结论 |
|---|---|---|---|---|---|---|---|
| `null` | `regular` | `regular` | 50 | true | 2 | true | **逐字节相同** |
| `''` | `regular` | `regular` | 50 | true | 2 | true | **逐字节相同** |
| `'REGULAR'` | `regular` | `regular` | 50 | true | 2 | true | **逐字节相同**（语义恰好不变） |
| `'regular'` | `regular` | `regular` | 50 | true | 2 | true | **逐字节相同** |
| `'hard'` | `hard` | `hard` | 25 | false | 3 | false | **逐字节相同** |
| `'extreme'` | `extreme` | `extreme` | 10 | false | 4 | false | **逐字节相同** |
| `'bogus'` | `regular` | `regular` | 50 | true | 2 | true | **逐字节相同** |
| `'HARD'` | `regular` ⚠️ | `hard` | **25**（原 50） | **false**（原 true） | **3**（原 2） | **false**（原 true） | **只改这一类的退化** |
| `'Hard'` | `regular` ⚠️ | `hard` | **25**（原 50） | **false**（原 true） | **3**（原 2） | **false**（原 true） | 同上 |
| `'EXTREME'` | `regular` ⚠️ | `extreme` | **10**（原 50） | **false**（原 true） | **4**（原 2） | **false**（原 true） | 同上 |
| `'CRITICAL'` | `regular` | `regular` | 50 | true | 2 | true | **规则层无此档**（`DIFFICULTY` 只有 3 档）；CRITICAL 的「只有 01」由 `raDifficultyPasses` 承担，见 §2.2 与 §8-D2 |

**夹具输入分布核对**（脚本扫 `test/fixtures/room_rules.json` 全文件）：
`check`（`regular`×40 / `hard`×6 / `extreme`×2）、`sceneStepPlan`（`hard`×2 / `regular`×4）、`sceneStepResolve`（`hard`×4 / `regular`×4）、
`dyingRoundCheck`/`resolveAttack`/`resolveSanCheck`/`temporaryInsanityCheck`（全 `regular`）、`targetOf`（含 `bogus`、走 `_targetOf`，**本次未改**）。
⇒ **没有任何夹具**把大写难度喂给这两个函数；`bogus` 经 `.toLowerCase()` 仍是 `bogus` → `regular`。
所以 §1.4-①② **对 oracle 是零差异改动**，只改真实链路的大写行为。

### 2.2 修复前后对照（波4 写端到端用例的靶子）

| 场景 | 修复前 | 修复后 | 能咬住它的断言 |
|---|---|---|---|
| 场景检定：`difficulty:'HARD'` 的步，KP 判 `level=2`（常规成功） | `required=2, success=true`（**困难步被当常规步判成功**） | `required=3, success=false` | `expect(rules.sceneStepResolve(step, 2)['success'], isFalse)` + `expect(...['required'], 3)` |
| 同上，KP 判 `level=3` | `success=true` | `success=true`（不变，但原因不同） | 配合上一条：2 不过 / 3 过 = 阈值真在 ÷2 |
| 场景检定：`difficulty:'EXTREME'`，`level=3` / `level=4` | 3 就过 | 3 不过 / 4 过 | `expect(resolve(step,3)['success'], isFalse)` + `expect(resolve(step,4)['success'], isTrue)` |
| `rules.check(base=50, difficulty:'HARD', value=26)` | `target=50, passed=true` | `target=25, passed=false` | `expect(res['target'], 25)` + `expect(res['passed'], isFalse)`（固定 `value`，免 rng） |
| 四档大成功：`raDifficultyPasses(1, 50, 'CRITICAL')` / `(2, ...)` | 未实现 | `true` / `false` | `expect(raDifficultyPasses(2, 50, 'CRITICAL'), isFalse)` ← **只有 01 过** |

> ⚠️ 第 5 行是本批唯一**不经过规则层**的档：`CocRules.DIFFICULTY` 没有 critical 档，`rules.check` 表达不了「只有 01」。
> 自动检定接线时必须用 `raDifficultyPasses(value, base, 'CRITICAL')`（或 `raDifficultyThreshold(...) + value==1`），
> **不要**给 `DIFFICULTY` 加第 4 档——那会改 `check.required` 的 oracle 输出。

### 归一后的实测（临时 dart 脚本直打 domain 纯函数，不是推断）

```
REGULAR  -> norm=REGULAR  thr(50)=50  required=2
HARD     -> norm=HARD     thr(50)=25  required=3
EXTREME  -> norm=EXTREME  thr(50)=10  required=4
CRITICAL -> norm=CRITICAL thr(50)=1   required=5
hard     -> norm=HARD     thr(50)=25          ← 小写归一
bogus    -> norm=REGULAR  thr(50)=50          ← 未知兜底（fixture #957 绿）
null     -> norm=REGULAR  thr(50)=50
thr(51,'HARD')=25   thr(9,'EXTREME')=1   thr(-5,'HARD')=0
raDefaultSceneResolve(HARD 步, level=2)  -> 走 onFailure（note=no）   ← 兜底不再按常规
raDefaultSceneResolve(REGULAR 步, level=2) -> 走 onSuccess（note=ok）

// 规则层：`_normDifficulty` 本体仍是老行为（oracle 要求），但两个调用点已归一
normDifficulty(HARD) = regular                      ← 未改，夹具要求
sceneStepResolve({difficulty:'HARD'}, level=2) → required=3, success=false   ← 已生效
check({base:50, difficulty:'HARD', value:26})  → target=25,  passed=false    ← 已生效
```

---

## 3. 四档阈值：实现位置与算式

**唯一实现**：`lib/domain/room_model_actions_room.dart:460` `raDifficultyThreshold(base, difficulty)`

| 档 | value（入库） | 阈值算式 | base=50 | base=0 | base=51 |
|---|---|---|---|---|---|
| 成功 | `REGULAR` | `base` | 50 | 0 | 51 |
| 困难成功 | `HARD` | `base ~/ 2`（向下取整） | 25 | 0 | 25 |
| 极难成功 | `EXTREME` | `base ~/ 5`（向下取整） | 10 | 0 | 10 |
| 大成功 | `CRITICAL` | **恒 1**（只有 01） | 1 | 1 | 1 |

判定：`raDifficultyPasses(value, base, difficulty)` = `value ∈ [1,100] && value <= raDifficultyThreshold(...)`。
- `CRITICAL` 用 `value == 1` 的语义落成「阈值恒 1 + 值域下限 1」，**不会把 0 / 负数判成功**。
- 负数 base 夹 0（对齐 `room-rules.js:121 Math.max(0, num(base))`）。
- 与老 APP `thresholds(base)`（`room-rules.js:120-123`）三档**逐项一致**，第四档是 Q1 新增特判。

配套：`raDifficultyRequiredLevel()` 2/3/4/5 与 `CocRules.LEVEL` 的 `REGULAR/HARD/EXTREME/CRITICAL` 数值一致，供「规则服务缺失」的兜底求值用。

> ⚠️ 我没有另写一份 `levelOf`：`CocRules._levelOf` 已经实现了 ≤extreme→4 / ≤hard→3 / ≤regular→2 的等级判定，
> 再抄一份就是「多个文件各写一份」。本文件只补「四档 → 阈值 / 下限」这一层。

---

## 4. UI 四步模式（对齐用户口径 + 老 APP）

| 用户步骤 | 落点 | 说明 |
|---|---|---|
| ① 选全体还是某个玩家 | `GpSceneCheckKeys.modeTarget` → `UnitPickerField(allowAll: true)` | 复用 `unit_picker.dart` 的 `showUnitPicker`，`*=全体` 保留；`unit_picker.dart` **零改动** |
| ② 输入要检定的技能 | `GpSceneCheckKeys.modeSkill` → 纯 `TextField` | 老 APP `room-panels.js:1880` 也是纯文本框（无下拉、无近义词），4 档别名归一由 `room_rules_sheet._skillValue` 在权威端做 |
| ③ 选成功所需等级 | `GpSceneCheckKeys.mode(value)` × 4 | `RoomTapTile` 108×48，选中项带 `Icons.check`；值取 domain 常量 |
| ④ 点推送 | `GpSceneCheckKeys.quickPush`（文案「推送检定」） | 发 `scene.check.push`，steps 恰好带 `id/title/skill/targetSeat/difficulty` |

- 既有 6 档**裁定结果**按钮（`level(5/4/3/2/0/-1)`）原样保留：那是 KP 手动改判结果的通道，不是「检定方式」。
- 弹层侧同样补齐：多步编辑器**每步**一个四档选择（`stepMode(i)`），「要求检定」一个（`requestMode`）。
- `textScaler` 1.3/1.5/2.0：四档 tile 走 `RoomTapTile`（内部 `clampBtnText` 钳到 1.0）；① 目标那一颗 `RoomTap` 单独 `clampBtnText` 包住（只钳该子树，不动面板其它文字）。不用 `ClipRect` 硬裁、不抬到 Theme。

---

## 5. §自动检定评估（要 op 吗？能不能复用？）

### 5.1 现状事实（已读源码核对）
1. `check.request`（`room_model_actions_combat.dart:checkRequest`）→ 给目标发 REQUEST 卡；**玩家点「同意」时由权威端代掷**：
   `room_model_host_intent.dart` 的 `consent` 分支 `if (req['op'] == 'check.request')` → `rollCheckRequest(seat, req)`。
   `rollCheckRequest` 注释逐字：「按权威端存的技能/难度替该玩家掷一次 D100」——**这就是现成的「系统自动检定」**，玩家自己不掷骰。
2. `scene.check.push` → `sceneCheckPush` → `autoAdvanceSceneCheck`：**只对「已撕卡 / 疯狂发作中」的目标**自动推进；
   普通目标的 `sceneCheckStep` 在 `p['level'] == null` 时走 `level = 2`（写死「常规成功」），**没有真掷骰**。
   疯狂分支虽然有 `rules.check` 自动判定，但 `autoBase` 查不到时回落 50，且只覆盖 bout 成员。
3. `dice.direct`（`dispatchCombatAction`）是权威掷骰，但它是**一条骰子记录**，不回写 `state.sceneCheck.results`，不能当「推送即结算」。

### 5.2 结论
| 目标 | 能否复用 | 说明 |
|---|---|---|
| 「推给玩家 → 系统代掷」（玩家只点同意） | **能** | 改发 `check.request` 即可；`difficulty` 已在载荷里，玩家端「同意」→ `rollCheckRequest` 权威掷。这是老 APP `room-panels.js:1901` 的同款载荷 |
| 「推给玩家 → 零点击直接出结果」（用户字面口径） | **不能** | 需要新增「推送即结算」语义：要么改 `sceneCheckStep` 的 `p['level']==null` 分支（普通目标改成权威 `rules.check`），要么新增 op |
| 「大成功档（CRITICAL）自动判定」 | **不能** | `CocRules.DIFFICULTY` 只有 3 档，`required` 最大 4，没有 `required=5`；`rules.check` 表达不了「只有 01」。要落只能靠 `raDifficultyPasses(value==1)` 这类特判 |

### 5.3 为什么本批**不新增 op**（按施工单 §4.3 要求停下报告）
- 新增 action 会打红 `test/room_ui_permission_test.dart:342` 的 `kRoomPolicy.length == 61`（§0-4 红线）。
- 改 `scene.check.push` 的既有行为（push 后自动结算）属于「改 oracle 期望」，`fixtures/room_actions.json:207-209/9611-9658` 是逐字节契约。
- 本批 UI 因此仍走 `scene.check.push`（多步引擎 + KP 裁定），并把所选难度写进 `step.difficulty`；
  「推送即结算」按上面两条路径任一实现都需要 team-lead 拍板（见 §8-D2）。

---

## 6. 给波 4 的验收用例口径（含反向证伪）

### 6.1 纯函数层（必测，咬得住）
```dart
// 阈值：四档 = 50 / 25 / 10 / 1
expect(raDifficultyThreshold(50, 'REGULAR'), 50);
expect(raDifficultyThreshold(50, 'HARD'), 25);      // ÷2 向下取整
expect(raDifficultyThreshold(51, 'HARD'), 25);      // 51÷2=25.5 → 25
expect(raDifficultyThreshold(50, 'EXTREME'), 10);   // ÷5
expect(raDifficultyThreshold(9, 'EXTREME'), 1);
expect(raDifficultyThreshold(50, 'CRITICAL'), 1);
expect(raDifficultyThreshold(0, 'REGULAR'), 0);
expect(raDifficultyThreshold(-5, 'HARD'), 0);        // base 负 → 夹 0

// 判定：边界值两侧都要断言
expect(raDifficultyPasses(25, 50, 'HARD'), isTrue);
expect(raDifficultyPasses(26, 50, 'HARD'), isFalse);   // ← 差 1 就失败，证明真按 ÷2
expect(raDifficultyPasses(10, 50, 'EXTREME'), isTrue);
expect(raDifficultyPasses(11, 50, 'EXTREME'), isFalse);
expect(raDifficultyPasses(1, 50, 'CRITICAL'), isTrue);
expect(raDifficultyPasses(2, 50, 'CRITICAL'), isFalse); // ← 只有 01
expect(raDifficultyPasses(0, 50, 'CRITICAL'), isFalse); // 非法值不算成功

// 大小写归一
expect(raNormSceneDifficulty('hard'), 'HARD');
expect(raNormSceneDifficulty(' Hard '), 'HARD');
expect(raNormSceneDifficulty('bogus'), 'REGULAR');
expect(raNormSceneDifficulty(null), 'REGULAR');
```

### 6.2 「不是静默退化」的**正/反向双证**（核心）
```dart
// 正向：同一 base 下 HARD/EXTREME 的阈值必须与 REGULAR 不同
expect(raDifficultyThreshold(50, 'HARD'), isNot(raDifficultyThreshold(50, 'REGULAR')));
expect(raDifficultyThreshold(50, 'EXTREME'), isNot(raDifficultyThreshold(50, 'REGULAR')));

// 反向证伪（改坏必红）：
//   把 raDifficultyThreshold 的 HARD 分支改成 return n（等价退化）→ 上面 isNot 必红；
//   把 CRITICAL 分支改成 return n → passes(2,50,'CRITICAL') 必红。
```

### 6.3 模型层（难度入库）
```dart
final steps = raSanitizeSceneSteps([
  {'difficulty': 'hard'}, {'difficulty': 'CRITICAL'}, {'difficulty': 'bogus'},
]);
expect(steps[0]['difficulty'], 'HARD');       // 小写归一
expect(steps[1]['difficulty'], 'CRITICAL');   // 第四档透传
expect(steps[2]['difficulty'], 'REGULAR');    // 未知兜底
```
反向证伪：把 `raNormSceneDifficulty` 改成「原样返回」→ 第 0 条必红（`hard` 出来还是 `hard`）。

### 6.4 端到端（规则层真生效 —— §1.4-①② 已落地，这条现在应是绿）
`scene.check.push` 推一条 `difficulty: 'HARD'` 的步骤，再让 KP 用 `level=2`（常规成功）裁定：
```dart
final r = CocRules();
final step = state.sceneCheck.steps[0];       // difficulty == 'HARD'
expect(r.sceneStepResolve(step, 2)['success'], isFalse);  // 困难步不能被「常规成功」判过
expect(r.sceneStepResolve(step, 3)['success'], isTrue);   // 困难成功才过
expect(r.sceneStepResolve(step, 2)['required'], 3);
```
**这就是「不是静默退化」的靶子**：修复前实测 `required=2, success=true`（困难步被当常规步判过），
修复后 `required=3, success=false`（已用临时脚本实测，见 §2.2）。
反向证伪：把 `_sceneStepPlan` 那行的 `.trim().toLowerCase()` 删掉 → 本条立刻变回 `success=true` 而红。
同理 `EXTREME` 用 `level=3 → false / level=4 → true`。
`CRITICAL` **不能**用 `sceneStepResolve` 验（规则层无第 4 档，`required` 最大 4）：
它的「只有 01」只能用 `raDifficultyPasses(1, base, 'CRITICAL') == true && raDifficultyPasses(2, ...) == false` 咬住。

`check.request` 路径（玩家同意后权威代掷）：
```dart
final res = r.check({'base': 50, 'difficulty': 'HARD', 'value': 26});  // 固定骰值，免 rng
expect(res['target'], 25);
expect(res['passed'], isFalse);   // 26 > 25
```
现在实测（修复后）`target=25, passed=false` ⇒ 该用例同样能证明「不是退化」。

### 6.5 UI 层
```dart
// 四档按钮存在且默认选中常规档；点「困难成功」后推送载荷 difficulty == 'HARD'
expect(find.byKey(GpSceneCheckKeys.mode('REGULAR')), findsOneWidget);
await tap(GpSceneCheckKeys.mode('HARD'));
await tap(GpSceneCheckKeys.quickPush);
final p = asMap(f.lastSent(action: 'scene.check.push')!['p']);
expect((p['steps']! as List).length, 1);
expect((p['steps']! as List).first['difficulty'], 'HARD');
// 目标选择
expect(find.byWidgetPredicate((w) => w is UnitPickerField && w.key == GpSceneCheckKeys.modeTarget), findsOneWidget);
expect(widget<UnitPickerField>(...).allowAll, isTrue);
// 技能为空不推送
await enterText(GpSceneCheckKeys.modeSkill, '');
await tap(GpSceneCheckKeys.quickPush);
expect(f.lastSent(action: 'scene.check.push'), isNull);
```
反向证伪：把 `kpQuickSceneStep` 的 `difficulty` 改回 `'regular'` → `'HARD'` 断言必红。

---

## 7. 预计转红的既有测试 + 建议口径

| 测试 | 现状断言 | 为什么会红 | 建议口径（更强或等价） |
|---|---|---|---|
| `test/room_ui_kp_test.dart:795-805`「快速推送走 scene.check.push 且带一步」 | 点 `quickPush` → `scene.check.push`，steps 长度 1 | 行为升级：现在带 ①②③ 选值；技能为空时**不推送**（默认 '侦查'，所以仍会推） | 保留原断言 + 新增 `steps[0]['difficulty'] == 'REGULAR'`（默认档）与「选困难成功 → 'HARD'」 |
| `test/p16_button_unify_test.dart` P16-06「gpScene 8 个按钮全 108×48，恰好 2 列」 | 8 个 key 的尺寸集合 == {108×48}、lefts == 2 | **不该红**：8 格结构与位置未动，新增的四档 tile 是**另一个 Wrap**，不在 key 列表内 | 绿则不动；若因新增行数导致 down 值变化，只放宽「行数」类断言，**尺寸集合与 2 列断言不许放宽** |
| 同上「大字体不溢出（1.3/1.5/2.0）」 | 全页无 FlutterError（白名单只有 `room_panel_kit.dart:291`） | 新块在 2.0 下可能多出换行（不会溢出，因为我钳了按钮子树） | 若红：只允许把新增溢出点……**不允许白名单化**，应回退到钳制该控件子树 |
| `test/p10_t6_layout_test.dart:552` | `level(5)` 按钮右/左边界落在 `gpScene` 格内 | 不应红（水平位置不变；格子内是竖向滚动） | 不动 |
| `test/qa_p5_priv_probe_test.dart:225-240` | `level(lv)` 的 enabled、旁观态 `findsNothing` | 不应红（6 档 enabled 表达式未改） | 不动 |
| `test/p16_wave1_sheets_test.dart:320-352`「场景弹层 4 处座位全是 UnitPickerField」 | 4 个 key 的 `UnitPickerField` + allowAll | 不应红（座位控件未动，只是外面多包了 `Column`） | 不动；可加「每步有四档选择 `stepMode(0)`」新断言 |
| `test/room_ui_kp_test.dart:1003-1006 / 1020-1040`（`SceneSheet.addStep`） | 点「加一步」步骤数 +1 | 不应红 | 不动 |
| 任何断言 `difficulty: 'REGULAR'` 的用例 | — | UI 默认仍是 `REGULAR`，只有用户改选时才变 | 若有用例断言「步骤载荷恒 REGULAR」，改成「默认 REGULAR + 可选 HARD/EXTREME/CRITICAL」 |
| `test/room_rules_oracle_test.dart` + `fixtures/room_rules.json` | `normDifficulty('HARD')='regular'` 等 | **不应红**：`_normDifficulty` 本体与 `DIFFICULTY` 键未动；两个调用点的夹具输入全是小写/`bogus`（§2.1 已逐值实测） | 若真红，按 §8-D1 的回滚说明逐行还原 3 处 |
| `test/room_ui_kp_test.dart` 及任何断言玩家侧难度文案的用例 | `sceneDifficultyText` 输出 | 玩家侧 `CRITICAL` 从「常规」变「大成功」，` hard ` 等小写也能认出 | 现状无用例断言该函数（已 grep）；新增断言应覆盖四档 |
| `test/room_ui_lobby_test.dart` 的「jsStr 预算」 | ≤13 处 | 我把 `gp_scene_check_pl.dart` 的 `jsStr(` 去掉了 ⇒ 总数**减少 1**，不会突破上限 | 不动（预算是上限判定） |

---

## 8. 决策项

### D1（已落地 —— team-lead 2026-11-14 批准）
原来卡在这里：「`HARD` 真按 ÷2」要求在规则层生效，但 `_normDifficulty('HARD')=='regular'` 被 `fixtures/room_rules.json` 逐字节钉死，
唯一不动 oracle 的修法是在**调用方**先 `.trim().toLowerCase()`。已按批准改了两处（详见 §1.4-①②，逐值等价证明见 §2.1）。

**回滚说明（若波4 全量发现 oracle 红，按此逐行还原，3 行即可）**

| # | 文件 | 把这一行改回 | 定位锚点 |
|---|---|---|---|
| 1 | `lib/domain/room_rules_sheet.dart` | `    'difficulty': _normDifficulty(jsStr(step['difficulty']).trim().toLowerCase()),` → `    'difficulty': _normDifficulty(step['difficulty']),` | 函数 `_sceneStepPlan`，`'skill': ...` 的下一行 |
| 2 | `lib/domain/room_rules_core.dart` | `  final difficulty = _normDifficulty(jsStr(opts['difficulty']).trim().toLowerCase());` → `  final difficulty = _normDifficulty(opts['difficulty']);` | 函数 `_check`，`final kind = ...` 的下一行 |
| 3 | `lib/ui/room/widgets/gp_scene_check_pl.dart` | 函数体整体还原为 `switch (jsStr(raw)) { case 'HARD': return '困难'; case 'EXTREME': return '极难'; default: return '常规'; }`，并把 `import '../../../domain/js_compat.dart' show asMap;` 改回 `show asMap, jsStr;`，删掉新增的 4 个 domain 常量 import | 函数 `sceneDifficultyText` |

回滚后 sha256 应分别恢复成 §1.4 表里的「改动前」值（`7115a27…` / `1c84ee9…` / `2655fdf…`），可用一次
`sha256sum <三个文件>` 与表逐字节比对确认。
若只回滚 ①②，则「HARD 真按 ÷2」重新退化为静默常规，§6.4/§6.2 的端到端断言会转红——那正是这条修复的靶子。

### D2（产品口径，待拍）「推送后由系统自动检定」要不要真的零点击？
- 方案 A（低成本，无新 op）：④ 改发 `check.request`（老 APP `room-panels.js:1901` 同款）。玩家收到「KP 要求检定」卡 → 点同意 → `rollCheckRequest` **权威代掷**，玩家自己不掷。代价：`room_ui_kp_test:799` 的 `scene.check.push` 断言要改口径（产品行为变了，允许）。**D1 落地后，这条路线的 HARD/EXTREME 已真正生效**；CRITICAL 仍需用 `raDifficultyPasses` 特判。
- 方案 B（零点击）：改 `sceneCheckStep` 的普通目标分支（`level = 2` → 权威 `rules.check`），或新增 op。**会打红 `kRoomPolicy.length == 61`**，本批不做。
- 本批已按「A 的载荷形态、B 的 op」折中：UI 仍发 `scene.check.push`，难度已入库，**自动判定留给 D2 拍板后的下一批**。

### D3（已落地 —— 同上批准）
`gp_scene_check_pl.dart#sceneDifficultyText` 已补 `CRITICAL` → 「大成功」，并改走 `raNormSceneDifficulty` 做大小写归一；
已 grep 全 `lib/ui`：按 `HARD/EXTREME` 二选一取难度文案的只此一处，无遗漏。

---

## 9. 声明

- **未经 `flutter test` 验证**（并发期禁跑，只做静态自检）：只跑了 `dart analyze lib` 与 `dart analyze test`（均 `No issues found`）。
  等价性由 ① 静态论证（夹具输入分布全量扫描，见 §2.1）+ ② 临时 `dart` 脚本直调 `CocRules` 的逐值实测 支撑，
  **最终由波4 全量 `flutter test --no-pub` 确认**。
- **未改任何既有测试**，**未新建测试**；波 4 请按 §6 的口径新增。
- **未碰** `lib/domain/room_rules_combat.dart`（计算式一字未动）、`lib/domain/room_rules.dart`（`DIFFICULTY`/`LEVEL` 常量未动）、`lib/ui/room/widgets/unit_picker.dart`、`lib/domain/room_types.dart`（`kRoomPolicy` 未动）、`test/fixtures/**`、`oracle_*`、`pubspec.yaml`、`lib/app_version.dart`、`pubspec.lock`。
- 未改 `SceneSheetKeys` 任何既有常量（只新增）；未改 `GpSceneCheckKeys` 任何既有常量（只新增）；`GpSceneCheckKp` 构造签名不变。
- `lib/ui/room/**` 两个 UI 文件：**零 emoji**（只匹配 U+1F300–1FAFF）、**零 `jsStr(`**（已用脚本核）。
- `dart analyze lib`（全库）：**No issues found**。
