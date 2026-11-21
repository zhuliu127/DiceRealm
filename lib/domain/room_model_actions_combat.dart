// ============================================================
// room_model_actions_combat.dart — S4.3 战斗/掷骰/检定动作（D18）
//
// extension RoomHostActionsCombat on RoomHost：
//   dispatchCombatAction(seat,p) + combatStart / combatActor /
//   combatEnqueue / combatDamage / combatAttack / combatEnd /
//   diceRoll / diceDirect / darkRoll / checkRequest / checkOpposed /
//   opposed / sceneCheckPush / sceneCheckStep / playerSanCheck。
//
// ⚠️ 纯 Dart：不得引入 Flutter 包、文件 I/O 或 UI 库（C1/K7）。
// ⚠️ 骰面与成功等级一律经注入的 RoomRulesPort 计算，模型不自行判等级。
// ⚠️ 随机源/时间复用 RoomHost.rng / RoomHost.now（js_compat 注入）。
// ============================================================

import 'js_compat.dart';
import 'room_model_actions_room.dart';
import 'room_model_actions_sheet.dart';
import 'room_model_host_core.dart';
import 'room_model_rollback.dart';
import 'room_model_state.dart';
import 'room_types.dart';

extension RoomHostActionsCombat on RoomHost {
  /// 战斗/掷骰/检定组动作分发。**返回 null 表示该 op 不属于本组**。
  List<SendPlan>? dispatchCombatAction(String seat, Map<String, Object?> p) {
    final op = jsStr(p['op']);
    switch (op) {
      // ---- 战斗 ----
      case 'combat.set':
        // ★ KP-1：移出战斗走整包替换（唯一真删槽通道）。domain 侧兜底
        //   turn 索引重映射 / 越界，并在真删槽时写一条 PUBLIC 游戏记录。
        //   不新增 action / 事件 / 意图类型，仍走既有 RoomEvt.combat 广播。
        return _combatSet(p);
      case 'combat.start':
        return combatStart(p);
      case 'combat.next':
        return nextTurn();
      case 'combat.turnState':
        return _combatPush(emit(RoomEvt.turnstate, p, vis: RoomVis.public));
      case 'combat.actor':
        return combatActor(p['actor']);
      case 'combat.enqueue':
        return combatEnqueue(p);
      case 'combat.damage':
        return combatDamage(p);
      case 'combat.attack':
        return combatAttack(seat, p);
      case 'combat.end':
        return combatEnd();

      // ---- 权威掷骰 ----
      case 'dice.roll':
        return diceRoll(seat, p);
      case 'combat.roll':
        // ★ F4（team-lead 裁决 ①）：非 host 一律走权威掷骰。
        //   旧版 applyAction 对 combat.roll 没有分支，Dart 别名补齐时直接
        //   复用 diceRoll(seat, p)，于是客户端自报的 p['result']（value /
        //   levelText / rolls）被原样写进权威 dice 记录并 PUBLIC 广播。
        //   这里改为复用 diceDirect 的规则服务复算路径：只透传骰式/名称/技能，
        //   丢掉 result（以及会改变广播目标或附带事件的 secret / reqId），
        //   结果由权威端 rng 算出。KP 保持原样（权威端可自报结果），
        //   POLICY 仍是 ['kp','player']，玩家仍可发起，只是结果不由客户端给。
        //   ⚠️ P11：这里**不落检定附加信息**（`checkMeta: false`）。战斗检定按
        //   规则书不可推动，`state.dice` 的记录键集也被
        //   `room_combat_roll_authority_test.dart` 的 F4 回归用例逐键锁死；
        //   花幸运 / 推动只对「技能 · 属性」检定通道开放（与 `_pushable` 一致）。
        if (seat != kHostSeat) {
          return diceDirect(
            seat,
            roster.get(seat),
            RoomRole.player,
            <String, Object?>{
              'expr': p['expr'],
              'label': p['label'],
              'skill': p['skill'],
            },
            checkMeta: false,
          );
        }
        return diceRoll(seat, p);
      case 'dice.dark':
        return darkRoll(seat, p);
      case 'dice.direct':
        return diceDirect(seat, roster.get(seat), RoomRole.player, p);

      // ---- KP 工具 / 检定 ----
      case 'check.request':
      // ★ P10 第 3 期 B 结论（team-lead 要求给明确判断）：
      //   老 APP 里 `check.push` **只在权限表登记**（room-model.js:222
      //   `'check.push': {roles:['kp'], confirm:null}`），`applyAction`
      //   的整条 if/else 链（:1795-1830）**没有它的处理器** —— 既不是
      //   「KP 代玩家推一次检定」的别名，也没有独立语义，是一条历史遗留的
      //   「允许但无行为」占位；UI 侧亦无任何调用点（全库 grep 只有
      //   `scene.check.push`，那是另一条场景检定引擎分支）。
      //   本工程把它接到 `checkRequest` 属于**无调用方的行为增强**：
      //   保留（比空操作有用、零风险、不改权限面），用一条用例钉住
      //   「check.push 与 check.request 同行为」，避免将来被误当成独立语义。
      case 'check.push':
        return checkRequest(seat, p);
      case 'check.opposed':
        return checkOpposed(seat, p);
      case 'scene.check.push':
        return sceneCheckPush(seat, p);
      case 'scene.check.step':
        return sceneCheckStep(seat, p);
      case 'sancheck':
        return playerSanCheck(seat, roster.get(seat), p);
      case 'opposed':
        return opposed(seat, roster.get(seat), RoomRole.player, p);
      default:
        return null;
    }
  }

  List<SendPlan> _combatPush(LogRecord rec) => pushInto(<SendPlan>[], rec);

  /// KP-1 移出战斗（真删槽）的权威端整包替换 + 兜底。
  ///
  /// UI 侧（GpCombatList）删槽后把**整包** `combat` 通过
  /// `hostAction('combat.set', {'combat': ...})` 送进来，其中
  /// `combat.turn` 是 `combat.order` 的**索引**（不是槽 id）。
  ///
  /// domain 侧做两件兜底（不改变 action / 事件 / 意图类型）：
  ///  ① turn 索引重映射：以旧权威态 [state] 的 order 为基准找出被删槽的
  ///     旧索引 i，按 `i<turn→turn-1` / `i>turn→不变` /
  ///     `i==turn→clamp(0, order.length-1)` 求值，最后统一夹到合法区间。
  ///     删「当前行动单位（尤其末位）」时 UI 可能给出
  ///     `turn == order.length` 的越界值（静默错误），这里必须兜住。
  ///  ② 真删槽时写一条 PUBLIC 游戏记录（[sys]，走既有广播通道），
  ///     报文含被移出单位名「已移出战斗」。
  /// `round` 不变；`done` / `movedToTail` 随槽走 —— 二者都在整包里，
  /// domain 只可能改动 `turn` 这一个键，其余字段逐字透传。
  List<SendPlan> _combatSet(Map<String, Object?> p) {
    final out = <SendPlan>[];
    final rawCombat = p['combat'];
    final newCombat = asMap(rawCombat);
    final newOrder = asList(newCombat['order']);
    final oldCombat = asMap(state['combat']);
    final oldOrder = asList(oldCombat['order']);

    // ① 对比旧 / 新 order 的槽 id：旧有、新无 = 被移出的槽。
    //    同一 base id 的 `#n` 多行动槽一并删时会有多个旧索引，
    //    单位名去重后只写一条记录。
    final newIdSet = <Object?>{};
    for (final sRaw in newOrder) {
      newIdSet.add(asMap(sRaw)['id']);
    }
    final removedIdx = <int>[];
    final removedNames = <String>[];
    final seenNames = <String>{};
    for (var i = 0; i < oldOrder.length; i++) {
      final s = asMap(oldOrder[i]);
      final sid = s['id'];
      if (sid == null || newIdSet.contains(sid)) continue;
      removedIdx.add(i);
      final nm = cleanText(s['name'], 40);
      if (nm.isNotEmpty && seenNames.add(nm)) removedNames.add(nm);
    }

    // ② turn 索引重映射（turn 是 order 的索引，不是槽 id）。
    //    用「旧 turn 锚定的槽 id 在新 order 里的下标」统一求解：
    //      · 锚槽还在 → 下标自然体现 i<turn 的左移 / i>turn 的不变；
    //      · 锚槽被删（i==turn）→ 保持旧 turn 后由末尾 clamp 兜底。
    //    多槽（含 #n）一并删时也不会因逐个左移而重复扣减。
    final oldTurn = raNum(oldCombat['turn'], 0).toInt();
    final lastIdx = newOrder.isEmpty ? 0 : newOrder.length - 1;
    var mappedTurn = oldTurn;
    if (removedIdx.isNotEmpty) {
      var anchorAt = -1;
      if (oldTurn >= 0 && oldTurn < oldOrder.length) {
        final anchorId = asMap(oldOrder[oldTurn])['id'];
        if (anchorId != null) {
          for (var j = 0; j < newOrder.length; j++) {
            if (asMap(newOrder[j])['id'] == anchorId) {
              anchorAt = j;
              break;
            }
          }
        }
      }
      mappedTurn = anchorAt >= 0 ? anchorAt : oldTurn;
    }
    final uiTurn = raNum(newCombat['turn'], 0).toInt();
    var finalTurn = removedIdx.isNotEmpty ? mappedTurn : uiTurn;
    if (finalTurn < 0) finalTurn = 0;
    if (finalTurn > lastIdx) finalTurn = lastIdx;

    // 只有 turn 需要修正时才复制整包；否则原样透传，保证既有 oracle
    // （A:apply:combat.set）逐字节不变。
    final Object? payloadCombat = finalTurn != uiTurn
        ? <String, Object?>{...newCombat, 'turn': finalTurn}
        : rawCombat;
    pushInto(out, emit(RoomEvt.combat, <String, Object?>{
      'combat': payloadCombat,
    }, vis: RoomVis.public));

    // ③ 移出战斗写一条 PUBLIC 游戏记录（走既有 sys → RoomEvt.log 广播）。
    if (removedIdx.isNotEmpty) {
      final label = removedNames.isEmpty ? '战斗单位' : removedNames.join('」「');
      pushInto(out, sys('「$label」已移出战斗'));
    }
    return out;
  }

  // ==========================================================
  // 战斗
  // ==========================================================

  /// 默认行动顺序兜底（规则服务缺失时用；旧版 :2423-2450）。
  Map<String, Object?> initiativeFallback(Object? actorsRaw) {
    final list = <Map<String, Object?>>[];
    for (final aRaw in asList(actorsRaw)) {
      final a = asMap(aRaw);
      final dex = raNum(a['dex'], 0);
      final ready = jsTruthy(a['readyFirearm']);
      final manual = a['manualOrder'];
      list.add(<String, Object?>{
        'id': a['id'],
        'name': a['name'] ?? '',
        'dex': dex,
        'readyFirearm': ready,
        'effDex': ready ? dex + 50 : dex,
        'actionsPerRound': raNum(a['actionsPerRound'], 1) > 1
            ? raNum(a['actionsPerRound'], 1)
            : 1,
        'manualOrder': manual,
      });
    }
    list.sort((x, y) {
      final xm = raFinite(x['manualOrder']);
      final ym = raFinite(y['manualOrder']);
      if (xm != null && ym != null) return xm.compareTo(ym);
      if (xm != null) return -1;
      if (ym != null) return 1;
      final dx = raNum(y['effDex'], 0) - raNum(x['effDex'], 0);
      if (dx != 0) return dx.sign.toInt();
      return (raNum(y['dex'], 0) - raNum(x['dex'], 0)).sign.toInt();
    });
    final order = <Object?>[];
    for (final a in list) {
      final actions = raNum(a['actionsPerRound'], 1).toInt();
      for (var i = 0; i < actions; i++) {
        order.add(<String, Object?>{
          'id': a['id'],
          'name': a['name'],
          'dex': a['dex'],
          'effDex': a['effDex'],
          'readyFirearm': a['readyFirearm'],
          'manualOrder': a['manualOrder'],
          'slot': i + 1,
          'totalSlots': actions,
        });
      }
    }
    return <String, Object?>{'order': order};
  }

  /// 开战：actors 编译成行动槽（旧版 :2461-2560）。
  List<SendPlan> combatStart(Map<String, Object?> p) {
    final out = <SendPlan>[];
    var pool = asList(p['actors']);
    final idsRaw = p['actorIds'];
    final ids = idsRaw is List
        ? idsRaw.map(jsStr).toList()
        : null;
    if (ids != null && ids.isNotEmpty) {
      pool = pool
          .where((a) {
            final m = asMap(a);
            return m['kind'] == 'pc' || ids.contains(jsStr(m['id']));
          })
          .toList();
    }
    final pcSeatsRaw = p['pcSeats'];
    final pcSeats = pcSeatsRaw is List
        ? pcSeatsRaw.map(jsStr).toList()
        : null;
    if (pcSeats != null) {
      pool = pool
          .where((a) {
            final m = asMap(a);
            if (m['kind'] != 'pc') return true;
            return pcSeats.contains(jsStr(m['seat']));
          })
          .toList();
    }
    // 撕卡角色不能参战。
    final rippedSkipped = <String>[];
    pool = pool.where((a) {
      final m = asMap(a);
      if (m['kind'] == 'pc' && jsTruthy(m['seat'])) {
        final mm = roster.get(jsStr(m['seat']));
        if (mm != null && raMemberRipped(mm)) {
          rippedSkipped.add(jsStr(m['name'] ?? m['seat']));
          return false;
        }
      }
      return true;
    }).toList();
    if (rippedSkipped.isNotEmpty) {
      pushInto(out, sysTo(kHostSeat,
          '已跳过已撕卡的角色（死亡/永久疯狂，不能参战）：${rippedSkipped.join('、')}'));
    }

    final brief = <Object?>[];
    for (final aRaw in pool) {
      final a = asMap(aRaw);
      brief.add(<String, Object?>{
        'id': a['id'],
        'name': a['name'],
        'dex': a['dex'],
        'readyFirearm': jsTruthy(a['readyFirearm']) ||
            jsTruthy(a['ready']) ||
            jsTruthy(a['preparedFirearm']),
        'actionsPerRound': a['actionsPerRound'],
        'manualOrder': a['manualOrder'],
      });
    }
    var ordered = rules?.initiativeOrder(brief, <String, Object?>{
      'useReadyFirearm': p['useReadyFirearm'] != false,
    });
    if (ordered == null || ordered['order'] is! List) {
      ordered = initiativeFallback(brief);
    }
    final byId = <String, Map<String, Object?>>{};
    for (final aRaw in pool) {
      final a = asMap(aRaw);
      byId[jsStr(a['id'])] = a;
    }
    // ★ P16 KP-4① / KP-8：权威端候选池（localActors，含 hp/hpMax 及护甲）
    //   作为 combat.start 载荷缺键时的补全源，避免「缺 hp 静默兜底 0」。
    final localById = <String, Map<String, Object?>>{
      for (final la in localActors) jsStr(la['id']): la,
    };
    final slots = <Object?>[];
    for (final oRaw in asList(ordered['order'])) {
      final o = asMap(oRaw);
      final a = byId[jsStr(o['id'])] ?? <String, Object?>{};
      final fallback =
          localById[jsStr(o['id'])] ?? const <String, Object?>{};
      // 缺键才从候选池同 id 原值补全；有键时取值与旧口径完全一致
      // （A:apply:combat.start 等 oracle 逐字段契约保持不变）。
      final hp =
          a['hp'] != null ? raNum(a['hp'], 0) : raNum(fallback['hp'], 0);
      final hpMax = a['hpMax'] != null
          ? raNum(a['hpMax'], hp)
          : raNum(fallback['hpMax'], hp);
      final armor = a['armor'] ?? fallback['armor'];
      final actions = raNum(o['totalSlots'],
          raNum(a['actionsPerRound'], 1) > 1 ? raNum(a['actionsPerRound'], 1) : 1)
          .toInt();
      if (actions < 1) continue;
      final slotNo = raNum(o['slot'], 1).toInt();
      slots.add(<String, Object?>{
        'id': '${jsStr(o['id'])}${actions > 1 ? '#$slotNo' : ''}',
        'actorId': jsStr(o['id']),
        'name': jsTruthy(a['name']) ? a['name'] : (o['name'] ?? ''),
        'seat': a['seat'] ?? '',
        'kind': a['kind'] ?? 'npc',
        'dex': raNum(a['dex'], raNum(o['dex'], 0)),
        'effDex': raNum(o['effDex'], raNum(a['dex'], 0)),
        'readyFirearm': jsTruthy(o['readyFirearm']),
        'manual': o['manualOrder'] != null,
        'manualOrder': o['manualOrder'],
        'slot': slotNo,
        'totalSlots': actions,
        'done': false,
        'movedToTail': false,
        'public': <String, Object?>{
          'dex': raNum(a['dex'], 0),
          'state': a['state'] ?? '',
          'hpPublic': a['kind'] == 'pc' ? true : a['hpPublic'] == true,
          'hp': hp,
          'hpMax': hpMax,
          'down': jsTruthy(a['down']),
        },
        // ★ P16 KP-8：仅当上游带 armor 时加键（老载荷无 → slot 结构
        //   逐字节不变），供下方 :585 的 tSlot['armor'] fallback 生效；
        //   room_rules_combat.dart 的 max(0, raw-armor) 计算式绝不改。
        if (armor != null) 'armor': raNum(armor, 0),
        // ★ PL-1b（任务 A）：仅当上游**显式带**可见性标记时透传到战斗槽。
        //   实测数据流：`a = byId[o['id']]` 来自 `pool = asList(p['actors'])`
        //   （actor 定义，带该字段）；`o` 是 initiativeOrder 产出的行动项
        //   （只有 id/name/dex/effDex/...，无该字段）；`fallback` 是
        //   localActors 同 id 候选（setActorPool 写入）。优先 a，次取 fallback。
        //   老载荷 / 老存档无此键 → slot 结构逐字节不变（oracle 零漂移）。
        //   ⚠️ 放槽顶层，绝不写进下面的 `public` 子袋（那是已裁剪的公开袋）。
        if (a.containsKey('visibleToPlayers') ||
            fallback.containsKey('visibleToPlayers'))
          'visibleToPlayers': jsTruthy(a.containsKey('visibleToPlayers')
              ? a['visibleToPlayers']
              : fallback['visibleToPlayers']),
      });
    }
    final combat = <String, Object?>{
      'order': slots,
      'turn': 0,
      'round': 1,
      'startedAt': now(),
    };
    state['combat'] = combat;
    stampAllPcSlots();
    asMap(state['meta'])['mode'] = RoomMode.combat;
    pushInto(out, emit(RoomEvt.status, <String, Object?>{
      'status': asMap(state['meta'])['status'],
      'mode': RoomMode.combat,
    }, vis: RoomVis.public));
    pushInto(out, emit(RoomEvt.combat, <String, Object?>{
      'combat': roomClone(combat),
    }, vis: RoomVis.public));
    pushInto(out, sys('进入战斗：共 ${slots.length} 个行动槽'));
    return out;
  }

