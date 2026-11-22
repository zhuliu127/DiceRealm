# P12 · UI 补齐与双模拟器联机核验（v2.22.0 → v2.22.1）

## 需求与结论

用户原话：
1. 「对 emoji 都替换掉，不太搭现在的风格」
2. 「还有一些文字按钮但是没有按钮背景图（主要在跑团房间内，招募大厅、准备房间和游戏中），看着有些别扭，你也都补上吧」
3. 「UI 补齐并接好后你可以用模拟器（包括开多个模拟器测试联机跑团房间功能），有 bug 直接修复」

**结论：三项都完成，并在联机实测中发现并修掉 1 个新 bug。**

## 一、素材决策：这轮没有新增 AI 生成图

按用户给的省钱思路试过 1 张 3×3 平铺图（9 个空态线稿图标，0.038 元），结果**不合格**：

- 背景确实是透明的（alpha 最小 0），但线条周围有大量黄红泼溅、线条本身偏粉
- 试图按饱和度抠掉泼溅 → **保留像素 0.0%**（AI 线色与泼溅颜色分不开）
- 正好印证用户「小图标用 AI 生会有脏像素」的经验

**最终方案（零生图成本）**：
- **空态图标**：`EmptyState` 新增 `icon` 参数，用 Flutter Material Icons（矢量、同字族、线宽圆角天然一致），优先级 `art > icon > emoji`，`emoji` 保留为最后兜底
- **按钮底色**：`RoomButtonSkin` 用代码画（`Palette.surface2` + `Palette.border` + `Radii.md`），与既有面板/chip 同一套 token，不生成图片
- 12 个 `EmptyState` 调用点全部挂上 `icon`（或原本就有 `art`），实测无一处还在渲染 emoji

**余额**：仍约 1.54 元（本轮只花掉那 1 张验证用的 0.038 元）。

## 二、emoji 替换

- 全库 UI 原有 113 处 emoji（42 种），测试里另有 397 处（369 处是 `★` 要点标记，非 UI 断言）
- 全部换成 Material Icons，统一尺寸（行内 14 / 按钮 16 / 标题 18）、统一跟随文字色
- **明确保留**（是内容/美术，不是图标）：日志正文里的 `→ ← ✓ ✕ ↻`、撕卡印章 `☠`、首页装饰 `✦`、`EmptyState` 的 `emoji:` 兜底参数、表单里「头像可填 emoji」的示例文案

## 三、按钮底色与一个真实的布局 bug

`RoomTap` 统一套 `RoomButtonSkin`。**第一版实现把 1dp 边框放在 `BoxDecoration.border` 里，边框参与布局，把按钮从 48×48 撑成 50×50**，会把工具栏挤出一行——正好违反用户「布局不要动」。

修法：底色 + 圆角留在 `decoration`，描边改走 `foregroundDecoration`（只绘制、不占尺寸）。视觉口径不变，尺寸回到 48×48。`p10_t3_layout_test.dart` 几何测试全绿。

## 四、限流事故与收敛

三条并行子任务在 8–9 分钟后撞 429（配额重置时间是次日中午），但**已落盘 28 个 lib 文件 + 3 个测试文件**，不是空手失败。

现场状态：`analyze` 2 个警告、`flutter test` 9 组红（2038 中）。收敛时发现：

1. **测试自己的正则编译不过**：`RegExp('[\u{1F300}-\u{1FAFF}...]')` 把代理对当字符类范围端点 → `FormatException: Range out of order in character class`。改用「高代理 + 低代理」整对匹配 `r'[\uD800-\uDBFF][\uDC00-\uDFFF]'`。A、B 两组红全是它连累的。
2. **测试文件自相矛盾**：一处断言 `skin.child is Material`（对），另三处断言 `skin.child is Container`（错——`Container` 是 `RoomButtonSkin.build()` 的返回值，不是 `child`）。统一改成从渲染树取 Container。
3. **D 组是真源码 bug**（见上），不是测试问题。
4. 删掉 `p12_emoji_a_test.dart` 的无用导入。

收敛后：`analyze` 零问题、`flutter test` **2038 全绿**。

## 五、双模拟器联机核验（发现并修掉 1 个 bug）

环境：`/d/dev/android-sdk`，AVD `diceA`(5556) / `diceB`(5554)，Android 15 / 1080×2400@420dpi。
`flutter run` 不可用（flutter 工具要调 `reg.exe` 被安全策略拦），绕法：`adb install` + `am start` + `screencap`。
两台模拟器各自有独立虚拟网段，用 `adb -s emulator-5554 forward tcp:4211 tcp:4211` + B 填 `10.0.2.2:4211` 打通。

