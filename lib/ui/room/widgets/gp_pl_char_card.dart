// ============================================================
// widgets/gp_pl_char_card.dart — 块 2（玩家）：我的角色卡
//
// ★ **双源**（S1 / Q-P5-3 的前提）：
//   · 技能值、八项属性 → `member.sheet`（`skillRows` / `attrRows` 纯函数）；
//   · HP / MP / SAN 现值 → `member.runtime`（`memberStats` 已做 status→runtime 双源回退）。
//   两处口径都来自 view/，本文件不自己算数值。
//
// ★ 撕卡判据与权威端**同源**：`operationLocked(mem)`（S7：死亡 / 濒死 / 昏迷 /
//   三类疯狂）。锁定后本块只剩「聊天」可用 —— 所有会发动作的入口**不渲染**
//   （不是禁用），这样 T-20「只剩聊天」在结构上成立，也顺带满足 T-30
//   「不渲染是合法分支」。
//
// ★ 只画、只发动作：零权威端引用、零规则调用。
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asMap;
import '../room_card_saver.dart' show RoomCardSaver;
import '../room_keys.dart';
import '../room_scope.dart';
import '../sheets/room_sheet.dart';
import '../sheets/sheet_self_state.dart' show openSelfStateSheet;
import '../view/member_view.dart';
import '../view/room_view.dart';
import '../view/sheet_view.dart';
import '../../widgets/avatar_picker.dart' show AvatarThumb, memberAvatarValue;
import 'room_button_size.dart'
    show RoomBtnSize, RoomTapTile, roomTapFixedGrid2;
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 角色卡内部稳定 key。
class GpPlCharCardKeys {
  const GpPlCharCardKeys._();

  static const Key root = ValueKey<String>('gpPlCharCard/root');
  static const Key name = ValueKey<String>('gpPlCharCard/name');
  static const Key status = ValueKey<String>('gpPlCharCard/status');
  static const Key locked = ValueKey<String>('gpPlCharCard/locked');
  static const Key unbound = ValueKey<String>('gpPlCharCard/unbound');
  static const Key stateBtn = ValueKey<String>('gpPlCharCard/stateBtn');
  static const Key itemsBtn = ValueKey<String>('gpPlCharCard/itemsBtn');

  /// ★ P17 C-1：角色卡的「AI RP」指引按钮已删（真入口在聊天输入行的魔棒）。
  ///   key 常量**保留**：多处既有测试按字符串 / 按 key 引用它，删常量会让
  ///   测试编译期就断裂；语义上这一项 P17 起已无 UI 使用点。
  static const Key aiBtn = ValueKey<String>('gpPlCharCard/aiBtn');
  static const Key fullscreen = ValueKey<String>('gpPlCharCard/fullscreen');

  /// C1：把**当前游戏中状态**手动存回「已保存的角色卡」。
  static const Key saveBtn = ValueKey<String>('gpPlCharCard/saveBtn');

  /// 自己的头像缩略图（`gpPlCharCard/avatar`）
  static const Key avatar = ValueKey<String>('gpPlCharCard/avatar');

  /// 技能行（`gpPlCharCard/skill/<name>`）。
  static Key skill(String name) => ValueKey<String>('gpPlCharCard/skill/$name');
}

/// 块 2：玩家角色卡。
class GpPlCharCard extends StatelessWidget {
  const GpPlCharCard({super.key, this.skillLimit = 6});

  /// 卡片上最多列几条技能（全量走弹层 / 全屏）。
  final int skillLimit;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final session = scope.session;
    final state = session.state;
    final seat = session.seat;
    final me = findMe(state, seat);
    final theme = Theme.of(context);

