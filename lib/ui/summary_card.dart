// ============================================================
// summary_card.dart — 候选卡预览（随机卡与 AI 卡共用同一套样式）
//
// 对应旧版 `ui/step-start.js#presetCard()`。数据全部来自
// `preset_gen.summaryOf()` 返回的那张 map —— 这里**不碰角色数据**，
// 只做展示，所以加字段不会影响卡片契约。
// ============================================================

import 'package:flutter/material.dart';

import '../domain/js_compat.dart';
import '../domain/rule_registry.dart' show RuleRegistry;
import '../theme.dart';
import 'art.dart';
import 'parchment.dart';
import 'widgets.dart';

const List<String> _attrOrder = <String>[
  'str',
  'con',
  'siz',
  'dex',
  'app',
  'int',
  'pow',
  'edu',
  'luck',
];

const Map<String, String> _attrAbbr = <String, String>{
  'str': 'STR',
  'con': 'CON',
  'siz': 'SIZ',
  'dex': 'DEX',
  'app': 'APP',
  'int': 'INT',
  'pow': 'POW',
  'edu': 'EDU',
  'luck': 'LUK',
};

/// 候选卡底纹的「顶部淡出」遮罩（喂给 [ShaderMask] 的 dstIn 源）。
///
/// ★ P11 需求 3：用户在「一键出卡」截图里看到候选卡**最上方有两条杠**，
///   和默认头像 / 姓名 / 规则徽标交叉。
///   根因不是 App 画的 Divider，而是**卡面底纹图自己**：`b_card/b1_card_face_3x4`
///   是 3:4 的竖图，图上画了一圈双线金框 —— 像素实测两条横线在 0.2% / 1.9%
///   图高处，四角花饰到 ~9%。它用 `BoxFit.cover` 铺进偏高的候选卡时（手机
///   宽度下按高度铺满、整幅可见），这两条线正好落在卡片顶端 1~10px 处，
///   于是从序号块、头像、「朱砚舟」、COC 徽标背后穿过去。
///
/// 修法：底纹在卡片顶部**完全透明**——0 → 4% 全透明（盖住两条金线），
///   4% → 12% 淡入（盖住四角花饰），之后才是纸张纹理。头像 / 姓名 / 徽标
///   那一行背后因此没有任何线条（布局与 Key 一个字都没动）。
///
/// 常量对外公开：验收用例直接读它，避免"看着像"。
const LinearGradient kCardFaceFade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0xFFFFFFFF)],
  stops: <double>[0, 0.04, 0.12],
);

/// 候选卡的纸面底（纯色 + 羊皮纸质感，**零图片**）。见 [kCardFaceFade]。
///
/// ★ P10 第 1 期 A1（用户原话）：「平板视角的一键出卡页，角色信息栏位背景图
///   改成纯色（带羊皮纸纹）的吧，左右各有两道竖线很不好看」。
///
/// 那两道竖线**不是 App 画的**，是旧底纹图 `b_card/b1_card_face_3x4`（3:4 竖图）
/// 自己画的一圈**双线金框**：
///   · 手机：卡片窄高 → `cover` 按高度铺满，左右被裁 → 竖线看不见；
///   · 平板：卡片宽扁 → `cover` 按宽度铺满 → 左右各两道竖线正好留在卡内。
/// 所以这里把底纹图整个换成 [ParchmentSurface]（纯色 + 极轻渐变/纤维/暗角）：
/// 与图片比例彻底无关，宽卡窄卡都不会再出现一条直线，也没有新增资源文件。
///
/// [kCardFaceFade] 与新底纹无关了，但**保留**这层 `dstIn` 遮罩：
///   · 顶部淡出仍然让卡片上沿与页面背景自然衔接（视觉更好）；
///   · 更重要的是它把「底纹不许在头部行画线」这条约束留在**结构**上 ——
///     以后谁再往底纹里塞图（哪怕又带框线），顶部那条横线也穿不出来。
class _CardFaceBackdrop extends StatelessWidget {
  const _CardFaceBackdrop();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect r) => kCardFaceFade.createShader(r),
      child: const ParchmentSurface(seed: 20261110),
    );
  }
}

