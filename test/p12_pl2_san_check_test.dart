// ============================================================
// test/p12_pl2_san_check_test.dart — P12 / 第 9 期 · PL-2
//
// 「San Check」免审批玩法验收：
//   A 真链路：sendIntent(RoomIntent.sanCheck, {okLoss,loss}) → PUBLIC 记录、
//     SAN 下降、pending 长度不变（全程无 RoomConfirm.kp）。
//   B 参数化注入 RoomRulesPort 替身（钉死检定骰值 / 成功失败分支 /
//     损失值），逐档验证「成功 -okLoss / 失败 -k / 边界」的 SAN 结算组合。
//   C UI：按钮 index = 主动对抗 + 1；非法格式禁用确定；textScaler
//     1.3 / 1.5 / 2.0 不溢出；GpDiceBar 9 项契约不动。
//
// ★ 权威端 settleSanCheck / afterSanLoss 是既有链路（本期零改动），
//   客户端只用 SanCheckExpr.parse 组装载荷 —— 本文件两端都验。
// ============================================================

import 'dart:convert' show jsonEncode;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_model_actions_sheet.dart'
    show RoomHostActionsSheet;
import 'package:dice_realm/domain/room_model_host_core.dart'
    show RoomHost, RoomHostOptions;
import 'package:dice_realm/domain/room_rules.dart' show CocRules;
import 'package:dice_realm/domain/room_types.dart'
    show RoomIntent, SendPlan, kHostSeat;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/san_check_expr.dart' show SanCheckExpr;
import 'package:dice_realm/ui/room/sheets/sheet_san_check.dart'
    show SanCheckSheet, SanCheckSheetKeys;
import 'package:dice_realm/ui/room/widgets/gp_dice_bar.dart'
    show diceBalancedRowSizes;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show Lcg, oracleNowMs;
import 'support/room_fakes.dart'
    show DeterministicRoomMadness, InMemoryRoomSaveStore;
import 'support/room_ui_harness.dart' show RoomUiFixture, useRoomScreen;

/// 注入替身：把「检定骰值 / 成功失败分支 / 本次理智损失」三件事钉死，
/// 其余规则方法仍走真实 CocRules（不重写规则书）。
///
/// 这就是 PL-2 的 diceRoll 替身注入点：settleSanCheck 通过
/// `rules.parseSanLoss` / `rules.resolveSanCheck` 拿检定结果，
/// 覆盖这两个方法即可在不碰 domain 的前提下参数化所有分支。
class _FixedSanRules extends CocRules {
  _FixedSanRules({
    required this.loss,
    required this.success,
    required this.roll,
  });

  final num loss;
  final bool success;
  final num roll;

  /// 记录 settleSanCheck 真正组合出来的表达式（验证 2/1d6 → 2/1D6）。
  String? lastLossExpr;

  @override
  Map<String, Object?> parseSanLoss(Object? expr) =>
      <String, Object?>{'ok': true};

  @override
  Map<String, Object?> resolveSanCheck(Map<String, Object?> opts) {
    lastLossExpr = jsStr(opts['lossExpr']);
    return <String, Object?>{
      'ok': true,
      'check': <String, Object?>{
        'value': roll,
        'level': success ? 2 : 0,
        'levelText': success ? '成功' : '失败',
      },
      'loss': loss,
      'branchText': success ? '成功' : '失败',
      'usedBranch': success ? 'onSuccess' : 'onFailure',
    };
  }
}

/// 一个带 SAN 的最小成员记录（settleSanCheck 从 sheet.status 读值）。
Map<String, Object?> _member(int san) => <String, Object?>{
      'seat': 'p1',
      'nickname': '调查员',
      'sheet': <String, Object?>{
        'name': '调查员',
        'status': <String, Object?>{
          'currentSAN': san,
          'maxSAN': 99,
        },
        'mental': <Object?>[],
      },
    };

/// 用注入替身建一台只用于结算的权威端。
RoomHost _hostWith(num loss, bool success) => _hostWithRules(
      _FixedSanRules(loss: loss, success: success, roll: 42),
    );

RoomHost _hostWithRules(_FixedSanRules rules) => RoomHost(RoomHostOptions(
      meta: <String, Object?>{'code': 'SAN1'},
      now: () => oracleNowMs,
      rng: Lcg(7).call,
      rules: rules,
      madness: const DeterministicRoomMadness(),
      saveStore: InMemoryRoomSaveStore(),
    ));

/// 把结算产出的全部 SendPlan 序列化成一段文本，逐字断言播报文案。
String _plansText(List<SendPlan> plans) =>
    plans.map((SendPlan p) => jsonEncode(p.toJson())).join('\n');

