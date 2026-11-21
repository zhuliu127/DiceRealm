// ============================================================
// room_controller.dart — UI 的**唯一出入口**（设计 §3.4 / §1.6）
//
// 全部 UI 交互都经这里：widget 里禁止直接拿 `RoomSession` 发东西。
// 三件事：
//   ① 节流（S6：400ms 防连点，**按 key 分桶**，不是全局一个闸门）；
//   ② 可点性闸门 [gate]，让「控件可点 ⟺ POLICY 允许」只有一处实现；
//   ③ 提示口径（[notice] 只写 `local.notice`，不弹模态、不乐观提示成功）。
//
// ⚠️ 本文件是 UI 层唯一被允许持有 [RoomSession] 的地方；
//    `widgets/` / `sheets/` / `painter/` 只经 `RoomScope.of(ctx).controller`。
// ============================================================

import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/room_legacy_migrate.dart';
import '../../domain/room_model_state.dart' show needs;
import '../../domain/room_ports.dart';
import '../../domain/room_types.dart' show RoomConfirm, RoomIntent;
import '../../repo/file_room_save_store.dart' show FileRoomSaveStore;
import '../../repo/room_notes_store.dart';

import 'room_image_picker.dart';
import 'room_save_syncer.dart' show resumeKeyOf;
import 'room_session.dart';
import 'room_ui_local.dart';

/// 可点性闸门：唯一实现。**不缓存**（POLICY 是 const，开销可忽略）。
///
/// ⚠️ 只服务 61 个 `INTENT.ACT` action；13 个 insight 通道的 INTENT
///    不经 POLICY，`can()` 对它们恒为 false（§1.6 / K6）。
class RoomGate {
  const RoomGate(this.role);

  final String role;

  bool can(String action) => needs(role, action).allowed;

  String? confirmOf(String action) => needs(role, action).confirm;
}

/// 全部 UI 交互的唯一出口。
class RoomController {
  RoomController({
    required this.session,
    required this.local,
    required this.notes,
    this.imagePicker,
    this.cardSink,
    this.saveStore,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? _systemNowMs;

  final RoomSession session;
  final RoomUiLocal local;
  final RoomNotesStore notes;
  final ImagePickerPort? imagePicker;
  final RoomCardSink? cardSink;
  final RoomSaveStore? saveStore;

  final int Function() _nowMs;
  final Map<String, int> _lastSentAt = <String, int>{};

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  RoomGate get gate => RoomGate(session.role);

  /// 发一个 13 个 INTENT 之一。失败不抛，一律转 notice（K2 第 4 条 / K7）。
  Future<void> sendIntent(String op, Map<String, Object?> p) async {
    try {
      await session.sendIntent(op, p);
    } catch (e) {
      notice('操作失败：$e');
    }
  }

  /// 发一个 61 个 action 之一（双层信封由 session 组装）。
  Future<void> hostAction(String action, [Map<String, Object?>? p]) async {
    try {
      await session.hostAction(action, p);
    } catch (e) {
      notice('操作失败：$e');
    }
  }

  /// 危险动作（K-03 两次点击才执行的那一类）。
  ///
  /// ★ P10 第 1 期 B3 的**真正根因**：`room.close` / `room.end` 在 POLICY 里是
  ///   `RoomConfirm.twice`，而权威端的 `act()` 对需要确认的动作用的是
  ///   「先入 pending 队列，等一条 `INTENT.CONFIRM` 才真的执行」
  ///   （`confirmPending`）。UI 这边只有「同一个按钮点两次」这层本地确认，
  ///   第二次点下去只是**又发了一遍同一个 action** —— 权威端按
  ///   「同一 pending 去重」把它吞掉，于是：
  ///     · KP 看到的是系统提示「该操作已在等待确认」；
  ///     · 房间状态一点没变 → 用户说的「点了没反应，也不退出房间」。
  ///
  /// 修法：本方法封装「发动作 + 补一条我确认」，语义仍是「点两次才执行」
  ///   （第一次只 arm，第二次才走到这里），不给任何一次点击放水。
  Future<void> dangerAction(String action, [Map<String, Object?>? p]) async {
    await hostAction(action, p);
    if (gate.confirmOf(action) != RoomConfirm.twice) return;
    await sendIntent(RoomIntent.confirm, <String, Object?>{
      'op': action,
      // `by` 必须与 pending 里那条的 `by` 一致（KP 自己发起 = 座位号）
      'by': session.seat,
      'agree': true,
    });
  }

  /// 按 key 分桶的 400ms 节流。返回 true = 放行；false = 本次被吞。
  /// 用途：`madness.advance`（S6）、重绘风暴按钮、`combat.next`。
  ///
  /// ★ 2.34.0 契约核对（I15 / GL-1）：**默认值 400ms 逐字不动**。500ms 冷却
  ///   只在各自**调用点**传 `window:`，即 `gp_pl_char_card.dart:365-370`
  ///   与 `gp_combat_list.dart:216-223`（W-E 文件集），本文件不设第二套闸门。
  /// ★ 2.34.0 契约核对（I5 / PV-1b）：玩家主动对抗申请载荷
  ///   `RoomIntent.act` 之 `p = {op:'check.opposed', auto:true, skill,
  ///   targetSeat, by}` 由 `sheet_opposed.dart` 的弹层经
  ///   `RoomScope.of(context).controller.sendIntent` 发出，落在本方法之上的
  ///   [sendIntent] 即可；本文件不新增 action / 事件 / 意图、不改签名，
  ///   `62 / 28 / 13` 覆盖矩阵与 `sendIntent` 的 `try/catch → notice` 口径不变。
  bool throttle(String key,
      {Duration window = const Duration(milliseconds: 400)}) {
    final now = _nowMs();
    final last = _lastSentAt[key];
    if (last != null && now - last < window.inMilliseconds) return false;
    _lastSentAt[key] = now;
    return true;
  }

  /// 存档：`host.save()` → `saveStore.put(code, data)`。返回是否成功。
  ///
  /// [name] 非空时用作存储键（自定义存档槽），否则用房间号。
  /// ⚠️ 不往 20 键存档里塞任何额外键（P4 门禁）。
  Future<bool> saveNow({String? name}) async {
    final store = saveStore;
    if (store == null) {
      notice('没有可用的存档后端');
      return false;
    }
    final data = session.exportSave();
    if (data == null) {
      notice('只有 KP 能保存房间');
      return false;
    }
    // ★ P13：自定义名可能含中文/空格/间隔号，会被 `FileRoomSaveStore.isSafeKey`
    //   拒写（用户体感=「保存按钮坏了」）。这里在 controller 层把名字清洗成
    //   合法键（不改 store 的白名单防线，也不改存档内容里的 meta.name）。
    final raw = name?.trim() ?? '';
    final key = raw.isEmpty ? session.code : _sanitizeSaveKey(raw, session.code);
    if (key.isEmpty) {
      notice('房间号为空，无法保存');
      return false;
    }
    debugPrint('[SAVE] saveNow name=$name key=$key store=${store.runtimeType}');
    store.put(key, data);
    if (store is FileRoomSaveStore && store.lastError != null) {
      debugPrint('[SAVE] saveNow put FAILED key=$key lastError=${store.lastError}');
    }
    // ★ GL-1：自定义名常含中文 / 空格，会被 FileRoomSaveStore.isSafeKey
    //   拒写；这里额外落一份房号键兜底，保证「存档槽 · 保存」之后 ③ 区
    //   续玩列表一定看得到这个房间。resumeKeyOf 复用 room_save_syncer.dart
    //   的单一真源，绝不复制第二份实现。
    final resumeKey = resumeKeyOf(session.code);
    if (resumeKey.isNotEmpty) store.put(resumeKey, data);
    return true;
  }

  /// 把用户输入的存档槽名清洗成 `FileRoomSaveStore` 认的安全键。
  ///
  /// ★ P13：白名单是 `^[A-Za-z0-9_\-]+$`（路径穿越防线，不能放宽），
  ///   所以清洗放在 controller 层：非白名单字符→`-`、压缩连续 `-`、
  ///   去首尾 `-`、截断 64、空则回退房号。
  static String _sanitizeSaveKey(String raw, String fallback) {
    var s = raw.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '-');
    s = s.replaceAll(RegExp(r'-+'), '-');
    s = s.replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.length > 64) s = s.substring(0, 64);
    s = s.replaceAll(RegExp(r'-+$'), '');
    return s.isEmpty ? fallback : s;
  }

