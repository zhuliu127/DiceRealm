// ============================================================
// test/p18_house_rules_test.dart — P18 房规（d100 检定阈值）
//
// 用户需求：
//   ① KP 在**招募时**就能设置房规 —— 大成功上限（输入 5 → 掷 1–5 全是
//      大成功）、大失败下限（输入 96 → 掷 96–100 全是大失败）。
//   ② 所有骰子检定除了数值还要显示成功等级（大成功 / 极难成功 / 困难成功 /
//      常规成功 / 失败 / 大失败）。
//
// 落点事实（P18 实现依据，动手前已逐条核过源码）：
//   · 规则层**早已支持**：`room_rules_core.dart` 的 `_levelOf` 里
//     `v <= _critThresholdOf(opts) → 5`（≤critMax 全大成功）、
//     `_isFumble` 里 `fumbleMin>0 → [min,100]`（≥fumbleMin 全大失败）；
//     房间 meta 的 `critThreshold` / `fumbleThreshold` 经
//     `room_model_state.dart ruleOptsOf`（1–99 校验）翻成
//     `{critMax, fumbleMin}`，并在 `room_model_actions_combat.dart` 的
//     7 处规则调用透传 —— 骰子 / 检定 / 对抗 / 疯狂 / 场景检定全部吃房规。
//   · 等级文本：`CocRules.LEVEL_TEXT` 六级齐全（大成功 / 极难成功 /
//     困难成功 / 常规成功 / 失败 / 大失败），公开骰单 `diceLine`
//     （`feed_view.dart:221`）与对抗结果文本（`room_model_actions_combat.dart:920`）
//     都拼 ` · $levelText`，暗骰私账同带 —— **显示侧不需要改**。
//   · 本批新增的只是**入口**：招募大厅的房规区（KP 可设 / 其余视角只读），
//     复用既有 `room.rules` op（POLICY `[kp]`，不新增 action，
//     `kRoomPolicy.length == 61` 不变）。
//
// 反向自证伪：
//   · 把 `_RuleCfgBlockState._save` 的 1–99 守卫删掉 → 用例 3 必红；
//   · 把 `_ruleView` 的渲染条件改成 `if (isKp)` → 用例 5 必红。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

Widget _app(RoomUiFixture f, String seat) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: f.scoped(seat, child: const RoomLobbyPage()),
    );

Future<void> _pumpLobby(
  WidgetTester tester,
  RoomUiFixture f, [
  String seat = kHostSeat,
]) async {
  useRoomScreen(tester, 900, 2400);
  await tester.pumpWidget(_app(f, seat));
  await tester.pump();
}

Future<void> _enterText(
  WidgetTester tester,
  Key field,
  String text,
) async {
  await tester.enterText(find.byKey(field), text);
  await tester.pump();
}

