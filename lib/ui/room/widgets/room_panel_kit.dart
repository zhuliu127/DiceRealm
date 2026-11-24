// ============================================================
// widgets/room_panel_kit.dart — 通用件 + §3.9 跨任务契约（设计 §2.5）
//
// ★ 只画、只发 intent：零权威状态赋值、零规则调用、零权威端引用。
// ★ §3.9 的 6 个 MapStageController 成员在此**定死**，T03 负责给实现，
//   T04 只通过它操作舞台 —— 两个并行任务不互相等。
// ★ T3：SectionBox 自带 Material（用 Card），且内部严禁 ListTile。
// ★ T-43：所有可点元素统一走 RoomTap（≥48dp 热区），禁止裸 IconButton。
// ============================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme.dart' show Palette, Radii;
import '../../art.dart';
import '../room_theme.dart';

// ------------------------------------------------------------
// §3.9 跨任务契约 ①：素材舞台控制面（T01 声明 / T03 实现）
// ------------------------------------------------------------

/// 素材舞台的控制面：KP 工具窄栏（块 3，T04）通过它去操作舞台（块 4，T03）。
///
/// 块 3 与块 4 是**两个独立 widget 子树**，块 3 拿不到块 4 的 State；
/// 用 InheritedWidget 传 Controller 是唯一不破坏「独立子树」的做法。
abstract class MapStageController {
  /// 进入画笔模式（下一笔按 [color]/[width] 落 `map.stroke`）。
  void beginStroke({required String color, required double width});

  /// 进入橡皮模式：手势期间本地删段，**手势末尾**一次 `map.strokes.set`（全量）。
  void beginErase();

  /// 进入标点模式：下一次点击落 `map.mark {x,y,kind,label,revealed}`。
  void beginMark({required String kind, required String label, bool revealed = true});

  /// 放置单位/玩家：下一次点击把 actorName / playerSeat 落到该点。
  void beginPlace({String? actorName, String? playerSeat});

  void cancel();

  /// 舞台当前是否处于「等待一次点击」的待放状态（用于显示十字光标）。
  bool get awaitingTap;
}

// ------------------------------------------------------------
// 通用件
// ------------------------------------------------------------

