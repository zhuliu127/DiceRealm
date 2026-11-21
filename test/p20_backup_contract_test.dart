// ============================================================
// test/p20_backup_contract_test.dart — P20 QA 契约 C/D 组
//
// 严过关（QA）独立编写。覆盖设计 §10.1 的「云端全量存档 / 同步语义」与
// 失败口径，全部用**内存 transport 逐条记录请求**，断言的是"发出去的
// 到底是什么"，不是"代码里有没有这个函数"：
//
//   D15 20 键权威快照逐键断言（含 privateBySeat）；KP 只走 /backup，绝不 POST /state
//   D16 seq 严格递增、stale 不覆盖不弹错不重试风暴；savedAt 只展示不参与冲突
//   D17 cloudSeq > localSeq：必须 newerConfirm 显式确认才 adoptSave；
//       未确认不覆盖、不伪造成功、不抬 seq；newerKeep 按 F6 如实提示
//   D18 玩家零云端全量上传/下载；exportSave()==null / importSave() no-op 不变
//   D19 N-3：RemoteSession / CloudRemoteSession 收 savesync 写 share/<code>/latest，
//       且 _tagSave 带 meta.role / meta.seat / members[].self
//       （用 f.stateOf(seat) 真实裁剪态夹具，不用 hostState()）
//   D20 finalizeOnLeave：先 /backup 再 /suspend，顺序不可反；只捕获纯数据
//   C13 bad_token/not_found/room_suspended/too_large → F2/F3/F4/F6 固定文案
//   C14 textScaler 1.0/1.3/1.5/2.0 无溢出；钳制只包固定尺寸子树
// ============================================================

import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;

import 'package:dice_realm/domain/js_compat.dart' show asList, asMap, jsStr;
import 'package:dice_realm/domain/room_types.dart'
    show EvtEnvelope, RoomEvt, RoomRole, SyncEnvelope;
import 'package:dice_realm/net/cloud_room.dart'
    show
        CloudHttpResponse,
        CloudHttpTransport,
        CloudRoomClient,
        CloudSocket,
        cloudDeviceId,
        cloudHttp,
        cloudSocketFactory;
import 'package:dice_realm/net/cloud_room_backup.dart'
    show
        BackupFetchResult,
        BackupWriteResult,
        CloudBackupContext,
        CloudBackupService,
        activeCloudBackupContext,
        armCloudBackup,
        clearActiveCloudBackup,
        cloudBackupClock,
        cloudBackupSink,
        errorKeyOfResponse,
        finalizeOnLeave,
        installCloudBackupRuntime,
        resetCloudBackupThrottle,
        resumeErrorText;
import 'package:dice_realm/net/lan_client.dart' show LanClient;
import 'package:dice_realm/repo/cloud_device_id.dart'
    show DeviceIdStorage, MemoryDeviceIdStorage, deviceIdStorage;
import 'package:dice_realm/repo/recent_room_credential.dart'
    show
        MemoryRecentCredentialStorage,
        RecentCredentialStorage,
        RecentRoomCredential,
        recentCredentialStore;
import 'package:dice_realm/repo/room_save_store.dart'
    show InMemoryRoomSaveStore;
import 'package:dice_realm/ui/room/room_boot.dart' show bootLocalRoom;
import 'package:dice_realm/ui/room/room_net_factory.dart' show RoomNetFactory;
import 'package:dice_realm/ui/room/room_resume.dart'
    show ResumeRunResult, RoomResumeService;
import 'package:dice_realm/ui/room/room_save_syncer.dart' show RoomSaveSyncer;
import 'package:dice_realm/ui/room/room_session_cloud.dart'
    show CloudRemoteSession;
import 'package:dice_realm/ui/room/room_session_remote.dart' show RemoteSession;
import 'package:dice_realm/ui/room/resume_mode_dialog.dart'
    show
        ResumeDialogKeys,
        ResumeFailAction,
        ResumeMode,
        showCloudNewerDialog,
        showResumeFailedDialog,
        showResumeModeDialog;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_ui_harness.dart' show RoomUiFixture;

// ------------------------------------------------------------
// 内存替身
// ------------------------------------------------------------

class _Req {
  const _Req(this.url, this.body);

  final Uri url;
  final Map<String, Object?> body;
}

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

/// 内存 socket：连上时推 [firstFrame]，之后可用 [pushRaw] 继续投帧。
class _PushSocket implements CloudSocket {
  _PushSocket(this.firstFrame);

  final Map<String, Object?> firstFrame;
  final List<String> urls = <String>[];
  void Function(String)? _onText;

  @override
  set onText(void Function(String text)? v) => _onText = v;

  @override
  set onClosed(void Function()? v) {}

  @override
  Future<void> connect(String url) async {
    urls.add(url);
    _onText?.call(jsonEncode(firstFrame));
  }

  @override
  void send(String text) {}

  @override
  Future<void> close() async {}

  void pushRaw(String text) => _onText?.call(text);
}

/// 一台"真服务端语义"的内存 /backup 端点：seq 单调递增才覆盖，否则 stale。
class _BackupServer implements CloudHttpTransport {
  int _seq = -1;
  String _payload = '';
  int _savedAt = 0;
  final List<_Req> log = <_Req>[];
  bool failWrites = false;