**结果**：A 建房（NX9BH9）→ B 加入 → 两端都显示「已连上局域网房间（实时同步）」、成员 (1) p1、KP 端「还差：p1」。**双端同步正常**。

**联机中发现的 bug**：两端「成员（1）」那一行都显示 `HP 0 / 0 · SAN 0`，而该玩家根本没绑卡——这是第 7 期修「我的角色卡画假 0 卡」时**漏掉的招募大厅成员行 + 成员详情弹层**（`room_lobby_page.dart:441` / `:497` 直接拼 `hpText · sanText`，没判 `hasCardVitals`）。

修法：两处都加 `hasCardVitals(m)`，无卡显示「未绑卡」；真 0 仍照实显示。新增 `test/p12_lobby_vitals_test.dart` 3 组（无卡 / 有卡显示真值 / 真 0 合法）。

**复核**：重新出包 2.22.1，两台重装，重新联机，双端成员行均显示「未绑卡」，`HP 0 / 0` 消失。

## 六、账目

| 项 | 值 |
| - | - |
| 版本 | 2.22.0+89 → **2.22.1+90** |
| APK | 70,446,288 B / `69624bd8…ea62` |
| `flutter analyze` | No issues found |
| `flutter test` | 2006 → **2041 全绿**（+35） |
| 新增测试 | `p12_emoji_a/b/c_test.dart`、`p12_lobby_vitals_test.dart` |
| 改动 | `lib/ui/widgets.dart`、`lib/ui/room/widgets/room_panel_kit.dart`、`lib/ui/room/room_lobby_page.dart` 等约 30 个 UI 文件 |
| 布局 | `p10_t3_layout_test.dart` 几何实测全绿，尺寸口径未变 |

---

## 七、追加：带卡开团的 E2E 巡检（用户后续要求）

用户：「用随机生成人物卡进跑团房间开始游戏再继续测试一下，看看 UI 布局、各个功能按钮、二级菜单有没有异常」。

**模拟器实况**：一键出卡页真机跑到了（生成 5 张候选，见 `_e2e_random_bottom2.png`），但继续压测时双模拟器反复 OOM 退出（进程被杀、后台 shell 仍在）。此前**双端联机已成功并留证**（`_p12_final_a_joined.png` / `_p12_final_b_joined.png`：房间 NX9BH9、成员 (1)、两端同步）。

**补齐方式**：`test/p12_game_e2e_test.dart` 13 组，用 `RoomUiFixture.boot(inGame: true)`（真实 `room.start` + `scene.mode`，`withSheets` 默认 true → 玩家各带一张完整卡，等价于随机卡进房）：

- **布局**：4 档屏幕（360×640 / 780×320 / 820×1180 / 1280×800）× KP / 玩家 = 8 组，逐组 `takeException() == null`（RenderFlex 溢出会在这里冒出来）
- **功能按钮**：所有 `RoomTap` 都有 `RoomButtonSkin` 底色；逐个点击、无一个抛异常
- **二级菜单**：面板 tab 切换无异常；**遍历按钮真正打开 BottomSheet / Dialog 并关闭**（`opened > 0` 强制断言，避免「找不到入口就跳过」的假绿）；弹层内渲染无异常
- **带卡玩家**：状态区显示真实数值，不再出现「未绑卡」

**顺带审查**：一键出卡页底部「重新随机」是**右下角常驻悬浮 FAB**（需求如此），滚动中途会经过卡片按钮行，看起来像遮住「继续完善」。但代码已有 `padding: EdgeInsets.fromLTRB(16, 6, 16, 96)`，滚到底有 96dp 安全区 —— **非 bug，不擅自改需求**。

## 八、追加：横幅星星压字（用户真机报，v2.22.2）

用户附两张平板横屏截图（暗色 + 亮色都试过）：首页「开始冒险」「角色档案」、规则页「规则系统」，「图里的星星和第一个字重叠了」，并提醒「手机横屏好像也这样，你审查一下」。

**根因**：`a3_section_{adventure,archive}_6x1.webp` 素材左侧约 **2.4%** 处烧了一颗四角星，位置随横幅宽度**线性右移**；而 `SectionBanner` 的文字左边距是**固定 14dp**。

| 场景 | 横幅宽 | 星星位置 | 文字起点 | 结果 |
| - | - | - | - | - |
| 手机竖屏 | ~360dp | 8.6dp | 14dp | 勉强错开 |
| 平板横屏 / 手机横屏 | 760dp+ | 18dp+ | 14dp | **重叠** |

四个调用点（首页 ×2、规则页、名册页）用的是同一套横幅，所以**改组件一处全解**，亮/暗两套素材一起覆盖。

