// ============================================================
// room_ports.dart — 端口（依赖倒置）与结构化结果值对象
//
// 为什么 domain 只声明「依赖什么」：
//   lib/domain 必须保持纯 Dart（不得引入 Flutter 包、文件 I/O 或 UI 库），
//   但「写回角色卡」这件事的落盘入口在 lib/repo（CharacterRepo.save 是
//   Future<void> 且内部走文件后端）。如果把 repo 类型写进 domain 就会
//   反向依赖 + 引入 I/O 能力。所以这里只放**纯抽象**，适配器在 lib/repo。
//
// K3 错误口径：旧版对可预期的非法输入**不抛异常**，返回结构化结果。
//   这里用值对象 + toJson() 固化，异常只用于程序员错误。
// ============================================================

import 'js_compat.dart';
import 'room_types.dart';

/// 规则服务端口（Host 的注入面）。
///
/// ⚠️ 与设计文档 §3.1 的端口草案有一处**刻意对齐**：草案把多个参数捆成
///    `Map`（如 `opposed(Map)`、`impaleDamage(Map)`），但附录 C 的 53 个
///    导出成员是 `opposed(a, b)` / `impaleDamage(expr, db, rng)` 的**位置参数**。
///    Dart 不允许同名方法两套签名，所以端口签名一律**照抄 53 导出**，
///    由 `CocRules implements RoomRulesPort` 一处实现两边共用。
///    这样 Host 注入的 `rules` 与 fixture 直接调用的 `CocRules` 是同一套语义。
abstract class RoomRulesPort {
  Map<String, Object?> check(Map<String, Object?> opts);

  Map<String, Object?> rollExpr(Object? expr, [JsRng? rng]);

  Map<String, Object?> rollDamageBonus(Object? expr, [JsRng? rng]);

  Map<String, Object?> parseExpr(Object? expr);

  Map<String, Object?> resolveAttack(Map<String, Object?> o);

  Map<String, Object?> initiativeOrder(
    Object? actors, [
    Map<String, Object?>? opts,
  ]);

  Map<String, Object?> opposed(Object? a, Object? b);

  Map<String, Object?> opposedFull(
    Object? a,
    Object? b, [
    Map<String, Object?>? o,
  ]);

  Map<String, Object?> resolveSanCheck(Map<String, Object?> opts);

  Map<String, Object?> parseSanLoss(Object? expr);

  Map<String, Object?> dyingRoundCheck(Object? con, [JsRng? rng]);

  Map<String, Object?> temporaryInsanityCheck(Object? intValue, [JsRng? rng]);

  /// 查不到返回 null（旧版 `skillValue` 返回 null，Host 据此回落）。
  int? skillValue(Object? sheet, Object? name);

  /// 查不到返回 null。
  int? attrValue(Object? sheet, Object? key);

  Map<String, Object?> sceneStepResolve(Object? step, Object? level);

  Map<String, Object?> impaleDamage(Object? expr, Object? db, [JsRng? rng]);

  int burstMaxOf(Object? expr);

  Map<String, Object?> malfunctionOf(
    Object? weapon,
    Object? rollValue, [
    Map<String, Object?>? opts,
  ]);

  String defaultMalfunctionType(Object? weapon);

  Map<String, Object?> malfunctionEffect(
    Object? weapon,
    Object? type, [
    JsRng? rng,
  ]);

  String normDifficulty(Object? d);

  /// 花幸运：**只算不改**（原子性由调用方保证）。
  ///
  /// 入参 `{result, amount, luckAvailable}`，返回
  /// `{ok, amount, spent, refund, before, after, beforeLevel, afterLevel,
  /// afterLevelText, passed, growthEligible, note}` 或 `{ok:false, reason}`。
  /// 形参可空：与 `CocRules.spendLuck(Map?)` 逐字对齐（旧版 53 导出的口径）。
  Map<String, Object?> spendLuck(Map<String, Object?>? opts);

  /// 能不能推动：只有**失败的技能 / 属性 / 特征检定**可以。
  Map<String, Object?> canPush(Map<String, Object?>? result, [Object? kind]);

  /// 端口侧改名：规避与 `CocRules.LEVEL`（static const）撞名。
  /// room-model.js 有 11 处 `rules.LEVEL` 引用，Host 经此取值。
  Map<String, int> get levelMap;
}

/// 疯狂表端口（U1：`lib/domain/madness.dart` 适配，P4 不重验表内容）。
abstract class RoomMadnessPort {
  Map<String, Object?>? roll(Object? type, bool permanent, [JsRng? rng]);

  Map<String, Object?>? make(
    Object? type,
    bool permanent,
    String? name, [
    JsRng? rng,
  ]);
}

/// 存档仓库端口（纯 Map；后续期换 File/云端实现即可，domain 一行不改）。
abstract class RoomSaveStore {
  void put(String code, Map<String, Object?> data);

  Map<String, Object?>? get(String code);

  List<String> list();
}

/// 角色卡写回端口（C5：唯一允许落盘的方向）。
abstract class RoomCardSink {
  Future<CardWriteResult> write(RoomCardPatch patch);
}

/// 一次写回意图：定位到哪张卡 + 要写什么。
class RoomCardPatch {
  const RoomCardPatch({this.charId, this.patch = const <String, Object?>{}});

  final String? charId;
  final Map<String, Object?> patch;

  Map<String, Object?> toJson() => <String, Object?>{
        'charId': charId,
        'patch': patch,
      };
}

/// `applyStateToCard` 的结构化结果（K3：绝不静默失败）。
class CardWriteResult {
  const CardWriteResult({
    required this.ok,
    this.reason = '',
    this.cardId = '',
    this.source = '',
  });

  final bool ok;
  final String reason;
  final String cardId;

