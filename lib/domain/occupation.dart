// ============================================================
// occupation.dart — 职业模型
// 逐行对应 `core/occupation.js`（`CocOccupation`，700 行）
//
//   1. 解析职业的「本职技能」描述文本 → 结构化选择规则
//   2. 解析职业的「属性点公式」→ 职业技能点总数
//   3. 计算职业点 / 兴趣点使用情况
//
// ⚠️ 结构说明：JS 里 `COC7.validators` 的 4 个职业相关校验器反向依赖本模块，
//   形成全局环。Dart 的 import 不能成环，所以那 4 个校验器放在这里
//   （[validateOccupationChoices] / [validateSkillPoints] / [validateSkillCap] /
//    [validateCreditRating]），函数名语义与输出文案与 JS 逐字一致。
// ============================================================

import 'character.dart';
import 'data/occupations.dart';
import 'data/skills.dart';
import 'js_compat.dart';
import 'rules_coc7.dart';

/* ---------- 技能名 → 技能 id 映射 (含别名, 取自卡表"技能名的改变") ----------
 * 注：原 JS 对象字面量里有 3 个键写了两遍（'开锁' / '撬锁' / '电脑'），
 *     值完全相同，对象语义下后者覆盖前者、不影响结果；Dart 的 const map
 *     不允许重复键，这里直接保留一份。 */
const Map<String, String> alias = <String, String>{
  '图书馆': 'library',
  '图书馆使用': 'library',
  '计算机': 'computer',
  '电脑': 'computer',
  '计算机使用': 'computer',
  '汽车': 'drive_auto',
  '驾驶汽车': 'drive_auto',
  '汽车驾驶': 'drive_auto',
  '开锁': 'locksmith',
  '锁匠': 'locksmith',
  '自然学': 'natural_world',
  '博物学': 'natural_world',
  '导航': 'navigate',
  '领航': 'navigate',
  '重型操作': 'op_heavy',
  '重型机械': 'op_heavy',
  '重型': 'op_heavy',
  '重型机械操作': 'op_heavy',
  '操作重型机械': 'op_heavy',
  '信用': 'credit',
  '信誉': 'credit',
  '信用评级': 'credit',
  '克苏鲁': 'cthulhu',
  'cm': 'cthulhu',
  '克苏鲁神话': 'cthulhu',
  '步枪': 'firearms',
  '霰弹枪': 'firearms',
  '步霰': 'firearms',
  '撬锁': 'locksmith',
  '侦查': 'spot_hidden',
  '侦察': 'spot_hidden',
  '电气维修': 'elec_repair',
  '机械维修': 'mech_repair',
  '技艺': 'art_craft',
  '艺术与手艺': 'art_craft',
  '艺术': 'art_craft',
  '科学': 'science',
  '格斗': 'fighting',
  '射击': 'firearms',
  '生存': 'survival',
  '驾驶': 'pilot',
  '外语': 'language_other',
  '母语': 'language_own',
  '学问': 'lore',
  '自然': 'natural_world',
  '骑乘': 'ride',
  '骑马': 'ride',
  '速记': 'art_craft',
  '会计学': 'accounting',
  '医学': 'medicine',
  '急救': 'first_aid',
  '考古': 'archaeology',
  '心理': 'psychology',
  '摄影': 'art_craft',
  '说服': 'persuade',
  '法律': 'law',
  '手艺': 'art_craft',
  '其他语言': 'language_other',
  '语言': 'language_other',
  '电工': 'elec_repair',
  '马车驾驶': 'pilot',
  '自行车驾驶': 'pilot',
  '驾驶：船': 'pilot',
  '钳工': 'mech_repair',
  '礼仪': 'persuade',
  '拉丁语': 'language_other',
  '外语（母语或外语）': 'language_other',
  /* 技能库里这一项的正式名是「取悦」（旧译「魅惑」）。
     职业数据 130+ 处写的是「魅惑」，不别名过来的话
     「两项社交技能（魅惑、话术、恐吓、说服）」只能解析出 3 项。 */
  '魅惑': 'charm',
  '取悦': 'charm',
  '魅惑（取悦）': 'charm',
  '魅惑/取悦': 'charm',
  '电子学': 'elec_repair',
  '电子': 'elec_repair',
  '艺术及手艺': 'art_craft',
  '艺术/工艺': 'art_craft',
};

/* ---------- 组技能「子类」别名 ----------
 * 职业数据里的写法与技能库的子类名常有出入（制药 / 药剂学 → 药学，拉丁文 → 拉丁语…）
 * 不归一化的话，「科学（生物学，制药）」会丢一项。 */
const Map<String, String> subAlias = <String, String>{
  '制药': '药学',
  '药剂学': '药学',
  '药物学': '药学',
  '拉丁文': '拉丁语',
  '物理': '物理学',
  '生物': '生物学',
  '植物': '植物学',
  '天文': '天文学',
  '地质': '地质学',
  '气象': '气象学',
  '动物': '动物学',
  '密码': '密码学',
  '工程': '工程学',
  '司法': '司法科学',
  '药理': '药学',
  '驾驶（船）': '船',
  '驾驶（飞行器）': '飞行器',
  '驾驶（飞行器或船）': '飞行器',
};

final RegExp _colonRe = RegExp(r'[：:]');
final RegExp _leadingLike = RegExp(r'^如');
final RegExp _edgeParen = RegExp(r'^[（(]|[）)]$');
final RegExp _parenToEnd = RegExp(r'[（(].*$');

/// 把「子类写法」归一到技能库里的正式子类名；匹配不到返回 null
String? canonicalSub(List<Object?> subs, String? name) {
  if (name == null || name.isEmpty) return null;
  var s = name
      .trim()
      .replaceFirst(_leadingLike, '')
      .replaceAll(_edgeParen, '')
      .replaceFirst(_parenToEnd, '')
      .trim();
  if (s.isEmpty) return null;
  final names = subs.map((x) => jsStr(asMap(x)['name'])).toList();
  for (final n in names) {
    if (n == s) return n;
  }
  final mapped = subAlias[s];
  if (mapped != null) {
    for (final n in names) {
      if (n == mapped) return n;
    }
  }
  // 后缀差异：「生物」↔「生物学」；只允许前缀关系，避免误伤
  for (final n in names) {
    if (n.length >= 2 && s.length >= 2 && (n.startsWith(s) || s.startsWith(n))) return n;
  }
  return null;
}

