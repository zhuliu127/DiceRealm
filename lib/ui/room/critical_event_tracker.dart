// ============================================================
// critical_event_tracker.dart — 5 类关键事件的**判据**（P20 需求 2）
//
// 一次 [sync] 吃一份会话视图（`RoomSession.state`），吐出「这一批该弹的
// 横幅事件」；排队 / 上屏 / 自消全部交给 UI 层（`RoomUiLocal.banners` +
// `RoomEventBanner`），本类**不碰 UI、不碰权威态、不写 state、不发任何包**。
//
// ★ 纯 Dart：零 Flutter 依赖（只用 `dart:core` + 两个纯 Dart 的 domain 文件），
//   便于纯逻辑单测（不需要 WidgetTester / FakeAsync）。
//
// ------------------------------------------------------------
// 为什么**不复用**既有的 optoast 通路（勘察已确认，三条都是硬伤）
// ------------------------------------------------------------
//   1. `feed_optoast_tracker.dart` 的 `kOptoastTtl = 2s` 被
//      `test/p11_pv1a_optoast_tracker_test.dart:164` 锁死，本需求要 4s；
//   2. 40 字截断（`:189-193`）会把「本回合累计理智损失 6 点…判定为不定性
//      疯狂」这种关键句截成半句 —— 横幅是**事件结论**，不是流水播报；
//   3. 一次新增 >6 条整批丢弃（`:124`）= 防断线刷屏守卫。KP 先加 5 只怪再
//      开战，一次 notify 就有 6+ 条公开记录 → 「进入战斗」会被整批吞掉。
//   4. 方向相反：optoast 的文案来自 domain log（原样转发），本需求要求
//      「文字由 APP 生成」。
//   所以另起一条独立通路，与 `notice` / `optoasts` **完全不共享**。
//
// ------------------------------------------------------------
// 判据（裁定 D5：**按 state diff，不解析 log**）
// ------------------------------------------------------------
//   · 为什么不能解析 log：永久疯狂一次写 3 条 log、死亡路径每写一次状态就
//     重复发一条 warn（`applyStatusJudgment`），log 驱动必然重复弹；而且
//     `room_model_reduce.dart:85-96` 的 log 只保留 5 个键，语义已被削平。
//   · 首帧只登记基线、**不弹历史**（进房不该被一屏历史事件糊一脸）。
//   · `syncEpoch` 变化（首连 / 断线补拉 / gap 自愈）→ [reset] 并重登基线：
//     补拉回来的历史不是「新发生」，一律不重播。
//   · **只在跃迁时产出**：非死亡 → 死亡、无永久疯狂 → 永久疯狂、
//     无临时/不定疯狂 → 有、`madnessCount` 增加。
//     因此「已撕卡角色每写一次状态都重复 warn」不会重复弹（基线里已经是
//     死亡，`prev.dead == true`，不再产出）。
//   · rewind / rollback 让状态**回退**（死亡消失）：只更新基线，
//     绝不产出「复活」事件 —— 本类根本没有「复活」这个事件类型。
//   · 群体事件（进入战斗）只产出 **1 条**，名单由 `combat.order` 生成。
//
// ------------------------------------------------------------
// 去重键（`CriticalEvent.key`）
// ------------------------------------------------------------
//   `death:<seat>`                    死亡（一次性）
//   `ripped:<seat>`                   永久疯狂 / 撕卡（一次性）
//   `madness:temp:<seat>`             临时疯狂（一次性）
//   `madness:indef:<seat>`            不定疯狂（一次性）
//   `madness:symptom:<seat>:<count>`  第 <count> 条疯狂症
//   `combat:start:<startedAt>`        进入战斗（按开战时间戳）
//   `combat:end:<startedAt>`          战斗结束（记的是**结束的那一场**的开战戳）
//   同一 key 只产出一次（`_emitted` 集合）。去重是第二道闸：第一道是
//   「跃迁判定」，两者都在，任何一条单独失效也不会刷屏。
//
// ------------------------------------------------------------
// 玩家端实际能拿到哪些字段（`room_model_host_core.dart:436-474`）
// ------------------------------------------------------------
//   本人 / KP：整份 sheet。其他玩家的 `sheet` 被 `_cropMember` 收窄成
//   `{name, avatar, status{body, currentHP, maxHP, currentSAN, currentMP,
//   maxMP, dying, unconscious}, mental[≤6], madnessCount, sanLoss:null,
//   maxSAN:null}` —— 也就是说：
//     · `status.body`  **公开** → 死亡判定用它（`'死亡'`）
//     · `mental`       **公开** → 临时/不定/永久疯狂判定用它
//     · `madnessCount` **公开** → 「获得新疯狂症」判定用它
//     · `madness`（症状名 / `rounds`）**刻意不下发** → 文案里不出现症状名
//       （裁定 D4），轮数拿不到时退成「若干轮」，绝不编数字。
//
// ------------------------------------------------------------
// 组合根怎么接（第二波收口工程师，详见回报里的「接线契约」）
// ------------------------------------------------------------
// ```dart
// final CriticalEventTracker _tracker = CriticalEventTracker(
//   artOf: (String kind) => switch (kind) { ... Art.e18Banner* ... },
// );
// final List<CriticalEvent> evts = _tracker.sync(
//   session.state, syncEpoch: session.syncEpoch, mySeat: session.seat);
// for (final CriticalEvent e in evts) {
//   local.pushBanner(title: e.title, subtitle: e.subtitle, art: e.art);
// }
// ```
// ============================================================