  @override
  Future<CloudHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    log.add(_Req(url, body));
    final String p = url.path;
    if (p.endsWith('/backup/read')) {
      if (_seq < 0) {
        return const CloudHttpResponse(
            ok: false,
            status: 404,
            json: <String, Object?>{'error': 'no_backup'});
      }
      return CloudHttpResponse(ok: true, status: 200, json: <String, Object?>{
        'ok': true,
        'seq': _seq,
        'payload': _payload,
        'savedAt': _savedAt,
      });
    }
    if (p.endsWith('/backup')) {
      if (failWrites) {
        return const CloudHttpResponse(
            ok: false, status: 413, json: <String, Object?>{'error': 'too_large'});
      }
      final int incoming = (body['seq'] as num?)?.toInt() ?? 0;
      final String payload = body['payload'] as String? ?? '';
      if (incoming <= _seq) {
        return CloudHttpResponse(ok: true, status: 200, json: <String, Object?>{
          'ok': true,
          'seq': _seq,
          'savedAt': _savedAt,
          'stale': true,
        });
      }
      _seq = incoming;
      _payload = payload;
      _savedAt = 1700000000000 + incoming;
      return CloudHttpResponse(ok: true, status: 200, json: <String, Object?>{
        'ok': true,
        'seq': _seq,
        'savedAt': _savedAt,
      });
    }
    if (p.endsWith('/resume')) {
      return CloudHttpResponse(
          ok: true, status: 200, json: const <String, Object?>{'ok': true});
    }
    if (p.endsWith('/suspend')) {
      return CloudHttpResponse(
          ok: true, status: 200, json: const <String, Object?>{'ok': true});
    }
    if (p.endsWith('/join')) {
      return CloudHttpResponse(ok: true, status: 200, json: <String, Object?>{
        'ok': true,
        'code': 'ab12cd',
        'mtoken': 'MT-NEW',
        'role': RoomRole.player,
        'seat': 'p1',
        'joinKind': 'reconnect',
      });
    }
    return CloudHttpResponse(
        ok: true, status: 200, json: const <String, Object?>{'ok': true});
  }

  List<String> get paths => <String>[for (final _Req r in log) r.url.path];
}

CloudHttpResponse _ok([Map<String, Object?> json = const <String, Object?>{}]) =>
    CloudHttpResponse(
        ok: true, status: 200, json: <String, Object?>{'ok': true, ...json});

Future<Map<String, Object?>> _realSave(String code, {String name = '本机档'}) async {
  final boot = await bootLocalRoom(code: code, name: name, nickname: '老K');
  final save = boot.session.exportSave();
  boot.dispose();
  return save!;
}

/// 静态红线检查必须只看**代码**，不能把注释里的反例说明当成命中。
/// 逐行去掉 `//` 行注释（含 `///` 文档注释），同时不误伤字符串里的 `//`。
String _codeOnly(String src) {
  final StringBuffer out = StringBuffer();
  for (final String line in src.split('\n')) {
    bool inString = false;
    bool escaped = false;
    int cut = -1;
    for (int i = 0; i < line.length; i++) {
      final int c = line.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == 0x5C) {
        escaped = true;
        continue;
      }
      if (c == 0x27 || c == 0x22) {
        inString = !inString;
        continue;
      }
      if (!inString && c == 0x2F && i + 1 < line.length &&
          line.codeUnitAt(i + 1) == 0x2F) {
        cut = i;
        break;
      }
    }
    out.writeln(cut >= 0 ? line.substring(0, cut) : line);
  }
  return out.toString();
}

/// 让 fire-and-forget 的 unawaited(upload) 真正跑完。
Future<void> _drain() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const String kBase = 'https://relay.example.com/room';
const String kCode = 'ab12cd';
const String kHostToken = 'HT-QA-SECRET-9c21';
const String kDeviceId = 'fl-0001020304050607';

final CloudHttpTransport _origHttp = cloudHttp;
final CloudSocket Function() _origFactory = cloudSocketFactory;
final DeviceIdStorage _origDeviceStorage = deviceIdStorage;
final RecentCredentialStorage _origCredStore = recentCredentialStore;
final String _origCloudDeviceId = cloudDeviceId;
final bool _origNetwork = RoomNetFactory.networkEnabled;
final Object? _origSink = cloudBackupSink;
final int Function() _origClock = cloudBackupClock;

