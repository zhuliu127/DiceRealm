// ============================================================
// room_theme.dart — 房间 UI 主题常量（纯 Dart，零 Flutter 依赖）
//
// ★ 为什么整份文件保持纯 Dart：view/（纯视图层）与 painter/ 都要取
//   「画笔色板 / 面板尺寸」，若这里引入 UI 框架，view/ 就会间接依赖它，
//   纯 Dart 单测不再成立。颜色在 view/ 里只当数据（hex / RgbColor），
//   到 widget / painter 层才转换成真正的 Color。
// ============================================================

/// KP 画笔 6 色，前 5 色沿用既有顺序语义（索引即
/// `RoomUiLocal.toolColorIndex`）。第 6 色 `#e67e22`（Flat-UI carrot 橙）
/// 为本期新增：老 APP `drawColors` 只有 5 色且色值全不同，无可沿用的第 6 色。
/// ★ 顺序即协议：前 5 色的索引 0–4 逐字不动，新增色只追加在末尾；
///   [RoomTheme.drawColor] 的越界夹取按 `kDrawColors.length` 自动适配 6 色。
const List<String> kDrawColors = <String>[
  '#e74c3c',
  '#f1c40f',
  '#2ecc71',
  '#3498db',
  '#9b59b6',
  '#e67e22',
];

/// 房间 UI 的尺度 / 上限常量。
class RoomTheme {
  const RoomTheme._();

  static const double panelRadius = 12;
  static const double panelGap = 8;
  static const double tapMinSize = 48;
  static const double mapAspect = 16 / 9;
  static const double zoomMin = 0.6;
  static const double zoomMax = 1.0;

  static const int feedCap = 120;
  static const int chatCap = 60;
  static const int privateCap = 12;
  static const int imageMaxBytes = 2 * 1024 * 1024;

  /// feed 的 kind → 中文短标签（只用于分组标题，不参与逻辑）。
  static const Map<String, String> feedLabels = <String, String>{
    'sys': '系统',
    'info': '信息',
    'note': '笔记',
    'chat': '聊天',
    'dice': '骰子',
    'check': '检定',
    'opposed': '对抗',
  };

  /// 取画笔色；索引越界夹回合法范围，永远有返回值。
  static String drawColor(int index) {
    if (kDrawColors.isEmpty) return '#e74c3c';
    var i = index;
    if (i < 0) i = 0;
    if (i >= kDrawColors.length) i = kDrawColors.length - 1;
    return kDrawColors[i];
  }

  /// `#rrggbb` / `#aarrggbb` → 0xAARRGGBB。非法输入回退不透明黑色，
  /// widget / painter 层可直接用 `Color(argb)` 构造。
  static int colorArgb(String hex) {
    var s = hex.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'ff$s';
    if (s.length != 8) return 0xff000000;
    final v = int.tryParse(s, radix: 16);
    return v ?? 0xff000000;
  }

  /// 画笔索引 → 0xAARRGGBB。
  static int drawColorArgb(int index) => colorArgb(drawColor(index));
}
