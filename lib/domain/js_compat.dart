// ============================================================
// js_compat.dart — 原 Web 版规则层所依赖的 JS 语义替身
//
// 为什么需要这一层：
//   老代码里到处是 `parseInt(v, 10) || 0`、`Math.floor`、`Math.round`、
//   `String(v)`、`!v` 这类隐式转换，而且**属性字段既可能是数字也可能是字符串**
//   （老存档里就是混着的）。Dart 没有这套隐式语义，如果随手写 `int.parse`
//   或 `as int`，遇到 '' / null / '15' 就会抛异常，与老行为不符。
//
//   所以把 JS 的转换规则**逐条实现**，其余模块只通过这里取值。
//   这是「逐行忠实翻译」的一部分，不是工具类工程化。
// ============================================================

import 'dart:math' as math;

/// 可注入的随机源（对应 `Math.random`：返回 [0,1)）。
typedef JsRng = double Function();

/// 可注入的时钟（对应 `Date.now()`），毫秒。
typedef JsClock = int Function();

/// 全局随机源。原码直接调 `Math.random`；Dart 侧抽成可替换变量，
/// 只是为了测试能把「同一个序列」同时喂给 JS 预言机与 Dart 实现。
JsRng nowRng = _mathRandom;

/// 全局时钟。原码用 `Date.now()` 写 `at` / `resetAt` / `id`，
/// 测试里需要固定它才能逐字段比对。
JsClock nowClock = _systemNow;

void setRng(JsRng rng) => nowRng = rng;
void setClock(JsClock clock) => nowClock = clock;

int nowMillis() => nowClock();

/// 默认随机源：与浏览器 `Math.random` 同为伪随机 [0,1)。
///
/// ⚠️ 不能用「微秒取模」：一次生成里连调 8 次，微秒计数器每次只前进个位
///    数，八项属性会拿到几乎相同的值（落在低位时集体偏低），真机上表现为
///    偶发「一键随机生成」成片低属性。改用进程级 [math.Random]，每次
///    nextDouble 独立取样，不再与调用时刻相关。
///    不用 `Random.secure()`：这里只需统计均匀、不需要密码学质量，
///    secure 每次取样要走平台 CSPRNG，掷骰 / 随机车卡的高频调用下更慢；
///    真正的 id 生成另有 `character.dart` 的 `Random.secure()` 双路径。
final math.Random _systemRng = math.Random();

double _mathRandom() => _systemRng.nextDouble();

int _systemNow() => DateTime.now().millisecondsSinceEpoch;

/// JS `parseInt(v, 10)`：解析失败返回 null（对应 JS 的 NaN）。
///
/// 规则（与 JS 一致，别用 int.tryParse 代替）：
///   · 数字 → 取整数部分（15.9 → 15）
///   · 字符串 → 跳过前导空白，读一个可选正负号 + 连续十进制数字，遇到其它字符就停
///     （"15abc" → 15，"'  -7'" → -7，"" → NaN，'0x10' → 0）
///   · null / bool / 其它 → NaN
int? jsParseInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) {
    if (v.isNaN || v.isInfinite) return null;
    return v.truncate();
  }
  if (v is bool) return null;
  if (v is String) {
    final m = _intPrefix.firstMatch(v);
    if (m == null) return null;
    return int.tryParse(m.group(0)!.trim());
  }
  return null;
}

final RegExp _intPrefix = RegExp(r'^[ \t\r\n\f\v\u00a0\u3000]*[+-]?[0-9]+');

/// 原码里无处不在的 `num(v)`（rules-coc7.js 的定义：parseInt 失败就当 0）
int jsNum(Object? v) => jsParseInt(v) ?? 0;

/// JS `String(v)`
String jsStr(Object? v) {
  if (v == null) return 'null';
  if (v is String) return v;
  if (v is bool) return v ? 'true' : 'false';
  if (v is double) {
    if (v.isNaN) return 'NaN';
    if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }
  return v.toString();
}

/// JS 真值判定（''、0、NaN、null、undefined、false 为假）
bool jsTruthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true;
}

/// JS `Math.round`：.5 一律向 +∞ 取整（Dart 的 round() 是远离零，负数上不同）
int jsRound(num x) {
  if (x.isNaN || x.isInfinite) return 0;
  return (x + 0.5).floor();
}

/// JS `Math.max` / `Math.min` over a list（空列表在 JS 里是 ∓Infinity，这里退化为 0）
int jsMax(Iterable<int> xs) =>
    xs.isEmpty ? 0 : xs.reduce((a, b) => a > b ? a : b);
int jsMin(Iterable<int> xs) =>
    xs.isEmpty ? 0 : xs.reduce((a, b) => a < b ? a : b);

/// 取出一个 JSON 对象；不是 Map 时返回空 Map（对应 `c.x || {}`）
Map<String, Object?> asMap(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  return <String, Object?>{};
}

/// 取出一个 JSON 数组；不是 List 时返回空列表（对应 `Array.isArray(x) ? x : []`）
List<Object?> asList(Object? v) {
  if (v is List) return v;
  return <Object?>[];
}

/// `Array.isArray`
bool isArray(Object? v) => v is List;
