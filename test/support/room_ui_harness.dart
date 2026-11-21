// ============================================================
// test/support/room_ui_harness.dart — P5/T01 S1.4 房间 UI 测试夹具
//
// 契约来源：设计 §6.1「测试夹具 RoomUiFixture」。
//
// 一个「KP 端 + N 个玩家 + M 个旁观者」的完整**进程内**房间：
//   · T1 铁律：后端全部内存实现（存档 / 笔记 / 角色卡 / 分享），零文件 I/O
//     —— widget 测试跑在 fake-async 区域，真实 I/O 的 Future 永不完成；
//   · 复用 P4 已有的 room_fakes.dart#roomHostOpts（固定时钟 + Lcg +
//     确定性规则 / 疯狂表），本文件**不新造**第二个规则或随机源替身；
//   · 玩家视图来自 RoomClient.receive() 真正裁剪过的数据（T8），
//     绝不是拿权威态假装；
//   · `sent` 与 hub 的 SessionSendLog 是同一份引用 → T6「点了没反应」有唯一依据。
//
// ★ 页面壳为什么在测试侧：
//   游戏页（T02）、房间页 / 入口页（T05）在 T01 阶段还不存在，而夹具必须先
//   能 pump、能随 session 重建。所以这里画一个**只读摘要壳**：顶栏身份行 +
//   成员数值 + 信息流计数，全部取自 S1.2 落地的纯视图函数（不做二次隐藏）。
//   T02/T05 落地真页面后，把 `pageBuilder` 注入进来即可全量切换，其余不变。
//   壳里**刻意不出现**任何容器 key：容器 key 归 T02/T05，夹具抢先占用会让
//   「12/13 容器逐个有内容」的用例变成自我实现。
// ============================================================

import 'dart:async' show unawaited;

import 'package:dice_realm/domain/js_compat.dart' show asList, jsStr;
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/repo_scope.dart';
import 'package:dice_realm/repo/room_notes_store.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:dice_realm/repo/share_store.dart';
import 'package:dice_realm/ui/room/room_controller.dart';
import 'package:dice_realm/ui/room/room_image_picker.dart';
import 'package:dice_realm/ui/room/room_scope.dart';
import 'package:dice_realm/ui/room/room_session_local.dart';
import 'package:dice_realm/ui/room/room_ui_local.dart';
import 'package:dice_realm/ui/room/view/member_view.dart';
import 'package:dice_realm/ui/room/view/room_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart'
    show FakeShareApi, newMemoryRepo, newMemorySettings, newMemoryShareStore;
import 'room_fakes.dart' show InMemoryRoomSaveStore, roomHostOpts;

// ------------------------------------------------------------
// 座位命名规约（用例断言里少几处魔法字符串）
// ------------------------------------------------------------

/// 默认房间号。
const String kFixtureRoomCode = 'p5-ui';

/// 玩家座位：`p1..pN`。
String playerSeat(int i) => 'p$i';

/// 旁观座位：`sp1..spN`。
String spectatorSeat(int i) => 'sp$i';

/// 一个 1×1 假 PNG 的 dataURL（与生产实现同形状，可直接喂 `asset.add`）。
const String kFakePngDataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/wD/6Bb0AAAAAElFTkSuQmCC';

// ------------------------------------------------------------
// 假图片选择器
// ------------------------------------------------------------

/// 假图片选择器：不碰平台通道（fake-async 里平台通道永不返回）。
///
/// [dataUrl] 为 null 表示「用户取消」；[bytes] 用来造「超 2MB 上限」（S9）。
class FakeImagePicker implements ImagePickerPort {
  FakeImagePicker({this.dataUrl, this.bytes = 120});

  String? dataUrl;
  int bytes;

  /// 被调用次数（断言「点了确实去选图了」）。
  int calls = 0;

  /// 最近一次收到的上限参数。
  int lastMaxBytes = 0;

