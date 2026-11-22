# QA P7 · 云分享规则徽标 独立复核 + 单模拟器冒烟报告

- 复核人：严过关（QA 工程师 / Edward）
- 日期：2026-11-10
- 工程根：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/dice-realm`
- 旧版分享服务端：`C:/Users/60965/WorkBuddy/2026-10-08-18-34-17/coc7th-card-app/tools/coc_share_server.py`
- 立场：**证伪优先**。不采信工程师绿灯，全部结论来自本次独立执行的真实输出。
- 路由判定：**NoOne**（本批未发现需回工程师修复的源码缺陷）；另记录 1 条**非本批引入**的 UI 观察项与若干边界，见第七节。
- 测试轮次：Round 1 全绿，未进入 Round 2（无源码 bug、无测试代码 bug 需要修复回路）。

---

## 0. 基线与还原校验（贯穿全文）

所有改动目标文件在**任何变异之前**记录 SHA256，变异后逐一还原并比对，末尾再次全量复核：

| 文件 | 基线 SHA256 |
| --- | --- |
| `lib/net/share_client.dart` | `c1dd3b084e2121479bb194e1e1ba7799586d9be506fb46935231d263f1168ba0` |
| `test/qa_p3_h2_h3_test.dart` | `e641ffce3beedad53f8b584ff9103a2e6eeaf80c1204ddaaf070f90ffd148e12` |
| `test/qa_p3_final_gate_test.dart` | `30d5d0b6083b721bdf01f5c1d905974b238efa931097b9f83d2dd1c998d510af` |
| `test/p7_share_badge_test.dart` | `7285e628de991ac5f723b4410cb66c9e7e708b55a936338e207127ad857bb21f` |
| `test/fixtures/qa_p3_share_oracle.json` | `e391da286eced338e5caf239638f9b273843aacb6d61bfb7b1263735b56eeb36` |
| `test/fixtures/qa_p3_final_gate_oracle.json` | `8088a6fcfc552c766c645021c47827c5198f237817cd667ba9e9eaa9e2aef0d0` |
| `coc_share_server.py` | `3e78f707ac36eee0109fd2263b84f73199f706accbb93ac8936ef6b82586a365` |
| `test_share_render_badge.py` | `c7f7a60bc18aa35929b36a453a2cd4d598aa8bc768a7f36df5cca079c66bd3f0` |
| `pubspec.yaml` | `930c15c779cd92db592c1245b2e686107aabb374b0412029a54fd762e03a79fc` |

**最终复核（全部一致，逐字节还原成功）**：

```
c1dd3b084e2121479bb194e1e1ba7799586d9be506fb46935231d263f1168ba0 *lib/net/share_client.dart
e641ffce3beedad53f8b584ff9103a2e6eeaf80c1204ddaaf070f90ffd148e12 *test/qa_p3_h2_h3_test.dart
30d5d0b6083b721bdf01f5c1d905974b238efa931097b9f83d2dd1c998d510af *test/qa_p3_final_gate_test.dart
7285e628de991ac5f723b4410cb66c9e7e708b55a936338e207127ad857bb21f *test/p7_share_badge_test.dart
e391da286eced338e5caf239638f9b273843aacb6d61bfb7b1263735b56eeb36 *test/fixtures/qa_p3_share_oracle.json
8088a6fcfc552c766c645021c47827c5198f237817cd667ba9e9eaa9e2aef0d0 *test/fixtures/qa_p3_final_gate_oracle.json
930c15c779cd92db592c1245b2e686107aabb374b0412029a54fd762e03a79fc *pubspec.yaml
3e78f707ac36eee0109fd2263b84f73199f706accbb93ac8936ef6b82586a365 *coc_share_server.py
c7f7a60bc18aa35929b36a453a2cd4d598aa8bc768a7f36df5cca079c66bd3f0 *test_share_render_badge.py
```

> ⚠️ 诚实记录一次操作坑：第一次还原用 Python **文本模式**写回，把原本 LF 的文件写成 CRLF，哈希变成
> `3a9dea6f...` / `59d47ff9...`，**不等于基线**。定位为换行符归一化后改用 `cp` + 二进制模式
> (`read_bytes`/`write_bytes`) 还原，最终哈希恢复为基线值。此后所有变异/还原一律走二进制模式，
> 报告里的「还原一致」均以哈希为准，不以「看起来改回去了」为准。
> 另：QA 变异写回更新了 `share_client.dart` / `qa_p3_h2_h3_test.dart` / `qa_p3_final_gate_test.dart`
> 的 mtime（12:27–12:28），但**内容哈希与基线逐字节一致**，未留任何改动。

**基线绿灯（独立跑，各自单独执行）**：

```
flutter test test/qa_p3_h2_h3_test.dart      → 00:00 +15: All tests passed!
flutter test test/qa_p3_final_gate_test.dart → 00:00 +15: All tests passed!
flutter test test/p7_share_badge_test.dart   → 00:00 +10: All tests passed!
```

---

## 一、契约隔离是否被架空（最高优先级）—— 结论：**没有被架空，双向自证伪成立**

### 1.1 正方向：开关置 `false` 时两处 oracle **真红，且差异确实来自规则字段**

临时把 `qa_p3_h2_h3_test.dart:84` 与 `qa_p3_final_gate_test.dart:93` 的 setUp 由
`legacySharePayloadForOracle = true` 改成 `false`，分别单独跑两个文件（退出码均为 1）。真实失败输出：

```
00:00 +8 -1: H3 严格探针：旧版 core/share.js 抓包逐字节对照 完整卡：POST /api/cards 请求体逐字节一致 [E]
  Expected: '{"name":"林晚",...,"unitName":"记者","sharedAt":1700000000000}}'
    Actual: '{"name":"林晚",...,"unitName":"记者","sharedAt":1700000000000,"ruleSystemId":"coc7","ruleShortName":"COC 7th"}}'
     Which: is different.
            Expected: ... 0000000000}}
              Actual: ... 0000000000,"ruleSyst ...
                                    ^
             Differ at offset 1300
  card1：Dart 请求体与旧版逐字节不一致

