// ============================================================
// room_boot.dart — 房间的进程内装配（P5 没有传输层）
//
// 一个房间在本机由四件东西组成：
//   · `RoomHost`：权威端（KP 那台「设备」，P5 里就是本进程）；
//   · `RoomLoopbackHub`：把权威端的 `SendPlan` 直接喂给各视角的泵；
//   · `LocalLoopbackSession`：一个**视角**（KP / 玩家 / 旁观），共享同一个 hub；
//   · `RoomUiLocal` + `RoomController`：UI 本地态与该视角的唯一出站口。
//
// ★ 为什么放在 UI 层：装配要用到 `LocalLoopbackSession`（ui/room），
//   放 repo 会让 repo 反向依赖 ui。这里是房间页面的**组合根**。
// ★ 后端全是内存实现：存档槽、笔记都只在本次 App 生命周期内有效。
// ============================================================

import 'dart:convert' show jsonEncode;

import '../../domain/js_compat.dart' show JsRng, asMap, jsNum, nowRng;
import '../../domain/room_madness_coc.dart' show CocMadness;
import '../../domain/room_model_client.dart' show RoomClient;
import '../../domain/room_model_host_core.dart' show RoomHost, RoomHostOptions;
import '../../domain/room_model_save.dart' show RoomHostSave;
import '../../domain/room_ports.dart' show RoomCardSink, RoomSaveStore;
import '../../domain/room_rules.dart' show CocRules;
import '../../domain/room_types.dart' show RoomRole, kHostSeat;
import '../../repo/room_notes_store.dart' show MemoryNotesStorage, RoomNotesStore;
import '../../repo/room_save_store.dart'
    show InMemoryRoomSaveStore, RoomSaveStoreMutable;
import '../../repo/recent_room_credential.dart' show saveRecentCredential;
import 'room_controller.dart';
import 'room_net_factory.dart' show RoomNetFactory;
import 'room_session_local.dart';
import 'room_ui_local.dart';
import 'room_text.dart';
import '../../net/cloud_room.dart'
    show
        CloudRoomHostLink,
        CloudSocket,
        CloudHostStart,
        cloudRoomCode,
        ensureCloudDeviceId,
        normalizeCloudBase;
import '../../net/cloud_room_backup.dart'
    show CloudBackupContext, armCloudBackup, clearActiveCloudBackup;
import '../../net/room_frame.dart' show kRoomDiscoverPort, kRoomServicePort;
import 'room_session_cloud.dart' show CloudHostingSession;

// ------------------------------------------------------------
// 房间号
// ------------------------------------------------------------

/// 房间号字母表：去掉容易看错的 `0 O 1 I`，剩 32 个字符。
const String kRoomCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// 房间号长度（PRD：6 位）。
const int kRoomCodeLength = 6;

/// 生成一个 6 位房间号（大写字母 + 数字）。
///
/// [rng] 可注入：测试用固定源钉死结果，生产默认全局随机源。
String newRoomCode({JsRng? rng}) {
  final r = rng ?? nowRng;
  final out = StringBuffer();
  for (var i = 0; i < kRoomCodeLength; i++) {
    final x = (r() * kRoomCodeAlphabet.length).floor();
    final at = x < 0 ? 0 : (x >= kRoomCodeAlphabet.length ? kRoomCodeAlphabet.length - 1 : x);
    out.write(kRoomCodeAlphabet[at]);
  }
  return out.toString();
}

/// 房间号是否合法：6 位大写字母 / 数字（小写自动按大写算）。
bool isValidRoomCode(String raw) =>
    RegExp('^[A-Z0-9]{$kRoomCodeLength}\$').hasMatch(raw.trim().toUpperCase());

/// 规范化房间号（去空格 + 转大写）。
String normalizeRoomCode(String raw) => raw.trim().toUpperCase();

// ------------------------------------------------------------
// 本机存档槽
// ------------------------------------------------------------

