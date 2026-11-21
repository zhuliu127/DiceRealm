// ============================================================
// room_model_actions_room.dart — S4.3 房间/场景/素材/地图/手绘板动作（D17）
//
// 本文件承担两件事：
//   ① 三个动作文件共用的「模块级纯助手」（旧版 room-model.js 的
//      num/clampNumber/clamp01/clampToMax/pick/memberStatusValue/... 等）
//      以 `ra*` 前缀公开导出，避免 D18/D19/D15 各自重复实现；
//   ② extension RoomHostActionsRoom on RoomHost：
//      dispatchRoomAction(seat,p) + 房间/场景/素材/地图/手绘板全部处理器。
//
// ⚠️ 纯 Dart：不得引入 Flutter 包、文件 I/O 或 UI 库（C1/K7）。
// ⚠️ 所有状态变更一律走 RoomHost.emit/apply（唯一写口），本文件不出现
//    第二处归约口，也不在事件流之外伪造权威状态。
// ============================================================

import 'js_compat.dart';
import 'room_model_actions_sheet.dart';
import 'room_model_host_core.dart';
import 'room_model_rollback.dart';
import 'room_model_save.dart' show RoomHostSave;
import 'room_model_state.dart';
import 'room_ports.dart';
import 'room_types.dart';

// ============================================================
// 常量（与 room-model.js:150 / 7171-7201 / 4371 对齐）
// ============================================================

/// 奖惩骰上限（`MOD_CAP`）。
const int kRaModCap = 5;

/// 对抗记录文案前缀。
const String kRaOpposedPrefix = '⚔ 对抗｜';

/// 疯狂症状类型白名单。
const Set<String> kRaMadTypes = <String>{'phobia', 'mania', 'bout'};

/// 精神状态合法取值。
///
/// P8（需求 6）：**删掉「昏迷」**（昏迷是身体状态，见 kRaBodyOk + dying/unconscious），
/// 新增「潜在疯狂」；老值「不定疯狂（症状消失）」仍被接受，读入时翻译成新名。
const Set<String> kRaMentalOk = <String>{
  '正常',
  '临时疯狂',
  '不定疯狂',
  '潜在疯狂',
  '不定疯狂（症状消失）',
  '疯狂症状',
  '永久疯狂',
  '其他',
};

/// 身体状态（伤级）白名单。
const Set<String> kRaBodyOk = <String>{'正常', '轻伤', '重伤', '死亡'};

const String kRaMentalPermanent = '永久疯狂';
const String kRaMentalSymptom = '疯狂症状';
const String kRaMentalIndef = '不定疯狂';

/// 「潜在疯狂」：不定疯狂的症状随轮次消退后的状态。
/// 此时再损失任意 SAN（>0）立即复发为不定疯狂并新生成一条症状。
const String kRaMentalPotential = '潜在疯狂';

/// 历史取值（老存档 / 老日志）。新代码一律用 [kRaMentalPotential]。
const String kRaMentalLegacyPotential = '不定疯狂（症状消失）';

/// 兼容旧名：老调用点（含事件日志字段 `from`）仍写 kRaMentalIndefFaded。
const String kRaMentalIndefFaded = kRaMentalPotential;

/// 九项属性键（与角色卡契约一致）。
const List<String> kRaAttrKeys = <String>[
  'str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu', 'luck',
];

/// 单调计数用的「未设置」哨兵，用于 `deriveBodyFromHp` 表达旧版
/// `undefined = 该项不动`。Dart 没有 undefined，用常量对象区分。
const Object kRaUnset = _RaUnset();

class _RaUnset {
  const _RaUnset();
}

// ============================================================
// 模块级纯助手
// ============================================================

/// 把任意值按 JS 的 `Number(v)` 解释成有限数；失败返回 null。
num? raFinite(Object? v) {
  if (v == null) return null;
  if (v is num) {
    if (v.isNaN || v.isInfinite) return null;
    return v;
  }
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    final low = t.toLowerCase();
    if (low.startsWith('0x')) {
      final h = int.tryParse(t.substring(2), radix: 16);
      return h;
    }
    final d = double.tryParse(t);
    if (d == null || d.isNaN || d.isInfinite) return null;
    return d == d.truncateToDouble() ? d.toInt() : d;
  }
  return null;
}

/// JS `num(v, dflt)`：`Number(v)` 有限则原样，否则回落 [dflt]。
num raNum(Object? v, [num dflt = 0]) => raFinite(v) ?? dflt;

/// JS `Math.max(lo, Math.min(hi, Math.round(Number(v))))`；无效 → [dflt]。
num raClampNumber(Object? v, num lo, num hi, num dflt) {
  if (v == null) return dflt;
  final f = raFinite(v);
  if (f == null) return dflt;
  final r = jsRound(f);
  if (r < lo) return lo;
  if (r > hi) return hi;
  return r;
}

/// 同上，但缺省回落 null（供白名单里「未登记」的字段使用）。
num? raClampNumberOrNull(Object? v, num lo, num hi) {
  if (v == null) return null;
  final f = raFinite(v);
  if (f == null) return null;
  final r = jsRound(f);
  if (r < lo) return lo;
  if (r > hi) return hi;
  return r;
}

/// JS `clamp01`：相对坐标夹到 0..1（非有限 → 0）。
num raClamp01(Object? v) {
  final f = raFinite(v);
  if (f == null) return 0;
  if (f < 0) return 0;
  if (f > 1) return 1;
  return f;
}

/// JS `clampToMax(v, max)`：上界必须 > 0 才夹，否则原值返回。
num raClampToMax(Object? v, Object? max) {
  final f = raFinite(v);
  if (f == null) return 0;
  final hi = raFinite(max);
  if (hi == null || !(hi > 0)) return f;
  return f > hi ? hi : f;
}

/// JS `pick(a,b)`：非 undefined/null 取 a。
Object? raPick(Object? a, Object? b) => a ?? b;

/// 公开昵称：优先角色名，其次昵称；KP 回落 meta.kpName / 'KP'。
String raNick(RoomHost h, Map<String, Object?>? m, String seat) {
  if (m != null && jsTruthy(m['charName'])) return jsStr(m['charName']);
  if (m != null && jsTruthy(m['nickname'])) return jsStr(m['nickname']);
  if (seat == kHostSeat) {
    final kp = asMap(h.state['meta'])['kpName'];
    return jsTruthy(kp) ? jsStr(kp) : 'KP';
  }
  return '某人';
}

/// 单位显示名（绝不把 seat/actorId 当名字）。
String raUnitName(RoomHost h, Map<String, Object?>? m, String seat) {
  if (m != null) {
    final cn = cleanText(m['charName'], 40);
    if (cn.isNotEmpty) return cn;
    final nn = cleanText(m['nickname'], 40);
    if (nn.isNotEmpty) return nn;
  }
  if (seat == kHostSeat) {
    final kp = asMap(h.state['meta'])['kpName'];
    return jsTruthy(kp) ? jsStr(kp) : 'KP';
  }
  return '未知单位';
}

