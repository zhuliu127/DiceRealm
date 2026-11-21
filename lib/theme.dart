// ============================================================
// theme.dart — 双皮肤（暗色「深渊」/ 亮色「羊皮卷」）+ 金色强调
//
// 取色源自老产品的 CSS 变量（coc7th-card-app/web/css/app.css 的 `:root`），
// 只取调色板，**不搬布局体系** —— 老页面是一整套 flex + sticky 的 Web 布局，
// Flutter 里照搬会寸步难行。这里只保留「描边 + 金线 + 衬线标题」的观感。
//
// ★ 双皮肤的实现方式（改之前务必读懂）
//   `Palette.xxx` 在 lib/ 里有 500+ 处静态引用。若把它改成
//   `Theme.of(context).extension<...>()`，等于全库重写一遍，风险远超收益。
//   所以这里保留 **`Palette.xxx` 的调用写法完全不变**，只把字段从
//   `static const` 换成读当前 [AppPalette] 的 getter：
//
//       Palette.bg  →  _current.bg
//
//   切换皮肤 = [Palette.use] 换掉 `_current`，再让 MaterialApp 换 ThemeData。
//   ThemeData 变化会让每个 `Scaffold`（它依赖 `Theme.of`）重建，其整棵子树
//   随之重新 build，`Palette.xxx` 自然取到新值。
//
//   ⚠️ 前提：**换 `_current` 必须发生在构建 ThemeData 之前**（见 [buildTheme]），
//   否则这一帧会新皮肤配旧色，出现一闪而过的错色。
// ============================================================

import 'package:flutter/material.dart';

import 'ui/art.dart';

/// 一套皮肤的完整色板。两套实例见 [AppPalette.dark] / [AppPalette.light]。
///
/// 为什么是独立类而不是 Map：字段名即语义，写错会编译报错；
/// Map 写错键名只会在运行期变成 null，那种 bug 在深色主题里极难发现。
@immutable
class AppPalette {
   const AppPalette({
    required this.brightness,
    required this.bg,
    required this.bgGradA,
    required this.bgGradB,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStr,
    required this.text,
    required this.textDim,
    required this.textMute,
    required this.gold,
    required this.goldSoft,
    required this.goldStr,
    required this.teal,
    required this.tealSoft,
    required this.danger,
    required this.dangerSoft,
    required this.success,
    required this.successSoft,
    required this.arcane,
    required this.arcaneSoft,
  });

  final Brightness brightness;

  final Color bg;
  final Color bgGradA;
  final Color bgGradB;
  final Color surface;
  final Color surface2;
  final Color surface3;

  final Color border;
  final Color borderStr;

  final Color text;
  final Color textDim;
  final Color textMute;

  final Color gold;
  final Color goldSoft;

  /// 强调金：深色下是「更亮的金」，浅色下必须反过来变成「更深的金」，
  /// 否则金色文字压在象牙底上会糊成一片。
  final Color goldStr;

  final Color teal;
  final Color tealSoft;
  final Color danger;
  final Color dangerSoft;
  final Color success;
  final Color successSoft;
  final Color arcane;
  final Color arcaneSoft;

  /// 金色按钮上的前景色
  Color get onGold =>
      brightness == Brightness.dark ? const Color(0xFF1A1408) : const Color(0xFF2A1D06);

  /// 青色按钮上的前景色
  Color get onTeal =>
      brightness == Brightness.dark ? Color(0xFF06201C) : Color(0xFF04241F);

