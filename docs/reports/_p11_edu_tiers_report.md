# P11 · 教育进步检定「按年龄给多次」改造报告

**IS_PASS = true**（`flutter analyze` 零问题；`flutter test` 全量 **1759 组全绿**，基线 1731 + 本改动新增 15 + 同期队友新增）

> 15–19 档取 0 次已由 team-lead 裁定确认（「镜像项目现有 ageTable，不要改官方表」），裁定三条依据：oracle 契约优先、少年档以幸运骰替代是既有设计意图、用户诉求是「年龄越大次数越多」。本文 §1 保留推导过程。

用户原话：
> 教育进步检定随着年龄的增长应该检定次数越来越多（你根据 coc 7th 的规则书来设置），现在好像无论多少年龄都是检定一次，你审查一下。"教育进步检定"的按钮不要 emoji，只要文字。

---

## 1. 官方 CoC 7e 年龄表 vs 本项目现有档位

官方《守秘人规则书》「创建调查员 · 年龄」：

| 年龄 | 官方 EDU 增强检定次数 | 官方属性调整 |
|---|---|---|
| 15–19 | **2 次** | STR+SIZ 合计 −5，幸运掷两次取高 |
| 20–39 | 1 次 | 无 |
| 40–49 | 2 次 | STR/CON/DEX 合计 −5，APP −5，MOV −1 |
| 50–59 | 3 次 | 合计 −10，APP −10，MOV −2 |
| 60–69 | 4 次 | 合计 −20，APP −15，MOV −3 |
| 70–79 | 4 次 | 合计 −40，APP −20，MOV −4 |
| 80–89 | 4 次 | 合计 −80，APP −25，MOV −5 |
| 90+ | 4 次 | 同上 |

项目 `lib/domain/rules_coc7.dart#ageTable`（145–208 行）**已经有 `eduChecks` 字段**，属性扣减档位与官方表**逐档一致**，只有 15–19 档不同：

| 项目档位 | `physLoss` | `appLoss` | `movLoss` | `eduChecks`（项目现值） |
|---|---|---|---|---|
| ≤19 | 5（STR/SIZ 分摊） | 0 | 0 | **0** |
| ≤39 | 0 | 0 | 0 | 1 |
| ≤49 | 5 | 5 | 1 | 2 |
| ≤59 | 10 | 10 | 2 | 3 |
| ≤69 | 20 | 15 | 3 | 4 |
| ≤79 | 40 | 20 | 4 | 4 |
| ≤89 | 80 | 25 | 5 | 4 |
| ≤999 | 80 | 25 | 5 | 4 |

### 推导依据（15–19 档为什么取 0 而不是 2）

项目把少年档的「教育机会」换成了 **「幸运骰 2 次取较高值」**（见该档 note 原文），`eduChecks` 记 0。因此：

1. **归属判断**：`eduChecks` 属于「次数」概念，不属于「属性扣减」；按任务里的兜底条款「以项目现有档位为准推导次数」，本项目少年档推导结果为 **0**。
2. **一致性**：`ageAdjust().eduChecks`、基本资料页「教育进步检定 N 次」、概要页、`test/fixtures/engine.json` 的 oracle 夹具（15 岁那条 `eduChecks: 0`，来自旧 JS 原码）全部以年龄表为准。若单方面把 15–19 改成 2：
   - `ageAdj.rule` 会与 JS oracle 夹具不符 → `oracle_engine_test` 必红（红线：不动 oracle 契约）；
   - 基本资料页/概要页会显示「0 次」而属性页允许 2 次，两个页面互相打脸。
3. **单调性**：官方表 15–19=2、20–39=1 天然是「年龄小的反而次数多」，与用户原话「随着年龄的增长次数越来越多」以及任务要求「次数必须随年龄单调不减」直接冲突。取 0 后序列为 **0,1,2,3,4,4,4,4**，单调不减成立。

> 结论：`eduCheckAllowance` **镜像项目 `ageTable`**（而不是照抄官方表），并在 doc 注释里把这处偏差与理由写明。已加**护栏测试**：15–99 岁逐岁断言 `eduCheckAllowance(age) == ageRule(age)['eduChecks']`，两处一旦漂移立刻红。
>
> 如后续产品决定对齐官方表，只需同时改 `ageTable` 的 15–19 `eduChecks` 与 oracle 夹具，两行改动；本次未动，以守住 oracle 契约。

---

## 2. 改动清单

