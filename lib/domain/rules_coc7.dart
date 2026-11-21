// ============================================================
// rules_coc7.dart — COC 7th 规则系统
// 逐行对应 `core/rules-coc7.js` 的 `COC7`（769 行）
//
// 本项目最重要的架构约束（原注释，保留）：
//   所有规则计算集中在此，UI 层不得硬编码任何公式。
//
// ⚠️ 与 JS 的**唯一**结构差异（Dart 没有全局对象）：
//   JS 里 `COC7.validators.occupationChoices / skillPoints / skillCap /
//   creditRating` 会反向调用 `CocOccupation`（职业层），构成循环依赖。
//   Dart 的 import 不能成环，所以这 4 个校验器搬到 `occupation.dart`
//   （函数名、输出形状、文案逐字不变），其余保持在本文件。
//
// 所有返回值都是 `Map<String, Object?>`，键名与 JS 对象**逐字一致** ——
// 这样 oracle 等价性测试可以把 JS 的 JSON 直接与 Dart 的输出对比，
// 而不需要写一层「字段映射」。这是有意的。
// ============================================================

import 'character.dart';
import 'dice.dart';
import 'edu_check.dart';
import 'js_compat.dart';
import 'madness_state.dart' as ms;

/* ---------- 属性定义 ---------- */
const List<Map<String, Object?>> attributes = <Map<String, Object?>>[
  <String, Object?>{
    'key': 'str',
    'abbr': 'STR',
    'name': '力量',
    'desc': '肌肉能力的量化。决定近战伤害加值。',
  },
  <String, Object?>{
    'key': 'con',
    'abbr': 'CON',
    'name': '体质',
    'desc': '健康、生气和活力。',
  },
  <String, Object?>{
    'key': 'siz',
    'abbr': 'SIZ',
    'name': '体型',
    'desc': '身高和体重整合成的数字。',
  },
  <String, Object?>{
    'key': 'dex',
    'abbr': 'DEX',
    'name': '敏捷',
    'desc': '迅捷灵敏程度，决定闪避初始值。',
  },
  <String, Object?>{
    'key': 'app',
    'abbr': 'APP',
    'name': '外貌',
    'desc': '肉体吸引力和人格魅力。',
  },
  <String, Object?>{
    'key': 'int',
    'abbr': 'INT',
    'name': '智力',
    'desc': '学习力、理解力、信息分析力。决定兴趣技能点。',
  },
  <String, Object?>{
    'key': 'pow',
    'abbr': 'POW',
    'name': '意志',
    'desc': '心意的力量。决定初始理智与魔法值。',
  },
  <String, Object?>{
    'key': 'edu',
    'abbr': 'EDU',
    'name': '教育',
    'desc': '受教育的程度。决定母语初始值。',
  },
  <String, Object?>{
    'key': 'luck',
    'abbr': 'LUCK',
    'name': '幸运',
    'desc': '运气。初始值之后不再起作用，上限永远是 99。',
    'optional': true,
  },
];

/// `key → 属性定义`
final Map<String, Map<String, Object?>> attrMap =
    <String, Map<String, Object?>>{
      for (final a in attributes) jsStr(a['key']): a,
    };

/// 中文名 / 缩写 / key → key（用于职业属性公式里写「教育×4」「智力或教育×2」）
const Map<String, String> cn2key = <String, String>{
  '力量': 'str',
  'STR': 'str',
  'str': 'str',
  '体质': 'con',
  'CON': 'con',
  'con': 'con',
  '体型': 'siz',
  'SIZ': 'siz',
  'siz': 'siz',
  '敏捷': 'dex',
  'DEX': 'dex',
  'dex': 'dex',
  '外貌': 'app',
  'APP': 'app',
  'app': 'app',
  '智力': 'int',
  '灵感': 'int',
  'INT': 'int',
  'int': 'int',
  '意志': 'pow',
  'POW': 'pow',
  'pow': 'pow',
  '教育': 'edu',
  'EDU': 'edu',
  'edu': 'edu',
  '幸运': 'luck',
  '运气': 'luck',
  'LUCK': 'luck',
  'luck': 'luck',
};

/* ---------- 属性生成规则 ---------- */
const int genMin = 15;
const int genMax = 90;
const int genStep = 5;

/// 随机掷骰方案 (COC 7e 标准)：[骰数, 面数, 加值]，结果再 ×5
const Map<String, List<int>> genRandomDice = <String, List<int>>{
  'str': <int>[3, 6, 0],
  'con': <int>[3, 6, 0],
  'dex': <int>[3, 6, 0],
  'app': <int>[3, 6, 0],
  'pow': <int>[3, 6, 0],
  'luck': <int>[3, 6, 0],
  'siz': <int>[2, 6, 6],
  'int': <int>[2, 6, 6],
  'edu': <int>[2, 6, 6],
};

