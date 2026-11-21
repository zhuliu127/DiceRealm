package com.teaegg.dice_realm

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity —— 只干一件事：提供 Android 多播锁。
 *
 * 为什么需要：Android 的 WiFi 省电模式会丢弃广播与多播包。不做这一步，
 * 两台真机连同一个 WiFi 时「界面都说局域网已开，但互相搜不到房间」，
 * 而模拟器与桌面环境永远暴露不出这个问题（它们的网络栈不省电）。
 *
 * Dart 侧见 `lib/net/multicast_lock.dart`（带引用计数，广播器与扫描器
 * 各持一层、严格配对释放）。
 *
 * 注意：这里的锁**不做引用计数**（`setReferenceCounted(false)`），
 * 因为 Dart 侧已经数过层了 —— 两边都数会互相打架，谁先释放谁出错。
 */
class MainActivity : FlutterActivity() {

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> result.success(acquireLock())
                    "release" -> {
                        releaseLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // Activity 销毁时一定要放：留一层锁会让系统持续不允许省电，白耗电。
        releaseLock()
        super.onDestroy()
    }

    private fun acquireLock(): Boolean {
        multicastLock?.let { return true } // 已经持有
        return try {
            val wifi = applicationContext
                .getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return false
            val lock = wifi.createMulticastLock(LOCK_TAG)
            // Dart 侧已有引用计数，这里不再叠加。
            lock.setReferenceCounted(false)
            lock.acquire()
            multicastLock = lock
            true
        } catch (e: Exception) {
            // 权限缺失或 WiFi 未开：静默降级。
            // 广播可能收不到，但建房/加入不能因此失败（手输地址始终可用）。
            false
        }
    }

    private fun releaseLock() {
        try {
            multicastLock?.release()
        } catch (_: Exception) {
            // 已释放过，忽略。
        }
        multicastLock = null
    }

    companion object {
        private const val CHANNEL = "dice_realm/multicast"
        private const val LOCK_TAG = "dice_realm_lan"
    }
}
