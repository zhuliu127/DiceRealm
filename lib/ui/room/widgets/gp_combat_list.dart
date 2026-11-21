// ============================================================
// widgets/gp_combat_list.dart — 块 6（两侧共用）：战斗列表
//
// KP 可推进（「下一个行动 ▶」按 `gate.can('combat.next')`），玩家/旁观只读
// —— 但**不隐藏已有信息**：玩家看到的是裁剪后的 order，缺的键不补、不当 0。
// ★ P14 COMBAT-4：开打后的 order **全量**（参战即公开），裁剪只剥属性不删槽
//   —— 否则 `turn` 下标错位会让玩家侧「当前行动者」错乱、攻击按钮永久置灰。
// ★ P14 COMBAT-6：玩家侧怪物行的卡壳 / 排版骨架与 PC 行完全一致，只少属性文案。
//
// 三条硬口径：
//   ① `hpPublic == false` → 显示「隐藏」，绝不把缺键当成 0（K4）；
//   ② 判活必须带 `hpMax > 0` 守卫 —— HP 未公开 / 未初始化的单位不算倒下（S5）；
//   ③ KP 侧可用 `secret` / `kpOnly` 补全 HP（`combatRows(isKp: true)` 已做），
//      玩家侧这两块在裁剪时已被删，绝不越权读取。
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap, jsStr;
import '../../../domain/room_types.dart' show RoomIntent, RoomRole;
import '../room_keys.dart';
import '../room_scope.dart';
import '../sheets/room_sheet.dart' show showRoomSheet;
import '../sheets/sheet_combat.dart' show showPlayerAttackSheet;
import '../view/combat_view.dart';
import 'gp_combat_strip.dart' show GpCombatStrip, GpCombatStripKeys;
import '../view/room_view.dart' show playersOf;
import 'gp_status.dart' show RoomRequestCard;
import 'room_button_size.dart' show clampBtnText;
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 战斗列表内部稳定 key。
class GpCombatKeys {
  const GpCombatKeys._();

  static const Key root = ValueKey<String>('gpCombat/root');
  static const Key empty = ValueKey<String>('gpCombat/empty');
  static const Key list = ValueKey<String>('gpCombat/list');
  static const Key tabs = ValueKey<String>('gpCombat/tabs');

  /// ＋加入（把未参战玩家追加入场）。
  static const Key enqueue = ValueKey<String>('gpCombat/enqueue');

  /// 加入候选里的空态（全都在战斗中了）。
  static const Key enqueueEmpty = ValueKey<String>('gpCombat/enqueue/empty');

  /// 单行（`gpCombat/row/<id>`）。
  static Key row(String id) => ValueKey<String>('gpCombat/row/$id');

  /// ★ P17 KP-7：KP 重排行动顺序的「上移 / 下移」按钮。
  ///   发 `combat.set`（POLICY `[kp]`，**不新增 action** —— `kRoomPolicy.length
  ///   == 62` 被 `room_ui_permission_test.dart` 钉死）。
  static Key moveUp(String id) => ValueKey<String>('gpCombat/moveUp/$id');
  static Key moveDown(String id) => ValueKey<String>('gpCombat/moveDown/$id');

  /// ★ 2.34.0 KP-1：打开「移出战斗」确认弹层的入口（KP 专属）。
  /// 只开本机弹层、不直接发 intent，故**不挂** `RoomKeys.action(op)`
  /// （与 I12 同款口径，避免 T-30 探针误判）。
  static const Key removeEntry = ValueKey<String>('gpCombat/removeEntry');

  /// 弹层里某个 base id 单位的「移出」确认按钮。
  static Key removeUnit(String base) =>
      ValueKey<String>('gpCombat/removeUnit/$base');

  /// 弹层里没有可移出单位时的空态。
  static const Key removeEmpty = ValueKey<String>('gpCombat/removeEmpty');

  /// 加入候选行（`gpCombat/enqueue/<seat>`）。
  static Key enqueueRow(String seat) =>
      ValueKey<String>('gpCombat/enqueue/$seat');

