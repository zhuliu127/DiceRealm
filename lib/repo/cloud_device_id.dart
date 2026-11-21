// ============================================================
// repo/cloud_device_id.dart — P20 稳定设备标识端口（N1）
//
// ★ 为什么需要这一层：
//   既有 `ensureCloudDeviceId()`（`cloud_room.dart`）用进程内 `math.Random()`
//   生成 `fl-` 设备码，App 重启即变 → 服务端 `device_seats` 绑定失效，
//   玩家「永远回不去原座」。本文件把「生成 / 校验 / 持久化」抽成端口，
//   生产在 `main()` 注入 [FileDeviceIdStorage]（写到与凭据同目录的
//   `.room_credentials/device_id.txt`），flutter test 保持内存实现零 I/O。
//
// ★ 安全口径（与 recent_room_credential.dart 一致）：
//   1. 只存一份不含任何用户信息的随机码；与 `room_saves` 存档目录严格分离；
//   2. 绝不 import 任何 domain 存档打包函数，绝不写 print / 日志；
//   3. 构造期零 I/O，读 / 写失败一律静默 —— 设备码是「锦上添花」，
//      拿不到就退回进程内随机，绝不拖垮建房 / 加入 / 续玩主流程。
//
// ★ 格式：`fl-` + 16 位小写 hex（沿用既有口径，服务端 `clean_device_id`
//   只做控制字符过滤 + 80 字截断，本格式天然通过）。
// ============================================================

import 'dart:io';
import 'dart:math' as math;

/// 稳定设备标识的合法格式：`fl-` + 16 位小写十六进制。
final RegExp _kDeviceIdPattern = RegExp(r'^fl-[0-9a-f]{16}$');

/// 校验一个候选设备标识；不合法（含空串）返回 false。
bool isValidDeviceId(String id) => _kDeviceIdPattern.hasMatch(id);

/// 用密码学安全随机源生成一个符合 [isValidDeviceId] 的新标识。
String newStableDeviceId() {
  final math.Random r = math.Random.secure();
  final StringBuffer b = StringBuffer('fl-');
  for (var i = 0; i < 16; i++) {
    b.write(r.nextInt(16).toRadixString(16));
  }
  return b.toString();
}

/// 设备标识存储端口（可注入，便于测试与替换落盘目录）。
abstract class DeviceIdStorage {
  /// 读取已持久化的设备标识；不存在 / 损坏 / 读盘异常一律返回 ''。
  String read();

  /// 写入设备标识；原子替换，失败静默。
  void write(String id);
}

/// 默认实现：进程内内存。零 I/O，flutter test 下不会挂，也绝不误写盘。
class MemoryDeviceIdStorage implements DeviceIdStorage {
  MemoryDeviceIdStorage([this._value = '']);

  String _value;

  @override
  String read() => _value;

  @override
  void write(String id) {
    _value = id;
  }
}

/// 独立私有文件实现：单文件 `device_id.txt`，原子写（.tmp → copy）。
///
/// [dir] 必须由调用方给应用私有目录（与 `recent_rooms.json` 同目录、
/// **不同文件**）；构造期绝不自作主张去找全局目录，也不做任何 I/O。
class FileDeviceIdStorage implements DeviceIdStorage {
  FileDeviceIdStorage(this.dir);

  final Directory dir;

  File get _file =>
      File('${dir.path}${Platform.pathSeparator}device_id.txt');

  @override
  String read() {
    try {
      final File f = _file;
      if (!f.existsSync()) return '';
      return f.readAsStringSync().trim();
    } catch (_) {
      // 坏文件 / 权限问题不拖垮主流程：当作「没有设备码」。
      return '';
    }
  }

  @override
  void write(String id) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final File f = _file;
      final File tmp = File('${f.path}.tmp');
      tmp.writeAsStringSync(id, flush: true);
      tmp.copySync(f.path);
      try {
        tmp.deleteSync();
      } catch (_) {
        // tmp 删不掉不影响正确性，下次 write 会覆盖它。
      }
    } catch (_) {
      // 写盘失败静默：设备码是辅助能力，绝不拖垮主流程。
    }
  }
}

/// 全局可替换的存储后端。生产在 `main()` 注入 [FileDeviceIdStorage]。
/// 未注入时保持内存实现 —— flutter test 零 I/O、绝不误写盘。
DeviceIdStorage deviceIdStorage = MemoryDeviceIdStorage();
