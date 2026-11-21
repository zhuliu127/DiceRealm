// ============================================================
// room_scope.dart — 向下传「三件套」的 InheritedNotifier（设计 §1.4）
//
// 照抄项目既有范式（`repo_scope.dart` 的 RepoScope / SettingsScope）：
//   · `of(context)` 订阅 session 变化（在 build 里用）；
//   · `read(context)` 只取实例不订阅（在回调 / initState 里用）。
//
// ★ 两层 Listenable 分开订阅：session 变化频繁（每条事件），local 变化
//   稀疏（点 tab / 折叠）。每块写法统一为
//   `RoomScope.of(ctx)` → `ListenableBuilder(listenable: sc.local, ...)`。
// ============================================================

import 'package:flutter/widgets.dart';

import 'room_controller.dart';
import 'room_session.dart';
import 'room_ui_local.dart';

/// 房间页作用域。`notifier` 就是 [RoomSession]（ChangeNotifier），
/// 所以 `dependOnInheritedWidgetOfExactType` 会同时订阅它的通知。
class RoomScope extends InheritedNotifier<RoomSession> {
  const RoomScope({
    super.key,
    required RoomSession session,
    required this.local,
    required this.controller,
    required super.child,
  }) : super(notifier: session);

  final RoomUiLocal local;
  final RoomController controller;

  /// 有类型的别名（`InheritedNotifier.notifier` 是可空泛型）。
  RoomSession get session => notifier!;

  /// 取作用域并订阅 session 变更（在 build 里用）。
  static RoomScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RoomScope>();
    assert(scope != null, 'RoomScope 未挂载：请把房间页放在 RoomScope 子树内');
    return scope!;
  }

  /// 只取作用域、不订阅（在回调 / initState 里用）。
  static RoomScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<RoomScope>();
    assert(scope != null, 'RoomScope 未挂载：请把房间页放在 RoomScope 子树内');
    return scope!;
  }

  /// 便捷：直接拿控制器（等价于 `of(context).controller`）。
  static RoomController controllerOf(BuildContext context) =>
      of(context).controller;
}