  /// 新增 / 更新一个战斗参与者（旧版 :2563-2570）。
  List<SendPlan> combatActor(Object? actorRaw) {
    final actor = asMap(actorRaw);
    if (!jsTruthy(actor['id'])) {
      localSeq += 1;
      actor['id'] = 'x$localSeq';
    }
    final out = <SendPlan>[];
    pushInto(out, emit(RoomEvt.actor, <String, Object?>{
      'actor': roomClone(actor),
    }, vis: RoomVis.public));
    pushInto(out, sys('KP 更新了战斗单位「${actor['name'] ?? ''}」'));
    return out;
  }

  /// 追加进现有战斗（幂等，不重置 turn/round；旧版 :2591-2713）。
  List<SendPlan> combatEnqueue(Map<String, Object?> p) {
    final out = <SendPlan>[];
    if (state['combat'] is! Map) {
      pushInto(out, sysTo(kHostSeat,
          '当前不在战斗中，无法把单位加入战斗（请先开始战斗）'));
      return out;
    }
    final c = asMap(state['combat']);
    if (c['order'] is! List) c['order'] = <Object?>[];
    final order = asList(c['order']);
    final seatList = <Object?>[];
    if (p['seats'] is List) seatList.addAll(asList(p['seats']));
    if (p['seat'] != null && p['seat'] != '') seatList.add(p['seat']);
    final idList = <Object?>[];
    if (p['actorIds'] is List) idList.addAll(asList(p['actorIds']));
    if (p['actorId'] != null && p['actorId'] != '') idList.add(p['actorId']);
    final added = <String>[];
    final skippedRipped = <String>[];

    for (final rawSeat in seatList) {
      final seat = cleanText(rawSeat, 40);
      if (seat.isEmpty) continue;
      var exists = false;
      for (final sRaw in order) {
        final s = asMap(sRaw);
        if (s['kind'] == 'pc' && s['seat'] == seat) exists = true;
      }
      if (exists) continue;
      final m = roster.get(seat);
      final name = raUnitName(this, m, seat);
      if (m != null && raMemberRipped(m)) {
        skippedRipped.add(name);
        continue;
      }
      final dex = skillBaseOf(m, '敏捷', null);
      final hp = m == null ? null : raMemberStatusValue(m, 'currentHP');
      final hpMax = m != null && m['sheet'] is Map
          ? raFinite(asMap(asMap(m['sheet'])['status'])['maxHP'])
          : null;
      final d = dex ?? 0;
      final h = hp ?? 0;
      final hm = hpMax ?? h;
      order.add(<String, Object?>{
        'id': 'p-$seat',
        'actorId': 'p-$seat',
        'name': name,
        'seat': seat,
        'kind': 'pc',
        'dex': d,
        'effDex': d,
        'readyFirearm': false,
        'manual': false,
        'manualOrder': null,
        'slot': 1,
        'totalSlots': 1,
        'done': false,
        'movedToTail': false,
        'public': <String, Object?>{
          'dex': d,
          'state': '',
          'hpPublic': true,
          'hp': h,
          'hpMax': hm,
          'down': false,
        },
      });
      added.add(name);
    }
    for (final rawId in idList) {
      final id = cleanText(rawId, 40);
      if (id.isEmpty) continue;
      var exists = false;
      for (final sRaw in order) {
        final s = asMap(sRaw);
        if (s['actorId'] == id || s['id'] == id) exists = true;
      }
      if (exists) continue;
      Map<String, Object?>? a;
      for (final x in localActors) {
        if (x['id'] == id) a = x;
      }
      if (a == null) continue;
      final dx = raNum(a['dex'], 0);
      final ah = raNum(a['hp'], 0);
      final ahm = raNum(a['hpMax'], ah);
      final kind = (a['kind'] == 'monster' || a['kind'] == 'npc')
          ? a['kind']
          : 'npc';
      order.add(<String, Object?>{
        'id': jsStr(a['id']),
        'actorId': jsStr(a['id']),
        'name': cleanText(a['name'], 24).isNotEmpty
            ? cleanText(a['name'], 24)
            : '单位',
        'seat': '',
        'kind': kind,
        'dex': dx,
        'effDex': dx,
        'readyFirearm': false,
        'manual': false,
        'manualOrder': null,
        'slot': 1,
        'totalSlots': raNum(a['actionsPerRound'], 1) > 1
            ? raNum(a['actionsPerRound'], 1)
            : 1,
        'done': false,
        'movedToTail': false,
        'public': <String, Object?>{
          'dex': dx,
          'state': '',
          'hpPublic': false,
          'hp': ah,
          'hpMax': ahm,
          'down': false,
        },
      });
      added.add(cleanText(a['name'], 24).isNotEmpty
          ? cleanText(a['name'], 24)
          : '单位');
    }
    if (added.isEmpty) {
      pushInto(out, sysTo(kHostSeat, skippedRipped.isNotEmpty
          ? '「${skippedRipped.join('」「')}」已撕卡（死亡/永久疯狂），不能加入战斗'
          : '没有可加入战斗的目标（已在队列中的会被跳过）'));
      return out;
    }
    if (skippedRipped.isNotEmpty) {
      pushInto(out, sysTo(kHostSeat,
          '已跳过已撕卡的角色（死亡/永久疯狂，不能加入战斗）：${skippedRipped.join('、')}'));
    }
    stampAllPcSlots();
    pushInto(out, emit(RoomEvt.turnstate, <String, Object?>{
      'turn': c['turn'],
      'round': c['round'],
      'order': order,
    }, vis: RoomVis.public));
    pushInto(out, sys('KP 把「${added.join('」「')}」加入了战斗'));
    return out;
  }

