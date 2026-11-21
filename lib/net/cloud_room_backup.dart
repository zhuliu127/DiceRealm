// ============================================================
// net/cloud_room_backup.dart — P20 公网全量存档 + 房间保活（N2）
//
// ★ 职责（设计 §3/§4.5/§5.4）：
//   · 两个 hostToken-only 端点：POST /backup（写）、POST /backup/read（读）；
//   · 复用既有 POST /resume / POST /suspend（服务端零改动）；
//   · KP 全量档**一律走 /backup**，绝不写 /state —— 线上 `/api_get_state`
//     的 deviceId 绑定通道会把不透明 payload 返给任意已绑定设备，而
//     host.save() 含 privateBySeat（隐私红线 Q3）；
//   · 玩家侧**不上传、不下载**云端全量档，同步仍走 WS + save.share 广播。
//
// ★ 保活顺序（主理人 D-5 硬约束）：末次 `POST /backup` 成功（或明确失败）
//   **之后**才 `POST /suspend`，顺序绝不可反。只在「KP 离开房间但未关房
//   (_exit.kind == none)」或 App `detached` 时触发；关房/结团一律不触发。
//   `finalizeOnLeave()` 只读全局纯数据上下文，绝不引用 context/BuildContext/
//   _syncer/widget.controller（dispose 后树已销毁），全链路 try/catch。
//
// ★ 可注入：`cloudHttp`（既有全局）、`cloudBackupSink`（默认 null，
//   flutter test 零网络）、`cloudBackupClock`、`activeCloudBackupContext`。
// ============================================================

import 'dart:async' show unawaited;
import 'dart:convert' show jsonEncode;

import '../domain/js_compat.dart' show jsNum, jsStr;
import 'cloud_room.dart'
    show
        CloudHttpResponse,
        CloudHttpTransport,
        cloudApiUri,
        cloudHttp,
        cloudRoomCode;

// ------------------------------------------------------------
// 结果类型
// ------------------------------------------------------------

/// `POST /resume` 的结果。
///
/// [seq] / [payload] 来自 /resume 回包中的 room_state（老客户端用），
/// **新客户端忽略** —— 全量档一律走 `POST /backup/read`。
class CloudRoomResumeResult {
  const CloudRoomResumeResult({
    required this.ok,
    this.code = '',
    this.base = '',
    this.role = '',
    this.seat = '',
    this.seq = 0,
    this.payload = '',
    this.errorKey = '',
    this.errorText = '',
  });

  final bool ok;
  final String code;
  final String base;
  final String role;
  final String seat;
  final int seq;
  final String payload;
  final String errorKey;
  final String errorText;
}

/// `POST /backup`（写）的结果。`stale` 是正常结果，不是错误。
class BackupWriteResult {
  const BackupWriteResult({
    required this.ok,
    this.seq = 0,
    this.stale = false,
    this.errorKey = '',
    this.errorText = '',
  });

  final bool ok;
  final int seq;
  final bool stale;
  final String errorKey;
  final String errorText;
}

/// `POST /backup/read`（读）的结果。
class BackupFetchResult {
  const BackupFetchResult({
    required this.ok,
    this.seq = 0,
    this.payload = '',
    this.savedAt = 0,
    this.errorKey = '',
    this.errorText = '',
  });

  final bool ok;
  final int seq;
  final String payload;
  final int savedAt;
  final String errorKey;
  final String errorText;
}

/// ★ P20 Q4 保活的**纯数据上下文**（不含任何 BuildContext / Session /
/// Controller / ChangeNotifier 引用，dispose 之后依然安全）。
///
/// 由云端 KP 开房 / 续玩成功后 [armCloudBackup] 写入；关房 / 结团 / 完成
/// 保活后 [clearActiveCloudBackup] 清空。[payload] 缓存最近一份 20 键 JSON
/// 字符串，供末次上传使用（dispose 时已无法再取 host.save()）。
class CloudBackupContext {
  const CloudBackupContext({
    required this.base,
    required this.code,
    required this.hostToken,
    this.deviceId = '',
    this.seq = 0,
    this.payload = '',
  });

