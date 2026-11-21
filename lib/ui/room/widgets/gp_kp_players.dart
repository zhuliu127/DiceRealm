// ============================================================
// widgets/gp_kp_players.dart — 块 7：KP 玩家信息（设计 §5 T04 / S4.4）
//
// 三条容易踩空的口径，全部走 T01 的纯视图函数，不在 widget 里二次猜：
//   ① 他人视图无 `maxSAN` → SAN 只显当前值（C2），`sanText` 内部已按
//      `MemberStats.hasMaxSan` 收口，即便传 full:true 也不会出现 '/ 60'；
//   ② 无疯狂明细 → 只显 `madnessCount`（`madnessText(self:false)`）；
//   ③ 手绘板缩略**用笔数**：PRD §6.4 的 `thumb` 恒空，必须读本机
//      只读面的 `boardBySeat[seat]['strokes']`，玩家视角回退到
//      `boardCountOf(state, seat)`（裁剪态里的笔数，不做二次隐藏）。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap;
import '../../../theme.dart' show Palette;
import '../../art.dart';
import '../../widgets/avatar_picker.dart' show AvatarThumb, memberAvatarValue;
import '../painter/stroke_painter.dart' show BoardPainter;
import '../room_scope.dart';
import '../room_ui_local.dart' show RoomUiLocal;
import '../sheets/room_sheet.dart' show showFullscreenReader;
import '../sheets/sheet_char_view.dart' show showCharViewSheet;
import '../view/member_view.dart'
    show hpText, madnessText, memberStats, mpText, sanText;
import '../view/room_view.dart' show playersOf;
import '../view/scene_view.dart' show boardCountOf;
import 'room_button_size.dart' show clampBtnText;
import 'room_panel_kit.dart' show AvatarDot, RoomTap, SectionBox;
import '../room_text.dart';

/// 块 7 内部稳定 key。
class GpKpPlayersKeys {
  const GpKpPlayersKeys._();

  // ★ 与页面槽位 key（RoomKeys.gpPlayers）区分开（同 GpKpLeft 的理由）。
  static const Key root = ValueKey<String>('gpKpPlayers/root');

  /// ★ 2.34.0 KP-5：玩家信息栏「收起 / 展开」toggle。
  ///
  /// 声明类型为 [Key]，实际值是 `ValueKey<String>`，value 为
  /// `'gpKpPlayers/collapseToggle'`。
  /// ★ 契约 §5.1 A.5：本类历史成员只有 `root/detail/board/avatar`，
  ///   **没有 `toggle`**；Wave2 请一律用本常量写断言，勿写
  ///   `GpKpPlayersKeys.toggle`（不存在，会编译失败）。
  static const Key collapseToggle =
      ValueKey<String>('gpKpPlayers/collapseToggle');

  static Key detail(String seat) =>
      ValueKey<String>('gpKpPlayers/detail/$seat');

  static Key board(String seat) => ValueKey<String>('gpKpPlayers/board/$seat');

  /// 成员头像缩略图（`gpKpPlayers/avatar/<seat>`）
  static Key avatar(String seat) => ValueKey<String>('gpKpPlayers/avatar/$seat');

  /// ★ P12 KP-7：卡片里的「角色名：xxx」行（缺失时不渲染）。
  static Key charName(String seat) =>
      ValueKey<String>('gpKpPlayers/charName/$seat');
}

/// 某座位的手绘板笔数（本机只读面优先，裁剪态回退）。
int kpBoardStrokeCount(
  Map<String, Object?> state,
  String seat, {
  Map<String, Object?>? board,
}) {
  if (board != null) return asList(board['strokes']).length;
  return boardCountOf(state, seat);
}

/// KP 玩家信息块。
///
/// ★ 2.34.0 KP-5：自带 [ListenableBuilder] 订阅 `RoomUiLocal`，读
///   `playersPanelCollapsed` / `setPlayersPanelCollapsed(bool)`（契约 I8，
///   字段由 `room_ui_local.dart` 定义，这里只按名引用、不自己定义）。
///   `const` 实例会被元素树按 identical 跳过 build —— 接线处
///   （`room_game_page.dart`，T03）必须去掉 `const GpKpPlayers()`。
/// ★ 收起态只隐藏**本块自己的 body**（`Offstage`），标题行含 toggle 常驻；
///   绝不卸载 `GpSceneCheckKp`（那是 T03 `RoomStackNode` 里共 rect 的
///   另一格，与本块子树无关）。
class GpKpPlayers extends StatelessWidget {
  const GpKpPlayers({super.key, this.stateOverride});

  /// 跨视角验数用（注入裁剪后的玩家视图）；生产不传。
  final Map<String, Object?>? stateOverride;

