// ============================================================
// test/room_ui_permission_test.dart — P5/T05-B2b · T-30 表驱动权限探针
//
// 核心不变式（一条，贯穿全部用例）：
//   **控件 `enabled` ⟺ `RoomController.gate.can(op)`**
//   `gate` 与 `kRoomPolicy` 同源（`room_controller.dart#RoomGate`），
//   所以这条等价同时钉住了「UI 可点性」与「POLICY 登记表」。
//
// 铁律：
//   · T1 全内存后端，零真实文件读写（源码扫描用同步读，不产生待完成 Future）；
//   · T5 房间页按真实档位 pump；
//   · T6 只看 `enabled` / 结构，不看文案；
//   · T8 三视角都用「该视角真收到的那份 state」建页面（`stateOf`）。
//
// 判据对应派工表：
//   ① 先枚举锚点：扫 `RoomKeys.action(op)` 的实际挂载点，产出 op → 位置表；
//   ② 每个已挂载 op × {KP, 玩家, 旁观}：`enabled == gate.can(op)`；
//   ③ 未挂载 op 不测，但报告「POLICY 61 条里哪些没有锚点」；
//   ④ `room.kick` 特殊：全部 kick 按钮的 enabled 集合恰好 == {gate.can}；
//   ⑤ 结构式断言：玩家 / 旁观下 KP 专属按钮 `findsNothing`（T-22 口径）；
//   ⑥ 反向验证（人工，见交付报告）：把某 op 写死 true → 本文件必须转红。
//
// ★ 屏幕尺寸取 900×2200：`ListView` / `Wrap` 只有进了可视区才会挂到元素树，
//   探针要读到**全部**按钮，故给一块足够高的画布。本文件不承担任何布局档位
//   断言（那些在 room_ui_shell_test / room_view_test 里）。
// ============================================================

import 'dart:io' show Directory, File;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart'
    show RoomMode, kHostSeat, kRoomPolicy;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_keys.dart' show RoomKeys;
import 'package:dice_realm/ui/room/room_lobby_page.dart'
    show RoomLobbyKeys, RoomLobbyPage;
import 'package:dice_realm/ui/room/sheets/sheet_combat.dart'
    show CombatSheet, CombatSheetKeys;
import 'package:dice_realm/ui/room/sheets/sheet_dice_tools.dart'
    show DiceToolsKeys, DiceToolsSheet;
import 'package:dice_realm/ui/room/sheets/sheet_kp_directives.dart'
    show KpDirectivesSheet;
import 'package:dice_realm/ui/room/sheets/sheet_kp_panel.dart' show KpPanel;
import 'package:dice_realm/ui/room/sheets/sheet_opposed.dart' show OpposedSheet;
import 'package:dice_realm/ui/room/sheets/sheet_scene.dart' show SceneSheet;
import 'package:dice_realm/ui/room/widgets/gp_map_stage.dart' show GpMapStage;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart'
    show RoomTap, SectionBox;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

// ------------------------------------------------------------
// 静态锚点扫描（同步读，零待完成 Future）
// ------------------------------------------------------------

/// 逐行剥离行内注释，换行保留 → 行号与原文一致。
String _stripComments(String src) {
  return src.split('\n').map((String line) {
    final int i = line.indexOf('//');
    return i < 0 ? line : line.substring(0, i);
  }).join('\n');
}

/// 字符下标 → 1 基行号。
int _lineOf(String src, int index) {
  var n = 1;
  for (var i = 0; i < index && i < src.length; i += 1) {
    if (src.codeUnitAt(i) == 0x0A) n += 1;
  }
  return n;
}