  /// HTTP base（如 `https://host/room`），**不是** wss:// 全 URL。
  final String base;

  /// 已经 `cloudRoomCode()` 小写规范化、与服务端正则 `[a-z0-9]{4,12}` 一致。
  final String code;

  final String hostToken;
  final String deviceId;

  /// 最近一份存档的 `save()['seq']`（RoomHost.log.seq，跨重启单调）。
  final int seq;

  /// 最近一份 20 键存档的 JSON 字符串（不透明，服务端不解析）。
  final String payload;

  bool get isValid =>
      base.trim().isNotEmpty && code.trim().isNotEmpty && hostToken.isNotEmpty;

  CloudBackupContext copyWith({
    String? base,
    String? code,
    String? hostToken,
    String? deviceId,
    int? seq,
    String? payload,
  }) =>
      CloudBackupContext(
        base: base ?? this.base,
        code: code ?? this.code,
        hostToken: hostToken ?? this.hostToken,
        deviceId: deviceId ?? this.deviceId,
        seq: seq ?? this.seq,
        payload: payload ?? this.payload,
      );
}

/// 当前活跃的云端 KP 房间上下文（进程内纯数据）。测试可直接注入 / 清空。
CloudBackupContext? activeCloudBackupContext;

/// 挂载（云端 KP 建连成功时）。
void armCloudBackup(CloudBackupContext ctx) {
  activeCloudBackupContext = ctx;
}

/// 清空（关房 / 结团 / 保活完成 / 非云端会话）。
/// ★ D-2：这里只清**运行时上下文**，**绝不清** `RecentRoomCredential`
/// 持久化凭据 —— 凭据保留才能让 `/resume` 的 `not_found` 触发 F3 诚实提示。
void clearActiveCloudBackup() {
  activeCloudBackupContext = null;
}

// ------------------------------------------------------------
// 错误码 → F1–F7 中文口径（设计 §8.4）
// ------------------------------------------------------------

/// 服务端 error / 客户端信号 → 给用户看的一句人话。
///
/// 红线（R-09）：任何失败分支都不得出现「已连回 / 已同步 / 云端第 N 版」。
String resumeErrorText(String errorKey, String code) {
  final String c = code.trim();
  switch (errorKey) {
    case 'not_found': // F3：房间已 CLOSED 或已被回收
      return '房间已过期或已结束，无法连回原房号$c';
    case 'bad_token': // F2：房主令牌已失效
      return '房主令牌已失效，没能连回房间 $c';
    case 'room_suspended': // F4：玩家侧，KP 未先续玩
      return '房间已挂起，需 KP 先续玩';
    case 'too_large': // F6：备份超限
    case 'parse_failed':
      return '本次进度未备份到云端，本机存档仍可用';
    case 'lan_not_found': // F5
      return '没找到 KP 的局域网房间，需 KP 先在同一 WiFi 打开原房号';
    case 'new_identity': // F7
      return '无法确认原座位，是否以新身份加入（可能占新座位）？';
    case 'timeout':
    case 'network':
    case 'ws_closed':
      return '没能连回房间 $c：服务器连不上';
    case 'no_backup':
      // 云端还没有备份（首次开房）不是失败，但也不能说「已同步」。
      return '云端暂无备份进度，已按本机存档继续';
    default:
      return errorKey.isEmpty ? '没能连回房间 $c' : '没能连回房间 $c（$errorKey）';
  }
}

/// 把 HTTP 响应映射成 errorKey（供 [resumeErrorText]）。
String errorKeyOfResponse(CloudHttpResponse res) {
  final String code = res.errorCode;
  if (code.isNotEmpty) return code;
  if (!res.ok && res.error.isNotEmpty) return 'network';
  return '';
}

// ------------------------------------------------------------
// 云端备份服务（4 端点）
// ------------------------------------------------------------

class CloudBackupService {
  CloudBackupService({CloudHttpTransport? http}) : http = http ?? cloudHttp;

  /// 可注入的 HTTP 端口（默认全局 cloudHttp，测试换内存实现）。
  final CloudHttpTransport http;

