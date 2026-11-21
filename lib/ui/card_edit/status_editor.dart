// ============================================================
// status_editor.dart — 角色卡详情的「状态管理」编辑区
//
// 对齐旧版 `app.js#statusSheet`（v2.1.10 草稿制 + v2.1.9 统一撕卡判定）：
//
//   · **数字一律「输入框暂存 → 失焦 / 确认才提交」**：
//     清空输入框 = 什么也没提交（≠ 归零），只有真输入了数字（含 0）才写模型。
//     这条是硬约束 1，实现落在 `commitStatusNumber`。
//   · HP/MP/SAN/LUCK 的写入走 `status_ops` 的通道，**同时打上「用户直接改过」
//     标记** —— 否则保存时的 `recalc()` 会把 HP=0 的濒死角色补回满血
//     （P0 报告坑 B，硬约束 4）。
//   · 撕卡**不在这里写**：面板只提示「保存时将判定」，真正的判定与二次确认
//     在详情页的保存流程里（`prepareStatusSave → 确认 → applyRip`）。
//   · 本面板**绝不因为 HP 变化去追加任何疯狂条目**（硬约束 2）：
//     疯狂列表只由玩家显式操作（掷 / 手动 / 删除 / 清空）改变。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/character.dart';
import '../../domain/engine.dart';
import '../../domain/js_compat.dart';
import '../../domain/madness.dart' as mad;
import '../../domain/madness_state.dart' as ms;
import '../../domain/rules_coc7.dart';
import '../../theme.dart';
import '../card_view.dart';
import '../status_ops.dart';
import '../widgets.dart';
import '../notice.dart';

class StatusEditor extends StatefulWidget {
  const StatusEditor({super.key, required this.card, required this.onChanged});

  final Character card;
  final VoidCallback onChanged;

  @override
  State<StatusEditor> createState() => StatusEditorState();
}

/// 提示条的单槽位覆盖（需求 9）。
///
/// 原实现直接 `showSnackBar` —— Flutter 的 SnackBar 是**队列**：
/// 连点几次「推进 1 轮」会排出 N 条，每条默认 4 秒，于是新消息要等
/// 旧消息全部播完才出现（用户看到的「广播很久才消失 / 新消息排在后面」）。
/// 这里先把当前那条**立即移除**再显示新的，并把时长压到 2 秒。
void showSlotNotice(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  messenger.showSlot(
    SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
  );
}

class StatusEditorState extends State<StatusEditor> {
  static const List<String> _numberFields = <String>[
    'currentHP',
    'currentMP',
    'currentSAN',
    'currentLuck',
  ];

  static const Map<String, String> _labels = <String, String>{
    'currentHP': '当前生命 HP',
    'currentMP': '当前魔法 MP',
    'currentSAN': '当前理智 SAN',
    'currentLuck': '当前幸运 LUCK',
  };

  /// 每个状态值一色。
  ///
  /// 用 getter 而不是 `static final` 缓存：`static final` 只在首次访问时求值，
  /// 切到另一套皮肤后这里会永远停在旧配色（暗色下切亮色时数值仍是冷色）。
  static Map<String, Color> get _colors => <String, Color>{
    'currentHP': Palette.danger,
    'currentMP': Palette.teal,
    'currentSAN': Palette.arcane,
    'currentLuck': Palette.gold,
  };

  final Map<String, TextEditingController> _ctrls =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  late final TextEditingController _lossCtrl;
  final FocusNode _lossNode = FocusNode();

  Character get _c => widget.card;

  @override
  void initState() {
    super.initState();
    for (final f in _numberFields) {
      _ctrls[f] = TextEditingController(text: '${jsNum(_c.status[f])}');
      _nodes[f] = FocusNode()..addListener(() => _onFocusChange(f));
    }
    _lossCtrl = TextEditingController(text: '${jsNum(_c.raw['sanLoss'])}');
    _lossNode.addListener(_onLossFocusChange);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    _lossCtrl.dispose();
    _lossNode.dispose();
    super.dispose();
  }

