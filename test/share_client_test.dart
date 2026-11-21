// ============================================================
// share_client_test.dart — 云分享的请求 / 响应形状（本地假服务）
//
// 对齐 `core/share.js`：
//   POST {base}/api/cards            body {name, visibility, data} → {id,url,delToken}
//   POST {base}/api/cards/<id>/del   body {token}
//
// 重点断言：
//   · 请求体**只有** name / visibility / data（不含 delToken / aiKey / 头像）
//   · delToken 落到本机记录里，删除时用它；删除成功后本地记录被清
//   · 未配置 shareBase → **一个请求都不发**，直接 unconfigured
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/net/share_client.dart';
import 'package:dice_realm/repo/share_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http.dart';

Character sampleCard() {
  final c = Character(newCharacter());
  c.raw['id'] = 'cardA';
  c.raw['characterName'] = '林晚';
  c.raw['playerName'] = '老王';
  c.basicInfo['occupationName'] = '记者';
  c.attributes['str'] = 55;
  c.raw['shareVisibility'] = 'link';
  c.raw['avatar'] = 'data:image/svg+xml;charset=utf-8,AAAABBBBCCCC%20huge';
  c.raw['skills'] = <Object?>[
    <String, Object?>{
      'key': 'spot::',
      'id': 'spot',
      'name': '侦查',
      'sub': '',
      'base': 25,
      'growth': 0,
      'occ': 40,
      'int': 0,
      'total': 65,
      'custom': false,
      'desc': '很长的描述不该上传',
    },
  ];
  c.raw['weapons'] = <Object?>[
    <String, Object?>{
      'name': '小刀',
      'skill': '斗殴',
      'damage': '1D4',
      'range': '接触',
      'ammo': '—',
    },
  ];
  c.raw['items'] = <Object?>[
    <String, Object?>{'name': '手电筒', 'quantity': 1, 'description': ''},
  ];
  return c;
}

