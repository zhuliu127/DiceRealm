// ============================================================
// test/p11_status_bar_test.dart — P11 修「玩家视角自己的 HP / MP / SAN 是空的」
//
// 用户真机报的 bug（2026-11-11）：
//   「跑团房间里，玩家视角看自己角色，HP / MP / SAN 三个数值都是空的，
//     显示成『-』。」
//
// 本文件先给**实测事实清单**（哪个 widget / 哪个字段 / 渲染出的确切文本），
// 再用断言把「未初始化 ≠ 0」这条口径钉死。
//
// 附带覆盖的卡形（缺一不可，否则修着修着就把别的视角搞坏）：
//   ① 完整卡（车卡器产出，带 derivedStats → status 满值）
//   ② 老卡（只有 status，没有 attrs / derivedStats）
//   ③ 他人视角（`_cropMember` 把 maxSAN 裁成 null、attrs 整块删掉）
//   ④ 未绑卡（成员在房间里，但还没有任何卡数据）← 用户看到的那一屏
//   ⑤ 真的 0（「清空房卡数值」后的空白卡：0 是事实，必须照实显示）
//   ⑥ 有卡名但卡数据没到（ACT 通道 char.share 丢 sheet 的遗留数据）
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/ui/room/room_game_page.dart';
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/sheets/card_sheet_payload.dart'
    show cardToRoomSheet;
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart'
    show GpPlCharCard, GpPlCharCardKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart' show GpPlMates;
import 'package:dice_realm/ui/room/widgets/gp_status.dart' show GpStatus;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 造卡（走**真实**链路：车卡 → cardToRoomSheet → INTENT.CHAR）
// ------------------------------------------------------------

/// 完整卡：属性齐全 + `recalc` 过 → status 被引擎初始化成满值。
Character _fullCard() {
  final Character c = Character(newCharacter());
  c.raw['id'] = 'full01';
  c.raw['characterName'] = '完整卡';
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
  for (final String k in <String>[
    'str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu', 'luck',
  ]) {
    c.attributes[k] = 60;
  }
  recalc(c);
  return c;
}

/// 老卡：只有 status 块，没有 attributes / derivedStats（房间外的历史数据形状）。
Character _oldCard() {
  return Character(<String, Object?>{
    'id': 'old01',
    'characterName': '老卡',
    'status': <String, Object?>{
      'currentHP': 9,
      'maxHP': 13,
      'currentMP': 7,
      'maxMP': 11,
      'currentSAN': 44,
      'maxSAN': 60,
      'currentLuck': 30,
      'body': '正常',
      'dying': false,
      'unconscious': false,
    },
  });
}

/// 「清空房卡数值」用的空白卡（与 `sheet_bind_char.dart#_clear` 同一构造）。
Character _blankCard() => Character(<String, Object?>{});

/// 用**玩家自己的视角**把一张车卡带进房间（与 `BindCharSheet#_pick` 同一条链）。
Future<void> _bind(
  RoomUiFixture f,
  String seat,
  Character card,
) async {
  await f.sessionOf(seat).sendIntent(RoomIntent.char, <String, Object?>{
    'id': card.id,
    'name': card.characterName,
    'sheet': cardToRoomSheet(card),
  });
}

// ------------------------------------------------------------
// 取数小工具
// ------------------------------------------------------------

/// 某个子树里所有 Text 的 data（顺序即渲染顺序）。
List<String> _textsIn(WidgetTester tester, Finder root) => <String>[
      for (final Element e
          in find.descendant(of: root, matching: find.byType(Text)).evaluate())
        (e.widget as Text).data ?? '',
    ];

Finder get _cardRoot => find.byKey(GpPlCharCardKeys.root);

/// 块级宿主（弹层 / 单块用例用；带三件套作用域，与 `room_ui_player_test` 同形）。
Widget _blockHost(RoomUiFixture f, String seat, Widget block) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(
        seat,
        child: Scaffold(body: SingleChildScrollView(child: block)),
      ),
    );

