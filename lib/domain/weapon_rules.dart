// ============================================================
// weapon_rules.dart — 武器数值的**校验口径**（纯 Dart，供 UI 复用）
//
// 朋友 bug 1：自定义武器的「故障值」可以填 100 / 120 / -1 ——
//   CoC 7e 的故障值语义是「掷 D100 ≥ 该值时武器卡壳」，合法区间 1–99；
//   100（或不填）在规则表里写作「——」，表示**该武器不会故障**。
//   表单以前完全不校验，玩家能存进 500 这种永不卡壳的枪。
//
// 这里的口径与 `data/weapons.dart` 的官方武器表一致：
//   · `'——'` / 空 → 合法（近战武器与部分枪械本来就不故障）；
//   · 纯数字 → 必须 1..99 的整数；
//   · 其余（负数 / 小数 / 字母）→ 非法。
// 伤害 / 射程 / 次数是自由文本（`1D10+2`、`20/50`），不做数字校验，
// 但提供上限长度与空白提示，避免把整段 JSON 粘进去。
// ============================================================

/// 故障值下限（含）。
const int weaponMalfunctionMin = 1;

/// 故障值上限（含）。CoC 7e 里 100 表示「不会故障」，账号里写作「——」。
const int weaponMalfunctionMax = 99;

/// 官方武器表里「不会故障」的占位符。
const String weaponNoMalfunction = '——';

/// 校验故障值。合法返回 null，否则返回给玩家看的中文文案。
String? weaponMalfunctionError(String raw) {
  final t = raw.trim();
  // 空 / 官方占位符 = 该武器不会故障，合法。
  if (t.isEmpty || t == weaponNoMalfunction) return null;
  if (!RegExp(r'^\d+$').hasMatch(t)) {
    return '故障值必须是 $weaponMalfunctionMin-$weaponMalfunctionMax 的整数';
  }
  final v = int.parse(t);
  if (v < weaponMalfunctionMin || v > weaponMalfunctionMax) {
    return '故障值必须在 $weaponMalfunctionMin-$weaponMalfunctionMax 之间'
        '（$weaponMalfunctionMax 以上表示不会故障，请留空或填「$weaponNoMalfunction」）';
  }
  return null;
}

/// 规范化故障值：合法值去空格，空值保留空串（不写「——」以免脏数据）。
String normalizeWeaponMalfunction(String raw) => raw.trim();

/// 武器名 / 伤害 / 射程这类自由文本的通用长度闸门（防止粘整段 JSON）。
String? weaponTextFieldError(String raw, {required String label, int maxLen = 40}) {
  if (raw.trim().length > maxLen) return '$label 不能超过 $maxLen 个字符';
  return null;
}
