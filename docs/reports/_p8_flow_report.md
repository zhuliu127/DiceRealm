# P8 车卡流程 / 技能步骤 UI —— 交付报告（flow-dev）

需求来源：用户第 8 条（步骤自由跳转）、第 11 条（选职业焦点 bug / 技能分类 / 模糊搜索 / 任选弹窗过滤）。

改动范围严格限制在本人负责的文件内：**未触碰** `lib/domain/**`、`chargen_logic.dart`、
`home_page.dart`、`ai_create_page.dart`、`card_detail_page.dart`、`art.dart`、`roster_page.dart`，
以及 `create_flow_page.dart` 顶部那条 68px 横幅（原样保留）。

---

## 一、文件清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `lib/ui/create/create_flow_page.dart` | 改 | ① 顶部 9 段进度条可点（`step_jump_0..8`，28px 透明点击区）+ AppBar「步骤总览」入口；② 统一 `_jumpToIndex()` / `_jumpTo()`；③ 保存前全量校验，不合格直接送回第一个问题步 |
| `lib/ui/create/steps/step_basics.dart` | 改 | 选完职业不再把焦点交给年龄输入框（打开前 / 关闭后 / 帧末三次 `unfocus`） |
| `lib/ui/create/steps/step_skills.dart` | 改 | 分类 chip + 模糊搜索 + 边筛边省流；「+选择技能」弹窗按 `occupationalSet` 排除本职技能；技能行 / 总数加稳定 Key |
| `lib/ui/create/skill_groups.dart` | **新建** | 展示层分组表（全部 / 常用 / 战斗 / 社交 / 探索 / 生存 / 学识 / 语言 / 技艺 / 行动 / 其他）+ `skillMatchesKeyword()` 模糊匹配。**不放 domain** |
| `test/p8_wizard_nav_test.dart` | **新建** | 需求 8 跳转 5 例 + 需求 11 焦点 1 例（共 6 例） |
| `test/p8_skill_step_test.dart` | **新建** | 分类表 3 例 + 分类筛选 2 例 + 搜索 3 例 + 加点共享 2 例 + 任选弹窗过滤 2 例（共 12 例） |

`wizard_steps.dart` **没有改**：跳转用的就是注册表已有的 `length / titleAt / indexOf / runOnEnter`，
不需要额外暴露索引，改它只会增加风险面。

---

## 二、需求 8：点击第 1-9 步自由跳转

### 改法

1. **进度条的 9 段变成可点。** `_StepBar` 新增 `onJump`。视觉仍是 4px 细条（不给整条加厚），
   但外包一层 **28px 高的 `InkWell`** —— 4px 高的目标手指点不到，这是纯命中区优化。
   Key 用 **0 基下标**（与页面 `_index` 同源，避免「第 1 步是 0 还是 1」的换算 bug）：
   `step_jump_0` = 第 1 步 … `step_jump_8` = 第 9 步。
2. **再加一个带名字的总览入口。** AppBar 右侧 `btn_step_overview` → 底部弹层列出
   「1 规则系统 / 2 基本资料 / … / 9 概要」，点哪条跳哪条（`step_overview_0..8`）。
   9 段细条再宽也就 30-40px，键盘/宽屏下仍不好点，所以两条路都给了。
3. **跳转不校验，但会跑「入场准备」。** `_jumpToIndex()`：
   - 不调用 `validateAt()` —— 玩家常常是带着半成品回去改第 4 步，跳过去先被
     「请先填完属性」拦住就等于没修；
   - 但会跑目标步的 `onEnter`（`recalc` / `syncSkills` / `materializeOccupationalSkills`
     / `adoptCreditFromSkill`）。这一步只准备数据、幂等、无校验，不跑的话跳到技能页
     会看到一份还没补齐的本职技能列表；
   - `IndexedStack` 不做重建，各步输入控件状态原样保活（`_IndexedStack` 的所有 child
     本来就是一次构建、只切 index，所以跳到数据全空的步骤也不会崩）。
