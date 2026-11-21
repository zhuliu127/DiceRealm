// ============================================================
// widgets/unit_picker.dart — 房间单位（玩家 / 怪物 / NPC）统一枚举与选择器
//
// P16 波1-A · KP-1（对抗弹窗选单位）/ KP-6（场景检定编辑检定选单位）共用：
//   · collectUnitOptions(state) 是**纯函数**：只读传入的房间快照，枚举
//     「在线玩家 + 已输入且存活的怪物 / NPC」，首位恒含「全体」项；
//   · showUnitPicker(context, ...) 在纯函数之上补两份**不在 state 里**的
//     本地候选（RoomUiLocal.pendingActors / RoomHostRead.localActors），
//     再走统一弹层壳弹选项；
//   · UnitPickerField 是给两个弹层复用的「点一下弹选择器」表单控件；
//   · unitValueToSeat 把统一 value 翻成 domain 期望的裸 seat / '*'。
//
// ★ value 前缀对齐老 APP 2.13.13：玩家 `p:<seat>`、单位 `a:<id>`、全体 `*`。
// ★ 玩家显示名角色名优先：charName → sheet.name → nickname → '玩家'。
// ★ 只画、只发意图：零权威状态赋值、零规则调用、零 emoji、零 jsStr。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap, jsTruthy;
import '../../../domain/room_model_state.dart' show roomNumber;
import '../room_scope.dart' show RoomScope;
import '../room_text.dart' show roomText;
import '../sheets/room_sheet.dart' show showRoomSheet;
import '../view/combat_view.dart' show combatRows, downRows;
import '../view/room_view.dart' show playersOf;
import 'room_panel_kit.dart' show RoomTap;

/// 「全体」项的 value（场景检定 targetSeat / scene.clue 的合法语义）。
const String kUnitAllValue = '*';

/// 一个可选单位（玩家 / 怪物 / NPC / 全体）的不可变值对象。
class RoomUnitOption {
  const RoomUnitOption({
    required this.value,
    required this.label,
    required this.kind,
    this.base,
  });

  /// 提交用值：玩家 `p:<seat>`、单位 `a:<id>`、全体 `kUnitAllValue`。
  final String value;

  /// 展示用文案（角色名 / 单位名 + 类型后缀）。
  final String label;

  /// `'player'` / `'monster'` / `'npc'` / `'all'`。
  final String kind;

  /// 无卡单位（怪物 / NPC）的对抗 / 检定基准值（1–100，可选）。
  /// 老 APP 口径：单位无人物卡，对抗值由 KP 手输；玩家有卡可留空从卡读。
  final int? base;

  /// 无卡单位选中后由调用方补上对抗值（保留其余字段不变）。
  RoomUnitOption copyWith({int? base}) => RoomUnitOption(
        value: value,
        label: label,
        kind: kind,
        base: base ?? this.base,
      );
}

/// 把一条单位记录翻成 [RoomUnitOption]；PC / 空 id 返回 null。
RoomUnitOption? _recordOption(Map<String, Object?> rec) {
  final id = roomText(rec['id']);
  if (id.isEmpty) return null;
  final kindRaw = roomText(rec['kind']);
  if (kindRaw == 'pc') return null;
  final kind = kindRaw == 'npc' ? 'npc' : 'monster';
  final name = roomText(rec['name']);
  final labelName = name.isEmpty ? id : name;
  return RoomUnitOption(
    value: 'a:$id',
    label: '$labelName（${kind == 'npc' ? 'NPC' : '怪物'}）',
    kind: kind,
  );
}

/// 单位记录是否已不存活（HP 判活守卫 + 倒地 / 濒死 / 昏迷 / 死亡文案）。
/// `hpMax <= 0` 视为「未初始化 / 探索态」，按老 APP unitDown 口径当存活。
bool _recordDown(Map<String, Object?> rec) {
  final pub = asMap(rec['public']);
  if (jsTruthy(pub['down'])) return true;
  final st = roomText(pub['state']);
  if (st == '死亡' || st == '濒死' || st == '昏迷' || st == '倒地') {
    return true;
  }
  final hp = roomNumber(pub['hp'] ?? rec['hp'], 0);
  final hpMax = roomNumber(pub['hpMax'] ?? rec['hpMax'], 0);
  return hpMax > 0 && hp <= 0;
}

