// ============================================================
// test/p11_misc_bug_test.dart — P11 四条「静默丢数据 / null 当文字」回归靶子
//
// 钉住的四条（每条都能独立变红，改回缺陷即红）：
//   A. ACT 通道 `char.share` 必须把整份 `sheet` 落到成员上
//      （`room_model_actions_room.dart#roomActionCharShare` 委托给
//       `room_model_save.dart#shareSheet`）。缺陷形态：只写 charName / charId，
//      `p['sheet']` 整块丢弃 → 「有卡名、无卡数据」。
//   B. 「清空房卡数值」后 `sheet.name` 必须是空串
//      （`sheet_bind_char.dart#_clear`）。缺陷形态：`Character({})` 让
//      `jsStr(null) == 'null'`，卡名变成四个字母 `null`。
//   C. 玩家栏队友行：无卡成员显示「未绑卡」，不许拼 `HP 0 · SAN 0`
//      （`gp_pl_mates.dart`）。
//   D. 手绘板状态行：无卡成员显示「未绑卡」，不许拼 `HP 0/0`
//      （`gp_pl_sketch.dart`）。
//
// ★ 铁律：T1 全内存后端、零真实 I/O；T6 断言「到底发了什么」看 `sent`；
//   T8 跨视角只用 `stateOf(seat)`；断言只收紧不放宽。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_model_host_core.dart' show RoomHost;
import 'package:dice_realm/domain/room_model_host_intent.dart'
    show RoomHostIntent;
import 'package:dice_realm/domain/room_types.dart'
    show RoomEvt, RoomIntent, RoomRole, SendPlan;
import 'package:dice_realm/repo/avatar_thumb.dart' show avatarThumbEncoder;
import 'package:dice_realm/repo/repo_scope.dart' show RepoScope;
import 'package:dice_realm/ui/room/sheets/sheet_bind_char.dart'
    show BindCharSheetKeys, openBindCharSheet;
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart'
    show GpPlMates, GpPlMatesKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_sketch.dart'
    show GpPlSketch, GpPlSketchKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart'
    show autoAvatarPngEncoder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart' show roomHostOpts;
import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// A 的脚手架（与 p11_authz_ready_test 同源）
// ------------------------------------------------------------

/// p1 / p2 是玩家，sp1 是旁观者。
RoomHost _host() {
  final h = RoomHost(roomHostOpts(seed: 7));
  h.attachPeer(<String, Object?>{
    'seat': 'p1',
    'nickname': '甲',
    'role': RoomRole.player,
    'at': 1,
  });
  h.attachPeer(<String, Object?>{
    'seat': 'p2',
    'nickname': '乙',
    'role': RoomRole.player,
    'at': 2,
  });
  h.attachPeer(<String, Object?>{
    'seat': 'sp1',
    'nickname': '旁观',
    'role': RoomRole.spectator,
    'at': 3,
  });
  return h;
}

/// ACT 通道请求体。
Map<String, Object?> _act(String op, Map<String, Object?> p) =>
    <String, Object?>{
      'op': RoomIntent.act,
      'p': <String, Object?>{'op': op, ...p},
    };

/// 某视角收到的最后一份 `members` 广播里的成员表（没有则空）。
///
/// ★ 必须按 `to` 取：他人视图会被 `_cropMember` 裁掉 `attrs`，
///   拿「最后一份」容易取到别人那份裁剪态，断言就变成测裁剪规则了。
List<Map<String, Object?>> _membersFor(List<SendPlan> plans, String to) {
  List<Map<String, Object?>> last = <Map<String, Object?>>[];
  for (final p in plans) {
    if (p.to != to) continue;
    final m = p.msg.toJson();
    if (m['k'] == 'evt' && m['t'] == RoomEvt.members) {
      last = asList(asMap(m['p'])['members']).map(asMap).toList();
    }
  }
  return last;
}

Map<String, Object?>? _memberIn(List<Map<String, Object?>> members, String seat) {
  for (final m in members) {
    if (jsStr(m['seat']) == seat) return m;
  }
  return null;
}

/// 一份完整卡载荷（键名就是 `INTENT.CHAR` 的 `sheet` 形状）。
Map<String, Object?> _fullSheet() => <String, Object?>{
      'name': '调查员',
      'attrs': <String, Object?>{
        'str': 50,
        'con': 55,
        'siz': 60,
        'dex': 61,
        'app': 45,
        'int': 70,
        'pow': 65,
        'edu': 80,
        'luck': 40,
      },
      'status': <String, Object?>{
        'currentHP': 9,
        'maxHP': 12,
        'currentMP': 7,
        'maxMP': 10,
        'currentSAN': 44,
        'maxSAN': 99,
        'body': '正常',
      },
      'skills': <Object?>[
        <String, Object?>{'name': '侦查', 'total': 70},
      ],
    };

