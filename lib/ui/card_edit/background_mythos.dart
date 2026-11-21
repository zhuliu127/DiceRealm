// ============================================================
// background_mythos.dart — 角色背景的「克苏鲁神话 / 已学法术」两块
//
// 对齐旧版 `ui/steps-d.js#background`（约 306-520 行）：
//   · 克苏鲁神话：knowledge（已知学识）+ notes（神话相关经历）
//     + **只读**展示技能表里的「克苏鲁神话」技能值
//   · 已学法术：从 `cocSpells`（61 条）选择（**深拷贝**进卡）+ 自定义法术 + 删除 + 计数
//
// ⚠️ `mythos.skill` 与技能表里的 `cthulhu` 是两套东西：
//   旧版只读技能值（`c.skills` 里 id==='cthulhu' 的 total），从不写 `mythos.skill`。
//   这里照抄：**只读、不同步**。
//
// ⚠️ `mythos.notes`：旧版真的写过这个键（steps-d.js:321-324），属于既有契约。
//   不合并进 `knowledge`（语义不同）。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/character.dart';
import '../../domain/data/spells.dart';
import '../../domain/js_compat.dart';
import '../../theme.dart';
import '../widgets.dart';
import 'background_logic.dart';
import '../notice.dart';

/// 克苏鲁神话（知识 + 经历 + 只读技能值）
class MythosEditor extends StatefulWidget {
  const MythosEditor({super.key, required this.card, required this.onChanged});

  final Character card;
  final VoidCallback onChanged;

  @override
  State<MythosEditor> createState() => _MythosEditorState();
}

class _MythosEditorState extends State<MythosEditor> {
  late final TextEditingController _knowledge;
  late final TextEditingController _notes;

  Character get _c => widget.card;

  @override
  void initState() {
    super.initState();
    _knowledge = TextEditingController(
      text: jsStr(_c.mythos['knowledge'] ?? ''),
    );
    _notes = TextEditingController(text: jsStr(_c.mythos['notes'] ?? ''));
  }

