// ============================================================
// roster_page.dart — 角色名册（P8 从首页拆出来的二级页）
//
// 为什么要拆：首页原先直接铺「已保存的角色卡」+「英灵殿」两个 2 列网格，
// 卡片一多就把四个入口挤出首屏（用户原话「首页太乱了」）。现在首页只留
// 一个「角色档案」入口，卡片全部在这里看。
//
// 两条硬约束（老测试口径，改这里之前先读）：
//   · 每张卡必须有 `card_rule_badge_<id>`（单一真源 RuleRegistry，
//     test/p7_rule_registry_test.dart 按名依赖）；
//   · 已撕卡只能出现在「英灵殿」块，且整行偏灰（撕卡判定在 repo 层，
//     这里只按传入的两个列表分区展示）。
//
// ★ 一行一张（而不是首页那套 2 列网格）：HP / SAN / MP 三组数字塞进
//   ~150px 的窄卡会溢出边框（P8 用户反馈），改成整行长条 + `Wrap` 排列，
//   窄屏最多换行、永远不会溢出。
//
// ★ P10 需求 2（用户原话）：「首页点已保存的角色卡后就只显示已保存的角色卡，
//   不要显示英灵殿；英灵殿也按照此逻辑」。所以本页接收 [RosterScope]：
//   只渲染对应那**一块**，另一块的标题 / 列表 / 空态**压根不构建**
//   （不是 `Visibility` 隐藏 —— 老用例用 `findsNothing` 守这条）。
//   `/roster` 命名路由不带参数时仍是 `all`（深链行为不变）。
// ============================================================

import 'package:flutter/material.dart';

import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../domain/rule_registry.dart' show RuleRegistry;
import '../repo/repo_scope.dart';
import '../theme.dart';
import 'art.dart';
import 'card_view.dart';
import 'responsive.dart';
import 'widgets.dart';
import 'widgets/avatar_picker.dart';

/// 名册要显示哪一块（P10 需求 2）。
///
/// 首页两张入口图各自带一个作用域：「已保存的角色卡」→ [saved]，
/// 「英灵殿」→ [fallen]；`/roster` 深链不带参数 → [all]（两块都看）。
enum RosterScope {
  /// 两块都显示（深链 / 老入口的默认行为）
  all,

  /// 只显示「已保存的角色卡」
  saved,

  /// 只显示「英灵殿」
  fallen,
}

class RosterPage extends StatelessWidget {
  const RosterPage({super.key, this.scope});

  /// 路由名。
  ///
  /// 放在页面里而不是 `AppRoutes`：`repo_scope.dart` 不属于本批改动范围，
  /// 新路由的常量跟着页面走，一处改完全生效。
  static const String route = '/roster';

  /// 显式作用域；null = 交给路由参数（[route] 的 `arguments`），都没有则 [RosterScope.all]。
  final RosterScope? scope;

