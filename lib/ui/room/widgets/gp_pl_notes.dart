// ============================================================
// widgets/gp_pl_notes.dart — 块 11（玩家）：我的笔记（本机私有）
//
// ★ K12 / P1-05：走 `RoomNotesStore`（键 = `room/<code>/<seat>`），
//   **不进权威态、不上传、不发包** —— 本文件零 `sendIntent` / `hostAction`。
// ★ 后端是内存实现（U4：P5 用 `MemoryNotesStorage`，重启丢；文件后端构造位
//   留在 `room_notes_store.dart`）。
// ============================================================

import 'package:flutter/material.dart';

import '../../../repo/room_notes_store.dart' show RoomNote;
import '../room_scope.dart';
import 'room_panel_kit.dart';
import '../room_text.dart';

/// 笔记块内部稳定 key。
class GpPlNotesKeys {
  const GpPlNotesKeys._();

  static const Key root = ValueKey<String>('gpPlNotes/root');
  static const Key input = ValueKey<String>('gpPlNotes/input');
  static const Key add = ValueKey<String>('gpPlNotes/add');
  static const Key empty = ValueKey<String>('gpPlNotes/empty');
  static const Key list = ValueKey<String>('gpPlNotes/list');

  /// 单条（`gpPlNotes/row/<id>`）。
  static Key row(String id) => ValueKey<String>('gpPlNotes/row/$id');
}

/// 块 11：我的笔记（本机）。
class GpPlNotes extends StatefulWidget {
  const GpPlNotes({super.key, this.height = 140, this.fill = false});

  /// 列表可视高度。★ 只在 [fill] == false 时生效（旧路径逐字不变）。
  final double height;

  /// 是否吃满父级剩余高度（2.42.0 / P20 需求 3②）。
  ///
  /// · `false`（默认）：列表恒为 `SizedBox(height: widget.height)`，
  ///   dock 格 / KP 折叠档 / 既有几何断言依赖它 —— **一个字节都不许动**。
  /// · `true`：列表换成 `Expanded`、`SectionBox` 切到 `expand: true`，
  ///   整块吃满父级高度。给「全屏打开笔记」用：
  ///   `openRoomSlotFullscreen(context, title: '我的笔记',
  ///       body: (_) => const GpPlNotes(fill: true))`。
  ///
  /// ★ 调用约束：[fill] == true 要求父级给出**有界高度**
  ///   （`Scaffold.body` / 全屏路由 body / dock 格）；放进
  ///   `SingleChildScrollView` 这类无界父级会撞「unbounded height」断言。
  final bool fill;

  @override
  State<GpPlNotes> createState() => _GpPlNotesState();
}

class _GpPlNotesState extends State<GpPlNotes> {
  final TextEditingController _draft = TextEditingController();
  List<RoomNote> _notes = <RoomNote>[];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  /// 本机读写（异步但零 I/O；不产生任何 intent）。
  Future<void> _reload() async {
    final scope = RoomScope.read(context);
    final session = scope.session;
    final rows = await scope.controller.notes.load(session.code, session.seat);
    if (!mounted) return;
    setState(() => _notes = rows);
  }

  Future<void> _add() async {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    final scope = RoomScope.read(context);
    final session = scope.session;
    _draft.clear();
    await scope.controller.notes.add(session.code, session.seat, text);
    await _reload();
  }

  Future<void> _remove(String id) async {
    final scope = RoomScope.read(context);
    final session = scope.session;
    await scope.controller.notes.remove(session.code, session.seat, id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 列表 / 空态。抽成局部变量，让 fill 与非 fill 两条路径共用同一棵子树。
    final Widget listOrEmpty = _notes.isEmpty
        ? Center(
            child: Text(
              '还没有笔记',
              key: GpPlNotesKeys.empty,
              style: theme.textTheme.bodySmall,
            ),
          )
        : ListView.builder(
            key: GpPlNotesKeys.list,
            itemCount: _notes.length,
            itemBuilder: (BuildContext context, int i) {
              final n = _notes[i];
              return Row(
                key: GpPlNotesKeys.row(n.id),
                children: <Widget>[
                  Expanded(
                    child: Text(
                      roomText(n.text),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  RoomTap(
                    icon: Icons.delete_outline,
                    hint: '删除这条笔记',
                    minSize: const Size(36, 30),
                    onTap: () => _remove(n.id),
                  ),
                ],
              );
            },
          );

    return SectionBox(
      key: GpPlNotesKeys.root,
      title: '我的笔记（本机）',
      // ★ P20 需求 3②：fill 时整块吃满父级高度（全屏路由用）；
      //   默认 false ⇒ SectionBox 渲染逐字不变。
      expand: widget.fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: GpPlNotesKeys.input,
                  controller: _draft,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '记一条（不上传，只在本机）',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (String _) => _add(),
                  // ★ P16 C-2：与自定义骰子同形态常驻输入框，点击外部失焦。
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
              RoomTap(
                key: GpPlNotesKeys.add,
                icon: Icons.add,
                hint: '添加笔记（本机保存）',
                minSize: const Size(48, 44),
                onTap: _add,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // ★ 旧路径（fill == false）逐字保留 `SizedBox(height: widget.height)`。
          widget.fill
              ? Expanded(child: listOrEmpty)
              : SizedBox(height: widget.height, child: listOrEmpty),
        ],
      ),
    );
  }
}
