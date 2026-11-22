# P10 · 教育进步检定（EDU）+ 年龄扣 DEX 对闪避的影响 —— 工程师报告

范围：CoC 7e 建卡期「教育进步检定」，以及用户怀疑的「扣敏捷不影响闪避」审查。
红线遵守：`lib/domain/**` 无 `package:flutter` / `dart:io` / `dart:ui`（`test/domain_purity_test.dart` 绿）；
未出包、未 `flutter clean`、未加依赖；未触碰 `room/**`、`ai_create_page.dart`、`random_create_page.dart`、
`roster_page.dart`、`home_page.dart`、`art.dart`、`theme.dart`、`rule_pick_page.dart`、`step_basics.dart`。

---

## 一、先查「项目里已有什么」（没有重写一套）

| 已有资产 | 位置 | 我怎么处理 |
|---|---|---|
| `eduProgress = {base, done, log, bonus}` 字段 | `character.dart:148-156` | **沿用**，不新增键（只多写一个 `d10` 进 log 行，供文案判断封顶） |
| `eduImproveCheck(edu, [rng])`（自带掷骰） | `rules_coc7.dart:404` | **改成调用新纯函数**，随机数消耗顺序一字未动（oracle 9 例仍绿） |
| 年龄修正只作用于「生效属性 eff」 | `rules_coc7.dart:219-375 #ageAdjust` | **沿用**：EDU 增益与年龄修正走同一条路（只进生效值） |
| 旧检定作废守卫（原始 EDU 变了就清 log） | `engine.dart:243 #dropStaleEduChecks` | **沿用**，写入时补记 `baseEdu`，避免被误判过期 |
| 概要页「原始 → 生效」并排显示 | `steps/step_summary.dart:264 _AttrChip` | 无需改动，EDU 增益自动以 `55 → 62` 形式呈现 |
| 属性页「教育进步检定」的**按钮** | 不存在（全 `lib/ui` grep `eduProgress` 只有 `summary_card` 的随机卡摘要） | **本次新增**（UI 接线） |

结论：规则计算本来就有（且被 oracle 夹具盯住），**缺的是建卡向导的入口与提示** —— 正是用户说的「好像都没有」。

## 二、规则落点

### 2.1 纯函数（新增 `lib/domain/edu_check.dart`）

```dart
const int eduCap = 99;
class EduCheckResult { before, roll, success, gain, after }
EduCheckResult eduCheck(int edu, int d100, int d10);
```

- 判定：**`d100 > edu`（严格大于）** 才进步；等于不算（规则书原文「大于」）。
- 进步：`after = min(99, edu + d10)`，`gain = after - edu`（因此封顶时 `gain < d10`，例如 95 + 10 → gain 4）。
- 失败：`after == edu`、`gain == 0`，`d10` 完全不参与。
- **入参 `edu` 不夹取**：JS 原码（`rules-coc7.js#eduImproveCheck`）对脏数据 EDU=100 失败时原样返回 100，
  oracle 夹具 `eduImproveCheck#712` 逐字比对这个行为。封顶只发生在成功之后。
  （第一版我在入口夹了 99，直接被 `oracle_rules_test` 判红 —— 记在这里，别再"优化"回去。）
- 两个骰值都是**入参**，随机数在调用方生成 → 纯函数可逐条钉边界，且天然幂等。

`rules_coc7.dart#eduImproveCheck` 现在内部调它，随机数消耗顺序保持「先 1D100，进步了才 1D10」：

```dart
final r = roll(1, 100, rng);
final d10 = r > cur ? roll(1, 10, rng) : 0;   // 失败不掷 1D10（randUsed 也是契约）
final res = eduCheck(cur, r, d10);
```

### 2.2 写卡路径（`chargen_logic.dart`，UI 层纯逻辑，无 BuildContext）

| 函数 | 职责 |
|---|---|
| `ensureEduProgress(card)` | 规整 `eduProgress`（幂等，与 `normalize.dart` 口径一致） |
| `eduChecked(card)` | `eduProgress.log` 非空 = 已检定（**数据判定**，不靠 widget state，退出重进也不丢） |
| `eduForCheck(card)` | 检定用的「当前 EDU」= `effectiveAttrs(card)['edu']`，封顶 99 |
| `runEduCheck(card, {rng})` | 掷骰 → 写 log/bonus/done/baseEdu → `recalc` + `syncSkills`；已检定返回 `null` |
| `eduCheckText(row)` | 结果文案（界面与测试共用一份，避免措辞漂移） |

