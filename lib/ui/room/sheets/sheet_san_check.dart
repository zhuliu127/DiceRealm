// ============================================================
// sheets/sheet_san_check.dart — SAN Check 弹层（P12 / 第 9 期 · PL-2）
//
// ★ 免审批：直接 `sendIntent(RoomIntent.sanCheck, {okLoss, loss})`，
//   **不经过** `RoomConfirm.kp` / pending / KP 同意（权威端
//   `settleSanCheck` + `afterSanLoss` 链路已完整，domain 零改动）。
// ★ 只画、只发意图：零权威状态赋值、零规则调用、不新增 intent / 事件。
// ★ 实时校验走纯 Dart 的 `SanCheckExpr.parse`，非法时「确定」禁用；
//   定宽控件用 `clampBtnText` 只包该控件子树（textScaler 1.3/1.5/2.0）。
// ★ 新 Key 一律独立 `ValueKey<String>`，不挂 `act/` 锚点。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_types.dart' show RoomIntent;
import '../room_scope.dart' show RoomScope;
import '../san_check_expr.dart' show SanCheckExpr;
import '../widgets/room_button_size.dart' show clampBtnText;
import '../widgets/room_panel_kit.dart' show RoomTap;
import 'room_sheet.dart' show showRoomSheet;

/// SAN Check 弹层内部稳定 key。
class SanCheckSheetKeys {
  const SanCheckSheetKeys._();

  static const Key root = ValueKey<String>('sanCheckSheet/root');
  static const Key field = ValueKey<String>('sanCheckSheet/field');
  static const Key submit = ValueKey<String>('sanCheckSheet/submit');
  static const Key cancel = ValueKey<String>('sanCheckSheet/cancel');
}

/// 推一个 SAN Check 弹层。
///
/// [showRoomSheet] 会在弹层 body 外原样重包一层 `RoomScope`，所以
/// [SanCheckSheet] 里可以安全地 `RoomScope.read(context).controller`。
/// 返回泛型 [T] 与项目其它弹层入口（`showPlayerOpposedRequestSheet` 等）同款。
Future<T?> showSanCheckSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: 'SAN Check',
    body: (BuildContext _) => const SanCheckSheet(),
  );
}

/// SAN Check 弹层主体：一行输入 + 实时校验 + 确定 / 取消。
class SanCheckSheet extends StatefulWidget {
  const SanCheckSheet({super.key});

  @override
  State<SanCheckSheet> createState() => _SanCheckSheetState();
}

class _SanCheckSheetState extends State<SanCheckSheet> {
  final TextEditingController _raw = TextEditingController();

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  /// 当前输入的解析结果；非法为 null（驱动「确定」禁用）。
  SanCheckExpr? get _expr => SanCheckExpr.parse(_raw.text);

  void _submit() {
    final SanCheckExpr? expr = _expr;
    if (expr == null) return;
    // ★ 实地核对的精确签名：
    //   `RoomController.sendIntent(String op, Map<String, Object?> p)`
    //   （room_controller.dart:65）。RoomIntent.sanCheck 是既有 13 个意图之一。
    RoomScope.read(context).controller.sendIntent(
          RoomIntent.sanCheck,
          expr.toIntentPayload(),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final SanCheckExpr? expr = _expr;
    final bool invalid = _raw.text.trim().isNotEmpty && expr == null;
    return Column(
      key: SanCheckSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          '格式：成功扣值 / 失败扣值，例如 2/1d6（大小写与空格容错）',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          key: SanCheckSheetKeys.field,
          controller: _raw,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: 'SAN Check 表达式',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: (String _) => setState(() {}),
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
        ),
        if (invalid)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '格式不合法：需要「正整数或骰式 / 正整数或骰式」，如 2/1D6',
              style: TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
          ),
        const SizedBox(height: 10),
        clampBtnText(
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              RoomTap(
                key: SanCheckSheetKeys.submit,
                label: '确定',
                icon: Icons.check,
                enabled: expr != null,
                hint: expr == null ? '请先填写合法表达式' : '发起 SAN Check',
                onTap: _submit,
              ),
              RoomTap(
                key: SanCheckSheetKeys.cancel,
                label: '取消',
                icon: Icons.close,
                hint: '放弃本次输入',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
