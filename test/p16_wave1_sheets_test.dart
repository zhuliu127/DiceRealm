// ============================================================
// test/p16_wave1_sheets_test.dart — P16 波1-A（弹层与单位选择器）用例
//
// 覆盖（施工单 §4）：下拉选单位 / 公开互斥无关 / 治疗三分支路由 /
//   加怪弹窗六字段；另补 collectUnitOptions 纯函数、showUnitPicker
//   运行时交互、固定尺寸控件 textScaler 1.3/1.5/2.0、源码红线自检。
//
// ★ 波1 并发写码期本组**不执行**本文件；由波2 独占串行期统一跑
//   `flutter test --no-pub test/p16_wave1_sheets_test.dart`。
// ★ 用例只依赖本组独占文件 + 既有只读夹具，不改任何既有测试。
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/domain/js_compat.dart' show asMap;
import 'package:dice_realm/domain/room_types.dart'
    show kHostSeat, RoomIntent, RoomRole;
import 'package:dice_realm/ui/room/sheets/sheet_add_actor.dart'
    show AddActorSheetKeys, openAddActorSheet;
import 'package:dice_realm/ui/room/sheets/sheet_opposed.dart'
    show OpposedSheet, OpposedSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_scene.dart'
    show ClueSheet, SceneSheet, SceneSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_treat.dart'
    show TreatSheetKeys, openTreatSheet;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:dice_realm/ui/room/widgets/unit_picker.dart'
    show
        RoomUnitOption,
        UnitPickerField,
        collectUnitOptions,
        kUnitAllValue,
        showUnitPicker,
        unitValueToSeat;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 本组独占的 6 个源码文件（源码红线自检用）。
const List<String> _wave1Files = <String>[
  'lib/ui/room/widgets/unit_picker.dart',
  'lib/ui/room/sheets/sheet_opposed.dart',
  'lib/ui/room/sheets/sheet_scene.dart',
  'lib/ui/room/sheets/sheet_misc.dart',
  'lib/ui/room/sheets/sheet_add_actor.dart',
  'lib/ui/room/sheets/sheet_treat.dart',
];

/// 独立宿主：MaterialApp.builder 把 RoomScope 挂在 Navigator 之上，
/// 于是弹层（showModalBottomSheet）里也能取到同一份作用域。
Widget _app(RoomUiFixture f, Widget body, {String seat = 'p1'}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) =>
        f.scoped(seat, child: child ?? const SizedBox.shrink()),
    home: Scaffold(body: SingleChildScrollView(child: body)),
  );
}

/// 一个「点一下打开弹层」的宿主按钮，用来在测试里取得可用的 context。
class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.onOpen});

  final void Function(BuildContext) onOpen;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: () => onOpen(context),
        child: const Text('open'),
      );
}

/// 手拼一份只含「成员 + 战斗槽」的房间快照，喂给纯函数 collectUnitOptions。
Map<String, Object?> _unitState() => <String, Object?>{
      'members': <Object?>[
        <String, Object?>{
          'seat': 'p1',
          'role': RoomRole.player,
          'nickname': '阿明',
          'charName': '调查员张三',
          'sheet': <String, Object?>{'name': '卡名'},
        },
        <String, Object?>{
          'seat': 'p2',
          'role': RoomRole.player,
          'nickname': '小红',
        },
        <String, Object?>{
          'seat': 'host',
          'role': RoomRole.kp,
          'nickname': '老K',
        },
        <String, Object?>{
          'seat': 'sp1',
          'role': RoomRole.spectator,
        },
      ],
      'combat': <String, Object?>{
        'turn': 0,
        'order': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': '深潜者',
            'kind': 'monster',
            'public': <String, Object?>{
              'hp': 8,
              'hpMax': 8,
              'hpPublic': true,
            },
          },
          <String, Object?>{
            'id': 'n1',
            'name': '村民',
            'kind': 'npc',
            'public': <String, Object?>{
              'hp': 5,
              'hpMax': 5,
              'hpPublic': true,
            },
          },
          <String, Object?>{
            'id': 'pc-1',
            'name': '张三',
            'kind': 'pc',
            'public': <String, Object?>{
              'hp': 12,
              'hpMax': 12,
              'hpPublic': true,
            },
          },
          <String, Object?>{
            'id': 'm2',
            'name': '倒地怪',
            'kind': 'monster',
            'public': <String, Object?>{
              'hp': 0,
              'hpMax': 6,
              'hpPublic': true,
            },
          },
        ],
      },
    };

