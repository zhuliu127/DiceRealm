// ============================================================
// room_lobby_page.dart — 大厅页（招募中）R1–R6 + 招募期房间生命周期
//
// 流程位置：入口页创建 / 加入 → **本页**（`meta.status == RECRUITING`）
//   → KP 点「开始游戏」（`room.start`）→ `IN_GAME` → 游戏页壳体。
// 阶段切换由调用方的 `_RoomShell` 负责（整棵子树换 key 重建）。
//
// ★ P7 真机反馈修复（大厅错位显示游戏期按钮）：
//   本页**永远只在招募期渲染**（room_entry_page 的 _RoomStageSwitch 用
//   isInGame(state) 选择本页 / RoomGamePage）。房间管理（切模式 / 战斗准备 /
//   结束战斗）、探索面板、KP 工具、待办状态条、掷骰条这 5 类都是**游戏期**能力，
//   游戏期由 RoomGamePage 的 slot 网格承载（GpStatus / GpDiceBar /
//   GpKpTools / GpMapStage / KP 面板），不该在招募期重复出现。
//   ★ 但「结束房间 / 结团」是招募期也需要的房间生命周期能力，必须保留；
//     `kick`（成员行踢人）、`copyInvite`（房间头复制邀请）也在 R1 / R3 保留。
//   以下 5 类块统一按 `isInGame(state)` 门控：招募期零渲染，游戏期才出现
//   （防御性分支，防止大厅被误用于游戏期时缺块）。
//
// ★ 权限口径（T-22 / T-30）：
//   · KP 专属块对玩家/旁观者**不渲染**（`isKp ? … : null`），不是禁用；
//   · 凡挂了 `RoomKeys.action(op)` 的按钮，`enabled` 恒等 `gate.can(op)`，
//     业务前置条件（例如「全员准备」）一律写进 hint —— 否则表驱动探针会判漂移。
//     `room.start` 不在此列：它用 `RoomKeys.kpStartGame`（非 POLICY 探针位），
//     所以可以按「是否全员准备」禁用。
//
// ★ 只画、只发动作：零权威端引用、零规则调用。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../domain/js_compat.dart' show asList, asMap, jsParseInt, jsTruthy;
import '../../theme.dart' show Palette;
import '../../domain/room_types.dart'
    show RoomIntent, RoomMode, RoomRole, kHostSeat;
import '../art.dart';
import 'room_controller.dart' show RoomController, RoomGate;
import 'room_keys.dart' show RoomKeys;
import 'room_scope.dart' show RoomScope;
import 'room_theme.dart' show RoomTheme;
import 'sheets/room_sheet.dart' show showRoomSheet;
import 'sheets/sheet_bind_char.dart' show openBindCharSheet;
import 'sheets/sheet_char_view.dart' show showCharViewSheet;
import 'sheets/sheet_kp_panel.dart' show KpDangerAction, showKpPanel;
import 'sheets/sheet_combat.dart' show showCombatSheet;
import 'view/member_view.dart'
    show hasCardVitals, hpText, memberStats, sanText;
import 'sheets/sheet_lan_check.dart' show openLanCheckSheet;
import 'view/room_view.dart'
    show isCombat, isInGame, metaOf, playersOf, roleText, roomStatusText,
        spectatorsOf;
import 'view/scene_view.dart' show assetsOf, publicAssets, sceneOf;
import 'widgets/gp_dice_bar.dart' show GpDiceBar;
import 'widgets/gp_status.dart' show GpStatus;
import 'widgets/room_panel_kit.dart' show AvatarDot, RoomTap, SectionBox;
import 'room_text.dart';

/// 大厅页内部稳定 key（R1–R12 与用例共用）。
class RoomLobbyKeys {
  const RoomLobbyKeys._();

  static const Key root = ValueKey<String>('roomLobby/root');
  static const Key header = ValueKey<String>('roomLobby/header');
  static const Key roomName = ValueKey<String>('roomLobby/roomName');
  static const Key roomCode = ValueKey<String>('roomLobby/roomCode');
  static const Key status = ValueKey<String>('roomLobby/status');
  static const Key copyInvite = ValueKey<String>('roomLobby/copyInvite');
  static const Key leave = ValueKey<String>('roomLobby/leave');
  static const Key service = ValueKey<String>('roomLobby/service');

  /// 服务地址块的说明文案（P6：真实地址 / 未开局域网）。
  static const Key serviceHint = ValueKey<String>('roomLobby/serviceHint');

  /// 服务地址本体（可选中复制）。
  static const Key serviceBase = ValueKey<String>('roomLobby/serviceBase');
  static const Key copyAddress = ValueKey<String>('roomLobby/copyAddress');
  static const Key copyJoin = ValueKey<String>('roomLobby/copyJoin');

