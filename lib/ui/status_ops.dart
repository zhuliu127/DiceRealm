// ============================================================
// status_ops.dart — 状态管理的**写入通道**（纯 Dart，无 BuildContext）
//
// 为什么要有这一层：`lib/domain` 在本期被冻结（只允许改 uid()），但旧版
// 状态管理里有三条**必须落到数据层**的语义，UI 不能各写一遍：
//
//   1) 清空输入 ≠ 0（v2.1.8 用户第 3 项）：删掉输入框里的数字只代表
//      「还没提交」，绝不能把角色判成归零撕卡。
//   2) 「用户直接改过」标记（`_hpTouched / _mpTouched / _sanTouched /
//      _luckTouched`，P0 报告坑 B）：`recalc()` 里有一条
//      「HP 为 0 且没被手动改过 → 补满」的兜底初始化；如果不打标记，
//      玩家把 HP 改成 0、保存时 recalc 会**把濒死角色治活**。
//   3) 撕卡判定（`app.js#statusSheet / ripPending / commit`）：
//      HP（或上限）归零 → 死亡；SAN（或上限）归零 → 永久疯狂；
//      两者都要玩家二次确认，且只有确认后才写入。
//
// 这些函数只碰**已有的键**（status.* / sanLoss / madness），不新增任何
// 卡片键名 —— `_hpTouched` 等标记是旧版就有的键，normalize 已经在维护
// `_inited / _luckTouched`，属于既有契约的一部分。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/madness.dart' as mad;
import 'package:dice_realm/domain/madness_state.dart' as ms;
import 'package:dice_realm/domain/rules_coc7.dart';

/// 状态数字字段 → 它的「用户直接改过」标记（与旧版逐字一致，勿改名）
const Map<String, String> statusTouchedKeys = <String, String>{
  'currentHP': '_hpTouched',
  'currentMP': '_mpTouched',
  'currentSAN': '_sanTouched',
  'currentLuck': '_luckTouched',
};

/// 状态数字字段 → 它的上限字段（null 表示硬上限 99）
const Map<String, String?> statusMaxKeys = <String, String?>{
  'currentHP': 'maxHP',
  'currentMP': 'maxMP',
  'currentSAN': 'maxSAN',
  'currentLuck': null,
};

/// 某个状态字段当前允许的上限
int statusMaxOf(Character c, String field) {
  final maxKey = statusMaxKeys[field];
  if (maxKey == null) return 99;
  final max = jsNum(c.status[maxKey]);
  return max <= 0 ? 0 : max;
}

/// 提交一个「输入框暂存值」到状态。
///
/// 语义与旧版 `numField.oninput` 一致：
///   · 空串 / 纯空白 → **什么都不写**（清空 ≠ 0），返回 false
///   · 非数字        → **什么都不写**，返回 false
///   · 合法数字（含 0）→ clamp 到 `0..上限` 后写入，并打上「用户改过」标记
///
/// 返回是否真的写入了模型。调用方据此决定要不要 recalc / 重绘。
bool commitStatusNumber(Character c, String field, String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final parsed = jsParseInt(text);
  if (parsed == null) return false;
  final max = statusMaxOf(c, field);
  final value = clamp(parsed, 0, max);
  c.status[field] = value;
  final touched = statusTouchedKeys[field];
  if (touched != null) c.status[touched] = true;
  return true;
}

/// 程序化写入（「归零」按钮 / 导入与外部回写的标记通道）。
///
/// 与 [commitStatusNumber] 的区别：值已经确定，一定要写进去；
/// 同样会打「用户改过」标记 —— 这正是「濒死角色不得被 recalc 治活」的保证。
///
/// **谁在调**（D1 修复后不再是死代码）：
///   · `lib/ui/card_edit/status_editor.dart` 的「清零 / 归零」按钮
///   · `lib/repo/character_repo.dart#save` → [applyExplicitStatusMarks]（每次落盘前）
///     —— 覆盖「导入 / 房间外部回写」这两条**不经过输入框**的路径
///   · 单元测试直接调它验证通道语义
///
/// **什么时候调**：写入的值必须来自「玩家真的确认过」的语义（输入框提交、
/// 外部 JSON 里显式存在的状态值、或 UI 上的归零操作）。批量标记请走
/// [applyExplicitStatusMarks]，别在别处自己 `status[k]=v` 绕开标记。
void setStatusNumber(Character c, String field, int value) {
  final max = statusMaxOf(c, field);
  c.status[field] = clamp(value, 0, max);
  final touched = statusTouchedKeys[field];
  if (touched != null) c.status[touched] = true;
}

