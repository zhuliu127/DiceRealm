// ============================================================
// ai_rp_prompt_test.dart — AI RP 的提示词构造与结果清洗
//
// 为什么要单测 prompt：它决定 AI 输出的质量与**安全性**，
// 但真跑一遍要几十秒、还要花 token，而且模型输出不稳定。
// 纯函数测能钉住的是「我们发出去什么」，这恰恰是最该固定的部分。
//
// 最要紧的一条：**prompt 里绝不能出现 `state.logs`**。
// K3 红线说 logs 的 `p` 可能带明文，拼进 prompt 就等于发给了第三方。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asMap;
import 'package:dice_realm/ui/room/ai_rp_prompt.dart'
    show buildRpMessages, cleanRpText;
import 'package:flutter_test/flutter_test.dart';

/// 一条「我」的成员记录。
Map<String, Object?> _me({
  String name = '林墨',
  String occupation = '记者',
  int? hp = 9,
  int? maxHp = 12,
  int? san = 55,
  String body = '正常',
  List<Object?> mental = const <Object?>[],
}) => <String, Object?>{
  'seat': 'p1',
  'nickname': '甲',
  'sheet': <String, Object?>{
    'name': name,
    'occupation': occupation,
    'status': <String, Object?>{
      'currentHP': hp,
      'maxHP': maxHp,
      'currentSAN': san,
      'body': body,
    },
    'mental': mental,
  },
};

Map<String, Object?> _state({
  String title = '洋馆门厅',
  String desc = '潮湿的地毯，吊灯在轻微摇晃。',
  List<Object?> chats = const <Object?>[],
  List<Object?> logs = const <Object?>[],
}) => <String, Object?>{
  'scene': <String, Object?>{'title': title, 'desc': desc},
  'chats': chats,
  'logs': logs,
};

