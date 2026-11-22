# P10 第 7 期 B 批 · 只读侦察报告（老 APP 2.13.13 vs 新工程）

> 任务性质：**纯只读研究**。未改任何文件（本文件除外）、未跑 flutter 命令、未出包。
> 老 APP 根：`coc7th-card-app/android/app/src/main/assets/js/`
> 新工程根：`dice-realm/`
> 结论先行：**两个问题都是「UI 没接」而不是「domain 没做」**——domain 侧的
> `combat.start` 已经完整支持 `actorIds` / `pcSeats` / 每个 actor 的 `hp/hpMax/dex/
> actionsPerRound`；缺的是「填数值的表单」和「选怪选人的弹层 + 轮次信息条」。

---

## A · 加怪 / NPC 的数值输入

### A1 老 APP 的入口链路（行号）

| 步骤 | 出处 | 说明 |
|---|---|---|
| 左窄栏三 tab（地图 / NPC·怪物 / 素材） | `ui/room-panels.js:1402-1416` | `kpLeftColumn`，tab 文案 `👹 NPC·怪物` (:1407) |
| 「＋ 添加怪物 / NPC」按钮 | `ui/room-panels.js:1380-1383` | 仅 KP 渲染；`onclick → addActorSheet(ctx, {preCombat:true})` |
| 候选池列表 | `ui/room-panels.js:1377-1399` | 每行：名称 + `怪物/NPC · DEX n`；空池给「还没有怪物/NPC。点上面添加。」 |
| 候选池三来源合并 | `ui/room-panels.js:1335-1355` | ① `ctx.host.localActors` ② `UI_STATE.pendingActors` ③ `st.combat.order` 里已有的 monster/npc |
| 写入候选池 | `ui/room-panels.js:1367-1375` | 优先 `host.addLocalActor(actor)`（同 id 去重）；否则直 push；再否则 `UI_STATE.pendingActors` |
| 战斗准备弹层里也能加 | `ui/room-panels.js:4169-4172` | 「＋ 新增怪物 / NPC」→ 加完 `render(); syncDeploy();` |
| 战斗中加单位 | `ui/room-panels.js:1797` | 战斗面板底部「＋ 加单位」→ `addActorSheet(ctx)`（**preCombat 缺省 = false**，走 `combat.actor`） |

### A2 老 APP 让 KP 填的字段（**这是问题 3 的答案**）

表单构造：`ui/room-panels.js:5258-5297`（`addActorSheet`）。字段清单：

| # | 中文标签 | 键名 | 默认值 | 必填 | 校验 / 夹取 | 出处（room-panels.js） |
|---|---|---|---|---|---|---|
| 1 | 名称 | `name` | `'新单位'` | 否 | HTML `maxlength:24`；提交前 `M.cleanText(name,24)`；空 → `'单位'` | :5260（input）、:5269（label）、:5279 |
| 2 | 类型 | `kind` | `'monster'` | 是（二选一） | select 只有两项：`monster`「怪物（血量隐藏）」/ `npc` | :5264-5267、:5270 |
| 3 | DEX | `dex` | `50` | 否 | `+dexI.value \|\| 0`（非法 → 0） | :5261、:5271、:5280 |
| 4 | HP | `hp` | `10` | 否 | `+hpI.value \|\| 0`；**同时把同值写进 `hpMax`**（不单独填上限） | :5262、:5272、:5281 |
| 5 | 每轮行动次数 | `actionsPerRound` | `1` | 否 | UI 侧 `Math.max(1, +actI.value \|\| 1)`；domain 侧 `raClampNumber(...,1,10,1)` 再夹到 1–10 | :5263、:5273、:5282；夹取见 `core/room-model.js:3932` |
| 6 | （自动）id | `id` | `'x'+Date.now()+rand(0..999)` | 是 | 无（`combat.actor` 缺 id 时 domain 兜底 `x{localSeq}`，见 `room_model_actions_combat.dart:298-301`） | :5278 |

构造出的 actor 对象（:5277-5283）：
```js
{ id, name, kind, dex, hp, hpMax: hp, actionsPerRound }
```

**老 APP 明确没有的字段（如实说「没有」，不硬凑）**：
- ❌ 伤害加值 / DB
- ❌ 护甲 / 装甲值
- ❌ 格斗值（Fighting）
- ❌ 闪避（Dodge）
- ❌ MOV / 移动力
- ❌ HP 上限单独输入（与 HP 同值）
- ❌ 攻击次数与「每轮行动次数」的区分（两者合一）
- ❌ 任何「从怪物库选」的入口（见 A3）
- ❌ 数值范围校验提示（超出只静默夹取，不弹错；只有 `actionsPerRound` 有 1–10 夹取）

