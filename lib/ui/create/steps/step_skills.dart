// ============================================================
// step_skills.dart — 第 4 步：职业技能
//
// 两件事：
//   ① 满足职业的「本职技能」要求（fixed / choice / free / alt 四种块）
//   ② 把职业点与兴趣点分配完（点数池由 domain 按规则算，不是写死的）
//
// 加点一律走 domain 的 `applyPoint` —— 上限、点数池、「克苏鲁神话 / 信用评级
// 车卡期不可加点」这些约束都在那里，UI 不重复实现一份。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/character.dart';
import '../../../domain/data/skills.dart';
import '../../../domain/js_compat.dart';
import '../../../domain/occupation.dart';
import '../../../domain/rules_coc7.dart';
import '../../../domain/skillmodel.dart';
import '../../../theme.dart';
import '../../widgets.dart';
import '../chargen_logic.dart';
import '../skill_groups.dart';
import '../../notice.dart';

class StepSkills extends StatefulWidget {
  const StepSkills({super.key, required this.draft, required this.onChanged});

  final Character draft;
  final VoidCallback onChanged;

  @override
  State<StepSkills> createState() => _StepSkillsState();
}

class _StepSkillsState extends State<StepSkills> {
  bool _showAll = false;

  /// 当前分类筛选（chip）。[skillGroupAllId] = 不筛。
  String _group = skillGroupAllId;

  /// 模糊搜索关键词
  String _kw = '';
  final TextEditingController _search = TextEditingController();

  Character get _c => widget.draft;

  /// 是否处于「筛选 / 搜索」状态：此时把「只看有加点的」这个省流开关让位，
  /// 否则玩家点了「战斗」却只看到技能点上已有数字的几项，会以为技能丢了。
  bool get _filtering => _group != skillGroupAllId || _kw.trim().isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int _maxFor(Map<String, Object?> req) {
    final c = jsNum(req['count']);
    return c > 0 ? c : 1;
  }

  void _afterPickChange() {
    materializeOccupationalSkills(_c);
    widget.onChanged();
  }

  bool _matches(Map<String, Object?> skill) {
    if (!_filtering) return true;
    final g = skillGroupById(_group);
    if (g.id != skillGroupAllId && !g.contains(jsStr(skill['id']))) return false;
    return skillMatchesKeyword(skill, _kw);
  }

  /// 「任意选择 N 项」弹窗里要隐藏的技能：已经属于本职业的不再出现。
  ///
  /// 口径与 `occupationalSet` 完全一致（fixed / choice / alt / free 已选都算本职），
  /// 但**本块已勾选的仍然显示** —— 否则玩家勾错了取消不掉。
  bool Function(String id, String sub) _occupationBlocked(String reqId) {
    final occ = occupationalSet(_c);
    final own = <String>{
      for (final p in picksOf(_c, reqId))
        keyOf(jsStr(p['skill']), jsStr(p['sub'])),
    };
    return (String id, String sub) {
      final key = keyOf(id, sub);
      if (own.contains(key)) return false; // 自己的选择要能取消
      if (occ.containsKey(key)) return true;
      if (occ.containsKey(id)) return true; // 整组已归职业
      return false;
    };
  }

