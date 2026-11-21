// ============================================================
// main.dart — 应用入口
//
// 启动顺序：先把角色卡读进内存，再起 UI。
// 读盘失败不会阻塞启动（repo 会记下 lastError 并给空列表），
// 这样即使 JSON 被写坏，用户也能进首页而不是看到白屏。
// ============================================================

import 'dart:async' show unawaited;
import 'dart:io' show Directory, Platform;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'repo/ai_probe_io.dart';
import 'repo/character_repo.dart';
import 'repo/cloud_device_id.dart'
    show FileDeviceIdStorage, deviceIdStorage;
import 'repo/file_room_save_store.dart';
import 'repo/recent_room_credential.dart'
    show FileRecentCredentialStorage, recentCredentialStore;
import 'repo/settings_repo.dart';
import 'repo/share_store.dart';
import 'net/cloud_room_backup.dart'
    show finalizeOnLeave, installCloudBackupRuntime;
import 'net/share_client.dart';
import 'ui/room/room_boot.dart' show installRoomSaveStore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = CharacterRepo();
  // 设置先读：房规数值上限是「每次生成现读」的，早读一步，
  // 第 0 步生成随机卡时就已经按玩家的上限在算。
  final settings = SettingsRepo(probe: HttpAiProbe());
  // 分享：地址是**现读**设置里的 shareBase（改完设置立刻生效，
  // 不需要重建客户端）；记录单独一个文件，方便把删除口令和角色卡分开清理。
  final shareStore = ShareStore();
  final share = ShareService(
    client: ShareClient(baseProvider: () => settings.shareBase),
    store: shareStore,
  );
  await Future.wait<void>(<Future<void>>[
    repo.load(),
    settings.load(),
    shareStore.load(),
  ]);
  // 房间存档：能拿到应用目录就落盘（切后台被系统回收也不丢），
  // 拿不到就保持内存实现 —— 存档不可用绝不能挡住启动。
  await _installRoomSaves();
  runApp(DiceRealmApp(repo: repo, settings: settings, share: share));
}

/// 把房间存档换到文件后端。
///
/// 目录用**应用文档目录**而不是缓存目录：缓存会被系统在空间紧张时清掉，
/// 存档放那里等于随机丢档。
Future<void> _installRoomSaves() async {
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      '${docs.path}${Platform.pathSeparator}room_saves',
    );
    final FileRoomSaveStore store = FileRoomSaveStore(dir);
    // ★ P13 T1 主修法：先把文件后端装进全局，再 loadSync。
    //   旧顺序下 loadSync 之前的任何异常都会让 install 永不执行，
    //   全局 store 一直是内存实现 → put 只写内存、退出即丢。
    installRoomSaveStore(store);
    debugPrint('[SAVE] installed FileRoomSaveStore at ${dir.path}');
    store.loadSync(); // 同步读入，续玩列表首屏就有货
    // ★ P16 P-1(a)：联网房间凭据的落盘后端。
    //   目录必须**独立于存档**（下面的 `.room_credentials`，与 `room_saves`
    //   平级但分开）：存档会被「导出游戏历史 / 云分享」整包带走，凭据里有
    //   hostToken，混进去就等于随存档泄露。这个私有目录：
    //   · 不进存档快照、不进导出、不进云分享；
    //   · 不写任何日志（`recent_room_credential.dart` 全程零 print）；
    //   · `.gitignore` 已加 `**/.room_credentials/`。
    //   ★ P20：凭据写入点已下沉到 `room_boot.dart` / `room_net_factory.dart`
    //   / `room_resume.dart`（开房 / 加入 / 续玩成功时写），不再留到下一批。
    final Directory credDir = Directory(
      '${docs.path}${Platform.pathSeparator}.room_credentials',
    );
    recentCredentialStore = FileRecentCredentialStorage(credDir);
    // ★ P20：稳定 deviceId 落**同一私有目录、不同文件**（`device_id.txt`），
    //   与 `recent_rooms.json` 分离；App 重启后服务端 device_seats 仍能回座。
    deviceIdStorage = FileDeviceIdStorage(credDir);
    // ★ P20：安装云端备份运行时（`cloudBackupSink` 生产实现，默认 null 时
    //   flutter test 零网络；见 cloud_room_backup.dart）。
    installCloudBackupRuntime();
    // ★ P20 Q4：仅 App 即将终止（detached）时触发离房保活；
    //   paused / hidden / inactive 一律不触发（短暂切后台不 suspend）。
    WidgetsBinding.instance.addObserver(_P20LifecycleObserver());
  } catch (e) {
    // 插件不可用（极少数定制 ROM）或目录不可写：保持内存实现。
    // 界面上「关闭 App 后不保留」的说明仍然成立，不会骗用户。
    // ★ P13 T1：绝不空吞 —— 安装失败必须留下可诊断日志。
    debugPrint('[SAVE] _installRoomSaves FAILED: $e');
  }
}

/// ★ P20：App 生命周期观察者。
///
/// **只**在 [AppLifecycleState.detached]（App 即将终止）触发
/// [finalizeOnLeave] —— 它内部只捕获纯数据上下文、全链路 try/catch、
/// best-effort fire-and-forget（先末次 `POST /backup` 再 `POST /suspend`）。
/// 短暂切后台 / 切前台 / 失焦**一律不动作**，避免给还在房里的玩家造成
/// `room_suspended`（主理人 D-5）。崩溃兜底靠服务端 30 天 TTL，不靠客户端。
class _P20LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached) return;
    try {
      unawaited(finalizeOnLeave());
    } catch (_) {
      // 保活是 best-effort：绝不让 App 退出路径抛异常。
    }
  }
}
