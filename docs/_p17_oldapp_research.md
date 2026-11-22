# P17 · 老 APP 2.13.13（webview 版）8 组口径只读研究报告

> 研究性质：**纯只读**。未修改任何生产代码，未跑 flutter / 出包 / adb；本报告是唯一写入文件。
> 老 APP 根：`C:/Users/60965/WorkBuddy/2026-11-08-13-25-14/_oldapp_ref/web/`（GitHub 备份 `zhuliu127/DiceLens-TRPG` 浅克隆）。
> 版本校验：`web/js/core/build-config.js:40` `versionName: '2.13.13'` ✓ 与任务声明一致。
> **本报告所有路径/行号均指 `web/js/...`（core / ui / data）、`web/index.html`、`web/css/app.css`。** P16 报告已逐条校验「历史报告根 `coc7th-card-app/.../assets/js/` 与本副本行号一致」，本批沿用。
> 实际文件树（供施工单按真实路径引用）：`web/js/{app.js, core/*.js, data/*.js, ui/*.js}` + `web/index.html` + `web/css/app.css`。任务书写的「`web/js/room-model.js`、`web/js/ui/room-*.js`、83 个 js」略有出入 —— 本副本 `room-model.js`/`room-rules.js` 在 **`core/`** 下，`ui/` 下只有 `room-panels.js`/`room-ui.js`，js 共 46 个。**按本报告给的 `web/js/core/...` / `web/js/ui/...` 引用即可。**
> 可复用校验：`_p16_oldapp_research.md`（对抗选单位/场景检定选单位/护甲/急救医学精神分析/布局）、`_p10_t7_research.md`（加怪/战斗准备/轮次栏）已读；本批 8 组是其**未覆盖的新东西**，不重复劳动。

---

## 0. 本批用户口径 vs 老 APP 口径 差异表（施工单先读）

| # | 用户口径（新 APP 改造诉求） | 老 APP 2.13.13 实际口径 | 判定 |
|---|---|---|---|
| A | 场景检定「检定方式」：①选全体/某玩家 ②输入技能 ③选**成功需要的检定等级：大成功/成功/困难成功/极难成功** ④推送→**系统自动检定** | 老 APP 无「检定方式」「检定等级」字样（全库 0 命中）。有两条流程：ⓐ「自定义检定（快速推送）」= 目标(`*`/单人) + 技能文本框 + **难度** 下拉 `REGULAR/HARD/EXTREME`（3 档，叫「难度」不叫「检定等级」，且**无「大成功」档**）→ `check.request` **推给玩家自己掷**（非自动）；ⓑ「场景检定编辑器」多步骤 → `scene.check.push`，仅**疯狂发作中**目标由系统自动掷（`sceneCheckStep` 自动分支）。「大成功/成功/困难成功/极难成功」是**结果等级**（LEVEL 5/2/3/4，KP 裁定按钮），不是「成功所需等级」输入 | **大部分为新需求**：4 档「成功所需等级」+ 通用「系统自动检定」老 APP 都没有；可复用的是目标下拉与 4 档等级字面量/判定式 |
| B | 对抗与老 APP 基本一致、仅小部分改动；一方玩家**下拉选武器**、武器→战斗技能映射表；一方怪物/NPC 时 KP 选**反击/闪避**；反击要输入**检定等级 + 造成伤害（骰表达式）**，闪避只输入**检定等级**；删「武器对抗」（与战斗对抗重复） | 老 APP 攻击对抗 `kpAttackSheet` 有：攻/防下拉(`pc:`/`mo:`) + **武器下拉**（攻击方是玩家时，从 `sheet.weapons` 取，`w.skill` 自动填攻击技能）+ 防守方式下拉 `counter/dodge/none` + **对抗值 1–100 数值** + 攻击方**伤害式(骰表达式)** + DB/护甲/连发。**没有「检定等级」输入、没有「反击单独输入造成伤害」**；反击伤害沿用攻击方武器伤害式。玩家侧「⚔ 战斗对抗」按钮 = `playerOpposedSheet`（弹层标题「⚔ 武器对抗」）→ **与「武器对抗」是同一个东西**（老 APP 只有一个玩家入口）；KP「⚔ 攻击对抗」是另一条 KP 直发链路 | **B1/B2 部分成立，B3 判定式成立**；「反击/闪避输入检定等级 + 造成伤害」属新需求；「武器对抗=战斗对抗」在老 APP 成立（删重复入口合理） |
| C | KP 定向指令按钮「点了只能选目标、没有输入效果」，需补：造成伤害值/临时状态/物品/sancheck 数值/急救医学检定数值/精神分析检定数值；另 3 个只需选目标：治愈疯狂、治愈重伤、**SAN 大失败追加（KP 要能选追加哪一次大失败的数值）** | 老 APP 定向指令卡 `kpDirectivesCard` 共 **9 个按钮**，多数**已有输入表单**（伤害值/状态文本/物品名数量/sancheck 成功·失败损失）；急救/医学有**技能下拉**（无数值输入，检定值从施救者人物卡读）；**精神分析不是 KP 定向指令**（是玩家侧申请 `aid.psycho`）；「SAN 大失败追加」=「🌀 追加理智损失」`sheet.sanloss`，**一键掷 1D10、不记录多次大失败、不让 KP 选** | 「补输入效果」多数老 APP 已做；**「多次大失败记录 + KP 选哪一次」老 APP 完全没有，是全新需求** |
| D | 玩家「申请治愈疯狂状态」「申请治愈重伤」入口 | 有：`selfStateSheet`（状态管理弹层）内「💊 治愈不定疯狂（需 KP 同意）」「🩹 治愈伤势（需 KP 同意）」→ `ctx.intent(ACT,{op:'madness.cure'})` / `{op:'sheet.healwound'}` → POLICY `confirm:'kp'` → KP「待你确认」卡 `ctx.side.confirmAct()` | **一致**，可直接复用 |
| E | 玩家侧「更多工具」菜单有哪些条目、昏迷/疯狂时是否仍可点开 | 老 APP **无字面「更多工具」弹层**（全库 0 命中；只有车卡器首页 `app.js:815` 的「⋯ 更多操作」角色卡菜单）。玩家房间工具入口是 ① `.gp-quick` 快捷行（人物卡查看/手绘板/重置缩放）② `diceBar .dice-extra` 8 个扩展按钮。昏迷/疯狂时 `.dice-extra` 全被 `disabled: opLocked` 禁用；`.gp-quick` **未接 opLocked、仍可点** | 「更多工具」名称/弹层属新 APP；老 APP 对应物被锁 |
| F | 昏迷/疯狂时**只能点「推进 1 轮」和「更多工具」，其它全禁** | 老 APP 整体操作锁 `playerOperationLocked`（昏迷/濒死/已撕卡/疯狂发作中 4 态）→ diceBar 全部按钮 disabled；**唯一例外是「⏩ 推进 1 轮」**；模型 intent 白名单另放行 `madness.cure`/`sheet.healwound`/聊天。「更多工具」(dice-extra) **也被锁** | 用户要求把「更多工具」也放行 = **对老 APP 的改动**（老 APP 只放行推进 1 轮） |
| G | KP 自定义调整战斗行动顺序（怪物插队） | **老 APP 无此功能**：无上移/下移/拖拽/输入序号 UI，无 reorder op；`combat.start` 按 `CocRules.initiativeOrder()` 自动 DEX 排序；`combat.enqueue` 只 `order.push` 追加到队尾；`manualOrder` 是 actor 携带字段（无 UI 录入） | **老 APP 无此功能，属新需求** |
| H | 首页头图删「COC 7th」「克苏鲁的呼唤 第七版 · 车卡器」，版本号移到原来 COC 7th 位置 | **这 5 段文字不在老 APP 的 HTML/CSS/JS 里**（`开始冒险`、`克苏鲁的呼唤 第七版 · 车卡器`、`骰境TRPG`(无空格) 全仓 0 命中）。它们全在**新 APP** `lib/ui/home_page.dart`。老 APP 只有：`COC 7th`（作为规则标签/卡片副标题）、`骰境 TRPG`（**带空格**，顶栏/关于/title）、`克苏鲁的呼唤 第七版`（首页规则卡大标题，**无「· 车卡器」**）、版本号（**只在「关于」弹层** `v2.13.13`） | 用户诉求是**新 APP 首页头图**改造；老 APP 无对应头图，只能给「最接近的等价物」当参照 |

---

## A. 场景检定「检定方式」

### 结论先行
老 APP **没有**「检定方式 / 检定等级」这两个词（全库 `检定方式|检定等级` Grep 0 命中）。场景检定实际是**两条独立流程**，且「系统自动检定」只在极窄条件下发生。用户描述的 4 步是**新口径**。

### A-1 「自定义检定（快速推送）」= 最接近用户描述的面板
`web/js/ui/room-panels.js:1818-1913` `kpSceneCheckPanel(ctx)` 尾部 `:1873-1907`（KP 场景检定面板里的「自定义检定」卡）：

```js
// :1875-1879  目标下拉（原生 selectCtl），value = '*' 或裸 seat
var players = playersOf(ctx).filter(function (m) { return !targetBlocked(m); });
var targetSel = selectCtl(
  [{ value: '*', label: '全体玩家' }].concat(players.map(function (m) {
    return { value: m.seat, label: m.charName || m.nickname || '玩家' };
  })), '*', null);
// :1880  检定内容（文本输入框，非单位名）
var skillI = el('input.input', { type: 'text', placeholder: '技能 / 属性，如：侦查 / 敏捷', maxlength: 20 });
// :1885-1889  难度下拉（3 档，字面量大写）
var diffSel = selectCtl([
  { value: 'REGULAR', label: '常规' },
  { value: 'HARD',   label: '困难（÷2）' },
  { value: 'EXTREME',label: '极难（÷5）' }
], 'REGULAR', null);
// :1896-1905  推送按钮 → payload
text: '推送给玩家',
onclick: function () {
  var skill = M.cleanText(skillI.value, 20);
  if (!skill) { global.UI.toast('请填写技能/属性', 'err'); return; }
  ctx.act({ op: 'check.request', seat: targetSel.value, skill: skill,
            difficulty: diffSel.value, desc: skill });   // :1901-1902
  global.UI.toast('已推送检定', 'ok');
}
```
- **载荷完整形状**：`{ op:'check.request', seat:'*'|<seat>, skill:<string>, difficulty:'REGULAR'|'HARD'|'EXTREME', desc:<string> }`（`desc` = skill 同值）。
- `:1881-1884` 注释明确「**删掉了「检定类型」下拉**（技能检定/属性检定），协议里没有 type 字段」—— 施工单勿再补 type。

### A-2 推送语义：**推给玩家自己掷，不是系统自动检定**
`web/js/core/room-model.js:3190-3238` `Host.prototype.checkRequest`（`:3186-3188` 注释逐字）：
> 「给目标（全体或单人）各发一条 REQUEST 事件（op='check.request'），玩家端弹出『KP 要求检定』卡；玩家点掷骰 → diceDirect 算结果并回发 REQUEST-done 摘卡。」

```js
// :3197-3201  seat='*' 展开成全体在线玩家 seat 列表
if (p.seat === '*' || !p.seat) targets = this.roster.onlinePlayers().map(function (m) { return m.seat; });
else targets = [p.seat];
// :3219-3229  请求卡 payload（base 从权威人物卡取，不信任客户端）
var authBase = that._skillBaseOf(tm, skill, null);
var rec = { id: id, from: bySeat, op: 'check.request',
            payload: { skill: skill, difficulty: difficulty, desc: desc, base: authBase }, ... };
that._push(out, that.emit(EVT.REQUEST,
  { self: true, id: id, op: 'check.request', payload: rec.payload, ... }, VIS.SEAT, t));
```
- 结果广播文案 `:3231-3237`：`diffText = { REGULAR:'', HARD:'（困难）', EXTREME:'（极难）' }[difficulty]`，LOG `text: 'KP 要求 ' + (全体玩家|名字) + '进行「' + skill + '」检定' + diffText`，`kind:'check-req'`。
- 玩家点掷骰走 `diceDirect` `room-model.js:3016-3048`：`res = rules.check({ kind:'skill', base:authBase, difficulty: p.difficulty || 'REGULAR', ... })`。

