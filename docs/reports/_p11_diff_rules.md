# P11 · 判定规则（纯计算）差异盘点

> 基准：老 APP `coc7th-card-app/.../js/core/room-rules.js`（1591 行 / 53 个导出）、
> `js/core/rules-coc7.js`（769 行，与房间相关的计算片段）
> 对照：`dice-realm/lib/domain/`（`room_rules.dart` + 5 个 part、`rules_coc7.dart`、`edu_check.dart`）
> 本报告**只盘点、未改任何文件、未运行 flutter test / build**。所有行号均来自实际读取。

---

## 0. 结论摘要

| 项 | 结果 |
|---|---|
| `room-rules.js` 53 个导出成员 | **53/53 全部有 Dart 实现**（拆进 `room_rules_core/opposed/expr/sheet/combat.dart` 五个 part + `room_rules.dart` 门面） |
| 「老 APP 有、新工程完全没有」的规则 | **0 条** |
| 真正的行为差异 | **4 条**（1× P1、3× P2），全部属于「边界/文案/口径」，**没有一条会算错骰子** |
| 与 diff-flow 交界的 SAN/疯狂条目 | 4 条，归属已划清（见 §3.1）；其中 `afterSanLoss` 早退归 diff-flow，我交叉确认其结论成立且**不影响 D08「1/5 公式已对齐」** |
| `rules-coc7.js` 房间相关计算（DB/派生属性/理智上限/教育进步/年龄调整/技能上限） | **6/6 全部 1:1 移植** |
| 等价性证据 | `test/fixtures/room_rules.json` 有 **455 例**由 JS 端生成的夹具，`test/room_rules_oracle_test.dart` 逐字段深比较 + 校验随机数消耗数（`used == randUsed`）。⚠️ 该测试本次**未运行**（按硬要求），结论基于逐行代码比对 + 夹具覆盖面统计 |

**因此：判定规则层不是「要补齐」，而是「已补齐，只需修 1 处口径 + 3 处边界」。**

---

## 1. 差异清单

