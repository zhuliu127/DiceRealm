// ui/room/room_save_syncer.dart — P19 存档自动保存 + 全员分发/落盘
//
// 用户需求（2026-11-14）：
//   ① KP 和所有玩家的手机上都保存一份存档，并标上时间戳；
//   ② KP 和玩家都可以回到存档的房间继续进行游戏（玩家续玩入口见
//      `home_page.dart` 的「续玩房间」）；
//   ③ 缺席的玩家回来后，缺失的存档可以同步到最新的那一份（看时间戳）；
//   ④ 自动存档触发点：KP 推进下一回合、每 10 分钟、KP 结束房间 / 结团。
//   ⑤ 存档时，玩家游戏中的角色卡状态自动保存到「角色卡」。
//
// 架构（为什么这么做）：
//   · **快照从 KP 流向玩家**：玩家实时收到的只是裁剪态，且缺席期间错过
//     的事件永远补不回来 —— 唯一可信的全量来源是 KP 的 `host.save()`。
//     所以「同步」= KP 每次存档成功后把快照广播出去（`save.share` op →
//     `RoomEvt.saveSync`），玩家端在 session 层拦截落盘。
//   · **时间戳去重**：快照自带 `savedAt`（20 键存档的既有键）。玩家端
//     只接受比本地同房间最新一份**更新**的快照 —— 缺席玩家回来后收到的
//     第一份就是最新的；乱序到达的旧快照被丢弃。
//   · **角色卡联动**：收到快照后照 `RoomCardSaver` 的口径把**自己**的
//     卡面数值写回本地角色卡（`controller.writeCard`），满足 ⑤。
//     （回合边界的自动存卡由既有 `RoomCardSaver` 负责，两者互补。）
//   · **自动存档（KP）**：三个触发点 + 玩家加入时补一发 —— 快照滚动
//     保留最近 [maxAutoSlots] 份，防止每回合一份把存档库撑爆。
//
// 反向自证伪：
//   · 删掉 `_onRound` 的回合变化判据 → round 触发用例必红；
//   · 把玩家端 `_onShared` 的时间戳比较改成恒接受 → 去重用例必红；
//   · 把 shareSave 的空载荷校验删掉 → domain 用例必红。

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/room_types.dart' show RoomRole, RoomStatus;
import '../../domain/js_compat.dart' show asList, asMap, jsParseInt, jsStr;
import '../../repo/file_room_save_store.dart' show FileRoomSaveStore;
import '../../repo/room_save_store.dart'
    show RoomSaveStoreMutable;
import '../../net/cloud_room_backup.dart' show cloudBackupSink;
import 'room_card_saver.dart' show roomCardPatchOf;
import 'room_controller.dart' show RoomController;
import 'room_session.dart' show RoomSession;

/// 自动存档的滚动保留份数（超过后删最旧的）。
const int kAutoSaveKeep = 10;

/// 自动存档周期（用户要求：每 10 分钟）。
const Duration kAutoSaveInterval = Duration(minutes: 10);

/// GL-1：「续玩可见槽」的存储键 = 房号本身（去空格 + 大写归一）。
///
/// ★ 单一真源：`auto/$code/…` 与 `share/$code/latest` 含 `/`，2.37.0 起由
///   `FileRoomSaveStore` 的**结构化槽键编码**落盘（FileRoomSaveStore.isSafeKey
///   白名单语义与路径穿越防线不变）；房号键仍额外写一份，作为续玩列表折叠
///   去重与文件后端不可用时的兜底，语义逐字保留。
/// ★ 云端房号可能是小写，`toUpperCase()` 保证同房号只占一条槽（R8）。
/// ★ `meta.code` 原样保留、凭据仍走 `loadRecentCredentialFlexible`
///   三形态归一；本函数只管存储键，不动存档内容。
String resumeKeyOf(String code) => code.trim().toUpperCase();

class RoomSaveSyncer {
  RoomSaveSyncer({
    required this.controller,
    required this.session,
    this.maxAutoSlots = kAutoSaveKeep,
    this.nowMs,
  }) {
    _now = nowMs ?? _systemNowMs;
    // ★ P20 N-3 / M12：构造期**统一**给所有会话（本机 / LAN 远端 /
    //   云端远端）挂落盘回调。此前只在 `_RoomShellState.initState()` 的
    //   `if (session is LocalLoopbackSession)` 分支挂，真实联网玩家会话
    //   从不落盘 → ③ 区根本没有玩家续玩条目。
    //   语义与 initState():1006–1010 的既有回调完全一致：
    //   `onShared(save)` + `onStateChanged()` 两步（Local 会话后挂覆盖也
    //   是同一语义，允许覆盖）。
    session.onSharedSave = (Map<String, Object?> save) {
      onShared(save);
      onStateChanged();
    };
  }

