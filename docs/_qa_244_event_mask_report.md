# QA 独立验收报告 · 2.44.0+114 · 关键事件全屏信息遮罩

> 角色：QA 严过关（独立验证，不复用工程师自证用例）
> 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
> 版本：`2.44.0+114`（pubspec / app_version / local.properties 四处一致）
> 结论：**ROUTE: NoOne** —— 四条需求 A1~A4 全部独立证明成立，全量回归 2620 用例 0 失败 0 skip

---

## 1. 结论与总评

**ROUTE: NoOne**（无需返工）。

用户报的三个症状（图被裁、不是全屏遮罩、多人连发挤掉信息）在
`room_event_banner.dart` / `room_ui_local.dart` / `room_notice_overlay.dart`
三处被真实修掉，且修复方式不是「调参糊住」而是**结构性**的：

- 裁切 → 主图层改成 `Center(AspectRatio(16/9) + BoxFit.contain)`：**框与图比例相等
  ⇒ contain ≡ 不裁不变形**，与屏幕尺寸解耦（400×860 / 860×400 / 320×568 实测都是 16/9）；
- 全屏遮罩 → `Stack(fit: expand)` + `Positioned.fill`，底色 `0xA60B0D11`（alpha 0.65）；
- 不丢信息 → 删掉 `kBannerMax=2`，队列不限长，「队首=当前条 + 等待队列」；
- 点击关闭 → `GestureDetector(behavior: opaque)`，**仅 `onDismiss != null` 时建**
  （没有遮罩时连 RenderObject 都没有，比 `IgnorePointer` 更彻底）。

我用 5 条**与工程师不同**的改坏实验反向证伪了自己的用例（见 §4），每条都真的红，
说明这批用例不是恒真断言。

---

## 2. 独立用例清单（`test/qa_244_event_mask_test.dart`，22 条）

| # | 用例名 | 断言要点 | 验收点 |
|---|---|---|---|
| 1 | 五类 kind 的底图一一对应，且互不重复 | `EventBannerArt.of(kind)` == `Art.e18Banner*` 逐条相等；5 个路径互不重复（纯 Dart 镜像不许与单一真源跑偏） | A1 |
| 2 | 五张底图资源在磁盘上真实存在 | `File(art).existsSync()` + 体积 > 1KB + 命名带 `_16x9`（缺图 = 用户看到一块纯色） | A1 |
| 3 | ★ 真实 diff · 死亡 | 跑 `CriticalEventTracker.sync` 真实跃迁：`kind==death`、`art==Art.e18BannerDeath`、标题含角色名、有副行；**再写一次不重复弹** | A1 |
| 4 | ★ 真实 diff · 永久疯狂（撕卡） | `kind==ripped`、`art==Art.e18BannerRipped`、去重键 `ripped:p1` | A1 |
| 5 | ★ 真实 diff · 疯狂（临时/不定/新疯狂症） | 三条跃迁各自产出，`art` 都是 `Art.e18BannerMadness` | A1 |
| 6 | ★ 真实 diff · 进入战斗/战斗结束 | 群体事件**只弹 1 条**（不是每人一条）；start 与 end 底图不同；开战副行带参战名单 | A1 |
| 7 | ★ 端到端：真实 watcher + 真实 combat.start/combat.end | 挂真 `RoomEventBannerWatcher`，用真实 host action 开战/结束 → `local.banners` 出现、`ArtImage.path` 等于开战图 / 结束图（证明 watcher 内联 `artOf` 接线真通） | A1 |
| 8 | ★ 五类底图逐一上屏 | 逐 kind push → `art(id)` 的 `ArtImage.path` 对应、`fit==BoxFit.contain`、宽高比 16/9 | A1 |
| 9 | ★ 遮罩铺满整屏，底色 alpha 严格 < 1 | `getSize(mask)==400×860`；**读渲染树 `ColoredBox.color.a` < 1.0 且 > 0.40**；氛围层也铺满 | A2 |
| 10 | ★ 主图层也不挡房间 | 主图外层 `Opacity.opacity < 1.0`；`(1-mask.a)*(1-art.opacity)` 房间可见度 **> 0** | A2 |
| 11 | ★ 横屏 860×400 遮罩同样铺满 | `getSize(mask)==860×400` | A2 |
| 12 | ★ 默认 4 秒（边界值） | `pump(3.99s)` 仍在；越过 4s 时 `banners` 清空且遮罩**仍在树上**（淡出中）；跑满后 `findsNothing` | A3 |
| 13 | ★ 点屏幕任意位置（角落 12,12）→ 有可见淡出 | 点击后数据立刻空、遮罩仍在树；半程祖先 `FadeTransition.opacity ∈ (0.01, 0.99)`；220ms 后 `findsNothing` | A3 |
| 14 | ★ 点击节奏（吃两次、第三次恢复穿透） | ①点→关掉；②淡出中 80ms 再点「结束房间」→ `roomTaps==0`；③淡出结束后点→`roomTaps==1`，且浮层内 `GestureDetector` 为 `findsNothing` | A3 |
| 15 | ★ 没有遮罩时是零占位 | `emptyBannerSlot` 尺寸 == `Size.zero` | A3 |
| 16 | ★ 连发 5 条排定时长（结构证明） | 记录 `scheduleDismiss` 收到的时长序列 == `[4s, 2.2s, 2.2s, 2.2s, 2.2s, 4s]` | A4 |
| 17 | ★ 连发 10 条一条不丢、按 id 顺序 | `banners.length==10`；逐条消费记录到的 id == `[1..10]` 无跳号 | A4 |
| 18 | ★ `dismissActiveBanner(id:)` 守卫 | 拿不匹配的 id 关 → 队首不动、长度不变；拿对的 id → 前进一条 | A4 |
| 19 | ★ 点一下只关当前条 | 连推 2 条，点一下 → `activeBanner.id==2`、`length==1`，第 2 条真的上屏 | A4 |
| 20 | ★ 连发 5 条·绝对时刻表 | t=2000/2250/4000/4450/6000/6650/8000/8850/11000/12850 逐点断言当前 id 与「该条真的在屏上」；末条用满 4s；最终 `seen==[1,2,3,4,5]` | A4 |
| 21 | ★ textScaler 1.3/1.5/2.0 不溢出 | 三档下 `takeException()==null`、title/subtitle 都在 | A3/A4 附带 |
| 22 | ★ 极端窄屏 320×568 + 2.0 倍字号 | 不溢出；主图层仍精确 16/9 且不超出屏幕宽高 | A1/A3 附带 |

