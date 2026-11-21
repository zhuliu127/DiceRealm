// ============================================================
// test/support/app_harness.dart — UI 测试的公共夹具
//
// 三件事：
//   · 造一个「临时目录 + 已 load」的仓库（不碰真实文档目录，也不用 mock 平台通道）
//   · 把测试窗口调大（默认 800×600 装不下整个向导，滚动查找又很脆）
//   · 换掉导入/导出的平台传输层（分享面板 / 文件选择器在测试环境没有实现）
// ============================================================

import 'dart:io';

import 'package:dice_realm/app.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/ai_probe.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/net/share_client.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/repo/share_store.dart';
import 'package:dice_realm/repo/repo_scope.dart';
import 'package:dice_realm/ui/card_transfer_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 临时目录里的空仓库（真实文件 I/O —— 只能在普通 test 里用）
Future<CharacterRepo> newTempRepo() async {
  final dir = await Directory.systemTemp.createTemp('dice_realm_test_');
  final repo = CharacterRepo(directory: dir);
  await repo.load();
  return repo;
}

/// 内存仓库（widget 测试用：fake-async 区域里真实 I/O 的 Future 永远不完成）
Future<CharacterRepo> newMemoryRepo() async {
  final repo = CharacterRepo(storage: MemoryStorage());
  await repo.load();
  return repo;
}

/// 内存设置仓库（widget 测试用；真实文件 I/O 在 fake-async 里永不完成）
Future<SettingsRepo> newMemorySettings({AiProbe? probe}) async {
  final repo = SettingsRepo(storage: MemorySettingsStorage(), probe: probe);
  await repo.load();
  return repo;
}

/// 内存分享仓库（widget 测试用）
Future<ShareStore> newMemoryShareStore() async {
  final s = ShareStore(storage: MemoryShareStorage());
  await s.load();
  return s;
}

/// 假分享接口：不联网，按队列回结果
class FakeShareApi implements ShareApi {
  FakeShareApi({
    this.base = 'https://share.example.com',
    this.createResult = const ShareCreateResult(
      id: 'sh_1',
      url: 'https://share.example.com/c/sh_1',
      delToken: 'tok-abc',
    ),
  });

  @override
  String base;

  ShareCreateResult createResult;

  /// 非 null 时 create 直接抛它
  ShareException? createError;

  /// 非 null 时 remove 直接抛它
  ShareException? removeError;

  int createCalls = 0;
  int removeCalls = 0;
  final List<String> removedTokens = <String>[];
  Character? lastCreated;

  @override
  bool get configured => base.isNotEmpty;

  @override
  Future<ShareCreateResult> create(Character c) async {
    createCalls++;
    lastCreated = c;
    final e = createError;
    if (e != null) throw e;
    return createResult;
  }

  @override
  Future<void> remove(String shareId, String token) async {
    removeCalls++;
    removedTokens.add(token);
    final e = removeError;
    if (e != null) throw e;
  }
}

/// 装一个假分享服务
Future<ShareService> useFakeShare(FakeShareApi api, {ShareStore? store}) async {
  final s = store ?? await newMemoryShareStore();
  return ShareService(client: api, store: s);
}

/// 假的 AI 探测：不联网，直接返回预设结果（并记录收到的参数）
class FakeAiProbe implements AiProbe {
  FakeAiProbe({
    this.result = const AiProbeResult(kind: AiProbeKind.ok, message: '已连接'),
  });

  AiProbeResult result;
  String? lastBase;
  String? lastModel;
  String? lastKey;
  int calls = 0;

  @override
  Future<AiProbeResult> test({
    required String base,
    required String model,
    required String key,
  }) async {
    calls++;
    lastBase = base;
    lastModel = model;
    lastKey = key;
    return result;
  }
}

/// 把测试窗口调成一台「高一点」的手机，避免控件落在折叠线以下
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 起 App 并等首帧。[repo] 不传就现造一个空仓库。
Future<CharacterRepo> pumpApp(
  WidgetTester tester, {
  CharacterRepo? repo,
  SettingsRepo? settings,
  ShareService? share,
  Widget? home,
}) async {
  useTallScreen(tester);
  final r = repo ?? await newMemoryRepo();
  final s = settings ?? await newMemorySettings();
  final sh =
      share ??
      ShareService(
        // 默认「未配置」：绝大多数 UI 用例不该因为分享而联网
        client: FakeShareApi(base: ''),
        store: await newMemoryShareStore(),
      );
  await tester.pumpWidget(
    DiceRealmApp(repo: r, settings: s, share: sh, home: home),
  );
  await tester.pumpAndSettle();
  return r;
}

