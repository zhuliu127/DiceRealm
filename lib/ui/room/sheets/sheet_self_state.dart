// ============================================================
// sheets/sheet_self_state.dart — 状态管理弹层（玩家自助）
//
// Q-P5-3 的**唯一文案口径**（不要沿用旧版「不需要 KP 同意」）：
//   · HP / MP / SAN 等**数字** → `state.edit.self` → POLICY 里 confirm = kp
//     ⇒ 文案必须是「**需 KP 同意**」，提交后进 KP 的待确认队列；
//   · 身体状态 / 精神状态 → `state.self` → confirm = null
//     ⇒ 文案必须是「**立即生效**」，直接改自己的状态。
//
// ★ 只发动作：本文件零权威端引用、零规则调用；弹层作用域由 `showRoomSheet`
//   自动补（不需要自己再包 RoomScope）。
// ★ 数字输入只做「整数 + 非负」的本地清洗，真正的夹取（0–9999、不超过上限）
//   在权威端 `stateSelf` 里做 —— 客户端不复制这套规则。
// ============================================================

import 'package:flutter/material.dart';

import '../room_scope.dart';
import '../view/member_view.dart' show memberStats;
import '../view/room_view.dart' show findMe;
import '../view/sheet_view.dart' show mentalText;
import '../widgets/room_panel_kit.dart' show RoomTap;
import 'room_sheet.dart';

/// 状态管理弹层内部稳定 key。
class GpSelfStateKeys {
  const GpSelfStateKeys._();

  static const Key root = ValueKey<String>('gpSelfState/root');
  static const Key hp = ValueKey<String>('gpSelfState/hp');
  static const Key mp = ValueKey<String>('gpSelfState/mp');
  static const Key san = ValueKey<String>('gpSelfState/san');
  static const Key submitNumbers = ValueKey<String>('gpSelfState/submitNumbers');
  static const Key noticeNumbers = ValueKey<String>('gpSelfState/noticeNumbers');
  static const Key noticeBody = ValueKey<String>('gpSelfState/noticeBody');
  static const Key noticeMental = ValueKey<String>('gpSelfState/noticeMental');

  /// 身体状态 chip（`gpSelfState/body/<值>`）。
  static Key body(String v) => ValueKey<String>('gpSelfState/body/$v');

  /// 精神状态 chip（`gpSelfState/mental/<值>`）。
  static Key mental(String v) => ValueKey<String>('gpSelfState/mental/$v');
}

/// 身体状态可选值（与 `kRaBodyOk` 同集合）。
const List<String> kSelfBodyValues = <String>['正常', '轻伤', '重伤'];

/// 精神状态可选值（与 `kRaMentalOk` 同集合）。
const List<String> kSelfMentalValues = <String>['正常', '临时疯狂', '不定疯狂'];

/// 打开状态管理弹层。
Future<void> openSelfStateSheet(BuildContext context) => showRoomSheet<void>(
      context: context,
      title: '状态管理',
      body: (BuildContext _) => const GpSelfStateBody(),
    );

/// 弹层主体（数值需 KP 同意 / 身体·精神立即生效）。
class GpSelfStateBody extends StatefulWidget {
  const GpSelfStateBody({super.key});

  @override
  State<GpSelfStateBody> createState() => _GpSelfStateBodyState();
}

