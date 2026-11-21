// ============================================================
// test/p10_t6_room_fixes_test.dart — P10 第 6 期（五项修复，按 1–5 分组）
//
// 1 大厅预览角色 → 完整人物卡弹层（跨设备 sheet，不画假 0 卡）
// 2 「潜在疯狂」是**刻意不显示的派生状态**，后台判定链核实（确认项，不改 UI）
// 3 手机竖屏顶栏 / 工具栏几何 + 战技按钮真修复
// 4 KP 平板横屏参考图重排几何 + 对抗按钮真修复
// 5 推送请求居中弹窗（全局监听 / 去重 / 跨视角 / 秘密口径）
//
// ★ T1：全内存后端（RoomUiFixture），零真实 I/O；几何一律用 getRect 实测。
// ★ 所有 flutter test 必须带 NO_PROXY（环境代理会拦 localhost WebSocket）。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io' show File;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/madness_state.dart'
    show
        isPotentialMadness,
        kMentalIndefinite,
        kMentalNormalState,
        kMentalPotential,
        kMentalTemporary,
        nextMentalState,
        normalizeMentalList,
        MentalEvent;
import 'package:dice_realm/domain/room_types.dart'
    show RoomIntent, kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/room_request_watcher.dart'
    show RoomPushKeys, RoomPushReply, collectRoomPushRequests;
import 'package:dice_realm/ui/room/sheets/sheet_char_view.dart'
    show CharViewKeys;
import 'package:dice_realm/ui/room/sheets/sheet_opposed.dart'
    show OpposedSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_self_state.dart'
    show kSelfMentalValues;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show RoomSheet, RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 作用域挂在 Navigator 之上：页面与弹层都能拿到 RoomScope。
Widget _app(RoomUiFixture f, String seat, Widget body) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) =>
          f.scoped(seat, child: child ?? const SizedBox.shrink()),
      home: body,
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

/// 由**玩家自己的视角**上报一张带全部公开字段的房卡（模拟另一台设备绑卡）。
/// `shareSheets()` 的夹具卡只有数值/技能，这里补上基本资料 / 背景 / 经历 /
/// 装备资产 / 教育进步，走真实 `INTENT.CHAR` → `sanitizeSheet` 白名单。
Future<void> _reportFullSheet(RoomUiFixture f, String seat) async {
  final sheet = <String, Object?>{
    'name': '完整测试卡',
    'attrs': <String, Object?>{
      'str': 50,
      'con': 45,
      'siz': 60,
      'dex': 55,
      'app': 50,
      'int': 70,
      'pow': 60,
      'edu': 65,
    },
    'status': <String, Object?>{
      'currentHP': 12,
      'maxHP': 12,
      'currentMP': 10,
      'maxMP': 10,
      'currentSAN': 55,
      'maxSAN': 99,
      'body': '正常',
    },
    'skills': <Object?>[
      <String, Object?>{'name': '侦查', 'total': 70},
    ],
    'items': <Object?>[
      <String, Object?>{'id': 'i1', 'name': '测试物品', 'qty': 2},
    ],
    'weapons': <Object?>[
      <String, Object?>{'name': '测试武器', 'damage': '1D6'},
    ],
    'gender': '女',
    'age': 30,
    'era': '1920s',
    'residence': '测试居所',
    'birthplace': '测试籍贯',
    'occupation': '侦探',
    'world': '测试世界',
    'look': '测试外貌',
    'background': <String, Object?>{
      'ideology': '测试信念',
      'significantPeople': '测试重要之人',
      'meaningfulPlaces': '测试地点',
      'treasuredPossessions': '测试珍宝',
      'traits': '测试特质',
      'wounds': '测试伤痕',
      'phobias': '测试恐惧',
    },
    'history': <Object?>[
      <String, Object?>{
        'title': '测试经历',
        'description': '测试经历正文',
        'date': '1925',
        'notes': '测试备注',
      },
    ],
    'armors': <Object?>[
      <String, Object?>{'name': '测试防具'},
    ],
    'assets': <String, Object?>{
      'creditRating': 40,
      'cash': 100,
      'spendingLevel': '普通',
      'currency': '元',
      'assetsDescription': '测试资产说明',
    },
    'eduProgress': <String, Object?>{
      'log': <Object?>[
        <String, Object?>{'ok': true},
      ],
      'bonus': 5,
    },
  };
  await f.plSessions[seat]!.sendIntent(
    RoomIntent.char,
    <String, Object?>{
      'id': 'c_full_$seat',
      'name': '完整测试卡',
      'sheet': sheet,
    },
  );
}