| 编号 | 差异点 | 老 APP（文件:行号 + 代码） | 新工程（文件:行号 + 现状） | 判定 | 影响 | 建议 |
|---|---|---|---|---|---|---|
| **D-01** | 精神分析**失败**时，处于「临时/不定疯狂」的目标是否扣 SAN | `room-model.js:5035` `var sanLoss = (loss && loss.ok) ? Math.max(1, num(loss.total, 1)) : 1;`<br>`room-model.js:5039` `var sanAfter = Math.max(0, num(sanBefore, 0) - sanLoss);`（无条件扣） | `room_model_actions_sheet.dart:1751` `final targetMadActive = mental_state.blockedByMadness(...);`<br>`room_model_actions_sheet.dart:1756` `final appliedLoss = targetMadActive ? 0 : sanLoss;` | ❌ 不等价 | 老 APP：精神分析失败一律扣 1D6 SAN；新工程：**目标已处于临时/不定疯狂时 SAN 一点不掉**。且 `appliedLoss == 0` 时 `1759` 的 `if (appliedLoss > 0)` 让 `stateApply` **整段跳过**（连 EVT.STATE 都不发，客户端人物卡完全不被触碰），只留一条「本次不受 SAN 减损」日志。玩家会看到「队友精神分析失败，但我 SAN 没变」。⚠️ 但老端**已有同类口径**：`memberMadActive` 拦截在 `room-model.js:5499`（KP 定向 SAN Check）与 `:5528`（追加理智损失）各一处（v2.5.0 需求「疯狂发作中不接受 SAN 检定/追加损失」），新端 `:1102` / `:1439` 一一对应 → P8 这条是**同一产品方向的延伸**，不是凭空发明。**换个说法：老端在「KP 定向 SAN Check」与「追加 SAN 损失」两条路径上是直接拒绝操作（提示「正处于疯狂发作中，不能…」），只有精神分析这一路漏了拦截；新端把它补齐为「照样结算、但不扣 SAN」**——所以这条更像「补齐一致性」而非「改规则」 | 若以老 APP 为准：删掉 `room_model_actions_sheet.dart:1750-1756` 的免减分支，`appliedLoss` 直接用 `sanLoss`（`1775` 的 `afterSanLoss(target, appliedLoss, bySeat)` 同步改回 `sanLoss`）。若保留 P8 口径：必须在验收表写明「与 2.13.13 有意不同」。**建议倾向保留**（与既有 2 处拦截一致），只需产品签字 |
| **D-02** | 先攻排序：**同 DEX 同名档**的兜底比较口径不同 | `room-rules.js:859` `return String(x.name).localeCompare(String(y.name));`（ICU 语言环境排序） | `room_rules_combat.dart:70` `return jsStr(x['name']).compareTo(jsStr(y['name']));`（UTF-16 码位比较） | ⚠️ 部分 | 只在「effDex 与 dex 完全相同」时触发。两个同 DEX 的中文昵称会排出不同先后：老 APP（zh 环境按拼音）「李四」<「张三」，新工程按码位「张三」(U+5F20) <「李四」(U+674E)。玩家看到的是**先攻顺序和手机上不一样**。与 D01 结论不冲突（D01 比较的是 DEX 不同的情形） | 不建议去模拟 ICU。建议改成**确定性次序**：同 effDex/同 dex 时再按 `seat` 号排（并同步改老端或直接以新端为准），彻底摆脱语言环境依赖。若必须与老端逐字节一致，只能固定 collation（代价大、收益低）→ 建议列为 P2 |
| **D-03** | 场景检定等级文案：`level` 若为 `double` 则文案丢失 | `room-rules.js:1399` `levelText: LEVEL_TEXT[String(lvl)] \|\| ''`（JS 无 int/double 之分，`String(4.0)==='4'`） | `room_rules_sheet.dart:523` `'levelText': CocRules.LEVEL_TEXT['$lvl'] ?? ''`（`4.0` → `'4.0'` → 未命中 → `''`） | ⚠️ 部分 | 场景检定结果里的等级文字变空（显示「」而不是「困难成功」）。`_toLevelNumber` 在 `494-495` 行原样返回 `num`，而调用方 `room_model_actions_combat.dart:2545/2555` 用 `raNum(...)`（会保留 double）→ 客户端 JSON 传 `4.0` 即可触发 | `room_rules_sheet.dart:521-523` 改用 `CocRules.LEVEL_TEXT[jsStr(lvl)]`，或 `_toLevelNumber` 统一 `.toInt()`。一行改动 |
| **D-04** | `rollExpr(null)` 的错误文案不同 | `room-rules.js:588` `typeof expr === 'string' \|\| 'number' ? parseExpr(expr) : expr` → `null` 走 `p=null` → `589` `'骰式不合法'` | `room_rules_expr.dart:113` 非 String/num/Map → `_parseExpr(null)` → `'骰式为空'`（`:27`） | ⚠️ 部分（仅文案） | `ok` 都是 `false`，判定一致；但 `reason` 会原样弹给玩家（`room_model_actions_combat.dart:824-826`），空伤害式时的提示从「骰式不合法」变成「骰式为空」。属体验差异，不是错算 | 可不动。若要一致：`room_rules_expr.dart:112-113` 对 `null` 单独返回 `骰式不合法` |

### 备注（不算与老 APP 的差异，但建议顺手清掉）

