// ============================================================
// sheets/sheet_combat.dart — 战斗准备 / 结算伤害 / 加怪（设计 §5 T04 / S4.5）
//
// 三组：
//   · 准备：`combat.start {actorIds, actors, pcSeats}`，actors =
//     勾选的本地候选怪（`RoomUiLocal.pendingActors`，不进事件流）
//     **拼接显式构造的 PC 记录**；
//   · 结算：`combat.damage {slotId, damage, summary}`，槽位取
//     `combatRows(state, isKp:true)`（hpPublic 已在数据层收敛）；
//   · 加怪：`combat.actor {actor}` 与 `combat.pool.set {actors}`。
//
// ★ P10 第 7 期 C 批 B：对齐老 APP `combatPrepareSheet`（room-panels.js
//   :4080-4177）—— 玩家默认全选（反选集合）、怪物默认全不选（正选集合）、
//   「至少 1 个怪物」门禁走 hint + 点后一次性提示，不塞进 `enabled`（T-30）。
//
// ★ 载荷里为什么必须显式带 PC：domain `combatStart` 的
//   `pool = asList(p['actors'])` 只从传入的 actors 取池子，`kind=='pc'`
//   仅在 actorIds 过滤时「保留」已有 PC、并不会凭空创建；若 actors 只含
//   怪物，开战后 order 里就没有玩家槽。老 APP :4064-4073 / :4136-4152
//   的真实载荷是 `pcActors(ctx).concat(monsterActors)`，本层照此装配。
//   DEX / HP 复用 `member_view` 的既有纯函数（取不到给 0，不编默认值），
//   撕卡 PC 由 domain 自己过滤，UI 不判。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap, jsStr;
import '../../../domain/room_types.dart' show RoomIntent;
import '../room_keys.dart';
import '../room_scope.dart';
import '../room_text.dart' show roomText;
import '../view/combat_view.dart' show combatRows, visibleCombatActors;
import '../view/member_view.dart' show memberDex, memberStats;
import '../view/room_view.dart' show playersOf;
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import 'room_sheet.dart' show showRoomSheet;
import 'sheet_add_actor.dart' show openAddActorSheet;

/// 战斗弹层内部稳定 key。
class CombatSheetKeys {
  const CombatSheetKeys._();

  static const Key root = ValueKey<String>('combatSheet');
  static const Key prepare = ValueKey<String>('combatSheet/prepare');
  static const Key damage = ValueKey<String>('combatSheet/damage');
  static const Key damageInput = ValueKey<String>('combatSheet/damageInput');
  static const Key actorName = ValueKey<String>('combatSheet/actorName');
  static const Key addActor = ValueKey<String>('combatSheet/addActor');
  static const Key pool = ValueKey<String>('combatSheet/pool');

  // ---- 主理人追加：加单位数值表单的 6 个稳定 key ----
  // 值与窄栏的 `GpKpToolsKeys` 刻意分开（带 combatSheet/ 前缀）：弹层与
  // 整页窄栏可能同树，独立 key 才不会让 findsOneWidget 退化成 findsWidgets。
  // ★ P16 KP-8：内联表单改成「先弹 `sheets/sheet_add_actor.dart` 加单位弹层」，
  //   下面这批 key **不再有 UI 使用点**，常量保留给测试/兼容。
  static const Key actorDex = ValueKey<String>('combatSheet/actorDex');
  static const Key actorHp = ValueKey<String>('combatSheet/actorHp');
  static const Key actorActions = ValueKey<String>('combatSheet/actorActions');
  static const Key actorKind = ValueKey<String>('combatSheet/actorKind');
  static const Key actorKindMonster =
      ValueKey<String>('combatSheet/actorKind/monster');
  static const Key actorKindNpc =
      ValueKey<String>('combatSheet/actorKind/npc');

  // ---- P10 第 7 期 C 批 B：勾选列表与部署控件 ----

  /// 玩家勾选行（`combatSheet/pcToggle/<seat>`）。
  static Key pcToggle(String seat) =>
      ValueKey<String>('combatSheet/pcToggle/$seat');

  /// 怪物 / NPC 勾选行（`combatSheet/monsterToggle/<id>`）。
  static Key monsterToggle(String id) =>
      ValueKey<String>('combatSheet/monsterToggle/$id');

  /// 部署计数文案。
  static const Key deployCount = ValueKey<String>('combatSheet/deployCount');

