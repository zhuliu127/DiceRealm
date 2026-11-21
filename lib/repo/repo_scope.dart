// ============================================================
// repo_scope.dart — 仓库作用域 + 路由名常量
//
// 单独一个文件，避免「页面 import app、app import 页面」的环。
// 用 InheritedNotifier 而不是全局单例：仓库变更时，依赖它的页面自动重建；
// 测试里换一个临时目录的仓库也只是换一个参数。
// ============================================================

import 'package:flutter/widgets.dart';

import 'character_repo.dart';
import 'settings_repo.dart';
import 'share_store.dart';

class RepoScope extends InheritedNotifier<CharacterRepo> {
  const RepoScope({
    super.key,
    required CharacterRepo repo,
    required super.child,
  }) : super(notifier: repo);

  /// 取仓库并订阅变更（在 build 里用）
  static CharacterRepo of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepoScope>();
    assert(scope != null, 'RepoScope 未挂载：请把页面放在 DiceRealmApp 子树内');
    return scope!.notifier!;
  }

  /// 只取实例、不订阅（在回调 / initState 里用）
  static CharacterRepo read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<RepoScope>();
    assert(scope != null, 'RepoScope 未挂载');
    return scope!.notifier!;
  }
}

/// 设置作用域（与 [RepoScope] 同一套路，只是换一个仓库）
///
/// 为什么不用全局单例：设置页与首页都要读它，而测试里换一个内存后端
/// 只需要换一个参数 —— 全局单例就得在 tearDown 里手工复位，很容易串味。
class SettingsScope extends InheritedNotifier<SettingsRepo> {
  const SettingsScope({
    super.key,
    required SettingsRepo repo,
    required super.child,
  }) : super(notifier: repo);

  /// 取仓库并订阅变更（在 build 里用）
  static SettingsRepo of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope 未挂载：请把页面放在 DiceRealmApp 子树内');
    return scope!.notifier!;
  }

  /// 只取实例、不订阅（在 initState / didChangeDependencies 里用）
  static SettingsRepo read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope 未挂载');
    return scope!.notifier!;
  }
}

/// 云分享作用域
///
/// 用普通 [InheritedWidget] 而不是 InheritedNotifier：要传的是
/// [ShareService]（它本身不是 Listenable），变更由它内部的
/// `store`（ChangeNotifier）通知，UI 侧用 AnimatedBuilder 订阅即可。
class ShareScope extends InheritedWidget {
  const ShareScope({super.key, required this.service, required super.child});

  final ShareService service;

  static ShareService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShareScope>();
    assert(scope != null, 'ShareScope 未挂载：请把页面放在 DiceRealmApp 子树内');
    return scope!.service;
  }

  /// 只取实例、不订阅（在 initState / 回调里用）
  static ShareService read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ShareScope>();
    assert(scope != null, 'ShareScope 未挂载');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(ShareScope oldWidget) => oldWidget.service != service;
}

/// 路由名常量（避免各处写魔法字符串）
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String create = '/create';
  static const String settings = '/settings';
  static const String ai = '/ai';
  static String card(String id) => '/card/$id';

  /// 骰境TRPG 房间入口页（创建 / 加入 / 续玩）。
  static const String room = '/room';

  /// 带房间号的入口页（深链：`/room/K3M9QZ` 进页面时预填房间号）。
  ///
  /// ★ 前缀必须是 [room] + `/`，路由表据此区分「入口页」与「带号入口页」。
  static String roomCode(String code) => '$room/$code';
}
