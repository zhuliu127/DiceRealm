// ============================================================
// http_io.dart — 极小的 HTTP 客户端壳（dart:io，无第三方依赖）
//
// 为什么自己写而不引 `package:http`：
//   · 我们要的能力只有三样：发一个带 JSON 的请求、读完整响应体、按需取消；
//   · 取消（[closeClient] / 传入的 client 被 close）在 AI 生成那种「用户随时
//     想中断」的场景里是必需项，裸 HttpClient 支持得最直接；
//   · 少一个依赖就少一处与 Flutter 版本的耦合。
//
// ⚠️ 本文件**不做任何语义翻译**：状态码、错误文本原样返回，由调用方决定
//    「401 是 Key 无效」还是「404 是路径不对」。翻译逻辑在
//    `domain/ai_probe.dart`（纯函数，可单测）。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 一次请求的结果。`error != null` 表示根本没拿到 HTTP 响应（网络层失败）。
class HttpResult {
  const HttpResult({required this.status, required this.body, this.error});

  const HttpResult.fail(String message)
    : status = 0,
      body = '',
      error = message;

  final int status;
  final String body;
  final String? error;

  bool get ok => error == null && status >= 200 && status < 300;
}

/// 发一次请求。
///
/// [client] 由调用方持有（要取消就 close 它）；不传则内部临时建一个并在结束时关闭。
Future<HttpResult> httpRequest(
  String url,
  String method,
  Map<String, String> headers,
  String body, {
  required Duration timeout,
  HttpClient? client,
}) async {
  final own = client == null;
  final c = client ?? HttpClient();
  c.connectionTimeout = timeout;
  try {
    final req = await c
        .openUrl(method.toUpperCase(), Uri.parse(url))
        .timeout(timeout);
    headers.forEach((k, v) => req.headers.set(k, v));
    if (body.isNotEmpty) {
      final bytes = utf8.encode(body);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    return HttpResult(status: res.statusCode, body: text);
  } on TimeoutException {
    return HttpResult.fail('TimeoutException: 连接超时（${timeout.inSeconds} 秒）');
  } on SocketException catch (e) {
    return HttpResult.fail(e.message.isEmpty ? '$e' : e.message);
  } on HandshakeException catch (e) {
    return HttpResult.fail('SSL handshake failed: ${e.message}');
  } catch (e) {
    return HttpResult.fail('$e');
  } finally {
    if (own) c.close(force: true);
  }
}

/// JSON 解析失败返回 null（不抛）
Object? decodeJsonOrNull(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}
