// ============================================================
// secret_mask.dart — 敏感信息脱敏（纯 Dart，零依赖）
//
// `aiKey` 是唯一一个「误打进日志就等于泄密」的字段。所以打码逻辑必须只有
// 一份实现，并且被所有可能把 Key 拼进字符串的地方复用：
//   · 设置页展示（`maskedAiKey`）
//   · 异常 / 错误消息（HTTP 库有时会把请求头拼进异常文本）
//   · 任何 `print(settings)` 的替代品（`SettingsRepo.describe()`）
//
// 放在 domain 而不是 repo：`lib/net/*` 也要用，而 net 不该反向依赖 repo。
// ============================================================

/// API Key 脱敏：前 4 + 后 4。
///
/// 短 Key（≤8 位）只留前 2 位 —— 否则「留前4后4」等于把原样打出来。
String maskApiKey(String key) {
  final k = key.trim();
  if (k.isEmpty) return '';
  if (k.length <= 8) return '${k.substring(0, k.length >= 2 ? 2 : 1)}****';
  return '${k.substring(0, 4)}****${k.substring(k.length - 4)}';
}

/// 把任意字符串里可能出现的 API Key 打码。
///
/// 用在异常消息上：某些 HTTP 库会把请求头（含 `Authorization: Bearer ...`）
/// 拼进异常文本，直接显示就等于把 Key 打在了界面上。
String maskSecrets(String text) {
  var out = text;
  out = out.replaceAllMapped(
    RegExp(r'(Bearer\s+)([A-Za-z0-9._\-]{8,})'),
    (m) => '${m.group(1)}${maskApiKey(m.group(2)!)}',
  );
  out = out.replaceAllMapped(
    RegExp(r'\b(sk-[A-Za-z0-9._\-]{6,})'),
    (m) => maskApiKey(m.group(1)!),
  );
  return out;
}