// ------------------------------------------------------------
// B/C/D 的宿主
// ------------------------------------------------------------

/// 独立宿主：作用域挂在 Navigator 之上（弹层也能取到同一份作用域）。
Widget _hostApp(
  RoomUiFixture f,
  Widget Function() build, {
  String seat = 'p1',
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => f.scoped(seat, child: child),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: build(),
      ),
    ),
  );
}

/// 弹层宿主：绑卡弹层要 `RepoScope`（角色卡仓库）+ `RoomScope`。
Widget _sheetHost(RoomUiFixture f, Widget Function(BuildContext) trigger) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => RepoScope(
      repo: f.repo,
      child: f.scoped('p1', child: child),
    ),
    home: Scaffold(body: Center(child: Builder(builder: trigger))),
  );
}

/// 递归收集 Map / List 里所有 **String 值**（用于证明没有字面量 `null`）。
List<String> _stringValues(Object? v) {
  final out = <String>[];
  if (v is String) {
    out.add(v);
  } else if (v is Map) {
    for (final val in v.values) {
      out.addAll(_stringValues(val));
    }
  } else if (v is List) {
    for (final val in v) {
      out.addAll(_stringValues(val));
    }
  }
  return out;
}

/// 某行（或任意子树）里所有 Text 的文案。
List<String> _textsUnder(WidgetTester tester, Finder root) => <String>[
      for (final t in tester.widgetList<Text>(find.descendant(
        of: root,
        matching: find.byType(Text),
      )))
        t.data ?? '',
    ];

