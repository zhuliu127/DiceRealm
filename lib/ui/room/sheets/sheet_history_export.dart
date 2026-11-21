// ============================================================
// sheets/sheet_history_export.dart — P2-06「导出文本」弹层（PRD :764）
//
// 旧版 `room-ui.js:535 exportArchiveText` 调 UI.saveFile 下载一份 .txt，
// 成功后弹 toast。本工程按 K7 不造假入口：即使系统分享 / 剪贴板通道在
// 自动化环境里不返回，用户也必须真的拿到文本 —— 所以底线是
//   「完整文本用 SelectableText 上屏 + 可长按全选复制」
// 再叠加「复制」「系统分享」两个真动作。
//
// ★ 平台动作做成可注入 port：测试注入同步替身计数；生产用系统实现。
//   port 的方法是同步返回 void，widget 里**零 await** —— 可见反馈先
//   同步 setState 上屏，再触发平台动作，反馈绝不依赖副作用完成。
// ★ 零 Timer / 零延迟 / 零动画控制器；不读网络、不写房间状态、不发意图。
// ★ 权限：入口由调用方用 gate.can(op) 结构性控制；弹层自身二次防御，
//   无权时只给一句如实说明，不渲染文本、不渲染两个动作。
// ============================================================

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';

import '../room_history_export.dart'
    show buildRoomHistoryExportText, kRoomHistoryChatLimit, kRoomHistoryFeedLimit;
import '../room_scope.dart' show RoomScope;
import '../widgets/room_panel_kit.dart' show RoomTap;
import 'room_sheet.dart' show showRoomSheet;

/// 导出入口沿用的 POLICY action。
///
/// 导出是「公开信息流的本机只读副本」，不是新的权威动作，因此**不新增
/// POLICY op、不加白名单、不另写一套权限判断**：直接复用 chat
/// （POLICY = [kp, player]，恰好把旁观者排除）。可点性与既有 T-30 同源。
const String kRoomHistoryExportPolicyOp = 'chat';

/// 平台动作端口。测试注入同步替身；生产用 [SystemRoomHistoryExportPort]。
///
/// 方法刻意同步返回 void：widget 不需要等平台通道，也就不会在测试环境里
/// 挂住；「导出成功」的可见反馈由 widget 自己在上屏前给出。
abstract class RoomHistoryExportPort {
  const RoomHistoryExportPort();

  /// 把完整文本放进系统剪贴板。
  void copy(String text);

  /// 调起系统分享面板发送完整文本。
  void share(String text);
}

/// 生产实现：剪贴板 + 系统分享。
///
/// 两个平台调用都被包成「发起即返回」，异常只吞进空 catch：平台不可用时
/// 弹层里的完整文本仍然可见、仍可长按全选复制 —— 不会因此变成「点了没
/// 反应」或「假成功」。异常不往上抛，也不改任何可见反馈。
class SystemRoomHistoryExportPort implements RoomHistoryExportPort {
  const SystemRoomHistoryExportPort();

  @override
  void copy(String text) => unawaited(_copy(text));

  @override
  void share(String text) => unawaited(_share(text));

  static Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // 剪贴板不可用时：文本仍完整可见，可长按全选复制。
    }
  }

  static Future<void> _share(String text) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: '跑团游戏历史记录'),
      );
    } catch (_) {
      // 系统分享面板不可用时：同上，文本仍完整可见。
    }
  }
}

/// 导出弹层内部稳定 key。
class RoomHistoryExportKeys {
  const RoomHistoryExportKeys._();

  static const Key root = ValueKey<String>('historyExport/root');
  static const Key intro = ValueKey<String>('historyExport/intro');
  static const Key count = ValueKey<String>('historyExport/count');
  static const Key text = ValueKey<String>('historyExport/text');
  static const Key copy = ValueKey<String>('historyExport/copy');
  static const Key share = ValueKey<String>('historyExport/share');
  static const Key feedback = ValueKey<String>('historyExport/feedback');
  static const Key denied = ValueKey<String>('historyExport/denied');
}

