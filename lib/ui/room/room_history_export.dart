// ============================================================
// room_history_export.dart — P2-06「导出文本」纯函数层
//
// ★ 纯 Dart：零 UI 框架依赖、零文件读写、零平台通道、零网络。
//   「state + 视角 → 导出文本」：同样的入参恒得同样的字符串，可完整单测。
//
// ★ K3 / 脱敏红线：**只从既有只读派生取公开字段** ——
//   · 抬头取 view/room_view.dart 的 meta / 成员（昵称、角色名、座位）；
//   · 正文取 view/feed_view.dart 的 collectFeeds / collectChats / checkLine，
//     二者已是「当前座位可见公开信息流」的唯一裁剪口径。
//   本文件绝不自己遍历权威日志、公开骰原始表或私密栏，也不碰事件日志的
//   对外序列化结果（那份带明文载荷）；更不解析角色卡、暗骰结果、私有素材。
//   redacted 行只渲公开 text，结构化结果一律不还原。
//
// ★ 空值安全：所有取值走 roomText（null 当空串），界面与文本都不印字面量
//   null；这也是 UI 层既有的唯一取文本口径，没有第二套实现。
//
// ★ 视角：入参 state 是「当前座位已裁剪过的会话状态」，过滤发生在数据层；
//   seat / role 只用于抬头如实写清导出视角，不参与二次过滤（二次隐藏会让
//   跨视角用例假绿，与 T8 冲突）。
// ============================================================

import 'package:dice_realm/domain/room_types.dart' show kHostSeat;

import 'room_text.dart';
import 'view/feed_view.dart'
    show FeedItem, checkLine, collectChats, collectFeeds;
import 'view/room_view.dart'
    show codeOf, kpNameOf, membersOf, roleText, roomNameOf;

/// 单行正文的最大字符数（按 Unicode 码点计）。超出按 [kRoomHistoryClipSuffix]
/// 收口，避免一条超长文本把整份导出撑爆或破坏编号行格式。
const int kRoomHistoryMaxLineChars = 160;

/// 游戏记录 / 聊天显示上限，与 U11「记录 120、聊天 60」同源。
const int kRoomHistoryFeedLimit = 120;
const int kRoomHistoryChatLimit = 60;

/// 截断标记。
const String kRoomHistoryClipSuffix = '…（已截断）';

/// 两个分节的空态文案。
const String kRoomHistoryEmptyFeeds = '（该团没有游戏记录）';
const String kRoomHistoryEmptyChats = '（没有聊天记录）';

