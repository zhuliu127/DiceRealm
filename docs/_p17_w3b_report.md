# P17 波3-B / KP-3 对抗改造 · 施工报告（v2.30.0）

> worker：p17-w3b（Flutter 工程师「寇豆码」）
> 独占文件：`lib/ui/room/sheets/sheet_opposed.dart`、`lib/domain/room_model_actions_combat.dart`
> 依据：`_p17_construction_spec.md` §0/§1/§2-KP-3/§4/§6-Q2、`_p17_kp_landing.md` KP-3 节、`_p17_oldapp_research.md` B1/B2/B3/B4/B5/B6
> 时间：2026-11-14

---

## 0. 一句话结论

KP-3 已按 Q2 拍板落地：**通用对抗 / 攻击对抗（玩家武器自动带技能 + 怪物反击·闪避用检定等级 + 反击伤害骰式）/ 裁定 / 选伤害目标** 四条链路全部对齐老 APP 字段名；「武器对抗」入口删除但 `INTENT.OPPOSED` 与 domain `opposed()` 链路完整保留；反击·闪避的判定**没有复制一行规则**，全部由 `CocRules.resolveAttack` / `_opposedAttack` 权威执行（已用两轮纯 Dart 探针逐格验证）；两个文件 `dart analyze` 零问题；未跑 `flutter test`、未改任何既有测试。

---

## 1. 逐项落点（行号 = 改动后文件；含 sha256）

### 1.1 文件哈希

| 文件 | 行数 | sha256 |
|---|---|---|
| `lib/ui/room/sheets/sheet_opposed.dart` | 813 | `b59bcb0d482380c971a7ae6f2ee79d5742205579d25279722e097f6082a1f0c4` |
| `lib/domain/room_model_actions_combat.dart` | 3086 | `d288085d1d211a4aaa1ab8c444c862bbf5225ecded66cf348d2451602d66d37d` |

（基线：`sheet_opposed.dart` 402925d8…，255 行；`room_model_actions_combat.dart` b641991e…，2933 行。）

### 1.2 `lib/domain/room_model_actions_combat.dart` 落点

| # | 行段 | 内容 | 关键片段 |
|---|---|---|---|
| D1 | **1537–1608**（新增） | `opposedDeclaredLevelSpec(levelRaw)`：把「KP 判定的防守方检定等级」折成权威检定能吃的 `{base, roll}` | `case 5: {'level':5,'base':100,'roll':1}` / `case 2: {'base':100,'roll':51}` / `case 0: {'base':1,'roll':2}` / `case -1: {'base':1,'roll':96}` |
| D2 | **2024–2027** | `opposedCheckPayload` 取 `defender['declaredLevel']` 作展示开关 | `final declaredLevel = defender['declaredLevel']; final declared = declaredLevel != null;` |
| D3 | **2036 / 2038–2041** | 结果卡文案：KP 判定时写「（KP 判定）」而不是假骰值 | `'${noDefense || declared ? '' : ' ${jsStr(defender['value'])}'}'`、`s += declared ? ' vs 守方 $dLevelText（KP 判定）' : ' vs 守方 $dLevelText（掷 …）'` |
| D4 | **2088–2098** | 载荷 `b` 块：KP 判定时 `value=null` + 新增 `declaredLevel` | `'value': declared ? null : (…)`、`if (declared) 'declaredLevel': declaredLevel,` |
| D5 | **2197–2205** | 防守方等级探测（向后兼容门） | `final declaredSpec = opposedDeclaredLevelSpec(asMap(p['defender'])['level']); final declared = declaredSpec['ok'] == true && asMap(p['defender'])['side'] != 'pc';` |
| D6 | **2238–2258** | `fromRequest`（裁定玩家申请）分支新增 `else if (declared)`，不再要求 1–100 | `'value': declaredSpec['base'], 'roll': declaredSpec['roll'], 'declaredLevel': declaredSpec['level'],` |
| D7 | **2259–2273** | 原 1–100 校验的报错文案补上「或直接选择反击 / 闪避的检定等级」（无 level 时行为不变） | `'请为「$dname」输入 1–100 的对抗值，或直接选择…'` |
| D8 | **2284–2306** | KP 直发攻击对抗新增 `else if (declared)`（怪物 / NPC 防守方同样用等级；`actorId` 缺省按名字回查战斗槽） | `'skill': reaction == 'counter' ? '反击' : '闪避'` + `'level'` 代表值 |
| D9 | **2318–2337**（新增） | 反击伤害骰式校验：**复用 `rules.parseExpr`**，空值沿用老 APP 默认 `1D3`，非法明确报错 | `if (rules == null || rules!.parseExpr(useExpr)['ok'] != true) { … '反击伤害骰式无法解析「$useExpr」（支持 2D6+D4+1 这类加减组合）' }` → `counterDmg = {'expr': useExpr, 'db': '0'}` |
| D10 | **2399–2413** | 把「代表骰值」与「反击伤害式」送进权威结算 | `'roll': defender['roll'],` / `'damage': ?counterDmg,` |

