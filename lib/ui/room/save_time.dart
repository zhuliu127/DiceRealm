// ============================================================
// save_time.dart — 存档时间展示（纯函数，零 Flutter 依赖）
//
// 续玩列表（room_entry_page）与存档槽弹层（sheet_save_slots）共用同一套
// 时间文案，避免两处各写一份、格式漂移。
//
// ★ 只用本地时区：玩家看到的应该是「自己手机的钟」。
// ★ 同年只到 `MM-dd HH:mm`，省地方（列表副标题是 11px 单行）；
//   跨年才补年份，免得把去年的存档看成昨天的。
// ============================================================

/// 存档时间展示：毫秒 → `MM-dd HH:mm`（同年）/ `yyyy-MM-dd HH:mm`（跨年）。
///
/// `savedAtMs` 为 0 / 负数 / 超出 [DateTime] 可表示范围时返回 `'—'`。
/// [now] 可注入，便于测试固定「今年」；默认取本机当前时间。
String saveTimeText(int savedAtMs, {DateTime? now}) {
  if (savedAtMs <= 0) return '—';
  final DateTime at;
  try {
    at = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
  } catch (_) {
    return '—';
  }
  final DateTime today = now ?? DateTime.now();
  String two(int v) => v < 10 ? '0$v' : '$v';
  final String md = '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  if (at.year == today.year) return md;
  return '${at.year}-$md';
}
