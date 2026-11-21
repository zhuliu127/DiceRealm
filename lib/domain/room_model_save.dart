// ============================================================
// room_model_save.dart — 存档 / 恢复 / 角色卡白名单化（D21，S4.4）
//
//   extension RoomHostSave on RoomHost:
//     save()        —— **20 个顶层键**（v:2 / code / rules / savedAt / seq /
//                      stateSeq / meta / members / chats / logs / dice / scene /
//                      combat / sceneCheck / roundStarts / privateBySeat /
//                      requestsBySeat / boardBySeat / localAssets /
//                      localActors），逐字段照搬 room-model.js:6885-6905
//     savePayload() / adoptSave() / shareSheet()
//   纯函数：parseSave / restoreHost / playerViewFromSave /
//          resolveRoomCardPatch / sanitizeSheet / sanitizeSceneSteps
//
// ⚠️ 本文件是纯 Map ↔ Map 变换：只用 dart:convert，零文件读写、零平台 IO 库（C1/K7）。
//    savePayload() 用 jsonEncode（序列化成字符串，不是写文件）；落盘在 lib/repo。
// ⚠️ 角色卡白名单的**唯一实现**是 S4.3 已落地的 raSanitizeSheet /
//    raSanitizeSceneSteps（D19/D17 的真实逐字段实现，不是替身）；本文件只做
//    薄封装，把它们收敛成 D21 的对外签名（设计 §3.1），避免两份实现分叉。
// ⚠️ Q6 休眠项（EVT.REWIND / state.rewind / rollback.turn 分支）原样保留：
//    adoptSave 只把 rewind 置 null，不删任何枚举/分支；旧存档的 rewind 字段
//    经 emptyRoomState 仍存在（值 null），reduce 的 case EVT.REWIND 仍可达。
// ============================================================

import 'dart:convert';

import 'js_compat.dart';
import 'room_model_actions_room.dart' show raSanitizeSceneSteps;
import 'room_model_actions_sheet.dart' show raSanitizeSheet;
import 'room_model_host_core.dart';
import 'room_model_log.dart';
import 'room_model_state.dart';
import 'room_ports.dart';
import 'room_types.dart';

/// 深拷贝后收成 List（旧版 `clone(x || [])`）。
List<Object?> _cl(Object? v) => asList(roomClone(v));

/// seat → List 的私有累计表（旧版 `_privateBySeat`）。
Map<String, List<Object?>> _seatLists(Object? raw) {
  final out = <String, List<Object?>>{};
  asMap(roomClone(raw)).forEach((k, v) {
    out[k] = asList(v);
  });
  return out;
}

/// seat → 结构化请求列表（旧版 `_requestsBySeat`）。
Map<String, List<Map<String, Object?>>> _seatMapLists(Object? raw) {
  final out = <String, List<Map<String, Object?>>>{};
  asMap(roomClone(raw)).forEach((k, v) {
    out[k] = asList(v).map(asMap).toList();
  });
  return out;
}

/// seat → 手绘板（旧版 `_boardBySeat`）。
Map<String, Map<String, Object?>> _seatMaps(Object? raw) {
  final out = <String, Map<String, Object?>>{};
  asMap(roomClone(raw)).forEach((k, v) {
    out[k] = asMap(v);
  });
  return out;
}

