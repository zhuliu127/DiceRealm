// ============================================================
// madness_state.dart — 精神状态的**纯状态机**（需求 6 / 7）
//
// 为什么单独一个文件：精神状态原先散落在
//   · `rules_coc7.dart`（选项字面量）
//   · `normalize.dart`（派生「疯狂症状」）
//   · `ui/status_ops.dart`（点 chip 的互斥）
//   · `room_model_actions_sheet.dart`（跑团里的 SAN / 轮次 / 治愈）
// 四处各写一份 if，规则一改就有三处对不上。这里把「状态 → 状态」的
// 迁移收敛成一个纯函数 [nextMentalState]，其余各处只负责调用。
//
// 规则（用户原话 → 迁移表，见 test/p8_madness_state_test.dart 真值表）：
//   · 精神状态的取值只有 正常 / 临时疯狂 / 不定疯狂 / 潜在疯狂 /
//     疯狂症状 / 永久疯狂 / 其他；**没有「昏迷」**（昏迷是身体状态）。
//   · 「不定疯狂」与「潜在疯狂」互斥，同时只能有一个。
//   · 不定疯狂 / 临时疯狂 期间：**不掉 SAN、不获得新疯狂症**。
//   · 不定疯狂 + 其疯狂症随轮次消失 → 潜在疯狂；
//     临时疯狂 + 其疯狂症随轮次消失 → 回正常（不产生潜在疯狂）。
//   · 潜在疯狂 + 损失任意 SAN(>0) → 立刻回到不定疯狂，并**新生成一条**疯狂症。
//   · 治愈按钮 / 成功的精神分析 → 取消 不定疯狂 与 潜在疯狂。
//   · 「疯狂症状」是**背景标记**，永久、不可治愈、不与跑团游戏联动。
// ============================================================

import 'character.dart' show kMentalNormal;

/// 精神状态取值（与 rules_coc7.dart#mentalStatus 同源，勿各写一份字面量）。
const String kMentalNormalState = kMentalNormal;
const String kMentalTemporary = '临时疯狂';
const String kMentalIndefinite = '不定疯狂';
const String kMentalPotential = '潜在疯狂';
const String kMentalSymptom = '疯狂症状';
const String kMentalPermanent = '永久疯狂';
const String kMentalOther = '其他';

/// 历史上的错误取值：昏迷不是精神状态（需求 6）。仅用于老数据迁移时丢弃。
const String kMentalLegacyComa = '昏迷';

/// 历史取值：跑团层曾把「潜在疯狂」叫成「不定疯狂（症状消失）」。
/// 老存档 / 老事件日志仍可能出现，读入时统一翻译成 [kMentalPotential]。
const String kMentalLegacyPotential = '不定疯狂（症状消失）';

/// 合法的精神状态取值（顺序即 UI chip 顺序）。
const List<String> kMentalChoices = <String>[
  kMentalNormalState,
  kMentalTemporary,
  kMentalIndefinite,
  kMentalPotential,
  kMentalSymptom,
  kMentalPermanent,
  kMentalOther,
];

const Set<String> kMentalAllowed = <String>{
  kMentalNormalState,
  kMentalTemporary,
  kMentalIndefinite,
  kMentalPotential,
  kMentalSymptom,
  kMentalPermanent,
  kMentalOther,
};

/// 把任意一条历史值翻译成现行值；无法识别返回空串。
String normalizeMentalValue(Object? raw) {
  final v = raw == null ? '' : '$raw'.trim();
  if (v.isEmpty) return '';
  if (v == kMentalLegacyComa) return ''; // 昏迷不再属于精神状态
  if (v == kMentalLegacyPotential) return kMentalPotential;
  return kMentalAllowed.contains(v) ? v : '';
}

/// 规整一组精神状态（幂等、无副作用）。
///
/// 互斥优先级（从强到弱）：
///   `永久疯狂` > `正常` > `不定疯狂`（与 `潜在疯狂` 互斥时保不定）
/// 另：`疯狂症状` 是派生标记，由调用方通过 [withBackgroundSymptom] 决定增删。
List<String> normalizeMentalList(Iterable<Object?> raw) {
  final out = <String>[];
  for (final x in raw) {
    final v = normalizeMentalValue(x);
    if (v.isEmpty || out.contains(v)) continue;
    out.add(v);
  }
  if (out.contains(kMentalPermanent)) return <String>[kMentalPermanent];
  if (out.contains(kMentalNormalState)) {
    // 「正常」代表没有任何异常：其余项一律让位。
    return <String>[kMentalNormalState];
  }
  if (out.contains(kMentalIndefinite) && out.contains(kMentalPotential)) {
    out.remove(kMentalPotential); // 互斥：保重的那一个
  }
  if (out.isEmpty) out.add(kMentalNormalState);
  return out;
}

/* ============================================================
 * 状态迁移
 * ============================================================ */

/// 触发状态迁移的事件。
enum MentalEvent {
  /// 轮次推进，一条疯狂症自然消退。[fromIndefinite] 标明它是不是
  /// 「不定疯狂」带来的那一条。
  symptomFaded,