  // ---- P10 第 7 期 C 批 B：老 APP `initiativeBar` 行动顺序条 ----
  // 值统一取自 `GpCombatStripKeys`（单一真相源，避免两处字符串漂移）。

  /// 整条顺序条的根。
  static const Key strip = GpCombatStripKeys.strip;

  /// 单个行动槽（`gpCombat/strip/slot/<id>`）。
  static Key stripSlot(String id) => GpCombatStripKeys.slot(id);

  /// 当前行动槽（高亮）。
  static const Key stripCurrent = GpCombatStripKeys.current;

  /// 顶部文案「第 N 轮 · 当前行动：X」。
  static const Key stripHeader = ValueKey<String>('gpCombat/stripHeader');

  /// ★ P13 COMBAT-3：玩家侧「攻击对抗」按钮（独立 ValueKey，不挂 RoomKeys.action
  ///   锚点 —— 始终渲染、仅 enabled 随 isMyTurn 置灰，避开 T-30 静态锚点探针）。
  static const Key attack = ValueKey<String>('gpCombat/attack');
}

/// 块 6：战斗顺序 / 怪物信息 + KP 的推进按钮 + 待确认请求卡。
class GpCombatList extends StatelessWidget {
  const GpCombatList({super.key, this.height = 200});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    // ★ 自己订阅本地态：tab 切换是纯本地态，RoomScope 不订阅它。
    return ListenableBuilder(
      listenable: scope.local,
      builder: (BuildContext _, Widget? child) => _body(context, scope),
    );
  }

  Widget _body(BuildContext context, RoomScope scope) {
    final role = scope.session.role;
    final isKp = role == RoomRole.kp;
    final state = scope.session.state;
    final local = scope.local;
    final gate = scope.controller.gate;
    final rows = combatRows(state, isKp: isKp);
    // ★ P17 KP-7：KP 可重排行动顺序（怪物「插队」）。复用 `combat.set`
    //   （POLICY `[kp]`，`room_types.dart:277`），**不新增 action** ——
    //   `kRoomPolicy.length == 62` 被 `room_ui_permission_test.dart` 钉死。
    final bool canReorder = isKp && scope.controller.gate.can('combat.set');
    // ★ 2.34.0 KP-1：移出战斗同样复用 `combat.set`（不新增 action），
    //   只有 KP 且 gate 放行才渲染入口（T-22：玩家侧结构性不渲染）。
    final bool canRemove = isKp && scope.controller.gate.can('combat.set');
    final theme = Theme.of(context);

    final pending = <Widget>[];
    final read = scope.session.hostRead;
    if (isKp && read != null) {
      // 待确认的高危动作：与状态条同一份队列，这里给出与战斗相关的快捷入口。
      for (final q in read.pending) {
        final op = roomText(q['op']);
        final by = roomText(q['by']);
        final id = 'combat-pending:$op:$by';
        pending.add(RoomRequestCard(
          key: GpCombatKeys.row(id),
          id: id,
          title: '待确认：$op',
          text: '来自 $by',
          onReply: (bool agree) => scope.controller.sendIntent(
            RoomIntent.confirm,
            <String, Object?>{'op': op, 'by': by, 'agree': agree},
          ),
        ));
      }
    }

    // ★ P16 KP-4②：本块新增一个落点 —— **素材舞台格**（KP 战斗态），那一格给的是
    //   `Expanded` 的**紧约束**；而本块正文是「文案 + 顺序条 + tab + 200dp 列表」，
    //   在 1280×800 档的格高（约 283dp）里必然超一截。所以正文列提到 `SectionBox`
    //   外面，按高度两档处理（见下面 `child:`）。
    //   ★ 为什么不能把判定放进 `SectionBox.child` 里：`SectionBox` 内部是
    //     `Column(mainAxisSize: min)`，`RenderFlex` 给**非 flex 子节点**的主轴
    //     约束恒为无界 —— 放在里面永远读不到「有界」。
    final Widget column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ★ P10 第 7 期 C 批 B：顶部文案改老 APP `initiativeBar` 口径
        //   「第 N 轮 · 当前行动：X」；`roundText` 函数本身原样保留在
        //   combat_view.dart（既有纯函数测试依赖它）。
        Text(
          initiativeText(state),
          key: GpCombatKeys.stripHeader,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        // 逐槽行动顺序条（横向排，不把格子撑破）；只在战斗面板内渲染，
        // 不动 room_game_page.dart 的 Column / Stack 骨架。
        GpCombatStrip(isKp: isKp, seat: scope.session.seat),
        const SizedBox(height: 4),
        // ★ P13 COMBAT-3：玩家侧「攻击对抗」入口 —— 始终渲染，仅 enabled
        //   随 isMyTurn 置灰（门控锚点 combat_view.dart:109），不挂
        //   RoomKeys.action 字面量，避开 T-30 静态锚点探针。KP 侧结构性不渲染。
        if (!isKp)
          Align(
            alignment: Alignment.centerLeft,
            child: clampBtnText(
              RoomTap(
                key: GpCombatKeys.attack,
                label: '攻击对抗',
                icon: Icons.sports_martial_arts,
                // 门控：仅本人回合可点；gate 放行是必要非充分条件。
                enabled: isMyTurn(state, scope.session.seat) &&
                    gate.can('check.opposed'),
                hint: isMyTurn(state, scope.session.seat)
                    ? '选自己的武器与参战怪物发起对抗（需 KP 同意）'
                    : '还没轮到你行动，轮到你后方可攻击',
                minSize: const Size(96, 32),
                onTap: () => showPlayerAttackSheet(context),
              ),
            ),
          ),
        const SizedBox(height: 4),
        PanelTabs(
          key: GpCombatKeys.tabs,
          tabs: const <String>['顺序', '怪物信息'],
          index: local.combatTab,
          onChanged: (int i) => local.setTab('combat', i),
        ),
        const SizedBox(height: 4),
        // ★ P13 COMBAT-2（栏位可拖）：改前这里是 `SizedBox(height: height=200,
        //   child: ListView.builder)`，内层 ListView 抢走垂直拖拽手势，但只有
        //   200dp 高 —— 玩家拖「顺序 / 怪物信息」下面的栏位时只滚这 200dp、
        //   无法带动外层 SingleChildScrollView 去到下方其它信息（"拖不动屏幕"）。
        //   改法：内层用 shrinkWrap + NeverScrollableScrollPhysics 自然撑开，
        //   把所有滚动统一交给外层 SingleChildScrollView（有界档）/ 页面外层
        //   （无界档）。顶端 stripHeader / GpCombatStrip 仍是自动展开的正文，
        //   GpCombatKeys.strip 命中不被抢。height 参数保留兼容既有构造点，
        //   仅作无界档的最小高度提示，不再裁切内容。
        rows.isEmpty
            ? SizedBox(
                height: height,
                child: Center(
                  child: Text(
                    '未开战',
                    key: GpCombatKeys.empty,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              )
            : ListView.builder(
                key: GpCombatKeys.list,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                primary: false,
                itemCount: rows.length,
                itemBuilder: (BuildContext context, int i) {
                  final r = rows[i];
                  // ★ P17 KP-7：仅 KP + 「顺序」tab；首项无上移、末项无
                  //   下移（传 null = 按钮呈禁用态，结构上仍渲染，便于
                  //   测试按 key 找到）。
                  final bool showMoves = canReorder && local.combatTab == 0;
                  return _CombatRowTile(
                    key: GpCombatKeys.row(r.id),
                    row: r,
                    index: i,
                    detail: local.combatTab == 1,
                    showMoves: showMoves,
                    onMoveUp: i > 0
                        ? () => _moveCombatSlot(scope, i, -1)
                        : null,
                    onMoveDown: i < rows.length - 1
                        ? () => _moveCombatSlot(scope, i, 1)
                        : null,
                  );
                },
              ),
        // ★ 2.34.0 KP-1：移出战斗入口。
        //   ★ 刻意放正文列、不放 SectionBox.trailing：trailing 在 Row 里
        //     拿到的是**无界横向约束**，第三个按钮会让标题行溢出（现有
        //     两个按钮已占 180dp，格宽约 226dp）；放正文列则零几何影响，
        //     且在有界档由 Expanded+SingleChildScrollView 自然兜住。
        //   ★ 只开本机确认弹层、不直接发 intent，故不挂
        //     `RoomKeys.action(op)`（I12 同款口径，避开 T-30 探针）。
        if (canRemove)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: clampBtnText(
                RoomTap(
                  key: GpCombatKeys.removeEntry,
                  label: '移出战斗',
                  icon: Icons.logout,
                  enabled: gate.can('combat.set'),
                  hint: '剧情需要时把某个单位移出战斗（真删槽）',
                  minSize: const Size(96, 32),
                  onTap: () => openCombatRemoveSheet(context),
                ),
              ),
            ),
          ),
        if (pending.isNotEmpty) ...pending,
      ],
    );
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints c) {
        return SectionBox(
          key: GpCombatKeys.root,
          title: '战斗',
          // ★ T-22：玩家侧**不渲染**这批按钮（不是禁用），能力边界在结构上成立；
          //   T-30 探针遇到「该角色不渲染」是合法分支。
          //
          // ★ P16（QA 第 2 轮裁决 #1）：这两个按钮**宽度保持原样**（规格 §6：
          //   `下一个行动 ▶` 内容 115.5 > 等分宽，任何「统一到长按钮」的做法都
          //   必然 overflow），只把**文字缩放**钳住 —— 否则系统字号 1.3× 就在
          //   1280/1524 横屏把 `SectionBox` 标题行撑出 4.6px，1.5× 撑 31px、
          //   2.0× 撑 96px（用户开长辈模式一眼看到黄黑条纹）。
          //   `clampBtnText` 只包 RoomTap 子树：不改 trailing 结构、不改尺寸、
          //   不改文案、不改 `SectionBox`。
          trailing: isKp
              ? Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    // ★ 2.34.0 I15：「下一个行动」补 500ms 节流 + 冷却期
                    //   视觉置灰（见文件末尾 [_NextTurnButton]）；`enabled`
                    //   口径逐字不动，T-30 探针读到的仍是 `gate.can(op)`。
                    _NextTurnButton(
                      scope: scope,
                      enabled: gate.can('combat.next'),
                    ),
                    // PRD `_p5_prd.md:305`（块 6「＋加入 → combat.enqueue {seat}」）
                    // + `:513`（[kp]）；载荷 `{seat}`。
                    clampBtnText(
                      RoomTap(
                        key: GpCombatKeys.enqueue,
                        label: '＋加入',
                        icon: Icons.person_add_alt,
                        enabled: gate.can('combat.enqueue'),
                        hint: gate.can('combat.enqueue')
                            ? '把未参战的玩家追加入场'
                            : '只有 KP 能追加参战单位',
                        minSize: const Size(80, 32),
                        onTap: () => openCombatEnqueueSheet(context),
                      ),
                    ),
                  ],
                )
              : null,
          // ★ 有界（素材舞台格的战斗态）：正文列塞进 `Expanded` + 单层滚动 ——
          //   卡片吃满格高、内容超长就滚，绝不 `RenderFlex overflow`。
          //   `Expanded` 必须是 `SectionBox` 内层 Column 的**直接子节点**，
          //   所以直接交给它，不要再套一层 Builder。
          // ★ 无界（折叠档展开面板 / 独立 pump 的外层 SingleChildScrollView）：
          //   与改前逐字一致，仍是自然高度列，由外层滚动兜底（那里套
          //   `Expanded` 会直接抛「非零 flex + 无界约束」断言）。
          child: c.hasBoundedHeight
              ? Expanded(child: SingleChildScrollView(child: column))
              : column,
        );
      },
    );
  }

  /// ★ P17 KP-7：KP 重排行动顺序（怪物「插队」）。
  ///
  /// 复用 `combat.set`（POLICY `[kp]`），把整包 `combat` 原样带回、只改
  /// `order` 数组顺序与 `turn` —— `RoomEvt.combat` 在 `room_model_reduce.dart`
  /// 是**整体替换**，所以三个状态键必须一起维护：
  ///   · `done` / `movedToTail` 挂在 slot 元素上，随元素交换天然跟随；
  ///   · `turn` 是**索引**（`combatStart` 写死 `'turn': 0`，`nextTurn` 按
  ///     `raNum(c['turn'])` 取），交换 `a` / `b` 两位置后按「互换规则」重映射
  ///     （`turn==a → b`、`turn==b → a`、否则不变）—— 与「turn 跟随同一个
  ///     slot」语义等价（actorId 在 `order` 内唯一）。
  /// 排序算法本体（`room_rules_combat.dart:24-94`）一字不动。
  void _moveCombatSlot(RoomScope scope, int index, int delta) {
    final gate = scope.controller.gate;
    if (!gate.can('combat.set')) return;
    final c0 = asMap(scope.session.state['combat']);
    if (c0['order'] is! List) return;
    final src = asList(c0['order']);
    final j = index + delta;
    if (j < 0 || j >= src.length) return;
    // 一层拷贝（slot 内全是标量）：改副本，不直接改权威态。
    final order = <Object?>[
      for (final s in src) Map<String, Object?>.from(asMap(s)),
    ];
    final tmp = order[index];
    order[index] = order[j];
    order[j] = tmp;
    final turnRaw = c0['turn'];
    final turnIdx = turnRaw is num ? turnRaw.toInt() : 0;
    var newTurn = turnIdx;
    if (turnIdx == index) {
      newTurn = j;
    } else if (turnIdx == j) {
      newTurn = index;
    }
    final combat = Map<String, Object?>.from(c0)
      ..['order'] = order
      ..['turn'] = newTurn;
    scope.controller.hostAction('combat.set', <String, Object?>{
      'combat': combat,
    });
  }

}

