// ============================================================
// widgets/gp_scene_check_kp.dart — 块 5：KP 场景检定（设计 §5 T04 / S4.3）
//
// 三件事：
//   ① 步骤进度（只读派生）；
//   ② **检定方式**（P17 KP-2：目标 → 技能 → 成功所需等级 → 推送）；
//   ③ **2 个动作按钮**：推送检定（`scene.check.push`）+ 检定编辑器入口。
//
// ★ 2.34.0 / KP-6b：原「③ 6 档裁定结果」按钮（`5/4/3/2/0/-1`）已移除。
//   **删的只是 UI 入口**：domain `scene.check.step` POLICY、`sceneCheckStep`
//   （`autoAdvanceSceneCheck` 仍调用）与纯函数 [sceneCheckStepPayload] 全部
//   保留；载荷仍恰好 `{stepId, seat, level}` 三键，供权威端/自动推进复用。
//
// ★ P17 KP-2 口径（§6-Q1 已拍板）：四档「检定方式」= **结果等级当成功阈值**
//   成功 / 困难成功 / 极难成功 / 大成功 ⇒ 掷骰 ≤ 技能值 / ≤ base÷2 / ≤ base÷5 /
//   **只有 01**。`difficulty` 一律按 domain 的 `kRaDifficulty*` 常量**全大写**
//   入库（`raNormSceneDifficulty` 是唯一归一入口），避免老 APP
//   「大写载荷 + 小写规则键 → 困难/极难静默退化成常规」的坑。
//   ⚠️ 四档「检定方式」与已移除的 6 档「结果裁定」是两件事，本栏保留的是前者。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_model_actions_room.dart'
    show
        kRaDifficultyCritical,
        kRaDifficultyExtreme,
        kRaDifficultyHard,
        kRaDifficultyLevels,
        kRaDifficultyRegular;
import '../room_controller.dart' show RoomController;
import '../room_scope.dart';
import '../view/scene_view.dart'
    show
        sceneCheckCursor,
        sceneCheckOf,
        sceneCheckProgress,
        sceneCheckSteps;
import '../sheets/room_sheet.dart' show showRoomSheet;
import 'room_button_size.dart'
    show RoomBtnSize, RoomTapTile, clampBtnText, roomTapWrap2;
import 'room_panel_kit.dart' show SectionBox;
import 'unit_picker.dart'
    show
        kUnitAllValue,
        RoomUnitOption,
        UnitPickerField,
        unitValueToSeat;
import '../room_text.dart';

// ------------------------------------------------------------
// 2.34.0 / KP-6b：6 档结果裁定 UI 已移除
// ------------------------------------------------------------

// ★ `kSceneCheckLevels` / `kKpSceneLevels` / `GpSceneCheckKeys.level(int)` 与
//   6 档 `RoomTapTile` 循环一并删除（Wave2 用**硬编码**
//   `ValueKey<String>('gpSceneCheckKp/level/$lv')` 断言 findsNothing，不依赖
//   任何源码符号，故不留孤儿工厂）。domain `scene.check.step` POLICY /
//   `sceneCheckStep` 与 [sceneCheckStepPayload] 全部保留：`autoAdvanceSceneCheck`
//   仍调用；删 UI 按钮 ≠ 删 domain 能力。
// ★ [KpSceneLevel] 作为 public 数据模型按删除清单保留（清单未列、零引用、
//   不影响编译），不与任何 UI 入口绑定。

/// 一档「结果裁定」的数据模型（历史保留，本栏已不再渲染 6 档按钮）。
class KpSceneLevel {
  const KpSceneLevel(this.level, this.label);

  final int level;
  final String label;
}

// ------------------------------------------------------------
// P17 KP-2 · 「检定方式」四档（成功阈值）
// ------------------------------------------------------------

/// 一档「检定方式」。
///
/// [value] 直接取 domain 的 `kRaDifficulty*` 常量（**唯一真源**，全大写），
/// 本文件不重复写难度字面量；[label] / [hint] 只是展示文案。
class KpSceneMode {
  const KpSceneMode(this.value, this.label, this.hint);

  /// 入库值（`REGULAR` / `HARD` / `EXTREME` / `CRITICAL`）。
  final String value;

  /// 按钮文案。
  final String label;

  /// 阈值说明（给按钮 hint + 区块标题下的口径说明）。
  final String hint;
}

