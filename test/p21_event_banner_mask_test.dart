// ============================================================
// p21_event_banner_mask_test.dart — 关键事件「全屏信息遮罩」（P21 需求 1-4）
//
// 这个文件守的是用户报的 4 个问题，一条用例对一个：
//   Q1 图片显示不全（被裁成窄带）
//      → 5 类底图逐一量「主图层框」的宽高比必须 == 16/9（框与图比例相等 ⇒
//        `BoxFit.contain` 等于不裁不变形）。改前框被压到屏高 32%，比例
//        随屏幕漂移，同一张图必然被 cover 裁掉上下 —— 这条用例在改前的
//        实现上必红，是**结构性**证伪，不是靠肉眼。
//   Q2 改为全屏遮罩（带透明度、底图作全屏背景层）
//      → 遮罩尺寸 == 屏幕尺寸；房间仍可见（遮罩 alpha < 255）。
//   Q3 默认 4 秒 / 点击任意位置即时**淡出** / 无横幅时绝不拦点击
//      → 点角落（远离文字）也能关；关掉后还要在树上存在半程（= 真淡出，
//        不是瞬消）；无横幅时下层按钮照常可点。
//      ★ 主理人裁定：淡出这 220ms **继续吃掉点击**（用户本能是连点两下，
//        第二下若穿透可能落在「结束房间 / 结团 / 战斗」这类不可逆按钮上）；
//        同时必须证明「有 → 有」交叉淡化期间新条没被旧层挡住 hit-test。
//   Q4 多人连发（KP 的 SAN Check）不能丢信息、按序一条一条弹
//      → 连推 5 条，队列长度必须是 5（改前上限 2，后 3 条被静默丢弃）；
//        同一时刻只渲染 1 条；点掉当前条后下一条顶上。
// ============================================================

import 'dart:async' show Timer;

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/art.dart' show Art, ArtImage;
import 'package:dice_realm/ui/room/room_ui_local.dart'
    show RoomBannerItem, RoomUiLocal;
import 'package:dice_realm/ui/room/widgets/room_event_banner.dart'
    show RoomEventBanner, RoomEventBannerKeys, kBannerDefaultTtl;
import 'package:dice_realm/ui/room/widgets/room_notice_overlay.dart'
    show RoomNoticeKeys, RoomNoticeOverlay;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 组件级宿主：RoomScope + 一个可点击按钮（用于验「遮罩不吃点击」）。
///
/// [textScale] 用来把 textScaler 抬到 1.3 / 1.5 / 2.0（遮罩内固定字号
/// 必须在这些档位下不溢出）。
Widget _host(
  RoomUiFixture f, {
  required Widget child,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext ctx, Widget? c) {
      final MediaQueryData mq = MediaQuery.of(ctx);
      return MediaQuery(
        data: textScale == 1.0
            ? mq
            : mq.copyWith(textScaler: TextScaler.linear(textScale)),
        child: f.scoped(kHostSeat, child: c ?? const SizedBox.shrink()),
      );
    },
    home: Scaffold(body: child),
  );
}

/// 把「淡入 / 淡出 / 交叉淡化」跑完，让树落到最终形态。
///
/// 四步都是必要的（这是 `Ticker` 的真实语义，不是凑帧数）：
///   ① `pump()` —— 若切换发生在这一帧（例如定时器刚触发了队列前进），
///      切换动画的 ticker 在这一帧只会被**排上**；
///   ② `pump(60ms)` —— ticker 的第一 tick 的 `elapsed` 恒为 0（只用来对齐
///      起始时间戳），必须再走一帧才开始真正计时；
///   ③ `pump(fadeDuration)` —— 把剩余时长跑完（累计 60+220 > 220）；
///   ④ `pump()` —— `AnimatedSwitcher` 在动画**结束的状态回调**里 setState
///      把旧条目摘掉，那次 setState 要再一帧才生效。
///
/// 累计只推进 280ms，远小于连发短时长 2.2s，所以不会误触发下一条的自消。
Future<void> _settleFade(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(RoomEventBanner.fadeDuration);
  await tester.pump();
}

/// 5 张底图（`Art` 是单一真源）。
const List<String> _kArts = <String>[
  Art.e18BannerCombat,
  Art.e18BannerCombatEnd,
  Art.e18BannerDeath,
  Art.e18BannerMadness,
  Art.e18BannerRipped,
];