4. **跳转不是校验后门。** 新增 `_firstInvalidStep()`：保存时按步序跑**全量校验**，
   第一个不合格的步就 `setState(_index = bad, _stepError = 文案)` 并 `return`（不落库）。
   为什么必须加：允许自由跳转后，玩家可以「第 1 步 → 直接点第 9 步 → 保存」，
   只校验末步会让一张没名字、没属性、没职业的卡进仓库。有测试钉住
   （`自由跳转不是后门…`：空卡从第 1 步跳到第 9 步保存 → 仓库 0 张、页面回到第 2 步、
   显示「请填写角色姓名」）。
   「下一步」仍只校验当前步（原行为不变）。

### 与老测试的关系

`wizard_fix_jump_test.dart` 用的是自建迷你向导（`_MiniWizard` + 自己的 `onJumpTo`），
不经过 `_StepBar` / `_save`，**一行没动也仍然全绿**。
`create_extra_steps_test.dart` 的「真实向导里点去修复」走 `_jumpTo(stepId)` —— 改成
委托 `_jumpToIndex(_steps.indexOf(id))` 后行为等价，仍绿。

---

## 三、需求 11 前半：选完职业焦点跑到年龄输入框

### 根因

职业选择器是 `showModalBottomSheet`，里面有搜索框。玩家在弹层里打字 → 搜索框拿到焦点；
点某一项 `Navigator.pop(职业)` 返回后，Flutter 把焦点还给**上层路由里上一个被聚焦的
节点**——通常就是玩家刚填过的「年龄」输入框，于是输入法自己弹出来盖住职业详情。

### 改法（三处，缺一不可）

1. 打开弹层**前** `FocusScope.unfocus()`：先把年龄框的焦点与输入法收掉；
2. 弹层里点选某职业时**先 unfocus 再 pop**（关闭按钮同理）：不让「搜索框的输入法状态」
   跟着路由返回上层；
3. `await` 回来后再 unfocus 一次，并在 `addPostFrameCallback` 里补一次：
   父页 `onChanged → setState` 重建后，框架仍可能按焦点遍历顺序给第一个可聚焦控件上焦点。

### 验证

`p8_wizard_nav_test.dart` 的 `选职业前后都没有输入框被抢焦点…`：
先 `enterText(field_age)` 制造「年龄框刚被聚焦」的前置条件（并断言前置成立），
选完职业后断言 `所有 EditableText 的 focusNode 都不 hasFocus` 且 `testTextInput.isVisible == false`。

**这条测试是反向验证过的**：把三处 unfocus 临时注释掉重跑，测试确实红
（`选完职业后焦点不该落在任何输入框上`），恢复后绿 —— 不是空断言。

---

## 四、需求 11 后半：技能分类 / 模糊搜索 / 任选弹窗过滤

### 4.1 分类（`skill_groups.dart`）

**做成筛选项**，不做「一个技能在多个分类里就渲染多行」：chip 选某组 → 只列出该组技能，
列表仍是一条、每个技能最多一行。这样「同一技能已加点共享」在结构上就不可能出错
（只有一份 `draft.skills[key]`，视图只是过滤）。

| 分组 id | 名称 | 技能（id） |
|---|---|---|
| `all` | 全部 | 全部 54 条 + 自定义 |
| `common` | 常用 | 侦查、聆听、图书馆使用、心理学、闪避、急救、潜行、说服、格斗、射击、攀爬 |
| `combat` | 战斗 | 格斗、射击、闪避、投掷、炮术、爆破 |
| `social` | 社交 | 心理学、说服、话术、恐吓、取悦、乔装、读唇 |
| `explore` | 探索 | 侦查、聆听、追踪、潜行、领航、锁匠、妙手、读唇、攀爬 |
| `survival` | 生存 | 急救、攀爬、跳跃、游泳、生存、潜水、驯兽、追踪 |
| `knowledge` | 学识 | 图书馆使用、会计、人类学、估价、考古学、历史、法律、神秘学、科学、学识、克苏鲁神话、医学、精神分析、催眠、博物学、电子学、计算机使用 |
| `language` | 语言 | 母语、其他语言 |
| `craft` | 技艺 | 技艺、机械维修、电气维修、驾驶 |
| `action` | 行动 | 汽车驾驶、骑术、驾驶、操作重型机械 |
| `other` | 其他 | **兜底**：没被上面任何一组覆盖的 id（当前 = 信用评级）+ `custom` |

