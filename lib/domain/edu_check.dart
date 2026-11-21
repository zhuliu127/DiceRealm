// ============================================================
// edu_check.dart — 教育进步检定（CoC 7e 建卡期）的**纯计算核心**
//
// 规则书（创建调查员 · 年龄调整）：
//   每个「教育进步检定」都掷 1D100，
//   结果 **严格大于** 当前 EDU 才算进步 → EDU 增加 1D10（上限 99）；
//   否则不变。建卡期能做**几次**由年龄决定（见 [eduCheckAllowance]）：
//   官方 CoC 7e 的表是「年龄越大次数越多」—— 20–39 岁 1 次、40–49 岁 2 次、
//   50–59 岁 3 次、60 岁以上 4 次。次数用完就不能再掷（避免刷点）。
//
// ⚠️ 为什么把两个骰值做成**入参**：
//   纯函数才能被单测逐条钉死（`d100 == edu` 不增、`d100 == edu + 1` 增、
//   95 + 10 封顶 99）。随机数在调用方（UI 层）用现有 rng 生成后传进来；
//   这里不 import 任何随机源，也不读写角色卡 —— 同一组入参永远得到同一结果，
//   天然幂等（「能做几次」由 [eduCheckAllowance] 决定，「已做几次」由调用方的
//   eduProgress.log 记录控制，都不在这里）。
//
// 与 `rules_coc7.dart#eduImproveCheck(edu, [rng])` 的关系：
//   后者是「掷骰 + 计算」的便捷封装（老接口、被 oracle 夹具逐字比对），
//   内部改为调用本文件的 [eduCheck] —— 两处判定只有一份事实源。
// ============================================================

/// 教育进步检定的上限（规则书：EDU 最高 99）
const int eduCap = 99;

/// 一次教育进步检定的结果
class EduCheckResult {
  const EduCheckResult({
    required this.before,
    required this.roll,
    required this.success,
    required this.gain,
    required this.after,
  });

  /// 检定前的 EDU
  final int before;

  /// 掷出的 1D100
  final int roll;

  /// 是否进步（`roll > before` 才算，**严格大于**）
  final bool success;

  /// 实际增加的点数。封顶后可能小于掷出的 1D10（例如 95 + 10 → 只加 4），
  /// 失败时为 0。
  final int gain;

  /// 检定后的 EDU（已封顶 99）
  final int after;

  @override
  String toString() =>
      'EduCheckResult(before: $before, roll: $roll, success: $success, '
      'gain: $gain, after: $after)';
}

/// 把 EDU 夹到 [0, 99]（只用于**成功后的结果**）
int _clampEdu(int v) => v < 0 ? 0 : (v > eduCap ? eduCap : v);

/// 教育进步检定（纯函数）
///
/// - [edu]  当前 EDU
/// - [d100] 掷出的 1D100
/// - [d10]  掷出的 1D10（**只在进步时才会被用到**；失败传什么都不影响结果）
///
/// ⚠️ 入参 [edu] **不夹取**：与 `rules_coc7.dart#eduImproveCheck`（及其 JS 原码）
/// 逐字一致 —— 脏数据 edu=100 失败时原样返回 100，不能被这里悄悄改成 99。
/// 封顶只发生在「成功之后」，且 [EduCheckResult.gain] 因此可能小于掷出的 1D10。
EduCheckResult eduCheck(int edu, int d100, int d10) {
  final before = edu;
  // 严格大于：掷出值等于 EDU 视为「没有进步」（规则书原文：大于）。
  final success = d100 > before;
  if (!success) {
    return EduCheckResult(
      before: before,
      roll: d100,
      success: false,
      gain: 0,
      after: before,
    );
  }
  final after = _clampEdu(before + d10);
  return EduCheckResult(
    before: before,
    roll: d100,
    success: true,
    gain: after - before,
    after: after,
  );
}

/// 按年龄该做的**教育进步检定次数**（CoC 7e 建卡期）。
///
/// | 年龄   | 次数 |
/// |--------|------|
/// | 15–19  | 0（见下方偏差说明） |
/// | 20–39  | 1 |
/// | 40–49  | 2 |
/// | 50–59  | 3 |
/// | 60–69  | 4 |
/// | 70–79  | 4 |
/// | 80–89  | 4 |
/// | 90+    | 4 |
///
/// 次数**随年龄单调不减**，高龄段永远不少于低龄段。
///
/// ⚠️ 与官方表的已知偏差（15–19 档）：官方《守秘人规则书》给 15–19 岁
///    **2 次**教育进步检定；本项目在 `rules_coc7.dart#ageTable` 里把少年档
///    换成了「力量与体型合计 −5，之后幸运骰两次取较高值」，教育进步检定记
///    **0 次**。本函数**镜像项目现有的年龄表**（而不是照抄官方表），原因：
///      · `ageAdjust().eduChecks` / 基本资料页「教育进步检定 N 次」/ 概要页 /
///        `test/fixtures/engine.json` 的 oracle 夹具（15 岁那条 eduChecks: 0）
///        全部以年龄表为准，单方面改成 2 会让这三处与夹具互相矛盾；
///      · 15–19=2 而 20–39=1 会破坏「年龄越大次数越多」的单调性，
///        而用户的原话正是「随着年龄的增长检定次数越来越多」。
///    两处的一致性由 `test/p10_edu_check_test.dart` 的护栏用例逐档对照
///    `ageRule(age)['eduChecks']` 钉死 —— 改这里必须同步改年龄表。
///
/// 年龄 < 15、0 或负数等异常值按**最低档**处理（返回 0，不抛异常）。
int eduCheckAllowance(int age) {
  if (age < 20) return 0; // 15–19（及 <15 等异常值）
  if (age < 40) return 1; // 20–39
  if (age < 50) return 2; // 40–49
  if (age < 60) return 3; // 50–59
  return 4; // 60–69 / 70–79 / 80–89 / 90+（年龄段上限与 ageTable 的 999 对齐）
}