| 编号 | 事项 | 证据 | 判定 | 影响 | 建议 |
|---|---|---|---|---|---|
| N-01 | 武器「故障值 = 100」口径自相矛盾 | 规则层 `room_rules_expr.dart:259-268` 接受 `1..100`（100 → 「掷出 100 才卡壳」）；新表单校验 `weapon_rules.dart:18-21, 27-38` 只接受 `1..99`，100 直接判非法 | ⚠️ 内部不一致 | 老 APP 填表占位符就是 `'99 / 100 / ——'`（`ui/steps-c.js:180`），老存档里存在 100 的枪 → 在新工程武器表单里会被判「故障值必须在 1-99」。规则层判卡壳的逻辑本身与老 APP 一致，不产生错算 | 二选一：`weaponMalfunctionMax` 放宽到 100，或规则层把 100 视为「永不故障」（`_malfunctionThresholdOf` 返回 0）。改哪边都要同时改另一处，别只改一边 |
| N-02 | `dice.dart` 里两个「零调用」的旧实现仍在，且带已知缺陷 | `dice.dart:60 d100Bonus`（先对十位骰取 min 再判 100，个位骰为 0 时结果取反）、`dice.dart:80 successLevel`（只按原始技能值判大失败，不看本次要求阈值） | ✅ 等价（两边同为死代码） | 老 APP `dice.js` 同样零调用（`room-rules.js:19-24` 注释已声明绕开）。**只要不接线就不会出问题** | 建议加 `@Deprecated` 或直接删除，防止后人误用；删除属 P2 |

---

## 2. 等价登记（逐函数 → 新工程位置）

> 判定一律 ✅ 等价。行号 = 老文件 `room-rules.js`；右侧 = Dart 实现位置。

### 2.1 阈值与成功等级
| 老 | 新 | 备注 |
|---|---|---|
| `thresholds` 120-123 | `room_rules_core.dart:54-62` | `Math.floor(b/2)` ↔ `b ~/ 2`，b 已夹 ≥0，等价 |
| `normDifficulty` 124 | `core:64-65` | |
| `targetOf` 125-127 | `core:67-68` | |
| `critThresholdOf` 146-151 | `core:71-76` | 默认 1、上限 100 一致 |
| `fumbleThresholdOf` 152-157 | `core:79-84` | 0 = 走动态规则一致 |
| `fumbleRange` 158-162 | `core:87-98` | 用「要求阈值 <50 ? 96-100 : 100-100」一致 |
| `isFumble` 163-167 | `core:100-110` | 老 `value===100` 严格相等；Dart 只对 `num` 生效，但 100 恒落在 range 内 → 结果等价 |
| `levelOf` 181-192 | `core:116-131` | 等级看 base、大失败看 target，两个分母没有混 |

### 2.2 百分骰（奖励/惩罚）
| 老 | 新 | 备注 |
|---|---|---|
| `die10` / `clampDie10` / `combine` 90-103 | `core:23-37` | `combine(0,0)=100` 一致 |
| `clampValue` 104-109 | `core:39-44` | |
| `rollD100` 220-254 | `core:144-196` | **先组合再比大小**的顺序一致（`combos` 生成在取 min 之前），个位骰为 0 时不会取反 |
| `describeDice` 256-263 | `core:199-214` | |

### 2.3 检定 / 推动 / 幸运
| 老 | 新 | 备注 |
|---|---|---|
| `PUSHABLE` / `PUSH_REASON` 62-71 | `core:220-234` | |
| `LUCK_FORBIDDEN` 74-80 | `core:236-242` | |
| `check` 282-330 | `core:245-314` | 字段集、`canSpendLuck = level===FAIL && value>1` 一致 |
| `describeCheck` 332-341 | `core:316-332` | 文案逐字一致 |
| `canPush` 353-362 | `core:339-362` | |
| `luckAllowed` 373-378 | `core:369-374` | |
| `spendLuck` 387-421 | `core:377-428` | 最低压到 1、多花点数退还、`growthEligible:false` 一致 |

### 2.4 对抗
| 老 | 新 | 备注 |
|---|---|---|
| `opposed` 435-459 | `room_rules_opposed.dart:23-70` | 等级 → 技能值 → 重掷 三级一致 |
| `opposedReroll` 462-468 | `opposed:73-94` | 低者胜、同值继续重掷一致 |
| `opposedAttack` 489-531 | `opposed:101-201` | 反击同级→攻方胜、闪避同级→攻方败、通用 10 轮兜底判 a 全一致；`rerollMax` 的 0/负数语义一致 |
| `opposedFull` 534-537 | `opposed:204-216` | |
| `normMode` 917-922 | `opposed:13-20` | 中英文别名（闪避/反击/fight_back）一致 |

