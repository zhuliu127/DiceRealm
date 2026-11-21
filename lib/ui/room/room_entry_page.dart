// ============================================================
// room_entry_page.dart — 房间入口页（创建 / 加入 / 续玩，设计 §2 / §5 T05）
//
// 三个功能区互相独立：
//   ① 创建：本机开一个房间（你就是 KP），生成 6 位房间号，顺手存一份本机存档；
//   ② 加入：P6 已完成局域网联机——先在同一 WiFi 下发现房间并连到远端服务，
//      也可手输服务地址；发现 / 连接失败才回退到本机预览会话。界面上用
//      「已连上局域网房间（实时同步）」与「本机预览」两条横幅如实区分，
//      不许把回退预览说成连上了远端；
//   ③ 续玩：列本机存档槽。生产存档后端在 main() 里装成落盘持久化实现，
//      App 重启后仍在；测试注入的才是内存后端，别把两者混写。
//
// ★ 只用端口与 UI 层：零权威状态写入、零规则调用。
// ★ 装配全部走 `room_boot.dart`（组合根），本文件不直接 new `RoomHost`。
// ============================================================

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../domain/room_ports.dart' show RoomSaveStore;
import '../../domain/js_compat.dart' show jsParseInt;
import '../../theme.dart' show AppBackground, Palette;
import '../../domain/room_types.dart' show RoomRole;
import 'room_boot.dart'
    show
        CloudBootResult,
        RoomBoot,
        bootCloudRoom,
        bootHostedRoom,
        bootLocalRoom,
        isValidRoomCode,
        kRoomCodeLength,
        newRoomCode,
        normalizeRoomCode,
        resumeLocalRoom,
        roomSaveSlots;
import '../../repo/room_notes_store.dart' show MemoryNotesStorage, RoomNotesStore;
import '../../repo/room_save_store.dart' show RoomSaveStoreMutable;
import '../../net/lan_discovery.dart' show RoomAnnounce;
import '../art.dart';
import '../../repo/room_state_writer.dart' show CharacterRepoRoomCardSink;
import '../../repo/repo_scope.dart' show AppRoutes, RepoScope, SettingsScope;
import '../../net/cloud_room.dart' show isCloudBase, normalizeCloudBase;
import '../../repo/recent_room_credential.dart'
    show RecentRoomCredential, loadRecentCredentialFlexible;
// ★ P20 新增 import（下层新增组件/服务，既有 import 行零改动）。
import '../../net/cloud_room_backup.dart'
    show clearActiveCloudBackup, finalizeOnLeave;
import 'room_resume.dart' show ResumeRunResult, RoomResumeService;
import 'resume_mode_dialog.dart'
    show
        ResumeChoice,
        ResumeFailAction,
        ResumeMode,
        showCloudNewerDialog,
        showResumeFailedDialog,
        showResumeModeDialog;
import 'room_card_saver.dart' show RoomCardSaver;
import 'room_save_syncer.dart' show RoomSaveSyncer;
import 'room_session_local.dart' show LocalLoopbackSession;
import 'room_controller.dart' show RoomController;
import 'room_exit.dart' show RoomExit, RoomExitKind, roomExitOf;
// ★ P20：`RoomExit.shouldLeave == false` 即 `kind == none`（未关房），
//   无需额外导入 RoomExitKind 枚举。
import 'room_session_hosting.dart' show HostingLocalSession;
import 'room_net_factory.dart' show CloudJoinOutcome, JoinOutcome, RoomNetFactory;
import 'room_session.dart' show RoomSession;
import 'room_session_cloud.dart' show CloudHostingSession, CloudRemoteSession;
import 'room_session_remote.dart' show RemoteSession;
import 'room_ui_local.dart' show RoomUiLocal;
// ★ P20（需求 5 / D11）：结团 / 关房 / 被踢时必须停掉本机 BGM。
//   本文件是**整间房唯一的壳体**（每台设备各跑一遍），所以停音乐挂在这里。
import 'room_music_ports.dart' show musicPort;
import 'room_game_page.dart' show RoomGamePage;
import 'room_lobby_page.dart' show RoomLobbyPage;
import 'room_scope.dart' show RoomScope;
import 'view/room_view.dart' show isInGame;
import 'room_theme.dart' show RoomTheme;
import 'save_persist_hint.dart' show savePersistHintOf;
import 'save_time.dart' show saveTimeText;
import 'sheets/sheet_nearby_rooms.dart' show showNearbyRoomsSheet;
import 'widgets/room_notice_overlay.dart' show RoomNoticeOverlay;
import 'widgets/room_panel_kit.dart' show ConfirmTwice, RoomTap, SectionBox;

/// 加入时该不该走「公网中继」通道（抽成纯函数，便于回归测试）。
///
/// ★ P12 真机 bug：从「附近的房间」（UDP 广播，只能发现同网段）选中的
///   地址**必定是局域网**，哪怕它长得像 `http://192.168.x.x:4211`。
///   之前只靠 `isCloudBase()` 看 scheme，把它当成公网中继 → HTTP 404。
///   这里加一道与地址无关的保险：`fromDiscovery` 时一律走局域网，
///   以后就算 `isCloudBase` 的口径再变，也不会把扫到的房间送进云端。
bool shouldJoinCloud(String base, {required bool fromDiscovery}) =>
    !fromDiscovery && isCloudBase(base);

/// 入口页内部稳定 key（用例与门禁共用，避免字面量漂移）。
class RoomEntryKeys {
  const RoomEntryKeys._();

  static const Key root = ValueKey<String>('roomEntry/root');
  static const Key createName = ValueKey<String>('roomEntry/create/name');
  static const Key createNick = ValueKey<String>('roomEntry/create/nick');
  static const Key createSubmit = ValueKey<String>('roomEntry/create/submit');

  /// 公网开房按钮（B5）。与局域网按钮**分开**：两条路失败模式完全不同。
  static const Key createSubmitCloud =
      ValueKey<String>('roomEntry/create/submitCloud');

