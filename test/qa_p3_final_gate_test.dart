// ============================================================
// QA P3 最终闸门 · 主动推翻 6 项修复的独立探针（第 3 批 / 最终批）
//
// 边界：只改 test/ 与 tool/qa/，一行都不碰 lib/。
// 期望值来自 tool/qa/qa_p3_final_gate_gen.js 在旧版 JS vm 沙箱里的
// 真实执行结果；输入是 QA 自选的更刁样本，不复用工程师 fixture。
//
// 覆盖：
//   G1 工程师审计补点 lib/net/ai_create.dart:136（非 JSON 200 回显 Key）
//      以及 lib/net/share_client.dart#shareErrorFrom 的 '$e' 兜底
//   G2 服务端 500 / 200 回显 Key 的全部用户可见出口：
//      message / reply / models / hint / describe() / lastProbe /
//      ShareException / AiException
//   G3 unitName 七种 falsy 变体，与旧版 core/share.js 请求体逐字节比对
//   G4 toProfile 混合 falsy 数组，与旧版 core/ai.js 逐字段比对
//   G5 默认 nowRng 分布（不注入 LCG）+ setRng 注入点未破
//
// 本文件刻意不含 testWidgets：同一 suite 混入 testWidgets 会触发
// flutter_test 的 HttpOverrides，真实 HttpClient 请求全变 400（假阳性）。
//
// ★ P7 收尾：G3 现在验的是**旧版 wire 契约**（不含 ruleSystemId /
//   ruleShortName）。生产载荷按用户要求带规则标记，属于有意偏离旧版，
//   由 setUp 的 legacySharePayloadForOracle=true 隔离，fixture 与全部
//   expect 一个字未改。生产载荷的规则标记由 test/p7_share_badge_test.dart
//   （含真实 FakeServer wire 级验证）覆盖。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/ai_gen.dart';
import 'package:dice_realm/domain/ai_probe.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/net/ai_client.dart';
import 'package:dice_realm/net/ai_create.dart';
import 'package:dice_realm/net/share_client.dart';
import 'package:dice_realm/repo/ai_probe_io.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http.dart';

const String kKey = 'sk-abcdefghijklmnopqrstuvwxyz123456';

/// 短 Key：用于「reply 截断 20 字」这条路径，保证完整 Key 落进截断窗口。
/// 长度 11（sk- 后 9 位），仍满足 maskSecrets 的 {6,} 匹配下限。
const String kShort = 'sk-qa123456';

/// 把一个对象所有「用户可见文本」摊平，一条断言网住全部出口。
String blob(Object? o) {
  if (o == null) return '';
  final parts = <String>[o.toString()];
  if (o is AiException) parts.add(o.message);
  if (o is ShareException) parts.add(o.message);
  if (o is AiGenException) parts.add(o.message);
  if (o is AiProbeResult) {
    parts.addAll(<String>[
      o.message, o.hint, o.reply, o.kindLabel, o.models.join(','),
    ]);
  }
  return parts.join(' | ');
}

class _CreateOutcome {
  const _CreateOutcome(this.caught, this.attempts);

  final Object? caught;
  final int attempts;
}

