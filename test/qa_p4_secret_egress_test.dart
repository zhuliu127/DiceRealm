// ============================================================
// test/qa_p4_secret_egress_test.dart — 独立复核：KP 秘密的**其他出口**
//
// 工程师的 805 例主要走 `emit` 路径（那条已经 scrub 过，测了等于没测）。
// 本文件的攻击方式：
//   ① 直接把隐藏字段**注入权威态**（state.combat / state.members 的 sheet），
//      再逐个出口探：planAll / cropFor / combatFor / syncFor / save() /
//      playerViewFromSave —— 这是「先广播再隐藏」的漏点高发区。
//   ② 对同一 SEAT 秘密 CHECK 造**变体**（改文案 / 改 seat / 改 seq / 加额外字段），
//      验证 rollback 重放后每个在线座位的载荷字节级干净（Q1 不得只钉住一个脚本）。
//   ③ 断言「不得出现」用**递归键集合**而不是字符串 contains：
//      `hpPublic` 含子串 `hp`，用 contains 会假红（K14 的同款坑）。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';

/// 任何情况下都不得出现在**未授权**载荷里的键（与白名单的 forbiddenKeys 同源，
/// 另加 kSecretKeys 里的 7 个）。
const List<String> kQaForbiddenKeys = <String>[
  'secret',
  'hidden',
  'kpOnly',
  'truth',
  'clue',
  'spoiler',
  'answer',
];

/// 递归收集所有 Map 的键。
void _collectKeys(Object? v, Set<String> out) {
  if (v is Map) {
    for (final e in v.entries) {
      out.add('${e.key}');
      _collectKeys(e.value, out);
    }
    return;
  }
  if (v is List) {
    for (final x in v) {
      _collectKeys(x, out);
    }
  }
}

/// 递归收集所有字符串值（用于「明文不得出现」的字节级断言）。
void _collectStrings(Object? v, List<String> out) {
  if (v is Map) {
    for (final e in v.entries) {
      _collectStrings(e.value, out);
    }
    return;
  }
  if (v is List) {
    for (final x in v) {
      _collectStrings(x, out);
    }
    return;
  }
  if (v is String) out.add(v);
}

/// 三人在线房间（全部 online=true，确保 skip / 逐人裁剪都真的发出去）。
RoomHost _threeSeatHost({int snapshotEvery = 20}) {
  final h = RoomHost(roomHostOpts(snapshotEvery: snapshotEvery));
  h.attachPeer(<String, Object?>{'seat': 'p1', 'nickname': '甲', 'at': 1});
  h.attachPeer(<String, Object?>{'seat': 'p2', 'nickname': '乙', 'at': 2});
  h.attachPeer(<String, Object?>{'seat': 'p3', 'nickname': '丙', 'at': 3});
  return h;
}

/// 断言某份出站载荷里既无私有键、也无给定明文串。
void _expectClean(
  Object? payload,
  String where, {
  List<String> plaintexts = const <String>[],
}) {
  final keys = <String>{};
  _collectKeys(payload, keys);
  final hit = keys.where(kQaForbiddenKeys.contains).toList();
  expect(hit, isEmpty, reason: '$where：泄漏了私有键 $hit');
  if (plaintexts.isEmpty) return;
  final strs = <String>[];
  _collectStrings(payload, strs);
  for (final p in plaintexts) {
    final leaked = strs.where((s) => s.contains(p)).toList();
    expect(leaked, isEmpty, reason: '$where：明文「$p」出现在出站载荷里 → $leaked');
  }
}

