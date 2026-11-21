// ============================================================
// assets_logic.dart — 资产 / 信用评级的**纯逻辑**（无 BuildContext）
//
// 逐行对齐旧版 `ui/steps-c.js#assets`：
//   · 信用评级必须落在职业允许区间内（`occupation.creditMin/creditMax`）
//   · 信用评级占用**职业点**：它是 `credit` 技能的 `occ` 值（旧版 `syncCreditSkill`）
//   · 生活水平 / 货币 / 建议现金与资产都由信用评级 + 时代自动推出
//   · 越界的信用评级**不写进模型**（与 P2-A 的「空输入 ≠ 0」同一口径）
//
// ⚠️ 旧版这里踩过的 bug（不许重复）：早期「每次 oninput 重建整个区块」，
//   导致输入框焦点丢失、软键盘被收起，而且数字没输完就被判「超出范围」。
//   现在的做法：输入框只创建一次（controller 常驻），非法值**只提示不写入**，
//   结构不变 → 焦点不丢。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/data/assets.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/occupation.dart';
import 'package:dice_realm/domain/skillmodel.dart';

import '../create/chargen_logic.dart';

/// 职业允许的信用评级区间
class CreditRange {
  const CreditRange(this.min, this.max);

  final int min;
  final int max;

  String get text => '$min - $max';

  int get mid => ((min + max) / 2).floor();
}

/// 取职业允许的信用评级区间；职业未选或未规定范围时返回 null
CreditRange? creditRange(Character c) {
  if (c.occupationId.isEmpty) return null;
  final occ = getOccupationById(c.occupationId);
  if (occ == null || occ['creditMin'] == null || occ['creditMax'] == null) return null;
  return CreditRange(jsNum(occ['creditMin']), jsNum(occ['creditMax']));
}

/// 提交信用评级的返回值
class CreditCommit {
  const CreditCommit({
    required this.written,
    this.value,
    this.error,
    this.hint,
  });

  /// 是否真的写进了模型
  final bool written;
  final int? value;

  /// 可读错误（界面直接显示）；null = 没有错误
  final String? error;

  /// 提示（未填写 / 无职业范围等），不是错误
  final String? hint;
}

/// 提交一个「输入框里的信用评级」。
///
/// 规则（与 P2-A 的通道同口径）：
///   · 空串 → **不写**（空输入 ≠ 0），返回「尚未分配」提示
///   · 非数字 → **不写**，返回错误
///   · 超出职业允许区间 → **不写**，返回错误（旧版会写进去再靠校验报错，
///     但那正是「没输完就判越界」的来源；这里改成拦在输入层）
///   · 合法 → 写入 `assets.creditRating`，同步到 `credit.occ`，并重算
CreditCommit commitCreditRating(Character c, String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const CreditCommit(written: false, hint: '尚未分配信用评级');
  }
  final parsed = jsParseInt(text);
  if (parsed == null) {
    return const CreditCommit(written: false, error: '信用评级必须是数字');
  }
  final value = clamp(parsed, 0, 99);
  final range = creditRange(c);
  if (range != null && (value < range.min || value > range.max)) {
    return CreditCommit(
      written: false,
      error: '信用评级需在 ${range.text} 之间（当前输入 $value）',
    );
  }
  c.assets['creditRating'] = value;
  syncCreditSkill(c);
  syncAssetDerived(c);
  return CreditCommit(written: true, value: value);
}

/// 程序化设置（chips / 「采用建议值」/ 导入回写用）
void setCreditRating(Character c, int value) {
  c.assets['creditRating'] = clamp(value, 0, 99);
  syncCreditSkill(c);
  syncAssetDerived(c);
}

/// 取 `credit` 技能实例（没有就建一个 —— 与旧版渲染前的 `syncSkills` 同效）
Map<String, Object?> creditSkillOf(Character c, {bool create = true}) {
  for (final sRaw in c.skills) {
    final s = asMap(sRaw);
    if (jsStr(s['id']) == 'credit') return s;
  }
  if (!create) return <String, Object?>{};
  return ensureSkill(c, 'credit', '');
}

/// 当前信用评级占用的职业点（= `credit.occ`）
int creditPointsOf(Character c) {
  final s = creditSkillOf(c, create: false);
  return s.isEmpty ? 0 : jsNum(s['occ']);
}

/// 资产 → 信用评级技能（旧版 `syncCreditSkill`：改资产，技能跟着变）
int syncCreditSkill(Character c) {
  final cr = clamp(jsNum(c.assets['creditRating']), 0, 99);
  final s = creditSkillOf(c);
  s['occ'] = cr;
  recompute(s);
  return cr;
}

/// 信用评级技能 → 资产（技能页里把信用评级加了点时，回到资产页跟着变）。
///
/// 只在「资产里还是 0」时采纳，避免把玩家在资产页填的值覆盖掉。
bool adoptCreditFromSkill(Character c) {
  if (jsNum(c.assets['creditRating']) != 0) return false;
  final fromSkill = creditPointsOf(c);
  if (fromSkill <= 0) return false;
  c.assets['creditRating'] = clamp(fromSkill, 0, 99);
  syncAssetDerived(c);
  return true;
}