  /// 未配置公网地址时给「去设置」的真入口（不发假请求）。
  static const Key cloudSetupHint = ValueKey<String>('roomEntry/create/cloudHint');
  static const Key createdCode = ValueKey<String>('roomEntry/create/code');
  static const Key createdCopy = ValueKey<String>('roomEntry/create/copy');
  static const Key joinCode = ValueKey<String>('roomEntry/join/code');
  static const Key joinNick = ValueKey<String>('roomEntry/join/nick');

  /// 手输服务地址（UDP 被拦时的兜底，如企业 WiFi / 热点隔离）。
  static const Key joinBase = ValueKey<String>('roomEntry/join/base');
  static const Key joinSubmit = ValueKey<String>('roomEntry/join/submit');
  static const Key joinHint = ValueKey<String>('roomEntry/join/hint');

  /// 打开「附近的房间」（UDP 扫描结果列表）。
  static const Key nearby = ValueKey<String>('roomEntry/join/nearby');
  static const Key resumeEmpty = ValueKey<String>('roomEntry/resume/empty');
  static const Key resumeHint = ValueKey<String>('roomEntry/resume/hint');
  static const Key busy = ValueKey<String>('roomEntry/busy');
  static const Key banner = ValueKey<String>('roomEntry/banner');

  /// 离开房间的原因横幅（结团 / 关房 / 被踢后回到入口页时显示）。
  static const Key notice = ValueKey<String>('roomEntry/notice');

  /// 一个存档槽行（`roomEntry/resume/row/<槽键>`）。
  static Key resumeRow(String key) => ValueKey<String>('roomEntry/resume/row/$key');

  /// 槽行的「载入」按钮。
  static Key resumeLoad(String key) => ValueKey<String>('roomEntry/resume/load/$key');

  /// 槽行的「删除」按钮（P15 新增；两段式确认，无弹窗）。
  static Key resumeRemove(String key) =>
      ValueKey<String>('roomEntry/resume/remove/$key');
}

/// 房间入口页。
class RoomEntryPage extends StatefulWidget {
  const RoomEntryPage({super.key, this.initialCode, this.saveStore});

  /// 从「加入房间」深链进来时预填的房间号（`AppRoutes.roomCode(code)`）。
  final String? initialCode;

  /// 存档后端（默认本机唯一实例；测试注入自己的，避免用例互相串味）。
  final RoomSaveStore? saveStore;

  @override
  State<RoomEntryPage> createState() => _RoomEntryPageState();
}

class _RoomEntryPageState extends State<RoomEntryPage> {
  late final TextEditingController _createName;
  late final TextEditingController _createNick;
  late final TextEditingController _joinCode;
  late final TextEditingController _joinNick;

  /// 手输服务地址（可空 —— 空则靠 UDP 发现）。
  late final TextEditingController _joinBase;

  /// 刚创建出来的房间号（null = 还没创建过）。
  String? _created;

  /// 本机存档槽键（按写入顺序倒序展示：新存档在上）。
  List<String> _saves = <String>[];

  /// 正在装配房间（防连点，也用来渲染一个转圈）。
  bool _busy = false;

  /// 上次操作失败的原因（块级提示，不弹模态）。
  String? _error;

  /// 上次「为什么离开了房间」（结团 / 关房 / 被踢）。与 [_error] 分开：
  /// 这不是失败，用中性色显示，也不该和红色报错混在一起。
  String? _notice;

  RoomSaveStore get _store => widget.saveStore ?? roomSaveSlots;

  /// 设置里配的公网中继地址（空串 = 未配置）。
  ///
  /// 用 `SettingsScope` 而不是缓存字段：设置页改完地址回到这里必须**立刻**
  /// 反映出来，否则用户会以为「填了没用」。
  String get _cloudBase {
    final scope = context.getInheritedWidgetOfExactType<SettingsScope>();
    final raw = scope?.notifier?.roomBase ?? '';
    return normalizeCloudBase(raw);
  }

  @override
  void initState() {
    super.initState();
    _createName = TextEditingController(text: '洋馆惊魂');
    _createNick = TextEditingController(text: 'KP');
    _joinCode = TextEditingController(text: normalizeRoomCode(widget.initialCode ?? ''));
    _joinNick = TextEditingController(text: '调查员');
    _joinBase = TextEditingController(text: '');
    _reloadSaves();
  }

  @override
  void dispose() {
    _createName.dispose();
    _createNick.dispose();
    _joinCode.dispose();
    _joinNick.dispose();
    _joinBase.dispose();
    super.dispose();
  }

  void _reloadSaves() {
    final keys = <String>[..._store.list()];
    // 新的在上：按存档顶层的 savedAt（毫秒）降序，而不是按槽键名字排序。
    // 读不出 savedAt 的按 0 处理 → 排在最后（不丢）；同时间戳按槽键倒序兜底。
    int savedAtOf(String key) => jsParseInt(_store.get(key)?['savedAt']) ?? 0;
    keys.sort((String a, String b) {
      final ta = savedAtOf(a);
      final tb = savedAtOf(b);
      if (ta != tb) return tb.compareTo(ta);
      return b.compareTo(a);
    });
    final ordered = keys;

    // ★ GL-1（R8 / R12）：同一个房号可能同时存在三条槽 ——
    //   `auto/<code>/…`（KP 自动档）、`share/<code>/latest`（玩家收档）
    //   与房号键本身（续玩可见档）。按 meta.code 大写归一去重，
    //   **优先保留键本身就是房号的那条**：否则 _resume() 读到的是
    //   auto/ 或 share/ 槽，③ 区会出现三行同一个房间。
    final byCode = <String, String>{};
    final noCode = <String>[];
    for (final key in ordered) {
      final save = _store.get(key);
      final meta = (save?['meta'] is Map)
          ? (save!['meta']! as Map)
          : const <String, Object?>{};
      final code = '${meta['code'] ?? ''}'.trim().toUpperCase();
      if (code.isEmpty) {
        // 读不出房号的自定义槽：原样保留，不参与折叠。
        noCode.add(key);
        continue;
      }
      final prev = byCode[code];
      final isRoomKey = key.toUpperCase() == code;
      if (prev == null || (isRoomKey && prev.toUpperCase() != code)) {
        byCode[code] = key;
      }
    }
    // 保留「新的在上」的相对顺序，只把被折叠掉的键从结果里剔除。
    final chosen = <String>{...byCode.values, ...noCode};
    _saves = ordered.where((String k) => chosen.contains(k)).toList();
  }

