// ============================================================
// ui/room/room_resume.dart — P20 续玩编排层（N4）
//
// [RoomResumeService] 是应用服务：判定是否弹窗、默认选中优先级、
// 按 `role × mode` 分派、云端 seq 比对（K3/K4/K5）、凭据刷新、banner、
// F1–F7 文案。它**不持有 BuildContext**，弹窗由入口页 `_resume()` 调用
// resume_mode_dialog.dart 后把用户选择传进来 —— 决策与 UI 分离、可单测。
//
// ★ 诚实提示（R-09）：任何失败分支都不出现「已连回 / 已同步 / 云端第 N 版」。
// ★ 取消零副作用：不写凭据、不改存档、不自动进离线副本（由 _resume 保证）。
// ★ D-2：用户**主动选**「仅本机离线副本」横幅为「已载入本机存档」，
//   不含「未能连回」字样；关房**不清**凭据。
// ============================================================

import 'dart:convert' show jsonEncode;

import '../../domain/js_compat.dart' show asMap, jsNum;
import '../../domain/room_model_save.dart' show parseSave;
import '../../domain/room_ports.dart' show RoomSaveStore;
import '../../domain/room_types.dart' show RoomRole;
import '../../net/cloud_room.dart' show cloudRoomCode;
import '../../net/cloud_room_backup.dart'
    show
        BackupFetchResult,
        BackupWriteResult,
        CloudBackupService,
        CloudRoomResumeResult,
        resumeErrorText;
import '../../repo/recent_room_credential.dart'
    show
        RecentRoomCredential,
        loadRecentCredentialFlexible,
        saveRecentCredential;
import 'room_boot.dart'
    show
        CloudBootResult,
        RoomBoot,
        normalizeRoomCode,
        resumeCloudRoom,
        resumeLanHostedRoom;
import 'room_net_factory.dart'
    show CloudJoinOutcome, JoinOutcome, RoomNetFactory;
import 'room_text.dart' show roomText;
import 'resume_mode_dialog.dart' show ResumeMode;

/// 编排结果：三选一承载 [boot]（LAN KP / 云端 KP）/ [cloudJoin]（云端玩家）/
/// [lanJoin]（LAN 玩家）+ [banner] + 失败信息。
class ResumeRunResult {
  const ResumeRunResult({
    required this.ok,
    this.boot,
    this.cloudJoin,
    this.lanJoin,
    this.banner = '',
    this.errorKey = '',
    this.errorText = '',
    this.offline = false,
  });

  final bool ok;
  final RoomBoot? boot;
  final CloudJoinOutcome? cloudJoin;
  final JoinOutcome? lanJoin;
  final String banner;
  final String errorKey;
  final String errorText;

  /// 用户主动选「仅本机离线副本」：入口页走既有 resumeLocalRoom 离线路径。
  final bool offline;

  /// 失败便捷构造。
  factory ResumeRunResult.failure(String errorKey, String code) =>
      ResumeRunResult(
        ok: false,
        errorKey: errorKey,
        errorText: resumeErrorText(errorKey, code),
      );

  /// 离线副本便捷构造（D-2：横幅与 v2.32.0 逐字节一致，不含「未能连回」）。
  factory ResumeRunResult.offlineChoice() => const ResumeRunResult(
        ok: true,
        offline: true,
        banner: '已载入本机存档',
      );
}

/// 续玩编排服务。
class RoomResumeService {
  RoomResumeService({
    required this.store,
    CloudBackupService? backup,
    int Function()? clock,
  })  : backup = backup ?? CloudBackupService(),
        clock = clock ?? _systemNowMs;

  /// 存档后端（用于把云端较新的档灌回本机会话）。
  final RoomSaveStore store;

  /// 云端备份服务（可注入内存 CloudHttpTransport 替身）。
  final CloudBackupService backup;

  /// 可注入时钟（测 7 天 TTL 用）。
  final int Function() clock;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 是否该弹「选择续玩方式」：有凭据且 `hasBase==true` 必弹；
  /// 无凭据 / base 空 → 不弹，直接走既有离线路径（行为与 v2.32.0 一致）。
  Future<bool> shouldShowDialog(String code) async {
    if (code.trim().isEmpty) return false;
    final RecentRoomCredential? cred = loadRecentCredentialFlexible(code);
    return cred != null && cred.hasBase;
  }

