// ============================================================
// ai_probe_io.dart — 「测试连接」的网络实现（仅连通性自检）
//
// ⚠️ 这里**只做设置页的连通性自检**，不是 AI 车卡的网络层。
//    AI 车卡主流程（提示词、结果落地、截断重试）属于 P3-B，届时另写；
//    本文件刻意只暴露 `AiProbe` 这一个契约，避免以后两套客户端互相打架。
//
// 用 `dart:io` 的 HttpClient 而不是引第三方包：
//   一条 GET + 一条 POST，不需要连接池 / 拦截器，少一个依赖就少一处版本风险。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/ai_probe.dart';
import '../domain/secret_mask.dart';

class _Resp {
  _Resp({required this.status, required this.body, this.error});
  final int status;
  final String body;
  final String? error;

  bool get ok => error == null && status >= 200 && status < 300;
}

/// 走 `dart:io` 的两步探测
class HttpAiProbe implements AiProbe {
  HttpAiProbe({
    this.modelsTimeout = const Duration(seconds: 20),
    this.chatTimeout = const Duration(seconds: 60),
  });

  final Duration modelsTimeout;
  final Duration chatTimeout;

  @override
  Future<AiProbeResult> test({
    required String base,
    required String model,
    required String key,
  }) async =>
      _maskedResult(await _testRaw(base: base, model: model, key: key));

  /// 未脱敏的原始探测。所有「服务端回显」都只经这里构造，
  /// 对外统一由 [test] 包一层 [_maskedResult]，避免漏掉某个分支。
  Future<AiProbeResult> _testRaw({
    required String base,
    required String model,
    required String key,
  }) async {
    if (base.trim().isEmpty) return AiProbeResult.notConfigured('接口地址');
    if (model.trim().isEmpty) return AiProbeResult.notConfigured('模型名称');
    if (key.trim().isEmpty) return AiProbeResult.notConfigured('API Key');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${key.trim()}',
    };

    /* ---------- 第 1 步：GET /models —— 只验「地址 + Key」 ---------- */
    final r1 = await _request(
      modelsEndpoint(base),
      'GET',
      headers,
      '',
      modelsTimeout,
    );

    if (r1.ok && !looksLikeNoModels(r1.body)) {
      final names = modelNames(jsonSafeDecode(r1.body));
      final inList = names.isEmpty || names.contains(model.trim());
      if (!inList) {
        final sample = names.take(6).join('、');
        return AiProbeResult(
          kind: AiProbeKind.modelMissing,
          via: 'models',
          models: names,
          modelInList: false,
          message: '地址与 Key 都通，但可用模型里没有「${model.trim()}」',
          hint: names.isEmpty
              ? ''
              : '该地址报告了 ${names.length} 个模型，例如：$sample。填一个列表里的名字，或换成别的服务地址。',
        );
      }
      return AiProbeResult(
        kind: AiProbeKind.ok,
        via: 'models',
        models: names,
        message: names.isNotEmpty ? '已连接 · 该地址可用模型 ${names.length} 个' : '已连接',
      );
    }

    // 地址本身不通（DNS / TLS / 超时）：不必再打一次 chat
    if (r1.error != null) {
      return AiProbeResult(
        kind: AiProbeKind.unreachable,
        via: 'models',
        message: maskSecrets(explainRequestError(r1.error!)),
      );
    }
    // 401 / 403：Key 的问题，也不用回退（chat 一定同样失败）
    if (r1.status == 401 || r1.status == 403) {
      return AiProbeResult(
        kind: AiProbeKind.badKey,
        via: 'models',
        message: maskSecrets(explainHttpError(r1.status, r1.body)),
      );
    }

