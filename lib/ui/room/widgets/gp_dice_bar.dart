// ============================================================
// widgets/gp_dice_bar.dart — 骰子条（KP 块 11 内 / PL 块 12 内，共用）
//
// 职责极窄：**只发 `INTENT.DICE{direct:true}` 信封**，不自己算结果。
//   规则复算在权威端（`diceDirect`），客户端自报的 result 根本不进那条路径
//   （P4 F4 的同一保证）。所以这里既没有随机源，也没有任何判读逻辑。
//
// 五件事：
//   · 骰式快捷：D100 / D4 / D6 / D8 / D10 / D12 / D20 + 自定义骰式；
//   · 奖惩骰：**互斥**且各自 0–5（`RoomUiLocal.setBonus/setPenalty` 一处实现）；
//   · 暗骰开关：置 `secret:true` —— 权威端只把结果定向发给本人与 KP
//     （B1-F1），`state.dice` 只承载公开骰；
//   · 扩展按钮组：按角色门控（`gate.can(op)`，与 POLICY 同源）；
//   · 旁观者：**全部禁用**（T-05）。
//
// ★ T-30 契约：挂了 `RoomKeys.action(op)` 的按钮，`enabled` 必须恰好等于
//   `gate.can(op)`，不许叠加业务前置条件（否则表驱动探针判成漂移）。
//   ★ P17 修订（施工单 §2-P-3，唯一例外）：昏迷 / 疯狂「锁定态」是**跨按钮
//     的统一闸门**（权威端 `room_model_host_intent.dart#_passSelf` 已在拦，
//     只放行 `madness.advance` / `madness.cure` / `sheet.healwound` 与
//     聊天 / 同步）。所以 `enabled` 允许且必须叠加 `!locked`
//     ⇒ 新口径 `gate.can(op) && !locked`，探针口径由波4 同步改。
//     ⚠️ 白名单不收窄：本文件**没有**白名单按钮（骰子 / 奖惩 / 暗骰 / 战技 /
//     对抗全部黑名单）；「缩放 / 全屏」在 `gp_toolbar.dart` 与角色卡上。
//
// ★ P10 第 6 期（布局专项，用户原话「下方玩家工具栏按钮也很乱」「手机竖屏
//   下堆成 4 行、战技单独一行」）：
//   · 窄档（可用宽度 < [_kGroupBelowWidth] = 600dp，含 412dp 手机竖屏）：
//     把原来「一整条 Wrap 贪心铺 13 个按钮」改成**按可用宽度均衡显式切行**
//     ——412dp 实测 4/3/3/3，每行 3~4 个按钮；旧版贪心是 4/4/4/1，
//     末尾「战技」孤零零一行。13 个按钮宽 48~98dp、可用 392dp，
//     物理上排不进 3 行，所以目标定为「整齐、无孤行」而不是强行 3 行。
//   · 宽档（≥ 600dp，含 1280×800 / 1524×1016 平板横屏）：仍是**单个 Wrap**
//     一行流，工具栏高度与旧版逐像素一致，不压缩 KP 横屏内容区。
//   · 密集化：Wrap spacing/runSpacing 4→3、容器内边距 6/4→4/3、
//     自定义输入框 92→68dp；所有 RoomTap 的 minSize 与 48×48 热区口径
//     一字不动；容器边框从 BoxDecoration 移到 foregroundDecoration
//     （P12 同口径：描边不占尺寸，不把按钮挤出一行）。
//   · ★ 战技 / 对抗两个 RoomTap 的 onTap 回调（P10 第 6 期真修复）
//     **逐字保留**，本批只调它们的排布（移到第 ② 组）与外层间距。
//
// ★ P17（v2.30.0）三项，本文件承担两项半：
//   · **P-4 重排**：工具栏删掉「下一轮 / 转战斗」后，目标手机竖屏 4 行
//     = 4 / 3 / 3 / 3。本文件仍保持 **9 个条目**（见下条为何没变多），
//     `per ∈ {3,4}` 恒切成 **3 / 3 / 3** ⇒ 骰子条正好占第 2~4 行，
//     第 1 行由主组 2 个缩放 + 注入的「更多工具 / 治疗」补成 4 个。
//   · **C-3 奖惩骰加减与归零**：原来两个按钮只能 `setX(x+1)`。现在每侧是
//     **三段式复合控件** `[−] [奖励 N（点=+1）] [↺ 归零]`：
//     三个段仍是同一个条目 ⇒ 条目数不变（9），切行不变，行数不变。
//     归零复用 `RoomUiLocal.setBonus/setPenalty(0)`（**不新增任何状态字段**），
//     下限 0 / 上限 5 / 奖惩互斥全部仍由那一处夹取（见 `room_ui_local.dart`）。
//     为什么不用「长按归零 / 双击归零」：① `RoomTap` 没有 `onLongPress`
//     （`room_panel_kit.dart` 不在本批文件集，动它就是跨组改共用件）；
//     ② 长按与双击都是**不可见手势**，工具栏是高频密排区，可发现性必须
//     靠可见的 `−` / `↺` 图形——用户上一轮正是「不知道能减」才提的需求。
//   · **P-3 锁定**：见文件头 T-30 的 P17 修订。`locked == true` 时除
//     「其他骰子」弹层内按钮外，本文件**全部**按钮 / 输入框禁用。
// ============================================================