**修法**：新增 `SectionBanner.titleInsetFor(width)`，按宽度取 5% 并钳在 18..46dp（360→18dp / 760→38dp / 1200→46dp，均大于对应星星位置 +8）。只挪文字，**不动素材、不动布局结构、不改字号**。

**回归** `test/p12_banner_inset_test.dart` 7 组：含一条**反向自证伪**（断言旧值 14dp 在 760dp 下确实不够，证明用例抓得住 bug）、多档宽度静态断言、4 档真渲染断言（用 LayoutBuilder 实际宽度，避免父约束钳制导致假红）、亮色主题单独一组。

## 九、最终账目

| 项 | 值 |
| - | - |
| 版本 | 2.22.0+89 → 2.22.1+90 → **2.22.2+91** |
| APK | 70,446,288 B / `9c52ffd1…5d72` |
| `flutter analyze` | No issues found |
| `flutter test` | 2006 → **2061 全绿**（+55） |
| 新增测试 | `p12_emoji_a/b/c_test.dart`、`p12_lobby_vitals_test.dart`、`p12_game_e2e_test.dart`(13)、`p12_banner_inset_test.dart`(7) |
| 生图成本 | 0.038 元（1 张验证用，未采用）；余额约 1.54 元 |

---

## 十、追加：死亡提示条两个骷髅（用户真机报，v2.22.3）

用户附暗色/亮色两张截图：已撕卡角色卡详情顶部「这名调查员已经死亡」提示条里**并排两个骷髅**——左边「圆圈+骷髅头」素材图、右边一个黑白 emoji `☠`。要求删掉右侧 emoji，保留左边图标。

**代码**：`lib/ui/card_detail_page.dart` 死亡提示条的 Row 里，
`ArtImage(Art.rippedStamp)` 之后紧跟 `SizedBox(6)` + `Text('☠')` + `SizedBox(8)`。
那个 `☠` 原本是注释里写的「图缺失时的语义兜底」（P12 去 emoji 时按「撕卡印章是美术元素」的理由保留了它，属于误判——它和印章是**两个独立元素**，不是同一个）。

**修法**：
1. 删掉 `Text('☠')`，把两段间距合成一个 `SizedBox(10)`（避免留下 6+8=14 的松垮间距）
2. 保住「缺图有语义标记」的原意图：给 `ArtImage` 加可选 `fallback` 参数（默认 `null` → 老行为完全不变，`errorBuilder` / `frameBuilder` 仍铺皮肤表面色），这一处传 `Icon(Icons.dangerous_outlined, ...)` 矢量图标。既不是 emoji，也不再是空白方块。

**回归**：在 `test/create_flow_widget_test.dart` 用例 ④（已撕卡的卡只出现在英灵殿）里加两条断言：
- 没有单独的 `Text('☠')`（精确 `data.trim() == '☠'`，不会误伤别处的 `☠ 已撕卡` 文案）
- 仍有 `ArtImage(Art.rippedStamp)`

**反向自证伪**：把 `Text('☠')` 注回去 → 用例 ④ 立即红；恢复后 SHA `c38c1cbe…` 逐字节一致。

## 十一、最终账目（更新）

| 项 | 值 |
| - | - |
| 版本 | → **2.22.3+92** |
| APK | 70,446,380 B / `affd5ee9…95ce` |
| `flutter analyze` | No issues found |
| `flutter test` | 2006 → **2061 全绿**（+55） |

---

## 十二、追加：纯色卡面 + 加入路由（v2.23.0）

### 12.1 暗色角色卡列表两侧两道杠

用户截图（暗色「角色档案」9 位调查员 / 「英灵殿」1 位长眠者）：卡片左右各一道竖杠（普通卡金色、英灵殿红色），要求「也改成纯色图」。

**根因**：`roster_page.dart` 的 `Ink` 用 `artDecoration(Art.cardFaceFor(...))` 铺底纹。`b1_card_face_3x4.webp` / `b1_card_face_light_3x4.webp` 两张 3:4 素材**图内烧了左右两道金色竖线 + 内圈细框 + 四角花纹**；列表卡片是横向长条，`BoxFit.cover` 会把竖图裁成中间一条，两道竖线正好落在卡片左右边缘。代码本身已经用 `Border.all` 画了唯一边框，图里的框是多余的第二层（违反「图内不许有任何边框，由 App 画唯一边框」的既有约定）。

**修法**：用代码（PIL）重出两张**纯色径向渐变底纹**，不花生图 API 的钱，也避开上次 AI 线稿的脏像素坑：
- 暗色 `#261B34 → #181123`、亮色 `#FAF3EA → #EBDECE`，768×1024 保持 3:4
- 叠一层 `seed=20261111` 的高斯噪声（σ=1.3）做极淡质感，肉眼不可见但避免退化成纯色块
- 校验：尺寸、色数（171 / 297）、方差（86 / 105）、**相邻列亮度尖峰 < 2**（竖线会形成尖峰，径向渐变不会）

