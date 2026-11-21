// ============================================================
// repo_test.dart — 角色卡仓库（落盘 / 分区 / 迁移）
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

Character _blankCard(String name, {String? id}) {
  final c = Character(newCharacter());
  // 注：domain 的 uid() 是 8 位随机串，测试里同一微秒连续造卡可能撞 id，
  // 所以显式指定，避免用例之间互相覆盖（真实使用中是用户点击触发，不会撞）。
  if (id != null) c.raw['id'] = id;
  c.raw['characterName'] = name;
  c.raw['playerName'] = '测试玩家';
  c.basicInfo['age'] = 30;
  c.raw['age'] = 30;
  c.attributes.addAll(<String, Object?>{
    'str': 60,
    'con': 60,
    'siz': 60,
    'dex': 60,
    'app': 60,
    'int': 60,
    'pow': 60,
    'edu': 60,
    'luck': 60,
  });
  recalc(c);
  return c;
}

void main() {
  test('保存 → 读取 → 列表：字段名与 domain 一致，文件落盘', () async {
    final repo = await newTempRepo();
    final card = _blankCard('阿米蒂奇', id: 'armitage');

    await repo.save(card);

    expect(repo.all.length, 1);
    final loaded = repo.get(card.id);
    expect(loaded, isNotNull);
    expect(loaded!.characterName, '阿米蒂奇');
    expect(jsNum(loaded.derivedStats['maxHP']), 12); // (60+60)/10
    expect(jsNum(loaded.status['maxHP']), 12);

    // 磁盘上确实有一个 JSON，且结构是 {format, version, cards}
    // debugStoragePath 已经是**文件**路径（load 之后才有值）
    final file = File(repo.debugStoragePath!);
    expect(file.existsSync(), isTrue);
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(decoded['format'], JsonFileStorage.formatTag);
    final cards = decoded['cards'] as Map<String, Object?>;
    expect(cards.containsKey(card.id), isTrue);
    // normalize 已把 mental 从字符串迁成数组
    final raw = cards[card.id] as Map<String, Object?>;
    expect((raw['status'] as Map)['mental'], isA<List<Object?>>());
    expect(raw['skillCapOcc'], 99);
    expect(raw['pbCap'], 480);
  });

  test('重新打开仓库能读回同一张卡（跨实例持久化）', () async {
    final dir = await Directory.systemTemp.createTemp(
      'dice_realm_test_reload_',
    );
    final repo1 = CharacterRepo(directory: dir);
    await repo1.load();
    final card = _blankCard('复读调查员', id: 'reload01');
    await repo1.save(card);

    final repo2 = CharacterRepo(directory: dir);
    await repo2.load();
    expect(repo2.all.length, 1);
    expect(repo2.get(card.id)!.characterName, '复读调查员');
  });

  test('分区：身体死亡 或 永久疯狂 → 英灵殿', () async {
    final repo = await newTempRepo();

    final alive = _blankCard('活着的人', id: 'alive001');
    await repo.save(alive);

    final dead = _blankCard('已死的人', id: 'dead0001');
    dead.status['body'] = '死亡';
    await repo.save(dead);

    final insane = _blankCard('永久疯狂者', id: 'insane01');
    insane.status['mental'] = <Object?>['永久疯狂'];
    await repo.save(insane);

    expect(repo.all.length, 3);
    expect(repo.alive.map((c) => c.characterName), <String>['活着的人']);
    expect(repo.fallen.map((c) => c.characterName).toSet(), <String>{
      '已死的人',
      '永久疯狂者',
    });
    expect(isRippedCard(repo.get(dead.id)!), isTrue);
    expect(isRippedCard(repo.get(insane.id)!), isTrue);
    expect(isRippedCard(repo.get(alive.id)!), isFalse);
  });

  test('删除后列表与磁盘同步', () async {
    final repo = await newTempRepo();
    final card = _blankCard('要被删掉', id: 'delete01');
    await repo.save(card);
    await repo.delete(card.id);
    expect(repo.all, isEmpty);
    expect(repo.get(card.id), isNull);

    final decoded = jsonDecode(
      File(repo.debugStoragePath!).readAsStringSync(),
    ) as Map<String, Object?>;
    expect((decoded['cards'] as Map).isEmpty, isTrue);
  });

  test('老结构（缺字段 / 字符串 mental / 仅 skillCap）保存后被 normalize 补全', () async {
    final repo = await newTempRepo();
    final legacy = <String, Object?>{
      'id': 'legacy01',
      'characterName': '老卡',
      'playerName': '老人',
      'skillCap': 80,
      'attributes': <String, Object?>{
        'str': '50',
        'con': '50',
        'siz': '50',
        'dex': '50',
      },
      'status': <String, Object?>{
        'mental': '临时疯狂',
        'body': '濒死',
        'currentHP': 0,
        'maxHP': 10,
      },
    };
    await repo.save(Character(legacy));

    final c = repo.get('legacy01')!;
    expect(c.raw['skillCapOcc'], 80);
    expect(c.raw['skillCapInterest'], 80);
    expect(c.status['mental'], <Object?>['临时疯狂']);
    expect(c.status['body'], '重伤');
    expect(c.status['dying'], isTrue);
    expect(c.raw['pbCap'], 480);
    expect(c.raw['occupationPicks'], isA<Map<String, Object?>>());
  });

  test('文件不存在 / JSON 坏掉时 load 不抛，仓库给空列表', () async {
    final dir = await Directory.systemTemp.createTemp(
      'dice_realm_test_broken_',
    );
    File('${dir.path}/characters.json').writeAsStringSync('{ 这不是 JSON');
    final repo = CharacterRepo(directory: dir);
    await repo.load();
    expect(repo.all, isEmpty);
    expect(repo.isLoaded, isTrue);
    expect(repo.lastError, isNotNull);
  });
}