### A3 是否有怪物库 / 预置怪物数据

**没有。** 全库 grep `COC_MONSTERS` / `monsterPool` / `npcPool` **零命中**；
`coc7th-card-app/.../js/` 下 `monster` 仅 48 处、`room-model.js` 26 处、`room-ui.js` 1 处，
全部是「单位类型字符串 `'monster'`」与「新战斗单位」的语义，**没有任何数据表文件**。
→ 老 APP 走的是**纯手填**，每次开战前 KP 逐个添加。新工程现状相同（见 A4），无需补数据表。

### A4 新工程现状对照

| 项 | 新工程位置 | 现状 |
|---|---|---|
| 本地候选池 | `lib/ui/room/room_ui_local.dart:43-44` | `final List<Map<String,Object?>> pendingActors`（注释「不进事件流，随 combat.start 送」） |
| 加怪纯函数 | `lib/ui/room/widgets/gp_kp_tools.dart:76-99`（`addLocalActor`） | **函数签名已经支持 hp / dex / actionsPerRound**（默认 10 / 50 / 1，ap 夹 1–10，kind 只认 monster/npc） |
| 加怪 UI（工具窄栏） | `gp_kp_tools.dart:240-256` | 只有一个 `TextField(labelText:'候选单位名')` + 「加怪」按钮；**调用点 `:252` 只传 `name:`** → 其余三项永远吃默认值 |
| 加怪 UI（左窄栏） | `gp_kp_left.dart:155-186` | 同上；**`:161` 也只传 `name:`**；列表只显示 `名称（kind）`，**不显示 DEX / HP / 每轮行动** |
| 战斗弹层里的「加单位」 | `sheets/sheet_combat.dart:176-222` | 只有一个「单位名」输入 + 「加入战斗」/「写入候选池」；`_actorPayload()` (`:228-236`) **硬编码 `kind:'monster', dex:50, hp:10, hpMax:10, actionsPerRound:1`** |
| domain 侧 actor 字段要求 | `lib/domain/room_model_actions_combat.dart:170-260`（`combatStart`） | 读 `p['actors']` 每个 actor 的 `id/name/kind/dex/hp/hpMax/actionsPerRound/manualOrder/readyFirearm/seat`；`hp` 缺省 0（`room-model.js:4344-4345` 注释明确「`hp:0,hpMax:0` 不是死了，是没登记血量」） |
| 服务端候选池 | `lib/domain/room_model_actions_room.dart:1012-1039`（`setActorPool`） | **已实现**：白名单收 `id/name/kind/dex/hp/hpMax/actionsPerRound`，写 `host.localActors`，**随存档**（`room_model_save.dart:93`） |
| 读服务端池 | `lib/ui/room/room_session.dart:76` | `RoomHostRead.localActors` **已暴露**，但**全库没有任何 UI 读它**（`gp_kp_left` / `gp_kp_tools` 读的是 `local.pendingActors`） |

**结论（缺什么）**：新工程缺 **4 个输入控件**（类型 / DEX / HP / 每轮行动次数）与**候选列表的字段展示**；
数据层与纯函数都已就绪，**不需要动 domain**。

---

## B · 战斗准备（选怪选人）+ 轮次信息栏

### B1 老 APP「转战斗」到底做了什么（问题 10 的根因）

`ui/room-panels.js:277-299`（`modeSwitch`，KP 专用）：

```
:283  onclick:
:284    if (cur === mode) return;
:285    if (mode === 'COMBAT') { combatPrepareSheet(ctx); return; }   // 必须先选怪
:286    if (cur === 'COMBAT') {   // 战斗 → 探索
:287      global.UI.confirm('回到探索模式？会结束当前战斗。', {okText:'结束战斗'})
:288        .then(ok => ok && ctx.act({ op: 'combat.end' }));
:289      return;
:290    }
:291    ctx.act({ op: 'scene.mode', mode: mode });   // 探索→探索之类才直发 scene.mode
```

→ **点「⚔️ 战斗」不直切 mode，而是打开 `combatPrepareSheet`**；只有「结束战斗回探索」走 `combat.end`。

### B2 `combatPrepareSheet` 完整交互（`ui/room-panels.js:4080-4177`）