/* ---------- 年龄调整表 ----------
   physLoss 是「力量/体质/敏捷三项合计」要扣的总量，由本引擎平均分摊
   （见 spreadLoss），单项最低扣到 15 为止，不会把某一项扣穿。 */
const List<Map<String, Object?>> ageTable = <Map<String, Object?>>[
  <String, Object?>{
    'max': 19,
    'physLoss': 5,
    'appLoss': 0,
    'movLoss': 0,
    'eduChecks': 0,
    'note': '力量与体型合计 −5（平均分摊），之后骰 2 次幸运取较大值',
  },
  <String, Object?>{
    'max': 39,
    'physLoss': 0,
    'appLoss': 0,
    'movLoss': 0,
    'eduChecks': 1,
    'note': '无属性扣减，教育进步检定 1 次',
  },
  <String, Object?>{
    'max': 49,
    'physLoss': 5,
    'appLoss': 5,
    'movLoss': 1,
    'eduChecks': 2,
    'note': '力量/体质/敏捷合计 −5（三项平均分摊），外貌 −5，移动 −1，教育进步检定 2 次',
  },
  <String, Object?>{
    'max': 59,
    'physLoss': 10,
    'appLoss': 10,
    'movLoss': 2,
    'eduChecks': 3,
    'note': '力量/体质/敏捷合计 −10（三项平均分摊），外貌 −10，移动 −2，教育进步检定 3 次',
  },
  <String, Object?>{
    'max': 69,
    'physLoss': 20,
    'appLoss': 15,
    'movLoss': 3,
    'eduChecks': 4,
    'note': '力量/体质/敏捷合计 −20（三项平均分摊），外貌 −15，移动 −3，教育进步检定 4 次',
  },
  <String, Object?>{
    'max': 79,
    'physLoss': 40,
    'appLoss': 20,
    'movLoss': 4,
    'eduChecks': 4,
    'note': '力量/体质/敏捷合计 −40（三项平均分摊），外貌 −20，移动 −4，教育进步检定 4 次',
  },
  <String, Object?>{
    'max': 89,
    'physLoss': 80,
    'appLoss': 25,
    'movLoss': 5,
    'eduChecks': 4,
    'note': '力量/体质/敏捷合计 −80（三项平均分摊），外貌 −25，移动 −5，教育进步检定 4 次',
  },
  <String, Object?>{
    'max': 999,
    'physLoss': 80,
    'appLoss': 25,
    'movLoss': 5,
    'eduChecks': 4,
    'note': '力量/体质/敏捷合计 −80（三项平均分摊），外貌 −25，移动 −5，教育进步检定 4 次',
  },
];

/// 年龄 → 区间规则
Map<String, Object?> ageRule(Object? age) {
  final a = jsNum(age);
  for (final rule in ageTable) {
    if (a <= jsNum(rule['max'])) return rule;
  }
  return ageTable.last;
}

/* ---------- 年龄调整（真正生效，而不是只写一句提示） ----------
 * 规则书：年龄区间要扣减 力量/体质/敏捷（合计值，由玩家自行分配）与 外貌，
 *         并降低移动力；20 岁以上还有若干次教育进步检定。
 *
 * 设计取舍：**不改写玩家输入的原始属性**。
 *   直接改会被三件事污染且不可逆 —— 掷骰结果、购点上限校验、来回改年龄时的叠加扣减。
 *   所以这里额外算出一份「生效属性 eff」，派生属性、技能基础值（母语=EDU、闪避=DEX/2）
 *   与角色卡展示全部走这份数值；界面上把「原始 → 生效」并排显示，玩家一眼看懂扣在哪。
 */

/// 物理扣减的单项下限。
/// 3D6×5 的理论最低值是 15 —— 扣到这个数就不再往下扣。
/// 没有这条下限时，高龄角色的力量会被一路扣成个位数，
/// 而体质、敏捷纹丝不动，属性表一眼就畸形。
const int physFloor = 15;