  /// `characters` = 按 charId 命中；`current` = 未绑定卡时的旧行为兜底。
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        'reason': reason,
        'cardId': cardId,
        'source': source,
      };
}

/// `needs()` 结果。未登记 action → `allowed:false, confirm:null`。
class NeedsResult {
  const NeedsResult(this.allowed, this.confirm);

  final bool allowed;
  final String? confirm;

  Map<String, Object?> toJson() => <String, Object?>{
        'allowed': allowed,
        'confirm': confirm,
      };
}

/// 序号闸门结果（`skip` 与 `evt` **共用**同一套判据）。
class GateResult {
  const GateResult({
    required this.ok,
    this.dup = false,
    this.gap = false,
    required this.lastSeq,
  });

  final bool ok;
  final bool dup;
  final bool gap;

  /// 闸门放行/拒绝**之后**的 lastSeq（与旧版 `from: this.lastSeq` 对齐）
  final int lastSeq;

  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        'dup': dup,
        'gap': gap,
        'lastSeq': lastSeq,
      };
}

/// `Client.receive()` 的返回体。
///
/// ⚠️ 旧版不同分支返回**不同键集合**（见 room-model.js:7010-7046），
///    所以这里用「显式键序 + 可空字段」而不是固定 toJson：
///    `expectJsonMatch` 要求键集合完全一致，多一个 null 键也算不一致。
/// ⚠️ §0.3：返回体里**没有** `gapFrom` 字段，用的是 `from`（值 = lastSeq）。
///    `gapFrom` 是内部字段，禁止在此凭空添加。
class ReceiveResult {
  ReceiveResult._(this._order, this._values);

  /// `{kind:'ignore'}`
  factory ReceiveResult.ignore() => ReceiveResult._(
        const <String>['kind'],
        <String, Object?>{'kind': 'ignore'},
      );

  /// `{kind:'sync', changed:true, seq}`
  factory ReceiveResult.sync(int seq) => ReceiveResult._(
        const <String>['kind', 'changed', 'seq'],
        <String, Object?>{'kind': 'sync', 'changed': true, 'seq': seq},
      );

  /// 水位标记通过闸门：`{kind:'skip', changed:false, seq, filled}`
  factory ReceiveResult.skipOk(int seq, bool filled) => ReceiveResult._(
        const <String>['kind', 'changed', 'seq', 'filled'],
        <String, Object?>{
          'kind': 'skip',
          'changed': false,
          'seq': seq,
          'filled': filled,
        },
      );

  /// 增量事件通过闸门：`{kind:'evt', changed:true, seq, t, filled}`
  factory ReceiveResult.evtOk(int seq, String t, bool filled) => ReceiveResult._(
        const <String>['kind', 'changed', 'seq', 't', 'filled'],
        <String, Object?>{
          'kind': 'evt',
          'changed': true,
          'seq': seq,
          't': t,
          'filled': filled,
        },
      );

  /// 被闸门拒绝（重复 / 跳号）：`{kind, dup, gap, from, got}`
  factory ReceiveResult.rejected(
    String kind,
    bool dup,
    bool gap,
    int from,
    int got,
  ) =>
      ReceiveResult._(
        const <String>['kind', 'dup', 'gap', 'from', 'got'],
        <String, Object?>{
          'kind': kind,
          'dup': dup,
          'gap': gap,
          'from': from,
          'got': got,
        },
      );

  final List<String> _order;
  final Map<String, Object?> _values;

  String get kind => _values['kind']! as String;

  /// 键序与旧版对象字面量一致
  Map<String, Object?> toJson() {
    final out = <String, Object?>{};
    for (final k in _order) {
      out[k] = _values[k];
    }
    return out;
  }
}

/// `rollback()` 结果。
class RollbackResult {
  const RollbackResult({
    required this.dropped,
    required this.seq,
    required this.from,
  });

  final int dropped;
  final int seq;
  final int from;

  Map<String, Object?> toJson() => <String, Object?>{
        'dropped': dropped,
        'seq': seq,
        'from': from,
      };
}

/// `Client.applySheetState()` 结果（幂等：同一 seq 只生效一次）。
class ApplySheetResult {
  const ApplySheetResult(this.applied, this.seq, [this.dup]);

  final bool applied;
  final int seq;

  /// 旧版只在「已应用过更大 seq」时带这个键 → null 表示不带。
  final bool? dup;

  Map<String, Object?> toJson() {
    final out = <String, Object?>{'applied': applied, 'seq': seq};
    if (dup != null) out['dup'] = dup;
    return out;
  }
}

/// `attachPeer()` 结果（U2：保留结构对象，`out` 仍是发送计划）。
class AttachPeerResult {
  const AttachPeerResult({
    required this.seat,
    required this.rejected,
    required this.blocked,
    this.member,
    this.out = const <SendPlan>[],
  });

  final String seat;
  final bool rejected;

  /// true = 这个 seat 被踢过，调用方应直接断开连接。
  final bool blocked;
  final Map<String, Object?>? member;
  final List<SendPlan> out;

  Map<String, Object?> toJson() => <String, Object?>{
        'seat': seat,
        'rejected': rejected,
        'blocked': blocked,
        'member': member,
        'out': out.map((p) => p.toJson()).toList(),
      };
}

/// 补拉进度诊断。
class ResyncDiag {
  const ResyncDiag({
    required this.from,
    required this.last,
    required this.filled,
    required this.holes,
    required this.count,
  });

  final int from;
  final int last;
  final int filled;
  final int holes;
  final int count;

  Map<String, Object?> toJson() => <String, Object?>{
        'from': from,
        'last': last,
        'filled': filled,
        'holes': holes,
        'count': count,
      };
}
