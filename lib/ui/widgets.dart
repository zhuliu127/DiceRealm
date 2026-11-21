// ============================================================
// widgets.dart — 通用小组件
//
// 只做「这一版反复要用」的几个：分区卡、数值块、空态、细线、撕卡徽标。
// 不做组件库 —— P1 的目标是三条路由能跑通，不是把设计系统搭完。
//
// ★ P8：本文件里所有读取 [Palette] 的组件都在 build 开头显式写了
//   `Theme.of(context);`。原因见下方注释 —— 双皮肤切换时，**const 实例**
//   会被父级 Element 原样复用（widget 完全相同 → 跳过 rebuild），
//   `Palette.xxx` 就永远停在旧皮肤上。`Theme.of` 让组件成为 Theme 的依赖者，
//   皮肤一变，InheritedElement 直接把依赖者标脏，哪怕 widget 是 const 也会重建。
// ============================================================

import 'package:flutter/material.dart';

import '../theme.dart';
import 'art.dart';

/// 皮肤依赖哨兵。
///
/// 用途只有一个：在 build 里建立「我跟着 Theme 走」的依赖，切皮肤时被标脏重建。
/// 不写它，**const 构造出来的** Palette 消费者在切皮肤后不会刷新（P8 真机反馈：
/// 首页「开始冒险」与四个入口切亮色后仍是暗色）。
void dependOnTheme(BuildContext context) => Theme.of(context);

/// 分区横幅（首页「开始冒险 / 角色档案」、规则选择页「规则系统」的标题栏）。
///
/// 源图是 6:1 的圆角描边条（1536×256，图上自带四条金边）。
/// **框与图比例必须严格一致**：只有 6:1 的框配 `BoxFit.cover` 才一像素不裁。
///
/// ★ P10 第 1 期 A2/A3 的根因（用户原话）：
///   「平板视角的首页，『开始冒险』和『角色档案』标题栏的图没有显示完全，
///     上或下边框没显示出来」；规则选择页「规则系统」标题栏同样问题。
///
///   旧实现用 `BannerSlot(aspectRatio: 6, maxHeight: 96)`：
///   · 手机 380dp 宽 → 380/6 = 63px < 96，框就是 6:1 → 不裁（所以竖屏看不出问题）；
///   · 平板（内容限宽 760）→ 760/6 = 126.7px，被钳到 **96** → 框变成 7.9:1，
///     `BoxFit.cover` 按宽度铺满后，上下各裁掉 15px —— 正好是金边所在位置。
///
///   修法两条一起上：
///     ① **钳高不再靠裁图**：高度上限 [maxHeight] 只在上限以下才生效，
///        一旦触顶就改用 `BoxFit.contain`（图完整、两侧留极窄底色），
///        所以「任何时候都不裁上下边框」是结构性的，不依赖具体宽度；
///     ② 上限从 96 放到 [maxHeight]（=168）：内容限宽 760 的页面上
///        126.7px **永远触不到顶** ⇒ 常态就是精确 6:1 + cover（零裁切、零黑边）。
///
///   手机竖屏一并覆盖：63px 依旧是精确 6:1（本批不只看平板）。
///
/// 文字用 App 渲染而不是烧进图里：字号 / 多语言 / 主题色都要跟着 App 走。
class SectionBanner extends StatelessWidget {
  const SectionBanner({
    super.key,
    required this.title,
    required this.art,
    this.hint,
    this.aspectRatio = headerAspect,
  });

  final String title;
  final String? hint;
  final String art;

  /// 图与框的比例（默认 6:1，与 `a3_section_*_6x1` 素材一致）。
  final double aspectRatio;

  /// 头图素材的宽高比（6:1）。
  static const double headerAspect = 6;

  /// 高度上限。内容限宽 760 时 6:1 = 126.7px，触不到这个上限；
  /// 只有把本组件放到更宽的容器里才会触顶（那时改走 contain，不裁图）。
  static const double maxHeight = 168;

  /// 最矮高度（320dp 窄屏 6:1 = 53px，仍在之上；这里只防极端窄容器）。
  static const double minHeight = 44;