### A-3 「场景检定编辑器（多步骤/分支）」= 另一条流程
`web/js/ui/room-panels.js:4414-4459` `sceneCheckSheet` / `:4461-4544` `stepEditor` / `:4547-4575` `pushSceneCheck`。
- 目标 mode 下拉 `:4481-4485`：`[{value:'all',label:'全部玩家'},{value:'one',label:'指定一名玩家'},{value:'many',label:'指定多名玩家（按序）'}]`；`one` 用 `selectCtl(players.map(m=>({value:m.seat,...})))`（**裸 seat**）、`many` 用 `.pick` 多选、`all` → `['*']`（`:4555`）。
- 难度下拉 `:4512-4516` **同样是 3 档** `REGULAR/HARD/EXTREME`（字面量与 A-1 一致）。
- 步骤展开与提交 `:4558-4572`：
```js
steps.push({ id: s.id+'-'+seat, title: s.title||s.skill||'步骤', desc: s.desc||'',
  targetSeat: seat, skill: s.skill||'', difficulty: s.difficulty||'REGULAR',
  bonus: s.bonus||0, penalty: s.penalty||0,
  onSuccess: { damage:(s.onSuccess||{}).damage||'', note:(s.onSuccess||{}).note||'' },
  onFailure: { damage:(s.onFailure||{}).damage||'', note:(s.onFailure||{}).note||'' } });
ctx.act({ op:'scene.check.push', title: draft.title||'场景检定', desc: draft.desc||'', steps: steps });  // :4572
```
- 运行中数据挂 `state.sceneCheck`（`sceneCheckOf` `:1813-1815` 兜底 `sceneCheck‖scenecheck`；模型 `room-model.js:92` `SCENE_CHECK:'scenecheck'`）。数据结构 `{id,title,desc,steps,cursor,results}`。

### A-4 「系统自动检定」函数（老 APP 唯一的自动判定）
`web/js/core/room-model.js:6663-6850`：
- `sceneCheckPush` `:6663-6678`：`EVT.SCENE_CHECK` + sys 文案 `:6674` `'KP 推送了场景检定「'+sc.title+'」（'+steps.length+' 步）'`，随后 `_autoAdvanceSceneCheck()`。
- `_autoAdvanceSceneCheck` `:6690-6704`：**只处理「指定座位」且目标已锁死（撕卡 / 疯狂发作中）**的步骤；`'*'` 全员步仍留给 KP。
- `sceneCheckStep` `:6734-6850` 的 `p.level` 缺省分支 `:6767-6789`：
```js
// :6768-6783  疯狂发作中 → 权威端替他掷一次 D100（系统自动）
if (mPre && memberInBout(mPre)) {
  var autoBase = this._skillBaseOf(mPre, step.skill, null);
  if (autoBase == null) autoBase = 50;
  var diff = rules.normDifficulty(step.difficulty);   // :6772
  var autoChk = rules.check(Object.assign({ base: autoBase, difficulty: diff, kind:'skill',
                    label: (step.skill||'自动检定')+'（系统自动）', rng: this.rng }, ruleOptsOf(...)));
  level = autoChk.level;
  out = out.concat(this.diceRoll(seatPre, { expr:'1D100',
    label:'场景检定自动判定（...疯狂/撕卡状态由系统随机）', result: autoChk }));
} else { level = 2; }   // 默认 regular（原行为）
```
- **已撕卡**目标 `:6763-6765` → `_skipSceneStep`（`:6712-6731`）**跳过并提示**，不替掷。
- KP 手动裁定按钮（`:1856-1861`）：`[['🌟 大成功',5],['💀 大失败',-1],['❌ 失败',0],['✅ 成功',2],['⭐ 困难成功',3],['🌟 极难成功',4]]` → `ctx.act({ op:'scene.check.step', stepId:step.id, seat:step.targetSeat||'', level:p[1] })`。
- 成功判定 `:6796` `var ok = level >= 2;`；`sceneStepResolve` `room-rules.js:1384-1405` `success = lvl >= required`（`required` 来自 `DIFFICULTY[plan.difficulty].required`）。
- 结果广播文案 `:6839-6846`：`EVT.LOG`，`text: '场景检定「'+step.title+'」：'+nick+' '+lvlWord+'（'+note+'），受到 '+result.damage+' 点伤害'`，`kind:'check'`；`lvlWord`（`:6837-6838`）= `大成功`(level 5) / `大失败`(-1) / `ok?'成功':'失败'`。

### A-5 四个等级各自判定式（阈值怎么算）—— **可复制**
两套实现，结论一致：
**① `web/js/core/room-rules.js`（权威规则层，房间内所有检定走这里）**
```js
// :34-41  成功等级数值
var LEVEL = { CRITICAL:5, EXTREME:4, HARD:3, REGULAR:2, FAIL:0, FUMBLE:-1 };
// :43-46  文案（注意 '2' 是「常规成功」，不是「成功」）
var LEVEL_TEXT = { '5':'大成功','4':'极难成功','3':'困难成功','2':'常规成功','0':'失败','-1':'大失败' };
// :54-58  难度 → 所需等级 / 除数（键为小写！）
var DIFFICULTY = {
  regular: { required: LEVEL.REGULAR, text:'常规', div:1 },
  hard:    { required: LEVEL.HARD,     text:'困难', div:2 },
  extreme: { required: LEVEL.EXTREME,  text:'极难', div:5 }
};
// :120-123  三档阈值：常规=技能值，困难=/2，极难=/5，均向下取整
function thresholds(base) {
  var b = Math.max(0, num(base));
  return { base:b, regular:b, hard:Math.floor(b/2), extreme:Math.floor(b/5) };
}
// :181-192  成功等级判定（value=掷出 1-100，base=技能值）
function levelOf(value, base, target, opts) {
  var v = clampValue(value); var t = thresholds(base);
  var req = (target === undefined || target === null) ? t.regular : num(target);
  if (v <= critThresholdOf(opts)) return LEVEL.CRITICAL;   // 大成功：默认 v<=1（即 01）
  if (isFumble(v, req, opts)) return LEVEL.FUMBLE;          // 大失败
  if (v <= t.extreme) return LEVEL.EXTREME;                 // 极难成功 ≤ floor(skill/5)
  if (v <= t.hard)    return LEVEL.HARD;                     // 困难成功 ≤ floor(skill/2)
  if (v <= t.regular) return LEVEL.REGULAR;                   // 常规成功 ≤ skill
  return LEVEL.FAIL;
}
// :158-167  大失败范围（按「本次要求阈值」而非技能原值）
function fumbleRange(target, opts) {
  var fm = fumbleThresholdOf(opts);                 // 自定义 fumbleMin
  if (fm > 0) return { min:fm, max:100 };
  return num(target) < 50 ? { min:96, max:100 } : { min:100, max:100 };
}
// :285-297  check()： passed = level >= DIFFICULTY[difficulty].required
var difficulty = normDifficulty(opts.difficulty);
var target = targetOf(base, difficulty);          // :126 → thresholds(base)[difficulty]
var required = DIFFICULTY[difficulty].required;
var passed = level >= required;
```
**② `web/js/core/dice.js:47-56`（`COCDice.successLevel`，车卡器/简单判定用，房间规则层不调用）**
```js
function successLevel(rollVal, skill) {
  if (rollVal === 1) return 5;                                   // 大成功
  if (rollVal === 100 || (skill < 50 && rollVal >= 96)) return -1; // 大失败
  if (rollVal <= Math.floor(skill / 5)) return 4;                  // 极难成功
  if (rollVal <= Math.floor(skill / 2)) return 3;                  // 困难成功
  if (rollVal <= skill) return 2;                                  // 常规成功
  return 0;                                                       // 失败
}
var LEVEL_TEXT = { 5:'大成功', 4:'极难成功', 3:'困难成功', 2:'成功', 0:'失败', '-1':'大失败' };
```
> **⚠️ 大小写坑（全库复核确认，施工单务必注意）**：UI 下拉 / 载荷用的是**大写** `REGULAR/HARD/EXTREME`（`room-panels.js:1886-1888`、`:4513-4516`、`:5879-5882`；`room-model.js:3044`、`:3120`、`:5863`、`room-ui.js:5100` 均以 `'REGULAR'` 兜底），但规则层 `DIFFICULTY` 键是**小写** `regular/hard/extreme`，`normDifficulty(d)`（`room-rules.js:124`）=「`hasOwnProperty(DIFFICULTY,d) ? d : 'regular'`」→ **大写值一律回落成 `regular`**（`REGULAR` 回落语义恰好不变，但 `HARD`/`EXTREME` 会退化为常规：`target=base`、`required=LEVEL.REGULAR`，见 `room-rules.js:285-297`）。全库 Grep `difficulty.*toLowerCase` **0 命中**，确认无任何大小写转换包装；链路 `checkRequest`(大写) → REQUEST 卡 → `diceDirect`(`:3044` 大写) → `rules.check()`(`:285`) 逐段已核。→ **老 APP 存在此「困难/极难档在权威端退化为常规」的历史行为**。新 APP 是 Dart 自写口径，请主理人裁定：沿用大写字面量但自行归一、还是统一小写、以及是否顺手修正这个退化。

### A 未找到清单
- `检定方式` / `检定等级`：**全库 0 命中**（Grep `web/**`）。
- 「选成功需要的检定等级：大成功/成功/困难成功/极难成功」的下拉：**未找到**。老 APP 只有 3 档「难度」`REGULAR/HARD/EXTREME`；「大成功/成功/困难成功/极难成功」只作为**结果 level**（`:1856` KP 裁定按钮、`LEVEL_TEXT`）。
- 「推送→系统自动检定」的**通用**路径：**未找到**；只有 `sceneCheckStep` 对「疯狂发作中」目标自动掷（A-4）。

---

## B. 对抗（通用对抗 / 攻击对抗 / 反击闪避 / 武器对抗）

### B1 「通用对抗」vs「攻击对抗」入口区分与判定条件
`web/js/ui/room-panels.js:4654-4671` `opposedSheet(ctx)`（KP 二级菜单「⚔ 对抗」）：
```js
if (ctx.role !== 'kp') { global.UI.toast('只有 KP 能发起对抗检定', 'err'); return; }   // :4657
grid.appendChild(toolBtn('🎯 通用对抗', '双方各出一技能/属性比高低（同级同值逐轮重掷）', ...genericOpposedSheet(ctx)));
grid.appendChild(toolBtn('⚔ 攻击对抗', '攻击方 vs 防守方（反击/闪避）+ 自动伤害结算', ...kpAttackSheet(ctx)));
el('div.tiny.dim', { text: '通用对抗 = 技能/属性比高低；攻击对抗 = 战斗攻击 + 反击/闪避 + 伤害。' });  // :4666
```
- 入口另见 `:5729` KP 工具「⚔ 对抗」→ `opposedSheet`；玩家侧 diceBar「⚔ 战斗对抗」→ `playerOpposedSheet`（见 B4）。
- **模型侧 discriminator**：`web/js/core/room-model.js:5839-5843` `checkOpposed`：`if (p.attack || p.cancel) return this._opposedAttackResolve(bySeat, p);` 否则走 `:5845-5899` 通用分支。
  - 通用对抗载荷 `:4738-4741`：`{ op:'check.opposed', aSeat, aSkill, aBase, bSeat, bSkill, bBase, secret }`，下拉 value 前缀 `p:<seat>` / `a:<id>`（`:4697-4701`、`:4683-4689`）；结算 `rules.opposedFull`（`room-rules.js:533-537`，比等级→比数值→逐轮重掷 D100 低者胜 ≤10 轮兜底发起方胜）。
  - 攻击对抗载荷带 `attack:true` + `attacker`/`defender`/`weapon`/`shots`/`armor`/`secret`（`:4875-4897`），下拉 value 前缀 `pc:<seat>` / `mo:<id>`（`:4760-4770`）。
