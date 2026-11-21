// ============================================================
// map_fullscreen_page.dart — 素材舞台「真全屏」独立路由（P12 / 第 9 期）
//
// KP-1c / PL-3c：不再用 `showRoomSheet` 半屏弹层，改成一条独立路由。
//   · 无 AppBar 的 `Scaffold` + `PopScope`：左上「退出全屏」+ 系统返回键；
//     点画布空白**不**退出（Q1）。
//   · KP：左侧工具窄栏（退出 / 放单位 / 画笔 / 橡皮 / 标点 / 清除标记 /
//     拖动素材 / 纯文字 `-` `+`），舞台 `readOnly:false`；
//   · 玩家：整条窄栏不渲染，舞台 `readOnly:true`，仅「退出 + 缩放」。
//   · 舞台 rect ≈ 视口（Expanded + Positioned.fill）；底图 / 笔迹 / 标点 /
//     落点手势四层共用同一条 Transform（由 GpMapStage 负责，R11）。
//   · 退出时 `resetMapView()`：全屏态 / offset / zoom / 工具态一次复位。
//   · 定宽按钮一律 `clampBtnText` 只包该按钮子树（textScaler 1.3/1.5/2.0）。
//
// ★ 本机态隔离：本页读写的全是 `RoomUiLocal`（纯本机），绝不进 `state` /
//   存档 JSON / 出站 `SendPlan`；拖动与缩放不同步给其他端。
// ★ `zoom`（页面整体 0.6–1.0）与 `mapZoom`（舞台 0.5–3.0）严格隔离，
//   本页只用 `mapZoom` / `setMapZoom`，绝不互相赋值。
// ★ 新 Key 一律独立 `ValueKey<String>`，不挂 `act/` 锚点（§7.1）。
// ============================================================

import 'package:flutter/material.dart';

import 'room_scope.dart';
import 'room_theme.dart' show RoomTheme;
import 'room_ui_local.dart' show RoomToolMode, RoomUiLocal;
import 'view/scene_view.dart' show NormPoint;
import 'widgets/gp_map_stage.dart'
    show GpMapStage, GpMapStageKeys, MapStageControl, stagePointJson;
import 'widgets/room_button_size.dart' show clampBtnText;
import 'widgets/room_panel_kit.dart' show RoomTap;

/// 全屏页稳定 Key（命名空间 `mapFullscreen/…`，§7.1）。
class MapFullscreenKeys {
  const MapFullscreenKeys._();

  static const Key root = ValueKey<String>('mapFullscreen/root');
  static const Key toolRail = ValueKey<String>('mapFullscreen/toolRail');
  static const Key exit = ValueKey<String>('mapFullscreen/exit');
  /// 2.37.0 / Q2：独立 ValueKey，绝不挂 `RoomKeys.action(...)`（避 T-30 污染）。
  static const Key eraser = ValueKey<String>('mapFullscreen/eraser');
  static const Key zoomIn = ValueKey<String>('mapFullscreen/zoomIn');
  static const Key zoomOut = ValueKey<String>('mapFullscreen/zoomOut');
}

/// 素材舞台真全屏页。由 `showMapStageFullscreen` 推入，并在新路由内
/// 重包一层 [RoomScope] 透传 session / local / controller。
class MapFullscreenPage extends StatefulWidget {
  const MapFullscreenPage({
    super.key,
    required this.stageControl,
    required this.isKp,
  });

  /// 与主页舞台**共用同一实例**（工具态 / 落点回调不串味）。
  final MapStageControl stageControl;

  /// `true` = KP（可标记 / 可拖动 + 左侧窄栏）；`false` = 玩家（只读）。
  final bool isKp;

  @override
  State<MapFullscreenPage> createState() => _MapFullscreenPageState();
}

class _MapFullscreenPageState extends State<MapFullscreenPage> {
  /// 「清除标记」二次确认的本机开关（不进 RoomUiLocal、不进 state）。
  bool _clearArmed = false;