void main() {
  // ----------------------------------------------------------
  // 0 · 事实清单（用户报的那一屏，逐位置实测）
  // ----------------------------------------------------------
  group('0 · 事实清单：三个候选位置各自的实测文本', () {
    testWidgets('完整卡 · 玩家自己视角：三个位置都正常，没有任何字面破折号',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      await _bind(f, 'p1', _fullCard());
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      // ① 我的角色卡（StatBar）：'<现值> / <上限>'
      final List<String> card = _textsIn(tester, _cardRoot);
      expect(card, containsAll(<String>['HP', 'MP', 'SAN']));
      expect(card.where((String t) => t == '12 / 12').length, 2,
          reason: 'HP 与 MP 的「现值 / 上限」都要渲染出来（各一条）');
      expect(card.where((String t) => t.contains('—')).toList(), isEmpty,
          reason: '完整卡不该出现「—」占位（八项属性必须都是真实数字）');
      expect(card.where((String t) => t.trim() == '-').toList(), isEmpty,
          reason: '角色卡上不该有任何「-」字面量');

      // ② 队友栏（他人视角）：只有当前值，没有「/ 上限」
      f.localOf('p1').setMatesOpen(true);
      await tester.pumpWidget(_blockHost(f, 'p1', const GpPlMates()));
      await tester.pump();
      final List<String> mates = _textsIn(tester, find.byType(GpPlMates));
      expect(
        mates.where((String t) => t.startsWith('HP ') && t.contains(' · SAN ')),
        isNotEmpty,
        reason: '队友行应渲染「HP x · SAN y」',
      );
      for (final String t in mates) {
        expect(t.contains(' / '), isFalse,
            reason: '他人视角的 maxSAN 已裁剪，队友行不许出现「/ 上限」：$t');
        expect(t.contains('—'), isFalse, reason: '队友行不该出现「—」：$t');
      }

      // ③ 状态条：本块只画「需我同意」，不含 HP/MP/SAN
      await tester.pumpWidget(_blockHost(f, 'p1', const GpStatus()));
      await tester.pump();
      final List<String> status = _textsIn(tester, find.byType(GpStatus));
      expect(status.where((String t) => t.contains('HP')).toList(), isEmpty,
          reason: '状态条不该出现 HP 数值（用户报的位置不在这里）');
    });
  });

  // ----------------------------------------------------------
  // 1 · 用户那一屏：没绑卡时**不许**画一张 0 / 0 的假卡
  // ----------------------------------------------------------
  group('1 · 未初始化：如实说「没绑卡」，不许拿 0 冒充', () {
    testWidgets('没绑卡的玩家 → 明确说没绑卡；不再出现 0 / 0、也不出现「—」',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, withSheets: false);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      // 成员在（所以以前会掉进完整卡片分支），但一丁点卡数据都没有
      expect(f.stateOf('p1')['members'], isA<List<Object?>>());
      final List<String> card = _textsIn(tester, _cardRoot);

      expect(card, contains('还没有绑定角色卡（等 KP 或房间页绑定）'),
          reason: '没绑卡时必须如实说明（用户报的「空的三个数值」就是缺这句）');
      expect(card.where((String t) => t.contains('0 / 0')).toList(), isEmpty,
          reason: '★ 未初始化 ≠ 0：不许画出 HP 0 / 0');
      expect(card.where((String t) => t.contains('—')).toList(), isEmpty,
          reason: '★ 未初始化时也不该出现八项属性的「—」占位');
      expect(card.contains('HP'), isFalse,
          reason: '没卡就不该有数值条（含 HP 标签）');
    });

    testWidgets('有卡名但数值没到（历史遗留数据）→ 说没同步到',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, withSheets: false);
      // ★ 复现路径（P11 更新）：旧版 ACT `char.share` 只写 charName / charId，
      //   `sheet` 整块丢弃 —— 于是存档里留下「有卡名、无卡数据」的成员。
      //   P11 已把 ACT 通道改成委托 `shareSheet`（整份落库），这条通道再也
      //   造不出坏形状；所以这里直接构造**遗留数据本身的形状**：只报 id/name，
      //   不带 sheet（= 旧客户端 / 旧存档里那条记录的样子）。
      //   断言一字未改：仍然必须落到「数值还没同步到」的占位分支。
      await f.controllerOf('p1').hostAction('char.share', <String, Object?>{
        'id': 'full01',
        'name': '完整卡',
      });
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      final List<String> card = _textsIn(tester, _cardRoot);
      expect(card, contains('角色卡的数值还没同步到（重新绑定一次角色卡即可）'));
      expect(card.where((String t) => t.contains('0 / 0')).toList(), isEmpty);
    });
  });

  // ----------------------------------------------------------
  // 2 · 各种**有数据**的卡形：必须显示真实数值
  // ----------------------------------------------------------
  group('2 · 有卡就必须显示真实数值（三种来源各一遍）', () {
    testWidgets('完整卡（derivedStats → status 满值）：12 / 12 · 12 / 12 · 60 / 60',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, withSheets: false);
      await _bind(f, 'p1', _fullCard());
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      final List<String> card = _textsIn(tester, _cardRoot);
      expect(card, contains('12 / 12')); // HP（CON 60 + SIZ 60 → 12）
      expect(card, contains('60 / 60')); // SAN（POW 60）
      expect(card.where((String t) => t.contains('0 / 0')).toList(), isEmpty);
      // 八项属性是真实数字，不是占位
      expect(card, contains('STR 60'));
      expect(card.where((String t) => t.contains('—')).toList(), isEmpty);
      expect(find.byKey(GpPlCharCardKeys.unbound), findsNothing,
          reason: '有卡时不该再出「未绑定」提示');
    });

    testWidgets('老卡（只有 status）：9 / 13 · 7 / 11 · 44 / 60，不吃上限',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, withSheets: false);
      await _bind(f, 'p1', _oldCard());
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      final List<String> card = _textsIn(tester, _cardRoot);
      expect(card, contains('9 / 13'), reason: 'HP 现值 / 上限取自 status');
      expect(card, contains('7 / 11'), reason: 'MP 现值 / 上限取自 status');
      expect(card, contains('44 / 60'), reason: 'SAN 现值 / 上限取自 status');
    });

    testWidgets('真的 0（清空房卡数值）：0 / 0 照实显示 —— 0 是事实，不是「不知道」',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true, withSheets: false);
      await _bind(f, 'p1', _blankCard());
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      final List<String> card = _textsIn(tester, _cardRoot);
      expect(card.where((String t) => t == '0 / 0').length, 3,
          reason: '空白卡的三个数值确实是 0，必须照实显示（不能被当成未初始化）');
      expect(find.byKey(GpPlCharCardKeys.unbound), findsNothing,
          reason: '空白卡是「有卡」，不是「没绑卡」');
    });
  });

  // ----------------------------------------------------------
  // 3 · 他人视角的裁剪规则没被搞坏（反向保护）
  // ----------------------------------------------------------
  group('3 · 他人视角：maxSAN 仍然裁剪、attrs 仍然不下发', () {
    testWidgets('p1 看 p2：队友行只有当前值；p1 自己那张仍然带上限',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true); // 夹具给每人一张卡（如 p1 SAN 56 / p2 SAN 57）
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      // ① 自己那张：现值 / 上限都在
      final List<String> mine = _textsIn(tester, _cardRoot);
      expect(mine, contains('56 / 99'), reason: '自己的 SAN 上限必须显示');

      // ② 数据层：p1 收到的 p2 已被裁（maxSAN null、attrs 整块消失）
      final Map<Object?, Object?> p2 = (f.stateOf('p1')['members'] as List<Object?>)
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> m) => m['seat'] == 'p2');
      final Map<String, Object?> p2Sheet = asMap(p2['sheet']);
      expect(asMap(p2Sheet['status'])['maxSAN'], isNull,
          reason: '他人视图的 maxSAN 必须仍是 null（裁剪规则不许动）');
      expect(p2Sheet.containsKey('attrs'), isFalse,
          reason: '他人视图不搬 attrs（隐私白名单）');

      // ③ 渲染层：队友行只有当前值，没有「/ 上限」
      f.localOf('p1').setMatesOpen(true);
      await tester.pumpWidget(_blockHost(f, 'p1', const GpPlMates()));
      await tester.pump();
      final List<String> mates = _textsIn(tester, find.byType(GpPlMates));
      expect(mates, contains('HP 12 · SAN 57'));
      expect(mates.where((String t) => t.contains(' / ')).toList(), isEmpty);
    });

    testWidgets('p2 自己的视角：看到的是自己那张完整卡（不是被别人裁过的那份）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(f.pageOf('p2'));
      await tester.pump();

      final List<String> mine = _textsIn(tester, _cardRoot);
      expect(mine, contains('57 / 99'), reason: 'p2 自己的 SAN 上限必须显示');
      // 夹具逐座位给不同的 dex（55 + 序号）：p2 必须是 57，证明看到的是**自己**
      // 那份完整卡（他人视图里 attrs 整块被裁，根本拿不到这个数）。
      expect(mine, contains('DEX 57'), reason: '自己的八项属性必须可见');
      // ★ P17 P-1：属性区补了 LUK（幸运）。夹具的卡没有 luck 字段 →
      //   按新口径显示占位「LUK —」。裁剪缺口的「—」禁令对它豁免 ——
      //   这不是他人视角的裁剪缺口，是「该卡本来就没有幸运值」。
      expect(
        mine.where((String t) => t.contains('—') && t != 'LUK —').toList(),
        isEmpty,
        reason: '他人视图的裁剪缺口不显示「—」（LUK 缺键占位除外，P17 P-1）',
      );
    });
  });

  // ----------------------------------------------------------
  // 4 · 槽位没被改动（用户要求「布局不要动」的守卫）
  // ----------------------------------------------------------
  testWidgets('4 · 布局守卫：角色卡仍在 gpPlCharCard 槽位、三个数值条仍是 3 条',
      (WidgetTester tester) async {
    final RoomUiFixture f = RoomUiFixture();
    await f.boot(inGame: true);
    f.pageBuilder = (String s, String r) => const RoomGamePage();
    useRoomScreen(tester, 360, 640);
    await tester.pumpWidget(f.pageOf('p1'));
    await tester.pump();

    expect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpPlCharCard)), findsOneWidget);
    expect(find.byType(GpPlCharCard), findsOneWidget);
    for (final String label in <String>['HP', 'MP', 'SAN']) {
      expect(
        find.descendant(of: _cardRoot, matching: find.text(label)),
        findsOneWidget,
        reason: '$label 数值条不能少（布局/槽位改动零容忍）',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