  /// 载入：★ K4 顺序**不可交换** —— 先迁移、再 adopt。
  /// `migrateLegacySave` → `session.importSave` → `pullSync()` → 一次性提示。
  Future<LegacyMigrateResult> openSave(Map<String, Object?> save) async {
    final result = migrateLegacySave(save);
    session.importSave(result.save);
    await session.pullSync();
    if (result.changed) {
      notice('旧存档含历史明文记录，已自动脱敏 ${result.migrated} 条。');
    }
    return result;
  }

  /// 提示（进 `local.notice`，由块级 banner 渲染，默认 2s 自消）。
  /// 同时转发给 session 的下游接收者（P6 可挂日志）。
  void notice(String text) {
    local.showNotice(text);
    final sink = session.onNotice;
    if (sink != null) sink(text);
  }

  /// 选图片 → dataURL。测试注入 `imagePicker`，生产回落全局可替换实例。
  /// 返回 null = 用户取消或超过 2MB（S9）。
  Future<String?> pickImage({int maxBytes = 2 * 1024 * 1024}) async {
    final picker = imagePicker ?? roomImagePicker;
    try {
      return await picker.pickImage(maxBytes: maxBytes);
    } catch (e) {
      notice('选择图片失败：$e');
      return null;
    }
  }

  /// 写回角色卡（K11 唯一路径：`cardSink` → `CharacterRepoRoomCardSink`）。
  /// 没注入 sink 时直接返回 null，绝不在 widget 里改 `Character`。
  Future<CardWriteResult?> writeCard(RoomCardPatch patch) async {
    final sink = cardSink;
    if (sink == null) {
      notice('没有可用的角色卡仓库');
      return null;
    }
    try {
      return await sink.write(patch);
    } catch (e) {
      notice('写回角色卡失败：$e');
      return null;
    }
  }

  /// 测试用：清空节流记录（不影响生产行为）。
  void resetThrottle() => _lastSentAt.clear();
}
