// ============================================================
// room_rules.dart — COC 7 版规则服务门面 `CocRules`（library + 5 个 part）
//
// 为什么拆 part：
//   room-rules.js 有 1591 行、53 个导出成员。一次性塞一个 Dart 文件既难审
//   也难分批验收。用 `library + part` 让 53 个**签名一次定死**，
//   实现按「核心检定 / 对抗 / 骰式 / 角色卡 / 战斗」五批填进 part。
//
// 三条不可违反的约束（与旧版一致）：
//   1) 纯函数：不碰 DOM、不发请求、不读全局可变状态；
//   2) 随机源可注入：每个掷骰入口收 `rng`，缺省回落 js_compat 的 `nowRng`；
//   3) 掷骰结果可外部传入（`value` / `ones` / `forcedTens`），以便重放与校验。
//
// ⚠️ 刻意**不复用** lib/domain/dice.dart 里那两个零调用的预留实现（奖励骰 / 成功等级）：
//    前者在「个位骰为 0」时会把奖励骰结果取反（见 `_rollD100` 注释），
//    属于既有缺陷；本模块另建 `_rollD100` / `_combine` / `_levelOf`。
//    `dice.dart` 一行不动（C7）。
// ============================================================

// ⚠️ 常量名刻意沿用旧版 `CocRules.LEVEL` / `DIFFICULTY` / `OUTCOME` 等全大写形式：
//    它们是**协议级名字**（fixture 与 P5/P6 都按这些名字取值），改成 lowerCamelCase
//    会让 53 导出成员与旧版对不上。故整文件关闭该命名 lint。
// ignore_for_file: constant_identifier_names

// 保留库名（设计 §3.1 要求）：P5/P6 的调试栈与文档都按 `room_rules` 指代本库。
// ignore: unnecessary_library_name
library room_rules;

import 'js_compat.dart';
import 'room_ports.dart';

part 'room_rules_core.dart';
part 'room_rules_opposed.dart';
part 'room_rules_expr.dart';
part 'room_rules_sheet.dart';
part 'room_rules_combat.dart';

/// 检定 / 状态 / 行动顺序的**唯一**规则出口。
///
/// ⚠️ 方法必须是实例方法：Dart 不允许同名 static 与 instance 成员共存。
///    常量仍为 `static const`（测试可直接 `CocRules.LEVEL` 断言）；
///    端口用 `levelMap` 间接暴露 LEVEL，避免撞名。
class CocRules implements RoomRulesPort {
  const CocRules();

  static const int version = 1;

  /// 成功等级。数值可比大小，比较成功等级时直接比数字即可。
  static const Map<String, int> LEVEL = <String, int>{
    'CRITICAL': 5,
    'EXTREME': 4,
    'HARD': 3,
    'REGULAR': 2,
    'FAIL': 0,
    'FUMBLE': -1,
  };

  /// 稳定的 ASCII 键，给事件 payload / 测试断言用（中文文案改了不影响协议）
  static const Map<String, String> LEVEL_KEY = <String, String>{
    '5': 'critical',
    '4': 'extreme',
    '3': 'hard',
    '2': 'regular',
    '0': 'fail',
    '-1': 'fumble',
  };

  static const Map<String, String> LEVEL_TEXT = <String, String>{
    '5': '大成功',
    '4': '极难成功',
    '3': '困难成功',
    '2': '常规成功',
    '0': '失败',
    '-1': '大失败',
  };

  static const Map<String, Map<String, Object?>> DIFFICULTY =
      <String, Map<String, Object?>>{
    'regular': <String, Object?>{'required': 2, 'text': '常规', 'div': 1},
    'hard': <String, Object?>{'required': 3, 'text': '困难', 'div': 2},
    'extreme': <String, Object?>{'required': 4, 'text': '极难', 'div': 5},
  };

  /// 攻击结算的结局枚举（契约 §4.1）。
  static const Map<String, String> OUTCOME = <String, String>{
    'HIT': 'hit',
    'MISS': 'miss',
    'ATTACKER_WINS': 'attacker_wins',
    'DEFENDER_WINS': 'defender_wins',
  };

  /// 四种常见故障（KP 可在弹层指定，缺省按武器类型自动选）。
  static const Map<String, int> JAM_TYPES = <String, int>{
    'jam': 1,
    'feed': 1,
    'dud': 1,
    'burst': 1,
  };

  /// 上限常量：测试与界面提示要引用同一份数字。
  static const Map<String, int> limits = <String, int>{
    'MAX_DICE': 100,
    'MAX_SIDES': 1000,
  };

  @override
  Map<String, int> get levelMap => LEVEL;

  // ---- 1. 阈值与成功等级 ------------------------------------
  Map<String, Object?> thresholds(Object? base) => _thresholds(base);

  int targetOf(Object? base, Object? difficulty) =>
      _targetOf(base, difficulty);

  @override
  String normDifficulty(Object? d) => _normDifficulty(d);

  Map<String, Object?> fumbleRange(
    Object? target, [
    Map<String, Object?>? opts,
  ]) =>
      _fumbleRange(target, opts);

  bool isFumble(
    Object? value,
    Object? target, [
    Map<String, Object?>? opts,
  ]) =>
      _isFumble(value, target, opts);

  int levelOf(
    Object? value,
    Object? base, [
    Object? target,
    Map<String, Object?>? opts,
  ]) =>
      _levelOf(value, base, target, opts);