  // ---------------- 暗色：深渊 ----------------
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B1119),
    bgGradA: Color(0xFF0D1420),
    bgGradB: Color(0xFF131C2B),
    surface: Color(0xFF161F2E),
    surface2: Color(0xFF1C2738),
    surface3: Color(0xFF233047),
    border: Color(0x17FFFFFF), // rgba(255,255,255,.09)
    borderStr: Color(0x29FFFFFF), // rgba(255,255,255,.16)
    text: Color(0xFFE8EEF7),
    textDim: Color(0xFF93A3BA),
    textMute: Color(0xFF66748C),
    gold: Color(0xFFD4A94A),
    goldSoft: Color(0x24D4A94A),
    goldStr: Color(0xFFF0C96A),
    teal: Color(0xFF46B9A8),
    tealSoft: Color(0x2446B9A8),
    danger: Color(0xFFE0605A),
    dangerSoft: Color(0x24E0605A),
    success: Color(0xFF4FB98A),
    successSoft: Color(0x244FB98A),
    arcane: Color(0xFF8A7DE0),
    arcaneSoft: Color(0x268A7DE0),
  );

  // ---------------- 亮色：羊皮卷 ----------------
  // 底色不是纯白而是暖象牙：纯白配金色会显得廉价，也压不住插图里的暖调。
  // 所有正文色对底色的对比度都 ≥ 4.5:1（WCAG AA）。
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF7F1E4),
    bgGradA: Color(0xFFFCF8F0),
    bgGradB: Color(0xFFEDE3D1),
    surface: Color(0xFFFFFCF5),
    surface2: Color(0xFFF6EFDF),
    surface3: Color(0xFFEADFCB),
    border: Color(0x1F6B5836),
    borderStr: Color(0x336B5836),
    text: Color(0xFF2C2240),
    textDim: Color(0xFF6B6079),
    textMute: Color(0xFF8B8095),
    gold: Color(0xFFB8873A),
    goldSoft: Color(0x24B8873A),
    goldStr: Color(0xFF8A5F1E),
    teal: Color(0xFF1F8C7D),
    tealSoft: Color(0x241F8C7D),
    danger: Color(0xFFBE3A2C),
    dangerSoft: Color(0x24BE3A2C),
    success: Color(0xFF2F8A62),
    successSoft: Color(0x242F8A62),
    arcane: Color(0xFF6B5BC7),
    arcaneSoft: Color(0x266B5BC7),
  );

  static AppPalette of(Brightness b) =>
      b == Brightness.dark ? dark : light;
}

/// 调色板门面：**调用写法与旧版完全一致**（`Palette.gold` 等），
/// 只是取值来自当前皮肤。这样 500+ 处引用一行都不用改。
class Palette {
  const Palette._();

  static AppPalette _current = AppPalette.dark;

  static AppPalette get current => _current;
  static Brightness get brightness => _current.brightness;
  static bool get isDark => _current.brightness == Brightness.dark;

  /// 切换当前皮肤。**必须在构建 ThemeData 之前调用**。
  static void use(AppPalette p) => _current = p;

  static void useBrightness(Brightness b) => _current = AppPalette.of(b);

  static Color get bg => _current.bg;
  static Color get bgGradA => _current.bgGradA;
  static Color get bgGradB => _current.bgGradB;
  static Color get surface => _current.surface;
  static Color get surface2 => _current.surface2;
  static Color get surface3 => _current.surface3;

  static Color get border => _current.border;
  static Color get borderStr => _current.borderStr;

  static Color get text => _current.text;
  static Color get textDim => _current.textDim;
  static Color get textMute => _current.textMute;

  static Color get gold => _current.gold;
  static Color get goldSoft => _current.goldSoft;
  static Color get goldStr => _current.goldStr;

  static Color get teal => _current.teal;
  static Color get tealSoft => _current.tealSoft;
  static Color get danger => _current.danger;
  static Color get dangerSoft => _current.dangerSoft;
  static Color get success => _current.success;
  static Color get successSoft => _current.successSoft;
  static Color get arcane => _current.arcane;
  static Color get arcaneSoft => _current.arcaneSoft;

  static Color get onGold => _current.onGold;
  static Color get onTeal => _current.onTeal;
}

/// 圆角 / 间距（与 CSS 的 --radius 族一致）
class Radii {
  const Radii._();
  static const double sm = 9;
  static const double md = 14;
  static const double lg = 20;
}

/// 衬线字族：中文优先思源宋体 / 宋体，退回系统衬线
const String serifFamily = 'serif';

TextTheme _textTheme() {
  // 标题用衬线（老产品的「克苏鲁」味全在衬线上），正文用系统无衬线。
  // 这里不能是 const：颜色来自当前皮肤。
  return TextTheme(
    displaySmall: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w600,
      color: Palette.text,
      letterSpacing: 2,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Palette.text,
      letterSpacing: 1,
    ),
    headlineSmall: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Palette.text,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: Palette.text,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: Palette.text,
    ),
    bodyLarge: TextStyle(fontSize: 15, height: 1.5, color: Palette.text),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: Palette.textDim),
    bodySmall: TextStyle(fontSize: 12.5, height: 1.45, color: Palette.textMute),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Palette.text,
    ),
  );
}