extension RoomHostSave on RoomHost {
  /// 打包存档。**含 KP 私有内容**（要能续玩），但不含任何令牌 / 密码。
  ///
  /// 20 个顶层键、键序与旧版 `Host.prototype.save` 完全一致（P0-M12）。
  /// `TEMP_COMMIT` 是事件不是状态键，不进存档；`state.privates` / `requests`
  /// / `board` 由逐 seat 的三张表承载，也不单独进存档。
  Map<String, Object?> save() {
    final meta = asMap(state['meta']);
    return <String, Object?>{
      'v': 2,
      'code': jsTruthy(meta['code']) ? meta['code'] : '',
      'rules': jsTruthy(meta['rules']) ? meta['rules'] : 'coc7',
      'savedAt': now(),
      'seq': log.seq,
      'stateSeq': stateSeq,
      'meta': roomClone(meta),
      'members': roster.dump(),
      'chats': roomClone(state['chats']),
      'logs': roomClone(state['logs']),
      'dice': roomClone(state['dice']),
      'scene': roomClone(state['scene']),
      'combat': roomClone(state['combat']),
      'sceneCheck': roomClone(state['sceneCheck']),
      'roundStarts': roomClone(roundStarts),
      'privateBySeat': roomClone(privateBySeat),
      'requestsBySeat': roomClone(requestsBySeat),
      'boardBySeat': roomClone(boardBySeat),
      'localAssets': roomClone(localAssets),
      'localActors': roomClone(localActors),
    };
  }

  /// 存档的 JSON 字符串（序列化，不是落盘）。
  String savePayload() => jsonEncode(save());

  /// 把一份存档灌回本 Host（保持 RoomHost 对象引用稳定，UI 不必换对象）。
  ///
  /// · state 用 `emptyRoomState(meta)` 重建后逐键 clone（老 JSON 无损）；
  /// · 花名册重建时每成员跑一次 `migrateBodyStatus`（幂等、只迁 body，
  ///   不做全量重洗），并统一 `online=false` 等重连；
  /// · log 清空并把水位设回 save.seq；快照重置为单条；pending / rewind 清空。
  RoomHost adoptSave(Map<String, Object?> save) {
    final meta = asMap(save['meta']);
    state = emptyRoomState(meta);
    state['meta'] = roomClone(meta);
    state['members'] = _cl(save['members']);
    state['chats'] = _cl(save['chats']);
    state['logs'] = _cl(save['logs']);
    state['dice'] = _cl(save['dice']);
    state['scene'] = save['scene'] == null ? null : roomClone(save['scene']);
    state['combat'] = save['combat'] == null ? null : roomClone(save['combat']);
    state['sceneCheck'] =
        save['sceneCheck'] == null ? null : roomClone(save['sceneCheck']);
    state['seq'] = jsNum(save['seq']);

    roster = RoomRoster();
    for (final mRaw in asList(save['members'])) {
      final m = asMap(mRaw);
      final seat = jsStr(m['seat']);
      if (seat.isEmpty) continue;
      final rec = asMap(roomClone(m));
      final sheet = rec['sheet'];
      if (sheet is Map && sheet['status'] is Map) {
        // 老存档 body='濒死'/'昏迷' 的一次性迁移（不改其余字段）。
        migrateBodyStatus(asMap(asMap(sheet)['status']));
      }
      rec['online'] = false;
      roster.bySeat[seat] = rec;
      if (!roster.order.contains(seat)) roster.order.add(seat);
    }

    roundStarts
      ..clear()
      ..addAll(_cl(save['roundStarts']).map(asMap).toList());
    privateBySeat
      ..clear()
      ..addAll(_seatLists(save['privateBySeat']));
    requestsBySeat
      ..clear()
      ..addAll(_seatMapLists(save['requestsBySeat']));
    boardBySeat
      ..clear()
      ..addAll(_seatMaps(save['boardBySeat']));
    localAssets
      ..clear()
      ..addAll(_cl(save['localAssets']).map(asMap).toList());
    localActors
      ..clear()
      ..addAll(_cl(save['localActors']).map(asMap).toList());

    stateSeq = jsNum(save['stateSeq']).toInt();
    log.items.clear();
    log.truncated = 0;
    log.seq = jsNum(save['seq']).toInt();
    snapshots
      ..clear()
      ..add(RoomSnapshot(log.seq, asMap(roomClone(state))));
    pending.clear();
    rewind = null;
    sanLostThisRound.clear();
    roundStartSan.clear();
    fadedArm.clear();
    fireUsed.clear();
    return this;
  }

