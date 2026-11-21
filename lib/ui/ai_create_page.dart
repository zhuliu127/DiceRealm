// ============================================================
// ai_create_page.dart — ✨ AI 车卡
//
// 对齐旧版 `ui/step-start.js`（向导第 0 步）+ `openAIPanel()`。
//
// ★ P8：本页**只留 AI 车卡**（用户原话「让里面只有 ai 车卡的功能」）。
//   原先页内还嵌着「随机 5 张候选」一整套 UI（生成 / 换一批 / 采用），
//   和 AI 产出混在两个列表里，用户分不清在看哪一类结果。现在：
//     · 随机 5 张整体搬到独立页面 [RandomCreatePage]（路由 /random）；
//     · 本页只保留一个「一键出卡」入口按钮 + 一段「不想用 AI？」说明；
//     · AI 失败时的兜底也从「就地出 5 张卡」改成「跳到一键出卡页」——
//       兜底必须真的能拿到卡，且不把两种产出混在同一页。
//
// 四条硬要求（照旧版踩过的坑）：
//   1. **生成中要可取消、要有进度感**：显示已用秒数 + AI 层的阶段消息
//      （「正在用更大额度重试…」），不做成转圈干等；
//   2. **失败必须能回退**：AI 不可用 / Key 没填 / 超时 → 一键「改用一键出卡」，
//      真的能拿到卡（进随机页出 5 张），不是只弹个提示；
//   3. **未配置时给引导而不是报错**：默认值已经是 DeepSeek 地址，通常只补 Key；
//   4. **上限是「每项的天花板」不是「点数池」**：文案必须说清（旧版踩过）。
//
// ★ P7 真机反馈批次（B/C/D）：
//   · B 本页直接可填「属性总和上限 / 含幸运 / 本职上限 / 兴趣上限」，
//     0 或留空 = 不限；三档快捷保留，填了自定义值后显示「自定义」态
//     （三档都不选中），绝不把自定义伪装成「标准」。
//     保存走 [AiCapsSavePort]（同步 void + unawaited），widget 里零 await，
//     fake-async 下不会因真实文件 I/O 挂死。
//   · C 生成动作**之前**先选规则系统；生成时把所选规则传给 AI 生成链
//     并写进卡上的 `ruleSystemId`；「继续完善」进 [CreateFlowPage] 时跳过
//     rules 步，进度分母自洽。
//   · D 规则元信息单一真源 = `RuleRegistry`（domain，零 Flutter），
//     未开放项如实展示「未开放」且不可选。
// ============================================================

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'art.dart';
import '../domain/ai_caps.dart';
import '../domain/ai_gen.dart';
import '../domain/character.dart';
import '../domain/engine.dart' show recalc;
import '../domain/js_compat.dart';
import '../domain/personas.dart' as per;
import '../domain/preset_gen.dart' as preset;
import '../domain/rule_registry.dart' show RuleRegistry;
import '../net/ai_client.dart';
import '../net/ai_create.dart';
import '../repo/repo_scope.dart';
import '../repo/settings_repo.dart';
import '../theme.dart';
import 'create/create_flow_page.dart';
import 'random_create_page.dart';
import 'summary_card.dart';
import 'widgets.dart';
import 'widgets/avatar_picker.dart';

/* ============================================================
 * 可注入的生成入口（widget 测试用假实现，不联网）
 * ============================================================ */

/// 一次生成请求
class AiGenerateRequest {
  const AiGenerateRequest({
    required this.desc,
    this.settingId,
    required this.caps,
    this.ruleSystemId,
  });
  final String desc;
  final String? settingId;
  final AiCaps caps;

  /// ★ P7-C：生成前所选的规则系统 id（写进结果卡 `ruleSystemId`）。
  final String? ruleSystemId;
}

/// 生成函数：desc → 一张卡（[onStage] 给界面显示阶段消息）
typedef AiGenerate = Future<AiCreateResult> Function(
  AiGenerateRequest req,
  void Function(String message) onStage,
);

/* ============================================================
 * 房规数值设置的可注入保存端口（P7-B）
 *
 * 方法刻意同步返回 void：真实 `SettingsRepo.save()` 内部是异步文件 I/O，
 * 在 fake-async 的 widget 测试里 `await` 会永不完成（铁律 T1）。
 * 这里「先同步写内存 + 上屏反馈，再 unawaited 发起落盘」，与
 * `sheet_history_export.dart` 的 RoomHistoryExportPort 同一套路。
 * ============================================================ */

