// ============================================================
// qa_244_event_mask_test.dart — 2.44.0 QA **独立验收**用例（不复用工程师的
// p21_event_banner_mask_test.dart，从用户视角逐条证明 P21 需求成立）
//
// 用户原话（拆成 A1~A4）：
//   A1 五类全覆盖：combatStart / combatEnd / death / ripped / madness
//      底图正确、**且图不被裁切**（原缺陷：卡片钉在屏高 32%，cover 裁上下）。
//   A2 全屏 + 半透明：遮罩铺满整屏；带透明度，房间背景仍可见。
//   A3 默认 4 秒 + 点击淡出：4 秒自消；点任意位置 → **有可见淡出** 再消失。
//   A4 连续多人疯狂：按入队顺序依次弹；**一条都不许丢**；连发时单条缩短；
//      点一下只关**当前**这条，后面的继续。
//
// 与工程师用例的**差异**（独立性声明，避免「自证」）：
//   1. 五类底图不是直接喂 art 字符串，而是**真的跑 CriticalEventTracker 的
//      state diff 判据机**，断言它产出的 kind / art；再把这批 art 真的推上
//      屏幕，断言 `ArtImage.path` 与磁盘资源都真的存在。
//   2. 半透明断言读**渲染树里的 ColoredBox.color.a**，不是读 `RoomEventBanner.mask`
//      这个静态常量（读常量证明不了它被贴到屏幕上）。
//   3. 「4 秒」用**边界值**验（3.99s 在 / 4.01s 起淡出），不是「跑满 4 秒看看」。
//   4. 连发用**绝对时刻表**（t = 2.00 / 2.25 / 4.00 / 4.45 … 12.85）逐点断言，
//      证明每条恰好 2.2s、最后一条恰好 4s，且 5 个 id 按序全部出现过。
//   5. 「点击吃两次」用**房间按钮计数**验，三步逐条断言。
//
// ★ 断言口径不放宽：不用 findsWidgets、不 skip、不留恒真。找不到就是缺陷。
// ============================================================

import 'dart:async' show Timer;
import 'dart:io' show File;

import 'package:dice_realm/domain/madness_state.dart'
    show kMentalIndefinite, kMentalPermanent, kMentalTemporary;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/art.dart' show Art, ArtImage;
import 'package:dice_realm/ui/room/critical_event_tracker.dart'
    show
        CriticalEvent,
        CriticalEventKind,
        CriticalEventTracker,
        EventBannerArt;
import 'package:dice_realm/ui/room/room_event_banner_watcher.dart'
    show RoomEventBannerWatcher;
import 'package:dice_realm/ui/room/room_ui_local.dart' show RoomUiLocal;
import 'package:dice_realm/ui/room/widgets/room_event_banner.dart'
    show RoomEventBanner, RoomEventBannerKeys, kBannerDefaultTtl;
import 'package:dice_realm/ui/room/widgets/room_notice_overlay.dart'
    show RoomNoticeKeys, RoomNoticeOverlay;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 宿主
// ------------------------------------------------------------

/// 把 `RoomNoticeOverlay`（可选 `RoomEventBannerWatcher`）挂在 RoomScope 下，
/// 下面可以垫一层 `under`（用来验「点击穿透 / 被吃掉」）。
Widget _host(
  RoomUiFixture f, {
  Widget? under,
  bool withWatcher = false,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext ctx, Widget? _) {
      final MediaQueryData mq = MediaQuery.of(ctx);
      return MediaQuery(
        data: textScale == 1.0
            ? mq
            : mq.copyWith(textScaler: TextScaler.linear(textScale)),
        child: f.scoped(
          kHostSeat,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (under != null) under,
              if (withWatcher) const RoomEventBannerWatcher(),
              const Positioned.fill(child: RoomNoticeOverlay()),
            ],
          ),
        ),
      );
    },
    home: const Scaffold(body: SizedBox.expand()),
  );
}

/// 一屏能点的按钮（模拟「结束房间」这类不可逆按钮）。
Widget _roomButton(void Function() onTap) => Center(
      child: TextButton(
        onPressed: onTap,
        child: const Text('结束房间'),
      ),
    );

