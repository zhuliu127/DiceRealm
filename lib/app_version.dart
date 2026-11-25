// ============================================================
// app_version.dart — 应用版本号的**单一真源**
//
// 为什么不引 `package_info_plus`：
//   `pubspec.yaml` 是冻结区（加插件要重新过一次原生构建风险），而版本号
//   只需要「一个能被读到、且写死就够」的字符串。所以这里放常量，
//   再写一条测试去读 `pubspec.yaml` 逐字比对 —— 谁改了 pubspec 忘改这里，
//   测试会立刻红，比引插件更省且更硬。
//
// ⚠️ 升级版本时**两处一起改**：`pubspec.yaml` 的 `version:` 与本文件。
//    `test/app_version_test.dart` 会验证两者一致。
// ============================================================

/// 语义化版本（对应 pubspec 里 `+` 之前的部分）
const String kAppVersion = '2.49.2';

/// 构建号（对应 pubspec 里 `+` 之后的部分）
const int kAppBuildNumber = 124;

/// 展示用短标签：`v<版本>`
const String kAppVersionShort = 'v$kAppVersion';

/// 展示用完整标签：`v<版本> (<构建号>)`
const String kAppVersionLabel = 'v$kAppVersion ($kAppBuildNumber)';

/// 应用中文名（多处复用，避免各页面写死不一致）
const String kAppTitle = '骰境TRPG';
