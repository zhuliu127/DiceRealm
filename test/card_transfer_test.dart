// ============================================================
// card_transfer_test.dart — 导入 / 导出（老角色唯一的搬家通道）
//
// 钉住的硬约束：
//   · 硬约束 5：导出 → 再导入 → 除 id 外逐字段深比较相等
//   · 硬约束 6：卡片数据契约不变 —— 能吃旧版真实导出的 JSON
//
// fixture `test/fixtures/legacy_card_export.json` 是用**旧版 store.js 本身**
// 生成的（见 tool/gen_legacy_export.js），不是手写的样本。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/normalize.dart';
import 'package:dice_realm/repo/card_transfer.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:flutter_test/flutter_test.dart';

String _readFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

/// 造一张最小可用的卡（不依赖任何随机数）
Character _tinyCard() {
  final c = Character(<String, Object?>{
    'id': 'abc12345',
    'characterName': '甲',
  });
  return c;
}

/// 深比较助手（键集合必须完全一致）
void _expectDeepEqual(Object? actual, Object? expected, String path) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: '$path 应为对象');
    final a = _asMapOf(actual);
    final e = _asMapOf(expected);
    expect(a.keys.toSet(), e.keys.toSet(), reason: '$path 键集合不一致');
    for (final k in e.keys) {
      _expectDeepEqual(a[k], e[k], '$path.$k');
    }
    return;
  }
  if (expected is List) {
    expect(actual, isA<List>(), reason: '$path 应为数组');
    final a = actual! as List;
    final e = expected;
    expect(a.length, e.length, reason: '$path 长度不一致');
    for (var i = 0; i < e.length; i++) {
      _expectDeepEqual(a[i], e[i], '$path[$i]');
    }
    return;
  }
  expect(actual, expected, reason: '$path 值不一致');
}

Map<String, Object?> _asMapOf(Object? v) {
  final out = <String, Object?>{};
  (v! as Map).forEach((k, val) => out[jsStr(k)] = val);
  return out;
}

