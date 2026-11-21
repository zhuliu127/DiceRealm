// ============================================================
// widgets/gp_topbar.dart — 块 1（两侧共用）房间顶栏（设计 §2.5 / T02-S2.3）
//
// 内容（PRD 附录 A.1 块 1）：
//   房间名 · 房间号 · 身份行 · 角色 · 模式 · 回合 · 场景 · 观众数 · 连接态三档
//   + 服务地址块（**仅 KP** 渲染）。
//
// ★ 只画、只读：状态一律取自 RoomScope 里的会话快照与纯视图函数
//   （view/room_view.dart）；本文件零权威端引用、零规则调用、零写入。
// ★ P0-04：连接态三档（连接中 / 在线 / 补拉中 / 离线）必须始终可见 ——
//   顶栏由页面钉在顶部（不进滚动区），所以「始终可见」是结构保证而不是样式巧合。
// ★ T-43：所有可点元素走 RoomTap（≥48dp 热区），禁止裸 IconButton。
//
// ★ P10 第 6 期（布局专项，用户原话「这些信息可以摆在一行，但是占了 3 行，
//   压缩了下方栏位的空间」）：
//   · 宽档（可用宽度 ≥ [GpTopbar.oneLineMinWidth] = 900dp，覆盖 KP 平板横屏
//     1524dp / 1280dp）：全部信息压成**一行**；KP 服务地址收进同一行的
//     「可省略胶囊」，不再单独吃第三行。
//   · 窄档（< 900dp，含荣耀 Magic9 手机竖屏 412dp）：压成**两行**
//     ——「房间标识行」+「状态行」；观众数不再被挤到第三行。
//     换档口径写死在 [GpTopbar.oneLineMinWidth]，没有第三种行数。
//   · 文字与 4×1 头图匹配：整条顶栏先垫一层半透明底色 + 低透明度头图，
//     每个信息再套圆角胶囊底衬 + 文字阴影/描边感，亮暗两套皮肤都由
//     Palette 派生；文字不再直接压在装饰纹样上。
//   · 全部 [GpTopbarKeys]、全部文案（Text.data 保持完整，仅视觉省略）、
//     构造参数与调用方签名一律不变；观众数 [RoomTap] 热区仍是既有 56×32。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_types.dart';
import '../../../theme.dart' show Palette;
import '../../art.dart';
import '../room_scope.dart';
import '../room_session.dart' show RoomLinkState;
import '../view/room_view.dart';
import '../view/scene_view.dart' show sceneOf;
import 'room_panel_kit.dart';

/// 顶栏内部的稳定 key（容器 key 由页面挂在槽位上，见 RoomKeys）。
class GpTopbarKeys {
  const GpTopbarKeys._();

  static const Key roomName = ValueKey<String>('gpTopbar/roomName');
  static const Key roomCode = ValueKey<String>('gpTopbar/roomCode');
  static const Key who = ValueKey<String>('gpTopbar/who');

  /// ★ P10 第 7 期：`role` 胶囊已撤除渲染（用户实测「『KP·KP 主持』与
  ///   『角色：主持人』重复」，身份行 whoLine 已含角色）。常量保留，
  ///   供「旧的必须消失」的反向断言使用；不代表还有 UI 在用。
  static const Key role = ValueKey<String>('gpTopbar/role');
  static const Key mode = ValueKey<String>('gpTopbar/mode');
  static const Key round = ValueKey<String>('gpTopbar/round');
  static const Key scene = ValueKey<String>('gpTopbar/scene');
  static const Key link = ValueKey<String>('gpTopbar/link');
  static const Key spectators = ValueKey<String>('gpTopbar/spectators');

  /// ★ P10 第 7 期：服务行已整体撤除（用户原话「这个也可以删掉」）。
  ///   常量保留供反向断言；不代表还有 UI 在用。
  static const Key service = ValueKey<String>('gpTopbar/service');
}

/// 连接态 → 中文文案（三档，`online` 是 `connected` 的别名，不另算一档）。
String roomLinkText(RoomLinkState value) {
  switch (value) {
    case RoomLinkState.connecting:
      return '连接中';
    case RoomLinkState.connected:
      return '在线';
    case RoomLinkState.resync:
      return '补拉中';
    case RoomLinkState.offline:
      return '离线';
  }
}

/// 连接态 → 语义色（红/黄/绿三档一眼可分）。
Color roomLinkColor(RoomLinkState value, ColorScheme scheme) {
  switch (value) {
    case RoomLinkState.connected:
      return const Color(0xff2ecc71);
    case RoomLinkState.resync:
      return const Color(0xfff1c40f);
    case RoomLinkState.offline:
      return scheme.error;
    case RoomLinkState.connecting:
      return scheme.outline;
  }
}

