// ============================================================
// room_feed_flash_test.dart — 信息流闪烁判据（PRD P2-05，纯逻辑）
//
// 这个文件守的是「什么时候**不该**闪」，以及 Round 2 之后「什么时候**该**闪」。
// 闪错了比不闪更糟：进房间时几十条历史一起闪 = 放烟花；自己刚发的消息
// 闪一下 = 莫名其妙；断线重连补拉几十条闪一下 = 看起来像出 bug。
//
// ★ Round 2：原先用「全局 evt.seq 的差值」同时猜「断线补拉」和「一次
//   涌入太多」，两条都判错（QA 报告 §4.1 / §4.2）。现在 seq 差判据整个退役：
//     · 补拉由连接层 RoomSession.syncEpoch 显式告知，GpFeeds 见到世代
//       变化就 reset()（见 room_sync_epoch_test.dart 的真实链路回归）；
//     · 判据只回答「有没有新条目、是不是自己发的」，不再猜批次语义。
//   下面第 8 / 9 / 11 组是从旧版 flood 边界用例**如实重写**而来，不是悄悄
//   删用例：判据变了，用例的目标值要跟着变，且必须写清为什么变。
//
// ★ 这里刻意不 pump 任何 widget：判据是纯 Dart，能脱离 FakeAsync 直接跑，
//   也便于接线测试把 tracker 换成一个「恒不闪」的替身做反向验证。
// ============================================================

import 'package:dice_realm/ui/room/room_feed_flash.dart' show FeedFlashTracker;
import 'package:flutter_test/flutter_test.dart';

/// 造一个「已经画过首屏」的 tracker（首绘只登记基线、返回 null）。
///
/// Round 2 之后 [FeedFlashTracker] 是无参构造：判据不再持有任何阈值参数，
/// 「一次涌入多少算补拉」这件事已整体搬去连接层世代信号。
FeedFlashTracker _seeded(int seq) {
  final t = FeedFlashTracker();
  // 首绘：历史消息不算新，返回 null 是契约的一部分。
  expect(
    t.check(lastSeq: seq, lastSeat: 'p1', mySeat: 'host'),
    isNull,
    reason: '前置：_seeded 必须真的把基线登记好，否则后面的断言会空转',
  );
  return t;
}

const String _other = 'p2';
const String _mine = 'host';