void main() {
  // ------------------------------------------------------------
  // 数据层：队列调度（纯逻辑，没有 Widget）
  // ------------------------------------------------------------
  group('横幅队列（RoomUiLocal 纯逻辑）', () {
    test('★ 连推 5 条一条都不丢（改前上限 2 条，后 3 条被静默丢弃）', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      local.scheduleDismiss = (_, _) => null;

      for (int i = 1; i <= 5; i++) {
        local.pushBanner(
          title: '玩家$i 陷入临时疯狂',
          subtitle: '症状将持续 3 轮',
          art: Art.e18BannerMadness,
        );
      }

      expect(local.banners.length, 5,
          reason: '★ KP 的 SAN Check 会让多人同时疯狂：一条都不能丢');
      expect(local.activeBanner?.id, 1, reason: '队首即当前条，按入队顺序上屏');
      expect(local.pendingBannerCount, 4);
    });

    test('★ 点一下只关当前条，后面的按序提升', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      local.scheduleDismiss = (_, _) => null;

      for (int i = 1; i <= 3; i++) {
        local.pushBanner(
          title: '玩家$i 陷入临时疯狂',
          subtitle: '',
          art: Art.e18BannerMadness,
        );
      }

      local.dismissActiveBanner(id: 1);
      expect(local.activeBanner?.id, 2);
      expect(local.banners.length, 2);

      local.dismissActiveBanner(id: 2);
      expect(local.activeBanner?.id, 3);
      expect(local.banners.length, 1);

      local.dismissActiveBanner(id: 3);
      expect(local.banners, isEmpty, reason: '队尾关掉后队列必须真正清空');
      expect(local.activeBanner, isNull);
    });

    test('★ dismissActiveBanner(id:) 只在 id 命中时才关（淡出期间旧点击不误伤）',
        () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      local.scheduleDismiss = (_, _) => null;

      local.pushBanner(title: 'A', subtitle: '', art: Art.e18BannerDeath);
      local.pushBanner(title: 'B', subtitle: '', art: Art.e18BannerDeath);

      // 队首是 1；拿旧 id 2 来关 → 必须空转（不能把 2 提前消费掉）。
      local.dismissActiveBanner(id: 2);
      expect(local.activeBanner?.id, 1);
      expect(local.banners.length, 2);
    });

    test('空标题直接丢弃（不占队列）', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      local.scheduleDismiss = (_, _) => null;

      local.pushBanner(title: '   ', subtitle: '', art: Art.e18BannerDeath);
      expect(local.banners, isEmpty);
    });

    test('clearBanners 清空队列并取消定时器', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      int armed = 0;
      int cancelled = 0;
      local.scheduleDismiss = (Duration _, void Function() _) {
        armed++;
        return _CountingTimer(() => cancelled++);
      };

      local.pushBanner(title: 'A', subtitle: '', art: Art.e18BannerDeath);
      local.pushBanner(title: 'B', subtitle: '', art: Art.e18BannerDeath);
      expect(armed, greaterThanOrEqualTo(1), reason: '队首必须排定自消定时器');

      local.clearBanners();
      expect(local.banners, isEmpty);
      expect(cancelled, armed, reason: '清队列必须把排定的定时器一并取消');
    });

    test('连发时队首改用短时长，队尾用默认 4 秒', () {
      final RoomUiLocal local = RoomUiLocal();
      addTearDown(local.dispose);
      final List<Duration> armedTtls = <Duration>[];
      local.scheduleDismiss = (Duration d, void Function() _) {
        armedTtls.add(d);
        return _CountingTimer(() {});
      };

      local.pushBanner(title: 'A', subtitle: '', art: Art.e18BannerDeath);
      expect(armedTtls.last, kBannerDefaultTtl,
          reason: '只推一条时它就是队尾 → 用满 4 秒');

      local.pushBanner(title: 'B', subtitle: '', art: Art.e18BannerDeath);
      expect(armedTtls.last, RoomUiLocal.kBannerBurstTtl,
          reason: '★ 后来者入队后，队首必须重排成连发短时长');
      expect(armedTtls.last, lessThan(kBannerDefaultTtl));

      local.dismissActiveBanner(id: 1);
      expect(armedTtls.last, kBannerDefaultTtl,
          reason: '队列只剩最后一条时恢复默认 4 秒');
    });
  });

  // ------------------------------------------------------------
  // 组件级：遮罩怎么长、怎么关
  // ------------------------------------------------------------
  group('全屏信息遮罩（组件级）', () {
    testWidgets('★ Q1：5 类底图在全屏下都是精确 16:9（不再被裁成窄带）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      for (final String art in _kArts) {
        local.pushBanner(title: '测试标题', subtitle: '测试副行', art: art);
        await tester.pump();

        final RoomBannerItem item = local.banners.first;
        final Finder artFinder = find.byKey(RoomEventBannerKeys.art(item.id));
        expect(artFinder, findsOneWidget, reason: '主图层必须上屏：$art');

        // ① 框与图的比例相等 ⇒ contain ≡ 不裁不变形（Q1 的结构性证伪）。
        final Size size = tester.getSize(artFinder);
        expect(size.width / size.height, closeTo(16 / 9, 0.01),
            reason: '★ 主图层框必须是 16:9（改前被压成 4:1 的窄带，'
                'cover 必然裁掉上下）：实际 ${size.width}×${size.height}');

        // ② 主图层坚持 contain：即便比例被外部挤掉也不允许 cover 硬裁。
        final ArtImage image = tester.widget<ArtImage>(artFinder);
        expect(image.fit, BoxFit.contain,
            reason: '★ 主图层只能用 contain（cover 会裁掉构图边缘）');

        local.clearBanners();
        await tester.pump();
        await _settleFade(tester);
      }
    });

    testWidgets('★ Q1 续：横屏矮屏（860×400）下主图层仍是 16:9',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 860, 400);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      f.localOf(kHostSeat).pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );
      await tester.pump();

      final Size size = tester.getSize(
        find.byKey(RoomEventBannerKeys.art(1)),
      );
      expect(size.width / size.height, closeTo(16 / 9, 0.01),
          reason: '★ 横屏 400dp 高时改前只能给图 128dp —— 现在必须是完整 16:9');
      expect(size.height, closeTo(400, 0.5),
          reason: '横屏下 16:9 应当吃满屏高（宽度 711 < 860，两侧留给氛围层）');
    });

    testWidgets('★ Q2：遮罩铺满全屏且带透明度（房间仍可见）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      f.localOf(kHostSeat).pushBanner(
        title: '战斗结束',
        subtitle: '回到探索模式',
        art: Art.e18BannerCombatEnd,
      );
      await tester.pump();

      final Size mask =
          tester.getSize(find.byKey(RoomEventBannerKeys.mask(1)));
      expect(mask, const Size(400, 860),
          reason: '★ 遮罩必须铺满全屏（改前是一张 520 宽的居中卡片）');

      final RoomEventBanner banner = tester.widget<RoomEventBanner>(
        find.byType(RoomEventBanner),
      );
      expect(banner.banner.art, Art.e18BannerCombatEnd);
      expect(RoomEventBanner.mask.a, lessThan(1.0),
          reason: '★ 遮罩必须半透明（用户：玩家还能看到游戏房间背景）');
      expect(RoomEventBanner.mask.a, greaterThan(0.3),
          reason: '也不能淡到压不住画面 —— 否则白色面板上标题读不清');
    });

    testWidgets('★ Q3：点屏幕任意位置（角落）→ 当前条淡出关闭',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      local.pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );
      await tester.pump();
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget);

      // 先把淡入跑完（真实使用就是「看到遮罩之后才去点」）——否则控制器
      // 还停在 value≈0，reverse() 会立刻到 dismissed，测出来的就不是淡出。
      await _settleFade(tester);

      // 左上角：远离文字块，证明是「任意位置」而不是只有文字上能点。
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();

      expect(local.banners, isEmpty, reason: '★ 点一下当前条就被消费掉');

      // ---- 真淡出（不是瞬消）：半程时它还在树上，且透明度处于中间值 ----
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget,
          reason: '★ 淡出动画期间遮罩不能立刻从树上消失');
      // 先走一帧让淡出 ticker 拿到起始时间（第一 tick 的 elapsed 恒为 0）。
      await tester.pump();
      await tester.pump(
        Duration(milliseconds: RoomEventBanner.fadeDuration.inMilliseconds ~/ 2),
      );
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget);
      final Iterable<FadeTransition> fades =
          tester.widgetList<FadeTransition>(find.ancestor(
        of: find.byKey(RoomEventBannerKeys.root(1)),
        matching: find.byType(FadeTransition),
      ));
      expect(
        fades.any((FadeTransition t) =>
            t.opacity.value > 0.01 && t.opacity.value < 0.99),
        isTrue,
        reason: '★ 半程必须有不透明度中间值 = 真的在淡出（瞬消会直接没有）',
      );

      // 走完淡出时长后彻底消失。
      await _settleFade(tester);
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsNothing);
    });

    testWidgets('★ Q3 续：无遮罩时绝不拦截点击（下层按钮照常可点）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      int taps = 0;
      await tester.pumpWidget(
        _host(
          f,
          child: Stack(
            children: <Widget>[
              Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('下面的按钮'),
                ),
              ),
              const RoomNoticeOverlay(),
            ],
          ),
        ),
      );
      await tester.pump();

      // 没有横幅：遮罩层里连手势层都不该存在。
      expect(
        find.descendant(
          of: find.byType(RoomNoticeOverlay),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason: '★ 没有遮罩就不该有手势层（比 IgnorePointer 更彻底）',
      );

      await tester.tap(find.text('下面的按钮'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 1, reason: '★ 无横幅时浮层必须全穿透');
    });

    testWidgets('★ Q3 续：点掉之后淡出 220ms 内**继续吃掉点击**（不许穿透到房间按钮）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      int roomTaps = 0;
      await tester.pumpWidget(
        _host(
          f,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Center(
                  child: TextButton(
                    onPressed: () => roomTaps++,
                    child: const Text('结束房间'),
                  ),
                ),
              ),
              const RoomNoticeOverlay(),
            ],
          ),
        ),
      );
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      local.pushBanner(
        title: '沈砚清 陷入永久疯狂',
        subtitle: '撕卡 —— SAN 已归零',
        art: Art.e18BannerRipped,
      );
      await tester.pump();
      await _settleFade(tester); // 淡入跑完，遮罩完全不透明

      // ① 点一下 → 当前条被消费、淡出开始
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(local.banners, isEmpty);

      // ② 淡出进行中（~100ms）：遮罩**还在树上**
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget,
          reason: '前提：此刻确实处于 220ms 的淡出过程中');

      // ③ 连点的第二下必须被吃掉 —— 落在「结束房间」上就是不可逆事故
      await tester.tap(find.text('结束房间'), warnIfMissed: false);
      await tester.pump();
      expect(roomTaps, 0,
          reason: '★ 淡出 220ms 内不许穿透：用户本能是连点两下，'
              '第二下落点可能是「结束房间」这类不可逆按钮');

      // ④ 动画彻底结束 + 队列已空 → 必须恢复全穿透（这一条不许被上的改动带坏）
      await _settleFade(tester);
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsNothing);
      await tester.tap(find.text('结束房间'), warnIfMissed: false);
      await tester.pump();
      expect(roomTaps, 1,
          reason: '★ 队列空 + 动画结束之后，点击必须重新落到房间按钮上');
    });

    testWidgets('★ Q3 续：交叉淡化期间点屏幕 → 关掉的是**新条**（旧层不许挡住）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      local.pushBanner(
        title: '玩家A 陷入临时疯狂',
        subtitle: '',
        art: Art.e18BannerMadness,
      );
      local.pushBanner(
        title: '玩家B 陷入临时疯狂',
        subtitle: '',
        art: Art.e18BannerMadness,
      );
      await tester.pump();
      await _settleFade(tester);

      // ① 点掉第 1 条 → 第 2 条提升，「有 → 有」交叉淡化开始
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(local.activeBanner?.id, 2);

      // ② 交叉淡化进行中：旧条（id=1）还在树上叠在下层
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget,
          reason: '前提：此刻确实处于「有 → 有」的交叉淡化过程中');
      expect(find.byKey(RoomEventBannerKeys.root(2)), findsOneWidget);

      // ③ 此刻再点：必须关掉**新条**（id=2）。
      //    若旧层抢了 hit-test，回调带的会是旧 id=1 →
      //    `dismissActiveBanner(id: 1)` 因队首已是 2 而空转 → 下面必红。
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(local.banners, isEmpty,
          reason: '★ 交叉淡化期间旧层不许挡住新条：这一下必须关掉第 2 条');
      expect(local.activeBanner, isNull);
      await _settleFade(tester);
      expect(find.byType(RoomEventBanner), findsNothing);
    });

    testWidgets('★ Q4：连发 5 条 → 只显示 1 条，点掉一条顶一条，一条不丢',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      final RoomUiLocal local = f.localOf(kHostSeat);
      for (int i = 1; i <= 5; i++) {
        local.pushBanner(
          title: '玩家$i 陷入临时疯狂',
          subtitle: '症状将持续 3 轮',
          art: Art.e18BannerMadness,
        );
      }
      await tester.pump();

      expect(local.banners.length, 5, reason: '★ 一条都不能丢（改前上限 2）');
      // 同一时刻只显示 1 条。
      expect(find.byType(RoomEventBanner), findsOneWidget);
      expect(find.byKey(RoomEventBannerKeys.title(1)), findsOneWidget);
      expect(find.byKey(RoomEventBannerKeys.title(2)), findsNothing);

      // 逐条点掉，每次都应「只掉当前条 + 下一条顶上」。
      for (int id = 1; id <= 5; id++) {
        await tester.tapAt(const Offset(12, 12));
        await tester.pump();
        expect(local.activeBanner?.id, id == 5 ? null : id + 1,
            reason: '点掉第 $id 条后必须按序提升');
        await _settleFade(tester);
      }
      expect(local.banners, isEmpty);
      expect(find.byType(RoomEventBanner), findsNothing);
    });

    testWidgets('★ Q3 续：默认 4 秒 / 连发 2.2 秒（到点自动下一条）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      // harness 的 boot() 把 scheduleDismiss 换成了 `(_, _) => null`，
      // 这里显式换回真 Timer 才能验「到点自消」。
      final RoomUiLocal local = f.localOf(kHostSeat);
      local.scheduleDismiss =
          (Duration d, void Function() fn) => Timer(d, fn);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      local.pushBanner(
        title: '玩家A 陷入临时疯狂',
        subtitle: '',
        art: Art.e18BannerMadness,
      );
      local.pushBanner(
        title: '玩家B 陷入临时疯狂',
        subtitle: '',
        art: Art.e18BannerMadness,
      );
      await tester.pump();

      // 连发短时长：2.2 秒。1.5 秒时第 1 条还在。
      await tester.pump(const Duration(milliseconds: 1500));
      expect(local.activeBanner?.id, 1, reason: '2.2 秒没到，不该提前翻页');

      // 越过 2.2 秒 → 第 1 条到点，第 2 条顶上。
      await tester.pump(const Duration(milliseconds: 800));
      expect(local.activeBanner?.id, 2, reason: '★ 队列里还有后续时用 2.2 秒');
      await _settleFade(tester);
      expect(find.byKey(RoomEventBannerKeys.title(2)), findsOneWidget);

      // 第 2 条是队尾 → 用满默认 4 秒：再等 3 秒它仍应在。
      await tester.pump(const Duration(seconds: 3));
      expect(local.banners.length, 1, reason: '★ 队尾用默认 4 秒，不该被连发时长带走');
      expect(find.byKey(RoomEventBannerKeys.title(2)), findsOneWidget);

      // 再越过 4 秒 → 自动消失。
      await tester.pump(const Duration(milliseconds: 1200));
      await _settleFade(tester);
      expect(local.banners, isEmpty, reason: '4 秒到了必须自动消失');
      expect(find.byType(RoomEventBanner), findsNothing);
    });

    testWidgets('★ textScaler 1.3 / 1.5 / 2.0 下遮罩不溢出',
        (WidgetTester tester) async {
      for (final double scale in <double>[1.3, 1.5, 2.0]) {
        final RoomUiFixture f = RoomUiFixture();
        await f.boot();
        useRoomScreen(tester, 400, 860);

        await tester.pumpWidget(
          _host(f, child: const RoomNoticeOverlay(), textScale: scale),
        );
        await tester.pump();

        f.localOf(kHostSeat).pushBanner(
          title: '沈砚清 获得 1 项新的疯狂症状',
          subtitle: '症状将持续 3 轮',
          art: Art.e18BannerMadness,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull,
            reason: 'textScaler=$scale 下遮罩不得 RenderFlex overflow / 抛异常');
        expect(find.byKey(RoomEventBannerKeys.root(1)), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('没有提示 / 播报 / 横幅时仍然是零占位', (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot();
      useRoomScreen(tester, 400, 860);

      await tester.pumpWidget(_host(f, child: const RoomNoticeOverlay()));
      await tester.pump();

      expect(find.byKey(RoomNoticeKeys.root), findsNothing);
      expect(find.byKey(RoomNoticeKeys.text), findsNothing);
      expect(find.byType(RoomEventBanner), findsNothing);
      // 遮罩层常驻但**只有一颗零尺寸的占位盒**（常驻是为了让最后一条的
      // 淡出动画能跑完；没有横幅时它不带任何 RenderObject 体积）。
      expect(find.byKey(RoomNoticeKeys.bannerLayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(RoomNoticeKeys.bannerLayer),
          matching: find.byKey(RoomNoticeKeys.emptyBannerSlot),
        ),
        findsOneWidget,
        reason: '没有横幅时遮罩层里只有那颗零尺寸占位盒',
      );
      expect(
        tester.getSize(find.byKey(RoomNoticeKeys.emptyBannerSlot)),
        Size.zero,
        reason: '★ 零占位：不许在屏幕上留一块空的拦截区域',
      );
    });
  });
}

/// 只用来计数取消次数的假 Timer（不参与真实计时）。
class _CountingTimer implements Timer {
  _CountingTimer(this._onCancel);

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