abstract class AiCapsSavePort {
  const AiCapsSavePort();

  /// 同步发起保存；不等待、不改可见反馈。
  void save();
}

/// 一个上限输入框的解析结果（纯数据）。
class CapsInputResult {
  const CapsInputResult({required this.value, required this.error});

  /// null = 非法，调用方**不得写入设置**。
  final int? value;

  /// 给玩家看的可见提示（合法时为空串）。
  final String error;

  bool get ok => value != null;
}

/// 解析一个上限输入框（纯函数，UI 与单测共用同一套判据）。
///
/// 0 / 留空 = 不限；负数、非数字、超范围一律拒收并返回可见提示。
/// 输入框另有 `digitsOnly` + 4 位长度限制做前置过滤，本函数是第二道闸门：
/// 即使以后换了输入控件 / 从别处灌值，也绝不把非法值写进设置。
CapsInputResult parseAiCapInput(String raw, String label) {
  final t = raw.trim();
  if (t.isEmpty) return const CapsInputResult(value: 0, error: '');
  final v = int.tryParse(t);
  if (v == null || v < 0 || v > 9999) {
    return CapsInputResult(
      value: null,
      error: '$label 只能填 0-9999 的整数（0 / 留空 = 不限）',
    );
  }
  return CapsInputResult(value: v, error: '');
}

/// 生产实现：把设置仓库的落盘动作包成「发起即返回」。
class SettingsRepoCapsSavePort implements AiCapsSavePort {
  const SettingsRepoCapsSavePort(this.repo);

  final SettingsRepo repo;

  @override
  void save() => unawaited(repo.save());
}

/// 真正的实现：AiClient + AiCreateService
class LiveAiRunner {
  LiveAiRunner(this._settings) {
    _client = AiClient(
      configProvider: () => AiConfig(
        base: _settings.aiBase,
        model: _settings.aiModel,
        key: _settings.aiKey,
      ),
    );
    _service = AiCreateService(
      client: _client,
      capsProvider: () => capsFromSettings(_settings.settings),
    );
  }

  final SettingsRepo _settings;
  late final AiClient _client;
  late final AiCreateService _service;

  Future<AiCreateResult> generate(
    AiGenerateRequest req,
    void Function(String) onStage,
  ) async {
    final r = await _service.makeCharacter(
      req.desc,
      settingId: req.settingId,
      caps: req.caps,
      onStage: onStage,
    );
    // ★ P7-C/D：net 层不改，规则标记在 UI 落地后盖上（值来自生成前所选规则）。
    final rid = req.ruleSystemId;
    if (rid != null && rid.isNotEmpty) {
      r.character.raw['ruleSystemId'] = RuleRegistry.effectiveId(rid);
    }
    return r;
  }

  void cancel() => _service.cancel();
}

class AiCreatePage extends StatefulWidget {
  const AiCreatePage({
    super.key,
    this.generate,
    this.onCancel,
    this.capsSavePort,
    this.initialRuleSystemId,
    this.initialRuleId,
  });

  /// 测试注入用；null → 走真实的 AI 客户端
  final AiGenerate? generate;

  /// 测试注入用；null → 走 LiveAiRunner.cancel
  final VoidCallback? onCancel;

  /// ★ P7-B：测试可注入同步替身；null → [SettingsRepoCapsSavePort]。
  final AiCapsSavePort? capsSavePort;

  /// ★ P7-C：初始规则选择。null（默认）= 已选默认规则；
  /// 传空串可模拟「未选」，用于验证「未选规则时无法生成」。
  ///
  /// ★ P9：规则已前移到 [RulePickPage]，本页改为**接收**选好的规则
  ///   （用 [initialRuleId]）。这个旧参数保留只为兼容老入口与既有用例，
  ///   两者都传时 [initialRuleId] 优先。
  final String? initialRuleSystemId;

  /// ★ P9：从规则选择页带进来的规则 id。
  ///
  /// 有值时：本页**不再渲染规则选择芯片**，只显示一条只读的「当前规则」；
  /// 为 null / 空串时：保留旧的芯片选择行为（兼容从其它入口直接进本页）。
  final String? initialRuleId;

  @override
  State<AiCreatePage> createState() => _AiCreatePageState();
}

