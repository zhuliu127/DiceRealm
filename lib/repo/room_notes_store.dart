// ============================================================
// room_notes_store.dart — 玩家本机笔记栏（P1-05 / K12）
//
// 设计 §3.9 / §7.2 K12：键 = `room/<code>/<seat>`，**不上传、不进 state、
// 不进存档**。文件后端留构造位（同 `room_save_store.dart` 范式），本期
// 只交付内存实现，widget 测试与生产共用它 —— `flutter_test` 跑在 fake-async
// 区域里，真实文件 I/O 的 Future 永不完成（T1 铁律）。
//
// ⚠️ 本层是 I/O 边界：允许 dart:async 的 Future，但不允许 dart:io 落到
//    `lib/domain`；`RoomNotesStorage` 只是端口，换文件后端时 UI 一行不改。
// ============================================================

import '../domain/js_compat.dart';
import '../domain/room_model_state.dart' show roomClone;

/// 一条笔记。`id` 由 [RoomNotesStore.add] 生成（本机单调，不依赖网络）。
class RoomNote {
  const RoomNote({required this.id, required this.text, required this.at});

  final String id;
  final String text;
  final num at;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'text': text,
        'at': at,
      };

  static RoomNote fromJson(Object? raw) {
    final m = asMap(raw);
    return RoomNote(
      id: jsStr(m['id'] ?? ''),
      text: jsStr(m['text'] ?? ''),
      at: (m['at'] is num) ? m['at']! as num : jsNum(m['at']),
    );
  }
}

/// 笔记存储端口（纯 Map 契约；后续换 SharedPreferences / 文件后端不动 UI）。
abstract class RoomNotesStorage {
  Future<Map<String, Object?>> load(String key);

  Future<void> save(String key, Map<String, Object?> data);
}

/// 纯内存后端：key → 数据 Map。每次读写都深拷贝，避免调用方拿到内部引用
/// 后原地改写（K9：一律 roomClone，不用 jsonDecode(jsonEncode(x))）。
class MemoryNotesStorage implements RoomNotesStorage {
  final Map<String, Map<String, Object?>> _byKey =
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> load(String key) async =>
      asMap(roomClone(_byKey[key] ?? const <String, Object?>{}));

  @override
  Future<void> save(String key, Map<String, Object?> data) async {
    _byKey[key] = asMap(roomClone(data));
  }

  /// 已经写过的键数（诊断 / 测试用）。
  int get length => _byKey.length;

  /// 直接读内部数据（测试断言用，生产不调）。
  Map<String, Object?>? peek(String key) => _byKey[key];
}

/// §6.1 夹具里用的是 `InMemoryNotesStorage()` 这个名字，与 §3.9 的
/// `MemoryNotesStorage` 是同一个实现 —— 保留别名，避免夹具改名。
class InMemoryNotesStorage extends MemoryNotesStorage {
  InMemoryNotesStorage();
}

/// 笔记栏门面：把「一串笔记」序列化成存储后端的一份 Map。
///
/// 存储形状固定为 `{'notes': [ {id,text,at}, ... ]}`，**不新增任何房间
/// 状态键**。键 = `room/<code>/<seat>`（K12）。
class RoomNotesStore {
  RoomNotesStore(this.storage);

  final RoomNotesStorage storage;

  /// 键的构造规则（K12 唯一真相源）。
  static String keyOf(String code, String seat) => 'room/$code/$seat';

  Future<List<RoomNote>> load(String code, String seat) async {
    final data = await storage.load(keyOf(code, seat));
    return asList(data['notes']).map(RoomNote.fromJson).toList();
  }

  Future<void> add(String code, String seat, String text) async {
    final key = keyOf(code, seat);
    final data = await storage.load(key);
    final rows = asList(data['notes']).map(asMap).toList();
    final id = 'n${rows.length + 1}_${jsNum(data['nextId'])}';
    rows.add(<String, Object?>{
      'id': id,
      'text': text,
      'at': 0,
    });
    data['notes'] = rows;
    data['nextId'] = jsNum(data['nextId']) + 1;
    await storage.save(key, data);
  }

  Future<void> update(String code, String seat, String id, String text) async {
    final key = keyOf(code, seat);
    final data = await storage.load(key);
    final rows = asList(data['notes']).map(asMap).toList();
    for (final row in rows) {
      if (jsStr(row['id'] ?? '') == id) {
        row['text'] = text;
        break;
      }
    }
    data['notes'] = rows;
    await storage.save(key, data);
  }

  Future<void> remove(String code, String seat, String id) async {
    final key = keyOf(code, seat);
    final data = await storage.load(key);
    final rows = asList(data['notes'])
        .map(asMap)
        .where((r) => jsStr(r['id'] ?? '') != id)
        .toList();
    data['notes'] = rows;
    await storage.save(key, data);
  }

  /// 一次性整体替换（供弹层「编辑并保存」使用；仍是本机数据）。
  Future<void> replace(String code, String seat, List<RoomNote> notes) async {
    await storage.save(
      keyOf(code, seat),
      <String, Object?>{
        'notes': notes.map((n) => n.toJson()).toList(),
        'nextId': notes.length + 1,
      },
    );
  }
}

// ------------------------------------------------------------
// 后续期（K12 / 设计 §2.2）：FileNotesStorage implements RoomNotesStorage
//   · 构造位：FileNotesStorage({required Directory directory})
//   · load → 读 <directory>/<hash(key)>.json；save → 临时文件 + rename
//   ⚠️ dart:io 只允许出现在本文件（repo 层），domain / view 保持纯 Dart。
// ------------------------------------------------------------