    // ★ P11（用户 2026-11-11 真机报的 bug）：「成员在」≠「卡数据在」。
    //
    //   以前这里只判 `me == null`（人都不在房间），于是「已经进房、但还没绑卡 /
    //   数值还没同步到」的玩家会掉进下面的完整卡片分支：`memberStats` 对缺失键
    //   逐项回退 0 → 面板画出三条**空进度条**（ratio 恒 0，看起来就是一条横线）
    //   加上 `HP 0 / 0`、`MP 0 / 0`、`SAN 0 / 0`，八项属性全 `—`
    //   （`sheet_view.dart#attrRows` 是这张卡上唯一的字面破折号）。
    //   用户看到的「HP / MP / SAN 三个数值都是空的，显示成 -」就是这一屏。
    //
    //   未初始化必须**如实说**：没绑卡就说没绑卡，卡名在但数值没到就说没同步。
    //   绝不拿 0 冒充真实数值（0 点血和「不知道」是两件事）。
    //   ★ 布局零改动：仍是同一个 SectionBox / 同一个 child 位置，只换文案。
    if (me == null || !hasCardVitals(me)) {
      final bound = roomText(me?['charId']).isNotEmpty ||
          roomText(me?['charName']).isNotEmpty;
      return SectionBox(
        key: GpPlCharCardKeys.root,
        title: '我的角色卡',
        child: Text(
          bound
              ? '角色卡的数值还没同步到（重新绑定一次角色卡即可）'
              : '还没有绑定角色卡（等 KP 或房间页绑定）',
          key: GpPlCharCardKeys.unbound,
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final stats = memberStats(me);
    final vitals = vitalsOf(me);
    final attrs = attrRows(me);
    // ★ P17 P-1：属性区补 LUK（当前幸运点）。
    //   `vitals.luck`（= `status.currentLuck`，见 `sheet_view.dart:69`）一直取到
    //   却没在任何地方画出来：属性区只跑 `attrRows`，而它按 `_attrLabels`
    //   （8 项，不含 luck）截断，`kRaAttrKeys` 里的 `luck` 永远到不了界面。
    //   ★ **不改共享纯函数 `attrRows`**：它还被 `sheet_char_view.dart:153`（全屏
    //     只读详情）与 `room_view_test.dart` 的 8 项断言复用，改它会连带改口径。
    //     只在本卡片补一项。
    //   ★ 缺键显示「—」而不是 0：与八项属性同一 K4 口径（缺键 ≠ 0）。必须读
    //     **原始** status —— `roomNumber(null)` 也返回 0，从 `vitals.luck` 上
    //     区分不出「真的 0」与「没这个键」。
    final Object? luckRaw = asMap(asMap(me['sheet'])['status'])['currentLuck'];
    final String luckText =
        (luckRaw == null || luckRaw == '') ? '—' : _fmtNum(vitals.luck);
    final skills = skillRows(asMap(me['sheet']));
    final locked = operationLocked(me);
    final ripped = isRipped(me);
    final name = roomText(me['nickname']).isEmpty
        ? roomText(me['seat'])
        : roomText(me['nickname']);
    final portrait = roomText(asMap(me['sheet'])['name']).isEmpty
        ? name
        : roomText(asMap(me['sheet'])['name']);

    return SectionBox(
      key: GpPlCharCardKeys.root,
      title: '我的角色卡',
      trailing: RoomTap(
        key: GpPlCharCardKeys.fullscreen,
        icon: Icons.fullscreen,
        hint: '全屏查看我的角色卡',
        // ★ P16：标题栏只有一个控件，无处「统一」→ 尺寸不动（44×32）。
        minSize: RoomBtnSize.trailingSm,
        onTap: () => showFullscreenReader<void>(
          context: context,
          title: portrait,
          child: _detailBody(me),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              AvatarThumb(
                key: GpPlCharCardKeys.avatar,
                relPath: memberAvatarValue(context, me),
                name: portrait,
                size: 30,
                fallback: AvatarDot(name: portrait, size: 30),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  portrait,
                  key: GpPlCharCardKeys.name,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                charStatusText(me),
                key: GpPlCharCardKeys.status,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              // ★ T-20：撕卡后只剩聊天 —— 这里明说。
              // ★ S7：昏迷 / 濒死 / 疯狂发作**不是**撕卡，此时仍可「推进 1 轮」
              //   或申请治愈，所以文案要分开，不能一律说「只能聊天」。
              child: Text(
                ripped
                    ? '已撕卡 / 无法行动：只能聊天'
                    : '操作受限：只能「推进 1 轮」或申请治愈',
                key: GpPlCharCardKeys.locked,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 6),
          StatBar(
            label: 'HP',
            value: stats.hp,
            max: stats.hpMax,
            color: theme.colorScheme.error,
          ),
          StatBar(
            label: 'MP',
            value: stats.mp,
            max: stats.mpMax,
            color: theme.colorScheme.primary,
          ),
          StatBar(
            label: 'SAN',
            value: vitals.san,
            max: vitals.sanMax,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: 6),
          // ★ P17 P-1：从 8 项变 9 项（末尾追加 LUK）。这是**柔性 Wrap**，
          //   多一项只会多一行，不会溢出；卡片所在的两种宿主都是可滚动的
          //   （折叠档整页 `SingleChildScrollView`、平板横屏 `_slotView` 格内
          //   竖向滚动），所以 textScaler 1.3/1.5/2.0 下高度增长只增加滚动量。
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: <Widget>[
              for (final row in attrs)
                Text('${row.k} ${row.v}', style: const TextStyle(fontSize: 11)),
              // 第 9 项：幸运（当前幸运点）。取值口径见 build 顶部的注释。
              Text('LUK $luckText', style: const TextStyle(fontSize: 11)),
            ],
          ),
          if (skills.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            for (final s in skills.take(skillLimit))
              Row(
                key: GpPlCharCardKeys.skill(s.name),
                children: <Widget>[
                  Expanded(
                    child: Text(s.name,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${s.value}',
                      style: const TextStyle(fontSize: 11)),
                ],
              ),
            if (skills.length > skillLimit)
              Text('另有 ${skills.length - skillLimit} 项（全屏查看）',
                  style: const TextStyle(fontSize: 11)),
          ],
          if (!locked) ...<Widget>[
            const SizedBox(height: 6),
            // ★ P16：短按钮统一 104×40（`RoomBtnSize.charTile`）并排成**固定 2 列**。
            //   改前是 84/64/64/64 的「内容驱动宽度」，一行里状态管理比其他三个
            //   宽 20dp —— 用户说的「同一栏位大小不同」。
            //   104 的依据来自已被 P17 C-1 删掉的 `AI RP`（实测 100.25 含 12 padding）；
            //   现在剩下的 `状态管理`（87）与 `物品`（60.5）都远小于 104，保留
            //   104 是为了「同类短按钮一律等宽」这条口径不随本次删按钮而漂移。
            // ★ 为什么用 `roomTapFixedGrid2` 而不是 `roomTapWrap2`（QA 实测）：
            //   「能塞几个塞几个」在宽档（412dp 竖屏内容 ≈368）会排成通栏，
            //   每行个数一变宽度就不再一致 —— 列数必须钉死。
            // ★ P17 C-1：删掉 2 个按钮后**只剩 2 个**，`2×104 + 4 = 212` 恰好
            //   等于钳制宽 ⇒ 正好填满一行、右侧**不留空白**。
            //   ⚠️ 若将来再少到只剩 1 个（`state.self` 拿不到的极端档），
            //   `SizedBox(212)` 会留下约 108dp 空白；那时把 `columns: 1` 传进来
            //   即可，别在这里加按钮填空。
            roomTapFixedGrid2(<Widget>[
              // ★ 旁观者没有「我的角色」语义：POLICY 里 `state.self` 只放
              //   player / kp，spectator 拿不到 ⇒ 入口**结构性不渲染**（不是禁用）。
              //   与 T-20「撕卡后不渲染」同一口径。
              if (scope.controller.gate.can('state.self'))
                RoomTapTile(
                  roomKey: GpPlCharCardKeys.stateBtn,
                  size: RoomBtnSize.charTile,
                  icon: Icons.edit_note,
                  label: '状态管理',
                  hint: '改身体 / 精神 / 数值（数字需 KP 同意）',
                  onTap: () => openSelfStateSheet(context),
                ),
              // ★ P17 C-1：原「急救」按钮（发 `aid.apply` 的那个 act 锚点）已删。
              //   本行刻意不写出锚点的源码字面量：波4 的源码门禁要靠
              //   「角色卡里零命中 `act/aid.apply` 锚点」来证明它真的撤了。
              //   用户口径是「角色卡上的 AI RP / 急救没用了」，**不是**「删重复入口」：
              //   聊天栏只有 AI RP 真入口（`gp_feeds.dart:785-800` 魔棒），工具栏
              //   只有「治疗」弹层（`room_game_page.dart:1056-1066` → `openTreatSheet`），
              //   后者进弹层可选急救 / 医学 / 精神分析（`sheet_treat.dart:65-69`）。
              //   ⇒ 急救能力仍有去处（工具栏「治疗」），这里只撤掉角色卡这个旧入口。
              RoomTapTile(
                roomKey: GpPlCharCardKeys.itemsBtn,
                size: RoomBtnSize.charTile,
                icon: Icons.backpack_outlined,
                label: '物品',
                hint: '查看随身物品与武器',
                onTap: () => _openItems(context, me),
              ),
              // ★ P17 C-1：原「AI RP」指引按钮（`GpPlCharCardKeys.aiBtn`）已删。
              //   它本来就只是「去聊天输入行点魔棒」的指引（`:277-280` 旧注释），
              //   真入口一直在聊天栏（`gp_feeds.dart:50/785-800`，生成结果只回填
              //   输入框）。撤掉角色卡这一份指引后，功能**零丢失**。
              //   key 常量 `GpPlCharCardKeys.aiBtn` 保留（测试兼容，见类定义）。
            ], tileWidth: RoomBtnSize.charTile.width),
          ],
          // ★ PRD S7（`_p5_prd.md:687`）+ 块 2 规格（`_p5_prd.md:356`）：
          //   「⏩推进 1 轮」是昏迷 / 濒死 / 疯狂发作期间**唯一**可点的自助动作，
          //   所以它必须渲染在上面那个 `if (!locked)` 之外 —— 这是它存在的全部意义。
          //   撕卡（死亡 / 永久疯狂）仍只留聊天，故额外要求 `!ripped`。
          //
          // ★ 可点性用 `gate.can('madness.advance')`（POLICY = [player, kp]），
          //   与操作锁**无关** —— 权威端的放行在 `room_model_host_intent.dart#_passSelf`
          //   （白名单含 madness.advance / madness.cure / sheet.healwound），
          //   那是权威端的判断，不该复制成 UI 的 enabled 条件。
          // ---- P10 第 1 期 C1：手动保存当前状态到「已保存」 ----
          //
          // ★ 为什么放在 `if (!locked)` **之外**：撕卡 / 昏迷时这张卡仍在屏幕上，
          //   而且它必须**照旧渲染**（P17 P-3 也没有把它挪进 `if (!locked)`）——
          //   只是可点性叠加了操作锁，见下方 `enabled`。
          // ★ 旁观者**不渲染**：POLICY 里 `state.self` 只给 player / kp，
          //   旁观者拿不到 → 结构性不渲染（与「状态管理」同一口径）。
          // ★ 纯本机动作：不发包、不改房间 state；写回仍走 K1x 的唯一路径
          //   （controller.writeCard → repo.save）。
          // ★ P17 P-3：昏迷 / 濒死 / 疯狂发作时**不可点**（用户口径：「只能点
          //   「推进 1 轮」和「更多工具」，其余全禁」）。`operationLocked(mem)`
          //   与权威端 `_passSelf` 同源判据，所以这只是把权威端已经拦住的
          //   动作在 UI 上标明 —— 点下去本来就会被拒。
          //   ⚠️ 本按钮的 key 是 `GpPlCharCardKeys.saveBtn`（**不是**
          //   `RoomKeys.action(op)`），不参与 T-30「`enabled` 恰好等于
          //   `gate.can(op)`」的表驱动探针；「渲染但不发动作」的 4 个短按钮
          //   在锁定态仍是结构性不渲染（T-20），两者口径不冲突。
          if (scope.controller.gate.can('state.self'))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              // ★ P16：本栏长按钮各占一行并**拉满整行**（高 40）。
              //   改前 `Align(centerLeft)` + minSize 128/112：长按钮比上面
              //   短按钮宽 38/24，且都靠左留一大截空白。
              //   去掉 `Align`：它没有 widthFactor 时会让 RoomTap 收缩居中。
              child: RoomTapTile(
                roomKey: GpPlCharCardKeys.saveBtn,
                size: RoomBtnSize.fullRow40,
                fullWidth: true,
                icon: Icons.save_outlined,
                // ★ 2.42.0 / P20 需求 3①（用户：「保存到已保存」看不懂）：
                //   按钮文案改说清落点 —— 存的是**角色卡**，不是别的什么。
                //   字面量长度不变（6 字）⇒ P16 的按钮宽度/满宽几何断言零影响；
                //   存量用例全部按 `GpPlCharCardKeys.saveBtn` 取控件，不按文案找。
                label: '保存到角色卡',
                // ★ P17 P-3：`gate.can(op) && !locked`（前者是本按钮的结构性
                //   前置，后者是本次新增的操作锁）。锁定态按钮变灰、点了不发。
                enabled: scope.controller.gate.can('state.self') && !locked,
                hint: locked
                    ? '昏迷 / 疯狂发作期间不可保存（只能「推进 1 轮」或申请治愈）'
                    : '把当前 HP/MP/SAN、物品、状态写回本机这张角色卡（覆盖同一张）',
                onTap: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  final outcome =
                      await RoomCardSaver(
                    controller: scope.controller,
                    session: scope.session,
                  ).saveNow();
                  messenger?.showSnackBar(
                    SnackBar(content: Text(outcome.message)),
                  );
                },
              ),
            ),
          if (!ripped && scope.controller.gate.can('madness.advance'))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              // ★ 2.34.0 GL-1：冷却窗口在调用点提到 500ms，并在冷却期做
              //   纯视觉置灰；enabled 口径逐字不动（T-30）。见文件末尾
              //   [_AdvanceRoundButton] 的实现说明。
              child: _AdvanceRoundButton(
                scope: scope,
                enabled: scope.controller.gate.can('madness.advance'),
              ),
            ),
        ],
      ),
    );
  }