import '../../domain/js_compat.dart' show asList, asMap, jsNum, jsStr, jsTruthy;
import '../../domain/madness_state.dart'
    show kMentalIndefinite, kMentalPermanent, kMentalTemporary;
import 'event_banner_copy.dart' show EventBannerCopy;

/// `sheet.status.body` 的「死亡」字面量。
///
/// 与 `raMemberRipped`（`room_model_actions_room.dart:215`）逐字同口径 ——
/// 那边也是直接比 `== '死亡'`，没有常量可复用，这里只把它提成有名字的常量。
const String kBodyDead = '死亡';

/// 战斗快照里「这一场是哪一场」的标识键（`combatStart` 写入的 `now()`）。
const String _kCombatStampKey = 'startedAt';

/// 5 类事件的 `kind` 字面量（与 UI 侧的 `EventBannerArt` / 埋点文案一一对应）。
class CriticalEventKind {
  const CriticalEventKind._();

  /// 进入战斗（群体事件，一次只产出 1 条）。
  static const String combatStart = 'combatStart';

  /// 战斗结束。
  static const String combatEnd = 'combatEnd';

  /// 角色死亡（`status.body == '死亡'`）。
  static const String death = 'death';

  /// 永久疯狂（SAN 归零 → 撕卡）。
  static const String ripped = 'ripped';

  /// 临时 / 不定疯狂，或「获得 1 项新的疯狂症状」。
  static const String madness = 'madness';
}

/// 5 张 16:9 底图的资源路径（**镜像** `lib/ui/art.dart` 的 `Art.e18Banner*`）。
///
/// ★ 为什么在这里再写一份字面量：本文件必须**零 Flutter 依赖**（纯 Dart
///   单测），而 `lib/ui/art.dart` 里同时住着 `ArtImage`（`package:flutter`）。
///   两份字面量逐字相同，UI 侧可以用 `CriticalEventTracker(artOf: ...)`
///   注入 `Art.e18Banner*` 把 `Art` 保持为单一真源（见类文档的用法）。
class EventBannerArt {
  const EventBannerArt._();

  /// 进入战斗。
  static const String combat =
      'assets/images/e_game/e18_banner_combat_16x9.webp';

  /// 战斗结束。
  static const String combatEnd =
      'assets/images/e_game/e18_banner_combat_end_16x9.webp';

  /// 死亡。
  static const String death =
      'assets/images/e_game/e18_banner_death_16x9.webp';

  /// 临时 / 不定疯狂、新疯狂症。
  static const String madness =
      'assets/images/e_game/e18_banner_madness_16x9.webp';

