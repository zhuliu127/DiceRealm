// ============================================================
// test/p10_t1_ui_paper_banner_test.dart — P10 第 1 期 A1 / A2 / A3 / B1 / B2
//
// 每条都用「能证伪」的方式守，不看截图：
//   A1 一键出卡候选卡：背景换成纯色羊皮纸（**不再有底纹图** → 左右不可能有竖线）
//   A2 首页两个标题栏：框与图同比例（6:1），平板宽度下也不裁上下边框
//   A3 选择规则系统页「规则系统」标题栏：同 A2（同一个 SectionBanner 组件）
//   B1 KP 审卡：基本资料 / 背景 / 经历 / 装备与资产 / 教育进步 全部在，且能滚动
//   B2 房间头像缩略：本机没有那张图时**退回首字圆点**（跨设备边界如实）
//
// 铁律：全内存后端、零真实 I/O；头像的「根目录」用 `avatarStore.rootOverride`
// 指到临时目录（只是个路径，不读写文件）。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart' show asMap, asList;
import 'package:dice_realm/domain/room_types.dart' show RoomIntent, kHostSeat;
import 'package:dice_realm/repo/avatar_store.dart' show avatarStore;
import 'package:dice_realm/theme.dart' show Palette;
import 'package:dice_realm/ui/art.dart' show ArtImage;
import 'package:dice_realm/ui/create/rule_pick_page.dart'
    show RulePickPage, RulePickTarget;
import 'package:dice_realm/ui/parchment.dart' show ParchmentSurface;
import 'package:dice_realm/ui/random_create_page.dart' show RandomCreatePage;
import 'package:dice_realm/ui/room/sheets/sheet_char_view.dart'
    show CharViewKeys, showCharViewSheet;
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart'
    show GpKpPlayers, GpKpPlayersKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart'
    show GpPlMates, GpPlMatesKeys;
import 'package:dice_realm/ui/widgets.dart' show SectionBanner;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/room_ui_harness.dart';

/// 每个用例前后复位全局色板（Palette 是全局门面，会跨界污染）。
void _resetPalette() => Palette.useBrightness(Brightness.dark);

/// 卡片里所有 `Decoration` 上的 `DecorationImage`（A1 用来证「没有底纹图」）。
List<DecorationImage> _decorationImagesIn(WidgetTester tester, Finder root) {
  final out = <DecorationImage>[];
  for (final Widget w in tester.widgetList(
    find.descendant(of: root, matching: find.byType(DecoratedBox)),
  )) {
    final Decoration d = (w as DecoratedBox).decoration;
    if (d is BoxDecoration && d.image != null) out.add(d.image!);
  }
  for (final Widget w in tester.widgetList(
    find.descendant(of: root, matching: find.byType(Container)),
  )) {
    final Decoration? d = (w as Container).decoration;
    if (d is BoxDecoration && d.image != null) out.add(d.image!);
  }
  return out;
}

