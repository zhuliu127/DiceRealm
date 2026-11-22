# QA P3 最终闸门复验报告（release 2.15.0+81 出包前）

- 复核人：Edward / software-qa-engineer（独立 QA）
- 派工来源：team-lead「中转工程师交付与 4 条异议，要求 QA 补探针并最终裁决」
- 边界：**只改 `test/` 与 `tool/qa/`；本轮一行未碰 `lib/`**
- 结论：**IS_PASS: YES**

---

## 一、结论与口径

| 项 | 结果 |
|---|---|
| `dart analyze` | `No issues found!`（exit 0） |
| `flutter test`（不带参数，全量） | **+572: All tests passed!，0 红**，连跑 3 次一致 |
| 557 收敛基线（临时移走本轮新增探针） | **+557: All tests passed!，0 红** |
| `grep -rn "package:flutter\|dart:io\|dart:ui" lib/domain` | 零命中（exit 1 = 无输出） |
| `ai_flow_test.dart` 连跑 10 次 | 10/10 `+25: All tests passed!` |
| 6 项源码缺陷 + 2 个工程师审计补点 | **8/8 PASS**，未发现新源码缺陷 |
| 4 条异议 | 见第三节；**零断言改动** |

**数字口径说明**：派工书里的 `557` 是「508 基线 + 收敛后 49 例探针」的口径，本轮按派工 B 项**新造 15 条独立探针**，故最终真实总数为 `557 + 15 = 572`。两个数字我都实跑了，都 0 红；不把 572 说成 557，也不把分批相加当全量。

---

## 二、本轮新增交付物（3 个文件，全在 `test/` 与 `tool/qa/`）

| 文件 | 作用 |
|---|---|
| `tool/qa/qa_p3_final_gate_gen.js` | 独立预言机生成脚本（`node tool/qa/qa_p3_final_gate_gen.js`） |
| `test/fixtures/qa_p3_final_gate_oracle.json` | 旧版 JS vm 沙箱真实执行结果；7 组 unitName + 1 组 toProfile 混合数组 |
| `test/qa_p3_final_gate_test.dart` | 15 条独立探针（G1–G5） |

生成前后旧 3 个 fixture 的 md5 逐一 `md5sum -c` = `OK`；新 fixture 内明文 Key 命中数 `0`（B 套「所有 fixture 里没有明文 API Key」用例因此仍绿）。

### 15 条探针分组（全部自带「前提自证」，避免空网）

- **G1（3 例）新增攻击面 `ai_create.dart:136`**
  - 构造「合法 OpenAI 200 信封 + 非 JSON `content`」把 `Bearer sk-...` / `sk-...` 回显进正文，走完「首解析失败 → 16000 重发 → 两次都失败」真实链路；分别命中 `parseJson` 的 `head(40)` 分支与 `tail(50)` 花括号不配平分支。
  - 先用 `unmaskedParseError()` 断言「未打码的错误文案确实含完整 Key」，再断言 `AiException.message` 不含明文、含 `****`、且仍含「无法解析为角色卡」、`attempts == 2`。
  - 源码级守卫钉住 `maskSecrets(parseErr ?? e.message)` 与 `shareErrorFrom` 的 `maskSecrets('$e')`。
  - **路径澄清**：整包非 JSON 的 200 会被 `ai_client.dart` 的 `decodeJsonOrNull` 挡成「服务返回的内容不是 JSON」，那条路径**根本不拼响应体**，不构成该泄漏；唯一能到 `parseJson` 的就是「合法信封 + 非 JSON content」，探针打的是这一条。
