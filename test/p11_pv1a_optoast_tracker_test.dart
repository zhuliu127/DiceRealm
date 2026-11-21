// ============================================================
// test/p11_pv1a_optoast_tracker_test.dart — PV-1a 遮罩广播六项判据
//
// 被测：lib/ui/room/feed_optoast_tracker.dart（纯 Dart，零 Flutter 依赖）
// 六项：① 首次只登基线 ② 增量≤6 逐条升序且含自己发的 ③ >6 视为全量同步
//       ④ syncEpoch 变化 / reset 重登基线 ⑤ chat 排除 + redacted 只取 text
//          + \s+ 归并 + >40 截断 + dice 文案 ⑥ 空文案不入列
// ============================================================

import 'package:dice_realm/ui/room/feed_optoast_tracker.dart';
import 'package:dice_realm/ui/room/view/feed_view.dart' show FeedItem, FeedKind;
import 'package:flutter_test/flutter_test.dart';

FeedItem _it(
  int seq, {
  FeedKind kind = FeedKind.sys,
  String seat = '',
  String nickname = '',
  String text = '',
  Map<String, Object?>? dice,
  Map<String, Object?>? opp,
  bool redacted = false,
}) =>
    FeedItem(
      seq: seq,
      at: seq,
      kind: kind,
      seat: seat,
      nickname: nickname,
      text: text,
      dice: dice,
      opp: opp,
      redacted: redacted,
    );

void main() {
  group('PV-1a 六项判据', () {
    test('① 首次 sync 返回 [] 并登记基线（不弹历史）', () {
      final t = FeedOptoastTracker();
      expect(t.initialized, isFalse);
      expect(t.lastSeq, isNull);
      final out = t.sync(<FeedItem>[_it(1, text: 'a'), _it(2, text: 'b')],
          syncEpoch: 0);
      expect(out, isEmpty, reason: '首次只建基线');
      expect(t.initialized, isTrue);
      expect(t.lastSeq, 2);
    });

    test('② 增量 ≤6 条按 seq 升序逐条返回，且含本机 seat 的那条', () {
      final t = FeedOptoastTracker();
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      final out = t.sync(<FeedItem>[
        _it(1, text: 'a'),
        _it(3, kind: FeedKind.check, seat: 'p1', text: '我自己的检定'),
        _it(2, kind: FeedKind.check, seat: 'p2', text: '别人的检定'),
      ], syncEpoch: 0);
      expect(out, <String>['别人的检定', '我自己的检定'],
          reason: '按 seq 升序；本机 seat 的也要播（与 FeedFlashTracker 相反）');
    });

    test('③ 一次 7 条（>kOptoastFlood=6）→ [] 且基线已推进，下批不重弹', () {
      final t = FeedOptoastTracker();
      expect(kOptoastFlood, 6);
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      final List<FeedItem> flood = <FeedItem>[
        _it(1, text: 'a'),
        for (var i = 2; i <= 8; i++) _it(i, text: 'm$i'),
      ];
      expect(t.sync(flood, syncEpoch: 0), isEmpty, reason: '>6 视为全量同步');
      expect(t.lastSeq, 8, reason: '基线必须先推进');
      expect(t.sync(<FeedItem>[...flood, _it(9, text: '新')], syncEpoch: 0),
          <String>['新'], reason: '下一批只弹真正新增的那条');
    });

    test('④ syncEpoch 变化 → [] 并重登基线；reset() 后首次仍 []', () {
      final t = FeedOptoastTracker();
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      expect(
          t.sync(<FeedItem>[_it(1, text: 'a'), _it(2, text: 'b')],
              syncEpoch: 1),
          isEmpty,
          reason: '世代变化视为补拉，不弹');
      expect(t.lastSeq, 2, reason: '重登基线到 2');
      t.reset();
      expect(t.initialized, isFalse);
      expect(t.lastSeq, isNull);
      expect(t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 1), isEmpty);
    });

    test('⑤ chat 被排除且不抬基线', () {
      final t = FeedOptoastTracker();
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      final out = t.sync(<FeedItem>[
        _it(1, text: 'a'),
        _it(5, kind: FeedKind.chat, text: '聊天不该播'),
      ], syncEpoch: 0);
      expect(out, isEmpty);
      expect(t.lastSeq, 1, reason: 'chat 不参与 maxSeq');
    });

    test('⑤b redacted 只取公开 text（不还原结构化结果）', () {
      final t = FeedOptoastTracker();
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      final out = t.sync(<FeedItem>[
        _it(1, text: 'a'),
        _it(6,
            kind: FeedKind.opposed,
            redacted: true,
            text: '  私密   内容  ',
            opp: <String, Object?>{'winner': 'a', 'total': 999}),
      ], syncEpoch: 0);
      expect(out, <String>['私密 内容'],
          reason: 'redacted 只用 text，且 \\s+ 归并 + trim；不得出现 opp 里的 999');
    });

    test('⑤c \\s+ 归并 + 41 字截断为 39 字 + …', () {
      expect(kOptoastMaxChars, 40);
      final t = FeedOptoastTracker();
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      final String long = '一二三四五六七八九十' * 5; // 50 字
      final out = t.sync(<FeedItem>[
        _it(1, text: 'a'),
        _it(2, text: '  多   空格\n换行  '),
        _it(3, text: long),
      ], syncEpoch: 0);
      expect(out.first, '多 空格 换行');
      expect(out[1].length, kOptoastMaxChars,
          reason: '39 字 + 1 个省略号 = 40 个 UTF-16 code unit');
      expect(out[1].endsWith('…'), isTrue);
      expect(out[1], '${long.substring(0, 39)}…');
    });

    test('⑤d dice 行含昵称 / ＝total / levelText', () {
      final t = FeedOptoastTracker();
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      final out = t.sync(<FeedItem>[
        _it(1, text: 'a'),
        _it(2, kind: FeedKind.dice, nickname: '阿明', dice: <String, Object?>{
          'label': '侦查',
          'expr': '1D100',
          'total': 42,
          'levelText': '成功',
        }),
      ], syncEpoch: 0);
      expect(out, <String>['阿明 掷 侦查＝42 成功']);
    });

    test('⑥ 空文案（trim 后为空）不入列', () {
      final t = FeedOptoastTracker();
      t.sync(<FeedItem>[_it(1, text: 'a')], syncEpoch: 0);
      final out = t.sync(<FeedItem>[
        _it(1, text: 'a'),
        _it(2, text: '   '),
        _it(3, text: '有效'),
      ], syncEpoch: 0);
      expect(out, <String>['有效']);
    });

    test('常量契约：kOptoastMax=3 / kOptoastFlood=6 / kOptoastMaxChars=40 / TTL=2s',
        () {
      expect(kOptoastMax, 3);
      expect(kOptoastFlood, 6);
      expect(kOptoastMaxChars, 40);
      expect(kOptoastTtl, const Duration(seconds: 2));
      // 类内同值入口与顶层一致
      expect(FeedOptoastTracker.kOptoastMax, kOptoastMax);
      expect(FeedOptoastTracker.kOptoastFlood, kOptoastFlood);
      expect(FeedOptoastTracker.kOptoastMaxChars, kOptoastMaxChars);
      expect(FeedOptoastTracker.kOptoastTtl, kOptoastTtl);
    });
  });
}