| 步骤 | 出处 | 行为 |
|---|---|---|
| 角色门禁 | :4082 | 非 KP → toast「只有 KP 能开始战斗」并返回 |
| ① 玩家多选 | :4095-4111 | 标题「玩家（勾选进入战斗）」；**反选表 `pcOff`：key 不存在 = 默认选中**（默认全选）；已撕卡（`targetBlocked`）**不列出** |
| ② 怪物多选 | :4112-4130 | 标题「怪物 / NPC（勾选进入战斗）」；`selected` 初始**空对象 = 默认全不选**；空池提示「候选池是空的。点下面「＋ 新增怪物」先添加。」；行内显示 `类型 · DEX n · 每轮 k 次`（k>1 才显示） |
| ③ 加怪 | :4169-4172 | 「＋ 新增怪物 / NPC」→ `addActorSheet({preCombat:true, onAdded: render+syncDeploy})` |
| ④ 主按钮 | :4133-4162 | 文案「⚔️ 战斗部署完毕」；`disabled = 选中怪物数 === 0`；有选中时带计数「（怪物 n · 玩家 m）」 |
| ⑤ 至少 1 个怪物 | :4136-4137 | 否则 toast「至少选择 1 个怪物/NPC」 |
| ⑥ 弹层标题/说明 | :4175 / :4167 | 「战斗模式 · 选择参战单位」/「勾选要进入战斗的玩家与怪物/NPC（玩家默认全选）。系统按 CoC 7th 规则自动排行动顺序。」 |

**提交载荷（:4136-4152）**：
```js
ctx.act({
  op: 'combat.start',
  actorIds: ids,                                 // 只列怪物/NPC 的 id
  actors: pcActors(ctx).concat(monsterActors),   // PC 也塞进 actors（kind:'pc', seat）
  pcSeats: [...]                                 // 勾选的玩家座位
});
```
其中 `pcActors`（:4064-4073）：`{id:'p-'+seat, name:charName||nickname||'玩家', kind:'pc', seat,
dex: memberDex(m) ?? 0, actionsPerRound:1, hp: memberStats.hp ?? 0, hpMax: hpMax ?? hp}`。

**domain 侧 `combatStart`（`core/room-model.js:2461-2560`）**：
- `actorIds` 只过滤怪物/NPC，**PC 永远自动加入**（:2471-2473）；
- `pcSeats` 再过滤 PC（:2477-2483）；
- 撕卡 PC 跳过并 sysTo KP 提示（:2486-2498）；
- `CocRules.initiativeOrder()` 排序（DEX 降序 / 已准备枪械 +50 / manualOrder 优先 / 多行动展开多槽）（:2500-2513）；
- 槽字段：`id/actorId/name/seat/kind/dex/effDex/readyFirearm/manual/manualOrder/slot/totalSlots/done/movedToTail/public{dex,state,hpPublic,hp,hpMax,down}`（:2518-2547）；
  **`hpPublic = kind==='pc' ? true : (a.hpPublic===true)`** → 怪物与 NPC 默认都隐藏 HP；
- 写 `state.combat = {order, turn:0, round:1, startedAt}`、`meta.mode = COMBAT`，发 `STATUS` + `COMBAT` 事件，并 sys「进入战斗：共 N 个行动槽」（:2549-2558）。

### B3 老 APP 进入战斗后的「战斗轮次信息栏」

**① 行动顺序条 `initiativeBar`（`ui/room-panels.js:372-400`）** —— 这就是用户说的「战斗轮次信息栏位」：

| 元素 | 字段 | 出处 |
|---|---|---|
| 顶部一行 | `第 <b>N</b> 轮 · 当前行动：<b>名字</b>`（多行动时追加 `（第 x/y 次行动）`） | :379-382 |
| 轮到你提示 | `🎯 轮到你行动了`（仅自己回合） | :383-385 |
| 横向槽条 `.init-bar` | 每个行动槽一个 `.init-slot`，状态类：`.cur`（当前）/ `.done`（已行动）/ `.down`（已倒下） | :386-391 |
| 单槽内容 | ① `slot-no`：`x/y`（totalSlots>1 才显示）② 名字 ③ 类型（`PC` / `怪物` / `NPC`）④ `hpBar(slot)` | :392-396 |
| 挂载位置 | KP 地图区 `:1543`；玩家地图区 `:3057`；骨架预留 `.gp-combat-strip`（`ui/room-ui.js:2951`、`:3038-3041`），每次 paint 先 `clear`（`:3094-3095`） | 同左 |

**② 轮次强提醒 `notifyTurn`（:402-427）**：读 `state.alert`（`{kind,round,turn,name,seat,at}`），
按 `at|round|turn` 去重；轮到本人 → beep + toast「🎯 轮到你了：名字」；KP 侧轮到 NPC/怪物 → toast「▶ 轮到 X 行动」。