/// ★ 契约：枚举房间快照里可见的可选单位。
///
/// 返回列表首项恒为「全体」（`value == kUnitAllValue`），其后为在线玩家、
/// 再其后为战斗槽 / 候选池里存活的怪物 / NPC。调用方若不需要「全体」，
/// 用 [showUnitPicker] 的 `allowAll: false`（默认）过滤即可。
///
/// 纯函数：不读 RoomScope、不读本地态、不修改入参。
List<RoomUnitOption> collectUnitOptions(Map<String, Object?> state) {
  final out = <RoomUnitOption>[
    const RoomUnitOption(value: kUnitAllValue, label: '全体', kind: 'all'),
  ];
  final seen = <String>{kUnitAllValue};

  // ① 在线玩家：角色名优先，value 带 `p:` 前缀。
  for (final m in playersOf(state)) {
    final seat = roomText(m['seat']);
    if (seat.isEmpty) continue;
    final charName = roomText(m['charName']);
    final sheetName = roomText(asMap(m['sheet'])['name']);
    final nick = roomText(m['nickname']);
    final display = charName.isNotEmpty
        ? charName
        : (sheetName.isNotEmpty
            ? sheetName
            : (nick.isNotEmpty ? nick : '玩家'));
    final value = 'p:$seat';
    if (seen.add(value)) {
      out.add(RoomUnitOption(
        value: value,
        label: '$display（玩家）',
        kind: 'player',
      ));
    }
  }

  // ② 战斗槽里已输入的怪物 / NPC（排除已倒地 / HP 归零）。
  final dead = <String>{
    for (final r in downRows(combatRows(state, isKp: true))) r.id,
  };
  for (final raw in asList(asMap(state['combat'])['order'])) {
    final slot = asMap(raw);
    final id = roomText(slot['id']);
    if (id.isEmpty || dead.contains(id)) continue;
    final opt = _recordOption(slot);
    if (opt != null && seen.add(opt.value)) out.add(opt);
  }

  // ③ 状态里若直接带了候选池（部分存档 / 同步形态），宽容列出并去重。
  //    ★ P12 PL-1b：玩家态拿到的 `state['actors']` 是权威端 `makeSync`
  //      下发的**裁剪视图**（每条恰好 `{id,name}`，且只含
  //      `visibleToPlayers == true` 的记录）。`_recordOption` /
  //      `_recordDown` 对这份两键记录天然成立（缺 public/hp → 视为存活、
  //      缺 kind → 按 monster），所以「玩家态只列可见怪」无需二次过滤，
  //      纯函数判据见 [isPlayerVisibleActorRecord]。
  for (final raw in asList(state['actors'])) {
    final rec = asMap(raw);
    if (_recordDown(rec)) continue;
    final opt = _recordOption(rec);
    if (opt != null && seen.add(opt.value)) out.add(opt);
  }

  return out;
}

/// ★ P12 PL-1b：玩家裁剪态 `actors` 记录的纯判据（供 QA 单测）。
///
/// 权威端 `makeSync` 给非 KP 下发的 `actors` 视图里，每条**恰好只有
/// `id` + `name` 两个键**（hp / hpMax / dex / skill / value / armor /
/// attrs / secret / kpOnly 一律不下发）；且只有
/// `visibleToPlayers == true` 的记录才进入该视图，未勾选者完全不下发。
/// 因此「玩家态只列可见怪」等价于「`state['actors']` 里全是这类两键记录」。
///
/// 纯 Dart：不读 RoomScope、不改入参、零副作用；
/// [collectUnitOptions] 本身不调用它（自然枚举已成立，避免推翻 KP
/// 全量态里带属性记录的既有行为）。
bool isPlayerVisibleActorRecord(Object? raw) {
  if (raw is! Map) return false;
  final rec = asMap(raw);
  if (rec.length != 2) return false;
  if (!rec.containsKey('id') || !rec.containsKey('name')) return false;
  return roomText(rec['id']).isNotEmpty;
}