  @override
  Widget build(BuildContext context) {
    final RoomUiLocal local = RoomScope.of(context).local;
    // ★ 订阅层必须长在本块内：收起是纯本地态，父级不会因它重建，
    //   与 GpPlMates（gp_pl_mates.dart:40-76）同一范式。
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) => _panel(ctx),
    );
  }

  Widget _panel(BuildContext context) {
    final scope = RoomScope.of(context);
    final local = scope.local;
    final collapsed = local.playersPanelCollapsed;
    final state = stateOverride ?? scope.session.state;
    final read = scope.session.hostRead;
    final members = playersOf(state);
    final boards = read == null
        ? const <String, Map<String, Object?>>{}
        : read.boardBySeat;

    // ★ P12 KP-4 根因修复：收起态不再返回撑满整格的 `SectionBox`。
    //   `RoomStackNode` 的 `Positioned.fill` 给上层紧约束，而 `SectionBox`
    //   的 `Card` 带不透明 Material（`hitTestSelf == true`）→ 结构性吸收
    //   整格 pointer，底层 `GpSceneCheckKp` 永远拿不到命中（`Offstage`
    //   只管子树，管不到 Card 自己）。改用 `Align`（`hitTestSelf == false`）
    //   + 28dp 标题行：标题行以下区域穿透到下一个 Stack child。
    //   展开态仍用 SectionBox；`room_layout.dart` / `RoomStackNode` 零 diff，
    //   `GpSceneCheckKp` 常驻不卸载。
    if (collapsed) {
      return Align(
        key: GpKpPlayersKeys.root,
        alignment: Alignment.topLeft,
        child: SizedBox(
          height: 28,
          width: double.infinity,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child:               Row(
                children: <Widget>[
                  Expanded(
                    // ★ 2.36.0 / Q2：标题文字是纯展示区，显式不吃命中。
                    //   收起态唯一允许拦截 pointer 的是右侧的展开 toggle；
                    //   与 `_slotView` 去掉整格 ScrollView 形成双保险，让共
                    //   rect 的 `GpSceneCheckKp` 按钮 onTap / 输入框获焦真触发。
                    child: IgnorePointer(
                      child: Text(
                        '玩家信息（${members.length}）',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  RoomTap(
                    key: GpKpPlayersKeys.collapseToggle,
                    icon: Icons.expand_more,
                  label: '展开',
                  hint: '展开玩家信息',
                  minSize: const Size(72, 28),
                  onTap: () => local.setPlayersPanelCollapsed(false),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SectionBox(
      key: GpKpPlayersKeys.root,
      title: '玩家信息（${members.length}）',
      // ★ 固定 28dp 标题行（与 `_combatHeader` 的 combatHeaderHeight=28
      //   同口径）；只钳这一棵 trailing 子树的文字缩放，不抬到页面 /
      //   Theme 层、不 ClipRect 硬裁。
      trailing: SizedBox(
        height: 28,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.0,
          child: RoomTap(
            key: GpKpPlayersKeys.collapseToggle,
            icon: collapsed ? Icons.expand_more : Icons.expand_less,
            label: collapsed ? '展开' : '收起',
            hint: collapsed ? '展开玩家信息' : '收起玩家信息（只留标题行）',
            minSize: const Size(72, 28),
            onTap: () => local.setPlayersPanelCollapsed(!collapsed),
          ),
        ),
      ),
      // ★ 收起时 body 不占空间、只留标题行；用 Offstage 保留子树
      //   （不卸载、不丢滚动位置），也不碰另一格的 GpSceneCheckKp。
      child: Offstage(
        offstage: collapsed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (members.isEmpty)
              const Text('暂无玩家', style: TextStyle(fontSize: 12)),
            for (final m in members) _row(context, scope, state, m, boards),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    RoomScope scope,
    Map<String, Object?> state,
    Map<String, Object?> m,
    Map<String, Map<String, Object?>> boards,
  ) {
    final ctl = scope.controller;
    final seat = roomText(m['seat']);
    final name = roomText(m['nickname']).isEmpty
        ? seat
        : roomText(m['nickname']);
    final stats = memberStats(m);
    final strokes = kpBoardStrokeCount(state, seat, board: boards[seat]);
    // ★ KPBOARD-1：全屏只读页的真实笔迹取自本机权威副本
    //   `hostRead.boardBySeat[seat]['strokes']`，绝不读 KP 视角恒空的
    //   `state.board`。BoardPainter 自动识别分段 / 旧扁平两种载荷。
    //   （P14：载荷改为在全屏页的 ListenableBuilder 里现取，见下方 onTap，
    //   这样打开全屏期间玩家继续画也能同步；这里不再预先拼一份快照。）
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      // 席位卡底纹（E11）：clip 让底图跟着 Card 的圆角走，
      // 只叠背景，不动行内任何控件与 Key。
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(Art.seatCard),
            fit: BoxFit.cover,
            opacity: Palette.isDark ? 0.30 : 0.15,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // P10：有自定义头像就显示缩略图，没有就还是原来的首字圆点。
                  // ★ P10 第 2 期 A：本机有原图文件就走文件（高清），没有就用成员的
                  // `sheet.avatar` 缩略 dataURI（跨设备广播来的，远端玩家靠它）。
                  // 两层都拿不到才退化成首字圆点（见 memberAvatarValue 的注释）。
                  AvatarThumb(
                    key: GpKpPlayersKeys.avatar(seat),
                    relPath: memberAvatarValue(context, m),
                    name: name,
                    size: 28,
                    fallback: AvatarDot(name: name, size: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, style: const TextStyle(fontSize: 13)),
                  ),
                  RoomTap(
                    key: GpKpPlayersKeys.detail(seat),
                    label: '详情',
                    enabled:
                        ctl.gate.can('char.share') ||
                        ctl.gate.can('sheet.damage'),
                    hint: '查看人物卡',
                    onTap: () => showCharViewSheet<void>(context, seat: seat),
                  ),
                ],
              ),
              Text(
                '${hpText(stats, full: true)} · '
                '${mpText(stats, full: true)} · '
                '${sanText(stats, full: true)}',
                key: ValueKey<String>('gpKpPlayers/stats/$seat'),
                style: const TextStyle(fontSize: 11),
              ),
              Text(
                '疯狂：${madnessText(m, self: false)}',
                key: ValueKey<String>('gpKpPlayers/madness/$seat'),
                style: const TextStyle(fontSize: 11),
              ),
              // ★ P12 KP-7：角色名与玩家侧 `gp_pl_char_card.dart` 的
              //   `me['charName']` 同源（`members[].charName`）；缺则不渲染、
              //   不出空串。`clampBtnText` 只包这一行（×1.3/1.5/2.0 不溢出），
              //   长名 `maxLines:1 + ellipsis`，不硬裁、不抬到页面层。
              if (roomText(m['charName']).isNotEmpty)
                clampBtnText(
                  Text(
                    '角色名：${roomText(m['charName'])}',
                    key: GpKpPlayersKeys.charName(seat),
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '手绘板：$strokes 笔',
                      key: ValueKey<String>('gpKpPlayers/boardCount/$seat'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  // ★ P12 KP-5：卡片按钮「全屏」→「手绘板」（打开的本来
                  //   就是 `showFullscreenReader` 的手绘板，不是素材舞台）。
                  RoomTap(
                    key: GpKpPlayersKeys.board(seat),
                    label: '手绘板',
                    icon: Icons.draw,
                    hint: '全屏只读手绘板',
                    onTap: () => showFullscreenReader<void>(
                      context: context,
                      title: '手绘板 · $name',
                      // ★ 保留标题与笔数文字（FullscreenReader 缺 child 时回退用）。
                      text: '共 $strokes 笔（本机权威副本）',
                      // ★ KPBOARD-1 根因修复：原来只传 title/text、漏 child →
                      //   FullscreenReader 只显示一行文字、画面一片空白。
                      //   补 child=CustomPaint(BoardPainter(...)) 真正渲染笔迹。
                      //
                      // ★ P14 根因 2：白底**必须画在笔迹下面**。
                      //   `CustomPaint` 的绘制顺序是 painter → child，原来写的是
                      //   `CustomPaint(painter: BoardPainter, child: ColoredBox(白))`
                      //   → 白色子节点把刚画好的笔迹整块盖住，用户看到的就是
                      //   「点开手绘板一片白、玩家画的都没同步」。改成白底在外、
                      //   画布在内（painter 在上层）才看得见笔迹。
                      // ★ P14 根因 3：全屏页是独立路由，`child` 在 onTap 那一刻
                      //   构造完就固定了；玩家后续再画/擦，这里不会重画。改用
                      //   `ListenableBuilder(session)` 现取 `hostRead.boardBySeat`，
                      //   全屏打开期间笔迹也跟房间事件同步（不改协议、不给玩家
                      //   多发一份笔迹）。
                      child: ColoredBox(
                        color: Colors.white,
                        child: SizedBox.expand(
                          child: ListenableBuilder(
                            listenable: scope.session,
                            builder: (BuildContext c, Widget? _) {
                              final Map<String, Object?>? board =
                                  scope.session.hostRead?.boardBySeat[seat];
                              final List<Map<String, Object?>> live =
                                  <Map<String, Object?>>[
                                for (final raw in asList(board?['strokes']))
                                  asMap(raw),
                              ];
                              return CustomPaint(
                                painter: BoardPainter(live),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
