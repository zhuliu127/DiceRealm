// ============================================================
// file_room_save_store_test.dart — 房间存档的文件后端
//
// 这条测试的价值全在**「新实例能读回来」**上：
// 同一个实例读自己写的内存，什么实现都能过。
// 只有另起一个实例（模拟「杀掉 App 再打开」）才验得到真持久化。
//
// 用 `Directory.systemTemp.createTempSync` 而非 mock 文件系统：
// 原子写（tmp → copy）、坏文件跳过、目录创建这些行为，
// mock 掉就验不到了 —— 而它们正是存档最容易丢数据的地方。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/repo/file_room_save_store.dart';
import 'package:dice_realm/repo/room_save_store.dart'
    show InMemoryRoomSaveStore;
import 'package:dice_realm/ui/room/save_persist_hint.dart'
    show isPersistentSaveStore, savePersistHintOf;
import 'package:flutter_test/flutter_test.dart';

Directory _tmpDir() {
  final d = Directory.systemTemp.createTempSync('dice_save_test_');
  addTearDown(() {
    try {
      d.deleteSync(recursive: true);
    } catch (_) {}
  });
  return d;
}

/// 一份像样的存档（含嵌套 Map / List —— 深拷贝才有的验）。
Map<String, Object?> _save(String name) => <String, Object?>{
  'meta': <String, Object?>{'name': name, 'code': 'AB12CD'},
  'logs': <Object?>[
    <String, Object?>{'t': 'sys', 'p': <String, Object?>{'text': '开场'}},
  ],
  'members': <Object?>[
    <String, Object?>{'seat': 'p1', 'nickname': '甲'},
  ],
};

