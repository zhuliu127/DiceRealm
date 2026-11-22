# P9-9 战斗技能跟随武器 + 闪避基础值 —— 施工报告

范围：需求 9（用户原话两条）
> 9. 无论哪种车卡方式，自动生成的战斗技能要和角色实际携带的武器对得上（指虎→斗殴，手枪→射击（手枪），
>    没武器→斗殴）；闪避要自带 DEX×½ 的基础点数，学闪避是在这个基础值上加。

结论：**IS_PASS**。`flutter analyze` 零问题；`flutter test` 全量 **1676 组全绿**（基线 1636 + 本批 28 + 其它工程师并行批次）。

---

## 一、武器 → 战斗技能映射（唯一事实源）

新增纯 Dart 模块 `lib/domain/combat_skill_map.dart`，三层口径：

1. **别名归一**：武器表（`data/weapons.dart`）的 `skill` 是人类写法，和技能表专攻名不一致；
2. **查实例 key**：组技能 `id::专攻`（`fighting::斗殴`），独立技能用 id（`throw`）；
3. **只认战斗分类**：`category == '战斗'` 的才算，雷管的「电气维修」不算。

### 1.1 别名归一表（`weaponSkillAlias`）

| 武器表写法 | 归一后（技能表专攻名） |
|---|---|
| 剑 | 刀剑 |
| 鞭子 | 鞭 |
| 绞具 / 绞绳 | 绞索 |
| 链枷 / 电锯 / 链锯 | 链锯/连枷 |
| 机枪 / 重武器 / 喷射器 / 火焰喷射器 | 机枪/重武器/火焰喷射器 |
| 步枪 / 霰弹枪 | 步枪/霰弹枪 |
| 弩 / 弓弩 | 弓 |

前 8 条与展示层 `lib/ui/card_edit/combat_logic.dart#weaponSkillAlias` 逐字一致（该文件不在本批允许改的清单内，未改动；
一致性由 `p9_combat_skill_test.dart`「与展示层别名表逐条一致」锁死）。

### 1.2 完整映射（覆盖武器表全部 104 条 skill 取值）

| 武器类别（举例） | 武器表 skill | 技能实例 key | 显示名 |
|---|---|---|---|
| 徒手 / 黄铜指虎 / 小刀 / 棍棒 / 火把 | 斗殴 | `fighting::斗殴` | 格斗（斗殴） |
| 中型剑 / 大型剑 / 轻剑 | 剑 | `fighting::刀剑` | 格斗（刀剑） |
| 伐木斧 / 手斧 | 斧 | `fighting::斧` | 格斗（斧） |
| 矛 / 骑士长枪 | 矛 | `fighting::矛` | 格斗（矛） |
| 绞具 | 绞具 | `fighting::绞索` | 格斗（绞索） |
| 长鞭 | 鞭子 | `fighting::鞭` | 格斗（鞭） |
| 电锯 / 双节棍(链枷) | 电锯 / 链枷 | `fighting::链锯/连枷` | 格斗（链锯/连枷） |
| 手枪 / 左轮 | 手枪 | `firearms::手枪` | 射击（手枪） |
| 步枪 / 猎枪 / 霰弹枪 | 步枪/霰弹枪 | `firearms::步枪/霰弹枪` | 射击（步枪/霰弹枪） |
| 冲锋枪 | 冲锋枪 | `firearms::冲锋枪` | 射击（冲锋枪） |
| 机枪 / 重武器 / 火焰喷射器 | 机枪 / 重武器 / 喷射器 | `firearms::机枪/重武器/火焰喷射器` | 射击（机枪/重武器/火焰喷射器） |
| 弓 / 弩 | 弓 | `firearms::弓` | 射击（弓） |
| 投石 / 手里剑 / 掷矛 | 投掷 | `throw` | 投掷 |
| 炸药 / 雷管 / 手榴弹 | 爆破 | `demolitions` | 爆破 |
| 迫击炮 / 野战炮 / 舰炮 | 炮术 | `artillery` | 炮术 |
| 雷管（另一条数据） | 电气维修 | `elec_repair`（**非战斗**，不进闸门） | 电气维修 |

**没有武器 / 武器技能认不出来 → `fighting::斗殴`**（`unarmedCombatSkillKey`）。理由：徒手也打得出来，
这是需求里明确点名的一条。

对外 API：
- `canonicalWeaponSkillName(raw)` — 别名归一
- `skillKeyOfName(name)` / `combatSkillKeyOfWeaponSkill(raw)` — 名字 → 实例 key
- `requiredCombatSkillKeys(character)` / `requiredCombatSkillKeysFromWeapons(list)` — 角色武器 → 闸门集合（含斗殴兜底）
- `isCombatSkillId(id)` / `isCombatSkillKey(key)` — 分类判定（走数据表 `category`，不写死名单）

---

## 二、分配算法怎么改的（三条车卡路径全覆盖）