/// 读成员 HP/MP/SAN 现值：sheet.status → runtime → sheet 顶层。
num? raMemberStatusValue(Object? mRaw, String key) {
  final m = asMap(mRaw);
  const runtimeKey = <String, String>{
    'currentHP': 'hp',
    'currentMP': 'mp',
    'currentSAN': 'san',
  };
  final sh = asMap(m['sheet']);
  final st = asMap(sh['status']);
  var v = raFinite(st[key]);
  if (v != null) return v;
  final rk = runtimeKey[key];
  if (rk == null) return null;
  v = raFinite(asMap(m['runtime'])[rk]);
  if (v != null) return v;
  return raFinite(sh[rk]);
}

/// 读成员九项属性之一。
num? raMemberAttr(Object? mRaw, String key) {
  final attrs = asMap(asMap(asMap(mRaw)['sheet'])['attrs']);
  final v = attrs[key];
  if (v == null || v == '') return null;
  return raFinite(v);
}

/// 是否已撕卡（死亡 / 永久疯狂）。
bool raMemberRipped(Object? mRaw) {
  final m = asMap(mRaw);
  final sh = m['sheet'];
  if (sh == null) return false;
  final sheet = asMap(sh);
  if (asMap(sheet['status'])['body'] == '死亡') return true;
  return asList(sheet['mental']).contains(kRaMentalPermanent);
}

/// 是否处于疯狂发作中（临时 / 不定疯狂）。
bool raMemberInBout(Object? mRaw) {
  final mental = asList(asMap(asMap(mRaw)['sheet'])['mental']);
  return mental.contains('临时疯狂') || mental.contains(kRaMentalIndef);
}

/// KP 定向 SAN 指令的发作判定（与 memberInBout 同口径，独立保留）。
bool raMemberMadActive(Object? mRaw) => raMemberInBout(mRaw);

/// 背景症状判据：bg 标记，或兼容老数据 permanent && !from。
bool raIsBgSymptom(Object? xRaw) {
  if (xRaw == null) return false;
  final x = asMap(xRaw);
  if (x['bg'] == true) return true;
  return x['permanent'] == true && !jsTruthy(x['from']);
}

/// 整组症状是否全部来自背景（严格逐条判据）。
bool raOnlyBgSymptoms(Object? list) {
  if (list is! List || list.isEmpty) return false;
  for (final x in list) {
    if (!raIsBgSymptom(x)) return false;
  }
  return true;
}

/// JS `deriveBodyFromHp(prevBody, amount, after, maxHP)`。
/// 返回 `{body?, dying?, unconscious?, needCon}`；键缺失 = 旧版 undefined（该项不动）。
Map<String, Object?> raDeriveBodyFromHp(
  String prevBodyRaw,
  num amountRaw,
  num afterRaw,
  num maxHPRaw,
) {
  final prevBody = jsTruthy(prevBodyRaw) ? prevBodyRaw : '正常';
  final amount = raNum(amountRaw, 0) < 0 ? 0 : raNum(amountRaw, 0);
  final after = raNum(afterRaw, 0) < 0 ? 0 : raNum(afterRaw, 0);
  final maxHP = raNum(maxHPRaw, 0);
  final isMajorHit = maxHP > 0 && amount * 2 >= maxHP;
  var needCon = false;
  Object? body = kRaUnset;
  Object? dying = kRaUnset;
  Object? unconscious = kRaUnset;

  if (maxHP > 0 && amount > maxHP) {
    body = '死亡';
    dying = false;
    unconscious = false;
  } else if (after <= 0) {
    final hadMajor = isMajorHit || prevBody == '重伤' || prevBody == '濒死';
    if (hadMajor) {
      body = '重伤';
      dying = true;
    } else {
      unconscious = true;
    }
  } else if (isMajorHit) {
    body = '重伤';
    dying = false;
    needCon = prevBody != '重伤' && prevBody != '濒死';
  } else if (prevBody == '濒死') {
    dying = false;
    body = (maxHP > 0 && after * 2 >= maxHP)
        ? (after >= maxHP ? '正常' : '轻伤')
        : '重伤';
  } else if (prevBody == '重伤') {
    if (maxHP > 0 && after * 2 >= maxHP) {
      body = after >= maxHP ? '正常' : '轻伤';
      dying = false;
    }
  } else if (prevBody == '昏迷') {
    // 昏迷不降级：唤醒由急救 / 治愈负责。
  } else {
    body = (maxHP > 0 && after >= maxHP) ? '正常' : '轻伤';
  }

  final out = <String, Object?>{'needCon': needCon};
  if (!identical(body, kRaUnset)) out['body'] = body;
  if (!identical(dying, kRaUnset)) out['dying'] = dying;
  if (!identical(unconscious, kRaUnset)) out['unconscious'] = unconscious;
  return out;
}

/// 战斗槽是否已倒下 / 死亡。
bool raSlotDown(Object? slotRaw) {
  final slot = asMap(slotRaw);
  if (slot.isEmpty) return false;
  final pub = asMap(slot['public']);
  if (jsTruthy(pub['down']) || pub['state'] == 'dead') return true;
  final hp = pub['hp'];
  final hpMax = raFinite(pub['hpMax']) ?? 0;
  if (hp != null && hpMax > 0 && (raFinite(hp) ?? 0) <= 0) return true;
  return false;
}

/// 归一「手输检定值」：空 / 非法 → null（不按 0 结算）。
num? raNormBase(Object? v) {
  if (v == null || v == '') return null;
  return raFinite(v);
}

/// 归一防守方式：counter/fightback/反击→counter；dodge/闪避→dodge；其余 none。
String raNormReaction(Object? r) {
  final s = (r == null ? '' : jsStr(r)).trim().toLowerCase();
  if (s == 'counter' || s == 'fightback' || s == '反击') return 'counter';
  if (s == 'dodge' || s == '闪避') return 'dodge';
  return 'none';
}

/// 归一 SAN 损失的一侧（空值给默认，其余原样字符串）。
String raNormLossPart(Object? v, String dflt) {
  if (v == null) return dflt;
  final s = jsStr(v).trim();
  return s.isEmpty ? dflt : s;
}

/// 逐轮重掷明细文案（以 '；' 前缀拼接）。
String raBuildOpposedRerollLines(
  Object? roundsRaw,
  String aName,
  String bName,
  bool fallback,
) {
  final rounds = asList(roundsRaw);
  if (rounds.isEmpty) return '';
  final lines = <String>[];
  for (final rRaw in rounds) {
    final r = asMap(rRaw);
    final who = r['winner'] == 'a'
        ? aName
        : (r['winner'] == 'b' ? bName : '继续重掷');
    lines.add('重掷 ${r['round']}：$aName 掷 ${r['aRoll']} vs '
        '$bName 掷 ${r['bRoll']} → $who 胜');
  }
  var s = '；${lines.join('；')}';
  if (fallback) s += '；达到重掷上限，按规则兜底判发起方胜';
  return s;
}

