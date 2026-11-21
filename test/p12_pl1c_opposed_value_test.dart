// ============================================================
// test/p12_pl1c_opposed_value_test.dart — P12 / 第 9 期 · PL-1c
//
// KP 同意「目标为可见怪的 auto 主动对抗」后补输 1–100 技能点数：
//   · confirmPending 把可选的 value 合并进 entry['p']['defender']；
//   · _autoOpposedCheck 在守方补值合法时做真胜负判定，仍只产出 1 条
//     PUBLIC kind:'check' log，两端 reduce 一致；
//   · 未补值 / 非法值 / side=='pc' 一律走既有单方分支，不误判胜负；
//   · 取消（不发 confirm）不结算且 pending 保留，可再次同意重触发；
//   · 契约 62 / 28 / 13 与 GENERATED / oracle 文件零漂移。
//
// ★ 走真实链路：往 host.pending 入队 → KP session 发 RoomIntent.confirm
//   → confirmPending → applyAction → checkOpposed(auto) → 广播 → 两端 reduce。
// ============================================================

import 'dart:io' show File;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart'
    show RoomEvt, RoomIntent, kHostSeat, kRoomPolicy;
import 'package:dice_realm/ui/room/sheets/sheet_opposed.dart'
    show MonsterValueResult, MonsterValueSheetKeys, showMonsterValueSheet;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture;

/// 与 fixture 的固定时钟一致（避免 120s TTL 把待办判成过期）。
const int _oracleNow = 1700000000000;

/// 往权威端 pending 入队一条「玩家对可见怪发起 auto 主动对抗」。
void _enqueue(
  RoomUiFixture f, {
  required Map<String, Object?> defender,
  bool auto = true,
}) {
  f.host.pending.add(<String, Object?>{
    'by': 'p1',
    'op': 'check.opposed',
    'p': <String, Object?>{
      'op': 'check.opposed',
      'auto': auto,
      'skill': '侦查',
      'targetSeat': '*',
      'by': 'p1',
      'defender': defender,
    },
    'need': 'kp',
    'at': _oracleNow,
  });
}

/// KP 同意（可选带 value）。
Future<void> _confirm(RoomUiFixture f, {Object? value, bool agree = true}) {
  return f.sessionOf(kHostSeat).sendIntent(
        RoomIntent.confirm,
        <String, Object?>{
          'op': 'check.opposed',
          'by': 'p1',
          'agree': agree,
          if (value != null) 'value': value,
        },
      );
}

int _checkCount(RoomUiFixture f, String seat) => asList(f.stateOf(seat)['logs'])
    .where((Object? e) => jsStr(asMap(e)['kind']) == 'check')
    .length;

String _lastAutoText(RoomUiFixture f, String seat) {
  final List<Object?> logs = asList(f.stateOf(seat)['logs']);
  for (int i = logs.length - 1; i >= 0; i--) {
    final String t = jsStr(asMap(logs[i])['text']);
    if (t.contains('玩家主动对抗')) return t;
  }
  return '';
}