**没有改的地方（一个字都没动）**：
- `dispatchCombatAction` 1–115（含 `combat.set` 29–32、`combat.next` 35–36、`combat.attack` 45–46、`opposed` 107–108）
- `combatStart` 170–313、`combatActor` 315–470、`combatDamage` 471–525、`combatAttack` 526–781、`combatEnd` 782+
- `checkOpposed` **通用分支** 1611–1704（`aSeat/aSkill/aBase/bSeat/bSkill/bBase` 原本就吃这些字段，本次只补 UI）
- `resolveActorSkill` 1707–1789（**没有加 `pc:` 前缀**，仍是 `p:`/`a:`/`mo:`）
- `findActorSlot` 1791 / `skillBaseOf` 1817 / `findCombatSlot` 1831 / `findCombatSlotByName` 1841 / `matchSheetWeapon` 1867
- `opposed()` 2593 / `opposedPlayerRequest` 2617 / `opposedPlayerTarget` 2732（**玩家战斗对抗链路完整保留**）
- `emitOpposedCheck`（secret 1:1 落地，本批未施工）、`sceneCheck*` 2851+

### 1.3 `lib/ui/room/sheets/sheet_opposed.dart` 落点

| # | 行段 | 内容 |
|---|---|---|
| U1 | 36–97 | `OpposedSheetKeys`：既有常量（`root/general/attack/weapon/resolve/target/reqId/targetId/reqBase/targetBase`）**全部保留原值未改名**；新增 `aSeat/aSkill/aBase/bSeat/bSkill/bBase`、`attacker/attackerWeapon/attackerSkill/attackerBase/attackerDamage/defender/defenderSkill/counterDamage/armor/resolveCounterDamage/resolveArmor`、`reaction(scope,r)`、`level(scope,lv)`、`weaponOption(i)` |
| U2 | 100–123 | 等级六档常量 + `opposedLevelText()`（与 `CocRules.LEVEL_TEXT` 同文案） |
| U3 | 265–322 | ① 通用对抗：甲/乙 `UnitPickerField` + 两个技能文本框（默认 `格斗`/`闪避`）+ 无卡单位 1–100 对抗值 + 提交按钮（**key 仍是 `RoomKeys.action('check.opposed')`**） |
| U4 | 324–402 | ② 攻击对抗：攻击方 →（玩家）武器下拉 /（无卡）技能+对抗值+伤害式；防守方 →（玩家）技能框 /（无卡）反击·闪避 + 检定等级 +（反击）伤害骰式；护甲；提交按钮 `OpposedSheetKeys.attack` |
| U5 | 404–442 | ③ 裁定申请：保留 `reqId` picker（`UnitPickerField`、`allowAll:false`）+ 反击/闪避 + 检定等级 + 反击伤害式 + 护甲；`OpposedSheetKeys.resolve` 保留 |
| U6 | 444–462 | ④ 选伤害目标：保留 `targetId` picker + `OpposedSheetKeys.target`（`kpOpposedCanApply` 闸门不变） |
| U7 | 504–552 | `_weaponField` + `_pickWeapon`：武器列表取 `mem.sheet.weapons`（老 APP `mem.sheet.weapons` 同源），标签带 `伤害 / 贯穿 / 技能` |
| U8 | 554–589 | `_reactionRow`：**反击（同级攻方胜）/ 闪避（同级免伤）** 二选一 |
| U9 | 591–625 | `_levelRow`：六档检定等级（大成功/极难/困难/常规/失败/大失败），**取代原 1–100 输入框** |
| U10 | 627–654 | `_submitGeneral` → `check.opposed {aSeat,aSkill,aBase?,bSeat,bSkill,bBase?}`：**删掉 `kind:'general'` 与裸 `base`**；有卡单位绝不塞 base（技能值只能由权威端从卡取，查不到要报错） |
| U11 | 656–756 | `_submitAttack` → `check.opposed {attack:true, attacker, defender, weapon, armor, shots}` |
| U12 | 758–781 | `_submitResolve` → `check.opposed {reqId, attack:true, defender:{reaction,level,damage}, armor}`；`reqId` 优先取 `state.opposed.id`（真源），无待办时回落选中值（保持既有测试口径） |
| U13 | 783–800 | `_submitTarget` → `INTENT.opposed {phase:'target', targetId}`，**targetId 用 `unitValueToSeat` 剥前缀**（domain 只认裸 actorId） |

