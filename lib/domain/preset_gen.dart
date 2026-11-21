// ============================================================
// preset_gen.dart — 随机预设角色卡生成器（规则引擎随机出整张合法卡）
// 逐行对应 `core/preset.js`（1386 行，`PresetGen`）
//
// 用途：
//   · 向导第 0 步「快速开始」一次生成若干张**完整可用**的角色卡，
//     玩家挑一张就能直接开团；
//   · 被 AI 车卡复用：AI 只给创意字段（是谁 / 想做什么 / 长什么样 /
//     有什么故事），数值落地全靠这里 —— 出来的卡必须过 Engine.validate
//     与 checkList，这是「AI 车卡出来的卡一定能用」的地基。
//
// 「完整」的定义（与旧版一致，不自作主张改动）：
//   属性 9 项齐备（含幸运）、年龄调整与教育进步检定已掷、
//   职业 + 本职技能选择已完成、职业点 / 兴趣点已分配完毕、
//   信用评级在职业允许范围内且占用职业点、装备与背景全部填好。
//   生成后用 `checkList` 自检，有问题就重来（最多 8 次）。
//
// ⚠️ 三条硬约束（动了就立刻和 oracle 不等）：
//   1. **随机调用顺序**逐字保留。取谁、取几次、哪个分支才消耗随机数，
//      全部与原码一致；测试会断言 `randUsed`。
//   2. 卡片形状完全沿用 `newCharacter()`，键名一个不改（数据契约）。
//   3. 不"顺手优化"（比如把 `pick([5,5,5,10])` 去重成 3 个元素）——
//      那会改变随机序列。
// ============================================================

import 'dart:math' as math;

import 'ai_caps.dart';
import 'avatar.dart' as avatar;
import 'character.dart';
import 'combat_skill_map.dart';
import 'data/armors.dart';
import 'data/assets.dart';
import 'data/weapons.dart';
import 'easter_egg.dart' as egg;
import 'engine.dart' as engine;
import 'js_compat.dart';
import 'madness.dart' as madness;
import 'occupation.dart' as occ;
import 'personas.dart' as per;
import 'personas.dart' show PickCtx;
import 'rule_registry.dart' show RuleRegistry;
import 'rules_coc7.dart' as rules;
import 'skillmodel.dart' as sm;

/* ---------- 背景心理症状的出现概率 ----------
   v2.11.4：随机角色卡**不再人手一条**疯狂症状。
     · 普通随机角色 + 名人彩蛋卡 → 约 1/5 带一条；
     · 跑团成员彩蛋卡 → **一律不带**（用户明确要求）。
   ⚠️ 只改**出现概率**，不动疯狂表内部逻辑（8/10 总结症状 + 各 1/10 恐惧/狂躁
      是规则书口径，rules 层有真值表钉住）。 */
const double bgMadnessRate = 0.2;

/* 「支援层」的目标值基准：拔尖项之外的技能给一个中等目标。
   故意压在 50 上下而不是齐刷刷 50 —— 玩家要的是「几项拔尖 + 其余够用」。 */
const int occMidTarget = 50;

/* 拔尖项的软上限。默认上限是 99（等于「不限」），真把某项堆到 96
   反而像假数据；所以顶项按 90 封顶，上限本身更低（如 80）时软上限就等于上限。 */
const int occSoftTop = 90;

/* ============================================================
 * 房规数值上限的取数口径
 * ============================================================ */

/// 当前生效的房规设置（由 `settings_repo` 在启动 / 保存后写入）。
///
/// ⚠️ 必须是**变量**、每次生成现读 —— 玩家改完设置再点「换一批」就该按
/// 新上限来。写成启动时读一次的常量，改完设置要重开应用才生效。
Map<String, Object?> presetSettings = defaultSettings();

/// 生成选项（对应 JS 里那个 `opts` 字面量）
class PresetOptions {
  PresetOptions({
    this.setting,
    this.ctx,
    this.caps,
    this.ptsCap,
    this.profile,
    this.ruleSystemId,
  });

  /// 指定世界设定（不传则按权重随机）
  Map<String, Object?>? setting;

  /// 同批去重游标（`generate()` 内部会建一个并复用给整批）
  PickCtx? ctx;

  /// 房规数值上限（不传则读 [presetSettings]）
  AiCaps? caps;

  /// 兼容旧的 ptsCap 写法（只给技能上限、不给属性上限）
  Map<String, Object?>? ptsCap;

  /// 外部注入的创意字段（AI 车卡 / 彩蛋卡）
  Map<String, Object?>? profile;

  /// 本次生成所选的规则系统 id（不传则取 [RuleRegistry.defaultRule]）。
  /// 生成路径一律写进卡上的 `ruleSystemId`，不硬编码 'coc7' 字面量。
  String? ruleSystemId;
}

/// 本次生成实际采用的规则 id。
///
/// 统一走注册表：未开放 / 认不出的 id 一律回退默认规则，
/// 保证 [Character.ruleSystemId] 永远是一个已注册、可查找的规则。
String ruleSystemIdOf([PresetOptions? opts]) =>
    RuleRegistry.effectiveId(opts?.ruleSystemId);

/// 读一次当前生效的房规数值上限（`activeCaps`，与 [build] 同源）
AiCaps activeCaps([PresetOptions? opts]) {
  if (opts != null) {
    if (opts.caps != null) return opts.caps!;
    if (opts.ptsCap != null) {
      return AiCaps(
        attrCap: 0,
        withLuck: true,
        occCap: jsNum(opts.ptsCap!['occ']),
        intCap: jsNum(opts.ptsCap!['int']),
      );
    }
  }
  return capsFromSettings(presetSettings);
}

/// 把「属性总和上限」压到角色上（复用 [applyAttrCap]，随机卡与 AI 卡同源）
bool _applyAttrCapToCard(Character c, AiCaps caps) {
  if (caps.attrCap == 0) return false;
  final holder = <String, Object?>{'attributes': c.attributes};
  final moved = applyAttrCap(holder, caps);
  if (moved) c.raw['attributes'] = holder['attributes'];
  return moved;
}

/* ---------- 小工具 ---------- */

/// `Math.max(lo, Math.min(hi, v))`
int _clamp(int v, int lo, int hi) => math.max(lo, math.min(hi, v));

/// `Math.round(v / 5) * 5` —— 技能值习惯上是 5 的倍数
int _snap5(num v) => jsRound(v / 5) * 5;

/// 稳定排序（V8 的 `Array#sort` 自 ES2019 起保证稳定；
/// Dart 的 `List.sort` **不**稳定，必须显式带下标做次级比较）
void _stableSort<T>(List<T> list, int Function(T a, T b) cmp) {
  final idx = List<int>.generate(list.length, (i) => i);
  idx.sort((a, b) {
    final c = cmp(list[a], list[b]);
    return c != 0 ? c : a - b;
  });
  final sorted = idx.map((i) => list[i]).toList();
  for (var i = 0; i < list.length; i++) {
    list[i] = sorted[i];
  }
}

/// 取角色身上的技能实例 Map 列表（直接是卡里那些 Map，不是副本）
List<Map<String, Object?>> _skills(Character c) => c.skills.map(asMap).toList();

/// 按 key 找技能实例
Map<String, Object?>? _byKey(Character c, String key) {
  for (final sRaw in c.skills) {
    final s = asMap(sRaw);
    if (jsStr(s['key']) == key) return s;
  }
  return null;
}

/// JS 里到处是 `p.sub || ''` —— 缺失 / null / 空串统一成空串。
/// 不能直接 `jsStr(v)`：那会得到字符串 'null'，去重键与「组技能落专攻」
/// 的判定都会跟着走偏。
String _subOf(Object? v) => jsTruthy(v) ? jsStr(v) : '';

/* ---------- 属性 ---------- */

/// 掷一组属性（`R.generators.random()`）
Map<String, Object?> _rollAttributes() => <String, Object?>{
  ...rules.genRandom(),
};

/// 属性是否「能用」：不太极端，总和不至于算不出职业点
bool attrsUsable(Map? a) {
  const keys = <String>['str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu'];
  var sum = 0;
  for (final k in keys) {
    final v = jsNum(a?[k]);
    if (v < 25 || v > 90) return false;
    sum += v;
  }
  if (sum < 380 || sum > 640) return false;
  return true;
}

/// AI / 外部给定的属性：只要每项在规则区间、是 5 的倍数、合计不离谱就收下
/// （配合属性上限设置 —— 压完之后八项合计可能低于随机卡要求的 380）。
///
/// ★ P7 真机反馈修复：新增「5 的倍数」闸门。
///   取舍说明：选**拒收走重掷**，不做就地规整。理由有三：
///     ① 这是外部输入闸门，拒收最保守 —— 规则层随后用 `genRandom()`
///        （3D6×5 / (2D6+6)×5）重掷，一定是 5 倍数且落在规则区间；
///     ② 就地规整会篡改 AI 配好的人物性格，且与 `applyAttrCap` 的
///        5 倍数网格形成「第二套规整实现」，违反单一真源；
///     ③ 压缩路径（`applyAttrCap`）已经负责把超限值规整成 5 倍数，
///        两者合起来覆盖「超限 / 未超限」两种情况，绝不让非法值进卡。
bool attrsFromAi(Map? a) {
  if (a == null) return false;
  const keys = <String>['str', 'con', 'siz', 'dex', 'app', 'int', 'pow', 'edu'];
  var sum = 0;
  for (final k in keys) {
    final v = jsNum(a[k]);
    if (v < rules.genMin || v > rules.genMax) return false;
    if (v % rules.genStep != 0) return false;
    sum += v;
  }
  final lk = jsParseInt(a['luck']);
  if (lk == null) return false;
  // 幸运的规则上限是 99（rules_coc7.dart 的属性表），但同样必须是 5 的倍数。
  if (lk < rules.genMin || lk > 99 || lk % rules.genStep != 0) return false;
  return sum >= 200 && sum <= 720;
}

/* ---------- 年龄 / 教育进步检定 ---------- */

int _randomAge() {
  final r = nowRng();
  if (r < 0.42) return 21 + per.rnd(9); // 21-29
  if (r < 0.72) return 30 + per.rnd(10); // 30-39
  if (r < 0.92) return 40 + per.rnd(10); // 40-49
  return 50 + per.rnd(11); // 50-60
}