  void _onFocusChange(String field) {
    if (_nodes[field]!.hasFocus) return;
    // 失焦即提交 —— 这是「暂存 → 提交」的提交时机之一（另一个是点保存）
    _commit(field, _ctrls[field]!.text, silent: true);
  }

  void _onLossFocusChange() {
    if (_lossNode.hasFocus) return;
    _commitLoss(_lossCtrl.text, silent: true);
  }

  /// 保存前由详情页调用：把还在输入框里、没失焦的暂存值也提交掉。
  ///
  /// 注意这里**不加"强制提交"**：值没变就不写、更不打 `_hpTouched` 之类的标记 ——
  /// 否则「只是打开编辑又原样保存」会让幸运永远脱离属性（`_luckTouched` 一旦为真，
  /// recalc 就不再让 currentLuck 跟随 LUCK 属性）。
  void commitPending() {
    for (final f in _numberFields) {
      _commit(f, _ctrls[f]!.text, silent: true);
    }
    _commitLoss(_lossCtrl.text, silent: true);
  }

  /// 模型被别处改动（改年龄 / 属性会让上限变化）后刷新显示。
  /// 正在输入（有焦点）的字段不动，免得把用户打了一半的字冲掉。
  void syncFromModel() {
    for (final f in _numberFields) {
      if (_nodes[f]!.hasFocus) continue;
      final shown = '${jsNum(_c.status[f])}';
      if (_ctrls[f]!.text != shown) _ctrls[f]!.text = shown;
    }
    if (!_lossNode.hasFocus) {
      final shown = '${jsNum(_c.raw['sanLoss'])}';
      if (_lossCtrl.text != shown) _lossCtrl.text = shown;
    }
  }

  /// 提交一个数字字段。
  ///
  /// `raw` 为空 / 非数字 → **不写模型**（清空 ≠ 0），并把显示回滚到模型值。
  void _commit(String field, String raw, {bool silent = false}) {
    final text = raw.trim();
    // 值没变：不写模型、不打「用户改过」标记。
    // ⚠️ 比较必须按**数值**而不是字面：'007' / ' 7 ' / '+7' 与 7 是同一个值，
    //    按字面比会误判成「改过」，顺手打上 `_luckTouched`，幸运从此不再跟随属性（D4）。
    if (statusTextEquals(text, _c.status[field])) return;
    final ok = commitStatusNumber(_c, field, text);
    if (!ok) {
      // 空 / 非数字：什么都不提交，显示回滚（用户清空只是想重输）
      _ctrls[field]!.text = '${jsNum(_c.status[field])}';
      if (!silent) setState(() {});
      return;
    }
    recalc(_c);
    // clamp 之后以模型为准（例如 200 会被夹到上限）
    final shown = '${jsNum(_c.status[field])}';
    if (_ctrls[field]!.text != shown) _ctrls[field]!.text = shown;
    if (!silent) setState(() {});
    widget.onChanged();
  }

  void _commitLoss(String raw, {bool silent = false}) {
    final text = raw.trim();
    if (statusTextEquals(text, _c.raw['sanLoss'])) return;
    final parsed = jsParseInt(text);
    if (parsed == null) {
      _lossCtrl.text = '${jsNum(_c.raw['sanLoss'])}';
      if (!silent) setState(() {});
      return;
    }
    setSanLoss(_c, parsed);
    final shown = '${jsNum(_c.raw['sanLoss'])}';
    if (_lossCtrl.text != shown) _lossCtrl.text = shown;
    if (!silent) setState(() {});
    widget.onChanged();
  }