/// 本机存档槽的唯一实例。
///
/// 续玩列表必须与「保存」**共用同一份**，所以进程内只留这一个（每个房间各建
/// 一个的话，关掉房间续玩列表就空了）。测试用 `setUp(roomSaveSlots.clear)` 隔离。
///
/// ★ 类型是**接口**（`RoomSaveStoreMutable`）而不是具体类：
///   生产在 `main()` 里会把它换成 `FileRoomSaveStore`（落盘持久化），
///   拿不到应用目录时（或测试）保持内存实现。两者行为对调用方一致。
/// ★ 用 repo 层的实现：`put/get/list` 深拷贝快照，`remove/clear` 是扩展能力。
RoomSaveStoreMutable roomSaveSlots = InMemoryRoomSaveStore();

/// 启动时替换全局存档后端（见 `main.dart`）。
///
/// 只允许在 `runApp` 之前调一次；之后所有房间共用同一个实例 ——
/// 各建一个的话，关掉房间续玩列表就空了。
void installRoomSaveStore(RoomSaveStoreMutable store) {
  roomSaveSlots = store;
}

// ------------------------------------------------------------
// 装配结果
// ------------------------------------------------------------

/// 一个可渲染的房间视角：壳体页拿它就够（其余都在里面）。
class RoomBoot {
  RoomBoot({
    required this.host,
    required this.hub,
    required this.session,
    required this.local,
    required this.controller,
    required this.saveStore,
  });

  final RoomHost host;
  final RoomLoopbackHub hub;
  final LocalLoopbackSession session;
  final RoomUiLocal local;
  final RoomController controller;
  final RoomSaveStore saveStore;

  bool _closed = false;

  /// 离开房间时释放：本地态 + 会话。
  ///
  /// ★ 会话也要 dispose：P6 建房的 session 是 `HostingLocalSession`，
  ///   它持有局域网服务 —— 只清 local 会留下幽灵房（别人一直能搜到）。
  /// ★ 幂等：`State.dispose()` 与路由 pop 可能各调一次。
  void dispose() {
    if (_closed) return;
    _closed = true;
    local.dispose();
    session.dispose();
  }
}

/// 装配一个本机房间并返回指定视角。
///
/// · `role == kp`（默认）：你就是 KP，直接拿权威态；
/// · `role == player`：你是「加入者」——P5 没有网络，所以在本机建一份
///   同房间号的**预览会话**（真的会进花名册、真的能收事件，只是没有远端）。
Future<RoomBoot> bootLocalRoom({
  required String code,
  required String name,
  required String nickname,
  String role = RoomRole.kp,
  String seat = kHostSeat,
  RoomSaveStore? saveStore,
  RoomCardSink? cardSink,
}) async {
  final store = saveStore ?? roomSaveSlots;
  final host = RoomHost(RoomHostOptions(
    meta: <String, Object?>{
      'code': code,
      'name': name,
      'kpName': nickname,
      'maxPlayers': 6,
      // 新建房间：大成功默认上限 5（01-05 都算大成功）。
      // ⚠️ 只在这里显式给值：`emptyRoomState` 的缺省 1 是旧版逐字节契约
      //    （test/fixtures/room_actions.json 等 259 条用例都按 1 固定），不能动。
      'critThreshold': 5,
      'allowSpectate': true,
    },
    // 规则用生产实现；疯狂表经本文件的端口适配（P4 只留了端口）。
    rules: const CocRules(),
    madness: const CocMadness(),
    saveStore: store,
  ));
  final hub = RoomLoopbackHub(host);

  // 权威侧把手：KP 视角永远存在（本机自带一个「KP 那台设备」）。
  final hostSide = LocalLoopbackSession(
    host: host,
    seat: kHostSeat,
    role: RoomRole.kp,
    hub: hub,
  );

  LocalLoopbackSession session = hostSide;
  if (role != RoomRole.kp) {
    hostSide.attach(seat, RoomClient(seat: seat, role: role));
    final attached = host.attachPeer(<String, Object?>{
      'seat': seat,
      'role': role,
      'nickname': nickname,
      'at': 1,
    });
    if (attached.out.isNotEmpty) hostSide.pumpPlans(attached.out);
    session = hostSide.viewFor(seat, role);
    await session.pullSync();
  }

  final local = RoomUiLocal();
  final controller = RoomController(
    session: session,
    local: local,
    notes: RoomNotesStore(MemoryNotesStorage()),
    saveStore: store,
    // C1/C2：本机角色卡写回端口（K11 唯一落盘路径在 repo 层）。
    cardSink: cardSink,
  );
  return RoomBoot(
    host: host,
    hub: hub,
    session: session,
    local: local,
    controller: controller,
    saveStore: store,
  );
}