/// 教育进步检定：年龄带来的 EDU 增益不是白送的 ——
/// 每次掷 1D100，结果大于当前 EDU 才 +1D10。
void _runEduChecks(Character c) {
  final need = rules.ageProgressChecks(jsParseInt(c.basicInfo['age']));
  c.raw['eduProgress'] = <String, Object?>{
    'base': null,
    'done': 0,
    'log': <Object?>[],
    'bonus': 0,
  };
  final p = asMap(c.raw['eduProgress']);
  final log = asList(p['log']);
  for (var i = 0; i < need; i++) {
    engine.recalc(c);
    final before = jsNum(engine.effAttrs(c)['edu']);
    final r = rules.eduImproveCheck(before);
    log.add(<String, Object?>{
      'n': i + 1,
      'roll': r['roll'],
      'before': before,
      'gain': r['gain'],
      'after': math.min(99, before + jsNum(r['gain'])),
    });
  }
  var bonus = 0;
  for (final x in log) {
    bonus += jsNum(asMap(x)['gain']);
  }
  p['bonus'] = bonus;
  p['done'] = log.length;
  engine.recalc(c);
}

/* ============================================================
 * 职业：按世界设定做加权抽样
 *   命中 occPrefer 关键词 → 权重 ×4
 *   命中 occAvoid  关键词 → 权重 ×0.03（几乎不会出现，但不至于抽空池子）
 *   不是硬性黑白名单，避免设定过窄时一个职业都挑不出来。
 * ============================================================ */

List<Map<String, Object?>> _candidateOccupations() {
  return occ.listOccupations().where((o) {
    if (jsStr(o['id']) == 'occ1') return false; // 排除「自定义职业」
    if (o['creditMin'] == null) return false;
    if (!jsTruthy(o['attrFormula'])) return false;
    return true;
  }).toList();
}

double _occWeight(Map<String, Object?> o, Map<String, Object?>? setting) {
  final n = jsStr(o['name']);
  var w = 1.0;
  final prefer = asList(setting?['occPrefer']);
  for (final kw in prefer) {
    if (n.contains(jsStr(kw))) {
      w *= 4;
      break;
    }
  }
  final avoid = asList(setting?['occAvoid']);
  for (final kw in avoid) {
    if (n.contains(jsStr(kw))) {
      w *= 0.03;
      break;
    }
  }
  return w;
}

final RegExp _nameParenRe = RegExp(r'[（(]([^）)]*)[）)]');
final RegExp _reqRe = RegExp(
  r'([A-Za-z\u4e00-\u9fa5]{2,5})\s*([<>]=?)\s*(\d+)',
);

/// 个别职业把属性门槛写在名字里（「相扑力士(SIZ>80,STR>70)」）
List<Map<String, Object?>>? _nameAttrRequirements(Map<String, Object?> o) {
  final m = _nameParenRe.firstMatch(jsStr(o['name']));
  if (m == null) return null;
  final out = <Map<String, Object?>>[];
  for (final part in m.group(1)!.split(RegExp(r'[,，、]'))) {
    final t = _reqRe.firstMatch(part);
    if (t == null) continue;
    final key = rules.attrByName(t.group(1));
    if (key == null) continue;
    out.add(<String, Object?>{
      'key': key,
      'op': t.group(2),
      'val': jsParseInt(t.group(3)),
    });
  }
  return out.isEmpty ? null : out;
}

bool _meetsNameReqs(Map<String, Object?> o, Map<String, Object?> attrs) {
  final reqs = _nameAttrRequirements(o);
  if (reqs == null) return true;
  for (final r in reqs) {
    final v = jsNum(attrs[jsStr(r['key'])]);
    final val = jsNum(r['val']);
    switch (jsStr(r['op'])) {
      case '>':
        if (!(v > val)) return false;
        break;
      case '>=':
        if (!(v >= val)) return false;
        break;
      case '<':
        if (!(v < val)) return false;
        break;
      default:
        if (!(v <= val)) return false;
    }
  }
  return true;
}

class _WeightedOcc {
  _WeightedOcc(this.o, this.w);
  final Map<String, Object?> o;
  final double w;
}

/// 按设定口味挑一个职业。
///
/// 要求：满足职业名自带的属性门槛；属性算出来的职业点在 `minPts`-400 之间
/// （下限太低说明属性正好压在公式短板上；默认 120）。
///
/// [minPts] 房规把属性总和压到上限时，职业点公式算出来的池子会同步变小，
/// 沿用 120 会把职业全筛掉 —— 调用方按压缩幅度放宽这个下限传进来。
Map<String, Object?>? pickOccupation(
  Character c,
  Map<String, Object?>? setting,
  Object? forceId,
  Object? minPts,
) {
  final parsed = jsParseInt(minPts);
  final floor = (parsed != null && parsed > 0) ? parsed : 120;
  final eff = engine.effAttrs(c);
  final available = _candidateOccupations()
      .where((o) => _meetsNameReqs(o, eff))
      .toList();

  if (jsTruthy(forceId)) {
    final fid = jsStr(forceId);
    for (final o in available) {
      if (jsStr(o['id']) == fid) return o;
    }
    // 名字对得上也算（AI 更可能给名字）
    for (final o in available) {
      if (jsStr(o['name']) == fid) return o;
    }
  }

  final weighted = available
      .map((o) => _WeightedOcc(o, _occWeight(o, setting)))
      .toList();
  for (var attempt = 0; attempt < 40; attempt++) {
    var total = 0.0;
    for (final x in weighted) {
      total += x.w;
    }
    if (total <= 0) break;
    var r = nowRng() * total;
    var hit = weighted.last.o;
    for (final x in weighted) {
      r -= x.w;
      if (r <= 0) {
        hit = x.o;
        break;
      }
    }
    final pts = occ.evalFormula(hit['attrFormula'], eff);
    if (pts >= floor && pts <= 400) return hit;
  }
  // 兜底：洗一遍，取一个能满足点数条件的
  final sorted = per.shuffle(available);
  for (final o in sorted) {
    final p = occ.evalFormula(asMap(o)['attrFormula'], eff);
    if (p >= floor && p <= 400) return asMap(o);
  }
  return available.isEmpty ? null : available.first;
}

/// 按名字找职业（AI 返回职业名时用）
Map<String, Object?>? occupationByName(Object? name) {
  if (!jsTruthy(name)) return null;
  final target = jsStr(name).trim();
  final all = occ.listOccupations();
  for (final o in all) {
    if (jsStr(o['name']) == target) return o;
  }
  for (final o in all) {
    if (jsStr(o['name']).contains(target)) return o;
  }
  for (final o in all) {
    if (target.contains(jsStr(o['name'])) && jsStr(o['id']) != 'occ1') return o;
  }
  return null;
}

/* ---------- 本职技能选择（自动替玩家选完） ---------- */

/// 自由项（「任选 N 项」）的候选池
const List<String> freePool = <String>[
  '侦查',
  '聆听',
  '图书馆使用',
  '心理学',
  '说服',
  '话术',
  '恐吓',
  '取悦',
  '乔装',
  '潜行',
  '闪避',
  '攀爬',
  '跳跃',
  '游泳',
  '汽车驾驶',
  '急救',
  '医学',
  '法律',
  '历史',
  '神秘学',
  '会计',
  '博物学',
  '领航',
  '追踪',
  '妙手',
  '锁匠',
  '机械维修',
  '电气维修',
  '计算机使用',
  '电子学',
  '摄影',
  '人类学',
  '考古学',
  '估价',
  '驯兽',
  '骑术',
  '读唇',
  '精神分析',
  '催眠',
  '潜水',
  '投掷',
];

String _skillLabel(Object? skillId, String? sub) {
  final d = occ.skillById(skillId);
  final nm = d != null ? jsStr(d['name']) : jsStr(skillId);
  return jsTruthy(sub) ? '$nm（$sub）' : nm;
}

/// 组技能挑一个专攻。
///
/// 优先职业原文里点名的（「手艺（烹饪）」→ 烹饪），否则随机 ——
/// 与 `occupation.dart#groupSubFor` 保持同一套偏好，两边才不会选出不同的专攻。
String _pickGroupSub(Character c, Map<String, Object?>? def) {
  final subs = asList(def?['subskills']);
  if (subs.isEmpty) return '';
  final o = occ.getOccupationById(c.occupationId);
  final text = '${jsStr(o?['skillText'])}　${jsStr(o?['desc'])}';
  final hint = subs.where((s) {
    final n = jsStr(asMap(s)['name']);
    return n.isNotEmpty && text.contains(n);
  }).toList();
  final pool = hint.isNotEmpty ? hint : subs;
  return jsStr(asMap(pool[per.rnd(pool.length)])['name']);
}

/// 保证这个专攻在技能表里有一条实例（非 flat 组不会自动展开）
void _ensureSub(Character c, Object? skillId, String? sub) {
  if (!jsTruthy(skillId) || !jsTruthy(sub)) return;
  final key = '${jsStr(skillId)}::$sub';
  if (_byKey(c, key) != null) return;
  sm.addSubSkill(c, jsStr(skillId), sub!);
}