/// 信用评级 → 生活水平（`livingLevels` 六档）
Map<String, Object?> livingLevelOf(int cr) {
  for (final lRaw in asList(cocAssets['livingLevels'])) {
    final l = asMap(lRaw);
    if (cr >= jsNum(l['crMin']) && cr <= jsNum(l['crMax'])) return l;
  }
  return asMap(asList(cocAssets['livingLevels']).first);
}

/// 当前时代对应的货币表（旧版：按 `basicInfo.era` 找，找不到退回第 2 条）
Map<String, Object?> currencyOf(Character c) {
  final era = jsStr(c.basicInfo['era']);
  final all = asList(cocAssets['currencies']).map(asMap).toList();
  for (final cur in all) {
    if (jsStr(cur['era']) == era) return cur;
  }
  return all.length > 1
      ? all[1]
      : (all.isEmpty ? <String, Object?>{} : all.first);
}

/// 由信用评级 + 时代推出 `spendingLevel` / `currency`（旧版 `paintLevel` 的副作用）
void syncAssetDerived(Character c) {
  final cr = jsNum(c.assets['creditRating']);
  c.assets['spendingLevel'] = jsStr(livingLevelOf(cr)['level']);
  c.assets['currency'] = jsStr(currencyOf(c)['unit']);
}

/// 建议现金 / 其他资产（旧版 `paintLevel` 里那段参考数值）
class SuggestedAmounts {
  const SuggestedAmounts({
    required this.cash,
    required this.assets,
    required this.currency,
  });

  final int cash;
  final int assets;
  final String currency;
}

/// 参考数值；信用评级为 0 或没有对应档位时返回 null（旧版同样不显示）
SuggestedAmounts? suggestedAmountsOf(Character c) {
  final cr = jsNum(c.assets['creditRating']);
  if (cr <= 0) return null;
  final level = jsStr(livingLevelOf(cr)['level']);
  final cur = currencyOf(c);
  final unit = jsStr(cur['unit']);
  for (final rowRaw in asList(cur['mul'])) {
    final row = asList(rowRaw);
    if (row.length < 3 || jsStr(row[0]) != level) continue;
    final cashMul = jsNum(row[1]);
    final assetMul = jsNum(row[2]);
    // 旧版：>100 / >1000 的当作「固定值」，其余按信用评级倍乘
    final cash = cashMul > 100 ? cashMul : cashMul * cr;
    final asset = assetMul > 1000 ? assetMul : assetMul * cr;
    return SuggestedAmounts(
      cash: jsRound(cash),
      assets: jsRound(asset),
      currency: unit,
    );
  }
  return null;
}

/// 现金：空 / 非数字 → **不写**（与信用评级同口径）
bool commitCash(Character c, String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final n = jsParseInt(text);
  if (n == null) return false;
  c.assets['cash'] = clamp(n, 0, 999999999);
  return true;
}

/// 资产分类（旧版的 5 个固定类目）
const List<String> assetCategories = <String>[
  '交通工具',
  '住所',
  '奢侈品',
  '股票/证券',
  '其他',
];

/// 读某类资产的描述（同类只保留一条，与旧版一致）
String assetDescOf(Character c, String cat) {
  for (final xRaw in asList(c.assets['assets'])) {
    final x = asMap(xRaw);
    if (jsStr(x['cat']) == cat) return jsStr(x['desc']);
  }
  return '';
}

/// 写某类资产的描述（空 → 移除该类）
void setAssetDesc(Character c, String cat, String desc) {
  final kept = asList(c.assets['assets'])
      .map(asMap)
      .where((x) => jsStr(x['cat']) != cat)
      .toList();
  if (desc.trim().isNotEmpty) {
    kept.add(<String, Object?>{'cat': cat, 'desc': desc});
  }
  c.assets['assets'] = kept;
}

/// 「采用建议现金与资产」：写 cash + assetsDescription（旧版同款文案）
void adoptSuggestedAmounts(Character c, SuggestedAmounts s) {
  c.assets['cash'] = s.cash;
  c.assets['assetsDescription'] = '总价值约 ${s.currency} ${s.assets}';
}

/// 技能上限提示（旧版 `refreshCreditNotice` 末段，只作提示用）
String skillCapHint(Character c) {
  final occCap = jsNum(c.raw['skillCapOcc']) != 0
      ? jsNum(c.raw['skillCapOcc'])
      : jsNum(c.raw['skillCap']);
  final intCap = jsNum(c.raw['skillCapInterest']) != 0
      ? jsNum(c.raw['skillCapInterest'])
      : jsNum(c.raw['skillCap']);
  if (occCap <= 0 && intCap <= 0) return '';
  final parts = <String>[];
  if (occCap > 0) parts.add('本职技能最多 $occCap');
  if (intCap > 0) parts.add('非本职技能最多 $intCap');
  return '技能最终值上限：${parts.join('　·　')}。'
      '点数池不因此减少，但如果所有技能都到上限，剩余点数就无法分配。';
}

/// 该卡的所有技能是否已经在列表里（旧版渲染前会 `SM.syncSkills`）
bool hasCreditSkill(Character c) =>
    c.skills.any((sRaw) => jsStr(asMap(sRaw)['id']) == 'credit');
