// ============================================================
// share_store.dart — 云分享的本机记录（谁分享过、链接是什么、删除口令）
//
// 对应 `core/share.js` 里的 `KEY = 'coc7_card_shares_v1'` 那一套，
// 但存储从 localStorage 换成**应用文档目录下的独立 JSON**：
//   `<文档目录>/dice_realm/shares.json`
//   `{ "format": "dice-realm.shares", "version": 1, "shares": { "<charId>": {...} } }`
//
// 为什么不并进 characters.json：
//   `delToken` 是**删除口令**，属于敏感信息 —— 它必须能和角色卡分开清理
//   （换手机、清分享、批量删卡）。混在一起的话，导出一次存档就把口令也带出去了。
//
// 🔒 delToken 的三条铁律：
//   1. 只在本地文件里，**不上传**（请求体只有 {name, visibility, data}）；
//   2. **不进导出**（`exportBundleJson` 只吃角色卡，本来就碰不到这里）；
//   3. **不进日志**（打印只打 id / url，见 [ShareRecord.describe]）。
//
// 与 [CharacterStorage] / [SettingsStorage] 同一套路：文件后端 + 内存后端。
// 内存后端不是「为了测试而测试」—— widget 测试跑在 fake-async 里，
// 真实文件 I/O 的 Future 永远不会完成。
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../domain/rule_registry.dart';
import '../net/share_client.dart';

/// 一张卡的分享记录
class ShareRecord {
  /// [ruleShortName] 是 P7 新增的**可选**字段，带默认值 ''：
  /// 本能力上线前落盘的老记录没有它，所有 `const ShareRecord(...)` 构造点
  /// 一个都不用改；空串在 UI 里如实显示为「未标注规则」，不假装是 COC 7th。
  const ShareRecord({
    required this.id,
    required this.url,
    required this.delToken,
    required this.at,
    required this.name,
    this.ruleShortName = '',
  });

  factory ShareRecord.fromJson(Map<String, Object?> j) => ShareRecord(
    id: jsStr(j['id']),
    url: jsStr(j['url']),
    delToken: jsStr(j['delToken']),
    at: jsNum(j['at']),
    name: jsStr(j['name']),
    ruleShortName: _readRuleShortName(j['ruleShortName']),
  );

  /// 旧 JSON 缺字段 / 脏值一律给 ''。
  ///
  /// 不能直接 `jsStr(j['ruleShortName'])`：缺字段时那是字符串 `'null'`，
  /// 会被 UI 当成一条真实规则名显示出来。与服务端 render_card 的回退口径
  /// 保持一致（服务端回退 COC 7th，本机如实留空，语义不同但都不印 null）。
  static String _readRuleShortName(Object? v) {
    if (v == null) return '';
    final s = jsStr(v);
    return (s.isEmpty || s == 'null' || s == 'None') ? '' : s;
  }

  /// 服务端的分享 id
  final String id;

  /// 可发给别人的链接
  final String url;

  /// 删除口令（**只在本机**）
  final String delToken;

  /// 生成时间（毫秒）
  final int at;

  /// 生成时的角色名（角色改名后用来对比「链接是不是旧的」）
  final String name;

  /// 生成时该卡采用的规则简称（P7 云分享徽标，老记录为 ''）
  final String ruleShortName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'url': url,
    'delToken': delToken,
    'at': at,
    'name': name,
    'ruleShortName': ruleShortName,
  };

  /// 允许打日志的形状：口令已抹掉（新字段不含任何敏感信息，照常带出）
  Map<String, Object?> describe() => <String, Object?>{
    'id': id,
    'url': url,
    'delToken': delToken.isEmpty ? '' : '****',
    'at': at,
    'name': name,
    'ruleShortName': ruleShortName,
  };

  ShareRecord copyWith({
    String? name,
    int? at,
    String? ruleShortName,
  }) => ShareRecord(
    id: id,
    url: url,
    delToken: delToken,
    at: at ?? this.at,
    name: name ?? this.name,
    ruleShortName: ruleShortName ?? this.ruleShortName,
  );
}

/// 存储后端
abstract class ShareStorage {
  Future<Map<String, ShareRecord>> load();
  Future<void> save(Map<String, ShareRecord> records);
  String? get location;
}

/// 内存后端（widget 测试 / 预览态）
class MemoryShareStorage implements ShareStorage {
  MemoryShareStorage([Map<String, ShareRecord>? seed])
    : _records = <String, ShareRecord>{...?seed};

  Map<String, ShareRecord> _records;

  @override
  String? get location => null;

  @override
  Future<Map<String, ShareRecord>> load() async => <String, ShareRecord>{
    ..._records,
  };

