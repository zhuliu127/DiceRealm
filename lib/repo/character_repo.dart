// ============================================================
// character_repo.dart — 角色卡持久化
//
// 为什么是「一个 JSON 文件 + 原样结构」：
//   老产品把整张卡以 `JSON.stringify(character)` 存进 localStorage
//   （键 `coc7.characters.v1`，值是 { id: character } 字典）。要继承老存档，
//   唯一正确的做法是**保持结构一字不改** —— 字段名、嵌套、类型都不动，
//   加载时直接把这段 JSON 喂给 `normalize()`（它就是为此写的幂等迁移）。
//
// 存储位置：<应用文档目录>/dice_realm/characters.json
// 结构：{ "format": "dice-realm.characters", "version": 1, "cards": { "<id>": {...} } }
//
// 为什么要抽 [CharacterStorage]：
//   1. `path_provider` 依赖平台通道，单测跑不了 —— 换成注入目录即可；
//   2. 更要紧的是 widget 测试跑在 fake-async 区域里，**真实文件 I/O 的 Future
//      永远不会完成**（整个用例会挂死）。所以内存后端不是「为了测试而测试」，
//      而是让 UI 流程能在 fake-async 下跑完的唯一办法。
//      真实落盘由 repo_test.dart（普通 test，真 I/O）覆盖。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/character.dart';
import '../domain/engine.dart';
import '../domain/js_compat.dart';
import '../domain/normalize.dart';
// 状态「用户改过」标记通道（纯 Dart，无 Flutter 依赖）。
// 方向是 repo → ui，看着别扭，但这一层语义（哪些值需要标记、怎么 clamp）
// 必须与输入框路径共用同一份实现，否则「导入」与「手改」两套规则迟早分叉。
import '../ui/status_ops.dart' show applyExplicitStatusMarks;

/// 撕卡判据（英灵殿口径）
///
/// ⚠️ 与老产品 `app.js#isRippedCard` 的**差异**（有意为之，任务要求）：
///   老版只认 `status.body === '死亡'`；这里额外把「永久疯狂」也算作撕卡
///   （规则上永久疯狂 = 角色退场，跑团房间也据此拒绝选卡）。
///   两者都来自卡片上的权威字段，不引入新键名。
bool isRippedCard(Character c) {
  if (jsStr(c.status['body']) == '死亡') return true;
  final mental = asList(c.status['mental']);
  return mental.map(jsStr).contains('永久疯狂');
}

/// 存储后端
abstract class CharacterStorage {
  Future<Map<String, Map<String, Object?>>> load();
  Future<void> save(Map<String, Map<String, Object?>> cards);

  /// 调试/测试用：落盘位置（内存后端为 null）
  String? get location;
}

/// 内存后端（widget 测试用；也便于以后做「预览态」）
class MemoryStorage implements CharacterStorage {
  MemoryStorage([Map<String, Map<String, Object?>>? seed])
    : _cards = _copy(seed ?? const <String, Map<String, Object?>>{});

  Map<String, Map<String, Object?>> _cards;

  @override
  String? get location => null;

  @override
  Future<Map<String, Map<String, Object?>>> load() async => _copy(_cards);

  @override
  Future<void> save(Map<String, Map<String, Object?>> cards) async {
    _cards = _copy(cards);
  }

  static Map<String, Map<String, Object?>> _copy(
    Map<String, Map<String, Object?>> src,
  ) {
    final out = <String, Map<String, Object?>>{};
    src.forEach((k, v) => out[k] = _deep(v));
    return out;
  }

  static Map<String, Object?> _deep(Map<String, Object?> v) {
    final out = <String, Object?>{};
    v.forEach((k, x) => out[k] = _val(x));
    return out;
  }

  static Object? _val(Object? v) {
    if (v is Map) {
      final out = <String, Object?>{};
      v.forEach((k, x) => out[jsStr(k)] = _val(x));
      return out;
    }
    if (v is List) return v.map(_val).toList();
    return v;
  }
}

/// JSON 文件后端（真实运行用）
class JsonFileStorage implements CharacterStorage {
  JsonFileStorage({Directory? directory}) : _dirOverride = directory;

  static const String formatTag = 'dice-realm.characters';
  static const int formatVersion = 1;
  static const String fileName = 'characters.json';

  final Directory? _dirOverride;
  File? _file;