**③ 战斗面板 `kpCombatPanel`（:1695-1806）**：两 tab「战斗列表 / 怪物信息」
（:1698-1701）。「战斗列表」表头 **顺序 · 名称 · 类型 · HP · 状态 · 行动**（:1739-1746），
每行：`序号(+ x/y)` / 名字 / `PC|怪物|NPC` / `hp/hpMax`（无公开 HP 显示「隐藏」）/ `已倒下|state` /
按钮 `▶`（`combat.next`）与 `💥`（`damageSheet`）（:1747-1767）。
「怪物信息」按 actor 去重，显示 名字 + 类型 + 每轮次数 + DEX + hpBar + 状态 chip（:1716-1733）。
未参战玩家卡「未参战玩家（可加入战斗）」+「＋加入战斗」→ `combat.enqueue {seat}`（:1774-1792）。
底部「下一个行动 ▶ / ＋ 加单位 / 结束战斗」（:1795-1804）。空态提示：「尚未开始战斗。请在 KP 工具栏点「🛡 战斗模式」选怪后部署。」（:1709）

### B4 新工程差在哪（逐条）

| 差异 | 新工程现状 | 老 APP | 影响 |
|---|---|---|---|
| 转战斗 | `gp_toolbar.dart:135-142`：`RoomKeys.action('scene.mode')` → `hostAction('scene.mode', {mode:'combat'})` **直接切** | 先弹 `combatPrepareSheet` 选怪选人 | **问题 10 直接原因** |
| 战斗准备弹层 | `sheets/sheet_combat.dart` 存在，但①入口只有「KP 工具弹层 → 战斗」/ 战斗面板里的 `combat.start`；②**没有勾选**：`pcSeats` = 全部玩家（`:67-69`）、`actorIds: []`（`:97`）、`actors` = 全部候选（`:98`）；③无「至少 1 个怪物」门禁 | 勾选 + 默认全选玩家 + 至少 1 怪 | 无法选人选怪 |
| 候选池来源 | `local.pendingActors`（本机内存，**不进存档**） | `host.localActors`（进存档）+ 本地兜底 | 重开会丢候选怪（次要） |
| 轮次信息栏 | 只在 `gp_combat_list.dart:136` 有一行 `Text(roundText(state))` → `第 N 轮 · 行动 x/y`（`combat_view.dart:101-111`）；**没有地图上方的行动顺序条** | `initiativeBar`：轮次 + 当前行动者 + 槽进度 + 每槽 HP 条 + 高亮 | **问题 10 后半：「没有出现战斗轮次信息栏位」** |
| `gpCombatStrip` 槽位 | `room_keys.dart:38/69` 有 `RoomSlot.gpCombatStrip`，但 `room_game_page.dart:183`(标题) 与 `:725`(兜底) **都是零尺寸/断言分支 → 从不渲染** | 老 APP 有 `.gp-combat-strip` 实体 | 需要在页面钉住一条 strip，或复用 `gp_combat_list` 内部 |
| 战斗列表字段 | `gp_combat_list.dart:145-160`：序号 / 名字 / `stateText` / `HP n/m`（隐藏时「隐藏」）/ `已倒下` / （monster 信息 tab）`kind · state` / `行动 k` | 表格六列 顺序·名称·类型·HP·状态·行动 | 基本对齐，仅「类型」列只在 detail tab 显示 |
| 玩家加入战斗 | `gp_combat_list.dart:118-124` 有「＋加入」→ `combat.enqueue`（顶栏 trailing） | 未参战玩家卡片列表 | 已有，位置不同 |

---

## C · 最小实现建议（只做用户点名的两件事）

**原则：不动 domain**。domain 侧 `combatStart` / `setActorPool` / `combatEnqueue` 已完整支持全部字段与过滤。

### C1 问题 3「加怪能填数值」——改 2 个文件

1. `lib/ui/room/widgets/gp_kp_tools.dart`
   - 加怪区（`:240-256`）从「单行名字 + 按钮」扩成一个**内联小表单**（在窄栏里用 `Wrap` 排，不新增弹层）：
     名称(TextField，已有) / 类型(SegmentedButton 或两个 chip：怪物·NPC) / DEX(number) / HP(number) / 每轮行动(number)
   - 调用点 `:252` 改为把 4 个值一起传进 `addLocalActor(local, name:…, kind:…, dex:…, hp:…, actionsPerRound:…)`
     —— **函数签名已支持，零改动**。
   - 候选列表行（`gp_kp_left.dart:165-186` 与 `gp_kp_tools.dart:258`）补显示 `DEX n · HP n · 每轮 k 次`。
