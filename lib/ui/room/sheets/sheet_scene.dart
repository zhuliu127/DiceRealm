// ============================================================
// sheets/sheet_scene.dart — 场景检定编辑器 / 要求检定 / 请求修改状态 /
//   素材与地图卡 + **独立递线索弹层**（设计 §5 T04 / S4.5）
//
// 多步编辑器的步骤载荷按 domain 的 `raSanitizeSceneSteps` 白名单逐字段写：
// `id/title/desc/targetSeat/skill/difficulty/bonus/penalty/onSuccess/onFailure`，
// 难度用 REGULAR / HARD / EXTREME / CRITICAL 四档（P17 KP-2 由三档扩到四档，
// 取值一律来自 domain 的 `kRaDifficulty*` 常量、**全大写**入库；小写/未知值
// 会被 `raNormSceneDifficulty` 归一，这里不再写难度字面量）。
//
// ★ P16 波1-A / KP-6：4 处纯文本座位输入全部改成**下拉选单位**，共用
//   `unit_picker.dart`（用户放宽到「玩家 + 已设置怪物 / NPC」）。统一枚举的
//   value 带 `p:`/`a:` 前缀，提交时用 [unitValueToSeat] 剥成 domain 期望的
//   裸 seat / '*'，载荷字段名与 domain 逻辑零改动；`'*' = 全体` 保留。
//
// ★ 2.34.0 / KP-6c（用户拍板 D7）：多步编辑器「推送给玩家」只发**一次**
//   `scene.check.push`，载荷字段（title/desc/steps[]）逐字不变。权威端一次
//   把 M 步 × N 人**全部展开**成 M×N 条 result + M×N 条 `kind:'check'`
//   PUBLIC log + 一次 sceneCheck 更新；本文件不自己循环发 action、不削减
//   步数。游戏记录栏照出 M×N 条，遮罩广播层由 `FeedOptoastTracker` 的
//   flood 守卫（一次 diff > 6 视为全量同步、不刷屏）兜住，两层解耦，
//   不许为了让遮罩好看而删减记录条数。
//
// ★ 2.34.0 / KP-7（契约 I10）：「递线索」能力已从 [SceneSheet] 整体收拢进
//   独立的 [showClueSheet] → [ClueSheet]，编辑器内不再有第二个入口。新
//   「递出」用独立 [SceneSheetKeys.clueSubmit]，绝不复用 `act/scene.clue`
//   锚点（契约 I12 禁用；原入口移除后该锚点才释放，且须保证全局
//   `findsOneWidget`）。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_model_actions_room.dart'
    show kRaDifficultyRegular;
import '../room_keys.dart';
import '../room_scope.dart';
import '../view/scene_view.dart'
    show assetsOf, marksOf, publicAssets, sceneOf, strokesOf;
import '../widgets/gp_scene_check_kp.dart' show kKpSceneModes;
import '../widgets/room_button_size.dart'
    show RoomBtnSize, RoomTapTile, roomTapWrap2;
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import '../widgets/unit_picker.dart'
    show
        kUnitAllValue,
        RoomUnitOption,
        UnitPickerField,
        unitValueToSeat;
import 'room_sheet.dart' show showRoomSheet;

/// 场景弹层内部稳定 key。
class SceneSheetKeys {
  const SceneSheetKeys._();

  static const Key root = ValueKey<String>('sceneSheet');
  static const Key title = ValueKey<String>('sceneSheet/title');
  static const Key desc = ValueKey<String>('sceneSheet/desc');
  static const Key addStep = ValueKey<String>('sceneSheet/addStep');
  static const Key push = ValueKey<String>('sceneSheet/push');
  /// ★ KP-7（2.34.0）：递线索能力已收拢进独立 [ClueSheet]；本 key 现在是
  /// 那个弹层的根 key（`SceneSheet` 内不再渲染「递线索」区）。
  static const Key clue = ValueKey<String>('sceneSheet/clue');
  static const Key requestCheck = ValueKey<String>('sceneSheet/requestCheck');
  static const Key requestState = ValueKey<String>('sceneSheet/requestState');
  static const Key assetSummary = ValueKey<String>('sceneSheet/assetSummary');

  /// KP-6：单值座位下拉的稳定 key（步骤座位沿用 stepSeat(i)）。
  /// `clueSeat` 随递线索能力一起收拢进 [ClueSheet]，编辑器内不再挂载。
  static const Key clueSeat = ValueKey<String>('sceneSheet/clueSeat');
  static const Key checkSeat = ValueKey<String>('sceneSheet/checkSeat');
  static const Key stateSeat = ValueKey<String>('sceneSheet/stateSeat');