/// 把武器伤害式转成可掷骰式（剥 DB 记号 / 退化到前导骰式）。
Map<String, Object?> raWeaponDamageExpr(Object? dmg, RoomRulesPort? rules) {
  var s = (dmg == null ? '' : jsStr(dmg)).trim();
  if (s.isEmpty) {
    return <String, Object?>{'ok': false, 'expr': '', 'reason': '武器没有伤害式'};
  }
  s = s
      .replaceAll(RegExp(r'[+＋]?\s*半?\s*D\.?B\.?', caseSensitive: false), '')
      .replaceAll(RegExp(r'[+＋\-\s]+$'), '')
      .replaceAll(RegExp(r'\s+'), '');
  bool okExpr(String x) => x.isNotEmpty && (rules?.parseExpr(x)['ok'] == true);
  if (okExpr(s)) {
    return <String, Object?>{'ok': true, 'expr': s, 'reason': ''};
  }
  final m = RegExp(r'^(\d*[dD]\d+(?:[+-]\d+)*)').firstMatch(s);
  if (m != null && okExpr(m.group(1)!)) {
    return <String, Object?>{'ok': true, 'expr': m.group(1)!, 'reason': ''};
  }
  return <String, Object?>{
    'ok': false,
    'expr': '',
    'reason': '武器伤害式无法解析：$s',
  };
}

/// 从疯狂症状表掷一个「疯狂发作」症状（临时，带轮数）。
Map<String, Object?>? raRollSymptom(RoomMadnessPort? madness) {
  if (madness == null) return null;
  final m = madness.roll('any', false);
  if (m == null) return null;
  final type = m['type'];
  return <String, Object?>{
    'type': kRaMadTypes.contains(type) ? type : 'phobia',
    'name': m['name'],
    'en': m['en'] ?? '',
    'desc': m['desc'] ?? '',
    'permanent': false,
    'rounds': m['rounds'] ?? 0,
  };
}

// ============================================================
// P17 KP-2 · 场景检定「检定方式」四档（Q1 拍板：结果等级当成功阈值）
//
// ⚠️ 大小写是这里唯一的历史坑：老 APP 2.13.13 的 UI/载荷发**大写**
//    `REGULAR/HARD/EXTREME`，而规则层 `DIFFICULTY` 的键是**小写**，
//    `normDifficulty` 对未知值回落 `regular` ⇒ 困难/极难**静默退化成常规**
//    （新 APP 原来也一样：`gp_scene_check_kp.dart` 发小写 `regular`、
//    `sheet_scene.dart` 发大写 `REGULAR`、本文件白名单认大写）。
//    修法：入库前统一走 [raNormSceneDifficulty]，模型里只留下面四个**大写**值。
//
// ⚠️ `CocRules.DIFFICULTY` 只有三档（无 critical），且
//    `test/fixtures/room_rules.json` 逐字节钉死
//    `normDifficulty('HARD') == 'regular'`（老 APP 退化行为的等价快照）。
//    ⇒ **不许改规则层的归一函数**，也不许给 `DIFFICULTY` 加大写键；
//      四档阈值在下面独立实现（[raDifficultyThreshold]），CRITICAL 走 `== 1` 特判。
// ============================================================

/// 常规成功：掷骰 ≤ 技能值。
const String kRaDifficultyRegular = 'REGULAR';

/// 困难成功：掷骰 ≤ floor(技能值 / 2)。
const String kRaDifficultyHard = 'HARD';

/// 极难成功：掷骰 ≤ floor(技能值 / 5)。
const String kRaDifficultyExtreme = 'EXTREME';

/// 大成功：只有掷出 01（`== 1`）才算成功。
const String kRaDifficultyCritical = 'CRITICAL';

/// 四档全序（从易到难）—— UI 选择器 / 白名单 / 测试的唯一真源。
///
/// 顺序对齐用户口径「大成功 / 成功 / 困难成功 / 极难成功」的**难度**排列
/// 反向（由易到难）：成功 → 困难成功 → 极难成功 → 大成功。
const List<String> kRaDifficultyLevels = <String>[
  kRaDifficultyRegular,
  kRaDifficultyHard,
  kRaDifficultyExtreme,
  kRaDifficultyCritical,
];

/// 难度规范名：**全大写**入库，未知值回落常规（对齐老 APP `normDifficulty`）。
///
/// 唯一入口：任何写进模型 / 载荷的 `difficulty` 都必须先过这里，
/// 这样大小写不同的同一档不会在链路上被当成两档。
String raNormSceneDifficulty(Object? raw) {
  switch (jsStr(raw ?? '').trim().toUpperCase()) {
    case kRaDifficultyHard:
      return kRaDifficultyHard;
    case kRaDifficultyExtreme:
      return kRaDifficultyExtreme;
    case kRaDifficultyCritical:
      return kRaDifficultyCritical;
    default:
      return kRaDifficultyRegular;
  }
}

/// 四档「成功阈值」：掷骰值 `<=` 返回值即成功。
///
/// 算式与老 APP `room-rules.js:120-123 thresholds(base)` 一致（向下取整），
/// 第四档 CRITICAL 是新增特判：只有 01。
int raDifficultyThreshold(Object? base, Object? difficulty) {
  final b = raNum(base, 0).toInt();
  final n = b < 0 ? 0 : b;
  switch (raNormSceneDifficulty(difficulty)) {
    case kRaDifficultyHard:
      return n ~/ 2;
    case kRaDifficultyExtreme:
      return n ~/ 5;
    case kRaDifficultyCritical:
      return 1;
    default:
      return n;
  }
}

/// 四档判定：`value`（掷出的 1-100）是否达到该档要求。
///
/// ★ CRITICAL 的语义是「只有掷出 01」，所以必须 `value == 1`；
///   用 `value <= 1` 会把非法值 0 / 负数也判成功，这里显式挡掉。
bool raDifficultyPasses(Object? value, Object? base, Object? difficulty) {
  final v = raNum(value, 0).toInt();
  if (v < 1 || v > 100) return false;
  return v <= raDifficultyThreshold(base, difficulty);
}

/// 四档对应的「结果等级」下限（`CocRules.LEVEL` 口径）。
///
/// 规则服务缺失时的兜底求值用它（[raDefaultSceneResolve]）；
/// 常规 2 / 困难 3 / 极难 4 / 大成功 5。
int raDifficultyRequiredLevel(Object? difficulty) {
  switch (raNormSceneDifficulty(difficulty)) {
    case kRaDifficultyHard:
      return 3;
    case kRaDifficultyExtreme:
      return 4;
    case kRaDifficultyCritical:
      return 5;
    default:
      return 2;
  }
}