**已删除**：`sheet_opposed.dart` 原 144–153 的独立「武器对抗」按钮（`sendIntent(RoomIntent.opposed,{phase:'apply'})`）—— `OpposedSheetKeys.weapon` 常量保留但**不再渲染**，波4 可用 `find.byKey(OpposedSheetKeys.weapon) == findsNothing` 反向钉住。

**同时删除（必须报备，理由见 §6）**：原 134–143 的 `combat.attack {phase:'apply'}` 快捷按钮 —— 它与「攻击对抗」语义重复且载荷不完整（无 targetId/weapon，点下去会打出一条「对着空气攻击」的公共日志）。攻击对抗改走老 APP 口径 `check.opposed {attack:true}`。

---

## 2. 载荷对照表（四种场景 + 两条衍生链路）

> 全部字段名逐字对齐 `_p17_oldapp_research.md` B5 表；`p:`/`a:` 前缀只用于通用对抗的 `aSeat/bSeat`（`resolveActorSkill` 支持），
> 攻击对抗的 `seat` / `actorId` 一律是**裸值**（`resolveOpposedSide` / `findCombatSlot` 只认裸值）。

### ① 通用对抗（KP 直发，`check.opposed`）

```jsonc
{
  "op": "check.opposed",
  "aSeat": "p:p1",        // UnitPickerField value（p:<seat> / a:<id>），★ 保留前缀
  "aSkill": "斗殴",       // 纯文本；权威端 4 档归一 + 16 条别名自动取卡值
  // "aBase" 只在无卡单位（怪物/NPC）时出现，1–100 整数
  "bSeat": "a:m1",
  "bSkill": "格斗",
  "bBase": 50
}
```
- 玩家侧：`aBase`/`bBase` **不出现** → `skillBaseOf → rules.skillValue → _skillValue` 取卡值；查不到 → domain 明确报错。
- 无卡侧：必须带 1–100，UI 已本地拦截（否则 domain 会按 0 结算）。

### ② 攻击对抗 —— 玩家武器

```jsonc
{
  "op": "check.opposed", "attack": true,
  "attacker": {"side": "pc", "seat": "p1", "name": "调查员", "skill": "斗殴", "ranged": false},
  "defender": {"side": "monster", "actorId": "m1", "name": "怪物",
               "skill": "闪避", "reaction": "dodge", "level": 2},
  "weapon":   {"name": "黄铜指虎", "skill": "斗殴", "damage": "1D3+1",
               "pierce": "×", "perRound": "1", "db": "0"},
  "armor": {"value": 0},
  "shots": 1
}
```
- `attacker.skill` = **所选武器的 `skill` 字段**（老 APP `data/weapons.js` 同源，如「弓箭→弓」「黄铜指虎→斗殴」）；UI 不做任何反查，`attacker.value` 不传（由 `resolveOpposedSide → skillBaseOf` 读卡）。
- `weapon.db` 取该玩家人物卡的 `db`（老 APP `me.sheet.db`）。

