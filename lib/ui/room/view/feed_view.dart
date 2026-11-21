// ============================================================
// view/feed_view.dart — 聊天 / 记录 / 私密栏只读派生（设计 §3.6）
//
// ★ 纯 Dart：零 UI 框架依赖。
// ★ C6：绝不调 LogRecord.toWireJson()；`redacted` 行只取 text。
// ★ K8：结构化骰子气泡只用于公开骰（state.dice）；私密/暗骰只渲 text。
// ★ 私密栏只取 `{seq,title,text,at,kind}` 五键，不解析、不还原。
// ============================================================

import 'package:dice_realm/domain/avatar_uri.dart' show roomAvatarDataUri;
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_state.dart'
    show roomClone, roomNumber;
import '../room_text.dart';

enum FeedKind { sys, note, chat, dice, check, opposed }

/// 一条合并后的信息流（不可变值对象）。
class FeedItem {
  const FeedItem({
    required this.seq,
    required this.at,
    required this.kind,
    this.seat = '',
    this.nickname = '',
    this.text = '',
    this.avatar = '',
    this.dice,
    this.opp,
    this.redacted = false,
  });

  final int seq;
  final num at;
  final FeedKind kind;
  final String seat, nickname, text;

  /// 这一条**左侧要显示的头像值**：跨设备缩略 dataURI
  /// （`data:image/(png|jpe?g|webp);base64,`，≤20000 字符）。
  ///
  /// 来源不是条目自己带的字段，而是「按 `seat` 反查成员表」的表头头像 ——
  /// 与老 APP `room-ui.js:4106-4111` `feedAvatarForSeat` /
  /// `room-panels.js:1572` `feedAvatar` 完全同一口径：
  /// 聊天 / 骰子 / 检定条目左侧显示**发言人**的缩略头像，没有就退回首字。
  /// 空串 = 这一条不渲染头像（系统提示 / 没有 seat 的条目）。
  final String avatar;

  /// 仅 [FeedKind.dice]（公开骰）持有；结构化字段，供气泡渲染。
  final Map<String, Object?>? dice;

  /// 仅 `logs[kind=='check'] && opp != null` 的对抗结果卡持有。
  final Map<String, Object?>? opp;

  /// true → **只能**渲染 [text]，不得还原结果。
  final bool redacted;
}

/// 按 seat 反查成员头像值（对齐老 APP `feedAvatarForSeat`）。
///
/// 只认**缩略 dataURI**：原图可能是几 MB 的 dataURL，广播里本来就不会带
/// （`sanitizeSheet` 已卡 20000 字符上限），这里再审一次是为了「即使存档 /
/// 旧数据里塞了超限原图，也绝不把它画到列表里」。
/// 找不到成员 / 没有头像 / 不合规 → 空串。
String feedAvatarOfSeat(Map<String, Object?> state, String seat) {
  if (seat.isEmpty) return '';
  for (final row in asList(state['members'])) {
    final m = asMap(row);
    if (roomText(m['seat']) != seat) continue;
    return roomAvatarDataUri(asMap(m['sheet'])['avatar']);
  }
  return '';
}

num _at(Object? v) => roomNumber(v, 0);