- **玩家发起战斗对抗门禁**（`:5431-5439`、`room-model.js:6468-6524`）：仅玩家、**仅战斗模式**、**仅自己行动轮次**（`isMyTurn`，当前行动槽须为本人 pc 槽）。

### B2 战斗对抗：武器下拉 / 武器→战斗技能映射 / 反击闪避输入 / 骰表达式
**（1）一方是玩家时下拉选武器 + 武器→「需要检定的战斗技能」映射表**
`web/js/ui/room-panels.js:4752-4905` `kpAttackSheet`：
```js
// :4790-4834  武器下拉容器，随攻击方变化重建；仅当攻击方 side==='pc' 才列武器
function rebuildWeapons() {
  var o = optOf(attPool, aSel.value);
  var opts = [{ value:'', label:'（手动填写伤害）' }];
  if (o.side === 'pc' && o.mem) {
    ((o.mem.sheet && o.mem.sheet.weapons) || []).forEach(function (w) {
      opts.push({ value: w.name, label: w.name+'（'+(w.damage||'')+(w.pierce==='√'?' 贯穿':'')+'）' });  // :4828
    });
  }
  wepSel = selectCtl(opts, '', function (v) { applyWeapon(v); });
}
// :4795-4807  选中武器 → 自动带出 伤害式 / 贯穿 / 【战斗技能】
function applyWeapon(name) {
  var w = /* 按 name 从 mem.sheet.weapons 找 */;
  if (w) {
    dmgI.value = w.damage || '1D3';       // 伤害式
    pierceChk.checked = (w.pierce === '√'); // 贯穿
    if (w.skill) aSkill.value = w.skill;    // ★武器→「需要检定的战斗技能」= weapon.skill 字段
  }
  rebuildShots(w);
}
```
- **映射表本体 = 武器对象的 `skill` 字段**，不是查表函数：
  - 数据源 `web/js/data/weapons.js`：`window.COC_WEAPONS = [{"id":"w1","name":"弓箭","skill":"弓","damage":"1D6+半DB",...}, ...]`（共 104 项）。全部 `skill` 取值（`grep '"skill":"..."'`）：`步枪/霰弹枪`(30)、`手枪`(18)、`斗殴`(11)、`机枪`(8)、`投掷`(7)、`冲锋枪`(6)、`爆破`(4)、`炮术`(4)、`剑`(3)、`重武器`(2)、`斧`(2)、`弓`(2)、`鞭子`/`链枷`/`绞具`/`矛`/`电锯`/`电气维修`/`喷射器`(各 1)。
  - **别名归一表** `web/js/ui/steps-c.js:30-34` `WEAPON_SKILL_ALIAS`（车卡阶段把武器库写法对齐人物卡技能专攻名）：
```js
var WEAPON_SKILL_ALIAS = {
  '剑':'刀剑', '鞭子':'鞭', '绞具':'绞索', '链枷':'链锯/连枷', '电锯':'链锯/连枷',
  '机枪':'机枪/重武器/火焰喷射器', '重武器':'机枪/重武器/火焰喷射器',
  '喷射器':'机枪/重武器/火焰喷射器'
};
var EXTRA_COMBAT_SKILLS = ['投掷','炮术','爆破'];
```
  - 战斗技能可选项 `weaponSkillOptions()` `steps-c.js:65-80`：从 `COC_SKILLS` 中 `def.id==='fighting'` 或 `'firearms'` 的 `subskills` 取 + `EXTRA_COMBAT_SKILLS`，label 形如 `'斗殴　45%（本职）'`。
  - 玩家侧另一个「战斗技能白名单」`room-panels.js:3336` `combatNames = ['格斗','斗殴','射击','闪避','武术','刀剑','枪械','斧','矛','鞭']`（`skillCheckSheet(ctx,'combat')` 用，**不是**武器映射表）。
  - 权威端取值 `room-model.js:6017-6029`（玩家申请路径）：`weapon = this._matchSheetWeapon(am, reqWeapon.name) || reqWeapon; var av = cleanText(weapon.skill,30) || reqSkill; var aval = this._skillBaseOf(am, av, null);` —— **按 `weapon.skill` 去人物卡查技能值**，查不到则整条对抗失败并提示「在发起者人物卡里查不到「X」」。

**（1-补）技能输入是否走「近义词 / 缩写标签」自动取卡值 —— 会，但是权威端 4 档归一匹配，不是搜索/下拉**（应 researcher-kp-p17 补查）
- UI 侧 `aSkill`/`bSkill`（`room-panels.js:4706-4707`）是**纯文本框** `el('input.input',{type:'text',value:'格斗'|'闪避',maxlength:20})`，**没有下拉、没有标签、没有近义词搜索框**；默认值 `'格斗'` / `'闪避'`。
- 提交后 `checkOpposed` → `_resolveActorSkill(p.aSeat,p.aSkill,aBase)`（`:5851-5852`）→ 玩家侧走 `_skillBaseOf(m,name,fallback)`（`:3835`、`:3782-3798`）→ `rules.skillValue(sheet,nm)`，未命中再 `rules.attrValue(sheet,nm)`，仍未命中才用 KP 手输 `fallback`（= `aBase`/`bBase`）兜底。
- **`rules.skillValue` 的 4 档匹配** `web/js/core/room-rules.js:1265-1300`（注释 `:1254-1264` 逐字「匹配档位（依次，命中多个即判为歧义 → 返回 null）」）：
  ① **精确名**（`normSkillName` `:1210-1221` 归一「全/半角/方/花括号→`()`、去所有空白含全角、去首尾标点、小写」）
  ② **别名** `SKILL_ALIAS`（`:1180-1197`，**16 条，可复制**）：
```js
var SKILL_ALIAS = {
  '斗殴':'格斗(斗殴)', '擒抱':'格斗(擒抱)', '踢击':'格斗(踢)', '踢':'格斗(踢)',
  '射击':'射击(手枪)', '手枪':'射击(手枪)', '步枪':'射击(步枪)', '霰弹枪':'射击(霰弹枪)',
  '冲锋枪':'射击(冲锋枪)', '机枪':'射击(机枪)', '弓':'射击(弓)', '弩':'射击(弩)',
  '侦察':'侦查', '图书馆':'图书馆使用', '计算机':'计算机使用', '开锁':'锁匠'
};
```
  ③ **基名相等**（`skillBase(s)` `:1223-1227`，去掉括号及其内容 / `｜` 分隔开头片段，如 `'格斗'` → `'格斗(斗殴)'`）
  ④ **子类名相等**（`skillSpecs(s)` `:1233-1245`，如查询 `'斗殴'` 命中卡上 `'格斗（斗殴）'`）
  - `totalOfSkill` `:1246-1252` 取 `s.total ?? s.value`。歧义（>1 命中）返回 `null`。
- `attrValue` `:1306-1320`：支持中文属性名（`'力量'`）或 key（`'str'`），`ATTR_CN2KEY` + 大小写变体。
- **⚠️ 三张别名表别混**：① `room-rules.js:1180 SKILL_ALIAS`（**权威端技能名取值**，v2.2.2 为修「『斗殴』查不到」加的）；② `steps-c.js:30-34 WEAPON_SKILL_ALIAS`（**车卡阶段**武器库写法→人物卡专攻名，见 B2(1)）；③ 新 APP P15 的「技能搜索近义词」（搜索框联想，**老 APP 无**）。
- 单位（怪物/NPC）没人物卡 → **必须手输 1–100 对抗值**（`:4708-4712` 输入 `aBase`/`bBase`、`:4730-4737` 拦截、`_resolveActorSkill` `:3849-3861` 校验 1–100 整数，非法明确报错不静默截断）。

**（2）一方是怪物/NPC 时 KP 选反击/闪避**
`room-panels.js:4777-4781`（KP 直接发起）与 `:5001-5004`（KP 裁定玩家申请）：
```js
// kpAttackSheet 防守方式（默认 'dodge'）
var reactionSel = selectCtl([
  { value:'counter', label:'反击（同级攻方胜）' },
  { value:'dodge',   label:'闪避（同级攻方败/免伤）' },
  { value:'none',    label:'不防御' }
], 'dodge', null);
// opposedResolveSheet 防守方式（默认 'counter'，只有两项）
[{ value:'counter', label:'反击（同级：攻击方胜）' },
 { value:'dodge',   label:'闪避（同级：攻击方败/被躲开）' }]
```
- 模型归一 `room-model.js:4376-4377` `normReaction`：`'counter'|'fightback'|'反击' → 'counter'`，`'dodge'|'闪避' → 'dodge'`；规则层 `room-rules.js:917-922` `normMode`：`'dodge'/'闪避'→'dodge'`，`'fightback'/'fight_back'/'fight back'/'反击'→'fightback'`，其余 `'none'`。

**（3）「反击要输入检定等级 + 造成伤害骰表达式；闪避只输入检定等级」—— 老 APP 没有**
- 老 APP 防守方输入的是 **「对抗值 1–100」**（数值，不是「检定等级」）：`kpAttackSheet` `dVal` `:4782`（`type:'number', value:'50', placeholder:'1-100（怪物必填）'`，校验 `:4872-4874`）；`opposedResolveSheet` `valI` `:5005`（校验 `:5056-5058`）；攻击方 `aVal` `:4775`。
- 老 APP **无「反击单独造成伤害」输入**。伤害式 `dmgI` `:4783`（`type:'text', value:'1D3', maxlength:30`，label「伤害式」`:4859`）是**攻击方武器**的；反击命中时沿用同一伤害式（`room-model.js:6065` `dmgSpec = (defenderDeals && defenseSpec.damage) ? defenseSpec.damage : o.damage`，而 UI 从不传 `defense.damage` → 用 `o.damage` = 武器伤害式）。
- 「🕶 无法反抗」勾选项 `:5008-5017`（`noDefense`）→ 跳过对抗判定、攻击方自动成功直接进伤害判定（`:6041-6044`、`:6158-6160`）。

**（4）骰表达式解析 / 投骰函数（支持 `2D6+D4+1`）—— 可复制**
三套，施工单按需要取：
```js
// ① web/js/core/room-rules.js:554-584  CocRules.parseExpr（严格校验、可注入 rng）
function parseExpr(expr) {
  var raw = String(expr == null ? '' : expr).trim();
  if (!raw) return { ok:false, reason:'骰式为空', expr:'' };
  var s = raw.replace(/\s+/g,'').toUpperCase();
  var tokens = s.match(/[+-]?[^+-]+/g);            // 按 +/- 切项
  ...
  var m = tk.match(/^(\d*)[D](\d+)$/);               // 2D6、D4、+1 都认
  if (m) { ...; terms.push({ sign, count, sides }); }        // count 1..MAX_DICE, sides 2..MAX_SIDES
  else if (/^\d+$/.test(tk)) terms.push({ sign, count:0, sides:0, constant:c });
  else return { ok:false, reason:'骰式里有无法识别的片段「'+tk+'」', expr:raw };
  return { ok:true, expr:raw, terms:terms };
}
// :587-608  CocRules.rollExpr(expr, rng) → {ok, total, rolls:[{count,sides,sign,dice}], detail}
// 例：'2D6+D4+1' → terms=[2D6, +D4, +1]，total = 掷 2 个 D6 + 1 个 D4 + 1
```
```js
// ② web/js/core/dice.js:14-30  COCDice.parse（车卡器用，直接 Math.random，会吞掉中文/码后缀）
function parse(expr) {
  var clean = String(expr).replace(/[（(].*?[)）]/g,'').replace(/[A-Za-z\u4e00-\u9fa5/码米步].*$/,'');
  var m = clean.match(/-?\d*[Dd]\d+|\d+/g);
  ...  // 逐 token：/[Dd]/ → roll(n,sides)；否则 parseInt 累加
}
// dice.js:47-56  COCDice.successLevel（见 A-5）
```
```js
// ③ web/js/ui/room-panels.js:5476-5508  玩家直投（doRollExpr）
function parseDiceExpr(expr) {  // :5476-5483  只认「NDM」单段，暗骰冻结 payload 用
  var m = /^\s*(\d*)\s*[dD]\s*(\d+)\s*$/.exec(String(expr||''));
  return m ? {count:..., sides:...} : null;   // count 1-20, sides 2-1000
}
function doRollExpr(ctx, expr) {   // :5485
  if (ctx.role === 'kp') { var rr = R.rollExpr(expr); ctx.act({ op:'dice.roll', expr, result:{rolls:rr.rolls, value:rr.total} }); }
  else ctx.intent(M.INTENT.DICE, { expr, direct:true, secret:!!UI_STATE.darkRoll });
}
```
- 另有 `weaponDamageExpr` `room-model.js:4403-4408`（剥掉 `半DB`/`DB` 记号）、`maxOfExpr`/`impaleDamage` `room-rules.js:925-968`（贯穿取最大值）。
- `room-rules.js:550-552` 注释逐字说明「为什么要自己解析而不复用 dice.js#parse：① parse 内部直接调 Math.random 测试无法注入 rng；② parse 会静默吞掉不认识的内容返回 0，校验场景需要明确报错」。

