// ============================================================
// widgets/room_event_banner.dart — 关键事件「全屏信息遮罩」（P21 需求 1-3）
//
// 一次只显示**一条**：整屏半透明遮罩 + 16:9 底图（完整呈现、绝不裁切）
// + 居中标题 / 副标题。
//
// ------------------------------------------------------------
// P21 改版：从「居中卡片」改成「全屏遮罩」（用户明确要求）
// ------------------------------------------------------------
// 改前（P20）是一张居中卡片：`maxWidth=520` + `maxHeightRatio=0.32`，
// 16:9 底图被塞进一条 `Flexible(loose)` 的窄带里，于是 `BoxFit.cover`
// 只能把上下一刀切掉 —— 5 类底图**全部**被裁（用户截图的是「永久疯狂」
// 那张：撕卡特有的右下角撕裂纸边被裁掉了，观感上等于换了张图）。
//
// 改后：
//   · 遮罩**铺满全屏**，带透明度（用户原话：玩家还能看到游戏房间背景）；
//   · 底图不再被压进窄带 —— 主图层用 `BoxFit.contain` 装进一个
//     **精确 16:9 的框**（`AspectRatio(16/9)`），框与图比例相等 ⇒
//     contain ≡ 不裁不变形（与 `lib/ui/widgets.dart#SectionBanner.fitFor`
//     同一条口径：框不是图的比例时才允许 contain，任何时候都不用 cover 硬裁）；
//   · 另有一层同图的 `BoxFit.cover` **低透明度氛围层**，只为在竖屏 / 超宽屏
//     上把遮罩「补满」（16:9 图铺不满的上下或左右两侧不会露出突兀的纯色带）。
//     这一层**不承载构图**，裁掉的是模糊的暗部边缘，故与「图片显示不全」
//     不冲突（构图由上面那层 contain 完整承载）。
//
// ------------------------------------------------------------
// 点击：任意位置 → 当前条淡出关闭（P21 需求 3）
// ------------------------------------------------------------
// ★ 口径变更（**用户明确推翻**了 P20 的裁定 D3「不可点击关闭」）：
//   旧口径——整卡 `IgnorePointer`，4 秒自消、点不掉，理由是「一可点就等于
//   在屏幕上挖了个黑洞」。
//   新口径——遮罩**存在时**全屏可点（点一下关掉当前这条），**不存在时**
//   子树根本不挂手势层（`onDismiss == null` 时连 `GestureDetector` 都不建），
//   所以「无横幅时绝不拦截页面点击」是结构性的，不依赖调用方自觉。
//   为什么更强：旧口径守的是「浮层不吃点击」，但它同时让用户**无法主动
//   关掉**一条盖住整屏的遮罩（5 类关键事件在 KP 的 SAN Check 场景下会
//   连发，玩家要等 4 秒 × N 条）。新口径把两件事拆开守：
//     ① 没有遮罩时零手势层（比 IgnorePointer 更彻底：连 RenderObject 都没有）；
//     ② 有遮罩时只吃「一次点击」且只关当前条（后续条目照常按序弹）。
//
// ★ 淡出**必须是真的动画**：数据层移除是瞬时的（`banners` 队列立即前进），
//   视觉层由 `_BannerMaskLayer` 的 `AnimatedSwitcher`（默认 `FadeTransition`）
//   用 [fadeDuration] 淡出 / 交叉淡化。所以「点掉」= 220ms 的真淡出，
//   不是「啪」一下消失。
//
// ★ textScaler：遮罩里的字号是**固定**的（26 / 15），所以只包本控件子树
//   `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)`
//   （与 `room_button_size.dart#clampBtnText` / `resume_mode_dialog.dart:66`
//   同口径）。不做页面级钳制、不用 `ClipRect` / `ClipRRect` 硬裁。
//
// ★ 本控件**不持有 Timer**：到点自消由 `RoomUiLocal` 内部走可注入的
//   `scheduleDismiss` 驱动（FakeAsync 口径，FakeAsync 里推 4 秒才消失）。
//
// ------------------------------------------------------------
// 与 `RoomUiLocal` 的归属说明
// ------------------------------------------------------------
// [RoomBannerItem] 定义在**本文件**而不是 `room_ui_local.dart`：
//   · 本文件是它的唯一消费者，定义在这里不产生任何反向依赖；
//   · 先落盘的一方必须能独立编译 —— 若 `room_ui_local.dart` 先引用一个
//     还不存在的类，整个仓库会编译不过。
//   `room_ui_local.dart` 只需两行即可获得与契约**完全一致**的对外符号：
// ```dart
// import 'widgets/room_event_banner.dart' show RoomBannerItem;
// export 'widgets/room_event_banner.dart' show RoomBannerItem;
// ```
// ============================================================