final Map<String, String> name2id = _buildName2Id();

Map<String, String> _buildName2Id() {
  final m = <String, String>{};
  for (final s in cocSkills) {
    final nm = jsStr(s['name']);
    m[nm] = jsStr(s['id']);
    m[nm.replaceAll(_colonRe, '')] = jsStr(s['id']);
  }
  alias.forEach((k, v) => m[k] = v);
  return m;
}

/// 长名优先匹配（同长按插入顺序 —— JS 的 Array.sort 是稳定的，
/// Dart 的 List.sort 不稳定，所以显式带上原始下标做次级比较）
final List<String> nameKeys = _buildNameKeys();

List<String> _buildNameKeys() {
  final keys = name2id.keys.toList();
  final order = <String, int>{for (var i = 0; i < keys.length; i++) keys[i]: i};
  keys.sort((a, b) {
    final d = b.length - a.length;
    return d != 0 ? d : order[a]! - order[b]!;
  });
  return keys;
}

String? resolveSkillId(Object? name) {
  if (name == null) return null;
  var n = jsStr(name).trim().replaceAll(_colonRe, '');
  if (n.isEmpty) return null;
  final direct = name2id[n];
  if (direct != null) return direct;
  for (final k in nameKeys) {
    if (n.startsWith(k)) return name2id[k];
  }
  return null;
}

Map<String, Object?>? skillById(Object? id) {
  for (final s in cocSkills) {
    if (jsStr(s['id']) == jsStr(id)) return s;
  }
  return null;
}

/* ============================================================
 * 技能搜索索引
 * ------------------------------------------------------------
 * 曾经的搜索只比对技能「本身」的名字：
 *   · 组技能（格斗 / 射击 / 科学 / 技艺 / 驾驶 / 生存 / 学识 / 其他语言）
 *     只有组名进了索引，子类名完全没有 —— 搜「斗殴」「步枪」「拉丁语」
 *     会把整组直接过滤掉，什么都搜不到；
 *   · 技能库里「取悦」在职业数据里大量写作旧译「魅惑」，搜「魅惑」也会落空。
 * 这里把「组名 + 全部子类名 + 别名 + 分类 + 描述」合成一个可检索文本，
 * 组技能再额外支持「按子类名只列出命中的那个子类」。
 * ============================================================ */

/// 子类名 → 所属组技能 id
final Map<String, String> subToGroup = _buildSubToGroup();

Map<String, String> _buildSubToGroup() {
  final m = <String, String>{};
  for (final s in cocSkills) {
    if (jsTruthy(s['special'])) {
      for (final sub in asList(s['subskills'])) {
        m[jsStr(asMap(sub)['name'])] = jsStr(s['id']);
      }
    }
  }
  return m;
}

/// 与某技能 id 相关的全部中文别名
List<String> aliasesOf(Object? id) {
  final out = <String>[];
  alias.forEach((k, v) {
    if (v == jsStr(id)) out.add(k);
  });
  return out;
}

/// 一个技能定义（含组技能的全部子类）参与搜索的文本
String skillSearchText(Map<String, Object?>? def) {
  if (def == null) return '';
  var parts = <String>[
    jsStr(def['id']),
    jsStr(def['name']),
    jsStr(def['category']),
    jsStr(def['desc']),
  ];
  parts = parts + aliasesOf(def['id']);
  if (jsTruthy(def['special'])) {
    for (final s in asList(def['subskills'])) {
      final nm = jsStr(asMap(s)['name']);
      parts.add(nm);
      subAlias.forEach((k, v) {
        if (v == nm) parts.add(k);
      });
    }
  }
  return parts.join(' ').toLowerCase();
}

/// 关键词能否命中该技能定义（组技能：命中组名 或 任一子类名）
bool skillMatches(Map<String, Object?>? def, String? kw) {
  if (kw == null || kw.trim().isEmpty) return true;
  return skillSearchText(def).contains(kw.trim().toLowerCase());
}

/// 搜子类名时只列出命中的子类（避免搜「斗殴」却把 7 个格斗专攻全列出来）。
/// 命中组名 / 关键词为空 → 返回 null，表示「整组都要列」。
List<Object?>? matchedSubs(Map<String, Object?>? def, Object? kw) {
  if (def == null || !jsTruthy(def['special'])) return null;
  final k = jsStr(kw).trim().toLowerCase();
  if (k.isEmpty) return null;
  if (jsStr(def['name']).toLowerCase().contains(k)) return null; // 命中组名 → 全列
  final out = asList(def['subskills'])
      .where((s) => jsStr(asMap(s)['name']).toLowerCase().contains(k))
      .toList();
  return out.isEmpty ? null : out;
}

/// 一个「技能实例」（可能是组技能的某个专攻）参与搜索的文本。
/// 注意：专攻实例不并入同组其它子类名 —— 否则搜「斗殴」会把 7 个格斗专攻全列出来。
String instanceSearchText(String? id, String? sub) {
  final def = skillById(id);
  if (def == null) return jsStr(sub ?? id ?? '').toLowerCase();
  var parts = <String>[
    jsStr(def['id']),
    jsStr(def['name']),
    jsStr(def['category']),
    sub ?? '',
  ];
  parts = parts + aliasesOf(def['id']);
  if (sub != null && sub.isNotEmpty) {
    subAlias.forEach((k, v) {
      if (v == sub) parts.add(k);
    });
  } else if (jsTruthy(def['special'])) {
    for (final s in asList(def['subskills'])) {
      parts.add(jsStr(asMap(s)['name']));
    }
  }
  return parts.join(' ').toLowerCase();
}

