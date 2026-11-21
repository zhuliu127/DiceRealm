// ============================================================
// test/room_save_test.dart — S4.4 存档 / 恢复 / 白名单正式验收（T08）
//
// A) room_model.json 里 6 类 fn 共 25 例（此前从未实跑的 D21 相关用例）
//    全部接入 RoomOracleFixture.run 的严格逐字段深比较 + randUsed：
//      sanitizeSheet 6 / sanitizeSceneSteps 4 / parseSave 5 /
//      restoreHost 2 / playerViewFromSave 2 / applyStateToCard 6
// B) Dart-only：P0-M12 save() 恰好 20 键、savePayload JSON 形状、
//    adoptSave 幂等 + body 迁移 + online=false、playerViewFromSave 可喂
//    receive、sanitizeSheet 不信任客户端数字、TEMP_COMMIT 不进 save、
//    RoomSaveStore 内存后端可注入。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_ports.dart';
import 'package:dice_realm/repo/room_save_store.dart' as repo_store;
import 'package:flutter_test/flutter_test.dart';

import 'support/oracle.dart' show oracleNowMs;
import 'support/room_fakes.dart';
import 'support/room_oracle.dart';

/// 复刻旧版 `M.applyStateToCard(store, charId, patch)` 的 fixture 形状。
///
/// 旧版接收的是 store 对象（getState / saveNow），Dart 侧拆成了纯函数
/// `resolveRoomCardPatch(patch, cards, current)` + repo 适配器，所以这里把
/// store 形状翻译成纯函数入参，并按旧版各分支重建返回体的**键集合**
/// （ok=true 四键 / card_not_found 三键 / no_card·no_store 两键）。
Object? _applyStateToCardForFixture(Map<String, Object?> a) {
  final storeState = a['storeState'];
  if (storeState == null) {
    return <String, Object?>{
      'res': <String, Object?>{'ok': false, 'reason': 'no_store'},
      'saved': 0,
    };
  }
  final st = asMap(storeState);
  final cards = <String, Map<String, Object?>>{};
  asMap(st['characters']).forEach((k, v) {
    cards[k] = asMap(v);
  });
  final current = st['current'] == null ? null : asMap(st['current']);
  final patch = RoomCardPatch(
    charId: a['charId'] == null ? null : jsStr(a['charId']),
    patch: asMap(a['patch']),
  );
  final res = resolveRoomCardPatch(patch, cards, current);
  final json = <String, Object?>{'ok': res.ok, 'reason': res.reason};
  if (res.ok || res.reason == 'card_not_found') json['cardId'] = res.cardId;
  if (res.ok) json['source'] = res.source;
  return <String, Object?>{'res': json, 'saved': res.ok ? 1 : 0};
}

/// 与 `dump_p4_room.js` 的 twoPeerOps() 一致的初始房间。
RoomHost _legacyHost() {
  final h = RoomHost(roomHostOpts(meta: <String, Object?>{'code': 'abcd'}));
  h.attachPeer(<String, Object?>{
    'seat': 'p1',
    'nickname': '甲',
    'at': 1,
  });
  h.attachPeer(<String, Object?>{
    'seat': 'p2',
    'nickname': '乙',
    'at': 2,
  });
  return h;
}