import 'package:flutter/material.dart';

import '../../art.dart' show ArtImage;
import '../../../theme.dart' show Palette;

/// 一条横幅默认显示多久（P21 需求 3：4 秒）。
///
/// 放在这里的理由：它同时是 `RoomBannerItem.ttl` 的默认值、
/// `RoomUiLocal.pushBanner(ttl:)` 的默认值、以及本控件 `ttl` 的默认值 ——
/// 三处必须是**同一个**常量，否则「契约声明」与实际行为会悄悄跑偏。
const Duration kBannerDefaultTtl = Duration(seconds: 4);

/// 一条「关键事件横幅」的队列元素。
///
/// 由 `RoomUiLocal.banners` 持有（独立队列，与 `notice` / `optoasts`
/// **完全分开**，那两条通路被大量用例锁死，本批不动）。
/// [id] 稳定且递增，供 `RoomEventBannerKeys.root(id)` 定位、供到点自消 /
/// 点击关闭按 id 精确移除；[at] 是入队时刻（纯记录，不参与任何判据 /
/// 规则 / 存档）。
class RoomBannerItem {
  const RoomBannerItem(
    this.id,
    this.title,
    this.subtitle,
    this.art,
    this.at, {
    this.ttl = kBannerDefaultTtl,
  });

  /// 递增 id（自消 / 点击关闭时按它精确移除，不会误删后来入队的同文案条目）。
  final int id;

  /// 主标题（已由 `EventBannerCopy` 生成）。
  final String title;

  /// 副行；空串表示没有副行（例如「获得 1 项新的疯狂症状」）。
  final String subtitle;

  /// 16:9 底图资源路径（来自 `Art.e18Banner*`）。
  final String art;

  /// 入队时刻。
  final DateTime at;

  /// 这条「独占屏幕」时应该显示多久（默认 [kBannerDefaultTtl] = 4 秒）。
  ///
  /// ★ 只有它**排在队尾**时才会用满这个时长：后面还有条目等着上屏时，
  ///   `RoomUiLocal` 会改用连发短时长，让队列尽快走完（见那边的说明）。
  final Duration ttl;

  /// 是否有副行（UI 据此决定要不要留那一行的高度）。
  bool get hasSubtitle => subtitle.trim().isNotEmpty;

  @override
  String toString() => 'RoomBannerItem($id, $title / $subtitle, $art)';
}

/// 关键事件遮罩的稳定 key（供测试逐条定位 / 逐块断言）。
class RoomEventBannerKeys {
  const RoomEventBannerKeys._();

  /// 一条遮罩的整体（铺满全屏，`banner.id` 区分）。
  static Key root(int id) => ValueKey<String>('roomBanner/root/$id');

  /// 全屏半透明遮罩底色（铺满屏，尺寸即屏幕）。
  static Key mask(int id) => ValueKey<String>('roomBanner/mask/$id');

  /// 主图层：**精确 16:9** 的框 + `BoxFit.contain` ⇒ 图完整、不裁切。
  static Key art(int id) => ValueKey<String>('roomBanner/art/$id');

  /// 氛围层：同图 `BoxFit.cover` + 低透明度，只为把遮罩补满（不承载构图）。
  static Key ambientArt(int id) => ValueKey<String>('roomBanner/ambient/$id');

  /// 主标题。
  static Key title(int id) => ValueKey<String>('roomBanner/title/$id');

  /// 副行（没有副行时整块不渲染，`findsNothing` 也是有效断言）。
  static Key subtitle(int id) => ValueKey<String>('roomBanner/subtitle/$id');

  /// 整屏点击关闭层（没有 `onDismiss` 时**根本不建**，`findsNothing` 有效）。
  static Key tapTarget(int id) => ValueKey<String>('roomBanner/tap/$id');
}

/// 关键事件「全屏信息遮罩」：背景遮罩 + 16:9 底图 + 居中标题 / 副标题。
///
/// 挂载点：`RoomNoticeOverlay` 的浮层 `Stack` 里、最上层（由
/// `_BannerMaskLayer` 用 `AnimatedSwitcher` 做淡入淡出）。
class RoomEventBanner extends StatelessWidget {
  const RoomEventBanner({
    super.key,
    required this.banner,
    this.ttl = kBannerDefaultTtl,
    this.onDismiss,
  });

  /// 要渲染的那一条（由 `RoomUiLocal.banners` 的队首提供）。
  final RoomBannerItem banner;

  /// 展示时长。★ 只作**契约声明**：自消由 `RoomUiLocal` 的
  /// `scheduleDismiss` 驱动，本控件不持有任何 Timer。
  final Duration ttl;