补充：`A1#2` 的「资源在磁盘存在」与 `A1#1` 的「镜像不许跑偏」是本次新增的
**结构性回归闸**（此前全库没有任何用例覆盖 tracker / watcher —— 我 grep 过，
`test/` 下 0 处引用 `CriticalEventTracker`；这批用例第一次把「state diff → 底图」
这段接上）。

---

## 3. 全量回归

| 项 | 值 |
|---|---|
| 测试文件数 | **189**（既有 188 含工程师新增 `p21_event_banner_mask_test.dart` + 我新增 1） |
| 用例总数 | **2620** |
| 失败 | **0** |
| skip | **0**（`~N` 扫描仅命中一条**用例名**里的字面量 `60~99`，非 skip 标记） |
| 运行方式 | 12 批串行 `flutter test --no-pub -j 1` |
| build 缓存轮换 | 每批前把 `build/{test_cache,unit_test_assets,native_assets}` 改名（`qa244b_<批>_<ts>` 后缀），绕开 `PathExistsException ... cache.dill.track.dill errno=183` |

分批结果（全部 `EXIT=0`）：

```
BATCH=1  +228   BATCH=2  +303   BATCH=3  +214   BATCH=4  +161
BATCH=5  +179   BATCH=6  +209   BATCH=7  +164   BATCH=8  +226 (含我的 22 条)
BATCH=9  +264   BATCH=10 +268   BATCH=11 +263   BATCH=12 +141
```

日志：`build/_qa244_batch_{1..12}.log`、汇总 `build/_qa244_summary.tsv`、
脚本 `build/_qa244_loop.sh`。

---

## 4. 反向证伪表（改坏 → 真红 → 逐字节恢复）

> 自检驱动：`grep -c '\[E\]'`（**不锚行首** —— `flutter test` 的失败行形如
> `00:00 +0 -1: <用例名> [E]`，锚行首会自报 0 形成假象）。
> 每条都确认是**真断言失败**（有 `Expected:` / `Actual:` + 目标用例的 `[E]` 行），
> 不是编译错、不是脚本自身报错。

