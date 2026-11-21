// ============================================================
// step_assets.dart — 车卡第 4 步：资产与信用评级（旧版 `steps-c.js#assets`）
//
// ⚠️ 这一步**必须排在技能之前**：信用评级占用职业点数，先定信用评级再分技能点，
//   否则职业点算错、`validateCreditRating` 也会误报（旧版注释写得很清楚）。
//
// ⚠️ 旧的坑不许重复：信用评级输入框**只创建一次**（controller 常驻）。
//   早期版本每次 oninput 都重建整个区块 → 焦点丢失、软键盘被收起，
//   而且数字还没输完就被判「超出范围」。现在：非法值只提示、不写模型、不重建。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/character.dart';
import '../../../domain/engine.dart';
import '../../../domain/js_compat.dart';
import '../../../domain/occupation.dart';
import '../../../theme.dart';
import '../../card_edit/assets_logic.dart';
import '../../widgets.dart';
import '../../notice.dart';

class StepAssets extends StatefulWidget {
  const StepAssets({super.key, required this.draft, required this.onChanged});

  final Character draft;
  final VoidCallback onChanged;

  @override
  State<StepAssets> createState() => _StepAssetsState();
}

class _StepAssetsState extends State<StepAssets> {
  late final TextEditingController _credit;
  late final TextEditingController _cash;
  late final TextEditingController _assetDesc;
  late final Map<String, TextEditingController> _cats;
  String? _creditError;
  String? _creditHint;

  Character get _c => widget.draft;

  @override
  void initState() {
    super.initState();
    // 从技能页改过 credit 点时，回到这里跟着变（只在资产还是 0 时采纳）
    adoptCreditFromSkill(_c);
    syncAssetDerived(_c);
    _credit = TextEditingController(
      text: jsNum(_c.assets['creditRating']) == 0
          ? ''
          : '${jsNum(_c.assets['creditRating'])}',
    );
    _cash = TextEditingController(
      text: jsNum(_c.assets['cash']) == 0 ? '' : '${jsNum(_c.assets['cash'])}',
    );
    _assetDesc = TextEditingController(
      text: jsStr(_c.assets['assetsDescription']),
    );
    _cats = <String, TextEditingController>{
      for (final cat in assetCategories)
        cat: TextEditingController(text: assetDescOf(_c, cat)),
    };
  }

