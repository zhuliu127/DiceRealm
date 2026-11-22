// ============================================================
// test/p20_resume_reconnect_test.dart — P20 QA 契约 A/B 组
//
// 严过关（QA）独立编写。目标不是"看代码长得对"，而是用**内存替身逐字
// 捕获 URL / 请求体 / 落盘内容**，证明下面这些事真的发生：
//
//   A. 同房号与身份
//      1. KP 公网续玩不发 POST /api/rooms（P0-4 抓包判据），只发 /resume；
//         WS 用原 code + 原 hostToken；结果 meta.code 与原存档一致。
//      2. 玩家 /join 带持久 deviceId，joinKind=reconnect，座位/角色不变。
//      3. LAN 续玩用大写原号；玩家 deviceId 作为 LanClient.cid。
//      4. cloudRoomCode 小写 / normalizeRoomCode 大写；HTTP 路径与 WS code
//         query 必须是**同一个**规范化值。
//      5. N-2：完整 wss wsUrl 当 base 时产出 wss://h/room/ws，不降级、不双 /ws。
//   B. 凭据闭环与稳定 deviceId
//      6. 5 个写入点后凭据 9 字段齐全、mode ∈ {lan,cloud}。
//      7. 旧 7 字段 JSON 无损回落；flexible 三种大小写查法命中。
//      8. 冷启 3 次 deviceId 完全一致；默认内存实现零文件 I/O。
//      9. 令牌禁令：20 键快照 / 导出文本 / print / 源码字符串零命中。
//
// 全部零真网络：cloudHttp / cloudSocketFactory / deviceIdStorage /
// recentCredentialStore 都换成内存替身，tearDown 逐字恢复全局注入点。
// ============================================================

import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File;

import 'package:dice_realm/domain/js_compat.dart' show asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart' show RoomRole;
import 'package:dice_realm/net/cloud_room.dart'
    show
        CloudHttpResponse,
        CloudHttpTransport,
        CloudRoomClient,
        CloudSocket,
        cloudDeviceId,
        cloudHttp,
        cloudRoomCode,
        cloudSocketFactory,
        cloudWsUrl,
        ensureCloudDeviceId;
import 'package:dice_realm/net/cloud_room_backup.dart'
    show CloudBackupService, clearActiveCloudBackup;
import 'package:dice_realm/repo/cloud_device_id.dart'
    show
        DeviceIdStorage,
        FileDeviceIdStorage,
        MemoryDeviceIdStorage,
        deviceIdStorage,
        isValidDeviceId,
        newStableDeviceId;
import 'package:dice_realm/repo/recent_room_credential.dart'
    show
        MemoryRecentCredentialStorage,
        RecentCredentialStorage,
        RecentRoomCredential,
        clearRecentCredential,
        loadRecentCredential,
        loadRecentCredentialFlexible,
        recentCredentialStore,
        saveRecentCredential;
import 'package:dice_realm/repo/room_save_store.dart'
    show InMemoryRoomSaveStore;
import 'package:dice_realm/ui/room/room_boot.dart'
    show
        bootCloudRoom,
        bootHostedRoom,
        bootLocalRoom,
        normalizeRoomCode,
        resumeCloudRoom;
import 'package:dice_realm/ui/room/room_history_export.dart'
    show buildRoomHistoryExportText;
import 'package:dice_realm/ui/room/room_net_factory.dart' show RoomNetFactory;
import 'package:dice_realm/ui/room/room_resume.dart'
    show ResumeRunResult, RoomResumeService;
import 'package:dice_realm/ui/room/resume_mode_dialog.dart' show ResumeMode;
import 'package:flutter_test/flutter_test.dart';

// ------------------------------------------------------------
// 内存替身
// ------------------------------------------------------------

class _Req {
  const _Req(this.url, this.body);

  final Uri url;
  final Map<String, Object?> body;
}

/// 记录所有 POST 的 URL 与请求体；[handler] 决定响应。
class _RecordingHttp implements CloudHttpTransport {
  _RecordingHttp(this.handler);

  final CloudHttpResponse Function(Uri url, Map<String, Object?> body) handler;
  final List<_Req> log = <_Req>[];

  @override
  Future<CloudHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    log.add(_Req(url, body));
    return handler(url, body);
  }

  List<String> get paths => <String>[for (final _Req r in log) r.url.path];
}

/// 连上后立刻推 [readyFrame] 的内存 socket（与 p10 FakeRelay 同口径：
/// onText 在 connect 之前已挂好，因此同步推帧是合法的）。
class _FakeSocket implements CloudSocket {
  _FakeSocket(this.readyFrame);