> 体积阈值的小结：纯色渐变被 webp 压到 6~8KB 是**正常**的，不能拿「复杂插画 >10KB」的标准判它为坏图。改用「色数 + 方差 + 边缘尖峰」三项判定才贴合纯色图。

亮色素材也一并换掉（用户没提，但同类型 UI 风格要一致；亮色那张原本也有金色装饰框，只是浅底上不明显）。`Art.ruleCardFor()` 的 fallback 也指向 cardFaceFor，同样受益。

### 12.2 「公网加入失败 HTTP404」——加入路由误判

用户描述：点过一次「开公网房间」后，再「搜索附近的房间」加入就报「公网加入失败：加入失败 HTTP404」，杀进程重进也一样，怀疑「配置了公网服务器所以加入都走公网」。

**真因跟公网配置无关**：
1. `lan_server.dart:572` `_baseFor(ip) => 'http://$ip:$boundPort'` —— **局域网 UDP 广播里的 base 本来就带 `http://`**
2. `cloud_room.dart` 旧 `isCloudBase()` = `startsWith('http://') || startsWith('https://')` —— 把任何 http 地址都当公网中继
3. `_join()` 里 `if (isCloudBase(base))` → 朝 `http://192.168.x.x:4211` 发**云端 API** → 404 →「公网加入失败」

「附近的房间」自动填的地址一定带前缀，所以**每次都失败**，看起来像「配置被持久化了」。之前双模拟器联机成功是因为手填的是不带 `http://` 的 `10.0.2.2:4211`，恰好绕过了误判。

**双保险修法**：
1. `isCloudBase` 改为按**主机**判定：本机 / RFC1918 私有网段（10. / 172.16-31. / 192.168.）/ 链路本地一律算局域网；只有公网域名或公网 IP 才算中继
2. 新增纯函数 `shouldJoinCloud(base, fromDiscovery: ...)`：`_openNearby()` 传 `fromDiscovery: true`，**UDP 发现的一律走局域网**（广播只能来自同网段，与地址长什么样无关）。以后即使 `isCloudBase` 口径再变，这道保险也还在

**测试**：
- 修正 `p10_t1_cloud_room_test.dart` 那条**前提就错**的契约（测试名写「局域网是 ip:port」，但广播实际带 http://）：`isCloudBase('http://192.168.1.7:4211')` 从 `isTrue` 改 `isFalse` —— 是**收紧**判定，不是放宽断言；并补 10 条地址用例
- 新增 `test/p12_join_routing_test.dart` 18 组：7 种局域网地址 × 发现/手输两路、公网域名仍能走云端、发现来源的强保险、空地址

## 十三、账目（更新）

| 项 | 值 |
| - | - |
| 版本 | → **2.23.0+93** |
| APK | 70,381,104 B / `32fc23c1…81c4` |
| `flutter analyze` | No issues found |
| `flutter test` | 2061 → **2079 全绿**（+18） |
| 生图成本 | 本批 0 元（纯色底纹用代码生成） |

---

## 十四、追加：UI 素材接入审查（v2.27.0）

用户：「用另一个模型检查发现还有一些生成的 ui 图没有接入 app，审查一下是否需要接入，需要接入的直接接」。

### 审查结论（架构师 `_p13_asset_audit.md`，44KB / 408 行）

以**当前代码**（v2.26.0+96）为准重算三层差集，不照抄 2026-11-10 的旧接入报告：

| 层 | 计算 | 结果 |
| - | - | - |
| 工程 `assets/images/` | 实文件 | **106** |
| `ui_assets/` 成图（排除 `_raw`/`_atlas`/`_preview`/`_legacy`） | 实文件 | **119** |
| 差集 A | 源包有、工程无 | 24（反向 11 是工程后续新增：亮色版 3 + `g_rules` 6 + `banner_cards` 2） |
| **差集 B** | 工程素材 → `art.dart` 声明 | **0**（71 个精确常量 + 5 个动态模板覆盖全部 106 个文件，零断链） |
| 差集 C | 已声明但全库零渲染 | 50（56 已渲染） |
| 待裁决 | 24 + 50 | **74** |

**结论：需要接入 1 项，不接 73 项。**

> **对「还有生成图没接入」的直接回答**：确实有 74 项「在包或源包里但没渲染」，但**不是漏接**，而是 2.17→2.26 十几期迭代里被矢量图标化、代码绘制、换规格、房间布局冻结**主动淘汰/替代**的结果。旧报告第五节列的「下一批候选」（`e1` 游戏背景、`d1` 入口头图、`c1` 向导头图、`d2` 大厅头图、`f1` sheet 头图、`g_rules` 6 张、`f3/f4/f5` 状态插画）**现在都已接入**。

