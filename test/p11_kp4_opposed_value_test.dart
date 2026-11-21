// ============================================================
// test/p11_kp4_opposed_value_test.dart — KP-4（P0）攻击对抗「数值优先」
//
// 链路：checkOpposed → opposedAttackResolve → defender 合成 → rules.resolveAttack
// 判定：room_model_actions_combat.dart:2369-2383
//   declared = !hasValue && declaredSpec.ok && side != 'pc'
//
// 可观察差异（opposedCheckPayload :2199-2207）：
//   · 非 declared（有 value）：文本含防守 value，如「（闪避 60）」，且「vs 守方 X（掷 N）」；
//   · declared（只有 level）：文本**不含**防守 value（「（闪避）」），
//     且「vs 守方 X（KP 判定）」。
// 因此用「文本是否含 value / 是否 KP 判定」可靠区分两条路径。
//
// 六档等级映射（opposedDeclaredLevelSpec :1553-1608）：
//   level 5→base100/roll1、4→100/20、3→100/50、2→100/51、0→1/2、-1→1/96。
// rules 侧据此把守方等级判成 大成功/极难成功/困难成功/成功/失败/大失败。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture;

/// 直发攻击对抗的最小合法载荷（结构取自 sheet_opposed.dart:792-799）。
Map<String, Object?> _payload({required Map<String, Object?> defender}) =>
    <String, Object?>{
      'attack': true,
      'attacker': <String, Object?>{
        // 用「无卡单位」攻击方（手输 1–100 值），避免依赖 roster 人物卡；
        // KP-4 测的是防守方合成，攻击方形态不影响结论。
        'side': 'monster',
        'name': '调查员',
        'skill': '格斗',
        'value': 50,
      },
      // 默认走「闪避」防守，让 rules 真正计算守方等级文案；调用方可覆盖。
      'defender': <String, Object?>{'reaction': 'dodge', ...defender},
      'weapon': <String, Object?>{
        'name': '拳头',
        'damage': '1D3',
        'skill': '格斗',
      },
      'armor': <String, Object?>{'value': 0},
      'shots': 1,
    };

/// 最近一条「发起对抗」记录文本（无则空串）。
String _lastOpposedText(RoomUiFixture f) {
  final logs = asMap(f.stateOf(kHostSeat))['logs'];
  if (logs is! List) return '';
  for (var i = logs.length - 1; i >= 0; i--) {
    final t = jsStr(asMap(logs[i])['text']);
    if (t.contains('发起对抗')) return t;
  }
  return '';
}

/// 诊断用：全部 log 文本。
String _allLogTexts(RoomUiFixture f) {
  final logs = asMap(f.stateOf(kHostSeat))['logs'];
  if (logs is! List) return '<logs 不是 List: ${logs.runtimeType}>';
  return logs.map((e) => jsStr(asMap(e)['text'])).join(' | ');
}

Future<String> _run(RoomUiFixture f, Map<String, Object?> defender) async {
  await f.kpSession.hostAction('check.opposed', _payload(defender: defender));
  return _lastOpposedText(f);
}

