// ============================================================
// net/multicast_lock.dart — Android 多播锁
//
// 为什么需要它：Android 的 WiFi 省电模式会**丢弃广播与多播包**。
// 只在模拟器或开发机上测的话永远发现不了 —— 表现是「两台真机连同一
// 个 WiFi，界面都说局域网已开，但互相搜不到房间」。
//
// 修法是拿一个 `WifiManager.MulticastLock`（需要
// `CHANGE_WIFI_MULTICAST_STATE` 权限），持有期间系统不再过滤这些包。
//
// 设计要点：
//   · **引用计数**：广播器与扫描器都会 acquire，必须严格配对释放，
//     否则一方先结束就把另一方的锁撤了（症状是「扫描时能收到，一建房就收不到」）。
//   · **非 Android 一律 no-op**：`flutter test` 跑在桌面 VM 上，
//     `Platform.isAndroid` 为 false，直接返回 —— 测试不受影响，
//     也不需要为平台通道写替身。
//   · **失败不致命**：拿不到锁只说明「可能收不到广播」，
//     绝不能因此让建房/加入失败。手输服务地址始终是兜底。
// ============================================================

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;

/// Android 多播锁的 Dart 侧门面。
class MulticastLock {
  const MulticastLock._();

  static const MethodChannel _channel = MethodChannel('dice_realm/multicast');

  /// 当前持有层数（广播器 + 扫描器各自持有一层）。
  static int _refs = 0;

  /// 平台是否真的拿到了锁（拿不到时不要重复尝试）。
  static bool _held = false;

  /// 测试用：强制打开/关闭「像 Android 一样工作」的分支。
  ///
  /// 生产为 null（按 `Platform.isAndroid` 判断）。
  /// 单测里设成 true 才能验引用计数；跑完记得设回 null。
  @visibleForTesting
  static bool? debugForceSupported;

  static bool get _supported =>
      debugForceSupported ??
      (!kIsWeb && Platform.isAndroid);

  /// 是否已持锁（诊断/测试用）。
  static bool get held => _held;

  /// 当前引用层数（测试用）。
  @visibleForTesting
  static int get refCount => _refs;

  /// 拿一层锁。可重入（引用计数 +1）。
  ///
  /// 返回是否真的持有。非 Android 或平台调用失败时返回 false，
  /// **调用方不该因此改变业务行为**。
  static Future<bool> acquire() async {
    if (!_supported) return false;
    _refs++;
    if (_held) return true;
    try {
      final bool? ok = await _channel.invokeMethod<bool>('acquire');
      _held = ok ?? false;
    } catch (_) {
      // 平台通道不可用（例如被裁剪的引擎）：静默降级，广播可能收不到，
      // 但建房/加入不能因此失败。
      _held = false;
    }
    return _held;
  }

  /// 放一层锁。只有最后一层释放时才真的交给系统。
  static Future<void> release() async {
    if (!_supported) return;
    if (_refs > 0) _refs--;
    if (_refs > 0 || !_held) {
      // 还有别的持有者，或者本来就没拿到 —— 都不该调平台。
      if (_refs == 0) _held = false;
      return;
    }
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {
      // 同上：释放失败只是省电优化失效，不影响功能。
    }
    _held = false;
  }

  /// 测试用：把状态清回初始（避免用例之间串味）。
  @visibleForTesting
  static void debugReset() {
    _refs = 0;
    _held = false;
    debugForceSupported = null;
  }
}