**不接 73 项的理由分布**：R1 已被矢量 Material Icons / 代码绘制替代 **35**（28 张 icons 全部 + b2/b5/c3/f3/f4/f6/a3_section_header；P12 去 emoji、P9「小图标一律矢量」是明确项目决策，接回去是倒退）；R3 会动 `lib/ui/room/**` 布局骨架 **16**；R9 当前 UI 压根没这一层 **9**（5 张随机卡背 + B3 卡背 2 + 舞台默认/空态层 2——候选卡现在直接渲染 `SummaryCard`，没有「未翻开卡背」交互态）；R7 已被后续换规格的图替代 4；R2 图内烧边框/竖线 3（含 `b1_card_face*` 旧版，接回去会重现 v2.23.0 的金色竖杠 bug）；R8 往滚动列表顶部塞装饰图 2（A2 首页头图、D5 存档槽，会重演「续玩看不见」）；R6 素材缺陷 3（C5 卡背各 851–986KB、A4 烧字、dice 黄斑）。

### 唯一接入项 A1：横屏游戏背景

`Art.gameBgLand`（`e2_game_bg_land_16x9.webp`，1920×1080 纯渐变、无框无字、10,014 B）**声明了但全库零渲染**。`room_game_page.dart` 恒用 `Art.gameBgFor(b)` 取 9:16 竖版，`BoxFit.cover` 在平板横屏（1524×1016）下上下各裁约 31%，只剩中央暗带；而工程本身已支持横屏多列。

**主理人 Q1 裁决：接入**。虽落在 `room/**`，但属**纯装饰层换图**——只改 `ArtImage` 的 path 实参，不碰 `Stack(fit: StackFit.expand)` / SafeArea 紧约束 / `RoomGridSpec.of` 分栏判据 / dock-folded 档位 / `RoomSlot`·`RoomKeys` / 共用 gap，符合「布局骨架冻结」红线；用户上一批需求也正要求改 KP 平板横屏。

**改法**（2 个生产文件 + 1 个新测试文件）：
- `art.dart` `gameBgFor(b, {bool landscape = false})`，默认分支逐字不变；横屏暗色取 `gameBgLand`，亮色按 `pick` 的 `light ?? dark` 精神回退 `gameBgLight`（不新出图、零包体增量、无需改 `pubspec.yaml`）
- `room_game_page.dart` 用 `MediaQuery.of(context).size` 判横屏（**不用全库零命中的 `MediaQuery.sizeOf`，避免版本兼容风险**），`landscape` 只传给 `gameBgFor`，不进任何布局逻辑
- `test/p13_landscape_bg_test.dart` 5 条纯函数断言 + 反向自证伪

### QA 独立验证（`qa_p13_landscape_bg_report.md`）

工程师如实登记一处**覆盖空白**：纯函数测试锁不住「调用点是否真的传了 `landscape`」——把它改回不传参，现有测试仍全绿。QA 补 `test/p13_landscape_bg_wiring_test.dart` **10 条 widget 级用例**，5 场景 × KP/玩家双视角，用 `find.byWidgetPredicate((w) => w is ArtImage && w.path == X)` 精确断言页面**实际渲染**的路径；期望值硬编码 `Art.*` 常量（绝不用被测实现生成期望），并加方向守卫（挡住默认 800×600 横屏掩盖竖屏分支）、皮肤守卫、「三张背景恰好一张」集合断言。

**反向证伪针对接线**：去掉 `landscape: landscape` → 4 条横屏暗色用例真变红（另 6 条按设计仍绿，因为四象限里只有「横屏+暗色」能区分接/没接）→ 逐字节恢复 `b90fcdd2…3b9bd`、连续 3 次采样稳定、复跑 10 条全绿。

| 项 | 结果 |
| - | - |
| `flutter analyze` | No issues found! |
| `flutter test` 全库串行 | **2167/2167**（2152 基线 + 5 + 10），无 `did not complete` |
| 反向证伪 | 真红 + 逐字节恢复 |
| `pubspec.lock` | `fa69e596…` / 82 处 pub.dev / 0 镜像（出包与跑测试各被镜像改写一次，均逐字节恢复） |
| 资源在包 | 106 条 = 工程 106，e2 在包 10,014 B |
| 生产源码 bug | **0** |

### 出包与实证

