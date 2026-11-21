// ============================================================
// ai_probe.dart — 「测试连接」的语义层（纯 Dart，无网络）
// 对应 `core/ai.js#test()` / `explainError()` / `explainRequestError()`
//
// 分两层是刻意的：
//   · 本文件只定义**协议**：端点怎么拼、HTTP 错误怎么翻成人话、
//     结果怎么归成三类（地址不通 / Key 无效 / 模型不在列表里）；
//   · 真正发请求的实现放在 `repo/ai_probe_io.dart`。
//   这样 UI 与测试可以注入假实现，一行网络代码都不用跑。
//
// 旧版的两步策略（照抄，别"优化"）：
//   第 1 步 `GET {base}/models` —— 只验「地址 + Key」：
//     · 秒回、不烧生成额度；
//     · 成功且响应不像「not found / not supported」→ 连上了，
//       顺便核对模型名在不在列表里；
//   第 2 步 只有第 1 步失败才回退到一次极小的 `chat` 探测 ——
//     有些服务不实现 /models（返回 404 或 HTML 404 页）。
//
// ⚠️ 三种失败的区分是产品要求：
//     地址不通（DNS / TLS / 超时 / 404 路径错）
//     Key 无效（401 / 403）
//     模型不在列表里（/models 通了，但列表里没有这个模型名）
//   混成一句"连接失败"会让用户不知道该改哪一格。
// ============================================================

import 'dart:convert';

import 'js_compat.dart';

/// 探测结果分类
enum AiProbeKind {
  /// 连上了（第 1 步或第 2 步）
  ok,

  /// 地址不通：DNS / TLS / 超时 / 明文被禁 / 路径不对
  unreachable,

  /// Key 无效：401 / 403
  badKey,

  /// 地址与 Key 都通，但 `/models` 里没有填的这个模型
  modelMissing,

  /// 配置不全（地址 / 模型 / Key 有空格子）
  notConfigured,

  /// 通了但回应看不懂（非 JSON、结构不对、其它 4xx/5xx）
  badResponse,
}

/// 一次探测的结果
class AiProbeResult {
  const AiProbeResult({
    required this.kind,
    required this.message,
    this.via = '',
    this.reply = '',
    this.models = const <String>[],
    this.modelInList = true,
    this.hint = '',
  });

  /// 未配置时的结果（三个空格子分别提示）
  factory AiProbeResult.notConfigured(String what) => AiProbeResult(
    kind: AiProbeKind.notConfigured,
    message: '还没填写$what，请先在本页配置',
  );

  final AiProbeKind kind;

  /// 给人看的一句话
  final String message;

  /// `'models'` | `'chat'` | `''`
  final String via;

  /// 对话探测拿到的回复片段（截断 20 字）
  final String reply;

  /// `/models` 返回的模型名列表（没有就是空）
  final List<String> models;

  /// 模型名是否在列表里（拿不到列表时视为「无法判断」，记 true）
  final bool modelInList;

  /// 补充说明（例如推理型模型把额度用在思考链上）
  final String hint;

  bool get ok => kind == AiProbeKind.ok;

  /// 界面上的短标签
  String get kindLabel {
    switch (kind) {
      case AiProbeKind.ok:
        return '连接正常';
      case AiProbeKind.unreachable:
        return '地址不通';
      case AiProbeKind.badKey:
        return 'Key 无效';
      case AiProbeKind.modelMissing:
        return '模型不在列表里';
      case AiProbeKind.notConfigured:
        return '未配置';
      case AiProbeKind.badResponse:
        return '响应异常';
    }
  }
}

/// 探测接口（UI 只依赖这个，不依赖具体网络实现）
abstract class AiProbe {
  /// 两步探测。[base] 是用户填的接口地址（可带 /chat/completions），
  /// [model] 是模型名，[key] 是 API Key（**不落任何日志**）。
  Future<AiProbeResult> test({
    required String base,
    required String model,
    required String key,
  });
}

/* ---------- 端点拼接（ai.js#endpointOf / modelsEndpoint） ---------- */

/// 去掉所有空白与结尾斜杠
String normalizeBase(String base) =>
    base.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'/+$'), '');

/// chat 端点；用户已经填了 `/chat/completions` 就原样用
String endpointOf(String base) {
  final b = normalizeBase(base);
  if (RegExp(r'/chat/completions$', caseSensitive: false).hasMatch(b)) return b;
  return '$b/chat/completions';
}

/// `/models` 端点；用户填了 `/chat/completions` 就先截掉再拼
String modelsEndpoint(String base) {
  var b = normalizeBase(base);
  b = b.replaceAll(RegExp(r'/chat/completions$', caseSensitive: false), '');
  return '$b/models';
}

/* ---------- 错误翻译 ---------- */

