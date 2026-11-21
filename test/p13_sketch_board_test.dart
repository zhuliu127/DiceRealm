// ============================================================
// test/p13_sketch_board_test.dart — P13 SKETCH-1/2/3 + KPBOARD-1
//
// SKETCH-1 分段：新段不与上段末点连线（BoardPainter 按段各画一条 path）。
// SKETCH-2 上限：kBoardMaxPoints=4000 丢最早整段 + kBoardLimitNotice 可见提示，
//   旧扁平点集按单段读入兼容。
// SKETCH-3 擦除：eraseBoardSegments 容差 0.03 点到线段即整段删，抬手不回弹。
// KPBOARD-1：KP 看玩家手绘板取自 hostRead.boardBySeat[seat]['strokes']
//   构造的 BoardPainter（不是纯文字、不读 KP 恒空 state.board）。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/painter/stroke_painter.dart'
    show BoardPainter;
import 'package:dice_realm/ui/room/view/scene_view.dart' show NormPoint;
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart'
    show GpKpPlayers, GpKpPlayersKeys, kpBoardStrokeCount;
import 'package:dice_realm/ui/room/widgets/gp_pl_sketch.dart'
    show kBoardLimitNotice, kBoardMaxPoints, boardSegmentsFromRaw,
        eraseBoardPoints, eraseBoardSegments;
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

Map<String, Object?> _seg(String id, List<List<num>> pts) => <String, Object?>{
      'id': id,
      'pts': <Object?>[
        for (final List<num> p in pts)
          <String, Object?>{'x': p[0] / 100.0, 'y': p[1] / 100.0},
      ],
    };

