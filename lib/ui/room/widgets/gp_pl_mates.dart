// ============================================================
// widgets/gp_pl_mates.dart — 块 8（玩家）：队友（裁剪视图）
//
// ★ 玩家看到的是**裁剪后**的队友数据（C2 / T-14）：
//   · 他人 `maxSAN` 被裁成 null → `sanText(full: false)` 只显当前值（不出现「/」）；
//   · 他人 `sheet.madness` 明细被裁掉 → `madnessText(self: false)` 只显
//     `madnessCount`（缺键 = 0，不假设拿到全量卡）；
//   · 手绘板缩略按**笔数**（`scene.boards[seat].count`），不读他人笔迹（K12 隔离）。
//
// ★ 只画：本块零发包入口（查看详情走只读弹层）。
// ============================================================

import 'package:flutter/material.dart';

import '../room_scope.dart';
import '../view/member_view.dart'
    show hasCardVitals, hpText, madnessText, memberStats, sanText;
import '../view/room_view.dart' show findMe, playersOf, roleText;
import '../view/scene_view.dart' show boardCountOf;
import '../../widgets/avatar_picker.dart' show AvatarThumb, memberAvatarValue;
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 队友块内部稳定 key。
class GpPlMatesKeys {
  const GpPlMatesKeys._();

  static const Key root = ValueKey<String>('gpPlMates/root');
  static const Key toggle = ValueKey<String>('gpPlMates/toggle');
  static const Key empty = ValueKey<String>('gpPlMates/empty');

  /// 单个队友（`gpPlMates/row/<seat>`）。
  static Key row(String seat) => ValueKey<String>('gpPlMates/row/$seat');

  /// 队友头像缩略图（`gpPlMates/avatar/<seat>`）
  static Key avatar(String seat) =>
      ValueKey<String>('gpPlMates/avatar/$seat');
}

/// 块 8：队友列表（可收起）。
class GpPlMates extends StatelessWidget {
  const GpPlMates({super.key, this.forceOpen = false});

  /// ★ 2.42.0 / P20 需求 3⑤：强制展开（默认关闭）。
  ///
  /// 为什么需要它：[RoomUiLocal.matesOpen] 的默认值已改成 **false**
  /// （dock 右列是 `RoomStackNode` 叠放，`Positioned.fill` 给紧约束，
  /// 展开态会与场景检定栏逐像素同 rect 并把它盖死）。于是所有「不在叠放
  /// 语境里」的入口都必须自己声明「我要看列表」：
  ///   · 折叠档点开队友方块 → `openRoomSlotFullscreen` 全屏路由，
  ///     路由 body 由 `room_game_page.dart#_bodyOf(..., matesForcedOpen: true)`
  ///     传 true；否则全屏页里只有一个 28dp 标题条 + 「展开」按钮；
  ///   · 组件级单测（直接 `GpPlMates()` 断言列表内容 / 头像 / 未绑卡文案）。
  ///
  /// 纯本地 UI 开关：不写 `local.matesOpen`、不发包、不落盘 —— 点「收起」
  /// 仍只改 `local`（本块照旧自己订阅 `local` 重画）。
  final bool forceOpen;