/// 技能是否命中关键词（按实例：id + 专攻名）
bool instanceMatches(String? id, String? sub, Object? kw) {
  final k = jsStr(kw).trim();
  if (k.isEmpty) return true;
  return instanceSearchText(id, sub).contains(k.toLowerCase());
}

/* ---------- 顶层分割（忽略括号内） ---------- */
const String _openChars = '（(【';
const String _closeChars = '）)】';

List<String> splitTop(String text, String seps) {
  final out = <String>[];
  var buf = '';
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (_openChars.contains(ch)) {
      depth++;
    } else if (_closeChars.contains(ch)) {
      depth--;
    }
    if (depth == 0 && seps.contains(ch)) {
      if (buf.trim().isNotEmpty) out.add(buf.trim());
      buf = '';
    } else {
      buf += ch;
    }
  }
  if (buf.trim().isNotEmpty) out.add(buf.trim());
  return out;
}

const Map<String, int> cnNum = <String, int>{
  '一': 1,
  '两': 2,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
};

/// 解析本职技能描述
///
/// Requirement 形状（与 JS 逐字一致）：
///   { id, type:'fixed',  skill, sub }          固定技能
///   { id, type:'choice', count, pool:[{skill,sub,name}], label }   从池中选 count 项
///   { id, type:'free',   count, label }        任选 count 项
///   { id, type:'alt',    options:[Requirement], label }       或 — 择一
List<Map<String, Object?>> parseSkillText(Object? text) {
  if (text == null) return <Map<String, Object?>>[];
  var t = jsStr(text)
      /* 数据里有的职业用换行分行（甚至整段重复粘贴）。
         换行必须尽早变成逗号：JS 正则的 `.` 默认不匹配换行，
         留着它会让「N 项…」这类整行匹配直接失败，退化成「择一」并产出 undefined。 */
      .replaceAll(RegExp(r'\r?\n'), '，')
      // 句号不是分隔符，紧跟分隔符或位于行尾时去掉，避免混进选项名
      .replaceAll(RegExp(r'。\s*(?=[，,、；;]|$)'), '')
      .replaceAll(RegExp(r'[。；;]\s*$'), '')
      .replaceAll('任意其他', '任意')
      /* 「任两种其他学术或个人特长」「任意四项其他学术、时代或个人特长」
         本质都是「自由选择 N 项」，中间那些「或／、」不是择一、也不是分隔，
         先整体收成一个不含分隔符的说法，后面才不会被拆坏。 */
      .replaceAllMapped(
        RegExp(
          r'任(?:意)?\s*([一二两三四五六七八九十\d]+)\s*[种项]\s*(?:其他)?\s*'
          r'(?:学术|学识|个人|时代)(?:\s*[、，,或/]\s*(?:学术|学识|个人|时代))*\s*'
          r'(?:特长|技能)?[。]?',
        ),
        (m) => '任${m[1]}项个人或时代特长',
      )
      .replaceAll('可以使用', '')
      .replaceAll(RegExp(r'※[^，,]*'), '')
      .replaceAll('以及', '')
      .replaceAll(RegExp(r'(从)?(下面|以下)(中)?'), '')
      .replaceAll(RegExp(r'(最多)?(选取|选择|任选)(?=\s*[一二两三四五六七八九十\d]+\s*项)'), '')
      .trim();
  if (t.isEmpty) return <Map<String, Object?>>[];

  // 特例：自定义职业的自由描述
  final mFree = RegExp(r'^不多于\s*(\d+)\s*个本职技能').firstMatch(t);
  if (mFree != null) {
    final n = mFree[1]!;
    return <Map<String, Object?>>[
      <String, Object?>{
        'id': 'r0',
        'type': 'free',
        'count': jsParseInt(n) ?? 0,
        'label': '任选 $n 项本职技能',
      },
    ];
  }

  final parts = splitTop(t, '，,、');
  // 去重：部分职业数据里同一项被写了两次（如「士兵」的潜行），
  // 重复项会在界面上变成两个一模一样的「本职」条目。
  final seenPart = <String, bool>{};
  final reqs = <Map<String, Object?>>[];
  var idx = 0;

  for (final raw in parts) {
    final part = raw.trim();
    if (part.isEmpty || (seenPart[part] ?? false)) continue;
    seenPart[part] = true;
    final rs = parsePart(part);
    for (final r in rs) {
      if (r != null) reqs.add(assignId(r, idx++));
    }
  }
  return reqs;
}

Map<String, Object?> assignId(Map<String, Object?> r, int i) {
  r['id'] = 'r$i';
  if (!jsTruthy(r['label'])) r['label'] = reqLabel(r);
  return r;
}

String reqLabel(Map<String, Object?> r) {
  if (jsStr(r['type']) == 'fixed') {
    final s = skillById(r['skill']);
    if (s != null) {
      return '${s['name']}'
          '${jsTruthy(r['sub']) ? '（${r['sub']}）' : (jsTruthy(r['isGroup']) ? '（任选子类）' : '')}';
    }
    return jsStr(r['skill']);
  }
  if (jsStr(r['type']) == 'alt' && r['options'] != null) {
    return asList(r['options'])
        .map((oRaw) {
          final o = asMap(oRaw);
          if (oRaw != null &&
              (jsTruthy(o['skill']) || jsStr(o['type']) == 'fixed')) {
            final d = skillById(o['skill']);
            return '${d != null ? d['name'] : jsStr(o['skill'])}'
                '${jsTruthy(o['sub']) ? '（${o['sub']}）' : (jsTruthy(o['isGroup']) ? '（任选子类）' : '')}';
          }
          // 择一项里也可能是「自由选择 / 组技能任选」这类没有 skill 的项。
          // 老实现直接读 o.skill → undefined，界面上就出现「undefined 或 undefined」。
          final lbl = o['label'] ?? o['raw'];
          return jsTruthy(lbl) ? jsStr(lbl) : '自由选择';
        })
        .join(' 或 ');
  }
  return jsStr(r['label']);
}

