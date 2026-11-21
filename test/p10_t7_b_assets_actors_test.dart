// ============================================================
// test/p10_t7_b_assets_actors_test.dart — P10 第 7 期 B 批验收
//
// 用户两条原话：
//   ①「上传素材后，没有缩略图」
//   ②「增加怪物、NPC，没有让我填数值（比如 HP、DEX 等），对照老版 app 2.13.13」
//
// 覆盖：
//   TB1 合法 dataURL → Image.memory 真字节；坏 / 空数据静默降级占位、零异常；
//   TB2 按 id 去重仍成立（A 批 T7 口径：私有原件 + 广播副本只一行）；
//   TB3 左窄栏「加怪」→ 弹层填六字段 → pendingActors 全字段（含护甲）生效；
//   TB4 非法数字回落默认 + 每轮 12→10 / 0→1 + 护甲 -5→0 静默夹取；
//   TB5 候选行文本含 DEX 30 / HP 25 / 每轮 2 次（渲染点在左窄栏）；
//   TB6 左窄栏入口是唯一入口（工具窄栏已无内联表单，弹层口径一致）；
//   TB7 回归：缩略图加入后素材按钮热区 ≥48×48 且矩形不出格（P16 只剩两个）；
//   TB8 T-30：左窄栏加怪按钮 enabled 恰好恒等 gate.can('combat.start')，
//        工具窄栏已无加怪入口（KP-10）。
//
// ★ P16 KP-7 / KP-8 / KP-10：内联数值表单（工具窄栏 + 左窄栏）全部退役，
//   唯一入口是左窄栏 `GpKpLeftKeys.addActor` → `openAddActorSheet` 弹层
//   （六字段：名称 / 类型 / DEX / HP / 每轮 / 护甲）。
//
// ★ T1：全内存后端（RoomUiFixture），零真实 I/O；flutter test 必须带 NO_PROXY。
// ★ 断言一律用真实 widget / Rect / 载荷逐字段，不用 findsWidgets 放宽。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/sheets/sheet_add_actor.dart'
    show AddActorSheetKeys;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys, RoomSlot;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart'
    show GpKpLeft, GpKpLeftKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart'
    show GpKpTools, GpKpToolsKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart'
    show RoomUiFixture, kFakePngDataUrl, useRoomScreen;

/// 独立块宿主：MaterialApp + RoomScope + Scaffold（同 room_ui_blocks_test）。
Widget _hostBlock(RoomUiFixture f, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: f.scoped(kHostSeat, child: child),
        ),
      ),
    );

/// 滚动到可见再输入（窄栏里表单会换行，可能落在首屏之外）。
Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await tester.pump();
}

/// 滚动到可见再点。
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// 直接往私有素材库塞一条（与 p10_t7_layout_test T5/T8 同口径，绕过 action 校验）。
void _seedAsset(
  RoomUiFixture f, {
  required String id,
  required String name,
  required String data,
  bool revealed = false,
}) {
  f.host.localAssets.add(<String, Object?>{
    'id': id,
    'kind': 'map',
    'name': name,
    'data': data,
    'revealed': revealed,
    'at': 1,
  });
}

/// 用真实 action 造一条素材，返回其 id（复刻 A 批 T7 的去重前置）。
Future<String> _addAssetViaAction(
  RoomUiFixture f, {
  required String name,
  required String data,
}) async {
  await f.controllerOf(kHostSeat).hostAction('asset.add', <String, Object?>{
    'asset': <String, Object?>{
      'kind': 'map',
      'name': name,
      'data': data,
    },
  });
  return '${f.host.localAssets.last['id']}';
}