  /// char.share（INTENT.CHAR）的完整结算（旧版 :1435-1490）。
  ///
  /// 与 S4.3 的 ACT 别名 `roomActionCharShare` 不同：这里是**整体覆盖** sheet，
  /// 走 `sanitizeSheet` 白名单，且贴回权威端产生的 tempStatus / items
  /// （防玩家重连补报把 KP 发的临时状态清空），并写 runtime 现值。
  List<SendPlan> shareSheet(
    String role,
    String seat,
    Map<String, Object?>? mem,
    Map<String, Object?> p,
  ) {
    final out = <SendPlan>[];
    if (role != RoomRole.player) {
      pushInto(out, sysTo(seat, '旁观者不需要上报角色卡'));
      return out;
    }
    // 权威端守卫：不信任客户端过滤，按上报摘要再判一次撕卡。
    final repSheet = asMap(p['sheet']);
    final repStatus = asMap(repSheet['status']);
    final repMental = repSheet['mental'] is List
        ? asList(repSheet['mental']).map(jsStr).toList()
        : (repSheet['mental'] != null
            ? <String>[jsStr(repSheet['mental'])]
            : <String>[]);
    if (repStatus['body'] == '死亡' || repMental.contains('永久疯狂')) {
      pushInto(out, sysTo(seat, '该角色已撕卡（死亡/永久疯狂），不能进入房间'));
      return out;
    }

    if (mem != null) {
      final name = cleanText(p['name'], 40);
      if (name.isNotEmpty) mem['charName'] = name;
      if (jsTruthy(p['id'])) mem['charId'] = p['id'];

      final prevSheet = asMap(mem['sheet']);
      final prevTs = prevSheet['tempStatus'] is List
          ? roomClone(prevSheet['tempStatus'])
          : <Object?>[];
      final prevItems = prevSheet['items'] is List
          ? roomClone(prevSheet['items'])
          : <Object?>[];
      final nextSheet = sanitizeSheet(p, mem);
      nextSheet['tempStatus'] = prevTs;
      nextSheet['items'] = prevItems;
      mem['sheet'] = nextSheet;

      final nst = asMap(nextSheet['status']);
      final runtime = mem['runtime'] is Map
          ? asMap(mem['runtime'])
          : <String, Object?>{};
      mem['runtime'] = runtime;
      const pairs = <List<String>>[
        <String>['currentHP', 'hp'],
        <String>['maxHP', 'hpMax'],
        <String>['currentMP', 'mp'],
        <String>['maxMP', 'mpMax'],
        <String>['currentSAN', 'san'],
        <String>['maxSAN', 'sanMax'],
      ];
      for (final pair in pairs) {
        final v = nst[pair[0]];
        if (v != null) runtime[pair[1]] = v;
      }
    }
    out.addAll(syncMembers());
    return out;
  }
}

/// 解析存档载荷（对象或 JSON 字符串）→ 存档对象；失败返回 null。
Map<String, Object?>? parseSave(Object? payload) {
  if (!jsTruthy(payload)) return null;
  if (payload is Map) return payload.cast<String, Object?>();
  try {
    final decoded = jsonDecode(jsStr(payload));
    if (decoded is Map) return decoded.cast<String, Object?>();
    return null;
  } catch (_) {
    return null;
  }
}

/// 从存档重建一个 Host（续玩 / 玩家侧裁剪）。非法载荷返回 null。
RoomHost? restoreHost(Object? saveOrPayload, [RoomHostOptions? opts]) {
  final save = parseSave(saveOrPayload);
  if (save == null) return null;
  final o = opts;
  // 旧版 `new Host(Object.assign({meta: save.meta || {}}, opts))`：
  // meta 以存档为准，其余依赖注入参数由 opts 覆盖。
  final hostOpts = RoomHostOptions(
    meta: asMap(save['meta']),
    logCap: o?.logCap ?? 400,
    snapshotEvery: o?.snapshotEvery ?? 20,
    snapshotLimit: o?.snapshotLimit ?? 20,
    now: o?.now,
    rng: o?.rng,
    rules: o?.rules,
    madness: o?.madness,
    saveStore: o?.saveStore,
  );
  return RoomHost(hostOpts)..adoptSave(save);
}

