// ============================================================
// test/p10_t3_broadcast_potential_png_test.dart — P10 第 3 期 A 批
//
// 三块一张测试文件（按 team-lead 的 A / B / C 顺序）：
//   A. 互动信息广播：roll 点 / 检定结果 / SAN Check 必须**在别的会话视角里
//      看得见**；暗骰 / 秘密检定**绝不能**出现在别人视角（K3 红线）。
//   B. 「潜在疯狂」↔ 老 APP「不定疯狂（症状消失）」：回合边界 disarm 语义。
//   C. 自动头像 PNG 化：与 SVG 同源、长度 ≤ 20000、老卡 SVG 不炸。
//
// ★ 铁律 T1：全部走内存替身（`roomHostOpts()` 的 LCG / 内存存档 /
//   确定性规则），零真实 I/O、零 Timer、零 Future.delayed、零 AnimationController。
// ★ 跨视角用**两个真实 RoomClient**：权威端产出的 `SendPlan` 各喂一份给
//   p1 / p2 的 client，断言的是「另一个会话视角收到的 state」，
//   而不是「权威端 state 里有这条」—— 后者证明不了广播。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/avatar.dart' as avatar;
import 'package:dice_realm/domain/avatar_uri.dart'
    show avatarDataUriBytes, roomAvatarDataUri;
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/ui/room/sheets/card_sheet_payload.dart'
    show cardToRoomSheetForReport;
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/view/feed_view.dart'
    show FeedKind, collectFeeds, diceLine;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart' show FeedRow;
import 'package:dice_realm/repo/avatar_thumb.dart' show avatarThumbEncoder;
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

// ------------------------------------------------------------
// 公共脚手架：一个 KP + 两张有卡的角色
// ------------------------------------------------------------

RoomHost _host() {
  final h = RoomHost(roomHostOpts(seed: 13));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  h.roster.get('p1')!['sheet'] = <String, Object?>{
    'name': '甲',
    'status': <String, Object?>{
      'currentHP': 10,
      'maxHP': 10,
      'currentSAN': 50,
      'maxSAN': 60,
      'body': '正常',
    },
    'mental': <Object?>['正常'],
    'madness': <Object?>[],
    'tempStatus': <Object?>[],
    'skills': <Object?>[
      <String, Object?>{'name': '侦查', 'base': 60},
    ],
  };
  return h;
}

/// 把一批 [SendPlan] 按「收件人」投递给对应视角的 client。
///
/// 这是**真实链路**的等价物：权威端 plan → 中继按 `to` 分发 → 客户端
/// `receive()` → reduce。`'*'` 代表全员。
void _deliver(
  List<SendPlan> plans,
  Map<String, RoomClient> clients,
) {
  for (final p in plans) {
    if (p.to == '*') {
      for (final c in clients.values) {
        c.receive(p.msg.toJson());
      }
    } else {
      final c = clients[p.to];
      if (c != null) c.receive(p.msg.toJson());
    }
  }
}

Map<String, RoomClient> _clients() => <String, RoomClient>{
      'p1': RoomClient(seat: 'p1'),
      'p2': RoomClient(seat: 'p2'),
    };

/// 两个视角都先吃一份全量 sync，序号水位对齐，后续增量才不会被判成跳号。
void _boot(RoomHost h, Map<String, RoomClient> cs) {
  for (final e in cs.entries) {
    e.value.receive(h.syncFor(e.key).toJson());
  }
}

Map<String, Object?> _act(String op, Map<String, Object?> p) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