  // ----------------------------------------------------------
  // ① 创建
  // ----------------------------------------------------------

  Future<void> _create() async {
    if (_busy) return;
    final name = _createName.text.trim().isEmpty ? '无名房间' : _createName.text.trim();
    final nick = _createNick.text.trim().isEmpty ? 'KP' : _createNick.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = newRoomCode();
      // P6：建房即开局域网服务 + 广播，别人才能搜到。
      final boot = await bootHostedRoom(
        code: code,
        name: name,
        nickname: nick,
        saveStore: _store,
        cardSink: CharacterRepoRoomCardSink(RepoScope.read(context)),
      );
      // 创建即存一份本机存档：续玩列表立刻有东西，且不必先开存档槽。
      await boot.controller.saveNow();
      if (!mounted) return;
      setState(() {
        _created = code;
        _reloadSaves();
        _busy = false;
      });
      // ★ 横幅如实说网络状态：起不来就说「只有你自己能进」，不能假装联机了。
      final hosted = boot.session as HostingLocalSession;
      final banner = hosted.lanWifi
          ? '房间 $code 已创建 · 局域网已开（${hosted.lanBase}）· 同伴可搜到'
          : '房间 $code 已创建 · 未连局域网（只有你自己能进）';
      await _openRoom(boot, banner: banner);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '创建失败：$e';
      });
    }
  }

  // ----------------------------------------------------------
  // ①' 创建（公网中继）
  // ----------------------------------------------------------

  /// 公网开房：走 `SettingsRepo.roomBase` 里配的中继地址。
  ///
  /// ★ K7：**未配置就如实引导去设置**，绝不偷偷降级成本机房间
  ///   （那会让 KP 拿到一个别人根本连不上的房号，比报错更糟）。
  /// ★ 失败也如实说：中继连不上 / 登记被拒，都直接把原因写在这张卡片上。
  Future<void> _createCloud() async {
    if (_busy) return;
    final String base = normalizeCloudBase(SettingsScope.read(context).roomBase);
    if (base.isEmpty) {
      // 理论上按钮此时已被「去设置」替代；这里再兜一次，绝不发空地址请求。
      setState(() {
        _error = '还没有配置公网中继地址：请到「设置 → 跑团房间服务地址」填写';
      });
      return;
    }
    final name =
        _createName.text.trim().isEmpty ? '无名房间' : _createName.text.trim();
    final nick = _createNick.text.trim().isEmpty ? 'KP' : _createNick.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final CloudBootResult out = await bootCloudRoom(
        base: base,
        name: name,
        nickname: nick,
        saveStore: _store,
        cardSink: CharacterRepoRoomCardSink(RepoScope.read(context)),
      );
      if (!mounted) return;
      if (!out.ok || out.boot == null) {
        setState(() {
          _busy = false;
          _error = '公网开房失败：${out.error}';
        });
        return;
      }
      // 创建即存一份本机存档（与局域网开房同一口径）
      await out.boot!.controller.saveNow();
      if (!mounted) {
        out.boot!.dispose();
        return;
      }
      setState(() {
        _created = out.code;
        _reloadSaves();
        _busy = false;
      });
      await _openRoom(
        out.boot!,
        banner: '房间 ${out.code} 已创建 · 公网中继（$base）· 房间号发给同伴即可加入',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '公网开房失败：$e';
      });
    }
  }

  // ----------------------------------------------------------
  // ② 加入
  // ----------------------------------------------------------

  /// 打开「附近的房间」：选中后自动填好房号与地址并直接加入。
  ///
  /// 为什么要自动填：用户从列表里点「加入」，本来就已经表达了「就是这间」，
  /// 再让他抄一遍 6 位房号是多余的。填进去的同时也留了痕 —— 失败时输入框里
  /// 就是刚才那间房，手输兜底路径可以直接复用。
  Future<void> _openNearby() async {
    if (_busy) return;
    final RoomAnnounce? picked = await showNearbyRoomsSheet(context);
    if (picked == null || !mounted) return;
    _joinCode.text = picked.code;
    _joinBase.text = picked.base;
    // UDP 发现的一定是同网段房间，明确标记来源，不许被判成公网中继。
    await _join(fromDiscovery: true);
  }

  Future<void> _join({bool fromDiscovery = false}) async {
    if (_busy) return;
    final code = normalizeRoomCode(_joinCode.text);
    if (!isValidRoomCode(code)) {
      setState(() => _error = '房间号应为 $kRoomCodeLength 位大写字母或数字');
      return;
    }
    final nick = _joinNick.text.trim().isEmpty ? '调查员' : _joinNick.text.trim();
    // 手输地址优先于发现（UDP 被拦时这是唯一出路）。
    final manualBase = _joinBase.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    // ① 先定地址：手输优先，否则靠发现
    try {
      final hits = manualBase.isNotEmpty
          ? <RoomAnnounce>[]
          : (await RoomNetFactory.nearby(
              timeout: const Duration(milliseconds: 1200),
            )).where((a) => a.code == code).toList();
      // 手输地址时不校验房号是否匹配（对面会自己校验 WRONG_CODE）
      final String base = manualBase.isNotEmpty
          ? manualBase
          : (hits.isNotEmpty ? hits.first.base : '');
      // ★ B5：手填公网中继地址（https 域名）才走云端 join + 中继通道。
      //   ★ P12：局域网广播地址也带 http:// 前缀，靠 shouldJoinCloud
      //   的主机判定 + fromDiscovery 双重把关，不再误判成公网。
      if (shouldJoinCloud(base, fromDiscovery: fromDiscovery)) {
        final CloudJoinOutcome out = await RoomNetFactory.joinCloud(
          base: base,
          code: code,
          nickname: nick,
        );
        if (out.ok && out.session != null) {
          if (!mounted) {
            out.session!.closeConnection();
            return;
          }
          setState(() => _busy = false);
          await _openCloud(out, banner: '已连上公网房间（云端中继：$base）');
          return;
        }
        if (mounted) {
          setState(() {
            _busy = false;
            _error = '公网加入失败：${out.error}';
          });
        }
        return;
      }
      if (base.isNotEmpty) {
        final JoinOutcome out = await RoomNetFactory.join(
          code: code,
          seat: '', // 空座位 = 让服务端分配（玩家不认识座位）
          injectedBase: base,
        );
        if (out.ok) {
          if (!mounted) {
            out.session?.dispose();
            return;
          }
          setState(() => _busy = false);
          await _openRemote(out.session!, banner: kJoinLanBanner);
          return;
        }
      }
    } catch (_) {
      // 扫描/连接失败不阻止本机预览（可能只是防火墙拦了 UDP）
    }

    if (!mounted) return;

    // ② 回退：本机预览会话（P5 行为，单机试玩）
    try {
      final boot = await bootLocalRoom(
        code: code,
        name: '$code 的房间',
        nickname: nick,
        role: RoomRole.player,
        seat: 'p1',
        saveStore: _store,
        cardSink: CharacterRepoRoomCardSink(RepoScope.read(context)),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _openRoom(boot, banner: kJoinPreviewBanner);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '加入失败：$e';
      });
    }
  }

  /// 加入区下方的常驻说明 + 回退本机预览时的横幅（不骗人）。
  /// ★ P16 P-1(b) ④：明确「没找到该房间，已开离线预览」，别静默降级；
  ///   保留「本机预览」字样（既有入口页用例钉死 contains('本机预览')）。
  static const String kJoinPreviewBanner =
      '没找到该房间，已开离线预览（本机预览：只有你自己看得到）';

  /// 真的连上了局域网房间时的横幅。
  static const String kJoinLanBanner = '已连上局域网房间（实时同步）';

  // ----------------------------------------------------------
  // ③ 续玩
  // ----------------------------------------------------------

  Future<void> _resume(String key) async {
    if (_busy) return;
    final save = _store.get(key);
    if (save == null) {
      setState(() => _error = '这条存档读不出来了');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map metaMap = save['meta'] is Map
          ? save['meta']! as Map
          : const <String, Object?>{};
      final String code = (metaMap['code'] ?? '').toString().trim();
      // ★ P20：读凭据用 flexible（兼容云端小写 / LAN 大写 / 历史混合大小写）。
      final RecentRoomCredential? cred =
          code.isEmpty ? null : loadRecentCredentialFlexible(code);

      // ----------------------------------------------------------
      // 离线路径（无凭据 / hasBase=false / 用户主动选「仅本机离线副本」）
      // ★ 与 v2.32.0 **逐字节一致**：仍走既有 resumeLocalRoom，横幅
      //   '已载入本机存档'（+ migrated 脱敏提示），不含「未能连回」字样
      //   （主理人 D-2）。绝不联网、不写凭据、不改存档。
      // ----------------------------------------------------------
      Future<void> openOffline() async {
        final (boot, migrated) = await resumeLocalRoom(
          save,
          saveStore: _store,
          cardSink: CharacterRepoRoomCardSink(RepoScope.read(context)),
        );
        if (!mounted) return;
        setState(() => _busy = false);
        final String banner;
        if (migrated > 0) {
          banner =
              '已载入本机存档 · 旧存档含历史明文记录，已自动脱敏 $migrated 条';
        } else {
          banner = '已载入本机存档';
        }
        await _openRoom(boot, banner: banner);
      }

      // F1：无凭据 / base 空 → 不弹窗、零联网请求，直接既有离线路径。
      if (cred == null || !cred.hasBase) {
        await openOffline();
        return;
      }

      // ----------------------------------------------------------
      // 有凭据且 hasBase → **必弹**「选择续玩方式」3 选项
      // ----------------------------------------------------------
      final RoomResumeService service = RoomResumeService(store: _store);
      final ResumeChoice choice = await showResumeModeDialog(
        context,
        code: code,
        defaultMode: service.defaultMode(cred, service.clock()),
      );
      if (!mounted) return;
      // S7：取消 → 零副作用，回入口页；不写凭据 / 不改存档 / 不进离线副本。
      if (choice.cancelled) {
        setState(() => _busy = false);
        return;
      }
      // D-2：主动选「仅本机离线副本」→ 横幅『已载入本机存档』，不含「未能连回」。
      if (choice.mode == ResumeMode.offline) {
        await openOffline();
        return;
      }

      // 联网重连：8s 进度由 CloudRoomClient/CloudRoomHostLink 内部超时保证。
      Future<ResumeRunResult> runOnce() => service.run(
            save,
            cred,
            choice.mode,
            confirmCloudNewer: (int cloudSeq, int localSeq) =>
                showCloudNewerDialog(
              context,
              cloudSeq: cloudSeq,
              localSeq: localSeq,
            ),
          );
      ResumeRunResult result = await runOnce();
      // F2–F7：失败 → 弹「连回失败」（重试 / 仅本机离线副本 / 取消）。
      while (!result.ok) {
        if (!mounted) return;
        final ResumeFailAction action = await showResumeFailedDialog(
          context,
          code: code,
          reason: result.errorText,
        );
        if (!mounted) return;
        if (action == ResumeFailAction.cancel) {
          setState(() => _busy = false);
          return;
        }
        if (action == ResumeFailAction.offline) {
          await openOffline();
          return;
        }
        setState(() => _busy = true);
        result = await runOnce(); // retry
      }
      if (!mounted) return;
      if (result.offline) {
        await openOffline();
        return;
      }
      setState(() => _busy = false);
      // 成功：按编排结果分派到既有 _openRoom / _openCloud / _openRemote。
      if (result.boot != null) {
        await _openRoom(result.boot!, banner: result.banner);
      } else if (result.cloudJoin != null) {
        await _openCloud(result.cloudJoin!, banner: result.banner);
      } else if (result.lanJoin != null && result.lanJoin!.session != null) {
        await _openRemote(result.lanJoin!.session!, banner: result.banner);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '载入失败：$e';
      });
    }
  }

  // ----------------------------------------------------------
  // 进房间
  // ----------------------------------------------------------

  Future<void> _openRoom(RoomBoot boot, {required String banner}) async {
    await _openShell(
      session: boot.session,
      local: boot.local,
      controller: boot.controller,
      onClose: boot.dispose,
      banner: banner,
    );
  }

  /// 进局域网房间（P6）：自己装配 local / controller，退房时断连接。
  ///
  /// ⚠️ 这里的 `local` 必须是**新的一份**：本机建房那套 RoomUiLocal 里有
  ///    工具模式、折叠态、手绘分页等大量本地态，两个房间共用一个会串味。
  Future<void> _openRemote(RemoteSession remote, {required String banner}) async {
    final RoomUiLocal local = RoomUiLocal();
    final RoomController controller = RoomController(
      session: remote,
      local: local,
      notes: RoomNotesStore(MemoryNotesStorage()),
      // ★ 2.37.0 / Q1：此前远端玩家控制器没接存档后端，RoomSaveSyncer
      //   onShared 第一步就 no_store → 玩家手机上一份收档都落不下来。
      saveStore: _store,
      cardSink: CharacterRepoRoomCardSink(RepoScope.read(context)),
    );
    await _openShell(
      session: remote,
      local: local,
      controller: controller,
      onClose: () {
        local.dispose();
        remote.dispose();
        // ★ B4：离开时必须真的关掉连接。
        //   `RemoteSession.dispose()` 只摘回调（它可能被多处共享），
        //   不关 socket 的话：被踢 / 主动退房后那条连接还挂在服务端，
        //   玩家再点「加入」会开第二条连接，而老连接仍占着旧座 ——
        //   服务端就以「同座重复连接」把他刚进来的新连接顶掉。
        remote.closeConnection();
      },
      banner: banner,
    );
  }

  /// 进公网房间（B5）：与 [_openRemote] 同形，只是会话是 CloudRemoteSession。
  Future<void> _openCloud(CloudJoinOutcome out, {required String banner}) async {
    final CloudRemoteSession session = out.session!;
    final RoomUiLocal local = RoomUiLocal();
    final RoomController controller = RoomController(
      session: session,
      local: local,
      notes: RoomNotesStore(MemoryNotesStorage()),
      // ★ 2.37.0 / Q1：云端玩家与局域网玩家同一口径，必须接本机存档后端。
      saveStore: _store,
      cardSink: CharacterRepoRoomCardSink(RepoScope.read(context)),
    );
    await _openShell(
      session: session,
      local: local,
      controller: controller,
      onClose: () {
        local.dispose();
        session.dispose();
        session.closeConnection();
      },
      banner: banner,
    );
  }

  /// 进房间的唯一出口：本机 / 远端都走这里，只是装配来源不同。
  Future<void> _openShell({
    required RoomSession session,
    required RoomUiLocal local,
    required RoomController controller,
    required VoidCallback onClose,
    required String banner,
  }) async {
    final String? why = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext _) => _RoomShell(
          session: session,
          local: local,
          controller: controller,
          onClose: onClose,
          banner: banner,
        ),
      ),
    );
    if (!mounted) return;
    // 从房间里出来：存档可能刚被写过（存档槽弹层），列表要跟上；
    // 若是「结团 / 关房 / 被踢」导致的离开，把原因留在入口页（不弹模态）。
    setState(() {
      _reloadSaves();
      if (why != null && why.isNotEmpty) _notice = why;
    });
  }

  // ----------------------------------------------------------
  // 画
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('骰境TRPG · 房间'),
        // ★ 不用透明：这个 AppBar 在 `AppBackground` **外面**，透明时透出的是
        //   Scaffold 之外的东西 —— 亮色皮肤下就是一条黑栏，而且要等背景图
        //   解码完才「变好」，表现为延迟闪黑。直接用皮肤底色，同步、跟肤。
        backgroundColor: Palette.bg,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            key: RoomEntryKeys.root,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: <Widget>[
              // 房间入口头图（D1）。
              //
              // ⚠️ 历史坑：这里曾用 **100px** 的装饰条，把「续玩」区推出了
              //    首屏 —— ListView 懒加载不再构建它，真机上表现为「续玩
              //    列表消失」。所以这次只给 **48px**：横条构图裁上下仍能
              //    看出是酒馆长桌，而 48px 不到原来的一半，不会把任何功能
              //    区顶出首屏。
              //    要更大请改用折叠式 SliverAppBar，别直接加大这里的数字。
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ArtImage(
                    Art.roomEntryHeaderFor(Palette.brightness),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_busy) const LinearProgressIndicator(key: RoomEntryKeys.busy, minHeight: 2),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _notice!,
                    key: RoomEntryKeys.notice,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.secondary),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              _createSection(theme),
              const SizedBox(height: RoomTheme.panelGap),
              _joinSection(theme),
              const SizedBox(height: RoomTheme.panelGap),
              _resumeSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createSection(ThemeData theme) {
    return SectionBox(
      title: '① 创建房间（你是 KP）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: RoomEntryKeys.createName,
            controller: _createName,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '房间名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: RoomEntryKeys.createNick,
            controller: _createNick,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '你的昵称（KP 名）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text('规则：克苏鲁的呼唤 7 版 · 模式：探索',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          // ★ B5：两条路分开摆 —— 局域网（同 WiFi）与公网（云端中继）。
          //   用户原话要的是「创建房间给局域网 / 公网两条路」。
          Text(
            '联网方式',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.secondary),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              RoomTap(
                key: RoomEntryKeys.createSubmit,
                icon: Icons.meeting_room_outlined,
                label: '开局域网房间',
                hint: '局域网房间：同 WiFi 的同伴可搜到并加入',
                minSize: const Size(148, 40),
                onTap: _create,
              ),
              if (_cloudBase.isNotEmpty)
                RoomTap(
                  key: RoomEntryKeys.createSubmitCloud,
                  icon: Icons.public,
                  label: '开公网房间',
                  hint: '公网房间：走云端中继（$_cloudBase），不同网络的同伴也能加入',
                  minSize: const Size(132, 40),
                  onTap: _createCloud,
                )
              else
                RoomTap(
                  key: RoomEntryKeys.cloudSetupHint,
                  icon: Icons.settings_ethernet,
                  label: '去设置公网地址',
                  hint: '公网开房要先在设置里填中继地址（例如 https://relay.example.com/room）',
                  minSize: const Size(148, 40),
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                ),
            ],
          ),
          if (_cloudBase.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                // ★ 如实说明：没配地址就没有公网入口，不给假按钮。
                '公网开房需要先在「设置 → 跑团房间服务地址」填一个中继地址；'
                '没配之前这里只有局域网。',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '公网中继：$_cloudBase（云端只转发，不保存任何游戏数据）',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_created != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text('房间号：', style: theme.textTheme.bodySmall),
                Text(
                  _created!,
                  key: RoomEntryKeys.createdCode,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                RoomTap(
                  key: RoomEntryKeys.createdCopy,
                  icon: Icons.copy_all_outlined,
                  hint: '复制房间号',
                  minSize: const Size(44, 32),
                  onTap: () => _copy(_created ?? ''),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _joinSection(ThemeData theme) {
    return SectionBox(
      title: '② 加入房间',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: RoomEntryKeys.joinCode,
                  controller: _joinCode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '房间号（6 位）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: RoomEntryKeys.joinNick,
                  controller: _joinNick,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '昵称',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            key: RoomEntryKeys.joinBase,
            controller: _joinBase,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '服务地址（可空，如 192.168.1.7:4211）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          // ★ 不许骗人：这句话必须一直在，而不是失败时才出现。
          Text(
            kJoinPreviewBanner,
            key: RoomEntryKeys.joinHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.secondary),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                RoomTap(
                  key: RoomEntryKeys.joinSubmit,
                  icon: Icons.login,
                  label: '加入',
                  hint: '找不到局域网房时退成本机预览',
                  minSize: const Size(112, 40),
                  onTap: _join,
                ),
                // ★ 不必挨个问房号：同一 WiFi 下正在招募的房直接列出来。
                RoomTap(
                  key: RoomEntryKeys.nearby,
                  icon: Icons.wifi_find,
                  label: '找附近的房间',
                  hint: '扫描同一 WiFi 下正在招募的房间',
                  minSize: const Size(148, 40),
                  onTap: _openNearby,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumeSection(ThemeData theme) {
    return SectionBox(
      title: '③ 续玩本机存档（${_saves.length}）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            // ★ 按后端能力说真话：内存后端会丢，文件后端不会。
            savePersistHintOf(_store),
            key: RoomEntryKeys.resumeHint,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          if (_saves.isEmpty)
            Text(
              '还没有本机存档',
              key: RoomEntryKeys.resumeEmpty,
              style: theme.textTheme.bodySmall,
            )
          else
            for (final key in _saves) _saveRow(theme, key),
        ],
      ),
    );
  }

  Widget _saveRow(ThemeData theme, String key) {
    final save = _store.get(key);
    final meta = (save?['meta'] is Map) ? (save!['meta']! as Map) : const <String, Object?>{};
    final name = '${meta['name'] ?? ''}'.trim();
    final code = '${meta['code'] ?? ''}'.trim();
    final status = '${meta['status'] ?? ''}'.trim();
    // ★ P15：所有列表存档都带时间戳（读不出 savedAt 的显示「—」，排最后）。
    final savedAt = jsParseInt(save?['savedAt']) ?? 0;
    final removable = _store is RoomSaveStoreMutable;
    return Padding(
      key: RoomEntryKeys.resumeRow(key),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name.isEmpty ? key : name,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$key${code.isEmpty || code == key ? '' : ' · $code'}'
                  '${status.isEmpty ? '' : ' · $status'}'
                  ' · ${saveTimeText(savedAt)}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          RoomTap(
            key: RoomEntryKeys.resumeLoad(key),
            icon: Icons.play_circle_outline,
            label: '续玩',
            hint: '载入这条本机存档',
            minSize: const Size(84, 40),
            onTap: () => _resume(key),
          ),
          // ★ P15：非 Mutable 后端连按钮都不渲染（不做禁用态，免得像个坏按钮）。
          if (removable)
            ConfirmTwice(
              key: RoomEntryKeys.resumeRemove(key),
              label: '删除',
              // 删的是本机存档槽，不动当前房间；两段式确认，不弹窗。
              confirmLabel: '再点一次',
              onConfirmed: () => _removeSave(key),
            ),
        ],
      ),
    );
  }

  /// 删除续玩列表里的一行。
  ///
  /// ★ 列表是**按房号折叠**的（见 `_reloadSaves`）：同一房号可能同时存在
  ///   房号键、`auto/<code>/*`、`share/<code>/latest` 三条槽。只删当前行
  ///   对应的键，下次刷新另外两条会顶上来「复活」。所以这里删**同房号的
  ///   全部槽**；读不出房号的自定义槽只删自己。
  void _removeSave(String key) {
    final store = _store;
    if (store is! RoomSaveStoreMutable) return;
    final save = store.get(key);
    final meta = (save?['meta'] is Map) ? (save!['meta']! as Map) : const <String, Object?>{};
    final code = '${meta['code'] ?? ''}'.trim().toUpperCase();
    final victims = <String>[];
    if (code.isEmpty) {
      victims.add(key);
    } else {
      for (final other in store.list()) {
        final s = store.get(other);
        final m = (s?['meta'] is Map) ? (s!['meta']! as Map) : const <String, Object?>{};
        if ('${m['code'] ?? ''}'.trim().toUpperCase() == code) victims.add(other);
      }
      // 兜底：当前行 meta 在前面读得到、这里读不到时也要删掉它自己。
      if (!victims.contains(key)) victims.add(key);
    }
    for (final victim in victims) {
      store.remove(victim);
    }
    setState(_reloadSaves);
  }

  Future<void> _copy(String text) async {
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      setState(() => _error = null);
    } catch (_) {
      // 剪贴板不可用（部分桌面环境）：不影响其余功能，静默即可。
    }
  }
}

