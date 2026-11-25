// ============================================================
// rule_pick_page.dart — 「先选规则系统」前置页（四个入口共用）
//
// 用户原话（需求 5）：
//   首页「AI车卡」「一键出卡」「跑团房间」也要先选规则系统，
//   也就是四个入口逻辑一样 —— 先到选择规则系统，再进后续流程。
//
// 所以本页是**唯一**的规则入口：
//   跑团房间 / AI 车卡 / 一键出卡 / 按流程车卡
//   四条路都先到这里，选完再进对应页面（见 [RulePickTarget]）。
//
// 三条设计约束（照 `rule_registry.dart` 的既有约定）：
//   · **不硬编码三条规则**：渲染 `RuleRegistry.all`，以后注册表里加一条，
//     这里自动多一张卡（卡面图在 `Art.ruleCardFor` 里登记，未登记回退通用底纹）。
//   · `available == false` 的规则**如实灰掉、不可点**，并标「未开放」——
//     绝不做出一个点下去没反应的假入口。
//   · 卡面 2:1（`Art.ruleCardFor` 的图规格）。顶部头图用 `SectionBanner`
//     （内部 `BannerSlot` 钳高），不用裸 `AspectRatio` —— 平板 1524dp 上
//     6:1 的裸比例会变成一条 254px 的巨幅装饰。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/rule_registry.dart' show RuleMeta, RuleRegistry;
import '../../repo/repo_scope.dart' show AppRoutes;
import '../../theme.dart';
import '../ai_create_page.dart';
import '../art.dart';
import '../random_create_page.dart';
import '../responsive.dart';
import '../widgets.dart';
import 'create_flow_page.dart';

/// 选完规则之后去哪。
///
/// 用枚举而不是字符串：新增目标时编译期就能发现漏处理的 switch。
enum RulePickTarget {
  /// 跑团房间入口（`/room`）
  room,

  /// ✨ AI 车卡
  ai,

  /// 🎲 一键出卡（纯本地随机 5 张）
  random,

  /// 按流程车卡（8 步向导，规则步已被本页取代）
  wizard,
}

/// 选择页标题当前去向，用于副标题文案。
extension RulePickTargetText on RulePickTarget {
  String get label => switch (this) {
    RulePickTarget.room => '跑团房间',
    RulePickTarget.ai => 'AI 车卡',
    RulePickTarget.random => '一键出卡',
    RulePickTarget.wizard => '按流程车卡',
  };
}

class RulePickPage extends StatelessWidget {
  const RulePickPage({super.key, required this.next, this.rules});

  /// 选完规则后要去哪
  final RulePickTarget next;

  /// 测试注入用：null → [RuleRegistry.all]。
  ///
  /// 留这个口子是为了自证「遍历注册表、不是写死三条」——
  /// 用例可以塞一条假规则进来，断言它同样被渲染成一张卡。
  final List<RuleMeta>? rules;