### 2.1 手动车卡「一键分配」`lib/ui/create/chargen_logic.dart#autoSpendPoints`

- 开算前先按 `requiredCombatSkillKeys(card)` 把武器技能补成实例；
- **本职池**：排序时把「武器对得上的战斗技能」提到最前（本职设定本身不动）；
- **兴趣池**：`_spendInterest(..., combatGate:)` —— 闸门外的战斗技能**直接不进候选**，
  闸门内的排最前（`_gateRank`）；
- 兜底两级：先摊到**非战斗**技能；连非战斗都封顶了才允许回流闸门外（否则「点数必须用完」这条硬 UI 约束会破功）。
  正常卡走不到第二级（非战斗技能 50+ 项）。

### 2.2 换武器之后 `charGen_logic.dart#alignCombatSkillsToWeapons`（新增）

向导的步骤顺序是「技能(5) → 战斗装备(6)」（沿用旧版），玩家常常**先一键分配、后挑武器**。
所以补了一个搬移函数：

- 目标：`requiredCombatSkillKeys`（无武器 = 斗殴），缺实例先补；
- 源：**非本职**战斗技能上的**兴趣点**（兴趣点本来就是自由选择）；
- **本职技能上的职业点一律不动**（职业设定，不是玩家的额外选择）；
- 搬出来的点先喂目标技能，喂满后往非战斗技能兜底，保持点数用完；
- 幂等：没有可搬的点返回 0，一个字节都不改。

接线点（`lib/ui/create/wizard_steps.dart`，只加 `onEnter`，不动步骤顺序）：
- `gear` 步入场（= 战斗装备步刚做完）→ `alignCombatSkillsToWeapons`；
- `summary` 步入场 → 再兜一次（自由跳转到概要页时也能纠正）。

### 2.3 随机车卡 / AI 车卡 `lib/domain/preset_gen.dart#_distributePoints`

旧实现（移植自 `core/preset.js`）用**原样字符串**比对武器的 `skill`：

```js
wantCombat[sk.sub] || wantCombat[sk.id]   // '剑' ≠ '刀剑'，'投掷' ≠ 'throw'
```

于是带剑 / 鞭 / 绞具 / 链枷 / 电锯 / 机枪 / 投掷的卡，战斗点统统被排掉、退回斗殴 —— 真实 bug。
现在改成 `requiredCombatSkillKeys` + 实例 key 比对，并额外加了一条**预支**：

> `weaponSkillPrefund = 40`：随机算法按「基础值高」挑拔尖项，手枪（基础 20）、鞭（基础 5）
> 这类武器技能常常一个点都分不到 —— 那就成了「带了手枪却没学射击（手枪）」。
> 先给它预支 40 点（本职走职业点、非本职走兴趣点），余下的照原算法分，池子总量不变。

---

## 三、闪避基础值（核实结论：**本来就已经是 DEX ~/ 2**）

- 数据：`lib/domain/data/skills.dart` 里 `dodge` 的 `base` 是 0，但带 `'dyn': 'dex2'`；
- 唯一基础值来源：`lib/domain/skillmodel.dart#baseValue` → `(dex / 2).floor()`，并**保留了一条 `id == 'dodge'` 的兜底**；
- `makeSkill` / `syncSkills` / `engine.recalc` 三处都走 `baseValue`，显示层（技能编辑器、概要、角色卡）
  读的都是实例上的 `base` 字段 —— **没有第二处各算一遍**；
- `total = base + growth + occ + int`（`recompute`），所以「学闪避」是**在基础值上加**；
- 点数池只统计 `occ` / `int` 字段（`usedOccPoints` / `interestPoints`），**DEX/2 不占玩家点数**；
- 上限判断用 `total`，即基于「基础值 + 投入」判断。

结论：需求后半段**无需改数据**，只补了回归测试把口径钉死（含奇数向下取整、年龄调整跟随生效属性）。
落点记录：`skillmodel.dart:48`（dyn dex2）、`skills.dart:201`（dyn 标注）、`engine.dart:76`（recalc 时刷新）。

---

## 四、测试账目

新增 `test/p9_combat_skill_test.dart`，**28 组**：

| 组 | 组数 | 覆盖 |
|---|---|---|
| 武器 → 战斗技能映射 | 8 | 近战 / 火器 / 投掷爆破炮术 / 104 条武器不漏映射 / 与展示层别名表一致 / 雷管非战斗不挤掉斗殴 / 无武器只有斗殴 / 多武器 |
| 一键分配按武器对齐 | 7 | 手枪（其它战斗技能全 0）/ 指虎 / 无武器 / 剑→刀剑 / 投石→投掷 / 五种武器批量扫「无配点悬空」/ 本职职业点不被清 |
| align 换武器搬移 | 3 | 无武器→给手枪（斗殴清零）/ 幂等 / 本职点数原地不动 |
| 闪避基础值 | 6 | 8 组 DEX（含 61→30、65→32、99→49、1→0）/ dyn 标注 / 基础+投入 / 基础不占点 / 上限判断 / 年龄调整 |
| preset_gen 生产口径 | 4 | legacy 开关默认关 / 手枪 / 投石连跑 20 次 / 无武器连跑 10 次 |

