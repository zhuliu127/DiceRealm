// ============================================================
// card_detail_page.dart — 角色卡详情（P2-A：可编辑 + 删除 + 导入/导出）
//
// 编辑态语义对齐旧版 `core/store.js` 的 beginEdit / commitEdit / cancelEdit：
//   · 进入编辑 = 深拷贝一份工作副本（`clone()`），原卡一个字都不动
//   · 编辑期间所有改动只落在副本上
//   · 「保存」才 normalize → recalc → 落盘；「取消」直接丢弃副本
//   · 中途返回（系统返回键）也走「放弃」，不会悄悄写回
//
// 撕卡（body='死亡' 或 mental 含「永久疯狂」）的卡**不可编辑**（旧版 v2.1.8
// 同款约束），只能浏览 / 导出 / 删除。
//
// 保存时的撕卡判定与二次确认（硬约束 3）：
//   HP（或上限）归零 → body='死亡'；SAN（或上限）归零 → mental=['永久疯狂']
//   两者都要玩家在弹窗里确认；取消 = 什么都不写、留在编辑态。
// ============================================================

import 'package:flutter/material.dart';

import 'art.dart';
import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../domain/occupation.dart';
import '../domain/rule_registry.dart' show RuleRegistry;
import '../repo/card_transfer.dart';
import '../repo/character_repo.dart';
import '../repo/repo_scope.dart';
import '../theme.dart';
import 'attr_meta.dart';
import 'card_edit/background_editor.dart';
import 'card_edit/basics_editor.dart';
import 'card_edit/skills_editor.dart';
import 'card_edit/status_editor.dart';
import 'card_transfer_io.dart';
import 'card_view.dart';
import 'share_panel.dart';
import 'status_ops.dart';
import 'widgets.dart';
import 'notice.dart';

class CardDetailPage extends StatefulWidget {
  const CardDetailPage({super.key, required this.cardId});

  final String cardId;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  /// 编辑中的工作副本（null = 只读态）
  Character? _draft;
  final GlobalKey<StatusEditorState> _statusKey =
      GlobalKey<StatusEditorState>();
  bool _busy = false;

  /// 只读态列表的滚动控制器：顶部 bar 的「分享」按钮靠它滚到页面底部的云分享区。
  final ScrollController _readScroll = ScrollController();

  /// 云分享区的锚点：滚到位后用 `Scrollable.ensureVisible` 精确对齐。
  final GlobalKey _shareKey = GlobalKey();

  @override
  void dispose() {
    _readScroll.dispose();
    super.dispose();
  }

  /// 滚到页面底部的云分享区。
  ///
  /// 只读态是 `ListView(children: …)`，子项**懒构建** —— 分享区在屏幕外时
  /// 根本不在树里，`ensureVisible` 拿不到它的 context。所以分两步：
  ///   1. 先 `jumpTo(maxScrollExtent)` 把最后一段拉出来（懒构建列表的
  ///      maxScrollExtent 是估算值，跳完可能还不够，最多补 4 帧收敛）；
  ///   2. 一旦分享区进入树，用 `Scrollable.ensureVisible` 平滑对齐。
  void _scrollToShare() => _revealShare(4);