  /// 主按钮外层锚点（按钮自身仍挂 `RoomKeys.action('combat.start')`）。
  static const Key deploy = ValueKey<String>('combatSheet/deploy');

  static Key slot(String id) => ValueKey<String>('combatSheet/slot/$id');

  // ---- ★ P13 COMBAT-3：玩家「攻击对抗」弹窗①（独立 key，不挂 act 锚点）----

  /// 肉搏斗殴选项（合成武器，固定第一个）。
  static const Key attackBarehand =
      ValueKey<String>('combatSheet/attack/barehand');

  /// 玩家角色卡里的某把武器选项（`combatSheet/attack/weapon/<i>`）。
  static Key attackWeapon(int i) =>
      ValueKey<String>('combatSheet/attack/weapon/$i');

  /// 防守方怪物选项（`combatSheet/attack/defender/<id>`）。
  static Key attackDefender(String id) =>
      ValueKey<String>('combatSheet/attack/defender/$id');

  /// 提交攻击申请按钮。
  static const Key attackSubmit =
      ValueKey<String>('combatSheet/attack/submit');

  /// 空态：没有可选怪物 / 没有自己成员。
  static const Key attackEmpty = ValueKey<String>('combatSheet/attack/empty');
}

/// 战斗弹层。
class CombatSheet extends StatefulWidget {
  const CombatSheet({super.key});

  @override
  State<CombatSheet> createState() => _CombatSheetState();
}

class _CombatSheetState extends State<CombatSheet> {
  final TextEditingController _damage = TextEditingController(text: '1');
  String _slotId = '';

  /// 反选集合：key 不存在 = 选中（玩家默认全选，老 APP :4095-4111）。
  final Set<String> _pcOff = <String>{};

  /// 正选集合：初始为空 = 怪物 / NPC 默认全不选（老 APP :4112-4130）。
  final Set<String> _monsterOn = <String>{};

  /// 勾选是否已按「当前参战单位」回填过一次（P14 P3）。
  /// 只做一次：之后用户的手动勾选/取消不能被 build 覆盖回去。
  bool _seeded = false;