/// 给「自己造裸 MaterialApp 宿主」的老用例补上三个 Scope。
///
/// P3-B 起 `StepSummary` 内嵌 `SharePanel`，其 build 第一行会调用
/// `ShareScope.of(context)`；裸宿主没有挂载任何 Scope，会命中 `repo_scope.dart`
/// 里的断言。真实 app 走 `DiceRealmApp`，`pumpApp` 也走它，都不受影响 —— 只有
/// 这两个「自己造宿主」的 P2 老用例需要补夹具。
///
/// 层级顺序与 [DiceRealmApp] 完全一致：RepoScope → SettingsScope →
/// ShareScope → child。后端一律内存实现，分享服务用 `FakeShareApi(base: '')`
/// （未配置），保证测试里绝不联网、也不触发真实上传。
///
/// 只在测试侧补挂载，不触碰产品代码：`ShareScope.of` 的断言原样保留，
/// 真实 app 若漏挂 Scope 依旧会在启动/构建时立刻抛错，不会被静默吞掉。
Future<Widget> wrapWithScopes(Widget child) async {
  final repo = await newMemoryRepo();
  final settings = await newMemorySettings();
  final share = await useFakeShare(FakeShareApi(base: ''));
  return RepoScope(
    repo: repo,
    child: SettingsScope(
      repo: settings,
      child: ShareScope(service: share, child: child),
    ),
  );
}

/// 点某个 key 并等动画
Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// 假传输层：把导出的 JSON 记下来，把预设的文本当成"用户选中的文件"
class FakeCardTransferIo implements CardTransferIo {
  FakeCardTransferIo({this.importPayload});

  /// `importText()` 要返回的文本（null = 模拟用户取消）
  String? importPayload;

  /// 最后一次导出的文件名 / 内容
  String? lastFileName;
  String? lastJson;
  int exportCount = 0;

  @override
  Future<String?> export(String fileName, String json) async {
    exportCount++;
    lastFileName = fileName;
    lastJson = json;
    return '/tmp/$fileName';
  }

  @override
  Future<String?> importText() async => importPayload;
}

/// 装一个假传输层，并在用例结束时还原全局实例
FakeCardTransferIo useFakeTransferIo({String? importPayload}) {
  final io = FakeCardTransferIo(importPayload: importPayload);
  final previous = cardTransferIo;
  cardTransferIo = io;
  addTearDown(() => cardTransferIo = previous);
  return io;
}

/// 一张属性齐备、已 recalc、可以直接落库的卡
Character validCard({
  String id = 'card0001',
  String name = '测试调查员',
  String player = '老王',
}) {
  final c = Character(newCharacter());
  c.raw['id'] = id;
  c.raw['characterName'] = name;
  c.raw['playerName'] = player;
  c.basicInfo['age'] = 32;
  c.raw['age'] = 32;
  c.basicInfo['occupationName'] = '记者';
  c.raw['occupationId'] = 'occ67';
  for (final k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
    'luck',
  ]) {
    c.attributes[k] = 50;
  }
  recalc(c);
  return c;
}

/// 起 App 并直接进某张卡的详情页
///
/// ★ P8：角色卡从首页收进了二级页「角色档案」（`RosterPage`，首页入口
/// `home_roster_entry`）。卡片不再直接铺在首页，所以这里要先点入口进名册，
/// 再点卡名。这不是放宽断言 —— 详情页的覆盖范围一点没变，只是多一跳。
///
/// ★ P10 需求 2：名册按入口分栏（已保存 / 英灵殿），已撕的卡只出现在英灵殿
/// 那一栏，所以入口要按卡片状态选 —— 同样不是放宽：进的还是同一个详情页。
Future<CharacterRepo> pumpCardDetail(
  WidgetTester tester, {
  Character? card,
}) async {
  final repo = await newMemoryRepo();
  final c = card ?? validCard();
  await repo.save(c);
  await pumpApp(tester, repo: repo);
  await tester.tap(
    find.byKey(
      Key(isRippedCard(c) ? 'home_roster_valhalla' : 'home_roster_entry'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(c.characterName.isEmpty ? '无名调查员' : c.characterName).first,
  );
  await tester.pumpAndSettle();
  return repo;
}

/// 把某个 key 滚进可视区域（ListView 是懒构建的，屏幕外的控件不在树里）
Future<void> scrollTo(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}