  /// 点击遮罩任意位置时的回调（`RoomUiLocal.dismissActiveBanner`）。
  ///
  /// ★ 为 `null` 时**不建手势层** —— 「没有可关闭的遮罩就绝不拦截点击」
  ///   由结构保证，而不是靠 `IgnorePointer` 事后兜。
  final VoidCallback? onDismiss;

  // ------------------------------------------------------------
  // 遮罩层次常量（改数值前请先看各自的理由）
  // ------------------------------------------------------------

  /// ① 半透明遮罩底色：alpha 166/255 ≈ 0.65。
  ///
  /// 取值理由：既要「铺满全屏、压住游戏画面」，又要满足用户「玩家还能看到
  /// 游戏房间背景」。0.65 时房间仍保留约 1/3 的可见度（能看出舞台 / 面板
  /// 轮廓），再深（0.8+）就只剩一块黑；再浅（0.5-）在亮色舞台上文字对比度
  /// 不够。
  static const Color mask = Color(0xA60B0D11);

  /// ② 氛围层（同图 `cover`）的不透明度：0.30。
  ///
  /// 只为了让 16:9 图铺不满的边带也有画面色调，不承载构图；0.30 时它的
  /// 明暗已足够淡（不会让人误以为是「第二张图」），也能与遮罩叠乘后仍保留
  /// 房间轮廓：房间可见度 ≈ (1-0.65) × (1-0.30) ≈ 0.245。
  static const double ambientOpacity = 0.30;

  /// ③ 主图层（`contain`，精确 16:9）的不透明度：0.94。
  ///
  /// 留 6% 的透光：底图那一段仍能隐约透出房间，与「遮罩是半透明的」这一
  /// 整体观感一致；同时 0.94 已足够让底图的构图（撕纸边 / 提灯 / 战场）
  /// 清晰可辨。
  static const double artOpacity = 0.94;

  /// ④ 上下压暗渐变（scrim）的最大 alpha：140/255 ≈ 0.55。
  ///
  /// 5 张底图（已逐张核对）都是「中间空、四边有戏」的电影感构图：
  /// 顶部常有窗光 / 云隙，底部常有主体（撕纸边 / 提灯 / 战场地面）。
  /// 这两条边带既是**画面主体**又最亮，所以只压 0.55、且中间 26%–74%
  /// 完全不压 —— 图案不被压死，文字又落在最暗的中央区。
  static const Color scrimEdge = Color(0x8C000000);

  /// ⑤ 文字底衬（半透明底）：alpha 179/255 ≈ 0.70。
  ///
  /// 「足够的 scrim」由**两重**保证：全屏上下渐变（④）+ 这块贴着文字的
  /// 深色圆角底衬。底衬是最后一道保险 —— 即使某张底图正中偏亮（未来换图
  /// 时可能发生），金色标题也不会糊在图案亮部上。
  static const Color textBackdrop = Color(0xB30A0C10);

  /// 副行文字色（暖白，不用纯白以免在深底上发飘）。
  static const Color bodyText = Color(0xFFEDE6D6);

  /// 文字块最大宽度（平板横屏下不至于拉成一条 1200dp 的长句）。
  static const double maxTextWidth = 720;

  /// 文字块与屏幕左右边缘的最小留白。
  static const double textGutter = 32;

  /// 淡入 / 淡出时长（`_BannerMaskLayer` 的 `AnimatedSwitcher` 使用）。
  ///
  /// 220ms：短到「点一下立刻有反应」，长到肉眼能看出是**淡出**而不是瞬消；
  /// 比 120ms 更像转场、比 400ms 又不至于让下一次点击等太久。
  static const Duration fadeDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final int id = banner.id;

