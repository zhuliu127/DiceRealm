// ============================================================
// test/qa_p10_4_verify_test.dart — QA 独立复核（P10 第 3 期 A 批）
//
// 这个文件**不属于**工程师的交付（`test/p10_t3_broadcast_potential_png_test.dart`），
// 是 QA（严过关）为了「自己怀疑、自己证伪」而另起的独立验证：
//
//   R1 暗骰的 `label` 哨兵串：第三人（p2/p3）的记录栏 / 导出文本 / 整个
//      state JSON 里都搜不到 —— 补 `room_history_export_test` K3 探针
//      从 label 搬走之后**没人守**的那条缺口。
//   R2 正例：公开骰的 label 反过来**必须**看得见（防止用「谁都不显示」骗过 R1）。
//   R3 回合边界 disarm 的**行为后果**（不是只看键值）：潜在疯狂 + 上回合武装
//      → 推进回合 → 再损失 1 点 SAN **不该**复发。
//   R4 自动头像 PNG 跨会话：p2 视角拿到的是图（Image），不是首字圆点。
//   R5 `avatar.make()` 输出**逐字节不变**：拿 Nov 8 的 preset 夹具当旧版 oracle。
//
// ★ 铁律同 T1：全部内存替身，零真实 I/O（R5 只读一个本地夹具文件）。
// ============================================================

import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;

import 'package:dice_realm/domain/avatar.dart' as avatar;
import 'package:dice_realm/domain/avatar_uri.dart' show avatarDataUriBytes;
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_history_export.dart'
    show buildRoomHistoryExportText;
import 'package:dice_realm/ui/room/view/feed_view.dart'
    show FeedKind, collectFeeds, feedAvatarOfSeat;
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart';
import 'package:dice_realm/ui/widgets/avatar_picker.dart' show AvatarThumb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

/// 哨兵串：暗骰 label 里塞的秘密，任何第三人视角都不得出现。
///
/// ⚠️ 必须 ≤ 20 字符：`diceDirect``/`diceRoll` 对 label 走 `cleanText(p['label'], 20)`，
/// 超长会被截断 —— 用 26 字符的串会「因为被截断而搜不到」，得到假绿灯。
const String kLabelSentinel = 'SENTINEL_LBL';