命名在用户建议的「常用/战斗/社交/生存/语言/技艺/生活」基础上做了两处调整：
把「生活」换成 **探索**（潜行/锁匠/妙手/读唇这堆最常找的技能原来散在「其他」里）
和 **行动**（载具与重机械），并补上旧数据里本来就有、但界面无处可去的 **学识**。

不漏项的保证：`uncoveredSkillIds()` 算出「显式分组没覆盖到的 id」，全部塞进「其他」。
测试逐条断言 54 条技能**每一条** `skillGroupIdsOf(id)` 非空。

### 4.2 模糊搜索

`Key('skill_search')`，纯函数 `skillMatchesKeyword(skill, kw)`：
1. 归一化（小写 + 去掉空格/下划线/括号等分隔符）；
2. 姓名 / id / 子类 / 描述任一 **子串** 命中 → 命中（搜「侦」→「侦查」；搜 `spot` → `spot_hidden`）；
3. 否则退化成「按顺序出现」的子序列匹配（搜「图书使」→「图书馆使用」）。

### 4.3 「+选择技能」弹窗过滤

`_FreePicker` 新增 `isBlocked(id, sub)`，由页面按 `occupationalSet(draft)` 生成：
- 本职技能（fixed / choice / alt / free 已选）**直接不列出**，弹窗顶部注明
  「已自动隐藏 N 项本职业已有的技能」（`free_picker_hidden_hint`）；
- **本块已勾选的仍然列出**（`own.contains(key)` 优先返回 false），否则玩家勾错了取消不掉；
- 组技能按 `id::sub` 精确判断，不会因为「语言（拉丁语）」是本职就把整组语言都拉黑。

### 4.4 不动算法

`autoSpendPoints` / `applyPoint` / `materializeOccupationalSkills` / `occupationalSet` / 上限
全部照旧调用 domain 与 `chargen_logic`，UI 没有任何算法副本。

### 4.5 顺手修的一处 UI 侧读法

原先「其他技能」用 `skills.where((s) => !occSkills.contains(s))` 排除本职项，而 `occSkills`
是自己过滤出来的新 list —— 用 `contains` 比较 Map 实例。现在把**未过滤**的 `inOccSet`
作为分割依据，过滤只用于展示，避免「筛过之后本职项掉进其他技能」这类因过滤引入的重复。
未加点的技能在**未筛选时**仍按原有省流规则收在「显示全部」后面；只要进入筛选/搜索，
省流开关让位（否则点了「战斗」却只看到已加点的几项，玩家会以为技能丢了）。

---

## 五、测试账目

### 新增

`test/p8_wizard_nav_test.dart`（6 例，全绿）
1. 第 1 步 → 第 5 步 → 回第 2 步：`step_progress` 依次 `1/9 → 5/9 → 2/9`，页面类型与关键控件同步；跳转不报 `step_error`
2. 跳到数据全空的属性 / 概要步：正常渲染（`attr_str` / `StepSummary` 在），再跳回第 1 步状态没被重置
3. 跳转不强制校验目标步（第 2 步全空也能跳第 3 步）
4. 「步骤总览」9 条都在，点第 4 条 → `4/9` 且 `credit_input` 在，再跳第 8 条 → `8/9`
5. 自由跳转不是后门：第 1 步 → 第 9 步 → 保存 → 仓库仍空、回到第 2 步、显示「请填写角色姓名」
6. 选完职业后无 EditableText 被聚焦、`testTextInput.isVisible == false`、职业确实选上