00:00 +8 -2: H3 严格探针：旧版 core/share.js 抓包逐字节对照 老卡（basicInfo 缺 occupationName）：... [E]
             Differ at offset 1276
  share_client.dart:127 用 jsStr(null)="null"，旧版 (basicInfo||{}).occupationName || '' 给空串
...
00:00 +13 -2: Some tests failed.
Failing tests:
  .../test/qa_p3_h2_h3_test.dart: H3 ... 完整卡：POST /api/cards 请求体逐字节一致
  .../test/qa_p3_h2_h3_test.dart: H3 ... 老卡（basicInfo 缺 occupationName）...
```

```
00:00 +8 -1: G3 unitName 全部 falsy 变体：与旧版 core/share.js 逐字节对照 ... [E]
             Differ at offset 1276
  变体 missing：与旧版请求体逐字节不一致
00:00 +14 -1: Some tests failed.
Failing tests:
  .../test/qa_p3_final_gate_test.dart: G3 unitName 全部 falsy 变体 ...
```

两处 oracle 共 **3 条失败**，全部是 `expect(body, 冻结body)` 的逐字节比对，差异唯一来源就是追加在
`data` 末尾的 `,"ruleSystemId":"coc7","ruleShortName":"COC 7th"`（offset 1300 / 1276），
不是别的原因红。

### 1.2 「不加任何开关」也红

把两个文件的隔离开关脚手架**整体删除**（`late bool savedLegacySharePayloadForOracle` 声明 +
setUp 快照 + setUp 置位 + tearDown 还原，各 4 行），`grep legacySharePayloadForOracle` 只剩文件头注释、
无可执行开关，再跑：

```
EXIT=1
00:00 +22 -3: Some tests failed.
Failing tests:
  qa_p3_final_gate_test.dart: G3 unitName 全部 falsy 变体 ...
  qa_p3_h2_h3_test.dart: H3 ... 完整卡：POST /api/cards 请求体逐字节一致
  qa_p3_h2_h3_test.dart: H3 ... 老卡（basicInfo 缺 occupationName）...
