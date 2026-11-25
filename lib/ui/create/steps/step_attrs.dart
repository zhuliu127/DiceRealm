// ============================================================
// step_attrs.dart — 第 3 步：属性分配
//
// 三种方式（P7-E 把旧版的「天命 N 选一」加回来，对齐 ui/steps-a.js:536-660）：
//   ① 点数分配：单项 15-90、5 的倍数、总和不超过上限（460 / 含幸运 540）
//   ② 随机掷骰：3D6×5（SIZ/INT/EDU 是 2D6+6 再×5）—— 直接调 domain 的 genRandom
//   ③ 天命 N 选一：一次性掷出 N（2-10）组完整属性，玩家挑一组；
//      **掷出后不可重掷**，只能新建卡换一批。
//
// ⚠️ 输入校验在本地做完（`attrFieldError`）才轮到 domain 的 validatePointBuy：
//    后者在原码里引用了未定义的 ATT_MAP，只要收到非法值就抛异常（见 _p0_report.txt 坑 A）。
// ⚠️ 天命纯逻辑（含随机数、持久化、硬拦截数据）全在 `chargen_logic.dart`，
//    本文件只负责画 —— `fate` 原样存在 `draft.raw['fate']`，刷新 / 重进不丢。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/character.dart';
import '../../../domain/js_compat.dart';
import '../../../domain/rules_coc7.dart';
import '../../../theme.dart';
import '../../attr_meta.dart';
import '../../widgets.dart';
import '../chargen_logic.dart';

class StepAttrs extends StatefulWidget {
  const StepAttrs({super.key, required this.draft, required this.onChanged});

  final Character draft;
  final VoidCallback onChanged;

  @override
  State<StepAttrs> createState() => _StepAttrsState();
}

class _StepAttrsState extends State<StepAttrs> {
  late final Map<String, TextEditingController> _ctl;
  late final TextEditingController _fateNCtl;
  String _fateError = '';

  /// 归一后的模式：pointbuy / random / fate（其它脏值按 random 处理）。
  String get _mode {
    final m = jsStr(widget.draft.raw['attributeMode']);
    return (m == 'pointbuy' || m == 'fate') ? m : 'random';
  }

  bool get _pointBuy => _mode == 'pointbuy';
  bool get _fate => _mode == 'fate';
  bool get _includeLuck => jsTruthy(widget.draft.raw['pbIncludeLuck']);

  @override
  void initState() {
    super.initState();
    _ctl = <String, TextEditingController>{
      for (final k in allAttrKeys)
        k: TextEditingController(text: _textOf(widget.draft.attributes[k])),
    };
    _fateNCtl = TextEditingController(text: '${fateN(widget.draft)}');
  }