/// 一张锚点表：`op → ['文件:行', ...]`。
///
/// 解析四类实参（`RoomKeys.action(...)` 的全部写法）：
///   · `'lit'`       —— 字面量，直接取；
///   · `widget.op`   —— `KpDangerAction` 的 `op` 字段，取值来自其调用点的 `op: 'x'`；
///   · `op`          —— `sheet_kp_panel.dart` 的 `_action()` 辅助方法，同上；
///   · `d.op`        —— KP 定向指令表 `KpDirective(op: 'x')` 的常量。
Map<String, List<String>> scanAnchors() {
  final List<File> files = Directory('lib/ui/room')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  final Map<String, String> srcByFile = <String, String>{};
  for (final File f in files) {
    srcByFile[f.path.replaceAll(r'\', '/')] = _stripComments(f.readAsStringSync());
  }

  // 第一遍：收齐三类动态实参的取值来源（op → 定义它的那些 `file:line`）。
  //
  // ★ 为什么保留定义点：`_action(op: …)` / `KpDangerAction(op: …)` /
  //   `KpDirective(op: …)` 这三种写法里，`act/<op>` 这个 key 都挂在**同一个**
  //   辅助/组件上，只有「调用点」才区分得开是哪个 op。把定义点一起打印出来，
  //   锚点表才对人有信息量（否则 7 个 op 会全部指向同一行）。
  final RegExp reDanger = RegExp(r"KpDangerAction\(\s*op:\s*'([^']+)'");
  final RegExp reHelper = RegExp(r"_action\(\s*op:\s*'([^']+)'");
  final RegExp reDirective = RegExp(r"KpDirective\(\s*op:\s*'([^']+)'");
  final Map<String, List<String>> dangerOps = <String, List<String>>{};
  final Map<String, List<String>> helperOps = <String, List<String>>{};
  final Map<String, List<String>> directiveOps = <String, List<String>>{};

  void collect(Map<String, List<String>> into, RegExp re, String file,
      String src) {
    for (final RegExpMatch m in re.allMatches(src)) {
      (into[m.group(1)!] ??= <String>[]).add('$file:${_lineOf(src, m.start)}');
    }
  }

  srcByFile.forEach((String file, String src) {
    collect(dangerOps, reDanger, file, src);
    collect(helperOps, reHelper, file, src);
    collect(directiveOps, reDirective, file, src);
  });

  // 第二遍：解析 `RoomKeys.action(<实参>)`。
  final RegExp reAction = RegExp(r'RoomKeys\.action\(\s*([^)]*?)\s*\)');
  final RegExp reLit = RegExp(r"^'([^']+)'$");
  final Map<String, List<String>> table = <String, List<String>>{};
  final List<String> unresolved = <String>[];

  void record(String op, String hit) {
    (table[op] ??= <String>[]).add(hit);
  }

  /// 动态实参：key 挂在这里，op 由调用点决定 → 两者都记。
  void recordDynamic(
    Map<String, List<String>> ops,
    String file,
    int line,
    String argText,
  ) {
    ops.forEach((String op, List<String> defs) {
      for (final String def in defs) {
        record(op, '$file:$line（$argText ← $def）');
      }
    });
  }

  srcByFile.forEach((String file, String src) {
    for (final RegExpMatch m in reAction.allMatches(src)) {
      final String arg = m.group(1)!.trim();
      final int line = _lineOf(src, m.start);
      final RegExpMatch? lit = reLit.firstMatch(arg);
      if (lit != null) {
        record(lit.group(1)!, '$file:$line');
      } else if (arg == 'widget.op') {
        recordDynamic(dangerOps, file, line, arg);
      } else if (arg == 'op') {
        recordDynamic(helperOps, file, line, arg);
      } else if (arg == 'd.op') {
        recordDynamic(directiveOps, file, line, arg);
      } else {
        unresolved.add('$file:$line arg=$arg');
      }
    }
  });

  // 未解析实参必须为空 —— 有的话说明源码新增了第五种写法，探针会漏测。
  expect(unresolved, isEmpty, reason: 'RoomKeys.action 出现未知实参写法：$unresolved');
  return table;
}

/// 冻结的「无 `RoomKeys.action` 锚点」清单（POLICY 61 − 有锚点 31 = 30）。
///
/// 这些 op 多数**另有专用 key 入口**（如 `room.kick` → `RoomLobbyKeys.kick`、
/// `room.start` → `RoomKeys.kpStartGame`、`asset.*` → `RoomLobbyKeys.asset*`、
/// `map.*` → `GpKpTools` 的画笔按钮），只是不走 `act/<op>` 这一族 key，
/// 所以不在 T-30 的表驱动射程内 —— 本清单把它显式化，防止「悄悄少测」。
const List<String> kFrozenNoAnchor = <String>[
  'asset.add',
  'asset.cover',
  'asset.del',
  'asset.reveal',
  'board.self',
  'char.share',
  'chat',
  'check.push',
  // ★ P17 KP-3：`combat.attack` 从「有锚点」迁到「无锚点」（快捷按钮删除，
  //   攻击对抗改走 `check.opposed {attack:true}`），链路与 POLICY 未动。
  'combat.attack',
  'combat.enqueue',
  'combat.prepare',
  'combat.set',
  // ★ 2.37.0 / Q4：骰子工具弹层删掉「暗骰设置」块，`act/dice.dark` 锚点随之
  //   消失（domain op / POLICY 条目未动）。显式申报清单**只增这一项**，
  //   不删任何既有项；暗骰能力仍由 `gp_dice_bar` 专用入口覆盖。这是收紧
  //   申报（少测的表驱动覆盖平移到专用 key 探针），不是放宽 FROZEN 数字。
  'dice.dark',
  'dice.request',
  'dice.roll',
  'item.del',
  'map.clear',
  'map.mark',
  'map.stroke',
  'map.strokes.set',
  'ready.set',
  'rollback.commit',
  'rollback.round',
  'room.kick',
  'room.resume',
  'room.start',
  'room.suspend',
  // ★ 2.36.0 / Q6：「下一回合」从 `sheet_kp_panel.dart` 的 `act/round.next`
  //   锚点扁平迁入工具栏 `RoomGamePage.nextRoundKey`（独立 ValueKey，
  //   绝不挂 `RoomKeys.action(...)`）。POLICY 条目与 domain 零改动 ⇒
  //   本清单**只增这一项、不删任何既有项**（显式申报清单的收紧，不是放宽
  //   `FROZEN` 数字门禁）。运行时等价由本文件 ② 新增的「专用 key 探针」
  //   三视角 + tap 真触发把丢失的表驱动覆盖**平移回来**。
  'round.next',
  // ★ P19：`save.share` 由 KP 端 `RoomSaveSyncer` 静默自动触发（每回合 /
  //   每 10 分钟 / 结束房间 / 结团 / 玩家加入），没有 UI 挂载点。
  'save.share',
  'scene.check.step',
  // ★ KP-7：`scene.clue` 已迁入独立 `showClueSheet`（独立 ValueKey），不再挂
  //   `act/scene.clue` 锚点；domain action 名与 POLICY 条目均未动。
  'scene.clue',
  // ★ P17 P-4：玩家工具栏「转战斗」恒灰无用，三视角删除；KP 侧走大厅与
  //   KP 工具（`combat.start`）。
  'scene.mode',
  'scene.reveal',
  'scene.set',
  'state.edit.other',
  'state.edit.self',
  'state.self',
];

// ------------------------------------------------------------
// 夹具与宿主
// ------------------------------------------------------------

/// 造一个开团中的房间（成员齐、有三份裁剪视角）。
///
/// ★ P10 第 2 期 B：页面档位被显式传参。游戏页在「平板横屏」档才会把
///   12 / 13 个槽位全部摊成真块（竖屏 / 手机档按用户口述收成方块），
///   所以页面级用例传 1280×800；弹层用例仍用足够大的竖屏（弹层不受影响）。
Future<RoomUiFixture> _boot(
  WidgetTester tester, {
  double w = 900,
  double h = 2200,
  String mode = RoomMode.exploration,
}) async {
  final RoomUiFixture f = RoomUiFixture();
  await f.boot(inGame: true, mode: mode);
  useRoomScreen(tester, w, h);
  return f;
}

/// 游戏页专用档位（平板横屏固定网格）。
const double kPageW = 1280;
const double kPageH = 800;

/// 宿主：作用域挂在 Navigator **之上**，于是弹层 / 页面都能 `RoomScope.of`。
Widget _appFor(RoomUiFixture f, String seat, Widget body) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (BuildContext _, Widget? child) => f.scoped(
      seat,
      child: child ?? const SizedBox.shrink(),
    ),
    home: body,
  );
}