  @override
  Future<String?> pickImage({int maxBytes = 2 * 1024 * 1024}) async {
    calls += 1;
    lastMaxBytes = maxBytes;
    final url = dataUrl;
    if (url == null) return null;
    if (maxBytes > 0 && bytes > maxBytes) return null;
    return url;
  }
}

// ------------------------------------------------------------
// 夹具
// ------------------------------------------------------------

/// 一个房间 + 多份视角的完整夹具。
///
/// widget 用例：
/// ```dart
/// final f = RoomUiFixture();
/// await f.boot();                       // KP + p1 + p2 + sp1
/// useRoomScreen(tester, 360, 640);
/// await tester.pumpWidget(f.playerPage('p1'));
/// ```
///
/// 纯 Dart 用例（无需 await）：
/// ```dart
/// final f = RoomUiFixture()..bootSync();
/// f.host.intent('p1', {'op': 'dice', 'p': {...}});
/// expect(f.stateOf('p2')['dice'], isEmpty);
/// ```
class RoomUiFixture {
  RoomUiFixture();

  /// 权威端（只有 KP 视角能拿到它的只读面）。
  late RoomHost host;

  /// KP 视角会话；它也是共享 hub 的入口（其余视角由 viewFor 派生）。
  late LocalLoopbackSession kpSession;

  /// 玩家视角（seat → session），默认 p1 / p2。
  final Map<String, LocalLoopbackSession> plSessions =
      <String, LocalLoopbackSession>{};

  /// 旁观视角（seat → session），默认 sp1。
  final Map<String, LocalLoopbackSession> spectatorSessions =
      <String, LocalLoopbackSession>{};

  /// 本机笔记仓库（K12：不上传、不进 state、不进存档）。
  final RoomNotesStore notes = RoomNotesStore(MemoryNotesStorage());

  /// 角色卡仓库（内存后端；`pumpApp(tester, repo: f.repo, ...)` 用）。
  late CharacterRepo repo;

  /// 设置仓库（内存后端）：只用于撑起设置作用域，与房间逻辑无关。
  late SettingsRepo settings;

  /// 分享服务（假接口、未配置）：撑起分享作用域，保证绝不联网。
  late ShareService share;

  /// 假图片选择器（所有 seat 的控制器共用一份，断言 `calls` 更直观）。
  late FakeImagePicker picker;

  /// 可推进的确定性时钟：`f.nowMs += 500` 即越过 400ms 节流窗口。
  int nowMs = 0;

  /// 逐 seat 的 UI 本地态（折叠 / 奖惩骰 / 缩放）。
  final Map<String, RoomUiLocal> locals = <String, RoomUiLocal>{};

  /// 逐 seat 的控制器（UI 的唯一出入口）。
  final Map<String, RoomController> controllers = <String, RoomController>{};

  /// 玩家 / 旁观座位表（按创建顺序）。
  final List<String> playerSeats = <String>[];
  final List<String> spectatorSeats = <String>[];

  bool _booted = false;

  /// 是否已 boot（在 `late` 字段初始化前访问会被这层挡住）。
  bool get booted => _booted;

  /// 玩家数 / 旁观数。
  int get players => playerSeats.length;
  int get spectators => spectatorSeats.length;

  /// 视角总数（KP + 玩家 + 旁观），默认规模下应为 4。
  int get viewCount => 1 + playerSeats.length + spectatorSeats.length;

  /// 所有非 KP 座位（玩家 + 旁观）。
  List<String> get clientSeats => <String>[
        ...playerSeats,
        ...spectatorSeats,
      ];

  /// 存档后端。`roomHostOpts()` 内部注入的正是内存实现，这里回读同一实例，
  /// 保证「控制器写进去的存档」与「用例读出来的存档」是同一个后端。
  InMemoryRoomSaveStore get saves => host.saveStore! as InMemoryRoomSaveStore;

  /// ★ 所有 UI 发出的 intent / action（断言「点了没反应」的唯一依据，T6）。
  /// 直接暴露 hub 内 SessionSendLog 的 entries —— 同一份引用，不是副本。
  List<Map<String, Object?>> get sent => kpSession.sent.entries;