  static String _textOf(Object? v) => (v == null) ? '' : jsStr(v).trim();

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    _fateNCtl.dispose();
    super.dispose();
  }

  void _write(String key, String raw) {
    final t = raw.trim();
    widget.draft.attributes[key] = t.isEmpty ? '' : (int.tryParse(t) ?? t);
    widget.onChanged();
  }

  void _bump(String key, int delta) {
    final cur = jsNum(widget.draft.attributes[key]);
    var next = (cur == 0 ? genMin : cur) + delta;
    if (next < genMin) next = genMin;
    if (next > genMax) next = genMax;
    _ctl[key]!.text = '$next';
    _write(key, '$next');
  }

  void _roll() {
    final rolled = genRandom();
    rolled.forEach((k, v) {
      if (!_ctl.containsKey(k)) return;
      _ctl[k]!.text = '$v';
      widget.draft.attributes[k] = v;
    });
    HapticFeedback.lightImpact();
    widget.onChanged();
  }

  /* ---------------- 天命 N 选一 ---------------- */

  void _setFateN(int n) {
    if (fateRolled(widget.draft)) return;
    _fateNCtl.text = '$n';
    ensureFate(widget.draft)['n'] = n;
    setState(() => _fateError = '');
    widget.onChanged();
  }

  void _rollFate() {
    final n = int.tryParse(_fateNCtl.text.trim()) ?? 0;
    if (!isValidFateN(n)) {
      setState(() => _fateError = '请把组数填写为 2 - 10 之间的整数');
      return;
    }
    final ok = rollFate(widget.draft, n);
    if (!ok) {
      setState(
        () => _fateError = '天命已经掷出，不能重掷。想换一批请新建角色卡。',
      );
      return;
    }
    setState(() => _fateError = '');
    HapticFeedback.lightImpact();
    widget.onChanged();
  }

  void _pickFate(int i) {
    if (!pickFate(widget.draft, i)) return;
    final attrs = widget.draft.attributes;
    for (final k in allAttrKeys) {
      if (_ctl.containsKey(k)) {
        _ctl[k]!.text = jsStr(attrs[k] ?? '').trim();
      }
    }
    HapticFeedback.selectionClick();
    widget.onChanged();
  }

  /* ---------------- 教育进步检定 ---------------- */

  /// 掷一次教育进步检定（次数由年龄决定，见 `eduCheckAllowance`）。
  ///
  /// 掷骰 / 写卡 / 重算全在 `chargen_logic.dart#runEduCheck`（可单测），
  /// 这里只负责触发与重建 —— 结果落在 `draft.eduProgress`，不是 widget state。
  void _rollEdu() {
    final r = runEduCheck(widget.draft);
    if (r == null) return; // 次数用完：按钮本来就是禁用的，双保险
    HapticFeedback.lightImpact();
    widget.onChanged();
  }

  /// 教育进步检定区块（放在属性页最下方）
  ///
  /// 次数按年龄算（`eduCheckAllowance`）：20–39 岁 1 次、40–49 岁 2 次、
  /// 50–59 岁 3 次、60 岁以上 4 次；每掷一次（成功失败都算）用掉一次。
  ///
  /// ⚠️ 这里显示的「当前教育」是**生效值**：原始 EDU 是玩家买来的点数
  /// （购点上限校验只认它），检定的增益只落在生效值上（与年龄修正同一条路），
  /// 所以原始值不动、生效值变高 —— 概要页会并排显示「原始 → 生效」。
  Widget _eduBlock() {
    final p = ensureEduProgress(widget.draft);
    final log = asList(p['log']);
    final used = log.length;
    final allowance = eduCheckAllowanceOf(widget.draft);
    // 年龄被改小后可能出现「已用 > 允许」，剩余夹到 0（不回退已做的检定）
    final remaining = used >= allowance ? 0 : allowance - used;
    final done = remaining <= 0;
    final bonus = jsNum(p['bonus']);
    final rawEdu = jsNum(widget.draft.attributes['edu']);
    final effEdu = eduForCheck(widget.draft);
    final lastRow = log.isEmpty ? null : asMap(log.last);
    final nth = lastRow == null
        ? used
        : (jsNum(lastRow['n']) > 0 ? jsNum(lastRow['n']) : used);

    /* 结果文案：第一次 = 原措辞；之后每次前面挂上「第 N 次检定：」，
       让玩家看得出这是第几次、总共几次（剩余次数在 edu_check_remain 里）。 */
    final String resultText;
    if (lastRow != null) {
      resultText = '第 $nth 次检定：${eduCheckText(lastRow)}';
    } else if (allowance <= 0) {
      resultText = '本年龄没有教育进步检定次数（15–19 岁不检定，改掷 2 次幸运取较高值）。';
    } else {
      resultText = '尚未检定 —— 不做也照样能保存，只是教育保持原值。';
    }

    return SectionCard(
      title: '教育进步检定',
      subtitle: '年龄带来的教育成长机会：掷 1D100，大于当前教育才 +1D10（上限 99）；'
          '次数随年龄增加 —— 20–39 岁 1 次、40–49 岁 2 次、'
          '50–59 岁 3 次、60 岁以上 4 次',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '原始教育 $rawEdu',
                key: const Key('edu_check_raw'),
                style: TextStyle(fontSize: 12.5, color: Palette.textDim),
              ),
              if (bonus > 0) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  '→ 生效 $effEdu（检定 +$bonus）',
                  key: const Key('edu_check_edu'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Palette.goldStr,
                  ),
                ),
              ] else ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  '生效 $effEdu',
                  key: const Key('edu_check_edu'),
                  style: TextStyle(fontSize: 12.5, color: Palette.textDim),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          /* 剩余次数：单独一行，玩家一眼看到「还能检定几次」。
             全部用完时显示「检定次数已用完（used/allowance）」，
             文案里不带任何 emoji / 符号图标（用户明确要求只要文字）。 */
          Text(
            allowance <= 0
                ? '本档不做教育进步检定（0/0）'
                : (done
                    ? '检定次数已用完（$used/$allowance）'
                    : '还可检定 $remaining 次（已做 $used/$allowance）'),
            key: const Key('edu_check_remain'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: done ? Palette.textMute : Palette.goldStr,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('edu_check_roll'),
            onPressed: done ? null : _rollEdu,
            /* 15–19 岁没有次数：按钮直接写「本年龄段不做检定」并禁用，
               不给一个点不动的「已完成（0/0）」让玩家以为是漏做了什么。 */
            child: Text(
              allowance <= 0
                  ? '本年龄段不做检定'
                  : (done
                      ? '已完成（$used/$allowance）'
                      : '进行检定（还剩 $remaining 次）'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            resultText,
            key: const Key('edu_check_result'),
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: lastRow != null
                  ? (jsNum(lastRow['gain']) > 0
                      ? Palette.goldStr
                      : Palette.textDim)
                  : Palette.textMute,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fateBlock() {
    final fate = ensureFate(widget.draft);
    final rolled = jsTruthy(fate['rolled']);
    final opts = fateOptions(widget.draft);
    final picked = jsParseInt(fate['picked']) ?? -1;

    return SectionCard(
      title: '模式三 · 天命 N 选一',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                rolled ? '已掷出 · 不可重掷' : '未掷出',
                key: const Key('attr_fate_state'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: rolled ? Palette.goldStr : Palette.textMute,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '一次掷出 N 组完整属性，你从中挑一组用。掷出后不能重掷 —— '
            '想换一批天命只能新建角色卡；挑中的那组会写进「属性值」，之后仍可手动微调。',
            style: TextStyle(fontSize: 11.5, color: Palette.textMute, height: 1.7),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('attr_fate_n'),
            controller: _fateNCtl,
            readOnly: rolled,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: const InputDecoration(
              labelText: '组数 N（2 - 10 选 1）',
              hintText: '例如 10，就一次生成 10 组属性',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (String v) {
              final p = int.tryParse(v.trim());
              if (!rolled && p != null && isValidFateN(p)) {
                ensureFate(widget.draft)['n'] = p;
              }
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton(
                key: const Key('attr_fate_quick_5'),
                onPressed: rolled ? null : () => _setFateN(5),
                child: const Text('5 选 1'),
              ),
              OutlinedButton(
                key: const Key('attr_fate_quick_10'),
                onPressed: rolled ? null : () => _setFateN(10),
                child: const Text('10 选 1'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('attr_fate_roll'),
            onPressed: rolled ? null : _rollFate,
            icon: const Icon(Icons.casino_outlined, size: 18),
            label: Text(rolled ? '已掷出（不可重掷）' : '掷出天命'),
          ),
          if (_fateError.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _fateError,
              key: const Key('attr_fate_error'),
              style: TextStyle(fontSize: 11.5, color: Palette.danger),
            ),
          ],
          if (rolled) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              picked >= 0
                  ? '已选定第 ${picked + 1} 组。仍可以在下面改选其它组，但不能再掷新的一批。'
                  : '共 ${opts.length} 组天命，选一组（点「选这组」）。',
              key: const Key('attr_fate_hint'),
              style: TextStyle(fontSize: 12, color: Palette.textDim),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < opts.length; i++)
              _fateOption(opts[i], i, picked),
          ],
        ],
      ),
    );
  }

  Widget _fateOption(Map<String, Object?> opt, int i, int picked) {
    final on = picked == i;
    final all = fateOptionSum(opt, withLuck: true);
    final noLuck = fateOptionSum(opt, withLuck: false);
    return Container(
      key: Key('attr_fate_opt_$i'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: on ? Palette.goldSoft : Palette.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: on ? Palette.gold : Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('第 ${i + 1} 组',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (on) ...<Widget>[
                const SizedBox(width: 6),
                Text('已选定',
                    style: TextStyle(fontSize: 11, color: Palette.goldStr)),
              ],
              const Spacer(),
              Text(
                '总 $all（不含幸运 $noLuck）',
                key: Key('attr_fate_sum_$i'),
                style: TextStyle(fontSize: 11.5, color: Palette.textDim),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final k in allAttrKeys)
                Text(
                  '${attrAbbr(k)} ${jsStr(opt[k] ?? '')}',
                  key: Key('attr_fate_${i}_$k'),
                  style: TextStyle(fontSize: 11, color: Palette.text),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: Key('attr_fate_pick_$i'),
            onPressed: on ? null : () => _pickFate(i),
            child: on
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.check, size: 16),
                      const SizedBox(width: 6),
                      const Text('就用这一组'),
                    ],
                  )
                : const Text('选这组'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final check = checkAttributes(
      widget.draft,
      pointBuy: _pointBuy,
      includeLuck: _includeLuck,
    );
    final keys = <String>[
      ...coreAttrKeys,
      if (_pointBuy && _includeLuck) 'luck',
      if (_fate) 'luck', // 天命是 9 项完整属性，幸运也要显示（只读）
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        SectionCard(
          title: '分配方式',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ★ P8 修复「分配方式文字显示不全」：
              //   412dp 上三段各约 118dp，原先每段还有一个 15px 图标 +
              //   Material 默认的水平内边距，四个汉字被挤成「点数分…」。
              //   处理：**去掉图标**（信息由文案本身承担，图标是装饰性的）
              //   + 显式收窄 padding + 字号降到 12，给文字留足宽度。
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'pointbuy',
                    label: Text(
                      '点数分配',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment<String>(
                    value: 'random',
                    label: Text(
                      '随机掷骰',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment<String>(
                    value: 'fate',
                    label: Text(
                      '天命 N 选一',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: <String>{_mode},
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                    EdgeInsets.symmetric(horizontal: 3, vertical: 7),
                  ),
                  textStyle: const WidgetStatePropertyAll<TextStyle>(
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
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
                  // ★ 只改模式，不清 fate 数据：切走再切回，掷出的 N 组仍在
                  //   （纯数据挂在卡上，不在 widget state 里）。
                  widget.draft.raw['attributeMode'] = v.first;
                  widget.onChanged();
                },
              ),
              if (_pointBuy) ...<Widget>[
                const SizedBox(height: 10),
                // 注意：这里刻意不用 SwitchListTile —— ListTile 系列要求最近的
                // Material 祖先提供背景，套在 SectionCard（带背景色的 DecoratedBox）
                // 里会触发 debug 断言「ink splashes may be invisible」。
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '幸运参与购点',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Palette.textDim,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _includeLuck
                                ? '上限 ${pointBuyCap(includeLuck: true)}（9 项合计）'
                                : '上限 ${pointBuyCap(includeLuck: false)}（8 项合计）',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Palette.textMute,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      key: const Key('switch_include_luck'),
                      value: _includeLuck,
                      onChanged: (v) {
                        widget.draft.raw['pbIncludeLuck'] = v;
                        widget.draft.raw['pbCap'] = pointBuyCap(includeLuck: v);
                        widget.onChanged();
                      },
                    ),
                  ],
                ),
              ] else if (_fate) ...<Widget>[
                const SizedBox(height: 12),
                _fateBlock(),
              ] else ...<Widget>[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('btn_roll_attrs'),
                  onPressed: _roll,
                  icon: const Icon(Icons.casino, size: 18),
                  label: const Text('掷骰生成属性'),
                ),
                const SizedBox(height: 6),
                Text(
                  '力量/体质/敏捷/外貌/意志/幸运 = 3D6×5；体型/智力/教育 = (2D6+6)×5',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '属性',
          child: Column(
            children: <Widget>[
              for (final k in keys) ...<Widget>[
                _AttrRow(
                  attrKey: k,
                  controller: _ctl[k]!,
                  error: check.errors[k],
                  readOnly: !_pointBuy,
                  onChanged: (v) => _write(k, v),
                  onBump: _pointBuy ? (d) => _bump(k, d) : null,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        _SumBar(check: check, pointBuy: _pointBuy),
        const SizedBox(height: 12),
        // ★ P10（用户第 9 项）：教育进步检定放在属性页最下方 ——
        //   它读的是属性，改的也是「生效教育」，放在这里玩家一眼能对上。
        _eduBlock(),
      ],
    );
  }
}

class _AttrRow extends StatelessWidget {
   const _AttrRow({
    required this.attrKey,
    required this.controller,
    required this.onChanged,
    this.error,
    this.readOnly = false,
    this.onBump,
  });

  final String attrKey;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? error;
  final bool readOnly;
  final void Function(int delta)? onBump;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 74,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    attrName(attrKey),
                    style: TextStyle(fontSize: 13, color: Palette.text),
                  ),
                  Text(
                    attrAbbr(attrKey),
                    style: TextStyle(
                      fontSize: 10,
                      color: Palette.textMute,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            if (onBump != null)
              _MiniBtn(
                icon: Icons.remove,
                onTap: () => onBump!(-genStep),
                semantics: '${attrName(attrKey)}减5',
              ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                key: Key('attr_$attrKey'),
                controller: controller,
                readOnly: readOnly,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: readOnly ? Palette.textDim : Palette.text,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  hintText: '—',
                  errorText: error == null ? null : '',
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
                onChanged: onChanged,
              ),
            ),
            if (onBump != null) const SizedBox(width: 6),
            if (onBump != null)
              _MiniBtn(
                icon: Icons.add,
                onTap: () => onBump!(genStep),
                semantics: '${attrName(attrKey)}加5',
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 74, top: 3),
            child: Text(
              error!,
              style: TextStyle(fontSize: 11, color: Palette.danger),
            ),
          ),
      ],
    );
  }
}

class _MiniBtn extends StatelessWidget {
   const _MiniBtn({required this.icon, required this.onTap, this.semantics});

  final IconData icon;
  final VoidCallback onTap;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Palette.surface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Palette.border),
          ),
          child: Icon(icon, size: 15, color: Palette.textDim),
        ),
      ),
    );
  }
}

class _SumBar extends StatelessWidget {
   const _SumBar({required this.check, required this.pointBuy});

  final AttrCheck check;
  final bool pointBuy;

  @override
  Widget build(BuildContext context) {
    final over = check.over;
    final color = over
        ? Palette.danger
        : (check.remain == 0 ? Palette.success : Palette.gold);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: over ? Palette.danger.withValues(alpha: 0.5) : Palette.border,
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '合计 ${check.sum}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          if (pointBuy)
            Text(
              '上限 ${check.cap}',
              style: TextStyle(fontSize: 12, color: Palette.textMute),
            ),
          const Spacer(),
          Text(
            pointBuy
                ? (over ? '超出 ${check.sum - check.cap}' : '剩余 ${check.remain}')
                : '已填 ${check.filled}/8',
            key: const Key('attr_sum_hint'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
