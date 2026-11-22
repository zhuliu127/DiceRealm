# P17 波3-C · KP-6 定向指令补输入（施工报告）

- 组：**W3-C**（文件集：`lib/ui/room/sheets/sheet_kp_directives.dart` + **2026-11-14 追加** `lib/domain/room_model_actions_sheet.dart`）
- 版本口径：v2.30.0（版本号由波4 总装改，本组未碰 `pubspec.yaml` / `app_version.dart` / `pubspec.lock`）
- 源码 SHA256（交付时点）：

```
2da60bf1014aa9c4085884054df522b1f505f6588187ddf6e5b060c5cfa15edc *lib/ui/room/sheets/sheet_kp_directives.dart
d67ed14dbcff7995f2a0a0b373952f0facbd7f4ae31b2998d178d000334d342f *lib/domain/room_model_actions_sheet.dart
```
大小 29592 字节 / 776 行（UI）、81888 字节（domain）。

- `dart analyze lib/ui/room/sheets/sheet_kp_directives.dart lib/domain/room_model_actions_sheet.dart` → **No issues found!**
- 门禁自检：UI 文件 `lib/ui/room/**` **零 emoji**（代理对 U+1F300–1FAFF 命中 0）、**零 `jsStr(`**（命中 0）。
- ⚠️ **2026-11-14 裁决已落地**：`aid.apply` / `aid.psycho` 各补可选「检定数值」`base`（用户口径 > 老 APP），domain 侧改成**条件性覆盖**，老载荷路径逐字不变（证据见 §8）。

---

## 1. 交互形态（为什么不是一个长表单）

保留原有两步骨架（**选指令 → 选目标行**），中间插入一张**只属于当前指令**的小表单：

```
[定向指令（8 项）]  ← Wrap 按钮（key 仍是 RoomKeys.action(op)）
[填写参数 · <按钮名>] ← 仅 kKpFormOps 里的 6 项渲染；其余 3 项无输入，不出现这一块
[目标 · <op>]        ← 每行「执行」= 确认（先校验表单，通过了才发包）
```

- 一次只在屏幕上出现**一张**表单，点别的指令立刻换掉；不存在「9 项塞一个长表单」。
- 表单草稿存在 `State` 的 `TextEditingController` 里（与 `sheet_dice_tools.dart` / `sheet_add_actor.dart` 同范式）。`showRoomSheet` 的 body 会被 `refreshTopSheet` 整体重建，草稿在 State 里因此不丢。
- 目标行 `「执行」` 按钮就是**确认按钮**，key 沿用 P16 的 `kpDirective/target/<op>/<seat>`（`room_ui_kp_test.dart:898` 已钉死该形态），字符串逐字未变，只是收敛成工厂方法 `KpDirectiveKeys.targetConfirm(op, seat)`。

---

## 2. 逐按钮落点表（按钮 → 表单 → 载荷字段 → key）

源码行号均指 `lib/ui/room/sheets/sheet_kp_directives.dart`。

