// ============================================================
// test/room_ui_player_test.dart — P5/T05-B2b · 跨块玩家整合流程
//
// 一条**完整链路**串起散在各批次的块（不重复单块测试的细项）：
//
//   ① 绑卡      — 大厅 R5「角色卡」→ 绑卡弹层 → 选一张卡
//   ② 准备      — 大厅 R4「准备」→ 我准备好了
//   ③ KP 开局   — 大厅 R6「开始游戏」（真 action `room.start`）
//   ④ 掷骰      — 游戏页骰子条 → 1D100
//   ⑤ 改状态请求 — 我的角色卡 → 状态管理 → 提交 SAN（需 KP 同意）
//   ⑥ KP 同意   — KP 工具弹层「待你确认」→ 确认
//   ⑦ 数值生效 — 权威态 currentSAN 变成提交值
//
// ★ 每一步都断言 `host.state`（权威态），**不看 UI 文案**：
//   UI 文案改一个字不该让这条链路红，而「数值没真变」必须红。
// ★ 铁律：T1 全内存后端（角色卡仓库也是内存实现，零文件读写）；
//   T5 `useRoomScreen`；T8 玩家侧只发 intent，权威态由 KP 视角读。
// ★ 不用 `pumpAndSettle()`：夹具把提示条的自动消失换成了空实现，
//   但弹层路由动画仍要手动推进（`pump(Duration)`），别指望 settle。
// ============================================================

import 'package:dice_realm/domain/character.dart' show Character, newCharacter;
import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart'
    show RoomIntent, RoomRole, RoomStatus, kHostSeat;
import 'package:dice_realm/repo/repo_scope.dart'
    show RepoScope, SettingsScope, ShareScope;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/sheets/sheet_bind_char.dart'
    show BindCharSheetKeys;
import 'package:dice_realm/ui/room/room_request_watcher.dart'
    show RoomPushKeys, RoomRequestWatcher;
import 'package:dice_realm/ui/room/sheets/sheet_kp_panel.dart'
    show KpPanel, KpPanelKeys;
import 'package:dice_realm/ui/room/sheets/sheet_self_state.dart'
    show GpSelfStateKeys;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart'
    show GpDiceBar, GpDiceBarKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart'
    show GpPlCharCard, GpPlCharCardKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart'
    show autoAvatarPngEncoder;

// ------------------------------------------------------------
// 夹具
// ------------------------------------------------------------

/// 单玩家 + 单旁观：开局前置「全员已准备」只需 p1 一个人点头。
///
/// `withSheets: false` —— 本链路要**从没绑卡开始**走一遍绑卡，
/// 夹具默认会给每个玩家塞一张卡，那样第 ① 步就永远测不到。
Future<RoomUiFixture> _boot(WidgetTester tester) async {
  final RoomUiFixture f = RoomUiFixture();
  await f.boot(players: 1, spectators: 1, withSheets: false);
  useRoomScreen(tester, 900, 1600);
  return f;
}

/// 三件套作用域 + 房间作用域（与夹具 `shell()` 同层级）。
///
/// 绑卡弹层要 `RepoScope`（角色卡仓库），所以这里不能只套 `RoomScope`。
Widget _wrap(RoomUiFixture f, String seat, Widget child) => RepoScope(
      repo: f.repo,
      child: SettingsScope(
        repo: f.settings,
        child: ShareScope(
          service: f.share,
          child: f.scoped(seat, child: child),
        ),
      ),
    );

/// 页面宿主：整页自带 Scaffold / ListView，**不能**再套滚动容器
/// （套了会给 Scaffold 无限高约束，直接 layout 崩）。
Widget _pageHost(RoomUiFixture f, String seat, Widget page) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) =>
          _wrap(f, seat, child ?? const SizedBox.shrink()),
      home: page,
    );

/// 弹层 / 块宿主：内容装进可滚动容器，块内 Wrap 子项全部建出来。
Widget _blockHost(RoomUiFixture f, String seat, Widget block) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) =>
          _wrap(f, seat, child ?? const SizedBox.shrink()),
      home: Scaffold(body: SingleChildScrollView(child: block)),
    );

/// 推一帧再走 400ms（弹层路由动画够用，且不像 settle 那样等无限定时器）。
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 取某座位在权威态里的成员表。
Map<String, Object?> _memberOf(RoomUiFixture f, String seat) {
  for (final Object? m in asList(f.hostState()['members'])) {
    final Map<String, Object?> mem = asMap(m);
    if (jsStr(mem['seat']) == seat) return mem;
  }
  return <String, Object?>{};
}

