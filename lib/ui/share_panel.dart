// ============================================================
// share_panel.dart — 角色卡云分享的界面（详情页与完成页共用）
// 对应 `ui/share-ui.js#panel()`
//
// 三种状态，各有各的正确做法：
//   ① 未配置服务地址 → **不摆上传按钮**，给「怎么开启」+「不开也能用」两条路；
//      点了也不会发起请求（不许静默失败）。
//   ② 已配置、未分享 → 一个「创建分享」按钮。
//   ③ 已分享 → 链接 + 复制 / 分享 / 更新 / 删除（删除要二次确认）。
//
// ⚠️ 「浏览器打开」用**系统分享面板**代替（`share_plus` 已是现有依赖）：
//    平台自带浏览器有多套，`url_launcher` 会多一个依赖 + 一套 Android
//    queries 配置，为一个次要按钮不值当。系统面板里可以选浏览器、微信、邮件。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/character.dart';
import '../domain/rule_registry.dart';
import '../net/share_client.dart';
import '../repo/repo_scope.dart';
import '../repo/share_store.dart';
import '../theme.dart';
import 'widgets.dart';
import 'notice.dart';

class SharePanel extends StatefulWidget {
  const SharePanel({super.key, required this.card});

  final Character card;

  @override
  State<SharePanel> createState() => _SharePanelState();
}

class _SharePanelState extends State<SharePanel> {
  bool _busy = false;
  String _error = '';

  ShareService get _service => ShareScope.read(context);

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSlot(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Palette.danger : null,
      ),
    );
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final rec = await _service.create(widget.card);
      if (!mounted) return;
      _toast('分享已生成：${rec.url}');
    } on ShareException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ShareRecord rec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分享'),
        content: const Text('删除后该链接立即失效，其他人将无法打开。确定删除吗？'),
        actions: <Widget>[
          TextButton(
            key: const Key('share_delete_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('share_delete_confirm'),
            style: FilledButton.styleFrom(backgroundColor: Palette.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await _service.remove(widget.card.id);
      if (!mounted) return;
      _toast('分享已删除');
    } on ShareException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _toast('链接已复制');
  }

  Future<void> _share(String url) async {
    try {
      await SharePlus.instance.share(ShareParams(text: url, subject: '角色卡分享'));
    } catch (e) {
      _toast('分享失败，请长按链接手动复制', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ShareScope.of(context);
    return AnimatedBuilder(
      animation: service.store,
      builder: (context, _) {
        final rec = service.store.forCard(widget.card.id);
        if (!service.configured) return _configCard();
        return rec == null ? _createCard() : _linkCard(rec);
      },
    );
  }

  /* ---------------- ① 未配置 ---------------- */

  Widget _configCard() {
    return SectionCard(
      key: const Key('share_unconfigured'),
      title: '云分享',
      subtitle: '未配置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '云分享需要先指定一个后端服务地址。「设置 → 分享服务地址」里填入你自己的服务地址即可开启。',
            style: TextStyle(
              fontSize: 12.5,
              color: Palette.textMute,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '不配置也完全不影响使用：角色卡始终保存在本机，可以用「导出角色 JSON」直接发给队友。',
            style: TextStyle(
              fontSize: 12.5,
              color: Palette.textMute,
              height: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('share_go_settings'),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
            // P12：行首 ⚙ 换成矢量图标（16dp，颜色继承按钮前景色）。
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.settings_outlined, size: 16),
                const SizedBox(width: 8),
                const Text('去设置里填写服务地址'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------- ② 已配置、未分享 ---------------- */

  Widget _createCard() {
    // ★ P7：规则名从当前卡动态取（与 buildSharePayload 同一口径），
    //   不写死 'COC 7th'；以后开放新规则时这里自动跟着变。
    final rid = RuleRegistry.effectiveId(widget.card.ruleSystemId);
    final ruleName = RuleRegistry.shortNameOf(rid);
    return SectionCard(
      key: const Key('share_unshared'),
      title: '云分享',
      subtitle: '未分享',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '生成一条只读链接，任何人打开都能看到这张卡（不能修改）。'
            '上传的是精简视图 —— 头像、自定义技能描述等大字段不会传。\n'
            '链接会带上当前规则标记：$ruleName。',
            style: TextStyle(
              fontSize: 12.5,
              color: Palette.textMute,
              height: 1.8,
            ),
          ),
          if (_error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error,
              key: const Key('share_error'),
              style: TextStyle(
                fontSize: 12,
                color: Palette.danger,
                height: 1.7,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('share_create'),
            onPressed: _busy ? null : _create,
            // P12：☁ 换成云上传图标；上传中保留同一颗图标，避免宽度跳动。
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_upload_outlined, size: 16),
                const SizedBox(width: 8),
                Text(_busy ? '上传中…' : '创建分享链接'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------- ③ 已分享 ---------------- */

  Widget _linkCard(ShareRecord rec) {
    return SectionCard(
      key: const Key('share_shared'),
      title: '云分享',
      subtitle: '已生成',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '分享链接（任何人可打开，只读）',
            style: TextStyle(fontSize: 11.5, color: Palette.textMute),
          ),
          const SizedBox(height: 5),
          Container(
            key: const Key('share_link_box'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: Palette.surface2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Palette.border),
            ),
            child: SelectableText(
              rec.url,
              style: TextStyle(
                fontSize: 12.5,
                color: Palette.teal,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 9),
          // ★ P7 云分享规则徽标：本机记录带字段就如实显示简称；
          //   老记录（上线前落盘、字段为空）不假装是 COC 7th，明确提示
          //   点「更新为当前版本」即可补上。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Palette.surface2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Palette.border),
            ),
            child: Text(
              rec.ruleShortName.isEmpty
                  ? '未标注规则（旧链接，可点『更新为当前版本』补上）'
                  : '规则徽标：${rec.ruleShortName}',
              key: const Key('share_rule_badge'),
              style: TextStyle(
                fontSize: 12,
                color: rec.ruleShortName.isEmpty
                    ? Palette.textMute
                    : Palette.goldStr,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: const Key('share_copy'),
                  onPressed: () => _copy(rec.url),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.content_copy, size: 16),
                      const SizedBox(width: 8),
                      const Text('复制链接'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('share_open'),
                  onPressed: () => _share(rec.url),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.open_in_new, size: 16),
                      const SizedBox(width: 8),
                      const Text('分享 / 打开'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '管理口令（删除该分享时需要，建议记下来）',
            style: TextStyle(fontSize: 11.5, color: Palette.textMute),
          ),
          const SizedBox(height: 4),
          SelectableText(
            rec.delToken.isEmpty ? '—' : rec.delToken,
            key: const Key('share_token'),
            style: TextStyle(
              fontSize: 12,
              color: Palette.goldStr,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '生成于 ${_fmtTime(rec.at)}',
            style: TextStyle(fontSize: 11, color: Palette.textMute),
          ),
          if (_error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error,
              key: const Key('share_error'),
              style: TextStyle(
                fontSize: 12,
                color: Palette.danger,
                height: 1.7,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  key: const Key('share_update'),
                  onPressed: _busy ? null : _create,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.refresh, size: 16),
                      const SizedBox(width: 8),
                      const Text('更新为当前版本'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('share_delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.danger,
                  ),
                  onPressed: _busy ? null : () => _remove(rec),
                  child: const Text('删除分享'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtTime(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p(int n) => n < 10 ? '0$n' : '$n';
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }
}