  final RoomController controller;
  final RoomSession session;
  final int maxAutoSlots;

  int Function()? nowMs;
  late int Function() _now;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 自动存档槽键前缀（`auto/<房间号>/<时间戳>`；`list()` 按 mtime 排序）。
  String autoKeyPrefix(String code) => 'auto/$code/';

  /// KP 是否为自动存档 / 分发的主体（旁观者永远不是）。
  bool get isKp => session.role == RoomRole.kp;

  // ---- 状态（测试与诊断用） ----
  int autoSaved = 0;
  int sharedCount = 0;
  int receivedCount = 0;
  int skippedStale = 0;
  String lastError = '';
  bool _busy = false;
  int _lastRound = -1;
  int _lastMemberCount = -1;
  String? _lastStatus;
  Timer? _ticker;

  /// 启动 10 分钟周期存档（仅 KP）。由房间壳体（`_RoomShell`）在
  /// initState 里调用，dispose 里调 [stopTicker]。
  void startTicker() {
    if (!isKp || _ticker != null) return;
    _ticker = Timer.periodic(kAutoSaveInterval, (_) {
      autoSave(reason: 'interval');
    });
  }

  void stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 进房基线：把**进房那一刻**状态对应的 `_lastStatus` 先记下来，但不落档。
  ///
  /// ★ 为什么需要：续玩一个已结束（CLOSED）的存档时，会话状态从第一帧起
  ///   就是终态。`onStateChanged` 的 `key != _lastStatus` 会把它误判成
  ///   「刚刚关房」，于是每次续玩都白写一份 `auto/<code>/close-*` 档并多发
  ///   一次 `save.share` 广播（真机表现为「点一次续玩多一条 close 档」）。
  ///   基线化之后，只有**进房之后真的发生**了关房 / 结团跳变才落档；
  ///   GL-1 要的「KP 点结束房间 → 存下终态档」照旧成立。
  void primeStatusBaseline() {
    final Map<String, Object?> meta = asMap(session.state['meta']);
    final String status = jsStr(meta['status']);
    final bool ended = meta['ended'] == true;
    _lastStatus = '$status${ended ? ':ended' : ''}';
  }

  /// 进房时补一份「开局档」并广播（仅 KP、仅本机还没有该房号档时）。
  ///
  /// ★ 2.37.0 / Q1：建房路径已有 `saveNow()` 兜底，这里靠房号键存在性
  ///   自动跳过，不重复写；从云端 / 存档续玩进来时若本机没档，则立刻落
  ///   一份并 `save.share`，避免「开局 10 分钟内一份都没有」。
  ///   幂等：同一房间第二次调用零写入、零广播。
  Future<bool> saveOnOpen() async {
    if (!isKp || _busy) return false;
    final String code = session.code;
    if (code.isEmpty) return false;
    final store = controller.saveStore;
    if (store == null) return false;
    if (store.get(resumeKeyOf(code)) != null) return false;
    debugPrint('[SAVE] saveOnOpen code=$code store=${store.runtimeType} reason=open');
    return autoSave(reason: 'open');
  }

