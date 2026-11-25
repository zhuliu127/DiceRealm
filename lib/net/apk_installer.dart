// ============================================================
// apk_installer.dart — 调起系统安装器的 Dart 侧薄壳
//
// Android 没有「静默装自己的新版本」这种能力（除非是系统应用），
// 唯一合规的路是把已下载的 apk 交给系统安装器（Intent.ACTION_VIEW +
// application/vnd.android.package-archive），由用户点「安装」确认。
//
// 原生侧在 MainActivity.kt 的 `dice_realm/app_update` 通道里实现：
//   · installApk(path)  把 File 包成 content:// FileProvider URI 再起 Intent；
//     返回 true=已拉起安装器 / false=没拉起（通常用户未授权「安装未知应用」）。
//   · canRequestInstall() 当前是否已允许本应用「安装未知应用」。
//   · openUnknownSourcesSettings() 跳到系统的「安装未知应用」授权页。
//
// 桌面 / 测试环境（无该通道）时全部降级为 false，不崩。
// ============================================================

import 'package:flutter/services.dart';

class ApkInstaller {
  const ApkInstaller();

  static const MethodChannel _channel = MethodChannel(
    'dice_realm/app_update',
  );

  /// 是否已允许本应用安装未知来源应用（Android 8+ 的「安装未知应用」单独授权）。
  Future<bool> canRequestInstall() async {
    try {
      final res = await _channel.invokeMethod<bool>('canRequestInstall');
      return res ?? false;
    } on MissingPluginException {
      return false; // 桌面 / 测试：无原生通道
    } on PlatformException {
      return false;
    }
  }

  /// 拉起系统安装器；返回是否成功拉起。
  Future<bool> installApk(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('installApk', <String, Object?>{
        'path': filePath,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 跳到系统「安装未知应用」授权页。返回是否跳成功。
  Future<bool> openUnknownSourcesSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openUnknownSourcesSettings');
      return res ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
