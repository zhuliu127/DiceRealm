// ============================================================
// ui/room/room_net_factory.dart — P6 接线的一次性入口
//
// 入口页只需要问它两个问题：
//   · `host(...)`  —— 我建房，顺便开局域网服务
//   · `join(...)`  —— 我要进别人的房
// 多 base 候选、连接重试、会话创建、广播启动全在这里收口，
// UI 不碰 socket、不碰 LanServer、不碰 RoomClient。
//
// ★ 一条重要取舍：**建房时服务起不来不算失败**。
//   端口被别人占了、没连 WiFi —— 这些不该阻止 KP 单机开团。
//   服务起不来时 `lanWifi` 为 false、`lanBase` 退化成 127.0.0.1，
//   界面据此显示「只有你自己能进」，而不是把整页卡死。
// ============================================================

import '../../domain/room_model_host_core.dart';
import '../../domain/room_types.dart';
import '../../net/lan_client.dart';
import '../../net/lan_discovery.dart';
import '../../net/cloud_room.dart';
import '../../net/lan_room_host.dart';
import '../../net/lan_server.dart' show LanServerStart;
import '../../net/room_endpoint.dart';
import '../../net/room_frame.dart' show kRoomDiscoverPort, kRoomServicePort;
import '../../repo/recent_room_credential.dart'
    show saveRecentCredential;

import 'room_session_cloud.dart';
import 'room_session_hosting.dart';
import 'room_session_local.dart' show RoomLoopbackHub;
import 'room_session_remote.dart';

/// 建房结果。
class HostOutcome {
  const HostOutcome({required this.session, required this.server});

  /// KP 视角会话（同时向本机与网络投递）。
  final HostingLocalSession session;

  /// 服务启动详情（`ok:false` 仍可单机玩）。
  final LanServerStart server;

  /// 网络是否真的起来了。false ⇒ 界面要提示「只有自己能进」。
  bool get lanOk => server.ok;

  /// 是否连了局域网（有真网卡地址）。
  bool get lanWifi => server.wifi;
}

/// 公网开房结果（失败时 [session] 为 null、[error] 是人话）。
class CloudHostOutcome {
  const CloudHostOutcome({
    required this.session,
    required this.code,
    required this.error,
  });

  final CloudHostingSession? session;
  final String code;
  final String error;

  bool get ok => session != null;
}

/// 公网加入结果。
class CloudJoinOutcome {
  const CloudJoinOutcome({required this.session, required this.error});

  final CloudRemoteSession? session;
  final String error;

  bool get ok => session != null;
}

/// 加入结果。
class JoinOutcome {
  const JoinOutcome({this.session, this.error});

  final RemoteSession? session;
  final String? error;

  bool get ok => session != null;
}

/// 房间网络的统一入口。
class RoomNetFactory {
  const RoomNetFactory._();

  /// KP 建房：本机会话 + 局域网服务 + 广播心跳。
  ///
  /// 永远返回一个可用的 [HostingLocalSession]（单机保底），
  /// 网络状态看 [HostOutcome.lanOk] / [HostOutcome.lanWifi]。
  static Future<HostOutcome> host({
    required RoomHost host,
    /// 复用调用方已建好的 hub（建房时要让存档 / 存档槽 / KP 面板都看到同一份）。
    RoomLoopbackHub? hub,
    int servicePort = kRoomServicePort,
    int discoverPort = kRoomDiscoverPort,
    String discoverTarget = '255.255.255.255',
    Duration heartbeat = const Duration(seconds: 1),
  }) async {
    final LanRoomHost server = LanRoomHost(
      host: host,
      servicePort: servicePortOverride ?? servicePort,
      discoverPort: discoverPort,
      discoverTarget: discoverTarget,
      beatEvery: heartbeat,
    );
    final LanServerStart res;
    if (!networkEnabled) {
      // 测试路径：不 bind、不广播，只给一个「没网」结果。
      res = const LanServerStart(ok: false, error: 'NETWORK_DISABLED');
    } else {
      res = await server.start();
    }
    final HostingLocalSession session = HostingLocalSession(
      host: host,
      seat: kHostSeat,
      role: RoomRole.kp,
      server: server,
      hub: hub,
    );
    return HostOutcome(session: session, server: res);
  }