/// 把职业描述里的「任选 N 项」全部替玩家选好（choice / free 两类）
///
/// [customSkills] 是 AI 在自定义职业时给的技能名数组（最多 8 项），
/// 只作**建议**用 —— 名字解析不出来就退回随机池，宁可随机也不能选空。
void _fillOccupationPicks(
  Character c,
  PickCtx? ctx,
  Map<String, Object?>? opts,
) {
  final o = opts ?? <String, Object?>{};
  final reqs = occ.getRequirements(c);
  c.raw['occupationPicks'] = <String, Object?>{};
  final picks = asMap(c.raw['occupationPicks']);
  final used = <String, bool>{};

  for (final r in reqs) {
    final type = jsStr(r['type']);
    if (type == 'fixed') {
      /* 组技能但职业没点名专攻（「格斗」「技艺」「射击」）：替玩家落到
         **一个**专攻上，并保证技能表里有这条实例。不落下去的话，
         它既不出现在本职列表里、也吃不到职业点。 */
      final d0 = jsTruthy(r['skill']) ? occ.skillById(r['skill']) : null;
      if (d0 != null && jsTruthy(d0['special']) && !jsTruthy(r['sub'])) {
        final sub0 = _pickGroupSub(c, d0);
        _ensureSub(c, r['skill'], sub0);
        used['${jsStr(r['skill'])}::$sub0'] = true;
        picks[jsStr(r['id'])] = <Object?>[
          <String, Object?>{
            'skill': r['skill'],
            'sub': sub0,
            'name': '${jsStr(d0['name'])}（$sub0）',
          },
        ];
      }
    } else if (type == 'choice') {
      final pool = per
          .shuffle(asList(r['pool']))
          .map(asMap)
          .where(
            (p) =>
                !(used['${jsStr(p['skill'])}::${_subOf(p['sub'])}'] ?? false),
          )
          .toList();
      final rawCount = jsParseInt(r['count']);
      final take = rawCount == null
          ? double.nan
          : math.min(rawCount, pool.length).toDouble();
      final arr = <Object?>[];
      for (var i = 0; i < pool.length && i < take; i++) {
        final p = pool[i];
        var psub = _subOf(p['sub']);
        final pdef = occ.skillById(p['skill']);
        if (pdef != null && jsTruthy(pdef['special']) && psub.isEmpty) {
          psub = _pickGroupSub(c, pdef);
          _ensureSub(c, p['skill'], psub);
        }
        used['${jsStr(p['skill'])}::$psub'] = true;
        arr.add(<String, Object?>{
          'skill': p['skill'],
          'sub': psub,
          'name': jsTruthy(p['name'])
              ? p['name']
              : _skillLabel(p['skill'], psub),
        });
      }
      if (arr.isNotEmpty) picks[jsStr(r['id'])] = arr;
    } else if (type == 'free') {
      final rawCount = jsParseInt(r['count']);
      final want = rawCount == null
          ? double.nan
          : math.min(8, rawCount).toDouble();
      final arr2 = <Object?>[];

      // 先用 AI 指定的（自定义职业专用路径）
      for (final nm in asList(o['customSkills'])) {
        if (arr2.length >= want) break;
        final id = occ.resolveSkillId(nm);
        if (!jsTruthy(id)) continue;
        final def = occ.skillById(id);
        if (def == null) continue;
        var sub = '';
        if (jsTruthy(def['special'])) {
          // 组技能（如「射击」）必须落到某个专攻上
          if (asList(def['subskills']).isEmpty) continue;
          sub = _pickGroupSub(c, def);
        }
        if (used['$id::$sub'] ?? false) continue;
        used['$id::$sub'] = true;
        _ensureSub(c, id, sub);
        arr2.add(<String, Object?>{
          'skill': id,
          'sub': sub,
          'name': sub.isEmpty
              ? jsStr(def['name'])
              : '${jsStr(def['name'])}（$sub）',
        });
      }

      // 不够就用随机池补齐
      final names = per.shuffleStrings(freePool);
      for (var k = 0; k < names.length && arr2.length < want; k++) {
        final id2 = occ.resolveSkillId(names[k]);
        if (!jsTruthy(id2) || (used['$id2::'] ?? false)) continue;
        final def2 = occ.skillById(id2);
        if (def2 == null || jsTruthy(def2['special'])) continue;
        used['$id2::'] = true;
        arr2.add(<String, Object?>{
          'skill': id2,
          'sub': '',
          'name': def2['name'],
        });
      }
      if (arr2.isNotEmpty) picks[jsStr(r['id'])] = arr2;
    }
  }
  engine.recalc(c);
}

/* ---------- 信用评级 ---------- */

int pickCreditRating(Map<String, Object?>? o, int totalPoints) {
  /* 自定义职业没有信用评级区间（creditMin/Max 为 null）——
     规则书里这一项是玩家自己定的，这里就留 0 让玩家去填。 */
  if (o == null || o['creditMin'] == null) return 0;
  final lo = math.max(0, jsNum(o['creditMin']));
  final cm = o['creditMax'];
  final hi = math.min(cm == null ? lo : jsNum(cm), lo + 60);
  final mid = jsRound(((lo + hi) / 2) / 5) * 5;
  final jitter = jsNum(per.pickOne(<Object?>[-10, -5, 0, 5, 10]));
  var cr = _clamp(mid + jitter, lo, hi);
  /* 信用评级是从职业点里扣的：留至少 60 点给技能。
     ⚠️ 但这只是「尽量」—— 池子本来就小的时候要能让位给技能，
     否则评级一项就吃掉全部点数。规则书允许信用评级为 0（尚未分配），
     所以这里不会把池子扣成负数。 */
  if (cr > totalPoints - 60) cr = totalPoints - 60;
  cr = math.max(0, cr);
  if (cr < lo) cr = math.min(lo, totalPoints);
  cr = _clamp(cr, math.min(lo, totalPoints), hi);
  return cr;
}

/* ---------- 点数分配 ---------- */

/// 随机撒点（兴趣技能与本职的零散点数都用它）。
///
/// [avoid] 避免让某项的最终值**恰好落在**这个数上。本职分配传 50 ——
/// 玩家上一版最大的抱怨就是「一摞技能全卡在 50」，所以哪怕随机撒点，
/// 也别正好撒出一个 50 来（越过或退到 45 都行）。兴趣点不需要这个规避。
int _spendPoints(
  Character c,
  List<String> keys,
  int budget,
  String field,
  int Function(Map<String, Object?>) capFn,
  int? avoid,
) {
  final alive = List<String>.from(keys);
  var spent = 0;
  var guard = 0;
  while (spent < budget && alive.isNotEmpty && guard++ < 6000) {
    final k = alive[per.rnd(alive.length)];
    final s = _byKey(c, k);
    if (s == null) {
      alive.removeAt(alive.indexOf(k));
      continue;
    }
    final room = capFn(s) - jsNum(s['total']);
    if (room <= 0) {
      alive.removeAt(alive.indexOf(k));
      continue;
    }
    final left = budget - spent;
    var step = math.min(
      room,
      math.min(left, jsNum(per.pickOne(<Object?>[5, 5, 5, 10, 10, 15, 20]))),
    );
    /* 落点正好是 avoid（本职是 50）→ 往上越过去；越不过就退 5 点；
       连退都退不动（只剩 5 点）就照原样加，别为了规避而卡住预算。 */
    if (avoid != null && jsNum(s['total']) + step == avoid) {
      if (step + 5 <= math.min(room, left)) {
        step += 5;
      } else if (step > 5) {
        step -= 5;
      }
    }
    if (step <= 0) {
      alive.removeAt(alive.indexOf(k));
      continue;
    }
    s[field] = jsNum(s[field]) + step;
    sm.recompute(s);
    spent += step;
  }
  return spent;
}

class _PlanItem {
  _PlanItem(this.skill, this.need);
  final Map<String, Object?> skill;
  int need;
}

