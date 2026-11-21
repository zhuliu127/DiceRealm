// ============================================================
// responsive.dart — 断点、内容限宽、响应式列数
//
// 背景：用户自用两台设备
//   · 手机   荣耀 Magic9 标准版  2664×1236   dpr≈3.0 → 逻辑 ≈ 412×888（竖屏）
//   · 平板   荣耀平板 GT2 Pro    3048×2032   dpr≈2.0 → 逻辑 ≈ 1524×1016（横屏）/ 1016×1524（竖屏）
//
// 手机上 412dp 比常见的 360 略宽，现有单列布局是合适的；真正的麻烦在平板：
// 内容按手机那套排版铺满 1524dp，会得到「一行字横跨整个屏幕」「6:1 装饰条
// 变成 254px 高的巨幅」这种明显不对的效果。所以这里的做法不是给平板写
// 第二套页面，而是：
//   ① **限宽**：阅读型内容（首页 / 名册 / 向导 / 设置 / AI 页）最大 760dp 居中；
//   ② **限高**：装饰条这类按宽度等比放大的图，单独钳一个上限；
//   ③ **变列**：卡片列表在宽屏上多列并排，而不是拉长单列。
//
// 为什么阈值取 600 / 840：
//   沿用 Material 3 的 compact / medium / expanded 三档，和 Flutter 官方
//   示例、以及后续可能的折叠屏展开态一致，不自创一套。
// ============================================================

import 'package:flutter/material.dart';

/// 断点阈值（逻辑像素）。
class Bp {
  const Bp._();

  /// 小于此值 = 手机竖屏（compact）
  static const double compactMax = 600;

  /// 此值到 [compactMax] 之间 = 小平板 / 折叠展开（medium）
  static const double mediumMax = 840;

  /// 阅读型内容的最大宽度。超过就居中留白，不再拉满。
  ///
  /// 760 是「一行中文 40~50 字」的上限附近 —— 再宽，眼睛回行会丢行。
  static const double contentMax = 760;

  static bool isCompact(double w) => w < compactMax;
  static bool isMedium(double w) => w >= compactMax && w < mediumMax;
  static bool isExpanded(double w) => w >= mediumMax;
}

/// 按窗口宽度取一个值（三档）。
T byWidth<T>(
  double width, {
  required T compact,
  T? medium,
  T? expanded,
}) {
  if (width >= Bp.mediumMax) return expanded ?? medium ?? compact;
  if (width >= Bp.compactMax) return medium ?? compact;
  return compact;
}

/// 响应式列数：手机 1 列，小平板 2 列，平板 3 列（可由调用方覆盖）。
int columnsFor(
  double width, {
  int compact = 1,
  int medium = 2,
  int expanded = 3,
}) =>
    byWidth<int>(width, compact: compact, medium: medium, expanded: expanded);

/// 把阅读型内容限制在 [maxWidth] 内并居中。
///
/// 手机（≤600）上它完全不生效 —— 不会给手机引入任何额外留白。
class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.child,
    this.maxWidth = Bp.contentMax,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        if (!c.maxWidth.isFinite || c.maxWidth <= maxWidth) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

/// 装饰条这类「按宽度等比放大」的图，钳一个高度上限。
///
/// 为什么需要：6:1 的分区头在 412dp 上是 69px（正好），到 1524dp 上就是
/// 254px —— 一条装饰占掉四分之一屏。上限取 [maxHeight]，超出部分让
/// `BoxFit.cover` 从两端裁掉（装饰条两端本来就是留白，裁掉不心疼）。
class BannerSlot extends StatelessWidget {
  const BannerSlot({
    super.key,
    required this.aspectRatio,
    required this.child,
    this.maxHeight = 96,
    this.minHeight = 44,
  });

  final double aspectRatio;
  final Widget child;
  final double maxHeight;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double byAspect =
            c.maxWidth.isFinite ? c.maxWidth / aspectRatio : maxHeight;
        final double h = byAspect.clamp(minHeight, maxHeight);
        return SizedBox(height: h, child: child);
      },
    );
  }
}