  /// 玩家/旁观加入：按「注入 > 手填 > 预设」顺序逐个试。
  ///
  /// 全部失败时返回最后一次的错误 —— 界面显示「连不上」比显示第一个
  /// 候选的超时更有用（第一个候选往往是过期的注入地址）。
  static Future<JoinOutcome> join({
    required String code,
    required String seat,
    String injectedBase = '',
    String userBase = '',
    List<String> presets = const <String>[],
    String role = RoomRole.player,
    /// ★ P16 P-1(a)/P-1(b)：稳定设备标识。空串时由 LanClient 回退
    ///   `ensureCloudDeviceId()`；续玩重建连接时传入历史凭据里的原值，
    ///   让服务端按 cid 复用旧座。
    String deviceId = '',
  }) async {
    // 与 host() 同一个开关：`testWidgets` 推不动真实 socket，真连会永远挂着。
    if (!networkEnabled) {
      return const JoinOutcome(error: 'NETWORK_DISABLED');
    }
    final List<String> bases = RoomEndpoint.candidates(
      injected: injectedBase,
      user: userBase,
      presets: presets,
    );
    if (bases.isEmpty) {
      return const JoinOutcome(error: '没有可用的房间地址');
    }

    String? lastErr;
    for (final String b in bases) {
      final LanClient client = LanClient(
        base: b,
        seat: seat,
        code: code,
        role: role,
        cid: deviceId,
      );
      final r = await client.connect();
      if (r.ok) {
        // ★ P20 M6：局域网加入成功 → 写凭据（LAN 房号保持大写归一不变）。
        //   凭据目录与存档严格分离，全程零日志；失败静默不拖垮主流程。
        saveRecentCredential(
          roomCode: code.trim().toUpperCase(),
          base: b,
          hostToken: '',
          deviceId: deviceId.isNotEmpty ? deviceId : ensureCloudDeviceId(),
          role: role,
          seat: client.seat,
          mode: 'lan',
          lastOkAt: DateTime.now().millisecondsSinceEpoch,
        );
        return JoinOutcome(
          session: RemoteSession(client: client, roomCode: code),
        );
      }
      lastErr = r.error;
      await client.dispose();
    }
    return JoinOutcome(error: lastErr ?? '连接失败');
  }

  /// 局域网发现开关。**测试设为 false** —— 真 UDP 扫描会拖慢每个用例
  /// 1.2s，且不同机器上受防火墙影响结果不稳定（会造出假红）。
  static bool discoveryEnabled = true;

  /// 服务端口覆盖。**测试设为 0** —— 否则多个走真实入口流程的用例
  /// 会抢 4211，后起的直接 bind 失败（表现是「建房成功但没网」）。
  /// 0 = 由系统分配。
  static int? servicePortOverride;

  /// 网络总开关。**测试必须设为 false**：
  /// `testWidgets` 跑在 FakeAsync 下，**推不动真实的 socket bind**，
  /// 于是 `await host()` 会卡住、页面永远进不去（表现为「找不到大厅页」）。
  /// 关掉后 `HostingLocalSession` 仍会构造（`pump` 变 no-op），
  /// 类型与生产一致，UI 逻辑不变。
  static bool networkEnabled = true;

  // ----------------------------------------------------------
  // 公网（云端 /room 中继）
  // ----------------------------------------------------------

