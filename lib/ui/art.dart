// ============================================================
// art.dart — 美术资源路径的**单一真源** + 安全加载组件
//
// 为什么集中在这里：
//   · 资源路径散落在各页面会让改名变成全库搜索；这里一处改完全生效。
//   · `Image.asset` 直接写死路径，缺图时会在运行期抛异常；本文件统一用
//     [ArtImage] 兜底 —— 缺图/解码失败都只是**不显示**，绝不让页面崩。
//     widget 测试里资源可能不可用，这条兜底同时保护 1565 组测试。
//
// 资源来源：`ui_asset_plan.md` 清单 → `ui_assets/` 素材包 →
//   压缩后落到 `assets/images/`（转 WebP 控制包体，18.4MB → 6.1MB）。
// ============================================================

import 'package:flutter/material.dart';

/// 所有资源路径。命名与清单一致：`分组_用途_比例`。
class Art {
  const Art._();

  // ---------- A 首页 ----------
  static const String appBg = 'assets/images/a_home/a1_app_bg_9x16.webp';
  static const String appBgLight = 'assets/images/a_home/a1_app_bg_light_9x16.webp';
  static const String homeHeader = 'assets/images/a_home/a2_home_header_3x1.webp';
  static const String sectionHeader = 'assets/images/a_home/a3_section_header_6x1.webp';
  static const String emptyCards = 'assets/images/a_home/a5_home_empty_cards_1x1.png';
  static const String emptyValhalla = 'assets/images/a_home/a6_home_empty_valhalla_1x1.png';

  // 首页两个分类的分区头图（6:1 细长装饰条，文字由 App 渲染）
  static const String sectionAdventure =
      'assets/images/a_home/a3_section_adventure_6x1.webp';
  static const String sectionAdventureLight =
      'assets/images/a_home/a3_section_adventure_light_6x1.webp';
  static const String sectionArchive =
      'assets/images/a_home/a3_section_archive_6x1.webp';
  static const String sectionArchiveLight =
      'assets/images/a_home/a3_section_archive_light_6x1.webp';

  /// 「开始冒险」分区头图（两套皮肤）
  static String sectionAdventureFor(Brightness b) =>
      pick(sectionAdventure, sectionAdventureLight, b);

  /// 「角色档案」分区头图（两套皮肤）
  static String sectionArchiveFor(Brightness b) =>
      pick(sectionArchive, sectionArchiveLight, b);

  static const String bannerRoom = 'assets/images/a_home/a_home_banner_room_2x1.webp';
  static const String bannerAi = 'assets/images/a_home/a_home_banner_ai_2x1.webp';
  static const String bannerRandom = 'assets/images/a_home/a_home_banner_random_2x1.webp';
  static const String bannerWizard = 'assets/images/a_home/a_home_banner_wizard_2x1.webp';
  static const String bannerValhalla = 'assets/images/a_home/a_home_banner_valhalla_2x1.webp';

  // 亮色皮肤的同款横幅（同一套几何锁定，只换配色）
  static const String bannerRoomLight =
      'assets/images/a_home/a_home_banner_room_light_2x1.webp';
  static const String bannerAiLight = 'assets/images/a_home/a_home_banner_ai_light_2x1.webp';
  static const String bannerRandomLight =
      'assets/images/a_home/a_home_banner_random_light_2x1.webp';
  static const String bannerWizardLight =
      'assets/images/a_home/a_home_banner_wizard_light_2x1.webp';
  static const String bannerValhallaLight =
      'assets/images/a_home/a_home_banner_valhalla_light_2x1.webp';

  /// 按当前皮肤取入口横幅（两套都必要，与 [pick] 语义一致）
  static String banner(String dark, String light, Brightness b) =>
      b == Brightness.dark ? dark : light;

  /// 按当前皮肤取全站背景图。
  static String appBgFor(Brightness b) =>
      b == Brightness.dark ? appBg : appBgLight;

