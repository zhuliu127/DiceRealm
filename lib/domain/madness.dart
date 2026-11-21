// ============================================================
// madness.dart — 疯狂状态管理
// 逐行对应 `core/madness.js`（427 行，`CocMadness`）
//
// 跑团中角色会逐条掷出「临时疯狂」（Bout of Sanity）等发作状态。
// v2.1.9（用户第 3 项）疯狂表体系重做 —— 规则书的「疯狂表」实为**两张**：
//   即时症状表（发作时，掷 1D10）与 总结症状表（独处 / 事后，掷 1D10）。
//   两表各 10 条，第 9 / 10 条指向 100 条的恐惧症 / 狂躁症子表（再掷 1D100）。
//
// 数据落在 character.madness（数组），每条：
//   { id, type, name, en, desc, rounds, permanent, bg, sum, at }
//     type       'phobia'（恐惧症）| 'mania'（狂躁症）| 'bout'（1-8 发作行为）
//     rounds     剩余轮数；permanent 为 true 时忽略此字段
//     permanent  true = 不随轮次消失（永久疯狂或背景症状）
//     bg         true = 来自角色背景（显示「（背景症状）」）
// ============================================================

import 'character.dart';
import 'data/madness.dart';
import 'js_compat.dart';

List<Map<String, Object?>> pool(String? type) {
  return (type == 'mania'
          ? asList(cocMadnessTable['manias'])
          : asList(cocMadnessTable['phobias']))
      .map(asMap)
      .toList();
}

String labelOf(Object? type) {
  if (type == 'mania') return '狂躁症';
  if (type == 'bout') return '疯狂发作';
  return '恐惧症';
}

/// `'m' + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36)`
String uid() {
  return 'm${(nowMillis()).toRadixString(36)}${(nowRng() * 1e6).floor().toRadixString(36)}';
}

int poolSize(Object? type) => pool(jsStr(type)).length;

Map<String, Object?> _tag(String type, Map<String, Object?> x) =>
    <String, Object?>{
      'type': type,
      'name': x['name'],
      'en': x['en'],
      'desc': x['desc'],
      'no': x['no'],
    };

/// 全池（两种症状混在一起随机，规则书本来就是混着掷的）
List<Map<String, Object?>> allSymptoms() {
  return <Map<String, Object?>>[
    ...asList(cocMadnessTable['phobias']).map((x) => _tag('phobia', asMap(x))),
    ...asList(cocMadnessTable['manias']).map((x) => _tag('mania', asMap(x))),
  ];
}

/* ============================================================
 * v2.1.9（用户第 3 项）：**疯狂表体系重做** ——
 * 规则书的「疯狂表」实为两张：**即时症状表**（发作时，掷 1D10）
 * 与**总结症状表**（独处 / 事后，掷 1D10）。两表都是 10 条，
 * 第 9、10 条指向 100 条的恐惧症 / 狂躁症子表（再掷 1D100）。
 *
 *   即时症状（掷 1D10；有同伴在场时按轮扮演，各持续 1D10 轮）：
 *     1 失忆  2 假性残疾  3 暴力倾向  4 偏执妄想  5 人际依赖
 *     6 昏厥  7 惊慌逃窜  8 歇斯底里  9 恐惧症  10 躁狂症
 *   总结症状（独自一人时，KP 快进陈述结果，约 1D10 小时后恢复神志）：
 *     1 失忆  2 被劫  3 遍体鳞伤  4 暴力  5 思想与信念
 *     6 重要之人  7 被收容  8 惊慌逃窜  9 恐惧症  10 躁狂症
 *
 * 规则书里 1-8 是**行为层面的结果**（不产生具体恐惧症/狂躁症），
 * 只有 1/5 的概率发展出新的恐惧症（9）或狂躁症（10）。
 * 这条规则贯穿所有「随机疯狂」路径：跑团 SAN Check 结算、
 * 车卡「掷疯狂状态」、随机角色池预设卡、彩蛋卡、AI 生卡。
 * ============================================================ */

