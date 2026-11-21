// ============================================================
// sheet_music_test.dart — 音乐控制台（PRD P2-03 / P10 第 5 期 A）
//
// ★ 本批是**口径更新**：上批面板是「依赖冻结、无播放器、不放假按钮」的
//   纯说明面板；用户已拍板解锁音频插件，现在是真播放器 + 5 场景插槽。
//   因此把过时断言（noFakeButton / 「没有内置播放器」/「点了没反应」/
//   「后台播放」/「如实说明」面板 / 结构上不许有 RoomTap）**改写成新口径
//   的正向断言**，而不是删用例、改成永真或 skip：
//     · 确有选文件 / 播放 / 暂停 / 停止按钮，且可点、点了 Fake 记到调用；
//     · 确有 5 个场景插槽 + 5 个场景快捷键；
//     · 切场景必停旧（stop 早于 play、零叠播）；
//     · 状态真实反映播放态 + 场景 + 文件名；
//     · 仍不打包音频 / 不联网 / 不同步 / 零发包 / 不进状态 / 不进存档。
//   「不放假按钮」精神保留：按钮可点且点了有真实行为。
//
// ★ T1：widget 用例全用 RoomUiFixture 的内存后端 + FakeMusicPort，零文件 I/O。
// ★ 弹层统一走 showRoomSheet，用 pump(Duration) 推进转场（不是真实 Timer）。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File;

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:dice_realm/ui/room/room_music_ports.dart'
    show MusicPort, MusicSlot, kMusicScenes, musicPort;
import 'package:dice_realm/ui/room/sheets/sheet_kp_panel.dart'
    show KpPanel, KpPanelKeys;
import 'package:dice_realm/ui/room/sheets/sheet_misc.dart'
    show MiscSheet, MiscSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_music.dart'
    show MusicSheetKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_fakes.dart';
import 'support/room_ui_harness.dart';

/// 宿主：RoomScope 套在 Navigator 外层，弹层里才找得到作用域（showRoomSheet 口径）。
Widget _scopedApp(RoomUiFixture f, Widget body) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) =>
          f.scoped(kHostSeat, child: child ?? const SizedBox.shrink()),
      home: Scaffold(body: SingleChildScrollView(child: body)),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

/// 弹层内某个 key 上的纯文本。
String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

/// 先滚到可见再点（弹层内容可能超过可视高度）。
Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump();
}

String _saveSnapshot(RoomUiFixture f) => f.saves
    .list()
    .map((String code) => '$code=${jsonEncode(f.saves.get(code))}')
    .join('|');