/// 场景检定分支白名单。
Map<String, Object?> raSanitizeBranch(Object? bRaw) {
  final b = asMap(bRaw);
  return <String, Object?>{
    'damage': cleanText(b['damage'], 20),
    'note': cleanText(b['note'], 120),
    'next': cleanText(b['next'], 24),
  };
}

/// 场景检定步骤数组白名单（最多 60 步）。
///
/// ★ P17 KP-2：`difficulty` 走 [raNormSceneDifficulty]，四档**全大写**入库；
///   未知值（含历史存档里的 `bogus`）仍回落 `REGULAR`，与
///   `fixtures/room_model.json#M:sanitizeSceneSteps#957` 逐字节一致。
List<Map<String, Object?>> raSanitizeSceneSteps(Object? arr) {
  final out = <Map<String, Object?>>[];
  final list = asList(arr);
  for (var i = 0; i < list.length && i < 60; i++) {
    final s = asMap(list[i]);
    out.add(<String, Object?>{
      'id': cleanText(s['id'], 24).isNotEmpty
          ? cleanText(s['id'], 24)
          : 'st${i + 1}',
      'title': cleanText(s['title'], 60).isNotEmpty
          ? cleanText(s['title'], 60)
          : '步骤 ${i + 1}',
      'desc': cleanText(s['desc'], 200),
      'targetSeat': cleanText(s['targetSeat'], 64),
      'skill': cleanText(s['skill'], 30),
      'difficulty': raNormSceneDifficulty(s['difficulty']),
      'bonus': raClampNumber(s['bonus'], 0, kRaModCap, 0),
      'penalty': raClampNumber(s['penalty'], 0, kRaModCap, 0),
      'onSuccess': raSanitizeBranch(s['onSuccess']),
      'onFailure': raSanitizeBranch(s['onFailure']),
    });
  }
  return out;
}

/// 场景检定分支兜底求值（规则服务缺失时用）。
///
/// ★ P17 KP-2：成功门槛从写死的 `>= 2` 改成按步骤难度取
///   [raDifficultyRequiredLevel]（常规 2 / 困难 3 / 极难 4 / 大成功 5）。
///   常规档行为与改前完全一致，只有困难 / 极难 / 大成功不再被当成常规。
Map<String, Object?> raDefaultSceneResolve(Object? stepRaw, Object? level) {
  final step = asMap(stepRaw);
  final b = raNum(level, 0) >= raDifficultyRequiredLevel(step['difficulty'])
      ? raSanitizeBranch(step['onSuccess'])
      : raSanitizeBranch(step['onFailure']);
  return <String, Object?>{
    'damage': jsTruthy(b['damage']) ? b['damage'] : '',
    'note': jsTruthy(b['note']) ? b['note'] : '',
    'next': jsTruthy(b['next']) ? b['next'] : '',
  };
}

// ============================================================
// 房间/场景/素材/地图/手绘板动作
// ============================================================

extension RoomHostActionsRoom on RoomHost {
  /// 房间组动作分发。**返回 null 表示该 op 不属于本组**（由 D18/D19 接手）。
  /// ★ P19：把一份存档快照广播给全员（`RoomEvt.saveSync`，public）。
  ///
  /// 载荷校验：必须有 `code`（与 `save()` 的 20 键结构一致），否则给系统
  /// 提示且**不广播** —— 防止把坏快照散到所有玩家手机上。
  List<SendPlan> shareSave(String seat, Map<String, Object?> p) {
    final save = asMap(p['save']);
    // ⚠️ `jsStr(null)` 返回 'null'（JS 语义）—— 不能用它判空，缺 code 的
    //    快照会被当成「房间号叫 null」广播出去（P19 测试②踩过）。
    final codeRaw = asMap(save)['code'];
    final code = (codeRaw == null || !jsTruthy(codeRaw)) ? '' : jsStr(codeRaw);
    final out = <SendPlan>[];
    if (save.isEmpty || code.isEmpty) {
      pushInto(out, sys('没有可分发的存档（快照为空或缺房间号）'));
      return out;
    }
    return _roomPush(emit(RoomEvt.saveSync, <String, Object?>{
      'save': roomClone(save),
      'from': seat,
      'at': now(),
    }, vis: RoomVis.public));
  }

  List<SendPlan>? dispatchRoomAction(String seat, Map<String, Object?> p) {
    final op = jsStr(p['op']);
    switch (op) {
      // ---- 房间生命周期 ----
      case 'room.start':
        return roomActionStart();
      case 'room.kick':
        return kick(jsStr(p['seat']));
      case 'room.close':
        return closeRoom();
      case 'room.end':
      case 'session.end':
        return endSession();
      case 'room.suspend':
        return suspendRoom(seat);
      case 'room.resume':
        return resumeRoom(seat);
      case 'room.rules':
        return setRoomRules(p);

      // ---- ★ P19 存档分发 ----
      // KP 把本机存档快照广播给全员（每回合 / 每 10 分钟 / 结束房间 /
      // 结团 / 玩家加入时由 `RoomSaveSyncer` 自动触发）。玩家端在 session
      // 层拦截落盘（`LocalLoopbackSession._captureNotice`），不参与 reduce。
      case 'save.share':
        return shareSave(seat, p);

      // ---- 场景 ----
      case 'scene.set':
        return _roomPush(emit(RoomEvt.scene, <String, Object?>{'scene': p['scene']},
            vis: RoomVis.public));
      case 'scene.reveal':
        return revealAsset(p['id'], p['revealed'] != false);
      case 'scene.clue':
        return sceneClue(seat, p);
      case 'scene.mode':
        return modeChanged(p['mode']);

      // ---- 素材 ----
      case 'asset.add':
        return addAsset(p['asset']);
      case 'asset.reveal':
        return revealAsset(p['id'], p['revealed'] != false);
      case 'asset.cover':
        return coverAsset(p['id']);
      case 'asset.del':
        return delAsset(p['id']);

      // ---- 地图 ----
      case 'map.mark':
        return mapMark(p);
      case 'map.stroke':
        return mapStroke(p);
      case 'map.clear':
        return mapClear(p);
      case 'map.strokes.set':
        return mapStrokesSet(p);

      // ---- 手绘板 / 背包 ----
      case 'board.self':
        return boardSelf(seat, p);
      case 'item.del':
        return delItem(seat, p);

      // ---- 战斗候选池 / 纯 UI ----
      case 'combat.pool.set':
        return setActorPool(p);
      case 'combat.prepare':
        // 纯 UI：打开选怪流程，不产生任何事件（契约 §5.3）。
        return const <SendPlan>[];

      // ---- 回合 / 回退 ----
      case 'round.next':
      case 'rollback.round':
        return roomActionNextRound();
      case 'rollback.commit':
        return rollbackCommit(seat);
      case 'rollback.turn':
        // Q6 休眠项：分支保留，入口已从 POLICY 摘除（伪造 ACT 被 needs 拒绝）。
        return rollbackPropose(seat, jsNum(p['turns']));

      // ---- INTENT 级动作在 ACT 通道的等价别名 ----
      // 旧版这些 op 由 intent() 直接处理；ACT 通道也给出真实结算，
      // 保证 61 个 POLICY action 在 applyAction 里都有真实分支。
      case 'chat':
        return roomActionChat(seat, p);
      case 'dice.request':
        return roomActionDiceRequest(seat, p);
      case 'ready.set':
        return roomActionReady(seat, p);
      case 'char.share':
        return roomActionCharShare(seat, p);
      default:
        return null;
    }
  }

