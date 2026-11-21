// ============================================================
// step_gear.dart — 车卡第 7 步：随身物品（旧版 `steps-c.js#gear`）
//
// 数据写进既有数组 `items[]`，每条 `{ name, quantity, description }`
// （键名与旧版逐字一致，`newCharacter()` 里 items 已经是空数组）。
//
// ⚠️ 数量口径照抄旧版：`parseInt(v,10) || 1` —— 非法或空一律当 1，
//   不是 0、也不报错（这是老代码的行为，别"优化"）。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/character.dart';
import '../../../domain/js_compat.dart';
import '../../../theme.dart';
import '../../card_edit/combat_logic.dart';
import '../../widgets.dart';
import '../../notice.dart';

class StepGear extends StatefulWidget {
  const StepGear({super.key, required this.draft, required this.onChanged});

  final Character draft;
  final VoidCallback onChanged;

  @override
  State<StepGear> createState() => _StepGearState();
}

class _StepGearState extends State<StepGear> {
  Character get _c => widget.draft;

  List<Object?> get _items => asList(_c.raw['items']);

  void _add(String name) {
    _items.add(newItemEntry(name));
    setState(() {});
    widget.onChanged();
    if (name.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSlot(SnackBar(content: Text('已添加 $name')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        SectionCard(
          title: '常用物品快捷添加',
          subtitle: '10 个预设，点一下加一条',
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (var i = 0; i < gearPresets.length; i++)
                InkWell(
                  key: Key('gear_preset_$i'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _add(gearPresets[i]),
                  child: Pill(text: '＋ ${gearPresets[i]}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '物品清单',
          subtitle: '共 ${_items.length} 项',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_items.isEmpty)
                 EmptyState(
                  emoji: '🎒',
                  icon: Icons.backpack_outlined,
                  title: '背包是空的',
                  hint: '点击下方添加物品',
                )
              else
                for (var i = 0; i < _items.length; i++) _itemRow(i),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('btn_add_item'),
                onPressed: () => _add(''),
                child: const Text('＋ 添加物品'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _itemRow(int i) {
    final it = asMap(_items[i]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  key: Key('item_name_$i'),
                  initialValue: jsStr(it['name']),
                  decoration: const InputDecoration(
                    hintText: '物品名称',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    it['name'] = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 86,
                child: TextFormField(
                  key: Key('item_qty_$i'),
                  initialValue:
                      '${jsNum(it['quantity']) == 0 ? 1 : jsNum(it['quantity'])}',
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: '数量',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    // 非法 / 空 → 1（旧版 `parseInt(v,10) || 1`）
                    it['quantity'] = normalizeItemQuantity(v);
                    widget.onChanged();
                  },
                ),
              ),
              IconButton(
                key: Key('item_remove_$i'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 16, color: Palette.danger),
                onPressed: () {
                  _items.removeAt(i);
                  setState(() {});
                  widget.onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            key: Key('item_desc_$i'),
            initialValue: jsStr(it['description']),
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '描述 / 用途（可选）',
              isDense: true,
            ),
            onChanged: (v) {
              it['description'] = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}