void main() {
  // ==========================================================
  // A. 互动信息广播（用户点名第 3 项）
  // ==========================================================
  group('A · 互动信息广播：另一个会话视角必须看得见', () {
    testWidgets('A1 普通 roll 点（快捷骰 1D6）：p2 视角收到，且记录栏看得出是谁掷的',
        (WidgetTester tester) async {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);

      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{'expr': '1D6', 'direct': true},
      });
      _deliver(plans, cs);

      // —— 跨视角：p2 的 state.dice 里有这条（不是「权威端有」）——
      final p2Dice = asList(cs['p2']!.state['dice']);
      expect(p2Dice, hasLength(1), reason: 'roll 点必须广播到其他玩家');
      final row = asMap(p2Dice.single);
      expect(jsStr(row['seat']), 'p1');
      expect(jsStr(row['nickname']), '甲');
      expect(jsStr(row['expr']), '1D6');
      expect(row.containsKey('total'), isTrue);

      // —— 呈现：记录栏（state.dice → collectFeeds）里这一条带发言人 ——
      final feeds = collectFeeds(cs['p2']!.state);
      final diceItems = feeds.where((f) => f.kind == FeedKind.dice).toList();
      expect(diceItems, hasLength(1));
      expect(diceItems.single.seat, 'p1');
      expect(diceItems.single.nickname, '甲',
          reason: 'FeedItem 必须带昵称，FeedRow 靠它印「甲：」');

      // —— 真渲染一遍，确认「甲：」与骰值都画出来了 ——
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: FeedRow(item: diceItems.single)),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final rendered = _texts(tester).join('\n');
      expect(rendered.contains('甲：'), isTrue,
          reason: '改前记录栏只在聊天栏印发言人，骰行是一堆匿名数字');
      expect(rendered.contains('1D6 →'), isTrue);
    });

    testWidgets('A2 技能检定：结果行带技能名 + 成功等级，p2 视角可见',
        (WidgetTester tester) async {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);

      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'direct': true,
          'skill': '侦查',
          'label': '侦查',
        },
      });
      _deliver(plans, cs);

      final p2Dice = asList(cs['p2']!.state['dice']);
      expect(p2Dice, hasLength(1), reason: '检定结果必须广播到其他玩家');
      final row = asMap(p2Dice.single);
      expect(jsStr(row['label']), '侦查', reason: '结构里必须带技能名');
      expect(jsStr(row['levelText']).isNotEmpty, isTrue, reason: '必须带成功等级');

      // 呈现层：diceLine 要把技能名印出来（改前只剩「1D100 → xx」）
      final line = diceLine(row);
      expect(line.startsWith('侦查：'), isTrue, reason: '改前看不到检定的是什么技能');
      expect(line.contains('1D100 →'), isTrue);

      // 记录栏真渲染
      final feeds = collectFeeds(cs['p2']!.state)
          .where((f) => f.kind == FeedKind.dice)
          .toList();
      expect(feeds, hasLength(1));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: FeedRow(item: feeds.single)),
      ));
      await tester.pump();
      final rendered = _texts(tester).join('\n');
      expect(rendered.contains('侦查：'), isTrue);
      expect(rendered.contains('甲：'), isTrue);
    });

    test('A3 SAN Check：掷骰 + 结算说明都进 p2 视角的公共记录', () {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);

      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.sanCheck,
        'p': <String, Object?>{'okLoss': '0', 'loss': '1D6'},
      });
      _deliver(plans, cs);

      final p2 = cs['p2']!;
      // ① 骰：SAN Check 的那一颗
      final labels = asList(p2.state['dice'])
          .map((e) => jsStr(asMap(e)['label']))
          .toList();
      expect(labels.any((l) => l.startsWith('SAN Check')), isTrue,
          reason: 'SAN Check 的骰点必须广播');

      // ② 公共记录：一条 kind=='check' 的结算说明
      final checks = asList(p2.state['logs'])
          .map(asMap)
          .where((l) => jsStr(l['kind']) == 'check')
          .toList();
      expect(checks, isNotEmpty, reason: 'SAN Check 结算必须进公共记录');
      final text = checks.map((l) => jsStr(l['text'])).join('\n');
      expect(text.contains('SAN Check'), isTrue);
      expect(text.contains('甲'), isTrue);
      // 「理智损失」或「无理智损失」二者必居其一 —— 玩家必须看得出 SAN 变化
      expect(text.contains('理智损失'), isTrue, reason: '要能看出损失');
    });

    test('A4 反向：暗骰（secret）**不得**出现在别人视角（K3）', () {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);

      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{'expr': '1D100', 'direct': true, 'secret': true},
      });
      _deliver(plans, cs);

      final p2 = cs['p2']!;
      // ① p2 的公开骰列里没有这条
      expect(asList(p2.state['dice']), isEmpty,
          reason: '暗骰是 SEAT 口径，公共骰列必须为空');
      // ② p2 的公共记录只有脱敏提示，不含骰值
      final texts = asList(p2.state['logs'])
          .map((e) => jsStr(asMap(e)['text']))
          .join('\n');
      expect(texts.contains('暗骰了一次'), isTrue);
      expect(texts.contains('只有他/她与 KP 可见'), isTrue);
      // ③ p2 没有收到任何私密内容（完整结果是发给本人与 KP 的）
      expect(asList(p2.state['privates']), isEmpty,
          reason: '暗骰完整结果只发给本人与 KP');

      // ④ 本人与 KP 两边都看得到（不是「谁都没收到」）
      expect(asList(cs['p1']!.state['privates']), hasLength(1));
      expect(asList(h.syncFor(kHostSeat).state['privates']), hasLength(1));
    });

    test('A5 反向：KP 秘密检定（check.opposed secret）不泄漏结果', () {
      final h = _host();
      final cs = _clients();
      _boot(h, cs);

      final plans = h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
        'secret': true,
        'a': <String, Object?>{'side': 'pc', 'seat': 'p1', 'skill': '侦查'},
        'b': <String, Object?>{'side': 'monster', 'name': '怪', 'value': 40},
      }));
      _deliver(plans, cs);

      final p2 = cs['p2']!;
      final p2Logs = asList(p2.state['logs'])
          .map((e) => asMap(e))
          .where((l) => jsStr(l['kind']) == 'check')
          .toList();
      // 只允许一条脱敏行；不得出现 summary / 胜负 / 骰值
      for (final l in p2Logs) {
        expect(jsTruthy(l['redacted']), isTrue,
            reason: '秘密检定在公共记录里必须是脱敏行');
        expect(jsStr(l['text']).contains('胜'), isFalse);
      }
      expect(asList(p2.state['dice']), isEmpty);
    });
  });

  // ==========================================================
  // B. 「潜在疯狂」↔「不定疯狂（症状消失）」
  // ==========================================================
  group('B · 潜在疯狂：回合边界 disarm 与新旧取值兼容', () {
    test('B1 仍处「潜在疯狂」的座位在回合推进时被 disarm（fadedArm=false）', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        ...asMap(h.roster.get('p1')!['sheet']),
        'mental': <Object?>['潜在疯狂'],
      };
      expect(h.fadedArm['p1'], isNull, reason: '前置：尚未分配');

      // 进入下一回合（RoomEvt.round 触发 _onRoundBoundary）
      h.intent(kHostSeat, _act('round.next', const <String, Object?>{}));

      expect(h.fadedArm['p1'], isFalse,
          reason: '改前这里硬编码老取值，潜在疯狂的座位永远 disarm 不掉');
    });

    test('B2 老取值「不定疯狂（症状消失）」仍按潜在疯狂处理（老卡兼容）', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        ...asMap(h.roster.get('p1')!['sheet']),
        'mental': <Object?>[avatarLegacyPotential],
      };
      h.intent(kHostSeat, _act('round.next', const <String, Object?>{}));
      expect(h.fadedArm['p1'], isFalse);
    });

    test('B3 不处于潜在疯狂的座位不受影响（不会被无脑置 false）', () {
      final h = _host();
      // p1 = 正常，p2 = 潜在疯狂
      h.roster.get('p2')!['sheet'] = <String, Object?>{
        'name': '乙',
        'status': <String, Object?>{'currentSAN': 40, 'maxSAN': 60},
        'mental': <Object?>['潜在疯狂'],
        'madness': <Object?>[],
      };
      h.intent(kHostSeat, _act('round.next', const <String, Object?>{}));
      expect(h.fadedArm.containsKey('p1'), isFalse,
          reason: '正常人不需要 disarm 标记');
      expect(h.fadedArm['p2'], isFalse);
    });

    test('B4 潜在疯狂 + 再损失 SAN → 复发为不定疯狂并新增一条症状', () {
      final h = _host();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        ...asMap(h.roster.get('p1')!['sheet']),
        'mental': <Object?>['潜在疯狂'],
      };
      h.fadedArm['p1'] = true; // 本回合已武装

      h.intent(kHostSeat, _act('sheet.sanloss', <String, Object?>{
        'seat': 'p1',
        'loss': 1,
      }));

      final mental = asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
      expect(mental.contains('不定疯狂'), isTrue, reason: '必须复发为不定疯狂');
      expect(mental.contains('潜在疯狂'), isFalse, reason: '两者互斥');
      expect(asList(asMap(h.roster.get('p1')!['sheet'])['madness']),
          isNotEmpty, reason: '必须新生成一条疯狂症');
    });

    test('B5 玩家可见文案统一用「潜在疯狂」，不含旧名「症状消失」', () {
      final files = <File>[];
      for (final dir in <String>[
        'lib/ui',
        'lib/domain',
      ]) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        for (final e in d.listSync(recursive: true)) {
          if (e is File && e.path.endsWith('.dart')) files.add(e);
        }
      }
      expect(files, isNotEmpty);
      final offenders = <String>[];
      for (final f in files) {
        // 先去注释再判：注释里写「老值 X 已改名为 Y」是**必须留**的说明，
        // 只有**代码**里还拿旧名做比较 / 展示才是问题。
        final code = _stripComments(f.readAsStringSync()).split('\n');
        for (var i = 0; i < code.length; i++) {
          final line = code[i];
          if (!line.contains('症状消失')) continue;
          // 兼容取值常量本身（kRaMentalLegacyPotential 那一行）允许存在 ——
          // 老卡读入时必须认得出老名字。
          final isLegacyConst = line.contains('kRaMentalLegacyPotential') ||
              line.contains('kMentalLegacyPotential');
          if (isLegacyConst) continue;
          // 「兼容取值表里的独立字面量」允许：那一行只可能是
          //   '不定疯狂（症状消失）',
          // 是「读入时认得出老名字」的白名单，不是给玩家看的句子。
          // 但把旧名嵌进一句话里（例如「你正处于不定疯狂（症状消失）」）必须报。
          final bare = line.trim().replaceAll(',', '').trim();
          if (bare == "'不定疯狂（症状消失）'" ||
              bare == '"不定疯狂（症状消失）"') {
            continue;
          }
          offenders.add('${f.path}:${i + 1}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty,
          reason: '玩家可见文案不该再出现旧名「症状消失」：\n${offenders.join('\n')}');
    });
  });

  // ==========================================================
  // C. 自动头像 PNG 化
  // ==========================================================
  group('C · 自动头像 PNG 化（跨设备广播）', () {
    test('C1 PNG 与 SVG 视觉参数同源（同一份取色 / 转角 / 点数）', () {
      for (final name in <String>['张三', 'Eliza Ward', '王', '李四光']) {
        final spec = avatar.specOf(name);
        final back = avatar.specFromSvg(avatar.make(name));
        expect(back, isNotNull, reason: '$name 的 SVG 应可反解');
        expect(back!.bgTop, spec.bgTop);
        expect(back.bgBottom, spec.bgBottom);
        expect(back.foreground, spec.foreground);
        expect(back.initial, spec.initial);
        expect(back.rotationDegrees, spec.rotationDegrees);
        expect(back.dots, spec.dots);
      }
    });

    test('C2 warm 调色也能反解回来（不丢 flavor）', () {
      const name = '赵五';
      final warm = avatar.specOf(name, 'warm');
      final back = avatar.specFromSvg(avatar.make(name, 'warm'));
      expect(back, isNotNull);
      expect(back!.bgTop, warm.bgTop);
      expect(back.foreground, warm.foreground);
      // 与默认 flavor 不同 —— 证明 flavor 真的被保住了
      expect(warm.bgTop, isNot(avatar.specOf(name).bgTop));
    });

    test('C3 判据：自动 SVG 与上传的 PNG 分得清', () {
      expect(avatar.isAutoAvatarSvg(avatar.make('张三')), isTrue);
      expect(avatar.isAutoAvatarSvg('data:image/png;base64,AAAA'), isFalse);
      expect(avatar.isAutoAvatarSvg('avatars/c1.png'), isFalse);
      expect(avatar.isAutoAvatarSvg(''), isFalse);
      // 广播判据只认 png/jpeg/webp：SVG **不能**进广播（这就是缺口）
      expect(roomAvatarDataUri(avatar.make('张三')), '');
    });

    testWidgets('C4 生成的是 PNG base64 dataURI，长度 ≤ 20000，且是真 PNG',
        (WidgetTester tester) async {
      // `picture.toImage()` / `toByteData()` 是真异步：必须在 runAsync 里跑，
      // 否则 fake-async 区域里永不完成。
      await tester.runAsync(() async {
        final spec = avatar.specOf('张三');
        final uri = await autoAvatarPng(spec);
        expect(uri.startsWith('data:image/png;base64,'), isTrue,
            reason: '必须是 PNG base64（跨设备缩略链路只收这个形态）');
        expect(uri.length, lessThanOrEqualTo(20000));
        expect(uri.length, greaterThan(500), reason: '不能是空图');
        final bytes = avatarDataUriBytes(uri);
        expect(bytes, isNotNull);
        // PNG 魔数 \x89PNG\r\n\x1a\n
        expect(bytes!.sublist(0, 8),
            <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        // 能被房间广播判据接受
        expect(roomAvatarDataUri(uri), uri);
      });
    });

    test('C5 绑卡上报：没有上传头像 + 有名字 → sheet 里带的是 PNG（不是 SVG）',
        () async {
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      const png = 'data:image/png;base64,AAAB';
      String? gotInitial;
      autoAvatarPngEncoder = (spec) async {
        gotInitial = spec.initial;
        return png;
      };
      final savedThumb = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = savedThumb);
      avatarThumbEncoder = (Object? _) async => '';

      final card = Character(newCharacter());
      card.raw['id'] = 'c9';
      card.raw['characterName'] = '张三';
      card.raw['avatar'] = '';
      final sheet = await cardToRoomSheetForReport(card);
      expect(sheet['avatar'], png, reason: '广播用的必须是 PNG');
      expect(gotInitial, '张', reason: '首字要与 SVG 版同源');
    });

    test('C6 绑卡上报：老卡里已存的 SVG 自动头像 → 反解参数后转 PNG', () async {
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      const png = 'data:image/png;base64,AAAC';
      avatar.AvatarSpec? seen;
      autoAvatarPngEncoder = (spec) async {
        seen = spec;
        return png;
      };
      final savedThumb = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = savedThumb);
      avatarThumbEncoder = (Object? _) async => '';

      final card = Character(newCharacter());
      card.raw['id'] = 'c10';
      card.raw['characterName'] = '赵五';
      // 老卡：avatar 里躺的就是自动 SVG
      card.raw['avatar'] = avatar.make('赵五', 'warm');
      final sheet = await cardToRoomSheetForReport(card);
      expect(sheet['avatar'], png);
      final expected = avatar.specOf('赵五', 'warm');
      expect(seen, isNotNull);
      expect(seen!.bgTop, expected.bgTop, reason: '必须用老 SVH 里的原始调色');
      expect(seen!.foreground, expected.foreground);
    });

    test('C7 老卡 SVG 在本机显示侧不炸（退回首字圆点，不抛、不空白）', () {
      final svg = avatar.make('张三');
      // 显示侧判据只认 base64 dataURI / 本机相对路径 → SVG 一律 null
      expect(avatarDataUriBytes(svg), isNull);
      expect(roomAvatarDataUri(svg), '');
      // 但卡里的值**不被改掉**（老卡头像不能丢）
      final card = <String, Object?>{'characterName': '张三', 'avatar': svg};
      final kept = avatar.ensure(card);
      expect(kept, svg, reason: '已有头像必须原样返回，不能覆盖');
    });

    test('C8 缩略图生成失败也降级为「不带 avatar 键」（不阻塞绑卡）', () async {
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      autoAvatarPngEncoder = (spec) async => throw StateError('boom');
      final savedThumb = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = savedThumb);
      avatarThumbEncoder = (Object? _) async => '';

      final card = Character(newCharacter());
      card.raw['id'] = 'c11';
      card.raw['characterName'] = '李四';
      final sheet = await cardToRoomSheetForReport(card);
      expect(sheet.containsKey('avatar'), isFalse);
      expect(sheet['name'], isNotNull);
    });
  });
}