/// 顶栏胶囊的亮暗两套取色（唯一取色处，避免每处手写 rgba 跑偏）。
@immutable
class _TopbarInk {
  const _TopbarInk._({
    required this.scrim,
    required this.chip,
    required this.chipEdge,
    required this.ink,
    required this.emphasis,
    required this.shade,
    required this.imageOpacity,
  });

  /// 头图下面那层半透明底衬（把 4×1 纹样压成背景而不是前景）。
  final Color scrim;

  /// 单条信息的胶囊底色 / 描边色。
  final Color chip;
  final Color chipEdge;

  /// 正文色 / 强调色（房间名）。
  final Color ink;
  final Color emphasis;

  /// 文字阴影色（做「描边」观感，不与头图纹样糊在一起）。
  final Color shade;

  final double imageOpacity;

  factory _TopbarInk.of(bool dark) {
    if (dark) {
      return const _TopbarInk._(
        scrim: Color(0xCC0B1119),
        chip: Color(0xE6101420),
        chipEdge: Color(0x59D4A94A),
        ink: Color(0xFFE8EEF7),
        emphasis: Color(0xFFF0C96A),
        shade: Color(0xFF000000),
        imageOpacity: 0.20,
      );
    }
    return const _TopbarInk._(
      scrim: Color(0xCCFFFCF5),
      chip: Color(0xE6FFFDF7),
      chipEdge: Color(0x806B5836),
      ink: Color(0xFF2C2240),
      emphasis: Color(0xFF8A6116),
      shade: Color(0xFFFFFFFF),
      imageOpacity: 0.14,
    );
  }

  /// 描边感：亮色皮肤用浅色外发光，暗色皮肤用深色外发光。
  List<Shadow> get shadows => <Shadow>[
        Shadow(offset: const Offset(0.5, 0.5), blurRadius: 1.2, color: shade),
        Shadow(offset: const Offset(-0.4, -0.4), blurRadius: 0.8, color: shade),
      ];
}

/// 一帧顶栏所需的全部纯数据（从 session / view 层取好后一次传下去）。
@immutable
class _TopbarData {
  const _TopbarData({
    required this.name,
    required this.code,
    required this.who,
    required this.mode,
    required this.round,
    required this.scene,
    required this.spectators,
    required this.link,
    required this.isKp,
  });

  final String name;
  final String code;
  final String who;
  final String mode;
  final String round;
  final String scene;
  final String spectators;
  final RoomLinkState link;
  final bool isKp;
}

/// 块 1：房间顶栏。
class GpTopbar extends StatelessWidget {
  const GpTopbar({super.key, this.serviceBase = '', this.onSpectatorsTap});

  /// KP 的服务地址（P5 无传输层，默认空 → 显示「本机进程内」）。
  final String serviceBase;

  /// 点观众数 → 只读弹层（由页面注入；null 时该数字不可点）。
  final VoidCallback? onSpectatorsTap;

  /// 单行档的最小可用宽度。
  ///
  /// ≥ 900dp（KP 平板横屏 1524×1016 / 1280×800）→ **一行**；
  /// < 900dp（荣耀 Magic9 竖屏 412dp）→ **两行**。
  /// 阈值以上用 Row（长文本胶囊可省略），以下用两行 Row，不再有第三行。
  static const double oneLineMinWidth = 900;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final session = scope.session;
    final state = session.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final role = session.role;
    final isKp = role == RoomRole.kp;

    final rawName = roomNameOf(state);
    final scene = sceneOf(state);
    final sceneName = scene == null ? '' : '${scene['name'] ?? ''}';
    final data = _TopbarData(
      name: rawName.isEmpty ? '未命名房间' : rawName,
      code: codeOf(state),
      who: whoLine(state, session.seat, role),
      mode: isCombat(state) ? '模式：战斗' : '模式：探索',
      round: '第 ${roundOf(state).toInt()} 回合',
      scene: sceneName.isEmpty ? '' : '场景：$sceneName',
      spectators: '观众 ${spectatorsOf(state).length}',
      link: session.link,
      isKp: isKp,
    );
    final ink = _TopbarInk.of(Palette.isDark);