void main() {
  // ==========================================================
  // ① Q1 变体：同一 SEAT 秘密 CHECK，改文案 / 改 seat / 改 seq / 加字段
  // ==========================================================
  group('Q1 变体 · rollback 重放后每个在线座位的载荷字节级干净', () {
    /// 造一个「秘密 CHECK + 定向私密 + 回退」的脚本并返回 (host, 明文串)。
    ({RoomHost host, String secret, String toSeat}) runVariant({
      required String summary,
      required String toSeat,
      int snapshotEvery = 1,
      Map<String, Object?> extra = const <String, Object?>{},
    }) {
      final h = _threeSeatHost(snapshotEvery: snapshotEvery);
      h.emit(
        RoomEvt.chat,
        <String, Object?>{
          'seat': kHostSeat,
          'nickname': 'KP',
          'text': '开始',
          'at': 1,
        },
        vis: RoomVis.public,
      );
      // ★ 关键：SEAT 事件不 scrub，隐藏字段真的进了事件对象
      h.emit(
        RoomEvt.check,
        <String, Object?>{
          'summary': summary,
          'seat': toSeat,
          'at': 3,
          'kind': 'check',
          ...extra,
        },
        vis: RoomVis.seat,
        to: toSeat,
      );
      h.emit(
        RoomEvt.private_,
        <String, Object?>{'title': '只给 $toSeat', 'text': '线索A', 'at': 4},
        vis: RoomVis.seat,
        to: toSeat,
      );
      h.emit(
        RoomEvt.chat,
        <String, Object?>{'seat': 'p1', 'text': '然后呢', 'at': 5},
        vis: RoomVis.public,
      );
      // 回退到「秘密事件之后、私密事件之前」→ 重放区间包含秘密事件。
      // 注意：_threeSeatHost 的 3 次 attach 已占掉 seq 1~3，
      // 所以秘密事件在 seq5、私密事件在 seq6 → rollback(6) 的 target 是 5。
      h.rollback(6);
      return (host: h, secret: summary, toSeat: toSeat);
    }

    void assertVariant(
      ({RoomHost host, String secret, String toSeat}) r,
      String label,
    ) {
      final h = r.host;
      // 权威态：只许有脱敏行
      final logs = asList(h.state['logs']);
      final checkRows =
          logs.map(asMap).where((l) => l['kind'] == 'check').toList();
      expect(checkRows, isNotEmpty, reason: '$label：权威态应保留 1 条 check 行');
      for (final row in checkRows) {
        expect(row['text'], 'KP 秘密进行了一次检定', reason: '$label：脱敏文案被改');
        expect(row['seat'], '', reason: '$label：脱敏行不得带座位');
        expect(row['redacted'], isTrue, reason: '$label：redacted 标记丢失');
      }
      // state.privates 不得含定向私密
      expect(asList(h.state['privates']), isEmpty,
          reason: '$label：定向私密混进了 state.privates');

      // 每个在线座位：syncFor / planAll / save / playerViewFromSave 全部干净
      for (final seat in <String>['p1', 'p2', 'p3', 'spectator-x']) {
        _expectClean(h.syncFor(seat).toJson(), 'syncFor($seat)/$label',
            plaintexts: <String>[r.secret]);
      }
      // 增量分发：只对**非授权收件人**的载荷断言（发给 toSeat 本人的 evt 是正常的）
      for (final j in h.planAll(h.log.items).map((p) => p.toJson())) {
        final msg = asMap(j['msg']);
        final authorized = msg['k'] == 'evt' && j['to'] == r.toSeat;
        if (authorized) continue;
        _expectClean(msg, 'planAll(${j['to']})/$label',
            plaintexts: <String>[r.secret]);
      }
      final saveJson = h.save();
      _expectClean(saveJson, 'save()/$label', plaintexts: <String>[r.secret]);
      for (final seat in <String>['p1', 'p2', 'p3']) {
        final view = playerViewFromSave(saveJson, seat);
        expect(view, isNotNull, reason: '$label：playerViewFromSave($seat) 为 null');
        _expectClean(view!.toJson(), 'playerViewFromSave($seat)/$label',
            plaintexts: <String>[r.secret]);
      }
    }

    test('变体 A：基线文案 + 定向 p1', () {
      assertVariant(
        runVariant(summary: '秘密检定：骰出 07，极难成功', toSeat: 'p1'),
        'A',
      );
    });

    test('变体 B：改文案（含 HP 数字与怪物真名）', () {
      assertVariant(
        runVariant(summary: '暗骰 1D100=13/45 困难成功（HP 9/14，真名：深潜者）', toSeat: 'p1'),
        'B',
      );
    });

    test('变体 C：改收件人 seat 到 p3（不是第一个座位）', () {
      assertVariant(
        runVariant(summary: 'p3 的侦查：骰出 88，失败', toSeat: 'p3'),
        'C',
      );
    });

    test('变体 D：chunk 加额外隐藏字段（hp/hpMax/attrs/攻击值）', () {
      assertVariant(
        runVariant(
          summary: '秘密对抗：怪物 STR 80 胜出',
          toSeat: 'p2',
          extra: <String, Object?>{
            'hp': 9,
            'hpMax': 20,
            'attrs': <String, Object?>{'str': 80, 'con': 65},
            'kpOnly': <String, Object?>{'真名': '深潜者'},
          },
        ),
        'D',
      );
    });

    test('变体 E：snapshotEvery=3（秘密事件落在快照之后的重放区间）', () {
      assertVariant(
        runVariant(
          summary: '秘密检定：骰出 03，大成功',
          toSeat: 'p1',
          snapshotEvery: 3,
        ),
        'E',
      );
    });

    test('变体 F：多次回退（回退后再回退，重放路径不得退回明文）', () {
      final h = _threeSeatHost(snapshotEvery: 1);
      h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p1', 'text': 'a', 'at': 1},
          vis: RoomVis.public);
      h.emit(
        RoomEvt.check,
        <String, Object?>{'summary': '秘密检定：07', 'seat': 'p1', 'at': 2},
        vis: RoomVis.seat,
        to: 'p1',
      );
      h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p1', 'text': 'b', 'at': 3},
          vis: RoomVis.public);
      // attach 占 seq1~2；chat a=3；check=4；chat b=5
      h.rollback(5); // target 4 → 重放区间 (2,4] 含秘密事件
      h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p2', 'text': 'c', 'at': 4},
          vis: RoomVis.public);
      h.rollback(5); // 再回退一次，重放区间再次包含秘密事件
      for (final seat in <String>['p1', 'p2', 'p3']) {
        _expectClean(h.syncFor(seat).toJson(), 'syncFor($seat)/F',
            plaintexts: <String>['秘密检定：07']);
      }
      final rows = asList(h.state['logs'])
          .map(asMap)
          .where((l) => l['kind'] == 'check')
          .toList();
      expect(rows.every((r) => r['redacted'] == true), isTrue,
          reason: 'F：二次回退后出现了未脱敏的 check 行');
    });

    test('变体 G：秘密事件之后 logCap 截断（补拉窗口外的明文不进 save）', () {
      final h = RoomHost(roomHostOpts(snapshotEvery: 1, logCap: 3));
      h.attachPeer(<String, Object?>{'seat': 'p1', 'at': 1});
      h.attachPeer(<String, Object?>{'seat': 'p2', 'at': 2});
      h.emit(
        RoomEvt.check,
        <String, Object?>{'summary': '秘密检定：骰出 01', 'seat': 'p1', 'at': 1},
        vis: RoomVis.seat,
        to: 'p1',
      );
      for (var i = 0; i < 6; i++) {
        h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p1', 'text': 'x$i'},
            vis: RoomVis.public);
      }
      _expectClean(h.syncFor('p2').toJson(), 'syncFor(p2)/G',
          plaintexts: <String>['秘密检定：骰出 01']);
      _expectClean(h.save(), 'save()/G', plaintexts: <String>['秘密检定：骰出 01']);
    });
  });

  // ==========================================================
  // ①b 增量补拉（intent SYNC）是**另一条**出站路径：不能只钉 syncFor
  // ==========================================================
  group('增量补拉 · SEAT 秘密不得随 canFill 补齐发给别人', () {
    test('p2 请求补拉时只收到 skip 水位，收不到秘密 CHECK 的原文', () {
      final h = _threeSeatHost(snapshotEvery: 10);
      final to = h.log.seq;
      h.emit(
        RoomEvt.check,
        <String, Object?>{
          'summary': '秘密检定：骰出 04，大成功',
          'seat': 'p1',
          'at': 9,
          'hp': 7,
          'secret': '真名',
        },
        vis: RoomVis.seat,
        to: 'p1',
      );
      h.emit(RoomEvt.chat, <String, Object?>{'seat': 'p1', 'text': '好'},
          vis: RoomVis.public);
      final out = h.intent('p2', <String, Object?>{
        'op': RoomIntent.sync,
        'p': <String, Object?>{'lastSeq': to},
      });
      expect(out, isNotEmpty);
      // p2 只应拿到 skip（或与己无关的公共事件），绝不能拿到那条 SEAT CHECK
      for (final plan in out) {
        final j = plan.toJson();
        final msg = asMap(j['msg']);
        if (msg['k'] == 'evt' && msg['t'] == RoomEvt.check) {
          fail('增量补拉把 SEAT CHECK 原文发给了 ${j['to']}');
        }
        _expectClean(msg, 'intent(sync) → ${j['to']}',
            plaintexts: <String>['秘密检定：骰出 04，大成功']);
      }
      // p1（收件人）应当拿得到
      final forP1 = h.intent('p1', <String, Object?>{
        'op': RoomIntent.sync,
        'p': <String, Object?>{'lastSeq': to},
      });
      final gotCheck = forP1.any((p) {
        final msg = asMap(p.toJson()['msg']);
        return msg['k'] == 'evt' && msg['t'] == RoomEvt.check;
      });
      expect(gotCheck, isTrue, reason: '收件人本人反而收不到自己的秘密检定');
    });
  });

  // ==========================================================
  // ② 其他出口：隐藏字段注入权威态后逐个探
  // ==========================================================
  group('KP 秘密的其他出口（注入权威态，不走 emit）', () {
    RoomHost hiddenStateHost() {
      final h = _threeSeatHost();
      // 成员卡：sheet 里塞隐藏键（模拟 KP 端持有全量卡）
      final m1 = h.roster.get('p1')!;
      m1['sheet'] = <String, Object?>{
        'name': '张三',
        'avatar': 'a.png',
        'status': <String, Object?>{
          'currentHP': 7,
          'maxHP': 12,
          'currentSAN': 33,
          'maxSAN': 60,
          'body': '正常',
          'dying': false,
          'unconscious': false,
        },
        'mental': <Object?>['正常'],
        'madness': <Object?>[],
        'secret': 'KP 对张三的秘密笔记',
        'kpOnly': <String, Object?>{'真名': '不可名状'},
        'attrs': <String, Object?>{'str': 60},
        'skills': <Object?>[
          <String, Object?>{'id': 'spot', 'total': 70, 'hidden': true},
        ],
      };
      final m2 = h.roster.get('p2')!;
      m2['sheet'] = <String, Object?>{
        'name': '李四',
        'status': <String, Object?>{'currentHP': 5, 'maxHP': 9},
      };
      // 战斗：怪物槽 hpPublic=false，槽内带 secret/kpOnly/attrs
      h.state['combat'] = <String, Object?>{
        'order': <Object?>[
          <String, Object?>{
            'id': 'pc-p1',
            'actorId': 'pc-p1',
            'name': '张三',
            'kind': 'pc',
            'seat': 'p1',
            'public': <String, Object?>{
              'hp': 7,
              'hpMax': 12,
              'hpPublic': true,
            },
          },
          <String, Object?>{
            'id': 'm1',
            'actorId': 'm1',
            'name': '深潜者',
            'kind': 'npc',
            'public': <String, Object?>{
              'hp': 30,
              'hpMax': 30,
              'hpPublic': false,
            },
            'secret': '怪物真名：深潜者',
            'kpOnly': <String, Object?>{'san': 8},
            'attrs': <String, Object?>{'str': 80},
          },
        ],
        'turn': 0,
        'round': 1,
      };
      // 场景素材：隐藏真相
      h.state['scene'] = <String, Object?>{
        'title': '码头',
        'image': '',
        'assets': <Object?>[
          <String, Object?>{
            'id': 'a1',
            'name': '公开图',
            'revealed': true,
          },
        ],
        'marks': <Object?>[],
        'strokes': <Object?>[],
        'boards': <String, Object?>{},
      };
      return h;
    }

    test('combatFor：非 KP 座位拿不到 secret/kpOnly/attrs，且未公开的怪物 hp 被剥', () {
      final h = hiddenStateHost();
      for (final seat in <String>['p1', 'p2', 'p3', 'outside']) {
        final view = h.combatFor(seat)!;
        _expectClean(view, 'combatFor($seat)');
        final order = asList(view['order']);
        final monster = order.map(asMap).firstWhere((s) => s['id'] == 'm1');
        final pub = asMap(monster['public']);
        expect(pub.containsKey('hp'), isFalse,
            reason: 'combatFor($seat)：未公开的怪物 HP 仍在载荷里');
        expect(pub.containsKey('hpMax'), isFalse,
            reason: 'combatFor($seat)：未公开的怪物 hpMax 仍在载荷里');
        // PC 的 HP 是公开的（hpPublic=true），不应被误删
        final pc = order.map(asMap).firstWhere((s) => s['id'] == 'pc-p1');
        expect(asMap(pc['public'])['hp'], 7,
            reason: 'combatFor($seat)：公开的 PC HP 被误删');
      }
      // KP 拿全量
      final hostView = h.combatFor(kHostSeat)!;
      final hostMonster =
          asList(hostView['order']).map(asMap).firstWhere((s) => s['id'] == 'm1');
      expect(asMap(hostMonster['public'])['hp'], 30,
          reason: 'combatFor(host)：KP 视图丢了怪物 HP');
    });

    test('cropFor：战斗/成员类事件逐人裁剪；非战斗事件原样（不二次过滤）', () {
      final h = hiddenStateHost();
      final combatPayload = <String, Object?>{'combat': h.state['combat']};
      final cropped = h.cropFor(RoomEvt.combat, combatPayload, 'p2');
      _expectClean(cropped, 'cropFor(combat,p2)');
      final raw = h.cropFor(RoomEvt.chat, <String, Object?>{'text': 'hi'}, 'p2');
      expect(raw['text'], 'hi');
      // 成员事件：别人的 sheet 只留白名单键
      final membersPayload = <String, Object?>{'members': h.members()};
      final mc = h.cropFor(RoomEvt.members, membersPayload, 'p2');
      _expectClean(mc, 'cropFor(members,p2)');
      final p1View = asList(mc['members']).map(asMap).firstWhere(
            (m) => m['seat'] == 'p1',
          );
      final sheet = asMap(p1View['sheet']);
      expect(sheet.containsKey('secret'), isFalse);
      expect(sheet.containsKey('kpOnly'), isFalse);
      expect(sheet.containsKey('attrs'), isFalse);
      expect(sheet.containsKey('skills'), isFalse);
      // 本人视图保留全量
      final self = h.cropFor(RoomEvt.members, membersPayload, 'p1');
      final selfP1 =
          asList(self['members']).map(asMap).firstWhere((m) => m['seat'] == 'p1');
      expect(asMap(selfP1['sheet']).keys, contains('name'),
          reason: 'cropFor 本人视图应保留自己的完整 sheet');
    });

    test('syncFor：隐藏字段注入后每个座位的全量同步仍然干净', () {
      final h = hiddenStateHost();
      for (final seat in <String>['p1', 'p2', 'p3', 'outside']) {
        final view = h.syncFor(seat).toJson();
        // ⚠️ 本人视图（seat == 自己的 seat）按设计返回**自己的完整 sheet**
        //（`_cropMember` 的 isSelf 分支），所以私有键断言只对「别人」成立。
        // 当前唯一写入点 sanitizeSheet 是白名单，故 self 视图里不可能真有
        // kpOnly/secret；这里记录该语义，见报告的防御性建议。
        if (seat != 'p1') {
          _expectClean(view, 'syncFor($seat)');
          _expectClean(view, 'syncFor($seat)', plaintexts: <String>['KP 对张三的秘密笔记']);
        }
        // 任何人都看不到怪物未公开 HP
        final combat = asMap(asMap(view['state'])['combat']);
        final order = asList(combat['order']).map(asMap).toList();
        final monster = order.firstWhere((s) => s['id'] == 'm1');
        expect(asMap(monster['public']).containsKey('hp'), isFalse,
            reason: 'syncFor($seat)：未公开的怪物 HP 泄露');
      }
    });

    test('playerViewFromSave：存档裁剪视图与 syncFor 同口径', () {
      final h = hiddenStateHost();
      final save = h.save();
      for (final seat in <String>['p1', 'p2', 'p3']) {
        final view = playerViewFromSave(save, seat)!;
        if (seat != 'p1') {
          _expectClean(view.toJson(), 'playerViewFromSave($seat)');
          _expectClean(view.toJson(), 'playerViewFromSave($seat)',
              plaintexts: <String>['KP 对张三的秘密笔记']);
        }
      }
    });

    test('save() 是 KP 存档：含全量（这是**要求**，不是泄漏）但不得含令牌', () {
      final h = hiddenStateHost();
      final save = h.save();
      // KP 存档必须能续玩 → 隐藏字段应保留
      final order = asList(asMap(save['combat'])['order']).map(asMap).toList();
      final monster = order.firstWhere((s) => s['id'] == 'm1');
      expect(monster['secret'], '怪物真名：深潜者',
          reason: 'save() 丢了 KP 私有内容（无法续玩）');
      // 但绝不能带任何令牌 / 密码类键
      final keys = <String>{};
      _collectKeys(save, keys);
      for (final k in <String>['token', 'password', 'pwd', 'auth', 'secretKey']) {
        expect(keys.contains(k), isFalse, reason: 'save() 出现凭据类键 $k');
      }
      // 存档可 JSON 序列化（无循环 / 无非法类型）
      expect(() => jsonEncode(save), returnsNormally);
    });

    test('顶层 actor 携带 hp（非 public 结构）时：记录当前裁剪覆盖范围', () {
      final h = _threeSeatHost();
      h.state['combat'] = <String, Object?>{
        'order': <Object?>[
          <String, Object?>{
            'id': 'm2',
            'kind': 'npc',
            'name': '食尸鬼',
            // 非规范结构：hp 在槽顶层（不是 public.hp）
            'hp': 22,
            'hpMax': 22,
            'public': <String, Object?>{'hpPublic': false},
            'secret': '真名',
          },
        ],
        'turn': 0,
        'round': 1,
      };
      final view = h.combatFor('p2')!;
      final slot = asList(view['order']).map(asMap).first;
      expect(slot.containsKey('secret'), isFalse, reason: 'secret 必须剥掉');
      // 现状记录：顶层 hp/hpMax 未被剥离（裁剪只认 public.hp）——
      // 当前生成路径（combatStart/combatEnqueue/stampSlotBody）一律写 public.hp，
      // 故不可达；仅当 KP 客户端上报非规范 actor 形状时才会外泄。
      expect(slot.containsKey('hp'), isTrue,
          reason: '若此处变 false 说明裁剪已加强（好事，请同步更新本探针）');
    });
  });
}
