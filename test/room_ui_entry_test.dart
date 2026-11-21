// ============================================================
// test/room_ui_entry_test.dart — P5/T05-B1 入口页 + 三个弹层的验收
//
// 铁律：
//   · T1：后端全部内存实现（存档槽 / 笔记 / 角色卡仓库），零文件读写；
//   · T5：房间相关页面按真实尺寸 pump（`useRoomScreen`）；
//   · T6：断言「点了到底发了什么」看 `sent`，不看文案；
//   · T8：跨视角断言只用「该视角真收到的那份 state」。
//
// ★ 本文件的宿主一律**不替被测组件订阅 `local`**：
//   「读本地态的 widget 必须自己包 ListenableBuilder」这条约束，只有在
//   宿主不兜底时才可能被真正证明（上一批踩过一次假绿）。
// ============================================================

import 'dart:io' show Directory, File;

import 'package:dice_realm/repo/file_room_save_store.dart'
    show FileRoomSaveStore;
import 'package:dice_realm/ui/room/save_persist_hint.dart'
    show savePersistHintOf;
import 'package:dice_realm/app.dart' show DiceRealmApp;
import 'package:dice_realm/ui/room/room_net_factory.dart'
    show RoomNetFactory;
import 'package:dice_realm/domain/character.dart' show Character, newCharacter;
import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/madness.dart' as madness;
import 'package:dice_realm/domain/room_madness_coc.dart' show CocMadness;
import 'package:dice_realm/domain/room_model_actions_room.dart'
    show kRaMadTypes;
import 'package:dice_realm/domain/room_types.dart'
    show RoomIntent, RoomMode, RoomRole;
import 'package:dice_realm/repo/repo_scope.dart' show AppRoutes, RepoScope;
import 'package:dice_realm/ui/room/room_boot.dart'
    show RoomBoot, bootLocalRoom, kRoomCodeLength, newRoomCode, roomSaveSlots;
import 'package:dice_realm/ui/room/room_entry_page.dart'
    show RoomEntryKeys, RoomEntryPage;
import 'package:dice_realm/ui/room/room_scope.dart' show RoomScope;
import 'package:dice_realm/ui/room/room_session_local.dart'
    show LocalLoopbackSession;
import 'package:dice_realm/ui/room/sheets/card_sheet_payload.dart'
    show cardToRoomSheet;
import 'package:dice_realm/ui/room/sheets/sheet_bind_char.dart'
    show BindCharSheetKeys, openBindCharSheet;
import 'package:dice_realm/ui/room/sheets/sheet_misc.dart'
    show MiscSheetKeys, openMiscSheet;
import 'package:dice_realm/ui/room/sheets/sheet_save_slots.dart'
    show SaveSlotsKeys, openSaveSlotsSheet;
import 'package:dice_realm/ui/room/view/room_view.dart' show memberOfSeat;
import 'package:dice_realm/ui/room/sheets/sheet_nearby_rooms.dart'
    show NearbyKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart'
    show autoAvatarPngEncoder;

/// 造一套「仓库 + 设置 + 分享」作用域（入口页要用到角色卡仓库）。
Future<RoomUiFixture> _boot(WidgetTester tester) async {
  final f = RoomUiFixture();
  await f.boot();
  useRoomScreen(tester, 400, 860);
  return f;
}

/// 整个 App（走真实路由表）。
Widget _app(RoomUiFixture f) =>
    DiceRealmApp(repo: f.repo, settings: f.settings, share: f.share);

/// 推一条命名路由（走 `_onGenerateRoute`）。
Future<void> _pushNamed(WidgetTester tester, String name) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  Navigator.of(ctx).pushNamed(name);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 顶部横幅的文本（key 挂在容器上，文本是它的子节点）。
String _bannerText(WidgetTester tester) => tester
        .widget<Text>(find.descendant(
          of: find.byKey(RoomEntryKeys.banner),
          matching: find.byType(Text),
        ))
        .data ??
    '';