| # | 按钮 | op | 表单字段（Key） | 载荷字段 | 确认 key |
|---|---|---|---|---|---|
| 1 | 造成伤害 | `sheet.damage` | 伤害值 `KpDirectiveKeys.damageAmount`（`kpDirective/damage/amount`，数字键盘+digitsOnly，默认 `1`，≤4 位）<br>伤害类型 `damageKind`（`kpDirective/damage/kind`，132dp，≤20 字，可空） | `{seat, amount:int, kind:string}` | `targetConfirm('sheet.damage', seat)` |
| 2 | 临时状态 | `sheet.tempstatus` | 临时状态 `tempStatusText`（`kpDirective/temp/text`，整行，≤60 字，占位「如：中毒 3 轮 / 流血」） | `{seat, text}` | `targetConfirm('sheet.tempstatus', seat)` |
| 3 | 给物品 | `sheet.item` | 数量 `itemQty`（`kpDirective/item/qty`，88dp，digitsOnly，默认 `1`，≤4 位）<br>物品名 `itemName`（`kpDirective/item/name`，176dp，≤40 字）<br>备注 `itemNote`（`kpDirective/item/note`，整行，≤60 字） | `{seat, name, qty:int, note}` | `targetConfirm('sheet.item', seat)` |
| 4 | SAN Check | `sheet.sancheck` | 成功损失 `sanCheckOkLoss`（`kpDirective/san/okLoss`，116dp，默认 `0`，≤12 字）<br>失败损失 `sanCheckLoss`（`kpDirective/san/loss`，116dp，默认 `1D6`，≤12 字）<br>原因 `sanCheckReason`（`kpDirective/san/reason`，整行，≤40 字） | `{seat, okLoss, loss, reason}` | `targetConfirm('sheet.sancheck', seat)` |
| 5 | 急救/医学 | `aid.apply` | 技能二选一 ChoiceChip：`KpDirectiveKeys.aidSkill('急救')` / `aidSkill('医学')`（`kpDirective/aid/skill/急救`、`…/医学`，默认「急救」）<br>检定数值 `KpDirectiveKeys.aidBase`（`kpDirective/aid/base`，152dp，digitsOnly，≤3 位，**可留空** = 由角色卡技能值自动取） | `{seat, targetSeat, skill:'急救'|'医学'[, base:int]}` | `targetConfirm('aid.apply', seat)` |
| 6 | 精神分析 | `aid.psycho` | 检定数值 `KpDirectiveKeys.aidBase`（`kpDirective/aid/base`，152dp，digitsOnly，≤3 位，**可留空**） | `{seat, targetSeat[, base:int]}` | `targetConfirm('aid.psycho', seat)` |
| 7 | 治愈疯狂状态 | `madness.cure` | 无表单（系统自动判定） | `{seat}` | `targetConfirm('madness.cure', seat)` |
| 8 | 治愈重伤 | `sheet.healwound` | 无表单（系统自动判定） | `{seat}` | `targetConfirm('sheet.healwound', seat)` |
| 9 | SAN 大失败追加 | `sheet.sanloss` | 无表单（Q4：只追加最近一次） | `{seat, dice:'1D10'}` | `targetConfirm('sheet.sanloss', seat)` |

其它稳定 key：

- `KpDirectiveKeys.formError` = `kpDirective/form/error`（校验失败提示，无提示时不渲染）。
- `KpDirectiveKeys.aidBase` = `kpDirective/aid/base`（急救/医学与精神分析**共用**同一个 key：两个指令的表单互斥渲染，树里同时只有一个）。
- 列表 / 表单相关：`kKpDirectives`（8 项，`:60`）、`kKpRemovedDirectiveOps`（`:79`）、`kKpExtraDirectives`（1 项，`:106`）、`kKpFormOps`（6 项，`:117`）、`kpDirectivePayload(op, seat, {form})`（`:164`）、`KpDirectiveKeys`（`:249`）、`_validate`（`:352`）、`_draftFor`（`:390`）、`_form`（`:479`）、`build`（`:650`）、`_targetList`（`:707`）。

### 输入校验（空 / 非法 → 只提示，不发包）

| 指令 | 规则 | 提示文案 |
|---|---|---|
| `sheet.damage` | `amount` 必须是 1–9999 的整数（digitsOnly 已挡非数字，仍二次判空/越界） | 伤害值必须是 1–9999 的整数 |
| `sheet.tempstatus` | `text` 去空格后非空 | 临时状态内容不能为空 |
| `sheet.item` | `name` 非空；`qty` 1–9999 整数 | 物品名不能为空 / 数量必须是 1–9999 的整数 |
| `sheet.sancheck` | `okLoss`、`loss` 各自必须是「纯数字或可解析骰式」 | 成功损失要填数字或骰式（如 0、1D6）/ 失败损失要填数字或骰式（如 1D6、1D10） |
| `aid.apply` / `aid.psycho` | `base` **可留空**；填了必须是 1–999 的整数 | 检定数值要留空或填 1–999 的整数 |

