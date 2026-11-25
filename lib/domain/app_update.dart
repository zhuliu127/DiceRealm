// ============================================================
// app_update.dart — 「检查更新」的纯逻辑（零 dart:io、零 Flutter 依赖）
//
// 为什么单独成一个纯文件：
//   · 版本比较、Release JSON 解析、挑哪个 apk 都能被单测钉死；
//   · 真正的网络 / 落盘 / 调起安装放 net 层与原生通道，界面只调这里。
//
// GitHub Release 的 `GET /repos/{owner}/{repo}/releases/latest` 返回体里有：
//   tag_name       形如 "v2.50.0"
//   name           发布标题（可能空）
//   body           Markdown 更新说明（可能空）
//   html_url       这个 Release 的网页地址（给「打不开安装器」时的兜底）
//   prerelease     true 表示预发布
//   assets[]       每个 { name, browser_download_url, size }
// ============================================================

/// 一次「检查更新」的解析结果（纯数据，不含网络）。
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.tagName,
    required this.title,
    required this.notes,
    required this.htmlUrl,
    required this.apkUrl,
    required this.apkSize,
    required this.prerelease,
  });

  /// 去掉前缀 v 的语义化版本，如 `2.50.0`
  final String latestVersion;

  /// 原始 tag，如 `v2.50.0`
  final String tagName;

  /// 发布标题（可能空串）
  final String title;

  /// 更新说明（Markdown，可能空串）
  final String notes;

  /// Release 网页地址（兜底用：安装器调不起来时让用户去网页下）
  final String htmlUrl;

  /// 直接下载 apk 的地址；找不到 apk asset 时为空串
  final String apkUrl;

  /// apk 字节数；未知为 0
  final int apkSize;

  /// 是否预发布
  final bool prerelease;

  bool get hasApk => apkUrl.isNotEmpty;
}

/// 把版本串拆成可比较的三段整数；解析不出的一律当 0。
///
/// 容忍：`v` 前缀、`2.50`（缺 patch 段）、`2.50.0+126`（带构建号）、
/// 末尾的 `-beta.1`（预发布后缀，按主版本号比，后缀不参与）。
List<int> parseVersionParts(String raw) {
  final s = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  // 砍掉 `+build` 与 `-prerelease`
  final core = s.split('+').first.split('-').first;
  final segs = core.split('.');
  final out = <int>[0, 0, 0];
  for (var i = 0; i < 3 && i < segs.length; i++) {
    out[i] = int.tryParse(segs[i].trim()) ?? 0;
  }
  return out;
}

/// 比较两个版本号：a>b 返回正、a<b 返回负、相等返回 0。
int compareVersions(String a, String b) {
  final pa = parseVersionParts(a);
  final pb = parseVersionParts(b);
  for (var i = 0; i < 3; i++) {
    final d = pa[i] - pb[i];
    if (d != 0) return d;
  }
  return 0;
}

/// 是否有更新：远端版本严格大于当前版本才算（相等 / 更旧都不提示）。
bool isUpdateAvailable({required String current, required String latest}) {
  return compareVersions(latest, current) > 0;
}

/// 从一个 apk 文件名猜它对应哪条 ABI（用于「有多个 apk asset」时的择优，
/// 本项目目前只发一个 universal apk，这里只是兜底不误选）。
bool _looksLikeApk(String name) => name.toLowerCase().endsWith('.apk');

/// 解析 GitHub Release JSON 为 [UpdateInfo]。
///
/// 找不到 tag_name 返回 null（不拿空数据冒充「已是最新」）。
/// apk 选取优先级：名字带 `universal` 的 → 第一个 .apk。
UpdateInfo? parseReleaseJson(Object? json) {
  if (json is! Map) return null;
  final tag = (json['tag_name'] ?? '').toString().trim();
  if (tag.isEmpty) return null;

  final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
  final title = (json['name'] ?? '').toString();
  final notes = (json['body'] ?? '').toString();
  final htmlUrl = (json['html_url'] ?? '').toString();
  final prerelease = json['prerelease'] == true;

  var apkUrl = '';
  var apkSize = 0;
  final assets = json['assets'];
  if (assets is List) {
    // 先找 universal 命名的 apk，再退回第一个 apk
    Map<Object?, Object?>? chosen;
    for (final a in assets) {
      if (a is Map && _looksLikeApk((a['name'] ?? '').toString())) {
        chosen = a;
        if ((a['name'] ?? '').toString().toLowerCase().contains('universal')) {
          break;
        }
      }
    }
    if (chosen != null) {
      apkUrl = (chosen['browser_download_url'] ?? '').toString();
      final sz = chosen['size'];
      if (sz is int) apkSize = sz;
      if (sz is num) apkSize = sz.toInt();
    }
  }

  return UpdateInfo(
    latestVersion: version,
    tagName: tag,
    title: title,
    notes: notes,
    htmlUrl: htmlUrl,
    apkUrl: apkUrl,
    apkSize: apkSize,
    prerelease: prerelease,
  );
}
