// ============================================================
// sheets/sheet_misc.dart — 杂项弹层
//   规则参考 · 物品道具 · UI 缩放 · 观众名单 · 本机工具 · 玩家申请
//
// 分区各自只读 / 只发 intent：
//   · 规则参考是**纯文本速查**，不参与任何判定（判定在权威端）；
//   · 物品道具读自己的房卡（`itemsOf` / `weaponsOf`）；
//   · UI 缩放只改 `local.zoom`（60–100%，五档），**零发包**；
//   · 音乐控制台（P2-03 / P10 第 5 期）**已于 P17 / KP-8 上移一级** ——
//     真入口现在在「KP 工具」弹层（`sheet_kp_panel.dart` 的 KpPanel），
//     本弹层不再放该条目（本机身份的音乐控制台仍只在本机播放，不联网、
//     不同步、不进存档、不碰房间状态，见 sheet_music.dart）；
//   · 游戏历史导出（P2-06）是真入口：点开是完整可复制文本 + 复制 / 系统分享
//     两个真动作，平台动作走可注入端口（见 sheet_history_export.dart）；
//   · 玩家「申请」一节（P17 / P-3）：申请治愈疯狂状态 / 申请治愈重伤，走
//     `madness.cure` / `sheet.healwound`（POLICY 均 `[player,kp] + confirm.kp`），
//     权威端在确认后才生效；**昏迷 / 疯狂锁定态刻意不加锁** —— 用户口径是
//     锁定期间只放行「推进 1 轮」+「更多工具」，申请就长在「更多工具」里，
//     且 `_passSelf`（room_model_host_intent.dart:95-111）本就放行这两个 op；
//   · AI RP 真入口在聊天输入行的魔棒图标；「更多工具」弹层不再放 AI RP
//     条目（P16 波1-A / P-2，产品口径变更）。
//
// ★ 本文件读 `local`（缩放档位与百分比），所以**自己包**
//   `ListenableBuilder(listenable: local)` —— 不依赖父级重建。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/room_types.dart' show RoomRole;
import '../room_scope.dart' show RoomScope;
import '../room_ui_local.dart' show RoomUiLocal;
import '../view/room_view.dart' show findMe, spectatorsOf;
import '../view/sheet_view.dart' show itemsOf, weaponsOf;
import '../widgets/room_panel_kit.dart' show ConfirmTwice, RoomTap;
import 'room_sheet.dart' show showRoomSheet;
import 'sheet_history_export.dart'
    show
        RoomHistoryExportPort,
        kRoomHistoryExportPolicyOp,
        openRoomHistoryExportSheet;
import '../room_text.dart';

/// 杂项弹层内部稳定 key。
class MiscSheetKeys {
  const MiscSheetKeys._();

  static const Key root = ValueKey<String>('misc/root');
  static const Key rules = ValueKey<String>('misc/rules');
  static const Key items = ValueKey<String>('misc/items');
  static const Key itemsEmpty = ValueKey<String>('misc/itemsEmpty');
  static const Key zoomPct = ValueKey<String>('misc/zoomPct');
  static const Key zoomReset = ValueKey<String>('misc/zoomReset');

  /// P10 第 5 期 B：缩放按钮组的**可见**说明（不能只塞进 Tooltip hint）。
  static const Key zoomHint = ValueKey<String>('misc/zoomHint');

  /// 5 个百分比按钮所在的那一行（几何用例逐个取 top 验证同一行）。
  static const Key zoomRow = ValueKey<String>('misc/zoomRow');
  static const Key spectators = ValueKey<String>('misc/spectators');

  /// 音乐控制台（P2-03 / P10 第 5 期）：真入口，打开本机播放控制台。
  ///
  /// ★ P17 / KP-8：该入口**已从「更多工具」上移一级到「KP 工具」**
  ///   （`sheet_kp_panel.dart` 的 `KpPanelKeys.music`）。本常量**刻意保留**，
  ///   原因同 [aiEntry]：既有测试仍按名字引用它，删了会连带断编译；
  ///   它不代表本弹层还有该 UI。
  static const Key musicEntry = ValueKey<String>('misc/music');

