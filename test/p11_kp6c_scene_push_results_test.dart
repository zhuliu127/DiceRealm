// ============================================================
// test/p11_kp6c_scene_push_results_test.dart — KP-6c 推全体场景检定一次展开
//
// 被测：room_model_actions_combat.dart
//   · sceneCheckPush（:3030-3052）→ autoAdvanceSceneCheck（:3055-3074）
//   · _resolveAllPlayersSceneStep（:3085-3193）
// 口径（用户拍板 D7）：targetSeat == '*' 时 M 步 × N 在线玩家一次展开，
//   产出 M×N 条 results + 同数 kind:'check' PUBLIC log + **一次** sceneCheck
//   状态更新（cursor 推到末尾），严禁在循环里逐个调 sceneCheckStep。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show kHostSeat;
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture;

/// 构造一个「全体」场景检定步骤。
Map<String, Object?> _step(String id, String skill) => <String, Object?>{
      'id': id,
      'title': skill,
      'skill': skill,
      'targetSeat': '*',
      'difficulty': 1,
    };

/// 推一次全体检定，返回 KP 视角的 sceneCheck。
Future<Map<String, Object?>> _push(
  RoomUiFixture f,
  List<Map<String, Object?>> steps,
) async {
  await f.kpSession.hostAction('scene.check.push', <String, Object?>{
    'title': '快速检定',
    'desc': '',
    'steps': steps,
  });
  return asMap(f.stateOf(kHostSeat)['sceneCheck']);
}

/// 当前 kind=='check' 的公开记录条数。
int _checkLogCount(RoomUiFixture f) {
  final logs = asList(f.stateOf(kHostSeat)['logs']);
  return logs.where((e) => jsStr(asMap(e)['kind']) == 'check').length;
}

void main() {
  group('KP-6c 推全体：M 步 × N 玩家一次展开', () {
    test('1 步 × 2 玩家 → 2 条 result + 2 条 kind:check，cursor 到末尾', () async {
      final f = RoomUiFixture()..bootSync(); // 默认 2 玩家
      final int before = _checkLogCount(f);
      final sc = await _push(f, <Map<String, Object?>>[
        _step('s1', '侦查'),
      ]);

      final results = asList(sc['results']);
      expect(results.length, 1 * f.players,
          reason: '1 步 × ${f.players} 在线玩家 = ${1 * f.players} 条 result');
      expect('${sc['cursor']}', '1', reason: 'cursor 推到 steps.length');
      expect(_checkLogCount(f) - before, 1 * f.players,
          reason: 'kind:check 公开记录同条数');
      // 每条 result 必须带 stepId / seat / level / ok
      for (final r in results) {
        final m = asMap(r);
        expect(jsStr(m['stepId']), 's1');
        expect(jsStr(m['seat']), isNotEmpty);
        expect(m.containsKey('level'), isTrue);
        expect(m.containsKey('ok'), isTrue);
      }
      // 每个在线玩家恰好一条（不重不漏）
      final seats = results.map((r) => jsStr(asMap(r)['seat'])).toList();
      expect(seats.toSet().length, f.players, reason: '按 seat 不重复：$seats');
    });

    test('2 步 × 2 玩家 → 4 条 result + 4 条 kind:check，且不是 cursor 覆盖',
        () async {
      final f = RoomUiFixture()..bootSync();
      final int before = _checkLogCount(f);
      final sc = await _push(f, <Map<String, Object?>>[
        _step('s1', '侦查'),
        _step('s2', '聆听'),
      ]);

      final results = asList(sc['results']);
      expect(results.length, 2 * f.players, reason: 'M=2 × N=${f.players}');
      expect('${sc['cursor']}', '2');
      expect(_checkLogCount(f) - before, 2 * f.players);
      // 两步都在结果里（若被逐次 sceneCheckStep 覆盖，只会剩最后一步）
      final stepIds = results.map((r) => jsStr(asMap(r)['stepId'])).toSet();
      expect(stepIds, <String>{'s1', 's2'},
          reason: '两步都必须保留（cursor 覆盖会让 s1 消失）');
    });

    test('不同玩家技能值不同 → 结果里的 level 由各自角色卡决定（不是同一个值）',
        () async {
      final f = RoomUiFixture()..bootSync();
      // 给 p1 / p2 造不同侦查值
      final host = f.hostState();
      final members = asList(host['members']);
      for (final m in members) {
        final mm = asMap(m);
        final seat = jsStr(mm['seat']);
        if (seat == 'p1' || seat == 'p2') {
          mm['sheet'] = <String, Object?>{
            'name': '卡$seat',
            'skills': <Object?>[
              <String, Object?>{'name': '侦查', 'value': seat == 'p1' ? 90 : 10},
            ],
          };
        }
      }
      final sc = await _push(f, <Map<String, Object?>>[_step('s1', '侦查')]);
      final results = asList(sc['results']);
      expect(results.length, f.players);
      // 至少不是「全部同一 seat」——每人一条，seat 集合等于在线玩家
      final seats = results.map((r) => jsStr(asMap(r)['seat'])).toList();
      expect(seats.toSet(), <String>{'p1', 'p2'});
    });

    test('保留 sys 摘要「KP 推送了场景检定…」', () async {
      final f = RoomUiFixture()..bootSync();
      await _push(f, <Map<String, Object?>>[_step('s1', '侦查')]);
      final logs = asList(f.stateOf(kHostSeat)['logs']);
      final texts = logs.map((e) => jsStr(asMap(e)['text'])).join('\n');
      expect(texts.contains('推送了场景检定'), isTrue,
          reason: 'sceneCheckPush 的 sys 摘要必须保留');
    });

    test('定向单人（targetSeat=p1）不走全体展开（results 为空，等待该玩家）',
        () async {
      final f = RoomUiFixture()..bootSync();
      final sc = await _push(f, <Map<String, Object?>>[
        <String, Object?>{
          'id': 's1',
          'title': '侦查',
          'skill': '侦查',
          'targetSeat': 'p1',
          'difficulty': 1,
        },
      ]);
      expect(asList(sc['results']), isEmpty,
          reason: '定向步骤不在推全体时自动结算');
      expect('${sc['cursor']}', '0');
    });
  });
}
