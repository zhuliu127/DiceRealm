// ============================================================
// wizard_steps.dart — 车卡向导的**步骤注册表**（唯一事实源）
//
// 为什么要有这张表：之前「标题 / 顺序 / 进度条 / 校验 / 末步判定 / 底栏文案」
// 分散在 5 处（`_titles`、IndexedStack 的 children 顺序、`_validateStep` 的
// case、`_lastStep`、`_BottomBar` 里的字面量 `step == 5`）。加一步要改 5 个地方，
// 漏一个就是「进度条 6 段但标题只有 5 个」这种错位。
//
// 现在：**一个 `WizardStep` 列表驱动全部**。加步骤 = 往列表里插一个元素。
//
// ⚠️ 旧版索引 → 新步骤 id 的映射（见 `wizard_checks.dart#stepIdForCheck`）：
//   `lib/domain` 的 `engine.checkList()` 每条结果带 `step: 0..4`，那是**旧版
//   向导**的页序（0 基本资料 / 1 属性 / 2 职业 / 3 信用评级 / 4 技能）。
//   domain 已冻结，所以映射写在 UI 层，并且是纯函数 —— 单测逐条断言
//   「每个出现过的 step 值都映射到一个真实存在、且确实是该问题所属的那一页」。
//
// ⚠️ 顺序不是随便排的：**资产（信用评级）必须排在技能之前**。
//   信用评级占用职业点数，先定信用评级再分技能点，否则职业点算错、
//   `validateCreditRating` 会误报（旧版 `steps-c.js#assets` 的注释写得很清楚）。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/character.dart';
import '../../domain/engine.dart';
import '../../domain/js_compat.dart';
import '../../domain/occupation.dart';
import '../../domain/skillmodel.dart';
import '../attr_meta.dart';
import '../card_edit/assets_logic.dart';
import 'chargen_logic.dart';
import 'steps/step_assets.dart';
import 'steps/step_attrs.dart';
import 'steps/step_background.dart';
import 'steps/step_basics.dart';
import 'steps/step_combat.dart';
import 'steps/step_gear.dart';
import 'steps/step_rules.dart';
import 'steps/step_skills.dart';
import 'steps/step_summary.dart';

/// 一个向导步骤
class WizardStep {
  const WizardStep({
    required this.id,
    required this.title,
    required this.short,
    required this.icon,
    required this.builder,
    required this.validate,
    this.onEnter,
  });

  /// 稳定 id（`assets` / `skills` / `background` …），供跨页跳转与测试使用
  final String id;

  /// 顶部标题（长）
  final String title;

  /// 侧栏 / 紧凑视图用的短名（与旧版 `Steps.*.short` 一致）
  final String short;

  /// 旧版步骤编号（`Steps.*.icon`，1-9），仅用于对齐旧版的展示顺序
  final String icon;

  /// 页面内容
  final Widget Function() builder;

  /// 返回 null 表示可以进入下一步
  final String? Function() validate;

  /// 进入本步之前的准备工作（建技能列表 / 重算派生值等）
  final void Function()? onEnter;
}

// ============================================================
// 校验函数（从原 create_flow_page 的 switch 里逐字搬出来，逻辑一字未改）
// ============================================================

/// 规则系统：无必填
String? validateRules(Character c) => null;

/// 基本资料（含职业）
String? validateBasics(Character c) {
  if (c.characterName.trim().isEmpty) return '请填写角色姓名';
  if (c.playerName.trim().isEmpty) return '请填写玩家名称';
  final age = ageOf(c);
  if (age < 1 || age > 200) return '年龄必须填写为 1-200 的整数';
  if (c.occupationId.isEmpty) return '请选择职业（职业决定本职技能与职业技能点）';
  return null;
}