### 2.5 骰式 / 伤害 / 贯穿 / 连发 / 故障
| 老 | 新 | 备注 |
|---|---|---|
| `parseExpr` 554-584 | `room_rules_expr.dart:24-103` | 令牌正则 `[+-]?[^+-]+` 完全一致（含「`1D6+-2` 静默吃掉 `+`」这类怪癖），MAX_DICE/MAX_SIDES/常数上限 10000 一致 |
| `rollExpr` 587-608 | `expr:106-163` | 接受预解析对象 ↔ 接受 Map |
| `rollDamageBonus` 611-616 | `expr:166-178` | `'0'`/空 → 0 一致 |
| `maxOfExpr` 925-934 | `expr:181-196` | |
| `maxOfDamageBonus` 941-946 | `expr:199-204` | |
| `impaleDamage` 962-968 | `expr:207-224` | 「武器最大值 + **最大 DB** + 再投一次」一致 |
| `burstMaxOf` 1422-1436 | `expr:227-253` | `1(3)` / `N连射` / `or N` / 全自动≥3 / 纯数字，优先级与取 max 一致 |
| `isBurstWeapon` 1439 | `expr:256` | |
| `malfunctionThresholdOf` 1442-1451 | `expr:259-268` | 空/`——`/非法 → 0（永不故障），1-100 有效 |
| `malfunctionOf` 1459-1466 | `expr:271-285` | 大成功不故障、`v >= th` 判故障一致 |
| `isRevolver` / `defaultMalfunctionType` 1472-1487 | `expr:288-300` | 左轮→哑火、连发→供弹、其它→卡弹一致 |
| `burstSelfDamage` 1490-1493 | `expr:303-310` | 1D3−1 下限 0 |
| `malfunctionEffect` 1503-1541 | `expr:313-370` | 卡弹 1D6 / 供弹 1D4+2 / 哑火 1 回合 / 炸膛 1D3−1 全部一致；`JAM_TYPES[type]` ↔ `containsKey` 仅差 `'constructor'` 这类不可达原型键 |

### 2.6 SAN / 伤势
| 老 | 新 | 备注 |
|---|---|---|
| `parseSanLoss` 626-638 | `room_rules_sheet.dart:14-49` | 两侧都过 `parseExpr` 校验，`0/999D999` 会被拒 |
| `resolveSanCheck` 651-682 | `sheet:52-102` | 成功取斜线前、失败取后；`maxSan` 默认 99；只做上限约束 |
| `insanityFlags` 693-713 | `sheet:108-135` | `loss>=5` 临时、`dayTotal*5 >= dayStart` 不定（不做除法取整）、`threshold = ceil(dayStart/5)` 一致 |
| `damageFlags` 728-757 | `sheet:153-194` | 重伤 `dmg*2>=maxHP`、致死 `dmg > maxHP`（恰等于走濒死）、归零分流一致 |
| `dyingRoundCheck` 772-782 | `sheet:216-231` | |
| `temporaryInsanityCheck` 800-810 | `sheet:236-254` | INT 成功=「理解」→ 发作，语义一致 |
| `boutRounds` 813-815 | `sheet:257` | 1D10 |

### 2.7 行动顺序 / 攻击结算
| 老 | 新 | 备注 |
|---|---|---|
| `initiativeOrder` 834-882 | `room_rules_combat.dart:24-113` | DEX+50（已准备枪械）、多动作展开成多槽位、manualOrder 优先、`lastSlot` 全部一致；**唯一差异见 D-02** |
| `advanceTurn` 889-897 | `combat:116-139` | 不删条目、走完 round+1 一致 |
| `resolveAttack` 1001-1126 | `combat:148-326` | 远程 fightback→dodge 降级、闪避胜出免伤、反击由防御方结算、护甲 `max(0, raw-armor)`、贯穿仅在攻方极难/大成功且 `impale` 时生效、`flags` 复用 damageFlags 一致 |
| `OUTCOME` / `ATTACK_LEVEL_KEY` 904-914 | `room_rules.dart:85-90` / `combat:12-19` | 常规成功写 `success` 一致 |
| `buildAttackSummary` 1129-1153 | `combat:329-376` | 文案逐句一致 |

