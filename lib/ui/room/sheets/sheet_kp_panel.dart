// ============================================================
// sheets/sheet_kp_panel.dart — KP 工具弹层根（设计 §5 T04 / S4.2）
//
// 三件最硬的事都在这里收口：
//   ① 未读角标公式（纯函数，可脱离 widget 逐项断言）：
//      `pending(need ∈ {twice, kp}) + requests + (opposed.phase=='await_kp' ? 1 : 0)`
//      —— pending / requests 一律取会话的**本机只读面**，不去权威快照里找
//      （这两份数据本就不在广播态里，去 state 里找会得到永远为空的假绿）。
//      ★ P10 第 6 期收尾起：**弹层里不再展示**这个角标（见 KpPanel 的说明），
//        纯函数与 `room_ui_kp_test.dart` 的直接单测**保留** —— 它们验的是
//        「计入口径」这条语义本身（哪些 need 算数、requests 怎么计数），
//        不依赖 UI 是否展示；将来谁再要角标（例如工具栏入口）可直接复用。
//   ② 待确认队列逐条确认 / 取消：走 13 个意图通道的 confirm，
//      载荷 `{op, by, agree}`，与权威端按 op+by 定位待办的口径一致。
//      ★ P10 第 6 期收尾起：整个「待处理」区块从弹层撤掉，确认/取消改由
//        页面级 `RoomRequestWatcher` 的居中弹窗承载（载荷与这里**逐字相同**，
//        仍是 `{op, by, agree}`）；本文件不再渲染任何确认行。
//   ③ `room.close` / `session.end` **必须点两次**才发 action（K-03），
//      且所有 action 入口的可点性恰好等于可点性闸门的结果（T-30）。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ★ 本文件不引用任何其他 KP 弹层：后续批次通过 [onOpen] 回调接线，
//   并行批次之间不会互相卡编译。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asMap;
import '../../../domain/room_types.dart' show RoomConfirm;
import '../room_keys.dart';
import '../room_scope.dart';
import '../room_session.dart' show RoomSession;
import '../view/room_view.dart' show playersOf;
import '../widgets/room_panel_kit.dart'
    show RoomTap, SectionBox;
import 'room_sheet.dart' show showRoomSheet;
import 'sheet_char_view.dart' show showCharViewSheet;
import 'sheet_combat.dart' show showCombatSheet;
import 'sheet_dice_tools.dart' show showDiceToolsSheet;
import 'sheet_kp_directives.dart' show showKpDirectivesSheet;
import 'sheet_opposed.dart' show showOpposedSheet;
import 'sheet_misc.dart' show openMiscSheet;
import 'sheet_music.dart' show openMusicSheet;
import 'sheet_save_slots.dart' show openSaveSlotsSheet;
import 'sheet_scene.dart' show showSceneSheet;
import '../room_text.dart';

// ------------------------------------------------------------
// 纯函数层：未读角标（S4.2 / 验收 ④）
// ------------------------------------------------------------

/// 计入角标的待办确认类型（其余 `owner` / `all` / null 都不计）。
const List<String> kKpUnreadNeeds = <String>[
  RoomConfirm.twice,
  RoomConfirm.kp,
];

/// 单条待办是否计入未读。
bool kpPendingCounts(Map<String, Object?> q) =>
    kKpUnreadNeeds.contains(roomText(q['need']));

/// 筛出计入角标的待办（保留原顺序，不修改入参）。
List<Map<String, Object?>> kpCountablePending(
        List<Map<String, Object?>> pending) =>
    pending.where(kpPendingCounts).toList(growable: false);

/// 逐 seat 的改状态请求总数。
int kpRequestCount(Map<String, List<Map<String, Object?>>> requestsBySeat) {
  var total = 0;
  for (final list in requestsBySeat.values) {
    total += list.length;
  }
  return total;
}

/// 当前是否有「待 KP 裁定」的对抗申请。
bool kpOpposedAwaitingKp(Map<String, Object?> state) =>
    roomText(asMap(state['opposed'])['phase']) == 'await_kp';

