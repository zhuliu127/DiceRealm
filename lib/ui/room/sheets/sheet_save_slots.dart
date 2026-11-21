// ============================================================
// sheets/sheet_save_slots.dart — 本机存档槽（新建 / 载入 / 删除）
//
// 保存：`controller.saveNow(name:)` → `session.exportSave()` → `saveStore.put`。
// 载入：`controller.openSave(save)` —— K4 顺序不可交换：
//       `migrateLegacySave` → `adoptSave` → 迁移条数 > 0 一次性提示。
// 删除：`RoomSaveStore` 端口没有 delete（domain 冻结），所以只有实现了
//       `RoomSaveStoreMutable` 的后端才能删；纯端口后端下按钮**不渲染**并给出说明。
//
// ★ 存档后端在 P5 是**纯内存**：App 关闭即丢。文案照实写。
// ★ 只发动作：零权威端引用、零规则调用；保存失败一律转 notice。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asMap, jsParseInt;
import '../../../domain/room_ports.dart' show RoomSaveStore;
import '../../../repo/room_save_store.dart' show RoomSaveStoreMutable;
import '../room_scope.dart' show RoomScope;
import '../save_persist_hint.dart' show savePersistHintOf;
import '../save_time.dart' show saveTimeText;
import '../widgets/room_panel_kit.dart' show ConfirmTwice, RoomTap;
import 'room_sheet.dart' show showRoomSheet;
import '../room_text.dart';

/// 存档槽弹层内部稳定 key。
class SaveSlotsKeys {
  const SaveSlotsKeys._();

  static const Key root = ValueKey<String>('saveSlots/root');
  static const Key name = ValueKey<String>('saveSlots/name');
  static const Key save = ValueKey<String>('saveSlots/save');
  static const Key empty = ValueKey<String>('saveSlots/empty');
  static const Key hint = ValueKey<String>('saveSlots/hint');

  /// 一个槽行（`saveSlots/row/<槽键>`）。
  static Key row(String key) => ValueKey<String>('saveSlots/row/$key');

  /// 该行的「载入」。
  static Key load(String key) => ValueKey<String>('saveSlots/load/$key');

  /// 该行的「删除」。
  static Key remove(String key) => ValueKey<String>('saveSlots/remove/$key');
}

/// 打开「存档槽」弹层。
Future<void> openSaveSlotsSheet(BuildContext context) => showRoomSheet<void>(
      context: context,
      title: '存档槽（本机）',
      body: (BuildContext _) => const SaveSlotsSheet(),
    );

/// 存档槽弹层主体。
class SaveSlotsSheet extends StatefulWidget {
  const SaveSlotsSheet({super.key, this.store});

  /// 存档后端；不传则用控制器里的那份（与入口页、续玩列表同源）。
  final RoomSaveStore? store;

  @override
  State<SaveSlotsSheet> createState() => _SaveSlotsSheetState();
}

class _SaveSlotsSheetState extends State<SaveSlotsSheet> {
  final TextEditingController _name = TextEditingController();
  List<String> _keys = <String>[];
  bool _init = false;