```

同样是 3 条失败，`Expected/Actual` 差异同上。生产默认 `false` 确实会发规则字段，隔离不是摆设。

### 1.3 反方向：开关 `true` 时逐字节相等（独立脚本，不复用工程师断言）

另写临时探针 `test/_qa_p7_oracle_probe_tmp.dart`（**跑完即删，已确认 `ls` 不存在**），直接读冻结
fixture 并调生产 `buildSharePayload`：

```
[QA] switch=true IDENTICAL=true len=1302/1302
[QA] switch=false 差异仅两个规则字段：verified
00:00 +1: All tests passed!
```

断言包含：`expect(isolated, legacyBody)`、`isolated` 不含 `ruleSystemId`；`prodBody != legacyBody`、
`prod` 含两个规则字段；**摘掉两个新字段后 `jsonEncode(stripped) == jsonEncode(legacyData)` 逐字节相等**。

### 1.4 断言 / fixture / 调用链完整性

- `test/fixtures/qa_p3_share_oracle.json` mtime `2026-11-08 17:33:32.855341900 +0800`、
  `qa_p3_final_gate_oracle.json` mtime `2026-11-08 18:34:12.371049400 +0800`，
  哈希与上表基线一致；本批文件最早 mtime 是 `12:03`（`qa_p3_*`），**冻结 fixture 早于本批两天，未被改动**。
- `grep -nE "skip:|skip =|TODO|FIXME|..."` 两文件零命中；H3 组 `expect(` 计数 39、G3 组 4，
  `hasLength(7)` 仍在；`captures[0]['body']` / `captures[2]['body']` / `c['body']` 三处逐字节比对断言原样保留，
  **没有 skip、没有删用例、没有把 expect 改弱**（1.1 的真红输出反证断言仍是严格逐字节）。
- `grep -rn "buildSharePayload|buildSharePayloadLegacy|legacySharePayloadForOracle" lib/` 只有
  **一处定义** `lib/net/share_client.dart:112`、一处开关 `:106`、一处生产调用 `:209`，不存在另写的
  legacy 函数。`ShareClient.create()` 原文：

```dart
Future<ShareCreateResult> create(Character c) async {
  ...
  final body = jsonEncode(buildSharePayload(c));   // :209，就是带开关的同一个函数
  final res = await httpRequest('$b/api/cards', 'POST', ...);
```

**结论：oracle 没有被降级成测死函数，隔离真实有效、双向可证伪。**

---

## 二、新增测试是否非恒绿（变异测试）—— 结论：**全部会真红，不是摆设**

| 变异 | 操作 | 结果 | 还原后 |
| --- | --- | --- | --- |
| MUT-C | `lib/net/share_client.dart:153` 的 `if (!legacySharePayloadForOracle) {` → `if (false) {` | `flutter test test/p7_share_badge_test.dart` **EXIT=1，`+0 -5`，5 条失败** | 哈希 `c1dd3b...`，10/10 全绿 |
| MUT-D1 | `coc_share_server.py` `.tags` 里整段 `<span class="tag rule-tag" ...>{{RULE}}</span>` 删除 | Python unittest **EXIT=1，`Ran 6 tests` / `FAILED (failures=10)`** | 哈希 `3e78f7...`，6/6 OK |
| MUT-D2 | `rule_label = "COC 7th"` 回退改成 `rule_label = None` | Python unittest **EXIT=1，`Ran 6 tests` / `FAILED (failures=7)`** | 哈希 `3e78f7...`，6/6 OK |

MUT-C 真实失败片段（关键：wire 级用例也真红，证明它检的是真实请求体）：

```
00:00 +0 -1: ① 生产默认路径 data 带规则字段 ... [E]
  Expected: 'coc7'
    Actual: <null>
00:00 +0 -2: ② 老卡 / 未知 id / 占位 id 回退 ... [E]
  Expected: 'coc7'
    Actual: <null>
00:00 +0 -3: ③ 真实 wire 级 + ⑦ 脱敏回归 ShareClient.create() 发出的请求体 data 里真有规则字段 [E]
  Expected: 'coc7'
    Actual: <null>
00:00 +0 -4: ③ ... 请求体不含 delToken / API Key / settings [E]
  Expected: contains '"ruleSystemId":"coc7"'
    Actual: '{"name":"林晚",...,"unitName":"记者","sharedAt":1794284927338}}'
     Which: does not contain '"ruleSystemId":"coc7"'
00:00 +0 -5: ④ 隔离自证伪 ... [E]
...
00:00 +5 -5: Some tests failed.
```

MUT-D1 / D2 真实失败片段（Python unittest 的 `assertIn` 失败信息内嵌整页 HTML，此处取摘要行）：

```
===== MUT-D1（徽标被删） =====
  FAIL: test_all_falsy_rule_values_fall_back (...) (value=None) ... (6 个 subTest 全 FAIL)
  AssertionError: '规则 COC 7th' not found in '<!DOCTYPE html>...'
  FAIL: test_explicit_rule_badge
  AssertionError: 'class="tag rule-tag"' not found in '<!DOCTYPE html>...'
  FAIL: test_missing_field_falls_back_without_none
  FAIL: test_other_rule_renders_verbatim
  FAIL: test_xss_is_escaped
  Ran 6 tests in 0.014s
  FAILED (failures=10)

===== MUT-D2（回退改 None） =====
  FAIL: test_all_falsy_rule_values_fall_back (...) (6 个 subTest 全 FAIL)
  AssertionError: '规则 COC 7th' not found in '<!DOCTYPE html>...'
  FAIL: test_missing_field_falls_back_without_none
  Ran 6 tests in 0.007s
  FAILED (failures=7)
```

**结论：三处变异都让新测试真红，`test/p7_share_badge_test.dart` 与 `test_share_render_badge.py` 非恒绿。**

---

## 三、真实 wire 级断言是否成立 + 拆文件裁决 —— 结论：**成立；裁决「可接受，不必拆」**

### 3.1 SDK 源码层面的机制核实（不靠工程师口头说明）

`/d/dev/flutter/bin/cache/dart-sdk/lib/_http/overrides.dart`：

```dart
static HttpOverrides? get current {
  return Zone.current[_httpOverridesToken] ?? _global;
}
static R runWithHttpOverrides<R>(R Function() body, HttpOverrides overrides) {
  return dart_async.runZoned<R>(body, zoneValues: {_httpOverridesToken: overrides});
}
HttpClient createHttpClient(SecurityContext? context) {
  return _HttpClient(context);          // 基类默认实现 = 真 client
}
```

`/d/dev/flutter/bin/cache/dart-sdk/lib/_http/http.dart:1349`：`factory HttpClient(...)` 取
`HttpOverrides.current`（不是 `global`）。
`/d/dev/flutter/packages/flutter_test/lib/src/_binding_io.dart:27`：`HttpOverrides.global = _MockHttpOverrides()`；
同文件注释明写 *"If another HttpClient is provided using HttpOverrides.runZoned, that will take precedence
over this provider"*。`runWithHttpOverrides` 是同一 zone 机制。
`testWidgets` 声明时（`widget_tester.dart:163`）调 `ensureInitialized()` → `binding.dart:1289` →
`setupHttpOverrides()`，故**文件里只要注册了 testWidgets，全 isolate 就装上 400 mock**。

### 3.2 独立 wire 探针（含**负控**，跑完即删）

临时 `test/_qa_p7_wire_probe_tmp.dart`（已删除）。用一个空 `testWidgets` 触发 mock 安装，再用普通
`test()` 跑真实 HTTP：

```
[QA] HttpOverrides outside=_MockHttpOverrides inside=_RealHttpOverrides
[QA] RECEIVED method=POST path=/v1/api/cards content-type=application/json ruleSystemId=coc7 ruleShortName=COC 7th bodyLen=950
[QA] NEGATIVE CONTROL: caught=ShareErrorKind.http msg=服务器返回 400： server.requests=0
00:00 +3: All tests passed!
```

负控证明：**不套 `runWithHttpOverrides` 时，裸 `HttpClient()` 拿到 400，`ShareClient.create()` 抛
`ShareErrorKind.http`，且 `server.requests=0` —— 一条真实请求都没到 FakeServer**。
因此正式用例绝不可能「400 假响应下恰好通过」：若 override 失效，`expect(res.id, 'sh_badge')` 根本到不了。
MUT-C 时 wire 用例真红（见 2.1）也是同一结论的旁证。

### 3.3 裁决

**可接受，不要求拆成两份文件。** 理由：① 机制由 Dart SDK 自身保证且 SDK 注释背书；② 正式文件里
真实 HTTP 用例是普通 `test()`（真实 async zone），`testWidgets` 只用于 ⑥ SharePanel 三例，职责分离清楚；
③ 负控证明 mock 场景必然失败而非静默通过；④ 全量 `flutter test` 默认并发与 `--concurrency=1`（工程师报，
本次亦跑默认并发全绿）都不串味。

**两条非缺陷的改进建议 / 维护性提示（不要求本批修改）**：
1. `p7_share_badge_test.dart` ③ 组目前断言了 `res.id`、`server.requests` 长度、`body` 解码后的规则字段，
   但**未显式断言 `server.requests.single.method` / `.path`**（本次独立探针已补验：`POST /v1/api/cards`、
   `content-type=application/json`）。建议后续顺手补两行断言，可读性更强；当前缺失不构成漏测
   （method/path 另由 `qa_p3_h2_h3_test.dart` H3 与 `share_client_test.dart` 覆盖）。
2. **真实 HTTP 用例必须保持普通 `test()`**。我第一版探针误把它放进 `testWidgets`，因 FakeAsync 真 I/O
   不推进而挂起、被命令超时 SIGTERM 杀掉 —— 这是**我探针的写法问题，不是产品问题**，但说明该约束是硬的。
   建议文件头注释补一句「真 HTTP 用例不得改写成 testWidgets」。

> 全程未改任何产品代码；新增的两个临时探针文件均已删除，`ls test/_qa_p7*` 确认无残留。

---

## 四、端到端 HTTP（补工程师明确未做的一环）—— 结论：**三次真实响应全部符合预期**

### 4.1 隔离环境（`run_in_background: true` 起服务，收尾停服删库）

```
source /tmp/qa_p7/e2e_env.sh
COC_SHARE_HOST=127.0.0.1
COC_SHARE_PORT=2589
COC_SHARE_DB=C:/Users/60965/AppData/Roaming/WorkDaddy/client-tmp/workbuddy-cn/qa_p7/e2e/cards.db
COC_SHARE_PUBLIC_BASE=http://127.0.0.1:2589
COC_SHARE_RATE_PER_IP=100
COC_SHARE_RATE_GLOBAL=100
COC_SHARE_MAX_CARDS=1000
```

- 启动探活：`curl -i http://127.0.0.1:2589/health` →
  `HTTP/1.1 200 OK` / `Server: coc-share/1.0 Python/3.13.14` /
  `{"ok": true, "service": "coc-share", "time": 1794285477}`。
- 服务端启动日志：`STARTUP host=127.0.0.1 port=2589 db=.../e2e/cards.db public=http://127.0.0.1:2589 rate_ip=100`。
- **限流如实记录**：我把 `RATE_PER_IP` / `RATE_GLOBAL` 从默认 6 / 60 调高到 100 / 100（按要求用环境变量），
  实际只发 3 次 POST，本就低于默认 6 次/分；服务端日志无 429，全部 200。**未发生限流，也未谎报通过**。
- `pack()` = `zlib.compress(json.dumps(...))`，不白名单过滤字段，规则字段能完整落库再被 `render_card` 读到。

### 4.2 三次真实响应（原文片段）

**CASE-1 新卡（带 `ruleShortName: "COC 7th"` / `ruleSystemId: "coc7"`）**

```
POST /api/cards -> status=200 content-type=application/json; charset=utf-8
POST response: {"ok": true, "id": "x47whey9zu", "url": "http://127.0.0.1:2589/s/x47whey9zu", "apiUrl": "http://127.0.0.1:2589/api/cards/x47whey9zu", "delToken": "7pzuR_pFabPOqumF_7CdEZY4"}
GET  /s/x47whey9zu -> status=200 content-type=text/html; charset=utf-8 len=5343
HTML .tags 片段: <div class="tags"><span class="tag rule-tag" data-rule-id="coc7">规则 COC 7th</span><span class="tag">—</span><span class="tag">记者</span><span class="tag">—</span><span class="tag">— 岁</span><span class="tag">信用评级 30</span></div>
[ASSERT] OK: rule-tag / data-rule-id=coc7 / 规则 COC 7th
```

原始响应头（`curl -i`）：

```
HTTP/1.1 200 OK
Server: coc-share/1.0 Python/3.13.14
Content-Type: text/html; charset=utf-8
Content-Length: 5747
Access-Control-Allow-Origin: *
X-Robots-Tag: noindex, nofollow
```

**CASE-2 老卡（完全不带规则字段）**

```
POST /api/cards -> status=200
POST response: {"ok": true, "id": "hrnkrp89jy", "url": "http://127.0.0.1:2589/s/hrnkrp89jy", ...}
GET  /s/hrnkrp89jy -> status=200 content-type=text/html; charset=utf-8 len=5343
HTML .tags 片段: <div class="tags"><span class="tag rule-tag" data-rule-id="coc7">规则 COC 7th</span>...
[ASSERT] OK: 回退 COC 7th；无 >None< / >null< / 规则 None / 规则 null / 裸 {{RULE}} / {{RULE_ID}}
```

**CASE-3 XSS（`ruleShortName = "<script>alert(1)</script>"`）**

```
POST /api/cards -> status=200
POST response: {"ok": true, "id": "a6hqcu87k2", "url": "http://127.0.0.1:2589/s/a6hqcu87k2", ...}
GET  /s/a6hqcu87k2 -> status=200 content-type=text/html; charset=utf-8 len=5373
HTML .tags 片段: <div class="tags"><span class="tag rule-tag" data-rule-id="coc7">规则 &lt;script&gt;alert(1)&lt;/script&gt;</span>...
[ASSERT] OK: &lt;script&gt; / &lt;/script&gt; 已转义；无裸 <script>
```

补充核实：

```
=== CSS .tag.rule-tag 是否随页下发 ===
.tag.rule-tag{color:var(--gold);border-color:var(--gold);background:rgba(217,180,74,.10);margin-left:0;font-weight:600}
=== 全页未替换占位符扫描（三个 id） ===
x47whey9zu : 0
hrnkrp89jy : 0
a6hqcu87k2 : 0
=== 服务端 stderr（节选，无 429） ===
[12:38:15] share created id=x47whey9zu name=QA-P7-CASE-1 size=251B ip=127.0.0.1
[12:38:15] "POST /api/cards HTTP/1.1" 200 -
[12:38:15] "GET /s/x47whey9zu HTTP/1.1" 200 -
...（CASE-2 / CASE-3 同样 200）...
```

`url` 与 `COC_SHARE_PUBLIC_BASE` 一致；`delToken` 在 POST 响应里出现但不在 HTML 里（本批未改该链路）。

### 4.3 收尾

`TaskStop` 停后台服务 + `adb` 无关的本机清理：

```
curl -sS --noproxy '*' --max-time 3 http://127.0.0.1:2589/health
→ curl: (7) Failed to connect to 127.0.0.1:2589 after 2031 ms: Could not connect to server
rm -rf /tmp/qa_p7/e2e  →  ls: cannot access '/tmp/qa_p7/e2e': No such file or directory（已删除）
netstat -ano | grep ':2589' → 仅 TIME_WAIT，无 LISTENING
```

> 边界：本次补的是**真实 `POST /api/cards` → `GET /s/<id>` 全链路**与「CSS 规则随页下发」的字符串证据；
> **仍未在真实浏览器里看视觉呈现**（金色 / 排在 .tags 最前 / 响应式），这一项留给清单第 8 条的真机 / 浏览器验收。

---

## 五、全量回归 —— 结论：**全绿，红线零触碰**

统一在 `unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy; export NO_PROXY=127.0.0.1,localhost` 后执行：

| 项 | 实际输出 |
| --- | --- |
| `flutter test`（全量，默认并发） | `FLUTTER_TEST_EXIT=0`，`00:55 +1565: All tests passed!`（基线 1555 + 本批 10） |
| `dart analyze` | `ANALYZE_EXIT=0`，`Analyzing dice-realm...` / `No issues found!` |
| `node tool/qa/qa_p4_gate.js` | `==== 合计 13 条，失败 0 条 ====` / `P4_GATE IS_PASS: YES` |
| `node tool/qa/qa_p5_ui.js` | `==== 合计 14 条，失败 0 条 ====` / `P5_UI_GATE IS_PASS: YES`；含 `[OK] jsStr( 命中 ≤ 14 且只在白名单 6 文件` |
| `python -m unittest -v test_share_render_badge`（在 `coc7th-card-app/tools/`） | `Ran 6 tests in 0.002s` / `OK` |

红线复核：

- **`lib/domain/**` 零改动**：全部 domain 文件最新 mtime 为 `2026-11-10 10:03`（`ai_caps.dart`），
  其次 `09:31 rule_registry.dart`、`09:23 preset_gen.dart`，**均早于本批最早文件 12:03**；
  P4 门禁 `[OK] lib/domain 纯 Dart（零 Flutter/IO/UI）`。
- **K3（`LogRecord.toWireJson()` 不进中继/出站）**：全 `lib/` 只有 `lib/domain/room_types.dart:386` 的
  **方法定义**，`.toWireJson()` 实际调用**零命中**；`lan_server.dart` / `room_frame.dart` /
  `feed_view.dart` 三处仅为「禁止调用」的注释。本批未碰房间日志 / 中继链。
- **K7（无假按钮 / 无假成功文案）**：本批改动文件中 `已导出成功|文件已保存|\.txt|onPressed: null|
  onPressed: () {}` 零命中；唯一的「占位」字样是注释里描述 `dnd5e`/`custom` 占位规则 id，不是假按钮。
  P5 14/14 亦覆盖弹层 / 门禁字面量。
- **`pubspec.yaml` 未加依赖**：mtime `2026-11-08 18:55:07`，哈希未变；依赖仍为
  `flutter(sdk)` / `cupertino_icons` / `path_provider` / `share_plus` / `file_picker`，无新增。
- APK 与 junction（顺带复核，未重复工程师的指纹核验）：`app-release.apk` SHA256
  `9a12391337b0945d24046dc1cc31970fdb8c5e13bcfd60cc3adc4bd2dfb52b84`，60,635,735 字节；
  `build -> /d/dev/dice-build` 仍是 junction，未删、未 `flutter clean`。

---

## 六、单模拟器冒烟（用户授权「你自己用模拟器先测试一遍有没有 bug」）—— 结论：**通过，无 crash / ANR / 白屏**

### 6.1 环境与约束遵守

- **只用** `/d/dev/android-sdk/platform-tools/adb.exe` 与 `/d/dev/android-sdk/emulator/emulator.exe`；
  **全程未调用 `flutter devices`**，未碰 system32 的 adb shim。
- **只开一台 AVD `diceA`**（`emulator -list-avds` 显示 `diceA` / `diceB`，diceB 未启动，遵守 P6 双开内存崩溃教训）。
- `emulator.exe -avd diceA -no-boot-anim -gpu swiftshader_indirect`，`run_in_background: true` 启动；
  在同一 agent turn 内完成全部检查后 `adb emu kill` + `TaskStop` 收尾。
- `adb wait-for-device` + **一次性设备侧等待**（非宿主机 sleep 循环）：
  `adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done; ...'`
  → `BOOT_COMPLETED=1 getprop=1`。
- 设备：`emulator-5554`，`sdk_gphone64_x86_64`，Android 15 / API 35。
- `MSYS_NO_PATHCONV=1`（P6 经验：Git Bash 会把 `/sdcard` 转成本地路径）用于 `uiautomator dump` / `pull`。

**环境坑（如实记录）**：adb daemon 在不同 Bash 调用之间被回收，第一次 `adb install` 报
`adb.exe: device offline` 失败。解法是**每条 adb 命令在同一调用内**先 `adb devices`（唤醒 daemon）再
`adb wait-for-device`，之后所有调用稳定。这不是产品缺陷。

### 6.2 安装 / 启动 / 进程证据

```
=== adb install -r（重试后） ===
Performing Streamed Install
Success
INSTALL_EXIT=0

=== pm list packages ===
package:com.teaegg.dice_realm

=== am start ===
Starting: Intent { cmp=com.teaegg.dice_realm/.MainActivity }

=== pidof（启动后，且贯穿全部流程始终非空） ===
PID=[3136]   PID_NONEMPTY=YES
```

### 6.3 logcat 结论

清空 logcat 后启动 App，`adb logcat -d -v brief` 共 687 行：

```
D/nativeloader( 3136): Load .../base.apk!/lib/x86_64/libflutter.so ...: ok
I/flutter ( 3136): [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).
E/aegg.dice_realm( 3136): Not starting debugger since process cannot load the jdwp agent.
```

- `FATAL EXCEPTION` / `ANR ` / `Force finishing` / `libapp.so` 加载失败 / Flutter 异常 / `SIGSEGV` /
  `Process com.teaegg` 死亡：**最终全量扫描零命中**。
- `E/aegg.dice_realm(3136): Not starting debugger ... jdwp agent` 是 release 包不加载调试代理的常规提示，无害。
- 日志里出现的 `D/AndroidRuntime(...)` 全部来自 `com.android.commands.uiautomator.Launcher`
  （我每次 dump UI 时系统自己起的进程），**不是 App 崩溃**；已逐条核对。
- 其余 `E/*` 为模拟器系统噪声（GMS PhenotypeFlagCommitter 超时、BestClock 无网络时间、
  RoleControllerServiceImpl、NetworkMonitor 连不上 google），与 App 无关。
- 全程 `pidof` 保持 `3136`，无进程退出 / 重启。

### 6.4 主流程 UI dump 关键节点（均非空白帧）

**首页（home）**：

```
骰境TRPG | COC 7th | 克苏鲁的呼唤 第七版 · 车卡器
已保存的角色卡 | 还没有角色卡，点右下角新建 | 英灵殿 | 新建角色卡
→ 中文文案上屏，非白屏。
```

**车卡相关页（手动新建 9 步向导，全程无崩溃）**：

```
1/9 规则系统（克苏鲁的呼唤 第七版 / DND 5E 未开放 / 自定义 未开放）
2/9 基本资料 → 填 QAInvestigator / QAPlayer / 27 → 校验「请填写角色姓名」→ 选职业（230 个，取「会计师」）
3/9 属性分配 → 随机掷骰 → 掷骰生成属性
4/9 资产与信用评级 → 采用建议值 50
5/9 职业技能 → 「任意两项个人或时代特长 还需指定 2 项」→ 勾心理学/追踪 → 一键分配
6/9 战斗装备 → … → 完成
首页出现已保存卡：QAInvestigator | COC 7th | 会计师 · 27 岁 · 男 | HP 12/12 SAN 75/75 MP 15/15
```

向导的必填校验（缺姓名 / 缺职业 / 缺 2 项特长）均按预期拦截，不是卡死。

**卡详情 + 云分享面板（未配置态，正常路径）**：

```
卡详情：QAInvestigator | 概要 规则 COC 7th · 克苏鲁的呼唤 第七版 | 职业 会计师 | 状态 HP/MP/SAN | 属性 9 项
滚到底部：
  ☁ 云分享
  未配置
  云分享需要先指定一个后端服务地址。「设置 → 分享服务地址」里填入你自己的服务地址即可开启。
  不配置也完全不影响使用：角色卡始终保存在本机，可以用「导出角色 JSON」直接发给队友。
  ⚙ 去设置里填写服务地址
点该按钮 → 设置页：AI 车卡 · 接入信息 / 数值上限 / 服务地址 → 分享服务地址「未配置 —— 不会上传任何数据」
→ 未配置态如实展示、可跳转设置、无崩溃、无假成功文案。
```

（截图 `qa_share.png` 目视复核：中文渲染正常、无白屏、无重叠、无崩溃弹窗。）

**房间大厅（招募期）**：

```
房间 SRXM62 已创建 · 局域网已开（http://10.0.2.16:4211）· 同伴可搜到
房间 洋馆惊魂 | 招募中 · connected | 房间号 SRXM62 | 你是 KP：等人到齐、大家准备后点「开始游戏」
按钮：复制邀请 / 离开 / 复制地址 / 复制加入信息 / 局域网自检
成员（0）；开始游戏（灰，「房间里还没有玩家」）；房间管理（仅 KP · 招募期）→ 结束房间 / 结团

游戏期专属关键词扫描（掷骰/投骰/技能检定/战斗/回合/更多工具/导出历史/发送消息/私聊/广播/
座位管理/踢出/骰子/发起检定/日志/聊天/游戏期/进行中/结束回合/行动）：零命中
ASSERT PASS: 招募期未出现游戏期按钮
```

（截图 `qa_lobby.png` 目视复核：中文渲染正常、布局完整、无空白区、无按钮重叠，「开始游戏」因无玩家正确置灰。）

### 6.5 收尾

```
=== adb emu kill ===
OK: killing emulator, bye bye
OK
EMU_KILL_EXIT=0
TaskStop(FcVpxx) → Status: killed（运行 15m 55s）
=== 最终 adb devices ===
List of devices attached（空）
=== 最终 emulator/qemu 进程 ===
(无残留)
```

---

## 七、遗留问题 / 边界 / 建议

1. **本批无源码 bug，路由 NoOne**：六项独立验证全部通过，未触发「送 Engineer」或「QA 自修测试」回路，
   测试轮次只用掉 Round 1。
2. **真实浏览器 CSS 呈现未验**：已证明 `.tag.rule-tag{...}` 随 `GET /s/<id>` 下发、徽标排 `.tags` 最前、
   `data-rule-id` 正确；但「金色 / 圆角 / 窄屏换行 / 暗色主题对比度」需要真实浏览器或真机 WebView 看，
   按约定留给清单第 8 条的真机统一验收。**不要写成已通过**。
3. **真机项一律仍待用户统一验收**：另一台设备/浏览器打开新链接与旧链接、「已生成」面板与
   「更新为当前版本」、系统剪贴板 / 系统分享、多设备同 WiFi 局域网、多播锁、debug 签名侧载等，
   本次只做到「单模拟器 + 本机 HTTP 端到端」。保留「真机测试等全部做完了再测」约定。
4. **非阻断 UI 观察项（非本批引入，建议记技术债，不塞进收尾批次）**：车卡向导的校验错误文案
   **只在下一次点「下一步」时刷新**，输入/状态已经改好时旧提示仍留在屏幕上。实测两例：
   - 填完 `QAInvestigator/QAPlayer/27` 后，`请填写角色姓名` 仍显示，再点一次「下一步」才变成 `请选择职业`；
   - 点「一键分配」后 `技能点` 已是 `职业点 320 / 320 已用完 / 兴趣点 150 / 150 已用完`，
     但底部仍留 `还有 270 点职业技能点未分配`，再点「下一步」正常进入 6/9。
   不影响流程、不崩、不误判（下一步能正常推进），属既存 UX 细节。相关文件
   `lib/ui/create/steps/step_basics.dart` / `step_skills.dart` / `wizard_checks.dart` mtime 均为
   `2026-11-08 15:15`、`create_flow_page.dart` 为 `2026-11-10 09:38`，**全部早于本批 12:03**，
   不是 P7 徽标改动引入的回归。请主理人决定是否另开批次，本批不改产品代码。
5. **测试侧两点小建议（非缺陷，见 3.3）**：③ 组可补 `method/path` 显式断言；真 HTTP 用例须保持普通
   `test()`，勿改成 `testWidgets`（FakeAsync 会挂）。**我未擅自修改任何产品代码或既有测试文件**。
6. **QA 变异写回更新了 3 个文件的 mtime**（`share_client.dart`、`qa_p3_h2_h3_test.dart`、
   `qa_p3_final_gate_test.dart`），内容哈希已逐字节还原到基线；若后续按 mtime 做增量扫描请注意这一点。
7. 本批**未启动第二台模拟器**（遵守 P6 内存教训），因此未做双设备 LAN 联调；该能力的历史证据见
   `_p6_emulator_verify.txt`，真机多设备仍待用户统一验收。

---

## 八、智能路由判定

```
Routing Decision: NoOne
```

- 源码缺陷：无（变异测试证明新测试有效、端到端 HTTP 与单模拟器冒烟均无 crash/ANR/白屏/UI 错乱）。
- 测试代码缺陷：无（未出现需要 QA 自修的错误断言；唯一「挂起」发生在我自己临时探针里，已定位为
  testWidgets/FakeAsync 写法问题并修正，临时文件已删除，不涉及交付物）。
- 全量回归：+1565 全绿 / analyze 零告警 / P4 13/13 / P5 14/14 / Python 6/6。
- 剩余项均为**边界与真机待验**，按约定留给「真机测试等全部做完了再测」，不计为本批失败。
