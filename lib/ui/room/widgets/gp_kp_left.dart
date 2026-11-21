// ============================================================
// widgets/gp_kp_left.dart — 块 2：KP 左窄栏（设计 §5 T04 / S4.1）
//
// 两 tab（NPC·怪物 / 素材）由 `RoomUiLocal.leftTab`
// 持有：切 tab 不丢滚动位置，也不重建整页（P1-01）。
// ★ P13 MAP-1：删「地图」tab（与工具窄栏「清除标记」功能重复）。
// 加怪复用 `gp_kp_tools.dart` 的 [addLocalActor]：纯本地、不发包；
// P16 KP-7 起「加怪」先弹 `sheets/sheet_add_actor.dart` 的加怪弹层。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ============================================================

import 'dart:convert' show base64Decode;

import 'package:flutter/material.dart';

import '../room_scope.dart';
import '../room_ui_local.dart' show RoomUiLocal;
import '../sheets/sheet_add_actor.dart' show openAddActorSheet;
import '../view/scene_view.dart' show assetsOf;
import 'gp_kp_tools.dart' show addLocalActor, actorSummaryText;
import 'room_button_size.dart'
    show RoomBtnSize, RoomTapTile, clampBtnText;
import 'room_panel_kit.dart' show PanelTabs, RoomTap, SectionBox;
import '../room_text.dart';

/// 块 2 内部稳定 key。
class GpKpLeftKeys {
  const GpKpLeftKeys._();

  // ★ 与页面槽位 key（RoomKeys.gpKpLeft）区分开：容器 key 由页面统一挂，
  //   这里只做「这个块自己的根」——否则 find.byKey 会命中两个同名节点。
  static const Key root = ValueKey<String>('gpKpLeft/root');
  static const Key tabs = ValueKey<String>('gpKpLeft/tabs');
  static const Key actorName = ValueKey<String>('gpKpLeft/actorName');
  static const Key addActor = ValueKey<String>('gpKpLeft/addActor');
  static const Key upload = ValueKey<String>('gpKpLeft/upload');
  static const Key clear = ValueKey<String>('gpKpLeft/clear');

  // ★ P10 第 7 期 B：加怪数值表单 + 素材缩略图的稳定 key。
  // ★ P16 KP-7：内联表单改成加怪弹层，故 `actorName` / `actorDex` / `actorHp`
  //   / `actorActions` / `actorKind*` 这 6 个 key **不再有 UI 使用点**；
  //   常量保留给测试/兼容（删了会让既有测试编译失败）。
  static const Key actorDex = ValueKey<String>('gpKpLeft/actorDex');
  static const Key actorHp = ValueKey<String>('gpKpLeft/actorHp');
  static const Key actorActions = ValueKey<String>('gpKpLeft/actorActions');
  static const Key actorKind = ValueKey<String>('gpKpLeft/actorKind');
  static const Key actorKindMonster =
      ValueKey<String>('gpKpLeft/actorKind/monster');
  static const Key actorKindNpc =
      ValueKey<String>('gpKpLeft/actorKind/npc');

  /// 第 [id] 个素材的缩略图（供 widget test 断言 [Image.memory]）。
  static Key thumb(String id) => ValueKey<String>('gpKpLeft/thumb/$id');

  static Key removeActor(String id) =>
      ValueKey<String>('gpKpLeft/removeActor/$id');

  /// ★ P12 PL-1a：候选怪「是否显示给玩家」切换（候选阶段可改）。
  static Key toggleActorVisible(String id) =>
      ValueKey<String>('gpKpLeft/toggleActorVisible/$id');

  static Key reveal(String id) => ValueKey<String>('gpKpLeft/reveal/$id');

  /// ★ P16 KP-2：素材行的「封面」按钮已删除（P16 起不再有 UI 使用点），
  ///   key 工厂保留给测试/兼容 —— 删了会让既有测试编译失败。
  static Key cover(String id) => ValueKey<String>('gpKpLeft/cover/$id');
  static Key delete(String id) => ValueKey<String>('gpKpLeft/delete/$id');
}

/// KP 左窄栏。
class GpKpLeft extends StatefulWidget {
  const GpKpLeft({super.key});