/// 建房（P6）：本机会话 + 局域网服务 + 广播。
///
/// 与 [bootLocalRoom] 的**唯一区别**：session 换成 `HostingLocalSession`，
/// 它在每次 `pumpPlans` 时把同一份计划多投一遍到网络。
/// 其余（RoomHost 装配、存档、notes）完全一样 —— 不要在这里另造一套。
///
/// ★ 服务起不来**不算失败**（端口被占 / 没连 WiFi）：单机照常开团，
///   只是调用方要在横幅里如实说「只有你自己能进」。
Future<RoomBoot> bootHostedRoom({
  required String code,
  required String name,
  required String nickname,
  RoomSaveStore? saveStore,
  RoomCardSink? cardSink,
  int servicePort = kRoomServicePort,
  int discoverPort = kRoomDiscoverPort,
}) async {
  final store = saveStore ?? roomSaveSlots;
  final host = RoomHost(RoomHostOptions(
    meta: <String, Object?>{
      'code': code,
      'name': name,
      'kpName': nickname,
      'maxPlayers': 6,
      'critThreshold': 5,
      'allowSpectate': true,
    },
    rules: const CocRules(),
    madness: const CocMadness(),
    saveStore: store,
  ));
  final hub = RoomLoopbackHub(host);

  final out = await RoomNetFactory.host(
    host: host,
    hub: hub,
    servicePort: servicePort,
    discoverPort: discoverPort,
  );

  final local = RoomUiLocal();
  final controller = RoomController(
    session: out.session,
    local: local,
    notes: RoomNotesStore(MemoryNotesStorage()),
    saveStore: store,
    cardSink: cardSink,
  );
  // ★ P20 M7：局域网开房成功 → 写凭据（LAN 房号保持大写归一不变）。
  //   base 取 HostingLocalSession.lanBase；hostToken 恒 ''；失败静默。
  final String did = ensureCloudDeviceId();
  saveRecentCredential(
    roomCode: normalizeRoomCode(code),
    // HostingLocalSession.lanBase 是 non-null String（server.base）；不加 ?? 兜底。
    base: out.session.lanBase,
    hostToken: '',
    deviceId: did,
    role: RoomRole.kp,
    seat: kHostSeat,
    mode: 'lan',
    lastOkAt: DateTime.now().millisecondsSinceEpoch,
  );
  // LAN 不做云端备份：清掉可能残留的云端 KP 上下文（避免误 suspend）。
  clearActiveCloudBackup();
  return RoomBoot(
    host: host,
    hub: hub,
    session: out.session,
    local: local,
    controller: controller,
    saveStore: store,
  );
}

// ------------------------------------------------------------
// 公网房间（B5）
// ------------------------------------------------------------

/// 公网开房 / 续玩结果：成功时给出可渲染的房间壳，失败时给一句人话。
class CloudBootResult {
  const CloudBootResult({
    this.boot,
    this.code = '',
    // ★ P20 M7：房主令牌（关房 / 续玩 / 云端备份要用）。不落日志、不进存档。
    this.hostToken = '',
    this.error = '',
  });

  final RoomBoot? boot;
  final String code;
  final String hostToken;
  final String error;

  bool get ok => boot != null;
}