class _AiCreatePageState extends State<AiCreatePage> {
  final _desc = TextEditingController();

  LiveAiRunner? _live;
  String? _settingId; // null = 自动（按描述判断）
  bool _busy = false;
  String _stage = '';
  DateTime? _startedAt;
  int _elapsed = 0;
  String _error = '';
  AiCreateResult? _result;
  String _capNote = '';

  /* ---- P7-C：生成前所选规则 ---- */
  late String? _selectedRuleId;

  /* ---- P10：生成前可先选头像 ---- */
  ///
  /// 先选图、后出卡：文件按本页自己的临时 id 落盘，生成结果直接引用这个
  /// 相对路径（`raw['avatar']`），「就用这张 / 继续完善」都带着它走。
  String? _avatarRel;

  /// 本页一次会话内的临时图片 id（同一页反复生成都指同一张图，语义正确）
  final String _avatarId = uid();

  /// 结果卡上一张「系统自动头像」（用户清除自定义头像时还原回去）
  String _resultAutoAvatar = '';

  /* ---- P7-B：自定义房规数值输入 ---- */
  late TextEditingController _capAttr;
  late TextEditingController _capOcc;
  late TextEditingController _capInt;
  bool _capsCtlInit = false;
  bool _withLuck = true;
  String _capsError = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRuleId ?? widget.initialRuleSystemId;
    _selectedRuleId = initial ?? RuleRegistry.defaultRule.id;
  }

  @override
  void dispose() {
    _desc.dispose();
    if (_capsCtlInit) {
      _capAttr.dispose();
      _capOcc.dispose();
      _capInt.dispose();
    }
    super.dispose();
  }

  SettingsRepo get _settings => SettingsScope.read(context);

  AiCapsSavePort get _capsSavePort =>
      widget.capsSavePort ?? SettingsRepoCapsSavePort(_settings);

  bool get _ruleSelected => RuleRegistry.isAvailable(_selectedRuleId);

  /// ★ P9：规则是否「上游已选定」（来自 [RulePickPage]）。
  ///
  /// 为 true 时本页只显示一条只读的当前规则 —— 规则这时是一个**前置条件**，
  /// 不是本页的一个选项；再摆一排芯片会让人以为能改，改了却和卡上写的不一致。
  bool get _ruleLocked {
    final String? fromPicker = widget.initialRuleId ?? widget.initialRuleSystemId;
    return fromPicker != null && fromPicker.isNotEmpty;
  }

  /// ★ P7-C / K7：未选规则时**生成入口**不放假按钮。
  ///   AI 生成按钮置 null，重试入口同步停用，并在规则卡片与按钮下方给
  ///   明确引导（不宣称成功）。
  ///
  /// ★ P8：「一键出卡」是**页面跳转**而不是"生成动作"，随机页自带默认规则，
  ///   所以不受这里的规则门禁影响（跳转永远可用，跳过去一定出得了卡）。
  bool get _canStart => _ruleSelected;

  AiGenerate get _generate {
    final injected = widget.generate;
    if (injected != null) return injected;
    _live ??= LiveAiRunner(_settings);
    return _live!.generate;
  }

  /// controller 延迟到 build 里初始化：InheritedWidget 此时一定可用。
  void _ensureCapsControllers(SettingsRepo settings) {
    if (_capsCtlInit) return;
    _capsCtlInit = true;
    _capAttr = TextEditingController(text: _numText(settings.aiAttrCap));
    _capOcc = TextEditingController(text: _numText(settings.aiOccPtsCap));
    _capInt = TextEditingController(text: _numText(settings.aiIntPtsCap));
    _withLuck = settings.aiAttrCapWithLuck;
  }

  static String _numText(int v) => v > 0 ? '$v' : '';

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Palette.danger : null,
      ),
    );
  }

  /// 选 / 清头像：同步到当前结果卡（还没出卡时只记在页面上）。
  void _setAvatar(String? rel) {
    setState(() => _avatarRel = rel);
    final r = _result;
    if (r != null) {
      r.character.raw['avatar'] = rel ?? _resultAutoAvatar;
    }
  }

  /* ---------------- AI 生成 ---------------- */
  Future<void> _runAi() async {
    // ★ P7-C：未选规则不许生成（K7：不放假按钮、不宣称成功）。
    if (!_ruleSelected) {
      _toast('请先选择一套规则系统，再生成角色卡', error: true);
      return;
    }
    final text = _desc.text.trim();
    if (text.isEmpty) {
      _toast('先写一句描述，或者点下面的示例', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
      _result = null;
      _stage = '';
      _capNote = '';
      _startedAt = DateTime.now();
      _elapsed = 0;
    });
    // ★ P7-B：每次生成现读设置 —— 刚填的自定义上限立刻生效。
    final caps = capsFromSettings(_settings.settings);

    // 每秒刷新「已用 N 秒」—— 旧版的进度感就靠这个，不能只转圈
    final ticker = Stream<void>.periodic(const Duration(seconds: 1))
        .listen((_) {
          if (!mounted || !_busy || _startedAt == null) return;
          setState(
            () => _elapsed = DateTime.now().difference(_startedAt!).inSeconds,
          );
        });

    try {
      final r = await _generate(
        AiGenerateRequest(
          desc: text,
          settingId: _settingId,
          caps: caps,
          ruleSystemId: _selectedRuleId,
        ),
        (msg) {
          if (mounted) setState(() => _stage = msg);
        },
      );
      if (!mounted) return;
      // ★ P7-D：所选规则写进卡（假生成实现也覆盖）。
      r.character.raw['ruleSystemId'] = RuleRegistry.effectiveId(
        _selectedRuleId,
      );
      // ★ P10：生成前选的头像跟着这张卡走（没选就不动系统的自动头像）。
      final autoAvatar = r.character.raw['avatar'];
      _resultAutoAvatar = autoAvatar is String ? autoAvatar : '';
      if (_avatarRel != null) r.character.raw['avatar'] = _avatarRel;
      setState(() {
        _busy = false;
        _result = r;
        _capNote = _buildCapNote(r, caps);
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    } finally {
      await ticker.cancel();
    }
  }

  /// 「上限到底起没起作用」必须说清 —— 静默生效的话，看到数值被压会以为生成错了
  String _buildCapNote(AiCreateResult r, AiCaps caps) {
    if (!caps.active) return '';
    var note = '已按上限生成：${caps.text}';
    if (r.attrScaled) note += '　（模型给的属性超了，已按比例压缩）';
    if (caps.occCap > 0 || caps.intCap > 0) {
      note += '。技能上限只压**每一项能到的最大值**，不减少点数总额。';
    }
    return note;
  }

  void _cancel() {
    final injected = widget.onCancel;
    if (injected != null) {
      injected();
    } else {
      _live?.cancel();
    }
  }

  /* ---------------- 采用一张卡 ---------------- */

  /// 追加一条改动日志（「就用这张」与「继续完善」共用，只有 note 不同）。
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
  void _adopt(Character c, String note) {
    _logAdopt(c, note);
    // ★ P7-C：生成前已经选过规则，进向导时跳过 rules 步
    //   （进度条 / 步骤编号由注册表同步变成 8 步，首步 = 基本资料）。
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateFlowPage(initial: c, skipRules: true),
      ),
    );
  }

  /// ★ P9 需求 6/8：「就用这张」—— 直接落库，然后回首页。
  ///
  /// 落库路径与向导末步保存**同一套**（`recalc` → `repo.save` → 提示），
  /// 不另写一份仓库写入；id 撞车时同样换一个，绝不覆盖已有卡。
  Future<void> _useThis(Character c, String note) async {
    final repo = RepoScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _logAdopt(c, note);
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
    final settings = SettingsScope.of(context);
    _ensureCapsControllers(settings);
    final caps = capsFromSettings(settings.settings);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.auto_awesome, size: 18, color: Palette.goldStr),
              const SizedBox(width: 6),
              const Text(
                'AI 车卡',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              /* ★ P9 追加：AI 车卡页的头图（与向导页同一套「书桌 / 羽毛笔」素材）。
                 **固定 64px、不用 AspectRatio** —— 3:1 在平板 1524dp 上会吃掉
                 200+ px，把首屏的「规则系统」和输入框挤出可视区（向导入口页踩过
                 两次同样的坑，见 create_flow_page 里的注释）。 */
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: SizedBox(
                  key: const Key('ai_header'),
                  height: 64,
                  width: double.infinity,
                  child: ArtImage(
                    Art.wizardHeaderFor(Palette.brightness),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                  children: <Widget>[
                    // ★ P7-C：规则选择放在最上面，未配置 AI 时也能看到 / 选好。
                    _ruleCard(),
                    const SizedBox(height: 12),
                    if (!settings.aiConfigured &&
                        widget.generate == null) ...<Widget>[
                      _configCard(settings),
                      const SizedBox(height: 12),
                    ] else ...<Widget>[
                      _inputCard(caps),
                      const SizedBox(height: 12),
                    ],
                    if (_busy) ...<Widget>[_busyCard()],
                    if (_error.isNotEmpty) ...<Widget>[
                      _errorCard(),
                      const SizedBox(height: 12),
                    ],
                    if (_result != null) ...<Widget>[
                      _resultCard(_result!, caps),
                      const SizedBox(height: 12),
                    ],
                    _howItWorks(),
                    const SizedBox(height: 12),
                    _noAiCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------------- ⓪ 生成前选规则（P7-C / P9） ---------------- */

  Widget _ruleCard() {
    // ★ P9：规则由上一页（规则选择页）定好了 —— 这里只**告知**，不给改。
    if (_ruleLocked) {
      final rule = RuleRegistry.resolve(_selectedRuleId);
      return SectionCard(
        title: '规则系统',
        subtitle: '已在上一步选定；建卡过程中不再更改',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '规则：${rule.shortName} · ${rule.rulebook}',
              key: const Key('ai_rule_current'),
              style: TextStyle(
                fontSize: 12.5,
                color: Palette.text,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              rule.description,
              style: TextStyle(
                fontSize: 11.5,
                color: Palette.textMute,
                height: 1.65,
              ),
            ),
          ],
        ),
      );
    }

    final chosen = _selectedRuleId;
    return SectionCard(
      title: '规则系统',
      subtitle: '生成前先选好；「继续完善」时不会再让你选一次',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              for (final r in RuleRegistry.all)
                ChoiceChip(
                  key: Key('ai_rule_${r.id}'),
                  label: Text(
                    r.available ? r.shortName : '${r.shortName}（未开放）',
                  ),
                  selected: chosen == r.id,
                  onSelected: r.available
                      ? (_) => setState(() => _selectedRuleId = r.id)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _ruleSelected
                ? '当前规则：${RuleRegistry.resolve(chosen).shortName}'
                      ' · ${RuleRegistry.resolve(chosen).rulebook}'
                : '当前规则：未选择',
            key: const Key('ai_rule_current'),
            style: TextStyle(fontSize: 11.5, color: Palette.textMute),
          ),
          if (!_ruleSelected)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '请先选择一套规则系统，再生成角色卡。',
                key: Key('ai_rule_hint'),
                style: TextStyle(fontSize: 11.5, color: Palette.danger),
              ),
            ),

        ],
      ),
    );
  }

  /* ---------------- ① 未配置：引导而不是报错 ---------------- */

  Widget _configCard(SettingsRepo settings) {
    return SectionCard(
      title: '先接入一个大模型',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'AI 车卡需要你提供一个「OpenAI 兼容」的模型接口。填接口地址、模型名称与 API Key 三样即可，'
            '默认值已经填好 DeepSeek 的地址，通常只需要补一个 Key。',
            style: TextStyle(
              fontSize: 12.5,
              color: Palette.textMute,
              height: 1.85,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: const Key('ai_go_settings'),
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.settings),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.smart_toy_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('去配置'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('ai_use_random_from_config'),
                  // ★ P8：改成跳「一键出卡」页 —— 本页不再就地生成随机候选。
                  onPressed: () =>
                      Navigator.of(context).pushNamed(RandomCreatePage.route),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.casino_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('用离线随机卡'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            '不接入也完全不影响使用 ——「一键出卡」纯本地运行，不依赖任何接口。',
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------- ② 输入区 ---------------- */

  Widget _inputCard(AiCaps caps) {
    final labels = per.labels;
    return SectionCard(
      title: '描述你想创建什么样的调查员',
      subtitle: '一句话就行 —— 时代、职业、性格、经历，想到什么写什么。写得越具体，出来的卡越贴你的想法。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('ai_desc'),
            controller: _desc,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: '例如：民国时期的私家侦探，前警察，因为一桩案子丢了差事，随身带着一副旧手铐',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final ex in aiExamples)
                ActionChip(
                  label: Text(
                    ex.length > 14 ? '${ex.substring(0, 14)}…' : ex,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () => setState(() => _desc.text = ex),
                ),
            ],
          ),
          const SizedBox(height: 14),
           FieldLabel('世界设定', hint: '不选由模型按描述判断'),
          DropdownButtonFormField<String>(
            key: const Key('ai_setting'),
            initialValue: _settingId,
            isExpanded: true,
            decoration: const InputDecoration(),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(
                value: null,
                child: Text('自动（按描述判断）'),
              ),
              for (var i = 0; i < labels.length; i++)
                DropdownMenuItem<String>(
                  value: jsStr(per.list[i]['id']),
                  child: Text(labels[i]),
                ),
            ],
            onChanged: (v) => setState(() => _settingId = v),
          ),
          const SizedBox(height: 14),
          _capsEditor(caps),
          const SizedBox(height: 14),
          // ★ P10：生成**之前**就能选头像 —— 生成出来的卡直接带上这张图
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AvatarPicker(
              keyPrefix: 'ai_avatar',
              value: _avatarRel,
              name: _desc.text.trim(),
              cardId: _avatarId,
              label: '角色头像',
              hint: '可以先选一张图，生成出来的调查员会直接带上它',
              onChanged: _setAvatar,
            ),
          ),
          FilledButton(
            key: const Key('ai_generate'),
            // ★ P7-C：未选规则时按钮不可用，且下方有明确引导（K7）。
            onPressed: (_busy || !_canStart) ? null : _runAi,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.auto_awesome, size: 16),
                const SizedBox(width: 6),
                const Text('生成调查员'),
              ],
            ),
          ),
          if (!_ruleSelected)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '生成按钮已停用：请先在上方「规则系统」里选一套规则。',
                key: Key('ai_generate_rule_hint'),
                style: TextStyle(fontSize: 11.5, color: Palette.danger),
              ),
            ),
        ],
      ),
    );
  }

  /* ---------------- ②b 数值上限：三档 + 自定义（P7-B） ---------------- */

  /// 解析一个上限输入框。非法 → null（**不写入**，同时记下可见提示）。
  /// 判据与错误文案来自 [parseAiCapInput]，UI 里不写第二套。
  int? _parseCap(String raw, String label) {
    final r = parseAiCapInput(raw, label);
    if (!r.ok) _capsError = r.error;
    return r.value;
  }

  /// 把自定义输入写回设置并同步落盘（同步路径，零 await）。
  void _applyCustomCaps() {
    final s = _settings;
    final attr = _parseCap(_capAttr.text, '属性总和上限');
    final occ = _parseCap(_capOcc.text, '每项本职技能上限');
    final intn = _parseCap(_capInt.text, '每项兴趣技能上限');
    if (attr == null || occ == null || intn == null) {
      setState(() {}); // 只把可见提示上屏，设置里一个字节都不写
      return;
    }
    _capsError = '';
    // SettingsRepo 的 setter 同步 `applyToDomain()` → presetSettings 立刻生效。
    s
      ..aiAttrCap = attr
      ..aiOccPtsCap = occ
      ..aiIntPtsCap = intn
      ..aiAttrCapWithLuck = _withLuck;
    _capsSavePort.save();
    setState(() {});
  }

  Widget _capsEditor(AiCaps caps) {
    const tiers = <String, AiCaps>{
      '不限': AiCaps(),
      '标准': AiCaps(attrCap: 460, withLuck: true, occCap: 85, intCap: 70),
      '严格': AiCaps(attrCap: 400, withLuck: true, occCap: 70, intCap: 55),
    };
    String current = '自定义';
    tiers.forEach((k, v) {
      if (v.attrCap == caps.attrCap &&
          v.withLuck == caps.withLuck &&
          v.occCap == caps.occCap &&
          v.intCap == caps.intCap) {
        current = k;
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
         FieldLabel('数值上限（房规）', hint: '对随机卡与 AI 卡都生效；0 / 留空 = 不限'),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final e in tiers.entries)
              ChoiceChip(
                key: Key('ai_cap_${e.key}'),
                label: Text(e.key),
                selected: current == e.key,
                onSelected: (_) {
                  final v = e.value;
                  _settings
                    ..aiAttrCap = v.attrCap
                    ..aiAttrCapWithLuck = v.withLuck
                    ..aiOccPtsCap = v.occCap
                    ..aiIntPtsCap = v.intCap;
                  _capAttr.text = _numText(v.attrCap);
                  _capOcc.text = _numText(v.occCap);
                  _capInt.text = _numText(v.intCap);
                  _withLuck = v.withLuck;
                  _capsError = '';
                  _capsSavePort.save();
                  setState(() {});
                },
              ),
            if (current == '自定义')
              Chip(
                key: Key('ai_cap_custom_state'),
                label: Text('自定义'),
                backgroundColor: Palette.goldSoft,
              ),
          ],
        ),
        const SizedBox(height: 10),
         FieldLabel('属性总和上限', hint: '例如 400；九项合计超过就被压缩成 5 的倍数'),
        TextField(
          key: const Key('ai_cap_attr_input'),
          controller: _capAttr,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: const InputDecoration(
            hintText: '不限（填 0 或留空）',
            isDense: true,
          ),
          onChanged: (_) => _applyCustomCaps(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final withLuck in <bool>[true, false])
              ChoiceChip(
                key: Key('ai_cap_luck_${withLuck ? 'with' : 'without'}'),
                label: Text(withLuck ? '含幸运（9 项）' : '不含幸运（8 项）'),
                selected: _withLuck == withLuck,
                onSelected: (_) {
                  _withLuck = withLuck;
                  _applyCustomCaps();
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
         FieldLabel('每项本职技能上限', hint: '填 80 → 侦查这类本职技能最高 80；点数总额不变'),
        TextField(
          key: const Key('ai_cap_occ_input'),
          controller: _capOcc,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: const InputDecoration(
            hintText: '不限（填 0 或留空）',
            isDense: true,
          ),
          onChanged: (_) => _applyCustomCaps(),
        ),
        const SizedBox(height: 8),
         FieldLabel('每项兴趣技能上限', hint: '填 60 → 会计这类兴趣技能最高 60'),
        TextField(
          key: const Key('ai_cap_int_input'),
          controller: _capInt,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: const InputDecoration(
            hintText: '不限（填 0 或留空）',
            isDense: true,
          ),
          onChanged: (_) => _applyCustomCaps(),
        ),
        if (_capsError.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _capsError,
            key: const Key('ai_caps_error'),
            style: TextStyle(fontSize: 11.5, color: Palette.danger),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          caps.active ? '本次数值上限：${caps.text}' : '暂未设置数值上限 —— 按规则公式全额生成。',
          key: const Key('ai_caps_text'),
          style: TextStyle(
            fontSize: 11.5,
            color: Palette.textMute,
            height: 1.7,
          ),
        ),
        if (caps.occCap > 0 || caps.intCap > 0) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            '注意：技能上限指的是**每一项技能最多能点到多少**（例：职业 80 → 侦查最多 80），'
            '**不是**把职业点总数压到 80。点数总额仍按规则算。',
            style: TextStyle(fontSize: 11, color: Palette.gold, height: 1.7),
          ),
        ],
      ],
    );
  }

  /* ---------------- ③ 生成中 ---------------- */

  Widget _busyCard() {
    return SectionCard(
      key: const Key('ai_busy'),
      title: '正在生成…',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 生成中的插画：纯装饰，不参与语义。放在最上面是因为等待时
          // 用户的视线就停在这块卡片上，一张图比一行「请稍候」更能安抚。
          Center(
            child: SizedBox(
              width: 84,
              height: 84,
              child: ArtImage(Art.aiLoading, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _stage.isEmpty ? '正在请模型把你的点子写成一个调查员' : _stage,
                      key: const Key('ai_stage'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Palette.text,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '已用 $_elapsed 秒 · 通常 5-20 秒，模型越慢越久',
                      key: const Key('ai_elapsed'),
                      style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('ai_cancel'),
                onPressed: _cancel,
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '生成完会自动做一次规则校验：属性、职业点、技能上限、信用评级都要过，通不过会自动重掷。',
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------- ④ 失败 + 回退 ---------------- */

  Widget _errorCard() {
    return Container(
      key: const Key('ai_error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Palette.danger.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 失败插画：小尺寸，别让「出错了」看起来像中奖
          Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: ArtImage(
                Art.stateErrorFor(Palette.brightness),
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Icon(Icons.close, size: 14, color: Palette.danger),
              const SizedBox(width: 8),
              Text(
                '生成失败',
                style: TextStyle(
                  color: Palette.danger,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _error,
            key: const Key('ai_error_text'),
            style: TextStyle(fontSize: 13, color: Palette.text, height: 1.6),
          ),
          const SizedBox(height: 8),
          Text(
            '描述不会丢，直接再点一次试试；反复失败多半是接口配置的问题。',
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.75,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: const Key('ai_retry'),
                  onPressed: _canStart ? _runAi : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.refresh, size: 16),
                      const SizedBox(width: 6),
                      const Text('再试一次'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('ai_check_settings'),
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.settings),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.smart_toy_outlined, size: 16),
                      const SizedBox(width: 6),
                      const Text('检查设置'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          /* ⚠️ 这条是硬要求：AI 全挂了也要能拿到卡，不许把用户卡在错误页。
             P8 起改成跳「一键出卡」页（真的出 5 张完整卡），
             不再就地生成候选卡 —— 本页只负责 AI 那一条路。 */
          FilledButton.tonal(
            key: const Key('ai_fallback_random'),
            onPressed: () =>
                Navigator.of(context).pushNamed(RandomCreatePage.route),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.casino_outlined, size: 16),
                const SizedBox(width: 6),
                const Text('改用一键出卡（不需要网络）'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------- ⑤ 结果 ---------------- */

  Widget _resultCard(AiCreateResult r, AiCaps caps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '这张还行吗',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Palette.text,
              ),
            ),
            const Spacer(),
            TextButton(
              key: const Key('ai_regenerate'),
              onPressed: _canStart ? _runAi : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.refresh, size: 16),
                  const SizedBox(width: 6),
                  const Text('重新生成'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SummaryCard(
          summary: preset.summaryOf(r.character),
          index: 0,
          key: const Key('ai_result_card'),
        ),
        if (_capNote.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _capNote,
            key: const Key('ai_cap_note'),
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.7,
            ),
          ),
        ],
        const SizedBox(height: 11),
        /* ★ P9 需求 6：原来一个「√ 就用这张，继续完善」拆成两个动作 ——
           「就」= 我认了，直接存起来（需求 8：存完回首页）；
           「继续」= 还不满意，先进向导改（不存）。
           两个按钮都是真动作，没有一个是装饰。 */
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                key: const Key('result_use_this'),
                onPressed: () => _useThis(
                  r.character,
                  '第 0 步 AI 车卡：直接采用 AI 生成的调查员',
                ),
                child: const Text('就用这张'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                key: const Key('result_continue_edit'),
                onPressed: () => _adopt(
                  r.character,
                  '第 0 步 AI 车卡：采用 AI 生成的调查员',
                ),
                child: const Text('继续完善'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '「就用这张」直接存进「角色档案」并回首页；「继续完善」进向导逐项改，改完再存。'
          '「重新生成」会用同样的描述再要一张，风格会不一样。',
          style: TextStyle(
            fontSize: 11.5,
            color: Palette.textMute,
            height: 1.8,
          ),
        ),
      ],
    );
  }

  /* ---------------- ⑦ 说明 / 一键出卡入口 ---------------- */

  Widget _howItWorks() {
    return SectionCard(
      title: '它是怎么工作的',
      child: Text(
        'AI 只负责「是谁、做什么职业、长什么样、有什么故事」这些创意部分；'
        '属性、职业点、技能分配、装备与资产全部由本地规则引擎生成，'
        '所以生成的卡一定能通过完整性校验，可以直接拿去跑团。',
        style: TextStyle(fontSize: 12.5, color: Palette.textMute, height: 1.85),
      ),
    );
  }

  /// 「不想用 AI？」—— 只留说明 + 一个真正的入口，随机 5 张的 UI 全在
  /// [RandomCreatePage]，本页不再就地生成候选卡（P8）。
  Widget _noAiCard() {
    return SectionCard(
      title: '不想用 AI？',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '不用填 Key、不用联网、不用等模型。去「一键出卡」页，'
            '一次随机出 5 张完整预设卡（属性、技能、装备、背景全部填好），'
            '不满意就点右下角「重新随机」换一批。',
            style: TextStyle(
              fontSize: 12.5,
              color: Palette.textMute,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('ai_entry_random'),
            onPressed: () =>
                Navigator.of(context).pushNamed(RandomCreatePage.route),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.casino_outlined, size: 16),
                const SizedBox(width: 6),
                const Text('去「一键出卡」页'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
