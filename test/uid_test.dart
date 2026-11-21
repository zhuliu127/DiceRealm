// ============================================================
// uid_test.dart — uid() 换成 Random.secure() 的守卫
//
// P0 报告记录的坑：旧实现的默认随机源是
// `DateTime.now().microsecondsSinceEpoch % 1000000`，同一微秒内连续取 8 次
// 拿到的是同一个数 → 8 位 id 完全相同 → 同一微秒连建两张卡必撞 id，
// 后一张直接覆盖前一张（repo 是 `cards[id] = card`）。
//
// 这条测试同时证明：改 uid 没有连带影响 newCharacter / recalc。
// （uid 的值本身不在 oracle 的比对范围内；预言机靠 `uidDeterministic`
//   走旧序列，见 test/support/oracle.dart。）
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    // 其他测试文件可能把它置过；这里显式保证走生产路径
    uidDeterministic = false;
  });
  tearDown(() => uidDeterministic = false);

  test('uid 是 8 位小写字母 / 数字，且 1000 次内无重复', () {
    final seen = <String>{};
    for (var i = 0; i < 1000; i++) {
      final id = uid();
      expect(id.length, 8);
      expect(RegExp(r'^[a-z0-9]{8}$').hasMatch(id), isTrue, reason: '非法字符：$id');
      seen.add(id);
    }
    expect(seen.length, 1000, reason: '1000 次生成不应该出现任何重复');
  });

  test('同一「微秒」内连续建卡 200 张，id 全部不同（旧实现会全部相同）', () {
    // 把时钟钉死在同一毫秒 / 随机源钉死成同一个值 —— 这正是旧实现撞 id 的条件
    final prevClock = nowClock;
    final prevRng = nowRng;
    setClock(() => 1700000000000);
    setRng(() => 0.5);
    try {
      final ids = <String>{};
      for (var i = 0; i < 200; i++) {
        ids.add(newCharacter()['id']! as String);
      }
      expect(ids.length, 200, reason: 'Random.secure() 不该受时钟 / 注入源影响');
    } finally {
      setClock(prevClock);
      setRng(prevRng);
    }
  });

  test('uidDeterministic=true 时回到旧序列（预言机靠它逐字比对 id）', () {
    uidDeterministic = true;
    setClock(() => 1700000000000);
    setRng(() => 0.5);
    final a = uid();
    final b = uid();
    expect(a, b, reason: '注入源恒定时旧序列必然相同 —— 这正是它只能在测试里用的原因');
    expect(a.length, 8);
  });

  test('改 uid 没有连带影响 newCharacter 的结构与 recalc 的派生值', () {
    final c = Character(newCharacter());
    for (final k in <String>[
      'str',
      'con',
      'siz',
      'dex',
      'app',
      'int',
      'pow',
      'edu',
      'luck',
    ]) {
      c.attributes[k] = 50;
    }
    recalc(c);
    expect(jsNum(c.status['maxHP']), 10);
    expect(jsNum(c.status['maxMP']), 10);
    expect(jsNum(c.status['currentSAN']), 50);
    expect(c.raw.containsKey('characterName'), isTrue);
    expect(c.id.length, 8);
  });
}