`test/p8_skill_step_test.dart`（12 例，全绿）
1. 54 条技能每条都至少在一个分类里
2. 一个技能可属多组（闪避 = 常用 + 战斗）
3. 首位「全部」、末位「其他」，未分组 id 全在「其他」，且「其他」只多一个 `custom`
4. 11 个 chip 都在；点「战斗」→ 斗殴在、侦查不在、标题含「· 战斗」；点「全部」恢复
5. 点「语言」→ 母语 + 拉丁语在，侦查/斗殴不在
6. 搜「侦」→ 侦查在，斗殴/聆听不在
7. 搜 `spot` → 侦查在；搜不存在 → `skill_none` 空态
8. 分类 + 搜索叠加（战斗里搜「斗」只剩格斗（斗殴））
9. **加点共享**：闪避在「战斗」25 → 加 10 点 → 切「常用」35 → 切回「战斗」35 → 切「全部」35；卡里 `dodge` 仍只有 1 个实例、`int == 10`
10. 同一分类内同一技能只出一行
11. 会计师「任意两项」弹窗不含侦查/会计/法律/聆听/说服，含「格斗（斗殴）」，有隐藏提示
12. 本块已勾的仍显示（能取消）

### 反向验证（确认测试不是空断言）

- 去掉三处 `unfocus` → 焦点用例红；恢复 → 绿。
- 把 `isBlocked` 置 null → 弹窗过滤用例红（「侦查」出现在任选列表里）；恢复 → 绿。

### 跑过并全绿的既有测试（共 60 例，命令见下）

```
flutter test test/p8_wizard_nav_test.dart test/p8_skill_step_test.dart \
  test/wizard_steps_test.dart test/create_extra_steps_test.dart \
  test/create_flow_widget_test.dart test/wizard_fix_jump_test.dart \
  test/step_background_test.dart
→ +60: All tests passed!
```

另跑 `test/p7_ai_caps_ui_test.dart test/ai_create_page_test.dart test/ai_flow_test.dart
test/p7_fate_test.dart` → 全绿（含「AI 卡首步是基本资料、进度 1/8」「手动新建 1/9」）。

`flutter analyze lib/ui/create test/p8_*.dart` → No issues found。

### 老测试改动清单

**零改动。** 没有为了绿改弱断言、没有删测试、没有改 `wizard_fix_jump_test.dart`。
`step_skills_test.dart` 这个文件在仓库里**不存在**（`ls test/` 只有
`step_background_test.dart`），任务里给的跑测命令按实际文件名执行，已补 `step_background_test.dart`。

### 已知与本线无关的红（并行改动，非本人文件）

`test/card_detail_edit_test.dart` 有 2 例红：
- 「删除角色卡 菜单 → 删除 → 二次确认 → 仓库删除并回首页」
- 「导入 / 导出 硬约束 6：首页导入旧版真实导出的 JSON…」

原因：删除后落地的页面已经从「首页」变成「角色档案」页（探针实测：`HomePage` 在树上为 0，
`角色档案 / 已保存 0 位调查员 · 0 位长眠者` 在树上为 1），而这两例仍在断言首页的
`骰境TRPG` / 空态文案。删卡导航与首页改版属于 `card_detail_page.dart` / `home_page.dart` /
`roster_page.dart`（本批他人负责），**未触碰**，留给对应负责人处理。
同一时间 `lib/ui/home_page.dart` 也出现过 `RandomCreatePage` 未定义的短暂编译错误（现已消失），
可佐证该文件正在被并行修改。

---

## 六、红线自查

- 未改 `lib/domain/**`、`chargen_logic.dart`、`home_page.dart`、`ai_create_page.dart`、
  `card_detail_page.dart`、`art.dart`、`roster_page.dart`；68px 横幅原样未动
- 未 `flutter clean`、未加依赖、未出包
- 每段进度条都真能跳（无假按钮）；`testWidgets` 内无 `Timer` / `Future.delayed` / 真实文件 I/O
  （新测试自建 `RepoScope/SettingsScope/ShareScope` 全内存后端 + `baseProvider: () => ''` 的未配置分享客户端）
- 全量 `flutter test` 留给主理人