/// 建房（公网中继版）：登记 → 建权威端 → 连中继 → 返回同形的 [RoomBoot]。
///
/// 与 [bootHostedRoom] 的差别只有一处：**转发者**从中继换成云端服务，
/// 权威端（RoomHost / 规则 / 存档）一个字节都没变 —— 这正是「局域网与公网
/// 共用同一套房间协议」的落地方式。
///
/// ⚠️ 服务端（云端 `/room`）已部署且只做「鉴权 + 转发 + 目录」，不持有游戏状态；
///    应用层载荷一律是 `SendPlan.toJson()`（红线：绝不用 LogRecord.toWireJson）。
Future<CloudBootResult> bootCloudRoom({
  required String base,
  required String name,
  required String nickname,
  RoomSaveStore? saveStore,
  RoomCardSink? cardSink,
  CloudSocket? socket,
  int maxPlayers = 6,
}) async {
  final store = saveStore ?? roomSaveSlots;
  // ① 先在中继上登记，拿到房间号（房间号是中继分配的）
  final CloudHostStart reg = await CloudRoomHostLink.registerRoom(
    base: base,
    name: name,
    kpName: nickname,
    maxPlayers: maxPlayers,
  );
  if (!reg.ok) {
    return CloudBootResult(error: reg.error.isEmpty ? '中继登记失败' : reg.error);
  }
  // ② 用中继给的房间号建权威端（meta 里从此就是真房号，不需要事后改）
  final host = RoomHost(RoomHostOptions(
    meta: <String, Object?>{
      'code': reg.code,
      'name': name,
      'kpName': nickname,
      'maxPlayers': maxPlayers,
      'critThreshold': 5,
      'allowSpectate': true,
    },
    rules: const CocRules(),
    madness: const CocMadness(),
    saveStore: store,
  ));
  final hub = RoomLoopbackHub(host);
  final link = CloudRoomHostLink(
    base: base,
    host: host,
    code: reg.code,
    hostToken: reg.token,
    socket: socket,
  );
  final session = CloudHostingSession(
    host: host,
    seat: kHostSeat,
    role: RoomRole.kp,
    cloudLink: link,
    hub: hub,
  );
  // ③ 连实时通道（失败就如实报错，不偷偷降级成局域网）
  final CloudHostStart started = await link.start(name: name, kpName: nickname);
  if (!started.ok) {
    await link.stop();
    session.dispose();
    return CloudBootResult(
      code: reg.code,
      error: started.error.isEmpty ? '连不上中继' : started.error,
    );
  }
  final local = RoomUiLocal();
  final controller = RoomController(
    session: session,
    local: local,
    notes: RoomNotesStore(MemoryNotesStorage()),
    saveStore: store,
    cardSink: cardSink,
  );
  // ★ P20 M7：公网开房成功 → 写凭据（云端房号小写规范化）。
  //   reg.code 来自服务端 CODE_ALPHA（已小写），此处再 cloudRoomCode 兜底幂等。
  final String normalizedCode = cloudRoomCode(reg.code);
  final String did = ensureCloudDeviceId();
  final String cleanBase = normalizeCloudBase(base);
  saveRecentCredential(
    roomCode: normalizedCode,
    base: cleanBase,
    hostToken: reg.token,
    deviceId: did,
    role: RoomRole.kp,
    seat: kHostSeat,
    mode: 'cloud',
    lastOkAt: DateTime.now().millisecondsSinceEpoch,
  );
  // ★ P20 B5/Q4：挂载云端 KP 纯数据上下文（供 cloudBackupSink 与
  //   finalizeOnLeave 使用）。开局档（20 键）此刻就算好缓存：即便之后
  //   一次 autoSave 都没发生，末次保活也有一份合法全量档可上传。
  //   seq 取 save()['seq']（RoomHost.log.seq，跨重启单调，§8.2）。
  final Map<String, Object?> openingSave = host.save();
  armCloudBackup(CloudBackupContext(
    base: cleanBase,
    code: normalizedCode,
    hostToken: reg.token,
    deviceId: did,
    seq: jsNum(openingSave['seq']),
    payload: jsonEncode(openingSave),
  ));
  return CloudBootResult(
    code: reg.code,
    hostToken: reg.token,
    boot: RoomBoot(
      host: host,
      hub: hub,
      session: session,
      local: local,
      controller: controller,
      saveStore: store,
    ),
  );
}