  @override
  void dispose() {
    _damage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;
    final state = scope.session.state;
    final rows = combatRows(state, isKp: true);
    final local = scope.local;
    final players = playersOf(state);
    final monsters = local.pendingActors;

    // ★ P14 P3：重开弹层时**按当前参战单位回填勾选**。
    //   为什么必须回填：`_pcOff` / `_monsterOn` 是两个 Set 状态，State 每次
    //   重开都新建 ⇒ 默认值永远是「玩家全勾 / 怪物全不勾」。于是战斗打到一半
    //   再点「战斗准备」，读数显示「怪物 0 · 玩家 1」，而权威端 combat.order
    //   里其实还是 2 个单位（用户报的「勾选被重置」）。
    //   回填口径：有进行中的战斗（order 非空）时，**在参战的勾上、不在的取消**
    //   —— 玩家侧用反选集合（`_pcOff` 存「未参战」）、怪物侧用正选集合
    //   （`_monsterOn` 存「参战」），与既有 toggle 的语义保持一致；
    //   order 为空（还没开打）时保持老口径「玩家全勾 / 怪物全不勾」，
    //   既有的默认值用例零漂移。
    if (!_seeded) {
      _seeded = true;
      final List<Object?> order = asList(asMap(state['combat'])['order']);
      if (order.isNotEmpty) {
        final Set<String> inCombatSeats = <String>{};
        final Set<String> inCombatIds = <String>{};
        for (final Object? raw in order) {
          final Map<String, Object?> slot = asMap(raw);
          final String seat = roomText(slot['seat']);
          if (seat.isNotEmpty) inCombatSeats.add(seat);
          // 多行动槽的 id 是 `base#n`，actorId 才是基准 id（与候选池同键）。
          final String actorId = roomText(slot['actorId']);
          final String id = actorId.isNotEmpty ? actorId : roomText(slot['id']);
          if (id.isNotEmpty) inCombatIds.add(id);
        }
        for (final Map<String, Object?> m in players) {
          final String seat = roomText(m['seat']);
          if (seat.isNotEmpty && !inCombatSeats.contains(seat)) _pcOff.add(seat);
        }
        for (final Object? a in monsters) {
          final String id = roomText(asMap(a)['id']);
          if (id.isNotEmpty && inCombatIds.contains(id)) _monsterOn.add(id);
        }
      }
    }

    // 勾选结果：玩家取反选集合的补集，怪物取正选集合。
    final List<String> selectedPcSeats = <String>[
      for (final m in players)
        if (!_pcOff.contains(roomText(m['seat']))) roomText(m['seat']),
    ];
    final List<String> selectedMonsterIds = <String>[
      for (final a in monsters)
        if (_monsterOn.contains(roomText(asMap(a)['id'])))
          roomText(asMap(a)['id']),
    ];

    // ★ actors = 勾选的怪物候选 + 显式构造的 PC 记录（domain 不会自动带 PC）。
    final List<Map<String, Object?>> actors = <Map<String, Object?>>[
      for (final a in monsters)
        if (_monsterOn.contains(roomText(asMap(a)['id']))) asMap(a),
      for (final m in players)
        if (!_pcOff.contains(roomText(m['seat']))) _pcActor(m),
    ];

    final String countText =
        '（怪物 ${selectedMonsterIds.length} · 玩家 ${selectedPcSeats.length}）';

    return Column(
      key: CombatSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          key: CombatSheetKeys.prepare,
          title: '战斗准备（参战单位）',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '勾选要进入战斗的玩家与怪物/NPC（玩家默认全选）。'
                '系统按 CoC 7th 规则自动排行动顺序。',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 6),
              Text(
                '本地候选 ${monsters.length} · 玩家 ${players.length} · '
                '当前顺序 ${rows.length}',
                key: CombatSheetKeys.pool,
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 8),

              // ---- ① 玩家（勾选进入战斗），默认全选 ----
              const Text('玩家（勾选进入战斗）',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (players.isEmpty)
                const Text('花名册里还没有玩家', style: TextStyle(fontSize: 11)),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  for (final m in players)
                    RoomTap(
                      key: CombatSheetKeys.pcToggle(roomText(m['seat'])),
                      icon: _pcOff.contains(roomText(m['seat']))
                          ? Icons.check_box_outline_blank
                          : Icons.check_box,
                      label: _pcLabel(m),
                      hint: _pcOff.contains(roomText(m['seat']))
                          ? '点按选入战斗'
                          : '点按取消参战',
                      onTap: () => _togglePc(roomText(m['seat'])),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // ---- ② 怪物 / NPC（勾选进入战斗），默认全不选 ----
              const Text('怪物 / NPC（勾选进入战斗）',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (monsters.isEmpty)
                const Text('候选池是空的。点左栏「NPC·怪物」先添加。',
                    style: TextStyle(fontSize: 11)),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  for (final a in monsters)
                    RoomTap(
                      key: CombatSheetKeys.monsterToggle(
                          roomText(asMap(a)['id'])),
                      icon: _monsterOn.contains(roomText(asMap(a)['id']))
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      label: _monsterLabel(a),
                      hint: _monsterOn.contains(roomText(asMap(a)['id']))
                          ? '点按取消参战'
                          : '点按选入战斗',
                      onTap: () =>
                          _toggleMonster(roomText(asMap(a)['id'])),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // ---- ③ 部署（门禁不进 enabled） ----
              Text(countText,
                  key: CombatSheetKeys.deployCount,
                  style: const TextStyle(fontSize: 11)),
              KeyedSubtree(
                key: CombatSheetKeys.deploy,
                child: RoomTap(
                  key: RoomKeys.action('combat.start'),
                  label: '⚔️ 战斗部署完毕$countText',
                  icon: Icons.play_arrow,
                  // ★ T-30：恰好等于闸门，不许叠加「至少 1 怪」等业务前置。
                  enabled: gate.can('combat.start'),
                  // ★ 主理人裁决：空候选池走历史「纯 PC 开战」路径时，hint
                  //   必须明说「将以纯玩家战斗开始」，避免用户点了没反应或
                  //   莫名跳进战斗；候选池非空未勾时仍提示「至少 1 怪」门禁。
                  //   三个分支与下方 onTap 的门禁条件完全自洽，且 hint 绝不
                  //   参与 enabled 计算（T-30）。
                  hint: gate.can('combat.start')
                      ? (monsters.isEmpty
                          ? '当前无怪物候选，将以纯玩家战斗开始'
                          : (selectedMonsterIds.isEmpty
                              ? '至少选择 1 个怪物/NPC'
                              : '按勾选的参战单位开战'))
                      : '只有 KP 能开战',
                  onTap: () {
                    // K7：可点但前置不满足时必须给一次性提示，不能静默 return，
                    // 也不能把门禁塞进 enabled（与 `combat.damage` 同口径）。
                    // ★ 主理人裁决（已定稿）：候选池**完全为空**是历史路径，
                    //   此时根本没有「可勾的怪」，仍允许部署一场纯 PC 战斗
                    //   （`room_ui_permission_test.dart` 的 T-30 权限探针靠这条
                    //   路径造参战槽位；纯 PC 开战是本工程既有能力，砍掉属
                    //   未经授权的功能回退）。hint 已明说「将以纯玩家战斗开始」。
                    //   只要候选池非空，就必须至少勾 1 只怪（老 APP :4136-4137）。
                    if (monsters.isNotEmpty && selectedMonsterIds.isEmpty) {
                      RoomScope.read(context)
                          .local
                          .showNotice('至少选择 1 个怪物/NPC');
                      return;
                    }
                    ctl.hostAction(
                      'combat.start',
                      <String, Object?>{
                        'actorIds': <Object?>[...selectedMonsterIds],
                        'actors': <Object?>[...actors],
                        'pcSeats': <Object?>[...selectedPcSeats],
                      },
                    );
                  },
                ),
              ),
              RoomTap(
                key: RoomKeys.action('combat.end'),
                label: '结束战斗',
                enabled: gate.can('combat.end'),
                hint: '回到探索模式',
                onTap: () => ctl.hostAction('combat.end'),
              ),
            ],
          ),
        ),
        SectionBox(
          key: CombatSheetKeys.damage,
          title: '结算伤害',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  for (final r in rows)
                    RoomTap(
                      key: CombatSheetKeys.slot(r.id),
                      label: r.name,
                      enabled: gate.can('combat.damage'),
                      hint: '选中该槽位',
                      onTap: () => setState(() => _slotId = r.id),
                    ),
                  if (rows.isEmpty)
                    const Text('尚无参战槽位',
                        style: TextStyle(fontSize: 11)),
                ],
              ),
              Text('已选：${_slotId.isEmpty ? '未选' : _slotId}',
                  style: const TextStyle(fontSize: 11)),
              TextField(
                key: CombatSheetKeys.damageInput,
                controller: _damage,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '伤害值',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              RoomTap(
                key: RoomKeys.action('combat.damage'),
                label: '结算',
                // ★ T-30：挂了 `act/<op>` 锚点的按钮，可点性必须**恰好**等于
                //   `gate.can(op)`（与槽位按钮同一口径）。
                enabled: gate.can('combat.damage'),
                hint: _slotId.isEmpty ? '请先选择槽位' : '结算伤害',
                onTap: () {
                  // 业务前置留在动作里（与 `room.start` 同一口径），不进 enabled。
                  // 不能静默 return：可点却毫无反应比「灰着」更让人困惑，
                  // 所以未选槽位时给一条一次性提示（K7，不弹模态）。
                  if (_slotId.isEmpty) {
                    RoomScope.read(context).local.showNotice('请先选择槽位');
                    return;
                  }
                  ctl.hostAction(
                    'combat.damage',
                    <String, Object?>{
                      'slotId': _slotId,
                      'damage': int.tryParse(_damage.text.trim()) ?? 0,
                      'summary': '',
                    },
                  );
                },
              ),
            ],
          ),
        ),
        SectionBox(
          title: '加单位',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ★ P16 KP-8：内联数值表单撤掉，改成先弹
              //   `sheets/sheet_add_actor.dart` 的加单位弹层（六个字段：
              //   名称 / 类型 / DEX / HP / 每轮次数 / 护甲）。取消 → null，
              //   什么都不发。
              const Text(
                '点按钮后弹窗填写数值（含护甲），确定才发包。',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  KeyedSubtree(
                    key: CombatSheetKeys.addActor,
                    child: RoomTap(
                      key: RoomKeys.action('combat.actor'),
                      label: '加入战斗',
                      enabled: gate.can('combat.actor'),
                      hint: '弹窗填写数值后直接加入当前战斗',
                      onTap: () async {
                        final Map<String, Object?>? m =
                            await openAddActorSheet(context);
                        if (m == null || !mounted) return;
                        await ctl.hostAction(
                          'combat.actor',
                          <String, Object?>{
                            'actor': _actorPayload(m),
                          },
                        );
                      },
                    ),
                  ),
                  RoomTap(
                    key: RoomKeys.action('combat.pool.set'),
                    label: '写入候选池',
                    enabled: gate.can('combat.pool.set'),
                    hint: '弹窗填写数值后并入开战前候选池（整体替换）',
                    onTap: () async {
                      final Map<String, Object?>? m =
                          await openAddActorSheet(context);
                      if (m == null || !mounted) return;
                      await ctl.hostAction(
                        'combat.pool.set',
                        <String, Object?>{
                          'actors': <Object?>[
                            ...local.pendingActors,
                            _actorPayload(m),
                          ],
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 切换一个玩家的参战状态（反选集合取补 = 默认全选）。
  void _togglePc(String seat) {
    setState(() {
      if (!_pcOff.remove(seat)) _pcOff.add(seat);
    });
  }

  /// 切换一个怪物 / NPC 的参战状态（正选集合 = 默认全不选）。
  void _toggleMonster(String id) {
    setState(() {
      if (!_monsterOn.remove(id)) _monsterOn.add(id);
    });
  }

  /// 玩家行文案：昵称 + seat（缺昵称时只给 seat）。
  String _pcLabel(Map<String, Object?> m) {
    final String nick = roomText(m['nickname']);
    final String seat = roomText(m['seat']);
    if (nick.isEmpty) return seat;
    return '$nick（$seat）';
  }

  /// 怪物行文案：名字 · 类型 · DEX n · HP n · 每轮 k 次（k>1 才带次数）。
  String _monsterLabel(Map<String, Object?> a) {
    final m = asMap(a);
    final String rawName = roomText(m['name']);
    final String name = rawName.isEmpty ? roomText(m['id']) : rawName;
    final String kind = roomText(m['kind']) == 'npc' ? 'NPC' : '怪物';
    final String dex = _numText(m['dex']);
    final String hp = _numText(m['hp']);
    final Object? apr = m['actionsPerRound'];
    final String times = (apr is num && apr > 1)
        ? ' · 每轮 ${apr.toInt()} 次'
        : '';
    return '$name · $kind · DEX $dex · HP $hp$times';
  }

  /// 缺键 / 非数字一律给 0（不编默认值），数字去掉无意义的小数尾巴。
  static String _numText(Object? v) {
    if (v is! num) return '0';
    return v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
  }

  /// 把一个玩家成员映射成 PC 记录（老 APP `pcActors` :4064-4073）。
  ///
  /// DEX 走 `memberDex`（只认 `sheet.attrs.dex`），HP / HP 上限走
  /// `memberStats`（status → runtime → sheet 顶层逐项回退，取不到给 0）；
  /// 撕卡 PC 由 domain :198-214 自动过滤，这里不判。
  Map<String, Object?> _pcActor(Map<String, Object?> m) {
    final String seat = roomText(m['seat']);
    final String nick = roomText(m['nickname']);
    final String charName = roomText(asMap(m['sheet'])['name']);
    final String name = charName.isNotEmpty
        ? charName
        : (nick.isNotEmpty ? nick : (seat.isNotEmpty ? seat : '玩家'));
    final stats = memberStats(m);
    return <String, Object?>{
      'id': 'p-$seat',
      'name': name,
      'kind': 'pc',
      'seat': seat,
      'dex': memberDex(m),
      'actionsPerRound': 1,
      'hp': stats.hp,
      'hpMax': stats.hpMax,
    };
  }

  /// 一个战斗单位记录（字段与 `setActorPool` 白名单一致）。
  ///
  /// ★ 逐字段对齐 `addLocalActor` / 加单位弹层的口径 ——
  ///   name 空则「单位」、kind 只认 monster/npc、hp 同值写 hpMax、
  ///   actionsPerRound 静默夹 1–10、**armor 负值夹 0**（P16 KP-8）。
  ///   弹层已把非法数字回落成默认值，这里再兜一遍，保证发包载荷永远合法。
  Map<String, Object?> _actorPayload(Map<String, Object?> m) {
    final String rawName = roomText(m['name']).trim();
    final int rawAp = _intOf(m['actionsPerRound'], 1);
    final int ap = rawAp < 1 ? 1 : (rawAp > 10 ? 10 : rawAp);
    final int hp = _intOf(m['hp'], 10);
    final int armor = _intOf(m['armor'], 0);
    return <String, Object?>{
      'id': 'u${rawName.hashCode.abs()}',
      'name': rawName.isEmpty ? '单位' : rawName,
      'kind': roomText(m['kind']) == 'npc' ? 'npc' : 'monster',
      'dex': _intOf(m['dex'], 50),
      'hp': hp,
      'hpMax': hp,
      'actionsPerRound': ap,
      'armor': armor < 0 ? 0 : armor,
    };
  }

  /// 取整数键：缺键 / 非数字回落 [fallback]（不编别的默认值）。
  static int _intOf(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(roomText(v).trim()) ?? fallback;
  }
}

/// 打开战斗弹层（老 APP `combatPrepareSheet` 标题口径）。
Future<T?> showCombatSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: '战斗模式 · 选择参战单位',
    body: (BuildContext _) => const CombatSheet(),
  );
}

// ============================================================
// ★ P13 COMBAT-3：玩家「攻击对抗」弹窗①
//
// 流程：选己方武器（含「肉搏斗殴」合成项 → 斗殴技能 / 1D3+DB）
//     → 选防守方参战怪物（只名字，可见性已被数据层裁剪）
//     → 发 `RoomIntent.act {op:'check.opposed', auto:true, attack:true, ...}`。
//
// `check.opposed` 的 POLICY = `[kp,player] + RoomConfirm.kp`，玩家发起入
// `pending`；KP 同意后先由 KP 选防守方式（反击 / 闪避 / 不防御），counter/dodge
// 再复用 P12 的 `showMonsterValueSheet` 补 1–100 检定值；`confirmPending` 把
// `reaction` / `value` 合并进 `defender` 袋，再由 domain 上层编排分流到既有
// `opposedAttackResolve`（严格 COC7th 结算 + `opposedDamageMonster` 扣怪血 +
// PUBLIC 广播）。契约 62/28/13 零改动。
//
// ★ P13：防守方式不再由玩家在本弹窗①预置，改由 KP 同意后在
//   `room_request_watcher.dart` 的确认链路里选择（本批已放开该文件白名单）。
//   本弹窗只提交武器 / 目标 / attacker / weapon / defender.side 等其余载荷。
// ============================================================

/// 打开玩家攻击对抗弹窗①。
Future<T?> showPlayerAttackSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: '攻击对抗 · 选择武器与目标',
    body: (BuildContext _) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: const PlayerAttackSheet(),
    ),
  );
}

