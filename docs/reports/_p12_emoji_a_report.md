# P12 · Emoji → 矢量图标（A 组报告）

任务：用户原话「对 emoji 都替换掉，不太搭现在的风格」。
范围：`home_page` / `roster_page` / `card_detail_page` / `share_panel` / `settings_page`（+ 本组新建测试）。
一律用 **Material Icons**，不生成图片、不自绘、不改 `widgets.dart` 的组件定义。

---

## 一、逐处替换（14 个字符串 / 12 处）

| # | 位置 | 原 emoji | 换成 | 尺寸 / 颜色 | 为什么 |
|---|------|----------|------|-------------|--------|
| 1 | `home_page.dart` 数据菜单 · 导出全部 | `⬇` | `Icons.file_download_outlined` | 16 / `Palette.textDim` | 菜单项文字色是正文次要色，图标跟随；⬇ 是「下载」的动作图标 |
| 2 | `home_page.dart` 数据菜单 · 导入 | `⬆` | `Icons.file_upload_outlined` | 16 / `Palette.textDim` | 导入 = 上传，与导出成对 |
| 3 | `home_page.dart` 数据菜单 · 设置 | `⚙` | `Icons.settings_outlined` | 16 / `Palette.textDim` | 设置的标准隐喻 |
| 4 | `card_detail_page.dart` 卡菜单 · 导出 | `⬇` | `Icons.file_download_outlined` | 16 / `Palette.textDim` | 与首页菜单同义同图形，保证两处菜单观感一致 |
| 5 | `card_detail_page.dart` 卡菜单 · 删除 | `🗑` | `Icons.delete_outline` | 16 / `Palette.textDim` | 删除的标准隐喻；**不用** danger 红 —— 菜单正文本身是常规色，红色留给二次确认弹窗的 `confirm_delete` |
| 6 | `card_detail_page.dart` 编辑态提示条 | `✎` | `Icons.edit_note` | 14 / `Palette.goldStr` | 行内提示，14dp；颜色跟随提示条文字的金色，不另起一色 |
| 7 | `share_panel.dart` 未配置 · 去设置 | `⚙` | `Icons.settings_outlined` | 16 / 继承按钮前景色 | 按钮内图标交给 `IconTheme`（Material 3 从 `foregroundColor` 派生），天然跟随主题金 |
| 8 | `share_panel.dart` 创建分享 | `☁` | `Icons.cloud_upload_outlined` | 16 / 继承 | 云分享 = 上传到云；上传中(`上传中…`)保留同一颗图标，避免按钮宽度跳动 |
| 9 | `share_panel.dart` 复制链接 | `📋` | `Icons.content_copy` | 16 / 继承 | 剪贴板语义 |
| 10 | `share_panel.dart` 分享 / 打开 | `↗` | `Icons.open_in_new` | 16 / 继承 | 走系统分享面板，视觉上表达「往外部去」 |
| 11 | `share_panel.dart` 更新为当前版本 | `↻` | `Icons.refresh` | 16 / 继承 | 重新上传 = 刷新 |
| 12 | `share_panel.dart` 三处 `SectionCard(title:)` | `☁ 云分享`（3 处） | `云分享`（纯文本） | — | `SectionCard` 的标题只接受 `String`，本批不许改 `widgets.dart`；标题左侧已有全站统一的竖金条，再塞图标会重复装饰。**只去符号不补图标**，已在此说明 |

文案一律「去掉 emoji + 紧随的空格，只留文字」：`'🗑 删除角色'` → `'删除角色'`。

---

## 二、判定为「内容」而保留的符号

| 符号 | 位置 | 判定理由 |
|------|------|----------|
| `☠` | `card_detail_page.dart` 撕卡印章（原 405 行） | 明确保留的美术元素，注释写明「图缺失时作为兜底可见语义标记」；旁边就是 `Art.rippedStamp` 插画 |
| `←` | `card_detail_page.dart` `'← $raw'`（属性被年龄调整过时显示旧值） | 是**运算示意**（50 ← 55），不是图标 |
| `→` | `share_panel` / `settings_page` 文案中的「设置 → 分享服务地址」「填 80 → …」 | 句中的流程/因果连接符，属正文 |
| `✓` / `✕` | `settings_page.dart` 连接测试结果卡 | 规范明确列出的保留项（「✓ 已保存」类）；这里是状态标记而非按钮图标，且测试 `p10_edu_check_test` 对 `✓` 有口径依赖 |
| `①②③④` | `settings_page.dart` 步骤与排错清单 | 有序列表序号，不是装饰符号 |
| `📜` / `🕯` | `roster_page.dart` 两处 `EmptyState(emoji:)` | 该两处**已有 `art:`**，`EmptyState` 里 art 优先、emoji 只是兜底参数；按规范「art 优先，不加 icon」，故源码保留但不渲染（新用例断言 `find.text('📜')` == `findsNothing`） |
| `…` `—` `−` `·` | 各页 | 标点/符号，非 emoji |