/// 本职技能分配：**拔尖优先**，把预算一分不剩地花完。
///
/// 三步（与旧版一致，别改）：
///   1) **选** 2-4 项拔尖技能（一半取基础值最高的，一半随机）；
///   2) **堆** 按阶梯给拔尖项定目标值，按「离目标还差多少」从小到大推；
///   3) **垫** 富余点数先给 2-3 项「支援技能」一个中等目标（≈50 上下），
///      还多就**随机撒**到其余技能上。
///
/// ⚠️ 两条不能省的约束：
///   · **必须花完**（终止条件只能是预算用完或所有技能都到上限）；
///   · **不能为了达标而摊平**（玩家明确允许「有不加点的职业技能」）。
int _spendOccFocused(
  Character c,
  List<String> keys,
  int budget,
  int Function(Map<String, Object?>) capFn,
) {
  if (keys.isEmpty || budget <= 0) return 0;

  /* 只看「还有空间」的技能实例 */
  final items = <Map<String, Object?>>[];
  for (final k in keys) {
    final s = _byKey(c, k);
    if (s == null) continue;
    if (capFn(s) - jsNum(s['total']) <= 0) continue;
    items.add(s);
  }
  if (items.isEmpty) return 0;

  var spent = 0;

  /* ---- 1) 选拔尖项 ---- */
  final byBase = List<Map<String, Object?>>.from(items);
  _stableSort(byBase, (a, b) => jsNum(b['base']) - jsNum(a['base']));
  final nPeak = math.min(items.length, 2 + per.rnd(3)); // 2 - 4 项
  final takeTop = math.max(1, (nPeak / 2).ceil()); // 一半取基础值最高的
  var peaks = byBase.sublist(0, takeTop);
  final restPool = per.shuffle(byBase.sublist(takeTop)).map(asMap).toList();
  for (var i = 0; peaks.length < nPeak && i < restPool.length; i++) {
    peaks.add(restPool[i]);
  }
  peaks = List<Map<String, Object?>>.from(peaks);
  _stableSort(peaks, (a, b) => jsNum(b['base']) - jsNum(a['base']));

  /* ---- 2) 阶梯目标（按预算决定拔尖几项、推到多高）----
   * ⚠️ 顺序很关键：预算不够时，**先减项数、再降高度**。
   */
  final softTop = math.min(capFn(peaks[0]), occSoftTop);
  final jitterTop = softTop >= 80
      ? softTop - jsNum(per.pickOne(<Object?>[0, 0, 5]))
      : softTop;
  final step = jsNum(per.pickOne(<Object?>[4, 5, 5, 6, 8]));
  final budgetForPeaks = (budget * 0.7).floor();

  /* 把前 k 项按阶梯（jitterTop, jitterTop-step, …）推高要花多少 */
  int costHigh(int k) {
    var total = 0;
    for (var j = 0; j < k && j < peaks.length; j++) {
      final tg = math.min(_snap5(jitterTop - j * step), capFn(peaks[j]));
      total += math.max(0, tg - jsNum(peaks[j]['total']));
    }
    return total;
  }

  /* 从多到少找「预算扛得住的最大项数」；至少要 2 项 */
  var useN = 0;
  for (var kk = peaks.length; kk >= 2; kk--) {
    if (costHigh(kk) <= budgetForPeaks) {
      useN = kk;
      break;
    }
  }

  final plan = <_PlanItem>[];
  final plentiful = useN >= 2;
  if (plentiful) {
    peaks = peaks.sublist(0, useN);
    for (var i = 0; i < peaks.length; i++) {
      var t0 = _snap5(jitterTop - i * step);
      final cap0 = capFn(peaks[i]);
      if (t0 > cap0) t0 = cap0;
      if (t0 < jsNum(peaks[i]['total'])) t0 = jsNum(peaks[i]['total']);
      plan.add(_PlanItem(peaks[i], math.max(0, t0 - jsNum(peaks[i]['total']))));
    }
    /* 便宜的项先到目标 —— 同样的预算能让更多拔尖项真的站上去。 */
    _stableSort(plan, (a, b) => a.need - b.need);
  } else {
    /* 预算紧 → 走**低位阶梯**，顺序是「先垫底、再拔尖」：
     *   ① 先把靠前的几项垫到 50 以上（55 / 50 这样的相邻两档）；
     *   ② 剩下的钱**全部**砸给第 1 项，能顶多高顶多高 —— 它是这张卡的门面。
     * ⚠️ 顺序不能反过来（先砸第 1 项会让「2-4 项 ≥50」直接落空）。
     */
    final fPool = items.where((x) => capFn(x) >= occMidTarget).toList();
    int needToMid(Map<String, Object?> x) =>
        math.max(0, occMidTarget - math.min(jsNum(x['total']), capFn(x)));
    _stableSort(fPool, (a, b) => needToMid(a) - needToMid(b));
    final fNeed = <int>[];
    for (final x in fPool) {
      fNeed.add(
        math.max(0, math.min(occMidTarget, capFn(x)) - jsNum(x['total'])),
      );
    }
    /* 垫底能垫几项：从多往少试，每多垫一项要多 5 点的「阶梯余量」 */
    var floorN = 0;
    var bump = 5;
    for (var kf = math.min(fPool.length, 4); kf >= 2; kf--) {
      var sumF = 0;
      for (var j2 = 0; j2 < kf; j2++) {
        sumF += fNeed[j2];
      }
      if (sumF + bump * (kf - 1) <= budget) {
        floorN = kf;
        break;
      }
    }
    if (floorN == 0 && fPool.length >= 2 && fNeed[0] + fNeed[1] <= budget) {
      floorN = 2;
      bump = 0; // 刚好够两项都站上 50
    }
    for (var j2 = 0; j2 < floorN; j2++) {
      final tgF = occMidTarget + bump * (floorN - 1 - j2);
      plan.add(
        _PlanItem(
          fPool[j2],
          math.max(
            0,
            math.min(tgF, capFn(fPool[j2])) - jsNum(fPool[j2]['total']),
          ),
        ),
      );
    }
    /* ② 余钱全给第 1 项（必须排在垫底项**之后**，先保底再拔尖） */
    final top0 = peaks[0];
    final tgt0 = math.min(capFn(top0), occSoftTop);
    var have0 = jsNum(top0['total']);
    for (final p in plan) {
      if (jsStr(p.skill['key']) == jsStr(top0['key'])) {
        have0 = math.min(capFn(top0), jsNum(top0['total']) + p.need);
      }
    }
    final extra0 = math.max(0, tgt0 - have0);
    if (extra0 > 0) plan.add(_PlanItem(top0, extra0));
  }

  for (var i = 0; i < plan.length && spent < budget; i++) {
    final put = math.min(
      plan[i].need,
      math.min(
        budget - spent,
        capFn(plan[i].skill) - jsNum(plan[i].skill['total']),
      ),
    );
    if (put <= 0) continue;
    plan[i].skill['occ'] = jsNum(plan[i].skill['occ']) + put;
    sm.recompute(plan[i].skill);
    spent += put;
  }

  /* ---- 3) 支援层：给一部分剩下技能一个中等目标 ----
   * 目标值**刻意避开 50**（取 35/40/45/55/60）：上一版所有技能齐刷刷停在 50，
   * 玩家明确说不要那样。支援层本来就该是「够用即可」的一档。 */
  final midPool = per
      .shuffle(
        items
            .where((x) => !peaks.any((p) => jsStr(p['key']) == jsStr(x['key'])))
            .toList(),
      )
      .map(asMap)
      .toList();
  final nMid = math.min(midPool.length, 2 + per.rnd(2)); // 2 - 3 项
  /* 支援层的档位：**故意避开 50**，而且每项取不同的档（打乱后按序取），
     保证同一张卡里的支援项不会撞到同一个整数上。 */
  final midOffsets = per
      .shuffle(<Object?>[-20, -15, -10, -5, 5, 10, 15])
      .map(jsNum)
      .toList();
  for (var i = 0; i < nMid && spent < budget; i++) {
    final m = midPool[i];
    final mCap = capFn(m);
    var mTarget = _snap5(occMidTarget + midOffsets[i % midOffsets.length]);
    if (mTarget > mCap) mTarget = mCap;
    if (mTarget < jsNum(m['total'])) mTarget = jsNum(m['total']);
    final need2 = math.min(mTarget - jsNum(m['total']), budget - spent);
    if (need2 <= 0) continue;
    m['occ'] = jsNum(m['occ']) + need2;
    sm.recompute(m);
    spent += need2;
  }

  /* ---- 4) 还有富余 ----
   * 4a. 撒到**拔尖项之外**的技能上，而且是**随机步长**（5/10/15/20）——
   *     这正是「不再出现一堵同值的墙」的关键。
   * 4b. 连软上限都铺满时才放开到真实上限（默认 99 时几乎走不到）。
   * 4c. 只有**所有技能都到顶**才会剩下点数 —— 那是规则使然。
   */
  if (spent < budget) {
    int softCap(Map<String, Object?> x) => math.min(capFn(x), occSoftTop);
    final restKeys = <String>[];
    for (final x in items) {
      // 拔尖项已经推到目标了
      if (peaks.any((p) => jsStr(p['key']) == jsStr(x['key']))) continue;
      restKeys.add(jsStr(x['key']));
    }
    spent += _spendPoints(
      c,
      restKeys,
      budget - spent,
      'occ',
      softCap,
      occMidTarget,
    );

    if (spent < budget) {
      final ranked = List<Map<String, Object?>>.from(items);
      _stableSort(ranked, (a, b) => jsNum(b['total']) - jsNum(a['total']));
      for (var i = 0; i < ranked.length && spent < budget; i++) {
        final room = capFn(ranked[i]) - jsNum(ranked[i]['total']);
        if (room <= 0) continue;
        final lump = math.min(room, budget - spent);
        ranked[i]['occ'] = jsNum(ranked[i]['occ']) + lump;
        sm.recompute(ranked[i]);
        spent += lump;
      }
    }
  }

  return spent;
}

/// 预言机开关：旧版 `preset.js#weaponCombatSet` 只按**原样字符串**匹配武器的
/// `skill` 字段，不做别名归一 —— `剑` 对不上技能表的 `刀剑`、`鞭子` 对不上
/// `鞭`、`投掷` 对不上 `throw`，于是带这些武器的卡会把战斗点扔回「斗殴」。
///
/// P9（需求 9）把这条错配修掉了：生产路径改走 [requiredCombatSkillKeys]，
/// 别名归一后再比对。但 `oracle_preset_test` 的职责是逐字证明
/// 「移植 == 旧版 JS」，所以按 `ai_caps.legacyAttrCapForOracle` 的同一套
/// 双路径办法留了这个开关：默认 `false`（生产走新映射），只有预言机测试打开。
bool legacyWeaponSkillMatchForOracle = false;

/// 旧口径的「武器 → 战斗技能」集合（**名字**，命中 `sub` 或 `id`）。
///
/// 仅在 [legacyWeaponSkillMatchForOracle] 为 true 时使用，逐字保留旧行为。
Set<String> _legacyWeaponCombatSet(Character c) {
  final want = <String>{};
  for (final wRaw in asList(c.raw['weapons'])) {
    final sk = jsStr(asMap(wRaw)['skill']).trim();
    if (sk.isEmpty) continue;
    want.add(sk);
    /* '步枪/霰弹枪' 这类合并名拆开逐段命中 —— 否则和角色卡里的
       「步枪」「霰弹枪」子技能对不上，枪卡的射击子技能既加不到点、又被误排。 */
    for (final part in sk.split('/')) {
      final p = part.trim();
      if (p.isNotEmpty) want.add(p);
    }
  }
  if (want.isEmpty) want.add('斗殴');
  return want;
}

/// 武器对应战斗技能的「预支」点数（需求 9）。
///
/// 随机生成的分点算法会挑「基础值高」的项拔尖，手枪（基础 20）、鞭（基础 5）
/// 这类武器技能常常一个点都分不到 —— 那就成了「带了手枪却没学射击（手枪）」，
/// 与「学了用不上的技能」是同一种浪费。所以先给它预支一档（5 的倍数，
/// 与支援层同档），余下的点数照原算法分，池子总量不变。
const int weaponSkillPrefund = 40;

