// ============================================================
// test/p16_wave1_domain_test.dart — P16 波1-B（domain / 网络 / 续玩）
//
// ★ 波1 纪律：本文件**写好但暂不执行**（波1 三组并发写码期不跑
//   flutter test），由波2 独占串行验证期统一跑。不得修改任何既有测试。
// ★ 覆盖：KP-2 公开互斥、KP-4① 战斗 HP 双因、KP-8 armor 链路、
//   P-1(a) 按 cid 幂等复连、P-1(b) 独立凭据存储 + 存档隔离红线。
// ★ 断言不放宽、不 skip、不恒真；每条都针对本批真实行为变更。
// ============================================================

import 'dart:convert' show jsonEncode;

import 'package:flutter_test/flutter_test.dart';

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_model_actions_combat.dart';
import 'package:dice_realm/domain/room_model_actions_room.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_reduce.dart' show reduceRoomState;
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_model_state.dart' show roomNumber;
import 'package:dice_realm/domain/room_types.dart';
import 'package:dice_realm/repo/recent_room_credential.dart';
import 'package:dice_realm/ui/room/view/combat_view.dart' show combatRows;

/// 不注入 rules：combatStart 走 initiativeFallback（纯函数，测试更稳）。
RoomHost _host() => RoomHost(RoomHostOptions(
      meta: <String, Object?>{'code': 'TEST01'},
    ));

Map<String, Object?> _asset(String id, String name) => <String, Object?>{
      'id': id,
      'name': name,
      'kind': 'map',
      'data': '',
      'revealed': false,
      'at': 1,
    };