/// ★ P16 P-1(b) ①：从存档显式恢复本机视角（role / seat）。
///
/// 存档是 `host.save()` 的 20 键权威快照，标准 meta 不带视角标记 —— 此时
/// 如实回退 KP / host（权威存档本来就是 KP 视角，且 `LocalLoopbackSession
/// .importSave` 仅在 role==kp 时真的 adoptSave，是续玩能灌进存档的前提）。
/// 若存档 / 未来版本在 meta 里带了 role / seat / viewerSeat，或 members
/// 里标了 self，则优先按它恢复，为「原玩家续玩看到自己的卡」留落点。
/// ⚠️ 恢复出非 KP 视角时，进度灌回依赖联网重连（见交付报告 §P-1b 阻塞）。
({String role, String seat}) resumeViewFromSave(Map<String, Object?> save) {
  final Map meta = save['meta'] is Map
      ? save['meta']! as Map
      : const <String, Object?>{};
  String role = roomText(meta['role']);
  String seat = roomText(meta['seat']);
  if (seat.isEmpty) seat = roomText(meta['viewerSeat']);
  if (role != RoomRole.kp &&
      role != RoomRole.player &&
      role != RoomRole.spectator) {
    role = '';
  }
  final List members = save['members'] is List
      ? save['members']! as List
      : const <Object?>[];
  if (role.isEmpty || seat.isEmpty) {
    for (final Object? mRaw in members) {
      final Map m = mRaw is Map ? mRaw : const <String, Object?>{};
      if (m['self'] != true) continue;
      if (role.isEmpty) {
        final String r = roomText(m['role']);
        if (r == RoomRole.kp ||
            r == RoomRole.player ||
            r == RoomRole.spectator) {
          role = r;
        }
      }
      if (seat.isEmpty) seat = roomText(m['seat']);
      break;
    }
  }
  if (role.isEmpty) role = RoomRole.kp;
  if (seat.isEmpty) seat = role == RoomRole.kp ? kHostSeat : 'p1';
  return (role: role, seat: seat);
}

/// 续玩：装配一个空房间后把存档灌进去（K4 顺序由 `openSave` 保证）。
/// 返回 `(boot, 迁移条数)`；迁移条数 > 0 时调用方负责给一次性提示。
Future<(RoomBoot, int)> resumeLocalRoom(
  Map<String, Object?> save, {
  RoomSaveStore? saveStore,
  RoomCardSink? cardSink,
}) async {
  final meta = save['meta'] is Map ? (save['meta']! as Map) : const <String, Object?>{};
  final code = roomText(meta['code']);
  final name = roomText(meta['name']);
  final kpName = roomText(meta['kpName']);
  // ★ P16 P-1(b) ①：显式把从存档恢复的 role / seat 传给 bootLocalRoom，
  //   别再依赖默认的 role=kp / seat=host。
  final view = resumeViewFromSave(save);
  final boot = await bootLocalRoom(
    code: code.isEmpty ? 'RESUME' : code,
    name: name,
    nickname: kpName,
    role: view.role,
    seat: view.seat,
    saveStore: saveStore,
    cardSink: cardSink,
  );
  final result = await boot.controller.openSave(save);
  // `adoptSave` 会把存档里的 meta（房间号 / 房名 / KP 名）整体恢复，
  // 所以上面那份占位 meta 只是「载入前的空壳」，不需要事后改名。
  return (boot, result.migrated);
}

// ------------------------------------------------------------
// P20 续玩装配（M7）：同原房号 + 原身份，禁止 registerRoom / newRoomCode
// ------------------------------------------------------------

