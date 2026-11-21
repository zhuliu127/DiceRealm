// ============================================================
// create_flow_page.dart — 新建角色卡向导（9 步，由步骤注册表驱动）
//
// 步骤顺序与旧版 `steps-*.js` 的 icon 编号一致：
//   1 规则系统 → 2 基本资料（含职业）→ 3 属性分配
//   → 4 资产与信用评级 → 5 职业技能 → 6 战斗装备 → 7 随身物品
//   → 8 角色背景 → 9 概要（保存）
//
// ⚠️ 这个页面**不再自己维护步骤顺序 / 标题 / 校验 / 末步判定**：
//   全部来自 `wizard_steps.dart` 的 [WizardSteps] 注册表。加一步只需要往表里
//   插一个元素，不会出现「进度条改成 9 段、标题还是 6 个」这种错位。
//
// 状态**只存在这个页面的 State 里**（不用全局单例）：`_draft` 是一张
// `newCharacter()` 造出来的卡，各步骤直接对它的字段读写；返回上一步不会丢数据，
// 因为所有步骤挂在 IndexedStack 上，各自的输入控件状态也一直活着。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/character.dart';
import '../../domain/engine.dart';
import '../../domain/js_compat.dart';
import '../../domain/rule_registry.dart' show RuleRegistry;
import '../../repo/repo_scope.dart';
import '../art.dart';
import '../responsive.dart';
import '../../theme.dart';
import 'chargen_logic.dart' show eduChecksRemaining;
import 'wizard_steps.dart';
import '../notice.dart';

/// 保存成功后统一回首页（★ P9 需求 8）。
///
/// 所有落库路径（向导末步保存 / AI「就用这张」/ 一键出卡「就用这张」）
/// 都调这一个函数，不各写一套导航。
///
/// 为什么用 `isFirst` 而不是 `ModalRoute.withName(AppRoutes.home)`：
///   · 栈底永远是首页（MaterialApp 的初始路由 `/`）；
///   · 但测试里有「把某页直接当 home 注入」的宿主，那种宿主没有名为 `/`
///     的路由 —— 按名字匹配会一个都匹配不上，`popUntil` 会把栈弹空并抛错。
///   · `isFirst` 在两种宿主里都收敛到「第一页 = 首页」，且绝不会弹空。
void backToHome(NavigatorState navigator) {
  navigator.popUntil((Route<dynamic> route) => route.isFirst);
}

class CreateFlowPage extends StatefulWidget {
  const CreateFlowPage({
    super.key,
    this.initial,
    this.skipRules = false,
    this.initialRuleId,
  });

  /// 测试可以塞一张预置的草稿；正常入口为 null（走 newCharacter）
  final Character? initial;

  /// ★ P7-C：AI 车卡 / 随机卡在生成动作之前已经选过规则系统，
  ///   「继续完善」不该再让玩家选一次。传 true 时注册表过滤掉 rules 步，
  ///   进度条分母与步骤编号同步变成 8 步（首步 = 基本资料）。
  ///   手动新建卡不传（false），仍从规则步开始。`validateRules(draft)`
  ///   在数据层仍然恒为 null（卡上已有规则标记），不受影响。
  final bool skipRules;

  /// ★ P9：规则已由 [RulePickPage] 选好 —— 这里只负责把它写进草稿。
  ///
  /// 写入走的是「第 1 步选规则」**同一条路径**（`draft.raw['ruleSystemId']`，
  /// 见 `steps/step_rules.dart`），不另造字段；取值前先过
  /// [RuleRegistry.effectiveId]，未开放 / 认不出的 id 一律回退默认规则，
  /// 绝不把占位规则写进卡。
  final String? initialRuleId;

  @override
  State<CreateFlowPage> createState() => _CreateFlowPageState();
}

class _CreateFlowPageState extends State<CreateFlowPage> {
  late Character _draft;
  late final WizardSteps _steps;
  int _index = 0;
  String? _stepError;
  bool _saving = false;

  /// ★ P10：本次建卡会话里是否已经提示过「还没做教育进步检定」。
  ///
  /// 用户原话是「要提示玩家」，**不是**「不许走」——所以这里只是提示：
  /// 第一次点「下一步 / 保存」时弹一条带两个动作的 SnackBar，
  /// 页面照常前进（不做硬拦截，玩家不会卡在第 2 步出不去）。
  /// 只记录在页面 State 里（= 一次建卡会话），退出向导重进会重新提示一次。
  bool _eduHintShown = false;