**为什么增益落在 `eduProgress.bonus` 而不是直接改 `attributes.edu`**（这是本次唯一的"设计判断"，依据如下）：

1. `character.dart:148` 的字段注释、`rules_coc7.dart:342` 与 `engine.dart:27-40` 都明确写了
   「**原始 EDU 不动，增益只作用于生效值**」，理由是不能污染购点上限校验（460 / 540 只认玩家买来的点数）；
   直接改原始值，一张合法卡会突然被判「超出上限 N 点」。
2. 年龄修正（扣 STR/CON/DEX/APP）走的就是这条「只影响 eff」的路。EDU 增益跟它同源，
   这样 `ageAdjust()` 里一处 `eff['edu'] = min(99, eff.edu + eduBonus)` 就同时管住了
   母语基础值（`dyn=edu`）、职业技能点、角色卡与概要显示 —— **全都是真的生效了**，
   只是"原始值"这一列保持玩家输入。
3. 界面已经把这件事显示清楚了：属性页写「原始教育 55 → 生效 62（检定 +7）」，
   概要页 `_AttrChip` 并排显示 `55 → 62`（带删除线的原始值）。
4. `dropStaleEduChecks` 会把「原始 EDU 改过」的旧检定作废 —— 这条设计只有在
   「增益不进原始值」时才成立（否则原始 EDU 永远等于带增益的值，守卫生效不了）。

所以：`runEduCheck` **确实改了 `draft`**（`draft.raw['eduProgress']` 是卡上的真值，随卡一起落库），
并走既有的 `recalc()` 属性写入路径，而不是改 UI state。

### 2.3 UI（第 2 步属性页最下方，`step_attrs.dart#_eduBlock`）

- 标题「教育进步检定」+ 一行说明（掷 1D100，大于当前教育才 +1D10，上限 99，只做一次）。
- `Key('edu_check_raw')` 原始教育；`Key('edu_check_edu')` 生效教育（有增益时显示 `→ 生效 62（检定 +7）`）。
- `Key('edu_check_roll')` 按钮：未检定 → 「🎲 进行检定」；已检定 → 文案「✓ 已完成（不能重掷）」且 `onPressed == null`。
- `Key('edu_check_result')` 结果文案：`掷出 63 > 教育 55 → 教育 +7，现为 62` /
  封顶时 `掷出 100 > 教育 95 → 教育 +4（上限 99），现为 99` /
  失败时 `掷出 12 ≤ 教育 55 → 没有进步，教育保持 55`；未检定 → 「尚未检定 —— 不做也照样能保存，只是教育保持原值。」

### 2.4 未检定提示（`create_flow_page.dart`，**不阻止**）

- 触发点：① 从**属性页**点「下一步」；② 点「保存角色卡」（含从概要页自由跳过来保存）。
  - 只在离开 `attrs` 步时提示 —— 否则「基本资料 → 属性」也会弹，玩家还没见到按钮就被念一句。
- **不做硬拦截**（用户原话是「要提示玩家」）：`_goNext` 里校验通过后弹提示，然后**照常前进**；
  保存路径同理，提示完继续保存。玩家不会被卡在第 2 步出不去。
- 提示内容 `Key('edu_check_skip_hint')` + 两个动作：
  - 「现在去检定」`Key('edu_check_go_roll')` → 跳回属性页（`_jumpTo('attrs')`）；
  - 「仍要继续」`Key('edu_check_continue')` → 关掉提示，停/留在当前页。
- 只弹一次：`_eduHintShown`（页面 State = 一次建卡会话）。已检定 / 已提示过 / 已明确"仍要继续" → 不再弹。
- 保存路径的文案改成「保存后仍可回第 2 步补做，再保存一次即可」，并且不给「现在去检定」按钮
  （此刻马上回首页，跳过去也无处可跳）。

## 三、审查「扣敏捷是否影响闪避」——结论：**已经是正确的，不是 bug**

用户怀疑得有理，但现状是通的。逐条核：