/// 弹层内容装进可滚动容器（`Wrap` / `Column` 全量挂到元素树上）。
Widget _sheetHost(RoomUiFixture f, String seat, Widget sheet) {
  return _appFor(
    f,
    seat,
    Scaffold(body: SingleChildScrollView(child: sheet)),
  );
}

/// 读当前树里所有 `act/<op>` 锚点的可点性。
///
/// 返回 `op → 该 op 出现过的 enabled 集合`：集合大小 > 1 说明同 op 出现
/// 两个互相矛盾的可点性（本身就是缺陷）。
Map<String, Set<bool>> actEnabled(WidgetTester tester) {
  final Map<String, Set<bool>> out = <String, Set<bool>>{};
  for (final RoomTap tap in tester.widgetList<RoomTap>(find.byType(RoomTap))) {
    final Key? key = tap.key;
    if (key is! ValueKey<String>) continue;
    final String value = key.value;
    if (!value.startsWith('act/')) continue;
    (out[value.substring(4)] ??= <bool>{}).add(tap.enabled);
  }
  return out;
}

/// 断言「本面 × 本视角」下每个锚点都等于 `gate.can(op)`。
///
/// [requireAtLeastOne] 为 false 时允许「一个锚点都没有」——只用于
/// 「该视角在本面确实没有任何 act 入口」是正确结果的情形（如旁观者在大厅：
/// KP 工具块 / 探索面板改动入口 / 踢人 / `check.opposed` 全部结构性隐藏）。
/// 那种情形必须由调用方**另行显式断言为空**，不能靠这里放行。
void expectGateEquivalence(
  RoomUiFixture f,
  WidgetTester tester,
  String surface,
  String seat, {
  bool requireAtLeastOne = true,
}) {
  final Map<String, Set<bool>> got = actEnabled(tester);
  if (requireAtLeastOne) {
    expect(got, isNotEmpty, reason: '$surface @ $seat 一个 act/<op> 锚点都没挂');
  }
  final List<String> bad = <String>[];
  got.forEach((String op, Set<bool> flags) {
    final bool want = f.controllerOf(seat).gate.can(op);
    if (flags.length != 1) {
      bad.add('$op: 同 op 多处可点性不一致 $flags');
    } else if (flags.single != want) {
      bad.add('$op: enabled=${flags.single} 但 gate.can=$want');
    }
  });
  expect(bad, isEmpty, reason: '$surface @ $seat 可点性与闸门漂移：${bad.join('；')}');
}

/// 三个视角（KP / 玩家 / 旁观）。
const List<String> kSeats = <String>[kHostSeat, 'p1', 'sp1'];