  // ---- ★ KP-7 / 契约 I10+I12：递线索独立弹层的 3 个独立 ValueKey ----
  // 全部是独立 ValueKey，**绝不**挂 `act/scene.clue` 锚点
  // （I12 禁用；原「递出」移除后该锚点才释放，且须全局 findsOneWidget）。
  static const Key clueTitle = ValueKey<String>('sceneClue/title');
  static const Key clueText = ValueKey<String>('sceneClue/text');
  static const Key clueSubmit = ValueKey<String>('sceneClue/submit');

  static Key stepSkill(int i) =>
      ValueKey<String>('sceneSheet/step/$i/skill');

  static Key stepSeat(int i) =>
      ValueKey<String>('sceneSheet/step/$i/seat');

  static Key removeStep(int i) =>
      ValueKey<String>('sceneSheet/step/$i/remove');

  /// P17 KP-2：第 [i] 步的「检定方式」四档选择区。
  static Key stepMode(int i) => ValueKey<String>('sceneSheet/step/$i/mode');

  /// 第 [i] 步的某一档按钮（[value] 取 `kRaDifficulty*`）。
  static Key stepModeValue(int i, String value) =>
      ValueKey<String>('sceneSheet/step/$i/mode/$value');

  /// P17 KP-2：「要求检定」的「检定方式」四档选择区。
  static const Key requestMode = ValueKey<String>('sceneSheet/requestMode');

  /// 「要求检定」的某一档按钮（[value] 取 `kRaDifficulty*`）。
  static Key requestModeValue(String value) =>
      ValueKey<String>('sceneSheet/requestMode/$value');
}

/// 四档「检定方式」选择器（分段按钮，选中项带勾）。
///
/// 取值一律来自 domain 的 `kRaDifficultyLevels`；文案表复用 KP 场景检定块
/// 的 [kKpSceneModes]（唯一一份四档文案，避免两个弹层各写一套）。
/// ★ 定宽 tile 内部的文字缩放已由 `RoomTapTile` 钳到 1.0（1.3/1.5/2.0 档不破）。
class _ModePicker extends StatelessWidget {
  const _ModePicker({
    required this.sectionKey,
    required this.value,
    required this.enabled,
    required this.onPicked,
    required this.tileKey,
  });

  final Key sectionKey;
  final String value;
  final bool enabled;
  final ValueChanged<String> onPicked;
  final Key Function(String value) tileKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: sectionKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('检定方式（成功阈值）', style: TextStyle(fontSize: 11)),
        roomTapWrap2(<Widget>[
          for (final m in kKpSceneModes)
            RoomTapTile(
              roomKey: tileKey(m.value),
              size: RoomBtnSize.sceneTile,
              label: m.label,
              icon: value == m.value ? Icons.check : null,
              enabled: enabled,
              hint: m.hint,
              onTap: () => onPicked(m.value),
            ),
        ]),
      ],
    );
  }
}

/// 一步编辑器草稿。
class _StepDraft {
  _StepDraft()
      : skill = TextEditingController(text: '侦查'),
        targetSeat = kUnitAllValue,
        targetLabel = '全体';

  final TextEditingController skill;

  /// 选中单位的 value（`p:<seat>` / `a:<id>` / `*`）。
  String targetSeat;

  /// 选中单位的展示文案。
  String targetLabel;

  /// P17 KP-2：该步的成功阈值档（domain 常量，全大写）。
  String difficulty = kRaDifficultyRegular;

  void dispose() {
    skill.dispose();
  }

  Map<String, Object?> toPayload(int index) => <String, Object?>{
        'id': 'st${index + 1}',
        'title': '步骤 ${index + 1}',
        'desc': '',
        // 场景检定的 targetSeat 历来是裸 seat / '*'，剥掉统一枚举前缀。
        'targetSeat': unitValueToSeat(targetSeat),
        'skill': skill.text.trim(),
        'difficulty': difficulty,
        'bonus': 0,
        'penalty': 0,
        'onSuccess': <String, Object?>{},
        'onFailure': <String, Object?>{},
      };
}

/// 场景弹层。
class SceneSheet extends StatefulWidget {
  const SceneSheet({super.key});

  @override
  State<SceneSheet> createState() => _SceneSheetState();
}

class _SceneSheetState extends State<SceneSheet> {
  final TextEditingController _title =
      TextEditingController(text: '场景检定');
  final TextEditingController _desc = TextEditingController();

