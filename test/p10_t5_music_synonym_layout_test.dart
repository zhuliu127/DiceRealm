// ============================================================
// test/p10_t5_music_synonym_layout_test.dart — P10 第 5 期（A/B/C）
//
// A · 音乐控制台真播放：切场景「先停旧再播新」的行为级证据、零叠播、
//     空插槽只停不播、播放/暂停/停止/释放全经端口、配置落本机、
//     KP 房间内快捷入口按 gate 只给 KP、零发包 / 零状态 / 零存档。
// B · 缩放按钮加标题 + 一行排布：多档宽度下 5 个百分比按钮 top 相等、
//     工具栏可见标题、退回竖排/去掉标题的反向锚点。
// C · 组技能子类独立近义词：8 组全部子类行覆盖、搜「手枪 / pistol」命中
//     射击（手枪）、不污染、组级/子级分层、上批 54/54 与原有能力零回归。
//
// ★ T1：widget 用例全用 RoomUiFixture 内存后端 + FakeMusicPort，零真实 I/O；
//   纯逻辑用例用 `await Future<void>.value()` 推进微任务（不引 Timer）。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io' show File;

import 'package:dice_realm/domain/data/skills.dart' show cocSkills;
import 'package:dice_realm/domain/js_compat.dart'
    show asList, asMap, jsStr, jsTruthy;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/domain/skill_subskill_synonyms.dart'
    show
        allSpecialSubskillRows,
        allSubskillWords,
        skillSubskillSynonyms,
        subskillSynonymsOf,
        uncoveredSubskillRows;
import 'package:dice_realm/domain/skill_synonyms.dart'
    show
        skillSynonymIdOf,
        skillSynonyms,
        synonymOwnersOf,
        synonymsOf;
import 'package:dice_realm/ui/create/skill_groups.dart'
    show skillMatchesKeyword;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_music_controller.dart'
    show MusicConsoleController, MusicPlayState;
import 'package:dice_realm/ui/room/room_music_ports.dart'
    show MusicPort, MusicSlot, kMusicScenes, musicPort;
import 'package:dice_realm/ui/room/room_ui_local.dart' show RoomUiLocal;
import 'package:dice_realm/ui/room/sheets/sheet_misc.dart'
    show MiscSheet, MiscSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_music.dart' show MusicSheetKeys;
import 'package:dice_realm/ui/room/widgets/gp_toolbar.dart' show GpToolbarKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_fakes.dart';
import 'support/room_ui_harness.dart';

/// 让 `Future.value(...).then(...)` 的回调跑完（纯 test 用真实 async，安全）。
Future<void> _microtasks() async {
  await Future<void>.value();
  await Future<void>.value();
}

/// 造一个「5 个场景全配置好」的端口，方便切场景行为级用例。
FakeMusicPort _fullySeeded() {
  final fake = FakeMusicPort();
  for (final s in kMusicScenes) {
    fake.seed(
      s.id,
      MusicSlot(
        relPath: 'music/${s.id}.mp3',
        displayName: '${s.label}_${s.id}.mp3',
      ),
    );
  }
  return fake;
}

Future<MusicConsoleController> _controller(FakeMusicPort fake) async {
  final c = MusicConsoleController(port: fake);
  c.init();
  await _microtasks();
  return c;
}

/// 复刻 `makeSkill`（第一个搜索框：有 id / key / sub / name）。
Map<String, Object?> _defShape(String id, {String sub = ''}) {
  final def = cocSkills.firstWhere((s) => jsStr(s['id']) == id);
  final name = jsStr(def['name']);
  return <String, Object?>{
    'key': sub.isEmpty ? id : '$id::$sub',
    'id': id,
    'name': sub.isEmpty ? name : '$name（$sub）',
    'sub': sub,
    'desc': '',
  };
}

/// 复刻 `step_skills.dart:1015-1040` 的任选技能弹窗形状（无 id 键）。
Map<String, Object?> _pickerShape(String id, {String sub = ''}) {
  final def = cocSkills.firstWhere((s) => jsStr(s['id']) == id);
  final name = jsStr(def['name']);
  return <String, Object?>{
    'skill': id,
    'sub': sub.isEmpty ? null : sub,
    'name': sub.isEmpty ? name : '$name（$sub）',
  };
}