  Future<void> _pickFree(Map<String, Object?> req) async {
    final reqId = jsStr(req['id']);
    final max = _maxFor(req);
    final picks = picksOf(_c, reqId);
    final blocked = _occupationBlocked(reqId);
    final result = await showModalBottomSheet<List<Map<String, Object?>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => _FreePicker(
        title: jsStr(req['label']),
        max: max,
        initial: picks,
        isBlocked: blocked,
      ),
    );
    if (result == null) return;
    setPicks(_c, reqId, result);
    _afterPickChange();
  }

  Future<void> _openPointSheet(Map<String, Object?> skill) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => _PointSheet(card: _c, skill: skill),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_c.occupationId.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(
          emoji: '🧭',
          icon: Icons.explore_outlined,
          title: '还没有选择职业',
          hint: '回到上一步选一个职业，才能知道哪些技能是本职技能',
        ),
      );
    }

    final reqs = getRequirements(_c);
    final occSet = occupationalSet(_c);
    final occ = occupationPoints(_c);
    final itr = interestPoints(_c);

    final skills = _c.skills.map(asMap).toList();
    final inOccSet = skills
        .where(
          (s) =>
              occSet.containsKey(jsStr(s['key'])) ||
              occSet.containsKey(jsStr(s['id'])),
        )
        .toList();
    final occSkills = inOccSet.where(_matches).toList();
    final otherSkills = skills
        .where((s) => !inOccSet.contains(s))
        .where(_matches)
        .where(
          (s) =>
              _filtering ||
              jsTruthy(_showAll) ||
              jsNum(s['occ']) > 0 ||
              jsNum(s['int']) > 0,
        )
        .toList();
    final hit = occSkills.length + otherSkills.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        _PointsBar(occ: occ, itr: itr),
        const SizedBox(height: 12),
        SectionCard(
          title: '职业限定技能',
          subtitle: '规则要求勾满的项必须选完，才能进入下一步',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final r in reqs) ...<Widget>[
                _RequirementBlock(
                  req: r,
                  picks: picksOf(_c, jsStr(r['id'])),
                  max: _maxFor(r),
                  onToggle: (option) {
                    final ok = togglePick(_c, r, option, max: _maxFor(r));
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSlot(
                        SnackBar(content: Text('最多选 ${_maxFor(r)} 项')),
                      );
                    }
                    _afterPickChange();
                  },
                  onPickFree: () => _pickFree(r),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '技能加点',
          subtitle: '点技能行分配职业点 / 兴趣点；母语与信用评级按规则豁免上限',
          trailing: TextButton.icon(
            key: const Key('btn_auto_spend'),
            onPressed: () {
              final left = autoSpendPoints(_c);
              widget.onChanged();
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
              // ---- 搜索（模糊匹配：中英文、姓名 / id / 子类都认）----
              TextField(
                key: const Key('skill_search'),
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索技能（如：侦查 / 侦 / 拉丁 / spot）',
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: Palette.textMute,
                  ),
                  suffixIcon: _kw.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('skill_search_clear'),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _search.clear();
                            setState(() => _kw = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _kw = v),
              ),
              const SizedBox(height: 8),
              // ---- 分类 chip：只是筛选视图，数据仍是 draft.skills 的那一条 ----
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final g in skillGroups)
                    _GroupChip(
                      key: Key('skill_cat_${g.id}'),
                      label: g.label,
                      selected: _group == g.id,
                      onTap: () => setState(() => _group = g.id),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _filtering
                    ? '命中 $hit 项 · ${skillGroupById(_group).label}'
                    : '共 $hit 项（本职 ${occSkills.length} 项）',
                key: const Key('skill_hit_count'),
                style: TextStyle(fontSize: 11, color: Palette.textMute),
              ),
              const SizedBox(height: 2),
              if (_filtering && hit == 0)
                Padding(
                  key: const Key('skill_none'),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '没有匹配的技能，换个关键词或点「全部」',
                    style: TextStyle(fontSize: 12, color: Palette.textMute),
                  ),
                ),
              for (final s in occSkills)
                _SkillRow(
                  key: Key('skill_row_${jsStr(s['key'])}'),
                  skill: s,
                  isOcc: true,
                  onTap: () => _openPointSheet(s),
                ),
              if (occSkills.isEmpty && !_filtering)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '这个职业没有固定的本职技能实例',
                    style: TextStyle(fontSize: 12, color: Palette.textMute),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Text(
                    '其他技能',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Palette.textMute,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${otherSkills.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Palette.textMute,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const Key('btn_toggle_all_skills'),
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(
                      _showAll ? '只看有加点的' : '显示全部',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              for (final s in otherSkills)
                _SkillRow(
                  key: Key('skill_row_${jsStr(s['key'])}'),
                  skill: s,
                  isOcc: false,
                  onTap: () => _openPointSheet(s),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 分类 chip（`.skill_cat_<id>`）
class _GroupChip extends StatelessWidget {
   const _GroupChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Palette.goldSoft : Palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Palette.gold : Palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Palette.goldStr : Palette.textDim,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 点数条
class _PointsBar extends StatelessWidget {
   const _PointsBar({required this.occ, required this.itr});

  final Map<String, Object?> occ;
  final Map<String, Object?> itr;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '技能点',
      child: Column(
        children: <Widget>[
          _PointLine(
            label: '职业点',
            used: jsNum(occ['used']),
            total: jsNum(occ['total']),
            color: Palette.gold,
            keyValue: 'occ_points_hint',
          ),
          const SizedBox(height: 10),
          _PointLine(
            label: '兴趣点',
            used: jsNum(itr['used']),
            total: jsNum(itr['total']),
            color: Palette.teal,
            keyValue: 'int_points_hint',
          ),
        ],
      ),
    );
  }
}

class _PointLine extends StatelessWidget {
   const _PointLine({
    required this.label,
    required this.used,
    required this.total,
    required this.color,
    required this.keyValue,
  });

  final String label;
  final int used;
  final int total;
  final Color color;
  final String keyValue;

  @override
  Widget build(BuildContext context) {
    final remain = total - used;
    final ratio = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Palette.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$used / $total',
              key: Key(keyValue),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: remain == 0
                    ? Palette.success
                    : (remain < 0 ? Palette.danger : color),
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              remain == 0
                  ? '已用完'
                  : (remain < 0 ? '超出 ${-remain}' : '剩 $remain'),
              style: TextStyle(
                fontSize: 11.5,
                color: remain == 0 ? Palette.success : Palette.textMute,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 3,
            backgroundColor: Palette.surface3,
            valueColor: AlwaysStoppedAnimation<Color>(
              remain < 0 ? Palette.danger : color,
            ),
          ),
        ),
      ],
    );
  }
}

