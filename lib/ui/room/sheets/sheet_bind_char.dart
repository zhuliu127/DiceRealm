// ============================================================
// sheets/sheet_bind_char.dart — 绑定 / 更换 / 清空角色卡（房间页）
//
// 数据源：本机车卡仓库（经 `RepoScope`），**只读**——本弹层不改车卡。
// 选中一张 → `INTENT.CHAR { id, name, sheet }`，`sheet` 由
// `card_sheet_payload.dart` 搬运键名后交 domain 白名单产出（口径唯一）。
//
// ★ 房间里没有「解绑」这个动作：权威端只有 `char.share`（整体覆盖）。
//   所以「清空」= 用一张**空白房卡**覆盖，数值归零；名字与临时状态由
//   权威端保留。按钮与提示照实写，不做成「解绑」的错觉。
// ★ 只画、只发 intent：零权威端引用、零规则调用。
// ============================================================

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../domain/character.dart' show Character;
import '../../../domain/js_compat.dart' show asMap;
import '../../../domain/room_types.dart' show RoomIntent;
import '../../../repo/repo_scope.dart' show RepoScope;
import '../room_scope.dart' show RoomScope;
import '../view/room_view.dart' show findMe;
import '../widgets/room_panel_kit.dart' show AvatarDot, RoomTap;
import 'card_sheet_payload.dart'
    show cardDisplayName, cardToRoomSheetForReport;
import 'room_sheet.dart' show showRoomSheet;
import '../room_text.dart';

/// 绑卡弹层内部稳定 key。
class BindCharSheetKeys {
  const BindCharSheetKeys._();

  static const Key root = ValueKey<String>('bindChar/root');
  static const Key empty = ValueKey<String>('bindChar/empty');
  static const Key current = ValueKey<String>('bindChar/current');
  static const Key hint = ValueKey<String>('bindChar/hint');
  static const Key clear = ValueKey<String>('bindChar/clear');

  /// 一张车卡行（`bindChar/row/<卡 id>`）。
  static Key row(String id) => ValueKey<String>('bindChar/row/$id');

  /// 该行的「绑定 / 更换」按钮。
  static Key pick(String id) => ValueKey<String>('bindChar/pick/$id');
}

/// 打开「绑定角色卡」弹层。
Future<void> openBindCharSheet(BuildContext context) => showRoomSheet<void>(
      context: context,
      title: '角色卡',
      body: (BuildContext _) => const BindCharSheet(),
    );

/// 绑卡弹层主体。
class BindCharSheet extends StatefulWidget {
  const BindCharSheet({super.key});

  @override
  State<BindCharSheet> createState() => _BindCharSheetState();
}

class _BindCharSheetState extends State<BindCharSheet> {
  bool _asked = false;

  /// 上报中（生成头像缩略图时会有一次异步等待，防止连点发出两次 CHAR）。
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // 仓库没 load 过就补一次（内存后端，同步完成；失败只记 lastError）。
    final repo = RepoScope.read(context);
    if (!repo.isLoaded) unawaited(repo.load());
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final scope = RoomScope.of(context);
    final theme = Theme.of(context);
    final cards = repo.alive;
    final me = findMe(scope.session.state, scope.session.seat);
    final boundId = roomText(asMap(me?['sheet'])['charId']);
    final boundName = roomText(asMap(me?['sheet'])['name']);

