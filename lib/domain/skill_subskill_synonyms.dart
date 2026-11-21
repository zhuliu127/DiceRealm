// ============================================================
// domain/skill_subskill_synonyms.dart — 组技能**子类**独立近义词（P10 第 5 期 / C）
//
// 上批 `skill_synonyms.dart` 只按技能 id 补了「组名」近义词，并登记遗留
// 「组技能子类名暂无独立近义词」。本表把这层补齐：按 **组 id + 子类名**
// 给 8 条 `special:true` 组技能的**每一个子类行**配一组独立近义词，
// 让搜「pistol / 短枪」命中「射击（手枪）」、搜「拳脚」命中「格斗（斗殴）」。
//
// ★ 三条硬约束（与上批同精神）：
//   1) 只参与 `skillMatchesKeyword` 的匹配字段，**绝不进任何渲染文本**；
//   2) `lib/domain/data/skills.dart` 是 GENERATED FILE，一字不改，本表按
//      「组 id + 子类名」外挂，与生成数据完全解耦；
//   3) **分层不串**：组级表 `skillSynonyms` 与子级表 `skillSubskillSynonyms`
//      是两个独立常量；`subskillSynonymsOf` 复用 `skillSynonymIdOf` 的三级
//      回退**只用来解析组 id**，再单独查子级表，绝不把两级词互相并进去。
//      每个子类的词都刻意避开组级词与其它子类的词，防「搜 A 带出 B」。
//
// ★ 为什么子类名本身（如「手枪」）也能搜到：两个搜索框传的 Map 里 `sub`
//   与 `name` 已含子类名，正式名命中是既有能力；本表真正新增的是**该类
//   专属的口语 / 旧译 / 英文词**，且这些词只对该子类行生效。
//
// ⚠️ 纯 Dart：零引擎 / 零文件 / 零界面依赖，只 import 生成数据、
//   js_compat 与上批的组级表（用于三级回退解析）。
// ============================================================

import 'data/skills.dart' show cocSkills;
import 'js_compat.dart' show asList, asMap, jsStr, jsTruthy;
import 'skill_synonyms.dart' show skillSynonymIdOf;

