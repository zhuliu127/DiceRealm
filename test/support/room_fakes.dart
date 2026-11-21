// ============================================================
// test/support/room_fakes.dart — P4 测试用的确定性替身与内存后端
//
// 为什么需要它们：
//   · 端口（RoomSaveStore / RoomCardSink / RoomRulesPort / RoomMadnessPort）
//     在 domain 里是纯抽象，测试要能注入「不出 I/O、结果可复现」的实现；
//   · 规则服务若直接吃真随机，断线重连类用例就没法断言具体数值。
//
// `roomHostOpts()` 工厂随 D14（RoomHostOptions）在 T03 落地：固定时钟 + LCG +
// 确定性规则/疯狂表 + 纯内存存档后端，让 Host 相关用例完全可复现。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_ports.dart';
import 'package:dice_realm/domain/room_rules.dart';

import 'oracle.dart' show Lcg, oracleNowMs;

/// 构造一份确定性 [RoomHostOptions]（T03 的 D14 依赖注入工厂）。
///
/// · 时钟固定为 `oracleNowMs`（1700000000000），与 oracle fixture 一致；
/// · 随机源是独立 [Lcg]（不与 `setRng` 的全局源串味），`seed` 可钉死；
/// · `rules` / `madness` / `saveStore` 全部注入本文件的内存替身，零 I/O。
RoomHostOptions roomHostOpts({
  Map<String, Object?>? meta,
  int snapshotEvery = 20,
  int logCap = 400,
  int snapshotLimit = 20,
  int seed = 1,
}) {
  final lcg = Lcg(seed);
  return RoomHostOptions(
    meta: meta ?? const <String, Object?>{},
    snapshotEvery: snapshotEvery,
    snapshotLimit: snapshotLimit,
    logCap: logCap,
    now: () => oracleNowMs,
    rng: lcg.call,
    rules: DeterministicRoomRules(seed: seed),
    madness: const DeterministicRoomMadness(),
    saveStore: InMemoryRoomSaveStore(),
  );
}

/// 纯内存存档后端（Q5 端口的最小实现：后续期换文件/云端不动 domain）。
class InMemoryRoomSaveStore implements RoomSaveStore {
  final Map<String, Map<String, Object?>> _byCode =
      <String, Map<String, Object?>>{};

  @override
  void put(String code, Map<String, Object?> data) {
    _byCode[code] = data;
  }

  @override
  Map<String, Object?>? get(String code) => _byCode[code];

  @override
  List<String> list() => _byCode.keys.toList();
}

/// 记录型角色卡写回后端（断言「写了几次、写了什么」）。
class InMemoryRoomCardSink implements RoomCardSink {
  InMemoryRoomCardSink({this.nextResult});

  /// 需要模拟失败时注入
  final CardWriteResult? nextResult;

  final List<RoomCardPatch> written = <RoomCardPatch>[];

  @override
  Future<CardWriteResult> write(RoomCardPatch patch) async {
    written.add(patch);
    return nextResult ??
        CardWriteResult(
          ok: true,
          cardId: patch.charId ?? '',
          source: 'characters',
        );
  }
}

/// 确定性规则服务：把 `rng` 固定成同一条 LCG 序列，其余全部转发给 [CocRules]。
///
/// 只影响「需要掷骰」的入口；`check` 等仍可用 opts 里的 `value`/`ones`/`forcedTens`
/// 直接钉死结果（Q4 口径）。
class DeterministicRoomRules implements RoomRulesPort {
  DeterministicRoomRules({int seed = 1}) : _rng = Lcg(seed);

  static const CocRules _rules = CocRules();

  final Lcg _rng;

  /// 已消耗的随机数个数（用例可断言「注入位被真的用到了」）
  int get used => _rng.used;

  JsRng get rng => _rng.call;

  Map<String, Object?> _withRng(Map<String, Object?> opts) {
    if (opts.containsKey('rng') && opts['rng'] != null) return opts;
    return <String, Object?>{...opts, 'rng': _rng.call};
  }

  @override
  Map<String, Object?> check(Map<String, Object?> opts) =>
      _rules.check(_withRng(opts));

  @override
  Map<String, Object?> rollExpr(Object? expr, [JsRng? _]) =>
      _rules.rollExpr(expr, _rng.call);

