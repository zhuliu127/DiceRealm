// ============================================================
// rule_registry.dart — 规则系统元信息的**单一可查找真源**（纯 Dart）
//
// 存在理由：
//   · `step_rules.dart` 的文件头注释提到 `RuleRegistry.placeholders`，但
//     此前 domain 里并没有这份定义 —— UI 只好把占位项文案硬编码在页面里。
//   · 卡片上的 `ruleSystemId` 需要一个「id → 名称 / 简称 / 规则书」的查表口，
//     否则 UI 里会散落 `if (id == 'coc7')` 这种第二套实现。
//   · 以后加规则只需在 [RuleRegistry.all] 注册一条，UI 自动生成选择项与徽标。
//
// ★ 本文件保持 domain 纯度：只依赖同层规则定义，不引入框架、平台或渲染库。
// ★ COC7 的全部元信息取自 [Coc7]（rules_coc7.dart:867-874），本文件只做
//   聚合与查找，绝不复制字面量。占位项如实标注 available=false「未开放」。
// ============================================================

import 'rules_coc7.dart' show Coc7;

/// 一条规则系统的元信息。
class RuleMeta {
  const RuleMeta({
    required this.id,
    required this.name,
    required this.shortName,
    required this.rulebook,
    required this.available,
    this.description = '',
  });

  /// 稳定 id，写进角色卡 `raw['ruleSystemId']`。
  final String id;

  /// 全名（规则选择卡片标题）。
  final String name;

  /// 简称（卡面 / 卡列表 / 详情的规则徽标，例如 `COC 7th`）。
  final String shortName;

  /// 规则书名称（卡片副标题）。
  final String rulebook;

  /// 规则层是否已实现。**false = 未开放**，UI 必须如实展示且不可选。
  final bool available;

  /// 一段说明（规则选择卡片正文）。
  final String description;

  bool get isPlaceholder => !available;
}

/// 规则注册表。
///
/// [defaultRule] 是「没指定 / id 认不出」时的兜底，来自 [Coc7]，
/// 这样生成路径不需要写死 `'coc7'` 字面量。
class RuleRegistry {
  const RuleRegistry._();

  static const RuleMeta coc7 = RuleMeta(
    id: Coc7.id,
    name: Coc7.name,
    shortName: Coc7.shortName,
    rulebook: Coc7.rulebook,
    available: Coc7.available,
    description: Coc7.description,
  );

  static const RuleMeta dnd5e = RuleMeta(
    id: 'dnd5e',
    name: '龙与地下城 第五版',
    shortName: 'DND 5E',
    rulebook: '占位项 · 规则层尚未实现',
    available: false,
    description: '另一套经典的奇幻跑团规则。占位项，规则层尚未实现。',
  );

  static const RuleMeta custom = RuleMeta(
    id: 'custom',
    name: '自定义规则',
    shortName: '自定义',
    rulebook: '占位项 · 规则层尚未实现',
    available: false,
    description: '由守秘人自行约定的属性与技能体系。占位项，规则层尚未实现。',
  );

  /// 全部注册项（已实现 + 未开放）。
  static const List<RuleMeta> all = <RuleMeta>[coc7, dnd5e, custom];

  /// 未开放占位项（`step_rules.dart` 里如实展示为「敬请期待」）。
  static const List<RuleMeta> placeholders = <RuleMeta>[dnd5e, custom];

  /// 已开放、真正可选的规则。
  static const List<RuleMeta> availableRules = <RuleMeta>[coc7];

  static RuleMeta get defaultRule => coc7;

  /// 按 id 精确查找；认不出返回 null（**不**悄悄回退默认）。
  static RuleMeta? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 查不到（或 id 为空）时回退 [defaultRule] —— 显示用，不会报错。
  static RuleMeta resolve(String? id) => byId(id) ?? defaultRule;

  /// 显示用：任意 id → 简称。
  static String shortNameOf(String? id) => resolve(id).shortName;

  /// 生成用：任意 id → **已开放**规则的 id。
  ///
  /// 未开放项 / 认不出的 id 一律回退 [defaultRule]，绝不让占位规则写进卡。
  static String effectiveId(String? id) {
    final r = byId(id);
    return (r != null && r.available) ? r.id : defaultRule.id;
  }

  /// 该 id 是否是已开放规则。
  static bool isAvailable(String? id) {
    final r = byId(id);
    return r != null && r.available;
  }
}
