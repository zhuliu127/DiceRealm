// ============================================================
// share_store_test.dart — 分享记录的本机存储（真实文件 I/O）
//
// 记录里带着 `delToken`（删除口令），所以这份用例同时钉住两件事：
//   · 落盘 / 读回逐字段一致（含 delToken —— 丢了就再也删不掉分享）；
//   · 文件坏 / 不存在 / 类型错 → 干净空表，不抛。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:dice_realm/repo/share_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dice_realm_shares_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ShareStore newStore() =>
      ShareStore(storage: JsonFileShareStorage(directory: dir));

  File sharesFile() => File('${dir.path}${Platform.pathSeparator}shares.json');

  ShareRecord rec({
    String id = 'sh_1',
    String url = 'https://s.example.com/c/sh_1',
    String token = 'tok-abc',
  }) => ShareRecord(
    id: id,
    url: url,
    delToken: token,
    at: 1700000000000,
    name: '林晚',
  );

  test('文件不存在 → 空表，不抛', () async {
    final s = newStore();
    await s.load();
    expect(s.all, isEmpty);
    expect(s.lastError, isNull);
    expect(s.isLoaded, isTrue);
  });

  test('落盘 / 读回：id / url / delToken / at / name 全部一致', () async {
    final a = newStore();
    await a.load();
    await a.put('cardA', rec());
    expect(a.lastError, isNull);
    expect(sharesFile().existsSync(), isTrue);

    final b = newStore();
    await b.load();
    final r = b.forCard('cardA')!;
    expect(r.id, 'sh_1');
    expect(r.url, 'https://s.example.com/c/sh_1');
    expect(r.delToken, 'tok-abc');
    expect(r.at, 1700000000000);
    expect(r.name, '林晚');
  });

  test('删除记录后落盘也删掉（重启不会"复活"）', () async {
    final a = newStore();
    await a.load();
    await a.put('cardA', rec());
    await a.remove('cardA');

    final b = newStore();
    await b.load();
    expect(b.forCard('cardA'), isNull);
  });

  test('坏 JSON / 空文件 / 结构不对 → 空表，不抛', () async {
    for (final text in <String>[
      '',
      '  ',
      '{ not json',
      '[]',
      '{"shares": 5}',
    ]) {
      await sharesFile().writeAsString(text);
      final s = newStore();
      await s.load();
      expect(s.all, isEmpty, reason: '内容「$text」应退化成空表');
      expect(s.lastError, isNull, reason: '坏文件由存储层吞掉，不该冒到 repo');
    }
  });

  test('没有 shares 包一层的手写文件也能读（兼容）', () async {
    await sharesFile().writeAsString(
      jsonEncode(<String, Object?>{
        'cardA': <String, Object?>{
          'id': 'sh_9',
          'url': 'u',
          'delToken': 't',
          'at': 1,
          'name': 'n',
        },
      }),
    );
    final s = newStore();
    await s.load();
    expect(s.forCard('cardA')?.id, 'sh_9');
  });

  test('describe() 不吐口令原文（打日志专用形状）', () {
    final r = rec(token: 'tok-super-secret');
    expect(r.describe()['delToken'], '****');
    expect(jsonEncode(r.describe()), isNot(contains('tok-super-secret')));
    // 但 toJson 必须保留（要落盘）
    expect(r.toJson()['delToken'], 'tok-super-secret');
  });

  test('内存后端：widget 测试可用（不碰文件系统）', () async {
    final s = ShareStore(storage: MemoryShareStorage());
    await s.load();
    await s.put('c1', rec());
    expect(s.forCard('c1')?.id, 'sh_1');
    expect(s.debugStoragePath, isNull);
  });
}
