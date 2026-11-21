// ============================================================
// QA P3 独立探针 · B（最终版）：H2（API Key 不泄漏） + H3（分享契约逐字一致）
//
// 收敛说明：本文件由原 qa_edward_p3_h2_h3_strict_test.dart（严格版）与
// 原 qa_p3_h2_h3_test.dart（弱版）合并而来，是唯一保留的 H2/H3 探针。
// 严格版的「服务端回显 Key / oracle 逐字节对照」全部保留，弱版独有的
// 断言（fixture 无明文 Key、错误文案可读、导出类型标记、Authorization 头、
// 未配置不清记录、口令保留、删除请求体）逐条并入，**没有删断言、没有 skip、
// 没有把任何 expect 改弱**。
//
// H3 期望值来自 tool/qa/qa_p3_oracle_gen.js 抓的旧版 CocShare.fetch。
// 只改 test/ 下内容，不改 lib/。全部走本机 127.0.0.1 假服务。
// 注意：本文件刻意不含 testWidgets —— 同一 suite 里混入 testWidgets 会触发
// flutter_test 的 HttpOverrides，让所有真实 HttpClient 请求变成 400（假阳性）。
//
// ★ P7 收尾：H3 现在验的是**旧版 wire 契约**（不含 ruleSystemId /
//   ruleShortName）。生产载荷按用户要求带规则标记，属于有意偏离旧版，
//   由 setUp 的 legacySharePayloadForOracle=true 隔离，fixture 与全部
//   expect 一个字未改。生产载荷的规则标记由 test/p7_share_badge_test.dart
//   （含真实 FakeServer wire 级验证）覆盖。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/ai_probe.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/net/ai_client.dart';
import 'package:dice_realm/net/share_client.dart';
import 'package:dice_realm/repo/ai_probe_io.dart';
import 'package:dice_realm/repo/card_transfer.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/repo/share_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' as harness;
import 'support/fake_http.dart';

const String kKey = 'sk-abcdefghijklmnopqrstuvwxyz123456';

String blob(Object? o) {
  if (o == null) return '';
  final parts = <String>[o.toString()];
  if (o is AiException) parts.add(o.message);
  if (o is ShareException) parts.add(o.message);
  if (o is AiProbeResult) {
    parts.addAll(<String>[
      o.message, o.hint, o.reply, o.kindLabel, o.models.join(','),
    ]);
  }
  return parts.join(' | ');
}

Map<String, Object?> echoError(int status) => <String, Object?>{
  'error': <String, Object?>{
    'message': 'gateway echo: Bearer $kKey / $kKey',
    'type': 'invalid_request_error',
  },
};