/// 走「左窄栏加怪入口 → 弹层填六字段 → 确定」的完整流程。
///
/// ★ P16 KP-7：内联表单已删，唯一入口是左窄栏的 `addActor` 弹层；
///   本 helper 顺带钉住「弹层确实按 key 弹出来了」（否则后面填字段会炸，
///   比原来直接 enterText 更硬）。
Future<void> _addActorViaSheet(
  WidgetTester tester, {
  required String name,
  required String dex,
  required String hp,
  required String actions,
  String armor = '0',
  bool npc = true,
}) async {
  await _tap(tester, find.byKey(GpKpLeftKeys.addActor));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byKey(AddActorSheetKeys.root), findsOneWidget,
      reason: 'KP-7：点加怪必须先弹出六字段弹层');
  await _enter(tester, find.byKey(AddActorSheetKeys.name), name);
  await _enter(tester, find.byKey(AddActorSheetKeys.dex), dex);
  await _enter(tester, find.byKey(AddActorSheetKeys.hp), hp);
  await _enter(tester, find.byKey(AddActorSheetKeys.actions), actions);
  await _enter(tester, find.byKey(AddActorSheetKeys.armor), armor);
  await _tap(
    tester,
    find.byKey(npc
        ? AddActorSheetKeys.kindNpc
        : AddActorSheetKeys.kindMonster),
  );
  await _tap(tester, find.byKey(AddActorSheetKeys.confirm));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byKey(AddActorSheetKeys.root), findsNothing,
      reason: '确定后弹层应关闭');
}