### ③ 攻击对抗 —— 怪物反击（检定等级 + 伤害骰式）

```jsonc
"defender": {"side": "monster", "actorId": "m1", "name": "怪物",
             "skill": "反击", "reaction": "counter",
             "level": 3,                     // 困难成功（5/4/3/2/0/-1）
             "damage": "2D6+D4+1"}           // 反击命中时的伤害骰式
```
- 伤害 `applied = max(0, raw - armor)`；反击胜的伤害打在**攻击方**身上（`room_model_actions_combat.dart:2461-2469`）。

### ④ 攻击对抗 —— 怪物闪避

```jsonc
"defender": {"side": "monster", "actorId": "m1", "name": "怪物",
             "skill": "闪避", "reaction": "dodge", "level": 4}
```
- 闪避胜 / 落空 → `damage = null`，不扣血（`resolveAttack` 直接给 `outcome=miss`）。

### ⑤ 裁定玩家申请（`reqId` 链路）

```jsonc
{"op": "check.opposed", "reqId": "op3", "attack": true,
 "defender": {"reaction": "dodge", "level": 3},
 "armor": {"value": 0}}
```

### ⑥ 玩家胜后选伤害目标（`INTENT.OPPOSED`）

```jsonc
{"op": "opposed", "p": {"phase": "target", "targetId": "m1"}}   // 裸 actorId
```

### 玩家当防守方（少数派，仍支持）

```jsonc
"defender": {"side": "pc", "seat": "p2", "name": "乙", "skill": "闪避", "reaction": "dodge"}
// 不带 level：检定由权威端掷骰（技能值从卡取）
```

---

## 3. 反击 / 闪避的判定式在 domain 的落点（**没有复制规则**）

| 规则 | 落点（复用，未新增） |
|---|---|
| 攻击方检定（不可推动、花不了幸运） | `_resolveAttack` ① `room_rules_combat.dart:154-167` |
| **防守方等级 = KP 判定值** | 本批新增 `opposedDeclaredLevelSpec` 只做「等级 → 代表 base/roll」的**输入折算**；真正的等级判定仍是 `_check → _levelOf`（`room_rules_core.dart:116-131`） |
| **反击同级 → 攻方胜**（`mode_fightback_tie`） | `_opposedAttack` `room_rules_opposed.dart:140-148` |
| **闪避同级 → 攻方败/免伤**（`mode_dodge_tie`） | `_opposedAttack` `room_rules_opposed.dart:149-156` |
| 等级高者胜 | `_opposedAttack:122-139` |
| 同级比技能值 / 逐轮重掷 ≤10 轮 | `_opposedAttack:157-200`（KP 判定等级路径用不到：等级相同即由模式短路） |
| 攻方失败 → 落空；无人防御 → 纯命中；反击胜 → 防守方造成伤害；闪避胜 → 免伤 | `_resolveAttack:195-216` |
| 远程不能反击 → 强制按闪避 | `_resolveAttack:169-177` |
| 反击优先用**防守方**伤害式 | `_resolveAttack:223-229`（本批只是把 `defense.damage` 送进去） |
| `applied = max(0, raw - armor)` | `_resolveAttack:251-270` |
| 反击命中伤害打在**攻击方** | `opposedAttackResolve:2461-2469`（既有实现） |

**唯一新增的「规则性代码」是 D1 那张 `level → {base, roll}` 折算表**，它不判胜负、不碰阈值公式，只把 KP 的声明翻译成规则层已有的入参形状；已用探针逐档验证 `CocRules.check(base, roll).level == 声明等级`（见 §7）。

---

## 4. 伤害骰式解析：复用既有实现，未新增解析器

