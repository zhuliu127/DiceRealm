// ============================================================
// random_create_page.dart — 🎲 一键出卡（纯本地随机，不联网、不碰 AI）
//
// 用户原话：「首页『一键出卡』点进去，让里面只有随机 5 张卡的功能
// （这个页面不要 ai 车卡功能），这个页面在右下角一直悬浮一个重新随机一次的
// 按钮，点击后直接重新随机 5 张卡出来。」
//
// 所以本页只有三样东西：页头图 / 5 张候选卡 / 右下角常驻「重新随机」。
// 没有任何 AI 输入框、没有世界设定、没有上限档位 —— 那些都在 AI 页。
//
// 生成逻辑**复用规则层的 `preset.generate`**（不在 UI 里自造随机）：
// 属性、职业点、技能分配、装备与背景全部由引擎算完并自检，
// 出的一定是能直接跑团的完整卡。规则取值走注册表默认规则，
// 卡面自带 `summary_rule_badge` 标出规则简称，不隐瞒用的是哪套规则。
//
// ⚠️ 候选卡只存在内存里 —— 点「用这张」才进向导，进向导后才落库。
//    反复点「重新随机」不会留下垃圾数据。
//
// ★ 素材 TODO（本批**不生成图**，先用系统图标 / 现有图顶上）：
//   · 悬浮按钮图标：`Icons.casino` 占位。
//     待出图规格：1:1 骰子/重掷图标，256×256 PNG（透明底），
//     暗色版 + 亮色版各一张（亮色版线条更深，压在象牙底上才看得清）。
//     落位后替换 [Icons.casino]，路径建议 `assets/images/icons/general/reroll_1x1.png`
//     并加 `Art.icon('reroll')`。
//   · 页头图：本批复用 `Art.wizardHeaderFor(brightness)`（3:1），
//     待出图规格：单独一张「一键出卡」页头 3:1（1440×480），暗/亮各一，
//     中央留出文字安全区（左侧 40% 不放主体插画）。
// ============================================================

import 'package:flutter/material.dart';

import '../domain/character.dart';
import '../domain/engine.dart' show recalc;
import '../domain/js_compat.dart';
import '../domain/preset_gen.dart' as preset;
import '../domain/rule_registry.dart' show RuleRegistry;
import '../repo/repo_scope.dart' show RepoScope;
import '../theme.dart';
import 'art.dart';
import 'create/create_flow_page.dart';
import 'summary_card.dart';
import 'widgets.dart';
import 'widgets/avatar_picker.dart';
import 'responsive.dart';

/// 一次随机出几张（写死 5：用户要求「随机 5 张」，也是个可点的量）
const int kRandomBatchSize = 5;

class RandomCreatePage extends StatefulWidget {
  const RandomCreatePage({super.key, this.generate, this.initialRuleId});

  /// 路由名（同 [RosterPage.route]：新路由常量跟着页面走）
  static const String route = '/random';

  /// 测试注入用：返回一批完整角色卡；null → 走 `preset.generate`。
  final List<Character> Function()? generate;

  /// ★ P9：规则由 [RulePickPage] 选好再进来（不再用「默认规则」兜底猜）。
  ///   null 时仍走 [RuleRegistry.defaultRule]，兼容老入口与既有用例。
  ///   取值一律过 [RuleRegistry.effectiveId]：未开放 / 认不出的 id 回退默认。
  final String? initialRuleId;

  @override
  State<RandomCreatePage> createState() => _RandomCreatePageState();
}

class _RandomCreatePageState extends State<RandomCreatePage> {
  List<Character> _cards = const <Character>[];
  int _batch = 0;

  /* ---- P10：生成前可先选头像 ---- */
  String? _avatarRel;

  /// 本页一次会话内的临时图片 id（整批候选共用同一张图，语义正确）
  final String _avatarId = uid();

  /// 每张卡原本的「系统自动头像」，用户清除自定义头像时还原
  final Map<Character, String> _autoAvatar = <Character, String>{};

  /// 本页这一批卡统一用的规则 id（生成与文案同源，不各算一次）
  String get _ruleId => RuleRegistry.effectiveId(widget.initialRuleId);

  @override
  void initState() {
    super.initState();
    // 首屏直接出一批（纯 CPU 计算，没有异步），所以不需要 loading 态
    _cards = _buildBatch();
    _batch = 1;
    _applyAvatar();
  }

  /// 让每张候选卡带上当前选的头像；没选则还原成系统自动头像。
  void _applyAvatar() {
    for (final c in _cards) {
      final auto = _autoAvatar.putIfAbsent(c, () {
        final raw = c.raw['avatar'];
        return raw is String ? raw : '';
      });
      c.raw['avatar'] = _avatarRel ?? auto;
    }
  }

  void _setAvatar(String? rel) {
    setState(() {
      _avatarRel = rel;
      _applyAvatar();
    });
  }

  /// 现算一批。纯本地计算，无异步、无 I/O。
  List<Character> _buildBatch() {
    final injected = widget.generate;
    if (injected != null) return injected();
    return preset.generate(
      kRandomBatchSize,
      preset.PresetOptions(ruleSystemId: _ruleId),
    );
  }