    /* ---------- 第 2 步：回退到一次极小的 chat 探测 ---------- */
    final payload = jsonEncode(<String, Object?>{
      'model': model.trim(),
      // 512 不能再小：推理型模型要把额度分给思考链，太小会拿到空正文
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': '回复「好」一个字即可'},
      ],
      'temperature': 0,
      'max_tokens': 512,
      'stream': false,
    });

    final r2 = await _request(
      endpointOf(base),
      'POST',
      headers,
      payload,
      chatTimeout,
    );

    if (r2.error != null) {
      return AiProbeResult(
        kind: AiProbeKind.unreachable,
        via: 'chat',
        message: maskSecrets(explainRequestError(r2.error!)),
      );
    }
    if (!r2.ok) {
      return AiProbeResult(
        kind: kindOfStatus(r2.status),
        via: 'chat',
        message: maskSecrets(explainHttpError(r2.status, r2.body)),
      );
    }

    final data = jsonSafeDecode(r2.body);
    if (data == null) {
      return const AiProbeResult(
        kind: AiProbeKind.badResponse,
        via: 'chat',
        message: '服务返回的内容不是 JSON，请确认接口地址填的是 OpenAI 兼容接口',
      );
    }

    final text = pickText(data).trim();
    if (text.isNotEmpty) {
      return AiProbeResult(
        kind: AiProbeKind.ok,
        via: 'chat',
        reply: text.length > 20 ? text.substring(0, 20) : text,
        message: '已连接 · 模型回了话',
      );
    }

    /* HTTP 成功 + 合法 JSON，但正文为空：多见于推理型模型额度不足。
       这说明地址 / Key / 模型都是通的，不该报「连接失败」。 */
    final fr = finishReason(data);
    final rlen = reasoningLen(data);
    return AiProbeResult(
      kind: AiProbeKind.ok,
      via: 'chat',
      message: '已连接（模型未输出文字${fr.isEmpty ? '' : '，结束原因 $fr'}）',
      hint:
          '这不影响 AI 车卡 —— 车卡请求的额度更大。'
          '${rlen > 0 ? '这次模型把 $rlen 个字用在了思考过程上，说明它可能是推理型模型。' : ''}'
          '若想让测试连接也显示回复文字，可换一个非推理型模型名。',
    );
  }

  /// 归一化脱敏：探测结果里凡是可能来自服务端的文本（message / reply /
  /// models / hint）一律过 [maskSecrets]。
  ///
  /// 双保险：4 条错误分支在构造 message 时已即时打码（照抄
  /// `ai_client.dart` 的 `maskSecrets(explainXxx(...))` 口径）；这里再对整个
  /// 结果收口，覆盖 /models 列表、模型回复片段、结束原因 hint，以及**以后
  /// 新增分支** —— 任何 AiProbeResult 只要从这个类出去就不可能带明文 Key。
  /// [maskSecrets] 对已打码文本是幂等的，重复调用无副作用。
  AiProbeResult _maskedResult(AiProbeResult r) => AiProbeResult(
        kind: r.kind,
        message: maskSecrets(r.message),
        via: r.via,
        reply: maskSecrets(r.reply),
        models: r.models.map((m) => maskSecrets(m)).toList(),
        modelInList: r.modelInList,
        hint: maskSecrets(r.hint),
      );

  Future<_Resp> _request(
    String url,
    String method,
    Map<String, String> headers,
    String body,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(url);
      final req = await client.openUrl(method, uri).timeout(timeout);
      headers.forEach((k, v) => req.headers.set(k, v));
      if (body.isNotEmpty) {
        final bytes = utf8.encode(body);
        req.headers.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      return _Resp(status: res.statusCode, body: text);
    } on TimeoutException {
      return _Resp(status: 0, body: '', error: 'TimeoutException: 连接超时');
    } on SocketException catch (e) {
      return _Resp(status: 0, body: '', error: e.message);
    } on HandshakeException catch (e) {
      return _Resp(
        status: 0,
        body: '',
        error: 'SSL handshake failed: ${e.message}',
      );
    } catch (e) {
      return _Resp(status: 0, body: '', error: '$e');
    } finally {
      client.close(force: true);
    }
  }
}
