// ============================================================
// test/p20_offline_no_regression_test.dart — P20 QA 契约 C/E 组
//
// 严过关（QA）独立编写。核心命题：**P20 新增联网续玩能力，但不得让
// v2.32.0 的纯本机续玩路径有半点回归**。
//
//   C10 有凭据 hasBase → 必弹弹窗；三选项齐全；默认选中优先级；零令牌回显
//   C11 取消 → ResumeChoice.cancelled，凭据内容/mtime 不变、存档槽不变、
//       不进离线副本、零网络
//   C12 主动选「仅本机离线副本」→ 横幅「已载入本机存档」不含「未能连回」；
//       无凭据 / hasBase=false → 不弹窗，直接既有 resumeLocalRoom，
//       房间内容 / 横幅 / migrated 提示 / RoomEntryKeys.resumeLoad(key)
//       与 v2.32.0 基线逐字节一致
//   E 版本 / 冻结文件 / pubspec.lock / 无 skip / p10:350-362 逐字未改 /
//       全仓 NUL 扫描
//
// 静态断言全部用**可读文本检索**（语义比对区块字节），不用哈希代替语义。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File, Platform;

import 'package:dice_realm/domain/js_compat.dart' show asMap, jsStr;
import 'package:dice_realm/domain/room_ports.dart' show RoomSaveStore;
import 'package:dice_realm/domain/room_types.dart' show RoomRole;
import 'package:dice_realm/net/cloud_room.dart'
    show CloudHttpResponse, CloudHttpTransport, cloudHttp;
import 'package:dice_realm/net/cloud_room_backup.dart'
    show clearActiveCloudBackup;
import 'package:dice_realm/repo/recent_room_credential.dart'
    show
        FileRecentCredentialStorage,
        MemoryRecentCredentialStorage,
        RecentCredentialStorage,
        RecentRoomCredential,
        recentCredentialStore,
        saveRecentCredential;
import 'package:dice_realm/repo/room_save_store.dart'
    show InMemoryRoomSaveStore, RoomSaveStoreMutable;
import 'package:dice_realm/ui/room/room_boot.dart'
    show bootLocalRoom, roomSaveSlots;
import 'package:dice_realm/ui/room/room_entry_page.dart'
    show RoomEntryKeys, RoomEntryPage;
import 'package:dice_realm/ui/room/room_net_factory.dart' show RoomNetFactory;
import 'package:dice_realm/ui/room/room_resume.dart' show RoomResumeService;
import 'package:dice_realm/ui/room/room_scope.dart' show RoomScope;
import 'package:dice_realm/ui/room/save_time.dart' show saveTimeText;
import 'package:dice_realm/ui/room/resume_mode_dialog.dart'
    show
        ResumeChoice,
        ResumeDialogKeys,
        ResumeMode,
        showResumeModeDialog;
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart'
    show autoAvatarPngEncoder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' show pumpApp;
import 'support/room_ui_harness.dart' show useRoomScreen;

// ------------------------------------------------------------
// 工具
// ------------------------------------------------------------

class _ZeroHttp implements CloudHttpTransport {
  int calls = 0;

  @override
  Future<CloudHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    calls++;
    return const CloudHttpResponse(ok: false, error: 'SHOULD-NOT-CALL');
  }
}

/// 只读存档后端：能塞数据、能读，但**不实现** [RoomSaveStoreMutable]。
/// 用来证明「后端不支持删除时，入口页连删除按钮都不渲染」。
class _ReadOnlySaveStore implements RoomSaveStore {
  final InMemoryRoomSaveStore _inner = InMemoryRoomSaveStore();

  @override
  void put(String code, Map<String, Object?> data) => _inner.put(code, data);

  @override
  Map<String, Object?>? get(String code) => _inner.get(code);

  @override
  List<String> list() => _inner.list();
}

Future<Map<String, Object?>> _realSave(String code) async {
  final boot = await bootLocalRoom(code: code, name: '离线回归团', nickname: '老K');
  final save = boot.session.exportSave();
  boot.dispose();
  return save!;
}

/// 从源码里按"起始标记 + 花括号配对"精确抠出一个类/函数区块。
/// 用语义区块比对（不是整文件哈希），才能证明"禁改区段零改动"。
String _block(String src, String marker, {int from = 0}) {
  final int i = src.indexOf(marker, from);
  if (i < 0) return '';
  final int open = src.indexOf('{', i);
  if (open < 0) return '';
  int depth = 0;
  for (int k = open; k < src.length; k++) {
    if (src.codeUnitAt(k) == 0x7B) depth++;
    if (src.codeUnitAt(k) == 0x7D) {
      depth--;
      if (depth == 0) return src.substring(i, k + 1);
    }
  }
  return '';
}