  @override
  void initState() {
    super.initState();
    // ★ P7-D：手动新建卡的规则标记也来自注册表（不散落 'coc7' 字面量）。
    //   newCharacter() 的无参兜底仍在 domain 里，但所有 UI 入口都显式传 id。
    // ★ P9：id 可能是规则选择页带进来的（[CreateFlowPage.initialRuleId]）——
    //   未开放 / 认不出的一律回退默认规则，占位规则绝不写进卡。
    final String ruleId = RuleRegistry.effectiveId(widget.initialRuleId);
    _draft = widget.initial ?? Character(newCharacter(ruleId));
    // 带着一张已有卡进来（AI / 随机卡的「继续完善」）时，规则以**已选为准**：
    // 与 `step_rules.dart` 的写入完全同一条路径，只是玩家不用再点一次。
    if (widget.initial != null && widget.initialRuleId != null) {
      _draft.raw['ruleSystemId'] = ruleId;
    }
    /* 属性模式默认「点数分配」—— 与老产品默认的 random 不同：
       购物点是新玩家的第一直觉，随机掷骰作为可选项放在同一页切换。
       ⚠️ 但**带着一张已经填好的卡进来时不能改**（AI 车卡 / 预设卡都是
       random 掷出来的）：强行改 pointbuy 会让玩家一进向导就被告知
       「点数超标」，等于把刚生成的好卡判成坏卡。 */
    if (widget.initial == null) {
      _draft.raw['attributeMode'] = 'pointbuy';
    }
    if (jsStr(_draft.raw['pbCap']).isEmpty) _draft.raw['pbCap'] = 480;
    _steps = WizardSteps(
      draft: _draft,
      onChanged: _rebuild,
      onJumpTo: _jumpTo,
      skipStepIds: widget.skipRules
          ? const <String>{'rules'}
          : const <String>{},
    );
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // ---------------- 导航（全部由注册表驱动，无 step == N） ----------------

  void _goBack() {
    if (_index <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _index -= 1;
      _stepError = null;
    });
  }