  /// 伤害结算（旧版 :2716-2756）。
  List<SendPlan> combatDamage(Map<String, Object?> p) {
    final out = <SendPlan>[];
    if (state['combat'] is! Map) {
      pushInto(out, sysTo(kHostSeat, '当前没有战斗'));
      return out;
    }
    final c = asMap(state['combat']);
    final order = asList(c['order']);
    Map<String, Object?>? slot;
    for (final sRaw in order) {
      if (asMap(sRaw)['id'] == p['slotId']) slot = asMap(sRaw);
    }
    if (slot == null) {
      pushInto(out, sysTo(kHostSeat, '找不到该行动槽'));
      return out;
    }
    if (slot['public'] is! Map) slot['public'] = <String, Object?>{};
    final pub = asMap(slot['public']);
    final beforeHp = raNum(pub['hp'], 0);
    final dmg = raNum(p['damage'], 0);
    pub['hp'] = (beforeHp - dmg) > 0 ? beforeHp - dmg : 0;
    if (p['state'] != null) pub['state'] = p['state'];
    pub['down'] = raNum(pub['hp'], 0) <= 0;
    pushInto(out, emit(RoomEvt.actor, <String, Object?>{
      'actor': roomClone(slot),
    }, vis: RoomVis.public));
    if (jsTruthy(slot['seat'])) {
      final victim = roster.get(jsStr(slot['seat']));
      if (victim != null) {
        out.addAll(applyHpChange(victim, -dmg, '战斗伤害', <String, Object?>{
          'base': <String, Object?>{
            'maxHP': raNum(pub['hpMax'], beforeHp > 0 ? beforeHp : 1),
            'currentHP': beforeHp,
          },
        }));
        final vhp = raMemberStatusValue(victim, 'currentHP');
        if (vhp != null) pub['hp'] = vhp;
        out.addAll(syncBodyToCombatSlot(victim));
      } else {
        out.addAll(stateApply(jsStr(slot['seat']), <String, Object?>{
          'status': <String, Object?>{'currentHP': raNum(pub['hp'], 0)},
        }, <String, Object?>{'reason': '战斗伤害'}));
      }
    }
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': kHostSeat,
      'text': '${jsStr(slot['name'] ?? '')} 受到 ${dmg.toInt()} 点伤害'
          '${jsTruthy(p['summary']) ? '（${jsStr(p['summary'])}）' : ''}',
      'at': now(),
      'kind': 'damage',
    }, vis: RoomVis.public));
    return out;
  }

  /// 玩家 / KP 提交一次攻击（走规则服务；旧版 :2767-2905）。
  List<SendPlan> combatAttack(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    if (state['combat'] is! Map) {
      pushInto(out, sysTo(seat, '当前没有战斗'));
      return out;
    }
    final c = asMap(state['combat']);
    final order = asList(c['order']);
    final turn = raNum(c['turn'], 0).toInt();
    final cur = turn >= 0 && turn < order.length
        ? asMap(order[turn])
        : <String, Object?>{};
    if (seat != kHostSeat && cur['seat'] != seat) {
      pushInto(out, sysTo(seat, '还没轮到你行动'));
      return out;
    }
    var tSlot = <String, Object?>{};
    for (final sRaw in order) {
      if (asMap(sRaw)['actorId'] == p['targetId']) tSlot = asMap(sRaw);
    }
    if (seat != kHostSeat &&
        tSlot.isNotEmpty &&
        tSlot['kind'] != 'monster') {
      pushInto(out, sysTo(seat, '只能攻击怪物/NPC，不能攻击队友'));
      return out;
    }
    var aSlot = cur;
    if (p['slotId'] != null) {
      for (final sRaw in order) {
        if (asMap(sRaw)['id'] == p['slotId']) aSlot = asMap(sRaw);
      }
    }
    final nick = raNick(this, roster.get(seat), seat);
    final aMem = jsTruthy(aSlot['seat'])
        ? roster.get(jsStr(aSlot['seat']))
        : null;
    final tMem = jsTruthy(tSlot['seat'])
        ? roster.get(jsStr(tSlot['seat']))
        : null;
    final attackValue = skillBaseOf(aMem, p['skill'], p['base'] ?? 50);
    final defenseValue = skillBaseOf(
        tMem,
        jsTruthy(p['defenseSkill']) ? p['defenseSkill'] : '闪避',
        p['defenseBase'] ?? 25);
    final tPub = asMap(tSlot['public']);
    var tHp = raNum(tPub['hp'], raNum(tSlot['hp'], 0));
    var tMaxHp = raNum(tPub['hpMax'], raNum(tSlot['hpMax'], tHp));
    if (tMem != null && tMem['sheet'] is Map) {
      final st = asMap(asMap(tMem['sheet'])['status']);
      if (st['currentHP'] != null) tHp = raNum(st['currentHP'], tHp);
      if (st['maxHP'] != null) tMaxHp = raNum(st['maxHP'], tMaxHp);
    }
    final args = <String, Object?>{
      ...ruleOptsOf(asMap(state['meta'])),
      'attack': <String, Object?>{
        'name': cleanText(p['skill'], 30).isNotEmpty
            ? cleanText(p['skill'], 30)
            : '格斗',
        'value': raNum(attackValue, 50),
        'ranged': jsTruthy(p['ranged']) ||
            jsTruthy(asMap(p['attack'])['ranged']),
      },
      'defense': <String, Object?>{
        'name': cleanText(p['defenseSkill'], 30).isNotEmpty
            ? cleanText(p['defenseSkill'], 30)
            : '闪避',
        'value': raNum(defenseValue, 25),
        'mode': p['defense'] == 'fightback'
            ? 'fightback'
            : (p['defense'] == 'none' ? 'none' : 'dodge'),
      },
      'damage': <String, Object?>{
        'expr': cleanText(p['damage'], 20).isNotEmpty
            ? cleanText(p['damage'], 20)
            : '1D3',
        'db': cleanText(p['db'], 10).isNotEmpty ? cleanText(p['db'], 10) : '0',
      },
      'armor': <String, Object?>{
        'value': raNum(p['armor'], raNum(tSlot['armor'], 0)),
      },
      'impale': jsTruthy(p['impale']),
      'difficulty': p['difficulty'] ?? 'REGULAR',
      'bonus': raNum(p['bonus'], 0),
      'penalty': raNum(p['penalty'], 0),
      'secret': jsTruthy(p['secret']),
      'maxHP': tMaxHp,
      'currentHP': tHp,
      'target': <String, Object?>{
        'maxHP': tMaxHp,
        'currentHP': tHp,
        'majorWound': jsTruthy(tPub['majorWound']),
      },
      'ranged': jsTruthy(p['ranged']) ||
          jsTruthy(asMap(p['attack'])['ranged']),
      'rng': p['rng'] ?? rng,
    };
    final res = rules?.resolveAttack(args);
    if (res != null) {
      final outcome = jsStr(res['outcome'] ?? 'hit');
      final appliedDmg = asMap(res['damage']);
      final applied = raNum(appliedDmg['applied'], 0) > 0
          ? raNum(appliedDmg['applied'], 0)
          : 0;
      Map<String, Object?>? victim;
      if (applied > 0) {
        if (outcome == 'defender_wins') {
          victim = aSlot.isEmpty ? null : aSlot;
        } else if (outcome == 'hit' || outcome == 'attacker_wins') {
          victim = tSlot.isEmpty ? null : tSlot;
        }
      }
      if (victim != null && applied > 0) {
        if (victim['public'] is! Map) {
          victim['public'] = <String, Object?>{};
        }
        final pub = asMap(victim['public']);
        final before = raNum(pub['hp'], 0);
        pub['hp'] = (before - applied) > 0 ? before - applied : 0;
        pub['down'] = raNum(pub['hp'], 0) <= 0;
        final flags = asMap(res['flags']);
        if (res['flags'] is Map && flags['unknown'] != true) {
          if (flags['dead'] == true) {
            pub['state'] = 'dead';
          } else if (flags['dying'] == true) {
            pub['state'] = 'dying';
          } else if (flags['unconscious'] == true) {
            pub['state'] = 'unconscious';
          } else if (flags['majorWound'] == true) {
            pub['state'] = 'majorWound';
          }
        }
        pushInto(out, emit(RoomEvt.actor, <String, Object?>{
          'actor': roomClone(victim),
        }, vis: RoomVis.public));
        if (jsTruthy(victim['seat'])) {
          final vMem = roster.get(jsStr(victim['seat']));
          if (vMem != null) {
            out.addAll(applyHpChange(vMem, -applied, '战斗受伤',
                <String, Object?>{
                  'base': <String, Object?>{
                    'maxHP': raNum(pub['hpMax'],
                        raNum(victim['hpMax'], before > 0 ? before : 1)),
                    'currentHP': before,
                  },
                }));
            final vHp = raMemberStatusValue(vMem, 'currentHP');
            if (vHp != null) pub['hp'] = vHp;
            out.addAll(syncBodyToCombatSlot(vMem));
          } else {
            out.addAll(stateApply(jsStr(victim['seat']), <String, Object?>{
              'status': <String, Object?>{'currentHP': raNum(pub['hp'], 0)},
            }, <String, Object?>{'reason': '战斗受伤'}));
          }
        }
      }
      final weapon = <String, Object?>{
        'name': cleanText(p['weaponName'], 40).isNotEmpty
            ? cleanText(p['weaponName'], 40)
            : (cleanText(p['skill'], 30).isNotEmpty
                ? cleanText(p['skill'], 30)
                : '武器'),
        'malfunction': cleanText(p['malfunction'], 8),
        'perRound': cleanText(p['perRound'], 12),
      };
      applyMalfunction(out, seat, weapon,
          raNum(asMap(res['attack'])['value'], 0),
          jsTruthy(asMap(res['attack'])['critical']), p['malfType']);
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': seat,
        'text': '$nick 发起攻击${jsTruthy(res['summary']) ? '：${jsStr(res['summary'])}' : ''}',
        'at': now(),
        'kind': 'attack',
      }, vis: RoomVis.public));
    } else {
      final r2 = asMap(p['result']);
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': seat,
        'text': '$nick 发起攻击${jsTruthy(r2['summary']) ? '：${jsStr(r2['summary'])}' : ''}',
        'at': now(),
        'kind': 'attack',
      }, vis: RoomVis.public));
    }
    return out;
  }

  /// 枪械故障判定统一落地点（旧版 :2917-2963）。
  void applyMalfunction(
    List<SendPlan> out,
    String seat,
    Map<String, Object?> weapon,
    num rollValue,
    bool isCritical,
    Object? kpType,
  ) {
    final r = rules?.malfunctionOf(weapon, rollValue,
        <String, Object?>{'critical': isCritical});
    if (r == null || r['jammed'] != true) return;
    final eff = rules?.malfunctionEffect(weapon,
        cleanText(kpType, 12).isNotEmpty ? cleanText(kpType, 12) : null, rng);
    if (eff == null) return;
    final mem = roster.get(seat);
    final who = raNick(this, mem, seat);
    final wname = cleanText(weapon['name'], 40).isNotEmpty
        ? cleanText(weapon['name'], 40)
        : '武器';
    if (mem != null) {
      if (mem['sheet'] is! Map) {
        mem['sheet'] = raSanitizeSheet(<String, Object?>{}, mem, now());
      }
      final sheet = asMap(mem['sheet']);
      if (sheet['tempStatus'] is! List) {
        sheet['tempStatus'] = <Object?>[];
      }
      final tsList = List<Object?>.from(asList(sheet['tempStatus']));
      tsList.add(<String, Object?>{
        'text': '$wname ${jsStr(eff['label'])}${jsStr(eff['clearText'] ?? '')}',
        'by': 'kp',
        'at': now(),
      });
      out.addAll(stateApply(seat, <String, Object?>{'tempStatus': tsList},
          <String, Object?>{'reason': '武器故障：${jsStr(eff['label'])}'}));
      if (eff['destroyed'] == true) {
        final ws = List<Object?>.from(asList(sheet['weapons']));
        var marked = false;
        for (var i = 0; i < ws.length; i++) {
          if (cleanText(asMap(ws[i])['name'], 40) == wname) {
            ws[i] = <String, Object?>{
              ...asMap(ws[i]),
              'broken': true,
            };
            marked = true;
          }
        }
        if (!marked) {
          ws.add(<String, Object?>{...weapon, 'broken': true});
        }
        out.addAll(stateApply(seat, <String, Object?>{'weapons': ws},
            <String, Object?>{'reason': '武器损坏：$wname'}));
        final dmg = raNum(eff['damage'], 0);
        if (dmg > 0) {
          out.addAll(applyHpChange(mem, -dmg, '$wname 炸膛',
              <String, Object?>{}));
        }
      }
    }
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': seat,
      'kind': 'attack',
      'text': '$who 的 $wname ${jsStr(eff['label'])}${jsStr(eff['clearText'] ?? '')}'
          '${eff['destroyed'] == true ? '，武器彻底损坏' : ''}'
          '${raNum(eff['damage'], 0) > 0 ? '，$who 受 ${raNum(eff['damage'], 0).toInt()} 点伤害' : ''}',
      'at': now(),
    }, vis: RoomVis.public));
  }

  /// 战斗结束（旧版 :2965-2972）。
  List<SendPlan> combatEnd() {
    final out = <SendPlan>[];
    asMap(state['meta'])['mode'] = RoomMode.exploration;
    pushInto(out, emit(RoomEvt.combat, <String, Object?>{
      'combat': null,
    }, vis: RoomVis.public));
    pushInto(out, emit(RoomEvt.status, <String, Object?>{
      'status': asMap(state['meta'])['status'],
      'mode': RoomMode.exploration,
    }, vis: RoomVis.public));
    pushInto(out, sys('战斗结束，回到探索模式'));
    return out;
  }

  // ==========================================================
  // 权威掷骰
  // ==========================================================

  /// 记进公共事件流并广播（旧版 :2980-3002）。
  ///
  /// ★ P11：检定结果（`rules.check()` 的产物）要把「目标/难度/类型」一起带出去，
  ///   否则玩家侧只剩一个裸骰值，既没法算「花多少幸运能改成成功」，也没法判断
  ///   该检定能不能推动 —— 见 [RoomEvt.dice] 归约分支里的同名可选键。
  ///   **只有真带这些键时才写**（快捷骰 1D6 之类一个键都不多），
  ///   既有「出站序列 / 状态深比」用例逐字节不受影响。
  ///   [checkMeta] = false 的调用方（`combat.roll`）保持旧记录键集不变 ——
  ///   见 `dispatchCombatAction` 里的说明。
  List<SendPlan> diceRoll(
    String seat,
    Map<String, Object?> p, {
    bool checkMeta = true,
  }) {
    final res = asMap(p['result']);
    final nick = raNick(this, roster.get(seat), seat);
    final dice = asMap(res['dice']);
    final isCheck =
        checkMeta && res.containsKey('target') && res.containsKey('kind');
    return _combatPush(emit(RoomEvt.dice, <String, Object?>{
      'seat': seat,
      'nickname': nick,
      'expr': cleanText(p['expr'], 40).isNotEmpty
          ? cleanText(p['expr'], 40)
          : '1D100',
      'rolls': roomClone(asList(res['rolls'])),
      'detail': jsTruthy(dice['detail'])
          ? dice['detail']
          : (res['detail'] ?? ''),
      'total': res['value'] ?? res['total'],
      'level': res['levelKey'] ?? res['level'] ?? '',
      'levelText': res['levelText'] ?? '',
      'label': cleanText(p['label'], 20),
      'at': now(),
      // ---- 检定附加信息（可选键；快捷骰一个都不写）----
      if (isCheck) 'kind': res['kind'],
      if (isCheck) 'base': res['base'],
      if (isCheck) 'target': res['target'],
      if (isCheck) 'difficulty': res['difficulty'],
      if (isCheck) 'required': res['required'],
      if (isCheck) 'critMax': res['critMax'],
      if (isCheck) 'fumbleMin': res['fumbleMin'],
      if (res.containsKey('pushed')) 'pushed': res['pushed'],
      if (res.containsKey('luckSpent')) 'luckSpent': res['luckSpent'],
      if (res.containsKey('luckFrom')) 'luckFrom': res['luckFrom'],
      if (res.containsKey('pushFrom')) 'pushFrom': res['pushFrom'],
    }, vis: RoomVis.public));
  }

  /// 玩家直投骰子（INTENT.DICE direct；旧版 :3016-3091）。
  List<SendPlan> diceDirect(
    String seat,
    Map<String, Object?>? mem,
    String role,
    Map<String, Object?> p, {
    bool checkMeta = true,
  }) {
    final out = <SendPlan>[];
    if (role == RoomRole.spectator) {
      pushInto(out, sysTo(seat, '旁观者不能掷骰'));
      return out;
    }
    final expr = cleanText(p['expr'], 40).isNotEmpty
        ? cleanText(p['expr'], 40)
        : '1D100';
    Map<String, Object?> res;
    if (expr != '1D100') {
      final rr = rules?.rollExpr(expr, rng);
      if (rr != null && rr['ok'] == true) {
        res = <String, Object?>{
          'rolls': rr['rolls'],
          'value': rr['total'],
          'detail': rr['detail'],
        };
      } else {
        pushInto(out, sysTo(seat,
            jsTruthy(rr?['reason']) ? jsStr(rr!['reason']) : '骰式不合法'));
        return out;
      }
    } else {
      final authBase = skillBaseOf(mem,
          jsTruthy(p['skill']) ? p['skill'] : p['label'], null);
      final base = authBase == null
          ? raClampNumber(p['base'], 0, 100, 100)
          : raClampNumber(authBase, 0, 100, 100);
      final opts = <String, Object?>{
        ...ruleOptsOf(asMap(state['meta'])),
        'kind': 'skill',
        'base': base,
        'difficulty': p['difficulty'] ?? 'REGULAR',
        'bonus': raClampNumber(p['bonus'], 0, kRaModCap, 0),
        'penalty': raClampNumber(p['penalty'], 0, kRaModCap, 0),
        'label': cleanText(p['label'], 20),
      };
      res = rules?.check(opts) ??
          <String, Object?>{'value': 1 + (rng() * 100).floor()};
    }
    if (jsTruthy(p['secret'])) {
      // ★ B1-F1（P2 隐私修复，方案 ②：只在 diceDirect 侧分流）：
      //   旧版 room-model.js:612-618 的 reduceRoomState EVT.DICE 分支**不看
      //   evt.vis**，于是这里 emit 的两条 SEAT 定向 DICE 事件都会 push 进
      //   公共 state.dice，再经 makeSync/save 的 `dice: clone(st.dice)`
      //   全量下发给所有玩家并写进存档 —— 与公共日志承诺的
      //   「只有他/她与 KP 可见」直接矛盾（B1 接线后玩家端首次可达）。
      //   现改为发 EVT.PRIVATE（SEAT 定向）给本人与 KP：完整结果只进
      //   privateBySeat（syncFor 按 seat 裁剪），state.dice 只承载公开骰。
      //   ⚠️ reduceRoomState 的 DICE 分支 / makeSync / syncFor / save 均不动。
      final nick = raNick(this, roster.get(seat), seat);
      final label = cleanText(p['label'], 20);
      final total = res['value'] ?? res['total'];
      final levelText = jsStr(res['levelText'] ?? '');
      final detail = jsTruthy(asMap(res['dice'])['detail'])
          ? jsStr(asMap(res['dice'])['detail'])
          : jsStr(res['detail'] ?? '');
      // _accumulatePrivate 只保留 {seq,title,text,at,kind} 五键，因此
      // 「完整结果」必须编码进 text；实时 evt 的 p 另带一份结构化字段，
      // SEAT 事件不被 scrub、cropFor 对 private 原样透传，UI 可直接渲染。
      final text = '暗骰 $expr'
          '${label.isNotEmpty ? '（$label）' : ''}'
          ' = ${jsStr(total)}'
          '${levelText.isNotEmpty ? '（$levelText）' : ''}'
          '${detail.isNotEmpty ? '　明细：$detail' : ''}';
      final privatePayload = <String, Object?>{
        'title': '暗骰结果',
        'text': text,
        'at': now(),
        'kind': 'dice-dark',
        // 保留旧版 payload 的 secret 标记：若日后有人误把这条改成 PUBLIC，
        // emit 的 hasSecret 闸门会立刻 scrub + 记 warning（多一层机械防呆）。
        // 当前两条都是 VIS.SEAT，不触发 scrub，也不产生 warning。
        'secret': true,
        'seat': seat,
        'nickname': nick,
        'expr': expr,
        'rolls': roomClone(asList(res['rolls'])),
        'total': total,
        'level': res['levelKey'] ?? res['level'] ?? '',
        'levelText': levelText,
        'detail': detail,
        'label': label,
      };
      // 本人：能看到自己那颗骰的完整结果。
      pushInto(
        out,
        emit(
          RoomEvt.private_,
          roomClone(privatePayload) as Map<String, Object?>,
          vis: RoomVis.seat,
          to: seat,
        ),
      );
      // KP：权威端必须看得见才能裁定（与 darkRoll 同款 to:kHostSeat）。
      if (seat != kHostSeat) {
        pushInto(
          out,
          emit(
            RoomEvt.private_,
            roomClone(privatePayload) as Map<String, Object?>,
            vis: RoomVis.seat,
            to: kHostSeat,
          ),
        );
      }
      // 公共侧只留一句脱敏提示，不含 total / levelText / 骰面明细。
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': seat,
        'text': '$nick 暗骰了一次（结果只有他/她与 KP 可见）',
        'at': now(),
        'kind': 'dice-dark',
      }, vis: RoomVis.public));
    } else {
      // 公开骰：行为完全不变，仍 diceRoll → EVT.DICE + to:'*' + 进 state.dice。
      out.addAll(diceRoll(seat, <String, Object?>{
        'expr': expr,
        'label': p['label'],
        'result': res,
      }, checkMeta: checkMeta));
    }
    final reqId = cleanText(p['reqId'], 24);
    if (reqId.isNotEmpty) {
      out.addAll(settleRequest(seat, reqId, true, '完成了检定'));
    }
    return out;
  }

  /// 暗骰（结果只进 KP 私密；旧版 :4492-4518）。
  List<SendPlan> darkRoll(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final count = raClampNumber(p['count'], 1, 20, 1).toInt();
    final sides = raClampNumber(p['sides'], 2, 1000, 100).toInt();
    final bonus = raClampNumber(p['bonus'], -999, 999, 0).toInt();
    final rolls = <int>[];
    for (var i = 0; i < count; i++) {
      rolls.add(1 + (rng() * sides).floor());
    }
    var total = bonus;
    for (final r in rolls) {
      total += r;
    }
    final expr = '$count' 'D$sides'
        '${bonus != 0 ? (bonus > 0 ? '+$bonus' : '$bonus') : ''}';
    final reason = cleanText(p['reason'], 60);
    pushInto(out, emit(RoomEvt.private_, <String, Object?>{
      'title': '暗骰',
      'kind': 'dark',
      'text': '🕶 $expr = $total'
          '${rolls.length > 1 ? '（${rolls.join('、')}）' : ''}'
          '${reason.isNotEmpty ? '　理由：$reason' : ''}',
      'at': now(),
    }, vis: RoomVis.seat, to: kHostSeat));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': 'KP 暗骰了一次',
      'at': now(),
      'kind': 'dark',
    }, vis: RoomVis.public));
    return out;
  }

  // ==========================================================
  // KP 工具 / 检定请求
  // ==========================================================

  /// 按权威端存的技能/难度替该玩家掷一次 D100（旧版 :3106-3131）。
  ///
  /// ★ P10 第 3 期 B：不再是死代码 —— 已按老 APP `room-model.js:1554-1566`
  ///   接到 `RoomHostIntent.consent` 的「同意 check.request」分支。
  ///   目标值优先级同样照抄老 APP：① 角色卡权威技能值 → ② 请求载荷里的
  ///   KP 权威 base → ③ 100；难度取请求载荷，绝不采信客户端回传值。
  List<SendPlan> rollCheckRequest(String seat, Map<String, Object?> req) {
    final pl = asMap(req['payload']);
    final mem = roster.get(seat);
    final authBase = skillBaseOf(mem, pl['skill'], null);
    final base = authBase == null
        ? raClampNumber(pl['base'], 0, 100, 100)
        : raClampNumber(authBase, 0, 100, 100);
    final res = rules?.check(<String, Object?>{
      ...ruleOptsOf(asMap(state['meta'])),
      'kind': 'skill',
      'base': base,
      'difficulty': pl['difficulty'] ?? 'REGULAR',
      'bonus': 0,
      'penalty': 0,
      'label': cleanText(pl['skill'], 20),
    }) ?? <String, Object?>{'value': 1 + (rng() * 100).floor()};
    return diceRoll(seat, <String, Object?>{
      'expr': '1D100',
      'label': pl['skill'],
      'result': res,
    });
  }

  // ==========================================================
  // P11 · CoC 7e「花幸运」与「推动检定」
  // ==========================================================
  //
  // 为什么放在 combat 组：两者都只对「检定结果」起作用，与 diceDirect /
  // rollCheckRequest / checkRequest 同一族；三个 dispatch 组的选择不影响协议。
  //
  // ★ 为什么不新增 RoomEvt：现有 27 项被覆盖矩阵（fixture 的 EVT 全量 tag）锁死，
  //   而「结果被幸运改过 / 这次是推动重掷」本质上还是**一条骰子记录** ——
  //   用既有的 `EVT.DICE`（带 `luckSpent` / `pushed` 可选键）+ `EVT.LOG`
  //   （公共播报）+ `EVT.STATE`（角色卡 currentLuck 写回）三件套就能完整表达，
  //   且回退重放能把三件事一起还原。
  //
  // ★ 为什么不新增 POLICY action：`kRoomPolicy` 的 61 条同样被
  //   `test/fixtures/room_model.json` 的 `P:*` / `N:*` 覆盖矩阵锁死（加一条就要
  //   改 fixture）。这两个动作只改**自己**的检定结果，天然属于「13 个意图通道
  //   不经 POLICY」的 `INTENT.DICE` 家族（该通道本来就不走 needs()），
  //   所以在 `intent` 的 dice 分支里按载荷字段分流，权限面一字不动。

  /// 该座位**最近一条**公共骰记录（不是「最近一条检定」——刻意的）。
  ///
  /// 语义：幸运 / 推动只能作用于「刚掷出的这条」。如果该玩家最近一次掷的是
  /// 3D6 伤害骰，那前面那条失败的侦查检定**已经翻篇**，不能再回头去改它
  /// （否则「未结算」范围含糊，还能被用来反复改老结果）。找不到返回 null。
  Map<String, Object?>? lastDiceOf(String seat) {
    final dice = asList(state['dice']);
    for (var i = dice.length - 1; i >= 0; i--) {
      final r = asMap(dice[i]);
      if (jsStr(r['seat']) == seat) return r;
    }
    return null;
  }

  /// 把 `state.dice` 的记录还原成规则层能吃的 `result` 形状。
  ///
  /// ⚠️ `_spendLuck` / `_canPush` 判的是 **bool**（`fumble` / `critical` /
  ///    `passed`），而 state 里存的是 levelKey 字符串；`jsTruthy('fail')` 为真，
  ///    直接把字符串喂进去会把「失败」当成「大失败」。所以这里必须显式翻译。
  Map<String, Object?> checkArgsOf(Map<String, Object?> r) {
    final lk = jsStr(r['level']);
    return <String, Object?>{
      'kind': jsTruthy(r['kind']) ? r['kind'] : 'skill',
      'label': jsStr(r['label']),
      'base': r['base'],
      'target': r['target'],
      'difficulty': jsTruthy(r['difficulty']) ? r['difficulty'] : 'REGULAR',
      'value': r['total'],
      'level': r['level'],
      'passed': !(lk == 'fail' || lk == 'fumble'),
      'fumble': lk == 'fumble',
      'critical': lk == 'critical',
      'critMax': r['critMax'],
      'fumbleMin': r['fumbleMin'],
    };
  }

  /// 成功等级（数字）→ 协议 key（`LEVEL_KEY` 与 `LEVEL` 同构：名字小写）。
  ///
  /// 走注入的端口取 `levelMap`（= `CocRules.LEVEL`），不在这里硬编码第二份常量表。
  String levelKeyOfLevel(int level) {
    for (final e in (rules?.levelMap ?? const <String, int>{}).entries) {
      if (e.value == level) return e.key.toLowerCase();
    }
    return '';
  }

  /// 花幸运把失败的检定压到成功（CoC 7e 规则书 Pg.99）。
  ///
  /// 载荷：`{amount?}`（缺省 = 恰好压到目标值所需的点数）。
  /// 拒绝一律走 `sysTo`（只有本人看得见），**一个字节的状态都不改**。
  List<SendPlan> checkLuck(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final mem = roster.get(seat);
    if (seat == kHostSeat || mem == null) {
      pushInto(out, sysTo(seat, '旁观者不能花幸运点'));
      return out;
    }
    final rulesRef = rules;
    if (rulesRef == null) {
      pushInto(out, sysTo(seat, '规则服务不可用，无法花幸运点'));
      return out;
    }
    final rec = lastDiceOf(seat);
    if (rec == null || !rec.containsKey('target')) {
      pushInto(out, sysTo(seat, '找不到可结算的检定结果（最近一次掷骰不是技能检定）'));
      return out;
    }
    final args = checkArgsOf(rec);
    final total = jsNum(rec['total']);
    final target = jsNum(rec['target']);
    final avail = raMemberStatusValue(mem, 'currentLuck') ?? 0;
    // 恰好压到目标值所需的点数（1 点 = 骰值降 1）；已成功时 ≤ 0 → 兜底 1，
    // 让规则层先跑完它自己的校验（大成功 / 大失败 / 类型不可花）。
    final needRaw = total - target;
    final need = needRaw < 1 ? 1 : needRaw.toInt();
    final askRaw = raFinite(p['amount']);
    final amount = askRaw == null || askRaw < 1 ? need : askRaw.toInt();

    final r = rulesRef.spendLuck(<String, Object?>{
      'result': args,
      'amount': amount,
      'luckAvailable': avail,
    });
    if (!jsTruthy(r['ok'])) {
      pushInto(
        out,
        sysTo(seat, jsTruthy(r['reason']) ? jsStr(r['reason']) : '无法花幸运点'),
      );
      return out;
    }
    // 规则层的 ok 只保证「类型允许 + 不是大成功大失败 + 点数够」，
    // 「已经成功就别再花」这条业务闸门在这里。
    if (jsTruthy(args['passed'])) {
      pushInto(out, sysTo(seat, '检定已经成功，不需要花幸运点'));
      return out;
    }

    final spent = jsNum(r['spent']);
    final after = jsNum(r['after']);
    final afterLevel = jsNum(r['afterLevel']);
    final before = jsNum(r['before']);
    final newLuck = avail - spent < 0 ? 0 : (avail - spent).toInt();
    final nick = raNick(this, mem, seat);

    // ① 扣幸运点：走唯一写口 stateApply（EVT.STATE，SEAT 单发 + 成员表同步）。
    out.addAll(stateApply(
      seat,
      <String, Object?>{
        'status': <String, Object?>{'currentLuck': newLuck},
      },
      const <String, Object?>{},
    ));
    // ② 结果改写：新增一条 EVT.DICE（骰值/等级都是新值，带 luckSpent 溯源）。
    //    ⚠️ 不能就地改 state.dice —— 那会让回退重放还原不出这条修正。
    out.addAll(diceRoll(seat, <String, Object?>{
      'expr': rec['expr'],
      'label': rec['label'],
      'result': <String, Object?>{
        'rolls': rec['rolls'],
        'value': after,
        'level': afterLevel,
        'levelKey': levelKeyOfLevel(afterLevel.toInt()),
        'levelText': jsStr(r['afterLevelText']),
        'detail': '',
        'kind': args['kind'],
        'base': args['base'],
        'target': args['target'],
        'difficulty': args['difficulty'],
        'required': rec['required'],
        'critMax': args['critMax'],
        'fumbleMin': args['fumbleMin'],
        'luckSpent': spent.toInt(),
        'luckFrom': before,
      },
    }));
    // ③ 公共播报：金额 / 原始骰值 / 新骰值 / 新等级，一个都不能少 ——
    //    玩家端只看到两个数字变了会以为「骰子被篡改」。
    final label = cleanText(rec['label'], 20);
    pushInto(
      out,
      sys('$nick 花 $spent 点幸运'
          '${label.isEmpty ? '' : '（$label）'}：'
          '${before.toInt()} → ${after.toInt()}'
          '（${jsStr(r['afterLevelText'])}，剩 $newLuck 点）'),
    );
    return out;
  }

  /// 推动检定：失败后按同一技能值 / 同一难度重掷一次（CoC 7e Pg.85）。
  ///
  /// 规则要点：必须描述新做法、**同一检定不能推动两次**、后果由 KP 加重
  /// （所以这里只标记「推动失败」，**绝不**自动施加任何后果）。
  List<SendPlan> checkRepush(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final mem = roster.get(seat);
    if (seat == kHostSeat || mem == null) {
      pushInto(out, sysTo(seat, '旁观者不能推动检定'));
      return out;
    }
    final rulesRef = rules;
    if (rulesRef == null) {
      pushInto(out, sysTo(seat, '规则服务不可用，无法推动检定'));
      return out;
    }
    final rec = lastDiceOf(seat);
    if (rec == null || !rec.containsKey('target')) {
      pushInto(out, sysTo(seat, '找不到可推动的检定结果（最近一次掷骰不是技能检定）'));
      return out;
    }
    final args = checkArgsOf(rec);
    final verdict = rulesRef.canPush(args, args['kind']);
    if (!jsTruthy(verdict['ok'])) {
      pushInto(
        out,
        sysTo(seat,
            jsTruthy(verdict['reason']) ? jsStr(verdict['reason']) : '该检定不能推动'),
      );
      return out;
    }
    // 「同一检定不能推动两次」：重掷出来的那条带 pushed 标记，
    // 于是它的下一次推动在这里被拒（不带标记的原始记录早已不是最近一条）。
    if (jsTruthy(rec['pushed'])) {
      pushInto(out, sysTo(seat, '这条检定已经推动过了，不能再次推动'));
      return out;
    }
    final base = raFinite(rec['base']);
    if (base == null) {
      pushInto(out, sysTo(seat, '这条检定没有技能值，无法推动'));
      return out;
    }
    final res = rulesRef.check(<String, Object?>{
      ...ruleOptsOf(asMap(state['meta'])),
      'kind': args['kind'],
      'base': raClampNumber(base, 0, 100, 100),
      'difficulty': args['difficulty'],
      'bonus': 0,
      'penalty': 0,
      'label': cleanText(rec['label'], 20),
    });
    final after = jsNum(res['value']);
    final pushedPassed = jsTruthy(res['passed']);
    final label = cleanText(rec['label'], 20);
    final nick = raNick(this, mem, seat);
    out.addAll(diceRoll(seat, <String, Object?>{
      'expr': rec['expr'],
      'label': rec['label'],
      'result': <String, Object?>{
        ...res,
        'pushed': true,
        'pushFrom': rec['total'],
      },
    }));
    pushInto(
      out,
      sys('$nick 推动了${label.isEmpty ? '这项' : '「$label」'}检定：'
          '1D100 → ${after.toInt()}，${jsStr(res['levelText'])}'
          '${pushedPassed ? '' : '（推动失败，后果加重）'}'),
    );
    return out;
  }

  /// 处理完一条请求：从待办表移除 + 给玩家发 REQUEST-done（旧版 :3138-3151）。
  List<SendPlan> settleRequest(
    String seat,
    String id,
    bool agree,
    String? verb,
  ) {
    final out = <SendPlan>[];
    final list = requestsBySeat[seat];
    if (list != null) {
      list.removeWhere((r) => r['id'] == id);
    }
    pending.removeWhere((x) => x['id'] == id);
    pushInto(out, emit(RoomEvt.request, <String, Object?>{
      'self': true,
      'id': id,
      'done': true,
      'at': now(),
    }, vis: RoomVis.seat, to: seat));
    if (verb != null && verb.isNotEmpty) {
      pushInto(out, sys('${raNick(this, roster.get(seat), seat)} $verb'));
    }
    return out;
  }

  /// KP 推送检定请求（旧版 :3190-3240）。
  List<SendPlan> checkRequest(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final skill = cleanText(p['skill'], 20).isNotEmpty
        ? cleanText(p['skill'], 20)
        : '检定';
    final difficulty = p['difficulty'] ?? 'REGULAR';
    final desc = cleanText(p['desc'], 200);
    localSeq += 1;
    final id = 'c$localSeq';
    List<String> targets;
    if (p['seat'] == '*' || !jsTruthy(p['seat'])) {
      targets = roster.onlinePlayers().map((m) => jsStr(m['seat'])).toList();
    } else {
      targets = <String>[jsStr(p['seat'])];
    }
    if (targets.isEmpty) {
      pushInto(out, sysTo(bySeat, '没有在线的玩家可以推送'));
      return out;
    }
    for (final t in targets) {
      final tm = roster.get(t);
      if (raMemberRipped(tm)) {
        pushInto(out, sysTo(bySeat,
            '「${raNick(this, tm, t)}」已撕卡（死亡/永久疯狂），已跳过检定请求'));
        continue;
      }
      final authBase = skillBaseOf(tm, skill, null);
      final rec = <String, Object?>{
        'id': id,
        'from': bySeat,
        'op': 'check.request',
        'payload': <String, Object?>{
          'skill': skill,
          'difficulty': difficulty,
          'desc': desc,
          'base': authBase,
        },
        'reason': desc,
        'at': now(),
      };
      requestsBySeat.putIfAbsent(t, () => <Map<String, Object?>>[]).add(rec);
      pushInto(out, emit(RoomEvt.request, <String, Object?>{
        'self': true,
        'id': id,
        'op': 'check.request',
        'payload': rec['payload'],
        'from': raNick(this, roster.get(bySeat), bySeat),
        'reason': desc,
        'at': rec['at'],
      }, vis: RoomVis.seat, to: t));
    }
    const diffText = <String, String>{
      'REGULAR': '',
      'HARD': '（困难）',
      'EXTREME': '（极难）',
    };
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': bySeat,
      'text': 'KP 要求 ${p['seat'] == '*' || !jsTruthy(p['seat']) ? '全体玩家' : raNick(this, roster.get(jsStr(p['seat'])), jsStr(p['seat']))}'
          '进行「$skill」检定${diffText[difficulty] ?? ''}',
      'at': now(),
      'kind': 'check-req',
    }, vis: RoomVis.public));
    pushInto(out, sysTo(bySeat, '已推送检定请求'));
    return out;
  }

  // ==========================================================
  // 对抗检定
  // ==========================================================

  /// 发布一条「对抗检定结果」（秘密走 PRIVATE 单发；旧版 :5811-5824）。
  void emitOpposedCheck(
    List<SendPlan> out,
    Map<String, Object?> payload,
    bool secret,
  ) {
    if (secret) {
      // 老 APP `:5814-5818` 用 `payload.summary || '…'` / `payload.at || now()`
      // （JS falsy 口径：空串 / 0 也走兜底）；Dart 的 `??` 只接 null。
      // 这里显式换成 jsTruthy，避免「summary 是空串」时发出一条空白私密卡。
      final text = jsTruthy(payload['summary'])
          ? jsStr(payload['summary'])
          : '（秘密对抗）';
      final at = jsTruthy(payload['at']) ? payload['at'] : now();
      pushInto(out, emit(RoomEvt.private_, <String, Object?>{
        'title': '秘密对抗',
        'kind': 'opposed',
        'text': text,
        'at': at,
      }, vis: RoomVis.seat, to: kHostSeat));
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': 'KP 秘密进行了一次对抗检定',
        'at': at,
        'kind': 'check',
      }, vis: RoomVis.public));
    } else {
      pushInto(out, emit(RoomEvt.check, payload, vis: RoomVis.public));
    }
  }

  /// 对抗裁定失败统一收尾（旧版 :5922-5930）。
  void opposedFail(
    List<SendPlan> out,
    String bySeat,
    String toSeat,
    String reason,
  ) {
    final txt = cleanText(reason, 200).isNotEmpty
        ? cleanText(reason, 200)
        : '对抗裁定失败';
    pushInto(out, sysTo(bySeat, txt));
    if (toSeat.isNotEmpty && toSeat != bySeat) {
      pushInto(out, sysTo(toSeat, txt));
    }
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': '$kRaOpposedPrefix（未结算）$txt',
      'at': now(),
      'kind': 'check',
    }, vis: RoomVis.public));
  }

  /// 解析对抗的一方（玩家走权威人物卡，怪物走 KP 手输值；旧版 :5956-5992）。
  Map<String, Object?> resolveOpposedSide(
    Object? specRaw,
    Map<String, Object?> opts,
  ) {
    final spec = asMap(specRaw);
    String side = '';
    if (spec['side'] == 'pc') {
      side = 'pc';
    } else if (spec['side'] == 'monster' || spec['side'] == 'npc') {
      side = 'monster';
    }
    if (side.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'reason': '未指定对抗方类型（玩家 / 怪物）',
      };
    }
    final skill = cleanText(spec['skill'], 30).isNotEmpty
        ? cleanText(spec['skill'], 30)
        : jsStr(opts['defaultSkill'] ?? '');
    final name = cleanText(spec['name'], 40).isNotEmpty
        ? cleanText(spec['name'], 40)
        : jsStr(opts['defaultName'] ?? '单位');
    if (side == 'pc') {
      final seat = cleanText(spec['seat'], 64);
      final mem = seat.isNotEmpty ? roster.get(seat) : null;
      if (mem == null) {
        return <String, Object?>{
          'ok': false,
          'reason': '找不到玩家「${name.isEmpty ? seat : name}」',
        };
      }
      if (raMemberRipped(mem)) {
        return <String, Object?>{
          'ok': false,
          'reason': '目标「${raNick(this, mem, seat)}」已撕卡（死亡/永久疯狂）',
        };
      }
      if (mem['online'] == false) {
        return <String, Object?>{
          'ok': false,
          'reason': '目标「${raNick(this, mem, seat)}」已离线',
        };
      }
      if (skill.isEmpty) {
        return <String, Object?>{
          'ok': false,
          'reason': '请指定该玩家要对抗的技能/属性',
        };
      }
      final v = skillBaseOf(mem, skill, null);
      if (v == null) {
        return <String, Object?>{
          'ok': false,
          'reason': '在「${raNick(this, mem, seat)}」人物卡里查不到「$skill」——请核对技能名，或改用 KP 手输值',
        };
      }
      return <String, Object?>{
        'ok': true,
        'side': 'pc',
        'seat': seat,
        'name': raNick(this, mem, seat),
        'skill': skill,
        'value': v,
        'reaction': spec['reaction'] ?? '',
        'ranged': jsTruthy(spec['ranged']),
      };
    }
    final hv = raFinite(spec['value']);
    if (hv == null || !(hv >= 1 && hv <= 100) || hv != hv.roundToDouble()) {
      return <String, Object?>{
        'ok': false,
        'reason': '「$name」的对抗值需为 1–100 的整数（怪物无人物卡，请 KP 手输）',
      };
    }
    var actorId = cleanText(spec['actorId'], 64);
    if (actorId.isEmpty && name.isNotEmpty) {
      final byName = findCombatSlotByName(name);
      if (byName != null) actorId = jsStr(byName['actorId'] ?? byName['id']);
    }
    return <String, Object?>{
      'ok': true,
      'side': 'monster',
      'seat': '',
      'actorId': actorId,
      'name': name,
      'skill': skill.isNotEmpty ? skill : '对抗',
      'value': hv,
      'reaction': spec['reaction'] ?? '',
      'ranged': jsTruthy(spec['ranged']),
    };
  }

  /// P17 波3-B / KP-3：把「KP 判定的防守方检定等级」折成权威检定能吃的
  /// `{base, roll}` —— 不是新规则，而是**借 `CocRules.check` 的同一套阈值**
  /// （`_thresholds` / `_isFumble` / `_levelOf`，`room_rules_core.dart:54-131`）
  /// 反解出一组代表值：`_levelOf(roll, base) == 声明的 level`。
  ///
  /// 为什么必须这样做：`room_rules_combat.dart` 的结算器只收 `defense.value`
  /// （1–100 技能值）＋ 掷骰，**没有「直接给等级」的入口**；而该文件的计算式
  /// 是 P17 红线（只读）。所以 domain 侧不复制任何判定式，只把等级翻译成
  /// 一个等价输入，后续命中 / 反击 / 闪避 / 护甲 / 伤害全部仍由
  /// `rules.resolveAttack` 跑。
  ///
  /// 代表值选取（逐条对齐 `_levelOf` 的实际判定顺序）：
  ///   · 基准 100 → regular 100 / hard 50 / extreme 20 / 大成功 1，且 100 才是大失败；
  ///   · 基准 1   → 目标 < 50 时大失败区间 96-100，2..95 一律「失败」。
  /// 结果只用于喂规则，**不进展示**（载荷里会带 `declaredLevel` 让 UI 显示
  /// 「KP 判定」而不是假骰值）。
  Map<String, Object?> opposedDeclaredLevelSpec(Object? levelRaw) {
    final lvl = raFinite(levelRaw);
    if (lvl == null) {
      return <String, Object?>{'ok': false, 'reason': '未给出防守方检定等级'};
    }
    final l = lvl.toInt();
    final lv = lvl == l.toDouble() ? l : -999;
    switch (lv) {
      case 5: // 大成功
        return <String, Object?>{
          'ok': true,
          'level': 5,
          'base': 100,
          'roll': 1,
        };
      case 4: // 极难成功
        return <String, Object?>{
          'ok': true,
          'level': 4,
          'base': 100,
          'roll': 20,
        };
      case 3: // 困难成功
        return <String, Object?>{
          'ok': true,
          'level': 3,
          'base': 100,
          'roll': 50,
        };
      case 2: // 常规成功
        return <String, Object?>{
          'ok': true,
          'level': 2,
          'base': 100,
          'roll': 51,
        };
      case 0: // 失败
        return <String, Object?>{
          'ok': true,
          'level': 0,
          'base': 1,
          'roll': 2,
        };
      case -1: // 大失败
        return <String, Object?>{
          'ok': true,
          'level': -1,
          'base': 1,
          'roll': 96,
        };
    }
    return <String, Object?>{
      'ok': false,
      'reason': '检定等级只能是 大成功 / 极难成功 / 困难成功 / 常规成功 / 失败 / 大失败',
    };
  }

  /// PV-1b：玩家主动对抗「KP 同意后系统自动检定」。
  ///
  /// **内部私有方法**，不是新 action / 事件 / 意图：由 [checkOpposed] 在
  /// `p['auto'] == true` 时短路调用。载荷冻结为
  /// `{op:'check.opposed', auto:true, skill, targetSeat, by}`（契约 I5）。
  /// 技能值一律由权威端从角色卡 [skillBaseOf] 读取（用户拍板 D6），
  /// 不采信客户端回传值；`rules.check` 自动掷一次 D100，产出**一条**
  /// PUBLIC `kind:'check'` 记录。守方（怪物）数值沿用 KP-4 的
  /// `defender.value` 口径：仅当载荷可选地带合法 1–100 整数时展示。
  List<SendPlan> _autoOpposedCheck(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final seat = jsTruthy(p['by']) ? jsStr(p['by']) : bySeat;
    final mem = roster.get(seat);
    final nick = raNick(this, mem, seat);
    final skill = cleanText(p['skill'], 30).isNotEmpty
        ? cleanText(p['skill'], 30)
        : '对抗';
    final num base = skillBaseOf(mem, skill, null) ?? 50;
    final chk = rules?.check(<String, Object?>{
      ...ruleOptsOf(asMap(state['meta'])),
      'base': base,
      'difficulty': 'REGULAR',
      'kind': 'skill',
      'label': skill,
      'rng': rng,
    }) ??
        <String, Object?>{
          'value': 1 + (rng() * 100).floor(),
          'level': 0,
          'levelText': '',
          'base': base,
        };
    final level = raNum(chk['level'], 0);
    final levelMap = rules?.levelMap ?? <String, int>{};
    final lvlWord = level == levelMap['CRITICAL']
        ? '大成功'
        : (level == levelMap['FUMBLE']
            ? '大失败'
            : (level >= 2 ? '成功' : '失败'));

    final targetSeat = cleanText(p['targetSeat'], 64);
    var targetName = '全体';
    if (targetSeat.isNotEmpty && targetSeat != '*') {
      final tm = roster.get(targetSeat);
      final slot = findCombatSlot(targetSeat);
      final slotName = slot == null ? '' : cleanText(slot['name'], 40);
      targetName = tm != null
          ? raNick(this, tm, targetSeat)
          : (slotName.isNotEmpty ? slotName : targetSeat);
    }

    // 守方数值：沿用 KP-4「defender.value 为 1–100 整数」的判定口径。
    final defSpec = asMap(p['defender']);
    final defVal = raFinite(defSpec['value']);
    final bool defValid = defVal != null &&
        defVal >= 1 &&
        defVal <= 100 &&
        defVal == defVal.roundToDouble();
    final String defText = defValid
        ? '（守方对抗值 ${raNum(defVal, 0).toInt()}）'
        : '';

    // ★ Q-B（用户拍板 · v1.1 §1.4）：只有「守方是怪物 / NPC 且补值合法」
    //   才做真胜负判定。守方未补值 / 值非法 / side=='pc' 一律走既有单方
    //   检定分支：不额外消耗 rng、不产出胜负结论（既有 oracle 零漂移）。
    final bool opposed = defValid && jsStr(defSpec['side']) != 'pc';
    String verdictText = '';
    if (opposed) {
      final num defBase = defVal!;
      // 与玩家同口径再跑一次 rules.check（同难度 / 同类型 / 同 rng 源）。
      final defChk = rules?.check(<String, Object?>{
            ...ruleOptsOf(asMap(state['meta'])),
            'base': defBase,
            'difficulty': 'REGULAR',
            'kind': 'skill',
            'label': skill,
            'rng': rng,
          }) ??
          <String, Object?>{
            'value': 1 + (rng() * 100).floor(),
            'level': 0,
            'levelText': '',
            'base': defBase,
          };
      final num defLevel = raNum(defChk['level'], 0);
      final num myRoll = raNum(chk['value'], 0);
      final num defRoll = raNum(defChk['value'], 0);
      final String winner;
      if (level > defLevel) {
        winner = '$nick 胜';
      } else if (level < defLevel) {
        winner = '守方胜';
      } else if (myRoll < defRoll) {
        // COC 同成功等级时掷骰值更低者胜（越接近 1 越好）。
        winner = '$nick 胜';
      } else if (myRoll > defRoll) {
        winner = '守方胜';
      } else {
        winner = '平局';
      }
      verdictText = ' → 对抗结果：$winner'
          '（成功等级 ${level.toInt()} : ${defLevel.toInt()}，'
          '掷 ${jsStr(chk['value'] ?? '')} : ${jsStr(defChk['value'] ?? '')}）';
    }

    // ★ 仍只 emit 这一条 PUBLIC kind:'check' log，两端 reduce 出同一条记录；
    //   不新增 RoomEvt 成员、不额外发包。
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': seat,
      'text': '玩家主动对抗「$skill」→「$targetName」$defText：'
          '$nick $lvlWord（掷 ${jsStr(chk['value'] ?? '')}，技能值 ${base.toInt()}）'
          '$verdictText',
      'at': now(),
      'kind': 'check',
    }, vis: RoomVis.public));
    return out;
  }

  /// 对抗检定（通用分支 + 攻击对抗 / 拒绝申请；旧版 :5830-5899）。
  List<SendPlan> checkOpposed(String bySeat, Map<String, Object?> p) {
    // ★ PV-1b：玩家主动对抗经「RoomConfirm.kp + pending」审批链路，
    //   KP 同意后 confirmPending → applyAction → 这里。技能值由权威端
    //   从角色卡读取并自动掷骰。下方非 auto 分支逐字未动。
    if (p['auto'] == true) {
      // ★ P13 COMBAT-3：玩家攻击对抗同样经「act + RoomConfirm.kp + pending」
      //   审批链路（`auto:true` 让 watcher 在 KP 同意后弹补值窗、`confirmPending`
      //   把 1–100 检定值合并进 defender.value）。与 PV-1b 单方检定的唯一区别是
      //   载荷带 `attack:true` —— 此时改走既有 [opposedAttackResolve] 做严格
      //   COC7th 结算（贯穿 / 大成功 / 护甲 / 重掷均由 room_rules_combat.dart
      //   的 `_resolveAttack` 负责），并把伤害应用到怪物状态、PUBLIC 广播。
      //   PV-1b 既有载荷无 `attack` 键 → 逐字维持 `_autoOpposedCheck`，零回归。
      //   仅在既有 check.opposed 处理器内分流：不新增 action / 事件 / 意图，
      //   契约 62/28/13 不变，规则函数与 rng 消耗顺序零改动。
      if (jsTruthy(p['attack'])) {
        return opposedAttackResolve(bySeat, p);
      }
      return _autoOpposedCheck(bySeat, p);
    }
    final out = <SendPlan>[];
    if (rules == null) {
      pushInto(out, sysTo(bySeat, '规则服务不可用，无法进行对抗检定'));
      return out;
    }
    if (jsTruthy(p['attack']) || jsTruthy(p['cancel'])) {
      return opposedAttackResolve(bySeat, p);
    }
    final aBase = raNormBase(p['aBase']);
    final bBase = raNormBase(p['bBase']);
    final a = resolveActorSkill(p['aSeat'], p['aSkill'], aBase);
    final b = resolveActorSkill(p['bSeat'], p['bSkill'], bBase);
    if (a['ok'] == false) {
      pushInto(out, sysTo(bySeat, '甲方无效：${jsStr(a['reason'] ?? '无法解析')}'));
      return out;
    }
    if (b['ok'] == false) {
      pushInto(out, sysTo(bySeat, '乙方无效：${jsStr(b['reason'] ?? '无法解析')}'));
      return out;
    }
    final diff = p['difficulty'] ?? 'REGULAR';
    final ro = ruleOptsOf(asMap(state['meta']));
    final aRes = rules!.check(<String, Object?>{
      ...ro,
      'kind': 'opposed',
      'base': a['value'],
      'difficulty': diff,
      'bonus': raNum(p['aBonus'], 0),
      'penalty': raNum(p['aPenalty'], 0),
      'label': a['name'],
    });
    final bRes = rules!.check(<String, Object?>{
      ...ro,
      'kind': 'opposed',
      'base': b['value'],
      'difficulty': diff,
      'bonus': raNum(p['bBonus'], 0),
      'penalty': raNum(p['bPenalty'], 0),
      'label': b['name'],
    });
    final verdict = rules!.opposedFull(aRes, bRes,
        <String, Object?>{'rng': p['rng'] ?? rng});
    final rounds = asList(verdict['rounds']);
    String summary;
    if (jsTruthy(verdict['winner'])) {
      final winner = verdict['winner'] == 'a' ? jsStr(a['name']) : jsStr(b['name']);
      summary = '$kRaOpposedPrefix${jsStr(a['name'])}（${jsStr(aRes['levelText'])}，'
          '掷 ${jsStr(aRes['value'])}） vs ${jsStr(b['name'])}'
          '（${jsStr(bRes['levelText'])}，掷 ${jsStr(bRes['value'])}） → '
          '$winner 胜（${jsStr(verdict['reason'])}）'
          '${raBuildOpposedRerollLines(rounds, jsStr(a['name']), jsStr(b['name']), verdict['fallback'] == true)}';
    } else {
      summary = '$kRaOpposedPrefix${jsStr(a['name'])} vs ${jsStr(b['name'])}（未能裁定）';
    }
    localSeq += 1;
    final payload = <String, Object?>{
      'id': 'o$localSeq',
      'kind': 'opposed',
      'targets': <Object?>[p['aSeat'], p['bSeat']]
          // 老 APP `:5888` 是 `.filter(Boolean)`：空串 / 0 / false 一并滤掉。
          // 改前这里只滤 null，空串会留在 targets 里（形状差异）。
          .where(jsTruthy)
          .toList(),
      'skill': '${jsStr(a['name'])} vs ${jsStr(b['name'])}',
      'difficulty': diff,
      'a': <String, Object?>{
        'ref': p['aSeat'] ?? '',
        'name': a['name'],
        'value': aRes['value'],
        'level': aRes['level'],
        'levelText': aRes['levelText'],
      },
      'b': <String, Object?>{
        'ref': p['bSeat'] ?? '',
        'name': b['name'],
        'value': bRes['value'],
        'level': bRes['level'],
        'levelText': bRes['levelText'],
      },
      'winner': verdict['winner'],
      'tie': verdict['tie'] == true,
      'reaction': '',
      'decidedBy': verdict['decidedBy'] ?? '',
      'rounds': rounds,
      'fallback': verdict['fallback'] == true,
      'damage': null,
      'summary': summary,
      'at': now(),
    };
    emitOpposedCheck(out, payload, jsTruthy(p['secret']));
    pushInto(out, sysTo(bySeat, '已发起对抗检定'));
    return out;
  }

  /// 解析「对抗检定的一方」（座位或战斗单位 id；旧版 :3811-3874）。
  Map<String, Object?> resolveActorSkill(
    Object? ref,
    Object? skillName,
    Object? fallback,
  ) {
    final name = cleanText(skillName, 30).isNotEmpty
        ? cleanText(skillName, 30)
        : '技能';
    var raw = cleanText(ref, 64);
    if (raw.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'name': '未知单位·$name',
        'reason': '未指定对抗单位',
      };
    }
    var hint = '';
    if (raw.startsWith('p:')) {
      hint = 'pc';
      raw = raw.substring(2);
    } else if (raw.startsWith('a:')) {
      hint = 'actor';
      raw = raw.substring(2);
    } else if (raw.startsWith('mo:')) {
      hint = 'actor';
      raw = raw.substring(3);
    }
    if (hint != 'actor') {
      final m = roster.get(raw);
      if (m != null) {
        if (raMemberRipped(m)) {
          return <String, Object?>{
            'ok': false,
            'name': '${raUnitName(this, m, raw)}·$name',
            'reason': '目标「${raNick(this, m, raw)}」已撕卡（死亡/永久疯狂）',
          };
        }
        final v = skillBaseOf(m, name, fallback);
        return <String, Object?>{
          'ok': true,
          'name': '${raUnitName(this, m, raw)}·$name',
          'value': raNum(v, raNum(fallback, 0)),
        };
      }
    }
    if (hint != 'pc') {
      final slot = findActorSlot(raw);
      if (slot != null) {
        var val = asMap(slot['skills'])[name];
        val ??= asMap(asMap(slot['stats'])['skills'])[name];
        val ??= slot[name];
        final fv = raFinite(fallback);
        if (val == null || raFinite(val) == null) {
          if (fv != null &&
              !(fv >= 1 && fv <= 100 && fv == fv.roundToDouble())) {
            return <String, Object?>{
              'ok': false,
              'name': '${cleanText(slot['name'], 40).isNotEmpty ? cleanText(slot['name'], 40) : '未知单位'}·$name',
              'reason': '「${cleanText(slot['name'], 40).isNotEmpty ? cleanText(slot['name'], 40) : '未知单位'}」的对抗值需为 1–100 的整数（怪物无人物卡，请 KP 手输）',
            };
          }
          if (fv != null && fv >= 1 && fv <= 100 && fv == fv.roundToDouble()) {
            return <String, Object?>{
              'ok': true,
              'name': '${cleanText(slot['name'], 40).isNotEmpty ? cleanText(slot['name'], 40) : '未知单位'}·$name',
              'value': fv,
            };
          }
        }
        return <String, Object?>{
          'ok': true,
          'name': '${cleanText(slot['name'], 40).isNotEmpty ? cleanText(slot['name'], 40) : '未知单位'}·$name',
          'value': raNum(val, raNum(fallback, 0)),
        };
      }
    }
    return <String, Object?>{
      'ok': false,
      'name': '未知单位·$name',
      'reason': '找不到对抗单位「$raw」（不在成员表也不在战斗列表）',
    };
  }

  /// 按 id 定位战斗单位 / 候选池单位（旧版 :3883-3905）。
  Map<String, Object?>? findActorSlot(Object? rawId) {
    final q = cleanText(rawId, 64);
    if (q.isEmpty) return null;
    if (state['combat'] is Map) {
      for (final sRaw in asList(asMap(state['combat'])['order'])) {
        final s = asMap(sRaw);
        if (s.isEmpty) continue;
        if (s['actorId'] == q || s['id'] == q || s['uid'] == q) return s;
      }
    }
    for (final a in localActors) {
      if (a.isEmpty) continue;
      if (a['id'] == q || a['actorId'] == q || a['uid'] == q) {
        return <String, Object?>{
          'actorId': a['id'],
          'id': a['id'],
          'name': a['name'],
          'kind': a['kind'],
          'skills': null,
        };
      }
    }
    return null;
  }

  /// 权威取值：优先角色卡技能/属性，回落 fallback（旧版 :3782-3798）。
  num? skillBaseOf(Map<String, Object?>? mem, Object? name, Object? fallback) {
    final sheet = mem?['sheet'];
    final nm = cleanText(name, 40);
    if (sheet is Map && nm.isNotEmpty && rules != null) {
      final v = rules!.skillValue(sheet, nm);
      if (v != null) return v.toDouble();
      final a = rules!.attrValue(sheet, nm);
      if (a != null) return a.toDouble();
    }
    if (fallback == null) return null;
    return raNum(fallback, 0);
  }

  /// 找到战斗槽（按 actorId 或槽 id；旧版 :6365-6372）。
  Map<String, Object?>? findCombatSlot(Object? id) {
    if (state['combat'] is! Map || !jsTruthy(id)) return null;
    for (final sRaw in asList(asMap(state['combat'])['order'])) {
      final s = asMap(sRaw);
      if (s['actorId'] == id || s['id'] == id) return s;
    }
    return null;
  }

  /// 按名字找战斗槽（旧版 :6375-6383）。
  Map<String, Object?>? findCombatSlotByName(Object? name) {
    final q = cleanText(name, 40);
    if (q.isEmpty || state['combat'] is! Map) return null;
    for (final sRaw in asList(asMap(state['combat'])['order'])) {
      if (cleanText(asMap(sRaw)['name'], 40) == q) return asMap(sRaw);
    }
    return null;
  }

  /// 存活怪物清单（旧版 :6386-6396）。
  List<Map<String, Object?>> aliveMonsters() {
    final out = <Map<String, Object?>>[];
    if (state['combat'] is! Map) return out;
    for (final sRaw in asList(asMap(state['combat'])['order'])) {
      final s = asMap(sRaw);
      if (s.isEmpty || s['kind'] != 'monster') continue;
      final pub = asMap(s['public']);
      if (jsTruthy(pub['down']) || pub['state'] == 'dead') continue;
      final hp = pub['hp'];
      if (hp != null && raNum(hp, 1) <= 0) continue;
      out.add(s);
    }
    return out;
  }

  /// 在人物卡武器清单里按名匹配（旧版 :6399-6405）。
  Map<String, Object?>? matchSheetWeapon(Map<String, Object?>? mem, Object? name) {
    final list = mem != null && mem['sheet'] is Map
        ? asList(asMap(mem['sheet'])['weapons'])
        : <Object?>[];
    final q = cleanText(name, 40);
    if (q.isEmpty) return list.isEmpty ? null : asMap(list.first);
    for (final wRaw in list) {
      if (cleanText(asMap(wRaw)['name'], 40) == q) return asMap(wRaw);
    }
    return null;
  }

  /// 当前是否该玩家的行动轮次（旧版 :6484-6491）。
  bool isMyActionTurn(String seat) {
    if (state['combat'] is! Map) return true;
    final c = asMap(state['combat']);
    final order = asList(c['order']);
    if (order.isEmpty) return true;
    final turn = raNum(c['turn'], 0).toInt();
    if (turn < 0 || turn >= order.length) return false;
    final cur = asMap(order[turn]);
    if (cur['kind'] != 'pc') return false;
    return jsTruthy(cur['seat']) && cur['seat'] == seat;
  }

  /// 对玩家造成伤害（反击 / 武器命中；旧版 :6412-6442）。
  List<SendPlan> opposedDamagePlayer(String seat, num amount, String reason) {
    final out = <SendPlan>[];
    if (!(amount > 0)) return out;
    final m = roster.get(seat);
    if (m == null) return out;
    out.addAll(applyHpChange(m, -amount,
        reason.isNotEmpty ? reason : '对抗伤害', <String, Object?>{}));
    if (state['combat'] is Map) {
      final c = asMap(state['combat']);
      final order = asList(c['order']);
      var synced = false;
      final hpNow = raMemberStatusValue(m, 'currentHP');
      for (var i = 0; i < order.length; i++) {
        final slot = asMap(order[i]);
        if (slot['kind'] != 'pc') continue;
        if (slot['seat'] != seat && slot['actorId'] != seat) continue;
        if (slot['public'] is! Map) {
          slot['public'] = <String, Object?>{};
        }
        final pub = asMap(slot['public']);
        if (raFinite(pub['hp']) == null) {
          pub['hp'] = raNum(pub['hpMax'], hpNow ?? 0);
        }
        if (hpNow != null) pub['hp'] = hpNow > 0 ? hpNow : 0;
        order[i] = slot;
        pushInto(out, emit(RoomEvt.actor, <String, Object?>{
          'actor': roomClone(slot),
        }, vis: RoomVis.public));
        synced = true;
      }
      if (synced) {
        out.addAll(syncBodyToCombatSlot(m));
        pushInto(out, emit(RoomEvt.turnstate, <String, Object?>{
          'turn': c['turn'],
          'round': c['round'],
          'order': order,
        }, vis: RoomVis.public));
      }
    }
    return out;
  }

  /// 对怪物造成伤害（旧版 :6449-6465）。
  List<SendPlan> opposedDamageMonster(Object? actorId, num amount) {
    final out = <SendPlan>[];
    if (!(amount > 0)) return out;
    final slot = findCombatSlot(actorId);
    if (slot == null) {
      pushInto(out, sysTo(kHostSeat,
          '对抗伤害：找不到目标战斗单位「${cleanText(actorId, 40).isNotEmpty ? cleanText(actorId, 40) : '（未指定）'}」，怪物未扣血 —— 请在战斗列表核对目标'));
      return out;
    }
    if (slot['public'] is! Map) slot['public'] = <String, Object?>{};
    final pub = asMap(slot['public']);
    if (raFinite(pub['hp']) == null) pub['hp'] = raNum(pub['hpMax'], 0);
    pub['hp'] = (raNum(pub['hp'], 0) - amount) > 0
        ? raNum(pub['hp'], 0) - amount
        : 0;
    if (raNum(pub['hp'], 0) <= 0) {
      pub['down'] = true;
      pub['state'] = 'dead';
    }
    pushInto(out, emit(RoomEvt.actor, <String, Object?>{
      'actor': roomClone(slot),
    }, vis: RoomVis.public));
    return out;
  }

  /// 「无法反抗」自动命中兜底（旧版 :6276-6305）。
  void forceAutoHit(
    Map<String, Object?> res,
    String expr,
    String db,
    num armorValue,
    bool pierce,
  ) {
    res['noDefense'] = true;
    final alreadyHit = res['outcome'] == 'hit' ||
        res['outcome'] == 'attacker_wins';
    if (!alreadyHit) {
      final attack = asMap(res['attack']);
      final main = rules?.rollExpr(expr, rng);
      if (main != null && main['ok'] == true) {
        final dbRoll = rules?.rollDamageBonus(db, rng) ??
            <String, Object?>{'total': 0};
        var raw = raNum(main['total'], 0) + raNum(dbRoll['total'], 0);
        var impale = false;
        final level = raNum(attack['level'], 0);
        if (pierce && (level == 4 || level == 5) && rules != null) {
          final imp = rules!.impaleDamage(expr, db, rng);
          if (imp['ok'] == true) {
            raw = raNum(imp['raw'], raw);
            impale = true;
          }
        }
        final armorV = armorValue > 0 ? armorValue : 0;
        res['outcome'] = 'attacker_wins';
        res['damage'] = <String, Object?>{
          'raw': raw,
          'expr': expr,
          'dbDice': dbRoll,
          'impale': impale,
          'armor': armorV,
          'applied': (raw - armorV) > 0 ? raw - armorV : 0,
        };
      } else {
        res['outcome'] = 'attacker_wins';
      }
    }
    res['compare'] = <String, Object?>{
      'winner': 'a',
      'decidedBy': 'auto',
      'rounds': <Object?>[],
    };
  }

  /// 组装对抗攻击的 EVT.CHECK 载荷（旧版 :6308-6362）。
  Map<String, Object?> opposedCheckPayload(
    Map<String, Object?> res,
    Map<String, Object?> attacker,
    Map<String, Object?> defender,
    String reaction,
    Map<String, Object?>? dmg,
    String? note,
  ) {
    final cmp = asMap(res['compare']);
    final rounds = asList(cmp['rounds']);
    final aLevelText = jsStr(asMap(res['attack'])['levelText'] ?? '');
    final dLevelText = jsStr(asMap(res['defense'])['levelText'] ?? '');
    final noDefense = jsTruthy(res['noDefense']) ||
        jsTruthy(defender['noDefense']);
    // ★ KP-3：防守方等级由 KP 判定（没有真实掷骰）—— 展示层必须写「KP 判定」，
    //   不能把内部代表骰值当成真骰值播给玩家。
    final declaredLevel = defender['declaredLevel'];
    final declared = declaredLevel != null;
    final reactionText = noDefense
        ? '无法反抗'
        : (reaction == 'counter'
            ? '反击'
            : (reaction == 'dodge' ? '闪避' : '不防御'));
    var s = '$kRaOpposedPrefix${jsStr(attacker['name'])} 发起对抗'
        '（${jsStr(attacker['skill'])} ${jsStr(attacker['value'])}） vs '
        '${jsStr(defender['name'])}（$reactionText'
        '${noDefense || declared ? '' : ' ${jsStr(defender['value'])}'}）';
    s += '\n攻方 $aLevelText（掷 ${jsStr(asMap(res['attack'])['value'] ?? '')}）';
    if (!noDefense) {
      s += declared
          ? ' vs 守方 $dLevelText（KP 判定）'
          : ' vs 守方 $dLevelText（掷 ${jsStr(asMap(res['defense'])['value'] ?? '')}）';
    }
    if (jsTruthy(res['coercedFromFightback'])) {
      s += '\n远程攻击：目标不能反击，按闪避处理';
    }
    final winnerName = cmp['winner'] == 'a'
        ? jsStr(attacker['name'])
        : (cmp['winner'] == 'b' ? jsStr(defender['name']) : '未分');
    if (res['outcome'] == 'miss') {
      s += '\n→ 落空 / 被躲开：未造成伤害';
    } else if (res['outcome'] == 'attacker_wins' ||
        res['outcome'] == 'hit') {
      s += '\n→ $winnerName 胜${noDefense ? '（对方无法反抗，自动命中）' : ''}';
    } else if (res['outcome'] == 'defender_wins') {
      s += '\n→ $winnerName 胜（反击命中）';
    }
    s += raBuildOpposedRerollLines(rounds, jsStr(attacker['name']),
        jsStr(defender['name']), cmp['fallback'] == true);
    if (dmg != null) {
      if (dmg['by'] == 'a') {
        s += '\n命中：伤害 ${jsStr(dmg['expr'] ?? '0')}+${jsStr(dmg['db'] ?? '0')}'
            '=${jsStr(dmg['raw'])}，护甲 ${jsStr(dmg['armor'])}，'
            '实扣 ${jsStr(dmg['applied'])}'
            '${dmg['impale'] == true ? '（贯穿：取最大值并追加伤害骰）' : ''}';
      } else {
        s += '\n反击命中：由 ${jsStr(defender['name'])} 造成 '
            '${jsStr(dmg['applied'])} 点伤害（伤害骰 ${jsStr(dmg['raw'])}，'
            '护甲 ${jsStr(dmg['armor'])}）';
      }
    }
    if (note != null && note.isNotEmpty) s += '\n（$note）';
    localSeq += 1;
    return <String, Object?>{
      'id': 'o$localSeq',
      'kind': 'opposed',
      'targets': <Object?>[attacker['seat'], defender['seat']]
          .where((x) => x != null && x != '')
          .toList(),
      'skill': '${jsStr(attacker['skill'])} vs ${jsStr(defender['skill'])}',
      'difficulty': asMap(res['attack'])['difficulty'] ?? 'REGULAR',
      'a': <String, Object?>{
        'ref': attacker['seat'] ?? attacker['actorId'] ?? '',
        'name': attacker['name'],
        'value': asMap(res['attack'])['value'] ?? attacker['value'],
        'level': asMap(res['attack'])['level'],
        'levelText': aLevelText,
      },
      'b': <String, Object?>{
        'ref': defender['seat'] ?? defender['actorId'] ?? '',
        'name': defender['name'],
        // KP 判定等级时没有真实骰值 → null（另给 declaredLevel 供 UI 显示）。
        'value': declared
            ? null
            : (asMap(res['defense'])['value'] ?? defender['value']),
        'level': asMap(res['defense'])['level'],
        'levelText': dLevelText,
        if (declared) 'declaredLevel': declaredLevel,
      },
      'winner': cmp['winner'],
      'tie': false,
      'reaction': reaction,
      'decidedBy': cmp['decidedBy'] ?? '',
      'rounds': rounds,
      'fallback': cmp['fallback'] == true,
      'damage': dmg,
      'summary': s,
      'at': now(),
    };
  }

  /// 拒绝玩家对抗申请（旧版 :5933-5948）。
  List<SendPlan> opposedReject(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final st = asMap(state['opposed']);
    if (st.isEmpty || (p['reqId'] != null && st['id'] != p['reqId'])) {
      pushInto(out, sysTo(bySeat, '该对抗申请已处理或不存在'));
      return out;
    }
    final toSeat = jsStr(st['by']);
    state['opposed'] = null;
    pushInto(out, emit(RoomEvt.opposed, <String, Object?>{
      'id': st['id'],
      'by': st['by'],
      'phase': 'rejected',
      'targetId': st['targetId'],
      'targetName': st['targetName'],
      'at': now(),
    }, vis: RoomVis.seat, to: toSeat));
    pushInto(out, sysTo(bySeat, '已拒绝该对抗申请'));
    pushInto(out, sysTo(toSeat, '你的对抗申请被 KP 拒绝'));
    return out;
  }

  /// 攻击对抗主结算（KP 直接发起 / 玩家申请裁定；旧版 :5995-6270）。
  List<SendPlan> opposedAttackResolve(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    if (jsTruthy(p['cancel'])) return opposedReject(bySeat, p);
    final fromRequest = jsTruthy(p['reqId']);
    final st = asMap(state['opposed']);
    if (fromRequest && (st.isEmpty || st['id'] != p['reqId'])) {
      pushInto(out, sysTo(bySeat, '该对抗申请已处理或不存在'));
      return out;
    }
    Map<String, Object?> attacker;
    Map<String, Object?> weapon;
    String db;
    if (fromRequest) {
      final am = roster.get(jsStr(st['by']));
      if (am == null) {
        opposedFail(out, bySeat, jsStr(st['by']), '发起者已不在房间，无法结算');
        state['opposed'] = null;
        return out;
      }
      final reqWeapon = asMap(st['weapon']);
      weapon = matchSheetWeapon(am, reqWeapon['name']) ?? reqWeapon;
      db = am['sheet'] is Map
          ? jsStr(asMap(am['sheet'])['db'] ?? '0')
          : jsStr(st['db'] ?? '0');
      final reqSkill = cleanText(reqWeapon['skill'], 30).isNotEmpty
          ? cleanText(reqWeapon['skill'], 30)
          : '格斗';
      final av = cleanText(weapon['skill'], 30).isNotEmpty
          ? cleanText(weapon['skill'], 30)
          : reqSkill;
      final aval = skillBaseOf(am, av, null);
      if (aval == null) {
        opposedFail(out, bySeat, jsStr(st['by']),
            '在发起者人物卡里查不到「$av」，无法结算（请核对武器技能）');
        state['opposed'] = null;
        return out;
      }
      attacker = <String, Object?>{
        'ok': true,
        'side': 'pc',
        'seat': st['by'],
        'name': raNick(this, am, jsStr(st['by'])),
        'skill': av,
        'value': aval,
        'ranged': RegExp(r'射击|枪|弓|投掷|弩').hasMatch(av),
      };
    } else {
      attacker = resolveOpposedSide(p['attacker'], <String, Object?>{
        'defaultName': '攻击方',
        'defaultSkill': '格斗',
      });
      if (attacker['ok'] != true) {
        pushInto(out, sysTo(bySeat, '攻击方无效：${jsStr(attacker['reason'])}'));
        return out;
      }
      weapon = asMap(p['weapon']);
      db = cleanText(weapon['db'], 10).isNotEmpty
          ? cleanText(weapon['db'], 10)
          : (cleanText(p['db'], 10).isNotEmpty
              ? cleanText(p['db'], 10)
              : '0');
    }
    final reaction = raNormReaction(asMap(p['defender'])['reaction']);
    final noDefense = jsTruthy(p['noDefense']);
    // ★ P17 波3-B / KP-3（Q2 拍板）：怪物 / NPC 防守方由 KP 直接判定
    //   **检定等级**，取代原来的 1–100 对抗值输入。只在「防守方不是玩家」
    //   且 `defender.level` 合法时启用；缺键 / 非法值 → 走原路径，行为不变
    //   （向后兼容：老载荷、oracle、既有测试全部不受影响）。
    final declaredSpec = opposedDeclaredLevelSpec(asMap(p['defender'])['level']);
    // ★ KP-4（P0）：怪物 / NPC 防守方「有合法 value 就优先用数值」。
    //   改前只要载荷带合法 level 就恒 declared，`:2246` / `:2302` 会把
    //   declaredSpec['base']（成功四档 100 / 失败档 1）写进 defender.value，
    //   覆盖 UI 手输的技能值。旧载荷（只有 level、无 value）仍走
    //   declared 六档兜底，oracle_* 与既有对抗路径零回归。
    //   ⚠️ opposedDeclaredLevelSpec 函数体、checkOpposed 通用分支、
    //   defSpec['side'] == 'pc' 玩家路径、通用对抗全部逐字不动。
    final defSpec = asMap(p['defender']);
    final v = raFinite(defSpec['value']);
    final hasValue =
        v != null && v >= 1 && v <= 100 && v == v.roundToDouble();
    final declared = !hasValue &&
        declaredSpec['ok'] == true &&
        defSpec['side'] != 'pc';
    Map<String, Object?> defender;
    if (fromRequest) {
      final slot = findCombatSlot(st['targetId']);
      final dname = jsTruthy(st['targetName'])
          ? jsStr(st['targetName'])
          : jsStr(slot?['name'] ?? '目标');
      if (slot == null) {
        opposedFail(out, bySeat, jsStr(st['by']),
            '目标「$dname」不在战斗中，无法结算');
        state['opposed'] = null;
        return out;
      }
      final pub = asMap(slot['public']);
      if (jsTruthy(pub['down']) ||
          pub['state'] == 'dead' ||
          (raFinite(pub['hp']) != null && raNum(pub['hp'], 1) <= 0)) {
        opposedFail(out, bySeat, jsStr(st['by']),
            '目标「$dname」已死亡/离场，无法结算');
        state['opposed'] = null;
        return out;
      }
      if (noDefense) {
        defender = <String, Object?>{
          'ok': true,
          'side': 'monster',
          'actorId': st['targetId'],
          'name': dname,
          'skill': '无法反抗',
          'value': 0,
          'reaction': 'none',
          'noDefense': true,
        };
      } else if (declared) {
        // ★ KP-3：KP 直接判定该怪物的检定等级，不再要求 1–100 对抗值。
        defender = <String, Object?>{
          'ok': true,
          'side': 'monster',
          'actorId': st['targetId'],
          'name': dname,
          'skill': reaction == 'counter' ? '反击' : '闪避',
          'value': declaredSpec['base'],
          'roll': declaredSpec['roll'],
          'declaredLevel': declaredSpec['level'],
          'reaction': reaction,
        };
      } else {
        final dval = raFinite(asMap(p['defender'])['value']);
        if (dval == null || !(dval >= 1 && dval <= 100) ||
            dval != dval.roundToDouble()) {
          pushInto(out, sysTo(bySeat, '请为「$dname」输入 1–100 的对抗值，'
              '或直接选择反击 / 闪避的检定等级'));
          return out;
        }
        defender = <String, Object?>{
          'ok': true,
          'side': 'monster',
          'actorId': st['targetId'],
          'name': dname,
          'skill': reaction == 'counter' ? '反击' : '闪避',
          'value': dval,
          'reaction': reaction,
        };
      }
    } else if (noDefense) {
      final dspec = asMap(p['defender']);
      defender = <String, Object?>{
        'ok': true,
        'side': jsTruthy(dspec['seat']) ? 'pc' : 'monster',
        'seat': cleanText(dspec['seat'], 64),
        'actorId': cleanText(dspec['actorId'], 64),
        'name': cleanText(dspec['name'], 40).isNotEmpty
            ? cleanText(dspec['name'], 40)
            : '防守方',
        'skill': '无法反抗',
        'value': 0,
        'reaction': 'none',
        'noDefense': true,
      };
    } else if (declared) {
      // ★ KP-3：KP 直发攻击对抗时，怪物 / NPC 防守方同样用「检定等级」。
      final dspec = asMap(p['defender']);
      final dname = cleanText(dspec['name'], 40).isNotEmpty
          ? cleanText(dspec['name'], 40)
          : '防守方';
      var actorId = cleanText(dspec['actorId'], 64);
      if (actorId.isEmpty) {
        final byName = findCombatSlotByName(dname);
        if (byName != null) actorId = jsStr(byName['actorId'] ?? byName['id']);
      }
      defender = <String, Object?>{
        'ok': true,
        'side': 'monster',
        'seat': '',
        'actorId': actorId,
        'name': dname,
        'skill': reaction == 'counter' ? '反击' : '闪避',
        'value': declaredSpec['base'],
        'roll': declaredSpec['roll'],
        'declaredLevel': declaredSpec['level'],
        'reaction': reaction,
      };
    } else {
      defender = resolveOpposedSide(p['defender'], <String, Object?>{
        'defaultName': '防守方',
        'defaultSkill': '闪避',
      });
      if (defender['ok'] != true) {
        pushInto(out, sysTo(bySeat, '防守方无效：${jsStr(defender['reason'])}'));
        return out;
      }
      defender['reaction'] = reaction;
    }
    // ★ KP-3：防守方检定等级由 KP 判定时，反击伤害必须由 KP 输入骰式
    //   （老 APP 是复用攻击方武器伤害式；用户口径明确要求「反击 → 输入伤害骰式」）。
    //   校验直接复用 `rules.parseExpr`（支持 2D6+D4+1 这类加减组合，
    //   MAX_DICE=100 / MAX_SIDES=1000 / 常数 ≤10000），本文件不新增解析器。
    //
    //   ★ P20（需求 1）：判据由 `declared && reaction == 'counter'` 放宽为
    //   `reaction == 'counter'`。为什么必须改：玩家攻击链路里 `confirmPending`
    //   会把 KP 补输的 1–100 写进 `defender.value` ⇒ `hasValue == true`
    //   ⇒ `declared == false` ⇒ 整个分支被跳过 ⇒ KP 填的反击伤害式被丢掉
    //   ⇒ 规则层回退成「用攻击方玩家的武器伤害」去打玩家。放宽后这条链路的
    //   伤害式才真正生效；同时也**复活**了 KP 直发攻击对抗的「反击伤害骰式」
    //   （`sheet_opposed.dart` 的 `OpposedSheetKeys.counterDamage`，原先填了没用）。
    //   三种来路分别处理（D2）：
    //     ① 载荷带非空骰式（玩家链路 / KP 直发带伤害式）→ 必须能解析，
    //        非法则报错并不结算；
    //     ② 骰式为空 + `declared`（老 KP 直发「只判等级」链路）→ 老默认 '1D3'；
    //     ③ 骰式为空 + 非 `declared` → 保持 `null` = 旧行为（规则层回退用
    //        攻击方武器伤害式，闪避 / 不防御路径同样不受影响）。
    Map<String, Object?>? counterDmg;
    if (reaction == 'counter') {
      final rawDmg = asMap(p['defender'])['damage'];
      final expr = (rawDmg is Map
              ? cleanText(asMap(rawDmg)['expr'], 40)
              : cleanText(rawDmg, 40))
          .trim();
      // 老 APP 该字段默认 '1D3'，空值沿用同一默认，避免反击变成 0 伤害。
      final useExpr = expr.isNotEmpty ? expr : (declared ? '1D3' : '');
      if (useExpr.isNotEmpty) {
        if (rules == null || rules!.parseExpr(useExpr)['ok'] != true) {
          pushInto(out, sysTo(bySeat,
              '反击伤害骰式无法解析「$useExpr」（支持 2D6+D4+1 这类加减组合）'));
          return out;
        }
        counterDmg = <String, Object?>{'expr': useExpr, 'db': '0'};
      }
    }
    final dmgExpr = raWeaponDamageExpr(weapon['damage'], rules);
    if (dmgExpr['ok'] != true) {
      final dReason = '武器伤害式非法：${jsStr(dmgExpr['reason'])}（请核对武器）';
      if (fromRequest) {
        opposedFail(out, bySeat, jsStr(st['by']), dReason);
        state['opposed'] = null;
      } else {
        pushInto(out, sysTo(bySeat, dReason));
      }
      return out;
    }
    final pierce = cleanText(weapon['pierce'], 4) == '√';
    final armorValue = raNum(asMap(p['armor'])['value'], 0) > 0
        ? raNum(asMap(p['armor'])['value'], 0)
        : 0;
    final perRoundStr = cleanText(weapon['perRound'], 12);
    final burstMax = rules?.burstMaxOf(perRoundStr) ?? 1;
    final shotsReq = fromRequest
        ? raNum(st['shots'], 0)
        : raNum(p['shots'], 0);
    var shots = 1;
    if (burstMax > 1 &&
        shotsReq >= 1 &&
        shotsReq <= burstMax) {
      shots = shotsReq.toInt();
    }
    final wkey = cleanText(weapon['name'], 40).isNotEmpty
        ? cleanText(weapon['name'], 40)
        : '_w';
    final fireKey = '${attacker['seat'] ?? st['by'] ?? ''}\u0000$wkey';
    final priorShots = fromRequest ? (fireUsed[fireKey] ?? 0) : 0;
    final burstPenalty = burstMax > 1
        ? (shots - 1 + priorShots) < kRaModCap
            ? (shots - 1 + priorShots)
            : kRaModCap
        : 0;
    final shotNote = burstMax > 1
        ? '本轮已发射 $priorShots/$burstMax，本次 $shots 发，惩罚骰 +$burstPenalty'
        : '';
    if (fromRequest) fireUsed[fireKey] = priorShots + shots;

    final monsters = aliveMonsters();
    final canDefer = fromRequest && !noDefense && shots == 1 && monsters.length >= 2;
    final seatOfAttacker = jsStr(attacker['seat'] ?? st['by'] ?? '');
    var firedCount = 0;
    var stopReason = '';
    Map<String, Object?>? lastRes;
    var lastAttackerWins = false;
    for (var shotIdx = 1; shotIdx <= shots; shotIdx++) {
      final penaltyThis = burstMax > 1
          ? ((shotIdx - 1 + priorShots) < kRaModCap
              ? (shotIdx - 1 + priorShots)
              : kRaModCap)
          : 0;
      final args = <String, Object?>{
        ...ruleOptsOf(asMap(state['meta'])),
        'attack': <String, Object?>{
          'name': attacker['skill'],
          'value': attacker['value'],
          'ranged': jsTruthy(attacker['ranged']),
        },
        'defense': <String, Object?>{
          'name': defender['skill'],
          'value': defender['value'],
          // ★ KP-3：只有「KP 判定等级」路径才带代表骰值；未声明时为 null，
          //   `_resolveAttack` 的 `_check` 照旧由 rng 掷 D100（行为逐字不变）。
          'roll': defender['roll'],
          'mode': noDefense
              ? 'none'
              : (reaction == 'counter'
                  ? 'fightback'
                  : (reaction == 'dodge' ? 'dodge' : 'none')),
          // 反击伤害式：规则层 `_resolveAttack` 已有「反击优先用防守方伤害式」
          // （`room_rules_combat.dart:223-229`），这里只负责把 KP 输入的骰式送进去。
          'damage': ?counterDmg,
        },
        'damage': <String, Object?>{
          'expr': dmgExpr['expr'],
          'db': db,
        },
        'armor': <String, Object?>{'value': armorValue},
        'impale': pierce,
        'difficulty': p['difficulty'] ?? 'REGULAR',
        'bonus': raNum(p['bonus'], 0),
        'penalty': (raNum(p['penalty'], 0) + penaltyThis) < kRaModCap
            ? (raNum(p['penalty'], 0) + penaltyThis)
            : kRaModCap,
        'secret': jsTruthy(p['secret']),
        'ranged': jsTruthy(attacker['ranged']),
        'rng': p['rng'] ?? rng,
      };
      final res = rules?.resolveAttack(args);
      if (res == null) {
        pushInto(out, sysTo(bySeat, '规则服务无法结算攻击对抗'));
        return out;
      }
      applyMalfunction(out, seatOfAttacker, weapon,
          raNum(asMap(res['attack'])['value'], 0),
          jsTruthy(asMap(res['attack'])['critical']), p['malfType']);
      if (noDefense) {
        forceAutoHit(res, jsStr(dmgExpr['expr']), db, armorValue, pierce);
      }
      firedCount++;
      lastRes = res;
      final outcome = jsStr(res['outcome'] ?? 'miss');
      final attackerWins = outcome == 'hit' || outcome == 'attacker_wins';
      final defenderWins = outcome == 'defender_wins';
      lastAttackerWins = attackerWins;
      Map<String, Object?>? dmg;
      if (attackerWins || defenderWins) {
        final base = asMap(res['damage']);
        final applied = raNum(base['applied'], 0) > 0
            ? raNum(base['applied'], 0)
            : 0;
        dmg = <String, Object?>{
          'expr': base['expr'],
          'db': db,
          'raw': raNum(base['raw'], 0),
          'armor': raNum(base['armor'], armorValue),
          'applied': applied,
          'impale': jsTruthy(base['impale']),
          'by': attackerWins ? 'a' : 'b',
        };
        if (defenderWins) {
          if (attacker['side'] == 'pc' && jsTruthy(attacker['seat'])) {
            out.addAll(opposedDamagePlayer(
                jsStr(attacker['seat']), applied, '对抗反击'));
          } else if (jsTruthy(attacker['actorId'])) {
            out.addAll(opposedDamageMonster(attacker['actorId'], applied));
          }
        } else {
          if (defender['side'] == 'pc' && jsTruthy(defender['seat'])) {
            out.addAll(opposedDamagePlayer(
                jsStr(defender['seat']), applied, '武器对抗'));
          } else if (jsTruthy(defender['actorId'])) {
            out.addAll(opposedDamageMonster(defender['actorId'], applied));
          }
        }
      }
      if (!canDefer || !attackerWins) {
        String? shotNoteThis;
        if (burstMax > 1) {
          shotNoteThis = shotIdx == 1
              ? '$shotNote　·　逐发串行判定：第 1/$shots 发（惩罚骰 +$penaltyThis）'
              : '连发第 $shotIdx/$shots 发（惩罚骰 +$penaltyThis）';
        } else {
          shotNoteThis = shotNote.isNotEmpty ? shotNote : null;
        }
        emitOpposedCheck(
          out,
          opposedCheckPayload(res, attacker, defender, reaction, dmg,
              shotNoteThis),
          jsTruthy(p['secret']),
        );
      }
      if (!attackerWins) {
        stopReason = '第 $shotIdx 发未命中，连发中断';
        break;
      }
      if (dmg == null || raNum(dmg['applied'], 0) <= 0) {
        stopReason = '第 $shotIdx 发未造成伤害，连发中断';
        break;
      }
      if (jsTruthy(defender['actorId'])) {
        final slotNow = findCombatSlot(defender['actorId']);
        final pubNow = asMap(slotNow?['public']);
        if (pubNow.isNotEmpty &&
            (jsTruthy(pubNow['down']) ||
                pubNow['state'] == 'dead' ||
                (raFinite(pubNow['hp']) != null &&
                    raNum(pubNow['hp'], 1) <= 0))) {
          stopReason = '目标已倒下，连发中断';
          break;
        }
      }
    }
    if (fromRequest && burstMax > 1) {
      fireUsed[fireKey] = priorShots + firedCount;
    }
    if (canDefer && lastAttackerWins && lastRes != null) {
      emitOpposedCheck(
        out,
        opposedCheckPayload(lastRes, attacker, defender, reaction, null,
            '待选择伤害目标${shotNote.isNotEmpty ? '　·　$shotNote' : ''}'),
        jsTruthy(p['secret']),
      );
      pushInto(out, emit(RoomEvt.opposed, <String, Object?>{
        'id': st['id'],
        'by': st['by'],
        'phase': 'await_target',
        'targetId': st['targetId'],
        'targetName': st['targetName'],
        'monsters': monsters
            .map((s) => <String, Object?>{
                  'id': s['actorId'] ?? s['id'],
                  'name': s['name'],
                })
            .toList(),
        'at': now(),
      }, vis: RoomVis.seat, to: jsStr(st['by'])));
      state['opposed'] = <String, Object?>{
        ...st,
        'phase': 'await_target',
        'secret': jsTruthy(p['secret']),
        'weapon': weapon,
        'db': db,
        'armor': armorValue,
        'pierce': pierce,
        'dmgExpr': dmgExpr['expr'],
        'monsters': monsters
            .map((s) => <String, Object?>{
                  'id': s['actorId'] ?? s['id'],
                  'name': s['name'],
                })
            .toList(),
        'win': <String, Object?>{
          'a': <String, Object?>{
            'name': attacker['name'],
            'value': asMap(lastRes['attack'])['value'],
            'level': asMap(lastRes['attack'])['level'],
            'levelText': asMap(lastRes['attack'])['levelText'],
          },
          'b': <String, Object?>{
            'name': defender['name'],
            'value': lastRes['defense'] is Map
                ? asMap(lastRes['defense'])['value']
                : defender['value'],
            'level': lastRes['defense'] is Map
                ? asMap(lastRes['defense'])['level']
                : null,
            'levelText': lastRes['defense'] is Map
                ? asMap(lastRes['defense'])['levelText']
                : '',
          },
          'reaction': reaction,
          'decidedBy': asMap(lastRes['compare'])['decidedBy'] ?? '',
          'rounds': asList(asMap(lastRes['compare'])['rounds']),
          'fallback': asMap(lastRes['compare'])['fallback'] == true,
        },
        'at': now(),
      };
      pushInto(out, sysTo(jsStr(st['by']), '对抗胜利！请选择要造成伤害的目标'));
      return out;
    }
    if (stopReason.isNotEmpty && burstMax > 1) {
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'text': '$kRaOpposedPrefix$stopReason（共打出 $firedCount/$shots 发）',
        'at': now(),
      }, vis: RoomVis.public));
    }
    if (fromRequest) state['opposed'] = null;
    return out;
  }

  /// 玩家发起武器对抗（INTENT.OPPOSED；旧版 :6498-6510 / :6512-6596）。
  List<SendPlan> opposed(
    String seat,
    Map<String, Object?>? mem,
    String role,
    Map<String, Object?> p,
  ) {
    final out = <SendPlan>[];
    if (role != RoomRole.player) {
      pushInto(out, sysTo(seat, '只有玩家能发起武器对抗'));
      return out;
    }
    if (mem == null) {
      pushInto(out, sysTo(seat, '找不到你的成员信息'));
      return out;
    }
    if (raMemberRipped(mem) || raMemberInBout(mem)) {
      pushInto(out, sysTo(seat, '你的角色当前无法发起对抗（撕卡 / 疯狂发作中）'));
      return out;
    }
    if (p['phase'] == 'target') return opposedPlayerTarget(seat, mem, p);
    return opposedPlayerRequest(seat, mem, p);
  }

  /// 玩家申请阶段（选武器 + 选目标怪物 → 建待办，通知 KP）。
  List<SendPlan> opposedPlayerRequest(
    String seat,
    Map<String, Object?> mem,
    Map<String, Object?> p,
  ) {
    final out = <SendPlan>[];
    final cur = asMap(state['opposed']);
    if (cur['phase'] == 'await_kp' && cur['by'] == seat) {
      pushInto(out, sysTo(seat, '你已有一条待处理的对抗申请'));
      return out;
    }
    if (!isMyActionTurn(seat)) {
      pushInto(out, sysTo(seat, '只能在你的行动轮次发起战斗对抗'));
      return out;
    }
    final reqWeapon = asMap(p['weapon']);
    final weapon = matchSheetWeapon(mem, reqWeapon['name']);
    if (weapon == null) {
      pushInto(out, sysTo(seat,
          '你的角色卡里没有这把武器「${cleanText(reqWeapon['name'], 40)}」，无法发起对抗'));
      return out;
    }
    if (jsTruthy(weapon['broken'])) {
      pushInto(out, sysTo(seat,
          '「${cleanText(weapon['name'], 40)}」已损坏，不能用于对抗（请先在车卡里更换或修复）'));
      return out;
    }
    final dmgExpr = raWeaponDamageExpr(weapon['damage'], rules);
    if (dmgExpr['ok'] != true) {
      pushInto(out, sysTo(seat, '该武器伤害式非法，无法发起对抗'));
      return out;
    }
    final db = mem['sheet'] is Map
        ? (jsStr(asMap(mem['sheet'])['db'] ?? '0'))
        : (cleanText(p['db'], 10).isNotEmpty ? cleanText(p['db'], 10) : '0');
    final perRound = cleanText(weapon['perRound'], 12);
    final burstMax = rules?.burstMaxOf(perRound) ?? 1;
    var shots = 1;
    if (burstMax == 2) {
      final reqShots = raNum(p['shots'], 0).toInt();
      if (reqShots != 1 && reqShots != 2) {
        pushInto(out, sysTo(seat,
            '该武器每轮最多发射 2 发，发起前请先选择「打 1 发 / 打 2 发」'));
        return out;
      }
      shots = reqShots;
    } else if (burstMax > 2) {
      final rs2 = raNum(p['shots'], 0);
      shots = (rs2 >= 1 && rs2 <= burstMax) ? rs2.toInt() : 1;
    }
    final monsters = aliveMonsters();
    if (monsters.isEmpty) {
      pushInto(out, sysTo(seat,
          '没有可选的怪物（请让 KP 先设置怪物并进入战斗）'));
      return out;
    }
    final tid = cleanText(p['targetId'], 64);
    final slot = findCombatSlot(tid);
    if (slot == null ||
        slot['kind'] != 'monster' ||
        !monsters.any((s) => identical(s, slot) || s['id'] == slot['id'])) {
      pushInto(out, sysTo(seat, '目标怪物不存在或已死亡/离场'));
      return out;
    }
    localSeq += 1;
    final st = <String, Object?>{
      'id': 'op$localSeq',
      'by': seat,
      'byName': raNick(this, mem, seat),
      'phase': 'await_kp',
      'weapon': <String, Object?>{
        'name': weapon['name'],
        'skill': weapon['skill'],
        'damage': weapon['damage'],
        'pierce': weapon['pierce'],
        'perRound': perRound,
        'malfunction': cleanText(weapon['malfunction'], 8),
        'ammo': cleanText(weapon['ammo'], 20),
      },
      'shots': shots,
      'burstMax': burstMax,
      'db': db,
      'targetId': slot['actorId'] ?? slot['id'],
      'targetName': slot['name'] ?? '怪物',
      'note': cleanText(p['note'], 80),
      'at': now(),
    };
    state['opposed'] = st;
    pushInto(out, emit(RoomEvt.opposed, <String, Object?>{
      'id': st['id'],
      'by': seat,
      'byName': st['byName'],
      'phase': 'await_kp',
      'weapon': st['weapon'],
      'db': st['db'],
      'shots': st['shots'],
      'burstMax': st['burstMax'],
      'targetId': st['targetId'],
      'targetName': st['targetName'],
      'note': st['note'],
      'at': st['at'],
    }, vis: RoomVis.seat, to: kHostSeat));
    var fireInfo = '';
    if (burstMax > 1) {
      final prior = fireUsed['$seat\u0000${cleanText(weapon['name'], 40)}'] ?? 0;
      final pen = (shots - 1 + prior) < kRaModCap
          ? (shots - 1 + prior)
          : kRaModCap;
      fireInfo = '（本轮已发射 $prior/$burstMax，本次 $shots 发，惩罚骰 +$pen）';
    }
    pushInto(out, sysTo(seat, '已发送对抗申请，等待 KP 处理$fireInfo'));
    return out;
  }

  /// 玩家胜后选怪 → 结算武器伤害（旧版 :6599-6657）。
  List<SendPlan> opposedPlayerTarget(
    String seat,
    Map<String, Object?> mem,
    Map<String, Object?> p,
  ) {
    final out = <SendPlan>[];
    final st = asMap(state['opposed']);
    if (st.isEmpty || st['phase'] != 'await_target' || st['by'] != seat) {
      pushInto(out, sysTo(seat, '当前没有待选择的对抗目标'));
      return out;
    }
    final tid = cleanText(p['targetId'], 64);
    final slot = findCombatSlot(tid);
    final monsters = aliveMonsters();
    if (slot == null ||
        slot['kind'] != 'monster' ||
        !monsters.any((s) => s['id'] == slot['id'])) {
      pushInto(out, sysTo(seat, '所选目标不存在或已死亡/离场'));
      return out;
    }
    var expr = jsStr(st['dmgExpr']);
    if (expr.isEmpty) {
      expr = jsStr(raWeaponDamageExpr(asMap(st['weapon'])['damage'], rules)['expr']);
    }
    final armor = raNum(st['armor'], 0) > 0 ? raNum(st['armor'], 0) : 0;
    final res = rules?.rollExpr(expr, rng);
    if (res == null || res['ok'] != true) {
      pushInto(out, sysTo(seat, '武器伤害式结算失败'));
      state['opposed'] = null;
      return out;
    }
    final dbRoll = rules?.rollDamageBonus(st['db'], rng);
    var raw = raNum(res['total'], 0) + raNum(dbRoll?['total'], 0);
    var impale = false;
    final win = asMap(st['win']);
    final aLevel = raFinite(asMap(win['a'])['level']);
    if (st['pierce'] == true &&
        aLevel != null &&
        (aLevel == 4 || aLevel == 5)) {
      final imp = rules?.impaleDamage(expr, st['db'], rng);
      if (imp != null && imp['ok'] == true) {
        raw = raNum(imp['raw'], raw);
        impale = true;
      }
    }
    final applied = (raw - armor) > 0 ? raw - armor : 0;
    final dmg = <String, Object?>{
      'expr': expr,
      'db': st['db'],
      'raw': raw,
      'armor': armor,
      'applied': applied,
      'impale': impale,
      'by': 'a',
    };
    out.addAll(opposedDamageMonster(slot['actorId'] ?? slot['id'], applied));
    final attacker = <String, Object?>{
      'name': st['byName'] ?? '玩家',
      'skill': asMap(st['weapon'])['skill'] ?? '格斗',
      'value': asMap(win['a'])['value'] ?? '',
      'actorId': '',
      'seat': seat,
    };
    final defender = <String, Object?>{
      'name': slot['name'] ?? '怪物',
      'skill': '',
      'value': asMap(win['b'])['value'] ?? '',
      'actorId': slot['actorId'] ?? slot['id'],
    };
    localSeq += 1;
    emitOpposedCheck(out, <String, Object?>{
      'id': 'o$localSeq',
      'kind': 'opposed',
      'targets': <Object?>[seat],
      'skill': '${jsStr(attacker['skill'])} vs 目标',
      'difficulty': 'REGULAR',
      'a': <String, Object?>{
        'ref': seat,
        'name': attacker['name'],
        'value': attacker['value'],
        'level': null,
        'levelText': asMap(win['a'])['levelText'] ?? '',
      },
      'b': <String, Object?>{
        'ref': defender['actorId'],
        'name': defender['name'],
        'value': defender['value'],
        'level': null,
        'levelText': asMap(win['b'])['levelText'] ?? '',
      },
      'winner': 'a',
      'tie': false,
      'reaction': win['reaction'] ?? '',
      'decidedBy': win['decidedBy'] ?? '',
      'rounds': asList(win['rounds']),
      'fallback': win['fallback'] == true,
      'damage': dmg,
      'summary': '$kRaOpposedPrefix${jsStr(attacker['name'])} 用「'
          '${jsStr(asMap(st['weapon'])['name'] ?? '武器')}」攻击 '
          '${jsStr(defender['name'])} → 命中：伤害 $expr+${jsStr(st['db'] ?? '0')}'
          '=${raw.toInt()}，护甲 ${armor.toInt()}，实扣 ${applied.toInt()}'
          '${impale ? '（贯穿：取最大值并追加伤害骰）' : ''}',
      'at': now(),
    }, st['secret'] == true);
    pushInto(out, emit(RoomEvt.opposed, <String, Object?>{
      'id': st['id'],
      'by': seat,
      'phase': 'resolved',
      'at': now(),
    }, vis: RoomVis.seat, to: seat));
    state['opposed'] = null;
    return out;
  }

  // ==========================================================
  // 场景检定步骤引擎
  // ==========================================================

  /// 推场景检定（旧版 :6663-6678）。
  List<SendPlan> sceneCheckPush(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final steps = raSanitizeSceneSteps(p['steps']);
    if (steps.isEmpty) {
      pushInto(out, sysTo(bySeat, '至少要有一个检定步骤'));
      return out;
    }
    localSeq += 1;
    final sc = <String, Object?>{
      'id': 'sc$localSeq',
      'title': cleanText(p['title'], 60).isNotEmpty
          ? cleanText(p['title'], 60)
          : '场景检定',
      'desc': cleanText(p['desc'], 200),
      'steps': steps,
      'cursor': 0,
      'results': <Object?>[],
      'at': now(),
    };
    pushInto(out, emit(RoomEvt.sceneCheck, sc, vis: RoomVis.public));
    pushInto(out, sys('KP 推送了场景检定「${sc['title']}」（${steps.length} 步）'));
    out.addAll(autoAdvanceSceneCheck());
    return out;
  }

  /// 自动跳过/自动判定锁死目标的步骤（旧版 :6690-6704）。
  List<SendPlan> autoAdvanceSceneCheck() {
    final out = <SendPlan>[];
    var guard = 0;
    while (guard++ < 30) {
      final sc = asMap(state['sceneCheck']);
      final steps = asList(sc['steps']);
      final cursor = raNum(sc['cursor'], 0).toInt();
      if (cursor < 0 || cursor >= steps.length) break;
      final step = asMap(steps[cursor]);
      final seat = cleanText(step['targetSeat'], 64);
      if (seat.isEmpty || seat == '*') {
        // ★ KP-6c：推全体一次展开 M 步 × N 在线玩家（用户拍板 D7）。
        //   改前这里直接 break，推全体永远不产生任何结果。展开方法内部
        //   一次性组装 M×N 条 result + M×N 条 PUBLIC kind:'check' 记录，
        //   只发一次 RoomEvt.sceneCheck 状态更新并把 cursor 推到末尾。
        //   ⚠️ 严禁在此循环里逐个调用 sceneCheckStep：它会改写 cursor
        //   并递归回本方法，多次调用会互相覆盖 state。
        out.addAll(_resolveAllPlayersSceneStep(sc, cursor));
        break;
      }
      final m = roster.get(seat);
      if (m == null || !(raMemberRipped(m) || raMemberInBout(m))) break;
      out.addAll(sceneCheckStep(kHostSeat, <String, Object?>{
        'stepId': step['id'],
        'seat': seat,
      }));
    }
    return out;
  }

  /// KP-6c：推全体场景检定，M 步 × N 在线玩家一次展开（用户拍板 D7）。
  ///
  /// 这是**内部私有方法**，不是新 action / 事件 / 意图：只在
  /// [autoAdvanceSceneCheck] 遇到 `targetSeat == '*'`（或空）时调用。
  /// `scene.check.push` 载荷字段不变，`sys('KP 推送了场景检定…')` 摘要
  /// 由 [sceneCheckPush] 保留；多步编辑器（sheet_scene.dart）发同一 action，
  /// 同样按此口径展开。
  ///
  /// 记录栏照出 M×N 条 `kind:'check'` PUBLIC 记录；遮罩广播层由
  /// W-D 的 FeedOptoastTracker flood 守卫（一次 diff > 6 条不刷屏）独立
  /// 兜住，两层解耦，这里**不削减**记录条数。
  ///
  /// 写法对齐 [sceneCheckStep]：skillBaseOf(m, step['skill'], null) ?? 50，
  /// rules.check + 规则缺失时的 1D100 兜底，等级文案用 rules.levelMap，
  /// 昵称用 raNick(this, roster.get(seat), seat)。
  List<SendPlan> _resolveAllPlayersSceneStep(
    Map<String, Object?> sc,
    int cursor,
  ) {
    final out = <SendPlan>[];
    final steps = asList(sc['steps']);
    if (cursor < 0 || cursor >= steps.length) return out;

    // 全体展开对象：在线玩家，撕卡（死亡 / 永久疯狂）跳过。
    // 参考 checkRequest:1328-1344 的全体展开 + 撕卡跳过口径。
    final players = <Map<String, Object?>>[];
    for (final m in roster.onlinePlayers()) {
      if (raMemberRipped(m)) continue;
      if (jsStr(m['seat']).isEmpty) continue;
      players.add(m);
    }

    final results = <Object?>[];
    final logs = <Map<String, Object?>>[];
    final levelMap = rules?.levelMap ?? <String, int>{};
    final metaOpts = ruleOptsOf(asMap(state['meta']));

    // M 步 × N 人全部展开：每步对每个在线玩家各掷一次，逐条攒在内存里，
    // 全程不碰 state['sceneCheck']（不调 sceneCheckStep / autoAdvance）。
    for (var si = cursor; si < steps.length; si++) {
      final step = asMap(steps[si]);
      final diff = jsTruthy(step['difficulty'])
          ? step['difficulty']
          : 'regular';
      for (final m in players) {
        final seat = jsStr(m['seat']);
        final num base = skillBaseOf(m, step['skill'], null) ?? 50;
        final chk = rules?.check(<String, Object?>{
          ...metaOpts,
          'base': base,
          'difficulty': diff,
          'kind': 'skill',
          'label': '${jsStr(step['skill'] ?? '自动检定')}（系统自动）',
          'rng': rng,
        }) ??
            <String, Object?>{
              'value': 1 + (rng() * 100).floor(),
              'level': 0,
              'levelText': '',
              'base': base,
            };
        final level = raNum(chk['level'], 0);
        final ok = level >= 2;
        final plan = rules != null
            ? rules!.sceneStepResolve(step, level)
            : raDefaultSceneResolve(step, level);
        final note = cleanText(plan['note'], 120);
        final damageExpr = cleanText(plan['damage'], 20);
        final nick = raNick(this, roster.get(seat), seat);
        results.add(<String, Object?>{
          'stepId': step['id'],
          'seat': seat,
          'level': level,
          'ok': ok,
          'note': note,
          'damage': 0,
          'damageExpr': damageExpr,
          'at': now(),
        });
        final lvlWord = level == levelMap['CRITICAL']
            ? '大成功'
            : (level == levelMap['FUMBLE']
                ? '大失败'
                : (ok ? '成功' : '失败'));
        logs.add(<String, Object?>{
          'seat': seat,
          'text': '场景检定「${jsStr(step['title'])}」：$nick '
              '$lvlWord${note.isNotEmpty ? '（$note）' : ''}'
              '（掷 ${jsStr(chk['value'] ?? '')}）',
          'at': now(),
          'kind': 'check',
        });
      }
    }

    // M×N 条 PUBLIC 记录一次性连续广播，随后**一次** sceneCheck 状态更新
    // 写回全部 results 并把 cursor 推到末尾（全部展开 = 全部完成）。
    for (final log in logs) {
      pushInto(out, emit(RoomEvt.log, log, vis: RoomVis.public));
    }
    final nextSc = <String, Object?>{
      ...roomClone(sc) as Map<String, Object?>,
      'results': <Object?>[...asList(sc['results']), ...results],
      'cursor': steps.length,
      'at': now(),
    };
    pushInto(out, emit(RoomEvt.sceneCheck, nextSc, vis: RoomVis.public));
    return out;
  }

  /// 已撕卡目标的步骤跳过并提示（旧版 :6712-6731）。
  List<SendPlan> skipSceneStep(
    String bySeat,
    Map<String, Object?> sc,
    int idx,
    Map<String, Object?> step,
    String seat,
    Map<String, Object?> m,
  ) {
    final out = <SendPlan>[];
    final who = raNick(this, m, seat);
    final steps = asList(sc['steps']);
    final result = <String, Object?>{
      'stepId': step['id'],
      'seat': seat,
      'level': null,
      'ok': false,
      'skipped': true,
      'note': '已撕卡，跳过',
      'damage': 0,
      'damageExpr': '',
      'at': now(),
    };
    final nextSc = <String, Object?>{
      ...roomClone(sc) as Map<String, Object?>,
      'results': <Object?>[...asList(sc['results']), result],
      'cursor': (idx + 1) < steps.length ? idx + 1 : steps.length,
      'at': now(),
    };
    pushInto(out, emit(RoomEvt.sceneCheck, nextSc, vis: RoomVis.public));
    pushInto(out, sysTo(bySeat.isEmpty ? kHostSeat : bySeat,
        '「$who」已撕卡（死亡/永久疯狂），已跳过场景检定「${jsStr(step['title'])}」'));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': '场景检定「${jsStr(step['title'])}」：$who 已撕卡，跳过该步',
      'at': now(),
      'kind': 'warn',
    }, vis: RoomVis.public));
    out.addAll(autoAdvanceSceneCheck());
    return out;
  }

  /// 结算当前步（或指定步）：按成功等级挑分支、应用伤害、跳转（旧版 :6734-6850）。
  List<SendPlan> sceneCheckStep(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    var sc = asMap(state['sceneCheck']);
    final steps = asList(sc['steps']);
    if (steps.isEmpty) {
      pushInto(out, sysTo(bySeat, '当前没有进行中的场景检定'));
      return out;
    }
    var idx = -1;
    if (p['stepId'] != null) {
      for (var i = 0; i < steps.length; i++) {
        if (asMap(steps[i])['id'] == p['stepId']) idx = i;
      }
    } else {
      idx = raNum(sc['cursor'], 0).toInt();
    }
    if (idx < 0 || idx >= steps.length) {
      pushInto(out, sysTo(bySeat, '找不到该步骤'));
      return out;
    }
    final step = asMap(steps[idx]);
    final seatPre = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : jsStr(step['targetSeat'] ?? '');
    final mPre = seatPre.isNotEmpty ? roster.get(seatPre) : null;
    if ((p['level'] == null) && mPre != null && raMemberRipped(mPre)) {
      return skipSceneStep(bySeat, sc, idx, step, seatPre, mPre);
    }
    num level;
    if (p['level'] == null) {
      if (mPre != null && raMemberInBout(mPre)) {
        var autoBase = skillBaseOf(mPre, step['skill'], null);
        autoBase ??= 50;
        final diff = jsTruthy(step['difficulty'])
            ? step['difficulty']
            : 'regular';
        final autoChk = rules?.check(<String, Object?>{
          ...ruleOptsOf(asMap(state['meta'])),
          'base': autoBase,
          'difficulty': diff,
          'kind': 'skill',
          'label': '${jsStr(step['skill'] ?? '自动检定')}（系统自动）',
          'rng': rng,
        }) ?? <String, Object?>{
          'value': 1 + (rng() * 100).floor(),
          'level': 0,
          'levelText': '',
          'base': autoBase,
        };
        level = raNum(autoChk['level'], 0);
        out.addAll(diceRoll(seatPre, <String, Object?>{
          'expr': '1D100',
          'label': '场景检定自动判定（${jsStr(step['skill'] ?? '')}，对 ${autoBase.toInt()}，疯狂/撕卡状态由系统随机）',
          'result': autoChk,
        }));
      } else {
        level = 2;
      }
    } else {
      level = raNum(p['level'], 2);
    }
    final plan = rules != null
        ? rules!.sceneStepResolve(step, level)
        : raDefaultSceneResolve(step, level);
    final seat = seatPre;
    final ok = level >= 2;
    final note = cleanText(plan['note'], 120);
    final damageExpr = cleanText(plan['damage'], 20);
    final result = <String, Object?>{
      'stepId': step['id'],
      'seat': seat,
      'level': level,
      'ok': ok,
      'note': note,
      'damage': 0,
      'damageExpr': damageExpr,
      'at': now(),
    };
    if (damageExpr.isNotEmpty && seat.isNotEmpty) {
      num dmg = 0;
      final rr = rules?.rollExpr(damageExpr, rng);
      if (rr != null && rr['ok'] == true) {
        dmg = raNum(rr['total'], 0) > 0 ? raNum(rr['total'], 0) : 0;
      } else {
        dmg = raNum(damageExpr, 0) > 0 ? raNum(damageExpr, 0) : 0;
      }
      result['damage'] = dmg;
      if (dmg > 0) {
        final m = roster.get(seat);
        if (m != null) {
          out.addAll(applyHpChange(m, -dmg,
              '场景检定「${jsStr(step['title'])}」失败', <String, Object?>{}));
        }
      }
    }
    final nextSc = <String, Object?>{
      ...roomClone(sc) as Map<String, Object?>,
      'results': <Object?>[...asList(sc['results']), result],
      'at': now(),
    };
    if (plan['done'] == true || plan['next'] == 'end') {
      nextSc['cursor'] = steps.length;
    } else if (jsTruthy(plan['next'])) {
      var ni = -1;
      for (var j = 0; j < steps.length; j++) {
        if (asMap(steps[j])['id'] == plan['next']) ni = j;
      }
      nextSc['cursor'] = ni >= 0 ? ni : idx + 1;
    } else {
      nextSc['cursor'] = idx + 1;
    }
    pushInto(out, emit(RoomEvt.sceneCheck, nextSc, vis: RoomVis.public));
    final levelMap = rules?.levelMap ?? <String, int>{};
    final lvlWord = level == levelMap['CRITICAL']
        ? '大成功'
        : (level == levelMap['FUMBLE']
            ? '大失败'
            : (ok ? '成功' : '失败'));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': bySeat,
      'text': '场景检定「${jsStr(step['title'])}」：'
          '${seat.isNotEmpty ? '${raNick(this, roster.get(seat), seat)} ' : ''}'
          '$lvlWord${note.isNotEmpty ? '（$note）' : ''}'
          '${raNum(result['damage'], 0) > 0 ? '，受到 ${raNum(result['damage'], 0).toInt()} 点伤害' : ''}',
      'at': now(),
      'kind': 'check',
    }, vis: RoomVis.public));
    out.addAll(autoAdvanceSceneCheck());
    return out;
  }

  /// 玩家自助 SAN 检定（INTENT.SAN_CHECK；旧版 :5597-5604）。
  List<SendPlan> playerSanCheck(
    String seat,
    Map<String, Object?>? mem,
    Map<String, Object?> p,
  ) {
    final out = <SendPlan>[];
    if (mem == null || mem['role'] != RoomRole.player) {
      pushInto(out, sysTo(seat, '只有玩家可以做 SAN Check'));
      return out;
    }
    out.addAll(settleSanCheck(mem, p, seat));
    return out;
  }
}
