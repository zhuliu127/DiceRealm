// ============================================================
// room_view_test.dart — S1.2 纯视图层验收（设计 §5/T01、§6.4）
//
// 八条铁律里与本文件相关的：T6（断言权威侧数据形状，不断言 UI 文案）、
// T7（hostRead 不在 state 里）、T8（跨视角用裁剪后的 state）。
// 本文件全部是**纯 Dart 断言**：不起 widget 树、不 pump、不依赖屏幕尺寸。
// ============================================================

import 'dart:io';

import 'package:dice_realm/ui/room/room_theme.dart';
import 'package:dice_realm/ui/room/view/combat_view.dart';
import 'package:dice_realm/ui/room/view/feed_view.dart';
import 'package:dice_realm/ui/room/view/member_view.dart';
import 'package:dice_realm/ui/room/view/room_view.dart';
import 'package:dice_realm/ui/room/view/scene_view.dart';
import 'package:dice_realm/ui/room/view/sheet_view.dart';
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------
// 测试夹具：只造 state 形状，不碰 Host / Client / Flutter
// ------------------------------------------------------------

Map<String, Object?> _state({
  List<Object?>? logs,
  List<Object?>? dice,
  List<Object?>? chats,
  List<Object?>? privates,
}) =>
    <String, Object?>{
      'meta': <String, Object?>{
        'code': 'R1',
        'name': '测试团',
        'kpName': '守密人',
        'status': 'IN_GAME',
        'mode': 'COMBAT',
        'round': 3,
      },
      'members': <Object?>[],
      'logs': logs ?? <Object?>[],
      'dice': dice ?? <Object?>[],
      'chats': chats ?? <Object?>[],
      'privates': privates ?? <Object?>[],
      'scene': null,
      'combat': null,
      'board': null,
      'sceneCheck': null,
    };

Map<String, Object?> _member({
  Map<String, Object?>? status,
  Map<String, Object?>? runtime,
  Map<String, Object?>? sheetExtra,
}) =>
    <String, Object?>{
      'seat': 'p1',
      'nickname': '甲',
      'role': 'player',
      'sheet': <String, Object?>{
        'status': <String, Object?>{...?status},
        ...?sheetExtra,
      },
      // 恒带 runtime 键（null 会被 asMap 收成空 Map），避免条件条目 lint。
      'runtime': runtime,
    };

Map<String, Object?> _combatState() {
  final order = <Object?>[];
  for (var i = 0; i < 5; i++) {
    if (i == 0) {
      order.add(<String, Object?>{
        'id': 'm1',
        'name': '怪物',
        'kind': 'npc',
        'seat': '',
        'totalSlots': 1,
        'public': <String, Object?>{'hpPublic': false, 'state': '正常'},
      });
      continue;
    }
    order.add(<String, Object?>{
      'id': 'p$i#1',
      'name': '玩家$i',
      'kind': 'pc',
      'seat': 'p$i',
      'totalSlots': 1,
      'public': <String, Object?>{
        'hpPublic': true,
        'hp': i == 1 ? 0 : 5,
        'hpMax': 10,
        'state': '正常',
      },
    });
  }
  return <String, Object?>{
    'meta': <String, Object?>{'round': 3},
    'combat': <String, Object?>{
      'turn': 1,
      'round': 3,
      'order': order,
    },
  };
}

/// §3.9 契约的编译期钉子：六个成员一个不少、一个不多地能实现。
class _FakeStage implements MapStageController {
  bool _awaiting = false;
  String color = '';
  double width = 0;

  @override
  void beginStroke({required String color, required double width}) {
    this.color = color;
    this.width = width;
    _awaiting = true;
  }

  @override
  void beginErase() => _awaiting = true;

  @override
  void beginMark({
    required String kind,
    required String label,
    bool revealed = true,
  }) =>
      _awaiting = true;

  @override
  void beginPlace({String? actorName, String? playerSeat}) => _awaiting = true;

  @override
  void cancel() => _awaiting = false;

  @override
  bool get awaitingTap => _awaiting;
}