/// 一张候选卡的预览
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.summary,
    required this.index,
    this.onUseThis,
    this.onContinueEdit,
    this.keySuffix = '',
  });

  /// `preset_gen.summaryOf()` 的结果
  final Map<String, Object?> summary;

  final int index;

  /// ★ P9 需求 6：原来的「√ 用这张，继续完善」拆成两个动作。
  ///
  /// [onUseThis] = 「就用这张」：直接落库并回首页（由页面实现，卡片不管落库）。
  /// [onContinueEdit] = 「继续完善」：进向导逐项改，不落库。
  /// 两个都为 null 时不渲染按钮区（AI 结果页自己排版时曾这样用）。
  final VoidCallback? onUseThis;
  final VoidCallback? onContinueEdit;

  /// 按键后缀：一页多张候选卡时用 `_0` / `_1` 区分。
  /// 为空时键就是 `result_use_this` / `result_continue_edit`（单卡场景）。
  final String keySuffix;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final attrs = asMap(s['attrs']);
    final topSkills = asList(s['topSkills']).map(asMap).toList();

    return Container(
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Palette.gold.withValues(alpha: 0.28)),
      ),
      // 底纹画在自己的层里（而不是 Container.decoration 的 image），
      // 才能给它套顶部淡出 —— 图内那两条金框线不许穿到头部行。
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: _CardFaceBackdrop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ---- 头部：序号 + 头像 + 姓名 / 彩蛋角标 + 一行元信息 ----
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Palette.surface2,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Palette.border),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(fontSize: 11, color: Palette.textDim),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Avatar(summary: s),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  jsStr(s['name']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: serifFamily,
                                    color: Palette.text,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (jsTruthy(s['egg'])) ...<Widget>[
                                const SizedBox(width: 6),
                                _Badge(
                                  text:
                                      '${s['egg']} ${jsStr(s['eggKind']) == 'friend' ? '跑团成员' : '彩蛋'}',
                                  color: jsStr(s['eggKind']) == 'friend'
                                      ? Palette.teal
                                      : Palette.gold,
                                ),
                              ],
                              // ★ P7-D：规则徽标，让不同规则的卡在卡面就能区分。
                              const SizedBox(width: 6),
                              _Badge(
                                key: const Key('summary_rule_badge'),
                                text: RuleRegistry.shortNameOf(
                                  jsStr(s['ruleSystemId']),
                                ),
                                color: Palette.arcane,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${s['gender']} · ${s['age']} 岁 · ${s['era']} · ${s['residence']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Palette.textMute,
                            ),
                          ),
                          Text(
                            '籍贯 ${jsTruthy(s['birthplace']) ? s['birthplace'] : '—'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Palette.textMute,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: <Widget>[
                              _Badge(
                                text: jsStr(s['occupation']),
                                color: Palette.gold,
                              ),
                              if (jsTruthy(s['world']))
                                _Badge(
                                  text: jsStr(s['world']),
                                  color: Palette.arcane,
                                ),
                              _Badge(
                                text: '信用 ${s['credit']}',
                                color: Palette.textDim,
                              ),
                              _Badge(
                                text: 'HP ${s['hp']}',
                                color: Palette.teal,
                              ),
                              _Badge(
                                text: 'SAN 上限 ${s['san']}',
                                color: Palette.arcane,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                HairLine(),
                const SizedBox(height: 10),

                // ---- 属性 ----
                _label('属性'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final k in _attrOrder)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Palette.surface2,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Palette.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              _attrAbbr[k] ?? k.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                color: Palette.textMute,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              jsStr(attrs[k]),
                              style: TextStyle(
                                fontSize: 12,
                                color: Palette.textDim,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // ---- 派生与点数 ----
                _label('派生与点数'),
                Text(
                  'HP ${s['hp']}　MP ${s['mp']}　SAN ${s['san']}　MOV ${s['mov']}　'
                  '体格 ${s['build']}　伤害加值 ${s['db']}　幸运 ${s['luck']}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                    height: 1.8,
                  ),
                ),
                Text(
                  '职业点 ${s['occUsed']}/${s['occTotal']}（信用评级已占 ${s['credit']}）　'
                  '兴趣点 ${s['intUsed']}/${s['intTotal']}　本职技能 ${s['occtSkills']} 项',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                    height: 1.8,
                  ),
                ),
                if (jsNum(s['eduChecks']) > 0)
                  Text(
                    '教育进步检定 ${s['eduChecks']} 次（教育 +${s['eduBonus']}）',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Palette.textMute,
                      height: 1.8,
                    ),
                  ),

                // ---- 主要技能 ----
                if (topSkills.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  _label('主要技能'),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: <Widget>[
                      for (final sk in topSkills)
                        _Badge(
                          text: '${sk['name']} ${sk['total']}',
                          color: sk['occ'] == true
                              ? Palette.gold
                              : Palette.textDim,
                        ),
                    ],
                  ),
                ],

                // ---- 背景 ----
                const SizedBox(height: 10),
                _label('背景'),
                Text(
                  '外貌：${s['look']}\n${s['belief']}\n重要之人：${s['people']}\n'
                  '意义非凡之地：${s['place']}\n宝贵之物：${s['treasure']}\n'
                  '特点：${s['traits']}　伤口：${s['wound']}\n心理：${s['phobia']}\n'
                  '经历：${asList(s['history']).isEmpty ? '—' : asList(s['history']).join('；')}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                    height: 1.8,
                  ),
                ),

                // ---- 装备 ----
                const SizedBox(height: 10),
                _label('装备'),
                Text(
                  '武器：${_join(s['weapons'])}　防具：${_join(s['armors'])}　物品：${_join(s['items'])}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                    height: 1.8,
                  ),
                ),

                if (onUseThis != null || onContinueEdit != null) ...<Widget>[
                  const SizedBox(height: 11),
                  Row(
                    children: <Widget>[
                      if (onUseThis != null)
                        Expanded(
                          child: FilledButton(
                            key: Key('result_use_this$keySuffix'),
                            onPressed: onUseThis,
                            child: const Text('就用这张'),
                          ),
                        ),
                      if (onUseThis != null && onContinueEdit != null)
                        const SizedBox(width: 10),
                      if (onContinueEdit != null)
                        Expanded(
                          child: OutlinedButton(
                            key: Key('result_continue_edit$keySuffix'),
                            onPressed: onContinueEdit,
                            child: const Text('继续完善'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _join(Object? v) {
    final list = asList(v).map(jsStr).where((x) => x.isNotEmpty).toList();
    return list.isEmpty ? '—' : list.join('、');
  }

  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: Palette.textMute,
        letterSpacing: 1,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// 头像：自动生成的是 SVG dataURI，Flutter 不认 SVG，所以只画一个占位徽章
class _Avatar extends StatelessWidget {
  const _Avatar({required this.summary});

  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final name = jsStr(summary['name']);
    final ch = name.isEmpty ? '？' : name.characters.first;
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Palette.surface3, Palette.surface2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.gold.withValues(alpha: 0.45)),
      ),
      // 首字在下、美术头像在上：有图就用图，缺图（测试环境）自动退回首字，
      // 两种情况下都不会出现一个空方块。
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: <Widget>[
          Center(
            child: Text(
              ch,
              style: TextStyle(
                fontSize: 18,
                color: Palette.goldStr,
                fontFamily: serifFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ArtImage(Art.avatarDefault, fit: BoxFit.cover),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