校验失败时只有 `KpDirectiveKeys.formError` 出现、`f.lastSent` 保持为空（不发包）。

### `kpDirectivePayload` 的兼容性

签名改为 `kpDirectivePayload(String op, String seat, {Map<String,Object?> form = const {}})`——**只加可选命名参数**，不传 `form` 时按各字段「最小合法值」回落，因此既有调用点（`room_ui_kp_test.dart:873` 之类）行为与 P17 之前一致，绝不发出缺字段载荷。

`base` 走的是**条件性加键**：`if (form['base'] != null) 'base': form['base']`——表单留空时 `_draftFor` 根本不产生 `base`，所以老载荷形状 `{seat, targetSeat, skill}` / `{seat, targetSeat}` 逐字不变。

---

## 3. 删掉的两个按钮（与新口径）

| 删的条目 | 原位置 | 新口径（功能去处） |
|---|---|---|
| 暗骰 `dice.dark` | 原 `kKpDirectives` 第 5 项（`kKpDirectives:44`） | 工具栏 / 骰子工具弹层已有入口（`sheets/sheet_dice_tools.dart:226` 仍挂 `RoomKeys.action('dice.dark')` 锚点），本弹层重复 |
| 请求修改状态 `state.request` | 原 `kKpExtraDirectives` 第 2 项（`kKpExtraDirectives:76`） | 玩家「申请修改状态」会直接弹窗；`state.request` 的 UI 锚点仍在 `sheets/sheet_scene.dart:364` |

- 两项 op 记录在 **`kKpRemovedDirectiveOps`**（`:75`），注释写明「P17 起本弹层不再渲染」。
- **key 常量无需保留也不会断**：本弹层从来没有 `KpDirectiveKeys` 之外的 key 常量，两个按钮的 key 一直由工厂 `RoomKeys.action(op)`（`room_keys.dart:90` → `ValueKey('act/<op>')`）生成，删除条目不影响任何一个 key 的存在性——两个锚点在别的弹层里仍在。
- `kpDirectivePayload` 里 `dice.dark` / `state.request` 两个 `case` **保留**（注释标明「P17 起本弹层不再渲染，保留兼容」），外部按 op 取值不炸。
- `kKpConsentOps` **一行未动**（仍 5 项，含 `state.request`）：它是 domain「需其同意」语义名单，不是 UI 条目名单；动了会打红 `room_ui_kp_test.dart:815`（`kKpConsentOps.length == 5`），且语义上是错的。
- 排布不塌陷：按钮容器是 `Wrap(spacing:4, runSpacing:4)`，8 + 1 = 9 个 `RoomTap` 自动重排；`SectionBox` 高度由内容决定（`Column(mainAxisSize:min)`），无固定尺寸格。标题同步改成「定向指令（8 项）」。

---

## 4. Q4 拍板：SAN 大失败追加的实现选择与依据

**结论：复用现有 `sheet.sanloss{seat}`，不新增任何存储结构；UI 只需「选目标 → 执行」。**

依据（已 grep 确认，**没有**「最近一次 SC 大失败」记录可复用）：

| 候选字段 | 实际语义 | 能否复用 |
|---|---|---|
| `sheet.sanLoss`（`character.dart:191`、`engine.dart:116-124`、`room_model_actions_sheet.dart:299/476-478`） | **SAN 上限的永久减损量**（0–99），算 `maxSAN = baseMaxSAN − sanLoss` | ❌ 不是「这次大失败扣了多少」 |
| `sanHistory` / `pendingSan` / `lastSan` / `大失败记录` / 选「哪一次」 | 全库 0 命中（`_p17_oldapp_research.md:499-504` 亦同结论） | ❌ 不存在 |