/// 打开「游戏历史记录 · 导出文本」弹层。所有房间内弹层统一走 [showRoomSheet]。
///
/// [port] / [nowMs] 是测试注入点：生产分别回落到系统实现与系统时钟。
/// 文本生成只依赖「当前会话视角的 state」，不写 state、不发 intent、不联网。
Future<void> openRoomHistoryExportSheet(
  BuildContext context, {
  RoomHistoryExportPort? port,
  int Function()? nowMs,
}) {
  final scope = RoomScope.read(context);
  final session = scope.session;
  final clock = nowMs ?? _systemNowMs;
  final text = buildRoomHistoryExportText(
    session.state,
    seat: session.seat,
    role: session.role,
    exportedAtMs: clock(),
    feedLimit: kRoomHistoryFeedLimit,
    chatLimit: kRoomHistoryChatLimit,
  );
  return showRoomSheet<void>(
    context: context,
    title: '游戏历史记录 · 导出文本',
    body: (BuildContext _) => RoomHistoryExportSheet(
      text: text,
      port: port ?? const SystemRoomHistoryExportPort(),
      canExport: scope.controller.gate.can(kRoomHistoryExportPolicyOp),
    ),
  );
}

int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

/// 弹层主体：完整文本 + 两个真动作 + 同步可见反馈。
class RoomHistoryExportSheet extends StatefulWidget {
  const RoomHistoryExportSheet({
    super.key,
    required this.text,
    required this.port,
    this.canExport = true,
  });

  /// 由纯函数生成的**完整**文本。
  final String text;

  /// 平台动作端口（生产 = 系统实现，测试 = 同步替身）。
  final RoomHistoryExportPort port;

  /// 权限二次防御：false 时只给如实说明，不渲染文本与动作。
  final bool canExport;

  @override
  State<RoomHistoryExportSheet> createState() =>
      _RoomHistoryExportSheetState();
}

class _RoomHistoryExportSheetState extends State<RoomHistoryExportSheet> {
  String _feedback = '';

  /// ★ 先 setState 给可见反馈，再触发平台动作（零 await）。
  /// 文案同时守住 K7 底线：平台动作不返回，用户仍可长按全选复制。
  void _copy() {
    setState(() {
      _feedback = '复制已触发：完整文本已送入系统剪贴板；'
          '若设备不支持，请长按上方文本全选复制。';
    });
    widget.port.copy(widget.text);
  }

  void _share() {
    setState(() {
      _feedback = '系统分享已触发；若面板未出现，请长按上方文本全选复制。';
    });
    widget.port.share(widget.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodySmall;
    final dim = body?.copyWith(color: theme.colorScheme.secondary);

    if (!widget.canExport) {
      return Column(
        key: RoomHistoryExportKeys.root,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '当前视角没有导出游戏历史的权限，因此这里不显示记录文本，'
            '也不提供复制 / 分享。',
            key: RoomHistoryExportKeys.denied,
            style: body,
          ),
        ],
      );
    }

    final lineCount = '\n'.allMatches(widget.text).length + 1;
    return Column(
      key: RoomHistoryExportKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '下面是本视角可见的公开记录与聊天生成的完整文本，可长按全选复制，'
          '也可以用下面两个按钮交给系统处理。私密笔记、暗骰结果与其它座位的'
          '私有字段都不在其中。',
          key: RoomHistoryExportKeys.intro,
          style: body,
        ),
        const SizedBox(height: 8),
        Text(
          '共 ${widget.text.runes.length} 字 · $lineCount 行',
          key: RoomHistoryExportKeys.count,
          style: dim,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          // ★ K7 底线：完整文本真的上屏，且可全选复制。不是「已导出」假提示。
          child: SelectableText(
            widget.text,
            key: RoomHistoryExportKeys.text,
            style: body,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            RoomTap(
              key: RoomHistoryExportKeys.copy,
              icon: Icons.copy_all_outlined,
              label: '复制全文',
              hint: '把完整文本放进系统剪贴板',
              minSize: const Size(120, 40),
              onTap: _copy,
            ),
            RoomTap(
              key: RoomHistoryExportKeys.share,
              icon: Icons.ios_share,
              label: '系统分享',
              hint: '调起系统分享面板发送完整文本',
              minSize: const Size(120, 40),
              onTap: _share,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _feedback.isEmpty ? '尚未执行导出动作；文本已完整显示，可直接复制。'
              : _feedback,
          key: RoomHistoryExportKeys.feedback,
          style: dim,
        ),
      ],
    );
  }
}