| # | 问题 | 结论 | 依据 |
|---|---|---|---|
| 1 | 年龄修正在哪应用 | `rules_coc7.dart#ageAdjust`（`engine.recalc` 第 0 步调用） | 中老年把 `physLoss` **逐点轮转**摊到 `str/con/dex`（单项不低于 `physFloor=15`），APP 单独扣 |
| 2 | 修正后的 DEX 是否回写到 `attrs.dex` | **不回写**，只算 `eff` 与 `raw['effAttributes']` | 有意设计：回写会污染掷骰结果、购点上限校验、来回改年龄时的叠加扣减 |
| 3 | `skillmodel.dart#baseValue` 读哪个 DEX | **生效值** | `baseValue` 首行 `final a = effectiveAttrs(character);`，`dyn=dex2` → `(a['dex']/2).floor()`；`dodge` 还有兜底分支同算法 |
| 4 | 闪避实例 `base` recalc 时重算吗 | **会** | `engine.recalc` 第 2 步对每个非自定义技能重算 `baseValue` 并 `recompute`；`syncSkills` 亦同 |
| 5 | 派生值里的 `dodgeBase` | 用生效 DEX | `derived()` 第 458 行取 `adj['eff']`，`'dodgeBase': (dex/2).floor()` |

**判断依据（产品意图是"生效值"）**：
- `step_attrs.dart` 的说明就是「原始值不因年龄改动；年龄扣减只作用于『生效值』」，
  `rules_coc7.dart:219-227` 写明了取舍理由（不可逆污染）。
- 所以**闪避必须读生效值**；它读了 (`effectiveAttrs`)，链路闭合。
- 若哪天有人把 `baseValue` 改回读 `character.attributes['dex']`，年龄调整就"等于没生效" ——
  本次新增的测试正是钉这个。

实测（`test/p10_edu_check_test.dart` D 组）：25 岁 / 60 岁、八项属性各 60 →
60 岁 `str/con/dex` 合计 −20 轮转摊成 `7/7/6` → `eff.dex = 54` → 闪避 `base` 与 `total` 都从 `30` 降到 `27`；
`derivedStats.dodgeBase` 同步 27。奇数 DEX 也按向下取整跟（49→24、43→21）。

## 四、测试账目（新增 `test/p10_edu_check_test.dart`，16 例，全绿）

| 组 | 用例 | 钉住什么 |
|---|---|---|
| A（7） | `d100 == edu` 不进步 | **严格大于**（改成 `>=` 立刻红） |
| | `d100 == edu + 1` → +1D10 | 边界另一侧 |
| | 95 + d10=10 → 99 / gain=4 | 封顶，且 gain 不吃封顶外的点数 |
| | 99 + d100=100 → 进步但 gain=0 | 极值不越界 |
| | 失败时 d10 不参与 | 传 10 也不涨 |
| | 同参调用 100 次结果一致 | 幂等（domain 无状态） |
| | 文案三态（成功/封顶/失败）都带掷出值 | 界面文案与数据一致 |
| B（2） | 成功一次后：生效 EDU +gain、原始不动、再掷返回 null | "只能做一次" + 增益落点 |
| | 掷骰顺序：d100 与同序列逐字一致；成功消耗 2 个随机数、失败 1 个 | 与 `rules#eduImproveCheck`/JS 的 randUsed 契约一致 |
| B-UI（2） | 点检定 → 生效 EDU 涨、按钮禁、文案含掷出点数 | 用户可见行为 |
| | 掷出 ≤ EDU → 文案"没有进步"、按钮同样禁用 | 失败也算"做过了"（不能重掷刷成功） |
| C（2） | 未检定点下一步 → 提示出现**且已前进**；「仍要继续」后不再重复弹 | 提示而非硬拦 + 只弹一次 |
| | 做了检定再点下一步 → 完全不弹 | 提示条件正确 |
| D（3） | 60 岁扣 6 DEX → 闪避 30→27（含 `derivedStats.dodgeBase`） | 用户怀疑点 |
| | 奇数 DEX 取整（49→24、43→21） | 向下取整 |
| | 改 age 后重算，闪避立刻跟上 | 无幽灵缓存 |

### 跑过的命令与结果