/// 即时症状表（发作时，掷 1D10）。no 9 / 10 的 link 指向 100 条子表。
const List<Map<String, Object?>> boutTable = <Map<String, Object?>>[
  <String, Object?>{
    'no': 1,
    'name': '失忆',
    'en': 'Amnesia',
    'desc': '不知何时到的这里。',
  },
  <String, Object?>{
    'no': 2,
    'name': '假性残疾',
    'en': 'Psychosomatic Disability',
    'desc': '心因性失明 / 耳聋 / 失能。',
  },
  <String, Object?>{
    'no': 3,
    'name': '暴力倾向',
    'en': 'Violence',
    'desc': '对四周无差别破坏。',
  },
  <String, Object?>{
    'no': 4,
    'name': '偏执妄想',
    'en': 'Paranoia',
    'desc': '人人与我作对。',
  },
  <String, Object?>{
    'no': 5,
    'name': '人际依赖',
    'en': 'Interpersonal Dependency',
    'desc': '把同伴错认成重要之人。',
  },
  <String, Object?>{'no': 6, 'name': '昏厥', 'en': 'Fainting', 'desc': '立即昏倒。'},
  <String, Object?>{
    'no': 7,
    'name': '惊慌逃窜',
    'en': 'Flee in Panic',
    'desc': '不择手段逃离。',
  },
  <String, Object?>{
    'no': 8,
    'name': '歇斯底里',
    'en': 'Hysteria',
    'desc': '狂笑 / 哭泣 / 尖叫。',
  },
  <String, Object?>{
    'no': 9,
    'name': '恐惧症',
    'en': 'Phobia',
    'link': 'phobia',
    'desc': '掷 1D100 从恐惧症表（100 条）决定具体症状。',
  },
  <String, Object?>{
    'no': 10,
    'name': '躁狂症',
    'en': 'Mania',
    'link': 'mania',
    'desc': '掷 1D100 从狂躁症表（100 条）决定具体症状。',
  },
];

/// 总结症状表（独处 / 事后，掷 1D10）。no 9 / 10 同样指向 100 条子表。
const List<Map<String, Object?>> summaryTable = <Map<String, Object?>>[
  <String, Object?>{
    'no': 1,
    'name': '失忆',
    'en': 'Amnesia',
    'desc': '身在陌生地点，连自己是谁都不记得。',
  },
  <String, Object?>{
    'no': 2,
    'name': '被劫',
    'en': 'Robbed',
    'desc': '财物遭劫，宝贵之物掷幸运决定是否幸免。',
  },
  <String, Object?>{
    'no': 3,
    'name': '遍体鳞伤',
    'en': 'Battered',
    'desc': 'HP 减半（不算重伤）。',
  },
  <String, Object?>{
    'no': 4,
    'name': '暴力',
    'en': 'Violence',
    'desc': '对谁施暴、是否致死由 KP 决定。',
  },
  <String, Object?>{
    'no': 5,
    'name': '思想与信念',
    'en': 'Ideology',
    'desc': '把信条以极端方式活出来。',
  },
  <String, Object?>{
    'no': 6,
    'name': '重要之人',
    'en': 'Significant People',
    'desc': '尽一切努力接近 TA。',
  },
  <String, Object?>{
    'no': 7,
    'name': '被收容',
    'en': 'Institutionalized',
    'desc': '醒来在病房或拘留室。',
  },
  <String, Object?>{
    'no': 8,
    'name': '惊慌逃窜',
    'en': 'Flee in Panic',
    'desc': '醒来已在荒野或长途车上。',
  },
  <String, Object?>{
    'no': 9,
    'name': '恐惧症',
    'en': 'Phobia',
    'link': 'phobia',
    'desc': '掷 1D100 从恐惧症表（100 条）决定具体症状。',
  },
  <String, Object?>{
    'no': 10,
    'name': '躁狂症',
    'en': 'Mania',
    'link': 'mania',
    'desc': '掷 1D100 从狂躁症表（100 条）决定具体症状。',
  },
];

/// 掷**即时症状表**：1D10 决定发作种类。
///
/// 返回 `{kind:'bout'|'phobia'|'mania', no, src}`：
///   1-8 → kind='bout'（src = boutTable 条目）；
///   9 → kind='phobia'、10 → kind='mania'（src = 对应 100 表随机一条）。
Map<String, Object?> rollTable([JsRng? rng]) {
  final r = rng ?? nowRng;
  final no = 1 + (r() * 10).floor();
  final row = boutTable[no - 1];
  final link = row['link'];
  if (!jsTruthy(link)) return <String, Object?>{'kind': 'bout', 'no': no, 'src': row};
  final arr = pool(jsStr(link));
  if (arr.isEmpty) return <String, Object?>{'kind': 'bout', 'no': no, 'src': row};
  return <String, Object?>{
    'kind': link,
    'no': no,
    'src': arr[(r() * arr.length).floor()],
  };
}