### B3 反击与闪避的对抗成功/失败逻辑（谁赢怎么判、伤害怎么结算、失败扣什么）—— 逐条可复制
**权威结算**：`web/js/core/room-rules.js:1001-1126` `resolveAttack(o)`；`room-model.js:5994-6204` `_opposedAttackResolve`（逐发串行）。
```js
// room-rules.js:904-909  结局枚举
var OUTCOME = { HIT:'hit', MISS:'miss', ATTACKER_WINS:'attacker_wins', DEFENDER_WINS:'defender_wins' };
// :1047-1058  结局判定（attack=攻击方 check()，defense=防守方 check()，mode='fightback'|'dodge'|'none'）
if (!attack.passed) outcome = OUTCOME.MISS;                 // ① 攻击方没成功 → 落空（无需比较）
else if (mode === 'none') outcome = OUTCOME.HIT;             // ② 无人防御 → 纯命中
else {
  compare = opposedAttack(attack, defense, { mode:mode, rng:rng });
  if (compare.winner === 'a') outcome = OUTCOME.ATTACKER_WINS;
  else if (mode === 'dodge') outcome = OUTCOME.MISS;         // ③ 闪避胜出 → 免伤
  else outcome = OUTCOME.DEFENDER_WINS;                      // ④ 反击胜出 → 反击方造成伤害
}
var attackerDeals = (outcome==='hit'||outcome==='attacker_wins');
var defenderDeals = (outcome==='defender_wins');
```
```js
// room-rules.js:489-531  opposedAttack —— 反击/闪避的「同级短路」
if (a.level > b.level) return { winner:'a', decidedBy:'level', ... };   // 成功等级高者胜
if (b.level > a.level) return { winner:'b', decidedBy:'level', ... };
var mode = normMode(o.mode);
if (mode === 'fightback') return { winner:'a', decidedBy:'mode_fightback_tie',
  reason:'反击：双方成功等级相同 → 攻击方（发起方）胜' };                  // ★反击同级→攻方胜
if (mode === 'dodge')    return { winner:'b', decidedBy:'mode_dodge_tie',
  reason:'闪避：双方成功等级相同 → 攻击方败（被躲开、免伤）' };               // ★闪避同级→攻方败
if (a.base > b.base) return { winner:'a', decidedBy:'value', ... };        // 同级比技能值
if (b.base > a.base) return { winner:'b', decidedBy:'value', ... };
for (var i=0;i<max;i++){ /* 双方各掷 D100，骰值较低者胜 */ }               // ≤10 轮
return { winner:'a', fallback:true, reason:'达到重掷上限，按规则兜底判发起方胜' };
```
- **远程降级** `room-rules.js:1022-1027`：`ranged===true` 且 `mode==='fightback'` → 强制改 `dodge`（「远程攻击：目标不能反击，按闪避处理」，`room-model.js:6323`）。
- 防守方检定**恒按常规难度** `room-rules.js:1029-1040`：`difficulty:'regular', kind:'combat'`（规则不允许对防御选难度）。

**伤害结算** `room-rules.js:1064-1093`：
```js
var exprRaw = dmgSpec.expr; var expr = (空?'0':String(exprRaw));
var armorValue = Math.max(0, num(o.armor && o.armor.value));
var impaleApplies = attackerDeals && !!o.impale &&
  (attack.level === LEVEL.EXTREME || attack.level === LEVEL.CRITICAL);   // 攻方极难/大成功 + 贯穿
if (attackerDeals || defenderDeals) {
  var main = rollExpr(expr, rng);
  var dbRoll = rollDamageBonus(db, rng);
  var raw = main.total + dbRoll.total;
  if (impaleApplies) { var imp = impaleDamage(expr, db, rng); raw = imp.raw; } // 最大伤害+最大DB+追加一次伤害骰
  damage.raw = raw;
  damage.applied = Math.max(0, raw - armorValue);      // ★护甲应用前扣除，最低 0
}
```
- 反击胜（`DEFENDER_WINS`）时**优先用 `o.defense.damage`**（`room-rules.js:1065`），但老 APP UI 从不传 → 用 `o.damage`（= 攻击方武器伤害式）。

**失败/扣什么（副作用）** `room-model.js:6169-6191`：
```js
if (attackerWins || defenderWins) {
  var applied = Math.max(0, dmg.applied);
  if (defenderWins) {          // ★反击命中：伤害打在【攻击方】身上
    if (attacker.side === 'pc' && attacker.seat)
      out = out.concat(this._opposedDamagePlayer(attacker.seat, applied, '对抗反击'));
    else if (attacker.actorId)
      out = out.concat(this._opposedDamageMonster(attacker.actorId, applied));
  } else {                      // 攻方胜：打防守方
    if (defender.side === 'pc' && defender.seat)
      out = out.concat(this._opposedDamagePlayer(defender.seat, applied, '武器对抗'));
    else if (defender.actorId)
      out = out.concat(this._opposedDamageMonster(defender.actorId, applied));
  }
}
```
- `_opposedDamagePlayer` `room-model.js:6412-6442`：`applyHpChange(m, -amount, reason)` → `settleWounds`（**死亡/重伤/昏迷判定**）+ 同步战斗槽 `public.hp` / `down` / `state`（`_syncBodyToCombatSlot`）+ `EVT.TURNSTATE`。
- `_opposedDamageMonster` `room-model.js:6449-6465`：`pub.hp = Math.max(0, pub.hp - amount)`，`if (pub.hp<=0){ pub.down=true; pub.state='dead'; }` + `EVT.ACTOR`。
- **闪避成功 / MISS**：`damage=null`，**不造成伤害**（`room-model.js:6335` 注释「失败 / 被躲开（damage=null）不显示伤害行」）；`buildAttackSummary` `room-rules.js:1146-1149` 文案「→ 闪避成功，攻击被躲开，未造成伤害」/「→ 攻击落空，未造成伤害」。
- 结果卡文案 `room-model.js:6307-6360` `_opposedCheckPayload`：`reactionText = 反击|闪避|不防御|无法反抗`；`outcome==='miss'` → 「→ 落空 / 被躲开：未造成伤害」；`defender_wins` → 「→ X 胜（反击命中）」+「反击命中：由 防守方名 造成 N 点伤害（伤害骰 raw，护甲 armor）」；`attacker_wins/hit` → 「→ X 胜」+「命中：伤害 expr+db=raw，护甲 armor，实扣 applied」。

### B4 「武器对抗」在哪 / 和「攻击对抗」是否同一个东西
**结论：老 APP 里「⚔ 战斗对抗」按钮 与「⚔ 武器对抗」弹层是同一个玩家功能；KP「⚔ 攻击对抗」是另一条 KP 直发链路。老 APP 没有两个并列的玩家入口。**
- 玩家工具按钮 `room-panels.js:5434-5441`：`text:'⚔ 战斗对抗'`，`disabled: !_myTurnNow || opLocked`，`onclick: playerOpposedSheet(ctx)`。
- `playerOpposedSheet` `room-panels.js:4909-4994`：函数注释 `:4909`「玩家发起**武器对抗**（选武器 + 选怪 → 推送 KP）」，弹层标题 `:4992` `'⚔ 武器对抗'`，门禁 `:4912`「只有玩家能发起武器对抗」+ `:4917` 轮次校验。
- 载荷 `:4979-4986`：
```js
ctx.intent(M.INTENT.OPPOSED, {
  phase: 'request',
  weapon: { name: w.name, skill: w.skill, damage: w.damage, pierce: w.pierce },
  db: (me.sheet && me.sheet.db) || '0',
  targetId: target.id, targetName: target.name,
  shots: shots,
  note: M.cleanText(noteI.value, 80)
});
```
- 状态机（P16 §1 已校验，`room-model.js:6494` `opposedRequest`）：`phase:'request'` → `await_kp` → KP 裁定 `opposedResolveSheet`（`:4997`）→ `await_target`（`:5076` `playerTargetSheet`）→ `resolved`。
- KP 端 `check.opposed` 直发入口 `kpAttackSheet`（`:4752`）**不走 INTENT.OPPOSED**，直接 `ctx.act({op:'check.opposed', attack:true, attacker, defender, weapon, ...})`（`:4875-4897`）。
- 死代码 `plBottomBar` `room-panels.js:3220-3270`（0 调用方）里另有 `['⚔ 战斗对抗', playerOpposedSheet]` 和 `['⚔️ 战斗检定', skillCheckSheet(ctx,'combat')]`（`:3245`、`:3253-3254` 注释明确已摘除、玩家从未见过）—— 施工单**不要**据此认为存在两个入口。
- 结论：用户说「武器对抗和战斗对抗重复，删掉武器对抗」—— 在老 APP 视角成立（本来就是同一个 `playerOpposedSheet`）；新 APP 若真并列了两个按钮，删其一即可，**但务必保留 `INTENT.OPPOSED` / `opposed()` 整条链路**（那就是玩家战斗对抗本身，删了等于把功能删没了）。

### B5 对抗载荷字段名对照（应 researcher-kp-p17：新 APP `sheet_opposed.dart` 字段对不上 domain）
老 APP `web/js/ui/room-panels.js` 全部 `check.opposed` / `INTENT.OPPOSED` 提交点（已 Grep 全量核对，共 4 + 2 处）：
| # | 场景 | 位置 | 载荷（**可复制**） |
|---|---|---|---|
| 1 | 通用对抗（KP 直发） | `:4738-4741` | `{ op:'check.opposed', aSeat, aSkill, aBase, bSeat, bSkill, bBase, secret }` |
| 2 | 攻击对抗（KP 直发） | `:4875-4897` | `{ op:'check.opposed', attack:true, attacker:{side,seat,actorId,name,skill,value,ranged}, defender:{side,seat,actorId,name,skill,value,reaction}, weapon:{name,damage,pierce,db}, shots, armor:{value}, secret }` |
| 3 | KP 裁定玩家申请 | `:5060-5065` | `{ op:'check.opposed', reqId, attack:true, noDefense, defender:{reaction,value}, armor:{value}, malfType, secret }` |
| 4 | 拒绝玩家申请 | `:5107` | `{ op:'check.opposed', reqId, cancel:true }` |
| 5 | 玩家发起武器/战斗对抗申请 | `:4979-4986` | `INTENT.OPPOSED { phase:'request', weapon:{name,skill,damage,pierce}, db, targetId, targetName, shots, note }` |
| 6 | 玩家胜后选伤害目标 | `:5087` | `INTENT.OPPOSED { phase:'target', targetId }` |

