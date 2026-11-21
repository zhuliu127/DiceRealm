// ============================================================
// settings_repo_test.dart — 设置存储（真实文件 I/O）
//
// 普通 test（不是 testWidgets）：这里就是要跑真的读写盘，
// 顺带验证「文件不存在 / 内容损坏 / 目录不可写」时**必须干净退化**，
// 而不是把异常抛到启动路径上。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/repo/settings_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dice_realm_settings_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SettingsRepo newRepo() =>
      SettingsRepo(storage: JsonFileSettingsStorage(directory: dir));

  File settingsFile() =>
      File('${dir.path}${Platform.pathSeparator}settings.json');

  group('默认值与容错（读不到文件时必须是干净默认值，不许抛）', () {
    test('文件不存在 → 默认值，不抛', () async {
      final repo = newRepo();
      await repo.load();
      expect(repo.isLoaded, isTrue);
      expect(repo.lastError, isNull);
      expect(repo.aiBase, 'https://api.deepseek.com/v1');
      expect(repo.aiModel, 'deepseek-flash');
      expect(repo.aiKey, '');
      expect(repo.shareBase, '');
      expect(repo.roomBase, '');
      expect(repo.skillCap, 99);
      expect(repo.autoSave, isTrue);
      expect(repo.aiAttrCap, 0);
      expect(repo.aiAttrCapWithLuck, isTrue);
      // 全部键都在（与 defaultSettings 一致）
      for (final k in defaultSettings().keys) {
        expect(repo.settings.containsKey(k), isTrue, reason: '缺键 $k');
      }
    });

    test('文件内容是坏 JSON → 默认值 + 记一条错误，不抛', () async {
      await settingsFile().writeAsString('{ 这不是 JSON ');
      final repo = newRepo();
      await repo.load();
      expect(repo.isLoaded, isTrue);
      expect(repo.aiBase, 'https://api.deepseek.com/v1');
      expect(repo.lastError, isNull, reason: '坏 JSON 由存储层吞掉，不该冒到 repo');
    });

    test('空文件 → 默认值', () async {
      await settingsFile().writeAsString('   ');
      final repo = newRepo();
      await repo.load();
      expect(repo.aiModel, 'deepseek-flash');
    });

    test('类型写坏（num 存成字符串、bool 存成 1）→ 退回默认值，不抛', () async {
      await settingsFile().writeAsString(
        jsonEncode(<String, Object?>{
          'format': 'dice-realm.settings',
          'version': 1,
          'settings': <String, Object?>{
            'skillCap': 'abc',
            'autoSave': 1,
            'aiBase': 123,
            'aiAttrCap': 'not-a-number',
          },
        }),
      );
      final repo = newRepo();
      await repo.load();
      expect(repo.skillCap, 99);
      expect(repo.autoSave, isTrue);
      expect(repo.aiBase, 'https://api.deepseek.com/v1');
      expect(repo.aiAttrCap, 0);
    });
  });

  group('落盘 / 读回', () {
    test('保存后重新读回：逐键一致', () async {
      final a = newRepo();
      await a.load();
      a
        ..aiBase = 'https://api.example.com/v1'
        ..aiModel = 'my-model'
        ..aiKey = 'sk-abcdefghijklmnop'
        ..shareBase = 'https://share.example.com'
        ..roomBase = 'https://room.example.com'
        ..skillCap = 85
        ..autoSave = false
        ..aiAttrCap = 420
        ..aiAttrCapWithLuck = false
        ..aiOccPtsCap = 70
        ..aiIntPtsCap = 60;
      await a.save();
      expect(a.lastError, isNull);
      expect(settingsFile().existsSync(), isTrue);

      final b = newRepo();
      await b.load();
      expect(b.aiBase, 'https://api.example.com/v1');
      expect(b.aiModel, 'my-model');
      expect(b.aiKey, 'sk-abcdefghijklmnop');
      expect(b.shareBase, 'https://share.example.com');
      expect(b.roomBase, 'https://room.example.com');
      expect(b.skillCap, 85);
      expect(b.autoSave, isFalse);
      expect(b.aiAttrCap, 420);
      expect(b.aiAttrCapWithLuck, isFalse);
      expect(b.aiOccPtsCap, 70);
      expect(b.aiIntPtsCap, 60);
    });

    test('未知键保留（以后加字段不会互删）', () async {
      await settingsFile().writeAsString(
        jsonEncode(<String, Object?>{
          'format': 'dice-realm.settings',
          'version': 1,
          'settings': <String, Object?>{
            'futureKey': 'from-newer-version',
            'aiModel': 'x',
          },
        }),
      );
      final repo = newRepo();
      await repo.load();
      expect(repo.settings['futureKey'], 'from-newer-version');
      expect(repo.aiModel, 'x');
    });

    test('地址两端空白会被裁掉（手机键盘很容易带空格）', () async {
      final repo = newRepo();
      await repo.load();
      repo
        ..aiBase = '  https://api.deepseek.com/v1  '
        ..shareBase = ' https://a.example.com ';
      await repo.save();
      expect(repo.aiBase, 'https://api.deepseek.com/v1');
      expect(repo.shareBase, 'https://a.example.com');
    });

    test('skillCap 被夹在 1-99', () async {
      final repo = newRepo();
      await repo.load();
      repo.skillCap = 0;
      expect(repo.skillCap, 1);
      repo.skillCap = 500;
      expect(repo.skillCap, 99);
    });
  });

  group('API Key 脱敏（硬约束：不进日志 / 不进快照）', () {
    test('maskApiKey：前 4 + 后 4', () {
      expect(maskApiKey('sk-1234567890abcdef'), 'sk-1****cdef');
      expect(maskApiKey(''), '');
      // 短 Key 不能"留前4后4"（那样等于原样打出来）
      expect(maskApiKey('sk-1234'), 'sk****');
      expect(maskApiKey('abcdefgh'), 'ab****');
    });

    test('describe() 里 Key 已脱敏，且不含原文', () async {
      final repo = newRepo();
      await repo.load();
      repo.aiKey = 'sk-supersecret-0123456789';
      final d = repo.describe();
      expect('${d['aiKey']}', isNot(contains('supersecret')));
      expect('${d['aiKey']}', contains('****'));
      // 其它键照常
      expect(d['aiModel'], 'deepseek-flash');
    });

    test('maskedAiKey 与真实 Key 不同', () async {
      final repo = newRepo();
      await repo.load();
      repo.aiKey = 'sk-supersecret-0123456789';
      expect(repo.aiKey, 'sk-supersecret-0123456789');
      expect(repo.maskedAiKey, isNot(repo.aiKey));
    });

    test('异常文本里的 Key 会被打码', () {
      final text =
          'HttpException: header Authorization: Bearer sk-abcdefghijklmnop failed';
      final masked = maskSecrets(text);
      expect(masked, isNot(contains('abcdefghijklmnop')));
      expect(masked, contains('****'));
    });
  });

  group('落盘失败不崩（目录不可写时只记错误）', () {
    test('把目录换成一个文件 → save 记 lastError，不抛', () async {
      final blocker = File('${dir.path}${Platform.pathSeparator}blocked');
      await blocker.writeAsString('x');
      final repo = SettingsRepo(
        storage: JsonFileSettingsStorage(directory: Directory(blocker.path)),
      );
      await repo.load();
      repo.aiModel = 'still-works-in-memory';
      await repo.save();
      expect(repo.lastError, isNotNull);
      // 内存值仍然可用（UI 不会因为写盘失败而显示空白）
      expect(repo.aiModel, 'still-works-in-memory');
    });
  });

  group('设置会喂给规则层（房规上限是每次生成现读的）', () {
    test('改完 aiAttrCap 后 presetSettings 立刻同步', () async {
      final repo = newRepo();
      await repo.load();
      repo.aiAttrCap = 400;
      await repo.save();
      // ignore: avoid_print
      expect(repo.settings['aiAttrCap'], 400);
    });
  });

  group('测试连接（未注入探测实现时不得联网）', () {
    test('三个空格子分别提示', () async {
      final repo = newRepo();
      await repo.load();
      repo
        ..aiBase = ''
        ..aiModel = ''
        ..aiKey = '';
      var r = await repo.testConnection();
      expect(r.message, contains('接口地址'));

      repo.aiBase = 'https://api.deepseek.com/v1';
      r = await repo.testConnection();
      expect(r.message, contains('模型名称'));

      repo.aiModel = 'deepseek-flash';
      r = await repo.testConnection();
      expect(r.message, contains('API Key'));

      // 三项齐了但没注入 probe：说明「本版本未接入网络层」，且绝不发请求
      repo.aiKey = 'sk-1234567890abcdef';
      r = await repo.testConnection();
      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
      // 结果里不能出现完整 Key
      expect(r.message, isNot(contains('sk-1234567890abcdef')));
    });
  });
}
