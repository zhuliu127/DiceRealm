// ============================================================
// widgets/gp_pl_sketch.dart — 块 10（玩家）：我的手绘板
//
// ★ 数据形状（P13 T3，对齐 KP 舞台 `gp_map_stage.dart`）：`strokes` 是
//   **分段笔迹** `[{id, pts:[{x,y},...]}, ...]`，每段各画一条 path、跨段
//   不连线。手势：panStart 开新段 → panUpdate 段内采点 → panEnd 整段一次
//   `INTENT.BOARD{strokes:<全量分段>}` 提交（与 KP `map.strokes.set` 同口径）。
//
// ★ 兼容（Q4）：旧扁平点集 `[{x,y}, ...]` 由 [boardSegmentsFromRaw] 按
//   **单段**读入；`BoardPainter` 同时认分段与扁平两种载荷。
//
// ★ 上限（Q3）：`kBoardMaxPoints=4000` 按**点数**计；超限**丢最早整段**并
//   经 [RoomUiLocal.showNotice] 可见提示，绝不 `take(4000)` 静默截断。
//
// ★ 橡皮（P14 改口径）：[eraseBoardSegments] 由「命中即整段删」改为
//   **点级切分**（与 KP 舞台 `eraseStrokeSegments` 同口径）：命中 path
//   （容差 0.03）的点丢弃、未命中的连续点各自成段；抬手提交后经
//   `_awaitingEcho` 本地镜像保证**不回弹**，KP 侧随 `boardBySeat` 同步。
//
// ★ 隔离（T-63）：`boardSelf` 只发 `VIS.SEAT` 给**本人**；`state.board` 只在本
//   人视图里有内容，他人 `syncFor(seat).state.board` 恒空。UI 不做二次过滤。
//
// ★ 只画、只发 intent：零权威端引用、零规则调用。
// ============================================================

import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap;
import '../../../domain/room_types.dart' show RoomIntent;
import '../painter/stroke_painter.dart' show BoardPainter;
import '../room_scope.dart';
import '../room_ui_local.dart' show BoardMode;
import '../view/member_view.dart' show hasCardVitals, memberStats;
import '../view/room_view.dart' show findMe;
import '../view/scene_view.dart' show NormPoint, clampNorm;
import 'gp_map_stage.dart' show stageNormOf;
import 'gp_pl_char_card.dart' show selfLocked;
import 'room_panel_kit.dart';

/// 手绘板点数上限：超限丢最早整段 + 可见提示（禁止静默截断）。
const int kBoardMaxPoints = 4000;

/// 上限提示文案（QA 断言的单一真源）。
const String kBoardLimitNotice = '已达上限，最早笔迹已移除';

/// 橡皮的旧逐点演算（纯函数，保留兼容既有断言）。
///
/// 新渲染路径改走段级 [eraseBoardSegments]，本函数不删符号。
List<Map<String, Object?>> eraseBoardPoints(
  List<Map<String, Object?>> points,
  List<NormPoint> path, {
  double tol = 0.03,
}) {
  if (path.isEmpty) return <Map<String, Object?>>[for (final p in points) {...p}];
  final out = <Map<String, Object?>>[];
  for (final raw in points) {
    final p = asMap(raw);
    final x = clampNorm(_num(p['x']));
    final y = clampNorm(_num(p['y']));
    var hit = false;
    for (final q in path) {
      final dx = x - q.x;
      final dy = y - q.y;
      if (dx * dx + dy * dy <= tol * tol) {
        hit = true;
        break;
      }
    }
    if (!hit) out.add(<String, Object?>{...p});
  }
  return out;
}

