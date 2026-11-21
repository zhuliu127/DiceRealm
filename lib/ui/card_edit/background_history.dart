// ============================================================
// background_history.dart — 角色背景的「调查员经历 / 调查员伙伴」两块
//
// 逐段对齐旧版 `ui/steps-d.js#background`（约 247-305 行）：
//   · 经历：9 个字段（title / date / description / sanChange / hpChange /
//     skillChanges / moneyChange / itemsObtained / notes），可增删
//   · 伙伴：6 个字段（name / avatar / identity / age / relationship / description），可增删
//
// ⚠️ 数字型字段（sanChange / hpChange / moneyChange）**照抄字符串**：
//   旧版 `oninput` 存的就是 `this.value`（字符串），Dart 侧照抄才能与老卡读回一致；
//   也天然不会把半截输入（"-"、""）变成 0 或 NaN。
//
// ⚠️ 每条用 `ObjectKey(entry)` 固化身份：删掉中间一条后，剩下几条的输入状态
//   不会因为「下标平移」而串到别人身上。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/character.dart';
import '../../domain/js_compat.dart';
import '../../theme.dart';
import '../widgets.dart';
import 'background_logic.dart';

/// 调查员经历
class HistoryEditor extends StatefulWidget {
  const HistoryEditor({super.key, required this.card, required this.onChanged});

  final Character card;
  final VoidCallback onChanged;

  @override
  State<HistoryEditor> createState() => _HistoryEditorState();
}

class _HistoryEditorState extends State<HistoryEditor> {
  List<Object?> get _list => historyOf(widget.card);

  void _add() {
    setState(() => addHistory(widget.card, newHistoryEntry()));
    widget.onChanged();
  }

  void _remove(int index) {
    setState(() => removeAt(widget.card, _list, index));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return CollapsibleSection(
      title: '调查员经历',
      subtitle: '${list.length} 条 · 用于保存角色成长历史',
      toggleKey: 'btn_toggle_history',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (list.isEmpty)
             EmptyState(
              emoji: '📜',
              icon: Icons.description_outlined,
              title: '还没有经历记录',
              hint: '用于保存角色成长历史',
            )
          else
            for (var i = 0; i < list.length; i++)
              _HistoryEntry(
                key: ObjectKey(list[i]),
                entry: asMap(list[i]),
                index: i,
                onChanged: widget.onChanged,
                onRemove: () => _remove(i),
              ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('btn_add_history'),
            onPressed: _add,
            child: const Text('＋ 添加经历'),
          ),
        ],
      ),
    );
  }
}

class _HistoryEntry extends StatelessWidget {
   const _HistoryEntry({
    super.key,
    required this.entry,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  final Map<String, Object?> entry;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                  textOf(entry, 'title').isEmpty
                      ? '未命名经历'
                      : textOf(entry, 'title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: Key('history_remove_$index'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 16, color: Palette.danger),
                onPressed: onRemove,
              ),
            ],
          ),
          _field('事件标题', 'title', '例：阿卡姆调查事件'),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: _field('发生时间', 'date', '例：1925-03')),
              const SizedBox(width: 8),
              Expanded(child: _field('技能变化', 'skillChanges', '例：侦查 +3')),
            ],
          ),
          const SizedBox(height: 8),
          _field('事件描述', 'description', '发生了什么…', lines: 2),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: _field('SAN 变化', 'sanChange', '-5')),
              const SizedBox(width: 8),
              Expanded(child: _field('HP 变化', 'hpChange', '-2')),
              const SizedBox(width: 8),
              Expanded(child: _field('金钱变化', 'moneyChange', '0')),
            ],
          ),
          const SizedBox(height: 8),
          _field('获得物品', 'itemsObtained', '例：神秘古书'),
          const SizedBox(height: 8),
          _field('备注', 'notes', ''),
        ],
      ),
    );
  }

  Widget _field(String label, String key, String hint, {int lines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Palette.textMute),
        ),
        const SizedBox(height: 3),
        TextFormField(
          key: Key('history_${index}_$key'),
          initialValue: textOf(entry, key),
          minLines: lines,
          maxLines: lines == 1 ? 1 : 3,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint.isEmpty ? null : hint,
            isDense: true,
          ),
          onChanged: (v) {
            setText(entry, key, v);
            onChanged();
          },
        ),
      ],
    );
  }
}

/// 调查员伙伴
class CompanionsEditor extends StatefulWidget {
  const CompanionsEditor({
    super.key,
    required this.card,
    required this.onChanged,
  });

  final Character card;
  final VoidCallback onChanged;

  @override
  State<CompanionsEditor> createState() => _CompanionsEditorState();
}

class _CompanionsEditorState extends State<CompanionsEditor> {
  List<Object?> get _list => companionsOf(widget.card);

  void _add() {
    setState(() => addCompanion(widget.card, newCompanionEntry()));
    widget.onChanged();
  }

  void _remove(int index) {
    setState(() => removeAt(widget.card, _list, index));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return CollapsibleSection(
      title: '调查员伙伴',
      subtitle: '${list.length} 位',
      toggleKey: 'btn_toggle_companions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (list.isEmpty)
             EmptyState(
              emoji: '👥',
              icon: Icons.people_outline,
              title: '还没有伙伴记录',
            )
          else
            for (var i = 0; i < list.length; i++)
              _CompanionEntry(
                key: ObjectKey(list[i]),
                entry: asMap(list[i]),
                index: i,
                onChanged: widget.onChanged,
                onRemove: () => _remove(i),
              ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('btn_add_companion'),
            onPressed: _add,
            child: const Text('＋ 添加伙伴'),
          ),
        ],
      ),
    );
  }
}

class _CompanionEntry extends StatelessWidget {
   const _CompanionEntry({
    super.key,
    required this.entry,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  final Map<String, Object?> entry;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                  textOf(entry, 'name').isEmpty
                      ? '未命名 NPC'
                      : textOf(entry, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: Key('companion_remove_$index'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 16, color: Palette.danger),
                onPressed: onRemove,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(child: _field('姓名', 'name', '例：约翰')),
              const SizedBox(width: 8),
              Expanded(child: _field('身份', 'identity', '例：大学教授')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: _field('年龄', 'age', '')),
              const SizedBox(width: 8),
              Expanded(child: _field('关系', 'relationship', '例：调查搭档')),
            ],
          ),
          const SizedBox(height: 8),
          _field('头像（emoji / 文本）', 'avatar', '例：🧑‍🔬（旧版为空字符串占位）'),
          const SizedBox(height: 8),
          _field('描述', 'description', '例：两年前认识的考古学家。', lines: 2),
        ],
      ),
    );
  }

  Widget _field(String label, String key, String hint, {int lines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Palette.textMute),
        ),
        const SizedBox(height: 3),
        TextFormField(
          key: Key('companion_${index}_$key'),
          initialValue: textOf(entry, key),
          minLines: lines,
          maxLines: lines == 1 ? 1 : 3,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint.isEmpty ? null : hint,
            isDense: true,
          ),
          onChanged: (v) {
            setText(entry, key, v);
            onChanged();
          },
        ),
      ],
    );
  }
}