    return Column(
      key: BindCharSheetKeys.root,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '选择一张本机角色卡带进房间（车卡本身不会被修改）',
          key: BindCharSheetKeys.hint,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          boundId.isEmpty
              ? '当前：未绑定'
              : '当前：${boundName.isEmpty ? boundId : boundName}',
          key: BindCharSheetKeys.current,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.secondary),
        ),
        const Divider(height: 16),
        if (cards.isEmpty)
          Text(
            '本机还没有角色卡（先去首页建一张）',
            key: BindCharSheetKeys.empty,
            style: theme.textTheme.bodySmall,
          )
        else
          for (final card in cards) _row(card, boundId, scope),
        const Divider(height: 16),
        Text(
          '房间内没有单独的「解绑」动作：清空 = 用空白房卡覆盖，'
          '数值归零，名字与 KP 发的临时状态由权威端保留。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.disabledColor),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: RoomTap(
            key: BindCharSheetKeys.clear,
            icon: Icons.layers_clear_outlined,
            label: '清空房卡数值',
            hint: boundId.isEmpty ? '还没有绑定角色卡' : '用空白卡覆盖当前房卡',
            enabled: boundId.isNotEmpty,
            minSize: const Size(140, 40),
            onTap: () => unawaited(_clear(scope)),
          ),
        ),
      ],
    );
  }

  Widget _row(Character card, String boundId, RoomScope scope) {
    final theme = Theme.of(context);
    final name = cardDisplayName(card);
    final bound = card.id == boundId && boundId.isNotEmpty;
    return Padding(
      key: BindCharSheetKeys.row(card.id),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          AvatarDot(name: name, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(name,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis),
                Text(_vitalsOf(card), style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          RoomTap(
            key: BindCharSheetKeys.pick(card.id),
            label: bound ? '已在房间' : '绑定',
            icon: bound ? Icons.check : Icons.link,
            hint: bound ? '当前已绑定这张卡' : '带上这张卡进房间',
            minSize: const Size(88, 40),
            onTap: () => unawaited(_pick(scope, card)),
          ),
        ],
      ),
    );
  }

  /// 一行数值摘要（只读展示；真值仍以权威端为准）。
  String _vitalsOf(Character card) {
    final st = card.status;
    final hp = st['currentHP'] ?? 0;
    final hpMax = st['maxHP'] ?? 0;
    final san = st['currentSAN'] ?? 0;
    return 'HP $hp / $hpMax · SAN $san';
  }

  /// 绑定 / 更换：先把头像压成跨设备缩略图，再发 `INTENT.CHAR`。
  ///
  /// 顺序对齐老 APP `reportSheet`：**生成完缩略图才发** —— 否则广播出去的
  /// sheet 里头像还是一条本机相对路径，远端照样只能看到首字圆点。
  Future<void> _pick(RoomScope scope, Character card) async {
    if (_busy) return;
    _busy = true;
    try {
      final sheet = await cardToRoomSheetForReport(card);
      if (!mounted) return;
      await scope.controller.sendIntent(RoomIntent.char, <String, Object?>{
        'id': card.id,
        'name': card.characterName,
        'sheet': sheet,
      });
      if (!mounted) return;
      scope.local.showNotice('已绑定「${cardDisplayName(card)}」');
      Navigator.of(context).maybePop();
    } finally {
      _busy = false;
    }
  }

  /// 清空 = 用空白房卡覆盖（不是解绑）。空白卡没有头像 → 载荷里不带 avatar 键。
  ///
  /// ★ 卡名必须显式落成 `''`，不能留缺键：`Character` 的 `characterName` 走
  ///   `jsStr`（JS `String(v)` 语义），而空 map 取到的是 null → 字符串 `null`
  ///   四个字母，广播出去就是一张名叫「null」的卡。空串仍会被
  ///   `raSanitizeSheet` 回落到权威端保留的 `mem.charName`，所以「清空数值但
  ///   保留卡名」的语义不变。
  Future<void> _clear(RoomScope scope) async {
    if (_busy) return;
    _busy = true;
    try {
      final sheet = await cardToRoomSheetForReport(
          Character(<String, Object?>{'characterName': ''}));
      if (!mounted) return;
      await scope.controller.sendIntent(RoomIntent.char, <String, Object?>{
        'id': '',
        'name': '',
        'sheet': sheet,
      });
      if (!mounted) return;
      scope.local.showNotice('已清空房卡数值');
      Navigator.of(context).maybePop();
    } finally {
      _busy = false;
    }
  }
}
