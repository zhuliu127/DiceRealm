// ============================================================
// view/scene_view.dart — 场景 / 素材 / 笔迹只读派生与纯函数（设计 §3.0 / §3.6）
//
// ★ 纯 Dart：零 UI 框架、零平台依赖。归一化坐标自己造值对象，
//   widget / painter 层才把它们换成 Offset / Color。
// ★ K5：笔迹一律用归一化 [0,1] 存；像素换算只在 UI 边界做，
//   缩放不参与换算（Transform.scale 会自动把 localPosition 变回本地系）。
// ============================================================

import 'dart:math' as math;

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_state.dart'
    show roomClone, roomNumber;
import '../room_text.dart';

/// 归一化坐标点（[0,1]）。
class NormPoint {
  const NormPoint(this.x, this.y);

  final double x, y;
}

/// 像素包围盒（widget 层把 RenderBox 的宽高传进来做换算）。
class NormBox {
  const NormBox(this.l, this.t, this.r, this.b);

  final double l, t, r, b;

  double get width => r - l;
  double get height => b - t;
}

/// 颜色在 view/ 里只是数据；painter 用 `Color(rgb.argb)` 转真颜色。
class RgbColor {
  const RgbColor(this.argb);

  final int argb;

  int get red => (argb >> 16) & 0xff;
  int get green => (argb >> 8) & 0xff;
  int get blue => argb & 0xff;
  int get alpha => (argb >> 24) & 0xff;
}

/// 把 [0,1] 之外的值夹回来（笔迹来自网络，可能是脏数据）。
double clampNorm(double v) {
  if (v.isNaN) return 0;
  if (v < 0) return 0;
  if (v > 1) return 1;
  return v;
}

/// 像素 → 归一化：`norm = (local - box.topLeft) / box.size`。
List<NormPoint> normalizePath(List<NormPoint> pts, NormBox box) {
  final w = box.width == 0 ? 1.0 : box.width;
  final h = box.height == 0 ? 1.0 : box.height;
  return <NormPoint>[
    for (final p in pts)
      NormPoint(
        clampNorm((p.x - box.l) / w),
        clampNorm((p.y - box.t) / h),
      ),
  ];
}

/// 归一化 → 像素：`px = norm * box.size`（painter 落笔前调用）。
List<NormPoint> denormalizePath(List<NormPoint> pts, NormBox box) => <NormPoint>[
      for (final p in pts)
        NormPoint(box.l + clampNorm(p.x) * box.width,
            box.t + clampNorm(p.y) * box.height),
    ];

/// 场景的只读深拷贝；无场景返回 null。
Map<String, Object?>? sceneOf(Map<String, Object?> state) {
  final sc = state['scene'];
  return sc is Map ? asMap(roomClone(sc)) : null;
}

List<Map<String, Object?>> _listOf(Object? raw) => <Map<String, Object?>>[
      for (final x in asList(roomClone(raw))) asMap(x),
    ];

/// 素材列表；[kind] 非空时按 `asset.kind` 过滤。
List<Map<String, Object?>> assetsOf(Map<String, Object?> state, {String? kind}) {
  final sc = sceneOf(state);
  if (sc == null) return <Map<String, Object?>>[];
  final rows = _listOf(sc['assets']);
  if (kind == null || kind.isEmpty) return rows;
  return rows.where((a) => roomText(a['kind']) == kind).toList();
}

/// 已公开素材（`revealed == true`）。
List<Map<String, Object?>> publicAssets(Map<String, Object?> state) =>
    assetsOf(state).where((a) => jsTruthy(a['revealed'])).toList();

List<Map<String, Object?>> marksOf(Map<String, Object?> state) {
  final sc = sceneOf(state);
  return sc == null ? <Map<String, Object?>>[] : _listOf(sc['marks']);
}

List<Map<String, Object?>> strokesOf(Map<String, Object?> state) {
  final sc = sceneOf(state);
  return sc == null ? <Map<String, Object?>>[] : _listOf(sc['strokes']);
}

/// `scene.boards[seat].count`（队友手绘板缩略按笔数显示，S8）。
int boardCountOf(Map<String, Object?> state, String seat) {
  final sc = sceneOf(state);
  if (sc == null) return 0;
  final boards = asMap(sc['boards']);
  return roomNumber(asMap(boards[seat])['count'], 0).toInt();
}

/// 本人手绘板笔迹：`state.board.strokes`（已按座位裁剪）。
List<Map<String, Object?>> myBoardStrokes(Map<String, Object?> state) =>
    _listOf(asMap(state['board'])['strokes']);