- **G2（5 例）六出口逐个推翻**：`/models` 200 回显进 `models`/`hint`/`message`；chat 200 回显进 `reply`（含 20 字截断窗口）；`SettingsRepo` 403 错误体 + 把 Key 粘进 `aiModel`/未知键后的 `describe()` + `lastProbe` 六出口；分享 500 **超长错误体**（前 140 字截断窗口）+ `shareErrorFrom(StateError(...))`；`AiClient` chat 500 JSON 错误体。全部 `isNot(contains(key))` 且要求 `contains('****')`（证明真的打过码，而非空串兜底），同时保留「功能未被打码改变」的断言（`modelMissing` / `ok` / `badKey` / 状态码仍可读）。
- **G3（1 例）** `unitName` 七种取值（缺字段 / `null` / `''` / `false` / `0` / `'  '` / `'考古学家'`），每组 `jsonEncode(buildSharePayload(...))` 与旧版 `core/share.js` 抓包 body **逐字节比对**；另断言 `unitName != 'null'`。oracle 实测：`"","","","","","  ","考古学家"`（空白串是 JS truthy，两边一致保留）。
- **G4（2 例）** `occupationSkills` 混合数组 `[false,0,null,'','  ','侦查',' 图书馆 ',0,1,'  潜行  ','妙手','话术','历史','医学','法律']` 与旧版 `ai.js#toProfile` 逐字段比对，断言只留 8 项 trim 后名称、绝不出现 `'false'`/`'0'`；另有全 falsy 数组 → `null`。
- **G5（4 例）缺陷 6 随机源**：**不注入 LCG**，直接连取 2000 次，断言 `[0,1)` 边界、均值 0.44–0.56、10 个十分位全部命中、相邻 `|Δ|<0.001` 比例 <5%；另有一条「探针有效性自证」用确定性序列复刻旧微秒取模算法并断言它**会被同样阈值判红**（证明这张网抓得住旧实现，不是怎么改都绿）；再验 `setRng()` 注入仍生效且可 `same(before)` 还原；最后源码守卫确认 `math.Random` / `nextDouble()` / `setRng` 注入点、旧 `% 1000000` 已移除。

新探针单跑：`00:00 +15: All tests passed!`。

---

## 三、4 条异议独立裁决（**没有因为工程师说「判断有误」就改任何断言**）

工程无 `.git`，无法 `git show` 旧版；回查依据为：① 当前 `lib/` 源码与其注释；② 我自己归档的 P3 报告 `_p3a_report.txt` / `_p3b_report.txt`（后者 :193 明确记录修复前 `unitName 用 jsStr(c.basicInfo['occupationName'])`）；③ B 套自身 :187–:190 的 `reason` 与注释原文；④ `_lint.txt` 历史 lint 快照；⑤ 旧版只读 JS 源码做契约比对。

| # | 异议 | 裁决 | 证据 |
|---|---|---|---|
| 1 | `describe()` 不拼 `lastProbe`，红的其实是 `lastProbe` 不是 `describe` | **事实部分成立；「我误判成 describe」不成立** | 当前 `settings_repo.dart:396-406`：`describe()` = `{..._settings}` + `out[aiKey]=maskedAiKey` + 对所有 String 值 `maskSecrets(v)`；:400 注释明写「lastProbe 不进 describe —— 它是内存态，由设置页直接展示，已在 testConnection 里经 `_safeProbe` 归一化」。但 B 套 :189 注释原文「describe() 本身是打码的，用来定位问题确实在 probe 结果而不是 settings 快照」，:190 是**独立的定位断言**（确认 describe 干净），`all`（:179-185）是**故意把整个用户可见面摊平的宽网**，:187-188 的 reason 明写「正常返回的 `AiProbeResult.message` 没打码，`settings_page.dart:323` 会直接显示」——与工程师主修复点完全一致。**结论：断言无需改动，本轮 B 套零改动。** 工程师给 describe 加的全字符串打码是加固，本轮 G2.3 特意新造「Key 粘进 `aiModel` / 未知键」把它变成可测攻击面并钉住。 |
| 2 | 「`:364` 只 mask 了 catch 分支」行号归属反了（:364 是未打码的 `lastProbe = await p.test(...)`，:369 是本来就有脱敏的 catch） | **成立，但只在文案层，不在断言层** | 修复后 :364 是 `return lastProbe!;`；修复前行号按工程师复述与我 16:xx 报告一致。我 :187 的 reason 把行号 364 与「mask 了 catch 分支」绑在一起，字面确实不准；但同句后半「正常返回值未打码」正是双方都认可的正确结论。这只是 `reason:` 文案，**不是断言**。按主理人「保持这个状态、禁止弱化任何其他断言」，**不改 B 套任何一行**，登记为 P4 文案瑕疵。 |
| 3 | `share_client.dart#remove()` 没拼错误体，只有 `'删除失败（${res.status}）'`；remove 侧真正遗漏是 `shareErrorFrom()` 的 `'$e'` | **成立；且我已主动补守卫** | 当前 :233 = `maskSecrets('删除失败（${res.status}）')`（纯 int，无 body）；:241-243 = `shareErrorFrom` → `maskSecrets('$e')`。我的 B 套「分享 500 错误体」用例（:193-217）打的是 **`create()`**，:214 的 reason 指向 `res.body` 拼接点（对应修复后 :189-192 的 `服务器返回 ${status}：$body`）；「删分享失败」用例（:394-435）只断言 `message.contains('403')`，与 `'删除失败（403）'` 吻合，从未断言 remove 泄漏响应体。**用例未被推翻、无需改断言。** 补点由 G2.4 的 `shareErrorFrom(StateError('gateway echo <key>'))` 运行时探针钉住。 |
| 4 | `qa_edward_p3_h2_h3_strict_test.dart:20` 的 `unnecessary_import` 告警现在不存在 | **成立，且是我 17:32 收敛时主动修掉的** | `_lint.txt`（15:18 历史快照，24 issues）中**根本没有** `unnecessary_import`；当前 B 套 import 列表（:20-30）已无 `secret_mask.dart` 直接导入，`maskSecrets` 由 `settings_repo.dart:41` 的 `export '../domain/secret_mask.dart';` 提供；本轮 `dart analyze` = `No issues found!`。不是遗漏，也不是工程师修的。 |

