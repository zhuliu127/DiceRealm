// ============================================================
// app_update_client.dart — 「检查更新」的网络与落盘（dart:io）
//
// 只做两件事：
//   1. fetchLatest()   GET 公开仓的 latest release，解析成 UpdateInfo。
//   2. downloadApk()   把 apk 流式下到临时目录，返回本地路径 + 进度回调。
//
// 为什么用 dart:io 的 HttpClient 而不引 http 包：
//   与 ai_probe_io.dart / net/http_io.dart 一致 —— 一条 GET、一条流式下载，
//   少一个依赖就少一处与 Flutter 版本的耦合。
//
// ★ 本文件在 io 边界，允许 dart:io；界面层只通过 [AppUpdateClient] 接口调它，
//   测试里换成假实现即可（不碰真实网络）。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/app_update.dart';

/// 一次下载的进度（0..1；total<=0 表示服务端没给 Content-Length）。
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});
  final int received;
  final int total;

  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  String get label {
    final r = (received / (1024 * 1024)).toStringAsFixed(1);
    if (total <= 0) return '已下载 $r MB';
    final t = (total / (1024 * 1024)).toStringAsFixed(1);
    return '$r / $t MB（${(fraction * 100).toStringAsFixed(0)}%）';
  }
}

/// 「检查更新」的可注入契约（界面依赖它，测试替换它）。
abstract class AppUpdateClient {
  /// 拉取最新 Release；失败抛 [AppUpdateException]（带可读中文原因）。
  Future<UpdateInfo> fetchLatest({required String currentVersion});

  /// 下载 apk 到临时目录；[onProgress] 实时回报进度。
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(DownloadProgress)? onProgress,
  });
}

class AppUpdateException implements Exception {
  AppUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 真实实现：打 GitHub 公开仓 API + 流式下载。
class HttpAppUpdateClient implements AppUpdateClient {
  HttpAppUpdateClient({
    this.owner = 'zhuliu127',
    this.repo = 'DiceRealm',
    this.timeout = const Duration(seconds: 20),
    this.downloadTimeout = const Duration(minutes: 5),
    this.apiBase = 'https://api.github.com',
  });

  final String owner;
  final String repo;
  final Duration timeout;
  final Duration downloadTimeout;
  final String apiBase;

  String get _latestUrl => '$apiBase/repos/$owner/$repo/releases/latest';

  @override
  Future<UpdateInfo> fetchLatest({required String currentVersion}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse(_latestUrl))
          .timeout(timeout);
      // GitHub API 要求 UA，否则 403
      req.headers.set('User-Agent', 'dice-realm-updater');
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      if (res.statusCode == 404) {
        throw AppUpdateException('仓库里还没有任何 Release');
      }
      if (res.statusCode != 200) {
        throw AppUpdateException('查询失败：HTTP ${res.statusCode}');
      }
      final parsed = parseReleaseJson(decodeJsonLoose(body));
      if (parsed == null) {
        throw AppUpdateException('返回内容无法解析（可能是接口被限流，稍后再试）');
      }
      return parsed;
    } on TimeoutException {
      throw AppUpdateException('连接超时，请检查网络或代理');
    } on SocketException catch (e) {
      throw AppUpdateException('网络不可用：${e.message.isEmpty ? e : e.message}');
    } on HandshakeException catch (e) {
      throw AppUpdateException('HTTPS 握手失败：${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    if (!info.hasApk) {
      throw AppUpdateException('这个 Release 没有附带 apk 安装包');
    }
    final dir = await Directory.systemTemp.createTemp('dice_update_');
    final safeName = info.apkUrl.split('/').last;
    final out = File('${dir.path}${Platform.pathSeparator}'
        '${safeName.isEmpty ? 'dice-realm-update.apk' : safeName}');

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse(info.apkUrl))
          .timeout(timeout);
      // GitHub release 下载会 302 到 objects.githubusercontent.com，dart:io 默认跟随后续。
      req.headers.set('User-Agent', 'dice-realm-updater');
      req.followRedirects = true;
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        throw AppUpdateException('下载失败：HTTP ${res.statusCode}');
      }
      final total = res.contentLength;
      final sink = out.openWrite();
      var received = 0;
      await for (final chunk in res.timeout(downloadTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received: received, total: total));
      }
      await sink.flush();
      await sink.close();
      return out;
    } on TimeoutException {
      throw AppUpdateException('下载超时（网络较慢的话多试一次）');
    } on SocketException catch (e) {
      throw AppUpdateException('下载中断：${e.message.isEmpty ? e : e.message}');
    } finally {
      client.close(force: true);
    }
  }
}

Object? decodeJsonLoose(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}