/// 手绘板擦除（纯函数，返回新 List、绝不修改入参）。
///
/// ★ P14：由「命中即整段移除」改为**按手指划过的位置点级切分**，与 KP 公开
///   素材舞台 `eraseStrokeSegments`（`view/scene_view.dart:201`）同口径：
///   对每段逐点判命中（点到擦除路径的**点距 / 点段距** ≤ [tol]），命中点
///   丢弃，未命中的**连续点**各自成为一条新段（跨段不连线）。
///
/// 两条收口，避免「擦一次整笔消失 / 点迹被路过擦没」：
///   · 整段**一个点都没命中** → 原样保留（含单点圆点段，橡皮路过不算擦）；
///   · 命中后被切出的**孤立单点**（run 长 < 2）→ 丢弃：它只是擦断处的碎片，
///     不是用户画出来的笔，留着会在画面上闪一堆小点。
///
/// [split] = false 是**单点点击**专用的旧口径（P13 Q5）：命中容差内即**整段
/// 移除**。为什么点按不跟拖动同口径：静止点击没有「划过的轨迹」，点一下擦掉
/// 这一笔是可解释的产品语义，且该行为已被既有断言钉死（`test/qa_236_regression_test.dart`
/// Q4-A：点按后总点数必须为 0）。
List<Map<String, Object?>> eraseBoardSegments(
  List<Map<String, Object?>> segments,
  List<NormPoint> path, {
  double tol = 0.03,
  bool split = true,
}) {
  final out = <Map<String, Object?>>[];
  if (path.isEmpty) {
    for (final s in segments) {
      out.add(<String, Object?>{...s});
    }
    return out;
  }
  for (final s in segments) {
    final pts = <NormPoint>[
      for (final p in asList(s['pts']))
        NormPoint(
          clampNorm(_num(asMap(p)['x'])),
          clampNorm(_num(asMap(p)['y'])),
        ),
    ];
    // 1) 逐点判命中，把该段切成若干「未命中的连续点」跑。
    var hitAny = false;
    final runs = <List<NormPoint>>[];
    var current = <NormPoint>[];
    for (final p in pts) {
      if (_pointNearPath(p, path, tol)) {
        hitAny = true;
        if (current.isNotEmpty) {
          runs.add(current);
          current = <NormPoint>[];
        }
      } else {
        current.add(p);
      }
    }
    if (current.isNotEmpty) runs.add(current);

    // 2) 整段未被碰到 → 原样保留（不拆、不丢单点圆点段）。
    if (!hitAny) {
      out.add(<String, Object?>{...s});
      continue;
    }

    // 2b) 单点点击口径：命中即整段移除（不保留任何残余点）。
    if (!split) continue;

    // 3) 否则按跑长 ≥ 2 重建子段（丢弃擦断处的孤立单点碎片）。
    final rawId = s['id'];
    final baseId = rawId is String && rawId.isNotEmpty ? rawId : 's${out.length}';
    var n = 0;
    for (final run in runs) {
      if (run.length < 2) continue;
      out.add(<String, Object?>{
        'id': n == 0 ? baseId : '$baseId#$n',
        'pts': <Object?>[
          for (final p in run) <String, Object?>{'x': p.x, 'y': p.y},
        ],
      });
      n++;
    }
  }
  return out;
}

bool _pointNearPath(NormPoint p, List<NormPoint> path, double tol) {
  final t2 = tol * tol;
  for (final q in path) {
    final dx = p.x - q.x;
    final dy = p.y - q.y;
    if (dx * dx + dy * dy <= t2) return true;
  }
  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1];
    final b = path[i];
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) continue;
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
    final ex = p.x - (a.x + t * dx);
    final ey = p.y - (a.y + t * dy);
    if (ex * ex + ey * ey <= t2) return true;
  }
  return false;
}

/// 原始载荷 → 分段笔迹：新结构 `{id, pts}` 原样读入；旧扁平点 `{x,y}`
/// 连续段合并为**一段**（legacy 兼容，旧画面仍是连成一条线）。
List<Map<String, Object?>> boardSegmentsFromRaw(List<Object?> raw) {
  final out = <Map<String, Object?>>[];
  List<Object?> flat = <Object?>[];
  void flushFlat() {
    if (flat.isEmpty) return;
    out.add(<String, Object?>{
      'id': 'legacy${out.length}',
      'pts': List<Object?>.of(flat),
    });
    flat = <Object?>[];
  }

  for (var i = 0; i < raw.length; i++) {
    final m = asMap(raw[i]);
    if (m.containsKey('pts')) {
      flushFlat();
      final pts = <Object?>[
        for (final p in asList(m['pts']))
          <String, Object?>{
            'x': clampNorm(_num(asMap(p)['x'])),
            'y': clampNorm(_num(asMap(p)['y'])),
          },
      ];
      if (pts.isEmpty) continue;
      final id = m['id'];
      out.add(<String, Object?>{
        'id': id is String && id.isNotEmpty ? id : 's$i',
        'pts': pts,
      });
    } else if (m.containsKey('x') || m.containsKey('y')) {
      flat.add(<String, Object?>{
        'x': clampNorm(_num(m['x'])),
        'y': clampNorm(_num(m['y'])),
      });
    }
  }
  flushFlat();
  return out;
}

/// 段集签名：判 echo 是否已到（本地乐观态与 state 收敛）。
String _boardSig(List<Map<String, Object?>> segments) =>
    jsonEncode(segments);