String _fmt(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

FeedKind _logKind(String raw, Object? opp, bool redacted) {
  if (redacted) return FeedKind.check;
  if (raw == 'check') return opp is Map ? FeedKind.opposed : FeedKind.check;
  if (raw == 'chat') return FeedKind.chat;
  if (raw == 'dice') return FeedKind.dice;
  if (raw == 'note') return FeedKind.note;
  return FeedKind.sys;
}

void _sortByAt(List<FeedItem> rows) {
  rows.sort((a, b) {
    final c = a.at.compareTo(b.at);
    return c != 0 ? c : a.seq.compareTo(b.seq);
  });
}

List<FeedItem> _tail(List<FeedItem> rows, int limit) {
  if (limit <= 0) return <FeedItem>[];
  if (rows.length <= limit) return rows;
  return rows.sublist(rows.length - limit);
}

/// logs + dice 按 `at` 升序合并（同 at 按 seq），取最近 [limit] 条（默认 120）。
/// 返回值仍保持**时间正序**，聊天/记录列表直接从上往下渲染即可。
List<FeedItem> collectFeeds(Map<String, Object?> state, {int limit = 120}) {
  final out = <FeedItem>[];

  for (final row in asList(state['logs'])) {
    final r = asMap(row);
    final redacted = jsTruthy(r['redacted']);
    // ★ redacted 行只取 text：seat / opp / 结构化结果一律不进 FeedItem。
    final oppRaw = redacted ? null : r['opp'];
    final seat = redacted ? '' : roomText(r['seat']);
    out.add(FeedItem(
      seq: jsNum(r['seq']),
      at: _at(r['at']),
      kind: _logKind(roomText(r['kind']), oppRaw, redacted),
      seat: seat,
      text: roomText(r['text']),
      avatar: redacted ? '' : feedAvatarOfSeat(state, seat),
      opp: oppRaw is Map ? asMap(roomClone(oppRaw)) : null,
      redacted: redacted,
    ));
  }

  for (final row in asList(state['dice'])) {
    final d = asMap(roomClone(row));
    final seat = roomText(d['seat']);
    out.add(FeedItem(
      seq: jsNum(d['seq']),
      at: _at(d['at']),
      kind: FeedKind.dice,
      seat: seat,
      nickname: roomText(d['nickname']),
      text: diceLine(d),
      avatar: feedAvatarOfSeat(state, seat),
      dice: d,
    ));
  }

  _sortByAt(out);
  return _tail(out, limit);
}

/// 聊天栏：state.chats 的最近 [limit] 条（默认 60），时间正序。
List<FeedItem> collectChats(Map<String, Object?> state, {int limit = 60}) {
  final out = <FeedItem>[];
  for (final row in asList(state['chats'])) {
    final r = asMap(row);
    final seat = roomText(r['seat']);
    out.add(FeedItem(
      seq: jsNum(r['seq']),
      at: _at(r['at']),
      kind: FeedKind.chat,
      seat: seat,
      nickname: roomText(r['nickname']),
      text: roomText(r['text']),
      avatar: feedAvatarOfSeat(state, seat),
    ));
  }
  _sortByAt(out);
  return _tail(out, limit);
}

/// 私密栏：最近 [limit] 条（默认 12），**正序**（最新在最后）。
/// ★ 只保留五键；`state.privates` 已是权威端裁剪后的本座位数据，UI 不二次过滤。
List<Map<String, Object?>> collectPrivates(
  Map<String, Object?> state, {
  int limit = 12,
}) {
  if (limit <= 0) return <Map<String, Object?>>[];
  final rows = asList(state['privates']);
  final start = rows.length > limit ? rows.length - limit : 0;
  final out = <Map<String, Object?>>[];
  for (var i = start; i < rows.length; i++) {
    final r = asMap(rows[i]);
    out.add(<String, Object?>{
      'seq': jsNum(r['seq']),
      'title': roomText(r['title']),
      'text': roomText(r['text']),
      'at': _at(r['at']),
      'kind': roomText(r['kind']),
    });
  }
  return out;
}

/// §1.4 重绘范式里 `privRowsOf(s, seat)` 的抓手。
/// [seat] 仅用于签名对齐（私密数据是按座位裁剪好的，不需要再按 seat 过滤）。
List<Map<String, Object?>> privRowsOf(
  Map<String, Object?> state,
  String seat, {
  int limit = 12,
}) =>
    collectPrivates(state, limit: limit);

/// 公开骰单行文案：'侦查：1D100 → 42 · 困难成功'。
///
/// ★ P10 第 3 期 A 批（用户：「roll 点 / 检定结果看不出是谁、检定什么，
///   等于没广播」）：技能名（`label`）必须出现在行内。
///   老 APP `room-panels.js:1593-1601` 的骰子是两行：
///     `昵称 · 1D100 ＝ 42`
///     `常规成功 · 侦查`
///   这里把「技能名」并进同一行（记录栏是单行渲染），昵称由 `FeedRow` 前置；
///   与老 APP 的信息量对齐：谁 / 什么技能 / 掷了多少 / 什么成功等级。
///   `label` 为空（快捷骰 1D6 之类）时行为与改前**逐字节相同**。
/// ★ 不按 rolls 自己算总值；total / level 整键不存在时按「有没有给」分支。
String diceLine(Map<String, Object?> d) {
  final label = roomText(d['label']);
  final expr = roomText(d['expr']);
  final buf = StringBuffer();
  if (label.isNotEmpty) buf.write('$label：');
  buf.write(expr.isEmpty ? '骰子' : expr);
  buf.write(' → ');
  final total = d['total'];
  if (_finiteNum(total) != null) {
    buf.write(_fmt(total as num));
  } else if (d.containsKey('level') && d['level'] != null) {
    buf.write(roomText(d['level']));
  } else {
    buf.write('—');
  }
  final levelText = roomText(d['levelText']);
  if (levelText.isNotEmpty) buf.write(' · $levelText');
  // ★ P11：被幸运改过的 / 推动重掷出来的记录，行内必须能看出「这条不是原样」，
  //   否则同技能的两行数字对不上，玩家会以为骰子被篡改。
  final luck = _finiteNum(d['luckSpent']);
  if (luck != null && luck > 0) buf.write('（花 ${_fmt(luck)} 点幸运）');
  final pushFrom = _finiteNum(d['pushFrom']);
  if (pushFrom != null) buf.write('（推动重掷，原 ${_fmt(pushFrom)}）');
  return buf.toString();
}

/// 一条**未结算检定**上还能做的两个动作（P11 花幸运 / 推动检定）。
///
/// ★ 为什么是个值对象而不是「在行里现算」：`FeedRow` 拿不到 `mySeat` / 余额，
///   而这些判定是纯粹的协议推导（与权威端 `_spendLuck` / `_canPush` 同一口径），
///   放在 view 层才能被单测逐条钉死。
class FeedCheckAction {
  const FeedCheckAction({
    required this.seq,
    required this.luckAmount,
    required this.canPush,
    required this.label,
  });

  /// 对应那条 `state.dice` 记录（也是按钮的 key 后缀）。
  final int seq;

  /// 恰好压到成功所需的点数；0 = 不可花（不渲染按钮）。
  final int luckAmount;

  /// 能否推动（不可推动时不渲染按钮）。
  final bool canPush;

  /// 技能名（只用于 hint，不含结果信息）。
  final String label;

  bool get canLuck => luckAmount > 0;

  String get luckLabel => '花 $luckAmount 点幸运改为成功';
  static const String pushLabel = '推动检定（重掷一次）';
}

/// 该座位自己那条「最近一次掷骰」的可操作项；不可操作时返回 null。
///
/// [isLatestOfSeat] 由调用方按「该 seat 在列表里最后一条骰」判定 —— 权威端
/// `lastDiceOf(seat)` 就是这个口径，两边必须一致，否则会出现「按钮点了被拒」。
FeedCheckAction? checkActionOf(
  FeedItem item, {
  required String mySeat,
  required String role,
  required bool isLatestOfSeat,
  required int luck,
}) {
  if (role != 'player') return null;
  if (mySeat.isEmpty || item.seat != mySeat) return null;
  if (item.kind != FeedKind.dice || !isLatestOfSeat) return null;
  final d = item.dice;
  if (d == null || !d.containsKey('target')) return null;
  final levelKey = roomText(d['level']);
  // 大失败：幸运抹不掉、也不能推动（规则书明确）。
  if (levelKey == 'fumble') return null;
  final value = _finiteNum(d['total']);
  final target = _finiteNum(d['target']);
  if (value == null || target == null) return null;
  final need = (value - target).toInt();
  final failed = levelKey == 'fail';
  final kind = roomText(d['kind']);
  const pushableKinds = <String>{'skill', 'attribute', 'characteristic'};
  // 与规则层 `_luckForbidden` 同表：幸运点不能用来改幸运 / 理智 / 伤害类检定。
  const luckForbiddenKinds = <String>{
    'luck',
    'san',
    'sanity',
    'sanloss',
    'damage',
  };
  final luckAmount = failed &&
          need > 0 &&
          luck >= need &&
          !luckForbiddenKinds.contains(kind)
      ? need
      : 0;
  final canPush = failed &&
      !jsTruthy(d['pushed']) &&
      pushableKinds.contains(kind.isEmpty ? 'skill' : kind);
  if (luckAmount <= 0 && !canPush) return null;
  return FeedCheckAction(
    seq: item.seq,
    luckAmount: luckAmount,
    canPush: canPush,
    label: roomText(d['label']),
  );
}

/// 自己那张卡的当前幸运点（`state.members` 里本人那份是**未裁剪**的）。
///
/// 拿不到就返回 0 —— 按钮不渲染，而不是渲染一个点了必被拒的按钮。
int selfLuckOf(Map<String, Object?> state, String seat) {
  if (seat.isEmpty) return 0;
  for (final row in asList(state['members'])) {
    final m = asMap(row);
    if (roomText(m['seat']) != seat) continue;
    final st = asMap(asMap(m['sheet'])['status']);
    final v = st['currentLuck'];
    if (v is num) return v.toInt();
    return 0;
  }
  return 0;
}

num? _finiteNum(Object? v) {
  if (v is num && !v.isNaN && !v.isInfinite) return v;
  return null;
}

/// 检定行单行文案；redacted 时恒为 text（K8，不得还原 / 不得加「点击查看」）。
String checkLine(FeedItem it) {
  if (it.redacted) return it.text;
  final opp = it.opp;
  if (opp != null) {
    if (jsTruthy(opp['tie'])) return '${it.text} · 平局';
    final winner = roomText(opp['winner']);
    if (winner.isNotEmpty) return '${it.text} · $winner 胜';
  }
  return it.text;
}
