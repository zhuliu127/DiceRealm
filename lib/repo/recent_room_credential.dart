// ============================================================
// repo/recent_room_credential.dart — 最近一次联网房间的凭据（P16 P-1(b)）
//
// ★ 安全口径（本批最高风险项，优先级高于一切）：
//   1. 只存 roomCode / base / hostToken / deviceId / role / seat / savedAt，
//      落**独立的本地私有文件**，与 room_saves（存档快照）目录严格分开；
//   2. **绝不写进现有存档**（存档会被 room_history_export.dart 导出 / 云分享，
//      凭据会随之泄露）—— 本文件不 import 任何 domain 存档打包函数，
//      `save()` / `packSave` / `openSave` / `adoptSave` 也绝不引用本文件；
//   3. hostToken **不落日志**（参照 cloud_room.dart:292 的先例）：本文件
//      全程不 print、不写任何日志；
//   4. roomCode 作查询键前过白名单，防路径穿越（见 [_safeKey]）。
//
// ⚠️ 目录通过 [recentCredentialStore] 注入：波2 在 main() 里把它指向应用
//   私有目录（例如 `docs/.room_credentials`，与 `docs/room_saves` 分开），
//   并需在该私有目录被工程内访问时给 .gitignore 加一条
//   `**/.room_credentials/`（.gitignore 不在本组独占集，交波2 加）。
//   未注入时退化为**进程内内存实现**：单进程内可用、flutter test 下零 I/O
//   不挂、绝不误写盘。凭据是「锦上添花」的辅助能力，任何读写失败都静默，
//   绝不拖垮建房 / 加入 / 续玩主流程。
//
// ★ 契约（§3）：导出 [saveRecentCredential] / [loadRecentCredential] /
//   [clearRecentCredential]；不得被存档打包路径引用。
// ============================================================

import 'dart:convert';
import 'dart:io';

/// 一条最近房间的联网凭据。
class RecentRoomCredential {
  const RecentRoomCredential({
    required this.roomCode,
    this.base = '',
    this.hostToken = '',
    this.deviceId = '',
    this.role = '',
    this.seat = '',
    this.savedAt = 0,
    // ★ P20：最后一次成功建连的模式 / 时刻（向后兼容默认值）。
    this.mode = '',
    this.lastOkAt = 0,
  });

  final String roomCode;
  final String base;
  final String hostToken;
  final String deviceId;
  final String role;
  final String seat;
  final int savedAt;

  /// ★ P20：最后一次**成功**开房 / 加入 / 续玩的模式：`lan` \| `cloud` \| `''`。
  /// 旧 JSON 缺该键时回落 `''`（未知），见 [fromJson]。
  final String mode;

  /// ★ P20：最后一次成功建连的 epoch ms；`0` = 从未成功记录。
  final int lastOkAt;

  /// 是否含一个可用的服务地址（续玩联网重连的最低门槛）。
  bool get hasBase => base.trim().isNotEmpty;

  /// ★ P20：由服务地址推断联网模式（弹窗默认选中的第二优先级）。
  ///
  /// 判定口径与 `net/cloud_room.dart#isCloudBase`（:225–247）**逐字一致**：
  /// 这里内联一份等价纯函数，刻意**不 import net 层** —— 保持 repo 层纯度、
  /// 避免 `cloud_room.dart`(net) ↔ `cloud_device_id.dart`(repo) 的跨层反向依赖，
  /// 也让本文件如设计 M4 所述「只改自身、不新增 import」。
  String inferredMode() => _inferCloudBase(base) ? 'cloud' : 'lan';

  /// ★ P20：7 天内记住「上次成功模式」；超时 / 无记录 / 时钟倒退返回 `''`。
  String lastOkMode(int nowMs) {
    if (mode != 'lan' && mode != 'cloud') return '';
    if (lastOkAt <= 0) return '';
    final int delta = nowMs - lastOkAt;
    if (delta < 0 || delta > _kModeMemoryMs) return '';
    return mode;
  }

  /// 「上次成功模式」的记忆窗口：7 天。
  static const int _kModeMemoryMs = 7 * 24 * 60 * 60 * 1000;

  Map<String, Object?> toJson() => <String, Object?>{
        'roomCode': roomCode,
        'base': base,
        'hostToken': hostToken,
        'deviceId': deviceId,
        'role': role,
        'seat': seat,
        'savedAt': savedAt,
        'mode': mode,
        'lastOkAt': lastOkAt,
      };