  /// `POST /api/rooms/<code>/resume`（hostToken）：SUSPENDED/RECRUITING/
  /// IN_GAME → RECRUITING。服务端零改动；不补 wsBase，客户端用 cred.base。
  Future<CloudRoomResumeResult> resumeRoom(
    String base,
    String code,
    String hostToken,
  ) async {
    final String normalized = cloudRoomCode(code);
    try {
      final CloudHttpResponse res = await http.postJson(
        cloudApiUri(base.trim(), '/api/rooms/$normalized/resume'),
        <String, Object?>{'hostToken': hostToken},
      );
      if (!res.ok) {
        final String key = errorKeyOfResponse(res);
        return CloudRoomResumeResult(
          ok: false,
          code: normalized,
          base: base,
          errorKey: key.isEmpty ? 'network' : key,
          errorText: resumeErrorText(key.isEmpty ? 'network' : key, code),
        );
      }
      return CloudRoomResumeResult(
        ok: true,
        code: normalized,
        base: base,
        role: 'kp',
        seat: 'host',
        // 回包里的 room_state 是老客户端用的，新客户端忽略（走 /backup/read）。
        seq: jsNum(res.json['seq']),
        payload: jsStr(res.json['payload'] ?? ''),
      );
    } catch (_) {
      return CloudRoomResumeResult(
        ok: false,
        code: normalized,
        base: base,
        errorKey: 'network',
        errorText: resumeErrorText('network', code),
      );
    }
  }

  /// `POST /api/rooms/<code>/backup`（hostToken, seq, payload）。
  /// `stale:true` 是正常结果 —— 不弹错、不重试风暴（K2）。
  Future<BackupWriteResult> upload(
    String base,
    String code,
    String hostToken,
    int seq,
    String payload,
  ) async {
    final String normalized = cloudRoomCode(code);
    try {
      final CloudHttpResponse res = await http.postJson(
        cloudApiUri(base.trim(), '/api/rooms/$normalized/backup'),
        <String, Object?>{
          'hostToken': hostToken,
          'seq': seq,
          'payload': payload,
        },
      );
      if (!res.ok) {
        final String key = errorKeyOfResponse(res);
        return BackupWriteResult(
          ok: false,
          errorKey: key.isEmpty ? 'network' : key,
          errorText: resumeErrorText(key.isEmpty ? 'network' : key, code),
        );
      }
      return BackupWriteResult(
        ok: true,
        seq: jsNum(res.json['seq']),
        stale: res.json['stale'] == true,
      );
    } catch (_) {
      return BackupWriteResult(
        ok: false,
        errorKey: 'network',
        errorText: resumeErrorText('network', code),
      );
    }
  }

  /// `POST /api/rooms/<code>/backup/read`（hostToken 放 body，避免进 access_log）。
  Future<BackupFetchResult> fetch(
    String base,
    String code,
    String hostToken,
  ) async {
    final String normalized = cloudRoomCode(code);
    try {
      final CloudHttpResponse res = await http.postJson(
        cloudApiUri(base.trim(), '/api/rooms/$normalized/backup/read'),
        <String, Object?>{'hostToken': hostToken},
      );
      if (!res.ok) {
        final String key = errorKeyOfResponse(res);
        return BackupFetchResult(
          ok: false,
          errorKey: key.isEmpty ? 'network' : key,
          errorText: resumeErrorText(key.isEmpty ? 'network' : key, code),
        );
      }
      return BackupFetchResult(
        ok: true,
        seq: jsNum(res.json['seq']),
        payload: jsStr(res.json['payload'] ?? ''),
        savedAt: jsNum(res.json['savedAt']),
      );
    } catch (_) {
      return BackupFetchResult(
        ok: false,
        errorKey: 'network',
        errorText: resumeErrorText('network', code),
      );
    }
  }

  /// `POST /api/rooms/<code>/suspend`（hostToken）：行不清、30 天可恢复。
  Future<bool> suspend(String base, String code, String hostToken) async {
    final String normalized = cloudRoomCode(code);
    try {
      final CloudHttpResponse res = await http.postJson(
        cloudApiUri(base.trim(), '/api/rooms/$normalized/suspend'),
        <String, Object?>{'hostToken': hostToken},
      );
      return res.ok;
    } catch (_) {
      return false;
    }
  }