- 版本 **2.26.0+96 → 2.27.0+97**（`pubspec.yaml` + `app_version.dart` 同改，`app_version_test` 3/3）
- APK **70,561,384 B / `5f13bc24…e817e6f4`**，debug 签名
- **AOT 真重编**：三 ABI `libapp.so` SHA 逐 ABI 全变（`74546fbd` / `70639d3e` / `c5252abc` vs 旧 `6d04ad76` / `ad816700` / `f305c6e6`）；尺寸巧合相同（8979336/9962056/9241480）不作为证据
- 字节级字面量：`2.27.0` 命中 1、`2.26.0` 命中 0、`e2_game_bg_land_16x9.webp` 与 `landscape` 均命中
- 环境：代理端口当日 11884（探活后临时改两处 `proxyPort`，出完 `cmp -s` 逐字节恢复 9194）；`build/` 是实目录；出包前清 `.dart_tool/flutter_build` + `build/app/intermediates/flutter`

> **编码口径补正**：Dart AOT 里**纯 ASCII 字符串是单字节（latin-1/OneByteString）存**，中文才是 UTF-16LE。字节级 hex 搜索要按字符类型选编码——本次用 UTF-16LE 搜 `2.27.0` 得 0 命中（假阴性），换 latin-1 立刻命中 1。

## 十五、账目（更新）

| 项 | 值 |
| - | - |
| 版本 | → **2.27.0+97** |
| APK | 70,561,384 B / `5f13bc24…e817e6f4` |
| `flutter test` | 2152 → **2167 全绿**（+15） |
| 新增文件 | `_p13_asset_audit.md`、`qa_p13_landscape_bg_report.md`、`test/p13_landscape_bg_test.dart`(5)、`test/p13_landscape_bg_wiring_test.dart`(10) |
| 生产改动 | `lib/ui/art.dart`、`lib/ui/room/room_game_page.dart`（共 2 文件） |
| 生图成本 | **0 元**（接入的是已有素材，未生成新图） |

---

## 十六、P15：亮色背景补齐（用户推翻 P14 裁决）

### 16.1 用户驳回与重开

P14 我裁决「不需要生图」，最硬依据是「平板竖屏同样裁掉金饰 + 用户长期未反馈」。用户明确驳回：

> 「平板竖屏同样裁掉那圈金饰，**我是根本不知道有这个金饰**，你补应该生成的图吧，横屏竖屏都可以补。」

**这条依据的前提不成立**——用户不知道有这个装饰，「未反馈」不能解释为「接受」。裁决作废，按「横竖屏都补」重开。

### 16.2 生成 2 张图（规格见 `_p15_bg_generation_spec.md` v1.1）

| # | 动作 | 文件 | 尺寸 | 服务 |
| - | - | - | - | - |
| ① | 新增 | `e2_game_bg_land_light_16x9.webp` | 1920×1080 | 亮色横屏（1.5 / 2.156） |
| ② | 定向覆盖 | `e1_game_bg_light_9x16.webp` | 1080×1920 | 亮色竖屏（0.464 / 0.667） |

**构图重构**：原「顶部一条横贯拱形」→ **「沿安全区内侧环绕四边的断续有机淡金藤蔓环带 + 四角四芒星锚点 + 大半径柔光」**，装饰离边 ≥18%（预留 `post.py fit` 二次裁切 7.81%），中心 40% 几乎纯平、中心 60% Δ≤12/255，**顶部中央段对比度降到侧边 50%** 保顶栏小字。

**为什么覆盖原文件而非新增**：常量值不变 → 竖屏所有 `expect(..., Art.gameBgLight)` 断言**逐字不动**；不制造孤儿素材（新增文件会让旧的 15,574 B 仍被打进包）。三重保险：主理人先备份（工程外 `_bg_backup_20261112/`）、先 `fit` 到工程外临时文件、过全部闸口 + 人工看图才 `cp` 覆盖。

### 16.3 生图过程（3 次迭代，6 次调用 ≈ 0.228 元）

| 轮次 | 模型 | 横版闸口 | 竖版闸口 | 结果 |
| - | - | - | - | - |
| v1 | `gpt-image-2.6-flare` + generations | FAIL [4,8] | FAIL [4] | 母题完全成功，但金饰偏淡（std_all 4.06 / 锚点差 7.71） |
| v2 | flare + 定点微调 prompt | FAIL [4,7] | FAIL [4,7] | 金饰最清楚（锚点差 30.98），但「离边 ≥22%」让环带内移侵入中心（Δ19.20） |
| v3 | `sunburst` + edits（ref=原亮竖 PNG） | FAIL [4,8] | FAIL [4,7] | 洗得过淡；竖版还被旧构图带回来（Δ35.63） |

**结构性矛盾**：这类「中心必须极平（Δ≤12）」的低对比底图，AI 出图的 `std_all` 天然落在 3~5.5，与闸口第 4 项（std≥6）存在张力。v2 一旦把金饰做清楚，中心就必然被侵入。

