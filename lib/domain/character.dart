// ============================================================
// character.dart — 角色卡数据模型
//
// 对应 `core/store.js` 的：
//   · `newCharacter()`      → [newCharacter]
//   · `uid()`               → [uid]
//   · `defaultSettings()`   → [defaultSettings]
//
// ⚠️ 关键设计（与审计 §D.1 一致，不要"优化"）：
//   角色卡**没有 schema 版本号**，结构演进全靠 normalize() 的幂等字段探测。
//   老存档里字段就是缺的、类型也可能是字符串，所以这里不做强类型化 ——
//   [Character] 只是包在 `Map<String, Object?>` 外面的一层**便捷视图**，
//   真值永远是那张 JSON 形状的 Map，读写都直接作用于它。
//   这样做的好处：老卡能原样读进来、normalize 能逐字段补、导出格式一字不变。
// ============================================================

import 'dart:math' as math;

import 'js_compat.dart';

/// 精神状态的「正常」项。多选里它是特殊互斥项（选了就代表没有任何异常）。
/// 值必须与 rules_coc7.dart#mentalStatus 的字面量一致。
const String kMentalNormal = '正常';

const String _uidChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// 生产环境的熵源：`Random.secure()`（平台 CSPRNG）。
///
/// ⚠️ 为什么不再用 [nowRng]（P0 报告已记录这是真 bug）：
///   [nowRng] 的默认实现是 `DateTime.now().microsecondsSinceEpoch % 1000000`，
///   同一微秒内连续调用 8 次拿到的是**同一个数**，于是「同一微秒连建两张卡」
///   必然生成同一个 id —— 后一张卡直接覆盖前一张。
///   `Random.secure()` 由平台 CSPRNG 提供，不存在这个相关性。
final math.Random _secureRng = math.Random.secure();

/// 是否让 [uid] 走「可复现」分支。
///
/// 只由测试置位（见 `test/support/oracle.dart`）：预言机的 `normalize` 用例
/// 会逐字比对 id，并断言「随机数消耗数 = 8」，两条都要求 id 由注入的
/// 确定性序列（对应 JS 的 `Math.random`）算出来。生产环境的默认值是 false，
/// 走 [math.Random.secure]。
bool uidDeterministic = false;

/// 8 位随机 id（对应 `Store.uid()`）
///
/// - 生产：[math.Random.secure] —— 同微秒连建卡不会撞 id。
/// - [uidDeterministic] 为真：与 JS `Math.random` 序列逐字一致（含 8 次消耗），
///   供 oracle 等价性测试使用。
String uid() {
  if (uidDeterministic) {
    var legacy = '';
    for (var i = 0; i < 8; i++) {
      legacy += _uidChars[(nowRng() * _uidChars.length).floor()];
    }
    return legacy;
  }
  var out = '';
  for (var i = 0; i < 8; i++) {
    out += _uidChars[_secureRng.nextInt(_uidChars.length)];
  }
  return out;
}

/// 默认设置（`store.js#defaultSettings`）
///
/// shareBase / roomBase 留空表示未配置 —— 未配置时界面不提供入口。
/// aiBase / aiModel / aiKey 只存本机，不随请求以外的途径上传。
Map<String, Object?> defaultSettings() {
  return <String, Object?>{
    'skillCap': 99,
    'theme': 'light',
    'autoSave': true,
    'lastRuleSystem': null,
    'shareBase': '',
    'roomBase': '',
    'aiBase': 'https://api.deepseek.com/v1',
    'aiModel': 'deepseek-flash',
    'aiKey': '',
    // ---- AI 车卡的数值上限（可选）----
    // 0 / 空 表示不限制。设置后 AI 生成的卡会被**本地二次校准**，
    // 即使模型没照做也一定不会超标 —— 提示词只是第一道，这里是兜底。
    'aiAttrCap': 0, // 属性总和上限
    'aiAttrCapWithLuck': true, // true=含幸运，false=不含幸运
    'aiOccPtsCap': 0, // 职业技能点数上限
    'aiIntPtsCap': 0, // 兴趣技能点数上限
  };
}