/// 把 total 点扣减**平均**摊到 keys 指定的属性上。
///
/// 早先的写法是「按固定顺序填满一个再填下一个」，于是 69 岁的角色
/// 会把力量扣穿、体质敏捷几乎不动。改成逐点轮转：每个属性各扣一点，
/// 再回到第一个，直到点数用完或全部触底 —— 三项的扣减量最多相差 1。
///
/// 逐点轮转（而不是一次性除以份数）是为了同时满足「尽量平均」与
/// 「单项不低于下限」：某个属性触底后，剩余点数自动流向还有余量的属性。
///
/// @param total 要扣的总点数
/// @param keys  参与分摊的属性 key（顺序固定 → 结果可复现，不会因刷新而变）
/// @param caps  每个属性最多能扣多少（通常是 raw − 下限）
/// @returns `{'loss': Map<String,int>, 'remain': int}`；
///          remain > 0 表示点数多到全部触底都用不完
Map<String, Object?> spreadLoss(
  int total,
  List<String> keys,
  Map<String, int> caps,
) {
  final loss = <String, int>{for (final k in keys) k: 0};
  var remain = total < 0 ? 0 : total;
  while (remain > 0) {
    var moved = false;
    for (var i = 0; i < keys.length && remain > 0; i++) {
      final k = keys[i];
      final cap = (caps[k] ?? 0) < 0 ? 0 : (caps[k] ?? 0);
      if (loss[k]! < cap) {
        loss[k] = loss[k]! + 1;
        remain--;
        moved = true;
      }
    }
    if (!moved) break; // 全部触底，剩下的点数无处可扣
  }
  return <String, Object?>{'loss': loss, 'remain': remain};
}

/// 某个属性最多能被扣掉多少（扣到下限为止）
int lossCapOf(Object? value, int floor) {
  final v = jsNum(value) - floor;
  return v < 0 ? 0 : v;
}

/// 年龄调整结果（键名与 `ageAdjust()` 返回对象完全一致）
///
/// ```
/// { age, rule, raw, eff, loss, totalLoss, physLoss, appLoss, movLoss,
///   eduChecks, eduBonus, unapplied, floor, active }
/// ```
Map<String, Object?> ageAdjust(Map<String, Object?>? attrs) {
  final a = attrs ?? <String, Object?>{};
  final ageRaw = jsNum(a['age']);
  final age = ageRaw != 0 ? ageRaw : 25;
  final rule = ageRule(age);

  final raw = <String, int>{
    'str': jsNum(a['str']),
    'con': jsNum(a['con']),
    'siz': jsNum(a['siz']),
    'dex': jsNum(a['dex']),
    'app': jsNum(a['app']),
    'int': jsNum(a['int']),
    'pow': jsNum(a['pow']),
    'edu': jsNum(a['edu']),
    'luck': jsNum(a['luck']),
  };
  final loss = <String, int>{'str': 0, 'con': 0, 'siz': 0, 'dex': 0, 'app': 0};
  /* 因为触底而没能扣掉的点数。规则给的扣减量是固定的，
     属性本身太低时会扣不满 —— 这个值必须暴露出去，
     否则界面上「合计 −20」与实际生效的差值会变成一个说不清的谜。 */
  var unapplied = 0;

  if (age <= 19) {
    // 少年（15-19）：力量与体型合计 −5，同样平均摊
    final physLoss = jsNum(rule['physLoss']);
    final rT = spreadLoss(
      physLoss != 0 ? physLoss : 5,
      <String>['str', 'siz'],
      <String, int>{
        'str': lossCapOf(raw['str'], physFloor),
        'siz': lossCapOf(raw['siz'], physFloor),
      },
    );
    final l = asMap(rT['loss']);
    loss['str'] = loss['str']! + jsNum(l['str']);
    loss['siz'] = loss['siz']! + jsNum(l['siz']);
    unapplied += jsNum(rT['remain']);
  } else {
    // 中老年：力量/体质/敏捷合计扣减，三项平均分摊
    final physLoss = jsNum(rule['physLoss']);
    final rP = spreadLoss(
      physLoss,
      <String>['str', 'con', 'dex'],
      <String, int>{
        'str': lossCapOf(raw['str'], physFloor),
        'con': lossCapOf(raw['con'], physFloor),
        'dex': lossCapOf(raw['dex'], physFloor),
      },
    );
    final l = asMap(rP['loss']);
    loss['str'] = loss['str']! + jsNum(l['str']);
    loss['con'] = loss['con']! + jsNum(l['con']);
    loss['dex'] = loss['dex']! + jsNum(l['dex']);
    unapplied += jsNum(rP['remain']);
  }
  loss['app'] = jsMin(<int>[raw['app']!, jsNum(rule['appLoss'])]);

  // 教育进步检定带来的增益（a.eduBonus）：同样不进 raw，只作用于生效值。
  // 这样购点上限校验仍然看玩家购买的原始 EDU，不会被检定结果污染。
  final eduBonus = jsNum(a['eduBonus']);

  final eff = <String, int>{};
  raw.forEach((k, v) {
    final cut = loss[k] ?? 0;
    eff[k] = (v - cut) < 0 ? 0 : (v - cut);
  });
  if (eduBonus > 0) eff['edu'] = jsMin(<int>[99, eff['edu']! + eduBonus]);

  var totalLoss = 0;
  loss.forEach((k, v) => totalLoss += v);

  return <String, Object?>{
    'age': age,
    'rule': rule,
    'raw': raw,
    'eff': eff,
    'loss': loss,
    'totalLoss': totalLoss,
    'physLoss': loss['str']! + loss['con']! + loss['dex']! + loss['siz']!,
    'appLoss': loss['app'],
    'movLoss': jsNum(rule['movLoss']),
    'eduChecks': jsNum(rule['eduChecks']),
    'eduBonus': eduBonus,
    /** 应扣但被 15 下限挡住、最终没扣成的点数 */
    'unapplied': unapplied,
    /** 物理扣减的单项下限，界面提示会引用它 */
    'floor': physFloor,
    /** 是否有任何实际生效的调整 */
    'active': totalLoss > 0 || jsNum(rule['movLoss']) > 0 || eduBonus > 0,
  };
}