/// 掷**总结症状表**（独处 / 事后）。规则同 rollTable，只是 1-8 取 [summaryTable]。
/// 返回 `{kind:'sum'|'phobia'|'mania', no, src}`
Map<String, Object?> rollSummary([JsRng? rng]) {
  final r = rng ?? nowRng;
  final no = 1 + (r() * 10).floor();
  final row = summaryTable[no - 1];
  final link = row['link'];
  if (!jsTruthy(link)) return <String, Object?>{'kind': 'sum', 'no': no, 'src': row};
  final arr = pool(jsStr(link));
  if (arr.isEmpty) return <String, Object?>{'kind': 'sum', 'no': no, 'src': row};
  return <String, Object?>{
    'kind': link,
    'no': no,
    'src': arr[(r() * arr.length).floor()],
  };
}

/// 背景症状文本（给随机角色池 / 彩蛋卡 / AI 卡用）。
///
/// v2.1.9：背景心理症状**改按总结症状表**掷骰 ——
/// 8/10 得到一条总结症状（文本标【疯狂发作】），
/// 各 1/10 得到恐惧症 / 狂躁症（来自 100 条子表）。
/// 文本格式沿用 `【类型】名字：描述`。
String backgroundText([String? tail, JsRng? rng]) {
  final hit = rollSummary(rng);
  final src = asMap(hit['src']);
  if (jsStr(hit['kind']) == 'sum') {
    return '【疯狂发作】${src['name']}：${jsTruthy(src['desc']) ? src['desc'] : ''}${tail ?? ''}';
  }
  final t = (jsStr(hit['kind']) == 'mania') ? '狂躁症' : '恐惧症';
  return '【$t】${src['name']}：${jsTruthy(src['desc']) ? src['desc'] : ''}${tail ?? ''}';
}

/// 随机一个疯狂结果。
///
/// @param type  'phobia' | 'mania'（手动指定表，直接从该表抽）
///              | 'any'（默认：**按疯狂表 1D10 规则** —— 见 [boutTable]）
/// @param permanent 是否永久（轮次归零、不随推进消退）
/// @returns `{id,type,name,en,desc,permanent,rounds,at}`；
///          type 可能是 'phobia' | 'mania' | 'bout'（1-8 的发作行为）。
Map<String, Object?>? roll(Object? type, bool permanent, [JsRng? rng]) {
  final t = (type == 'phobia' || type == 'mania') ? jsStr(type) : 'any';
  late Map<String, Object?> s;
  if (t == 'any') {
    /* v2.1.7：1D10 疯狂表 —— 1-8 发作行为、9 恐惧表、10 狂躁表 */
    final hit = rollTable(rng);
    final src = asMap(hit['src']);
    s = <String, Object?>{
      'type': hit['kind'],
      'name': src['name'],
      'en': src['en'] ?? '',
      'desc': src['desc'] ?? '',
    };
  } else {
    final src = pool(t);
    if (src.isEmpty) return null;
    final p = src[((rng ?? nowRng)() * src.length).floor()];
    s = <String, Object?>{
      'type': t,
      'name': p['name'],
      'en': p['en'] ?? '',
      'desc': p['desc'] ?? '',
    };
  }
  return <String, Object?>{
    'id': uid(),
    'type': s['type'],
    'name': s['name'],
    'en': s['en'] ?? '',
    'desc': s['desc'] ?? '',
    'permanent': permanent,
    // 规则书：临时疯狂持续 1D10 轮。这里随机 1-10 轮。
    // ⚠️ 原码这里用的是 Math.random（不是注入的 rng），照抄。
    'rounds': permanent ? 0 : (1 + (nowRng() * 10).floor()),
    'at': nowMillis(),
  };
}

/// 从症状表里挑一条（不掷骰，供「手动添加」用）
Map<String, Object?>? make(
  Object? type,
  Map<String, Object?>? src,
  bool permanent, [
  int? rounds,
]) {
  if (src == null) return roll(type, permanent);
  /* v2.1.9：保留 bout（发作行为 / 总结症状）类型，
     不再一律强转 phobia —— 否则「失忆」会被记成一条不存在的恐惧症。 */
  final t = (type == 'mania') ? 'mania' : (type == 'bout' ? 'bout' : 'phobia');
  return <String, Object?>{
    'id': uid(),
    'type': t,
    'name': src['name'],
    'en': src['en'] ?? '',
    'desc': src['desc'] ?? '',
    'permanent': permanent,
    'rounds': permanent
        ? 0
        : ((rounds ?? 0) != 0 ? rounds : (1 + (nowRng() * 10).floor())),
    'at': nowMillis(),
  };
}