  @override
  void initState() {
    super.initState();
    // 进全屏记本机态。延到首帧后写，避免 build 期间 `notifyListeners`
    // 触发 `ListenableBuilder` 重入（setState during build）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RoomScope.read(context).local.setMapFullscreen(true);
    });
  }

  /// 退出：一次复位全部舞台本机态（全屏 / offset / zoom / 工具态）再 pop。
  /// 三个入口（窄栏首项 / 左上按钮 / 系统返回键 / 舞台右下角）同口径。
  void _exit() {
    RoomScope.read(context).local.resetMapView();
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final RoomUiLocal local = RoomScope.of(context).local;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _exit();
      },
      child: Scaffold(
        key: MapFullscreenKeys.root,
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Row(
            children: <Widget>[
              // KP 才挂工具窄栏；玩家侧整条不渲染（PL-3c）。
              if (widget.isKp) _toolRail(local),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: GpMapStage(
                        controller: widget.stageControl,
                        readOnly: !widget.isKp,
                        // 右下角 zoomIn/zoomOut/reset 仍保留（四层同步）；
                        // fullscreenMode 结构性地隐藏嵌套的 fullscreen 键。
                        showControls: true,
                        fullscreenMode: true,
                        onPlaceActor: widget.isKp ? _placeActor : null,
                      ),
                    ),
                    // 玩家侧：左上角唯一的「退出全屏」；KP 侧由窄栏首项提供。
                    // 两侧互斥 → `MapFullscreenKeys.exit` 在同一棵树里恰好一个。
                    if (!widget.isKp)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _toolButton(
                          key: MapFullscreenKeys.exit,
                          icon: Icons.close_fullscreen,
                          label: '退出全屏',
                          onTap: _exit,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// KP 左侧工具窄栏（Q2 口径：不含「放玩家」「全屏」）。
  ///
  /// 用 [ListenableBuilder] 只订阅 `local`：拖动按钮的激活态由只读 getter
  /// `local.panArmed` 派生，切到其它工具时自动熄灭，不另存第二份状态。
  Widget _toolRail(RoomUiLocal local) {
    return Container(
      key: MapFullscreenKeys.toolRail,
      width: 104,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: local,
          builder: (BuildContext ctx, Widget? _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _toolButton(
                key: MapFullscreenKeys.exit,
                icon: Icons.close_fullscreen,
                label: '退出全屏',
                onTap: _exit,
              ),
              _toolButton(
                icon: Icons.person_add,
                label: '放单位',
                onTap: () {
                  // 与 `gp_kp_tools.addLocalActor` 同口径：固定取本机候选池
                  // 的第一个名字，空池回落「单位」；不读写权威 state。
                  final pool = local.pendingActors;
                  final raw = pool.isEmpty ? null : pool.first['name'];
                  final name = (raw == null || raw.toString().trim().isEmpty)
                      ? '单位'
                      : raw.toString();
                  widget.stageControl.beginPlace(actorName: name);
                },
              ),
              _toolButton(
                icon: Icons.brush,
                label: '画笔',
                onTap: () => widget.stageControl.beginStroke(
                  color: RoomTheme.drawColor(local.toolColorIndex),
                  width: 3,
                ),
              ),
              // 2.37.0 / Q2：全屏窄栏补「橡皮」。与主页 `gp_kp_tools` 的
              // 橡皮共用同一个 stageControl；擦除提交仍由 GpMapStage 的
              // `_onPanEnd` 走 `map.strokes.set`，不另造 op / 不碰 POLICY。
              _toolButton(
                key: MapFullscreenKeys.eraser,
                icon: Icons.backspace,
                label: '橡皮',
                onTap: () => widget.stageControl.beginErase(),
              ),
              _toolButton(
                icon: Icons.place,
                label: '标点',
                onTap: () => widget.stageControl.beginMark(
                  kind: 'dot',
                  label: '',
                ),
              ),
              // KP-2c：清 scene.strokes + scene.marks，不动 scene.assets；
              // 二次确认，口径与工具窄栏的「清除标记」一致。
              _toolButton(
                icon: Icons.delete_sweep,
                label: _clearArmed ? '再点一次清除' : '清除标记',
                selected: _clearArmed,
                onTap: _clearMarks,
              ),
              // ★ 主口径：`setTool(RoomToolMode.pan)`。严禁写
              //   `local.panArmed = true`（只读 getter，编译失败）。
              _toolButton(
                key: GpMapStageKeys.panTool,
                icon: Icons.open_with,
                label: '拖动素材',
                selected: local.panArmed,
                onTap: () => local.setTool(
                  local.panArmed ? RoomToolMode.none : RoomToolMode.pan,
                ),
              ),
              // 2.37.0 / Q2：RoomTap 会把 icon 与 label 并排渲染，用户看到
              // 「两个符号」。缩放按钮只留一个文字字符，icon 传 null，
              // RoomTap 的 icon 本就可空；其余按钮口径不变。
              _toolButton(
                key: MapFullscreenKeys.zoomOut,
                icon: null,
                label: '-',
                onTap: () => local.setMapZoom(local.mapZoom / 1.25),
              ),
              _toolButton(
                key: MapFullscreenKeys.zoomIn,
                icon: null,
                label: '+',
                onTap: () => local.setMapZoom(local.mapZoom * 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「清除标记」二次确认：第一下只点亮，第二下才真正下发。
  void _clearMarks() {
    if (!_clearArmed) {
      setState(() => _clearArmed = true);
      return;
    }
    setState(() => _clearArmed = false);
    RoomScope.read(context).controller.hostAction(
          'map.clear',
          <String, Object?>{'strokesOnly': false},
        );
  }

  /// 全屏页内「放单位」的落点：`map.mark`，与主页 `_placeMark` 同口径
  /// （`kind='actor'` + `label=actorName` + 归一化 `{x,y}`）。
  /// 不新建 domain op、不改 domain。
  void _placeActor(String actorName, NormPoint at) {
    final scope = RoomScope.read(context);
    if (!scope.controller.gate.can('map.mark')) return;
    scope.controller.hostAction('map.mark', <String, Object?>{
      ...stagePointJson(at),
      'kind': 'actor',
      'label': actorName,
      'revealed': true,
    });
  }

  /// 定宽按钮：`clampBtnText` 只包这一棵子树，不抬到页面 / Theme 层。
  Widget _toolButton({
    Key? key,
    IconData? icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: clampBtnText(
          RoomTap(
            key: key,
            icon: icon,
            label: label,
            hint: label,
            minSize: const Size(88, 40),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