/// HTTP 状态码 → 人话（`ai.js#explainError` 的逐条搬运）
String explainHttpError(int status, String body) {
  var detail = '';
  try {
    final j = asMap(jsonSafeDecode(body));
    final err = j['error'];
    if (err is Map) {
      final m = err['message'];
      final t = err['type'];
      detail = jsTruthy(m) ? jsStr(m) : jsStr(t);
    }
    if (detail.isEmpty) detail = jsTruthy(j['message']) ? jsStr(j['message']) : '';
  } catch (_) {
    // 不是 JSON，忽略
  }

  final String head;
  if (status == 400) {
    head = '请求被拒绝（400），可能是模型名称不对，或该模型不支持这种调用';
  } else if (status == 401) {
    head = 'API Key 不正确或已失效（401）';
  } else if (status == 402) {
    head = '账户余额不足（402）';
  } else if (status == 403) {
    head = '没有访问权限（403），请确认 Key 的可用范围';
  } else if (status == 404) {
    head = '接口地址或模型名称不存在（404）';
  } else if (status == 422) {
    head = '参数不被接受（422）';
  } else if (status == 429) {
    head = '请求过于频繁或额度已用尽（429），稍后再试';
  } else if (status >= 500) {
    head = '模型服务端出错（$status），稍后再试';
  } else {
    head = '请求失败（${status == 0 ? '无响应' : status}）';
  }
  return detail.isNotEmpty ? '$head：$detail' : head;
}

/// 网络层异常 → 人话（`ai.js#explainRequestError` 的关键分支）
String explainRequestError(String message) {
  final s = message;
  if (RegExp(r'Cannot set request property after connection is made')
      .hasMatch(s)) {
    return '这是应用自身的缺陷（请求头设置时机不对），与你的 Key、地址无关。';
  }
  if (RegExp(
    r'Cleartext.*not permitted|NetworkSecurityPolicy',
    caseSensitive: false,
  ).hasMatch(s)) {
    return '接口地址是 http://，但系统不允许明文流量。请改用 https:// 地址。';
  }
  if (RegExp(
    r'UnknownHost|unable to resolve host|Failed host lookup',
    caseSensitive: false,
  ).hasMatch(s)) {
    return '域名解析失败，请检查接口地址是否写错、是否有网络连接。';
  }
  if (RegExp(
    r'SSL|handshake|certificate|CERTIFICATE',
    caseSensitive: false,
  ).hasMatch(s)) {
    return 'HTTPS 握手失败，可能是证书问题或该服务需要自签证书。';
  }
  if (RegExp(
    r'timed? ?out|TimeoutException|Connection closed',
    caseSensitive: false,
  ).hasMatch(s)) {
    return '连接超时，请检查网络或稍后再试。';
  }
  if (RegExp(
    r'Connection refused|SocketException',
    caseSensitive: false,
  ).hasMatch(s)) {
    return '无法连接到该地址，请确认地址与端口是否正确。';
  }
  return '请求失败：$s';
}

/// 按状态码把失败归类（产品要求的三分法）
AiProbeKind kindOfStatus(int status) {
  if (status == 401 || status == 403) return AiProbeKind.badKey;
  if (status == 404) return AiProbeKind.unreachable;
  return AiProbeKind.badResponse;
}

/* ---------- 响应解析 ---------- */

/// JSON 解析失败时返回 null（不抛）
Object? jsonSafeDecode(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

/// 取第一个 choice 的正文（`ai.js#pickText`）
String pickText(Object? data) {
  final d = asMap(data);
  final choices = asList(d['choices']);
  if (choices.isEmpty) return '';
  final ch = asMap(choices.first);
  final m = asMap(ch['message']);
  final c = jsTruthy(m['content']) ? jsStr(m['content']) : jsStr(ch['text']);
  return c;
}

/// 单独取思考链长度，用于解释「为什么没有文字」
int reasoningLen(Object? data) {
  final d = asMap(data);
  final choices = asList(d['choices']);
  if (choices.isEmpty) return 0;
  final m = asMap(asMap(choices.first)['message']);
  return jsStr(m['reasoning_content']).length;
}

/// 结束原因，用于给用户解释空回复
String finishReason(Object? data) {
  final d = asMap(data);
  final choices = asList(d['choices']);
  if (choices.isEmpty) return '';
  return jsStr(asMap(choices.first)['finish_reason']);
}

/// 从 `/models` 响应里挖模型名
List<String> modelNames(Object? data) {
  final d = asMap(data);
  final out = <String>[];
  for (final m in asList(d['data'])) {
    final id = asMap(m)['id'];
    if (jsTruthy(id)) out.add(jsStr(id));
  }
  return out;
}

/// 响应体像不像「这个服务没有 /models」
bool looksLikeNoModels(String body) {
  final head = body.length > 200 ? body.substring(0, 200) : body;
  return RegExp(
    r'not found|not supported|404',
    caseSensitive: false,
  ).hasMatch(head);
}