  /// 便捷包装：把单条事件的分发计划作为结果返回。
  List<SendPlan> _roomPush(LogRecord rec) => pushInto(<SendPlan>[], rec);

  /// 开团：进入 IN_GAME，首回合边界，系统播报（旧版 :1705-1712）。
  List<SendPlan> roomActionStart() {
    final out = <SendPlan>[];
    out.addAll(setStatus(RoomStatus.inGame));
    if (!(raNum(asMap(state['meta'])['round'], 0) >= 1)) {
      pushInto(out,
          emit(RoomEvt.round, <String, Object?>{'round': 1}, vis: RoomVis.public));
    }
    pushInto(out, sys('开团！'));
    return out;
  }

  /// 探索态「进入下一回合」：统一回合出口 + 系统播报（旧版 :1847-1855）。
  List<SendPlan> roomActionNextRound() {
    final nextRound = raNum(asMap(state['meta'])['round'], 0) + 1;
    final out = <SendPlan>[];
    out.addAll(advanceRound(nextRound.toInt()));
    pushInto(out, sys('进入第 ${nextRound.toInt()} 回合'));
    return out;
  }

  /// ACT 通道的 chat 别名（与 INTENT.CHAT 同形）。
  List<SendPlan> roomActionChat(String seat, Map<String, Object?> p) {
    final text = cleanText(p['text'], 600);
    if (text.isEmpty) return const <SendPlan>[];
    return _roomPush(emit(RoomEvt.chat, <String, Object?>{
      'seat': seat,
      'nickname': raNick(this, roster.get(seat), seat),
      'text': text,
      'at': now(),
      'kind': 'user',
    }, vis: RoomVis.public));
  }

  /// ACT 通道的 dice.request 别名（与 INTENT.DICE 非 direct 同形）。
  List<SendPlan> roomActionDiceRequest(String seat, Map<String, Object?> p) {
    final expr = cleanText(p['expr'], 40);
    return _roomPush(emit(RoomEvt.log, <String, Object?>{
      'seat': seat,
      'text': '${raNick(this, roster.get(seat), seat)} 请求掷 $expr',
      'at': now(),
      'kind': 'dice-request',
      'expr': expr,
    }, vis: RoomVis.public));
  }

  /// ACT 通道的 ready.set 别名（与 INTENT.READY 同形）。
  ///
  /// 🔒 目标座位**只能是发起者本人**：`ready.set` 的 POLICY 角色只有
  /// `RoomRole.player`（`room_types.dart:245`），KP 连调用权都没有，因此
  /// 不存在「KP 代设准备状态」的正当代操作路径；老 APP 的 ACT 通道也没有
  /// 这条 op（只有 INTENT 侧按 `seat` 本人处理）。早前按客户端传来的
  /// `p['seat']` 当目标，等于任何玩家都能把别人强制设为已准备。
  List<SendPlan> roomActionReady(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    // 客户端传来的 `p['seat']` 只当「自带座位」，指向他人即拒
    // （守卫写法对齐同文件 `delItem` 的「只能删除自己的物品」）。
    final asked = cleanText(p['seat'], 64);
    if (asked.isNotEmpty && asked != seat) {
      pushInto(out, sysTo(seat, '只能设置自己的准备状态'));
      return out;
    }
    final target = seat;
    final mem = roster.get(target);
    if (mem == null || mem['role'] != RoomRole.player) {
      pushInto(out, sysTo(target, '旁观者不能设准备状态'));
      return out;
    }
    if (jsTruthy(p['ready']) && !jsTruthy(mem['charId'])) {
      pushInto(out, sysTo(target, '请先选择角色卡'));
      return out;
    }
    mem['ready'] = jsTruthy(p['ready']);
    out.addAll(syncMembers());
    pushInto(out, sys('${raNick(this, mem, target)}'
        '${jsTruthy(mem['ready']) ? ' 已准备' : ' 取消准备'}'));
    return out;
  }

  /// ACT 通道的 `char.share`。
  ///
  /// 🔒 同 [roomActionReady]：目标座位只能是发起者本人。`char.share` 的
  /// POLICY 角色同样只有 `RoomRole.player`，KP 无权调用；INTENT 侧的
  /// `shareSheet` 也只用 `seat` 本人。早前读客户端 `p['seat']` 会让任意玩家
  /// 换掉别人的角色卡。
  ///
  /// ★ P11：**委托给 INTENT 侧的 [RoomHostSave.shareSheet]**，和
  ///   `INTENT.CHAR` 走同一条结算链路。早前这里自己拼 `charName` / `charId`
  ///   两个字段，把 `p['sheet']`（整份角色卡数据）整块丢掉 —— 结果是「有卡名、
  ///   无卡数据」的成员，角色卡面板只能落到「数值还没同步到」的占位分支。
  ///   sheet 覆盖、`sanitizeSheet` 白名单、tempStatus / items 贴回、runtime
  ///   现值写入，全部只有那一处实现，这里不再另立一份。
  List<SendPlan> roomActionCharShare(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final asked = cleanText(p['seat'], 64);
    if (asked.isNotEmpty && asked != seat) {
      pushInto(out, sysTo(seat, '只能上报自己的角色卡'));
      return out;
    }
    final target = seat;
    final mem = roster.get(target);
    if (mem == null) {
      pushInto(out, sysTo(target, '旁观者不需要上报角色卡'));
      return out;
    }
    return shareSheet(jsStr(mem['role']), target, mem, p);
  }

  /// 懒创建 scene 骨架（键序与旧版 `_ensureScene` 一致）。
  Map<String, Object?> ensureScene() {
    var sc = state['scene'];
    if (sc is! Map) {
      sc = <String, Object?>{
        'title': '',
        'image': '',
        'assets': <Object?>[],
        'marks': <Object?>[],
        'strokes': <Object?>[],
        'boards': <String, Object?>{},
      };
      state['scene'] = sc;
    }
    final s = asMap(sc);
    if (s['assets'] is! List) s['assets'] = <Object?>[];
    if (s['marks'] is! List) s['marks'] = <Object?>[];
    if (s['strokes'] is! List) s['strokes'] = <Object?>[];
    if (s['boards'] is! Map) s['boards'] = <String, Object?>{};
    return s;
  }

