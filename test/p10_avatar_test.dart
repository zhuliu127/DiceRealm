// ============================================================
// test/p10_avatar_test.dart — 角色头像（上传 / 落盘 / 显示）验收
//
// 覆盖：
//   A 存储层（普通 test，真 I/O + 真编解码）
//     · importFrom 落盘、文件名含 cardId、最长边缩到 ≤512、小图不放大
//     · remove / providerFor / localAvatarRel 的边界
//   B 向导第 2 步（widget）
//     · 老卡（没有 avatar 字段）→ 显示占位、不崩
//     · 选图 → 写进 draft.raw['avatar']；取消 → 一个字节都不改
//     · 移除 → 字段清空、回到占位
//   C 名册 / 卡面（widget）
//     · 有头像 → 按该路径渲染图片；没有 → 占位
//   D 跑团房间玩家栏（widget）
//     · KP 视角：sheet.avatar 直接命中
//     · 玩家视角 / 我的角色卡：sheet 被白名单裁剪时，按 member.charId
//       回查本机角色库命中（这是生产里实际生效的那条路）
//
// ★ 依赖注入（与 cardTransferIo 同一套路）：
//   `avatarStore.rootOverride = <临时目录>` 把落盘根目录换掉，不碰 path_provider；
//   `avatarPicker` / `avatarImageImporter` 换成假实现，避免 fake-async 区域里
//   平台通道 / 引擎解码的 Future 永远不返回。
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dice_realm/domain/ai_caps.dart';
import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/net/ai_create.dart' show AiCreateResult;
import 'package:dice_realm/repo/avatar_store.dart';
import 'package:dice_realm/repo/repo_scope.dart';
import 'package:dice_realm/theme.dart';
import 'package:dice_realm/ui/ai_create_page.dart';
import 'package:dice_realm/ui/create/steps/step_basics.dart';
import 'package:dice_realm/ui/random_create_page.dart';
import 'package:dice_realm/ui/room/widgets/gp_kp_players.dart';
import 'package:dice_realm/ui/room/widgets/gp_pl_char_card.dart';
import 'package:dice_realm/ui/room/widgets/gp_pl_mates.dart';
import 'package:dice_realm/ui/roster_page.dart';
import 'package:dice_realm/ui/widgets/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/room_ui_harness.dart';

/// 造一张指定尺寸的纯色 PNG（真字节，能被 dart:ui 解码）。
Future<Uint8List> _makePng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF2F6FB2),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 读回 PNG 的像素尺寸（验证「缩放」不是嘴上说说）。
Future<(int, int)> _pngSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return size;
}

/// 假选图：返回预置字节（null = 用户取消）。
class _FakeAvatarPicker implements AvatarPickerPort {
  _FakeAvatarPicker(this.bytes);

  Uint8List? bytes;
  int calls = 0;
  String? lastTitle;

  @override
  Future<Uint8List?> pickImageBytes({String? title, int maxBytes = 0}) async {
    calls++;
    lastTitle = title;
    return bytes;
  }
}

/// 假的「字节 → 相对路径」：只记参数、直接给路径（编解码由 A 组真测）。
class _FakeImporter {
  final List<String> cardIds = <String>[];
  String? result = 'avatars/card0001.png';

  Future<String?> call(Uint8List bytes, String cardId) async {
    cardIds.add(cardId);
    return result;
  }
}

/// 装一套假选图 + 假落盘（用例结束自动还原全局实例）
void _useFakePick(Uint8List bytes, String rel) {
  final fakeImporter = _FakeImporter()..result = rel;
  final prevPicker = avatarPicker;
  final prevImporter = avatarImageImporter;
  avatarPicker = _FakeAvatarPicker(bytes);
  avatarImageImporter = fakeImporter.call;
  addTearDown(() {
    avatarPicker = prevPicker;
    avatarImageImporter = prevImporter;
  });
}