/// 按**当前皮肤**构建 ThemeData。
///
/// 调用方（[DiceRealmApp]）必须先把 `Palette.use(...)` 设好；
/// 这里再保险地按 [brightness] 同步一次，杜绝「皮肤与色板不同步」。
ThemeData buildTheme([Brightness? brightness]) {
  if (brightness != null) Palette.useBrightness(brightness);

  final bool dark = Palette.isDark;
  final base = dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

  final scheme = ColorScheme(
    brightness: Palette.brightness,
    primary: Palette.gold,
    onPrimary: Palette.onGold,
    secondary: Palette.teal,
    onSecondary: Palette.onTeal,
    // ★ P8 修复：原先只给了 secondary / onSecondary，Material 3 的
    //   ChoiceChip / FilterChip / SegmentedButton **用的是
    //   secondaryContainer / onSecondaryContainer**，缺省时框架自己从
    //   secondary 派生出一对「亮青底 + 浅青字」，两者明度接近 →
    //   选中项几乎看不清（用户截图实证：暗色、亮色都一样糊）。
    //   这里显式改成**金色系**：淡金底 + 高对比金字，和整体美术一致，
    //   而不是把青色硬调深 —— 换色比调明度更不容易再翻车。
    secondaryContainer: Palette.gold.withValues(alpha: 0.22),
    onSecondaryContainer: Palette.goldStr,
    surface: Palette.surface,
    onSurface: Palette.text,
    error: Palette.danger,
    onError: Colors.white,
    outline: Palette.borderStr,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.bg,
    dividerColor: Palette.border,
    textTheme: _textTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Palette.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: Palette.text,
        letterSpacing: 1.5,
      ),
    ),
    cardTheme: CardThemeData(
      // ★ P16 C-1：栏位背景加 85% 不透明度（alpha 0xD9），让房间背景图透出。
      //   一处覆盖所有 Card；Palette.surface 会跟随亮/暗皮肤自动切换。
      //   用 withValues 而非 withOpacity（新版已弃用）：alpha 0.85 量化成
      //   8-bit 即 0xD9（217），RGB 保持 Palette.surface 原值不变。
      color: Palette.surface.withValues(alpha: 0.85),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: Palette.border),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: Palette.textMute, fontSize: 14),
      labelStyle: TextStyle(color: Palette.textDim, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: Palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: Palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: Palette.gold, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: Palette.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.gold,
        foregroundColor: Palette.onGold,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.textDim,
        side: BorderSide(color: Palette.borderStr),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Palette.gold),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Palette.gold,
      foregroundColor: Palette.onGold,
      elevation: 3,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.surface3,
      contentTextStyle: TextStyle(color: Palette.text, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: Palette.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Palette.surface2,
      // 选中态：淡金底 + 加粗金字（见 ColorScheme 里 secondaryContainer 的注释）。
      // 之前这里没写 selectedColor / secondaryLabelStyle，Material 就会用
      // 框架派生的「亮青底 + 浅青字」，选中项几乎看不清。
      selectedColor: Palette.gold.withValues(alpha: 0.22),
      disabledColor: Palette.surface2,
      side: BorderSide(color: Palette.border),
      labelStyle: TextStyle(color: Palette.textDim, fontSize: 13),
      secondaryLabelStyle: TextStyle(
        color: Palette.goldStr,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      checkmarkColor: Palette.goldStr,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: Palette.gold),
    sliderTheme: SliderThemeData(
      activeTrackColor: Palette.gold,
      inactiveTrackColor: Palette.surface3,
      thumbColor: Palette.goldStr,
    ),
  );
}

/// 兼容旧调用名（`app.dart` 曾直接用 `buildDarkTheme()`）。
@Deprecated('改用 buildTheme()：颜色现在跟随当前皮肤')
ThemeData buildDarkTheme() => buildTheme(Brightness.dark);

/// 页面背景：美术底图（当前皮肤一套）+ 渐变叠层。
///
/// 为什么还要叠渐变：
///   · 深色底图中央本就「几乎纯暗」，但列表文字压在星点上仍会发花；
///   · 浅色底图若不压一层更亮的中央，密集表单会显得脏。
///   · 底图缺失时页面退化成纯渐变，观感与旧版一致，不会露出突兀的纯色。
class AppBackground extends StatelessWidget {
   const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool dark = Palette.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.bg,
        image: artDecoration(Art.appBgFor(Palette.brightness), fit: BoxFit.cover),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.4,
            colors: dark
                ? <Color>[
                    Palette.bgGradB.withValues(alpha: 0.42),
                    Palette.bgGradA.withValues(alpha: 0.74),
                    Palette.bg.withValues(alpha: 0.92),
                  ]
                : <Color>[
                    // 亮色：顶部让底图的星云淡彩透出，中下部用底色压稠，
                    // 保证密排正文的对比度不被花纹削弱。
                    Palette.bgGradA.withValues(alpha: 0.50),
                    Palette.bg.withValues(alpha: 0.82),
                    Palette.bg.withValues(alpha: 0.95),
                  ],
            stops: const <double>[0, 0.45, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}
