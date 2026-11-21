// ============================================================
// test/p12_pl1_actor_visible_test.dart — P12 / 第 9 期 · PL-1a / PL-1b
//
//   · 「加怪」弹层新增「是否显示给玩家」勾选（默认不勾，防泄露）；
//   · 候选怪阶段也能切换（GpKpLeftKeys.toggleActorVisible），
//     addLocalActor 总是写显式 visibleToPlayers 键；
//   · 玩家裁剪态 makeSync 新增的 actors 视图：只有 visibleToPlayers==true
//     的记录下发，且**每条恰好 id + name**（无 hp/skill/value/attr…）；
//     仅当任一记录显式带该键时才加 actors 键（老存档 / oracle 零漂移）；
//   · 主动对抗目标列表出现该名字且可点，未勾选者完全不出现；
//   · combatFor 按同一标志过滤怪物槽；KP 全量 13 键视图逐字不动。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/sheets/sheet_add_actor.dart'
    show AddActorSheetKeys, openAddActorSheet;
import 'package:dice_realm/ui/room/widgets/gp_kp_left.dart'
    show GpKpLeft, GpKpLeftKeys;
import 'package:dice_realm/ui/room/widgets/gp_kp_tools.dart' show addLocalActor;
import 'package:dice_realm/ui/room/widgets/unit_picker.dart'
    show RoomUnitOption, collectUnitOptions, isPlayerVisibleActorRecord,
        showUnitPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 打开加怪弹层的小宿主（捕获 openAddActorSheet 返回的草稿）。
Widget _sheetApp(void Function(Map<String, Object?>? r) onResult) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext ctx) => ElevatedButton(
              key: const ValueKey<String>('openAddActor'),
              onPressed: () async => onResult(await openAddActorSheet(ctx)),
              child: const Text('打开加怪弹层'),
            ),
          ),
        ),
      ),
    );

Widget _scopedApp(RoomUiFixture f, String seat, Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(body: f.scoped(seat, child: child)),
    );

/// 一条「本期」怪物记录：带显式 visibleToPlayers + 全部属性。
Map<String, Object?> _monster(String id, String name, bool visible) =>
    <String, Object?>{
      'id': id,
      'name': name,
      'kind': 'monster',
      'hp': 20,
      'hpMax': 20,
      'dex': 50,
      'skill': 70,
      'value': 60,
      'armor': 2,
      'attrs': <String, Object?>{'str': 80},
      'secret': 'KP 专有',
      'kpOnly': '不下发',
      'visibleToPlayers': visible,
    };

