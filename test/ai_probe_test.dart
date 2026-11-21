// ============================================================
// ai_probe_test.dart — 「测试连接」的语义层（纯函数，不联网）
//
// 对齐 `core/ai.js#test()` / `explainError()` / `pickText` / `modelsEndpoint`。
// 这些函数决定「报错够不够人话」和「三种失败分不分得开」，
// 属于产品要求，所以单独钉一遍。
// ============================================================

import 'package:dice_realm/domain/ai_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('端点拼接', () {
    test('默认补 /chat/completions', () {
      expect(
        endpointOf('https://api.deepseek.com/v1'),
        'https://api.deepseek.com/v1/chat/completions',
      );
    });

    test('已带 /chat/completions 就不重复拼', () {
      expect(
        endpointOf('https://api.deepseek.com/v1/chat/completions'),
        'https://api.deepseek.com/v1/chat/completions',
      );
      expect(
        endpointOf('https://api.deepseek.com/v1/Chat/Completions'),
        'https://api.deepseek.com/v1/Chat/Completions',
      );
    });

    test('空白与结尾斜杠被清掉', () {
      expect(normalizeBase('  https://a.com/v1///  '), 'https://a.com/v1');
      expect(
        endpointOf(' https://a.com/v1/ '),
        'https://a.com/v1/chat/completions',
      );
    });

    test('/models 端点：先截掉 /chat/completions 再拼', () {
      expect(modelsEndpoint('https://a.com/v1'), 'https://a.com/v1/models');
      expect(
        modelsEndpoint('https://a.com/v1/chat/completions'),
        'https://a.com/v1/models',
      );
      expect(modelsEndpoint('https://a.com/v1/'), 'https://a.com/v1/models');
    });
  });

  group('HTTP 错误翻成人话（旧版 explainError 的逐条口径）', () {
    test('常见状态码各有专门说法', () {
      expect(explainHttpError(400, ''), contains('400'));
      expect(explainHttpError(401, ''), contains('API Key 不正确'));
      expect(explainHttpError(402, ''), contains('余额'));
      expect(explainHttpError(403, ''), contains('访问权限'));
      expect(explainHttpError(404, ''), contains('不存在'));
      expect(explainHttpError(422, ''), contains('参数'));
      expect(explainHttpError(429, ''), contains('频繁'));
      expect(explainHttpError(503, ''), contains('服务端出错'));
      expect(explainHttpError(0, ''), contains('无响应'));
    });

    test('响应体里的 error.message 会附在后面', () {
      final msg = explainHttpError(
        401,
        '{"error":{"message":"invalid api key"}}',
      );
      expect(msg, contains('API Key 不正确'));
      expect(msg, contains('invalid api key'));
    });

    test('非 JSON 响应体不抛，只给状态码说法', () {
      expect(explainHttpError(500, '<html>oops</html>'), contains('服务端出错'));
    });
  });

  group('三种失败必须分得开', () {
    test('401 / 403 → Key 无效', () {
      expect(kindOfStatus(401), AiProbeKind.badKey);
      expect(kindOfStatus(403), AiProbeKind.badKey);
    });

    test('404 → 地址不通（路径/域名不对，不是 Key 的问题）', () {
      expect(kindOfStatus(404), AiProbeKind.unreachable);
    });

    test('其它 → 响应异常', () {
      expect(kindOfStatus(500), AiProbeKind.badResponse);
      expect(kindOfStatus(429), AiProbeKind.badResponse);
    });

    test('三种 kind 的界面标签互不相同', () {
      const kinds = <AiProbeKind>[
        AiProbeKind.ok,
        AiProbeKind.unreachable,
        AiProbeKind.badKey,
        AiProbeKind.modelMissing,
        AiProbeKind.notConfigured,
        AiProbeKind.badResponse,
      ];
      final labels = kinds
          .map((k) => AiProbeResult(kind: k, message: '').kindLabel)
          .toSet();
      expect(labels.length, kinds.length);
    });
  });

  group('网络异常翻成人话', () {
    test('域名解析 / 明文 / 证书 / 超时各有说法', () {
      expect(
        explainRequestError('Failed host lookup: api.x.com'),
        contains('域名解析失败'),
      );
      expect(
        explainRequestError('Cleartext HTTP traffic not permitted'),
        contains('明文流量'),
      );
      expect(explainRequestError('SSL handshake failed'), contains('握手失败'));
      expect(explainRequestError('TimeoutException: 连接超时'), contains('超时'));
      expect(explainRequestError('Connection refused'), contains('无法连接'));
    });

    test('认不出的异常也会原样带上（不吞信息）', () {
      expect(
        explainRequestError('weird failure 42'),
        contains('weird failure 42'),
      );
    });
  });

  group('响应解析', () {
    test('pickText：content 优先，其次 text', () {
      expect(
        pickText(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{'content': '好'},
            },
          ],
        }),
        '好',
      );
      expect(
        pickText(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{'text': 'fallback'},
          ],
        }),
        'fallback',
      );
      expect(pickText(null), '');
      expect(pickText(<String, Object?>{'choices': <Object?>[]}), '');
    });

    test('finishReason / reasoningLen', () {
      final data = <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'finish_reason': 'length',
            'message': <String, Object?>{'reasoning_content': '思考了挺久'},
          },
        ],
      };
      expect(finishReason(data), 'length');
      expect(reasoningLen(data), 5);
    });

    test('modelNames：挖出 data[].id', () {
      final data = <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'id': 'deepseek-chat'},
          <String, Object?>{'id': 'deepseek-reasoner'},
          <String, Object?>{'nope': 1},
        ],
      };
      expect(modelNames(data), <String>['deepseek-chat', 'deepseek-reasoner']);
      expect(modelNames(null), isEmpty);
    });

    test('looksLikeNoModels：只认 not found / not supported / 404', () {
      expect(looksLikeNoModels('{"error":"404 page not found"}'), isTrue);
      expect(looksLikeNoModels('<html>Not Found</html>'), isTrue);
      expect(looksLikeNoModels('{"data":[{"id":"x"}]}'), isFalse);
    });
  });
}
