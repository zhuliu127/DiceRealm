// ============================================================
// ai_gen.dart — AI 车卡的「纯」部分：提示词 / JSON 解析 / profile 清洗
// 对应 `core/ai.js#AIGen` 里**不碰网络**的那几个函数
//
// ⚠️ 为什么 makeCharacter 不在这里：
//   它必须发 HTTP。`lib/domain` 是零 Flutter、零 IO 的纯规则层，
//   网络调用放在 `lib/net/ai_create.dart`。分工是：
//     domain/ai_gen.dart   提示词 + 解析 + 清洗（纯函数，可逐字节比对旧版）
//     net/ai_create.dart   调模型 + 重试 + 落地成卡（依赖 HttpClient）
//
// 🎯 核心不变式（整条 AI 车卡的立足点）：
//   **AI 只给创意字段，数值一律由 preset_gen 的规则引擎生成。**
//   所以 parseJson / toProfile 对恶意输入的唯一正确反应是
//   「丢掉这一项、回落到规则生成」，绝不能把 AI 的数值直接写进卡里。
// ============================================================

import 'dart:convert';

import 'ai_caps.dart';
import 'data/occupations.dart';
import 'js_compat.dart';
import 'personas.dart' as per;
import 'preset_gen.dart' as preset;

/// 解析失败时抛它（消息本身就是给人看的，可以直接显示）
class AiGenException implements Exception {
  AiGenException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 系统提示词（`ai.js#SYSTEM_PROMPT`，逐字节照抄）
const List<String> _systemPromptLines = <String>[
  '你是一位资深的《克苏鲁的呼唤》第七版（COC 7th）跑团守秘人，擅长把玩家一句',
  '随手写的点子扩写成一位有血有肉、能直接上桌的调查员。',
  '',
  '你的输出必须是**一个 JSON 对象**，从第一个字符 { 到最后一个字符 } 为止，',
  '不要输出任何解释、前后缀、Markdown 代码块围栏或注释。',
  '所有文本字段一律使用简体中文，人名与地名按所选时代与地区的习惯书写。',
];

final String aiSystemPrompt = _systemPromptLines.join('\n');

/// 描述示例（`ai.js#EXAMPLES`）
const List<String> aiExamples = <String>[
  '一个在旧书店打工的女大学生，喜欢研究古旧地图，胆子小但好奇心很重',
  '民国时期的私家侦探，前警察，因为一桩案子丢了差事，随身带着一副旧手铐',
  '1920 年代波士顿的报社记者，参加过一战，落下了耳背的毛病',
  '中国当代的法医，理性到近乎冷淡，但会替无名死者记下名字',
  '维多利亚时代的乡村医生，业余研究真菌，被同行视为怪人',
  '近未来的机械师，装了一条二手义肢，靠修旧机器过活',
];

/// 职业清单（去重、剔除自定义职业）—— 给模型一份「可选项」，
/// 避免它编出不存在的职业名。
///
/// 缓存：这份清单有 200 多条，每次生成都要拼进提示词，
/// 而职业数据是 const，进程内不会变。
List<String>? _occNamesCache;

List<String> occNames() {
  final cached = _occNamesCache;
  if (cached != null) return cached;
  final seen = <String>{};
  final out = <String>[];
  for (final o in cocOccupations) {
    final name = jsStr(o['name']);
    if (name.isEmpty || jsStr(o['id']) == 'occ1') continue;
    if (o['creditMin'] == null) continue;
    if (seen.contains(name)) continue;
    seen.add(name);
    out.add(name);
  }
  _occNamesCache = out;
  return out;
}

/// 上限写进提示词的那几行（没设就返回空数组）
List<String> capLines([AiCaps? caps]) {
  final c = caps ?? capsFromSettings(preset.presetSettings);
  final out = <String>[];
  if (c.attrCap > 0) {
    out.add(
      '· 属性总和上限：${c.withLuck ? '九项（含幸运）' : '八项（不含幸运）'}相加不得超过 '
      '${c.attrCap}。请主动把数值压在上限内，不要等到被提醒。',
    );
  }
  if (c.occCap > 0) out.add('· 每项本职技能的最终值不得超过 ${c.occCap} 点。');
  if (c.intCap > 0) out.add('· 每项非本职（兴趣）技能的最终值不得超过 ${c.intCap} 点。');
  return out;
}

/// 把玩家的一句话扩成完整提示词（`ai.js#buildPrompt`，逐字节照抄）
String buildPrompt(String desc, {AiCaps? caps}) {
  final labels = per.labels.join('\n  ');
  final names = occNames().join('、');
  final lines = capLines(caps);
  final out = <String>[
    '请根据下面这段玩家的描述，创建一位调查员：',
    '"""',
    desc.trim(),
    '"""',
    '',
    '【第一步】从下列世界设定中选一个最贴合的，填入 setting 字段，必须原样照抄其中一个：',
    '  $labels',
    '',
    '【第二步】职业：优先从下面这份清单里选一个最贴合的，填入 occupationName（原样照抄）：',
    names,
    '  只有当清单里确实没有任何一个贴合时，才填「自定义职业」，',
    '  并在 occupationSkills 里给出 6-8 个本职技能名（从上面的职业描述里挑说法，',
    '  例如 ["侦查","潜行","图书馆使用","心理学","说服","手枪射击"]）。',
    '',
    '【第三步】按下面的结构输出 JSON：',
    '{',
    '  "setting": "上面清单里的某一个，原样照抄",',
    '  "name": "★（最高优先）如果玩家的描述里明确指定了角色姓名（例如「车一个刘华强」「名字叫张三」），必须原样使用玩家指定的姓名，'
        '不得改写、不得谐音、不得另起新名字；'
        '仅当玩家没有指定姓名时，才自行起一个符合该设定文化的完整人名，每次都必须生成与示例不同的人名，'
        '不得重复使用同一姓名；'
        '下面只是格式示范，禁止照抄：林砚秋 / 陆知微 / 顾长庚 / 温静姝 / 裴允行",',
    '  "gender": "男 或 女",',
    '  "age": 15 到 75 之间的整数,',
    '  "residence": "现居城市，必须是该设定下合理的地名",',
    '  "birthplace": "出生地，同样合理，且不能与现居城市相同",',
    '  "occupationName": "上面职业清单里的某一个，或「自定义职业」",',
    '  "occupationSkills": ["仅当 occupationName 为「自定义职业」时才填，6-8 个技能名"],',
    '  "attributes": { "str": 0, "con": 0, "siz": 0, "dex": 0, "app": 0, "int": 0, "pow": 0, "edu": 0, "luck": 0 },',
    '  "background": {',
    '    "description": "外貌，一句话，要有具体细节",',
    '    "ideology": "信念，以「信念：」开头，一句话",',
    '    "significantPeople": "严格按「关系｜经过｜现状」三段写",',
    '    "meaningfulPlaces": "严格按「地点｜氛围｜意义」三段写",',
    '    "treasuredPossessions": "严格按「物品｜特征｜来历｜意义」四段写",',
    '    "traits": "三到四个性格特点，用「、」分隔",',
    '    "wounds": "一处旧伤，没有就写「无。」",',
    '    "phobias": "根据这个人物的性格与经历，判断他是否可能有背景疯狂症状',
    '（恐惧症 / 狂躁症 / 疯狂发作）：有就写「【恐惧症】」或「【狂躁症】」或',
    '「【疯狂发作】」+ 具体症状名 + 「：」+ 一句具体描述；没有就写「无。」。',
    '由你依据人物设定判断，不要人人都写一条，也不要为了写而强行编造",',
    '    "history": "两到三句话的入行经历，要能看出他为什么走上这条路"',
    '  }',
    '}',
    '',
    '数值要求（重要，请严格遵守）：',
    '· str/con/siz/dex/app/int/pow 取值 20-90；edu 取值 40-95；luck 取值 15-90。',
    '· 数值要与职业和年龄相称：学者型 int/edu 高，运动员与体力职业 str/con/dex 高，',
    '  年长者 edu 可以高但 dex 偏低。不要所有人都是相同的数字。',
  ];
  if (lines.isNotEmpty) {
    out.add('');
    out.add('本次的硬性上限（超过会被自动压缩，请主动遵守）：');
    out.addAll(lines);
  }
  out.add('');
  out.add('内容要求：');
  out.add('· 姓名、地名、职业、装备、经历必须在同一个时代与地区里说得通 ——');
  out.add('  例如选「中国 · 古代」就不要出现手枪、电脑、现代职称。');
  out.add('· 背景要贴合玩家描述里透露的线索，不要写成放之四海皆可的空话。');
  out.add('');
  out.add('现在只输出这个 JSON。');
  return out.join('\n');
}

/* ============================================================
 * 姓名兜底（v2.46.0 起：只兜空名，不再纠偏）
 *
 * 历史教训（保留记录）：模型对姓名曾有顽固偏好 —— 同一段描述反复生成，
 * 十有八九还是同一个名字（「沈砚清」就是这么来的 —— 全工程 grep 不到，
 * 完全是模型自己产的）。v2.39.0 为此做过「本地姓名池纠偏」：
 * AI 结果落地前，空名 / 常见重复值 / 与上一次相同 → 一律换成本地随机名。
 *
 * 但纠偏有反向代价：玩家在描述里明确指定的姓名（「车一个华强买瓜里面的
 * 刘华强」→ 应叫「刘华强」）也会被池子覆盖，QA 2025 反馈确认这是真问题。
 * v2.46.0 起改为：
 *   · 姓名完全采信模型 —— 玩家指定的姓名由提示词约束「必须原样使用」
 *     （写为最高优先级条款），多样性也由提示词约束（每次不同）；
 *   · 本地只在**名字为空**时用 [randomInvestigatorName] 兜底，
 *     不再做任何其它纠偏（`ensureFreshInvestigatorName` 已删除）。
 * ============================================================ */

/// 姓氏池（单字姓，35 个；含沈但远不止沈，刻意铺开冷门姓）
const List<String> _surnamePool = <String>[
  '沈', '陆', '顾', '程', '叶', '温', '裴', '阮', '邵', '傅',
  '霍', '岑', '黎', '穆', '祁', '商', '闻', '褚', '晏', '崔',
  '虞', '路', '容', '闵', '苏', '江', '许', '谢', '秦', '韩',
  '白', '池', '凌', '卫', '段',
];

/// 名字池（单字 / 双字混合，≥40 个）
const List<String> _givenNamePool = <String>[
  '之遥', '承宇', '望舒', '知微', '允行', '明澈', '叙白', '若川',
  '怀瑾', '静姝', '书言', '清让', '亦安', '星野', '衡之', '既明',
  '长庚', '秋池', '逸舟', '观澜', '听雨', '未晞', '行舟', '慕辰',
  '令仪', '归远', '疏影', '寒山', '云归', '若水', '一苇', '临渊',
  '珩', '玦', '澈', '舟', '渊', '昀', '岚', '樟',
  '樵', '樾', '彧', '昭', '湛', '沅', '漪', '珂',
];

/// 打散后的全量名字袋（姓氏 × 名字），取完一轮再重新打散
List<String>? _nameBag;

List<String> _buildNameBag(JsRng rng) {
  final all = <String>[];
  for (final s in _surnamePool) {
    for (final g in _givenNamePool) {
      all.add('$s$g');
    }
  }
  // Fisher–Yates：只依赖传入的 rng，便于测试用固定种子复现
  for (var i = all.length - 1; i > 0; i--) {
    final r = rng();
    final j = (r.isFinite ? (r < 0 ? 0 : (r > 1 ? 1 : r)) : 0) * (i + 1);
    final k = j.floor();
    if (k == i) continue;
    final t = all[i];
    all[i] = all[k];
    all[k] = t;
  }
  return all;
}

/// 本地随机中文名（2-4 个汉字）—— **只**用于 AI 落地时的空名兜底。
///
/// 连续调用会把一整袋（35 × 48 = 1680 个）名字打散后逐个取用，
/// 因此**一轮之内不会重复**；袋空后重新打散。
/// v2.46.0 起：模型给的非空姓名一律原样保留，不再走这里。
String randomInvestigatorName([JsRng? rng]) {
  final r = rng ?? nowRng;
  var bag = _nameBag;
  if (bag == null || bag.isEmpty) {
    bag = _nameBag = _buildNameBag(r);
  }
  return bag.removeLast();
}

/* ============================================================
 * JSON 抠取
 *
 * 模型的实际输出五花八门，这里按「从宽到严」逐级抢救：
 *   ① 去掉 ```json 围栏 → 直接 parse
 *   ② 从第一个 { 开始配平花括号 → 抠出片段 parse
 *   ③ 去掉尾随逗号再 parse
 *   ④ 仍失败 → 抛带上下文的可读错误
 *
 * ⚠️ 刻意**不**做的三件事：
 *   · 不修单引号 / 不补括号 —— 那等于猜模型想写什么，猜错会把
 *     「缺失的字段」变成「错误的字段」，比失败更糟；
 *   · 不吞异常 —— 调用方需要知道「这次是截断还是格式错」才决定重试策略；
 *   · 不把数组 / 数字当卡 —— 返回什么就是什么，由 [toProfile] 兜。
 * ============================================================ */

/// 从模型回复里把 JSON 抠出来（容忍代码块围栏、前后废话、尾随逗号）
///
/// @returns 解析出的任意 JSON 值（可能是 Map / List / null / 标量）
/// @throws AiGenException 抠不出来（消息里带上下文，可直接显示）
Object? parseJson(Object? text) {
  var s = jsStr(text ?? '').trim();
  s = s.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'```\s*$'), '').trim();

  final direct = _tryDecode(s);
  if (direct.ok) return direct.value;

  final start = s.indexOf('{');
  if (start < 0) {
    final head = s.length > 40 ? s.substring(0, 40) : s;
    throw AiGenException('模型没有返回 JSON 结构（回复开头是：$head…）');
  }

  var depth = 0;
  var inStr = false;
  var esc = false;
  var end = -1;
  for (var i = start; i < s.length; i++) {
    final ch = s[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (ch == r'\') {
        esc = true;
      } else if (ch == '"') {
        inStr = false;
      }
      continue;
    }
    if (ch == '"') {
      inStr = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) {
    /* 花括号没配平 —— 这是「被 max_tokens 截断」最典型的症状，
       模型正写到一半额度就没了。把尾部露出来方便判断。 */
    final tail = s.length > 50 ? s.substring(s.length - 50) : s;
    throw AiGenException('模型返回的 JSON 不完整（花括号没配平，末尾停在：…$tail）');
  }

  final frag = s.substring(start, end + 1);
  final second = _tryDecode(frag);
  if (second.ok) return second.value;

  // 常见毛病：末尾多了逗号
  final fixed = frag.replaceAllMapped(
    RegExp(r',\s*([}\]])'),
    (m) => m.group(1)!,
  );
  final third = _tryDecode(fixed);
  if (third.ok) return third.value;
  throw AiGenException('JSON 格式有误：${third.error ?? second.error}');
}