→ 没有现成记录可直接取数值，故按老 APP 一键口径：载荷 `{seat, dice:'1D10'}`，权威端 `sheetSanLoss`（`room_model_actions_sheet.dart:1439`）读 `p['dice']` 后 `rollExpr` 掷 1D10 追加。显式带 `'1D10'`（而不是省掉让 domain 回落）是为了把「老 APP 一键掷 1D10」这条口径写在载荷里、可被波4 逐字段断言。

**未做**：不碰存档快照（`room_model_save.dart` 未读未改）、不新增 `meta`/`sheet` 字段、不加「选哪一次大失败」的二次弹层。

---

## 5. 骰式支持的结论

| 字段 | 结论 | 理由 |
|---|---|---|
| `sheet.damage.amount` | **只收整数**（digitsOnly + 1–9999 校验），不收骰式 | 权威端 `sheetDamage`（`room_model_actions_sheet.dart:1072-1074`）用 `raClampNumber(p['amount'],0,9999,0)`，骰式进来会被钳成 0 → 静默发一条「伤害值要大于 0」。老 APP 同样是 `parseInt(amtI.value,10)`。**改 domain 不在本组文件集**，故 UI 直接只收整数 |
| `sheet.sancheck.okLoss` / `loss` | **支持骰式**，复用 `CocRules.parseExpr` | 工程有现成纯函数：`lib/domain/room_rules_expr.dart:24` `_parseExpr` → 门面 `CocRules.parseExpr`（`room_rules.dart:190`，`const CocRules()`）。老 APP `validLossSide`（`room-panels.js:2053-2060`）判据同款「纯数字 or `R.parseExpr(t).ok`」。**没有另造解析器**，`parseExpr` 只在本地做语法校验，不掷骰、不碰状态，权威端 `parseSanLoss` 仍二次校验 |
| `sheet.sanloss` | 不收输入 | Q4：一键 1D10 |
| `aid.apply` / `aid.psycho` 的 `base` | **只收整数 1–999**，不收骰式 | 裁决新增项是「检定数值」，权威端 `rules.check({'base': …})` 要的是数值；骰式在这里没有语义（不是损失量） |
| `sheet.damage.kind` | 自由文本（≤20 字，可空），**不是下拉** | 老 APP 就是 `<input type=text>`（`kindI`，占位「如 物理/火焰」），工程内也无伤害类型枚举（grep `伤害类型`/`damageKind`/`物理` 均无伤害分类表）。硬造一套下拉会与老 APP 口径不符且凭空引入枚举 |

> 说明：这是本文件唯一的 domain 引用（`import '../../../domain/room_rules.dart' show CocRules;`），已在文件头注释里写明「纯函数、只做语法校验」。

---

## 6. 给波4 的验收用例口径（建议 `test/p17_w3c_test.dart`）

夹具沿用 `room_ui_kp_test.dart` 的 `_boot` / `_croppedState` / `_hostApp` 三件套（KP 视角 + 至少 2 个玩家）。

1. **伤害带 `amount` / `kind`**
   点 `RoomKeys.action('sheet.damage')` → `enterText(byKey(KpDirectiveKeys.damageAmount), '7')` → `enterText(damageKind, '火焰')` → 点 `targetConfirm('sheet.damage','p1')` →
   `p = asMap(f.lastSent(action:'sheet.damage')!['p'])`；断言 `p['seat']=='p1' && p['amount']==7 && p['kind']=='火焰'`（`amount` 必须是 int，不是 `'7'`）。