  @override
  State<GpKpLeft> createState() => _GpKpLeftState();
}

class _GpKpLeftState extends State<GpKpLeft> {
  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final local = scope.local;
    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) {
        // ★ P16 KP-9：栏位侧给的是**有界高度**（页面把 gpKpLeft 槽位改成
        //   紧约束）。有界时让外框吃满：内容列塞进 `Expanded` + 单层滚动，
        //   卡片底色/描边一直铺到栏位底端，不再「内容多少决定面板高矮」。
        //   无界时（独立 pump 验收 / 旧档布局）退回原来的 min 尺寸列 ——
        //   否则「非零 flex + 无界约束」会直接抛 AssertionError。
        return LayoutBuilder(
          builder: (BuildContext lctx, BoxConstraints c) {
            final bool bounded = c.maxHeight.isFinite;
            final Widget content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PanelTabs(
                  key: GpKpLeftKeys.tabs,
                  // ★ P13 MAP-1：删「地图」tab，3→2，索引重映射
                  //   0=NPC·怪物 / 1=素材（旧值 2=素材 落到 1）。
                  tabs: const <String>['NPC·怪物', '素材'],
                  // P12：tab 名里的 emoji 换成图标（行内 14dp，颜色跟随选中态）。
                  icons: const <IconData?>[
                    Icons.pets,
                    Icons.image_outlined,
                  ],
                  index: local.leftTab,
                  onChanged: (int i) => local.setTab('left', i),
                  // ★ 2.34.0 / KP-3（I17）：NPC·怪物 / 素材两按钮等宽等高。
                  //   共用件 PanelTabs 只在显式 equalWidth=true 时按可用宽动态
                  //   均分；gp_combat_list.dart 的「顺序 / 怪物信息」不传该参数，
                  //   默认 false ⇒ 零影响（禁止全局改共用件）。
                  equalWidth: true,
                ),
                const SizedBox(height: 8),
                if (local.leftTab == 0) _npcTab(ctx, scope, local),
                if (local.leftTab == 1) _assetTab(ctx, scope),
              ],
            );
            return SectionBox(
              key: GpKpLeftKeys.root,
              title: 'NPC / 素材',
              child: bounded
                  ? Expanded(child: SingleChildScrollView(child: content))
                  : content,
            );
          },
        );
      },
    );
  }

  /// NPC tab：本地候选池（不进事件流，随开战送出）。
  Widget _npcTab(
    BuildContext context,
    RoomScope scope,
    RoomUiLocal local,
  ) {
    final ctl = scope.controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ★ P16 KP-7：内联数值表单撤掉，改成「加怪」先弹
        //   `sheets/sheet_add_actor.dart` 的加怪弹层（六个字段：名称 / 类型 /
        //   DEX / HP / 每轮次数 / 护甲），确定后用返回值进本地候选池。
        //   弹层取消 / 点外部 / 返回键 → null，本地态零变化。
        // ★ P16：「加怪」与工具窄栏同档（90×48），两栏之间不再一个大一个小。
        Align(
          alignment: Alignment.centerLeft,
          child: RoomTapTile(
            roomKey: GpKpLeftKeys.addActor,
            size: RoomBtnSize.toolsTile,
            label: '加怪',
            icon: Icons.add,
            // ★ T-30：可点性恰好恒等闸门，不叠加任何表单前置条件。
            enabled: ctl.gate.can('combat.start'),
            hint: '弹窗填写数值，加入本地候选（不发包）',
            onTap: () async {
              final Map<String, Object?>? m = await openAddActorSheet(context);
              if (m == null || !context.mounted) return;
              addLocalActor(
                local,
                name: roomText(m['name']),
                kind: roomText(m['kind']),
                dex: (m['dex'] as num?) ?? 50,
                hp: (m['hp'] as num?) ?? 10,
                actionsPerRound: (m['actionsPerRound'] as int?) ?? 1,
                armor: (m['armor'] as int?) ?? 0,
                // ★ P12 PL-1a：加怪弹层第 7 字段，默认不勾（防泄露）。
                visibleToPlayers: m['visibleToPlayers'] == true,
              );
            },
          ),
        ),
        Text('候选 ${local.pendingActors.length} 个',
            key: const ValueKey<String>('gpKpLeft/actorCount'),
            style: const TextStyle(fontSize: 11)),
        for (var i = 0; i < local.pendingActors.length; i++)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  actorSummaryText(local.pendingActors[i]),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              // ★ P12 PL-1a：候选阶段可切「是否显示给玩家」，写回本机
              //   `pendingActors[i]['visibleToPlayers']`（不进事件流、不发包，
              //   随 combat.start 才送）。默认不显示（防泄露）。
              clampBtnText(
                RoomTap(
                  key: GpKpLeftKeys.toggleActorVisible(
                      roomText(local.pendingActors[i]['id'])),
                  label: local.pendingActors[i]['visibleToPlayers'] == true
                      ? '已显示'
                      : '不显示',
                  enabled: ctl.gate.can('combat.start'),
                  hint: '切换是否显示给玩家（只影响玩家裁剪态 actors）',
                  onTap: () {
                    final rec = local.pendingActors[i];
                    rec['visibleToPlayers'] =
                        !(rec['visibleToPlayers'] == true);
                    local.setTool(local.toolMode);
                  },
                ),
              ),
              RoomTap(
                key: GpKpLeftKeys.removeActor(
                    roomText(local.pendingActors[i]['id'])),
                label: '移除',
                enabled: ctl.gate.can('combat.start'),
                hint: '从本地候选池移除',
                onTap: () {
                  local.pendingActors.removeAt(i);
                  local.setTool(local.toolMode);
                },
              ),
            ],
          ),
      ],
    );
  }

  /// 素材缩略图：`data` 是 dataURL，取逗号后的 base64 → [Image.memory]。
  ///
  /// 与 `gp_map_stage.dart#_coverImage` 同一口径：坏数据 / 空数据一律
  /// try/catch + errorBuilder 静默降级成占位图标，绝不因为一张图炸掉整栏。
  /// 公开 / 未公开用一圈极细边框区分（foregroundDecoration 不参与布局）。
  Widget _assetThumb(Map<String, Object?> a) {
    final raw = roomText(a['data']);
    final revealed = roomText(a['revealed']) == 'true';
    Widget picture;
    if (raw.isEmpty) {
      picture = _thumbPlaceholder();
    } else {
      try {
        final int comma = raw.indexOf(',');
        final String b64 = comma >= 0 ? raw.substring(comma + 1) : raw;
        final bytes = base64Decode(b64);
        picture = Image.memory(
          bytes,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (BuildContext _, Object? _, StackTrace? _) =>
              _thumbPlaceholder(),
        );
      } catch (_) {
        picture = _thumbPlaceholder();
      }
    }
    return Container(
      key: GpKpLeftKeys.thumb(roomText(a['id'])),
      width: 40,
      height: 40,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: revealed ? Colors.amber : Colors.white24,
          width: revealed ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(width: 40, height: 40, child: picture),
      ),
    );
  }

  /// 缩略图坏数据占位（不是 Image，测试据此断言降级）。
  Widget _thumbPlaceholder() => const ColoredBox(
        color: Color(0x33222222),
        child: Center(
          child: Icon(Icons.image_outlined, size: 20, color: Colors.white54),
        ),
      );

  /// 素材 tab：公开 / 隐藏 / 封面 / 删除 / 上传。
  Widget _assetTab(BuildContext context, RoomScope scope) {
    final ctl = scope.controller;
    final state = scope.session.state;
    final read = scope.session.hostRead;
    final localAssets = read == null
        ? const <Map<String, Object?>>[]
        : read.localAssets;
    final public = assetsOf(state);
    // ★ P10 第 7 期修复（用户原话「公开后素材栏多了一个」）：已公开的素材**同时**
    //   存在于 `scene.assets`（广播副本）与 `host.localAssets`（私有原件 ——
    //   domain 的 revealAsset 只把 `revealed` 置 true，并不从私有库删除）。
    //   原实现直接 `[...public, ...localAssets]` 拼接，同一 id 会渲染两行。
    //   这里按 id 合并：优先取私有原件（它的 revealed 标记是最新的），
    //   广播副本只补「私有库里没有的」（例如别的设备公开的素材）。
    final merged = <String, Map<String, Object?>>{};
    for (final a in localAssets) {
      merged[roomText(a['id'])] = a;
    }
    for (final a in public) {
      merged.putIfAbsent(roomText(a['id']), () => a);
    }
    final rows = merged.values.toList(growable: false);
    final pubCount = rows.where((a) => roomText(a['revealed']) == 'true').length;
    final privCount = rows.length - pubCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ★ P16：本栏唯一的长按钮 → 拉满整行、高 48。
        //   去掉外层 `Align(centerLeft)`：`Align` 无 widthFactor 时会让
        //   `RoomTap` 收缩居中，永远满不了宽。
        RoomTapTile(
          roomKey: GpKpLeftKeys.upload,
          size: RoomBtnSize.fullRow48,
          fullWidth: true,
          label: '上传素材',
          icon: Icons.upload_file,
          enabled: ctl.gate.can('asset.add'),
          hint: '选择图片（≤2MB）',
          onTap: () async {
            final url = await ctl.pickImage();
            if (url == null) return;
            await ctl.hostAction(
              'asset.add',
              <String, Object?>{
                'asset': <String, Object?>{
                  'kind': 'map',
                  'name': '素材',
                  'data': url,
                },
              },
            );
          },
        ),
        Text('公开 $pubCount · 未公开 $privCount',
            key: const ValueKey<String>('gpKpLeft/assetCount'),
            style: const TextStyle(fontSize: 11)),
        for (final a in rows)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ★ P10 第 7 期 B：素材行左侧补缩略图（40×40），保持
                //   第 7 期 A 批「名字一行 + 按钮 Wrap 一行」防裁切结构：
                //   缩略图只占名字行，不碰下面三个 48×48 按钮。
                Row(
                  children: <Widget>[
                    _assetThumb(a),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        roomText(a['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                // ★ P10 第 7 期（用户截图：『素材 隐藏 封面 删除』右半边被裁）：
                //   左窄栏 17%（1280dp ≈ 213dp）放不下「名字 + 3 个 48dp 按钮」
                //   一行。改成名字单独一行、按钮用 Wrap 自动换行，按钮都保留
                //   48×48 热区且完整落在格内，不再被 ClipRect 裁一半。
                // ★ P16：按钮仍保持 48×48（`p10_t7:427-430` /
                //   `p10_t7_b:394-397` 钉死「热区 ≥47.5」）；本栏**不**跟着
                //   工具按钮升到 90×48 —— 它们是「素材行尾」的图标动作。
                // ★ P16 KP-2：「封面」按钮已删除（只留 公开/隐藏 + 删除）。
                Wrap(
                  spacing: 2,
                  children: <Widget>[
                    RoomTapTile(
                      roomKey: GpKpLeftKeys.reveal(roomText(a['id'])),
                      size: RoomBtnSize.assetTile,
                      label:
                          roomText(a['revealed']) == 'true' ? '隐藏' : '公开',
                      enabled: ctl.gate.can('asset.reveal'),
                      // ★ P16 KP-2：公开是**互斥**的（domain 侧公开一张会自动
                      //   隐藏其余），所以文案要说清，别让 KP 以为能多张并存。
                      hint: roomText(a['revealed']) == 'true'
                          ? '从舞台隐藏'
                          : '公开到素材舞台（同时只能公开一张，其他会自动隐藏）',
                      onTap: () => ctl.hostAction(
                        'asset.reveal',
                        <String, Object?>{
                          'id': a['id'],
                          'revealed': roomText(a['revealed']) != 'true',
                        },
                      ),
                    ),
                    RoomTapTile(
                      roomKey: GpKpLeftKeys.delete(roomText(a['id'])),
                      size: RoomBtnSize.assetTile,
                      label: '删除',
                      enabled: ctl.gate.can('asset.del'),
                      hint: '删除素材',
                      onTap: () => ctl.hostAction(
                        'asset.del',
                        <String, Object?>{'id': a['id']},
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