/// 取角色当前生效属性（含年龄调整 + 教育进步检定增益），供技能基础值等下游使用
Map<String, int> effectiveAttrs(Character character) {
  final a = <String, Object?>{...character.attributes};
  a['age'] = character.basicInfo['age'];
  a['eduBonus'] = eduBonusOf(character);
  return asMap(ageAdjust(a)['eff']).map((k, v) => MapEntry(k, jsNum(v)));
}

/// 教育进步检定累计增益
int eduBonusOf(Character? character) {
  final p = character?.eduProgress;
  if (p == null || p.isEmpty) return 0;
  final b = p['bonus'];
  if (b != null && b != '') return jsNum(b);
  // 兼容：早期只写了 log 的数据
  var t = 0;
  for (final r in asList(p['log'])) {
    t += jsNum(asMap(r)['gain']);
  }
  return t;
}

/* ---------- 教育进步检定 ----------
 * 规则书：年龄区间带来的「教育进步检定」不是直接把 EDU 加上去，
 * 而是每一次都掷 1D100：结果 > 当前 EDU 才算进步，EDU +1D10（上限 99）。
 * 所以这里提供真正的掷骰函数，由界面显式调用 —— 不静默改写玩家的属性。
 *
 * 判定与封顶都在 `edu_check.dart#eduCheck`（纯函数，可单测逐条钉边界），
 * 这里只负责按同一顺序消耗随机数：先 1D100，**进步了才**再掷 1D10。
 * 掷骰顺序与旧实现逐字一致 —— oracle 夹具里那几个 eduImproveCheck 用例
 * 比的就是「消耗几次随机数、结果是什么」。
 */
Map<String, Object?> eduImproveCheck(Object? currentEdu, [JsRng? rng]) {
  final cur = jsNum(currentEdu);
  final r = roll(1, 100, rng);
  // 失败时不掷 1D10（随机数消耗数也是契约的一部分，别改）
  final d10 = r > cur ? roll(1, 10, rng) : 0;
  final res = eduCheck(cur, r, d10);
  return <String, Object?>{
    'roll': res.roll,
    'edu': res.after,
    'gain': res.gain,
    'success': res.success,
  };
}

/* ---------- 伤害加值 / 体格表 ---------- */
const List<Map<String, Object?>> dbTable = <Map<String, Object?>>[
  <String, Object?>{'min': 2, 'max': 64, 'db': '-2', 'build': -2},
  <String, Object?>{'min': 65, 'max': 84, 'db': '-1', 'build': -1},
  <String, Object?>{'min': 85, 'max': 124, 'db': '0', 'build': 0},
  <String, Object?>{'min': 125, 'max': 164, 'db': '+1D4', 'build': 1},
  <String, Object?>{'min': 165, 'max': 204, 'db': '+1D6', 'build': 2},
  <String, Object?>{'min': 205, 'max': 284, 'db': '+2D6', 'build': 3},
  <String, Object?>{'min': 285, 'max': 364, 'db': '+3D6', 'build': 4},
  <String, Object?>{'min': 365, 'max': 444, 'db': '+4D6', 'build': 5},
];

/// STR+SIZ → 伤害加值 / 体格
Map<String, Object?> dbBuild(num strSizRaw) {
  var strSiz = strSizRaw;
  if (strSiz < 2) strSiz = 2;
  for (final row in dbTable) {
    if (strSiz >= jsNum(row['min']) && strSiz <= jsNum(row['max'])) {
      return <String, Object?>{'db': row['db'], 'build': row['build']};
    }
  }
  // 超过 444：每再超过 80 点，+1D6 伤害加值与 +1 体格
  final extra = ((strSiz - 445) / 80).floor() + 1;
  return <String, Object?>{'db': '+${4 + extra}D6', 'build': 5 + extra};
}

