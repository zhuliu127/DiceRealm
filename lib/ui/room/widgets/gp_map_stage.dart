// ============================================================
// widgets/gp_map_stage.dart — 块 4(KP) / 3(PL)：公开素材舞台
//
// 两件事：
//   ① 画：16:9 舞台 + 已公开素材底 + 笔迹/标点两层画布 + 平移缩放 ± ；
//   ② 收点：落点回调（工具态决定这一下是「标点」「放怪」「放玩家」还是「画笔」）。
//
// ★ 实现设计 §3.9 的 `MapStageController` 六个成员（签名一字不改）：
//   块 3（KP 工具窄栏，T04）只通过这个接口操作舞台 —— 块 3 与块 4 是两个
//   独立子树，共享 Controller 是唯一不破「独立子树」的做法。
//
// ★ K5 / T-13：坐标一律**归一化到 [0,1]** 再出门（`stageNormOf` 是纯函数，
//   纯 Dart 就能钉死），缩放只在绘制层发生，绝不参与坐标换算 ——
//   Transform 会把指针位置自动变换回未缩放本地系。
//
// ★ 只画、只发动作：本文件零权威端引用、零规则调用。
// ============================================================

import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';

import '../../../domain/room_types.dart' show RoomRole;
import '../painter/stroke_painter.dart';
import '../room_scope.dart';
import '../room_theme.dart';
import '../sheets/room_sheet.dart';
import '../view/scene_view.dart';
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 舞台当前工具态（由 `MapStageController` 的四个 begin* 设置）。
enum MapStageMode { none, stroke, erase, mark, placeActor, placePlayer }

/// 像素 → 归一化坐标（纯函数，T-13 的落点）。
///
/// `x = clamp(local.dx / w)`、`y = clamp(local.dy / h)`；零尺寸时返回 (0,0) 而不是 NaN。
NormPoint stageNormOf(Offset local, Size size) {
  final w = size.width <= 0 ? 1.0 : size.width;
  final h = size.height <= 0 ? 1.0 : size.height;
  return NormPoint(clampNorm(local.dx / w), clampNorm(local.dy / h));
}

/// 归一化坐标 → JSON 点（`{x, y}`，权威端 `mapStroke` 认这个形状）。
Map<String, Object?> stagePointJson(NormPoint p) => <String, Object?>{
      'x': clampNorm(p.x),
      'y': clampNorm(p.y),
    };

/// 素材舞台的控制面：实现 §3.9 的六个成员 + 舞台自己要读的工具态。
class MapStageControl extends ChangeNotifier implements MapStageController {
  MapStageMode mode = MapStageMode.none;

  /// 画笔颜色（hex）与线宽（权威端会夹 1–24）。
  String strokeColor = RoomTheme.drawColor(0);
  double strokeWidth = 3;

  /// 标点三要素。
  String markKind = 'dot';
  String markLabel = '';
  bool markRevealed = true;

  /// 放置目标（T04 的「放怪 / 放玩家」）。
  String? actorName;
  String? playerSeat;

  @override
  void beginStroke({required String color, required double width}) {
    mode = MapStageMode.stroke;
    strokeColor = color;
    strokeWidth = width;
    notifyListeners();
  }

  @override
  void beginErase() {
    mode = MapStageMode.erase;
    notifyListeners();
  }

  @override
  void beginMark({
    required String kind,
    required String label,
    bool revealed = true,
  }) {
    mode = MapStageMode.mark;
    markKind = kind;
    markLabel = label;
    markRevealed = revealed;
    notifyListeners();
  }

  @override
  void beginPlace({String? actorName, String? playerSeat}) {
    this.actorName = actorName;
    this.playerSeat = playerSeat;
    mode = actorName != null ? MapStageMode.placeActor : MapStageMode.placePlayer;
    notifyListeners();
  }

  @override
  void cancel() {
    if (mode == MapStageMode.none && actorName == null && playerSeat == null) {
      return;
    }
    mode = MapStageMode.none;
    actorName = null;
    playerSeat = null;
    notifyListeners();
  }

  /// 是否在「等一次点击」（十字光标用）。
  @override
  bool get awaitingTap =>
      mode == MapStageMode.mark ||
      mode == MapStageMode.placeActor ||
      mode == MapStageMode.placePlayer;
}

/// 舞台内部的稳定 key。
class GpMapStageKeys {
  const GpMapStageKeys._();