void main() {
  group('cleanRpText（模型很爱加这四类包装）', () {
    test('★ 去掉「RP：」「角色扮演：」前缀', () {
      expect(cleanRpText('RP：我握紧方向盘'), '我握紧方向盘');
      expect(cleanRpText('rp: 我握紧方向盘'), '我握紧方向盘');
      expect(cleanRpText('角色扮演：我握紧方向盘'), '我握紧方向盘');
    });

    test('★ 去掉代码块围栏（含语言标记）', () {
      expect(cleanRpText('```text\n门后传来低语'), '门后传来低语');
      expect(cleanRpText('```\n门后传来低语\n```'), '门后传来低语');
    });

    test('★ 剥掉整段的外层引号（四种都认）', () {
      expect(cleanRpText('「我推开门」'), '我推开门');
      expect(cleanRpText('“我推开门”'), '我推开门');
      expect(cleanRpText('"我推开门"'), '我推开门');
      expect(cleanRpText("'我推开门'"), '我推开门');
    });

    test('只剥一层，且不碰句子内部的引号', () {
      expect(cleanRpText('他说「别动」，然后转身'), '他说「别动」，然后转身',
          reason: '★ 整段没有被引号包住，内部的引号是正文');
      expect(cleanRpText('「「套两层」」'), '「套两层」',
          reason: '只剥一层，不做贪心处理');
    });

    test('太短的串不剥（避免把「好」这种吃掉引号）', () {
      expect(cleanRpText('「」'), '「」', reason: '长度不足 3，不剥');
    });

    test('null / 空白 → 空串，不抛', () {
      expect(cleanRpText(null), '');
      expect(cleanRpText('   '), '');
      expect(cleanRpText(123), '123');
    });
  });

  group('buildRpMessages（我们发给模型的东西）', () {
    test('★ 返回 system + user 两条', () {
      final m = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(),
        idea: '我想先听听门后有没有动静',
      );
      expect(m.length, 2);
      expect(m[0]['role'], 'system');
      expect(m[1]['role'], 'user');
    });

    test('system 里必须写清三条硬约束（不宣布裁定 / 不写数值 / 只输出正文）', () {
      final sys = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(),
        idea: 'x',
      )[0]['content']!;
      expect(sys.contains('不替守秘人宣布'), isTrue, reason: '不能替 KP 裁定成功失败');
      expect(sys.contains('不写掷骰、数值'), isTrue, reason: 'RP 里不该出现规则术语');
      expect(sys.contains('只输出这段 RP 文字本身'), isTrue,
          reason: '否则会出现「好的，以下是…」这种开场');
      expect(sys.contains('60–180 字'), isTrue, reason: '长度约束');
    });

    test('★ KP 与玩家的 user 首句不同（一个写场景，一个演自己）', () {
      final kp = buildRpMessages(
        isKp: true,
        me: _me(),
        state: _state(),
        idea: '玩家撬锁失败',
      )[1]['content']!;
      final pl = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(),
        idea: '我想撬锁',
      )[1]['content']!;
      expect(kp.startsWith('我是守秘人'), isTrue);
      expect(kp.contains('场景描写'), isTrue);
      expect(pl.startsWith('我是玩家'), isTrue);
      expect(pl.contains('调查员身份'), isTrue);
    });

    test('带上角色底稿：姓名 / 职业 / HP / SAN / 精神状态', () {
      final usr = buildRpMessages(
        isKp: false,
        me: _me(
          name: '林墨',
          occupation: '记者',
          hp: 9,
          maxHp: 12,
          san: 55,
          body: '重伤',
          mental: <Object?>['恐惧', '偏执'],
        ),
        state: _state(),
        idea: '我要开口问路',
      )[1]['content']!;
      expect(usr.contains('林墨'), isTrue);
      expect(usr.contains('记者'), isTrue);
      expect(usr.contains('HP 9/12'), isTrue);
      expect(usr.contains('SAN 55'), isTrue);
      expect(usr.contains('身体：重伤'), isTrue);
      expect(usr.contains('恐惧、偏执'), isTrue);
    });

    test('身体「正常」时不啰嗦（旧版同口径）', () {
      final usr = buildRpMessages(
        isKp: false,
        me: _me(body: '正常'),
        state: _state(),
        idea: 'x',
      )[1]['content']!;
      expect(usr.contains('身体：'), isFalse);
    });

    test('带上场景标题与说明', () {
      final usr = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(title: '洋馆门厅', desc: '潮湿的地毯'),
        idea: 'x',
      )[1]['content']!;
      expect(usr.contains('当前场景：洋馆门厅'), isTrue);
      expect(usr.contains('场景说明：潮湿的地毯'), isTrue);
    });

    test('场景说明超长时截到 200 字（避免 prompt 被一段描述吃满）', () {
      final long = '甲' * 400;
      final usr = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(desc: long),
        idea: 'x',
      )[1]['content']!;
      expect(usr.contains('甲' * 200), isTrue);
      expect(usr.contains('甲' * 201), isFalse, reason: '必须截断');
      expect(usr.contains('…'), isTrue, reason: '截断要有省略号');
    });

    test('★ 最近的桌上对话取最近 5 条（用 chats，不是 logs）', () {
      final chats = <Object?>[
        for (var i = 0; i < 8; i++)
          <String, Object?>{'seat': 'p1', 'text': '第 $i 句聊天'},
      ];
      final usr = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(chats: chats),
        idea: 'x',
      )[1]['content']!;
      expect(usr.contains('第 7 句聊天'), isTrue, reason: '最新的要有');
      expect(usr.contains('第 3 句聊天'), isTrue, reason: '倒数第 5 条也是 5 条之内');
      expect(usr.contains('第 2 句聊天'), isFalse, reason: '第 6 条起不该带上');
      expect(usr.contains('第 0 句聊天'), isFalse);
    });

    test('过短的聊天（≤2 字）被过滤掉，不占上下文', () {
      final usr = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(
          chats: <Object?>[
            <String, Object?>{'text': '嗯'},
            <String, Object?>{'text': '我去看看门后'},
          ],
        ),
        idea: 'x',
      )[1]['content']!;
      expect(usr.contains('我去看看门后'), isTrue);
      expect(usr.contains('· 嗯'), isFalse, reason: '两字以内的闲聊不进上下文');
    });

    test('★★ prompt 里绝不含 logs 的内容（K3 红线）', () {
      // 造一条带明文的 logs —— 如果实现误用了 logs，这里会漏进 prompt。
      final state = _state(
        logs: <Object?>[
          <String, Object?>{
            'text': '秘密检定：林墨 侦查 80 成功',
            'p': <String, Object?>{'secret': true},
          },
        ],
      );
      final usr = buildRpMessages(
        isKp: false,
        me: _me(),
        state: state,
        idea: 'x',
      )[1]['content']!;
      expect(usr.contains('秘密检定'), isFalse,
          reason: '★ logs 可能带明文，拼进 prompt 等于发给第三方（K3）');
      expect(usr.contains('侦查 80'), isFalse);
    });

    test('空 state / 空成员不崩，仍产出可用 prompt', () {
      final m = buildRpMessages(
        isKp: false,
        me: const <String, Object?>{},
        state: const <String, Object?>{},
        idea: '我想坐下',
      );
      expect(m.length, 2);
      expect(m[1]['content']!.contains('我的想法：我想坐下'), isTrue);
    });

    test('想法前后空白被去掉', () {
      final usr = buildRpMessages(
        isKp: false,
        me: _me(),
        state: _state(),
        idea: '   我想坐下   ',
      )[1]['content']!;
      expect(usr.endsWith('我的想法：我想坐下'), isTrue);
    });

    test('sheet 里的 null 值不会印出字面量 "null"（jsStr 那个 bug class）', () {
      final me = <String, Object?>{
        'seat': 'p1',
        'sheet': <String, Object?>{
          'name': null,
          'occupation': null,
          'status': <String, Object?>{'currentHP': null, 'body': null},
          'mental': <Object?>[null, '恐惧'],
        },
      };
      final usr = buildRpMessages(
        isKp: false,
        me: me,
        state: _state(title: '', desc: ''),
        idea: 'x',
      )[1]['content']!;
      expect(usr.contains('null'), isFalse,
          reason: '★ prompt 里出现 null 会让模型照着写出来');
      expect(usr.contains('恐惧'), isTrue);
      // 不该凭空造出「角色姓名：」这种空行
      expect(usr.contains('角色姓名：'), isFalse);
    });

    test('asMap 包装的成员记录也能吃（不要求调用方先 cast）', () {
      final me = asMap(_me());
      final m = buildRpMessages(
        isKp: false,
        me: me,
        state: _state(),
        idea: 'x',
      );
      expect(m[1]['content']!.contains('林墨'), isTrue);
    });
  });
}