  // ----------------------------------------------------------
  // 造场景
  // ----------------------------------------------------------

  /// 造场景（异步版：跑角色卡 / 设置 / 分享仓库的首次 load）。
  ///
  /// [inGame] 为 true 时用**真实 action** 开团（`room.start` + `scene.mode`），
  /// 不手改权威态 —— 手改会让「开团事件流」在测试里从未被跑到。
  Future<void> boot({
    int players = 2,
    int spectators = 1,
    bool inGame = false,
    String mode = RoomMode.exploration,
    int seed = 1,
    bool withSheets = true,
    String code = kFixtureRoomCode,
  }) async {
    repo = await newMemoryRepo();
    settings = await newMemorySettings();
    share = ShareService(
      client: FakeShareApi(base: ''),
      store: await newMemoryShareStore(),
    );
    _buildRoom(
      players: players,
      spectators: spectators,
      seed: seed,
      code: code,
    );
    await _primeClients();
    if (withSheets) await shareSheets();
    if (inGame) await startGame(mode: mode);
  }

  /// 造场景（同步版，供纯 Dart 用例用）。
  ///
  /// 四条会话链路都是同步装配（意图结算与投递全同步），所以同步版足够支撑
  /// 「暗骰只进私有账」「stateOf 跨视角」这类数据断言。**不要**用它 pump 真 App。
  void bootSync({
    int players = 2,
    int spectators = 1,
    bool inGame = false,
    String mode = RoomMode.exploration,
    int seed = 1,
    String code = kFixtureRoomCode,
  }) {
    // 内存仓库不 load 也可用（表为空，isLoaded == false），且零 I/O。
    repo = CharacterRepo(storage: MemoryStorage());
    settings = SettingsRepo(storage: MemorySettingsStorage());
    share = ShareService(
      client: FakeShareApi(base: ''),
      store: ShareStore(storage: MemoryShareStorage()),
    );
    _buildRoom(
      players: players,
      spectators: spectators,
      seed: seed,
      code: code,
    );
    unawaited(_primeClients()); // 体内无 await，实际同步完成
    if (inGame) startGameSync(mode: mode);
  }

  /// 装配 host + 客户端 + 名册 + 逐 seat 控制器（同步核心）。
  void _buildRoom({
    required int players,
    required int spectators,
    required int seed,
    required String code,
  }) {
    plSessions.clear();
    spectatorSessions.clear();
    locals.clear();
    controllers.clear();
    playerSeats.clear();
    spectatorSeats.clear();
    nowMs = 0;
    _booted = false;

    picker = FakeImagePicker(dataUrl: kFakePngDataUrl);
    host = RoomHost(roomHostOpts(
      seed: seed,
      meta: <String, Object?>{
        'code': code,
        'name': '$code 测试团',
        'kpName': '老 K',
      },
    ));
    kpSession = LocalLoopbackSession(
      host: host,
      seat: kHostSeat,
      role: RoomRole.kp,
    );

    final specs = <List<String>>[
      for (var i = 1; i <= players; i++)
        <String>[playerSeat(i), RoomRole.player, '玩家$i'],
      for (var i = 1; i <= spectators; i++)
        <String>[spectatorSeat(i), RoomRole.spectator, '旁观$i'],
    ];

    // ① 先注册客户端（收件箱），② 再走真实的 attachPeer 产出 hello/members。
    final plans = <SendPlan>[];
    for (final spec in specs) {
      final seat = spec[0];
      final role = spec[1];
      if (role == RoomRole.player) {
        playerSeats.add(seat);
      } else {
        spectatorSeats.add(seat);
      }
      kpSession.attach(seat, RoomClient(seat: seat, role: role));
      plans.addAll(host
          .attachPeer(<String, Object?>{
            'seat': seat,
            'role': role,
            'nickname': spec[2],
            'at': 1,
          })
          .out);
    }
    kpSession.pumpPlans(plans);

    // ③ 派生每个玩家 / 旁观视角（共享同一个 hub）。
    for (final spec in specs) {
      final view = kpSession.viewFor(spec[0], spec[1]);
      if (spec[1] == RoomRole.player) {
        plSessions[spec[0]] = view;
      } else {
        spectatorSessions[spec[0]] = view;
      }
    }

    // ④ 逐 seat 本地态 + 控制器。
    for (final seat in <String>[kHostSeat, ...playerSeats, ...spectatorSeats]) {
      final local = RoomUiLocal();
      // fake-async 里真实 Timer 永不返回：禁用自动消失，用例自己推进。
      local.scheduleDismiss = (_, _) => null;
      locals[seat] = local;
      controllers[seat] = RoomController(
        session: sessionOf(seat),
        local: local,
        notes: notes,
        imagePicker: picker,
        saveStore: saves,
        nowMs: () => nowMs,
      );
    }
    _booted = true;
  }