final RegExp _anyWord = RegExp(r'^(任一|任意|任选|任何|任意一个|任意一种)');
final RegExp _nItems = RegExp(
  r'^(任(?:意)?)?\s*([一二两三四五六七八九十\d]+)\s*[种项]\s*(.*)$',
);
final RegExp _nameParen = RegExp(r'^([^（(]*)[（(]([^）)]*)[）)]\s*(.*)$');
final RegExp _colonBody = RegExp(r'^[：:]\s*(.+)$');
final RegExp _skillNameParen = RegExp(r'^([^（(]+)[（(]([^）)]*)[）)]\s*(.*)$');

/// 解析单个顶层片段
/// 顺序很重要：先处理「N项」整体，避免「个人或时代」被误当作择一
List<Map<String, Object?>?> parsePart(String part) {
  final p = part.trim().replaceFirst(RegExp(r'^[：:]\s*'), '');
  if (p.isEmpty) return <Map<String, Object?>?>[null];

  // ---- 1) 「(任意)N项 …」 / 「任N种 …」 ----
  // 前缀允许只写「任」，量词允许「种」——数据里两种写法都有
  final m = _nItems.firstMatch(p);
  if (m != null) {
    // 对应 `CN_NUM[m[2]] || parseInt(m[2], 10) || 1`
    final cnVal = cnNum[m[2]] ?? 0;
    final arVal = jsParseInt(m[2]) ?? 0;
    final cnt = cnVal != 0 ? cnVal : (arVal != 0 ? arVal : 1);
    final rest = (m[3] ?? '').trim();
    final any = jsTruthy(m[1]);

    // 1a) 后接「名称（池）」
    final mm = _nameParen.firstMatch(rest);
    if (mm != null) {
      final catName = (mm[1] ?? '').trim();
      final inner = (mm[2] ?? '').trim();
      var label = '${any ? '任意' : ''}${num2cn(cnt)}项$catName';
      // 「如…」是举例提示，不作为限定池
      if (!inner.startsWith('如')) {
        final pool = buildPool(inner);
        if (pool.length >= 2) {
          return <Map<String, Object?>?>[
            <String, Object?>{
              'type': 'choice',
              'count': cnt,
              'pool': pool,
              'label': label,
            },
          ];
        }
        if (pool.length == 1) {
          return <Map<String, Object?>?>[
            <String, Object?>{
              'type': 'fixed',
              'skill': pool[0]['skill'],
              'sub': pool[0]['sub'],
              'weight': cnt,
            },
          ];
        }
      }
      if (inner.isNotEmpty) label += '（$inner）';
      return <Map<String, Object?>?>[
        <String, Object?>{'type': 'free', 'count': cnt, 'label': label},
      ];
    }

    // 1b) 后接「：具体技能」或「：（池）」
    final m2 = _colonBody.firstMatch(rest);
    if (m2 != null) {
      final inner0 = (m2[1] ?? '').trim();
      final pool3 = buildPool(inner0.replaceAll(_edgeParen, ''));
      if (pool3.length >= 2) {
        return <Map<String, Object?>?>[
          <String, Object?>{
            'type': 'choice',
            'count': cnt,
            'pool': pool3,
            'label': '${any ? '任意' : ''}${num2cn(cnt)}项技能',
          },
        ];
      }
      final sid2 = resolveSkillId(inner0);
      if (sid2 != null) {
        return <Map<String, Object?>?>[
          <String, Object?>{
            'type': 'fixed',
            'skill': sid2,
            'sub': null,
            'weight': cnt,
          },
        ];
      }
    }

    // 1c) 纯自由选择
    return <Map<String, Object?>?>[
      <String, Object?>{
        'type': 'free',
        'count': cnt,
        'label':
            '${any ? '任意' : ''}${num2cn(cnt)}项${rest.isNotEmpty ? rest : '技能'}',
      },
    ];
  }

  // ---- 2) 「A 或 B」 择一（splitTop 已忽略括号内） ----
  final alts = splitTop(p, '或');
  if (alts.length > 1) {
    final options = <Object?>[];
    for (final a in alts) {
      final sub = parseSingle(a.trim());
      if (sub != null && jsStr(sub['type']) != 'alt') options.add(sub);
    }
    if (options.length > 1) {
      final opt = <String, Object?>{'type': 'alt', 'options': options};
      opt['label'] = reqLabel(opt);
      return <Map<String, Object?>?>[opt];
    }
    if (options.length == 1) return <Map<String, Object?>?>[asMap(options[0])];
  }

  // ---- 3) 单项 ----
  return <Map<String, Object?>?>[parseSingle(p)];
}