  /// 按当前皮肤取同一用途的两套图。
  ///
  /// [light] 传 `null` 表示「还没有亮色版」—— 此时回退暗色图（宁可图不对味，
  /// 也不要整块空白：`ArtImage` 缺图是静默不显示的）。
  static String pick(String dark, String? light, Brightness b) =>
      b == Brightness.dark ? dark : (light ?? dark);

  // ---------- B 角色卡 ----------
  static const String cardFace = 'assets/images/b_card/b1_card_face_3x4.webp';
  static const String cardFaceLight =
      'assets/images/b_card/b1_card_face_light_3x4.webp';
  static const String cardTile = 'assets/images/b_card/b2_card_tile_6x1.webp';
  static const String cardBack = 'assets/images/b_card/b3_card_back_3x4.webp';
  static const String cardBackLight =
      'assets/images/b_card/b3_card_back_light_3x4.webp';
  static const String avatarDefault = 'assets/images/b_card/b4_avatar_default_1x1.png';
  static const String avatarFrame = 'assets/images/b_card/b5_avatar_frame_1x1.png';
  static const String rippedStamp = 'assets/images/b_card/b8_ripped_stamp_1x1.png';

  /// 卡面底纹（两套皮肤）
  static String cardFaceFor(Brightness b) => pick(cardFace, cardFaceLight, b);

  /// 卡背（两套皮肤）
  static String cardBackFor(Brightness b) => pick(cardBack, cardBackLight, b);

  // ---------- C 车卡 ----------
  static const String wizardHeader = 'assets/images/c_wizard/c1_wizard_header_3x1.webp';
  static const String wizardHeaderLight =
      'assets/images/c_wizard/c1_wizard_header_light_3x1.webp';

  /// 向导头图（两套皮肤）
  static String wizardHeaderFor(Brightness b) =>
      pick(wizardHeader, wizardHeaderLight, b);
  static const String wizardProgress = 'assets/images/c_wizard/c3_wizard_progress_12x1.webp';
  static const String wizardDone = 'assets/images/c_wizard/c4_wizard_done_1x1.png';
  static const String aiLoading = 'assets/images/c_wizard/c7_ai_loading_1x1.png';

  // ---------- 首页「角色档案」两个入口横幅（2:1，两套皮肤） ----------
  //
  // 规则卡面（`ruleCardFor`）在下方 `_ruleCards` 表里实现，
  // 这里只保留首页用的两张，避免同文件两套映射。

  /// 首页「已保存的角色卡」入口横幅。
  static const String homeBannerCards =
      'assets/images/a_home/a_home_banner_cards_2x1.webp';
  static const String homeBannerCardsLight =
      'assets/images/a_home/a_home_banner_cards_light_2x1.webp';

  static String homeBannerCardsFor(Brightness b) =>
      pick(homeBannerCards, homeBannerCardsLight, b);

  /// 首页「英灵殿」入口横幅（2:1，两套皮肤）。素材早已入包，此前未接。
  static const String homeBannerValhalla =
      'assets/images/a_home/a_home_banner_valhalla_2x1.webp';
  static const String homeBannerValhallaLight =
      'assets/images/a_home/a_home_banner_valhalla_light_2x1.webp';

  static String homeBannerValhallaFor(Brightness b) =>
      pick(homeBannerValhalla, homeBannerValhallaLight, b);

  // ---------- D 房间招募期 ----------
  /// 房间入口页头图（创建 / 加入那一页）。两套皮肤各一张：
  /// 暗色是原来的金色线稿酒馆长桌；亮色是 P11 补的暖米色日光版 ——
  /// 原先亮色复用暗色图，在象牙底上像一块"黑色补丁"（用户明确提过）。
  static const String roomEntryHeader =
      'assets/images/d_lobby/d1_room_entry_header_3x1.webp';
  static const String roomEntryHeaderLight =
      'assets/images/d_lobby/d1_room_entry_header_light_3x1.webp';

