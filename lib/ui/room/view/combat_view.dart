// ============================================================
// view/combat_view.dart — 战斗顺序只读派生（设计 §3.6）
//
// ★ 纯 Dart：零 UI 框架依赖。
// ★ K4：combat.order 已是按座位裁剪后的数据，UI 既不删也不补；
//   `hpPublic == false` 时显示「隐藏」，绝不把缺键当成 0。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_state.dart'
    show roomClone, roomNumber;
import '../room_text.dart';

/// 战斗顺序的一行（不可变值对象）。
class CombatRow {
  const CombatRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.seat,
    required this.hp,
    required this.hpMax,
    required this.hpHidden,
    required this.stateText,
    required this.isCurrent,
    required this.actionsPerRound,
    required this.playerNameOnly,
  });

  final String id, name, kind, seat, stateText;
  final num hp, hpMax;

  /// true → UI 显示「隐藏」而不是 0（K4 缺键 ≠ 0）。
  final bool hpHidden;
  final bool isCurrent;
  final int actionsPerRound;

  /// ★ P13 COMBAT-1：玩家侧的「怪物 / NPC」行只显示名字。
  ///
  ///   数据层 `combatFor` / `_cropCombat` 已删怪物的 `public.hp / hpMax` 与
  ///   `secret / kpOnly / attrs`，这里只是把「只显名字」的意图显式化，供
  ///   战斗列表 / 战斗条据此裁剪 HP、类型、状态、行动次数等属性文案。
  ///   KP 视角恒 false；玩家侧 PC 行也恒 false（玩家之间 HP 互相可见）。
  ///   ★ P14 COMBAT-6：只裁**内容**，卡壳与布局骨架与 PC 行完全一致
  ///   （同 Card / 边框 / 内边距 / 字号 / 行数占位），保证形式统一。
  final bool playerNameOnly;
}

Map<String, Object?> _combatOf(Map<String, Object?> state) =>
    asMap(state['combat']);

/// 顺序表 → 行列表。[isKp] 为 true 时可用 secret/kpOnly 里的 HP 补全，
/// 但玩家视角绝不越权读取（这两键在裁剪时已被删）。
List<CombatRow> combatRows(Map<String, Object?> state, {required bool isKp}) {
  final c = _combatOf(state);
  final order = asList(c['order']);
  final turn = roomNumber(c['turn'], 0).toInt();
  final rows = <CombatRow>[];

  for (var i = 0; i < order.length; i++) {
    final slot = asMap(order[i]);
    final pub = asMap(slot['public']);
    final hpPublic = jsTruthy(pub['hpPublic']);
    // ★ P16 KP-4①：兼容两种槽结构 —— combatStart 写 public.{hp,hpMax}，
    //   而 combat.actor / 旧存档可能是扁平 actor（hp/hpMax 在顶层）。
    //   有 public 键用 public，缺键回退顶层原值，绝不把缺键当成 0（K4）。
    //   玩家侧裁剪会删 public.hp；此时顶层无 hp 则回退 0，但会被
    //   hidden=true 盖成「隐藏」，不泄露数值。
    num hp = pub.containsKey('hp')
        ? roomNumber(pub['hp'], roomNumber(slot['hp'], 0))
        : roomNumber(slot['hp'], 0);
    num hpMax = pub.containsKey('hpMax')
        ? roomNumber(pub['hpMax'], roomNumber(slot['hpMax'], hp))
        : roomNumber(slot['hpMax'], hp);
    var hidden = !hpPublic;

    if (isKp && hidden) {
      final secret = asMap(slot['secret']);
      final kpOnly = asMap(slot['kpOnly']);
      // ★ 缺键时**保持上一步算出的值**（不能写 `roomNumber(x, hp)`：
      //   roomNumber 对 null 恒返回 0，会把扁平槽的顶层 hp 抹成 0 = K4 复现）。
      final secretHp = secret['hp'] ?? kpOnly['hp'];
      final secretHpMax = secret['hpMax'] ?? kpOnly['hpMax'];
      if (secretHp != null) hp = roomNumber(secretHp, hp);
      if (secretHpMax != null) hpMax = roomNumber(secretHpMax, hpMax);
      hidden = false;
    }

    var stateText = roomText(pub['state']);
    if (stateText.isEmpty) {
      stateText = jsTruthy(pub['down']) ? '倒地' : '正常';
    }

    rows.add(CombatRow(
      id: roomText(slot['id']),
      name: roomText(slot['name']),
      kind: roomText(slot['kind']),
      seat: roomText(slot['seat']),
      hp: hp,
      hpMax: hpMax,
      hpHidden: hidden,
      stateText: stateText,
      isCurrent: i == turn,
      actionsPerRound: roomNumber(slot['totalSlots'], 1).toInt(),
      // ★ P13 COMBAT-1：玩家侧怪物/NPC 只显名字；KP 与玩家 PC 行不裁剪。
      playerNameOnly: !isKp && jsStr(slot['kind']) != 'pc',
    ));
  }
  return rows;
}