/// 玩家攻击对抗弹窗主体。
class PlayerAttackSheet extends StatefulWidget {
  const PlayerAttackSheet({super.key});

  @override
  State<PlayerAttackSheet> createState() => _PlayerAttackSheetState();
}

class _PlayerAttackSheetState extends State<PlayerAttackSheet> {
  /// 选中的武器索引：0 = 肉搏斗殴合成项，1..n = 角色卡 weapons。
  int _weaponIndex = 0;

  /// 选中的防守怪物 actorId（裸 id，去 #n 后缀）。
  String? _defenderId;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final state = scope.session.state;
    final seat = scope.session.seat;
    final theme = Theme.of(context);

    // 甲方固定本人：只从自己成员读卡。
    final Map<String, Object?> me = <String, Object?>{
      for (final m in playersOf(state))
        if (roomText(asMap(m)['seat']) == seat) ...asMap(m),
    };
    final mySheet = asMap(me['sheet']);
    final String db = roomText(mySheet['db']).trim().isEmpty
        ? '0'
        : roomText(mySheet['db']).trim();

    // 武器清单：肉搏斗殴合成项 + 角色卡 weapons（逐条原样）。
    final List<Map<String, Object?>> weapons = <Map<String, Object?>>[
      <String, Object?>{
        'name': '肉搏斗殴',
        'skill': '斗殴',
        'damage': '1D3',
        'db': db,
        'ranged': false,
        'perRound': '',
        'pierce': '',
        'barehand': true,
      },
      for (final w in asList(mySheet['weapons'])) asMap(w),
    ];
    final Map<String, Object?> chosen =
        _weaponIndex < weapons.length ? weapons[_weaponIndex] : weapons.first;

