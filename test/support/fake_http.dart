// ============================================================
// test/support/fake_http.dart — 本地假服务（**绝不打真网**）
//
// 起一个 `HttpServer`（绑定 127.0.0.1，端口随机），把收到的请求体记下来，
// 由用例决定怎么回。好处：
//   · 真跑 HTTP 解析 / 超时 / 状态码分支，比 mock 客户端更接近真实；
//   · 完全在本机，不依赖网络（CI 里也能跑，配合 NO_PROXY=127.0.0.1）。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 收到的请求
class FakeRequest {
  FakeRequest({
    required this.path,
    required this.method,
    required this.body,
    required this.headers,
  });
  final String path;
  final String method;
  final String body;
  final Map<String, String> headers;

  Map<String, Object?> get json => body.isEmpty
      ? <String, Object?>{}
      : (jsonDecode(body) as Map<String, Object?>);
}

typedef FakeResponder = Future<void> Function(
  HttpRequest req,
  FakeRequest captured,
);

class FakeServer {
  FakeServer._(this._server);

  static Future<FakeServer> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeServer._(s);
    unawaited(fake._serve());
    return fake;
  }

  final HttpServer _server;

  /// 全部收到的请求（按顺序）
  final List<FakeRequest> requests = <FakeRequest>[];

  /// 由用例设置：怎么回
  FakeResponder? responder;

  int get port => _server.port;

  /// OpenAI 风格的 base（不带 /chat/completions）
  String get base => 'http://127.0.0.1:$port/v1';

  Future<void> _serve() async {
    await for (final req in _server) {
      String body = '';
      try {
        body = await utf8.decoder.bind(req).join();
      } catch (_) {
        body = '';
      }
      final headerMap = <String, String>{};
      req.headers.forEach((name, values) {
        headerMap[name.toLowerCase()] = values.join(',');
      });
      final captured = FakeRequest(
        path: req.uri.path,
        method: req.method,
        body: body,
        headers: headerMap,
      );
      requests.add(captured);
      try {
        final r = responder;
        if (r == null) {
          await json(req, 200, <String, Object?>{'choices': <Object?>[]});
        } else {
          await r(req, captured);
        }
      } catch (_) {
        // 客户端先断开（取消 / 超时）会在这里抛，忽略即可
      }
    }
  }

  /// 回一段 JSON
  static Future<void> json(HttpRequest req, int status, Object? body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  /// 回一段纯文本（模拟「返回不是 JSON」）
  ///
  /// ⚠️ `charset=utf-8` 不能省：HttpResponse 的编码是从 contentType 的 charset
  ///    推出来的，charset 为空时退回 latin1 —— 写中文会抛，
  ///    响应永远不结束，客户端就挂到超时（第一次踩这个坑花了一轮排查）。
  static Future<void> text(
    HttpRequest req,
    int status,
    String body, {
    String type = 'text/html',
  }) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.parse('$type; charset=utf-8')
      ..write(body);
    await req.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

/// 一个「正常的」chat 响应体
Map<String, Object?> chatOk(
  String content, {
  String finishReason = 'stop',
  int reasoning = 0,
}) => <String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{'role': 'assistant', 'content': content},
      'finish_reason': finishReason,
    },
  ],
  'usage': <String, Object?>{
    'completion_tokens': 120,
    'completion_tokens_details': <String, Object?>{
      'reasoning_tokens': reasoning,
    },
  },
};

/// 只有思考链、没有正文的响应体（推理模型额度不够时的典型形状）
Map<String, Object?> chatReasoningOnly(int chars) => <String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{
        'role': 'assistant',
        'content': '',
        'reasoning_content': 'x' * chars,
      },
      'finish_reason': 'length',
    },
  ],
  'usage': <String, Object?>{
    'completion_tokens': 1800,
    'completion_tokens_details': <String, Object?>{'reasoning_tokens': 1425},
  },
};