  /// 永久疯狂（撕卡）。
  static const String ripped =
      'assets/images/e_game/e18_banner_ripped_16x9.webp';

  /// `kind` → 底图路径。未知 kind 退「疯狂」那张（存在即安全，不抛异常）。
  static String of(String kind) {
    switch (kind) {
      case CriticalEventKind.combatStart:
        return combat;
      case CriticalEventKind.combatEnd:
        return combatEnd;
      case CriticalEventKind.death:
        return death;
      case CriticalEventKind.ripped:
        return ripped;
      case CriticalEventKind.madness:
        return madness;
      default:
        return madness;
    }
  }
}

/// 一次横幅事件（**UI 无关**：只有文案与资源路径，没有任何 Widget / Color）。
///
/// 由 [CriticalEventTracker.sync] 产出，交给 `RoomUiLocal.pushBanner` 排队。
class CriticalEvent {
  const CriticalEvent({
    required this.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.art,
  });

  /// 去重键（见文件头注释的键表）。同一个 key 在一次会话内只产出一次。
  final String key;

  /// 事件类型，取值见 [CriticalEventKind]。
  final String kind;

  /// 主标题，已由 [EventBannerCopy] 生成（**不含**底图、不含 emoji 装饰以外
  /// 的任何排版信息）。
  final String title;

  /// 副行；空串表示「这条事件没有副行」（例如「获得 1 项新的疯狂症状」）。
  final String subtitle;

  /// 16:9 底图资源路径（见 [EventBannerArt]）。
  final String art;

  /// 是否要渲染副行（UI 侧据此决定要不要留出那一行的高度）。
  bool get hasSubtitle => subtitle.trim().isNotEmpty;

  @override
  String toString() => 'CriticalEvent($kind, key: $key, $title / $subtitle)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CriticalEvent) return false;
    return other.key == key &&
        other.kind == kind &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.art == art;
  }

  @override
  int get hashCode => Object.hash(key, kind, title, subtitle, art);
}

/// 单个成员的**快照**（只存判据要用的四个量，其余一概不抄）。
class _MemberSnap {
  const _MemberSnap({
    required this.seat,
    required this.name,
    required this.body,
    required this.mental,
    required this.madnessCount,
    required this.rounds,
  });

  /// 座位号（去重键里用）。
  final String seat;

  /// 已解析好的显示名（sheet.name → charName → nickname → 「该角色」）。
  final String name;

  /// `sheet.status.body`（玩家端公开）。
  final String body;

  /// `sheet.mental`（玩家端公开，最多 6 项）。
  final List<String> mental;

  /// `sheet.madness` 的长度（玩家端以 `madnessCount` 公开）。
  final int madnessCount;

  /// 临时疯狂剩余轮数；**玩家端拿不到**（`madness` 数组不下发）时为 null。
  final int? rounds;

  bool get dead => body == kBodyDead;

  bool get permanentlyMad => mental.contains(kMentalPermanent);

  bool get temporarilyMad => mental.contains(kMentalTemporary);

  bool get indefinitelyMad => mental.contains(kMentalIndefinite);

  @override
  String toString() =>
      '_MemberSnap($seat, $name, body: $body, mental: $mental, '
      'madnessCount: $madnessCount, rounds: $rounds)';
}

/// 5 类关键事件的**判据机**。
///
/// 一个实例对应一份**会话视图**（`RoomEventBannerWatcher` 持一个）。它是
/// 纯状态机：不持有 Timer、不持有 Widget、不依赖 `DateTime.now()`，
/// 因此可以在纯 Dart 单测里逐帧推演。
class CriticalEventTracker {
  /// [artOf] 可注入 `kind → 资源路径` 的映射；默认用 [EventBannerArt.of]。
  ///
  /// UI 侧想以 `lib/ui/art.dart` 的 `Art.e18Banner*` 为单一真源时传一个
  /// 包了 `Art` 常量的闭包即可（`Art` 住在一个依赖 Flutter 的文件里，
  /// 本文件不能直接 import，见 [EventBannerArt] 的说明）。
  CriticalEventTracker({String Function(String kind)? artOf})
      : _artOf = artOf ?? EventBannerArt.of;