import 'package:flutter/material.dart';

import '../../art.dart';
import '../../../theme.dart' show Palette;

import '../../../domain/room_types.dart';
import '../room_keys.dart';
import '../room_scope.dart';
import '../sheets/sheet_opposed.dart' show showOpposedSheet;
import '../sheets/sheet_treat.dart' show openTreatSheet;
import 'room_button_size.dart' show RoomBtnSize, clampBtnText;
import 'room_panel_kit.dart';

/// 窄档阈值：低于该可用宽度时把骰子条拆成两组 Wrap（避免末尾孤行）。
const double _kGroupBelowWidth = 600;

/// 骰子条按钮**统一定宽**（与 `RoomBtnSize.diceTile.width` 同源）。
///
/// ★ 单一真源在 `room_button_size.dart`；这里另立一个 double 常量只是为了
///   让切行公式能在**纯 Dart 用例**里直接算（不 import Flutter 的 Size）。
///   `p16_button_unify_test.dart` 有一条一致性断言钉住两者相等，防漂移。
const double kDiceTileW = 90;

/// 骰子条按钮间距（与 `RoomBtnSize.gapTight` 同源，既有口径 `spacing: 3`）。
const double kDiceTileGap = 3;

/// 一行最多放几个骰子按钮（**纯函数**，可直接单测）。
///
/// ★ P16（规格 §5）：原实现是 `((w - 16) / 88).floor().clamp(2, 4)`——
///   `88` 是「按钮平均宽」的**魔数**，与任何 `minSize` 都无关联。统一到
///   90 宽后，除数改成「统一宽 + spacing」的符号式，按钮再变宽时切行会
///   **自动**跟着变（这正是反向证伪链 2 要守的那条性质）。
///   · `- 16` 保留既有保守口径（padding 4×2 + 安全 8）；
///   · `clamp(2, 4)` 一字不动：下限 2 防「一列到底」，上限 4 防按钮太碎。
int diceMaxPerRow(double availableWidth) {
  final int raw =
      ((availableWidth - 16) / (kDiceTileW + kDiceTileGap)).floor();
  // 与既有 `clamp(2, 4)` 逐值等价（写成显式分支只为返回型别确定）。
  if (raw < 2) return 2;
  if (raw > 4) return 4;
  return raw;
}

/// 均衡切行后**每行的按钮数**（纯函数，「无孤行」断言可直接调用）。
///
/// 分配规则与 `_balancedRows` 完全同一算术：`rowCount = ceil(n / per)`、
/// `base = n ~/ rowCount`、`extra = n % rowCount`，前 `extra` 行各多 1 个。
///
/// 对当前的 **9 项**（D4–D20 收进「其他骰子」弹窗后）：
/// `per = 3` → `3/3/3`；`per = 4` → `3/3/3`；只有 `per = 2` 才会退化成
/// `2/2/2/2/1`（孤行），而 `per = 2` 需要可用宽 < 295 —— 工具栏最小档
/// （屏宽 320）也有 308，不可达。
List<int> diceBalancedRowSizes(int itemCount, int maxPerRow) {
  if (itemCount <= 0) return <int>[];
  final int per = maxPerRow < 2 ? 2 : maxPerRow;
  final int rowCount = (itemCount / per).ceil();
  final int base = itemCount ~/ rowCount;
  final int extra = itemCount % rowCount;
  return <int>[
    for (var r = 0; r < rowCount; r++) base + (r < extra ? 1 : 0),
  ];
}

