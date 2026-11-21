// ============================================================
// test/room_ui_harness_test.dart — P5/T01 S1.4 夹具自证
//
// 目的：证明 `test/support/room_ui_harness.dart` 真的可用，而不是「看起来
// 能编译」：
//   ① `boot()` 能造出「KP + 2 玩家 + 1 旁观」四份视角；
//   ② `stateOf(seat)` 给的是裁剪态：玩家看不到他人的 sheet.attrs（T8）；
//   ③ `sent` 能记录 UI 发出的 intent / action（T6 的唯一依据）；
//   ④ 竖屏 360×640 与横屏 780×320 下页面都能 pump 成功；
//   ⑤ `bootSync()` 在纯 Dart 用例里可用（暗骰只进私有账）；
//   ⑥ `FakeImagePicker` 的三种返回（选中 / 取消 / 超限）。
//
// 铁律：T1（全内存后端）、T6（断言权威侧 / sent）、T8（跨视角用 stateOf）。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap;
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 深搜一个 JSON 对象里的所有字符串值（含键名），用于「搜不到某字段」断言。
void _collectStrings(Object? v, List<String> out) {
  if (v is Map) {
    for (final e in v.entries) {
      out.add('${e.key}');
      _collectStrings(e.value, out);
    }
  } else if (v is List) {
    for (final x in v) {
      _collectStrings(x, out);
    }
  } else if (v is String) {
    out.add(v);
  }
}

List<String> _allStrings(Object? v) {
  final out = <String>[];
  _collectStrings(v, out);
  return out;
}