  /// 重新随机一批（悬浮按钮点一次就走这里）
  void _reroll() {
    setState(() {
      _batch++;
      _cards = _buildBatch();
      // 换了一批 = 新对象，头像要重新贴上去（玩家选的那张继续生效）
      _applyAvatar();
    });
  }

  /// 追加一条改动日志（两个按钮共用）
  void _logAdopt(Character c, String note) {
    final log = asList(c.raw['changeLog']);
    log.add(<String, Object?>{
      'version': 'v1.0',
      'note': note,
      'at': nowMillis(),
    });
    c.raw['changeLog'] = log;
  }

  /// ★ P9 需求 6：「继续完善」—— 进向导改，**不保存**。
  /// （规则已在生成时选好，跳过 rules 步）
  void _adopt(Character c) {
    _logAdopt(c, '一键出卡：采用随机预设卡');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateFlowPage(initial: c, skipRules: true),
      ),
    );
  }

  /// ★ P9 需求 6/8：「就用这张」—— 直接落库，然后回首页。
  ///
  /// 落库与向导末步保存同一套（`recalc` → `repo.save`），id 撞车时换一个，
  /// 绝不覆盖已有卡。
  Future<void> _useThis(Character c) async {
    final repo = RepoScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _logAdopt(c, '一键出卡：直接采用随机预设卡');
    var guard = 0;
    while (repo.get(c.id) != null && guard++ < 20) {
      c.raw['id'] = uid();
    }
    recalc(c);
    await repo.save(c);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('已保存「${c.characterName}」')),
    );
    backToHome(navigator);
  }

  @override
  Widget build(BuildContext context) {
    dependOnTheme(context);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.casino_outlined, size: 18, color: Palette.goldStr),
              const SizedBox(width: 6),
              const Text(
                '一键出卡',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          // Stack：列表在下、右下角常驻悬浮按钮在上 —— 按钮一直悬浮，
          // 不随列表滚走（用户要求「右下角一直悬浮」）。
          child: Stack(
            children: <Widget>[
              // 用 SingleChildScrollView + Column 而不是 ListView：
              // 这一页永远只有 5 张卡，全量构建换来「所见即所得」——
              // 不会出现「第 5 张还没被懒构建」导致的点击/滚动异常。
              SingleChildScrollView(
                // 底部留 96：最后一张卡不会被悬浮按钮压住
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 页头图。
                    //
                    // ★ P9：与「按流程车卡」向导页**同一套** —— 同一个
                    //   `Art.wizardHeaderFor`、同一组
                    //   `BannerSlot(aspectRatio: 3, maxHeight: 160, minHeight: 64)`。
                    //   以前这里是裸 `AspectRatio(3)`，宽屏上会和向导页差出一大截，
                    //   两页看起来「一个扁一个厚」。改这里请同步 create_flow_page。
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.md),
                      child: SizedBox(
                        key: const Key('random_header'),
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
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '纯本地随机，不联网、不花钱。一次出 $kRandomBatchSize 张完整卡：'
                      '属性、职业点、技能、装备与背景都已按规则算好并通过自检，'
                      '挑一张就能直接开跑。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Palette.textMute,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // ★ P9：规则在上一页选好了，这里只如实回报「这一批按哪套算」。
                    Text(
                      '本次规则：${RuleRegistry.resolve(_ruleId).shortName}'
                      ' · ${RuleRegistry.resolve(_ruleId).rulebook}',
                      key: const Key('random_rule_current'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Palette.textDim,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ★ P10：生成（随机）之前就能选头像 —— 这一批卡都带上它。
                    //   「重新随机」换的是属性 / 职业 / 背景，头像不动。
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Palette.surface2,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(color: Palette.border),
                      ),
                      child: AvatarPicker(
                        keyPrefix: 'random_avatar',
                        value: _avatarRel,
                        name: _cards.isEmpty ? '' : _cards.first.characterName,
                        cardId: _avatarId,
                        label: '角色头像',
                        hint: '先选一张图，这一批候选卡都会带上它',
                        onChanged: _setAvatar,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Text(
                          '第 $_batch 批 · ${_cards.length} 张候选',
                          key: const Key('random_batch_label'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Palette.text,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '未选中的不保存',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Palette.textMute,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_cards.isEmpty)
                       EmptyState(
                        emoji: '🎲',
                        icon: Icons.casino_outlined,
                        title: '这次没能生成，点右下角再试一次',
                      )
                    else
                      for (var i = 0; i < _cards.length; i++) ...<Widget>[
                        SummaryCard(
                          summary: preset.summaryOf(_cards[i]),
                          index: i,
                          key: Key('random_candidate_$i'),
                          // ★ P9 需求 6：一张卡两个动作 —— 直接存 / 进向导改。
                          keySuffix: '_$i',
                          onUseThis: () => _useThis(_cards[i]),
                          onContinueEdit: () => _adopt(_cards[i]),
                        ),
                        const SizedBox(height: 10),
                      ],
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '不满意就点右下角「重新随机」，换一批全新的。',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Palette.textMute,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  key: const Key('random_reroll'),
                  onPressed: _reroll,
                  backgroundColor: Palette.gold,
                  foregroundColor: Palette.onGold,
                  icon: const Icon(Icons.casino, size: 20),
                  label: const Text(
                    '重新随机',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
