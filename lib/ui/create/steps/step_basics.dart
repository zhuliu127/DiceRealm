// ============================================================
// step_basics.dart — 第 2 步：基础信息
//
// 姓名 / 玩家名 / 性别 / 年龄 / 职业 / 头像（P10 追加）。
// 年龄在这里只做「规则提示」（区间带来的属性扣减与教育进步检定次数），
// 真正的扣减在 domain 的 ageAdjust 里算 —— 本步不改写属性原值。
//
// ★ 头像只写 `raw['avatar']`（形如 `avatars/<cardId>.png` 的相对路径），
//   图片本体在 `repo/avatar_store.dart` 里落盘 —— 不把二进制塞进存档。
// ============================================================

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/character.dart';
import '../../../domain/js_compat.dart';
import '../../../domain/occupation.dart';
import '../../../domain/rules_coc7.dart';
import '../../../repo/avatar_store.dart';
import '../../../theme.dart';
import '../../widgets.dart';
import '../../widgets/avatar_picker.dart';
import '../chargen_logic.dart';

class StepBasics extends StatefulWidget {
  const StepBasics({super.key, required this.draft, required this.onChanged});

  final Character draft;
  final VoidCallback onChanged;

  @override
  State<StepBasics> createState() => _StepBasicsState();
}

class _StepBasicsState extends State<StepBasics> {
  late final TextEditingController _name;
  late final TextEditingController _player;
  late final TextEditingController _age;
  late final TextEditingController _genderCustom;