/// 骰子条内部稳定 key。
class GpDiceBarKeys {
  const GpDiceBarKeys._();

  static const Key bonus = ValueKey<String>('gpDice/bonus');
  static const Key penalty = ValueKey<String>('gpDice/penalty');
  static const Key dark = ValueKey<String>('gpDice/dark');
  static const Key customExpr = ValueKey<String>('gpDice/customExpr');
  static const Key rollCustom = ValueKey<String>('gpDice/rollCustom');

  /// ★ P17 C-3：奖惩骰复合控件的另外两段。
  ///
  /// `bonus` / `penalty` 仍是**中间那一段**（点 = +1，语义与 P16 完全一致，
  /// 既有「点 bonus ×3 → bonus:3」的用例逐字不动），只是它左右各多了一段：
  /// `…Minus` = `−1`，`…Reset` = 归零。三个段都是独立 `RoomTap`，
  /// 所以各自都能被 `find.byKey` 命中、被 `enabled` 探针读到。
  static const Key bonusMinus = ValueKey<String>('gpDice/bonusMinus');
  static const Key bonusReset = ValueKey<String>('gpDice/bonusReset');
  static const Key penaltyMinus = ValueKey<String>('gpDice/penaltyMinus');
  static const Key penaltyReset = ValueKey<String>('gpDice/penaltyReset');

  /// 某个骰式的按钮 key（`gpDice/expr/1D100`）。
  static Key expr(String e) => ValueKey<String>('gpDice/expr/$e');

  /// 「其他骰子」弹层入口（P10 第 7 期：D4~D20 从工具栏收进弹窗）。
  static const Key otherDice = ValueKey<String>('gpDice/otherDice');
}

/// P17 C-3：奖惩复合控件里**单段**的最小尺寸 —— 高度与 `diceTile` 同档（40），
/// 宽度交给内容（`minWidth: 0`）。
///
/// ★ 为什么不定宽：`−` / `↺` 是纯图标段（内容 30dp），中间的 `奖励 N` 是
///   文字段（内容随字数变）。定宽要么给图标段留空、要么把文字段挤到
///   `RenderFlex overflow`（P16 踩过：`SizedBox(80)` 紧约束让内容宽 87 的
///   `100%` 溢出 7dp）。三段各自取「内容宽 vs 0」的最大值 ⇒ 结构上不可能溢出，
///   也不需要为大字体额外调宽（文字缩放另外由 `clampBtnText` 钳住）。
const Size _kZoneMin = Size(0, 40);

/// 骰式 → 自绘骰型图标名（`1D20` → `d20`）。
///
/// 认不出的骰式（自定义表达式）返回 `d20` 作兜底 —— 泛用骰子图标，
/// 总比没有图标好认。
String _dicePngOf(String expr) {
  final String e = expr.toUpperCase().replaceAll(' ', '');
  for (final String n in <String>['100', '20', '12', '10', '8', '6', '4']) {
    if (e.endsWith('D$n')) return 'd$n';
  }
  return 'd20';
}

/// 骰式 → 按钮**显示文案**（去掉前导 1：`1D100` → `D100`）。
///
/// ★ 只影响显示；掷骰仍用 [kDiceExprs] 里的原表达式（`1D100` 等），
///   规则层的 `INTENT.DICE.expr` 与 `diceDirect` 复算一字不动。
String _diceLabelOf(String expr) {
  final e = expr.trim().toUpperCase();
  return e.startsWith('1D') ? e.substring(1) : e;
}

/// 骰式快捷表（顺序即渲染顺序）。
const List<String> kDiceExprs = <String>[
  '1D100',
  '1D4',
  '1D6',
  '1D8',
  '1D10',
  '1D12',
  '1D20',
];

/// 把按钮**均衡**切成若干显式行，每行至多 [maxPerRow] 个。
///
/// 为什么不能只靠一个 Wrap：Wrap 是贪心装箱，412dp 下 13 个按钮会排成
/// 4+4+4+1，末尾又出现一个孤零零的按钮（正是用户抱怨的「战技单独一行」）。
/// 显式按「行数 = ceil(n / maxPerRow)」均分后，13 个 → 4/3/3/3、
/// 14 个 → 4/4/3/3，每行都至少 3 个，结构上不再产生孤行。
/// 相对顺序完全不变（只切分，不重排），宽档的单个 Wrap 与旧版一致。
///
/// ★ P16：切行的**算术**已抽成纯函数 [diceBalancedRowSizes]（可单测）；
///   本函数只负责把「每行几个」落成 `sublist`。当前骰子条实际是 **9 项**
///   （D4–D20 收进「其他骰子」弹窗后），`per ∈ {3, 4}` 时恒为 `3/3/3`。
List<List<Widget>> _balancedRows(List<Widget> items, int maxPerRow) {
  final rows = <List<Widget>>[];
  var cursor = 0;
  for (final take in diceBalancedRowSizes(items.length, maxPerRow)) {
    rows.add(items.sublist(cursor, cursor + take));
    cursor += take;
  }
  return rows;
}