/// 把职业点与兴趣点分完
///
/// ⚠️ 「AI 设置」里的技能上限写进的是 `c.skillCapOcc` / `c.skillCapInterest`
///（**每个技能最终值**的上限），点数池本身永远是规则算出的全额。
void _distributePoints(Character c) {
  final set = occ.occupationalSet(c);
  int capFn(Map<String, Object?> s) => sm.capOf(c, s);

  /* 先看武器 —— 只有武器对应的战斗技能才配拿点；没有武器就保底「斗殴」。
     避免「拿了小刀却把点扔进射击(步枪)/格斗(绞索)」这种没有配套武器的浪费。

     P9：比对口径改成「技能实例 key」（`fighting::斗殴` / `throw`），
     武器的 `skill` 先过别名归一，所以带剑的卡现在真的会点「刀剑」、
     带投掷武器的卡会点「投掷」，而不是统统退回斗殴。 */
  final legacy = legacyWeaponSkillMatchForOracle;
  final legacyNames = legacy ? _legacyWeaponCombatSet(c) : const <String>{};
  final wantKeys = legacy ? const <String>{} : requiredCombatSkillKeys(c);
  bool combatHit(Map<String, Object?> sk) {
    if (legacy) {
      return legacyNames.contains(jsStr(sk['sub'])) ||
          legacyNames.contains(jsStr(sk['id']));
    }
    return wantKeys.contains(jsStr(sk['key']));
  }

  bool combatUsable(Map<String, Object?> sk) {
    if (sm.categoryOf(jsStr(sk['id'])) != '战斗') return true; // 非战斗技能不受限
    return combatHit(sk);
  }

  final pool = <Map<String, Object?>>[];
  for (final sRaw in c.skills) {
    final s = asMap(sRaw);
    final id = jsStr(s['id']);
    if (id == 'credit' || id == 'cthulhu' || rules.isGrowthOnly(id)) continue;
    /* 母语这类「豁免上限」的技能不进加点池（先天能力，非练出来的专长）。 */
    if (rules.capExempt(id)) continue;
    pool.add(s);
  }
  bool inSet(Map<String, Object?> sk) =>
      (set[jsStr(sk['key'])] ?? false) || (set[jsStr(sk['id'])] ?? false);

  final occAll = pool.where(inSet).toList();
  final intAll = pool.where((sk) => !inSet(sk)).toList();
  /* 本职池剔除用不上的战斗技能；但若剔完本职池空了（极端职业全是战斗技），
     就保留原池，避免职业点花不完导致自检不过。兴趣池直接剔。 */
  final occFiltered = occAll.where(combatUsable).toList();
  final occKeys = (occFiltered.isNotEmpty ? occFiltered : occAll)
      .map((sk) => jsStr(sk['key']))
      .toList();
  final intKeys = intAll
      .where(combatUsable)
      .map((sk) => jsStr(sk['key']))
      .toList();

  /* 武器对应战斗技能的 key 集合（保证它们进兴趣焦点、真拿到点） */
  final wantCombatKeys = <String>{};
  for (final sRaw in asList(c.raw['skills'])) {
    final sk = asMap(sRaw);
    if (sm.categoryOf(jsStr(sk['id'])) != '战斗') continue;
    if (combatHit(sk)) wantCombatKeys.add(jsStr(sk['key']));
  }
  /* 武器技能没能在卡里实例化时，保底把「斗殴」拉回池子 —— 否则所有战斗技能
     被排掉、角色一门战斗技都不能打（呼应「斗殴最差也能肉搏攻击」）。 */
  if (wantCombatKeys.isEmpty) {
    for (final sRaw in asList(c.raw['skills'])) {
      final sk = asMap(sRaw);
      if (jsStr(sk['sub']) == '斗殴') wantCombatKeys.add(jsStr(sk['key']));
    }
  }

  /* 需求 9：武器对应的战斗技能必须真的拿到点（理由见 [weaponSkillPrefund]）。
     本职技能从职业点里预支，非本职技能从兴趣点里预支 —— 后者本来就是自由
     选择，花在自己手里的武器上最合理。旧口径（预言机）不预支。 */
  if (!legacy) {
    for (final key in wantCombatKeys) {
      final s = _byKey(c, key);
      if (s == null) continue;
      final field = inSet(s) ? 'occ' : 'int';
      final pts = field == 'occ'
          ? occ.occupationPoints(c)
          : occ.interestPoints(c);
      final room = capFn(s) - jsNum(s['total']);
      final put = math.min(
        weaponSkillPrefund,
        math.min(room, jsNum(pts['remain'])),
      );
      if (put <= 0) continue;
      s[field] = jsNum(s[field]) + put;
      sm.recompute(s);
    }
  }

  /* ⚠️ 预算必须是「**还剩**多少」，不是总额。
     正常生成时技能上还没加点，两者相等；但「恢复全额点数」这种**二次调用**
     时卡上已经有一批点了 —— 拿总额当预算会再分一遍同样的点数，直接超额。
     用 remain 天然对两种情况都成立（也就让这个函数变成幂等的）。
     ⚠️ 预支过武器技能后必须重取一次 remain，否则会多分一份。 */
  _spendOccFocused(
    c,
    occKeys,
    math.max(0, jsNum(occ.occupationPoints(c)['remain'])),
    capFn,
  );

  /* 兴趣点：先集中投在 10 项以内（投 14 项的话每项只剩十几二十点，
     摊得越平，卡越「什么都会一点但都不行」）。但玩家要求「点数必须全部用完」，
     所以这 10 项到顶之后要继续往其余兴趣技能上倒。 */
  final wantInt = intKeys.where(wantCombatKeys.contains).toList();
  final focusCap = math.min(intKeys.length, math.min(10, 7 + per.rnd(4)));
  final restInt = per.shuffleStrings(
    intKeys.where((k) => !wantCombatKeys.contains(k)).toList(),
  );
  final focus = <String>[
    ...wantInt,
    ...restInt,
  ].take(math.max(focusCap, wantInt.length)).toList();
  _spendPoints(
    c,
    focus,
    math.max(0, jsNum(occ.interestPoints(c)['remain'])),
    'int',
    capFn,
    null,
  );
  /* 预支过武器技能后兴趣池的 remain 已经变了，这里必须重新取一次。 */
  final intAfter = jsNum(occ.interestPoints(c)['remain']);
  if (intAfter > 0) {
    _spendPoints(c, intKeys, intAfter, 'int', capFn, null);
  }
}

/* ============================================================
 * 装备：按设定的年代口径从规则数据里挑
 * ============================================================ */

const Set<String> _meleeSkills = <String>{
  '斗殴',
  '剑',
  '斧',
  '矛',
  '鞭子',
  '链枷',
  '绞具',
  '弓',
  '投掷',
};

final RegExp _modernGadget = RegExp(
  '电锯|通电导线|电棍|电击枪|燃烧瓶|炸药|雷管|手榴弹|地雷|管状炸弹|信号枪|'
  '催泪瓦斯|火焰喷射器|迫击炮|坦克炮|舰载炮|反坦克',
);

/* 古代口径下**允许**出现的火器，逐件列出。
 *
 * ⚠️ 这里为什么不能靠 `w.era` 字符串过滤：武器表的 era 字段混了两种语义 ——
 *    「1920s / 现代」是年代，而「罕见」是**稀有度**。早先的写法是
 *    `era.indexOf('罕见') >= 0` 就当古代武器，结果 .58 斯普林菲尔德步枪
 *    （1870 年代的栓动步枪）被判定成古代产物，「武则天」这种古代卡里
 *    会掏出一把 M1873 —— 规则上说不通。所以改成显式白名单，
 *    宁可少给也不能给错。 */
const Set<String> _ancientFirearms = <String>{'遂发枪'};

class WeaponPools {
  WeaponPools(this.melee, this.gun);
  final List<Map<String, Object?>> melee;
  final List<Map<String, Object?>> gun;
}

WeaponPools weaponPools(Map<String, Object?>? setting) {
  final melee = <Map<String, Object?>>[];
  final gun = <Map<String, Object?>>[];
  final era = jsStr(setting?['weaponEra']);
  for (final w in cocWeapons) {
    final skill = jsStr(w['skill']);
    final we = jsStr(w['era']);
    if (_meleeSkills.contains(skill)) {
      if (era == 'ancient' && _modernGadget.hasMatch(jsStr(w['name']))) continue;
      melee.add(w);
      continue;
    }
    if (era == 'ancient') {
      // 古代：只认白名单里的早期火器
      if (_ancientFirearms.contains(jsStr(w['name']))) gun.add(w);
      continue;
    }
    if (era == '1920s') {
      if (we.contains('1920')) gun.add(w);
      continue;
    }
    if (we.contains('现代')) gun.add(w);
  }
  return WeaponPools(melee, gun);
}

List<Map<String, Object?>> _armorPool(Map<String, Object?>? setting) {
  final era = jsStr(setting?['weaponEra']);
  final out = cocArmors.where((a) {
    final e = jsStr(a['era']);
    if (era == 'modern') return e.contains('现代') || e.contains('至今');
    if (era == '1920s') return e.contains('1920') || e.contains('至今');
    return !e.contains('现代') && !e.contains('1920');
  }).toList();
  return out.isNotEmpty ? out : cocArmors;
}

const List<String> _itemsModern = <String>[
  '手电筒',
  '手机',
  '钱包',
  '打火机',
  '急救包',
  '相机',
  '笔记本与铅笔',
  '绳索',
  '瑞士军刀',
  '雨伞',
  '备用弹匣',
  '防风外套',
  '望远镜',
  '备用电池',
  '药盒',
  '充电宝',
  '湿纸巾',
  '口香糖',
  '便携充电线',
  '折叠水杯',
  '头灯',
  '录音笔',
];
const List<String> _items1920 = <String>[
  '手电筒',
  '怀表',
  '烟盒与火柴',
  '皮质笔记本',
  '钢笔与墨水',
  '折叠小刀',
  '绳索',
  '水壶',
  '雨衣',
  '备用子弹',
  '相机',
  '折叠地图',
  '手帕',
  '随身酒壶',
  '报纸',
  '车票',
  '绷带卷',
  '手杖',
  '皮手套',
  '蜡封信纸',
];
const List<String> _itemsAncient = <String>[
  '火折子',
  '油纸伞',
  '毛笔与墨',
  '折扇',
  '布囊',
  '绳索',
  '水囊',
  '干粮',
  '一串铜钱',
  '药囊',
  '短匕',
  '竹简与刀笔',
  '灯笼',
  '斗笠',
  '玉佩',
  '香囊',
  '火镰',
  '算筹',
  '油布',
  '铁蒺藜',
];

List<String> _itemPool(Map<String, Object?>? setting) {
  final era = jsStr(setting?['weaponEra']);
  if (era == 'ancient') return _itemsAncient;
  if (era == '1920s') return _items1920;
  return _itemsModern;
}

/// 把武器数据复制成一张**可改的**卡内条目（`Object.assign({}, m, {qty:1})`）
Map<String, Object?> _copyWeapon(Map<String, Object?> m) {
  final out = Map<String, Object?>.from(m);
  out['qty'] = 1;
  return out;
}

void _fillEquipment(Character c, Map<String, Object?> setting, PickCtx? ctx) {
  final pools = weaponPools(setting);

  c.raw['weapons'] = <Object?>[];
  final weapons = asList(c.raw['weapons']);
  // 1 把近战武器；按设定概率再带一件远程
  final m = per.pickFrom(pools.melee, ctx, 'w_melee');
  if (m != null) weapons.add(_copyWeapon(asMap(m)));
  final gunChance = setting['gunChance'];
  if (pools.gun.isNotEmpty &&
      nowRng() < (jsTruthy(gunChance) ? (gunChance as num).toDouble() : 0)) {
    final g = per.pickFrom(pools.gun, ctx, 'w_gun');
    if (g != null) weapons.add(_copyWeapon(asMap(g)));
  }

  c.raw['armors'] = <Object?>[];
  final armors = asList(c.raw['armors']);
  final ap = _armorPool(setting);
  final arm = per.pickFrom(ap, ctx, 'armor');
  if (arm != null) armors.add(Map<String, Object?>.from(asMap(arm)));

  c.raw['items'] = <Object?>[];
  final items = asList(c.raw['items']);
  final ip = per.shuffleStrings(_itemPool(setting));
  final n = 3 + per.rnd(3);
  for (var i = 0; i < ip.length && i < n; i++) {
    items.add(<String, Object?>{
      'name': ip[i],
      'quantity': 1,
      'description': '',
    });
  }
}