  @override
  Map<String, Object?> rollDamageBonus(Object? expr, [JsRng? _]) =>
      _rules.rollDamageBonus(expr, _rng.call);

  @override
  Map<String, Object?> parseExpr(Object? expr) => _rules.parseExpr(expr);

  @override
  Map<String, Object?> resolveAttack(Map<String, Object?> o) =>
      _rules.resolveAttack(_withRng(o));

  @override
  Map<String, Object?> initiativeOrder(
    Object? actors, [
    Map<String, Object?>? opts,
  ]) =>
      _rules.initiativeOrder(actors, opts);

  @override
  Map<String, Object?> opposed(Object? a, Object? b) => _rules.opposed(a, b);

  @override
  Map<String, Object?> opposedFull(
    Object? a,
    Object? b, [
    Map<String, Object?>? o,
  ]) =>
      _rules.opposedFull(a, b, <String, Object?>{...?o, 'rng': _rng.call});

  @override
  Map<String, Object?> resolveSanCheck(Map<String, Object?> opts) =>
      _rules.resolveSanCheck(_withRng(opts));

  @override
  Map<String, Object?> parseSanLoss(Object? expr) => _rules.parseSanLoss(expr);

  @override
  Map<String, Object?> dyingRoundCheck(Object? con, [JsRng? _]) =>
      _rules.dyingRoundCheck(con, _rng.call);

  @override
  Map<String, Object?> temporaryInsanityCheck(Object? intValue, [JsRng? _]) =>
      _rules.temporaryInsanityCheck(intValue, _rng.call);

  @override
  int? skillValue(Object? sheet, Object? name) =>
      _rules.skillValue(sheet, name);

  @override
  int? attrValue(Object? sheet, Object? key) => _rules.attrValue(sheet, key);

  @override
  Map<String, Object?> sceneStepResolve(Object? step, Object? level) =>
      _rules.sceneStepResolve(step, level);

  @override
  Map<String, Object?> impaleDamage(Object? expr, Object? db, [JsRng? _]) =>
      _rules.impaleDamage(expr, db, _rng.call);

  @override
  int burstMaxOf(Object? expr) => _rules.burstMaxOf(expr);

  @override
  Map<String, Object?> malfunctionOf(
    Object? weapon,
    Object? rollValue, [
    Map<String, Object?>? opts,
  ]) =>
      _rules.malfunctionOf(weapon, rollValue, opts);

  @override
  String defaultMalfunctionType(Object? weapon) =>
      _rules.defaultMalfunctionType(weapon);

  @override
  Map<String, Object?> malfunctionEffect(
    Object? weapon,
    Object? type, [
    JsRng? _,
  ]) =>
      _rules.malfunctionEffect(weapon, type, _rng.call);

  @override
  String normDifficulty(Object? d) => _rules.normDifficulty(d);

  // ★ P11 花幸运 / 推动：纯算术、不吃随机源，直接转发。
  @override
  Map<String, Object?> spendLuck(Map<String, Object?>? opts) =>
      _rules.spendLuck(opts);

  @override
  Map<String, Object?> canPush(Map<String, Object?>? result, [Object? kind]) =>
      _rules.canPush(result, kind);

  @override
  Map<String, int> get levelMap => CocRules.LEVEL;
}

/// 确定性疯狂表替身（U1：P4 不重验疯狂表内容）。
class DeterministicRoomMadness implements RoomMadnessPort {
  const DeterministicRoomMadness();

  static const Map<String, Object?> _symptom = <String, Object?>{
    'type': 'phobia',
    'name': '恐高',
    'permanent': false,
    'rounds': 3,
    'from': '临时疯狂',
    'bg': false,
    'sum': false,
  };

  @override
  Map<String, Object?>? roll(Object? type, bool permanent, [JsRng? rng]) =>
      <String, Object?>{
        ..._symptom,
        'type': ?type,
        'permanent': permanent,
        'rounds': permanent ? 0 : 3,
      };

  @override
  Map<String, Object?>? make(
    Object? type,
    bool permanent,
    String? name, [
    JsRng? rng,
  ]) =>
      <String, Object?>{
        ..._symptom,
        'type': ?type,
        'name': ?name,
        'permanent': permanent,
        'rounds': permanent ? 0 : 3,
      };
}