  void _revealShare(int attemptsLeft) {
    final BuildContext? ctx = _shareKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
      return;
    }
    if (!_readScroll.hasClients || attemptsLeft <= 0) return;
    _readScroll.jumpTo(_readScroll.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealShare(attemptsLeft - 1);
    });
  }

  bool get _editing => _draft != null;

  void _startEdit(Character card) {
    setState(() => _draft = card.clone());
  }

  void _cancelEdit() {
    setState(() => _draft = null);
  }

  /// 保存：提交暂存 → recalc → 撕卡判定（二次确认）→ normalize+recalc+落盘
  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _busy) return;
    _statusKey.currentState?.commitPending();

    final messenger = ScaffoldMessenger.of(context);
    final repo = RepoScope.read(context);

    final pending = prepareStatusSave(draft);
    if (pending.hit) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存后角色将被判定撕卡（不可逆）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final r in pending.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· $r',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '确定要撕掉这张角色卡吗？',
                style: TextStyle(fontSize: 13, color: Palette.textDim),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('cancel_rip'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('confirm_rip'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认撕卡'),
            ),
          ],
        ),
      );
      if (ok != true) {
        if (mounted) {
          setState(() {});
          messenger.showSlot(const SnackBar(content: Text('已取消，未保存撕卡判定')));
        }
        return;
      }
      applyRip(draft, pending);
    }

    setState(() => _busy = true);
    try {
      await repo.save(draft);
      if (!mounted) return;
      setState(() {
        _draft = null;
        _busy = false;
      });
      // 保存后停留在详情页（与旧版 saveEdit 跳回卡片页一致）
      messenger.showSlot(
        SnackBar(content: Text('已保存「${draft.characterName}」')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(Character card) async {
    final messenger = ScaffoldMessenger.of(context);
    final json = exportCardJson(card);
    final safeName = card.characterName.trim().isEmpty
        ? 'character'
        : card.characterName.trim();
    try {
      final path = await cardTransferIo.export('coc7-$safeName.json', json);
      if (!mounted) return;
      messenger.showSlot(
        SnackBar(content: Text(path == null ? '已导出' : '已导出到 $path')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSlot(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _delete(Character card) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = RepoScope.read(context);
    final name = card.characterName.trim().isEmpty ? '未命名' : card.characterName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「$name」？'),
        content: const Text('此操作不可恢复（没有回收站）。'),
        actions: <Widget>[
          TextButton(
            key: const Key('cancel_delete'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm_delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Palette.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.delete(card.id);
    if (!mounted) return;
    messenger.showSlot(const SnackBar(content: Text('已删除')));
    // 回首页（详情页是从首页 push 上来的）
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final draft = _draft;
    final card = draft ?? repo.get(widget.cardId);

    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('角色卡')),
        body: Center(
          child: Text('这张卡已经不在了', style: TextStyle(color: Palette.textDim)),
        ),
      );
    }

    final ripped = isRippedCard(card);
    final title = card.characterName.isEmpty ? '无名调查员' : card.characterName;

    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_editing) return;
        // 编辑态按返回 = 放弃修改（原卡纹丝不动）
        setState(() => _draft = null);
      },
      child: Scaffold(
        backgroundColor: Palette.bg,
        appBar: AppBar(
          title: Text(title),
          actions: _editing ? _editActions() : _readActions(card, ripped),
        ),
        body: _editing ? _editBody(card) : _readBody(card, ripped),
      ),
    );
  }

  List<Widget> _editActions() {
    return <Widget>[
      TextButton(
        key: const Key('btn_cancel_edit'),
        onPressed: _busy ? null : _cancelEdit,
        child: const Text('取消'),
      ),
      Padding(
        padding: const EdgeInsets.only(right: 8, left: 4),
        child: FilledButton(
          key: const Key('btn_save'),
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          child: const Text('保存'),
        ),
      ),
    ];
  }

  List<Widget> _readActions(Character card, bool ripped) {
    return <Widget>[
      if (!ripped)
        IconButton(
          key: const Key('btn_edit'),
          tooltip: '编辑角色',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: () => _startEdit(card),
        ),
      // ★ P8：「修改」右边的快捷分享 —— 滚到页面底部的云分享区，
      //   不弹假弹层、不假装分享成功（真正的分享动作仍由 SharePanel 发起）。
      IconButton(
        key: const Key('card_quick_share'),
        tooltip: '分享到云（跳到云分享区）',
        icon: const Icon(Icons.ios_share, size: 20),
        onPressed: _scrollToShare,
      ),
      PopupMenuButton<String>(
        key: const Key('card_menu'),
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) {
          if (v == 'export') _export(card);
          if (v == 'delete') _delete(card);
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          // P12：⬇ / 🗑 前缀换成矢量图标，文案只留中文。
          PopupMenuItem<String>(
            key: const Key('menu_export_card'),
            value: 'export',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.file_download_outlined,
                  size: 16,
                  color: Palette.textDim,
                ),
                const SizedBox(width: 8),
                const Text('导出 JSON'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            key: const Key('menu_delete_card'),
            value: 'delete',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Palette.textDim,
                ),
                const SizedBox(width: 8),
                const Text('删除角色'),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _editBody(Character card) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Palette.goldSoft,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: Palette.gold.withValues(alpha: 0.4)),
          ),
          // P12：行首 ✎ 换成矢量图标（14dp，跟随提示文字的金色）。
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.edit_note,
                  size: 14,
                  color: Palette.goldStr,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '正在编辑：改动不会自动写回，点右上角「保存」才生效，「取消」则恢复原样。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Palette.goldStr,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        BasicsEditor(card: card, onChanged: _rebuild),
        const SizedBox(height: 12),
        StatusEditor(key: _statusKey, card: card, onChanged: _rebuild),
        const SizedBox(height: 12),
        SkillsEditor(card: card, onChanged: _rebuild),
        const SizedBox(height: 12),
        BackgroundEditor(
          card: card,
          onChanged: _rebuild,
          showPresets: false,
          showMadnessTable: true,
        ),
      ],
    );
  }

  void _rebuild() {
    if (!mounted) return;
    // 改了年龄 / 属性会让 HP/MP/SAN 的上限变化，输入框要跟着刷新
    _statusKey.currentState?.syncFromModel();
    setState(() {});
  }

  Widget _readBody(Character card, bool ripped) {
    final occSet = occupationalSet(card);
    final rows = skillRows(card, occKeys: occSet.keys.toSet());
    final adj = card.raw['ageAdj'];
    final loss = adj is Map ? asMap(adj['loss']) : <String, Object?>{};

    return ListView(
      controller: _readScroll,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      children: <Widget>[
        if (ripped) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Palette.dangerSoft,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: Palette.danger.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: <Widget>[
                // 撕卡印章（美术）：只保留左侧「圆圈 + 骷髅头」这一枚图标。
                // ★ 用户 2026-11-11 真机指出旁边还并排着一个 ☠ emoji，
                //   两个骷髅很怪 → 删掉。它原本是「图缺失时的语义兜底」，
                //   现在改由 ArtImage.fallback 用矢量图标承担，不再用 emoji。
                SizedBox(
                  width: 30,
                  height: 30,
                  child: ArtImage(
                    Art.rippedStamp,
                    fit: BoxFit.contain,
                    fallback: Icon(
                      Icons.dangerous_outlined,
                      size: 26,
                      color: Palette.danger,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    jsStr(card.status['body']) == '死亡'
                        ? '这名调查员已经死亡，卡片已进入英灵殿。'
                        : '永久疯狂 —— 调查员已退场，卡片已进入英灵殿。',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Palette.danger,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ---------- 概要 ----------
        SectionCard(
          title: '概要',
          child: Column(
            children: <Widget>[
              // ★ P7-D：详情里能看到规则徽标（单一真源 RuleRegistry）。
              KeyValueRow(
                '规则',
                '${RuleRegistry.shortNameOf(card.ruleSystemId)} · '
                    '${RuleRegistry.resolve(card.ruleSystemId).name}',
              ),
              KeyValueRow('职业', occupationLabel(card)),
              KeyValueRow('年龄', ageLabel(card)),
              KeyValueRow('性别', genderLabel(card)),
              KeyValueRow(
                '玩家',
                card.playerName.isEmpty ? '—' : card.playerName,
              ),
              KeyValueRow('时代', jsStr(card.basicInfo['era'])),
              KeyValueRow('居住地', jsStr(card.basicInfo['residence'])),
              KeyValueRow('出生地', jsStr(card.basicInfo['birthplace'])),
              KeyValueRow(
                '身体状态',
                bodyView(card),
                valueColor: bodyView(card) == '正常'
                    ? Palette.success
                    : Palette.danger,
              ),
              KeyValueRow('精神状态', mentalText(card)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 状态 ----------
        SectionCard(
          title: '状态',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      label: '生命 HP',
                      value: hpLabel(card),
                      color: Palette.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: '魔法 MP',
                      value: mpLabel(card),
                      color: Palette.teal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      label: '理智 SAN',
                      value: sanLabel(card),
                      color: Palette.arcane,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: '幸运 LUCK',
                      value: luckLabel(card),
                      color: Palette.gold,
                    ),
                  ),
                ],
              ),
              if (jsNum(card.raw['sanLoss']) > 0) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '理智上限永久减损 −${jsNum(card.raw['sanLoss'])}（未减损时上限 ${jsNum(card.status['baseMaxSAN'])}）',
                  style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                ),
              ],
              if (madnessCount(card) > 0) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '疯狂 ${madnessCount(card)} 条',
                    style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 属性 ----------
        SectionCard(
          title: '属性',
          subtitle: jsNum(loss.values.fold<int>(0, (a, b) => a + jsNum(b))) > 0
              ? '年龄调整：${_lossText(loss)}'
              : null,
          child: Column(
            children: <Widget>[
              for (var i = 0; i < allAttrKeys.length; i += 3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      for (
                        var j = i;
                        j < i + 3 && j < allAttrKeys.length;
                        j++
                      ) ...<Widget>[
                        if (j > i) const SizedBox(width: 8),
                        Expanded(
                          child: _AttrTile(card: card, attrKey: allAttrKeys[j]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 派生 ----------
        SectionCard(
          title: '派生',
          child: Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: '移动力 MOV',
                  value: '${jsNum(card.derivedStats['mov'])}',
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: '伤害加值 DB',
                  value: jsStr(card.derivedStats['db']),
                  compact: true,
                  color: Palette.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: '体格',
                  value: '${jsNum(card.derivedStats['build'])}',
                  compact: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 技能 ----------
        SectionCard(
          title: '技能',
          subtitle: '共 ${rows.length} 项 · 本职技能优先',
          child: Column(
            children: <Widget>[
              for (final s in rows.where((r) => jsNum(r['total']) > 0).take(40))
                _SkillRow(
                  skill: s,
                  isOcc:
                      occSet.containsKey(jsStr(s['key'])) ||
                      occSet.containsKey(jsStr(s['id'])),
                ),
              if (rows.where((r) => jsNum(r['total']) > 0).isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '还没有技能加点',
                    style: TextStyle(fontSize: 12.5, color: Palette.textMute),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 背景 ----------
        SectionCard(
          title: '背景',
          child: Column(
            children: <Widget>[
              KeyValueRow('形象描述', jsStr(card.background['description'])),
              KeyValueRow('思想与信念', jsStr(card.background['ideology'])),
              KeyValueRow('重要之人', jsStr(card.background['significantPeople'])),
              KeyValueRow('意义之地', jsStr(card.background['meaningfulPlaces'])),
              KeyValueRow(
                '宝贵之物',
                jsStr(card.background['treasuredPossessions']),
              ),
              KeyValueRow('特质', jsStr(card.background['traits'])),
              KeyValueRow('伤口与疤痕', jsStr(card.background['wounds'])),
              KeyValueRow('恐惧症 / 狂躁症', jsStr(card.background['phobias'])),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---------- 云分享 ----------
        SharePanel(key: _shareKey, card: card),
      ],
    );
  }

  static String _lossText(Map<String, Object?> loss) {
    final parts = <String>[];
    const names = <String, String>{
      'str': '力量',
      'con': '体质',
      'siz': '体型',
      'dex': '敏捷',
      'app': '外貌',
    };
    names.forEach((k, v) {
      final n = jsNum(loss[k]);
      if (n > 0) parts.add('$v −$n');
    });
    return parts.join('，');
  }
}

class _AttrTile extends StatelessWidget {
   const _AttrTile({required this.card, required this.attrKey});

  final Character card;
  final String attrKey;

  @override
  Widget build(BuildContext context) {
    final raw = attrText(card, attrKey);
    final eff = effAttr(card, attrKey);
    final changed = raw != '—' && eff != jsNum(card.attributes[attrKey]);
    final label = attrName(attrKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.surface2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 11, color: Palette.textMute)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                changed ? '$eff' : raw,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: changed ? Palette.gold : Palette.text,
                ),
              ),
              if (changed) ...<Widget>[
                const SizedBox(width: 5),
                Text(
                  '← $raw',
                  style: TextStyle(fontSize: 10.5, color: Palette.textMute),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
   const _SkillRow({required this.skill, required this.isOcc});

  final Map<String, Object?> skill;
  final bool isOcc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          if (isOcc)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: Palette.gold,
                shape: BoxShape.circle,
              ),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              jsStr(skill['name']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: isOcc ? Palette.text : Palette.textDim,
              ),
            ),
          ),
          Text(
            '${jsNum(skill['total'])}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Palette.text,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 62,
            child: Text(
              _breakdown(skill),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10.5, color: Palette.textMute),
            ),
          ),
        ],
      ),
    );
  }

  static String _breakdown(Map<String, Object?> s) {
    final parts = <String>[];
    if (jsNum(s['base']) != 0) parts.add('基${jsNum(s['base'])}');
    if (jsNum(s['occ']) != 0) parts.add('职${jsNum(s['occ'])}');
    if (jsNum(s['int']) != 0) parts.add('兴${jsNum(s['int'])}');
    if (jsNum(s['growth']) != 0) parts.add('成${jsNum(s['growth'])}');
    return parts.join(' ');
  }
}
