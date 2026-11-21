// ============================================================
// ai_client.dart — OpenAI 兼容的 chat 客户端
// 对应 `core/ai.js#AIClient`
//
// ⚠️ 与旧版的**唯一**结构性差异：旧版有两套通道（Android 原生桥 + fetch），
//    因为网页版的源是 `appassets.androidplatform.net`，直连外部接口会撞
//    CORS 预检与混合内容策略。Flutter 是原生运行时，`dart:io` 直接发请求，
//    既没有 CORS 也没有同源限制 —— 所以这里**只保留一条通道**，
//    旧版的 `hasBridge()` / `__cocHttpDone` 一律不移植。
//
// 参数照抄旧版（都是有原因的，别"优化"）：
//   · maxTokens 默认 6000 —— 推理型模型会把 max_tokens 的一大半花在
//     reasoning_content 上。实测 LongCat-2.5-Preview 生成一张卡：
//     1800 → 思考链 1425（79%）、finish_reason=length、正文只剩 750 字符、
//     JSON 在半个字符串处被截断；6000 → 思考 202、正文 1082、stop、完整。
//   · 超时 180000ms —— 推理模型慢，90 秒会误杀。
//   · 被截断（finish_reason=length）时用 16000 重试一次（见 ai_create.dart）。
//
// 🔒 `aiKey` 只在 Authorization 头里出现一次；所有对外可见的错误消息都过
//    `maskSecrets`（HTTP 库偶尔会把请求头拼进异常文本）。
// ============================================================

import 'dart:convert';
import 'dart:io';

import '../domain/ai_probe.dart';
import '../domain/secret_mask.dart';
import 'http_io.dart';

/// 一次请求的元信息（用来判断要不要加额度重试）
class AiChatMeta {
  const AiChatMeta({
    this.finishReason = '',
    this.completionTokens = 0,
    this.reasoningTokens = 0,
    this.truncated = false,
  });

  final String finishReason;
  final int completionTokens;
  final int reasoningTokens;

  /// `finish_reason == 'length'` —— 正文被硬截断，解析再宽容也救不回来
  final bool truncated;
}

/// 一次对话的结果
class AiChatResult {
  const AiChatResult({required this.text, required this.meta});
  final String text;
  final AiChatMeta meta;
}

/// 调用失败的分类（界面据此决定「去改设置」还是「换个模型」）
enum AiErrorKind {
  /// 地址 / 模型 / Key 有空格子
  notConfigured,

  /// 网络层：域名、TLS、超时、被拒绝
  unreachable,

  /// 401 / 403
  badKey,

  /// 404：路径或模型名不对
  notFound,

  /// 429
  rateLimited,

  /// 5xx
  serverError,

  /// 其它 4xx
  badRequest,

  /// 返回不是 JSON，或结构里没有 choices
  badResponse,

  /// 模型没输出正文（多为推理模型额度被思考链吃光）
  emptyContent,

  /// 用户主动取消
  cancelled,
}

/// 带人话消息的异常。**message 已经过脱敏**，可以直接显示、可以打日志。
class AiException implements Exception {
  AiException(this.kind, this.message);

  final AiErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// 从设置里现读的 AI 配置
class AiConfig {
  const AiConfig({required this.base, required this.model, required this.key});

  final String base;
  final String model;
  final String key;

  bool get configured => base.isNotEmpty && model.isNotEmpty && key.isNotEmpty;

  /// 缺哪一项（给「还没填写 XXX」用）
  String get missing {
    if (base.isEmpty) return '接口地址';
    if (model.isEmpty) return '模型名称';
    if (key.isEmpty) return 'API Key';
    return '';
  }
}

const int aiDefaultMaxTokens = 6000;
const int aiRetryMaxTokens = 16000;
const Duration aiDefaultTimeout = Duration(milliseconds: 180000);

/// OpenAI 兼容 chat 客户端
class AiClient {
  /// [configProvider] 每次调用**现读**设置 —— 玩家改完 Key 立刻生效，
  /// 不需要重建客户端。
  AiClient({
    required AiConfig Function() configProvider,
    HttpClient? httpClient,
  }) : _config = configProvider,
       _injected = httpClient;

  final AiConfig Function() _config;
  final HttpClient? _injected;

  HttpClient? _active;
  bool _cancelled = false;

  bool get busy => _active != null;

  /// 中断当前请求（AI 生成页的「取消」按钮）。
  ///
  /// 只关连接、不抛异常：进行中的 `chat()` 会拿到一个 SocketException，
  /// 由 [_request] 翻译成 [AiErrorKind.cancelled]。
  void cancel() {
    _cancelled = true;
    final c = _active;
    _active = null;
    try {
      c?.close(force: true);
    } catch (_) {
      // 关连接失败无所谓（可能已经自己结束了）
    }
  }