  static RecentRoomCredential? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = _s(raw['roomCode']);
    if (code.isEmpty) return null;
    return RecentRoomCredential(
      roomCode: code,
      base: _s(raw['base']),
      hostToken: _s(raw['hostToken']),
      deviceId: _s(raw['deviceId']),
      role: _s(raw['role']),
      seat: _s(raw['seat']),
      savedAt: _i(raw['savedAt']),
      // ★ P20：旧 JSON（7 字段）缺这两键时由 _s / _i 回落 '' / 0，无损读取。
      mode: _s(raw['mode']),
      lastOkAt: _i(raw['lastOkAt']),
    );
  }
}

String _s(Object? v) => v is String ? v : '';
int _i(Object? v) => v is num ? v.toInt() : 0;

/// 与 `net/cloud_room.dart#isCloudBase` 判定口径逐字一致的纯函数。
///
/// 公网域名 / 公网 IP 才算中继；本机 / 回环 / RFC1918 私网 / 链路本地
/// 一律算局域网。抽在这里供 [RecentRoomCredential.inferredMode] 复用，
/// 避免 repo 层反向 import net 层。
bool _inferCloudBase(String raw) {
  final String s = raw.trim().toLowerCase();
  if (!s.startsWith('http://') && !s.startsWith('https://')) return false;
  final String h = (Uri.tryParse(s)?.host ?? '').toLowerCase();
  if (h.isEmpty) return false;
  if (h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]') {
    return false;
  }
  if (h.startsWith('10.') ||
      h.startsWith('192.168.') ||
      h.startsWith('169.254.')) {
    return false;
  }
  final RegExpMatch? m = RegExp(r'^172\.(\d+)\.').firstMatch(h);
  if (m != null) {
    final int? n = int.tryParse(m.group(1) ?? '');
    if (n != null && n >= 16 && n <= 31) return false;
  }
  return true;
}

String _codeOf(Object? e) =>
    e is Map && e['roomCode'] is String ? e['roomCode'] as String : '';

/// 查询键白名单：字母数字下划线短横线，1–64 位（房间号是 6 位大写字母数字）。
/// 不含 `/` `\` `.` `:` —— 即便将来拿它拼文件名也逃不出私有目录。
bool _safeKey(String key) {
  if (key.isEmpty || key.length > 64) return false;
  return RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(key);
}

/// 凭据存储端口（可注入，便于测试与替换落盘目录）。
abstract class RecentCredentialStorage {
  Map<String, Object?> readAll();

  void writeAll(Map<String, Object?> data);

  void clear();
}

/// 默认兜底：进程内内存。零 I/O，flutter test 下不会挂，也绝不误写盘。
class MemoryRecentCredentialStorage implements RecentCredentialStorage {
  Map<String, Object?> _data = <String, Object?>{};

  @override
  Map<String, Object?> readAll() => <String, Object?>{..._data};

  @override
  void writeAll(Map<String, Object?> data) {
    _data = <String, Object?>{...data};
  }

  @override
  void clear() {
    _data = <String, Object?>{};
  }
}

/// 独立私有文件实现：单文件 `recent_rooms.json`，原子写（.tmp → copy）。
///
/// [dir] 必须由调用方给应用私有目录；构造期绝不自作主张去找全局目录，
/// 也不在构造期做任何 I/O。与存档快照目录分开是铁律。
class FileRecentCredentialStorage implements RecentCredentialStorage {
  FileRecentCredentialStorage(this.dir);

  final Directory dir;

  File get _file =>
      File('${dir.path}${Platform.pathSeparator}recent_rooms.json');

  @override
  Map<String, Object?> readAll() {
    try {
      final f = _file;
      if (!f.existsSync()) return <String, Object?>{};
      final raw = jsonDecode(f.readAsStringSync());
      return raw is Map ? raw.cast<String, Object?>() : <String, Object?>{};
    } catch (_) {
      // 坏文件不拖垮主流程：当作「没有凭据」。
      return <String, Object?>{};
    }
  }