  @override
  void dispose() {
    _credit.dispose();
    _cash.dispose();
    _assetDesc.dispose();
    for (final c in _cats.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onCreditChanged(String raw) {
    final r = commitCreditRating(_c, raw);
    setState(() {
      _creditError = r.error;
      _creditHint = r.hint;
    });
    if (r.written) {
      recalc(_c);
      widget.onChanged();
    }
  }

  void _setCredit(int v) {
    setCreditRating(_c, v);
    recalc(_c);
    _credit.text = '$v';
    setState(() {
      _creditError = null;
      _creditHint = null;
    });
    widget.onChanged();
    ScaffoldMessenger.of(context)
        .showSlot(SnackBar(content: Text('信用评级已设为 $v')));
  }

  void _adoptSuggested() {
    final s = suggestedAmountsOf(_c);
    if (s == null) return;
    adoptSuggestedAmounts(_c, s);
    _cash.text = '${s.cash}';
    _assetDesc.text = jsStr(_c.assets['assetsDescription']);
    setState(() {});
    widget.onChanged();
    ScaffoldMessenger.of(context)
        .showSlot(const SnackBar(content: Text('已采用建议数值')));
  }

  @override
  Widget build(BuildContext context) {
    final range = creditRange(_c);
    final occ = getOccupationById(_c.occupationId);
    final occPts = occupationPoints(_c);
    final creditPoints = creditPointsOf(_c);
    final otherPoints = jsNum(occPts['used']) - creditPoints;
    final over = jsNum(occPts['used']) > jsNum(occPts['total']);
    final cr = jsNum(_c.assets['creditRating']);
    final level = livingLevelOf(cr);
    final suggested = suggestedAmountsOf(_c);
    final capHint = skillCapHint(_c);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        SectionCard(
          title: '信用评级与生活水平',
          subtitle: '信用评级会占用职业点数 —— 先定它，再去分技能点',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FieldLabel(
                '信用评级 Credit Rating',
                hint: range != null
                    ? '职业「${jsStr(occ?['name'])}」允许 ${range.text}'
                    : '选择职业后确定取值范围',
              ),
              TextField(
                key: const Key('credit_input'),
                controller: _credit,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textInputAction: TextInputAction.done,
                onChanged: _onCreditChanged,
                decoration: InputDecoration(
                  hintText: range != null ? range.text : '0 - 99',
                  errorText: _creditError,
                ),
              ),
              if (_creditHint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _creditHint!,
                    key: const Key('credit_hint'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Palette.textMute,
                    ),
                  ),
                ),
              if (range != null) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    _chip(
                      '职业下限 ${range.min}',
                      'credit_chip_min',
                      () => _setCredit(range.min),
                    ),
                    _chip(
                      '中位 ${range.mid}',
                      'credit_chip_mid',
                      () => _setCredit(range.mid),
                    ),
                    _chip(
                      '职业上限 ${range.max}',
                      'credit_chip_max',
                      () => _setCredit(range.max),
                    ),
                    _chip(
                      '采用建议值 ${range.mid}',
                      'credit_chip_suggest',
                      () => _setCredit(range.mid),
                      on: true,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // ---- 提示与点数预算（旧版 refreshCreditNotice）----
              if (occ == null)
                _notice('尚未选择职业，无法校验信用评级范围。请先回到「基本资料」步骤。', Palette.gold)
              else if (range == null)
                _notice('职业「${jsStr(occ['name'])}」没有规定信用评级范围。', Palette.success)
              else if (cr == 0)
                _notice(
                  '请分配信用评级。「${jsStr(occ['name'])}」允许 ${range.text}。',
                  Palette.gold,
                )
              else if (cr < range.min || cr > range.max)
                _notice(
                  '当前 $cr 超出「${jsStr(occ['name'])}」允许的 ${range.text}，请调整。',
                  Palette.danger,
                )
              else
                _notice(
                  '信用评级 $cr 合法。「${jsStr(occ['name'])}」允许 ${range.text}，本次占用职业点 $creditPoints 点。',
                  Palette.success,
                ),
              const SizedBox(height: 8),
              Text(
                '职业点数：总计 ${jsNum(occPts['total'])}　信用评级占用 $creditPoints'
                '　其它技能占用 $otherPoints　剩余 ${jsNum(occPts['total']) - jsNum(occPts['used'])}'
                '${over ? '（已超额）' : ''}',
                key: const Key('occ_points_budget'),
                style: TextStyle(
                  fontSize: 11.5,
                  color: over ? Palette.danger : Palette.textMute,
                  height: 1.5,
                ),
              ),
              if (capHint.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  capHint,
                  style: TextStyle(
                    fontSize: 11,
                    color: Palette.textMute,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Palette.surface2,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: Palette.border),
                ),
                child: Text(
                  '${jsStr(level['level'])}：${jsStr(level['desc'])}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textDim,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '现金与资产',
          subtitle: '消费水平与货币由信用评级 / 时代自动确定',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        FieldLabel('现金（${jsStr(_c.assets['currency'])}）'),
                        TextField(
                          key: const Key('cash_input'),
                          controller: _cash,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(hintText: '例：500'),
                          onChanged: (v) {
                            if (commitCash(_c, v)) widget.onChanged();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                         FieldLabel('消费水平'),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Palette.surface2,
                            borderRadius: BorderRadius.circular(Radii.sm),
                            border: Border.all(color: Palette.border),
                          ),
                          child: Text(
                            jsStr(_c.assets['spendingLevel']),
                            key: const Key('spending_level'),
                            style: TextStyle(
                              fontSize: 14,
                              color: Palette.textDim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
               FieldLabel('资产描述'),
              TextField(
                key: const Key('asset_desc'),
                controller: _assetDesc,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '例：波士顿公寓一套、1930年福特A型车',
                ),
                onChanged: (v) {
                  _c.assets['assetsDescription'] = v;
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 12),
               FieldLabel('资产分类', hint: '每类一条，留空即删除该类'),
              for (var i = 0; i < assetCategories.length; i++) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    key: Key('asset_cat_$i'),
                    controller: _cats[assetCategories[i]],
                    decoration: InputDecoration(
                      hintText: '${assetCategories[i]}…',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      setAssetDesc(_c, assetCategories[i], v);
                      widget.onChanged();
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        if (suggested != null) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title:
                '参考数值（${jsStr(currencyOf(_c)['era'])} · ${jsStr(currencyOf(_c)['region'])}）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatTile(
                        label: '建议现金',
                        value: '${suggested.currency} ${suggested.cash}',
                        compact: true,
                        color: Palette.gold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatTile(
                        label: '建议其他资产',
                        value: '${suggested.currency} ${suggested.assets}',
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton(
                  key: const Key('btn_adopt_suggest'),
                  onPressed: _adoptSuggested,
                  child: const Text('采用建议现金与资产'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String text, String key, VoidCallback onTap, {bool on = false}) {
    return InkWell(
      key: Key(key),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
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
      ),
    );
  }

  Widget _notice(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        key: const Key('credit_notice'),
        style: TextStyle(fontSize: 11.5, color: color, height: 1.5),
      ),
    );
  }
}