  /// 打开「局域网自检」弹层（P6）。
  static const Key lanCheck = ValueKey<String>('roomLobby/lanCheck');
  static const Key members = ValueKey<String>('roomLobby/members');
  static const Key ready = ValueKey<String>('roomLobby/ready');
  static const Key start = ValueKey<String>('roomLobby/start');
  static const Key spectatorNote = ValueKey<String>('roomLobby/spectatorNote');
  static const Key readyHint = ValueKey<String>('roomLobby/readyHint');
  static const Key bindChar = ValueKey<String>('roomLobby/bindChar');
  static const Key closeRoom = ValueKey<String>('roomLobby/closeRoom');
  static const Key modeSwitch = ValueKey<String>('roomLobby/modeSwitch');
  static const Key combatPrep = ValueKey<String>('roomLobby/combatPrep');
  static const Key endCombat = ValueKey<String>('roomLobby/endCombat');
  static const Key explore = ValueKey<String>('roomLobby/explore');
  static const Key sceneName = ValueKey<String>('roomLobby/sceneName');
  static const Key sceneEdit = ValueKey<String>('roomLobby/sceneEdit');
  static const Key addAsset = ValueKey<String>('roomLobby/addAsset');
  static const Key kpTools = ValueKey<String>('roomLobby/kpTools');
  static const Key openKpPanel = ValueKey<String>('roomLobby/openKpPanel');

  // ---- ★ P18 房规（d100 检定阈值；招募期即可设置） ----
  /// KP 侧「大成功上限」输入框。
  static const Key ruleCrit = ValueKey<String>('roomLobby/ruleCrit');
  /// KP 侧「大失败下限」输入框。
  static const Key ruleFumble = ValueKey<String>('roomLobby/ruleFumble');
  /// KP 侧「保存阈值」按钮（复用 `room.rules` op，POLICY `[kp]` 不新增 action）。
  static const Key ruleSave = ValueKey<String>('roomLobby/ruleSave');
  /// 非 KP 侧只读展示当前房规。
  static const Key ruleView = ValueKey<String>('roomLobby/ruleView');

  /// 成员行（`roomLobby/member/<seat>`）。
  static Key memberRow(String seat) => ValueKey<String>('roomLobby/member/$seat');

  /// 成员行上的「查看」。
  static Key memberDetail(String seat) =>
      ValueKey<String>('roomLobby/member/$seat/detail');

  /// 踢人（`roomLobby/member/<seat>/kick`）。
  ///
  /// ★ 不用 `RoomKeys.action('room.kick')`：一行一个，N 个同 key 会让
  ///   `find.byKey` 变成多命中，表驱动探针没法逐点。权限仍按闸门判定。
  static Key kick(String seat) => ValueKey<String>('roomLobby/member/$seat/kick');

  /// 素材行（`roomLobby/asset/<id>`）。
  static Key assetRow(String id) => ValueKey<String>('roomLobby/asset/$id');

  static Key assetReveal(String id) =>
      ValueKey<String>('roomLobby/asset/$id/reveal');

  static Key assetCover(String id) =>
      ValueKey<String>('roomLobby/asset/$id/cover');

  static Key assetDel(String id) => ValueKey<String>('roomLobby/asset/$id/del');
}

