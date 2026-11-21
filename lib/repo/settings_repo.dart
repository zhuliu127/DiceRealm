// ============================================================
// settings_repo.dart — 设置存储（本机独立文件，不与角色卡混在一起）
//
// 对应旧版 `core/store.js#defaultSettings()` + `app.js#settingsSheet`
// 里那几个键。**键名一个不改**（见 character.dart#defaultSettings），
// 这样以后的导入导出 / 迁移都不用做字段映射。
//
// 为什么是独立文件 `<应用文档目录>/dice_realm/settings.json`：
//   · 角色卡是「数据」，设置是「本机偏好」，两者的备份/清理周期不同；
//   · `aiKey` 是敏感信息，只该待在本机私有目录，不该跟着导出捆绑包走。
//
// 为什么抽 [SettingsStorage]（与 `CharacterStorage` 同一套路）：
//   1. `path_provider` 依赖平台通道，单测跑不了；
//   2. 更要紧的是 widget 测试跑在 fake-async 区域里，**真实文件 I/O 的 Future
//      永远不会完成**（用例会挂死）。所以内存后端不是「为了测试而测试」，
//      而是让 UI 流程能在 fake-async 下跑完的唯一办法。
//
// ⚠️ 三条硬要求：
//   1. **读不到文件时必须是干净默认值，绝不抛异常** —— 设置读失败不能让应用起不来；
//   2. **`aiKey` 不进日志**：对外只给 [SettingsRepo.maskedAiKey]（前 4 + 后 4），
//      [SettingsRepo.describe] 是唯一允许打日志的形状；
//   3. 老版本没有 settings 迁移需求（用户重填即可），但**未知键要保留** ——
//      以后加字段时不至于把别的版本写的值丢掉。
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/ai_probe.dart';
import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../domain/preset_gen.dart' as preset;
import '../domain/secret_mask.dart';

// maskApiKey / maskSecrets 搬到了 domain（lib/net 也要用，net 不能反向依赖 repo）。
// 这里重新导出，既有调用方与测试不需要改 import。
export '../domain/secret_mask.dart';

/// 设置键名常量（**与 character.dart#defaultSettings 的钥匙逐字一致**）
class SettingsKeys {
  const SettingsKeys._();

  static const String skillCap = 'skillCap';
  static const String theme = 'theme';

  /// Flutter 客户端的皮肤选择（`'dark'` / `'light'`）。
  ///
  /// **不能复用 [theme]**：那个键是旧版 Web 契约，`defaultSettings()` 会把它
  /// 预填成 `'light'` 且被 `qa_p3_h1_h4` 逐字断言 —— 一旦用它当皮肤开关，
  /// 所有老用户一升级就会从暗色突然变亮色。新键不存在才是「没选过」。
  static const String uiTheme = 'uiTheme';
  static const String autoSave = 'autoSave';
  static const String lastRuleSystem = 'lastRuleSystem';
  static const String shareBase = 'shareBase';
  static const String roomBase = 'roomBase';
  static const String aiBase = 'aiBase';
  static const String aiModel = 'aiModel';
  static const String aiKey = 'aiKey';
  static const String aiAttrCap = 'aiAttrCap';
  static const String aiAttrCapWithLuck = 'aiAttrCapWithLuck';
  static const String aiOccPtsCap = 'aiOccPtsCap';
  static const String aiIntPtsCap = 'aiIntPtsCap';
}

/// 存储后端
abstract class SettingsStorage {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> settings);

  /// 调试/测试用：落盘位置（内存后端为 null）
  String? get location;
}

/// 内存后端（widget 测试 / 预览态用）
class MemorySettingsStorage implements SettingsStorage {
  MemorySettingsStorage([Map<String, Object?>? seed])
    : _settings = <String, Object?>{...?seed};

  Map<String, Object?> _settings;

  @override
  String? get location => null;

  @override
  Future<Map<String, Object?>> load() async => <String, Object?>{..._settings};

  @override
  Future<void> save(Map<String, Object?> settings) async {
    _settings = <String, Object?>{...settings};
  }
}