  final Map<String, Object?> readyFrame;
  final List<String> urls = <String>[];
  void Function(String)? _onText;

  @override
  set onText(void Function(String text)? v) => _onText = v;

  @override
  set onClosed(void Function()? v) {}

  @override
  Future<void> connect(String url) async {
    urls.add(url);
    _onText?.call(jsonEncode(readyFrame));
  }

  @override
  void send(String text) {}

  @override
  Future<void> close() async {}
}

CloudHttpResponse _ok([Map<String, Object?> json = const <String, Object?>{}]) =>
    CloudHttpResponse(ok: true, status: 200, json: <String, Object?>{
      'ok': true,
      ...json,
    });

/// 一份**真 20 键**权威存档（走生产 bootLocalRoom/exportSave，不手搓 Map）。
Future<Map<String, Object?>> _realSave(String code, {String name = '本机档'}) async {
  final boot = await bootLocalRoom(code: code, name: name, nickname: '老K');
  final save = boot.session.exportSave();
  boot.dispose();
  return save!;
}

const String kCloudBase = 'https://relay.example.com/room';
const String kCloudCode = 'ab12cd';
const String kHostToken = 'HT-ORIGINAL-SECRET-7f3a';
const String kDeviceId = 'fl-a1b2c3d4e5f60718';

/// KP 续玩用的 HTTP 路由表：/resume 200；/backup/read 可注入云端档。
_RecordingHttp _kpHttp({
  int fetchSeq = 0,
  String? fetchPayload,
  bool fetchOk = true,
  int savedAt = 0,
}) {
  return _RecordingHttp((Uri url, Map<String, Object?> body) {
    final String p = url.path;
    if (p.endsWith('/resume')) return _ok();
    if (p.endsWith('/backup/read')) {
      if (!fetchOk) {
        return const CloudHttpResponse(
            ok: false, status: 404, json: <String, Object?>{'error': 'no_backup'});
      }
      return _ok(<String, Object?>{
        'seq': fetchSeq,
        'payload': fetchPayload ?? '',
        'savedAt': savedAt,
      });
    }
    if (p.endsWith('/backup')) return _ok(<String, Object?>{'seq': 1});
    if (p.endsWith('/suspend')) return _ok();
    if (p.endsWith('/join')) {
      return _ok(<String, Object?>{
        'code': kCloudCode,
        'mtoken': 'MT-NEW',
        'role': RoomRole.player,
        'seat': 'p1',
        'joinKind': 'reconnect',
      });
    }
    return _ok();
  });
}

// ------------------------------------------------------------
// 全局注入点：捕获初值 → setUp 替换 → tearDown 逐字恢复
// ------------------------------------------------------------
final CloudHttpTransport _origHttp = cloudHttp;
final CloudSocket Function() _origSocketFactory = cloudSocketFactory;
final DeviceIdStorage _origDeviceStorage = deviceIdStorage;
final RecentCredentialStorage _origCredStore = recentCredentialStore;
final String _origCloudDeviceId = cloudDeviceId;
final bool _origNetworkEnabled = RoomNetFactory.networkEnabled;