/* ============================================================
 * 派生属性计算
 * ============================================================ */
Map<String, Object?> derived(Map<String, Object?> attrs) {
  // 全部基于「年龄调整后」的生效属性来算：
  // 属性被扣了，HP / 移动力 / 伤害加值 / 体格 / 闪避基础值都要跟着变。
  final adj = ageAdjust(attrs);
  final a = asMap(adj['eff']);
  final hp = ((jsNum(a['con']) + jsNum(a['siz'])) / 10).floor();
  final mp = (jsNum(a['pow']) / 5).floor();
  // 理智上限 = 意志（POW）。POW 若因释放法术等原因变化，上限跟着变。
  // 注意：当前理智可以暂时超过这个上限（界面不再把当前值夹到上限）。
  final san = jsNum(a['pow']);

  // 移动力: 基础 8，STR/DEX 均小于 SIZ → 7；均大于等于 → 9
  var mov = 8;
  final str = jsNum(a['str']);
  final dex = jsNum(a['dex']);
  final siz = jsNum(a['siz']);
  if (str < siz && dex < siz) {
    mov = 7;
  } else if (str > siz && dex > siz) {
    mov = 9;
  }
  // 年龄修正
  mov -= jsNum(adj['movLoss']);
  if (mov < 1) mov = 1;

  final dbb = dbBuild(str + siz);

  return <String, Object?>{
    'hp': hp,
    'maxHP': hp,
    'mp': mp,
    'maxMP': mp,
    'san': san,
    'maxSAN': san,
    'mov': mov,
    'build': dbb['build'],
    'db': dbb['db'],
    // 闪避初始值 = DEX / 2（同样取调整后的 DEX）
    'dodgeBase': (dex / 2).floor(),
    // 年龄调整摘要，供界面与角色卡展示
    'ageLoss': adj['loss'],
    'ageLossTotal': adj['totalLoss'],
  };
}

/// 理智上限 = 99 - 克苏鲁神话成功率
int maxSan(Object? cthulhuSkill) {
  final v = jsNum(cthulhuSkill);
  return 99 - (v != 0 ? v : 0);
}

/* ---------- 车卡期不允许加点的技能 ----------
 * 克苏鲁神话：规则书明确「车卡时不可加点」，只能靠实际遭遇神话事件获得，
 * 因此职业点与兴趣点都不该能加到它身上（成长可以）。
 *
 * 信用评级：同样按「车卡时不可加点」处理。
 * 它不是一根普通技能 —— 规则书里它是**用职业点买来的资产**，
 * 数值由职业决定的区间（creditMin-creditMax）约束，
 * 所以在「技能分配」那一步不给它加点的入口：
 * 要改请去「资产与信用评级」步骤（那里的区间校验更严格）。
 * 放在这里标成「仅成长」是为了跟克苏鲁神话一致 ——
 * 车卡时不能靠技能点 / 兴趣点堆它。
 */
const Map<String, bool> growthOnly = <String, bool>{
  'cthulhu': true,
  'credit': true,
};

bool isGrowthOnly(Object? skillId) => growthOnly[jsStr(skillId)] ?? false;

/* ---------- 技能最终值上限（两类） ----------
 * 本职技能 → 本职技能上限；非本职技能 → 兴趣技能上限。
 * 兼容早期只有一个 skillCap 的数据：没有分项值时回落到它。
 *
 * 两个例外 —— 它们由规则决定，不受用户设定的上限约束：
 *   1) 母语：基础值就等于「教育 EDU」，天生可能高于自定义上限
 *      （EDU 80 而上限被设成 60）。规则书只给了 99% 的硬顶，
 *      所以母语一律按 99 计，加点也最多加到 99。
 *   2) 其余技能：上限同样不会低于该技能自身的「基础值」。
 *      基础值不是用点数买来的，把它算成「超过上限」属于误报
 *      （例如闪避基础 = 敏捷÷2 = 45，而兴趣上限被设成 40）。
 */
const int defaultSkillCap = 99;
const int defaultOccSkillCap = 99;
const int defaultInterestSkillCap = 99;

