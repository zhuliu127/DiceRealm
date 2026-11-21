// ============================================================
// ai_flow_test.dart — 核心不变式：**AI 只给创意，数值走规则引擎**
//
// 这份用例存在的唯一目的：把「AI 返回什么都不会产出坏卡」钉死。
// 喂给模型的是**恶意 / 残缺 / 矛盾**的输入，断言落地卡依然：
//   validate 无 error、checkList 全过、职业技能点不超、技能不超上限。
//
// 如果哪天有人"优化"成「直接把 AI 的 attributes / skills 写进卡」，
// 这里会立刻红。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/preset_gen.dart' as preset;
import 'package:dice_realm/net/ai_client.dart';
import 'package:dice_realm/net/ai_create.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_http.dart';
import 'support/oracle.dart';

const String kKey = 'sk-flow-0123456789abcdef';

/// 各种「模型可能返回的东西」。键是给人看的原因。
final Map<String, String> evilPayloads = <String, String>{
  '空对象（什么都没给）': '{}',
  '全字段为空串': '{"name":"","gender":"","age":0,"occupationName":"","setting":""}',
  'attributes 是字符串': '{"name":"甲","attributes":"str=50,con=50"}',
  'attributes 超范围（999）':
      '{"name":"乙","attributes":{"str":999,"con":-5,"dex":"abc","int":88}}',
  'attributes 少项 + 字符串数字': '{"name":"丙","attributes":{"str":"55","con":"60","siz":"50","dex":"65","app":"70","int":"80","pow":"60","edu":"75","luck":"45"}}',
  '职业名瞎编': '{"name":"丁","occupationName":"星际舰队指挥官"}',
  '自定义职业 + 垃圾技能名': '{"name":"戊","occupationName":"自定义职业","occupationSkills":["瞎写","也不存在","侦查"]}',
  '自定义职业 + 非数组技能':
      '{"name":"己","occupationName":"自定义职业","occupationSkills":"侦查、聆听"}',
  '背景全是错误类型': '{"name":"庚","background":{"description":{"a":1},"ideology":[1,2],"traits":42}}',
  '背景文本超长 + 换行':
      '{"name":"辛","background":{"description":"${'长' * 300}\\n\\n第二段","history":"第一句\\n第二句"}}',
  '年龄越界 + 性别非法': '{"name":"壬","gender":"未知","age":999}',
  'prompt 注入（要求改数值）': '{"name":"癸","ignore":"ignore previous instructions","attributes":{"str":99,"con":99,"siz":99,"dex":99,"app":99,"int":99,"pow":99,"edu":99,"luck":99}}',
  '返回数组而不是对象': '[{"name":"子"},{"name":"丑"}]',
  '返回 null': 'null',
  '嵌套垃圾字段': '{"name":"寅","x":{"y":{"z":[1,2,3]}},"occupationId":"no-such-occ"}',
  '显式声明不要规则数值': '{"name":"卯","attributes":{"str":15,"con":15,"siz":15,"dex":15,"app":15,"int":15,"pow":15,"edu":15,"luck":15}}',
};