/// 所有块的外框。Card 内部自带 Material，可直接放 InkWell / RoomTap。
/// ★ 内部严禁 ListTile / SwitchListTile（T3）。
class SectionBox extends StatelessWidget {
  const SectionBox({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.foldId,
    this.expand = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// 折叠标识（供 `RoomUiLocal.folded` 使用；本 widget 不改本地态）。
  final String? foldId;

  /// 高度策略开关（2.42.0 / P20 需求 3⑦）。**默认 false ⇒ 渲染逐字不变**。
  ///
  /// · `false`（默认）：`Column(mainAxisSize: MainAxisSize.min)` —— Card 按内容
  ///   撑高，与 P17 KP-4「三块等高」的口径一致，既有 200+ 条几何断言依赖它。
  /// · `true`：`MainAxisSize.max` **且**把 [child] 包进 `Expanded`。
  ///
  /// ★ 为什么必须同时包 `Expanded`，而不是只改 `mainAxisSize`：
  ///   `RenderFlex` 给**非 flex 子级**下发的约束是「交叉轴收紧、主轴
  ///   `maxHeight == double.infinity`」（见 `RenderFlex.performLayout` 里
  ///   `innerConstraints = BoxConstraints(maxWidth: constraints.maxWidth)`）。
  ///   所以只把本 Column 改成 `max` 时，[child] 仍然拿到**无界高度**——
  ///   [child] 里再放 `Expanded` / `ListView` / `FeedList` 会当场撞
  ///   「RenderFlex children have non-zero flex but incoming height constraints
  ///   are unbounded」。只有 `Expanded(child)` 才会给它下发**紧**高度。
  ///
  /// ★ 调用约束：`expand: true` 要求 SectionBox 自身处在**有界高度**里
  ///   （dock 格 / `Scaffold.body` / 全屏路由 body）。放进
  ///   `SingleChildScrollView` 这类无界父级会断言失败 —— 那时请传 false。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    // ★ 栏位美化：在卡片内容**下方**铺一张暗/亮双主题的装饰边框纹理
    //   （`Art.panelFrameFor`）。用 `Stack` + `Positioned.fill` 把图垫在
    //   `Padding/Column` 下方 —— 尺寸仍由 `Padding/Column` 决定，几何逐像素
    //   不变（P10 的 200+ 条几何断言因此不受影响）。`Card.clipBehavior` 让图
    //   随圆角裁切；图仅绘制、不占尺寸。
    //   `Art` 缺图时 `Image.asset` 走 errorBuilder 静默降级，只露出 Card 底色。
    return Card(
      margin: const EdgeInsets.all(RoomTheme.panelGap / 2),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RoomTheme.panelRadius),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            // ★ P18b 修复（重叠）：原用 `BoxFit.fill` 把方形边框图整张拉伸铺满
            //   卡片，横屏卡片一宽，四角巴洛克花饰与细金线被横向拉扁，压到标题
            //   / 内容 / 右侧按钮上。修法分两层：
            //   ① 已重做「薄轮廓」素材：内金线贴近边缘、四角花饰压到 ≤7%（curl
            //      仅约 68px / 1024），不再是原来 220px 的大花饰；
            //   ② 用 `LayoutBuilder` 判断卡片短边：足够大（≥ 2×切分内边距）时走
            //      `centerSlice` 九宫格——四角花饰按原尺寸固定、只拉伸直边与中央，
            //      长宽比再大也不变形、不越界；卡片太小（dock 短格等，短边放不下
            //      两个角）时退回 `BoxFit.fill` 整张拉伸——此时卡片本身极小，
            //      花饰占比也小，不会压到内容。两路都不加 padding、不影响布局。
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints c) {
                // 源图 1024²，薄轮廓下角部（内金线拐角 + 花饰）只占约 40-70px。
                // 九宫格内边距取 40px：四角花饰在屏幕上约 20-25px、小巧贴角，
                // 不会压到 10px 内边距里的标题与右侧按钮；短边 ≥ 2×40 = 80px
                // 才走九宫格（绝大多数卡片都满足），否则退回普通整图拉伸。
                const double kSlice = 40;
                final bool bigEnough =
                    c.maxWidth >= kSlice * 2 && c.maxHeight >= kSlice * 2;
                // ★ 为什么要自己画九宫格（CustomPainter），而不用 Flutter 自带的
                //   `Image.centerSlice` / `DecorationImage.centerSlice`：
                //   两者在图片被「缩放」绘制时都会断言崩溃
                //   `decoration_image.dart:572 'sourceSize == inputSize'`——
                //   即 centerSlice 只允许 1:1 原尺寸绘制，一旦卡片尺寸 ≠ 源图
                //   尺寸（必然发生）就挂。自绘 9 段 `drawImageRect` 完全绕开该
                //   限制：四角花饰按固定 40px 画、四条边与中央各自拉伸，任意长
                //   宽比都不变形、不越界、不崩。
                return _NineSliceFrame(
                  asset: Art.panelFrameFor(Theme.of(ctx).brightness),
                  slice: bigEnough ? kSlice : 0,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      // ★ P10 第 7 期：栏位标题色必须**跟随主题**。
                      //   `_textTheme()` 并未定义 `titleSmall`，它回落到默认
                      //   DefaultTextStyle，亮色皮肤下会与卡片浅底混成「白字看不见」。
                      //   这里显式取 `colorScheme.onSurface`（亮=深墨、暗=浅墨），
                      //   与 Card 底色构成 ≥4.5:1 对比，亮暗两套皮肤都可读。
                      child: Text(
                        title,
                        style: (Theme.of(context).textTheme.titleSmall ??
                                Theme.of(context).textTheme.titleMedium)
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 8),
                // ★ P20 需求 3⑦：`expand` 时把剩余高度真正交给 child
                //   （理由见 [expand] 的注释：非 flex 子级拿不到有界高度）。
                expand ? Expanded(child: child) : child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 可点件的统一按钮底色（P12）。
///
/// 为什么单独抽出来：改之前 `RoomTap` 只有「图标 + 文字」，落在面板 / 工具栏上
/// 完全看不出是可点的按钮（用户 2026-11 真机反馈「还有一些文字按钮但是没有
/// 按钮背景图，看着有些别扭」）。房间内 140+ 个可点件**全部**由 [RoomTap] 出，
/// 所以皮肤只画在这一处；每处手写一套，圆角与描边粗细几天内就会跑偏。
///
/// ★ 零布局影响：只画底色 + 描边，**一个 padding 都不加**，外部尺寸仍由
///   [RoomTap] 内部的 `ConstrainedBox(minSize)` 与内容决定 —— P10 的几何实测
///   （工具栏按钮不越界、5 个缩放档同一行）因此逐条不变。
class RoomButtonSkin extends StatelessWidget {
  const RoomButtonSkin({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  /// 与 ChipTheme / InputDecoration 同一套「可点控件」口径：面板底是
  /// `Palette.surface`，控件再亮一档（`surface2`）才看得出边界；用 `surface`
  /// 会与所在卡片同色、只剩一根几乎看不见的描边，等于没补。
  ///
  /// ★ 按钮美化（2026-11）：在底色之上再铺一张「细金描边 + 极轻顶部高光」的
  ///   底板纹理（暗/亮两套，`Art.btnPlateFor`），与栏位边框的维多利亚金线统一。
  ///   **零布局影响**：`DecorationImage` 只绘制、不占尺寸，按钮的 48×48 热区与
  ///   `minSize` 口径一字不动。`color` 仍为 `surface2`（既有底色断言不变），
  ///   纹理按其自身 `opacity` 叠在上面 —— 可用态 0.92、禁用态 0.30（更淡，
  ///   一眼看出不可点，且与 `color.a=0.45` 叠加后整体更灰）。
  static BoxDecoration decorationFor(bool enabled) => BoxDecoration(
        color: enabled
            ? Palette.surface2
            : Palette.surface2.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(Radii.md),
        image: DecorationImage(
          image: AssetImage(Art.btnPlateFor(
              Palette.isDark ? Brightness.dark : Brightness.light)),
          fit: BoxFit.fill,
          // ★ P18b：按钮底板是「细金描边圆角框 + 顶部轻高光」，描边本就极薄且
          //   贴着边缘，直接 `BoxFit.fill` 拉伸即可（圆角在极宽按钮上略有透视，
          //   但按钮高度都很小、观感不影响）；不再用 `centerSlice`，避免窄按钮
          //   （<2×inset）时的负边绘制风险。
          opacity: enabled ? 0.92 : 0.28,
        ),
      );

  /// ★ P12：描边走 `foregroundDecoration`。`BoxDecoration.border` 会**参与布局**
  ///   —— 1dp 边框让每个 RoomTap 从 48×48 撑成 50×50，工具栏一行就放不下，
  ///   而用户明确要求「布局不要动」。前景装饰只绘制、不占尺寸，视觉上仍是
  ///   1dp / `Palette.border` / `Radii.md` 同一口径，且盖在水波纹上层不影响反馈。
  static BoxDecoration borderFor() => BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Palette.border),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: decorationFor(enabled),
      foregroundDecoration: borderFor(),
      child: child,
    );
  }
}

/// 所有可点元素的唯一抓手。
/// `enabled` 是 T-30 表驱动权限探针读取的字段；`hint` 在禁用时以 Tooltip 呈现。
class RoomTap extends StatelessWidget {
  const RoomTap({
    super.key,
    this.label = '',
    this.icon,
    this.pngIcon,
    this.enabled = true,
    this.hint,
    this.onTap,
    this.minSize = const Size(RoomTheme.tapMinSize, RoomTheme.tapMinSize),
  });

  final String label;
  final IconData? icon;

  /// 自绘 PNG 线稿图标（`assets/images/icons/<pngIcon>.png`）。
  ///
  /// 为什么不用 `IconData`：骰型（d4/d6/d8/d10/d12/d20/d100）没有对应的
  /// Material 图标，而自绘的那套是**白色线稿 + alpha**，这里用 `srcIn`
  /// 染成当前前景色，所以 enabled / disabled / 两套皮肤都自动跟随。
  final String? pngIcon;
  final bool enabled;
  final String? hint;
  final VoidCallback? onTap;
  final Size minSize;

  /// 统一触控口径（§1.5）：热区 ≥48dp + padded。
  static const MaterialTapTargetSize tapTargetSize = MaterialTapTargetSize.padded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = enabled ? theme.colorScheme.primary : theme.disabledColor;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (pngIcon != null)
          ColorFiltered(
            colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
            child: Image.asset(
              'assets/images/icons/$pngIcon.png',
              width: 16,
              height: 16,
              // 资源缺失（老包 / 测试夹具）时静默降级，绝不因为一张图炸掉按钮
              errorBuilder: (BuildContext context, Object? error,
                      StackTrace? stack) =>
                  const SizedBox.shrink(),
            ),
          ),
        if (pngIcon != null && label.isNotEmpty) const SizedBox(width: 4),
        if (icon != null) Icon(icon, size: 18, color: fg),
        if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
        if (label.isNotEmpty)
          Text(label, style: TextStyle(color: fg, fontSize: 13)),
      ],
    );
    final body = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minSize.width,
        minHeight: minSize.height,
      ),
      // ★ `widthFactor/heightFactor = 1`（P10 第 2 期 B）：`Center` 在**宽度有界
      //   但松**的容器里会撑满整行，于是放进 `Wrap` 后每个按钮各占一行
      //   （工具栏「按钮显示不全 / 要横向拖动」的根因）。改成按内容收紧后，
      //   按钮宽度 = max(内容, minSize)，`Wrap` 才能真的多列排布。
      //   在紧约束（Column 的 stretch、Expanded）下行为不变。
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: row,
        ),
      ),
    );
    final ink = InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(Radii.md),
      child: body,
    );
    final withHint = (hint == null || hint!.isEmpty)
        ? ink
        : Tooltip(message: hint!, child: ink);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label.isNotEmpty ? label : (hint ?? ''),
      // ★ 按钮底色在 Material **外面**：底色先画、水波纹画在它上面，
      //   否则水波会被这层底色盖住（点下去毫无反馈）。
      child: RoomButtonSkin(
        enabled: enabled,
        child: Material(type: MaterialType.transparency, child: withHint),
      ),
    );
  }
}