  static String roomEntryHeaderFor(Brightness b) =>
      pick(roomEntryHeader, roomEntryHeaderLight, b);

  static const String lobbyHeader = 'assets/images/d_lobby/d2_lobby_header_16x9.webp';
  static const String lobbyHeaderLight =
      'assets/images/d_lobby/d2_lobby_header_light_16x9.webp';

  /// 大厅头图（两套皮肤）
  static String lobbyHeaderFor(Brightness b) =>
      pick(lobbyHeader, lobbyHeaderLight, b);
  static const String lobbySeat = 'assets/images/d_lobby/d4_lobby_seat_3x4.webp';

  // ---------- E 房间游戏期 ----------
  static const String gameBg = 'assets/images/e_game/e1_game_bg_9x16.webp';
  static const String gameBgLight = 'assets/images/e_game/e1_game_bg_light_9x16.webp';
  static const String gameBgLand = 'assets/images/e_game/e2_game_bg_land_16x9.webp';
  static const String gameBgLandLight =
      'assets/images/e_game/e2_game_bg_land_light_16x9.webp';

  /// 游戏页背景（两套皮肤 × 横竖两版）。
  /// [landscape] 为 true 时按屏幕方向取 16:9 横版，避免 9:16 竖图在横屏被
  /// `BoxFit.cover` 上下各裁约 31%；横屏暗 / 亮各有一张专属横版，亮色不再
  /// 回退竖版（P15：让金色装饰在两台设备 × 横竖两种朝向下都完整可见）。
  /// 竖屏仍取 9:16 竖版，暗 / 亮各一张，逻辑逐字不变。
  static String gameBgFor(Brightness b, {bool landscape = false}) {
    if (!landscape) return pick(gameBg, gameBgLight, b);
    return pick(gameBgLand, gameBgLandLight, b);
  }
  static const String stageDefault = 'assets/images/e_game/e3_stage_default_16x9.webp';
  static const List<String> stageSets = <String>[
    'assets/images/e_game/e3_stage_default_16x9.webp',
    'assets/images/e_game/e4_stage_forest_16x9.webp',
    'assets/images/e_game/e4_stage_cellar_16x9.webp',
    'assets/images/e_game/e4_stage_library_16x9.webp',
    'assets/images/e_game/e4_stage_coast_16x9.webp',
    'assets/images/e_game/e4_stage_street_16x9.webp',
  ];
  static const String stageEmpty = 'assets/images/e_game/e5_stage_empty_1x1.png';
  static const String topbar = 'assets/images/e_game/e6_topbar_4x1.webp';
  static const String statusBar = 'assets/images/e_game/e7_status_bar_4x1.webp';
  static const String diceBar = 'assets/images/e_game/e8_dice_bar_4x1.webp';
  static const String kpTools = 'assets/images/e_game/e10_kp_tools_3x4.webp';
  static const String seatCard = 'assets/images/e_game/e11_seat_card_3x4.webp';
  static const String plCharCard = 'assets/images/e_game/e12_pl_char_card_3x4.webp';
  static const String toolbar = 'assets/images/e_game/e16_toolbar_8x1.webp';
  static const String sceneCheck = 'assets/images/e_game/e17_scene_check_3x2.webp';

  // ---- 栏位面板装饰边框（暗 / 亮两套，1:1 方形，供 SectionBox 铺底）----
  // 用于跑团房间所有栏位卡片（KP + 玩家视角、各弹层 SectionBox 共用）。
  // 用 `BoxFit.fill` 拉伸铺满卡片：四角花饰固定在四角，中央为平静渐变，
  // 因此任意长宽比都不丢边框、也不喧宾夺主（中央留白给正文）。
  static const String panelFrameDark =
      'assets/images/e_game/e19_panel_frame_dark_1x1.webp';
  static const String panelFrameLight =
      'assets/images/e_game/e19_panel_frame_light_1x1.webp';