  /// 给每个客户端发首份全量同步（水位拉齐，玩家才有 members 基线）。
  Future<void> _primeClients() async {
    for (final seat in clientSeats) {
      await kpSession.pullSync(seat);
    }
  }

  // ----------------------------------------------------------
  // 常见场景快捷法
  // ----------------------------------------------------------

  /// 每个玩家分享一张卡（`sheet.attrs` 逐座位不同 → 跨视角裁剪可被断言）。
  ///
  /// 必须**用玩家自己的视角**发：权威端 shareSheet 只放行 player 角色，
  /// KP 视角发会被 sysTo 拒绝，不产生任何裁剪事件。
  Future<void> shareSheets() async {
    var i = 0;
    for (final seat in playerSeats) {
      i += 1;
      await plSessions[seat]!.sendIntent(RoomIntent.char, <String, Object?>{
        'id': 'c_$seat',
        'name': '${_nickOf(seat)}的调查员',
        'sheet': <String, Object?>{
          'name': '${_nickOf(seat)}的调查员',
          'attrs': <String, Object?>{
            'str': 50,
            'dex': 55 + i, // 逐座位不同：跨视角对比有区分度
            'pow': 60,
          },
          'status': <String, Object?>{
            'currentHP': 12,
            'maxHP': 12,
            'currentMP': 10,
            'maxMP': 10,
            'currentSAN': 55 + i,
            'maxSAN': 99,
          },
          'skills': <Object?>[
            <String, Object?>{'name': '侦查', 'value': 70},
          ],
        },
      });
    }
  }

  /// 开团（真实 action：`room.start` + `scene.mode`）。
  Future<void> startGame({String mode = RoomMode.exploration}) async {
    await kpSession.hostAction('room.start');
    await kpSession.hostAction('scene.mode', <String, Object?>{'mode': mode});
  }

  /// 同步版开团（纯 Dart 用例用；两条 action 的投递全程同步）。
  void startGameSync({String mode = RoomMode.exploration}) {
    unawaited(kpSession.hostAction('room.start'));
    unawaited(kpSession.hostAction('scene.mode', <String, Object?>{'mode': mode}));
  }

  // ----------------------------------------------------------
  // 取用
  // ----------------------------------------------------------

  /// 按 seat 取会话（含 KP）。
  LocalLoopbackSession sessionOf(String seat) {
    if (seat == kHostSeat) return kpSession;
    final view = plSessions[seat] ?? spectatorSessions[seat];
    if (view == null) throw StateError('未知座位 $seat：请先调用 boot()');
    return view;
  }

  /// 按 seat 取 UI 本地态。
  RoomUiLocal localOf(String seat) {
    final local = locals[seat];
    if (local == null) throw StateError('未知座位 $seat：请先调用 boot()');
    return local;
  }

  /// 按 seat 取控制器（UI 的唯一出入口）。
  RoomController controllerOf(String seat) {
    final ctl = controllers[seat];
    if (ctl == null) throw StateError('未知座位 $seat：请先调用 boot()');
    return ctl;
  }

  /// 该座位的角色（kp / player / spectator），供建页面用。
  String roleOf(String seat) {
    if (seat == kHostSeat) return RoomRole.kp;
    if (spectatorSeats.contains(seat)) return RoomRole.spectator;
    return RoomRole.player;
  }