    return Material(
      color: scheme.surfaceContainerHighest,
      // 顶栏底纹（E6）：先垫半透明底色，再叠低透明度 4×1 头图 ——
      // 文字胶囊压在「底色 + 淡纹样」上，而不是压在装饰线条上。
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.scrim,
          image: DecorationImage(
            image: AssetImage(Art.topbar),
            fit: BoxFit.cover,
            opacity: ink.imageOpacity,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final oneLine = constraints.maxWidth >= oneLineMinWidth;
              return oneLine
                  ? _oneLine(context, data, ink)
                  : _twoLine(context, data, ink);
            },
          ),
        ),
      ),
    );
  }

  /// 宽档：全部信息一行（服务地址是行末的可省略胶囊）。
  Widget _oneLine(BuildContext context, _TopbarData d, _TopbarInk ink) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _flexChip(GpTopbarKeys.roomName, d.name, _titleStyle(context, ink), ink, 3),
        _gap(),
        _flexChip(GpTopbarKeys.roomCode, '房间 ${d.code}', _bodyStyle(context, ink), ink, 3),
        _gap(),
        _linkBadge(context, d.link, ink),
        _gap(),
        _flexChip(GpTopbarKeys.who, d.who, _bodyStyle(context, ink), ink, 3),
        _gap(),
        _flexChip(GpTopbarKeys.mode, d.mode, _bodyStyle(context, ink), ink, 2),
        _gap(),
        _flexChip(GpTopbarKeys.round, d.round, _bodyStyle(context, ink), ink, 2),
        if (d.scene.isNotEmpty) ...<Widget>[
          _gap(),
          _flexChip(GpTopbarKeys.scene, d.scene, _bodyStyle(context, ink), ink, 3),
        ],
        _gap(),
        _spectators(d),
      ],
    );
  }

  /// 窄档：两行 —— 房间标识行 + 状态行；不再出现第三行。
  Widget _twoLine(BuildContext context, _TopbarData d, _TopbarInk ink) {
    final body = _bodyStyle(context, ink);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _flexChip(GpTopbarKeys.roomName, d.name, _titleStyle(context, ink), ink, 3),
            _gap(),
            _flexChip(GpTopbarKeys.roomCode, '房间 ${d.code}', body, ink, 3),
            _gap(),
            _linkBadge(context, d.link, ink),
            _gap(),
            _spectators(d),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _flexChip(GpTopbarKeys.who, d.who, body, ink, 3),
            _gap(),
            _flexChip(GpTopbarKeys.mode, d.mode, body, ink, 2),
            _gap(),
            _flexChip(GpTopbarKeys.round, d.round, body, ink, 2),
            if (d.scene.isNotEmpty) ...<Widget>[
              _gap(),
              _flexChip(GpTopbarKeys.scene, d.scene, body, ink, 3),
            ],
          ],
        ),
      ],
    );
  }

  /// 观众数入口：热区维持既有 56×32（只收紧外层间距，不改口径）。
  Widget _spectators(_TopbarData d) => RoomTap(
        key: GpTopbarKeys.spectators,
        icon: Icons.visibility_outlined,
        label: d.spectators,
        hint: '查看旁观者',
        enabled: onSpectatorsTap != null,
        minSize: const Size(56, 32),
        onTap: onSpectatorsTap,
      );

  /// 连接态徽标：文案 + 圆点，三档 + 连接中；语义色不变，只加胶囊底衬。
  Widget _linkBadge(BuildContext context, RoomLinkState link, _TopbarInk ink) {
    final scheme = Theme.of(context).colorScheme;
    final color = roomLinkColor(link, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ink.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      // 与 RoomButtonSkin 同一口径：描边走 foregroundDecoration，不占尺寸。
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ink.chipEdge, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            roomLinkText(link),
            key: GpTopbarKeys.link,
            maxLines: 1,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: ink.shadows,
                ),
          ),
        ],
      ),
    );
  }

  /// 可省略胶囊（长文本）：`Flexible` 只给上限，文字短时仍按内容收紧，
  /// 文字长时 ellipsis —— 这是「宽档保证不换行」的结构保证。
  Widget _flexChip(
    Key key,
    String text,
    TextStyle style,
    _TopbarInk ink,
    int flex,
  ) {
    return Flexible(
      flex: flex,
      child: _chipBox(
        ink,
        Text(
          text,
          key: key,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }

  /// 胶囊外壳：半透明底 + 不占尺寸的描边 + 紧凑内边距。
  Widget _chipBox(_TopbarInk ink, Widget label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ink.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ink.chipEdge, width: 0.5),
      ),
      child: label,
    );
  }

  TextStyle _bodyStyle(BuildContext context, _TopbarInk ink) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 11))
          .copyWith(
        fontSize: 11,
        height: 1.15,
        color: ink.ink,
        fontWeight: FontWeight.w500,
        shadows: ink.shadows,
      );

  TextStyle _titleStyle(BuildContext context, _TopbarInk ink) =>
      (Theme.of(context).textTheme.titleSmall ?? const TextStyle(fontSize: 13))
          .copyWith(
        fontSize: 13,
        height: 1.15,
        color: ink.emphasis,
        fontWeight: FontWeight.w700,
        shadows: ink.shadows,
      );

  Widget _gap() => const SizedBox(width: 6);
}