  static const Key stage = ValueKey<String>('gpMapStage/stage');
  static const Key canvas = ValueKey<String>('gpMapStage/canvas');
  static const Key empty = ValueKey<String>('gpMapStage/empty');
  static const Key zoomIn = ValueKey<String>('gpMapStage/zoomIn');
  static const Key zoomOut = ValueKey<String>('gpMapStage/zoomOut');
  static const Key reset = ValueKey<String>('gpMapStage/reset');
  static const Key fullscreen = ValueKey<String>('gpMapStage/fullscreen');

  // ★ P12 / §7.1：本期新增稳定 Key（全部独立 `ValueKey<String>`，不挂
  //   `act/` 锚点）。既有 7 个常量一个都没删（R9：删符号 = 编译期假红）。
  static const Key exitFullscreen = ValueKey<String>('gpMapStage/exitFullscreen');
  static const Key panTool = ValueKey<String>('gpMapStage/panTool');
  static const Key coverLayer = ValueKey<String>('gpMapStage/coverLayer');
}

// ------------------------------------------------------------
// ★ P17 C-4：无公开素材 → 舞台改「白板」
//
// 白板是**硬白**（`Colors.white`，不跟主题、不半透明）：亮/暗主题都白，
// 且不能用 `withValues(alpha:)`（半透明会露出游戏页背景图，P16 C-1 已踩过）。
//
// 白板上的一切文字必须深色 —— 不能再用 `theme.textTheme.bodySmall`
// （暗色主题那是近白色 → 白底白字）。三个常量就是白板上的取色口径，
// 波4 可直接按名字断言。
// ------------------------------------------------------------

/// 白板（无公开素材）底色：硬白，亮暗主题一致。
const Color stageBoardColor = Colors.white;

/// 白板上的主提示文字色（对白对比度 15.9:1）。
const Color stageBoardInk = Color(0xff222222);

/// 白板上的次要文字色（计数/注意提示，对白对比度 6.7:1，过 AA）。
const Color stageBoardInkSoft = Color(0xff5c5c5c);

/// 画布底色（外层铺满格子的收边色）：白板硬白，有素材时跟主题。
Color stageBackdropColor(
  Map<String, Object?>? cover,
  ColorScheme scheme,
) =>
    cover == null ? stageBoardColor : scheme.surfaceContainerHighest;

/// 舞台画布本身（内层 Container）的底色：
/// 白板硬白；有素材时必须透明（否则把底图整块盖住，P10 第 7 期真 bug）。
Color stageCanvasColor(
  Map<String, Object?>? cover,
  ColorScheme scheme,
) =>
    cover == null ? stageBoardColor : Colors.transparent;

/// 舞台上的辅助文字色：白板深色，否则回落到主题默认（传 null 表示不覆盖）。
Color? stageInkColor(Map<String, Object?>? cover, {bool soft = false}) =>
    cover == null ? (soft ? stageBoardInkSoft : stageBoardInk) : null;


/// 块 4 / 3：公开素材舞台。
class GpMapStage extends StatefulWidget {
  const GpMapStage({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.onPlaceActor,
    this.onPlacePlayer,
    this.showControls = true,
    this.fullscreenMode = false,
  });

  /// §3.9 契约的实现（块 3 也持有同一个实例）。
  final MapStageControl controller;

  /// 全屏只读 / 玩家侧：禁画笔、禁标点、禁放置（只看）。
  final bool readOnly;

  /// 放置回调用（真正的结算在 T04 的战斗动作里，舞台只交出归一化坐标）。
  final void Function(String actorName, NormPoint at)? onPlaceActor;
  final void Function(String playerSeat, NormPoint at)? onPlacePlayer;

  /// 是否显示右下角缩放按钮（全屏弹层里也显示）。
  final bool showControls;

  /// ★ P12 KP-1b/PL-3b：是否处于「素材舞台真全屏」独立路由。
  /// 全屏态**结构性地不渲染** [GpMapStageKeys.fullscreen] 入口，
  /// 避免「全屏里还有全屏按钮」的嵌套；默认 false → 既有调用点零影响。
  /// `panMode` 刻意不做第二个参数：拖动激活态由本机态 `local.panArmed`
  /// 单一真源派生，不另存一份工具态。
  final bool fullscreenMode;

  @override
  State<GpMapStage> createState() => _GpMapStageState();
}

