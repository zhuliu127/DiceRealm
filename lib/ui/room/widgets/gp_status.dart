// ============================================================
// widgets/gp_status.dart — 块 12(KP) / 13(PL)：状态条
//
// KP 侧（块 12）：**恒空**是合法状态 —— 没有待办时只显示「暂无待办」；
//   有待确认动作（`hostRead.pending`）或状态变更请求（`hostRead.requestsBySeat`）
//   时逐条列出，同意 / 拒绝两条路径都只发 `INTENT.CONFIRM` / `INTENT.CONSENT`。
// PL 侧（块 13）：「需我同意」的请求卡 + 对抗待办 + 选伤害目标的入口占位。
//
// ★ 只读权威面：KP 走 `hostRead`（不在 state 里找 pending / requests，T7），
//   玩家走自己那份裁剪后的 state（`requests` 键可能为空，缺键 ≠ 有 0 条待办）。
// ★ 请求卡的按钮**不是** POLICY action，所以不用 `RoomKeys.action(op)`，
//   避免被 T-30 表驱动探针误判成「可点性漂移」。
// ============================================================

import 'package:flutter/material.dart';

import '../../art.dart';
import '../../../theme.dart' show Palette;

import '../../../domain/js_compat.dart' show asList, asMap;
import '../../../domain/room_types.dart' show RoomIntent, RoomRole;
import '../room_controller.dart';
import '../room_scope.dart';
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 状态条内部稳定 key。
class GpStatusKeys {
  const GpStatusKeys._();

  static const Key root = ValueKey<String>('gpStatus/root');
  static const Key empty = ValueKey<String>('gpStatus/empty');
  static const Key pending = ValueKey<String>('gpStatus/pending');

  /// 某条请求卡（`gpStatus/req/<id>`）。
  static Key request(String id) => ValueKey<String>('gpStatus/req/$id');

  /// 同意 / 拒绝按钮（`gpStatus/agree/<id>` / `gpStatus/reject/<id>`）。
  static Key agree(String id) => ValueKey<String>('gpStatus/agree/$id');
  static Key reject(String id) => ValueKey<String>('gpStatus/reject/$id');
}

/// 一条「需某人同意」的请求卡（供状态条与战斗列表共用）。
class RoomRequestCard extends StatelessWidget {
  const RoomRequestCard({
    super.key,
    required this.id,
    required this.title,
    required this.text,
    required this.onReply,
  });

  final String id;
  final String title;
  final String text;

  /// `agree=true` → 同意；`false` → 拒绝。
  final void Function(bool agree) onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
        // 状态条底纹（E7）：只做质感，不改变布局、语义与 Key
        image: DecorationImage(
          image: AssetImage(Art.statusBar),
          fit: BoxFit.cover,
          opacity: Palette.isDark ? 0.40 : 0.22,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: theme.textTheme.bodySmall),
          if (text.isNotEmpty)
            Text(text, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              RoomTap(
                key: GpStatusKeys.agree(id),
                label: '同意',
                icon: Icons.check,
                minSize: const Size(56, 36),
                hint: '同意这条请求',
                onTap: () => onReply(true),
              ),
              // ★ P16：两个已等宽的按钮之间补 6dp —— 改前 0 间距，视觉上
              //   像「一个被从中间劈开的按钮」。尺寸一个字节不动（56×36）。
              const SizedBox(width: 6),
              RoomTap(
                key: GpStatusKeys.reject(id),
                label: '拒绝',
                icon: Icons.close,
                minSize: const Size(56, 36),
                hint: '拒绝这条请求',
                onTap: () => onReply(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 状态条。
class GpStatus extends StatelessWidget {
  const GpStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final role = scope.session.role;
    final isKp = role == RoomRole.kp;
    final read = scope.session.hostRead;
    final state = scope.session.state;

    final cards = <Widget>[];
    if (isKp && read != null) {
      // ① 待确认的高危动作（KP 自己发起的不入队，故这里恒为「别人提交的」）。
      for (final q in read.pending) {
        final op = roomText(q['op']);
        final by = roomText(q['by']);
        // `state.request` 也会在 pending 里留一条**记账**，但它的确认方是玩家
        // （走 CONSENT），不是 KP（走 CONFIRM）—— 这里跳过，避免点错链路。
        // 以前这里还要挡 `op == 'null'`：那是 jsStr(null) 的产物。
        // 现在 op 走 roomText（null → 空串），只判空即可。
        if (op.isEmpty) continue;
        final id = 'pending:$op:$by';
        cards.add(RoomRequestCard(
          key: GpStatusKeys.request(id),
          id: id,
          title: '待确认：$op',
          text: '来自 $by',
          onReply: (bool agree) => _confirm(scope.controller, op, by, agree),
        ));
      }
      // ② 玩家提交的状态变更请求（逐 seat 汇总）。
      for (final entry in read.requestsBySeat.entries) {
        for (final r in entry.value) {
          final id = roomText(r['id']);
          if (id.isEmpty) continue;
          cards.add(RoomRequestCard(
            key: GpStatusKeys.request(id),
            id: id,
            title: '状态变更请求',
            text: '${entry.key}：${roomText(r['op'])}',
            onReply: (bool agree) => _consent(scope.controller, id, agree),
          ));
        }
      }
    } else {
      // 玩家 / 旁观：只读自己那份裁剪态里的请求（缺键 → 空，不当 0 条待办）。
      for (final raw in asList(state['requests'])) {
        final r = asMap(raw);
        final id = roomText(r['id']);
        if (id.isEmpty) continue;
        cards.add(RoomRequestCard(
          key: GpStatusKeys.request(id),
          id: id,
          title: '需我同意',
          text: roomText(r['op']),
          onReply: (bool agree) => _consent(scope.controller, id, agree),
        ));
      }
    }

    final title = isKp ? '待办' : '需我同意';

    return SectionBox(
      key: GpStatusKeys.root,
      title: title,
      trailing: _pendingBadge(context, isKp),
      child: cards.isEmpty
          ? Text(
              isKp ? '暂无待办' : '没有需要你同意的请求',
              key: GpStatusKeys.empty,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: cards,
            ),
    );
  }

  /// KP 侧的「待办角标」（S4.2 的完整计数公式在 T04 落地，这里只给条数）。
  Widget? _pendingBadge(BuildContext context, bool isKp) {
    if (!isKp) return null;
    final read = RoomScope.read(context).session.hostRead;
    if (read == null) return null;
    final n = read.pending.length +
        read.requestsBySeat.values.fold<int>(0, (int a, List<Map<String, Object?>> b) => a + b.length);
    if (n <= 0) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text('$n', key: GpStatusKeys.pending),
    );
  }

  /// 确认一条待办：`INTENT.CONFIRM{p.op, p.by, p.agree}`。
  void _confirm(RoomController controller, String op, String by, bool agree) {
    controller.sendIntent(
      RoomIntent.confirm,
      <String, Object?>{'op': op, 'by': by, 'agree': agree},
    );
  }

  /// 回应一条「需我同意」：`INTENT.CONSENT{p.id, p.agree}`。
  void _consent(RoomController controller, String id, bool agree) {
    controller.sendIntent(
      RoomIntent.consent,
      <String, Object?>{'id': id, 'agree': agree},
    );
  }
}