  /// KP 端：会话每次变化都过一遍触发器（幂等，全部静默）。
  ///
  /// 触发点：
  ///   ① `meta.round` 变化（KP 推进下一回合）；
  ///   ② 成员加入（在线成员数增加 —— 缺席玩家回来时立即补档）；
  ///   ③ `meta.status` 变为 CLOSED / SUSPENDED（结束房间 / 挂起）或
  ///      `meta.ended` 置位（结团）。
  Future<void> onStateChanged() async {
    if (!isKp || _busy) return;
    final state = session.state;
    final meta = asMap(state['meta']);
    // ★ GL-1：改前 CLOSED 直接 return，③ 终态落档成了死代码 —— 关房 /
    //   结团永远存不下档。现在 CLOSED 只跳过 ① 回合 / ② 成员加入两个
    //   触发，仍要走到 ③ 判定，让 close / end 真正 autoSave → 落房号键
    //   + shareLatest。`auto/` `share/` 前缀与滚动淘汰口径逐字不动。
    final closed = jsStr(meta['status']) == RoomStatus.closed;

    if (!closed) {
      // ① 回合边界
      final roundRaw = meta['round'];
      final round = (roundRaw is num) ? roundRaw.toInt() : 0;
      if (round > 0 && round != _lastRound) {
        final first = _lastRound == -1;
        _lastRound = round;
        if (!first) await autoSave(reason: 'round');
      }

      // ② 成员加入（玩家进入房间 = 需要立即同步最新快照）
      // ★ 2.37.0 / Q1：此前额外要求 IN_GAME，招募期加入的玩家在开局前
      //   一份快照都拿不到。成员数增长本身就是「有人要新档」的充分信号，
      //   CLOSED 已在上面短路；基线由壳体 initState 先过一遍 onStateChanged
      //   落下，第一波加入照样能触发。一变一档，不是高频写。
      final members = asList(state['members']);
      if (members.length != _lastMemberCount) {
        final grew =
            _lastMemberCount >= 0 && members.length > _lastMemberCount;
        _lastMemberCount = members.length;
        if (grew) {
          await autoSave(reason: 'join');
          return;
        }
      }
    }

    // ③ 结束房间（CLOSED）/ 结团（meta.ended）—— 存的是结束那一刻的终态
    final status = jsStr(meta['status']);
    final ended = meta['ended'] == true;
    final key = '$status${ended ? ':ended' : ''}';
    // ★ 跳变判据保留（key 变化才触发），但去掉 `_lastStatus != null`
    //   守卫：监听首达就是 CLOSED 的房间（例如直接载入已关房存档）
    //   也要落终态档。首次非终态（IN_GAME）仍不落档，幂等用例零漂移。
    if (key != _lastStatus && (status == RoomStatus.closed || ended)) {
      await autoSave(reason: ended ? 'end' : 'close');
    }
    _lastStatus = key;
  }

  bool isInGameLike(Map<String, Object?> meta) =>
      jsStr(meta['status']) == RoomStatus.inGame;

  /// KP：自动存档 + 分发。
  ///
  /// [name] = `auto/<房间号>/<时间戳>`（带时间戳的独立槽，滚动保留
  /// [maxAutoSlots] 份）；存档本身自带 `savedAt`（秒级），槽键用毫秒避免
  /// 同秒覆盖。
  Future<bool> autoSave({required String reason}) async {
    if (!isKp || _busy) return false;
    _busy = true;
    try {
      final code = session.code;
      if (code.isEmpty) return false;
      final name = '${autoKeyPrefix(code)}$reason-${_now()}';
      final data = session.exportSave();
      if (data == null) return false;
      final store = controller.saveStore;
      if (store == null) {
        lastError = 'no_store';
        return false;
      }
      // ★ 走到这里 data 一定非空（上面已 return），所以只报键数，
      //   不再写 `data!=null` —— 那是个恒真判断（analyzer 会告警）。
      debugPrint('[SAVE] autoSave reason=$reason code=$code keys=${data.length} store=${store.runtimeType}');
      store.put(name, data);
      if (store is FileRoomSaveStore && store.lastError != null) {
        debugPrint('[SAVE] autoSave put FAILED name=$name lastError=${store.lastError}');
      }
      // ★ GL-1：额外落一份「续玩可见」的房号键。auto/ 槽现在由文件后端
      //   编码落盘，房号键仍作为续玩列表去重锚点与兜底，口径逐字保留。
      store.put(resumeKeyOf(code), data);
      // ★ P20 B1/B5：本机落盘成功后调全局云端备份钩子（默认 null →
      //   flutter test 零网络、零异常）。只有云端 KP 的 activeCloudBackupContext
      //   有效时才会真正 POST /backup；玩家 / LAN / 本机房间零请求。
      //   失败静默，绝不拖垮自动存档主流程。
      try {
        cloudBackupSink?.call(data);
      } catch (_) {
        // 云端备份是辅助能力：失败只影响灾备副本，不影响本机存档。
      }
      // 滚动淘汰需要 remove —— 只有 Mutable 实现支持（文件后端支持）。
      if (store is RoomSaveStoreMutable) {
        _pruneAutoSlots(code, store);
      }
      autoSaved += 1;
      // 存档成功 → 立即分发（快照里带 meta.role/seat 标记，见 [_tagSave]）
      await shareLatest(data);
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    } finally {
      _busy = false;
    }
  }