/// 一张能落库的完整卡
Character _card(String id, String name) {
  final c = Character(newCharacter());
  c.raw['id'] = id;
  c.raw['characterName'] = name;
  c.raw['playerName'] = '老王';
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List srcPng;
  late Directory tmp;

  setUpAll(() async {
    srcPng = await _makePng(900, 600); // 大于 512：用来验缩放
  });

  setUp(() async {
    Palette.useBrightness(Brightness.dark);
    tmp = await Directory.systemTemp.createTemp('dice_avatar_');
    avatarStore.rootOverride = tmp.path;
  });

  tearDown(() async {
    Palette.useBrightness(Brightness.dark);
    avatarStore.rootOverride = null;
    try {
      await tmp.delete(recursive: true);
    } catch (_) {
      // 删不掉不影响用例结论（系统临时目录）
    }
  });

  // =========================================================
  // A. 存储层（真 I/O）
  // =========================================================
  group('A 存储层', () {
    test('importFrom 落盘到 avatars/<cardId>.png，并把最长边缩到 512', () async {
      final src = File('${tmp.path}${Platform.pathSeparator}src.png');
      await src.writeAsBytes(srcPng, flush: true);

      final rel = await avatarStore.importFrom(src, 'card0001');
      expect(rel, 'avatars/card0001.png', reason: '相对路径 + 文件名必须含 cardId');

      final saved = File(
        '${tmp.path}${Platform.pathSeparator}avatars'
        '${Platform.pathSeparator}card0001.png',
      );
      expect(saved.existsSync(), isTrue, reason: '图片必须真的落盘');

      final (w, h) = await _pngSize(await saved.readAsBytes());
      expect(w > h, isTrue, reason: '900×600 是横图，缩放后仍应横着');
      expect(w, 512, reason: '最长边必须缩到 512');
      expect(h, lessThanOrEqualTo(512));
      expect((h / w - 600 / 900).abs() < 0.02, isTrue, reason: '不能把图拉变形');
    });

    test('小图不会被放大（100×80 原样保留）', () async {
      final small = await _makePng(100, 80);
      final rel = await avatarStore.importBytes(small, 'small01');
      expect(rel, 'avatars/small01.png');
      final file = await avatarStore.fileOf(rel);
      final (w, h) = await _pngSize(await file!.readAsBytes());
      expect((w, h), (100, 80));
    });

    test('remove 删掉文件；providerFor 对不存在 / 非法路径返回 null', () async {
      final rel = await avatarStore.importBytes(srcPng, 'gone01');
      expect(await avatarStore.providerFor(rel), isA<FileImage>());

      await avatarStore.remove(rel);
      expect(await avatarStore.fileOf(rel), isNull);
      expect(await avatarStore.providerFor(rel), isNull);

      expect(await avatarStore.providerFor(null), isNull);
      expect(await avatarStore.providerFor(''), isNull);
      expect(await avatarStore.providerFor('data:image/png;base64,AAAA'), isNull);
      expect(await avatarStore.providerFor('https://x/y.png'), isNull);
      expect(await avatarStore.providerFor('../../etc/passwd'), isNull);
    });

    test('importBytes 拒绝非图片字节（返回 null，不写半个坏文件）', () async {
      final rel = await avatarStore.importBytes(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        'bad00001',
      );
      expect(rel, isNull);
      expect(
        Directory('${tmp.path}${Platform.pathSeparator}avatars').existsSync(),
        isFalse,
        reason: '失败时不该留下 avatars 目录 / 空文件',
      );
    });

    test('localAvatarRel：只认本机相对路径', () {
      expect(localAvatarRel('avatars/card0001.png'), 'avatars/card0001.png');
      expect(localAvatarRel('  avatars/a.png  '), 'avatars/a.png');
      expect(localAvatarRel(''), isNull);
      expect(localAvatarRel(null), isNull);
      expect(localAvatarRel('data:image/svg+xml;charset=utf-8,%3Csvg%3E'), isNull);
      expect(localAvatarRel('https://cdn/x.png'), isNull);
      expect(localAvatarRel('/data/user/0/app/a.png'), isNull);
      expect(localAvatarRel('C:/tmp/a.png'), isNull);
      expect(localAvatarRel('avatars/../../a.png'), isNull);
    });

    test('safeName 挡住路径穿越与奇怪字符', () {
      expect(AvatarStore.safeName('card0001'), 'card0001');
      expect(AvatarStore.safeName('../etc/passwd'), isNot(contains('/')));
      expect(AvatarStore.safeName('../etc/passwd'), isNot(contains('..')));
      expect(AvatarStore.safeName(''), 'unnamed');
    });
  });

  // =========================================================
  // B. 向导第 2 步：选 / 换 / 移除
  // =========================================================
  group('B 向导第 2 步', () {
    Future<void> pumpStep(WidgetTester tester, Character draft) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: StepBasics(draft: draft, onChanged: () {}),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('老卡没有 avatar 字段：显示占位，不崩', (tester) async {
      final draft = _card('card0001', '阿米蒂奇');
      draft.raw.remove('avatar');
      await pumpStep(tester, draft);

      expect(find.byKey(const Key('basics_avatar')), findsOneWidget);
      expect(find.byKey(const Key('basics_avatar_pick')), findsOneWidget);
      expect(find.byKey(const Key('basics_avatar_clear')), findsNothing,
          reason: '没有头像时不该有「移除」');
      expect(
        find.descendant(
          of: find.byKey(const Key('basics_avatar_thumb')),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('选图 → 写进 draft.raw["avatar"]，预览换成图片', (tester) async {
      final fakePicker = _FakeAvatarPicker(srcPng);
      final fakeImporter = _FakeImporter();
      final prevPicker = avatarPicker;
      final prevImporter = avatarImageImporter;
      avatarPicker = fakePicker;
      avatarImageImporter = fakeImporter.call;
      addTearDown(() {
        avatarPicker = prevPicker;
        avatarImageImporter = prevImporter;
      });

      final draft = _card('card0001', '阿米蒂奇');
      await pumpStep(tester, draft);

      await tester.tap(find.byKey(const Key('basics_avatar_pick')));
      await tester.pump();

      expect(fakePicker.calls, 1);
      expect(fakeImporter.cardIds.single, 'card0001',
          reason: '落盘文件名必须用这张卡的 id');
      expect(draft.raw['avatar'], 'avatars/card0001.png');
      expect(find.byKey(const Key('basics_avatar_clear')), findsOneWidget);
    });

    testWidgets('取消选图：字段一个字节都不改', (tester) async {
      final fakePicker = _FakeAvatarPicker(null);
      final prevPicker = avatarPicker;
      avatarPicker = fakePicker;
      addTearDown(() => avatarPicker = prevPicker);

      final draft = _card('card0001', '阿米蒂奇');
      await pumpStep(tester, draft);

      await tester.tap(find.byKey(const Key('basics_avatar_pick')));
      await tester.pump();

      expect(fakePicker.calls, 1);
      expect(draft.raw['avatar'], isEmpty);
    });

    testWidgets('已有头像 → 按路径渲染图片；移除 → 字段清空并回到占位', (tester) async {
      // 真写一份文件，让同步 provider 能命中
      final avatarFile = File(
        '${tmp.path}${Platform.pathSeparator}avatars'
        '${Platform.pathSeparator}card0001.png',
      );
      avatarFile.parent.createSync(recursive: true);
      avatarFile.writeAsBytesSync(srcPng);

      final draft = _card('card0001', '阿米蒂奇');
      draft.raw['avatar'] = 'avatars/card0001.png';
      await pumpStep(tester, draft);

      final thumb = find.byKey(const Key('basics_avatar_thumb'));
      final imageFinder = find.descendant(of: thumb, matching: find.byType(Image));
      expect(imageFinder, findsOneWidget, reason: '有头像就该画图，不是首字');
      final provider = tester.widget<Image>(imageFinder).image;
      expect(provider, isA<FileImage>());
      expect(
        (provider as FileImage).file.path,
        endsWith('avatars${Platform.pathSeparator}card0001.png'),
      );

      await tester.tap(find.byKey(const Key('basics_avatar_clear')));
      await tester.pump();

      expect(draft.raw['avatar'], '');
      expect(
        find.descendant(of: thumb, matching: find.byType(Image)),
        findsNothing,
        reason: '清除后必须回到首字占位',
      );
    });
  });

  // =========================================================
  // C. 名册
  // =========================================================
  group('C 名册', () {
    testWidgets('有头像的卡按路径渲染缩略图', (tester) async {
      final avatarFile = File(
        '${tmp.path}${Platform.pathSeparator}avatars'
        '${Platform.pathSeparator}card0001.png',
      );
      avatarFile.parent.createSync(recursive: true);
      avatarFile.writeAsBytesSync(srcPng);

      final repo = await newMemoryRepo();
      final c = validCard(id: 'card0001', name: '阿米蒂奇');
      c.raw['avatar'] = 'avatars/card0001.png';
      await repo.save(c);

      await pumpApp(tester, repo: repo, home: const RosterPage());
      await tester.pumpAndSettle();

      final thumb = find.byKey(const Key('roster_avatar_card0001'));
      expect(thumb, findsOneWidget);
      final imageFinder = find.descendant(of: thumb, matching: find.byType(Image));
      expect(imageFinder, findsOneWidget);
      final provider = tester.widget<Image>(imageFinder).image as FileImage;
      expect(provider.file.path, endsWith('card0001.png'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('老卡（无 avatar 字段）不崩，显示首字占位', (tester) async {
      final repo = await newMemoryRepo();
      final c = validCard(id: 'oldcard1', name: '老卡调查员');
      c.raw.remove('avatar');
      await repo.save(c);

      await pumpApp(tester, repo: repo, home: const RosterPage());
      await tester.pumpAndSettle();

      final thumb = find.byKey(const Key('roster_avatar_oldcard1'));
      expect(thumb, findsOneWidget, reason: '占位圆点也必须存在（布局不能跳）');
      expect(
        find.descendant(of: thumb, matching: find.byType(Image)),
        findsNothing,
      );
      expect(find.text('老'), findsWidgets, reason: '首字占位');
      expect(tester.takeException(), isNull);
    });

    testWidgets('avatar 是自动 SVG dataURI 时不当文件路径读（显示占位）',
        (tester) async {
      final repo = await newMemoryRepo();
      final c = validCard(id: 'svgcard1', name: '自动头像');
      c.raw['avatar'] = 'data:image/svg+xml;charset=utf-8,%3Csvg%3E';
      await repo.save(c);

      await pumpApp(tester, repo: repo, home: const RosterPage());
      await tester.pumpAndSettle();

      final thumb = find.byKey(const Key('roster_avatar_svgcard1'));
      expect(
        find.descendant(of: thumb, matching: find.byType(Image)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================
  // D. 跑团房间玩家栏
  // =========================================================
  group('D 房间玩家栏', () {
    /// 只造「一个玩家成员」的最小 state（给 GpKpPlayers 的 stateOverride 用）。
    Map<String, Object?> stateWith({
      String seat = 'p1',
      String avatar = '',
      String charId = '',
    }) {
      return <String, Object?>{
        'status': 'playing',
        'members': <Object?>[
          <String, Object?>{
            'seat': seat,
            'role': 'player',
            'nickname': '玩家1',
            'charId': charId,
            'sheet': <String, Object?>{
              'name': '玩家1的调查员',
              'avatar': avatar,
              'attrs': <String, Object?>{'str': 50, 'dex': 55},
              'status': <String, Object?>{
                'currentHP': 12,
                'maxHP': 12,
                'currentMP': 10,
                'maxMP': 10,
                'currentSAN': 50,
                'maxSAN': 60,
                'body': '正常',
              },
              'mental': <Object?>['正常'],
            },
          },
        ],
      };
    }

    Widget host(RoomUiFixture f, String seat, Widget body) {
      return MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (BuildContext _, Widget? child) => RepoScope(
          repo: f.repo,
          child: f.scoped(seat, child: child ?? const SizedBox.shrink()),
        ),
        home: Scaffold(body: SingleChildScrollView(child: body)),
      );
    }

    Future<RoomUiFixture> boot(WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 800, 1400);
      return f;
    }

    testWidgets('KP 视角：成员 sheet.avatar 命中 → 显示图片', (tester) async {
      final f = await boot(tester);
      final avatarFile = File(
        '${tmp.path}${Platform.pathSeparator}avatars'
        '${Platform.pathSeparator}p1.png',
      );
      avatarFile.parent.createSync(recursive: true);
      avatarFile.writeAsBytesSync(srcPng);

      await tester.pumpWidget(
        host(
          f,
          kHostSeat,
          GpKpPlayers(stateOverride: stateWith(avatar: 'avatars/p1.png')),
        ),
      );
      await tester.pump();

      final thumb = find.byKey(GpKpPlayersKeys.avatar('p1'));
      expect(thumb, findsOneWidget);
      final imageFinder = find.descendant(of: thumb, matching: find.byType(Image));
      expect(imageFinder, findsOneWidget);
      expect(
        (tester.widget<Image>(imageFinder).image as FileImage).file.path,
        endsWith('p1.png'),
      );
    });

    testWidgets('KP 视角：没有头像 → 还是原来的首字圆点', (tester) async {
      final f = await boot(tester);
      await tester.pumpWidget(
        host(f, kHostSeat, GpKpPlayers(stateOverride: stateWith())),
      );
      await tester.pump();

      final thumb = find.byKey(GpKpPlayersKeys.avatar('p1'));
      expect(thumb, findsOneWidget);
      expect(
        find.descendant(of: thumb, matching: find.byType(Image)),
        findsNothing,
      );
      expect(find.text('玩'), findsWidgets, reason: '退化成首字');
    });

    testWidgets('玩家视角队友栏：按 member.charId 回查本机角色库', (tester) async {
      final avatarFile = File(
        '${tmp.path}${Platform.pathSeparator}avatars'
        '${Platform.pathSeparator}c_p2.png',
      );
      avatarFile.parent.createSync(recursive: true);
      avatarFile.writeAsBytesSync(srcPng);

      final f = await boot(tester);
      // 房间成员由 shareSheets 写入 charId = 'c_p2'；把那张卡存进本机库
      final c = _card('c_p2', '玩家2的调查员');
      c.raw['avatar'] = 'avatars/c_p2.png';
      await f.repo.save(c);

      // ★ P20 需求 3⑤：`matesOpen` 默认改成 false（dock 里默认收起）。
      //   本用例测「队友行按 charId 回查本机头像」，属**列表内容** ⇒ forceOpen。
      await tester.pumpWidget(host(f, 'p1', const GpPlMates(forceOpen: true)));
      await tester.pump();

      final thumb = find.byKey(GpPlMatesKeys.avatar('p2'));
      expect(thumb, findsOneWidget, reason: 'p2 应该出现在队友列表里');
      final imageFinder = find.descendant(of: thumb, matching: find.byType(Image));
      expect(
        imageFinder,
        findsOneWidget,
        reason: 'sheet.avatar 被白名单裁掉后，得靠 charId 回查本机卡',
      );
      expect(
        (tester.widget<Image>(imageFinder).image as FileImage).file.path,
        endsWith('c_p2.png'),
      );
    });

    testWidgets('我的角色卡：也显示头像；无头像时不崩', (tester) async {
      final avatarFile = File(
        '${tmp.path}${Platform.pathSeparator}avatars'
        '${Platform.pathSeparator}c_p1.png',
      );
      avatarFile.parent.createSync(recursive: true);
      avatarFile.writeAsBytesSync(srcPng);

      final f = await boot(tester);
      final c = _card('c_p1', '玩家1的调查员');
      c.raw['avatar'] = 'avatars/c_p1.png';
      await f.repo.save(c);

      await tester.pumpWidget(host(f, 'p1', const GpPlCharCard()));
      await tester.pump();

      final thumb = find.byKey(GpPlCharCardKeys.avatar);
      expect(thumb, findsOneWidget);
      expect(
        find.descendant(of: thumb, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('我的角色卡：没有头像 → 首字圆点，不崩', (tester) async {
      final f = await boot(tester);
      await tester.pumpWidget(host(f, 'p1', const GpPlCharCard()));
      await tester.pump();

      final thumb = find.byKey(GpPlCharCardKeys.avatar);
      expect(thumb, findsOneWidget);
      expect(
        find.descendant(of: thumb, matching: find.byType(Image)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================
  // E. AI 车卡：生成之前选头像
  // =========================================================
  group('E AI 车卡', () {
    testWidgets('生成之前就有头像位；选了图 → 生成结果卡带上它', (tester) async {
      _useFakePick(srcPng, 'avatars/ai_tmp.png');

      final generated = _card('ai000001', '民国侦探');
      final page = AiCreatePage(
        generate: (AiGenerateRequest req, void Function(String) onStage) async {
          onStage('正在生成');
          return AiCreateResult(
            character: generated,
            profile: const <String, Object?>{},
            raw: null,
            caps: const AiCaps(),
            attrScaled: false,
          );
        },
      );

      await pumpApp(tester, home: page);
      await tester.pumpAndSettle();

      // ① 生成之前就存在（还没有结果卡）
      expect(find.byKey(const Key('ai_avatar')), findsOneWidget);
      expect(find.byKey(const Key('ai_result_card')), findsNothing);

      // ② 选图
      await tester.tap(find.byKey(const Key('ai_avatar_pick')));
      await tester.pump();
      expect(find.byKey(const Key('ai_avatar_clear')), findsOneWidget);

      // ③ 生成
      await tester.enterText(find.byKey(const Key('ai_desc')), '民国时期的私家侦探');
      await tester.ensureVisible(find.byKey(const Key('ai_generate')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai_generate')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai_result_card')), findsOneWidget);
      expect(generated.raw['avatar'], 'avatars/ai_tmp.png',
          reason: '生成出来的卡必须自带这张头像');
    });

    testWidgets('没选头像 → 不动生成卡自带的自动头像', (tester) async {
      const auto = 'data:image/svg+xml;charset=utf-8,%3Csvg%3E';
      final generated = _card('ai000002', '自动头像');
      generated.raw['avatar'] = auto;
      final page = AiCreatePage(
        generate: (AiGenerateRequest req, void Function(String) onStage) async =>
            AiCreateResult(
              character: generated,
              profile: const <String, Object?>{},
              raw: null,
              caps: const AiCaps(),
              attrScaled: false,
            ),
      );

      await pumpApp(tester, home: page);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ai_desc')), '随便写一句');
      await tester.ensureVisible(find.byKey(const Key('ai_generate')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai_generate')));
      await tester.pumpAndSettle();

      expect(generated.raw['avatar'], auto);
    });
  });

  // =========================================================
  // F. 一键出卡：生成之前选头像，整批候选都带上
  // =========================================================
  group('F 一键出卡', () {
    testWidgets('选了头像 → 这一批候选卡都带它；重新随机后仍然带', (tester) async {
      _useFakePick(srcPng, 'avatars/random_tmp.png');

      final cards = <Character>[
        _card('rnd00001', '甲'),
        _card('rnd00002', '乙'),
      ];
      await pumpApp(
        tester,
        home: RandomCreatePage(generate: () => cards),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('random_avatar')), findsOneWidget);
      expect(cards.first.raw['avatar'], isEmpty, reason: '没选之前不动卡上的字段');

      await tester.tap(find.byKey(const Key('random_avatar_pick')));
      await tester.pump();

      expect(cards[0].raw['avatar'], 'avatars/random_tmp.png');
      expect(cards[1].raw['avatar'], 'avatars/random_tmp.png');

      // 重新随机（同一批对象由注入函数返回）—— 头像必须还在
      await tester.tap(find.byKey(const Key('random_reroll')));
      await tester.pump();
      expect(cards[0].raw['avatar'], 'avatars/random_tmp.png');
      expect(cards[1].raw['avatar'], 'avatars/random_tmp.png');
    });

    testWidgets('清除头像 → 还原成生成卡自带的自动头像', (tester) async {
      const auto = 'data:image/svg+xml;charset=utf-8,%3Csvg%3E';
      _useFakePick(srcPng, 'avatars/random_tmp.png');

      final c = _card('rnd00003', '丙');
      c.raw['avatar'] = auto;
      await pumpApp(
        tester,
        home: RandomCreatePage(generate: () => <Character>[c]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('random_avatar_pick')));
      await tester.pump();
      expect(c.raw['avatar'], 'avatars/random_tmp.png');

      await tester.tap(find.byKey(const Key('random_avatar_clear')));
      await tester.pump();
      expect(c.raw['avatar'], auto, reason: '清掉自定义头像要还给系统自动头像');
    });
  });
}
