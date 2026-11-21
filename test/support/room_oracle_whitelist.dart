// ============================================================
// test/support/room_oracle_whitelist.dart — 「已知差异」登记（恰好 2 条）
//
// 硬约束（team-lead 裁决 U6 / F3 裁决 A / 设计 §6.4）：
//   · 全库**恰好 2 条** KnownDivergence，断言 length == 2；
//   · 只允许登记 allowedPaths 里的精确 JSON 路径，禁止 `.*` 通配；
//   · 其余场景一律严格 expectJsonMatch + randUsed 全等，禁用 contains / 模糊匹配。
//   · 每条登记覆盖的每个 case 都**必须真的产生差异**；登记但零消费的路径一律删
//     （qa_p4_whitelist_proof_test.dart 常驻核算「一条不多、一条不少」）。
//     当前：S:q1 = 9 条路径 / S:trim = 1 条路径。
//
// ① S:q1 —— 旧版 room-model.js:965 初始 emit 把 vis/to 交给 reduce（脱敏正确），
//    而 :3450 回退重放只传 {t, seq, p}，丢掉 vis/to →
//    :685 的 `evt.vis === undefined` 被当成 PUBLIC → 秘密检定被写成明文；
//    :762 的 PRIVATE 守卫同样失效 → 定向私密混进 KP 的公共私有栏。
//    Dart 侧靠「RoomEvent 持久化 vis/to + apply 单口重放」修正，故必然不同。
// ② S:trim —— 旧版 :1025 `_maybeSnapshot` 用 shift() 裁掉建团基线快照，
//    :3437 的 rollback 又以 snapshots[0] 无条件兜底 → 快照表打满后深回退
//    状态不退、:3468 把快照表清空、二次回退崩溃。F3 裁决 A 要求本期修，
//    因此这是**第 2 条有意偏离 oracle** 的登记（QA 现造 oracle 的 F:4 例
//    已证明修复前 Dart 与旧版逐字段一致）。
// ============================================================

/// F3 第 2 条登记放行的**唯一**精确路径。
///
/// F5 已把 `room_oracle.dart#RoomOracleFixture.run` 的比较根改回 `r'$'`
/// （用例名改走 `label` 参数，只影响报错），故这里恢复文档语法的
/// `$.` 精确路径：只放行 `snapshotSeqs` 的第 0 个下标，不放过整棵子树、
/// 不用任何通配；数组长度、其余 19 个下标、state / steps / logSeq /
/// saveKeys 等一律仍逐字段严格比较。
const String kTrimAllowedPath = r'$.snapshotSeqs[0]';

/// 一条「旧版与 Dart 行为不同」的登记。
class KnownDivergence {
  const KnownDivergence({
    required this.caseId,
    required this.legacyRef,
    required this.reproInput,
    required this.legacyBehavior,
    required this.dartBehavior,
    required this.allowedPaths,
    required this.forbiddenKeys,
    this.exactCaseNames = const <String>{},
    this.excludeCaseNames = const <String>{},
  });

  /// fixture 里的 tag（或 case name 前缀）
  final String caseId;

  /// 额外的**精确** case name 名单（不改 [coversCase] 的前缀匹配口径）。
  ///
  /// ⚠️ P4-QA 的 F1 修复收紧的是「name 前缀」：只认 caseId 本身与
  ///    `caseId#序号`。这里补的是**逐个点名**的精确集合，不是放宽前缀；
  ///    只用于登记「旧版 oracle 里确实会产生差异的那一个具体用例名」。
  final Set<String> exactCaseNames;

  /// 精确**排除**的 case name（比 tag 匹配更细的一层）。
  ///
  /// ⚠️ P4-QA 终验：`S:q1` 家族 3 例共用同一个 tag，但 `#1015` 的重放区间为空
  ///    （`(2,2]`），Dart 与旧版**逐字段相等**、零差异。它若继续被 tag 覆盖，
  ///    将来这 9 条登记路径上真出现回归也会被静默放行。故按名排除，让它回到
  ///    严格比较（严格比较下它是绿的，因为本来就相等）。
  ///    这是**收紧**：不放宽任何前缀，也不新增任何放行路径。
  final Set<String> excludeCaseNames;

  /// 旧版源码位置
  final String legacyRef;

  /// 完整复现输入
  final String reproInput;

  /// 旧版实际行为
  final String legacyBehavior;

  /// Dart 期望行为（修正后）
  final String dartBehavior;

  /// 精确到 JSON 路径；支持结尾 `.*` 表示该节点下所有后代
  final List<String> allowedPaths;

  /// 任何情况下都不得出现在未授权载荷里的键
  final List<String> forbiddenKeys;

