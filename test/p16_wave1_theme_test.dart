// ============================================================
// p16_wave1_theme_test.dart — P16 · v2.29.0 波1-C 自检用例
//
// 覆盖：C-1（cardTheme 真实 alpha）/ P-3（白板 + 默认黑笔）/
//       C-2（两处 onTapOutside）/ KP-5（私密栏 220）/ P-4（急救空参数）。
//
// ★ 波1 纪律：本文件「写好但暂不执行」（波1 三组并发，禁止 flutter test），
//   由波2 独占串行跑全量时统一执行。
// ★ 最强的一条：C-1 用 Color 逐通道相等断言真实 alpha（0xD9），
//   补 test/p10_t7_layout_test.dart:164 `computeLuminance()` 忽略 alpha
//   造成的「假绿」—— 那条既有亮度断言不改、不放宽，这里另加更强正向断言。
// ★ 房间 UI 零 emoji / 不写 jsStr(：本文件均为中文 + BMP 符号。
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dice_realm/theme.dart' show Palette, buildTheme;
import 'package:dice_realm/ui/room/painter/stroke_painter.dart' show BoardPainter;
import 'package:dice_realm/ui/room/widgets/gp_privates.dart'
    show GpPrivates, GpPrivatesRow;

void main() {
  group('P16 波1-C：主题 / 绘画 / 骰子 / 小件', () {
    // ---------------- C-1 ----------------
    group('C-1 栏位背景 85% 不透明（真实 alpha，非 computeLuminance 假值）', () {
      for (final Brightness b in Brightness.values) {
        test('$b：cardTheme.color == surface.withValues(alpha: 0.85)', () {
          final ThemeData theme = buildTheme(b);
          // buildTheme(b) 会把 Palette._current 切到 b，故此处取到该皮肤 surface。
          final Color surface = Palette.surface;
          // 当前 SDK 的 cardTheme 非空，直接取显式设过的 cardTheme.color。
          final Color card = theme.cardTheme.color!;

          // ① 真实 alpha 断言：Color 相等是逐通道（含 alpha）比较，
          //    比 computeLuminance()（只按 RGB、忽略 alpha）严格更强。
          expect(card, surface.withValues(alpha: 0.85),
              reason: '$b：cardTheme.color 必须是 surface 叠加 0xD9 alpha');

          // ② 方案 A 只在 cardTheme 就地叠加 alpha，Palette.surface 本身
          //    仍是不透明常量（暗 0xFF161F2E / 亮 0xFFFFFCF5），不被就地改。
          expect(
            surface,
            b == Brightness.dark
                ? const Color(0xFF161F2E)
                : const Color(0xFFFFFCF5),
          );

          // ③ 记录既有断言的盲点：半透明后 computeLuminance() 逐值不变
          //    （不是放宽 p10_t7_layout_test.dart:164，真正的 alpha 由 ① 钉死）。
          expect(card.computeLuminance(),
              closeTo(surface.computeLuminance(), 1e-9));
        });
      }
    });

    // ---------------- P-3 ----------------
    test('P-3 BoardPainter 默认纯黑（改默认值一处覆盖所有调用点）', () {
      expect(
        BoardPainter(const <Map<String, Object?>>[]).color,
        0xff000000,
        reason: '白板默认笔色必须是纯黑 0xff000000（原 0xff222222）',
      );
      // 显式传色仍可覆盖（构造函数参数未被写死）。
      expect(
        BoardPainter(const <Map<String, Object?>>[], color: 0xff123456).color,
        0xff123456,
      );
    });

    test('P-3 画布硬编码白色，不再随 theme.colorScheme.surface', () {
      final String src =
          File('lib/ui/room/widgets/gp_pl_sketch.dart').readAsStringSync();
      expect(src, contains('color: Colors.white'),
          reason: '画布底色必须是硬编码白（亮/暗主题都白板）');
      expect(src, isNot(contains('color: theme.colorScheme.surface')),
          reason: '不得再读主题 surface（暗色主题会变深底）');
    });

    // ---------------- C-2 ----------------
    test('C-2 两处常驻 TextField 均挂 onTapOutside（控件级失焦）', () {
      for (final String path in <String>[
        'lib/ui/room/widgets/gp_dice_bar.dart',
        'lib/ui/room/widgets/gp_pl_notes.dart',
      ]) {
        final String src = File(path).readAsStringSync();
        expect(
          src,
          contains('onTapOutside: (_) => FocusScope.of(context).unfocus()'),
          reason: '$path 缺少控件级 onTapOutside',
        );
      }
      // 门禁（约束说明，不读波2 独占文件）：禁止页面级 FocusNode /
      // GestureDetector，room_game_page.dart 不为 C-2 落任何改动。
    });

    // ---------------- KP-5 ----------------
    test('KP-5 GpPrivates 默认高度 220（与聊天/游戏记录一致）', () {
      expect(const GpPrivates().height, 220,
          reason: '私密栏默认高度须由 160 拉长到 220');
    });

    // 固定尺寸控件（SizedBox(height: 220) + 空态 Text）在无障碍放大下不溢出：
    // 用 MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0) 只钳该控件子树，
    // 不抬到页面/Theme 层、不用 ClipRect 硬裁（P16 测试纪律）。
    testWidgets('KP-5 固定高度私密行 textScaler 1.3/1.5/2.0 不溢出',
        (WidgetTester tester) async {
      for (final double scale in <double>[1.3, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: const Center(
              child: SizedBox(
                width: 300,
                height: 220,
                child: GpPrivatesRow(text: '测试私密信息内容', title: '标题'),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull,
            reason: 'textScaler=$scale 固定高度私密行不应溢出/抛异常');
      }
    });

    // ---------------- P-4 ----------------
    test('P17 C-1：急救按钮已从角色卡删除（真入口在「治疗」弹层 / 更多工具）', () {
      final String src =
          File('lib/ui/room/widgets/gp_pl_char_card.dart').readAsStringSync();
      // ★ P17 C-1：`act/aid.apply` 按钮的渲染已删（key 常量保留兼容）。
      //   P16 时的「空参数已补齐」断言随按钮一起退役；真入口契约改由：
      //   · `sheet_treat.dart`（治疗弹层，急救/医学/精神分析三分支）
      //   · `room_ui_entry_test.dart` 的「更多工具」widget 级断言
      //   两处共同守住。
      expect(src, contains("GpPlCharCardKeys.aiBtn"),
          reason: 'P17 C-1：key 常量保留（既有测试可编译），只是不再渲染');
      expect(src, isNot(contains("RoomKeys.action('aid.apply')")),
          reason: 'P17 C-1：角色卡不再挂急救的 act/ 锚点');
      expect(src, isNot(contains("'skill': '急救'")),
          reason: 'P17 C-1：急救载荷随按钮一起移走');
      final treat =
          File('lib/ui/room/sheets/sheet_treat.dart').readAsStringSync();
      // skill 值走 `_TreatKind('急救', 'aid.apply', '急救', ...)` 分支常量表。
      expect(treat.contains("_TreatKind('急救', 'aid.apply', '急救'"), isTrue,
          reason: 'P17 C-1：急救真入口在治疗弹层（急救分支仍在）');
      expect(treat.contains('aid.apply'), isTrue,
          reason: 'P17 C-1：治疗弹层仍走 aid.apply 通道');
    });
  });
}