void main() {
  // ----------------------------------------------------------
  // KP-2 公开互斥（domain）
  // ----------------------------------------------------------
  group('KP-2 revealAsset 公开互斥', () {
    test('公开 a2 时 a1 自动取消公开，scene.assets 同时只剩一张', () {
      final h = _host();
      h.localAssets.addAll(<Map<String, Object?>>[
        _asset('a1', '图1'),
        _asset('a2', '图2'),
      ]);
      h.revealAsset('a1', true);
      h.revealAsset('a2', true);

      final revealed =
          h.localAssets.where((a) => a['revealed'] == true).toList();
      expect(revealed.length, 1,
          reason: 'KP-2：同时只能有一张素材公开（KP 侧列表也同步）');
      expect(jsStr(revealed.single['id']), 'a2');

      final assets = asList(asMap(h.state['scene'])['assets']);
      expect(assets.length, 1, reason: '广播出去的公开列也只剩一张');
      expect(jsStr(asMap(assets.single)['id']), 'a2');
    });

    test('被互斥隐藏的旧底图会清理 scene.image', () {
      final h = _host();
      h.localAssets.addAll(<Map<String, Object?>>[
        _asset('a1', '图1'),
        _asset('a2', '图2'),
      ]);
      h.revealAsset('a1', true);
      h.coverAsset('a1');
      expect(jsStr(asMap(h.state['scene'])['image']), 'a1');

      h.revealAsset('a2', true);
      expect(jsStr(asMap(h.state['scene'])['image']), '',
          reason: 'a1 被互斥隐藏后，指向它的 scene.image 必须清掉');
    });

    test('隐藏目标本身仍沿用旧口径（只剔除目标、保留其余公开项）', () {
      final h = _host();
      h.localAssets.addAll(<Map<String, Object?>>[
        _asset('a1', '图1'),
      ]);
      h.revealAsset('a1', true);
      h.revealAsset('a1', false);
      expect(asList(asMap(h.state['scene'])['assets']), isEmpty);
      expect(h.localAssets.single['revealed'], false);
    });
  });

  // ----------------------------------------------------------
  // KP-8 护甲链路（domain 白名单 + combatStart slot）
  // ----------------------------------------------------------
  group('KP-8 armor 链路', () {
    test('setActorPool 白名单保留 armor', () {
      final h = _host();
      h.setActorPool(<String, Object?>{
        'actors': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': '怪',
            'kind': 'monster',
            'hp': 10,
            'armor': 3,
          },
        ],
      });
      expect(h.localActors.length, 1);
      expect(roomNumber(h.localActors.single['armor'], 0), 3);
    });

    test('老载荷不带 armor 时候选池不新增键（守 action oracle 契约）', () {
      final h = _host();
      h.setActorPool(<String, Object?>{
        'actors': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': '怪',
            'kind': 'monster',
            'hp': 10,
          },
        ],
      });
      expect(h.localActors.single.containsKey('armor'), isFalse);
    });
  });

  // ----------------------------------------------------------
  // KP-4① 战斗 HP 显示 0（双因并修）
  // ----------------------------------------------------------
  group('KP-4① 战斗 HP', () {
    test('combatStart 缺 hp 时从候选池补全，且把 armor 写进 slot', () {
      final h = _host();
      // 候选池（权威端 localActors）带完整 hp/hpMax/armor。
      h.setActorPool(<String, Object?>{
        'actors': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': '怪',
            'kind': 'monster',
            'hp': 12,
            'hpMax': 12,
            'armor': 2,
          },
        ],
      });
      // 载荷故意缺 hp/hpMax（旧路径会静默兜底 0）。
      h.combatStart(<String, Object?>{
        'actors': <Object?>[
          <String, Object?>{
            'id': 'm1',
            'name': '怪',
            'kind': 'monster',
            'dex': 50,
            'actionsPerRound': 1,
            'armor': 2,
          },
        ],
      });
      final order = asList(asMap(h.state['combat'])['order']);
      expect(order.length, 1);
      final slot = asMap(order.single);
      expect(roomNumber(asMap(slot['public'])['hp'], 0), 12,
          reason: '缺 hp 必须从 localActors 原值补，不能是 0');
      expect(roomNumber(asMap(slot['public'])['hpMax'], 0), 12);
      expect(roomNumber(slot['armor'], 0), 2,
          reason: 'KP-8：armor 写进 slot 供 :585 的 tSlot[armor] fallback');
    });

    test('RoomEvt.actor 把扁平 actor 写成 public 嵌套', () {
      final state = <String, Object?>{
        'combat': <String, Object?>{'order': <Object?>[]},
        'meta': <String, Object?>{},
      };
      reduceRoomState(
        state,
        RoomEvent(
          t: RoomEvt.actor,
          p: <String, Object?>{
            'actor': <String, Object?>{
              'id': 'm1',
              'name': '怪',
              'kind': 'monster',
              'dex': 40,
              'hp': 9,
              'hpMax': 9,
            },
          },
          vis: RoomVis.public,
        ),
      );
      final order = asList(asMap(state['combat'])['order']);
      expect(order.length, 1);
      final pub = asMap(asMap(order.single)['public']);
      expect(roomNumber(pub['hp'], 0), 9);
      expect(roomNumber(pub['hpMax'], 0), 9);
    });

    test('combatRows 兼容嵌套 public 与扁平 actor 两种结构', () {
      final state = <String, Object?>{
        'combat': <String, Object?>{
          'order': <Object?>[
            <String, Object?>{
              'id': 'n1',
              'kind': 'npc',
              'public': <String, Object?>{
                'hpPublic': true,
                'hp': 7,
                'hpMax': 7,
              },
            },
            <String, Object?>{
              'id': 'f1',
              'kind': 'npc',
              'hp': 5,
              'hpMax': 5,
            },
          ],
          'turn': 0,
        },
        'meta': <String, Object?>{},
      };
      final rows = combatRows(state, isKp: true);
      expect(rows.length, 2);
      expect(rows[0].hp, 7, reason: 'combatStart 的 public 嵌套结构');
      expect(rows[1].hp, 5,
          reason: 'combat.actor / 旧存档的扁平结构必须回退顶层 hp，不能读成 0');
    });
  });

  // ----------------------------------------------------------
  // P-1(a) 按 cid 幂等复连（服务端不新增第二个成员）
  // ----------------------------------------------------------
  group('P-1(a) attachPeer 按 cid 幂等', () {
    test('同 cid 换 seat 重连归一到旧座、不新增成员', () {
      final h = _host();
      final r1 = h.attachPeer(<String, Object?>{
        'seat': 'p1',
        'cid': 'devA',
        'role': RoomRole.player,
        'nickname': '甲',
      });
      expect(r1.seat, 'p1');
      final r2 = h.attachPeer(<String, Object?>{
        'seat': 'p2',
        'cid': 'devA',
        'role': RoomRole.player,
        'nickname': '甲',
      });
      expect(r2.seat, 'p1', reason: '同一设备必须复用旧座');
      expect(h.roster.list().length, 1,
          reason: 'p10_t1 契约：不能出现 2 个玩家');
    });

    test('不带 cid 的同座重连仍复用旧座（p10_t1 契约基线）', () {
      final h = _host();
      h.attachPeer(<String, Object?>{
        'seat': 'p1',
        'role': RoomRole.player,
      });
      final r = h.attachPeer(<String, Object?>{
        'seat': 'p1',
        'role': RoomRole.player,
      });
      expect(r.rejected, isFalse);
      expect(h.roster.list().length, 1);
    });
  });

  // ----------------------------------------------------------
  // P-1(b) 独立凭据存储 + 存档隔离红线
  // ----------------------------------------------------------
  group('P-1(b) recent_room_credential + 存档隔离', () {
    late RecentCredentialStorage prev;

    setUp(() {
      prev = recentCredentialStore;
      recentCredentialStore = MemoryRecentCredentialStorage();
    });
    tearDown(() {
      recentCredentialStore = prev;
    });

    test('save / load / clear 往返，字段逐一对', () {
      saveRecentCredential(
        roomCode: 'ABC123',
        base: 'http://192.168.1.7:4211',
        hostToken: 'tk',
        deviceId: 'fl-abc',
        role: RoomRole.player,
        seat: 'p1',
        savedAt: 123,
      );
      final c = loadRecentCredential('ABC123');
      expect(c, isNotNull);
      expect(c!.roomCode, 'ABC123');
      expect(c.base, 'http://192.168.1.7:4211');
      expect(c.hostToken, 'tk');
      expect(c.deviceId, 'fl-abc');
      expect(c.role, RoomRole.player);
      expect(c.seat, 'p1');
      expect(c.savedAt, 123);
      expect(c.hasBase, isTrue);

      clearRecentCredential('ABC123');
      expect(loadRecentCredential('ABC123'), isNull);
    });

    test('非法 roomCode（路径穿越）被拒', () {
      saveRecentCredential(roomCode: '../evil', base: 'x');
      expect(loadRecentCredential('../evil'), isNull);
      expect(loadRecentCredential(''), isNull);
    });

    test('host.save() 的 20 键不含任何 token / 凭据（存档隔离红线）', () {
      final h = _host();
      final save = h.save();
      for (final k in save.keys) {
        expect(k.toLowerCase().contains('token'), isFalse);
        expect(k.toLowerCase().contains('password'), isFalse);
        expect(k.toLowerCase().contains('credential'), isFalse);
      }
      final wire = jsonEncode(save);
      expect(wire.contains('hostToken'), isFalse);
      expect(wire.contains('recent_room_credential'), isFalse);
    });
  });
}