/// 把「JSON 里**显式存在**、且会被 recalc 覆盖掉」的状态值走一遍写入通道。
///
/// 为什么必须有这一层（QA 的 D1）：
///   `engine.dart` 的 recalc 有三行补值守卫 ——
///   `if (ready && currentHP == 0 && !_hpTouched) currentHP = maxHP;`
///   它们存在是为了「属性刚填好时初始化血量」，但**导入一张 HP=0 的濒死卡**
///   时会被误判成「还没初始化」，于是把卡治活。整条链路上只有输入框路径
///   （[commitStatusNumber]）会打 `_hpTouched`，导入 / 房间回写没有任何标记点。
///   domain 不能在 recalc 里改（P0 冻结 + 反面测试依赖那三行），所以标记点
///   只能放在**写库入口**：`CharacterRepo.save`。
///
/// 语义：**只标注那些「不标记就会被 recalc 改掉」的显式值**，不是无差别全标 ——
///   · `currentHP / currentMP / currentSAN`：值为 0 时必须标记（否则补满）；
///     非 0 的值 recalc 只会做 `clamp(0, max)`，不会凭空改，无需标记。
///   · `currentLuck`：与 LUCK 属性不相等时说明是玩家改过的，标记后保留；
///     相等时不标记（recalc 会写回同一个值，且保留「幸运跟随属性」的旧语义）。
///   · `status` 里**根本没有**这个键 → 一律不标记（新卡 / 老卡按旧版语义补满）。
void applyExplicitStatusMarks(Character c) {
  final st = c.status;
  for (final field in <String>['currentHP', 'currentMP', 'currentSAN']) {
    if (!st.containsKey(field)) continue;
    final v = jsParseInt(st[field]);
    if (v == null) continue;
    if (v == 0) setStatusNumber(c, field, 0);
  }
  if (st.containsKey('currentLuck')) {
    final v = jsParseInt(st['currentLuck']);
    if (v != null && v != clamp(jsNum(c.attributes['luck']), 0, 99)) {
      setStatusNumber(c, 'currentLuck', v);
    }
  }
}

/// 输入框里的值与模型值是否**数值等价**（不看字面）。
///
/// `'007'` / `' 7 '` / `'+7'` 与 7 等价 —— 否则玩家把 `7` 改成 `007`
/// 会被判成「改过」，顺手打上 `_luckTouched`，幸运从此不再跟随属性（QA 的 D4）。
bool statusTextEquals(String raw, Object? model) {
  final text = raw.trim();
  final a = jsParseInt(text);
  final b = jsParseInt(model);
  if (a == null || b == null) return text == jsStr(model);
  return a == b;
}

/// SAN 上限的永久减损（施放神话法术 / 接触神话生物）。0-99，写入后 recalc
/// 会把它折算进 `status.maxSAN`。
void setSanLoss(Character c, int loss) {
  c.raw['sanLoss'] = clamp(loss, 0, 99);
  recalc(c);
}

/// 精神状态多选：点一个 chip 后的新数组。
///
/// 与旧版 `mentalSelect` 的互斥规则一致：
///   · 「正常」互斥：选它只留它
///   · 「永久疯狂」互斥（撕卡级）：选它只留它
///   · 「疯狂症状」是**派生项**，不由点击切换（它跟着背景 madness 走）
///   · P8：「不定疯狂」与「潜在疯狂」互斥（同时只能存在一个）
///   · 已废弃的取值（「昏迷」）点了不生效
///   · 取消后若空了，回落「正常」
List<String> toggleMental(Character c, String value) {
  final list = ms.normalizeMentalList(asList(c.status['mental']));
  final v = ms.normalizeMentalValue(value);
  if (v.isEmpty) return list; // 昏迷等已废弃取值：点击无效
  if (v == mentalSymptom) return list; // 派生项，点了也不改（由 UI 解释）
  if (v == mentalNormal) return <String>[mentalNormal];
  if (v == mentalPermanent) {
    return list.contains(mentalPermanent)
        ? <String>[mentalNormal]
        : <String>[mentalPermanent];
  }
  if (list.contains(v)) {
    final without = list.where((x) => x != v).toList();
    return without.isEmpty ? <String>[mentalNormal] : without;
  }
  final kept = list
      .where((x) => x != mentalNormal && x != mentalPermanent)
      // 互斥对：加一个就把另一个摘掉
      .where((x) => !(v == mentalIndefinite && x == mentalPotential))
      .where((x) => !(v == mentalPotential && x == mentalIndefinite))
      .toList();
  kept.add(v);
  return kept;
}

