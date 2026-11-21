// ============================================================
// skills_editor.dart — 角色卡详情的「技能加点」编辑区
//
// 口径完全交给 domain（`core/skillmodel.js` 的移植）：
//   · 点数池：`occupationPoints` / `interestPoints`
//   · 每次加减：`applyPoint`（负值 / 超上限 / 点数透支 / 「只能靠成长」四项约束）
//   · 上限：`capOf`（本职走 skillCapOcc，兴趣走 skillCapInterest）
// 界面只负责「把点加在哪个技能上」，一条规则都不重复实现。
// 加点弹层直接复用向导里的 `SkillPointSheet`，两边行为必然一致。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/character.dart';
import '../../domain/js_compat.dart';
import '../../domain/occupation.dart';
import '../../theme.dart';
import '../create/chargen_logic.dart';
import '../create/steps/step_skills.dart';
import '../widgets.dart';
import '../notice.dart';

class SkillsEditor extends StatelessWidget {
   const SkillsEditor({super.key, required this.card, required this.onChanged});

  final Character card;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final occ = occupationPoints(card);
    final itr = interestPoints(card);
    final occSet = occupationalSet(card);
    final rows = card.skills.map(asMap).toList()
      ..sort((a, b) {
        final ao =
            occSet.containsKey(jsStr(a['key'])) ||
            occSet.containsKey(jsStr(a['id']));
        final bo =
            occSet.containsKey(jsStr(b['key'])) ||
            occSet.containsKey(jsStr(b['id']));
        if (ao != bo) return ao ? -1 : 1;
        return jsNum(b['total']).compareTo(jsNum(a['total']));
      });
    final shown = rows.where((s) => jsNum(s['total']) > 0).toList();

    return SectionCard(
      title: '技能加点',
      subtitle: '点技能行分配职业点 / 兴趣点；上限与点数池由规则层把关',
      trailing: TextButton.icon(
        key: const Key('btn_edit_auto_spend'),
        onPressed: () {
          final left = autoSpendPoints(card);
          onChanged();
          ScaffoldMessenger.of(context).showSlot(
            SnackBar(
              content: Text(
                left[0] == 0 && left[1] == 0
                    ? '已自动分配完剩余点数'
                    : '已尽量分配，剩余 职业 ${left[0]} / 兴趣 ${left[1]}（技能已达上限）',
              ),
            ),
          );
        },
        icon: const Icon(Icons.auto_fix_high, size: 15),
        label: const Text('一键分配', style: TextStyle(fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PointLine(
            label: '职业点',
            used: jsNum(occ['used']),
            total: jsNum(occ['total']),
            color: Palette.gold,
          ),
          const SizedBox(height: 8),
          _PointLine(
            label: '兴趣点',
            used: jsNum(itr['used']),
            total: jsNum(itr['total']),
            color: Palette.teal,
          ),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Text(
              '还没有技能加点',
              style: TextStyle(fontSize: 12, color: Palette.textMute),
            )
          else
            for (final s in shown)
              _SkillRow(
                card: card,
                skill: s,
                isOcc:
                    occSet.containsKey(jsStr(s['key'])) ||
                    occSet.containsKey(jsStr(s['id'])),
                onChanged: onChanged,
              ),
          const SizedBox(height: 6),
          OutlinedButton(
            key: const Key('btn_show_all_skills'),
            onPressed: () => _openAllSkills(context, rows),
            child: Text(
              '查看全部 ${rows.length} 项技能',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAllSkills(
    BuildContext context,
    List<Map<String, Object?>> rows,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) =>
          _AllSkillsSheet(card: card, rows: rows, onChanged: onChanged),
    );
  }
}

class _PointLine extends StatelessWidget {
   const _PointLine({
    required this.label,
    required this.used,
    required this.total,
    required this.color,
  });

  final String label;
  final int used;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final remain = total - used;
    return Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: Palette.textDim,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '$used / $total',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: remain < 0
                ? Palette.danger
                : (remain == 0 ? Palette.success : color),
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          remain == 0 ? '已用完' : (remain < 0 ? '超出 ${-remain}' : '剩 $remain'),
          style: TextStyle(
            fontSize: 11,
            color: remain < 0 ? Palette.danger : Palette.textMute,
          ),
        ),
      ],
    );
  }
}

class _SkillRow extends StatelessWidget {
   const _SkillRow({
    required this.card,
    required this.skill,
    required this.isOcc,
    required this.onChanged,
  });

  final Character card;
  final Map<String, Object?> skill;
  final bool isOcc;
  final VoidCallback onChanged;

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => SkillPointSheet(card: card, skill: skill),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final occ = jsNum(skill['occ']);
    final itr = jsNum(skill['int']);
    return InkWell(
      key: Key('edit_skill_${jsStr(skill['key'])}'),
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: <Widget>[
            if (isOcc)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(
                  color: Palette.gold,
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    jsStr(skill['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isOcc ? Palette.text : Palette.textDim,
                    ),
                  ),
                  if (occ > 0 || itr > 0)
                    Text(
                      <String>[
                        if (occ > 0) '职业 +$occ',
                        if (itr > 0) '兴趣 +$itr',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Palette.textMute,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '${jsNum(skill['total'])}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Palette.text,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 15, color: Palette.textMute),
          ],
        ),
      ),
    );
  }
}

class _AllSkillsSheet extends StatelessWidget {
   const _AllSkillsSheet({
    required this.card,
    required this.rows,
    required this.onChanged,
  });

  final Character card;
  final List<Map<String, Object?>> rows;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final occSet = occupationalSet(card);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Palette.surface3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: <Widget>[
                const Text(
                  '全部技能',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rows.length} 项',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final s = rows[i];
                return _SkillRow(
                  card: card,
                  skill: s,
                  isOcc:
                      occSet.containsKey(jsStr(s['key'])) ||
                      occSet.containsKey(jsStr(s['id'])),
                  onChanged: onChanged,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
