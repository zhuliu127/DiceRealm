// ============================================================
// card_transfer_io.dart — 导入/导出的**平台传输层**
//
// 纯逻辑（JSON 形状、id 重分配、错误文案）在 `repo/card_transfer.dart`；
// 这里只负责「把字符串交出去 / 把字符串拿回来」这一件事，抽成接口是为了：
//   1. widget 测试跑在 fake-async 区域里，插件调用（分享面板 / 文件选择器）
//      永远不会返回，整条用例会挂死 —— 必须能换成假实现；
//   2. 分享面板与文件选择器都是平台通道，单测环境没有。
//
// 导出走 `share_plus`（系统分享面板：存到文件 / 发微信 / 发邮件都行），
// 同时会在应用文档目录 `dice_realm/exports/` 留一份副本 —— 玩家从
// 「没有装文件管理器」的环境里也能把文件拷出来，且下次可在应用内看到记录。
// 导入走 `file_picker`。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 传输层接口
abstract class CardTransferIo {
  /// 导出：把 [json] 以 [fileName] 交出去。
  /// 返回「副本落在哪里」（拿不到路径时返回 null，不算失败）。
  Future<String?> export(String fileName, String json);

  /// 导入：让用户挑一个 .json 并返回其文本。用户取消返回 null。
  Future<String?> importText();
}

/// 全局传输层实例。测试可以在 `setUp` 里换成假实现（与 domain 的
/// `setRng` 同样是「可注入」的做法，理由一致：确定性 / 可测）。
CardTransferIo cardTransferIo = PlatformCardTransferIo();

/// 真实实现（share_plus + file_picker）
class PlatformCardTransferIo implements CardTransferIo {
  const PlatformCardTransferIo();

  @override
  Future<String?> export(String fileName, String json) async {
    // 1) 先落一份副本到应用文档目录（分享面板不可用时至少文件还在）
    String? copyPath;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
        '${docs.path}${Platform.pathSeparator}dice_realm'
        '${Platform.pathSeparator}exports',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(json, flush: true);
      copyPath = file.path;
    } catch (_) {
      // 副本失败不影响分享，继续走第 2 步
    }

    // 2) 走系统分享面板
    if (copyPath != null) {
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(copyPath)], subject: fileName),
      );
    } else {
      // 没有可分享的文件时退化成文本分享（仍是同一份 JSON 内容）
      await SharePlus.instance.share(
        ShareParams(text: json, subject: fileName),
      );
    }
    return copyPath;
  }

  @override
  Future<String?> importText() async {
    // file_picker 13 的 API 是静态方法 + `PlatformFile.readAsBytes()`
    // （旧版的 `FilePicker.platform.pickFiles(withData: true)` 已经不存在）
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择角色卡 JSON',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}