/// 全新的空白角色卡（`store.js#newCharacter`）。
/// 新建时必须走这里，绝不能复用上一张卡的数据。
Map<String, Object?> newCharacter([String? ruleSystemId]) {
  final now = nowMillis();
  return <String, Object?>{
    'id': uid(),
    'userId': 'local',
    'ruleSystemId': (ruleSystemId == null || ruleSystemId.isEmpty)
        ? 'coc7'
        : ruleSystemId,

    // 基本信息
    'characterName': '',
    'playerName': '',
    'avatar': '',
    'basicInfo': <String, Object?>{
      'era': '现代',
      'eraCustom': '',
      'age': '', // 空着，让玩家自己填，避免误以为是系统给的默认年龄
      'gender': '男',
      'genderCustom': '',
      'residence': '',
      'birthplace': '',
      'occupationName': '',
    },
    // 兼容顶层访问
    'age': '',

    'occupationId': '',
    'occupationPicks': <String, Object?>{},
    'customOccupation': null,

    'attributes': <String, Object?>{
      'str': '',
      'con': '',
      'siz': '',
      'dex': '',
      'app': '',
      'int': '',
      'pow': '',
      'edu': '',
      'luck': '',
    },
    'attributeMode': 'random',
    'attributeHistory': <Object?>[],
    // 手动购点：属性点上限必须有真实初值。
    // 早期版本只在输入框里显示 480、却从没写进数据，
    // 于是 c.pbCap 是 undefined，校验按 0 算，页面会显示「超出上限 0」。
    'pbCap': 480,
    'pbIncludeLuck': true,
    // 「天命 N 选一」：一次性掷出 N 组属性（2-10 组），玩家从中挑一组。
    // 掷出后不再重掷 —— 这是模式的设计约束，只有新建角色卡才能换一批天命。
    'fate': <String, Object?>{
      'n': 5,
      'rolled': false,
      'options': <Object?>[],
      'picked': -1,
      'rolledAt': 0,
    },
    // 教育进步检定（年龄调整的一部分）：
    // 记录起始 EDU、每次掷骰结果与累计增益 bonus。
    // bonus 只作用于「生效属性」，不改写玩家输入的原始 EDU。
    'eduProgress': <String, Object?>{
      'base': null,
      'done': 0,
      'log': <Object?>[],
      'bonus': 0,
    },

    'derivedStats': <String, Object?>{},
    'status': <String, Object?>{
      'currentHP': 0,
      'maxHP': 0,
      'currentMP': 0,
      'maxMP': 0,
      'currentSAN': 0,
      'maxSAN': 99,
      'currentLuck': 0,
      // v2.10.0：body 收敛为四态单值 {正常, 轻伤, 重伤, 死亡}；
      // 「濒死 / 昏迷」改为布尔标记 dying / unconscious，可与「重伤」叠加。
      // 单机车卡与跑团房间共用同一张卡 schema、同语义
      // （房间侧权威形状见 room-model.js#sanitizeStatus / applyStateToCard，勿在此处发明新键名）。
      'body': '正常',
      // ⚠️ 新卡这里是**字符串**而不是数组 —— 老形状。normalize() 会把它变成
      // ['正常']。保持原样是为了让 normalize 的「字符串 → 数组」分支有输入可测。
      'mental': '正常',
      'dying': false,
      'unconscious': false,
    },

    // 疯狂状态列表（跑团中逐条掷出来的）。
    // 每条：{ id, type:'phobia'|'mania', name, en, desc, rounds, permanent, at }
    //   · type       恐惧症 / 狂躁症（v2.1.9 起还有 'bout' 发作行为）
    //   · rounds     持续轮数（临时疯狂）；permanent 为真时表示永久
    //   · permanent  永久疯狂 —— 不随轮次消失，只能手动删
    // 存成数组而不是塞进 background.phobias 文本，是因为要能逐条管理。
    'madness': <Object?>[],

    // 理智上限的永久减损（施放神话法术、与克苏鲁接触都可能 -1D5、-1D10）。
    // baseMaxSAN 记录「未被减损时的上限」（= 意志），
    // sanLoss 是累计减损量，界面上算作 maxSAN = baseMaxSAN − sanLoss。
    'baseMaxSAN': null,
    'sanLoss': 0,

    'skills': <Object?>[], // 完整技能实例
    'weapons': <Object?>[],
    'armors': <Object?>[],
    'vehicles': <Object?>[],
    'items': <Object?>[],

    'assets': <String, Object?>{
      'creditRating': 0,
      'cash': 0,
      'spendingLevel': '标准',
      'assetsDescription': '',
      'assets': <Object?>[],
      'currency': r'$',
    },

    'background': <String, Object?>{
      'description': '',
      'ideology': '',
      'significantPeople': '',
      'meaningfulPlaces': '',
      'treasuredPossessions': '',
      'traits': '',
      'wounds': '',
      'phobias': '',
    },
    'history': <Object?>[],
    'companions': <Object?>[],
    'mythos': <String, Object?>{
      'skill': 0,
      'knowledge': '',
      'entries': <Object?>[],
      'spells': <Object?>[],
    },

    'skillCap': 99, // 兼容旧数据：单一上限
    'skillCapOcc': 99, // 本职技能最终值上限
    'skillCapInterest': 99, // 非本职（兴趣）技能最终值上限
    'shareVisibility': 'link', // public | private | link
    'shareId': '',
    'version': 'v1.0',
    'changeLog': <Object?>[
      <String, Object?>{'version': 'v1.0', 'note': '创建角色', 'at': now},
    ],
    'createdAt': now,
    'updatedAt': now,
  };
}