  @override
  Future<void> save(Map<String, ShareRecord> records) async {
    _records = <String, ShareRecord>{...records};
  }
}

/// JSON 文件后端
class JsonFileShareStorage implements ShareStorage {
  JsonFileShareStorage({Directory? directory}) : _dirOverride = directory;

  static const String formatTag = 'dice-realm.shares';
  static const int formatVersion = 1;
  static const String fileName = 'shares.json';

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

  /// 读盘。**任何异常都退化成空表**，绝不向上抛（分享记录坏了不该拦启动）。
  @override
  Future<Map<String, ShareRecord>> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return <String, ShareRecord>{};
      final text = await file.readAsString();
      if (text.trim().isEmpty) return <String, ShareRecord>{};
      final decoded = jsonDecode(text);
      if (decoded is! Map) return <String, ShareRecord>{};
      final src = decoded['shares'] is Map ? decoded['shares'] as Map : decoded;
      final out = <String, ShareRecord>{};
      src.forEach((k, v) {
        if (v is Map) out[jsStr(k)] = ShareRecord.fromJson(v.cast<String, Object?>());
      });
      return out;
    } catch (_) {
      return <String, ShareRecord>{};
    }
  }

  @override
  Future<void> save(Map<String, ShareRecord> records) async {
    final file = await _resolveFile();
    final body = <String, Object?>{
      'format': formatTag,
      'version': formatVersion,
      'shares': records.map((k, v) => MapEntry<String, Object?>(k, v.toJson())),
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent(' ').convert(body),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}

/// 分享记录仓库
class ShareStore extends ChangeNotifier {
  ShareStore({ShareStorage? storage})
    : _storage = storage ?? JsonFileShareStorage();

  final ShareStorage _storage;
  final Map<String, ShareRecord> _records = <String, ShareRecord>{};

  bool _loaded = false;
  String? lastError;

  bool get isLoaded => _loaded;

  /// 只读快照
  Map<String, ShareRecord> get all =>
      Map<String, ShareRecord>.unmodifiable(_records);

  ShareRecord? forCard(String? charId) =>
      charId == null ? null : _records[charId];

  /// 读盘（失败只记 lastError）
  Future<void> load() async {
    try {
      final list = await _storage.load();
      _records
        ..clear()
        ..addAll(list);
      lastError = null;
    } catch (e) {
      _records.clear();
      lastError = '读取分享记录失败：$e';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> put(String charId, ShareRecord rec) async {
    _records[charId] = rec;
    notifyListeners();
    await _flush();
  }

  Future<void> remove(String charId) async {
    _records.remove(charId);
    notifyListeners();
    await _flush();
  }

  Future<void> _flush() async {
    try {
      await _storage.save(_records);
      lastError = null;
    } catch (e) {
      lastError = '保存分享记录失败：$e';
    }
  }

  @visibleForTesting
  String? get debugStoragePath => _storage.location;
}

/// 把「网络」和「本机记录」缝在一起 —— UI 只跟它打交道
///
/// 为什么不把这些逻辑塞进 UI：创建成功后要同时做三件事
/// （调接口 / 落本机记录 / 把 shareId 写回卡上），漏一件就会
/// 「界面显示已分享、下次打开却找不到记录」。放在这里一次做全。
class ShareService {
  ShareService({required this.client, required this.store});

  final ShareApi client;
  final ShareStore store;

  bool get configured => client.configured;
  String get base => client.base;

  ShareRecord? forCard(String? charId) => store.forCard(charId);

  /// 创建 / 更新分享。
  ///
  /// 「更新为当前版本」在旧版里就是再 create 一次（服务端生成新 id），
  /// 所以这里不区分，语义交给 UI 的按钮文案。
  Future<ShareRecord> create(Character c) async {
    final res = await client.create(c);
    // ★ P7：与 buildSharePayload 同一口径 —— 先算已开放规则 id，
    //   再用该 id 取简称，避免占位 / 脏 id 让记录与云端载荷打架。
    final rid = RuleRegistry.effectiveId(c.ruleSystemId);
    final rec = ShareRecord(
      id: res.id,
      url: res.url,
      delToken: res.delToken,
      at: nowMillis(),
      name: jsStr(c.raw['characterName']),
      ruleShortName: RuleRegistry.shortNameOf(rid),
    );
    await store.put(c.id, rec);
    c.raw['shareId'] = res.id;
    return rec;
  }

  /// 删除分享。[token] 不传就用本机记录里的口令。
  Future<void> remove(String charId, {String? token}) async {
    final rec = store.forCard(charId);
    if (rec == null) {
      throw ShareException(ShareErrorKind.noRecord, '本机没有该角色的分享记录');
    }
    await client.remove(rec.id, token ?? rec.delToken);
    await store.remove(charId);
  }
}
