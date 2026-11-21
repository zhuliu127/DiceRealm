// ============================================================
// test/qa_p4_c5_writeback_test.dart — 独立复核：C5 房间状态写回（濒死卡不得复活）
//
// ⚠️ 为什么另写一份：`test/room_card_writeback_test.dart` 用的是
//   `newCharacter()` —— 它的 **attributes 全是空串**，于是 derivedStats.maxHP=0、
//   `recalc` 的 `ready` 恒为 false，走的是「属性未填好 → currentHP 保持 0」分支。
//   那条断言在「没有 _hpTouched 保护」的实现下**也会通过**（等于没钉住 D1）。
//   本文件把属性填成真实值（maxHP=12 / maxMP=10），让 `ready=true`，
//   这样「HP=0 不被补满」才真的是 mark 机制在起作用。
//
// 覆盖面：
//   ① currentHP=0 且**未**打 _hpTouched（导入/外部回写的真实形态）→ 写回后仍是 0；
//   ② dying=true 但 HP 是满的（脏卡）→ 写回不得把 dying 清成 false（不得「治活」）；
//   ③ currentSAN=0 + 永久疯狂 → 写回后 SAN 仍 0、mental 不被清空（撕卡语义保持）；
//   ④ 越界值被 recalc 夹回上限（写回不得把 HP 写成 999）；
//   ⑤ 定位规则：charId 命中才写、找不到即 card_not_found、绝不退到 current 别的卡；
//   ⑥ 每次写回**恰好** 1 次 repo.save（C5 唯一落盘入口的实证）。
// ============================================================

import 'dart:convert';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_ports.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/room_state_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计真实后端被写了几次。
class _CountingStorage implements CharacterStorage {
  _CountingStorage([Map<String, Map<String, Object?>>? seed])
      : _inner = MemoryStorage(seed);

  final MemoryStorage _inner;
  int saves = 0;

  @override
  String? get location => null;

  @override
  Future<Map<String, Map<String, Object?>>> load() => _inner.load();

  @override
  Future<void> save(Map<String, Map<String, Object?>> cards) async {
    saves += 1;
    await _inner.save(cards);
  }
}

/// 一张**属性齐全**的卡（这样 maxHP>0，recalc 的 ready 分支才会真的跑）。
///
/// ⚠️ `_inited` 必须显式为 true：否则 `recalc` 会先走「首次有效初始化」
/// （engine.dart:127）把 currentHP 直接写成满值 —— 那是**另一条**分支，
/// 会把「标记守卫是否生效」这件事掩盖掉。真实旧卡（legacy_card_export.json:89）
/// 本身就带 `_inited: true`，所以这也是更贴近生产的形态。
Character _readyCard(String id) {
  final c = Character(newCharacter());
  c.raw['id'] = id;
  for (final e in <String, Object?>{
    'str': 50,
    'con': 60,
    'siz': 60,
    'dex': 50,
    'app': 50,
    'int': 60,
    'pow': 50,
    'edu': 60,
    'luck': 50,
  }.entries) {
    c.attributes[e.key] = e.value;
  }
  c.status['_inited'] = true;
  c.status['maxHP'] = 12;
  c.status['currentHP'] = 12;
  c.status['maxMP'] = 10;
  c.status['currentMP'] = 10;
  c.status['maxSAN'] = 50;
  c.status['currentSAN'] = 50;
  c.status['currentLuck'] = 50;
  return c;
}

Future<CharacterRepo> _repoWith(List<Character> cards, _CountingStorage out) async {
  final seed = <String, Map<String, Object?>>{};
  for (final c in cards) {
    seed[c.id] = c.toJson();
  }
  final repo = CharacterRepo(storage: out);
  await out.save(seed); // 直接铺底，不计入 saves（下面清零）
  await repo.load();
  out.saves = 0;
  return repo;
}