  /// ★ 每个 seat 的**裁剪后**状态（玩家拿到的就是客户端真收到的那份）。
  /// T8：跨视角用例必须用它建页面，不要用 [hostState]。
  Map<String, Object?> stateOf(String seat) => kpSession.stateFor(seat);

  /// KP 权威态（只用于 T6 的「权威侧」断言，不用于建玩家页）。
  Map<String, Object?> hostState() => host.state;

  /// 便捷断言：最近一次发出的载荷（可按 op / action 过滤，从后往前找）。
  Map<String, Object?>? lastSent({String? op, String? action}) {
    for (var i = sent.length - 1; i >= 0; i--) {
      final e = sent[i];
      if (action != null && !(e['kind'] == 'action' && e['op'] == action)) {
        continue;
      }
      if (op != null && e['op'] != op) continue;
      return e;
    }
    return null;
  }

  /// 清空发送记录（用例内需要「只看这一步」时用）。
  void clearSent() => kpSession.sent.clear();

  // ----------------------------------------------------------
  // 页面（可 pumpWidget 的完整 widget 树）
  // ----------------------------------------------------------

  /// 页面注入点：T02 落地游戏页后把真页面塞进这里，全 P5 用例自动切换。
  ///
  /// 约定：入参 `(seat, role)`，返回**不含** MaterialApp / RoomScope 的子树，
  /// 由 [shell] 统一套壳（保证作用域与尺寸一致）。
  Widget Function(String seat, String role)? pageBuilder;

  /// KP 视角游戏页。
  Widget kpPage() => pageOf(kHostSeat);

  /// 玩家视角游戏页（骨架与旁观相同，靠 role 区分能力）。
  Widget playerPage(String seat) => pageOf(seat);

  /// 旁观者视角游戏页（复用玩家骨架）。
  Widget spectatorPage(String seat) => pageOf(seat);

  /// 房间页（招募中）：T05 落地后走 [pageBuilder]。
  Widget lobbyPage() => shell(kHostSeat, RoomRole.kp, stage: RoomFixtureStage.lobby);

  /// 房间入口页（创建 / 加入 / 续玩）：T05 落地后走 [pageBuilder]。
  Widget entryPage() => shell(kHostSeat, RoomRole.kp, stage: RoomFixtureStage.entry);

  /// 任意座位的游戏页（T02/T03 做「同骨架跨角色」对比时用）。
  Widget pageOf(String seat) => shell(seat, roleOf(seat));

  /// 把页面套上「MaterialApp + 三件套作用域 + 房间作用域」。
  ///
  /// 为什么不用 `app_harness.wrapWithScopes()`：它是 `Future<Widget>`，而
  /// `pumpWidget` 要同步拿 Widget。这里用 boot 期间预先建好的内存后端同步拼出
  /// **完全相同的层级**（repo → settings → share → room → child），效果等价，
  /// 于是页面可以直接 `await tester.pumpWidget(f.playerPage('p1'))`。
  Widget shell(String seat, String role, {RoomFixtureStage stage = RoomFixtureStage.game}) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: RepoScope(
        repo: repo,
        child: SettingsScope(
          repo: settings,
          child: ShareScope(
            service: share,
            child: RoomScope(
              session: sessionOf(seat),
              local: localOf(seat),
              controller: controllerOf(seat),
              child: pageBuilder != null && stage == RoomFixtureStage.game
                  ? pageBuilder!(seat, role)
                  : _FixtureShell(seat: seat, role: role, stage: stage),
            ),
          ),
        ),
      ),
    );
  }

  /// 只套房间作用域（供已有宿主自己带 MaterialApp 的用例，§6.1 第一种写法）。
  Widget scoped(String seat, {Widget? child}) => RoomScope(
        session: sessionOf(seat),
        local: localOf(seat),
        controller: controllerOf(seat),
        child: child ?? pageOf(seat),
      );

  String _nickOf(String seat) {
    final me = memberOfSeat(kpSession.stateFor(seat), seat);
    final nick = me == null ? '' : jsStr(me['nickname']);
    return nick.isEmpty ? seat : nick;
  }
}