  /// 「本机工具」这一节的标题（P17 / KP-8 后只剩游戏历史导出）。
  static const Key musicSection = ValueKey<String>('misc/musicSection');

  /// 游戏历史导出（P2-06）：真入口，打开完整可复制文本弹层。
  static const Key historyExport = ValueKey<String>('misc/historyExport');

  /// 旧「更多工具」弹层里的 AI RP 禁用指引件 key。
  /// ★ P16 波1-A / P-2：该条目已删除；常量**刻意保留**，仅为兼容既有测试
  ///   对 `MiscSheetKeys` 的引用（波2 统一重写门禁契约时再收拾）。
  static const Key aiEntry = ValueKey<String>('misc/ai');

  /// 同上：旧的 AI RP 指引文字 key，弹层已不再渲染。
  static const Key aiHint = ValueKey<String>('misc/aiHint');

  /// P17 / P-3：「申请」这一节的标题（仅玩家侧渲染）。
  static const Key applySection = ValueKey<String>('misc/applySection');

  /// P17 / P-3：「申请治愈疯狂状态」→ `madness.cure`。
  ///
  /// ★ 不用 `RoomKeys.action(op)`：T-30 的静态锚点表钉死了 `act/<op>` 锚点
  ///   数量（`room_ui_permission_test.dart:321` 断言 30 个），这里挂锚点会
  ///   改锚点表口径；申请按钮的权限闸门由本文件内部 `gate.can` 承担。
  static const Key applyMadnessCure = ValueKey<String>('misc/applyMadnessCure');

  /// P17 / P-3：「申请治愈重伤」→ `sheet.healwound`。
  static const Key applyHealWound = ValueKey<String>('misc/applyHealWound');

  /// 缩放档位按钮（`misc/zoom/<百分比>`）。
  static Key zoom(int pct) => ValueKey<String>('misc/zoom/$pct');

  /// 单件物品的「删除」（`misc/itemDel/<id>`）。
  ///
  /// ★ 不用 `RoomKeys.action('item.del')`：一行一个，N 件物品会让同一个 key
  ///   多命中，表驱动探针没法逐点（与 `RoomLobbyKeys.kick` 同一口径）。
  static Key itemDel(String id) => ValueKey<String>('misc/itemDel/$id');
}

/// 打开「杂项」弹层。
Future<void> openMiscSheet(BuildContext context) => showRoomSheet<void>(
      context: context,
      title: '更多工具',
      body: (BuildContext _) => const MiscSheet(),
    );

/// 杂项弹层主体。
class MiscSheet extends StatelessWidget {
  const MiscSheet({
    super.key,
    this.historyExportPort,
    this.historyExportNowMs,
  });

  /// 测试注入点：平台动作替身（生产为 null → 系统实现）。
  final RoomHistoryExportPort? historyExportPort;

  /// 测试注入点：固定时钟（生产为 null → 系统时钟）。
  final int Function()? historyExportNowMs;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final local = scope.local;
    final state = scope.session.state;
    final seat = scope.session.seat;
    // P17 / P-3：申请按钮只在玩家侧渲染 —— KP 走「定向指令」弹层（同一批 op，
    // 且能指定目标），两边共用本弹层时重复放一遍会变成两个入口。
    final isPlayer = scope.session.role == RoomRole.player;
    final me = findMe(state, seat);
    final items = itemsOf(me);
    final weapons = weaponsOf(me);
    final watchers = spectatorsOf(state);

