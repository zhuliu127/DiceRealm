// ============================================================
// ai_name_land_test.dart — 姓名落地策略（v2.46.0）
//
// 产品行为真变：AI 车卡的姓名从「本地姓名池纠偏」改回「完全由模型生成」：
//   · 玩家在描述里指定的姓名（如「车一个华强买瓜里面的刘华强」→ 刘华强）
//     必须原样落地成卡，不得被本地池覆盖；
//   · 模型自拟姓名同样原样保留（多样性由提示词约束）；
//   · 本地只在**名字为空**时用 randomInvestigatorName 兜底。
// 对应实现：net/ai_create.dart#_land（不再调用已删除的
// ensureFreshInvestigatorName）。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/net/ai_client.dart';
import 'package:dice_realm/net/ai_create.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http.dart';
import 'support/oracle.dart';

const String kKey = 'sk-name-0123456789abcdef';

void main() {
  late FakeServer server;

  // 全局随机源 / 时钟是可变全局：每个用例前快照、用例后还原（同 ai_flow_test）
  late JsRng savedRng;
  late JsClock savedClock;
  late bool savedUid;

  setUp(() async {
    savedRng = nowRng;
    savedClock = nowClock;
    savedUid = uidDeterministic;
    setRng(Lcg(20261108).call);
    server = await FakeServer.start();
  });

  tearDown(() async {
    setRng(savedRng);
    setClock(savedClock);
    uidDeterministic = savedUid;
    await server.close();
  });

  AiCreateService service() {
    final client = AiClient(
      configProvider: () => AiConfig(base: server.base, model: 'm', key: kKey),
    );
    return AiCreateService(
      client: client,
      capsProvider: () => const AiCaps(),
    );
  }

  /// 让服务端固定回一段文本
  void reply(String content) {
    server.responder = (req, cap) async =>
        FakeServer.json(req, 200, chatOk(content));
  }

  group('姓名落地策略（完全采信模型，空名才兜底）', () {
    test('★ 模型给 name=刘华强 → 原样落地成卡，不被本地池覆盖', () async {
      reply(jsonEncode(<String, Object?>{'name': '刘华强'}));
      final r = await service().makeCharacter('车一个华强买瓜里面的刘华强');
      expect(r.profile['name'], '刘华强',
          reason: '★ 玩家指定的姓名必须原样保留在 profile');
      expect(r.character.raw['characterName'], '刘华强',
          reason: '★ 玩家指定的姓名必须原样落地成卡（QA 案例：不能变成「岳振山」）');
    });

    test('★ 模型给模型自拟的正常姓名 → 原样保留，连续同名也不再被换掉', () async {
      reply(jsonEncode(<String, Object?>{'name': '岳振山'}));
      final r1 = await service().makeCharacter('一个老刑警');
      expect(r1.character.raw['characterName'], '岳振山',
          reason: '★ 模型自拟姓名应原样保留（本地不再纠偏）');

      // 纠偏删除后：连续两次同名必须原样保留
      reply(jsonEncode(<String, Object?>{'name': '岳振山'}));
      final r2 = await service().makeCharacter('一个老刑警');
      expect(r2.character.raw['characterName'], '岳振山',
          reason: '★ 连续同名必须原样保留（v2.39.0 的跨调用去重已随纠偏一起删除）');
    });

    test('★ 模型给空名 → 兜底成 randomInvestigatorName 的非空中文姓名', () async {
      reply(jsonEncode(<String, Object?>{'name': ''}));
      final r = await service().makeCharacter('描述');
      final n = r.profile['name'] as String;
      expect(n.trim(), isNotEmpty, reason: '★ 空名必须被兜底，不能落地空名');
      expect(RegExp(r'^[\u4e00-\u9fa5]{2,4}$').hasMatch(n), isTrue,
          reason: '兜底名必须来自本地中文姓名池（2-4 汉字）：$n');
      expect(r.character.raw['characterName'], n,
          reason: '★ 兜底名要一路落进卡里');
    });

    test('★ 模型给全空 JSON（连 name 字段都没有）→ 同样兜底非空姓名', () async {
      reply('{}');
      final r = await service().makeCharacter('描述');
      final n = r.profile['name'] as String;
      expect(n.trim(), isNotEmpty, reason: '★ 缺 name 字段也必须兜底');
      expect(r.character.raw['characterName'], isNotEmpty);
    });
  });
}