/// 属性分配
///
/// ★ P7-E：对齐旧版 `app.js#attrBlockReason` 的天命硬拦截。
///   「掷出后不可重掷」是模式语义，但「没掷出 / 没选一组」必须拦住下一步，
///   否则玩家会带着空属性进技能页。购点总上限只在 pointbuy 生效
///   （[checkAttributes] 的 enforceCap），fate 模式不误套。
String? validateAttrs(Character c) {
  if (jsStr(c.raw['attributeMode']) == 'fate') {
    final fate = c.fate;
    final options = asList(fate['options']);
    if (!jsTruthy(fate['rolled']) || options.isEmpty) {
      return '天命还没掷出：先点「掷出天命」';
    }
    final picked = jsParseInt(fate['picked']) ?? -1;
    if (picked < 0 || picked >= options.length) {
      return '请先从 ${options.length} 组天命里选一组';
    }
  }
  final check = checkAttributes(
    c,
    pointBuy: jsStr(c.raw['attributeMode']) == 'pointbuy',
    includeLuck: jsTruthy(c.raw['pbIncludeLuck']),
  );
  // 优先级：先报「填了但不合法」（用户刚输入的值有问题），再报「还没填」，
  // 最后才是总和。否则输入 53 会被说成「还差力量」，很误导。
  final invalid = check.errors.entries
      .where((e) => e.key != '__sum' && e.value != '未填写')
      .toList();
  if (invalid.isNotEmpty) {
    return '${attrName(invalid.first.key)}：${invalid.first.value}';
  }
  if (!check.allCoreFilled) {
    final missing = coreAttrKeys
        .where((k) => attrFieldError(jsStr(c.attributes[k] ?? '')) != null)
        .toList();
    return '请先填完 8 项属性（还差：${missing.map(attrName).join('、')}）';
  }
  final sumError = check.errors['__sum'];
  if (sumError != null) return sumError;
  if (check.over) {
    return '属性总和 ${check.sum} 超出上限 ${check.cap}，请减少 ${check.sum - check.cap} 点';
  }
  return null;
}

/// 资产 / 信用评级：只拦「填了但不合法」，缺省不算错（旧版同款）
String? validateAssets(Character c) {
  final errs = validateCreditRating(c);
  if (errs.isEmpty) return null;
  // `cr == 0`（尚未分配）在旧版是「提示」而非硬拦，这里放行但把文案留给概要页
  final cr = jsNum(c.assets['creditRating']);
  if (cr == 0) return null;
  return jsStr(errs.first['text']);
}

/// 技能（点数与本职勾选）
String? validateSkills(Character c) {
  final reqErr = validateOccupationChoices(c);
  if (reqErr.isNotEmpty) return jsStr(reqErr.first['text']);
  final occ = occupationPoints(c);
  final itr = interestPoints(c);
  if (jsNum(occ['remain']) > 0 && canAbsorbMore(c, 'occ')) {
    return '还有 ${jsNum(occ['remain'])} 点职业技能点未分配';
  }
  if (jsNum(itr['remain']) > 0 && canAbsorbMore(c, 'int')) {
    return '还有 ${jsNum(itr['remain'])} 点兴趣技能点未分配';
  }
  return null;
}

/// 战斗装备 / 随身物品 / 背景：全部非必填
String? validateOptional(Character c) => null;

// ============================================================
// 注册表
// ============================================================

/// 9 步顺序（标题 / 短名 / icon 与旧版 `steps-*.js` 对齐）
class WizardSteps {
  WizardSteps._(this.steps);

