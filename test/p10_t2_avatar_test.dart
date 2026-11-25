// ============================================================
// test/p10_t2_avatar_test.dart — P10 第 2 期 A：头像跨设备（缩略 dataURI）
//
// 用户需求原文：「显示头像缩略图让游戏中的玩家栏里面也显示头像」。
// 真因：头像文件在本机私有目录，成员 sheet 里只有**本机相对路径**，
// 远端那台设备读不到 → 玩家栏永远是首字圆点。
// 老 APP v2.13.7 的解法：把头像压成 64px 正方形缩略图，随公开 sheet 广播。
//
// 覆盖：
//   A. 缩略图生成：正方形 / 64×64 / 短边居中裁 / 体积 ≤20000 / 无头像→空 /
//      解码失败不崩 / 超限逐级降尺寸
//   B. AvatarThumb 三层优先级：dataURI 能渲染 → 本机文件优先于 dataURI →
//      都没有退回首字圆点
//   C. **远端视角**（本批要修的场景，必须有正向用例）：成员 sheet.avatar 是
//      dataURI、本机没有该文件 → 玩家栏显示的是图，不是圆点
//   D. feed 条目头像：有 → 显示；超 20000 字符 → 置空回退
//   E. 无头像时**载荷里不带 avatar 键**（键不存在 ≠ 空串）
//
// 铁律：
//   · 缩略图生成要读盘 + 解码，所以放在普通 `test()` 里跑（真实异步可用）；
//   · widget 用例里头像一律用**预置字节 / 预置 dataURI**（`setUpAll` 里在
//     fake-async 之外生成一次），绝不在 fake-async 区域里等引擎解码；
//   · 零 Timer / Future.delayed / AnimationController。
// ============================================================

import 'dart:convert' show base64Encode, utf8;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dice_realm/domain/avatar_uri.dart'
    show avatarDataUriBytes, kAvatarThumbMaxChars, roomAvatarDataUri;
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart' show asMap;
import 'package:dice_realm/domain/room_types.dart' show RoomIntent;
import 'package:dice_realm/repo/avatar_store.dart';
import 'package:dice_realm/repo/avatar_thumb.dart'
    show
        avatarThumbEncoder,
        avatarThumbOf,
        encodeAvatarThumb,
        kAvatarThumbSize;
import 'package:dice_realm/repo/repo_scope.dart';
import 'package:dice_realm/theme.dart' show Palette;
import 'package:dice_realm/ui/room/sheets/card_sheet_payload.dart'
    show cardToRoomSheetForReport;
import 'package:dice_realm/ui/room/view/feed_view.dart'
    show FeedItem, FeedKind, collectChats;
import 'package:dice_realm/ui/room/widgets/gp_feeds.dart'
    show FeedList, GpFeedsKeys;
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart'
    show GpPlMates, GpPlMatesKeys;
import 'package:dice_realm/ui/widgets/auto_avatar_png.dart'
    show autoAvatarPngEncoder;
import 'package:dice_realm/ui/widgets/avatar_picker.dart'
    show AvatarThumb, memberAvatarValue;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart' show newMemoryRepo;
import 'support/room_ui_harness.dart' show RoomUiFixture;

// ------------------------------------------------------------
// 造图工具（普通 test / setUpAll 里可用真实 dart:ui）
// ------------------------------------------------------------

/// 画一张 [w]×[h] 的 PNG：中间按短边裁出的正方形涂 [mid]，两侧涂 [edge]。
///
/// 用来验证「短边居中裁正方形」：200×100 的图裁完只应剩下中间的 [mid] 色块。
Future<Uint8List> _pngStriped({
  required int w,
  required int h,
  required Color mid,
  required Color edge,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  final short = w < h ? w : h;
  final bar = (w - short) / 2.0;
  canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = edge);
  canvas.drawRect(
      ui.Rect.fromLTWH(bar, 0, short.toDouble(), h.toDouble()),
      ui.Paint()..color = mid);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 画一张 [n]×[n] 的「类噪声」PNG（每 6px 一个随机色块），用来逼出 PNG 体积。
///
/// 纯色图 PNG 太小，测不出「超限降尺寸」这条路径。
Future<Uint8List> _pngNoise(int n) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()));
  for (var y = 0; y < n; y += 6) {
    for (var x = 0; x < n; x += 6) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 6, 6),
        ui.Paint()
          ..color = Color(0xFF000000 | ((x * 7919 + y * 104729) & 0xFFFFFF)),
      );
    }
  }
  final pic = recorder.endRecording();
  final img = await pic.toImage(n, n);
  pic.dispose();
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 解一张图，返回 (宽, 高, 中心像素 RGB)。
Future<({int w, int h, int r, int g, int b})> _inspect(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final px = raw!.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
  final cx = img.width ~/ 2;
  final cy = img.height ~/ 2;
  final i = (cy * img.width + cx) * 4;
  final out =
      (w: img.width, h: img.height, r: px[i], g: px[i + 1], b: px[i + 2]);
  img.dispose();
  codec.dispose();
  return out;
}