int skillCapOf(
  Character? character,
  Map<String, Object?>? skill,
  Map<String, bool>? occSet,
) {
  final c = character?.raw ?? <String, Object?>{};
  /* 母语与信用评级：规则决定的上限，只受 99 硬顶 */
  if (skill != null &&
      (jsStr(skill['id']) == 'language_own' ||
          jsStr(skill['id']) == 'credit')) {
    return 99;
  }
  final shared = jsNum(c['skillCap']);
  var isOcc = false;
  if (occSet != null && skill != null) {
    isOcc =
        (occSet[jsStr(skill['key'])] ?? false) ||
        (occSet[jsStr(skill['id'])] ?? false);
  }
  final capOcc = jsNum(c['skillCapOcc']);
  final capInt = jsNum(c['skillCapInterest']);
  var cap = isOcc
      ? (capOcc != 0 ? capOcc : (shared != 0 ? shared : defaultOccSkillCap))
      : (capInt != 0
            ? capInt
            : (shared != 0 ? shared : defaultInterestSkillCap));
  final base = jsNum(skill?['base']);
  if (base > cap) cap = jsMin(<int>[base, 99]);
  return cap;
}

/// 该技能的上限是否被规则豁免（不受「上限设置」约束，只受 99 硬顶）
bool capExempt(Object? skillId) {
  final id = jsStr(skillId);
  /* 信用评级与母语一样：数值由规则（职业区间 / 教育值）决定，
     不该被用户设的「技能上限」压住 ——
     否则上限一改，规则书允许的信用评级就变成「超上限」的非法值。 */
  return id == 'language_own' || id == 'credit';
}

/* ============================================================
 * 属性生成器
 * ============================================================ */

/// 模式一: 随机生成
Map<String, int> genRandom([JsRng? rng]) {
  final out = <String, int>{};
  genRandomDice.forEach((k, r) {
    out[k] = (roll(r[0], r[1], rng) + r[2]) * 5;
  });
  return out;
}

/// 单属性随机 (用于幸运栏等)
int genRandomOne(String key, [JsRng? rng]) {
  final r = genRandomDice[key] ?? <int>[3, 6, 0];
  return (roll(r[0], r[1], rng) + r[2]) * 5;
}

/// 模式二: 购点 — 校验
///
/// `includeLuck == false` 时，「属性总和」只累加 8 项
/// （幸运不参与购点，也就不该计入）。
Map<String, Object?> validatePointBuy(
  Map<String, Object?> attrs,
  Object? totalCap,
  bool includeLuck,
) {
  final errors = <Object?>[];
  var sum = 0;
  final cap = jsNum(totalCap);
  final keys = includeLuck
      ? attributes.map((a) => jsStr(a['key'])).toList()
      : attributes
            .where((a) => !jsTruthy(a['optional']))
            .map((a) => jsStr(a['key']))
            .toList();
  for (final k in keys) {
    final v = attrs[k];
    if (v == null || v == '') continue;
    final n = jsNum(v);
    if (n < genMin || n > genMax) {
      errors.add(<String, Object?>{
        'text': '${attrMap[k]!['name']} 必须在 $genMin-$genMax 之间',
      });
    }
    if (n % genStep != 0) {
      errors.add(<String, Object?>{'text': '${attrMap[k]!['name']} 必须是 5 的倍数'});
    }
    sum += n;
  }
  // cap 为 0 表示还没设定，此时只做数值合法性检查，避免提示「超出上限 0」
  final over = cap > 0 && sum > cap;
  if (over) {
    errors.add(<String, Object?>{
      'text': '属性总和 $sum 超出上限 $cap，请减少 ${sum - cap} 点',
    });
  }
  return <String, Object?>{
    'ok': errors.isEmpty,
    'errors': errors,
    'sum': sum,
    'cap': cap,
    'remain': cap - sum,
    'counted': keys.length, // 本次计入的属性项数（8 或 9）
    'over': over,
    'overBy': over ? sum - cap : 0,
  };
}

/// 模式三: 预设方案 (预留)
const Map<String, Map<String, int>> genArrays = <String, Map<String, int>>{
  'A': <String, int>{
    'str': 80,
    'con': 70,
    'siz': 60,
    'dex': 60,
    'app': 50,
    'int': 70,
    'pow': 60,
    'edu': 70,
    'luck': 50,
  },
  'B': <String, int>{
    'str': 60,
    'con': 60,
    'siz': 60,
    'dex': 70,
    'app': 60,
    'int': 80,
    'pow': 70,
    'edu': 60,
    'luck': 50,
  },
  'C': <String, int>{
    'str': 50,
    'con': 70,
    'siz': 70,
    'dex': 60,
    'app': 70,
    'int': 60,
    'pow': 80,
    'edu': 60,
    'luck': 50,
  },
};

/* ============================================================
 * 校验器 (供"完成角色卡"时统一调用)
 *
 * 除 4 个需要职业层的（见文件头的结构差异说明）外，全部在此。
 * 每条错误的形状：`{step, target, text}`。
 * ============================================================ */