/// 四档「检定方式」，由易到难。
///
/// 与 domain [kRaDifficultyLevels] 逐项对应（顺序 / 值都必须一致），
/// 波4 可以用 `kKpSceneModes[i].value == kRaDifficultyLevels[i]` 直接钉住。
/// ★ `sheets/sheet_scene.dart:85-114` 的 `_ModePicker` 复用本表，务必保留。
const List<KpSceneMode> kKpSceneModes = <KpSceneMode>[
  KpSceneMode(kRaDifficultyRegular, '成功', '掷骰 ≤ 技能值'),
  KpSceneMode(kRaDifficultyHard, '困难成功', '掷骰 ≤ 技能值 ÷ 2（向下取整）'),
  KpSceneMode(kRaDifficultyExtreme, '极难成功', '掷骰 ≤ 技能值 ÷ 5（向下取整）'),
  KpSceneMode(kRaDifficultyCritical, '大成功', '只有掷出 01 才算成功'),
];

/// 取某档的展示文案（未知值按常规档）。
KpSceneMode kpSceneModeOf(String value) {
  for (final m in kKpSceneModes) {
    if (m.value == value) return m;
  }
  return kKpSceneModes.first;
}

/// ★ 唯一载荷生成处：恰好三个键，逐字段可断言。
///
/// 2.34.0 / KP-6b：本栏不再渲染 6 档手动裁定按钮，但**本纯函数与 domain
/// `scene.check.step` 能力全部保留**（`autoAdvanceSceneCheck` 与权威端仍复用）。
Map<String, Object?> sceneCheckStepPayload({
  required String stepId,
  required String seat,
  required int level,
}) {
  return <String, Object?>{
    'stepId': stepId,
    'seat': seat,
    'level': level,
  };
}

/// 块 5 内部稳定 key。
class GpSceneCheckKeys {
  const GpSceneCheckKeys._();

  static const Key root = ValueKey<String>('gpSceneCheckKp');
  static const Key progress = ValueKey<String>('gpSceneCheckKp/progress');
  static const Key quickPush = ValueKey<String>('gpSceneCheckKp/quickPush');
  static const Key editor = ValueKey<String>('gpSceneCheckKp/editor');

  // ---- P17 KP-2：检定方式四步（目标 / 技能 / 等级 / 推送） ----

  /// 检定方式子块。
  static const Key modeRoot = ValueKey<String>('gpSceneCheckKp/mode');

  /// ① 目标（全体或某个玩家 / 单位）。
  static const Key modeTarget = ValueKey<String>('gpSceneCheckKp/modeTarget');

  /// ② 要检定的技能（纯文本，老 APP 同款）。
  static const Key modeSkill = ValueKey<String>('gpSceneCheckKp/modeSkill');

  /// ③ 某一档成功等级按钮（值取 `kRaDifficulty*`）。
  static Key mode(String value) =>
      ValueKey<String>('gpSceneCheckKp/mode/$value');
}

/// 快速推送的一步（自定义检定，不需要编辑器也能发起）。
///
/// P17 KP-2：技能 / 目标 / 难度参数化（默认值与改前一致），`difficulty`
/// 由调用方传入 **domain 常量**，这里不再写难度字面量。
Map<String, Object?> kpQuickSceneStep({
  String skill = '侦查',
  String targetSeat = kUnitAllValue,
  String difficulty = kRaDifficultyRegular,
}) =>
    <String, Object?>{
      'id': 's1',
      'title': '快速检定',
      'skill': skill,
      'targetSeat': targetSeat,
      'difficulty': difficulty,
    };

/// KP 场景检定块。
class GpSceneCheckKp extends StatefulWidget {
  const GpSceneCheckKp({super.key, this.onOpenEditor});

  /// 编辑器入口（接线方注入；缺省时用统一弹层壳显示提示）。
  final void Function(BuildContext context)? onOpenEditor;

  @override
  State<GpSceneCheckKp> createState() => _GpSceneCheckKpState();
}