    // 遮罩层次（自下而上）：
    //   ① 半透明底色（房间可见）
    //   ② 氛围层（同图 cover、0.30）
    //   ③ 主图层（精确 16:9 + contain、0.94）—— **构图完整承载在这里**
    //   ④ 上下压暗渐变（scrim）
    //   ⑤ 文字底衬 + 标题 / 副标题
    //   ⑥ 整屏点击层（只在 onDismiss != null 时存在）
    final Widget layers = Stack(
      key: RoomEventBannerKeys.root(id),
      fit: StackFit.expand,
      children: <Widget>[
        // ---- ① 半透明遮罩 ----
        Positioned.fill(
          child: ColoredBox(
            key: RoomEventBannerKeys.mask(id),
            color: mask,
          ),
        ),
        // ---- ② 氛围层：把遮罩「补满」，不承载构图 ----
        Positioned.fill(
          child: ArtImage(
            banner.art,
            key: RoomEventBannerKeys.ambientArt(id),
            fit: BoxFit.cover,
            opacity: ambientOpacity,
            fallback: const ColoredBox(color: _fallbackImageBg),
          ),
        ),
        // ---- ③ 主图层：精确 16:9 的框 ⇒ contain 等于「不裁不变形」----
        //
        // 为什么用 `Center + AspectRatio` 而不是直接 `BoxFit.contain`：
        //   `AspectRatio` 会算出「能装进屏幕的最大 16:9 矩形」，框的比例与
        //   素材完全一致，于是 `BoxFit.contain` 恰好铺满这个框 —— 既不裁，
        //   也不留黑边。用例可以直接量 `art(id)` 的尺寸比值 == 16/9 来
        //   **证明**没被裁（比断言一个 fit 枚举强得多）。
        Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ArtImage(
              banner.art,
              key: RoomEventBannerKeys.art(id),
              fit: BoxFit.contain,
              opacity: artOpacity,
              fallback: const ColoredBox(color: _fallbackImageBg),
            ),
          ),
        ),
        // ---- ④ 上下压暗渐变：图案不被压死，文字落在最暗的中央 ----
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: _edgeScrim),
          ),
        ),
        // ---- ⑤ 标题 / 副标题 ----
        Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: textGutter),
            child: _textBlock(id),
          ),
        ),
        // ---- ⑥ 整屏点击关闭层 ----
        if (onDismiss != null)
          Positioned.fill(
            child: GestureDetector(
              key: RoomEventBannerKeys.tapTarget(id),
              // opaque：连「图上没有内容」的像素也要吃到点击 —— 用户要求
              // 「点击屏幕**任意位置**」都能关。
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );

    // 只钳本控件子树的 textScaler（遮罩内字号固定；不抬到页面 / Theme 层）。
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: layers,
    );
  }

  /// 文字底衬 + 标题 + （可选）副行。
  Widget _textBlock(int id) {
    return Container(
      constraints: const BoxConstraints(maxWidth: maxTextWidth),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 20),
      decoration: BoxDecoration(
        color: textBackdrop,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          // ★ 不能是 const：`Palette.goldStr` 是跟随皮肤的静态 getter。
          color: Palette.goldStr.withValues(alpha: 0.30),
        ),
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // ★ 标题 3 行（2.45.0 修：320dp 极窄屏 + 最长标题会被省略号吃掉字）。
            //
            // 实测（`TextPainter` / `RenderParagraph.didExceedMaxLines`，字号被
            // 本控件钳到固定 26/15，故这些行数是确定的）：
            //   320dp 宽 → 文字块内容宽 = 320 - 2×32(gutter) - 2×28(底衬 padding)
            //              = 200dp；「沈砚清 获得 1 项新的疯狂症状」在 26px 下
            //              **需要 3 行**，2 行会被吃掉约 2 个字。
            //   360dp 起 → 需要 2 行，本来就完整（360/375/400/412 均完整）。
            // 所以 2 → 3 只影响 320dp 这一档，不会让正常尺寸多长出一行
            // （`maxLines` 只是上限，行数由实际排版决定）。
            Text(
              banner.title,
              key: RoomEventBannerKeys.title(id),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Palette.goldStr,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                height: 1.2,
                decoration: TextDecoration.none,
              ),
            ),
            if (banner.hasSubtitle) ...<Widget>[
              const SizedBox(height: 8),
              // ★ 副行同样 2 → 3 行（2.45.0，同类缺陷一并修）。
              //
              // 实测：320dp 下「共 5 名行动者：沈砚清、顾长夜、白露、林间 等 5 人」
              // （`EventBannerCopy.combatStartSubtitle`，名字满 4 个 + 「等 N 人」）
              // 在 15px 下**需要 3 行**，2 行会被截。其余副行模板（含最长的
              // `deathSubtitle`「撕卡 —— 该角色只能通过聊天框交流」）在 320dp
              // 下都只要 2 行，故 3 行上限对它们是无副作用的纯余量。
              //
              // 文案本身一个字没动（`event_banner_copy.dart` 是文案单一真源）。
              Text(
                banner.subtitle,
                key: RoomEventBannerKeys.subtitle(id),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: bodyText,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ④ 的渐变本体：顶部压暗 → 中间 26%–74% 全透明 → 底部压暗。
  static const LinearGradient _edgeScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      scrimEdge,
      Color(0x00000000),
      Color(0x00000000),
      scrimEdge,
    ],
    stops: <double>[0.0, 0.26, 0.74, 1.0],
  );

  /// 底图缺失时的兜底底色（房间面板同色系，不会在亮/暗皮肤上都突兀）。
  static const Color _fallbackImageBg = Color(0xFF1C1F24);
}
