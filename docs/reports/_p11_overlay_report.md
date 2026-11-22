# P11 · 去蒙版 / 圆角 / 候选卡头部 修复报告

**结论：IS_PASS**（`flutter analyze` 零问题；本轮 7 个目标测试文件 117 组全绿；新增 `test/p11_overlay_test.dart` 13 组）

工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`

---

## 0. 一句话总览

| 用户原话 | 根因 | 改法 | 文件 |
|---|---|---|---|
| 「两个按钮有一层暗色蒙板，显得灰蒙蒙，去掉，直接显示原图」 | 横幅左侧压了 `black@0.55→0.05` 当"文字安全区" | 换成**跟随皮肤的极淡侧渐变**（亮 `<白@0.38>`、暗 `<黑@0.42>`，右侧透明）+ 文字阴影；**不再靠压黑读字** | `lib/ui/home_page.dart` |
| 「英灵殿…你给弄成一样的」 | 上一代英灵殿素材把三段字烧进图里，所以那张卡**没有任何叠字**、只挂一个右下角计数角标 | 新素材（无字、左留白）后，两张卡走**同一套**「竖金条 + 标题 + 张数副标题」，角标删除 | `lib/ui/home_page.dart` |
| 「已保存的角色卡 4 个边角被裁切（仅亮色）」 | 旧亮色素材**自己带圆角**（实测 768 高图 r≈41px ≈ 9dp），而 `ClipRRect` 按宽度算 `w*0.045`（≈14.8dp）＞ 素材圆角 → 裁切线切进金框的弧里 | 圆角改成**全站统一 `Radii.md`=14**，两张卡共用同一个常量；不对横幅做任何 scale/overflow | `lib/ui/home_page.dart` |
| 「亮色选规则…这个卡片也灰灰的，去掉这层灰的蒙板」 | 亮色下压 `black@0.78→0.46→0` | 渐变**跟随皮肤**：亮 `<白@0.45→0.18→0>`、暗 `<黑@0.55→0.22→0>`；文字加阴影；顺手删掉给旧图打的「放大 1.753 裁金边」补丁 | `lib/ui/create/rule_pick_page.dart` |
| 「一键出卡…背景图最上方的两条杠和头像、名字、规则交叉」 | **不是 App 画的横线**，是**卡面底纹图 `b1_card_face_3x4` 自带的双线金框**（实测横线在 0.2% / 1.5~1.9% 图高），`BoxFit.cover` 铺满后正好落在卡片顶端 1~10px，从头像/姓名/徽标背后穿过 | 底纹改成独立图层 + **顶部全透明淡出**（0→4% 全透明、4%→12% 淡入），线条被擦掉；头像/姓名/徽标**布局与 Key 一个字都没动** | `lib/ui/summary_card.dart`（见下方"越界说明"） |

---

## 1. A · 档案横幅：去黑蒙版 + 两张卡同一套叠字

### 1.1 根因
`home_page.dart` 的 `_RosterBanner` 里，给"图上留白区"压了两档黑：

```dart
Colors.black.withValues(alpha: 0.55),  // 左
Colors.black.withValues(alpha: 0.05),  // 右
```

这是给"图上有字 + App 也叠字"做的压暗。新素材左侧本来就是浅色留白，再压黑 = 整块发灰（用户描述的"灰蒙蒙"）。

### 1.2 改法（`lib/ui/home_page.dart:327` 起）
* 渐变改为**皮肤相关**、**只压左侧**：

```dart
final Color veil = dark ? Colors.black : Colors.white;
colors: [veil.withValues(alpha: dark ? 0.42 : 0.38), veil.withValues(alpha: 0)];
```
  判据用 `Palette.isDark`（`home_page.dart:403`），不写死。
* 可读性改由 **`Shadow`** 兜：浅底给白色光晕、深底给黑色光晕，`blurRadius: 6`（标题与副标题都用，`home_page.dart:437/451`）。
* **两张横幅都叠标题**：英灵殿从"零叠字 + 右下角计数"改成和已保存完全一样的
  `竖金条(3×15) + 标题 + 一行副标题`，**同一个 `_RosterBanner.build`**，没有第二份布局。
  * 英灵殿副标题 = `暂无长眠者` / `N 位长眠者`（文案一个字没改，老用例继续成立）。
  * `Semantics(label: '英灵殿', button: true)` 保留（读屏契约不变）。

### 1.3 右下角「N 位长眠者」角标：**选"并入副标题行、去掉角标"**
理由（三选一的取舍）：
1. 新横幅素材**主体就在右半边**（`cards_light` 的书册+羽毛笔、`valhalla_light` 的墓碑+花环），
   浮动角标压在右下 = 直接盖在插画主体上，正是用户抱怨的那类"文字和图打架"。
2. 「已保存」那张的计数本来就在副标题里（`N 位调查员`）。角标去掉后，**两张卡的
   信息结构完全一致**（标题=名词，副标题=数量），才是用户要的"弄成一样的"。
3. 副标题字号 11.5、颜色 `Palette.textDim`，比角标（10px 白字压黑底）更融入版式。

已同步删除 `_CornerNote` 组件（无引用）。

---

## 2. B · 「已保存的角色卡」亮色四角被裁

### 2.1 实测（不是猜）
用 Pillow 逐像素量了**上一代**素材 `a_home_banner_cards[_light]_2x1.webp`（1536×768）：

* 四角**透明**（alpha=0），沿左上对角线第一次不透明处 y≈13~15px；
* 按行扫描：`y=0 → x≈39`、`y=42 → x=0` —— 解圆方程得**素材自身圆角 r ≈ 41px ≈ 5.3% 图高**（768 高图）。
* 屏上卡高 ≈164dp → 素材圆角 ≈ **8.8dp**；而当时的裁切半径是 `w * 0.045`（328 宽 → **14.8dp**）。
  **裁切弧（14.8）比素材弧（8.8）大** → 裁切线切掉了金框拐角与四角星，
  在亮色（浅底 + 亮金框）下最扎眼，暗色下深底遮住了，所以用户只报亮色。
* 排查过 `Transform.scale` / `OverflowBox` / `FittedBox`：`home_page.dart` 里**一处都没有**（已用 grep + 用例双向确认），
  即"放大导致露直角"这条路不存在。

### 2.2 改法
* 两张横幅共用 `static const BorderRadius _radius = BorderRadius.all(Radius.circular(Radii.md));`（`home_page.dart:361`），
  即 **14dp，和规则卡 / 候选卡同一个圆角**；
* 横幅图 **不放大、不位移**（`ArtImage(fit: BoxFit.cover)`，素材本身就是 2:1，cover 不裁内容）；
* 新素材实测是**方角全出血**（21:21 版：四角不透明、无金框、无四角星）→ `ClipRRect` 成为唯一圆角来源，
  14dp 只负责"把方图画圆"，不可能再"削掉"任何画面。

---

## 3. C · 规则卡：去掉亮色灰蒙 + 删掉旧图裁切补丁

### 3.1 根因
`rule_pick_page.dart` 的压层是写死的黑渐变 `black@0.78 / 0.46 / 0`。亮色皮肤下
"压黑"= 整卡降亮度+降饱和，跟"未开放"的灰度视觉撞车，用户读成"灰灰的"。

### 3.2 改法（`lib/ui/create/rule_pick_page.dart:181` 起）
* 新增 `_scrim()`（`:213`）：亮 `<白@0.45, 白@0.18, 白@0>`、暗 `<黑@0.55, 黑@0.22, 黑@0>`，
  `stops = [0, 0.36, 0.8]`，**右侧完全透明**（原图可见）。
  暗色从 0.78 降到 0.55：新素材左侧是深紫空场，不需要那么黑。
* `chipBg` 跟随皮肤（亮 `白@0.75`、暗 `黑@0.35`）：否则亮色卡上会冒出两块黑胶囊。
* 标题 / 书名 / 状态行都加 `_halo()`（亮白晕、暗黑晕）。
* **删除旧图补丁**：`_innerCrops` 表（`zoom: 1.753`）、`_art()` 里的 `ClipRect + OverflowBox`、
  以及 `_InnerCrop` 类 —— 新六张 `g_rules` 素材实测**图内无边框**（21:12 版：无金线、无四角星），
  补丁若留着只会白裁掉画面。现在统一 `ArtImage(..., fit: BoxFit.cover)` 原图直铺。
* 可选项**仍然不套整体 `Opacity`**；未开放项仍是 `Opacity(0.45) + 灰度矩阵 + 「未开放」标签`（未改动）。

对照度核算（把渐变叠到真图上算的，不是估的）：

| 位置 | 文字色 | 遮罩后底 | 对比度 |
|---|---|---|---|
| 亮色规则卡标题区 | `#8A5F1E` | (221,201,188) | 3.51:1（19px 粗体，AA-large 需 3:1 ✅） |
| 亮色横幅标题区 | `#8A5F1E` | (233,217,201) | 4.07:1（17px 粗体，AA-large 需 3:1 ✅） |
| 暗色横幅标题区 | `#F0C96A` | (48,35,54) | 9.38:1 ✅ |