  /// 当前头像相对路径（null = 没有头像）。真值仍以 `draft.raw['avatar']` 为准，
  /// 这里只是给本步一个「选完立刻能重画」的副本。
  String? _avatar;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.draft.characterName);
    _player = TextEditingController(text: widget.draft.playerName);
    final age = jsStr(widget.draft.basicInfo['age'] ?? '');
    _age = TextEditingController(text: age);
    _genderCustom = TextEditingController(
      text: jsStr(widget.draft.basicInfo['genderCustom'] ?? ''),
    );
    // 老卡 / 自动 SVG 头像 → localAvatarRel 返回 null，正常显示占位。
    // ★ 这里直接传原始值、不过 `jsStr`：`jsStr(null)` 是字符串 'null'
    //   （JS 语义），会被当成一个相对路径。
    _avatar = localAvatarRel(widget.draft.raw['avatar']);
  }

  /// 写回草稿并按需删掉上一张图（撕卡式清理属于低优先级，但换个头像就
  /// 把旧文件删掉，避免存档目录里堆一串没人引用的 png）。
  void _setAvatar(String? rel) {
    final old = _avatar;
    widget.draft.raw['avatar'] = rel ?? '';
    setState(() => _avatar = rel);
    widget.onChanged();
    if (old != null && old != rel) {
      unawaited(avatarStore.remove(old).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _player.dispose();
    _age.dispose();
    _genderCustom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final age = ageOf(d);
    final rule = ageRule(age > 0 ? age : 25);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        SectionCard(
          title: '调查员',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
               FieldLabel('角色姓名', required: true),
              TextField(
                key: const Key('field_name'),
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: '例：阿米蒂奇·卡特'),
                onChanged: (v) {
                  d.raw['characterName'] = v;
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 14),
               FieldLabel('玩家名称', required: true),
              TextField(
                key: const Key('field_player'),
                controller: _player,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: '你的名字'),
                onChanged: (v) {
                  d.raw['playerName'] = v;
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 14),
               FieldLabel('性别'),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: '男', label: Text('男')),
                  ButtonSegment<String>(value: '女', label: Text('女')),
                  ButtonSegment<String>(value: '其他', label: Text('其他')),
                ],
                selected: <String>{jsStr(d.basicInfo['gender'] ?? '男')},
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
                  d.basicInfo['gender'] = v.first;
                  widget.onChanged();
                },
              ),
              if (jsStr(d.basicInfo['gender']) == '其他') ...<Widget>[
                const SizedBox(height: 10),
                TextField(
                  controller: _genderCustom,
                  decoration: const InputDecoration(hintText: '自定义性别描述'),
                  onChanged: (v) {
                    d.basicInfo['genderCustom'] = v;
                    widget.onChanged();
                  },
                ),
              ],
              const SizedBox(height: 14),
               FieldLabel(
                '年龄',
                required: true,
                hint: '1-200；影响属性扣减与教育进步检定',
              ),
              TextField(
                key: const Key('field_age'),
                controller: _age,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(hintText: '例：32'),
                onChanged: (v) {
                  setAge(d, v.trim().isEmpty ? '' : int.parse(v.trim()));
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Palette.surface2,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: Palette.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Palette.textMute,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${jsStr(rule['note'])}（教育进步检定 ${jsNum(rule['eduChecks'])} 次）',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Palette.textMute,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ---------- 头像（P10） ----------
        SectionCard(
          title: '头像',
          child: AvatarPicker(
            keyPrefix: 'basics_avatar',
            value: _avatar,
            name: widget.draft.characterName,
            cardId: widget.draft.id,
            onChanged: _setAvatar,
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '职业',
          subtitle: '决定本职技能、职业技能点公式与信用评级区间',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InkWell(
                key: const Key('btn_pick_occupation'),
                borderRadius: BorderRadius.circular(Radii.sm),
                onTap: () async {
                  // ★ P8：选职业不该动输入焦点。
                  //   弹层里有搜索框，关掉之后 Flutter 会把焦点还给「上一个
                  //   被聚焦的节点」（通常就是玩家刚填过的年龄输入框），于是
                  //   输入法自己弹出来盖住职业详情 —— 玩家只是选了个职业。
                  //   所以：打开前收一次、关闭后立刻收一次，不让任何输入框接管。
                  final FocusScopeNode scope = FocusScope.of(context);
                  scope.unfocus();
                  final picked = await showOccupationPicker(
                    context,
                    d.occupationId,
                  );
                  if (!mounted) return;
                  scope.unfocus();
                  if (picked == null) return;
                  d.raw['occupationId'] = jsStr(picked['id']);
                  d.basicInfo['occupationName'] = jsStr(picked['name']);
                  // 换职业等于换了一整套本职技能与点数公式，旧的勾选必须清掉
                  d.raw['occupationPicks'] = <String, Object?>{};
                  widget.onChanged();
                  // 重建（onChanged → setState）之后，框架仍可能按焦点遍历顺序
                  // 给第一个可聚焦控件上焦点。帧结束再兜一次，保证「选完职业
                  // 没有任何输入框处于 focused、输入法不弹」。
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) scope.unfocus();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.surface2,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: d.occupationId.isEmpty
                          ? Palette.border
                          : Palette.gold.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          d.occupationId.isEmpty
                              ? '选择职业…'
                              : occupationNameOf(d),
                          style: TextStyle(
                            fontSize: 15,
                            color: d.occupationId.isEmpty
                                ? Palette.textMute
                                : Palette.text,
                            fontWeight: d.occupationId.isEmpty
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
              if (d.occupationId.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _OccupationBrief(occupation: getOccupationById(d.occupationId)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OccupationBrief extends StatelessWidget {
   const _OccupationBrief({required this.occupation});

  final Map<String, Object?>? occupation;

  @override
  Widget build(BuildContext context) {
    if (occupation == null) return const SizedBox.shrink();
    final cred = <String>[
      if (occupation!['creditMin'] != null)
        '信用 ${occupation!['creditMin']}-${occupation!['creditMax']}',
      '点数公式 ${jsStr(occupation!['attrFormula'])}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          cred,
          style: TextStyle(fontSize: 11.5, color: Palette.textMute),
        ),
        const SizedBox(height: 6),
        Text(
          '本职：${jsStr(occupation!['skillText'])}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            color: Palette.textMute,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// 职业选择器：可搜索的底部弹层（230 个职业，下拉框不可用）
Future<Map<String, Object?>?> showOccupationPicker(
  BuildContext context,
  String currentId,
) {
  return showModalBottomSheet<Map<String, Object?>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    builder: (_) => _OccupationPicker(currentId: currentId),
  );
}

class _OccupationPicker extends StatefulWidget {
  const _OccupationPicker({required this.currentId});

  final String currentId;

  @override
  State<_OccupationPicker> createState() => _OccupationPickerState();
}

class _OccupationPickerState extends State<_OccupationPicker> {
  String _kw = '';

  @override
  Widget build(BuildContext context) {
    final list = _kw.trim().isEmpty
        ? listOccupations()
        : searchOccupations(_kw);
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
                const Text(
                  '选择职业',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '${list.length} 个',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('btn_occ_close'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('field_occ_search'),
              autofocus: false,
              decoration: InputDecoration(
                hintText: '搜索职业名 / 技能 / 描述（如：格斗、医学、教授）',
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
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的职业',
                      style: TextStyle(fontSize: 13, color: Palette.textMute),
                    ),
                  )
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: Palette.border),
                    itemBuilder: (context, i) {
                      final o = list[i];
                      final id = jsStr(o['id']);
                      final selected = id == widget.currentId;
                      return ListTile(
                        dense: true,
                        title: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                jsStr(o['name']),
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: selected
                                      ? Palette.goldStr
                                      : Palette.text,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check,
                                size: 15,
                                color: Palette.gold,
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${jsStr(o['attrFormula'])}${o['creditMin'] != null ? ' · 信用 ${o['creditMin']}-${o['creditMax']}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Palette.textMute,
                          ),
                        ),
                        onTap: () {
                          // 先交还焦点再关弹层：否则焦点会带着「搜索框」的
                          // 输入法状态回到上层路由（选完职业输入法自己弹出来）。
                          FocusScope.of(context).unfocus();
                          Navigator.of(context).pop(o);
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
