// ============================================================
// step_combat.dart — 车卡第 6 步：战斗装备（旧版 `steps-c.js#combat`）
//
// 三块：武器 / 防具 / 载具，分别写进既有数组 `weapons / armors / vehicles`
// （键名与元素结构照抄旧版，`newCharacter()` 里这几个键本来就有）。
//
// ⚠️ 硬约束 4：「使用技能」必须是**受约束的清单**（格斗各门类 + 射击各门类 +
//   投掷/炮术/爆破），不许退回自由文本 —— 旧版之前能填出「心理学」。
//   清单与别名归一都在 `card_edit/combat_logic.dart` 里（纯逻辑、可单测）。
//
// ⚠️ 伤害加值 DB / 体格由 `derivedStats` 给出，这里**只读展示**（旧版也不允许手填）。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/character.dart';
import '../../../domain/data/armors.dart';
import '../../../domain/data/vehicles.dart';
import '../../../domain/data/weapons.dart';
import '../../../domain/js_compat.dart';
import '../../../domain/weapon_rules.dart';
import '../../../theme.dart';
import '../../card_edit/combat_logic.dart';
import '../../widgets.dart';
import '../../notice.dart';

class StepCombat extends StatefulWidget {
  const StepCombat({super.key, required this.draft, required this.onChanged});

  final Character draft;
  final VoidCallback onChanged;

  @override
  State<StepCombat> createState() => _StepCombatState();
}

class _StepCombatState extends State<StepCombat> {
  Character get _c => widget.draft;

  List<Object?> get _weapons => asList(_c.raw['weapons']);
  List<Object?> get _armors => asList(_c.raw['armors']);
  List<Object?> get _vehicles => asList(_c.raw['vehicles']);

  void _changed() {
    if (mounted) setState(() {});
    widget.onChanged();
  }

  // ---------------- 武器 ----------------