---

## 4. D · 一键出卡候选卡头部那「两条横杠」到底是什么

### 4.1 查明
`random_create_page.dart` 里**没有任何** `Divider` / `Border(top:)` / 装饰横线（已 grep 确认唯一的分隔线是正文里的一个 `HairLine`，
在**属性区上方**，也就是头部行的**下面**）。

真正的来源是 **`lib/ui/summary_card.dart` 的卡面底纹**：

* 底纹图 `assets/images/b_card/b1_card_face_3x4.webp`（768×1024，亮色版 `..._light_...`）自己画了一圈**双线金框**；
* 逐行扫描亮色版，列 `x = w/2-150`：亮度跳变在 **y=2（0.20% 图高）** 与 **y=15~19（1.46%~1.86% 图高）** —— 正好两条线；
* 卡片用 `Container(decoration: image: artDecoration(..., fit: cover, opacity: 0.42))` 把这张 3:4 竖图铺在整卡上（含头部行）。
  手机宽度下 cover 按高度铺满、整幅可见 → 两条线落在卡顶 **1px / 10px** 处，
  而头部行从头像顶（12px）开始 → 两条金线从序号块、头像、「朱砚舟」、`COC 7th` 徽标背后横穿。
  （暗色版同款线极淡，`opacity 0.5` + 深底，肉眼几乎看不见，所以用户主要在亮色下发现。）