/// 房间壳体：`RoomScope` 必须在页面（大厅 / 游戏页）**之上**，块才能取到作用域。
///
/// 壳体只负责三件事：作用域、顶部横幅、阶段路由（[_RoomStageSwitch]）。
class _RoomShell extends StatefulWidget {
  const _RoomShell({
    required this.session,
    required this.local,
    required this.controller,
    required this.onClose,
    required this.banner,
  });

  /// 抽象会话：本机环境 / 局域网远端都是它（P6 的关键）。
  final RoomSession session;
  final RoomUiLocal local;
  final RoomController controller;

  /// 退房时的清理（本机环境会连存档一起收；远端会断连接）。
  final VoidCallback onClose;

  /// 顶部一次性横幅（加入预览 / 载入存档 / 迁移提示）。
  final String banner;

  @override
  State<_RoomShell> createState() => _RoomShellState();
}

class _RoomShellState extends State<_RoomShell> {
  /// 已经判定的离开原因（none = 还在房里）。
  RoomExit _exit = RoomExit.none;

  /// 只允许离开一次（会话会持续发通知，不能反复 pop）。
  bool _leaving = false;

  /// 进房那一刻的离开判定（见 [initState] 的 P13 注释）。
  ///
  /// 续玩已结束的存档时它是 `closed` / `ended`，这类「进房即终态」**不算**
  /// 离开信号；只有进房后原因发生变化（例如真的被踢）才 pop 回入口页。
  RoomExitKind _entryExitKind = RoomExitKind.none;

