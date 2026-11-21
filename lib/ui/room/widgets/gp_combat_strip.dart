// ============================================================
// widgets/gp_combat_strip.dart — 老 APP `initiativeBar` 的行动顺序条
//
// ★ P10 第 7 期 C 批 B（用户原话「进入战斗模式，没有出现战斗轮次信息栏位」）：
//   战斗面板里原本只有一行 `第 N 轮 · 行动 x/y`，没有逐槽的行动顺序条。
//   本组件复用 `combatRows(state, isKp:)` 的只读派生（已有
//   isCurrent / hp / hpMax / hpHidden / kind / actionsPerRound），
//   每槽画：x/y（多行动时）+ 名字 + 类型 + HP 条或「隐藏」，
//   isCurrent 用 primaryContainer 高亮，横向滚动不把格子撑破。
//
// ★ 三条硬口径（与 gp_combat_list.dart 同源）：
//   ① `hpHidden` 只显示「隐藏」，绝不把缺键当成 0（K4）；
//   ② 进度条必须带 `hpMax > 0` 守卫，未知上限不画进度、不判死（S5）；
//   ③ 不读 secret / kpOnly —— 补全逻辑只在 `combatRows(isKp: true)` 里，
//      玩家侧那两块裁剪时已删，绝不越权。
//
// ★ 只画、不发意图：订阅 RoomScope 的会话通知即可，零权威端引用。
// ★ key 单独成类，让 `gp_combat_list.dart` 能单向 import 本文件而不循环。
// ============================================================

import 'package:flutter/material.dart';

import '../room_scope.dart';
import '../view/combat_view.dart' show CombatRow, combatRows, isMyTurn;

/// 行动顺序条内部稳定 key（`GpCombatKeys` 在 gp_combat_list.dart 里别名引用）。
class GpCombatStripKeys {
  const GpCombatStripKeys._();

  /// 整条顺序条的根（挂在真实 RenderObject 上，可被 getRect）。
  static const Key strip = ValueKey<String>('gpCombat/strip');

  /// 当前行动槽（唯一）。
  static const Key current = ValueKey<String>('gpCombat/strip/current');

  /// 单个槽（`gpCombat/strip/slot/<id>`）。
  static Key slot(String id) =>
      ValueKey<String>('gpCombat/strip/slot/$id');
}

/// 行动顺序条：一行横向槽位，当前槽高亮。
///
/// [isKp] 决定是否允许 `combatRows` 用 secret 补全 HP；[seat] 用于
/// 「轮到你行动了」提示（空串 = 不显示）。
class GpCombatStrip extends StatelessWidget {
  const GpCombatStrip({
    super.key,
    required this.isKp,
    this.seat = '',
  });

  final bool isKp;
  final String seat;