void main() {
  // 自动头像 PNG 生成是引擎真异步：widget 测试里统一替身（见文件末注释）
  setUp(_stubAutoAvatarPng);

  setUp(() {
    roomSaveSlots.clear();
    // P6：加入流程会先扫局域网。测试里关掉 —— 真 UDP 扫描会拖慢
    // 每个用例 1.2s，且不同机器受防火墙影响结果不稳定。
    RoomNetFactory.discoveryEnabled = false;
    // P6：建房会真起 HTTP 服务，但 testWidgets 的 FakeAsync 推不动真实 bind
    // → await 永远不返回。关掉网络，session 仍是 HostingLocalSession。
    RoomNetFactory.networkEnabled = false;
    RoomNetFactory.servicePortOverride = 0;
  });

  tearDown(() {
    RoomNetFactory.servicePortOverride = null;
    RoomNetFactory.networkEnabled = true;
  });

  // ----------------------------------------------------------
  // 路由
  // ----------------------------------------------------------
  group('路由', () {
    testWidgets('/room 可达：首页 🎲 FAB 进入入口页，三个功能区都在',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();

      expect(find.byKey(const Key('fab_room')), findsOneWidget);
      // ★ P9 需求 5：首页 → 规则选择页 → 跑团房间入口
      // ★ P9 需求 5：首页 → 规则选择页 → 跑团房间入口
      await tester.tap(find.byKey(const Key('fab_room')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rule_pick_coc7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RoomEntryPage), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.createName), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.joinCode), findsOneWidget);
      expect(find.byKey(RoomEntryKeys.resumeEmpty), findsOneWidget,
          reason: '存档槽为空时要有空态');
      expect(find.byKey(RoomEntryKeys.joinHint), findsOneWidget);
    });

    testWidgets('/room/<code> 带房间号：房间号输入框预填，且文案不假装联网',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();

      expect(AppRoutes.roomCode('K3M9QZ'), '/room/K3M9QZ');
      await _pushNamed(tester, AppRoutes.roomCode('K3M9QZ'));

      final field =
          tester.widget<TextField>(find.byKey(RoomEntryKeys.joinCode));
      expect(field.controller?.text, 'K3M9QZ', reason: '深链要把房间号预填好');

      final hint =
          tester.widget<Text>(find.byKey(RoomEntryKeys.joinHint)).data ?? '';
      expect(hint.contains('本机预览'), isTrue,
          reason: '★ 必须明示「找不到局域网房时会退成本机预览」——不骗用户');
    });

    testWidgets('房间号生成器：6 位、只用无歧义字符', (WidgetTester tester) async {
      for (var i = 0; i < 50; i++) {
        final code = newRoomCode();
        expect(code.length, kRoomCodeLength);
        expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(code), isTrue);
        expect(code.contains('0') || code.contains('O'), isFalse);
        expect(code.contains('1') || code.contains('I'), isFalse);
      }
    });
  });

  // ----------------------------------------------------------
  // ① 创建
  // ----------------------------------------------------------
  group('① 创建房间', () {
    testWidgets('★ 填房名 + 昵称 → 创建出房间号，会话 meta.name 就是输入的房名',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();
      await _pushNamed(tester, AppRoutes.room);

      await tester.enterText(find.byKey(RoomEntryKeys.createName), '测试团甲');
      await tester.enterText(find.byKey(RoomEntryKeys.createNick), '老K');
      await tester.pump();

      await tester.tap(find.byKey(RoomEntryKeys.createSubmit));
      await tester.pump(); // onTap → 异步装配开始
      await tester.pump(); // 装配完成 → setState + push
      await tester.pump(const Duration(milliseconds: 400)); // 路由动画

      // 生成的房间号回填到入口页
      final codeText =
          tester.widget<Text>(find.byKey(RoomEntryKeys.createdCode)).data ?? '';
      expect(codeText.length, kRoomCodeLength);
      expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(codeText), isTrue);

      // 会话真的建出来了：host.state 的 meta 就是输入值
      final scope = tester.widget<RoomScope>(find.byType(RoomScope));
      final session = scope.session as LocalLoopbackSession;
      expect(session.role, RoomRole.kp);
      expect(jsStr(asMap(session.host.state['meta'])['name']), '测试团甲');
      expect(jsStr(asMap(session.host.state['meta'])['code']), codeText);
      expect(jsStr(asMap(session.host.state['meta'])['kpName']), '老K');

      // 顺手存了一份本机存档 → 续玩列表能列出来
      expect(roomSaveSlots.list(), contains(codeText));
    });
  });

  // ----------------------------------------------------------
  // ② 加入
  // ----------------------------------------------------------
  group('② 加入房间', () {
    testWidgets('★ 输 6 位号 → 找不到局域网房时回退本机会话，横幅明示「本机预览」',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();
      await _pushNamed(tester, AppRoutes.room);

      await tester.enterText(find.byKey(RoomEntryKeys.joinCode), 'k3m9qz');
      await tester.enterText(find.byKey(RoomEntryKeys.joinNick), '调查员甲');
      await tester.pump();

      await tester.tap(find.byKey(RoomEntryKeys.joinSubmit));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final scope = tester.widget<RoomScope>(find.byType(RoomScope));
      final session = scope.session as LocalLoopbackSession;
      expect(session.role, RoomRole.player, reason: '加入者是玩家视角');
      expect(session.code, 'K3M9QZ', reason: '小写房间号要被规范化成大写');

      // 本机预览会话：自己在花名册里
      final members = asList(session.state['members']);
      expect(members.length, 1);
      expect(jsStr(asMap(members.single)['seat']), 'p1');
      expect(jsStr(asMap(members.single)['nickname']), '调查员甲');

      // ★ 不骗用户：进房间后的横幅明说这是本机预览
      final banner = _bannerText(tester);
      expect(banner.contains('本机预览'), isTrue);
      expect(banner.contains('本机'), isTrue);
    });

    testWidgets('★ 「找附近的房间」能打开列表；没扫到时给排查清单（不是干等）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();
      // ★ P9 需求 5：首页 → 规则选择页 → 跑团房间入口
      await tester.tap(find.byKey(const Key('fab_room')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rule_pick_coc7')));
      await tester.pumpAndSettle();

      // 入口在加入区，与「加入」并列 —— 用户不必先知道房号才能找房。
      expect(find.byKey(RoomEntryKeys.nearby), findsOneWidget);

      await tester.ensureVisible(find.byKey(RoomEntryKeys.nearby));
      await tester.pump();
      await tester.tap(find.byKey(RoomEntryKeys.nearby));
      // 弹层进入动画约 250ms，且扫描桩会立即返回空列表。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(NearbyKeys.root), findsOneWidget,
          reason: '★ 从真实入口能打开；打不开说明 RoomScope 没覆盖到弹层');
      expect(find.byKey(NearbyKeys.empty), findsOneWidget,
          reason: '测试里关掉了发现 ⇒ 必然是空态');
      expect(tester.takeException(), isNull);
    });

    testWidgets('填了手输地址也不会卡（网络关闭时立即回退本机预览）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();
      // ★ P9 需求 5：首页 → 规则选择页 → 跑团房间入口
      await tester.tap(find.byKey(const Key('fab_room')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rule_pick_coc7')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(RoomEntryKeys.joinCode), 'K3M9QZ');
      await tester.enterText(find.byKey(RoomEntryKeys.joinNick), '甲');
      await tester.enterText(
          find.byKey(RoomEntryKeys.joinBase), '192.168.1.7:4211');
      await tester.tap(find.byKey(RoomEntryKeys.joinSubmit));
      await tester.pumpAndSettle();

      // 网络关闭 ⇒ join 立即返回失败 ⇒ 回退本机预览。
      // 这条守的是「不能因为填了地址就卡在连接中」。
      expect(find.byKey(RoomEntryKeys.joinBase), findsNothing,
          reason: '应该已经离开入口页进房间了');
      expect(_bannerText(tester).contains('本机预览'), isTrue);
    });

    testWidgets('房间号不合法 → 不进房间，入口页给出错误提示',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();
      await _pushNamed(tester, AppRoutes.room);

      await tester.enterText(find.byKey(RoomEntryKeys.joinCode), 'abc');
      await tester.tap(find.byKey(RoomEntryKeys.joinSubmit));
      await tester.pump();

      expect(find.byType(RoomScope), findsNothing);
      expect(find.textContaining('房间号应为'), findsOneWidget);
    });
  });

  // ----------------------------------------------------------
  // ③ 续玩
  // ----------------------------------------------------------
  group('③ 续玩', () {
    testWidgets('★ 存档槽有货 → 列表可列、可载入（meta 恢复）',
        (WidgetTester tester) async {
      // 先造一份真实存档（走生产装配 + exportSave，不手搓 Map）
      final seed = await bootLocalRoom(
        code: 'OLD666',
        name: '旧团·洋馆',
        nickname: '老K',
      );
      final save = seed.session.exportSave();
      expect(save, isNotNull);
      roomSaveSlots.put('OLD666', save!);
      seed.dispose();

      final f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();
      await _pushNamed(tester, AppRoutes.room);

      expect(find.byKey(RoomEntryKeys.resumeEmpty), findsNothing);
      expect(find.byKey(RoomEntryKeys.resumeRow('OLD666')), findsOneWidget);
      expect(find.text('旧团·洋馆'), findsOneWidget);

      await tester.tap(find.byKey(RoomEntryKeys.resumeLoad('OLD666')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final scope = tester.widget<RoomScope>(find.byType(RoomScope));
      final session = scope.session as LocalLoopbackSession;
      expect(jsStr(asMap(session.host.state['meta'])['name']), '旧团·洋馆',
          reason: '★ 载入必须真的把存档灌回权威态');
      expect(jsStr(asMap(session.host.state['meta'])['code']), 'OLD666');

      final banner = _bannerText(tester);
      expect(banner.contains('已载入本机存档'), isTrue);
    });

    testWidgets('续玩区如实说明「关闭 App 后不保留」', (WidgetTester tester) async {
      final f = await _boot(tester);
      await tester.pumpWidget(_app(f));
      await tester.pump();
      await _pushNamed(tester, AppRoutes.room);

      final hint =
          tester.widget<Text>(find.byKey(RoomEntryKeys.resumeHint)).data ?? '';
      expect(hint.contains('关闭 App 后不保留'), isTrue,
          reason: '★ 测试用的是内存后端（roomSaveSlots），文案不许做成永久存档的错觉');
    });

    testWidgets('★ 换成文件后端 → 文案跟着改口（不能继续说「会丢」）',
        (WidgetTester tester) async {
      // 这是本次改动的核心承诺：文案跟后端能力走，不是写死一句。
      // 写死的话，换后端那天界面就变成骗用户。
      //
      // ★ 视口：房间入口页顶部现在有一张 48px 头图（P8），默认 800×600 下
      //   「③ 续玩」会落到折叠线以下 —— ListView 懒加载不构建它，
      //   resumeHint 自然找不到。换成**手机竖屏**尺寸（420×1400），
      //   与真机（Magic9 ≈ 412×888）同档。
      //   注意不是放宽断言：断言一字未改，只是让测试视口贴合实际设备。
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dir = Directory.systemTemp.createTempSync('dice_entry_hint_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final fileStore = FileRoomSaveStore(dir)..loadSync();

      await tester.pumpWidget(
        MaterialApp(home: RoomEntryPage(saveStore: fileStore)),
      );
      await tester.pump();

      final hint =
          tester.widget<Text>(find.byKey(RoomEntryKeys.resumeHint)).data ?? '';
      expect(hint.contains('关闭 App 后不保留'), isFalse,
          reason: '★ 文件后端不会因为关 App 丢档，这句就变成假话了');
      expect(hint.contains('文件'), isTrue);
      expect(hint.contains('不卸载'), isTrue);
    });

    testWidgets('★ 没有存档后端（远端会话）→ 明说「只有房主能保存」',
        (WidgetTester tester) async {
      // 这个分支没法通过 RoomEntryPage 测：它的 `_store` 会退回全局
      // roomSaveSlots（永远非空）。真正的 null 分支在
      // file_room_save_store_test.dart 的「持久化文案」组里钉。
      //
      // 这里只留一句说明，避免以后有人以为漏测了。
      expect(savePersistHintOf(null).contains('只有房主能保存'), isTrue);
    });
  });

  _sheetGroups();
  _saveStoreGroup();
  _madnessPortGroup();
  _gateGroup();
}

// ------------------------------------------------------------
// 三个弹层的宿主：作用域挂在 Navigator 之上（`showRoomSheet` 才能重提供）
// ★ 宿主**不订阅 local**：缩放那条用例要证明弹层自己订阅了。
// ------------------------------------------------------------
Widget _sheetHost(
  RoomUiFixture f,
  RoomBoot boot,
  Widget Function(BuildContext) trigger,
) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => RepoScope(
      repo: f.repo,
      child: RoomScope(
        session: boot.session,
        local: boot.local,
        controller: boot.controller,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
    home: Scaffold(
      body: Center(child: Builder(builder: trigger)),
    ),
  );
}

/// 造一个开好的房间（默认 KP = 本机）。
///
/// ★ 绑卡必须用**玩家**视角：`char.share` 在 POLICY 里只放行 player，
///   而且 KP 不在花名册里（只有 attach 过的玩家/旁观才是成员）。
Future<RoomBoot> _bootRoom(
  WidgetTester tester, {
  String role = RoomRole.kp,
  String seat = 'p1',
  String nickname = '调查员甲',
}) async {
  final boot = await bootLocalRoom(
    code: 'K3M9QZ',
    name: '测试团',
    nickname: role == RoomRole.kp ? '老K' : nickname,
    role: role,
    seat: seat,
  );
  // fake-async 里真实 Timer 永不返回：关掉提示的自动消失。
  boot.local.scheduleDismiss = (_, _) => null;
  addTearDown(boot.dispose);
  return boot;
}

/// 去掉会漂移的字段时间戳（两次 `sanitizeSheet` 各取一次 `now`）。
Map<String, Object?> _stripVolatile(Map<String, Object?> sheet) =>
    <String, Object?>{...sheet}..remove('at');

/// 一张带数值的车卡（走生产默认卡，不手搓陌生形状）。
///
/// ⚠️ `repo.save()` 会跑一次 `recalc`：属性会**重算** status（maxHP/maxMP/maxSAN
/// 由属性推出，currentHP 回到上限）。所以断言一律以「存回去再读出来」的那张卡为准，
/// 不要拿构造时的中间值。
Character _card({
  String id = 'c1',
  String name = '李探',
  int hp = 11,
  int san = 55,
}) {
  final raw = newCharacter();
  raw['id'] = id;
  raw['characterName'] = name;
  raw['attributes'] = <String, Object?>{
    'str': 50,
    'con': 55,
    'siz': 60,
    'dex': 61,
    'app': 45,
    'int': 70,
    'pow': 65,
    'edu': 80,
  };
  final st = <String, Object?>{...asMap(raw['status'])};
  st['currentHP'] = hp;
  st['maxHP'] = 12;
  st['currentSAN'] = san;
  st['maxSAN'] = 99;
  st['body'] = '正常';
  raw['status'] = st;
  raw['skills'] = <Object?>[
    <String, Object?>{'name': '侦查', 'total': 70},
    <String, Object?>{'name': '图书馆使用', 'total': 55},
  ];
  return Character(raw);
}

// ------------------------------------------------------------
// 三个弹层
// ------------------------------------------------------------
void _sheetGroups() {
  group('弹层 · 绑定角色卡', () {
    testWidgets('本机没有卡 → 空态；有卡 → 列表可点', (WidgetTester tester) async {
      final f = await _boot(tester);
      final boot = await _bootRoom(tester);
      await tester.pumpWidget(_sheetHost(
        f,
        boot,
        (BuildContext ctx) => RoomTap(
          key: const Key('openBind'),
          label: '绑卡',
          onTap: () => openBindCharSheet(ctx),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const Key('openBind')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(BindCharSheetKeys.root), findsOneWidget);
      expect(find.byKey(BindCharSheetKeys.empty), findsOneWidget);
      expect(find.byKey(BindCharSheetKeys.clear), findsOneWidget);

      // 关掉弹层，往仓库塞一张卡，再看列表
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await f.repo.save(_card());
      await tester.pump();

      await tester.tap(find.byKey(const Key('openBind')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(BindCharSheetKeys.empty), findsNothing);
      expect(find.byKey(BindCharSheetKeys.row('c1')), findsOneWidget);
      expect(find.text('李探'), findsOneWidget);
    });

    testWidgets('★ 选中一张卡 → 发 INTENT.CHAR，载荷 sheet 与搬运函数逐字段一致',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      await f.repo.save(_card());
      // ★ P10 第 3 期 B（修掉 QA `qa_p10_4_report.md` §3a 登记的「前提陈旧假绿」）：
      //   本用例改前断言「没有头像 → 不带 avatar 键」，那只在替身返回空串时成立；
      //   P10-3A 起**没上传头像的玩家就是会带自动头像 PNG**。
      //   现在改成正向口径：给一个确定 PNG 替身，断言载荷真的带上它。
      //   「生成器拿不到东西 → 删键」的降级路径由
      //   `test/p10_t3b_rule_diff_test.dart` + `p10_t2_avatar_test` E1/E3 钉住。
      const autoPng = 'data:image/png;base64,AAAB';
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      autoAvatarPngEncoder = (spec) async => autoPng;
      // recalc 之后的卡才是权威形状（属性→上限由 rules 算）
      final card = f.repo.get('c1')!;
      // 绑卡是玩家动作（KP 走这条会被权威端拒绝）
      final boot = await _bootRoom(tester, role: RoomRole.player);
      boot.hub.sent.clear();

      await tester.pumpWidget(_sheetHost(
        f,
        boot,
        (BuildContext ctx) => RoomTap(
          key: const Key('openBind'),
          label: '绑卡',
          onTap: () => openBindCharSheet(ctx),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('openBind')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.byKey(BindCharSheetKeys.pick('c1')));
      await tester.pump();

      final sent = boot.hub.sent.entries;
      final char = sent.lastWhere((Map<String, Object?> e) => e['op'] == RoomIntent.char);
      expect(char['kind'], 'intent');
      final payload = asMap(char['p']);
      expect(payload['id'], 'c1');
      expect(payload['name'], '李探');
      // ★ 键名搬运 + domain 白名单，两边逐字段相等（时间戳除外）
      //
      // P10 第 2 期 A：绑卡上报时 `sheet.avatar` 换成**跨设备缩略 dataURI**。
      // P10 第 3 期 A：没有上传头像时改成「自动头像渲染成 PNG 再上报」。
      // 因此期望值要把这张自动 PNG 加回去再比，其余字段逐字段相同。
      final expectSheet = _stripVolatile(cardToRoomSheet(card))
        ..['avatar'] = autoPng;
      expect(_stripVolatile(asMap(payload['sheet'])), equals(expectSheet));
      expect(asMap(payload['sheet'])['avatar'], autoPng,
          reason: '没上传头像也应带自动头像 PNG（广播判据只收 png/jpeg/webp）');
      // 抽查关键字段，防止「两边一起错」
      final sheet = asMap(payload['sheet']);
      expect(asMap(sheet['attrs'])['dex'], 61);
      expect(asList(sheet['skills']).length, 2);
      expect(asMap(sheet['status'])['currentHP'],
          asMap(card.status)['currentHP']);
      expect(asMap(sheet['status'])['maxSAN'], asMap(card.status)['maxSAN']);

      // 权威端真的把房卡换掉了
      final me = asMap(memberOfSeat(boot.session.state, 'p1'));
      expect(asMap(me['sheet'])['name'], '李探');
      expect(asMap(asMap(me['sheet'])['attrs'])['dex'], 61);
    });
  });

  group('弹层 · 存档槽', () {
    testWidgets('★ 新建 → 存档里有条目；载入 → 权威态恢复；删除 → 条目消失',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final boot = await _bootRoom(tester);
      await tester.pumpWidget(_sheetHost(
        f,
        boot,
        (BuildContext ctx) => RoomTap(
          key: const Key('openSlots'),
          label: '存档',
          onTap: () => openSaveSlotsSheet(ctx),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('openSlots')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // ① 新建：默认名 = 房间号
      expect(find.byKey(SaveSlotsKeys.empty), findsOneWidget);
      final defaultName =
          tester.widget<TextField>(find.byKey(SaveSlotsKeys.name)).controller!.text;
      expect(defaultName, 'K3M9QZ');

      await tester.tap(find.byKey(SaveSlotsKeys.save));
      await tester.pump();
      await tester.pump();
      expect(roomSaveSlots.list(), contains('K3M9QZ'));
      expect(find.byKey(SaveSlotsKeys.row('K3M9QZ')), findsOneWidget);

      // ② 改动房间状态，再从存档载入 → 恢复
      await boot.session.hostAction('scene.mode', <String, Object?>{
        'mode': RoomMode.combat,
      });
      await tester.pump();
      expect(jsStr(asMap(boot.host.state['meta'])['mode']), RoomMode.combat);

      await tester.tap(find.byKey(SaveSlotsKeys.load('K3M9QZ')));
      await tester.pump();
      await tester.pump();
      expect(jsStr(asMap(boot.host.state['meta'])['mode']), RoomMode.exploration,
          reason: '★ 载入必须真的把存档灌回权威态');

      // ③ 删除：ConfirmTwice 点两次
      await tester.tap(find.byKey(const Key('openSlots')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(SaveSlotsKeys.remove('K3M9QZ')));
      await tester.pump();
      expect(roomSaveSlots.list(), contains('K3M9QZ'), reason: '第一次只上膛');
      await tester.tap(find.byKey(SaveSlotsKeys.remove('K3M9QZ')));
      await tester.pump();
      expect(roomSaveSlots.list(), isNot(contains('K3M9QZ')));
    });

    testWidgets('存档区如实说明「关闭 App 后不保留」', (WidgetTester tester) async {
      final f = await _boot(tester);
      final boot = await _bootRoom(tester);
      await tester.pumpWidget(_sheetHost(
        f,
        boot,
        (BuildContext ctx) => RoomTap(
          key: const Key('openSlots'),
          label: '存档',
          onTap: () => openSaveSlotsSheet(ctx),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('openSlots')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final hint = tester.widget<Text>(find.byKey(SaveSlotsKeys.hint)).data ?? '';
      expect(hint.contains('关闭 App 后不保留'), isTrue);
    });
  });

  group('弹层 · 杂项', () {
    testWidgets('★ 缩放档位：点 70% → local.zoom 变化，且百分比文本自己跟着变',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final boot = await _bootRoom(tester);
      await tester.pumpWidget(_sheetHost(
        f,
        boot,
        (BuildContext ctx) => RoomTap(
          key: const Key('openMisc'),
          label: '更多',
          onTap: () => openMiscSheet(ctx),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('openMisc')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(MiscSheetKeys.root), findsOneWidget);
      String pct() =>
          tester.widget<Text>(find.byKey(MiscSheetKeys.zoomPct)).data ?? '';
      expect(pct(), '100%');

      // ★ 钉死「弹层自己订阅了 local」：宿主不订阅，点完必须立刻变
      await tester.tap(find.byKey(MiscSheetKeys.zoom(70)));
      await tester.pump();
      expect(boot.local.zoom, closeTo(0.70, 1e-9));
      expect(pct(), '70%',
          reason: '★ 百分比文本要跟着 local 变（弹层内 ListenableBuilder(local)）');

      // 零发包：缩放纯本地
      expect(boot.hub.sent.isEmpty, isTrue);
    });

    testWidgets('规则参考 / 观众名单 / P2 入口按约定渲染',
        (WidgetTester tester) async {
      final f = await _boot(tester);
      final boot = await _bootRoom(tester);
      await tester.pumpWidget(_sheetHost(
        f,
        boot,
        (BuildContext ctx) => RoomTap(
          key: const Key('openMisc'),
          label: '更多',
          onTap: () => openMiscSheet(ctx),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('openMisc')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(MiscSheetKeys.rules), findsOneWidget);
      expect(find.byKey(MiscSheetKeys.spectators), findsOneWidget);
      expect(find.byKey(MiscSheetKeys.itemsEmpty), findsOneWidget);

      // ★ P17 KP-8：音乐控制台入口已从「更多工具」上移一级到「KP 工具」
      //   （`KpPanelKeys.music`）。本弹层改成**不含音乐入口**的正向断言；
      //   KP 工具侧的 widget 级断言在 `sheet_music_test.dart`。
      expect(find.byKey(MiscSheetKeys.musicEntry), findsNothing,
          reason: 'KP-8：音乐入口已上移，「更多工具」不再渲染');
      // ★ P17 KP-8：`musicSection` 这个 key 刻意沿用（现在是「本机工具」
      //   节标题，只剩游戏历史导出），既有测试按名引用不断。
      final section = tester
              .widget<Text>(find.byKey(MiscSheetKeys.musicSection))
              .data ??
          '';
      expect(section, '本机工具',
          reason: 'KP-8：节标题已从「音乐」改为「本机工具」');

      // ★ P16 P-2：「更多工具」弹层里的 AI RP 禁用指引件已整块删除。
      //   注意这不是「删功能」—— 真入口仍在两处（聊天输入行魔棒 + 角色卡
      //   AI RP 按钮），本文件末尾的源码锚点 + `p16_button_unify_test.dart`
      //   的 widget 级断言共同守住「功能没丢」。
      expect(find.byKey(MiscSheetKeys.aiEntry), findsNothing,
          reason: 'P-2：更多工具弹层不含 AI RP 条目');
      expect(find.byKey(MiscSheetKeys.aiHint), findsNothing,
          reason: 'P-2：AI RP 禁用指引文案已删');
      expect(find.textContaining('AI RP'), findsNothing,
          reason: 'P-2：本弹层里不该再有 AI RP 相关字样');
    });

    test('★ P-2 源码锚点：AI RP 真入口仍在（聊天输入行 / 角色卡）', () {
      final feeds =
          File('lib/ui/room/widgets/gp_feeds.dart').readAsStringSync();
      expect(feeds.contains('GpFeedsKeys.aiRp'), isTrue,
          reason: '聊天输入行的 AI RP 魔棒入口不能被删');
      expect(feeds.contains('openAiRpSheet('), isTrue,
          reason: '魔棒必须接到真弹层（不是假入口）');

      final card =
          File('lib/ui/room/widgets/gp_pl_char_card.dart').readAsStringSync();
      expect(card.contains('GpPlCharCardKeys.aiBtn'), isTrue,
          reason: '角色卡上的 AI RP 入口不能被删');

      final misc = File('lib/ui/room/sheets/sheet_misc.dart').readAsStringSync();
      expect(misc.contains('MiscSheetKeys.aiEntry'), isFalse,
          reason: 'P-2：更多工具弹层不许再引用被删的 AI RP 条目 key');
      expect(misc.contains('MiscSheetKeys.aiHint'), isFalse,
          reason: 'P-2：更多工具弹层不许再引用被删的指引文案 key');
    });
  });
}

// ------------------------------------------------------------
// 机械门禁（B1 新增的 6 个文件）
// ------------------------------------------------------------
void _gateGroup() {
  group('门禁 · B1 新文件零命中', () {
    test('6 个文件纯净：零死代码名 / 零规则入口 / 零权威赋值 / 注释零框架字面量', () {
      const files = <String>[
        'room_boot.dart',
        'room_entry_page.dart',
        'sheets/card_sheet_payload.dart',
        'sheets/sheet_bind_char.dart',
        'sheets/sheet_save_slots.dart',
        'sheets/sheet_misc.dart',
      ];
      // 死代码名与「客户端自己算规则」的入口：全部文件都不许出现
      const banned = <String>[
        'plBottomBar',
        'plFeeds',
        'kpChat',
        'kpGameLog',
        'rules?.check(',
        'rollExpr(',
        'opposedFull(',
      ];
      expect(files.length, 6, reason: 'B1 应恰好新增 6 个文件');

      for (final rel in files) {
        final src = File('lib/ui/room/$rel').readAsStringSync();
        for (final word in banned) {
          expect(src.contains(word), isFalse, reason: '$rel 命中 $word');
        }
        // `RoomHost` 只允许出现在组合根（room_boot）；弹层与页面不许直接摸权威端
        if (rel != 'room_boot.dart') {
          expect(src.contains('RoomHost('), isFalse,
              reason: '$rel 不许自己 new 权威端（应走 room_boot 的装配）');
        }
        // 权威快照赋值（形如 state[...] = ）零出现
        expect(RegExp(r'state\s*\[[^\]]+\]\s*=').hasMatch(src), isFalse,
            reason: '$rel 出现权威快照赋值');
        // 注释里不许出现框架 / IO 库的导入字面量（机械门禁是朴素 grep）
        for (final line in src.split('\n')) {
          if (!line.trimLeft().startsWith('//')) continue;
          for (final word in <String>['package:flutter', 'dart:io', 'dart:ui']) {
            expect(line.contains(word), isFalse, reason: '$rel 注释命中 $word');
          }
        }
      }
    });
  });
}

// ------------------------------------------------------------
// 存档后端：深拷贝快照（(c) 的回归网）
// ------------------------------------------------------------
void _saveStoreGroup() {
  group('存档后端 · 深拷贝快照', () {
    test('★ save() → 继续推进房间 → get() 仍是保存那一刻', () async {
      final boot = await bootLocalRoom(
        code: 'SNAP01',
        name: '快照团',
        nickname: '老K',
      );
      addTearDown(boot.dispose);

      // 先聊两句，让存档里有真实内容（空房间的 chats / logs 都是 0，断言会空转）
      await boot.session.hostAction('chat', <String, Object?>{
        'text': '存档前的第一句',
      });
      // ★ P13 产品行为真变（更强口径）：saveNow 的槽名会先过
      //   `_sanitizeSaveKey`（非 [A-Za-z0-9_-] → '-' → 压缩 → 去首尾，空则退房号）。
      //   '槽A' 的「槽」被清洗掉，落盘键是 'A' —— 这里显式钉死清洗后的键，
      //   并反证原始中文键**没有**被直接写进 store（否则 FileRoomSaveStore
      //   会整条拒写）。核心断言（深拷贝快照）一字未动。
      expect(await boot.controller.saveNow(name: '槽A'), isTrue);
      expect(roomSaveSlots.get('A'), isNotNull,
          reason: '★ 清洗后的键 A 必须落盘');
      expect(roomSaveSlots.get('槽A'), isNull,
          reason: '★ 含中文的原始槽名不许直接当键（FileRoomSaveStore 会拒写）');

      final saved = roomSaveSlots.get('A')!;
      final chatsAtSave = asList(saved['chats']).length;
      final seqAtSave = saved['seq'];
      expect(chatsAtSave, greaterThan(0), reason: '存档里得有内容，断言才不空转');

      // 继续玩：再造几条事件
      await boot.session.hostAction('chat', <String, Object?>{
        'text': '存档之后说的话',
      });
      await boot.session.hostAction('round.next');
      expect(asList(boot.host.state['chats']).length, greaterThan(chatsAtSave),
          reason: '反证：权威态确实往前走了');

      final again = roomSaveSlots.get('A')!;
      expect(asList(again['chats']).length, chatsAtSave,
          reason: '★ 存档必须是保存那一刻的快照，不被后续事件污染');
      expect(again['seq'], seqAtSave, reason: '★ 序号也要停在保存那一刻');
    });

    test('★ 槽名清洗：非法字符→合法键，内容不丢档、可再读回', () async {
      final boot = await bootLocalRoom(
        code: 'SNAP03',
        name: '快照团',
        nickname: '老K',
      );
      addTearDown(boot.dispose);

      await boot.session.hostAction('chat', <String, Object?>{
        'text': '清洗探针',
      });
      // '槽 2/3' → 非 [A-Za-z0-9_-] 全变 '-' → 压缩 → 去首尾 = '2-3'
      expect(await boot.controller.saveNow(name: '槽 2/3'), isTrue);
      final cleaned = roomSaveSlots.get('2-3');
      expect(cleaned, isNotNull, reason: '★ 清洗后的键 2-3 必须落盘（不丢档）');
      expect(asList(cleaned!['chats']), isNotEmpty,
          reason: '★ 清洗只改键，不改档内容');
      expect(roomSaveSlots.get('槽 2/3'), isNull,
          reason: '★ 原始非法槽名不得作为键出现');
      // 全非法字符 → 退回房号键，仍然要能存档
      expect(await boot.controller.saveNow(name: '槽'), isTrue,
          reason: '★ 全非法字符时退回房号兜底，不静默失败');
    });

    test('★ 存档与调用方不共享嵌套引用（put 侧 + get 侧各一条）', () async {
      final boot = await bootLocalRoom(
        code: 'SNAP02',
        name: '快照团',
        nickname: '老K',
      );
      addTearDown(boot.dispose);

      // 先造一条聊天，让存档里有嵌套 List<Map> 可验（空存档验不出别名）
      await boot.session.hostAction('chat', <String, Object?>{
        'text': '存档前的第一句',
      });

      // put 侧：改「交给 store 的那份」不能反写存档
      final source = boot.session.exportSave()!;
      roomSaveSlots.put('槽B', source);
      asMap(source['meta'])['name'] = '被改掉的';
      expect(jsStr(asMap(roomSaveSlots.get('槽B')!['meta'])['name']), '快照团',
          reason: '★ put 必须深拷贝：源对象事后被改也不能影响存档');

      // get 侧：改「从 store 取出的那份」不能反写存档
      final taken = roomSaveSlots.get('槽B')!;
      asMap(asMap(taken['meta']))['name'] = '又被改掉的';
      expect(jsStr(asMap(roomSaveSlots.get('槽B')!['meta'])['name']), '快照团',
          reason: '★ get 必须深拷贝：取出的副本被就地改也不能污染存档');

      // 嵌套 List<Map> 同样不许共享：就地改取出的那条聊天
      final taken2 = roomSaveSlots.get('槽B')!;
      final chats = asList(taken2['chats']);
      expect(chats, isNotEmpty, reason: '存档里要有聊天才能验嵌套 List');
      asMap(chats.first)['text'] = '被改掉的话';
      expect(
          jsStr(asMap(asList(roomSaveSlots.get('槽B')!['chats']).first)['text']),
          isNot('被改掉的话'),
          reason: '★ List<Map> 也必须深拷贝');
      // 权威态也不受影响
      expect(jsStr(asMap(asList(boot.host.state['chats']).first)['text']),
          '存档前的第一句');

      // 更硬的一条：两条 get 之间也不共享嵌套对象
      final a = roomSaveSlots.get('槽B')!;
      final b = roomSaveSlots.get('槽B')!;
      expect(identical(asMap(a['meta']), asMap(b['meta'])), isFalse);
      expect(identical(asList(a['chats']).first, asList(b['chats']).first), isFalse);
    });
  });
}

// ------------------------------------------------------------
// 疯狂表端口（CocMadness 落在 domain 之后的行为钉死）
// ------------------------------------------------------------
void _madnessPortGroup() {
  group('疯狂表端口 · CocMadness', () {
    test('「any」走 1D10 即时症状表；phobia/mania 直接抽子表；轮次 1D10', () {
      const port = CocMadness();

      // 'any'（`raRollSymptom` 的调用方式）与 domain 的 rollTable 同源
      final any = port.roll('any', false, () => 0.0)!;
      expect(any['type'], jsStr(madness.rollTable(() => 0.0)['kind']));
      expect(kRaMadTypes.contains(any['type']), isTrue);
      expect(any['rounds'], 1, reason: '1 + floor(0*10)');

      // 手动指定表：直接从该 100 条子表抽
      final ph = port.roll('phobia', false, () => 0.0)!;
      expect(ph['type'], 'phobia');
      expect(jsStr(ph['name']), isNotEmpty);
      final ma = port.roll('mania', false, () => 0.0)!;
      expect(ma['type'], 'mania');

      // permanent → 轮次归零，不随推进消退
      final perm = port.roll('phobia', true, () => 0.5)!;
      expect(perm['permanent'], isTrue);
      expect(perm['rounds'], 0);

      // 随机源给 1.0 / 负数的边界：不越界、不抛
      expect(port.roll('phobia', false, () => 1.0), isNotNull);
      expect(port.roll('mania', false, () => -0.5), isNotNull);

      // KP 手填症状名以手填为准
      final named = port.make('phobia', false, '怕水', () => 0.0)!;
      expect(jsStr(named['name']), '怕水');
    });
  });
}

/// ★ P10 第 3 期 A 批：自动头像 PNG 化是 `picture.toImage()` 的真异步，
/// 在 fake-async 区域里永不完成 → 绑卡链路会卡在 `await`。
/// 与既有 `avatarThumbEncoder` 同一套注入规矩（见 `repo/avatar_thumb.dart`），
/// 这里统一换成同步返回空串的替身；头像 PNG 本身由
/// `test/p10_t3_broadcast_potential_png_test.dart` 的 C 组覆盖。
void _stubAutoAvatarPng() {
  final saved = autoAvatarPngEncoder;
  addTearDown(() => autoAvatarPngEncoder = saved);
  autoAvatarPngEncoder = (spec) async => '';
}