2. `lib/ui/room/widgets/gp_kp_left.dart`
   - `:155-163` 同样把 4 个值传全（或让左窄栏复用工具窄栏的表单组件，避免两套）。
   - `:168-186` 行文本补字段。

**可选（推荐但可延后）**：把 `pendingActors` 同步到服务端池（`combat.pool.set`）以获得**存档持久化**
（老 APP 就是 `host.localActors` 进存档）。这会用到已存在的 `setActorPool`，仍不必改 domain。

### C2 问题 10「转战斗能选怪选人 + 出现轮次栏」——改 3 个文件 + 1 处接线

1. `lib/ui/room/widgets/gp_toolbar.dart`（`:135-142`）
   - KP 点「转战斗」时**不直发 `scene.mode`**，改为打开战斗准备弹层：
     `showCombatSheet<void>(context)`（该弹层已存在，`sheet_combat.dart:240`）。
   - 保留「战斗→探索」路径仍走 `combat.end`（与老 APP 一致），即按当前 `isCombat(state)` 分流。
   - ⚠️ T-30 探针：`RoundKeys.action('scene.mode')` 的 `enabled` 仍必须恒等 `gate.can('scene.mode')`，
     `onTap` 换实现不改 `enabled`（本批已踩过这个口径）。
2. `lib/ui/room/sheets/sheet_combat.dart`（战斗准备 SectionBox `:76-112`）
   - 加**两个勾选列表**（`playersOf(state)` 默认全选，反选集合；`local.pendingActors` 默认全不选）；
   - `combat.start` 载荷改为：`actorIds` = 勾选的候选 id、`actors` = `pendingActors` 全量（domain 会按 actorIds 过滤怪物 + 自动带 PC）、
     `pcSeats` = 勾选的座位；
   - 主按钮 `disabled` 增加「选中怪物数 == 0」（`RoomTap.enabled` 必须仍是 `gate.can('combat.start')`，
     所以「至少 1 怪」要写成 `hint` + 点后 toast，或用外层按钮包一层条件渲染——**不要动 enabled 口径**）。
3. `lib/ui/room/widgets/gp_combat_list.dart`（`:132-170`）
   - 在 `roundText(state)` 那一行下面加一条**行动顺序条**（复用 `combatRows(state, isKp:)`，
     已有 `isCurrent` / `hp` / `hpMax` / `hpHidden` / `kind` / `actionsPerRound` 字段，`combat_view.dart:70-81`）：
     每个槽显示 `x/y`（`actionsPerRound>1`）+ 名字 + 类型 + HP 条，`isCurrent` 高亮。
   - 若要「横屏时叠在地图上方」的观感，可把同一组件渲染进 `RoomSlot.gpCombatStrip` 并在
     `room_game_page.dart` 钉住（`room_keys.dart` 已预留该槽位，但**这是改 page，属更大面**）；
     **最小方案 = 只放在战斗面板内**，先满足「进入战斗能看到轮次信息」。

**不需要新增的**：不需要新 domain action、不需要怪物库数据、不需要新 RoomSlot/RoomKeys。

### C3 建议的验收（供施工单参考）

- 加怪：填 DEX 30 / HP 25 / 每轮 2 次 → 候选行显示 `DEX 30 · HP 25 · 每轮 2 次`；
  开战后该单位在顺序表中 `totalSlots=2` 且出现两个槽（domain 已保证）。
- 转战斗：点「转战斗」→ 出现「战斗模式 · 选择参战单位」；玩家默认全勾、怪物默认全不勾；
  不勾怪物时确认要给出明确提示；确认后 `state.combat.order` 长度 = 勾选怪物槽数 + 勾选 PC 数。
- 轮次栏：进入战斗后立刻可见「第 1 轮 · 当前行动：X」，槽条高亮第一个，`combat.next` 后高亮右移且文案同步。

---

## D · 事实清单里「老 APP 没做」的部分（避免施工时误补）

1. 没有怪物库 / 预置怪物数据（A3）。
2. 没有 DB / 护甲 / 格斗 / 闪避 / MOV / HP 上限单独输入（A2）。
3. 没有数值越界提示（静默夹取，仅 `actionsPerRound` 夹 1–10）。
4. `combat.prepare` 在老 APP 与**新工程**都是**纯 UI 空操作**（老：`core/room-model.js:250` 注释；
   新：`room_model_actions_room.dart:515-517` 返回空计划）——不要指望它做任何事。
5. 怪物与 NPC **都默认隐藏 HP**（`hpPublic=false`），只有 PC 公开（老 `:2541`，新 `:418-424` 同口径）。