  @override
  Widget build(BuildContext context) {
    // ★ 订阅会话：combat.next 后 state 变化 → 本组件重算 combatRows，
    //   高亮与文案自然同步，无需本地缓存。
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final rows = combatRows(state, isKp: isKp);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final myTurn = seat.isNotEmpty && isMyTurn(state, seat);

    return Column(
      key: GpCombatStripKeys.strip,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (myTurn)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '轮到你行动了',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (rows.isEmpty)
          Text('尚未部署参战单位', style: theme.textTheme.bodySmall)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _slots(context, rows, scheme),
            ),
          ),
      ],
    );
  }

  /// 逐槽构造。多行动槽按「去掉 # 后缀的 actorId」分组累加，给出 `x/y`；
  /// 这样即便老存档的 id 没带 `#n`，也能稳定排出 1/2、2/2。
  List<Widget> _slots(
    BuildContext context,
    List<CombatRow> rows,
    ColorScheme scheme,
  ) {
    final out = <Widget>[];
    final seen = <String, int>{};
    for (final CombatRow r in rows) {
      final hash = r.id.indexOf('#');
      final base = hash >= 0 ? r.id.substring(0, hash) : r.id;
      final x = (seen[base] ?? 0) + 1;
      seen[base] = x;
      final slotNo = r.actionsPerRound > 1 ? '$x/${r.actionsPerRound} · ' : '';
      Widget tile = _slotTile(context, r, scheme, slotNo);
      if (r.isCurrent) {
        // 两个 key 都要能查到：槽自身用 slot(id)，当前态额外包一层 current。
        tile = KeyedSubtree(key: GpCombatStripKeys.current, child: tile);
      }
      out.add(tile);
    }
    return out;
  }

  /// 单槽卡片：宽度固定，绝不因文字长短把整行撑破。
  ///
  /// ★ P14 COMBAT-6（用户问题 8）：**怪物槽与玩家槽共用同一张卡壳 + 同一套
  ///   排版骨架** —— 同宽（104）、同内外边距、同边框 / 圆角、同字号层级。
  ///   差别只在内容：怪物仍只写名字（不显类型 / HP / 进度条，一个数值都不
  ///   渲染），属性行用不可见的同字号占位保留骨架高度，两种卡并排时高度、
  ///   行距、高亮样式完全一致，不再是「玩家是三行卡、怪物是一行条」。
  Widget _slotTile(
    BuildContext context,
    CombatRow r,
    ColorScheme scheme,
    String slotNo,
  ) {
    final theme = Theme.of(context);

    final String kind = r.kind == 'pc'
        ? 'PC'
        : (r.kind == 'monster' ? '怪物' : 'NPC');
    // ① K4：隐藏时只给「隐藏」，一个数字都不露。
    final String hpText = r.hpHidden
        ? '隐藏'
        : (r.hpMax > 0
            ? 'HP ${_fmt(r.hp)}/${_fmt(r.hpMax)}'
            : 'HP ${_fmt(r.hp)}');
    final Color bg = r.isCurrent
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final Color fg = r.isCurrent
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final Color outline =
        r.isCurrent ? scheme.primary : scheme.outlineVariant;
    final TextStyle? nameStyle = theme.textTheme.bodySmall?.copyWith(
      color: fg,
      fontWeight: r.isCurrent ? FontWeight.w700 : FontWeight.w400,
    );
    final TextStyle? attrStyle =
        theme.textTheme.bodySmall?.copyWith(color: fg, fontSize: 10);

    // 骨架公用：名字行 + 两条属性行 + 进度条位。怪物侧属性行留空占位。
    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          // 「只显示名字」是内容差异，骨架一致；多行动 x/y 只给有属性的槽。
          r.playerNameOnly
              ? (r.name.isEmpty ? r.id : r.name)
              : '$slotNo${r.name.isEmpty ? r.id : r.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: nameStyle,
        ),
        const SizedBox(height: 2),
        r.playerNameOnly
            ? _blankLine(attrStyle)
            // ★ P14：属性行也锁成单行 —— 固定 104 宽里「HP 12/120」在
            //   textScaler 1.3+ 会折成两行，把玩家卡顶高（与怪物卡错位）。
            : _attrLine(kind, attrStyle),
        const SizedBox(height: 2),
        r.playerNameOnly
            ? _blankLine(attrStyle)
            : _attrLine(hpText, attrStyle),
        // ② hpMax <= 0 不画进度条（未知上限 ≠ 空血）。
        //   怪物侧留同高空位，保证两种卡高度一致（不画任何进度）。
        if (!r.playerNameOnly && !r.hpHidden && r.hpMax > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 88,
              height: 3,
              child: LinearProgressIndicator(
                value: (r.hp / r.hpMax).clamp(0.0, 1.0),
                minHeight: 3,
                color: scheme.primary,
                backgroundColor: scheme.outlineVariant,
              ),
            ),
          )
        else if (r.playerNameOnly)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: SizedBox(width: 88, height: 3),
          ),
      ],
    );

    return Container(
      key: GpCombatStripKeys.slot(r.id),
      width: 104,
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: outline),
      ),
      child: body,
    );
  }

  /// 占位行：与属性行同字号同色的一行空白（不渲染任何属性文字）。
  ///
  /// 用它而不是固定 `SizedBox(height:)`：textScaler 1.3 / 1.5 / 2.0 时四种
  /// 字号的真实行高由 TextPainter 自己算，占位与属性行恒等高，玩家槽与怪物槽
  /// 永远不会一高一矮，也不会因写死高度而溢出。
  static Widget _blankLine(TextStyle? style) =>
      Text('\u00A0', maxLines: 1, style: style);

  /// 属性行：与 [_blankLine] 严格同高（单行 + 省略号，绝不折行）。
  static Widget _attrLine(String text, TextStyle? style) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );

  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
