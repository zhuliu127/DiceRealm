// ============================================================
// event_banner_copy.dart — 5 类关键事件横幅的**文案真源**（P20 需求 2）
//
// 为什么单独一个文件：
//   横幅上的字一律由 **APP 生成**（不解析 domain log 文案），且运营/文案改
//   一个字都不该动 tracker 的判据、也不该动 UI 的布局。所以「判据」留在
//   `critical_event_tracker.dart`，「怎么说」全部收在这里的纯函数里。
//
// ★ 纯 Dart：零 Flutter 依赖（便于纯逻辑单测）。本文件只用 `dart:core`。
//
// ★ 裁定 D4：**绝不显示具体疯狂症状名**。
//   `room_model_host_core.dart:453-472` 的 `_cropMember` 对「非本人 / 非 KP」
//   的成员只下发 `madnessCount`（数组长度），`madness`（症状名 / 描述）刻意
//   不下发；玩家端根本拿不到。既有日志里泄露症状名属历史问题，本批不扩大。
//   因此这里只有「获得 1 项新的疯狂症状」，没有 `newSymptomSubtitle`。
//
// ★ 与 `Art` 常量的一致性：本文件**不含**任何资源路径 —— 路径由
//   `critical_event_tracker.dart` 的 `EventBannerArt`（同样零 Flutter 依赖）
//   给出，UI 侧还可以用 `CriticalEventTracker(artOf: ...)` 注入
//   `lib/ui/art.dart` 的 `Art.e18Banner*` 常量做单一真源。
// ============================================================

/// 「空名字」的统一兜底。宁可显示「该角色」也不显示 `seat` / `actorId`
/// 之类的内部标识（`raUnitName` 同口径：绝不把 seat 当名字）。
const String _kFallbackName = '该角色';

/// 副行里「最多列出几个名字」。
const int _kMaxNames = 4;

/// 5 类关键事件横幅的文案（全部是纯函数，无状态、无副作用）。
///
/// 用法（tracker 侧）：
/// ```dart
/// CriticalEvent(
///   key: 'death:$seat',
///   kind: CriticalEventKind.death,
///   title: EventBannerCopy.deathTitle('沈砚清'),
///   subtitle: EventBannerCopy.deathSubtitle(),
///   art: EventBannerArt.of(CriticalEventKind.death),
/// );
/// ```
class EventBannerCopy {
  const EventBannerCopy._();

  // ---------------- ① 进入战斗 ----------------

  /// 「⚔ 战斗开始」。
  static String combatStartTitle() => '⚔ 战斗开始';

  /// 「共 N 名行动者：A、B、C」——最多列 4 个，多出来的写「等 N 人」。
  ///
  /// [names] 允许有重复（多行动槽的角色会在 `combat.order` 里出现多次）、
  /// 允许有空串；这里去重、去空白、保序，最后按去重后的**人数**计 N。
  static String combatStartSubtitle(List<String> names) {
    final List<String> clean = <String>[];
    for (final String raw in names) {
      final String name = raw.trim();
      if (name.isEmpty) continue;
      if (clean.contains(name)) continue;
      clean.add(name);
    }
    if (clean.isEmpty) return '战斗已开始';
    final int total = clean.length;
    final int shown = total > _kMaxNames ? _kMaxNames : total;
    final String head = clean.take(shown).join('、');
    if (total <= _kMaxNames) return '共 $total 名行动者：$head';
    return '共 $total 名行动者：$head 等 $total 人';
  }

  // ---------------- ② 战斗结束 ----------------

  /// 「战斗结束」。
  static String combatEndTitle() => '战斗结束';

  /// 「回到探索模式」。
  static String combatEndSubtitle() => '回到探索模式';

  // ---------------- ③ 死亡 ----------------

  /// 「沈砚清 已死亡」。
  static String deathTitle(String charName) => '${_name(charName)} 已死亡';

  /// 「撕卡 —— 该角色只能通过聊天框交流」。
  static String deathSubtitle() => '撕卡 —— 该角色只能通过聊天框交流';

  // ---------------- ④ 永久疯狂（SAN 归零 → 撕卡） ----------------

  /// 「沈砚清 陷入永久疯狂」。
  static String rippedTitle(String charName) => '${_name(charName)} 陷入永久疯狂';

  /// 「撕卡 —— SAN 已归零」。
  static String rippedSubtitle() => '撕卡 —— SAN 已归零';

  // ---------------- ⑤ 临时 / 不定疯狂 ----------------

  /// 「沈砚清 陷入临时疯狂」/「沈砚清 陷入不定疯狂」。
  ///
  /// [kind] 直接取精神状态字面量（`临时疯狂` / `不定疯狂`），与
  /// `domain/madness_state.dart` 的 `kMentalTemporary` / `kMentalIndefinite`
  /// 同源，不另造一套措辞。传空串时退回「不定疯狂」（更严重的那一档）。
  static String madnessTitle(String charName, String kind) {
    final String k = kind.trim();
    final String state = k.isEmpty ? '不定疯狂' : k;
    return '${_name(charName)} 陷入$state';
  }

  /// 「症状将持续 N 轮」/「需治愈才能解除」。
  ///
  /// [rounds] 只在**能拿到疯狂症数组**时才有值（KP 视角：`sheet.madness`
  /// 全量下发）；玩家端被 `_cropMember` 裁成 `madnessCount`，拿不到轮数，
  /// 于是 [rounds] 为 null —— 此时绝不能编一个数字出来，退成「若干轮」。
  static String madnessSubtitle(String kind, {int? rounds}) {
    final String k = kind.trim();
    if (k.contains('永久')) return '撕卡 —— SAN 已归零';
    if (k.contains('不定')) return '需治愈才能解除';
    if (rounds != null && rounds > 0) return '症状将持续 $rounds 轮';
    return '症状将持续若干轮';
  }

  // ---------------- ⑤' 新疯狂症（不显示症状名，裁定 D4） ----------------

  /// 「沈砚清 获得 1 项新的疯狂症状」。副行为空（不显示症状名）。
  static String newSymptomTitle(String charName) =>
      '${_name(charName)} 获得 1 项新的疯狂症状';

  // ---------------- 内部 ----------------

  /// 名字兜底：去空白；空则「该角色」。
  static String _name(String raw) {
    final String name = raw.trim();
    return name.isEmpty ? _kFallbackName : name;
  }
}
