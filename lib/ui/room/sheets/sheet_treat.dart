// ============================================================
// sheets/sheet_treat.dart — 玩家「治疗」聚合弹层（P16 波1-A · P-4）
//
// ★ 契约：openTreatSheet(context, {required RoomController ctl}) → Future<void>。
//
// ① 选治疗方式：急救 / 医学 / 精神分析（三分支）；
// ② 选队友（玩家 seat）+ 输入 / 确认检定数值；
// ③ 结算**只读复用** domain 现有实现，不改规则层：
//      · 急救     → aid.apply  {seat, targetSeat, skill:'急救'}
//      · 医学     → aid.apply  {seat, targetSeat, skill:'医学'}
//      · 精神分析 → aid.psycho {seat, targetSeat}
//    三者 POLICY 均为 [player, kp] + RoomConfirm.kp，玩家可直接发起、
//    走 KP 同意流程；成功 / 失败效果全部由 domain 现有实现决定。
//
// ★ 已知口径差（本批不改规则层，报告登记）：
//   · domain 的 aid.apply / aid.psycho 用 skillBaseOf 从角色卡自动取检定值，
//     不接受 UI 传 base → 弹层里的「检定值」输入框仅供确认 / 预留，
//     **不进入 hostAction 载荷**；是否允许手填覆盖需用户单独拍板。
//   · 老 APP 精神分析失败无条件 −1D6 SAN；现有实现
//     (room_model_actions_sheet.dart:1761-1763) 对已疯狂目标免减损。
//   · domain 另有 sheet.healwound（治愈重伤，只能治自己），用户三选一
//     未包含「治愈重伤」，本弹层不提供该分支（波2 / 用户可另行接线）。
//
// ★ 零 emoji、零 jsStr、零权威状态赋值、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../room_controller.dart' show RoomController;
import '../room_text.dart' show roomText;
import '../view/room_view.dart' show playersOf;
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import 'room_sheet.dart' show showRoomSheet;

/// 治疗弹层内部稳定 key。
class TreatSheetKeys {
  const TreatSheetKeys._();

  static const Key root = ValueKey<String>('treatSheet');
  static Key kind(String label) =>
      ValueKey<String>('treatSheet/kind/$label');
  static Key target(String seat) =>
      ValueKey<String>('treatSheet/target/$seat');
  static const Key checkValue = ValueKey<String>('treatSheet/checkValue');
  static const Key submit = ValueKey<String>('treatSheet/submit');
  static const Key back = ValueKey<String>('treatSheet/back');
}

/// 一条治疗分支：UI 文案 → domain action + 可选 skill。
class _TreatKind {
  const _TreatKind(this.label, this.op, this.skill, this.icon);

  final String label;

  /// `'aid.apply'` 或 `'aid.psycho'`。
  final String op;

  /// aid.apply 用（'急救' / '医学'）；aid.psycho 为 null。
  final String? skill;

  final IconData icon;
}

/// 用户口径的三分支（顺序即弹层展示顺序）。
const List<_TreatKind> _kTreatKinds = <_TreatKind>[
  _TreatKind('急救', 'aid.apply', '急救', Icons.healing),
  _TreatKind('医学', 'aid.apply', '医学', Icons.medical_services),
  _TreatKind('精神分析', 'aid.psycho', null, Icons.psychology),
];

/// ★ 契约：打开治疗弹层。
Future<void> openTreatSheet(
  BuildContext context, {
  required RoomController ctl,
}) async {
  await showRoomSheet<void>(
    context: context,
    title: '治疗',
    body: (BuildContext _) => TreatSheet(
      key: const ValueKey<String>('treatSheet/body'),
      ctl: ctl,
    ),
  );
}

/// 治疗弹层主体：选方式 → 选队友 + 确认检定值 → 提交。
class TreatSheet extends StatefulWidget {
  const TreatSheet({super.key, required this.ctl});

  final RoomController ctl;

  @override
  State<TreatSheet> createState() => _TreatSheetState();
}