### 4.2 改法
把底纹从 `Container.decoration` 挪到独立图层，并套**顶部淡出**：

```dart
const LinearGradient kCardFaceFade = LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0xFFFFFFFF)],
  stops: [0, 0.04, 0.12],   // 0→4% 全透明（盖掉 0.2%/1.9% 两条线），4%→12% 淡入
);
...
ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: (r) => kCardFaceFade.createShader(r), child: 底纹)
```

* 头像 / 姓名 / 规则徽标那一行背后**再没有任何线条**；纸张纹理从 12% 高度开始淡入，卡面质感保留。
* **头像、姓名、徽标、按钮的布局与 Key 全部未动**（`summary_rule_badge` / `result_use_this_0` 等实测仍在原位）。
* ⚠️ **越界说明**：这个根因落在共享组件 `summary_card.dart`，而不是调度里写的
  `random_create_page.dart`。`SummaryCard` 同时被 AI 结果页复用，改的是**背景装饰**、
  对 AI 页是同样的改善（同样的双线金框问题），不影响任何数据/Key。
  若严格按文件清单执行，可选方案是给 `SummaryCard` 加开关，但那是为一次性需求加参数，故选直接修根因。

---

## 5. 老测试改动（都是**产品行为变更**导致，不是为绿放宽）

| 文件 | 原断言 | 现断言 | 为什么必须改 |
|---|---|---|---|
| `test/p9_rule_pick_test.dart` | `expect(find.text('英灵殿'), findsNothing)` | `findsOneWidget` | 新素材图上**没有字**了，App 叠的这层是唯一可见标题（调度里点名要求同步） |
| `test/qa_probe_test.dart` | 同上 `findsNothing` | `findsOneWidget` | 同上；同时**保留**"唯一语义节点 + button"断言 |
| `test/p10_roster_rule_test.dart` 需求 4 组 | 「首页没有 Text('英灵殿')」+「只留一个 ≤11px 右下角计数（位置断言在右下象限）」 | 「首页有且只有一个 Text('英灵殿')」+「两张卡都是左侧标题+张数副标题，标题/副标题**左边界对齐**、都在左半边、**没有浮动角标**」+ 320dp 不溢出 | 角标已并入副标题（见 1.3），旧的"位置在右下象限"断言与新版式冲突；新版断言强度不低于旧版（还多了两张卡**版式一致性**的几何校验） |
| `test/p10_roster_rule_test.dart` 需求 5 组 | 「暗色 COC 图必须被放大 1.753 倍 + 有 OverflowBox」 | 「两套皮肤都是原图 1:1 直铺、**没有** OverflowBox」 | `_innerCrops` 补丁按调度要求删除，旧断言反向锁着一个已作废的实现 |

其余老用例（p8 首页几何、p10_avatar、create_flow 的 `暂无长眠者`/`1 位长眠者` 文案、p9 的语义断言）
**一个都没改、也没放宽**：英灵殿副标题文案刻意保持原字符串，就是为了不牵动它们。

---

## 6. 新增验收：`test/p11_overlay_test.dart`（13 组）

* **需求 2**：亮色下两张横幅子树的「最大黑色叠加 alpha」`<= 0.05`（`maxBlackAlpha()` 扫描所有
  `DecoratedBox` 的 `color` / `LinearGradient.colors`）；暗色允许但 `< 0.5`；两张卡都有可见标题。