  /// 用局部字段生成一条完整的 scene（客户端整块替换）。
  Map<String, Object?> sceneWith(Object? s, Map<String, Object?> patch) {
    final next = <String, Object?>{};
    final src = asMap(s);
    for (final e in src.entries) {
      next[e.key] = roomClone(e.value);
    }
    for (final e in patch.entries) {
      next[e.key] = e.value;
    }
    return next;
  }

  /// 切模式：探索 / 战斗（旧版 :1880-1885）。
  List<SendPlan> modeChanged(Object? modeRaw) {
    final mode = modeRaw == RoomMode.combat
        ? RoomMode.combat
        : RoomMode.exploration;
    final out = <SendPlan>[];
    pushInto(
      out,
      emit(RoomEvt.status, <String, Object?>{
        'status': asMap(state['meta'])['status'],
        'mode': mode,
      }, vis: RoomVis.public),
    );
    asMap(state['meta'])['mode'] = mode;
    return out;
  }

  /// 新增素材：只进 KP 私有库，公开必须显式 reveal（旧版 :1892-1911）。
  List<SendPlan> addAsset(Object? assetRaw) {
    final asset = asMap(assetRaw);
    localSeq += 1;
    final rec = <String, Object?>{
      'id': 'a$localSeq',
      'kind': cleanText(asset['kind'], 20).isNotEmpty
          ? cleanText(asset['kind'], 20)
          : 'map',
      'name': cleanText(asset['name'], 60).isNotEmpty
          ? cleanText(asset['name'], 60)
          : '素材',
      'data': asset['data'] ?? '',
      'revealed': false,
      'at': now(),
    };
    localAssets.add(rec);
    if (localAssets.length > 60) localAssets.removeAt(0);
    final out = <SendPlan>[];
    pushInto(out, emitLocal('asset.added', <String, Object?>{
      'asset': roomClone(rec),
    }));
    pushInto(out, sysTo(kHostSeat, '你上传了素材「${rec['name']}」（尚未公开）'));
    return out;
  }

  /// 公开 / 隐藏素材（旧版 :1914-1932）。
  ///
  /// ★ P16 KP-2「公开互斥」：同一时刻只允许一张素材公开。公开某张时，
  ///   其余已公开素材自动取消公开（`localAssets.revealed=false` 同步 KP 侧
  ///   列表状态），并清理指向它们的 `scene.image`；被互斥隐藏的素材也按现有
  ///   「已隐藏」文案补公开记录。事件/广播结构沿用旧口径 —— 一条
  ///   `RoomEvt.asset` 携带互斥后的完整公开列，reduce 整列替换，客户端同步。
  ///   舞台 `gp_map_stage.dart` 取 `publicAssets.last`，互斥后天然只剩一张。
  List<SendPlan> revealAsset(Object? idRaw, bool revealed) {
    final id = jsStr(idRaw);
    Map<String, Object?>? a;
    for (final x in localAssets) {
      if (x['id'] == id) a = x;
    }
    if (a == null) {
      return <SendPlan>[
        ..._roomPush(sysTo(kHostSeat, '找不到该素材')),
      ];
    }
    a['revealed'] = revealed;
    final s = ensureScene();

    // 公开互斥：先把其余已公开素材取消公开，记下名字用于补「已隐藏」记录。
    final hiddenNames = <String>[];
    if (revealed) {
      for (final x in localAssets) {
        if (x['id'] != id && x['revealed'] == true) {
          x['revealed'] = false;
          hiddenNames.add(jsStr(x['name']));
        }
      }
    }

    // 公开列：互斥后至多只剩目标一张（直接收敛，不依赖旧 scene.assets
    // 是否残留）；隐藏时沿用旧口径，只剔除目标本身。
    final pub = <Object?>[];
    if (revealed) {
      pub.add(roomClone(a));
    } else {
      for (final x in asList(s['assets'])) {
        if (jsStr(asMap(x)['id']) != id) pub.add(x);
      }
    }

    final out = <SendPlan>[];
    // 与现有 reveal 的 emit 写法一致：整列广播，隐藏项在客户端自然消失。
    pushInto(out, emit(RoomEvt.asset, <String, Object?>{'assets': pub},
        vis: RoomVis.public));
    for (final name in hiddenNames) {
      pushInto(out, sys('素材「$name」已隐藏'));
    }

    // scene.image 清理：指向本次隐藏的目标，或指向任一被互斥隐藏的旧素材
    // （即已不在最终公开列里）时清空，照旧发一条 RoomEvt.scene。
    final img = jsStr(s['image']);
    final imageStillPublic =
        img.isNotEmpty && pub.any((x) => jsStr(asMap(x)['id']) == img);
    if (img.isNotEmpty && !imageStillPublic) {
      s['image'] = '';
      pushInto(out, emit(RoomEvt.scene, <String, Object?>{
        'scene': sceneWith(s, <String, Object?>{'image': ''}),
      }, vis: RoomVis.public));
    }
    pushInto(out, sys(revealed ? '素材「${a['name']}」已公开' : '素材「${a['name']}」已隐藏'));
    return out;
  }

  // P16 KP-2：封面按钮已删、改为「公开互斥」，本函数保留但无新调用点
  // （勿删，兼容旧存档 / asset.cover 事件与旧调用方）。
  /// KP 指定中央底图：只能选已公开素材（旧版 :1941-1963）。
  List<SendPlan> coverAsset(Object? idRaw) {
    final id = cleanText(idRaw, 24);
    final s = ensureScene();
    final out = <SendPlan>[];
    if (id.isEmpty) {
      s['image'] = '';
      pushInto(out, emit(RoomEvt.scene, <String, Object?>{
        'scene': sceneWith(s, <String, Object?>{'image': ''}),
      }, vis: RoomVis.public));
      pushInto(out, sys('KP 清除了中央底图'));
      return out;
    }
    Map<String, Object?>? hit;
    for (final x in asList(s['assets'])) {
      if (asMap(x)['id'] == id) hit = asMap(x);
    }
    if (hit == null) {
      pushInto(out, sysTo(kHostSeat, '只能把「已公开」的素材设为底图'));
      return out;
    }
    s['image'] = id;
    pushInto(out, emit(RoomEvt.scene, <String, Object?>{
      'scene': sceneWith(s, <String, Object?>{'image': id}),
    }, vis: RoomVis.public));
    pushInto(out, sys('KP 把底图换成了「${hit['name'] ?? '素材'}」'));
    return out;
  }