/// 页面阶段（只影响测试侧壳的画法，不影响真页面）。
enum RoomFixtureStage { game, lobby, entry }

/// 只读摘要壳：顶栏身份行 + 成员数值 + 信息流计数。
///
/// ★ 只用 S1.2 的纯视图函数取数：跨视角裁剪已经发生在数据层，这里**不做**
///   二次隐藏 —— 若在 UI 里再藏一次，T8 的跨视角用例就会假绿。
/// ★ 全部装在列表里（可滚动）：360×640 竖屏与 780×320 横屏都不会溢出。
class _FixtureShell extends StatelessWidget {
  const _FixtureShell({
    required this.seat,
    required this.role,
    required this.stage,
  });

  final String seat;
  final String role;
  final RoomFixtureStage stage;

  @override
  Widget build(BuildContext context) {
    // 订阅会话变化（InheritedNotifier 语义）。
    final scope = RoomScope.of(context);
    final session = scope.session;
    final local = scope.local;
    final state = session.state;
    final meta = metaOf(state);
    final members = membersOf(state);
    final status = jsStr(meta['status']);

    final rows = <Widget>[
      _line('stage', switch (stage) {
        RoomFixtureStage.game => '游戏页',
        RoomFixtureStage.lobby => '房间页',
        RoomFixtureStage.entry => '入口页',
      }),
      _line('who', whoLine(state, seat, role)),
      _line('seat', '$seat / $role'),
      _line('status', '${roomStatusText(status)} · ${session.link.name}'),
      _line('seq', 'lastSeq=${session.lastSeq} · code=${session.code}'),
      if (session.lastNotice != null)
        _line('notice', '提示：${session.lastNotice}'),
      _line(
        'counts',
        '成员 ${members.length}'
        ' · 聊天 ${asList(state['chats']).length}'
        ' · 记录 ${asList(state['logs']).length}'
        ' · 骰子 ${asList(state['dice']).length}',
      ),
    ];

    for (final m in members) {
      final mSeat = jsStr(m['seat']);
      final self = mSeat == seat;
      final stats = memberStats(m);
      final nick = jsStr(m['nickname']);
      rows.add(_line(
        'member/$mSeat',
        '${nick.isEmpty ? mSeat : nick}'
        '（${roleText(jsStr(m['role']))}）'
        ' ${hpText(stats, full: self)} ${sanText(stats, full: self)}'
        ' 身体：${bodyViewOf(m)}',
      ));
    }

    // 奖惩骰草稿（纯本地态）：证明 local 也被传下来了。
    rows.add(_line('local', '奖励骰 ${local.bonus} · 惩罚骰 ${local.penalty}'));

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const ValueKey<String>('fixtureShell'),
          padding: const EdgeInsets.all(8),
          children: rows,
        ),
      ),
    );
  }

  Widget _line(String tag, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          text,
          key: ValueKey<String>('fixture/$tag'),
          softWrap: true,
        ),
      );
}

// ------------------------------------------------------------
// 屏幕尺寸夹具
// ------------------------------------------------------------

/// 设定测试屏幕逻辑尺寸（房间页专用）。
///
/// ★ 不要用 `useTallScreen`（1200×2600）：它会把「单列 / 网格」两个档位全测成
///   网格档，房间页必须按真实档位测。
/// ★ 物理尺寸严格取 `w×3 / h×3`、像素密度 3.0（避免 1/3 像素的取整偏差）。
/// [landscape] 只是给布局档位断言的语义提示，**不参与换算**：横屏请直接传
/// `(780, 320)`（宽 > 高）。
void useRoomScreen(
  WidgetTester tester,
  double w,
  double h, {
  bool landscape = false,
}) {
  // ignore: avoid_print
  assert(w > 0 && h > 0, 'useRoomScreen: 尺寸必须为正（收到 $w × $h）');
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