/// ★ P20：KP **公网续玩**（设计 §5.1）。
///
/// 与 [bootCloudRoom] 的唯一区别：**绝不**调 `POST /api/rooms` /
/// `registerRoom()` / `newRoomCode()` —— 房号与 hostToken 都是凭据里的原值。
/// 流程：先由 [RoomResumeService] 调 `POST /resume` 把 SUSPENDED/IN_GAME
/// 复活成 RECRUITING，再用「原 code + 原 hostToken」构造
/// [CloudRoomHostLink]，`start()` 因 code/hostToken 非空而**跳过登记**，
/// 直接连 WS `t=hostToken`（服务端据此判 role=kp）。
///
/// 返回的 [RoomBoot] 已含可渲染会话；云端 seq 比对 / `openSave` 由编排层
/// [RoomResumeService] 完成（K3/K4/K5）。
Future<CloudBootResult> resumeCloudRoom({
  required Map<String, Object?> save,
  required String base,
  required String code,
  required String hostToken,
  required String deviceId,
  RoomSaveStore? saveStore,
  RoomCardSink? cardSink,
  CloudSocket? socket,
}) async {
  final store = saveStore ?? roomSaveSlots;
  // 云端房号一律小写规范化（服务端正则 [a-z0-9]{4,12}）；LAN 的大写原号
  // 绝不混用（§8.1）。
  final String normalizedCode = cloudRoomCode(code);
  final String cleanBase = normalizeCloudBase(base);
  // meta 从存档恢复（含原房号 / 房名 / KP 名），但把 code 换成规范化值，
  // 保证 RoomHost.meta.code 与 WS/HTTP 路径的 code 是同一个值。
  final Map<String, Object?> meta = <String, Object?>{...asMap(save['meta'])};
  meta['code'] = normalizedCode;
  final host = RoomHost(RoomHostOptions(
    meta: meta,
    rules: const CocRules(),
    madness: const CocMadness(),
    saveStore: store,
  ));
  final hub = RoomLoopbackHub(host);
  final link = CloudRoomHostLink(
    base: cleanBase,
    host: host,
    code: normalizedCode,
    hostToken: hostToken,
    deviceId: deviceId,
    socket: socket,
  );
  final session = CloudHostingSession(
    host: host,
    seat: kHostSeat,
    role: RoomRole.kp,
    cloudLink: link,
    hub: hub,
  );
  final CloudHostStart started = await link.start(
    name: roomText(meta['name']),
    kpName: roomText(meta['kpName']),
  );
  if (!started.ok) {
    await link.stop();
    session.dispose();
    return CloudBootResult(
      code: normalizedCode,
      hostToken: hostToken,
      error: started.error.isEmpty ? '连不上中继' : started.error,
    );
  }
  final local = RoomUiLocal();
  final controller = RoomController(
    session: session,
    local: local,
    notes: RoomNotesStore(MemoryNotesStorage()),
    saveStore: store,
    cardSink: cardSink,
  );
  // ★ 续玩成功：刷新凭据（mode=cloud / 原 hostToken / 原 deviceId）。
  saveRecentCredential(
    roomCode: normalizedCode,
    base: cleanBase,
    hostToken: hostToken,
    deviceId: deviceId,
    role: RoomRole.kp,
    seat: kHostSeat,
    mode: 'cloud',
    lastOkAt: DateTime.now().millisecondsSinceEpoch,
  );
  // ★ 重新挂载云端 KP 纯数据上下文（开局档 = 本机存档的 20 键序列化）。
  final Map<String, Object?> openingSave = host.save();
  armCloudBackup(CloudBackupContext(
    base: cleanBase,
    code: normalizedCode,
    hostToken: hostToken,
    deviceId: deviceId,
    seq: jsNum(openingSave['seq']),
    payload: jsonEncode(openingSave),
  ));
  return CloudBootResult(
    code: normalizedCode,
    hostToken: hostToken,
    boot: RoomBoot(
      host: host,
      hub: hub,
      session: session,
      local: local,
      controller: controller,
      saveStore: store,
    ),
  );
}

/// ★ P20：KP **局域网续玩**（设计 §5.3）。
///
/// 用存档 `meta.code` 的**原号**（`normalizeRoomCode` 大写归一不变）重开
/// LAN 服务，`openSave` 灌回进度 —— `adoptSave` 会把存档 `members[].cid`
/// 原样恢复进花名册，玩家带原 cid 加入时 `reuseSeat` 幂等复用旧座。
/// 绝不产生新房号、绝不登记公网房间。
Future<RoomBoot> resumeLanHostedRoom(
  Map<String, Object?> save, {
  RoomSaveStore? saveStore,
  RoomCardSink? cardSink,
}) async {
  final Map<String, Object?> meta = asMap(save['meta']);
  final String code = normalizeRoomCode(roomText(meta['code']));
  final boot = await bootHostedRoom(
    code: code.isEmpty ? 'RESUME' : code,
    name: roomText(meta['name']),
    nickname: roomText(meta['kpName']),
    saveStore: saveStore,
    cardSink: cardSink,
  );
  // `openSave` → `importSave` → `host.adoptSave(save)`：灌回进度，
  // 花名册 members[].cid 原样恢复（含 P19 视角标记 meta.role/seat）。
  await boot.controller.openSave(save);
  return boot;
}
