// ============================================================
// sheets/room_sheet.dart — 弹层统一入口（设计 §2.7）
//
// ★ 只画、只发 intent：零权威端引用、零权威状态赋值。
// ★ 可刷新 body：`ValueNotifier` 负责全局刷新（refreshTopSheet），
//   `StatefulBuilder` 负责弹层内的局部重建，两者都不碰权威 state。
// ============================================================

import 'package:flutter/material.dart';

import '../map_fullscreen_page.dart' show MapFullscreenPage;
import '../room_scope.dart';
import '../widgets/gp_map_stage.dart' show MapStageControl;
import '../widgets/room_panel_kit.dart';

/// 顶层弹层刷新信号。权威端状态变化后调用 [refreshTopSheet]，
/// 当前打开的弹层 body 会整体重建（旧版 kpPanel 的定时刷新同语义）。
final ValueNotifier<int> _topSheetTick = ValueNotifier<int>(0);

/// 刷新当前顶层弹层。没有打开的弹层时是安全的空操作。
void refreshTopSheet() {
  _topSheetTick.value += 1;
}

/// 房间侧所有弹层的统一入口。
///
/// [body] 每次刷新都会重新构建，因此不要在 body 内持有可变草稿
/// （草稿应放 `RoomUiLocal`，或由调用方自己用 StatefulWidget 保存）。
///
/// ★ **作用域必须由这里补**：`showModalBottomSheet` 把弹层挂在 Navigator 的
///   浮层上，而 `RoomScope` 在**页面路由内部** —— 弹层与页面是兄弟路由，
///   弹层里 `RoomScope.of(ctx)` 会命中断言。所以在打开时抓一份 scope，
///   在弹层 body 外原样重新提供（同 session/local/controller，不产生第二个写口）。
///   调用方在 scope 之外打开弹层（纯弹层单测）时 `scope == null`，行为不变。
Future<T?> showRoomSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder body,
  List<Widget> actions = const <Widget>[],
  bool isScrollControlled = true,
}) {
  // 只取不订阅：弹层自己会通过重新提供的 RoomScope 订阅会话。
  final RoomScope? scope = context.getInheritedWidgetOfExactType<RoomScope>();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => ValueListenableBuilder<int>(
      valueListenable: _topSheetTick,
      builder: (listenedContext, _, _) => StatefulBuilder(
        builder: (buildContext, setSheetState) => RoomSheet(
          title: title,
          actions: <Widget>[
            ...actions,
            RoomTap(
              icon: Icons.refresh,
              hint: '刷新当前弹层',
              onTap: () {
                setSheetState(() {});
                refreshTopSheet();
              },
            ),
          ],
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(buildContext).size.height * 0.72,
            ),
            child: SingleChildScrollView(
              child: scope == null
                  ? body(buildContext)
                  : RoomScope(
                      session: scope.session,
                      local: scope.local,
                      controller: scope.controller,
                      child: body(buildContext),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 全屏只读阅读器（私密栏 / 聊天 / 规则参考的 ⛶ 全屏）。
class FullscreenReader extends StatelessWidget {
  const FullscreenReader({
    super.key,
    required this.title,
    this.text = '',
    this.child,
  });

  final String title;
  final String text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          RoomTap(
            icon: Icons.close,
            hint: '关闭',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: child ??
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
      ),
    );
  }
}

/// 推一个全屏只读页。
Future<T?> showFullscreenReader<T>({
  required BuildContext context,
  required String title,
  String text = '',
  Widget? child,
}) {
  final RoomScope? scope = context.getInheritedWidgetOfExactType<RoomScope>();
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (_) {
        final page = FullscreenReader(title: title, text: text, child: child);
        if (scope == null) return page;
        return RoomScope(
          session: scope.session,
          local: scope.local,
          controller: scope.controller,
          child: page,
        );
      },
    ),
  );
}

/// 推一个「素材舞台真全屏」独立路由（P12 KP-1c / PL-3c）。
///
/// ★ 与 [showFullscreenReader] **同一套 `RoomScope` 透传范式**：新路由是
///   页面级路由，原 `RoomScope` 挂在旧路由内；必须在 builder 里重包一层，
///   否则全屏页里 `RoomScope.of(ctx)` 会命中断言。禁止裸 `Navigator.push`。
/// ★ 全局壳（`showRoomSheet:51-61` 默认刷新按钮 / [refreshTopSheet]）
///   与 [showFullscreenReader] 逐字不动 —— 本函数只新增，不改既有 18+ 调用点。
/// ★ [stageControl] 与主页舞台共用同一实例，工具态 / 落点回调不串味。
Future<T?> showMapStageFullscreen<T>({
  required BuildContext context,
  required MapStageControl stageControl,
  required bool isKp,
}) {
  final RoomScope? scope = context.getInheritedWidgetOfExactType<RoomScope>();
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (_) {
        final page = MapFullscreenPage(
          stageControl: stageControl,
          isKp: isKp,
        );
        if (scope == null) return page;
        return RoomScope(
          session: scope.session,
          local: scope.local,
          controller: scope.controller,
          child: page,
        );
      },
    ),
  );
}