2. **伤害校验**：`enterText(damageAmount, '')` → 点执行 → `find.byKey(KpDirectiveKeys.formError)` **findsOneWidget** + `f.lastSent(action:'sheet.damage')` **isNull**；再 `enterText('0')` 同样拦。
3. **临时状态带 `text`**：选 `sheet.tempstatus` → `enterText(tempStatusText,'中毒 3 轮')` → 执行 → `p['text']=='中毒 3 轮'`；空串时必须拦（formError 出现、不发包）。
4. **物品带 `name`/`qty`**：`itemName='撬棍'`、`itemQty='2'`、`itemNote='沾血'` → `p['name']=='撬棍' && p['qty']==2 && p['note']=='沾血'`；`itemName=''` 时拦。
5. **sancheck 带 `okLoss`/`loss`**：`okLoss='0'`、`loss='1D10'`、`reason='见到深潜者'` → 逐字段断言；再 `loss='@@@'` → formError 出现且不发包（证明 `CocRules.parseExpr` 真的接上了）。
6. **急救：技能 + 检定数值（不带 `base`）**：选 `aid.apply` → 点 `aidSkill('医学')` → **检定数值留空** → 执行 → `p['skill']=='医学'`、`p['seat']==p['targetSeat']`，且 `p.keys.toSet() == {'seat','targetSeat','skill'}`（**钉死「留空时不加键」**：多一个 `base` 就红）。
6b. **急救：检定数值覆盖**：同上但 `enterText(byKey(KpDirectiveKeys.aidBase), '75')` → `p['base']==75`（int，不是 `'75'`），且 `p.keys.toSet() == {'seat','targetSeat','skill','base'}`。
6c. **精神分析：可选检定数值**：选 `aid.psycho` → 留空执行 → `p.keys.toSet() == {'seat','targetSeat'}`；再填 `60` → `p['base']==60`。
6d. **检定数值非法 → 不发包**：`enterText(aidBase, '0')` 与 `'abc'`（digitsOnly 会清空 → 等价留空，故重点测 `'0'` 与 `'1000'`）→ `formError` 出现、`lastSent(action:'aid.apply')` isNull。
6e. **domain 条件性覆盖（纯 domain 用例，不开 widget）**：`room_actions` 级夹具里发 `{op:'aid.apply', seat:'p1', targetSeat:'p2', skill:'急救'}`（**不带 base**）→ 与改动前逐字节一致（校验 `diceRoll` 的 `label` 里 `对 X` 的 X 等于角色卡技能值）；再发带 `base: 88` 的同款载荷（`bySeat='host'`）→ label 里的 X 等于 88；再发 `bySeat='p1'`（玩家自投）带 `base: 88` → 仍取角色卡值（**证明 KP 闸门生效**）。
7. **治愈疯狂 / 治愈重伤只带 `seat`**：两 op 各点一行 → `p.keys.toSet() == {'seat'}`（对 `madness.cure` 保留原 `kpDirective/target/madness.cure/p1` 那条既有断言，可直接复用）。
8. **暗骰 findsNothing**：`await _tap(find.byKey(RoomKeys.action('sheet.damage')))` 后，`expect(find.byKey(RoomKeys.action('dice.dark')), findsNothing)`；并 `expect(kKpDirectives.map((e)=>e.op), isNot(contains('dice.dark')))`。
9. **请求修改状态 findsNothing**：同上，`find.byKey(RoomKeys.action('state.request'))` findsNothing + `kKpExtraDirectives.map((e)=>e.op)` 不含 `'state.request'`。
10. **SAN 大失败追加无输入**：选 `sheet.sanloss` → `expect(find.byType(TextField), findsNothing)`（该指令不渲染表单）→ 执行 → `p['seat']=='p1' && p['dice']=='1D10'`。
11. **表单不串台**：选 `sheet.damage` → 填 `amount=7` → 切到 `sheet.tempstatus` → 执行 → 载荷里不得出现 `amount`。
12. **textScaler 1.3/1.5/2.0**：三档各 pump 一次 `KpDirectivesSheet`，依次点开 6 个有表单的指令（`sheet.damage` / `tempstatus` / `item` / `sancheck` / `aid.apply` / `aid.psycho`），`expect(tester.takeException(), isNull)`（固定宽度字段已用 `MediaQuery.withClampedTextScaling(maxScaleFactor:1.0)` 只钳该字段子树）。