void main() {
  // SettingsRepo.load()/save() 会调 applyToDomain() 改写全局
  // preset.presetSettings（lib/repo/settings_repo.dart:220）。本文件 H2 的
  // 「导出 / 分享请求体不夹带 settings」用例会造一个带 aiAttrCap=420 的
  // repo，若不还原就会污染同文件后续用例。连同 nowRng / nowClock /
  // uidDeterministic 一起在用例前快照、用例后还原，保证探针自身不泄漏全局。
  late Map<String, Object?> savedPresetSettings;
  late JsRng savedRng;
  late JsClock savedClock;
  late bool savedUid;
  // ★ P7：H3 逐字节比对的是旧版 wire 契约，冻结 fixture 的 data 里没有
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

  // ==========================================================
  group('H2 严格探针：四条异常路径都让服务端回显 Key', () {
    test('chat 401 → 已打码 + Authorization 头确实发出（功能对/安全对）',
        () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      final httpClient = HttpClient();
      addTearDown(() => httpClient.close(force: true));
      server.responder = (req, cap) async =>
          FakeServer.json(req, 401, echoError(401));
      final client = AiClient(
        configProvider: () =>
            AiConfig(base: server.base, model: 'm', key: kKey),
        httpClient: httpClient,
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
      expect(server.requests.single.headers['authorization'], 'Bearer $kKey');
      expect(blob(caught), isNot(contains(kKey)));
      expect(blob(caught), contains('sk-a****3456'));
      // 弱版并入：401 的人话分类不能被打码吃掉，错误仍要可读
      expect(blob(caught), contains('API Key 不正确'));
    });

    test('chat 超时 → 错误文本无明文', () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      final httpClient = HttpClient();
      addTearDown(() => httpClient.close(force: true));
      server.responder = (req, cap) async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        try {
          await FakeServer.json(req, 200, chatOk('ok'));
        } catch (_) {
          // 客户端已超时断开
        }
      };
      final client = AiClient(
        configProvider: () =>
            AiConfig(base: server.base, model: 'm', key: kKey),
        httpClient: httpClient,
      );
      Object? caught;
      try {
        await client.chat(
          <Map<String, String>>[
            <String, String>{'role': 'user', 'content': 'hi'},
          ],
          timeout: const Duration(milliseconds: 200),
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<AiException>());
      expect(blob(caught), isNot(contains(kKey)));
      expect(blob(caught).contains('超时'), isTrue);
      // 弱版并入：超时路径也要确认 Authorization 头确实发出去了
      expect(server.requests.single.headers['authorization'], 'Bearer $kKey');
    });

    test('测试连接失败（/models 401 回显 Key）→ message 不得泄漏明文',
        () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      server.responder = (req, cap) async =>
          FakeServer.json(req, 401, echoError(401));
      final r = await HttpAiProbe().test(
        base: server.base, model: 'm', key: kKey,
      );
      expect(r.kind, isNot(AiProbeKind.ok));
      expect(server.requests.single.headers['authorization'], 'Bearer $kKey');
      expect(blob(r), isNot(contains(kKey)),
          reason: 'ai_probe_io.dart 的 explainHttpError 结果没过 maskSecrets');
    });

    test('SettingsRepo.testConnection 的 lastProbe / describe 不得泄漏明文',
        () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      server.responder = (req, cap) async => FakeServer.json(req, 403,
          <String, Object?>{'error': <String, Object?>{'message':
              'echo $kKey'}});
      final repo = SettingsRepo(
        storage: MemorySettingsStorage(<String, Object?>{
          'aiBase': server.base, 'aiModel': 'm', 'aiKey': kKey,
        }),
        probe: HttpAiProbe(),
      );
      await repo.load();
      final r = await repo.testConnection();
      final all = <String>[
        blob(r),
        jsonEncode(repo.describe()),
        repo.lastError ?? '',
        repo.lastProbe?.message ?? '',
        repo.lastProbe?.hint ?? '',
      ].join(' | ');
      expect(all, isNot(contains(kKey)),
          reason: 'settings_repo.dart:364 只 mask 了 catch 分支，正常返回的'
              'AiProbeResult.message 没打码，settings_page.dart:323 会直接显示');
      // describe() 本身是打码的，用来定位问题确实在 probe 结果而不是 settings 快照
      expect(jsonEncode(repo.describe()), isNot(contains(kKey)));
    });

    test('分享 500 的错误体回显 Key → 必须过 maskSecrets',
        () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      server.responder = (req, cap) async => FakeServer.text(
        req, 500, 'gateway echo: Bearer $kKey / $kKey',
      );
      final client = ShareClient(baseProvider: () => server.base);
      Object? caught;
      try {
        final c = Character(newCharacter());
        c.raw['characterName'] = '甲';
        await client.create(c);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ShareException>());
      // 分享请求本身不发 Key，功能侧先确认这一点
      expect(server.requests.single.headers['authorization'], isNull);
      expect(server.requests.single.body, isNot(contains(kKey)));
      expect(blob(caught), isNot(contains(kKey)),
          reason: 'share_client.dart:183 直接拼 res.body，与 ai_client.dart:210 口径不一致');
      // 弱版并入：错误仍要可读，状态码不能被打码吃掉
      expect(blob(caught), contains('500'));
    });

    test('源码级回归守卫：4 个异常文本构造点都调用 maskSecrets', () {
      // 修复前这里断言 isFalse（把「缺陷存在」写死成期望）；修复后翻成
      // isTrue，变成防止再次漏打码的回归守卫。断言没有被改弱。
      String read(String p) => File('lib/$p').readAsStringSync();
      expect(read('net/ai_client.dart').contains('maskSecrets('), isTrue);
      expect(read('repo/settings_repo.dart').contains('maskSecrets('), isTrue);
      expect(read('repo/ai_probe_io.dart').contains('maskSecrets('), isTrue,
          reason: '测试连接的消息构造必须脱敏');
      expect(read('net/share_client.dart').contains('maskSecrets('), isTrue,
          reason: '分享错误文本必须脱敏');
      // 一行修复可行性：同一份 maskSecrets 对回显体有效
      final raw = explainHttpError(401, jsonEncode(echoError(401)));
      expect(raw, contains(kKey), reason: '前提：未打码的错误体确实含明文');
      final masked = maskSecrets(raw);
      expect(masked, isNot(contains(kKey)));
      // 弱版并入：打码后的可读前缀要保留
      expect(masked, contains('sk-a****3456'));
    });

    test('导出 / 分享请求体不夹带 settings（Key 只在本机 settings 文件）',
        () async {
      final repo = SettingsRepo(
        storage: MemorySettingsStorage(<String, Object?>{
          'aiKey': kKey,
          'shareBase': 'https://share.example.com',
          'aiAttrCap': 420,
        }),
      );
      await repo.load();
      final c = Character(newCharacter());
      c.raw['characterName'] = '导出检查';
      final single = exportCardJson(c);
      final bundle = exportBundleJson(<Character>[c]);
      final payload =
          jsonEncode(buildSharePayload(c, sharedAt: 1700000000000));
      // 弱版并入：导出文件确实带类型标记，且设置键不跟着走
      expect(single, contains('coc7-card'));
      expect(bundle, contains('coc7-bundle'));
      expect(single, isNot(contains('shareBase')));
      expect(bundle, isNot(contains('shareBase')));
      expect(single, isNot(contains('aiAttrCap')));
      expect(bundle, isNot(contains('aiAttrCap')));
      for (final s in <String>[single, bundle, payload]) {
        expect(s, isNot(contains(kKey)));
        expect(s, isNot(contains('"aiKey"')));
        expect(s, isNot(contains('"settings"')));
      }
    });

    // 弱版独有的整条用例：导出/分享 fixture 目录里不许出现明文 Key
    test('所有 fixture 里没有明文 API Key', () {
      final dir = Directory('test/fixtures');
      for (final f in dir.listSync().whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains(kKey)),
            reason: '${f.path} 夹带明文 Key');
      }
    });
  });

  // ==========================================================
  group('H3 严格探针：旧版 core/share.js 抓包逐字节对照', () {
    final oracle = jsonDecode(
      File('test/fixtures/qa_p3_share_oracle.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final cards = (oracle['cards'] as List).cast<Map<String, Object?>>();
    final captures = (oracle['captures'] as List).cast<Map<String, Object?>>();

    Character cardOf(int i) =>
        Character(Map<String, Object?>.from(cards[i]));

    test('完整卡：POST /api/cards 请求体逐字节一致', () {
      final create = captures[0];
      expect(create['method'], 'POST');
      expect(create['url'], 'http://127.0.0.1:9/coc/api/cards');
      expect((create['headers'] as Map)['Content-Type'], 'application/json');
      final body = jsonEncode(
        buildSharePayload(cardOf(0), sharedAt: 1700000000000),
      );
      expect(body, create['body'],
          reason: 'card1：Dart 请求体与旧版逐字节不一致');
      expect(body, isNot(contains('tok_qa')));
    });

    test('老卡（basicInfo 缺 occupationName）：unitName 应为 \'\' 而非 \'null\'',
        () {
      final create = captures[2];
      final body = jsonEncode(
        buildSharePayload(cardOf(1), sharedAt: 1700000000000),
      );
      expect(body, create['body'],
          reason: 'share_client.dart:127 用 jsStr(null)="null"，旧版 '
              '(basicInfo||{}).occupationName || \'\' 给空串');
    });

    test('删除请求：路由 / 方法 / body {"token":...} 逐字一致', () {
      for (final i in <int>[1, 3]) {
        final del = captures[i];
        expect(del['method'], 'POST');
        expect(del['url'], 'http://127.0.0.1:9/coc/api/cards/sh_qa/del');
        expect((del['headers'] as Map)['Content-Type'], 'application/json');
        expect(del['body'], '{"token":"tok_qa"}');
      }
    });

    test('shareBase 未配置 → 零请求 / 本地记录不清（含 ShareService 层）',
        () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      final client = ShareClient(baseProvider: () => '');
      final c = Character(newCharacter());
      c.raw['characterName'] = '甲';
      for (final call in <Future<void> Function()>[
        () async => client.create(c),
        () => client.remove('sh_1', 'tok'),
      ]) {
        Object? caught;
        try {
          await call();
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<ShareException>());
        expect((caught as ShareException).kind, ShareErrorKind.unconfigured);
      }
      expect(server.requests, isEmpty);

      // 弱版并入：未配置失败不能清掉本地记录（否则用户再也删不掉云端那条）
      final store = await harness.newMemoryShareStore();
      final service = ShareService(client: client, store: store);
      await store.put('qaUnconfigured', const ShareRecord(
        id: 'sh_1', url: 'u', delToken: 'tok_qa', at: 1, name: '甲',
      ));
      Object? e1;
      try {
        await service.create(c);
      } catch (e) {
        e1 = e;
      }
      expect(e1, isA<ShareException>());
      Object? e2;
      try {
        await service.remove('qaUnconfigured');
      } catch (e) {
        e2 = e;
      }
      expect(e2, isA<ShareException>());
      expect((e2 as ShareException).kind, ShareErrorKind.unconfigured);
      expect(server.requests, isEmpty);
      expect(store.forCard('qaUnconfigured'), isNotNull,
          reason: '未配置失败不能清记录');
    });

    test('delToken 落盘 → 新实例读回；删除成功清记录', () async {
      final dir = await Directory.systemTemp.createTemp('qa_p3_share_');
      addTearDown(() => dir.delete(recursive: true));
      final storage = JsonFileShareStorage(directory: dir);
      final s1 = ShareStore(storage: storage);
      await s1.load();
      await s1.put('cardX', const ShareRecord(
        id: 'sh_1', url: 'https://s/c/sh_1', delToken: 'tok-secret-qa',
        at: 1700000000000, name: '甲',
      ));
      final s2 = ShareStore(storage: storage);
      await s2.load();
      expect(s2.forCard('cardX')?.delToken, 'tok-secret-qa');
      // 弱版并入：url 也要完整读回
      expect(s2.forCard('cardX')?.url, 'https://s/c/sh_1');
      expect(jsonEncode(s2.forCard('cardX')?.describe()),
          isNot(contains('tok-secret-qa')));
      await s2.remove('cardX');
      final s3 = ShareStore(storage: storage);
      await s3.load();
      expect(s3.forCard('cardX'), isNull);
    });

    test('删分享失败（403 / token 错）→ 可读错误 + 本地记录保留', () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      final store = await harness.newMemoryShareStore();
      final service = ShareService(
        client: ShareClient(baseProvider: () => server.base),
        store: store,
      );
      final c = Character(newCharacter());
      c.raw['id'] = 'cardDel';
      c.raw['characterName'] = '甲';
      server.responder = (req, cap) async => FakeServer.json(req, 200,
          <String, Object?>{'id': 'sh_1', 'url': 'u', 'delToken': 'tok_qa'});
      expect((await service.create(c)).delToken, 'tok_qa');
      expect(server.requests.last.body, isNot(contains('tok_qa')));

      server.responder = (req, cap) async =>
          FakeServer.text(req, 403, 'bad token');
      Object? caught;
      try {
        await service.remove('cardDel');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ShareException>());
      expect((caught as ShareException).kind, ShareErrorKind.http);
      expect(caught.message.contains('403'), isTrue);
      expect(store.forCard('cardDel'), isNotNull,
          reason: '失败时提前清记录 = 用户永远删不掉云端那条');
      // 弱版并入：记录里的口令仍是原值，可以重试
      expect(store.forCard('cardDel')!.delToken, 'tok_qa');
      expect(server.requests.last.path, endsWith('/api/cards/sh_1/del'));
      expect(server.requests.last.body, '{"token":"tok_qa"}');

      server.responder = (req, cap) async => FakeServer.text(req, 200, 'ok');
      await service.remove('cardDel');
      expect(store.forCard('cardDel'), isNull);
      // 弱版并入：删除成功的真实请求方法 / 路由 / 请求体
      expect(server.requests.last.method, 'POST');
      expect(server.requests.last.path, endsWith('/api/cards/sh_1/del'));
      expect(server.requests.last.body, '{"token":"tok_qa"}');
    });

    test('无本机记录 → noRecord 可读错误，不发请求', () async {
      final server = await FakeServer.start();
      addTearDown(server.close);
      final service = ShareService(
        client: ShareClient(baseProvider: () => server.base),
        store: await harness.newMemoryShareStore(),
      );
      Object? caught;
      try {
        await service.remove('never-shared');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ShareException>());
      expect((caught as ShareException).kind, ShareErrorKind.noRecord);
      expect(caught.message.contains('本机没有'), isTrue);
      expect(server.requests, isEmpty);
    });
  });
}