class _DecodeAttempt {
  const _DecodeAttempt(this.ok, this.value, this.error);
  final bool ok;
  final Object? value;
  final String? error;
}

_DecodeAttempt _tryDecode(String s) {
  try {
    return _DecodeAttempt(true, jsonDecode(s), null);
  } catch (e) {
    return _DecodeAttempt(false, null, '$e');
  }
}

/* ============================================================
 * profile 清洗
 * ============================================================ */

/// JS `String(v)` 的忠实版（对象 / 数组的字符串化与 JS 一致）
///
/// 为什么不用 Dart 的 `toString()`：`Map` 在 Dart 里是 `{a: 1}`，JS 是
/// `[object Object]`；数组在 JS 里是 `1,2`。AI 万一在文本字段里塞了对象，
/// 两边落地的文案就会不同 —— 虽然罕见，但没有理由让它们不同。
String _jsString(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is bool) return v ? 'true' : 'false';
  if (v is Map) return '[object Object]';
  if (v is List) {
    return v.map((x) => x == null ? '' : _jsString(x)).join(',');
  }
  return jsStr(v);
}

/// 把模型给的零散信息洗成 `preset_gen.buildFrom()` 能吃的 profile
///
/// ⚠️ 清洗原则：**能给空串就给空串，绝不给错值**。
///   每个字段都独立兜底（哪一项坏了只丢那一项），因为规则层对空值
///   会自己从池子里补，对错值却会照着错值生成。
Map<String, Object?> toProfile(Object? rawIn) {
  final raw = rawIn is Map
      ? rawIn.cast<Object?, Object?>()
      : const <Object?, Object?>{};
  const attrKeys = <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
    'luck',
  ];

  Map<String, Object?>? attrs;
  final a0 = raw['attributes'];
  if (a0 is Map) {
    final out = <String, Object?>{};
    var any = false;
    for (final k in attrKeys) {
      final v = jsParseInt(a0[k]);
      if (v != null) {
        out[k] = v;
        any = true;
      }
    }
    if (any) attrs = out;
  }

  /// 单行化 + 截断（旧版 `s()`）
  String s(Object? v) {
    if (v == null) return '';
    var text = _jsString(v).replaceAll(RegExp(r'\s*\n+\s*'), ' ').trim();
    if (text.length > 240) text = text.substring(0, 240);
    return text;
  }

  final bgIn = raw['background'] is Map
      ? (raw['background'] as Map)
      : const <Object?, Object?>{};
  final bg = <String, Object?>{
    'description': s(bgIn['description']),
    'ideology': s(bgIn['ideology']),
    'significantPeople': s(bgIn['significantPeople']),
    'meaningfulPlaces': s(bgIn['meaningfulPlaces']),
    'treasuredPossessions': s(bgIn['treasuredPossessions']),
    'traits': s(bgIn['traits']),
    'wounds': s(bgIn['wounds']),
    'phobias': s(bgIn['phobias']),
    'history': s(bgIn['history']),
  };
  /* 背景疯狂症状**采信 AI 的返回值**（含它写「无。」= 判定没有）：
     提示词已要求它依据人物判断，preset 侧对 fromAI 的卡也跳过了 1/5 随机闸门，
     避免「AI 说了无、系统又掷一条」的双重决定。 */
  final hasBg = bg.values.any(jsTruthy);

  final genderRaw = jsStr(raw['gender']);
  final gender = (genderRaw == '男' || genderRaw == '女') ? genderRaw : '';
  final age = jsParseInt(raw['age']);

  /* 自定义职业时模型给的本职技能名（6-8 个），交给 preset 去解析；
     解析不出来的名字会在那边被跳过，所以这里不做严格校验。 */
  List<Object?>? occSkills;
  final os = raw['occupationSkills'];
  if (os is List) {
    final arr = <Object?>[];
    for (final x in os) {
      // 旧版 `String(x || '').trim()`：false / 0 / null / '' 等 falsy 值
      // 一律回落成空串并被 filter(Boolean) 丢掉，不能变成 'false' / '0'。
      final v = (jsTruthy(x) ? _jsString(x) : '').trim();
      if (v.isNotEmpty) arr.add(v);
      if (arr.length >= 8) break;
    }
    if (arr.isNotEmpty) occSkills = arr;
  }

  return <String, Object?>{
    'fromAI': true,
    'occupationSkills': occSkills,
    'setting': s(raw['setting']),
    'name': s(raw['name']),
    'gender': gender,
    'age': (age != null && age != 0 && age >= 15 && age <= 75) ? age : 0,
    'residence': s(raw['residence']),
    'birthplace': s(raw['birthplace']),
    'occupationId': s(raw['occupationId']),
    'occupationName': s(raw['occupationName']),
    'attributes': attrs,
    'background': hasBg ? bg : null,
  };
}