  final String Function(String kind) _artOf;

  /// 上一帧的成员基线（`seat → 快照`）。
  final Map<String, _MemberSnap> _members = <String, _MemberSnap>{};

  /// 已产出的去重键。同一 key 只产出一次。
  final Set<String> _emitted = <String>{};

  /// 是否已登记基线（首次 [sync] 前为 `false`）。
  bool _hasBaseline = false;

  /// 当前 `syncEpoch`（世代变化 → 整机重置）。
  int? _epoch;

  /// 上一帧的战斗标识：`null` = 不在战斗中；非 null = 该场战斗的
  /// `combat.startedAt` 字符串（缺键时是 `anon<n>` 匿名戳，见
  /// [_combatStampOf]）。战斗结束时用它拼 `combat:end:<stamp>`。
  String? _combatStamp;

  /// `combat.startedAt` 缺失时（老存档 / 手工构造）的自增序号，
  /// 保证「打一场 → 结束 → 再打一场」每次都能算一个新的开战戳。
  int _anonCombatSeq = 0;

  /// 基线的成员数（诊断 / 测试用）。
  int get trackedMemberCount => _members.length;

  /// 基线是否已登记（首次 [sync] 前为 `false`）。
  bool get initialized => _hasBaseline;

  /// 是否在战斗中（按基线判定；测试 / 诊断用）。
  bool get inCombat => _combatStamp != null;

  /// 已产出的去重键快照（测试 / 诊断用，**只读**）。
  Set<String> get emittedKeys => Set<String>.unmodifiable(_emitted);

  /// 整机重置：清基线、清世代、清去重表。
  ///
  /// 调用方无需手动判世代 —— [sync] 收到变化的 `syncEpoch` 会自行调用本方法
  /// （随后按「首帧」处理：只登记基线、不产事件）。
  void reset() {
    _members.clear();
    _emitted.clear();
    _hasBaseline = false;
    _epoch = null;
    _combatStamp = null;
    _anonCombatSeq = 0;
  }

  /// 判一次「新发生的关键事件」，按 [CriticalEvent.key] 去重后返回。
  ///
  /// [state] 取 `RoomSession.state`（本视角真正收到的裁剪态）。
  /// [syncEpoch] 取 `RoomSession.syncEpoch`（每完成一次全量同步自增一次）。
  /// [mySeat] 取 `RoomSession.seat`，只用于**显示名兜底**（拿不到角色名时
  /// 给本人写「你的角色」，给别人写「该角色」）—— 不参与任何事件判据。
  ///
  /// 返回空列表的情形：首帧 / 世代变化 / 无跃迁 / 全部命中去重表 /
  /// 新加入的成员（只登记基线）。
  List<CriticalEvent> sync(
    Map<String, Object?> state, {
    required int syncEpoch,
    required String mySeat,
  }) {
    // ① 世代变化（首连 / 断线补拉 / gap 自愈）：整机重置 → 走「首帧」分支。
    if (_epoch != syncEpoch) {
      reset();
      _epoch = syncEpoch;
    }

    final Map<String, _MemberSnap> current = _readMembers(state, mySeat);
    final String? combatStamp = _combatStampOf(state);

    // ② 首帧：只登记基线，绝不弹历史。
    if (!_hasBaseline) {
      _hasBaseline = true;
      _members
        ..clear()
        ..addAll(current);
      _combatStamp = combatStamp;
      return const <CriticalEvent>[];
    }

    final List<CriticalEvent> out = <CriticalEvent>[];

    // ③ 成员逐一 diff。按 seat 排序只为让产出顺序稳定（可测）。
    final List<String> seats = current.keys.toList()..sort();
    for (final String seat in seats) {
      final _MemberSnap? prev = _members[seat];
      final _MemberSnap cur = current[seat]!;
      if (prev == null) {
        // 新加入的成员：他此刻的状态是「历史」，只登记不弹（进房即弹一脸
        // 别人的旧死亡没有意义）。
        _members[seat] = cur;
        continue;
      }
      _diffMember(prev, cur, out);
      _members[seat] = cur;
    }
    // 已离开（被踢 / 退房）的成员：删基线，回来时按「新成员」重新登记。
    _members.removeWhere(
      (String seat, _MemberSnap _) => !current.containsKey(seat),
    );

    // ④ 战斗 diff：只在「在打 / 不在打」与「换了一场」时产出。
    if (_combatStamp != combatStamp) {
      final String? prevStamp = _combatStamp;
      // 先收尾再开新的一场（同一帧内先「结束」后「开始」，观感才对）。
      if (prevStamp != null) {
        out.add(CriticalEvent(
          key: 'combat:end:$prevStamp',
          kind: CriticalEventKind.combatEnd,
          title: EventBannerCopy.combatEndTitle(),
          subtitle: EventBannerCopy.combatEndSubtitle(),
          art: _artOf(CriticalEventKind.combatEnd),
        ));
      }
      if (combatStamp != null) {
        out.add(CriticalEvent(
          key: 'combat:start:$combatStamp',
          kind: CriticalEventKind.combatStart,
          title: EventBannerCopy.combatStartTitle(),
          subtitle: EventBannerCopy.combatStartSubtitle(_combatNames(state)),
          art: _artOf(CriticalEventKind.combatStart),
        ));
      }
      _combatStamp = combatStamp;
    }

    // ⑤ 去重表是第二道闸（第一道是上面的「跃迁判定」）。
    final List<CriticalEvent> fresh = <CriticalEvent>[];
    for (final CriticalEvent e in out) {
      if (_emitted.add(e.key)) fresh.add(e);
    }
    return fresh;
  }