/// 写入精神状态（走 [toggleMental] 的规则），返回是否变化
bool applyMentalToggle(Character c, String value) {
  final before = asList(c.status['mental']).map(jsStr).toList();
  final after = toggleMental(c, value);
  if (before.length == after.length && before.join('|') == after.join('|')) return false;
  c.status['mental'] = after;
  return true;
}

/// 「保存时是否会被判定撕卡」—— 逐字对应旧版 `ripPending()`。
///
/// ⚠️ 这条判定**只看状态字段**，不产生任何副作用（输入路径只提示、不改状态）。
///   hpDown : 当前 HP ≤ 0 或 HP 上限 ≤ 0
///   sanDown: 当前 SAN ≤ 0 或 SAN 上限 ≤ 0
///   flagged: 已显式标记 body='死亡' 或 mental 含「永久疯狂」
class RipPending {
  const RipPending({
    required this.hpDown,
    required this.sanDown,
    required this.flagged,
  });

  final bool hpDown;
  final bool sanDown;
  final bool flagged;

  bool get hit => hpDown || sanDown || flagged;

  /// 给二次确认弹窗用的原因清单
  List<String> get reasons {
    final out = <String>[];
    if (hpDown) out.add('HP（或其上限）归零 → 死亡');
    if (sanDown) out.add('SAN（或其上限）归零 → 永久疯狂');
    if (!hpDown && !sanDown) out.add('已标记「死亡 / 永久疯狂」');
    return out;
  }

  /// 一句话提示（输入路径用，不涉及副作用）
  String get hint {
    if (hpDown && sanDown) return '当前 HP 与 SAN（或其上限）已达 0 —— 保存时将判定是否撕卡';
    if (hpDown) return '当前 HP（或其上限）已达 0 —— 保存时将判定是否撕卡（死亡）';
    if (sanDown) return '当前 SAN（或其上限）已达 0 —— 保存时将判定是否撕卡（永久疯狂）';
    if (flagged) return '已标记「死亡 / 永久疯狂」—— 保存时将写入撕卡';
    return '';
  }
}

/// 判定要素（不修改任何状态）
RipPending ripPending(Character c) {
  final st = c.status;
  final hpDown = jsNum(st['currentHP']) <= 0 || jsNum(st['maxHP']) <= 0;
  final sanDown = jsNum(st['currentSAN']) <= 0 || jsNum(st['maxSAN']) <= 0;
  final mental = asList(st['mental']).map(jsStr);
  final flagged = jsStr(st['body']) == '死亡' || mental.contains(mentalPermanent);
  return RipPending(hpDown: hpDown, sanDown: sanDown, flagged: flagged);
}

/// 玩家确认撕卡后，把判定写进卡片（旧版 `commit()` 前的两行）。
///
/// `hpDown → body='死亡'`；`sanDown → mental=['永久疯狂']`。
/// **不加不减**：`repo.isRippedCard` 的判据（body==='死亡' 或 mental 含
/// 「永久疯狂」）因此一字不动。
void applyRip(Character c, RipPending p) {
  if (p.hpDown) c.status['body'] = '死亡';
  if (p.sanDown) c.status['mental'] = <Object?>[mentalPermanent];
  recalc(c);
}

/// 身体状态的四个单值（v2.10.0 模型）+ 两个可叠加标记
const List<String> bodyStates = <String>['正常', '轻伤', '重伤', '死亡'];

/// 设置 body（只接受 [bodyStates] 里的值，防止写脏）
void setBody(Character c, String body) {
  c.status['body'] = bodyStates.contains(body) ? body : '正常';
  recalc(c);
}

/// 濒死 / 昏迷两个布尔标记（可与「重伤」叠加）
void setFlag(Character c, String key, bool value) {
  if (key != 'dying' && key != 'unconscious') return;
  c.status[key] = value;
  recalc(c);
}

/// 当前持有的疯狂症状条数（状态面板显示用）
int madnessCount(Character c) => mad.list(c).length;

/// 整个状态面板的「统一提交」：recalc + 撕卡判定。
///
/// 返回判定结果；调用方据此弹二次确认（确认后才调 [applyRip]）。
RipPending prepareStatusSave(Character c) {
  recalc(c);
  return ripPending(c);
}
