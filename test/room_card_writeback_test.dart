// ============================================================
// test/room_card_writeback_test.dart — P0-M07 / C5 房间状态写回（T07）
//
//   · 濒死卡 currentHP=0 / dying=true 经房间写回后**不被 recalc 补满**；
//   · 写回路径必过 `CharacterRepo.save()`（唯一落盘入口，C5），
//     因为 applyExplicitStatusMarks→normalize→recalc 都在它内部；
//   · resolveRoomCardPatch 找不到 charId 返回 card_not_found，绝不退到
//     current 别的卡（旧版「写到别人卡上」的根因）；
//   · applySheetState 幂等；
//   · 静态检查：房间写回适配器里恰好 1 处 await repo.save(，domain 零落盘。
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_client.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_ports.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/repo/room_state_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计真实后端被写了几次（证明「写回必过 repo.save」而不是原地改 Map）。
class _CountingStorage implements CharacterStorage {
  _CountingStorage(this.inner);

  final MemoryStorage inner;
  int saves = 0;

  @override
  String? get location => null;

  @override
  Future<Map<String, Map<String, Object?>>> load() => inner.load();

  @override
  Future<void> save(Map<String, Map<String, Object?>> cards) async {
    saves += 1;
    await inner.save(cards);
  }
}

/// 去掉 `//` 行注释，只保留真实代码文本，避免把说明文字里的示例代码
/// 当成一次真实的落盘调用来计数（C5 数的是**代码**，不是注释）。
String _stripLineComments(String src) => src
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

/// currentHP=0 / dying=true / body=重伤 的濒死卡。
Character _dyingCard(String id) {
  final c = Character(newCharacter());
  c.raw['id'] = id;
  c.status['currentHP'] = 0;
  c.status['maxHP'] = 10;
  c.status['body'] = '重伤';
  c.status['dying'] = true;
  return c;
}

void main() {
  group('P0-M07 · 濒死卡房间写回', () {
    test('写回必过 repo.save()，且 HP=0 / dying=true 不被 recalc 补满', () async {
      final seed = _dyingCard('c1');
      final storage = _CountingStorage(
        MemoryStorage(<String, Map<String, Object?>>{
          'c1': seed.toJson(),
        }),
      );
      final repo = CharacterRepo(storage: storage);
      await repo.load();
      final sink = CharacterRepoRoomCardSink(repo);

      final res = await sink.write(RoomCardPatch(
        charId: 'c1',
        patch: <String, Object?>{
          'status': <String, Object?>{
            'currentHP': 0,
            'dying': true,
            'body': '重伤',
          },
        },
      ));

      expect(res.ok, isTrue);
      expect(res.reason, '');
      expect(res.cardId, 'c1');
      expect(res.source, 'characters');
      expect(storage.saves, 1,
          reason: '写回必须经过 repo.save() → 触发后端落盘，不能只改内存 Map');

      final after = repo.get('c1');
      expect(after, isNotNull);
      final st = after!.status;
      expect(st['currentHP'], 0,
          reason: 'QA D1：recalc 的补值守卫不得把导入/回写的濒死卡治活');
      expect(st['dying'], isTrue);
      expect(st['body'], '重伤');
      expect(jsTruthy(st['_hpTouched']), isTrue,
          reason: '只有 repo.save 的 applyExplicitStatusMarks 会打这个标记，'
              '它是「确实走过唯一落盘入口」的运行时证据');

      // 后端里也必须是濒死态（不是只有内存缓存对）。
      final persisted = await storage.inner.load();
      expect(asMap(asMap(persisted['c1'])['status'])['currentHP'], 0);
    });

    test('charId 找不到 → card_not_found，绝不退到 current 别的卡', () {
      final current = <String, Object?>{
        'id': 'cur',
        'status': <String, Object?>{'currentHP': 9},
      };
      final res = resolveRoomCardPatch(
        RoomCardPatch(
          charId: 'c9',
          patch: <String, Object?>{
            'status': <String, Object?>{'currentHP': 0},
          },
        ),
        <String, Map<String, Object?>>{},
        current,
      );
      expect(res.ok, isFalse);
      expect(res.reason, 'card_not_found');
      expect(res.cardId, 'c9');
      expect(asMap(current['status'])['currentHP'], 9,
          reason: '定位失败时绝不许碰 current 的卡');
    });

    test('没有 charId 且没有 current → no_card；有 current 才标 source=current',
        () {
      final noCurrent = resolveRoomCardPatch(
        const RoomCardPatch(patch: <String, Object?>{'status': <String, Object?>{}}),
        <String, Map<String, Object?>>{},
        null,
      );
      expect(noCurrent.ok, isFalse);
      expect(noCurrent.reason, 'no_card');

      final withCurrent = resolveRoomCardPatch(
        const RoomCardPatch(patch: <String, Object?>{'status': <String, Object?>{}}),
        <String, Map<String, Object?>>{},
        <String, Object?>{'id': 'cur', 'status': <String, Object?>{}},
      );
      expect(withCurrent.ok, isTrue);
      expect(withCurrent.source, 'current');
      expect(withCurrent.cardId, 'cur');
    });

    test('applySheetState 幂等：同 seq 只生效一次，seq<=0 不生效', () {
      final c = RoomClient(seat: 'p1');
      expect(c.applySheetState(0, <String, Object?>{'hp': 3}).applied, isFalse);
      expect(c.applySheetState(5, <String, Object?>{'hp': 3}).applied, isTrue);
      expect(c.applySheetState(5, <String, Object?>{'hp': 99}).applied, isFalse);
      expect(c.sheetState, <String, Object?>{'hp': 3});
      expect(c.lastStateSeq, 5);
    });

    test('C5 静态检查：房间写回路径恰好 1 处 repo.save，domain 零落盘', () {
      final writer = _stripLineComments(
        File('lib/repo/room_state_writer.dart').readAsStringSync(),
      );
      expect(
        RegExp(r'await\s+repo\.save\(').allMatches(writer).length,
        1,
        reason: '房间状态写回的唯一落盘入口',
      );

      // 「房间写回路径」= 所有引用 RoomCardSink / RoomCardPatch /
      // resolveRoomCardPatch / applyStateToCard 的源文件。这些文件里只允许
      // 出现一次落盘调用；lib 里其它 repo.save（导入导出、UI 编辑、settings）
      // 是各自的业务入口，不属于房间写回路径，不在本断言范围内。
      final pathFiles = <String>[
        'lib/domain/character.dart',
        'lib/domain/room_model_save.dart',
        'lib/domain/room_ports.dart',
        'lib/repo/room_state_writer.dart',
      ];
      final hits = <String>[];
      for (final p in pathFiles) {
        final code = _stripLineComments(File(p).readAsStringSync());
        for (final m in RegExp(r'await\s+\w+\.save\(').allMatches(code)) {
          hits.add('$p:${m.start}');
        }
      }
      expect(hits.length, 1,
          reason: '房间写回路径唯一落盘入口应只在 room_state_writer.dart: $hits');
      expect(hits.single.startsWith('lib/repo/room_state_writer.dart'), isTrue);

      final domainDir = Directory('lib/domain');
      final offenders = <String>[];
      for (final f in domainDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        // 数的是真实代码/真实 import，说明文字里的示例不算命中。
        final code = _stripLineComments(f.readAsStringSync());
        if (RegExp(r'await\s+\w+\.save\(').hasMatch(code) ||
            code.contains('dart:io') ||
            code.contains('dart:ui') ||
            code.contains('package:flutter')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'domain 必须纯 Dart，落盘只能在 repo 层: $offenders');
    });
  });
}