  // ----------------------------------------------------------
  // 成员 diff
  // ----------------------------------------------------------

  /// 一个成员的「上一帧 → 这一帧」跃迁判定（**只认跃迁，不认当前值**）。
  ///
  /// 逐条依据：
  ///   · 死亡：`prev` 非死亡 且 `cur` 死亡。已死亡的角色后续每次写状态都会
  ///     重复走一遍 `applyStatusJudgment`（重复 warn），但 `prev.dead` 已是
  ///     true → 不再产出。rewind 让死亡消失时 `cur.dead == false` → 也不产出
  ///     （没有「复活」事件）。
  ///   · 永久疯狂：同上，用 `mental` 是否**新**包含 `永久疯狂` 判定。
  ///   · 临时 / 不定疯狂：`mental` 里新出现该项。精神分析 / 治愈把它清掉时
  ///     只是基线变化，不产事件。
  ///   · 新疯狂症：`madnessCount` **增加**才产（治疗让数量下降不产）；
  ///     键里带 `count`，所以「第 1 条、第 2 条……」各自只弹一次。
  void _diffMember(
    _MemberSnap prev,
    _MemberSnap cur,
    List<CriticalEvent> out,
  ) {
    final String seat = cur.seat;

    // ---- 死亡 ----
    if (cur.dead && !prev.dead) {
      out.add(CriticalEvent(
        key: 'death:$seat',
        kind: CriticalEventKind.death,
        title: EventBannerCopy.deathTitle(cur.name),
        subtitle: EventBannerCopy.deathSubtitle(),
        art: _artOf(CriticalEventKind.death),
      ));
    }

    // ---- 永久疯狂（SAN 归零 → 撕卡）----
    if (cur.permanentlyMad && !prev.permanentlyMad) {
      out.add(CriticalEvent(
        key: 'ripped:$seat',
        kind: CriticalEventKind.ripped,
        title: EventBannerCopy.rippedTitle(cur.name),
        subtitle: EventBannerCopy.rippedSubtitle(),
        art: _artOf(CriticalEventKind.ripped),
      ));
    }

    // ---- 临时疯狂 ----
    if (cur.temporarilyMad && !prev.temporarilyMad) {
      out.add(CriticalEvent(
        key: 'madness:temp:$seat',
        kind: CriticalEventKind.madness,
        title: EventBannerCopy.madnessTitle(cur.name, kMentalTemporary),
        subtitle: EventBannerCopy.madnessSubtitle(
          kMentalTemporary,
          rounds: cur.rounds,
        ),
        art: _artOf(CriticalEventKind.madness),
      ));
    }

    // ---- 不定疯狂 ----
    if (cur.indefinitelyMad && !prev.indefinitelyMad) {
      out.add(CriticalEvent(
        key: 'madness:indef:$seat',
        kind: CriticalEventKind.madness,
        title: EventBannerCopy.madnessTitle(cur.name, kMentalIndefinite),
        subtitle: EventBannerCopy.madnessSubtitle(kMentalIndefinite),
        art: _artOf(CriticalEventKind.madness),
      ));
    }

    // ---- 新疯狂症（裁定 D4：不显示症状名）----
    if (cur.madnessCount > prev.madnessCount && cur.madnessCount > 0) {
      out.add(CriticalEvent(
        key: 'madness:symptom:$seat:${cur.madnessCount}',
        kind: CriticalEventKind.madness,
        title: EventBannerCopy.newSymptomTitle(cur.name),
        subtitle: '',
        art: _artOf(CriticalEventKind.madness),
      ));
    } else if (cur.madnessCount < prev.madnessCount) {
      // 治愈 / 轮次消退 / rewind 让数量**下降**：本身不产事件，但要恢复
      // 计数递增的可用性 —— 把「高于当前计数的历史键」丢掉，这样「治好之后
      // 又得了第 1 条」还能再弹一次（键格式与裁定一致，只是补了这次重置，
      // 否则 `madness:symptom:<seat>:1` 会永久假死）。
      final String prefix = 'madness:symptom:$seat:';
      _emitted.removeWhere((String k) {
        if (!k.startsWith(prefix)) return false;
        final int n = int.tryParse(k.substring(prefix.length)) ?? 0;
        return n > cur.madnessCount;
      });
    }
  }

