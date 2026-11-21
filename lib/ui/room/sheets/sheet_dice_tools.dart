// ============================================================
// sheets/sheet_dice_tools.dart — d100 成败阈值（设计 §5 T04 / S4.5）
//
// ★ 2.37.0 / Q4：技能检定 / SAN Check / 自定义骰式 / 暗骰设置四块已删，
//   功能分别在骰条与专用面板中提供；本弹层只保留阈值与 `room.rules`。
//   `DiceToolsKeys` 全部常量一字保留（R9：删符号 = 编译期假红），
//   KP 工具入口 `sheet_kp_panel.dart` 的 `room.rules → diceTools` 不动。
//
// `enabled` 取闸门对 `room.rules` 的结果，保证弹层入口与 §1.6 权限同源。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../room_keys.dart';
import '../room_scope.dart';
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import 'room_sheet.dart' show showRoomSheet;

/// 骰子工具弹层内部稳定 key。
class DiceToolsKeys {
  const DiceToolsKeys._();

  static const Key root = ValueKey<String>('diceTools');
  static const Key skillLabel = ValueKey<String>('diceTools/skillLabel');
  static const Key skillBase = ValueKey<String>('diceTools/skillBase');
  static const Key skillRoll = ValueKey<String>('diceTools/skillRoll');
  static const Key sanCheck = ValueKey<String>('diceTools/sanCheck');
  static const Key customExpr = ValueKey<String>('diceTools/customExpr');
  static const Key customRoll = ValueKey<String>('diceTools/customRoll');
  static const Key crit = ValueKey<String>('diceTools/crit');
  static const Key fumble = ValueKey<String>('diceTools/fumble');
  static const Key rules = ValueKey<String>('diceTools/rules');
  static const Key dark = ValueKey<String>('diceTools/dark');
}

/// 骰子工具弹层。
class DiceToolsSheet extends StatefulWidget {
  const DiceToolsSheet({super.key});

  @override
  State<DiceToolsSheet> createState() => _DiceToolsSheetState();
}

class _DiceToolsSheetState extends State<DiceToolsSheet> {
  final TextEditingController _crit = TextEditingController(text: '1');
  final TextEditingController _fumble = TextEditingController(text: '96');

  @override
  void dispose() {
    _crit.dispose();
    _fumble.dispose();
    super.dispose();
  }

  int _intOf(TextEditingController c, int dflt) =>
      int.tryParse(c.text.trim()) ?? dflt;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;

    return Column(
      key: DiceToolsKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: 'd100 成败阈值',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                key: DiceToolsKeys.crit,
                controller: _crit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '大成功上限（1–99）',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              TextField(
                key: DiceToolsKeys.fumble,
                controller: _fumble,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '大失败下限（1–99）',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: RoomTap(
                  key: RoomKeys.action('room.rules'),
                  label: '保存阈值',
                  enabled: gate.can('room.rules'),
                  hint: gate.can('room.rules') ? '写入房间规则' : '只有 KP 能改规则',
                  onTap: () => ctl.hostAction(
                    'room.rules',
                    <String, Object?>{
                      'critThreshold': _intOf(_crit, 1),
                      'fumbleThreshold': _intOf(_fumble, 96),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 打开骰子工具弹层。
Future<T?> showDiceToolsSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: '检定与骰子',
    body: (BuildContext _) => const DiceToolsSheet(),
  );
}
