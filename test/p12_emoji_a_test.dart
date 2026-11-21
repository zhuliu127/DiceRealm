// ============================================================
// p12_emoji_a_test.dart — P12：UI 里的 emoji 换成矢量图标
//
// 用户原话：「对 emoji 都替换掉，不太搭现在的风格」。
// 本文件只覆盖 A 组负责的页面：首页 / 名册 / 卡详情 / 云分享面板 / 设置页。
//
// 两个方向都断言，缺一不可：
//   ① **负向**：这些页面里渲染出来的 Text 不得再出现 emoji 字符
//      （扫的是 widget 树里的真实文本，不是源码字符串）；
//   ② **正向**：原来的 emoji 位置现在必须是 Material 图标 ——
//      只删不补会得到「光秃秃的按钮」，负向断言抓不到这种回归。
//
// ⚠️ 不做整棵树扫描的地方：卡详情「编辑态」会把 `lib/ui/card_edit/**`
//    （不属本批可改范围，仍带 emoji）整棵子树挂上来，扫了必然误报。
//    那里只断言提示条自己的图标 + 文案。
// ============================================================

import 'package:dice_realm/repo/share_store.dart';
import 'package:dice_realm/theme.dart';
import 'package:dice_realm/ui/share_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// emoji 的码位范围：补丁符号区（1F300-1FAFF）、杂项符号（2600-27BF，
/// 含 ☁ ⚙ ☠）、杂项符号与箭头（2B00-2BFF，含 ⬇ ⬆）、变体选择符 FE0F。
final RegExp _emoji = RegExp(
  r'[\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{1F300}-\u{1FAFF}]',
  unicode: true,
);

/// 当前渲染树里所有 Text 的纯文本（含 Text.rich 的 span 拼合结果）
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList(growable: false);

/// 断言这棵子树里没有任何 emoji 文本
void _expectNoEmoji(WidgetTester tester, String where) {
  final hits = _texts(tester).where(_emoji.hasMatch).toList(growable: false);
  expect(hits, isEmpty, reason: '$where 仍有 emoji 文本：$hits');
}

Widget _host(Widget child) => AppBackground(
  child: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

void main() {
  group('首页「数据」菜单', () {
    testWidgets('三项入口都是矢量图标，文案只剩中文', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'home_menu');

      // 负向：菜单里一个 emoji 都不许剩（原来的 ⬇ / ⬆ / ⚙）
      _expectNoEmoji(tester, '首页菜单');

      // 正向：图标必须在（只删不补 = 光秃秃的菜单项）
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
      expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

      // 文案去掉 emoji 与紧随的空格，只留文字
      expect(find.text('导出全部角色'), findsOneWidget);
      expect(find.text('导入角色 JSON'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });
  });

  group('角色卡详情', () {
    testWidgets('「⋯」菜单：导出 / 删除用矢量图标，文案无 emoji', (tester) async {
      await pumpCardDetail(tester);
      await tapKey(tester, 'card_menu');

      _expectNoEmoji(tester, '卡详情菜单');

      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('导出 JSON'), findsOneWidget);
      expect(find.text('删除角色'), findsOneWidget);
    });

    testWidgets('编辑态提示条：行首 ✎ 换成图标，正文不再带符号', (tester) async {
      await pumpCardDetail(tester);
      await tapKey(tester, 'btn_edit');

      // ⚠️ 不扫整棵树：编辑表单来自 card_edit/**（本批不可改，仍带 emoji）
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      expect(find.textContaining('正在编辑：'), findsOneWidget);
      expect(
        _texts(tester).where((t) => t.startsWith('✎')),
        isEmpty,
        reason: '提示文案不该再以 ✎ 开头',
      );
    });

    testWidgets('只读态（含底部云分享区）整页无 emoji', (tester) async {
      await pumpCardDetail(tester);
      _expectNoEmoji(tester, '卡详情只读态');
    });
  });

  group('云分享面板', () {
    testWidgets('未配置：⚙ → 图标，文案无 emoji', (tester) async {
      final share = ShareService(
        client: FakeShareApi(base: ''),
        store: await newMemoryShareStore(),
      );
      await pumpApp(
        tester,
        share: share,
        home: _host(SharePanel(card: validCard())),
      );

      expect(find.byKey(const Key('share_unconfigured')), findsOneWidget);
      _expectNoEmoji(tester, '分享面板 · 未配置');
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.text('去设置里填写服务地址'), findsOneWidget);
    });

    testWidgets('已配置：☁ → 云图标（创建后进入已分享态）', (tester) async {
      final api = FakeShareApi();
      final share = ShareService(
        client: api,
        store: await newMemoryShareStore(),
      );
      await pumpApp(
        tester,
        share: share,
        home: _host(SharePanel(card: validCard(id: 'cardP12'))),
      );

      expect(find.byKey(const Key('share_unshared')), findsOneWidget);
      _expectNoEmoji(tester, '分享面板 · 未分享');
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(find.text('创建分享链接'), findsOneWidget);

      await tapKey(tester, 'share_create');
      expect(find.byKey(const Key('share_shared')), findsOneWidget);
      _expectNoEmoji(tester, '分享面板 · 已分享');

      // 📋 复制 / ↗ 打开 / ↻ 更新 三个按钮各有一颗图标
      expect(find.byIcon(Icons.content_copy), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('分享 / 打开'), findsOneWidget);
      expect(find.text('更新为当前版本'), findsOneWidget);
    });
  });

  group('设置页 / 名册', () {
    testWidgets('设置页整页无 emoji', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'home_menu');
      await tapKey(tester, 'menu_settings');
      expect(find.text('外观 · 皮肤'), findsOneWidget, reason: '确实进了设置页');
      _expectNoEmoji(tester, '设置页');
    });

    testWidgets('名册空态靠插画，不渲染 emoji 文字', (tester) async {
      await pumpApp(tester); // 空仓库
      await tapKey(tester, 'home_roster_entry');
      expect(find.text('还没有角色卡，从上方「按流程车卡」开始'), findsOneWidget);

      _expectNoEmoji(tester, '名册空态');
      // 兜底参数还在（art 优先），但**不能**被画出来
      expect(find.text('📜'), findsNothing);
    });
  });
}