/// 解析不可再分的单项技能
Map<String, Object?>? parseSingle(String part) {
  final p = part.trim().replaceFirst(RegExp(r'^[：:]\s*'), '');
  if (p.isEmpty) return null;

  // 组技能 + 括号
  final m4 = _skillNameParen.firstMatch(p);
  if (m4 != null) {
    final base = (m4[1] ?? '').trim();
    final inner = (m4[2] ?? '').trim();
    final tail = (m4[3] ?? '').trim();
    final sid = resolveSkillId(base);
    if (sid != null) {
      final def = skillById(sid);
      final subs = (def != null && jsTruthy(def['special']))
          ? asList(def['subskills'])
          : <Object?>[];

      // 「如…」举例 → 视为自由选择并保留提示
      if (inner.startsWith('如')) {
        final pool2 = buildPool(inner.replaceFirst(RegExp(r'^如'), ''));
        if (pool2.length >= 2) {
          return <String, Object?>{
            'type': 'choice',
            'count': 1,
            'pool': pool2,
            'label': '一项${def!['name']}',
          };
        }
        return <String, Object?>{
          'type': 'free',
          'count': 1,
          'label': '一项${def!['name']}（$inner）',
        };
      }

      // 「任一 / 任意」→ 整组任选
      if (_anyWord.hasMatch(inner)) {
        if (subs.isNotEmpty) {
          return <String, Object?>{
            'type': 'choice',
            'count': 1,
            'pool': subs
                .map(
                  (s) => <String, Object?>{
                    'skill': sid,
                    'sub': jsStr(asMap(s)['name']),
                    'name': jsStr(asMap(s)['name']),
                  },
                )
                .toList(),
            'label': '一项${def!['name']}',
          };
        }
        return <String, Object?>{
          'type': 'fixed',
          'skill': sid,
          'sub': null,
          'isGroup': true,
        };
      }

      if (subs.isNotEmpty) {
        final subList = splitTop(inner, '、,，');
        // 子类名做归一化匹配（制药→药学、拉丁文→拉丁语、生物→生物学…）
        final resolved = <String>[];
        for (final s in subList) {
          final c = canonicalSub(subs, s);
          if (c != null && !resolved.contains(c)) resolved.add(c);
        }
        if (resolved.length == subList.length && resolved.length == 1) {
          return <String, Object?>{
            'type': 'fixed',
            'skill': sid,
            'sub': resolved[0],
          };
        }
        if (resolved.length > 1) {
          final opts = resolved
              .map(
                (s) => <String, Object?>{
                  'type': 'fixed',
                  'skill': sid,
                  'sub': s,
                },
              )
              .toList();
          final alt = <String, Object?>{'type': 'alt', 'options': opts};
          alt['label'] = reqLabel(alt);
          return alt;
        }
        // 未识别子类名 → 整组
        return <String, Object?>{
          'type': 'fixed',
          'skill': sid,
          'sub': null,
          'isGroup': true,
        };
      }
      return <String, Object?>{
        'type': 'fixed',
        'skill': sid,
        'sub': tail.isNotEmpty ? tail : null,
      };
    }
  }

  // 纯技能名
  final sid5 = resolveSkillId(p);
  if (sid5 != null) {
    final d5 = skillById(sid5);
    if (d5 != null && jsTruthy(d5['special'])) {
      // 组技能（技艺/科学/格斗/射击/驾驶/生存/外语）→ 整组开放
      return <String, Object?>{
        'type': 'fixed',
        'skill': sid5,
        'sub': null,
        'isGroup': true,
      };
    }
    return <String, Object?>{'type': 'fixed', 'skill': sid5, 'sub': null};
  }

  // 无法识别 → 自由选择，保留原文供提示
  return <String, Object?>{'type': 'free', 'count': 1, 'label': p, 'raw': p};
}

String num2cn(int n) {
  const map = <int, String>{
    1: '一',
    2: '两',
    3: '三',
    4: '四',
    5: '五',
    6: '六',
    7: '七',
    8: '八',
  };
  return map[n] ?? '$n';
}

List<Map<String, Object?>> buildPool(String text) {
  final pool = <Map<String, Object?>>[];
  final seen = <String, bool>{};
  for (var s in splitTop(text, '、,，或/')) {
    s = s
        .replaceFirst(RegExp(r'^如'), '')
        .replaceFirst(RegExp(r'等$'), '')
        .trim();
    if (s.isEmpty) continue;
    final id = resolveSkillId(s);
    if (id == null || (seen[id] ?? false)) continue; // 去重：同一技能被写两遍只算一项
    seen[id] = true;
    final def = skillById(id);
    // 用技能库的正式名，保证选项文字和技能列表里看到的一致
    // （数据写「魅惑」、库里叫「取悦」，两边统一显示后者）
    pool.add(<String, Object?>{
      'skill': id,
      'sub': null,
      'name': def != null ? def['name'] : s,
    });
  }
  return pool;
}

/* ---------- 职业属性点公式 ---------- */
int evalFormula(Object? formula, Map<String, Object?> attrs) {
  if (formula == null) return 0;
  final f = jsStr(formula)
      .replaceAll(RegExp(r'[＋]'), '+')
      .replaceAll(RegExp(r'[×✕xX*]'), '*')
      .trim();
  if (f.isEmpty) return 0;
  final terms = f.split('+');
  var total = 0;
  var ok = false;
  final termRe = RegExp(r'^(.+?)\s*\*\s*(\d+)$');
  for (var term in terms) {
    term = term.trim();
    if (term.isEmpty) continue;
    final m = termRe.firstMatch(term);
    if (m == null) continue;
    final names = m[1]!.split('或');
    final mult = jsParseInt(m[2]) ?? 0;
    final vals = <int>[];
    for (final n in names) {
      final k = attrByName(n);
      if (k != null) vals.add(jsNum(attrs[k]));
    }
    if (vals.isEmpty) continue;
    total += jsMax(vals) * mult;
    ok = true;
  }
  return ok ? total : 0;
}

/* ============================================================
 * 职业模型 API
 * ============================================================ */
Map<String, Object?>? getOccupationById(Object? id) {
  for (final o in cocOccupations) {
    if (jsStr(o['id']) == jsStr(id)) return o;
  }
  return null;
}

List<Map<String, Object?>> listOccupations() => cocOccupations;

/// `{reqId: parsedRequirements}` —— 与原码的 `var cache = {}` 对应
final Map<String, List<Map<String, Object?>>> _reqCache =
    <String, List<Map<String, Object?>>>{};

/// 取得该职业的结构化技能要求（含用户已选项）
List<Map<String, Object?>> getRequirements(Character character) {
  final occ = getOccupationById(character.occupationId);
  if (occ == null) return <Map<String, Object?>>[];
  final key = jsStr(occ['id']);
  if (!_reqCache.containsKey(key)) {
    _reqCache[key] = parseSkillText(occ['skillText']);
  }
  final picked = character.occupationPicks;
  // 深拷贝并附加已选状态
  return _reqCache[key]!.map((r) {
    final c = _deepCopyMap(r);
    final v = picked[jsStr(c['id'])];
    c['picked'] = jsTruthy(v) ? v : <Object?>[];
    return c;
  }).toList();
}