double _num(Object? v) => v is num ? v.toDouble() : 0;

/// 块 10：我的手绘板。
class GpPlSketch extends StatefulWidget {
  const GpPlSketch({super.key, this.height = 180, this.fill = false});

  /// 画布可视高度（块在 Wrap 里没有外部高度约束）。
  ///
  /// ★ 只在 [fill] == false 时生效（旧路径逐字不变）。
  final double height;

  /// 是否吃满父级剩余高度（2.42.0 / P20 需求 3②）。
  ///
  /// · `false`（默认）：画布高度恒为 [height]（`SizedBox`），KP 折叠档 /
  ///   dock 格 / 既有 20+ 条几何断言都依赖它 —— **一个字节都不许动**。
  /// · `true`：画布换成 `Expanded`，`SectionBox` 也切到 `expand: true`，
  ///   整块吃满父级高度。给「全屏打开手绘板」用：
  ///   `openRoomSlotFullscreen(context, title: '我的手绘板',
  ///       body: (_) => const GpPlSketch(fill: true))`。
  ///
  /// ★ 调用约束：[fill] == true 要求父级给出**有界高度**
  ///   （`Scaffold.body` / 全屏路由 body / dock 格）。放进
  ///   `SingleChildScrollView` 这类无界父级会撞「unbounded height」断言。
  final bool fill;

  @override
  State<GpPlSketch> createState() => _GpPlSketchState();
}

class _GpPlSketchState extends State<GpPlSketch> {
  /// 本次手势新采、尚未提交的点（只属当前新段）。
  final List<NormPoint> _pendingPts = <NormPoint>[];

  /// 手势路径（归一化），擦除时按它删点。
  final List<NormPoint> _path = <NormPoint>[];

  /// 擦除前的已提交段快照（手势末尾一次提交，不在中途发包）。
  List<Map<String, Object?>> _snapshot = <Map<String, Object?>>[];

  bool _dragging = false;

  /// 已提交、但尚未在 state 中出现 echo 的段集。
  ///
  /// 本地环回是同步的，但云 / 远端会话 `sendIntent` 异步；若无此镜像，
  /// 抬手当帧 painter 会读到旧 state → 笔迹/擦除「回弹」。提交后本地立即
  /// 显示本字段，待 state 收敛（签名相同）后自动透明切回 state。
  List<Map<String, Object?>>? _awaitingEcho;

  List<Map<String, Object?>> _segmentsOf(Map<String, Object?> state) =>
      boardSegmentsFromRaw(asList(asMap(state['board'])['strokes']));

  /// painter 的可见段集：未确认的本地提交优先，防跨会话回弹。
  List<Map<String, Object?>> _visible(Map<String, Object?> state) {
    final fromState = _segmentsOf(state);
    final pending = _awaitingEcho;
    if (pending != null && _boardSig(pending) != _boardSig(fromState)) {
      return pending;
    }
    return fromState;
  }

  /// 整段提交一次 `INTENT.BOARD`。`segments` 为全量分段笔迹。
  void _commit(List<Map<String, Object?>> segments) {
    final scope = RoomScope.read(context);
    final local = scope.local;

    // 归一载荷 + 上限（按整段丢最早段，超限可见提示，绝不静默截断）。
    final normalized = <Map<String, Object?>>[
      for (var i = 0; i < segments.length; i++)
        <String, Object?>{
          'id': segments[i]['id'] is String &&
                  (segments[i]['id'] as String).isNotEmpty
              ? segments[i]['id']
              : 's$i',
          'pts': <Object?>[
            for (final p in asList(segments[i]['pts']))
              <String, Object?>{
                'x': clampNorm(_num(asMap(p)['x'])),
                'y': clampNorm(_num(asMap(p)['y'])),
              },
          ],
        },
    ];
    var total = 0;
    for (final s in normalized) {
      total += asList(s['pts']).length;
    }
    var kept = normalized;
    var dropped = false;
    while (total > kBoardMaxPoints && kept.isNotEmpty) {
      total -= asList(kept.first['pts']).length;
      kept = kept.sublist(1);
      dropped = true;
    }
    if (dropped) local.showNotice(kBoardLimitNotice);

    final payload = <Map<String, Object?>>[
      for (final s in kept)
        <String, Object?>{'id': s['id'], 'pts': s['pts']},
    ];
    _awaitingEcho = payload;
    scope.controller.sendIntent(
      RoomIntent.board,
      <String, Object?>{'strokes': payload},
    );
    setState(() {});
  }

