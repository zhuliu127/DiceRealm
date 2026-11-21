// ============================================================
// app.dart — 应用外壳：MaterialApp + 路由
//
// 路由三条：首页 `/`、新建流程 `/create`、角色卡详情 `/card/<id>`。
// 仓库不在全局单例里，而是通过 RepoScope（见 repo/repo_scope.dart）向下传。
// ============================================================

import 'package:flutter/material.dart';

import 'repo/character_repo.dart';
import 'repo/repo_scope.dart';
import 'repo/settings_repo.dart';
import 'repo/share_store.dart';
import 'theme.dart';
import 'ui/card_detail_page.dart';
import 'ui/create/create_flow_page.dart';
import 'ui/home_page.dart';
import 'ui/ai_create_page.dart';
import 'ui/random_create_page.dart' show RandomCreatePage;
import 'ui/roster_page.dart' show RosterPage;
import 'ui/room/room_entry_page.dart' show RoomEntryPage;
import 'ui/settings_page.dart';

class DiceRealmApp extends StatefulWidget {
  const DiceRealmApp({
    super.key,
    required this.repo,
    required this.settings,
    required this.share,
    this.home,
  });

  final CharacterRepo repo;
  final SettingsRepo settings;
  final ShareService share;

  /// 测试注入用：替换首页（其余路由不变）
  final Widget? home;

  @override
  State<DiceRealmApp> createState() => _DiceRealmAppState();
}

class _DiceRealmAppState extends State<DiceRealmApp> {
  late bool _dark;

  @override
  void initState() {
    super.initState();
    _dark = widget.settings.isDarkTheme;
    widget.settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// 只对「皮肤」变化重建。
  ///
  /// 为什么不能直接 `AnimatedBuilder(animation: settings)`：`SettingsRepo` 是
  /// 全局 ChangeNotifier，设置页每敲一个字符都会通知一次 —— 那样会让整个
  /// `MaterialApp`（含路由栈）每帧重建，输入框会明显卡顿。这里比对上一帧的
  /// 皮肤值，只有真的切换了才 `setState`。
  void _onSettingsChanged() {
    final bool dark = widget.settings.isDarkTheme;
    if (dark != _dark && mounted) {
      setState(() => _dark = dark);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ★ 必须先设 Palette 再建 ThemeData：否则这一帧会「新皮肤 + 旧色板」。
    Palette.useBrightness(_dark ? Brightness.dark : Brightness.light);

    return RepoScope(
      repo: widget.repo,
      child: SettingsScope(
        repo: widget.settings,
        child: ShareScope(
          service: widget.share,
          child: MaterialApp(
            title: '骰境TRPG',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            onGenerateRoute: _onGenerateRoute,
          ),
        ),
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? AppRoutes.home;

    if (name == AppRoutes.create) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const CreateFlowPage(),
      );
    }
    if (name == AppRoutes.ai) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const AiCreatePage(),
      );
    }
    // ★ P8：AI 车卡 与 一键出卡 拆成两页（前者只有 AI，后者只有随机 5 张）。
    //   路由常量定义在页面里（`repo_scope.dart` 不属于本批改动范围）。
    if (name == RandomCreatePage.route) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const RandomCreatePage(),
      );
    }
    if (name == RosterPage.route) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>  RosterPage(),
      );
    }
    if (name == AppRoutes.settings) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const SettingsPage(),
      );
    }
    if (name.startsWith('/card/')) {
      final id = name.substring('/card/'.length);
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => CardDetailPage(cardId: id),
      );
    }
    if (name == AppRoutes.room) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const RoomEntryPage(),
      );
    }
    if (name.startsWith('${AppRoutes.room}/')) {
      final code = name.substring(AppRoutes.room.length + 1);
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => RoomEntryPage(initialCode: code),
      );
    }
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => AppBackground(child: widget.home ?? const HomePage()),
    );
  }
}