Map<String, Object?>? sceneCheckOf(Map<String, Object?> state) {
  final sc = state['sceneCheck'];
  return sc is Map ? asMap(roomClone(sc)) : null;
}

List<Map<String, Object?>> sceneCheckSteps(Map<String, Object?> state) {
  final sc = sceneCheckOf(state);
  return sc == null ? <Map<String, Object?>>[] : _listOf(sc['steps']);
}

int sceneCheckCursor(Map<String, Object?> state) =>
    roomNumber(sceneCheckOf(state)?['cursor'], 0).toInt();

/// 场景检定进度（0–1），无步骤时返回 0。
double sceneCheckProgress(Map<String, Object?> state) {
  final steps = sceneCheckSteps(state);
  if (steps.isEmpty) return 0;
  final cur = sceneCheckCursor(state);
  final v = cur / steps.length;
  return clampNorm(v);
}

/// 从一条笔迹里取出归一化点列（painter 与命中判定共用）。
List<NormPoint> strokePointsOf(Map<String, Object?> stroke) => <NormPoint>[
      for (final pRaw in asList(stroke['pts']))
        NormPoint(
          clampNorm(roomNumber(asMap(pRaw)['x'], 0).toDouble()),
          clampNorm(roomNumber(asMap(pRaw)['y'], 0).toDouble()),
        ),
    ];

double _dist(NormPoint a, NormPoint b) =>
    math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// 点到线段的最短距离（段长为 0 时退化成点距）。
double _distToSegment(NormPoint p, NormPoint a, NormPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return _dist(p, a);
  final t = clampNorm(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2);
  return _dist(p, NormPoint(a.x + t * dx, a.y + t * dy));
}

bool _nearPath(NormPoint p, List<NormPoint> path, double tol) {
  if (path.isEmpty) return false;
  for (final q in path) {
    if (_dist(p, q) <= tol) return true;
  }
  for (var i = 1; i < path.length; i++) {
    if (_distToSegment(p, path[i - 1], path[i]) <= tol) return true;
  }
  return false;
}

bool _strokeHit(Map<String, Object?> stroke, NormPoint at, double tol) {
  final pts = strokePointsOf(stroke);
  if (pts.isEmpty) return false;
  for (final p in pts) {
    if (_dist(p, at) <= tol) return true;
  }
  for (var i = 1; i < pts.length; i++) {
    if (_distToSegment(at, pts[i - 1], pts[i]) <= tol) return true;
  }
  return false;
}

/// 命中哪条笔迹（从最上层往下找）；未命中返回 -1。
/// 纯函数 → 橡皮擦的命中判定可以在纯 Dart 测试里钉死，不必 pump 画布。
int hitStrokeIndex(
  List<Map<String, Object?>> strokes,
  NormPoint at, {
  double tol = 0.02,
}) {
  for (var i = strokes.length - 1; i >= 0; i--) {
    if (_strokeHit(strokes[i], at, tol)) return i;
  }
  return -1;
}

/// 段级擦除：把被 [path] 命中的点切掉，剩余连续段各自成为一条新笔迹。
/// 返回**新的** List<Map>，绝不修改入参；空笔迹直接丢弃。
List<Map<String, Object?>> eraseStrokeSegments(
  List<Map<String, Object?>> strokes,
  List<NormPoint> path, {
  double tol = 0.02,
}) {
  final out = <Map<String, Object?>>[];
  if (path.isEmpty) {
    for (final st in strokes) {
      out.add(asMap(roomClone(st)));
    }
    return out;
  }

  for (final st in strokes) {
    final runs = <List<Object?>>[];
    var current = <Object?>[];
    for (final p in strokePointsOf(st)) {
      if (_nearPath(p, path, tol)) {
        if (current.isNotEmpty) {
          runs.add(current);
          current = <Object?>[];
        }
      } else {
        current.add(<String, Object?>{'x': clampNorm(p.x), 'y': clampNorm(p.y)});
      }
    }
    if (current.isNotEmpty) runs.add(current);

    final base = asMap(roomClone(st));
    final id = roomText(base['id']);
    for (var k = 0; k < runs.length; k++) {
      if (runs[k].isEmpty) continue;
      final next = <String, Object?>{...base};
      next['pts'] = runs[k];
      next['id'] = k == 0 ? id : (id.isEmpty ? 's$k' : '$id#$k');
      out.add(next);
    }
  }
  return out;
}

/// hex → RgbColor（与 `RoomTheme.colorArgb` 同口径，但保持 view/ 零外部依赖）。
RgbColor rgbOfHex(String hex) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'ff$s';
  if (s.length != 8) return const RgbColor(0xffe74c3c);
  return RgbColor(int.tryParse(s, radix: 16) ?? 0xffe74c3c);
}