List<Map<String, Object?>> validateAttributes(Character c) {
  final errs = <Map<String, Object?>>[];
  for (final a in attributes) {
    final key = jsStr(a['key']);
    final v = jsNum(c.attributes[key]);
    final raw = c.attributes[key];
    if (!jsTruthy(raw) && raw != 0) {
      errs.add(<String, Object?>{
        'step': 1,
        'target': 'attr_$key',
        'text': '${a['name']} 未填写',
      });
    } else if (v < 1 || v > 999) {
      errs.add(<String, Object?>{
        'step': 1,
        'target': 'attr_$key',
        'text': '${a['name']} 数值不合法',
      });
    }
  }
  return errs;
}

/// 基本信息
List<Map<String, Object?>> validateBasicInfo(Character c) {
  final errs = <Map<String, Object?>>[];
  if (c.raw['characterName'] == null || c.characterName.trim().isEmpty) {
    errs.add(<String, Object?>{
      'step': 0,
      'target': 'characterName',
      'text': '角色姓名未填写',
    });
  }
  if (c.raw['playerName'] == null || c.playerName.trim().isEmpty) {
    errs.add(<String, Object?>{
      'step': 0,
      'target': 'playerName',
      'text': '玩家名称未填写',
    });
  }
  final age = jsNum(c.raw['age']);
  if (age == 0 || age < 1 || age > 200) {
    errs.add(<String, Object?>{
      'step': 0,
      'target': 'age',
      'text': '年龄必须填写为 1-200 的整数',
    });
  }
  return errs;
}

List<Map<String, Object?>> validateOccupationSelected(Character c) {
  if (c.occupationId.isEmpty) {
    return <Map<String, Object?>>[
      <String, Object?>{
        'step': 2,
        'target': 'occupationPicker',
        'text': '尚未选择职业',
      },
    ];
  }
  return <Map<String, Object?>>[];
}

/* ============================================================
 * 身体/精神状态枚举
 *
 * ⚠️ v2.10.0 起 **body 状态模型已换代**，下面的 [bodyStatus] 只是
 *    **历史六态快照**，勿被它的形状误导：
 *      · 旧模型（v2.10.0 前）：body 单选六态 —— 正常/轻伤/重伤/濒死/昏迷/死亡；
 *      · 新模型（v2.10.0）：sheet.status.body ∈ {正常, 轻伤, 重伤, 死亡} 四态单选；
 *        「濒死」「昏迷」升级为独立布尔标记 sheet.status.dying /
 *        sheet.status.unconscious，可与 body **叠加**
 *        （如 {body:'重伤', dying:true, unconscious:true} 合法）；
 *        显示 / 判定一律读视图合成 bodyView（死亡 > dying > unconscious > body）。
 *
 *    [bodyStatus] 保留仅为**旧存档 / 历史数据兼容**（老卡的 '濒死'/'昏迷'
 *    字符串会先经 normalize 迁移），**勿在新代码引用**；
 *    新代码一律走「body 四态 + dying/unconscious 标记」。
 *    ⚠️ 绝对不要改它的值（既有断言依赖）。
 *
 * mental **多选**（规则允许同时存在：背景自带永久疯狂，
 *          游戏里又叠加临时疯狂 / 不定疯狂）—— 这个没变，别一起改。
 * 「正常」在多选里表示「没有任何异常」——不能和别的项同时存在，
 * 这个互斥由 UI 处理（选「正常」时清空其余，选其余时摘掉「正常」）。
 * ============================================================ */
const List<String> bodyStatus = <String>['正常', '轻伤', '重伤', '濒死', '昏迷', '死亡'];

/* v2.1.5（用户第 1/4 项）：精神状态增加「疯狂症状」—— 表示角色**持有具体症状**
   （恐惧症 / 狂躁症）。它是多选里的一项，与「临时/不定/永久疯狂」并列：
   「疯狂症状」回答的是「有没有具体症状」，「临时/不定/永久」回答的是「多严重、会不会好」。
   「永久疯狂」改为**互斥项**（类似「正常」）：选了它就不能同时是别的精神状态。

   P8（用户第 6/7 项）：
     · **删掉「昏迷」** —— 昏迷是身体状态（status.dying / unconscious），
       从来不是精神状态；
     · 新增「潜在疯狂」—— 不定疯狂的症状随轮次消失后转入该状态，
       此后再掉 1 点 SAN 立刻复发为不定疯狂并新生成一条症状；
     · 「疯狂症状」只作为**背景疯狂表**的永久标记，不与跑团游戏联动。
   互斥 / 迁移规则统一在 `madness_state.dart`，本表只保留选项顺序。 */
const List<String> mentalStatus = ms.kMentalChoices;
const String mentalNormal = kMentalNormal;
const String mentalTemporary = ms.kMentalTemporary;
const String mentalIndefinite = ms.kMentalIndefinite;
const String mentalPotential = ms.kMentalPotential;
const String mentalSymptom = ms.kMentalSymptom;
const String mentalPermanent = ms.kMentalPermanent;