  /// 构建注册表。[draft] 与 [onChanged] 由页面持有（状态只在页面里）。
  factory WizardSteps({
    required Character draft,
    required VoidCallback onChanged,
    required void Function(String stepId) onJumpTo,
    Set<String> skipStepIds = const <String>{},
  }) {
    void refresh() {
      recalc(draft);
      syncSkills(draft);
    }

    final steps = <WizardStep>[
      WizardStep(
        id: 'rules',
        title: '规则系统',
        short: '规则',
        icon: '1',
        builder: () => StepRules(draft: draft, onChanged: onChanged),
        validate: () => validateRules(draft),
      ),
      WizardStep(
        id: 'basics',
        title: '基本资料',
        short: '基本',
        icon: '2',
        builder: () => StepBasics(draft: draft, onChanged: onChanged),
        validate: () => validateBasics(draft),
      ),
      WizardStep(
        id: 'attrs',
        title: '属性分配',
        short: '属性',
        icon: '3',
        builder: () => StepAttrs(draft: draft, onChanged: onChanged),
        validate: () => validateAttrs(draft),
        // 进技能 / 资产之前必须把技能列表建起来（母语/闪避的基础值依赖属性），
        // 并补齐职业要求的技能实例，否则技能页看到的是空列表、信用评级也同步不了
        onEnter: () {
          recalc(draft);
          syncSkills(draft);
          materializeOccupationalSkills(draft);
        },
      ),
      WizardStep(
        id: 'assets',
        title: '资产与信用评级',
        short: '资产',
        icon: '4',
        builder: () => StepAssets(draft: draft, onChanged: onChanged),
        validate: () => validateAssets(draft),
        // 先把技能列表 / 派生值准备好，再把「技能页里加过的信用评级」采纳回来
        // （旧版渲染资产页前同样是 syncSkills + syncCreditSkill）
        onEnter: () {
          refresh();
          adoptCreditFromSkill(draft);
        },
      ),
      WizardStep(
        id: 'skills',
        title: '职业技能',
        short: '技能',
        icon: '5',
        builder: () => StepSkills(draft: draft, onChanged: onChanged),
        validate: () => validateSkills(draft),
        onEnter: () {
          recalc(draft);
          syncSkills(draft);
          materializeOccupationalSkills(draft);
        },
      ),
      WizardStep(
        id: 'combat',
        title: '战斗装备',
        short: '战斗',
        icon: '6',
        builder: () => StepCombat(draft: draft, onChanged: onChanged),
        validate: () => validateOptional(draft),
        onEnter: refresh,
      ),
      WizardStep(
        id: 'gear',
        title: '随身物品',
        short: '装备',
        icon: '7',
        builder: () => StepGear(draft: draft, onChanged: onChanged),
        validate: () => validateOptional(draft),
        // 战斗装备（第 6 步）可能刚被改过：此时把「额外分配的战斗技能」
        // 搬回武器对得上的那一门（需求 9）。技能步在战斗步之前，玩家
        // 先一键分配、后挑武器时全靠这一步兜住。
        onEnter: () {
          refresh();
          alignCombatSkillsToWeapons(draft);
        },
      ),
      WizardStep(
        id: 'background',
        title: '角色背景',
        short: '背景',
        icon: '8',
        builder: () => StepBackground(draft: draft, onChanged: onChanged),
        validate: () => validateOptional(draft),
      ),
      WizardStep(
        id: 'summary',
        title: '概要',
        short: '概要',
        icon: '9',
        builder: () => StepSummary(draft: draft, onJumpTo: onJumpTo),
        // 概要页的「下一步」= 保存，校验沿用技能步（与原实现一致）
        validate: () => validateSkills(draft),
        onEnter: () {
          recalc(draft);
          // 保存前最后兜一次：从概要页自由跳转过来时，技能点可能仍是
          // 「没对武器」的旧分配（需求 9）。
          alignCombatSkillsToWeapons(draft);
        },
      ),
    ];
    // ★ P7-C：AI / 随机卡已在生成前选过规则，`_adopt` 进向导时跳过 rules。
    //   过滤后进度条段数、标题、编号、末步判定全部由同一份列表驱动，
    //   不会出现「显示 2/9 但实际首步是规则」这种错位。手动新建卡不传
    //   skipStepIds，仍从规则步开始。
    final active = steps
        .where((WizardStep s) => !skipStepIds.contains(s.id))
        .toList();
    return WizardSteps._(active);
  }

  final List<WizardStep> steps;

  int get length => steps.length;

  List<String> get ids => steps.map((s) => s.id).toList();

  int indexOf(String id) {
    final i = steps.indexWhere((s) => s.id == id);
    return i < 0 ? 0 : i;
  }

  bool has(String id) => steps.any((s) => s.id == id);

  WizardStep at(int index) => steps[index];

  bool isLast(int index) => index == steps.length - 1;

  String titleAt(int index) => steps[index].title;

  /// 底栏主按钮文案：末步是「保存角色卡」
  String primaryLabel(int index) => isLast(index) ? '保存角色卡' : '下一步';

  String? validateAt(int index) => steps[index].validate();

  void runOnEnter(int index) => steps[index].onEnter?.call();

  /// 所有步骤的 id（调试 / 测试用）
  List<String> get debugIds => ids;
}