  @override
  void dispose() {
    _knowledge.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = mythosSkillTotal(_c);
    return SectionCard(
      title: '克苏鲁神话',
      subtitle: '技能值只读：在「技能」步骤里加点即可提升',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: '克苏鲁神话技能值',
                  value: '$total%',
                  color: Palette.arcane,
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                     FieldLabel('克苏鲁知识'),
                    TextField(
                      key: const Key('mythos_knowledge'),
                      controller: _knowledge,
                      decoration: const InputDecoration(
                        hintText: '已知的神话学识…',
                        isDense: true,
                      ),
                      onChanged: (v) {
                        _c.mythos['knowledge'] = v;
                        widget.onChanged();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
           FieldLabel('神话相关经历', hint: '非必填'),
          TextField(
            key: const Key('mythos_notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '古籍 / 魔法 / 神话生物 / 第三类接触 / 梦境 / 其他…',
            ),
            onChanged: (v) {
              _c.mythos['notes'] = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}

/// 已学会的法术
class SpellsEditor extends StatefulWidget {
  const SpellsEditor({super.key, required this.card, required this.onChanged});

  final Character card;
  final VoidCallback onChanged;

  @override
  State<SpellsEditor> createState() => _SpellsEditorState();
}

class _SpellsEditorState extends State<SpellsEditor> {
  Character get _c => widget.card;

  List<Object?> get _spells => spellsOf(_c);

  void _add(Map<String, Object?> spell) {
    setState(() => _spells.add(spell));
    widget.onChanged();
  }

  Future<void> _pickFromCatalog() async {
    final picked = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => const _SpellPicker(),
    );
    if (picked == null) return;
    // 旧版是 JSON.parse(JSON.stringify(src)) —— 必须深拷贝，否则改卡污染静态表
    final copy = copySpell(picked);
    _add(copy);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSlot(SnackBar(content: Text('已学会：${jsStr(copy['name'])}')));
  }

  Future<void> _customSpell() async {
    final created = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => const _CustomSpellForm(),
    );
    if (created == null) return;
    _add(created);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSlot(SnackBar(content: Text('已学会：${jsStr(created['name'])}')));
  }

  @override
  Widget build(BuildContext context) {
    final list = _spells;
    return CollapsibleSection(
      title: '已学会的法术',
      subtitle: '${list.length} 个',
      toggleKey: 'btn_toggle_spells',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (list.isEmpty)
             EmptyState(
              emoji: '📜',
              icon: Icons.auto_stories_outlined,
              title: '还没有学会法术',
              hint: '从法术表选择，或按格式自定义一个',
            )
          else
            for (var i = 0; i < list.length; i++)
              _SpellCard(
                key: ObjectKey(list[i]),
                spell: asMap(list[i]),
                index: i,
                onRemove: () {
                  setState(() => removeAt(_c, list, i));
                  widget.onChanged();
                },
              ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: const Key('btn_pick_spell'),
                  onPressed: _pickFromCatalog,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.auto_stories_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('从法术表选择', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('btn_custom_spell'),
                  onPressed: _customSpell,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.edit_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('自定义法术', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '提示：法术不是调查员的超能力，每次施放都在蚕食理智。学会途径只有阅读神话典籍或他人传授。',
            style: TextStyle(
              fontSize: 11,
              color: Palette.textMute,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条已学法术（键名照抄 `cocSpells`，不翻译）
class _SpellCard extends StatefulWidget {
  const _SpellCard({
    super.key,
    required this.spell,
    required this.index,
    required this.onRemove,
  });

  final Map<String, Object?> spell;
  final int index;
  final VoidCallback onRemove;

  @override
  State<_SpellCard> createState() => _SpellCardState();
}

class _SpellCardState extends State<_SpellCard> {
  bool _showVariants = false;

  @override
  Widget build(BuildContext context) {
    final sp = widget.spell;
    final variants = asList(sp['variants']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Palette.surface2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  jsStr(sp['name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Pill(text: spellCategory(sp), color: Palette.arcane),
              IconButton(
                key: Key('spell_remove_${widget.index}'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 16, color: Palette.danger),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          Text(
            '消耗：${spellCost(sp)}　用时：${spellTime(sp)}',
            style: TextStyle(
              fontSize: 11,
              color: Palette.textMute,
              height: 1.5,
            ),
          ),
          if (jsStr(sp['effect'] ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                jsStr(sp['effect']),
                style: TextStyle(
                  fontSize: 11.5,
                  color: Palette.textDim,
                  height: 1.6,
                ),
              ),
            ),
          if (jsStr(sp['condition'] ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '施法条件：${jsStr(sp['condition'])}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Palette.textMute,
                  height: 1.5,
                ),
              ),
            ),
          if (variants.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            OutlinedButton(
              key: Key('spell_variants_${widget.index}'),
              onPressed: () => setState(() => _showVariants = !_showVariants),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                textStyle: const TextStyle(fontSize: 11.5),
              ),
              child: Text(_showVariants ? '收起 ▴' : '变体 ${variants.length} 种 ▾'),
            ),
            if (_showVariants)
              for (final vRaw in variants)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${jsStr(asMap(vRaw)['name'])}'
                        '${jsStr(asMap(vRaw)['cost']) == '同基础消耗' ? '' : '（${jsStr(asMap(vRaw)['cost'])}）'}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Palette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (jsStr(asMap(vRaw)['note'] ?? '').isNotEmpty)
                        Text(
                          jsStr(asMap(vRaw)['note']),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Palette.textMute,
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// 法术表选择器（搜索 + 分类筛选，旧版同款）
class _SpellPicker extends StatefulWidget {
  const _SpellPicker();

  @override
  State<_SpellPicker> createState() => _SpellPickerState();
}

class _SpellPickerState extends State<_SpellPicker> {
  String _kw = '';
  String _cat = '全部';

  List<String> get _categories {
    final out = <String>['全部'];
    for (final s in cocSpells) {
      final cat = jsStr(s['category']);
      if (!out.contains(cat)) out.add(cat);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final kw = _kw.trim().toLowerCase();
    final list = cocSpells.where((s) {
      if (_cat != '全部' && jsStr(s['category']) != _cat) return false;
      if (kw.isEmpty) return true;
      final hay =
          '${jsStr(s['name'])} ${jsStr(s['effect'])} ${jsStr(s['condition'])}'
              .toLowerCase();
      return hay.contains(kw);
    }).toList();

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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: <Widget>[
                Text(
                  '法术表（${cocSpells.length} 个）',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('spell_search'),
              decoration: InputDecoration(
                hintText: '搜索法术名 / 效果 / 条件…',
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: Palette.textMute,
                ),
              ),
              onChanged: (v) => setState(() => _kw = v),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                for (final cat in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      key: Key('spell_cat_$cat'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _cat = cat),
                      child: Pill(
                        text: cat,
                        color: _cat == cat ? Palette.goldStr : Palette.textDim,
                        background: _cat == cat ? Palette.goldSoft : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的法术',
                      style: TextStyle(fontSize: 13, color: Palette.textMute),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return ListTile(
                        key: Key('spell_lib_$i'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          jsStr(s['name']),
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Palette.text,
                          ),
                        ),
                        subtitle: Text(
                          '${jsStr(s['cost'])} · ${jsStr(s['time'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Palette.textMute,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 自定义法术（键名照抄旧版 `steps-d.js:463` 的 push）
class _CustomSpellForm extends StatefulWidget {
  const _CustomSpellForm();

  @override
  State<_CustomSpellForm> createState() => _CustomSpellFormState();
}

class _CustomSpellFormState extends State<_CustomSpellForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _category = TextEditingController(text: '自定义');
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final TextEditingController _effect = TextEditingController();
  final TextEditingController _condition = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _cost.dispose();
    _time.dispose();
    _effect.dispose();
    _condition.dispose();
    super.dispose();
  }

  void _save() {
    final nm = _name.text.trim();
    if (nm.isEmpty) {
      setState(() => _error = '法术名称不能为空');
      return;
    }
    Navigator.of(context).pop(
      newCustomSpell(
        name: nm,
        category: _category.text,
        cost: _cost.text,
        time: _time.text,
        effect: _effect.text,
        condition: _condition.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '自定义法术',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        fontFamily: serifFamily,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
               FieldLabel('名称', required: true),
              TextField(
                key: const Key('custom_spell_name'),
                controller: _name,
                decoration: const InputDecoration(hintText: '法术名称，如：阿撒托斯的号角'),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('分类'),
                        TextField(
                          key: const Key('custom_spell_category'),
                          controller: _category,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('施法用时'),
                        TextField(
                          key: const Key('custom_spell_time'),
                          controller: _time,
                          decoration: const InputDecoration(hintText: '例：1 轮'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
               FieldLabel('消耗', hint: '按格式写：X 点魔法值 / X 点理智值 / X 点 POW'),
              TextField(
                key: const Key('custom_spell_cost'),
                controller: _cost,
                decoration: const InputDecoration(
                  hintText: '例：8 点魔法值；1D6 点理智值',
                ),
              ),
              const SizedBox(height: 12),
               FieldLabel('效果'),
              TextField(
                key: const Key('custom_spell_effect'),
                controller: _effect,
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
               FieldLabel('施法条件'),
              TextField(
                key: const Key('custom_spell_condition'),
                controller: _condition,
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('custom_spell_error'),
                  style: TextStyle(fontSize: 12, color: Palette.danger),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('custom_spell_save'),
                onPressed: _save,
                child: const Text('＋ 学会该法术'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