### 2.8 角色卡取值 / 场景步骤
| 老 | 新 | 备注 |
|---|---|---|
| `ATTR_CN2KEY` 1160-1170 | `sheet:264-294` | |
| `normSkillName` / `skillBase` / `skillSpecs` 1210-1245 | `sheet:316-359` | 全/半角括号归一、去空白与首尾标点、大小写一致 |
| `skillValue` 1265-1300 | `sheet:361-421` | 四级匹配（精确→别名→基名→子类名），歧义返回 null 一致 |
| `attrValue` 1306-1324 | `sheet:424-446` | 中文/key/大小写变体回退一致 |
| `normBranch` / `sceneStepPlan` 1331-1363 | `sheet:452-491` | `next==='end'/'done'/'结束'` 视为终止且原样回传一致 |
| `toLevelNumber` / `sceneStepResolve` 1366-1405 | `sheet:494-529` | 分支选择、`critical`/`fumble` 标注一致；**文案见 D-03** |

### 2.9 rules-coc7.js（房间相关片段）
| 老 | 新 | 备注 |
|---|---|---|
| `DB_TABLE` / `dbBuild` 308-329 | `rules_coc7.dart:425-448` | 8 档表 + 「>444 每 80 点 +1D6/+1 体格」的溢出公式一致 |
| `derived` 334-369 | `rules_coc7.dart:453-496` | HP=⌊(CON+SIZ)/10⌋、MP=⌊POW/5⌋、SAN上限=POW、MOV 7/8/9 + 年龄扣减下限 1、闪避=⌊DEX/2⌋ 一致 |
| `maxSan` 372-374 | `rules_coc7.dart:499-502` | 99 − 克苏鲁神话 |
| `AGE_TABLE` / `ageRule` / `spreadLoss` / `PHYS_FLOOR` 55-123 | `rules_coc7.dart:144-277` | 逐点轮转分摊、单项下限 15、`unapplied` 一致 |
| `ageAdjust` 125-191 | `rules_coc7.dart:285-376` | `eduBonus` 只作用于 eff、`appLoss = min(raw.app, appLoss)` 一致 |
| `eduImproveCheck` 298-305 | `rules_coc7.dart:410-422` + `edu_check.dart:70-91` | `roll<=cur` 不进步、`roll>cur` 加 1D10 封顶 99；**随机数消耗顺序（进步才掷 1D10）也一致** |
| `skillCapOf` / `capExempt` / `isGrowthOnly` 388-425 | `rules_coc7.dart:516-575` | 母语/信用评级上限 99、基础值不判超限一致 |
| `radar` 666-698 | `rules_coc7.dart:818+` | 仅展示用 |

---

## 3. ⚠️ 重要：这些规则**两边都没有接线**，不要判成「新工程缺失」

以下 15 个导出在 `room-rules.js` 里实现完整、但**老 APP 全仓（含 `ui/**`）grep 不到任何调用点**；
新工程同样只在规则层实现、业务层零调用。因此它们属于「两边等价的死代码」，**不是回归**：

`spendLuck`（花幸运点改结果）、`canPush` / `pushBlockReason`（推动检定）、`luckAllowed`、
`insanityFlags`（疯狂提示文案）、`boutRounds`、`advanceTurn`、`sceneStepPlan`、
`maxOfExpr`、`thresholds`、`levelOf`、`fumbleRange`、`isFumble`、`combine`、`describeCheck`
（`damageFlags` 只被 `resolveAttack` 内部复用，行为一致）。

两条容易误判的补充：

1. **`check.push` 不是缺失，但也不是"新工程只登记"——要区分 POLICY 与分发两层**：
   - POLICY 层：老 `room-model.js:222` `'check.push': {roles:['kp'],confirm:null}` ↔ 新 `room_types.dart:289`，**只登记，两边一致**；
   - 分发层：老 `applyAction` 的 if/else 链从 `check.request`(`:1806`) / `check.opposed`(`:1808`) 直接跳到 `scene.check.push`(`:1810`)，**没有 `check.push` 分支 → 静默空操作**；新 `room_model_actions_combat.dart:92-93` `case 'check.push': return checkRequest(seat, p);` → **会真发一条检定请求**。
   - 判定：✅ 等价（POLICY）**+ 行为增强**（分发侧「新有老无」）。因 UI 侧零调用点，线上症状为 0，不算缺失；但严格说是 15 个「新有老无」分发 op 之一 —— 这条归属 **diff-actions**（其 `_p11_diff_actions.md` 已覆盖），我这里只做交叉引用。