void main() {
  late FakeServer server;
  late ShareStore store;
  late ShareService service;

  setUp(() async {
    server = await FakeServer.start();
    store = ShareStore(storage: MemoryShareStorage());
    await store.load();
    service = ShareService(
      client: ShareClient(baseProvider: () => server.base),
      store: store,
    );
  });

  tearDown(() async {
    await server.close();
  });

  group('创建分享', () {
    test('请求形状 {name, visibility, data}；响应落成本机记录', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, <String, Object?>{
            'id': 'sh_1',
            'url': 'https://share.example.com/c/sh_1',
            'delToken': 'tok-abcdef',
          });

      final c = sampleCard();
      final rec = await service.create(c);

      expect(rec.id, 'sh_1');
      expect(rec.url, 'https://share.example.com/c/sh_1');
      expect(rec.delToken, 'tok-abcdef');
      expect(rec.name, '林晚');
      expect(c.raw['shareId'], 'sh_1');

      // 本地记录
      expect(store.forCard('cardA')?.id, 'sh_1');
      expect(store.forCard('cardA')?.delToken, 'tok-abcdef');

      // 请求
      expect(server.requests, hasLength(1));
      final req = server.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/v1/api/cards'); // server.base 带 /v1，路径就跟着走
      final body = req.json;
      expect(body.keys.toSet(), <String>{'name', 'visibility', 'data'});
      expect(body['name'], '林晚');
      expect(body['visibility'], 'link');

      final data = (body['data'] as Map).cast<String, Object?>();
      expect(data['characterName'], '林晚');
      expect(data['playerName'], '老王');
      expect(data['attributes'], isA<Map>());
      expect(data['unitName'], '记者');
      expect(data['sharedAt'], isA<int>());
      // 技能是精简视图：只有 6 个键，且没有 desc / key
      final skills = (data['skills'] as List).cast<Map>();
      expect(skills, hasLength(1));
      expect(skills.first.keys.toSet(), <String>{
        'name',
        'total',
        'base',
        'occ',
        'int',
        'growth',
      });
      // 头像不上传（体积大、服务端不展示）
      expect(jsonEncode(body), isNot(contains('AAAABBBBCCCC')));
      // delToken 绝不出现在请求里
      expect(jsonEncode(body), isNot(contains('tok-abcdef')));
    });

    test('服务端回 409 → http 错误，带状态码，不写本地记录', () async {
      server.responder = (req, cap) async =>
          FakeServer.text(req, 409, 'conflict');
      try {
        await service.create(sampleCard());
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.http);
        expect(e.message, contains('409'));
      }
      expect(store.forCard('cardA'), isNull);
    });

    test('服务端回 500 → http 错误', () async {
      server.responder = (req, cap) async => FakeServer.text(req, 500, 'boom');
      try {
        await service.create(sampleCard());
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.http);
        expect(e.message, contains('500'));
      }
    });

    test('返回不是 JSON / 缺字段 → badResponse', () async {
      server.responder = (req, cap) async =>
          FakeServer.text(req, 200, 'ok', type: 'text/plain');
      try {
        await service.create(sampleCard());
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.badResponse);
      }

      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, <String, Object?>{'id': 'x'});
      try {
        await service.create(sampleCard());
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.badResponse);
        expect(e.message, contains('id / url'));
      }
    });

    test('网络断（服务已关）→ unreachable', () async {
      final dead = server.base;
      await server.close();
      final s2 = ShareService(
        client: ShareClient(baseProvider: () => dead),
        store: store,
      );
      try {
        await s2.create(sampleCard());
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.unreachable);
      }
      server = await FakeServer.start();
    });
  });

  group('删除分享', () {
    test('用本机 delToken 发删除；成功后本地记录被清', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, <String, Object?>{
            'id': 'sh_1',
            'url': 'https://share.example.com/c/sh_1',
            'delToken': 'tok-abcdef',
          });
      await service.create(sampleCard());
      expect(store.forCard('cardA'), isNotNull);

      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, <String, Object?>{'ok': true});
      await service.remove('cardA');

      final del = server.requests.last;
      expect(del.path, '/v1/api/cards/sh_1/del');
      expect(del.json['token'], 'tok-abcdef');
      expect(store.forCard('cardA'), isNull, reason: '删除后本地记录必须清掉');
    });

    test('服务端拒绝删除（token 错）→ 抛错且**保留**本地记录（还能重试）', () async {
      server.responder = (req, cap) async => FakeServer.json(
        req,
        200,
        <String, Object?>{'id': 'sh_1', 'url': 'u', 'delToken': 'tok'},
      );
      await service.create(sampleCard());

      server.responder = (req, cap) async =>
          FakeServer.text(req, 403, 'bad token');
      try {
        await service.remove('cardA');
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.http);
      }
      expect(store.forCard('cardA'), isNotNull, reason: '删不掉就别把记录丢了，否则再也删不了');
    });

    test('本机没有记录 → noRecord', () async {
      try {
        await service.remove('nope');
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.noRecord);
      }
    });
  });

  group('未配置 shareBase（硬约束：不发请求、不静默失败）', () {
    test('create / remove 都直接 unconfigured，且一个请求都不发', () async {
      final s = ShareService(
        client: ShareClient(baseProvider: () => ''),
        store: store,
      );
      expect(s.configured, isFalse);

      try {
        await s.create(sampleCard());
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.unconfigured);
      }
      expect(server.requests, isEmpty, reason: '未配置时绝不能发请求');

      // 有记录但地址被清空：删除同样拒绝
      server.responder = (req, cap) async => FakeServer.json(
        req,
        200,
        <String, Object?>{'id': 'x', 'url': 'u', 'delToken': 't'},
      );
      await service.create(sampleCard());
      server.requests.clear();
      try {
        await s.remove('cardA');
        fail('应该抛');
      } on ShareException catch (e) {
        expect(e.kind, ShareErrorKind.unconfigured);
      }
      expect(server.requests, isEmpty);
    });

    test('地址规范化 / 有效性判断', () {
      expect(normalizeShareBase(' https://a.com/coc/// '), 'https://a.com/coc');
      expect(looksValidShareBase('https://a.com/coc'), isTrue);
      expect(looksValidShareBase('http://a.com'), isTrue);
      expect(looksValidShareBase('a.com'), isFalse);
      expect(looksValidShareBase(''), isFalse);
    });
  });

  group('delToken 只在本机（硬约束）', () {
    test('record.describe() 不含口令原文', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 200, <String, Object?>{
            'id': 'sh_1',
            'url': 'u',
            'delToken': 'tok-super-secret',
          });
      final rec = await service.create(sampleCard());
      expect(rec.delToken, 'tok-super-secret');
      expect(jsonEncode(rec.describe()), isNot(contains('tok-super-secret')));
    });

    test('分享请求体里不含 aiKey（设置里的 Key 与分享无关）', () async {
      server.responder = (req, cap) async => FakeServer.json(
        req,
        200,
        <String, Object?>{'id': 'i', 'url': 'u', 'delToken': 't'},
      );
      final c = sampleCard();
      c.raw['aiKey'] = 'sk-should-never-upload';
      await service.create(c);
      expect(
        jsonEncode(server.requests.single.json),
        isNot(contains('sk-should-never-upload')),
      );
    });
  });
}
