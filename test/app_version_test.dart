// ============================================================
// app_version_test.dart — 版本号单一真源的守卫
//
// `lib/app_version.dart` 是展示用版本号的真源，`pubspec.yaml` 是构建用真源。
// 两处最容易「改了这边忘那边」，于是把「一致」变成一条会红的测试：
// 谁只改了一边，`flutter test` 立刻失败，比在真机上发现版本号不对要早得多。
// ============================================================

import 'dart:io';

import 'package:dice_realm/app_version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

void main() {
  group('版本号真源一致', () {
    test('app_version.dart 与 pubspec.yaml 的 version 逐字对齐', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final RegExp re = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
        multiLine: true,
      );
      final RegExpMatch? m = re.firstMatch(pubspec);
      expect(m, isNotNull,
          reason: 'pubspec.yaml 里找不到形如 `version: x.y.z+n` 的行');

      expect(
        kAppVersion,
        m!.group(1),
        reason: 'lib/app_version.dart 的 kAppVersion 与 pubspec 不一致',
      );
      expect(
        kAppBuildNumber,
        int.parse(m.group(2)!),
        reason: 'lib/app_version.dart 的 kAppBuildNumber 与 pubspec 不一致',
      );
    });

    test('展示标签由两个真值拼出，不手写', () {
      expect(kAppVersionShort, 'v$kAppVersion');
      expect(kAppVersionLabel, 'v$kAppVersion ($kAppBuildNumber)');
    });
  });

  group('首页显示版本号', () {
    testWidgets('首页头部有版本号且内容与真源一致', (tester) async {
      await pumpApp(tester);

      final Finder f = find.byKey(const Key('home_app_version'));
      expect(f, findsOneWidget, reason: '首页应常驻显示版本号');

      final Text t = tester.widget<Text>(f);
      expect(t.data, kAppVersionLabel);
      expect(t.data, contains(kAppVersion));
    });
  });
}
