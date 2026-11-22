# P16「跑团房间按钮统一尺寸 + 重排」独立验收报告

- **验收人**：QA 严过关（software-qa-engineer）
- **被验对象**：dice-realm v2.27.0+97（未升版本）
- **验收方式**：**独立验证（fresh eyes）**，未采信工程师自验结论，未复用其脚本；所有数字均由本人重新 pump 实测
- **未改动任何生产源码**：本轮只新增临时探针 `test/p16qa_zz_probe_test.dart`（验证后已删除），
  反向证伪用的 4 次注入全部按「cp 备份 + md5 + trap EXIT + cmp/md5 复核」流程恢复并核销

---

## 0. 智能路由判定

> ## `IS_PASS: NO / Engineer`
>
> **理由（唯一阻塞项）**：`RoomTapTile` 的紧约束（`SizedBox(W,H)`）把按钮变成定宽后，
> **系统字体调大时会 RenderFlex overflow**。实测在 `textScaleFactor ∈ {1.3, 1.5, 2.0}` 下
> **36 / 48 格全红**（1.0 下 12/12 全绿），涉及 `gpToolbar` 主组、`gpKpTools`、`gpScene`、
> `gpPlCharCard` 四个栏位；最大溢出 **87.8dp**（`极难成功(4)`，108 宽，2.0 倍字体）。
> 已用「把 `gp_scene_check_kp.dart` 换回改动前版本」证伪：**旧代码同档不溢出**。
> 即这是本批**新引入的回归**，不是历史遗留。

附带 1 个非阻塞排布问题（P2，建议同批一起修）：
`412×915`（荣耀 Magic9 竖屏，也是最常见的安卓竖屏档之一）玩家 `gpPlCharCard` 4 个短按钮
被 `Wrap` 排成 **3 + 1**，第 4 个（`AI RP`）单独成行 —— 正是用户抱怨过的「孤行」形态。
工程师的测试只在 1280 下断言（2 列），未覆盖这一档。

**其余全部通过**：全量 2184 条全绿、`analyze` 干净、6 个栏位尺寸与规格逐像素一致、
零横向溢出、零改动核验（room_panel_kit / sheets 19 / 按钮数 49 / enabled / 文案）全部成立。

---

## 1. 全量回归与静态检查

| 项 | 命令 | 结果 |
|---|---|---|
| 静态检查 | `flutter analyze`（全库） | **`No issues found! (ran in 6.2s)`** |
| 全量测试 | `flutter test`（不带文件名，全库串行） | **`+2184: All tests passed!`**，耗时 1m33s |
| 条数核对 | 2171（基线）+ 13（新增 `p16_button_unify_test.dart`） | **2184 ✓ 精确吻合** |
| `(did not complete)` | —— | **0 次**（未出现瞬时挂起，无需复跑，未用 `--concurrency`） |
| 恢复注入后定向回归 | `flutter test p16 + room_ui_permission + p10_t6 + p10_t7 + p10_t7_b` | **`+60: All tests passed!`** |

> 全量是在**注入实验之前**跑的（干净工作树）；注入实验后再次用定向 60 条确认恢复无残留。

---

## 2. ★★ 大字体溢出矩阵（工程师完全未测的真实风险）

### 2.1 方法

- `tester.platformDispatcher.textScaleFactorTestValue = scale`（`addTearDown`/显式复位）
- 先确认 `textScaler` **真的生效**（避免「测了个假的」）：
  同一文案 `极难成功(4)` 实测 —— 1.0 → `Size(92.8, 19.0)`；1.5 → `Size(138.3, 28.0)`；2.0 → `Size(183.8, 37.0)` ✓
- 每格都收集两路证据：① `FlutterError.onError` 拦到的 `RenderFlex overflowed by N pixels`
  ② 逐按钮独立算「内容需要宽」= Row 子件宽之和 + 12（左右各 6 padding），与实测宽相减
  （两路互相印证，数字一致）
- 48 格 = 4 档字号 × 6 档屏 × 2 视角

### 2.2 矩阵结果（`null` = `takeException()==null` 且无溢出）