/// ★ P13 COMBAT-1 / P14 COMBAT-4：玩家可见的参战怪物/NPC，**只含 id + name**。
///
///   数据层 `state['combat']` 在玩家端已经过 [combatFor] / `_cropCombat`
///   裁剪（`public.hp` 被摘、`secret / kpOnly / attrs` 被删）。★ P14 起
///   **开打后的槽不再按 `visibleToPlayers` 过滤**（参战即公开，用户问题 6），
///   所以这里天然能看到全部参战怪物；尚未参战的隐藏怪仍不在 `actors` 里。
///   返回项**仅** `id` / `name` 两键，绝不带 hp / hpMax / armor / value / secret。
///   供战斗条与「攻击对抗」防守方选择复用，避免 UI 越权读怪物属性。
///
///   [id] 取战斗槽的 `actorId ?? id`（去 `#n` 多行动后缀的基 id），
///   与 domain 侧 `opposedDamageMonster` / `targetId` 的口径一致。
List<Map<String, Object?>> visibleCombatActors(Map<String, Object?> state) {
  final c = _combatOf(state);
  final order = asList(c['order']);
  final out = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final raw in order) {
    final slot = asMap(raw);
    final kind = jsStr(slot['kind']);
    if (kind == 'pc' || kind.isEmpty) continue;
    final rawId = jsStr(slot['actorId']).isNotEmpty
        ? jsStr(slot['actorId'])
        : jsStr(slot['id']);
    // 去掉多行动 #n 后缀，同一单位只列一次。
    final hash = rawId.indexOf('#');
    final baseId = hash >= 0 ? rawId.substring(0, hash) : rawId;
    if (baseId.isEmpty || !seen.add(baseId)) continue;
    final name = roomText(slot['name']);
    out.add(<String, Object?>{
      'id': baseId,
      'name': name.isEmpty ? baseId : name,
    });
  }
  return out;
}

/// 当前行动槽（只读深拷贝）；没有顺序表时返回 null。
Map<String, Object?>? curSlot(Map<String, Object?> state) {
  final order = asList(_combatOf(state)['order']);
  if (order.isEmpty) return null;
  final turn = roomNumber(_combatOf(state)['turn'], 0).toInt();
  final idx = turn < 0 ? 0 : (turn >= order.length ? order.length - 1 : turn);
  return asMap(roomClone(order[idx]));
}

/// 当前是不是 [seat] 的回合。
bool isMyTurn(Map<String, Object?> state, String seat) {
  final slot = curSlot(state);
  return slot != null && roomText(slot['seat']) == seat;
}

/// '第 3 轮 · 行动 2/5'。
///
/// ★ P10 第 7 期 C 批 B：本函数**原样保留** —— 既有 `room_view_test.dart`
///   与战斗面板的既有口径都依赖它；新增的老 APP 口径走 [initiativeText]。
String roundText(Map<String, Object?> state) {
  final c = _combatOf(state);
  final order = asList(c['order']);
  final rawRound = roomNumber(c['round'], roomNumber(asMap(state['meta'])['round'], 1));
  final round = rawRound <= 0 ? 1 : rawRound.toInt();
  final turn = roomNumber(c['turn'], 0).toInt();
  final total = order.length;
  final cur = total == 0 ? 0 : (turn < 0 ? 1 : (turn >= total ? total : turn + 1));
  return '第 $round 轮 · 行动 $cur/$total';
}

/// 老 APP `initiativeBar` 顶部一行：「第 N 轮 · 当前行动：X」。
///
/// ★ 纯函数、每次从 [state] 现算：`combat.next` 推进 `turn` 后，调用方
///   只要重新 build 就能拿到新的当前行动者，不需要任何本地缓存。
/// ★ 名字缺失时回退到槽 id，再回退到「—」；绝不把缺键当成 0（K4）。
String initiativeText(Map<String, Object?> state) {
  final c = _combatOf(state);
  final rawRound =
      roomNumber(c['round'], roomNumber(asMap(state['meta'])['round'], 1));
  final round = rawRound <= 0 ? 1 : rawRound.toInt();
  final slot = curSlot(state);
  final name = slot == null ? '' : roomText(slot['name']);
  final id = slot == null ? '' : roomText(slot['id']);
  final who = name.isNotEmpty ? name : (id.isNotEmpty ? id : '—');
  return '第 $round 轮 · 当前行动：$who';
}

/// 判活失败的行（含 `hpMax > 0` 守卫：HP 隐藏 / 未初始化的单位不判死）。
List<CombatRow> downRows(List<CombatRow> rows) => rows
    .where((r) =>
        !r.hpHidden &&
        r.hpMax > 0 &&
        (r.hp <= 0 ||
            r.stateText == '死亡' ||
            r.stateText == '濒死' ||
            r.stateText == '昏迷' ||
            r.stateText == '倒地'))
    .toList();