void main() {
  group('P2-05 · FeedFlashTracker 判据（Round 2：seq 差规则已退役）', () {
    test('★ 首次 check 返回 null（只登记基线、不闪）', () {
      // 为什么存在：进房间时那几十条历史消息不是「新消息」。
      // 全闪一遍等于给用户放烟花，而且用户根本没漏读任何东西。
      final t = FeedFlashTracker();
      expect(t.check(lastSeq: 12, lastSeat: _other, mySeat: _mine), isNull,
          reason: '首屏必须有且只有一次「登记基线」的返回');
      expect(t.lastSeq, 12, reason: '基线要真的记下来，下次才能比较');
    });

    test('★ 空流（lastSeq <= 0）不闪，且**不登记基线**', () {
      // 为什么存在：空列表没有「最后一条」，拿 0 当基线会污染状态；
      // 空流只返回 false、不写状态，随后到达的第一条仍算「首屏」。
      final t = FeedFlashTracker();
      expect(t.check(lastSeq: 0, lastSeat: '', mySeat: _mine), isFalse);
      expect(t.lastSeq, isNull, reason: '空流不许污染基线');
      expect(t.check(lastSeq: -3, lastSeat: '', mySeat: _mine), isFalse,
          reason: '负数（异常序号）同样按空流处理');
      expect(t.lastSeq, isNull);

      // 随后到达的第一条仍算「首屏」：这正是规则 1 在空房间里的表现。
      expect(t.check(lastSeq: 9, lastSeat: _other, mySeat: _mine), isNull,
          reason: '空房间里的第一条也是首屏，不该闪');
    });

    test('同 seq 重绘不闪（没有新条目）', () {
      // 为什么存在：缩放 / 切 tab / 别人改了与本块无关的数据都会触发重绘，
      // 每次都闪等于把「重绘」误报成「新消息」。
      final t = _seeded(10);
      expect(t.check(lastSeq: 10, lastSeat: _other, mySeat: _mine), isFalse);
      expect(t.check(lastSeq: 10, lastSeat: _other, mySeat: _mine), isFalse);
    });

    test('seq 回退不闪（补拉乱序 / 状态重建不该当成新消息）', () {
      // 为什么存在：回退意味着「看到的内容变少了」，此时提醒「有新消息」
      // 是反的；宁可不闪也不能闪错。
      final t = _seeded(10);
      expect(t.check(lastSeq: 7, lastSeat: _other, mySeat: _mine), isFalse);
      expect(t.check(lastSeq: 7, lastSeat: _other, mySeat: _mine), isFalse);
    });

    test('★ +1 且是别人发的 → 该闪（最小正例）', () {
      // 为什么存在：这才是 P2-05 要提醒的真正场景 —— 一条我还不知道的、
      // 来自别人的新消息进来了。
      final t = _seeded(10);
      expect(t.check(lastSeq: 11, lastSeat: _other, mySeat: _mine), isTrue);
      expect(t.lastSeq, 11, reason: '判完基线要推进，否则下一条会重复闪');
    });

    test('★ 自己发的不闪', () {
      // 为什么存在：用户知道自己刚发了什么，闪了反而莫名其妙。
      // 旧版 feedFlashCheck 也是 `lastChat.seat !== mySeat` 才触发。
      final t = _seeded(10);
      expect(t.check(lastSeq: 11, lastSeat: _mine, mySeat: _mine), isFalse);
    });

    test('★ 系统消息（lastSeat 为空串）该闪', () {
      // 为什么存在：空串表示「无归属」（系统 / 脱敏行），不是自己。
      // 若写成 `lastSeat == mySeat` 就漏判，若把空串当成自己则漏报系统播报。
      final t = _seeded(10);
      expect(t.check(lastSeq: 11, lastSeat: '', mySeat: _mine), isTrue);
      // 自己座位也为空时（异常视角），空 lastSeat 仍不能被当成自己。
      final t2 = _seeded(10);
      expect(t2.check(lastSeq: 11, lastSeat: '', mySeat: ''), isTrue);
    });

    test('★ 判据退役：+6 / +7 / +30 只要是新条目且别人发的，都该闪', () {
      // ★ 如实重写（原用例：「恰好 6 条该闪 / 7 条不闪（flood 边界）」）。
      //
      // 为什么目标值变了：旧用例把 `lastSeq - prev > 6` 当成「断线补拉 /
      // 一次涌入太多」的判据。但 chats / logs / dice 每条的 seq 都是**全局
      // 事件序号**（room_model_reduce 三类事件共用 evt.seq），不是每列自己
      // 的序号。于是：
      //   · 两条聊天之间夹了 7 条骰子 → 聊天列差值虚高到 8，正常在线的
      //     新消息被误判成补拉而**漏闪**（QA 限制 3，jump=8）；
      //   · 短断线只漏 3 个事件 → 差值 3 够不到阈值，补拉回来的一批照样
      //     被当成新消息而**误闪**（QA 限制 2，10→13）。
      // 同一个错误抽象的两面，靠调阈值只是把出错场景挪位置。Round 2 让
      // 补拉改由连接层 syncEpoch 显式告知，判据侧彻底不看差值大小。
      // 所以这里 +6 / +7 / +30 全都是「别人发的新条目」→ 全部该闪。
      for (final jump in const <int>[6, 7, 30]) {
        final t = _seeded(10);
        expect(
          t.check(lastSeq: 10 + jump, lastSeat: _other, mySeat: _mine),
          isTrue,
          reason: '+$jump 是别人发的新条目，不再存在任何差值拐点',
        );
      }
    });

    test('★ 大跳跃不再抑制这一批，基线仍推进，下一次 +1 仍闪', () {
      // ★ 如实重写（原用例：「大跳跃只抑制这一批，基线仍推进」）。
      // 旧用例断言 +20 返回 false（被 flood 抑制）；判据退役后 +20 就该闪，
      // 且基线仍推进到 20 附近，下一次 +1 是又一条新消息，照常该闪。
      final t = _seeded(10);
      expect(t.check(lastSeq: 30, lastSeat: _other, mySeat: _mine), isTrue,
          reason: '差值 20 不代表补拉，也不代表本列涌入了 20 条');
      expect(t.lastSeq, 30, reason: '基线照样推进');
      expect(t.check(lastSeq: 31, lastSeat: _other, mySeat: _mine), isTrue,
          reason: '大跳跃之后没有「冷却期」，下一条新消息仍要正常闪');
    });

    test('★ reset() 后重新登记基线（换房间首屏不闪）', () {
      // 为什么存在：新房间的第一批历史消息与旧房间的 seq 毫无关系，
      // 不重置会拿旧房间的水位跟新房间比，要么放烟花要么永久不闪。
      final t = _seeded(10);
      expect(t.check(lastSeq: 11, lastSeat: _other, mySeat: _mine), isTrue);
      t.reset();
      expect(t.lastSeq, isNull);
      expect(t.check(lastSeq: 11, lastSeat: _other, mySeat: _mine), isNull,
          reason: '重置后第一次又是首屏');
      expect(t.check(lastSeq: 12, lastSeat: _other, mySeat: _mine), isTrue,
          reason: '重置后仍能正常工作');
    });

    test('★ 阈值参数已彻底移除：无参构造，不同差值行为完全一致', () {
      // ★ 如实重写（原用例：「floodThreshold 可配置（不只是写死的 6）」）。
      // 旧用例验证 `FeedFlashTracker(floodThreshold: 2)` 能把拐点挪到 +3。
      // Round 2 删掉了字段、构造参数与那条 if —— 判据里**不存在**任何可
      // 配置的阈值，也不该存在：阈值本身就是错抽象的产物。这里改为验证
      // 「无参构造 + 任意差值都不出现拐点」，与旧用例同强度（守同一处行为）。
      for (final jump in const <int>[1, 2, 3, 6, 7, 12]) {
        final t = FeedFlashTracker();
        expect(t.check(lastSeq: 10, lastSeat: _other, mySeat: _mine), isNull,
            reason: '+$jump 前置：先登记基线');
        expect(t.check(lastSeq: 10 + jump, lastSeat: _other, mySeat: _mine),
            isTrue,
            reason: '差值 $jump 不该改变「别人发的新条目要闪」这一结论');
      }
    });

    test('自己发的优先于「该闪」：序号前进但座位是自己 → 仍不闪', () {
      // 为什么存在：判据顺序必须稳定 —— 先排除无新增 / 回退，再排除自己。
      // 只要是自己发的，无论一次前进几条都不该闪。
      final t = _seeded(10);
      expect(t.check(lastSeq: 14, lastSeat: _mine, mySeat: _mine), isFalse);
    });

    test('连续多条别人消息：基线逐次推进，每条都闪（无冷却期）', () {
      // 为什么存在：退役 flood 之后不能引入「闪过一次就沉默一批」的退化；
      // 基线逐条推进，每条别人发的新消息都应独立触发。
      final t = _seeded(10);
      for (var seq = 11; seq <= 18; seq++) {
        expect(t.check(lastSeq: seq, lastSeat: _other, mySeat: _mine), isTrue,
            reason: '第 $seq 条别人消息必须闪');
        expect(t.lastSeq, seq);
      }
    });

    test('reset() 后空流仍不登记基线，下一条仍算首屏不闪', () {
      // 为什么存在：补拉 reset 之后若恰好渲染到空流（例如裁剪后本列无
      // 记录），不能把 0 写成基线；随后到达的第一条仍须按首屏处理。
      final t = _seeded(10);
      t.reset();
      expect(t.check(lastSeq: 0, lastSeat: '', mySeat: _mine), isFalse);
      expect(t.lastSeq, isNull);
      expect(t.check(lastSeq: 21, lastSeat: _other, mySeat: _mine), isNull,
          reason: 'reset 后的第一条非空 check 仍是首屏登记，不闪');
      expect(t.check(lastSeq: 22, lastSeat: _other, mySeat: _mine), isTrue,
          reason: '再下一条真新消息恢复正常闪');
    });
  });
}