void main() {
  // ========================================================
  // TB1 · 素材缩略图：合法图 / 坏数据 / 空数据
  // ========================================================
  testWidgets('TB1 合法 dataURL 出 Image.memory 真字节；坏/空数据静默占位',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    _seedAsset(f, id: 'goodThumb', name: '好图', data: kFakePngDataUrl);
    _seedAsset(f,
        id: 'badThumb',
        name: '坏图',
        data: 'data:image/png;base64,@@@not-base64@@@');
    _seedAsset(f, id: 'emptyThumb', name: '空图', data: '');

    await tester.pumpWidget(_hostBlock(f, const GpKpLeft()));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 1);
    await tester.pump();

    // ① 合法 1×1 PNG：缩略图 key 存在，内部真有一张 MemoryImage 且字节非空。
    final good = find.byKey(GpKpLeftKeys.thumb('goodThumb'));
    expect(good, findsOneWidget, reason: '每行素材都要挂稳定缩略图 key');
    final img = find.descendant(of: good, matching: find.byType(Image));
    expect(img, findsOneWidget, reason: '用户原话「上传素材后，没有缩略图」');
    final widget = tester.widget<Image>(img);
    expect(widget.image, isA<MemoryImage>(),
        reason: '缩略图必须由 dataURL 解出的字节驱动（不是组件壳）');
    expect((widget.image as MemoryImage).bytes.isNotEmpty, isTrue,
        reason: '字节为空 ⇒ 等于没渲染');
    expect(widget.fit, BoxFit.cover, reason: '缩略图按 cover 裁切铺满 40×40');

    // ② 坏 base64 与空 data：不抛异常、不画 Image、显示占位图标。
    for (final id in <String>['badThumb', 'emptyThumb']) {
      final thumb = find.byKey(GpKpLeftKeys.thumb(id));
      expect(thumb, findsOneWidget, reason: '$id 仍应占一行，不能整栏消失');
      expect(find.descendant(of: thumb, matching: find.byType(Image)),
          findsNothing,
          reason: '$id 坏数据不应画 Image');
      expect(
        find.descendant(
            of: thumb, matching: find.byIcon(Icons.image_outlined)),
        findsOneWidget,
        reason: '$id 坏数据要静默降级成占位图标',
      );
    }
    expect(find.text('好图'), findsOneWidget);
    expect(find.text('坏图'), findsOneWidget);
    expect(find.text('空图'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '一张坏图绝不许炸掉整个素材栏');
  });

  // ========================================================
  // TB2 · 按 id 去重仍成立（第 7 期 A 批 T7 口径不许破）
  // ========================================================
  testWidgets('TB2 公开后左栏按 id 去重（一行、计数正确、缩略图恰好一张）',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    final id = await _addAssetViaAction(
      f,
      name: '重复素材',
      data: kFakePngDataUrl,
    );
    await f.controllerOf(kHostSeat).hostAction(
      'asset.reveal',
      <String, Object?>{'id': id, 'revealed': true},
    );
    // 前置：私有库里确实还留着原件（reveal 只改标记，不删）。
    expect(f.host.localAssets.where((a) => a['id'] == id).length, 1,
        reason: '私有原件仍在，否则去重断言没有意义');

    await tester.pumpWidget(_hostBlock(f, const GpKpLeft()));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 1);
    await tester.pump();

    // A 批 T7 的核心不变量逐字保留。
    expect(find.text('重复素材'), findsOneWidget,
        reason: '同一 id 的素材只能出现一行（旧实现会出现两行）');
    final count = tester.widget<Text>(
        find.byKey(const ValueKey<String>('gpKpLeft/assetCount')));
    expect(count.data, '公开 1 · 未公开 0',
        reason: '计数必须按去重后的行算，且公开/未公开不重叠');
    // ★ 新增正向断言（加严）：加缩略图后每个 id 也只出一张图。
    expect(find.byKey(GpKpLeftKeys.thumb(id)), findsOneWidget,
        reason: '去重后缩略图也只能有一张');
    expect(
      find.descendant(
          of: find.byKey(GpKpLeftKeys.thumb(id)),
          matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // TB3 · 加怪弹层六字段：全字段一起进 addLocalActor
  // ========================================================
  testWidgets('TB3 左栏加怪弹层填 DEX30/HP25/每轮2/护甲7/NPC → pendingActors 全字段',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    await tester.pumpWidget(_hostBlock(f, const GpKpLeft()));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 0);
    await tester.pump();

    // 前置（KP-10）：工具窄栏已无加怪入口，左栏是唯一入口。
    expect(find.byKey(GpKpToolsKeys.addActor), findsNothing,
        reason: 'KP-10：工具窄栏不再有加怪按钮，用例前提不成立会立刻暴露');

    await _addActorViaSheet(
      tester,
      name: '值钱怪',
      dex: '30',
      hp: '25',
      actions: '2',
      armor: '7',
    );

    final rows = f.localOf(kHostSeat).pendingActors;
    expect(rows.length, 1, reason: '点一次加怪只加一条');
    final r = rows.single;
    expect(r['name'], '值钱怪');
    expect(r['dex'], 30, reason: 'DEX 必须来自弹层，不能吃默认 50');
    expect(r['hp'], 25, reason: 'HP 必须来自弹层，不能吃默认 10');
    expect(r['hpMax'], 25, reason: 'hp 同时写进 hpMax（老 APP A2 口径）');
    expect(r['kind'], 'npc', reason: '类型 chip 选了 NPC');
    expect(r['actionsPerRound'], 2, reason: '每轮次数必须来自弹层');
    // ★ P16 KP-8：护甲成为第六个必填契约字段（不是「硬凑」）。
    expect(r['armor'], 7, reason: 'KP-8：护甲必须原样写进候选记录');
    expect(r['id'], 'la1');
    // ★ 反向不变量：老 APP 明确没有的字段仍不许硬凑（armor 已转正，移出清单）。
    for (final forbidden in <String>['db', 'dodge', 'mov', 'fighting']) {
      expect(r.containsKey(forbidden), isFalse,
          reason: '老 APP 2.13.13 没有 $forbidden 字段，不许硬凑');
    }
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // TB4 · 非法数字静默回落 + actionsPerRound 1–10 / armor >=0 静默夹取
  // ========================================================
  testWidgets('TB4 非法数字回落默认；每轮 12→10、0→1、护甲 -5→0（不弹错）',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    await tester.pumpWidget(_hostBlock(f, const GpKpLeft()));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 0);
    await tester.pump();
    final local = f.localOf(kHostSeat);

    // ① 四个数字全非法 → 静默回落 50 / 10 / 1 / 0，hpMax 同值。
    await _addActorViaSheet(
      tester,
      name: '非法',
      dex: 'x',
      hp: 'y',
      actions: 'z',
      armor: 'w',
      npc: false,
    );
    expect(local.pendingActors.last['dex'], 50);
    expect(local.pendingActors.last['hp'], 10);
    expect(local.pendingActors.last['hpMax'], 10);
    expect(local.pendingActors.last['actionsPerRound'], 1);
    expect(local.pendingActors.last['kind'], 'monster');
    expect(local.pendingActors.last['armor'], 0,
        reason: 'KP-8：护甲非法值同样回落默认 0');

    // ② 12 → 夹到 10（domain 侧口径，addLocalActor 函数体零改动）。
    await _addActorViaSheet(
      tester,
      name: '超上限',
      dex: '50',
      hp: '10',
      actions: '12',
      npc: false,
    );
    expect(local.pendingActors.last['actionsPerRound'], 10);

    // ③ 0 → 夹到 1。
    await _addActorViaSheet(
      tester,
      name: '低于下限',
      dex: '50',
      hp: '10',
      actions: '0',
      npc: false,
    );
    expect(local.pendingActors.last['actionsPerRound'], 1);

    // ④ KP-8：护甲负值 → 夹到 0（不能出现负护甲进战斗公式）。
    await _addActorViaSheet(
      tester,
      name: '负护甲',
      dex: '50',
      hp: '10',
      actions: '1',
      armor: '-5',
      npc: false,
    );
    expect(local.pendingActors.last['armor'], 0,
        reason: 'KP-8：护甲 -5 必须静默夹到 0');

    expect(local.pendingActors.length, 4);
    expect(tester.takeException(), isNull,
        reason: '越界只静默夹取，不许弹错 / 抛异常');
  });

  // ========================================================
  // TB5 · 候选行字段展示（老 APP :4112-4130 口径；渲染点在左窄栏 NPC tab）
  // ========================================================
  testWidgets('TB5 左栏候选行显示 DEX 30 / HP 25 / 每轮 2 次',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    await tester.pumpWidget(_hostBlock(f, const GpKpLeft()));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 0);
    await tester.pump();

    await _addActorViaSheet(
        tester, name: '值钱怪', dex: '30', hp: '25', actions: '2');
    expect(find.text('值钱怪（npc） · DEX 30 · HP 25 · 每轮 2 次'),
        findsOneWidget,
        reason: '候选行必须把数值摊出来，不能只有名字（KP-10 后只剩左栏这一处）');

    // 每轮 1 次时不追加「每轮 k 次」（老 APP 只在 k>1 才显示）。
    await _addActorViaSheet(
      tester,
      name: '普通怪',
      dex: '50',
      hp: '10',
      actions: '1',
      npc: false,
    );
    expect(find.text('普通怪（monster） · DEX 50 · HP 10'), findsOneWidget,
        reason: 'k=1 时不得追加「每轮 1 次」');
    expect(find.text('值钱怪（npc） · DEX 30 · HP 25 · 每轮 2 次'),
        findsOneWidget, reason: '第一行仍在');
    expect(f.localOf(kHostSeat).pendingActors.length, 2);
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // TB6 · KP-10：工具窄栏内联表单退役，左栏弹层是唯一入口
  // ========================================================
  testWidgets('TB6 工具窄栏无加怪表单（KP-10）；左栏弹层口径仍是六字段',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);

    // ① 工具窄栏：8 个内联表单 key 一个都不许渲染。
    await tester.pumpWidget(_hostBlock(f, const GpKpTools()));
    await tester.pump();
    for (final k in <Key>[
      GpKpToolsKeys.actorName,
      GpKpToolsKeys.actorDex,
      GpKpToolsKeys.actorHp,
      GpKpToolsKeys.actorActions,
      GpKpToolsKeys.actorKindMonster,
      GpKpToolsKeys.actorKindNpc,
      GpKpToolsKeys.addActor,
      GpKpToolsKeys.upload,
    ]) {
      expect(find.byKey(k), findsNothing,
          reason: 'KP-10：工具窄栏不该再渲染 $k');
    }

    // ② 左栏走弹层 → 六字段（含 armor）与候选行文本都对。
    await tester.pumpWidget(_hostBlock(f, const GpKpLeft()));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 0);
    await tester.pump();

    await _addActorViaSheet(
      tester,
      name: '左栏怪',
      dex: '30',
      hp: '25',
      actions: '2',
      armor: '3',
    );

    final rows = f.localOf(kHostSeat).pendingActors;
    expect(rows.length, 1);
    final r = rows.single;
    expect(r['name'], '左栏怪');
    expect(r['dex'], 30);
    expect(r['hp'], 25);
    expect(r['hpMax'], 25);
    expect(r['kind'], 'npc');
    expect(r['actionsPerRound'], 2);
    expect(r['armor'], 3);
    expect(find.text('左栏怪（npc） · DEX 30 · HP 25 · 每轮 2 次'),
        findsOneWidget, reason: '左栏候选行同样补了字段展示');
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // TB7 · 回归：A 批 T8 几何不变量（加了缩略图仍不许裁按钮）
  // ========================================================
  // ★ P16 KP-2：素材行「封面」按钮已删除，只剩 公开/隐藏 + 删除 两个；
  //   本用例保留原始几何口径（逐键量 Rect、热区 ≥48），并补一条
  //   「封面不存在」的正向反证。
  testWidgets('TB7 1280 档：缩略图加入后素材按钮不出格、热区 ≥48×48',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    _seedAsset(f, id: 'tb7asset', name: '测试底图', data: '');
    f.pageBuilder = (String s, String r) => const RoomGamePage();
    useRoomScreen(tester, 1280, 800);
    await tester.pumpWidget(f.pageOf(kHostSeat));
    await tester.pump();

    f.localOf(kHostSeat).setTab('left', 1);
    await tester.pump();

    final cell =
        tester.getRect(find.byKey(RoomKeys.keyOfSlot(RoomSlot.gpKpLeft)));
    for (final key in <Key>[
      GpKpLeftKeys.reveal('tb7asset'),
      GpKpLeftKeys.delete('tb7asset'),
    ]) {
      final r = tester.getRect(find.byKey(key));
      expect(r.left, greaterThanOrEqualTo(cell.left - 0.5),
          reason: '$key 左越出左窄栏');
      expect(r.right, lessThanOrEqualTo(cell.right + 0.5),
          reason: '$key 右越出左窄栏（用户截图「右半边被裁」）');
      expect(r.width, greaterThanOrEqualTo(48 - 0.5),
          reason: '$key 热区宽度被压到 48 以下');
      expect(r.height, greaterThanOrEqualTo(48 - 0.5),
          reason: '$key 热区高度被压到 48 以下');
    }
    // ★ P16 KP-2 正向反证：封面按钮已删（key 与文案都不得残留）。
    expect(find.byKey(GpKpLeftKeys.cover('tb7asset')), findsNothing,
        reason: 'KP-2：素材行不再有「封面」按钮');
    expect(find.text('封面'), findsNothing, reason: '「封面」文案已随按钮退场');
    // 缩略图确实渲染在名字行里（空 data → 占位，不炸）。
    expect(find.byKey(GpKpLeftKeys.thumb('tb7asset')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ========================================================
  // TB8 · T-30 契约：加怪按钮 enabled 恰好恒等闸门（KP-10 后只剩左栏入口）
  // ========================================================
  testWidgets('TB8 T-30：左栏加怪 enabled 恒等 gate.can(combat.start)',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot(inGame: true);
    final gateCan = f.controllerOf(kHostSeat).gate.can('combat.start');
    expect(gateCan, isTrue, reason: 'KP 开团中应能准备战斗（用例前置）');

    // ① 左栏：enabled 恒等闸门（弹层前置条件不许叠加到按钮上）。
    await tester.pumpWidget(_hostBlock(f, const GpKpLeft()));
    await tester.pump();
    f.localOf(kHostSeat).setTab('left', 0);
    await tester.pump();
    expect(
      tester.widget<RoomTap>(find.byKey(GpKpLeftKeys.addActor)).enabled,
      gateCan,
      reason: '左窄栏 addActor 的 enabled 不许叠加任何业务前置条件',
    );

    // ② 弹层取消（等价原来的「表单清空」）→ enabled 仍必须不变。
    await _tap(tester, find.byKey(GpKpLeftKeys.addActor));
    await tester.pump(const Duration(milliseconds: 400));
    await _tap(tester, find.byKey(AddActorSheetKeys.cancel));
    await tester.pump(const Duration(milliseconds: 400));
    expect(f.localOf(kHostSeat).pendingActors, isEmpty,
        reason: '取消弹层不许写本地候选');
    expect(
      tester.widget<RoomTap>(find.byKey(GpKpLeftKeys.addActor)).enabled,
      gateCan,
      reason: '取消弹层后按钮可点性不得漂移',
    );

    // ③ KP-10：工具窄栏那半段已退役 —— 直接反证「本栏不含加怪按钮」。
    await tester.pumpWidget(_hostBlock(f, const GpKpTools()));
    await tester.pump();
    expect(find.byKey(GpKpToolsKeys.addActor), findsNothing,
        reason: 'KP-10：工具窄栏不再有加怪按钮（唯一入口在左栏）');
    expect(find.byKey(GpKpToolsKeys.actorName), findsNothing,
        reason: 'KP-10：工具窄栏不再有内联名称输入');
    expect(tester.takeException(), isNull);
  });
}