/// 第二个搜索框的**全量**选项（8 组子类行 + 46 条普通技能）。
List<Map<String, Object?>> _allPickerOptions() {
  final out = <Map<String, Object?>>[];
  for (final s in cocSkills) {
    if (jsTruthy(s['special'])) {
      for (final raw in asList(s['subskills'])) {
        final nm = jsStr(asMap(raw)['name']);
        out.add(<String, Object?>{
          'skill': s['id'],
          'sub': nm,
          'name': '${jsStr(s['name'])}（$nm）',
        });
      }
    } else {
      out.add(<String, Object?>{
        'skill': s['id'],
        'sub': null,
        'name': s['name'],
      });
    }
  }
  return out;
}

/// 搜某关键词，返回全量选项里命中的 `组id::子类名`。
List<String> _hits(String kw) => <String>[
      for (final o in _allPickerOptions())
        if (skillMatchesKeyword(o, kw))
          '${o['skill']}::${o['sub'] ?? ''}',
    ];

Widget _miscApp(RoomUiFixture f) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) =>
          f.scoped(kHostSeat, child: child ?? const SizedBox.shrink()),
      home: const Scaffold(body: SingleChildScrollView(child: MiscSheet())),
    );

void main() {
  // ★ 必须在任何注入之前捕获生产端口（顶层 final 延迟初始化会拿到 fake）。
  final MusicPort systemPort = musicPort;

  // ========================================================
  // A · 音乐控制台真播放
  // ========================================================
  group('A · 音乐控制台真播放（纯本机 / 切场景停旧）', () {
    test('A1 ★ 切场景：stop 严格早于 play、零叠播、只有一条流', () async {
      final fake = _fullySeeded();
      final c = await _controller(fake);
      expect(c.loaded, isTrue, reason: '前置：本机配置已加载');

      c.switchScene('daily');
      final stopAt = fake.firstIndexOf('stop');
      final playAt = fake.firstIndexOf('play:');
      expect(stopAt, greaterThanOrEqualTo(0), reason: '切场景必须显式停旧');
      expect(playAt, greaterThan(stopAt),
          reason: '★ stop 必须发生在 play 之前（旧曲不许和新曲叠播）');
      expect(fake.lastPlayPath, 'music/daily.mp3');
      expect(fake.overlaps, 0, reason: '★ 任一时刻只有一条流在播');
      expect(fake.activeStreams, 1);
      expect(c.state, MusicPlayState.playing);
      expect(c.statusText, '播放中 · 日常 · 日常_daily.mp3');

      // 第二次切场景：整段调用序列恰好是 stop → play（不多不少）。
      final before = fake.calls.length;
      c.switchScene('combat');
      expect(fake.calls.sublist(before), <String>['stop', 'play:music/combat.mp3']);
      expect(fake.overlaps, 0);
      expect(fake.activeStreams, 1);
      expect(c.statusText, contains('战斗'));
    });

    test('A2 ★ 空插槽切场景 = 停旧的、不播新的', () async {
      final fake = FakeMusicPort();
      fake.seed('daily',
          const MusicSlot(relPath: 'music/daily.mp3', displayName: 'd.mp3'));
      final c = await _controller(fake);

      c.switchScene('daily');
      expect(fake.activeStreams, 1);

      final before = fake.calls.length;
      c.switchScene('suspense'); // 未配置
      expect(fake.calls.sublist(before), <String>['stop'],
          reason: '★ 空插槽：只停旧的，绝不播新的');
      expect(fake.activeStreams, 0);
      expect(c.state, MusicPlayState.stopped);
      expect(c.statusText, startsWith('已停止'));
      expect(c.statusText, contains('悬疑'));
      expect(c.notice, contains('未配置'));
    });

    test('A3 播放 / 暂停 / 停止 / release 全经端口，状态文本如实', () async {
      final fake = _fullySeeded();
      final c = await _controller(fake);

      expect(c.statusText, contains('未播放'));
      c.selectScene('combat');
      c.play();
      expect(fake.lastPlayPath, 'music/combat.mp3');
      expect(c.statusText, '播放中 · 战斗 · 战斗_combat.mp3');

      c.pause();
      expect(fake.calls.contains('pause'), isTrue);
      expect(c.statusText, startsWith('已暂停'));
      expect(c.state, MusicPlayState.paused);

      c.stop();
      expect(fake.calls.contains('stop'), isTrue);
      expect(c.statusText, startsWith('已停止'));
      expect(fake.activeStreams, 0);

      c.releasePlayer();
      expect(fake.calls.contains('release'), isTrue);
      expect(c.statusText, contains('未播放'));
    });

    test('A4 选文件真的写本机配置；取消给真提示、不造假状态', () async {
      final fake = FakeMusicPort();
      final c = await _controller(fake);

      c.pickFor('daily');
      await _microtasks();
      expect(fake.calls.contains('import:daily'), isTrue);
      expect(fake.saveCalls, 1, reason: '配置必须落本机');
      expect(fake.saved.containsKey('daily'), isTrue);
      expect(c.slotOf('daily').configured, isTrue);
      expect(c.notice, contains('已绑定'));
      expect(c.activeSceneId, 'daily');

      // 用户取消：槽位保持未配置，且给真提示（不是「点了没反应」）。
      fake.importReturnsNull = true;
      c.pickFor('explore');
      await _microtasks();
      expect(c.slotOf('explore').configured, isFalse,
          reason: '取消不许写成一个「有音频」的假状态');
      expect(c.notice, contains('没有选到音频'));
    });

    test('A5 没选定 / 没配置时点播放：给真提示，不许点了没反应', () async {
      final fake = FakeMusicPort();
      final c = await _controller(fake);

      final before = fake.calls.length;
      c.play();
      expect(fake.calls.length, before, reason: '没选中时不该乱播');
      expect(c.notice, contains('请先点一个场景'));

      c.selectScene('combat'); // 该场景未配置
      c.play();
      expect(fake.calls.length, before);
      expect(c.notice, contains('还没有绑定音频'));
    });

    testWidgets('A6 KP 房间内快捷入口只给 KP，点开切场景零发包',
        (WidgetTester tester) async {
      final fake = _fullySeeded();
      musicPort = fake;
      addTearDown(() => musicPort = systemPort);

      final f = RoomUiFixture();
      await f.boot(inGame: true);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 900, 2400);
      await tester.pumpWidget(f.pageOf(kHostSeat));
      await tester.pump();

      final finder = find.byKey(MusicSheetKeys.roomSceneQuick);
      expect(finder, findsOneWidget, reason: 'KP 房间内必须有可见入口');
      final btn = tester.widget<RoomTap>(finder);
      expect(btn.enabled, isTrue);
      expect(btn.onTap, isNotNull);

      final sentBefore = f.sent.length;
      final stateBefore = jsonEncode(f.stateOf(kHostSeat));
      final saveBefore = f.saves
          .list()
          .map((String c) => jsonEncode(f.saves.get(c)))
          .join('|');

      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(MusicSheetKeys.quickRoot), findsOneWidget,
          reason: '5 个场景键收进弹层，避免挤爆自适应高度工具栏');
      for (final s in kMusicScenes) {
        expect(find.byKey(MusicSheetKeys.quickScene(s.id)), findsOneWidget);
      }

      await tester.tap(find.byKey(MusicSheetKeys.quickScene('combat')));
      await tester.pump();
      expect(fake.calls.contains('stop'), isTrue);
      expect(fake.firstIndexOf('play:'), greaterThan(fake.firstIndexOf('stop')));
      expect(fake.overlaps, 0);

      // ★ 音乐纯本机：零发包、零房间状态、零存档。
      expect(f.sent.length, sentBefore, reason: '★★ 选文件/切场景/播放都不发 intent');
      expect(jsonEncode(f.stateOf(kHostSeat)), stateBefore,
          reason: '★★ 不进房间 state');
      expect(
        f.saves.list().map((String c) => jsonEncode(f.saves.get(c))).join('|'),
        saveBefore,
        reason: '★★ 不进存档',
      );
    });

    testWidgets('A7 玩家 / 旁观视角结构上不渲染 KP 的 BGM 场景入口',
        (WidgetTester tester) async {
      final fake = _fullySeeded();
      musicPort = fake;
      addTearDown(() => musicPort = systemPort);

      final f = RoomUiFixture();
      await f.boot(inGame: true);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 900, 2400);

      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();
      expect(find.byKey(MusicSheetKeys.roomSceneQuick), findsNothing);

      await tester.pumpWidget(f.spectatorPage('sp1'));
      await tester.pump();
      expect(find.byKey(MusicSheetKeys.roomSceneQuick), findsNothing);
    });
  });

  // ========================================================
  // B · 缩放按钮标题 + 一行排布
  // ========================================================
  group('B · 缩放按钮标题 / 一行排布几何', () {
    testWidgets('B1 多档宽度下 5 个百分比按钮确实同一行 + 标题/说明可见',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);

      for (final w in <double>[320, 360, 480, 700, 900]) {
        useRoomScreen(tester, w, 2400);
        await tester.pumpWidget(_miscApp(f));
        await tester.pump();

        // ★ 反向锚点：这一行必须是 Wrap（退回竖排 Column 这条就红）。
        expect(tester.widget(find.byKey(MiscSheetKeys.zoomRow)), isA<Wrap>(),
            reason: '宽度 $w：缩放档位不许退回一行一个的竖排');
        final tops = <double>[
          for (final pct in RoomUiLocal.zoomSteps)
            tester.getRect(find.byKey(MiscSheetKeys.zoom(pct))).top,
        ];
        expect(tops.toSet(), hasLength(1),
            reason: '宽度 $w 下 5 个档位不在同一行：$tops');

        // ★ 反向锚点：可见标题 + 可见说明（删掉任一处这条就红）。
        expect(find.text('界面缩放'), findsOneWidget);
        expect(find.byKey(MiscSheetKeys.zoomHint), findsOneWidget);
        final hint = tester.widget<Text>(find.byKey(MiscSheetKeys.zoomHint));
        expect(hint.data, contains('百分比按钮'));
        expect(hint.data, contains('缩放'));
      }
    });

    testWidgets('B2 工具栏缩放组保持紧凑自适应（本批零改动、不挤爆）',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 900, 2400);
      await tester.pumpWidget(f.pageOf(kHostSeat));
      await tester.pump();

      // ★ 工具栏本批逐字节未改（哈希见报告）。这组只有一个循环百分比按钮
      //   + 重置，不是用户说的「几个百分比数字」；它已经靠 Tooltip 说清是缩放。
      final zoom =
          tester.widget<RoomTap>(find.byKey(GpToolbarKeys.zoomPercent));
      expect(zoom.label, contains('%'));
      expect(zoom.hint, contains('缩放'),
          reason: 'Tooltip 里必须写清这是缩放档位切换');
      expect(zoom.onTap, isNotNull);
      // 按钮组仍是单个 Wrap（自适应高度，不退回一行一个的竖排）。
      expect(tester.widget(find.byKey(GpToolbarKeys.quickRow)), isA<Wrap>());
    });

    test('B3 同类按钮扫查锚点：缩放区是 Wrap + 紧凑间距，工具栏有标题', () {
      final misc =
          File('lib/ui/room/sheets/sheet_misc.dart').readAsStringSync();
      expect(misc.contains('key: MiscSheetKeys.zoomRow,'), isTrue);
      expect(misc.contains('spacing: 3,'), isTrue);
      expect(misc.contains('Size(54, 34)'), isTrue);
      expect(misc.contains("'下面这排百分比按钮用来缩放界面"), isTrue);

      final toolbar =
          File('lib/ui/room/widgets/gp_toolbar.dart').readAsStringSync();
      // ★ 工具栏本批零改动：仍是 Wrap + 循环百分比按钮 + Tooltip 说明。
      expect(toolbar.contains("'点按切换缩放档位"), isTrue);
      expect(toolbar.contains('Wrap('), isTrue);
      expect(toolbar.contains('zoomLabel'), isFalse,
          reason: '实测加可见标签会打穿 S2.4，已撤回（见报告扫查表）');

      // 扫查结论（详见 _p10_transport7.txt 的「按钮扫查表」）：其余
      // RoomTap 竖排组都是「每行带独立数据、行数随人数/物品数变化」的高
      // 密度列表，或语义上必须竖排的确认动作，本批**不动**。这里只钉住
      // 杂项弹层那处确属低密度、已加说明并压成一行的位置，防后续回退。
    });
  });

  // ========================================================
  // C · 组技能子类独立近义词
  // ========================================================
  group('C · 组技能子类独立近义词（只服务搜索）', () {
    test('C1 ★ 覆盖 8 条 special 的全部子类行，两种搜索框形状都非空', () {
      final rows = allSpecialSubskillRows();
      expect(rows.length, greaterThanOrEqualTo(85),
          reason: '生成数据里 8 组子类行应约 85 条');
      expect(skillSubskillSynonyms.length, 8);
      expect(uncoveredSubskillRows(), isEmpty,
          reason: '不许只给几个常用子类加，必须逐行覆盖');
      // 表里的条目数恰好等于生成数据的子类行数（防多余 / 防遗漏）。
      final tableRows = skillSubskillSynonyms.values
          .fold<int>(0, (int n, Map<String, List<String>> g) => n + g.length);
      expect(tableRows, rows.length);

      for (final row in rows) {
        final i = row.indexOf('::');
        final groupId = row.substring(0, i);
        final sub = row.substring(i + 2);
        expect(subskillSynonymsOf(_defShape(groupId, sub: sub)), isNotEmpty,
            reason: '第一搜索框形状 $row');
        expect(subskillSynonymsOf(_pickerShape(groupId, sub: sub)), isNotEmpty,
            reason: '第二搜索框形状 $row');
      }
    });

    test('C2 ★ 正例：搜「手枪」命中射击（手枪），专属近义词也命中', () {
      final def = _defShape('firearms', sub: '手枪');
      final picker = _pickerShape('firearms', sub: '手枪');
      expect(skillMatchesKeyword(def, '手枪'), isTrue);
      expect(skillMatchesKeyword(picker, '手枪'), isTrue);
      // 子类独立近义词带来的**新**能力
      expect(skillMatchesKeyword(def, 'pistol'), isTrue);
      expect(skillMatchesKeyword(def, '短枪'), isTrue);
      expect(skillMatchesKeyword(picker, 'handgun'), isTrue);
      // 反向：没有这张表时 'pistol' 在原始字段里根本不存在
      expect(_rawFieldsOf(def).any((String f) => f.contains('pistol')), isFalse,
          reason: '前置：pistol 不在 name/id/sub/desc/组级近义词里');
    });

    test('C3 ★ 不污染：子类近义词不把别的组 / 别的子类带出来', () {
      expect(_hits('pistol'), <String>['firearms::手枪']);
      expect(_hits('短枪'), <String>['firearms::手枪']);
      expect(_hits('拳脚'), <String>['fighting::斗殴']);
      expect(_hits('堪舆'), <String>['art_craft::风水']);
      expect(_hits('法医'), <String>['science::司法科学']);
      expect(_hits('necronomicon'), <String>['lore::《死灵之书》学识']);

      // 组级近义词仍是组级语义：搜「魅惑」只带出 charm，不被子类表污染。
      expect(_hits('魅惑'), <String>['charm::']);
      for (final id in <String>['fast_talk', 'persuade', 'intimidate']) {
        expect(skillMatchesKeyword(_pickerShape(id), 'pistol'), isFalse);
      }
    });

    test('C4 ★ 分层：三级回退只解析组 id，两级词零交集、子级词零重复', () {
      final row = _pickerShape('firearms', sub: '手枪');
      expect(skillSynonymIdOf(row), 'firearms');
      expect(synonymsOf(row), skillSynonyms['firearms'],
          reason: '组级表语义一字未动');
      expect(synonymsOf(row).contains('pistol'), isFalse);
      expect(subskillSynonymsOf(row).contains('pistol'), isTrue);
      for (final w in subskillSynonymsOf(row)) {
        expect(synonymsOf(row).contains(w), isFalse,
            reason: '子类词 $w 不该出现在组级表');
      }
      // 全表分层零交集
      final groupWords = <String>{
        for (final list in skillSynonyms.values) ...list,
      };
      final subWords = allSubskillWords();
      for (final w in subWords) {
        expect(groupWords.contains(w), isFalse,
            reason: '分层不串：$w 同时出现在两级表');
      }
      // 子级词表内零重复（否则搜 A 会串到 B）
      expect(subWords.toSet().length, subWords.length,
          reason: '子类近义词不能重复');
    });

    test('C5 上批 54/54 与原有能力一条不回归', () {
      expect(cocSkills, hasLength(54));
      for (final s in cocSkills) {
        final id = jsStr(s['id']);
        expect(skillSynonyms.containsKey(id), isTrue, reason: '$id 缺组级近义词');
        expect(skillSynonyms[id], isNotEmpty);
      }
      expect(skillSynonyms.length, 54);
      expect(synonymOwnersOf('魅'), <String>['charm']);
      expect(synonymOwnersOf('惑'), <String>['charm']);
      // 取悦 ↔ 魅惑，两种搜索框形状
      expect(skillMatchesKeyword(_defShape('charm'), '魅惑'), isTrue);
      expect(skillMatchesKeyword(_pickerShape('charm'), '魅惑'), isTrue);
      expect(skillMatchesKeyword(_defShape('charm'), '取悦'), isTrue);
      // 原有模糊能力
      expect(skillMatchesKeyword(_defShape('spot_hidden'), '侦'), isTrue);
      expect(skillMatchesKeyword(_defShape('spot_hidden'), 'spot'), isTrue);
      expect(skillMatchesKeyword(_defShape('library'), '图书使'), isTrue);
      expect(skillMatchesKeyword(_pickerShape('charm'), '讨好'), isTrue);
      expect(skillMatchesKeyword(_defShape('spot_hidden'), '这技能不存在'),
          isFalse);
      // 三级回退对 8 组子类行仍能解析出组 id
      for (final d in cocSkills.where((x) => jsTruthy(x['special']))) {
        for (final raw in asList(d['subskills'])) {
          final nm = jsStr(asMap(raw)['name']);
          expect(
            skillSynonymIdOf(<String, Object?>{
              'skill': d['id'],
              'sub': nm,
              'name': '${jsStr(d['name'])}（$nm）',
            }),
            jsStr(d['id']),
            reason: '${jsStr(d['id'])}::$nm',
          );
        }
      }
    });

    test('C6 子类近义词不进任何渲染文本（结构上只服务搜索）', () {
      final groups =
          File('lib/ui/create/skill_groups.dart').readAsStringSync();
      // 调用点唯一，且落在 skillMatchesKeyword 的局部 fields 列表里。
      expect(
        groups.split('...subskillSynonymsOf(skill),').length - 1,
        1,
        reason: '调用点唯一，且只在 fields 局部列表里',
      );
      final fieldsAt = groups.indexOf('final fields = <String>[');
      final callAt = groups.indexOf('...subskillSynonymsOf(skill),');
      expect(fieldsAt, greaterThanOrEqualTo(0));
      expect(callAt, greaterThan(fieldsAt));
      expect(callAt, lessThan(groups.indexOf('];', fieldsAt)));

      // 两个搜索框的 UI 文件里绝不引用子级表（不会把它写进 Text / hint）。
      final step = File('lib/ui/create/steps/step_skills.dart')
          .readAsStringSync();
      expect(step.contains('subskillSynonymsOf'), isFalse);
      expect(step.contains('skillSubskillSynonyms'), isFalse);

      // GENERATED 的技能数据一字未改：正式子类名仍在，且没有新增任何英文
      // 近义词字段。
      final skills =
          File('lib/domain/data/skills.dart').readAsStringSync();
      expect(skills.contains("'name': '手枪'"), isTrue);
      expect(skills.contains('pistol'), isFalse);
      expect(skills.contains('GENERATED FILE'), isTrue);
    });
  });
}

/// 只取 `skillMatchesKeyword` 里除子类表以外的原始字段（C2 前置断言用）。
List<String> _rawFieldsOf(Map<String, Object?> skill) => <String>[
      jsStr(skill['name']),
      jsStr(skill['id']),
      jsStr(skill['sub']),
      jsStr(skill['desc']),
      ...synonymsOf(skill),
    ];