void main() {
  group('S1.2 · RoomGridSpec 五档阈值（§1.5）', () {
    test('五个常量只在这里出现一次', () {
      expect(RoomGridSpec.wide, 820);
      expect(RoomGridSpec.narrowLo, 520);
      expect(RoomGridSpec.narrowHi, 599);
      expect(RoomGridSpec.minH, 290);
      expect(RoomGridSpec.compactH, 360);
    });

    test('360×640 竖屏 → 单列、非 compact', () {
      final s = RoomGridSpec.of(w: 360, h: 640, landscape: false);
      expect(s.grid, isFalse);
      expect(s.compact, isFalse);
    });

    test('780×320 横屏 → 网格 + compact', () {
      final s = RoomGridSpec.of(w: 780, h: 320, landscape: true);
      expect(s.grid, isTrue);
      expect(s.compact, isTrue);
    });

    test('560×320 横屏（520–599 窄档）→ 不 grid 也不 compact', () {
      final s = RoomGridSpec.of(w: 560, h: 320, landscape: true);
      expect(s.grid, isFalse, reason: '窄档必须强制单列');
      expect(s.compact, isFalse, reason: 'compact 不能简化成独立 h<=360');
    });

    test('900×290 宽屏极矮边界 → grid + compact', () {
      final s = RoomGridSpec.of(w: 900, h: 290, landscape: false);
      expect(s.grid, isTrue);
      expect(s.compact, isTrue);
    });

    test('900×289 → 高度不足，单列', () {
      final s = RoomGridSpec.of(w: 900, h: 289, landscape: false);
      expect(s.grid, isFalse);
      expect(s.compact, isFalse);
    });

    test('480×800 竖屏 → 单列', () {
      final s = RoomGridSpec.of(w: 480, h: 800, landscape: false);
      expect(s.grid, isFalse);
      expect(s.compact, isFalse);
    });

    test('compact 恒蕴含 grid（遍历档位组合）', () {
      for (final w in <double>[360, 480, 520, 560, 599, 600, 780, 819, 820, 900]) {
        for (final h in <double>[280, 289, 290, 320, 360, 361, 640]) {
          for (final landscape in <bool>[false, true]) {
            final s = RoomGridSpec.of(w: w, h: h, landscape: landscape);
            if (s.compact) {
              expect(s.grid, isTrue, reason: '$w×$h landscape=$landscape');
            }
          }
        }
      }
    });
  });

  group('S1.2 · room_view 基础派生', () {
    test('meta / 状态 / 模式 / 身份行', () {
      final s = _state();
      expect(metaOf(s)['code'], 'R1');
      expect(roomStatusText('IN_GAME'), '游戏中');
      expect(roleText('kp'), '主持人');
      expect(roleText('player'), '玩家');
      expect(roleText('spectator'), '旁观者');
      expect(isInGame(s), isTrue);
      expect(isCombat(s), isTrue);
      expect(modeOf(s), 'COMBAT');
      expect(whoLine(s, 'host', 'kp'), '守密人 · KP 主持');
      expect(whoLine(s, 'sp1', 'spectator'), '旁观中');
      expect(codeOf(s), 'R1');
      expect(roomNameOf(s), '测试团');
      expect(kpNameOf(s), '守密人');
      expect(roundOf(s), 3);
    });

    test('members / players / spectators / findMe 不返回 state 引用', () {
      final s = _state();
      s['members'] = <Object?>[
        <String, Object?>{'seat': 'host', 'role': 'kp', 'nickname': 'KP'},
        <String, Object?>{'seat': 'p1', 'role': 'player', 'nickname': '甲'},
        <String, Object?>{'seat': 'p2', 'role': 'player', 'nickname': '乙'},
        <String, Object?>{'seat': 'sp1', 'role': 'spectator', 'nickname': '观'},
      ];
      final list = membersOf(s);
      list.first['nickname'] = '改写副本';
      expect((s['members'] as List<Object?>).first,
          isNot(same(list.first)),
          reason: 'membersOf 必须深拷贝');
      expect((s['members'] as List<Object?>).first is Map, isTrue);
      expect(playersOf(s).length, 2);
      expect(spectatorsOf(s).length, 1);
      expect(findMe(s, 'p1')!['nickname'], '甲');
      expect(memberOfSeat(s, 'sp1')!['role'], 'spectator');
      expect(findMe(s, 'nobody'), isNull, reason: '查不到 = 旁观者');
    });
  });

  group('S1.2 · member_view 双源 / 裁剪 / 判活', () {
    test('S1：status 与 runtime 双源逐个回退', () {
      final s = memberStats(_member(
        status: <String, Object?>{
          'currentHP': 7,
          'maxHP': 10,
          'currentMP': null,
          'currentSAN': 40,
          'maxSAN': 60,
          'body': '正常',
        },
        runtime: <String, Object?>{'mp': 3, 'maxMP': 8},
      ));
      expect(s.hp, 7);
      expect(s.hpMax, 10);
      expect(s.mp, 3);
      expect(s.mpMax, 8);
      expect(s.san, 40);
      expect(s.sanMax, 60);
      expect(s.hasMaxSan, isTrue);
      expect(sanText(s, full: true), 'SAN 40 / 60');
      expect(hpText(s, full: true), 'HP 7 / 10');
      expect(mpText(s, full: false), 'MP 3');
    });

    test('C2：他人视图 maxSAN 为 null → 只显当前值、无斜杠', () {
      final mem = <String, Object?>{
        'seat': 'p2',
        'sheet': <String, Object?>{
          'name': '乙',
          'status': <String, Object?>{
            'currentHP': 5,
            'maxHP': 9,
            'currentSAN': 33,
            'body': '正常',
          },
          'maxSAN': null,
          'sanLoss': null,
          'madnessCount': 2,
        },
      };
      final s = memberStats(mem);
      expect(s.hasMaxSan, isFalse);
      expect(sanText(s, full: true), 'SAN 33');
      expect(sanText(s, full: true).contains('/'), isFalse);
      expect(madnessText(mem, self: false), '不定疯狂 ×2');
      expect(attrRows(mem).first.v, '—', reason: '他人 attrs 整块被删，不能显示 0');
    });

    test('S5：isDown 带 hpMax > 0 守卫', () {
      final hidden = _member(status: <String, Object?>{'currentHP': 0});
      expect(isDown(hidden), isFalse, reason: 'HP 未公开不能判死');
      final dead = _member(status: <String, Object?>{
        'currentHP': 0,
        'maxHP': 10,
        'body': '死亡',
      });
      expect(isDown(dead), isTrue);
      expect(isRipped(dead), isTrue);
      expect(targetBlocked(dead), isTrue);
    });

    test('bodyViewOf 优先级：死亡 > 濒死 > 昏迷 > body', () {
      expect(bodyViewOf(_member(status: <String, Object?>{
        'body': '正常',
        'dying': true,
        'unconscious': true,
      })), '濒死');
      expect(bodyViewOf(_member(status: <String, Object?>{
        'body': '正常',
        'unconscious': true,
      })), '昏迷');
      expect(bodyViewOf(_member(status: <String, Object?>{'body': '死亡'})), '死亡');
      expect(bodyViewOf(_member(status: <String, Object?>{'body': '轻伤'})), '轻伤');
    });

    test('S2 / S7：memberDex 只认 attrs.dex；operationLocked 与权威端同判据', () {
      final mem = <String, Object?>{
        'sheet': <String, Object?>{
          'attrs': <String, Object?>{'dex': 65},
          'status': <String, Object?>{'body': '正常'},
          'mental': <Object?>['临时疯狂'],
        },
        'derivedStats': <String, Object?>{'dex': 999},
      };
      expect(memberDex(mem), 65);
      expect(operationLocked(mem), isTrue);
      expect(isRipped(mem), isFalse);
      expect(madnessText(mem, self: true), '临时疯狂');
    });
  });

  group('S1.2 · feed_view 合并 / 裁剪 / 脱敏', () {
    test('logs + dice 按 at 升序合并（同 at 按 seq）', () {
      final feeds = collectFeeds(_state(
        logs: <Object?>[
          <String, Object?>{'seq': 2, 'at': 20, 'kind': 'info', 'text': '二'},
          <String, Object?>{'seq': 1, 'at': 10, 'kind': 'sys', 'text': '一'},
        ],
        dice: <Object?>[
          <String, Object?>{
            'seq': 3,
            'at': 30,
            'expr': '1D100',
            'total': 42,
            'levelText': '困难成功',
            'nickname': '甲',
            'seat': 'p1',
          },
        ],
      ));
      expect(feeds.length, 3);
      expect(feeds[0].text, '一');
      expect(feeds[1].text, '二');
      expect(feeds[2].kind, FeedKind.dice);
      expect(feeds[2].text, '1D100 → 42 · 困难成功');
      expect(feeds[2].dice, isNotNull, reason: '公开骰才带结构化气泡');
      expect(feeds[2].redacted, isFalse);
    });

    test('cap 120：取最近 120 条且仍为正序', () {
      final logs = <Object?>[
        for (var i = 1; i <= 130; i++)
          <String, Object?>{'seq': i, 'at': i, 'kind': 'info', 'text': '$i'},
      ];
      final feeds = collectFeeds(_state(logs: logs));
      expect(feeds.length, 120);
      expect(feeds.first.text, '11');
      expect(feeds.last.text, '130');
    });

    test('C6/K8：redacted 行只取 text，不还原结果', () {
      final feeds = collectFeeds(_state(logs: <Object?>[
        <String, Object?>{
          'seq': 9,
          'at': 9,
          'kind': 'check',
          'seat': 'p2',
          'text': 'KP 秘密进行了一次检定',
          'opp': null,
          'redacted': true,
          'total': 95,
          'summary': '甲 侦查 困难成功 95',
        },
      ]));
      final f = feeds.single;
      expect(f.redacted, isTrue);
      expect(f.kind, FeedKind.check);
      expect(f.text, 'KP 秘密进行了一次检定');
      expect(f.seat, '');
      expect(f.opp, isNull);
      expect(f.dice, isNull);
      expect(checkLine(f), 'KP 秘密进行了一次检定');
    });

    test('对抗结果卡只做只读数据化，不重算胜负', () {
      final f = collectFeeds(_state(logs: <Object?>[
        <String, Object?>{
          'seq': 5,
          'at': 5,
          'kind': 'check',
          'text': '对抗检定',
          'opp': <String, Object?>{'winner': 'p1', 'tie': false},
        },
      ])).single;
      expect(f.kind, FeedKind.opposed);
      expect(f.opp!['winner'], 'p1');
      expect(checkLine(f), '对抗检定 · p1 胜');
    });

    test('collectChats cap 60', () {
      final chats = <Object?>[
        for (var i = 1; i <= 80; i++)
          <String, Object?>{
            'seq': i,
            'at': i,
            'nickname': 'n$i',
            'text': 'c$i',
          },
      ];
      final rows = collectChats(_state(chats: chats));
      expect(rows.length, 60);
      expect(rows.first.text, 'c21');
      expect(rows.last.nickname, 'n80');
    });

    test('collectPrivates 只留五键、正序、最新在最后', () {
      final privates = <Object?>[
        for (var i = 0; i < 15; i++)
          <String, Object?>{
            'seq': i,
            'title': 't$i',
            'text': 'p$i',
            'at': i,
            'kind': 'info',
            'secret': '不该出现',
          },
      ];
      final rows = collectPrivates(_state(privates: privates));
      expect(rows.length, 12);
      expect(rows.first['text'], 'p3');
      expect(rows.last['text'], 'p14');
      for (final r in rows) {
        expect(r.keys.toSet(), <String>{'seq', 'title', 'text', 'at', 'kind'});
        expect(r.containsKey('secret'), isFalse);
      }
      expect(privRowsOf(_state(privates: privates), 'p1').length, 12);
    });
  });

  group('S1.2 · combat_view 隐藏 HP / 回合', () {
    test('hpPublic==false → hpHidden（不是 0）', () {
      final rows = combatRows(_combatState(), isKp: false);
      expect(rows.length, 5);
      expect(rows[0].hpHidden, isTrue);
      expect(rows[0].hp, 0);
      expect(rows[1].isCurrent, isTrue);
      expect(rows[1].hpHidden, isFalse);
    });

    test('roundText / curSlot / isMyTurn', () {
      final s = _combatState();
      expect(roundText(s), '第 3 轮 · 行动 2/5');
      expect(curSlot(s)!['seat'], 'p1');
      expect(isMyTurn(s, 'p1'), isTrue);
      expect(isMyTurn(s, 'p2'), isFalse);
    });

    test('downRows 含 hpMax>0 守卫', () {
      final rows = combatRows(_combatState(), isKp: false);
      final down = downRows(rows);
      expect(down.length, 1, reason: 'HP 隐藏的怪物不能被判死');
      expect(down.single.id, 'p1#1');
    });
  });

  group('S1.2 · scene_view 归一化与段级擦除', () {
    test('normalizePath / denormalizePath / clampNorm', () {
      const box = NormBox(10, 20, 110, 70);
      final norm = normalizePath(const <NormPoint>[NormPoint(60, 45)], box);
      expect(norm.single.x, closeTo(0.5, 1e-9));
      expect(norm.single.y, closeTo(0.5, 1e-9));
      final back = denormalizePath(norm, box);
      expect(back.single.x, closeTo(60, 1e-9));
      expect(back.single.y, closeTo(45, 1e-9));
      expect(clampNorm(-0.2), 0);
      expect(clampNorm(1.4), 1);
      expect(clampNorm(0.37), closeTo(0.37, 1e-9));
    });

    test('hitStrokeIndex 命中线段、未命中返回 -1', () {
      final strokes = <Map<String, Object?>>[
        <String, Object?>{
          'id': 's1',
          'color': '#e74c3c',
          'width': 3,
          'pts': <Object?>[
            <String, Object?>{'x': 0.1, 'y': 0.1},
            <String, Object?>{'x': 0.9, 'y': 0.9},
          ],
        },
      ];
      expect(hitStrokeIndex(strokes, const NormPoint(0.5, 0.5)), 0);
      expect(hitStrokeIndex(strokes, const NormPoint(0.1, 0.9)), -1);
      expect(hitStrokeIndex(<Map<String, Object?>>[], const NormPoint(0.5, 0.5)), -1);
    });

    test('eraseStrokeSegments 段级擦除且不改入参', () {
      final strokes = <Map<String, Object?>>[
        <String, Object?>{
          'id': 's1',
          'color': '#e74c3c',
          'width': 3,
          'pts': <Object?>[
            <String, Object?>{'x': 0.1, 'y': 0.5},
            <String, Object?>{'x': 0.4, 'y': 0.5},
            <String, Object?>{'x': 0.5, 'y': 0.5},
            <String, Object?>{'x': 0.6, 'y': 0.5},
            <String, Object?>{'x': 0.9, 'y': 0.5},
          ],
        },
      ];
      final out = eraseStrokeSegments(
        strokes,
        const <NormPoint>[NormPoint(0.45, 0.5), NormPoint(0.55, 0.5)],
        tol: 0.06,
      );
      expect(out.length, 2, reason: '中间三点被擦掉，剩下两段');
      expect((out[0]['pts'] as List<Object?>).length, 1);
      expect((out[1]['pts'] as List<Object?>).length, 1);
      expect(out[0]['id'], 's1');
      expect(out[1]['id'], 's1#1');
      expect((strokes[0]['pts'] as List<Object?>).length, 5,
          reason: '入参绝不被修改');
    });

    test('assets / boards / sceneCheck 只读派生', () {
      final s = <String, Object?>{
        'scene': <String, Object?>{
          'assets': <Object?>[
            <String, Object?>{'id': 'a1', 'kind': 'map', 'revealed': true},
            <String, Object?>{'id': 'a2', 'kind': 'map', 'revealed': false},
          ],
          'marks': <Object?>[
            <String, Object?>{'id': 'm1', 'x': 0.2, 'y': 0.3, 'kind': 'dot'},
          ],
          'strokes': <Object?>[],
          'boards': <String, Object?>{
            'p1': <String, Object?>{'count': 7},
          },
        },
        'board': <String, Object?>{
          'strokes': <Object?>[<String, Object?>{'x': 0.1, 'y': 0.2}],
        },
        'sceneCheck': <String, Object?>{
          'cursor': 2,
          'steps': <Object?>[
            <String, Object?>{'text': '一'},
            <String, Object?>{'text': '二'},
            <String, Object?>{'text': '三'},
            <String, Object?>{'text': '四'},
          ],
        },
      };
      expect(assetsOf(s).length, 2);
      expect(assetsOf(s, kind: 'map').length, 2);
      expect(publicAssets(s).length, 1);
      expect(marksOf(s).single['id'], 'm1');
      expect(strokesOf(s), isEmpty);
      expect(boardCountOf(s, 'p1'), 7);
      expect(boardCountOf(s, 'p2'), 0);
      expect(myBoardStrokes(s).length, 1);
      expect(sceneCheckSteps(s).length, 4);
      expect(sceneCheckCursor(s), 2);
      expect(sceneCheckProgress(s), closeTo(0.5, 1e-9));
      expect(rgbOfHex('#e74c3c').argb, 0xffe74c3c);
      expect(sceneOf(<String, Object?>{}), isNull);
    });
  });

  group('S1.2 · sheet_view 角色卡只读派生', () {
    test('vitalsOf / attrRows / skillRows / charStatusText', () {
      final mem = <String, Object?>{
        'seat': 'p1',
        'sheet': <String, Object?>{
          'attrs': <String, Object?>{
            'str': 50,
            'con': 60,
            'siz': 55,
            'dex': 45,
            'app': 50,
            'int': 70,
            'pow': 60,
            'edu': 65,
            'luck': 55,
          },
          'status': <String, Object?>{
            'currentHP': 9,
            'maxHP': 12,
            'currentMP': 4,
            'maxMP': 10,
            'currentSAN': 55,
            'maxSAN': 60,
            'currentLuck': 50,
            'body': '重伤',
            'dying': true,
          },
          'skills': <Object?>[
            <String, Object?>{'name': '侦查', 'total': 60},
            <String, Object?>{'name': '自定', 'value': 30, 'custom': true},
          ],
          'mental': <Object?>['正常'],
          'tempStatus': <Object?>[
            <String, Object?>{'text': '中毒', 'by': 'kp', 'at': 1},
          ],
          'items': <Object?>[
            <String, Object?>{'id': 'i1', 'name': '手电', 'qty': 1},
          ],
        },
      };
      final v = vitalsOf(mem);
      expect(v.hp, 9);
      expect(v.hpMax, 12);
      expect(v.san, 55);
      expect(v.luck, 50);

      final attrs = attrRows(mem);
      expect(attrs.length, 8);
      expect(attrs.first.k, 'STR');
      expect(attrs.first.v, '50');
      expect(attrs[3].k, 'DEX');
      expect(attrs[3].v, '45');

      final skills = skillRows(mem['sheet'] as Map<String, Object?>);
      expect(skills.length, 2);
      expect(skills[0].name, '侦查');
      expect(skills[0].value, 60);
      expect(skills[0].isCustom, isFalse);
      expect(skills[1].value, 30);
      expect(skills[1].isCustom, isTrue);

      expect(charStatusText(mem), '重伤·濒死');
      expect(mentalText(mem), '正常');
      expect(tempStatusOf(mem).single['text'], '中毒');
      expect(itemsOf(mem).single['name'], '手电');
      expect(weaponsOf(mem), isEmpty);
      expect(madnessOf(mem), isEmpty);
    });
  });

  group('S1.2 · 静态门禁与跨任务契约', () {
    test('view/ 六个文件零 Flutter 框架 / 零 UI 库字面量', () {
      final dir = Directory('lib/ui/room/view');
      expect(dir.existsSync(), isTrue, reason: 'view/ 未创建');
      final files = dir
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files.length, 6, reason: 'view/ 应恰好 6 个纯 Dart 文件');

      final offenders = <String>[];
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('package:flutter') ||
              line.contains("'dart:ui'") ||
              line.contains('"dart:ui"')) {
            offenders.add('${f.path}:${i + 1}  ${line.trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'view/ 被 UI 依赖污染：\n${offenders.join('\n')}');
    });

    test('§3.9 MapStageController 六成员可完整实现', () {
      final stage = _FakeStage();
      expect(stage.awaitingTap, isFalse);
      stage.beginStroke(color: '#e74c3c', width: 3);
      expect(stage.awaitingTap, isTrue);
      expect(stage.color, '#e74c3c');
      expect(stage.width, 3);
      stage.beginErase();
      stage.beginMark(kind: 'dot', label: '线索');
      stage.beginPlace(actorName: '怪物');
      stage.cancel();
      expect(stage.awaitingTap, isFalse);
    });

    test('room_theme 常量与画笔 6 色', () {
      expect(kDrawColors.length, 6);
      // ★ KP-2：第 6 色 #e67e22 追加在末尾；前 5 色索引 0–4 顺序即协议、逐字不动。
      expect(kDrawColors[5], '#e67e22');
      expect(RoomTheme.drawColor(5), '#e67e22');
      expect(RoomTheme.drawColor(0), '#e74c3c');
      expect(RoomTheme.drawColor(99), kDrawColors.last, reason: '越界夹回');
      expect(RoomTheme.drawColor(-3), kDrawColors.first);
      expect(RoomTheme.colorArgb('#e74c3c'), 0xffe74c3c);
      expect(RoomTheme.colorArgb('bad'), 0xff000000);
      expect(RoomTheme.tapMinSize, 48);
      expect(RoomTheme.feedCap, 120);
      expect(RoomTheme.chatCap, 60);
      expect(RoomTheme.privateCap, 12);
    });

    test('通用件契约字段存在（T-30 / T-43 抓手）', () {
      const tap = RoomTap(label: '开始游戏', enabled: false, hint: '只有 KP 能开始');
      expect(tap.enabled, isFalse);
      expect(tap.label, '开始游戏');
      expect(tap.minSize.width, 48);
      expect(RoomTap.tapTargetSize, MaterialTapTargetSize.padded);
      const box = SectionBox(title: '标题', child: SizedBox.shrink());
      expect(box.title, '标题');
      expect(box.foldId, isNull);
      const placeholder = PlaceholderBlock(label: '占位');
      expect(placeholder.label, '占位');
    });
  });
}