void main() {
  // 头像编码是引擎真异步：widget 测试里统一替身（本文件不测头像链路）。
  setUp(() {
    avatarThumbEncoder = (Object? raw) async => '';
    autoAvatarPngEncoder = (Object? spec) async => '';
  });

  // ==========================================================
  // A · ACT char.share 不许丢 sheet
  // ==========================================================
  group('A ACT char.share：整份 sheet 必须落到成员上', () {
    test('A-1 带 sheet 上报 → 成员 sheet / runtime 都拿到卡数据', () {
      final h = _host();
      final sheet = _fullSheet();

      final plans = h.intent(
        'p1',
        _act('char.share', <String, Object?>{
          'seat': 'p1',
          'id': 'c1',
          'name': '调查员',
          'sheet': sheet,
        }),
      );

      final mem = h.roster.get('p1')!;
      expect(mem['charName'], '调查员');
      expect(mem['charId'], 'c1');

      final got = asMap(mem['sheet']);
      expect(got, isNotEmpty,
          reason: '★ 修复前这里整块为空：p[\'sheet\'] 被丢弃，只剩卡名');
      expect(asMap(got['status'])['currentHP'], 9,
          reason: '★ 卡数据必须真的落库，而不是只留 charName');
      expect(asMap(got['status'])['maxSAN'], 99);
      expect(asMap(got['attrs'])['dex'], 61);
      expect(asList(got['skills']).length, 1);

      // 现值同步进 runtime（与 INTENT.CHAR 同一条结算链）
      expect(asMap(mem['runtime'])['hp'], 9,
          reason: '★ sheet 落了，runtime 现值也要跟着写（否则玩家栏仍显示旧值）');

      // 广播出去的成员表里也带上了卡数据（本人视角全量）
      final p1 = _memberIn(_membersFor(plans, 'p1'), 'p1');
      expect(p1, isNotNull, reason: '合法上报必须广播成员表');
      expect(asMap(asMap(p1!['sheet'])['attrs'])['dex'], 61,
          reason: '★ 成员表广播里也要有卡数据');
    });

    test('A-2 越权守卫仍在：指他人一个字节都不改', () {
      final h = _host();

      final plans = h.intent(
        'p1',
        _act('char.share', <String, Object?>{
          'seat': 'p2',
          'id': 'c9',
          'name': '被顶替',
          'sheet': _fullSheet(),
        }),
      );

      expect(h.roster.get('p2')!['charId'], isNull,
          reason: '★ 越权请求不得给 p2 挂上别人送来的卡');
      expect(asMap(h.roster.get('p2')!['sheet']), isEmpty);
      expect(asMap(h.roster.get('p1')!['sheet']), isEmpty,
          reason: '更不能把「指向他人」的载荷落到自己身上');
      final texts = <String>[
        for (final p in plans)
          if (p.msg.toJson()['k'] == 'evt' && p.msg.toJson()['t'] == RoomEvt.private_)
            jsStr(asMap(p.msg.toJson()['p'])['text']),
      ];
      expect(texts, contains('只能上报自己的角色卡'));
    });
  });

  // ==========================================================
  // B · 清空房卡不许把卡名写成字符串 "null"
  // ==========================================================
  group('B 清空房卡数值：卡名是空串，不是字面量 null', () {
    testWidgets('B-1 点「清空房卡数值」→ sheet.name == ""，载荷里没有 "null"',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(); // p1 已有卡（charId = c_p1）→ 清空按钮可用
      useRoomScreen(tester, 400, 860);
      f.sent.clear();

      await tester.pumpWidget(_sheetHost(
        f,
        (BuildContext ctx) => RoomTap(
          key: const Key('openBind'),
          label: '绑卡',
          onTap: () => openBindCharSheet(ctx),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('openBind')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(BindCharSheetKeys.clear), findsOneWidget);

      await tester.tap(find.byKey(BindCharSheetKeys.clear));
      await tester.pump();
      await tester.pump();

      final chars = f.sent
          .where((Map<String, Object?> e) => e['op'] == RoomIntent.char)
          .toList();
      expect(chars, hasLength(1), reason: '清空必须真的发一条 INTENT.CHAR');
      final payload = asMap(chars.single['p']);
      expect(payload['id'], '');
      expect(payload['name'], '');

      final sheet = asMap(payload['sheet']);
      expect(sheet['name'], '',
          reason: '★ 修复前这里是字符串 "null"（jsStr(null) 的 JS 语义）');
      // 顺手钉死同一条 _clear 路径的其它字段：任何层级都不许出现字面量 "null"
      expect(_stringValues(sheet), isNot(contains('null')),
          reason: '★ 八项属性 / 技能 / 装备 / 背景 任一字段被 jsStr(null) 污染都会红');
    });
  });

  // ==========================================================
  // C · 玩家栏队友行
  // ==========================================================
  group('C 队友行：无卡成员不许拼 HP 0 · SAN 0', () {
    testWidgets('C-1 无卡（没 sheet）→ 显示「未绑卡」，不出现 HP 0 / SAN 0',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(withSheets: false);
      useRoomScreen(tester, 800, 900);

      expect(asMap(asMap(f.host.roster.get('p2')!['sheet'])), isEmpty,
          reason: '前提：p2 确实没有卡数据');

      // ★ P20 需求 3⑤：`matesOpen` 默认 false（dock 里默认收起）
      //   ⇒ 验队友行内容要用 `forceOpen: true`。
      await tester.pumpWidget(_hostApp(f, () => GpPlMates(forceOpen: true)));
      await tester.pump();

      final texts = _textsUnder(tester, find.byKey(GpPlMatesKeys.row('p2')));
      expect(texts.any((String s) => s.contains('未绑卡')), isTrue,
          reason: '★ 无卡成员必须如实说没绑卡');
      expect(texts.any((String s) => s.contains('HP 0')), isFalse,
          reason: '★ 「取不到给 0」不是真实血量，不许画成 HP 0');
      expect(texts.any((String s) => s.contains('SAN 0')), isFalse);
    });

    testWidgets('C-2 有卡（真的 0 点血也算有卡）→ 仍显示真实数值', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(); // p2 有卡：HP 12 / SAN 57
      useRoomScreen(tester, 800, 900);

      // ★ 同上：forceOpen 才能验到队友行内容（默认收起）。
      await tester.pumpWidget(_hostApp(f, () => GpPlMates(forceOpen: true)));
      await tester.pump();

      final texts = _textsUnder(tester, find.byKey(GpPlMatesKeys.row('p2')));
      expect(texts, contains('HP 12 · SAN 57'),
          reason: '★ 反证：有卡的成员不许被误判成「未绑卡」');
      expect(texts.any((String s) => s.contains('未绑卡')), isFalse);
    });
  });

  // ==========================================================
  // D · 手绘板状态行
  // ==========================================================
  group('D 手绘板状态行：无卡成员不许拼 HP 0/0', () {
    testWidgets('D-1 无卡 → 状态行含「未绑卡」，不出现 HP 0/0', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(withSheets: false);
      useRoomScreen(tester, 800, 900);

      await tester.pumpWidget(_hostApp(f, () => GpPlSketch()));
      await tester.pump();

      final status =
          tester.widget<Text>(find.byKey(GpPlSketchKeys.locked)).data ?? '';
      expect(status.contains('未绑卡'), isTrue,
          reason: '★ 状态行：$status');
      expect(status.contains('HP 0/0'), isFalse,
          reason: '★ 未初始化不许画成 0 点血：$status');
      expect(status.contains('HP '), isFalse,
          reason: '没有卡就完全不出现 HP 数值段：$status');
    });

    testWidgets('D-2 有卡 → 状态行仍带真实 HP', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 800, 900);

      await tester.pumpWidget(_hostApp(f, () => GpPlSketch()));
      await tester.pump();

      final status =
          tester.widget<Text>(find.byKey(GpPlSketchKeys.locked)).data ?? '';
      expect(status.contains('HP 12/12'), isTrue,
          reason: '★ 反证：有卡的成员不许被误判成「未绑卡」：$status');
      expect(status.contains('未绑卡'), isFalse);
    });
  });
}