  /// 给定容器宽度，算出标题栏高度。
  ///
  /// 公开成静态函数是为了让用例能**直接断言**「框高 = 宽/6」，
  /// 不用去量像素猜比例。
  static double heightFor(double width, {double aspectRatio = headerAspect}) {
    if (!width.isFinite || width <= 0) return minHeight;
    final double exact = width / aspectRatio;
    return exact.clamp(minHeight, maxHeight);
  }

  /// 给定容器宽度，该用哪种 `BoxFit`。
  ///
  /// 只有「框恰好是图的比例」时才用 cover（等于不裁）；一旦被钳高，
  /// 必须 contain —— 否则就是本 bug 的复现。
  static BoxFit fitFor(double width, {double aspectRatio = headerAspect}) {
    if (!width.isFinite || width <= 0) return BoxFit.contain;
    final double exact = width / aspectRatio;
    return exact <= maxHeight && exact >= minHeight
        ? BoxFit.cover
        : BoxFit.contain;
  }

  /// 素材（`a3_section_{adventure,archive}_6x1`）左侧烧了一颗四角星，
  /// 位置约占图宽的 2.4%。
  static const double starInsetRatio = 0.024;

  /// 标题文字左边距。
  ///
  /// ★ P12 真机 bug：原来是**固定 14dp**。星星在图里是按比例定位的，
  ///   横幅一变宽它就线性右移 —— 手机竖屏（约 360dp）时星星在 8.6dp，
  ///   文字从 14dp 起刚好错开；平板横屏 / 手机横屏（760dp+）星星移到
  ///   18dp 以上，文字还在 14dp，于是**星星和第一个字叠在一起**。
  ///   （用户 2026-11-11 在平板横屏、暗色与亮色主题下都复现了。）
  ///
  /// 改成按宽度取 5%（约为星星位置的 2 倍余量），钳在 18..46dp：
  ///   360dp → 18dp > 8.6dp；760dp → 38dp > 18dp；1200dp → 46dp > 28.8dp。
  /// 只挪文字，**不动素材、不动布局结构、不改字号**。
  static double titleInsetFor(double width) {
    if (!width.isFinite || width <= 0) return 18;
    return (width * 0.05).clamp(18.0, 46.0);
  }

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth.isFinite && c.maxWidth > 0
                ? c.maxWidth
                : 380;
            final double h = heightFor(w, aspectRatio: aspectRatio);
            final BoxFit fit = fitFor(w, aspectRatio: aspectRatio);
            return SizedBox(
              height: h,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  // 触顶（contain）时两侧留底色，而不是把金边裁掉。
                  if (fit == BoxFit.contain)
                    Positioned.fill(
                      child: ColoredBox(color: Palette.surface2),
                    ),
                  Positioned.fill(child: ArtImage(art, fit: fit)),
                  Padding(
                    // 左边距随横幅宽度走，保证永远落在素材左侧四角星的右边。
                    padding: EdgeInsets.only(
                      left: titleInsetFor(w),
                      right: 14,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: serifFamily,
                            color: Palette.goldStr,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (hint != null)
                          Expanded(
                            child: Text(
                              hint!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Palette.textMute,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 小节标题：竖条 + 标题 + 数字 + 右侧提示
class SectionTitle extends StatelessWidget {
   const SectionTitle({
    super.key,
    required this.title,
    required this.count,
    required this.accent,
    this.hint,
  });

  final String title;
  final int count;
  final Color accent;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          margin: const EdgeInsets.only(right: 8, bottom: 2),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Palette.text,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 13,
            color: accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (hint != null) ...<Widget>[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Palette.textMute),
            ),
          ),
        ],
      ],
    );
  }
}

/// 分区卡：标题 + 可选副标题 + 内容
class SectionCard extends StatelessWidget {
   const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Container(
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Palette.border),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 3,
                  height: 15,
                  margin: const EdgeInsets.only(right: 8, top: 3),
                  decoration: BoxDecoration(
                    color: Palette.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title!,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Palette.text,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Palette.textMute,
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          if (title != null) const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 数值块：大数字 + 小标签
class StatTile extends StatelessWidget {
   const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    this.color,
    this.compact = false,
  });

  final String label;
  final String value;
  final String? suffix;