/// 骰子条。
class GpDiceBar extends StatefulWidget {
  const GpDiceBar({
    super.key,
    this.extensions = const <Widget>[],
    this.locked = false,
  });

  /// 扩展按钮组（T04/T05 可再往里塞），T03 自己的快捷动作已内置。
  final List<Widget> extensions;

  /// P17 P-3：本人处于昏迷 / 疯狂 / 濒死 / 死亡等**锁定态**。
  ///
  /// ★ 契约（施工单 §2-P-3 逐字）：由 `room_game_page.dart#_buildToolbar`
  ///   计算后传入，默认 `false`（玩家正常态）。本组件内**全部**按钮与输入框
  ///   的 `enabled` 叠加 `!locked`：
  ///     D100 / 其他骰子 / 自定义骰式（输入框 + 掷）/ 暗骰 / 战技 / 对抗，
  ///     以及 C-3 新增的 `−` / `+`（值本身）/ `↺` 四组六段。
  /// ★ 白名单内**没有**本文件的按钮：缩放 / 全屏 / 折叠展开在别处
  ///   （`gp_toolbar.dart` 的缩放两件、角色卡、素材舞台）。
  final bool locked;

  @override
  State<GpDiceBar> createState() => _GpDiceBarState();
}

class _GpDiceBarState extends State<GpDiceBar> {
  final TextEditingController _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// 发一次「直接掷」。**只给 op + p，信封形状由会话组装。**
  void _roll(String expr) {
    final scope = RoomScope.read(context);
    final local = scope.local;
    final trimmed = expr.trim();
    if (trimmed.isEmpty) return;
    scope.controller.sendIntent(
      RoomIntent.dice,
      <String, Object?>{
        'expr': trimmed,
        'direct': true,
        // ★ 互斥与夹取都在 RoomUiLocal 里做过，这里原样透传，不再二次判断。
        'bonus': local.bonus,
        'penalty': local.penalty,
        // 暗骰：只影响权威端的可见性分流，不影响骰值。
        if (local.darkRoll) 'secret': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    // ★ 自己订阅本地态：RoomScope 只订阅会话，奖励/惩罚/暗骰都是本地态，
    //   不订阅的话「点了数字不刷新」（标签会停在旧值）。
    return ListenableBuilder(
      listenable: scope.local,
      builder: (BuildContext _, Widget? child) => _bar(context, scope),
    );
  }

  Widget _bar(BuildContext context, RoomScope scope) {
    final local = scope.local;
    final controller = scope.controller;
    final gate = controller.gate;
    final bool editable = scope.session.role != RoomRole.spectator;
    // ★ 2.34.0 / I2 + I16：R1 门控与 PV-2「治疗」都按视角分流。
    //   判定唯一来源是会话角色（与页面 _buildToolbar 的
    //   `role == RoomRole.kp` 同源），不新造权限判定、不改 gate.can 口径。
    final bool isKp = scope.session.role == RoomRole.kp;
    // ★ P17 P-3：锁定时整条骰子条禁用（权威端 `_passSelf` 已在拦，UI 同步）。
    final bool locked = widget.locked;
    final bool canRoll = editable && !locked;
    final String blockedHint = locked
        ? '操作受限：昏迷 / 疯狂 / 濒死期间只能「推进 1 轮」或点「更多工具」'
        : '旁观者不能掷骰';
    final theme = Theme.of(context);

    // ---- 组 ①：奖惩骰 + 7 个骰式快捷（纯掷骰动作） ----
    // ★ P16 补齐（QA 二轮缺口）：这两个列表里的 `RoomTap` 是「裸 RoomTap + minSize」，
    //   不在 `RoomTapTile` 内 ⇒ **不会**被 tile 的钳制覆盖，必须在这里显式钳。
    //   不钳的后果（QA 实测）：×1.5 下同栏位宽度散成 {113,113,111,113,90,93.3}
    //   （distinct=4）、360dp 档行数 3→4 —— 直接违背用户「同一栏位一样大」。
    //   `.map(clampBtnText)` 只钳**文字缩放**：minSize / pngIcon / 文案 /
    //   切行公式 / 宽档单 Wrap 分支一律不动。
    final rollGroup = <Widget>[
      // ★ P17 C-3：`[−] [奖励 N] [↺]` 三段式复合控件（一个条目，不增加条目数）。
      _stepper(
        name: '奖励',
        value: local.bonus,
        minusKey: GpDiceBarKeys.bonusMinus,
        valueKey: GpDiceBarKeys.bonus,
        resetKey: GpDiceBarKeys.bonusReset,
        enabled: canRoll,
        blockedHint: blockedHint,
        baseHint: '奖励骰 +1（与惩罚骰互斥，范围 0–5；左段 −1，右段归零）',
        onSet: local.setBonus,
      ),
      _stepper(
        name: '惩罚',
        value: local.penalty,
        minusKey: GpDiceBarKeys.penaltyMinus,
        valueKey: GpDiceBarKeys.penalty,
        resetKey: GpDiceBarKeys.penaltyReset,
        enabled: canRoll,
        blockedHint: blockedHint,
        baseHint: '惩罚骰 +1（与奖励骰互斥，范围 0–5；左段 −1，右段归零）',
        onSet: local.setPenalty,
      ),
      // ★ P10 第 7 期（用户原话「1D100、1D4 等文字，D 前面的数字 1 都删掉」
      //   「工具栏仅保留 D100 和自定义骰子，其他骰子收到『其他骰子』弹窗」）：
      //   工具栏只留 D100；D4/D6/D8/D10/D12/D20 进弹窗。
      //   按钮 key 仍是 `gpDice/expr/1D100`（表达式不变），只是显示 `D100`。
      RoomTap(
        key: GpDiceBarKeys.expr(kDiceExprs.first),
        label: _diceLabelOf(kDiceExprs.first),
        pngIcon: 'dice/${_dicePngOf(kDiceExprs.first)}',
        enabled: canRoll,
        hint: canRoll ? '掷 ${kDiceExprs.first}' : blockedHint,
        minSize: RoomBtnSize.diceTile,
        onTap: () => _roll(kDiceExprs.first),
      ),
    ].map(clampBtnText).toList();

    // ---- 组 ②：自定义骰式 + 暗骰 + 战技/对抗 + 扩展 ----
    // ★ 下面两个 RoomTap 的 onTap 是 P10 第 6 期的真修复，逐字未改；
    //   两组在宽档拼成单个 Wrap（相对顺序与旧版一致），在窄档拼成
    //   _balancedRows 的均衡行，避免末尾落单成「战技单独一行」。
    //   ★ P17 C-3：`其他骰子` 移进尾组 —— 组① 两个三段式 stepper（各 ~112dp）
    //   + D100(90) 后就到 412dp 预算上限（112+112+90+90+3×4 = 416 > 392），
    //   原顺序会把「其他骰子」挤成孤行并被 Row 溢出裁掉（B1 实测 [7,1,4]）。
    //   移到尾组开头后：组① 322 ✓ 单行、尾组 6 项均衡切 [3,3] ✓ 无孤行。
    final tailGroup = <Widget>[
      RoomTap(
        key: GpDiceBarKeys.otherDice,
        label: '其他骰子',
        icon: Icons.casino_outlined,
        enabled: canRoll,
        hint: canRoll ? 'D4 / D6 / D8 / D10 / D12 / D20' : blockedHint,
        minSize: RoomBtnSize.diceTile,
        onTap: () => _openOtherDice(context, canRoll),
      ),
      SizedBox(
        width: 68,
        child: TextField(
          key: GpDiceBarKeys.customExpr,
          controller: _custom,
          enabled: canRoll,
          style: theme.textTheme.bodySmall,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '3D6+1',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (String v) => _roll(v),
          // ★ P16 C-2：点击输入框外部即失焦（控件级，不吞兄弟按钮点击、
          //   不影响 tester.enterText；禁止页面级 FocusNode / GestureDetector）。
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
        ),
      ),
      RoomTap(
        key: GpDiceBarKeys.rollCustom,
        icon: Icons.casino,
        hint: canRoll ? '掷自定义骰式' : blockedHint,
        enabled: canRoll,
        minSize: RoomBtnSize.diceTile,
        onTap: () => _roll(_custom.text),
      ),
      RoomTap(
        key: GpDiceBarKeys.dark,
        icon: Icons.visibility_off_outlined,
        label: local.darkRoll ? '暗骰开' : '暗骰关',
        enabled: canRoll,
        hint: canRoll ? '暗骰：结果只给你与 KP 看' : blockedHint,
        minSize: RoomBtnSize.diceTile,
        onTap: () => local.setDarkRoll(!local.darkRoll),
      ),
      // ---- 扩展按钮组：**只在被允许时渲染**（T-22 口径：能力边界在结构上）；
      //      enabled = `gate.can(op) && !locked`，T-30 探针两种分支都成立。 ----
      // ★ P10 第 6 期（用户真机报「战技 / 对抗点了没反应」）真因：
      //   · 战技原为 `hostAction('combat.roll')` **空参数**。domain 的
      //     `dispatchCombatAction` 对非 KP 走 `diceDirect`（只拿到
      //     expr/label/skill 三个 null）、对 KP 走 `diceRoll`（`p['result']`
      //     为空 ⇒ 只落一条 total=null 的空 DICE 记录）。两条路径都没有
      //     可看见的骰点 / 标签，用户感知就是「点了没反应」。
      //     改为走 `INTENT.DICE {direct:true}`：权威端 `diceDirect` 用规则
      //     服务复算并 PUBLIC 广播骰点，KP 与玩家两条路径都有可见反馈。
      //   · 对抗原为 `hostAction('check.opposed')` 空参数，domain
      //     `checkOpposed` 先 `resolveActorSkill(p['aSeat'], ...)` ⇒ 直接回
      //     「甲方无效：未指定对抗方类型」，用户看到「提示没有对象」。
      //     正确入口是已有的 `showOpposedSheet`（能选双方 / 通用 / 攻击 /
      //     武器对抗），改成打开弹层，不再发空 action。
      // ★ T-30 不变：两个按钮仍挂 `RoomKeys.action(op)`，
      //   `enabled` = `gate.can(op) && !locked`（P17 唯一允许的叠加项，
      //   见文件头「T-30 的 P17 修订」；探针口径由波4 同步改）。
      //   结构门控（`if (gate.can(...))`）一字不动：锁定时是**禁用**而不是
      //   「结构上消失」，否则锁定态与无权限态在 UI 上无法区分。
      if (gate.can('combat.roll'))
        RoomTap(
          key: RoomKeys.action('combat.roll'),
          icon: Icons.gavel,
          label: '战技',
          enabled: gate.can('combat.roll') && !locked,
          hint: locked ? blockedHint : '战技检定：掷 1D100 并广播骰点',
          minSize: RoomBtnSize.diceTile,
          onTap: () => controller.sendIntent(
            RoomIntent.dice,
            <String, Object?>{
              'expr': '1D100',
              'label': '战技',
              'skill': '战技',
              'direct': true,
              'bonus': local.bonus,
              'penalty': local.penalty,
              if (local.darkRoll) 'secret': true,
            },
          ),
        ),
      // ★ 2.34.0 / I16（PV-2）：「治疗」从 room_game_page.dart 的 mainActions
      //   移到骰子条尾组，紧邻「战技」右侧。只开本机弹层、不发 intent，
      //   因此沿用 treatKey（不挂 RoomKeys.action，与 I12 同口径）。
      //   ★ 只挪按钮、不动骨架：不改 Wrap / width:double.infinity /
      //     diceMaxPerRow / _balancedRows / 本列表末尾的 .map(clampBtnText)。
      if (!isKp)
        RoomTap(
          // 与 room_game_page.dart:275 的 `RoomGamePage.treatKey` 逐字一致：
          //   static const Key treatKey = ValueKey<String>('gpToolbar/treat');
          // 这里写字面量而不引用常量，是因为 room_game_page.dart:44 已 import
          // 本文件，反向 import 会形成循环依赖。ValueKey<String> 按 value 判等，
          // 两个 key 完全等价，find.byKey 命中的是同一个按钮。
          key: const ValueKey<String>('gpToolbar/treat'),
          icon: Icons.medical_services_outlined,
          label: '治疗',
          hint: '急救 / 医学 / 精神分析：先选技能，再选队友与检定值',
          // ★ P17 P-3：锁定态禁用（与旧 mainActions 实现逐字同口径）。
          enabled: !locked,
          minSize: RoomBtnSize.toolbarWide,
          onTap: () =>
              openTreatSheet(context, ctl: RoomScope.read(context).controller),
        ),
      // ★ 2.34.0 / I2（R1 门控，最高优先）：T01 把 check.opposed 的 POLICY
      //   放宽成 [kp, player] + RoomConfirm.kp 后，玩家 gate.can 变 true，
      //   单靠 gate.can 会让玩家侧结构性新渲染出 KP 手填裁定弹层入口
      //   （既破骰子条 9 项条目口径，又给玩家看错 UI）。这里只把 isKp 叠到
      //   **渲染条件**：玩家侧仍 findsNothing，KP 侧逐字不变。
      //   ★ RoomTap 的 `enabled: gate.can('check.opposed') && !locked`、
      //     RoomKeys.action 锚点、showOpposedSheet 回调全部逐字不动
      //     （T-30 管的是 enabled，不是渲染条件；契约 §5.2 已复核）。
      if (isKp && gate.can('check.opposed'))
        RoomTap(
          key: RoomKeys.action('check.opposed'),
          icon: Icons.compare_arrows,
          label: '对抗',
          enabled: gate.can('check.opposed') && !locked,
          hint: locked ? blockedHint : '打开对抗检定：选双方与对抗类型',
          minSize: RoomBtnSize.diceTile,
          onTap: () => showOpposedSheet<void>(context),
        ),
      ...widget.extensions,
    ].map(clampBtnText).toList();

    // ★ 分档要在 Container **外面**量：把它塞进外层 Wrap 的 child 时，
    //   容器默认按内容收缩（412dp 竖屏实测只有 ~300dp），9 个骰式按钮
    //   会排成 4+4+1，末尾又出现新的孤行。窄档强制占满整行后，内部
    //   拿到 ~392dp，实测排成 5+4，加上尾组 4 个 = 3 行且无孤行。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints outer) {
        final narrow = outer.maxWidth.isFinite &&
            outer.maxWidth < _kGroupBelowWidth;
        return Container(
          key: RoomKeys.gpDiceBar,
          width: narrow ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            // 掷骰条底纹（E8）：纯背景，不动任何按钮结构
            image: DecorationImage(
              image: AssetImage(Art.diceBar),
              fit: BoxFit.cover,
              opacity: Palette.isDark ? 0.38 : 0.20,
            ),
          ),
          // ★ P12 口径：描边走 foregroundDecoration（只绘制、不参与布局），
          //   不把 48×48 热区撑成 50×50 挤出一行。
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          child: narrow
              // 窄档：按可用宽度均衡切行（412dp 实测 4/3/3/3），
              // 每行至少 3 个按钮，末尾不再出现「战技单独一行」。
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final row in _balancedRows(
                      <Widget>[...rollGroup, ...tailGroup],
                      // ★ P17 C-3：两个三段式 stepper（各 ~112dp）比标准 90dp
                      //   条目各宽出 ~22dp。直接按标准宽算 per=4 会让行1
                      //   （112+112+90+90+3×4 = 416）超出 392，被 Wrap 二次
                      //   换行成「其他骰子」孤行（B1 实测 [7,1,4]）。把可用宽
                      //   按 stepper 的额外宽折算（392-44=348 → per=3），
                      //   行分布 3/3/2，无孤行、无溢出。
                      diceMaxPerRow(outer.maxWidth - 44),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Wrap(
                          spacing: 3,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: row,
                        ),
                      ),
                  ],
                )
              // 宽档：与旧版完全一致的「单个 Wrap 一行流」，工具栏不加高。
              : Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[...rollGroup, ...tailGroup],
                ),
        );
      },
    );
  }

  /// P17 C-3：奖惩骰的**三段式**复合控件 `[−] [名称 N（点=+1）] [↺]`。
  ///
  /// ★ 为什么是一个条目而不是三个条目：条目数是切行公式的入参
  ///   （`_balancedRows` → `diceBalancedRowSizes(9, per)`），一旦从 9 变 13，
  ///   412dp 会从 `3/3/3` 掉成 `4/3/3/3`、360dp 掉成 `3/3/3/2/2`，
  ///   P-4 的「4 行 = 4/3/3/3」直接做不到。三段拼成**一个** `Row` 后条目数
  ///   仍是 9，切行与行数一字未变。
  /// ★ 三段都是独立 `RoomTap`（各有稳定 key），所以：
  ///   · 中间段的 key 仍是 [GpDiceBarKeys.bonus] / [(penalty)]，点它 = +1
  ///     （既有「点 3 次 → 3」用例逐字不动）；
  ///   · 禁用语义三段一致（旁观者 / 锁定态整组不可点，不会出现「能减不能加」）。
  /// ★ 夹取全在 `RoomUiLocal.setBonus/setPenalty`：`v<0→0`、`v>5→5`、
  ///   `n>0` 才清对面一侧 ⇒ 传 `-1` 在 0 处仍是 0（不会变负）、传 `0` 是真归零
  ///   且**不会**误清另一侧。本方法不自己 clamp，避免两份夹取漂移。
  /// ★ 宽度账（**为什么值段不带 `+` 图标、且文字里不留空格**）：
  ///   一段纯图标 `RoomTap` 的内容宽 = 12 内边距 + 18 图标 = 30；
  ///   值段文字按测试字体每字 13.25 计，`奖励 0` 有 4 个字形 = 53，
  ///   带 `+` 图标还要再加 18+4 ⇒ 一个复合控件会到 125~131。
  ///   360dp 档骰子条内容宽只有 **340**，而第 2 行是「奖励 + 惩罚 + D100」：
  ///   `125×2 + 90 + 6 = 346 > 340` → 内部 Wrap 会多折一行，P16 的
  ///   「360dp 仍 3 行」用例直接红。去掉 `+` 图标、`奖励0` 去掉空格后
  ///   复合控件 ≈112，`112×2 + 90 + 6 = 320 ≤ 340` ✓，412dp（内容 392）也宽裕。
  ///   **加一的入口仍是值段本身**（点数字 = +1），语义与 P16 完全一致
  ///   （既有「点 bonus ×3 → bonus:3」用例逐字不动）。
  Widget _stepper({
    required String name,
    required int value,
    required Key minusKey,
    required Key valueKey,
    required Key resetKey,
    required bool enabled,
    required String blockedHint,
    required String baseHint,
    required ValueChanged<int> onSet,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RoomTap(
          key: minusKey,
          icon: Icons.remove,
          enabled: enabled,
          hint: enabled ? '$name骰 −1（最低 0）' : blockedHint,
          minSize: _kZoneMin,
          onTap: () => onSet(value - 1),
        ),
        RoomTap(
          key: valueKey,
          label: '$name$value',
          enabled: enabled,
          hint: enabled ? baseHint : blockedHint,
          minSize: _kZoneMin,
          onTap: () => onSet(value + 1),
        ),
        RoomTap(
          key: resetKey,
          icon: Icons.restart_alt,
          enabled: enabled,
          hint: enabled ? '$name骰归零' : blockedHint,
          minSize: _kZoneMin,
          onTap: () => onSet(0),
        ),
      ],
    );
  }

  /// 「其他骰子」居中弹层：D4 / D6 / D8 / D10 / D12 / D20。
  ///
  /// 复用同一个 [_roll] 回调，`INTENT.DICE` 载荷与工具栏上的 D100 **完全一致**
  /// （只发 op + p，信封形状由会话组装）；显示文案去掉前导 1，但表达式仍是
  /// `1D4`…`1D20`，规则层 / 既有载荷断言不需要任何改动。
  /// 用 `showGeneralDialog`（项目统一弹层底层，零裸 `showDialog`）。
  ///
  /// ★ P17 P-3：入参从「非旁观者」改成「可掷骰 = 非旁观者 && !锁定」，
  ///   弹层已开着时若本人进入锁定态，里面 6 个骰式按钮同样禁用。
  Future<void> _openOtherDice(BuildContext context, bool canRoll) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '其他骰子',
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (BuildContext ctx, Animation<double> _,
              Animation<double> _) =>
          SafeArea(
        child: Center(
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('其他骰子',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final e in kDiceExprs)
                        if (e != kDiceExprs.first)
                          RoomTap(
                            key: GpDiceBarKeys.expr(e),
                            label: _diceLabelOf(e),
                            pngIcon: 'dice/${_dicePngOf(e)}',
                            enabled: canRoll,
                            hint: canRoll ? '掷 $e' : '当前不可掷骰',
                            minSize: const Size(64, 40),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _roll(e);
                            },
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
