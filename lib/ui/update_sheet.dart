// ============================================================
// lib/ui/update_sheet.dart — 「检查更新」弹层（首页菜单进入）
//
// 流程：
//   ① 一进来就查 GitHub 公开仓 latest release；
//   ② 无更新 → 显示「已是最新（vX）」；
//   ③ 有更新 → 显示版本 + 更新说明 + 「下载并安装」；
//   ④ 点「下载并安装」→ 进度条下载 apk → 交给系统安装器（原生通道）；
//      若系统不允许「安装未知应用」，给一个「去开启」按钮跳授权页。
//
// ★ 网络与安装都走可注入端口（[appUpdateClient] / [apkInstaller]），
//   测试里换成假实现即可，不碰真实网络 / 通道。
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../domain/app_update.dart';
import '../net/apk_installer.dart';
import '../net/app_update_client.dart';
import '../theme.dart';

/// 全局可替换的「检查更新」客户端（测试用完在 tearDown 还原）。
AppUpdateClient appUpdateClient = HttpAppUpdateClient();

/// 全局可替换的安装器（测试用完在 tearDown 还原）。
ApkInstaller apkInstaller = const ApkInstaller();

/// 打开「检查更新」弹层。
Future<void> showUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext _) => const UpdateSheet(),
  );
}

class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key});

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

enum _Phase { checking, upToDate, available, downloading, ready, error }

class _UpdateSheetState extends State<UpdateSheet> {
  _Phase _phase = _Phase.checking;
  UpdateInfo? _info;
  String _error = '';
  double _progress = 0;
  String _progressLabel = '';
  File? _apkFile;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _error = '';
    });
    try {
      final info = await appUpdateClient.fetchLatest(
        currentVersion: kAppVersion,
      );
      if (!mounted) return;
      final has = isUpdateAvailable(current: kAppVersion, latest: info.latestVersion);
      setState(() {
        _info = info;
        _phase = has ? _Phase.available : _Phase.upToDate;
      });
    } on AppUpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final info = _info;
    if (info == null) return;
    if (!info.hasApk) {
      setState(() {
        _phase = _Phase.error;
        _error = '这个版本没有附带 apk 安装包，请到网页手动下载。';
      });
      return;
    }
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _progressLabel = '准备下载…';
    });
    try {
      final file = await appUpdateClient.downloadApk(
        info,
        onProgress: (DownloadProgress p) {
          if (!mounted) return;
          setState(() {
            _progress = p.fraction;
            _progressLabel = p.label;
          });
        },
      );
      if (!mounted) return;
      _apkFile = file;

      // 检查「安装未知应用」是否已授权
      final canInstall = await apkInstaller.canRequestInstall();
      if (!mounted) return;
      if (!canInstall) {
        setState(() => _phase = _Phase.ready);
        return;
      }
      await _launchInstaller(file);
    } on AppUpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  Future<void> _launchInstaller(File file) async {
    final ok = await apkInstaller.installApk(file.path);
    if (!mounted) return;
    if (ok) {
      setState(() => _phase = _Phase.ready);
    } else {
      setState(() {
        _phase = _Phase.ready;
        _error = '没能拉起安装器，可能需要在系统设置里允许本应用安装应用。';
      });
    }
  }

  Future<void> _openUnknownSources() async {
    await apkInstaller.openUnknownSourcesSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Palette.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        border: Border(
          top: BorderSide(color: Palette.gold.withValues(alpha: 0.5), width: 1.2),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        14,
        18,
        18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.system_update_alt, size: 20, color: Palette.gold),
                const SizedBox(width: 8),
                Text(
                  '检查更新',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.goldStr,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('update_close'),
                  icon: const Icon(Icons.close, size: 20),
                  color: Palette.textMute,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '当前版本 $kAppVersionLabel',
              style: TextStyle(fontSize: 12, color: Palette.textMute),
            ),
            const SizedBox(height: 14),
            _body(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.checking:
        return Row(
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('正在检查最新版本…',
                style: TextStyle(fontSize: 13, color: Palette.textDim)),
          ],
        );

      case _Phase.upToDate:
        return _message(
          icon: Icons.check_circle_outline,
          color: Palette.success,
          title: '已是最新版本',
          detail: '你用的 $kAppVersionLabel 就是当前最新版。',
        );

      case _Phase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _message(
              icon: Icons.error_outline,
              color: Palette.danger,
              title: '检查更新失败',
              detail: _error,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('update_retry'),
                    onPressed: _check,
                    child: const Text('重试'),
                  ),
                ),
                if (_info != null && _info!.htmlUrl.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonal(
                      key: const Key('update_open_page'),
                      onPressed: () => _openUnknownSources(),
                      child: const Text('去设置'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );

      case _Phase.available:
        final info = _info!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _message(
              icon: Icons.rocket_launch_outlined,
              color: Palette.gold,
              title: '发现新版本 ${info.tagName}',
              detail: info.title.isNotEmpty ? info.title : null,
            ),
            if (info.notes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Palette.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: Palette.border),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.notes.trim(),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: Palette.textDim,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('update_download'),
              onPressed: _downloadAndInstall,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('下载并安装'),
            ),
          ],
        );

      case _Phase.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('正在下载新版本…',
                style: TextStyle(fontSize: 13, color: Palette.textDim)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 6,
                backgroundColor: Palette.surface2,
                valueColor: AlwaysStoppedAnimation<Color>(Palette.gold),
              ),
            ),
            const SizedBox(height: 8),
            Text(_progressLabel,
                key: const Key('update_progress_label'),
                style: TextStyle(fontSize: 12, color: Palette.textMute)),
          ],
        );

      case _Phase.ready:
        final info = _info!;
        final canRetry = _apkFile != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _message(
              icon: Icons.download_done_outlined,
              color: Palette.success,
              title: '下载完成',
              detail: _error.isEmpty
                  ? '请在弹出的系统界面点「安装」。若没弹出来，点下面的按钮再试一次。'
                  : _error,
            ),
            const SizedBox(height: 14),
            if (canRetry)
              FilledButton.icon(
                key: const Key('update_install_again'),
                onPressed: () => _launchInstaller(_apkFile!),
                icon: const Icon(Icons.install_desktop, size: 18),
                label: const Text('重新调起安装'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('update_open_settings'),
              onPressed: _openUnknownSources,
              child: const Text('去开启「安装未知应用」'),
            ),
            if (info.htmlUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '也可以到 Release 页面手动下载：${info.htmlUrl}',
                style: TextStyle(
                  fontSize: 11,
                  color: Palette.textMute,
                  height: 1.5,
                ),
              ),
            ],
          ],
        );
    }
  }

  Widget _message({
    required IconData icon,
    required Color color,
    required String title,
    String? detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Palette.text,
                ),
              ),
              if (detail != null && detail.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Palette.textDim,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