  // ----------------------------------------------------------
  // 读 state（只读，绝不写）
  // ----------------------------------------------------------

  /// 把 `state['members']` 读成 `seat → 快照`。
  ///
  /// 没有 `sheet` 的成员（旁观 / 未选卡）也建快照（空值），这样他后面选卡
  /// 时会被当作「同一个 seat 的跃迁」而不是「新成员」—— 否则第一个角色卡
  /// 一上场就会被静默登记成基线，之后同一次里的死亡会被漏掉。
  Map<String, _MemberSnap> _readMembers(
    Map<String, Object?> state,
    String mySeat,
  ) {
    final Map<String, _MemberSnap> out = <String, _MemberSnap>{};
    for (final Object? raw in asList(state['members'])) {
      final Map<String, Object?> m = asMap(raw);
      final String seat = jsStr(m['seat']);
      if (seat.isEmpty || seat == 'null') continue;
      out[seat] = _snapMember(m, seat, mySeat);
    }
    return out;
  }

  /// 单个成员 → 快照。字段读法严格按 `_cropMember` 的**公开面**：
  /// `sheet.status.body` / `sheet.mental` / `sheet.madnessCount`（或 `madness`
  /// 数组长度）/ `sheet.name`。
  _MemberSnap _snapMember(
    Map<String, Object?> m,
    String seat,
    String mySeat,
  ) {
    final Map<String, Object?> sheet = asMap(m['sheet']);
    final Map<String, Object?> status = asMap(sheet['status']);

    // `mental` 现在是**多选数组**（一个人可以同时有永久疯狂 + 临时疯狂）；
    // 老存档 / 老事件里可能是**单选字符串**，两种都要认。
    final List<String> mental = <String>[];
    final Object? mentalRaw = sheet['mental'];
    if (mentalRaw is String) {
      final String single = mentalRaw.trim();
      if (single.isNotEmpty) mental.add(single);
    } else {
      for (final Object? x in asList(mentalRaw)) {
        final String v = jsStr(x).trim();
        if (v.isEmpty) continue;
        mental.add(v);
      }
    }

    // 计数的两个来源：
    //   · 本人 / KP → 整份 sheet，有 `madness` 数组，长度即计数（还能取轮数）
    //   · 其他玩家 → `_cropMember` 只给 `madnessCount`（整数）
    final Object? madnessRaw = sheet['madness'];
    final bool hasMadnessArray = madnessRaw is List;
    final int madnessCount = hasMadnessArray
        ? asList(madnessRaw).length
        : jsNum(sheet['madnessCount']);
    final int? rounds =
        hasMadnessArray ? _roundsOf(asList(madnessRaw)) : null;

    return _MemberSnap(
      seat: seat,
      name: _displayName(sheet, m, seat, mySeat),
      body: jsStr(status['body']).trim(),
      mental: List<String>.unmodifiable(mental),
      madnessCount: madnessCount < 0 ? 0 : madnessCount,
      rounds: rounds,
    );
  }