  /// ★ D-5：末次保活（先 backup 后 suspend，顺序不可反）。
  ///
  /// [ctx] 是纯数据；本方法不引用任何 UI 对象。失败也继续走下一步
  /// （先明确失败、再 suspend），末次上传不受 B1 节流限制。
  Future<void> finalizeOnLeave(CloudBackupContext ctx) async {
    if (!ctx.isValid) return;
    // ① 末次全量档（成功或明确失败都要走到 ②）
    try {
      if (ctx.payload.isNotEmpty) {
        await upload(ctx.base, ctx.code, ctx.hostToken, ctx.seq, ctx.payload);
      }
    } catch (_) {
      // 明确失败：不截断、不伪造成功，但仍继续 suspend（D-5）。
    }
    // ② 房间挂起（顺序不可反）
    try {
      await suspend(ctx.base, ctx.code, ctx.hostToken);
    } catch (_) {
      // 崩溃 / 断网兜底靠服务端 30 天 TTL，不靠客户端。
    }
  }
}

/// ★ P20 顶层 fire-and-forget 入口（main.dart 的 detached 观察者与
/// `_RoomShellState.dispose()` 都调它）。只读全局纯数据快照，全链路
/// try/catch，绝不引用 context / _syncer / widget.controller。
///
/// 取出即清空，保证 dispose 与 detached 双重路径只发一次 backup + suspend。
Future<void> finalizeOnLeave() async {
  try {
    final CloudBackupContext? ctx = activeCloudBackupContext;
    clearActiveCloudBackup();
    if (ctx == null || !ctx.isValid) return;
    await CloudBackupService().finalizeOnLeave(ctx);
  } catch (_) {
    // 保活是 best-effort：绝不把异常抛回 App 退出路径。
  }
}

// ------------------------------------------------------------
// B1 / B5 云端备份钩子（RoomSaveSyncer.autoSave 调用）
// ------------------------------------------------------------

/// KP 每次自动存档后的全局钩子。**默认 null** —— flutter test 零网络、
/// 零异常（不加任何替身也不会发包）。生产由 [installCloudBackupRuntime] 装。
void Function(Map<String, Object?> save)? cloudBackupSink;

/// 节流时钟（可注入，便于测试 ≥5s 节流）。
int Function() cloudBackupClock = () => DateTime.now().millisecondsSinceEpoch;

int _lastUploadSeq = -1;
int _lastUploadAtMs = 0;

/// 重置节流状态（测试隔离用）。
void resetCloudBackupThrottle() {
  _lastUploadSeq = -1;
  _lastUploadAtMs = 0;
}

/// ★ 生产运行时装配（main.dart 调用一次）。
///
/// 把 `cloudBackupSink` 装成「KP 自动存档 → 20 键 payload → POST /backup」。
/// 节流：同一 `seq` 不重传、相邻两次最小间隔 ≥5s（设计 §5.4 B1）。
/// 只有 [activeCloudBackupContext] 有效（云端 KP）时才发包 —— 玩家侧 /
/// LAN / 本机房间零请求。
void installCloudBackupRuntime() {
  cloudBackupSink = (Map<String, Object?> save) {
    try {
      final CloudBackupContext? ctx = activeCloudBackupContext;
      if (ctx == null || !ctx.isValid) return;
      final int seq = jsNum(save['seq']);
      final String payload = jsonEncode(save);
      // 缓存末次全量档（供 finalizeOnLeave 在 dispose 后使用）。
      armCloudBackup(ctx.copyWith(seq: seq, payload: payload));
      final int now = cloudBackupClock();
      if (seq == _lastUploadSeq) return; // 同 seq 不重传
      if (now - _lastUploadAtMs < 5000 && _lastUploadAtMs > 0) return; // ≥5s 节流
      _lastUploadSeq = seq;
      _lastUploadAtMs = now;
      unawaited(CloudBackupService().upload(
        ctx.base,
        ctx.code,
        ctx.hostToken,
        seq,
        payload,
      ));
    } catch (_) {
      // 备份是辅助能力，绝不拖垮自动存档主流程。
    }
  };
}