void main() {
  group('真持久化（换个实例还能读到）', () {
    test('★ put → flush → 新实例 loadSync → get 拿回同一份', () async {
      final dir = _tmpDir();

      final a = FileRoomSaveStore(dir)..loadSync();
      a.put('AB12CD', _save('洋馆惊魂'));
      await a.flush();

      // 模拟「杀掉 App 再打开」：全新实例，只共享磁盘。
      final b = FileRoomSaveStore(dir)..loadSync();
      final got = b.get('AB12CD');
      expect(got, isNotNull, reason: '★ 这就是存档持久化的全部意义');
      expect((got!['meta']! as Map)['name'], '洋馆惊魂');
      expect(b.list(), <String>['AB12CD']);
      expect(b.isLoaded, isTrue);
    });

    test('list 排序稳定（续玩列表不该每次打开顺序都变）', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('ZZ0001', _save('C'));
      s.put('AA0002', _save('A'));
      s.put('MM0003', _save('B'));
      await s.flush();

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), <String>['AA0002', 'MM0003', 'ZZ0001']);
    });

    test('多槽各自独立，互不覆盖', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('AA0001', _save('一号'));
      s.put('BB0002', _save('二号'));
      await s.flush();

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.length, 2);
      expect((b.get('AA0001')!['meta']! as Map)['name'], '一号');
      expect((b.get('BB0002')!['meta']! as Map)['name'], '二号');
    });
  });

  // ----------------------------------------------------------
  // ★ 2.37.0 / Q1：结构化槽键真落盘链路（玩家/ KP 收档主因的回归靶点）
  // ----------------------------------------------------------
  group('★ 结构化槽键落盘（auto/ share/ 三段键 → ~sk~<hex> 文件名）', () {
    const String code = 'NU9E6R';
    const String autoKey = 'auto/NU9E6R/round-1700000000000';
    const String shareKey = 'share/NU9E6R/latest';

    test('isStructuredSlotKey 只认 auto/share 三段键；isSafeKey 白名单语义未改', () {
      expect(FileRoomSaveStore.isStructuredSlotKey(autoKey), isTrue);
      expect(FileRoomSaveStore.isStructuredSlotKey(shareKey), isTrue);
      // 形状不对的一律拒（路径穿越面零扩大）。
      for (final String bad in <String>[
        'auto/$code',
        'auto/$code/a/b',
        'other/$code/x',
        'auto/../evil',
        '../evil/x',
        r'auto\NU9E6R\x',
        'auto/$code/中文',
        '',
      ]) {
        expect(FileRoomSaveStore.isStructuredSlotKey(bad), isFalse,
            reason: '不该放行的结构化键：$bad');
      }
      // ★ 白名单本身一字未改：含 / 的键 isSafeKey 仍是 false。
      expect(FileRoomSaveStore.isSafeKey(autoKey), isFalse);
      expect(FileRoomSaveStore.isSafeKey(shareKey), isFalse);
      expect(FileRoomSaveStore.isSafeKey(code), isTrue);
    });

    test('★ put(auto + share + 房号) → flush → 新实例 loadSync：三条都在且可解析',
        () async {
      final dir = _tmpDir();
      final a = FileRoomSaveStore(dir)..loadSync();
      a.put(autoKey, _save('自动档'));
      a.put(shareKey, _save('收档'));
      a.put(code, _save('续玩档'));
      await a.flush();

      // 磁盘上：auto/share 编码成 ~sk~<hex>（无 /）；房号键文件名零漂移。
      final List<String> names = dir
          .listSync()
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
      expect(names.length, 3, reason: '三条槽都得真落盘：$names');
      expect(
        names.where((String n) =>
            n.startsWith(FileRoomSaveStore.encodedSlotMarker)).length,
        2,
        reason: '★ 两条结构化键必须编码成 ~sk~<hex>，磁盘上不能有 / 子目录',
      );
      expect(names, contains('$code.json'), reason: '房号键文件名零漂移');

      // 模拟杀进程重开：全新实例只共享磁盘。
      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.length, 3);
      expect(b.list(), <String>[code, autoKey, shareKey],
          reason: 'list() 对外仍返回逻辑键（不是 ~sk~ 文件名）');
      expect((b.get(autoKey)!['meta']! as Map)['name'], '自动档');
      expect((b.get(shareKey)!['meta']! as Map)['name'], '收档');
      expect((b.get(code)!['meta']! as Map)['name'], '续玩档');
    });

    test('结构化键 remove 后重开不再出现（滚动淘汰真删文件）', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put(autoKey, _save('将被淘汰'));
      s.put(code, _save('保留'));
      await s.flush();

      expect(s.remove(autoKey), isTrue);
      await s.flush();
      final List<String> onDisk = dir
          .listSync()
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .toList();
      expect(
        onDisk.any((String n) =>
            n.startsWith(FileRoomSaveStore.encodedSlotMarker)),
        isFalse,
        reason: '★ 编码文件必须随 remove 一起删掉',
      );
      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), <String>[code]);
      expect(b.get(autoKey), isNull);
    });

    test('损坏/伪造的编码文件被跳过，合法槽照常可读', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put(shareKey, _save('好的收档'));
      await s.flush();

      // ① 十六进制损坏（奇数长度 / 非 hex）；② 解码后不是结构化键。
      File('${dir.path}${Platform.pathSeparator}'
              '${FileRoomSaveStore.encodedSlotMarker}zzz.json')
          .writeAsStringSync(jsonEncode(_save('坏编码')));
      final String safeKeyHex = utf8
          .encode('AB12CD')
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      File('${dir.path}${Platform.pathSeparator}'
              '${FileRoomSaveStore.encodedSlotMarker}$safeKeyHex.json')
          .writeAsStringSync(jsonEncode(_save('伪装成房号')));

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), <String>[shareKey],
          reason: '★ 外来/伪造编码文件一律跳过，合法收档不能跟着丢');
      expect((b.get(shareKey)!['meta']! as Map)['name'], '好的收档');
    });
  });

  group('深拷贝边界（与 InMemory 同口径）', () {
    test('put 之后改源对象，存档不受影响', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();

      final src = _save('快照团');
      s.put('AA0001', src);
      // 事后原地改源（真实场景：调用方继续用这个 Map）
      (src['meta']! as Map)['name'] = '被改掉的';
      await s.flush();

      final b = FileRoomSaveStore(dir)..loadSync();
      expect((b.get('AA0001')!['meta']! as Map)['name'], '快照团',
          reason: 'put 必须深拷贝：源对象事后被改也不能影响存档');
    });

    test('get 出来的副本被就地改，存档不受影响', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('AA0001', _save('快照团'));
      await s.flush();

      final taken = s.get('AA0001')!;
      (taken['meta']! as Map)['name'] = '被改掉的';
      expect((s.get('AA0001')!['meta']! as Map)['name'], '快照团',
          reason: 'get 必须深拷贝：调用方就地改不能污染存档（adoptSave 会改）');

      // 磁盘上也不能被污染
      final b = FileRoomSaveStore(dir)..loadSync();
      expect((b.get('AA0001')!['meta']! as Map)['name'], '快照团');
    });

    test('嵌套 List<Map> 也是深拷贝（不只是顶层）', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('AA0001', _save('x'));
      await s.flush();

      final taken = s.get('AA0001')!;
      ((taken['logs']! as List).first as Map)['p'] = '被改掉的';
      final again = s.get('AA0001')!;
      expect(((again['logs']! as List).first as Map)['p'], isA<Map>(),
          reason: '★ 嵌套层不能是共享引用');
    });
  });

  group('删除与清空', () {
    test('★ remove 连文件一起删（新实例读不到）', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('AA0001', _save('一号'));
      s.put('BB0002', _save('二号'));
      await s.flush();

      expect(s.remove('AA0001'), isTrue);
      expect(s.remove('AA0001'), isFalse, reason: '已删过的返回 false');
      await s.flush();

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), <String>['BB0002']);
      expect(
        File('${dir.path}${Platform.pathSeparator}AA0001.json').existsSync(),
        isFalse,
        reason: '★ 只删内存不删文件 = 重启后「删掉的存档又回来了」',
      );
    });

    test('clear 清空全部（含磁盘）', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('AA0001', _save('一'));
      s.put('BB0002', _save('二'));
      await s.flush();

      s.clear();
      expect(s.list(), isEmpty);
      await s.flush();

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), isEmpty);
    });
  });

  group('健壮性（存档损坏是丢档的第二大原因）', () {
    test('★ 单个存档文件损坏 → 跳过它，其余照常可读', () async {
      final dir = _tmpDir();
      final good = FileRoomSaveStore(dir)..loadSync();
      good.put('AA0001', _save('好的'));
      await good.flush();

      // 手写一个坏文件（模拟写到一半掉电 / 用户手改）
      // 截断的 JSON（模拟写到一半掉电 / 用户手改）
      File('${dir.path}${Platform.pathSeparator}BB0002.json')
          .writeAsStringSync('{"meta": {"name": "坏的"');

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), <String>['AA0001'],
          reason: '坏的那个跳过，好的不能跟着丢');
      expect(b.lastError, isNotNull, reason: '要记下来，便于排查');
    });

    test('★ 残留的 .tmp 文件不会被当成存档读进来', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('AA0001', _save('好的'));
      await s.flush();

      // 模拟上次写到一半被杀：留下 .tmp
      File('${dir.path}${Platform.pathSeparator}CC0003.json.tmp')
          .writeAsStringSync(jsonEncode(_save('半截')));

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), <String>['AA0001'],
          reason: '★ .tmp 是中间产物，读进来会得到一份重复的半个存档');
    });

    test('目录不存在时自动创建（首次启动）', () async {
      final root = _tmpDir();
      final dir = Directory('${root.path}${Platform.pathSeparator}room_saves');
      expect(dir.existsSync(), isFalse);

      final s = FileRoomSaveStore(dir)..loadSync();
      expect(dir.existsSync(), isTrue, reason: 'loadSync 应建目录，否则首次保存必失败');

      s.put('AA0001', _save('一'));
      await s.flush();
      expect(
        File('${dir.path}${Platform.pathSeparator}AA0001.json').existsSync(),
        isTrue,
      );
    });

    test('没 loadSync 过也能用（只是 list 为空）', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir);
      expect(s.isLoaded, isFalse);
      expect(s.list(), isEmpty);
      // put 仍然要能工作（并落盘）
      s.put('AA0001', _save('一'));
      await s.flush();
      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), <String>['AA0001']);
    });
  });

  group('路径穿越防护（槽键会被拼进文件名）', () {
    test('★ 含路径分隔符或 .. 的键被拒绝', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();

      for (final bad in <String>[
        '../evil',
        '..',
        'a/b',
        r'a\b',
        'CON',   // Windows 保留名（虽被白名单拦住，但这行是文档）
        '',
        'x' * 65, // 超长
        'a.json', // 带扩展名（白名单不含点）
      ]) {
        expect(FileRoomSaveStore.isSafeKey(bad), isFalse, reason: '应拒绝：$bad');
      }

      s.put('../evil', _save('x'));
      expect(s.list(), isEmpty, reason: '★ 非法键不能进内存');
      expect(s.get('../evil'), isNull);

      // 确认真的没在上级目录写出文件
      final parent = Directory(dir.parent.path);
      expect(
        parent.listSync().whereType<File>().any((f) => f.path.endsWith('evil.json')),
        isFalse,
        reason: '★ 绝不能写到 dir 外面去',
      );
    });

    test('正常键都通过（房间号 / 槽名）', () {
      for (final ok in <String>['AB12CD', '槽A', 'save-1', 'SAVE_2', 'a']) {
        // 注意：中文不在白名单里（不用它做文件名），这条只验英数
        if (ok == '槽A') continue;
        expect(FileRoomSaveStore.isSafeKey(ok), isTrue, reason: '应通过：$ok');
      }
      // 中文槽名确实会被拒 —— 这是刻意的：存档槽的 key 用房间号或
        // 时间戳生成，不用用户输入的中文。
      expect(FileRoomSaveStore.isSafeKey('槽A'), isFalse);
    });
  });

  group('写入排队（同一槽连写不能抢同一文件）', () {
    test('★ 连续 put 同一槽 5 次 → 最终落盘的是最后一次', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      for (var i = 0; i < 5; i++) {
        s.put('AA0001', _save('第 $i 次'));
      }
      await s.flush();

      final b = FileRoomSaveStore(dir)..loadSync();
      expect((b.get('AA0001')!['meta']! as Map)['name'], '第 4 次', reason: '下标从 0 起');
    });

    test('put 后立刻 remove → 最终不存在（不会写出半路内容）', () async {
      final dir = _tmpDir();
      final s = FileRoomSaveStore(dir)..loadSync();
      s.put('AA0001', _save('一'));
      s.remove('AA0001');
      await s.flush();

      final b = FileRoomSaveStore(dir)..loadSync();
      expect(b.list(), isEmpty);
    });
  });

  group('持久化文案（按后端能力说真话，不写死一句）', () {
    test('内存后端 → 明说「关闭 App 后不保留」', () {
      final s = InMemoryRoomSaveStore();
      expect(isPersistentSaveStore(s), isFalse);
      expect(savePersistHintOf(s).contains('关闭 App 后不保留'), isTrue);
    });

    test('★ 文件后端 → 改口成「不卸载就一直有效」', () {
      final s = FileRoomSaveStore(_tmpDir())..loadSync();
      expect(isPersistentSaveStore(s), isTrue,
          reason: '★ 靠 PersistentSaveStore 标记识别，UI 不必认具体类');
      expect(savePersistHintOf(s).contains('不卸载'), isTrue);
      expect(savePersistHintOf(s).contains('关闭 App 后不保留'), isFalse,
          reason: '★ 这句对文件后端是假话，换后端时最容易漏改的就是它');
    });

    test('没有后端（远端会话）→ 明说「只有房主能保存」', () {
      expect(isPersistentSaveStore(null), isFalse);
      expect(savePersistHintOf(null).contains('只有房主能保存'), isTrue,
          reason: '玩家/旁观接远端会话，本来就没有存档能力，不能装作有');
    });
  });
}