void main() {
  // ----------------------------------------------------------
  // a) 新载荷：有合法 value → 直接用该值，不被 declared base(100/1) 覆盖
  // ----------------------------------------------------------
  group('KP-4a 新载荷：monster + value → 数值优先', () {
    test('value=60 时防守值就是 60，且不走 KP 判定', () async {
      final f = RoomUiFixture()..bootSync();
      final t = await _run(f, <String, Object?>{
        'name': '深潜者',
        'side': 'monster',
        'value': 60,
      });
      expect(t, isNotEmpty, reason: '应产出对抗记录；实际 logs：${_allLogTexts(f)}');
      expect(t.contains('60'), isTrue,
          reason: '防守值必须是载荷的 60，不能被 declared base(100) 覆盖：$t');
      expect(t.contains('KP 判定'), isFalse,
          reason: '有 value 时不该走 declared 六档兜底：$t');
    });

    test('value=1 边界同样生效（最小合法整数）', () async {
      final f = RoomUiFixture()..bootSync();
      final t = await _run(f, <String, Object?>{
        'name': '深潜者',
        'side': 'monster',
        'value': 1,
      });
      expect(t.contains(' 1）'), isTrue, reason: '防守值应为 1：$t');
      expect(t.contains('KP 判定'), isFalse, reason: '$t');
    });
  });

  // ----------------------------------------------------------
  // b) 旧载荷：只有 level → 仍走 declared 六档兜底（旧行为不回归）
  // ----------------------------------------------------------
  group('KP-4b 旧载荷：monster + level → 六档 declared 兜底', () {
    // 逐档：level → rules 侧守方等级文案（base/roll 由 opposedDeclaredLevelSpec 决定）
    const Map<int, String> expectLevelText = <int, String>{
      5: '大成功',
      4: '极难成功',
      3: '困难成功',
      2: '成功',
      0: '失败',
      -1: '大失败',
    };

    for (final MapEntry<int, String> e in expectLevelText.entries) {
      test('level=${e.key} → 走 KP 判定且守方等级为「${e.value}」', () async {
        final f = RoomUiFixture()..bootSync();
        final t = await _run(f, <String, Object?>{
          'name': '深潜者',
          'side': 'monster',
          'level': e.key,
        });
        expect(t, isNotEmpty, reason: '应产出对抗记录');
        expect(t.contains('KP 判定'), isTrue,
            reason: 'level=${e.key} 必须走 declared 兜底：$t');
        expect(t.contains(e.value), isTrue,
            reason: 'level=${e.key} 的守方等级文案应为「${e.value}」：$t');
      });
    }

    test('level 合法时不把 100/1 当成「玩家手输值」播报（文本无防守 value）',
        () async {
      final f = RoomUiFixture()..bootSync();
      final t = await _run(f, <String, Object?>{
        'name': '深潜者',
        'side': 'monster',
        'level': 2,
      });
      // declared 路径 :2202 输出空串 → 防守方括号内没有数字。
      expect(RegExp(r'（闪避 \d+）').hasMatch(t), isFalse,
          reason: 'declared 路径不得显示内部代表值：$t');
    });
  });

  // ----------------------------------------------------------
  // c) 非怪物 / 非法路径：逐字不动（与既有行为一致）
  // ----------------------------------------------------------
  group('KP-4c 非怪物与非法值', () {
    test('side=pc + seat → 走角色卡，level 不触发 declared', () async {
      // 玩家路径需 roster 里有角色卡 → 用 boot()（会 shareSheets）。
      final f = RoomUiFixture();
      await f.boot();
      final t = await _run(f, <String, Object?>{
        'name': '队友',
        'side': 'pc',
        'seat': 'p2',
        'skill': '侦查',
        'level': 2,
      });
      expect(t, isNotEmpty, reason: '应产出对抗记录');
      expect(t.contains('KP 判定'), isFalse,
          reason: 'side=pc 时 level 不触发 declared：$t');
    });

    for (final Object? bad in <Object?>[null, 1.5, 99]) {
      test('level=$bad（非法）→ 非 declared，走 value/提示路径', () async {
        final f = RoomUiFixture()..bootSync();
        await f.kpSession.hostAction(
          'check.opposed',
          _payload(defender: <String, Object?>{
            'name': '深潜者',
            'side': 'monster',
            'level': bad,
            'value': 70,
          }),
        );
        final t = _lastOpposedText(f);
        expect(t.contains('KP 判定'), isFalse,
            reason: 'level=$bad 非法，不该走 declared：$t');
        expect(t.contains('70'), isTrue,
            reason: 'level=$bad 非法时应回落到 value=70：$t');
      });
    }

    for (final Object? bad in <Object?>[0, 101, 1.5]) {
      test('value=$bad（非法）+ 无 level → 明确提示，不静默结算', () async {
        final f = RoomUiFixture()..bootSync();
        await f.kpSession.hostAction(
          'check.opposed',
          _payload(defender: <String, Object?>{
            'name': '深潜者',
            'side': 'monster',
            'value': bad,
          }),
        );
        final t = _lastOpposedText(f);
        // 既没有合法 value 也没有合法 level → 应给出「1–100 对抗值 / 检定等级」提示。
        expect(t.contains('KP 判定'), isFalse, reason: '$t');
        expect(t.contains('${bad}'), isFalse,
            reason: 'value=$bad 非法，不得被当成防守值播报：$t');
      });
    }
  });

  // ----------------------------------------------------------
  // d) 链入口：attack 分派到 opposedAttackResolve
  // ----------------------------------------------------------
  group('KP-4d 链入口分派', () {
    test('attack=true 走攻击对抗（产出「发起对抗」记录）', () async {
      final f = RoomUiFixture()..bootSync();
      await f.kpSession.hostAction('check.opposed', <String, Object?>{
        'attack': true,
        'attacker': <String, Object?>{
          'side': 'monster',
          'name': '调查员',
          'skill': '格斗',
          'value': 50,
        },
        'defender': <String, Object?>{
          'name': '深潜者',
          'side': 'monster',
          'value': 60,
          'reaction': 'dodge',
        },
        'weapon': <String, Object?>{'name': '拳头', 'damage': '1D3'},
        'armor': <String, Object?>{'value': 0},
        'shots': 1,
      });
      expect(_lastOpposedText(f).contains('发起对抗'), isTrue,
          reason: 'attack 必须进 opposedAttackResolve 并产出记录');
    });
  });
}