/// 权威态里该座位的 currentSAN（读 `sheet.status`）。
int _sanOf(RoomUiFixture f, String seat) {
  final Object? raw = asMap(_memberOf(f, seat)['sheet'])['status'];
  final Object? san = asMap(raw)['currentSAN'];
  if (san is int) return san;
  if (san is num) return san.toInt();
  return -1;
}

/// 权威态里该座位绑的角色卡 id（未绑卡 → 空串）。
String _charIdOf(RoomUiFixture f, String seat) {
  final Object? raw = asMap(_memberOf(f, seat)['sheet'])['charId'];
  return raw == null ? '' : jsStr(raw);
}

/// 该座位是否已准备。
bool _readyOf(RoomUiFixture f, String seat) =>
    asMap(_memberOf(f, seat))['ready'] == true;

/// 卡片 id（用例里多处引用）。
const String kCardId = 'card_p1';

/// 往内存角色卡仓库塞一张带数值的卡（零文件读写）。
Future<void> _seedCard(RoomUiFixture f) async {
  await f.repo.load();
  final Character card = Character(newCharacter());
  card.raw['id'] = kCardId;
  card.raw['characterName'] = '调查员甲';
  // 属性给真数：`repo.save()` 会跑一次 recalc（maxSAN = 意志 − 永久减损），
  // 属性留空串会推出 maxSAN 0，后面「改 SAN」就没观测空间了。
  card.raw['attributes'] = <String, Object?>{
    'str': 50,
    'con': 50,
    'siz': 50,
    'dex': 50,
    'app': 50,
    'int': 50,
    'pow': 60,
    'edu': 50,
    'luck': 50,
  };
  final Map<String, Object?> status = asMap(card.raw['status']);
  status['currentHP'] = 12;
  status['maxHP'] = 12;
  status['currentMP'] = 10;
  status['maxMP'] = 10;
  status['currentSAN'] = 50;
  status['maxSAN'] = 60;
  await f.repo.save(card);
  expect(f.repo.alive.length, greaterThanOrEqualTo(1),
      reason: '前置：内存角色卡仓库里应有一张卡');
}

