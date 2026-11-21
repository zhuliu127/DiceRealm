// ============================================================
// widgets/gp_scene_check_pl.dart — 块 7（玩家）：场景检定（只读 + 主动检定）
//
// 玩家侧**只做两件事**：
//   ① 只读展示 KP 推来的步骤与进度（`sceneCheckSteps / Cursor / Progress`）；
//   ② 用**自己的技能**发起一次检定（`INTENT.DICE{direct:true, skill}`，
//      权威端用 `skillBaseOf` 取技能值复算，客户端不自报结果）。
//
// ★ T-23：玩家侧**零**裁定 / 推送按钮 —— 本文件不渲染
//   `RoomKeys.kpScenePush`，也不发 `scene.check.step` / `scene.check.push`。
// ★ T-20：撕卡 / 无法行动时，连「用我的技能检定」也不渲染。
// ★ 只画、只发 intent：零权威端引用、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asMap;
import '../../../domain/room_model_actions_room.dart'
    show
        kRaDifficultyCritical,
        kRaDifficultyExtreme,
        kRaDifficultyHard,
        raNormSceneDifficulty;
import '../../../domain/room_types.dart' show RoomIntent;
import '../room_scope.dart';
import '../view/room_view.dart' show findMe;
import '../view/scene_view.dart'
    show sceneCheckProgress, sceneCheckSteps, sceneCheckCursor;
import '../view/sheet_view.dart' show skillRows;
import 'gp_pl_char_card.dart' show selfLocked;
import 'room_button_size.dart' show RoomBtnSize, RoomTapTile;
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 场景检定（玩家侧）内部稳定 key。
class GpSceneCheckPlKeys {
  const GpSceneCheckPlKeys._();

  static const Key root = ValueKey<String>('gpSceneCheckPl/root');
  static const Key empty = ValueKey<String>('gpSceneCheckPl/empty');
  static const Key progress = ValueKey<String>('gpSceneCheckPl/progress');
  static const Key roll = ValueKey<String>('gpSceneCheckPl/roll');
  static const Key locked = ValueKey<String>('gpSceneCheckPl/locked');

  /// 步骤行（`gpSceneCheckPl/step/<i>`）。
  static Key step(int i) => ValueKey<String>('gpSceneCheckPl/step/$i');

  /// 技能 chip（`gpSceneCheckPl/skill/<name>`）。
  static Key skill(String name) => ValueKey<String>('gpSceneCheckPl/skill/$name');
}

/// 难度 → 中文（只读展示；裁定在 KP 侧）。
///
/// ★ P17 KP-2：四档与 domain `kRaDifficultyLevels` **一一对应**
///   （`REGULAR` 常规 / `HARD` 困难 / `EXTREME` 极难 / `CRITICAL` 大成功）。
///   `CRITICAL` 是本批新引入的档（只有掷出 01 才算成功），缺分支会静默回落成
///   「常规」——那是**错的玩家信息**，不是文案美化。
///   ★ 取值先过 `raNormSceneDifficulty`：老存档里的小写 `hard` 也能认出来，
///     未知值仍回落常规（与模型侧同一套归一，不再各写一份字面量）。
String sceneDifficultyText(Object? raw) {
  switch (raNormSceneDifficulty(raw)) {
    case kRaDifficultyHard:
      return '困难';
    case kRaDifficultyExtreme:
      return '极难';
    case kRaDifficultyCritical:
      return '大成功';
    default:
      return '常规';
  }
}

/// 块 7（玩家）：只读场景检定 + 用自己的技能检定。
class GpSceneCheckPl extends StatefulWidget {
  const GpSceneCheckPl({super.key, this.skillLimit = 6});

  final int skillLimit;

  @override
  State<GpSceneCheckPl> createState() => _GpSceneCheckPlState();
}

class _GpSceneCheckPlState extends State<GpSceneCheckPl> {
  String? _skill;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final seat = scope.session.seat;
    final steps = sceneCheckSteps(state);
    final cursor = sceneCheckCursor(state);
    final progress = sceneCheckProgress(state);
    final locked = selfLocked(state, seat);
    final me = findMe(state, seat);
    final skills = skillRows(asMap(me?['sheet'])).take(widget.skillLimit).toList();
    final theme = Theme.of(context);
    final chosen = _skill ?? (skills.isEmpty ? null : skills.first.name);

    return SectionBox(
      key: GpSceneCheckPlKeys.root,
      title: '场景检定',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LinearProgressIndicator(
            key: GpSceneCheckPlKeys.progress,
            value: progress,
            minHeight: 4,
          ),
          const SizedBox(height: 4),
          if (steps.isEmpty)
            Text(
              'KP 还没有推送场景检定',
              key: GpSceneCheckPlKeys.empty,
              style: theme.textTheme.bodySmall,
            )
          else
            for (var i = 0; i < steps.length; i++)
              Padding(
                key: GpSceneCheckPlKeys.step(i),
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${i == cursor ? '▶ ' : '· '}'
                  '${roomText(steps[i]['title'])}'
                  '${roomText(steps[i]['skill']).isEmpty ? '' : '（${roomText(steps[i]['skill'])}）'}'
                  ' · ${sceneDifficultyText(steps[i]['difficulty'])}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: i == cursor ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
          const SizedBox(height: 6),
          if (locked)
            Text(
              '已撕卡 / 无法行动：不能发起检定',
              key: GpSceneCheckPlKeys.locked,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            )
          else ...<Widget>[
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: <Widget>[
                // ★ P16：技能 chip 只统一**高度**（恒 32）与**最小宽**（90）。
                //   为什么不定宽：技能名来自角色卡数据（长度不可预置），
                //   定宽会把长技能名挤成 RenderFlex overflow。这是全工程唯一
                //   「允许不同宽」的按钮组，断言口径因此是「高 ==32 且宽 ≥90」。
                for (final s in skills)
                  RoomTap(
                    key: GpSceneCheckPlKeys.skill(s.name),
                    label: '${s.name} ${s.value}',
                    hint: '选中「${s.name}」用于检定',
                    minSize: RoomBtnSize.scenePlTile,
                    onTap: () => setState(() => _skill = s.name),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // ★ P16：本栏唯一的长按钮 → 拉满整行、高 40。
            //   改前是 `Align(centerLeft)` + `minSize 140`：按钮宽随技能名
            //   在 140~200 之间跳，和上面的 chip 组不成体系。
            RoomTapTile(
              roomKey: GpSceneCheckPlKeys.roll,
              size: RoomBtnSize.fullRow40,
              fullWidth: true,
              icon: Icons.casino_outlined,
              label: chosen == null ? '用我的技能检定' : '用「$chosen」检定',
              // 没有技能 / 没有绑定角色卡时不可点（业务前置条件放 hint）。
              enabled: chosen != null && me != null,
              hint: chosen == null
                  ? '还没有可用技能（先绑定角色卡）'
                  : '发起 1D100 检定（结果由权威端复算）',
              onTap: () => _roll(chosen),
            ),
          ],
        ],
      ),
    );
  }

  void _roll(String? skill) {
    if (skill == null) return;
    final scope = RoomScope.read(context);
    scope.controller.sendIntent(
      RoomIntent.dice,
      <String, Object?>{
        'expr': '1D100',
        'direct': true,
        // ★ 只给技能名；技能值由权威端 `skillBaseOf` 取，客户端不自报 base。
        'skill': skill,
        'label': skill,
      },
    );
  }
}