**反向证伪建议（波5 用）**：把 `amount` 的 `form:` 覆盖改成写死 `1` → 用例 1 必须红；把 `sheet.item` 的 `qty` 传成字符串 → 用例 4 必须红；把 `aid.apply` 的 `skill` 去掉 → 用例 6 必须红；把 `raPayloadBaseOverride` 的 `!p.containsKey('base')` 判断删掉（改成 `raFinite(p['base'])`）→ 用例 6 必须红（空载荷会变成 `base:0`）；把 `bySeat == kHostSeat` 条件删掉 → 用例 6e 玩家自投那一路必须红。

---

## 7. 预计转红的既有测试（逐条给建议口径）

| 文件:行 | 断言 | 现在 | 建议口径（更强或等价） |
|---|---|---|---|
| `test/room_ui_kp_test.dart:813` | `expect(kKpDirectives.length, 9)` | **红**（现 8） | 改 `8`，并**新增** `expect(kKpDirectives.map((d)=>d.op), isNot(contains('dice.dark')))` + `expect(kKpDirectives.map((d)=>d.op), containsAll(<String>['sheet.damage','sheet.tempstatus','sheet.item','sheet.sancheck','madness.cure','sheet.healwound','aid.apply','sheet.sanloss']))`（把「删的是哪一项」钉死，而不是只改数字） |
| `test/room_ui_kp_test.dart:816` | `expect(kKpExtraDirectives.length, 2)` | **红**（现 1） | 改 `1`，并新增 `expect(kKpExtraDirectives.single.op, 'aid.psycho')` + `expect(kKpExtraDirectives.map((d)=>d.op), isNot(contains('state.request')))` |
| `test/room_ui_kp_test.dart:815` | `expect(kKpConsentOps.length, 5)` | 绿（未动） | 不动。另可加 `expect(kKpRemovedDirectiveOps, <String>{'dice.dark','state.request'})` 把「删的两项」显式化 |
| `test/room_ui_kp_test.dart:836-846` | 循环 `<String>['sheet.damage','sheet.tempstatus','sheet.item','dice.dark']` 断言「不过滤发作中」 | 绿（以 op 字符串驱动，不依赖列表） | 不动（`dice.dark` 作为 op 仍合法） |
| `test/room_ui_kp_test.dart:865-878` | `for (d in kKpDirectives/… ) p = kpDirectivePayload(d,'p1'); expect(p['seat'],'p1')` | 绿（可选参数默认值回落） | 不动 |
| `test/room_ui_kp_test.dart:880-905` | 点 `sheet.damage` 后 `find.textContaining('发作中') findsOneWidget` / 点 `madness.cure` 行 key 发 `{seat:p1}` | **预期仍绿**（伤害表单只含「伤害值/伤害类型」两个字段，不渲染人名；`madness.cure` 无表单） | 若因新增 `SectionBox` 导致文本计数漂移，**不要放宽成全量 findsWidgets**，改成 `find.textContaining('发作中（p2）')` 精确到座位；行 key 断言保持原样 |
| `test/room_ui_permission_test.dart:305-353`（T-30 锚点表） | `table.length == 30` / `kFrozenNoAnchor` 逐条 | **预期仍绿** | 不动。理由：删的两项锚点分别在 `sheets/sheet_dice_tools.dart:226`（字面量）与 `sheets/sheet_scene.dart:364`（字面量），`scanAnchors()` 仍能扫到，`POLICY` 61 条与「无锚点 30 条」清单都不变 |
| `test/room_ui_permission_test.dart:370-377`、`:456-500` | `expectGateEquivalence('KpDirectivesSheet')` / 静态表每个 op 运行时都能找到 | **预期仍绿** | 不动。新增控件一律不带 `act/` 前缀 key（`kpDirective/...`），不进入 T-30 射程；表单只在选指令后渲染，三种视角都没有新增 `act/<op>` |
| `test/p16_wave1_sheets_test.dart:600-601` | 玩家治疗弹层 `expect(p.containsKey('base'), isFalse)` | **绿**（未碰 `sheet_treat.dart`） | 不动。这条正好与新增的 KP 侧 `base` 相反：**玩家侧仍不带**、KP 侧才带，两条断言互相印证 |
| `test/p10_t7_*`（断言按钮数量/条目） | grep `KpDirectivesSheet|kKpDirectives|定向` 在 `test/p10_t7*` **0 命中** | 绿 | 无需改动（本组未碰这些用例的取样面） |