  /// 主色；null = 用当前皮肤的正文字色。
  ///
  /// 为什么默认值是 null 而不是 `Palette.text`：双皮肤下 `Palette.text`
  /// 是运行时 getter，不能当编译期常量默认值；写死又会永远停在某一套配色。
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Palette.surface2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: Palette.textMute),
          ),
          const SizedBox(height: 3),
          RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: compact ? 15 : 18,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                if (suffix != null)
                  TextSpan(
                    text: suffix,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Palette.textMute,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态
///
/// 图标优先级：[art]（美术插图）> [icon]（矢量图标）> [emoji]（兜底）。
///
/// ★ P12：新增 [icon] —— emoji 在不同设备上字形/基线都不一样，和本工程的
///   金色线稿风格也不搭；矢量图标走同一字族，线宽与圆角天然一致，
///   而且缩放不糊、零资源体积。[emoji] 仍保留为最后兜底（老调用点零改动，
///   测试环境也不至于空白）。
class EmptyState extends StatelessWidget {
   const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.hint,
    this.art,
    this.icon,
  });

  final String emoji;
  final String title;
  final String? hint;
  final String? art;

  /// 矢量图标（优先于 [emoji]）。建议尺寸语义：40dp，颜色由组件染成主题金。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: Palette.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Palette.border, style: BorderStyle.solid),
      ),
      child: Column(
        children: <Widget>[
          if (art != null)
            SizedBox(
              width: 96,
              height: 96,
              // 空态插画只有暗色一套：亮色皮肤下把不透明度压到 0.5，
              // 让它退成「淡淡的墨线」而不是一块突兀的深色方块。
              child: Opacity(
                opacity: Palette.isDark ? 1 : 0.5,
                child: ArtImage(art!, fit: BoxFit.contain),
              ),
            )
          else if (icon != null)
            Icon(icon, size: 40, color: Palette.goldStr)
          else
            Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 14, color: Palette.textDim)),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Palette.textMute),
              ),
            ),
        ],
      ),
    );
  }
}

/// 撕卡徽标
class RippedBadge extends StatelessWidget {
   const RippedBadge({super.key, this.text = '☠ 已撕卡'});

  final String text;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Palette.dangerSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.danger.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: Palette.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 小标签
class Pill extends StatelessWidget {
   const Pill({super.key, required this.text, this.color, this.background});

  final String text;

  /// null = 用当前皮肤的次要文字色（理由同 [StatTile.color]）
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? Palette.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: color ?? Palette.textDim),
      ),
    );
  }
}

/// 细分割线
class HairLine extends StatelessWidget {
   const HairLine({super.key, this.vertical = 0});

  final double vertical;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: Divider(height: 1, thickness: 1, color: Palette.border),
    );
  }
}

/// 表单字段标签
class FieldLabel extends StatelessWidget {
   const FieldLabel(this.text, {super.key, this.required = false, this.hint});

  final String text;
  final bool required;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Palette.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (required)
            Text(' *', style: TextStyle(fontSize: 13, color: Palette.danger)),
          if (hint != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  hint!,
                  style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 键值行（详情页用）
class KeyValueRow extends StatelessWidget {
   const KeyValueRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;

  /// null = 用当前皮肤的正文字色（理由同 [StatTile.color]）
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Palette.textMute),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 13.5,
                color: valueColor ?? Palette.text,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 可折叠分区卡（背景页的「经历 / 伙伴 / 法术」三块长列表用）
///
/// 为什么需要：这三块每条都要渲染 6-9 个输入框，卡上写下 5 条经历就是 45 个控件，
/// 全展开会把首屏撑得很长、也让「找到了但滚不过去」的测试很脆。
/// 折叠只影响**显示**，不影响数据读写。
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.toggleKey,
    this.initiallyOpen = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// 折叠按钮的 Key（测试用；为空则不挂 key）
  final String? toggleKey;
  final bool initiallyOpen;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: IconButton(
        key: widget.toggleKey == null ? null : Key(widget.toggleKey!),
        tooltip: _open ? '收起' : '展开',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 20,
          color: Palette.textMute,
        ),
        onPressed: () => setState(() => _open = !_open),
      ),
      child: _open ? widget.child : const SizedBox.shrink(),
    );
  }
}