void main() {
  final fixture = RoomOracleFixture.load('room_model.json');

  // ==========================================================
  // A) 旧版预言机：D21 相关 25 例严格逐字段等价
  // ==========================================================
  group('S4.4 存档纯函数 · 旧版逐字段等价（25 例）', () {
    fixture.run(
      <String, Object? Function(Map<String, Object?> args)>{
        'sanitizeSheet': (a) => sanitizeSheet(a['p']),
        'sanitizeSceneSteps': (a) => sanitizeSceneSteps(a['arr']),
        'parseSave': (a) => parseSave(a['payload']),
        'restoreHost': (a) {
          final h = restoreHost(a['save']);
          if (h == null) return null;
          return <String, Object?>{
            'state': h.state,
            'logSeq': h.log.seq,
            'members': h.roster.dump(),
          };
        },
        'playerViewFromSave': (a) =>
            playerViewFromSave(a['save'], jsStr(a['seat']))?.toJson(),
        'applyStateToCard': _applyStateToCardForFixture,
      },
      only: <String>{
        'sanitizeSheet',
        'sanitizeSceneSteps',
        'parseSave',
        'restoreHost',
        'playerViewFromSave',
        'applyStateToCard',
      },
    );
  });

  // ==========================================================
  // B) P0-M12 / P1-05 Dart-only 判据
  // ==========================================================
  group('P0-M12 · save() 20 键 / adoptSave / 裁剪视图', () {
    test('save() 恰好 20 个顶层键，且与旧版 S:legacy#1034 逐字段一致', () {
      setClock(() => oracleNowMs);
      final h = _legacyHost();
      final saved = h.save();
      expect(saved.length, 20, reason: 'PRD 笔误写 19，实测是 20（设计 §0.4）');
      expect(saved.keys.toList(), <String>[
        'v',
        'code',
        'rules',
        'savedAt',
        'seq',
        'stateSeq',
        'meta',
        'members',
        'chats',
        'logs',
        'dice',
        'scene',
        'combat',
        'sceneCheck',
        'roundStarts',
        'privateBySeat',
        'requestsBySeat',
        'boardBySeat',
        'localAssets',
        'localActors',
      ]);
      expect(saved['v'], 2);
      expect(saved['savedAt'], oracleNowMs);

      // 与 oracle dump 出的旧版 save 结果做严格深比较（键集合双向差集）。
      final seq = RoomOracleFixture.load('room_sequences.json');
      final legacy = seq.cases.firstWhere(
        (c) => jsStr(c['name']) == 'S:legacy#1034',
      );
      final legacyExpect = asMap(legacy['expect']);
      expectJsonMatch(saved, legacyExpect['save'], r'$.save');
      expect(asList(legacyExpect['saveKeys']), saved.keys.toList());
    });

    test('savePayload() 是 save() 的 JSON 序列化，往返逐字段一致', () {
      setClock(() => oracleNowMs);
      final h = _legacyHost();
      final decoded = jsonDecode(h.savePayload());
      expectJsonMatch(decoded, h.save(), r'$.savePayload');
      expect(h.savePayload().startsWith('{"v":2,'), isTrue);
    });

    test('adoptSave：老 JSON 无损 + body 一次性迁移 + online=false + 幂等', () {
      setClock(() => oracleNowMs);
      final src = _legacyHost();
      final save = <String, Object?>{
        ...src.save(),
        'seq': 7,
        'stateSeq': 4,
        'members': <Object?>[
          <String, Object?>{
            'seat': 'p1',
            'role': 'player',
            'online': true,
            'sheet': <String, Object?>{
              'name': '甲',
              'status': <String, Object?>{
                'body': '濒死',
                'currentHP': 0,
                'maxHP': 10,
              },
            },
          },
        ],
      };
      final h = RoomHost(roomHostOpts());
      h.adoptSave(asMap(jsonDecode(jsonEncode(save))));

      // state.members 是存档原样 clone（老 JSON 无损，不做重洗）。
      expectJsonMatch(h.state['members'], save['members'], r'$.state.members');
      // roster 侧跑一次 body 迁移：濒死 → 重伤 + dying:true，并统一离线。
      final mem = h.roster.dump().single;
      expect(mem['online'], isFalse);
      expect(asMap(asMap(mem['sheet'])['status'])['body'], '重伤');
      expect(asMap(asMap(mem['sheet'])['status'])['dying'], isTrue);
      expect(asMap(asMap(mem['sheet'])['status'])['currentHP'], 0);
      // 水位 / 快照 / 队列 / Q6 休眠项。
      expect(h.log.seq, 7);
      expect(h.stateSeq, 4);
      expect(h.snapshots.length, 1);
      expect(h.snapshots.single.seq, 7);
      expect(h.pending, isEmpty);
      expect(h.rewind, isNull);
      expect(h.state.containsKey('rewind'), isTrue,
          reason: 'Q6 休眠项：state.rewind 字段不许被删');

      // 幂等：同一份存档再 adopt 一次，逐字段不变。
      final before = jsonEncode(h.save());
      h.adoptSave(asMap(jsonDecode(jsonEncode(save))));
      expect(jsonEncode(h.save()), before);
    });

    test('playerViewFromSave 的 sync 信封可直接喂 RoomClient.receive', () {
      setClock(() => oracleNowMs);
      final src = _legacyHost();
      final save = <String, Object?>{...src.save(), 'seq': 9};
      final env = playerViewFromSave(save, 'p1');
      expect(env, isNotNull);
      final wire = env!.toJson();
      expect(wire['k'], 'sync');
      expect(wire['seq'], 9);
      final c = RoomClient(seat: 'p1', meta: asMap(save['meta']));
      final r = c.receive(wire);
      expect(asMap(r.toJson())['kind'], 'sync');
      expect(c.lastSeq, 9);
    });

    test('sanitizeSheet 白名单：权威端不信任客户端数字，输出键集合固定', () {
      setClock(() => oracleNowMs);
      final out = sanitizeSheet(<String, Object?>{
        'sheet': <String, Object?>{
          'name': '越权',
          'attrs': <String, Object?>{'str': 99999, 'con': -7},
          'status': <String, Object?>{
            'currentHP': -50,
            'maxHP': 99999,
            'body': '伪字段',
          },
          'sanLoss': 500,
          'db': '+1D4',
          '不该出现': 'x',
        },
      });
      expect(out.keys.toSet(), <String>{
        'name',
        'charId',
        'avatar',
        'attrs',
        'status',
        'skills',
        'madness',
        'mental',
        'sanLoss',
        'maxSAN',
        'san',
        'hp',
        'mp',
        'tempStatus',
        'items',
        'weapons',
        'db',
        'at',
      });
      expect(asMap(out['attrs'])['str'], 999);
      expect(asMap(out['attrs'])['con'], 0);
      expect(asMap(out['status'])['currentHP'], 0);
      expect(asMap(out['status'])['maxHP'], 9999);
      expect(asMap(out['status'])['body'], '正常');
      expect(out['sanLoss'], 99);
      expect(out.containsKey('不该出现'), isFalse);
      expect(out['at'], oracleNowMs);
    });

    test('TEMP_COMMIT 是事件不是状态键：advanceRound 后 save 仍恰好 20 键', () {
      setClock(() => oracleNowMs);
      final h = _legacyHost();
      final before = h.save().keys.toSet();
      h.advanceRound(2);
      final after = h.save();
      expect(after.keys.toSet(), before);
      expect(after.containsKey('tempCommit'), isFalse);
      expect(after.containsKey('tempcommit'), isFalse);
    });

    test('RoomSaveStore 内存后端可注入：put/get/list 且 get 是深拷贝', () {
      setClock(() => oracleNowMs);
      final store = repo_store.InMemoryRoomSaveStore();
      final data = _legacyHost().save();
      store.put('abcd', data);
      expect(store.list(), <String>['abcd']);
      expectJsonMatch(store.get('abcd')!, data, r'$.get');
      // 改动返回值不应污染仓库内部
      store.get('abcd')!['code'] = 'zzzz';
      expect(asMap(store.get('abcd'))['code'], 'abcd');
      expect(store.get('missing'), isNull);
      expect(store.length, 1);
    });
  });
}