/// 把 AnimatedSwitcher 的淡入 / 交叉淡化 / 淡出彻底跑完（共 ~290ms）。
///
/// 四步都是 Ticker 的真实语义：切换那一帧只排上 ticker；第一 tick 的
/// elapsed 恒为 0；跑满时长；结束回调里的 setState 再要一帧生效。
/// 290ms 远小于连发短时长 2.2s，不会误触发下一条的自消。
Future<void> _fadeDone(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump();
}

/// 当前这条遮罩的「淡出是否真的在进行」：祖先链上存在一个不透明度处于
/// 中间值（0.01~0.99）的 `FadeTransition`。
bool _midFade(WidgetTester tester, Key rootKey) {
  final Finder root = find.byKey(rootKey);
  if (root.evaluate().isEmpty) return false;
  for (final FadeTransition t in tester.widgetList<FadeTransition>(
    find.ancestor(of: root, matching: find.byType(FadeTransition)),
  )) {
    final double v = t.opacity.value;
    if (v > 0.01 && v < 0.99) return true;
  }
  return false;
}

/// 虚拟时钟：按**绝对时刻**推进 testWidgets 的 FakeAsync，避免累加漂移。
class _At {
  _At(this.tester);

  final WidgetTester tester;
  int now = 0;

  Future<void> call(int ms) async {
    final int delta = ms - now;
    if (delta < 0) {
      throw StateError('虚拟时钟只能前进：$now → $ms');
    }
    await tester.pump(Duration(milliseconds: delta));
    now = ms;
  }
}

/// 只计数取消次数的假 Timer（不参与真实计时）。
class _FakeTimer implements Timer {
  _FakeTimer(this._onCancel);

  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}

// ------------------------------------------------------------
// 喂给 CriticalEventTracker 的 state 构造器
// （字段读法严格按 `_cropMember` 的**公开面**：sheet.status.body /
//   sheet.mental / sheet.madness / sheet.name）
// ------------------------------------------------------------

Map<String, Object?> _member(
  String seat, {
  String name = '沈砚清',
  String body = '正常',
  List<String> mental = const <String>[],
  List<Map<String, Object?>> madness = const <Map<String, Object?>>[],
}) {
  return <String, Object?>{
    'seat': seat,
    'nickname': name,
    'sheet': <String, Object?>{
      'name': name,
      'status': <String, Object?>{'body': body},
      'mental': mental,
      'madness': madness,
    },
  };
}

Map<String, Object?> _state(
  List<Map<String, Object?>> members, {
  Map<String, Object?>? combat,
}) {
  return <String, Object?>{
    'members': members,
    'combat': combat ?? <String, Object?>{},
  };
}

/// 跑一次 tracker 的真实 diff：先登记基线，再吃第二帧。
List<CriticalEvent> _diff(
  CriticalEventTracker tracker,
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  expect(
    tracker.sync(before, syncEpoch: 1, mySeat: 'p1'),
    isEmpty,
    reason: '前提：首帧只登记基线，不弹历史',
  );
  return tracker.sync(after, syncEpoch: 1, mySeat: 'p1');
}

