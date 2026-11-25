// ============================================================
// settings_page.dart — 设置页
//
// 对齐旧版 `app.js#aiSettingsSheet`（AI 接入信息 + 数值上限）+ 分享/跑团地址
// + 技能上限与自动保存。旧版是弹层，这里做成整页（手机上长表单用页面更稳，
// 键盘弹起时不用和遮罩抢滚动）。
//
// 分五块：
//   ⓿ 外观 · 皮肤（暗色「深渊」/ 亮色「羊皮卷」）
//   ① AI 车卡 · 接入信息（地址 / 模型 / Key + 测试连接）
//   ② 数值上限（房规，可留空 = 不限）
//   ③ 服务地址（分享服务 / 跑团服务）
//   ④ 其它（技能上限 / 自动保存）
//
// ⚠️ 三条交互约定：
//   · 「测试连接」会**先保存**再探测（否则测的是旧配置）；
//   · Key 永远以 `password` 呈现，只有点「显示」才临时可见，
//     已保存时下方给的是**脱敏**后的形式（`sk-1****abcd`）；
//   · `roomBase` 只存不连 —— 界面必须写明「P4 才启用」，
//     不能让用户以为填了就能联机。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/ai_probe.dart';
import '../repo/repo_scope.dart';
import '../repo/settings_repo.dart';
import '../theme.dart';
import 'widgets.dart';
import 'notice.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsRepo _repo;
  bool _bound = false;

  final _aiBase = TextEditingController();
  final _aiModel = TextEditingController();
  final _aiKey = TextEditingController();
  final _shareBase = TextEditingController();
  final _roomBase = TextEditingController();
  final _capAttr = TextEditingController();
  final _capOcc = TextEditingController();
  final _capInt = TextEditingController();
  final _skillCap = TextEditingController();

  bool _showKey = false;
  bool _testing = false;
  bool _withLuck = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = SettingsScope.read(context);
    if (!_bound) {
      _bound = true;
      _pullFromRepo();
    }
  }

  /// 把仓库里的现值灌进输入框（只做一次；之后以用户输入为准）
  void _pullFromRepo() {
    _aiBase.text = _repo.aiBase;
    _aiModel.text = _repo.aiModel;
    _aiKey.text = _repo.aiKey;
    _shareBase.text = _repo.shareBase;
    _roomBase.text = _repo.roomBase;
    _capAttr.text = _repo.aiAttrCap > 0 ? '${_repo.aiAttrCap}' : '';
    _capOcc.text = _repo.aiOccPtsCap > 0 ? '${_repo.aiOccPtsCap}' : '';
    _capInt.text = _repo.aiIntPtsCap > 0 ? '${_repo.aiIntPtsCap}' : '';
    _skillCap.text = '${_repo.skillCap}';
    _withLuck = _repo.aiAttrCapWithLuck;
  }

  @override
  void dispose() {
    _aiBase.dispose();
    _aiModel.dispose();
    _aiKey.dispose();
    _shareBase.dispose();
    _roomBase.dispose();
    _capAttr.dispose();
    _capOcc.dispose();
    _capInt.dispose();
    _skillCap.dispose();
    super.dispose();
  }

  bool _looksLikeUrl(String v) =>
      RegExp(r'^https?://', caseSensitive: false).hasMatch(v);

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSlot(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Palette.danger : null,
      ),
    );
  }

  /// 保存 AI 三项 + 房规上限。返回是否成功（地址格式不对就不保存）。
  Future<bool> _saveAi({bool quiet = false}) async {
    final base = _aiBase.text.trim();
    if (base.isNotEmpty && !_looksLikeUrl(base)) {
      _toast('接口地址需要以 http:// 或 https:// 开头', error: true);
      return false;
    }
    _repo
      ..aiBase = base
      ..aiModel = _aiModel.text.trim()
      ..aiKey = _aiKey.text.trim()
      ..aiAttrCap = _readCap(_capAttr)
      ..aiAttrCapWithLuck = _withLuck
      ..aiOccPtsCap = _readCap(_capOcc)
      ..aiIntPtsCap = _readCap(_capInt);
    await _repo.save();
    if (!quiet) _toast('设置已保存');
    return true;
  }

  int _readCap(TextEditingController c) {
    final v = int.tryParse(c.text.trim()) ?? 0;
    return v > 0 ? v : 0; // 0 = 不限
  }

  Future<void> _testConnection() async {
    final ok = await _saveAi(quiet: true);
    if (!ok) return;
    if (!_repo.aiConfigured) {
      _toast('三项都填好才能测试', error: true);
      return;
    }
    setState(() => _testing = true);
    final r = await _repo.testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    _toast('${r.kindLabel} · ${r.message}', error: !r.ok);
  }

  @override
  Widget build(BuildContext context) {
    // 订阅仓库：其它地方改了设置（或探测结果变了）也能刷新
    final repo = SettingsScope.of(context);
    _repo = repo;
    final probe = repo.lastProbe;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            '设置',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
            children: <Widget>[
              _themeCard(),
              const SizedBox(height: 12),
              _aiCard(),
              if (probe != null) ...<Widget>[
                const SizedBox(height: 12),
                _probeCard(probe),
              ],
              const SizedBox(height: 12),
              _capsCard(),
              const SizedBox(height: 12),
              _servicesCard(),
              const SizedBox(height: 12),
              _miscCard(),
              const SizedBox(height: 12),
              _HowToCard(),
              if (repo.lastError != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  repo.lastError!,
                  style: TextStyle(fontSize: 12, color: Palette.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /* ---------- ⓿ 外观 · 皮肤 ---------- */

  /// 切换皮肤。
  ///
  /// 这里只改 `SettingsRepo` 并落盘 —— 真正的重建由 `DiceRealmApp` 监听
  /// 完成（它比对皮肤值后 `setState`，从而让 MaterialApp 换 ThemeData，
  /// 进而每个 Scaffold 重建、`Palette.xxx` 取到新色）。
  /// 所以本页必须自己 `setState` 一次，否则勾选状态要等下次进页面才变。
  Future<void> _pickTheme(bool dark) async {
    if (_repo.isDarkTheme == dark) return;
    setState(() => _repo.isDarkTheme = dark);
    await _repo.save();
  }

  Widget _themeCard() {
    return SectionCard(
      title: '外观 · 皮肤',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _ThemeOption(
              optKey: const Key('settings_theme_dark'),
              label: '暗色 · 深渊',
              hint: '深紫夜空 · 冷金',
              palette: AppPalette.dark,
              selected: _repo.isDarkTheme,
              onTap: () => _pickTheme(true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ThemeOption(
              optKey: const Key('settings_theme_light'),
              label: '亮色 · 羊皮卷',
              hint: '暖象牙 · 深金',
              palette: AppPalette.light,
              selected: !_repo.isDarkTheme,
              onTap: () => _pickTheme(false),
            ),
          ),
        ],
      ),
    );
  }

  /* ---------- ① AI 接入信息 ---------- */

  Widget _aiCard() {
    return SectionCard(
      title: 'AI 车卡 · 接入信息',
      subtitle: '填入任意一个「OpenAI 兼容」的大模型接口。三项都只保存在本机，不会随导出/分享上传。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
           FieldLabel(
            '接口地址',
            hint: '默认 DeepSeek：https://api.deepseek.com/v1',
          ),
          TextField(
            key: const Key('settings_ai_base'),
            controller: _aiBase,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://api.deepseek.com/v1',
            ),
          ),
          const SizedBox(height: 12),
           FieldLabel('模型名称', hint: '默认 deepseek-flash；换服务商时填它提供的模型名'),
          TextField(
            key: const Key('settings_ai_model'),
            controller: _aiModel,
            decoration: const InputDecoration(hintText: 'deepseek-flash'),
          ),
          const SizedBox(height: 12),
           FieldLabel('API Key', hint: '在服务商后台创建，形如 sk-...'),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('settings_ai_key'),
                  controller: _aiKey,
                  obscureText: !_showKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(hintText: 'sk-...'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('settings_ai_key_toggle'),
                onPressed: () => setState(() => _showKey = !_showKey),
                child: Text(_showKey ? '隐藏' : '显示'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: const Key('settings_save_ai'),
                  onPressed: () => _saveAi(),
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('settings_test_conn'),
                  onPressed: _testing ? null : _testConnection,
                  child: Text(_testing ? '测试中…' : '测试连接'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _repo.aiConfigured
                ? '当前：${_repo.aiBase}　模型 ${_repo.aiModel}　Key ${_repo.maskedAiKey}'
                : '尚未配置完整 —— AI 车卡暂不可用（「生成随机角色」不受影响，完全离线）。',
            key: const Key('settings_ai_state'),
            style: TextStyle(
              fontSize: 12,
              color: Palette.textMute,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  /* ---------- 探测结果 ---------- */

  Widget _probeCard(AiProbeResult r) {
    final color = r.ok ? Palette.success : Palette.danger;
    return Container(
      key: const Key('settings_probe_result'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                r.ok ? '✓' : '✕',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                r.kindLabel,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              if (r.via.isNotEmpty) ...<Widget>[
                const Spacer(),
                Text(
                  '经由 /${r.via}',
                  style: TextStyle(fontSize: 11, color: Palette.textMute),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.message,
            style: TextStyle(
              fontSize: 13,
              color: Palette.text,
              height: 1.6,
            ),
          ),
          if (r.hint.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              r.hint,
              style: TextStyle(
                fontSize: 12,
                color: Palette.textDim,
                height: 1.7,
              ),
            ),
          ],
          if (r.models.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '该地址可用模型（部分）：${r.models.take(12).join('、')}'
              '${r.models.length > 12 ? ' 等 ${r.models.length} 个' : ''}',
              style: TextStyle(
                fontSize: 11.5,
                color: Palette.textMute,
                height: 1.7,
              ),
            ),
          ],
          if (!r.ok) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '可以按顺序检查：① 接口地址是不是以 http(s):// 开头、结尾有没有多写斜杠；'
              '② 模型名称是不是该服务商实际提供的名字；③ API Key 有没有复制完整；'
              '④ 网络能不能访问该地址（部分服务需要代理）。',
              style: TextStyle(
                fontSize: 11.5,
                color: Palette.textMute,
                height: 1.75,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /* ---------- ② 数值上限 ---------- */

  Widget _capsCard() {
    return SectionCard(
      title: '数值上限（房规 · 可选）',
      subtitle:
          '定房规用：想让大家创建的调查员别太强，就在这里设上限。对「生成随机角色」与「AI 车卡」都生效（彩蛋卡也一样）。留空表示不限制。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
           FieldLabel('属性总和上限', hint: '例如 400；九项合计超过就被等比压缩'),
          TextField(
            key: const Key('settings_cap_attr'),
            controller: _capAttr,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(hintText: '不限'),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final withLuck in <bool>[true, false]) ...<Widget>[
                ChoiceChip(
                  key: Key(
                    'settings_cap_luck_${withLuck ? 'with' : 'without'}',
                  ),
                  label: Text(withLuck ? '含幸运（9 项）' : '不含幸运（8 项）'),
                  selected: _withLuck == withLuck,
                  onSelected: (_) => setState(() => _withLuck = withLuck),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
           FieldLabel(
            '每项本职技能上限',
            hint: '填 80 → 「侦查」这类本职技能最高到 80；点数总额不会因此变少',
          ),
          TextField(
            key: const Key('settings_cap_occ'),
            controller: _capOcc,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(hintText: '不限'),
          ),
          const SizedBox(height: 12),
           FieldLabel('每项兴趣技能上限', hint: '填 60 → 「会计」这类非本职技能最高到 60'),
          TextField(
            key: const Key('settings_cap_int'),
            controller: _capInt,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(hintText: '不限'),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: const Key('settings_save_caps'),
                  onPressed: () => _saveAi(),
                  child: const Text('保存上限'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('settings_clear_caps'),
                  onPressed: () async {
                    setState(() => _withLuck = true);
                    _capAttr.text = '';
                    _capOcc.text = '';
                    _capInt.text = '';
                    await _saveAi();
                  },
                  child: const Text('全部清除'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '属性超限时按比例压缩，不会把某个单项砍成废人 —— 原本强的还是强。',
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.75,
            ),
          ),
        ],
      ),
    );
  }

  /* ---------- ③ 服务地址 ---------- */

  Widget _servicesCard() {
    return SectionCard(
      title: '服务地址',
      subtitle: '两项都可以留空 —— 留空表示未配置，应用不会向任何服务器发送数据。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
           FieldLabel('分享服务地址', hint: '角色卡云分享用的后端'),
          TextField(
            key: const Key('settings_share_base'),
            controller: _shareBase,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://你的域名/coc（可留空）',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _repo.shareConfigured
                ? '当前：${_repo.shareBase}'
                : '未配置 —— 不会上传任何数据。这段时间仍然可用「本机导出 JSON / 生成长图」分享角色卡。',
            key: const Key('settings_share_state'),
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.75,
            ),
          ),
          const SizedBox(height: 12),
          FieldLabel('跑团服务地址'),
          TextField(
            key: const Key('settings_room_base'),
            controller: _roomBase,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://你的域名/room（可留空）',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            key: const Key('settings_save_services'),
            onPressed: () async {
              for (final v in <String>[
                _shareBase.text.trim(),
                _roomBase.text.trim(),
              ]) {
                if (v.isNotEmpty && !_looksLikeUrl(v)) {
                  _toast('地址需要以 http:// 或 https:// 开头', error: true);
                  return;
                }
              }
              _repo
                ..shareBase = _shareBase.text
                ..roomBase = _roomBase.text;
              await _repo.save();
              _toast('服务地址已保存');
            },
            child: const Text('保存服务地址'),
          ),
        ],
      ),
    );
  }

  /* ---------- ④ 其它 ---------- */

  Widget _miscCard() {
    return SectionCard(
      title: '其它',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
           FieldLabel('技能上限', hint: '单项技能的通用上限（1-99）；分项上限在「数值上限」里'),
          TextField(
            key: const Key('settings_skill_cap'),
            controller: _skillCap,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(hintText: '99'),
          ),
          const SizedBox(height: 10),
          /* ⚠️ 这里刻意**不用 SwitchListTile**：它要在最近的 Material 上画背景与
             水波纹，而 SectionCard 外面是一层 DecoratedBox（底色 + 描边），
             Flutter 会直接断言「ListTile 的底色/水波纹可能看不见」。
             自己拼一行 Row 更省事，也不会为了一个开关去改通用卡片。 */
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '自动保存',
                      style: TextStyle(fontSize: 14, color: Palette.text),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '车卡过程中自动写入本地存档；关掉后需要手动点保存',
                      style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const Key('settings_auto_save'),
                value: _repo.autoSave,
                onChanged: (v) async {
                  _repo.autoSave = v;
                  await _repo.save();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          FilledButton.tonal(
            key: const Key('settings_save_misc'),
            onPressed: () async {
              final n = int.tryParse(_skillCap.text.trim()) ?? 99;
              _repo.skillCap = n;
              await _repo.save();
              _skillCap.text = '${_repo.skillCap}';
              _toast('已保存');
            },
            child: const Text('保存技能上限'),
          ),
        ],
      ),
    );
  }
}

/// 一张皮肤选项卡：用该皮肤自己的三种颜色画一个迷你预览，
/// 让用户在**不切换**的情况下就能看出两套皮肤的区别。
///
/// 为什么包一层 `Material`：`SectionCard` 外层是 `DecoratedBox`，
/// `InkWell` 的水波纹要在最近的 `Material` 上绘制，否则会断言
/// 「墨水特效可能看不见」（与下面自动保存开关不用 ListTile 是同一原因）。
class _ThemeOption extends StatelessWidget {
   const _ThemeOption({
    required this.optKey,
    required this.label,
    required this.hint,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final Key optKey;
  final String label;
  final String hint;
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: optKey,
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Palette.surface2,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: selected ? Palette.gold : Palette.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 迷你预览：底色 + 一条金线，正是两套皮肤最大的观感差异
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: palette.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.gold.withValues(alpha: 0.55)),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 46,
                  height: 7,
                  decoration: BoxDecoration(
                    color: palette.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Palette.text,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, size: 15, color: Palette.gold),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                hint,
                style: TextStyle(fontSize: 10.5, color: Palette.textMute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「怎么用（三步）」+「去哪儿申请 Key」—— 与旧版一致，降低上手成本
class _HowToCard extends StatelessWidget {
   const _HowToCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '怎么用（三步）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _line(
            '① 填三项',
            '接口地址、模型名称、API Key。默认值已经是 DeepSeek 官方地址与 deepseek-flash，只补 Key 就能用。',
          ),
          _line(
            '② 点「测试连接」',
            '先验地址与 Key（GET /models，秒回、不烧生成额度），不支持时自动回退一次极小的对话探测。',
          ),
          _line('③ 去第 0 步用', '「快速开始 → AI 车卡」，用一句话描述你想创建什么样的调查员。'),
          const SizedBox(height: 10),
          Text(
            '不配置也完全不影响使用：第 0 步的「生成随机角色」与所有车卡功能都是纯本地的。',
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.75,
            ),
          ),
          const SizedBox(height: 12),
           HairLine(),
          const SizedBox(height: 12),
          Text(
            '去哪儿申请 Key',
            style: TextStyle(
              fontSize: 13,
              color: Palette.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '· DeepSeek：platform.deepseek.com → API keys，价格便宜、中文好。\n'
            '· 其它兼容 OpenAI 格式的服务（通义千问、智谱、月之暗面、硅基流动等）：\n'
            '　 把服务商给的接口地址、模型名、Key 填进去即可，用法完全一样。',
            style: TextStyle(
              fontSize: 12,
              color: Palette.textMute,
              height: 1.85,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '说明：AI 车卡时，你写的那句描述会发送到上面填写的接口，由该服务商处理；'
            '除此之外不会有任何数据离开这台设备。生成一张卡通常几秒，费用由你的账号承担。',
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.textMute,
              height: 1.75,
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String bold, String rest) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$bold　',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Palette.textDim,
              ),
            ),
            TextSpan(text: rest),
          ],
        ),
        style: TextStyle(
          fontSize: 12.5,
          color: Palette.textMute,
          height: 1.8,
        ),
      ),
    );
  }
}