/// ★ 未读角标：三项相加，逐项可单独断言。
int kpUnreadCount({
  required List<Map<String, Object?>> pending,
  required Map<String, List<Map<String, Object?>>> requestsBySeat,
  required Map<String, Object?> state,
}) {
  return kpCountablePending(pending).length +
      kpRequestCount(requestsBySeat) +
      (kpOpposedAwaitingKp(state) ? 1 : 0);
}

/// 从会话直接取数（KP 面板用）。非 KP 视角没有本机只读面 → 恒 0。
int kpUnreadCountOf(RoomSession session) {
  final read = session.hostRead;
  return kpUnreadCount(
    pending: read == null
        ? const <Map<String, Object?>>[]
        : read.pending,
    requestsBySeat: read == null
        ? const <String, List<Map<String, Object?>>>{}
        : read.requestsBySeat,
    state: session.state,
  );
}

// ------------------------------------------------------------
// 稳定 key
// ------------------------------------------------------------

/// KP 面板内部稳定 key（`kpPanel` 是根，供接线与测试定位）。
///
/// ★ P10 第 6 期收尾：`unread` / `pendingList` / `opposedCard` / `requestList`
///   四个 key 已随「待处理」区块一起从 UI 撤下，但**常量保留** ——
///   `room_ui_kp_test.dart` / `room_ui_confirm_flow_test.dart` 用它们做
///   「新口径反向断言」（`findsNothing`：弹层里不许再出现），删掉会导致
///   回归断言无法编译。它们不代表还有 UI 在用。
class KpPanelKeys {
  const KpPanelKeys._();

  static const Key root = ValueKey<String>('kpPanel');

  /// 已从 UI 撤下（保留供「不再渲染」的反向断言）。
  static const Key unread = ValueKey<String>('kpPanel/unread');
  static const Key pendingList = ValueKey<String>('kpPanel/pendingList');
  static const Key opposedCard = ValueKey<String>('kpPanel/opposedCard');
  static const Key requestList = ValueKey<String>('kpPanel/requestList');

  static const Key saveNow = ValueKey<String>('kpPanel/saveNow');
  static const Key saveSlots = ValueKey<String>('kpPanel/saveSlots');
  static const Key misc = ValueKey<String>('kpPanel/misc');

  /// P17 / KP-8：音乐控制台从「更多工具」（二级弹层）上移一级到本弹层。
  ///
  /// ★ 与 `MiscSheetKeys.musicEntry`（保留但不再渲染）是**两个 key**：
  ///   入口换了宿主，测试要能分别断言「更多工具不含 / KP 工具含」。
  static const Key music = ValueKey<String>('kpPanel/music');
}

/// 弹层分派 id（后续批次把同名弹层接进来，第一个批次只留占位说明）。
const List<String> kKpSheetIds = <String>[
  'directives',
  'opposed',
  'combat',
  'scene',
  'charView',
  'diceTools',
  'saveSlots',
  'misc',
];

/// 弹层打开回调：`sheetId` 取 [kKpSheetIds] 之一。
typedef KpSheetOpener = void Function(BuildContext context, String sheetId);

/// KP 面板的弹层分派表（T04 全部 KP 侧弹层的唯一入口）。
///
/// `saveSlots` 已在 T05 接上真入口（`openSaveSlotsSheet`）。
void openKpSheet(BuildContext context, String sheetId) {
  switch (sheetId) {
    case 'directives':
      showKpDirectivesSheet<void>(context);
      return;
    case 'opposed':
      showOpposedSheet<void>(context);
      return;
    case 'combat':
      showCombatSheet<void>(context);
      return;
    case 'scene':
      showSceneSheet<void>(context);
      return;
    case 'charView':
      final session = RoomScope.read(context).session;
      final rows = playersOf(session.state);
      if (rows.isEmpty) {
        showRoomSheet<void>(
          context: context,
          title: '人物卡',
          body: (BuildContext _) => const Text('暂无玩家可查看。'),
        );
        return;
      }
      showCharViewSheet<void>(context, seat: '${rows.first['seat']}');
      return;
    case 'diceTools':
      showDiceToolsSheet<void>(context);
      return;
    case 'saveSlots':
      // T05 已交付存档槽弹层：直接接真入口（不再是只读说明）。
      openSaveSlotsSheet(context);
      return;
    case 'misc':
      // 规则参考 / 物品 / UI 缩放 / 观众名单 / P2 占位（T05 的杂项弹层）
      openMiscSheet(context);
      return;
    default:
      showRoomSheet<void>(
        context: context,
        title: 'KP 工具 · $sheetId',
        body: (BuildContext _) => const Text('未知分组。'),
      );
  }
}