2. **「幸运恢复」老 APP 里根本不存在**（无任何恢复幸运点的规则/入口）。新工程也没有 —— 等价，不需要补。

### 3.1 与 diff-flow / diff-actions 的归属划分（避免重复计票）

| 事项 | 归属 | 我的结论 |
|---|---|---|
| 精神分析失败免 SAN 减损 | **diff-rules（本报告 D-01）** | 我的 D-01，diff-actions 已确认不单列 |
| `afterSanLoss` 在临时/不定疯狂期整体早退（新 `room_model_actions_sheet.dart:1224-1232` vs 老 `room-model.js:5160-5271` 无此早退） | **diff-flow（其 F02）** | 交叉确认：老端确实没有该早退，会继续累计 `_sanLostThisRound` 并允许 ②（`loss>=5 && !isFaded`）再抽一条症状、④ 再判不定疯狂；新端 `1224-1232` 直接 return → 连累计都停。**但「1/5 阈值公式」本身与老端逐字一致**（新 `1281-1285` `ceil(maxSAN/5)` + `lossTotal >= oneFifth` ↔ 老 `5242-5244`），所以 D08 的"公式已对齐"结论**不变**，差异只在"是否早退" |
| `addSymptom` 不派生「疯狂症状」标签 / `cureIndefinite` 连带清「临时疯狂」 | **diff-flow（其 F03 / F04）** | 纯精神状态机，未纳入本报告 |
| `check.push` 分发侧接到 `checkRequest` | **diff-actions** | 见上条补充 1 |
| `stateApply.writeField` 对非数字字符串跳过 vs 老 `clampNumber` 回落写回旧值 | **diff-flow** | 我认同"结果等价"（都表现为值不变），但 `''` 空串清值场景需 UI 侧确认，我这侧无补充 |

---

## 4. 优先级汇总

| 优先级 | 编号 | 一句话 | 触发条件 |
|---|---|---|---|
| **P0**（影响对局正确性） | — | **无** | — |
| **P1**（口径待确认，非缺陷） | D-01 | 精神分析失败：新工程对已疯狂目标免 SAN 减损，老 APP 一律 −1D6；但老端已有两处同类 `memberMadActive` 拦截，倾向保留 P8 口径 | 每次玩家用「精神分析」且失败 |
| **P2**（边界 / 技术债） | D-03 | 场景检定等级文案在 `level` 为 double 时丢字 | 客户端传 `4.0` 这类浮点等级 |
| **P2** | D-02 | 同 DEX 同 effDex 时先攻次序依赖语言环境比较 | 两名角色 DEX 完全相同 |
| **P2** | D-04 | 空骰式的报错文案从「骰式不合法」变「骰式为空」 | 空伤害式 / 空骰式输入 |
| **P2** | N-01 | 故障值 100 在表单被判非法、在规则层又有效 | 老存档/自定义武器填 100 |
| **P2** | N-02 | `dice.dart` 里两个带缺陷的死代码仍在 | 只要不接线即安全 |

### 建议先改的 3 条（按收益/成本比）
1. **D-01** —— 唯一一条会改变实际数值结果的分歧，且方向是「对玩家更宽松」，必须先跟产品确认 P8 口径再决定改不改；不改也要在验收表里写明「与 2.13.13 有意不同」。
2. **D-03** —— 一行 `jsStr()` 就能修，且修完能同时挡住「等级文案/等级键」两类同类问题（`_toLevelNumber` 返回 `num` 是根因）。
3. **N-01** —— 不是算错，但会让玩家在老存档武器上看到「非法」红字，体感上像数据损坏；统一口径成本很低。