void main() {
  // ============================================================
  // A1 —— 五类全覆盖：kind → 底图路径 → 真的上屏
  // ============================================================
  group('A1 五类底图映射', () {
    test('五类 kind 的底图一一对应，且互不重复', () {
      final Map<String, String> expected = <String, String>{
        CriticalEventKind.combatStart: Art.e18BannerCombat,
        CriticalEventKind.combatEnd: Art.e18BannerCombatEnd,
        CriticalEventKind.death: Art.e18BannerDeath,
        CriticalEventKind.ripped: Art.e18BannerRipped,
        CriticalEventKind.madness: Art.e18BannerMadness,
      };
      for (final MapEntry<String, String> e in expected.entries) {
        expect(EventBannerArt.of(e.key), e.value,
            reason: '★ kind=${e.key} 必须拿到自己的那张底图'
                '（纯 Dart 镜像 EventBannerArt 与单一真源 Art 不许跑偏）');
      }
      expect(
        expected.values.toSet().length,
        expected.length,
        reason: '★ 五类各自一张，不许两类共用同一张图',
      );
    });

    test('五张底图资源在磁盘上真实存在（缺图 = 用户看到一块纯色）', () {
      for (final String art in <String>[
        Art.e18BannerCombat,
        Art.e18BannerCombatEnd,
        Art.e18BannerDeath,
        Art.e18BannerMadness,
        Art.e18BannerRipped,
      ]) {
        expect(File(art).existsSync(), isTrue,
            reason: '★ 底图资源缺失：$art');
        expect(File(art).lengthSync(), greaterThan(1024),
            reason: '★ 底图疑似空文件：$art');
        expect(art.endsWith('_16x9.webp'), isTrue,
            reason: '★ 底图命名必须标出 16:9 比例：$art');
      }
    });

    test('★ 真实 diff · 死亡：跃迁才产 1 条，底图是 death', () {
      final CriticalEventTracker t = CriticalEventTracker();
      final List<CriticalEvent> evts = _diff(
        t,
        _state(<Map<String, Object?>>[_member('p1')]),
        _state(<Map<String, Object?>>[_member('p1', body: '死亡')]),
      );
      expect(evts.length, 1, reason: '★ 一条跃迁只弹一条');
      expect(evts.single.kind, CriticalEventKind.death);
      expect(evts.single.art, Art.e18BannerDeath);
      expect(evts.single.title, contains('沈砚清'),
          reason: '标题必须带角色名，否则玩家不知道死的是谁');
      expect(evts.single.hasSubtitle, isTrue,
          reason: '死亡必须有副行（撕卡说明）');

      // 已死亡的角色再写一次状态 → 不许重复弹。
      expect(
        t.sync(_state(<Map<String, Object?>>[_member('p1', body: '死亡')]),
            syncEpoch: 1, mySeat: 'p1'),
        isEmpty,
        reason: '★ 重复写状态不许重复弹（永久疯狂一次写 3 条 log 的老毛病）',
      );
    });

    test('★ 真实 diff · 永久疯狂（撕卡）：底图是 ripped', () {
      final CriticalEventTracker t = CriticalEventTracker();
      final List<CriticalEvent> evts = _diff(
        t,
        _state(<Map<String, Object?>>[_member('p1')]),
        _state(<Map<String, Object?>>[
          _member('p1', mental: <String>[kMentalPermanent]),
        ]),
      );
      final CriticalEvent ripped = evts
          .firstWhere((CriticalEvent e) => e.kind == CriticalEventKind.ripped);
      expect(ripped.art, Art.e18BannerRipped,
          reason: '★ 永久疯狂必须用「撕纸」那张（用户当初报的就是这张显示不全）');
      expect(ripped.subtitle, isNotEmpty, reason: '撕卡必须有副行说明');
      expect(ripped.key, 'ripped:p1', reason: '去重键按座位隔离');
    });

    test('★ 真实 diff · 疯狂（临时 / 不定 / 新疯狂症）：底图都是 madness', () {
      // 临时疯狂
      final CriticalEventTracker t1 = CriticalEventTracker();
      final List<CriticalEvent> temp = _diff(
        t1,
        _state(<Map<String, Object?>>[_member('p1')]),
        _state(<Map<String, Object?>>[
          _member('p1', mental: <String>[kMentalTemporary], madness: <Map<String, Object?>>[
            <String, Object?>{'rounds': 3},
          ]),
        ]),
      );
      final CriticalEvent e = temp.firstWhere(
          (CriticalEvent x) => x.key == 'madness:temp:p1');
      expect(e.kind, CriticalEventKind.madness);
      expect(e.art, Art.e18BannerMadness);

      // 不定疯狂
      final CriticalEventTracker t2 = CriticalEventTracker();
      final List<CriticalEvent> indef = _diff(
        t2,
        _state(<Map<String, Object?>>[_member('p1')]),
        _state(<Map<String, Object?>>[
          _member('p1', mental: <String>[kMentalIndefinite]),
        ]),
      );
      final CriticalEvent i = indef.firstWhere(
          (CriticalEvent x) => x.key == 'madness:indef:p1');
      expect(i.kind, CriticalEventKind.madness);
      expect(i.art, Art.e18BannerMadness);

      // 新疯狂症（madnessCount 增加）
      final CriticalEventTracker t3 = CriticalEventTracker();
      final List<CriticalEvent> sym = _diff(
        t3,
        _state(<Map<String, Object?>>[_member('p1')]),
        _state(<Map<String, Object?>>[
          _member('p1', madness: <Map<String, Object?>>[
            <String, Object?>{'rounds': 0, 'permanent': true},
          ]),
        ]),
      );
      final CriticalEvent s = sym.firstWhere(
          (CriticalEvent x) => x.key == 'madness:symptom:p1:1');
      expect(s.kind, CriticalEventKind.madness);
      expect(s.art, Art.e18BannerMadness,
          reason: '「获得 1 项新的疯狂症状」也用疯狂那张');
    });

    test('★ 真实 diff · 进入战斗 / 战斗结束：各 1 条，底图不同', () {
      final CriticalEventTracker t = CriticalEventTracker();
      final List<Map<String, Object?>> members = <Map<String, Object?>>[
        _member('p1'),
      ];

      // 基线：不在战斗中。
      final List<CriticalEvent> start = _diff(
        t,
        _state(members),
        _state(members, combat: <String, Object?>{
          'startedAt': '1000',
          'order': <Object?>[
            <String, Object?>{'name': '沈砚清'},
            <String, Object?>{'name': '深潜者'},
          ],
        }),
      );
      expect(start.length, 1, reason: '★ 群体事件只弹 1 条，不是每人一条');
      expect(start.single.kind, CriticalEventKind.combatStart);
      expect(start.single.art, Art.e18BannerCombat);
      expect(start.single.subtitle, contains('沈砚清'),
          reason: '开战副行要带参战名单，否则只是一句空话');

      // 结束。
      final List<CriticalEvent> end =
          t.sync(_state(members), syncEpoch: 1, mySeat: 'p1');
      expect(end.length, 1);
      expect(end.single.kind, CriticalEventKind.combatEnd);
      expect(end.single.art, Art.e18BannerCombatEnd,
          reason: '★ 战斗结束必须是「尾声」那张，不能复用开战图');
    });

    testWidgets('★ 端到端：真实 watcher + 真实 combat.start / combat.end → 遮罩底图',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, withWatcher: true));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);

      // ① 真实 action 开战 → 应弹「进入战斗」。
      await f.kpSession.hostAction('combat.start', <String, Object?>{
        'actorIds': <Object?>['qa_m1'],
        'actors': <Object?>[
          <String, Object?>{
            'id': 'qa_m1',
            'name': '深潜者',
            'kind': 'monster',
            'dex': 50,
            'hp': 12,
            'hpMax': 12,
            'actionsPerRound': 1,
          },
        ],
        'pcSeats': <Object?>['p1'],
      });
      await tester.pump();

      expect(local.banners, isNotEmpty,
          reason: '★ 真实开战必须弹一条（watcher 挂载 / 接线真的通了）');
      expect(local.activeBanner!.art, Art.e18BannerCombat,
          reason: '★ 端到端底图：watcher 内联 artOf 必须指向开战图');
      final ArtImage img1 = tester.widget<ArtImage>(
        find.byKey(RoomEventBannerKeys.art(local.activeBanner!.id)),
      );
      expect(img1.path, Art.e18BannerCombat,
          reason: '★ 屏幕上那一层真的拿到了开战图（不是只有数据对）');

      // ② 真实 action 结束战斗 → 应弹「战斗结束」。
      await f.kpSession.hostAction('combat.end');
      await tester.pump();

      final List<String> arts =
          local.banners.map((dynamic b) => b.art as String).toList();
      expect(arts, contains(Art.e18BannerCombatEnd),
          reason: '★ 真实 combat.end 必须产出「战斗结束」那张底图：$arts');
    });

    testWidgets('★ 五类底图逐一上屏：art(id) 拿到对应路径 + contain + 精确 16:9',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      final Map<String, String> arts = <String, String>{
        CriticalEventKind.combatStart: Art.e18BannerCombat,
        CriticalEventKind.combatEnd: Art.e18BannerCombatEnd,
        CriticalEventKind.death: Art.e18BannerDeath,
        CriticalEventKind.madness: Art.e18BannerMadness,
        CriticalEventKind.ripped: Art.e18BannerRipped,
      };

      for (final MapEntry<String, String> e in arts.entries) {
        local.pushBanner(
          title: 'QA ${e.key}',
          subtitle: '副行',
          art: e.value,
        );
        await tester.pump();

        final int id = local.activeBanner!.id;
        final Finder artFinder = find.byKey(RoomEventBannerKeys.art(id));
        expect(artFinder, findsOneWidget, reason: '主图层必须上屏：${e.key}');

        final ArtImage img = tester.widget<ArtImage>(artFinder);
        expect(img.path, e.value,
            reason: '★ kind=${e.key} 的底图路径必须是它自己那张');
        expect(img.fit, BoxFit.contain,
            reason: '★ 主图层只许 contain（cover 就是「图显示不全」的根因）');

        local.clearBanners();
        await tester.pump();
        await _fadeDone(tester);
      }
    });
  });

  // ============================================================
  // A2 —— 全屏 + 半透明（房间背景仍可见）
  // ============================================================
  group('A2 全屏半透明遮罩', () {
    testWidgets('★ 遮罩铺满整屏，且底色 alpha 严格 < 1（房间仍可见）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      f.localOf(kHostSeat).pushBanner(
        title: '战斗结束',
        subtitle: '回到探索模式',
        art: Art.e18BannerCombatEnd,
      );
      await tester.pump();

      final Finder maskFinder = find.byKey(RoomEventBannerKeys.mask(1));
      expect(maskFinder, findsOneWidget);
      expect(tester.getSize(maskFinder), const Size(400, 860),
          reason: '★ 遮罩必须铺满整屏（改前是一张 520 宽的居中卡片）');

      final ColoredBox box = tester.widget<ColoredBox>(maskFinder);
      expect(box.color.a, lessThan(1.0),
          reason: '★ 读渲染树里的真实颜色：不透明就是一块黑板，'
              '用户明确要求「玩家还能看到游戏房间背景」');
      expect(box.color.a, greaterThan(0.40),
          reason: '也不能淡到压不住亮色舞台，否则金色标题读不清');

      // 氛围层同样铺满整屏（它负责把 16:9 图铺不满的边带补上）。
      expect(
        tester.getSize(find.byKey(RoomEventBannerKeys.ambientArt(1))),
        const Size(400, 860),
        reason: '★ 氛围层也要铺满，否则竖屏上下会露出突兀的纯色带',
      );
    });

    testWidgets('★ 主图层也不挡房间：ArtImage 外面那层 Opacity < 1',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      f.localOf(kHostSeat).pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );
      await tester.pump();

      final Iterable<Opacity> artOpacity = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byKey(RoomEventBannerKeys.art(1)),
          matching: find.byType(Opacity),
        ),
      );
      expect(artOpacity, isNotEmpty,
          reason: '主图层必须带透明度（ArtImage.opacity）');
      expect(artOpacity.every((Opacity o) => o.opacity < 1.0), isTrue,
          reason: '★ 主图必须留一点透光，与「整块是半透明遮罩」的观感一致');

      // 三层叠加后的房间可见度必须 > 0（否则等于全遮）。
      final ColoredBox mask =
          tester.widget<ColoredBox>(find.byKey(RoomEventBannerKeys.mask(1)));
      final double art = artOpacity.last.opacity;
      final double roomVisible = (1 - mask.color.a) * (1 - art);
      expect(roomVisible, greaterThan(0.0),
          reason: '★ 叠乘后的房间可见度必须严格 > 0（实测 $roomVisible）');
    });

    testWidgets('★ 横屏 860×400：遮罩同样铺满整屏', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 860, 400);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      f.localOf(kHostSeat).pushBanner(
        title: '⚔ 战斗开始',
        subtitle: '行动顺序：沈砚清 → 深潜者',
        art: Art.e18BannerCombat,
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(RoomEventBannerKeys.mask(1))),
        const Size(860, 400),
        reason: '★ 横屏也必须铺满整屏',
      );
    });
  });

  // ============================================================
  // A3 —— 默认 4 秒 / 点击任意位置淡出
  // ============================================================
  group('A3 默认 4 秒 + 点击淡出', () {
    testWidgets('★ 默认 4 秒：3.99s 仍在，越过 4s 才起淡出', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      // harness 把 scheduleDismiss 换成 no-op；这里换回真 Timer 才能验自消。
      f.localOf(kHostSeat).scheduleDismiss =
          (Duration d, void Function() fn) => Timer(d, fn);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      final _At at = _At(tester);

      local.pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );

      await at(3990);
      expect(local.banners.length, 1,
          reason: '★ 3.99 秒时还没到点，不许提前消失');
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget);

      await at(4020);
      expect(local.banners, isEmpty,
          reason: '★ 越过 4 秒必须自消（用户要求默认显示 4 秒）');
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget,
          reason: '★ 此刻应处于淡出动画中，遮罩还不该从树上消失');

      await _fadeDone(tester);
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsNothing);
      expect(find.byType(RoomEventBanner), findsNothing);
    });

    testWidgets('★ 点屏幕任意位置（左上角 12,12）→ 有可见淡出再消失',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      local.pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );
      await tester.pump();
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget);

      // 先把淡入跑完（真实使用就是「看到遮罩之后才去点」）。
      await _fadeDone(tester);

      // 角落：远离文字块 → 证明「任意位置」而不是只有文字上能点。
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();

      expect(local.banners, isEmpty, reason: '★ 点一下当前条就被消费掉');
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget,
          reason: '★ 淡出动画期间遮罩不能立刻从树上消失（那是「瞬消」）');

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget,
          reason: '前提：此刻确实处于淡出过程中');
      expect(_midFade(tester, RoomEventBannerKeys.root(1)), isTrue,
          reason: '★ 半程必须有不透明度中间值 = 真的在淡出，不是「啪」一下没了');

      await _fadeDone(tester);
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsNothing,
          reason: '★ 淡出跑完后必须彻底消失');
    });

    testWidgets('★ 点击节奏：第一下关掉、淡出中再点被吃掉、结束后恢复穿透',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      int roomTaps = 0;
      await tester.pumpWidget(
        _host(f, under: _roomButton(() => roomTaps++)),
      );
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      local.pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );
      await tester.pump();
      await _fadeDone(tester);

      // ① 第一下：关掉当前条。
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(local.banners, isEmpty, reason: '第一下必须关掉当前条');

      // ② 淡出中立刻再点：必须被吃掉（落点若是「结束房间」就是不可逆事故）。
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('结束房间'), warnIfMissed: false);
      await tester.pump();
      expect(roomTaps, 0,
          reason: '★ 淡出 220ms 内不许穿透：用户本能是连点两下');

      // ③ 淡出结束之后：点击必须重新落到房间按钮上。
      await _fadeDone(tester);
      expect(find.byType(RoomEventBanner), findsNothing);
      await tester.tap(find.text('结束房间'), warnIfMissed: false);
      await tester.pump();
      expect(roomTaps, 1,
          reason: '★ 队列空 + 动画结束后必须恢复全穿透，否则页面按钮全废');
      expect(
        find.descendant(
          of: find.byType(RoomNoticeOverlay),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason: '★ 没有遮罩时连手势层都不该存在（比 IgnorePointer 更彻底）',
      );
    });

    testWidgets('★ 没有遮罩时是零占位（不许在屏幕上留一块空的拦截区）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      expect(find.byType(RoomEventBanner), findsNothing);
      expect(
        tester.getSize(find.byKey(RoomNoticeKeys.emptyBannerSlot)),
        Size.zero,
        reason: '★ 零占位：常驻的遮罩层不许有体积',
      );
    });
  });

  // ============================================================
  // A4 —— 连续多人疯狂：不丢 / 依次 / 缩短 / 只关当前条
  // ============================================================
  group('A4 连发（KP 的 SAN Check 场景）', () {
    test('★ 连发 5 条的排定时长：4×2.2s + 末条 4s（结构证明）', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      final List<Duration> armed = <Duration>[];
      local.scheduleDismiss = (Duration d, void Function() _) {
        armed.add(d);
        return _FakeTimer(() {});
      };

      for (int i = 1; i <= 5; i++) {
        local.pushBanner(
          title: '玩家$i 陷入临时疯狂',
          subtitle: '症状将持续 3 轮',
          art: Art.e18BannerMadness,
        );
      }
      expect(local.banners.length, 5,
          reason: '★ 一条都不许丢（改前 kBannerMax=2，后 3 条被静默丢弃）');
      expect(armed.first, kBannerDefaultTtl,
          reason: '只推第一条时它就是队尾 → 先按 4 秒排定');
      expect(armed.last, const Duration(milliseconds: 2200),
          reason: '★ 有后续条目时，队首必须重排成连发短时长');

      for (int i = 1; i <= 4; i++) {
        local.dismissActiveBanner(id: i);
      }
      expect(local.activeBanner?.id, 5);
      expect(armed, <Duration>[
        const Duration(seconds: 4),
        const Duration(milliseconds: 2200),
        const Duration(milliseconds: 2200),
        const Duration(milliseconds: 2200),
        const Duration(milliseconds: 2200),
        const Duration(seconds: 4),
      ], reason: '★ 每条 2.2s 依次消费，最后一条恢复默认 4 秒');
    });

    test('★ 连发 10 条一条不丢，按 id 顺序依次提升', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      local.scheduleDismiss = (_, _) => _FakeTimer(() {});

      for (int i = 1; i <= 10; i++) {
        local.pushBanner(
          title: '玩家$i 陷入临时疯狂',
          subtitle: '',
          art: Art.e18BannerMadness,
        );
      }
      expect(local.banners.length, 10, reason: '★ 队列不限长，一条都不丢');
      expect(local.pendingBannerCount, 9);

      final List<int> seen = <int>[];
      for (int i = 1; i <= 10; i++) {
        expect(local.activeBanner?.id, i, reason: '★ 必须严格按入队顺序上屏');
        seen.add(local.activeBanner!.id);
        local.dismissActiveBanner(id: i);
      }
      expect(seen, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          reason: '★ 10 个 id 一个不许跳号');
      expect(local.banners, isEmpty);
      expect(local.activeBanner, isNull);
    });

    test('★ dismissActiveBanner(id:) 守卫：不匹配的 id 不许误关队首', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      local.scheduleDismiss = (_, _) => _FakeTimer(() {});

      for (int i = 1; i <= 3; i++) {
        local.pushBanner(title: 'P$i', subtitle: '', art: Art.e18BannerDeath);
      }

      local.dismissActiveBanner(id: 3);
      expect(local.activeBanner?.id, 1,
          reason: '★ 淡出期间旧遮罩带的旧 id 不许把刚提升上来的条目吃掉');
      expect(local.banners.length, 3);

      local.dismissActiveBanner(id: 1);
      expect(local.activeBanner?.id, 2);
      expect(local.banners.length, 2);
    });

    testWidgets('★ 点一下只关当前条，后面的一条不少继续弹',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      local.pushBanner(title: '玩家A 疯狂', subtitle: '', art: Art.e18BannerMadness);
      local.pushBanner(title: '玩家B 疯狂', subtitle: '', art: Art.e18BannerMadness);
      await tester.pump();
      await _fadeDone(tester);
      expect(find.byKey(RoomEventBannerKeys.title(1)), findsOneWidget);

      await tester.tapAt(const Offset(12, 12));
      await tester.pump();

      expect(local.activeBanner?.id, 2, reason: '★ 只关当前条，下一条顶上');
      expect(local.banners.length, 1, reason: '★ 后面的条目一条不少');
      await _fadeDone(tester);
      expect(find.byKey(RoomEventBannerKeys.title(2)), findsOneWidget,
          reason: '★ 第 2 条必须真的上屏');
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsNothing);
    });

    testWidgets('★ 连发 5 条：绝对时刻表逐点验证「依次 2.2s + 末条 4s + 不丢」',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      final RoomUiLocal local = f.localOf(kHostSeat);
      local.scheduleDismiss =
          (Duration d, void Function() fn) => Timer(d, fn);

      await tester.pumpWidget(_host(f));
      await tester.pump();

      for (int i = 1; i <= 5; i++) {
        local.pushBanner(
          title: '玩家$i 陷入临时疯狂',
          subtitle: '症状将持续 3 轮',
          art: Art.e18BannerMadness,
        );
      }

      final _At at = _At(tester);
      await tester.pump(); // 建树（零时长，不推进假时钟）
      final List<int> seen = <int>[];
      void note() {
        final int id = local.activeBanner!.id;
        if (seen.isEmpty || seen.last != id) {
          seen.add(id);
          // 此刻该条必须真的在屏幕上。
          expect(find.byKey(RoomEventBannerKeys.title(id)), findsOneWidget,
              reason: '★ 第 $id 条必须真的上屏（t=${at.now}ms）');
        }
      }

      // 同屏只显示 1 条。
      expect(find.byType(RoomEventBanner), findsOneWidget);

      await at(2000);
      note();
      expect(local.activeBanner?.id, 1, reason: '2.2 秒没到，不该提前翻页');

      await at(2250);
      note();
      expect(local.activeBanner?.id, 2, reason: '★ 越过 2.2 秒 → 第 2 条顶上');

      await at(4000);
      note();
      expect(local.activeBanner?.id, 2,
          reason: '★ 第 2 条的窗口内（2.2–4.4s）不许被提前带走');

      await at(4450);
      note();
      expect(local.activeBanner?.id, 3);

      await at(6000);
      note();
      expect(local.activeBanner?.id, 3, reason: '3 号窗口 4.4–6.6s');

      await at(6650);
      note();
      expect(local.activeBanner?.id, 4);

      await at(8000);
      note();
      expect(local.activeBanner?.id, 4, reason: '4 号窗口 6.6–8.8s');

      await at(8850);
      note();
      expect(local.activeBanner?.id, 5);

      await at(11000);
      expect(local.activeBanner?.id, 5,
          reason: '★ 末条是队尾 → 用满默认 4 秒（8.8–12.8s），不许被连发时长带走');

      await at(12850);
      expect(local.banners, isEmpty,
          reason: '★ 末条 4 秒到了必须自消');
      await _fadeDone(tester);
      expect(find.byType(RoomEventBanner), findsNothing);

      expect(seen, <int>[1, 2, 3, 4, 5],
          reason: '★ 5 条按入队顺序依次出现，一条都不许丢、不许跳号');
    });
  });

  // ============================================================
  // 排版稳健性（遮罩内字号固定，但极端环境仍不许溢出）
  // ============================================================
  group('排版', () {
    testWidgets('★ textScaler 1.3 / 1.5 / 2.0 下遮罩不溢出',
        (WidgetTester tester) async {
      for (final double scale in <double>[1.3, 1.5, 2.0]) {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot();
        useRoomScreen(tester, 400, 860);

        await tester.pumpWidget(_host(f, textScale: scale));
        await tester.pump();

        f.localOf(kHostSeat).pushBanner(
          title: '沈砚清 获得 1 项新的疯狂症状',
          subtitle: '症状将持续 3 轮',
          art: Art.e18BannerMadness,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull,
            reason: '★ textScaler=$scale 下遮罩不得 RenderFlex overflow / 抛异常');
        expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget);
        expect(find.byKey(RoomEventBannerKeys.title(1)), findsOneWidget);
        expect(find.byKey(RoomEventBannerKeys.subtitle(1)), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('★ 极端窄屏 320×568 + textScaler 2.0：不溢出、图仍 16:9',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 320, 568);

      await tester.pumpWidget(_host(f, textScale: 2.0));
      await tester.pump();

      f.localOf(kHostSeat).pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull,
          reason: '★ 320dp 窄屏 + 2.0 倍字号不许溢出');

      final Size art = tester.getSize(find.byKey(RoomEventBannerKeys.art(1)));
      expect(art.width / art.height, closeTo(16 / 9, 0.01),
          reason: '★ 窄屏下仍必须是完整 16:9（实际 ${art.width}×${art.height}）');
      expect(art.width, lessThanOrEqualTo(320),
          reason: '主图层不许超出屏幕宽度');
      expect(art.height, lessThanOrEqualTo(568),
          reason: '主图层不许超出屏幕高度');
    });
  });
}