> 若波4/QA 另有「弹层标题文案」断言：标题已由「定向指令（9 项）」改为「定向指令（8 项）」，请同步口径（当前全库无该文案断言）。

---

## 8. 三处口径 → 2026-11-14 裁决与落地（已裁决并落地）

| # | 事项 | 裁决 | 落地状态 |
|---|---|---|---|
| 1 | 「急救/医学检定数值」「精神分析检定数值」 | **要加**（用户口径 > 老 APP，施工单 §0.1） | ✅ 已落地（UI + domain，见 8.1） |
| 2 | `sheet.damage.kind` 用文本框 | **接受**（老 APP 就是自由文本，工程无伤害类型枚举；硬造下拉会偏离） | ✅ 保持文本框，理由已写入 §5 |
| 3 | `aid.psycho` 保留 | **接受**：保留按钮、载荷 `{seat, targetSeat}` + 可选 `base` | ✅ 保持 |
| 4 | `base` 只认 KP 发起（`bySeat == kHostSeat`） | **批准并保留**：玩家走 confirm 路径时，篡改成功率对 KP 不可见，审批兜不住 → 判据必须放在取值侧 | ✅ 已落地（§8.2） |
| — | 「施救者/目标」 | **不动**：行座位同时作 `seat`/`targetSeat`（= 自救），P16 已定 | ✅ 未动（domain 仍支持 healer ≠ target，未来加下拉即可） |

### 8.1 新增「检定数值」的实现与「老载荷零变化」证据

**UI（`sheet_kp_directives.dart`）**
- 新 key `KpDirectiveKeys.aidBase` = `kpDirective/aid/base`（`:278`），152dp 固定宽 + `digitsOnly` + ≤3 位 + 该控件子树 `withClampedTextScaling(maxFactor:1.0)`。
- `aid.apply` 表单 = 技能 chips + 检定数值；`aid.psycho` 表单 = 只一个检定数值（`kKpFormOps` 因此从 5 项变 6 项，`:117`）。
- `_draftFor` 只在 `int.tryParse(...) != null` 时才放 `base`；`kpDirectivePayload` 用 `if (form['base'] != null) 'base': …` **条件性加键**。留空 → 载荷形状与 P17 之前逐字相同。

**domain（`room_model_actions_sheet.dart`）**
```dart
// :328 模块级纯助手
num? raPayloadBaseOverride(Map<String, Object?> p) {
  if (!p.containsKey('base')) return null;      // 老载荷：无键 → null
  final raw = p['base'];
  if (raw == null) return null;                  // 显式 null → null
  if (raw is String && raw.trim().isEmpty) return null; // 空串 → null
  return raFinite(raw);                          // 非数字 → null
}

// :1620（aidApply）/ :1756（psychoAnalyze）
final base = (bySeat == kHostSeat ? raPayloadBaseOverride(p) : null) ??
    skillBaseOf(..., ...);
```

**四类空值的逐项复核（lead 复核项）**：无键 → `null`；显式 `null` → `null`；空串 / 纯空白 → `null`（`raw.trim().isEmpty` 前置拦截，**不会**走进 `raFinite` 里 `t.isEmpty → 0` 那条分支）；非数字（`'abc'` / `'12abc'`）→ `raFinite` 内部 `double.tryParse` 失败返回 `null`。
**故意不回落成 0**：`base = 0` 会让检定必失败，比「不给值」更糟，正是要避开的坑。
补充边界（如实登记）：`'0'` / `0` 属于合法有限数，会被原样接受 —— UI 侧限制 1–999 拦掉 0，domain 对合法数字不做额外改判（KP 直发路径信任 KP；只有 KP 能走到这里）。