  /// 全屏只读详情（技能全量 + 属性 + 武器 + 物品）。
  Widget _detailBody(Map<String, Object?> me) {
    final skills = skillRows(asMap(me['sheet']));
    final weapons = weaponsOf(me);
    final items = itemsOf(me);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('状态：${charStatusText(me)}'),
          Text('精神状态：${mentalText(me)}'),
          const SizedBox(height: 8),
          for (final s in skills)
            Text('${s.name}  ${s.value}', style: const TextStyle(fontSize: 12)),
          if (weapons.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            const Text('武器'),
            for (final w in weapons)
              Text('${roomText(w['name'])}  ${roomText(w['damage'])}',
                  style: const TextStyle(fontSize: 12)),
          ],
          if (items.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            const Text('随身物品'),
            for (final it in items)
              Text('${roomText(it['name'])} × ${roomText(it['qty'])}',
                  style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  void _openItems(BuildContext context, Map<String, Object?> me) {
    final items = itemsOf(me);
    final weapons = weaponsOf(me);
    showRoomSheet<void>(
      context: context,
      title: '物品 / 武器',
      body: (BuildContext _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (items.isEmpty) const Text('没有随身物品'),
          for (final it in items)
            Text('${roomText(it['name'])} × ${roomText(it['qty'])}'
                '${roomText(it['note']).isEmpty ? '' : '（${roomText(it['note'])}）'}'),
          if (weapons.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            const Text('武器'),
            for (final w in weapons)
              Text('${roomText(w['name'])}  ${roomText(w['damage'])}'),
          ],
        ],
      ),
    );
  }
}

/// 玩家侧「我已撕卡 / 无法行动」判定（与权威端 `operationLocked` 同源）。
///
/// 手绘板 / 场景检定等块也要用它，所以导出成顶层函数，避免各自复制判据。
bool selfLocked(Map<String, Object?> state, String seat) =>
    operationLocked(findMe(state, seat));

/// 数值 → 最短文本：整数不带 `.0`，其余保留一位小数。
///
/// ★ 为什么不用 `num.toString()`：`status.currentLuck` 常是 `'60'` 这类字符串，
///   `roomNumber` 归一后是 `double 60.0`，直接插值会显示成 `LUK 60.0`。
/// ★ 与 `sheet_view.dart` 的私有 `_fmt` 同口径（那边不导出，复制 2 行比
///   改共享文件的可见性更安全）。
String _fmtNum(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

// ------------------------------------------------------------
// 2.34.0 GL-1：「推进 1 轮」500ms 冷却 + 冷却期视觉置灰
// ------------------------------------------------------------

/// 「推进 1 轮」按钮：调用点把节流窗口提到 500ms，并在冷却期做视觉置灰。
///
/// ★ T-30（硬约束）：挂在 `RoomKeys.action(op)` 上的按钮，`enabled` 必须
///   **恰好**等于 `gate.can(op) && !locked` 这一既有口径。本按钮原口径是
///   `gate.can('madness.advance')`（受操作锁时仍可用，见上方 :301-304
///   注释），这里 [enabled] 原样透传、逐字不改；`_cooling` **只**用于
///   `foregroundDecoration` 视觉置灰，绝不叠加进 `enabled`，也不改按钮
///   尺寸 / key / 文案，因此表驱动权限探针与等宽等高精度断言不受影响。
/// ★ 冷却复位复用 `RoomUiLocal.scheduleDismiss` 这个可注入时钟
///   （测试 harness 把它换成 `(_, _) => null`，fake-async 里不会挂死），
///   不裸用 `Timer`；冷却态只影响观感，发包闸门仍由
///   `RoomController.throttle` 的注入时钟唯一决定。
class _AdvanceRoundButton extends StatefulWidget {
  const _AdvanceRoundButton({required this.scope, required this.enabled});

  final RoomScope scope;

  /// 原样来自 `gate.can('madness.advance')`，T-30 探针读取的就是它。
  final bool enabled;

  @override
  State<_AdvanceRoundButton> createState() => _AdvanceRoundButtonState();
}

class _AdvanceRoundButtonState extends State<_AdvanceRoundButton> {
  bool _cooling = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _onTap() {
    final controller = widget.scope.controller;
    // ★ GL-1：只在调用点传 500ms 窗口；`RoomController.throttle` 的默认
    //   400ms 逐字不动（room_session_test.dart:339-357 /
    //   room_ui_shell_test.dart:384-396 依赖默认窗口）。
    if (!controller.throttle(
      'madness.advance',
      window: const Duration(milliseconds: 500),
    )) {
      return;
    }
    controller.hostAction('madness.advance', <String, Object?>{});
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
    // `foregroundDecoration` 只绘制、不参与布局（见
    // room_panel_kit.dart:133-140 同款手法），所以按钮尺寸 / hitTest
    // 完全不变；`RoomTapTile` 内部已自带 clampBtnText（C7）。
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        color: _cooling
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.55)
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: RoomTapTile(
        roomKey: RoomKeys.action('madness.advance'),
        size: RoomBtnSize.fullRow40,
        fullWidth: true,
        icon: Icons.skip_next,
        label: '⏩ 推进 1 轮',
        // ★ T-30：enabled 口径逐字保持 `gate.can(op)`。
        enabled: widget.enabled,
        hint: '推进一轮疯狂发作（受操作锁时仍可用）',
        onTap: _onTap,
      ),
    );
  }
}

