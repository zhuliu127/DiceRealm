// ============================================================
// P7 · 云分享规则徽标（生产路径 + 旧版预言机隔离自证伪 + 本机记录 + 面板）
//
// 本批是一次**有意偏离旧版 wire 契约**的改动：
//   · `core/share.js#buildPayload`（旧版）的 data 里没有规则字段；
//   · 生产 `buildSharePayload` 按用户要求新增 ruleSystemId / ruleShortName；
//   · `qa_p3_h2_h3_test.dart` / `qa_p3_final_gate_test.dart` 的冻结 fixture
//     仍逐字节验旧版，靠 `legacySharePayloadForOracle` 开关隔离。
//
// 因此本文件必须证明三件事，缺一不可：
//   ① 生产默认路径真的带规则字段（含老卡 / 占位 id 的回退口径）；
//   ② 规则字段**真的进了 wire**（打 FakeServer 抓 server.requests.single.body，
//      而不是只测一个没人调用的纯函数）；
//   ③ 隔离不是摆设：关掉开关后与冻结 captures[0]['body'] 真的不相等，
//      且差异只来自新增的两个规则字段（H3 若去掉隔离会真红）。
//
// ⚠️ 本文件同时含 `test()` 与 `testWidgets()`。flutter_test 在**注册**
//    testWidgets 时就安装 `HttpOverrides.global = _MockHttpOverrides`（所有
//    裸 `HttpClient()` 一律返回 400），所以真实 HTTP 用例必须显式跑在
//    `HttpOverrides.runWithHttpOverrides` 的干净 zone 里 —— 基类
//    `HttpOverrides.createHttpClient` 的默认实现就是构造真 `_HttpClient`。
//    这也是 qa_p3_* 那两个文件「刻意不含 testWidgets」的同一个原因。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/rule_registry.dart';
import 'package:dice_realm/net/share_client.dart';
import 'package:dice_realm/repo/share_store.dart';
import 'package:dice_realm/theme.dart';
import 'package:dice_realm/ui/share_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' as harness;
import 'support/fake_http.dart';

/// 空子类即可：`HttpOverrides` 基类的 `createHttpClient` 默认实现
/// 就是构造真实的 `dart:io` `_HttpClient`，不会走 flutter_test 的 400 假响应。
class _RealHttpOverrides extends HttpOverrides {}

Character _card() {
  final c = Character(newCharacter());
  c.raw['id'] = 'cardBadge';
  c.raw['characterName'] = '林晚';
  c.raw['playerName'] = '老王';
  c.basicInfo['occupationName'] = '记者';
  return c;
}