List<Object?> list(Character? character) {
  if (character == null) return <Object?>[];
  if (!isArray(character.raw['madness'])) character.raw['madness'] = <Object?>[];
  return asList(character.raw['madness']);
}

Map<String, Object?>? add(Character character, Map<String, Object?>? entry) {
  if (entry == null) return null;
  list(character).add(entry);
  return entry;
}

Map<String, Object?>? remove(Character character, Object? id) {
  final arr = list(character);
  for (var i = 0; i < arr.length; i++) {
    final m = asMap(arr[i]);
    if (m['id'] == id) {
      arr.removeAt(i);
      return m;
    }
  }
  return null;
}

void clear(Character character) {
  character.raw['madness'] = <Object?>[];
}

/// 推进 n 轮，把到期的临时疯狂清掉。
/// 永久疯狂（permanent）永远不会被这一步清掉 —— 只能手动删。
///
/// @returns 本轮自然消退的症状
List<Object?> advance(Character character, Object? n) {
  final step = jsMax(<int>[1, jsNum(n) != 0 ? jsNum(n) : 1]);
  final arr = list(character);
  final faded = <Object?>[];
  for (var i = arr.length - 1; i >= 0; i--) {
    final m = asMap(arr[i]);
    if (jsTruthy(m['permanent'])) continue;
    final rounds = m['rounds'];
    m['rounds'] = (rounds == null) ? 1 : (jsNum(rounds) - step);
    if (jsNum(m['rounds']) <= 0) {
      faded.add(arr.removeAt(i));
    }
  }
  return faded;
}

/// 一句话摘要，给角色卡与状态栏显示（v2.1.7：背景症状单独标注）
String summary(Character character) {
  final arr = list(character);
  if (arr.isEmpty) return '';
  return arr
      .map(
        (m) =>
            '【${labelOf(asMap(m)['type'])}】${asMap(m)['name']}${tailText(asMap(m))}',
      )
      .join('　');
}

/// 条目尾注：背景症状 / 永久 / 剩余轮次（三处显示共用，v2.1.7 抽出）
String tailText(Map<String, Object?> m) {
  if (jsTruthy(m['permanent'])) {
    return jsTruthy(m['bg']) ? '（背景症状）' : '（永久）';
  }
  return '（${jsNum(m['rounds'])} 轮）';
}

/// 还有几条会在 N 轮内消退（给「本轮结束」提示用）
List<Object?> fading(Character character, Object? within) {
  final w = jsMax(<int>[1, jsNum(within) != 0 ? jsNum(within) : 1]);
  return list(character).where((mRaw) {
    final m = asMap(mRaw);
    return !jsTruthy(m['permanent']) && jsNum(m['rounds']) <= w;
  }).toList();
}

/* ============================================================
 * 背景文本 → 结构化症状
 *
 * 第 8 步「恐惧症 / 狂躁症」在很长一段时间里只是一个**文本框**
 * （background.phobias），而状态管理里的 madness 是另一套数组，
 * 两者互不相通 —— 结果是「背景里明明写着幽闭恐惧症，状态管理里却是空的」。
 *
 * 这里做两件事：
 *   1) 以后在背景里点选症状时，**同时**写结构化数组（见 fromPicked）；
 *   2) 对**已经存下来的老卡**做一次性迁移，把文本里的症状补进数组。
 *
 * 迁移必须幂等：同一张卡反复进 normalize() 不能越迁越多（否则每存一次
 * 就多一条重复的症状）。所以按「名称 + 类型」去重，且只处理
 * **在症状表里确实存在**的名字 —— 文本框里玩家自己写的自由文字不硬塞。
 * ============================================================ */

/// 把一条症状名归一到症状表里的条目；认不出返回 null
Map<String, Object?>? lookup(Object? name, [Object? type]) {
  final n = jsStr(name ?? '').trim();
  if (n.isEmpty) return null;
  final pools = (type == 'mania')
      ? <String>['mania']
      : (type == 'phobia')
      ? <String>['phobia']
      : <String>['phobia', 'mania'];
  for (final p in pools) {
    final arr = pool(p);
    for (final row in arr) {
      if (jsStr(row['name']) == n) {
        return <String, Object?>{'type': p, 'src': row};
      }
    }
  }
  return null;
}