/// 组技能「没指定专攻」时该算哪个专攻。
///
/// ⚠️ 这是「一张卡冒出 40 项本职技能」的根治点。
/// 职业原文里经常只写「格斗」「技艺」「射击」而不点名专攻，
/// 早先的实现把整组（技艺 30 个专攻、格斗 7 个）全部标成本职，
/// 于是「厨师」「技师」这类卡的本职技能能到 40-51 项 ——
/// 界面上根本看不完，点数也被摊得极薄。
/// 规则书里这种写法是「任选一个专攻」，所以只该算**一个**。
///
/// 取值顺序（保证稳定，不能随机 —— 校验器与界面会反复调用）：
///   ① 已经选过就用选过的（occupationPicks）
///   ② 职业原文点名的专攻（「手艺（烹饪）」→ 烹饪）
///   ③ 否则取该组第一个专攻
String groupSubFor(
  Character? character,
  Map<String, Object?>? r,
  Map<String, Object?>? def,
) {
  final subs = def == null ? <Object?>[] : asList(def['subskills']);
  if (subs.isEmpty) return '';

  final picked = asList(r?['picked']);
  for (final pRaw in picked) {
    final p = asMap(pRaw);
    if (jsTruthy(p['sub'])) return jsStr(p['sub']);
  }

  final occ = getOccupationById(character?.occupationId);
  final text = '${jsStr(occ?['skillText'])}　${jsStr(occ?['desc'])}';
  for (final s in subs) {
    final n = jsStr(asMap(s)['name']);
    if (n.isNotEmpty && text.contains(n)) return n;
  }
  return jsStr(asMap(subs.first)['name']);
}

/// 标记一个技能（组技能会自动收敛到单个专攻）
void markReq(
  Map<String, bool> set,
  Character? character,
  Map<String, Object?>? reqOrItem,
  Object? skillId,
  Object? sub,
  bool on,
) {
  if (skillId == null) return;
  final sid = jsStr(skillId);
  if (sid.isEmpty) return;
  final def = skillById(sid);
  if (def != null && jsTruthy(def['special']) && !jsTruthy(sub)) {
    final one = groupSubFor(character, reqOrItem, def);
    set['$sid::$one'] = on;
    return;
  }
  set[jsTruthy(sub) ? '$sid::$sub' : sid] = on;
}

/// 该职业的全部可选技能池（用于判断某技能是否为"本职"）
Map<String, bool> occupationalSet(Character character) {
  final set = <String, bool>{};
  final occ = getOccupationById(character.occupationId);
  if (occ == null) return set;
  final reqs = getRequirements(character);
  for (final r in reqs) {
    final type = jsStr(r['type']);
    if (type == 'fixed') {
      markReq(set, character, r, r['skill'], r['sub'], true);
    } else if (type == 'choice') {
      final chosen = asList(r['picked']);
      if (chosen.isNotEmpty) {
        for (final pRaw in chosen) {
          final p = asMap(pRaw);
          markReq(set, character, r, p['skill'], p['sub'], true);
        }
      } else {
        for (final pRaw in asList(r['pool'])) {
          final p = asMap(pRaw);
          markReq(set, character, r, p['skill'], p['sub'], true);
        }
      }
    } else if (type == 'alt') {
      final ch = asList(r['picked']);
      if (ch.isNotEmpty) {
        final c0 = asMap(ch.first);
        markReq(set, character, r, c0['skill'], c0['sub'], true);
      } else {
        for (final oRaw in asList(r['options'])) {
          final o = asMap(oRaw);
          markReq(set, character, r, o['skill'], o['sub'], true);
        }
      }
    } else if (type == 'free') {
      for (final pRaw in asList(r['picked'])) {
        final p = asMap(pRaw);
        markReq(set, character, r, p['skill'], p['sub'], true);
      }
    }
  }
  return set;
}

void markSkill(Map<String, bool> set, Object? skillId, Object? sub, bool on) {
  /* 注意：这里**不再**把组技能整组展开。
     需要「组技能收敛到一个专攻」时请用 markReq()，它要用到角色上下文。 */
  if (skillId == null) return;
  final sid = jsStr(skillId);
  if (sid.isEmpty) return;
  set[jsTruthy(sub) ? '$sid::$sub' : sid] = on;
}

/// 取「生效属性」（含年龄调整与教育进步增益）
///
/// 原码在 Engine 未就绪时回落到原始属性；Dart 侧直接调 rules_coc7 的
/// 同一个函数 —— 它算出来的值就是 `Engine.effAttrs()` 返回的那份
/// （后者只是多了一层指纹缓存）。这样可以避免 occupation → engine 的循环 import。
Map<String, Object?> attrsFor(Character? character) {
  if (character == null) return <String, Object?>{};
  return effectiveAttrs(character);
}

/// 职业技能点总数（按生效属性算：EDU 被教育进步检定抬高后，点数要跟着涨）
///
/// ⚠️ 这里**不再**有「点数总额上限」。
/// 早先的 AI 设置把「职业技能点数上限」理解成「压缩整个点数池」，
/// 于是 total 变小、界面显示「职业点 80/280」，看着像有 200 点没用完。
/// 现在的语义是**每个技能最终值**的上限（见 skillCapOf），
/// 点数池始终是规则算出的全额 —— 玩家设上限不会凭空少掉点数，
/// 只是每一项最多点到那个值。
Map<String, Object?> occupationPoints(Character character) {
  final occ = getOccupationById(character.occupationId);
  final total = occ != null
      ? evalFormula(occ['attrFormula'], attrsFor(character))
      : 0;
  final used = usedOccPoints(character);
  return <String, Object?>{
    'total': total,
    'used': used,
    'remain': total - used,
  };
}

int usedOccPoints(Character character) {
  var a = 0;
  for (final sRaw in character.skills) {
    final s = asMap(sRaw);
    a += jsNum(s['occ']) + jsNum(s['creditOcc']);
  }
  return a;
}

/// 兴趣技能点总数 = INT × 2
Map<String, Object?> interestPoints(Character character) {
  final attrs = attrsFor(character);
  final base = jsNum(attrs['int']);
  final total = base * 2;
  var used = 0;
  for (final sRaw in character.skills) {
    used += jsNum(asMap(sRaw)['int']);
  }
  return <String, Object?>{
    'total': total,
    'used': used,
    'remain': total - used,
  };
}