/// ★ 契约：弹层选单位，返回选中项；点空白 / 返回键关闭则为 null。
///
/// 在 [collectUnitOptions] 之上补两份**不在 state 里**的本地候选：
/// `RoomUiLocal.pendingActors`（本地加怪草稿）与
/// `RoomHostRead.localActors`（开战前候选池，随存档）。这样探索态
/// （combat.order 为空）也能列出怪物 / NPC，对齐老 APP actorPool 口径。
///
/// `allowAll` 为 false（默认）时过滤掉「全体」项（对抗弹窗用）；
/// 场景检定传 true 保留「全体」。
Future<RoomUnitOption?> showUnitPicker(
  BuildContext context, {
  required String title,
  bool allowAll = false,
}) {
  final scope = context.getInheritedWidgetOfExactType<RoomScope>();
  final state = scope?.session.state ?? const <String, Object?>{};
  final options = <RoomUnitOption>[...collectUnitOptions(state)];
  final seen = <String>{for (final o in options) o.value};

  void merge(List<Map<String, Object?>> rows) {
    for (final rec in rows) {
      if (_recordDown(rec)) continue;
      final opt = _recordOption(rec);
      if (opt == null || !seen.add(opt.value)) continue;
      options.add(opt);
    }
  }

  if (scope != null) {
    merge(scope.local.pendingActors);
    final hostRead = scope.session.hostRead;
    if (hostRead != null) merge(hostRead.localActors);
  }

  final items = <RoomUnitOption>[
    for (final o in options)
      if (allowAll || o.value != kUnitAllValue) o,
  ];
  return showRoomSheet<RoomUnitOption>(
    context: context,
    title: title,
    body: (BuildContext _) => _UnitPickerBody(options: items),
  );
}

/// 选单位表单控件：显示当前值，点击弹 [showUnitPicker]。
///
/// [display] 由调用方提供（未选一般是「未选」），[onPicked] 收到选中项后
/// 由调用方 setState 更新自己的草稿，控件本身不持有可变状态。
class UnitPickerField extends StatelessWidget {
  const UnitPickerField({
    super.key,
    required this.label,
    required this.display,
    required this.onPicked,
    this.title = '选择单位',
    this.allowAll = false,
    this.enabled = true,
  });

  /// 字段名（如「申请单位」「目标座位」）。
  final String label;

  /// 当前选中项的展示文案。
  final String display;

  final ValueChanged<RoomUnitOption> onPicked;

  /// 选择弹层标题。
  final String title;

  /// 是否保留「全体」项。
  final bool allowAll;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return RoomTap(
      key: key,
      label: '$label：$display',
      hint: '点击选择单位',
      enabled: enabled,
      onTap: enabled
          ? () async {
              final picked = await showUnitPicker(
                context,
                title: title,
                allowAll: allowAll,
              );
              if (picked != null) onPicked(picked);
            }
          : null,
    );
  }
}

/// 载荷适配：把统一枚举的 value 翻成 domain 期望的「裸 seat / '*'」。
///
/// 对抗弹窗（KP-1）直接用带前缀的 value（对齐老 APP 对抗口径）；
/// 场景检定（KP-6）的 `targetSeat` / `seat` 历来是裸 seat，故在此剥前缀，
/// 载荷字段名与 domain 处理逻辑都不改。`a:<id>` 按用户放宽口径剥成 id。
String unitValueToSeat(String value) {
  if (value == kUnitAllValue) return kUnitAllValue;
  if (value.startsWith('p:') || value.startsWith('a:')) {
    return value.substring(2);
  }
  return value;
}

/// 选单位弹层内容：每个候选项一个 RoomTap，点即 pop 回该项。
class _UnitPickerBody extends StatelessWidget {
  const _UnitPickerBody({required this.options});

  final List<RoomUnitOption> options;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('没有可选单位', style: TextStyle(fontSize: 12)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final o in options)
          RoomTap(
            key: ValueKey<String>('unitPicker/${o.value}'),
            label: o.label,
            hint: '选择 ${o.label}',
            onTap: () => Navigator.of(context).pop<RoomUnitOption>(o),
          ),
      ],
    );
  }
}