  @override
  Widget build(BuildContext context) {
    final local = RoomScope.of(context).local;
    // ★ 本块读本地态（收起 / 展开）→ **必须自己订阅** `local`。
    //   不能指望父级重建带下来：`const` 实例会被元素树按身份（`identical`）
    //   复用、连 `build` 都不调，订阅层一定要长在本块内。
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) => _panel(ctx),
    );
  }

  /// 面板本体：在 [ListenableBuilder] 内构建，`local` 变一次就重画一次。
  Widget _panel(BuildContext context) {
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final seat = scope.session.seat;
    final local = scope.local;
    final theme = Theme.of(context);
    final mates = playersOf(state).where((m) => roomText(m['seat']) != seat).toList();

    // ★ 2.42.0 / P20 需求 3⑤：`forceOpen` 优先于本地态。
    final bool open = forceOpen || local.matesOpen;

    // ------------------------------------------------------------
    // ★ P20 需求 3⑤（裁定 D7）：收起态**不建铺满整格的 Card**。
    //
    // 改前收起是 `child: const SizedBox.shrink()` —— body 变空了，但外层
    // [SectionBox] 的 `Card` 还在：`Card` 是 `Material`，`hitTestSelf == true`，
    // 而 `RoomStackNode` 用 `Positioned.fill` 给的是**紧约束**，Card 于是自己
    // 铺满整格并结构性吸收整格 pointer ⇒ 下层（同 rect 的 `gpPlScene` 场景
    // 检定栏 / 掷骰按钮）永远拿不到命中。这就是用户说的「收起后下层点不到」。
    //
    // ★ 两个反例，别走回头路：
    //   · 只把 body 包 `Offstage`：Card 本身还在，照样吃整格；
    //   · 外层套 `AbsorbPointer`：它的 `hitTest` 直接返回 true 且**不测子树**
    //     ⇒ 下层永远点不到，**连本块的「展开」按钮自己也点不到**（永久锁死）。
    //
    // ★ 正解（逐条复刻 `gp_kp_players.dart:112-157` 的两段式）：收起态返回
    //   `Align`（`hitTestSelf == false`）+ 28dp 标题行；标题文字 `IgnorePointer`
    //   不吃命中，只有右侧「展开」`RoomTap` 吃 pointer，其余区域穿透下去。
    //   展开态仍走 [SectionBox]，与改前逐字一致。
    // ------------------------------------------------------------
    if (!open) {
      return Align(
        key: GpPlMatesKeys.root,
        alignment: Alignment.topRight,
        child: SizedBox(
          height: 28,
          width: double.infinity,
          // ★ 固定 28dp 高度是硬约束 ⇒ 只钳这一棵子树的字号缩放
          //   （P16 纪律：不抬到页面 / Theme 层、不用 ClipRect 硬裁）。
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '队友（${mates.length}）',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                RoomTap(
                  key: GpPlMatesKeys.toggle,
                  icon: Icons.expand_more,
                  label: '展开',
                  hint: '展开队友列表',
                  minSize: const Size(72, 28),
                  onTap: () => local.setMatesOpen(true),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SectionBox(
      key: GpPlMatesKeys.root,
      title: '队友（${mates.length}）',
      // ★ `forceOpen` 时不画收起按钮：此刻 `open` 恒为 true，收起点了也
      //   不会收起（会把「收起」画成一个点了没反应的死按钮）。
      //   全屏路由里没有「叠放」语境，本来也不需要收起。
      trailing: forceOpen
          ? null
          : RoomTap(
              key: GpPlMatesKeys.toggle,
              icon: open ? Icons.expand_less : Icons.expand_more,
              hint: open ? '收起队友列表' : '展开队友列表',
              minSize: const Size(44, 32),
              onTap: () => local.setMatesOpen(!open),
            ),
      child: mates.isEmpty
          ? Text(
              '还没有其他玩家',
              key: GpPlMatesKeys.empty,
              style: theme.textTheme.bodySmall,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final m in mates) _row(context, m, state),
              ],
            ),
    );
  }

  Widget _row(
    BuildContext context,
    Map<String, Object?> m,
    Map<String, Object?> state,
  ) {
    final seat = roomText(m['seat']);
    final name = roomText(m['nickname']).isEmpty ? seat : roomText(m['nickname']);
    final stats = memberStats(m);
    final theme = Theme.of(context);
    final self = findMe(state, seat) != null;

    return Padding(
      key: GpPlMatesKeys.row(seat),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          AvatarThumb(
            key: GpPlMatesKeys.avatar(seat),
            relPath: memberAvatarValue(context, m),
            name: name,
            size: 26,
            fallback: AvatarDot(name: name, size: 26),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$name（${roleText(roomText(m['role']))}）',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  // ★ 无卡成员：`memberStats` 的契约是「取不到给 0」，直接拼
                  //   `HP 0 · SAN 0` 会把「还没同步到」画成「真的 0 点血」。
                  //   判据与角色卡面板同源（`hasCardVitals`），文案保持 3 字。
                  hasCardVitals(m)
                      // ★ full:false → 他人只有当前值（maxSAN 已被裁掉）
                      ? '${hpText(stats, full: false)} · ${sanText(stats, full: false)}'
                      : '未绑卡',
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  // ★ self:false → 只显 madnessCount，不还原明细
                  '精神：${madnessText(m, self: false)}'
                  ' · 手绘板 ${boardCountOf(state, seat)} 笔'
                  '${self ? ' · 本人' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
