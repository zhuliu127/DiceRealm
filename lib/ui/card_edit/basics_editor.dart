// ============================================================
// basics_editor.dart — 角色卡详情的「基本资料」编辑区
//
// 对齐旧版 `ui/steps-a.js#basic` 的字段集 + `app.js` 的编辑态语义：
//   姓名 / 玩家 / 性别（含自定义）/ 年龄 / 职业 / 居住地 / 出生地
//
// 为什么职业也能改：旧版编辑态就是「整张卡重新走一遍向导」，
// 职业当然是可改的。换职业 = 换一整套本职技能与点数公式，所以与车卡
// 向导一样要清空 `occupationPicks`（否则会带着旧职业的勾选去校验新职业）。
//
// 年龄改动会连带影响年龄调整 / 教育进步检定，这些都交给 domain 的
// `recalc()`（保存时统一跑），本文件不碰任何规则数值。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/character.dart';
import '../../domain/js_compat.dart';
import '../../theme.dart';
import '../create/chargen_logic.dart';
import '../create/steps/step_basics.dart';
import '../widgets.dart';

class BasicsEditor extends StatefulWidget {
  const BasicsEditor({super.key, required this.card, required this.onChanged});

  final Character card;
  final VoidCallback onChanged;

  @override
  State<BasicsEditor> createState() => _BasicsEditorState();
}

class _BasicsEditorState extends State<BasicsEditor> {
  late final TextEditingController _name;
  late final TextEditingController _player;
  late final TextEditingController _age;
  late final TextEditingController _genderCustom;
  late final TextEditingController _residence;
  late final TextEditingController _birthplace;

  Character get _c => widget.card;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _c.characterName);
    _player = TextEditingController(text: _c.playerName);
    _age = TextEditingController(text: jsStr(_c.basicInfo['age'] ?? ''));
    _genderCustom = TextEditingController(
      text: jsStr(_c.basicInfo['genderCustom'] ?? ''),
    );
    _residence = TextEditingController(
      text: jsStr(_c.basicInfo['residence'] ?? ''),
    );
    _birthplace = TextEditingController(
      text: jsStr(_c.basicInfo['birthplace'] ?? ''),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _player.dispose();
    _age.dispose();
    _genderCustom.dispose();
    _residence.dispose();
    _birthplace.dispose();
    super.dispose();
  }

  Future<void> _pickOccupation() async {
    final picked = await showOccupationPicker(context, _c.occupationId);
    if (picked == null) return;
    _c.raw['occupationId'] = jsStr(picked['id']);
    _c.basicInfo['occupationName'] = jsStr(picked['name']);
    // 换职业 = 换一整套本职技能与点数公式，旧的勾选必须清掉
    _c.raw['occupationPicks'] = <String, Object?>{};
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final gender = jsStr(_c.basicInfo['gender'] ?? '男');

    return SectionCard(
      title: '基本资料',
      subtitle: '改完点右上角「保存」才写回角色卡',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
           FieldLabel('角色姓名', required: true),
          TextField(
            key: const Key('edit_field_name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: '例：阿米蒂奇·卡特'),
            onChanged: (v) {
              _c.raw['characterName'] = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
           FieldLabel('玩家名称'),
          TextField(
            key: const Key('edit_field_player'),
            controller: _player,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: '你的名字'),
            onChanged: (v) {
              _c.raw['playerName'] = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
           FieldLabel('性别'),
          SegmentedButton<String>(
            key: const Key('edit_field_gender'),
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: '男', label: Text('男')),
              ButtonSegment<String>(value: '女', label: Text('女')),
              ButtonSegment<String>(value: '其他', label: Text('其他')),
            ],
            selected: <String>{gender.isEmpty ? '男' : gender},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Palette.goldSoft
                    : Palette.surface2,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Palette.goldStr
                    : Palette.textDim,
              ),
              side: WidgetStatePropertyAll<BorderSide>(
                BorderSide(color: Palette.border),
              ),
            ),
            onSelectionChanged: (v) {
              _c.basicInfo['gender'] = v.first;
              widget.onChanged();
              setState(() {}); // 自定义性别输入框的显隐
            },
          ),
          if (gender == '其他') ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              key: const Key('edit_field_gender_custom'),
              controller: _genderCustom,
              decoration: const InputDecoration(hintText: '自定义性别描述'),
              onChanged: (v) {
                _c.basicInfo['genderCustom'] = v;
                widget.onChanged();
              },
            ),
          ],
          const SizedBox(height: 12),
           FieldLabel('年龄', required: true, hint: '1-200；影响属性扣减与教育进步检定'),
          TextField(
            key: const Key('edit_field_age'),
            controller: _age,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: const InputDecoration(hintText: '例：32'),
            onChanged: (v) {
              // 空串保持空串（≠ 0）：recalc 会把空年龄当「未填」处理
              setAge(_c, v.trim().isEmpty ? '' : int.parse(v.trim()));
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
           FieldLabel('职业', hint: '换职业会清空已勾选的本职技能'),
          InkWell(
            key: const Key('edit_btn_pick_occupation'),
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: _pickOccupation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Palette.surface2,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: _c.occupationId.isEmpty
                      ? Palette.border
                      : Palette.gold.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _c.occupationId.isEmpty ? '未选择职业' : occupationNameOf(_c),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: _c.occupationId.isEmpty
                            ? Palette.textMute
                            : Palette.text,
                        fontWeight: _c.occupationId.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Palette.textMute,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
           FieldLabel('居住地'),
          TextField(
            key: const Key('edit_field_residence'),
            controller: _residence,
            decoration: const InputDecoration(hintText: '例：阿卡姆 · 洛根街 12 号'),
            onChanged: (v) {
              _c.basicInfo['residence'] = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
           FieldLabel('出生地'),
          TextField(
            key: const Key('edit_field_birthplace'),
            controller: _birthplace,
            decoration: const InputDecoration(hintText: '例：波士顿'),
            onChanged: (v) {
              _c.basicInfo['birthplace'] = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}