  Future<void> _openWeaponForm({int? index}) async {
    final isEdit = index != null;
    final init = isEdit ? asMap(_weapons[index]) : <String, Object?>{};
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => _WeaponForm(card: _c, initial: init, isEdit: isEdit),
    );
    if (result == null) return;
    if (isEdit) {
      _weapons[index] = result;
    } else {
      _weapons.add(result);
    }
    _changed();
  }

  Future<void> _pickWeaponFromLibrary() async {
    final picked = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => _LibraryPicker(
        title: '武器库（${cocWeapons.length} 件）',
        hint: '搜索武器 / 技能…',
        items: cocWeapons,
        subtitleOf: (w) {
          final st = skillTotalOf(_c, jsStr(w['skill']));
          return '技能 ${jsStr(w['skill'])}${st.total > 0 ? ' ${st.total}%' : ''}'
              ' · 伤害 ${jsStr(w['damage'])} · 射程 ${jsStr(w['range'])}';
        },
        keyPrefix: 'weapon_lib',
      ),
    );
    if (picked == null) return;
    _weapons.add(weaponFromLibrary(picked));
    _changed();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSlot(SnackBar(content: Text('已添加 ${jsStr(picked['name'])}')));
  }

  // ---------------- 防具 / 载具 ----------------

  Future<void> _pickArmor() async {
    final picked = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => _LibraryPicker(
        title: '防具表（${cocArmors.length} 项）',
        hint: '搜索防具 / 掩体…',
        items: cocArmors,
        subtitleOf: (a) =>
            '护甲 ${jsStr(a['armor'])} · 覆盖 ${jsStr(a['cover'])} · MOV ${jsStr(a['movPenalty'])}',
        keyPrefix: 'armor_lib',
      ),
    );
    if (picked == null) return;
    _armors.add(Map<String, Object?>.from(picked));
    _changed();
  }

  Future<void> _pickVehicle() async {
    final picked = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => _LibraryPicker(
        title: '载具表（${cocVehicles.length} 种）',
        hint: '搜索载具…',
        items: cocVehicles,
        subtitleOf: (v) => 'MOV ${jsStr(v['mov'])} · 技能 ${jsStr(v['skill'])}',
        keyPrefix: 'vehicle_lib',
      ),
    );
    if (picked == null) return;
    _vehicles.add(Map<String, Object?>.from(picked));
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final melee = MeleeSummary.of(_c);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        SectionCard(
          title: '近战修正（自动）',
          subtitle: '力量+体型合计值每超过一个 80，再 +1D6 伤害加成与 +1 体格',
          child: Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: '伤害加值 DB',
                  value: melee.db,
                  color: Palette.gold,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: '体格 Build',
                  value: '${melee.build}',
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: '力量+体型',
                  value: '${melee.strSiz}',
                  compact: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '武器',
          subtitle: '共 ${_weapons.length} 件 · 使用技能只能从战斗类技能里选',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_weapons.isEmpty)
                 EmptyState(
                  emoji: '⚔',
                  icon: Icons.sports_martial_arts,
                  title: '尚未添加武器',
                  hint: '从武器库中选择，或自定义一把',
                )
              else
                for (var i = 0; i < _weapons.length; i++) _weaponRow(i),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      key: const Key('btn_pick_weapon'),
                      onPressed: _pickWeaponFromLibrary,
                      child: const Text(
                        '＋ 从武器库选择',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('btn_custom_weapon'),
                      onPressed: () => _openWeaponForm(),
                      child: const Text(
                        '＋ 自定义武器',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '防具 / 护甲',
          subtitle: '共 ${_armors.length} 项',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_armors.isEmpty)
                 EmptyState(
                  emoji: '🛡',
                  icon: Icons.shield_outlined,
                  title: '尚未装备防具',
                )
              else
                for (var i = 0; i < _armors.length; i++) _armorRow(i),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('btn_pick_armor'),
                onPressed: _pickArmor,
                child: const Text('＋ 从防具表选择'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '载具',
          subtitle: '共 ${_vehicles.length} 项',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_vehicles.isEmpty)
                 EmptyState(
                  emoji: '🚗',
                  icon: Icons.directions_car_outlined,
                  title: '尚未拥有载具',
                )
              else
                for (var i = 0; i < _vehicles.length; i++) _vehicleRow(i),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('btn_pick_vehicle'),
                onPressed: _pickVehicle,
                child: const Text('＋ 从载具表选择'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _weaponRow(int i) {
    final w = asMap(_weapons[i]);
    final st = jsStr(w['skill']).isEmpty
        ? null
        : skillTotalOf(_c, jsStr(w['skill']));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  jsStr(w['name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: Palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (jsStr(w['category']).isNotEmpty)
                Pill(text: jsStr(w['category'])),
              const SizedBox(width: 6),
              Text(
                '×${jsNum(w['qty']) == 0 ? 1 : jsNum(w['qty'])}',
                style: TextStyle(fontSize: 12, color: Palette.gold),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '技能 ${jsStr(w['skill'])}${st != null && st.total > 0 ? '（${st.total}%）' : ''}'
            '　伤害 ${jsStr(w['damage'])}${jsStr(w['pierce']) == '√' ? '（贯穿）' : ''}'
            '　射程 ${jsStr(w['range'])}　连发 ${jsStr(w['perRound'])}'
            '　装弹 ${jsStr(w['ammo'])}　故障 ${jsStr(w['malfunction'])}',
            style: TextStyle(
              fontSize: 11,
              color: Palette.textMute,
              height: 1.5,
            ),
          ),
          if (st != null && st.total > 0)
            Text(
              '成功率：常规 ${st.total}%　困难 ${(st.total / 2).floor()}%　极难 ${(st.total / 5).floor()}%',
              style: TextStyle(fontSize: 10.5, color: Palette.textMute),
            ),
          Row(
            children: <Widget>[
              TextButton(
                key: Key('weapon_edit_$i'),
                onPressed: () => _openWeaponForm(index: i),
                child: const Text('编辑', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              IconButton(
                key: Key('weapon_qty_minus_$i'),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.remove_circle_outline,
                  size: 18,
                  color: Palette.textDim,
                ),
                onPressed: () {
                  stepWeaponQty(w, -1);
                  _changed();
                },
              ),
              Text(
                '${jsNum(w['qty']) == 0 ? 1 : jsNum(w['qty'])} 件',
                style: TextStyle(fontSize: 11.5, color: Palette.textDim),
              ),
              IconButton(
                key: Key('weapon_qty_plus_$i'),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.add_circle_outline,
                  size: 18,
                  color: Palette.gold,
                ),
                onPressed: () {
                  stepWeaponQty(w, 1);
                  _changed();
                },
              ),
              IconButton(
                key: Key('weapon_remove_$i'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 16, color: Palette.danger),
                onPressed: () {
                  _weapons.removeAt(i);
                  _changed();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _armorRow(int i) {
    final a = asMap(_armors[i]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  jsStr(a['name']),
                  style: TextStyle(fontSize: 13.5, color: Palette.text),
                ),
                Text(
                  '护甲 ${jsStr(a['armor'])}　覆盖 ${jsStr(a['cover'])}　MOV ${jsStr(a['movPenalty'])}',
                  style: TextStyle(fontSize: 11, color: Palette.textMute),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('armor_remove_$i'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 16, color: Palette.danger),
            onPressed: () {
              _armors.removeAt(i);
              _changed();
            },
          ),
        ],
      ),
    );
  }

  Widget _vehicleRow(int i) {
    final v = asMap(_vehicles[i]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  jsStr(v['name']),
                  style: TextStyle(fontSize: 13.5, color: Palette.text),
                ),
                Text(
                  'MOV ${jsStr(v['mov'])}　技能 ${jsStr(v['skill'])}　体格 ${jsStr(v['build'])}　载员 ${jsStr(v['capacity'])}',
                  style: TextStyle(fontSize: 11, color: Palette.textMute),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('vehicle_remove_$i'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 16, color: Palette.danger),
            onPressed: () {
              _vehicles.removeAt(i);
              _changed();
            },
          ),
        ],
      ),
    );
  }
}

/// 武器编辑表单（库选择 / 自定义共用）
class _WeaponForm extends StatefulWidget {
  const _WeaponForm({
    required this.card,
    required this.initial,
    required this.isEdit,
  });

  final Character card;
  final Map<String, Object?> initial;
  final bool isEdit;

  @override
  State<_WeaponForm> createState() => _WeaponFormState();
}

class _WeaponFormState extends State<_WeaponForm> {
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _damage;
  late final TextEditingController _range;
  late final TextEditingController _perRound;
  late final TextEditingController _ammo;
  late final TextEditingController _malfunction;
  late final TextEditingController _qty;
  late final TextEditingController _note;
  late List<WeaponSkillOption> _skillOptions;
  late String _skill;
  late String _pierce;
  String? _error;

  Map<String, Object?> get _w => widget.initial;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: jsStr(_w['name']));
    _category = TextEditingController(
      text: jsStr(_w['category']).isEmpty ? '自定义' : jsStr(_w['category']),
    );
    _damage = TextEditingController(text: jsStr(_w['damage']));
    _range = TextEditingController(text: jsStr(_w['range']));
    _perRound = TextEditingController(text: jsStr(_w['perRound']));
    _ammo = TextEditingController(text: jsStr(_w['ammo']));
    _malfunction = TextEditingController(text: jsStr(_w['malfunction']));
    _qty = TextEditingController(
      text: '${jsNum(_w['qty']) == 0 ? 1 : jsNum(_w['qty'])}',
    );
    _note = TextEditingController(text: jsStr(_w['note']));
    _skill = jsStr(_w['skill']).isEmpty ? '斗殴' : jsStr(_w['skill']);
    _skillOptions = weaponSkillOptionsFor(widget.card, _skill);
    _skill = _skillOptions.first.value;
    _pierce = jsStr(_w['pierce']) == '√' ? '√' : '×';
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _damage.dispose();
    _range.dispose();
    _perRound.dispose();
    _ammo.dispose();
    _malfunction.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '武器名称不能为空');
      return;
    }
    /* 朋友 bug 1：故障值必须 < 100（1-99），否则存进去的枪永远不会卡壳。
       空 / 「——」表示该武器不会故障，按官方武器表的写法放行。 */
    final malfunctionError = weaponMalfunctionError(_malfunction.text);
    if (malfunctionError != null) {
      setState(() => _error = malfunctionError);
      return;
    }
    // 以 initial 为底（保住 era / price / id 等表单没有的字段），再叠加表单值
    final out = <String, Object?>{};
    _w.forEach((k, v) => out[k] = v);
    out['name'] = _name.text.trim();
    out['skill'] = _skill;
    out['category'] = _category.text.trim();
    out['damage'] = _damage.text.trim();
    out['range'] = _range.text.trim();
    out['pierce'] = _pierce;
    out['perRound'] = _perRound.text.trim();
    out['ammo'] = _ammo.text.trim();
    out['malfunction'] = _malfunction.text.trim();
    out['qty'] = normalizeItemQuantity(_qty.text);
    out['note'] = _note.text.trim();
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final current = _skillOptions.firstWhere(
      (o) => o.value == _skill,
      orElse: () => _skillOptions.first,
    );
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
                  Expanded(
                    child: Text(
                      widget.isEdit ? '编辑武器' : '自定义武器',
                      style: const TextStyle(
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
               FieldLabel('武器名称', required: true),
              TextField(
                key: const Key('weapon_name'),
                controller: _name,
                decoration: const InputDecoration(hintText: '例：左轮手枪'),
              ),
              const SizedBox(height: 12),
               FieldLabel('使用技能', hint: '只能选战斗类技能；右边是角色当前的成功率'),
              DropdownButtonFormField<String>(
                key: const Key('weapon_skill'),
                initialValue: _skill,
                isExpanded: true,
                items: <DropdownMenuItem<String>>[
                  for (final o in _skillOptions)
                    DropdownMenuItem<String>(
                      value: o.value,
                      child: Text(
                        o.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _skill = v);
                },
              ),
              const SizedBox(height: 6),
              Text(
                current.chanceText,
                style: TextStyle(fontSize: 11.5, color: Palette.textMute),
              ),
              const SizedBox(height: 12),
               FieldLabel('类型'),
              TextField(
                key: const Key('weapon_category'),
                controller: _category,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('伤害'),
                        TextField(
                          key: const Key('weapon_damage'),
                          controller: _damage,
                          decoration: const InputDecoration(hintText: '1D10'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('射程'),
                        TextField(
                          key: const Key('weapon_range'),
                          controller: _range,
                          decoration: const InputDecoration(hintText: '15码'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
               FieldLabel('贯穿'),
              SegmentedButton<String>(
                key: const Key('weapon_pierce'),
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: '×', label: Text('× 不贯穿')),
                  ButtonSegment<String>(value: '√', label: Text('√ 贯穿')),
                ],
                selected: <String>{_pierce},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _pierce = v.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('连发（每轮）'),
                        TextField(
                          key: const Key('weapon_per_round'),
                          controller: _perRound,
                          decoration: const InputDecoration(
                            hintText: '1 / 1(2)',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('装弹量'),
                        TextField(
                          key: const Key('weapon_ammo'),
                          controller: _ammo,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('故障值'),
                        TextField(
                          key: const Key('weapon_malfunction'),
                          controller: _malfunction,
                          decoration: const InputDecoration(
                            hintText: '99 / 100',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('数量'),
                        TextField(
                          key: const Key('weapon_qty'),
                          controller: _qty,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
               FieldLabel('备注'),
              TextField(
                key: const Key('weapon_note'),
                controller: _note,
                minLines: 2,
                maxLines: 3,
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('weapon_error'),
                  style: TextStyle(fontSize: 12, color: Palette.danger),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('weapon_save'),
                onPressed: _save,
                child: const Text('保存武器'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用「从数据表里挑一条」弹层（武器 / 防具 / 载具共用）
class _LibraryPicker extends StatefulWidget {
  const _LibraryPicker({
    required this.title,
    required this.hint,
    required this.items,
    required this.subtitleOf,
    required this.keyPrefix,
  });

  final String title;
  final String hint;
  final List<Map<String, Object?>> items;
  final String Function(Map<String, Object?> item) subtitleOf;
  final String keyPrefix;

  @override
  State<_LibraryPicker> createState() => _LibraryPickerState();
}

class _LibraryPickerState extends State<_LibraryPicker> {
  String _kw = '';

  @override
  Widget build(BuildContext context) {
    final kw = _kw.trim().toLowerCase();
    final list = widget.items.where((x) {
      if (kw.isEmpty) return true;
      final hay =
          '${jsStr(x['name'])} ${jsStr(x['skill'])} ${jsStr(x['category'])}'
              .toLowerCase();
      return hay.contains(kw);
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
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
              key: Key('${widget.keyPrefix}_search'),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: Palette.textMute,
                ),
              ),
              onChanged: (v) => setState(() => _kw = v),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的条目',
                      style: TextStyle(fontSize: 13, color: Palette.textMute),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final item = list[i];
                      return ListTile(
                        key: Key('${widget.keyPrefix}_$i'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          jsStr(item['name']),
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Palette.text,
                          ),
                        ),
                        subtitle: Text(
                          widget.subtitleOf(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Palette.textMute,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