void main() {
  setUp(() {
    cloudHttp = _BackupServer();
    cloudSocketFactory =
        () => _PushSocket(const <String, Object?>{'k': 'host.ok'});
    deviceIdStorage = MemoryDeviceIdStorage();
    cloudDeviceId = '';
    recentCredentialStore = MemoryRecentCredentialStorage();
    RoomNetFactory.networkEnabled = false;
    cloudBackupSink = null;
    cloudBackupClock = () => 1700000000000;
    resetCloudBackupThrottle();
    clearActiveCloudBackup();
  });

  tearDown(() {
    cloudHttp = _origHttp;
    cloudSocketFactory = _origFactory;
    deviceIdStorage = _origDeviceStorage;
    cloudDeviceId = _origCloudDeviceId;
    recentCredentialStore = _origCredStore;
    RoomNetFactory.networkEnabled = _origNetwork;
    cloudBackupSink = _origSink as void Function(Map<String, Object?>)?;
    cloudBackupClock = _origClock;
    resetCloudBackupThrottle();
    clearActiveCloudBackup();
  });

  // ==========================================================
  // D15 20 键 payload / KP 只走 /backup
  // ==========================================================
  group('D15 云端全量存档 = host.save() 20 键', () {
    test('installCloudBackupRuntime 只发 /backup，payload 逐键 20 键且零令牌',
        () async {
      final _BackupServer server = _BackupServer();
      cloudHttp = server;
      final Map<String, Object?> save = await _realSave(kCode);
      save['seq'] = 137;
      installCloudBackupRuntime();
      armCloudBackup(CloudBackupContext(
        base: kBase,
        code: kCode,
        hostToken: kHostToken,
        deviceId: kDeviceId,
      ));
      cloudBackupSink!(save);
      await _drain();

      expect(server.paths, isNotEmpty, reason: 'KP 自动存档必须真的发一次 /backup');
      expect(server.paths.every((String p) => p.endsWith('/backup')), isTrue);
      expect(server.paths.where((String p) => p.contains('/state')), isEmpty,
          reason: 'KP 绝不 POST /state');
      expect(server.paths.where((String p) => p.endsWith('/backup/read')), isEmpty);
      final _Req req = server.log.single;
      expect(req.url.path, '/room/api/rooms/ab12cd/backup');
      expect(req.body.keys.toSet(), <String>{'hostToken', 'seq', 'payload'});
      expect(req.body['hostToken'], kHostToken);
      expect(req.body['seq'], 137);

      final Object? decoded = jsonDecode(req.body['payload']! as String);
      expect(decoded, isA<Map<dynamic, dynamic>>());
      final Map<String, Object?> payload =
          (decoded! as Map).cast<String, Object?>();
      expect(payload.keys.toSet(), <String>{
        'v', 'code', 'rules', 'savedAt', 'seq', 'stateSeq', 'meta',
        'members', 'chats', 'logs', 'dice', 'scene', 'combat',
        'sceneCheck', 'roundStarts', 'privateBySeat', 'requestsBySeat',
        'boardBySeat', 'localAssets', 'localActors',
      }, reason: 'payload 必须恰好是 host.save() 的 20 键权威快照');
      expect(payload['privateBySeat'], isNotNull);
      expect(payload['seq'], 137);
      expect(payload['code'], kCode);
      final String wire = req.body['payload']! as String;
      for (final String banned in <String>[
        'hostToken', 'mtoken', 'deviceId', kHostToken, kDeviceId,
        '203.0.113.10', 'id_ed25519',
      ]) {
        expect(wire.contains(banned), isFalse,
            reason: '备份 payload 不得含 $banned');
      }
    });

    test('CloudBackupService 四端点路径逐字正确，且不存在 /state 写路径',
        () async {
      final _RecordingHttp http = _RecordingHttp(
          (Uri url, Map<String, Object?> body) => _ok(<String, Object?>{
                'seq': 1,
                'payload': '{}',
                'savedAt': 1,
              }));
      final CloudBackupService svc = CloudBackupService(http: http);
      await svc.resumeRoom(kBase, 'AB12CD', kHostToken);
      await svc.upload(kBase, 'AB12CD', kHostToken, 1, '{}');
      await svc.fetch(kBase, 'AB12CD', kHostToken);
      await svc.suspend(kBase, 'AB12CD', kHostToken);
      expect(http.paths, <String>[
        '/room/api/rooms/ab12cd/resume',
        '/room/api/rooms/ab12cd/backup',
        '/room/api/rooms/ab12cd/backup/read',
        '/room/api/rooms/ab12cd/suspend',
      ], reason: '四个端点全部小写归一、路径逐字一致');
      expect(http.paths.where((String p) => p.contains('/state')), isEmpty);
      final String src = File('lib/net/cloud_room_backup.dart').readAsStringSync();
      expect(src.contains("'/state'") || src.contains('"/state"'), isFalse,
          reason: '客户端源码里根本不该出现 /state 路径字符串');
      expect(src.contains('registerRoom'), isFalse);
      expect(src.contains('newRoomCode'), isFalse);
    });

    test('cloudBackupSink 默认 null：RoomSaveSyncer.autoSave 零网络零异常',
        () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      final _BackupServer server = _BackupServer();
      cloudHttp = server;
      // 不 install、不 arm：默认 null sink + 空上下文。
      expect(cloudBackupSink, isNull);
      expect(activeCloudBackupContext, isNull);
      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: f.controllerOf('host'),
        session: f.sessionOf('host'),
      );
      final bool ok = await syncer.autoSave(reason: 'qa');
      expect(ok, isTrue, reason: 'KP 自动存档本身必须成功');
      await _drain();
      expect(server.log, isEmpty,
          reason: '未装运行时不得发任何云端请求');
    });
  });

  // ==========================================================
  // D16 seq / stale / savedAt
  // ==========================================================
  group('D16 seq 单调 + stale 不覆盖', () {
    test('seq 严格递增才覆盖；更小/相同 seq 返回 stale:true 且不覆盖、不弹错',
        () async {
      final _BackupServer server = _BackupServer();
      final CloudBackupService svc = CloudBackupService(http: server);
      final BackupWriteResult a =
          await svc.upload(kBase, kCode, kHostToken, 10, 'V10');
      expect(a.ok, isTrue);
      expect(a.seq, 10);
      expect(a.stale, isFalse);

      final BackupWriteResult b =
          await svc.upload(kBase, kCode, kHostToken, 12, 'V12');
      expect(b.seq, 12);
      expect(b.stale, isFalse);

      for (final int seq in <int>[11, 12, 2]) {
        final BackupWriteResult s =
            await svc.upload(kBase, kCode, kHostToken, seq, 'SHOULD-NOT-STICK');
        expect(s.ok, isTrue, reason: 'stale 是正常结果，不能当失败');
        expect(s.stale, isTrue);
        expect(s.seq, 12, reason: '必须回已存 seq');
        expect(s.errorText, isEmpty, reason: 'stale 不弹错');
        expect(s.errorKey, isEmpty);
      }
      final BackupFetchResult got =
          await svc.fetch(kBase, kCode, kHostToken);
      expect(got.ok, isTrue);
      expect(got.seq, 12);
      expect(got.payload, 'V12', reason: '更小 seq 绝不覆盖');
      expect(server.log, hasLength(6),
          reason: '5 次 upload + 1 次 fetch = 6，不得有重试风暴');
    });

    test('installCloudBackupRuntime 节流：同 seq 不重传，<5s 不重传', () async {
      final _BackupServer server = _BackupServer();
      cloudHttp = server;
      int now = 1700000000000;
      cloudBackupClock = () => now;
      installCloudBackupRuntime();
      armCloudBackup(CloudBackupContext(
          base: kBase, code: kCode, hostToken: kHostToken));
      final Map<String, Object?> save = await _realSave(kCode);

      save['seq'] = 1;
      cloudBackupSink!(save);
      await _drain();
      expect(server.paths, hasLength(1), reason: '首包必须发');
      cloudBackupSink!(save);
      await _drain();
      expect(server.paths, hasLength(1), reason: '同一 seq 绝不重传');

      save['seq'] = 2;
      cloudBackupSink!(save);
      await _drain();
      expect(server.paths, hasLength(1), reason: '<5s 节流窗口内不重传');

      now += 5000;
      save['seq'] = 3;
      cloudBackupSink!(save);
      await _drain();
      expect(server.paths, hasLength(2), reason: '越过 5s 窗口后必须真发');
      // 末次全量档已缓存进上下文，供 finalizeOnLeave 在 dispose 后使用。
      final CloudBackupContext? ctx = activeCloudBackupContext;
      expect(ctx, isNotNull);
      expect(ctx!.seq, 3);
      expect(ctx.payload, isNotEmpty);
    });

    test('savedAt 只展示不参与冲突判定：savedAt 极大但 seq 相等 → 不弹覆盖确认',
        () async {
      final Map<String, Object?> local = await _realSave(kCode);
      local['seq'] = 7;
      final _RecordingHttp http = _RecordingHttp((Uri url, Map<String, Object?> b) {
        if (url.path.endsWith('/resume')) return _ok();
        if (url.path.endsWith('/backup/read')) {
          return _ok(<String, Object?>{
            'seq': 7, // 与本机相等
            'payload': jsonEncode(local),
            'savedAt': 9999999999999, // 云端"时间"远超本机
          });
        }
        return _ok(<String, Object?>{'seq': 7});
      });
      cloudHttp = http;
      cloudSocketFactory =
          () => _PushSocket(const <String, Object?>{'k': 'host.ok'});
      final cred = RecentRoomCredential(
        roomCode: kCode,
        base: kBase,
        hostToken: kHostToken,
        deviceId: kDeviceId,
        role: RoomRole.kp,
        seat: 'host',
        mode: 'cloud',
      );
      int confirmCalls = 0;
      final RoomResumeService service = RoomResumeService(
        store: InMemoryRoomSaveStore(),
        backup: CloudBackupService(http: http),
        clock: () => 1700000010000,
      );
      final ResumeRunResult r = await service.run(
        local,
        cred,
        ResumeMode.cloud,
        confirmCloudNewer: (int cloudSeq, int localSeq) async {
          confirmCalls++;
          return true;
        },
      );
      expect(r.ok, isTrue, reason: r.errorText);
      expect(confirmCalls, 0,
          reason: 'savedAt 不参与冲突：seq 相等就绝不能弹覆盖确认');
      expect(http.paths.where((String p) => p.endsWith('/backup')).length, 0,
          reason: 'seq 相等也不该偷偷抬 seq 上传');
      r.boot?.dispose();
    });
  });

  // ==========================================================
  // D17 云端更新 → K4 显式确认
  // ==========================================================
  group('D17 cloudSeq > localSeq 必须显式确认', () {
    _RecordingHttp newerHttp(Map<String, Object?> local, Map<String, Object?> cloud) {
      return _RecordingHttp((Uri url, Map<String, Object?> body) {
        if (url.path.endsWith('/resume')) return _ok();
        if (url.path.endsWith('/backup/read')) {
          return _ok(<String, Object?>{
            'seq': 9,
            'payload': jsonEncode(cloud),
            'savedAt': 1700000011111,
          });
        }
        return _ok(<String, Object?>{'seq': 9});
      });
    }

    Future<ResumeRunResult> runWithConfirm(bool adopt) async {
      final Map<String, Object?> local = await _realSave(kCode, name: '本机档');
      local['seq'] = 5;
      final Map<String, Object?> cloud =
          await _realSave(kCode, name: '云端档');
      cloud['seq'] = 9;
      final _RecordingHttp http = newerHttp(local, cloud);
      cloudHttp = http;
      cloudSocketFactory =
          () => _PushSocket(const <String, Object?>{'k': 'host.ok'});
      final cred = RecentRoomCredential(
        roomCode: kCode,
        base: kBase,
        hostToken: kHostToken,
        deviceId: kDeviceId,
        role: RoomRole.kp,
        seat: 'host',
        mode: 'cloud',
      );
      int calls = 0;
      final RoomResumeService service = RoomResumeService(
        store: InMemoryRoomSaveStore(),
        backup: CloudBackupService(http: http),
        clock: () => 1700000010000,
      );
      final ResumeRunResult r = await service.run(
        local,
        cred,
        ResumeMode.cloud,
        confirmCloudNewer: (int cloudSeq, int localSeq) async {
          calls++;
          expect(cloudSeq, 9);
          expect(localSeq, 5);
          return adopt;
        },
      );
      expect(calls, 1, reason: 'cloudSeq>localSeq 必须调用 KP 显式确认');
      return r;
    }

    test('未确认（newerKeep）→ 不覆盖本机、不伪造成功、不抬 seq、F6 如实提示',
        () async {
      final ResumeRunResult r = await runWithConfirm(false);
      expect(r.ok, isTrue);
      expect(r.boot, isNotNull);
      final Map<String, Object?> meta =
          asMap(r.boot!.host.state['meta']);
      expect(jsStr(meta['name']), '本机档',
          reason: '未确认绝不能把云端档灌进本机权威态');
      expect(r.banner, contains('本次未备份到云端'),
          reason: 'newerKeep 后续上传按 F6 如实提示');
      expect(r.banner.contains('已同步'), isFalse);
      expect(r.banner.contains('进度：云端第'), isFalse);
      r.boot!.dispose();
    });

    test('确认（newerConfirm）→ adoptSave，本机档被云端档覆盖', () async {
      final ResumeRunResult r = await runWithConfirm(true);
      expect(r.ok, isTrue);
      final Map<String, Object?> meta =
          asMap(r.boot!.host.state['meta']);
      expect(jsStr(meta['name']), '云端档',
          reason: 'KP 明确确认后必须 adoptSave 云端档');
      r.boot!.dispose();
    });

    testWidgets('showCloudNewerDialog：newerConfirm=true / newerKeep=false',
        (WidgetTester tester) async {
      for (final bool tapConfirm in <bool>[true, false]) {
        bool? got;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(builder: (BuildContext ctx) => ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                got = await showCloudNewerDialog(
                    ctx, cloudSeq: 9, localSeq: 5);
              },
              child: const Text('OPEN'),
            )),
          ),
        ));
        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();
        expect(find.byKey(ResumeDialogKeys.newerRoot), findsOneWidget);
        expect(find.byKey(ResumeDialogKeys.newerConfirm), findsOneWidget);
        expect(find.byKey(ResumeDialogKeys.newerKeep), findsOneWidget);
        await tester.tap(find.byKey(tapConfirm
            ? ResumeDialogKeys.newerConfirm
            : ResumeDialogKeys.newerKeep));
        await tester.pumpAndSettle();
        expect(got, tapConfirm);
      }
    });
  });

  // ==========================================================
  // D18 玩家零请求 + 非权威契约
  // ==========================================================
  group('D18 玩家零云端全量请求', () {
    test('RoomResumeService 玩家云分支只发 /join，零 /backup /state', () async {
      RoomNetFactory.networkEnabled = true;
      final _RecordingHttp http = _RecordingHttp(
          (Uri url, Map<String, Object?> body) => _ok(<String, Object?>{
                'code': kCode,
                'mtoken': 'MT-1',
                'role': RoomRole.player,
                'seat': 'p2',
                'joinKind': 'reconnect',
              }));
      cloudHttp = http;
      cloudSocketFactory =
          () => _PushSocket(const <String, Object?>{'k': 'ready', 'seat': 'p2'});
      final Map<String, Object?> save = await _realSave(kCode);
      final cred = RecentRoomCredential(
        roomCode: kCode,
        base: kBase,
        deviceId: kDeviceId,
        role: RoomRole.player,
        seat: 'p2',
        mode: 'cloud',
      );
      final service = RoomResumeService(
        store: InMemoryRoomSaveStore(),
        backup: CloudBackupService(http: http),
        clock: () => 1700000000000,
      );
      final ResumeRunResult r =
          await service.run(save, cred, ResumeMode.cloud);
      expect(r.ok, isTrue, reason: r.errorText);
      expect(r.cloudJoin, isNotNull);
      expect(r.cloudJoin!.session!.seat, 'p2');
      expect(http.paths.where((String p) => p.endsWith('/join')), hasLength(1));
      expect(http.paths.where((String p) => p.contains('/backup')), isEmpty);
      expect(http.paths.where((String p) => p.contains('/state')), isEmpty);
      expect(http.log.single.body['deviceId'], kDeviceId);
      await r.cloudJoin!.session!.closeConnection();
    });

    test('RemoteSession / CloudRemoteSession 非权威契约不变', () async {
      final LanClient lan = LanClient(
        base: 'http://127.0.0.1:1',
        seat: 'p1',
        code: 'AB12CD',
        role: RoomRole.player,
      );
      final RemoteSession rs = RemoteSession(client: lan, roomCode: 'AB12CD');
      expect(rs.exportSave(), isNull, reason: '玩家不能导出权威全量档');
      final Map<String, Object?> before = Map<String, Object?>.from(rs.state);
      rs.importSave(<String, Object?>{'meta': <String, Object?>{'code': 'X'}});
      expect(rs.state.length, before.length,
          reason: 'importSave 必须是 no-op');
      rs.dispose();

      final CloudRoomClient cc = CloudRoomClient(
        base: kBase,
        code: kCode,
        role: RoomRole.player,
        deviceId: kDeviceId,
        socket: _PushSocket(const <String, Object?>{'k': 'ready', 'seat': 'p1'}),
      );
      final CloudRemoteSession crs =
          CloudRemoteSession(client: cc, roomCode: kCode);
      expect(crs.exportSave(), isNull);
      final Map<String, Object?> beforeCloud =
          Map<String, Object?>.from(crs.state);
      crs.importSave(<String, Object?>{'meta': <String, Object?>{'code': 'X'}});
      expect(crs.state.length, beforeCloud.length);
      crs.dispose();
      await cc.dispose();
    });
  });

  // ==========================================================
  // D19 N-3 savesync 落盘（真实裁剪态夹具）
  // ==========================================================
  group('D19 N-3 savesync 写 share/<code>/latest', () {
    test('RemoteSession 收到 savesync → 落盘 + _tagSave 三处视角标记', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      // ★ 用真实裁剪态（不是 hostState()）：P4 的 stateFor(seat) 产物。
      final Map<String, Object?> clipped = f.stateOf('p1');
      final String code = jsStr(asMap(clipped['meta'])['code']);
      expect(code, isNotEmpty);

      final LanClient lan = LanClient(
        base: 'http://127.0.0.1:1',
        seat: 'p1',
        code: code,
        role: RoomRole.player,
      );
      final RemoteSession rs = RemoteSession(client: lan, roomCode: code);
      // 先把裁剪态真正灌进会话（否则 session.state 是空壳，_saveOwnCard 语义不对）。
      lan.deliverForTest(SyncEnvelope(10, clipped).toJson());
      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: f.controllerOf('p1'),
        session: rs,
      );
      final Map<String, Object?> save = <String, Object?>{
        'v': 2,
        'code': code,
        'savedAt': 777,
        'seq': 11,
        'meta': asMap(clipped['meta']),
        'members': asList(clipped['members']),
        'chats': asList(clipped['chats']),
        'logs': asList(clipped['logs']),
        'dice': asList(clipped['dice']),
      };
      lan.deliverForTest(EvtEnvelope(11, RoomEvt.saveSync, <String, Object?>{
        'save': save,
      }).toJson());
      await _drain();

      final String key = 'share/$code/latest';
      final Map<String, Object?>? stored = f.saves.get(key);
      expect(stored, isNotNull,
          reason: 'RemoteSession 必须把 KP 广播的快照写进 $key');
      expect(syncer.receivedCount, 1);
      final Map<String, Object?> meta = asMap(stored!['meta']);
      expect(meta['role'], RoomRole.player, reason: '_tagSave 必须打 meta.role');
      expect(meta['seat'], 'p1', reason: '_tagSave 必须打 meta.seat');
      final bool selfTagged = asList(stored['members']).any((Object? m) =>
          asMap(m)['seat'] == 'p1' && asMap(m)['self'] == true);
      expect(selfTagged, isTrue, reason: '_tagSave 必须给本座位打 members[].self');
      rs.dispose();
    });

    test('CloudRemoteSession 收到 savesync → 落盘 + 视角标记', () async {
      final f = RoomUiFixture();
      await f.boot(inGame: true);
      final Map<String, Object?> clipped = f.stateOf('p1');
      final String code = jsStr(asMap(clipped['meta'])['code']);

      final _PushSocket sock =
          _PushSocket(const <String, Object?>{'k': 'ready', 'seat': 'p1'});
      cloudHttp = _RecordingHttp((Uri url, Map<String, Object?> body) =>
          _ok(<String, Object?>{
            'code': code,
            'mtoken': 'MT-CLOUD',
            'role': RoomRole.player,
            'seat': 'p1',
            'joinKind': 'reconnect',
          }));
      final CloudRoomClient cc = CloudRoomClient(
        base: kBase,
        code: code,
        role: RoomRole.player,
        deviceId: kDeviceId,
        socket: sock,
      );
      final CloudJoinResultHolder holder = CloudJoinResultHolder();
      holder.ok = (await cc.connect()).ok;
      expect(holder.ok, isTrue);
      final CloudRemoteSession crs =
          CloudRemoteSession(client: cc, roomCode: code);
      sock.pushRaw(jsonEncode(SyncEnvelope(10, clipped).toJson()));
      final RoomSaveSyncer syncer = RoomSaveSyncer(
        controller: f.controllerOf('p1'),
        session: crs,
      );
      final Map<String, Object?> save = <String, Object?>{
        'v': 2,
        'code': code,
        'savedAt': 888,
        'seq': 11,
        'meta': asMap(clipped['meta']),
        'members': asList(clipped['members']),
        'chats': <Object?>[],
        'logs': <Object?>[],
        'dice': <Object?>[],
      };
      sock.pushRaw(jsonEncode(EvtEnvelope(11, RoomEvt.saveSync,
          <String, Object?>{'save': save}).toJson()));
      await _drain();

      final Map<String, Object?>? stored = f.saves.get('share/$code/latest');
      expect(stored, isNotNull,
          reason: 'CloudRemoteSession 必须落盘 share/$code/latest');
      expect(syncer.receivedCount, 1);
      expect(asMap(stored!['meta'])['role'], RoomRole.player);
      expect(asMap(stored['meta'])['seat'], 'p1');
      expect(
          asList(stored['members']).any((Object? m) =>
              asMap(m)['seat'] == 'p1' && asMap(m)['self'] == true),
          isTrue);
      crs.dispose();
      await cc.dispose();
    });
  });

  // ==========================================================
  // D20 finalizeOnLeave 顺序 / 纯数据
  // ==========================================================
  group('D20 finalizeOnLeave 先 /backup 后 /suspend', () {
    test('成功路径：调用序列逐字为 [backup, suspend]', () async {
      final _BackupServer server = _BackupServer();
      final CloudBackupService svc = CloudBackupService(http: server);
      await svc.finalizeOnLeave(CloudBackupContext(
        base: kBase,
        code: kCode,
        hostToken: kHostToken,
        seq: 137,
        payload: '{"v":2}',
      ));
      expect(server.paths, <String>[
        '/room/api/rooms/ab12cd/backup',
        '/room/api/rooms/ab12cd/suspend',
      ], reason: '顺序不可反：末次备份必须先于挂起');
      expect(server.paths.where((String p) => p.contains('/state')), isEmpty);
    });

    test('/backup 明确失败（413）也要先失败再 /suspend，不跳过不反序', () async {
      final _BackupServer server = _BackupServer()..failWrites = true;
      final CloudBackupService svc = CloudBackupService(http: server);
      await svc.finalizeOnLeave(CloudBackupContext(
        base: kBase,
        code: kCode,
        hostToken: kHostToken,
        seq: 137,
        payload: '{"v":2}',
      ));
      expect(server.paths, <String>[
        '/room/api/rooms/ab12cd/backup',
        '/room/api/rooms/ab12cd/suspend',
      ]);
    });

    test('顶层 finalizeOnLeave() 取出即清空；二次调用零请求；无效上下文不发',
        () async {
      final _BackupServer server = _BackupServer();
      cloudHttp = server;
      armCloudBackup(CloudBackupContext(
        base: kBase,
        code: kCode,
        hostToken: kHostToken,
        seq: 1,
        payload: '{"v":2}',
      ));
      await finalizeOnLeave();
      expect(activeCloudBackupContext, isNull, reason: '取出即清空，双路径只发一次');
      expect(server.paths, hasLength(2));
      await finalizeOnLeave();
      expect(server.paths, hasLength(2), reason: '第二次不得再发 backup+suspend');

      armCloudBackup(const CloudBackupContext(
          base: '', code: '', hostToken: '', payload: '{"v":2}'));
      await finalizeOnLeave();
      expect(server.paths, hasLength(2), reason: '无效上下文绝不发包');
    });

    test('只捕获纯数据、不引用 context；会话类型与 exit.kind 门禁在源码里',
        () {
      final String src =
          File('lib/net/cloud_room_backup.dart').readAsStringSync();
      final String code = _codeOnly(src);
      expect(code.contains('BuildContext'), isFalse,
          reason: '云端备份层代码不得引用 BuildContext（注释里的反例不算）');
      expect(code.contains('widget.'), isFalse);
      expect(code.contains("import 'package:flutter"), isFalse,
          reason: 'net 层不得依赖 Flutter 框架');
      final int start = code.indexOf('Future<void> finalizeOnLeave() async {');
      final String fn =
          code.substring(start, code.indexOf('\n}\n', start) + 3);
      expect(fn.contains(RegExp(r'\bcontext\b')), isFalse,
          reason: '顶层 finalizeOnLeave 不得引用 context');
      expect(fn.contains('activeCloudBackupContext'), isTrue);
      expect(fn.contains('clearActiveCloudBackup()'), isTrue);

      final String entry =
          File('lib/ui/room/room_entry_page.dart').readAsStringSync();
      expect(
          entry.contains(
              'if (!_exit.shouldLeave && widget.session is CloudHostingSession)'),
          isTrue,
          reason: '仅 _exit.kind==none 且云端 KP 才触发保活');
      expect(entry.contains('unawaited(finalizeOnLeave())'), isTrue);
      expect(entry.contains('clearActiveCloudBackup();'), isTrue,
          reason: '关房/结团/玩家/LAN 走 else 清上下文，不 suspend');
      final String boot =
          File('lib/ui/room/room_boot.dart').readAsStringSync();
      expect(boot.contains('clearActiveCloudBackup()'), isTrue,
          reason: 'LAN 开房必须清掉云端 KP 上下文，避免误 suspend');
    });
  });

  // ==========================================================
  // C13 失败文案 / 失败弹窗
  // ==========================================================
  group('C13 F2/F3/F4/F6 固定中文文案', () {
    test('bad_token/not_found/room_suspended/too_large 映射逐字正确', () {
      expect(resumeErrorText('bad_token', 'AB12CD'),
          contains('房主令牌已失效'));
      expect(resumeErrorText('bad_token', 'AB12CD'),
          contains('没能连回房间 AB12CD'));
      expect(resumeErrorText('not_found', 'AB12CD'),
          contains('房间已过期或已结束，无法连回原房号'));
      expect(resumeErrorText('room_suspended', 'AB12CD'),
          '房间已挂起，需 KP 先续玩');
      expect(resumeErrorText('too_large', 'AB12CD'),
          '本次进度未备份到云端，本机存档仍可用');
      expect(resumeErrorText('parse_failed', 'AB12CD'),
          '本次进度未备份到云端，本机存档仍可用');
      // 红线：失败分支零「已连回 / 已同步 / 进度：云端第 N 版」。
      for (final String key in <String>[
        'bad_token', 'not_found', 'room_suspended', 'too_large',
        'parse_failed', 'network', 'timeout', 'ws_closed', 'lan_not_found',
        'new_identity', 'no_backup', 'room_closed',
      ]) {
        final String text = resumeErrorText(key, 'AB12CD');
        expect(text.contains('已连回'), isFalse, reason: '$key 不得出现「已连回」');
        expect(text.contains('已同步'), isFalse, reason: '$key 不得出现「已同步」');
        expect(text.contains('进度：云端第'), isFalse,
            reason: '$key 不得出现「进度：云端第 N 版」');
      }
    });

    test('errorKeyOfResponse 把服务端 error 码透传给文案层', () {
      expect(
          errorKeyOfResponse(const CloudHttpResponse(
              ok: false,
              status: 403,
              json: <String, Object?>{'error': 'bad_token'})),
          'bad_token');
      expect(
          errorKeyOfResponse(const CloudHttpResponse(
              ok: false,
              status: 413,
              json: <String, Object?>{'error': 'too_large'})),
          'too_large');
      expect(
          errorKeyOfResponse(const CloudHttpResponse(
              ok: false, error: 'connection refused')),
          'network');
      expect(errorKeyOfResponse(_ok()), isEmpty);
    });

    testWidgets('showResumeFailedDialog 三按钮齐全，「仅本机离线副本」始终可选',
        (WidgetTester tester) async {
      for (final String key in <String>[
        'bad_token', 'not_found', 'room_suspended', 'too_large',
      ]) {
        ResumeFailAction? got;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(builder: (BuildContext ctx) => ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                got = await showResumeFailedDialog(ctx,
                    code: 'AB12CD', reason: resumeErrorText(key, 'AB12CD'));
              },
              child: const Text('OPEN'),
            )),
          ),
        ));
        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();
        expect(find.byKey(ResumeDialogKeys.failRoot), findsOneWidget);
        expect(find.byKey(ResumeDialogKeys.failReason), findsOneWidget);
        expect(find.byKey(ResumeDialogKeys.retry), findsOneWidget);
        expect(find.byKey(ResumeDialogKeys.failOffline), findsOneWidget,
            reason: '失败分支「仅本机离线副本」始终可选');
        expect(find.byKey(ResumeDialogKeys.failCancel), findsOneWidget);
        await tester.tap(find.byKey(ResumeDialogKeys.failOffline));
        await tester.pumpAndSettle();
        expect(got, ResumeFailAction.offline);
      }
    });
  });

  // ==========================================================
  // C14 textScaler 四档
  // ==========================================================
  group('C14 textScaler 1.0/1.3/1.5/2.0 无溢出', () {
    testWidgets('模式弹窗 / 失败弹窗 / 云端更新弹窗四档均无异常',
        (WidgetTester tester) async {
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      for (final double scale in <double>[1.0, 1.3, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final void Function(BuildContext) opener
            in <void Function(BuildContext)>[
          (BuildContext ctx) {
            showResumeFailedDialog(ctx,
                code: 'AB12CD', reason: resumeErrorText('not_found', 'AB12CD'));
          },
          (BuildContext ctx) {
            showCloudNewerDialog(ctx, cloudSeq: 9, localSeq: 5);
          },
          (BuildContext ctx) {
            showResumeModeDialog(ctx,
                code: 'AB12CD', defaultMode: ResumeMode.cloud);
          },
        ]) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: Builder(builder: (BuildContext ctx) => ElevatedButton(
                key: const Key('open'),
                onPressed: () => opener(ctx),
                child: const Text('OPEN'),
              )),
            ),
          ));
          await tester.tap(find.byKey(const Key('open')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull,
              reason: 'textScaler=$scale 下弹窗不得 RenderFlex overflow / 抛异常');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    });

    test('MediaQuery 钳制只包固定尺寸子树：无 ClipRect / 无页面级钳制', () {
      final String src =
          File('lib/ui/room/resume_mode_dialog.dart').readAsStringSync();
      final String code = _codeOnly(src);
      expect(code.contains('MediaQuery.withClampedTextScaling'), isTrue);
      expect(code.contains('maxScaleFactor: 1.0'), isTrue);
      expect(code.contains('ClipRect'), isFalse,
          reason: '禁止 ClipRect 硬裁（只看代码，注释里的禁令说明不算）');
      expect(code.contains('MediaQuery(data:'), isFalse,
          reason: '不得在页面/弹窗级整体钳制（只包控件子树）');
      expect(code.contains('SingleChildScrollView'), isTrue);
      expect(code.contains('MainAxisSize.min'), isTrue);
      // _clampFixed 只出现在定义 + 固定尺寸控件调用点上。
      final int clampUses = '_clampFixed('.allMatches(code).length;
      expect(clampUses, greaterThanOrEqualTo(6));
      final String entry =
          File('lib/ui/room/room_entry_page.dart').readAsStringSync();
      expect(entry.contains('withClampedTextScaling'), isFalse,
          reason: '入口页不得有页面级 textScaler 钳制');
      final String theme = File('lib/theme.dart').readAsStringSync();
      expect(theme.contains('withClampedTextScaling'), isFalse,
          reason: 'Theme 级不得钳制');
    });
  });
}

/// 保存 CloudRoomClient.connect() 的布尔结果，避免未使用变量告警。
class CloudJoinResultHolder {
  bool ok = false;
}