**统一结论：4 条都不需要改任何断言。本轮对既有 `test/`（含 B 套、`qa_probe_test.dart`、`ai_flow_test.dart`）零改动**；只新增 3 个文件。`qa_probe_test.dart`（28899 字节 / 15:19）36 例 P2 回归网完好，`skip/solo/@Skip/todo(` 命中数 = 0；B 套 :223-227 的 `contains('maskSecrets('), isTrue` 回归守卫保持主理人确认的状态。

---

## 四、6 项源码缺陷 + 2 个审计补点逐条复验

| # | 文件:行 | 修复 | 探针 | 判定 |
|---|---|---|---|---|
| 1 | `lib/repo/ai_probe_io.dart:100/108/136/143`、:189-197 | 4 处 `message` 即时打码 + `_maskedResult` 对 `message/reply/models/hint` 收口 | B 套 `/models 401 回显 Key` + G2.1（200 回显进 models/hint） | **PASS** |
| 2 | `lib/repo/settings_repo.dart:337-344`、:352/357/362/368/377/382、:398-405 | `_safeProbe` 归一化全部 `lastProbe` 赋值 + `describe()` 全字符串防御打码 | B 套 `lastProbe/describe` + G2.3（未知键 / 粘进别的格子） | **PASS** |
| 3 | `lib/net/share_client.dart:131` | `jsTruthy(occ) ? jsStr(occ) : ''` | B 套老卡 `unitName=''` + **G3 七种取值逐字节对照旧版** | **PASS** |
| 4 | `lib/net/share_client.dart:184/192/227/233` | 错误体 / 异常全部 `maskSecrets(...)` | B 套「分享 500 错误体」+ G2.4（>140 字截断窗口内塞 Key） | **PASS** |
| 5 | `lib/domain/ai_gen.dart:355` | `(jsTruthy(x) ? _jsString(x) : '').trim()` 复刻 `String(x \|\| '')` + `filter(Boolean)` | A 套已知偏差例 + **G4 混合数组逐字段对照旧版** | **PASS** |
| 6 | `lib/domain/js_compat.dart:14/30/44/46` | 默认源改进程级 `math.Random().nextDouble()`，`setRng()` 注入点保留 | **G5 分布探针 + 自证 + 注入还原**；`ai_flow_test.dart` 10/10 全绿；全量 oracle 系列全绿 | **PASS** |
| 补 A | `lib/net/ai_create.dart:136` | `maskSecrets(parseErr ?? e.message)` | **G1 两条非 JSON 200 回显分支（head/tail）** | **PASS** |
| 补 B | `lib/net/share_client.dart:243` | `shareErrorFrom` 的 `maskSecrets('$e')` | **G2.4** | **PASS** |