/* ---------- 资产数值 ---------- */

void _fillAssets(Character c, Map<String, Object?>? setting) {
  final levels = asList(cocAssets['livingLevels']).map(asMap).toList();
  if (levels.isEmpty) return;
  final currencies = asList(cocAssets['currencies']).map(asMap).toList();
  final assets = c.assets;
  final cr = jsNum(assets['creditRating']);

  Map<String, Object?>? level;
  for (final l in levels) {
    if (cr >= jsNum(l['crMin']) && cr <= jsNum(l['crMax'])) {
      level = l;
      break;
    }
  }
  level ??= levels.first;
  assets['spendingLevel'] = level['level'];

  /* 货币不再只按时代匹配：古代中国在数据里根本没有对应币种，
     所以每个世界设定显式指定「用哪张倍数表（moneyRef）+ 显示成什么单位」。 */
  final moneyRef = asMap(setting?['moneyRef']);
  final refEra = jsTruthy(moneyRef['era'])
      ? jsStr(moneyRef['era'])
      : jsStr(c.basicInfo['era']);
  final refRegion = jsStr(moneyRef['region']);

  Map<String, Object?>? cur;
  for (final x in currencies) {
    if (jsStr(x['era']) == refEra &&
        (refRegion.isEmpty || jsStr(x['region']) == refRegion)) {
      cur = x;
      break;
    }
  }
  if (cur == null) {
    for (final x in currencies) {
      if (jsStr(x['era']) == refEra) {
        cur = x;
        break;
      }
    }
  }
  if (cur == null && currencies.length > 1) cur = currencies[1];
  if (cur == null) return;

  final unit = setting?['unit'];
  assets['currency'] = jsTruthy(unit) ? unit : cur['unit'];

  List<Object?>? row;
  for (final mRaw in asList(cur['mul'])) {
    final m = asList(mRaw);
    if (m.isNotEmpty && m[0] == level['level']) {
      row = m;
      break;
    }
  }
  if (row != null && cr > 0) {
    final v1 = jsNum(row.length > 1 ? row[1] : null);
    final v2 = jsNum(row.length > 2 ? row[2] : null);
    assets['cash'] = jsRound(v1 > 100 ? v1 : v1 * cr);
    final asset = jsRound(v2 > 1000 ? v2 : v2 * cr);
    final label = setting != null ? jsStr(setting['label']) : jsStr(cur['era']);
    assets['assetsDescription'] =
        '总价值约 ${jsStr(assets['currency'])} $asset（$label，${jsStr(level['level'])}水平）';
  } else {
    assets['cash'] = 0;
    assets['assetsDescription'] =
        '${jsStr(level['level'])}：${jsStr(level['desc'])}';
  }
}

/* ---------- 背景 ---------- */

void _fillBackground(
  Character c,
  Map<String, Object?> occupation,
  Map<String, Object?> setting,
  PickCtx? ctx,
  Map<String, Object?>? pf,
) {
  final bg = c.background;
  /* AI 车卡时会把「长什么样 / 信什么 / 牵挂谁」一起带进来。
     原则：AI 给了就用 AI 的，没给才从池子里补 —— 但池子里的东西会尊重
     世界设定，所以补出来的部分不会和 AI 的描述打架。 */
  final inj = asMap(pf?['background']);

  final description = inj['description'];
  bg['description'] = jsTruthy(description)
      ? description
      : per.buildLook(setting, ctx);
  final ideology = inj['ideology'];
  bg['ideology'] = jsTruthy(ideology)
      ? ideology
      : per.pickFrom(per.beliefs, ctx, 'beliefs');
  final traits = inj['traits'];
  bg['traits'] = jsTruthy(traits)
      ? traits
      : per.shuffleStrings(per.traits.map(jsStr).toList()).take(3).join('、');
  final wounds = inj['wounds'];
  bg['wounds'] = jsTruthy(wounds)
      ? wounds
      : per.pickFrom(per.wounds, ctx, 'wounds');
  final treasure = inj['treasuredPossessions'];
  bg['treasuredPossessions'] = jsTruthy(treasure)
      ? treasure
      : per.pickFrom(per.treasure, ctx, 'treasure');

  // 重要之人：关系 × 经过 × 现状 三段组合，重复概率极低
  final injPeople = inj['significantPeople'];
  if (jsTruthy(injPeople)) {
    bg['significantPeople'] = injPeople;
  } else {
    final rel = per.pickFrom(per.peopleRel, ctx, 'peopleRel');
    final mid = per.pickOne(per.peopleMid);
    final end = per.pickOne(per.peopleEnd);
    bg['significantPeople'] = '${jsStr(rel)}｜${jsStr(mid)}｜${jsStr(end)}';
  }

  // 意义非凡之地：模板里嵌真实地名，地点与出身保持一致
  final injPlaces = inj['meaningfulPlaces'];
  if (jsTruthy(injPlaces)) {
    bg['meaningfulPlaces'] = injPlaces;
  } else {
    final tpl = jsStr(per.pickFrom(per.placeTpl, ctx, 'placeTpl'));
    final sites = asList(setting['sites']);
    final site = jsStr(
      sites.isEmpty ? '城外那处旧地方' : sites[per.rnd(sites.length)],
    );
    final cityRaw = c.basicInfo['residence'];
    final city = jsTruthy(cityRaw)
        ? jsStr(cityRaw)
        : (jsTruthy(c.basicInfo['birthplace'])
              ? jsStr(c.basicInfo['birthplace'])
              : '城里');
    bg['meaningfulPlaces'] = tpl
        .replaceAll('{city}', city)
        .replaceAll('{site}', site);
  }

  final injPhobias = inj['phobias'];
  if (jsTruthy(injPhobias)) {
    bg['phobias'] = injPhobias;
  } else if (jsStr(pf?['eggKind']) == 'friend') {
    /* 跑团成员彩蛋卡一律不带背景心理症状。 */
    bg['phobias'] = '暂无。';
  } else if (jsTruthy(pf?['fromAI'])) {
    /* AI 车卡的背景疯狂症状由 **AI 根据人物描述自行决定**，
       这里必须跳过 1/5 随机闸门 —— 否则会出现「AI 判定没有、系统又掷一条」。 */
    bg['phobias'] = '暂无。';
  } else if (nowRng() < bgMadnessRate) {
    /* 约 1/5 的概率带一条。内容仍走疯狂表新逻辑：8/10 得到一条总结症状
       （文本标【疯狂发作】），各 1/10 得到恐惧症 / 狂躁症。 */
    final lead = jsStr(per.pickOne(per.phobiaLead));
    bg['phobias'] = madness.backgroundText('（$lead）');
  } else {
    bg['phobias'] = '暂无。';
  }

  // 入行经历
  final treasureName = jsStr(bg['treasuredPossessions']).split('｜').first;
  final occName = jsStr(occupation['name']);
  final injHistory = inj['history'];
  String historyDesc;
  if (jsTruthy(injHistory)) {
    historyDesc = jsStr(injHistory);
  } else {
    final tpl = jsStr(per.pickOne(per.historyTpl)).replaceAll('{occ}', occName);
    final tail = jsStr(per.pickOne(per.entryTail))
        .replaceAll('{treasure}', treasureName);
    historyDesc = '$tpl　$tail';
  }
  c.raw['history'] = <Object?>[
    <String, Object?>{
      'title': '入行：$occName',
      'date': '',
      'description': historyDesc,
      'skillChanges': '',
      'itemsObtained': '',
      'notes': '',
      'sanChange': '',
      'hpChange': '',
      'moneyChange': '',
    },
  ];

  // 一位关系人
  final p = jsStr(bg['significantPeople']).split('｜');
  final p0 = p.isNotEmpty && p[0].isNotEmpty ? p[0] : '（未命名）';
  final p1 = p.length > 1 ? p[1] : '';
  final p2 = p.length > 2 ? p[2] : '';
  c.raw['companions'] = <Object?>[
    <String, Object?>{
      'name': p0,
      'avatar': '',
      'identity': '背景关系人',
      'age': '${28 + per.rnd(25)}',
      'relationship': '$occName时期结识',
      'description': p2.isNotEmpty ? '$p1　$p2' : p1,
    },
  ];
}

/* ============================================================
 * 组装一张卡
 * ============================================================ */