/// 面板 tab 条；选中态用颜色区分，不持有本地态（由调用方传 index）。
///
/// [icons] 与 [tabs] 一一对应：给了就在文字前画一个 14dp 的 Material 图标
/// （P12 起 tab 名里不再夹 emoji）。不传则与旧版逐像素一致。
class PanelTabs extends StatelessWidget {
  const PanelTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.icons,
    // ★ 2.34.0 / I17（KP-3）：默认 false ⇒ 行为与旧版逐字一致。
    this.equalWidth = false,
  });

  final List<String> tabs;
  final List<IconData?>? icons;
  final int index;
  final ValueChanged<int> onChanged;

  /// 三 tab 等宽开关（可选，默认关闭）。
  ///
  /// ★ 只在显式传 true 时生效：`gp_combat_list.dart:147-152` 的
  ///   「顺序 / 怪物信息」不传该参数 ⇒ 渲染树逐字不变（C4 / I17）。
  final bool equalWidth;

  /// 等宽分支的**固定高度**：取工程内既有 chip 高度口径 ——
  /// `RoomBtnSize.scenePlTile`（`room_button_size.dart:100`）注释记载
  /// 「技能 chip 高度恒定 32」，与 M3 `ActionChip` 默认高度同档。
  /// 固定 w + 固定 H ⇒ 三个 tab 的 RenderBox 尺寸逐像素相等（容差 0）。
  static const double _kEqualTabHeight = 32;

  @override
  Widget build(BuildContext context) {
    final selected = Theme.of(context).colorScheme.primaryContainer;
    if (!equalWidth) return _defaultWrap(selected);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth;
        // 无界 / 非正宽度（独立 pump、无界父约束）无法均分 → 原样退回，
        // 避免 SizedBox(width: infinity) 在紧约束下抛断言。
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return _defaultWrap(selected);
        }
        // ★ I17 冻结公式：扣掉 2 个 spacing(6) 后按 tab 数动态均分，
        //   不写死任何像素宽度，随栏位可用宽自适应。
        final double w = (maxWidth - 2 * 6) / tabs.length;
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            // ★ 2.34.0 / KP-3 返工：等宽分支改用**专用紧凑 chip**，
            //   不复用默认 `_chip`（默认 chip 的 padding + 长 label 在
            //   w≈57.7dp 下 textScaler=1.0 基线就会 RenderFlex overflow）。
            for (var i = 0; i < tabs.length; i++)
              // ★ C7（保留原 :303 写法）：定宽子树唯一允许的大字体写法 ——
              //   只钳该控件子树，1.0 / 1.3 / 1.5 / 2.0 四档都不撑破紧约束；
              //   不 ClipRect、不抬到页面 / Theme 层、不改 textTheme。
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.0,
                child: _equalChip(i, selected, w),
              ),
          ],
        );
      },
    );
  }

  /// 单个 tab chip。默认分支与等宽分支共用，参数与旧实现逐字一致。
  Widget _chip(int i, Color selected) => ActionChip(
        backgroundColor: i == index ? selected : null,
        label: _label(i),
        onPressed: () => onChanged(i),
      );

  /// 旧版 Wrap（默认分支 / 无界宽度回退共用），行为逐字不变。
  Widget _defaultWrap(Color selected) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          for (var i = 0; i < tabs.length; i++) _chip(i, selected),
        ],
      );

  /// ★ 2.34.0 / KP-3 返工：等宽分支**专用紧凑 chip**（不复用 [_chip]）。
  ///
  /// ① 外框 `SizedBox(width: w, height: H)` 给 tight 约束 ⇒ 三个 tab
  ///    渲染宽、高逐像素相等；H 取既有 chip 高度口径 [_kEqualTabHeight]。
  /// ② `padding` / `labelPadding` 归零 + `shrinkWrap` 去掉默认约 32dp
  ///    内边距与 48dp 最小热区，label 可用宽直接等于 w。
  /// ③ label 走 `Center + FittedBox(BoxFit.scaleDown)`：FittedBox 给
  ///    [_label] 的 Row **无界约束**按固有尺寸测量（不会 RenderFlex
  ///    overflow），再整体等比缩小到 ≤ w×H —— 只缩不放、不截断、不删 icon，
  ///    「NPC·怪物」完整可读；不用 TextOverflow.ellipsis、不用 ClipRect。
  /// ④ 选中底色、点击回调、icons 着色全部沿用默认 chip 口径
  ///    （外层 C7 钳制见 build 的 equalWidth 分支）。
  Widget _equalChip(int i, Color selected, double w) {
    return SizedBox(
      width: w,
      height: _kEqualTabHeight,
      child: ActionChip(
        backgroundColor: i == index ? selected : null,
        padding: EdgeInsets.zero,
        labelPadding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        label: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _label(i),
          ),
        ),
        onPressed: () => onChanged(i),
      ),
    );
  }

  Widget _label(int i) {
    final text = Text(tabs[i], style: const TextStyle(fontSize: 12));
    final icon = (icons != null && i < icons!.length) ? icons![i] : null;
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: i == index ? Palette.goldStr : Palette.textDim),
        const SizedBox(width: 4),
        text,
      ],
    );
  }
}