// ------------------------------------------------------------
// 二次确认（K-03：第一次只改文案，第二次才发 intent）
// ------------------------------------------------------------

/// 危险操作按钮：连点两次才触发 [onConfirmed]。
///
/// `enabled` 由调用方用闸门结果传入；禁用时连点不会推进状态。
class KpDangerAction extends StatefulWidget {
  const KpDangerAction({
    super.key,
    required this.op,
    required this.label,
    required this.enabled,
    required this.hint,
    required this.onConfirmed,
    this.confirmLabel = '再点一次确认',
  });

  /// 动作名（同时用于稳定 key，表驱动权限探针据此取按钮）。
  final String op;
  final String label;
  final bool enabled;
  final String hint;
  final VoidCallback onConfirmed;
  final String confirmLabel;

  @override
  State<KpDangerAction> createState() => _KpDangerActionState();
}

class _KpDangerActionState extends State<KpDangerAction> {
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return RoomTap(
      key: RoomKeys.action(widget.op),
      label: _armed ? widget.confirmLabel : widget.label,
      icon: Icons.warning_amber_outlined,
      enabled: widget.enabled,
      hint: widget.hint,
      onTap: () {
        if (!_armed) {
          setState(() => _armed = true);
          return;
        }
        setState(() => _armed = false);
        widget.onConfirmed();
      },
    );
  }
}

// ------------------------------------------------------------
// 面板根
// ------------------------------------------------------------

/// `kpPanel` 根：三组工具 + 房间管理。
///
/// ★ P10 第 6 期收尾（用户原话「推送消息弹窗后，kp工具箱里面的就不要有了」）：
///   原来的「待处理」SectionBox（待确认 / 待裁定 / 待处理 + 未读角标）
///   **整块撤掉** —— 推送已由页面级 `RoomRequestWatcher` 居中弹窗直接承载，
///   并且弹窗里就能点「同意 / 拒绝」完成处理；KP 工具弹层再列一遍就是重复入口，
///   用户会以为要处理两次。弹窗是全局的（每个新请求都会弹，`Set<String> _seen`
///   按 id 去重），所以撤掉这一块**不会漏待办**。
///   其余三组工具（回合与检定 / 战斗与场景 / 房间管理）标题、按钮、
///   权限与 key 一律未动。
///
/// ★ P17 / KP-8：「工具 · 房间管理」组**新增**「音乐控制台」
///   （`KpPanelKeys.music`）—— 从二级「更多工具」上移一级，直接开本机播放
///   控制台；插在「更多工具」之后、危险操作之前，既有条目相对顺序未变。
class KpPanel extends StatelessWidget {
  const KpPanel({super.key, this.onOpen});