  /// KP 开公网房间：在中继上登记 → 连 WS → 返回一个和局域网同形的会话。
  ///
  /// 失败**不保底**：与局域网不同，公网房间没有「单机也能玩」这回事 ——
  /// 用户点的是「公网开房」，连不上就必须如实报错，不能偷偷降级成局域网
  /// （那会让玩家拿着一个别人连不上的房号干等）。
  static Future<CloudHostOutcome> hostCloud({
    required RoomHost host,
    RoomLoopbackHub? hub,
    required String base,
    required String name,
    required String nickname,
    int maxPlayers = 6,
    bool allowSpectate = true,
    CloudSocket? socket,
  }) async {
    if (!networkEnabled) {
      return const CloudHostOutcome(
        session: null,
        code: '',
        error: '网络已关闭（测试模式）',
      );
    }
    final String cleanBase = normalizeCloudBase(base);
    if (cleanBase.isEmpty) {
      return const CloudHostOutcome(
        session: null,
        code: '',
        error: '没有配置公网中继地址',
      );
    }
    final CloudRoomHostLink link = CloudRoomHostLink(
      base: cleanBase,
      host: host,
      socket: socket,
    );
    final CloudHostStart start = await link.start(
      name: name,
      kpName: nickname,
      maxPlayers: maxPlayers,
      allowSpectate: allowSpectate,
    );
    if (!start.ok) {
      await link.stop();
      return CloudHostOutcome(session: null, code: '', error: start.error);
    }
    final CloudHostingSession session = CloudHostingSession(
      host: host,
      seat: kHostSeat,
      role: RoomRole.kp,
      cloudLink: link,
      hub: hub,
    );
    // cloudLink 是构造里挂的 onPlans；这里再补一次保证顺序（同一函数引用，幂等）。
    link.onPlans = session.pumpPlans;
    return CloudHostOutcome(
      session: session,
      code: start.code,
      error: '',
    );
  }

  /// 玩家加入公网房间。
  static Future<CloudJoinOutcome> joinCloud({
    required String base,
    required String code,
    String nickname = '调查员',
    String role = RoomRole.player,
    // ★ P20 M6：稳定设备标识透传（续玩时传凭据里的原值 → device_seats
    //   命中 → joinKind='reconnect'、复用原座）。
    String deviceId = '',
    CloudSocket? socket,
  }) async {
    if (!networkEnabled) {
      return const CloudJoinOutcome(session: null, error: 'NETWORK_DISABLED');
    }
    final String cleanBase = normalizeCloudBase(base);
    if (cleanBase.isEmpty) {
      return const CloudJoinOutcome(
        session: null,
        error: '没有配置公网中继地址',
      );
    }
    // ★ P20 N-1：云端房号一律用 cloudRoomCode() 小写规范化（服务端正则
    //   `[a-z0-9]{4,12}`）。HTTP join 路径与 WS query 用同一个规范化变量；
    //   LAN 的 normalizeRoomCode() 大写口径保持不变，两者绝不混用。
    final String normalizedCode = cloudRoomCode(code);
    final CloudRoomClient client = CloudRoomClient(
      base: cleanBase,
      code: normalizedCode,
      role: role,
      nickname: nickname,
      deviceId: deviceId,
      socket: socket,
    );
    final CloudJoinResult r = await client.connect();
    if (!r.ok) {
      await client.dispose();
      return CloudJoinOutcome(session: null, error: r.error);
    }
    // ★ P20 M6：公网加入成功 → 写凭据（mode=cloud / 规范化 code / 原 deviceId）。
    //   玩家 hostToken 恒 ''；凭据只进 .room_credentials 私有目录。
    saveRecentCredential(
      roomCode: normalizedCode,
      base: cleanBase,
      hostToken: '',
      deviceId: deviceId.isNotEmpty ? deviceId : ensureCloudDeviceId(),
      role: role,
      seat: client.seat,
      mode: 'cloud',
      lastOkAt: DateTime.now().millisecondsSinceEpoch,
    );
    return CloudJoinOutcome(
      session: CloudRemoteSession(client: client, roomCode: normalizedCode),
      error: '',
    );
  }

  /// 扫附近房间（界面「附近的房间」列表用）。
  static Future<List<RoomAnnounce>> nearby({
    Duration timeout = const Duration(milliseconds: 1600),
  }) async {
    if (!discoveryEnabled) return const <RoomAnnounce>[];
    return LanDiscoverer.scan(timeout: timeout);
  }
}