* **需求 2**：两张横幅 `ClipRRect.borderRadius` **完全相同**、都等于 `Radii.md`；子树里
  **没有** `Transform` / `OverflowBox` / `FittedBox`。
* **需求 5**：亮色规则卡可选项**无 `Opacity`**、压层里**一点黑都没有**；暗色压层 `0.4 < a <= 0.6` 且右侧透明。
* **需求 3**：候选卡底纹套 `ShaderMask(blendMode: dstIn)`；`kCardFaceFade` 前两档 alpha=0、
  全透明带 `stops[1] > 0.019`（0.019 = 实测第二条金线位置）；**几何**：遮罩铺满整卡（让开 1px 描边），
  且**头像顶部落在全透明带内**（横线不可能穿过它）；`summary_rule_badge` / `result_use_this_0` 仍在原位。
* **反向自证伪**（3 条纯函数用例）：把旧代码的 `black@0.55→0.05`（横幅）与 `black@0.78→0.46→0`（规则卡）
  喂给同一个判据 `isHeavyBlackScrim()`，**必须判为"重黑蒙版"**，而新版 `white@0.38→0` 必须判为否 ——
  证明前面那些 `<= 0.05` / `findsNothing` 不是空断言。
  （等价于：谁把亮色遮罩改回 `Colors.black.withValues(alpha: 0.78)`，亮色用例立刻红。）

---

## 7. 测试结果

```
flutter analyze                      → No issues found!
flutter test test/p11_overlay_test.dart test/p9_rule_pick_test.dart test/p8_home_ui_test.dart
             test/p10_roster_rule_test.dart test/p10_avatar_test.dart test/qa_probe_test.dart
             test/create_flow_widget_test.dart            → 117 组 全绿
flutter test（全量）                  → 1759 组，其中 3 组在**并发跑全量**时偶发失败，
                                        单文件重跑均全绿（p10_avatar / p10_roster_rule / p10_edu_check 各出现一次，
                                        失败点每次都不在同一组 → 负载型 flake，与本次改动无关）
```

> 说明：`p10_edu_check_test.dart` 属于另一位工程师（edu-tiers）的改动面，我在其文件变动期间跑全量时
> 命中过 3 次偶发失败，单独跑 `flutter test test/p10_edu_check_test.dart` → 31 组全绿。

---

## 8. 遗留 / 需要 lead 知道的事

1. **素材状态（截至 21:21）**：13 张新图已落盘 —— 横幅四张、`g_rules` 六张、`a1_app_bg_light`。
   实测结论：横幅 = **方角全出血、无字、左留白、主体在右**；规则卡六张 = **图内无边框、主体在右、左留空**。
   因此本轮两处"删补丁"（`_innerCrops`）是**安全**的，不会出现旧图那种内框。
   `a_home_banner_valhalla_light_2x1.webp` 现在也是标准 2:1（1536×768，之前那份是 1536×620 —— 那张会把左右裁掉，
   新版已修正）。**若后续两套皮肤还要重出，请维持"2:1 / 方角 / 无字 / 左 40% 留白"**，代码侧不需要再改。
2. **`summary_card.dart` 越界**（见 4.2）：这是需求 3 的真实根因所在；改动只在背景装饰层，
   对 AI 结果页是同样的改善。**没有**碰 `avatar` 相关代码，也没碰 `random_create_page.dart` 的任何一行
   （`RandomCreatePage` 一行未改）。
3. **`dart format` 副作用**：为了让改动可读，我对 `home_page.dart` / `rule_pick_page.dart` / `summary_card.dart`
   跑了 `dart format`。仓库原本不是 dart-format 干净的（不少地方是 3 空格缩进），所以这三个文件会带出
   **纯空白 diff**（语义零变化，`flutter analyze` 仍零问题）。如果有"最小 diff"要求，可以在合入时用
   `git diff -w` 审阅。
4. 未做（本批不在范围）：
   * 首页「开始冒险」四宫格（`_EntryBanner`）仍用 `w * 0.045` 圆角 —— 那四张图未重出，先不动。
   * 亮色横幅的白色遮罩系数 0.38 是按调度给的；若设计上想更"原图"，可以再降到 0.30（对比度仍 > 3:1）。
5. 语义/可访问性：英灵殿的 `Semantics(label:'英灵殿', button:true)` 保留，且现在页面上**同时**有可见
   `Text('英灵殿')` —— 读屏会听到一次标签（不会重复播报两次，因为文本被并进同一个 container 节点）。