  // ---- KP-6：单值座位改「选中 value + 展示文案」 ----
  // ★ KP-7：递线索的 4 个状态字段（`_clueSeat` / `_clueLabel` /
  //   `_clueTitle` / `_clueText`）已整体收拢进 [_ClueSheetState]，
  //   编辑器内不再持有第二个递线索入口的草稿。
  String _checkSeat = 'p:p1';
  String _checkLabel = 'p1';
  final TextEditingController _checkSkill =
      TextEditingController(text: '侦查');

  /// P17 KP-2：「要求检定」的成功阈值档（domain 常量，全大写）。
  String _checkDifficulty = kRaDifficultyRegular;

  String _stateSeat = 'p:p1';
  String _stateLabel = 'p1';
  final TextEditingController _stateReason = TextEditingController();

  final List<_StepDraft> _steps = <_StepDraft>[_StepDraft()];

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _checkSkill.dispose();
    _stateReason.dispose();
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;
    final state = scope.session.state;
    final scene = sceneOf(state) ?? const <String, Object?>{};

    return Column(
      key: SceneSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: '场景检定编辑器',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: SceneSheetKeys.title,
                controller: _title,
                decoration: const InputDecoration(
                  labelText: '标题',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              TextField(
                key: SceneSheetKeys.desc,
                controller: _desc,
                decoration: const InputDecoration(
                  labelText: '描述',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              Text('步骤（${_steps.length}）',
                  style: const TextStyle(fontSize: 11)),
              for (var i = 0; i < _steps.length; i++)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            key: SceneSheetKeys.stepSkill(i),
                            controller: _steps[i].skill,
                            decoration: const InputDecoration(
                              labelText: '技能',
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // KP-6 ①：步骤目标座位 → 下拉选单位（保留全体）。
                        Expanded(
                          child: UnitPickerField(
                            key: SceneSheetKeys.stepSeat(i),
                            label: '目标',
                            display: _steps[i].targetLabel,
                            title: '选择目标单位',
                            allowAll: true,
                            onPicked: (RoomUnitOption o) => setState(() {
                              _steps[i].targetSeat = o.value;
                              _steps[i].targetLabel = o.label;
                            }),
                          ),
                        ),
                        RoomTap(
                          key: SceneSheetKeys.removeStep(i),
                          icon: Icons.delete_outline,
                          hint: '删除该步',
                          enabled: _steps.length > 1,
                          onTap: () {
                            final removed = _steps.removeAt(i);
                            removed.dispose();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    // P17 KP-2：该步的成功阈值档（四档，全大写入库）。
                    _ModePicker(
                      sectionKey: SceneSheetKeys.stepMode(i),
                      value: _steps[i].difficulty,
                      enabled: gate.can('scene.check.push'),
                      tileKey: (String v) =>
                          SceneSheetKeys.stepModeValue(i, v),
                      onPicked: (String v) =>
                          setState(() => _steps[i].difficulty = v),
                    ),
                  ],
                ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  RoomTap(
                    key: SceneSheetKeys.addStep,
                    label: '加一步',
                    icon: Icons.add,
                    enabled: gate.can('scene.check.push'),
                    hint: '最多 60 步',
                    onTap: () {
                      if (_steps.length >= 60) return;
                      setState(() => _steps.add(_StepDraft()));
                    },
                  ),
                  // ★ KP-6c / 用户拍板 D7：多步编辑器也只发**一次**
                  //   `scene.check.push`，载荷字段逐字不变（title/desc/
                  //   steps[]），不在此循环发 action、不削减步数。权威端
                  //   一次把 M 步 × N 人**全部展开**成 M×N 条 result +
                  //   M×N 条 `kind:'check'` PUBLIC log + 一次 sceneCheck
                  //   更新；游戏记录栏照出 M×N 条，遮罩广播层由
                  //   `FeedOptoastTracker` 的 flood 守卫（一次 diff > 6
                  //   视为全量同步、不刷屏）兜住，两层解耦，不许为遮罩
                  //   好看而删减记录条数。
                  RoomTap(
                    key: RoomKeys.action('scene.check.push'),
                    label: '推送给玩家',
                    icon: Icons.send,
                    enabled: gate.can('scene.check.push'),
                    hint: '推送多步场景检定',
                    onTap: () => ctl.hostAction(
                      'scene.check.push',
                      <String, Object?>{
                        'title': _title.text.trim(),
                        'desc': _desc.text.trim(),
                        'steps': <Object?>[
                          for (var i = 0; i < _steps.length; i++)
                            _steps[i].toPayload(i),
                        ],
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ★ KP-7（2.34.0 / 契约 I10）：「递线索」SectionBox 已整体移除，
        //   9 项能力逐项收拢进独立的 [showClueSheet] → [ClueSheet]。
        //   编辑器内不再有第二个递线索入口；`act/scene.clue` 这个锚点也
        //   随之释放（契约 I12 明确禁用，不再复用）。
        SectionBox(
          title: '要求检定 / 请求修改状态',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // KP-6 ③：检定座位 → 下拉选单位。
                  Expanded(
                    child: UnitPickerField(
                      key: SceneSheetKeys.checkSeat,
                      label: '座位',
                      display: _checkLabel,
                      title: '选择检定座位',
                      allowAll: true,
                      onPicked: (RoomUnitOption o) => setState(() {
                        _checkSeat = o.value;
                        _checkLabel = o.label;
                      }),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _checkSkill,
                      decoration: const InputDecoration(
                        labelText: '技能',
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              // P17 KP-2：「要求检定」也要能选成功阈值档（原来写死常规档）。
              _ModePicker(
                sectionKey: SceneSheetKeys.requestMode,
                value: _checkDifficulty,
                enabled: gate.can('check.request'),
                tileKey: SceneSheetKeys.requestModeValue,
                onPicked: (String v) => setState(() => _checkDifficulty = v),
              ),
              Row(
                children: <Widget>[
                  RoomTap(
                    key: RoomKeys.action('check.request'),
                    label: '要求检定',
                    enabled: gate.can('check.request'),
                    hint: '向该玩家发起检定请求',
                    onTap: () => ctl.hostAction(
                      'check.request',
                      <String, Object?>{
                        'seat': unitValueToSeat(_checkSeat),
                        'skill': _checkSkill.text.trim(),
                        'difficulty': _checkDifficulty,
                        'desc': '',
                      },
                    ),
                  ),
                  RoomTap(
                    key: RoomKeys.action('state.request'),
                    label: '请求改状态',
                    enabled: gate.can('state.request'),
                    hint: '生成一张需玩家同意的请求卡',
                    onTap: () => ctl.hostAction(
                      'state.request',
                      <String, Object?>{
                        'seat': unitValueToSeat(_stateSeat),
                        'change': <String, Object?>{},
                        'reason': _stateReason.text.trim(),
                      },
                    ),
                  ),
                ],
              ),
              // KP-6 ④：改状态目标座位 → 下拉选单位。
              UnitPickerField(
                key: SceneSheetKeys.stateSeat,
                label: '改状态目标座位',
                display: _stateLabel,
                title: '选择改状态目标',
                allowAll: true,
                onPicked: (RoomUnitOption o) => setState(() {
                  _stateSeat = o.value;
                  _stateLabel = o.label;
                }),
              ),
              TextField(
                controller: _stateReason,
                decoration: const InputDecoration(
                  labelText: '理由',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        SectionBox(
          title: '素材与地图',
          child: Text(
            '场景：${scene['title'] ?? ''} · '
            '笔迹 ${strokesOf(state).length} · 标记 ${marksOf(state).length} · '
            '素材 ${assetsOf(state).length}（公开 ${publicAssets(state).length}）',
            key: SceneSheetKeys.assetSummary,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 打开场景弹层。
Future<T?> showSceneSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: '场景与素材',
    body: (BuildContext _) => const SceneSheet(),
  );
}

// ------------------------------------------------------------
// ★ KP-7（2.34.0 / 契约 I10）：递线索能力收拢后的独立弹层
// ------------------------------------------------------------

/// ★ 契约 I10：打开「递线索」独立弹层。
///
/// 把原 [SceneSheet] 里「递线索」SectionBox 的 9 项能力逐项收拢到这里：
/// ① [SectionBox] 容器；② [UnitPickerField]（[SceneSheetKeys.clueSeat]，
/// `allowAll: true`，`* = 全体`）；③ 线索标题 [TextField]；④ 线索正文
/// [TextField]；⑤ 「递出」回调 `hostAction('scene.clue', {...})`；
/// ⑥ 4 个状态字段 + dispose；⑦ 稳定 key [SceneSheetKeys.clue] /
/// [SceneSheetKeys.clueSeat]；⑧ domain `sceneClue`
/// （`room_model_actions_room.dart:1164-1185`，`*` 逐人单发 PRIVATE +
/// 一条 PUBLIC log）与 POLICY `scene.clue=[kp]`；⑨ 行为与旧入口一致。
///
/// ★ 契约 I12：新「递出」用独立 [SceneSheetKeys.clueSubmit]
/// （`ValueKey<String>('sceneClue/submit')`），**绝对不复用** `act/scene.clue`
/// 锚点 —— 原「递出」移除后该锚点才释放，且新 key 必须保证全局
/// `findsOneWidget`；T03 打开本弹层的按钮用的是
/// `RoomGamePage.clueQuickKey`，与此处内部 key 互不冲突。
///
/// ★ 两条原有打开链路（`GpSceneCheckKp`「检定编辑器」经
/// `room_game_page.dart:892` 的 `onOpenEditor`、以及 `KpPanel` 经
/// `sheet_kp_panel.dart:168`）仍打开 [showSceneSheet]，逐字不动；递线索
/// 入口改由 T03 的工具栏新按钮调用本函数。
///
/// ★ C7：弹层 body 子树用 `MediaQuery.withClampedTextScaling` 钳到 1.0，
/// 保证 textScaler 1.3 / 1.5 / 2.0 下不溢出（只包子树，不抬到页面/Theme 层）。
Future<T?> showClueSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: '递线索',
    body: (BuildContext _) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: const ClueSheet(),
    ),
  );
}

/// 递线索独立弹层主体（能力从 [SceneSheet] 整体收拢，行为逐字一致）。
class ClueSheet extends StatefulWidget {
  const ClueSheet({super.key});

  @override
  State<ClueSheet> createState() => _ClueSheetState();
}

class _ClueSheetState extends State<ClueSheet> {
  // ⑥ 四个状态字段：默认值与旧 `SceneSheet` 逐字一致（默认「全体」、
  // 标题默认「线索」）。
  String _clueSeat = kUnitAllValue;
  String _clueLabel = '全体';
  final TextEditingController _clueTitle =
      TextEditingController(text: '线索');
  final TextEditingController _clueText = TextEditingController();

  @override
  void dispose() {
    _clueTitle.dispose();
    _clueText.dispose();
    super.dispose();
  }

  /// ⑤ 递出回调：`scene.clue {seat,title,text}`。
  /// `*` 的逐人单发由 domain `sceneClue` 完成，UI 只负责把统一枚举的
  /// value 经 [unitValueToSeat] 剥成裸 seat / '*'；字段名与 trim 口径不变。
  void _submitClue(BuildContext context) {
    final String title = _clueTitle.text.trim();
    final String text = _clueText.text.trim();
    // ★ 2.36.0 / Q5：`_clueText` 默认空。改前「只填标题就递」会下发
    //   `text:''`，玩家私密栏红点亮起却没有任何可见内容。
    //   这里**不阻断递出**（保持 `clueSubmit → hostAction('scene.clue')`
    //   既有契约：`p16_wave1_sheets_test.dart:394/417` 直接点递出并断言
    //   载荷），而是在空正文时用标题兜底成可见内容；标题也空则回落「线索」。
    //   字段名 / trim 口径 / seat 剥壳逐字不变，domain `sceneClue` 零改动。
    final String body =
        text.isEmpty ? (title.isEmpty ? '线索' : title) : text;
    final ctl = RoomScope.of(context).controller;
    ctl.hostAction('scene.clue', <String, Object?>{
      'seat': unitValueToSeat(_clueSeat),
      'title': title,
      'text': body,
    });
  }

  @override
  Widget build(BuildContext context) {
    final gate = RoomScope.of(context).controller.gate;
    return Column(
      key: SceneSheetKeys.clue,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: '递线索',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ② KP-6：线索目标座位 → 下拉选单位（默认全体，`*` = 全体）。
              UnitPickerField(
                key: SceneSheetKeys.clueSeat,
                label: '目标座位（* = 全体）',
                display: _clueLabel,
                title: '选择线索目标',
                allowAll: true,
                onPicked: (RoomUnitOption o) => setState(() {
                  _clueSeat = o.value;
                  _clueLabel = o.label;
                }),
              ),
              // ③ 线索标题。
              TextField(
                key: SceneSheetKeys.clueTitle,
                controller: _clueTitle,
                decoration: const InputDecoration(
                  labelText: '线索标题',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              // ④ 线索正文。
              TextField(
                key: SceneSheetKeys.clueText,
                controller: _clueText,
                decoration: const InputDecoration(
                  labelText: '线索正文',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              // ⑤ 递出：★ 独立 ValueKey，绝不挂 `act/scene.clue` 锚点。
              Align(
                alignment: Alignment.centerLeft,
                child: RoomTap(
                  key: SceneSheetKeys.clueSubmit,
                  label: '递出',
                  enabled: gate.can('scene.clue'),
                  hint: gate.can('scene.clue') ? '私下递线索' : '只有 KP 能递线索',
                  onTap: () => _submitClue(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
