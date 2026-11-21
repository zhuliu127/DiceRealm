// ============================================================
// wizard_checks.dart — 完整性检查（概要页那一张表）的**纯逻辑**
//
// 两件事：
//   1) 把 `lib/domain` 的 `engine.checkList()`（10 项，每条带 `step: 0..4`）
//      翻译成「新向导的步骤 id」—— domain 冻结，所以这张映射表只能写在 UI 层。
//   2) 追加 UI 层自己的检查项（武器 / 防具 / 物品）—— 规则层不管这些，
//      但玩家在概要页应该看得到自己漏了什么。
//
// ⚠️ 映射必须是**纯函数**并且可单测：概要页的「去修复 →」直接吃它的输出，
//   映射错了就会跳到错的页面（而且只有玩家点下去才会发现）。
//
// ⚠️ 旧版索引的语义（来自 `lib/domain/engine.dart#checkList` 的 `step` 参数）：
//   0 基本资料 / 1 属性 / 2 职业 / 3 信用评级 / 4 技能
//   新流程把「职业」并进「基本资料」，所以 0 与 2 默认都映射到 basics。
//
// ⚠️ **step 数字不够用**（QA 的 D2）：`step=2` 被两个语义不同的检查项共用：
//   · 「已选择职业」            → 在「基本资料」页选（basics）✔ 按数字映射就对
//   · 「职业限定技能选择完成」  → 只能在「职业技能」页勾选（skills）✘ 按数字映射跳错
//   domain 里那个 2 不能改（engine.checkList 冻结），所以映射升级成
//   **(step, label) 二元查表 + 单 step 兜底**：先按 label 查例外表，查不到再按数字。
// ============================================================

import '../../domain/character.dart';
import '../../domain/engine.dart';
import '../../domain/js_compat.dart';

/// 旧版 `checkList()` 的 `step` 索引 → 新步骤 id（单 step 兜底）
const Map<int, String> legacyCheckStepToId = <int, String>{
  0: 'basics',
  1: 'attrs',
  2: 'basics', // 「已选择职业」在这里；「职业限定技能选择完成」走下面的例外表
  3: 'assets',
  4: 'skills',
};

/// (step, label) 例外表：同一个 step 数字被两个语义不同的检查项共用时用它覆盖。
///
/// 键是 `'<step>|<checkList 的 label 原文>'`。目前只有一条：
///   `职业限定技能选择完成` 在 domain 里被标成 step=2（职业），
///   但玩家只能在「职业技能」页勾选 `_RequirementBlock`，所以指向 skills。
const Map<String, String> legacyCheckLabelToId = <String, String>{
  '2|职业限定技能选择完成': 'skills',
};

/// 旧索引 → 步骤 id。
///
/// [label] 可选：给了就先查 **(step, label) 二元例外表**，查不到再按 step 兜底。
/// 只给 step 时行为与升级前一致（既有调用点不会碎）。
/// 认不出返回 null —— 调用方据此不显示「去修复」。
String? stepIdForCheck(Object? legacyStep, [String? label]) {
  final n = jsParseInt(legacyStep);
  if (n == null) return null;
  if (label != null) {
    final byLabel = legacyCheckLabelToId['$n|$label'];
    if (byLabel != null) return byLabel;
  }
  return legacyCheckStepToId[n];
}

/// 从一行 `checkList()` 结果直接取步骤 id（把 label 一起带上，别再自己拆）
String? stepIdForCheckRow(Map<String, Object?> row) =>
    stepIdForCheck(row['step'], jsStr(row['label']));

/// 完整性检查的一行
class WizardCheck {
  const WizardCheck({
    required this.label,
    required this.ok,
    required this.stepId,
    this.detail = '',
  });

  final String label;
  final bool ok;

  /// 该问题所属的步骤 id；null = 无处可跳（不显示「去修复」）
  final String? stepId;
  final String detail;
}

/// 规则层 10 项（经映射）+ 本层 3 项附加检查
List<WizardCheck> wizardChecks(Character c) {
  final out = <WizardCheck>[];
  for (final row in checkList(c)) {
    out.add(
      WizardCheck(
        label: jsStr(row['label']),
        ok: jsTruthy(row['ok']),
        detail: jsStr(row['detail']),
        stepId: stepIdForCheckRow(row),
      ),
    );
  }
  // ---- 本层附加项（规则层不管武器/防具/物品，但完成度检查要看一眼）----
  out.add(
    WizardCheck(
      label: '已添加武器',
      ok: asList(c.raw['weapons']).isNotEmpty,
      detail: '未添加（可留空，跑团时再补）',
      stepId: 'combat',
    ),
  );
  out.add(
    WizardCheck(
      label: '已装备防具',
      ok: asList(c.raw['armors']).isNotEmpty,
      detail: '未装备（可留空）',
      stepId: 'combat',
    ),
  );
  out.add(
    WizardCheck(
      label: '随身物品已填写',
      ok: asList(c.raw['items']).isNotEmpty,
      detail: '背包是空的（可留空）',
      stepId: 'gear',
    ),
  );
  return out;
}
