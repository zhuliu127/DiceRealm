// ============================================================
// step_background.dart — 车卡第 5 步：角色背景（旧版 steps-d.js#background）
//
// P1 跳过了这一步，P2-A 补回来。内容全部由 `BackgroundEditor` 承担
// （8 项文本 + 10 套预设 + 疯狂表），保证「车卡」与「详情页编辑」
// 看到的是**同一个组件**，不会两边口径打架。
//
// 这一步**没有任何必填项**（旧版 sub 文案：「都非必填，可稍后补充」），
// 所以校验永远通过 —— 但不能跳过「疯狂表写入结构化症状」这条副作用：
// 它由 BackgroundEditor 在选中时直接落到 card.background / card.madness。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/character.dart';
import '../../../theme.dart';
import '../../card_edit/background_editor.dart';

class StepBackground extends StatefulWidget {
  const StepBackground({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final Character draft;
  final VoidCallback onChanged;

  @override
  State<StepBackground> createState() => _StepBackgroundState();
}

class _StepBackgroundState extends State<StepBackground> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        BackgroundEditor(card: widget.draft, onChanged: widget.onChanged),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Palette.surface2,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: Palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, size: 15, color: Palette.textMute),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '背景不影响任何规则数值，可以留空。从「疯狂表」选中的症状会同时写进'
                  '「疯狂症状」文本与状态里的结构化症状，之后在角色卡详情里能逐条管理。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                    height: 1.55,
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
