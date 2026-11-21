// ============================================================
// room_legacy_migrate.dart — K4 旧存档明文脱敏迁移（纯函数、零 I/O）
//
// 背景（PRD §9.2）：旧版 buggy rollback 重放时丢 `vis/to`（P4 Q1 已修），
// 旧存档 `logs` 里可能存在**明文秘密检定行**；`playerViewFromSave` 会原样
// 透传。合规的脱敏行恒为
//   `{seat:'', text:'KP 秘密进行了一次检定', redacted:true}`
// （room_model_reduce.dart:227-235），明文行只可能来自 Q1 缺陷重放。
//
// ⚠️ 本文件在 lib/domain 下，必须保持**纯 Dart**：
//    不得依赖 Flutter 框架，也不得做任何平台 I/O 或 UI 绘制。
//    零文件读写，只做 Map → Map 变换。
// ⚠️ 不改 `room_model_save.dart`（P4 冻结文件）；落点由 T05/S5.5 接线：
//    载入 → migrateLegacySave → adoptSave → 一次性提示。
// ============================================================

import 'js_compat.dart';
import 'room_model_state.dart' show roomClone;

/// 迁移结果。`save` 是**深拷贝后**的存档（入参绝不被改），`migrated` 是
/// 命中并改写了几条；0 表示无需迁移（也用于断言幂等）。
class LegacyMigrateResult {
  const LegacyMigrateResult({required this.save, required this.migrated});

  final Map<String, Object?> save;
  final int migrated;

  /// 是否发生了脱敏（>0 条）。
  bool get changed => migrated > 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'save': save,
        'migrated': migrated,
      };
}

/// K4 命中条件（保守，只打真缺陷产物）：
///   `log.kind == 'check' && log.opp == null && log.seat != ''`
///   `&& log.text 含「秘密检定」`
///
/// 命中后**就地改写这一行**（在深拷贝的副本里）：
///   `seat:''`、`text:'KP 秘密进行了一次检定'`、`redacted:true`；
///   **保留** `seq` / `at` / `kind` 及所有其余键（不打乱时间轴、不动水位）。
///
/// 幂等：已脱敏行 `seat == ''` → 不命中；重复导入零变化。
/// 公开检定（`opp != null` 或 text 不含「秘密检定」）不命中。
LegacyMigrateResult migrateLegacySave(Map<String, Object?> save) {
  final copy = asMap(roomClone(save));
  final logs = asList(copy['logs']);
  final outLogs = <Object?>[];
  var migrated = 0;

  for (final raw in logs) {
    final row = asMap(raw);
    final next = asMap(roomClone(row));
    if (_isLegacyPlaintext(row)) {
      next['seat'] = '';
      next['text'] = 'KP 秘密进行了一次检定';
      next['redacted'] = true;
      migrated += 1;
    }
    outLogs.add(next);
  }

  // 只有确实存在 logs 键时才写回，避免给一份不含 logs 的存档凭空加键。
  if (save.containsKey('logs')) {
    copy['logs'] = outLogs;
  }
  return LegacyMigrateResult(save: copy, migrated: migrated);
}

/// 单条日志是否命中 K4 明文缺陷产物。
bool _isLegacyPlaintext(Map<String, Object?> row) {
  if (jsStr(row['kind'] ?? '') != 'check') return false;
  // `opp == null` 包含「键不存在」与「显式 null」两种旧存档形状。
  if (row['opp'] != null) return false;
  final seat = row['seat'];
  // 合规脱敏行 seat 恒为 ''；null 也按空处理（保守，不误伤）。
  if (seat == null || jsStr(seat).isEmpty) return false;
  return jsStr(row['text'] ?? '').contains('秘密检定');
}