void main() {
  group('S1.4 · boot 造出四份视角', () {
    test('KP + 2 玩家 + 1 旁观：四份会话都可取且各自有裁剪态', () async {
      final f = RoomUiFixture();
      await f.boot();

      expect(f.booted, isTrue);
      expect(f.viewCount, 4);
      expect(f.players, 2);
      expect(f.spectators, 1);
      expect(f.plSessions.keys, <String>['p1', 'p2']);
      expect(f.spectatorSessions.keys, <String>['sp1']);
      expect(f.kpSession.seat, kHostSeat);
      expect(f.kpSession.role, RoomRole.kp);
      expect(f.sessionOf('p1').role, RoomRole.player);
      expect(f.sessionOf('sp1').role, RoomRole.spectator);
      expect(f.roleOf(kHostSeat), RoomRole.kp);
      expect(f.roleOf('p1'), RoomRole.player);
      expect(f.roleOf('sp1'), RoomRole.spectator);

      // 座位表：KP 在前，玩家与旁观随后
      expect(f.kpSession.seats, <String>[kHostSeat, 'p1', 'p2', 'sp1']);

      // 四份视角各自的 state 都是「真的收到的那份」（非空且带房间号）
      for (final seat in <String>[kHostSeat, 'p1', 'p2', 'sp1']) {
        final st = f.stateOf(seat);
        expect(st, isNotEmpty, reason: '$seat 的视图不该是空 Map');
        expect(jsonEncode(st).contains(kFixtureRoomCode), isTrue,
            reason: '$seat 应该拿到 meta.code');
      }

      // T7：KP 只读面只有 KP 拿得到
      expect(f.kpSession.hostRead, isNotNull);
      expect(f.sessionOf('p1').hostRead, isNull);
      expect(f.sessionOf('sp1').hostRead, isNull);

      // 水位：四份视角都在同一条序号上（首份全量同步已拉齐）
      for (final seat in f.clientSeats) {
        expect(f.sessionOf(seat).lastSeq, f.host.log.seq,
            reason: '$seat 的水位应与权威端一致');
      }
    });

    test('inGame 走真实 action 开团：status=IN_GAME、round>=1、mode 可指定', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true, mode: RoomMode.combat);

      final meta = asMap(f.host.state['meta']);
      expect(meta['status'], RoomStatus.inGame);
      expect(meta['mode'], RoomMode.combat);
      expect(asMap(f.stateOf('p1')['meta'])['mode'], RoomMode.combat,
          reason: '玩家侧也要收到模式变更事件');

      // 开团与切模式都留下 sent 记录（证明走的是真实 action 而不是手改权威态）
      expect(f.sent.where((e) => e['op'] == 'room.start'), hasLength(1));
      expect(f.sent.where((e) => e['op'] == 'scene.mode'), hasLength(1));
    });
  });

  group('S1.4 · stateOf 给的是裁剪态（T8）', () {
    test('玩家看不到他人的 sheet.attrs，但看得到自己的', () async {
      final f = RoomUiFixture();
      await f.boot(); // boot 默认让每个玩家分享一张 attrs 互不相同的卡

      final s1 = f.stateOf('p1');
      final s2 = f.stateOf('p2');

      Map<String, Object?> memberIn(Map<String, Object?> st, String seat) =>
          asList(st['members'])
              .map(asMap)
              .firstWhere((m) => m['seat'] == seat);

      // 自己的卡：attrs 在（dex = 55 + 座位序号）
      expect(asMap(asMap(memberIn(s1, 'p1')['sheet'])['attrs'])['dex'], 56,
          reason: 'p1 的 dex = 55 + 1（夹具按座位递增）');
      expect(asMap(asMap(memberIn(s2, 'p2')['sheet'])['attrs'])['dex'], 57);

      // 他人的卡：attrs 键整个消失（不是置 null，是压根没下发）
      expect(asMap(memberIn(s1, 'p2')['sheet']).containsKey('attrs'), isFalse,
          reason: 'p1 视图不得出现 p2 的 sheet.attrs 键');
      expect(asMap(memberIn(s2, 'p1')['sheet']).containsKey('attrs'), isFalse,
          reason: 'p2 视图不得出现 p1 的 sheet.attrs 键');

      // 旁观者没有任何人的 attrs
      expect(_allStrings(f.stateOf('sp1')).contains('attrs'), isFalse,
          reason: '旁观者视图不得出现任何 sheet.attrs 键');

      // 两份状态的可见数据确实不同
      expect(identical(s1, s2), isFalse);
      expect(jsonEncode(s1), isNot(equals(jsonEncode(s2))),
          reason: 'p1 / p2 各自看到的「我」不同 → 序列化结果必须不同');

      // ★ 关键反例：stateOf 不能是权威态的别名
      expect(identical(s1, f.host.state), isFalse,
          reason: 'T8：拿权威态当玩家视图会让可见性用例假绿');
      expect(jsonEncode(s1).contains('secret'), isFalse);
    });
  });

  group('S1.4 · sent 记录 intent / action（T6）', () {
    test('controller.sendIntent 记一条 intent，载荷可回查', () async {
      final f = RoomUiFixture();
      await f.boot();
      f.clearSent();

      await f
          .controllerOf('p1')
          .sendIntent(RoomIntent.chat, <String, Object?>{'text': '大家好'});

      expect(f.sent, hasLength(1));
      expect(f.sent.single['kind'], 'intent');
      expect(f.sent.single['op'], RoomIntent.chat);
      final last = f.lastSent(op: RoomIntent.chat);
      expect(last, isNotNull);
      expect(asMap(last!['p'])['text'], '大家好');

      // 权威端真的收到了（T6：断言权威侧，不看 UI 文案）
      expect(asList(f.host.state['chats']), hasLength(1));
    });

    test('hostAction 记一条 action（双层信封的内层 op 就是 action 名）', () async {
      final f = RoomUiFixture();
      await f.boot();
      f.clearSent();

      await f
          .controllerOf(kHostSeat)
          .hostAction('chat', <String, Object?>{'text': 'KP 说话'});

      final last = f.lastSent(action: 'chat');
      expect(last, isNotNull, reason: 'action 必须能按 action: 过滤到');
      expect(last!['kind'], 'action');
      expect(asMap(last['p'])['op'], 'chat',
          reason: '双层信封：内层 p.op 才是 action 名');
      expect(asList(f.host.state['chats']), hasLength(1));
    });

    test('被权威端拒绝的 action 同样留痕，且权威态不变', () async {
      final f = RoomUiFixture();
      await f.boot();
      f.clearSent();

      // 旁观者开团：POLICY 不允许 → 不产生事件
      await f.controllerOf('sp1').hostAction('room.start');

      expect(f.lastSent(action: 'room.start'), isNotNull,
          reason: '按钮点了就必须留痕（否则「点了没反应」无从断言）');
      expect(asMap(f.host.state['meta'])['status'], RoomStatus.recruiting,
          reason: '权威端必须拒绝旁观者的开团');
    });
  });

  group('S1.4 · useRoomScreen + 页面 pump', () {
    testWidgets('竖屏 360×640：玩家页 pump 成功且渲染自己的身份行',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();

      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('fixtureShell')), findsOneWidget);
      expect(find.textContaining('当前玩家：玩家1'), findsOneWidget,
          reason: '顶栏身份行取自 whoLine（纯视图层）');
      expect(find.byKey(const ValueKey<String>('fixture/seat')), findsOneWidget);
    });

    testWidgets('横屏 780×320：同一页面也能 pump 成功（不溢出）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();

      useRoomScreen(tester, 780, 320);
      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('fixtureShell')), findsOneWidget);

      // 同一个用例换档再 pump 一次：尺寸夹具可重复使用
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('KP / 旁观页：身份行按角色切换，KP 看 KP 名',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 360, 640);

      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('KP 主持'), findsOneWidget);

      await tester.pumpWidget(f.spectatorPage('sp1'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('旁观中'), findsOneWidget);
    });

    testWidgets('房间页 / 入口页壳也能 pump（占位，T05 换真页面）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 360, 640);

      await tester.pumpWidget(f.lobbyPage());
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('fixture/stage')), findsOneWidget);
      expect(find.text('房间页'), findsOneWidget);

      await tester.pumpWidget(f.entryPage());
      await tester.pump();
      expect(find.text('入口页'), findsOneWidget);
    });

    testWidgets('页面随 session 重建：发出的聊天出现在下一次 pump 里',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 360, 640);

      await tester.pumpWidget(f.playerPage('p2'));
      await tester.pump();
      expect(find.textContaining('聊天 0'), findsOneWidget);

      await f
          .controllerOf('p1')
          .sendIntent(RoomIntent.chat, <String, Object?>{'text': 'update'});
      await tester.pump();

      expect(find.textContaining('聊天 1'), findsOneWidget,
          reason: '房间作用域订阅 session，泵完必须重建');
    });
  });

  group('S1.4 · bootSync（纯 Dart 用例）', () {
    test('同步装配可用：暗骰结果不进他人视图，只进私有账', () {
      final f = RoomUiFixture()..bootSync();
      expect(f.booted, isTrue);

      f.host.intent('p1', <String, Object?>{
        'op': RoomIntent.dice,
        'p': <String, Object?>{
          'expr': '1D100',
          'direct': true,
          'secret': true,
          'label': '侦查',
        },
      });

      expect(asList(f.stateOf('p2')['dice']), isEmpty,
          reason: '暗骰不得进公共骰栏');
      expect(f.host.privateBySeat['p1'], isNotEmpty);
      expect(f.host.privateBySeat[kHostSeat], isNotEmpty);
    });

    test('bootSync(inGame: true) 同步开团（status / mode 立即可读）', () {
      final f = RoomUiFixture()..bootSync(inGame: true, mode: RoomMode.combat);
      expect(asMap(f.host.state['meta'])['status'], RoomStatus.inGame);
      expect(asMap(f.host.state['meta'])['mode'], RoomMode.combat);
      expect(asMap(f.stateOf('p1')['meta'])['status'], RoomStatus.inGame);
    });
  });

  group('S1.4 · FakeImagePicker', () {
    test('选中 / 取消 / 超限三种返回', () async {
      final p = FakeImagePicker(dataUrl: kFakePngDataUrl);
      expect(await p.pickImage(), kFakePngDataUrl);
      expect(p.calls, 1);
      expect(p.lastMaxBytes, 2 * 1024 * 1024);

      p.dataUrl = null; // 用户取消
      expect(await p.pickImage(), isNull);
      expect(p.calls, 2);

      final big =
          FakeImagePicker(dataUrl: kFakePngDataUrl, bytes: 3 * 1024 * 1024);
      expect(await big.pickImage(), isNull, reason: 'S9：超过 2MB 上限当取消');
      expect(await big.pickImage(maxBytes: 5 * 1024 * 1024), kFakePngDataUrl,
          reason: '放宽上限后同一个替身应能返回');

      // 端口契约：假替身必须真的满足图片选择端口
      final ImagePickerPort port = FakeImagePicker(dataUrl: kFakePngDataUrl);
      expect(await port.pickImage(), isNotNull);
    });
  });
}