/// 背景文本里是否已经有这一条（同一姓名 + 同一类型算重复）
bool hasName(Character? character, Object? type, Object? name) {
  return list(character).any((mRaw) {
    final m = asMap(mRaw);
    return m['name'] == name && (m['type'] == type || !jsTruthy(type));
  });
}

/// 从背景文本解析出症状名。
///
/// 背景里的写入格式是每一行 `【恐惧症】幽闭恐惧症：描述…`（见 steps-d.js）。
/// 但用户也可能手打进纯文本，所以这里两种都认：
///   · 带 `【类型】名字：…` 的按标记走（最准）
///   · 其余每一行取「：」之前那段当候选名，再去症状表里查
/// 查不到的一律忽略 —— 不能把玩家的自由描述硬当成症状。
List<Map<String, Object?>> parseBackground(Object? text) {
  final out = <Map<String, Object?>>[];
  final seen = <String, bool>{};
  final re = RegExp(r'^【(恐惧症|狂躁症)】\s*([^：:]+)');
  for (final line in jsStr(text ?? '').split(RegExp(r'\r?\n'))) {
    final s = line.trim();
    if (s.isEmpty) continue;
    final m = re.firstMatch(s);
    if (m != null) {
      final t = (m[1] == '狂躁症') ? 'mania' : 'phobia';
      final hit = lookup(m[2]!.trim(), t);
      if (hit != null) {
        final key = '$t/${asMap(hit['src'])['name']}';
        if (!(seen[key] ?? false)) {
          seen[key] = true;
          out.add(hit);
        }
      }
      continue;
    }
    // 没带标记：整行当候选名（去了「：描述」的尾巴）
    final bare = s.split(RegExp(r'[：:]')).first.trim();
    final h2 = lookup(bare);
    if (h2 != null) {
      final key = '${h2['type']}/${asMap(h2['src'])['name']}';
      if (!(seen[key] ?? false)) {
        seen[key] = true;
        out.add(h2);
      }
    }
  }
  return out;
}

/// 把背景文本里已识别的症状**补进** madness 数组（永久疯狂）。
/// 幂等：已有的不重复加。返回本次新增的条数。
int fromBackground(Character? character) {
  if (character == null) return 0;
  final found = parseBackground(character.background['phobias']);
  var added = 0;
  for (final h in found) {
    final src = asMap(h['src']);
    if (hasName(character, h['type'], src['name'])) continue;
    final e = make(h['type'], src, true)!;
    e['bg'] = true; /* v2.1.7：标记来源是背景 —— 显示「（背景症状）」而非「（永久）」 */
    add(character, e);
    added++;
  }
  return added;
}

/// 背景点选后调用：把选中的症状同时写进结构化数组（永久疯狂），返回新增条数
int fromPicked(Character? character, Object? picked) {
  if (character == null || !isArray(picked)) return 0;
  var added = 0;
  for (final xRaw in asList(picked)) {
    final x = asMap(xRaw);
    /* v2.1.9：新增支持『疯狂发作』（即时 / 总结症状）—— type='bout'，
       并打 sum 标记；恐惧症 / 狂躁症仍走 phobia / mania。 */
    final String type;
    if (x['type'] == 'bout' || x['kind'] == '疯狂发作') {
      type = 'bout';
    } else {
      type = (x['kind'] == '狂躁症' || x['type'] == 'mania') ? 'mania' : 'phobia';
    }
    final name = jsStr(x['name'] ?? xRaw).trim();
    if (name.isEmpty) continue;
    if (hasName(character, type, name)) continue;
    final hit = (type == 'bout') ? null : lookup(name, type);
    final src = hit != null
        ? asMap(hit['src'])
        : <String, Object?>{
            'name': name,
            'en': x['en'] ?? '',
            'desc': x['desc'] ?? '',
          };
    final e = make(type, src, true)!;
    e['bg'] = true; /* v2.1.7：同 fromBackground */
    if (type == 'bout' && jsTruthy(x['sum'])) e['sum'] = true; /* v2.1.9：总结症状标记 */
    add(character, e);
    added++;
  }
  return added;
}

int get size =>
    asList(cocMadnessTable['phobias']).length +
    asList(cocMadnessTable['manias']).length;

List<Map<String, Object?>> phobias() =>
    asList(cocMadnessTable['phobias'])
        .map((x) => _tag('phobia', asMap(x)))
        .toList();

List<Map<String, Object?>> manias() =>
    asList(cocMadnessTable['manias'])
        .map((x) => _tag('mania', asMap(x)))
        .toList();