  /// 删除素材：私有库 + 公共画面一起撤（旧版 :1972-2002）。
  List<SendPlan> delAsset(Object? idRaw) {
    final id = cleanText(idRaw, 24);
    final before = localAssets.length;
    Map<String, Object?>? removed;
    localAssets.removeWhere((a) {
      if (a['id'] == id) {
        removed = a;
        return true;
      }
      return false;
    });
    final s = ensureScene();
    final pub = asList(s['assets']);
    final hadPub = pub.any((x) => asMap(x)['id'] == id);
    final out = <SendPlan>[];
    if (hadPub) {
      s['assets'] = pub.where((x) => asMap(x)['id'] != id).toList();
      pushInto(out, emit(RoomEvt.asset, <String, Object?>{
        'assets': roomClone(s['assets']),
      }, vis: RoomVis.public));
      pushInto(out, sysTo(kHostSeat, '已从公开画面撤下该素材'));
      if (s['image'] == id) {
        s['image'] = '';
        pushInto(out, emit(RoomEvt.scene, <String, Object?>{
          'scene': sceneWith(s, <String, Object?>{'image': ''}),
        }, vis: RoomVis.public));
      }
    }
    if (removed == null && !hadPub) {
      pushInto(out, sysTo(kHostSeat, '找不到该素材（可能已被删除）'));
      return out;
    }
    pushInto(out, sysTo(kHostSeat,
        '已删除素材「${removed?['name'] ?? '素材'}」（私有库 $before → ${localAssets.length}）'));
    return out;
  }

  /// 删除玩家背包里的一件物品（按 id，幂等；旧版 :2012-2035）。
  List<SendPlan> delItem(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final target = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : bySeat;
    if (bySeat != kHostSeat && target != bySeat) {
      pushInto(out, sysTo(bySeat, '只能删除自己的物品'));
      return out;
    }
    final m = roster.get(target);
    if (m == null) {
      pushInto(out, sysTo(bySeat, '找不到该玩家，无法删除物品'));
      return out;
    }
    final items = asMap(m['sheet'])['items'];
    if (items is! List) {
      pushInto(out, sysTo(bySeat, '该玩家背包里没有物品'));
      return out;
    }
    final id = cleanText(p['id'], 24);
    final list = List<Object?>.from(asList(items));
    var idx = -1;
    for (var i = 0; i < list.length; i++) {
      if (asMap(list[i])['id'] == id) idx = i;
    }
    if (idx < 0) return out;
    final gone = asMap(list[idx]);
    list.removeAt(idx);
    out.addAll(stateApply(target, <String, Object?>{'items': list},
        <String, Object?>{'reason': '删除物品：${gone['name'] ?? '物品'}'}));
    return out;
  }

  /// 地图标记（相对坐标 0..1；旧版 :2304-2323）。
  List<SendPlan> mapMark(Map<String, Object?> p) {
    final s = ensureScene();
    localSeq += 1;
    final mark = <String, Object?>{
      'id': 'm$localSeq',
      'x': raClamp01(p['x']),
      'y': raClamp01(p['y']),
      'kind': cleanText(p['kind'], 16).isNotEmpty
          ? cleanText(p['kind'], 16)
          : 'dot',
      'label': cleanText(p['label'], 24),
      'assetId': p['assetId'] ?? '',
      'revealed': p['revealed'] != false,
      'at': now(),
    };
    final out = <SendPlan>[];
    if (mark['revealed'] == false) {
      pushInto(out, emitLocal('mark.hidden', <String, Object?>{
        'mark': roomClone(mark),
      }));
      return out;
    }
    final marks = List<Object?>.from(asList(s['marks']))..add(mark);
    pushInto(out, emit(RoomEvt.scene, <String, Object?>{
      'scene': sceneWith(s, <String, Object?>{'marks': marks}),
    }, vis: RoomVis.public));
    return out;
  }

  /// 地图笔迹（旧版 :2325-2337）。
  List<SendPlan> mapStroke(Map<String, Object?> p) {
    final s = ensureScene();
    localSeq += 1;
    final pts = <Object?>[];
    for (final qRaw in asList(p['pts']).take(2000)) {
      final q = asMap(qRaw);
      pts.add(<String, Object?>{
        'x': raClamp01(q['x']),
        'y': raClamp01(q['y']),
      });
    }
    if (pts.isEmpty) return const <SendPlan>[];
    final stroke = <String, Object?>{
      'id': 'p$localSeq',
      'color': cleanText(p['color'], 16).isNotEmpty
          ? cleanText(p['color'], 16)
          : '#e74c3c',
      'width': raNum(p['width'], 3),
      'pts': pts,
    };
    final strokes = List<Object?>.from(asList(s['strokes']))..add(stroke);
    return _roomPush(emit(RoomEvt.scene, <String, Object?>{
      'scene': sceneWith(s, <String, Object?>{'strokes': strokes}),
    }, vis: RoomVis.public));
  }

  /// 一键清除：只清笔迹（不写公开记录；旧版 :2348-2354）。
  List<SendPlan> mapClear(Map<String, Object?> p) {
    final s = ensureScene();
    final marks = jsTruthy(p['strokesOnly'])
        ? asList(s['marks'])
        : <Object?>[];
    return _roomPush(emit(RoomEvt.scene, <String, Object?>{
      'scene': sceneWith(s, <String, Object?>{
        'strokes': <Object?>[],
        'marks': marks,
      }),
    }, vis: RoomVis.public));
  }

  /// 整集替换笔迹（实时橡皮擦 / 撤销单笔；旧版 :2364-2383）。
  List<SendPlan> mapStrokesSet(Map<String, Object?> p) {
    final s = ensureScene();
    final strokes = <Object?>[];
    for (final stRaw in asList(p['strokes'])) {
      if (strokes.length >= 4000) break;
      final st = asMap(stRaw);
      final pts = asList(st['pts']);
      if (pts.isEmpty) continue;
      localSeq += 1;
      final cleanPts = <Object?>[];
      for (final qRaw in pts.take(2000)) {
        final q = asMap(qRaw);
        cleanPts.add(<String, Object?>{
          'x': raClamp01(q['x']),
          'y': raClamp01(q['y']),
        });
      }
      strokes.add(<String, Object?>{
        'id': cleanText(st['id'], 40).isNotEmpty
            ? cleanText(st['id'], 40)
            : 'p$localSeq',
        'color': cleanText(st['color'], 16).isNotEmpty
            ? cleanText(st['color'], 16)
            : '#e74c3c',
        'width': raNum(st['width'], 3),
        'pts': cleanPts,
      });
    }
    return _roomPush(emit(RoomEvt.scene, <String, Object?>{
      'scene': sceneWith(s, <String, Object?>{'strokes': strokes}),
    }, vis: RoomVis.public));
  }

