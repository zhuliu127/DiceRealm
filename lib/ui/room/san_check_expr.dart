// ============================================================
// san_check_expr.dart — SAN Check 表达式解析（P12 / 第 9 期 · PL-2）
//
// 纯 Dart：零 Flutter 依赖、零权威端引用，便于 QA 表驱动单测。
// 载荷键名 `okLoss` / `loss` 与 `sheet_dice_tools.dart:136-142` 的
// `RoomIntent.sanCheck` 调用点逐字对齐；合法性终判仍由权威端
// `settleSanCheck` / `rules.parseSanLoss` 负责，本类只做输入容错 + 归一。
//
// ★ 权威性：本文件不改规则函数、不新增 action / 事件 / 意图。
// ============================================================

/// SAN Check 表达式：成功扣值 / 失败扣值。
class SanCheckExpr {
  const SanCheckExpr(this.okLoss, this.loss);

  /// 成功时的扣值（如 `'2'`，也接受骰式 `'1D3'`）。
  final String okLoss;

  /// 失败时的扣值（骰式，如 `'1D6'`，统一大写 `D`）。
  final String loss;

  /// 单段合法：正整数，或 `NdM` / `NdM+K` 的骰式（N / M / K 均 ≥ 1）。
  ///
  /// 刻意不接受：负数 / 0 / 空串 / 字母 / 多个 `/` / 多段骰式。
  /// 这样 `-1/1d6`、`2/`、`abc`、`2/1d6/3` 一律在 UI 侧就被判非法。
  static final RegExp _segment = RegExp(
    r'^[1-9][0-9]*(?:[dD][1-9][0-9]*(?:\+[1-9][0-9]*)?)?$',
  );

  /// 容错解析：`2/1d6` / `2/1D6` / `2 / 1d6`（大小写、`/` 两侧空格）。
  ///
  /// 非法（`abc` / `2/` / `-1/1d6` / `/1d6` / 空 / 缺任一段 / 多段）→ null。
  /// 成功时把骰子分隔符统一成大写 `D`，其余字符原样保留。
  static SanCheckExpr? parse(String raw) {
    if (raw.trim().isEmpty) return null;
    final List<String> parts = raw.split('/');
    if (parts.length != 2) return null;
    final String ok = parts[0].trim();
    final String loss = parts[1].trim();
    if (ok.isEmpty || loss.isEmpty) return null;
    if (!_segment.hasMatch(ok) || !_segment.hasMatch(loss)) return null;
    return SanCheckExpr(_normalize(ok), _normalize(loss));
  }

  /// 骰子分隔符统一大写 `D`（权威端同口径）。
  static String _normalize(String s) => s.replaceAll('d', 'D');

  /// → `RoomIntent.sanCheck` 载荷，键名与 `sheet_dice_tools.dart` 一致。
  Map<String, Object?> toIntentPayload() => <String, Object?>{
        'okLoss': okLoss,
        'loss': loss,
      };
}