Character? _build([PresetOptions? options]) {
  final opts = options ?? PresetOptions();
  final pf = opts.profile ?? <String, Object?>{};
  /* 房规数值上限：随机卡 / 彩蛋卡 / AI 卡走的是**同一份**设置，
     而且每次生成时现读（是变量）—— 改完设置再点「换一批」立刻生效。 */
  final caps = activeCaps(opts);
  // 设定来源优先级：显式传入 > 外部创意里描述的地区/年代 > 加权随机
  final setting =
      opts.setting ??
      (jsTruthy(pf['setting']) ? per.resolve(pf['setting']) : null) ??
      per.pickSetting();
  final ctx = opts.ctx ?? PickCtx();
  // ★ P7：规则系统标记来自**所选规则**（经注册表校验），不硬编码 'coc7'。
  //   AI 卡 / 5 张随机卡 / 彩蛋卡都走 _build，因此三条路径都带标记。
  final c = Character(newCharacter(ruleSystemIdOf(opts)));

  /* 1) 基本信息：姓名与地点都取自同一个世界设定 */
  final pfGender = jsStr(pf['gender']);
  final gender = (pfGender == '男' || pfGender == '女')
      ? pfGender
      : (nowRng() < 0.5 ? '男' : '女');
  final ageRaw = jsParseInt(pf['age']);
  var age = (ageRaw != null && ageRaw != 0) ? ageRaw : _randomAge();
  age = _clamp(age, 15, 80);
  c.basicInfo['gender'] = gender;
  c.basicInfo['age'] = age;
  c.raw['age'] = age;
  final pfEra = pf['era'];
  c.basicInfo['era'] = jsTruthy(pfEra) ? pfEra : setting['era'];
  c.basicInfo['eraCustom'] = jsStr(c.basicInfo['era']) == '自定义'
      ? (jsTruthy(pf['eraCustom'])
            ? pf['eraCustom']
            : (jsTruthy(setting['eraCustom']) ? setting['eraCustom'] : '自定义时代'))
      : '';
  c.raw['worldId'] = setting['id'];

  final cities = asList(setting['cities']);
  /* 彩蛋人物的居住/籍贯直接用资料里的，不随机 ——
     「茶叶蛋 · 现居宿州」这种一致性正是彩蛋要的效果。 */
  final pfResidence = jsTruthy(pf['residence']) ? pf['residence'] : pf['city'];
  final residence = jsTruthy(pfResidence)
      ? pfResidence
      : (per.pickFrom(cities, ctx, 'residence') ?? '未知');
  c.basicInfo['residence'] = residence;

  Object? birth = jsTruthy(pf['birthplace']) ? pf['birthplace'] : pf['town'];
  if (!jsTruthy(birth)) {
    final towns = <Object?>[...asList(setting['towns']), ...cities];
    var tries = 0;
    do {
      birth = per.pickFrom(towns, ctx, 'birthplace');
      tries++;
    } while (jsStr(birth) == jsStr(residence) && tries < 6);
  }
  c.basicInfo['birthplace'] = birth;
  c.raw['characterName'] = jsTruthy(pf['name'])
      ? pf['name']
      : per.nameFor(setting['nameKey'], gender);
  c.raw['playerName'] = jsTruthy(pf['playerName']) ? pf['playerName'] : '预设调查员';

  /* 2) 属性：外部给了且合规就用，否则掷到一组不极端的。
     ⚠️ AI 给的走**宽松**口径（[attrsFromAi]）：AI 车卡允许设置「属性总和上限」，
     压完之后八项合计可能低于随机卡要求的 380，但那是玩家自己定的上限，
     不能因此把 AI 好不容易配出来的人物性格丢掉、退回随机掷骰。 */
  Map<String, Object?> attrs;
  final pfAttrs = pf['attributes'];
  final externalOk =
      jsTruthy(pfAttrs) &&
      (jsTruthy(pf['fromAI'])
          ? attrsFromAi(asMap(pfAttrs))
          : attrsUsable(asMap(pfAttrs)));
  if (externalOk) {
    attrs = <String, Object?>{...c.attributes, ...asMap(pfAttrs)};
  } else {
    var rolled = _rollAttributes();
    for (var t = 1; t < 60 && !attrsUsable(rolled); t++) {
      rolled = _rollAttributes();
    }
    attrs = rolled;
  }
  c.raw['attributes'] = attrs;
  c.raw['attributeMode'] = 'random';
  c.raw['attributeHistory'] = <Object?>[
    <String, Object?>{
      'at': nowMillis(),
      'mode': 'random',
      'note': jsTruthy(pf['fromAI']) ? 'AI 车卡自动生成' : '第 0 步预设卡自动掷骰',
      'attrs': <String, Object?>{...attrs},
    },
  ];

  /* 2.5) 属性总和上限（房规）。掷完 / 采纳完属性立刻压一次 ——
     必须在这里、在算职业点之前：职业点多为「教育×4」之类的公式，
     压完属性池子自然按压缩后的数值算，两边不会打架。
     ⚠️ 彩蛋卡也走这条路径，所以彩蛋一样受房规约束 —— 等比压缩会保住
     「爱因斯坦的智力最高」这种相对关系，压完仍认得出是谁。 */
  if (caps.attrCap > 0) {
    c.raw['attrCapSetting'] = caps.attrCap;
    c.raw['attrCapWithLuck'] = caps.withLuck;
    c.raw['attrCapScaled'] = _applyAttrCapToCard(c, caps);
  }

  engine.recalc(c);

  /* 3) 年龄带来的教育进步检定（真掷） */
  _runEduChecks(c);

  /* 4) 职业 + 本职技能
     属性被压到上限后，职业点公式算出来的池子会同步变小 —— 沿用原来的 120
     下限会把职业全筛掉。按压缩幅度放宽下限：480 = 八项属性的常规总和。 */
  var minPts = 120;
  if (caps.attrCap > 0) {
    minPts = math.max(60, jsRound(120 * caps.attrCap / 480));
  }

  Map<String, Object?>? o;
  List<Object?>? customSkills;
  if (jsTruthy(pf['occupationId'])) {
    o = pickOccupation(c, setting, pf['occupationId'], minPts);
  }
  if (o == null && jsTruthy(pf['occupationName'])) {
    final byName = occupationByName(pf['occupationName']);
    if (byName != null && jsStr(byName['id']) == 'occ1') {
      /* 自定义职业：AI 明确要求时才用。
         规则书原文「不多于 8 个本职技能」由 _fillOccupationPicks 兜住上限。 */
      o = byName;
      customSkills = asList(pf['occupationSkills']).isEmpty
          ? null
          : asList(pf['occupationSkills']);
    } else if (byName != null && byName['creditMin'] != null) {
      o = _meetsNameReqs(byName, engine.effAttrs(c)) ? byName : null;
    }
  }
  o ??= pickOccupation(c, setting, null, minPts);
  if (o == null) return null;
  c.raw['occupationId'] = o['id'];
  c.basicInfo['occupationName'] = o['name'];
  c.raw['occupationPicks'] = <String, Object?>{};
  c.assets['creditMin'] = o['creditMin'];
  c.assets['creditMax'] = o['creditMax'];
  engine.recalc(c);
  sm.syncSkills(c);
  engine.recalc(c);
  _fillOccupationPicks(c, ctx, <String, Object?>{'customSkills': customSkills});

  /* 5) 技能最终值上限 + 信用评级（占用职业点）
   *
   * 上限必须**先**写到角色上 —— 信用评级按 creditMin/creditMax 选值，
   * 而上限会影响「非信用技能」能吃多少点，顺序错了分配预算会算错。
   *
   * ⚠️ 「每项本职技能上限 / 每项兴趣技能上限」的语义是**每个技能最终值
   * 最多到多少**，不是「压缩整个点数池」。所以写进的是 skillCapOcc /
   * skillCapInterest，**点数池本身不压** —— 池子始终是规则算出的全额。
   */
  final occCap = math.max(0, caps.occCap);
  final intCap = math.max(0, caps.intCap);
  if (occCap > 0) c.raw['skillCapOcc'] = occCap;
  if (intCap > 0) c.raw['skillCapInterest'] = intCap;
  if (occCap > 0 || intCap > 0) {
    c.raw['pointCapSetting'] = <String, Object?>{
      'occ': occCap,
      'interest': intCap,
    };
  }
  final occTotal = jsNum(occ.occupationPoints(c)['total']);
  final cr = pickCreditRating(o, occTotal);
  c.assets['creditRating'] = cr;
  for (final sRaw in c.skills) {
    final s = asMap(sRaw);
    if (jsStr(s['id']) == 'credit') {
      s['occ'] = cr;
      sm.recompute(s);
      break;
    }
  }
  engine.recalc(c);

  /* 6) 先定装备（武器必须先于加点，好让战斗技能只加「武器用得上的那门」） */
  _fillEquipment(c, setting, ctx);

  /* 7) 分完职业点与兴趣点（战斗技能按武器对齐） */
  _distributePoints(c);

  /* 8) 资产 / 背景 */
  _fillAssets(c, setting);
  _fillBackground(c, o, setting, ctx, pf);

  /* 8.5) 没上传头像就自动配一张 */
  if (!jsTruthy(c.raw['avatar'])) {
    final worldId = jsStr(setting['id']);
    final warm =
        jsStr(setting['weaponEra']) == 'ancient' ||
        worldId == 'us-1920' ||
        worldId == 'cn-republic' ||
        worldId == 'uk-victorian' ||
        worldId == 'ru-19c';
    avatar.ensure(c.raw, warm ? 'warm' : '');
  }

  /* 9) 彩蛋标记。必须在 build() 里做，不能只放在 generate() 里 ——
     generateOne / buildFrom 也可能被外部直接调用（AI 车卡复用这条路径），
     标记只在 generate 里设的话，从别处进来的彩蛋卡就没有标记。 */
  if (jsTruthy(pf['isEasterEgg'])) {
    c.raw['isEasterEgg'] = true;
    c.raw['eggKind'] = jsTruthy(pf['eggKind']) ? pf['eggKind'] : 'celeb';
  }

  engine.recalc(c);
  return c;
}

/// 生成后自检：规则上不通就重来
bool isSound(Character? c) {
  if (c == null) return false;
  final bad = engine.checkList(c).where((x) => x['ok'] != true).toList();
  return bad.isEmpty;
}

/// 生成一张预设卡（最多试 8 次，最后一次不看自检结果）
Character? generateOne([PresetOptions? opts]) {
  for (var i = 0; i < 8; i++) {
    final c = _build(opts);
    if (c != null && isSound(c)) return c;
  }
  return _build(opts);
}