/// 一个职业限定技能块
class _RequirementBlock extends StatelessWidget {
   const _RequirementBlock({
    required this.req,
    required this.picks,
    required this.max,
    required this.onToggle,
    required this.onPickFree,
  });

  final Map<String, Object?> req;
  final List<Map<String, Object?>> picks;
  final int max;
  final void Function(Map<String, Object?> option) onToggle;
  final VoidCallback onPickFree;

  @override
  Widget build(BuildContext context) {
    final type = jsStr(req['type']);
    final label = jsStr(req['label']);
    final done = type == 'fixed' || picks.length >= _need;

    return Container(
      // 稳定 key：概要页「职业限定技能选择完成 → 去修复」的验收要断言
      // 「跳到技能页后真的出现了能勾选的控件」（D2）
      key: Key('req_${jsStr(req['id'])}'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Palette.surface2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: done ? Palette.border : Palette.gold.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                done
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                size: 14,
                color: done ? Palette.success : Palette.gold,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Palette.text,
                    height: 1.4,
                  ),
                ),
              ),
              if (type != 'fixed' && _need > 1)
                Text(
                  '${picks.length}/$_need',
                  style: TextStyle(fontSize: 11, color: Palette.textMute),
                ),
            ],
          ),
          if (type == 'choice' || type == 'alt') ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final oRaw in asList(
                  req[type == 'choice' ? 'pool' : 'options'],
                ))
                  _Chip(
                    text: _optionLabel(asMap(oRaw)),
                    selected: isPicked(
                      picks,
                      asMap(oRaw)['skill'],
                      asMap(oRaw)['sub'],
                    ),
                    onTap: () => onToggle(asMap(oRaw)),
                  ),
              ],
            ),
          ],
          if (type == 'free') ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final p in picks)
                  _Chip(
                    text: jsTruthy(p['name'])
                        ? jsStr(p['name'])
                        : jsStr(p['skill']),
                    selected: true,
                    onTap: () => onToggle(p),
                  ),
                _Chip(
                  key: Key('btn_pick_free_${jsStr(req['id'])}'),
                  text: picks.length >= _need ? '已选满' : '＋ 选择技能',
                  selected: false,
                  dashed: true,
                  onTap: onPickFree,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int get _need {
    final c = jsNum(req['count']);
    return c > 0 ? c : 1;
  }

  static String _optionLabel(Map<String, Object?> o) {
    if (jsTruthy(o['name'])) return jsStr(o['name']);
    final def = skillById(o['skill']);
    final base = def != null ? jsStr(def['name']) : jsStr(o['skill']);
    final sub = jsStr(o['sub']);
    return sub.isEmpty ? base : '$base（$sub）';
  }
}