| # | 改坏方式 | 红的样子（关键断言） | 目标用例 | `[E]` | 恢复后 sha256 |
|---|---|---|---|---|---|
| M1 | 遮罩底色 `Color(0xA60B0D11)` → `Color(0xFF0B0D11)`（不透明） | `Expected: a value less than <1.0>` / `Actual: <1.0>` | A2#9 遮罩铺满整屏 | 1 | `room_event_banner.dart` `f6bfe6c0…61faa` |
| M2 | `dismissActiveBanner` 删掉 `if (id != null && banners.first.id != id) return;` | `Expected: <1>` / `Actual: <2>`（旧 id 把新条吃掉） | A4#18 守卫 | 1 | `room_ui_local.dart` `0e58f8a9…6cc188` |
| M3 | `dismissActiveBanner` 末尾删掉 `_armBannerHead();`（关掉当前条不提升下一条） | `Expected: <3>` / `Actual: <2>`（t=4450ms 卡在第 2 条） | A4#20 绝对时刻表 | 1 | `room_ui_local.dart` `0e58f8a9…6cc188` |
| M4 | `kBannerBurstTtl` 2.2s → 4s（连发不缩短） | `Expected: Duration:<0:00:02.200000>` / `Actual: Duration:<0:00:04.000000>` | A4#16 排定时长 | 1 | `room_ui_local.dart` `0e58f8a9…6cc188` |
| M5 | 主图层 `BoxFit.contain` → `BoxFit.cover`（「图显示不全」的原始根因） | `Expected: BoxFit:<BoxFit.contain>` / `Actual: BoxFit:<BoxFit.cover>` | A1#8 五类逐一上屏 | 1 | `room_event_banner.dart` `f6bfe6c0…61faa` |

恢复方式：`cp build/_qa244_mut/*.bak` + `sha256sum` 逐字节核对等于**工程师自报的 sha**
（`f6bfe6c08379bce6…` / `0e58f8a93d88a218…`），再跑目标用例 **rc=0 全绿**。
改坏前备份 sha 与恢复后 sha 完全一致（见上表）。

> 这 5 条与工程师已做的 6 条（16/9→16/4、去掉连发短时长、`reverseDuration=0`、
> 恢复丢最旧、恢复 `IgnorePointer`、顺序颠倒）**无重叠**。

---

## 5. 口径变化表

**无既有断言被放宽。** 本批只改了 8 个文件，其中 4 个是老门禁文件**完全未被触碰**
（mtime 早于本批 `18:00`）：

| 老口径文件 | 是否被改 | 用例 | 现态 |
|---|---|---|---|
| `test/room_notice_overlay_test.dart` | **未改** | ★ 没有提示时整块不渲染 | 通过 |
| 同上 | **未改** | ★ 浮层不吃点击（IgnorePointer） | 通过 |
| `test/p20_backup_contract_test.dart` | **未改** | 无 ClipRect / 无页面级 textScaler 钳制 | 通过 |
| `test/room_ui_permission_test.dart` | **未改** | 锚点 25 / 62 / 62 | 通过（21 条全绿） |
| `test/room_ui_lobby_test.dart` | **未改** | 隐私白名单门禁 + jsStr 预算冻结 | 通过（18 条全绿） |

本批实际改动文件（`find -newermt "2026-11-21 18:00"`）：

```
18:25  lib/app_version.dart                          (版本号)
18:35  lib/ui/room/room_event_banner_watcher.dart     (工程师报：仅注释)
18:37  lib/ui/room/room_game_page.dart               (工程师报：仅注释)
18:40  test/p21_event_banner_mask_test.dart           (新增 17 条)
18:42  lib/ui/room/widgets/room_notice_overlay.dart   (拆两层 + AnimatedSwitcher)
18:47  test/qa_244_event_mask_test.dart               (本次新增 22 条)
18:49  lib/ui/room/room_ui_local.dart                 (队列改造)
18:49  lib/ui/room/widgets/room_event_banner.dart     (全屏 6 层遮罩)
```

新测试文件里 **0 处 `skip:`、0 处 `findsWidgets`**（无降级）。

---

## 6. 未改动面核验

