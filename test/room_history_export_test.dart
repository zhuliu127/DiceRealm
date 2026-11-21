// ============================================================
// room_history_export_test.dart — P2-06「导出文本」验收
//
// 判据分四层，每条 reason 都写清「这条判据为什么存在」：
//   ① 纯函数：旧版格式 / 分节 / 顺序 / 空态 / null / 截断 / 上限 / 视角；
//   ② K3 脱敏：秘密字段零泄漏、只输出公开列、redacted 行不还原；
//   ③ 静态口径：纯函数层零框架零 I/O、弹层零 Timer 零发包零权威赋值；
//   ④ 接线（T1 内存后端）：入口可点 → 弹层出现 → 完整文本可见 →
//      复制 / 分享回调被真实调用 → 四项真值前后不变。
//
// ★ 平台动作全部注入同步替身，零 Timer / 零延迟 / 零动画控制器；
//   「空 port」用例专门验证：平台动作什么都不做，文本仍完整可见、仍不撒谎。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File;

import 'package:dice_realm/domain/room_types.dart' show kHostSeat, RoomRole;
import 'package:dice_realm/ui/room/room_game_page.dart' show RoomGamePage;
import 'package:dice_realm/ui/room/room_history_export.dart'
    show
        buildRoomHistoryExportText,
        formatHistoryTime,
        kRoomHistoryChatLimit,
        kRoomHistoryClipSuffix,
        kRoomHistoryEmptyChats,
        kRoomHistoryEmptyFeeds,
        kRoomHistoryFeedLimit,
        kRoomHistoryMaxLineChars;
import 'package:dice_realm/ui/room/sheets/sheet_history_export.dart'
    show
        RoomHistoryExportKeys,
        RoomHistoryExportPort,
        kRoomHistoryExportPolicyOp;
import 'package:dice_realm/ui/room/sheets/sheet_misc.dart'
    show MiscSheet, MiscSheetKeys;
import 'package:dice_realm/ui/room/widgets/room_panel_kit.dart' show RoomTap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart';

/// 固定时钟：抬头「导出时间」在测试里可复算，不依赖机器时区之外的变量。
const int kFixedNowMs = 1700000000000;

// ------------------------------------------------------------
// 造 state 的小工具（纯数据，不碰权威端）
// ------------------------------------------------------------

Map<String, Object?> _state({
  String code = 'ABC123',
  String name = '测试团',
  String kpName = '老 K',
  List<Object?>? logs,
  List<Object?>? dice,
  List<Object?>? chats,
  List<Object?>? members,
  List<Object?>? privates,
  Map<String, Object?>? extra,
}) {
  final out = <String, Object?>{
    'meta': <String, Object?>{
      'code': code,
      'name': name,
      'kpName': kpName,
      'status': 'inGame',
    },
    'members': members ??
        <Object?>[
          <String, Object?>{
            'seat': 'p1',
            'nickname': '玩家1',
            'charName': '调查员甲',
            'role': RoomRole.player,
          },
          <String, Object?>{
            'seat': 'p2',
            'nickname': '玩家2',
            'charName': '',
            'role': RoomRole.player,
          },
        ],
    'logs': logs ?? <Object?>[],
    'dice': dice ?? <Object?>[],
    'chats': chats ?? <Object?>[],
    'privates': privates ?? <Object?>[],
  };
  if (extra != null) out.addAll(extra);
  return out;
}

Map<String, Object?> _log({
  required int seq,
  required num at,
  required String text,
  String kind = 'chat',
  String seat = 'p1',
  Object? opp,
  bool redacted = false,
  Object? p,
  Object? wire,
}) {
  final out = <String, Object?>{
    'seq': seq,
    'at': at,
    'text': text,
    'kind': kind,
    'seat': seat,
    'redacted': redacted,
  };
  if (opp != null) out['opp'] = opp;
  if (p != null) out['p'] = p;
  if (wire != null) out['wire'] = wire;
  return out;
}

Map<String, Object?> _chat({
  required int seq,
  required num at,
  required String text,
  String seat = 'p1',
  String nickname = '玩家1',
}) {
  return <String, Object?>{
    'seq': seq,
    'at': at,
    'text': text,
    'kind': 'chat',
    'seat': seat,
    'nickname': nickname,
  };
}

Map<String, Object?> _dice({
  required int seq,
  required num at,
  String expr = '1D100',
  Object? total = 42,
  String levelText = '困难成功',
  String seat = 'p1',
  String nickname = '玩家1',
  String label = '',
}) {
  return <String, Object?>{
    'seq': seq,
    'at': at,
    'seat': seat,
    'nickname': nickname,
    'expr': expr,
    'rolls': <Object?>[4, 2],
    'total': total,
    'levelText': levelText,
    'label': label,
  };
}