/// 可滚动内容容器；有 controller 时额外挂 Scrollbar。
class ScrollBox extends StatelessWidget {
  const ScrollBox({
    super.key,
    required this.child,
    this.controller,
    this.minHeight = 80,
  });

  final Widget child;
  final ScrollController? controller;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final view = SingleChildScrollView(controller: controller, child: child);
    final activeController = controller;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: activeController == null
          ? view
          : Scrollbar(controller: activeController, child: view),
    );
  }
}

String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// 数值条（HP / MP / SAN）；`max <= 0` 时进度按 0 处理，不显示除零。
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    this.color,
    this.showNumbers = true,
  });

  final String label;
  final num value;
  final num max;
  final Color? color;
  final bool showNumbers;

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Row(
      children: <Widget>[
        SizedBox(width: 34, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: LinearProgressIndicator(value: ratio, minHeight: 6, color: color),
        ),
        if (showNumbers)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text('${_fmt(value)} / ${_fmt(max)}',
                style: const TextStyle(fontSize: 11)),
          ),
      ],
    );
  }
}

/// 头像圆点（无头像时用昵称首字）。
class AvatarDot extends StatelessWidget {
  const AvatarDot({
    super.key,
    required this.name,
    this.size = 32,
    this.color,
  });

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontSize: size * 0.45),
      ),
    );
  }
}