Widget _host(Widget child) => AppBackground(
  child: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

/// 起一次**真实**本机 HTTP 往返，返回服务端抓到的原始请求体。
/// 断言的是 `ShareClient.create()` 这条生产出站链路，不是纯函数。
Future<String> _postAndCapture(Character c) async {
  return HttpOverrides.runWithHttpOverrides<Future<String>>(() async {
    final server = await FakeServer.start();
    try {
      server.responder = (req, cap) async => FakeServer.json(
        req,
        200,
        <String, Object?>{
          'id': 'sh_badge',
          'url': 'https://share.example.com/c/sh_badge',
          'delToken': 'tok_resp_secret',
        },
      );
      final client = ShareClient(baseProvider: () => server.base);
      final res = await client.create(c);
      expect(res.id, 'sh_badge', reason: '真实 HTTP 往返必须成功');
      expect(server.requests, hasLength(1));
      return server.requests.single.body;
    } finally {
      await server.close();
    }
  }, _RealHttpOverrides());
}

void main() {
  // 每次用例都从「生产默认 false」起步，tearDown 还原 setUp 快照，
  // 与 oracle_preset_test.dart 的 savedLegacyAttrCapForOracle 同款写法。
  late bool savedLegacySharePayloadForOracle;

  setUp(() {
    savedLegacySharePayloadForOracle = legacySharePayloadForOracle;
    legacySharePayloadForOracle = false;
  });

  tearDown(() {
    legacySharePayloadForOracle = savedLegacySharePayloadForOracle;
  });

  group('① 生产默认路径', () {
    test('data 带规则字段，旧版已有字段一个不少，顶层形状不变', () {
      expect(legacySharePayloadForOracle, isFalse,
          reason: '生产默认必须是 false');
      final payload = buildSharePayload(_card(), sharedAt: 1700000000000);
      expect(payload.keys.toSet(), <String>{'name', 'visibility', 'data'},
          reason: '规则字段只加在 data 层，不许污染顶层');

      final data = (payload['data'] as Map).cast<String, Object?>();
      expect(data['ruleSystemId'], 'coc7');
      expect(data['ruleShortName'], 'COC 7th');
      expect(RuleRegistry.effectiveId('coc7'), 'coc7');
      expect(RuleRegistry.shortNameOf(RuleRegistry.effectiveId('coc7')),
          'COC 7th');

      // 旧版 buildPayload 的全部 data 字段，一个都不能被挤掉。
      for (final k in <String>[
        'characterName',
        'playerName',
        'basicInfo',
        'attributes',
        'derivedStats',
        'status',
        'assets',
        'background',
        'skills',
        'weapons',
        'items',
        'mythos',
        'history',
        'unitName',
        'sharedAt',
      ]) {
        expect(data.containsKey(k), isTrue, reason: '旧版字段 $k 不能丢');
      }
      expect(data['sharedAt'], 1700000000000);
      expect(data['unitName'], '记者');
    });
  });

  group('② 老卡 / 未知 id / 占位 id 回退', () {
    test('空、空串、瞎填、占位 id、字面量 null/None 都给 coc7 + COC 7th', () {
      final variants = <Object?>[
        null, // 完全缺字段：c.ruleSystemId 会是 jsStr(null) == 'null'
        '',
        '   ',
        'garbage-xyz',
        'dnd5e', // 未开放占位项
        'custom', // 未开放占位项
        'null',
        'None',
      ];
      for (final v in variants) {
        final c = _card();
        if (v == null) {
          c.raw.remove('ruleSystemId');
        } else {
          c.raw['ruleSystemId'] = v;
        }
        final payload = buildSharePayload(c);
        final data = (payload['data'] as Map).cast<String, Object?>();
        expect(data['ruleSystemId'], 'coc7', reason: '变体 $v 的 ruleSystemId');
        expect(data['ruleShortName'], 'COC 7th',
            reason: '变体 $v 的 ruleShortName');
        // 占位 id 绝不能让两个字段打架（'coc7' + 'DND 5E'）。
        expect(data['ruleShortName'], isNot('DND 5E'), reason: '变体 $v');
        expect(data['ruleShortName'], isNot('自定义'), reason: '变体 $v');

        // 只针对规则字段检查：绝不把 jsStr(null) 的字符串 'null' 印出去。
        final ruleOnly = jsonEncode(<String, Object?>{
          'ruleSystemId': data['ruleSystemId'],
          'ruleShortName': data['ruleShortName'],
        });
        expect(ruleOnly, isNot(contains('null')), reason: '变体 $v 印出了 null');
        expect(ruleOnly, isNot(contains('None')), reason: '变体 $v 印出了 None');
      }
    });
  });

  group('③ 真实 wire 级 + ⑦ 脱敏回归', () {
    test('ShareClient.create() 发出的请求体 data 里真有规则字段', () async {
      final body = await _postAndCapture(_card());
      final decoded = jsonDecode(body) as Map<String, Object?>;
      final data = (decoded['data'] as Map).cast<String, Object?>();
      expect(data['ruleSystemId'], 'coc7');
      expect(data['ruleShortName'], 'COC 7th');
      expect(body, contains('"ruleSystemId":"coc7"'));
      expect(body, contains('"ruleShortName":"COC 7th"'));
      // 顶层仍只有三键（服务端 render_card 收的是 data）。
      expect(decoded.keys.toSet(), <String>{'name', 'visibility', 'data'});
    });

    test('请求体不含 delToken / API Key / settings', () async {
      final c = _card();
      c.raw['aiKey'] = 'sk-should-never-upload';
      c.raw['delToken'] = 'tok-local-only';
      c.raw['settings'] = <String, Object?>{
        'aiKey': 'sk-should-never-upload',
        'shareBase': 'https://share.example.com',
      };
      final body = await _postAndCapture(c);
      expect(body, isNot(contains('tok_resp_secret')),
          reason: '响应里的删除口令绝不能回流到请求');
      expect(body, isNot(contains('tok-local-only')));
      expect(body, isNot(contains('sk-should-never-upload')));
      expect(body, isNot(contains('"aiKey"')));
      expect(body, isNot(contains('"delToken"')));
      expect(body, isNot(contains('"settings"')));
      expect(body, isNot(contains('"shareBase"')));
      // 脱敏回归不能把新规则字段一起误删。
      expect(body, contains('"ruleSystemId":"coc7"'));
      expect(body, contains('"ruleShortName":"COC 7th"'));
    });
  });

  group('④ 隔离自证伪（H3 若去掉隔离会真红）', () {
    test('开关 true 逐字节等于冻结 captures[0]；false 时不等且差异只来自规则字段',
        () {
      final oracle = jsonDecode(
        File('test/fixtures/qa_p3_share_oracle.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cards = (oracle['cards'] as List).cast<Map<String, Object?>>();
      final captures = (oracle['captures'] as List).cast<Map<String, Object?>>();
      final legacyBody = captures[0]['body'] as String;
      final c = Character(Map<String, Object?>.from(cards[0]));

      // 正方向：开关打开时，create() 调用的就是这个函数，且逐字节回到旧版。
      legacySharePayloadForOracle = true;
      final isolated = jsonEncode(
        buildSharePayload(c, sharedAt: 1700000000000),
      );
      expect(isolated, legacyBody,
          reason: '预言机隔离必须让同一函数逐字节回到旧版 wire 契约');
      expect(isolated, isNot(contains('ruleSystemId')));

      // 反方向：关掉隔离，逐字节比对必须失败，证明 H3 不是测了个死函数。
      legacySharePayloadForOracle = false;
      final prodBody = jsonEncode(
        buildSharePayload(c, sharedAt: 1700000000000),
      );
      expect(prodBody, isNot(legacyBody),
          reason: '生产载荷若仍与旧版逐字节相等，说明规则字段根本没发出去');
      expect(prodBody, contains('ruleSystemId'));

      // 差异必须**只**来自两个规则字段，旧版其它字段一个字节都没被改坏。
      final prod = jsonDecode(prodBody) as Map<String, Object?>;
      final legacy = jsonDecode(legacyBody) as Map<String, Object?>;
      expect(prod['name'], legacy['name']);
      expect(prod['visibility'], legacy['visibility']);
      final prodData = (prod['data'] as Map).cast<String, Object?>();
      final legacyData = (legacy['data'] as Map).cast<String, Object?>();
      expect(prodData['ruleSystemId'], 'coc7');
      expect(prodData['ruleShortName'], 'COC 7th');
      expect(legacyData.containsKey('ruleSystemId'), isFalse);
      expect(legacyData.containsKey('ruleShortName'), isFalse);
      final stripped = Map<String, Object?>.from(prodData)
        ..remove('ruleSystemId')
        ..remove('ruleShortName');
      expect(jsonEncode(stripped), jsonEncode(legacyData),
          reason: '摘掉两个新字段后必须逐字节等于旧版 data');
    });
  });

  group('⑤ ShareRecord 往返 / 脱敏 / copyWith', () {
    test('新字段落盘读回；旧 JSON 缺字段给空串；describe 仍不含口令', () async {
      const rec = ShareRecord(
        id: 'sh_1',
        url: 'https://share.example.com/c/sh_1',
        delToken: 'tok-super-secret',
        at: 1700000000000,
        name: '林晚',
        ruleShortName: 'COC 7th',
      );
      expect(rec.toJson()['ruleShortName'], 'COC 7th');
      final back = ShareRecord.fromJson(rec.toJson());
      expect(back.ruleShortName, 'COC 7th');
      expect(back.delToken, 'tok-super-secret');
      expect(back.copyWith(name: '林晚改').ruleShortName, 'COC 7th');

      // 老 JSON 完全没有该字段。
      final old = ShareRecord.fromJson(<String, Object?>{
        'id': 'sh_0',
        'url': 'u',
        'delToken': 't',
        'at': 1,
        'name': '老卡',
      });
      expect(old.ruleShortName, '');
      expect(old.copyWith(at: 2).ruleShortName, '');
      expect(old.toJson()['ruleShortName'], '');

      // 脏值（老客户端误写）也不许印出 'null'。
      for (final dirty in <Object?>['null', 'None', 0]) {
        final d = ShareRecord.fromJson(<String, Object?>{
          'id': 'i', 'url': 'u', 'delToken': 't', 'at': 1, 'name': 'n',
          'ruleShortName': dirty,
        });
        expect(d.ruleShortName, isNot('null'), reason: '脏值 $dirty');
        expect(d.ruleShortName, isNot('None'), reason: '脏值 $dirty');
      }

      final described = jsonEncode(rec.describe());
      expect(described, isNot(contains('tok-super-secret')));
      expect(described, contains('"delToken":"****"'));
      expect(described, contains('"ruleShortName":"COC 7th"'));

      // 真实文件后端往返（普通 test 里可用真实 I/O，不是 testWidgets）。
      final dir = await Directory.systemTemp.createTemp('p7_share_badge_');
      try {
        final storage = JsonFileShareStorage(directory: dir);
        final s1 = ShareStore(storage: storage);
        await s1.load();
        await s1.put('cardBadge', rec);
        final s2 = ShareStore(storage: storage);
        await s2.load();
        expect(s2.forCard('cardBadge')?.ruleShortName, 'COC 7th');
        expect(s2.forCard('cardBadge')?.delToken, 'tok-super-secret');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('ShareService.create() 组装记录时经 effectiveId 填入规则简称', () async {
      final store = ShareStore(storage: MemoryShareStorage());
      await store.load();
      final service = ShareService(
        client: harness.FakeShareApi(),
        store: store,
      );
      final c = _card();
      c.raw['ruleSystemId'] = 'dnd5e'; // 未开放占位项 → 收敛回 coc7
      final rec = await service.create(c);
      expect(rec.ruleShortName, 'COC 7th');
      expect(store.forCard('cardBadge')?.ruleShortName, 'COC 7th');
    });
  });

  group('⑥ SharePanel 规则徽标（注入 memory store，零平台动作）', () {
    testWidgets('已分享态：findsOneWidget(share_rule_badge) 且文案含 COC 7th',
        (tester) async {
      final store = await harness.newMemoryShareStore();
      await store.put(
        'cardBadge',
        const ShareRecord(
          id: 'sh_1',
          url: 'https://share.example.com/c/sh_1',
          delToken: 'tok-a',
          at: 1700000000000,
          name: '林晚',
          ruleShortName: 'COC 7th',
        ),
      );
      final share = ShareService(
        client: harness.FakeShareApi(),
        store: store,
      );
      await harness.pumpApp(
        tester,
        share: share,
        home: _host(SharePanel(card: _card())),
      );

      expect(find.byKey(const Key('share_shared')), findsOneWidget);
      expect(find.byKey(const Key('share_rule_badge')), findsOneWidget);
      final badge = tester.widget<Text>(
        find.byKey(const Key('share_rule_badge')),
      );
      expect(badge.data, contains('COC 7th'));
      expect(badge.data, isNot(contains('未标注规则')));
    });

    testWidgets('老记录：如实显示「未标注规则」，不假装是 COC 7th',
        (tester) async {
      final store = await harness.newMemoryShareStore();
      await store.put(
        'cardBadge',
        const ShareRecord(
          id: 'sh_0',
          url: 'https://share.example.com/c/sh_0',
          delToken: 'tok-old',
          at: 1,
          name: '老卡',
        ),
      );
      final share = ShareService(
        client: harness.FakeShareApi(),
        store: store,
      );
      await harness.pumpApp(
        tester,
        share: share,
        home: _host(SharePanel(card: _card())),
      );

      expect(find.byKey(const Key('share_rule_badge')), findsOneWidget);
      final badge = tester.widget<Text>(
        find.byKey(const Key('share_rule_badge')),
      );
      expect(badge.data, contains('未标注规则'));
      expect(badge.data, contains('更新为当前版本'));
      expect(badge.data, isNot(contains('COC 7th')));
    });

    testWidgets('未分享态文案补「链接会带上当前规则标记」，规则名动态取自卡',
        (tester) async {
      final share = ShareService(
        client: harness.FakeShareApi(),
        store: await harness.newMemoryShareStore(),
      );
      await harness.pumpApp(
        tester,
        share: share,
        home: _host(SharePanel(card: _card())),
      );

      expect(find.byKey(const Key('share_unshared')), findsOneWidget);
      final copy = find.textContaining('链接会带上当前规则标记');
      expect(copy, findsOneWidget);
      expect(tester.widget<Text>(copy).data, contains('COC 7th'));
    });
  });
}