跑过的相关测试（全绿）：
`p9_combat_skill_test`、`p8_weapon_chargen_test`、`p8_skill_step_test`、`chargen_logic_test`、
`combat_logic_test`、`oracle_rules_test`、`oracle_skillmodel_test`、`qa_probe_test`、`oracle_preset_test`。

全量：`flutter test` → **1676 全绿**；`flutter analyze` → **No issues found**。

---

## 五、自证伪（把映射改错 → 测试必须红）

三次注入、三次实测红，改完全部还原（无残留）：

| 注入 | 结果 |
|---|---|
| ① `weaponSkillAlias` 里加 `'手枪': '斗殴'` | p9 **5 组红**：映射表「火器」/「多把武器」、一键分配「带手枪」、align「搬到手枪」、preset「带手枪」 |
| ② `unarmedCombatSkillKey` 改成 `fighting::刀剑` | p9 **3 组红**：「没有武器 → 闸门里只有斗殴」/「一键分配保底斗殴」/「preset 保底斗殴」 |
| ③ `baseValue` 里把 dex2 与 `id=='dodge'` 两条都改成 `return 0` | p9 **4 组红**：多组 DEX / 基础+投入 / 上限判断 / 年龄调整 |

补充一条实测结论：只删数据里的 `'dyn': 'dex2'` 标注**不会**让行为退化（`baseValue` 有 `id == 'dodge'` 兜底），
但会让「dyn 标注必须存在」这条测试红 —— 双保险，两处都要守住。

---

## 六、改了哪些文件

| 文件 | 改动 |
|---|---|
| `lib/domain/combat_skill_map.dart` | **新增**。映射表 + 闸门函数（纯 Dart，零 UI/IO 依赖） |
| `lib/domain/preset_gen.dart` | 战斗技能比对改走实例 key；新增 `weaponSkillPrefund` 预支；新增 `legacyWeaponSkillMatchForOracle` 预言机开关（默认关） |
| `lib/ui/create/chargen_logic.dart` | `autoSpendPoints` 按武器过滤/优先；新增 `alignCombatSkillsToWeapons`；新增 `_gateRank`、`_ensureSkillByKey` |
| `lib/ui/create/wizard_steps.dart` | 只加两处 `onEnter`（`gear` / `summary`）调用搬移函数；**未改步骤顺序** |
| `test/oracle_preset_test.dart` | `setUp/tearDown` 增加 `legacyWeaponSkillMatchForOracle` 的存取（见下） |
| `test/p9_combat_skill_test.dart` | **新增**（28 组） |

未动（明确属于别人的文件）：`home_page` / `ai_create_page` / `random_create_page` / `create_flow_page` /
`steps/**` / `theme` / `art` / `card_edit/combat_logic.dart`。

---

## 七、老测试改动与理由（只有一处）

`test/oracle_preset_test.dart`：`setUp` 里把 `legacyWeaponSkillMatchForOracle` 置 true，`tearDown` 还原。

理由：这条测试的职责是**逐字证明「Dart 移植 == 旧版 core/preset.js」**，比对的是整张卡的 JSON。
旧版 `weaponCombatSet` 本身就是「原样字符串比对」的错配实现，P9 修掉它之后，带剑/鞭/绞具/投掷的卡
必然与冻结 fixture 不同 —— 不是移植错了，而是**生产口径有意改了**。

做法照抄本仓库既有的 `ai_caps.dart#legacyAttrCapForOracle` 双路径办法：
- 冻结 fixture **一个字节都不改**（没有削弱任何期望值）；
- 生产默认走新映射；只有预言机测试打开旧口径；
- 新口径的正确性由 `p9_combat_skill_test.dart` 的 4 组 preset 用例守（含连跑 20 次的抗抖动用例）。

没有删除任何测试、没有放宽任何断言。

---

## 八、已知边界

- **本职强制战斗技能不会被清**：若职业本身要求「格斗（斧）」，即使角色只带指虎，它在职业点上仍然有点
  （需求明确：本职属于职业设定）。这条只约束**额外分配**（兴趣点 / 预支）。
- 极端场景（所有非战斗技能都封顶）会允许点数回流闸门外的战斗技能，否则「点数必须用完」的硬约束会挡住保存。
  正常卡（50+ 非战斗技能）走不到。
- `lib/ui/card_edit/combat_logic.dart` 的展示层别名表未改动（不在允许清单内），两者一致性由测试锁死；
  若后续把该表迁到 domain，`p9_combat_skill_test.dart` 的「逐条一致」用例可以保证迁移不出偏差。