  /// 静止点击不走 Pan，这里按当前工具补一次「点操作」：
  ///   · erase：快照段集 → 单点点擦（`split:false`：命中即整笔移除，P13 Q5
  ///     旧口径，已被既有断言锁定）→ 全量提交；
  ///   · draw：按落点新建一段（单点）→ 全量提交（对齐 KP 画笔单点圆点）。
  void _onTapUp(TapUpDetails d, Size size) {
    final scope = RoomScope.read(context);
    final at = stageNormOf(d.localPosition, size);
    final base = _visible(scope.session.state);
    if (scope.local.boardMode == BoardMode.erase) {
      _commit(eraseBoardSegments(base, <NormPoint>[at], split: false));
      return;
    }
    _commit(<Map<String, Object?>>[
      ...base,
      <String, Object?>{
        'id': 'p${DateTime.now().microsecondsSinceEpoch}',
        'pts': <Object?>[<String, Object?>{'x': at.x, 'y': at.y}],
      },
    ]);
  }

  void _onPanStart(DragStartDetails d, Size size) {
    final scope = RoomScope.read(context);
    final mode = scope.local.boardMode;
    final at = stageNormOf(d.localPosition, size);
    _dragging = true;
    _pendingPts.clear();
    _path.clear();
    _path.add(at);
    if (mode == BoardMode.draw) {
      // ★ 新段第一点就在落点起笔，绝不与上段末尾连线（SKETCH-1）。
      _pendingPts.add(at);
    } else {
      _snapshot = _visible(scope.session.state);
    }
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    if (!_dragging) return;
    final scope = RoomScope.read(context);
    final at = stageNormOf(d.localPosition, size);
    _path.add(at);
    if (scope.local.boardMode == BoardMode.draw) {
      _pendingPts.add(at);
    }
    setState(() {});
  }

  void _onPanEnd() {
    if (!_dragging) return;
    _dragging = false;
    final scope = RoomScope.read(context);
    if (scope.local.boardMode == BoardMode.erase) {
      final next = eraseBoardSegments(_snapshot, _path);
      _path.clear();
      _commit(next);
      return;
    }
    if (_pendingPts.isEmpty) {
      _path.clear();
      setState(() {});
      return;
    }
    final next = <Map<String, Object?>>[
      ..._visible(scope.session.state),
      <String, Object?>{
        'id': 'p${DateTime.now().microsecondsSinceEpoch}',
        'pts': <Object?>[
          for (final p in _pendingPts)
            <String, Object?>{'x': p.x, 'y': p.y},
        ],
      },
    ];
    _pendingPts.clear();
    _path.clear();
    _commit(next);
  }