void main() {
  group('单卡导出（exportCharacter 的逐字对齐）', () {
    test('外层形状 / 键序 / 2 空格缩进 / 中文不转义 与旧版 JSON.stringify 一致', () {
      final json = exportCardJson(_tinyCard());
      const expected =
          '{\n'
          '  "format": "coc7-card",\n'
          '  "version": 1,\n'
          '  "data": {\n'
          '    "id": "abc12345",\n'
          '    "characterName": "甲"\n'
          '  }\n'
          '}';
      expect(json, expected);
    });

    test('解码后 format=coc7-card / version=1 / data 就是卡片本体', () {
      final c = _tinyCard();
      final decoded = jsonDecode(exportCardJson(c)) as Map<String, Object?>;
      expect(decoded['format'], 'coc7-card');
      expect(decoded['version'], 1);
      expect((decoded['data']! as Map)['characterName'], '甲');
    });
  });

  group('全量导出（app.js#exportAll 的逐字对齐）', () {
    test('外层是 {format:coc7-bundle, version:1, characters:[...]}', () {
      final json = exportBundleJson(<Character>[_tinyCard()]);
      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded.keys.toList(), <String>[
        'format',
        'version',
        'characters',
      ]);
      expect(decoded['format'], 'coc7-bundle');
      expect(decoded['version'], 1);
      expect((decoded['characters']! as List).length, 1);
      expect(((decoded['characters']! as List).first as Map)['id'], 'abc12345');
    });
  });

  group('导入解析', () {
    test('硬约束 6：能吃旧版真实导出的单卡（fixture 由旧版 store.js 生成）', () {
      final r = parseCardImport(_readFixture('legacy_card_export.json'));
      expect(r.count, 1);
      expect(r.bundle, isFalse);
      final card = r.cards.first;
      expect(card['characterName'], '旧版调查员');
      expect(card['id'], 'legacy01');
      expect(jsNum(_asMapOf(card['status'])['currentHP']), 10);
      expect((card['madness']! as List).length, 1, reason: '背景症状已迁移成结构化条目');
    });

    test('硬约束 6：能吃旧版真实导出的全量文件', () {
      final r = parseCardImport(_readFixture('legacy_bundle_export.json'));
      expect(r.bundle, isTrue);
      expect(r.count, greaterThanOrEqualTo(1));
      expect(r.cards.first['characterName'], '旧版调查员');
    });

    test('接受裸角色对象（obj.data || obj）', () {
      final r = parseCardImport('{"characterName":"裸对象","id":"bare0001"}');
      expect(r.count, 1);
      expect(r.cards.first['characterName'], '裸对象');
    });

    test('缺 characterName 且缺 id → 可读错误（不静默吞掉）', () {
      expect(
        () => parseCardImport('{"playerName":"x"}'),
        throwsA(
          isA<CardImportError>().having(
            (e) => e.message,
            'message',
            contains('characterName'),
          ),
        ),
      );
    });

    test('空内容 → 可读错误', () {
      expect(
        () => parseCardImport('   '),
        throwsA(
          isA<CardImportError>().having(
            (e) => e.message,
            'message',
            contains('内容为空'),
          ),
        ),
      );
    });

    test('非法 JSON → 可读错误', () {
      expect(
        () => parseCardImport('{这不是 json'),
        throwsA(
          isA<CardImportError>().having(
            (e) => e.message,
            'message',
            contains('不是合法的 JSON'),
          ),
        ),
      );
    });

    test('顶层不是对象 → 可读错误', () {
      expect(
        () => parseCardImport('[1,2,3]'),
        throwsA(
          isA<CardImportError>().having(
            (e) => e.message,
            'message',
            contains('顶层必须是对象'),
          ),
        ),
      );
    });

    test('全量文件里没有卡 → 可读错误', () {
      expect(
        () => parseCardImport(
          '{"format":"coc7-bundle","version":1,"characters":[]}',
        ),
        throwsA(
          isA<CardImportError>().having(
            (e) => e.message,
            'message',
            contains('没有可导入'),
          ),
        ),
      );
    });
  });

  group('硬约束 5：round-trip 等价（除 id 必变）', () {
    test('导出 → 导入 → 逐字段深比较相等（旧版 fixture 走一遍）', () {
      final original = parseCardImport(_readFixture('legacy_card_export.json'))
          .cards
          .first;
      final exported = exportCardJson(Character(original));
      final again = parseCardImport(exported).cards.first;

      final a = Map<String, Object?>.from(original)..remove('id');
      final b = Map<String, Object?>.from(again)..remove('id');
      _expectDeepEqual(b, a, 'data');

      // 除了 id 之外，连值类型（int / String / bool）都必须一致
      expect(again['id'], original['id'], reason: '纯解析不换 id，换 id 发生在写库前');
    });

    test('换 id 只改 id 一个字段（assignFreshId）', () {
      final original = parseCardImport(_readFixture('legacy_card_export.json'))
          .cards
          .first;
      final fresh = assignFreshId(original, takenIds: <String>{'legacy01'});
      expect(fresh['id'], isNot('legacy01'));
      final a = Map<String, Object?>.from(original)..remove('id');
      final b = Map<String, Object?>.from(fresh)..remove('id');
      _expectDeepEqual(b, a, 'data');
    });

    test('全量导出 → 全量导入 → 每张卡逐字段相等', () {
      final original = Character(
        Map<String, Object?>.from(
          parseCardImport(_readFixture('legacy_card_export.json')).cards.first,
        ),
      );
      final bundle = exportBundleJson(<Character>[original, _tinyCard()]);
      final parsed = parseCardImport(bundle);
      expect(parsed.count, 2);
      final a = Map<String, Object?>.from(original.raw)..remove('id');
      final b = Map<String, Object?>.from(parsed.cards.first)..remove('id');
      _expectDeepEqual(b, a, 'characters[0]');
    });
  });

  group('导入到仓库', () {
    test('重新分配 id：不覆盖原卡，原卡内容一字不动', () async {
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final existing = Character(
        Map<String, Object?>.from(
          parseCardImport(_readFixture('legacy_card_export.json')).cards.first,
        ),
      );
      await repo.save(existing);
      expect(repo.all.length, 1);

      final imported = await importIntoRepo(
        repo,
        _readFixture('legacy_card_export.json'),
      );

      expect(repo.all.length, 2, reason: '导入是「再拿一份」，不是覆盖');
      expect(imported.single.id, isNot('legacy01'));
      expect(repo.get('legacy01'), isNotNull, reason: '原卡还在');
      expect(repo.get('legacy01')!.characterName, '旧版调查员');
      expect(imported.single.characterName, '旧版调查员');
    });

    test('导入后落盘的是 normalize + recalc 过的卡（幂等）', () async {
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final imported = await importIntoRepo(
        repo,
        _readFixture('legacy_card_export.json'),
      );
      final c = imported.single;
      final before = jsonEncode(c.raw);
      normalize(c);
      expect(jsonEncode(c.raw), before, reason: 'normalize 必须幂等');
      expect(jsNum(c.status['maxHP']), greaterThan(0), reason: '派生值已算好');
    });
  });
}