class _TreatSheetState extends State<TreatSheet> {
  _TreatKind? _kind;
  String _targetSeat = '';

  /// 检定值（可选）：domain 自动从角色卡取 base，这里只做确认 / 预留，
  /// 不进 hostAction 载荷。
  final TextEditingController _checkValue = TextEditingController();

  @override
  void dispose() {
    _checkValue.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    final kind = _kind;
    if (kind == null || _targetSeat.isEmpty) {
      widget.ctl.notice('请先选择治疗方式与队友');
      return;
    }
    final payload = <String, Object?>{
      'seat': widget.ctl.session.seat,
      'targetSeat': _targetSeat,
    };
    final skill = kind.skill;
    if (skill != null) payload['skill'] = skill;
    widget.ctl.hostAction(kind.op, payload);
    /* ★ P17 KP-1⑤：提交成功后必须留一条**本机可见**的反馈，否则用户会判成
       「点了没反应」。domain 侧的「已提交，等待确认」是 `sysTo` 定向系统提示
       （`room_model_host_intent.dart:331-339`），只发**发起玩家**、且要等下一次
       事件才落到通知 / 聊天区，KP 侧完全看不到，弹层又是一提交就关 —— 前后
       没有任何可见变化。这里只补一条本地 banner（`local.notice`，与 domain
       那条是两条不同通道，不重复、不叠第二条 domain 提示），把「等 KP 同意、
       不会立刻结算」说清楚。
       ⚠️ 必须是本行（`hostAction` 之后）：`RoomController.hostAction` 的失败提示
       是 `notice('操作失败：…')`（`room_controller.dart:74-80`），异常走微任务
       才落地，晚于本行 → 真失败时它会把这条「已提交」覆盖掉，不会盖住错误。 */
    widget.ctl.notice('已提交${kind.label}申请，等待 KP 同意');
    Navigator.of(context).pop();
  }

  /// 队友显示名：角色名优先，其次昵称，兜底 seat（与单位枚举同口径）。
  static String _playerLabel(Map<String, Object?> m) {
    final seat = roomText(m['seat']);
    final charName = roomText(m['charName']);
    final nick = roomText(m['nickname']);
    final name = charName.isNotEmpty ? charName : nick;
    return name.isEmpty ? seat : '$name（$seat）';
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final players = playersOf(widget.ctl.session.state);

    return Column(
      key: TreatSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: '选择治疗方式',
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (final k in _kTreatKinds)
                RoomTap(
                  key: TreatSheetKeys.kind(k.label),
                  label: k.label,
                  icon: k.icon,
                  hint: '用${k.label}发起治疗申请',
                  onTap: () => setState(() {
                    _kind = k;
                    _targetSeat = '';
                  }),
                ),
            ],
          ),
        ),
        if (kind != null)
          SectionBox(
            title: '选择队友 · ${kind.label}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text('当前：${kind.label}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    RoomTap(
                      key: TreatSheetKeys.back,
                      label: '重选',
                      icon: Icons.arrow_back,
                      hint: '回到上一步重选治疗方式',
                      onTap: () => setState(() => _kind = null),
                    ),
                  ],
                ),
                if (players.isEmpty)
                  const Text('房间里还没有队友',
                      style: TextStyle(fontSize: 12)),
                for (final m in players)
                  RoomTap(
                    key: TreatSheetKeys.target(roomText(m['seat'])),
                    label: '${_playerLabel(m)}'
                        '${_targetSeat == roomText(m['seat']) ? '（已选）' : ''}',
                    hint: '选为治疗目标',
                    onTap: () => setState(
                        () => _targetSeat = roomText(m['seat'])),
                  ),
                TextField(
                  key: TreatSheetKeys.checkValue,
                  controller: _checkValue,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '检定值（可选，留空由角色卡自动读取）',
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                RoomTap(
                  key: TreatSheetKeys.submit,
                  label: '提交申请（等 KP 同意）',
                  icon: Icons.send,
                  hint: '按 domain 现有结算规则执行',
                  onTap: () => _submit(context),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
