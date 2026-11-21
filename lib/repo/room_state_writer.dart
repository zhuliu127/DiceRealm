// ============================================================
// room_state_writer.dart — 房间状态 → 本机角色卡的唯一落盘适配器（R01 / C5）
//
// ★ 全库「房间写回」路径里**唯一** `await repo.save(card)` 的地方。
//   domain 只出 `resolveRoomCardPatch` 纯函数 + `RoomCardSink` 抽象端口，
//   不反向依赖 lib/repo（否则会把 dart:io / Flutter 带进纯 Dart 规则层）。
//
// 为什么必须经过 CharacterRepo.save：
//   repo.save 内部统一走 applyExplicitStatusMarks → normalize → recalc，
//   其中 marks 会把「JSON 里显式存在的 0」打上 _hpTouched 标记。
//   绕过它直接 card.status[k]=v 落盘，导入/房间回写的濒死卡（HP=0）
//   会被 recalc 的三行补值守卫**治活**（QA 的 D1 缺陷，P0-M07）。
//
// 定位规则见 domain/resolveRoomCardPatch：charId 命中才写、找不到即
// card_not_found、绝不退到 current 别的卡；未绑定卡才退 current 并标 source。
// ============================================================

import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../domain/room_model_save.dart' show resolveRoomCardPatch;
import '../domain/room_ports.dart';

import 'character_repo.dart';

/// 把房间侧的 `RoomCardPatch` 落到 [CharacterRepo] 里的角色卡。
class CharacterRepoRoomCardSink implements RoomCardSink {
  const CharacterRepoRoomCardSink(this.repo, {this.currentCardId});

  final CharacterRepo repo;

  /// 未绑定卡（patch.charId == null）时用作 `current` 的卡 id。
  ///
  /// CharacterRepo 没有旧版 store 的「当前卡」概念，所以由调用方显式指定；
  /// 不指定时 current 为 null → 返回 `no_card`，绝不猜一张卡来写。
  final String? currentCardId;

  @override
  Future<CardWriteResult> write(RoomCardPatch patch) async {
    // 1) 定位 + 应用 patch（纯 Map 变换，命中前绝不落盘）。
    final cards = <String, Map<String, Object?>>{};
    for (final c in repo.all) {
      // Character.toJson() 返回的就是 repo 内部那份 raw（同一引用），
      // resolveRoomCardPatch 的就地写入会落到 repo 的内存态上。
      cards[c.id] = c.toJson();
    }
    final currentId = currentCardId;
    final current = currentId == null ? null : repo.get(currentId)?.toJson();
    final res = resolveRoomCardPatch(patch, cards, current);
    if (!res.ok) return res;

    // 2) 取命中的那张卡（characters 优先，其次同 id 的 current）。
    final hit = cards[res.cardId] ?? current;
    if (hit == null) {
      return CardWriteResult(
        ok: false,
        reason: 'card_not_found',
        cardId: res.cardId,
      );
    }

    // 3) ★ C5：唯一落盘入口。applyExplicitStatusMarks→normalize→recalc
    //    在 repo.save 内部统一执行，濒死卡 HP=0 不会被补满。
    await repo.save(Character(asMap(hit)));
    return res;
  }
}