- **复用了什么**：`RoomRulesPort.parseExpr` / `CocRules.parseExpr`（`lib/domain/room_rules_expr.dart:24-103`，经 `room_rules.dart:174` 暴露）。
- **支持语法**：`NdM`、纯数字，以及它们的**加减组合**（`1D6+1`、`2D6+D4+1`、`2D10-1`）；不支持乘除与括号。
- **上限保护（现成，非本批新增）**：`MAX_DICE = 100`（`CocRules.limits`）、`MAX_SIDES = 1000`、单项常数 `≤ 10000`；越界直接 `{ok:false, reason:…}`。所以 `9999D9999` 会被拒绝（探针 ⑤ 已实测报错文案）。
- **落点**：`room_model_actions_combat.dart:2318-2337`（`declared && reaction=='counter'` 时校验 `p['defender']['damage']`，接受 `String` 或 `{expr}` 两种写法，空值沿用老 APP 默认 `1D3`，非法则 `sysTo` 明确报错并中止结算）。
- **UI 侧不做语法校验**（`sheet_opposed.dart` 零规则调用），错误由权威端回显给 KP —— 避免在 UI 里复制第二份解析器。

---

## 5. 给 W3-D 的「已占用行段清单」（`room_model_actions_combat.dart`）

> 我从 2933 行改到 3086 行，**以下行段请视为已占用**（W3-D 改 `combat.set` / order 重排路径时请避开，或在我之后串行）。行号为**当前文件**行号。

**已占用（我改过，别并发动）**
```
1537–1608  新增 opposedDeclaredLevelSpec（插在 checkOpposed 之前）
2024–2027  opposedCheckPayload 声明等级开关
2036        opposedCheckPayload 头部文案
2038–2041  opposedCheckPayload 守方等级文案
2088–2098  opposedCheckPayload 的 'b' 块
2197–2205  opposedAttackResolve 起始处的 declared 探测
2238–2258  fromRequest 防守方 declared 分支
2259–2273  同分支的 1–100 报错文案
2284–2306  KP 直发防守方 declared 分支
2318–2337  反击伤害骰式校验（counterDmg）
2399–2413  args['defense'] 增加 roll / damage
```

**完全没动（W3-D 可安全施工）**
```
1–115      dispatchCombatAction（含 combat.set 29–32、combat.next 35–36）
116–168    战斗常量/兜底工具（initiativeFallback 等）
170–313    combatStart（含 initiativeOrder 生成）
315–525    combatActor / combatDamage
526–781    combatAttack（快捷攻击，未改）
782–1318   combatEnd / 战斗辅助 / applyMalfunction
1319–1536  checkRequest 等
1611–1704  checkOpposed 通用分支
1707–1866  resolveActorSkill / findActorSlot / skillBaseOf / findCombatSlot*
1867–2010  matchSheetWeapon / isMyActionTurn / opposedDamagePlayer / opposedDamageMonster / forceAutoHit
2437–2592  opposedAttackResolve 的逐发循环体 + 暂存态（我只动了 2399–2413 的 args 字面量）
2593–2850  opposed() / opposedPlayerRequest / opposedPlayerTarget
2851–3086  sceneCheck* / playerSanCheck
```
> 结论：**KP-7 的 `combat.set`（29–32）+ order/turn/done 维护 + `nextTurn` 都在我的空白区，可以直接动**，与本次改动零重叠（唯一交集是 `opposedAttackResolve` 里的 args，但那只在 `declared` 分支生效）。若 W3-D 也要动 `opposedAttackResolve`，请先与我串行确认。

---

## 6. 需要波4 特别注意的两处「测试口径漂移」

### 6.1 ★ T-30 锚点表：`combat.attack` 失去唯一挂载点

- 现状：`combat.attack` 的**唯一** `act/combat.attack` 锚点原在 `sheet_opposed.dart:135`（那个发 `{phase:'apply'}` 的快捷按钮）。本批按老 APP 口径把它换成 `check.opposed {attack:true}`，该锚点消失。
- 影响：`test/room_ui_permission_test.dart`
  - `:325 expect(table.length, 30)` → 会变成 **29**；
  - `:350 noAnchor == kFrozenNoAnchor`（31 条）→ `combat.attack` 会多进来。