**对照结论（施工单直接可用）**：
- 老 APP **没有** `kind:'general'`（全库 Grep 0 命中）—— 通用/攻击靠 `attack:true` 有无来分（`room-model.js:5841` `if (p.attack || p.cancel)`），不是 `kind`。
- 老 APP **没有裸 `base` 字段**：通用用 `aBase`/`bBase`，攻击用 `attacker.value`/`defender.value`，玩家申请用 `weapon`+`db`。`base` 只是 `rules.check()` 的内部参数名（`room-rules.js:286`），**不是协议字段**。
- 老 APP `check.request` 的 `difficulty` 与 `check.opposed` 的 `difficulty` 是**同一个大写三档**（`REGULAR/HARD/EXTREME`）；`aBonus/aPenalty/bBonus/bPenalty` 是 `checkOpposed` `:5863-5868` **模型侧预留接收**的字段，`room-panels.js` 的通用对抗表单**从不发送**（`difficulty` 缺省 → 模型 `|| 'REGULAR'`）。→ 新 APP domain 期望这些字段是对的（把老 APP 模型侧预留做全），但「照老 APP UI 抄」抄不到，需按模型口径补。
- `reqId` 仅出现在「玩家申请→KP 裁定」链路（#3/#4），对应 `state.opposed` 的待办 id；直发链路（#1/#2）无 `reqId`。
- `noDefense`（「无法反抗」`:5008-5017`）→ 跳过对抗判定、攻击方自动成功直接进伤害（`room-model.js:6041-6044`、`:6158-6160`）。

### B6 `pc:`/`mo:` 前缀归属 与 `secret` 可见性裁剪（应 researcher-kp-p17 二次补查）

**B6-1 `pc:` / `mo:` 前缀 —— UI 下拉值，提交前剥掉，模型侧只有 `mo:` 有一处宽松兜底**
全库 ERE 复核（`grep -rnE "pc:|mo:"`）：
- `pc:` 在 **`core/` 0 命中**，只在 `ui/room-panels.js` 3 处：`:4688`（注释）、`:4761`、`:4769`（= `kpAttackSheet` 的 `attPool`/`defPool` 里 `selectCtl` 的 option `value: 'pc:'+m.seat`）。
- `mo:` 在 UI 3 处（`:4687` 注释、`:4763`、`:4767`，option `value: 'mo:'+a.id`）+ `core/room-model.js:3820-3822`（`_resolveActorSkill` 的宽松解析）：
```js
// :3818-3822  _resolveActorSkill 剥前缀（通用对抗 check.opposed 非 attack 路径）
if (raw.slice(0,2) === 'p:')  { hint='pc';    raw = raw.slice(2); }
else if (raw.slice(0,2) === 'a:') { hint='actor'; raw = raw.slice(2); }
else if (raw.slice(0,3) === 'mo:') { hint='actor'; raw = raw.slice(3); }  // v2.5.0 放宽
```
- **前缀从不进模型载荷**：`kpAttackSheet :4875-4890` 用 `optOf(attPool, aSel.value)` 按 `pc:`/`mo:` value 找回选项对象，再构造 `attacker.seat = ao.mem.seat`（**裸 seat**）、`attacker.actorId = ao.mon.id`（**裸 id**）、`side:'pc'|'monster'` —— 前缀只用于 `optOf()` 查表。模型 `_resolveOpposedSide :5956-5975` **按 `spec.side` 分派**（`'pc'` → `roster.get(seat)` + `_skillBaseOf` 读人物卡；`'monster'/'npc'` → 手输 1–100），**不看前缀**。
- `p:`/`a:` 才是 `genericOpposedSheet`（通用对抗 `check.opposed` 非 attack 路径）真正在 `aSeat`/`bSeat` 里传的复合值，由 `_resolveActorSkill :3816-3822` 剥前缀分派；`mo:` 是 v2.5.0 为「旧客户端/其他调用方」加的宽松兜底（注释 `:3820`）。**无前缀则两者都试**。
- **⚠️ `_resolveActorSkill` 不认 `pc:`**：若把 `pc:s1` 当 `aSeat` 传进去，会落到「无前缀两者都试」→ `roster.get('pc:s1')` 失败 + `_findActorSlot('pc:s1')` 失败 → `ok:false`「找不到对抗单位」。这是**两套前缀体系**（攻击对抗下拉 value vs 通用对抗 `aSeat`/`bSeat` 复合值）不能混用的根因。
- 施工单结论：`pc:` 只是 UI 选项值，**别为新 APP domain 写 `pc:` 解析**；需要 `resolveActorSkill` 支持的是 `p:`/`a:`/`mo:`（researcher-kp-p17 核的新 APP `:1634` 已支持三者，口径一致）。

**B6-2 `secret` 在对抗链路的裁剪口径 —— 集中在 `_emitOpposedCheck`，结果卡二选一**
- UI 三个复选框，label 均为「秘密对抗（仅 KP 可见结果 / 仅 KP 可见）」：`room-panels.js:4724`（通用对抗）、`:4863`（攻击对抗）、`:5050`（KP 裁定玩家申请）；载荷 `secret: !!secretChk.checked` 分别在 `:4741`、`:4896`、`:5065`。
- 模型 `web/js/core/room-model.js:5801-5824` `_emitOpposedCheck(out, payload, secret)`（注释 `:5801-5806` 逐字「非秘密 → EVT.CHECK PUBLIC（全体现行 + 进公共日志，行为完全不变）；秘密 → 完整结果经 EVT.PRIVATE 单发 KP… 公共记录只落一条**脱敏** LOG（不含骰值 / 胜负 / 伤害）」）：
```js
if (secret) {
  this._push(out, this.emit(EVT.PRIVATE, {
    title:'秘密对抗', kind:'opposed', text: payload.summary || '（秘密对抗）',
    at: payload.at || this.now()
  }, VIS.SEAT, HOST_SEAT));                 // 完整结果单发房主(KP) 座位 → 进 KP 私密信息
  this._push(out, this.emit(EVT.LOG, {
    seat:'', text:'KP 秘密进行了一次对抗检定', kind:'check'
  }, VIS.PUBLIC));                            // 公共只留脱敏行（无骰值/胜负/伤害）
} else {
  this._push(out, this.emit(EVT.CHECK, payload, VIS.PUBLIC));
}
```
- **全链路 4 类调用点（`secret` 从头传到尾、跨 `await_target` 暂存不泄漏）**：
  | 位置 | 传参 |
  |---|---|
  | `checkOpposed`（通用对抗）`:5884-5896` | `var secret = !!p.secret; this._emitOpposedCheck(out, {...}, secret)` |
  | `_opposedAttackResolve` 逐发结果卡 `:6205-6207` | `!!p.secret` |
  | `canDefer` 待选目标结果卡 `:6229-6232` | `!!p.secret` |
  | **暂存进 `state.opposed`** `:6242-6244` | `this.state.opposed = Object.assign({}, st, { phase:'await_target', secret: !!p.secret, weapon, db, armor, pierce, dmgExpr, monsters, win, ... })`（注释 `:6241`「secret 一并暂存 → 选怪后的最终伤害卡也走「秘密」通道，不泄漏给玩家」） |
  | 最终伤害卡 `_opposedPlayerTarget` `:6636-6651` | `}, !!st.secret)` —— 从 `await_target` 暂存态继承 |
- `resolveAttack` 另把 `secret: !!o.secret` 透传进 `check()`（`room-rules.js:1015`），`check()` 结果带 `secret` 字段（`:305`）—— 但**真正的可见性裁剪只在 `_emitOpposedCheck`**，规则层不负责。
- **⚠️ 未逐条核实的边界（如实标注）**：`secret` 只包裹**结果卡**（`EVT.CHECK` / `EVT.PRIVATE` / 脱敏 `EVT.LOG`）；`_opposedDamagePlayer`/`_opposedDamageMonster` 的 `EVT.ACTOR`/`EVT.TURNSTATE` HP 同步、以及 `applyHpChange → stateApply` 的伤害副作用走**另一条 emit 链，不在 `_emitOpposedCheck` 范围内**，本次未逐条核实其可见性。施工单若实现「秘密对抗」，建议单独验证「秘密对抗造成伤害时 HP 变化是否也会泄漏到公共流」。

---

## C. KP 定向指令（逐按钮载荷字段名）

**面板本体** `web/js/ui/room-panels.js:2393-2416` `kpDirectivesCard(ctx)`，标题 `'定向指令（指定玩家 · 直接生效 · 无需同意）'`；挂在 KP 工具「组④」`:5733-5734`（注释「保留独立卡，**9 项顺序不变**」）。
**选人器** `pickTargetPlayer` `:2062-2095`：**强制选目标**（`opts.skip` 过滤），顶部固定「👥 全部玩家」→ `onPick({ seat:'*', all:true })`，其余每行一个玩家（`m.seat`、`m.charName||m.nickname||'玩家'`）；`targetBlocked(m)` `:2287` = 已撕卡（死亡/永久疯狂）不可选；SAN 类用更严的 `sanBlocked` `:2274`。
**权限** `room-model.js:223-230` POLICY：全部 `roles:['kp']`（`'sheet.damage'`/`'sheet.sancheck'`/`'sheet.tempstatus'`/`'sheet.item'`/`'dice.dark'`/`'sheet.sanloss'`），`confirm:null`（玩家发同 op 必被拒）。

| # | 按钮文案（`toolBtn` 第一参） | 处理函数 | 载荷完整字段名（**可复制**） | 输入项 |
|---|---|---|---|---|
| 1 | `💥 造成伤害` | `dmgForPlayer` `:2110-2134` | `ctx.act({ op:'sheet.damage', seat:m.seat, amount:amt, kind:M.cleanText(kindI.value,20) })` `:2124-2126`；`amt = parseInt(amtI.value,10)`，`amt<=0` 拦截 | 伤害值 `amtI`(text,默认'1')、类型 `kindI`(text,可空, 如 物理/火焰) |
| 2 | `🌫 临时状态` | `tempForPlayer` `:2138-2158` | `{ op:'sheet.tempstatus', seat:m.seat, text:t }` `:2150`；`t = M.cleanText(tI.value,60)`，空则拦 | 状态文本 `tI`(text,maxlength 60, 占位「如：中毒 3 轮 / 流血」) |
| 3 | `🎒 给物品` | `itemForPlayer` `:2162-2188` | `{ op:'sheet.item', seat:m.seat, name:nm, qty:Math.max(1,parseInt(qI.value,10)||1), note:M.cleanText(noteI.value,60) }` `:2178-2180`；`nm` 必填 | 名称 `nI`(40)、数量 `qI`(默认'1')、备注 `noteI`(60) |
| 4 | `🧠 SAN Check` | `sanForPlayer` `:2327-2369` | `{ op:'sheet.sancheck', seat:m.seat, okLoss:ok, loss:fail, reason:M.cleanText(reasonI.value,40) }` `:2359-2361`；默认 `okLoss:'0'`、`loss:'1D6'` | 成功损失 `okI`、失败损失 `failI`、原因 `reasonI`；`validLossSide` `:2053-2060` 校验「纯数字或 `R.parseExpr(t).ok`」 |
| 5 | `🕶 暗骰` | `darkRollSheet` `:2372-2391` | `{ op:'dice.dark', sides:spec.sides, count:spec.count, bonus:0, reason:M.cleanText(reasonI.value,40) }` `:2384-2385` | 骰式 `exprI`(默认'1D100')、用途 `reasonI`；`parseDiceExpr` 只认 NDM |
| 6 | `🌀 追加理智损失`（= 用户「SAN 大失败追加」） | `sanLossForPlayer` `:2588-2612` | **单人**：`ctx.act({ op:'sheet.sanloss', seat:m.seat })` `:2608`（**无任何数值**）；**全体**：`players.forEach(mm => ctx.act({op:'sheet.sanloss', seat:mm.seat}))` `:2595` | **无**（一键）。模型 `sheetSanLoss` `room-model.js:5517-5558` 支持可选 `p.dice`（默认 `'1D10'`）、`p.reason`，但 UI 从不传 |
| 7 | `💊 治愈疯狂`（= 治愈疯狂状态） | `cureForPlayer` `:2419-2434` | `ctx.act({ op:'madness.cure', seat:mm.seat })` `:2425`/`:2430` | **只需选目标**，无数值 |
| 8 | `🩹 治愈伤势`（= 治愈重伤） | `cureWoundForPlayer` `:2438-2454` | `ctx.act({ op:'sheet.healwound', seat:mm.seat })` `:2443`/`:2450`；单人前置 `isMemberWounded(m)` `:2447` | **只需选目标**，无数值 |
| 9 | `🚑 急救 / 医学` | `aidForPlayer` `:2464-2502` | `{ op:'aid.apply', seat:hv, targetSeat:tv, skill:skill }` `:2494`；`skill ∈ {'急救','医学'}`（`:2477-2480`、`:2493`） | **施救者**下拉 + **施救目标**下拉（均纯玩家 seat）+ 技能下拉；**无「检定数值」输入**（权威端 `_skillBaseOf(healer, skill)` 取人物卡技能值，见 P16 §7.3 `room-model.js:4882`） |

