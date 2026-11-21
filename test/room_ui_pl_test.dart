// ============================================================
// test/room_ui_pl_test.dart — P5/T05 玩家专属块验收
//   块 2 角色卡 / 块 7 场景检定 / 块 8 队友 / 块 10 手绘板 / 块 11 笔记
//   + 状态管理弹层（Q-P5-3 文案口径）
//
// 铁律：
//   · T1：后端全部内存实现（存档 / 笔记 / 角色卡 / 分享），零文件读写；
//   · T5：房间页尺寸走 `useRoomScreen`；
//   · T6：断言「点了到底发了什么」一律看夹具的 `sent`，不看 UI 文案；
//   · T8：跨视角断言只用 `stateOf(seat)`（玩家手里真收到的那份裁剪态）。
//
// ★ 每个用例**独立 pump Scaffold**，不依赖游戏页壳体：作用域用
//   `MaterialApp.builder` 挂在 Navigator 之上，于是 `showRoomSheet`
//   推出的弹层也能取到同一份作用域（与 KP 侧用例同一范式）。
// ★ 宿主额外套一层 `ListenableBuilder(local)`：块内部读 `local` 时，
//   生产页面由 `_zoomHost` 的那层订阅兜底，独立宿主必须自己补，
//   否则「点翻页 / 收起队友」这类纯本地交互在测试里不会重建。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io' show File;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show RoomIntent;
import 'package:dice_realm/ui/room/room_keys.dart';
import 'package:dice_realm/ui/room/room_ui_local.dart' show BoardMode;
import 'package:dice_realm/ui/room/sheets/sheet_self_state.dart'
    show GpSelfStateKeys, kSelfStateInstantOp, kSelfStateNumbersOp;
import 'package:dice_realm/ui/room/view/member_view.dart'
    show bodyViewOf, isDown, memberStats, sanText;
import 'package:dice_realm/ui/room/view/room_view.dart'
    show findMe, memberOfSeat;
import 'package:dice_realm/ui/room/view/scene_view.dart' show boardCountOf;
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart'
    show GpPlCharCard, GpPlCharCardKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart'
    show GpPlMates, GpPlMatesKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_notes.dart'
    show GpPlNotes, GpPlNotesKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_sketch.dart'
    show GpPlSketch, GpPlSketchKeys, boardSegmentsFromRaw;
import 'package:dice_realm/ui/room/widgets/gp_scene_check_pl.dart'
    show GpSceneCheckPl, GpSceneCheckPlKeys;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 夹具 / 宿主
// ------------------------------------------------------------

/// 造一个「KP + p1 + p2 + sp1」的房间，两人各分享一张卡。
///
/// 不开团：本文件测的 5 个块都不分阶段（`meta.status` 只影响骨架重建），
/// 少跑两条 action 事件流，用例更快也更稳。
Future<RoomUiFixture> _boot(WidgetTester tester) async {
  final f = RoomUiFixture();
  await f.boot();
  useRoomScreen(tester, 800, 900);
  return f;
}

/// 独立宿主：作用域挂在 Navigator 之上（弹层也能 `RoomScope.of`）。
///
/// ★ 宿主**故意不订阅** `local`，也不包 `ListenableBuilder`：
///   「读本地态的块必须自己订阅」这条约束只能在没有父级兜底时被证明。
///   若宿主替块订阅，块内漏订阅也会假绿 —— 这一层必须保持朴素。
///   会话（`RoomSession`）变化由 `RoomScope` 这个 `InheritedNotifier` 照常送达。
Widget _hostApp(
  RoomUiFixture f,
  Widget Function() build, {
  String seat = 'p1',
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) =>
        f.scoped(seat, child: child ?? const SizedBox.shrink()),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: build(),
      ),
    ),
  );
}

/// 滚动到可见再点（块较长时按钮可能落在首屏之外）。
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// 弹层动画：不等待「一切都静止」，只推进到弹层可见为止。
Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// 改权威花名册里的某位成员，再重新同步给所有客户端。
///
/// 为什么不手改 `host.state`：权威端读的是 `roster`，改 state 不会下发；
/// 走 `roster` + `pullSync` 拿到的就是**真实裁剪结果**，与生产路径同源。
Future<void> _patchMember(
  RoomUiFixture f,
  String seat,
  void Function(Map<String, Object?> member) edit,
) async {
  final m = f.host.roster.get(seat);
  expect(m, isNotNull, reason: '花名册里没有 $seat');
  edit(m!);
  for (final s in f.clientSeats) {
    await f.kpSession.pullSync(s);
  }
}