class _GpMapStageState extends State<GpMapStage> {
  final List<NormPoint> _draft = <NormPoint>[];
  bool _dragging = false;

  /// ★ P12 KP-1c/KP-2b：舞台缩放上提到 `RoomUiLocal.mapZoom`（本机态），
  ///   主页与真全屏共享同一份；夹 [0.5,3.0] 由 `setMapZoom` 负责，
  ///   这里不再留第二份 `_zoom` 私有状态（绝不复用页面整体 `zoom`）。
  void _setZoom(double v) {
    RoomScope.read(context).local.setMapZoom(v);
  }

  /// KP-2b：最小可见比例钳制（只在渲染侧做，本类是唯一拿得到 [size] 的地方）。
  /// 至少保留 20% 的舞台在视口内；缩放越大可平移范围越宽。
  Offset _clampPan(Offset next, Size size, double zoom) {
    final dx = size.width * 0.8 * zoom;
    final dy = size.height * 0.8 * zoom;
    return Offset(
      next.dx.clamp(-dx, dx).toDouble(),
      next.dy.clamp(-dy, dy).toDouble(),
    );
  }

  void _onTap(TapUpDetails d, Size size) {
    if (widget.readOnly) return;
    final c = widget.controller;
    if (!c.awaitingTap) return;
    final at = stageNormOf(d.localPosition, size);
    final scope = RoomScope.read(context);
    switch (c.mode) {
      case MapStageMode.mark:
        scope.controller.hostAction('map.mark', <String, Object?>{
          ...stagePointJson(at),
          'kind': c.markKind,
          'label': c.markLabel,
          'revealed': c.markRevealed,
        });
        break;
      case MapStageMode.placeActor:
        widget.onPlaceActor?.call(c.actorName ?? '', at);
        break;
      case MapStageMode.placePlayer:
        widget.onPlacePlayer?.call(c.playerSeat ?? '', at);
        break;
      default:
        return;
    }
    c.cancel(); // 单次工具态：落一次就复位
  }

  void _onPanStart(DragStartDetails d, Size size) {
    if (widget.readOnly) return;
    final m = widget.controller.mode;
    if (m != MapStageMode.stroke && m != MapStageMode.erase) return;
    _dragging = true;
    _draft
      ..clear()
      ..add(stageNormOf(d.localPosition, size));
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    final local = RoomScope.read(context).local;
    // ★ P12 KP-2b：拖动素材只更新**本机**平移量。绝不下发
    //   hostAction / SendPlan / RoomEvt，state / 存档 / 出站计划零变化；
    //   不同步给玩家侧。钳制在本渲染侧完成（拿得到舞台 size）再写入。
    if (local.panArmed && !widget.readOnly) {
      local.setMapPanOffset(
        _clampPan(local.mapPanOffset + d.delta, size, local.mapZoom),
      );
      return;
    }
    if (!_dragging) return;
    _draft.add(stageNormOf(d.localPosition, size));
    setState(() {});
  }