  @override
  Widget build(BuildContext context) {
    final local = RoomScope.of(context).local;
    // ★ 本块读本地态（画笔 / 橡皮模式）→ **必须自己订阅** `local`。
    //   不能指望父级重建带下来：`const` 实例会被元素树按身份（`identical`）
    //   复用、连 `build` 都不调，订阅层一定要长在本块内。
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) => _panel(ctx),
    );
  }

  /// 面板本体：在 [ListenableBuilder] 内构建，`local` 变一次就重画一次。
  Widget _panel(BuildContext context) {
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final local = scope.local;
    final seat = scope.session.seat;
    // ★ 橡皮拖动期间把「已擦掉的中间结果」实时喂给 BoardPainter；
    //   ★ P14：画笔拖动期间把**正在建的那一段**（`_pendingPts`）作为临时段
    //   追加在末尾一起画 —— 否则 painter 只读已提交的 `base`，手指拖动时
    //   画布一动不动，必须抬手 `_commit` 后才出墨。松手后 `_pendingPts` 清空、
    //   该段由 `base` 接管（同一批点），视觉无跳变。
    final bool erasing =
        _dragging && local.boardMode == BoardMode.erase;
    final bool drawingLive = _dragging &&
        local.boardMode == BoardMode.draw &&
        _pendingPts.isNotEmpty;
    final base = _visible(state);
    final List<Map<String, Object?>> segments = <Map<String, Object?>>[
      for (final s in (erasing ? eraseBoardSegments(_snapshot, _path) : base))
        <String, Object?>{'id': s['id'], 'pts': asList(s['pts'])},
      if (drawingLive)
        <String, Object?>{
          'id': '__live__',
          'pts': <Object?>[
            for (final p in _pendingPts)
              <String, Object?>{'x': p.x, 'y': p.y},
          ],
        },
    ];
    final int totalPts = segments.fold<int>(
      0,
      (int n, Map<String, Object?> s) => n + asList(s['pts']).length,
    );
    final locked = selfLocked(state, seat);
    final theme = Theme.of(context);
    final me = findMe(state, seat);
    final stats = memberStats(me);

    // 画布本体。抽成局部变量只为让 fill / 非 fill 两条路径**共用同一棵子树**
    // —— key、手势回调、painter 不许出现第二份实现（否则「画不动 / 不自绘」）。
    final Widget canvas = LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return Container(
          decoration: BoxDecoration(
            // ★ P16 P-3：所有主题都用不透明白板（画布，不算栏位，
            //   与 C-1 半透明栏位不冲突）；笔迹默认纯黑见 stroke_painter。
            color: Colors.white,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: GestureDetector(
            key: GpPlSketchKeys.canvas,
            behavior: HitTestBehavior.opaque,
            // ★ 静止点击由 TapGestureRecognizer 赢，不触发任何 Pan 回调 ⇒
            //   `onTapUp` 同时承担点擦与「点按落一点」；拖动走 Pan 链路。
            onTapUp: locked ? null : (TapUpDetails d) => _onTapUp(d, size),
            onPanStart: locked ? null : (DragStartDetails d) => _onPanStart(d, size),
            onPanUpdate: locked ? null : (DragUpdateDetails d) => _onPanUpdate(d, size),
            onPanEnd: locked ? null : (DragEndDetails _) => _onPanEnd(),
            child: CustomPaint(
              // 分段笔迹（旧扁平点已由 boardSegmentsFromRaw 归一）。
              painter: BoardPainter(segments),
              size: Size.infinite,
            ),
          ),
        );
      },
    );

    return SectionBox(
      key: GpPlSketchKeys.root,
      title: '我的手绘板',
      // ★ P20 需求 3②：fill 时整块吃满父级高度（全屏路由用）。
      //   false（默认）⇒ `SectionBox` 仍是 MainAxisSize.min + 非 Expanded，
      //   KP 折叠档 / dock 格 / 既有几何断言零 diff。
      expand: widget.fill,
      trailing: locked
          ? null
          : ConfirmTwice(
              key: GpPlSketchKeys.clear,
              label: '清空',
              onConfirmed: () => _commit(const <Map<String, Object?>>[]),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('‹1/1›',
                  key: GpPlSketchKeys.page,
                  style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              if (!locked) ...<Widget>[
                RoomTap(
                  key: GpPlSketchKeys.draw,
                  icon: Icons.edit,
                  label: '笔',
                  hint: '画笔',
                  minSize: const Size(48, 32),
                  onTap: () => local.setBoardMode(BoardMode.draw),
                ),
                RoomTap(
                  key: GpPlSketchKeys.erase,
                  icon: Icons.auto_fix_normal,
                  label: '擦',
                  hint: '橡皮',
                  minSize: const Size(48, 32),
                  onTap: () => local.setBoardMode(BoardMode.erase),
                ),
              ],
              // ★ 单列档可用宽只有 ~316dp（360 竖屏），状态文案必须可收缩：
              //   `Spacer + Text` 在窄屏会溢出 86dp，改成「右侧自动占满 + 尾部省略」。
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  locked
                      ? '已撕卡：手绘板不可用'
                      : '${local.boardMode == BoardMode.erase ? '橡皮' : '画笔'}'
                          ' · $totalPts 点'
                          '${hasCardVitals(me) ? ' · HP ${stats.hp}/${stats.hpMax}' : ' · 未绑卡'}',
                  key: GpPlSketchKeys.locked,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: locked ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // ★ 旧路径（fill == false）逐字保留 `SizedBox(height: widget.height)`：
          //   `p10`/`p11` 的多条几何与手势用例靠它把画布钳成 180dp。
          widget.fill
              ? Expanded(child: canvas)
              : SizedBox(height: widget.height, child: canvas),
        ],
      ),
    );
  }
}

/// 手绘板内部稳定 key。
class GpPlSketchKeys {
  const GpPlSketchKeys._();

  static const Key root = ValueKey<String>('gpPlSketch/root');
  static const Key canvas = ValueKey<String>('gpPlSketch/canvas');
  static const Key draw = ValueKey<String>('gpPlSketch/draw');
  static const Key erase = ValueKey<String>('gpPlSketch/erase');
  static const Key clear = ValueKey<String>('gpPlSketch/clear');
  static const Key page = ValueKey<String>('gpPlSketch/page');
  static const Key locked = ValueKey<String>('gpPlSketch/locked');
}