  /// 生效作用域：构造参数 > 路由 arguments > [RosterScope.all]。
  ///
  /// 为什么允许路由参数：首页两个入口共用 `/roster` 这一条命名路由
  /// （`app.dart` 不在本批可改范围），只能把作用域顺着 `arguments` 带过去。
  RosterScope _effectiveScope(BuildContext context) {
    final RosterScope? explicit = scope;
    if (explicit != null) return explicit;
    final Object? args = ModalRoute.of(context)?.settings.arguments;
    return args is RosterScope ? args : RosterScope.all;
  }

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    final repo = RepoScope.of(context);
    final alive = repo.alive;
    final fallen = repo.fallen;
    final RosterScope view = _effectiveScope(context);
    // 只建对应的那一块 —— 另一块连标题都不出现（用例用 findsNothing 守）。
    final bool showSaved = view != RosterScope.fallen;
    final bool showFallen = view != RosterScope.saved;
    final String hint = switch (view) {
      RosterScope.all => '已保存 ${alive.length} 位调查员 · ${fallen.length} 位长眠者',
      RosterScope.saved => '${alive.length} 位调查员',
      RosterScope.fallen => '${fallen.length} 位长眠者',
    };

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            '角色档案',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: SafeArea(
          top: false,
          // 平板/横屏：限宽居中（手机不受影响，≤760 时 ContentFrame 是透明的）
          child: ContentFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              children: <Widget>[
                SectionBanner(
                  title: '角色档案',
                  hint: hint,
                  art: Art.sectionArchiveFor(Palette.brightness),
                ),
                const SizedBox(height: 4),

                // ---------- 已保存的角色卡 ----------
                if (showSaved) ...<Widget>[
                  SectionTitle(
                    title: '已保存的角色卡',
                    count: alive.length,
                    accent: Palette.gold,
                  ),
                  const SizedBox(height: 10),
                  if (alive.isEmpty)
                    EmptyState(
                      emoji: '📜',
                      art: Art.emptyCards,
                      title: '还没有角色卡，从上方「按流程车卡」开始',
                      hint: '也可以先把旧版导出的 JSON 导进来',
                    )
                  else
                    for (final c in alive) ...<Widget>[
                      _RosterCard(card: c),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 12),
                ],

                // ---------- 英灵殿 ----------
                if (showFallen) ...<Widget>[
                  SectionTitle(
                    title: '英灵殿',
                    count: fallen.length,
                    accent: Palette.danger,
                  ),
                  const SizedBox(height: 10),
                  if (fallen.isEmpty)
                    EmptyState(
                      emoji: '🕯',
                      art: Art.emptyValhalla,
                      title: '还没有英雄长眠于此',
                    )
                  else
                    for (final c in fallen) ...<Widget>[
                      _RosterCard(card: c, ripped: true),
                      const SizedBox(height: 10),
                    ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行一张的角色卡：名字 + 规则徽标 + 职业·年龄·性别 + HP/SAN/MP + 更新时间
class _RosterCard extends StatelessWidget {
  const _RosterCard({required this.card, this.ripped = false});

  final Character card;
  final bool ripped;

  static String _updatedAt(Character c) {
    final ms = jsNum(c.raw['updatedAt']);
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    final name = card.characterName.isEmpty ? '无名调查员' : card.characterName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('roster_card_${card.id}'),
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.card(card.id)),
        child: Ink(
          decoration: BoxDecoration(
            color: ripped
                ? Palette.surface.withValues(alpha: 0.72)
                : Palette.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: ripped
                  ? Palette.danger.withValues(alpha: 0.28)
                  : Palette.border,
            ),
            // 卡面底纹（两套皮肤）：压得很淡，只做质感不做主体
            image: artDecoration(
              Art.cardFaceFor(Palette.brightness),
              fit: BoxFit.cover,
              opacity: Palette.isDark ? 0.34 : 0.28,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // 头像缩略图（P10）：没有头像时退化成首字圆点，
                  // 尺寸 / 位置与外面一圈边框都会跟着走，不挤名字。
                  AvatarThumb(
                    key: Key('roster_avatar_${card.id}'),
                    relPath: avatarImageRel(card),
                    name: name,
                    size: 34,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        fontFamily: serifFamily,
                        color: ripped ? Palette.textDim : Palette.text,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (ripped)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: RippedBadge(),
                    ),
                  Icon(Icons.chevron_right, size: 18, color: Palette.textMute),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  // ★ P7-D：卡列表规则徽标（单一真源 RuleRegistry）。
                  //   Key 被 test/p7_rule_registry_test.dart 按名依赖，不能动。
                  Container(
                    key: Key('card_rule_badge_${card.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Palette.goldSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      RuleRegistry.shortNameOf(card.ruleSystemId),
                      style: TextStyle(fontSize: 10, color: Palette.goldStr),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${occupationLabel(card)} · ${ageLabel(card)} · '
                      '${genderLabel(card)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Wrap 而不是 Row：窄屏（320px）上三组数字会自动换行，
              // 不会像旧网格卡那样顶出卡片边框。
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _StatChip(
                    label: 'HP',
                    value: hpLabel(card),
                    color: Palette.danger,
                  ),
                  _StatChip(
                    label: 'SAN',
                    value: sanLabel(card),
                    color: Palette.arcane,
                  ),
                  _StatChip(
                    label: 'MP',
                    value: mpLabel(card),
                    color: Palette.teal,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '更新于 ${_updatedAt(card)}',
                style: TextStyle(fontSize: 10.5, color: Palette.textMute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Palette.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textDim,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