| 屏 | KP @1.0 | PL @1.0 | KP @1.3 | PL @1.3 | KP @1.5 | PL @1.5 | KP @2.0 | PL @2.0 |
|---|---|---|---|---|---|---|---|---|
| 320×640 | null | null | **溢 6.9** | **溢 15.7** | **溢 22.5** | **溢 28.8** | **溢 87.8** | **溢 61.3** |
| 360×640 | null | null | **溢 6.9** | **溢 15.7** | **溢 22.5** | **溢 28.8** | **溢 87.8** | **溢 61.3** |
| 412×915 | null | null | **溢 6.9** | **溢 15.7** | **溢 22.5** | **溢 28.8** | **溢 87.8** | **溢 61.3** |
| 780×320 | null | null | **溢 6.9** | **溢 15.7** | **溢 22.5** | **溢 28.8** | **溢 87.8** | **溢 61.3** |
| 1280×800 | null | null | **溢 24.0** | **溢 15.7** | **溢 42.3** | **溢 28.8** | **溢 87.8** | **溢 61.3** |
| 1524×1016 | null | null | **溢 24.0** | **溢 15.7** | **溢 42.3** | **溢 28.8** | **溢 87.8** | **溢 61.3** |

> 表内填的是该格**最大溢出量**。**48 格中 36 格红**（1.3/1.5/2.0 三档 × 12 格全红），
> **48 格中 12 格绿**（scale=1.0 全部绿）。

### 2.3 溢出明细（哪几个按钮、差多少）

`gpScene`（`sceneTile` 108×48，KP 侧；1280×800 与 360/412 表现一致）：

| 按钮 key | 文案 | 1.3 | 1.5 | 2.0 |
|---|---|---|---|---|
| `gpSceneCheckKp/level/4` | 极难成功(4) | 需132.0 → **溢24.0** | 需150.3 → **溢42.3** | 需195.8 → **溢87.8** |
| `gpSceneCheckKp/level/3` | 困难成功(3) | 需132.0 → **溢24.0** | 需150.3 → **溢42.3** | 需195.8 → **溢87.8** |
| `gpSceneCheckKp/level/-1` | 大失败(-1) | 需132.0 → **溢24.0** | 需150.3 → **溢42.3** | 需195.8 → **溢87.8** |
| `gpSceneCheckKp/level/5` | 大成功(5) | 需114.9 → **溢6.9** | 需130.5 → **溢22.5** | 需169.5 → **溢61.5** |
| `gpSceneCheckKp/level/2` | 成功(2) | 未溢 | 需110.8 → **溢2.8** | 需143.3 → **溢35.3** |
| `gpSceneCheckKp/level/0` | 失败(0) | 未溢 | 需110.8 → **溢2.8** | 需143.3 → **溢35.3** |
| `gpSceneCheckKp/quickPush` | 快速推送 | 未溢 | 需113.0 → **溢5.0** | 需139.0 → **溢31.0** |
| `gpSceneCheckKp/editor` | 检定编辑器 | 需119.7 → **溢11.7** | 需132.8 → **溢24.8** | 需165.3 → **溢57.3** |

`gpPlCharCard`（`charTile` 104×40，玩家侧）：

| 按钮 key | 1.3 | 1.5 | 2.0 |
|---|---|---|---|
| `gpPlCharCard/aiBtn`（`AI RP`） | 需119.7 → **溢15.7** | 需132.8 → **溢28.8** | 需165.3 → **溢61.3** |
| `gpPlCharCard/stateBtn`（`状态管理`） | 未溢 | 需113.0 → **溢9.0** | 需139.0 → **溢35.0** |
| `act/madness.advance`（满宽 223.2） | 未溢 | 未溢 | 需244.0 → **溢20.8** |

`gpToolbar` 主组（`toolbarTile` 80×40，KP/PL 两侧）：

| 按钮 key | 1.3 | 1.5 | 2.0 |
|---|---|---|---|
| `act/round.next`（`下一轮`） | 需85.4 → **溢5.4** | 需93.3 → **溢13.3** | 需112.8 → **溢32.8** |
| `act/scene.mode`（`转战斗`） | 需85.4 → **溢5.4** | 需93.3 → **溢13.3** | 需112.8 → **溢32.8** |
| `gpToolbar/zoomPercent`（**不定宽**，实测 87） | 不溢 | 不溢 | 不溢 |

`gpKpTools`（`toolsTile` 90×48，仅 1280/1524 档该栏位才渲染）：