String _build(
  Map<String, Object?> state, {
  String seat = 'p1',
  String role = RoomRole.player,
  int? exportedAtMs = kFixedNowMs,
  int feedLimit = kRoomHistoryFeedLimit,
  int chatLimit = kRoomHistoryChatLimit,
  int maxLineChars = kRoomHistoryMaxLineChars,
}) {
  return buildRoomHistoryExportText(
    state,
    seat: seat,
    role: role,
    exportedAtMs: exportedAtMs,
    feedLimit: feedLimit,
    chatLimit: chatLimit,
    maxLineChars: maxLineChars,
  );
}

/// 只取编号记录行（两节的编号都从 1 开始，按出现顺序返回）。
List<String> _numbered(String text) => text
    .split('\n')
    .where((String l) => RegExp(r'^\d+\. ').hasMatch(l))
    .toList(growable: false);

/// 剥掉 // 行注释，避免回顾性说明把静态断言染红（门禁同款口径）。
String _codeOnly(String src) => src.split('\n').map((String line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    }).join('\n');

// ------------------------------------------------------------
// ① 纯函数 · 旧版格式 / 分节 / 顺序
// ------------------------------------------------------------

void main() {
  group('P2-06 · 纯函数：格式与旧版对齐', () {
    test('抬头逐项对应旧版：标题 / 分隔线 / 房号 / KP / 时间 / 成员 / 分节', () {
      // 判据为什么存在：旧版 exportArchiveText 的抬头是用户辨认「这是哪团」
      // 的唯一依据；少一列就分不清两份导出，多一列私有字段就违反 K3。
      final text = _build(_state(
        logs: <Object?>[_log(seq: 1, at: 1000, text: '开场')],
        chats: <Object?>[_chat(seq: 2, at: 2000, text: '你好')],
      ));
      final lines = text.split('\n');
      expect(lines[0], '跑团游戏历史记录');
      expect(lines[1], '================================');
      expect(lines[2], '房间：测试团（房间号 ABC123）');
      expect(lines[3], 'KP：老 K');
      expect(lines[4], '导出时间：${formatHistoryTime(kFixedNowMs)}');
      expect(lines[5], '成员：玩家1（调查员甲）、玩家2');
      expect(lines[6], '导出视角：玩家 · 座位 p1');
      expect(lines[7], contains('私密笔记'));
      expect(lines[8], '');
      expect(text.contains('游戏记录（共 1 条）'), isTrue);
      expect(text.contains('聊天记录（共 1 条）'), isTrue);
      // 两个分节各有一条分隔线（旧版记录节也用同一串）。
      expect('--------------------------------'.allMatches(text).length, 2);
      expect(text.contains('房间号 ABC123'), isTrue);
    });

    test('正文编号行格式：时间正序、从 1 递增、执行者用昵称 / KP 名 / 座位兜底', () {
      // 判据为什么存在：旧版是「编号 + [时间] + 执行者：内容」，乱序或丢
      // 执行者会让复盘读不出谁做了什么；顺序必须与既有 collectFeeds 一致。
      final text = _build(_state(logs: <Object?>[
        _log(seq: 3, at: 3000, text: '最晚'),
        _log(seq: 1, at: 1000, text: '最早', seat: kHostSeat),
        _log(seq: 2, at: 2000, text: '中间', seat: 'zz'),
      ]));
      final rows = _numbered(text);
      expect(rows.length, 3, reason: '没有聊天时只有 3 条游戏记录');
      expect(rows[0], contains('最早'));
      expect(rows[0], contains('老 K'), reason: 'host 座位要显示 KP 名');
      expect(rows[1], contains('中间'));
      expect(rows[1], contains('座位zz'), reason: '花名册查不到的座位按座位号兜底');
      expect(rows[2], contains('最晚'));
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].startsWith('${i + 1}. '), isTrue);
        expect(
          RegExp(r'^\d+\. \[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] .+：.+$')
              .hasMatch(rows[i]),
          isTrue,
          reason: '每行都必须是「编号. [时间] 执行者：内容」',
        );
      }
    });

    test('同 at 按 seq 定序，与 collectFeeds 的排序口径一致', () {
      // 判据为什么存在：同一毫秒里挤进多条事件时，若自己写一套排序，
      // 导出顺序就会和界面上看到的不一致。
      final text = _build(_state(logs: <Object?>[
        _log(seq: 9, at: 1000, text: 'SEQ_009'),
        _log(seq: 2, at: 1000, text: 'SEQ_002'),
      ]));
      final rows = _numbered(text);
      expect(rows.length, 2);
      expect(rows[0], contains('SEQ_002'));
      expect(rows[1], contains('SEQ_009'));
    });

    test('公开骰按 UI 同款文案进入游戏记录节，不落结构化字段', () {
      // 判据为什么存在：旧归档也留最近 20 条骰子；界面用 diceLine 渲染，
      // 导出必须同源，不能自己按 rolls 重算（会与权威结果不一致）。
      final text = _build(_state(dice: <Object?>[
        _dice(seq: 7, at: 1500),
      ]));
      expect(text.contains('游戏记录（共 1 条）'), isTrue);
      expect(text.contains('1D100 → 42 · 困难成功'), isTrue);
      expect(text.contains('rolls'), isFalse);
      expect(text.contains('levelText'), isFalse);
    });
  });

  // ----------------------------------------------------------
  // ② K3 脱敏
  // ----------------------------------------------------------
  group('P2-06 · K3 脱敏红线', () {
    test('秘密字段零泄漏：明文载荷 / 暗骰 / 私密笔记 / 私有素材 / 角色卡 / 其它座位', () {
      // 判据为什么存在：导出文本会被复制、分享、落到别的设备；任何一处
      // 把带明文载荷的序列化结果或私密栏拼进来，都是不可撤回的泄密。
      final state = _state(
        logs: <Object?>[
          _log(
            seq: 1,
            at: 1000,
            text: '公开记录正文',
            p: <String, Object?>{'detail': 'PLAINTEXT_P_SECRET'},
            wire: <String, Object?>{
              't': 'dice',
              'p': <String, Object?>{'x': 'WIRE_SECRET'},
            },
          ),
          _log(
            seq: 2,
            at: 1100,
            text: '（暗骰结果不公开）',
            kind: 'check',
            redacted: true,
            opp: <String, Object?>{'winner': 'DARK_ROLL_SECRET'},
            p: <String, Object?>{'detail': 'SECRET_DETAIL'},
          ),
        ],
        dice: <Object?>[_dice(seq: 3, at: 1200, label: '公开技能名')],
        chats: <Object?>[_chat(seq: 4, at: 1300, text: '公开聊天正文')],
        privates: <Object?>[
          <String, Object?>{
            'seq': 5,
            'title': '私密笔记',
            'text': 'PRIVATE_NOTE_SECRET DARK_ROLL_LABEL',
            'kind': 'note',
            'at': 1400,
          },
        ],
        members: <Object?>[
          <String, Object?>{
            'seat': 'p1',
            'nickname': '玩家1',
            'charName': '调查员甲',
            'role': RoomRole.player,
            'sheet': <String, Object?>{
              'status': <String, Object?>{'currentSAN': 'SHEET_SAN_SECRET'},
            },
            'privateBySeat': <String, Object?>{
              'p2': 'OTHER_SEAT_PRIVATE_SECRET',
            },
          },
        ],
        extra: <String, Object?>{
          'assets': <Object?>[
            <String, Object?>{'name': 'PRIVATE_ASSET_SECRET'},
          ],
          'notes': <String, Object?>{'text': 'LOCAL_NOTE_SECRET'},
        },
      );
      final text = _build(state);

      for (final secret in <String>[
        'PLAINTEXT_P_SECRET',
        'WIRE_SECRET',
        'DARK_ROLL_SECRET',
        'DARK_ROLL_LABEL',
        'SECRET_DETAIL',
        'PRIVATE_NOTE_SECRET',
        'PRIVATE_ASSET_SECRET',
        'LOCAL_NOTE_SECRET',
        'SHEET_SAN_SECRET',
        'OTHER_SEAT_PRIVATE_SECRET',
      ]) {
        expect(text.contains(secret), isFalse,
            reason: '★ 导出文本里绝不能出现 $secret');
      }
      // 正例也要在：不能靠「什么都不输出」骗过上面的断言。
      expect(text.contains('公开记录正文'), isTrue);
      // ★ P10 第 3 期 A 批：公开骰的 `label`（技能名）**本来就是公开字段**
      //   （老 APP `room-panels.js:1601` 直接渲染 `d.label`），本批把它并进
      //   `diceLine` 让玩家看得出「检定的是什么技能」。所以这里不再拿 label
      //   当秘密探针 —— 探针搬到 privates 正文（DARK_ROLL_LABEL 上面已搬），
      //   并在这里钉一条正例，防止有人反向「修」成不显示技能名。
      expect(text.contains('公开技能名'), isTrue,
          reason: '公开骰的技能名必须出现在导出正文里（老 APP 同口径）');
      expect(text.contains('公开聊天正文'), isTrue);
      expect(text.contains('玩家1（调查员甲）'), isTrue);
    });

    test('redacted 行只带公开 text，不还原结构化结果、不写暗骰元信息', () {
      // 判据为什么存在：feed_view.dart 已规定 redacted 行只取 text；
      // 导出若「好心」还原 opp / seat，等于绕过权威端裁剪。
      final text = _build(_state(logs: <Object?>[
        _log(
          seq: 1,
          at: 1000,
          text: '（某玩家进行了秘密检定）',
          kind: 'check',
          seat: 'p2',
          redacted: true,
          opp: <String, Object?>{'winner': 'SECRET_WINNER'},
          p: <String, Object?>{'detail': 'SECRET_DETAIL'},
        ),
      ]));
      expect(text.contains('（某玩家进行了秘密检定）'), isTrue);
      expect(text.contains('系统：（某玩家进行了秘密检定）'), isTrue,
          reason: '执行者统一写「系统」');
      expect(text.contains('SECRET_WINNER'), isFalse);
      expect(text.contains('SECRET_DETAIL'), isFalse);
      // 只查编号记录行：抬头「成员」里本来就有玩家2，扫全文会假红。
      expect(_numbered(text).single.contains('玩家2'), isFalse,
          reason: 'redacted 行不还原 seat');
      expect(text.contains('KP（暗骰）'), isFalse,
          reason: '连「这里发生过暗骰」的元信息都不写进导出文本');
      expect(text.contains('点击查看'), isFalse);
    });

    test('只输出公开列：不写 seq / 结构化骰子 / 原始 opp / 事件日志信封', () {
      // 判据为什么存在：导出是给人读的纯文本，不是状态快照；把内部键
      // 名带出去既难读，也会诱导后续实现往里塞更多字段。
      final text = _build(_state(
        logs: <Object?>[
          _log(
            seq: 1,
            at: 1000,
            text: '对抗成功',
            kind: 'check',
            opp: <String, Object?>{
              'winner': 'p1',
              'tie': false,
              'secret': 'OPP_SECRET',
            },
          ),
        ],
        dice: <Object?>[_dice(seq: 2, at: 1100)],
      ));
      for (final internal in <String>[
        'OPP_SECRET',
        '"seq"',
        'rolls',
        'levelText',
        "'p'",
        'toWireJson',
        'privates',
      ]) {
        expect(text.contains(internal), isFalse,
            reason: '导出文本不该出现内部键 $internal');
      }
      expect(text.contains('对抗成功 · p1 胜'), isTrue,
          reason: '走 UI 同款 checkLine，只拼公开胜负文案');
    });
  });

  // ----------------------------------------------------------
  // ③ 边界：空态 / null / 截断 / 上限 / 视角 / 时间
  // ----------------------------------------------------------
  group('P2-06 · 纯函数边界', () {
    test('空态：两个分节都写空态文案，抬头仍在', () {
      // 判据为什么存在：空房间导出不能是空白文件，否则用户会以为功能坏了。
      final text = _build(_state());
      expect(text.contains('游戏记录（共 0 条）'), isTrue);
      expect(text.contains(kRoomHistoryEmptyFeeds), isTrue);
      expect(text.contains('聊天记录（共 0 条）'), isTrue);
      expect(text.contains(kRoomHistoryEmptyChats), isTrue);
      expect(text.contains('房间号 ABC123'), isTrue);
      expect(text.trim().isEmpty, isFalse);
    });

    test('null 值不印字面量 null（抬头与正文都走空值安全取文本）', () {
      // 判据为什么存在：jsStr(null) 会印出字面量 null；房间状态里确实
      // 允许「键存在但值为 null」，导出一旦印出来就是脏文本。
      final raw = <String, Object?>{
        'meta': <String, Object?>{
          'code': null,
          'name': null,
          'kpName': null,
        },
        'members': <Object?>[
          <String, Object?>{
            'seat': null,
            'nickname': null,
            'charName': null,
          },
        ],
        'logs': <Object?>[
          <String, Object?>{
            'seq': 1,
            'at': 0,
            'text': null,
            'seat': null,
            'kind': 'chat',
          },
        ],
        'chats': <Object?>[
          <String, Object?>{
            'seq': 2,
            'at': 0,
            'text': null,
            'seat': null,
            'nickname': null,
          },
        ],
        'dice': <Object?>[],
        'privates': <Object?>[],
      };
      final text = _build(raw);
      expect(text.contains('null'), isFalse,
          reason: '★ 任何 null 都不得印成字面量 null');
      expect(text.contains('房间：房间 （房间号 ）'), isTrue);
      expect(text.contains('成员：?'), isTrue);
    });

    test('超长截断按码点收口，正文换行摊平不伪造记录行', () {
      // 判据为什么存在：一行一条编号记录的格式，正文自带换行会凭空多出
      // 几行；超长文本不收口会把整份导出撑爆。
      final long = '啊' * 40 + '\n' + '第二行';
      final text = _build(
        _state(logs: <Object?>[_log(seq: 1, at: 1000, text: long)]),
        maxLineChars: 12,
      );
      final rows = _numbered(text);
      expect(rows.length, 1);
      expect(rows.single.contains(kRoomHistoryClipSuffix), isTrue);
      expect(rows.single.contains('啊' * 12), isTrue);
      expect(rows.single.contains('啊' * 13), isFalse);
      expect(rows.single.contains('第二行'), isFalse);
      // 抬头 8 行 + 空行 + 记录节 3 行 + 空行 + 聊天节 3 行 = 16 行。
      expect(text.split('\n').length, 16,
          reason: '换行被摊平后不应多出一行');
    });

    test('maxLineChars <= 0 表示不截断（显式口径，不是隐式兜底）', () {
      // 判据为什么存在：截断口径必须可关掉，否则「完整文本」就无法验证。
      final long = '啊' * 200;
      final text = _build(
        _state(logs: <Object?>[_log(seq: 1, at: 1000, text: long)]),
        maxLineChars: 0,
      );
      expect(text.contains(long), isTrue);
      expect(text.contains(kRoomHistoryClipSuffix), isFalse);
    });

    test('feedLimit / chatLimit 与 U11 显示口径一致，且取最近 N 条', () {
      // 判据为什么存在：U11 定的是「聊天 60、记录 120，只裁显示」；
      // 导出是显示的副本，必须与界面看到的是同一批，不能悄悄导出全量。
      final logs = <Object?>[
        for (var i = 0; i < 130; i++)
          _log(
            seq: i + 1,
            at: 1000 + i,
            text: 'REC_${i.toString().padLeft(3, '0')}',
          ),
      ];
      final chats = <Object?>[
        for (var i = 0; i < 70; i++)
          _chat(
            seq: 200 + i,
            at: 5000 + i,
            text: 'CHAT_${i.toString().padLeft(3, '0')}',
          ),
      ];
      final state = _state(logs: logs, chats: chats);

      final defaultText = _build(state);
      expect(defaultText.contains('游戏记录（共 $kRoomHistoryFeedLimit 条）'),
          isTrue);
      expect(defaultText.contains('聊天记录（共 $kRoomHistoryChatLimit 条）'),
          isTrue);
      expect(defaultText.contains('REC_129'), isTrue);
      expect(defaultText.contains('REC_000'), isFalse);
      expect(defaultText.contains('CHAT_069'), isTrue);
      expect(defaultText.contains('CHAT_000'), isFalse);

      final small = _build(state, feedLimit: 5, chatLimit: 3);
      expect(small.contains('游戏记录（共 5 条）'), isTrue);
      expect(small.contains('聊天记录（共 3 条）'), isTrue);
      expect(small.contains('REC_129'), isTrue);
      expect(small.contains('REC_124'), isFalse);
      expect(small.contains('CHAT_069'), isTrue);
      expect(small.contains('CHAT_066'), isFalse);
    });

    test('视角只改抬头一行；同一 state 换 seat/role 正文完全一致', () {
      // 判据为什么存在：过滤发生在数据层（T8），视角参数若在纯函数里
      // 二次隐藏，跨视角用例就会假绿，且会变成第二套权限实现。
      final state = _state(
        logs: <Object?>[_log(seq: 1, at: 1000, text: '公开记录')],
        chats: <Object?>[_chat(seq: 2, at: 2000, text: '公开聊天')],
      );
      final asPlayer = _build(state, seat: 'p1', role: RoomRole.player);
      final asSpectator = _build(state, seat: 'sp1', role: RoomRole.spectator);
      expect(asPlayer.contains('导出视角：玩家 · 座位 p1'), isTrue);
      expect(asSpectator.contains('导出视角：旁观者 · 座位 sp1'), isTrue);
      String stripView(String t) => t
          .split('\n')
          .where((String l) => !l.startsWith('导出视角：'))
          .join('\n');
      expect(stripView(asPlayer), stripView(asSpectator));
    });

    test('formatHistoryTime：0 / 负数 / 非有限值返回空串，正数格式固定', () {
      // 判据为什么存在：旧版 `l.at ? archiveLogTime(l.at) : ''`，
      // 缺时间要留空而不是编一个 1970 年。
      expect(formatHistoryTime(0), '');
      expect(formatHistoryTime(-5), '');
      expect(formatHistoryTime(double.nan), '');
      expect(formatHistoryTime(double.infinity), '');
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')
            .hasMatch(formatHistoryTime(kFixedNowMs)),
        isTrue,
      );
    });
  });

  // ----------------------------------------------------------
  // ④ 静态口径
  // ----------------------------------------------------------
  group('P2-06 · 静态口径（防回退 / 防第二套实现）', () {
    test('纯函数源码：零 UI 框架 / 零 I/O / 零权威赋值 / 零平台动作 / 零私密字段', () {
      // ★ 按门禁同款口径剥掉 // 行注释：说明文字里回顾「零 Timer」这类
      //   历史约束不算命中，朴素 grep 会把自己写的注释扫成假红。
      final src = _codeOnly(
          File('lib/ui/room/room_history_export.dart').readAsStringSync());
      for (final banned in <String>[
        'package:flutter',
        'dart:io',
        'dart:ui',
        'Clipboard',
        'SharePlus',
        'Timer',
        'Future.delayed',
        'AnimationController',
        'sendIntent',
        'hostAction',
        'toWireJson',
        'collectPrivates',
        'privates',
        'jsStr(',
        'LogRecord',
        'showDialog',
      ]) {
        expect(src.contains(banned), isFalse,
            reason: '纯函数层不该出现 $banned');
      }
      expect(RegExp(r'state\[[^\]]*\]\s*=(?!=)').hasMatch(_codeOnly(src)),
          isFalse, reason: '纯函数层零权威状态赋值');
      expect(src.contains('collectFeeds'), isTrue);
      expect(src.contains('collectChats'), isTrue);
      expect(src.contains('checkLine'), isTrue);
      expect(src.contains('roomText'), isTrue);
      expect(src.contains('showRoomSheet'), isFalse);
    });

    test('导出弹层源码：零 Timer / 零延迟 / 零裸弹窗 / 零发包 / 零权威赋值', () {
      final src = _codeOnly(File('lib/ui/room/sheets/sheet_history_export.dart')
          .readAsStringSync());
      for (final banned in <String>[
        'Timer',
        'Future.delayed',
        'AnimationController',
        'showDialog',
        'sendIntent',
        'hostAction',
        'jsStr(',
        'toWireJson',
        'collectPrivates',
      ]) {
        expect(src.contains(banned), isFalse,
            reason: '导出弹层不该出现 $banned');
      }
      expect(RegExp(r'state\[[^\]]*\]\s*=(?!=)').hasMatch(_codeOnly(src)),
          isFalse, reason: '弹层零权威状态赋值');
      expect(src.contains('showRoomSheet'), isTrue);
      expect(src.contains('SelectableText'), isTrue,
          reason: 'K7 底线：完整文本可全选复制');
      expect(src.contains('widget.port.copy('), isTrue);
      expect(src.contains('widget.port.share('), isTrue);
      expect(src.contains('setState('), isTrue,
          reason: '可见反馈同步上屏，不依赖平台动作完成');
    });

    test('全 room/ 代码行不再有过期的用户可见占位表述', () {
      // 判据为什么存在：B 任务要求「用户可见字面量为零」；回顾性历史
      // 叙述放在 .txt 报告里可以，注释 / 代码里不许再出现。
      final files = Directory('lib/ui/room')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      for (final f in files) {
        final src = _codeOnly(f.readAsStringSync());
        for (final banned in <String>[
          '下一期',
          '后续版本提供',
          '当前没做',
          '未申请',
        ]) {
          expect(src.contains(banned), isFalse,
              reason: '${f.path} 代码里仍写着「$banned」= 过期表述');
        }
      }
    });
  });

  // ----------------------------------------------------------
  // ⑤ 接线（T1 内存后端）
  // ----------------------------------------------------------
  group('P2-06 · 接线（内存后端 / 零平台通道）', () {
    testWidgets('★ 入口可点 → 弹层出现 → 完整文本可见（SelectableText）',
        (WidgetTester tester) async {
      // 判据为什么存在：K7 不许造假入口 —— 光有按钮或「已导出」提示不算，
      // 必须真的把完整文本上屏且可全选复制。
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);
      final port = _CountingPort();

      await tester.pumpWidget(_scopedApp(
        f,
        kHostSeat,
        MiscSheet(
          historyExportPort: port,
          historyExportNowMs: () => kFixedNowMs,
        ),
      ));
      await _settle(tester);

      final entry =
          tester.widget<RoomTap>(find.byKey(MiscSheetKeys.historyExport));
      expect(entry.enabled, isTrue, reason: '恒 false 的禁用按钮 = 假入口');
      expect(entry.onTap, isNotNull, reason: '可点却没回调 = 点了没反应');
      expect(entry.hint, contains('完整文本'));

      await tester.ensureVisible(find.byKey(MiscSheetKeys.historyExport));
      await tester.pump();
      await tester.tap(find.byKey(MiscSheetKeys.historyExport));
      await _settle(tester);

      expect(find.byKey(RoomHistoryExportKeys.root), findsOneWidget,
          reason: '★ 点开必须有实际内容');
      final expected = buildRoomHistoryExportText(
        f.sessionOf(kHostSeat).state,
        seat: f.sessionOf(kHostSeat).seat,
        role: f.sessionOf(kHostSeat).role,
        exportedAtMs: kFixedNowMs,
      );
      final selectable = tester
          .widget<SelectableText>(find.byKey(RoomHistoryExportKeys.text));
      expect(selectable.data, expected,
          reason: '★★ 上屏的必须是纯函数生成的完整文本，不是摘要或占位');
      expect(selectable.data!.contains('跑团游戏历史记录'), isTrue);
      expect(selectable.data!.contains('游戏记录（共'), isTrue);
      expect(selectable.data!.contains('聊天记录（共'), isTrue);
      expect(find.byKey(RoomHistoryExportKeys.copy), findsOneWidget);
      expect(find.byKey(RoomHistoryExportKeys.share), findsOneWidget);
      expect(find.byKey(RoomHistoryExportKeys.denied), findsNothing);
    });

    testWidgets('★ 复制 / 系统分享两个真动作：同步替身计数 + 反馈先于平台动作',
        (WidgetTester tester) async {
      // 判据为什么存在：两个按钮必须真的把「同一份完整文本」交给平台；
      // 且可见反馈不能等平台通道返回（自动化环境里它不返回）。
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);
      final port = _CountingPort();

      await tester.pumpWidget(_scopedApp(
        f,
        kHostSeat,
        MiscSheet(
          historyExportPort: port,
          historyExportNowMs: () => kFixedNowMs,
        ),
      ));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(MiscSheetKeys.historyExport));
      await tester.pump();
      await tester.tap(find.byKey(MiscSheetKeys.historyExport));
      await _settle(tester);

      final expected = buildRoomHistoryExportText(
        f.sessionOf(kHostSeat).state,
        seat: f.sessionOf(kHostSeat).seat,
        role: f.sessionOf(kHostSeat).role,
        exportedAtMs: kFixedNowMs,
      );

      await tester.ensureVisible(find.byKey(RoomHistoryExportKeys.copy));
      await tester.pump();
      await tester.tap(find.byKey(RoomHistoryExportKeys.copy));
      await tester.pump(); // 只同步 pump，不 await 任何平台动作
      expect(port.copies, 1, reason: '★ 复制回调被真实调用');
      expect(port.copiedText.single, expected,
          reason: '★ 送进剪贴板的是完整文本');
      var feedback = tester
          .widget<Text>(find.byKey(RoomHistoryExportKeys.feedback))
          .data ??
          '';
      expect(feedback, contains('复制已触发'));
      expect(feedback, contains('全选复制'),
          reason: 'K7 底线：平台动作不返回也仍有完整文本可复制');

      await tester.ensureVisible(find.byKey(RoomHistoryExportKeys.share));
      await tester.pump();
      await tester.tap(find.byKey(RoomHistoryExportKeys.share));
      await tester.pump();
      expect(port.shares, 1, reason: '★ 系统分享回调被真实调用');
      expect(port.sharedText.single, expected,
          reason: '★ 送进系统分享的是完整文本');
      feedback = tester
          .widget<Text>(find.byKey(RoomHistoryExportKeys.feedback))
          .data ??
          '';
      expect(feedback, contains('系统分享已触发'));
      expect(feedback, contains('全选复制'));
    });

    testWidgets('★★ 空 port 也不丢文本、不说假话（K7 底线常在）',
        (WidgetTester tester) async {
      // 判据为什么存在：把平台动作换成什么都不做的替身，等价于「平台通道
      // 在测试环境不返回」。此时文本仍要完整可见、反馈仍要如实，不能变空白。
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);

      await tester.pumpWidget(_scopedApp(
        f,
        kHostSeat,
        MiscSheet(
          historyExportPort: const _SilentPort(),
          historyExportNowMs: () => kFixedNowMs,
        ),
      ));
      await _settle(tester);
      await tester.ensureVisible(find.byKey(MiscSheetKeys.historyExport));
      await tester.pump();
      await tester.tap(find.byKey(MiscSheetKeys.historyExport));
      await _settle(tester);

      final expected = buildRoomHistoryExportText(
        f.sessionOf(kHostSeat).state,
        seat: f.sessionOf(kHostSeat).seat,
        role: f.sessionOf(kHostSeat).role,
        exportedAtMs: kFixedNowMs,
      );
      expect(
        tester
            .widget<SelectableText>(find.byKey(RoomHistoryExportKeys.text))
            .data,
        expected,
        reason: '★ 空 port 时完整文本仍在屏上',
      );
      await tester.ensureVisible(find.byKey(RoomHistoryExportKeys.copy));
      await tester.pump();
      await tester.tap(find.byKey(RoomHistoryExportKeys.copy));
      await tester.pump();
      expect(
        tester
            .widget<SelectableText>(find.byKey(RoomHistoryExportKeys.text))
            .data,
        expected,
        reason: '★ 点完复制文本也没被清空 / 换成摘要',
      );
      final feedback = tester
          .widget<Text>(find.byKey(RoomHistoryExportKeys.feedback))
          .data ??
          '';
      expect(feedback, contains('复制已触发'));
      expect(feedback, isNot(contains('已导出成功')));
      expect(feedback, isNot(contains('文件已保存')));
    });

    testWidgets('★★ 零发包 / 零网络 / 零 state / 零 notice（四项真值前后对比）',
        (WidgetTester tester) async {
      // 判据为什么存在：只读导出不能顺手改房间；只看文案会漏掉「点了没
      // 反应」的反面，必须用权威侧真值钉死。
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);
      final port = _CountingPort();

      await tester.pumpWidget(_scopedApp(
        f,
        kHostSeat,
        MiscSheet(
          historyExportPort: port,
          historyExportNowMs: () => kFixedNowMs,
        ),
      ));
      await _settle(tester);

      final sentBefore = f.sent.length;
      final seqBefore = f.sessionOf(kHostSeat).lastSeq;
      final stateBefore = jsonEncode(f.stateOf(kHostSeat));
      final noticeBefore = f.localOf(kHostSeat).notice;

      await tester.ensureVisible(find.byKey(MiscSheetKeys.historyExport));
      await tester.pump();
      await tester.tap(find.byKey(MiscSheetKeys.historyExport));
      await _settle(tester);
      expect(find.byKey(RoomHistoryExportKeys.root), findsOneWidget,
          reason: '前置：这一步确实把弹层打开了');
      await tester.ensureVisible(find.byKey(RoomHistoryExportKeys.copy));
      await tester.pump();
      await tester.tap(find.byKey(RoomHistoryExportKeys.copy));
      await tester.pump();
      await tester.ensureVisible(find.byKey(RoomHistoryExportKeys.share));
      await tester.pump();
      await tester.tap(find.byKey(RoomHistoryExportKeys.share));
      await tester.pump();

      expect(port.copies + port.shares, 2, reason: '前置：两个动作确实执行了');
      expect(f.sent.length, sentBefore,
          reason: '★★ 导出绝不发 intent / action');
      expect(f.sessionOf(kHostSeat).lastSeq, seqBefore,
          reason: '★ 权威端序号没动 = 没有任何事件产生');
      expect(jsonEncode(f.stateOf(kHostSeat)), stateBefore,
          reason: '★★ 房间状态必须一字未改');
      expect(f.localOf(kHostSeat).notice, noticeBefore,
          reason: '★ 反馈走弹层内同步文本，不写 local.notice、不放假成功提示');
    });

    testWidgets('旁观者权限不足 → 结构上不渲染入口，且零发包',
        (WidgetTester tester) async {
      // 判据为什么存在：派工要求「权限不足不渲染入口」而不是置灰；
      // 旁观者能否看历史拿不准，取 POLICY 的保守口径，报告里请 QA 判。
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);
      final sentBefore = f.sent.length;

      await tester.pumpWidget(_scopedApp(f, 'sp1', const MiscSheet()));
      await _settle(tester);

      expect(find.byKey(MiscSheetKeys.historyExport), findsNothing,
          reason: '★ gate.can(chat) 对 spectator 为 false → 不渲染');
      expect(f.controllerOf('sp1').gate.can(kRoomHistoryExportPolicyOp),
          isFalse);
      expect(f.sent.length, sentBefore, reason: '旁观者零发包');
    });

    testWidgets('玩家视角入口存在（POLICY chat = [kp, player]）',
        (WidgetTester tester) async {
      // 判据为什么存在：导出不能只有 KP 能用；玩家是公开信息流的参与者。
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);

      await tester.pumpWidget(_scopedApp(f, 'p1', const MiscSheet()));
      await _settle(tester);
      expect(find.byKey(MiscSheetKeys.historyExport), findsOneWidget);
      expect(f.controllerOf('p1').gate.can(kRoomHistoryExportPolicyOp), isTrue);
    });

    testWidgets('生产路径：玩家工具栏有「更多工具」可达杂项弹层',
        (WidgetTester tester) async {
      // 判据为什么存在：杂项弹层此前只能从 KP 面板打开，玩家没有可达
      // 路径；P2-06 的真入口装在杂项里，必须补一条生产路径才不是孤儿入口。
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      useRoomScreen(tester, 900, 2400);
      f.pageBuilder = (String seat, String role) =>
          RoomGamePage(seat: seat, role: role);

      await tester.pumpWidget(f.playerPage('p1'));
      await tester.pump();
      expect(find.byKey(RoomGamePage.miscToolsKey), findsOneWidget,
          reason: '★ 玩家工具栏要能进「更多工具」');
      expect(find.byKey(RoomGamePage.kpPanelKey), findsNothing,
          reason: '玩家不该有 KP 工具入口');

      await tester.pumpWidget(f.kpPage());
      await tester.pump();
      expect(find.byKey(RoomGamePage.kpPanelKey), findsOneWidget);
      expect(find.byKey(RoomGamePage.miscToolsKey), findsNothing,
          reason: 'KP 走 KP 面板，不重复摆一个「更多工具」');

      await tester.pumpWidget(f.spectatorPage('sp1'));
      await tester.pump();
      expect(find.byKey(RoomGamePage.miscToolsKey), findsNothing,
          reason: '旁观者权限不足，结构上不渲染');
    });
  });
}

// ------------------------------------------------------------
// 替身 / 宿主
// ------------------------------------------------------------

/// 同步计数替身：零 Future、零 Timer、零平台通道。
class _CountingPort implements RoomHistoryExportPort {
  int copies = 0;
  int shares = 0;
  final List<String> copiedText = <String>[];
  final List<String> sharedText = <String>[];

  @override
  void copy(String text) {
    copies += 1;
    copiedText.add(text);
  }

  @override
  void share(String text) {
    shares += 1;
    sharedText.add(text);
  }
}

/// 空 port：平台动作什么都不做，用来验证「不依赖副作用完成」。
class _SilentPort implements RoomHistoryExportPort {
  const _SilentPort();

  @override
  void copy(String text) {}

  @override
  void share(String text) {}
}

/// 宿主：RoomScope 挂在 Navigator 外层，弹层里才找得到作用域。
Widget _scopedApp(RoomUiFixture f, String seat, Widget body) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (BuildContext _, Widget? child) =>
          f.scoped(seat, child: child ?? const SizedBox.shrink()),
      home: Scaffold(body: SingleChildScrollView(child: body)),
    );

/// 用 pump(Duration) 推进底部弹层转场（不是真实 Timer，不会挂 fake-async）。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}