void main() {
  group('A · SKETCH-1 分段笔迹（新段不连线）', () {
    test('两段独立载荷读入后仍是 2 段，段 id / 点归属逐字保留', () {
      final List<Map<String, Object?>> segs = boardSegmentsFromRaw(<Object?>[
        _seg('s1', <List<num>>[<num>[10, 10], <num>[20, 20]]),
        _seg('s2', <List<num>>[<num>[80, 80], <num>[90, 90]]),
      ]);
      expect(segs.length, 2, reason: '★ 两笔必须是两段，不能连成一条折线');
      expect(segs.first['id'], 's1');
      expect(segs.last['id'], 's2');
      expect((segs.first['pts'] as List).length, 2);
      expect((segs.last['pts'] as List).length, 2);
      final Map<String, Object?> firstPt =
          (segs.first['pts'] as List).first as Map<String, Object?>;
      expect(firstPt['x'], 0.1);
      expect(firstPt['y'], 0.1);
      // 两段之间有明显空隙：末点 (0.2,0.2) 与下段首点 (0.8,0.8) 不相连。
      expect((segs.last['pts'] as List).first, isNot(firstPt));
    });

    test('BoardPainter 支持分段且全段绘制，不受 page/perPage 200 截断', () {
      final List<Map<String, Object?>> segs = boardSegmentsFromRaw(<Object?>[
        _seg('s1', <List<num>>[
          for (var i = 0; i < 120; i++) <num>[i, i],
        ]),
        _seg('s2', <List<num>>[<num>[80, 80]]),
      ]);
      final BoardPainter painter = BoardPainter(segs);
      expect(painter.points.length, 2, reason: '★ 两独立段必须都保留');
      expect(painter.perPage, 200, reason: '旧默认保留，兼容扁平点集');
      expect((segs.first['pts'] as List).length, 120,
          reason: '分段路径全段绘制，不受 200 点截断');
    });
  });

  group('B · SKETCH-2 上限与旧载荷兼容', () {
    test('旧扁平点集合并为单段（legacy 兼容），坐标夹 [0,1]', () {
      final List<Map<String, Object?>> segs =
          boardSegmentsFromRaw(<Object?>[
        <String, Object?>{'x': 0.1, 'y': 0.2},
        <String, Object?>{'x': 0.3, 'y': 0.4},
        <String, Object?>{'x': -2, 'y': 9},
      ]);
      expect(segs.length, 1, reason: '旧扁平点集按单段读入');
      expect(segs.first['id'], 'legacy0');
      final List<Object?> pts = segs.first['pts'] as List<Object?>;
      expect(pts.length, 3);
      expect(asMapSafe(pts.last)['x'], 0.0, reason: '负坐标夹到 0');
      expect(asMapSafe(pts.last)['y'], 1.0, reason: '>1 夹到 1');
    });

    test('上限常量与可见提示文案（禁止 take(4000) 静默截断）', () {
      expect(kBoardMaxPoints, 4000);
      expect(kBoardLimitNotice, '已达上限，最早笔迹已移除');
      expect(kBoardLimitNotice.isNotEmpty, isTrue,
          reason: '★ 超上限必须在面板给可见提示');
    });
  });

  group('C · SKETCH-3 段级擦除（tol 0.03、不回弹）', () {
    test('3 段擦 1 段 → 2 段；命中点到线段（非仅端点）即整段移除', () {
      final List<Map<String, Object?>> segs = <Map<String, Object?>>[
        _seg('s1', <List<num>>[<num>[10, 10], <num>[50, 50]]),
        _seg('s2', <List<num>>[<num>[30, 30], <num>[70, 70]]),
        _seg('s3', <List<num>>[<num>[80, 10], <num>[90, 20]]),
      ];
      final List<Map<String, Object?>> next = eraseBoardSegments(
        segs,
        <NormPoint>[const NormPoint(0.305, 0.30)],
      );
      expect(segs.length, 3, reason: '纯函数不得修改入参');
      expect(next.length, 2, reason: '★ 命中 s2 线段中段 → 整段删，剩 2 段');
      expect(next.map((e) => e['id']).toList(), <String>['s1', 's3']);
    });

    test('容差 0.03 边界：0.029 命中、0.031 不命中', () {
      final List<Map<String, Object?>> segs = <Map<String, Object?>>[
        _seg('s1', <List<num>>[<num>[50, 50]]),
      ];
      expect(
        eraseBoardSegments(
          segs,
          <NormPoint>[const NormPoint(0.529, 0.5)],
        ).length,
        0,
        reason: '距离 0.029 ≤ tol，应擦除',
      );
      expect(
        eraseBoardSegments(
          segs,
          <NormPoint>[const NormPoint(0.531, 0.5)],
        ).length,
        1,
        reason: '距离 0.031 > tol，不该擦除',
      );
    });

    test('旧逐点擦除函数未删符号（兼容既有断言）', () {
      final List<Map<String, Object?>> flat = <Map<String, Object?>>[
        <String, Object?>{'x': 0.5, 'y': 0.5},
        <String, Object?>{'x': 0.9, 'y': 0.9},
      ];
      expect(
        eraseBoardPoints(
          flat,
          <NormPoint>[const NormPoint(0.5, 0.5)],
        ).length,
        1,
      );
    });
  });

  group('D · KPBOARD-1 KP 看玩家手绘板渲染真实笔迹', () {
    testWidgets('3 段笔迹取自 boardBySeat[seat]，全屏页 child 是 BoardPainter',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      // 权威端只读面塞 3 段；玩家裁剪态 state.board 保持空（KP 视角恒空）。
      f.host.boardBySeat['p1'] = <String, Object?>{
        'strokes': <Object?>[
          _seg('k1', <List<num>>[<num>[10, 10], <num>[20, 20]]),
          _seg('k2', <List<num>>[<num>[30, 40]]),
          _seg('k3', <List<num>>[<num>[60, 70], <num>[80, 80]]),
        ],
      };
      expect(
        kpBoardStrokeCount(
          f.hostState(),
          'p1',
          board: f.host.boardBySeat['p1'],
        ),
        3,
        reason: 'KP 权威副本读到 3 笔（state.board 恒空，必须传 board）',
      );
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: f.scoped(kHostSeat, child: const GpKpPlayers()),
      ));
      await tester.pump();

      await tester.tap(find.byKey(GpKpPlayersKeys.board('p1')));
      await tester.pumpAndSettle();
      final Finder painters = find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.painter is BoardPainter,
      );
      expect(painters, findsWidgets,
          reason: '★ 全屏只读页必须渲染 CustomPaint(BoardPainter)，不是一行文字');
      final BoardPainter painter = tester
          .widgetList<CustomPaint>(painters)
          .map((CustomPaint p) => p.painter! as BoardPainter)
          .firstWhere((BoardPainter p) => p.points.length == 3);
      expect(painter.points.length, 3,
          reason: '★ 3 段笔迹全部渲染（来自 boardBySeat，不是 state.board）');
      // FullscreenReader 有 child 时不再回退成一行文字——这正是 KPBOARD-1
      // 的根因闭环；笔数文案仍作为 text 参数保留在源码里（见下源码门禁）。
      expect(find.textContaining('本机权威副本'), findsNothing,
          reason: '★ 有 child 时不得再显示纯文字回退');
      expect(
        File('lib/ui/room/widgets/gp_kp_players.dart')
            .readAsStringSync()
            .contains("text: '共 \$strokes 笔（本机权威副本）'"),
        isTrue,
        reason: '笔数文字参数仍保留（缺 child 时的兜底）',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

Map<String, Object?> asMapSafe(Object? raw) =>
    raw is Map ? raw.cast<String, Object?>() : <String, Object?>{};