  @override
  String? get location => _file?.path ?? _dirOverride?.path;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    Directory dir;
    if (_dirOverride != null) {
      dir = _dirOverride;
      if (!await dir.exists()) await dir.create(recursive: true);
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}${Platform.pathSeparator}dice_realm');
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    return _file = File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<Map<String, Map<String, Object?>>> load() async {
    final file = await _resolveFile();
    final out = <String, Map<String, Object?>>{};
    if (!await file.exists()) return out;
    final text = await file.readAsString();
    if (text.trim().isEmpty) return out;
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final cards = decoded['cards'];
      if (cards is Map) {
        cards.forEach((k, v) {
          if (v is Map) out[jsStr(k)] = Map<String, Object?>.from(v);
        });
      }
    }
    return out;
  }

  @override
  Future<void> save(Map<String, Map<String, Object?>> cards) async {
    final file = await _resolveFile();
    final body = <String, Object?>{
      'format': formatTag,
      'version': formatVersion,
      'cards': cards,
    };
    // 先写临时文件再 rename：中途被杀不会留下半截 JSON
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent(' ').convert(body),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}

/// 角色卡仓库：内存缓存 + 落盘。用 ChangeNotifier 让页面随数据刷新。
class CharacterRepo extends ChangeNotifier {
  CharacterRepo({CharacterStorage? storage, Directory? directory})
    : _storage = storage ?? JsonFileStorage(directory: directory);

  final CharacterStorage _storage;
  final Map<String, Map<String, Object?>> _cards =
      <String, Map<String, Object?>>{};

  bool _loaded = false;
  String? lastError;

  bool get isLoaded => _loaded;

  /// 全部卡片（未排序）
  List<Character> get all => _cards.values.map((r) => Character(r)).toList();

  /// 「已保存的角色卡」：未撕卡，按最近修改倒序
  List<Character> get alive =>
      all.where((c) => !isRippedCard(c)).toList()..sort(_byUpdatedDesc);

  /// 「英灵殿」：已撕卡，按最近修改倒序
  List<Character> get fallen =>
      all.where(isRippedCard).toList()..sort(_byUpdatedDesc);

  Character? get(String id) {
    final raw = _cards[id];
    return raw == null ? null : Character(raw);
  }

  static int _byUpdatedDesc(Character a, Character b) =>
      jsNum(b.raw['updatedAt']).compareTo(jsNum(a.raw['updatedAt']));

  /// 读盘。失败时保持空列表并记录 [lastError]（不抛，首页能正常显示）。
  Future<void> load() async {
    try {
      final cards = await _storage.load();
      _cards
        ..clear()
        ..addAll(cards);
      lastError = null;
      _loaded = true;
    } catch (e) {
      lastError = '$e';
      _loaded = true;
    }
    notifyListeners();
  }

  /// 保存（新增或覆盖）。
  ///
  /// 落盘前统一走 `applyExplicitStatusMarks()` → `normalize()` → `recalc()`：
  ///   · marks 把「JSON 里显式存在的 0」（HP/MP/SAN）与「玩家改过的幸运」
  ///     打上 `_hpTouched / _mpTouched / _sanTouched / _luckTouched` 标记 ——
  ///     否则 recalc 的补值守卫会把导入进来的濒死卡**治活**（QA 的 D1）。
  ///     这是导入 / 房间外部回写唯一会经过的入口，所以标记点放在这里。
  ///   · normalize 把老结构 / 缺字段补齐（幂等，跑多少遍都一样）
  ///   · recalc 把派生值（HP/MP/SAN/DB/MOV）重算一遍，保证存进去的卡是自洽的
  Future<void> save(Character card) async {
    applyExplicitStatusMarks(card);
    final c = normalize(card);
    recalc(c);
    c.raw['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    if (!jsTruthy(c.raw['createdAt'])) {
      c.raw['createdAt'] = c.raw['updatedAt'];
    }
    _cards[c.id] = c.toJson();
    notifyListeners();
    await _flush();
  }

  Future<void> delete(String id) async {
    _cards.remove(id);
    notifyListeners();
    await _flush();
  }

  Future<void> _flush() async {
    try {
      await _storage.save(_cards);
      lastError = null;
    } catch (e) {
      lastError = '$e';
    }
  }

  /// 测试 / 调试用：当前内存里的原始字典
  @visibleForTesting
  Map<String, Map<String, Object?>> get rawCards => _cards;

  /// 测试 / 调试用：后端位置（内存后端为 null）
  @visibleForTesting
  String? get debugStoragePath => _storage.location;
}