  void _onPanEnd() {
    if (!_dragging) return;
    _dragging = false;
    final points = List<NormPoint>.of(_draft);
    _draft.clear();
    setState(() {});
    if (points.isEmpty) return;

    final scope = RoomScope.read(context);
    final m = widget.controller.mode;
    if (m == MapStageMode.stroke) {
      scope.controller.hostAction('map.stroke', <String, Object?>{
        'color': widget.controller.strokeColor,
        'width': widget.controller.strokeWidth,
        'pts': <Object?>[for (final p in points) stagePointJson(p)],
      });
      return;
    }
    if (m == MapStageMode.erase) {
      // 段级擦除：本地算好「擦完的整份笔迹」，手势末尾**一次**全量下发。
      final next = eraseStrokeSegments(
        strokesOf(scope.session.state),
        points,
      );
      scope.controller.hostAction('map.strokes.set', <String, Object?>{
        'strokes': <Object?>[for (final st in next) st],
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final local = scope.local;
    final state = scope.session.state;
    final strokes = strokesOf(state);
    final marks = marksOf(state);
    final assets = publicAssets(state);
    final theme = Theme.of(context);
    final isKp = scope.session.role == RoomRole.kp;

    return ListenableBuilder(
      // ★ 两层合订阅：controller（工具态） + local（mapZoom / mapPanOffset /
      //   mapFullscreen / panArmed）。舞台上的缩放与拖动都要局部重建，
      //   但绝不合成 session 通知（那是每条事件级别的重算）。
      listenable: Listenable.merge(<Listenable>[widget.controller, local]),
      builder: (BuildContext ctx, Widget? child) {
        final double mapZoom = local.mapZoom;
        final Offset mapPanOffset = local.mapPanOffset;
        final awaiting = widget.controller.awaitingTap && !widget.readOnly;
        // ★ 2.36.0 / Q1：底图不再只取 `assets.last`。
        //   `revealAsset` 互斥公开时通常只有一张，但旧存档 / 多入口公开可能
        //   留下多张 revealed；只要列表末位的 `data` 为空或非法，改前的
        //   `_coverImage` 就会把**整层**底图静默降级成空白 —— 这正是
        //   「全屏舞台只有白板和标记」的根因（全屏页与主页共用本组件，
        //   KP 侧全屏 Stack 没有额外不透明覆盖层，`RoomScope` 也透传同一个
        //   session 实例、数据是活的，故不是「被盖」或「快照没接上」）。
        //   改为：把**所有**能解码出图片的已公开素材按列表序叠放，并用
        //   「是否存在有效图片」驱动 hasCover 取色口径。
        final List<Uint8List> coverImages = <Uint8List>[];
        Map<String, Object?>? cover;
        for (final Map<String, Object?> a in assets) {
          final Uint8List? bytes = _coverBytes(a);
          if (bytes == null) continue;
          coverImages.add(bytes);
          cover ??= a; // 代表素材：只用于 hasCover 判定 / 取色，不参与绘制
        }
        // ★ P17 C-4：白板上文字必须深色；有素材时不覆盖（保持主题默认渲染）。
        final Color? ink = stageInkColor(cover);
        final Color? inkSoft = stageInkColor(cover, soft: true);
        // ★ 2.36.0 / Q3：把拖动中的 `_draft` 组成一条临时笔迹追加进绘制
        //   列表（新 List 实例 → StrokesPainter.shouldRepaint 恒为真），让画笔
        //   随手指实时出墨；橡皮模式不画临时笔迹（那是擦除路径，不是落墨）。
        //   `_draft` 已是归一化点，复用 stagePointJson；绝不乘 mapZoom
        //   （Transform 自动把指针逆变换回未缩放本地系）。
        final bool draftingStroke =
            _draft.isNotEmpty && widget.controller.mode == MapStageMode.stroke;
        final List<Map<String, Object?>> paintedStrokes = draftingStroke
            ? <Map<String, Object?>>[
                ...strokes,
                <String, Object?>{
                  'color': widget.controller.strokeColor,
                  'width': widget.controller.strokeWidth,
                  'pts': <Object?>[
                    for (final NormPoint p in _draft) stagePointJson(p),
                  ],
                },
              ]
            : strokes;
        // ★ P10 第 7 期（用户原话「中间一大片空白」「保证严格 16:9」）：
        //   外层 ColoredBox **填满整个格子**（同底色收边，不再出现「舞台
        //   周围一圈空白」），内层 Center + AspectRatio 保证舞台严格 16:9。
        //   GpMapStageKeys.stage 仍挂在 16:9 节点上，几何断言继续可测。
        return ColoredBox(
          // ★ P17 C-4：无公开素材（cover == null）→ 硬白板，否则保持主题底色。
          color: stageBackdropColor(cover, theme.colorScheme),
          child: Center(
            child: AspectRatio(
          key: GpMapStageKeys.stage,
          aspectRatio: RoomTheme.mapAspect,
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints c) {
              final size = Size(c.maxWidth, c.maxHeight);
              return ClipRect(
                child: Stack(
                  children: <Widget>[
                    // ★ P12 KP-1a/PL-3a（R11）：底图 + 笔迹/标点层 + 落点
                    //   手势层共用**同一条** Transform 链（平移 + 缩放），
                    //   是内层 Stack 的兄弟：底图在下、手势层在上。
                    //   禁止给底图单独套第二个 Transform（二次变换 → 落点漂移）。
                    //   Transform 自动逆变换指针坐标，stageNormOf /
                    //   stagePointJson 归一化口径逐字不动。
                    Positioned.fill(
                      child: Transform.translate(
                        offset: mapPanOffset,
                        child: Transform.scale(
                          scale: mapZoom,
                          alignment: Alignment.center,
                          child: Stack(
                            children: <Widget>[
                              // ★ 2.36.0 / Q1：全部已公开图片素材在最底层
                              //   （BoxFit.contain 不裁切不变形）；这一层始终
                              //   排在下面的 手势 → CustomPaint(笔迹/标点)
                              //   之前，保证「图片在底、标记与笔迹在上」。
                              if (coverImages.isNotEmpty)
                                _coverLayer(coverImages),
                              Positioned.fill(
                                child: GestureDetector(
                                  key: GpMapStageKeys.canvas,
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (TapUpDetails d) => _onTap(d, size),
                                  onPanStart: (DragStartDetails d) =>
                                      _onPanStart(d, size),
                                  onPanUpdate: (DragUpdateDetails d) =>
                                      _onPanUpdate(d, size),
                                  onPanEnd: (DragEndDetails _) => _onPanEnd(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      // ★ P10 第 7 期修复（真 bug）：这一层 Container 画在
                                      //   底图 **上面**，原来固定用不透明
                                      //   surfaceContainerHighest 铺满整格，会把下面刚画好的
                                      //   公开素材底图整块盖住 —— 结果就是「素材图根本没渲染」
                                      //   （组件在树里、肉眼一片纯色）。有底图时改成透明，
                                      //   只保留描边与圆角；没有底图时仍用同底色兜底。
                                      // ★ P17 C-4：没有底图时不再是主题底色，而是**硬白板**
                                      //   （`Colors.white`，亮/暗主题都白）。
                                      color: stageCanvasColor(cover, theme.colorScheme),
                                      border: Border.all(color: theme.dividerColor),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Stack(
                                      children: <Widget>[
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: StrokesPainter(paintedStrokes),
                                            // ★ P17 C-2：标签色按**画布类型**取，不跟主题
                                            //   （白板 + 暗色主题用 onSurface 会白底白字）。
                                            foregroundPainter: MarksPainter(
                                              marks,
                                              labelColor:
                                                  stageMarkLabelColor(cover != null),
                                              labelHalo:
                                                  stageMarkLabelHalo(cover != null),
                                            ),
                                          ),
                                        ),
                                        if (assets.isEmpty &&
                                            strokes.isEmpty &&
                                            marks.isEmpty)
                                          Center(
                                            child: Text(
                                              widget.readOnly
                                                  ? '暂无可查看的素材'
                                                  : '暂无公开素材 · 点左栏「上传素材」',
                                              key: GpMapStageKeys.empty,
                                              textAlign: TextAlign.center,
                                              // ★ P17 C-4：此分支必然是无素材白板 →
                                              //   文字必须深色（主题 bodySmall 在暗色主题是白字）。
                                              style: (theme.textTheme.bodySmall ??
                                                      const TextStyle(fontSize: 12))
                                                  .copyWith(color: stageBoardInk),
                                            ),
                                          ),
                                        if (awaiting)
                                          Positioned(
                                            left: 6,
                                            top: 6,
                                            child: Text(
                                              '点击落点…',
                                              // ★ P17 C-4：白板上深色；有素材时保持主题默认。
                                              style: ink == null
                                                  ? null
                                                  : TextStyle(color: ink),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (widget.showControls)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Row(
                          children: <Widget>[
                            RoomTap(
                              key: GpMapStageKeys.zoomOut,
                              icon: Icons.remove,
                              hint: '缩小舞台',
                              minSize: const Size(36, 32),
                              onTap: () => _setZoom(mapZoom / 1.25),
                            ),
                            RoomTap(
                              key: GpMapStageKeys.reset,
                              icon: Icons.center_focus_strong,
                              hint: '复位舞台缩放',
                              minSize: const Size(36, 32),
                              onTap: () {
                                _setZoom(1.0);
                                // 复位同时清掉本机平移量（四层同步回原点）。
                                RoomScope.read(context)
                                    .local
                                    .setMapPanOffset(Offset.zero);
                              },
                            ),
                            RoomTap(
                              key: GpMapStageKeys.zoomIn,
                              icon: Icons.add,
                              hint: '放大舞台',
                              minSize: const Size(36, 32),
                              onTap: () => _setZoom(mapZoom * 1.25),
                            ),
                            // ★ P12 KP-1b/PL-3b：全屏态结构性地不渲染这个
                            //   入口（嵌套入口数 = 0），常量本身保留（R9）。
                            if (!widget.fullscreenMode)
                              RoomTap(
                                key: GpMapStageKeys.fullscreen,
                                icon: Icons.fullscreen,
                                hint: '全屏查看素材',
                                minSize: const Size(36, 32),
                                onTap: () => _openFullscreen(context),
                              ),
                            // 全屏态用「退出全屏」替代上面那个入口；与左上角的
                            // MapFullscreenKeys.exit、系统返回键同口径。
                            if (widget.fullscreenMode)
                              RoomTap(
                                key: GpMapStageKeys.exitFullscreen,
                                icon: Icons.close_fullscreen,
                                hint: '退出全屏',
                                minSize: const Size(36, 32),
                                onTap: () => _exitFullscreen(context),
                              ),
                          ],
                        ),
                      ),
                    // KP 的素材数（T04 的素材库会做增删；这里只给只读计数）
                    if (isKp)
                      Positioned(
                        left: 6,
                        bottom: 4,
                        child: Text(
                          '素材 ${assets.length} · 笔迹 ${strokes.length} · 标点 ${marks.length}',
                          // ★ P17 C-4：白板上次要文字用深灰（对白 6.7:1）；
                          //   有素材时保持主题默认（原渲染不变）。
                          style: theme.textTheme.bodySmall?.copyWith(
                                color: inkSoft,
                              ) ??
                              TextStyle(color: inkSoft),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
            ),
          ),
        );
      },
    );
  }

  /// 素材 dataURL → 可渲染字节；空数据 / 非法 base64 静默跳过
  /// （绝不因为一张坏图炸掉整个舞台）。
  Uint8List? _coverBytes(Map<String, Object?> a) {
    final String raw = roomText(a['data']);
    if (raw.isEmpty) return null;
    try {
      final int comma = raw.indexOf(',');
      final String b64 = comma >= 0 ? raw.substring(comma + 1) : raw;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// 已公开图片素材底图层：全部 revealed 素材按列表序叠放，仍是 inner
  /// Stack 的**第一个** child（在手势 / 笔迹 / 标点层之下）。
  ///
  /// ★ 单张时结构与 P12 逐字一致（`Positioned.fill → Image.memory`），
  ///   `GpMapStageKeys.coverLayer` 在整棵树里恰好一个 ⇒ 既有
  ///   `findsOneWidget` 与「底图 / 笔迹层 rect 同量变化」几何断言零漂移。
  /// ★ 多张时才叠一层 Stack 容器，key 仍只挂在外层 `Positioned.fill` 上，
  ///   所以四复用点（主页 / 全屏 / 玩家 / 战斗态）共用同一套图层顺序。
  Widget _coverLayer(List<Uint8List> images) {
    if (images.isEmpty) return const SizedBox.shrink();
    Widget imageOf(Uint8List bytes) => Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (BuildContext _, Object? _, StackTrace? _) =>
              const SizedBox.shrink(),
        );
    return Positioned.fill(
      // ★ P12 KP-1a/PL-3a：底图层的稳定定位点（四层 rect 同量变化断言用）。
      key: GpMapStageKeys.coverLayer,
      child: images.length == 1
          ? imageOf(images.first)
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                for (final Uint8List bytes in images)
                  Positioned.fill(child: imageOf(bytes)),
              ],
            ),
    );
  }

  void _openFullscreen(BuildContext context) {
    final scope = RoomScope.read(context);
    // ★ P12 KP-1c/PL-3c：改走独立路由的真全屏页（不再是半屏 bottomSheet）。
    //   KP 非只读（可在全屏里标记 / 拖动），玩家只读；去掉现状硬编码的
    //   `readOnly: true`（这是 KP 全屏不能标记的隐藏 bug）。`RoomScope`
    //   由 showMapStageFullscreen 在新路由内重包一层透传。
    showMapStageFullscreen<void>(
      context: context,
      stageControl: widget.controller,
      isKp: scope.session.role == RoomRole.kp,
    );
  }

  /// 全屏态右下角的退出入口：与全屏页左上角按钮 / 系统返回键同口径，
  /// 都是「先复位全部舞台本机态，再 pop 回原路由」。
  void _exitFullscreen(BuildContext context) {
    RoomScope.read(context).local.resetMapView();
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }
}

/// 便于测试与 T04 复用的工具态摘要（不参与渲染）。
String stageModeName(MapStageMode m) => roomText(m.name);