**「老载荷路径零变化」的四条证据**
1. **表达式等价**：`base` 原来的取值表达式 `skillBaseOf(healer, skill, null)`（`:1600` 旧行号）现在只在 `??` 右侧出现；不带 `base` 时左操作数恒为 `null`，最终值与原表达式**完全相同**（`null ?? x == x`）。
2. **键存在性守卫**：`!p.containsKey('base')` 是第一个判断——fixtures / oracle / 玩家申请路径的 `p` 里根本没有这个键（`grep 'aid' test/*.dart` 里 `base` 0 命中；`p16_wave1_sheets_test.dart:600` 还专门断言玩家治疗弹层 `p.containsKey('base')` isFalse，本批未碰 `sheet_treat.dart`）。
3. **只改了「技能值来源」一处**：`aidApply` 的伤口 / 濒死 / 昏迷 / 回复量分支、`psychoAnalyze` 的 SAN 结算 / 冷却 / 疯狂判定，以及 `healWound` / `cureIndefinite` **一行未动**（只替换了两个 `final base =` 行 + 新增一个文件级纯函数）。
4. **安全闸门（lead 已批准，保留）**：`bySeat == kHostSeat`（`room_types.dart:29` = `'host'`）——只有 KP 经本弹层直发才认 `base`；玩家塞的 `base` 一律忽略。

### 8.2 为什么这个闸门必须做在取值侧（不是「收紧口径」而是安全边界）

`aid.apply` / `aid.psycho` 的 POLICY 是 `[player,kp] + RoomConfirm.kp`（`room_types.dart:307-318`），玩家提交会进 KP 的待确认队列。若玩家能自带 `base: 999`：

- 语义上等于「申请一次**必定成功**的急救 / 精神分析」；
- 而 KP 在待确认卡里看到的只是「某玩家申请对某玩家急救」（`OP_LABEL` 只有 op + 发起者），**看不到成功率被改过**；
- 也就是说，「KP 点同意」这道审批**挡不住这种隐蔽篡改** —— 人眼兜不住，只能把判据放在取值侧。

因此闸门写进 `aidApply` / `psychoAnalyze` 的取 base 表达式，而不是靠 UI 少发字段（UI 只发是「不该发」，domain 不收才是「不会生效」—— 两层都要有）。玩家申请路径因此与 P17 之前逐字相同：`bySeat != 'host'` → 左操作数恒 `null` → 回落角色卡技能值。

> 若日后产品上确实要允许玩家自填技能值（例如「KP 先口头同意再代填」），移除 `bySeat == kHostSeat ?` 一个条件即可，但那属于新需求，需重新评估审批卡的可见信息。

**未加的东西**（避免越界）：没有新增 action、没有改 `kRoomPolicy`、没有动 `stateRequest` / `consent` 链路、没有给 `base` 加存档字段（纯载荷级，一次性）。

---

## 9. 声明

- 未跑 `flutter test`（并发期纪律）；只跑了 `dart analyze lib/ui/room/sheets/sheet_kp_directives.dart lib/domain/room_model_actions_sheet.dart`（两文件一起，零问题）。
- 未修改任何既有测试，未新建测试文件。
- 文件集：本组写 `lib/ui/room/sheets/sheet_kp_directives.dart`、`lib/domain/room_model_actions_sheet.dart`（**2026-11-14 由主理人新纳入**，只改 `aidApply` / `psychoAnalyze` 的技能值来源 + 一个纯助手）与本报告；`room_types.dart` 仅只读。
- 未改 `pubspec.yaml` / `pubspec.lock` / `app_version.dart`；未 `flutter clean`；未出包；未跑 adb / 模拟器。
- 未新增 action、未改 `kRoomPolicy`（61 条不变）。