| 文件 | 改了什么 |
|---|---|
| `lib/domain/edu_check.dart` | 新增 `int eduCheckAllowance(int age)`（纯 Dart，不 import 任何东西）；`eduCheck(edu,d100,d10)` **一字未改**（签名/行为/边界全保留） |
| `lib/domain/rules_coc7.dart` | **未改动**（年龄表已经是对的，改了会破 oracle 夹具；`eduImproveCheck` 也保持原样） |
| `lib/ui/create/chargen_logic.dart` | 新增 `eduCheckAllowanceOf` / `eduChecksUsed` / `eduChecksRemaining`；`eduChecked` 语义改为「次数用完了」；`runEduCheck` 改为「剩余 > 0 才掷、每次追加一行 log（失败也追加）、返回体加 `n/used/remaining`」；`dropStaleEduChecks` 兼容性未受影响（`baseEdu` 仍每次刷新） |
| `lib/ui/create/steps/step_attrs.dart` | `_eduBlock` 重写：按钮换纯文字 `FilledButton`（去掉 🎲/✓ 与 casino/check 图标）、新增 `Key('edu_check_remain')`、结果文案加「第 N 次检定：」前缀、副标题说明各年龄段次数 |
| `lib/ui/create/create_flow_page.dart` | `_maybeHintEduCheck` 判据 `eduChecked`（做过没）→ `eduChecksRemaining <= 0`（还有没有剩）；文案带上剩余次数；仍不硬拦、仍只弹一次 |
| `test/p10_edu_check_test.dart` | 16 例 → 29 例（扩 4 个 group，未删任何原有可用用例） |

`lib/domain/**` 仍然零 IO / 零随机 / 零 Flutter 依赖。

---

## 3. 行为对照

| 场景 | 改前 | 改后 |
|---|---|---|
| 25 岁 | 1 次 | 1 次 |
| 45 岁（EDU 50，每次掷 100/10） | 只能 1 次 | 2 次：50→60→70 |
| 65 岁 | 只能 1 次 | 4 次 |
| 17 岁 | 1 次 | 0 次（按钮「**本年龄段不做检定**」且禁用，副标题说明改为幸运两次取高） |
| 失败一次后 | 按钮禁用 | 用掉 1 次，剩余次数继续可掷 |
| 按钮文案 | `🎲 进行检定` / `✓ 已完成（不能重掷）` | `进行检定（还剩 N 次）` / `已完成（N/N）` / `本年龄段不做检定` |
| 剩余次数 | 无 | `还可检定 N 次（已做 U/N）` / `检定次数已用完（U/N）` / `本档不做教育进步检定（0/0）` |
| 结果文案 | `掷出 63 > 教育 55 → 教育 +7，现为 62` | `第 2 次检定：掷出 63 > 教育 55 → 教育 +7，现为 62` |
| 下一步提示 | 「还没做教育进步检定」 | 「还有 N 次教育进步检定没做」（剩余 0 → 不弹） |

规则细节：每次都用**当时生效的 EDU** 比大小（逐次累加），封顶 99；失败也占一次机会；把年龄改小导致「已用 > 允许」时剩余夹到 0，已做的检定不回退。

---

## 4. 测试账目

`test/p10_edu_check_test.dart`：**16 → 31 例**

| Group | 用例 | 覆盖 |
|---|---|---|
| A（原有 7） | `eduCheck` 纯函数边界 | 未改动 |
| B（原有 2） | runEduCheck 单次语义 / 掷骰顺序 | 未改动（25 岁仍是 1 次，断言依然成立） |
| B-UI（原有 2） | 属性页掷骰 → 生效 EDU 涨、按钮禁用 | 未改动 |
| C（原有 2） | 未检定提示不拦路、只弹一次 | 未改动（32 岁 = 1 次） |
| D（原有 3） | 年龄扣 DEX → 闪避基础值 | 未改动 |
| **E（新 5）** | 逐档断言 15/19/20/39/40/49/50/59/60/69/70/79/80/89/90/99；**20 岁起**逐岁单调不减（少年档 0 不参与，注释写明原因）+ 低龄段不高于高龄段；<15/0/负数→0；与 `ageRule().eduChecks` 逐档护栏；`eduCheckAllowanceOf`（空年龄兜底 25 岁） | 次数表 |
| **F（新 5）** | 20 岁第 2 次返回 null；60 岁 4 次逐次累加 `before=[85,95,99,99] / after=[95,99,99,99] / gain=[10,4,0,0]`、4 行 log、bonus=14、第 5 次 null；失败算一次；17 岁一次都掷不了；改小年龄剩余夹 0 | 次数上限与累加 |
| **G（新 3）** | 60 岁 UI：按钮文案逐次递减、`第 2 次检定：…`、`还可检定 N 次`、4 次后禁用 `已完成（4/4）`、逐码点断言无 emoji；40 岁 UI：失败一次后剩 1 次且仍可掷；17 岁 UI：`本年龄段不做检定` 且禁用 | UI |
| **H（新 2）** | 42 岁做 1 次后点下一步 → 提示含「还有 1 次」且不拦路；做满 2 次 → 不提示 | 未检定提示 |