/// 组 id → 子类名 → 该子类**专属**近义词。
///
/// 覆盖 `cocSkills` 里全部 `special:true` 的 8 组、86 个子类行
/// （由 `uncoveredSubskillRows()` 逐行断言，防「只给几个常用子类加」）。
const Map<String, Map<String, List<String>>> skillSubskillSynonyms =
    <String, Map<String, List<String>>>{
  // ---- 其他语言（15） ----
  'language_other': <String, List<String>>{
    '拉丁语': <String>['拉丁文', 'latin', '拉丁'],
    '英语': <String>['英文', 'english', '英吉利语'],
    '法语': <String>['法文', 'french', '法兰西语'],
    '德语': <String>['德文', 'german', '日耳曼语'],
    '西班牙语': <String>['西语', 'spanish', '西班牙文'],
    '意大利语': <String>['意语', 'italian', '意大利文'],
    '俄语': <String>['俄文', 'russian', '俄罗斯语'],
    '希腊语': <String>['希腊文', 'greek', '古希腊语'],
    '希伯来语': <String>['希伯来文', 'hebrew', '犹太语'],
    '阿拉伯语': <String>['阿拉伯文', 'arabic', '阿语'],
    '梵语': <String>['梵文', 'sanskrit', '天城体'],
    '汉语': <String>['中文', 'chinese', '华语', '官话'],
    '日语': <String>['日文', 'japanese', '和语'],
    '埃及语': <String>['埃及文', 'egyptian', '象形文字'],
    '阿卡德语': <String>['阿卡德文', 'akkadian', '楔形文字'],
  },
  // ---- 格斗（7）----
  // ★ 组级表已有「徒手 / brawl / 近战 / 肉搏」，这里刻意不重复，
  //   否则搜这些词会把格斗的 7 个子类一起带出来（跨子类串味）。
  'fighting': <String, List<String>>{
    '斗殴': <String>['拳脚', '空手', 'unarmed', '赤手'],
    '刀剑': <String>['剑术', '刀法', 'sword', '白刃'],
    '斧': <String>['斧头', '战斧', 'axe', '斧术'],
    '矛': <String>['长矛', '枪术', 'spear', '矛术'],
    '绞索': <String>['绳索', '勒杀', 'garrote', '套索'],
    '鞭': <String>['鞭子', '长鞭', 'whip', '鞭术'],
    '链锯/连枷': <String>['链锯', '连枷', 'chainsaw', '钉锤'],
  },
  // ---- 射击（5）----
  'firearms': <String, List<String>>{
    '手枪': <String>['手枪', 'pistol', '短枪', 'handgun', '左轮'],
    '步枪/霰弹枪': <String>['步枪', '霰弹枪', 'rifle', 'shotgun', '猎枪'],
    '冲锋枪': <String>['冲锋枪', 'smg', 'submachine', '自动枪'],
    '弓': <String>['弓箭', 'bow', '箭术', '弓术'],
    '机枪/重武器/火焰喷射器': <String>[
      '机枪',
      '重武器',
      '火焰喷射器',
      'machinegun',
      '喷火器',
      '重火力',
    ],
  },
  // ---- 科学（13）----
  'science': <String, List<String>>{
    '天文学': <String>['天文', '星象', 'astronomy', '观星'],
    '生物学': <String>['生物', 'biology', '生命科学'],
    '植物学': <String>['植物', 'botany', '草木'],
    '化学': <String>['chemistry', '化学实验', '药剂化学'],
    '密码学': <String>['密码', 'cryptography', '破译', '加密'],
    '工程学': <String>['工程', 'engineering', '土木'],
    '司法科学': <String>['法医', 'forensics', '刑侦技术', '鉴证'],
    '地质学': <String>['地质', 'geology', '岩石'],
    '气象学': <String>['气象', 'meteorology', '天气'],
    '数学': <String>['math', 'mathematics', '算术', '代数'],
    '药学': <String>['药理', 'pharmacology', '药物'],
    '物理学': <String>['物理', 'physics', '力学'],
    '动物学': <String>['zoology', '动物分类', '动物研究'],
  },
  // ---- 学识（6）----
  'lore': <String, List<String>>{
    '文学': <String>['古典文学', 'literature', '诗文', '典籍'],
    '军事': <String>['兵法', 'military', '军略', '战术史'],
    '棋艺': <String>['棋类', 'chess', '对弈', '博弈'],
    '梦境学识': <String>['梦境', 'dream lore', '幻梦', '梦学'],
    '《死灵之书》学识': <String>['死灵之书', 'necronomicon', '死灵书', '禁书'],
    'UFO 学识': <String>['ufo', '不明飞行物', '飞碟', '外星'],
  },
  // ---- 驾驶（2）----
  'pilot': <String, List<String>>{
    '飞行器': <String>['飞机', 'aircraft', '飞行', '航空'],
    '船': <String>['船舶', 'ship', '航海', '操船'],
  },
  // ---- 生存（7）----
  'survival': <String, List<String>>{
    '沙漠': <String>['荒漠', 'desert', '沙海', '干旱地'],
    '极地': <String>['polar', '冰雪', '寒带', '极地环境'],
    '海上': <String>['海洋', 'sea', '远洋', '海上求生'],
    '丛林': <String>['雨林', 'jungle', '密林', '热带林'],
    '山地': <String>['高山', 'mountain', '山区', '攀登地'],
    '平原': <String>['草原', 'plain', '旷野', '平野'],
    '沼泽': <String>['湿地', 'swamp', '泥沼', '泽地'],
  },
  // ---- 技艺（31）----
  // ★ 与 `lore` 同名的「文学」子类刻意用不同的词，避免跨组串味。
  'art_craft': <String, List<String>>{
    '表演': <String>['演戏', 'acting', '舞台剧', '演艺'],
    '美术': <String>['fine art', '造型艺术', '绘事', '美术创作'],
    '绘画': <String>['画画', 'draw', '绘图', '油画'],
    '摄影': <String>['拍照', 'photography', '相片', '照相'],
    '伪造文书': <String>['造假', 'forgery', '伪造', '仿造文件'],
    '文学': <String>['作文', 'literary writing', '文笔', '文学创作'],
    '写作': <String>['撰稿', 'writing', '写文', '著述'],
    '书法': <String>['calligraphy', '毛笔字', '书道', '写字'],
    '乐理': <String>['music theory', '乐谱', '音律', '作曲理论'],
    '厨艺': <String>['烹饪', 'cooking', '做菜', '料理'],
    '裁缝': <String>['缝纫', 'tailoring', '做衣服', '针线'],
    '理发': <String>['剪发', 'hairdressing', '美发', '剃头'],
    '建筑': <String>['architecture', '营造', '建筑学', '盖房'],
    '舞蹈': <String>['跳舞', 'dance', '舞步', '编舞'],
    '酿酒': <String>['brewing', '造酒', '酒艺', '酿造'],
    '捕鱼': <String>['钓鱼', 'fishing', '渔猎', '打鱼'],
    '歌唱': <String>['唱歌', 'singing', '声乐', '演唱'],
    '制陶': <String>['陶艺', 'pottery', '烧陶', '陶器'],
    '雕塑': <String>['雕刻', 'sculpture', '塑像', '石雕'],
    '杂技': <String>['acrobatics', '杂耍', '特技', '马戏'],
    '风水': <String>['feng shui', '堪舆', '相地', '阴阳宅'],
    '技术制图': <String>['制图', 'drafting', '工程图', '蓝图'],
    '耕作': <String>['种田', 'farming', '农作', '耕地'],
    '打字': <String>['typing', '打字机', '录入', '键盘输入'],
    '速记': <String>['shorthand', '速写记录', 'stenography', '快记'],
    '木匠': <String>['木工', 'carpentry', '木作', '做家具'],
    '莫里斯舞': <String>['morris dance', '莫里斯', '英国民间舞', '铃舞'],
    '歌剧歌唱': <String>['opera', '歌剧', '美声', '咏叹调'],
    '粉刷匠与油漆工': <String>['油漆', 'house painting', '刷墙', '涂装'],
    '吹制玻璃管': <String>['玻璃吹制', 'glassblowing', '吹玻璃', '玻璃工艺'],
  },
};