| 按钮 key | 1.3 | 1.5 | 2.0 |
|---|---|---|---|
| `gpKpTools/placeActor`（`放单位`） | 未溢 | 需93.3 → **溢3.3** | 需112.8 → **溢22.8** |
| `gpKpTools/placePlayer`（`放玩家`） | 未溢 | 需93.3 → **溢3.3** | 需112.8 → **溢22.8** |

**错误原文（1.5×/1280×800/KP，`FlutterError.onError` 拦到的第一条）**：

```
A RenderFlex overflowed by 3.3 pixels on the right.
```

（1.3× 首条 `... by 6.9 pixels on the right.`；2.0× 首条 `... by 3.1 pixels on the right.`，
最大一条 `... by 87.8 pixels on the right.`）

### 2.4 这是**新引入的回归**（反向证伪）

把 `lib/ui/room/widgets/gp_scene_check_kp.dart` 临时换回 `_gh_backup` 里的改动前版本
（裸 `RoomTap(minSize: Size(...))`，无紧约束），同一探针重跑：

```
注入(旧版) RoomTap( =3  RoomTapTile( =0
--- scale=1.5 1280x800 KP errs=5
    OVERFLOW gpToolbar3 'act/round.next' w=80.0 need=93.3 溢=13.3
    OVERFLOW gpToolbar3 'act/scene.mode' w=80.0 need=93.3 溢=13.3
    （gpScene8 的 10 条溢出**全部消失**）
```

⇒ **`gpScene` 的溢出 100% 由本批新增的 `SizedBox(108,48)` 紧约束引入**；
`gpToolbar` / `gpPlCharCard` 同理（同为 `RoomTapTile`）。
旧实现是 `宽 = max(内容宽, minSize)`，字大只会变宽（破坏等宽但永不 overflow）。

### 2.5 建议修法（供工程师参考，本轮未改源码）

`RoomTapTile` 是新增件，**不碰 `room_panel_kit.dart` 也能修**，二选一：

1. 在 `RoomTapTile.build` 里用 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0/1.2, child: RoomTap(...))`
   —— 已确认本 SDK 有该 API（`flutter/lib/src/widgets/media_query.dart:1503`）。
   定宽按钮内**不跟随系统字号放大**是无障碍场景的常规取舍（对比度与热区仍达标）。
2. 或在 `RoomTapTile` 里给 label 套 `FittedBox(fit: BoxFit.scaleDown, child: Text(...))` —— 
   但这需要复制 `RoomTap` 的 row 结构，侵入性更大，**不推荐**。

---

## 3. 独立反向证伪（4 次注入，全部按纪律执行）

纪律：注入前 `cp` 备份 + `md5sum`；注入前打印锚点命中次数；`trap restore EXIT`；
恢复用 `cp` + `cmp -s` + `md5sum`；恢复后删备份目录。（该工程不是 git 仓库）

| # | 注入内容 | 锚点命中 | 结果 | 红条原文 |
|---|---|---|---|---|
| 1 | `gp_scene_check_kp.dart` 整体换回改动前版本（裸 `RoomTap`，`minSize 57.5~83.5`） | `RoomTap( =3`、`RoomTapTile( =0` | **只红 P16-06**（`+5 -1`，其余 12 条全绿） | `gpScene 8 个按钮：同栏位按钮尺寸必须恰好 108.0×48.0，实测 [Size(91.5, 48.0), Size(104.8, 48.0), Size(104.8, 48.0), …]` |
| 2 | `gp_dice_bar.dart` 除数 `(kDiceTileW + kDiceTileGap)` → **裸魔数 88** | `availableWidth - 16) / 88)` = 1 处 | **只红 P16-03** | `Expected: <2>  Actual: <3>` / `clamp 下限 2 必须仍然生效`（line 214，`diceMaxPerRow(280)`） |
| 3 | `gp_dice_bar.dart` `kDiceTileW = 90` → **104**（真实改宽） | `kDiceTileW = 104` = 1 处 | **只红 P16-03** | `Expected: <4>  Actual: <3>` / `412dp 屏：骰子条可用 400 → 每行 4 个`（line 212） |
| 4 | 同 #1，但目的是跑**大字体探针** | 同 #1 | 见 §2.4 | 旧版 `gpScene` 无溢出 ⇒ 回归确认 |

**恢复核销证据**

```
gp_scene_check_kp.dart  注入前 md5 32805ef3c2e2360b2dcbb1856215f3d0
                        恢复后 md5 32805ef3c2e2360b2dcbb1856215f3d0   [restore] cmp OK