  /// ★ P10：未做「教育进步检定」时给一次提示（**不阻止**前进）。
  ///
  /// 为什么不做硬拦截：用户原话是「要提示玩家」。硬拦会让没打算做检定的
  /// 玩家卡在第 2 步出不去 —— 这条路必须留着，所以只提示、不拦。
  /// 同一次建卡会话内只弹一次（[_eduHintShown]），次数用完则永远不弹。
  ///
  /// [saving] 为真时是「保存」路径：此刻马上就要回首页，所以不给
  /// 「现在去检定」按钮（点了也无处可跳），文案改成「保存后仍可补做」。
  void _maybeHintEduCheck({bool saving = false}) {
    if (_eduHintShown) return;
    // 没有属性步（理论上不会）就无从谈起，别弹没用的提示
    if (!_steps.has('attrs')) return;
    // P11：判据从「一次都没做」改成「**还有剩余次数没做**」——
    // 40 岁能检定 2 次，只做了 1 次也该提醒还剩 1 次。
    final remaining = eduChecksRemaining(_draft);
    if (remaining <= 0) return;
    _eduHintShown = true;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSlot(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              saving
                  ? '还有 $remaining 次教育进步检定没做，教育保持原值。保存后仍可回第 2 步补做，再保存一次即可。'
                  : '还有 $remaining 次教育进步检定没做，教育会保持原值。做完可以提升教育。',
              key: const Key('edu_check_skip_hint'),
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
            if (!saving)
              Row(
                children: <Widget>[
                  TextButton(
                    key: const Key('edu_check_go_roll'),
                    onPressed: () {
                      messenger.hideCurrentSnackBar();
                      _jumpTo('attrs');
                    },
                    child: const Text('现在去检定'),
                  ),
                  TextButton(
                    key: const Key('edu_check_continue'),
                    onPressed: messenger.hideCurrentSnackBar,
                    child: const Text('仍要继续'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _goNext() async {
    final err = _steps.validateAt(_index);
    if (err != null) {
      setState(() => _stepError = err);
      HapticFeedback.selectionClick();
      return;
    }
    if (_steps.isLast(_index)) {
      await _save();
      return;
    }
    // ★ P10：校验通过后先看一眼「教育进步检定做了没有」——只提示，照常前进。
    //   只在**离开属性页**时提示（玩家刚在那一页看到检定区），
    //   否则「基本资料 → 属性」也会弹一次，人还没见到那个按钮就被念一句。
    if (_steps.at(_index).id == 'attrs') _maybeHintEduCheck();
    final next = _index + 1;
    // 进入下一步之前的准备（建技能列表 / 重算派生值），定义在注册表的 onEnter 里
    _steps.runOnEnter(next);
    setState(() {
      _stepError = null;
      _index = next;
    });
  }

  /// 概要页「去修复 →」：跳到该问题所属的步骤
  void _jumpTo(String stepId) {
    if (!mounted) return;
    _jumpToIndex(_steps.indexOf(stepId));
  }

  /// 自由跳转（顶部进度条 / 步骤总览）。
  ///
  /// ★ P8 需求 8：不再只能一路「上一步」往回点。
  ///   **跳转不做校验** —— 玩家常常是带着半成品回去改第 4 步，
  ///   要是跳到目标步先被「请先填完属性」拦住，就等于没修。
  ///   真正把关的是「下一步」与保存：前者校验当前步，后者跑全量校验
  ///   （见 `_save` 的 [_firstInvalidStep]）。
  ///   `IndexedStack` 不做重建，各步的输入控件状态原样保留。
  void _jumpToIndex(int index) {
    if (!mounted) return;
    if (index < 0 || index >= _steps.length || index == _index) return;
    // 目标步的「入场准备」照跑（建技能列表 / 重算派生值 / 同步信用评级）：
    // 这一步只准备数据，不做校验，且全部幂等 —— 不跑的话跳到技能页会看到
    // 一份还没补齐的本职技能列表。
    _steps.runOnEnter(index);
    setState(() {
      _index = index;
      _stepError = null;
    });
  }

  /// 保存前的全量校验：返回第一个不合格的步骤下标，全部合格返回 null。
  ///
  /// 为什么保存要跑全量：允许自由跳转之后，玩家可以「第 1 步 → 直接点第 9 步」
  /// 然后保存；只校验末步会让一张没名字、没属性、没职业的卡落库。
  int? _firstInvalidStep() {
    for (var i = 0; i < _steps.length; i++) {
      if (_steps.validateAt(i) != null) return i;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final bad = _firstInvalidStep();
    if (bad != null) {
      // 不保存，直接把玩家送回那一页并说明原因（一步到位，不用自己找）
      HapticFeedback.selectionClick();
      setState(() {
        _index = bad;
        _stepError = _steps.validateAt(bad);
      });
      return;
    }
    setState(() => _saving = true);
    final repo = RepoScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // ★ P10：保存前也提示一次（未检定 → 不会拦，只告诉玩家还能补做）
    _maybeHintEduCheck(saving: true);
    try {
      // domain 的 uid() 是 8 位随机串。极端情况下可能撞车，
      // 这里兜一道：已存在就换一个 —— 不能让新建覆盖掉一张已有的卡。
      var guard = 0;
      while (repo.get(_draft.id) != null && guard++ < 20) {
        _draft.raw['id'] = uid();
      }
      recalc(_draft);
      await repo.save(_draft);
      if (!mounted) return;
      messenger.showSlot(
        SnackBar(content: Text('已保存「${_draft.characterName}」')),
      );
      // ★ P9 需求 8：无论从哪个入口进的向导（首页 / 规则选择页 / AI 页 /
      //   一键出卡页），保存成功一律回首页 —— 不再只是「返回上一页」，
      //   否则从 AI 页进来会退回到 AI 结果页，用户会以为没存上。
      backToHome(navigator);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- 构建 ----------------

  /// 步骤总览（带名字的跳步菜单）
  ///
  /// 进度条那 9 段只有 4px 高、按宽度平均分，手指点不准；这里给一份
  /// 「1 规则系统 / 2 基本资料 …」的清单，点哪条跳哪条。
  Future<void> _showStepOverview() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  '跳到第几步（可以直接跳，不会被校验拦住）',
                  style: TextStyle(fontSize: 13, color: Palette.textMute),
                ),
              ),
              for (var i = 0; i < _steps.length; i++)
                ListTile(
                  key: Key('step_overview_$i'),
                  dense: true,
                  leading: SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: i == _index ? Palette.goldStr : Palette.textMute,
                      ),
                    ),
                  ),
                  title: Text(
                    _steps.titleAt(i),
                    style: TextStyle(
                      fontSize: 14.5,
                      color: i == _index ? Palette.goldStr : Palette.text,
                      fontWeight: i == _index
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: i == _index
                      ? Icon(Icons.check, size: 16, color: Palette.gold)
                      : null,
                  onTap: () => Navigator.of(sheetCtx).pop(i),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null) _jumpToIndex(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: _goBack,
        ),
        title: Row(
          children: <Widget>[
            Text(_steps.titleAt(_index)),
            const SizedBox(width: 8),
            Text(
              '${_index + 1} / ${_steps.length}',
              key: const Key('step_progress'),
              style: TextStyle(
                fontSize: 12,
                color: Palette.textMute,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          // 9 段细条太窄，光靠它跳步不好点：这里再给一个带名字的总览入口
          IconButton(
            key: const Key('btn_step_overview'),
            tooltip: '步骤总览',
            icon: const Icon(Icons.view_week_outlined, size: 20),
            onPressed: _showStepOverview,
          ),
        ],
      ),
      body: ContentFrame(
        // 平板/横屏：限宽 820。九步表单在 1524dp 上单列会拉成一条细长蛇，
        // 读一行要横扫半个屏幕；限宽后居中，手机（≤760）完全不受影响。
        maxWidth: 820,
        child: Column(
          children: <Widget>[
            // 向导头图。
            //
            // ⚠️ 不用裸 `AspectRatio` —— 3:1 在平板 1524dp 上就是 508px，把下方
            //    表单整块挤出可视区（入口页加头图时踩过同一个坑）。
            // ★ P9：与「一键出卡」页**同一套**：同一个 `Art.wizardHeaderFor`、
            //    同一组 `BannerSlot(aspectRatio: 3, maxHeight: 160, minHeight: 64)`。
            //    两边参数各写一份迟早走偏，改这里请同步 random_create_page。
            SizedBox(
              key: const Key('wizard_header'),
              width: double.infinity,
              child: BannerSlot(
                aspectRatio: 3,
                maxHeight: 160,
                minHeight: 64,
                child: ArtImage(
                  Art.wizardHeaderFor(Palette.brightness),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            _StepBar(step: _index, total: _steps.length, onJump: _jumpToIndex),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: <Widget>[for (final s in _steps.steps) s.builder()],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        error: _stepError,
        step: _index,
        total: _steps.length,
        primaryLabel: _steps.primaryLabel(_index),
        saving: _saving,
        onBack: _goBack,
        onNext: _goNext,
      ),
    );
  }
}

/// 顶部进度条（段数 = 注册表长度）
///
/// ★ P8 需求 8：每一段都能点，点第 N 段就跳到第 N 步。
///   视觉仍是 4px 细条（不给整条加厚），但**点击区**是 28px 高的透明块 ——
///   4px 的目标手指点不到。key 用 0 基下标（与页面里的 `_index` 同源，
///   避免「第 1 步」到底指 0 还是 1 的换算 bug）：`step_jump_0` … `step_jump_8`。
class _StepBar extends StatelessWidget {
  const _StepBar({
    required this.step,
    required this.total,
    required this.onJump,
  });

  final int step;
  final int total;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < total; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: SizedBox(
                height: 28,
                child: InkWell(
                  key: Key('step_jump_$i'),
                  borderRadius: BorderRadius.circular(2),
                  onTap: () => onJump(i),
                  child: Center(
                    child: Builder(
                      builder: (BuildContext _) {
                        final bool done = i <= step;
                        return Container(
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: done ? null : Palette.surface3,
                            gradient: done
                                ? LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: <Color>[
                                      Palette.gold,
                                      Palette.goldStr,
                                    ],
                                  )
                                : null,
                            boxShadow: done
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: Palette.gold.withValues(
                                        alpha: 0.40,
                                      ),
                                      blurRadius: 6,
                                      spreadRadius: 0.4,
                                    ),
                                  ]
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.error,
    required this.step,
    required this.total,
    required this.primaryLabel,
    required this.saving,
    required this.onBack,
    required this.onNext,
  });

  final String? error;
  final int step;
  final int total;

  /// 「下一步」/「保存角色卡」—— 由注册表按「是不是末步」给出
  final String primaryLabel;
  final bool saving;
  final VoidCallback onBack;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Palette.bg,
        border: Border(top: BorderSide(color: Palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.error_outline,
                        size: 15,
                        color: Palette.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error!,
                          key: const Key('step_error'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Palette.danger,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: <Widget>[
                  if (step > 0)
                    OutlinedButton(
                      key: const Key('btn_prev'),
                      onPressed: saving ? null : onBack,
                      child: const Text('上一步'),
                    )
                  else
                    OutlinedButton(
                      key: const Key('btn_cancel'),
                      onPressed: saving ? null : onBack,
                      child: const Text('取消'),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('btn_next'),
                    onPressed: saving ? null : () => onNext(),
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF1A1408),
                            ),
                          )
                        : Text(primaryLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
