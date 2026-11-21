// ============================================================
// share_panel_test.dart — 云分享面板（widget，注入假接口，不联网）
//
// 三种状态 + 两个硬约束：
//   · 未配置 shareBase → 只给引导，**一个请求都不发**
//   · 已分享 → 链接 / 口令可见，可复制、可删除（**要二次确认**）
//   · 失败 → 显示可读错误，不是静默失败
// ============================================================

import 'package:dice_realm/net/share_client.dart';
import 'package:dice_realm/repo/share_store.dart';
import 'package:dice_realm/ui/settings_page.dart';
import 'package:dice_realm/ui/share_panel.dart';
import 'package:dice_realm/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

Widget host(Widget child) => AppBackground(
  child: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

void main() {
  testWidgets('未配置 shareBase：只给引导，点「去设置」进设置页，且不发请求', (tester) async {
    final api = FakeShareApi(base: '');
    final store = await newMemoryShareStore();
    final share = ShareService(client: api, store: store);
    final card = validCard();

    await pumpApp(
      tester,
      share: share,
      home: host(SharePanel(card: card)),
    );

    expect(find.byKey(const Key('share_unconfigured')), findsOneWidget);
    expect(
      find.byKey(const Key('share_create')),
      findsNothing,
      reason: '未配置时不该摆上传按钮',
    );
    // 要说明「不开也能用」
    expect(find.textContaining('本机'), findsWidgets);

    await tapKey(tester, 'share_go_settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(api.createCalls, 0, reason: '未配置时绝不能发请求');
  });

  testWidgets('已配置：创建分享 → 链接与口令都显示，记录落本机', (tester) async {
    final api = FakeShareApi();
    final store = await newMemoryShareStore();
    final share = ShareService(client: api, store: store);
    final card = validCard(id: 'cardX');

    await pumpApp(
      tester,
      share: share,
      home: host(SharePanel(card: card)),
    );

    expect(find.byKey(const Key('share_unshared')), findsOneWidget);
    await tapKey(tester, 'share_create');

    expect(api.createCalls, 1);
    expect(api.lastCreated?.id, 'cardX');
    expect(find.byKey(const Key('share_shared')), findsOneWidget);
    expect(
      find.textContaining('https://share.example.com/c/sh_1'),
      findsWidgets,
    );
    // 口令要露出来（旧版提示「建议记下来」）
    final token = tester.widget<SelectableText>(
      find.byKey(const Key('share_token')),
    );
    expect(token.data, 'tok-abc');
    // 本机记录 + 卡上的 shareId
    expect(store.forCard('cardX')?.id, 'sh_1');
    expect(card.raw['shareId'], 'sh_1');
  });

  testWidgets('删除分享要二次确认：取消不动，确认才删', (tester) async {
    final api = FakeShareApi();
    final store = await newMemoryShareStore();
    final share = ShareService(client: api, store: store);
    final card = validCard(id: 'cardY');
    await pumpApp(
      tester,
      share: share,
      home: host(SharePanel(card: card)),
    );

    await tapKey(tester, 'share_create');
    expect(store.forCard('cardY'), isNotNull);

    // 先取消
    await tapKey(tester, 'share_delete');
    expect(find.byKey(const Key('share_delete_confirm')), findsOneWidget);
    await tapKey(tester, 'share_delete_cancel');
    expect(api.removeCalls, 0);
    expect(store.forCard('cardY'), isNotNull, reason: '点取消不该删');

    // 再确认
    await tapKey(tester, 'share_delete');
    await tapKey(tester, 'share_delete_confirm');
    expect(api.removeCalls, 1);
    expect(store.forCard('cardY'), isNull, reason: '确认删除后本机记录必须清掉');
    expect(find.byKey(const Key('share_unshared')), findsOneWidget);
  });

  testWidgets('创建失败 → 显示可读错误，不静默', (tester) async {
    final api = FakeShareApi()
      ..createError = ShareException(ShareErrorKind.http, '服务器返回 500：boom');
    final share = ShareService(client: api, store: await newMemoryShareStore());
    await pumpApp(
      tester,
      share: share,
      home: host(SharePanel(card: validCard())),
    );

    await tapKey(tester, 'share_create');
    expect(find.byKey(const Key('share_error')), findsOneWidget);
    final err = tester.widget<Text>(find.byKey(const Key('share_error')));
    expect(err.data, contains('500'));
    // 失败后仍然是「未分享」状态，可以再点
    expect(find.byKey(const Key('share_unshared')), findsOneWidget);
  });

  testWidgets('删除失败 → 保留记录（还能重试）', (tester) async {
    final api = FakeShareApi();
    final store = await newMemoryShareStore();
    final share = ShareService(client: api, store: store);
    final card = validCard(id: 'cardZ');
    await pumpApp(
      tester,
      share: share,
      home: host(SharePanel(card: card)),
    );

    await tapKey(tester, 'share_create');
    api.removeError = ShareException(ShareErrorKind.http, '删除失败（403）');
    await tapKey(tester, 'share_delete');
    await tapKey(tester, 'share_delete_confirm');

    expect(store.forCard('cardZ'), isNotNull);
    final err = tester.widget<Text>(find.byKey(const Key('share_error')));
    expect(err.data, contains('403'));
  });

  testWidgets('角色卡详情页里也有云分享面板', (tester) async {
    final api = FakeShareApi(base: '');
    ShareService(client: api, store: await newMemoryShareStore());
    await pumpCardDetail(tester);
    // 详情页是长列表，滚到底部才能看到分享面板
    await tester.scrollUntilVisible(
      find.byKey(const Key('share_unconfigured'), skipOffstage: false),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share_unconfigured')), findsOneWidget);
  });
}