**补充：用户提到的「精神分析检定数值」** —— 老 APP **没有**这个 KP 定向指令按钮。精神分析是**玩家侧**「🩺 急救 / 医疗 / 精神分析」`aidPlayerSheet`（`:2515-2585`）里的第三个技能选项，载荷 `ctx.intent(M.INTENT.ACT, { op:'aid.psycho', seat:me.seat, targetSeat:tv })` `:2572`（**无数值输入**），走 `confirm:'kp'` 审批；KP 侧对应的是「待你确认」卡 `OP_LABEL['aid.psycho'] = '精神分析'` `:5771`，富详情 `:5806-5808`「X 对 Y 进行精神分析」。

**「SAN 大失败追加」—— 多次大失败记录 / KP 选哪一次：老 APP 完全没有**
- UI `sanLossForPlayer`（`:2587-2612`）只有 `op:'sheet.sanloss'`，注释逐字「**KP 一键入口，掷 1D10**」；按钮副标题 `:2403`「SAN 大失败后按规则书追加（掷 1D10）」。
- 模型 `sheetSanLoss` `room-model.js:5509-5558`：`var dice = cleanText(p.dice,12) || '1D10';` `:5520` → `rules.rollExpr(dice, this.rng)` `:5533` → `loss` → `stateApply(...{status:{currentSAN: after}})` + `_afterSanLoss`；LOG 文案 `:5550` `'who + ' SAN 大失败，按规则书追加理智损失：' + dice + ' = ' + loss + '，SAN ' + san + ' → ' + after'`。
- SAN Check 大失败时 **只写一句提示、不自动扣、不落库**：`room-model.js:5710-5713` `fumbleNote = '　·　⚠ 大失败：KP 可按规则书追加 1D10 理智损失（KP 工具 → 🧾 SAN 大失败追加，不自动扣）'`。
- **全库 Grep `sanHistory|pendingSan|sanCheckHistory|大失败.*记录|选.*大失败` 0 命中**；`state` 里唯一与 SAN 损失相关的持久化字段是 `m.sheet.sanLoss`（**SAN 上限永久减损**，数值 0-99，`room-model.js:4034`、`:7314`），**不是「每次大失败的损失值」列表**。
- → **用户「玩家可能 sc 大失败好几次，KP 要能选追加哪一次大失败的数值」= 全新需求**，需要新 APP 自己设计「大失败历史」数据结构 + KP 选择 UI。可借力的现成钩子：`sheet.sanloss` 载荷已有可选 `dice` / `reason` 字段（模型已支持传入任意骰式/数值），但 UI 未暴露。

---

## D. 玩家申请入口（申请治愈疯狂 / 申请治愈重伤）

**位置**：`web/js/ui/room-panels.js` `selfStateSheet(ctx)`（状态管理弹层）内，两个并排的 `.btn.sm.ghost.block`；弹层由 `plCharacterCard` 的「📝 状态管理（自行修改）」按钮打开（`:2809-2816`）。
```js
// :3784-3803  申请治愈疯狂
el('button.btn.sm.ghost.block', {
  text: '💊 治愈不定疯狂（需 KP 同意）',
  onclick: function () {
    var meNow = findMe(ctx);
    var mentalNow = (meNow && meNow.sheet && meNow.sheet.mental) || [];
    if (mentalNow.indexOf('不定疯狂') < 0 && mentalNow.indexOf('不定疯狂（症状消失）') < 0) {
      global.UI.toast('当前没有「不定疯狂」状态', 'err'); return;        // 前置：权威端实时状态
    }
    global.UI.confirm('向 KP 申请治愈你的不定疯狂？\nKP 同意后「不定疯狂」状态才会解除。',
      { okText:'申请治愈' }).then(function (ok) {
      if (!ok) return;
      ctx.intent(M.INTENT.ACT, { op: 'madness.cure' });                  // :3799  ★无 seat 字段
      global.UI.toast('已向 KP 发起治愈申请，等待同意', 'ok');
      global.UI.closeAllSheets();
    });
  }
}),
// :3806-3826  申请治愈重伤
el('button.btn.sm.ghost.block', {
  text: '🩹 治愈伤势（需 KP 同意）',
  onclick: function () {
    var meNow = findMe(ctx);
    if (!isMemberWounded(meNow)) { global.UI.toast('当前没有需要治愈的伤势', 'err'); return; }
    global.UI.confirm('向 KP 申请治愈你的伤势？\nKP 同意后「重伤 / 濒死 / 昏迷」状态才会解除。',
      { okText:'申请治愈' }).then(function (ok) {
      if (!ok) return;
      ctx.intent(M.INTENT.ACT, { op: 'sheet.healwound' });                // :3821  ★无 seat 字段
      global.UI.toast('已向 KP 发起治愈伤势申请，等待同意', 'ok');
      global.UI.closeAllSheets();
    });
  }
}),
```
- **载荷**：`INTENT.ACT` + `{ op:'madness.cure' }` / `{ op:'sheet.healwound' }`，**不带 seat**（由 intent 的 seat 隐式确定发起者；模型 `room-model.js:1655` 注释「用**原发起者**执行（而不是确认者）」）。
- **KP 侧怎么收到**：
  1. POLICY `room-model.js:198` `'madness.cure': { roles:['player','kp'], confirm:'kp' }`、`:269` `'sheet.healwound': { roles:['player','kp'], confirm:'kp' }` → 进 `host.pending` 队列（`q.need==='kp'`）。
  2. 全局操作锁白名单放行这两个 op（`room-model.js:1353-1357`，昏迷/疯狂也能申请）；重复提交拦截 `:1686`「你的治愈申请已在等待 KP 同意，请勿重复提交」；受理回执 `:1695`「已向 KP 发起治愈申请，等待同意」。
  3. KP 工具「待你确认」卡 `kpPanel` `room-panels.js:5673-5699`：`pendings.filter(q => q.need==='twice'||q.need==='kp')`，显示 `opLabel(q.op) + ' · ' + 发起者`，`OP_LABEL` `:5768-5769` = `'madness.cure':'玩家申请治愈不定疯狂'`、`'sheet.healwound':'玩家申请治愈伤势'`；按钮「确认」→ `ctx.side.confirmAct(q.op, true)`、「取消」→ `false`（`:5694-5695`）。
  4. 另有 `stateRequestCard` `:5813-5835`（「调整玩家状态」，走 `state.request` + 玩家 CONSENT，**不是**这两条申请的落点，别混）。
- **⚠️ 与 F 的交互（重要）**：这两个按钮在 `selfStateSheet` 内，而打开它的「📝 状态管理」按钮 `disabled: opLocked`（`:2811`）—— 昏迷/疯狂时**打不开状态管理弹层**；模型白名单虽放行 `madness.cure`/`sheet.healwound` intent，但 UI 入口被整体操作锁挡住。`:3809` 注释声称「该按钮在昏迷时也必须可点」是**设计意图与实际入口实现的矛盾**，施工单需拍板（见歧义点 6）。

---

## E. 玩家侧「更多工具」菜单

**结论：老 APP 无字面「更多工具」弹层，也无独立「更多工具」按钮**（全库 `更多工具` Grep 0 命中）。唯一含「更多」的是车卡器首页 `web/js/app.js:814-817` 的 `button.char-more`（`title:'更多操作'`，`onclick: charMenu(c)`）—— 那是「我的角色」列表里每张卡的菜单，**不是房间玩家侧工具**。

老 APP 玩家房间侧工具分两处：
**① `.gp-quick` 快捷操作行** `web/js/ui/room-ui.js:4188-4267` `paintGameToolbar()` 的 `else`（玩家）分支 `:4237-4259`：
| 条目 | 出处 | disabled |
|---|---|---|
| `📋 人物卡查看` → `cardImageSheet(me)` | `:4238-4245` | **无**（不接 opLocked） |
| `✏️ 我的手绘板` → `RoomPanels.playerBoardCard(...)` | `:4246-4251` | **无**（不接 opLocked） |
| `⤢ 重置缩放` → `resetZoom()` | `:4257-4259` | 无 |
| 缩放百分比 → `openZoomSheet()` | `:4260-4265` | 无 |

**② `diceBar` 的 `.dice-extra` 扩展按钮组**（真实玩家工具栏，`room-panels.js:5322-5472`，挂载见 `room-ui.js:4268`/`:4295`）：主行 `D100` + 奖惩骰 + `🕶 暗骰` + `D4/D6/D8/D10`（`:5408-5420`）；扩展组 `:5442-5469`：
```js
[
  ['🎯 技能检定', () => skillCheckSheet(ctx,'skill')],
  ['🎲 自定义骰子', () => customDiceSheet(ctx)],
  null,                                        // ← 占位：插入「⚔ 战斗对抗」（仅玩家）
  ['🧠 SAN Check', () => sanCheckSheet(ctx)],
  ['🩹 临时状态', () => tempStateSheet(ctx)],
  ['🩺 急救/医疗/精神分析', () => aidPlayerSheet(ctx), 'pl'],       // p[2]==='pl' 仅玩家
  ['🎒 物品道具', () => itemsSheet(ctx), 'pl'],                     // 仅玩家
  ['📖 规则参考', () => rulesSheet(ctx)]
].forEach(function (p) {
  if (p === null) { if (isPlayer) extra.appendChild(opposedBtn); return; }   // :5466
  if (p[2] === 'pl' && ctx.role !== 'player') return;
  extra.appendChild(el('button.dice-small', { text:p[0], disabled: isSpec || opLocked, onclick:p[1] }));  // :5468 ★
});
```
- `opposedBtn` `:5434-5441`：`text:'⚔ 战斗对抗'`，`disabled: !_myTurnNow || opLocked`，`onclick: playerOpposedSheet`（仅玩家、仅战斗、仅自己行动轮次）。
- **昏迷/疯狂时是否仍可点开**：`.dice-extra` 全部 8 个条目 + `opposedBtn` 都接 `disabled: isSpec || opLocked`（`:5468`、`:5436`）；D100/暗骰/D4-D10 同款（`:5333`/`:5403`/`:5417`）→ **全部禁用、点不开**。`.gp-quick` 快捷行 3 个按钮**未接 opLocked**（`room-ui.js:4238-4259` 无 `disabled`）→ **仍可点**。
- CSS：`web/css/app.css:3271-3275`（`.game-page.gp-pl .gp-toolbar .dice-bar > .dice-extra { display: contents; }`，扩展组用 `order:3` 排在主行后）、`:1943`（`.dice-extra { display:flex; flex-wrap:wrap; gap:5px; }`）—— **老 APP 是「常驻平铺」不是弹层**，没有「展开/收起」开关。

---

## F. 昏迷 / 疯狂状态锁定（判定字段 + disabled 接入方式）