class _Chip extends StatelessWidget {
   const _Chip({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
    this.dashed = false,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Palette.goldSoft : Palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Palette.gold
                : (dashed ? Palette.borderStr : Palette.border),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Palette.goldStr : Palette.textDim,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 技能行
class _SkillRow extends StatelessWidget {
   const _SkillRow({
    super.key,
    required this.skill,
    required this.isOcc,
    required this.onTap,
  });

  final Map<String, Object?> skill;
  final bool isOcc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occ = jsNum(skill['occ']);
    final itr = jsNum(skill['int']);
    return InkWell(
      onTap: onTap,
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
              // 分类切换只是视图：这个数字始终来自 `draft.skills` 里同一个实例，
              // 所以换分类再换回来必须一模一样（测试据此断言「加点共享」）。
              key: Key('skill_total_${jsStr(skill['key'])}'),
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

/// 加点弹层
/// 加点弹层的**公开入口**。
///
/// 角色卡详情页（P2-A 的「技能加点」编辑区）复用同一个弹层 —— 加点约束
/// （上限、点数池、克苏鲁神话不可加点）只在 domain 的 `applyPoint` 里实现
/// 一份，界面上不该有第二套口径。
class SkillPointSheet extends StatelessWidget {
  const SkillPointSheet({
    super.key,
    required this.card,
    required this.skill,
    this.allowGrowth = false,
  });

  final Character card;
  final Map<String, Object?> skill;

  /// 仅「修改已保存角色」传 true：克苏鲁神话这类技能可以直接加成长点。
  /// 车卡流程用默认 false —— 那里连成长点的入口都不该出现。
  final bool allowGrowth;

  @override
  Widget build(BuildContext context) {
    return _PointSheet(card: card, skill: skill, allowGrowth: allowGrowth);
  }
}

class _PointSheet extends StatefulWidget {
  const _PointSheet({
    required this.card,
    required this.skill,
    this.allowGrowth = false,
  });

  final Character card;
  final Map<String, Object?> skill;
  final bool allowGrowth;

  @override
  State<_PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends State<_PointSheet> {
  String? _error;

  void _apply(String field, int delta) {
    final r = applyPoint(widget.card, widget.skill, field, delta);
    setState(() {
      _error = jsTruthy(r['ok']) ? null : jsStr(r['reason']);
    });
  }

  @override
  Widget build(BuildContext context) {
    final skill = widget.skill;
    final cap = capOf(widget.card, skill);
    final occ = occupationPoints(widget.card);
    final itr = interestPoints(widget.card);
    final growthOnly = isGrowthOnly(skill['id']);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    jsStr(skill['name']),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      fontFamily: serifFamily,
                    ),
                  ),
                ),
                Text(
                  '上限 $cap%',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '基础 ${jsNum(skill['base'])} · 当前最终值 ${jsNum(skill['total'])}',
              style: TextStyle(fontSize: 12, color: Palette.textMute),
            ),
            const SizedBox(height: 12),
            if (growthOnly) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Palette.arcaneSoft,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  widget.allowGrowth
                      ? '这项技能只能通过成长点提升。'
                      : '按规则书，这项技能在车卡时不能用职业点 / 兴趣点加点，只能通过「成长」获得。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.arcane,
                    height: 1.5,
                  ),
                ),
              ),
              if (widget.allowGrowth) ...<Widget>[
                const SizedBox(height: 10),
                _PointStepper(
                  label: '成长点',
                  value: jsNum(skill['growth']),
                  remain: null, // 成长点不来自点数池，没有「可用 N」的说法
                  color: Palette.arcane,
                  keyPrefix: 'growth',
                  onStep: (d) => _apply('growth', d),
                ),
              ],
            ]
            else ...<Widget>[
              _PointStepper(
                label: '职业点',
                value: jsNum(skill['occ']),
                remain: jsNum(occ['remain']),
                color: Palette.gold,
                keyPrefix: 'occ',
                onStep: (d) => _apply('occ', d),
              ),
              const SizedBox(height: 10),
              _PointStepper(
                label: '兴趣点',
                value: jsNum(skill['int']),
                remain: jsNum(itr['remain']),
                color: Palette.teal,
                keyPrefix: 'int',
                onStep: (d) => _apply('int', d),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const Key('point_error'),
                style: TextStyle(fontSize: 12, color: Palette.danger),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // 归零：把两个来源都扣回去（受点数池保护，不会变负）
                      _apply('occ', -jsNum(skill['occ']));
                      _apply('int', -jsNum(skill['int']));
                    },
                    child: const Text('清零'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PointStepper extends StatelessWidget {
  const _PointStepper({
    required this.label,
    required this.value,
    required this.remain,
    required this.color,
    required this.keyPrefix,
    required this.onStep,
  });

  final String label;

  /// 该来源已加的点数（职业点 / 兴趣点 / 成长点）。
  final int value;

  /// 剩余可用点数；`null` = 不限制（成长点不来自点数池）。
  final int? remain;
  final Color color;
  final String keyPrefix;
  final void Function(int delta) onStep;

  /// 直接输入目标值：只把「差值」交给 `onStep`。
  ///
  /// 负值 / 上限 / 点数池 / 「只能靠成长」这些约束一律由 domain 的
  /// `applyPoint` 判定，界面不重复实现；失败时由 `_PointSheet` 的
  /// `_error` 展示原因。
  Future<void> _editValue(BuildContext context) async {
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _ValueInputDialog(
        title: '$label · 目标值',
        initial: value,
        hint: '输入 0 以上的整数',
        inputKey: '${keyPrefix}_value_input',
        okKey: '${keyPrefix}_value_ok',
      ),
    );
    if (target == null || target == value) return;
    onStep(target - value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.surface2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Palette.border),
      ),
      child: Row(
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            key: Key('${keyPrefix}_value'),
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: () => _editValue(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '$value',
                key: Key('${keyPrefix}_value_text'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              remain == null ? '不限制' : '可用 $remain',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Palette.textMute),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: Key('${keyPrefix}_minus'),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.remove_circle_outline,
              size: 20,
              color: Palette.textDim,
            ),
            onPressed: () => onStep(-genStep),
          ),
          IconButton(
            key: Key('${keyPrefix}_plus'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add_circle_outline, size: 20, color: color),
            onPressed: () => onStep(genStep),
          ),
        ],
      ),
    );
  }
}

