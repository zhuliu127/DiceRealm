// ============================================================
// view/room_view.dart — 房间级只读派生（设计 §3.6）
//
// ★ 纯 Dart：不得引入任何 UI 框架，也不得引用平台 I/O 或绘制库。
// ★ 所有函数首参恒为 `Map<String, Object?> state`，只读；返回的 Map
//   一律经 roomClone 深拷贝，绝不把 state 里的引用交给调用方。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_state.dart'
    show roomClone, roomNumber;
import 'package:dice_realm/domain/room_types.dart';
import '../room_text.dart';

/// meta 的只读副本（缺 meta 时返回空 Map，不返回 null）。
Map<String, Object?> metaOf(Map<String, Object?> state) =>
    asMap(roomClone(state['meta']));

/// 房间状态 → 中文文案（`RoomStatus.text` 的 UI 侧唯一出口）。
String roomStatusText(String status) => RoomStatus.text[status] ?? status;

/// 角色 → 中文文案。
String roleText(String role) {
  switch (role) {
    case RoomRole.kp:
      return '主持人';
    case RoomRole.player:
      return '玩家';
    case RoomRole.spectator:
      return '旁观者';
    default:
      return role;
  }
}

/// 顶栏身份行。KP 看 KP 名，玩家看自己昵称，旁观者恒为「旁观中」。
///
/// ★ P12：行首的 emoji（皇冠 / 眼睛 / 面具）已去掉 —— 这一行是纯文本，
///   顶栏里的图标由 widget 层自己画；纯视图层不再拼表情符号。
String whoLine(Map<String, Object?> state, String seat, String role) {
  final meta = metaOf(state);
  if (seat == kHostSeat || role == RoomRole.kp) {
    final kp = roomText(meta['kpName']);
    return '${kp.isEmpty ? 'KP' : kp} · KP 主持';
  }
  if (role == RoomRole.spectator) return '旁观中';
  final me = findMe(state, seat);
  final nick = me == null ? '' : roomText(me['nickname']);
  return '当前玩家：${nick.isEmpty ? seat : nick}';
}

/// 成员表的只读深拷贝。
List<Map<String, Object?>> membersOf(Map<String, Object?> state) {
  final cloned = asList(roomClone(state['members']));
  return <Map<String, Object?>>[
    for (final m in cloned) asMap(m),
  ];
}

bool _isPlayer(Map<String, Object?> m) {
  final role = roomText(m['role']);
  if (role.isNotEmpty) return role == RoomRole.player;
  // 老存档可能只有 `spec` 标记，没有 role 字段。
  return !jsTruthy(m['spec']) && roomText(m['seat']) != kHostSeat;
}

bool _isSpectator(Map<String, Object?> m) {
  final role = roomText(m['role']);
  if (role.isNotEmpty) return role == RoomRole.spectator;
  return jsTruthy(m['spec']);
}

/// 玩家成员（不含 KP、不含旁观）。
List<Map<String, Object?>> playersOf(Map<String, Object?> state) =>
    membersOf(state).where(_isPlayer).toList();

/// 旁观成员。
List<Map<String, Object?>> spectatorsOf(Map<String, Object?> state) =>
    membersOf(state).where(_isSpectator).toList();

/// 按 seat 找成员；查不到返回 null（即「旁观者 / 尚未入座」）。
Map<String, Object?>? memberOfSeat(Map<String, Object?> state, String seat) {
  for (final m in membersOf(state)) {
    if (roomText(m['seat']) == seat) return m;
  }
  return null;
}

/// [memberOfSeat] 的语义别名：找自己，查不到 = 旁观者。
Map<String, Object?>? findMe(Map<String, Object?> state, String seat) =>
    memberOfSeat(state, seat);

bool isInGame(Map<String, Object?> state) =>
    roomText(metaOf(state)['status']) == RoomStatus.inGame;

bool isCombat(Map<String, Object?> state) =>
    roomText(metaOf(state)['mode']) == RoomMode.combat;

/// 模式字符串（缺省按探索模式，绝不返回空串）。
String modeOf(Map<String, Object?> state) {
  final m = roomText(metaOf(state)['mode']);
  return m.isEmpty ? RoomMode.exploration : m;
}