/// 「技能搜索框传进来的 Map」对应的子类近义词（无则空表，绝不返回 null）。
///
/// 解析分两步，**分层**：
///   ① `skillSynonymIdOf(skill)` 走上批的三级回退（`id → skill → name 反查`）
///      解析出**组 id**（两个搜索框的 Map 形状不同，必须由它统一）；
///   ② 用 `sub` 取子类名，只在本张子级表里查一次。
/// 组级词与子级词互不并入，搜子级词不会把别的组 / 别的子类带出来。
List<String> subskillSynonymsOf(Map<String, Object?> skill) {
  final groupId = skillSynonymIdOf(skill);
  if (groupId == null) return const <String>[];
  final sub = jsStr(skill['sub']);
  if (sub.isEmpty) return const <String>[];
  return skillSubskillSynonyms[groupId]?[sub] ?? const <String>[];
}

/// 生成数据里全部 `special:true` 子类行的 `组id::子类名`（顺序稳定）。
List<String> allSpecialSubskillRows() => <String>[
      for (final def in cocSkills.where((d) => jsTruthy(d['special'])))
        for (final raw in asList(def['subskills']))
          '${jsStr(def['id'])}::${jsStr(asMap(raw)['name'])}',
    ];

/// 没有被本表覆盖的子类行（覆盖断言用；期望恒为空表）。
List<String> uncoveredSubskillRows() {
  final out = <String>[];
  for (final row in allSpecialSubskillRows()) {
    final i = row.indexOf('::');
    final groupId = row.substring(0, i);
    final sub = row.substring(i + 2);
    final words = skillSubskillSynonyms[groupId]?[sub];
    if (words == null || words.isEmpty) out.add(row);
  }
  return out;
}

/// 全部子类近义词展平（防重复 / 分层零交集断言用）。
List<String> allSubskillWords() => <String>[
      for (final group in skillSubskillSynonyms.values)
        for (final words in group.values)
          for (final w in words) w,
    ];
