// ============================================================
// test/p22_app_update_test.dart — 「检查更新」纯逻辑
//
// 覆盖：版本号解析、版本比较、是否有更新、GitHub Release JSON 解析。
// 这些都是无 IO 的纯函数，最容易回归，必须钉死。
// ============================================================

import 'package:dice_realm/domain/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseVersionParts', () {
    test('去掉 v 前缀与 +build / -prerelease 尾巴', () {
      expect(parseVersionParts('v2.49.2'), <int>[2, 49, 2]);
      expect(parseVersionParts('2.49.2+124'), <int>[2, 49, 2]);
      expect(parseVersionParts('v2.50.0-beta.1'), <int>[2, 50, 0]);
    });

    test('缺段补 0，垃圾输入按 0 处理（长度恒为 3，供比较用）', () {
      expect(parseVersionParts('2.5'), <int>[2, 5, 0]);
      expect(parseVersionParts('2'), <int>[2, 0, 0]);
      expect(parseVersionParts(''), <int>[0, 0, 0]);
      expect(parseVersionParts('abc'), <int>[0, 0, 0]);
    });
  });

  group('compareVersions', () {
    test('逐段比较，前面的段优先', () {
      expect(compareVersions('2.49.2', '2.49.1'), greaterThan(0));
      expect(compareVersions('2.49.1', '2.49.2'), lessThan(0));
      expect(compareVersions('2.49.2', '2.49.2'), 0);
      expect(compareVersions('v2.50.0', '2.49.9'), greaterThan(0));
      expect(compareVersions('3.0.0', '2.99.99'), greaterThan(0));
    });

    test('缺段按 0 处理', () {
      expect(compareVersions('2.49', '2.49.0'), 0);
      expect(compareVersions('2.49.1', '2.49'), greaterThan(0));
    });
  });

  group('isUpdateAvailable', () {
    test('远端更高才算有更新', () {
      expect(isUpdateAvailable(current: '2.49.2', latest: '2.50.0'), isTrue);
      expect(isUpdateAvailable(current: '2.49.2', latest: '2.49.2'), isFalse);
      expect(isUpdateAvailable(current: '2.49.2', latest: '2.49.1'), isFalse);
    });
  });

  group('parseReleaseJson', () {
    test('解析 tag / 标题 / 说明 / 页面 / apk 资源', () {
      final info = parseReleaseJson(<String, dynamic>{
        'tag_name': 'v2.50.0',
        'name': '骰境TRPG v2.50.0',
        'body': '## 更新\n- 检查更新\n- 头像修复',
        'html_url': 'https://github.com/zhuliu127/DiceRealm/releases/tag/v2.50.0',
        'prerelease': false,
        'assets': <dynamic>[
          <String, dynamic>{
            'name': 'dice-realm-v2.50.0.apk',
            'browser_download_url':
                'https://github.com/zhuliu127/DiceRealm/releases/download/v2.50.0/dice-realm-v2.50.0.apk',
            'size': 72046846,
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.latestVersion, '2.50.0');
      expect(info.tagName, 'v2.50.0');
      expect(info.title, '骰境TRPG v2.50.0');
      expect(info.notes, contains('检查更新'));
      expect(info.htmlUrl, contains('releases/tag/v2.50.0'));
      expect(info.hasApk, isTrue);
      expect(info.apkUrl, endsWith('.apk'));
      expect(info.apkSize, 72046846);
      expect(info.prerelease, isFalse);
    });

    test('多个 apk 优先选 universal 命名', () {
      final info = parseReleaseJson(<String, dynamic>{
        'tag_name': 'v2.50.0',
        'assets': <dynamic>[
          <String, dynamic>{
            'name': 'dice-realm-v2.50.0-arm64.apk',
            'browser_download_url': 'https://x/a-arm64.apk',
            'size': 10,
          },
          <String, dynamic>{
            'name': 'dice-realm-v2.50.0-universal.apk',
            'browser_download_url': 'https://x/a-universal.apk',
            'size': 20,
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.apkUrl, endsWith('a-universal.apk'));
    });

    test('没有 apk 资源时 hasApk 为 false', () {
      final info = parseReleaseJson(<String, dynamic>{
        'tag_name': 'v2.50.0',
        'assets': <dynamic>[],
      });
      expect(info, isNotNull);
      expect(info!.hasApk, isFalse);
    });

    test('缺少 tag_name 视为无法解析', () {
      expect(parseReleaseJson(<String, dynamic>{'name': 'x'}), isNull);
      expect(parseReleaseJson(null), isNull);
    });

    test('tag 不带 v 也能解析版本', () {
      final info = parseReleaseJson(<String, dynamic>{
        'tag_name': '2.51.0',
        'assets': <dynamic>[],
      });
      expect(info!.latestVersion, '2.51.0');
    });
  });
}