### F-1 判定所用字段（**精确 state 键**）
成员对象 `m` 的 `sheet`（权威角色卡）上：
| 状态 | 字段 | 判定函数（文件:行号） |
|---|---|---|
| **昏迷** | `m.sheet.status.unconscious === true`（布尔标记）；兼容旧数据 `status.body === '昏迷'` | `bodyViewOf` `room-panels.js:2232-2239`：「死亡 > dying > unconscious > body」；`isMemberUnconscious` `:2268-2271` = `bodyView ∈ {'昏迷','濒死'}`（**昏迷或濒死都算**） |
| **濒死** | `m.sheet.status.dying === true` | 同上 `bodyViewOf`；`WOUND_BODY = ['重伤','濒死','昏迷']` `:2251` |
| **身体单值** | `m.sheet.status.body ∈ {'正常','轻伤','重伤','死亡'}` | `:2224-2225` 注释冻结 |
| **已撕卡** | `body === '死亡'` 或 `m.sheet.mental` 含 `'永久疯狂'` | `isMemberRippedU` `:2216-2220`（**判死只认 body==='死亡'，绝不用 hp<=0**） |
| **疯狂发作中** | `m.sheet.mental`（数组）含 `'临时疯狂'` 或 `'不定疯狂'`；`'不定疯狂（症状消失）'` **不算** | `isMemberMadActive` `:2198-2205` |
| 精神状态可选取值 | `MENTAL_OPTS = ['正常','临时疯狂','不定疯狂','不定疯狂（症状消失）','疯狂症状','永久疯狂']` | `:3632` |

**整体操作锁（UI）** `room-panels.js:2298-2300`：
```js
function playerOperationLocked(m) {
  return isMemberUnconscious(m) || isMemberRippedU(m) || isMemberMadActive(m);
}
```
```js
// :2289-2295 注释逐字：「昏迷 / 濒死（isMemberUnconscious）或 已撕卡（isMemberRippedU）或
//   疯狂发作中（isMemberMadActive）。锁住后玩家不能操作任何东西，
//   唯一例外是「⏩ 推进 1 轮」（模型 intent 白名单放行 madness.advance）。」
```
**同判据的权威端全局 intent 锁** `room-model.js:1326-1370` `Host.prototype.intent`：
```js
var locked = !isHost && mem &&
  (memberRipped(mem) || memberInBout(mem) || this._isUnconscious(mem) || this._isDying(mem));  // :1344-1345
if (locked) {
  var passSelf = (op === INTENT.CHAT || op === INTENT.SYNC || op === INTENT.READY ||
                  op === INTENT.STATE_SYNC || op === INTENT.CHAR ||
                  (op === INTENT.ACT && p.op === 'madness.advance') ||      // 推进 1 轮
                  (op === INTENT.ACT && p.op === 'madness.cure') ||         // 申请治愈不定疯狂
                  (op === INTENT.ACT && p.op === 'sheet.healwound'));        // 申请治愈伤势
  if (!passSelf) {
    // :1363-1367 拒绝文案：
    //   撕卡 → '你的角色已死亡或永久疯狂（撕卡），只能通过聊天框交流'
    //   昏迷/濒死 → '你的角色正处于昏迷/濒死，无法进行该操作；可申请治愈伤势或请队友施救'
    //   疯狂 → '你的角色正处于疯狂发作中（临时/不定疯狂），只能「推进 1 轮」或申请治愈，其他操作暂不可用'
    return out;
  }
}
```

### F-2 `disabled` 接入方式（逐处）
`room-panels.js:5325-5329`：`var opLocked = me ? playerOperationLocked(me) : false;`（KP `findMe` 返回 null → 不参与锁）。
```js
:5333  D100           disabled: (isSpec || opLocked)
:5403  🕶 暗骰         disabled: (isSpec || opLocked)
:5417  D4/D6/D8/D10   disabled: (isSpec || opLocked)
:5436  ⚔ 战斗对抗      disabled: !_myTurnNow || opLocked
:5468  .dice-extra 全部 8 项  disabled: isSpec || opLocked
:2811  📝 状态管理（自行修改）  disabled: opLocked        ← plCharacterCard 内
```
**唯一保留（不受 opLocked 限制）**：`⏩ 推进 1 轮` `room-panels.js:2828-2845`，`disabled: _advanceBusy`（仅防连点冷却，`:2771-2837`，`_ADVANCE_COOLDOWN = 400`ms），点击 `ctx.intent(M.INTENT.ACT, { op:'madness.advance' })` `:2834`；注释 `:2821`「该按钮**不受整体操作锁限制**（昏迷角色也能点）」。它挂在 `plCharacterCard`（玩家信息卡 `room-panels.js:2779`），**不在 diceBar**。
**模型白名单另放行**：聊天 / `madness.cure` / `sheet.healwound`（见上），但 UI 上「状态管理」入口被 `disabled` 挡住（见 D 的 ⚠️）。

### F-3 与用户诉求的差异
用户要求「昏迷/疯狂时**只能点「推进 1 轮」和「更多工具」，其它全禁**」——老 APP：
- 保留清单 = **只有「⏩ 推进 1 轮」**（+ 模型层的聊天/申请治愈 intent 白名单，但无 UI 入口）；
- **「更多工具」（即 `.dice-extra`）在老 APP 是被 `opLocked` 禁用的一方**（`:5468`）；
- 老 APP 锁覆盖 **4 态**（昏迷/濒死/已撕卡/疯狂发作中），用户只提 **2 态**（昏迷/疯狂）。
→ 若照用户做：需 `playerOperationLocked` 判据收窄 + 把「更多工具」从 disabled 名单里摘出（且要保证其条目本身仍不可执行实质操作，否则与模型 intent 锁冲突）。见歧义点 5/6。

---

## G. 战斗行动顺序（KP 自定义调整 / 插队）

**结论：老 APP 2.13.13 无此功能，属新需求。**（用户「有的怪物可能有插队的能力」）

**搜过哪些文件/关键词**（全 `web/**`）：`manualOrder`、`combat.reorder`、`order.*splice`、`splice.*order`、`moveUp/moveDown`、`上移/下移/拖拽/置顶/插队/调整.*顺序/输入序号`、`combat.set` 的 UI 调用 —— 逐一核对如下：
1. **POLICY 里没有任何 reorder op** `room-model.js:205-217`：战斗动作只有 `'combat.set'`、`'combat.start'`、`'combat.next'`、`'combat.actor'`、`'combat.enqueue'`、`'combat.attack'`、`'combat.damage'`、`'combat.end'`、`'combat.roll'`、`'combat.pool.set'`、`'combat.prepare'`。
   - `'combat.set'` `:206` / 处理 `:1717-1718`：`this.emit(EVT.COMBAT, { combat: p.combat }, VIS.PUBLIC)` —— **整包替换 combat 状态的内部/存档通道，全库 UI 0 调用**（Grep `combat.set` 仅命中 `room-model.js:206`、`:1717`），不是给 KP 用的「调整顺序」界面。
   - `room-model.js:630`（`case EVT.TURN`）、`:674`（`case EVT.TURNSTATE`）里的 `if (p.order) state.combat.order = clone(p.order)` 是**事件归约**（`nextTurn` / `_reorderTail` `:3520` 内部写回），非用户 op。
2. **排序只能开局自动排**：`combatStart` `room-model.js:2461-2560` → `CocRules.initiativeOrder()`（`room-rules.js:822-860`）：`effDex = dex + (readyFirearm?50:0)`，`manualOrder` 越小越靠前、未指定的排手工项之后仍按 DEX 降序、多行动展开多槽（`:2500-2513`、`:2518-2547`）。UI 文案 `room-panels.js:4153`「已按 DEX 自动排序」、`:4167`「系统按 CoC 7th 规则自动排行动顺序」、`:4078` 注释 —— **均无人工调整入口**。
3. **`manualOrder` 字段存在但无 UI 录入**：`room-rules.js:843-854`、`:831` 注释 `@param actors [{id,name,dex,readyFirearm,actionsPerRound,manualOrder}]`；`room-model.js:2431-2445`（兜底排序）、`:2506`、`:2531-2532`（槽 `manual`/`manualOrder`）、`:2644`/`:2679`（enqueue 时恒 `manualOrder:null`）。**全部在 `core/`，`ui/` 下 0 命中** —— 没有输入序号/上下移控件。
4. **战斗面板按钮** `kpCombatPanel` `room-panels.js:1695-1806`（P10 §B3 已校验）：每行只有 `▶`(`combat.next`) 与 `💥`(`damageSheet`)，底部「下一个行动 ▶ / ＋ 加单位 / 结束战斗」；**无上移/下移/拖拽/改序号**。
5. **`combat.enqueue` 只追加到队尾**：`room-model.js:2572-2685`，注释 `:2575`「**只追加**，绝不重置 turn/round 或覆盖其它槽」；实现 `order.push({...})` `:2634`、`:2669` —— 这是「把新单位拉进战斗」，不是「插队」。
6. `initiativeBar` `room-panels.js:372-400` 是**只读**行动顺序条（`.init-slot` 状态 `.cur/.done/.down`），`pointer-events` 多数为 none（`P16 §6` 已证），不可交互。

→ 施工单：新 APP 若要「怪物插队」，需**自造 op + UI**（如 `combat.reorder` / `combat.order.set` + 上移/下移/拖拽/输入序号），并明确「插队后的 `turn` 游标、已行动 `done` 标记、多行动槽 totalSlots 如何重算」。老 APP 无可抄口径。

---

## H. APP 首页头图

### H-1 关键结论（先说清楚，避免施工单找错地方）
**用户列出的 5 段文字，有 4 段不在老 APP 的 HTML/CSS/JS 里；它们全部属于新 APP（Flutter v2.29.0）的首页头图。**
- 全仓（含 `web/**`、`android/**`、`tools/**`、`README.md`）Grep：`开始冒险` **0 命中**；`克苏鲁的呼唤 第七版 · 车卡器`（精确带「· 车卡器」）**0 命中**；`骰境TRPG`（无空格）**0 命中**（老 APP 一律写 `骰境 TRPG`，**中间有空格**）。
- 只读核验新 APP（未修改任何文件）：这些字面量在 `dice-realm/lib/ui/home_page.dart`：
  - `:559` `'骰境TRPG'`（`Text`，`fontSize:26`，`Palette.goldStr`，`letterSpacing:3`，`serifFamily`，在 `Expanded` 内、`maxLines:1`、`TextOverflow.ellipsis`）
  - `:575` `'COC 7th'`（`Text`，`fontSize:12`，`Palette.textMute`，`letterSpacing:1.5`；位于 `Row` 内，紧跟 `SizedBox(width:10)` + `Container(width:1,height:18,color:Palette.borderStr)` 竖分隔线之后、`PopupMenuButton` 之前）
  - `:651` `'克苏鲁的呼唤 第七版 · 车卡器'`（`Text`，`fontSize:12.5`，`Palette.textMute`，`letterSpacing:0.5`；`Row` 下方 `SizedBox(height:6)` 之后独立一行）
  - `:151` `title: '开始冒险'`（`SectionBanner` 分类头，`lib/ui/art.dart:38` 注释「『开始冒险』分区头图（两套皮肤）」；`lib/ui/widgets.dart:26` 注释「分区横幅（首页『开始冒险 / 角色档案』…）」）—— **这是分区标题，不是头图内文字**
  - `:662-670` 版本号 `Text(kAppVersionLabel, key: Key('home_app_version'))`，`fontSize:11`，`Palette.textMute.withValues(alpha:0.8)`；位于「克苏鲁…车卡器」下方 `SizedBox(height:3)` 之后，**第三行**
  - `lib/app_version.dart:15-27`：`kAppVersion='2.29.0'`、`kAppBuildNumber=99`、`kAppVersionShort='v2.29.0'`、`kAppVersionLabel='v2.29.0 (99)'`、`kAppTitle='骰境TRPG'`（`pubspec.yaml` 同步，测试 `test/app_version_test.dart` 逐字比对）