void main() {
  // 全局快照/还原：SettingsRepo.load() 会 applyToDomain() 写
  // preset.presetSettings；G5 要拿「未注入的默认 nowRng」，其余用例
  // 也会经 AiCreateService 消耗随机序列。探针不许自己污染后续用例。
  late Map<String, Object?> savedPresetSettings;
  late JsRng savedRng;
  late JsClock savedClock;
  late bool savedUid;
  // ★ P7：G3 逐字节比对的是旧版 wire 契约，冻结 fixture 的 data 里没有
  //   ruleSystemId / ruleShortName。生产载荷已按用户要求加规则标记，
  //   隔离方式照抄 oracle_preset_test.dart 的快照/还原写法。
  late bool savedLegacySharePayloadForOracle;

  setUp(() {
    savedPresetSettings = preset.presetSettings;
    savedRng = nowRng;
    savedClock = nowClock;
    savedUid = uidDeterministic;
    savedLegacySharePayloadForOracle = legacySharePayloadForOracle;
    legacySharePayloadForOracle = true;
  });

  tearDown(() {
    preset.presetSettings = savedPresetSettings;
    setRng(savedRng);
    setClock(savedClock);
    uidDeterministic = savedUid;
    legacySharePayloadForOracle = savedLegacySharePayloadForOracle;
  });

  final oracle = jsonDecode(
    File('test/fixtures/qa_p3_final_gate_oracle.json').readAsStringSync(),
  ) as Map<String, Object?>;

  // ==========================================================
  group('G1 新增攻击面：非 JSON 的 200 响应回显 Key（ai_create.dart:136）', () {
    /// 让网关把请求头回显进 chat 正文（合法 OpenAI 信封 + 非 JSON content），
    /// 走完「首次解析失败 → 大额度重发 → 两次都失败」的真实链路。
    Future<_CreateOutcome> createWithEcho(String content) async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, chatOk(content));
      final client = AiClient(
        configProvider: () =>
            AiConfig(base: server.base, model: 'm', key: kKey),
      );
      final service = AiCreateService(
        client: client,
        capsProvider: () => const AiCaps(),
      );
      Object? caught;
      try {
        await service.makeCharacter('一个调查员', caps: const AiCaps());
      } catch (e) {
        caught = e;
      }
      return _CreateOutcome(caught, server.requests.length);
    }

    /// 前提自证：这段正文确实让 parseJson 把完整 Key 拼进错误文案。
    /// 没有这条，断言可能因「截断把 Key 切一半」而变成空探针。
    String unmaskedParseError(String content) {
      try {
        parseJson(content);
      } on AiGenException catch (e) {
        return e.message;
      }
      return '<no-throw>';
    }

    test('无花括号的 200 回显：开头 40 字含完整 Key → AiException 不含明文',
        () async {
      // Key 放在最前，保证完整落在 parseJson 的 head(40) 里。
      final content = '$kKey gateway echo Authorization: Bearer $kKey';
      expect(unmaskedParseError(content), contains(kKey),
          reason: '前提：攻击载荷必须真的进入解析错误文案');

      final out = await createWithEcho(content);
      expect(out.attempts, 2, reason: '应发生一次大额度重发');
      expect(out.caught, isA<AiException>());
      final msg = (out.caught as AiException).message;
      expect(msg, isNot(contains(kKey)),
          reason: 'ai_create.dart:136 的 why 未过 maskSecrets');
      expect(msg, contains('****'),
          reason: '必须真的发生过打码，而不是靠空串兜底');
      expect(msg, contains('无法解析为角色卡'),
          reason: '打码不能吃掉可读文案');
    });

    test('花括号不配平的 200 回显：末尾 50 字含完整 Key → 同样不泄漏',
        () async {
      // 前缀 67 字符 + 'END ' + 完整 Key；最后 50 字一定包含完整 Key，
      // 命中 parseJson 的 tail(50) 分支（与 head 不同的第二条泄漏路径）。
      final content = '{"a":1${'x' * 60}END $kKey';
      expect(unmaskedParseError(content), contains(kKey),
          reason: '前提：tail 分支也要带明文');

      final out = await createWithEcho(content);
      expect(out.attempts, 2);
      expect(out.caught, isA<AiException>());
      final msg = (out.caught as AiException).message;
      expect(msg, isNot(contains(kKey)));
      expect(msg, contains('****'));
      expect(msg, contains('无法解析为角色卡'));
    });

    test('源码级回归守卫：ai_create / shareErrorFrom 两个审计补点已收口', () {
      String read(String p) => File('lib/$p').readAsStringSync();
      expect(read('net/ai_create.dart'),
          contains('maskSecrets(parseErr ?? e.message)'),
          reason: '两次解析都失败时 why 必须脱敏后才进 UI');
      expect(read('net/share_client.dart'), contains("maskSecrets('\$e')"),
          reason: 'shareErrorFrom 兜底路径必须脱敏');
    });
  });

  // ==========================================================
  group('G2 服务端回显 Key：六个用户可见出口逐个推翻', () {
    test('/models 200 回显 Key 进模型列表 → models / hint / message 全打码',
        () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      server.responder = (req, cap) async => FakeServer.json(
            req,
            200,
            <String, Object?>{
              'data': <Object?>[
                <String, Object?>{'id': kKey},
                <String, Object?>{'id': 'Bearer $kKey'},
              ],
            },
          );
      final r =
          await HttpAiProbe().test(base: server.base, model: 'm', key: kKey);
      expect(server.requests.single.headers['authorization'], 'Bearer $kKey');
      expect(r.kind, AiProbeKind.modelMissing,
          reason: '功能不能被打码改变');
      expect(r.models, hasLength(2));
      expect(blob(r), isNot(contains(kKey)),
          reason: 'models / hint / message 任一处漏打码都会在这里红');
      for (final m in r.models) {
        expect(m, isNot(contains(kKey)));
      }
      expect(r.hint, contains('****'),
          reason: 'hint 里的样例模型名必须真的被脱敏');
    });

    test('chat 200 回复正文回显 Key → reply 片段必须打码', () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      final content = '$kShort gateway echo';
      server.responder = (req, cap) async {
        if (cap.path.endsWith('/models')) {
          await FakeServer.text(req, 404, 'not found');
        } else {
          await FakeServer.json(req, 200, chatOk(content));
        }
      };
      final r =
          await HttpAiProbe().test(base: server.base, model: 'm', key: kKey);
      expect(r.kind, AiProbeKind.ok, reason: '功能：探测应当成功');
      expect(r.via, 'chat');
      final rawReply =
          content.length > 20 ? content.substring(0, 20) : content;
      expect(rawReply, contains(kShort),
          reason: '前提：未打码的 reply 片段确实含完整短 Key');
      expect(r.reply, isNot(rawReply), reason: 'reply 必须被归一化改写');
      expect(r.reply, maskSecrets(rawReply));
      expect(r.reply, isNot(contains(kShort)));
      expect(r.reply, contains('****'));
      expect(blob(r), isNot(contains(kShort)));
    });

    test('SettingsRepo 403 错误体回显 Key → lastProbe / describe / 未知键全不泄漏',
        () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      server.responder = (req, cap) async => FakeServer.json(
            req,
            403,
            <String, Object?>{
              'error': <String, Object?>{
                'message': 'gateway echo: Bearer $kKey / $kKey',
              },
            },
          );
      final repo = SettingsRepo(
        storage: MemorySettingsStorage(<String, Object?>{
          'aiBase': server.base,
          'aiModel': 'm-$kKey',
          'aiKey': kKey,
          'qaUnknownKey': 'note $kKey',
        }),
        probe: HttpAiProbe(),
      );
      await repo.load();
      final r = await repo.testConnection();
      expect(r.kind, AiProbeKind.badKey, reason: '功能不能被脱敏改变');
      expect(server.requests.single.headers['authorization'], 'Bearer $kKey');

      // 工程师异议 1 的核心：describe() 本来就不拼 lastProbe；这里另造一条
      // 独立攻击面 —— 用户把 Key 粘进「别的格子」（aiModel / 未知键）时，
      // 调试快照也不许漏。同时把 lastProbe 的六个出口一起网住。
      final describe = jsonEncode(repo.describe());
      final all = <String>[
        blob(r),
        describe,
        repo.lastError ?? '',
        repo.lastProbe?.message ?? '',
        repo.lastProbe?.hint ?? '',
        repo.lastProbe?.reply ?? '',
        (repo.lastProbe?.models ?? const <String>[]).join(','),
      ].join(' | ');
      expect(all, isNot(contains(kKey)),
          reason: 'lastProbe 六出口 + describe 任一漏打码都会红');
      expect(describe, isNot(contains(kKey)));
      expect(describe, contains('sk-a****3456'),
          reason: '必须真的打过码');
      expect(repo.describe()['qaUnknownKey'], isNotNull,
          reason: '未知键保留（H4 不变式）不能被防御性打码弄丢');
    });

    test('分享 500 超长错误体 + shareErrorFrom 兜底：两处都不泄漏', () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      // Key 放在前 140 字内（share_client 的截断窗口），同时给 Bearer 与裸 sk-。
      final body = 'gateway echo: Bearer $kKey / $kKey / ${'x' * 200}';
      server.responder = (req, cap) async =>
          FakeServer.text(req, 500, body);
      final c = Character(newCharacter());
      c.raw['characterName'] = '甲';
      Object? caught;
      try {
        await ShareClient(baseProvider: () => server.base).create(c);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ShareException>());
      expect(blob(caught), isNot(contains(kKey)));
      expect(blob(caught), contains('500'), reason: '状态码仍可读');
      expect(blob(caught), contains('****'), reason: '必须真的打过码');

      // 工程师自审补的第二条：任意异常经 shareErrorFrom 变成用户可见文本
      final wrapped = shareErrorFrom(StateError('gateway echo $kKey'));
      expect(wrapped.message, isNot(contains(kKey)));
      expect(wrapped.message, contains('****'));
    });

    test('AiClient chat 500 JSON 错误体回显 Key → 异常文案不泄漏', () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      // explainHttpError 只从 JSON 的 error.message / message 取 detail；
      // 用纯文本反而拼不进文案（会变成空探针），必须给 JSON 形态。
      server.responder = (req, cap) async => FakeServer.json(
            req,
            500,
            <String, Object?>{
              'error': <String, Object?>{
                'message': 'gateway echo: Bearer $kKey / $kKey',
              },
            },
          );
      final client = AiClient(
        configProvider: () =>
            AiConfig(base: server.base, model: 'm', key: kKey),
      );
      Object? caught;
      try {
        await client.chat(<Map<String, String>>[
          <String, String>{'role': 'user', 'content': 'hi'},
        ]);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<AiException>());
      expect(blob(caught), isNot(contains(kKey)));
      expect(blob(caught), contains('****'));
    });
  });

  // ==========================================================
  group('G3 unitName 全部 falsy 变体：与旧版 core/share.js 逐字节对照', () {
    final cases =
        (oracle['unitNameCases'] as List).cast<Map<String, Object?>>();

    test('7 种 occupationName 取值 → body 逐字节一致，且 unitName 不是 "null"',
        () {
      expect(cases, hasLength(7));
      for (final c in cases) {
        final card = Character(Map<String, Object?>.from(c['card'] as Map));
        final body = jsonEncode(
          buildSharePayload(card, sharedAt: 1700000000000),
        );
        expect(body, c['body'],
            reason: '变体 ${c['id']}：与旧版请求体逐字节不一致');
        final data =
            (jsonDecode(body) as Map<String, Object?>)['data'] as Map<String, Object?>;
        expect(data['unitName'], c['unitName'],
            reason: '变体 ${c['id']}：unitName');
        expect(data['unitName'], isNot('null'),
            reason: '变体 ${c['id']}：jsStr(null) 的 "null" 又回来了');
      }
    });
  });

  // ==========================================================
  group('G4 toProfile occupationSkills 混合 falsy 数组', () {
    final t = oracle['toProfile'] as Map<String, Object?>;

    test('旧版 String(x || "").trim() + filter(Boolean) + slice(0,8) 逐字段一致',
        () {
      final actual = toProfile(t['raw']);
      expect(jsonEncode(actual), jsonEncode(t['expect']),
          reason: '与旧版 core/ai.js#toProfile 不逐字一致');
      final skills = actual['occupationSkills'] as List<Object?>?;
      expect(skills, isNotNull);
      expect(skills, hasLength(8), reason: 'slice(0, 8) 上限');
      expect(skills, isNot(contains('false')));
      expect(skills, isNot(contains('0')));
      for (final s in skills!) {
        expect(s, isA<String>());
        expect(s, (s as String).trim(), reason: '每个技能名必须 trim');
      }
    });

    test('全 falsy 数组 → occupationSkills 为 null，不留空壳', () {
      final p = toProfile(<String, Object?>{
        'occupationSkills': <Object?>[false, 0, null, '', '  ', <Object?>[]],
      });
      expect(p['occupationSkills'], isNull);
    });
  });

  // ==========================================================
  group('G5 缺陷 6：默认随机源分布（不注入 LCG）+ 注入点未破', () {
    test('默认 nowRng 连取 2000 次：不再成片偏低 / 不再高度相关', () {
      final samples = List<double>.generate(2000, (_) => nowRng());
      for (final x in samples) {
        expect(x >= 0.0 && x < 1.0, isTrue, reason: '越界: $x');
      }
      final mean = samples.reduce((a, b) => a + b) / samples.length;
      expect(mean, greaterThan(0.44), reason: '均值偏低: $mean');
      expect(mean, lessThan(0.56), reason: '均值偏高: $mean');

      // 十个十分位都要命中：微秒取模在短时窗内只落 1 个十分位。
      final buckets = List<int>.filled(10, 0);
      for (final x in samples) {
        buckets[(x * 10).floor()]++;
      }
      expect(buckets.every((n) => n > 20), isTrue,
          reason: '十分位分布: $buckets');

      // 相邻取值几乎相同的比例：真随机 ~0.2%，微秒取模 ~100%。
      var close = 0;
      for (var i = 1; i < samples.length; i++) {
        if ((samples[i] - samples[i - 1]).abs() < 0.001) {
          close++;
        }
      }
      expect(close / (samples.length - 1), lessThan(0.05),
          reason: '相邻高度相关比例: ${close / (samples.length - 1)}');
    });

    test('探针有效性自证：修复前的微秒取模序列会被上面三条阈值判红', () {
      // 确定性复刻旧算法：连续调用时微秒计数器每次只前进约 1 微秒，
      // 2000 次取样落在宽度约 0.002 的窄带里。若这条不自证，分布探针
      // 就是「怎么改都绿」的空网 —— 必须先证明它抓得住旧实现。
      const int base = 337;
      final old = List<double>.generate(2000, (i) => (base + i) / 1000000.0);
      final buckets = List<int>.filled(10, 0);
      for (final x in old) {
        buckets[(x * 10).floor()]++;
      }
      expect(buckets.every((n) => n > 20), isFalse,
          reason: '前提：旧算法的十分位分布必须被判红');
      var close = 0;
      for (var i = 1; i < old.length; i++) {
        if ((old[i] - old[i - 1]).abs() < 0.001) {
          close++;
        }
      }
      expect(close / (old.length - 1), greaterThan(0.95),
          reason: '前提：旧算法相邻高度相关');
    });

    test('setRng 注入仍生效（oracle 契约不破）且可原样还原', () {
      final before = nowRng;
      setRng(() => 0.25);
      expect(nowRng(), 0.25);
      expect(nowRng(), 0.25);
      setRng(before);
      expect(nowRng, same(before));
    });

    test('源码守卫：默认源是进程级 math.Random，旧微秒取模已移除', () {
      final src = File('lib/domain/js_compat.dart').readAsStringSync();
      expect(src, contains("import 'dart:math' as math;"));
      expect(src, contains('final math.Random _systemRng = math.Random();'));
      expect(src, contains('double _mathRandom() => _systemRng.nextDouble();'));
      expect(src, contains('void setRng(JsRng rng) => nowRng = rng;'),
          reason: '所有 oracle 都靠这个注入点钉序列，不能丢');
      expect(src.contains('microsecondsSinceEpoch % 1000000'), isFalse,
          reason: '旧实现不能残留');
    });
  });
}