  /// 疯狂症数组里「临时发作还剩几轮」：取未标记 `permanent` 的最大轮数。
  ///
  /// 数组里可能混着背景症状（`permanent: true, rounds: 0`），它们不算
  /// 「临时疯狂的持续轮数」，必须跳过。
  static int? _roundsOf(List<Object?> madness) {
    int best = 0;
    for (final Object? raw in madness) {
      final Map<String, Object?> e = asMap(raw);
      if (jsTruthy(e['permanent'])) continue;
      final int r = jsNum(e['rounds']);
      if (r > best) best = r;
    }
    return best > 0 ? best : null;
  }

  /// 显示名：`sheet.name` → 成员 `charName` → `nickname` → 兜底。
  ///
  /// 绝不把 `seat` / `actorId` 当名字（与 `raUnitName` 同口径）。本人拿不到
  /// 角色名时写「你的角色」，别人写「该角色」。
  static String _displayName(
    Map<String, Object?> sheet,
    Map<String, Object?> member,
    String seat,
    String mySeat,
  ) {
    final List<String> candidates = <String>[
      jsStr(sheet['name']).trim(),
      jsStr(member['charName']).trim(),
      jsStr(member['nickname']).trim(),
    ];
    for (final String c in candidates) {
      if (c.isNotEmpty && c != 'null') return c;
    }
    return seat == mySeat ? '你的角色' : '该角色';
  }

  /// 战斗快照的标识：不在战斗中 → `null`；在战斗中 → 开战戳字符串。
  ///
  /// 取 `combat.startedAt`（`combatStart` 写入的 `now()`）。老存档 / 手工构造
  /// 可能缺这个键，此时用 `anon<n>` 兜底，并**沿用上一帧的匿名戳**（否则同一
  /// 场战斗每帧都会算出一个新戳，被判成「换了一场」而反复弹「战斗开始」）。
  String? _combatStampOf(Map<String, Object?> state) {
    final Object? raw = state['combat'];
    if (raw is! Map) return null;
    final Map<String, Object?> combat = asMap(raw);
    // 空 Map（`{}`）也算「没有战斗」：玩家端裁出来的 combat 一定带 order。
    if (combat.isEmpty) return null;
    final String stamp = jsStr(combat[_kCombatStampKey]).trim();
    if (stamp.isNotEmpty && stamp != 'null') return stamp;
    final String? prev = _combatStamp;
    if (prev != null && prev.startsWith('anon')) return prev;
    _anonCombatSeq += 1;
    return 'anon$_anonCombatSeq';
  }

  /// 参战名单（`combat.order[].name`，按行动顺序）。
  ///
  /// 多行动槽的角色会在 `order` 里出现多次（`id` 带 `#1` / `#2` 后缀），
  /// 名字重复是正常的 —— 去重交给 [EventBannerCopy.combatStartSubtitle]。
  List<String> _combatNames(Map<String, Object?> state) {
    final Object? raw = state['combat'];
    if (raw is! Map) return const <String>[];
    final List<String> names = <String>[];
    for (final Object? slotRaw in asList(asMap(raw)['order'])) {
      final String name = jsStr(asMap(slotRaw)['name']).trim();
      if (name.isEmpty || name == 'null') continue;
      names.add(name);
    }
    return names;
  }
}
