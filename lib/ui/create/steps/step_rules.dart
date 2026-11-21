// ============================================================
// step_rules.dart — 第 1 步：规则系统
//
// 目前只有 COC 7th 一套（[RuleRegistry.defaultRule]），选中即可下一步。
// 其余规则系统在 domain 里是「占位项」（[RuleRegistry.placeholders]），
// 这里如实展示为「敬请期待」，不假装可选。
// ★ P7-D：元信息单一真源收敛到 `lib/domain/rule_registry.dart`
//   （COC7 字段取自 `Coc7.id/name/shortName/rulebook`），本页不散落字面量。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/character.dart';
import '../../../domain/rule_registry.dart' show RuleRegistry;
import '../../../theme.dart';
import '../../widgets.dart';

class StepRules extends StatelessWidget {
   const StepRules({super.key, required this.draft, required this.onChanged});

  final Character draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rule = RuleRegistry.defaultRule;
    final selected = draft.ruleSystemId == rule.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        Text(
          '选择一套规则系统。属性、技能、检定与派生数值都由它决定，建卡后不可更改。',
          style: TextStyle(
            fontSize: 12.5,
            color: Palette.textMute,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 14),
        _RuleCard(
          key: const Key('rule_coc7'),
          title: rule.name,
          subtitle: rule.shortName,
          desc: rule.description,
          version: rule.rulebook,
          selected: selected,
          onTap: () {
            draft.raw['ruleSystemId'] = rule.id;
            onChanged();
          },
        ),
        const SizedBox(height: 20),
        Text(
          '未开放',
          style: TextStyle(
            fontSize: 11.5,
            color: Palette.textMute,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        for (final ph in RuleRegistry.placeholders) ...<Widget>[
          _RuleCard(
            title: ph.name,
            subtitle: ph.shortName,
            desc: ph.description,
            selected: false,
            disabled: true,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
   const _RuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.desc,
    required this.selected,
    this.version,
    this.disabled = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String desc;
  final String? version;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? Palette.gold : Palette.border;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: disabled ? null : onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? Palette.goldSoft : Palette.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: borderColor, width: selected ? 1.3 : 1),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: serifFamily,
                          color: selected ? Palette.goldStr : Palette.text,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Palette.gold,
                      )
                    else if (!disabled)
                      Icon(
                        Icons.radio_button_unchecked,
                        size: 18,
                        color: Palette.textMute,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Pill(
                      text: subtitle,
                      color: selected ? Palette.goldStr : Palette.textDim,
                    ),
                    if (version != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          version!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Palette.textMute,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Palette.textDim,
                    height: 1.55,
                  ),
                ),
                if (disabled) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '敬请期待',
                    style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