gp_dice_bar.dart        注入前 md5 a3f39924b8e35a658098e80fd4d66619
                        恢复后 md5 a3f39924b8e35a658098e80fd4d66619   [restore] cmp OK
```

恢复后 `diff -rq lib _gh_backup/lib` 的差异集合与注入前**逐项一致**（11 个 P16 源码 + 
`room_button_size.dart` 新增 + `art.dart`(属另一任务)），无任何残留注入。

**测试强度观察（非缺陷，告知 lead 评估）**：注入 #2 说明 `(kDiceTileW + kDiceTileGap)` 与旧魔数 `88`
在**真实三档（348 / 400 / 546）算术结果完全相同**，只有 `280` 这一个边界值能区分。也就是说
「除数与定宽同源」这条性质目前只被**一个边界值**钉住；若将来有人改回 88，在真机上不会立刻暴露。
（注入 #3 说明同源性确实有效：把按钮真实加宽后 `per` 会跟着变。）

---

## 4. 零改动核验（独立做，未采信工程师的 md5 列表）

| 项 | 判据 | 结果 |
|---|---|---|
| `room_panel_kit.dart` 整文件 | md5 vs `_gh_backup` | **`8e5126d3931092c49537ad32747a9659` = 基线 ✓**（与 lead 给的基线一致，独立确认） |
| `lib/ui/room/sheets/` | 19 个文件逐个 `cmp -s` | **19 / 19 逐字节相同 ✓** |
| `RoomTap` / `ConfirmTwice` 类体 | 由上一条覆盖（整文件 md5 相同） | **零改动 ✓** |
| 按钮调用点数量 | 改动前 `RoomTap(` 计数 vs 改动后 `RoomTap(` + `RoomTapTile(` | **49 = 24 + 25 ✓**，且**逐文件 1:1**（见下表），无按钮被删/合并/条件化 |
| 文案 | `find.text('更多工具')`（玩家工具栏） | **=1 ✓**（KP 侧本就不渲染该按钮，原逻辑如此） |
| 文案 | `find.byTooltip('点按切换缩放档位（60%–100%）')` | **=1 ✓** |
| 文案 | `下一个行动` 实际文案是 `下一个行动 ▶`（`gp_combat_list.dart:125`），只在战斗名单非空时渲染 | `gp_combat_list.dart` **本批零改动**（`diff` 无输出）✓ |
| `enabled` 语义 | 5 个挂 `RoomKeys.action(op)` 的按钮：`RoomTap.enabled == gate.can(op)` | **5/5 OK ✓**（KP round.next/scene.mode/combat.roll、PL aid.apply/combat.roll；无不渲染分支） |
| T-30 表驱动权限探针 | `room_ui_permission_test.dart` | **全绿**（含在全量 2184 内）✓ |

逐文件按钮调用点（改动前 → 改动后）：

```
gp_toolbar        4 → 1 裸 + 3 定宽 = 4
gp_dice_bar       9 → 9 裸（未改定宽，见 §6）
gp_kp_tools       7 → 0 裸 + 7 定宽 = 7
gp_kp_left        6 → 1 裸 + 5 定宽 = 6
gp_scene_check_kp 3 → 0 裸 + 3 定宽 = 3
gp_scene_check_pl 2 → 1 裸 + 1 定宽 = 2
gp_pl_char_card   7 → 1 裸 + 6 定宽 = 7
gp_feeds          7 → 7 裸（本批未加定宽）
gp_privates       2 → 2 裸
gp_status         2 → 2 裸
```

> **修正 lead 的一处预期**：`grep -c "RoomTap(" room_panel_kit.dart` 实测 **= 3**，不是 1
> —— 3 行分别是「构造函数声明」+ `FoldHeader` 内部 1 处 + `ConfirmTwice` 内部 1 处。
> 它们本来就存在（后者是 `ConfirmTwice` 的实现细节）。真正的零改动证据是**整文件 md5 与基线相同**，
> 比计数更强，建议后续用 md5 作为判据。

---

## 5. 逐栏位尺寸独立抽查（1280×800，本人实测，非跑工程师的测试）

| 栏位 | 规格（工程师声明） | **实测** | 组内尺寸种数 | 内容最大需要宽 → 余量 |
|---|---|---|---|---|
| `gpToolbar` 主组 3 个 | 80×40 | **80×40 ×3** | 1 ✓ | 73.8 → +6.2 |
| `gpToolbar` 缩放（不定宽） | ≥80×40 | **87×40** | 见下 | 87（自身） |
| `gpKpTools` 6 个 | 90×48 | **90×48 ×6** | 1 ✓ | 73.8 → +16.2 |
| `gpKpLeft` 素材 3 个 | 48×48 | **48×48 ×3** | 1 ✓ | 38.5 → +9.5 |
| `gpScene` 8 个 | 108×48 | **108×48 ×8** | 1 ✓ | 104.8 → +3.2 |
| `gpPlCharCard` 4 短 | 104×40 | **104×40 ×4** | 1 ✓ | 100.3 → +3.7 |
| `gpPlCharCard` 2 长（满宽） | (0,40)→满宽 | **223.2×40 ×2** | 1 ✓ | 140.0 |
| `gpStatus` 同意/拒绝 | 36 高 | **60.5×36 各 1**，**间距 6.00 ≥6** ✓ | 1 ✓ | —— |
| `gpFeeds` trailing | 44×32 | **44×32**（全屏；新角标另 2 个同值） | 1 ✓ | 30.0 |
| `gpFeeds` 输入行 3 图标 | 48×44 | **48×44 ×3** | 1 ✓ | 30.0 |
| `gpPrivates` trailing | 44×32 | **44×32** | 1 ✓ | 30.0 |
| `gpPlScene` 检定（满宽） | (0,40)→满宽 | **323.8×40** | 1 ✓ | 126.8 |
| `gpDiceBar` 8 个（未定宽） | 90×40 | **90×40 ×7**（`check.opposed` 对玩家不渲染，结构式边界，正常） | 1 ✓ | 87.0 → +3.0 |
| `gpToolbar` 扩展 KP | 90×40 | **`KP` 90×40** | —— | 51 |
| `gpToolbar` 扩展 更多工具 | 90×40 | **90×40**（实测 `find.text('更多工具')=1`） | —— | 86 → +4 |
| `gpToolbar` 扩展 BGM 场景 | 104×40（「特殊」长按钮） | **113.5×40** | —— | 88.5→**113.5**（见观察项 4） |

### 「同一栏位内不存在两种尺寸」逐条判定（用户诉求核心）

- `gpKpTools` / `gpKpLeft`(素材) / `gpScene` / `gpPlCharCard`(4 短) / `gpFeeds`(trailing、输入行) /
  `gpPrivates` / `gpStatus` / `gpDiceBar` ⇒ **组内恰好 1 种尺寸** ✓✓
- `gpToolbar` 是**唯一**存在两种宽度的栏位：主组 `{87, 80, 80, 80}`、扩展 `{90, 90, 113.5}`。
  按用户原话「如果一个栏位有一个比其他的按钮都长的按钮，那就让这一个特殊一点」，
  `缩放(87)` 与 `BGM 场景(113.5)` 就是那两个「特殊」的 ⇒ **符合口径，不判失败**。
- `gpPlScene` 技能 chip 是唯一不定宽组（技能名数据驱动），只统一高 32 + 最小宽 90 ⇒ 已由规格豁免。

---

## 6. 排布合理性与「无孤行 / 无横向溢出」

### 6.1 行数（本人按 centerY 聚类实测）

| 屏 | 栏位组 | 行数 / 每行个数 | 判定 |
|---|---|---|---|
| 360×640 | `gpToolbar` 主组 | 1 行 `[3]` | ✓ |
| 360×640 | `gpDiceBar`（7 项） | 3 行 `[3,2,2]` | ✓ 无 1 |
| 360×640 | `gpScene` 8 | 4 行 `[2,2,2,2]` | ✓ |
| 360×640 | `gpPlCharCard` 4 短 | 2 行 `[2,2]` | ✓ |
| 412×915 | `gpToolbar` 主组 | 1 行 `[3]` | ✓ |
| 412×915 | `gpScene` 8 | **3 行 `[3,3,2]`（3 列）** | ✓ 无 1（但见观察项 2） |
| 412×915 | `gpDiceBar`（7 项） | 2 行 `[4,3]` | ✓ |
| 412×915 | `gpPlCharCard` 4 短 | **2 行 `[3,1]`** | **✗ 第 4 个（`AI RP`）孤行** |
| 1280×800 | `gpToolbar` 主组 | 1 行 `[3]` | ✓ |
| 1280×800 | `gpKpTools`（加怪 + 5 工具 + 清除 = 7 项） | **4 行 `[1,2,2,2]`** | ✓（首行「加怪」独占是**设计意图**：留在表单下方，不参与网格；其余 2×3 无孤行） |
| 1280×800 | `gpScene` 8 | 4 行 `[2,2,2,2]` | ✓ 真 2 列 4 行 |
| 1280×800 | `gpPlCharCard` 4 短 | 2 行 `[2,2]` | ✓ |

**结论**：`gpKpTools` 行数 4 ≤ 4 ✓（工程师规格要求）；除 `412×915` 的 `gpPlCharCard` 外无孤行。

### 6.2 横向溢出

对 KP 4 个槽位 + 玩家 5 个槽位，在 360/412/1280 三档下逐个检查
「槽位矩形内每个 `RoomTap` 的 left/right 是否落在槽位 ±0.5 内」：

```
全部 27 组检查：hOverflow = 0
（例：360x640/KP/gpToolbar slot=0.0..360.0 maxR=345.0；1280x800/PL/gpPriv slot 1004.8 宽 maxR=1258.0）
```

⇒ **无横向溢出、不需要横向滚动** ✓
（纵向不判：`gpKpTools` / `gpScene` / `gpPlChat` 等面板内部是 `ScrollBox`，子件本来就可能落在视口外，
这是既有设计，与 P16 无关。）

---

## 7. `pubspec.lock` 基线

每次 `analyze` / `test` 都会触发 pub get 改写 url 行，收尾已从
`C:/Users/60965/WorkBuddy/2026-11-08-13-25-14/_gh_backup/pubspec.lock` **逐字节恢复**：

```
sha256 前16 = fa69e59604415960      ← 与基线一致
https://pub.dev     出现 82 次      ← 与基线一致
pub.flutter-io.cn   出现  0 次      ← 与基线一致
cmp -s pubspec.lock _gh_backup/pubspec.lock  →  逐字节一致
```

---

## 8. 观察项（非阻塞，交给 lead 决定是否同批处理）

1. **[P2] 412×915 玩家 `gpPlCharCard` 排成 3+1 孤行。**
   根因：`roomTapWrap2` 是 `Wrap`，104 宽 tile 在 412 档的内容宽 ≈370 能放 3 个，
   于是 4 个变成 `3+1`。代码注释写「3×104+8=320 > [下限] 内容宽 202 → 结构上只能 2 列」——
   这只在**最窄档**成立，412 档会变 3 列。
   建议：本组**固定 2 列**（`RoomTapEqualRow` 两行各 2 个，或 `Wrap` 外套 `SizedBox(width: 2*104+4)`），
   这样 360/412/1280 三档都是 `2+2`，与用户「更整齐」的目标一致。
   （`RoomTapEqualRow` 目前**零调用**，正好可以用在这里，顺带消掉死代码。）
2. **[提示] `gpScene` 在 412 档是 3 列 `[3,3,2]`，1280 档是 2 列 `[2,2,2,2]`。**
   代码注释「`3×108+8=332` > [下限] 格宽 232 → 永远 2 列、不会 3 列」中的「永远」不成立
   （412 竖屏是**单列通栏**布局，格宽 396，能放 3 列）。结果本身不算错（无孤行），
   但注释与事实不符，建议改口径为「窄栏 2 列、通栏 3 列」。
3. **[提示] 两个文件换行符被整体改写**：`gp_toolbar.dart`、`gp_pl_char_card.dart`
   由 CRLF → LF（`_gh_backup` 侧 CR=178/420，新侧 CR=0）。语义 diff 仍可逐行审阅
   （`diff --strip-trailing-cr`），但会让普通 `diff` 输出「整文件替换」，评审成本上升。
   建议后续统一走「保留原 EOL」的编辑方式。`room_game_page.dart` 保持了 CRLF，未受影响。
4. **[提示] `diceLong = 104` 是「下限」不是实际宽**：`BGM 场景` 用的是裸 `RoomTap(minSize: diceLong)`，
   测试字体下实测 **113.5×40**（真机 Roboto 下内容更窄，104 才生效）。
   与 `scenePlTile` 同理，属设计选择；但**没有任何用例钉住这个按钮的尺寸**，
   若将来文案变化不会被发现。
5. **[提示] 工程师的偏离理由 #2 有一个算术不成立的点**：报告称「定宽 88 会让主组在 360dp 掉两行」，
   实测 360dp 工具栏可用宽 348 = 360 − 左右各 6，`88+80×3+4×3 = 340 ≤ 348`，
   **仍然是一行**（实测主组 4 项 = 1 行 `[4]`，zoom 87 + 80×3 + 12 = 339）。
   结论（让缩放按钮保持不定宽）本身是合理的（content=87 > 80，定宽 80 会溢出），
   但理由应改成「内容 87 > 80，定宽则会溢出」，而不是「定宽 88 会掉两行」。
6. **[结论] 另外 3 处偏离规格的判断，我独立复核为「合理」**：
   - `sceneTile 104→108`：实测 `极难成功(4)` 需 104.8，**104 会溢出 0.8** ⇒ 108 正确（余量 3.2）。✓
   - `charTile 90→104`：实测 `AI RP` 需 100.3，**90 会溢出 10.3** ⇒ 104 正确（余量 3.7）。✓
   - `gpScene` 用定宽而非 `RoomTapEqualRow`、`gpKpTools` 的「6 个」口径：与代码事实一致。✓
     （`RoomTapEqualRow` 确实是死代码，但正好可在观察项 1 里用掉。）

---

## 9. 大字体回归的最小复现（交给工程师）

```dart
// test/p16_bigfont_repro_test.dart（可直接跑）
testWidgets('大字体 1.5 倍：gpScene 定宽按钮 overflow', (WidgetTester tester) async {
  tester.platformDispatcher.textScaleFactorTestValue = 1.5;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final f = RoomUiFixture();
  await f.boot(inGame: true);                      // KP 视角
  f.pageBuilder = (String s, String r) => const RoomGamePage();
  useRoomScreen(tester, 1280, 800);
  await tester.pumpWidget(f.pageOf(kHostSeat));
  await tester.pump();

  expect(tester.takeException(), isNull);          // 现在会红：
  // A RenderFlex overflowed by 42.3 pixels on the right.（level/4、level/3、level/-1）
});
```

期望：修复后 4 档字号 × 6 档屏 × 2 视角共 48 格全绿；
建议同时把这条矩阵**并入** `p16_button_unify_test.dart`（工程师现有 P16-12 只测了 scale=1.0）。

---

## 10. 清理证据

| 项 | 状态 |
|---|---|
| 临时探针 `test/p16qa_zz_probe_test.dart` | **已删除**（交付工作树内已无该文件） |
| 临时备份目录 `_p16qa/backup/`（2 个 .dart 备份） | **已删除** |
| 临时日志 `_p16qa/*.log`（8 个） | **已删除** |
| 临时目录 `_p16qa/`（含 `backup/` 子目录） | **已删除** |
| 注入的 2 个源文件 | **已恢复**，md5 与注入前逐一相同（§3） |
| 既有测试 `p16_button_unify_test.dart` / `p10_t6_layout_test.dart` | **一字未改**（本人全程只读） |
| 生产源码 | **本轮零改动**（除临时注入并已恢复的 2 个文件） |
| `pubspec.lock` | **逐字节恢复**（§7） |

---

## 11. 一句话总结

**改造本身的质量是高的**：6 个栏位尺寸逐像素达标、组内严格同尺寸、零横向溢出、
按钮零增减、`enabled` 语义零漂移、零改动核验全过、全量 2184 全绿 —— 用户诉求的
「同一栏位一样大 + 更整齐」在主路径（默认字号）上**真实达成**。

**但定宽引入了大字体下的 RenderFlex overflow（1.3/1.5/2.0 三档 36/48 格全红，最大 87.8dp）**，
这是本批唯一阻塞项，需要 `RoomTapTile` 做一处 `withClampedTextScaling`（或等价）处理。
另建议顺手修掉 412 档 `gpPlCharCard` 的 3+1 孤行。