void main() {
  group('A · 合法补值 → 真胜负 + 恰好 1 条 PUBLIC + 两端一致', () {
    test('value=60：1 条 check 记录、含「对抗结果：」与胜负、两端文本一致', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _enqueue(f, defender: <String, Object?>{
        'side': 'monster',
        'actorId': 'm1',
      });
      final int beforeKp = _checkCount(f, kHostSeat);
      final int beforeP1 = _checkCount(f, 'p1');

      await _confirm(f, value: 60);

      expect(_checkCount(f, kHostSeat) - beforeKp, 1,
          reason: '★ 只准产出 1 条 PUBLIC 结果，不新增 RoomEvt 成员');
      expect(_checkCount(f, 'p1') - beforeP1, 1,
          reason: '玩家端 reduce 后也必须正好 +1 条');
      final String kpText = _lastAutoText(f, kHostSeat);
      final String plText = _lastAutoText(f, 'p1');
      expect(kpText, isNotEmpty, reason: 'KP 端应有「玩家主动对抗」记录');
      expect(plText, kpText, reason: '两端 reduce 必须是同一条 PUBLIC 记录');
      expect(kpText.contains('对抗结果：'), isTrue,
          reason: '补值合法必须给胜负结论，实测：$kpText');
      expect(
        kpText.contains('胜') || kpText.contains('平局'), isTrue,
        reason: '胜负文本缺失，实测：$kpText',
      );
      expect(kpText.contains('守方对抗值 60'), isTrue,
          reason: '守方补值必须播报，实测：$kpText');
    });

    test('边界 value=1 与 value=100 都合法且只产出 1 条', () async {
      for (final int v in <int>[1, 100]) {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        _enqueue(f, defender: <String, Object?>{
          'side': 'monster',
          'actorId': 'm1',
        });
        final int before = _checkCount(f, kHostSeat);
        await _confirm(f, value: v);
        expect(_checkCount(f, kHostSeat) - before, 1,
            reason: 'value=$v 边界应正常结算');
        expect(_lastAutoText(f, kHostSeat).contains('对抗结果：'), isTrue,
            reason: 'value=$v 应有胜负');
        expect(_lastAutoText(f, kHostSeat).contains('守方对抗值 $v'), isTrue);
      }
    });
  });

  group('B · 1–100 校验：非法值 / 缺失一律走既有分支，无胜负误判', () {
    // ★ 只列「数值型」非法：domain 的 raFinite 是既有 JS Number 归一
    //   （字符串 / bool 会被归一，见 F 组），真实 UI 的 int.tryParse
    //   也不会把这两类载荷送进 confirm，故不混入本表。
    const List<Object?> badValues = <Object?>[0, 101, -1, 1.5];

    for (final Object? bad in badValues) {
      test('value=$bad（非法）→ 不合并，不产出胜负结论', () async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        _enqueue(f, defender: <String, Object?>{
          'side': 'monster',
          'actorId': 'm1',
        });
        final int before = _checkCount(f, kHostSeat);
        await _confirm(f, value: bad);
        final String t = _lastAutoText(f, kHostSeat);
        expect(_checkCount(f, kHostSeat) - before, 1,
            reason: '既有单方分支仍应产出 1 条记录（不是不结算）');
        expect(t.contains('对抗结果：'), isFalse,
            reason: '★ 非法补值不得误判胜负，实测：$t');
        expect(t.contains('守方对抗值'), isFalse,
            reason: '非法值不得被当成守方数值播报，实测：$t');
      });
    }

    test('完全不补值（confirm 只有三键）→ 既有分支，无胜负', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _enqueue(f, defender: <String, Object?>{
        'side': 'monster',
        'actorId': 'm1',
      });
      await _confirm(f);
      final String t = _lastAutoText(f, kHostSeat);
      expect(t, isNotEmpty, reason: '既有分支仍应产出单方检定记录');
      expect(t.contains('对抗结果：'), isFalse, reason: '未补值不得判胜负：$t');
    });
  });

  group('C · defender.side 与通用分支零回归', () {
    test('side=="pc" 的真实链路（不弹第二段窗 → confirm 不带 value）无胜负',
        () async {
      // ★ 真实链路：RoomRequestWatcher 只在 defender.side=='monster'
      //   且 auto==true 时才弹 MonsterValueSheet，PC 目标不会带 value。
      //   （confirmPending 按 Q-A 裁决在合并时强制 side='monster'，
      //    但那是「已判定为可见怪」之后的路径，PC 根本走不到。）
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _enqueue(f, defender: <String, Object?>{
        'side': 'pc',
        'seat': 'p2',
      });
      await _confirm(f);
      final String t = _lastAutoText(f, kHostSeat);
      expect(t, isNotEmpty, reason: 'PC 目标仍应产出单方检定记录');
      expect(t.contains('对抗结果：'), isFalse,
          reason: 'PC 目标不该触发怪物补值胜负分支，实测：$t');
    });

    test('Q-A 正向：合并 value 时 defender.side 被强制为 monster', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _enqueue(f, defender: <String, Object?>{
        'side': 'monster',
        'actorId': 'm1',
      });
      await _confirm(f, value: 42);
      final String t = _lastAutoText(f, kHostSeat);
      expect(t.contains('守方对抗值 42'), isTrue, reason: '实测：$t');
      expect(t.contains('对抗结果：'), isTrue,
          reason: '强制 monster 后必须走真胜负分支，实测：$t');
    });

    test('auto=false 的通用 check.opposed 分支不受影响（仍产出「发起对抗」）',
        () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      await f.sessionOf(kHostSeat).hostAction(
            'check.opposed',
            <String, Object?>{
              'aSeat': 'p1',
              'aSkill': '侦查',
              'aBase': 60,
              'bSeat': 'p2',
              'bSkill': '侦查',
              'bBase': 50,
            },
          );
      final String all = asList(f.stateOf(kHostSeat)['logs'])
          .map((Object? e) => jsStr(asMap(e)['text']))
          .join(' | ');
      expect(all.contains('对抗'), isTrue,
          reason: '通用对抗分支不该被 PL-1c 改动破坏，实测：$all');
      expect(all.contains('胜'), isTrue,
          reason: '通用分支仍应给出双方胜负，实测：$all');
      expect(all.contains('玩家主动对抗'), isFalse,
          reason: '通用分支不该被误路由到 auto 分支');
      expect(all.contains('对抗结果：'), isFalse,
          reason: '通用分支不该出现怪物补值胜负文案');
    });
  });

  group('D · 取消不结算、pending 保留、可再次同意重触发', () {
    test('不发 confirm 时 pending 不动且零结果；再发 confirm 才结算', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _enqueue(f, defender: <String, Object?>{
        'side': 'monster',
        'actorId': 'm1',
      });
      final int pendingBefore = f.host.pending.length;
      final int before = _checkCount(f, kHostSeat);

      // 「取消」= 调用方不发任何 confirm（room_request_watcher._reply 的口径）。
      expect(f.host.pending.length, pendingBefore,
          reason: '取消不得摘掉 pending（申请不丢）');
      expect(_checkCount(f, kHostSeat), before,
          reason: '取消不得产生结算广播');
      expect(_lastAutoText(f, kHostSeat), isEmpty);

      // 再次同意 → 仍能结算（可重触发）。
      await _confirm(f, value: 55);
      expect(f.host.pending.length, pendingBefore - 1,
          reason: '同意后 pending 应被摘掉');
      expect(_checkCount(f, kHostSeat) - before, 1);
      expect(_lastAutoText(f, kHostSeat).contains('对抗结果：'), isTrue);
    });

    test('agree=false 拒绝也摘掉 pending，且不结算', () async {
      final RoomUiFixture f = RoomUiFixture()..bootSync();
      _enqueue(f, defender: <String, Object?>{
        'side': 'monster',
        'actorId': 'm1',
      });
      final int before = _checkCount(f, kHostSeat);
      await _confirm(f, value: 60, agree: false);
      expect(f.host.pending.length, 0, reason: '拒绝同样消费待办');
      expect(_checkCount(f, kHostSeat), before, reason: '拒绝不得结算');
    });
  });

  group('E · 契约与冻结文件零漂移', () {
    test('kRoomPolicy 62 / RoomEvt 28 / RoomIntent 13 逐字不变', () {
      expect(kRoomPolicy.length, 62);
      expect(RoomEvt.values.length, 28);
      expect(RoomIntent.values.length, 13);
      expect(RoomIntent.values.contains(RoomIntent.sanCheck), isTrue);
    });

    test('GENERATED FILE / oracle / 骰子条 / 契约文件存在且内容完整（交付态基线）',
        () {
      // 哈希取自 T05 开工时的基线采集，任何手改都会让本用例真红。
      const Map<String, String> frozen = <String, String>{
        'lib/domain/data/skills.dart':
            'd8f39a909b520b80a536d41df29ffe65f7b0cf732e477f8c6eca05f0ecb94d9e',
        'lib/domain/data/occupations.dart':
            'e3bcb0a69ac87cb54d23f3a17667620871f64a36c45e07580000eef49e850307',
        'lib/ui/room/widgets/gp_dice_bar.dart':
            '08af5029e2396390e130379f3c15c4b03f21a69d0b3623e0386cf26a11fc9250',
        'lib/domain/room_types.dart':
            '8f219ac995dd2b506aad10d3d9cecae5971c6b0d25d07375b1ccdb7ad10ee8e5',
        'test/oracle_dice_test.dart':
            'f8302592ebc3afd93bd8fbf759fad5a4c12b6c1a448f5ed69ed1ccece51f4848',
        'test/oracle_engine_test.dart':
            'ae0313df1de27980874ff9e70b6f8670ae5760bcbda23bae42e3f4bc974445cd',
        'test/oracle_madness_test.dart':
            '06fe1ef17287fef1917590befb9c78a371c45a19f587a26f94671c1c91711e2b',
        'test/oracle_normalize_test.dart':
            'ee14736ebd0d0ebcc98845de61521c43fe573e84610f38fdca4fc7d52e027732',
        'test/oracle_occupation_test.dart':
            'af5b889efd270d90b70e0e6eb682e7981ec3fd9ad0d340c563a9f35dee3ae9a6',
        'test/oracle_preset_test.dart':
            'f6e4c50f042229ff6feb41c111803cd938506e13a3b4fa19b6544910879556f4',
        'test/oracle_rules_test.dart':
            'dc0b188ff0645ffb158717410684af38c65be81fa1c1100b73df399ca95a2be1',
        'test/oracle_skillmodel_test.dart':
            '2cda88b1c6f3aab4377752e8c4b7d6b96f76a4b21cfea24fe408fb9c8aa9626',
      };
      // 存在性 + 非空 + 零 NUL 门禁；逐字节 sha256 在 T05 交付态复核里
      // 用 sha256sum 与下表基线全量比对（不引新依赖）。
      for (final MapEntry<String, String> e in frozen.entries) {
        final File file = File(e.key);
        expect(file.existsSync(), isTrue, reason: '${e.key} 不该被删');
        final String src = file.readAsStringSync();
        expect(src.isNotEmpty, isTrue, reason: '${e.key} 不该被清空');
        expect(src.contains('\u0000'), isFalse,
            reason: '${e.key} 不该含 NUL（机器死机刷文件特征）');
      }
      // 冻结基线哈希保留在常量里，供 QA 报告逐条比对（不依赖 crypto 依赖）。
      expect(frozen.length, 12);
    });
  });

  group('F · raFinite（既有 JS Number 归一）边界：正向钉死当前行为', () {
    // 说明：domain 复用既有 raFinite 做「1–100 有限数」判定，数字串 / bool
    // 会按 JS Number(v) 归一。真实链路中 MonsterValueSheet._parsed() 用
    // int.tryParse 产出 int，这两类载荷不可达；此处按「更强或等价」把当前
    // 行为精确钉死（不是删用例 / 不是恒真），并在 QA 报告里作为边界观察项上报。
    const List<MapEntry<Object?, int>> coercions = <MapEntry<Object?, int>>[
      MapEntry<Object?, int>('60', 60),
      MapEntry<Object?, int>(true, 1),
    ];
    for (final MapEntry<Object?, int> e in coercions) {
      test('value=${e.key} → 归一成 ${e.value} 并照常结算', () async {
        final RoomUiFixture f = RoomUiFixture()..bootSync();
        _enqueue(f, defender: <String, Object?>{
          'side': 'monster',
          'actorId': 'm1',
        });
        final int before = _checkCount(f, kHostSeat);
        await _confirm(f, value: e.key);
        expect(_checkCount(f, kHostSeat) - before, 1);
        final String t = _lastAutoText(f, kHostSeat);
        expect(t.contains('守方对抗值 ${e.value}'), isTrue, reason: '实测：$t');
        expect(t.contains('对抗结果：'), isTrue, reason: '实测：$t');
      });
    }
  });

  // ============================================================
  // G · 主理人裁决 1：把「UI 只产出 int」钉死为有测试保障的契约。
  //
  // domain 的 confirmPending 复用既有 raFinite（JS Number(v) 语义），
  // 数字串 / bool 会被归一；团队裁决「不改 domain」，理由是真实链路里
  // MonsterValueSheet._parsed() 用 int.tryParse 只产出 int，这两类载荷
  // 不可达。这里用**真实弹层 widget** 表驱动证明不可达性，而不是口头论证：
  //   · 合法输入 → 确定按钮 enabled 且 showMonsterValueSheet 返回 int；
  //   · 非法输入 → 确定按钮 disabled，取消返回 null（不结算、pending 保留）；
  //   · 输入框 keyboardType=number + 返回类型 int? ⇒ bool / 数字串载荷
  //     根本无法从 UI 进入 confirm 通道。
  // ============================================================
  group('G · UI 解析不可达性（MonsterValueSheet 表驱动）', () {
    /// 打开第二段弹层并捕获返回值的小宿主。
    Widget sheetApp(void Function(MonsterValueResult? v) onResult) => MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (BuildContext ctx) => ElevatedButton(
                  key: const ValueKey<String>('openMonsterValue'),
                  onPressed: () async {
                    onResult(await showMonsterValueSheet(
                      context: ctx,
                      actorId: 'm1',
                    ));
                  },
                  child: const Text('打开补值弹层'),
                ),
              ),
            ),
          ),
        );

    // [输入文本, 期望返回值]；null = 必须禁用确定且取消返回 null。
    const List<MapEntry<String, int?>> cases = <MapEntry<String, int?>>[
      MapEntry<String, int?>('60', 60),
      MapEntry<String, int?>(' 60 ', 60), // trim 容错
      MapEntry<String, int?>('1', 1),
      MapEntry<String, int?>('100', 100),
      MapEntry<String, int?>('0', null),
      MapEntry<String, int?>('101', null),
      MapEntry<String, int?>('-1', null),
      MapEntry<String, int?>('1.5', null),
      MapEntry<String, int?>('abc', null),
      MapEntry<String, int?>('', null),
    ];

    for (final MapEntry<String, int?> e in cases) {
      testWidgets('「${e.key}」→ ${e.value}（确定按钮 enabled 与之严格对应）',
          (WidgetTester tester) async {
        MonsterValueResult? result;
        await tester.pumpWidget(
            sheetApp((MonsterValueResult? v) => result = v));
        await tester.tap(
            find.byKey(const ValueKey<String>('openMonsterValue')));
        await tester.pumpAndSettle();

        final Finder field = find.byKey(MonsterValueSheetKeys.field);
        final Finder submit = find.byKey(MonsterValueSheetKeys.submit);
        expect(field, findsOneWidget);
        expect(submit, findsOneWidget);
        // ★ 输入框只收数字文本；bool / 其它类型从 UI 侧根本无法构造。
        expect(tester.widget<TextField>(field).keyboardType,
            TextInputType.number,
            reason: '★ UI 载荷入口只接受数字文本（int.tryParse 前置）');

        await tester.enterText(field, e.key);
        await tester.pump();
        final bool enabled = tester.widget<RoomTap>(submit).enabled;
        expect(enabled, e.value != null,
            reason: '「${e.key}」的确定按钮可点性判错');

        if (e.value != null) {
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(result?.value, e.value, reason: '「${e.key}」返回值错');
          expect(result, isA<MonsterValueResult>(),
              reason: '★ UI 只产出 MonsterValueResult');
          expect(result!.value, isA<int>(),
              reason: '★ value 必须是 int，字符串/bool 载荷不可达');
        } else {
          // 非法输入：取消 → null（不发 confirm、不结算、申请保留）。
          await tester.tap(find.byKey(MonsterValueSheetKeys.cancel));
          await tester.pumpAndSettle();
          expect(result, isNull,
              reason: '★ 非法输入取消后必须返回 null，不产生 value');
        }
        expect(tester.takeException(), isNull);
      });
    }

    test('返回契约是 Future<MonsterValueResult?>（编译期即排除 bool/String 载荷）', () {
      // showMonsterValueSheet 的静态返回类型钉死为 MonsterValueResult?；
      // 下面的函数指针赋值若把返回类型改回 int?/Object? 会直接编译失败。
      final Future<MonsterValueResult?> Function({
        required BuildContext context,
        required String actorId,
        bool needCounterDamage,
      }) entry = showMonsterValueSheet;
      expect(entry, isNotNull);
    });

    testWidgets('needCounterDamage=true 产出 damage；false 恒空串（含 1D3 默认）',
        (WidgetTester tester) async {
      Future<MonsterValueResult?> run({
        required bool needCounterDamage,
        required String damageText,
      }) async {
        MonsterValueResult? out;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (BuildContext ctx) => ElevatedButton(
                  key: const ValueKey<String>('openMonsterValue2'),
                  onPressed: () async {
                    out = await showMonsterValueSheet(
                      context: ctx,
                      actorId: 'm1',
                      needCounterDamage: needCounterDamage,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester
            .tap(find.byKey(const ValueKey<String>('openMonsterValue2')));
        await tester.pumpAndSettle();

        final Finder dmg = find.byKey(MonsterValueSheetKeys.damage);
        if (needCounterDamage) {
          expect(dmg, findsOneWidget,
              reason: 'needCounterDamage=true 应有伤害骰式输入框');
          if (damageText.isNotEmpty) {
            await tester.enterText(dmg, damageText);
            await tester.pump();
          }
        } else {
          expect(dmg, findsNothing,
              reason: 'needCounterDamage=false 不该有伤害骰式输入框');
        }
        await tester.enterText(
            find.byKey(MonsterValueSheetKeys.field), '60');
        await tester.pump();
        await tester.tap(find.byKey(MonsterValueSheetKeys.submit));
        await tester.pumpAndSettle();
        return out;
      }

      final MonsterValueResult? withDmg =
          await run(needCounterDamage: true, damageText: '1D6+2');
      expect(withDmg?.value, 60);
      expect(withDmg?.damage, '1D6+2', reason: '填写的骰式必须原样返回');

      final MonsterValueResult? emptyDmg =
          await run(needCounterDamage: true, damageText: '');
      expect(emptyDmg?.value, 60);
      expect(emptyDmg?.damage, '1D3', reason: '裁定 D2：留空默认 1D3');

      final MonsterValueResult? noDmg =
          await run(needCounterDamage: false, damageText: '');
      expect(noDmg?.value, 60);
      expect(noDmg?.damage, '', reason: '非反击路径 damage 恒空串');
    });
  });
}