void main() {
  group('A · PL-1a 加怪弹层：默认不勾、可勾、七字段草稿', () {
    testWidgets('默认不勾选，取消前直接确定 → visibleToPlayers=false + 既有 6 键',
        (WidgetTester tester) async {
      Map<String, Object?>? result;
      await tester.pumpWidget(_sheetApp((Map<String, Object?>? r) => result = r));
      await tester.tap(find.byKey(const ValueKey<String>('openAddActor')));
      await tester.pumpAndSettle();

      expect(find.byKey(AddActorSheetKeys.visibleToPlayers), findsOneWidget,
          reason: '★ 勾选入口必须存在');
      final Finder box = find.descendant(
        of: find.byKey(AddActorSheetKeys.visibleToPlayers),
        matching: find.byType(Checkbox),
      );
      expect(tester.widget<Checkbox>(box).value, isFalse,
          reason: '★ Q6：默认不勾选（防泄露）');
      expect(find.text('是否显示给玩家'), findsOneWidget);

      await tester.tap(find.byKey(AddActorSheetKeys.confirm));
      await tester.pumpAndSettle();
      expect(result, isNotNull, reason: '确定应返回草稿');
      expect(result!['visibleToPlayers'], false);
      for (final String k in <String>[
        'name',
        'kind',
        'dex',
        'hp',
        'actionsPerRound',
        'armor',
      ]) {
        expect(result!.containsKey(k), isTrue,
            reason: '既有 6 键逐字保留，缺 $k');
      }
      expect(result!.length, 7, reason: '恰好 6 旧键 + 1 新键');
      expect(tester.takeException(), isNull);
    });

    testWidgets('勾选后确定 → visibleToPlayers=true',
        (WidgetTester tester) async {
      Map<String, Object?>? result;
      await tester.pumpWidget(_sheetApp((Map<String, Object?>? r) => result = r));
      await tester.tap(find.byKey(const ValueKey<String>('openAddActor')));
      await tester.pumpAndSettle();
      final Finder box = find.descendant(
        of: find.byKey(AddActorSheetKeys.visibleToPlayers),
        matching: find.byType(Checkbox),
      );
      await tester.tap(box);
      await tester.pump();
      expect(tester.widget<Checkbox>(box).value, isTrue);
      await tester.tap(find.byKey(AddActorSheetKeys.confirm));
      await tester.pumpAndSettle();
      expect(result!['visibleToPlayers'], true);
    });
  });

  group('B · PL-1a 候选阶段可切换，addLocalActor 总写显式键', () {
    test('addLocalActor 默认 false、显式带键；可传 true', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      final local = f.localOf(kHostSeat);
      final Map<String, Object?> a = addLocalActor(local, name: '深潜者');
      expect(a.containsKey('visibleToPlayers'), isTrue,
          reason: '★ 总是写这一键，权威端据此判断要不要下发 actors');
      expect(a['visibleToPlayers'], false);
      final Map<String, Object?> b =
          addLocalActor(local, name: '拜亚基', visibleToPlayers: true);
      expect(b['visibleToPlayers'], true);
      expect(local.pendingActors.length, 2);
    });

    testWidgets('GpKpLeft NPC tab 可切换候选怪可见性',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final Map<String, Object?> rec =
          addLocalActor(f.localOf(kHostSeat), name: '深潜者');
      f.localOf(kHostSeat).setTab('left', 0); // ★ P13 MAP-1：0=NPC·怪物（旧 1）
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_scopedApp(f, kHostSeat, const GpKpLeft()));
      await tester.pump();

      final Finder toggle = find.byKey(
          GpKpLeftKeys.toggleActorVisible(jsStr(rec['id'])));
      expect(toggle, findsOneWidget, reason: '候选阶段必须有切换入口');
      expect(rec['visibleToPlayers'], false);
      await tester.tap(toggle);
      await tester.pump();
      expect(rec['visibleToPlayers'], true,
          reason: '★ 切换必须写回 pendingActors[i]');
      await tester.tap(toggle);
      await tester.pump();
      expect(rec['visibleToPlayers'], false, reason: '可反复切换');
      expect(tester.takeException(), isNull);
    });
  });

  group('C · PL-1b 玩家裁剪态 actors：仅 id/name、仅可见者、oracle 零漂移', () {
    test('makeSync(p1) 每条恰好 id+name，属性一律不下发', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      f.host.localActors
        ..add(_monster('m1', '深潜者', true))
        ..add(_monster('m2', '隐藏怪', false));

      final Map<String, Object?> view = f.host.makeSync('p1').state;
      final List<Object?> actors = asList(view['actors']);
      expect(actors.length, 1,
          reason: '★ 只有 visibleToPlayers==true 的记录下发，未勾选者完全不下发');
      final Map<String, Object?> rec = asMap(actors.first);
      expect(rec.keys.toSet(), <String>{'id', 'name'},
          reason: '★ 每条恰好两个键，实测 ${rec.keys}');
      expect(jsStr(rec['name']), '深潜者');
      for (final String k in <String>[
        'hp',
        'hpMax',
        'dex',
        'skill',
        'value',
        'armor',
        'attrs',
        'secret',
        'kpOnly',
        'visibleToPlayers',
      ]) {
        expect(rec.containsKey(k), isFalse, reason: '属性 $k 不该下发');
      }
      expect(isPlayerVisibleActorRecord(actors.first), isTrue);
      expect(
        isPlayerVisibleActorRecord(<String, Object?>{
          'id': 'x',
          'name': 'y',
          'hp': 1,
        }),
        isFalse,
        reason: '带属性记录不算裁剪态记录',
      );

      // ★ KP 全量视图仍是既有 13 键，不含 actors（R7 逐字不动）。
      final Map<String, Object?> kpView = f.host.makeSync(kHostSeat).state;
      expect(kpView.length, 13, reason: 'KP 13 键视图零漂移，实测 ${kpView.keys}');
      expect(kpView.containsKey('actors'), isFalse);
    });

    test('仅当任一记录显式带 visibleToPlayers 才加 actors 键（老存档零漂移）',
        () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      f.host.localActors.add(<String, Object?>{
        'id': 'old',
        'name': '老怪',
        'kind': 'monster',
        'hp': 10,
      });
      final Map<String, Object?> view = f.host.makeSync('p1').state;
      expect(view.containsKey('actors'), isFalse,
          reason: '★ 老存档 / oracle 形态的 13 键 view 逐字节不变');
      expect(view.length, 13);
    });

    test('combatFor(p1) 过滤显式隐藏的非 PC 槽，PC 槽永不过滤', () {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      f.hostState()['combat'] = <String, Object?>{
        'order': <Object?>[
          <String, Object?>{
            'id': 's1',
            'name': '深潜者',
            'kind': 'monster',
            'visibleToPlayers': true,
            'public': <String, Object?>{'hp': 10, 'hpMax': 10},
          },
          <String, Object?>{
            'id': 's2',
            'name': '隐藏怪',
            'kind': 'monster',
            'visibleToPlayers': false,
            'public': <String, Object?>{'hp': 10, 'hpMax': 10},
          },
          <String, Object?>{
            'id': 'p1',
            'name': '玩家',
            'kind': 'pc',
            'visibleToPlayers': false,
          },
        ],
      };
      final List<Object?> order =
          asList(asMap(f.host.combatFor('p1'))['order']);
      expect(order.length, 2, reason: '隐藏怪被过滤，PC 槽保留');
      expect(order.any((Object? e) => jsStr(asMap(e)['name']) == '隐藏怪'),
          isFalse);
      expect(order.any((Object? e) => jsStr(asMap(e)['id']) == 'p1'), isTrue);
      expect(asList(asMap(f.host.combatFor(kHostSeat))['order']).length, 3,
          reason: 'KP 全量不受影响');
    });
  });

  group('D · PL-1b 主动对抗目标列表：出现可见怪且可点，未勾选者不出现', () {
    test('collectUnitOptions 对裁剪态 actors 列出 a:<id>，隐藏怪不出现', () {
      final Map<String, Object?> playerState = <String, Object?>{
        'members': <Object?>[],
        'combat': <String, Object?>{'order': <Object?>[]},
        'actors': <Object?>[
          <String, Object?>{'id': 'm1', 'name': '深潜者'},
        ],
      };
      final List<RoomUnitOption> opts = collectUnitOptions(playerState);
      final RoomUnitOption visible = opts.firstWhere(
        (RoomUnitOption o) => o.value == 'a:m1',
        orElse: () => const RoomUnitOption(
            value: '<missing>', label: '<missing>', kind: 'none'),
      );
      expect(visible.value, 'a:m1', reason: '目标列表必须出现可见怪');
      expect(visible.label.contains('深潜者'), isTrue);
      expect(visible.kind, 'monster');
      expect(opts.any((RoomUnitOption o) => o.value == 'a:m2'), isFalse,
          reason: '未勾选者完全不出现');
      expect(opts.first.value, '*', reason: '首位仍是「全体」项');
    });

    testWidgets('showUnitPicker 里该名字的条目存在且可点（点击回传 option）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      // 让会话 state 带上裁剪态 actors（与 makeSync 下发的形状一致）。
      f.hostState()['actors'] = <Object?>[
        <String, Object?>{'id': 'm1', 'name': '深潜者'},
      ];
      RoomUnitOption? picked;
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(_scopedApp(
        f,
        kHostSeat,
        Builder(
          builder: (BuildContext ctx) => ElevatedButton(
            key: const ValueKey<String>('openPicker'),
            onPressed: () async {
              picked = await showUnitPicker(ctx, title: '选择目标');
            },
            child: const Text('打开目标列表'),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey<String>('openPicker')));
      await tester.pumpAndSettle();

      final Finder option =
          find.byKey(const ValueKey<String>('unitPicker/a:m1'));
      expect(option, findsOneWidget,
          reason: '★ 目标列表应出现可见怪「深潜者」且可定位');
      expect(find.textContaining('深潜者'), findsWidgets);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(picked, isNotNull, reason: '★ 点击应回传选中项（可点）');
      expect(picked!.value, 'a:m1');
      expect(tester.takeException(), isNull);
    });
  });
}