  /// 默认选中优先级（设计 §4.4 / §8.4）：
  /// `lastOkMode(now)` > `inferredMode()` > `offline`。
  /// `hasBase==true` 时 inferredMode 恒有值（cloud/lan），第 3 档不会命中。
  ResumeMode defaultMode(RecentRoomCredential cred, int nowMs) {
    final String remembered = cred.lastOkMode(nowMs);
    if (remembered == 'cloud') return ResumeMode.cloud;
    if (remembered == 'lan') return ResumeMode.lan;
    final String inferred = cred.inferredMode();
    if (inferred == 'cloud') return ResumeMode.cloud;
    if (inferred == 'lan') return ResumeMode.lan;
    return ResumeMode.offline;
  }

  /// 生成横幅（成功路径才带「已连回」；失败/离线不带）。
  String bannerOf(ResumeRunResult r) => r.banner;

  /// 按 `role × mode` 分派。
  ///
  /// [confirmCloudNewer] 是 K4 的 KP 显式确认回调（由入口页注入
  /// `showCloudNewerDialog`）；为 null 或返回 false 时**不覆盖**本机档。
  Future<ResumeRunResult> run(
    Map<String, Object?> save,
    RecentRoomCredential cred,
    ResumeMode mode, {
    Future<bool> Function(int cloudSeq, int localSeq)? confirmCloudNewer,
  }) async {
    switch (mode) {
      case ResumeMode.offline:
        return ResumeRunResult.offlineChoice();
      case ResumeMode.cloud:
        return _runCloud(save, cred, confirmCloudNewer: confirmCloudNewer);
      case ResumeMode.lan:
        return _runLan(save, cred);
    }
  }

  // ----------------------------------------------------------
  // 云端：KP / 玩家
  // ----------------------------------------------------------
  Future<ResumeRunResult> _runCloud(
    Map<String, Object?> save,
    RecentRoomCredential cred, {
    Future<bool> Function(int cloudSeq, int localSeq)? confirmCloudNewer,
  }) async {
    final String code = cloudRoomCode(_codeOf(save));

    if (cred.hostToken.isNotEmpty) {
      // ===== 云端 KP =====
      // ① POST /resume（hostToken）把 SUSPENDED/IN_GAME → RECRUITING。
      //    绝无 POST /api/rooms / registerRoom / newRoomCode。
      final CloudRoomResumeResult resumed =
          await backup.resumeRoom(cred.base, code, cred.hostToken);
      if (!resumed.ok) {
        return ResumeRunResult.failure(resumed.errorKey, code);
      }
      // ② 原 code + 原 hostToken + WS t=hostToken（不登记新房）。
      final CloudBootResult boot = await resumeCloudRoom(
        save: save,
        base: cred.base,
        code: code,
        hostToken: cred.hostToken,
        deviceId: cred.deviceId,
        saveStore: store,
      );
      if (!boot.ok || boot.boot == null) {
        return ResumeRunResult.failure('network', code);
      }
      // ③ 拉云端全量档比 seq（K3/K4/K5）。
      final BackupFetchResult fetched =
          await backup.fetch(cred.base, code, cred.hostToken);
      final int localSeq = jsNum(save['seq']);
      final int cloudSeq = fetched.ok ? fetched.seq : 0;
      final RoomBoot roomBoot = boot.boot!;

      if (fetched.ok && cloudSeq > localSeq) {
        // K4：必须 KP 显式确认才 adoptSave；未确认不静默覆盖、不伪造成功、
        //     不偷偷抬 seq，且按 F6 口径如实提示「本次未备份到云端」。
        bool adopt = false;
        if (confirmCloudNewer != null) {
          adopt = await confirmCloudNewer(cloudSeq, localSeq);
        }
        if (adopt) {
          final Map<String, Object?>? cloudSave = parseSave(fetched.payload);
          if (cloudSave == null) {
            await roomBoot.controller.openSave(save);
            return ResumeRunResult.failure('parse_failed', code);
          }
          await roomBoot.controller.openSave(cloudSave);
        } else {
          // 保留本机：后续上传会因 stale 被拒，不伪造成功。
          await roomBoot.controller.openSave(save);
          _refreshCredential(cred, code, 'cloud');
          return ResumeRunResult(
            ok: true,
            boot: roomBoot,
            banner: '已连回房间 $code · 身份：KP · '
                '云端已有第 $cloudSeq 版进度，本次未备份到云端',
          );
        }
      } else {
        // K1/K3：以本机为准。
        await roomBoot.controller.openSave(save);
        // K5：本机更优 → 立即补一次上传把云端追平
        // （stale 是正常结果，不弹错、不重试风暴）。
        if (localSeq > cloudSeq && fetched.ok) {
          final BackupWriteResult _ = await backup.upload(
            cred.base,
            code,
            cred.hostToken,
            localSeq,
            jsonEncode(save),
          );
        }
      }
      _refreshCredential(cred, code, 'cloud');
      return ResumeRunResult(
        ok: true,
        boot: roomBoot,
        banner: '已连回房间 $code · 身份：KP · 进度：云端第 '
            '${cloudSeq > localSeq ? cloudSeq : localSeq} 版',
      );
    }

    // ===== 云端玩家 =====
    // 带原 deviceId 走 /join → get_device_seat 命中 → joinKind='reconnect'、
    // 复用原 seat/role，豁免满员/已开局。玩家**不上传、不下载**云端全量档。
    final CloudJoinOutcome out = await RoomNetFactory.joinCloud(
      base: cred.base,
      code: code,
      deviceId: cred.deviceId,
    );
    if (!out.ok || out.session == null) {
      return ResumeRunResult.failure(_joinErrorKey(out.error), code);
    }
    _refreshCredential(cred, code, 'cloud');
    return ResumeRunResult(
      ok: true,
      cloudJoin: out,
      banner: '已连回房间 $code · 身份：'
          '${cred.role == RoomRole.spectator ? '旁观者' : '玩家'}'
          '（座位 ${out.session!.seat}）',
    );
  }