  /// 损失了任意 SAN（> 0）。
  sanLost,

  /// 治愈按钮 / 成功的精神分析。
  cured,

  /// 背景（含 AI 车卡 / 随机出卡）从疯狂表选了一个疯狂状态。
  backgroundMadness,

  /// SAN 归零 → 永久疯狂。
  sanZero,
}

/// 迁移结果：新的精神状态 + 是否需要新生成一条疯狂症。
class MentalTransition {
  const MentalTransition(this.mental, {this.spawnSymptom = false});

  final List<String> mental;

  /// true 表示调用方必须**真的**往 madness 数组里加一条新症状。
  final bool spawnSymptom;

  bool get hasIndefinite => mental.contains(kMentalIndefinite);
  bool get hasPotential => mental.contains(kMentalPotential);
  bool get hasTemporary => mental.contains(kMentalTemporary);
  bool get hasSymptomMarker => mental.contains(kMentalSymptom);

  @override
  String toString() =>
      'MentalTransition(${mental.join('|')}${spawnSymptom ? ' +symptom' : ''})';
}

/// 精神状态迁移函数（**唯一**的规则实现）。
///
/// [fromIndefinite] 只对 [MentalEvent.symptomFaded] 有意义。
MentalTransition nextMentalState(
  Iterable<Object?> current,
  MentalEvent event, {
  bool fromIndefinite = false,
}) {
  final list = normalizeMentalList(current);
  switch (event) {
    case MentalEvent.symptomFaded:
      if (list.contains(kMentalPermanent)) {
        return MentalTransition(list); // 永久疯狂不吃轮次
      }
      if (list.contains(kMentalIndefinite) && fromIndefinite) {
        final next = list.where((x) => x != kMentalIndefinite).toList();
        next.add(kMentalPotential);
        return MentalTransition(normalizeMentalList(next));
      }
      if (list.contains(kMentalTemporary)) {
        final next = list.where((x) => x != kMentalTemporary).toList();
        return MentalTransition(normalizeMentalList(next));
      }
      return MentalTransition(list);

    case MentalEvent.sanLost:
      // 临时 / 不定疯狂期间：不掉 SAN、不获得新疯狂症（由调用方拦截扣值）。
      if (blockedByMadness(list)) return MentalTransition(list);
      if (list.contains(kMentalPotential)) {
        final next = list
            .where((x) => x != kMentalPotential && x != kMentalNormalState)
            .toList();
        next.add(kMentalIndefinite);
        return MentalTransition(
          normalizeMentalList(next),
          spawnSymptom: true,
        );
      }
      return MentalTransition(list);

    case MentalEvent.cured:
      // P8 补充口径（用户明确）：KP 的治愈按钮、玩家的申请治愈、成功的
      // 精神分析，都能清除**除「永久疯狂」和「疯狂症状」以外**的所有异常
      // 精神状态 —— 临时疯狂、不定疯狂、潜在疯狂一并清掉。
      //
      // 这两个为什么留下：
      //   · 永久疯狂 = 撕卡级终局，不属于「异常状态」而是角色生死；
      //   · 疯狂症状 = 背景标记（需求 7），永久且不可治愈。
      final keep = <String>[
        for (final x in list)
          if (x == kMentalPermanent || x == kMentalSymptom) x,
      ];
      // keep 为空时 normalizeMentalList 会补回「正常」——正是我们要的语义。
      return MentalTransition(normalizeMentalList(keep));

    case MentalEvent.backgroundMadness:
      if (list.contains(kMentalPermanent)) return MentalTransition(list);
      final next = list.where((x) => x != kMentalNormalState).toList();
      if (!next.contains(kMentalSymptom)) next.add(kMentalSymptom);
      return MentalTransition(normalizeMentalList(next));

    case MentalEvent.sanZero:
      return const MentalTransition(<String>[kMentalPermanent]);
  }
}

/// 是否处于「临时疯狂 / 不定疯狂」——这两种状态**不允许掉 SAN**。
bool blockedByMadness(Iterable<Object?> mental) {
  final list = normalizeMentalList(mental);
  return list.contains(kMentalTemporary) || list.contains(kMentalIndefinite);
}

/// 是否处于「不能获得新疯狂症」的状态（与 [blockedByMadness] 同口径）。
bool blockedFromNewSymptom(Iterable<Object?> mental) => blockedByMadness(mental);

/// 当前是否为「潜在疯狂」。
bool isPotentialMadness(Iterable<Object?> mental) =>
    normalizeMentalList(mental).contains(kMentalPotential);

/// 当前是否为「不定疯狂」。
bool isIndefiniteMadness(Iterable<Object?> mental) =>
    normalizeMentalList(mental).contains(kMentalIndefinite);

/// 给「背景 / 永久」症状补上「疯狂症状」标记（需求 7）。
///
/// 只处理**背景来源**：临时 / 不定疯狂的发作症状不再派生该标记，
/// 否则「疯狂症状」会随跑团临时症状反复出现，与「仅作背景标记」冲突。
List<String> withBackgroundSymptom(Iterable<Object?> mental) =>
    nextMentalState(mental, MentalEvent.backgroundMadness).mental;
