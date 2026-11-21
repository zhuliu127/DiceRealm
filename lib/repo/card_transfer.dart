// ============================================================
// card_transfer.dart — 角色卡的导入 / 导出（纯逻辑，无 UI、无平台依赖）
//
// 逐字对齐旧版 `core/store.js#exportCharacter / importCharacter` 与
// `app.js#exportAll`：
//
//   单卡：JSON.stringify({ format:'coc7-card',   version:1, data: c },        null, 2)
//   全量：JSON.stringify({ format:'coc7-bundle', version:1, characters: [...] }, null, 2)
//
// ⚠️ 这是老角色**唯一的搬家通道**，所以格式一个字都不能"优化"：
//   键名、键序、缩进（2 空格）、是否转义中文，全部照抄。
//   老卡能直接读进来 = 兼容性保住了；多一个自己发明的键 = 老版本读不回去。
//
// ⚠️ 导入必须**重新分配 id**（旧版同款行为）：导入是「再拿一份」，
//   不是「覆盖原卡」。否则从朋友那里拿到的卡会把本机同名 id 的卡顶掉。
// ============================================================

import 'dart:convert';

import '../domain/character.dart';
import '../domain/js_compat.dart';
import 'character_repo.dart';

/// 单卡存档的外层标记（与旧版一致，勿改）
const String cardExportFormat = 'coc7-card';
const int cardExportVersion = 1;

/// 全量存档的外层标记（与旧版 `app.js#exportAll` 一致，勿改）
const String bundleExportFormat = 'coc7-bundle';
const int bundleExportVersion = 1;

/// 导出缩进：`JSON.stringify(x, null, 2)`
const String _indent = '  ';

/// 单卡导出（对应 `Store.exportCharacter`）。
///
/// 返回的字符串可以直接喂给 [parseCardImport] 或旧版 `Store.importCharacter`。
String exportCardJson(Character card) {
  return _encode(<String, Object?>{
    'format': cardExportFormat,
    'version': cardExportVersion,
    'data': card.raw,
  });
}

/// 全量导出（对应 `app.js#exportAll`）。
///
/// [cards] 的顺序即最终顺序（旧版传的是 `Store.listCharacters()`，
/// 按 updatedAt 倒序 —— 调用方负责按同一口径排序）。
String exportBundleJson(List<Character> cards) {
  return _encode(<String, Object?>{
    'format': bundleExportFormat,
    'version': bundleExportVersion,
    'characters': cards.map((c) => c.raw).toList(),
  });
}

/// 与 `JSON.stringify(v, null, 2)` 同形的编码。
///
/// 用 [JsonEncoder.withIndent] 而不是手写：它对 Map / List / String / num
/// 的输出与 JS 逐字一致（2 空格缩进、不转义中文、键序按插入序）。
String _encode(Object? value) =>
    const JsonEncoder.withIndent(_indent).convert(value);

/// 导入失败：带一句**人话**（界面直接显示，不许静默吞掉）
class CardImportError implements Exception {
  CardImportError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次导入解析出来的结果
class CardImportResult {
  const CardImportResult({required this.cards, required this.bundle});

  /// 待导入的原始卡片（**未** normalize；由 [importIntoRepo] 统一处理）
  final List<Map<String, Object?>> cards;

  /// 是否来自全量存档（`{format:'coc7-bundle', characters:[...]}`）
  final bool bundle;

  int get count => cards.length;
}

/// 解析导入文本。
///
/// 接受三种形状（旧版只认前两种，第三种是全量导出文件的自然回读）：
///   1. `{format:'coc7-card', version:1, data:{...}}`
///   2. 裸角色对象 `{characterName:..., ...}`
///   3. `{format:'coc7-bundle', version:1, characters:[{...}, {...}]}`
///
/// 校验口径与旧版一致：`characterName` 或 `id` 至少有一个。
/// 失败抛 [CardImportError]（文案可直接显示给用户）。
CardImportResult parseCardImport(String text) {
  final raw = text.trim();
  if (raw.isEmpty) throw CardImportError('导入内容为空：请选择旧版导出的 .json 文件');

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (e) {
    throw CardImportError('不是合法的 JSON 文件：$e');
  }
  if (decoded is! Map) {
    throw CardImportError('格式不正确：文件顶层必须是对象（旧版导出的是单个 JSON 对象）');
  }

  final obj = Map<String, Object?>.from(decoded);
  final bundle = obj['characters'];
  if (bundle is List) {
    final cards = <Map<String, Object?>>[];
    for (final item in bundle) {
      if (item is! Map) continue;
      final card = Map<String, Object?>.from(item);
      _requireIdentifiable(card);
      cards.add(card);
    }
    if (cards.isEmpty) throw CardImportError('全量存档里没有可导入的角色卡');
    return CardImportResult(cards: cards, bundle: true);
  }

  // `obj.data || obj` —— 与旧版逐字一致
  final data = obj['data'];
  final card = (data is Map) ? Map<String, Object?>.from(data) : obj;
  _requireIdentifiable(card);
  return CardImportResult(cards: <Map<String, Object?>>[card], bundle: false);
}

void _requireIdentifiable(Map<String, Object?> card) {
  final name = jsStr(card['characterName'] ?? '');
  final id = jsStr(card['id'] ?? '');
  if (name.trim().isEmpty && (card['id'] == null || id.isEmpty)) {
    throw CardImportError('格式不正确：这张卡既没有 characterName 也没有 id');
  }
}

/// 给导入的卡分配一个**不冲突**的新 id（旧版 `c.id = uid()` 的同款语义，
/// 多了一道「别撞上已有卡」的保护 —— 旧版 8 位随机撞车概率虽低，
/// 但一旦撞上就是**覆盖掉本机一张卡**，代价太大）。
Map<String, Object?> assignFreshId(
  Map<String, Object?> raw, {
  required Set<String> takenIds,
}) {
  final copy = _deepCopyMap(raw);
  var id = uid();
  var guard = 0;
  while (takenIds.contains(id) && guard++ < 64) {
    id = uid();
  }
  copy['id'] = id;
  return copy;
}

/// 导入到仓库：解析 → 换 id → normalize + recalc → 落盘。
///
/// 返回导入进去的卡片。失败抛 [CardImportError]。
Future<List<Character>> importIntoRepo(CharacterRepo repo, String text) async {
  final result = parseCardImport(text);
  final taken = repo.all.map((c) => c.id).toSet();
  final out = <Character>[];
  for (final raw in result.cards) {
    final withId = assignFreshId(raw, takenIds: taken);
    // ⚠️ 这里**不做 normalize**：`repo.save` 本来就会 normalize，而提前 normalize
    // 会把缺失的状态键补成 0（`currentHP: 0`），让「显式存在的值才标记」这条语义
    // 失效 —— 老卡本来没有 currentHP 键，补成 0 再标记就会被当成「用户把血打到 0」
    // 而永远补不回来（QA 的 D1 反面用例）。
    final card = Character(withId);
    taken.add(card.id);
    await repo.save(card);
    out.add(card);
  }
  return out;
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> src) {
  final out = <String, Object?>{};
  src.forEach((k, v) => out[k] = _deepCopy(v));
  return out;
}

Object? _deepCopy(Object? v) {
  if (v is Map) {
    final out = <String, Object?>{};
    v.forEach((k, val) => out[jsStr(k)] = _deepCopy(val));
    return out;
  }
  if (v is List) return v.map(_deepCopy).toList();
  return v;
}