/// widget 用例用的固定素材：一张 32×32 的 PNG 与它的 dataURI。
///
/// ★ 在 `setUpAll`（fake-async 之外）生成一次 —— `testWidgets` 里等引擎
///   解码会永远等不到，这是本批最容易踩的坑。
late Uint8List kTinyPng;
late String kTinyUri;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    kTinyPng = await _pngStriped(
      w: 32,
      h: 32,
      mid: const Color(0xFFFF0000),
      edge: const Color(0xFFFF0000),
    );
    kTinyUri = 'data:image/png;base64,${base64Encode(kTinyPng)}';
  });

  setUp(() {
    Palette.useBrightness(Brightness.dark);
  });

  // ==========================================================
  // A. 缩略图生成
  // ==========================================================
  group('A · 缩略图生成（短边居中裁正方形 + ≤20000 字符）', () {
    test('200×100 → 64×64 正方形，且只保留中间的正方形区域', () async {
      final src = await _pngStriped(
        w: 200,
        h: 100,
        mid: const Color(0xFFFF0000),
        edge: const Color(0xFF0000FF),
      );
      final uri = await encodeAvatarThumb(src);
      expect(uri.startsWith('data:image/png;base64,'), isTrue,
          reason: 'Flutter 只有 PNG 编码器（无 JPEG），见 avatar_thumb.dart 头注释');
      final info = await _inspect(avatarDataUriBytes(uri)!);
      expect(info.w, 64, reason: '默认边长 64（与老 APP 调用处同口径）');
      expect(info.h, 64, reason: '必须裁成正方形');
      expect(info.r, greaterThan(200), reason: '中心像素应来自原图中间（红）');
      expect(info.b, lessThan(60), reason: '两侧的蓝色条必须被裁掉');
    });

    test('竖图 100×200 同样按短边居中裁（长宽比不被拉伸）', () async {
      final src = await _pngStriped(
        w: 100,
        h: 200,
        mid: const Color(0xFF00FF00),
        edge: const Color(0xFF0000FF),
      );
      final info =
          await _inspect(avatarDataUriBytes(await encodeAvatarThumb(src))!);
      expect(info.w, 64);
      expect(info.h, 64, reason: '竖图也必须变成正方形（不能 64×128）');
      expect(info.g, greaterThan(150), reason: '中心像素应来自原图中间（绿）');
    });

    test('体积 ≤ 20000 字符（老 APP 的广播上限）', () async {
      final src = await _pngNoise(300);
      final uri = await encodeAvatarThumb(src);
      expect(uri.length, lessThanOrEqualTo(kAvatarThumbMaxChars));
      expect(uri, isNotEmpty, reason: '噪声图也必须能压进上限');
      // 实测值进报告（PNG 与老 APP 的 JPEG 差异要如实写）
      // ignore: avoid_print
      print('[P10-T2] 64px PNG base64 长度 = ${uri.length}');
    });

    test('超限时逐级降尺寸（64 → 48），而不是硬塞超限串', () async {
      final src = await _pngNoise(400);
      // 先量出 64 与 48 的真实体积，再把上限卡在两者之间 —— 确定性、不猜数字
      final at64 = await encodeAvatarThumb(src);
      final at48 = await encodeAvatarThumb(src, size: 48);
      expect(at64.length, greaterThan(at48.length),
          reason: '前提：64px 的 base64 一定比 48px 长');

      final uri = await encodeAvatarThumb(src, maxChars: at48.length);
      expect(uri, isNotEmpty);
      final info = await _inspect(avatarDataUriBytes(uri)!);
      expect(info.w, lessThan(kAvatarThumbSize),
          reason: '64px 超限时必须真的降到 48，而不是硬塞超限串');
      expect(info.w, 48);
      expect(info.h, 48);
      expect(uri.length, lessThanOrEqualTo(at48.length));
    });

    test('无头像 / 空字节 / 非图片 → 空串（不抛、不返回半截）', () async {
      expect(await avatarThumbOf(null), '');
      expect(await avatarThumbOf(''), '');
      expect(await avatarThumbOf('   '), '');
      expect(await avatarThumbOf(Uint8List(0)), '');
      expect(await encodeAvatarThumb(Uint8List(0)), '');
      expect(
        await encodeAvatarThumb(Uint8List.fromList(utf8.encode('not a png'))),
        '',
      );
    });

    test('本机相对路径不存在 → 空串（别人的路径读不到就老老实实空）', () async {
      final dir = Directory.systemTemp.createTempSync('p10_t2_thumb_');
      addTearDown(() => dir.deleteSync(recursive: true));
      avatarStore.rootOverride = dir.path;
      addTearDown(() => avatarStore.rootOverride = null);
      expect(await avatarThumbOf('avatars/不存在.png'), '');
    });

    test('本机相对路径存在 → 生成缩略图（读盘 + 裁剪走通）', () async {
      final dir = Directory.systemTemp.createTempSync('p10_t2_thumb_ok_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final avatars = Directory('${dir.path}/avatars')
        ..createSync(recursive: true);
      final src = await _pngStriped(
        w: 120,
        h: 60,
        mid: const Color(0xFF00FF00),
        edge: const Color(0xFF0000FF),
      );
      File('${avatars.path}/c1.png').writeAsBytesSync(src);
      avatarStore.rootOverride = dir.path;
      addTearDown(() => avatarStore.rootOverride = null);

      final uri = await avatarThumbOf('avatars/c1.png');
      expect(uri, isNotEmpty);
      final info = await _inspect(avatarDataUriBytes(uri)!);
      expect(info.w, 64);
      expect(info.h, 64);
    });

    test('roomAvatarDataUri：正则 + 20000 上限，两条都不放宽', () {
      const ok = 'data:image/png;base64,AAAA';
      expect(roomAvatarDataUri(ok), ok);
      expect(roomAvatarDataUri('data:image/jpeg;base64,AA'), isNotEmpty);
      expect(roomAvatarDataUri('data:image/webp;base64,AA'), isNotEmpty);
      expect(roomAvatarDataUri('data:image/svg+xml;base64,AA'), '',
          reason: '自动 SVG 头像不是位图，不能当缩略图广播');
      expect(roomAvatarDataUri('avatars/c1.png'), '',
          reason: '本机相对路径跨不了设备，绝不能进广播');
      expect(roomAvatarDataUri('data:image/png;base64,${'A' * 20001}'), '',
          reason: '超过 20000 字符必须置空');
    });
  });

  // ==========================================================
  // B. AvatarThumb 三层优先级
  // ==========================================================
  group('B · AvatarThumb 三层优先级', () {
    testWidgets('② dataURI → 渲染成 Image（不退成圆点）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: AvatarThumb(relPath: kTinyUri, size: 26, name: '沈')),
      ));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget,
          reason: 'dataURI 必须渲染成 Image，而不是退回首字圆点');
      expect(find.text('沈'), findsNothing);
    });

    testWidgets('③ 都没有 → 首字圆点', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: AvatarThumb(relPath: null, size: 26, name: '沈')),
      ));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.text('沈'), findsOneWidget,
          reason: '拿不到图就显示首字（老 APP 同口径）');
    });

    testWidgets('① 本机文件优先于 dataURI：文件存在时返回相对路径',
        (WidgetTester tester) async {
      final dir = Directory.systemTemp.createTempSync('p10_t2_prio_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final avatars = Directory('${dir.path}/avatars')
        ..createSync(recursive: true);
      // 同步写盘（fake-async 里同步 I/O 是安全的；异步 I/O 会挂死）
      File('${avatars.path}/c1.png').writeAsBytesSync(kTinyPng);
      avatarStore.rootOverride = dir.path;
      addTearDown(() => avatarStore.rootOverride = null);

      final repo = await newMemoryRepo();
      final card = Character(newCharacter());
      card.raw['id'] = 'c1';
      card.raw['characterName'] = '沈墨白';
      card.raw['avatar'] = 'avatars/c1.png';
      await repo.save(card);

      String? got;
      await tester.pumpWidget(MaterialApp(
        home: RepoScope(
          repo: repo,
          child: Builder(builder: (BuildContext ctx) {
            got = memberAvatarValue(ctx, <String, Object?>{
              'seat': 'p1',
              'charId': 'c1',
              'sheet': <String, Object?>{'avatar': kTinyUri},
            });
            return const SizedBox();
          }),
        ),
      ));
      expect(got, 'avatars/c1.png',
          reason: '同机有原图文件时优先走文件（高清），不为了统一而下采样');
    });

    testWidgets('② 本机没有该文件 → 返回 dataURI（跨设备）',
        (WidgetTester tester) async {
      final dir = Directory.systemTemp.createTempSync('p10_t2_prio2_');
      addTearDown(() => dir.deleteSync(recursive: true));
      avatarStore.rootOverride = dir.path; // 目录里什么都没有
      addTearDown(() => avatarStore.rootOverride = null);

      final repo = await newMemoryRepo();
      String? got;
      await tester.pumpWidget(MaterialApp(
        home: RepoScope(
          repo: repo,
          child: Builder(builder: (BuildContext ctx) {
            got = memberAvatarValue(ctx, <String, Object?>{
              'seat': 'p2',
              'charId': 'c_p2',
              'sheet': <String, Object?>{'avatar': kTinyUri},
            });
            return const SizedBox();
          }),
        ),
      ));
      expect(got, kTinyUri,
          reason: '读不到本机文件时，必须回落到广播来的缩略 dataURI');
    });

    testWidgets('③ 既无文件也无 dataURI → null（退回首字圆点）',
        (WidgetTester tester) async {
      final dir = Directory.systemTemp.createTempSync('p10_t2_prio3_');
      addTearDown(() => dir.deleteSync(recursive: true));
      avatarStore.rootOverride = dir.path;
      addTearDown(() => avatarStore.rootOverride = null);
      final repo = await newMemoryRepo();
      String? got = 'x';
      await tester.pumpWidget(MaterialApp(
        home: RepoScope(
          repo: repo,
          child: Builder(builder: (BuildContext ctx) {
            got = memberAvatarValue(ctx, <String, Object?>{
              'seat': 'p2',
              'charId': '',
              'sheet': <String, Object?>{},
            });
            return const SizedBox();
          }),
        ),
      ));
      expect(got, isNull);
    });

    testWidgets('★ 同路径覆盖写：bump revision 后强制重载（「更换」要生效）',
        (WidgetTester tester) async {
      // 复现 bug：更换时写回同一个 avatars/c1.png，路径不变 →
      //   仅靠 relPath 比较不会重新 _reload，且 FileImage 以路径为缓存键会吐旧图。
      // 修法：AvatarThumb 新增 revision，变化即 evict + 重载。
      final dir = Directory.systemTemp.createTempSync('p10_t2_replace_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final avatars = Directory('${dir.path}/avatars')
        ..createSync(recursive: true);
      File('${avatars.path}/c1.png').writeAsBytesSync(kTinyPng);
      avatarStore.rootOverride = dir.path;
      addTearDown(() => avatarStore.rootOverride = null);

      Widget build(int rev) => MaterialApp(
            home: Center(
              child: AvatarThumb(
                relPath: 'avatars/c1.png',
                size: 40,
                name: '沈',
                revision: rev,
              ),
            ),
          );

      await tester.pumpWidget(build(0));
      await tester.pump();
      final img0 = tester.widget<Image>(find.byType(Image));
      final prov0 = img0.image;
      expect(prov0, isA<FileImage>());
      final path0 = (prov0 as FileImage).file.path;

      // 模拟「更换」：同一个文件被覆盖写入新字节（这里内容无所谓，关键是代次）。
      File('${avatars.path}/c1.png')
          .writeAsBytesSync(<int>[137, 80, 78, 71, 1, 2, 3]); // 伪字节，仅换 mtime

      // 代次不变 → 不重载，provider 实例同一（证明我们没瞎重建）
      await tester.pumpWidget(build(0));
      await tester.pump();
      final imgSame = tester.widget<Image>(find.byType(Image));
      expect(identical(imgSame.image, prov0), isTrue,
          reason: 'revision 未变时不应重建 provider');

      // 代次 +1（模拟成功导入后的 bump）→ 必须重载成新的 FileImage 实例
      await tester.pumpWidget(build(1));
      await tester.pump();
      final img1 = tester.widget<Image>(find.byType(Image));
      expect(img1.image, isA<FileImage>());
      expect(identical(img1.image, prov0), isFalse,
          reason: 'revision 变化必须重载，换出新的 provider');
      // 路径仍是同一个（写回同文件），但旧缓存已被 evict → 不会命中旧字节
      expect((img1.image as FileImage).file.path, path0,
          reason: '覆盖写仍写回同一个文件路径');
    });
  });

  // ==========================================================
  // C. 远端视角（本批要修的场景 —— 必须有正向用例）
  // ==========================================================
  group('C · 远端玩家在玩家栏里显示头像（本批核心）', () {
    testWidgets('成员 sheet.avatar 是 dataURI、本机无该文件 → 队友栏显示图，不是圆点',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(players: 2, spectators: 0);

      // 本机没有任何头像文件（模拟「这是我这台设备，别人的头像文件不存在」）
      final dir = Directory.systemTemp.createTempSync('p10_t2_remote_');
      addTearDown(() => dir.deleteSync(recursive: true));
      avatarStore.rootOverride = dir.path;
      addTearDown(() => avatarStore.rootOverride = null);

      // p2 在自己的设备上报卡：sheet.avatar 是缩略 dataURI（跨设备唯一载体）
      await f.plSessions['p2']!.sendIntent(RoomIntent.char, <String, Object?>{
        'id': 'c_p2',
        'name': '远端玩家',
        'sheet': <String, Object?>{
          'name': '远端玩家',
          'avatar': kTinyUri,
          'attrs': <String, Object?>{'str': 50},
          'status': <String, Object?>{'currentHP': 10, 'maxHP': 12},
        },
      });

      final p2 = asMap((f.stateOf('p1')['members'] as List)
          .firstWhere((Object? m) => asMap(m)['seat'] == 'p2'));
      expect(asMap(p2['sheet'])['avatar'], kTinyUri,
          reason: '权威端必须把缩略头像公开给同席（老 APP `_cropMember` 同口径）');

      f.localOf('p1').setMatesOpen(true);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: f.scoped(
          'p1',
          child: const Scaffold(
            body: SingleChildScrollView(
              // ★ P20 需求 3⑤：`matesOpen` 默认 false ⇒ 这里用 forceOpen
              //   测「队友行的头像图」（列表内容），不是收起语义。
              child: SizedBox(width: 360, child: GpPlMates(forceOpen: true)),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byKey(GpPlMatesKeys.row('p2')), findsOneWidget);
      expect(find.byKey(GpPlMatesKeys.avatar('p2')), findsOneWidget);
      // ★ 正向断言：p2 那一行必须是图（本批修的就是这里）
      expect(
        find.descendant(
          of: find.byKey(GpPlMatesKeys.avatar('p2')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
        reason: '远端玩家的自定义头像必须显示成图片，不能退化成首字圆点',
      );
      expect(
        find.descendant(
          of: find.byKey(GpPlMatesKeys.avatar('p2')),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: '有图时不许再画首字（三个「玩」字会重叠）',
      );
    });
  });

  // ==========================================================
  // D. feed 条目头像
  // ==========================================================
  group('D · 聊天 / 记录条目左侧头像', () {
    test('成员有缩略头像 → 条目 avatar 非空；超 20000 字符 → 置空', () {
      final uri = 'data:image/png;base64,${'A' * 100}';
      final huge = 'data:image/png;base64,${'A' * 30000}';
      Map<String, Object?> stateWith(String avatar) => <String, Object?>{
            'members': <Object?>[
              <String, Object?>{
                'seat': 'p1',
                'nickname': '甲',
                'sheet': <String, Object?>{'avatar': avatar},
              },
            ],
            'chats': <Object?>[
              <String, Object?>{
                'seq': 1,
                'at': 1,
                'seat': 'p1',
                'nickname': '甲',
                'text': '你好',
              },
            ],
          };

      expect(collectChats(stateWith(uri)).single.avatar, uri);
      expect(collectChats(stateWith(huge)).single.avatar, '',
          reason: '超过 20000 字符必须置空（老 APP `sanitizeSheet` 同口径）');
      expect(collectChats(stateWith('')).single.avatar, '');
    });

    testWidgets('条目有头像 → 渲染图；没有 → 不渲染（不留空位）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 200,
            child: FeedList(
              items: <FeedItem>[
                FeedItem(
                  seq: 1,
                  at: 1,
                  kind: FeedKind.chat,
                  seat: 'p1',
                  nickname: '甲',
                  text: '你好',
                  avatar: kTinyUri,
                ),
              ],
              scrollable: false,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.avatar(1)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(GpFeedsKeys.avatar(1)),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 200,
            child: FeedList(
              items: <FeedItem>[
                FeedItem(
                  seq: 2,
                  at: 2,
                  kind: FeedKind.chat,
                  seat: 'p1',
                  nickname: '甲',
                  text: '无头像',
                ),
              ],
              scrollable: false,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(GpFeedsKeys.avatar(2)), findsNothing,
          reason: '没有头像就不渲染整块，不留空位');
    });
  });

  // ==========================================================
  // E. 载荷里不带 avatar 键
  // ==========================================================
  group('E · 无头像时载荷里不带 avatar 键', () {
    test('没有头像 → sheet 里**不存在** avatar 键（不是空串）', () async {
      final saved = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = saved);
      avatarThumbEncoder = (Object? _) async => '';
      // ★ P10 第 3 期 A 批：没有上传头像时会再走一步「自动头像 PNG 化」
      //   （跨设备广播必须 PNG）。生成器是 `picture.toImage()` 的真异步，
      //   fake-async 区域里永不完成 → 这里同样换成空串替身，
      //   本用例的判据（没有可广播头像 → 删键）保持不变。
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      autoAvatarPngEncoder = (spec) async => '';

      final card = Character(newCharacter());
      card.raw['id'] = 'c1';
      card.raw['characterName'] = '无头像';
      final sheet = await cardToRoomSheetForReport(card);
      expect(sheet.containsKey('avatar'), isFalse,
          reason: '老 APP 原文：「没有头像 → 不占广播体积」；空串也算占体积');
    });

    test('有头像 → sheet.avatar 就是缩略 dataURI', () async {
      final saved = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = saved);
      const thumb = 'data:image/png;base64,AAAA';
      avatarThumbEncoder = (Object? _) async => thumb;
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      autoAvatarPngEncoder = (spec) async => '';

      final card = Character(newCharacter());
      card.raw['id'] = 'c1';
      card.raw['characterName'] = '有头像';
      card.raw['avatar'] = 'avatars/c1.png';
      final sheet = await cardToRoomSheetForReport(card);
      expect(sheet['avatar'], thumb);
    });

    test('缩略图生成抛异常也不能挡住绑卡（降级为不带 avatar）', () async {
      final saved = avatarThumbEncoder;
      addTearDown(() => avatarThumbEncoder = saved);
      avatarThumbEncoder = (Object? _) async => throw StateError('boom');
      // 自动头像那一步也抛：两条降级路径都走一遍
      final savedAuto = autoAvatarPngEncoder;
      addTearDown(() => autoAvatarPngEncoder = savedAuto);
      autoAvatarPngEncoder = (spec) async => throw StateError('boom');

      final card = Character(newCharacter());
      card.raw['id'] = 'c1';
      final sheet = await cardToRoomSheetForReport(card);
      expect(sheet.containsKey('avatar'), isFalse);
      expect(sheet['name'], isNotNull, reason: '其余字段照常上报，绑卡不失败');
    });
  });
}