  void _toggleMental(String value) {
    if (value == mentalSymptom) {
      final has = mad.list(_c).any((x) {
        final m = asMap(x);
        return m['bg'] == true || m['permanent'] == true;
      });
      showSlotNotice(
        context,
        has
            ? '「疯狂症状」是背景疯狂表的永久标记：不可治愈、不与跑团游戏联动'
            : '「疯狂症状」只由背景（含 AI 车卡 / 随机出卡）从疯狂表选中的症状自动生成',
      );
      return;
    }
    final changed = applyMentalToggle(_c, value);
    if (!changed) return;
    /* 需求 6：进入「临时疯狂 / 不定疯狂」时**自动获得一条会随轮次消失的疯狂症**。
       手动点 chip 也要走同一条规则（跑团侧由 addSymptom 负责）。 */
    var gained = '';
    final mentalNow = asList(_c.status['mental']).map(jsStr).toList();
    final needsSymptom = (value == mentalTemporary && mentalNow.contains(value)) ||
        (value == mentalIndefinite && mentalNow.contains(value));
    if (needsSymptom) {
      final hasFading =
          mad.list(_c).any((x) => !jsTruthy(asMap(x)['permanent']));
      if (!hasFading) {
        final m = mad.roll('any', false);
        if (m != null) {
          mad.add(_c, m);
          gained = '　获得疯狂症【${mad.labelOf(m['type'])}】${jsStr(m['name'])}'
              '（${jsNum(m['rounds'])} 轮）';
        }
      }
    }
    recalc(_c);
    setState(() {});
    widget.onChanged();
    if (gained.isNotEmpty) showSlotNotice(context, gained.trim());
  }

  void _rollMadness() {
    final m = mad.roll('any', false);
    if (m == null) {
      showSlotNotice(context, '症状表未加载');
      return;
    }
    mad.add(_c, m);
    recalc(_c);
    setState(() {});
    widget.onChanged();
    showSlotNotice(
      context,
      '【${mad.labelOf(m['type'])}】${jsStr(m['name'])}　持续 ${jsNum(m['rounds'])} 轮',
    );
  }