/// 某视角里某座位的成员表（裁剪后）。
Map<String, Object?> _member(Map<String, Object?> state, String seat) =>
    asMap(memberOfSeat(state, seat));

/// 某成员卡的身体状态块（`sheet.status`）。
Map<String, Object?> _statusOf(Map<String, Object?> member) =>
    asMap(asMap(member['sheet'])['status']);

void main() {
  // ----------------------------------------------------------
  // 块 2：我的角色卡（P0-08）
  // ----------------------------------------------------------
  group('块 2 · 我的角色卡（P0-08）', () {
    testWidgets('★ 双源：HP / SAN 现值优先取 runtime，runtime 缺位才回落 sheet',
        (WidgetTester tester) async {
      final f = await _boot(tester);

      // sheet.status 里删掉现值（模拟「卡上只有初始值」），只留 runtime 的活值，
      // 同时在 sheet **顶层**放一份诱饵值（只在 status / runtime 都缺位时可读）。
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        final st = _statusOf(m);
        st.remove('currentHP');
        st.remove('currentSAN');
        final sheet = asMap(m['sheet']);
        sheet['hp'] = 99;
        sheet['san'] = 88;
        m['runtime'] = <String, Object?>{'hp': 7, 'san': 33};
      });

      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard()));
      await tester.pump();

      // runtime 赢：7 / 12（上限仍来自 status.maxHP），不是顶层诱饵 99
      expect(find.text('7 / 12'), findsOneWidget,
          reason: '★ runtime.hp 优先于 sheet 顶层旧字段');
      expect(find.text('99 / 12'), findsNothing);
      expect(find.text('33 / 99'), findsOneWidget,
          reason: '★ runtime.san 优先，上限取 status.maxSAN');

      // 再把 runtime 摘掉 → 逐项回落到 sheet 顶层（缺键 ≠ 0）
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        m.remove('runtime');
      });
      await tester.pump();
      expect(find.text('99 / 12'), findsOneWidget,
          reason: 'runtime 缺位时回落到 sheet 顶层 hp');
      expect(find.text('88 / 99'), findsOneWidget);
    });

    testWidgets('★ 状态行用 status.body 原始值：重伤 + 濒死 显示「重伤·濒死」',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        final st = _statusOf(m);
        st['body'] = '重伤';
        st['dying'] = true;
      });

      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard()));
      await tester.pump();

      final text =
          tester.widget<Text>(find.byKey(GpPlCharCardKeys.status)).data;
      expect(text, '重伤·濒死',
          reason: '★ 必须保留 body 原始值，不能把两档归一成「濒死」');

      // 反证：归一化的视图函数给出的确实是「濒死」——说明这里没走它
      final me = findMe(f.stateOf('p1'), 'p1');
      expect(bodyViewOf(me), '濒死');
    });

    testWidgets('★ 他人视图裁剪：maxSAN 被置 null → SAN 只显当前值（无斜杠）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final p2 = _member(f.stateOf('p1'), 'p2');

      // 结构证据：键就在裁剪时被写成 null，不是 UI 二次隐藏
      expect(asMap(p2['sheet']).containsKey('maxSAN'), isTrue);
      expect(asMap(p2['sheet'])['maxSAN'], isNull);

      final s = memberStats(p2);
      expect(s.hasMaxSan, isFalse);
      expect(sanText(s, full: true), 'SAN 57',
          reason: 'p2 的卡 currentSAN = 55 + 2');
      expect(sanText(s, full: true).contains('/'), isFalse,
          reason: '★ 他人视图不能出现「33/」这类上限后缀');
    });

    testWidgets('★ 没有角色卡的座位（旁观者）：明确说「没卡」，绝不画 0/0 空卡（K4 更严口径）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // 旁观者进了花名册，但从来没分享过卡 → sheet 为空
      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard(), seat: 'sp1'));
      await tester.pump();

      expect(asMap(asMap(_member(f.stateOf('sp1'), 'sp1'))['sheet']), isEmpty);
      // ★ P11 口径更新（用户 2026-11-11 真机报的「HP / MP / SAN 三个数值都是
      //   空的，显示成 -」）：以前这里画的是一张**空卡** —— 三条 ratio=0 的
      //   空进度条 + 「HP 0 / 0」，八项属性全「—」。那正是用户看到的那一屏，
      //   它把「没有卡」伪装成了「数值是 0」。
      //   现在缺键更彻底：**根本不画数值**，如实说没绑卡 ——
      //   这是 K4「缺键 ≠ 0」的最严形态（连 0 都不出现）。
      expect(find.byKey(GpPlCharCardKeys.unbound), findsOneWidget);
      expect(find.text('还没有绑定角色卡（等 KP 或房间页绑定）'), findsOneWidget);
      expect(find.text('STR —'), findsNothing,
          reason: '不再画一张属性全「—」的空卡（K4 从「显示 —」升级为「不显示数值」）');
      expect(find.text('HP'), findsNothing,
          reason: '★ 没有卡就没有数值条，绝不允许出现「HP 0 / 0」');
      expect(find.byKey(GpPlCharCardKeys.skill('侦查')), findsNothing,
          reason: '没有卡就没有技能行');
      expect(find.byKey(GpPlCharCardKeys.root), findsOneWidget);
    });

    testWidgets('★ T-20：撕卡后只剩聊天 —— 动作入口不渲染（不是禁用）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        _statusOf(m)['body'] = '死亡';
      });

      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard()));
      await tester.pump();

      expect(find.byKey(GpPlCharCardKeys.locked), findsOneWidget);
      expect(find.text('已撕卡 / 无法行动：只能聊天'), findsOneWidget);
      for (final k in <Key>[
        GpPlCharCardKeys.stateBtn,
        GpPlCharCardKeys.itemsBtn,
        GpPlCharCardKeys.aiBtn,
        RoomKeys.action('aid.apply'),
      ]) {
        expect(find.byKey(k), findsNothing,
            reason: '撕卡后该入口必须**不渲染**（T-30 的合法分支）');
      }
    });
  });

  // ----------------------------------------------------------
  // 块 8：队友（P1-04）
  // ----------------------------------------------------------
  group('块 8 · 队友（P1-04）', () {
    testWidgets('★ 只渲染裁剪视图：他人的 attrs / skills 在 p1 的 state 里根本不存在',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final p2Sheet = asMap(_member(f.stateOf('p1'), 'p2')['sheet']);

      expect(p2Sheet.containsKey('attrs'), isFalse,
          reason: '★ 他人 attrs 已被权威端裁剪掉（不是 UI 隐藏）');
      expect(p2Sheet.containsKey('skills'), isFalse);
      // 连字符串都搜不到：避免「藏在别的子键里」的假绿
      expect(jsonEncode(p2Sheet).contains('"attrs"'), isFalse);

      // 本人视图仍有全量卡（对照组：证明上面的缺失是裁剪造成的）
      final mine = asMap(_member(f.stateOf('p1'), 'p1')['sheet']);
      expect(mine.containsKey('attrs'), isTrue);
    });

    testWidgets('队友行：HP / SAN 只显当前值 + 精神计数 + 手绘板笔数',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // ★ P20 需求 3⑤：`RoomUiLocal.matesOpen` 默认已改成 **false**
      //   （dock 叠放里队友栏默认收起，让位给场景检定栏）。
      //   本用例测的是**列表内容**，不是收起语义 ⇒ 用 `forceOpen` 强制展开。
      await tester.pumpWidget(_hostApp(f, () => GpPlMates(forceOpen: true)));
      await tester.pump();

      expect(find.byKey(GpPlMatesKeys.root), findsOneWidget);
      expect(find.byKey(GpPlMatesKeys.row('p2')), findsOneWidget);
      expect(find.text('HP 12 · SAN 57'), findsOneWidget,
          reason: '裁剪视图只有当前值，没有「 / 上限」');

      final rowText = <String>[];
      for (final t in tester.widgetList<Text>(find.descendant(
        of: find.byKey(GpPlMatesKeys.row('p2')),
        matching: find.byType(Text),
      ))) {
        rowText.add(t.data ?? '');
      }
      expect(rowText.any((String s) => s.contains('精神：')), isTrue);
      expect(rowText.any((String s) => s.contains('手绘板 0 笔')), isTrue);
      expect(rowText.any((String s) => s.contains('/')), isFalse,
          reason: '整行都不许出现上限分隔符');
    });

    testWidgets('★ S5 判活守卫：hpMax <= 0（HP 未公开）不算倒下',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // p2 的 HP 上限整个键缺失 → hpMax 读成 0；HP 现值也是 0
      await _patchMember(f, 'p2', (Map<String, Object?> m) {
        final st = _statusOf(m);
        st.remove('maxHP');
        st['currentHP'] = 0;
        m.remove('runtime');
      });

      final p2 = _member(f.stateOf('p1'), 'p2');
      final s = memberStats(p2);
      expect(s.hpMax, 0);
      expect(isDown(p2), isFalse,
          reason: '★ hpMax <= 0 表示 HP 未公开，绝不能当「已倒下」');

      await tester.pumpWidget(_hostApp(f, () => GpPlMates(forceOpen: true)));
      await tester.pump();
      expect(find.text('HP 0 · SAN 57'), findsOneWidget,
          reason: '没有上限就不画上限，也不因为 hp=0 把行抹掉');

      // 对照：上限存在且 hp=0 → 才判倒下
      await _patchMember(f, 'p2', (Map<String, Object?> m) {
        _statusOf(m)['maxHP'] = 12;
      });
      expect(isDown(_member(f.stateOf('p1'), 'p2')), isTrue);
    });

    testWidgets('★ 收起 / 展开：点 toggle 后子树从有到空（块必须自己订阅 local）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // ★ P20 需求 3⑤：`RoomUiLocal.matesOpen` 默认已改成 **false**
      //   （dock 叠放里队友栏默认收起，让位给场景检定栏）。
      //   本用例验的正是**收起语义**，所以先把本地态打开，且
      //   **不许**用 `forceOpen: true` 绕过 —— 强制展开时收起按钮根本不渲染，
      //   那样等于把这个用例的证据力抽掉。
      f.localOf('p1').setMatesOpen(true);
      await tester.pumpWidget(_hostApp(f, () => GpPlMates()));
      await tester.pump();
      expect(find.byKey(GpPlMatesKeys.row('p2')), findsOneWidget);
      f.clearSent();

      // ★ 钉死「块不订阅 local 就红」：点击只改 `local`，没有 session 事件，
      //   父级也不会重建 —— 唯一能救活它的就是块内那层 ListenableBuilder。
      await _tap(tester, find.byKey(GpPlMatesKeys.toggle));
      expect(f.localOf('p1').matesOpen, isFalse);
      expect(find.byKey(GpPlMatesKeys.row('p2')), findsNothing,
          reason: '★ 收起后队友行必须消失（块内订阅 local 才会重画）');

      await _tap(tester, find.byKey(GpPlMatesKeys.toggle));
      expect(f.localOf('p1').matesOpen, isTrue);
      expect(find.byKey(GpPlMatesKeys.row('p2')), findsOneWidget);
      expect(f.sent, isEmpty, reason: '收起队友是本机 UI 态，零发包');
    });
  });

  // ----------------------------------------------------------
  // 块 10：我的手绘板（T-63）
  // ----------------------------------------------------------
  group('块 10 · 手绘板（T-63）', () {
    testWidgets('★ 落笔一次 INTENT.BOARD 全量：权威侧有值、他人视图无笔迹',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlSketch()));
      await tester.pump();
      f.clearSent();

      final center = tester.getCenter(find.byKey(GpPlSketchKeys.canvas));
      final start = center - const Offset(40, 0);
      final g = await tester.startGesture(start);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(start + Offset(i * 12.0, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();

      final boards =
          f.sent.where((Map<String, Object?> e) => e['op'] == RoomIntent.board).toList();
      expect(boards, hasLength(1), reason: '★ 手势末尾只发一次整份点集');
      final payload = asMap(boards.single['p']);
      // ★ P13 SKETCH：载荷允许分段 {id,pts} 或旧扁平点集，归一后按总点数断言。
      final List<Map<String, Object?>> segs =
          boardSegmentsFromRaw(asList(payload['strokes']));
      final int totalPoints = segs.fold<int>(
        0,
        (int n, Map<String, Object?> s) => n + asList(s['pts']).length,
      );
      expect(totalPoints, greaterThanOrEqualTo(2),
          reason: '★ 手势末尾整份提交，总点数 ≥2（分段/扁平口径等价）');
      for (final Map<String, Object?> s in segs) {
        for (final Object? raw in asList(s['pts'])) {
          final Map<String, Object?> q = asMap(raw);
          for (final String axis in <String>['x', 'y']) {
            final num v = q[axis] as num;
            expect(v, inInclusiveRange(0.0, 1.0), reason: '坐标必须归一化');
          }
        }
      }

      // ★ P13 SKETCH：后续笔数断言统一用归一后的总点数。
      final int strokePointCount = totalPoints;
      // 权威侧：boardBySeat 存整份笔迹（P13 后为分段），按归一总点数断言
      final List<Map<String, Object?>> hostSegs = boardSegmentsFromRaw(
        asList(asMap(f.host.boardBySeat['p1'])['strokes']),
      );
      expect(
        hostSegs.fold<int>(
          0,
          (int n, Map<String, Object?> s) => n + asList(s['pts']).length,
        ),
        strokePointCount,
      );
      final scene = asMap(f.hostState()['scene']);
      final summary = asMap(asMap(scene['boards'])['p1']);
      // ★ P13 段级存储：summary.count 记段数（旧扁平口径记点数）。
      expect(summary['count'], hostSegs.length);
      expect(summary.containsKey('strokes'), isFalse,
          reason: '摘要里不许带笔迹（只存 count / at / thumb）');

      // p2 视角：VIS.SEAT 只发给本人（其余人收 skip 水位），
      // 摘要晚一步从全量同步里拿到 —— 笔迹永远不出现。
      await f.kpSession.pullSync('p2');
      final p2State = f.stateOf('p2');
      expect(asMap(p2State['board']), isEmpty,
          reason: '★ 他人 state.board 恒空（K12 隔离）');
      expect(jsonEncode(asMap(p2State['board'])), '{}');
      expect(boardCountOf(p2State, 'p1'), hostSegs.length,
          reason: '摘要（笔数）可见，笔迹不可见');

      // 本人视角：同步后仍能看到自己的笔迹
      await f.kpSession.pullSync('p1');
      expect(
        boardSegmentsFromRaw(
          asList(asMap(f.stateOf('p1')['board'])['strokes']),
        ).length,
        hostSegs.length,
      );
    });

    testWidgets('★ 分页只在本机（local.boardPage），零发包', (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlSketch()));
      await tester.pump();
      f.clearSent();

      // U13：单页结构，翻页控件只作占位显示
      final page = tester.widget<Text>(find.byKey(GpPlSketchKeys.page));
      expect(page.data, '‹1/1›');

      await tester.tap(find.byKey(GpPlSketchKeys.page));
      await tester.pump();
      f.localOf('p1').setBoardPage(3);
      await tester.pump();

      expect(f.sent, isEmpty, reason: '★ 翻页纯本地：不产生任何 intent / action');
      expect(f.localOf('p1').boardPage, 3);
      expect(f.localOf('p2').boardPage, 0, reason: '每个座位各有一份本地态');
    });

    testWidgets('★ 点「笔 / 擦」后状态标签跟着变（块必须自己订阅 local）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlSketch()));
      await tester.pump();

      String label() =>
          tester.widget<Text>(find.byKey(GpPlSketchKeys.locked)).data ?? '';
      expect(label(), startsWith('画笔'),
          reason: 'BoardMode.draw 是默认值');

      // ★ 钉死「块不订阅 local 就红」：点按钮只改 `local.boardMode`，
      //   既没有 session 事件、父级也不重建。
      await _tap(tester, find.byKey(GpPlSketchKeys.erase));
      expect(f.localOf('p1').boardMode, BoardMode.erase);
      expect(label(), startsWith('橡皮'),
          reason: '★ 切到橡皮后标签必须立刻变（块内订阅 local 才会重画）');

      await _tap(tester, find.byKey(GpPlSketchKeys.draw));
      expect(f.localOf('p1').boardMode, BoardMode.draw);
      expect(label(), startsWith('画笔'));
    });

    testWidgets('★ T-20：撕卡后画布不收手势、画笔 / 橡皮 / 清空都不渲染',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        _statusOf(m)['dying'] = true;
      });
      await tester.pumpWidget(_hostApp(f, () => GpPlSketch()));
      await tester.pump();

      expect(find.text('已撕卡：手绘板不可用'), findsOneWidget);
      for (final k in <Key>[
        GpPlSketchKeys.draw,
        GpPlSketchKeys.erase,
        GpPlSketchKeys.clear,
      ]) {
        expect(find.byKey(k), findsNothing);
      }

      f.clearSent();
      final center = tester.getCenter(find.byKey(GpPlSketchKeys.canvas));
      final g = await tester.startGesture(center - const Offset(40, 0));
      for (var i = 1; i <= 4; i++) {
        await g.moveTo(center - const Offset(40, 0) + Offset(i * 12.0, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();
      expect(f.sent, isEmpty, reason: '撕卡后画布不收手势 → 一个包都不发');
    });

    testWidgets('手绘板清空：连点两次才提交（ConfirmTwice），一次全量置空',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      // 先垫一份已有笔迹（走真实 intent，不手改权威态）
      await f.sessionOf('p1').sendIntent(RoomIntent.board, <String, Object?>{
        'strokes': <Object?>[
          <String, Object?>{'x': 0.2, 'y': 0.3},
          <String, Object?>{'x': 0.4, 'y': 0.5},
        ],
      });
      await tester.pumpWidget(_hostApp(f, () => GpPlSketch()));
      await tester.pump();
      f.clearSent();

      // 第一次点只是「上膛」，不发包
      await _tap(tester, find.byKey(GpPlSketchKeys.clear));
      expect(f.sent, isEmpty, reason: '第一次点击只上膛');
      expect(find.text('再点一次确认'), findsOneWidget);

      await _tap(tester, find.byKey(GpPlSketchKeys.clear));
      final clears =
          f.sent.where((Map<String, Object?> e) => e['op'] == RoomIntent.board).toList();
      expect(clears, hasLength(1));
      expect(asList(asMap(clears.single['p'])['strokes']), isEmpty,
          reason: '清空 = 提交一份空点集（全量替换）');
      expect(asMap(f.host.boardBySeat['p1'])['strokes'], isEmpty);
    });
  });

  // ----------------------------------------------------------
  // 块 11：我的笔记（P1-05）
  // ----------------------------------------------------------
  group('块 11 · 我的笔记（P1-05）', () {
    testWidgets('★ 纯本机：新增零发包，且重建后仍在（持久到 RoomNotesStore）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlNotes()));
      await tester.pump();

      expect(find.byKey(GpPlNotesKeys.empty), findsOneWidget);
      f.clearSent();

      await tester.enterText(find.byKey(GpPlNotesKeys.input), '门后有东西');
      await tester.pump();
      await _tap(tester, find.byKey(GpPlNotesKeys.add));
      await tester.pump();

      expect(find.text('门后有东西'), findsOneWidget);
      expect(f.sent, isEmpty, reason: '★ 笔记不上传、不进权威态、不发包');
      expect(asList(f.stateOf('p1')['chats']), isEmpty);

      // 整棵子树丢掉再重建 → 数据来自 store，不是 State 里的草稿
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(_hostApp(f, () => GpPlNotes()));
      await tester.pump();
      await tester.pump();
      expect(find.text('门后有东西'), findsOneWidget,
          reason: '★ 重建后仍在（键 = 房间号 + 座位）');

      // 别的座位看不到（本机私有，K12）
      final other = await f.notes.load(f.sessionOf('p1').code, 'p2');
      expect(other, isEmpty);
    });

    testWidgets('删除一条：列表回到空态，同样零发包', (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlNotes()));
      await tester.pump();

      await tester.enterText(find.byKey(GpPlNotesKeys.input), '甲');
      await _tap(tester, find.byKey(GpPlNotesKeys.add));
      await tester.pump();
      await tester.enterText(find.byKey(GpPlNotesKeys.input), '乙');
      await _tap(tester, find.byKey(GpPlNotesKeys.add));
      await tester.pump();
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('乙'), findsOneWidget);
      f.clearSent();

      // 删掉「甲」：行内唯一一个删除按钮
      final del = find.descendant(
        of: find.byKey(GpPlNotesKeys.list),
        matching: find.byIcon(Icons.delete_outline),
      );
      expect(del, findsNWidgets(2));
      await _tap(tester, del.first);

      expect(find.text('甲'), findsNothing);
      expect(find.text('乙'), findsOneWidget);
      expect(f.sent, isEmpty);
    });
  });

  // ----------------------------------------------------------
  // 状态管理弹层（Q-P5-3）
  // ----------------------------------------------------------
  group('状态管理弹层 · Q-P5-3 文案与生效路径', () {
    testWidgets('★ 数值走 state.edit.self → 进 KP 待确认队列，不乐观生效',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard()));
      await tester.pump();
      f.clearSent();

      await _tap(tester, find.byKey(GpPlCharCardKeys.stateBtn));
      await _pumpSheet(tester);
      expect(find.byKey(GpSelfStateKeys.root), findsOneWidget);
      expect(find.text('数值（HP / MP / SAN）：需 KP 同意后才能生效'), findsOneWidget);

      await tester.enterText(find.byKey(GpSelfStateKeys.hp), '5');
      await tester.pump();
      await _tap(tester, find.byKey(GpSelfStateKeys.submitNumbers));
      await _pumpSheet(tester);

      final last = f.sent.last;
      expect(last['kind'], 'action', reason: '★ ACTION 通道（外层 ACT 信封）');
      expect(last['op'], kSelfStateNumbersOp);
      final p = asMap(last['p']);
      expect(p['op'], kSelfStateNumbersOp, reason: '内层仍带 op（双层信封）');
      expect(asMap(p['status'])['currentHP'], 5);

      // 不乐观：权威态没变，请求躺在 pending 里等 KP
      expect(f.host.pending, hasLength(1));
      expect(f.host.pending.single['op'], kSelfStateNumbersOp);
      expect(f.host.pending.single['by'], 'p1');
      expect(f.host.pending.single['need'], 'kp');
      expect(_statusOf(_member(f.stateOf('p1'), 'p1'))['currentHP'], 12,
          reason: '★ 提交后不能直接改数（不能乐观提示成功）');
      expect(f.localOf('p1').notice, '已提交，需 KP 同意后生效');
    });

    testWidgets('身体状态走 state.self → 立即生效（不进队列）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard()));
      await tester.pump();

      await _tap(tester, find.byKey(GpPlCharCardKeys.stateBtn));
      await _pumpSheet(tester);
      expect(find.text('身体状态：立即生效'), findsOneWidget);
      f.clearSent();

      await _tap(tester, find.byKey(GpSelfStateKeys.body('轻伤')));
      await _pumpSheet(tester);

      expect(f.lastSent(action: kSelfStateInstantOp), isNotNull);
      expect(_statusOf(_member(f.stateOf('p1'), 'p1'))['body'], '轻伤',
          reason: '★ confirm 为 null → 立即写进权威态');
      expect(f.host.pending, isEmpty, reason: '立即生效类请求不进待确认队列');
      expect(f.localOf('p1').notice, '身体状态已更新（立即生效）');
    });

    testWidgets('精神状态走 state.self → 立即生效并出现在卡片视图里',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard()));
      await tester.pump();

      await _tap(tester, find.byKey(GpPlCharCardKeys.stateBtn));
      await _pumpSheet(tester);
      expect(
          find.textContaining('精神状态：立即生效'), findsOneWidget);
      f.clearSent();

      await _tap(tester, find.byKey(GpSelfStateKeys.mental('临时疯狂')));
      await _pumpSheet(tester);

      expect(f.lastSent(action: kSelfStateInstantOp), isNotNull);
      final sheet = asMap(_member(f.stateOf('p1'), 'p1')['sheet']);
      expect(asList(sheet['mental']).map(jsStr).toList(), contains('临时疯狂'));
      expect(f.host.pending, isEmpty);
    });

    testWidgets('★ 文案不许出现「不需要 KP 同意」这类误导句',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpPlCharCard()));
      await tester.pump();

      await _tap(tester, find.byKey(GpPlCharCardKeys.stateBtn));
      await _pumpSheet(tester);

      // 逐条 Text 检查（不只查可见屏）：文案口径是 Q-P5-3 的唯一出口
      final texts = <String>[
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          t.data ?? t.textSpan?.toPlainText() ?? '',
      ];
      expect(texts, isNotEmpty);
      for (final s in texts) {
        expect(s.contains('不需要 KP 同意'), isFalse, reason: '误导句：$s');
        expect(s.contains('不需要KP同意'), isFalse, reason: '误导句：$s');
        expect(s.contains('无需 KP'), isFalse, reason: '误导句：$s');
      }
      // 正面口径必须在
      expect(texts.any((String s) => s.contains('需 KP 同意')), isTrue);
      expect(texts.any((String s) => s.contains('立即生效')), isTrue);
    });
  });

  // ----------------------------------------------------------
  // 块 7：玩家场景检定（T-23）
  // ----------------------------------------------------------
  group('块 7 · 场景检定（T-23 / 只读 + 主动检定）', () {
    testWidgets('★ 玩家侧零裁定 / 推送按钮', (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpSceneCheckPl()));
      await tester.pump();

      expect(find.byKey(GpSceneCheckPlKeys.root), findsOneWidget);
      expect(find.byKey(RoomKeys.kpScenePush), findsNothing,
          reason: '★ T-23：裁定 / 推送是 KP 专属，玩家侧连控件都不渲染');
      // 只读展示区在，但还没有步骤 → 空态文案
      expect(find.byKey(GpSceneCheckPlKeys.progress), findsOneWidget);
      expect(find.byKey(GpSceneCheckPlKeys.empty), findsOneWidget);
      expect(find.text('KP 还没有推送场景检定'), findsOneWidget);
    });

    testWidgets('用自己技能发起检定：载荷走骰子 intent，也不自报技能值',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_hostApp(f, () => GpSceneCheckPl()));
      await tester.pump();
      f.clearSent();

      await _tap(tester, find.byKey(GpSceneCheckPlKeys.skill('侦查')));
      await _tap(tester, find.byKey(GpSceneCheckPlKeys.roll));

      final dice = f.sent
          .where((Map<String, Object?> e) => e['op'] == RoomIntent.dice)
          .toList();
      expect(dice, hasLength(1));
      final p = asMap(dice.single['p']);
      expect(p['expr'], '1D100');
      expect(p['direct'], isTrue);
      expect(p['skill'], '侦查');
      expect(p['label'], '侦查');
      expect(p.containsKey('base'), isFalse,
          reason: '★ 技能值由权威端 skillBaseOf 取，客户端不自报');
      // 更不许冒充 KP 推步骤
      expect(
        f.sent.where((Map<String, Object?> e) =>
            asMap(e['p'])['op'] == 'scene.check.step' ||
            asMap(e['p'])['op'] == 'scene.check.push'),
        isEmpty,
      );
    });

    testWidgets('撕卡后不渲染「用我的技能检定」（T-20）',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await _patchMember(f, 'p1', (Map<String, Object?> m) {
        _statusOf(m)['unconscious'] = true;
      });
      await tester.pumpWidget(_hostApp(f, () => GpSceneCheckPl()));
      await tester.pump();

      expect(find.byKey(GpSceneCheckPlKeys.locked), findsOneWidget);
      expect(find.byKey(GpSceneCheckPlKeys.roll), findsNothing);
      expect(find.byKey(GpSceneCheckPlKeys.skill('侦查')), findsNothing);
    });
  });

  // ----------------------------------------------------------
  // 门禁旁证：这 5 块全是「只画 + 只发 intent」
  // ----------------------------------------------------------
  group('只画不写权威态', () {
    testWidgets('五个块静态渲染都不产生任何发包', (WidgetTester tester) async {
      final f = await _boot(tester);
      f.clearSent();
      for (final build in <Widget Function()>[
        () => GpPlCharCard(),
        () => GpPlMates(),
        () => GpPlSketch(),
        () => GpPlNotes(),
        () => GpSceneCheckPl(),
      ]) {
        await tester.pumpWidget(_hostApp(f, build));
        await tester.pump();
        await tester.pump();
      }
      expect(f.sent, isEmpty, reason: '渲染本身零发包');
      expect(f.host.pending, isEmpty);
    });
  });

  // ----------------------------------------------------------
  // 机械门禁（T05 的 7 个文件；与 T04 的同类用例同口径）
  // ----------------------------------------------------------
  group('门禁 · T05 文件零命中', () {
    test('7 个文件纯净：零权威端引用、零规则调用、零死代码名、零占位块', () {
      const files = <String>[
        'widgets/gp_pl_char_card.dart',
        'widgets/gp_pl_mates.dart',
        'widgets/gp_pl_notes.dart',
        'widgets/gp_pl_sketch.dart',
        'widgets/gp_scene_check_pl.dart',
        'sheets/sheet_self_state.dart',
        'room_game_page.dart',
      ];
      const banned = <String>[
        'RoomHost',
        'rules?.check(',
        'rollExpr(',
        'opposedFull(',
        'plBottomBar',
        'plFeeds',
        'kpChat',
        'kpGameLog',
      ];
      expect(files.length, 7, reason: 'T05 应覆盖 6 个新块文件 + 页面壳体');
      for (final rel in files) {
        final src = File('lib/ui/room/$rel').readAsStringSync();
        for (final word in banned) {
          expect(src.contains(word), isFalse,
              reason: '$rel 命中门禁字面量 $word');
        }
        // K-01：T05 收尾后页面壳体已无占位块
        expect(src.contains('PlaceholderBlock'), isFalse,
            reason: '$rel 仍残留占位块');
        // 注释里不许出现框架 / IO 库的导入字面量（机械门禁是朴素 grep）
        for (final line in src.split('\n')) {
          if (!line.trimLeft().startsWith('//')) continue;
          for (final word in <String>[
            'package:flutter',
            'dart:io',
            'dart:ui',
          ]) {
            expect(line.contains(word), isFalse, reason: '$rel 注释命中 $word');
          }
        }
        // 权威快照赋值（形如 state[...] = ）在本层零出现
        expect(RegExp(r'state\s*\[[^\]]+\]\s*=').hasMatch(src), isFalse,
            reason: '$rel 出现权威快照赋值');
      }
    });
  });
}