    // 防守方：玩家可见怪物（数据层已裁剪为 id + name，只渲染名字）。
    final List<Map<String, Object?>> monsters = visibleCombatActors(state);

    final bool canAttack = ctl.gate.can('check.opposed');

    return Column(
      key: CombatSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: '① 选择武器（甲方：$seat）',
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (var i = 0; i < weapons.length; i++)
                RoomTap(
                  key: i == 0
                      ? CombatSheetKeys.attackBarehand
                      : CombatSheetKeys.attackWeapon(i),
                  icon: i == _weaponIndex
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  label: _weaponLabel(weapons[i], i == 0),
                  hint: i == 0 ? '斗殴技能检定，伤害 1D3 + DB' : '选这把武器',
                  onTap: () => setState(() => _weaponIndex = i),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SectionBox(
          title: '② 选择防守方（参战怪物，只显示名字）',
          child: monsters.isEmpty
              ? Text(
                  '当前没有可见的参战怪物',
                  key: CombatSheetKeys.attackEmpty,
                  style: theme.textTheme.bodySmall,
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final m in monsters)
                      RoomTap(
                        key: CombatSheetKeys.attackDefender(
                            roomText(m['id'])),
                        icon: _defenderId == roomText(m['id'])
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        label: roomText(m['name']),
                        hint: '选它作为防守方',
                        onTap: () =>
                            setState(() => _defenderId = roomText(m['id'])),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        RoomTap(
          key: CombatSheetKeys.attackSubmit,
          label: '发起攻击对抗（需 KP 同意）',
          icon: Icons.sports_martial_arts,
          enabled: canAttack,
          hint: canAttack
              ? '提交后进入待办，KP 同意并选择防守方式后自动结算'
              : '当前角色不能发起对抗',
          onTap: () => _submit(context, seat, chosen, db),
        ),
      ],
    );
  }

  /// 武器行文案。
  String _weaponLabel(Map<String, Object?> w, bool barehand) {
    if (barehand) return '肉搏斗殴（斗殴 · 1D3+DB）';
    final name = roomText(w['name']);
    final skill = roomText(w['skill']);
    final damage = roomText(w['damage']);
    return '$name · $skill · $damage';
  }

  /// 组装载荷并发 `RoomIntent.act`。
  void _submit(
    BuildContext context,
    String seat,
    Map<String, Object?> weapon,
    String db,
  ) {
    final ctl = RoomScope.of(context).controller;
    final id = _defenderId ?? '';
    if (id.isEmpty) {
      ctl.notice('请先选择防守方怪物');
      return;
    }
    final state = RoomScope.of(context).session.state;
    final Map<String, Object?> target = <String, Object?>{
      for (final m in visibleCombatActors(state))
        if (roomText(m['id']) == id) ...m,
    };
    final String targetName = roomText(target['name']);
    final bool ranged = jsStr(weapon['ranged']) == 'true' ||
        jsStr(weapon['ranged']) == '1';
    final String skill = roomText(weapon['skill']).isEmpty
        ? '斗殴'
        : roomText(weapon['skill']);
    final String wName = roomText(weapon['name']).isEmpty
        ? '武器'
        : roomText(weapon['name']);

    ctl.sendIntent(RoomIntent.act, <String, Object?>{
      'op': 'check.opposed',
      // ★ auto:true 让 P12 watcher 识别为「对可见怪的对抗」，KP 同意后弹补值窗；
      //   attack:true 让 domain 上层编排分流到伤害结算（非单方检定 log）。
      'auto': true,
      'attack': true,
      'by': seat,
      'skill': skill,
      'targetSeat': 'a:$id',
      // 命中战斗槽：结算器据此读目标 HP / 护甲并回写扣血。
      'targetId': id,
      'attacker': <String, Object?>{
        'side': 'pc',
        'seat': seat,
        'skill': skill,
        'name': seat,
      },
      'weapon': <String, Object?>{
        'name': wName,
        'skill': skill,
        'damage': roomText(weapon['damage']).isEmpty
            ? '1D3'
            : roomText(weapon['damage']),
        'db': db,
        'ranged': ranged,
        'perRound': roomText(weapon['perRound']),
        'pierce': roomText(weapon['pierce']),
      },
      // defender.reaction / defender.value 均由 confirmPending 在 KP 同意链路
      // （选防守方式 + 可选补检定值）后合并，本弹窗不预置。
      'defender': <String, Object?>{
        'side': 'monster',
        'actorId': id,
        'name': targetName,
      },
      'ranged': ranged,
      'db': db,
    });
    ctl.notice('已发起攻击对抗，等待 KP 同意并选择防守方式');
    Navigator.of(context).pop();
  }
}