String codeOf(Map<String, Object?> state) => roomText(metaOf(state)['code']);

String roomNameOf(Map<String, Object?> state) => roomText(metaOf(state)['name']);

String kpNameOf(Map<String, Object?> state) => roomText(metaOf(state)['kpName']);

num roundOf(Map<String, Object?> state) => roomNumber(metaOf(state)['round'], 0);

/// 房间内容区的布局形态（P10 第 2 期 B，用户口述「① / ②」两条）。
enum RoomLayoutMode {
  /// 平板横屏：复刻老 APP（2.13.13）的**固定比例网格**，格子之间同一 gap。
  dock,

  /// 平板竖屏 / 手机横屏 / 手机竖屏：少数面板展开 + 其余收成方块（点开全屏）。
  folded,
}

/// ★ 网格判定唯一真相源（设计 §1.5）。五档阈值只在这里出现一次，
///   `compact` 必须与 `grid` 同源：不能简化成独立的 `h <= 360`，
///   否则 520–599 的单列档也会被误判成 compact。
///
/// ★ P10 第 2 期 B：在原有 `grid` / `compact` 之上增加 [dock]，
///   **所有断点常量仍然只出现在本类**（`room_game_page.dart` 里不许再写数字）。
///   `dock` 不能只看宽度：手机横屏（如 780×320）也满足 `grid`，但按用户口径
///   它属于「折叠档」。区分靠**短边**——平板横屏短边 ≥ 560，手机横屏约 320–430。
class RoomGridSpec {
  const RoomGridSpec({
    required this.grid,
    required this.compact,
    this.dock = false,
  });

  /// 宽屏多列。
  final bool grid;

  /// 矮屏档：在 grid 成立的前提下收紧行高。
  final bool compact;

  /// 平板横屏（复刻老 APP 的固定网格）。恒 `dock → grid`。
  final bool dock;

  /// 布局形态（只读派生，**不要在别处重算**）。
  RoomLayoutMode get mode => dock ? RoomLayoutMode.dock : RoomLayoutMode.folded;

  static const double wide = 820;
  static const double narrowLo = 520;
  static const double narrowHi = 599;
  static const double minH = 290;
  static const double compactH = 360;

  /// 平板横屏的短边下限（手机横屏的短边约 320–430，落在其下）。
  static const double dockShortSide = 560;

  /// [viewportShortSide] 是**可选**的稳定短边：由调用点从页面根的
  /// `MediaQuery` 屏幕尺寸取得，不含键盘 `viewInsets`，因此输入法弹起时
  /// 不会跟着 `LayoutBuilder.maxHeight` 一起塌下去。它**只**参与 [dock]
  /// 判定；不传时逐字沿用从 `w`/`h` 推出的 shortSide（既有纯函数用例、
  /// 五档阈值、grid / compact 语义全部零影响）。
  ///
  /// ★ P11 KP-6a（P0 根因的第二道保险）：游戏页 Scaffold 已设
  ///   `resizeToAvoidBottomInset: false`（主修），这里再让 dock 判据不依赖
  ///   可能被压缩的高度，彻底杜绝「键盘弹起 → dock 翻成 folded →
  ///   `_content` 换形 → `GpSceneCheckKp` 父链整条替换、State 被 dispose」
  ///   这条失焦链。本文件仍是纯 Dart，不引入任何 UI 框架。
  static RoomGridSpec of({
    required double w,
    required double h,
    required bool landscape,
    double? viewportShortSide,
  }) {
    final wideEnough = (landscape && w >= narrowLo) || w >= wide;
    final narrowBand = w >= narrowLo && w <= narrowHi;
    final tallEnough = h >= minH;
    final grid = wideEnough && !narrowBand && tallEnough;
    final shortSide = w < h ? w : h;
    // 变量名刻意避开静态常量 `dockShortSide`，否则会遮蔽常量、判据恒真。
    final dockBasis = viewportShortSide ?? shortSide;
    return RoomGridSpec(
      grid: grid,
      compact: grid && h <= compactH,
      dock: grid && landscape && dockBasis >= dockShortSide,
    );
  }
}