  /// 栏位卡片底纹（按当前皮肤取；缺亮色版则回退暗色）。
  static String panelFrameFor(Brightness b) =>
      pick(panelFrameDark, panelFrameLight, b);

  // ---- 按钮底板纹理（暗 / 亮两套，2:1 宽版，供 RoomButtonSkin 铺底）----
  // 一条细金描边内框 + 极轻的顶部高光（emboss），中央平整留给图标与文字。
  // 铺在所有 RoomTap（140+ 个可点件）的底色上，视觉与栏位边框统一为维多利亚金线。
  static const String btnPlateDark =
      'assets/images/e_game/e20_btn_dark_2x1.webp';
  static const String btnPlateLight =
      'assets/images/e_game/e20_btn_light_2x1.webp';

  /// 按钮底板纹理（按当前皮肤取；缺亮色版则回退暗色）。
  static String btnPlateFor(Brightness b) =>
      pick(btnPlateDark, btnPlateLight, b);



  // ---- P20 需求 2：5 类关键事件横幅的 16:9 底图 ----
  // 文字**由 App 生成并画在图下方**（不烘焙进图里），所以这 5 张只出画面。
  // ★ 纯 Dart 的 `critical_event_tracker.dart` 里有一份逐字相同的镜像
  //   （`EventBannerArt`，因为那个文件不能 import 本文件——本文件带
  //   `package:flutter`）。改动路径时**两处一起改**；也可以在接 tracker 时
  //   用 `CriticalEventTracker(artOf: ...)` 注入这里的常量，让 `Art` 保持
  //   单一真源。
  /// 进入战斗。
  static const String e18BannerCombat =
      'assets/images/e_game/e18_banner_combat_16x9.webp';

  /// 战斗结束。
  static const String e18BannerCombatEnd =
      'assets/images/e_game/e18_banner_combat_end_16x9.webp';

  /// 角色死亡。
  static const String e18BannerDeath =
      'assets/images/e_game/e18_banner_death_16x9.webp';

  /// 临时 / 不定疯狂、获得新疯狂症状。
  static const String e18BannerMadness =
      'assets/images/e_game/e18_banner_madness_16x9.webp';

  /// 永久疯狂（SAN 归零 → 撕卡）。
  static const String e18BannerRipped =
      'assets/images/e_game/e18_banner_ripped_16x9.webp';

  // ---------- F 通用 ----------
  static const String sheetHeader = 'assets/images/f_common/f1_sheet_header_16x9.webp';
  static const String sheetHeaderLight =
      'assets/images/f_common/f1_sheet_header_light_4x1.webp';
  static const String stateLoading = 'assets/images/f_common/f3_state_loading_1x1.png';
  static const String stateEmpty = 'assets/images/f_common/f4_state_empty_1x1.png';
  static const String stateError = 'assets/images/f_common/f5_state_error_1x1.png';
  static const String stateErrorLight =
      'assets/images/f_common/f5_state_error_light_1x1.png';

  /// 错误态插画（两套皮肤）
  static String stateErrorFor(Brightness b) =>
      pick(stateError, stateErrorLight, b);
  static const String divider = 'assets/images/f_common/f6_divider_3x1.webp';

  /// 弹层头图（两套皮肤）
  static String sheetHeaderFor(Brightness b) =>
      pick(sheetHeader, sheetHeaderLight, b);

  // ---------- G 规则系统卡面（规则选择页） ----------
  static const String ruleCardCoc7 = 'assets/images/g_rules/r1_coc7_2x1.webp';
  static const String ruleCardCoc7Light =
      'assets/images/g_rules/r1_coc7_light_2x1.webp';
  static const String ruleCardDnd5e = 'assets/images/g_rules/r2_dnd5e_2x1.webp';
  static const String ruleCardDnd5eLight =
      'assets/images/g_rules/r2_dnd5e_light_2x1.webp';
  static const String ruleCardCustom = 'assets/images/g_rules/r3_custom_2x1.webp';
  static const String ruleCardCustomLight =
      'assets/images/g_rules/r3_custom_light_2x1.webp';