  int critThresholdOf(Map<String, Object?>? opts) => _critThresholdOf(opts);

  int fumbleThresholdOf(Map<String, Object?>? opts) =>
      _fumbleThresholdOf(opts);

  // ---- 2. 掷骰 ----------------------------------------------
  Map<String, Object?> rollD100(Map<String, Object?>? opts) =>
      _rollD100(opts ?? const <String, Object?>{});

  int combine(Object? tens, Object? ones) => _combine(tens, ones);

  // ---- 3. 检定 ----------------------------------------------
  @override
  Map<String, Object?> check(Map<String, Object?> opts) => _check(opts);

  String describeCheck(Map<String, Object?> r) => _describeCheck(r);

  @override
  Map<String, Object?> canPush(Map<String, Object?>? result, [Object? kind]) =>
      _canPush(result, kind);

  Map<String, Object?> luckAllowed(Object? kind) => _luckAllowed(kind);

  @override
  Map<String, Object?> spendLuck(Map<String, Object?>? opts) =>
      _spendLuck(opts ?? const <String, Object?>{});

  // ---- 4. 对抗 ----------------------------------------------
  @override
  Map<String, Object?> opposed(Object? a, Object? b) => _opposed(a, b);

  Map<String, Object?> opposedReroll(Object? aRoll, Object? bRoll) =>
      _opposedReroll(aRoll, bRoll);

  Map<String, Object?> opposedAttack(
    Object? a,
    Object? b, [
    Map<String, Object?>? o,
  ]) =>
      _opposedAttack(a, b, o ?? const <String, Object?>{});

  @override
  Map<String, Object?> opposedFull(
    Object? a,
    Object? b, [
    Map<String, Object?>? o,
  ]) =>
      _opposedFull(a, b, o ?? const <String, Object?>{});

  // ---- 5. 骰式与伤害 ----------------------------------------
  @override
  Map<String, Object?> parseExpr(Object? expr) => _parseExpr(expr);

  @override
  Map<String, Object?> rollExpr(Object? expr, [JsRng? rng]) =>
      _rollExpr(expr, rng);

  @override
  Map<String, Object?> rollDamageBonus(Object? expr, [JsRng? rng]) =>
      _rollDamageBonus(expr, rng);

  int maxOfExpr(Object? expr) => _maxOfExpr(expr);

  int maxOfDamageBonus(Object? dbStr) => _maxOfDamageBonus(dbStr);

  @override
  Map<String, Object?> impaleDamage(Object? expr, Object? db, [JsRng? rng]) =>
      _impaleDamage(expr, db, rng);

  @override
  int burstMaxOf(Object? perRound) => _burstMaxOf(perRound);

  bool isBurstWeapon(Object? perRound) => _isBurstWeapon(perRound);

  int malfunctionThresholdOf(Object? weapon) =>
      _malfunctionThresholdOf(weapon);

  @override
  Map<String, Object?> malfunctionOf(
    Object? weapon,
    Object? rollValue, [
    Map<String, Object?>? opts,
  ]) =>
      _malfunctionOf(weapon, rollValue, opts);

  @override
  String defaultMalfunctionType(Object? weapon) =>
      _defaultMalfunctionType(weapon);

  @override
  Map<String, Object?> malfunctionEffect(
    Object? weapon,
    Object? type, [
    JsRng? rng,
  ]) =>
      _malfunctionEffect(weapon, type, rng);

  // ---- 6. SAN / 伤势 ----------------------------------------
  @override
  Map<String, Object?> parseSanLoss(Object? expr) => _parseSanLoss(expr);

  @override
  Map<String, Object?> resolveSanCheck(Map<String, Object?> opts) =>
      _resolveSanCheck(opts);

  Map<String, Object?> insanityFlags(Map<String, Object?>? opts) =>
      _insanityFlags(opts ?? const <String, Object?>{});

  Map<String, Object?> damageFlags(Map<String, Object?>? opts) =>
      _damageFlags(opts ?? const <String, Object?>{});

  @override
  Map<String, Object?> dyingRoundCheck(Object? con, [JsRng? rng]) =>
      _dyingRoundCheck(con, rng);

  @override
  Map<String, Object?> temporaryInsanityCheck(
    Object? intValue, [
    JsRng? rng,
  ]) =>
      _temporaryInsanityCheck(intValue, rng);

  int boutRounds([JsRng? rng]) => _boutRounds(rng);

  // ---- 7. 行动顺序 / 战斗结算 ------------------------------
  @override
  Map<String, Object?> initiativeOrder(
    Object? actors, [
    Map<String, Object?>? opts,
  ]) =>
      _initiativeOrder(actors, opts);

  Map<String, Object?> advanceTurn(
    Object? index,
    Object? round,
    Object? queueLength,
  ) =>
      _advanceTurn(index, round, queueLength);

  @override
  Map<String, Object?> resolveAttack(Map<String, Object?> o) =>
      _resolveAttack(o);

  // ---- 8. 角色卡取值 ---------------------------------------
  @override
  int? skillValue(Object? sheet, Object? name) => _skillValue(sheet, name);

  @override
  int? attrValue(Object? sheet, Object? key) => _attrValue(sheet, key);

  // ---- 9. 场景检定步骤 -------------------------------------
  Map<String, Object?> sceneStepPlan(Object? step) => _sceneStepPlan(step);

  @override
  Map<String, Object?> sceneStepResolve(Object? step, Object? level) =>
      _sceneStepResolve(step, level);
}