  /// 选中一条**已开放**规则后的跳转。
  void _pick(BuildContext context, RuleMeta rule) {
    final NavigatorState nav = Navigator.of(context);
    switch (next) {
      case RulePickTarget.room:
        // 房间入口是命名路由（深链 `/room/<code>` 也走它），保持原样。
        nav.pushNamed(AppRoutes.room);
      case RulePickTarget.ai:
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => AiCreatePage(initialRuleId: rule.id),
          ),
        );
      case RulePickTarget.random:
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => RandomCreatePage(initialRuleId: rule.id),
          ),
        );
      case RulePickTarget.wizard:
        // 规则已经在**这一页**选过了，向导不再让玩家选第二次：
        // 与 AI / 随机卡「继续完善」同一条路径（skipRules + 规则写进 draft）。
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                CreateFlowPage(initialRuleId: rule.id, skipRules: true),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    final List<RuleMeta> list = rules ?? RuleRegistry.all;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            '选择规则系统',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ContentFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: <Widget>[
                SectionBanner(
                  title: '规则系统',
                  art: Art.sectionAdventureFor(Palette.brightness),
                ),
                const SizedBox(height: 14),
                // ★ 遍历注册表：以后加规则不用改本页。
                for (final RuleMeta r in list) ...<Widget>[
                  RulePickCard(
                    key: Key('rule_pick_${r.id}'),
                    rule: r,
                    brightness: Palette.brightness,
                    onTap: r.available ? () => _pick(context, r) : null,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一张规则卡（2:1 底图 + 文字压层）。
///
/// 单独抽成公开组件：规则选择页与测试共用同一份渲染逻辑，
/// 「加一条规则能渲染出来」不靠肉眼，靠这个组件被喂了什么。
///
/// ★ P11（本轮）：素材重出 —— 六张 `g_rules/*_2x1.webp` **图内不再有金边 /
///   四角星**，主体在右 55%、左侧 40% 留空。于是：
///   · P10 那套「把图放大 1.753 倍裁掉图内金框」的补丁（`_innerCrops` /
///     `ClipRect` + `OverflowBox`）**整段删除** —— 它是给旧图打的补丁，
///     留到现在只会白裁画面。App 自己的圆角边框就是唯一边框。
///   · 压层**跟随皮肤**：亮色下压黑就是用户说的「灰蒙蒙」（需求 5），
///     改成亮色白、暗色黑的侧渐变，都只压左侧、右侧透明，原图直接可见。
///   · 可读性靠文字 [Shadow] 兜底，不靠压暗。
///
/// ★ P10 需求 6（保留）：可选项**不套整体 `Opacity`**（那是"不可选"的视觉
///   语言）；未开放项 = 灰度 + 0.45 + 「未开放」标签，一眼能分开。
class RulePickCard extends StatelessWidget {
  const RulePickCard({
    super.key,
    required this.rule,
    required this.brightness,
    this.onTap,
  });

  /// 未开放项的灰度矩阵（Rec.709 亮度权重，人眼观感最接近"黑白"）。
  static const ColorFilter _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  final RuleMeta rule;
  final Brightness brightness;

  /// null = 不可选（未开放）。**不放假入口**：此时 InkWell 的 onTap 也是 null。
  final VoidCallback? onTap;

  /// 文字光晕：浅底白晕、深底黑晕 —— 不压暗也能保证对比度。
  List<Shadow> _halo() => <Shadow>[
    Shadow(
      color: (brightness == Brightness.dark ? Colors.black : Colors.white)
          .withValues(alpha: 0.85),
      blurRadius: 5,
    ),
  ];

  /// 文字压层的渐变（跟随皮肤，右侧完全透明）。
  LinearGradient _scrim() {
    final bool dark = brightness == Brightness.dark;
    final Color veil = dark ? Colors.black : Colors.white;
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[
        veil.withValues(alpha: dark ? 0.55 : 0.45),
        veil.withValues(alpha: dark ? 0.22 : 0.18),
        veil.withValues(alpha: 0),
      ],
      stops: const <double>[0, 0.36, 0.8],
    );
  }

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    final bool usable = rule.available && onTap != null;
    final bool dark = brightness == Brightness.dark;
    // 小徽标的底：暗色压黑、亮色铺白 —— 否则亮色卡上会出现一块突兀的黑。
    final Color chipBg = dark
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.75);

    final Widget card = AspectRatio(
      aspectRatio: 2, // 与素材规格一致（g_rules/*_2x1）
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: usable ? onTap : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // 原图直铺（2:1 素材铺 2:1 卡面），不放大、不裁切。
                ArtImage(
                  Art.ruleCardFor(rule.id, brightness),
                  fit: BoxFit.cover,
                ),
                // 只压左侧：文字都在左下角；右半张留白给插画。
                DecoratedBox(decoration: BoxDecoration(gradient: _scrim())),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              rule.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                fontFamily: serifFamily,
                                color: Palette.goldStr,
                                letterSpacing: 0.8,
                                shadows: _halo(),
                              ),
                            ),
                          ),
                          if (!rule.available)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Palette.borderStr),
                              ),
                              child: Text(
                                '未开放',
                                key: Key('rule_unavailable_${rule.id}'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Palette.textDim,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Pill(
                            text: rule.shortName,
                            color: Palette.goldStr,
                            background: chipBg,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rule.rulebook,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Palette.textDim,
                                shadows: _halo(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // ★ 可选项**不套 Opacity**：满格颜色是"可选"的视觉语言。
    if (usable) return card;
    // 未开放：灰度 + 0.45 + 右上「未开放」标签（三件事叠加，绝不会和可选混淆）。
    return Opacity(
      opacity: 0.45,
      child: ColorFiltered(colorFilter: _grayscale, child: card),
    );
  }
}