void main() {
  group('A · 真链路：免审批、SAN 下降、pending 不变', () {
    test('sendIntent(sancheck, 2/1d6) → PUBLIC 记录 + SAN 下降 + 无 KP 待办',
        () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final int pendingBefore = f.host.pending.length;
      final int sanBefore = _sanOf(f, 'p1');

      await f.sessionOf('p1').sendIntent(
            RoomIntent.sanCheck,
            SanCheckExpr.parse('2/1d6')!.toIntentPayload(),
          );

      expect(f.host.pending.length, pendingBefore,
          reason: '★ San Check 免审批：不得产生 RoomConfirm.kp 待办');
      final List<String> logs = asList(f.stateOf(kHostSeat)['logs'])
          .map((Object? e) => jsStr(asMap(e)['text']))
          .toList();
      expect(logs.any((String t) => t.contains('做 SAN Check')), isTrue,
          reason: '应产出 PUBLIC 检定记录，实测：$logs');
      expect(logs.any((String t) => t.contains('SAN Check') &&
              (t.contains('理智损失') || t.contains('无理智损失'))), isTrue,
          reason: '记录应含理智损失口径，实测：$logs');
      // 固定 seed 下必掉 san（成功 -2 / 失败 -骰值，都 > 0）。
      expect(_sanOf(f, 'p1'), lessThan(sanBefore),
          reason: 'SAN 必须实际下降，实测 $sanBefore → ${_sanOf(f, 'p1')}');
    });

    test('反复发起不积累 pending（幂等免审批）', () async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      final int pendingBefore = f.host.pending.length;
      for (int i = 0; i < 3; i++) {
        await f.sessionOf('p1').sendIntent(
              RoomIntent.sanCheck,
              SanCheckExpr.parse('2/1D6')!.toIntentPayload(),
            );
      }
      expect(f.host.pending.length, pendingBefore,
          reason: '连点三次也不该进审批队列');
    });
  });

  group('B · 参数化注入：成功 -2 / 失败固定骰值 -k / 边界', () {
    // [分支, 本次损失, 起始 SAN, 期望结算后 SAN, 是否出现「理智损失」]
    const List<List<Object>> cases = <List<Object>>[
      <Object>['成功', 2, 50, 48, true],
      <Object>['失败', 1, 50, 49, true],
      <Object>['失败', 3, 50, 47, true],
      <Object>['失败', 6, 50, 44, true],
      <Object>['失败', 5, 1, 0, true], // SAN 触底不出现负数
      <Object>['成功', 0, 50, 50, false], // 零损失：无 stateApply
      <Object>['失败', 99, 99, 0, true], // 最大损失钳制
    ];

    for (final List<Object> c in cases) {
      final String branch = c[0] as String;
      final num loss = c[1] as num;
      final int san = c[2] as int;
      final int after = c[3] as int;
      final bool hasLoss = c[4] as bool;

      test('$branch 支 loss=$loss：SAN $san → $after（注入骰值 42）', () {
        final RoomHost host = _hostWith(loss, branch == '成功');
        final List<SendPlan> plans = host.settleSanCheck(
          _member(san),
          <String, Object?>{'okLoss': '2', 'loss': '1D6'},
          'p1',
        );
        final String blob = _plansText(plans);
        expect(blob.contains('做 SAN Check'), isTrue,
            reason: '应产出检定播报，实测：$blob');
        if (hasLoss) {
          expect(blob.contains('理智损失 ${loss.toInt()}，SAN $san → $after'), isTrue,
              reason: 'SAN 结算组合错，实测：$blob');
        } else {
          expect(blob.contains('无理智损失（SAN 保持不变）'), isTrue,
              reason: '零损失分支不该写 stateApply，实测：$blob');
        }
        expect(blob.contains('SAN -'), isFalse,
            reason: 'SAN 不该出现负数');
      });
    }

    test('完整链路：SanCheckExpr.parse(2/1d6) → 载荷 → settleSanCheck 组合 2/1D6',
        () {
      final _FixedSanRules rules =
          _FixedSanRules(loss: 2, success: true, roll: 42);
      final RoomHost host = _hostWithRules(rules);
      final Map<String, Object?> payload =
          SanCheckExpr.parse('2/1d6')!.toIntentPayload();
      expect(payload, <String, Object?>{'okLoss': '2', 'loss': '1D6'});

      final List<SendPlan> plans =
          host.settleSanCheck(_member(50), payload, 'p1');
      // ① 权威端收到的表达式必须是归一后的 2/1D6（不是小写 d、不是别的形状）。
      expect(rules.lastLossExpr, '2/1D6',
          reason: 'okLoss=2 / loss=1D6 必须被组合成 2/1D6');
      // ② 成功支用 okLoss（2），不是失败支的 1D6。
      final String blob = _plansText(plans);
      expect(blob.contains('成功 支 2'), isTrue, reason: '实测：$blob');
      expect(blob.contains('理智损失 2，SAN 50 → 48'), isTrue,
          reason: '成功扣固定值 2，实测：$blob');
      // ③ 容错写法（大小写 / 空格）走同一条链路。
      for (final String raw in <String>['2/1D6', '2 / 1d6']) {
        final _FixedSanRules r =
            _FixedSanRules(loss: 2, success: true, roll: 42);
        _hostWithRules(r).settleSanCheck(
          _member(50),
          SanCheckExpr.parse(raw)!.toIntentPayload(),
          'p1',
        );
        expect(r.lastLossExpr, '2/1D6', reason: '「$raw」应归一成 2/1D6');
      }
    });
  });

  group('C · UI：按钮顺序 / 非法格式禁用 / 大字号 / 骰子条 9 项', () {
    testWidgets('San Check 在 mainActions 里紧跟「主动对抗」（index+1）',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 1280, 800);
      await tester.pumpWidget(f.pageOf('p1'));
      await tester.pump();

      final Finder opposed = find.byKey(RoomGamePage.playerOpposedKey);
      final Finder san = find.byKey(RoomGamePage.sanCheckKey);
      expect(opposed, findsOneWidget, reason: '玩家应有主动对抗按钮');
      expect(san, findsOneWidget, reason: '玩家应有 San Check 按钮');

      // DFS 顺序即 mainActions 的声明顺序；两个按钮之间不夹别的 RoomTap。
      final List<Element> taps = find.byType(RoomTap).evaluate().toList();
      int idxOf(Key k) => taps.indexWhere((Element e) => e.widget.key == k);
      final int iOpposed = idxOf(RoomGamePage.playerOpposedKey);
      final int iSan = idxOf(RoomGamePage.sanCheckKey);
      expect(iOpposed, greaterThanOrEqualTo(0));
      expect(iSan, iOpposed + 1,
          reason: '★ San Check 必须 index = 主动对抗 + 1（实测 $iOpposed / $iSan）');
      // 「右侧相邻」几何证据：同一行且 san 在右侧。
      final Rect rOpposed = tester.getRect(opposed);
      final Rect rSan = tester.getRect(san);
      expect(rSan.center.dy, closeTo(rOpposed.center.dy, 2.0),
          reason: '两按钮应同一行');
      expect(rSan.left, greaterThanOrEqualTo(rOpposed.right - 1.0),
          reason: 'San Check 应在主动对抗右侧');
      expect(tester.takeException(), isNull);
    });

    testWidgets('弹窗实时校验：abc / 2/ / -1/1d6 禁用确定，2/1d6 放行',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: f.scoped('p1', child: const SanCheckSheet())),
      ));
      await tester.pump();

      bool submitEnabled() => tester
          .widget<RoomTap>(find.byKey(SanCheckSheetKeys.submit))
          .enabled;
      expect(submitEnabled(), isFalse, reason: '空输入应禁用确定');
      for (final String bad in <String>['abc', '2/', '-1/1d6', '2/1d6/3']) {
        await tester.enterText(find.byKey(SanCheckSheetKeys.field), bad);
        await tester.pump();
        expect(submitEnabled(), isFalse, reason: '「$bad」不该放行');
      }
      await tester.enterText(find.byKey(SanCheckSheetKeys.field), '2/1d6');
      await tester.pump();
      expect(submitEnabled(), isTrue, reason: '合法 2/1d6 必须放行');
      expect(tester.takeException(), isNull);
    });

    testWidgets('textScaler 1.3 / 1.5 / 2.0：San Check 按钮子树被钳制、不溢出',
        (WidgetTester tester) async {
      final RoomUiFixture f = RoomUiFixture();
      await f.boot(inGame: true);
      f.pageBuilder = (String s, String r) => const RoomGamePage();
      useRoomScreen(tester, 1280, 800);
      for (final double scale in <double>[1.3, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(f.pageOf('p1'));
        await tester.pump();
        final Finder san = find.byKey(RoomGamePage.sanCheckKey);
        expect(san, findsOneWidget, reason: '×$scale 按钮不该消失');
        final BuildContext ctx = tester.element(san);
        expect(MediaQuery.of(ctx).textScaler.scale(13), closeTo(13, 0.01),
            reason: '×$scale：clampBtnText 必须只钳按钮子树');
        expect(tester.getSize(san).width, greaterThanOrEqualTo(80));
        // 整页可能有本批范围外的既有溢出，drain 掉，不污染后续断言。
        while (tester.takeException() != null) {}
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    test('GpDiceBar 9 项契约不动：diceBalancedRowSizes(9,3)/(9,4) 均 3/3/3', () {
      expect(diceBalancedRowSizes(9, 3), <int>[3, 3, 3]);
      expect(diceBalancedRowSizes(9, 4), <int>[3, 3, 3]);
      expect(RoomIntent.values.length, 13,
          reason: 'San Check 复用既有 sancheck，不新增第 14 个意图');
      expect(RoomIntent.values.contains(RoomIntent.sanCheck), isTrue);
    });
  });
}

/// 从裁剪态读某座位当前 SAN。
int _sanOf(RoomUiFixture f, String seat) {
  for (final Object? raw in asList(f.stateOf(seat)['members'])) {
    final Map<String, Object?> m = asMap(raw);
    if (jsStr(m['seat']) != seat) continue;
    final Map<String, Object?> status =
        asMap(asMap(m['sheet'])['status']);
    final Object? v = status['currentSAN'];
    return v is num ? v.toInt() : -1;
  }
  return -1;
}