    // ★ 缩放档位与百分比都来自 local：自己订阅，父级不保证重建。
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) {
        final theme2 = Theme.of(ctx);
        return Column(
          key: MiscSheetKeys.root,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // ---- 规则参考 ----
            Text('规则参考（COC 7 版速查）',
                style: theme2.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '· 技能检定：掷 1D100，≤ 技能值为成功；≤ 1/2 为困难成功，'
              '≤ 1/5 为极难成功，01 大成功，96–100 大失败。\n'
              '· 对抗：双方各掷 1D100，成功等级高者胜；同级比技能值。\n'
              '· SAN 损失：成功扣「/」前半，失败扣后半；单次 ≥5 点触发疯狂检定。\n'
              '· 重伤：单次伤害 ≥ 最大 HP 一半；濒死需急救，否则每轮流失 HP。',
              key: MiscSheetKeys.rules,
              style: theme2.textTheme.bodySmall,
            ),
            const Divider(height: 18),
            // ---- 物品道具 ----
            Text('物品与武器', style: theme2.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (items.isEmpty && weapons.isEmpty)
              Text(
                '房卡上还没有物品（绑定角色卡后自动带上）',
                key: MiscSheetKeys.itemsEmpty,
                style: theme2.textTheme.bodySmall,
              )
            else
              Column(
                key: MiscSheetKeys.items,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final it in items)
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '· ${roomText(it['name'])}'
                            '${roomText(it['qty']).isEmpty ? '' : ' × ${roomText(it['qty'])}'}'
                            '${roomText(it['note']).isEmpty ? '' : '（${roomText(it['note'])}）'}',
                            style: theme2.textTheme.bodySmall,
                          ),
                        ),
                        // ★ PRD `_p5_prd.md:522`（删物品 | 物品弹层 | {id} |
                        //   item.del | [kp,player]）+ `:760` P2-02。
                        //   删除不可逆 → 二次确认；旁观者结构上不渲染
                        //   （POLICY 不含 spectator，能力边界不靠置灰）。
                        if (scope.controller.gate.can('item.del'))
                          ConfirmTwice(
                            key: MiscSheetKeys.itemDel(roomText(it['id'])),
                            label: '删除',
                            confirmLabel: '再点一次',
                            onConfirmed: () => scope.controller.hostAction(
                              'item.del',
                              <String, Object?>{'id': roomText(it['id'])},
                            ),
                          ),
                      ],
                    ),
                  for (final w in weapons)
                    Text(
                      // P12：武器行原本用 ⚔ 起头，与上面的物品行（· 起头）
                      // 不一致；emoji 去掉后统一成同一个行首。
                      '· ${roomText(w['name'])}'
                      '${roomText(w['damage']).isEmpty ? '' : ' · ${roomText(w['damage'])}'}',
                      style: theme2.textTheme.bodySmall,
                    ),
                ],
              ),
            const Divider(height: 18),
            // ---- UI 缩放 ----
            Row(
              children: <Widget>[
                Text('界面缩放', style: theme2.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  '${(local.zoom * 100).round()}%',
                  key: MiscSheetKeys.zoomPct,
                  style: theme2.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                RoomTap(
                  key: MiscSheetKeys.zoomReset,
                  icon: Icons.restart_alt,
                  hint: '恢复 100%',
                  minSize: const Size(44, 32),
                  onTap: () => local.setZoom(1),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // ★ P10 第 5 期 B：用户反馈「不知道这几个百分比数字是缩放」。
            //   标题本来就有，这里再补一句**可见**说明（不是只塞 Tooltip）。
            Text(
              '下面这排百分比按钮用来缩放界面（60%–100%），点一下立即生效。',
              key: MiscSheetKeys.zoomHint,
              style: theme2.textTheme.bodySmall
                  ?.copyWith(color: theme2.colorScheme.secondary),
            ),
            const SizedBox(height: 4),
            // ★ 用户反馈「一行一个太占位置」：5 个 chip 压到同一行。
            //   缩小档位按钮的最小宽度与间距（不改全局 48dp 热区常量），
            //   320dp 窄屏的弹层（去掉左右 12dp 内边距后约 296dp）也放得下。
            Wrap(
              key: MiscSheetKeys.zoomRow,
              spacing: 3,
              runSpacing: 4,
              children: <Widget>[
                for (final pct in RoomUiLocal.zoomSteps) _zoomChip(local, pct),
              ],
            ),
            const Divider(height: 18),
            // ---- 观众名单 ----
            Text('观众名单（${watchers.length}）',
                style: theme2.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              watchers.isEmpty
                  ? '暂无观众'
                  : watchers
                      .map((m) => roomText(m['nickname']).isEmpty
                          ? roomText(m['seat'])
                          : roomText(m['nickname']))
                      .join('、'),
              key: MiscSheetKeys.spectators,
              style: theme2.textTheme.bodySmall,
            ),
            const Divider(height: 18),
            // ---- 本机工具（P2-06 游戏历史导出） ----
            // ★ P17 / KP-8：音乐控制台入口已上移一级到「KP 工具」弹层
            //   （`sheet_kp_panel.dart` 的 KpPanel），本节只剩游戏历史导出。
            //   标题 key `MiscSheetKeys.musicSection` 刻意沿用（既有测试按名引用）。
            Text('本机工具',
                key: MiscSheetKeys.musicSection,
                style: theme2.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                // ★ P2-06：权限沿用可点性闸门（chat = [kp, player]）。
                //   旁观者权限不足 → 结构上不渲染入口，而不是置灰假按钮。
                if (scope.controller.gate.can(kRoomHistoryExportPolicyOp))
                  RoomTap(
                    key: MiscSheetKeys.historyExport,
                    icon: Icons.article_outlined,
                    label: '导出游戏历史',
                    hint: '生成公开记录与聊天的完整文本，可复制 / 系统分享',
                    minSize: const Size(140, 40),
                    onTap: () => openRoomHistoryExportSheet(
                      ctx,
                      port: historyExportPort,
                      nowMs: historyExportNowMs,
                    ),
                  ),
                // ★ P16 波1-A / P-2：AI RP 禁用指引件已从「更多工具」弹层
                //   删除。真入口仍在聊天输入行与角色卡短按钮（都不属本文件），
                //   本弹层不再重复放 AI RP 条目。
              ],
            ),
            // ---- 申请（P17 / P-3）：玩家侧提交给 KP 确认的两个治愈申请 ----
            //
            // ★ 只在玩家侧渲染（见 `isPlayer`）：KP 有「定向指令」弹层。
            // ★ **不叠加 `operationLocked`**：用户口径是昏迷 / 疯狂时只放行
            //   「推进 1 轮」+「更多工具」，申请就长在「更多工具」里；在这里
            //   再叠一层锁，等于把锁定态唯一的自救出口也锁死。权威端
            //   `_passSelf`（room_model_host_intent.dart:95-111）本就放行
            //   `madness.cure` / `sheet.healwound`，且 POL ID 均为
            //   `[player, kp] + RoomConfirm.kp` —— 只留 `gate.can` 这一道闸门。
            // ★ 载荷与 `kpDirectivePayload`（sheet_kp_directives.dart:157-160）
            //   同口径：`{'seat': 自己的座位}`，显式传比让 domain 兜底更稳。
            if (isPlayer) ...<Widget>[
              const Divider(height: 18),
              Text('申请（由 KP 确认后生效）',
                  key: MiscSheetKeys.applySection,
                  style: theme2.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '· 治愈重伤：只能申请治自己（需处于重伤 / 濒死 / 昏迷）。\n'
                '· 治愈疯狂：只覆盖「不定疯狂 / 潜在疯狂」；临时疯狂点「推进 1 轮」自消。',
                style: theme2.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  if (scope.controller.gate.can('madness.cure'))
                    RoomTap(
                      key: MiscSheetKeys.applyMadnessCure,
                      icon: Icons.healing,
                      label: '申请治愈疯狂状态',
                      hint: '提交申请给 KP：治愈「不定疯狂 / 潜在疯狂」'
                          '（临时疯狂点「推进 1 轮」自消）',
                      minSize: const Size(150, 40),
                      onTap: () => scope.controller.hostAction(
                        'madness.cure',
                        <String, Object?>{'seat': seat},
                      ),
                    ),
                  if (scope.controller.gate.can('sheet.healwound'))
                    RoomTap(
                      key: MiscSheetKeys.applyHealWound,
                      icon: Icons.medical_services,
                      label: '申请治愈重伤',
                      hint: '提交申请给 KP：治愈自己的重伤 / 濒死 / 昏迷（只能治自己）',
                      minSize: const Size(130, 40),
                      onTap: () => scope.controller.hostAction(
                        'sheet.healwound',
                        <String, Object?>{'seat': seat},
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _zoomChip(RoomUiLocal local, int pct) {
    final active = (local.zoom * 100).round() == pct;
    return RoomTap(
      key: MiscSheetKeys.zoom(pct),
      label: '$pct%',
      hint: '缩放到 $pct%',
      minSize: const Size(54, 34),
      onTap: () => local.setZoom(pct / 100),
      enabled: !active,
    );
  }
}