class _GpSelfStateBodyState extends State<GpSelfStateBody> {
  late final TextEditingController _hp;
  late final TextEditingController _mp;
  late final TextEditingController _san;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final scope = RoomScope.read(context);
    final me = findMe(scope.session.state, scope.session.seat);
    final s = memberStats(me);
    _hp = TextEditingController(text: _fmt(s.hp));
    _mp = TextEditingController(text: _fmt(s.mp));
    _san = TextEditingController(text: _fmt(s.san));
  }

  @override
  void dispose() {
    if (_init) {
      _hp.dispose();
      _mp.dispose();
      _san.dispose();
    }
    super.dispose();
  }

  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  /// 本地只做清洗：负数 / 非数字 → 不发这一项（权威端还会夹上限）。
  int? _parse(TextEditingController c) {
    final raw = c.text.trim();
    if (raw.isEmpty) return null;
    final v = int.tryParse(raw);
    if (v == null || v < 0) return null;
    return v;
  }

  void _submitNumbers() {
    final scope = RoomScope.read(context);
    // ★ 双保险第一层（第二层是入口不渲染）：弹层被别的路径打开时也不能穿越权限。
    //   不乐观提示成功 —— 没权限时只说明事实，不改任何 UI 状态文案（K7）。
    if (!scope.controller.gate.can(kSelfStateNumbersOp)) {
      scope.local.showNotice('你没有权限提交数值');
      return;
    }
    final status = <String, Object?>{};
    final hp = _parse(_hp);
    final mp = _parse(_mp);
    final san = _parse(_san);
    if (hp != null) status['currentHP'] = hp;
    if (mp != null) status['currentMP'] = mp;
    if (san != null) status['currentSAN'] = san;
    if (status.isEmpty) {
      scope.local.showNotice('没有要提交的数值');
      return;
    }
    // ★ POLICY: state.edit.self 的 confirm 是 kp ⇒ 走待确认队列。
    scope.controller.hostAction(
      'state.edit.self',
      <String, Object?>{'status': status},
    );
    scope.local.showNotice('已提交，需 KP 同意后生效');
    Navigator.of(context).maybePop();
  }

  void _applyBody(String value) {
    final scope = RoomScope.read(context);
    // ★ 双保险：无权限时不发包、也不宣称「已更新」（K7 不乐观提示成功）。
    if (!scope.controller.gate.can(kSelfStateInstantOp)) {
      scope.local.showNotice('你没有权限修改身体状态');
      return;
    }
    // ★ POLICY: state.self 的 confirm 为 null ⇒ 立即生效。
    scope.controller.hostAction(
      'state.self',
      <String, Object?>{
        'status': <String, Object?>{'body': value},
      },
    );
    scope.local.showNotice('身体状态已更新（立即生效）');
    Navigator.of(context).maybePop();
  }

  void _applyMental(String value) {
    final scope = RoomScope.read(context);
    if (!scope.controller.gate.can(kSelfStateInstantOp)) {
      scope.local.showNotice('你没有权限修改精神状态');
      return;
    }
    scope.controller.hostAction(
      'state.self',
      <String, Object?>{
        'mental': <Object?>[value],
      },
    );
    scope.local.showNotice('精神状态已更新（立即生效）');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final me = findMe(scope.session.state, scope.session.seat);
    final mental = mentalText(me);
    final theme = Theme.of(context);

    return Column(
      key: GpSelfStateKeys.root,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ---- 数字：需 KP 同意 ----
        Text(
          '数值（HP / MP / SAN）：需 KP 同意后才能生效',
          key: GpSelfStateKeys.noticeNumbers,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Expanded(child: _field(GpSelfStateKeys.hp, _hp, 'HP')),
            const SizedBox(width: 6),
            Expanded(child: _field(GpSelfStateKeys.mp, _mp, 'MP')),
            const SizedBox(width: 6),
            Expanded(child: _field(GpSelfStateKeys.san, _san, 'SAN')),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: RoomTap(
            key: GpSelfStateKeys.submitNumbers,
            icon: Icons.send,
            label: '提交数值（需 KP 同意）',
            hint: '提交后进入 KP 的待确认队列',
            minSize: const Size(140, 40),
            onTap: _submitNumbers,
          ),
        ),
        const Divider(height: 16),
        // ---- 身体 / 精神：立即生效 ----
        Text(
          '身体状态：立即生效',
          key: GpSelfStateKeys.noticeBody,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final v in kSelfBodyValues)
              RoomTap(
                key: GpSelfStateKeys.body(v),
                label: v,
                hint: '设为「$v」（立即生效）',
                minSize: const Size(56, 36),
                onTap: () => _applyBody(v),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '精神状态：立即生效（当前：$mental）',
          key: GpSelfStateKeys.noticeMental,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final v in kSelfMentalValues)
              RoomTap(
                key: GpSelfStateKeys.mental(v),
                label: v,
                hint: '设为「$v」（立即生效）',
                minSize: const Size(72, 36),
                onTap: () => _applyMental(v),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '提示：处于「重伤 / 濒死 / 昏迷」时不能自行降级，请用「急救」或请 KP 处理。',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _field(Key key, TextEditingController c, String label) => TextField(
        key: key,
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13),
      );
}

/// 数值型请求的 op（导出给测试断言用，避免测试里写死字符串）。
const String kSelfStateNumbersOp = 'state.edit.self';

/// 立即生效类请求的 op。
const String kSelfStateInstantOp = 'state.self';