  @override
  void writeAll(Map<String, Object?> data) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = _file;
      final tmp = File('${f.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(data), flush: true);
      tmp.copySync(f.path);
      try {
        tmp.deleteSync();
      } catch (_) {
        // tmp 删不掉不影响正确性，下次 write 会覆盖它。
      }
    } catch (_) {
      // 写盘失败静默：凭据是辅助能力，绝不拖垮主流程。
    }
  }

  @override
  void clear() {
    try {
      final f = _file;
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

/// 全局可替换的存储后端。波2 在 main() 注入 [FileRecentCredentialStorage]。
RecentCredentialStorage recentCredentialStore =
    MemoryRecentCredentialStorage();

/// 最多保留的房间数（避免无限增长）。
const int _kMaxRooms = 8;

/// 保存 / 覆盖某房间的最近联网凭据（同步、失败静默、绝不写日志）。
void saveRecentCredential({
  required String roomCode,
  String base = '',
  String hostToken = '',
  String deviceId = '',
  String role = '',
  String seat = '',
  int? savedAt,
  // ★ P20：写入点可记录成功模式 / 时刻；不传保持 '' / 0（旧调用零回归）。
  String mode = '',
  int lastOkAt = 0,
}) {
  final code = roomCode.trim();
  if (!_safeKey(code)) return;
  try {
    final all = recentCredentialStore.readAll();
    final rawRooms = all['rooms'];
    final list = <Object?>[
      if (rawRooms is List)
        for (final e in rawRooms)
          if (_codeOf(e) != code) e,
    ];
    list.add(RecentRoomCredential(
      roomCode: code,
      base: base,
      hostToken: hostToken,
      deviceId: deviceId,
      role: role,
      seat: seat,
      savedAt: savedAt ?? DateTime.now().millisecondsSinceEpoch,
      mode: mode,
      lastOkAt: lastOkAt,
    ).toJson());
    final trimmed = list.length > _kMaxRooms
        ? list.sublist(list.length - _kMaxRooms)
        : list;
    recentCredentialStore.writeAll(<String, Object?>{'rooms': trimmed});
  } catch (_) {
    // 静默：绝不因凭据存储失败影响建房 / 加入。
  }
}

/// 读取某房间的最近联网凭据；没有 / 损坏 / 非法键返回 null。
/// **同步**：flutter test 的 fake-async 下不会挂。
RecentRoomCredential? loadRecentCredential(String roomCode) {
  final code = roomCode.trim();
  if (!_safeKey(code)) return null;
  try {
    final all = recentCredentialStore.readAll();
    final rooms = all['rooms'];
    if (rooms is! List) return null;
    for (final e in rooms.reversed) {
      if (_codeOf(e) == code) return RecentRoomCredential.fromJson(e);
    }
  } catch (_) {}
  return null;
}

/// ★ P20：按「原样 → 全小写 → 全大写」依次尝试读取凭据，命中即返回。
///
/// 为什么需要：云端房号是小写（`CODE_ALPHA` 小写 + 服务端正则 `[a-z0-9]`），
/// 局域网房号是大写（`normalizeRoomCode` 转大写），而存档 `meta.code` 可能
/// 是历史混合大小写。凭据键按各自模式规范化写入，读取时三形态兜底，
/// 兼容历史混合大小写凭据。**不改变** [loadRecentCredential] 原语义
/// （`p16_wave1_domain_test.dart:285–308` 保护）。
RecentRoomCredential? loadRecentCredentialFlexible(String code) {
  final String trimmed = code.trim();
  if (trimmed.isEmpty) return null;
  final List<String> candidates = <String>[
    trimmed,
    trimmed.toLowerCase(),
    trimmed.toUpperCase(),
  ];
  final Set<String> seen = <String>{};
  for (final String candidate in candidates) {
    if (!seen.add(candidate)) continue;
    final RecentRoomCredential? hit = loadRecentCredential(candidate);
    if (hit != null) return hit;
  }
  return null;
}

/// 清除凭据：[roomCode] 为空则清空全部，否则只删该房间的一条。
void clearRecentCredential([String roomCode = '']) {
  final code = roomCode.trim();
  try {
    if (code.isEmpty) {
      recentCredentialStore.clear();
      return;
    }
    final all = recentCredentialStore.readAll();
    final rooms = all['rooms'];
    if (rooms is! List) return;
    final kept = <Object?>[
      for (final e in rooms)
        if (_codeOf(e) != code) e,
    ];
    recentCredentialStore.writeAll(<String, Object?>{'rooms': kept});
  } catch (_) {}
}