String? _baseline(String rel) {
  final List<String> candidates = <String>[
    'C:/Users/60965/WorkBuddy/2026-11-08-13-25-14/$rel',
    '${Directory.current.parent.parent.path.replaceAll('\\', '/')}'
        '/2026-11-08-13-25-14/$rel',
  ];
  for (final String p in candidates) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

/// 顶部横幅文本（key 挂在容器上，Text 是子节点）。
String _bannerText(WidgetTester tester) {
  final Finder f = find.descendant(
    of: find.byKey(RoomEntryKeys.banner),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(f).data ?? '';
}

/// 把所有 Text 的文案拼起来，用来证明弹窗零令牌回显。
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void _stubAutoAvatarPng() {
  final saved = autoAvatarPngEncoder;
  addTearDown(() => autoAvatarPngEncoder = saved);
  autoAvatarPngEncoder = (spec) async => '';
}

const String kCode = 'AB12CD';
const String kBase = 'https://relay.example.com/room';
const String kHostToken = 'HT-NEVER-ECHO-4d81';
const String kDeviceId = 'fl-deadbeefdeadbeef';
const String kSaveKey = 'SLOT-QA-01';

final CloudHttpTransport _origHttp = cloudHttp;
final RecentCredentialStorage _origCredStore = recentCredentialStore;
final RoomSaveStoreMutable _origSlots = roomSaveSlots;
final bool _origNetwork = RoomNetFactory.networkEnabled;
final bool _origDiscovery = RoomNetFactory.discoveryEnabled;
final int? _origPort = RoomNetFactory.servicePortOverride;

void main() {
  late _ZeroHttp http;
  late InMemoryRoomSaveStore store;

  setUp(() {
    _stubAutoAvatarPng();
    http = _ZeroHttp();
    cloudHttp = http;
    store = InMemoryRoomSaveStore();
    roomSaveSlots = store;
    recentCredentialStore = MemoryRecentCredentialStorage();
    RoomNetFactory.networkEnabled = false;
    RoomNetFactory.discoveryEnabled = false;
    RoomNetFactory.servicePortOverride = 0;
    clearActiveCloudBackup();
  });

  tearDown(() {
    cloudHttp = _origHttp;
    roomSaveSlots = _origSlots;
    recentCredentialStore = _origCredStore;
    RoomNetFactory.networkEnabled = _origNetwork;
    RoomNetFactory.discoveryEnabled = _origDiscovery;
    RoomNetFactory.servicePortOverride = _origPort;
    clearActiveCloudBackup();
  });

  /// 准备一条可点的 ③ 区存档。
  Future<void> seedSave() async {
    final Map<String, Object?> save = await _realSave(kCode);
    store.put(kSaveKey, save);
  }

  void seedCred({required bool hasBase, String mode = 'cloud', int lastOkAt = 0}) {
    saveRecentCredential(
      roomCode: kCode,
      base: hasBase ? kBase : '',
      hostToken: kHostToken,
      deviceId: kDeviceId,
      role: RoomRole.player,
      seat: 'p1',
      mode: mode,
      lastOkAt: lastOkAt,
    );
  }

  Future<void> pumpEntry(WidgetTester tester) async {
    useRoomScreen(tester, 480, 900);
    await pumpApp(tester, home: RoomEntryPage(saveStore: store));
  }

  // ==========================================================
  // C10 弹窗三分支
  // ==========================================================
  group('C10 有凭据必弹、三选项、默认优先级、零令牌回显', () {
    test('shouldShowDialog：有凭据且 hasBase → true；无凭据/base 空 → false',
        () async {
      final service = RoomResumeService(store: store);
      expect(await service.shouldShowDialog(kCode), isFalse);
      expect(await service.shouldShowDialog(''), isFalse);
      seedCred(hasBase: false);
      expect(await service.shouldShowDialog(kCode), isFalse,
          reason: 'base 空不得弹窗（直接既有离线路径）');
      seedCred(hasBase: true);
      expect(await service.shouldShowDialog(kCode), isTrue);
      // flexible：历史混合大小写凭据也能命中。
      expect(await service.shouldShowDialog('ab12cd'), isTrue);
      expect(await service.shouldShowDialog('Ab12Cd'), isTrue);
    });

    test('defaultMode 优先级 lastOkMode > inferredMode > offline', () {
      final service = RoomResumeService(store: store);
      const int now = 1700000000000;
      // ① 7 天内成功模式优先于地址推断：LAN 记忆 + 公网 base → 仍选 lan。
      expect(
          service.defaultMode(
              RecentRoomCredential(
                roomCode: kCode, base: kBase, mode: 'lan',
                lastOkAt: now - 1000),
              now),
          ResumeMode.lan);
      // ② 记忆过期 → 回落到 inferredMode（公网 base → cloud）。
      expect(
          service.defaultMode(
              RecentRoomCredential(
                roomCode: kCode, base: kBase, mode: 'lan',
                lastOkAt: now - 8 * 86400 * 1000),
              now),
          ResumeMode.cloud);
      // ③ 无记忆：公网地址 → cloud；局域网地址 → lan。
      expect(
          service.defaultMode(
              RecentRoomCredential(roomCode: kCode, base: kBase), now),
          ResumeMode.cloud);
      expect(
          service.defaultMode(
              RecentRoomCredential(
                  roomCode: kCode, base: 'http://192.168.1.7:4211'),
              now),
          ResumeMode.lan);
      // hasBase==true 时 inferredMode 恒有值，offline 兜底档不会命中
      // （设计 §4.4 明确说明，offline 只能由用户主动点选）。
      expect(service.defaultMode(
              RecentRoomCredential(roomCode: kCode, base: ''), now),
          isNot(ResumeMode.offline));
      expect(ResumeChoice.cancelledChoice.cancelled, isTrue);
      expect(ResumeChoice.cancelledChoice.mode, ResumeMode.offline);
    });

    testWidgets('点续玩 → ResumeDialogKeys.root + 三选项齐全，UI 零令牌回显',
        (WidgetTester tester) async {
      await seedSave();
      seedCred(hasBase: true);
      await pumpEntry(tester);
      expect(find.byKey(RoomEntryKeys.resumeLoad(kSaveKey)), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.resumeRow(kSaveKey)), findsOneWidget);

      await tester.tap(find.byKey(RoomEntryKeys.resumeLoad(kSaveKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(ResumeDialogKeys.root), findsOneWidget,
          reason: '有凭据 hasBase 必弹「选择续玩方式」');
      expect(find.byKey(ResumeDialogKeys.title), findsOneWidget);
      expect(find.byKey(ResumeDialogKeys.subtitle), findsOneWidget);
      expect(find.byKey(ResumeDialogKeys.lan), findsOneWidget);
      expect(find.byKey(ResumeDialogKeys.cloud), findsOneWidget);
      expect(find.byKey(ResumeDialogKeys.offline), findsOneWidget,
          reason: '「仅本机离线副本」始终可选');
      expect(find.byKey(ResumeDialogKeys.confirm), findsOneWidget);
      expect(find.byKey(ResumeDialogKeys.cancel), findsOneWidget);
      expect(find.text('局域网重连'), findsOneWidget);
      expect(find.text('公网重连'), findsOneWidget);
      expect(find.text('仅本机离线副本'), findsOneWidget);

      final String all = _allText(tester);
      for (final String banned in <String>[
        kHostToken, kDeviceId, 'mtoken', 'hostToken', 'deviceId',
        kBase, '203.0.113.10', 'deploy_key',
      ]) {
        expect(all.contains(banned), isFalse,
            reason: '弹窗/进度层/横幅不得回显 $banned');
      }
      expect(all.contains(kCode), isTrue, reason: '只回显房号');

      // 默认选中：本用例 cred.mode='cloud' 但 lastOkAt=0（无记忆）→ 公网重连。
      expect(
          find.descendant(
            of: find.byKey(ResumeDialogKeys.cloud),
            matching: find.byIcon(Icons.radio_button_checked),
          ),
          findsOneWidget,
          reason: '默认选中必须落在 inferredMode 推出的公网重连');
      expect(
          find.descendant(
            of: find.byKey(ResumeDialogKeys.lan),
            matching: find.byIcon(Icons.radio_button_unchecked),
          ),
          findsOneWidget);
    });
  });

  // ==========================================================
  // C11 取消零副作用
  // ==========================================================
  group('C11 取消零写入', () {
    testWidgets('取消 → cancelled，凭据内容/mtime 不变、存档槽不变、不进离线副本',
        (WidgetTester tester) async {
      // 用文件后端，才能真的验 mtime。
      final Directory dir =
          Directory.systemTemp.createTempSync('p20_qa_cred_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      recentCredentialStore = FileRecentCredentialStorage(dir);
      await seedSave();
      seedCred(hasBase: true, mode: 'lan', lastOkAt: 1700000000000);
      final File f = File('${dir.path}${Platform.pathSeparator}recent_rooms.json');
      expect(f.existsSync(), isTrue, reason: '前置：凭据文件已落盘');
      final String beforeContent = f.readAsStringSync();
      final int beforeMtime = f.statSync().modified.millisecondsSinceEpoch;
      final List<String> beforeSlots = List<String>.of(store.list());
      final String beforeReadAll =
          jsonEncode(recentCredentialStore.readAll());

      await pumpEntry(tester);
      await tester.tap(find.byKey(RoomEntryKeys.resumeLoad(kSaveKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(ResumeDialogKeys.root), findsOneWidget);
      await tester.tap(find.byKey(ResumeDialogKeys.cancel));
      // 弹窗 pop 有渐隐动画：必须 pumpAndSettle 才能真正从树里移除。
      await tester.pumpAndSettle();

      expect(find.byKey(ResumeDialogKeys.root), findsNothing);
      expect(find.byType(RoomScope), findsNothing,
          reason: '取消绝不自动进离线副本 / 不打开任何房间');
      expect(find.byKey(RoomEntryKeys.banner), findsNothing);
      expect(f.readAsStringSync(), beforeContent,
          reason: '凭据文件内容逐字不变');
      expect(f.statSync().modified.millisecondsSinceEpoch, beforeMtime,
          reason: '凭据文件 mtime 不变');
      expect(jsonEncode(recentCredentialStore.readAll()), beforeReadAll,
          reason: 'readAll() 前后逐字一致');
      expect(store.list(), beforeSlots, reason: '存档槽数量与内容不变');
      expect(http.calls, 0, reason: '取消绝不联网');
    });

    testWidgets('showResumeModeDialog 取消/遮罩 → ResumeChoice.cancelledChoice',
        (WidgetTester tester) async {
      for (final bool tapCancel in <bool>[true, false]) {
        ResumeChoice? got;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(builder: (BuildContext ctx) => ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                got = await showResumeModeDialog(ctx,
                    code: kCode, defaultMode: ResumeMode.cloud);
              },
              child: const Text('OPEN'),
            )),
          ),
        ));
        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();
        if (tapCancel) {
          await tester.tap(find.byKey(ResumeDialogKeys.cancel));
        } else {
          // 点遮罩：barrierDismissible=true。
          await tester.tapAt(const Offset(4, 4));
        }
        await tester.pumpAndSettle();
        expect(got, isNotNull);
        expect(got!.cancelled, isTrue,
            reason: tapCancel ? '取消按钮' : '点遮罩/返回键');
        expect(got!.mode, ResumeMode.offline);
      }
    });
  });

  // ==========================================================
  // C12 离线零回归
  // ==========================================================
  group('C12 离线路径与 v2.32.0 逐字节一致', () {
    testWidgets('无凭据 → 不弹窗，直接 resumeLocalRoom，横幅「已载入本机存档」',
        (WidgetTester tester) async {
      await seedSave();
      await pumpEntry(tester);
      await tester.tap(find.byKey(RoomEntryKeys.resumeLoad(kSaveKey)));
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(ResumeDialogKeys.root), findsNothing,
          reason: 'S1：无凭据绝不弹窗');
      expect(find.byType(RoomScope), findsOneWidget);
      final String banner = _bannerText(tester);
      expect(banner, contains('已载入本机存档'));
      expect(banner.contains('未能连回'), isFalse, reason: 'D-2：不含「未能连回」');
      expect(banner.contains('已连回'), isFalse);
      expect(banner.contains('已同步'), isFalse);
      final RoomScope scope = tester.widget<RoomScope>(find.byType(RoomScope));
      expect(jsStr(asMap(scope.session.state['meta'])['name']), '离线回归团',
          reason: '房间内容必须真的从存档恢复');
      expect(jsStr(asMap(scope.session.state['meta'])['code']), kCode);
      expect(http.calls, 0, reason: '离线路径零网络');
      // ★ 2.37.0 / Q1 产品行为真变（更强口径）：进房首帧 saveOnOpen() 会补一份
      //   open 档 + 房号键（续玩锚点）。原「恰好 [kSaveKey]」在新行为下必红，
      //   升级为「原档仍在 + open 档 + 房号键，且恰好三条无其它离线副本」——
      //   保留「不新增离线副本」核心不变量，并正向钉死 Q1 新增的两条槽。
      final List<String> keys = store.list();
      expect(keys, contains(kSaveKey),
          reason: '★ 原离线存档必须仍然可读（原口径核心不变量逐字保留）');
      expect(keys, contains(kCode),
          reason: '★ Q1：进房必须落房号键（续玩锚点）');
      expect(keys.any((String k) => k.startsWith('auto/$kCode/open-')), isTrue,
          reason: '★ Q1：进房首帧必须补一份开局档：$keys');
      expect(keys.length, 3,
          reason: '★ 恰好「原档 + open 档 + 房号键」三条，不新增其它离线副本：$keys');
    });

    testWidgets('凭据 hasBase=false → 不弹窗，仍走既有离线路径',
        (WidgetTester tester) async {
      await seedSave();
      seedCred(hasBase: false);
      await pumpEntry(tester);
      await tester.tap(find.byKey(RoomEntryKeys.resumeLoad(kSaveKey)));
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(ResumeDialogKeys.root), findsNothing);
      expect(find.byType(RoomScope), findsOneWidget);
      expect(_bannerText(tester), contains('已载入本机存档'));
      expect(_bannerText(tester).contains('未能连回'), isFalse);
      expect(http.calls, 0);
    });

    testWidgets('主动选「仅本机离线副本」→ 横幅仍为「已载入本机存档」',
        (WidgetTester tester) async {
      await seedSave();
      seedCred(hasBase: true);
      await pumpEntry(tester);
      await tester.tap(find.byKey(RoomEntryKeys.resumeLoad(kSaveKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(ResumeDialogKeys.root), findsOneWidget);
      await tester.tap(find.byKey(ResumeDialogKeys.offline));
      await tester.pump();
      await tester.tap(find.byKey(ResumeDialogKeys.confirm));
      for (int i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RoomScope), findsOneWidget);
      final String banner = _bannerText(tester);
      expect(banner, contains('已载入本机存档'));
      expect(banner.contains('未能连回'), isFalse,
          reason: 'D-2：主动选离线是正常行为，不是"连回失败"');
      expect(http.calls, 0, reason: '主动选离线绝不联网');
      // ★ 2.37.0 / Q1 产品行为真变（更强口径）：同「无凭据」用例，saveOnOpen
      //   补 open 档 + 房号键；原档保留、恰好三条、不多写离线副本。
      final List<String> keys = store.list();
      expect(keys, contains(kSaveKey),
          reason: '★ 原离线存档仍可读（原口径核心不变量逐字保留）');
      expect(keys, contains(kCode), reason: '★ Q1：房号键必须落盘');
      expect(keys.any((String k) => k.startsWith('auto/$kCode/open-')), isTrue,
          reason: '★ Q1：首帧开局档必须落盘：$keys');
      expect(keys.length, 3,
          reason: '★ 恰好三条，不新增其它离线副本：$keys');
    });

    test('与 v2.32.0 基线逐字节一致：RoomEntryKeys / ③ 区 / _saveRow / shell initState',
        () {
      final String? baselinePath =
          _baseline('_p20_progress/room_entry_page.baseline.dart');
      expect(baselinePath, isNotNull,
          reason: '必须能读到 v2.32.0 基线副本做语义比对');
      final String? ghPath =
          _baseline('_gh_backup/lib/ui/room/room_entry_page.dart');
      expect(ghPath, isNotNull);
      final String base = File(baselinePath!).readAsStringSync();
      final String gh = File(ghPath!).readAsStringSync();
      final String now =
          File('lib/ui/room/room_entry_page.dart').readAsStringSync();
      // ★ P12 / 前提校正：两份历史副本是**不同期快照** ——
      //   `_p20_progress/…baseline.dart` 是 v2.32.0，`_gh_backup/…` 是
      //   P20 交付态（自带 `import 'dart:async'` 等 P20 新增 import），
      //   两者本就不逐字节相等。原先「两份基线必须逐字节一致」的前提
      //   已不成立，这里改为「同期备份确实是 RoomEntryPage 源码」；
      //   ★ 下面对 v2.32.0 base 的逐字节禁改区段比对一条都未删、未放宽。
      expect(gh.contains('class RoomEntryPage'), isTrue,
          reason: '同期备份里应有 RoomEntryPage，可作辅助对照');
      expect(base.contains('class RoomEntryPage'), isTrue,
          reason: 'v2.32.0 基线里应有 RoomEntryPage');

      // ★ P15（v2.40.0+110）：本期**合法新增**了
      //   `RoomEntryKeys.resumeRemove` 与 `_saveRow` 里的时间戳 / 删除按钮，
      //   原先「整块与 v2.32.0 逐字节相等」必然红（Differ at offset 1913）。
      //
      //   按「更强或等价」升级：既有区段仍是**逐字节**口径 —— 把本期新增片段
      //   逐段替换回基线原文，残余必须与基线一字不差；且
      //     · 每个新增片段必须在源码里逐字出现且**唯一命中**（缺一/写歪即红）；
      //     · 被替换掉的旧片段必须在基线里真实存在（证明「只加了这些」）；
      //   新增块本身也被正向钉死（见下面的 rowTime / rowRemove 片段）。
      //   比原口径更强：旧代码一个字符都没松，新代码也被锁死。
      String reduceToBaseline(
        String b,
        String n,
        List<List<String>> pairs,
        String label,
      ) {
        String residual = n;
        for (final List<String> pair in pairs) {
          final String cur = pair[0];
          final String old = pair.length > 1 ? pair[1] : '';
          expect(cur, isNotEmpty, reason: '★ $label 新增片段不得为空');
          expect(residual.contains(cur), isTrue,
              reason: '★ $label 新增片段必须在源码里逐字出现：\n$cur');
          expect(residual.indexOf(cur), residual.lastIndexOf(cur),
              reason: '★ $label 新增片段必须唯一命中：\n$cur');
          if (old.isNotEmpty) {
            expect(b.contains(old), isTrue,
                reason: '★ $label 被替换掉的旧片段必须在 v2.32.0 基线里：\n$old');
          }
          residual = residual.replaceFirst(cur, old);
        }
        expect(residual, b,
            reason: '★ $label 除本期合法新增外，其余必须与 v2.32.0 逐字节一致');
        return residual;
      }

      // ① _resumeSection：本期一字未动，仍与 v2.32.0 逐字节相等（原口径保留）。
      const String resumeSectionMark = 'Widget _resumeSection(ThemeData theme) {';
      final String baseResumeSection = _block(base, resumeSectionMark);
      expect(baseResumeSection, isNotEmpty, reason: '基线里找不到 _resumeSection');
      expect(_block(now, resumeSectionMark), baseResumeSection,
          reason: '禁改区段 _resumeSection(...) 与 v2.32.0 不一致');

      // ② RoomEntryKeys：v2.32.0 的 21 条 key 字符串逐字保留，仅新增 resumeRemove。
      final String baseKeys = _block(base, 'class RoomEntryKeys {');
      final String nowKeys = _block(now, 'class RoomEntryKeys {');
      expect(baseKeys, isNotEmpty, reason: '基线里找不到 RoomEntryKeys');
      final Iterable<RegExpMatch> baseKeyPaths =
          RegExp(r"'roomEntry/[^']*'").allMatches(baseKeys);
      expect(baseKeyPaths.length, 21,
          reason: 'v2.32.0 的 key 字面量应恰好 21 条');
      for (final RegExpMatch m in baseKeyPaths) {
        expect(nowKeys.contains(m.group(0)!), isTrue,
            reason: '★ 既有 key 字符串 ${m.group(0)} 不得改动或丢失');
      }
      expect(nowKeys, contains(r"'roomEntry/resume/row/$key'"),
          reason: '★ resumeRow 的 key 值逐字锁死');
      expect(nowKeys, contains(r"'roomEntry/resume/load/$key'"),
          reason: '★ resumeLoad 的 key 值逐字锁死');
      expect(nowKeys, contains(r"'roomEntry/resume/remove/$key'"),
          reason: '★ P15 新增 resumeRemove 的 key 值也正向钉死');
      // 本期唯一新增：resumeRemove 的定义体（连同前面的空行，便于逐字节还原）。
      // ★ 前导空行用显式 "\n\n" 拼接：Dart 多行字面量会吃掉开头的换行，
      //   直接写进 r''' 会少一个 \n，还原后就差一个字节。
      final String keyRemoveDef = "\n\n" +
          r'''  /// 槽行的「删除」按钮（P15 新增；两段式确认，无弹窗）。
  static Key resumeRemove(String key) =>
      ValueKey<String>('roomEntry/resume/remove/$key');''';
      reduceToBaseline(baseKeys, nowKeys, <List<String>>[
        <String>[keyRemoveDef, ''],
      ], 'RoomEntryKeys');

      // ③ _saveRow：既有结构逐字保留 + 本期新增的时间戳 / 删除按钮正向钉死。
      const String saveRowMark = 'Widget _saveRow(ThemeData theme, String key) {';
      final String baseSaveRow = _block(base, saveRowMark);
      final String nowSaveRow = _block(now, saveRowMark);
      expect(baseSaveRow, isNotEmpty, reason: '基线里找不到 _saveRow');
      // 既有结构（一个字符都不许松）。
      expect(nowSaveRow, contains('      key: RoomEntryKeys.resumeRow(key),'),
          reason: '★ 行外层 key 必须仍是 resumeRow(key)');
      expect(nowSaveRow, contains(r"            label: '续玩',"),
          reason: '★ 「续玩」按钮文案逐字保留');
      expect(nowSaveRow, contains(r"            onTap: () => _resume(key),"),
          reason: '★ 续玩仍走 _resume(key)');
      expect(nowSaveRow, contains("            hint: '载入这条本机存档',"),
          reason: '★ 续玩按钮 hint 逐字保留');
      expect(nowSaveRow, contains("            minSize: const Size(84, 40),"),
          reason: '★ 续玩按钮热区逐字保留');
      // 本期新增片段（逐字，且必须唯一命中）。
      final String rowSavedAt = r'''    // ★ P15：所有列表存档都带时间戳（读不出 savedAt 的显示「—」，排最后）。
    final savedAt = jsParseInt(save?['savedAt']) ?? 0;
    final removable = _store is RoomSaveStoreMutable;
''';
      final String rowTimeNow = r'''                  '${status.isEmpty ? '' : ' · $status'}'
                  ' · ${saveTimeText(savedAt)}',''';
      final String rowTimeBase = r'''                  '${status.isEmpty ? '' : ' · $status'}',''';
      final String rowMaxLines = r'''                  maxLines: 1,
''';
      final String rowRemoveTwice = r'''          // ★ P15：非 Mutable 后端连按钮都不渲染（不做禁用态，免得像个坏按钮）。
          if (removable)
            ConfirmTwice(
              key: RoomEntryKeys.resumeRemove(key),
              label: '删除',
              // 删的是本机存档槽，不动当前房间；两段式确认，不弹窗。
              confirmLabel: '再点一次',
              onConfirmed: () => _removeSave(key),
            ),
''';
      expect(nowSaveRow, contains('saveTimeText(savedAt)'),
          reason: '★ 副标题必须接时间文案 saveTimeText');
      expect(nowSaveRow, contains('_removeSave(key)'),
          reason: '★ 删除按钮必须接到 _removeSave');
      reduceToBaseline(baseSaveRow, nowSaveRow, <List<String>>[
        <String>[rowSavedAt, ''],
        <String>[rowTimeNow, rowTimeBase],
        <String>[rowMaxLines, ''],
        <String>[rowRemoveTwice, ''],
      ], '_saveRow');
      // ③ 区标题、resumeLoad(key)、离线横幅字面量逐字不变。
      expect(now.contains("title: '③ 续玩本机存档（\${_saves.length}）'"), isTrue);
      expect(base.contains("title: '③ 续玩本机存档（\${_saves.length}）'"), isTrue);
      expect(now.contains('key: RoomEntryKeys.resumeLoad(key),'), isTrue);
      expect(now, contains("banner = '已载入本机存档';"));
      expect(now,
          contains("'已载入本机存档 · 旧存档含历史明文记录，已自动脱敏 \$migrated 条'"),
          reason: 'migrated 脱敏提示与基线逐字一致');
      expect(base,
          contains("'已载入本机存档 · 旧存档含历史明文记录，已自动脱敏 \$migrated 条'"));
      // v2.32.0 的「未能连回」横幅字面量必须已消失（D-2）。
      expect(now.contains("banner = '未能连回原房间"), isFalse);
      expect(base.contains("banner = '未能连回原房间"), isTrue);
      // 离线仍走既有 resumeLocalRoom，不是新写一套。
      expect(_block(now, 'Future<void> openOffline() async {'),
          contains('resumeLocalRoom('));

      // ★ P12 GL-1 新增正向断言：_reloadSaves 按 meta.code 大写归一去重，
      //   并优先保留「键本身就是房号」那条（R8 / R12 / Q-E）。
      //   既有 RoomEntryKeys / ③ 区 / _saveRow / initState 的逐字节比对
      //   （上面的禁改区段循环）一条未动。
      final String reload = _block(now, 'void _reloadSaves() {');
      expect(reload, isNotEmpty, reason: '应能定位 _reloadSaves 区块');
      expect(reload, contains('toUpperCase()'),
          reason: '★ 房号必须大写归一，云端小写不产生第二条');
      expect(reload, contains('isRoomKey'),
          reason: '★ 去重必须优先保留键 == 房号的那条');
      expect(reload, contains('byCode'),
          reason: '★ 按 code 折叠 auto/ 与 share/ 槽');

      // ★ 2.37.0 / Q1 产品行为真变（更强口径）：
      //   initState 新增首帧 post-frame（onStateChanged 基线 + saveOnOpen）。
      //   旧「整块与 v2.32.0 逐字节相等」在新行为下必红；升级为
      //   「逐字钉死新增块 + 剔除新增块后旧块仍逐字节相等」——
      //   旧代码一个字符都没松，新块也被正向钉死，比原口径更强。
      //
      // ★ P14：同一口径再补两块 P13 产品行为（进房退出基线 / 存档触发器基线），
      //   它们同样落在 initState 里。三块各自正向钉死（缺一即红），
      //   全部剔除后的残余体仍与 v2.32.0 **逐字节**一致；基线里出现任一新增
      //   标记也算红（证明「差异只有这三块」，没有夹带别的改动）。
      final int bShell = base.indexOf('class _RoomShellState');
      final int nShell = now.indexOf('class _RoomShellState');
      expect(bShell, greaterThan(0));
      expect(nShell, greaterThan(0));
      final String nowInit = _block(now, 'void initState() {', from: nShell);
      final String baseInit = _block(base, 'void initState() {', from: bShell);

      /// 从 [src] 里切出以 [startMark] 开头、[endToken] 结尾的一整块新增代码。
      String cutBlock(String src, String startMark, String endToken, String label) {
        final int s = src.indexOf(startMark);
        expect(s, greaterThan(0), reason: '★ $label 必须落在 initState 里');
        expect(src.indexOf(startMark, s + 1), -1,
            reason: '★ $label 只应出现一次');
        final int e = src.indexOf(endToken, s);
        expect(e, greaterThan(s), reason: '★ $label 的结束标记 "$endToken" 缺失');
        return src.substring(s, e + endToken.length);
      }

      // ① P13 进房退出判定基线（续玩 CLOSED 档不被误 pop）
      final String p13Entry =
          cutBlock(nowInit, '    // ★ P13：**进房基线**', '    ).kind;\n', 'P13 进房基线块');
      expect(p13Entry, contains('_entryExitKind = roomExitOf('),
          reason: '★ 进房那一刻的退出判定必须落进 _entryExitKind');
      expect(p13Entry, contains('kickedByHost: widget.session.kickedByHost,'),
          reason: '★ 判定入参必须含「被踢」信号');
      expect(p13Entry, isNot(contains('_exit =')),
          reason: '★ 进房快照不许污染 _exit（dispose 判据要用）');

      // ② P13 存档触发器基线（避免续玩 CLOSED 档白写 close 档）
      final String p13Prime = cutBlock(
          nowInit, '    // ★ P13：同上', '    _syncer.primeStatusBaseline();\n', 'P13 存档触发器基线块');
      expect(p13Prime, contains('_syncer.primeStatusBaseline();'),
          reason: '★ 存档触发器基线必须落位');

      // ③ 2.37.0 / Q1 首帧 post-frame
      final String q1Block =
          cutBlock(nowInit, '    // ★ 2.37.0 / Q1', '    });\n', 'Q1 首帧 post-frame 块');
      expect(q1Block, contains('addPostFrameCallback'),
          reason: '★ 基线必须延到首帧后落（避免 build 期重建）');
      expect(q1Block, contains('unawaited(_syncer.onStateChanged());'),
          reason: '★ 首帧落触发器基线（成员数 / 回合号）');
      expect(q1Block, contains('unawaited(_syncer.saveOnOpen());'),
          reason: '★ 首帧补开局档（10 分钟内不再空窗）');

      // 基线里不得出现任一新增标记：证明 diff 仅限这三块
      for (final String mark in <String>[
        '// ★ P13：**进房基线**',
        '// ★ P13：同上',
        '// ★ 2.37.0 / Q1',
      ]) {
        expect(baseInit.contains(mark), isFalse,
            reason: 'v2.32.0 基线里不应有新增标记 $mark');
      }

      String residual = nowInit;
      for (final String seg in <String>[p13Entry, p13Prime, q1Block]) {
        expect(residual.contains(seg), isTrue);
        residual = residual.replaceFirst(seg, '');
      }
      expect(residual, baseInit,
          reason: '除 P13 两块 + Q1 首帧块外，initState 其余部分必须与 v2.32.0 逐字节一致');
    });
  });

  // ==========================================================
  // P15 存档时间戳 + 续玩列表删除（正向钉死）
  //
  // 产品行为本期真变：列表副标题带时间、续玩行多一个两段式「删除」。
  // 这不只是"源码长这样"，下面逐条跑真实行为。
  // ==========================================================
  group('P15 存档时间戳与续玩列表删除', () {
    /// 造一条最小可读存档（入口页只依赖 meta.code/name/status + savedAt）。
    Map<String, Object?> saveOf(String code, {String? name, int? savedAt}) =>
        <String, Object?>{
          'meta': <String, Object?>{
            'code': code,
            'name': name ?? '团$code',
            'status': '进行中',
          },
          'savedAt': savedAt ?? DateTime.now().millisecondsSinceEpoch,
        };

    test('saveTimeText：0/负数/越界 → —；同年 MM-dd HH:mm 无年份；跨年带 4 位年份', () {
      final DateTime now = DateTime(2026, 11, 21, 15, 30);
      // 空值口径。
      expect(saveTimeText(0), '—', reason: '0 表示读不出时间');
      expect(saveTimeText(-1), '—', reason: '负数同样是脏数据');
      expect(saveTimeText(-1700000000000), '—');
      expect(saveTimeText(1 << 62), '—',
          reason: '超出 DateTime 可表示范围也必须降级成「—」而不是抛异常');
      // 同年：只到分，不带年份。
      final DateTime sameYear = DateTime(2026, 3, 7, 9, 5);
      final String same =
          saveTimeText(sameYear.millisecondsSinceEpoch, now: now);
      expect(same, '03-07 09:05');
      expect(same.contains('2026'), isFalse, reason: '同年不显示年份，省地方');
      expect(RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(same), isTrue,
          reason: '同年格式必须是 MM-dd HH:mm');
      // 跨年：补 4 位年份，免得把去年的存档看成昨天的。
      final DateTime lastYear = DateTime(2025, 12, 31, 23, 59);
      final String cross =
          saveTimeText(lastYear.millisecondsSinceEpoch, now: now);
      expect(cross, '2025-12-31 23:59');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(cross), isTrue,
          reason: '跨年格式必须是 yyyy-MM-dd HH:mm');
      expect(cross.contains('2025'), isTrue, reason: '跨年必须带 4 位年份');
      // 同一个时刻，只要「今年」相同，文案就一致（年份只做归属判断）。
      expect(
          saveTimeText(sameYear.millisecondsSinceEpoch,
              now: DateTime(2026, 1, 1)),
          same);
    });

    testWidgets('_saveRow 副标题带时间：形如 MM-dd HH:mm（同年无年份）', (WidgetTester tester) async {
      store.put(kCode, saveOf(kCode, savedAt: DateTime.now().millisecondsSinceEpoch));
      await pumpEntry(tester);
      final Finder rowTexts = find.descendant(
        of: find.byKey(RoomEntryKeys.resumeRow(kCode)),
        matching: find.byType(Text),
      );
      final List<String> texts = tester
          .widgetList<Text>(rowTexts)
          .map((Text t) => t.data ?? '')
          .toList();
      expect(
        texts.any((String t) => RegExp(r' · \d{2}-\d{2} \d{2}:\d{2}$').hasMatch(t)),
        isTrue,
        reason: '列表副标题必须追加「· MM-dd HH:mm」：$texts',
      );
    });

    testWidgets('删除按房号群删：同房号三条槽全没了，其它房号 / 无房号自定义槽不受影响',
        (WidgetTester tester) async {
      store.put(kCode, saveOf(kCode));
      store.put('auto/$kCode/close-1', saveOf(kCode));
      store.put('share/$kCode/latest', saveOf(kCode));
      store.put('ZZ99YY', saveOf('ZZ99YY', name: '别的团'));
      store.put('custom-no-code',
          <String, Object?>{'meta': <String, Object?>{'name': '手搓槽'}});

      await pumpEntry(tester);
      // 折叠成一行（房号键优先），但三条槽都还在后端里。
      expect(find.byKey(RoomEntryKeys.resumeRow(kCode)), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.resumeRow('ZZ99YY')), findsOneWidget);
      expect(store.list().length, 5);

      await tester.tap(find.byKey(RoomEntryKeys.resumeRemove(kCode)));
      await tester.pump();
      // 两段式的第一段：只进入待确认，绝不删。
      expect(find.text('再点一次'), findsOneWidget,
          reason: '第一次点后按钮文案必须变成「再点一次」');
      expect(store.list().length, 5, reason: '★ 第一次点击不删任何槽：${store.list()}');
      expect(store.list(), containsAll(<String>[
        kCode,
        'auto/$kCode/close-1',
        'share/$kCode/latest',
      ]));

      await tester.tap(find.byKey(RoomEntryKeys.resumeRemove(kCode)));
      await tester.pumpAndSettle();
      expect(store.list().where((String k) => k.contains(kCode)), isEmpty,
          reason: '★ 同房号全部槽必须删净（否则下次刷新又「复活」）：${store.list()}');
      expect(store.list(), containsAll(<String>['ZZ99YY', 'custom-no-code']),
          reason: '★ 其它房号与无房号自定义槽不得被误删：${store.list()}');
      expect(store.list().length, 2);
      expect(find.byKey(RoomEntryKeys.resumeRow(kCode)), findsNothing,
          reason: '★ 删完这一行必须从列表消失');
      expect(find.byKey(RoomEntryKeys.resumeRow('ZZ99YY')), findsOneWidget);
    });

    testWidgets('ConfirmTwice 两段式：第一次不删、第二次才删；无房号槽只删自己',
        (WidgetTester tester) async {
      store.put('custom-a', <String, Object?>{'meta': <String, Object?>{'name': '甲'}});
      store.put('custom-b', <String, Object?>{'meta': <String, Object?>{'name': '乙'}});
      await pumpEntry(tester);
      expect(find.byKey(RoomEntryKeys.resumeRow('custom-a')), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.resumeRow('custom-b')), findsOneWidget);

      await tester.tap(find.byKey(RoomEntryKeys.resumeRemove('custom-a')));
      await tester.pump();
      expect(store.list(), <String>['custom-a', 'custom-b'],
          reason: '★ 第一次点击只上膛，不删');
      expect(find.byKey(RoomEntryKeys.resumeRow('custom-a')), findsOneWidget);
      expect(find.text('再点一次'), findsOneWidget);

      await tester.tap(find.byKey(RoomEntryKeys.resumeRemove('custom-a')));
      await tester.pumpAndSettle();
      expect(store.list(), <String>['custom-b'],
          reason: '★ 第二次才删，且无房号自定义槽只删自己');
      expect(find.byKey(RoomEntryKeys.resumeRow('custom-a')), findsNothing);
      expect(find.byKey(RoomEntryKeys.resumeRow('custom-b')), findsOneWidget);
    });

    testWidgets('非 Mutable 后端 → 删除按钮根本不渲染（不是禁用态）',
        (WidgetTester tester) async {
      final _ReadOnlySaveStore ro = _ReadOnlySaveStore();
      ro.put(kCode, saveOf(kCode));
      useRoomScreen(tester, 480, 900);
      await pumpApp(tester, home: RoomEntryPage(saveStore: ro));

      expect(find.byKey(RoomEntryKeys.resumeRow(kCode)), findsOneWidget,
          reason: '前置：存档行本身照常渲染');
      expect(find.byKey(RoomEntryKeys.resumeLoad(kCode)), findsOneWidget,
          reason: '前置：「续玩」按钮照常可用');
      expect(find.byKey(RoomEntryKeys.resumeRemove(kCode)), findsNothing,
          reason: '★ 后端不支持删除时连按钮都不能出现');
      expect(find.text('删除'), findsNothing,
          reason: '★ 也不许留个灰着的假按钮');
    });
  });

  // ==========================================================
  // E 版本 / 门禁 / 冻结 / NUL
  // ==========================================================
  group('E 版本与门禁', () {
    test('版本链路三处同步（正则从 pubspec 读真值，不写死版本字面量）', () {
      // ★ 产品行为真变（Q13 升 2.35.0+105）：按「更强或等价」改写。
      //   原先只查 3 个写死字面量；现在改为「从 pubspec.yaml 正则读真值
      //   → 与 app_version.dart 两处逐字比对」+ 版本行唯一性正向断言，
      //   以后再升版本也自动绿（与 test/app_version_test.dart 同款口径）。
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final String ver = File('lib/app_version.dart').readAsStringSync();
      final Iterable<RegExpMatch> hits = RegExp(
        r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
        multiLine: true,
      ).allMatches(pubspec);
      expect(hits.length, 1,
          reason: 'pubspec.yaml 必须恰好一行 version: x.y.z+n');
      final RegExpMatch m = hits.single;
      final String v = m.group(1)!;
      final String b = m.group(2)!;
      expect(v.split('.').length, 3, reason: '语义化版本三段');
      expect(ver, contains("kAppVersion = '$v'"),
          reason: 'app_version.dart 版本必须与 pubspec 同步');
      expect(ver, contains('kAppBuildNumber = $b'),
          reason: 'app_version.dart build 号必须与 pubspec 同步');
      expect(pubspec.contains('version: $v+$b'), isTrue);
    });

    test('pubspec.lock 82 处 pub.dev / 0 处镜像', () {
      final String lock = File('pubspec.lock').readAsStringSync();
      expect('pub.dev'.allMatches(lock).length, 82);
      for (final String mirror in <String>[
        'pub.flutter-io.cn', 'storage.flutter-io.cn', 'mirrors.tuna',
        'mirrors.aliyun', 'PUB_HOSTED_URL',
      ]) {
        expect(lock.contains(mirror), isFalse, reason: '不得残留镜像 $mirror');
      }
    });

    test('无 skip、无放宽断言；冻结文件零改动', () {
      final Directory testDir = Directory('test');
      int skips = 0;
      for (final File f in testDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))) {
        // 去掉本文件里作为"检索词"出现的字面量，避免门禁自己数自己。
        final String src = f.readAsStringSync().replaceAll("'skip:'", '');
        skips += RegExp(r'\bskip\s*:').allMatches(src).length;
      }
      expect(skips, 0, reason: '任何时候都不许 skip');

      const List<String> frozen = <String>[
        'lib/domain/data/skills.dart',
        'lib/domain/data/occupations.dart',
        'test/app_version_test.dart',
      ];
      for (final String rel in frozen) {
        final String? b = _baseline('_gh_backup/$rel');
        expect(b, isNotNull, reason: '找不到冻结基线 $rel');
        expect(File(rel).readAsStringSync(), File(b!).readAsStringSync(),
            reason: '冻结文件 $rel 不得改动');
      }
      final Directory oracle = Directory('test');
      for (final File f in oracle
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.contains('oracle_'))) {
        final String name = f.path.split(Platform.pathSeparator).last;
        final String? b = _baseline('_gh_backup/test/$name');
        expect(b, isNotNull, reason: '找不到 oracle 基线 $name');
        expect(f.readAsStringSync(), File(b!).readAsStringSync(),
            reason: 'oracle 文件 $name 不得逐字节改动');
      }
      // 门禁脚本 FROZEN 计数未被本期改大。
      final File gate = File('tool/qa/qa_p5_ui.js');
      if (gate.existsSync()) {
        final String? b = _baseline('_gh_backup/tool/qa/qa_p5_ui.js');
        if (b != null) {
          expect(gate.readAsStringSync(), File(b).readAsStringSync(),
              reason: '门禁脚本（含 FROZEN 口径）不得改动');
        }
      }
    });

    test('p10_t1_cloud_room_test.dart:350-362 既有断言一字不改', () {
      final String src =
          File('test/p10_t1_cloud_room_test.dart').readAsStringSync();
      const String golden = r'''    test('cloudWsUrl：https → wss，并带上 code / t / d 三个参数', () {
      final String url = cloudWsUrl(
        'https://relay.example.com/room',
        code: 'AB12CD',
        token: 'tk',
      );
      final Uri u = Uri.parse(url);
      expect(u.scheme, 'wss');
      expect(u.path, '/room/ws');
      expect(u.queryParameters['code'], 'AB12CD');
      expect(u.queryParameters['t'], 'tk');
      expect(u.queryParameters['d'], isNotEmpty,
          reason: '服务端用 d= 设备标识认"同一个人重连回原座"');''';
      expect(src.contains(golden), isTrue,
          reason: 'p10:350-362 既有口径必须逐字保留且全绿');
    });

    test('全仓 NUL 扫描：新增/修改文件没有被刷成全 0', () {
      int scanned = 0;
      final List<String> bad = <String>[];
      for (final String dirPath in <String>['lib', 'test']) {
        for (final File f in Directory(dirPath)
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart'))) {
          scanned++;
          final List<int> bytes = f.readAsBytesSync();
          final int nul = bytes.where((int b) => b == 0).length;
          if (nul > 0) bad.add('${f.path}:$nul');
        }
      }
      expect(scanned, greaterThan(150), reason: '应覆盖 lib+test 全量 Dart 文件');
      expect(bad, isEmpty, reason: 'NUL 命中：$bad');
    });
  });
}