- 建议口径（**更强，不是放宽**）：把 `'combat.attack'` 加进 `kFrozenNoAnchor`（字母序放在 `'check.push'` 与 `'combat.enqueue'` 之间），把 `table.length` 断言改成 29，并保留 `noAnchor.length + table.length == 61`。理由写进测试注释：**攻击对抗已按老 APP 统一走 `check.opposed {attack:true}`，`combat.attack` 在 UI 上再无诚实挂载点（保留锚点等于给按钮挂一个它不再发送的 op）**。

### 6.2 `reqId` 语义（既有 bug，我做了兼容修补，没扩大爆炸半径）

- 事实：老口径 `check.opposed {reqId}` 要比对 `state.opposed.id`（`op<N>`），但 P16 把该字段改成了「选单位」下拉（value `p:<seat>`）→ 裁定永远报「该对抗申请已处理或不存在」（既有缺陷，非本批引入）。
- 我的处理：`_submitResolve` 里 **优先用 `state.opposed.id`**（真源），没有待办时才回落选中值。这样：有真实申请时裁定链路真的能跑通；无待办时载荷与旧行为逐字一致（`p16_wave1_sheets_test:442` 的 `req['reqId']=='p:p1'` 仍绿）。
- 若波4 想彻底正名：把「申请单位」下拉改成「显示当前待处理申请的发起人 + 只读」，并按 `state.opposed.id` 断言。

---

## 7. 自证（纯 Dart 探针，未跑 `flutter test`）

三段一次性探针（放 `/tmp`，跑完即弃，未入库），命令形如
`dart --packages=.dart_tool/package_config.json /tmp/w3b_*.dart`：

1. **等级折算逐档对拍**（`CocRules.check{base,roll}` → level）：
   `100/1→大成功`、`100/20→极难成功`、`100/50→困难成功`、`100/51→常规成功`、`1/2→失败`、`1/96→大失败` —— 与声明值**逐档相等**。
2. **`resolveAttack` 四结局**（攻方 base 60、掷 51 → 常规成功）：
   - 守方声明「常规成功」+ 反击 → `attacker_wins` / `decidedBy = mode_fightback_tie`（★反击同级攻方胜）；
   - 守方声明「常规成功」+ 闪避 → `miss` / `decidedBy = mode_dodge_tie` / `damage.applied = 0`（★闪避同级免伤）；
   - 守方声明「极难成功」+ 反击 + `2D6+D4+1` → `defender_wins` / `damageBy = defender` / 用**反击骰式**（不是武器骰式）/ 护甲 `max(0, raw-armor)` 生效；
   - 守方声明「极难成功」+ 闪避 → `miss`，不扣血。
3. **`RoomHost` 级端到端**（真 host + `CocRules`，直接喂 UI 产出的载荷）：
   - ① 通用对抗：`aSeat:'p:p1' / aSkill:'斗殴'` 解析成 `甲·斗殴`，`bSeat:'a:m1' / bBase:50` 解析成 `怪物·格斗`，产出标准 `check` 记录（`kind:'opposed'`）；
   - ② 玩家武器 → 怪物闪避（等级 2）同级：`winner=b` / `mode_dodge_tie` / 怪物 HP 20→20；载荷 `b.value=null`、`b.declaredLevel=2`、摘要「守方 常规成功（KP 判定）」；
   - ③ 反击同级：`winner=a` / `mode_fightback_tie` / 伤害 `3 raw − 2 armor = 1` → 怪物 20→19；
   - ④ 反击（大成功）+ `2D6+D4+1`：`raw 12`、`applied 12` → **玩家** HP 12→0（伤害打攻击方）；
   - ⑤ `damage:'9999D9999'` → `sysTo`「反击伤害骰式无法解析「9999D9999」（支持 2D6+D4+1 这类加减组合）」且不结算；
   - ⑥ 裁定链路（`reqId:'op1'` + 闪避 困难）→ `winner=b`/`level`、怪物 HP 不变、`state.opposed` 清空；
   - ⑦ 裁定链路（反击 大成功 + `2D6+D4+1` + 护甲 1）→ `raw 12 − 1 = 11` → 玩家 12→1；
   - ⑧ 缺 `level` 且缺 `value` → 仍回老文案「请为「怪物」输入 1–100 的对抗值，或直接选择反击 / 闪避的检定等级」（**向后兼容未破**）。