/// 旧版 `archiveLogTime` 的口径：YYYY-MM-DD HH:MM:SS。
///
/// 入参是毫秒时间戳；0 / 负数 / 非有限值一律返回空串（调用方据此决定
/// 是否写方括号），绝不返回一个假装是 1970 年的时间。
String formatHistoryTime(num ms) {
  if (ms.isNaN || ms.isInfinite) return '';
  final t = ms.toInt();
  if (t <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  String p(int n) => n < 10 ? '0$n' : '$n';
  return '${d.year}-${p(d.month)}-${p(d.day)} '
      '${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
}

/// 把任意值摊平成单行纯文本：空值 → 空串，换行 / 制表符 → 空格。
///
/// 换行必须摊平：导出是「一行一条编号记录」，正文里带换行会伪造出额外的
/// 记录行，也会让「共 N 条」与实际行数对不上。
String _flat(Object? v) {
  final s = roomText(v);
  if (s.isEmpty) return '';
  return s
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('\t', ' ');
}

/// 按 Unicode 码点截断（不拆坏 emoji / 代理对）。
///
/// [maxLineChars] <= 0 表示不截断；这是显式口径，不是隐式兜底。
String _clip(String s, int maxLineChars) {
  if (s.isEmpty || maxLineChars <= 0) return s;
  final runes = s.runes.toList(growable: false);
  if (runes.length <= maxLineChars) return s;
  return '${String.fromCharCodes(runes.take(maxLineChars))}'
      '$kRoomHistoryClipSuffix';
}

/// 取值 + 摊平 + 截断，正文与抬头共用的唯一入口。
String _cell(Object? v, int maxLineChars) =>
    _clip(_flat(v), maxLineChars);

/// 成员名单：`昵称（角色名）`，用「、」连接；整体为空写「无」。
/// 只读 nickname / charName 两列，角色卡与其它座位私有字段一概不碰。
String _membersLine(Map<String, Object?> state, int maxLineChars) {
  final names = <String>[];
  for (final m in membersOf(state)) {
    final nick = _cell(m['nickname'], maxLineChars);
    final charName = _cell(m['charName'], maxLineChars);
    final label = nick.isEmpty ? '?' : nick;
    names.add(charName.isEmpty ? label : '$label（$charName）');
  }
  return names.isEmpty ? '无' : names.join('、');
}

/// seat → 成员显示名（昵称优先，其次角色名，最后退到座位号）。
Map<String, String> _seatNames(Map<String, Object?> state, int maxLineChars) {
  final out = <String, String>{};
  for (final m in membersOf(state)) {
    final seat = _cell(m['seat'], maxLineChars);
    if (seat.isEmpty) continue;
    final nick = _cell(m['nickname'], maxLineChars);
    final charName = _cell(m['charName'], maxLineChars);
    out[seat] = nick.isNotEmpty
        ? nick
        : (charName.isNotEmpty ? charName : '座位$seat');
  }
  return out;
}

/// 一条信息流的执行者显示名。
///
/// 与旧版 `archiveLogActor` 对齐：host → KP 名、成员 seat → 昵称 / 角色名、
/// 查不到 → 座位号系统兜底。**唯一有意的差异**：redacted（暗骰）行统一写
/// 「系统」，不写「KP（暗骰）」—— 连「这里发生过暗骰」这一元信息都不写进
/// 导出文本；该行只带权威端已公开的占位 text。
String _actorOf(
  FeedItem it,
  Map<String, String> bySeat,
  String kpName,
  int maxLineChars,
) {
  if (it.redacted) return '系统';
  if (it.seat == kHostSeat) return kpName.isEmpty ? 'KP' : kpName;
  final nick = _cell(it.nickname, maxLineChars);
  if (nick.isNotEmpty) return nick;
  final fromMember = bySeat[it.seat];
  if (fromMember != null && fromMember.isNotEmpty) return fromMember;
  final seat = _cell(it.seat, maxLineChars);
  return seat.isEmpty ? '系统' : '座位$seat';
}

/// 时间方括号。没有 at 时旧版写 `[] `，这里同口径。
String _stamp(FeedItem it) => '[${formatHistoryTime(it.at)}] ';

/// 「共 N 条」分节头（两个分节同款，避免两处格式漂移）。
List<String> _sectionHead(String title, int count) => <String>[
      '$title（共 $count 条）',
      '--------------------------------',
    ];

/// ★ 主入口：state + 视角 → 导出文本。
///
/// [exportedAtMs] 由调用方注入（纯函数不自行读系统时钟）；为 null 时
/// 抬头写「—」。[feedLimit] / [chatLimit] 与信息流显示口径一致，
/// [maxLineChars] 是单行截断口径，<= 0 表示不截断。
///
/// 抬头字段与旧版 `exportArchiveText` 逐项对应：标题、分隔线、房间名 /
/// 房间号、KP、时间、成员；正文分「游戏记录」「聊天记录」两节，都是时间
/// 正序 + 从 1 开始编号 + `[时间] 执行者：内容`。
/// 差异（已在交付报告的「关键决策」写明）：旧版导出的是**结团归档**，
/// 抬头是「结束时间」且只带 logs；本工程导出的是**当前会话视角的公开
/// 信息流**，抬头改用「导出时间」，并按既有只读口径把公开聊天单列一节。
String buildRoomHistoryExportText(
  Map<String, Object?> state, {
  required String seat,
  required String role,
  int? exportedAtMs,
  int feedLimit = kRoomHistoryFeedLimit,
  int chatLimit = kRoomHistoryChatLimit,
  int maxLineChars = kRoomHistoryMaxLineChars,
}) {
  final code = _cell(codeOf(state), maxLineChars);
  final name = _cell(roomNameOf(state), maxLineChars);
  final kpName = _cell(kpNameOf(state), maxLineChars);
  final bySeat = _seatNames(state, maxLineChars);
  final feeds = collectFeeds(state, limit: feedLimit);
  final chats = collectChats(state, limit: chatLimit);

  final out = <String>[
    '跑团游戏历史记录',
    '================================',
    '房间：${name.isEmpty ? '房间 $code' : name}（房间号 $code）',
    'KP：${kpName.isEmpty ? '—' : kpName}',
    '导出时间：${exportedAtMs == null ? '—' : formatHistoryTime(exportedAtMs)}',
    '成员：${_membersLine(state, maxLineChars)}',
    '导出视角：${_cell(roleText(role), maxLineChars)} · '
        '座位 ${_cell(seat, maxLineChars)}',
    '说明：仅含当前视角可见的公开记录与聊天；私密笔记、暗骰结果、'
        '角色卡与其它座位的私有字段不导出。',
    '',
    ..._sectionHead('游戏记录', feeds.length),
  ];

  if (feeds.isEmpty) {
    out.add(kRoomHistoryEmptyFeeds);
  } else {
    for (var i = 0; i < feeds.length; i++) {
      final it = feeds[i];
      // redacted 行恒取公开 text；非 redacted 行走 UI 同款 checkLine
      // （只拼对抗胜负文案，不还原结构化结果）。
      final body = it.redacted
          ? _cell(it.text, maxLineChars)
          : _cell(checkLine(it), maxLineChars);
      out.add('${i + 1}. ${_stamp(it)}'
          '${_actorOf(it, bySeat, kpName, maxLineChars)}：$body');
    }
  }

  out.addAll(<String>['', ..._sectionHead('聊天记录', chats.length)]);
  if (chats.isEmpty) {
    out.add(kRoomHistoryEmptyChats);
  } else {
    for (var i = 0; i < chats.length; i++) {
      final it = chats[i];
      final actor = _actorOf(it, bySeat, kpName, maxLineChars);
      out.add('${i + 1}. ${_stamp(it)}$actor：'
          '${_cell(it.text, maxLineChars)}');
    }
  }

  return out.join('\n');
}