void main() {
  // ----------------------------------------------------------
  // ① 静态锚点表
  // ----------------------------------------------------------
  group('T-30 锚点表（静态扫描）', () {
    test('扫 lib/ui/room 产出 op → 挂载点表，且每个 op 都在 POLICY 登记表里', () {
      final Map<String, List<String>> table = scanAnchors();
      // ignore: avoid_print
      print('[T-30] 锚点表 ${table.length} 个 op：');
      final List<String> ops = table.keys.toList()..sort();
      for (final String op in ops) {
        // ignore: avoid_print
        print('  $op ← ${table[op]!.join(', ')}');
      }
      // 28：P17 又迁走 3 个 ——
      //   · `combat.enqueue`（P10 旧迁）：专用 key `GpCombatKeys.enqueueRow(seat)`；
      //   · `combat.attack`（P17 KP-3）：快捷按钮换成 `check.opposed {attack:true}`，
      //     「武器对抗」与战斗对抗合并成一个入口；
      //   · `scene.mode`（P17 P-4）：玩家工具栏的「转战斗」恒灰无用，三视角删除；
      //     KP 的切战斗由大厅与工具栏 `RoomGamePage.combatReadyKey` 承担
      //     （`act/combat.start` 锚点仍由 `sheet_combat.dart:228` 的部署按钮保留）。
      // 门控仍在（`enabled: gate.can`），迁走的由对应专用 key 探针覆盖。
      // ★ KP-7：`scene.clue` 锚点撤回（迁入 showClueSheet）⇒ 28 − 1 = 27。
      // ★ 2.36.0 / Q6：`round.next` 的唯一 act/ 锚点（原 `sheet_kp_panel.dart`）
      //   随按钮迁入工具栏独立 ValueKey 而消失 ⇒ 27 − 1 = 26；
      //   `combat.start` 仍由 `sheet_combat.dart:228` 保留，**不减**。
      // ★ 2.37.0 / Q4：`dice.dark` 锚点随骰子工具弹层删除而消失 ⇒ 26 − 1 = 25。
      expect(table.length, 25, reason: '锚点 op 数变化了：${table.length}');

      final List<String> unknown = <String>[
        for (final String op in table.keys)
          if (!kRoomPolicy.containsKey(op)) op,
      ];
      expect(unknown, isEmpty,
          reason: '这些 op 挂了 act/ 锚点却没在 kRoomPolicy 登记：$unknown');

      // 每个 op 至少一个挂载点，且挂载点都指向 lib/ui/room 下的真实文件。
      table.forEach((String op, List<String> where) {
        expect(where, isNotEmpty, reason: '$op 无挂载点');
        for (final String hit in where) {
          expect(File(hit.split(':').first).existsSync(), isTrue,
              reason: '$op 的挂载点文件不存在：$hit');
        }
      });
    });

    test('③ 报告：POLICY 62 条里没有 act/<op> 锚点的 op 恰好 37 条', () {
      final Map<String, List<String>> table = scanAnchors();
      expect(kRoomPolicy.length, 62, reason: 'POLICY 条数变化（P19 +save.share）');
      final List<String> noAnchor = <String>[
        for (final String op in kRoomPolicy.keys)
          if (!table.containsKey(op)) op,
      ]..sort();
      // ignore: avoid_print
      print('[T-30] 无 act/<op> 锚点的 POLICY 项 ${noAnchor.length} 条：'
          '${noAnchor.join(', ')}');
      expect(noAnchor, kFrozenNoAnchor,
          reason: '「无锚点」清单漂移（多测或漏测都会在这里暴露）');
      expect(noAnchor.length + table.length, 62,
          reason: '有锚点 + 无锚点应恰好铺满 POLICY');
    });
  });

  // ----------------------------------------------------------
  // ② 运行时等价：enabled == gate.can(op)
  // ----------------------------------------------------------
  group('T-30 运行时等价（enabled ⟺ gate.can）', () {
    testWidgets('弹层 KpPanel × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_sheetHost(f, seat, const KpPanel()));
        await tester.pump();
        expectGateEquivalence(f, tester, 'KpPanel', seat);
      }
    });

    // ★ 2.36.0 / Q6（裁决 3）：`round.next` / `combat.start` 两个动作从
    //   `act/<op>` 表驱动射程**迁出**到独立 ValueKey，静态锚点表不再覆盖它们。
    //   这里把丢失的运行时等价覆盖**平移回来**（更强或等价）：
    //   ① 三视角分别断言新按钮存在性 + `enabled 恰好 == gate.can(op)`；
    //   ② 三视角分别断言 `gate.can(op)` 与角色一致；
    //   ③ tap 真触发（round.next 出站 / combatReady 打开弹层）。
    //   绝不挂 `RoomKeys.action(...)` 锚点 ⇒ T-30 表驱动探针与
    //   `p10_t3_layout_test.dart:292-295` 的 findsNothing 契约仍成立。
    testWidgets('Q6 专用 key 运行时等价：nextRoundKey / combatReadyKey × 三视角 + tap',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester, w: kPageW, h: kPageH);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_appFor(f, seat, const RoomGamePage()));
        await tester.pump();
        final bool kp = seat == kHostSeat;
        final Finder nr = find.byKey(RoomGamePage.nextRoundKey);
        final Finder cr = find.byKey(RoomGamePage.combatReadyKey);
        expect(nr, kp ? findsOneWidget : findsNothing,
            reason: '$seat：nextRoundKey 仅 KP 渲染');
        expect(cr, kp ? findsOneWidget : findsNothing,
            reason: '$seat：combatReadyKey 仅 KP 渲染');
        expect(find.byKey(RoomKeys.action('round.next')), findsNothing,
            reason: '$seat：新按钮绝不挂 act/round.next 锚点');
        expect(find.byKey(RoomKeys.action('combat.start')), findsNothing,
            reason: '$seat：新按钮绝不挂 act/combat.start 锚点');
        final gate = f.controllerOf(seat).gate;
        expect(gate.can('round.next'), kp, reason: '$seat：round.next 闸门');
        expect(gate.can('combat.start'), kp, reason: '$seat：combat.start 闸门');
        if (kp) {
          expect(tester.widget<RoomTap>(nr).enabled, gate.can('round.next'),
              reason: '★ enabled 恰好等于 gate.can(round.next)');
          expect(tester.widget<RoomTap>(cr).enabled, gate.can('combat.start'),
              reason: '★ enabled 恰好等于 gate.can(combat.start)');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      await tester.pumpWidget(_appFor(f, kHostSeat, const RoomGamePage()));
      await tester.pump();
      f.clearSent();
      await tester.ensureVisible(find.byKey(RoomGamePage.nextRoundKey));
      await tester.tap(find.byKey(RoomGamePage.nextRoundKey));
      await tester.pump();
      expect(f.lastSent(action: 'round.next'), isNotNull,
          reason: '★ tap nextRoundKey 必须真的下发 round.next');
      await tester.ensureVisible(find.byKey(RoomGamePage.combatReadyKey));
      await tester.tap(find.byKey(RoomGamePage.combatReadyKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CombatSheet), findsOneWidget,
          reason: '★ tap combatReadyKey 必须打开战斗准备弹层');
      expect(tester.takeException(), isNull);
    });

    testWidgets('弹层 KpDirectivesSheet × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_sheetHost(f, seat, const KpDirectivesSheet()));
        await tester.pump();
        expectGateEquivalence(f, tester, 'KpDirectivesSheet', seat);
      }
    });

    testWidgets('弹层 CombatSheet × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_sheetHost(f, seat, const CombatSheet()));
        await tester.pump();
        expectGateEquivalence(f, tester, 'CombatSheet', seat);
      }
    });

    testWidgets('弹层 SceneSheet × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_sheetHost(f, seat, const SceneSheet()));
        await tester.pump();
        expectGateEquivalence(f, tester, 'SceneSheet', seat);
      }
    });

    testWidgets('弹层 OpposedSheet × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_sheetHost(f, seat, const OpposedSheet()));
        await tester.pump();
        expectGateEquivalence(f, tester, 'OpposedSheet', seat);
      }
    });

    testWidgets('弹层 DiceToolsSheet × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_sheetHost(f, seat, const DiceToolsSheet()));
        await tester.pump();
        expectGateEquivalence(f, tester, 'DiceToolsSheet', seat);
      }
    });

    // ★ 2.37.0 / Q4：弹层只留 d100 阈值一块，四块设置入口迁走但 DiceToolsKeys
    //   常量全保留、room.rules 锚点仍在（gating 与 §1.6 同源）。
    testWidgets('弹层 DiceToolsSheet 只剩 d100 阈值块：crit/fumble/room.rules 在，'
        '四块删掉的 key 全不在', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_sheetHost(f, seat, const DiceToolsSheet()));
        await tester.pump();

        expect(find.byType(SectionBox), findsOneWidget,
            reason: '★ 只剩「d100 成败阈值」一个 SectionBox');
        expect(find.text('d100 成败阈值'), findsOneWidget);
        expect(find.byKey(DiceToolsKeys.root), findsOneWidget);
        expect(find.byKey(DiceToolsKeys.crit), findsOneWidget);
        expect(find.byKey(DiceToolsKeys.fumble), findsOneWidget);
        expect(find.byKey(RoomKeys.action('room.rules')), findsOneWidget,
            reason: '★ room.rules 锚点保留（Q4 只走 dice.dark 一个锚点）');

        for (final Key key in <Key>[
          DiceToolsKeys.skillLabel,
          DiceToolsKeys.skillBase,
          DiceToolsKeys.skillRoll,
          DiceToolsKeys.sanCheck,
          DiceToolsKeys.customExpr,
          DiceToolsKeys.customRoll,
          DiceToolsKeys.dark,
          DiceToolsKeys.rules,
        ]) {
          expect(find.byKey(key), findsNothing,
              reason: '★ 已删除的设置入口不该还在弹层里：$key');
        }
      }
    });

    testWidgets('游戏页 RoomGamePage × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester, w: kPageW, h: kPageH);
      for (final String seat in kSeats) {
        await tester.pumpWidget(_appFor(f, seat, const RoomGamePage()));
        await tester.pump();
        // ★ P17 P-4：`round.next` / `scene.mode` 两个「恒渲染但禁用」的工具栏
        //   锚点已三视角删除 —— 旁观者在游戏页从此**零 act/ 锚点**（骰子条 /
        //   对抗 / 更多工具 / 治疗对旁观都结构上不渲染）。与大厅同款处理：
        //   旁观 requireAtLeastOne:false + 零锚点结构断言。
        expectGateEquivalence(f, tester, 'RoomGamePage', seat,
            requireAtLeastOne: seat != 'sp1');
        if (seat == 'sp1') {
          expect(actEnabled(tester), isEmpty,
              reason: '旁观者在游戏页不应看到任何 act/<op> 锚点');
        }
      }
    });

    testWidgets('大厅页 RoomLobbyPage × 三视角', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);

      // KP / 玩家：大厅里确实挂着 act 锚点（探索面板 / 掷骰条 / 房间管理），
      // 逐点断言可点性恒等闸门。
      for (final String seat in <String>[kHostSeat, 'p1']) {
        await tester.pumpWidget(_appFor(f, seat, const RoomLobbyPage()));
        await tester.pump();
        expectGateEquivalence(f, tester, 'RoomLobbyPage', seat);
      }

      // 旁观：大厅里**一个 act 锚点都不该有**才是正确结果 ——
      // KP 工具块（isKp 门控）、探索面板的改动入口（isKp 门控）、
      // 踢人（isKp 门控）、掷骰条里的 combat.roll / check.opposed
      // （POLICY 不含 spectator）全部结构性隐藏。这是结构断言，不是放宽。
      await tester.pumpWidget(_appFor(f, 'sp1', const RoomLobbyPage()));
      await tester.pump();
      expect(actEnabled(tester), isEmpty,
          reason: '旁观者在大厅不应看到任何 act/<op> 锚点');
      expectGateEquivalence(f, tester, 'RoomLobbyPage', 'sp1',
          requireAtLeastOne: false);
      for (final String other in f.clientSeats) {
        expect(find.byKey(RoomLobbyKeys.kick(other)), findsNothing,
            reason: '旁观视角不该渲染 $other 的踢人按钮');
      }
    });

    testWidgets('静态表里的每个 op 都在运行时被真的找到（防「表里写着、页面没有」）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      final Set<String> observed = <String>{};
      final Map<String, Widget> surfaces = <String, Widget>{
        'KpPanel': const KpPanel(),
        'KpDirectivesSheet': const KpDirectivesSheet(),
        'CombatSheet': const CombatSheet(),
        'SceneSheet': const SceneSheet(),
        'OpposedSheet': const OpposedSheet(),
        'DiceToolsSheet': const DiceToolsSheet(),
        'RoomGamePage': const RoomGamePage(),
        'RoomLobbyPage': const RoomLobbyPage(),
      };
      for (final MapEntry<String, Widget> e in surfaces.entries) {
        // ★ 必须跑 KP **和玩家**两个视角：有的锚点只在其中一侧渲染
        //   （`combat.enqueue` 只在 KP 的战斗列表、`madness.advance` 只在玩家
        //   的角色卡块）。只跑 KP 会把玩家侧锚点误判成「静态表有、运行时没有」。
        // ★ 档位随页面走：游戏页要用「平板横屏」档（只有这一档会把 12 / 13
        //   个槽位全摊成真块），大厅页仍用足够高的竖屏（它的入口往下排）。
        useRoomScreen(
          tester,
          e.value is RoomGamePage ? kPageW : 900,
          e.value is RoomGamePage ? kPageH : 2200,
        );
        for (final String seat in <String>[kHostSeat, 'p1']) {
          await tester.pumpWidget(e.value is RoomGamePage ||
                  e.value is RoomLobbyPage
              ? _appFor(f, seat, e.value)
              : _sheetHost(f, seat, e.value));
          await tester.pump();
          observed.addAll(actEnabled(tester).keys);
        }
      }
      // ★ P16 KP-4②：游戏页的 `combat.next` 锚点随「战斗信息」格搬进了 gpMap，
      //   且只在**战斗态**渲染（探索态 gpMap 是素材舞台）。上面那轮是探索态，
      //   若只扫那一轮会把它误判成「静态表有、运行时没有」。补一轮战斗态扫描
      //   —— 不是放行，而是把「该在哪种态找到它」也钉进探针。
      final RoomUiFixture fc = RoomUiFixture();
      await fc.boot(inGame: true, mode: RoomMode.combat);
      useRoomScreen(tester, kPageW, kPageH);
      for (final String seat in <String>[kHostSeat, 'p1']) {
        await tester.pumpWidget(_appFor(fc, seat, const RoomGamePage()));
        await tester.pump();
        observed.addAll(actEnabled(tester).keys);
      }

      final Set<String> declared = scanAnchors().keys.toSet();
      final Set<String> missing = declared.difference(observed);
      final Set<String> extra = observed.difference(declared);
      // ignore: avoid_print
      print('[T-30] 运行时观察到 ${observed.length} 个 op，静态表 ${declared.length} 个');
      expect(missing, isEmpty, reason: '静态表有、运行时找不到：$missing');
      expect(extra, isEmpty, reason: '运行时出现、静态表没解析到：$extra');
    });
  });

  // ----------------------------------------------------------
  // ④ room.kick 特殊：一行一个按钮，enabled 集合恰好 {gate.can}
  // ----------------------------------------------------------
  group('T-30 room.kick（多按钮同 op）', () {
    testWidgets('KP 视角：任意座位上 kick 按钮的 enabled 集合 == {gate.can(room.kick)}',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_appFor(f, kHostSeat, const RoomLobbyPage()));
      await tester.pump();

      final bool want = f.controllerOf(kHostSeat).gate.can('room.kick');
      final Set<bool> seen = <bool>{};
      var count = 0;
      for (final String seat in f.clientSeats) {
        final Finder kick = find.byKey(RoomLobbyKeys.kick(seat));
        if (kick.evaluate().isEmpty) continue;
        count += 1;
        seen.add(tester.widget<RoomTap>(kick).enabled);
      }
      expect(count, greaterThanOrEqualTo(2),
          reason: 'KP 视角应能对每个非 KP 成员行看到 kick 按钮');
      expect(seen, <bool>{want},
          reason: 'kick 按钮可点性集合 $seen 应恰好是 {$want}');
      expect(want, isTrue, reason: 'KP 对 room.kick 应有权限（POLICY 只放 KP）');
    });

    testWidgets('玩家 / 旁观视角：kick 按钮结构上不存在（不是禁用）', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      for (final String seat in <String>['p1', 'sp1']) {
        await tester.pumpWidget(_appFor(f, seat, const RoomLobbyPage()));
        await tester.pump();
        for (final String other in f.clientSeats) {
          expect(find.byKey(RoomLobbyKeys.kick(other)), findsNothing,
              reason: '$seat 视角不该渲染 $other 的 kick 按钮');
        }
      }
    });
  });

  // ----------------------------------------------------------
  // ⑤ 结构式断言：KP 专属按钮在玩家 / 旁观下 findsNothing
  // ----------------------------------------------------------
  group('T-22 结构式边界（findsNothing 而非 enabled=false）', () {
    /// 源码里用 `isKp ? … : null` 或 `if (gate.can(…))` 做**结构性**门控的 op。
    /// 与「恒渲染但禁用」（如工具栏的 `round.next`）刻意区分：
    /// 前者是能力边界，后者只是可点性 —— 两种口径都必须成立。
    const List<String> structuralKpOnly = <String>[
      'combat.next', // gp_combat_list：isKp 三元
      'check.opposed', // gp_dice_bar：if (isKp && gate.can)
    ];

    testWidgets('玩家视角：KP 专属锚点 findsNothing', (WidgetTester tester) async {
      // 战斗态下反证（探索态本来就看不到战斗信息栏，那样断言会因「面板没开」
      // 而虚绿）：面板必须真的在渲染，而 KP 专属按钮仍结构性缺失。
      final RoomUiFixture f = await _boot(
        tester,
        w: kPageW,
        h: kPageH,
        mode: RoomMode.combat,
      );
      await tester.pumpWidget(_appFor(f, 'p1', const RoomGamePage()));
      await tester.pump();
      for (final String op in structuralKpOnly) {
        // ★ PV-1b：`check.opposed` 的 roles 已放宽为 [kp, player] + RoomConfirm.kp，
        //   玩家确有该权限（产品契约真变）；但 W-B 的 `&& isKp` 门控保证骰子条上的
        //   KP 裁定入口仍结构性隐藏 —— 下方 findsNothing 口径逐字保留。
        if (op == 'check.opposed') {
          expect(f.controllerOf('p1').gate.can(op), isTrue,
              reason: 'PV-1b：玩家可发起对抗，走 RoomConfirm.kp 审批');
        } else {
          expect(f.controllerOf('p1').gate.can(op), isFalse,
              reason: '前提：玩家不该有 $op 权限');
        }
        expect(find.byKey(RoomKeys.action(op)), findsNothing,
            reason: '玩家视角必须结构上不渲染 $op（T-22 口径）');
      }
      // ★ PV-1b 正向：玩家主动对抗走独立 ValueKey 新按钮（不是骰子条那个 KP 入口）。
      expect(find.byKey(RoomGamePage.playerOpposedKey), findsOneWidget,
          reason: '玩家应有独立的「主动对抗」入口按钮');
    });

    testWidgets('旁观视角：KP 专属锚点 + 玩家专属急救 findsNothing', (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(
        tester,
        w: kPageW,
        h: kPageH,
        mode: RoomMode.combat,
      );
      await tester.pumpWidget(_appFor(f, 'sp1', const RoomGamePage()));
      await tester.pump();
      for (final String op in <String>[...structuralKpOnly, 'combat.roll', 'aid.apply']) {
        expect(f.controllerOf('sp1').gate.can(op), isFalse,
            reason: '前提：旁观者不该有 $op 权限');
        expect(find.byKey(RoomKeys.action(op)), findsNothing,
            reason: '旁观视角必须结构上不渲染 $op');
      }
    });

    testWidgets('KP 视角：同一批锚点 findsOneWidget（结构门控不是「永久不渲染」）',
        (WidgetTester tester) async {
      // ★ P16 KP-4②：`combat.next` 的宿主（战斗信息栏）已从右列 gpCombat 搬到
      //   gpMap 格，并且**只在战斗态**渲染（探索态那一格是素材舞台）。
      //   所以正向反证必须开战斗态；随后再用探索态反证「确实没渲染」——
      //   两条合起来才是「结构门控」而不是「永久不渲染」。
      final RoomUiFixture f = await _boot(
        tester,
        w: kPageW,
        h: kPageH,
        mode: RoomMode.combat,
      );
      await tester.pumpWidget(_appFor(f, kHostSeat, const RoomGamePage()));
      await tester.pump();
      for (final String op in structuralKpOnly) {
        expect(f.controllerOf(kHostSeat).gate.can(op), isTrue,
            reason: '前提：KP 应有 $op 权限');
        expect(find.byKey(RoomKeys.action(op)), findsOneWidget,
            reason: 'KP 视角必须渲染 $op');
      }

      // 探索态：战斗信息栏不该抢素材舞台，故 combat.next 零渲染。
      final RoomUiFixture fe = await _boot(tester, w: kPageW, h: kPageH);
      await tester.pumpWidget(_appFor(fe, kHostSeat, const RoomGamePage()));
      await tester.pump();
      expect(find.byKey(RoomKeys.action('combat.next')), findsNothing,
          reason: '探索态的 gpMap 是素材舞台，不该渲染战斗信息栏');
      expect(find.byType(GpMapStage), findsOneWidget);
    });

    testWidgets('P17 P-4：工具栏 round.next / scene.mode 三视角删除（恒灰无用的入口）',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester, w: kPageW, h: kPageH);
      const List<String> removed = <String>['round.next', 'scene.mode'];
      for (final String seat in kSeats) {
        await tester.pumpWidget(_appFor(f, seat, const RoomGamePage()));
        await tester.pump();
        for (final String op in removed) {
          expect(find.byKey(RoomKeys.action(op)), findsNothing,
              reason: 'P17 P-4：$seat 视角的工具栏不应再渲染 $op（恒灰无用）');
        }
      }
      // KP 侧等价能力全部保留：推进回合在战斗信息栏 `combat.next` 与
      // 工具栏 `RoomGamePage.nextRoundKey`（2.36.0 / Q6 迁入）；切战斗在大厅
      // （`room_lobby_page.dart`）与工具栏 `RoomGamePage.combatReadyKey`。
      // ——— 两个 op 已迁入 kFrozenNoAnchor（静态断言），运行时等价由
      //     ② 的「Q6 专用 key 探针」三视角 + tap 真触发平移覆盖（见下）。
    });
  });

  // ----------------------------------------------------------
  // ⑥ combat.damage 的两段式表单
  //   这一条钉死一次真实修复：`enabled` 曾叠过 `&& _slotId.isNotEmpty`，
  //   使「挂了 act/ 锚点却不恒等闸门」（违反 gp_dice_bar.dart 的 T-30 契约）。
  //   修法把业务前置挪进 onTap 并给一次性提示，所以这里**两条都要守**：
  //     · 可点性恒等闸门（不变式）
  //     · 未选槽位时点下去**有反馈**、但**不发包**（不能静默 return）
  // ----------------------------------------------------------
  group('combat.damage 两段式表单（不变式 + 点了有反馈）', () {
    testWidgets('未选槽位：enabled 恒等闸门，点结算 → 发包 0 条 + 「请先选择槽位」',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_sheetHost(f, kHostSeat, const CombatSheet()));
      await tester.pump();

      final Finder btn = find.byKey(RoomKeys.action('combat.damage'));
      expect(btn, findsOneWidget, reason: '战斗弹层应渲染结算按钮');
      expect(tester.widget<RoomTap>(btn).enabled, isTrue,
          reason: '前提：KP 对 combat.damage 有权限');
      expect(tester.widget<RoomTap>(btn).enabled,
          f.controllerOf(kHostSeat).gate.can('combat.damage'),
          reason: '未选槽位时 enabled 也必须恒等闸门（不许叠加业务前置）');

      final int sentBefore = f.sent.length;
      await tester.tap(btn);
      await tester.pump();
      expect(f.sent.length, sentBefore,
          reason: '未选槽位不该发包：${f.sent.sublist(sentBefore)}');
      expect(f.localOf(kHostSeat).notice, '请先选择槽位',
          reason: '点了没反应不可接受 —— 必须给一次性提示');
    });

    testWidgets('选槽位后：enabled 仍恒等闸门，点结算真的发了那一条',
        (WidgetTester tester) async {
      final RoomUiFixture f = await _boot(tester);
      await tester.pumpWidget(_sheetHost(f, kHostSeat, const CombatSheet()));
      await tester.pump();

      // 造一个参战槽位，全程走**真实 action**（不手改权威态）：
      //   ① 「开始战斗」进入战斗态（`combat.start`）；
      //   ② `combat.enqueue` 把 p1 追加进 `combat.order`。
      // 弹层里的「开始战斗」载荷带的是空的本地候选池，所以单靠它
      // order 仍为空 —— 槽位来源必须是 enqueue（POLICY 里的 KP 动作）。
      await tester.tap(find.byKey(RoomKeys.action('combat.start')));
      await tester.pump();
      await f
          .controllerOf(kHostSeat)
          .hostAction('combat.enqueue', <String, Object?>{'seat': 'p1'});
      await tester.pump();

      final List<Object?> order =
          asList(asMap(f.hostState()['combat'])['order']);
      expect(order, isNotEmpty, reason: '开战并追加入场后权威态应有参战槽位：'
          '${f.hostState()['combat']}');
      final String slotId = jsStr(asMap(order.first)['id']);
      expect(slotId, isNotEmpty);

      await tester.tap(find.byKey(CombatSheetKeys.slot(slotId)));
      await tester.pump();

      final Finder btn = find.byKey(RoomKeys.action('combat.damage'));
      expect(tester.widget<RoomTap>(btn).enabled, isTrue,
          reason: '选了槽位后结算按钮应可点');
      expect(tester.widget<RoomTap>(btn).enabled,
          f.controllerOf(kHostSeat).gate.can('combat.damage'),
          reason: '选了槽位后 enabled 仍须恒等闸门');

      final int sentBefore = f.sent.length;
      await tester.tap(btn);
      await tester.pump();
      expect(f.sent.length, sentBefore + 1, reason: '选了槽位应发出 1 条结算');
      expect(asMap(f.sent.last['p'])['slotId'], slotId,
          reason: '发包里的 slotId 与选中的槽位不一致');
    });
  });
}