/// JSON 文件后端（真实运行用）
class JsonFileSettingsStorage implements SettingsStorage {
  JsonFileSettingsStorage({Directory? directory}) : _dirOverride = directory;

  static const String formatTag = 'dice-realm.settings';
  static const int formatVersion = 1;
  static const String fileName = 'settings.json';

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

  /// 读盘。**任何异常都退化成空 Map**（调用方再叠默认值），绝不向上抛。
  @override
  Future<Map<String, Object?>> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return <String, Object?>{};
      final text = await file.readAsString();
      if (text.trim().isEmpty) return <String, Object?>{};
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final out = <String, Object?>{};
        decoded.forEach((k, v) {
          if (k == 'settings' && v is Map) {
            v.forEach((k2, v2) => out[jsStr(k2)] = v2);
          }
        });
        // 兼容「直接把设置平铺在顶层」的手写文件
        if (out.isEmpty) decoded.forEach((k, v) => out[jsStr(k)] = v);
        return out;
      }
      return <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  @override
  Future<void> save(Map<String, Object?> settings) async {
    final file = await _resolveFile();
    final body = <String, Object?>{
      'format': formatTag,
      'version': formatVersion,
      'settings': settings,
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

/// 设置仓库：内存缓存 + 落盘 + 变更通知
class SettingsRepo extends ChangeNotifier {
  SettingsRepo({SettingsStorage? storage, this.probe})
    : _storage = storage ?? JsonFileSettingsStorage() {
    _settings = defaultSettings();
    applyToDomain();
  }

  final SettingsStorage _storage;

  /// 连通性自检实现（null = 未接入，测试连接会直接说明）
  final AiProbe? probe;

  Map<String, Object?> _settings = defaultSettings();

  bool _loaded = false;
  String? lastError;

  /// 上次探测结果（界面展示用；不持久化，避免把「当时网络不好」记成设置）
  AiProbeResult? lastProbe;

  bool get isLoaded => _loaded;

  /// 只读快照（要改请走 setter，改完 `await save()`）
  Map<String, Object?> get settings =>
      Map<String, Object?>.unmodifiable(_settings);

  // ---------- 读盘 / 落盘 ----------

  /// 读盘。失败时保持默认值并记录 [lastError]（**不抛**）。
  Future<void> load() async {
    try {
      final raw = await _storage.load();
      _settings = _normalize(raw);
      lastError = null;
    } catch (e) {
      _settings = defaultSettings();
      lastError = '读取设置失败，已使用默认值：${maskSecrets('$e')}';
    }
    _loaded = true;
    applyToDomain();
    notifyListeners();
  }

  /// 落盘（失败只记 [lastError]，不抛 —— 设置写不进去不该崩掉页面）
  Future<void> save() async {
    try {
      await _storage.save(_settings);
      lastError = null;
    } catch (e) {
      lastError = '保存设置失败：${maskSecrets('$e')}';
    }
    applyToDomain();
    notifyListeners();
  }

  /// 把当前设置喂给规则层（`preset_gen` 的房规数值上限是**每次生成现读**的）
  void applyToDomain() => preset.presetSettings = _settings;

  // ---------- 生成固定默认值 + 容错归一 ----------

  /// 把磁盘上的任意形状叠到默认值上，并把类型掰正。
  ///
  /// 关键点：
  ///   · **未知键保留**（以后加字段时不会丢掉别的版本写的值）；
  ///   · 类型不对的键**退回默认值**而不是抛异常（手改过 / 老版本写坏的都见过）。
  Map<String, Object?> _normalize(Map<String, Object?> raw) {
    final out = defaultSettings();
    raw.forEach((k, v) {
      switch (k) {
        case SettingsKeys.skillCap:
          final n = jsParseInt(v);
          if (n != null && n > 0) out[k] = jsMin(<int>[n, 99]);
          break;
        case SettingsKeys.autoSave:
        case SettingsKeys.aiAttrCapWithLuck:
          if (v is bool) out[k] = v;
          break;
        case SettingsKeys.theme:
        case SettingsKeys.uiTheme:
        case SettingsKeys.lastRuleSystem:
          if (v is String) out[k] = v;
          break;
        case SettingsKeys.aiAttrCap:
        case SettingsKeys.aiOccPtsCap:
        case SettingsKeys.aiIntPtsCap:
          final n = jsParseInt(v);
          if (n != null && n >= 0) out[k] = n;
          break;
        case SettingsKeys.shareBase:
        case SettingsKeys.roomBase:
        case SettingsKeys.aiBase:
        case SettingsKeys.aiModel:
        case SettingsKeys.aiKey:
          if (v is String) out[k] = v;
          break;
        default:
          // 未知键原样保留
          out[k] = v;
      }
    });
    return out;
  }

  // ---------- 各键的读写 ----------

  int get skillCap => jsNum(_settings[SettingsKeys.skillCap]);
  set skillCap(int v) => _set(
    SettingsKeys.skillCap,
    jsMin(<int>[
      jsMax(<int>[1, v]),
      99,
    ]),
  );

  String get theme => jsStr(_settings[SettingsKeys.theme] ?? 'light');
  set theme(String v) => _set(SettingsKeys.theme, v);

  /// 当前是否为深色皮肤。
  ///
  /// 口径：**看 [SettingsKeys.uiTheme]，不看 [theme]**。
  /// [theme] 是旧版 Web 契约（`defaultSettings()` 预填 `'light'`，
  /// `qa_p3_h1_h4` 逐字断言），拿它当开关会让老用户升级后突然变亮色。
  /// `uiTheme` 不存在 = 从没选过 = 沿用现有暗色观感。
  bool get isDarkTheme {
    final Object? v = _settings[SettingsKeys.uiTheme];
    if (v == null) return true;
    return jsStr(v) != 'light';
  }

  set isDarkTheme(bool v) => _set(SettingsKeys.uiTheme, v ? 'dark' : 'light');

  bool get autoSave => _settings[SettingsKeys.autoSave] != false;
  set autoSave(bool v) => _set(SettingsKeys.autoSave, v);

  String get lastRuleSystem =>
      jsStr(_settings[SettingsKeys.lastRuleSystem] ?? '');
  set lastRuleSystem(String v) => _set(SettingsKeys.lastRuleSystem, v);

  /// 分享服务地址。**留空 = 未配置** —— 界面据此说明「未配置时可用本机导出」。
  String get shareBase => jsStr(_settings[SettingsKeys.shareBase] ?? '');
  set shareBase(String v) => _set(SettingsKeys.shareBase, v.trim());
  bool get shareConfigured => shareBase.isNotEmpty;

  /// 跑团房间服务地址。本期只存不连（P4 才启用）。
  String get roomBase => jsStr(_settings[SettingsKeys.roomBase] ?? '');
  set roomBase(String v) => _set(SettingsKeys.roomBase, v.trim());
  bool get roomConfigured => roomBase.isNotEmpty;

  String get aiBase => jsStr(_settings[SettingsKeys.aiBase] ?? '');
  set aiBase(String v) => _set(SettingsKeys.aiBase, v.trim());

  String get aiModel => jsStr(_settings[SettingsKeys.aiModel] ?? '');
  set aiModel(String v) => _set(SettingsKeys.aiModel, v.trim());

  /// ⚠️ 真实 Key。**只在发请求时读它**，任何日志 / 快照都要用 [maskedAiKey]。
  String get aiKey => jsStr(_settings[SettingsKeys.aiKey] ?? '');
  set aiKey(String v) => _set(SettingsKeys.aiKey, v.trim());

  /// 脱敏后的 Key（前 4 位 + 后 4 位），给界面「已保存：sk-1****abcd」用
  String get maskedAiKey => maskApiKey(aiKey);

  bool get aiConfigured =>
      aiBase.isNotEmpty && aiModel.isNotEmpty && aiKey.isNotEmpty;

  int get aiAttrCap => jsNum(_settings[SettingsKeys.aiAttrCap]);
  set aiAttrCap(int v) => _set(SettingsKeys.aiAttrCap, jsMax(<int>[0, v]));

  bool get aiAttrCapWithLuck =>
      _settings[SettingsKeys.aiAttrCapWithLuck] != false;
  set aiAttrCapWithLuck(bool v) => _set(SettingsKeys.aiAttrCapWithLuck, v);

  int get aiOccPtsCap => jsNum(_settings[SettingsKeys.aiOccPtsCap]);
  set aiOccPtsCap(int v) => _set(SettingsKeys.aiOccPtsCap, jsMax(<int>[0, v]));

  int get aiIntPtsCap => jsNum(_settings[SettingsKeys.aiIntPtsCap]);
  set aiIntPtsCap(int v) => _set(SettingsKeys.aiIntPtsCap, jsMax(<int>[0, v]));

  void _set(String key, Object? value) {
    _settings[key] = value;
    applyToDomain();
    notifyListeners();
  }

  // ---------- 测试连接 ----------

  /// 任何 [AiProbe] 实现（含注入的假实现 / 未来的第三方实现）都可能把
  /// 服务端回显带进结果。存入 [lastProbe] 之前统一归一化脱敏，设置页与
  /// 调试快照才不会把明文 Key 显示出来。
  AiProbeResult _safeProbe(AiProbeResult r) => AiProbeResult(
        kind: r.kind,
        message: maskSecrets(r.message),
        via: r.via,
        reply: maskSecrets(r.reply),
        models: r.models.map((m) => maskSecrets(m)).toList(),
        modelInList: r.modelInList,
        hint: maskSecrets(r.hint),
      );

  /// 两步探测（`GET /models` → 回退 `chat`）。
  ///
  /// 没有注入 [AiProbe] 时直接返回「未接入」，不联网 —— 单测与离线环境都安全。
  Future<AiProbeResult> testConnection() async {
    if (aiBase.isEmpty) {
      lastProbe = _safeProbe(AiProbeResult.notConfigured('接口地址'));
      notifyListeners();
      return lastProbe!;
    }
    if (aiModel.isEmpty) {
      lastProbe = _safeProbe(AiProbeResult.notConfigured('模型名称'));
      notifyListeners();
      return lastProbe!;
    }
    if (aiKey.isEmpty) {
      lastProbe = _safeProbe(AiProbeResult.notConfigured('API Key'));
      notifyListeners();
      return lastProbe!;
    }
    final p = probe;
    if (p == null) {
      lastProbe = _safeProbe(const AiProbeResult(
        kind: AiProbeKind.badResponse,
        message: '本版本还没有接入网络层，无法测试连接',
        hint: '设置已保存在本机；连通过程会在 AI 车卡版本里启用。',
      ));
      notifyListeners();
      return lastProbe!;
    }
    try {
      lastProbe = _safeProbe(
        await p.test(base: aiBase, model: aiModel, key: aiKey),
      );
    } catch (e) {
      // 任何异常都要翻成人话，绝不能把 Key 泄漏到消息里
      lastProbe = _safeProbe(AiProbeResult(
        kind: AiProbeKind.unreachable,
        message: explainRequestError(maskSecrets('$e')),
      ));
    }
    notifyListeners();
    return lastProbe!;
  }

  // ---------- 打日志 / 调试 ----------

  /// 允许打日志的形状：`aiKey` 已脱敏。
  ///
  /// **不要**直接 `print(settings)` —— 那会把 Key 原样写进日志。
  Map<String, Object?> describe() {
    final out = <String, Object?>{..._settings};
    out[SettingsKeys.aiKey] = maskedAiKey;
    // 防御性收口：未知键（或用户把 Key 粘进了别的格子）也不许顺着调试
    // 快照漏出去。lastProbe 不进 describe —— 它是内存态，由设置页直接展示，
    // 已在 testConnection 里经 _safeProbe 归一化。
    for (final k in out.keys.toList()) {
      final v = out[k];
      if (v is String) out[k] = maskSecrets(v);
    }
    return out;
  }

  /// 测试 / 调试用：后端位置（内存后端为 null）
  @visibleForTesting
  String? get debugStoragePath => _storage.location;
}