  /// 发一次对话请求，返回模型回复的纯文本。
  ///
  /// @param messages `[{role, content}]`
  /// @param temperature 旧版默认 0.9（车卡要发散一点）
  /// @param maxTokens 旧版默认 6000，见文件头注释
  /// @param onMeta 拿到 finish_reason / token 用量时的回调（重试判据）
  Future<AiChatResult> chat(
    List<Map<String, String>> messages, {
    double temperature = 0.9,
    int maxTokens = aiDefaultMaxTokens,
    Duration timeout = aiDefaultTimeout,
    void Function(AiChatMeta meta)? onMeta,
  }) async {
    final c = _config();
    if (!c.configured) {
      throw AiException(
        AiErrorKind.notConfigured,
        '还没填写${c.missing}，请先到「设置」里配置',
      );
    }

    final body = <String, Object?>{
      'model': c.model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
    };

    _cancelled = false;
    final res = await _request(
      endpointOf(c.base),
      'POST',
      <String, String>{
        'Content-Type': 'application/json',
        // 🔒 这是 Key 唯一出现的地方
        'Authorization': 'Bearer ${c.key}',
      },
      jsonEncodeSafe(body),
      timeout,
    );

    if (_cancelled) {
      throw AiException(AiErrorKind.cancelled, '已取消');
    }
    if (res.error != null) {
      throw AiException(
        AiErrorKind.unreachable,
        maskSecrets(explainRequestError(res.error!)),
      );
    }
    if (!res.ok) {
      // 🔒 服务端的错误体可能把我们自己的请求头回显回来（有的网关会），
      //    所以这里也要过一遍脱敏 —— 不能让 Key 顺着错误提示跑到界面上。
      throw AiException(
        _kindOf(res.status),
        maskSecrets(explainHttpError(res.status, res.body)),
      );
    }

    final data = decodeJsonOrNull(res.body);
    if (data is! Map) {
      throw AiException(
        AiErrorKind.badResponse,
        '服务返回的内容不是 JSON，请确认接口地址填的是 OpenAI 兼容接口',
      );
    }

    final choices = (data['choices'] as List?) ?? const <Object?>[];
    final ch = choices.isEmpty
        ? null
        : (choices.first is Map ? choices.first as Map : null);
    final message = (ch?['message'] as Map?) ?? const <String, Object?>{};
    final text = ((message['content'] ?? ch?['text']) ?? '').toString();

    final usage = (data['usage'] as Map?) ?? const <String, Object?>{};
    final det =
        (usage['completion_tokens_details'] as Map?) ??
        const <String, Object?>{};
    final meta = AiChatMeta(
      finishReason: '${ch?['finish_reason'] ?? ''}',
      completionTokens: _intOf(usage['completion_tokens']),
      reasoningTokens: _intOf(det['reasoning_tokens']),
      truncated: '${ch?['finish_reason'] ?? ''}' == 'length',
    );
    onMeta?.call(meta);

    if (text.trim().isEmpty) {
      /* 正文为空但有思考链 → 几乎必然是额度被思考链吃光了。
         这是唯一值得单独说一句的空回复原因，别混进「模型没有返回任何内容」。 */
      final reasoning = '${message['reasoning_content'] ?? ''}';
      if (reasoning.isNotEmpty) {
        throw AiException(
          AiErrorKind.emptyContent,
          '模型只输出了思考过程、没有输出正文。这是额度不够导致的'
          '（推理型模型会把 max_tokens 的一大截用在思考上），请稍后重试。',
        );
      }
      throw AiException(AiErrorKind.emptyContent, '模型没有返回任何内容');
    }
    return AiChatResult(text: text, meta: meta);
  }

  /// 发请求。[client] 每次新建并记到 [_active]，取消时直接 close 它。
  Future<HttpResult> _request(
    String url,
    String method,
    Map<String, String> headers,
    String body,
    Duration timeout,
  ) async {
    final injected = _injected;
    if (injected != null) {
      _active = injected;
      try {
        return await httpRequest(
          url,
          method,
          headers,
          body,
          timeout: timeout,
          client: injected,
        );
      } finally {
        if (identical(_active, injected)) _active = null;
      }
    }
    final client = HttpClient();
    _active = client;
    try {
      return await httpRequest(
        url,
        method,
        headers,
        body,
        timeout: timeout,
        client: client,
      );
    } finally {
      if (identical(_active, client)) {
        _active = null;
        // ⚠️ 必须关：不关的话空闲连接会一直挂着（15s idleTimeout），
        //    测试里表现为「用例莫名挂到超时」，真机上表现为连接数只涨不降。
        client.close(force: true);
      }
    }
  }

  static AiErrorKind _kindOf(int status) {
    if (status == 401 || status == 403) return AiErrorKind.badKey;
    if (status == 404) return AiErrorKind.notFound;
    if (status == 429) return AiErrorKind.rateLimited;
    if (status == 400 || status == 422) return AiErrorKind.badRequest;
    if (status >= 500) return AiErrorKind.serverError;
    if (status == 0) return AiErrorKind.unreachable;
    return AiErrorKind.badResponse;
  }

  static int _intOf(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}

/// `jsonEncode` 的小包装：失败时抛 [AiException] 而不是裸 FormatException
String jsonEncodeSafe(Object? v) {
  try {
    return jsonEncode(v);
  } catch (e) {
    throw AiException(AiErrorKind.badRequest, '请求体无法序列化：${maskSecrets('$e')}');
  }
}