  Future<void> _addMadnessManually() async {
    final picked = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) => const _SymptomPicker(),
    );
    if (picked == null) return;
    if (!mounted) return;
    final entry = mad.make(picked['type'], asMap(picked['src']), false);
    if (entry == null) return;
    mad.add(_c, entry);
    recalc(_c);
    setState(() {});
    widget.onChanged();
  }

  void _advanceRound() {
    final before = ms.normalizeMentalList(asList(_c.status['mental']));
    final faded = mad.advance(_c, 1);
    final mentalBefore = asList(_c.status['mental']).map(jsStr).toList();

    /* 精神状态跟轮次走（需求 6）：
         · 不定疯狂 + 它的疯狂症消退 → 潜在疯狂；
         · 临时疯狂 + 疯狂症消退     → 回正常（临时疯狂不产生潜在疯狂）。
       判据是「还有没有非永久症状」，避免同状态的多条症状里只消退一条就提前改状态。 */
    final stillFading = mad.list(_c).any((x) => !jsTruthy(asMap(x)['permanent']));
    if (faded.isNotEmpty && !stillFading) {
      if (mentalBefore.contains(mentalIndefinite)) {
        _c.status['mental'] = ms.nextMentalState(
          before,
          ms.MentalEvent.symptomFaded,
          fromIndefinite: true,
        ).mental;
      } else if (mentalBefore.contains(mentalTemporary)) {
        _c.status['mental'] =
            ms.nextMentalState(before, ms.MentalEvent.symptomFaded).mental;
      }
    }
    recalc(_c);
    setState(() {});
    widget.onChanged();
    final potentialNow = ms.isPotentialMadness(asList(_c.status['mental']));
    showSlotNotice(
      context,
      faded.isEmpty
          ? '推进 1 轮，没有临时疯狂到期'
          : '推进 1 轮，${faded.length} 条疯狂症已消退：'
                '${faded.map((x) => jsStr(asMap(x)['name'])).join('、')}'
                '${potentialNow ? '（转入「潜在疯狂」：再损失任意 SAN 会立即复发）' : ''}',
    );
  }

  Future<void> _clearMadness() async {
    if (mad.list(_c).isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部疯狂状态？'),
        content: Text('当前有 ${mad.list(_c).length} 条。清空后不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm_clear_madness'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    mad.clear(_c);
    recalc(_c);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rip = ripPending(_c);
    final mental = mentalList(_c);
    final madList = mad.list(_c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionCard(
          title: '状态',
          subtitle: '输入后失焦或点保存才提交；清空输入框不代表 0',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < _numberFields.length; i += 2) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: _numberField(_numberFields[i])),
                    const SizedBox(width: 8),
                    Expanded(
                      child: i + 1 < _numberFields.length
                          ? _numberField(_numberFields[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 2),
              FieldLabel('SAN 上限永久减损', hint: '施放神话法术 / 接触神话生物后累计的减损'),
              TextField(
                key: const Key('status_sanloss'),
                controller: _lossCtrl,
                focusNode: _lossNode,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (v) => _commitLoss(v),
                decoration: const InputDecoration(hintText: '0'),
              ),
              const SizedBox(height: 6),
              Text(
                '当前上限 ${jsNum(_c.status['maxSAN'])}　=　意志 ${jsNum(_c.status['baseMaxSAN'])}'
                '${jsNum(_c.raw['sanLoss']) > 0 ? ' − 减损 ${jsNum(_c.raw['sanLoss'])}' : '（无减损）'}',
                style: TextStyle(fontSize: 11.5, color: Palette.textMute),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '身体状态',
          subtitle: '「濒死 / 昏迷」可与「重伤」叠加；死亡需在保存时二次确认',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SegmentedButton<String>(
                key: const Key('body_seg'),
                segments: <ButtonSegment<String>>[
                  for (final b in bodyStates)
                    ButtonSegment<String>(value: b, label: Text(b)),
                ],
                selected: <String>{
                  bodyStates.contains(jsStr(_c.status['body']))
                      ? jsStr(_c.status['body'])
                      : '正常',
                },
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
                  setBody(_c, v.first);
                  setState(() {});
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 6),
              // 这里刻意不用 SwitchListTile：SectionCard 是带背景色的
              // DecoratedBox，ListTile 的水波纹会被它挡住（Flutter 会断言报错）
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '濒死',
                      style: TextStyle(fontSize: 13, color: Palette.textDim),
                    ),
                  ),
                  Switch(
                    key: const Key('switch_dying'),
                    value: jsTruthy(_c.status['dying']),
                    onChanged: (v) {
                      setFlag(_c, 'dying', v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '昏迷',
                      style: TextStyle(fontSize: 13, color: Palette.textDim),
                    ),
                  ),
                  Switch(
                    key: const Key('switch_unconscious'),
                    value: jsTruthy(_c.status['unconscious']),
                    onChanged: (v) {
                      setFlag(_c, 'unconscious', v);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '精神状态（可多选）',
          subtitle: '「正常」与「永久疯狂」互斥；「不定疯狂 / 潜在疯狂」互斥；'
              '「疯狂症状」是背景疯狂表的永久标记（不可治愈）',
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final o in mentalStatus)
                InkWell(
                  key: Key('status_chip_$o'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _toggleMental(o),
                  child: _Chip(text: o, on: mental.contains(o)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '疯狂状态',
          subtitle: '临时疯狂会随轮次消退，永久疯狂只能手动删除 · 持有 ${madList.length} 条',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (madList.isEmpty)
                 EmptyState(
                  emoji: '🧠',
                  icon: Icons.psychology_outlined,
                  title: '当前没有疯狂状态',
                  hint: '掷一个临时疯狂试试',
                )
              else
                for (final mRaw in madList) ...<Widget>[
                  _MadnessRow(
                    entry: asMap(mRaw),
                    onRemove: () {
                      mad.remove(_c, asMap(mRaw)['id']);
                      recalc(_c);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ],
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('btn_roll_madness'),
                      onPressed: _rollMadness,
                      icon: const Icon(Icons.casino_outlined, size: 16),
                      label: const Text(
                        '掷临时疯狂',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('btn_add_madness'),
                      onPressed: _addMadnessManually,
                      child: const Text('＋ 手动', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('btn_advance_round'),
                      onPressed: _advanceRound,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.skip_next, size: 16),
                          const SizedBox(width: 6),
                          const Text('推进 1 轮', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('btn_clear_madness'),
                      onPressed: _clearMadness,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.delete_outline, size: 16),
                          const SizedBox(width: 6),
                          const Text('清空', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (rip.hit) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Palette.dangerSoft,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: Palette.danger.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Palette.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rip.hint,
                    key: const Key('status_rip_hint'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Palette.danger,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _numberField(String field) {
    final max = statusMaxOf(_c, field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(_labels[field]!, hint: '上限 $max'),
        TextField(
          key: Key('status_${field.replaceFirst('current', '').toLowerCase()}'),
          controller: _ctrls[field],
          focusNode: _nodes[field],
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => _commit(field, v),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _colors[field],
          ),
          decoration: InputDecoration(hintText: '${jsNum(_c.status[field])}'),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
   const _Chip({required this.text, required this.on});

  final String text;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? Palette.goldSoft : Palette.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? Palette.gold : Palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: on ? Palette.goldStr : Palette.textDim,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _MadnessRow extends StatelessWidget {
   const _MadnessRow({required this.entry, required this.onRemove});

  final Map<String, Object?> entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
                  '${mad.labelOf(entry['type'])}　${jsStr(entry['name'])}',
                  style: TextStyle(fontSize: 13, color: Palette.text),
                ),
                if (jsStr(entry['desc']).isNotEmpty)
                  Text(
                    jsStr(entry['desc']),
                    style: TextStyle(
                      fontSize: 11,
                      color: Palette.textMute,
                      height: 1.4,
                    ),
                  ),
                Text(
                  jsTruthy(entry['permanent'])
                      ? (jsTruthy(entry['bg'])
                            ? '背景症状 · 与生俱来，不会自行消退'
                            : '永久疯狂 · 不会自行消退')
                      : '临时疯狂 · 还剩 ${jsNum(entry['rounds'])} 轮',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Palette.textMute,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('madness_remove_${jsStr(entry['id'])}'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 16, color: Palette.danger),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// 手动从 200 条症状里挑一条（不掷骰）
class _SymptomPicker extends StatefulWidget {
  const _SymptomPicker();

  @override
  State<_SymptomPicker> createState() => _SymptomPickerState();
}

class _SymptomPickerState extends State<_SymptomPicker> {
  String _kw = '';

  List<Map<String, Object?>> get _all => <Map<String, Object?>>[
    for (final x in mad.phobias())
      <String, Object?>{'type': 'phobia', 'src': x},
    for (final x in mad.manias()) <String, Object?>{'type': 'mania', 'src': x},
  ];

  @override
  Widget build(BuildContext context) {
    final kw = _kw.trim().toLowerCase();
    final list = _all
        .where((e) {
          if (kw.isEmpty) return true;
          final src = asMap(e['src']);
          final hay =
              '${jsStr(src['name'])} ${jsStr(src['en'])} ${jsStr(src['desc'])}'
                  .toLowerCase();
          return hay.contains(kw);
        })
        .take(200)
        .toList();

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
                const Text(
                  '手动添加症状',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${mad.size} 条',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('symptom_search'),
              decoration: InputDecoration(
                hintText: '搜索症状名 / 英文名',
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
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Palette.border),
              itemBuilder: (context, i) {
                final e = list[i];
                final src = asMap(e['src']);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${mad.labelOf(e['type'])}　${jsStr(src['name'])}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Palette.textDim,
                    ),
                  ),
                  subtitle: Text(
                    jsStr(src['desc']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Palette.textMute,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(e),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