/// 角色卡：`Map<String, Object?>` 的便捷视图。
///
/// 刻意**不做强类型字段**（见文件头说明）。规则层的函数都直接改 [raw]，
/// 与 JS 里 `c.status.maxHP = ...` 的行为逐字对应。
class Character {
  Character([Map<String, Object?>? raw]) : raw = raw ?? newCharacter();

  /// 从 JSON 读入（老存档路径）。**不拷贝** —— 直接持有同一个 Map，
  /// 这样 normalize 的修改会落到调用者手里那份数据上（与 JS 一致）。
  factory Character.fromJson(Map<String, Object?> json) => Character(json);

  final Map<String, Object?> raw;

  Map<String, Object?> toJson() => raw;

  // ---------- 常用视图 ----------
  Map<String, Object?> get basicInfo => asMap(raw['basicInfo']);
  Map<String, Object?> get attributes => asMap(raw['attributes']);
  Map<String, Object?> get status => asMap(raw['status']);
  Map<String, Object?> get assets => asMap(raw['assets']);
  Map<String, Object?> get background => asMap(raw['background']);
  Map<String, Object?> get mythos => asMap(raw['mythos']);
  Map<String, Object?> get derivedStats => asMap(raw['derivedStats']);
  Map<String, Object?> get eduProgress => asMap(raw['eduProgress']);
  Map<String, Object?> get fate => asMap(raw['fate']);
  Map<String, Object?> get occupationPicks => asMap(raw['occupationPicks']);

  List<Object?> get skills => asList(raw['skills']);
  List<Object?> get madnessList => asList(raw['madness']);

  String get id => jsStr(raw['id']);
  String get ruleSystemId => jsStr(raw['ruleSystemId']);
  String get occupationId => jsStr(raw['occupationId']);
  Object? get age => raw['age'];
  String get characterName => jsStr(raw['characterName']);
  String get playerName => jsStr(raw['playerName']);

  /// 深拷贝（角色数据是纯 JSON，JSON 往返即可）
  Character clone() => Character(_deepCopyMap(raw));

  /// 独立副本：构造一张结构相同的卡，用于「编辑会话」隔离
  static Map<String, Object?> _deepCopyMap(Map<String, Object?> m) {
    return _deepCopy(m) as Map<String, Object?>;
  }

  static Object? _deepCopy(Object? v) {
    if (v is Map) {
      final out = <String, Object?>{};
      v.forEach((k, val) => out[jsStr(k)] = _deepCopy(val));
      return out;
    }
    if (v is List) return v.map(_deepCopy).toList();
    return v;
  }
}