---

## 8. 给波4 的验收用例口径（6 条）

| # | 用例 | 步骤 | 断言（要咬得住） |
|---|---|---|---|
| ① | **通用对抗载荷逐字段** | KP 弹层：甲=`p:p1`、甲技能 `斗殴`、乙=`a:m1`、乙技能 `格斗`、乙对抗值 `50` → 点「发起通用对抗」 | `lastSent(action:'check.opposed')['p']` 的键集合 == `{aSeat,aSkill,bSeat,bSkill,bBase}`；`aSeat=='p:p1'`（**保留前缀**）、`aSkill=='斗殴'`、`bBase==50`；**`kind` 不存在、裸 `base` 不存在**；再补一条「甲方是玩家时 `aBase` 键不存在」 |
| ② | **攻击对抗-玩家武器 → 技能自动带出** | 选攻击方 `p:p1` → 点武器下拉 → 选「黄铜指虎」→ 选防守方 `a:m1` → 反击/闪避=闪避 → 点「发起攻击对抗」 | `p['attack']==true`；`p['attacker'] == {side:'pc', seat:'p1', skill:'斗殴', …}`（`skill` 来自武器，不是手填）；`p['weapon']['damage']=='1D3+1'`、`p['weapon']['db']` == 人物卡 db；`p['attacker']` 里**没有** `value` |
| ③ | **怪物反击（含骰式伤害）** | 同上，防守方选「反击」+ 等级「困难成功」+ 骰式 `2D6+D4+1` | `p['defender'] == {side:'monster', actorId:'m1', skill:'反击', reaction:'counter', level:3, damage:'2D6+D4+1'}`；`p['armor']['value']` 是数字 |
| ④ | **怪物闪避（免伤）** | 防守方选「闪避」+ 等级「极难成功」 | `defender.damage` **不存在**；`defender.level==4`；domain 结果 `outcome=='miss'`、`damage==null`、目标 HP 不变 |
| ⑤ | **反击同级攻方胜 / 闪避同级免伤** | domain 级（`RoomHost` + 固定 rng 让攻方掷 51/base60 = 常规成功）：<br>a) defender `{reaction:'counter', level:2}` → `winner=='a'`、`decidedBy=='mode_fightback_tie'`、伤害落在防守方<br>b) defender `{reaction:'dodge', level:2}` → `outcome=='miss'`、`decidedBy=='mode_dodge_tie'`、`applied==0` | 两条都要**同时**断言 `decidedBy` 字面量与 HP 变化方向（P16 教训：只断 outcome 会被 fallback 蒙过去） |
| ⑥ | **武器对抗入口 findsNothing 但 `opposed()` 链路仍在** | 弹层内 `find.byKey(OpposedSheetKeys.weapon)` → `findsNothing`；静态扫 `sheet_opposed.dart` 不含 `label: '武器对抗'`；同时 domain 断言 `h.opposed('p1', sheet, RoomRole.player, {phase:'request', weapon:{name:'黄铜指虎'}, targetId:'m1'})` 仍能建 `state.opposed`（`phase=='await_kp'`） | 三者缺一不可：**入口删了、链路没删** |

---

## 9. 预计转红的既有测试 + 建议口径