**最终交付 = v1 AI 母图 + 可复现的径向对比度放大**（`_p15_enhance_probe.py --gc 1.35 --go 0.70 --lo 0.60 --hi 0.95`，中心 60% 恒定增益、只在外圈平滑递增，**不增删任何图形元素**）。这是唯一同时通过 12 项闸口的方案，非「硬接不合格图」，脚本与参数可复现可审计。代价：中心有极淡云状斑驳（原渐变被放大，App 上还有 `DecoratedBox` 渐变叠层 + 密集面板，实际不可见），已如实登记。

### 16.4 验收

- 12 项闸口：两张均 `IS_PASS: PASS`、自动项 `FAIL=[]`（横：uniq 7273 / std_all 6.89 / 中心 Δ10.79 / 锚点差 10.36；竖：uniq 4814 / std_all 6.21 / 中心 Δ11.73 / 锚点差 14.16）
- 四朝向 `cover` 裁切模拟：横版 `land_tablet` 4/4、`land_phone` 4/4；竖版 `portrait_phone` 4/4、`portrait_tablet` 4/4
- **主理人本人逐张实看 4 张裁切模拟图**：平板竖 0.667（用户点名场景）金藤环带完整环绕、四角四芒星清楚、中心干净平坦；手机横 2.156 与平板横 1.5 同样完整不残缺
- 生产代码只动 `lib/ui/art.dart`：加 1 常量 `gameBgLandLight` + 改 1 行 `pick(gameBgLand, gameBgLandLight, b)` + 订正注释；`room_game_page.dart` / `pubspec.yaml` 零改动
- 测试：`p13_landscape_bg_test.dart` 5→7 条、`p13_landscape_bg_wiring_test.dart` 10→12 条（既有 44 条断言值零改动，`_kAllGameBg` 3→4 张更强、forbidden 2→3 张、新增 2.156 极值场景）

## 十七、P16：房间栏位内按钮统一尺寸 + 重排

### 17.1 用户诉求

> 「跑团房间-游戏中，玩家和KP视角，**同一栏位的按钮，你都改成大小相同的（宽高相同）**，如果一个栏位有一个比其他的按钮都长的按钮，那就让这一个特殊一点，让其他按钮改成相同大小，然后**重新排布一下，让按钮更整齐**。」

### 17.2 审计（`_p16_button_audit.md`，70 处栏位内按钮 / 44 条测试依赖）

三个反直觉发现，直接决定方案：
1. **不能改 `RoomTap` 内部**：`p12_emoji_b_test.dart:256` 断言裸 `RoomTap(label:'好')` 精确 `Size(48,48)`，`:273` 断言显式 `minSize: Size(96,40)` 精确等于该值。
2. **只改 `minSize` 做不到严格等宽**：`RoomTap` 是 `ConstrainedBox(minW,minH)` + `Align(widthFactor:1)`，实际宽 = `max(内容, minWidth)`，文案长的会被内容撑开。
3. **视觉噪声主因是四种高度混排**（48/40/44/32，工具栏里 48 与 40 直接相邻），但素材行三按钮被 `p10_t7:427-430` + `p10_t7_b:394-397` 钉死 **≥47.5 高**，所以「全局统一到 40」被堵死。

### 17.3 方案（`_p16_button_unify_spec.md`）

新增 `lib/ui/room/widgets/room_button_size.dart`（300 行）：`RoomBtnSize` 尺寸族 + `RoomTapTile`（`SizedBox(W,H)` 紧约束 + 原样 `RoomTap`，`enabled`/`roomKey` 透传）+ `roomTapFixedGrid2`。**`room_panel_kit.dart` 0 字节变更**（md5 `8e5126d3…` 全程未变）。

| 栏位 | 统一后 | 长按钮例外 |
| - | - | - |
| gpToolbar 主组 | 80×40 | 缩放档位（内容 87 > 80，保持不定宽） |
| gpDiceBar | 90×40（8 个） | 无（原「其他骰子」88 归入同档） |
| 工具栏扩展 | KP/更多工具 90×40 | BGM 场景（下限 104，实测 113.5） |
| gpKpTools | 90×48（2 列网格） | 上传素材（满宽） |
| gpKpLeft | 加怪 90×48 | 上传满宽；素材三按钮保持 48×48（测试钉死） |
| gpScene | 108×48（8 个，2 列） | 无 |
| gpPlCharCard | 104×40（2 列） | 保存 / 推进（满宽） |
| gpStatus | 56×36 不变 | 仅加 6dp 间距 |

**保持原样**：`gp_map_stage`（4 个 36×32 浮层控件）、`gp_feeds` 花幸运/推动（132×30 行内）、`gp_pl_notes` 行尾删除（36×30）、`gp_combat`（`下一个行动 ▶` 实测内容 115.5，等宽必溢出）。

