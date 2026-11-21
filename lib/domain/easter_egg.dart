// ============================================================
// easter_egg.dart — 彩蛋角色卡（名人 🥚 / 跑团成员 🎭）
// 逐行对应 `core/easter-egg.js`（约 290 行）
//
// 两类彩蛋都**不绕过规则引擎**：彩蛋只提供「创意字段」（是谁、什么职业、
// 属性大致多少），数值落地仍然走 preset_gen.build() —— 所以彩蛋卡一样合规。
//
// 抽签规则（与旧版一致，别改）：
//   · `generate()` 是**批级**抽签：整批只掷一次，约 1/4 出跑团成员、
//     约 1/4 出名人，且固定落在这一批的中间那张；
//   · `generateOne()` 走**单卡**概率（朋友 2.6% / 名人 6.6%），仅作兜底。
//
// 数据在 `data/easter_egg.dart`（22 位名人 + 8 位跑团成员），本文件只放逻辑。
// ============================================================

import 'data/easter_egg.dart';
import 'js_compat.dart';
import 'personas.dart' as personas;

/// 批级概率：一整批只抽一次（`preset.generate()` 走这条）
const double batchFriendRate = 0.25;
const double batchCelebRate = 0.25;

/// 单卡概率（`roll()` 兜底用）
const double cardFriendRate = 0.026;
const double cardCelebRate = 0.066;

/// 一个彩蛋：`{kind: 'celeb'|'friend', data: {...}}`
class EasterEgg {
  const EasterEgg(this.kind, this.data);

  final String kind;
  final Map<String, Object?> data;

  bool get isFriend => kind == 'friend';

  /// 界面角标：🥚 名人 / 🎭 跑团成员
  String get badge => isFriend ? '🎭' : '🥚';
}

/// 全部名人
List<Map<String, Object?>> get celebrities => eggCelebrities;

/// 全部跑团成员
List<Map<String, Object?>> get friends => eggFriends;

Map<String, Object?>? _pickOne(List<Map<String, Object?>> arr) {
  if (arr.isEmpty) return null;
  return arr[personas.rnd(arr.length)];
}

/// 单卡抽签（`roll()`）。命中率可覆盖，默认 2.6% / 6.6%。
EasterEgg? roll({double? rate, double? friendRate}) {
  final fr = friendRate ?? cardFriendRate;
  final cr = rate ?? cardCelebRate;
  final r = nowRng();
  if (r < fr) {
    final d = _pickOne(eggFriends);
    return d == null ? null : EasterEgg('friend', d);
  }
  if (r < fr + cr) {
    final d = _pickOne(eggCelebrities);
    return d == null ? null : EasterEgg('celeb', d);
  }
  return null;
}

/// 批级抽签（`rollBatch()`）—— `preset_gen.generate()` 实际调用的入口
///
/// ⚠️ 无论 [n] 是多少，**先掷且只掷一次** —— 这个消耗位置必须与 JS 一致，
///    否则同一 seed 下整批卡的随机序列会整体错位。
EasterEgg? rollBatch([Object? n]) {
  final r = nowRng();
  if (r < batchFriendRate) {
    final d = _pickOne(eggFriends);
    return d == null ? null : EasterEgg('friend', d);
  }
  if (r < batchFriendRate + batchCelebRate) {
    final d = _pickOne(eggCelebrities);
    return d == null ? null : EasterEgg('celeb', d);
  }
  return null;
}

/// 彩蛋注入 `preset_gen.build()` 的 profile（`toProfile()`）
///
/// ⚠️ `residence` 取 `d.city`（可能没有）—— 缺省时 build() 会从世界设定的
///    城市池里随机取，这正是「跑团成员的住所改为随机」那条需求。
Map<String, Object?> toProfile(EasterEgg? egg) {
  if (egg == null) return <String, Object?>{};
  final d = egg.data;
  return <String, Object?>{
    'name': d['name'],
    'gender': d['gender'],
    'age': d['age'],
    'era': d['era'],
    'eraCustom': d['eraCustom'],
    'setting': d['setting'],
    'occupationName': d['occ'],
    'attributes': Map<String, Object?>.from(asMap(d['attrs'])),
    'residence': d['city'],
    'birthplace': d['town'],
    'playerName': egg.isFriend ? '茶叶蛋调查员协会' : '预设调查员',
    // 这两个字段会被预设卡的背景生成器采纳
    'ideology': d['idea'],
    'traits': d['trait'],
    // 背景心理症状不在此处指定 —— 交给 build() 按疯狂表掷
    'isEasterEgg': true,
    'eggKind': egg.kind,
  };
}

/// 不带随机性的全量清单（审计 / 测试用）
List<EasterEgg> all() => <EasterEgg>[
  ...eggCelebrities.map((c) => EasterEgg('celeb', c)),
  ...eggFriends.map((f) => EasterEgg('friend', f)),
];

/// 彩蛋总数
int get eggCount => eggCelebrities.length + eggFriends.length;