void main() {
  testWidgets('KP 招募大厅：房规区可见，未设置时初值 1 / 96（与骰子工具同口径）',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    await _pumpLobby(tester, f);

    expect(find.byKey(RoomLobbyKeys.ruleCrit), findsOneWidget);
    expect(find.byKey(RoomLobbyKeys.ruleFumble), findsOneWidget);
    expect(find.byKey(RoomLobbyKeys.ruleSave), findsOneWidget,
        reason: 'KP 在招募期就要能设置房规');

    final TextField crit =
        tester.widget<TextField>(find.byKey(RoomLobbyKeys.ruleCrit));
    final TextField fumble =
        tester.widget<TextField>(find.byKey(RoomLobbyKeys.ruleFumble));
    expect(crit.controller!.text, '1',
        reason: 'meta 未设置 → 显示默认大成功 01');
    expect(fumble.controller!.text, '96',
        reason: 'meta 未设置 → 显示默认大失败下限 96');
  });

  testWidgets('KP 填 5 / 96 保存 → 真发包 room.rules，payload 逐字段',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    await _pumpLobby(tester, f);

    await _enterText(tester, RoomLobbyKeys.ruleCrit, '5');
    await _enterText(tester, RoomLobbyKeys.ruleFumble, '96');
    f.clearSent();
    await tester.tap(find.byKey(RoomLobbyKeys.ruleSave));
    await tester.pump();

    final p = asMapOf(f.lastSent(action: 'room.rules')?['p']);
    expect(p, isNotNull, reason: '保存必须真的发包');
    expect(p['critThreshold'], 5,
        reason: '用户例子：大成功上限 5 → 之后掷 1–5 全判大成功');
    expect(p['fumbleThreshold'], 96,
        reason: '用户例子：大失败下限 96 → 之后掷 96–100 全判大失败');
    expect(f.localOf(kHostSeat).notice, contains('已保存'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('KP 填 0 / 100 保存 → 不发包 + 明确提示（domain 静默忽略非法值）',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    await _pumpLobby(tester, f);

    await _enterText(tester, RoomLobbyKeys.ruleCrit, '0');
    await _enterText(tester, RoomLobbyKeys.ruleFumble, '100');
    f.clearSent();
    await tester.tap(find.byKey(RoomLobbyKeys.ruleSave));
    await tester.pump();

    expect(f.lastSent(action: 'room.rules'), isNull,
        reason: '越界值不许发包 —— domain 的 ruleOptsOf 会静默忽略，'
            'UI 不拦的话 KP 会以为设置成功了');
    expect(f.localOf(kHostSeat).notice, contains('1–99'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('meta 已设置 → 输入框初值回填真实房规',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    f.hostState()['meta'] = <String, Object?>{
      'critThreshold': 20,
      'fumbleThreshold': 90,
    };
    await _pumpLobby(tester, f);

    final TextField crit =
        tester.widget<TextField>(find.byKey(RoomLobbyKeys.ruleCrit));
    final TextField fumble =
        tester.widget<TextField>(find.byKey(RoomLobbyKeys.ruleFumble));
    expect(crit.controller!.text, '20');
    expect(fumble.controller!.text, '90');
  });

  testWidgets('玩家视角：只读看到当前房规，KP 编辑区结构上不渲染',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    // ★ 玩家页必须用该座位的**裁剪后**状态建页（T8）——hostState 是 KP 权威
    //   态，改它不影响玩家 session（本用例首跑实测踩过：显示成默认值）。
    f.stateOf('p1')['meta'] = <String, Object?>{
      'critThreshold': 5,
      'fumbleThreshold': 96,
    };
    await _pumpLobby(tester, f, 'p1');

    expect(find.byKey(RoomLobbyKeys.ruleSave), findsNothing,
        reason: '玩家不渲染保存按钮（结构式权限，不是 enabled:false）');
    expect(find.byKey(RoomLobbyKeys.ruleCrit), findsNothing);
    expect(find.byKey(RoomLobbyKeys.ruleView), findsOneWidget);
    expect(find.textContaining('大成功：掷出 ≤ 5'), findsOneWidget,
        reason: '玩家掷骰前要知道这个房的大成功阈值');
    expect(find.textContaining('大失败：掷出 ≥ 96'), findsOneWidget);
  });

  testWidgets('旁观视角：同样只读可见（掷骰结果对旁观也广播）',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    await _pumpLobby(tester, f, 'sp1');

    expect(find.byKey(RoomLobbyKeys.ruleSave), findsNothing);
    expect(find.byKey(RoomLobbyKeys.ruleView), findsOneWidget);
    // 夹具默认 meta = critThreshold 1 / fumbleThreshold 100 —— 前者显式等价
    // 默认（仅 01），后者经 `ruleOptsOf` 的 1–99 校验回落动态规则。
    expect(find.textContaining('大成功：掷出 ≤ 1'), findsOneWidget,
        reason: '未设置时如实显示默认语义，不显示假阈值');
    expect(find.textContaining('大失败：默认'), findsOneWidget);
  });

  testWidgets('保存按钮可点性恒等 POLICY（T-30 口径）',
      (WidgetTester tester) async {
    final f = RoomUiFixture();
    await f.boot();
    await _pumpLobby(tester, f);
    final tap = tester.widget<RoomTap>(find.byKey(RoomLobbyKeys.ruleSave));
    expect(tap.enabled, f.controllerOf(kHostSeat).gate.can('room.rules'));
  });
}

/// harness 的 `lastSent(...)?['p']` 返回 `Object?`，这里安全转 Map。
Map<String, Object?> asMapOf(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) {
    return <String, Object?>{for (final k in raw.keys) '$k': raw[k]};
  }
  return const <String, Object?>{};
}