/// 去掉多行动 `#n` 后缀，取单位的 base id（公开给弹层 / Wave2 单测复用）。
/// 与 `gp_combat_strip.dart:106-107` 的分组口径逐字一致。
String combatBaseId(String id) {
  final hash = id.indexOf('#');
  return hash >= 0 ? id.substring(0, hash) : id;
}

/// ★ 2.34.0 KP-1：把某个单位（按 [baseId]）从 `combat.order` **真删槽**。
///
/// 抽成顶层函数：确认弹层 [_CombatRemoveBody] 是独立 widget，拿不到
/// [GpCombatList] 的私有方法；放顶层也能让 Wave2 直接单测 turn 四分支。
///
/// · 不是「标记离场」：现有 `down` / `state='dead'` 只是标记，单位仍在
///   order 里；这里是删除元素。同一 base id 的多行动 `#n` 槽一并删除
///   （base 口径与 `gp_combat_strip.dart:106-107` 完全一致）。
/// · `done` / `movedToTail` 挂在 slot 元素上，随元素一起走：删掉的槽连带
///   标记消失，留下的槽一层拷贝原样保留，绝不重排别人的标记。
/// · `turn` 是 `combat.order` 的**索引非 id**，删索引 i 后：
///   `i<turn → turn-1`、`i>turn → 不变`、`i==turn → clamp(0, len-1)`；
///   `round` 不变。删「末位 + 当前行动」单位会令 `turn == order.length`
///   越界（静默错误），末尾统一 clamp 修掉。
/// · 发包 `hostAction('combat.set', {'combat': combat})`，载荷**同时带齐**
///   `order` / `turn` / `round` 三键（T02 在权威端兜底）；复用既有
///   `combat.set`（POLICY `[kp]`，`kRoomPolicy.length == 62` 不变），
///   **不新增任何 action**；游戏记录与广播由权威端写，UI 不发 log。
void removeCombatUnit(RoomScope scope, String baseId) {
  final gate = scope.controller.gate;
  if (!gate.can('combat.set')) return;
  final c0 = asMap(scope.session.state['combat']);
  if (c0['order'] is! List) return;
  final src = asList(c0['order']);
  if (src.isEmpty) return;

  // ① 收集属于同一 base id 的槽索引（含多行动 `#n`）。
  final removed = <int>[];
  for (var i = 0; i < src.length; i++) {
    if (combatBaseId(roomText(asMap(src[i])['id'])) == baseId) {
      removed.add(i);
    }
  }
  if (removed.isEmpty) return;

  // ② 一层拷贝保留下来的槽；done / movedToTail 等元素内字段随槽走。
  final order = <Object?>[];
  for (var i = 0; i < src.length; i++) {
    if (removed.contains(i)) continue;
    order.add(Map<String, Object?>.from(asMap(src[i])));
  }

  // ③ turn 重映射：只有「被删索引 < turn」才让当前行动左移；删到
  //    turn 本身或之后的槽都不左移。末尾 clamp 到 [0, len-1]，同时修掉
  //    删「末位 + 当前行动」时 turn == order.length 的越界。
  final turnRaw = c0['turn'];
  final turn = turnRaw is num ? turnRaw.toInt() : 0;
  final before = removed.where((int i) => i < turn).length;
  final maxTurn = order.isEmpty ? 0 : order.length - 1;
  var newTurn = turn - before;
  if (newTurn < 0) newTurn = 0;
  if (newTurn > maxTurn) newTurn = maxTurn;

  // ④ round 原样带回；三键一次写全，避免整包替换丢键。
  final roundRaw = c0['round'];
  final round = roundRaw is num ? roundRaw : 1;
  final combat = Map<String, Object?>.from(c0)
    ..['order'] = order
    ..['turn'] = newTurn
    ..['round'] = round;
  scope.controller.hostAction('combat.set', <String, Object?>{
    'combat': combat,
  });
}