**增行**：零。唯一变化 = `gpKpTools` 5 行 → 4 行。

### 17.4 ★ 大字体回归（QA 抓到，本批新引入）

`RoomTapTile` 的 `SizedBox` 是紧约束，而 `Text(fontSize:13)` 默认跟随 `MediaQuery.textScaler` → 用户调大系统字体就撑破。QA 实测 **48 格中 36 格红**（1.3 倍就全红，最大溢出 87.8px），并用「换回旧版裸 RoomTap 溢出消失」证伪为**本批新引入**。

修法：`clampBtnText(child) = MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)`，**只包按钮子树**（`RoomTapTile` 内 + 工具栏不定宽缩放钮 + `gp_combat_list` 2 处 + `gp_kp_left` 1 处，共 5 个调用点）。面板正文/聊天/笔记**照常跟随系统字号**（QA 实测 1.5 档下「游戏记录」从 20dp → 30dp 放大，确认没钳整棵树）。**不用 `ClipRect`**（静默裁切更糟）、**不用 `FittedBox`**（会连 icon 一起缩）、**不用 `ellipsis`**（需改 `RoomTap` 内部，属禁区）。

三轮 QA 累计抓出并修掉：
- 第 1 轮：36/48 格大字体溢出（阻塞）
- 第 2 轮：`gpDiceBar` 8 个按钮漏钳（默认字号齐，1.3 倍变 4 种宽度）
- 顺手修 2 处既有溢出：`gp_combat_list` trailing 双按钮（**平板横屏 KP + 1.3 倍字体就溢 4.6px**，用户主力组合）、`gp_kp_left` 的 `ConfirmTwice`
- 留 P17 登记 1 处：`room_panel_kit.dart:291` `PanelTabs`（仅 2.0 倍极端档、3.1px，修它必须破 `room_panel_kit` 硬边界）

最终 **47/48 格干净**，唯一残留即上述 P17 登记项。

### 17.5 测试

- 既有 44 条断言值**零改动**（唯一触碰是 `p10_t6_layout_test.dart:315-320` 的**注释**）
- 新增 `test/p16_button_unify_test.dart` **17 条**：13 条尺寸集合精确断言（`expect(sizes, {Size(90,48)})` 一条同时证明「彼此相等」+「等于规格值」）+ 36 格大字体 + 412 六档 2+2
- 反向证伪 6 次全部真红：摘钳制 / 摘一半（证实「差 0.3px 不足以复现」）/ 除数写回 88 / 真实改宽 / 钳制抬到面板层 / 骰子条补钳前
- **白名单闸门非恒真**（QA 独立验证）：摘掉钳制后整页冒出 237 条 `room_panel_kit.dart:187`，与白名单 `:291` 同文件不同行，**一条未被吞**；别处人为溢出照样红；临时修好 `PanelTabs` 测试立即报错要求删白名单

## 十八、v2.28.0 账目

| 项 | 值 |
| - | - |
| 版本 | 2.27.0+97 → **2.28.0+98** |
| APK | **70,598,536 B** / `60475f58674e864c1d86354e9521c2fd9aec5b8d8a290e305d436db2584b7187` |
| `flutter test` | 2171 → **2188 全绿**（+17） |
| `flutter analyze` | No issues found! |
| AOT 真重编 | 三 ABI SHA 逐 ABI 全变：`108b7914` / `cf6cf6d0` / `036d3ad7`（旧 `74546fbd` / `70639d3e` / `c5252abc`） |
| 字节级字面量 | `2.28.0` 命中 1 / `2.27.0` 命中 0 / `e2_game_bg_land_light_16x9.webp` 1 / `room_button_size.dart` 1 |
| 资源在包 | **107** 条（106 + 1 新背景），两张目标图均在包（29,690 B / 22,798 B） |
| 生图成本 | 6 次调用 ≈ **0.228 元**（余额 1.08 元） |
| 新增文件 | `room_button_size.dart`(300) / `test/p16_button_unify_test.dart`(978) / 2 张背景图 / `_p15_bg_generation_spec.md` / `_p16_button_audit.md` / `_p16_button_unify_spec.md` / `qa_p16_*` 3 份 |
| 生产改动 | `art.dart` + 11 个 room widget + `room_game_page.dart`（3 个扩展按钮 minSize） |
| 硬边界守住 | `room_panel_kit.dart` md5 `8e5126d3…` 全程未变；`sheets/` 19 文件逐字节不变；`RoomSlot`/`RoomKeys`/`roomDockMinWidthOf`/`kToolbarMaxShare`/`grid spec`/`gap` 未动 |
