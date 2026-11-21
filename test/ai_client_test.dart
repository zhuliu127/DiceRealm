// ============================================================
// ai_client_test.dart — chat 客户端（本地假服务，不打真网）
//
// 覆盖任务书要求的那一串：200 正常 / 200 空正文 / 401 / 429 / 500 /
// 超时 / 非 JSON / 截断（meta.truncated 供上层重试）。
//
// 每个失败样例都要同时断言三件事：
//   ① 分类正确（UI 据此决定「去改设置」还是「换模型」）；
//   ② 文案可读（不是 `Exception: ...` 这种）；
//   ③ **Key 已打码**（消息里不得出现完整 Key）。
// ============================================================

import 'package:dice_realm/domain/secret_mask.dart';
import 'package:dice_realm/net/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http.dart';

const String kKey = 'sk-test-0123456789abcdef';

void main() {
  late FakeServer server;

  setUp(() async {
    server = await FakeServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  AiClient client({String? model, String? base, String? key}) {
    return AiClient(
      configProvider: () => AiConfig(
        base: base ?? server.base,
        model: model ?? 'test-model',
        key: key ?? kKey,
      ),
    );
  }

  List<Map<String, String>> msgs() => <Map<String, String>>[
    <String, String>{'role': 'user', 'content': 'hi'},
  ];

  /// 断言「消息里没有把 Key 打出来」
  void expectNoKey(String message) {
    expect(message, isNot(contains(kKey)), reason: '错误消息里不能出现完整 Key');
    expect(
      message,
      isNot(contains('0123456789abcdef')),
      reason: '错误消息里不能出现 Key 尾巴',
    );
  }

  group('成功路径', () {
    test('200 正常 → 文本 + meta（finish_reason / token 用量）', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, chatOk('{"a":1}'));

      String? metaFinish;
      var metaTruncated = true;
      final r = await client().chat(
        msgs(),
        onMeta: (m) {
          metaFinish = m.finishReason;
          metaTruncated = m.truncated;
        },
      );

      expect(r.text, '{"a":1}');
      expect(metaFinish, 'stop');
      expect(metaTruncated, isFalse);
      expect(r.meta.completionTokens, 120);

      // 请求形状：OpenAI 兼容
      expect(server.requests, hasLength(1));
      final req = server.requests.single;
      expect(req.path, '/v1/chat/completions');
      expect(req.method, 'POST');
      expect(req.headers['authorization'], 'Bearer $kKey');
      expect(req.headers['content-type'], contains('application/json'));
      final body = req.json;
      expect(body['model'], 'test-model');
      expect(body['max_tokens'], aiDefaultMaxTokens); // 6000
      expect(body['stream'], false);
      expect(body['temperature'], 0.9);
      expect((body['messages'] as List), hasLength(1));
    });

    test('用户填的地址已带 /chat/completions 时不重复拼', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, chatOk('ok'));
      final c = client(base: '${server.base}/chat/completions');
      await c.chat(msgs());
      expect(server.requests.single.path, '/v1/chat/completions');
    });

    test('正文为空但有思考链 → 明确说是「额度被思考链吃光」', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, chatReasoningOnly(300));
      await expectLater(
        client().chat(msgs()),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', AiErrorKind.emptyContent)
              .having((e) => e.message, 'message', contains('只输出了思考过程')),
        ),
      );
    });

    test('正文与思考链都空 → 「模型没有返回任何内容」', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, <String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'content': ''},
                'finish_reason': 'stop',
              },
            ],
          });
      await expectLater(
        client().chat(msgs()),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', AiErrorKind.emptyContent)
              .having((e) => e.message, 'message', contains('没有返回任何内容')),
        ),
      );
    });
  });

  group('失败分类（每种都要分类正确 + 文案可读 + Key 打码）', () {
    Future<AiException> catchErr(Future<Object?> f) async {
      try {
        await f;
      } on AiException catch (e) {
        return e;
      }
      fail('应该抛 AiException');
    }

    test('401 → badKey，文案说「API Key 不正确」', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 401, <String, Object?>{
            'error': <String, Object?>{'message': 'invalid api key'},
          });
      final e = await catchErr(client().chat(msgs()));
      expect(e.kind, AiErrorKind.badKey);
      expect(e.message, contains('API Key 不正确'));
      expect(e.message, contains('invalid api key')); // 附上原文
      expectNoKey(e.message);
    });

    test('403 → badKey', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 403, <String, Object?>{});
      final e = await catchErr(client().chat(msgs()));
      expect(e.kind, AiErrorKind.badKey);
      expectNoKey(e.message);
    });

    test('404 → notFound（路径或模型名不对）', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 404, <String, Object?>{});
      final e = await catchErr(client().chat(msgs()));
      expect(e.kind, AiErrorKind.notFound);
      expect(e.message, contains('不存在'));
    });

    test('429 → rateLimited', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 429, <String, Object?>{});
      final e = await catchErr(client().chat(msgs()));
      expect(e.kind, AiErrorKind.rateLimited);
      expect(e.message, contains('频繁'));
    });

    test('500 → serverError', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 500, <String, Object?>{});
      final e = await catchErr(client().chat(msgs()));
      expect(e.kind, AiErrorKind.serverError);
      expect(e.message, contains('服务端出错'));
    });

    test('200 但返回 HTML（不是 JSON）→ badResponse，提示检查地址', () async {
      server.responder = (req, cap) async =>
          FakeServer.text(req, 200, '<html>我是首页，不是接口</html>');
      final e = await catchErr(client().chat(msgs()));
      expect(e.kind, AiErrorKind.badResponse);
      expect(e.message, contains('不是 JSON'));
    });

    test('连不上（端口没人听）→ unreachable，文案是「无法连接」', () async {
      // 先关掉服务，端口就没人听了
      final deadBase = server.base;
      await server.close();
      final e = await catchErr(client(base: deadBase).chat(msgs()));
      expect(e.kind, AiErrorKind.unreachable);
      expect(e.message, isNotEmpty);
      expectNoKey(e.message);
      // 重新起一个，让 tearDown 的 close 不出错
      server = await FakeServer.start();
    });

    test('超时 → unreachable，文案说「超时」', () async {
      server.responder = (req, cap) async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await FakeServer.json(req, 200, chatOk('late'));
      };
      final e = await catchErr(
        client().chat(msgs(), timeout: const Duration(milliseconds: 120)),
      );
      expect(e.kind, AiErrorKind.unreachable);
      expect(e.message, contains('超时'));
    });

    test('被截断（finish_reason=length）→ meta.truncated=true（上层据此重试）', () async {
      server.responder = (req, cap) async => FakeServer.json(
        req,
        200,
        chatOk('{"a":1', finishReason: 'length', reasoning: 900),
      );
      final r = await client().chat(msgs());
      expect(r.meta.truncated, isTrue);
      expect(r.meta.reasoningTokens, 900);
      expect(r.text, '{"a":1');
    });
  });

  group('配置与取消', () {
    test('地址/模型/Key 缺一项 → notConfigured，且不打网络', () async {
      final e = await () async {
        try {
          await client(key: '').chat(msgs());
        } on AiException catch (e) {
          return e;
        }
        fail('应该抛');
      }();
      expect(e.kind, AiErrorKind.notConfigured);
      expect(e.message, contains('API Key'));
      expect(server.requests, isEmpty);
    });

    test('cancel() → cancelled（界面上的「取消」按钮）', () async {
      server.responder = (req, cap) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        await FakeServer.json(req, 200, chatOk('too late'));
      };
      final c = client();
      final f = c.chat(msgs(), timeout: const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      c.cancel();
      await expectLater(
        f,
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.cancelled,
          ),
        ),
      );
    });

    test('cancel 后再次 chat 能正常工作（状态不是一次性的）', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, chatOk('ok'));
      final c = client();
      c.cancel(); // 空转一次
      final r = await c.chat(msgs());
      expect(r.text, 'ok');
    });
  });

  group('Key 不泄漏（硬约束）', () {
    test('所有错误文案都不含完整 Key', () async {
      final statuses = <int>[400, 401, 403, 404, 422, 429, 500, 503];
      for (final st in statuses) {
        server.responder = (req, cap) async =>
            FakeServer.json(req, st, <String, Object?>{
              // 故意把 Key 回显在错误里（某些网关会这么干）
              'error': <String, Object?>{
                'message': 'bad request with key Bearer $kKey',
              },
            });
        try {
          await client().chat(msgs());
          fail('应该抛');
        } on AiException catch (e) {
          expectNoKey(e.message);
        }
      }
    });

    test('maskApiKey 之后只剩头尾', () {
      expect(kKey.contains('****'), isFalse);
      final masked = maskApiKey(kKey);
      expect(masked, startsWith('sk-t'));
      expect(masked, contains('****'));
    });
  });
}