Map<String, Object?> pointsFull(Character character) {
  final o = getOccupationById(character.occupationId);
  final attrs = attrsFor(character);
  return <String, Object?>{
    'occ': o != null ? evalFormula(o['attrFormula'], attrs) : 0,
    'int': jsNum(attrs['int']) * 2,
  };
}

/* ---------- 职业搜索 ---------- */
final Map<String, String> _occSearchCache = <String, String>{};

void collectReqSkillIds(Map<String, Object?>? r, Map<String, bool> out) {
  if (r == null) return;
  if (jsTruthy(r['skill'])) out[jsStr(r['skill'])] = true;
  for (final pRaw in asList(r['pool'])) {
    final p = asMap(pRaw);
    if (jsTruthy(p['skill'])) out[jsStr(p['skill'])] = true;
  }
  for (final xRaw in asList(r['options'])) {
    collectReqSkillIds(asMap(xRaw), out);
  }
}

/// 职业的可检索文本。
/// 除了名称 / 描述 / 原文，还把「解析后的技能名」与「技能库里这些技能的
/// 正式名 + 全部子类名」并进来 —— 职业数据写「魅惑」、技能库叫「取悦」，
/// 只比对原文的话，搜「取悦」就找不到任何一个需要社交技能的职业。
String searchTextOfOccupation(Map<String, Object?> o) {
  final cached = _occSearchCache[jsStr(o['id'])];
  if (cached != null) return cached;
  final parts = <String>[
    jsStr(o['name']),
    jsStr(o['desc']),
    jsStr(o['skillText']),
    jsStr(o['attrFormula']),
    jsStr(o['creditText']),
  ];
  final ids = <String, bool>{};
  for (final r in parseSkillText(o['skillText'])) {
    parts.add(reqLabel(r));
    collectReqSkillIds(r, ids);
  }
  ids.forEach((id, _) {
    final def = skillById(id);
    if (def != null) parts.add(skillSearchText(def)); // 组技能 → 连子类名一起进索引
  });
  final text = parts.join(' ').toLowerCase();
  _occSearchCache[jsStr(o['id'])] = text;
  return text;
}

/// 按关键词搜索职业（名称 / 描述 / 技能原文 / 解析后的技能名与别名的统一索引）
List<Map<String, Object?>> searchOccupations(Object? kw) {
  final k = jsStr(kw).trim();
  if (k.isEmpty) return cocOccupations;
  final low = k.toLowerCase();
  return cocOccupations
      .where((o) => searchTextOfOccupation(o).contains(low))
      .toList();
}

/* ============================================================
 * 职业相关的校验器（JS 里挂在 `COC7.validators` 上，见文件头说明）
 * ============================================================ */

/// 职业限定技能选择是否完成
List<Map<String, Object?>> validateOccupationChoices(Character c) {
  var errs = <Map<String, Object?>>[];
  if (c.occupationId.isEmpty) return errs;
  final req = getRequirements(c);
  for (final r in req) {
    final picked = asList(r['picked']);
    final count = jsNum(r['count']);
    if (jsStr(r['type']) == 'choice' && picked.length < count) {
      errs.add(<String, Object?>{
        'step': 2,
        'target': 'occ_${r['id']}',
        'text': '${r['label']} 还需选择 ${count - picked.length} 项',
      });
    }
    if (jsStr(r['type']) == 'free' && picked.length < count) {
      errs.add(<String, Object?>{
        'step': 2,
        'target': 'occ_${r['id']}',
        'text': '${r['label']} 还需指定 ${count - picked.length} 项',
      });
    }
  }
  errs = errs + duplicatePicks(c);
  return errs;
}

/// 技能点是否超额
List<Map<String, Object?>> validateSkillPoints(Character c) {
  final errs = <Map<String, Object?>>[];
  final occ = occupationPoints(c);
  final itr = interestPoints(c);
  if (jsNum(occ['used']) > jsNum(occ['total'])) {
    errs.add(<String, Object?>{
      'step': 4,
      'target': 'occPoints',
      'text':
          '职业技能点超出 ${jsNum(occ['used']) - jsNum(occ['total'])} 点'
          '（已用 ${occ['used']}/${occ['total']}）',
    });
  }
  if (jsNum(itr['used']) > jsNum(itr['total'])) {
    errs.add(<String, Object?>{
      'step': 4,
      'target': 'interestPoints',
      'text':
          '兴趣技能点超出 ${jsNum(itr['used']) - jsNum(itr['total'])} 点'
          '（已用 ${itr['used']}/${itr['total']}）',
    });
  }
  return errs;
}

/// 技能是否超过上限（本职走本职上限，非本职走兴趣上限）
List<Map<String, Object?>> validateSkillCap(Character c) {
  final errs = <Map<String, Object?>>[];
  final occSet = occupationalSet(c);
  for (final sRaw in c.skills) {
    final s = asMap(sRaw);
    final cap = skillCapOf(c, s, occSet);
    if (jsNum(s['total']) > cap) {
      final isOcc =
          (occSet[jsStr(s['key'])] ?? false) ||
          (occSet[jsStr(s['id'])] ?? false);
      errs.add(<String, Object?>{
        'step': 4,
        'target': 'skill_${s['key']}',
        'text':
            '技能「${s['name']}」达到 ${s['total']}，'
            '超过${isOcc ? '本职' : '兴趣'}技能上限 $cap%',
      });
    }
  }
  return errs;
}