void main() {
  late _RecordingHttp http;
  late _FakeSocket socket;

  setUp(() {
    http = _kpHttp();
    socket = _FakeSocket(const <String, Object?>{'k': 'host.ok'});
    cloudHttp = http;
    cloudSocketFactory = () => socket;
    deviceIdStorage = MemoryDeviceIdStorage();
    cloudDeviceId = '';
    recentCredentialStore = MemoryRecentCredentialStorage();
    RoomNetFactory.networkEnabled = false;
    clearActiveCloudBackup();
  });

  tearDown(() {
    cloudHttp = _origHttp;
    cloudSocketFactory = _origSocketFactory;
    deviceIdStorage = _origDeviceStorage;
    cloudDeviceId = _origCloudDeviceId;
    recentCredentialStore = _origCredStore;
    RoomNetFactory.networkEnabled = _origNetworkEnabled;
    clearActiveCloudBackup();
  });

  // ==========================================================
  // A. 同一房间号与身份
  // ==========================================================
  group('A 同一房间号与身份', () {
    test('A4 cloudRoomCode 小写归一化 / normalizeRoomCode 大写', () {
      expect(cloudRoomCode('AB12CD'), 'ab12cd');
      expect(cloudRoomCode('  Ab12Cd  '), 'ab12cd');
      expect(cloudRoomCode('ab12cd'), 'ab12cd', reason: '幂等：已小写不变');
      expect(normalizeRoomCode('ab12cd'), 'AB12CD');
      expect(normalizeRoomCode('  ab12cd '), 'AB12CD');
      expect(normalizeRoomCode('AB12CD'), 'AB12CD');
    });

    test('A5 N-2 cloudWsUrl 完整 wss wsUrl 不降级不双 ws', () {
      final String url = cloudWsUrl(
        'wss://relay.example.com/room/ws?code=ab12cd&t=tok&d=fl-x',
        code: kCloudCode,
        token: 'tk',
        deviceId: kDeviceId,
      );
      final Uri u = Uri.parse(url);
      expect(u.scheme, 'wss', reason: 'wss 输入绝不能降级成 ws');
      expect(u.path, '/room/ws');
      expect(url.contains('/ws/ws'), isFalse, reason: '不能出现双 /ws');
      expect(url.contains('wss://relay.example.com/room/ws'), isTrue);
      expect(u.queryParameters['code'], kCloudCode);
      expect(u.queryParameters['t'], 'tk');
      expect(u.queryParameters['d'], kDeviceId);
      // 既有 p10:350-362 的口径逐字保留（一字不改也必须全绿）。
      final String plain = cloudWsUrl(
        'https://relay.example.com/room',
        code: 'AB12CD',
        token: 'tk',
        deviceId: 'fl-test',
      );
      final Uri pu = Uri.parse(plain);
      expect(pu.scheme, 'wss');
      expect(pu.path, '/room/ws');
      expect(pu.queryParameters['code'], 'AB12CD');
      expect(pu.queryParameters['t'], 'tk');
      expect(pu.queryParameters['d'], 'fl-test');
    });

    test('A4 HTTP 路径与 WS code query 必须是同一个规范化值', () async {
      RoomNetFactory.networkEnabled = true;
      final http2 = _RecordingHttp((Uri url, Map<String, Object?> body) {
        return _ok(<String, Object?>{
          'code': kCloudCode,
          'mtoken': 'MT-1',
          'role': RoomRole.player,
          'seat': 'p1',
          'joinKind': 'reconnect',
        });
      });
      cloudHttp = http2;
      final sock = _FakeSocket(const <String, Object?>{'k': 'ready', 'seat': 'p1'});
      final client = CloudRoomClient(
        base: kCloudBase,
        code: cloudRoomCode('AB12CD'),
        role: RoomRole.player,
        deviceId: kDeviceId,
        socket: sock,
      );
      final result = await client.connect();
      expect(result.ok, isTrue);

      final Uri httpUri = http2.log.single.url;
      final Uri wsUri = Uri.parse(sock.urls.single);
      // 逐字取 HTTP 路径里的房号段与 WS query 的 code。
      final RegExpMatch? m =
          RegExp(r'/api/rooms/([^/]+)/join$').firstMatch(httpUri.path);
      expect(m, isNotNull, reason: 'HTTP 路径必须是 /api/rooms/<code>/join');
      final String httpCode = m!.group(1)!;
      final String wsCode = wsUri.queryParameters['code'] ?? '';
      expect(httpCode, kCloudCode);
      expect(wsCode, kCloudCode);
      expect(httpCode, wsCode, reason: '§8.1：两处必须用同一个规范化 code 变量');
      expect(httpUri.path, '/room/api/rooms/ab12cd/join');
      expect(wsUri.scheme, 'wss');
      expect(wsUri.path, '/room/ws');
      await client.dispose();
    });

    test('A1 KP 公网续玩：无 POST /api/rooms，只 /resume，WS 原 code+原 token',
        () async {
      final Map<String, Object?> save = await _realSave(kCloudCode);
      final cred = RecentRoomCredential(
        roomCode: kCloudCode,
        base: kCloudBase,
        hostToken: kHostToken,
        deviceId: kDeviceId,
        role: RoomRole.kp,
        seat: 'host',
        mode: 'cloud',
        lastOkAt: 1700000000000,
      );
      saveRecentCredential(
        roomCode: cred.roomCode,
        base: cred.base,
        hostToken: cred.hostToken,
        deviceId: cred.deviceId,
        role: cred.role,
        seat: cred.seat,
        mode: cred.mode,
        lastOkAt: cred.lastOkAt,
      );

      final RoomResumeService service = RoomResumeService(
        store: InMemoryRoomSaveStore(),
        backup: CloudBackupService(http: http),
        clock: () => 1700000005000,
      );
      final ResumeRunResult result =
          await service.run(save, cred, ResumeMode.cloud);

      expect(result.ok, isTrue, reason: 'KP 续玩必须成功：${result.errorText}');
      expect(result.boot, isNotNull);
      // P0-4 抓包判据：绝不能重新登记房间。
      expect(
        http.paths.where((String p) => p.endsWith('/api/rooms')),
        isEmpty,
        reason: 'KP 续玩绝不能 POST /api/rooms（会新建第二间房）',
      );
      expect(
        http.paths.where((String p) => p == '/room/api/rooms/ab12cd/resume'),
        hasLength(1),
        reason: '必须请求原小写房号的 /resume',
      );
      expect(
        http.paths.where((String p) => p.contains('/state')),
        isEmpty,
        reason: 'KP 全量档一律走 /backup，绝不写 /state',
      );
      // WS：原 code + 原 hostToken + 持久 deviceId。
      final Uri ws = Uri.parse(socket.urls.single);
      expect(ws.queryParameters['code'], kCloudCode);
      expect(ws.queryParameters['t'], kHostToken);
      expect(ws.queryParameters['d'], kDeviceId);
      // meta.code 与原存档逐字相同。
      expect(
        jsStr(asMap(result.boot!.host.state['meta'])['code']),
        jsStr(asMap(save['meta'])['code']),
      );
    });

    test('A1 resumeCloudRoom 用原 code + 原 hostToken 起 WS（跳过登记）',
        () async {
      final Map<String, Object?> save = await _realSave(kCloudCode);
      final sock = _FakeSocket(const <String, Object?>{'k': 'host.ok'});
      final out = await resumeCloudRoom(
        save: save,
        base: kCloudBase,
        code: kCloudCode,
        hostToken: kHostToken,
        deviceId: kDeviceId,
        saveStore: InMemoryRoomSaveStore(),
        socket: sock,
      );
      expect(out.ok, isTrue, reason: out.error);
      expect(out.code, kCloudCode);
      expect(out.hostToken, kHostToken);
      expect(asMap(out.boot!.host.state['meta'])['code'], kCloudCode);
      final Uri ws = Uri.parse(sock.urls.single);
      expect(ws.queryParameters['code'], kCloudCode);
      expect(ws.queryParameters['t'], kHostToken);
      expect(ws.queryParameters['d'], kDeviceId);
      // 关键：整个过程一次 HTTP 请求都没有（登记被跳过）。
      expect(http.log, isEmpty, reason: 'code/hostToken 非空时 start() 不得登记');
      out.boot!.dispose();
    });

    test('A2 玩家公网续玩：/join 带持久 deviceId，joinKind=reconnect，座位不变',
        () async {
      final http2 = _RecordingHttp((Uri url, Map<String, Object?> body) {
        return _ok(<String, Object?>{
          'code': kCloudCode,
          'mtoken': 'MT-RECONNECT',
          'role': RoomRole.player,
          'seat': 'p2',
          'joinKind': 'reconnect',
        });
      });
      cloudHttp = http2;
      final sock = _FakeSocket(const <String, Object?>{
        'k': 'ready',
        'seat': 'p2',
        'role': RoomRole.player,
      });
      final client = CloudRoomClient(
        base: kCloudBase,
        code: kCloudCode,
        role: RoomRole.player,
        deviceId: kDeviceId,
        socket: sock,
      );
      final result = await client.connect();
      expect(result.ok, isTrue, reason: result.error);
      expect(result.joinKind, 'reconnect');
      expect(result.seat, 'p2', reason: '座位必须与凭据 seat 相同');
      expect(client.role, RoomRole.player);
      final _Req req = http2.log.single;
      expect(req.body['deviceId'], kDeviceId,
          reason: '/join 请求体必须带持久 deviceId（不是新生成的）');
      expect(req.url.path, '/room/api/rooms/ab12cd/join');
      final Uri ws = Uri.parse(sock.urls.single);
      expect(ws.queryParameters['code'], kCloudCode);
      expect(ws.queryParameters['t'], 'MT-RECONNECT');
      expect(ws.queryParameters['d'], kDeviceId);
      // 玩家侧零云端全量档请求。
      expect(http2.paths.where((String p) => p.contains('/backup')), isEmpty);
      expect(http2.paths.where((String p) => p.contains('/state')), isEmpty);
      await client.dispose();
    });

    test('A2 旁观者公网续玩：spectator 角色保持，joinKind=reconnect', () async {
      final http2 = _RecordingHttp((Uri url, Map<String, Object?> body) {
        return _ok(<String, Object?>{
          'code': kCloudCode,
          'mtoken': 'MT-SPEC',
          'role': RoomRole.spectator,
          'seat': 'sp1',
          'joinKind': 'reconnect',
        });
      });
      cloudHttp = http2;
      final sock = _FakeSocket(const <String, Object?>{
        'k': 'ready',
        'seat': 'sp1',
        'role': RoomRole.spectator,
      });
      final client = CloudRoomClient(
        base: kCloudBase,
        code: kCloudCode,
        role: RoomRole.spectator,
        deviceId: kDeviceId,
        socket: sock,
      );
      final result = await client.connect();
      expect(result.joinKind, 'reconnect');
      expect(result.seat, 'sp1');
      expect(client.role, RoomRole.spectator,
          reason: '旁观者视角必须保持，不占玩家名额');
      expect(http2.log.single.body['deviceId'], kDeviceId);
      await client.dispose();
    });

    test('A3 LAN 续玩：resumeCloudRoom 之外 LAN 走大写原号 + deviceId→cid',
        () async {
      final Map<String, Object?> save = await _realSave('AB12CD');
      // bootHostedRoom 在 networkEnabled=false 下不真 bind，但凭据写入点照走。
      final boot = await bootHostedRoom(
        code: 'AB12CD',
        name: '局域网团',
        nickname: '老K',
        saveStore: InMemoryRoomSaveStore(),
      );
      expect(jsStr(asMap(boot.host.state['meta'])['code']), 'AB12CD');
      final RecentRoomCredential? c = loadRecentCredential('AB12CD');
      expect(c, isNotNull, reason: 'LAN 开房成功必须写凭据');
      expect(c!.roomCode, 'AB12CD', reason: 'LAN 房号必须保持大写原号');
      expect(c.mode, 'lan');
      expect(c.deviceId, isNotEmpty);
      boot.dispose();

      // 玩家侧：RoomNetFactory.join 必须把 deviceId 透传成 LanClient.cid。
      final String src = File('lib/ui/room/room_net_factory.dart')
          .readAsStringSync();
      expect(
        RegExp(r'LanClient\(').hasMatch(src) &&
            RegExp(r'cid:\s*deviceId').hasMatch(src),
        isTrue,
        reason: 'join() 必须把 cred.deviceId 作为 LanClient.cid 上送',
      );
      final String resumeSrc =
          File('lib/ui/room/room_resume.dart').readAsStringSync();
      expect(resumeSrc.contains('deviceId: cred.deviceId'), isTrue,
          reason: '_runLan 必须把凭据里的原 deviceId 传下去');
      expect(resumeSrc.contains('normalizeRoomCode(_codeOf(save))'), isTrue,
          reason: 'LAN 续玩必须用大写归一原号');
      expect(save, isNotNull);
    });
  });

  // ==========================================================
  // B. 凭据闭环与稳定 deviceId
  // ==========================================================
  group('B 凭据闭环与稳定 deviceId', () {
    /// 断言一条凭据 9 字段齐全且 mode 合法。
    void assertNineFields(RecentRoomCredential? c, String expectedCode,
        String expectedMode) {
      expect(c, isNotNull);
      final Map<String, Object?> j = c!.toJson();
      expect(j.keys.toSet(), <String>{
        'roomCode', 'base', 'hostToken', 'deviceId', 'role', 'seat',
        'savedAt', 'mode', 'lastOkAt',
      }, reason: '凭据必须恰好 9 字段');
      expect(c.roomCode, expectedCode);
      expect(c.mode, expectedMode);
      expect(c.mode == 'lan' || c.mode == 'cloud', isTrue);
      expect(c.deviceId, isNotEmpty, reason: 'deviceId 必须落凭据');
      expect(c.savedAt, greaterThan(0));
      expect(c.lastOkAt, greaterThan(0), reason: '成功写入点必须刷新 lastOkAt');
    }

    test('B6 五个写入点均产出 9 字段凭据', () async {
      // ① bootHostedRoom（LAN 开房）
      final b1 = await bootHostedRoom(
          code: 'LAN001', name: 'L', nickname: 'K',
          saveStore: InMemoryRoomSaveStore());
      assertNineFields(loadRecentCredential('LAN001'), 'LAN001', 'lan');
      b1.dispose();
      clearRecentCredential();

      // ② bootCloudRoom（公网开房）
      cloudHttp = _RecordingHttp((Uri url, Map<String, Object?> body) {
        return _ok(<String, Object?>{
          'code': 'cld001',
          'hostToken': 'HT-CLD',
          'wsBase': kCloudBase,
        });
      });
      cloudSocketFactory =
          () => _FakeSocket(const <String, Object?>{'k': 'host.ok'});
      final c2 = await bootCloudRoom(
          base: kCloudBase, name: 'C', nickname: 'K',
          saveStore: InMemoryRoomSaveStore());
      expect(c2.ok, isTrue, reason: c2.error);
      assertNineFields(loadRecentCredential('cld001'), 'cld001', 'cloud');
      c2.boot!.dispose();
      clearRecentCredential();

      // ③ RoomNetFactory.joinCloud（公网加入）
      RoomNetFactory.networkEnabled = true;
      cloudHttp = _RecordingHttp((Uri url, Map<String, Object?> body) {
        return _ok(<String, Object?>{
          'code': 'cld002', 'mtoken': 'MT-2', 'role': RoomRole.player,
          'seat': 'p1', 'joinKind': 'new',
        });
      });
      cloudSocketFactory =
          () => _FakeSocket(const <String, Object?>{'k': 'ready', 'seat': 'p1'});
      final j3 = await RoomNetFactory.joinCloud(
          base: kCloudBase, code: 'CLD002', deviceId: kDeviceId);
      expect(j3.ok, isTrue, reason: j3.error);
      assertNineFields(loadRecentCredential('cld002'), 'cld002', 'cloud');
      await j3.session!.closeConnection();
      clearRecentCredential();

      // ④ RoomNetFactory.join（LAN 加入，真回环 socket）
      final seed = await bootLocalRoom(
          code: 'LAN002', name: 'L', nickname: 'K');
      final host = await RoomNetFactory.host(
        host: seed.host,
        servicePort: 0,
        discoverPort: 24355,
        discoverTarget: '127.0.0.1',
        heartbeat: const Duration(milliseconds: 150),
      );
      expect(host.lanOk, isTrue, reason: '测试回环服务应能起来');
      final j4 = await RoomNetFactory.join(
        code: 'LAN002',
        seat: '', // 玩家只知道房号，座位由服务端分配（指定不存在的座位会 UNKNOWN_SEAT）
        injectedBase: 'http://127.0.0.1:${host.session.server.port}',
        deviceId: kDeviceId,
      );
      expect(j4.ok, isTrue, reason: 'LAN 加入失败：${j4.error}');
      assertNineFields(loadRecentCredential('LAN002'), 'LAN002', 'lan');
      j4.session?.dispose();
      await host.session.shutdown();
      seed.dispose();
      clearRecentCredential();

      // ⑤ 续玩成功（RoomResumeService._refreshCredential）
      RoomNetFactory.networkEnabled = false;
      final Map<String, Object?> save = await _realSave(kCloudCode);
      final cred = RecentRoomCredential(
        roomCode: kCloudCode,
        base: kCloudBase,
        hostToken: kHostToken,
        deviceId: kDeviceId,
        role: RoomRole.kp,
        seat: 'host',
        mode: 'lan', // 故意给旧值，续玩后必须刷新为 cloud
        lastOkAt: 1,
      );
      saveRecentCredential(
        roomCode: cred.roomCode, base: cred.base,
        hostToken: cred.hostToken, deviceId: cred.deviceId,
        role: cred.role, seat: cred.seat, mode: cred.mode,
        lastOkAt: cred.lastOkAt,
      );
      cloudHttp = http;
      cloudSocketFactory =
          () => _FakeSocket(const <String, Object?>{'k': 'host.ok'});
      final service = RoomResumeService(
        store: InMemoryRoomSaveStore(),
        backup: CloudBackupService(http: http),
        clock: () => 1700000009999,
      );
      final ResumeRunResult r =
          await service.run(save, cred, ResumeMode.cloud);
      expect(r.ok, isTrue, reason: r.errorText);
      final RecentRoomCredential? after = loadRecentCredential(kCloudCode);
      assertNineFields(after, kCloudCode, 'cloud');
      expect(after!.lastOkAt, 1700000009999,
          reason: '续玩成功必须把 lastOkAt 刷新为注入时钟');
      expect(after.hostToken, kHostToken, reason: '保持原 hostToken');
      expect(after.deviceId, kDeviceId, reason: '保持原 deviceId');
      r.boot?.dispose();
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('B7 旧 7 字段 JSON 无损回落 + flexible 三种大小写查法', () {
      final Map<String, Object?> old = <String, Object?>{
        'roomCode': 'AB12CD',
        'base': kCloudBase,
        'hostToken': 'HT-OLD',
        'deviceId': 'fl-olddevice000001',
        'role': RoomRole.player,
        'seat': 'p3',
        'savedAt': 123456,
        // 故意没有 mode / lastOkAt
      };
      final RecentRoomCredential? parsed = RecentRoomCredential.fromJson(old);
      expect(parsed, isNotNull);
      expect(parsed!.mode, '', reason: '旧 JSON 缺 mode → 回落空串');
      expect(parsed.lastOkAt, 0, reason: '旧 JSON 缺 lastOkAt → 回落 0');
      expect(parsed.roomCode, 'AB12CD');
      expect(parsed.hostToken, 'HT-OLD');
      expect(parsed.deviceId, 'fl-olddevice000001');
      expect(parsed.role, RoomRole.player);
      expect(parsed.seat, 'p3');
      expect(parsed.savedAt, 123456);
      expect(parsed.hasBase, isTrue);

      // 写进存储，三种查法都要命中（原样 / 全小写 / 全大写 / 混合）。
      recentCredentialStore.writeAll(<String, Object?>{
        'rooms': <Object?>[old],
      });
      for (final String q in <String>['AB12CD', 'ab12cd', 'Ab12Cd']) {
        final RecentRoomCredential? hit = loadRecentCredentialFlexible(q);
        expect(hit, isNotNull, reason: 'flexible($q) 必须命中');
        expect(hit!.roomCode, 'AB12CD');
        expect(hit.mode, '');
        expect(hit.lastOkAt, 0);
      }
      expect(loadRecentCredential('ab12cd'), isNull,
          reason: 'loadRecentCredential 原语义不变：不做大小写兜底');
    });

    test('B8 冷启 3 次 deviceId 完全一致且格式合法', () {
      final Directory dir =
          Directory.systemTemp.createTempSync('p20_qa_device_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      deviceIdStorage = FileDeviceIdStorage(dir);
      final List<String> ids = <String>[];
      for (int i = 0; i < 3; i++) {
        cloudDeviceId = ''; // 每次都模拟冷启（丢掉进程内缓存）
        final String id = ensureCloudDeviceId();
        expect(isValidDeviceId(id), isTrue, reason: '第 ${i + 1} 次格式非法：$id');
        ids.add(id);
      }
      expect(ids[0], ids[1]);
      expect(ids[1], ids[2]);
      expect(ids.toSet(), hasLength(1));
      final File f = File('${dir.path}/device_id.txt');
      expect(f.existsSync(), isTrue, reason: 'FileDeviceIdStorage 必须真落盘');
      expect(f.readAsStringSync().trim(), ids[0]);
      expect(newStableDeviceId(), isNot(ids[0]));
      expect(isValidDeviceId('fl-1234'), isFalse);
      expect(isValidDeviceId(''), isFalse);
      expect(isValidDeviceId('FL-A1B2C3D4E5F60718'), isFalse);
    });

    test('B8 flutter test 默认 MemoryDeviceIdStorage 零文件 I/O', () {
      expect(_origDeviceStorage, isA<MemoryDeviceIdStorage>(),
          reason: '未注入时必须是内存实现，flutter test 不碰盘');
      final Directory dir =
          Directory.systemTemp.createTempSync('p20_qa_nodevice_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      deviceIdStorage = MemoryDeviceIdStorage();
      cloudDeviceId = '';
      final String id = ensureCloudDeviceId();
      expect(isValidDeviceId(id), isTrue);
      expect(dir.listSync(), isEmpty, reason: '内存实现绝不能在磁盘上产生文件');
      final String src =
          File('lib/repo/cloud_device_id.dart').readAsStringSync();
      final int idx = src.indexOf('class MemoryDeviceIdStorage');
      final int end = src.indexOf('/// 独立私有文件实现', idx);
      final String memBlock = src.substring(idx, end < 0 ? src.length : end);
      expect(memBlock.contains('File('), isFalse);
      expect(memBlock.contains('Directory('), isFalse);
      expect(memBlock.contains('dart:io'), isFalse);
    });

    test('B9 令牌禁令：20 键快照 / 导出 / print / 源码字符串零命中', () async {
      final boot = await bootLocalRoom(
          code: 'AB12CD', name: '洋馆', nickname: '老K');
      final Map<String, Object?> save = boot.session.exportSave()!;
      // ① host.save() 必须恰好 20 键且含 privateBySeat。
      expect(save.keys.toSet(), <String>{
        'v', 'code', 'rules', 'savedAt', 'seq', 'stateSeq', 'meta',
        'members', 'chats', 'logs', 'dice', 'scene', 'combat',
        'sceneCheck', 'roundStarts', 'privateBySeat', 'requestsBySeat',
        'boardBySeat', 'localAssets', 'localActors',
      });
      expect(save.containsKey('privateBySeat'), isTrue);
      final String wire = jsonEncode(save);
      for (final String banned in <String>[
        'hostToken', 'mtoken', 'deviceId', kHostToken, kDeviceId,
        '203.0.113.10', 'deploy_key', 'BEGIN RSA PRIVATE KEY',
        'relay.example.com',
      ]) {
        expect(wire.contains(banned), isFalse,
            reason: 'host.save() 20 键快照不得出现 $banned');
      }
      boot.dispose();

      // ② room_history_export 产物不回显凭据（把秘密塞进 meta 测脱敏）。
      final Map<String, Object?> state = <String, Object?>{
        'meta': <String, Object?>{
          'code': 'AB12CD',
          'name': '洋馆',
          'kpName': '老K',
          'hostToken': kHostToken,
          'mtoken': 'MT-LEAK-PROBE',
          'deviceId': kDeviceId,
        },
        'members': <Object?>[
          <String, Object?>{'seat': 'host', 'role': 'kp', 'nickname': '老K'},
        ],
        'chats': <Object?>[],
        'logs': <Object?>[],
        'dice': <Object?>[],
      };
      final String export = buildRoomHistoryExportText(state,
          seat: 'p1', role: RoomRole.player, exportedAtMs: 1700000000000);
      for (final String banned in <String>[
        kHostToken, 'MT-LEAK-PROBE', kDeviceId,
        '203.0.113.10', 'deploy_key',
      ]) {
        expect(export.contains(banned), isFalse,
            reason: '导出产物不得回显 $banned');
      }

      // ③ 新增/修改源码：零 print/日志、零服务器地址/私钥明文字符串。
      const List<String> p20Files = <String>[
        'lib/repo/cloud_device_id.dart',
        'lib/repo/recent_room_credential.dart',
        'lib/net/cloud_room.dart',
        'lib/net/cloud_room_backup.dart',
        'lib/ui/room/room_net_factory.dart',
        'lib/ui/room/room_boot.dart',
        'lib/ui/room/room_resume.dart',
        'lib/ui/room/resume_mode_dialog.dart',
        'lib/ui/room/room_session.dart',
        'lib/ui/room/room_session_remote.dart',
        'lib/ui/room/room_session_cloud.dart',
        'lib/ui/room/room_save_syncer.dart',
        'lib/ui/room/room_entry_page.dart',
        'lib/main.dart',
      ];
      // ★ 口径修正（QA 自证伪后）：判「**新增**源码字符串」零命中，不是
      //   "整文件零命中" —— `room_entry_page.dart` 的「去设置」示例地址
      //   `https://relay.example.com/room` 是 v2.32.0 基线既存的
      //   UI 提示（基线 :728 逐字存在），P20 未新增任何服务器地址。
      //   因此用「与 v2.32.0 基线逐字比对 + 新增行零命中」两条同时收紧。
      final String baselineEntry = File(
              'C:/Users/60965/WorkBuddy/2026-11-08-13-25-14/'
              '_p20_progress/room_entry_page.baseline.dart')
          .readAsStringSync();
      final String currentEntry =
          File('lib/ui/room/room_entry_page.dart').readAsStringSync();
      const String preexistingHint =
          "hint: '公网开房要先在设置里填中继地址（例如 https://relay.example.com/room）',";
      expect(baselineEntry.contains(preexistingHint), isTrue,
          reason: '前置：该示例地址确为基线既存，不是 P20 新增');
      expect(currentEntry.contains(preexistingHint), isTrue);
      final String addedOnly =
          currentEntry.replaceAll(preexistingHint, '');
      for (final String banned in <String>[
        '203.0.113.10', 'deploy_key', 'BEGIN RSA PRIVATE KEY',
        'relay.example.com',
      ]) {
        expect(addedOnly.contains(banned), isFalse,
            reason: 'P20 新增源码字符串不得出现 $banned');
      }
      // 新增文件（基线里根本不存在）整文件零命中；其余文件也零 print/日志。
      for (final String path in p20Files) {
        final String s = File(path).readAsStringSync();
        expect(RegExp(r'\bprint\s*\(').hasMatch(s), isFalse,
            reason: '$path 不得出现 print(');
        // ★ P13 主修法要求「消除静默失败」，允许 room_save_syncer.dart /
        //   room_controller.dart / main.dart 出现带 [SAVE] 前缀的诊断日志；
        //   令牌 / 地址 / 私钥禁令与 print( 禁令逐字不动。
        final bool saveDiagnosticPath = path.endsWith('room_save_syncer.dart') ||
            path.endsWith('room_controller.dart') ||
            path.endsWith('main.dart');
        if (saveDiagnosticPath) {
          for (final Match m in RegExp(r'debugPrint\([^\n]*').allMatches(s)) {
            expect(
              m.group(0),
              contains('[SAVE]'),
              reason: '$path 的 debugPrint 必须带 [SAVE] 诊断前缀',
            );
          }
        } else {
          expect(s.contains('debugPrint'), isFalse,
              reason: '$path 不得 debugPrint');
        }
        for (final String banned in <String>[
          '203.0.113.10', 'deploy_key', 'BEGIN RSA PRIVATE KEY',
        ]) {
          expect(s.contains(banned), isFalse,
              reason: '$path 不得硬编码 $banned');
        }
      }
    });
  });
}