/// 生成 n 张预设卡。
///
/// 同一批里：世界设定不重复、姓名不重复、背景文本从池子里去重抽取 ——
/// 这样一次出 5 张不会「看起来像同一个人换了件衣服」。
///
/// 彩蛋按「**整批**」抽签而不是按单张卡抽：玩家的操作单位是点一次出 5 张，
/// 按单卡算概率时跑团成员低到「点一次才 13%」，体感就是「这功能没生效」。
/// 改成批级抽签后约 1/4 的批次出现一位跑团成员、约 1/4 出现一位名人，
/// 且彩蛋固定落在批次的中间位置。
List<Character> generate([int? n, PresetOptions? opts]) {
  // ⚠️ 与 JS 一致：`parseInt(n,10) || 5` —— n=0 也会变成 5
  final count = (n == null || n == 0) ? 5 : n;
  final options = opts ?? PresetOptions();
  final ctx = PickCtx();
  final out = <Character>[];
  final usedName = <String, bool>{};
  final usedSetting = <String, bool>{};
  var guard = 0;
  /* 房规数值上限：**整批只读一次**，5 张卡用同一份上限 ——
     否则玩家改设置的瞬间正在生成，一批里会出现两种口径。 */
  final caps = activeCaps(options);

  /* ---- 批级彩蛋计划：整批只抽一次，决定「这一批的第几张是彩蛋」 ---- */
  var eggAt = -1;
  egg.EasterEgg? planned;
  if (options.setting == null && options.profile == null && count > 0) {
    planned = egg.rollBatch(count);
    eggAt = planned != null ? (count / 2).floor() : -1; // 固定落在中间那张
  }

  var slotIdx = 0;
  while (out.length < count && guard++ < count * 10) {
    /* 用到这一张就是彩蛋；用掉即弃（eggAt 只匹配一次） */
    var thisEgg = (slotIdx == eggAt) ? planned : null;
    if (thisEgg != null) {
      eggAt = -1;
      planned = null;
    }
    slotIdx++;

    // 优先挑本批还没用过的世界设定，避免 5 张卡全挤在同一个地区
    //
    // ⚠️ 随机顺序：`PER.pick()` 一定先掷（加权随机），只有在
    //    「本批还有 ≥2 个没用过、且刚抽到的已经用过」时才**再**掷一次
    //    `rnd(fresh.length)`。顺序反了会让整批的随机序列整体错位。
    final Map<String, Object?> setting;
    final forced = options.setting;
    if (forced != null) {
      setting = forced;
    } else if (thisEgg != null) {
      setting = per.resolve(thisEgg.data['setting']) ?? per.pickSetting();
    } else {
      final fresh = per.list
          .where((s) => !(usedSetting[jsStr(s['id'])] ?? false))
          .toList();
      final picked = per.pickSetting(); // 加权随机
      if (fresh.length > 1 && (usedSetting[jsStr(picked['id'])] ?? false)) {
        setting = fresh[per.rnd(fresh.length)];
      } else {
        setting = picked;
      }
    }
    usedSetting[jsStr(setting['id'])] = true;

    final c = generateOne(
      PresetOptions(
        setting: setting,
        ctx: ctx,
        caps: caps,
        ruleSystemId: options.ruleSystemId,
        profile: thisEgg != null ? egg.toProfile(thisEgg) : options.profile,
      ),
    );
    if (c == null) continue;

    // 彩蛋角色的姓名不能被「重名就换名」的逻辑改掉
    if (thisEgg == null && (usedName[jsStr(c.raw['characterName'])] ?? false)) {
      for (var k = 0; k < 12; k++) {
        final nm = per.nameFor(setting['nameKey'], c.basicInfo['gender']);
        if (!(usedName[nm] ?? false)) {
          c.raw['characterName'] = nm;
          break;
        }
      }
      if (usedName[jsStr(c.raw['characterName'])] ?? false) {
        c.raw['characterName'] =
            '${jsStr(c.raw['characterName'])}·${out.length + 1}';
      }
      // 名字换了，头像也得跟着换
      c.raw['avatar'] = '';
      avatar.ensure(c.raw);
    }
    if (thisEgg != null) {
      c.raw['isEasterEgg'] = true;
      c.raw['eggKind'] = thisEgg.kind;
      // 彩蛋必须严格用资料里的名字（AI/预设流程可能改写过）
      c.raw['characterName'] = thisEgg.data['name'];
      c.raw['playerName'] = thisEgg.isFriend ? '茶叶蛋调查员协会' : '预设调查员';
      // 名人按自己的时代；朋友一律现代
      c.basicInfo['era'] = thisEgg.isFriend
          ? '现代'
          : (jsTruthy(thisEgg.data['era'])
                ? thisEgg.data['era']
                : setting['era']);
      if (jsStr(c.basicInfo['era']) == '自定义') {
        c.basicInfo['eraCustom'] = jsTruthy(thisEgg.data['eraCustom'])
            ? thisEgg.data['eraCustom']
            : '';
      }
      c.raw['avatar'] = '';
      avatar.ensure(c.raw);
    }
    usedName[jsStr(c.raw['characterName'])] = true;
    out.add(c);
  }
  return out;
}

/// 重新分配一次职业点与兴趣点。
///
/// 改了 skillCapOcc / skillCapInterest 之后可以用它重排。
/// 预算是**剩余量 remain** 而不是总额，所以重复调用不会超支（幂等）。
void redistributePoints(Character? c) {
  if (c == null) return;
  _distributePoints(c);
  engine.recalc(c);
}

/// 造一张卡并注入外部创意（AI 车卡入口）
Character? buildFrom(
  Map<String, Object?> profile, [
  Object? settingId,
  PresetOptions? opts,
]) {
  final setting = jsTruthy(settingId) ? per.resolve(settingId) : null;
  final o = PresetOptions(
    setting: setting,
    ctx: PickCtx(),
    profile: profile,
    ruleSystemId: opts?.ruleSystemId,
  );
  // 兼容旧的 ptsCap 写法：只给技能上限、不给属性上限
  if (opts != null && opts.caps != null) {
    o.caps = opts.caps;
  } else if (opts != null && opts.ptsCap != null) {
    o.caps = AiCaps(
      attrCap: 0,
      withLuck: true,
      occCap: jsNum(opts.ptsCap!['occ']),
      intCap: jsNum(opts.ptsCap!['int']),
    );
  }
  return generateOne(o);
}

/// 一张卡的摘要数据（供第 0 步列表展示）
Map<String, Object?> summaryOf(Character c) {
  engine.recalc(c);
  final d = c.derivedStats;
  final o = occ.getOccupationById(c.occupationId) ?? <String, Object?>{};
  final worldId = jsStr(c.raw['worldId']);
  final setting = worldId.isEmpty ? null : per.getById(worldId);
  final set = occ.occupationalSet(c);
  final top = _skills(c)
      .where((s) => jsNum(s['occ']) + jsNum(s['int']) > 0)
      .toList();
  _stableSort(top, (a, b) => jsNum(b['total']) - jsNum(a['total']));
  final top6 = top.take(6).toList();
  final st = sm.stats(c);
  final stOcc = asMap(st['occ']);
  final stInt = asMap(st['interest']);
  final occCapRaw = jsNum(st['occCap']);
  final intCapRaw = jsNum(st['interestCap']);
  final eduLog = asList(c.eduProgress['log']);

  return <String, Object?>{
    'card': c.raw,
    // ★ P7-D：候选卡卡面要能显示规则徽标，值来自卡上的 ruleSystemId。
    'ruleSystemId': c.ruleSystemId,
    'name': c.raw['characterName'],
    'avatar': c.raw['avatar'],
    'gender': c.basicInfo['gender'],
    'age': c.basicInfo['age'],
    'era': jsStr(c.basicInfo['era']) == '自定义'
        ? c.basicInfo['eraCustom']
        : c.basicInfo['era'],
    'world': setting != null ? setting['label'] : '',
    /* 彩蛋标记：🥚 名人 / 🎭 跑团成员 */
    'egg': jsTruthy(c.raw['isEasterEgg'])
        ? (jsStr(c.raw['eggKind']) == 'friend' ? '🎭' : '🥚')
        : '',
    'eggKind': jsTruthy(c.raw['eggKind']) ? c.raw['eggKind'] : '',
    'residence': c.basicInfo['residence'],
    'birthplace': c.basicInfo['birthplace'],
    'occupation': jsTruthy(o['name']) ? o['name'] : '—',
    'credit': c.assets['creditRating'],
    'currency': c.assets['currency'],
    'attrs': c.attributes,
    'hp': d['maxHP'],
    'mp': d['maxMP'],
    'san': d['maxSAN'],
    'mov': d['mov'],
    'build': d['build'],
    'db': d['db'],
    'luck': c.status['currentLuck'],
    'occUsed': stOcc['used'],
    'occTotal': stOcc['total'],
    'intUsed': stInt['used'],
    'intTotal': stInt['total'],
    /* 房规数值上限：**只有真正低于规则默认值（99 = 不限）时才算生效**。
       旧写法直接抛 st.occCap —— 而随机卡身上 skillCapOcc 默认就是 99，
       于是每张随机卡都会误报「被上限压过」。99 就是「不限」，不是「上限 99」。 */
    'occCap': (occCapRaw > 0 && occCapRaw < rules.defaultOccSkillCap)
        ? occCapRaw
        : 0,
    'intCap': (intCapRaw > 0 && intCapRaw < rules.defaultInterestSkillCap)
        ? intCapRaw
        : 0,
    /* 属性总和上限：生成时确实按它压过才记在卡上，没设就是 0 */
    'attrCap': jsNum(c.raw['attrCapSetting']),
    'attrCapWithLuck': c.raw['attrCapWithLuck'] != false,
    'attrCapScaled': jsTruthy(c.raw['attrCapScaled']),
    'eduChecks': eduLog.length,
    'eduBonus': jsNum(c.eduProgress['bonus']),
    'occtSkills': set.length,
    'topSkills': top6
        .map(
          (s) => <String, Object?>{
            'name': s['name'],
            'total': s['total'],
            'occ':
                (set[jsStr(s['key'])] ?? false) ||
                (set[jsStr(s['id'])] ?? false),
          },
        )
        .toList(),
    'weapons': asList(c.raw['weapons']).map((w) => asMap(w)['name']).toList(),
    'armors': asList(c.raw['armors']).map((a) => asMap(a)['name']).toList(),
    'items': asList(c.raw['items']).map((i) => asMap(i)['name']).toList(),
    'look': c.background['description'],
    'belief': c.background['ideology'],
    'traits': c.background['traits'],
    'phobia': c.background['phobias'],
    'people': c.background['significantPeople'],
    'place': c.background['meaningfulPlaces'],
    'treasure': c.background['treasuredPossessions'],
    'wound': c.background['wounds'],
    'history': asList(c.raw['history']).map((h) => asMap(h)['title']).toList(),
  };
}

/// 该卡属于哪个世界设定
Map<String, Object?>? settingOf(Character? c) {
  if (c == null) return null;
  final id = jsStr(c.raw['worldId']);
  if (id.isEmpty) return null;
  return per.getById(id);
}

/// 职业名门槛判定（对外暴露，审计 / 测试用）
bool meetsNameReqs(Map<String, Object?> o, Map<String, Object?> attrs) =>
    _meetsNameReqs(o, attrs);