  RoomSaveStore? get _store {
    final injected = widget.store;
    if (injected != null) return injected;
    return RoomScope.read(context).controller.saveStore;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final scope = RoomScope.read(context);
    // 默认名：存档槽键的**合法**格式（后端只收 `[A-Za-z0-9_-]`），用户可改。
    // ★ P13：原来是 `房间号 · 第 N 轮`，含空格/中文/间隔号 → 必被
    //   `FileRoomSaveStore.isSafeKey` 拒写，用户点「保存」看着像失败。
    //   现改：第 0 轮 = 纯房号；有轮次 = `房号-rN`（如 `K6NB89-r1`）。
    final meta = asMap(scope.session.state['meta']);
    final round = int.tryParse(roomText(meta['round'])) ?? 0;
    _name.text = round <= 0
        ? scope.session.code
        : '${scope.session.code}-r$round';
    _reload();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _reload() {
    final store = _store;
    if (store == null) {
      _keys = <String>[];
      return;
    }
    final keys = <String>[...store.list()];
    // 新的在上：按存档自带的 savedAt（毫秒）降序；读不出时间的排最后，不丢。
    int savedAtOf(String key) => jsParseInt(store.get(key)?['savedAt']) ?? 0;
    keys.sort((String a, String b) {
      final ta = savedAtOf(a);
      final tb = savedAtOf(b);
      if (ta != tb) return tb.compareTo(ta);
      return b.compareTo(a);
    });
    _keys = keys;
  }

  Future<void> _save() async {
    final scope = RoomScope.read(context);
    final name = _name.text.trim();
    final ok = await scope.controller.saveNow(name: name.isEmpty ? null : name);
    if (!mounted) return;
    setState(_reload);
    if (!ok) return;
    scope.local.showNotice('已保存到本机存档「${name.isEmpty ? scope.session.code : name}」');
  }

  Future<void> _load(String key) async {
    final store = _store;
    final save = store?.get(key);
    if (save == null) {
      RoomScope.read(context).local.showNotice('这条存档读不出来了');
      return;
    }
    final scope = RoomScope.read(context);
    // ★ K4：迁移 → adopt → 一次性提示，全在 openSave 里，顺序不可交换。
    await scope.controller.openSave(save);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _remove(String key) {
    final store = _store;
    if (store is RoomSaveStoreMutable) {
      store.remove(key);
    }
    final scope = RoomScope.read(context);
    scope.local.showNotice('已删除本机存档「$key」');
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = _store;
    final removable = store is RoomSaveStoreMutable;

    return Column(
      key: SaveSlotsKeys.root,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          // ★ 与入口页同一句，都跟后端能力走（见 save_persist_hint.dart）。
          savePersistHintOf(store),
          key: SaveSlotsKeys.hint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.secondary),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: SaveSlotsKeys.name,
                controller: _name,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '存档名（默认房间号）',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            RoomTap(
              key: SaveSlotsKeys.save,
              icon: Icons.save_outlined,
              label: '保存',
              hint: '把当前房间存成一个本机存档槽',
              minSize: const Size(88, 44),
              enabled: store != null,
              onTap: _save,
            ),
          ],
        ),
        const Divider(height: 18),
        if (_keys.isEmpty)
          Text(
            '还没有本机存档',
            key: SaveSlotsKeys.empty,
            style: theme.textTheme.bodySmall,
          )
        else
          for (final key in _keys) _row(theme, key, removable),
        if (!removable) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '当前存档后端不支持删除（只实现了内存槽的增 / 读 / 列）。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.disabledColor),
          ),
        ],
      ],
    );
  }

  Widget _row(ThemeData theme, String key, bool removable) {
    final save = _store?.get(key);
    final meta = asMap(save == null ? null : save['meta']);
    final name = roomText(meta['name']);
    final code = roomText(meta['code']);
    final status = roomText(meta['status']);
    // ★ P15：列表存档统一带时间戳（与续玩列表同一套文案）。
    final savedAt = jsParseInt(save?['savedAt']) ?? 0;
    return Padding(
      key: SaveSlotsKeys.row(key),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name.isEmpty ? key : name,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  // ★ P15：时间放**最前**。`auto/<房号>/round-<毫秒>` 这类
                  //   键很长，时间若放末尾会被 ellipsis 吃掉，用户看不到。
                  '${saveTimeText(savedAt)} · $key'
                  '${code.isEmpty || code == key ? '' : ' · $code'}'
                  '${status.isEmpty ? '' : ' · $status'}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          RoomTap(
            key: SaveSlotsKeys.load(key),
            icon: Icons.play_circle_outline,
            label: '载入',
            hint: '载入这条存档（当前房间状态会被覆盖）',
            minSize: const Size(76, 40),
            onTap: () => _load(key),
          ),
          if (removable)
            ConfirmTwice(
              key: SaveSlotsKeys.remove(key),
              label: '删除',
              // 删除只影响本机槽，不动当前房间。
              confirmLabel: '再点一次',
              onConfirmed: () => _remove(key),
            ),
        ],
      ),
    );
  }
}
