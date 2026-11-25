// ============================================================
// test/p22_update_sheet_test.dart — 「检查更新」弹层 UI 流转
//
// 用假的 AppUpdateClient / ApkInstaller 注入，验证：
//   ① 无更新 → 显示「已是最新版本」；
//   ② 有更新 → 显示新版 tag + 说明 + 「下载并安装」；
//   ③ 点下载 → 进度推进 → 下载完成 → 调起安装器（can=false 时只到 ready）；
//   ④ 查询失败 → 显示错误 + 重试可再查。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/app_update.dart';
import 'package:dice_realm/net/apk_installer.dart';
import 'package:dice_realm/net/app_update_client.dart';
import 'package:dice_realm/ui/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements AppUpdateClient {
  _FakeClient({
    this.info,
    this.error,
    this.downloadError,
  });

  UpdateInfo? info;
  String? error;
  String? downloadError;
  int fetchCount = 0;
  String? lastCurrentVersion;

  @override
  Future<UpdateInfo> fetchLatest({required String currentVersion}) async {
    fetchCount += 1;
    lastCurrentVersion = currentVersion;
    if (error != null) throw AppUpdateException(error!);
    return info!;
  }

  @override
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(DownloadProgress p)? onProgress,
  }) async {
    for (final f in <double>[0.5, 1.0]) {
      onProgress?.call(DownloadProgress(
        received: (f * 100).round(),
        total: 100,
      ));
    }
    if (downloadError != null) throw AppUpdateException(downloadError!);
    return File('${Directory.systemTemp.path}/fake_update.apk');
  }
}

class _FakeInstaller implements ApkInstaller {
  _FakeInstaller({this.canInstall = true, this.installOk = true});

  bool canInstall;
  bool installOk;
  int installCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<bool> canRequestInstall() async => canInstall;

  @override
  Future<bool> installApk(String path) async {
    installCalls += 1;
    return installOk;
  }

  @override
  Future<bool> openUnknownSourcesSettings() async {
    openSettingsCalls += 1;
    return true;
  }
}

UpdateInfo _info(String version, {bool withApk = true}) => UpdateInfo(
      latestVersion: version,
      tagName: 'v$version',
      title: '骰境TRPG v$version',
      notes: '· 新增检查更新\n· 修复头像更换',
      htmlUrl: 'https://github.com/zhuliu127/DiceRealm/releases/tag/v$version',
      apkUrl: withApk
          ? 'https://github.com/zhuliu127/DiceRealm/releases/download/v$version/dice-realm-v$version.apk'
          : '',
      apkSize: 72000000,
      prerelease: false,
    );

Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showUpdateSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump(); // 打开 bottom sheet 动画开始
  await tester.pump(const Duration(milliseconds: 350)); // 动画结束
}

void main() {
  late AppUpdateClient savedClient;
  late ApkInstaller savedInstaller;

  setUp(() {
    savedClient = appUpdateClient;
    savedInstaller = apkInstaller;
  });

  tearDown(() {
    appUpdateClient = savedClient;
    apkInstaller = savedInstaller;
  });

  testWidgets('无更新时显示「已是最新版本」', (WidgetTester tester) async {
    appUpdateClient = _FakeClient(info: _info('0.0.1'));
    apkInstaller = _FakeInstaller();
    await _pumpSheet(tester);
    await tester.pumpAndSettle();

    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.byKey(const Key('update_download')), findsNothing);
  });

  testWidgets('有更新时显示版本、说明与下载按钮', (WidgetTester tester) async {
    appUpdateClient = _FakeClient(info: _info('99.0.0'));
    apkInstaller = _FakeInstaller();
    await _pumpSheet(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('发现新版本'), findsOneWidget);
    expect(find.textContaining('v99.0.0'), findsWidgets);
    expect(find.textContaining('新增检查更新'), findsOneWidget);
    expect(find.byKey(const Key('update_download')), findsOneWidget);
  });

  testWidgets('下载→安装器可装→调起安装', (WidgetTester tester) async {
    appUpdateClient = _FakeClient(info: _info('99.0.0'));
    final installer = _FakeInstaller(canInstall: true, installOk: true);
    apkInstaller = installer;
    await _pumpSheet(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('update_download')));
    await tester.pump(); // 进入 downloading
    await tester.pumpAndSettle(); // 下载完成 + 调起安装

    expect(installer.installCalls, 1);
    expect(find.text('下载完成'), findsOneWidget);
  });

  testWidgets('未授权「安装未知应用」时停在下载完成并给去设置按钮',
      (WidgetTester tester) async {
    appUpdateClient = _FakeClient(info: _info('99.0.0'));
    final installer = _FakeInstaller(canInstall: false);
    apkInstaller = installer;
    await _pumpSheet(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('update_download')));
    await tester.pumpAndSettle();

    expect(installer.installCalls, 0);
    expect(find.text('下载完成'), findsOneWidget);
    expect(find.byKey(const Key('update_open_settings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('update_open_settings')));
    await tester.pumpAndSettle();
    expect(installer.openSettingsCalls, 1);
  });

  testWidgets('查询失败显示错误，点重试再次查询', (WidgetTester tester) async {
    final client = _FakeClient(error: '查询失败：HTTP 500');
    appUpdateClient = client;
    apkInstaller = _FakeInstaller();
    await _pumpSheet(tester);
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败'), findsOneWidget);
    expect(find.byKey(const Key('update_retry')), findsOneWidget);
    expect(client.fetchCount, 1);

    // 重试：这次让它成功
    client.error = null;
    client.info = _info('99.0.0');
    await tester.tap(find.byKey(const Key('update_retry')));
    await tester.pumpAndSettle();
    expect(client.fetchCount, 2);
    expect(find.byKey(const Key('update_download')), findsOneWidget);
  });

  testWidgets('下载失败显示错误', (WidgetTester tester) async {
    appUpdateClient = _FakeClient(
      info: _info('99.0.0'),
      downloadError: '下载失败：连接被重置',
    );
    apkInstaller = _FakeInstaller();
    await _pumpSheet(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('update_download')));
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败'), findsOneWidget);
    expect(find.textContaining('连接被重置'), findsOneWidget);
  });

  testWidgets('没有apk资源时下载报错', (WidgetTester tester) async {
    appUpdateClient = _FakeClient(info: _info('99.0.0', withApk: false));
    apkInstaller = _FakeInstaller();
    await _pumpSheet(tester);
    await tester.pumpAndSettle();

    // 没有 apk 时下载按钮其实仍会显示（hasApk=false 时点击提示去网页下载）
    final dl = find.byKey(const Key('update_download'));
    if (dl.evaluate().isNotEmpty) {
      await tester.tap(dl);
      await tester.pumpAndSettle();
      expect(find.textContaining('没有附带 apk'), findsOneWidget);
    }
  });
}