  /// KP：把快照广播给全员。
  Future<void> shareLatest(Map<String, Object?> data) async {
    await controller.hostAction('save.share', <String, Object?>{
      'save': data,
    });
    sharedCount += 1;
  }

  /// 滚动淘汰：同房间的自动档超过 [maxAutoSlots] 份时删最旧。
  void _pruneAutoSlots(String code, RoomSaveStoreMutable store) {
    final prefix = autoKeyPrefix(code);
    final keys =
        store.list().where((String k) => k.startsWith(prefix)).toList()..sort();
    while (keys.length > maxAutoSlots) {
      store.remove(keys.first);
      keys.removeAt(0);
    }
  }

  /// 玩家端：收到 KP 的快照 → 时间戳去重后写本地存档 + 联动角色卡。
  ///
  /// 槽键 `share/<房间号>/<savedAt>`：同一房间按 `savedAt` 只留最新一份
  /// （旧份删除）—— 「缺失的存档同步到最新的那一份」就是这条。
  Future<void> onShared(Map<String, Object?> save) async {
    try {
      final meta = asMap(save['meta']);
      final code = jsStr(meta['code']);
      if (code.isEmpty) return;
      final savedAt = jsParseInt(save['savedAt']) ?? _now();
      final store = controller.saveStore;
      if (store == null) {
        lastError = 'no_store';
        return;
      }
      final prefix = 'share/$code/';
      // 找本地同房间已有的快照：比新来的还新 → 丢弃（乱序保护）
      var localNewest = -1;
      for (final k in store.list().where((String k) => k.startsWith(prefix))) {
        final d = asMap(store.get(k));
        final t = jsParseInt(d['savedAt']) ?? 0;
        if (t > localNewest) localNewest = t;
      }
      if (localNewest > savedAt) {
        skippedStale += 1;
        return;
      }
      // 打上本机视角标记（P16 续玩落点：resumeViewFromSave 读它）
      final tagged = _tagSave(save);
      // 槽键固定 `latest`：同键覆盖旧数据 —— 不依赖 remove 端口（内存
      // store 没有它），「只留最新」的语义由覆盖自然成立。
      store.put('${prefix}latest', tagged);
      // ★ GL-1：玩家端同样额外落一份房号键（KP + 玩家两端都能续玩）。
      //   写的是打过本机视角标记的 tagged，meta.role/seat / members[].self
      //   一个不丢；share/ 槽（现由文件后端编码落盘）与时间戳去重口径不变。
      store.put(resumeKeyOf(code), tagged);
      receivedCount += 1;
      // ⑤ 存档时角色卡状态自动保存到「角色卡」（与 RoomCardSaver 同口径）
      await _saveOwnCard(tagged);
    } catch (e) {
      lastError = '$e';
    }
  }

  /// 给快照打本机视角标记（`meta.role` / `meta.seat` / `members[].self`），
  /// 供 `resumeViewFromSave` 恢复玩家视角。**不改 20 键结构**，只往
  /// `meta` 里加两个键（meta 本来就是自由 map）。
  Map<String, Object?> _tagSave(Map<String, Object?> save) {
    final out = Map<String, Object?>.from(save);
    final meta = Map<String, Object?>.from(asMap(save['meta']));
    meta['role'] = session.role;
    meta['seat'] = session.seat;
    out['meta'] = meta;
    final members = asList(save['members'])
        .map<Object?>((Object? mRaw) {
          final m = asMap(mRaw);
          if (jsStr(m['seat']) == session.seat) {
            return <String, Object?>{...m, 'self': true};
          }
          return m;
        })
        .toList();
    out['members'] = members;
    return out;
  }

  /// 玩家把自己的卡面数值写回本地角色卡（静默，失败只记 lastError）。
  Future<void> _saveOwnCard(Map<String, Object?> save) async {
    if (session.role != RoomRole.player) return;
    if (!controller.gate.can('state.self')) return;
    final patch = roomCardPatchOf(session.state, session.seat);
    if (patch == null) return;
    try {
      await controller.writeCard(patch);
    } catch (e) {
      lastError = '$e';
    }
  }
}