/// 打开弹层后推进底部弹层入场动画（项目惯例 350ms，取 400ms 留余量）。
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // ----------------------------------------------------------
  // ① 下拉选单位：collectUnitOptions 纯函数（KP-1 / KP-6 共用枚举）
  // ----------------------------------------------------------
  group('collectUnitOptions 纯函数', () {
    test('全体项 / 玩家 p: 前缀 / 角色名优先 / 存活怪物 NPC a: 前缀', () {
      final opts = collectUnitOptions(_unitState());
      final values = opts.map((RoomUnitOption o) => o.value).toList();

      expect(opts.first.value, kUnitAllValue, reason: '首项恒为「全体」');
      expect(opts.first.kind, 'all');

      expect(values, contains('p:p1'));
      expect(values, contains('p:p2'));
      expect(values, isNot(contains('p:host')), reason: 'KP 不列为可选单位');
      expect(values, isNot(contains('p:sp1')), reason: '旁观不列为可选单位');

      final p1 = opts.firstWhere((RoomUnitOption o) => o.value == 'p:p1');
      expect(p1.label, contains('调查员张三'),
          reason: 'charName 优先于 sheet.name / nickname');
      expect(p1.kind, 'player');
      final p2 = opts.firstWhere((RoomUnitOption o) => o.value == 'p:p2');
      expect(p2.label, contains('小红'), reason: '无 charName 时回退 nickname');

      expect(values, contains('a:m1'));
      expect(values, contains('a:n1'));
      expect(opts.firstWhere((o) => o.value == 'a:m1').kind, 'monster');
      expect(opts.firstWhere((o) => o.value == 'a:n1').kind, 'npc');
      expect(values, isNot(contains('a:pc-1')),
          reason: 'PC 槽不重复列为单位');
      expect(values, isNot(contains('a:m2')),
          reason: 'HP 归零的倒地怪不列出（存活过滤）');
    });

    test('RoomUnitOption 四字段齐备 / base 默认 null / copyWith 可补值', () {
      const o = RoomUnitOption(
        value: 'a:m1',
        label: '深潜者（怪物）',
        kind: 'monster',
      );
      expect(o.value, 'a:m1');
      expect(o.label, '深潜者（怪物）');
      expect(o.kind, 'monster');
      expect(o.base, isNull);
      expect(o.copyWith(base: 60).base, 60);
      expect(o.copyWith(base: 60).value, 'a:m1');
    });

    test('unitValueToSeat 剥前缀 / 保留全体（场景检定载荷适配）', () {
      expect(unitValueToSeat(kUnitAllValue), kUnitAllValue);
      expect(unitValueToSeat('p:p1'), 'p1');
      expect(unitValueToSeat('a:m1'), 'm1');
      expect(unitValueToSeat('p1'), 'p1');
    });

    test('空 state 仍返回「全体」项，且无其它越界数据', () {
      final opts = collectUnitOptions(const <String, Object?>{});
      expect(opts.length, 1);
      expect(opts.single.value, kUnitAllValue);
    });
  });

  // ----------------------------------------------------------
  // ② 下拉选单位：showUnitPicker 运行时交互
  // ----------------------------------------------------------
  group('showUnitPicker 弹层', () {
    testWidgets('allowAll:true 含全体 / 点选返回带前缀的 option',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      RoomUnitOption? picked;
      await tester.pumpWidget(_app(f, _OpenButton(onOpen: (BuildContext ctx) async {
        picked = await showUnitPicker(ctx, title: '选择单位', allowAll: true);
      })));
      await _openSheet(tester);

      expect(find.byKey(const ValueKey<String>('unitPicker/*')),
          findsOneWidget, reason: 'allowAll:true 保留「全体」');
      expect(find.byKey(const ValueKey<String>('unitPicker/p:p1')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('unitPicker/p:p1')));
      await tester.pump();
      expect(picked, isNotNull);
      expect(picked!.value, 'p:p1');
      expect(picked!.kind, 'player');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('allowAll:false 过滤全体项（对抗弹窗口径）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      await tester.pumpWidget(_app(f, _OpenButton(
        onOpen: (BuildContext ctx) async {
          await showUnitPicker(ctx, title: '选择单位');
        },
      )));
      await _openSheet(tester);

      expect(find.byKey(const ValueKey<String>('unitPicker/*')), findsNothing);
      expect(find.byKey(const ValueKey<String>('unitPicker/p:p1')),
          findsOneWidget);
      expect(tester.takeException(), isNull);

      // 点一项关闭弹层，避免挂起 Future。
      await tester.tap(find.byKey(const ValueKey<String>('unitPicker/p:p1')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ③ KP-1 / KP-6 结构：两弹层的座位输入确为选单位控件
  // ----------------------------------------------------------
  group('KP-1 / KP-6 选单位字段结构', () {
    // UnitPickerField 会把自身 key 一并下发给内部 RoomTap（同一个 key 出现在
    // 父子两层，find.byKey 会命中 2 个元素）。这里用「类型 + key」双重谓词
    // 精确定位字段本体，顺带断言它的 label / allowAll 语义 —— 比原来的
    // `tester.widget(find.byKey(k))` 更精确（后者只能取 single，且取到的
    // 可能是内部 RoomTap 而非字段本体）。
    UnitPickerField field(WidgetTester tester, String name, Key key,
        {required bool allowAll}) {
      final finder = find.byWidgetPredicate(
          (Widget w) => w is UnitPickerField && w.key == key);
      expect(finder, findsOneWidget, reason: '$name 必须是 UnitPickerField');
      final f = tester.widget<UnitPickerField>(finder);
      expect(f.allowAll, allowAll, reason: '$name 的 allowAll 口径');
      return f;
    }

    testWidgets('KP-1：对抗弹层两处字段是 UnitPickerField（不再是 TextField）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      await tester.pumpWidget(
          _app(f, const OpposedSheet(), seat: kHostSeat));
      await tester.pump();

      expect(find.byKey(OpposedSheetKeys.root), findsOneWidget);
      // 对抗弹窗不提供「全体」，两个字段都必须 allowAll:false。
      field(tester, '申请单位', OpposedSheetKeys.reqId, allowAll: false);
      field(tester, '伤害目标', OpposedSheetKeys.targetId, allowAll: false);
      // 旧文本输入确已消失：这两个 key 上不存在 TextField / TextFormField。
      expect(
          find.byWidgetPredicate((Widget w) =>
              w is TextField && w.key == OpposedSheetKeys.reqId),
          findsNothing);
      expect(
          find.byWidgetPredicate((Widget w) =>
              w is TextField && w.key == OpposedSheetKeys.targetId),
          findsNothing);
      // 既有申请流程结构（按钮 / 闸门）仍原样保留。
      expect(find.byKey(OpposedSheetKeys.resolve), findsOneWidget);
      expect(find.byKey(OpposedSheetKeys.target), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('KP-6/KP-7：场景编辑器 3 处 + 递线索独立弹层 1 处，座位全是 UnitPickerField',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      await tester.pumpWidget(
          _app(f, const SceneSheet(), seat: kHostSeat));
      await tester.pump();

      expect(find.byKey(SceneSheetKeys.root), findsOneWidget);
      // 编辑器内 3 处座位保留「全体」（'*' = 全体）语义。
      field(tester, '步骤目标座位', SceneSheetKeys.stepSeat(0), allowAll: true);
      field(tester, '检定座位', SceneSheetKeys.checkSeat, allowAll: true);
      field(tester, '改状态目标座位', SceneSheetKeys.stateSeat, allowAll: true);
      // ★ KP-7：线索目标座位已迁入独立 showClueSheet → ClueSheet；编辑器内不再挂载。
      expect(find.byKey(SceneSheetKeys.clueSeat), findsNothing,
          reason: 'KP-7：编辑器内不该再有线索座位选择器');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // 同一份 ClueSheet（showClueSheet 的 body）：座位选择器仍在、仍可选「全体」。
      await tester.pumpWidget(_app(f, const ClueSheet(), seat: kHostSeat));
      await tester.pump();
      expect(find.byKey(SceneSheetKeys.clue), findsOneWidget);
      field(tester, '线索目标座位', SceneSheetKeys.clueSeat, allowAll: true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    test('源码门禁：旧文本座位输入已移除、选单位 / 剥前缀代码在', () {
      final opposed =
          File('lib/ui/room/sheets/sheet_opposed.dart').readAsStringSync();
      expect(opposed.contains("labelText: '申请 id'"), isFalse);
      expect(opposed.contains("labelText: '目标 id'"), isFalse);
      expect(opposed.contains('UnitPickerField('), isTrue);

      final scene =
          File('lib/ui/room/sheets/sheet_scene.dart').readAsStringSync();
      expect(scene.contains("labelText: '目标座位'"), isFalse);
      expect(scene.contains("labelText: '改状态目标座位'"), isFalse);
      expect(scene.contains('UnitPickerField('), isTrue);
      expect(scene.contains('unitValueToSeat('), isTrue,
          reason: '场景检定提交须剥回裸 seat / 保留 *');
    });
  });

  // ----------------------------------------------------------
  // ③b 提交载荷：统一 value → domain 期望的座位口径
  // ----------------------------------------------------------
  group('选单位后的提交载荷', () {
    /// 点「选单位」字段本体（key 同时挂在 UnitPickerField 与内部 RoomTap 上，
    /// 用类型谓词精确命中可点的那一层）。
    Future<void> tapPicker(WidgetTester tester, Key key) async {
      await tester.tap(
          find.byWidgetPredicate((Widget w) => w is RoomTap && w.key == key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('KP-6/KP-7 递线索：p:p1 提交成裸 seat p1，"*" 保持不变（ClueSheet 内）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      // ★ KP-7：递线索已收拢进独立 ClueSheet（原 `act/scene.clue` 锚点撤回）。
      await tester.pumpWidget(_app(f, const ClueSheet(), seat: kHostSeat));
      await tester.pump();

      // ① 默认「全体」：递线索 seat 必须是 '*'（不是 'p:*' 之类）。
      final RoomTap clueBtn =
          tester.widget<RoomTap>(find.byKey(SceneSheetKeys.clueSubmit));
      expect(clueBtn.enabled, isTrue, reason: 'KP 应能递线索（前置）');
      f.clearSent();
      await tester.tap(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.pump();
      final all = asMap(f.lastSent(action: 'scene.clue')!['p']);
      expect(all['seat'], kUnitAllValue,
          reason: '默认「全体」必须原样提交 *');

      // ② 选具体玩家 p:p1 → 提交时必须剥成裸 seat 'p1'。
      await tapPicker(tester, SceneSheetKeys.clueSeat);
      expect(find.byKey(const ValueKey<String>('unitPicker/p:p1')),
          findsOneWidget,
          reason: 'KP-6：ClueSheet 的选单位弹层要列出玩家 p1');
      await tester.tap(find.byKey(const ValueKey<String>('unitPicker/p:p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 展示文案已换成该玩家（证明选择真的写进了草稿）。
      final UnitPickerField clueField = tester.widget<UnitPickerField>(
          find.byWidgetPredicate(
              (Widget w) => w is UnitPickerField && w.key == SceneSheetKeys.clueSeat));
      expect(clueField.display, contains('（玩家）'),
          reason: '选中后字段展示应变成「<名字>（玩家）」，而不是仍是「全体」');
      expect(clueField.display, isNot('全体'));

      f.clearSent();
      await tester.tap(find.byKey(SceneSheetKeys.clueSubmit));
      await tester.pump();
      final p1 = asMap(f.lastSent(action: 'scene.clue')!['p']);
      expect(p1['seat'], 'p1',
          reason: 'KP-6：p:p1 必须剥成裸 seat（domain 只认裸 seat）');
      expect('${p1['seat']}'.contains(':'), isFalse,
          reason: '载荷里绝不允许出现 p: 前缀');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('KP-1 对抗弹层：选单位后 reqId / targetId 用统一 value',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      // ★ P17 KP-3：弹层内容变长（甲乙双方 / 技能框 / 反击闪避 / 伤害目标
      //   四个 SectionBox），900 高的视口装不下 —— 「选伤害目标」掉到视口
      //   外导致 find 抛 0 widgets。加高视口让弹层整页可测。
      useRoomScreen(tester, 800, 2400);
      await tester.pumpWidget(
          _app(f, const OpposedSheet(), seat: kHostSeat));
      await tester.pump();

      // ① 申请单位 → reqId。★ 对抗口径**保留**统一 value 前缀（老 APP 一致），
      //   与场景检定的「剥裸 seat」是两套明确区分过的契约，见 unit_picker.dart
      //   顶部注释；这里断言的是「选择真的进了载荷」，不是空串。
      await tapPicker(tester, OpposedSheetKeys.reqId);
      await tester.tap(find.byKey(const ValueKey<String>('unitPicker/p:p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final RoomTap resolve =
          tester.widget<RoomTap>(find.byKey(OpposedSheetKeys.resolve));
      expect(resolve.enabled, isTrue, reason: 'KP 应能裁定（前置）');
      f.clearSent();
      await tester.tap(find.byKey(OpposedSheetKeys.resolve));
      await tester.pump();
      final req = asMap(f.lastSent(action: 'check.opposed')!['p']);
      expect(req['reqId'], 'p:p1',
          reason: '对抗口径保留统一 value（p:<seat>），不是空串');
      expect(req['attack'], true);

      // ② 伤害目标 → targetId（走 INTENT.opposed phase:target）。
      await tapPicker(tester, OpposedSheetKeys.targetId);
      await tester.tap(find.byKey(const ValueKey<String>('unitPicker/p:p2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final UnitPickerField targetField = tester.widget<UnitPickerField>(
          find.byWidgetPredicate((Widget w) =>
              w is UnitPickerField && w.key == OpposedSheetKeys.targetId));
      expect(targetField.display, contains('（玩家）'),
          reason: '选中 p2 后目标字段展示应更新');
      // 本夹具不在战斗态 / 不是我的回合 → 闸门必须拦住「选定目标」
      // （同时证明按钮没被改成恒可点，也没有偷发 INTENT.opposed）。
      expect(
        tester.widget<RoomTap>(find.byKey(OpposedSheetKeys.target)).enabled,
        isFalse,
        reason: 'kpOpposedCanApply=false 时「选定目标」必须禁用',
      );
      f.clearSent();
      await tester.tap(find.byKey(OpposedSheetKeys.target));
      await tester.pump();
      expect(f.lastSent(op: RoomIntent.opposed), isNull,
          reason: '闸门拦住时点下去不许发包');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ④ 加怪弹窗字段（KP-7 / KP-8 护甲 + P12 PL-1a 第 7 字段）
  // ----------------------------------------------------------
  group('openAddActorSheet 六字段 + P12 第 7 字段', () {
    testWidgets('填六字段 + 选 NPC → 返回契约 map（第 7 字段默认 false）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 800, 900);
      Map<String, Object?>? result;
      await tester.pumpWidget(_app(f, _OpenButton(
        onOpen: (BuildContext ctx) async {
          result = await openAddActorSheet(ctx);
        },
      )));
      await _openSheet(tester);

      await tester.enterText(find.byKey(AddActorSheetKeys.name), '深潜者');
      await tester.enterText(find.byKey(AddActorSheetKeys.dex), '60');
      await tester.enterText(find.byKey(AddActorSheetKeys.hp), '14');
      await tester.enterText(find.byKey(AddActorSheetKeys.actions), '2');
      await tester.enterText(find.byKey(AddActorSheetKeys.armor), '3');
      await tester.tap(find.byKey(AddActorSheetKeys.kindNpc));
      await tester.pump();
      await tester.tap(find.byKey(AddActorSheetKeys.confirm));
      await tester.pump();

      expect(result, isNotNull);
      expect(result!['name'], '深潜者');
      expect(result!['kind'], 'npc');
      expect(result!['dex'], 60);
      expect(result!['hp'], 14);
      expect(result!['actionsPerRound'], 2);
      expect(result!['armor'], 3);
      // ★ P12 PL-1a：「是否显示给玩家」是产品行为真变，草稿从 6 键变 7 键。
      //   按「更强或等价」改写：既有 6 键逐字保留，新增第 7 键正向断言。
      expect(result!.keys.toSet(), <String>{
        'name',
        'kind',
        'dex',
        'hp',
        'actionsPerRound',
        'armor',
        'visibleToPlayers',
      }, reason: '★ 恰好 6 旧键 + 1 新键，仍不夹带 hpMax / id');
      expect(result!.length, 7);
      expect(result!['visibleToPlayers'], false,
          reason: '★ Q6：默认不勾（防泄露）');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('取消 → 返回 null', (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 800, 900);
      Map<String, Object?>? result = const <String, Object?>{'sentinel': 1};
      await tester.pumpWidget(_app(f, _OpenButton(
        onOpen: (BuildContext ctx) async {
          result = await openAddActorSheet(ctx);
        },
      )));
      await _openSheet(tester);
      await tester.tap(find.byKey(AddActorSheetKeys.cancel));
      await tester.pump();
      expect(result, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('固定宽度字段在 textScaler 1.3 / 1.5 / 2.0 下无溢出',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 360, 640);
      await tester.pumpWidget(_app(f, _OpenButton(
        onOpen: (BuildContext ctx) async {
          await openAddActorSheet(ctx);
        },
      )));
      await _openSheet(tester);
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      for (final scale in <double>[1.3, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'textScaler $scale 下加怪弹层溢出');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // ----------------------------------------------------------
  // ⑤ 治疗三分支路由（P-4）
  // ----------------------------------------------------------
  group('openTreatSheet 三分支路由', () {
    Future<void> checkBranch(
      WidgetTester tester, {
      required String label,
      required String op,
      String? skill,
    }) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 900);
      await tester.pumpWidget(_app(f, _OpenButton(
        onOpen: (BuildContext ctx) {
          openTreatSheet(ctx, ctl: f.controllerOf('p1'));
        },
      )));
      await _openSheet(tester);

      await tester.tap(find.byKey(TreatSheetKeys.kind(label)));
      await tester.pump();
      await tester.tap(find.byKey(TreatSheetKeys.target('p2')));
      await tester.pump();
      f.clearSent();
      await tester.tap(find.byKey(TreatSheetKeys.submit));
      await tester.pump();

      final sent = f.lastSent(action: op);
      expect(sent, isNotNull, reason: '$label 应发出 $op');
      final p = asMap(sent!['p']);
      expect(p['seat'], 'p1', reason: 'seat = 发起者自己');
      expect(p['targetSeat'], 'p2', reason: 'targetSeat = 选中的队友裸 seat');
      if (skill != null) {
        expect(p['skill'], skill);
      } else {
        expect(p.containsKey('skill'), isFalse,
            reason: 'aid.psycho 不带 skill');
      }
      // 检定值输入框只做确认 / 预留，不进 domain 载荷。
      expect(p.containsKey('base'), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets('急救 → aid.apply（skill=急救）',
        (WidgetTester tester) async {
      await checkBranch(tester, label: '急救', op: 'aid.apply', skill: '急救');
    });

    testWidgets('医学 → aid.apply（skill=医学）',
        (WidgetTester tester) async {
      await checkBranch(tester, label: '医学', op: 'aid.apply', skill: '医学');
    });

    testWidgets('精神分析 → aid.psycho（不带 skill）',
        (WidgetTester tester) async {
      await checkBranch(tester, label: '精神分析', op: 'aid.psycho');
    });
  });

  // ----------------------------------------------------------
  // ⑥ 公开互斥无关 + 源码红线自检
  // ----------------------------------------------------------
  group('公开互斥无关 / 源码红线', () {
    test('本组源码不碰公开互斥（KP-2 属波1-B/波2）', () {
      for (final path in _wave1Files) {
        final src = File(path).readAsStringSync();
        for (final banned in <String>[
          'revealAsset',
          'coverAsset',
          'asset.cover',
          'revealed',
        ]) {
          expect(src.contains(banned), isFalse,
              reason: '$path 命中公开互斥字样 $banned');
        }
      }
    });

    test('本组源码零增补平面 emoji / 零 jsStr( / 零权威快照赋值', () {
      final emoji = RegExp(r'[\uD800-\uDBFF][\uDC00-\uDFFF]');
      final assign = RegExp(r'state\s*\[[^\]]+\]\s*=');
      for (final path in _wave1Files) {
        final src = File(path).readAsStringSync();
        expect(emoji.hasMatch(src), isFalse, reason: '$path 含 emoji');
        expect(src.contains('jsStr('), isFalse, reason: '$path 写了 jsStr(');
        expect(assign.hasMatch(src), isFalse, reason: '$path 出现权威快照赋值');
      }
    });
  });
}