void main() {
  // 自动头像 PNG 生成是引擎真异步：widget 测试里统一替身（见文件末注释）
  setUp(_stubAutoAvatarPng);

  testWidgets('完整链路：绑卡 → 准备 → KP 开局 → 掷骰 → 改状态请求 → KP 同意 → 数值生效',
      (WidgetTester tester) async {
    final RoomUiFixture f = await _boot(tester);
    await _seedCard(f);

    // ---- ① 绑卡（大厅 R5）----
    expect(_charIdOf(f, 'p1'), isEmpty, reason: '前置：p1 还没绑卡');
    await tester.pumpWidget(_pageHost(f, 'p1', const RoomLobbyPage()));
    await tester.pump();

    // 绑卡入口：R5 区块里的那个 RoomTap（标签「绑定角色卡」/「更换」都行）
    final Finder bindEntry = find.descendant(
      of: find.byKey(RoomLobbyKeys.bindChar),
      matching: find.byType(RoomTap),
    );
    expect(bindEntry, findsOneWidget, reason: '大厅 R5 应有绑卡入口');
    await tester.ensureVisible(bindEntry);
    await tester.pump();
    await tester.tap(bindEntry);
    await _settleSheet(tester);

    // 弹层里选那张卡
    final Finder pick = find.byKey(BindCharSheetKeys.pick(kCardId));
    expect(pick, findsOneWidget, reason: '绑卡弹层里应列出本机角色卡');
    await tester.tap(pick);
    await _settleSheet(tester);

    expect(_charIdOf(f, 'p1'), kCardId,
        reason: '绑卡后权威态 members[p1].sheet.charId 没变成 $kCardId');

    // ---- ② 准备（大厅 R4）----
    expect(_readyOf(f, 'p1'), isFalse);
    await tester.pumpWidget(_pageHost(f, 'p1', const RoomLobbyPage()));
    await tester.pump();
    final Finder readyBtn = find.descendant(
      of: find.byKey(RoomLobbyKeys.ready),
      matching: find.byType(RoomTap),
    );
    expect(readyBtn, findsOneWidget, reason: '大厅 R4 应有准备按钮');
    await tester.ensureVisible(readyBtn);
    await tester.pump();
    expect(tester.widget<RoomTap>(readyBtn).enabled, isTrue,
        reason: '绑好卡后准备按钮应可点（没卡时权威端会拒）');
    await tester.tap(readyBtn);
    await tester.pump();
    expect(_readyOf(f, 'p1'), isTrue, reason: '点了准备，权威态 ready 仍是 false');

    // ---- ③ KP 开局（大厅 R6，真 action room.start）----
    expect(jsStr(asMap(f.hostState()['meta'])['status']), RoomStatus.recruiting,
        reason: '前置：开局前状态应为招募中');
    await tester.pumpWidget(_pageHost(f, kHostSeat, const RoomLobbyPage()));
    await tester.pump();
    final Finder startBtn = find.byKey(RoomKeys.kpStartGame);
    expect(startBtn, findsOneWidget, reason: 'KP 大厅应有开始游戏按钮');
    await tester.ensureVisible(startBtn);
    await tester.pump();
    expect(tester.widget<RoomTap>(startBtn).enabled, isTrue,
        reason: '全员已准备时开始按钮应可点');
    await tester.tap(startBtn);
    await tester.pump();

    expect(jsStr(asMap(f.hostState()['meta'])['status']), RoomStatus.inGame,
        reason: '开了团但权威态状态不是 IN_GAME');

    // ---- ④ 掷骰（游戏页骰子条）----
    f.clearSent();
    final int diceBefore = asList(f.hostState()['dice']).length;
    await tester.pumpWidget(_blockHost(f, 'p1', const GpDiceBar()));
    await tester.pump();
    await tester.tap(find.byKey(GpDiceBarKeys.expr('1D100')));
    await tester.pump();

    final List<Object?> dice = asList(f.hostState()['dice']);
    expect(dice.length, diceBefore + 1, reason: '掷骰后权威态没新增骰记录');
    final Map<String, Object?> roll = asMap(dice.last);
    expect(jsStr(roll['seat']), 'p1');
    expect(roll['total'], inInclusiveRange(1, 100));
    expect(jsStr(roll['levelText']).isNotEmpty, isTrue);

    // ---- ⑤ 改状态请求（我的角色卡 → 状态管理）----
    // 目标值取「现状 ±1」：既保证确实变化，又不会触发「单次 SAN 损失 ≥5」
    // 的疯狂检定分支，让这条链路只验「提交流程」不掺别的副作用。
    final int sanBefore = _sanOf(f, 'p1');
    expect(sanBefore, greaterThan(0), reason: '前置：绑定后应有可读的 SAN');
    final int sanTarget = sanBefore >= 99 ? sanBefore - 1 : sanBefore + 1;

    await tester.pumpWidget(_blockHost(f, 'p1', GpPlCharCard()));
    await tester.pump();
    final Finder stateBtn = find.byKey(GpPlCharCardKeys.stateBtn);
    expect(stateBtn, findsOneWidget, reason: '角色卡块应有「状态管理」入口');
    await tester.ensureVisible(stateBtn);
    await tester.pump();
    await tester.tap(stateBtn);
    await _settleSheet(tester);

    expect(find.byKey(GpSelfStateKeys.root), findsOneWidget,
        reason: '状态管理弹层没打开');
    await tester.enterText(find.byKey(GpSelfStateKeys.san), '$sanTarget');
    await tester.pump();
    await tester.tap(find.byKey(GpSelfStateKeys.submitNumbers));
    await _settleSheet(tester);

    // 提交后进待确认队列，但**还没生效**
    expect(_sanOf(f, 'p1'), sanBefore,
        reason: '数字修改在 KP 同意前就已经生效了（越权）');
    final List<Map<String, Object?>> pending =
        f.sessionOf(kHostSeat).hostRead!.pending;
    final int askCount =
        pending.where((Map<String, Object?> q) => q['op'] == 'state.edit.self').length;
    expect(askCount, 1, reason: 'KP 的待确认队列里没有这条改数值请求：$pending');

    // ---- ⑥ KP 同意（P10 第 6 期收尾口径：入口改为页面级居中弹窗）----
    // 用户原话「推送消息弹窗后，kp工具箱里面的就不要有了」：KP 工具弹层里的
    // 「待处理」区块已整块撤掉，确认改由 `RoomRequestWatcher` 的居中弹窗承载。
    //
    // 前置整理：上一步那条请求已经验过「入队且未生效」，这里用**同一条 confirm
    // 通道**把它撤掉（controller 级，等价于点「拒绝」），让弹窗的已读基线干净
    // ——弹窗只弹「挂载之后新到」的请求（`Set<String> _seen` 按 id 去重）。
    f.controllerOf(kHostSeat).sendIntent(
      RoomIntent.confirm,
      <String, Object?>{'op': 'state.edit.self', 'by': 'p1', 'agree': false},
    );
    await tester.pump();
    expect(f.sessionOf(kHostSeat).hostRead!.pending, isEmpty,
        reason: '前置：先清空上一轮待确认，才能单独验弹窗这条路径');

    await tester.pumpWidget(_blockHost(
      f,
      kHostSeat,
      const RoomRequestWatcher(child: KpPanel()),
    ));
    await tester.pump();
    // ★ 新口径：弹层里不再有「待处理」标题 / 未读角标 / 确认行
    expect(find.text('待处理'), findsNothing,
        reason: '推送已由居中弹窗承载，KP 工具弹层不许再列一遍');
    expect(find.byKey(KpPanelKeys.pendingList), findsNothing);
    expect(find.byKey(KpPanelKeys.unread), findsNothing);
    expect(find.byKey(const ValueKey<String>('kpPanel/confirm/state.edit.self')),
        findsNothing);
    // 其余工具区块仍在（没有连带删掉别的东西）
    expect(find.text('工具 · 回合与检定'), findsOneWidget);
    expect(find.text('工具 · 战斗与场景'), findsOneWidget);
    expect(find.text('工具 · 房间管理'), findsOneWidget);

    // 真实再提交一次（玩家侧同 payload）→ 新请求 → 居中弹窗
    f.controllerOf('p1').hostAction('state.edit.self', <String, Object?>{
      'status': <String, Object?>{'currentSAN': sanTarget},
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final Finder agreeBtn = find.byKey(RoomPushKeys.agree);
    expect(agreeBtn, findsOneWidget,
        reason: 'KP 必须收到屏幕正中的推送弹窗（现在这是唯一的确认入口）');
    await tester.ensureVisible(agreeBtn);
    await tester.pump();
    await tester.tap(agreeBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // ---- ⑦ 数值生效 ----
    expect(_sanOf(f, 'p1'), sanTarget,
        reason: 'KP 同意后权威态 currentSAN 应为 $sanTarget，'
            '实际 ${_sanOf(f, 'p1')}（提交前 $sanBefore）');
    expect(f.sessionOf(kHostSeat).hostRead!.pending.where(
        (Map<String, Object?> q) => q['op'] == 'state.edit.self'),
        isEmpty,
        reason: '确认后这条请求应出队，不能留在待确认里反复可点');

    // 收尾：队列清空、状态仍是 IN_GAME（这条链路不该把房间搞挂）
    expect(jsStr(asMap(f.hostState()['meta'])['status']), RoomStatus.inGame);
  });

  testWidgets('断链保护：没绑卡就点准备 → 按钮禁用且权威态零变化',
      (WidgetTester tester) async {
    final RoomUiFixture f = await _boot(tester);
    await tester.pumpWidget(_pageHost(f, 'p1', const RoomLobbyPage()));
    await tester.pump();

    final Finder readyBtn = find.descendant(
      of: find.byKey(RoomLobbyKeys.ready),
      matching: find.byType(RoomTap),
    );
    expect(readyBtn, findsOneWidget);
    expect(tester.widget<RoomTap>(readyBtn).enabled, isFalse,
        reason: '没有 charId 时准备按钮应禁用（权威端会拒）');

    final int sentBefore = f.sent.length;
    await tester.tap(readyBtn);
    await tester.pump();
    expect(f.sent.length, sentBefore, reason: '禁用按钮竟然发出了意图');
    expect(_readyOf(f, 'p1'), isFalse);
  });

  testWidgets('旁观者视角：大厅里没有准备 / 绑卡入口（结构上不渲染）',
      (WidgetTester tester) async {
    final RoomUiFixture f = await _boot(tester);
    await tester.pumpWidget(_pageHost(f, 'sp1', const RoomLobbyPage()));
    await tester.pump();
    expect(find.byKey(RoomLobbyKeys.ready), findsNothing,
        reason: '旁观者不该看到准备块');
    expect(find.byKey(RoomLobbyKeys.bindChar), findsNothing,
        reason: '旁观者不该看到绑卡块');
    expect(find.byKey(RoomLobbyKeys.spectatorNote), findsOneWidget,
        reason: '旁观者应看到「旁观中」说明');
    expect(f.sessionOf('sp1').role, RoomRole.spectator);
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