  /// 个人手绘板：正文只回本人（旧版 :2404-2412）。
  List<SendPlan> boardSelf(String seat, Map<String, Object?> p) {
    final strokes = asList(p['strokes']).take(4000).toList();
    final at = now();
    boardBySeat[seat] = <String, Object?>{
      'strokes': roomClone(strokes),
      'at': at,
    };
    return _roomPush(emit(RoomEvt.board, <String, Object?>{
      'seat': seat,
      'self': true,
      'strokes': strokes,
      'at': at,
    }, vis: RoomVis.seat, to: seat));
  }

  /// 线索发给目标玩家：逐人单发，不进公共流（旧版 :1721-1735）。
  List<SendPlan> sceneClue(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final spec = jsStr(p['seat']);
    final targets = spec == '*'
        ? roster.onlinePlayers().map((m) => jsStr(m['seat'])).toList()
        : <String>[spec];
    for (final t in targets) {
      pushInto(out, emit(RoomEvt.private_, <String, Object?>{
        'title': jsTruthy(p['title']) ? p['title'] : '线索',
        'text': p['text'] ?? '',
        'at': now(),
      }, vis: RoomVis.seat, to: t));
    }
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': seat,
      'text': spec == '*' ? '（KP 给全体玩家递了线索）' : '（KP 私下递了一张纸条）',
      'at': now(),
      'kind': 'note',
    }, vis: RoomVis.public));
    return out;
  }

  /// 整体替换「开战前候选池」：纯本地状态，不产生事件（旧版 :3914-3932）。
  List<SendPlan> setActorPool(Map<String, Object?> p) {
    final list = asList(p['actors']);
    final seen = <String>{};
    final next = <Map<String, Object?>>[];
    for (final aRaw in list) {
      final a = asMap(aRaw);
      final id = jsStr(a['id']);
      if (!jsTruthy(a['id']) || seen.contains(id)) continue;
      if (a['kind'] != 'monster' && a['kind'] != 'npc') continue;
      seen.add(id);
      final hp = raNum(a['hp'], 0);
      next.add(<String, Object?>{
        'id': cleanText(a['id'], 40),
        'name': cleanText(a['name'], 24).isNotEmpty
            ? cleanText(a['name'], 24)
            : '单位',
        'kind': a['kind'],
        'dex': raNum(a['dex'], 0),
        'hp': hp,
        'hpMax': raNum(a['hpMax'], hp),
        'actionsPerRound': raClampNumber(a['actionsPerRound'], 1, 10, 1),
        // ★ P16 KP-8：候选池保留护甲。仅当上游带 armor 时加键 —— 老存档 /
        //   老载荷无此键时结构逐字节不变（不打红 action oracle）。
        if (a.containsKey('armor')) 'armor': raNum(a['armor'], 0),
        // ★ PL-1b（任务 A）：候选池记录同样透传可见性标记 —— 仅上游
        //   显式带键时才加，归一成 bool；缺键 = 默认不公开（防泄露），
        //   老存档 / 老载荷结构逐字节不变（不打红 action oracle）。
        if (a.containsKey('visibleToPlayers'))
          'visibleToPlayers': jsTruthy(a['visibleToPlayers']),
      });
    }
    localActors
      ..clear()
      ..addAll(next);
    return const <SendPlan>[];
  }

  /// 候选池追加一个单位（同 id 视为已存在）。
  bool addLocalActor(Map<String, Object?>? actorRaw) {
    final actor = asMap(actorRaw);
    if (!jsTruthy(actor['id'])) return false;
    if (actor['kind'] != 'monster' && actor['kind'] != 'npc') return false;
    for (final a in localActors) {
      if (a['id'] == actor['id']) return false;
    }
    // ★ PL-1b（任务 A）：候选池的第二个入口。原实现把上游 actor 记录
    //   **原样**加入（不做任何字段筛选），所以上游带的 `visibleToPlayers`
    //   天然保留、`_actorRecords()` 能读到；缺键时按默认不公开。
    //   此处刻意不复制 / 不归一化：入参可能是不可变 map，写入会抛；
    //   与 [setActorPool] 的「仅上游显式带键才加」口径一致且零漂移。
    localActors.add(actor);
    return true;
  }

  /// 挂起房间（旧版 :6855-6864）。
  List<SendPlan> suspendRoom(String bySeat) {
    final out = <SendPlan>[];
    if (asMap(state['meta'])['status'] == RoomStatus.suspended) {
      pushInto(out, sysTo(bySeat, '房间已经处于挂起状态'));
      return out;
    }
    out.addAll(setStatus(RoomStatus.suspended));
    pushInto(out, sys('房间已挂起，存档保留 30 天，可改天续玩'));
    return out;
  }

  /// 复活挂起房间（旧版 :6867-6877）。
  List<SendPlan> resumeRoom(String bySeat) {
    final out = <SendPlan>[];
    out.addAll(setStatus(RoomStatus.recruiting));
    pushInto(out, sys('房间已复活，继续跑团'));
    for (final m in roster.list()) {
      if (jsTruthy(m['online'])) {
        final s = jsStr(m['seat']);
        out.add(SendPlan(s, syncFor(s)));
      }
    }
    return out;
  }

  /// 修改房间的检定成败阈值（旧版 :5566-5591）。
  List<SendPlan> setRoomRules(Map<String, Object?> p) {
    final out = <SendPlan>[];
    final critRaw = p['critThreshold'];
    final fumbleRaw = p['fumbleThreshold'];
    num crit;
    num fumble;
    if (critRaw == null || jsStr(critRaw).trim().isEmpty) {
      crit = 1;
    } else {
      crit = raNum(critRaw, double.nan);
      if (!(crit >= 1 && crit <= 100)) {
        pushInto(out, sysTo(kHostSeat, '大成功阈值需为 1–100 的整数'));
        return out;
      }
    }
    if (fumbleRaw == null ||
        jsStr(fumbleRaw).trim().isEmpty ||
        raNum(fumbleRaw, 0) == 0) {
      fumble = 100;
    } else {
      fumble = raNum(fumbleRaw, double.nan);
      if (!(fumble >= 1 && fumble <= 100)) {
        pushInto(out, sysTo(kHostSeat, '大失败阈值需为 1–100 的整数'));
        return out;
      }
    }
    final meta = asMap(state['meta']);
    meta['critThreshold'] = crit;
    meta['fumbleThreshold'] = fumble;
    pushInto(out, emit(RoomEvt.hello, <String, Object?>{
      'meta': roomClone(meta),
    }, vis: RoomVis.public));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'kind': 'sys',
      'text': 'KP 设置了检定阈值：大成功 掷出 ≤ ${raNum(crit, 1).toInt()}；'
          '大失败 ${fumble == 100 ? '按规则书动态判定（要求阈值 < 50 时 96-100，否则仅 100）' : '掷出 ≥ ${raNum(fumble, 100).toInt()}'}',
      'at': now(),
    }, vis: RoomVis.public));
    return out;
  }
}