/* ============================================================
 * 技能分类 → 雷达图维度
 * ============================================================ */
const List<Map<String, Object?>> radarDims = <Map<String, Object?>>[
  <String, Object?>{'key': '战斗', 'label': '战斗能力', 'color': '#e05a4f'},
  <String, Object?>{'key': '探索', 'label': '探索能力', 'color': '#4f8fe0'},
  <String, Object?>{'key': '知识', 'label': '知识能力', 'color': '#8a6fd8'},
  <String, Object?>{'key': '交流', 'label': '交流能力', 'color': '#e0a24f'},
  <String, Object?>{'key': '生存', 'label': '生存能力', 'color': '#4fb98a'},
];

/// 计算雷达图各维度得分。
///   · value —— 原语义：该分类下技能最终值的**平均值**（保留，不改）。
///   · v2.2.0 新增：
///       sum  = 该类下技能最终值之**和**（类别得分）；
///       pct  = 该类得分 / 五类得分之和 × 100（占比 %）；
///       norm = pct / 五类中最大 pct × 100（归一化 0–100，最大占比 = 100）。
///     界面已改用占比口径绘制（radarChart 优先读 norm）。
List<Map<String, Object?>> radar(
  List<Object?>? skills,
  List<Map<String, Object?>> skillDefs,
) {
  final catMap = <String, Object?>{};
  for (final d in skillDefs) {
    catMap[jsStr(d['id'])] = d['category'];
  }
  final sums = <String, int>{for (final d in radarDims) jsStr(d['key']): 0};
  final counts = <String, int>{for (final d in radarDims) jsStr(d['key']): 0};
  for (final sRaw in skills ?? <Object?>[]) {
    final s = asMap(sRaw);
    final cat = jsStr(catMap[jsStr(s['id'])]);
    if (!catMap.containsKey(jsStr(s['id'])) || !sums.containsKey(cat)) continue;
    var v = jsNum(s['total']);
    if (s.containsKey('base') && v < jsNum(s['base'])) v = jsNum(s['base']);
    sums[cat] = sums[cat]! + jsMin(<int>[v, 100]);
    counts[cat] = counts[cat]! + 1;
  }
  /* 五类得分之和与最大类得分 —— 供 pct / norm 用。 */
  var totalSum = 0;
  var maxSum = 0;
  for (final d in radarDims) {
    final k = jsStr(d['key']);
    totalSum += sums[k]!;
    if (sums[k]! > maxSum) maxSum = sums[k]!;
  }
  return radarDims.map((d) {
    final k = jsStr(d['key']);
    final c = counts[k]! == 0 ? 1 : counts[k]!;
    final sum = sums[k]!;
    final pct = totalSum > 0 ? (sum / totalSum * 100) : 0.0;
    final norm = maxSum > 0 ? (sum / maxSum * 100) : 0.0;
    return <String, Object?>{
      'key': k,
      'label': d['label'],
      'color': d['color'],
      'value': jsRound(sum / c), // 原语义：类别平均（保留）
      'sum': sum, // 新增：类别技能值之和
      'pct': jsRound(pct * 10) / 10, // 新增：占比（%，一位小数）
      'norm': jsRound(norm * 10) / 10, // 新增：归一化 0–100（最大占比 = 100）
    };
  }).toList();
}

int ageProgressChecks(Object? age) => jsNum(ageRule(age)['eduChecks']);

String? attrByName(Object? name) => cn2key[jsStr(name).trim()];

/* ============================================================
 * 规则系统元信息（`COC7` 上的常量字段）
 * ============================================================ */
class Coc7 {
  static const String id = 'coc7';
  static const String name = '克苏鲁的呼唤 第七版';
  static const String shortName = 'COC 7th';
  static const bool available = true;
  static const String description = '调查员在诡秘的克苏鲁神话世界中探索真相，理智与生命随时可能被吞噬。';
  static const String version = '7th';
  static const String rulebook = '克苏鲁的呼唤 第七版规则书';

  /// 购点模式的标准属性点上限（不含幸运 / 含幸运 / 兜底）
  static const Map<String, int> pointBuyCap = <String, int>{
    'noLuck': 460,
    'withLuck': 540,
    'fallback': 480,
  };

  /// 兴趣技能点公式：INT × 2
  static const Map<String, Object?> defaultInterestFormula = <String, Object?>{
    'type': 'int',
    'mult': 2,
  };

  static const List<String> skillCategories = <String>[
    '战斗',
    '探索',
    '交流',
    '知识',
    '生存',
    '其他',
    '自定义',
  ];
}