void main() {
  test('前置：属性齐全的卡 maxHP>0（否则下面所有断言都是空转）', () async {
    final card = _readyCard('c1');
    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[card], storage);
    await repo.save(repo.get('c1')!);
    final st = repo.get('c1')!.status;
    expect(jsNum(st['maxHP']), greaterThan(0),
        reason: 'maxHP 仍为 0 → recalc 走的是「未就绪」分支，D1 断言会假绿');
    expect(jsNum(st['currentHP']), jsNum(st['maxHP']),
        reason: '健康卡保存后应满血');
  });

  test('① currentHP=0 且未打标记：写回后仍是 0（濒死卡不得被 recalc 治活）', () async {
    final dying = _readyCard('c1');
    dying.status['currentHP'] = 0;
    dying.status['maxHP'] = 12;
    dying.status['body'] = '重伤';
    dying.status['dying'] = true;
    // 真实形态：从旧 JSON 导入的卡没有任何 _hpTouched
    expect(dying.status.containsKey('_hpTouched'), isFalse);

    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[dying], storage);
    final sink = CharacterRepoRoomCardSink(repo);

    // 房间侧只写 body（不带 currentHP）——这正是 stateSelf 之外的常见 patch 形状
    final res = await sink.write(RoomCardPatch(
      charId: 'c1',
      patch: <String, Object?>{
        'status': <String, Object?>{'body': '重伤'},
      },
    ));
    expect(res.ok, isTrue);
    expect(storage.saves, 1, reason: '写回必须恰好 1 次 repo.save（C5）');

    final st = repo.get('c1')!.status;
    expect(jsNum(st['currentHP']), 0,
        reason: '★D1 复活：濒死卡 HP=0 被 recalc 补满了');
    expect(jsTruthy(st['dying']), isTrue, reason: 'dying 标记被清掉');
    expect(st['_hpTouched'], isTrue,
        reason: '未打 _hpTouched → 说明写回没走 repo.save 的标记通道');
  });

  test('② dying=true 但 HP 满（脏卡）：写回不得把 dying 清成 false', () async {
    final dirty = _readyCard('c2');
    dirty.status['currentHP'] = 12;
    dirty.status['maxHP'] = 12;
    dirty.status['body'] = '重伤';
    dirty.status['dying'] = true;

    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[dirty], storage);
    final sink = CharacterRepoRoomCardSink(repo);
    await sink.write(RoomCardPatch(
      charId: 'c2',
      patch: <String, Object?>{
        'status': <String, Object?>{'body': '重伤'},
      },
    ));
    final st = repo.get('c2')!.status;
    expect(jsTruthy(st['dying']), isTrue,
        reason: 'HP 满 + dying=true 是脏卡，但 recalc 不该替玩家「治活」');
    expect(jsNum(st['currentHP']), 12);
  });

  test('③ currentSAN=0 + 永久疯狂：写回后 SAN 仍 0、mental 不被清空', () async {
    final mad = _readyCard('c3');
    mad.status['currentSAN'] = 0;
    mad.status['mental'] = <Object?>['永久疯狂'];

    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[mad], storage);
    final sink = CharacterRepoRoomCardSink(repo);
    await sink.write(RoomCardPatch(
      charId: 'c3',
      patch: <String, Object?>{
        'status': <String, Object?>{'currentSAN': 0},
        'mental': <Object?>['永久疯狂'],
      },
    ));
    final card = repo.get('c3')!;
    expect(jsNum(card.status['currentSAN']), 0,
        reason: '★SAN=0 被 recalc 补回（永久疯狂卡被治活）');
    expect(asList(card.status['mental']), contains('永久疯狂'));
    expect(isRippedCard(card), isTrue, reason: '永久疯狂必须仍算撕卡');
  });

  test('④ 越界值被夹回上限（写 999 不得落成 999）', () async {
    final c = _readyCard('c4');
    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[c], storage);
    final sink = CharacterRepoRoomCardSink(repo);
    await sink.write(RoomCardPatch(
      charId: 'c4',
      patch: <String, Object?>{
        'status': <String, Object?>{'currentHP': 999, 'currentMP': 999, 'currentSAN': 999},
      },
    ));
    final st = repo.get('c4')!.status;
    expect(jsNum(st['currentHP']), jsNum(st['maxHP']),
        reason: 'currentHP 未被 clamp 到 maxHP');
    expect(jsNum(st['currentMP']), jsNum(st['maxMP']));
    expect(jsNum(st['currentSAN']), lessThanOrEqualTo(99));
  });

  test('⑤ 定位规则：charId 命中才写；找不到即 card_not_found 且不动任何卡', () async {
    final a = _readyCard('cA');
    final b = _readyCard('cB');
    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[a, b], storage);
    final sink = CharacterRepoRoomCardSink(repo);
    final before = jsonEncode(repo.rawCards);

    final miss = await sink.write(RoomCardPatch(
      charId: 'nope',
      patch: <String, Object?>{
        'status': <String, Object?>{'currentHP': 1},
      },
    ));
    expect(miss.ok, isFalse);
    expect(miss.reason, 'card_not_found');
    expect(storage.saves, 0, reason: '定位失败竟然也落盘了');
    expect(jsonEncode(repo.rawCards), before, reason: '定位失败改动了别的卡');

    // 未绑定卡 + 指定 currentCardId → 走 current
    final sink2 = CharacterRepoRoomCardSink(repo, currentCardId: 'cB');
    final hit = await sink2.write(RoomCardPatch(
      patch: <String, Object?>{
        'status': <String, Object?>{'currentHP': 5},
      },
    ));
    expect(hit.ok, isTrue);
    expect(hit.source, 'current');
    expect(jsNum(repo.get('cB')!.status['currentHP']), 5);
    expect(jsNum(repo.get('cA')!.status['currentHP']), 12,
        reason: '写到了另一张卡上（旧版「写错卡」的根因）');

    // 未绑定卡 + 没有 current → no_card，且不落盘
    final storage3 = _CountingStorage();
    final repo3 = await _repoWith(<Character>[_readyCard('cX')], storage3);
    final none = await CharacterRepoRoomCardSink(repo3).write(
      RoomCardPatch(patch: <String, Object?>{
        'status': <String, Object?>{'currentHP': 1},
      }),
    );
    expect(none.ok, isFalse);
    expect(none.reason, 'no_card');
    expect(storage3.saves, 0);
  });

  test('附：既有的 room_card_writeback_test 夹具是「属性为空」的卡 → 那条 D1 断言只覆盖未就绪分支', () async {
    // test/room_card_writeback_test.dart:59 用 newCharacter() 造卡，
    // 它的 attributes 全是空串 → derivedStats.maxHP = 0 →
    // engine.dart:127 的 `ready` 为 false → 走「属性未填好 → currentHP 保持 0」分支。
    // 也就是说：即使把 applyExplicitStatusMarks（D1 的保护）整段删掉，
    // 那条 `expect(currentHP, 0)` 依然会通过 —— 它并没有钉住 D1。
    final bare = Character(newCharacter());
    bare.raw['id'] = 'c0';
    bare.status['currentHP'] = 0;
    bare.status['maxHP'] = 10;
    bare.status['dying'] = true;
    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[bare], storage);
    await repo.save(repo.get('c0')!);
    final st = repo.get('c0')!.status;
    expect(jsNum(st['maxHP']), 0,
        reason: '属性为空时 maxHP 会被 recalc 重算成 0（说明 ready=false）');
    expect(jsNum(st['currentHP']), 0,
        reason: '未就绪分支本来就把 currentHP 归 0 —— 这条断言无法区分「有保护」与「没保护」');
    expect(st['_hpTouched'], isTrue,
        reason: 'mark 通道仍会打标记，只是断言本身辨不出差别');
  });

  test('⑥ 写回不做「明文键」直灌：patch 里多出来的键不落进 status', () async {
    final c = _readyCard('c5');
    final storage = _CountingStorage();
    final repo = await _repoWith(<Character>[c], storage);
    final sink = CharacterRepoRoomCardSink(repo);
    await sink.write(RoomCardPatch(
      charId: 'c5',
      patch: <String, Object?>{
        'status': <String, Object?>{
          'currentHP': 6,
          'secret': 'KP 私有',
          'kpOnly': <String, Object?>{'x': 1},
          'attrs': <String, Object?>{'str': 1},
          'token': 'abc',
        },
      },
    ));
    final st = repo.get('c5')!.status;
    expect(st.containsKey('secret'), isFalse, reason: '明文键 secret 落进了角色卡');
    expect(st.containsKey('kpOnly'), isFalse);
    expect(st.containsKey('attrs'), isFalse);
    expect(st.containsKey('token'), isFalse);
  });
}