  final KpSheetOpener? onOpen;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;
    final session = scope.session;
    final read = session.hostRead;
    final opener = onOpen ?? openKpSheet;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: '工具 · 回合与检定',
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              // ★ 2.36.0 / Q6：「下一回合」已扁平挪进工具栏主组
              //   （缩放复位按钮右侧），此处不再重复渲染。
              _action(
                op: 'check.request',
                label: '要求检定',
                icon: Icons.casino,
                enabled: gate.can('check.request'),
                onTap: () => opener(context, 'scene'),
              ),
              _action(
                op: 'room.rules',
                label: '成败阈值',
                icon: Icons.tune,
                enabled: gate.can('room.rules'),
                onTap: () => opener(context, 'diceTools'),
              ),
            ],
          ),
        ),
        SectionBox(
          title: '工具 · 战斗与场景',
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              _action(
                op: 'check.opposed',
                label: '对抗',
                icon: Icons.sports_kabaddi,
                enabled: gate.can('check.opposed'),
                onTap: () => opener(context, 'opposed'),
              ),
              // ★ 2.36.0 / Q6：「战斗准备」已扁平挪进工具栏主组
              //   （缩放复位按钮右侧），此处不再重复渲染。
              _action(
                op: 'scene.check.push',
                label: '检定编辑器',
                icon: Icons.fact_check,
                enabled: gate.can('scene.check.push'),
                onTap: () => opener(context, 'scene'),
              ),
              _action(
                op: 'sheet.damage',
                label: '定向指令',
                icon: Icons.gps_fixed,
                enabled: gate.can('sheet.damage'),
                onTap: () => opener(context, 'directives'),
              ),
            ],
          ),
        ),
        SectionBox(
          title: '工具 · 房间管理',
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              RoomTap(
                key: KpPanelKeys.saveSlots,
                label: '存档槽',
                icon: Icons.save_as_outlined,
                hint: '本机存档：新建 / 载入 / 删除（关 App 即丢）',
                onTap: () => opener(context, 'saveSlots'),
              ),
              RoomTap(
                key: KpPanelKeys.misc,
                label: '更多工具',
                icon: Icons.more_horiz,
                hint: '规则参考 / 物品 / UI 缩放 / 观众名单 / P2 占位',
                onTap: () => opener(context, 'misc'),
              ),
              // ★ P17 / KP-8：音乐控制台上移一级 —— 真入口直接开本机播放控制台
              //   （与「更多工具」里的旧入口是同一个 `openMusicSheet`，
              //   不另写一套）。纯本机、不联网、不进存档，所以不动闸门。
              RoomTap(
                key: KpPanelKeys.music,
                label: '音乐控制台',
                icon: Icons.music_note_outlined,
                hint: '本机 BGM：选本机音频、5 个场景插槽、播放 / 暂停 / 停止（不联网、不打包音频）',
                onTap: () => openMusicSheet(context),
              ),
              RoomTap(
                key: KpPanelKeys.saveNow,
                label: '保存本局',
                icon: Icons.save,
                enabled: read != null,
                hint: read == null ? '只有 KP 能保存房间' : null,
                onTap: () => ctl.saveNow(),
              ),
              KpDangerAction(
                op: 'room.close',
                label: '结束房间',
                enabled: gate.can('room.close'),
                hint: gate.can('room.close')
                    ? '需要连续点击两次'
                    : '你没有权限执行该操作',
                onConfirmed: () => ctl.dangerAction('room.close'),
              ),
              KpDangerAction(
                op: 'session.end',
                label: '结团',
                enabled: gate.can('session.end'),
                hint: gate.can('session.end')
                    ? '需要连续点击两次'
                    : '你没有权限执行该操作',
                // ★ P20（需求 5 / D12）：原为 `ctl.hostAction('session.end')`，
                //   结团按钮**静默失效** —— `session.end` 在 POLICY 里是
                //   `RoomConfirm.twice`（`room_types.dart:304`），`hostAction`
                //   只把动作塞进 `pending`，没有人补那条 `INTENT.CONFIRM`，
                //   于是权威端永远不执行。`dangerAction`
                //   （`room_controller.dart`）在 `confirmOf(op) == twice` 时会
                //   追加 `RoomIntent.confirm{op, by: 我的 seat, agree: true}`；
                //   大厅的结团 / 关房走的就是它（`room_lobby_page.dart`），
                //   所以大厅正常、游戏内失效。「点两次才生效」这层本地确认
                //   仍由 `KpDangerAction` 保证，不放开任何一次点击。
                onConfirmed: () => ctl.dangerAction('session.end'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 统一 action 按钮：key + 可点性 + 拒绝文案三件套（T-30 / K6）。
  Widget _action({
    required String op,
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return RoomTap(
      key: RoomKeys.action(op),
      label: label,
      icon: icon,
      enabled: enabled,
      hint: enabled ? null : '你没有权限执行该操作',
      onTap: onTap,
    );
  }
}

/// 打开 KP 工具弹层。`onOpen` 由接线方注入各分组弹层。
Future<T?> showKpPanel<T>(
  BuildContext context, {
  KpSheetOpener? onOpen,
}) {
  return showRoomSheet<T>(
    context: context,
    title: 'KP 工具',
    body: (BuildContext _) => KpPanel(key: KpPanelKeys.root, onOpen: onOpen),
  );
}