- **用户诉求「删掉前两段文字（COC 7th / 克苏鲁…车卡器），版本号移到原来 COC 7th 的位置」= 改新 APP `home_page.dart:553-670` 的 `Column`**：删 `:574-581` 的 `Text('COC 7th')`（及 `:572-573` 分隔线/SizedBox，需主理人定）、删 `:650-657` 的 `Text('克苏鲁…车卡器')`、把 `:662-670` 的版本号 `Text` 挪进 `Row` 里原 `COC 7th` 的位置（`:574` 处），保留 `骰境TRPG` + 菜单。`开始冒险` 是**另一个分区**（`home_page.dart:151`），若也要删需单独确认。

### H-2 老 APP 里最接近的等价物（施工单要「和老 APP 一样」时参照）
| 用户字面量 | 老 APP 对应（文件:行号 + 元素 + 定位） |
|---|---|
| `COC 7th` | ① `web/js/app.js:32` `RULE_LABEL = { coc7:'COC 7th', dnd5e:'DND 5E', custom:'自定义规则' }`（规则分类标签常量）；② `app.js:654-656` 首页「创建角色卡」卡内 `button.rule-card.on` 的 `div.d` 副标题 `COC 7th · 调查员角色卡 · N 个职业`（**大标题是 `div.t`「克苏鲁的呼唤 第七版」**）；③ `web/js/core/rules-coc7.js:714` `COC7.shortName = 'COC 7th'`、`:713` `name='克苏鲁的呼唤 第七版'`；④ `web/js/ui/room-ui.js:736` 房间规则卡 `div.d` `COC 7th · 已开放`、`:4332` 工具栏 `规则：COC 7th · 你是 X`；⑤ `web/js/ui/room-panels.js:4015` `<b>克苏鲁的呼唤 第七版 · 速查</b>`；⑥ `web/js/ui/sheet.js:485` 角色卡导出长图 `ctx.fillText('COC 7th · 调查员角色卡', ...)` |
| `克苏鲁的呼唤 第七版 · 车卡器` | **精确串 0 命中**。老 APP 只有 `克苏鲁的呼唤 第七版`（**无「· 车卡器」**）：`app.js:654` 首页规则卡 `div.t` 大标题、`rules-coc7.js:713`、`room-ui.js:735` 房间规则卡 `div.t`、`room-ui.js:3525` `.gp-title` `'克苏鲁的呼唤 7th'`。「车卡器」三字只出现在注释/构建文件里：`android/.../MainActivity.java:46`「COC 7th 调查员车卡器 —— 原生外壳」、`tools/coc_share_server.py:338`「由『调查员车卡器』生成」、`README.md`「调查员车卡 / 跑团」；`web/index.html` / `web/js/**` / `web/css/**` **均无「车卡器」** |
| `骰境TRPG` | 老 APP **一律 `骰境 TRPG`（带空格）**：`web/js/core/build-config.js:33` `displayName:'骰境 TRPG'`（单一真源）、`web/index.html:8` `<title>骰境 TRPG</title>`、`app.js:44` 顶栏 `.brand > span` 文本、`:593` 关于弹层 `.about-brand .nm`、`:595` `UI.notice(displayName + ' · 角色卡创建工具')`、`:596` 关于说明段、`:2273` console 日志、`web/css/app.css:2` 注释。另有 `web/img/logo.png` / `logo-192.png`（**方形 App 图标，图内烘焙「骰境 / TRPG」**，已用 ViewImage 核验：只有「骰境」大字 + 「TRPG」小字 + 巫师骰子插画，**无 COC 7th / 车卡器 / 开始冒险 / 版本号**） |
| `开始冒险` | **全仓 0 命中**（`web/**`、`android/**`、`tools/**`、`README.md` 全搜过）。老 APP 首页入口是 `app.js:650-674`「创建角色卡」卡 + 「跑团房间」入口 `.room-entry` `:669-674`（`div.t`「跑团房间」），无「开始冒险」分区头图 |
| 版本号 | 数据源 `web/js/core/build-config.js:40` `versionName:'2.13.13'`（打包时按 edition 覆盖）；**唯一展示处** `web/js/app.js:597-600`「ℹ 关于」弹层 `aboutSheet()` 内：`h('div.card-title',{text:'版本'})` + `h('div.small.dim',{text:'v'+((BuildConfig&&BuildConfig.versionName)||'2.13.13')})`（`:599`）。**老 APP 首页/顶栏 `.brand`（`:41-49`）只有 logo + 应用名，不显示版本号**；`index.html` 无版本元素；CSS 无版本号相关定位 |

### H-3 老 APP「首页头图」结构说明（施工单别误抄）
`web/js/app.js:644-732` `renderHome()` 是首页，**没有 banner/头图/hero 这一块**（`.appbar` `:41-49` 是 sticky 顶栏，`.content` 里第一块就是 `div.card`「创建角色卡」`:650`）。房间入口页另有 `.room-hero`（`web/js/ui/room-ui.js:386-389`：`h2「跑团房间」` + `p「和你的调查员一起开团：招募、聊天、掷骰、场景与战斗」`；CSS `web/css/app.css:967-969`、`:2781-2782`）—— 也不是用户说的头图。→ **老 APP 无「首页头图」可参照，H 属纯新 APP 改造。**

---

## 给施工单的歧义点（需主理人拍板）

1. **A「检定等级」4 档到底映射到什么**：用户要「选成功需要的检定等级：大成功/成功/困难成功/极难成功」。老 APP 只有 3 档「难度」`REGULAR/HARD/EXTREME` + 结果 LEVEL `5/4/3/2/0/-1`。新 APP 的 4 档是复用 `LEVEL.CRITICAL/REGULAR/HARD/EXTREME`（=5/2/3/4）当「required」吗？那「大成功」档要求 `level>=5`（只有掷出 01 才过）是否符合规则书？还是另造「需达到的阈值 = floor(skill/5) 等」？请明确「检定等级」= 结果等级 还是 = 难度档。
2. **A「系统自动检定」的触发范围**：用户要「推送→推送到指定玩家→系统自动检定」。老 APP `check.request` 是**推给玩家自己掷**（REQUEST 卡），只有 `sceneCheckStep` 对**疯狂发作中**目标才权威端自动掷。新 APP 是要「推送后由服务端替所有目标自动掷并直接出结果」（改协议），还是保留玩家掷但补一个「自动掷」按钮？另外自动掷时用谁的 `base`（老 APP 用 `_skillBaseOf(m, skill)` 权威取值，查不到回落 50，见 `room-model.js:6769-6770`）。
3. **A 难度字面量大小写**：老 APP UI/载荷是大写 `REGULAR/HARD/EXTREME`，但规则层 `DIFFICULTY` 键小写、`normDifficulty()` 对大写回落 `regular`（A-5 ⚠️）。新 APP 自写 Dart 口径时统一成哪一套？是否一并修正老 APP 这个「困难/极难档退化」的历史行为？
4. **B2「反击输入检定等级 + 造成伤害（骰表达式）、闪避只输入检定等级」**：老 APP 完全没有「检定等级」输入，防守方输入的是**对抗值 1–100**（`dVal`/`valI`），伤害式是**攻击方武器**的（`dmgI`），反击胜时沿用同一伤害式打在攻击方身上。请明确新 APP 的「检定等级」是取代「对抗值」还是并存？「反击造成伤害」是**防守方单独填**一个骰式（需新增 `defense.damage` 字段，模型 `room-rules.js:1065` 已预留但 UI 未传），还是复用武器伤害式？「闪避只需输入检定等级」时是否完全不掷防守骰？
5. **F「更多工具」放行范围**：用户要昏迷/疯狂时「只能点推进 1 轮和更多工具，其它全禁」。老 APP 把 `.dice-extra` 全部 8 项 + 战斗对抗都 `disabled: opLocked`，只放行推进 1 轮。新 APP 放行「更多工具」弹层本身可点开可以，但**弹层里各条目**（技能检定/SAN Check/给物品…）点下去会不会与模型 intent 锁（`room-model.js:1344-1368`）冲突、需要「打开但内部全灰」还是「打开且部分可用」？请给出放行清单。
6. **D/F 交叉**：玩家「申请治愈疯狂/重伤」按钮在 `selfStateSheet` 内，而其入口「📝 状态管理」被 `opLocked` 禁用（`room-panels.js:2811`）；模型 intent 白名单却放行 `madness.cure`/`sheet.healwound`（`room-model.js:1356-1357`），`:3809` 注释也声称昏迷可点。新 APP 昏迷/疯狂玩家若「只能点推进 1 轮 + 更多工具」，这两个**申请入口放哪**？（建议：移到「更多工具」弹层或常驻玩家卡，否则白名单形同虚设。）
7. **C「SAN 大失败追加」的多次记录**：老 APP 一键 `1D10`、不记录、不选（C 末段）。新 APP 要「KP 选追加哪一次大失败的数值」：请定义①大失败历史的存储位置（成员 `sheet` 下新数组？`state` 新字段？随存档？）②每条记录形状（时间 / 当时 SAN / 成功·失败损失表达式 / 已追加标记）③KP 选择 UI 与载荷（可复用 `sheet.sanloss` 已有的 `dice`/`reason` 可选字段，或新 op）④「追加一次后是否核销该条」。
8. **C 定向指令「精神分析检定数值」**：老 APP 精神分析**不是** KP 定向指令按钮（是玩家申请 `aid.psycho`，无数值输入），急救/医学也只有**技能下拉**无数值。用户「现有按钮只能选目标、没有输入效果，要补数值」—— 请确认新 APP 定向指令面板到底保留哪几个按钮、各自要补的输入是「检定数值(1-100)」还是「骰表达式/损失值」；是否与老 APP 的 9 按钮集合对齐（老 APP 还含 `🕶 暗骰`、用户清单未提）。
9. **G 插队的语义**：老 APP 无 reorder（G 全节）。新 APP 需明确调整方式（上移/下移/拖拽/输入序号）、载荷字段名、`turn` 游标与 `done`/`totalSlots` 在插队后如何重算、是否允许把单位插到**当前行动者之前**（插队的定义），以及是否只对「怪物」开放。
10. **H 删除范围与「原来 COC 7th 的位置」**：新 APP `home_page.dart:553-670` 里 `COC 7th` 在 `Row` 内（左右有分隔线 `Container(width:1,height:18)` 与 `SizedBox(width:10)`），删「前两段文字」时这些**分隔线/SizedBox 是否一并删**？版本号（当前第 3 行 `Text(kAppVersionLabel)`）移到 `Row` 内原 `COC 7th` 槽位后，`fontSize`/颜色是否沿用 `12/textMute`（原 COC 7th 样式）还是保留 `11/alpha 0.8`？`开始冒险`（`:151` 分区 `SectionBanner`）是否也在本次删除范围？`kAppVersionLabel` 含构建号 `(99)`，头图里要显示全称还是 `kAppVersionShort`（`v2.29.0`）？

---

## 附：与历史报告的校验（避免施工单沿用旧指引）
- `_p16_oldapp_research.md` §1（对抗下拉 `p:<seat>`/`a:<id>`、`check.opposed`、护甲 `max(0,raw-armor)`）、§5（场景检定 step 结构、`scene.check.push`）、§7（急救/医学/精神分析）、§8（布局）—— 本批逐条复核**一致**，行号相同。
- `_p10_t7_research.md` B2/B3（`combat.start` 自动 DEX 排序、`initiativeBar` 只读）—— 与 G 节结论一致。
- **本批新增/修正**：① `检定方式`/`检定等级`/`开始冒险`/`更多工具`/`骰境TRPG`(无空格)/`克苏鲁的呼唤 第七版 · 车卡器` 均为**老 APP 0 命中**；② 大写 `REGULAR/HARD/EXTREME` 与小写 `DIFFICULTY` 键的大小写坑（A-5）；③ 老 APP「更多工具」对应物 = `.dice-extra`（常驻平铺，非弹层，被 opLocked 禁用）而 `.gp-quick` 快捷行未接锁；④ H 的字面量实际在**新 APP** `lib/ui/home_page.dart`，老 APP 只有 `骰境 TRPG`（带空格）+ 版本号只在「关于」弹层。