class _GpSceneCheckKpState extends State<GpSceneCheckKp>
    with AutomaticKeepAliveClientMixin<GpSceneCheckKp> {
  // ---- 检定方式草稿（本地态，不进权威状态） ----

  /// ① 目标：统一枚举 value（`*` / `p:<seat>` / `a:<id>`）。
  String _target = kUnitAllValue;
  String _targetLabel = '全体';

  /// ② 技能（纯文本框）。
  final TextEditingController _skill = TextEditingController(text: '侦查');

  /// ② 技能输入框的显式焦点节点（KP-6a：与 [_skill] 同生命周期）。
  late final FocusNode _skillFocus;

  /// ③ 成功所需等级（domain 常量，全大写入库）。
  String _difficulty = kRaDifficultyRegular;

  @override
  void initState() {
    super.initState();
    // ★ KP-6a：显式持有 FocusNode，键盘弹出触发 dock→folded 翻档时，输入框的
    //   焦点 / 文本状态随本 State 保留；不循环 requestFocus、不延时重聚焦。
    _skillFocus = FocusNode();
  }

  /// ★ KP-6a：本栏子树始终保活（收起 `GpKpPlayers` 时绝不卸载本组件）。
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _skillFocus.dispose();
    _skill.dispose();
    super.dispose();
  }

  /// ④ 推送：一步自定义检定，载荷字段与老 APP `scene.check.push` 一致。
  void _push(RoomController ctl) {
    final skill = _skill.text.trim();
    if (skill.isEmpty) {
      ctl.notice('请先填写要检定的技能');
      return;
    }
    ctl.hostAction('scene.check.push', <String, Object?>{
      'title': '快速检定',
      'desc': '',
      'steps': <Object?>[
        kpQuickSceneStep(
          skill: skill,
          targetSeat: unitValueToSeat(_target),
          difficulty: _difficulty,
        ),
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    // ★ AutomaticKeepAliveClientMixin 契约：必须调 super.build，返回值忽略。
    super.build(context);

    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;
    final state = scope.session.state;
    final check = sceneCheckOf(state);
    final steps = sceneCheckSteps(state);
    final cursor = sceneCheckCursor(state);
    final progress = sceneCheckProgress(state);
    final hasStep = cursor >= 0 && cursor < steps.length;
    final step = hasStep ? steps[cursor] : const <String, Object?>{};
    final stepId = roomText(step['id']);
    final seat = roomText(step['targetSeat']);
    final canPush = gate.can('scene.check.push');

    return SectionBox(
      key: GpSceneCheckKeys.root,
      title: '场景检定',
      // ★ KP-5：两格叠放成 `RoomStackNode` 共 rect 后，本 [SectionBox] 拿到的是
      //   `Stack + Positioned.fill` 的**有界高度**（整个右列）。通用件 `SectionBox`
      //   内部是 `Column(mainAxisSize.min)`（`room_panel_kit.dart:75-78`，本任务
      //   文件集不含它、不许改）：内容一旦高于该紧约束就会 RenderFlex overflow。
      //   这里给内容区加一层 [SingleChildScrollView] —— 有界高度下可滚动、
      //   松约束下按内容收缩，**不写死任何像素高度**，也不依赖无限高度假设。
      //   `PageStorageKey` 同时稳住滚动 / 输入态（KP-6a）。
      //   ★ 本文件不含任何「收起 / 隐藏」逻辑；收起态只控 `GpKpPlayers` 子树，
      //     绝不卸载 `GpSceneCheckKp`。
      child: SingleChildScrollView(
        key: const PageStorageKey<String>('gpSceneCheckKp/body'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              key: GpSceneCheckKeys.progress,
              children: <Widget>[
                Expanded(
                  child: Text(
                    check == null
                        ? '暂无进行中的检定'
                        : '${roomText(check['title'])} · $cursor/${steps.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text('${(progress * 100).round()}%',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            if (hasStep)
              Text('当前步：$stepId · 目标：$seat',
                  style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 6),

            // ---- ★ P17 KP-2：检定方式（① 目标 ② 技能 ③ 等级 ④ 推送）----
            Column(
              key: GpSceneCheckKeys.modeRoot,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('检定方式（成功阈值）',
                    style: TextStyle(fontSize: 11)),
                // ★ 这一格只有 266.9 宽（内容 238.9），'① 目标：xxx' 在 2.0 倍字号
                //   下会顶破 `RoomTap` 内那个 `mainAxisSize.min` 的 Row ⇒ 只钳本
                //   按钮子树（不动面板其它文字）。
                clampBtnText(
                  UnitPickerField(
                    key: GpSceneCheckKeys.modeTarget,
                    label: '① 目标',
                    display: _targetLabel,
                    title: '选择检定目标',
                    allowAll: true,
                    enabled: canPush,
                    onPicked: (RoomUnitOption o) => setState(() {
                      _target = o.value;
                      _targetLabel = o.label;
                    }),
                  ),
                ),
                // ★ KP-6a 输入态三件套：
                //   ① 祖先 `PageStorageKey`（稳定滚动 / 输入态；**不覆盖**下层的
                //      [GpSceneCheckKeys.modeSkill] —— A.3 收起后正向断言仍靠它）；
                //   ② 显式 `FocusNode`（本 State 持有，initState 建 / dispose 释）；
                //   ③ State 上的 [AutomaticKeepAliveClientMixin]（wantKeepAlive=true）。
                //   ★ 禁循环 requestFocus / 延时重聚焦 / 禁用滚动 / ClipRect 硬裁；
                //     Scaffold 翻档的根因由 `room_game_page.dart:363` 侧修复。
                KeyedSubtree(
                  key: const PageStorageKey<String>(
                      'gpSceneCheckKp/modeSkill/page'),
                  child: TextField(
                    key: GpSceneCheckKeys.modeSkill,
                    controller: _skill,
                    focusNode: _skillFocus,
                    decoration: const InputDecoration(
                      labelText: '② 技能 / 属性',
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                // ③ 四档用定宽 tile（108×48，与下方 2 个动作按钮同规格）：
                //   文字缩放已由 `RoomTapTile` 内部 `clampBtnText` 钳到 1.0，
                //   1.3 / 1.5 / 2.0 三档都不会把定宽按钮撑破。
                roomTapWrap2(<Widget>[
                  for (final m in kKpSceneModes)
                    RoomTapTile(
                      roomKey: GpSceneCheckKeys.mode(m.value),
                      size: RoomBtnSize.sceneTile,
                      label: m.label,
                      icon: _difficulty == m.value ? Icons.check : null,
                      enabled: canPush,
                      hint: m.hint,
                      onTap: () => setState(() => _difficulty = m.value),
                    ),
                ]),
                Text('当前：${kpSceneModeOf(_difficulty).hint}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),

            // ★ 2.34.0 / KP-6b：本栏只剩 **2 个动作按钮**（推送检定 /
            //   检定编辑器），仍统一 108×48（`RoomBtnSize.sceneTile`）走
            //   `roomTapWrap2` 网格 —— 2 个正好 1 行 × 2 列，删档后网格
            //   不塌陷、无空白占位，两个按钮都保持可点、对齐正常。
            // ★ 108 的依据同步改为当前最长标签 `检定编辑器`（5 字，含图标与
            //   左右 12dp padding 实测远小于 108），`推送检定`（4 字）更短；
            //   尺寸值本身逐字不动（`p16_button_unify_test.dart` 钉住）。
            // ★ 列数仍**随档位**自适应：1280/1524 横屏格宽 266.9（内容
            //   238.9）⇒ `2×108 + 4 = 220` 放得下 2 列、`3×108 + 8 = 332`
            //   放不下 ⇒ **2 列**；412 竖屏单列通栏（内容 ≈368）⇒ 2 个同排。
            //   `Wrap` 在窄档自动掉列，不裁切、不 overflow、无孤行。
            // ★ 用定宽 tile 而不是 `RoomTapEqualRow`（等分）：等分宽度随栏宽变，
            //   写不进常量、也没法被精确尺寸断言守住。
            // ★ domain 的 `scene.check.step` POLICY / `sceneCheckStep` 与纯函数
            //   `sceneCheckStepPayload` 全部保留，删的只是 6 档 UI 入口。
            roomTapWrap2(<Widget>[
              // ④ 推送：发的是上面 ①②③ 选好的那一档（不再是写死的常规档）。
              RoomTapTile(
                roomKey: GpSceneCheckKeys.quickPush,
                size: RoomBtnSize.sceneTile,
                label: '推送检定',
                icon: Icons.send,
                enabled: canPush,
                hint: '按所选检定方式推送一步场景检定',
                onTap: () => _push(ctl),
              ),
              RoomTapTile(
                roomKey: GpSceneCheckKeys.editor,
                size: RoomBtnSize.sceneTile,
                label: '检定编辑器',
                icon: Icons.edit,
                enabled: canPush,
                hint: '打开多步检定编辑器',
                onTap: () {
                  final opener = widget.onOpenEditor;
                  if (opener != null) {
                    opener(context);
                    return;
                  }
                  showRoomSheet<void>(
                    context: context,
                    title: '场景检定编辑器',
                    body: (BuildContext _) => const Text('请在接线后打开完整编辑器。'),
                  );
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