命令与结果：

```
flutter analyze                                   → No issues found!
flutter test test/p10_edu_check_test.dart         → +31 All tests passed!
flutter test test/p10_edu_check_test.dart test/oracle_rules_test.dart \
  test/create_extra_steps_test.dart test/create_flow_widget_test.dart \
  test/qa_probe_test.dart                          → All tests passed!
flutter test                                       → +1759 All tests passed!   （基线 1731 + 本改动 15 + 同期队友新增）
```

> 期间有一次全量跑到 1730+1 红，原因是队友（overlay-fix）正在写 `lib/ui/home_page.dart` / `lib/ui/art.dart`，测试编译时撞上半写状态（报错是 `p10_roster_rule_test.dart` 的 **loading** 编译失败、以及 `qa_probe` 的「英灵殿标题不许再叠」）。等那两位的文件落盘后重跑，全量全绿，与本改动无关。

---

## 5. 反向自证伪（两次注入后恢复）

**注入 1：`eduCheckAllowance` 恒返回 1**（= 回到「无论多少岁都只检定一次」的旧行为）

→ **13 条红**：E 组 5 条（逐档、单调、异常值、与 ageTable 护栏、`eduCheckAllowanceOf`）；F 组 3 条（60 岁 4 次、17 岁 0 次、改小年龄后夹 0）；G 组 3 条（60 岁 UI、40 岁 UI、17 岁 UI）；H 组 2 条（还有剩余次数的提示）。说明「高龄多检定 / 少年档 0 次」都真被钉住了，不是空跑。

**注入 2：`runEduCheck` 失败时不追加 log**（= 失败不占次数）

→ **3 条红**：
- `F · 失败也算用掉一次：20 岁掷出 1 ≤ 教育 60 → 剩余直接归零`
- `G · 40 岁：第 1 次失败也算用掉一次，剩余 1 次且还能再掷`
- `B-UI · 掷出值 ≤ EDU → …按钮同样变禁用`（原有用例同样兜住）

两次注入都用 `cp` 备份后恢复，恢复后 `grep TEMP-SAOBOTAGE` 为空、`flutter analyze` 零问题、全量 **1759** 绿。

---

## 6. 老测试改动

- **没有删除/放宽任何原有断言**。原有 16 例全部保留且全部通过（25 岁、32 岁的卡本来就是 1 次，语义未变）。
- `_gotoAttrs` 增加可选参数 `String age = '32'`（默认值不变，老调用点零改动）。
- 新增两个测试辅助：`_labelOf`（从按钮后代捞 Text，因为 Key 挂在 `FilledButton` 上，既有用例要对它取 `widget<FilledButton>()`，不能挪 Key）与 `_alwaysMax` / `_alwaysMin`（恒定随机源，把「每次都成功 / 必失败」写成确定性断言，比扫种子更稳）。
- 文件头注释补充 P11 的 E/F/G/H 四组说明。

## 7. 已知偏差 / 遗留

1. **15–19 岁 = 0 次**（官方 2 次）：已由 team-lead 裁定「镜像项目现有 ageTable、不改官方表」，三条依据见文首。若将来产品要改，需同时改 `ageTable.eduChecks` + oracle 夹具，本次不动。
2. `step_attrs` 的副标题把「20–39/40–49/50–59/60+」四档写死在文案里；数值本身来自 `eduCheckAllowance`（次数）与 `ageTable`（展示），文案只是说明性文字，不影响判定。
3. `eduChecked(card)` 的语义从「做过至少一次」变为「次数用完」。当前唯一调用点是测试（`create_flow_page` 已改用 `eduChecksRemaining`），保留它是为了不破坏既有测试 API。
4. 少年档（0 次）的 UI 文案是「本年龄段不做检定」+ 禁用 + 「本档不做教育进步检定（0/0）」，不再显示容易误解的「已完成（0/0）」。