---

## 三、测试账目

### 改动的既有用例（`test/card_detail_edit_test.dart`，6 条断言）
只改文案、**强度不变**（全部仍是 `find.text(...)` 精确匹配，未降级为 `findsWidgets`）：

- `find.text('🗑 删除角色')` ×2 → `find.text('删除角色')`
- `find.text('⬇ 导出 JSON')` ×1 → `find.text('导出 JSON')`
- `find.text('⬆ 导入角色 JSON')` ×2 → `find.text('导入角色 JSON')`
- `find.text('⬇ 导出全部角色')` ×1 → `find.text('导出全部角色')`

其余曾经搜到的命中都**不需要动**：`test/create_flow_widget_test.dart` 的 `'☠ 已撕卡'` 来自 `widgets.dart#RippedBadge`（非本组文件）；`⚔ 对抗` 出现在跑团日志**正文**里，属内容。

### 新增 `test/p12_emoji_a_test.dart`（8 组，全绿）
1. 首页数据菜单：三项图标都在 + 文案无 emoji
2. 卡详情「⋯」菜单：导出/删除图标 + 文案
3. 卡详情编辑态提示条：`Icons.edit_note` 存在、文本不再以 `✎` 开头（**不扫整棵树**：编辑表单来自 `card_edit/**`，仍带 emoji，扫了必然误报）
4. 卡详情只读态（含底部云分享区）整页无 emoji
5. 分享面板 · 未配置：⚠️→`settings_outlined`，文案无 emoji
6. 分享面板 · 已配置→已分享：`cloud_upload_outlined` / `content_copy` / `open_in_new` / `refresh` 四颗图标
7. 设置页整页无 emoji
8. 名册空态：无 emoji 文本，`find.text('📜')` findsNothing

负向扫描用的是渲染树里的真实 `Text`（含 `Text.rich` 的 span 拼合），正则 `[\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{1F300}-\u{1FAFF}]`（`unicode: true`，含 ☁ ⚙ ⬇ ⬆ 这类 BMP 区 emoji）。

### 反向自证伪（已执行并恢复）
把 `share_panel.dart` 的 `'复制链接'` 改回 `'📋 复制链接'` → `flutter test test/p12_emoji_a_test.dart` 变红：
`分享面板 · 已分享 仍有 emoji 文本：[📋 复制链接]`（+5 -1）→ 逐字节还原，`md5 = 671eadfb3e2c517811b072225f713642` 与改动前一致。

### 总量
- 基线 2006
- 本组 +8 → 2014
- 与其它组并行后当前全量 **2026**（2023 绿 / 3 红，3 红全部在 `test/p12_emoji_c_test.dart`，是 C 组进行中的用例，与本组无关）
- `flutter analyze`：`No issues found!`

---

## 四、文件与换行符

| 文件 | 改动 | 换行符 |
|------|------|--------|
| `lib/ui/home_page.dart` | 3 处菜单项 | CRLF 保持 |
| `lib/ui/card_detail_page.dart` | 3 处（2 菜单 + 提示条） | CRLF 保持 |
| `lib/ui/share_panel.dart` | 5 处按钮 + 3 处标题 | CRLF 保持（中途被脚本写成 LF，已还原） |
| `lib/ui/roster_page.dart` | 未改（两处空态 art 优先） | CRLF |
| `lib/ui/settings_page.dart` | 未改（无 emoji，仅保留项） | CRLF |
| `test/card_detail_edit_test.dart` | 6 条文案断言 | CRLF 保持 |
| `test/p12_emoji_a_test.dart` | 新建 8 组 | LF |

未触碰：`lib/ui/widgets.dart` 组件定义、`lib/ui/room/**`、`lib/ui/ai_create_page.dart`、`lib/ui/card_edit/**`、`lib/ui/create/steps/**`、`pubspec.yaml`。