/// 取渲染出来的全部文本（含 RichText 的 TextSpan）。
List<String> _texts(WidgetTester tester) {
  final out = <String>[];
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final t = w.data ?? w.textSpan?.toPlainText();
    if (t != null && t.isNotEmpty) out.add(t);
  }
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    final t = w.text.toPlainText();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// 老取值常量（放在测试里单独抄一份，避免「用被测常量测被测代码」）。
const String avatarLegacyPotential = '不定疯狂（症状消失）';

/// 去掉 `//` 行注释与 `/* ... */` 块注释（保留原行数，方便报行号）。
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  var inBlock = false;
  var inLine = false;
  var inString = false;
  String? quote;
  while (i < src.length) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';
    if (inLine) {
      if (c == '\n') {
        inLine = false;
        out.write(c);
      }
      i++;
      continue;
    }
    if (inBlock) {
      if (c == '*' && next == '/') {
        inBlock = false;
        i += 2;
        continue;
      }
      if (c == '\n') out.write(c);
      i++;
      continue;
    }
    if (inString) {
      out.write(c);
      if (c == '\\') {
        if (next.isNotEmpty) {
          out.write(next);
          i += 2;
          continue;
        }
      } else if (c == quote) {
        inString = false;
      }
      i++;
      continue;
    }
    if (c == '/' && next == '/') {
      inLine = true;
      i += 2;
      continue;
    }
    if (c == '/' && next == '*') {
      inBlock = true;
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      inString = true;
      quote = c;
      out.write(c);
      i++;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