/// 把视口改成指定逻辑尺寸（平板/手机两档都用它）。
void _setScreen(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(_resetPalette);
  tearDown(_resetPalette);

  // ---------------------------------------------------------
  // A1 一键出卡：候选卡背景 = 纯色羊皮纸，没有底纹图 → 没有左右竖线
  // ---------------------------------------------------------
  group('A1 一键出卡候选卡的背景', () {
    testWidgets('平板宽度下：背景是 ParchmentSurface，卡内没有任何底纹图',
        (WidgetTester tester) async {
      // 平板逻辑尺寸（内容限宽 760，卡片被拉宽 —— 正是用户看到竖线的场景）
      _setScreen(tester, 1524, 1016);
      await pumpApp(tester, home: const RandomCreatePage(initialRuleId: 'coc7'));
      await tester.pump();

      final Finder card = find.byKey(const Key('random_candidate_0'));
      expect(card, findsOneWidget);

      // ① 新底 = ParchmentSurface（纯色 + 纸纹 + 暗角）
      expect(
        find.descendant(of: card, matching: find.byType(ParchmentSurface)),
        findsOneWidget,
        reason: 'A1：候选卡底纹必须换成纯色羊皮纸',
      );

      // ② 卡内**绝不能**再有 `DecorationImage` —— 那两道竖线就是 3:4 底纹图
      //    自带的双线金框；只要图还在，宽卡上它就会重新出现。
      expect(
        _decorationImagesIn(tester, card),
        isEmpty,
        reason: 'A1：卡片里还有底纹图（3:4 竖图自带双线金框 → 平板左右各两道竖线）',
      );

      // ③ 顶部淡出遮罩仍在（P11 的结构约束：底纹不许在头部行画线）
      expect(
        find.descendant(of: card, matching: find.byType(ShaderMask)),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull, reason: '宽卡上溢出了');
    });

    testWidgets('羊皮纸是纯色打底 + 渐变 + 纤维 + 暗角（不是删成纯白）',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox(width: 320, height: 200, child: ParchmentSurface())),
      ));
      await tester.pump();

      final Finder surface = find.byType(ParchmentSurface);
      // 底色层：一个 ColoredBox（纯色）
      expect(
        find.descendant(of: surface, matching: find.byType(ColoredBox)),
        findsWidgets,
        reason: 'A1：要求「纯色打底」',
      );
      // 受光渐变 + 暗角：两个 DecoratedBox 各自带渐变
      final List<Gradient> gradients = <Gradient>[
        for (final Widget w in tester.widgetList(
          find.descendant(of: surface, matching: find.byType(DecoratedBox)),
        ))
          if ((w as DecoratedBox).decoration is BoxDecoration &&
              ((w.decoration as BoxDecoration).gradient != null))
            (w.decoration as BoxDecoration).gradient!,
      ];
      expect(gradients.length, greaterThanOrEqualTo(2),
          reason: 'A1：要有受光渐变 + 四角暗角（不是纯白一块）');
      // 纸纤维（噪点）在
      expect(
        find.descendant(of: surface, matching: find.byType(CustomPaint)),
        findsWidgets,
        reason: 'A1：要有纸纤维质感',
      );
    });
  });

  // ---------------------------------------------------------
  // A2 首页标题栏：6:1 精确比例，平板/手机都不裁上下边框
  // ---------------------------------------------------------
  group('A2 首页标题栏不裁切', () {
    for (final List<double> screen in <List<double>>[
      <double>[412, 888], // 手机竖屏
      <double>[1524, 1016], // 平板横屏（用户报的那台）
    ]) {
      testWidgets('${screen[0].toInt()}×${screen[1].toInt()}：两个分类头都是 6:1 且 cover',
          (WidgetTester tester) async {
        _setScreen(tester, screen[0], screen[1]);
        await pumpApp(tester);

        final Finder banners = find.byType(SectionBanner);
        expect(banners, findsNWidgets(2), reason: '首页应有两个分类头');

        for (final Element e in banners.evaluate()) {
          // ⚠️ 要量**框**（图的容器），不是 SectionBanner 本身 ——
          //    后者含 `Padding(top:4,bottom:10)`，比例会凭空变小。
          final Finder box = find.descendant(
            of: find.byWidget(e.widget),
            matching: find.byType(ArtImage),
          );
          final Rect r = tester.getRect(box);
          // ① 框必须**就是图的 6:1** —— 这是「一像素都不裁」的唯一前提。
          expect(
            r.width / r.height,
            closeTo(6, 0.02),
            reason: '框被钳扁了（旧实现 maxHeight:96 让 760 宽变成 7.9:1 '
                '→ cover 上下各裁 15px，正好切掉金边）',
          );
          // ② 比例对了才允许 cover（cover + 精确比例 = 零裁切）
          final ArtImage img = tester.widget<ArtImage>(box);
          expect(img.fit, BoxFit.cover, reason: '精确 6:1 时应 cover（含 contain 会有黑边）');
          // ③ 高度也不能是"被钳过的 96"
          if (screen[0] > 800) {
            expect(r.height, greaterThan(96),
                reason: '平板下 760 宽的 6:1 是 126.7px，钳到 96 就会裁上下边框');
          }
        }
        expect(tester.takeException(), isNull);
      });
    }

    test('heightFor / fitFor：触顶时才改 contain（结构上永不裁图）', () {
      // 内容限宽 760 → 126.67px，不触顶
      expect(SectionBanner.heightFor(760), closeTo(760 / 6, 0.001));
      expect(SectionBanner.fitFor(760), BoxFit.cover);
      // 手机竖屏 380 → 63.3px
      expect(SectionBanner.heightFor(380), closeTo(380 / 6, 0.001));
      expect(SectionBanner.fitFor(380), BoxFit.cover);
      // 超宽容器（> 1008）才触顶，并且此时必须 contain（宁可两侧留底色也不裁金边）
      expect(SectionBanner.heightFor(1524), SectionBanner.maxHeight);
      expect(SectionBanner.fitFor(1524), BoxFit.contain);
    });
  });

  // ---------------------------------------------------------
  // A3 选择规则系统页「规则系统」标题栏：同一个组件，同一套断言
  // ---------------------------------------------------------
  testWidgets('A3 规则选择页标题栏也是 6:1（平板宽度）', (WidgetTester tester) async {
    _setScreen(tester, 1524, 1016);
    await pumpApp(tester, home: const RulePickPage(next: RulePickTarget.wizard));
    await tester.pump();

    final Finder banner = find.byType(SectionBanner);
    expect(banner, findsOneWidget);
    final Finder box =
        find.descendant(of: banner, matching: find.byType(ArtImage));
    final Rect r = tester.getRect(box);
    expect(r.width / r.height, closeTo(6, 0.02),
        reason: 'A3：规则系统标题栏同样被钳扁 → 上下边框被裁');
    final ArtImage img = tester.widget<ArtImage>(box);
    expect(img.fit, BoxFit.cover);
  });

  // ---------------------------------------------------------
  // B1 KP 审卡：完整角色卡 + 可滚动
  // ---------------------------------------------------------
  group('B1 招募页 KP 审卡 = 完整角色卡', () {
    /// 把「玩家上报的完整角色卡」推进房间（走真实 INTENT.CHAR）。
    Future<void> pushFullSheet(RoomUiFixture f) async {
      await f.plSessions['p1']!.sendIntent(RoomIntent.char, <String, Object?>{
        'id': 'c_p1',
        'name': '沈墨白',
        'sheet': <String, Object?>{
          'name': '沈墨白',
          'gender': '男',
          'age': 38,
          'era': '1920s',
          'residence': '波士顿',
          'birthplace': '阿卡姆',
          'occupation': '私人侦探',
          'look': '风衣上永远有雨渍',
          'attrs': <String, Object?>{'str': 55, 'dex': 60, 'pow': 65},
          'status': <String, Object?>{
            'currentHP': 11,
            'maxHP': 12,
            'currentMP': 9,
            'maxMP': 10,
            'currentSAN': 51,
            'maxSAN': 99,
            'body': '轻伤',
          },
          'skills': <Object?>[
            <String, Object?>{'name': '侦查', 'value': 70},
          ],
          'background': <String, Object?>{
            'ideology': '真相值得付代价',
            'significantPeople': '妹妹 沈兰',
            'meaningfulPlaces': '阿卡姆图书馆',
            'treasuredPossessions': '父亲的怀表',
            'traits': '嘴硬心软',
            'wounds': '左手旧伤',
            'phobias': '惧水',
          },
          'history': <Object?>[
            <String, Object?>{
              'title': '入行：私人侦探',
              'date': '1919',
              'description': '一桩失踪案把我拉进了这条道',
              'notes': '委托人至今没付尾款',
            },
          ],
          'armors': <Object?>[
            <String, Object?>{'name': '厚呢大衣'},
          ],
          'assets': <String, Object?>{
            'creditRating': 32,
            'cash': 120,
            'spendingLevel': '标准',
            'currency': r'$',
            'assetsDescription': '一间小事务所',
          },
          'eduProgress': <String, Object?>{
            'log': <Object?>[
              <String, Object?>{'gain': 3},
            ],
            'bonus': 3,
          },
        },
      });
    }

    testWidgets('审卡弹层里有 基本资料/背景/经历/装备与资产/教育进步，且能上下滚动',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 2, spectators: 1, withSheets: false);
      await pushFullSheet(f);
      useRoomScreen(tester, 360, 640);

      // KP 视角打开审卡弹层（招募页「详情」走的就是这个函数）
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (BuildContext _, Widget? child) =>
            f.scoped(kHostSeat, child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCharViewSheet<void>(ctx, seat: 'p1'),
                child: const Text('审卡'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('审卡'));
      await tester.pumpAndSettle();

      // ① 五个新分区都在（老分区也有，不回归）
      for (final Key k in <Key>[
        CharViewKeys.basics,
        CharViewKeys.background,
        CharViewKeys.history,
        CharViewKeys.assets,
        CharViewKeys.education,
        CharViewKeys.vitals,
        CharViewKeys.attrs,
        CharViewKeys.skills,
      ]) {
        expect(find.byKey(k, skipOffstage: false), findsOneWidget,
            reason: '$k 缺失：审卡仍是残卡');
      }

      // ② 内容真的来自上报的那张卡（不是空壳分区）
      expect(find.textContaining('沈墨白', skipOffstage: false), findsWidgets);
      expect(find.textContaining('私人侦探', skipOffstage: false), findsWidgets,
          reason: '基本资料里的职业没显示');
      expect(
        find.textContaining('阿卡姆图书馆', skipOffstage: false),
        findsOneWidget,
        reason: '背景「意义非凡之地」没显示',
      );
      expect(
        find.textContaining('父亲的怀表', skipOffstage: false),
        findsOneWidget,
        reason: '背景「宝贵之物」没显示',
      );
      expect(
        find.textContaining('一桩失踪案', skipOffstage: false),
        findsOneWidget,
        reason: '经历正文没显示',
      );
      expect(
        find.textContaining('厚呢大衣', skipOffstage: false),
        findsOneWidget,
        reason: '防具没显示',
      );
      expect(
        find.textContaining('教育进步检定 1 次', skipOffstage: false),
        findsOneWidget,
        reason: '教育进步没显示',
      );

      // ③ 超屏必须能滑动：滚动容器在，且拖一下真的改变了滚动位置。
      final Finder scrollable = find.byType(Scrollable).last;
      final ScrollableState st = tester.state<ScrollableState>(scrollable);
      final double before = st.position.pixels;
      await tester.drag(find.byKey(CharViewKeys.status), const Offset(0, -260));
      await tester.pump();
      final double after = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(after, greaterThan(before),
          reason: 'B1：卡片超屏时手指在卡面上拖动必须能滚（不然看不到下半张卡）');

      expect(tester.takeException(), isNull);
    });

    testWidgets('不读私密字段：privates / 明文 p 不会出现在审卡里',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 1, spectators: 0, withSheets: false);
      await f.plSessions['p1']!.sendIntent(RoomIntent.char, <String, Object?>{
        'id': 'c_p1',
        'name': '只读测试',
        'sheet': <String, Object?>{
          'name': '只读测试',
          'attrs': <String, Object?>{'str': 50},
          'status': <String, Object?>{'currentHP': 10, 'maxHP': 10},
          'privates': <Object?>[
            <String, Object?>{'text': '这是私密栏内容不该被审卡看到'},
          ],
          'p': '这是明文私密不该被审卡看到',
        },
      });
      useRoomScreen(tester, 360, 640);

      // 权威态里就不该有这两个键（白名单入口），审卡自然也无从显示。
      final Map<String, Object?> sheet = asMap(
        asMap(
          asList(f.stateOf(kHostSeat)['members'])
              .map(asMap)
              .firstWhere((Map<String, Object?> m) => m['seat'] == 'p1'),
        )['sheet'],
      );
      expect(sheet.containsKey('privates'), isFalse);
      expect(sheet.containsKey('p'), isFalse);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (BuildContext _, Widget? child) =>
            f.scoped(kHostSeat, child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCharViewSheet<void>(ctx, seat: 'p1'),
                child: const Text('审卡'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('审卡'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不该被审卡看到', skipOffstage: false), findsNothing);
    });
  });

  // ---------------------------------------------------------
  // B2 头像缩略：本机没有图就退回首字圆点（跨设备边界如实）
  // ---------------------------------------------------------
  group('B2 房间头像缩略（本机可见 + 回退）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('dice_avatar_p10');
      // 只给路径，不写文件 —— 模拟「远端玩家的头像文件在他手机上」。
      avatarStore.rootOverride = tmp.path;
    });

    tearDown(() {
      avatarStore.rootOverride = null;
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('成员表里写了头像路径但本机没有这个文件 → 首字圆点，不是空白',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 2, spectators: 0, withSheets: false);
      // 远端玩家上报的头像路径（文件在他自己设备上，本机一定读不到）
      await f.plSessions['p1']!.sendIntent(RoomIntent.char, <String, Object?>{
        'id': 'c_p1',
        'name': '远端调查员',
        'sheet': <String, Object?>{
          'name': '远端调查员',
          'avatar': 'avatars/c_p1.png',
          'attrs': <String, Object?>{'str': 50},
          'status': <String, Object?>{'currentHP': 10, 'maxHP': 10},
        },
      });
      // ★ 直接渲染两个真实块（夹具默认壳是测试侧的摘要，不含这两个块）
      useRoomScreen(tester, 900, 1600);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: f.scoped(kHostSeat, child: const GpKpPlayers()),
      ));
      await tester.pump();

      for (final Key k in <Key>[
        GpKpPlayersKeys.avatar('p1'),
      ]) {
        expect(find.byKey(k, skipOffstage: false), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(k, skipOffstage: false),
            matching: find.byType(Image),
          ),
          findsNothing,
          reason: 'B2：本机没有该头像文件时必须回退（不能留一个空块）',
        );
        // 回退是「首字圆点」：里面要有文字
        expect(
          find.descendant(
            of: find.byKey(k, skipOffstage: false),
            matching: find.byType(Text),
          ),
          findsWidgets,
        );
      }

      // 队友栏（玩家视角）同样不崩、同样有占位
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        // ★ P20 需求 3⑤：`matesOpen` 默认 false ⇒ forceOpen 才能验到队友行。
        home: f.scoped('p2', child: const GpPlMates(forceOpen: true)),
      ));
      await tester.pump();
      expect(find.byKey(GpPlMatesKeys.avatar('p1'), skipOffstage: false),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(GpPlMatesKeys.avatar('p1'), skipOffstage: false),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('KP 玩家信息块里确有头像位（结构存在，不是靠肉眼）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(players: 1, spectators: 0);
      useRoomScreen(tester, 900, 1600);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: f.scoped(kHostSeat, child: const GpKpPlayers()),
      ));
      await tester.pump();
      expect(find.byKey(GpKpPlayersKeys.avatar('p1')), findsOneWidget);
      expect(find.byType(GpPlMates), findsNothing,
          reason: 'KP 视角不该出现玩家专属的队友块');
    });
  });
}