/// 大厅页：招募中的房间（R1–R12）。
class RoomLobbyPage extends StatelessWidget {
  const RoomLobbyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final local = scope.local;
    // 本页读 `local`（折叠 / 草稿）——自己订阅，不依赖父级重建。
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext _, Widget? _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final role = scope.session.role;
    final isKp = role == RoomRole.kp;
    final isPlayer = role == RoomRole.player;
    final theme = Theme.of(context);
    final players = playersOf(state);
    final watchers = spectatorsOf(state);
    final inGame = isInGame(state);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          key: RoomLobbyKeys.root,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
          children: <Widget>[
            // 大厅头图（酒馆长桌）。固定 92px：用 AspectRatio 会在
            // 宽视口下吃掉 300+ px，把「开始游戏」推出首屏（入口页踩过）。
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 92,
                width: double.infinity,
                child: ArtImage(
                  Art.lobbyHeaderFor(Palette.brightness),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _header(context, theme, isKp: isKp),
            // R2 只对 KP 渲染
            if (isKp) _serviceBlock(context, theme),
            const SizedBox(height: RoomTheme.panelGap),
            _membersBlock(context, theme, isKp: isKp),
            const SizedBox(height: RoomTheme.panelGap),
            // R4 准备：玩家才有按钮；旁观者只给一句说明
            if (isPlayer) _readyBlock(context, theme),
            if (role == RoomRole.spectator) _spectatorNote(theme, watchers),
            // R5 绑卡：仅玩家
            if (isPlayer) _bindBlock(context, theme),
            // ★ P18 房规：招募期就能看 / 能设。KP 是输入区（复用 `room.rules`
            //   op），玩家/旁观是只读展示 —— 让玩家知道这个房的大成功 /
            //   大失败阈值是多少，掷骰前心里有数。
            if (isKp)
              _ruleCfgBlock(context, theme, state: state)
            else
              _ruleView(context, theme, state: state),
            // R6「开始游戏」+ 招募期房间生命周期（结束房间 / 结团）：仅 KP。
            // ★ 关闭房间 / 踢人 / 复制邀请在招募期仍然必须可用，不随游戏期块移除。
            if (isKp) ...<Widget>[
              const SizedBox(height: RoomTheme.panelGap),
              _startBlock(context, theme, players: players),
              // 招募期才需要「开房后能关房」；游戏期由 _kpManageBlock 承担。
              if (!inGame) _roomLifecycleBlock(context),
            ],
            // ★ 以下 5 类都是游戏期能力：招募期大厅零渲染，游戏期由
            //   RoomGamePage 的 slot 网格承载。这里按 isInGame 门控保留，
            //   保证大厅万一被误用到游戏期也不缺块。
            if (inGame) ...<Widget>[
              const SizedBox(height: RoomTheme.panelGap),
              // ★ 仍守权限口径：房间管理只给 KP，旁观者零发包、零锚点。
              if (isKp) _kpManageBlock(context, theme, state: state),
              const SizedBox(height: RoomTheme.panelGap),
              _exploreBlock(context, theme, isKp: isKp, state: state),
              const SizedBox(height: RoomTheme.panelGap),
              if (isKp) _kpToolsBlock(context, theme),
              const SizedBox(height: RoomTheme.panelGap),
              const GpStatus(),
              const SizedBox(height: RoomTheme.panelGap),
              SectionBox(title: '掷骰', child: const GpDiceBar()),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // R1 房间头卡
  // ----------------------------------------------------------

  Widget _header(
    BuildContext context,
    ThemeData theme, {
    required bool isKp,
  }) {
    final scope = RoomScope.of(context);
    final session = scope.session;
    final meta = metaOf(session.state);
    final name = roomText(meta['name']);
    final status = roomText(meta['status']);
    final code = session.code;
    return SectionBox(
      key: RoomLobbyKeys.header,
      title: '房间',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name.isEmpty ? '（未命名房间）' : name,
                  key: RoomLobbyKeys.roomName,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${roomStatusText(status)} · ${session.link.name}',
                key: RoomLobbyKeys.status,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ★ 房间号单独一行并可收缩：360 竖屏下「号码 + 两个按钮」同排会溢出
          Row(
            children: <Widget>[
              Text('房间号 ', style: theme.textTheme.bodySmall),
              Expanded(
                child: Text(
                  code,
                  key: RoomLobbyKeys.roomCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              RoomTap(
                key: RoomLobbyKeys.copyInvite,
                icon: Icons.ios_share,
                label: '复制邀请',
                hint: '复制房间号邀请朋友（本机预览）',
                minSize: const Size(96, 40),
                onTap: () => _copy(context, '骰境TRPG 房间 $code',
                    '已复制邀请信息：房间 $code'),
              ),
              const Spacer(),
              RoomTap(
                key: RoomLobbyKeys.leave,
                icon: Icons.logout,
                label: '离开',
                hint: '离开房间（不结束房间）',
                minSize: const Size(76, 40),
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isKp
                ? '你是 KP：等人到齐、大家准备后点「开始游戏」。'
                : '等人到齐，KP 会开始游戏。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // R2 服务地址（仅 KP）
  // ----------------------------------------------------------

  Widget _serviceBlock(BuildContext context, ThemeData theme) {
    final session = RoomScope.of(context).session;
    final code = session.code;
    // P6：真实局域网地址（未开局域网时为 null/空串）。
    final String base = session.lanBase ?? '';
    final bool hasLan = base.isNotEmpty;
    return SectionBox(
      key: RoomLobbyKeys.service,
      title: '服务地址（仅 KP 可见）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            hasLan
                ? '同 WiFi 的同伴可在「加入」里手输这个地址（或直接搜到）。'
                : '未开局域网服务（端口被占或没连 WiFi）：这间房只有你自己能进。',
            key: RoomLobbyKeys.serviceHint,
            style: theme.textTheme.bodySmall,
          ),
          if (hasLan) ...<Widget>[
            const SizedBox(height: 4),
            SelectableText(
              base,
              key: RoomLobbyKeys.serviceBase,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              RoomTap(
                key: RoomLobbyKeys.copyAddress,
                icon: Icons.link,
                label: '复制地址',
                hint: hasLan ? '复制 $base' : '当前没有局域网地址',
                enabled: hasLan,
                minSize: const Size(110, 40),
                onTap: () =>
                    _copy(context, base, '已复制服务地址（$base）'),
              ),
              RoomTap(
                key: RoomLobbyKeys.copyJoin,
                icon: Icons.content_copy,
                label: '复制加入信息',
                hint: '房间号 + 服务地址',
                minSize: const Size(136, 40),
                onTap: () => _copy(
                  context,
                  hasLan
                      ? '房间号 $code\n服务地址 $base\n（骰境TRPG）'
                      : '房间号 $code（骰境TRPG）',
                  '已复制加入信息',
                ),
              ),
              // ★ 同伴连不上时，KP 能当场查出是哪一步断了 —— 否则只能
              //   靠「你把地址发我看看」来回试。
              RoomTap(
                key: RoomLobbyKeys.lanCheck,
                icon: Icons.troubleshoot,
                label: '局域网自检',
                hint: '分步检查服务、网卡与连通性',
                minSize: const Size(120, 40),
                onTap: () => openLanCheckSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // R3 成员列表
  // ----------------------------------------------------------

  Widget _membersBlock(
    BuildContext context,
    ThemeData theme, {
    required bool isKp,
  }) {
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final rows = <Map<String, Object?>>[
      ...playersOf(state),
      ...spectatorsOf(state),
    ];
    final gate = scope.controller.gate;
    return SectionBox(
      key: RoomLobbyKeys.members,
      title: '成员（${rows.length}）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final m in rows) _memberRow(context, theme, m, isKp: isKp, gate: gate),
        ],
      ),
    );
  }

  Widget _memberRow(
    BuildContext context,
    ThemeData theme,
    Map<String, Object?> m, {
    required bool isKp,
    required RoomGate gate,
  }) {
    final seat = roomText(m['seat']);
    final nick = roomText(m['nickname']).isEmpty ? seat : roomText(m['nickname']);
    final role = roomText(m['role']);
    final stats = memberStats(m);
    final ready = jsTruthy(m['ready']);
    final self = seat == RoomScope.read(context).session.seat;
    return Padding(
      key: RoomLobbyKeys.memberRow(seat),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          AvatarDot(name: nick, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$nick（${roleText(role)}）${self ? ' · 我' : ''}',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                // ★ P12：与「我的角色卡」/ 玩家栏同源。成员在房间里但一丁点
                //   卡数据都没有时，memberStats 三源回退会静默给 0 —— 那会把
                //   「未初始化」画成一整张 0 的假卡。如实说「未绑卡」，真 0 照显。
                Text(
                  hasCardVitals(m)
                      ? '${hpText(stats, full: true)} · ${sanText(stats, full: true)}'
                      : '未绑卡',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            role == RoomRole.spectator
                ? '旁观'
                : (ready ? '已准备' : '未准备'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: ready ? theme.colorScheme.secondary : null,
            ),
          ),
          RoomTap(
            key: RoomLobbyKeys.memberDetail(seat),
            icon: Icons.badge_outlined,
            hint: '查看 $nick 的角色卡',
            minSize: const Size(40, 32),
            onTap: () => _openMember(context, seat),
          ),
          if (isKp && role != RoomRole.kp)
            RoomTap(
              key: RoomLobbyKeys.kick(seat),
              icon: Icons.person_remove_outlined,
              hint: '把 $nick 移出房间（需谨慎）',
              enabled: gate.can('room.kick'),
              minSize: const Size(40, 32),
              onTap: () {
                RoomScope.read(context)
                    .controller
                    .hostAction('room.kick', <String, Object?>{'seat': seat});
              },
            ),
        ],
      ),
    );
  }

  /// 大厅「预览角色」：接 P10-1 已做好的完整人物卡只读弹层。
  ///
  /// ★ P10 第 6 期（用户真机报「只显示简要状态」）真因：`showCharViewSheet`
  ///   早就存在（基本资料 / 属性 / 技能 / 背景 / 经历 / 装备资产 / 教育进步 /
  ///   状态，且 `showRoomSheet` 自带超屏滚动），但本入口没接它，自己画了
  ///   「座位 / HP·SAN / 卡名」三行。数据是权威端 state 里 `m['sheet']`
  ///   （由别的设备绑卡上报，KP / 本人视角全量可见），**不是**本机卡文件。
  /// ★ P12 `hasCardVitals` 不回退：真没绑卡时只说「未绑卡」，不画一整张 0 卡。
  void _openMember(BuildContext context, String seat) {
    final state = RoomScope.read(context).session.state;
    final m = playersOf(state)
        .followedBy(spectatorsOf(state))
        .firstWhere((Map<String, Object?> x) => roomText(x['seat']) == seat,
            orElse: () => const <String, Object?>{});
    final title =
        roomText(m['nickname']).isEmpty ? seat : roomText(m['nickname']);

    if (!hasCardVitals(m)) {
      showRoomSheet<void>(
        context: context,
        title: title,
        body: (BuildContext _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('座位：$seat · ${roleText(roomText(m['role']))}'),
            const SizedBox(height: 4),
            const Text('未绑卡'),
          ],
        ),
      );
      return;
    }
    showCharViewSheet<void>(context, seat: seat);
  }

  // ----------------------------------------------------------
  // R4 准备（仅玩家）
  // ----------------------------------------------------------

  Widget _readyBlock(BuildContext context, ThemeData theme) {
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final seat = scope.session.seat;
    final me = playersOf(state)
        .firstWhere((Map<String, Object?> m) => roomText(m['seat']) == seat,
            orElse: () => const <String, Object?>{});
    final ready = jsTruthy(me['ready']);
    final charId = roomText(asMap(me['sheet'])['charId']);
    return SectionBox(
      key: RoomLobbyKeys.ready,
      title: '准备',
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              ready
                  ? '已准备，等 KP 开始游戏'
                  : (charId.isEmpty ? '先绑定角色卡才能准备' : '还没准备'),
              key: RoomLobbyKeys.readyHint,
              style: theme.textTheme.bodySmall,
            ),
          ),
          RoomTap(
            icon: ready ? Icons.check_circle : Icons.check_circle_outline,
            label: ready ? '取消准备' : '我准备好了',
            // ★ 权威端规则：没有 charId 时 READY 会被拒（'请先选择角色卡'），
            //   所以这里按业务前置条件禁用，hint 说明原因（T-22 口径）。
            enabled: ready || charId.isNotEmpty,
            hint: ready
                ? '撤回准备状态'
                : (charId.isEmpty ? '先绑定角色卡才能准备' : '告诉 KP 你准备好了'),
            minSize: const Size(120, 40),
            onTap: () {
              scope.controller.sendIntent(RoomIntent.ready, <String, Object?>{
                'ready': !ready,
                'charId': charId,
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _spectatorNote(ThemeData theme, List<Map<String, Object?>> watchers) {
    return SectionBox(
      key: RoomLobbyKeys.spectatorNote,
      title: '旁观中',
      child: Text(
        '旁观中（不能准备）：你只能看，不会进入战斗轮次。',
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  // ----------------------------------------------------------
  // R5 绑定角色卡（仅玩家）
  // ----------------------------------------------------------

  Widget _bindBlock(BuildContext context, ThemeData theme) {
    final scope = RoomScope.of(context);
    final state = scope.session.state;
    final seat = scope.session.seat;
    final me = playersOf(state)
        .firstWhere((Map<String, Object?> m) => roomText(m['seat']) == seat,
            orElse: () => const <String, Object?>{});
    final cardName = roomText(asMap(me['sheet'])['name']);
    return SectionBox(
      key: RoomLobbyKeys.bindChar,
      title: '角色卡',
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              cardName.isEmpty ? '还没绑定角色卡' : '已绑定：$cardName',
              style: theme.textTheme.bodySmall,
            ),
          ),
          RoomTap(
            icon: Icons.badge_outlined,
            label: cardName.isEmpty ? '绑定角色卡' : '更换',
            hint: '从本机角色卡里选一张带进房间',
            minSize: const Size(104, 40),
            onTap: () => openBindCharSheet(context),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // R6 开始游戏（仅 KP）
  // ----------------------------------------------------------

  Widget _startBlock(
    BuildContext context,
    ThemeData theme, {
    required List<Map<String, Object?>> players,
  }) {
    final ctl = RoomScope.read(context).controller;
    final pending = <String>[
      for (final m in players)
        if (!jsTruthy(m['ready'])) roomText(m['nickname']).isEmpty
            ? roomText(m['seat'])
            : roomText(m['nickname']),
    ];
    final canStart = players.isNotEmpty && pending.isEmpty;
    return SectionBox(
      key: RoomLobbyKeys.start,
      title: '开始',
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              canStart
                  ? '全员已准备，可以开始'
                  : (players.isEmpty
                      ? '房间里还没有玩家'
                      : '还差：${pending.join('、')}'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          RoomTap(
            key: RoomKeys.kpStartGame,
            icon: Icons.play_arrow,
            label: '开始游戏',
            // ★ 不挂 `RoomKeys.action('room.start')`：本按钮按「全员准备」禁用，
            //   会让表驱动探针把可点性判成漂移。业务前置条件写在这里。
            hint: canStart ? '进入游戏（IN_GAME）' : '等所有人准备后才能开始',
            enabled: canStart,
            minSize: const Size(120, 40),
            onTap: () => ctl.hostAction('room.start'),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // 招募期房间生命周期（仅 KP）：结束房间 / 结团
  //
  // ★ P7：切模式 / 战斗准备 / 结束战斗属于游戏期，已随 _kpManageBlock
  //   门控掉；但「关闭房间」「结团」在招募期也必须可用（含 T-22 权限闸门），
  //   否则 KP 开了房却关不掉。key 沿用 RoomLobbyKeys.closeRoom，
  //   既有调用点与测试不断裂。
  // ----------------------------------------------------------

  Widget _roomLifecycleBlock(BuildContext context) {
    final ctl = RoomScope.read(context).controller;
    final gate = ctl.gate;
    return SectionBox(
      key: RoomLobbyKeys.closeRoom,
      title: '房间管理（仅 KP · 招募期）',
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          KpDangerAction(
            op: 'room.close',
            label: '结束房间',
            enabled: gate.can('room.close'),
            hint: '关闭房间（连点两次确认）',
            onConfirmed: () => ctl.dangerAction('room.close'),
          ),
          KpDangerAction(
            op: 'room.end',
            label: '结团',
            enabled: gate.can('room.end'),
            hint: '结束整团（连点两次确认）',
            onConfirmed: () => ctl.dangerAction('room.end'),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // R7 结束房间 + R8 模式（仅 KP · 游戏期门控分支）
  // ----------------------------------------------------------

  Widget _kpManageBlock(
    BuildContext context,
    ThemeData theme, {
    required Map<String, Object?> state,
  }) {
    final ctl = RoomScope.read(context).controller;
    final gate = ctl.gate;
    final combat = isCombat(state);
    final mode = roomText(metaOf(state)['mode']);
    return SectionBox(
      key: const Key('roomLobby/manageInGame'),
      title: '房间管理（仅 KP）',
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          KpDangerAction(
            op: 'room.close',
            label: '结束房间',
            enabled: gate.can('room.close'),
            hint: '关闭房间（连点两次确认）',
            onConfirmed: () => ctl.dangerAction('room.close'),
          ),
          KpDangerAction(
            op: 'room.end',
            label: '结团',
            enabled: gate.can('room.end'),
            hint: '结束整团（连点两次确认）',
            onConfirmed: () => ctl.dangerAction('room.end'),
          ),
          RoomTap(
            key: RoomLobbyKeys.modeSwitch,
            icon: combat ? Icons.explore_outlined : Icons.sports_kabaddi,
            label: combat ? '回到探索' : '切到战斗',
            hint: '当前模式：${mode.isEmpty ? '未知' : mode}',
            enabled: gate.can('scene.mode'),
            minSize: const Size(112, 40),
            onTap: () {
              // ★ P16 KP-4①：探索→战斗不再直发 scene.mode（只翻 meta.mode、
              //   不建 combat.order → 战斗列表 HP 恒 0），改走完整战斗准备
              //   弹层（combat.start 会带 hp/hpMax 建 order），与工具栏「转战斗」
              //   同口径。战斗→探索保持原样（另有「结束战斗」走 combat.end）。
              if (combat) {
                ctl.hostAction('scene.mode', <String, Object?>{
                  'mode': RoomMode.exploration,
                });
              } else {
                showCombatSheet<void>(context);
              }
            },
          ),
          RoomTap(
            key: RoomLobbyKeys.combatPrep,
            icon: Icons.groups_2_outlined,
            label: '战斗准备',
            hint: '打开战斗准备面板（选怪 / 先攻）',
            minSize: const Size(112, 40),
            onTap: () => showCombatSheet<void>(context),
          ),
          if (combat)
            RoomTap(
              key: RoomLobbyKeys.endCombat,
              icon: Icons.stop_circle_outlined,
              label: '结束战斗',
              hint: '退出战斗模式，回到探索',
              enabled: gate.can('combat.end'),
              minSize: const Size(104, 40),
              onTap: () => ctl.hostAction('combat.end'),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // R9 探索面板
  // ----------------------------------------------------------

  Widget _exploreBlock(
    BuildContext context,
    ThemeData theme, {
    required bool isKp,
    required Map<String, Object?> state,
  }) {
    final ctl = RoomScope.read(context).controller;
    final gate = ctl.gate;
    final scene = sceneOf(state);
    final sceneName = roomText(scene?['name']);
    final visible = isKp ? assetsOf(state) : publicAssets(state);
    return SectionBox(
      key: RoomLobbyKeys.explore,
      title: '探索面板',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  sceneName.isEmpty ? '（场景未命名）' : sceneName,
                  key: RoomLobbyKeys.sceneName,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isKp) ...<Widget>[
                RoomTap(
                  key: RoomLobbyKeys.sceneEdit,
                  icon: Icons.edit_note,
                  label: '改场景名',
                  hint: '给当前场景起个名字（公开）',
                  enabled: gate.can('scene.set'),
                  minSize: const Size(104, 36),
                  onTap: () => _editSceneName(context, ctl, scene),
                ),
                RoomTap(
                  key: RoomLobbyKeys.addAsset,
                  icon: Icons.add_photo_alternate_outlined,
                  label: '加素材',
                  hint: '添加一条素材（默认不公开）',
                  enabled: gate.can('asset.add'),
                  minSize: const Size(96, 36),
                  onTap: () => _addAsset(context, ctl),
                ),
              ],
            ],
          ),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('还没有素材', style: theme.textTheme.bodySmall),
            )
          else
            for (final a in visible) _assetRow(context, theme, a, isKp: isKp, gate: gate),
        ],
      ),
    );
  }

  Widget _assetRow(
    BuildContext context,
    ThemeData theme,
    Map<String, Object?> asset, {
    required bool isKp,
    required RoomGate gate,
  }) {
    final ctl = RoomScope.read(context).controller;
    final id = roomText(asset['id']);
    final revealed = jsTruthy(asset['revealed']);
    return Padding(
      key: RoomLobbyKeys.assetRow(id),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${roomText(asset['name'])}'
              '${revealed ? '' : '（未公开）'}',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isKp) ...<Widget>[
            RoomTap(
              key: RoomLobbyKeys.assetReveal(id),
              icon: revealed ? Icons.visibility_off_outlined : Icons.visibility,
              hint: revealed ? '遮挡这条素材' : '公开这条素材',
              enabled: gate.can(revealed ? 'asset.cover' : 'asset.reveal'),
              minSize: const Size(40, 32),
              onTap: () => ctl.hostAction(
                revealed ? 'asset.cover' : 'asset.reveal',
                <String, Object?>{'id': id, 'revealed': !revealed},
              ),
            ),
            RoomTap(
              key: RoomLobbyKeys.assetDel(id),
              icon: Icons.delete_outline,
              hint: '删除这条素材',
              enabled: gate.can('asset.del'),
              minSize: const Size(40, 32),
              onTap: () => ctl.hostAction('asset.del', <String, Object?>{'id': id}),
            ),
          ],
        ],
      ),
    );
  }

  void _editSceneName(
    BuildContext context,
    RoomController ctl,
    Map<String, Object?>? scene,
  ) {
    final draft = TextEditingController(text: roomText(scene?['name']));
    showRoomSheet<void>(
      context: context,
      title: '场景名',
      body: (BuildContext sheetCtx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: draft,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '场景名（公开可见）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: RoomTap(
              icon: Icons.save_outlined,
              label: '保存',
              hint: '把场景名写回房间',
              minSize: const Size(96, 40),
              onTap: () {
                // `scene.set` 是整体替换：把当前场景展开后只改 name。
                final next = <String, Object?>{...asMap(scene), 'name': draft.text.trim()};
                ctl.hostAction('scene.set', <String, Object?>{'scene': next});
                Navigator.of(sheetCtx).maybePop();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _addAsset(BuildContext context, RoomController ctl) {
    final draft = TextEditingController();
    showRoomSheet<void>(
      context: context,
      title: '添加素材',
      body: (BuildContext sheetCtx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: draft,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '素材名（例如：洋馆一层）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: RoomTap(
              icon: Icons.add,
              label: '添加',
              hint: '添加后默认不公开，可再点「公开」',
              minSize: const Size(88, 40),
              onTap: () {
                ctl.hostAction('asset.add', <String, Object?>{
                  'asset': <String, Object?>{
                    'kind': 'map',
                    'name': draft.text.trim().isEmpty ? '素材' : draft.text.trim(),
                  },
                });
                Navigator.of(sheetCtx).maybePop();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // R10 KP 工具（复用 T04 的弹层）
  // ----------------------------------------------------------

  Widget _kpToolsBlock(BuildContext context, ThemeData theme) {
    return SectionBox(
      key: RoomLobbyKeys.kpTools,
      title: 'KP 工具',
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          RoomTap(
            key: RoomLobbyKeys.openKpPanel,
            icon: Icons.tune,
            label: 'KP 工具',
            hint: '打开 KP 面板（待确认 / 战斗 / 场景 / 存档槽）',
            minSize: const Size(104, 40),
            onTap: () => showKpPanel<void>(context),
          ),
          RoomTap(
            icon: Icons.visibility_outlined,
            label: '观众名单',
            hint: '查看旁观者',
            minSize: const Size(104, 40),
            onTap: () {
              final rows = spectatorsOf(RoomScope.read(context).session.state);
              showRoomSheet<void>(
                context: context,
                title: '旁观者（${rows.length}）',
                body: (BuildContext _) => Text(
                  rows.isEmpty
                      ? '暂无旁观者'
                      : rows
                          .map((Map<String, Object?> m) => roomText(m['nickname']).isEmpty
                              ? roomText(m['seat'])
                              : roomText(m['nickname']))
                          .join('、'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // ★ P18 房规（d100 检定阈值）
  // ----------------------------------------------------------

  /// KP 侧：两个阈值输入 + 保存。
  ///
  /// 复用 `room.rules` op（POLICY `[kp]`，`room_types.dart`；骰子工具弹层
  /// `sheet_dice_tools.dart` 里已有同 op 的入口，两处写同一个 meta，不冲突）。
  /// domain 的 `ruleOptsOf` 只认 1–99 —— UI 侧显式拦住越界值并提示，
  /// 不发包，与「不许发非法载荷」的口径一致。
  Widget _ruleCfgBlock(
    BuildContext context,
    ThemeData theme, {
    required Map<String, Object?> state,
  }) {
    return _RuleCfgBlock(meta: asMap(state['meta']));
  }

  /// 非 KP 侧：只读展示当前房规（未设置 = 走规则层默认）。
  Widget _ruleView(
    BuildContext context,
    ThemeData theme, {
    required Map<String, Object?> state,
  }) {
    final meta = asMap(state['meta']);
    final c = jsParseInt(meta['critThreshold']);
    final f = jsParseInt(meta['fumbleThreshold']);
    final critText = (c != null && c >= 1 && c <= 99)
        ? '大成功：掷出 ≤ $c'
        : '大成功：默认（仅 01）';
    final fumbleText = (f != null && f >= 1 && f <= 99)
        ? '大失败：掷出 ≥ $f'
        : '大失败：默认（失败时 96–100，常规成功时仅 100）';
    return SectionBox(
      key: RoomLobbyKeys.ruleView,
      title: '房规（d100 检定阈值）',
      child: Text(
        '$critText；$fumbleText（由 KP 在房规里设置）',
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  // ----------------------------------------------------------

  Future<void> _copy(BuildContext context, String text, String notice) async {
    final scope = RoomScope.read(context);
    // ★ 先给反馈，再复制。
    //   原来写的是「await 剪贴板 → 再 showNotice」，而 `Clipboard.setData`
    //   在平台通道挂起时**不会抛异常、也不会返回** —— 于是「已复制」永远
    //   上不了屏，用户会反复点，以为是复制失败。
    //   提示不该依赖副作用完成。
    scope.local.showNotice(notice);
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      // 剪贴板不可用（部分桌面 / 无头环境 / 系统忙）：
      // 上面那句「已复制」就变成假话了，改成如实说。
      scope.local.showNotice('复制失败：剪贴板不可用，请手动选中地址复制');
    }
  }
}

/// ★ P18：房规编辑块（KP 专用，独立 StatefulWidget 管理 controller 生命周期
/// —— `RoomLobbyPage` 是 Stateless，直接在 build 里 new controller 会在
/// `local` 变化重建时丢掉用户输入）。
class _RuleCfgBlock extends StatefulWidget {
  const _RuleCfgBlock({required this.meta});

  final Map<String, Object?> meta;

  @override
  State<_RuleCfgBlock> createState() => _RuleCfgBlockState();
}

class _RuleCfgBlockState extends State<_RuleCfgBlock> {
  late final TextEditingController _crit;
  late final TextEditingController _fumble;

  /// 兜底默认：大成功 05（01-05 都算大成功）、大失败 96。
  @override
  void initState() {
    super.initState();
    _crit = TextEditingController(
      text: _thresholdText(widget.meta['critThreshold'], '5'),
    );
    _fumble = TextEditingController(
      text: _thresholdText(widget.meta['fumbleThreshold'], '96'),
    );
  }

  /// meta 阈值 → 输入框文本；未设置 / 非法 → 默认值文本。
  ///
  /// （不做 `didUpdateWidget` 权威回填：大厅是路由页，KP 在骰子工具里改完
  /// 阈值回到大厅时本组件已重建；在 State 存续期间抢着回填反而会覆盖
  /// 正在输入的半截数字。）
  String _thresholdText(Object? raw, String dflt) {
    final v = jsParseInt(raw);
    if (v == null || v < 1 || v > 99) return dflt;
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final gate = scope.controller.gate;
    final canSave = gate.can('room.rules');

    return SectionBox(
      title: '房规（d100 检定阈值）',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: RoomLobbyKeys.ruleCrit,
            controller: _crit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '大成功上限（1–99，默认 5 = 01–05）',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextField(
            key: RoomLobbyKeys.ruleFumble,
            controller: _fumble,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '大失败下限（1–99，默认 96）',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: RoomTap(
              key: RoomLobbyKeys.ruleSave,
              label: '保存阈值',
              enabled: canSave,
              hint: canSave
                  ? '写入房规（大成功 ≤ 上限；大失败 ≥ 下限到 100）'
                  : '只有 KP 能改房规',
              onTap: () => _save(context),
            ),
          ),
        ],
      ),
    );
  }

  void _save(BuildContext context) {
    final c = int.tryParse(_crit.text.trim());
    final f = int.tryParse(_fumble.text.trim());
    // UI 显式拦越界：domain 的 `ruleOptsOf` 会静默忽略非法值 —— 那样 KP
    // 以为设置成功了实际没生效，比报错更糟。
    if (c == null || c < 1 || c > 99 || f == null || f < 1 || f > 99) {
      RoomScope.read(context).local.showNotice('阈值必须为 1–99 的整数');
      return;
    }
    RoomScope.read(context).controller.hostAction(
      'room.rules',
      <String, Object?>{'critThreshold': c, 'fumbleThreshold': f},
    );
    RoomScope.read(context).local.showNotice('房规已保存');
  }
}

/// 大厅页里用到的座位集合（KP 不在花名册，故不含 `host`）。
List<String> lobbySeats(Map<String, Object?> state) => <String>[
      for (final m in asList(state['members'])) roomText(asMap(m)['seat']),
    ].where((String s) => s != kHostSeat).toList();