/// 玩家侧从服务器存档拿到的**裁剪后视图**（契约 §6.3）。
///
/// 复用 Host.syncFor 的裁剪规则 —— 与增量 / 全量同步口径完全一致；
/// 返回的信封可直接喂给 `RoomClient.receive`。
SyncEnvelope? playerViewFromSave(Object? saveOrPayload, String seat) {
  final h = restoreHost(saveOrPayload);
  if (h == null) return null;
  return h.syncFor(seat);
}

/// 把房间侧的 patch 落到本机角色卡（纯 Map 变换，零 I/O）。
///
/// 定位规则（旧版 `applyStateToCard`，:7519-7562）：
///   · 给了 charId 且命中 → 写那张（或同 id 的 current）；
///   · 给了 charId 但找不到 → `card_not_found`，**绝不退到别的卡**；
///   · 没给 charId → 才退 current 并标 `source:'current'`；没有 current → `no_card`。
/// 命中后逐键写 status（不新增 / 改名契约键），并把 madness / mental /
/// sanLoss / tempStatus / items / weapons 一并落下。
CardWriteResult resolveRoomCardPatch(
  RoomCardPatch patch,
  Map<String, Map<String, Object?>> cards,
  Map<String, Object?>? current,
) {
  final cid = patch.charId ?? '';
  late final Map<String, Object?> card;
  late final String source;
  if (cid.isNotEmpty) {
    final byId = cards[cid];
    final byCurrent =
        (current != null && jsStr(current['id']) == cid) ? current : null;
    final found = byId ?? byCurrent;
    if (found == null) {
      return CardWriteResult(
        ok: false,
        reason: 'card_not_found',
        cardId: cid,
      );
    }
    card = found;
    source = 'characters';
  } else {
    if (current == null) {
      return const CardWriteResult(ok: false, reason: 'no_card');
    }
    card = current;
    source = 'current';
  }

  final statusRaw = card['status'];
  final st = statusRaw is Map
      ? statusRaw.cast<String, Object?>()
      : <String, Object?>{};
  if (statusRaw is! Map) card['status'] = st;
  final pst = asMap(patch.patch['status']);
  for (final k in <String>[
    'currentHP',
    'maxHP',
    'currentMP',
    'maxMP',
    'currentSAN',
    'maxSAN',
    'currentLuck',
  ]) {
    final v = pst[k];
    if (v != null) st[k] = v;
  }
  if (pst['body'] != null) st['body'] = pst['body'];
  if (pst['dying'] != null) st['dying'] = jsTruthy(pst['dying']);
  if (pst['unconscious'] != null) {
    st['unconscious'] = jsTruthy(pst['unconscious']);
  }
  for (final k in <String>['madness', 'tempStatus', 'items', 'weapons']) {
    final v = patch.patch[k];
    if (v is List) card[k] = roomClone(v);
  }
  final mental = patch.patch['mental'];
  if (mental is List) st['mental'] = roomClone(mental);
  if (patch.patch.containsKey('sanLoss')) {
    st['sanLoss'] = patch.patch['sanLoss'];
  }

  return CardWriteResult(
    ok: true,
    cardId: cid.isNotEmpty ? cid : jsStr(card['id']),
    source: source,
  );
}

/// 角色卡上报摘要白名单（旧版 `sanitizeSheet`，:7297-7432）。
///
/// `at` 取 `nowMillis()`（js_compat 的全局时钟，oracle 固定 1700000000000），
/// 与旧版 `Date.now()` 同口径；白名单本体复用 S4.3 的 raSanitizeSheet。
Map<String, Object?> sanitizeSheet(Object? p, [Map<String, Object?>? mem]) =>
    raSanitizeSheet(p, mem, nowMillis());

/// 场景检定步骤数组白名单（旧版 `sanitizeSceneSteps`，:7449-7467）。
List<Map<String, Object?>> sanitizeSceneSteps(Object? p) =>
    raSanitizeSceneSteps(p);