  /// 本壳体自己的路由（用于 popUntil 把中间的弹层一起收掉）。
  ModalRoute<Object?>? _route;

  /// C1 / C2：角色卡保存器（本机动作，不发包）。
  late final RoomCardSaver _saver = RoomCardSaver(
    controller: widget.controller,
    session: widget.session,
  );

  /// ★ P19：存档自动保存 + 全员分发/落盘（KP 与玩家各管一头）。
  ///   KP：每回合 / 每 10 分钟 / 结束房间 / 结团 / 玩家加入 → 自动存档
  ///   并把快照广播出去；玩家：收到快照 → 写本地存档（时间戳去重）+
  ///   把自己的卡面数值写回「角色卡」。
  late final RoomSaveSyncer _syncer = RoomSaveSyncer(
    controller: widget.controller,
    session: widget.session,
  );

  @override
  void initState() {
    super.initState();
    // ★ P13：**进房基线**。续玩一个已结束（CLOSED / ended）的存档时，会话
    //   状态在进房那一刻就已经是终态；`_onSessionChanged` 会把它当成「刚刚
    //   关房」，于是刚 push 就被 pop 回入口页 —— 横幅「已载入本机存档」
    //   根本来不及显示（KP 续玩自己结束的档必踩；玩家侧续的是活房间，不踩）。
    //   这里只记「进房那一刻的判定」，**不写 `_exit`**：`_exit` 还要给
    //   dispose 的保活/挂起判据用，不能被进房快照污染。
    _entryExitKind = roomExitOf(
      state: widget.session.state,
      seat: widget.session.seat,
      role: widget.session.role,
      kickedByHost: widget.session.kickedByHost,
    ).kind;
    widget.session.addListener(_onSessionChanged);
    // KP：起 10 分钟周期自动存档；玩家：注入快照落盘回调。
    _syncer.startTicker();
    // ★ P13：同上，把「进房即终态」记成存档触发器的基线，避免续玩 CLOSED
    //   存档时每次确认都白写一份 close 档（autoSave reason=close）。
    _syncer.primeStatusBaseline();
    // ★ 2.37.0 / Q1：延到首帧后落触发器基线（成员数 / 回合号），否则
    //   「进房后第一波玩家加入」会被 first 守卫吞掉；再补一份开局档（仅
    //   本机无该房档时），顺手把全量快照广播给已在房的玩家。
    //   必须在 post-frame：autoSave → save.share → pumpPlans 会通知 listener，
    //   在 initState 里直接跑会在 build 阶段触发重建（项目既有踩坑口径）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncer.onStateChanged());
      unawaited(_syncer.saveOnOpen());
    });
    final session = widget.session;
    if (session is LocalLoopbackSession) {
      session.onSharedSave = (Map<String, Object?> save) {
        _syncer.onShared(save);
        // 快照到了 = 状态可能变了，让 syncer 的触发器再过一遍
        _syncer.onStateChanged();
      };
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    // ★ P20 Q4 保活挂点（主理人 D-1/D-5）：
    //   仅当用户「离开房间但未关房」(_exit.shouldLeave == false，即 kind==none)
    //   **且**当前会话是云端 KP 时，才做「末次备份 + /suspend」。
    //   · closed / ended / kicked 一律不 suspend、不 backup（否则会把结团
    //     误挂起，这正是挂在 dispose 而非 RoomBoot.dispose 的原因 —— 这里
    //     拿得到 _exit.kind 信号）；
    //   · 短暂切后台（paused/hidden/inactive）不触发，只有 main.dart 的
    //     detached 观察者与此处 dispose 两处触发；崩溃兜底靠服务端 30 天 TTL。
    //   · 必须在 widget.onClose() **之前**触发：onClose → RoomBoot.dispose
    //     → CloudHostingSession.dispose → cloudLink.stop()，纯数据上下文在
    //     finalizeOnLeave 里已被取出，fire-and-forget 不依赖会话存活。
    //   · finalizeOnLeave() 只读纯数据、全链路 try/catch，绝不引用 context /
    //     BuildContext / _syncer / widget.controller。
    if (!_exit.shouldLeave && widget.session is CloudHostingSession) {
      unawaited(finalizeOnLeave());
    } else {
      // 关房 / 结团 / 玩家 / LAN：不挂起，且清掉运行时上下文避免残留
      // （D-2：这里**不清**持久化凭据 RecentRoomCredential）。
      clearActiveCloudBackup();
    }
    widget.session.removeListener(_onSessionChanged);
    _syncer.stopTicker();
    // ★ P20（需求 5 / D11）兜底停 BGM：`_onSessionChanged` 已覆盖「结团 / 关房 /
    //   被踢」这条主路径，但页面还可能因为**别的**原因被销毁（深链换路由、
    //   上层主动 pop、切视角重建）。本机 BGM 不属于房间状态，没人替我们收，
    //   漏停就会「人已经不在房间里了，音乐还在放」。
    //   `SystemMusicPort._stop` 幂等（未在播放时是安全空操作），重复调无副作用。
    musicPort.stop();
    widget.onClose();
    super.dispose();
  }

  /// 会话一变就做两件事（B3/B4 + C2）：
  ///   ① 判「房间还容不容得下我」—— 结团 / 关房 / 被踢时离开房间；
  ///   ② 回合推进后自动把当前状态写回我的角色卡（只写本机，静默）。
  void _onSessionChanged() {
    if (!mounted || _leaving) return;
    final session = widget.session;
    // C2：自动保存（幂等，同一回合只写一次；失败静默）
    _saver.onStateChanged();
    // ★ P19：自动存档 / 分发触发器（回合边界 / 成员加入 / 房间结束）
    _syncer.onStateChanged();
    final RoomExit exit = roomExitOf(
      state: session.state,
      seat: session.seat,
      role: session.role,
      kickedByHost: session.kickedByHost,
    );
    if (!exit.shouldLeave) {
      // 房间已经回到「活着」的状态（例如续玩 CLOSED 档后又点了开始游戏）：
      // 进房基线作废，之后再关房 / 结团必须能正常离开。
      _entryExitKind = RoomExitKind.none;
      return;
    }
    if (exit.kind == _exit.kind) return;
    // ★ P13：与进房时同一个原因 → 不是跳变，不算离开。
    //   续玩 CLOSED 存档会反复走到这里；不拦就会立刻 pop 回入口页。
    if (exit.kind == _entryExitKind) return;
    /* ★ P20（需求 5 / D11）：走到这里 `exit.kind ∈ {closed, ended, kicked}`
       已经是确定事实 —— 上面的 `if (!exit.shouldLeave) { … return; }` 已把
       「房间还活着」返回掉，`room_exit.dart` 也明确挂起（SUSPENDED）不算离开。
       因此这是停本机 BGM 最准的一处：
         · 必须在 `if (exit.kind == _entryExitKind) return;` **之后** ——
           续玩 CLOSED 档会反复命中那条提前 return，放在前面会误停；
         · 在 `_exit = exit;` 之前，与「跳变判定」同一跳内完成副作用；
         · 紧随的下一帧 `popUntil` 会收掉所有弹层（音乐控制台 / KP 面板），
           弹层里的播放态真源是全局 `musicPort`，所以这里停一次就够全端一致。
       `SystemMusicPort._stop` 幂等：连点两次结团 / dispose 再兜一次都安全。 */
    musicPort.stop();
    _exit = exit;
    _leaving = true;
    final String message = exit.message;
    // 不能在通知回调里直接 pop（可能在 build/布局阶段），下一帧再走。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final NavigatorState nav = Navigator.of(context);
      final ModalRoute<Object?>? mine = _route;
      if (mine != null) {
        // 先把压在上面的弹层（存档槽 / KP 面板）一起收掉
        nav.popUntil((Route<Object?> r) => r == mine || r.isFirst);
      }
      if (nav.canPop()) {
        nav.pop<String>(message);
      } else {
        // 深链直接进了房间（没有可回退的栈）：换成入口页，别留在死房间里。
        nav.pushReplacementNamed(AppRoutes.room);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              key: RoomEntryKeys.banner,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: theme.colorScheme.secondaryContainer,
              child: Text(
                widget.banner,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            Expanded(
              child: RoomScope(
                session: widget.session,
                local: widget.local,
                controller: widget.controller,
                // ★ Stack：提示浮层必须盖在内容之上，且在 RoomScope 之下
                //   （要读 local）。浮层自己有 IgnorePointer，不吃点击。
                child: const Stack(
                  children: <Widget>[
                    _RoomStageSwitch(),
                    RoomNoticeOverlay(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 阶段路由：`meta.status` 决定进大厅还是进游戏页。
///
/// ★ 这是 PRD 的正式流程：创建 / 加入 → **大厅（招募中）** → KP 点「开始游戏」
///   → `IN_GAME` → 游戏页壳体。`KeyedSubtree` 的 key 带上 `inGame`，阶段切换时
///   整棵子树被丢弃重建（与 T02 的 `pageKeyOf` 同一手法），不会残留上一阶段的
///   State（滚动位置 / 弹层 / 手绘板草稿）。
/// ★ 必须放在 `RoomScope` **之下**：它要 `RoomScope.of(context)` 订阅会话，
///   才能第一时间响应 `room.start` 的 `meta.status` 翻转。
class _RoomStageSwitch extends StatelessWidget {
  const _RoomStageSwitch();

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final inGame = isInGame(scope.session.state);
    return KeyedSubtree(
      key: ValueKey<String>('roomStage/${scope.session.role}/$inGame'),
      child: inGame ? const RoomGamePage() : RoomLobbyPage(),
    );
  }
}