Map<String, Object?> _memberSheet(RoomUiFixture f, String viewSeat, String target) {
  for (final raw in asList(f.stateOf(viewSeat)['members'])) {
    final m = asMap(raw);
    if (jsStr(m['seat']) == target) return asMap(m['sheet']);
  }
  return const <String, Object?>{};
}

void main() {
  // ========================================================
  // 1 · 大厅「预览角色」= 完整人物卡
  // ========================================================
  group('1 · 大厅预览角色（跨设备 / 全部信息 / 无卡兜底）', () {
    testWidgets('1A ★ KP 点玩家预览 → 完整人物卡弹层，跨设备上报字段全可见',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(withSheets: false);
      await _reportFullSheet(f, 'p1');

      // 前置：字段来自权威端 state 的 sheet（别的设备上报），不是本机卡文件。
      final sh = _memberSheet(f, kHostSeat, 'p1');
      for (final k in <String>[
        'gender', 'age', 'occupation', 'background', 'history',
        'assets', 'eduProgress', 'attrs', 'skills', 'items', 'weapons',
      ]) {
        expect(sh.containsKey(k), isTrue, reason: 'KP 视角应看得到 $k');
      }
      expect(jsonEncode(sh).contains('测试信念'), isTrue);
      // 私密字段不该出现在广播 sheet 里
      expect(sh.containsKey('privates'), isFalse);
      expect(sh.containsKey('p'), isFalse);

      useRoomScreen(tester, 900, 1600);
      await tester.pumpWidget(
          _app(f, kHostSeat, const Scaffold(body: RoomLobbyPage())));
      await _settle(tester);

      await tester.ensureVisible(find.byKey(RoomLobbyKeys.memberDetail('p1')));
      await tester.pump();
      await tester.tap(find.byKey(RoomLobbyKeys.memberDetail('p1')));
      await _settle(tester);

      expect(find.byKey(CharViewKeys.root), findsOneWidget,
          reason: '★ 必须接上 P10-1 的完整人物卡弹层，不是三行简要状态');
      for (final k in <Key>[
        CharViewKeys.status,
        CharViewKeys.basics,
        CharViewKeys.vitals,
        CharViewKeys.attrs,
        CharViewKeys.skills,
        CharViewKeys.background,
        CharViewKeys.history,
        CharViewKeys.mental,
        CharViewKeys.temp,
        CharViewKeys.items,
        CharViewKeys.weapons,
        CharViewKeys.assets,
        CharViewKeys.education,
        CharViewKeys.madness,
      ]) {
        expect(find.byKey(k), findsOneWidget, reason: '$k 应在完整卡里');
      }
      // 只数弹层里的文本（成员行 / 页面其它块可能有同名字段）。
      final sheetBody = find.byType(RoomSheet);
      expect(
        find.descendant(
            of: sheetBody, matching: find.textContaining('测试信念')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: sheetBody, matching: find.text('测试经历（1925）')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: sheetBody, matching: find.textContaining('测试资产说明')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: sheetBody, matching: find.textContaining('教育进步检定')),
        findsOneWidget,
      );
      // 弹层走 showRoomSheet ⇒ 外层自带可滚动容器（超屏不截断）
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1B 没绑卡 → 如实「未绑卡」，不画一张假 0 卡（P12 不回退）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(withSheets: false);
      useRoomScreen(tester, 900, 1600);
      await tester.pumpWidget(
          _app(f, kHostSeat, const Scaffold(body: RoomLobbyPage())));
      await _settle(tester);

      await tester.ensureVisible(find.byKey(RoomLobbyKeys.memberDetail('p1')));
      await tester.pump();
      await tester.tap(find.byKey(RoomLobbyKeys.memberDetail('p1')));
      await _settle(tester);

      expect(
        find.descendant(
            of: find.byType(RoomSheet), matching: find.text('未绑卡')),
        findsOneWidget,
      );
      expect(find.byKey(CharViewKeys.root), findsNothing,
          reason: '无卡时不该把一堆 0 拼成完整卡');
    });
  });

  // ========================================================
  // 2 · 「潜在疯狂」= 刻意不显示的派生状态（确认项，UI 零改动）
  // ========================================================
  group('2 · 潜在疯狂后台判定链核实（确认项）', () {
    test('2A 状态管理只给 3 个手动项，不含「潜在疯狂」', () {
      expect(kSelfMentalValues, <String>['正常', '临时疯狂', '不定疯狂']);
      expect(kSelfMentalValues.contains(kMentalPotential), isFalse);
      final src = File('lib/ui/room/sheets/sheet_self_state.dart')
          .readAsStringSync();
      expect(src.contains('潜在疯狂'), isFalse,
          reason: '用户确认「不需要显示」，UI 不许加这个按钮');
    });

    test('2B 派生状态机完整：不定疯狂消退→潜在→掉 SAN 复发→治愈清除', () {
      // 归一化：不定与潜在互斥，保重的那一个
      expect(normalizeMentalList(<Object?>[kMentalIndefinite, kMentalPotential]),
          <String>[kMentalIndefinite]);
      expect(normalizeMentalList(<Object?>[kMentalNormalState, kMentalTemporary]),
          <String>[kMentalNormalState]);
      expect(isPotentialMadness(<Object?>[kMentalPotential]), isTrue);
      expect(isPotentialMadness(<Object?>[kMentalNormalState]), isFalse);

      // ① 不定疯狂症状消退 → 潜在疯狂
      final faded = nextMentalState(
        <Object?>[kMentalIndefinite],
        MentalEvent.symptomFaded,
        fromIndefinite: true,
      );
      expect(faded.hasPotential, isTrue);
      expect(faded.hasIndefinite, isFalse);

      // ② 潜在疯狂 + 掉 SAN → 不定疯狂 + 必须新生成症状
      final relapse = nextMentalState(faded.mental, MentalEvent.sanLost);
      expect(relapse.hasIndefinite, isTrue);
      expect(relapse.hasPotential, isFalse);
      expect(relapse.spawnSymptom, isTrue);

      // ③ 治愈 → 正常
      final cured = nextMentalState(faded.mental, MentalEvent.cured);
      expect(cured.mental, <String>[kMentalNormalState]);

      // ④ 临时疯狂消退 → 回正常，不产生潜在疯狂
      final tempFaded = nextMentalState(
        <Object?>[kMentalTemporary],
        MentalEvent.symptomFaded,
      );
      expect(tempFaded.hasPotential, isFalse);
      expect(tempFaded.mental, <String>[kMentalNormalState]);
    });

    test('2C 玩家手动切「正常/临时/不定」不会凭空派生出潜在疯狂', () {
      for (final v in kSelfMentalValues) {
        final normalized = normalizeMentalList(<Object?>[v]);
        expect(isPotentialMadness(normalized), isFalse, reason: v);
      }
      // 后台判定的关键闸门仍在（P10-3A / 3B 修过的两处）
      final sheet = File('lib/domain/room_model_actions_sheet.dart')
          .readAsStringSync();
      expect(sheet.contains('loss >= 5 && !isPotential'), isTrue,
          reason: 'P10-3B：单次 ≥5 且非潜在才走临时疯狂 INT 检定');
      expect(sheet.contains('fadedArm[seat] != false'), isTrue,
          reason: '复发武装开关');
      expect(sheet.contains('MentalEvent.symptomFaded'), isTrue,
          reason: '轮次消退经唯一状态机');
      final core = File('lib/domain/room_model_host_core.dart')
          .readAsStringSync();
      expect(core.contains('mental_state.isPotentialMadness'), isTrue,
          reason: 'P10-3A：回合边界 disarm 用状态机判据，兼容新旧取值');
    });
  });

  // ========================================================
  // 3/4 · 战技 / 对抗按钮真修复（KP 与玩家两条路径）
  // ========================================================
  group('3 · 战技按钮：点了要有可见骰点（KP + 玩家）', () {
    for (final seat in <String>[kHostSeat, 'p1']) {
      testWidgets('3A[$seat] 点战技 → INTENT.DICE direct 带默认参数 → 公共骰点',
          (WidgetTester tester) async {
        final f = RoomUiFixture();
        await f.boot(inGame: true);
        useRoomScreen(tester, 900, 1600);
        await tester.pumpWidget(
            _app(f, seat, const Scaffold(body: RoomGamePage())));
        await _settle(tester);

        final btn = find.byKey(RoomKeys.action('combat.roll'));
        expect(btn, findsOneWidget, reason: '$seat 应有战技按钮');

        f.clearSent();
        final before = asList(f.hostState()['dice']).length;
        await tester.ensureVisible(btn);
        await tester.pump();
        await tester.tap(btn);
        await tester.pump();

        final intent = f.lastSent(op: RoomIntent.dice);
        expect(intent, isNotNull, reason: '$seat 点了必须真的发出意图');
        expect(intent!['kind'], 'intent');
        final p = asMap(intent['p']);
        expect(p['direct'], true);
        expect(p['expr'], '1D100');
        expect(p['label'], '战技');
        expect(p['skill'], '战技');

        // ★ 可见反馈：权威端真掷出一颗带 total 的公共骰
        final dice = asList(f.hostState()['dice']);
        expect(dice.length, greaterThan(before),
            reason: '$seat 战技必须产生公共 DICE 记录（不许点了没反应）');
        final last = asMap(dice.last);
        expect(last['total'], isNotNull);
        expect(jsStr(last['label']), '战技');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('3B 旁观者视角没有战技按钮（POLICY 边界不变）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);
      await tester.pumpWidget(
          _app(f, 'sp1', const Scaffold(body: RoomGamePage())));
      await _settle(tester);
      expect(find.byKey(RoomKeys.action('combat.roll')), findsNothing);
    });
  });

  group('4 · 对抗按钮：打开对象选择弹层，不再发空 action', () {
    testWidgets('4A KP 点对抗 → 打开 OpposedSheet；零空 action',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(
          _app(f, kHostSeat, const Scaffold(body: RoomGamePage())));
      await _settle(tester);

      final btn = find.byKey(RoomKeys.action('check.opposed'));
      expect(btn, findsOneWidget);
      f.clearSent();
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await _settle(tester);

      expect(find.byKey(OpposedSheetKeys.root), findsOneWidget,
          reason: '★ 正确入口是能选双方的对抗弹层');
      expect(f.lastSent(action: 'check.opposed'), isNull,
          reason: '不许再发空 check.opposed → 「甲方无效」');
      expect(tester.takeException(), isNull);
    });

    testWidgets('4B 玩家视角：骰子条 KP 对抗入口仍隐藏，但玩家已有独立「主动对抗」权限与入口',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(
          _app(f, 'p1', const Scaffold(body: RoomGamePage())));
      await _settle(tester);
      // 结构层：骰子条的 KP 裁定入口（R1 门控 `isKp && gate.can`）仍不渲染 —— 逐字保留。
      expect(find.byKey(RoomKeys.action('check.opposed')), findsNothing);
      // ★ PV-1b：roles 放宽为 [kp, player] + RoomConfirm.kp，玩家权限由 false 变 true
      //   （产品契约真变；旧口径「POLICY = [kp]」已不成立）。
      expect(f.controllerOf('p1').gate.can('check.opposed'), isTrue,
          reason: 'PV-1b：玩家可发起对抗，走 RoomConfirm.kp 审批');
      // 正向：玩家独占的「主动对抗」入口确实渲染且可点。
      expect(find.byKey(RoomGamePage.playerOpposedKey), findsOneWidget,
          reason: '玩家应有独立的「主动对抗」入口按钮');
      expect(
          tester
              .widget<RoomTap>(find.byKey(RoomGamePage.playerOpposedKey))
              .enabled,
          isTrue);
    });
  });

  // ========================================================
  // 5 · 推送要求居中弹窗（接线 / 内容 / 可直接操作 / 去重 / 私密 / 双路径）
  // ========================================================
  group('5 · 推送请求：屏幕正中弹窗，可直接同意 / 拒绝', () {
    /// 造一条「KP 定向推送给 [target] 的状态变更请求」。
    ///
    /// 走真实 `INTENT.ACT → state.request → emit(EVT.REQUEST, vis=seat,
    /// to=target)`；`LocalLoopbackSession.pumpPlans` 再按 `to` 把权威端产出的
    /// 真实 `SendPlan` 分发进各 `RoomClient.receive()`（'*' 全员 / 其余单发）。
    /// [secret] 放在 reason 里，用于验「整份 state 搜不到私密内容」。
    Future<void> pushRequest(
      RoomUiFixture f,
      String target,
      String secret,
    ) async {
      await f.controllerOf(kHostSeat).hostAction(
            'state.request',
            <String, Object?>{
              'seat': target,
              'change': <String, Object?>{},
              'reason': secret,
            },
          );
    }

    /// 与 `_app` 等价，但 root 带 key：切视角时整树重建（含 Navigator），
    /// 保证上一个视角的弹窗 route 不残留、watcher State 从头初始化。
    Widget appKeyed(RoomUiFixture f, String seat, String tag, Widget body) =>
        MaterialApp(
          key: ValueKey<String>('p10t6-5e/$tag'),
          theme: ThemeData.dark(useMaterial3: true),
          builder: (BuildContext _, Widget? child) =>
              f.scoped(seat, child: child ?? const SizedBox.shrink()),
          home: body,
        );

    /// 挂好页面并跑到稳定帧（每个视角各自先挂载，再到达新请求）。
    Future<void> mountRoom(
      WidgetTester tester,
      RoomUiFixture f,
      String seat,
    ) async {
      await tester.pumpWidget(
          _app(f, seat, const Scaffold(body: RoomGamePage())));
      await _settle(tester);
    }

    testWidgets('5A 新请求到达 → 屏幕正中弹窗，标题与详情（含说明）可读',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);
      await mountRoom(tester, f, 'p1');

      const secret = '仅p1可见的推送说明AAA';
      await pushRequest(f, 'p1', secret);
      await _settle(tester);

      expect(find.byKey(RoomPushKeys.root), findsOneWidget,
          reason: '★ 新请求必须直接弹屏幕正中，而不是只在状态条里多一张卡');
      expect(find.byKey(RoomPushKeys.title), findsOneWidget);
      expect(find.byKey(RoomPushKeys.details), findsOneWidget);
      expect(find.byKey(RoomPushKeys.agree), findsOneWidget);
      expect(find.byKey(RoomPushKeys.reject), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(RoomPushKeys.details),
            matching: find.textContaining(secret)),
        findsOneWidget,
        reason: '详情要显示说明，不能只显示一个 id',
      );
      expect(
        find.descendant(
            of: find.byKey(RoomPushKeys.details),
            matching: find.textContaining('发起人')),
        findsWidgets,
        reason: '详情要显示谁发起',
      );

      // 几何实测：屏幕逻辑尺寸 900×1600，中心 (450, 800)。
      final rect = tester.getRect(find.byKey(RoomPushKeys.root));
      expect(rect.center.dx, closeTo(450.0, 32.0), reason: '水平必须居中');
      expect(rect.center.dy, closeTo(800.0, 32.0), reason: '垂直必须居中');
      expect(rect.width, lessThanOrEqualTo(340.0), reason: '窄屏不溢出');
      expect(tester.takeException(), isNull);
    });

    testWidgets('5B 点同意 → INTENT.CONSENT{agree:true} 且弹窗消失',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);
      await mountRoom(tester, f, 'p1');
      await pushRequest(f, 'p1', '5B同意说明');
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsOneWidget);

      f.clearSent();
      await tester.tap(find.byKey(RoomPushKeys.agree));
      await _settle(tester);

      final intent = f.lastSent(op: RoomIntent.consent);
      expect(intent, isNotNull, reason: '点同意必须真的发出意图');
      expect(intent!['kind'], 'intent');
      final p = asMap(intent['p']);
      expect(p['agree'], true);
      expect(p['id'], isA<String>());
      expect(find.byKey(RoomPushKeys.root), findsNothing,
          reason: '同意后弹窗关闭且不再弹');
      expect(tester.takeException(), isNull);
    });

    testWidgets('5C 点拒绝 → agree:false 且弹窗消失',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);
      await mountRoom(tester, f, 'p1');
      await pushRequest(f, 'p1', '5C拒绝说明');
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsOneWidget);

      f.clearSent();
      await tester.tap(find.byKey(RoomPushKeys.reject));
      await _settle(tester);

      final intent = f.lastSent(op: RoomIntent.consent);
      expect(intent, isNotNull, reason: '点拒绝也必须真的发出意图');
      final p = asMap(intent!['p']);
      expect(p['agree'], false);
      expect(p['id'], isA<String>());
      expect(find.byKey(RoomPushKeys.root), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5D 去重：KP 历史不弹 / 玩家历史必弹一次 / 同一 id 只弹一次',
        (WidgetTester tester) async {
      // 说明：原用例只覆盖玩家视角（`mountRoom(tester, f, 'p1')`）。
      //   KP 视角对 `state.request` 会走 confirm 入队（watcher :381 仅对
      //   `reply != confirm` 的历史记账），属「待我确认」路径、挂载即弹是设计
      //   预期，与本用例的 consent 历史场景不同，故不在此处断言 KP。
      useRoomScreen(tester, 900, 1600);

      // ===== 玩家视角：需求 3④ 后弹窗是唯一同意通道 → 历史 consent 必弹 =====
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      await pushRequest(f, 'p1', '首屏已有说明');
      await tester.pumpWidget(appKeyed(
          f, 'p1', 'plHist', const Scaffold(body: RoomGamePage())));
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsOneWidget,
          reason: '需求3④：弹窗是玩家唯一同意通道，历史 consent 不能被静默吞掉');
      expect(asList(f.stateOf('p1')['requests']).length, 1);

      // ===== 同一 id 只弹一次：显式处理后 refresh 不重弹 =====
      // ★ P20 需求3④：玩家 consent 弹窗 `barrierDismissible: false`
      //   （`room_request_watcher.dart:455` 仅 `reply == confirm` 可点外部关闭），
      //   因为弹窗是玩家唯一同意通道、不允许误关即丢。故这里用「点拒绝」关闭，
      //   而不是原用例的 `tapAt(4,4)`（对 consent 弹窗已无效）。
      await tester.tap(find.byKey(RoomPushKeys.reject));
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsNothing,
          reason: '点拒绝后弹窗应关闭');
      for (var i = 0; i < 3; i++) {
        f.sessionOf('p1').refresh(); // 只发通知、不改数据
        await _settle(tester);
        expect(find.byKey(RoomPushKeys.root), findsNothing,
            reason: '同一 id 只弹一次（第 $i 次额外通知）');
      }

      // ===== 之后到达的新请求（新 id）→ 再弹一次 =====
      await pushRequest(f, 'p1', '新到达说明');
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsOneWidget,
          reason: '新 id 的请求应再弹一次');
      expect(asList(f.stateOf('p1')['requests']), isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5E 私密口径：SendPlan 按 to 分发，只有收件人弹，'
        '第三人整份 state 搜不到密语', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      const secretA = '仅p1可见的密语AAA';
      const secretB = '仅p1可见的密语BBB';
      const secretC = '仅p1可见的密语CCC';

      // ① p1（收件人）：先挂载、无历史待办，再到达定向给自己的请求 → 该弹。
      await tester.pumpWidget(appKeyed(
          f, 'p1', 'p1', const Scaffold(body: RoomGamePage())));
      await _settle(tester);
      await pushRequest(f, 'p1', secretA);
      await _settle(tester);

      // 真实 SendPlan 的 to 分流：定向 REQUEST 只发 p1，其余座位拿 skip 水位。
      final wires = f.kpSession.sentLog;
      expect(
        wires.any((Map<String, Object?> w) =>
            w['to'] == 'p1' && asMap(w['msg'])['t'] == 'request'),
        isTrue,
        reason: 'state.request 必须产出 to:p1 的定向 EVT.REQUEST',
      );
      expect(
        wires.any((Map<String, Object?> w) =>
            w['to'] == 'p2' && asMap(w['msg'])['t'] == 'request'),
        isFalse,
        reason: '别人的请求绝不能进 p2 的字节里',
      );
      expect(
        wires.any((Map<String, Object?> w) =>
            w['to'] == 'sp1' && asMap(w['msg'])['t'] == 'request'),
        isFalse,
      );

      // 三个真实 RoomClient：只有 p1 的 state 里有这条请求 / 密语。
      expect(jsonEncode(f.kpSession.clients['p1']!.state).contains(secretA),
          isTrue);
      expect(jsonEncode(f.kpSession.clients['p2']!.state).contains(secretA),
          isFalse);
      expect(jsonEncode(f.kpSession.clients['sp1']!.state).contains(secretA),
          isFalse);
      expect(find.byKey(RoomPushKeys.root), findsOneWidget);
      expect(
        find.descendant(
            of: find.byKey(RoomPushKeys.details),
            matching: find.textContaining(secretA)),
        findsOneWidget,
      );

      // ② p2（别的玩家）：整树重建后，再到达一条**新的**定向给 p1 的请求
      //    → 不该弹，且整份 state 搜不到密语。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(appKeyed(
          f, 'p2', 'p2', const Scaffold(body: RoomGamePage())));
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsNothing);
      await pushRequest(f, 'p1', secretB);
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsNothing,
          reason: '别的玩家不该收到别人的推送');
      expect(jsonEncode(f.stateOf('p2')).contains(secretB), isFalse);
      expect(jsonEncode(f.stateOf('sp1')).contains(secretB), isFalse);
      expect(jsonEncode(f.stateOf('p1')).contains(secretB), isTrue);

      // ③ sp1（旁观者）：同样不该弹、整份 state 搜不到密语。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(appKeyed(
          f, 'sp1', 'sp1', const Scaffold(body: RoomGamePage())));
      await _settle(tester);
      await pushRequest(f, 'p1', secretC);
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsNothing,
          reason: '旁观者不该收到玩家的私密推送');
      expect(jsonEncode(f.stateOf('sp1')).contains(secretC), isFalse);
      expect(jsonEncode(f.stateOf('p2')).contains(secretC), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5F 两条数据源分别验：KP 走 hostRead.pending(CONFIRM)，'
        '玩家走 state[requests](CONSENT)', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 1600);

      // ① KP 路径：玩家提交需 KP 确认的动作 → hostRead.pending 出现新项。
      await mountRoom(tester, f, kHostSeat);
      expect(f.sessionOf(kHostSeat).hostRead, isNotNull);
      await f.plSessions['p1']!.hostAction(
        'state.edit.self',
        <String, Object?>{'skill': '侦查', 'value': 70},
      );
      await _settle(tester);
      expect(f.sessionOf(kHostSeat).hostRead!.pending.length, greaterThan(0),
          reason: 'KP 的待办来自 hostRead.pending，不是 state.requests');
      expect(find.byKey(RoomPushKeys.root), findsOneWidget);
      expect(find.textContaining('待确认'), findsWidgets);
      final kpReqs = collectRoomPushRequests(f.sessionOf(kHostSeat));
      expect(kpReqs.any((r) => r.reply == RoomPushReply.confirm), isTrue,
          reason: 'KP 待确认动作走 INTENT.CONFIRM 通道');
      expect(kpReqs.any((r) => r.details.any((d) => d.contains('侦查'))),
          isTrue, reason: '详情要扫到 p 载荷袋里的技能字段');
      // 屏障关闭，避免后续确认动作的下游状态变更干扰下一段。
      await tester.tapAt(const Offset(4, 4));
      await _settle(tester);
      expect(find.byKey(RoomPushKeys.root), findsNothing);

      // ② 玩家路径：KP 定向推送 → 自己裁剪态 state['requests'] 出现新项。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mountRoom(tester, f, 'p1');
      expect(f.sessionOf('p1').hostRead, isNull,
          reason: '非 KP 视角拿不到 hostRead，只能读自己的裁剪态');
      await pushRequest(f, 'p1', '5F玩家路径说明');
      await _settle(tester);
      expect(asList(f.stateOf('p1')['requests']).isNotEmpty, isTrue);
      expect(find.byKey(RoomPushKeys.root), findsOneWidget);
      final plReqs = collectRoomPushRequests(f.sessionOf('p1'));
      expect(plReqs.any((r) => r.reply == RoomPushReply.consent), isTrue,
          reason: '玩家的「需我同意」走 INTENT.CONSENT 通道');
      expect(tester.takeException(), isNull);
    });
  });
}