```
flutter analyze                       → No issues found!
flutter test                          → 1713 通过 / 4 失败（4 个全部与本次改动无关，见 §7）
flutter test test/p10_edu_check_test.dart test/oracle_rules_test.dart
                                      → 36 通过 / 0 失败
flutter test test/create_extra_steps_test.dart
                                      → 10 通过 / 0 失败
flutter test test/create_flow_widget_test.dart test/p9_combat_skill_test.dart \
              test/oracle_skillmodel_test.dart test/qa_probe_test.dart
                                      → 除 create_flow 的 3 个首页断言（见 §7）外全绿
flutter test test/p7_fate_test.dart test/p8_wizard_nav_test.dart test/wizard_fix_jump_test.dart \
              test/step_background_test.dart test/p7_attr_cap_test.dart \
              test/chargen_logic_test.dart test/domain_purity_test.dart test/wizard_steps_test.dart
                                      → 78 通过 / 0 失败
```

## 五、自证伪（把实现改坏，确认测试会红，再还原）

1. **`eduCheck` 的 `>` 改成 `>=`**
   - 结果：`A·d100 == 当前教育 → 不进步` 红（`Expected: false, Actual: <true>`），
     `A·失败时 d10 完全不参与` 红（`Expected: 70, Actual: 80`）。→ 边界真的被钉住。
   - 还原后 16 例全绿。
2. **`skillmodel.dart#baseValue` 的 `dyn=='dex2'` 分支改成 `return 0`**（等价于"闪避不读 DEX"）
   - 结果：D 组 3 例全红（`Expected: <30> / <24>, Actual: <0>`）。→ 闪避用例真的依赖 DEX/2。
   - 注意：此时 `derivedStats.dodgeBase` 仍是 30/27（`derived()` 自己算），
     说明测试确实分别覆盖了"技能实例 base"和"派生摘要"两条路，不是重复断言同一条。
   - 还原后全绿（并复跑 `oracle_skillmodel_test` 20 例确认没伤到技能基础值契约）。

## 六、老代码 / 老测试改动

| 文件 | 改动 | 风险 |
|---|---|---|
| `lib/domain/rules_coc7.dart#eduImproveCheck` | 内部改为调用 `eduCheck`，随机数消耗顺序不变 | 由 `oracle_rules_test` 9 例逐字比对兜住（第一次因入口夹 99 判红，已修） |
| `lib/domain/skillmodel.dart` | **零改动**（只用于变异验证，已还原） | — |
| 其他人的测试文件 | **零改动**（提示做成"不拦路"，所以既有向导流程测试不用改点击次数） | — |

## 七、已知失败（与本次改动无关）

全量 `flutter test` 的 4 个失败全部落在**首页 / 英灵殿横幅**的文案与 Key 上，属于同期另一位工程师
正在改的 `lib/ui/home_page.dart`（本次明确不许我碰）：

- `create_flow_widget_test` ①④⑤：断言首页空态「还没有英雄长眠于此」/「英灵殿」——
  该文案已随首页改版移进 `roster_page.dart:154`。
- `p9_rule_pick_test`「首页角色档案入口图 两张竖排 2:1 图、Key 齐全」——`home_page.dart` 的 `_RosterBanner` 正在改。

判断依据：这 4 例的断言位置都在 home 页（`test/create_flow_widget_test.dart:78`、
`test/qa_probe_test.dart:322` 附近），与 `edu_check` / `step_attrs` / `create_flow_page` 的逻辑无耦合；
且 `create_extra_steps_test`（同样走完 9 步 + 落库读回）10 例全绿，说明向导链路本身没被我的改动弄坏。

## 八、文件清单

**新增**
- `lib/domain/edu_check.dart`（纯函数 + `EduCheckResult`）
- `test/p10_edu_check_test.dart`（16 例）
- `_p10_edu_report.md`（本文件）

**修改**
- `lib/domain/rules_coc7.dart`（`eduImproveCheck` 委托给 `eduCheck`；+1 行 import）
- `lib/ui/create/chargen_logic.dart`（`ensureEduProgress` / `eduChecked` / `eduForCheck` / `runEduCheck` / `eduCheckText`）
- `lib/ui/create/steps/step_attrs.dart`（`_eduBlock()` + `_rollEdu()`，挂在属性页最下方）
- `lib/ui/create/create_flow_page.dart`（`_maybeHintEduCheck()` + `_eduHintShown`，接在"下一步/保存"上）