void main() {
  // ★ 必须在 setUp 注入之前捕获生产端口：顶层 final 是延迟初始化，
  //   若拖到 tearDown 才第一次读，拿到的会是被替换后的 fake。
  final MusicPort systemPort = musicPort;
  late FakeMusicPort fake;

  setUp(() {
    fake = FakeMusicPort(
      seedSlots: <String, MusicSlot>{
        'combat': const MusicSlot(
          relPath: 'music/combat.mp3',
          displayName: 'battle.mp3',
        ),
      },
    );
    musicPort = fake;
    addTearDown(() => musicPort = systemPort);
  });

  group('P2-03 · 音乐控制台入口', () {
    testWidgets('★ 入口真实可达：可点、有回调、不再写「下一期」',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);

      // ★ P17 KP-8：音乐入口从二级「更多工具」上移一级「KP 工具」
      //   （`KpPanelKeys.music`）。旧 key `MiscSheetKeys.musicEntry` 保留但
      //   不再渲染 —— 在更多工具宿主里断言 findsNothing（防回退）。
      await tester.pumpWidget(_scopedApp(f, const KpPanel()));
      await _settle(tester);

      final entry = tester.widget<RoomTap>(find.byKey(KpPanelKeys.music));
      expect(entry.enabled, isTrue,
          reason: '★ 恒 false 的禁用按钮 = 假入口，P2-03 已经是真入口');
      expect(entry.onTap, isNotNull, reason: '可点却没回调 = 点了没反应');
      expect(entry.hint, isNot(contains('下一期')));
      expect(entry.hint, isNot(contains('后续版本')));
      expect(entry.hint, contains('本机'));

      // ★ P17 KP-8（更强）：更多工具宿主里不再渲染音乐入口。
      await tester.pumpWidget(_scopedApp(f, const MiscSheet()));
      await _settle(tester);
      expect(find.byKey(MiscSheetKeys.musicEntry), findsNothing,
          reason: '音乐入口已上移，「更多工具」里不该再渲染');
    });

    testWidgets(
        '★ 新口径：真播放器 / 5 插槽 / 播放暂停停止可点且有真实行为 / 切场景停旧',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);

      await tester.pumpWidget(_scopedApp(f, const KpPanel()));
      await _settle(tester);

      await _tapKey(tester, KpPanelKeys.music);
      await _settle(tester);

      // ① 仍适用的旧 key 一个不少，且都有实际内容。
      expect(find.byKey(MusicSheetKeys.root), findsOneWidget,
          reason: '★ 点开必须有实际内容，不是空弹层');
      for (final k in <Key>[
        MusicSheetKeys.localOnly,
        MusicSheetKeys.statusLabel,
        MusicSheetKeys.status,
        MusicSheetKeys.howtoLabel,
        MusicSheetKeys.howto,
        MusicSheetKeys.whyLabel,
        MusicSheetKeys.why,
      ]) {
        expect(find.byKey(k), findsOneWidget, reason: '$k 应有实际内容');
      }

      // ② 新口径正向断言：确有播放 / 暂停 / 停止三个**可点、有回调**的按钮。
      for (final k in <Key>[
        MusicSheetKeys.play,
        MusicSheetKeys.pause,
        MusicSheetKeys.stop,
      ]) {
        final tap = tester.widget<RoomTap>(find.byKey(k));
        expect(tap.enabled, isTrue, reason: '$k 不该是禁用假按钮');
        expect(tap.onTap, isNotNull, reason: '$k 可点却没回调 = 假按钮');
      }
      expect(find.byKey(MusicSheetKeys.controls), findsOneWidget);

      // ③ 确有 5 个场景插槽（每个都有显示/状态、选文件按钮）+ 5 个场景快捷键。
      expect(kMusicScenes, hasLength(5));
      expect(find.byKey(MusicSheetKeys.sceneQuickRow), findsOneWidget);
      expect(find.byKey(MusicSheetKeys.slotsLabel), findsOneWidget);
      for (final s in kMusicScenes) {
        expect(find.byKey(MusicSheetKeys.slot(s.id)), findsOneWidget,
            reason: '${s.label} 插槽行');
        expect(find.byKey(MusicSheetKeys.slotName(s.id)), findsOneWidget);
        expect(find.byKey(MusicSheetKeys.slotState(s.id)), findsOneWidget);
        final pick = tester.widget<RoomTap>(find.byKey(MusicSheetKeys.pick(s.id)));
        expect(pick.enabled, isTrue, reason: '${s.label} 选文件按钮要真可点');
        expect(pick.onTap, isNotNull);
        expect(find.byKey(MusicSheetKeys.scene(s.id)), findsOneWidget);
      }
      // 已配置 / 未配置 状态如实上屏
      expect(_text(tester, MusicSheetKeys.slotState('combat')),
          contains('已配置'));
      expect(_text(tester, MusicSheetKeys.slotState('daily')),
          contains('未配置'));

      // ④ 状态真实反映播放态（初始 = 未播放 + 尚未选定场景）。
      expect(_text(tester, MusicSheetKeys.status), contains('未播放'));
      expect(_text(tester, MusicSheetKeys.status), contains('尚未选定场景'));

      // ⑤ 本机边界一字未删：不打包 / 不联网 / 不同步 / 自备。
      final local = _text(tester, MusicSheetKeys.localOnly);
      expect(local.contains('不联网'), isTrue);
      expect(local.contains('不同步'), isTrue);
      expect(local.contains('不打包任何音频'), isTrue);
      expect(_text(tester, MusicSheetKeys.howto).contains('自备'), isTrue);
      expect(_text(tester, MusicSheetKeys.why).contains('不打包音频'), isTrue);
      expect(_text(tester, MusicSheetKeys.why).contains('不联网'), isTrue);

      // ⑥ 不放假话：旧口径那几句「没有播放器 / 点了没反应 / 后台播放 /
      //    后台说明面板」以及假成功措辞全都不该再出现。
      final all = <String>[
        _text(tester, MusicSheetKeys.status),
        local,
        _text(tester, MusicSheetKeys.howto),
        _text(tester, MusicSheetKeys.why),
        _text(tester, MusicSheetKeys.notice),
      ].join('\n');
      for (final banned in <String>[
        '下一期',
        '后续版本',
        '已播放',
        '播放成功',
        '没有内置播放器',
        '点了没反应',
        '后台播放',
        '如实说明面板',
      ]) {
        expect(all.contains(banned), isFalse, reason: '不许再宣称 $banned');
      }

      // ⑦ ★ 按钮点了有真实行为：切场景 → Fake 记到 stop 严格早于 play、零叠播。
      await _tapKey(tester, MusicSheetKeys.scene('combat'));
      expect(fake.calls.contains('stop'), isTrue, reason: '切场景必须先停旧');
      final stopAt = fake.firstIndexOf('stop');
      final playAt = fake.firstIndexOf('play:');
      expect(stopAt, greaterThanOrEqualTo(0));
      expect(playAt, greaterThan(stopAt), reason: '★ stop 必须发生在 play 之前');
      expect(fake.overlaps, 0, reason: '★ 任一时刻只有一条流在播');
      expect(fake.activeStreams, 1);
      expect(fake.lastPlayPath, 'music/combat.mp3');

      final playing = _text(tester, MusicSheetKeys.status);
      expect(playing.contains('播放中'), isTrue);
      expect(playing.contains('战斗'), isTrue, reason: '状态要带当前场景');
      expect(playing.contains('battle.mp3'), isTrue, reason: '状态要带文件名');

      // ⑧ 暂停 / 停止 / 播放 三个按钮各自真的驱动端口。
      await _tapKey(tester, MusicSheetKeys.pause);
      expect(fake.calls.contains('pause'), isTrue);
      expect(_text(tester, MusicSheetKeys.status).contains('已暂停'), isTrue);

      await _tapKey(tester, MusicSheetKeys.stop);
      expect(fake.countOf('stop'), greaterThanOrEqualTo(2));
      expect(_text(tester, MusicSheetKeys.status).contains('已停止'), isTrue);
      expect(fake.activeStreams, 0);

      await _tapKey(tester, MusicSheetKeys.play);
      expect(fake.countOf('play:'), greaterThanOrEqualTo(2));
      expect(_text(tester, MusicSheetKeys.status).contains('播放中'), isTrue);

      // ⑨ 选文件按钮真的去选了、并把配置写回本机持久化。
      await _tapKey(tester, MusicSheetKeys.pick('daily'));
      expect(fake.calls.contains('import:daily'), isTrue);
      expect(fake.saveCalls, greaterThanOrEqualTo(1), reason: '配置必须落本机');
      expect(fake.saved.containsKey('daily'), isTrue);
      expect(_text(tester, MusicSheetKeys.slotState('daily')),
          contains('已配置'));
    });

    testWidgets('★★ 纯本机：零发包 / 零房间状态 / 零存档 / 零假成功提示',
        (WidgetTester tester) async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);

      await tester.pumpWidget(_scopedApp(f, const KpPanel()));
      await _settle(tester);

      final sentBefore = f.sent.length;
      final seqBefore = f.sessionOf(kHostSeat).lastSeq;
      final stateBefore = jsonEncode(f.stateOf(kHostSeat));
      final noticeBefore = f.localOf(kHostSeat).notice;
      final saveBefore = _saveSnapshot(f);

      await _tapKey(tester, KpPanelKeys.music);
      await _settle(tester);
      expect(find.byKey(MusicSheetKeys.root), findsOneWidget,
          reason: '前置：这一步确实把弹层打开了');

      // 一整串纯本机动作：选文件 / 切场景 / 播放 / 暂停 / 停止。
      for (final key in <Key>[
        MusicSheetKeys.pick('daily'),
        MusicSheetKeys.scene('combat'),
        MusicSheetKeys.play,
        MusicSheetKeys.pause,
        MusicSheetKeys.stop,
      ]) {
        await _tapKey(tester, key);
      }
      expect(fake.calls, isNotEmpty, reason: '前置：这些动作真的发生了');

      expect(f.sent.length, sentBefore,
          reason: '★★ 音乐控制台绝不发 intent / action（纯本机）');
      expect(f.sessionOf(kHostSeat).lastSeq, seqBefore,
          reason: '★ 权威端序号没动 = 没有任何事件产生');
      expect(jsonEncode(f.stateOf(kHostSeat)), stateBefore,
          reason: '★★ 房间状态必须一字未改');
      expect(f.localOf(kHostSeat).notice, noticeBefore,
          reason: '★ 也不许弹「已播放」之类假成功提示');
      expect(_saveSnapshot(f), saveBefore,
          reason: '★★ 场景插槽配置走独立本机文件，绝不进房间存档');
    });
  });

  group('P2-03 · 静态口径（防回退 / 防假入口）', () {
    test('音乐面板源码：零发包 / 零网络 / 零权威赋值，且确有真播放实现', () {
      final src = File('lib/ui/room/sheets/sheet_music.dart').readAsStringSync();
      for (final banned in <String>[
        'dart:io',
        'dart:ui',
        'http',
        'AiClient',
        'Clipboard',
        'sendIntent',
        'hostAction',
        'showDialog',
        'Timer',
        'Future.delayed',
        'AnimationController',
      ]) {
        expect(src.contains(banned), isFalse,
            reason: '音乐控制台是纯本机面板，不该出现 $banned');
      }
      expect(src.contains('showRoomSheet'), isTrue,
          reason: '弹层必须走统一入口');

      // ★ 新口径的**正向**断言（不是放宽）：真播放器、5 场景、真按钮、
      //   可注入端口都必须真在面板源码里，摘掉任一处这条就红。
      for (final needed in <String>[
        'MusicConsoleController',
        'MusicPort',
        'kMusicScenes',
        'MusicSheetKeys.play',
        'MusicSheetKeys.pause',
        'MusicSheetKeys.stop',
        'MusicSheetKeys.pick(',
        'MusicSheetKeys.scene(',
        'openMusicSceneQuickSheet',
      ]) {
        expect(src.contains(needed), isTrue,
            reason: '★ 新口径：$needed 必须真在面板里（不是把断言删了）');
      }
    });

    test('★ 全 room/ 代码里不再有「下一期 / 后续版本提供」的功能占位', () {
      // 只查**代码行**：注释里回顾这段历史是允许的，朴素 grep 会把注释
      // 也算上，那就成了自我实现的假红。按门禁同款口径剥掉 `//` 行注释。
      String codeOnly(String src) => src.split('\n').map((String line) {
            final i = line.indexOf('//');
            return i < 0 ? line : line.substring(0, i);
          }).join('\n');

      final files = Directory('lib/ui/room')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty, reason: '前置：确实扫到了源码文件');

      for (final f in files) {
        final src = codeOnly(f.readAsStringSync());
        for (final banned in <String>['下一期', '后续版本提供']) {
          expect(src.contains(banned), isFalse,
              reason: '${f.path} 的代码里仍写着「$banned」= 假占位');
        }
      }

      // 两处具体改动也要在：不是把入口一删了之。
      final misc =
          File('lib/ui/room/sheets/sheet_misc.dart').readAsStringSync();
      // ★ P16 P-2：「更多工具」弹层里的 AI RP 禁用指引件已整块删除
      //   （不是「只留指引的禁用件」了）。真正要守的不变量变成：
      //   · 本文件不含 AI RP 禁用件 / 不再有 `enabled: false` 的假按钮；
      //   · AI RP 真入口仍在输入行 / 角色卡（下面 `card` 那条 + 别处的 widget 级断言）。
      expect(misc.contains('MiscSheetKeys.aiEntry'), isFalse,
          reason: 'P-2：AI RP 禁用指引件已从「更多工具」弹层删除');
      expect(misc.contains('enabled: false'), isFalse,
          reason: 'P-2：本文件不该再有被永久禁用的假按钮');
      // ★ P17 KP-8：音乐入口上移到 KP 工具（更强：两个文件各断一侧）。
      expect(misc.contains('openMusicSheet'), isFalse,
          reason: 'KP-8：音乐入口已从「更多工具」移走');
      final kpPanel =
          File('lib/ui/room/sheets/sheet_kp_panel.dart').readAsStringSync();
      expect(kpPanel.contains('openMusicSheet'), isTrue,
          reason: 'KP-8：KP 工具里必须是真入口，不是删掉按钮');
      expect(kpPanel.contains('KpPanelKeys.music'), isTrue,
          reason: 'KP-8：稳定 key 必须保留（可点性 / 回调可测）');

      // ★ P17 C-1：角色卡的 AI RP 按钮已删（真入口在聊天输入行）。
      //   这条本意是「AI RP 不能一删了之」，真入口换到了 `gp_feeds.dart` 的
      //   `GpFeedsKeys.aiRp`（`room_ui_entry_test.dart` 另有 widget 级断言）。
      final card = File('lib/ui/room/widgets/gp_pl_char_card.dart')
          .readAsStringSync();
      expect(card.contains('GpPlCharCardKeys.aiBtn'), isTrue,
          reason: 'P17 C-1：key 常量保留（既有测试仍可编译），只是不再渲染');
      final feeds = File('lib/ui/room/widgets/gp_feeds.dart')
          .readAsStringSync();
      expect(feeds.contains('GpFeedsKeys.aiRp'), isTrue,
          reason: 'P17 C-1：AI RP 真入口在聊天输入行，必须仍在');
    });
  });
}