  static const Map<String, List<String>> _ruleCards = <String, List<String>>{
    'coc7': <String>[ruleCardCoc7, ruleCardCoc7Light],
    'dnd5e': <String>[ruleCardDnd5e, ruleCardDnd5eLight],
    'custom': <String>[ruleCardCustom, ruleCardCustomLight],
  };

  /// 某条规则的卡面图（2:1，按当前皮肤取）。
  ///
  /// 未登记的 id 回退到通用卡面底纹 —— 以后新增规则先有卡面再补图也不会空屏。
  static String ruleCardFor(String ruleId, Brightness b) {
    final List<String>? pair = _ruleCards[ruleId];
    if (pair == null) return cardFaceFor(b);
    return pick(pair[0], pair[1], b);
  }

  // ---------- 图标 ----------
  static String die(String name) => 'assets/images/icons/dice/$name.png';
  static String wizardIcon(String name) => 'assets/images/icons/wizard/$name.png';
  static String icon(String name) => 'assets/images/icons/general/$name.png';
  static String badge(String name) => 'assets/images/icons/badge/$name.png';
  static String shareState(String name) => 'assets/images/icons/share/$name.png';
}

/// 安全图片：缺图 / 解码失败 / 测试环境无 asset bundle 时**静默不显示**，
/// 绝不抛异常打断页面构建（这是能放心铺进全站的前提）。
class ArtImage extends StatelessWidget {
  const ArtImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.opacity,
    this.fallback,
  });

  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final double? opacity;

  /// 缺图 / 解码首帧前的替代内容。
  ///
  /// 默认 `null` → 保持老行为（铺一层跟随皮肤的表面色）。
  /// 需要「图没了也要有语义标记」的调用点可以传一个**矢量图标**；
  /// 不要传 emoji 文本 —— 各设备字形不一致，和线稿素材也不搭。
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    Widget img = Image.asset(
      path,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      // 缺图不是崩溃理由，但也**不能返回透明** —— 透明会露出父级深色底，
      // 在亮色皮肤下就是一块黑（用户亲眼所见）。这里同样铺皮肤表面色。
      errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
          fallback ??
          ColoredBox(
            color: Theme.of(c).colorScheme.surfaceContainerHighest,
          ),
      // ★ P8 修复「亮色下头图先是一块黑的，过一下才出来」：
      //   Image.asset 解码是**异步**的，第一帧到达前 Image 没有内容，
      //   于是露出父级底色 —— 暗色皮肤下正好是深蓝、亮色皮肤下就是一块
      //   突兀的黑。这里在解码期铺一层**跟随皮肤的**表面色，出图时再换成
      //   真图，视觉上就是「底色 → 淡入图片」，而不是「黑块 → 跳变」。
      frameBuilder: (BuildContext c, Widget child, int? frame, bool sync) {
        if (sync || frame != null) return child;
        return fallback ??
            ColoredBox(
              color: Theme.of(c).colorScheme.surfaceContainerHighest,
            );
      },
    );
    if (opacity != null) {
      img = Opacity(opacity: opacity!, child: img);
    }
    return img;
  }
}

/// 把图片铺成装饰背景（用于 Container.decoration）
DecorationImage? artDecoration(
  String path, {
  BoxFit fit = BoxFit.cover,
  Alignment alignment = Alignment.center,
  double opacity = 1,
}) {
  // 这里不能兜底错误，所以调用方仍需保证路径存在；
  // 缺图时 Flutter 只是在 decoration 层记一条错误，不会崩。
  return DecorationImage(
    image: AssetImage(path),
    fit: fit,
    alignment: alignment,
    opacity: opacity,
    onError: (Object e, StackTrace? s) {},
  );
}