/// 一个 KP + 三名玩家（p1 掷骰 / p2 旁人 / p3 第三人）。
RoomHost _host3() {
  final h = RoomHost(roomHostOpts(seed: 13));
  for (final s in <String>['p1', 'p2', 'p3']) {
    h.attachPeer(<String, Object?>{
      'seat': s,
      'nickname': s == 'p1' ? '甲' : (s == 'p2' ? '乙' : '丙'),
      'at': 1,
    });
  }
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

Map<String, RoomClient> _clients3() => <String, RoomClient>{
      'p1': RoomClient(seat: 'p1'),
      'p2': RoomClient(seat: 'p2'),
      'p3': RoomClient(seat: 'p3'),
    };

/// 按收件人投递（`'*'` = 全员）。这是中继的真等价物。
void _deliver(List<SendPlan> plans, Map<String, RoomClient> cs) {
  for (final p in plans) {
    if (p.to == '*') {
      for (final c in cs.values) {
        c.receive(p.msg.toJson());
      }
    } else {
      cs[p.to]?.receive(p.msg.toJson());
    }
  }
}

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

/// 一个会话视角能看到的**全部文本**：记录栏 + 聊天栏 + 私密栏。
String _visibleText(Map<String, Object?> state) {
  final buf = StringBuffer();
  for (final f in collectFeeds(state)) {
    buf.writeln(f.text);
  }
  for (final row in asList(state['logs'])) {
    buf.writeln(jsStr(asMap(row)['text']));
  }
  for (final row in asList(state['privates'])) {
    buf.writeln(jsStr(asMap(row)['text']));
  }
  return buf.toString();
}

void main() {
  // ==========================================================
  // R1 · 暗骰 label 哨兵串零泄漏（K3 补钉）
  // ==========================================================
  group('R1 · 暗骰的 label 不得出现在第三人视角（K3）', () {
    test('p2 / p3 的记录栏、导出文本、整份 state JSON 都搜不到哨兵串', () {
      final h = _host3();
      final cs = _clients3();
      _boot(h, cs);

      final plans = h.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'direct': true,
          'secret': true,
          'skill': kLabelSentinel,
          'label': kLabelSentinel,
        },
      });
      _deliver(plans, cs);

      // 前置：这条暗骰真的掷了（否则「没泄漏」是空的）——
      // 本人视角的私密栏里必须有完整结果，且带哨兵技能名。
      final p1Priv = _visibleText(cs['p1']!.state);
      expect(p1Priv.contains(kLabelSentinel), isTrue,
          reason: '前置：本人必须看得到自己暗骰的技能名，探针才是真的');
      final kpPriv = _visibleText(h.syncFor(kHostSeat).state);
      expect(kpPriv.contains(kLabelSentinel), isTrue, reason: 'KP 必须看得到');

      // 第三人（p2 / p3）三处都不得出现
      for (final seat in <String>['p2', 'p3']) {
        final st = cs[seat]!.state;

        // ① 记录栏 / 聊天 / 私密 的全部文本
        expect(_visibleText(st).contains(kLabelSentinel), isFalse,
            reason: '$seat 的可见文本里出现了暗骰的技能名');

        // ② 导出文本（会被复制 / 分享 / 落到别的设备）
        final export = buildRoomHistoryExportText(
          st,
          seat: seat,
          role: RoomRole.player,
          exportedAtMs: 1700000000000,
        );
        expect(export.contains(kLabelSentinel), isFalse,
            reason: '$seat 导出的记录里出现了暗骰的技能名');

        // ③ 兜底：整份 state 序列化后也不许有（防止藏在结构化字段里）
        expect(jsonEncode(st).contains(kLabelSentinel), isFalse,
            reason: '$seat 的 state JSON 里出现了暗骰的技能名');

        // ④ 公共侧只留脱敏提示（有话说，但不说是什么）
        expect(_visibleText(st).contains('暗骰了一次'), isTrue,
            reason: '公开侧仍应有一条脱敏提示，不是「什么都没发生」');
      }
    });

    test('KP 暗骰（darkRoll）与秘密对抗同样不带技能名出去', () {
      final h = _host3();
      final cs = _clients3();
      _boot(h, cs);

      _deliver(
        h.intent(kHostSeat, _act('check.opposed', <String, Object?>{
          'secret': true,
          'a': <String, Object?>{
            'side': 'pc',
            'seat': 'p1',
            'skill': kLabelSentinel,
          },
          'b': <String, Object?>{'side': 'monster', 'name': '怪', 'value': 40},
        })),
        cs,
      );

      for (final seat in <String>['p2', 'p3']) {
        expect(_visibleText(cs[seat]!.state).contains(kLabelSentinel), isFalse,
            reason: '$seat 看到了秘密对抗里的技能名');
        expect(jsonEncode(cs[seat]!.state).contains(kLabelSentinel), isFalse);
      }
    });
  });

  // ==========================================================
  // R2 · 正例：公开骰的技能名必须看得见
  // ==========================================================
  group('R2 · 公开检定反例（防止「谁都不显示」骗过 R1）', () {
    test('p2 的记录栏里出现「甲：侦查：1D100 → …」，第三人 p3 同样看得见', () {
      final h = _host3();
      final cs = _clients3();
      _boot(h, cs);

      _deliver(
        h.intent('p1', <String, Object?>{
          'op': RoomIntent.dice,
          'p': <String, Object?>{
            'expr': '1D100',
            'direct': true,
            'skill': '侦查',
            'label': '侦查',
          },
        }),
        cs,
      );

      for (final seat in <String>['p2', 'p3']) {
        final items = collectFeeds(cs[seat]!.state)
            .where((f) => f.kind == FeedKind.dice)
            .toList();
        expect(items, hasLength(1), reason: '$seat 没收到公开骰');
        expect(items.single.nickname, '甲', reason: '骰行必须带昵称');
        expect(items.single.text.startsWith('侦查：'), isTrue,
            reason: '骰行必须以技能名开头');
        expect(items.single.text.contains('1D100 →'), isTrue);
      }
    });
  });

  // ==========================================================
  // R3 · 回合边界 disarm 的**行为后果**
  // ==========================================================
  group('R3 · 潜在疯狂：回合推进后「任意损失即复发」必须失效', () {
    test('上回合武装 + 推进回合 + 再损失 1 点 → 仍是潜在疯狂（不复发）', () {
      final h = _host3();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        ...asMap(h.roster.get('p1')!['sheet']),
        'mental': <Object?>['潜在疯狂'],
      };
      h.fadedArm['p1'] = true; // 前置：上一回合已武装
      expect(h.fadedArm['p1'], isTrue);

      // 推进回合 → 仍处潜在疯狂 → 必须被 disarm
      h.intent(kHostSeat, _act('round.next', const <String, Object?>{}));
      expect(h.fadedArm['p1'], isFalse,
          reason: '★ 改前硬编码老取值，潜在疯狂永远 disarm 不掉');

      // 再损失 1 点 SAN：< ceil(maxSAN/5)=12，且已 disarm → 不该复发
      h.intent(kHostSeat, _act('sheet.sanloss', <String, Object?>{
        'seat': 'p1',
        'loss': 1,
      }));

      final mental = asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
      expect(mental.contains('不定疯狂'), isFalse,
          reason: '★ 本回合任意损失即复发 —— 推进回合后必须失效');
      expect(mental.contains('潜在疯狂'), isTrue, reason: '应仍是潜在疯狂');
    });

    test('对照：不推进回合（仍武装）时同一路径**会**复发 —— 证明上面测到了 disarm', () {
      final h = _host3();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        ...asMap(h.roster.get('p1')!['sheet']),
        'mental': <Object?>['潜在疯狂'],
      };
      h.fadedArm['p1'] = true;

      h.intent(kHostSeat, _act('sheet.sanloss', <String, Object?>{
        'seat': 'p1',
        'loss': 1,
      }));

      final mental = asList(asMap(h.roster.get('p1')!['sheet'])['mental']);
      expect(mental.contains('不定疯狂'), isTrue,
          reason: '对照：武装状态下 1 点损失就该复发，否则上面的绿灯是空的');
    });

    test('老取值「不定疯狂（症状消失）」的老卡同样被 disarm（不是只认新名）', () {
      final h = _host3();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        ...asMap(h.roster.get('p1')!['sheet']),
        'mental': <Object?>['不定疯狂（症状消失）'],
      };
      h.intent(kHostSeat, _act('round.next', const <String, Object?>{}));
      expect(h.fadedArm['p1'], isFalse,
          reason: '翻成「潜在疯狂」后必须命中同一条判据');
    });
  });

  // ==========================================================
  // R4 · 自动头像 PNG 跨会话：p2 拿到的是图
  // ==========================================================
  group('R4 · 没上传头像的玩家跨设备显示自动头像图（不是首字圆点）', () {
    testWidgets('真 PNG 进成员表 → p2 视角拿到 dataURI → 渲染出 Image', (
      WidgetTester tester,
    ) async {
      // 引擎真异步（toImage）必须在 runAsync 里跑
      String? uri;
      await tester.runAsync(() async {
        uri = await autoAvatarPng(avatar.specOf('张三'));
      });
      expect(uri, isNotNull);
      expect(uri!.startsWith('data:image/png;base64,'), isTrue);
      expect(avatarDataUriBytes(uri!), isNotNull, reason: '必须能解码');
      expect(uri!.length, lessThanOrEqualTo(20000));

      // p1 的卡上报成这个 PNG（等价于绑卡完成）
      final h = _host3();
      h.roster.get('p1')!['sheet'] = <String, Object?>{
        ...asMap(h.roster.get('p1')!['sheet']),
        'avatar': uri,
      };
      final p2 = RoomClient(seat: 'p2')..receive(h.syncFor('p2').toJson());

      final got = feedAvatarOfSeat(p2.state, 'p1');
      expect(got, uri, reason: 'p2 视角必须拿到 p1 的头像 dataURI（跨设备广播）');

      // 渲染：有图就是 Image，没有才是首字圆点
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AvatarThumb(relPath: got, name: '张三', size: 24)),
      ));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget, reason: '必须真的画出图片');
      expect(find.text('张'), findsNothing, reason: '不能退回成首字圆点');

      // 对照组：空头像 → 首字圆点（确认上面的 findsOneWidget 不是恒真）
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AvatarThumb(relPath: '', name: '张三', size: 24)),
      ));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.text('张'), findsOneWidget);
    });
  });

  // ==========================================================
  // R5 · make() 输出逐字节不变（夹具当旧版 oracle）
  // ==========================================================
  group('R5 · avatar.make() 字节不变', () {
    test('preset 夹具（Nov 8，改前生成）里的 avatar 串今天仍能原样复现', () {
      final raw = File('test/fixtures/preset.json').readAsStringSync();
      final doc = asMap(jsonDecode(raw));
      final cases = asList(doc['cases']);
      expect(cases, isNotEmpty);

      var checked = 0;
      for (final c in cases) {
        final expectPart = asMap(asMap(c)['expect']);
        final stored = jsStr(expectPart['avatar']);
        final name = jsStr(expectPart['characterName']);
        if (!stored.startsWith('data:image/svg+xml;charset=utf-8,')) continue;
        checked++;
        final d = avatar.make(name);
        final w = avatar.make(name, 'warm');
        expect(d == stored || w == stored, isTrue,
            reason: '★ $name 的自动头像字节变了（make() 不再逐字节等价）');
      }
      expect(checked, greaterThanOrEqualTo(5),
          reason: '夹具里至少要有 5 张自动头像才能当 oracle');
    });
  });
}