  // ----------------------------------------------------------
  // 局域网：KP / 玩家
  // ----------------------------------------------------------
  Future<ResumeRunResult> _runLan(
    Map<String, Object?> save,
    RecentRoomCredential cred,
  ) async {
    // LAN 房号保持大写归一不变（normalizeRoomCode 原语义）。
    final String code = normalizeRoomCode(_codeOf(save));
    if (_isKp(save, cred)) {
      // LAN KP：用存档 meta.code 原号重开 LAN 服务 + openSave 灌档。
      try {
        final RoomBoot boot = await resumeLanHostedRoom(save, saveStore: store);
        _refreshCredential(cred, code, 'lan');
        return ResumeRunResult(
          ok: true,
          boot: boot,
          banner: '已连回房间 $code · 身份：KP',
        );
      } catch (_) {
        return ResumeRunResult.failure('lan_not_found', code);
      }
    }
    // LAN 玩家：带原 deviceId 作 cid 加入，服务端 reuseSeat 幂等复用旧座。
    final JoinOutcome out = await RoomNetFactory.join(
      code: code,
      seat: '',
      injectedBase: cred.base,
      deviceId: cred.deviceId,
    );
    if (!out.ok || out.session == null) {
      return ResumeRunResult.failure('lan_not_found', code);
    }
    _refreshCredential(cred, code, 'lan');
    return ResumeRunResult(
      ok: true,
      lanJoin: out,
      banner: '已连回房间 $code · 身份：玩家（座位 ${out.session!.seat}）',
    );
  }

  // ----------------------------------------------------------
  // 工具
  // ----------------------------------------------------------

  /// 续玩成功：刷新 mode / savedAt / lastOkAt，**保持**原 hostToken/deviceId/
  /// base/role/seat（凭据 5 写入点之一，D-2 不清凭据）。
  void _refreshCredential(
    RecentRoomCredential cred,
    String code,
    String mode,
  ) {
    saveRecentCredential(
      roomCode: code,
      base: cred.base,
      hostToken: cred.hostToken,
      deviceId: cred.deviceId,
      role: cred.role,
      seat: cred.seat,
      mode: mode,
      lastOkAt: clock(),
    );
  }

  /// 存档里的房号（meta.code）。
  String _codeOf(Map<String, Object?> save) =>
      roomText(asMap(save['meta'])['code']);

  /// 视角是否 KP：cred.role 优先，其次存档 meta.role / members[].self。
  /// hostToken 非空一定是 KP（玩家凭据 hostToken 恒 ''）。
  bool _isKp(Map<String, Object?> save, RecentRoomCredential cred) {
    if (cred.hostToken.isNotEmpty) return true;
    if (cred.role == RoomRole.player || cred.role == RoomRole.spectator) {
      return false;
    }
    if (cred.role == RoomRole.kp) return true;
    final String metaRole = roomText(asMap(save['meta'])['role']);
    if (metaRole == RoomRole.player || metaRole == RoomRole.spectator) {
      return false;
    }
    return true; // 默认 KP（权威存档本来就是 KP 视角）
  }

  /// 玩家 join 失败文案 → errorKey（F4 / F5 / F2）。
  String _joinErrorKey(String error) {
    final String e = error.toLowerCase();
    if (e.contains('suspend') || e.contains('挂起')) return 'room_suspended';
    if (e.contains('not_found') || e.contains('过期') ||
        e.contains('不存在') || e.contains('连不上')) {
      return 'not_found';
    }
    return 'network';
  }
}