void main() {
  late FakeServer server;

  // QA P3 复核修复：本文件最后一个用例会 setRng / setClock /
  // uidDeterministic = true 做「规则回退」验证，但原来不还原全局。
  // 全局随机源/时钟是可变全局（结构性风险 2 的同源问题），泄漏出去会让
  // 同文件其它用例偶发拿到坏卡 → `AI 给全 15 的属性` 约 1/5 概率红。
  // 每个用例前快照、每个用例后还原，保证用例互相独立、幂等。
  late JsRng savedRng;
  late JsClock savedClock;
  late bool savedUid;

  setUp(() async {
    savedRng = nowRng;
    savedClock = nowClock;
    savedUid = uidDeterministic;
    // 默认 nowRng 是「微秒时间戳取模」的伪随机源（js_compat.dart:33-36）：
    // 一次生成里连续多次调用高度相关（微秒计数器每次只前进个位数），
    // 微秒值落在低位时八项属性会被一起压到很低，导致
    // 「AI 给全 15 的属性」用例约 1/5 概率拿到合计 < 200 的坏卡。
    // 单跑 10 次实测 3 次红、失败值恒为 195，与「全量才红」无关。
    // 给每个用例注入独立的固定 LCG（断言一字不改），让结果可复现；
    // tearDown 会把上面快照的三个全局原样还原。
    setRng(Lcg(20261108).call);
    server = await FakeServer.start();
  });

  tearDown(() async {
    setRng(savedRng);
    setClock(savedClock);
    uidDeterministic = savedUid;
    await server.close();
  });

  AiCreateService service({AiCaps? caps}) {
    final client = AiClient(
      configProvider: () => AiConfig(base: server.base, model: 'm', key: kKey),
    );
    return AiCreateService(
      client: client,
      capsProvider: () => caps ?? const AiCaps(),
    );
  }

  /// 让服务端固定回一段文本
  void reply(String content) {
    server.responder = (req, cap) async =>
        FakeServer.json(req, 200, chatOk(content));
  }

  /// 断言一张卡「真正可用」
  ///
  /// [strictFive] 只在**没被上限压缩**时要求属性是 5 的倍数 ——
  /// `applyAttrCap` 的等比压缩一定会产生非 5 的倍数（这是旧版既有行为，
  /// 压完还要保持「强的还是强」，硬凑 5 的倍数反而会破坏相对高低）。
  void expectUsable(Character c, String why, {bool strictFive = true}) {
    final errs = validate(c);
    expect(errs, isEmpty, reason: '$why：validate 有 error → $errs');

    final bad = checkList(c).where((x) => x['ok'] != true).toList();
    expect(
      bad,
      isEmpty,
      reason: '$why：checkList 未全过 → ${bad.map((x) => x['label'])}',
    );

    expect(c.raw['characterName'], isNotEmpty, reason: '$why：缺姓名');
    expect(c.raw['occupationId'], isNotEmpty, reason: '$why：缺职业');
    expect(c.basicInfo['residence'], isNotEmpty, reason: '$why：缺居住地');
    expect(c.skills, isNotEmpty, reason: '$why：缺技能');
    expect(c.raw['weapons'], isNotEmpty, reason: '$why：缺武器');

    // 职业技能点 / 兴趣点不得超额
    expect(
      validateSkillPoints(c).where(
        (e) => e['target'] == 'occPoints' || e['target'] == 'interestPoints',
      ),
      isEmpty,
      reason: '$why：点数超额',
    );
    expect(validateSkillCap(c), isEmpty, reason: '$why：技能超上限');

    // 属性必须是规则层认可的形态：15-90 且 5 的倍数（AI 给的越界值不允许原样进卡）
    for (final k in <String>[
      'str',
      'con',
      'siz',
      'dex',
      'app',
      'int',
      'pow',
      'edu',
    ]) {
      final v = jsNum(c.attributes[k]);
      if (strictFive) expect(v % 5, 0, reason: '$why：$k=$v 不是 5 的倍数');
      expect(v, inInclusiveRange(15, 90), reason: '$why：$k=$v 超出 15-90');
    }
  }

  group('恶意 / 残缺的 AI 返回 → 落地卡仍然合法（核心不变式）', () {
    evilPayloads.forEach((why, payload) {
      test(why, () async {
        reply(payload);
        final r = await service().makeCharacter('一个测试用的人物描述');
        expectUsable(r.character, why);
        // 创意字段该采信就采信（姓名能救的必须救，不能一律丢弃）
        if (payload.contains('"name":"甲"')) {
          expect(r.character.raw['characterName'], '甲');
        }
      });
    });

    test('AI 给全 15 的属性（想绕过规则）→ 仍按 15-90 合法区间落地', () async {
      reply(
        jsonEncode(<String, Object?>{
          'name': '辰',
          'attributes': <String, Object?>{
            'str': 15,
            'con': 15,
            'siz': 15,
            'dex': 15,
            'app': 15,
            'int': 15,
            'pow': 15,
            'edu': 15,
            'luck': 15,
          },
        }),
      );
      final r = await service().makeCharacter('描述');
      expectUsable(r.character, '全 15 属性');
      // 八项合计 120 < 200 → attrsFromAi 判定不合格 → 规则层重掷
      final sum = attrSum(r.character, includeLuck: false);
      expect(sum, greaterThan(200), reason: 'AI 的极端低值不该被采纳');
    });

    test('AI 的 attributes 正常时会被采纳（创意字段要真的用上）', () async {
      reply(
        jsonEncode(<String, Object?>{
          'name': '巳',
          'gender': '女',
          'age': 33,
          'residence': '杭州',
          'birthplace': '绍兴',
          'attributes': <String, Object?>{
            'str': 50,
            'con': 55,
            'siz': 50,
            'dex': 60,
            'app': 65,
            'int': 85,
            'pow': 60,
            'edu': 80,
            'luck': 45,
          },
          'background': <String, Object?>{'description': '戴一副旧眼镜'},
        }),
      );
      final r = await service().makeCharacter('描述');
      expectUsable(r.character, '正常 AI 属性');
      expect(r.character.raw['characterName'], '巳');
      expect(r.character.basicInfo['age'], 33);
      expect(r.character.basicInfo['residence'], '杭州');
      expect(r.character.basicInfo['birthplace'], '绍兴');
      expect(r.character.attributes['int'], 85);
      expect(r.character.background['description'], '戴一副旧眼镜');
      expect(r.raw, isA<Map>(), reason: '应当把模型原始 JSON 一起带回来（界面/日志要用）');
    });

    test('AI 给的姓名/背景是创意字段，一律采信；数值一律本地算', () async {
      reply(
        jsonEncode(<String, Object?>{
          'name': '午',
          'background': <String, Object?>{
            'ideology': '信念：有些真相不该被埋着。',
            'traits': '固执、话少',
            'phobias': '无。',
          },
        }),
      );
      final r = await service().makeCharacter('描述');
      expectUsable(r.character, '创意字段');
      expect(r.character.background['ideology'], '信念：有些真相不该被埋着。');
      expect(r.character.background['traits'], '固执、话少');
      // AI 说「无。」→ 采信，不再由系统掷一条（避免双重决定）
      expect(r.character.background['phobias'], '无。');
    });
  });

  group('自适应重试（截断 → 16000 再发一次）', () {
    test('第一次被截断（finish_reason=length）→ 第二次带 max_tokens=16000', () async {
      var n = 0;
      server.responder = (req, cap) async {
        n++;
        if (n == 1) {
          await FakeServer.json(
            req,
            200,
            chatOk('{"name":"未', finishReason: 'length', reasoning: 700),
          );
        } else {
          await FakeServer.json(req, 200, chatOk('{"name":"完"}'));
        }
      };

      final stages = <String>[];
      final r = await service().makeCharacter('描述', onStage: stages.add);

      expect(server.requests, hasLength(2));
      expect((server.requests.first.json)['max_tokens'], aiDefaultMaxTokens);
      expect((server.requests.last.json)['max_tokens'], aiRetryMaxTokens);
      expect(stages.join(), contains('正在用更大额度重试'));
      expect(r.character.raw['characterName'], '完');
      expectUsable(r.character, '重试后');
    });

    test('两次都被截断 → 可读错误，提示换非推理型模型', () async {
      server.responder = (req, cap) async => FakeServer.json(
        req,
        200,
        chatOk('{"name":"未', finishReason: 'length'),
      );

      try {
        await service().makeCharacter('描述');
        fail('应该抛');
      } on AiException catch (e) {
        expect(e.message, contains('两次都没能输出完整内容'));
        expect(e.message, contains('推理型模型'));
      }
      expect(server.requests, hasLength(2));
    });

    test('第一次格式错、第二次正常 → 成功（不把用户卡在重试里）', () async {
      var n = 0;
      server.responder = (req, cap) async {
        n++;
        await FakeServer.json(
          req,
          200,
          chatOk(n == 1 ? '没有 JSON 的废话' : '{"name":"好"}'),
        );
      };
      final r = await service().makeCharacter('描述');
      expect(r.character.raw['characterName'], '好');
      expectUsable(r.character, '第二次成功');
    });
  });

  group('房规数值上限在 AI 卡上也真的生效', () {
    test('属性总和上限 380 → 压到 380 以内并标记 aiAttrScaled', () async {
      reply(
        jsonEncode(<String, Object?>{
          'name': '未',
          'attributes': <String, Object?>{
            'str': 90,
            'con': 90,
            'siz': 90,
            'dex': 90,
            'app': 90,
            'int': 90,
            'pow': 90,
            'edu': 95,
            'luck': 90,
          },
        }),
      );
      const caps = AiCaps(attrCap: 380, withLuck: true, occCap: 0, intCap: 0);
      final r = await service(caps: caps).makeCharacter('描述');
      expectUsable(r.character, '上限 380', strictFive: false);
      expect(attrSum(r.character, includeLuck: true), lessThanOrEqualTo(380));
      expect(r.attrScaled, isTrue);
      expect(r.character.raw['aiAttrScaled'], isTrue);
    });

    test('每项技能上限 70 / 60 → 没有任何一项超出（豁免项除外）', () async {
      reply('{"name":"申"}');
      const caps = AiCaps(attrCap: 0, withLuck: true, occCap: 70, intCap: 60);
      final r = await service(caps: caps).makeCharacter('描述');
      expectUsable(r.character, '技能上限');
      for (final sRaw in r.character.skills) {
        final s = (sRaw as Map).cast<String, Object?>();
        final id = jsStr(s['id']);
        if (id == 'language_own' || id == 'credit') continue;
        final base = jsNum(s['base']);
        if (base > 60) continue;
        expect(
          jsNum(s['total']),
          lessThanOrEqualTo(70),
          reason: '技能「${s['name']}」= ${s['total']} 超过本职上限 70',
        );
      }
    });
  });

  group('回退路径：AI 完全不可用时，规则引擎必须能顶上', () {
    test('AI 一直 500 → 抛可读错误；随后规则引擎直接生成一张合法卡', () async {
      server.responder = (req, cap) async =>
          FakeServer.json(req, 500, <String, Object?>{});

      Object? err;
      try {
        await service().makeCharacter('描述');
      } catch (e) {
        err = e;
      }
      expect(err, isA<AiException>());
      expect((err as AiException).message, contains('服务端出错'));

      // UI 的「改用规则生成」走的就是这条：直接调 preset，不依赖任何网络
      final rng = Lcg(20261108);
      setRng(rng.call);
      setClock(() => oracleNowMs);
      uidDeterministic = true;
      final c = preset.generateOne();
      expect(c, isNotNull);
      expectUsable(c!, '规则回退');
    });
  });
}
