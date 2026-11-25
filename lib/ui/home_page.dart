// ============================================================
// home_page.dart — 首页
//
// 两块（手机纵向堆叠）：
//   · 开始冒险：四张入口横幅（跑团 / AI 车卡 / 一键出卡 / 按流程车卡）
//   · 角色档案：**只留入口**，卡片全部收进二级页 [RosterPage]
//
// ★ P8 为什么要收进二级页（用户原话「不然首页太乱了」）：
//   首页原先直接铺「已保存的角色卡」+「英灵殿」两个网格，卡片多起来以后
//   首屏只剩卡、四个入口全被挤走。现在首页只留一个「角色档案」横幅 +
//   两行只读计数（已保存 / 英灵殿），点任意一处进名册页看卡。
//
// ★ P8 卡面上的 HP / SAN 溢出：窄网格卡（~150px）塞不下两组数值，
//   现在名册页是**一行一张**长条卡，数值放 Wrap 里，窄屏也只是换行不溢出。
//
// P2-A 保留右上角「数据」菜单：导出全部 / 导入 JSON / 设置。
// ============================================================

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../repo/card_transfer.dart';
import '../repo/character_repo.dart';
import '../repo/repo_scope.dart';
import '../theme.dart';
import 'art.dart';
import 'card_transfer_io.dart';
import 'create/rule_pick_page.dart';
import 'responsive.dart';
import 'roster_page.dart';
import 'update_sheet.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 订阅皮肤：Palette 是全局门面，不重建就会停在旧配色上
    // （首页的路由 builder 不会因为切皮肤重跑，只能靠 Theme 依赖把本页标脏）。
    dependOnTheme(context);
    final repo = RepoScope.of(context); // 订阅：存卡 / 删卡后自动刷新
    final alive = repo.alive;
    final fallen = repo.fallen;

    return Scaffold(
      backgroundColor: Colors.transparent,
      /* 入口改成美术横幅（见 `_AdventureSection`）。
         四个 Key（fab_room / fab_ai_create / entry_random / fab_new_card）
         仍是唯一入口，测试与深链行为不受影响。 */
      body: SafeArea(
        bottom: false,
        // 平板/横屏：限宽 760 居中，避免「一行字横跨 1524dp」
        child: ContentFrame(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(child: _HomeHeader(repo: repo)),
              // ⚠️ 不能加 const：const 实例在切皮肤后会原样复用、Element 跳过
              //    rebuild，内部 Palette / Art 取到的还是旧皮肤（P8 bug 5）。
              SliverToBoxAdapter(child: _AdventureSection()),
              SliverToBoxAdapter(
                child: _RosterEntry(alive: alive, fallen: fallen),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「开始冒险」分类：四张入口横幅 2×2 平铺。
///
/// 为什么横滑改平铺：横滑会把后面两张藏起来，用户根本不知道有几个入口；
/// 2×2 四张全在首屏内（手机上一屏就能看到全部四个）。
class _AdventureSection extends StatelessWidget {
  const _AdventureSection();

  /// 卡片内容区比例。
  ///
  /// 源图 1536×620 ≈ 2.477:1，金边内缩到底边 13px / 上边 11px（≈0.85% / 1.8%）。
  ///
  /// 旧值 2.0 是本次「下边框、右边框不见了」的根因：
  ///   · 2.0 < 2.477 → cover 按高铺满、左右各裁 (1−2.0/2.477)/2 ≈ 9.6% 宽度，
  ///     金边左右各只剩 0.85% 的余量 → 右边框直接被裁掉；
  ///   · 3.1 的 `centerLeft` 对齐让裁切全落在右侧，右边框彻底消失；
  ///   · 上下方向铺满不裁，但 `_EntryBanner` 旧的 2:1 高度比图矮 → 下边框被切。
  ///
  /// 现在取 2.45：左右各裁 (1−2.45/2.477)/2 ≈ 0.55% = 8.5px < 13px 金边内缩，
  /// 上下完全不裁 —— 四条金边都在框内，留 4px 以上余量。
  static const double _aspect = 2.45;

  @override
  Widget build(BuildContext context) {
    // 切皮肤必须重建：本组件曾被 const 复用，Element 跳过 rebuild，
    // 内部 `Palette.brightness` 与 `Art.banner(...)` 仍是旧值（P8 bug 5 的根因）。
    dependOnTheme(context);
    final Brightness b = Palette.brightness;

    Widget card(Key key, String darkArt, String lightArt, RulePickTarget next) {
      return _EntryBanner(
        bannerKey: key,
        art: Art.banner(darkArt, lightArt, b),
        aspect: _aspect,
        // ★ P9 需求 5：四个入口逻辑一致 —— 都先到「选择规则系统」，
        //   选完规则再进各自的目标页（房间 / AI / 随机 / 流程向导）。
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => RulePickPage(next: next)),
        ),
      );
    }

    // 顺序沿用旧 FAB 的优先级：跑团 → AI → 一键出卡 → 按流程。
    // ⚠️ 前三个 Key 被 6 个测试文件按名取用，换布局可以，Key 与入口语义不能动。
    // ⚠️ 必须用 Expanded 包住：`Row` 的 child 宽度约束无界，
    //    直接放会让 `AspectRatio` 收到无界约束并抛
    //    `RenderAspectRatio has unbounded constraints`（真机同样崩）。
    final entryRoom = card(
      const Key('fab_room'),
      Art.bannerRoom,
      Art.bannerRoomLight,
      RulePickTarget.room,
    );
    final entryAi = card(
      const Key('fab_ai_create'),
      Art.bannerAi,
      Art.bannerAiLight,
      RulePickTarget.ai,
    );
    final entryRandom = card(
      const Key('entry_random'),
      Art.bannerRandom,
      Art.bannerRandomLight,
      RulePickTarget.random,
    );
    final entryWizard = card(
      const Key('fab_new_card'),
      Art.bannerWizard,
      Art.bannerWizardLight,
      RulePickTarget.wizard,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionBanner(
            title: '开始冒险',
            art: Art.sectionAdventureFor(Palette.brightness),
          ),
          Row(
            children: <Widget>[
              Expanded(child: entryRoom),
              const SizedBox(width: 10),
              Expanded(child: entryAi),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: entryRandom),
              const SizedBox(width: 10),
              Expanded(child: entryWizard),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 一张入口横幅：图片本身就是完整卡片（自带金边与文案），
/// 所以这里**不再叠任何文字或装饰**，只负责可点 + 圆角裁切。
class _EntryBanner extends StatelessWidget {
  const _EntryBanner({
    required this.bannerKey,
    required this.art,
    required this.aspect,
    required this.onTap,
  });

  final Key bannerKey;
  final String art;
  final double aspect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    // 圆角跟随实际宽度，不再写死 46px（2 列网格里宽度只有原来一半）。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth.isFinite ? c.maxWidth : 160;
        final BorderRadius radius = BorderRadius.circular(w * 0.045);
        return AspectRatio(
          aspectRatio: aspect,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: bannerKey,
              borderRadius: radius,
              onTap: onTap,
              child: ClipRRect(
                borderRadius: radius,
                // 居中：源图比框只宽 0.55%，左右各栽掉一点点插画边缘，
                // 四条金边都完整（旧版 centerLeft 把右边框直接裁没了）。
                child: ArtImage(
                  art,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 「角色档案」分类：分区头 + **两张 2:1 入口图**（已保存 / 英灵殿），都进 [RosterPage]。
///
/// ★ P9 追加（用户要求）：原来这里是「一条可点的横幅 + 两行只读计数」，
///   现在改成和「开始冒险」四宫格同一套视觉的两张图 —— 图自带金边与留白，
///   文字（标题 / 张数）由 App 画在图的左侧安全区上，**不烧进图**，
///   这样张数变了不用重出图。
///
/// ★ P10 需求 2：两张入口**各自带作用域**进名册 —— 已保存的只显示已保存，
///   英灵殿只显示长眠者（不再两栏混在一起）。
///
/// ★ P10 需求 4（**已被 P11 推翻**）：P10 时英灵殿那张底图把「英灵殿 /
///   英灵长眠于此 / 致敬每一位调查员」烧进了图里，App 只好不叠字。
///   P11 换了素材：四张入口横幅统一「不含文字、左侧留白、主体在右」，
///   所以两张卡现在**同一套叠字**（竖金条 + 标题 + 张数副标题），
///   用户要的「两个按钮弄成一样的」才是真正落地的状态。
///
/// 为什么还留着上面那条 `SectionBanner`：首页两个分类头（开始冒险 / 角色档案）
/// 左右边界必须完全对齐，那是 P8 的版式约束（`p8_home_ui_test` 有几何断言）。
class _RosterEntry extends StatelessWidget {
  const _RosterEntry({required this.alive, required this.fallen});

  final List<Character> alive;
  final List<Character> fallen;

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    final Brightness b = Palette.brightness;
    // 作用域顺着命名路由的 arguments 带进名册（`app.dart` 不在本批可改范围，
    // 首页两个入口继续共用 `/roster` 这一条路由）。
    void open(RosterScope scope) =>
        Navigator.of(context).pushNamed(RosterPage.route, arguments: scope);

    /* 计数文案：没有卡时给空态引导（老用例按这句断言空态，别改字），
       有卡时给「N 位调查员 / N 位长眠者」。 */
    final String savedSub = alive.isEmpty
        ? '还没有角色卡'
        : '${alive.length} 位调查员';
    final String fallenCount = fallen.isEmpty
        ? '暂无长眠者'
        : '${fallen.length} 位长眠者';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionBanner(
            title: '角色档案',
            hint: '已保存 ${alive.length} 张 · 长眠 ${fallen.length} 位',
            art: Art.sectionArchiveFor(Palette.brightness),
          ),
          /* `home_roster_entry` 是 P8 起老用例按名依赖的入口 Key（点它进名册）。
             现在入口拆成两张图，这个 Key 挂在**第一张**（已保存）外面：
             `KeyedSubtree` 不产生自己的 RenderObject，`tester.tap` 取到的中心
             仍然落在里面那张可点的卡上，老用例不用改。 */
          KeyedSubtree(
            key: const Key('home_roster_entry'),
            child: _RosterBanner(
              bannerKey: const Key('home_roster_saved'),
              art: Art.homeBannerCardsFor(b),
              title: '角色卡',
              subtitle: savedSub,
              accent: Palette.gold,
              onTap: () => open(RosterScope.saved),
            ),
          ),
          const SizedBox(height: 10),
          _RosterBanner(
            bannerKey: const Key('home_roster_valhalla'),
            art: Art.homeBannerValhallaFor(b),
            // ★ P11：新素材**不再把字烧进图里**（左侧整块留白），所以和
            //   「已保存」那张**同一套**标题 + 副标题，两张肉眼一致。
            title: '英灵殿',
            subtitle: fallenCount,
            accent: Palette.danger,
            semanticLabel: '英灵殿',
            onTap: () => open(RosterScope.fallen),
          ),
        ],
      ),
    );
  }
}

/// 一张「角色档案」入口图：2:1 底图 + 左侧安全区文字，整张可点。
///
/// ★ P11（本轮）：两张入口图的素材统一改成「**不含文字、左侧留白、主体在右**」，
///   所以两张卡走**同一套**布局 —— 左侧竖金条 + 标题 + 一行副标题（张数），
///   不再区分「图里有字」和「图里没字」两种形态，也不再挂右下角浮动角标
///   （新素材主体就在右下，角标会压在插画上）。
///
/// 可读性**不再靠压黑**：旧版在左侧压一层 `black@0.55`，那层黑让整张图发灰
/// （用户原话「感觉有一层暗色蒙板…去掉吧，直接用原图显示」）。现在只留一层
/// **跟随皮肤的极淡侧渐变**（亮色 <=0.38 白、暗色 <=0.42 黑，右侧透明），
/// 文字对比度靠 [Shadow] 兜底 —— 浅底深字、深底浅字都读得清。
class _RosterBanner extends StatelessWidget {
  const _RosterBanner({
    required this.bannerKey,
    required this.art,
    required this.accent,
    required this.onTap,
    required this.title,
    required this.subtitle,
    this.semanticLabel,
  });

  final Key bannerKey;
  final String art;
  final Color accent;
  final VoidCallback onTap;

  /// 左侧标题（两张卡必填：图里已经没字了，这一层就是唯一可见的标题）。
  final String title;

  /// 左侧副标题（张数 / 空态引导）。
  final String subtitle;

  /// 读屏名称。图和字是两棵独立子树，给显式的语义标签更稳。
  final String? semanticLabel;

  /// 圆角 = 全站统一的 [Radii.md]（14dp），两张入口**共用这一个值**。
  ///
  /// 旧版按宽度算 `w * 0.045`（328dp 宽 → 14.8dp），而**上一代素材自己就带
  /// 圆角**（像素实测 768 高的图里 r ≈ 41px ≈ 9dp）：裁切线比图上的圆角还大，
  /// 于是切进金框的弧里，四角看着「被削掉」（亮色皮肤下最扎眼）。
  ///
  /// 新素材是**方角全出血**（同尺寸实测四角不透明、无金框），
  /// `ClipRRect` 就是唯一的圆角来源 —— 写死一个 14dp 既不会削到任何画面，
  /// 又和规则卡 / 候选卡（`Radii.md`）保持一致。
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(Radii.md));

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    final bool dark = Palette.isDark;
    // 文字阴影：浅底给白晕、深底给黑晕 —— 不压暗也能保证对比度。
    final List<Shadow> halo = <Shadow>[
      Shadow(
        color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.9),
        blurRadius: 6,
      ),
    ];
    final Color veil = dark ? Colors.black : Colors.white;

    final Widget card = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth.isFinite ? c.maxWidth : 160;
        const BorderRadius radius = _radius;
        return AspectRatio(
          aspectRatio: 2,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: bannerKey,
              borderRadius: radius,
              onTap: onTap,
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // 原图直铺：素材与卡面同为 2:1，不放大、不位移、不额外裁切。
                    ArtImage(art, fit: BoxFit.cover),
                    /* 极淡的左侧渐变（不是蒙版）：只压左半边、到右侧完全透明，
                       亮色提亮、暗色压暗，两张卡都保留原图的质感。 */
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: <Color>[
                            veil.withValues(alpha: dark ? 0.42 : 0.38),
                            veil.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: w * 0.05),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 3,
                                  height: 15,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: serifFamily,
                                    color: Palette.goldStr,
                                    letterSpacing: 1.2,
                                    shadows: halo,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Palette.textDim,
                                height: 1.4,
                                shadows: halo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    final String? semantics = semanticLabel;
    if (semantics == null) return card;
    return Semantics(
      label: semantics,
      button: true,
      container: true,
      child: card,
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.repo});

  final CharacterRepo repo;

  /// 导出全部角色（`{format:'coc7-bundle', version:1, characters:[...]}`，
  /// 顺序与旧版 `Store.listCharacters()` 一致：updatedAt 倒序）
  Future<void> _exportAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final cards = repo.all
      ..sort(
        (a, b) =>
            jsNum(b.raw['updatedAt']).compareTo(jsNum(a.raw['updatedAt'])),
      );
    if (cards.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('还没有角色卡可以导出')));
      return;
    }
    try {
      final path = await cardTransferIo.export(
        'coc7-characters.json',
        exportBundleJson(cards),
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? '已导出 ${cards.length} 张角色卡'
                : '已导出 ${cards.length} 张角色卡到 $path',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  /// 导入角色 JSON（单卡 / 全量都吃；导入后重新分配 id，不覆盖原卡）
  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final text = await cardTransferIo.importText();
      if (text == null) return; // 用户取消
      final cards = await importIntoRepo(repo, text);
      if (!context.mounted) return;
      final names = cards
          .map((c) => c.characterName)
          .where((n) => n.isNotEmpty)
          .join('、');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${cards.length} 张角色卡${names.isEmpty ? '' : '：$names'}',
          ),
        ),
      );
    } on CardImportError catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Expanded：窄屏（320dp）+ 大字体（textScaler 2.0）时标题会挤爆一行，
              // 标题吃掉剩余宽度并省略，绝不横向溢出（P8 窄屏检查抓到过 50px）。
              Expanded(
                child: Text(
                  '骰境TRPG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Palette.goldStr,
                    letterSpacing: 3,
                    fontFamily: serifFamily,
                  ),
                ),
              ),
              // P17 H-1：原来标题右侧还有「SizedBox(10) + 1×18 竖线 + SizedBox(10)
              // + COC 7th」，用户要求删掉「COC 7th」；竖线是它的分隔装饰，
              // 文字删了竖线就成了孤立短线，一并清掉（不留空占位）。
              // 菜单按钮是唯一入口，必须保留（多个测试依赖 Key('home_menu')）。
              PopupMenuButton<String>(
                key: const Key('home_menu'),
                icon: Icon(Icons.more_vert, size: 20, color: Palette.textDim),
                onSelected: (v) {
                  if (v == 'export_all') _exportAll(context);
                  if (v == 'import') _import(context);
                  if (v == 'check_update') showUpdateSheet(context);
                  if (v == 'settings') {
                    Navigator.of(context).pushNamed(AppRoutes.settings);
                  }
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  // P12：菜单项前置的 ⬇ / ⬆ / ⚙ 换成矢量图标（emoji 与
                  // 皮肤不搭），文案只留中文；图标色跟随次要文字色。
                  PopupMenuItem<String>(
                    key: const Key('menu_export_all'),
                    value: 'export_all',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.file_download_outlined,
                          size: 16,
                          color: Palette.textDim,
                        ),
                        const SizedBox(width: 8),
                        const Text('导出全部角色'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('menu_import'),
                    value: 'import',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.file_upload_outlined,
                          size: 16,
                          color: Palette.textDim,
                        ),
                        const SizedBox(width: 8),
                        const Text('导入角色 JSON'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    key: const Key('menu_check_update'),
                    value: 'check_update',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.system_update_alt,
                          size: 16,
                          color: Palette.textDim,
                        ),
                        const SizedBox(width: 8),
                        const Text('检查更新'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('menu_settings'),
                    value: 'settings',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.settings_outlined,
                          size: 16,
                          color: Palette.textDim,
                        ),
                        const SizedBox(width: 8),
                        const Text('设置'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
            ],
          ),
          const SizedBox(height: 6),
          // P17 H-1：版本号从原来的第三行（「克苏鲁的呼唤 第七版 · 车卡器」下方）
          // 上移到 Header 第二行，也就是用户说的「原来 COC 7th 的位置」——
          // 按**位置语义**落地：骰境TRPG（主标题）→ 版本号（副行）→ …… → 开始冒险。
          // 版本号常驻首页：用户报问题时只需说「哪个版本」，不用再翻设置或翻安装包。
          // 真值来自 app_version.dart，由 test/app_version_test.dart 与 pubspec.yaml 对齐；
          // 该测试按 Key + kAppVersionLabel 逐字比对、不断言位置，所以 key 与文案都不许动。
          Text(
            kAppVersionLabel,
            key: const Key('home_app_version'),
            style: TextStyle(
              fontSize: 11,
              color: Palette.textMute.withValues(alpha: 0.8),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