/// 点数直接输入的弹窗（自带 controller，随路由一起释放）。
///
/// 只用 `digitsOnly` 过滤：非数字敲不进去、负号会被吃掉，
/// 因此 `int.tryParse` 失败只会发生在「空串」这一种情况 —— 回退当前值。
class _ValueInputDialog extends StatefulWidget {
  const _ValueInputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.inputKey,
    required this.okKey,
  });

  final String title;
  final int initial;
  final String hint;
  final String inputKey;
  final String okKey;

  @override
  State<_ValueInputDialog> createState() => _ValueInputDialogState();
}

class _ValueInputDialogState extends State<_ValueInputDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.initial}',
  )..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${widget.initial}'.length,
    );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_ctrl.text.trim());
    Navigator.of(context).pop(n ?? widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.surface2,
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: TextField(
        key: Key(widget.inputKey),
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          helperText: '当前 ${widget.initial}',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: Key(widget.okKey),
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 自由选择技能（多选，带搜索）
///
/// ★ P8：`isBlocked` 由调用方给出「已属于本职业」的判定 —— 弹窗里
///   **直接不列出**这些技能，而不是让玩家选完再提示「已占用」。
class _FreePicker extends StatefulWidget {
  const _FreePicker({
    required this.title,
    required this.max,
    required this.initial,
    this.isBlocked,
  });

  final String title;
  final int max;
  final List<Map<String, Object?>> initial;

  /// (skillId, sub) → 是否隐藏
  final bool Function(String id, String sub)? isBlocked;

  @override
  State<_FreePicker> createState() => _FreePickerState();
}

class _FreePickerState extends State<_FreePicker> {
  late List<Map<String, Object?>> _picked;
  String _kw = '';
  int _hidden = 0;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial.map((p) => Map<String, Object?>.from(p)).toList();
  }

  bool _blocked(Map<String, Object?> o) {
    final f = widget.isBlocked;
    if (f == null) return false;
    return f(jsStr(o['skill']), jsStr(o['sub']));
  }

  List<Map<String, Object?>> get _options {
    final out = <Map<String, Object?>>[];
    for (final s in cocSkills) {
      if (jsTruthy(s['special'])) {
        for (final subRaw in asList(s['subskills'])) {
          final sub = asMap(subRaw);
          final nm = jsStr(sub['name']);
          out.add(<String, Object?>{
            'skill': s['id'],
            'sub': nm,
            'name': '${s['name']}（$nm）',
          });
        }
      } else {
        out.add(<String, Object?>{
          'skill': s['id'],
          'sub': null,
          'name': s['name'],
        });
      }
    }
    final visible = out.where((o) => !_blocked(o)).toList();
    _hidden = out.length - visible.length;
    if (_kw.trim().isEmpty) return visible;
    return visible.where((o) => skillMatchesKeyword(o, _kw)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_picked.length}/${widget.max}',
                  style: TextStyle(fontSize: 12, color: Palette.textMute),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('btn_free_confirm'),
                  onPressed: () => Navigator.of(context).pop(_picked),
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('free_picker_search'),
              decoration: InputDecoration(
                hintText: '搜索技能（如：斗殴 / 侦查 / 拉丁语）',
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: Palette.textMute,
                ),
              ),
              onChanged: (v) => setState(() => _kw = v),
            ),
          ),
          if (_hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已自动隐藏 $_hidden 项本职业已有的技能',
                  key: const Key('free_picker_hidden_hint'),
                  style: TextStyle(fontSize: 11, color: Palette.textMute),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: options.isEmpty
                ? Center(
                    child: Text(
                      '没有可选的技能',
                      key: const Key('free_picker_empty'),
                      style: TextStyle(fontSize: 13, color: Palette.textMute),
                    ),
                  )
                : ListView.builder(
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final o = options[i];
                      final selected = isPicked(_picked, o['skill'], o['sub']);
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: Palette.gold,
                        title: Text(
                          jsStr(o['name']),
                          style: TextStyle(
                            fontSize: 13.5,
                            color: selected ? Palette.goldStr : Palette.text,
                          ),
                        ),
                        onChanged: (v) {
                          setState(() {
                            if (selected) {
                              _picked.removeWhere(
                                (p) =>
                                    jsStr(p['skill']) == jsStr(o['skill']) &&
                                    jsStr(p['sub']) == jsStr(o['sub']),
                              );
                            } else {
                              if (_picked.length >= widget.max) {
                                ScaffoldMessenger.of(context).showSlot(
                                  SnackBar(
                                    content: Text('最多选 ${widget.max} 项'),
                                  ),
                                );
                                return;
                              }
                              _picked.add(Map<String, Object?>.from(o));
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