| 项 | 实测 |
|---|---|
| `lib/domain/**` 0 改动 | 最新 mtime `2026-11-21 15:21`（本批 18:00 之后 0 个文件），**早于本批**。`skills.dart` / `occupations.dart` 未触碰 |
| `lib/ui/room/critical_event_tracker.dart` 0 改动 | mtime `2026-11-21 15:25`，sha256 `93bebe390ceffe0dbc1761df02e4595173957ab5f6b94c12334a5fcf02c597b9`（与我开工时逐字一致） |
| 协议 0 改动 | 无新增消息类型 / intent；`lib/domain` 0 改动即协议 0 改动；watcher 只读 `session.state` |
| `pubspec.lock` | sha256 `6484c4bf5bc696dec8661cab037aab161313d326d0352f8567df2d01694f560f`（跑完全部 flutter 命令后复测）<br>`url: "https://pub.dev"` = **82** 处<br>`flutter-io.cn` = **0** 处 |
| 锚点三数 | `table.length == 25`、`kRoomPolicy.length == 62`、`noAnchor.length + table.length == 62` —— 断言原文未改，测试通过 |
| 版本四处 | `pubspec.yaml:19 = 2.44.0+114`；`app_version.dart:15 = '2.44.0'`、`:18 = 114`；`local.properties` `flutter.versionName=2.44.0` / `flutter.versionCode=114` |
| `lib`+`test` NUL 扫描 | 扫描 **422** 个 `.dart`，含 NUL 字节文件 **0** |
| 旧实现是否真删 | `kBannerMax =` 在 `lib/`+`test/` 已无声明（仅注释提及）；`maxWidth: 520` / `maxHeightRatio` / `ClipRRect` / 整卡 `IgnorePointer` 在 `room_event_banner.dart` 只剩注释文字，代码 0 处 |
| 新 API 存在性 | `activeBanner` / `pendingBannerCount` / `dismissActiveBanner({int? id})` 均在 `room_ui_local.dart:330/333/375` |

---

## 7. 遗留风险（真机仍可能踩到）

1. **320dp 极窄屏的最长标题会被省略号截断（实测）**
   探针实测（`test/_probe_narrow_title_test.dart` 跑完即删）：
   `newSymptomTitle` 的最长形态「沈砚清 获得 1 项新的疯狂症状」在
   **320dp 宽**下 `didExceedMaxLines == true`（2 行 62dp 已满，尾字「症状」被省略）；
   **360dp 起 `didExceedMaxLines == false`**（360/375/400/412/860 全部不截断），
   且各档位 `takeException() == null`（无 overflow 异常）。
   → 影响面仅 320dp 宽的老机/小屏；省略号是 `TextOverflow.ellipsis` 的**既定策略**
   （不是溢出崩溃），但与「让玩家看清发生了什么」的意图有轻微落差。
   若要更稳，可把标题 `maxLines` 提到 3，或在 320dp 档降 title 字号（本次未做）。

2. **连发 10 条总时长 ≈ 24 秒**
   9×2.2s + 4s ≈ 23.8s。数据层一条不丢（已测），但玩家要连点 10 次或等 24 秒。
   KP 一次 SAN Check 打 10 人的概率低，但**真发生时观感偏久**。

3. **遮罩存在期间全屏吃点击（含淡出 220ms）**
   这是需求要求的行为 + 主理人拍板的「防连点误触不可逆按钮」。代价是
   连发 5 条时房间累计约 11 秒不可操作。这是口径取舍，不是缺陷，但值得产品侧知晓。

4. **文字压到图案亮部**
   金色 26px 标题落在 0.70 alpha 深色底衬上（`textBackdrop = 0xB30A0C10`）
   + 上下 scrim（中间 26%–74% 完全不压）。当前 5 张图的构图中心都偏暗，实测无问题；
   **将来若换图且新图正中偏亮**，标题对比度会下降 —— 底衬是最后一道保险，
   换图时应一起复核。

5. **氛围层 `BoxFit.cover` 在超宽屏会放大裁切**
   它不承载构图（构图由主图层 contain 完整承载），裁的是模糊暗部边缘，
   与「图片显示不全」不冲突；但若未来把有信息量的图放进这一层，会被裁。

6. **`room_event_banner_watcher.dart` / `room_game_page.dart` 无法逐字节证明「仅注释」**
   本仓库**不是 git 仓库**（`fatal: not a git repository`），也没有这两份文件的
   基线副本，因此我只能用**行为**兜底：端到端用例（真实 `combat.start` /
   `combat.end` → 遮罩底图）证明 watcher 的判据接线仍然正确。
   如需字节级证据，只能由工程师提供其改动前的 sha。

---

## 8. 附：证据文件

```
test/qa_244_event_mask_test.dart                       本次新增（22 条，sha256 bbbb4db8…4ce4）
build/_qa244_files.txt                                 189 个测试文件清单
build/_qa244_b{1..12}.txt                              12 批分批清单
build/_qa244_loop.sh                                   分批串行 + 缓存轮换脚本
build/_qa244_batch_{1..12}.log                         各批完整日志
build/_qa244_summary.tsv                               批次汇总
build/_qa244_mut/{m1..m5}.log                          5 条反向证伪日志
build/_qa244_mut/*.bak                                 改坏前备份（sha 与工程师自报一致）
```