/// 一行战斗参与者。
class _CombatRowTile extends StatelessWidget {
  const _CombatRowTile({
    super.key,
    required this.row,
    required this.index,
    required this.detail,
    this.showMoves = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  final CombatRow row;
  final int index;
  final bool detail;

  /// ★ P17 KP-7：true 才渲染「上移 / 下移」按钮（KP + 「顺序」tab）。
  ///   `onMoveUp == null` 表示首项（不能上移）、`onMoveDown == null` 表示
  ///   末项 —— 按钮呈**禁用态**而非隐藏，测试可按 key 找到。
  final bool showMoves;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = row.isCurrent ? scheme.primaryContainer : null;

    // ★ P14 COMBAT-6（用户问题 8）：怪物行与玩家行**共用同一张卡壳与同一条
    //   排版骨架**（同内边距、同行高、同序号列宽、同名字字号与省略规则），
    //   差别只在 `trailing`：怪物只写名字、不渲染 HP / 类型 / 状态 / 行动次数
    //   （P13 COMBAT-1 的「只显名字」逐字保留：数据层已删怪物 HP，这里连
    //   「隐藏」二字都不暗示）。
    final List<Widget> trailing = <Widget>[];
    if (!row.playerNameOnly) {
      // ① HP 文案：未公开 → 「隐藏」；已知但缺上限 → 只给当前值。
      final hpTextValue = row.hpHidden
          ? '隐藏'
          : (row.hpMax > 0
              ? '${_fmt(row.hp)} / ${_fmt(row.hpMax)}'
              : _fmt(row.hp));
      // ② 判活：必须带 hpMax > 0 守卫（未初始化 ≠ 已死）。
      final down = !row.hpHidden && row.hpMax > 0 && row.hp <= 0;
      trailing.addAll(<Widget>[
        Text(
          detail ? '${row.kind} · ${row.stateText}' : row.stateText,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(width: 6),
        Text('HP $hpTextValue', style: theme.textTheme.bodySmall),
        if (down) ...<Widget>[
          const SizedBox(width: 4),
          Text('已倒下',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        ],
        if (detail) ...<Widget>[
          const SizedBox(width: 6),
          Text('行动 ${row.actionsPerRound}',
              style: theme.textTheme.bodySmall),
        ],
        if (showMoves) ...<Widget>[
          const SizedBox(width: 4),
          _SlotMoveBtn(
            key: GpCombatKeys.moveUp(row.id),
            icon: Icons.keyboard_arrow_up,
            enabled: onMoveUp != null,
            onTap: onMoveUp,
          ),
          _SlotMoveBtn(
            key: GpCombatKeys.moveDown(row.id),
            icon: Icons.keyboard_arrow_down,
            enabled: onMoveDown != null,
            onTap: onMoveDown,
          ),
        ],
      ]);
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
              width: 20,
              child:
                  Text('${index + 1}', style: theme.textTheme.bodySmall)),
          Expanded(
            child: Text(
              row.name.isEmpty ? row.id : row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: row.isCurrent ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }

  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// ★ P17 KP-7：行动顺序槽的「上移 / 下移」小按钮（KP 专属，每格 20×28）。
class _SlotMoveBtn extends StatelessWidget {
  const _SlotMoveBtn({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 20,
      height: 28,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? scheme.onSurface
              : scheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// ＋加入战斗（PRD `_p5_prd.md:305` 块 6「＋加入 → combat.enqueue {seat}」）
// ------------------------------------------------------------

/// 打开「加入战斗」候选弹层。
///
/// 候选 = 花名册里的玩家 − 已在 `combat.order` 里的 pc 槽位。
Future<void> openCombatEnqueueSheet(BuildContext context) =>
    showRoomSheet<void>(
      context: context,
      title: '加入战斗',
      body: (BuildContext _) => const _CombatEnqueueBody(),
    );

/// 候选列表主体。
class _CombatEnqueueBody extends StatelessWidget {
  const _CombatEnqueueBody();

  @override
  Widget build(BuildContext context) {
    final RoomScope scope = RoomScope.of(context);
    final Map<String, Object?> state = scope.session.state;
    final Set<String> inOrder = <String>{
      for (final Object? s in asList(asMap(state['combat'])['order']))
        if (jsStr(asMap(s)['kind']) == 'pc') jsStr(asMap(s)['seat']),
    };
    final List<Map<String, Object?>> candidates = <Map<String, Object?>>[
      for (final Map<String, Object?> m in playersOf(state))
        if (!inOrder.contains(jsStr(m['seat']))) m,
    ];
    final bool can = scope.controller.gate.can('combat.enqueue');

    if (candidates.isEmpty) {
      return Text(
        '所有玩家都已在战斗中',
        key: GpCombatKeys.enqueueEmpty,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '选择要追加入场的玩家（${candidates.length}）',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        for (final Map<String, Object?> m in candidates)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _labelOf(m),
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                RoomTap(
                  key: GpCombatKeys.enqueueRow(jsStr(m['seat'])),
                  label: '加入',
                  icon: Icons.add,
                  enabled: can,
                  hint: can ? '追加入场' : '只有 KP 能追加参战单位',
                  minSize: const Size(72, 40),
                  onTap: () {
                    scope.controller.hostAction(
                      'combat.enqueue',
                      <String, Object?>{'seat': jsStr(m['seat'])},
                    );
                    Navigator.of(context).maybePop();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _labelOf(Map<String, Object?> m) {
    final String nick = roomText(m['nickname']);
    final String seat = roomText(m['seat']);
    return nick.isEmpty ? seat : '$nick（$seat）';
  }
}

// ------------------------------------------------------------
// 2.34.0 KP-1：移出战斗（按单位选择 + 防误触二次确认）
// ------------------------------------------------------------

/// 打开「移出战斗」弹层：按 base id 列出参战单位供 KP 选择。
///
/// 复用 [showRoomSheet] 这个 18+ 处共用的统一弹层壳（C8：壳本身禁改）；
/// 每个单位用 [ConfirmTwice] 连点两次才真正删槽，避免误触把单位移出。
Future<void> openCombatRemoveSheet(BuildContext context) =>
    showRoomSheet<void>(
      context: context,
      title: '移出战斗',
      body: (BuildContext _) => const _CombatRemoveBody(),
    );

/// 候选单位列表：按 base id 去重（多行动 `#n` 只列一次），逐行确认。
class _CombatRemoveBody extends StatelessWidget {
  const _CombatRemoveBody();

  @override
  Widget build(BuildContext context) {
    final RoomScope scope = RoomScope.of(context);
    final List<Object?> order =
        asList(asMap(scope.session.state['combat'])['order']);
    final Map<String, String> names = <String, String>{};
    for (final Object? raw in order) {
      final Map<String, Object?> slot = asMap(raw);
      final String id = roomText(slot['id']);
      final String base = combatBaseId(id);
      final String name = roomText(slot['name']);
      // 首现顺序保留；同 base 的多行动槽不重复列。
      names.putIfAbsent(base, () => name.isEmpty ? base : name);
    }
    final bool can = scope.controller.gate.can('combat.set');

    if (names.isEmpty) {
      return Text(
        '当前没有参战单位',
        key: GpCombatKeys.removeEmpty,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    // ★ T-22：非 KP 结构性不渲染移出按钮（不是禁用）。
    if (!can) {
      return Text(
        '只有 KP 能移出参战单位',
        key: GpCombatKeys.removeEmpty,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '移出后该单位的所有行动槽都会从顺序表删除（不是标记为倒下）。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        for (final MapEntry<String, String> e in names.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    e.value,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // ★ 防误触：连点两次才发 `combat.set`（项目既有
                //   ConfirmTwice 范式，见 sheet_misc.dart / gp_kp_tools.dart）。
                //   clampBtnText 只钳这一棵按钮子树（C7）。
                clampBtnText(
                  ConfirmTwice(
                    key: GpCombatKeys.removeUnit(e.key),
                    label: '移出',
                    confirmLabel: '再点一次移出',
                    onConfirmed: () {
                      removeCombatUnit(scope, e.key);
                      Navigator.of(context).maybePop();
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------
// 2.34.0 I15：「下一个行动 ▶」补 500ms 节流 + 冷却期视觉置灰
// ------------------------------------------------------------

/// 「下一个行动」按钮：原本**完全无节流**，连点会连打权威结算（I15）。
///
/// ★ T-30：挂 `RoomKeys.action('combat.next')` 的 [RoomTap]，其 `enabled`
///   必须恰好等于 `gate.can(op) && !locked` 这一既有口径；[enabled] 原样
///   透传、逐字保持 `gate.can('combat.next')`，`_cooling` **只**驱动
///   `foregroundDecoration` 视觉置灰，绝不叠进 `enabled`。
/// ★ 冷却复位复用 `RoomUiLocal.scheduleDismiss` 可注入时钟（harness 里为
///   `(_, _) => null`，fake-async 不挂死），不裸用 `Timer`。
class _NextTurnButton extends StatefulWidget {
  const _NextTurnButton({required this.scope, required this.enabled});

  final RoomScope scope;

  /// 原样来自 `gate.can('combat.next')`，T-30 探针读取的就是它。
  final bool enabled;

  @override
  State<_NextTurnButton> createState() => _NextTurnButtonState();
}

class _NextTurnButtonState extends State<_NextTurnButton> {
  bool _cooling = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _onTap() {
    final controller = widget.scope.controller;
    // ★ I15：只在调用点传 500ms 窗口；`throttle` 默认 400ms 逐字不动。
    if (!controller.throttle(
      'combat.next',
      window: const Duration(milliseconds: 500),
    )) {
      return;
    }
    controller.hostAction('combat.next');
    if (!mounted) return;
    setState(() => _cooling = true);
    _reset?.cancel();
    _reset = widget.scope.local.scheduleDismiss(
      const Duration(milliseconds: 500),
      () {
        if (!mounted) return;
        setState(() => _cooling = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // foregroundDecoration 只绘制、不参与布局，按钮尺寸 / hitTest 不变。
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        color: _cooling
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.55)
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: clampBtnText(
        RoomTap(
          key: RoomKeys.action('combat.next'),
          label: '下一个行动 ▶',
          icon: Icons.play_arrow,
          // ★ T-30：enabled 口径逐字保持 `gate.can(op)`。
          enabled: widget.enabled,
          hint: '推进到下一个行动',
          minSize: const Size(96, 32),
          onTap: _onTap,
        ),
      ),
    );
  }
}
