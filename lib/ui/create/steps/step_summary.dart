// ============================================================
// step_summary.dart — 最后一步：概要 + 保存
//
// 只读展示：派生值（HP/MP/SAN/MOV/DB/体格）来自保存前那一次 recalc。
//
// 完成度检查 = `wizardChecks()`（规则层 10 项 + UI 层附加项），
// **判定本身仍然只在 domain 里**（`engine.checkList`），这里只负责展示 +
// 「去修复 →」的跳转。「去修复」的目标步骤由 `wizard_checks.dart` 的
// 旧索引 → 步骤 id 映射给出，不在这里硬编码页序。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/character.dart';
import '../../../domain/js_compat.dart';
import '../../../theme.dart';
import '../../art.dart';
import '../../card_view.dart';
import '../../attr_meta.dart';
import '../../widgets.dart';
import '../chargen_logic.dart';
import '../../share_panel.dart';
import '../wizard_checks.dart';

class StepSummary extends StatelessWidget {
   const StepSummary({super.key, required this.draft, this.onJumpTo});

  final Character draft;

  /// 「去修复 →」：跳到该问题所属的步骤（按步骤 id，不按页序数字）
  final void Function(String stepId)? onJumpTo;

  @override
  Widget build(BuildContext context) {
    final checks = wizardChecks(draft);
    final okCount = checks.where((c) => c.ok).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        // 走到最后一步的「完成」插画：纯装饰，高度压得很低，
        // 避免把下面的完成度检查挤出首屏（那一块是可点的「去修复」入口）。
        Center(
          child: SizedBox(
            width: 72,
            height: 72,
            child: ArtImage(Art.wizardDone, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 2),
        SectionCard(
          title: draft.characterName.isEmpty ? '无名调查员' : draft.characterName,
          subtitle:
              '${occupationNameOf(draft)} · ${ageLabel(draft)} · ${genderLabel(draft)}',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      label: '生命 HP',
                      value: hpLabel(draft),
                      color: Palette.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: '魔法 MP',
                      value: mpLabel(draft),
                      color: Palette.teal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      label: '理智 SAN',
                      value: sanLabel(draft),
                      color: Palette.arcane,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: '幸运 LUCK',
                      value: luckLabel(draft),
                      color: Palette.gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      label: '移动力 MOV',
                      value: '${jsNum(draft.derivedStats['mov'])}',
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: '伤害加值 DB',
                      value: jsStr(draft.derivedStats['db']).isEmpty
                          ? '—'
                          : jsStr(draft.derivedStats['db']),
                      compact: true,
                      color: Palette.gold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: '体格',
                      value: '${jsNum(draft.derivedStats['build'])}',
                      compact: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '属性',
          subtitle: '括号内是年龄调整后的生效值（派生数值全部按它计算）',
          child: Column(
            children: <Widget>[
              for (var i = 0; i < coreAttrKeys.length; i += 3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      for (
                        var j = i;
                        j < i + 3 && j < coreAttrKeys.length;
                        j++
                      ) ...<Widget>[
                        if (j > i) const SizedBox(width: 8),
                        Expanded(
                          child: _AttrChip(
                            keyName: coreAttrKeys[j],
                            card: draft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '完成度检查',
          subtitle:
              '$okCount / ${checks.length} 项通过 · 标红项不影响保存，点右侧「去修复」可直接回到那一页',
          child: Column(
            children: <Widget>[
              for (final c in checks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        c.ok ? Icons.check_circle_outline : Icons.error_outline,
                        size: 15,
                        color: c.ok ? Palette.success : Palette.danger,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              c.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: c.ok ? Palette.textDim : Palette.text,
                              ),
                            ),
                            if (!c.ok && c.detail.isNotEmpty)
                              Text(
                                c.detail,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Palette.danger,
                                  height: 1.4,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!c.ok && c.stepId != null && onJumpTo != null)
                        TextButton(
                          key: Key('fix_${c.label}'),
                          onPressed: () => onJumpTo!(c.stepId!),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '去修复 →',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
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
              Icon(Icons.save_outlined, size: 15, color: Palette.textMute),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '保存后会出现在首页「已保存的角色卡」。卡面数值（HP/MP/SAN/DB/MOV）在保存时按当前属性重算，'
                  '之后在角色卡详情里能看到完整的技能与背景。',
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
        const SizedBox(height: 12),

        /* 车卡完成页也给一个分享入口（旧版 share-ui 就是「完成页 + 详情页」
           两处共用）。这里分享的是**当前草稿**：还没保存也能先生成链接，
           保存时 shareId 会一起落库。 */
        SharePanel(card: draft),
      ],
    );
  }
}

class _AttrChip extends StatelessWidget {
   const _AttrChip({required this.keyName, required this.card});

  final String keyName;
  final Character card;

  @override
  Widget build(BuildContext context) {
    final raw = jsNum(card.attributes[keyName]);
    final eff = effAttr(card, keyName);
    final changed = eff != raw;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Palette.surface2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            attrName(keyName),
            style: TextStyle(fontSize: 10.5, color: Palette.textMute),
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Text(
                '$raw',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: changed ? Palette.textMute : Palette.text,
                  decoration: changed ? TextDecoration.lineThrough : null,
                ),
              ),
              if (changed) ...<Widget>[
                const SizedBox(width: 5),
                Text(
                  '→ $eff',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Palette.gold,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