  bool coversCase(Map<String, Object?> c) {
    final tag = c['tag'];
    final name = c['name'];
    // 精确排除优先：被排除的用例一律回到严格比较（零差异用例不该蹭白名单）。
    if (name is String && excludeCaseNames.contains(name)) return false;
    if (tag is String && tag == caseId) return true;
    // ⚠️ P4-QA 加固：原来是 `name.startsWith(caseId)` —— `S:q1` 会把
    //    `S:q10` / `S:q1-other` 这类**无关用例**一并白名单掉（前缀过宽）。
    //    现在只认「完全同名」与 fixture 的 `caseId#序号` 命名法。
    if (name is String && (name == caseId || name.startsWith('$caseId#'))) {
      return true;
    }
    // 逐个点名的精确匹配：不放宽任何前缀，只认登记在册的完整用例名。
    if (name is String && exactCaseNames.contains(name)) return true;
    return false;
  }
}

const List<KnownDivergence> kRoomOracleWhitelist = <KnownDivergence>[
  KnownDivergence(
    caseId: 'S:q1',
    legacyRef: 'room-model.js:965（emit 传 vis/to）/ :3450（replay 只传 {t,seq,p}）'
        ' / :685（CHECK 脱敏判据）/ :762（PRIVATE 守卫）',
    // ★ F5：原文档写 rollback(5) 且把 emit 记成 seq1..seq5，那是错的。
    //   twoPeerOps() 的两次 attach 会占掉 seq1/seq2，5 条 emit 实际落在
    //   seq3..seq7。rollback(5) 的 target=4 会把秘密 CHECK(seq5) 裁掉，
    //   重放区间根本不含秘密事件 → 旧版 Q1 缺陷触发不了、白名单成死登记。
    //   现 fixture 改为 rollback(6)（target=5），逐例说明重放区间见下。
    reproInput: 'S:q1 家族 3 例，fn=hostScript；公共前缀 twoPeerOps()'
        '（attach p1/p2 各占 seq1/seq2）。\n'
        '① #1013 snapshotEvery=2：emit seq3 CHAT PUBLIC / seq4 LOG PUBLIC / '
        "seq5 CHECK VIS.SEAT to='p1'（summary='秘密检定：骰出 07，极难成功'）/ "
        "seq6 PRIVATE VIS.SEAT to='p1'（text='线索A'）/ seq7 CHAT PUBLIC；"
        'rollback(6)（target=5，快照 [0,2,4] 命中 @4，'
        '重放区间 (4,5] = seq5 秘密 CHECK；dropped=2 = seq6 PRIVATE + seq7 CHAT）；'
        'syncFor(p2)=steps[8] / syncFor(p1)=steps[9]。\n'
        '② #1014 snapshotEvery=3：同上 5 条 emit；'
        'rollback(6)（target=5，快照 [0,3] 命中 @3，'
        '重放区间 (3,5] = seq4 LOG + seq5 秘密 CHECK；dropped=2）；'
        'syncFor(p2)=steps[8] / syncFor(p1)=steps[9]。\n'
        '③ #1015 snapshotEvery=1（PRIVATE 定向 KP 守卫）：'
        "emit seq3 PRIVATE VIS.SEAT to=host（text='暗骰：07'）/ "
        'seq4 LOG PUBLIC；rollback(3)（target=2，快照 [0,1,2] 命中 @2，'
        '重放区间 (2,2] 为空、dropped=2 = seq3 PRIVATE + seq4 LOG）；'
        'syncFor(p2)=steps[5]；该例 Dart 与旧版逐字段一致，零差异，'
        '故由 excludeCaseNames 按名排除（回到严格比较），不共享本登记的放行。',
    legacyBehavior: '回退重放只传 {t,seq,p}、丢掉 vis/to → '
        'state.logs[1] 变成明文 {seat:\'p1\', '
        "text:'秘密检定：骰出 07，极难成功', redacted 键缺失}；"
        'steps[8]（syncFor p2）与 steps[9]（syncFor p1）的 state.logs[1] '
        '同样含明文。#1013/#1014 各 9 条差异，全部集中在 logs[1] 的 '
        'seat / text / redacted 三个字段；state.privates 两侧同为 []，'
        'steps[9].state.privates 两侧同为 seq6 定向私密，均不产生差异。',
    dartBehavior: "state.logs[1] 保持脱敏行 {seat:'', "
        "text:'KP 秘密进行了一次检定', kind:'check', opp:null, "
        'redacted:true}（redacted 键存在）；'
        'steps[8]/steps[9] 的 state.logs[1] 同样脱敏。'
        '私密栏按 evt.vis/evt.to 守卫，本 fixture 两侧取值一致；'
        '#1015 重放区间为空，Dart 与旧版逐字段一致（零差异）。',
    // ★ P4-QA 终验：14 → 9。独立核算（qa_p4_whitelist_proof_test.dart）
    //   证明两侧真正产生差异的只有 logs[1] 的 seat / text / redacted 三字段
    //   × 三个视图（权威态 state、steps[8]=syncFor(p2)、steps[9]=syncFor(p1)）。
    //   被删的 5 条（3× `.opp` + `$.state.privates` + `$.steps[8].state.privates`）
    //   在旧版与 Dart 两侧取值相同（legacy 的脱敏行同样带 `opp:null`；
    //   私密栏两侧同为 `[]`），属于「登记了但从不消费」的冗余放行。
    allowedPaths: <String>[
      // 回退后的权威端 state（旧版明文行 vs Dart 脱敏行）
      r'$.state.logs[1].text',
      r'$.state.logs[1].seat',
      r'$.state.logs[1].redacted',
      // syncFor('p2') 在脚本里的下标（attach×2 + emit×5 + rollback + syncFor×2）
      r'$.steps[8].state.logs[1].text',
      r'$.steps[8].state.logs[1].seat',
      r'$.steps[8].state.logs[1].redacted',
      // syncFor('p1')：同根因，脱敏行
      r'$.steps[9].state.logs[1].text',
      r'$.steps[9].state.logs[1].seat',
      r'$.steps[9].state.logs[1].redacted',
    ],
    forbiddenKeys: <String>[
      'hp',
      'hpMax',
      'secret',
      'kpOnly',
      'attrs',
    ],
    // `#1015` 重放区间为空（target=2、快照命中 @2）→ 两侧逐字段相等、零差异。
    // tag 会把同家族的它一起白名单掉，故按名排除，让它回到严格比较。
    excludeCaseNames: <String>{'S:q1#1015'},
  ),
  // ----------------------------------------------------------
  // ② F3：快照裁剪后深回退（team-lead 裁决 A：本期修，第 2 条有意偏离）
  // ----------------------------------------------------------
  KnownDivergence(
    caseId: 'S:trim',
    legacyRef: 'room-model.js:845（构造时 snapshots=[{seq:0}]）/ '
        ':1021-1025（_maybeSnapshot 用 shift() 无脑裁掉首条）/ '
        ':3437-3439（rollback 以 snapshots[0] 无条件兜底）/ '
        ':3468（filter 把快照表清空）；'
        'Dart 对应 lib/domain/room_model_host_core.dart:_maybeSnapshot 与 '
        'lib/domain/room_model_rollback.dart:rollback',
    reproInput: 'snapshotEvery=1, snapshotLimit=3；p1/p2 在线；'
        '连续 emit 10 条事件（快照表打满后只剩最近 3 条）；'
        'rollback(3)（target=2 早于所有留存快照）；再 rollback(2)',
    legacyBehavior: 'rollback(3) 后 log.seq=2 但 state.seq=8（用 seq8 的'
        '「未来快照」重建，权威态仍留着被撤销的事件）；'
        'snapshots 被清空；再 rollback(2) 时 snapshots.first 抛 '
        "'StateError: No element'（旧版是 TypeError）",
    dartBehavior: '_maybeSnapshot 保留 index0 基线 + 最近 N-1 条；'
        'rollback 只在 seq<=target 里选快照，一条都没有就从建团空状态'
        '重放 (0,target]；state.seq 与 log.seq 恒等；'
        '快照表永不清空，连续两次深回退都不崩溃；'
        'Q1 的 apply(persist:false) 单口与 vis/to 修正不受影响',
    allowedPaths: <String>[
      // ★ 唯一会产生 oracle 差异的精确路径：QA 现造 oracle 的 F:4 例
      //   （snapshotEvery=1、21 个 op 打满 20 条快照窗口）修复后
      //   snapshotSeqs=[0,3..21]，旧版是 shift() 后的 [2..21]，只有 [0]
      //   这一格不同。F5 后比较根为 `r'$'`，见 [kTrimAllowedPath] 的说明。
      kTrimAllowedPath,
    ],
    forbiddenKeys: <String>[
      'hp',
      'hpMax',
      'secret',
      'kpOnly',
      'attrs',
    ],
    // 逐个点名：QA 的 qa_p4_fresh_oracle.json 里只有这一例打满快照窗口。
    // 精确名单，不放宽 coversCase 的前缀匹配（遵守 P4-QA 的 F1 修复）。
    exactCaseNames: <String>{'F:4#900001'},
  ),
];
