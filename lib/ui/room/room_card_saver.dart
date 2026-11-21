// ============================================================
// room_card_saver.dart — 「把游戏中状态写回已保存角色卡」（P10 第 1 期 C1/C2）
//
// 用户报的两个需求：
//   C1 游戏里能**手动**把当前状态存回「已保存」的角色卡（覆盖同一 id，
//      不新建重复卡）；
//   C2 KP 推进到下一回合时，玩家角色卡**自动**存一次。
//
// 三条设计约束：
//  ① **不新增落盘路径**：写回一律走 `RoomController.writeCard(RoomCardPatch)`
//     → `CharacterRepoRoomCardSink` → `repo.save`（K11 / C5 的唯一入口）。
//     这里只负责「把房间状态整理成 patch」，绝不自己碰 `CharacterRepo`。
//  ② **纯本机动作**：不发包、不改房间 state（房间是权威端的，玩家无权写）。
//  ③ **domain 保持纯净**：patch 的定位与落键规则在 `resolveRoomCardPatch`
//     （domain）里，本文件只做「取值 + 组织」。
//
// ★ 边界（如实说明，别当成 bug）：
//   · C2 的自动保存只可能发生在**玩家自己的设备**上 —— KP 的机器上没有别的
//     玩家的角色卡文件，也没有权限替别人写盘。所以 KP 推进回合时，他本机
//     只保存「自己绑定的那张卡」（KP 通常没有绑定卡 → 直接跳过）。
//   · 房间侧能改的字段只有「数值 / 状态 / 物品 / 武器 / 精神 / 疯狂」，
//     属性与技能在跑团中不产生变更事件，patch 契约里也没有这两个键 ——
//     所以保存集合 = 房间协议里**可变字段的全集**，不会丢东西。
// ============================================================

import '../../domain/js_compat.dart' show asMap, asList, jsTruthy;
import '../../domain/room_ports.dart' show CardWriteResult, RoomCardPatch;
import '../../domain/room_types.dart' show RoomRole, RoomStatus;
import 'room_controller.dart' show RoomController;
import 'room_session.dart' show RoomSession;
import 'room_text.dart';
import 'view/member_view.dart' show memberStats;
import 'view/room_view.dart' show findMe, isInGame;

/// 把「我」当前在房间里的状态整理成写回角色卡的 patch。
///
/// 找不到我 / 没绑定卡 → null（调用方据此提示，绝不猜一张卡来写）。
RoomCardPatch? roomCardPatchOf(Map<String, Object?> state, String seat) {
  final me = findMe(state, seat);
  if (me == null) return null;
  final sheet = asMap(me['sheet']);
  final charId = roomText(sheet['charId']).isEmpty
      ? roomText(me['charId'])
      : roomText(sheet['charId']);
  if (charId.isEmpty) return null;

  final stats = memberStats(me);
  final st = asMap(sheet['status']);
  final statusPatch = <String, Object?>{
    if (stats.hpMax > 0) 'maxHP': stats.hpMax,
    if (stats.mpMax > 0) 'maxMP': stats.mpMax,
    if (stats.hasMaxSan) 'maxSAN': stats.sanMax,
    'currentHP': stats.hp,
    'currentMP': stats.mp,
    'currentSAN': stats.san,
    // 身体状态三件套：与房间卡同语义（body 四态 + dying / unconscious 布尔）
    'body': roomText(st['body']),
    'dying': jsTruthy(st['dying']),
    'unconscious': jsTruthy(st['unconscious']),
  };
  if (st.containsKey('currentLuck')) {
    statusPatch['currentLuck'] = st['currentLuck'];
  }

  return RoomCardPatch(
    charId: charId,
    patch: <String, Object?>{
      'status': statusPatch,
      'mental': asList(sheet['mental']),
      'madness': asList(sheet['madness']),
      'tempStatus': asList(sheet['tempStatus']),
      'items': asList(sheet['items']),
      'weapons': asList(sheet['weapons']),
      if (st.containsKey('sanLoss')) 'sanLoss': st['sanLoss'],
    },
  );
}

/// 一次保存的结果（供 UI 提示，不弹模态）。
class RoomCardSaveOutcome {
  const RoomCardSaveOutcome({
    required this.ok,
    required this.message,
    this.result,
  });

  final bool ok;
  final String message;
  final CardWriteResult? result;
}

/// 手动保存 / 自动保存的共用实现。
///
/// ★ 只持会话与控制器；不持 UI 状态、不挂钩子，所以可以安全地放进
///   `_RoomShell` 的一个字段里，随页面销毁一起消失。
class RoomCardSaver {
  RoomCardSaver({
    required this.controller,
    required this.session,
  });

  final RoomController controller;
  final RoomSession session;

  /// 上一次自动保存时的**临时卡生效回合号**（-1 = 还没自动保存过）。
  ///
  /// ★ P10 第 2 期 A：幂等键从「`meta.round` 的变化」换成「TEMP_COMMIT 的
  ///   `round`」。理由见 [onStateChanged] 的注释。
  int _lastAutoRound = -1;

  /// 是否正在保存（防止同一回合连点 / 自动保存重入）。
  bool _busy = false;

  /// 自动保存是否至少成功过一次（测试与诊断用）。
  int autoSaved = 0;

  /// 手动保存次数（测试用）。
  int manualSaved = 0;