/// 信用评级是否已分配且在职业允许范围内，且其占用的职业点未超额
List<Map<String, Object?>> validateCreditRating(Character c) {
  final errs = <Map<String, Object?>>[];
  if (c.occupationId.isEmpty) return errs;
  final occ = getOccupationById(c.occupationId);
  if (occ == null || occ['creditMin'] == null || occ['creditMax'] == null) return errs;
  final creditMin = jsNum(occ['creditMin']);
  final creditMax = jsNum(occ['creditMax']);
  final cr = jsNum(c.assets['creditRating']);
  if (cr == 0) {
    errs.add(<String, Object?>{
      'step': 3,
      'target': 'creditRating',
      'text': '尚未分配信用评级（该职业允许 $creditMin-$creditMax）',
    });
    return errs;
  }
  if (cr < creditMin || cr > creditMax) {
    errs.add(<String, Object?>{
      'step': 3,
      'target': 'creditRating',
      'text': '信用评级 $cr 超出该职业允许范围 $creditMin-$creditMax',
    });
    return errs;
  }
  // 信用评级由职业点数购买，需保证职业点总量未被突破
  final pts = occupationPoints(c);
  if (jsNum(pts['used']) > jsNum(pts['total'])) {
    errs.add(<String, Object?>{
      'step': 4,
      'target': 'occPoints',
      'text':
          '职业技能点超出 ${jsNum(pts['used']) - jsNum(pts['total'])} 点（信用评级也占用职业点数）',
    });
  }
  return errs;
}

/* ============================================================
 * 「任选 X 项」的去重校验
 *
 * 规则书要求任选的技能必须是**尚未拥有**的：
 *   ① 同一个任选块里不能重复选同一个技能（选两次「游泳」= 白占一个名额）
 *   ② 不能与已经获得的本职技能重复（「历史」既是本职又当特长 = 重复）
 *   ③ 组技能的不同专攻算不同技能，但同一个专攻不能选两次
 *
 * 界面上已经做了过滤（steps-b.js 的 pickFree），这里是数据层的兜底：
 * 老存档里可能已经存在重复项，界面绕过去也能查出来。
 * ============================================================ */
List<Map<String, Object?>> duplicatePicks(Character c) {
  final errs = <Map<String, Object?>>[];
  final picks = c.occupationPicks;
  final reqs = getRequirements(c);

  /* ⚠️ 只在「任选（free）」类型的块之间查重。
     c.occupationPicks 这一个字典里同时存着两类内容：
       · choice 择一项（用户或 preset 选中的那一个）
       · free   任选 N 项  ← 只有这一类之间才需要「不能重复」
     preset.fillOccupationPicks() 会把两类一起写进这个字典，
     早先的校验不分类型，于是两个 choice 块选到同一个技能就判成不合格，
     把 12 张彩蛋卡判成「职业限定技能选择完成」不合格。 */
  final freeIds = <String, bool>{};
  for (final r in reqs) {
    if (jsStr(r['type']) == 'free') freeIds[jsStr(r['id'])] = true;
  }
  /* 没有任何 free 块时无从检查，直接放过 —— 避免误伤正常卡 */
  if (freeIds.isEmpty) return errs;

  /* 「职业规则直接给定」的本职技能：fixed 全部 + choice/alt 里已选中的那一个 */
  final granted = <String, bool>{};
  for (final r in reqs) {
    final type = jsStr(r['type']);
    if (type == 'fixed') {
      _markOnce(granted, r['skill'], r['sub']);
    } else if (type == 'choice' || type == 'alt') {
      for (final pRaw in asList(r['picked'])) {
        final p = asMap(pRaw);
        _markOnce(granted, p['skill'], p['sub']);
      }
    }
  }

  final seen = <String, String>{};

  void addErr(String rid, String text) {
    final target = 'occ_$rid';
    for (final e in errs) {
      if (e['text'] == text && e['target'] == target) return;
    }
    errs.add(<String, Object?>{'step': 2, 'target': target, 'text': text});
  }

  freeIds.forEach((rid, _) {
    final arr = asList(picks[rid]);
    final inBlock = <String, bool>{};
    for (final pRaw in arr) {
      final p = asMap(pRaw);
      // ⚠️ 键必须按 JS 的 `(p.skill||'') + '|' + (p.sub||'')` 归一：
      // 缺失的 sub 是**空串**，不是字符串 'null' —— 否则「fixed 直接给定」的
      // 技能（r.sub 为 undefined）与真正带专攻的条目永远对不上，
      // 该类重复就查不出来（表现为预设卡少重试一次、卡面跑到另一个 seed 上）。
      final key = '${_keyPart(p['skill'])}|${_keyPart(p['sub'])}';
      final label = jsTruthy(p['name'])
          ? jsStr(p['name'])
          : (jsTruthy(p['skill']) ? jsStr(p['skill']) : '未知技能');

      if (inBlock[key] ?? false) {
        addErr(rid, '「$label」被重复选择了 —— 每个技能在该职业里只能选一次');
      }
      inBlock[key] = true;

      if (seen.containsKey(key)) {
        addErr(rid, '「$label」与其他已选特长重复（${seen[key]}），不能重复占用名额');
      }
      seen[key] = label;

      // 与「职业规则直接给定的」本职技能冲突
      if (granted[key] ?? false) {
        addErr(rid, '「$label」已经是本职技能，不能再作为个人或时代特长');
      }
    }
  });
  return errs;
}

/* 组技能（如「格斗」开放了「格斗（斗殴）」）要算进已拥有集合 */
void _markOnce(Map<String, bool> map, Object? skill, Object? sub) {
  if (!jsTruthy(skill)) return;
  map['${_keyPart(skill)}|${_keyPart(sub)}'] = true;
  final def = skillById(skill);
  if (def != null && jsTruthy(def['special']) && !jsTruthy(sub)) {
    for (final sRaw in asList(def['subskills'])) {
      map['${_keyPart(skill)}|${_keyPart(asMap(sRaw)['name'])}'] = true;
    }
  }
}

/// JS `(v || '')` —— 缺失 / null / 空串统一成空串（去重键的组成部分）
String _keyPart(Object? v) => jsTruthy(v) ? jsStr(v) : '';

Map<String, Object?> _deepCopyMap(Map<String, Object?> m) {
  final out = <String, Object?>{};
  m.forEach((k, v) => out[k] = _deepCopy(v));
  return out;
}

Object? _deepCopy(Object? v) {
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, val) => out[jsStr(k)] = _deepCopy(val));
    return out;
  }
  if (v is List) return v.map(_deepCopy).toList();
  return v;
}