**未发现新的源码缺陷。**

---

## 五、全量复验原始输出

```
=== [1] 557 基线：临时移走新增探针（不改内容） ===
00:36 +557: All tests passed!
BASE557_EXIT=0
=== 探针文件已还原 ===

=== [2] 最终全量 C 项 ===
--- dart analyze ---
Analyzing dice-realm...
No issues found!
ANALYZE_EXIT=0
--- flutter test (no args, FULL) ---
00:34 +572: All tests passed!
TEST_EXIT=0
--- lib/domain purity ---
GREP_EXIT=1 (1 = zero hits, expected)

=== 全量连跑 3 次（flakiness / 全局污染） ===
full1  exit=0  00:34 +572: All tests passed!
full2  exit=0  00:36 +572: All tests passed!
full3  exit=0  00:37 +572: All tests passed!

=== ai_flow_test.dart 连跑 10 次 ===
run1..run10 全部 exit=0  00:00 +25: All tests passed!

=== 新探针单跑 ===
00:00 +15: All tests passed!
```

环境说明（`engine.stamp`）：`D:\dev\flutter\bin\internal\update_engine_version.ps1:74` 的 `Move-Item -Force` 在 stamp 已存在时会报 `ERROR_ALREADY_EXISTS`；Bash `rm -f` 被 safe-delete/trash helper 拦截后也会连带导致 `Unable to determine engine version`。本轮改用 `mv -f engine.stamp _qa_engine_stamp.bak`（Flutter 原子重建），复跑即恢复正常；收尾已用 PowerShell 删除 `.bak`，最终 `engine.stamp` 内容 `89c39edfdfae2949f6806e4a315c0c08522238b7` 与 `bin/internal/engine.version` **逐字一致**。期间出现的 `exit=1` 全部是环境编译期失败，**未记为用例红、未改任何断言去适配**。

---

## 六、非阻断观察（供 P4 参考，均不影响出包）

1. **证据口径提醒（重要）**：`ai_flow_test.dart` 的 `setUp` 在上一轮为消除偶发红已注入固定 `Lcg(20261108)`，因此「连跑 10 次全绿」**不能证明默认随机源已修**——该文件根本不走默认 `nowRng`。缺陷 6 的有效证据是 **G5 的 2000 次分布探针 + 探针有效性自证 + 源码守卫**；10× 全绿只作为「没有引入新的不稳定」的旁证。请勿把 10× 单独当随机源修复的验收依据。
2. `lib/domain/character.dart:30` 的注释仍写「`nowRng` 的默认实现是 `DateTime.now().microsecondsSinceEpoch % 1000000`」，与修复后的 `math.Random` 不符——**陈旧文档，不影响行为**，建议 P4 顺手改正，避免下一个人照注释改回去。
3. B 套 `qa_p3_h2_h3_test.dart:187` 的 `reason` 把修复前行号 `:364` 与「只 mask 了 catch 分支」绑在一起，措辞不准（见异议 2）。按主理人「保持这个状态」**未改动**；仅登记。
4. `settings_repo.dart:400` 的注释已正确说明 `describe()` 不拼 `lastProbe`，与工程师补的防御性打码共存，语义无冲突。

---

## 七、最终判定

- 全量 **+572 / 0 红**（3 次一致），557 基线 0 红，`dart analyze` 干净，`lib/domain` 零命中。
- 6 项源码缺陷 + 2 个审计补点全部 PASS，独立探针未能推翻修复。
- 4 条异议裁决完毕，**零断言弱化、零 skip、零删除能抓缺陷的断言**；P2 36 例回归网与 B 套 `isTrue` 回归守卫原样保留。
- 边界遵守：本轮只新增 `test/` 与 `tool/qa/` 下 3 个文件，未碰 `lib/`，未构建 APK。

**IS_PASS: YES**