  /// 最后一次失败原因（静默记录，不弹错 —— C2 要求）。
  String lastError = '';

  /// 我是不是「能拥有角色卡」的身份（旁观者 / KP 没有可写的卡）。
  bool get canSave =>
      session.role == RoomRole.player &&
      controller.gate.can('state.self') &&
      roomCardPatchOf(session.state, session.seat) != null;

  /// C1：手动保存一次。返回结果供调用方提示。
  Future<RoomCardSaveOutcome> saveNow() async {
    if (_busy) {
      return const RoomCardSaveOutcome(ok: false, message: '正在保存，请稍候');
    }
    final patch = roomCardPatchOf(session.state, session.seat);
    if (patch == null) {
      return const RoomCardSaveOutcome(
        ok: false,
        message: '还没有绑定角色卡，无法保存',
      );
    }
    _busy = true;
    try {
      final result = await controller.writeCard(patch);
      if (result == null) {
        lastError = 'no_sink';
        return const RoomCardSaveOutcome(
          ok: false,
          message: '本机没有可用的角色卡仓库，未保存',
        );
      }
      if (!result.ok) {
        lastError = result.reason;
        return RoomCardSaveOutcome(
          ok: false,
          message: result.reason == 'card_not_found'
              ? '本机找不到这张角色卡（可能已被删除）'
              : '保存失败：${result.reason}',
          result: result,
        );
      }
      lastError = '';
      manualSaved += 1;
      return RoomCardSaveOutcome(
        ok: true,
        message: '已保存到「已保存的角色卡」',
        result: result,
      );
    } catch (e) {
      lastError = '$e';
      return RoomCardSaveOutcome(ok: false, message: '保存失败：$e');
    } finally {
      _busy = false;
    }
  }

  /// C2：**收到 TEMP_COMMIT（临时卡生效）后**把本房本卡写回「已保存」。
  ///
  /// 为什么触发源从「`meta.round` 变了」换成「TEMP_COMMIT」（P10 第 2 期 A，
  /// 对齐老 APP v2.9.0 的 `room-net.js#_onTempCommit`）：
  ///   老 APP 的回合出口顺序是硬要求 ——
  ///     ① `EVT.ROUND` → ② 濒死每轮 CON（`_onRoundBoundary`）→
  ///     ③ 天/周恢复（`_onDayWeekTick`，重伤每周回血经 `EVT.STATE` 改临时卡）
  ///     → **④ 最后**才发 `EVT.TEMP_COMMIT`。
  ///   老 APP 的原注释写着：必须等 ③ 之后才发，否则玩家会把「恢复前」的旧值
  ///   覆盖回原卡。所以落库时机只能由 ④ 决定，不能由「看到回合号变了」决定。
  ///   （Flutter 侧没有独立的 localStorage 临时卡：房间 state 本身就是唯一
  ///   暂存面，`roomCardPatchOf` 从它取值 → 覆盖原卡，与老 APP 的 commit
  ///   语义等价，且天然幂等。）
  ///
  /// 触发条件（全部满足才动手）：
  ///   ① 收到过 TEMP_COMMIT 且回合号 > 0（没收到过 = 玩家没被通知落库）；
  ///   ② 该回合号与上次不同（**幂等**：同一 round 重复投递只写一次）；
  ///   ③ 游戏期（`meta.status == IN_GAME`）—— 招募期没有回合；
  ///   ④ 我是玩家并且绑了卡（KP / 旁观没有可写的卡）；
  ///   ⑤ 不在保存中（重入保护）。
  ///
  /// 失败静默：只记 [lastError]，不弹错、不打断 UI（C2 明确要求）。
  Future<void> onStateChanged() async {
    if (_busy) return;
    // ★ 唯一触发源：TEMP_COMMIT。0 = 本视角从未收到（含「没注册 client 的
    //   空视角」「还没开团」），直接什么都不做。
    final commitRound = session.lastTempCommitRound;
    if (commitRound <= 0) return;
    if (commitRound == _lastAutoRound) return;

    final state = session.state;
    if (!isInGame(state)) return;
    if (roomText(asMap(state['meta'])['status']) == RoomStatus.closed) return;
    if (session.role != RoomRole.player) return;

    // 先占住回合号：即使保存失败也不在同一回合里反复重试（不乱循环）。
    _lastAutoRound = commitRound;
    if (roomCardPatchOf(state, session.seat) == null) return;
    if (!controller.gate.can('state.self')) return;

    _busy = true;
    try {
      final patch = roomCardPatchOf(session.state, session.seat);
      if (patch == null) return;
      final result = await controller.writeCard(patch);
      if (result != null && result.ok) {
        autoSaved += 1;
        lastError = '';
      } else {
        lastError = result?.reason ?? 'no_sink';
      }
    } catch (e) {
      lastError = '$e';
    } finally {
      _busy = false;
    }
  }

  /// 当前回合号（缺键 → 0，表示「还没有回合」）。
  ///
  /// ★ 只用于诊断 / 测试断言，**不再**作自动保存的触发判据 ——
  ///   触发源唯一是 [RoomSession.lastTempCommitRound]。
  static int roundOf(Map<String, Object?> state) {
    final raw = asMap(state['meta'])['round'];
    if (raw is num) return raw.toInt();
    final n = int.tryParse(roomText(raw));
    return n ?? 0;
  }
}