/// 多选 chip 行（精神状态 / 标签）。
class ChipRow extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.labels,
    this.selected = const <String>{},
    this.onTap,
  });

  final List<String> labels;
  final Set<String> selected;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final highlight = Theme.of(context).colorScheme.primaryContainer;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: <Widget>[
        for (final label in labels)
          ActionChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            backgroundColor: selected.contains(label) ? highlight : null,
            onPressed: onTap == null ? null : () => onTap!(label),
          ),
      ],
    );
  }
}

/// 折叠头（标题 + 展开/收起按钮 + 可选右侧件）。
class FoldHeader extends StatelessWidget {
  const FoldHeader({
    super.key,
    required this.title,
    required this.folded,
    required this.onToggle,
    this.trailing,
  });

  final String title;
  final bool folded;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        ?trailing,
        RoomTap(
          icon: folded ? Icons.expand_more : Icons.expand_less,
          hint: folded ? '展开' : '收起',
          onTap: onToggle,
        ),
      ],
    );
  }
}

/// 弹层壳（由 `sheets/room_sheet.dart#showRoomSheet` 调用）。
class RoomSheet extends StatelessWidget {
   const RoomSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 头部：一张金色魔法阵微光图垫底，标题直接叠在上面。
              // 18 个弹层共用这一处，所以只出一张图就够（清单 F1）。
              DecoratedBox(
                decoration: BoxDecoration(
                  image: artDecoration(Art.sheetHeaderFor(Palette.brightness),
                      fit: BoxFit.cover, opacity: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(title,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 二次确认按钮（危险操作：清除笔迹 / 删素材）。
class ConfirmTwice extends StatefulWidget {
  const ConfirmTwice({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmLabel = '再点一次确认',
  });

  final String label;
  final String confirmLabel;
  final VoidCallback onConfirmed;

  @override
  State<ConfirmTwice> createState() => _ConfirmTwiceState();
}

class _ConfirmTwiceState extends State<ConfirmTwice> {
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return RoomTap(
      label: _armed ? widget.confirmLabel : widget.label,
      icon: Icons.warning_amber_outlined,
      hint: '需要连续点击两次',
      onTap: () {
        if (!_armed) {
          setState(() => _armed = true);
          return;
        }
        setState(() => _armed = false);
        widget.onConfirmed();
      },
    );
  }
}

/// T02 骨架占位块；T03/T04/T05 逐个替换。
/// ★ T05 收尾必须 `findsNothing`（K-01）。
class PlaceholderBlock extends StatelessWidget {
  const PlaceholderBlock({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(RoomTheme.panelRadius),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

// ------------------------------------------------------------
// ★ P18b：自绘九宫格装饰底纹（绕开 Flutter centerSlice 的 1:1 断言限制）
// ------------------------------------------------------------

/// 把一张带四角花饰的方形装饰图按「九宫格」铺满任意尺寸的卡片。
///
/// · [slice] > 0 且卡片短边 ≥ 2×[slice] 时：四角按固定 [slice] 像素绘制
///   （花饰不变形、始终贴角），四条边与中央各自拉伸填满。
/// · [slice] == 0：退回整图 `drawImageRect` 拉伸（用于极小的 dock 短格）。
///
/// 为什么不用 `Image.centerSlice` / `DecorationImage.centerSlice`：二者在
/// 图片被缩放绘制时都会断言 `decoration_image.dart:572 'sourceSize == inputSize'`
/// 崩溃（centerSlice 仅允许 1:1 原尺寸）。自绘 9 段 `drawImageRect` 无此限制。
class _NineSliceFrame extends StatefulWidget {
  const _NineSliceFrame({required this.asset, required this.slice});

  final String asset;
  final double slice;

  @override
  State<_NineSliceFrame> createState() => _NineSliceFrameState();
}

class _NineSliceFrameState extends State<_NineSliceFrame> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_NineSliceFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) _resolve();
  }

  void _resolve() {
    final ImageStream stream = AssetImage(widget.asset).resolve(
      createLocalImageConfiguration(context),
    );
    if (_stream?.key == stream.key) return;
    _detach();
    _stream = stream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool sync) {
        if (!mounted) return;
        setState(() => _image = info.image);
      },
      onError: (Object e, StackTrace? s) {
        // 缺图：静默降级，只露出 Card 底色。
      },
    );
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? img = _image;
    if (img == null) return const SizedBox.expand();
    return CustomPaint(
      painter: _NineSlicePainter(image: img, slice: widget.slice),
      size: Size.infinite,
    );
  }
}

class _NineSlicePainter extends CustomPainter {
  _NineSlicePainter({required this.image, required this.slice});

  final ui.Image image;
  final double slice;

  @override
  void paint(Canvas canvas, Size size) {
    final double sw = image.width.toDouble();
    final double sh = image.height.toDouble();
    final Paint paint = Paint()..filterQuality = FilterQuality.medium;
    final Rect dst = Offset.zero & size;

    // 无九宫格（极小卡片）：整图拉伸。
    if (slice <= 0 || size.width < slice * 2 || size.height < slice * 2) {
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, sw, sh), dst, paint);
      return;
    }

    final double s = slice;
    // 源图四角边长按同样 slice 比例取（源图边长未必等于目标 slice，
    // 这里把 source 的角区按 slice 与自身尺寸的比例切分——因源图 1024、
    // 角部占用 ~40-70px，取源切片 = slice 即可，比例一致）。
    final double srcL = s, srcT = s, srcR = sw - s, srcB = sh - s;
    final double dstR = size.width - s, dstB = size.height - s;

    void tile(double sx0, double sy0, double sx1, double sy1, Rect d) {
      if (d.width <= 0 || d.height <= 0 || sx1 <= sx0 || sy1 <= sy0) return;
      canvas.drawImageRect(
        image,
        Rect.fromLTRB(sx0, sy0, sx1, sy1),
        d,
        paint,
      );
    }

    // 四角（固定 slice 尺寸）
    tile(0, 0, srcL, srcT, Rect.fromLTWH(0, 0, s, s)); // TL
    tile(srcR, 0, sw, srcT, Rect.fromLTWH(dstR, 0, s, s)); // TR
    tile(0, srcB, srcL, sh, Rect.fromLTWH(0, dstB, s, s)); // BL
    tile(srcR, srcB, sw, sh, Rect.fromLTWH(dstR, dstB, s, s)); // BR
    // 四条边（拉伸）
    tile(srcL, 0, srcR, srcT, Rect.fromLTWH(s, 0, size.width - 2 * s, s)); // top
    tile(srcL, srcB, srcR, sh,
        Rect.fromLTWH(s, dstB, size.width - 2 * s, s)); // bottom
    tile(0, srcT, srcL, srcB, Rect.fromLTWH(0, s, s, size.height - 2 * s)); // left
    tile(srcR, srcT, sw, srcB,
        Rect.fromLTWH(dstR, s, s, size.height - 2 * s)); // right
    // 中央（拉伸）
    tile(srcL, srcT, srcR, srcB,
        Rect.fromLTWH(s, s, size.width - 2 * s, size.height - 2 * s));
  }

  @override
  bool shouldRepaint(_NineSlicePainter old) =>
      old.image != image || old.slice != slice;
}