| 测试 | 现在 | 为什么红 | 建议口径（更强或等价） |
|---|---|---|---|
| `test/room_ui_kp_test.dart:963-1012`（对抗弹层 ACT 入口） | 点 `RoomKeys.action('check.opposed')` 直接断言 `lastSent(action:'check.opposed') != null` | 弹层现在**必须有甲乙双方**才发包；空表单只 `ctl.notice('请先选择通用对抗的甲方与乙方单位')` 并 return | 拆成两条：**甲**「空表单点下去 → `lastSent==null` 且 `notice` 含『请先选择』」（更强）；**乙**「先 tap `OpposedSheetKeys.aSeat`→`unitPicker/p:p1`、`bSeat`→`unitPicker/a:m1`，再点 → `lastSent` 的 `aSeat=='p:p1'`、`bSeat=='a:m1'`、无 `kind`」。保留 `enabled == gate.can('check.opposed')` 原断言 |
| `test/room_ui_permission_test.dart:325 / :350`（T-30 锚点表） | `table.length == 30`、`kFrozenNoAnchor` 31 条 不含 `combat.attack` | `combat.attack` 唯一锚点被删（见 §6.1） | 30→29；`kFrozenNoAnchor` 加 `'combat.attack'`；保留 `noAnchor.length + table.length == 61` |
| `test/p16_wave1_sheets_test.dart:290-318` | 两处 `UnitPickerField`（`allowAll:false`）+ `resolve`/`target` 存在 + `reqId/targetId` 不是 TextField | **本批仍绿**（全部保留） | 无需改；可**加**一条 `find.byKey(OpposedSheetKeys.weapon)` findsNothing（对应验收⑥） |
| `test/p16_wave1_sheets_test.dart:420-471`（选单位后的载荷） | `reqId=='p:p1'`、`attack==true`、`target.enabled==false` | **本批仍绿**（无 pending 时 `reqId` 回落选中值） | 无需改；建议**加**「通用对抗甲乙两方载荷」独立用例（验收①），以及「`targetId` 必须剥成裸 actorId」断言 |
| `test/p10_t6_room_fixes_test.dart:399-410`（KP 点对抗 → 开弹层、零空 action） | 点的是**骰子条**的锚点（`gp_dice_bar.dart:430`），不是弹层内按钮 | **本批仍绿** | 无需改 |
| `test/room_intent_dice_wiring_test.dart:308-360`、`test/p10_t3b_rule_diff_test.dart:145`、`test/qa_p10_4_verify_test.dart:185` | domain 级通用对抗对拍 | **仍绿**：`checkOpposed` 通用分支一行未改 | 无需改 |
| `test/room_rules_oracle_test.dart` + `test/fixtures/room_{model,actions}.json` | 逐字节契约 | **仍绿**：`resolveAttack` / `_check` / `_opposedAttack` 未改；新增只在 `defender.level` 存在时生效（fixture 无此键） | 无需改 |
| `test/room_ui_kp_test.dart:1116-1148`（T04 门禁） | 禁用串 `RoomHost`/`rules?.check(`/`rollExpr(`/`opposedFull(`/`plBottomBar`/`plFeeds`/`kpChat`/`kpGameLog` + `state[...]=` 赋值 | **仍绿**（已逐串 grep 核对，全为 0 命中） | 无需改 |
| `test/p16_button_unify_test.dart:207/384/406` | 骰子条 8 键尺寸统一 | **仍绿**（改的是弹层，不是骰子条） | 无需改 |

> 除 T-30 那一条（`combat.attack` 锚点迁移，属产品行为真变）外，**没有其他必须改的既有断言**。

---

## 10. 声明

- 未跑 `flutter test`（并发期禁止）；静态自检只用 `dart analyze`：`lib/ui/room` + `lib/domain` 全绿，两个独占文件 **No issues found**。
- 未运行 `flutter clean`；未改 `pubspec.yaml` / `pubspec.lock` / `app_version.dart`；未新增/修改任何 `test/**`（探针脚本在 `/tmp`，不在工程内）。
- 未改冻结文件：`room_rules_combat.dart`、`room_rules_sheet.dart`、`room_rules.dart`、`room_ports.dart`、`room_types.dart`（`kRoomPolicy` 仍 61 条）、`unit_picker.dart`、`skills.dart` / `occupations.dart`、`fixtures/**`、`oracle_*`。
- 未新增 domain action；未新增技能反查；未给 `resolveActorSkill` 加 `pc:` 前缀。
- `lib/ui/room/**` 零 emoji（代理对 U+1F300–1FAFF 命中 0）、新代码零 `jsStr(`（该文件 grep 为 0）。
- 未碰他人文件集（`gp_combat_list.dart` / `gp_combat_strip.dart` 等一律未动）。
- `secret` 秘密对抗按施工单**不施工**，仅登记（domain 侧 1:1 已落地，UI 未加复选框）。
