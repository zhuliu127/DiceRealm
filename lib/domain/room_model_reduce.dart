// ============================================================
// room_model_reduce.dart — `reduceRoomState(state, evt)`（D11）
//
// 「所有状态变更都走这里」是回退能成立的前提：回退 = 重放日志到某个 seq。
//
// ⚠️ 全库调用点**恰好 2 处**：`RoomHost.apply`（权威端）与
//    `RoomClient.receive`（客户端回放）。任何第三处调用都会破坏可重放性。
// ⚠️ 可见性依赖 `evt.vis` / `evt.to`（Q1）：
//    · CHECK 非 PUBLIC → 只落脱敏行（旧版 :685 判据）
//    · PRIVATE 且 vis=seat 且 to≠host → 不进 state.privates（旧版 :762 守卫）
//    `vis == null` ≡ 旧版「客户端 reduce / 旧调用未传 vis」→ 按 PUBLIC 处理。
// ⚠️ `EVT.TEMP_COMMIT` **刻意没有 case**（Q6）：走 default，什么都不改，
//    但仍会被末尾一句写成 `state.seq`。删掉它会让「刻意的空分支」变成漏写。
// ============================================================

import 'js_compat.dart';
import 'room_model_state.dart';
import 'room_types.dart';

/// 取「真值则原样，否则空串」——对应旧版 `x || ''`。
Object? _rStr(Object? v) => jsTruthy(v) ? v : '';

/// 取「真值则原样，否则 0」——对应旧版 `x || 0`。
Object? _rZero(Object? v) => jsTruthy(v) ? v : 0;

Map<String, Object?> _rMap(Object? v) => asMap(v);

/// 把日志数组裁到上限（超限丢最旧的）。
void _rCap(List<Object?> list, int max) {
  if (list.length > max) list.removeRange(0, list.length - max);
}

/// reduce 侧「机械闸门」的告警缓冲。
///
/// 为什么不直接写进 state：`state` 会整份进 sync / 存档 / oracle 深比，
/// 多一个键就是协议变更。这里只暂存，`RoomHost.apply()` 在归约后把它
/// 汇进既有的 `host.warnings`（与 `emit()` 的 scrub 告警同一个出口）。
/// 客户端回放（vis 恒 null）永不触发，因此不需要缓冲。
final List<RoomWarning> reduceGateWarnings = <RoomWarning>[];

/// 一次状态归约。**纯函数**：只改传入的 state 并返回它（便于链式与断言）。
Map<String, Object?> reduceRoomState(
  Map<String, Object?> state,
  RoomEvent evt,
) {
  final p = evt.p;
  final meta = _rMap(state['meta']);

  switch (evt.t) {
    // ---- 房间元信息 ----
    case RoomEvt.hello:
      final m = p['meta'];
      if (m is Map) {
        for (final e in m.entries) {
          meta['${e.key}'] = e.value;
        }
      }
      break;

    case RoomEvt.members:
      state['members'] = roomClone(asList(p['members']));
      break;

    case RoomEvt.status:
      meta['status'] = jsTruthy(p['status']) ? p['status'] : meta['status'];
      // mode（探索/战斗）与房间生命周期状态是两回事，但跟着同一条 STATUS 下发 ——
      // 漏了这里，客户端界面会永远停在探索。
      if (jsTruthy(p['mode'])) meta['mode'] = p['mode'];
      break;

    // ---- 事件流 ----
    case RoomEvt.chat:
      final chats = asList(state['chats']);
      chats.add(<String, Object?>{
        'seq': evt.seq,
        'seat': _rStr(p['seat']),
        'nickname': _rStr(p['nickname']),
        'text': _rStr(p['text']),
        'at': _rZero(p['at']),
        'kind': jsTruthy(p['kind']) ? p['kind'] : 'user',
      });
      _rCap(chats, 500);
      break;

    case RoomEvt.log:
      final logs = asList(state['logs']);
      logs.add(<String, Object?>{
        'seq': evt.seq,
        'seat': _rStr(p['seat']),
        'text': _rStr(p['text']),
        'at': _rZero(p['at']),
        'kind': jsTruthy(p['kind']) ? p['kind'] : 'info',
      });
      // 游戏记录上限 2000（长团也要完整留存）
      _rCap(logs, 2000);
      break;

    case RoomEvt.dice:
      // ★ P10 第 3 期 B：reduce 侧机械闸门（QA `qa_p10_4_report.md` §3b 登记的
      //   技术债）。`emit()` 的唯一 scrub 闸门只认 `kSecretKeys`，`label`（技能名）
      //   不在其中；而 `state.dice` 会整列进 sync / 存档 / 公开记录 / 历史导出。
      //   所以「非 PUBLIC 的 DICE」绝不能靠调用方自觉 —— 这里直接丢弃并记告警。
      //   vis == null ≡ 客户端回放 / 旧调用（旧口径按 PUBLIC 处理），保持原行为。
      //   ⚠️ 暗骰 / KP 暗骰走的是 `RoomEvt.private_`（SEAT），**不是** DICE，
      //      因此本闸门不会误伤正常秘密骰点分发。
      if (evt.vis != null && evt.vis != RoomVis.public) {
        reduceGateWarnings.add(RoomWarning(
          RoomEvt.dice,
          '非 PUBLIC 的 DICE 事件已丢弃（不进公共骰列）',
        ));
        break;
      }
      final dice = asList(state['dice']);
      dice.add(<String, Object?>{
        'seq': evt.seq,
        'seat': _rStr(p['seat']),
        'nickname': _rStr(p['nickname']),
        'expr': _rStr(p['expr']),
        'rolls': roomClone(asList(p['rolls'])),
        // ⚠️ total / level 在旧版是**原样透传**：调用方没给就是 undefined，
        //    JSON 化时该键整个消失。这里必须同样按「有没有给」决定是否落键。
        if (p.containsKey('total')) 'total': p['total'],
        if (p.containsKey('level')) 'level': p['level'],
        'levelText': _rStr(p['levelText']),
        'label': _rStr(p['label']),
        'at': _rZero(p['at']),
        // ★ P11 花幸运 / 推动：检定附加信息。
        //   同样是「有没有给」才落键 —— 快捷骰（1D6 等）一个键都不多，
        //   既有 reduce / 序列 / 状态深比用例的形状逐字节不变。
        //   为什么必须落进 state 而不是留在权威端内存：这三件事都要跨设备
        //   一致（玩家端要算「花多少点」、要判「能不能推动」），
        //   且回退重放必须能还原，只有事件载荷进 state 才两条都成立。
        if (p.containsKey('kind')) 'kind': p['kind'],
        if (p.containsKey('base')) 'base': p['base'],
        if (p.containsKey('target')) 'target': p['target'],
        if (p.containsKey('difficulty')) 'difficulty': p['difficulty'],
        if (p.containsKey('required')) 'required': p['required'],
        if (p.containsKey('critMax')) 'critMax': p['critMax'],
        if (p.containsKey('fumbleMin')) 'fumbleMin': p['fumbleMin'],
        if (p.containsKey('pushed')) 'pushed': p['pushed'],
        if (p.containsKey('luckSpent')) 'luckSpent': p['luckSpent'],
        if (p.containsKey('luckFrom')) 'luckFrom': p['luckFrom'],
        if (p.containsKey('pushFrom')) 'pushFrom': p['pushFrom'],
      });
      _rCap(dice, 200);
      break;

    // ---- 场景 / 战斗 ----
    case RoomEvt.scene:
      state['scene'] = jsTruthy(p['scene']) ? roomClone(p['scene']) : null;
      break;

    case RoomEvt.combat:
      state['combat'] = jsTruthy(p['combat']) ? roomClone(p['combat']) : null;
      break;

    case RoomEvt.turn:
      final c = state['combat'];
      if (c is Map) {
        if (p.containsKey('round')) c['round'] = p['round'];
        if (p.containsKey('turn')) c['turn'] = p['turn'];
        if (jsTruthy(p['order'])) c['order'] = roomClone(p['order']);
      }
      break;

    case RoomEvt.round:
      // 回合边界由**事件**写 meta.round（而不是命令式赋值），
      // 这样快照 / 回退重放 / 全量同步都能带上正确的回合号。
      if (p.containsKey('round') && p['round'] != null) {
        meta['round'] = p['round'];
      }
      break;

    // ---- P4 探索：手绘板 / 素材 ----
    case RoomEvt.board:
      if (state['scene'] is! Map) state['scene'] = _rEmptyScene();
      final sc = _rMap(state['scene']);
      if (sc['boards'] is! Map) sc['boards'] = <String, Object?>{};
      final seat = p['seat'];
      if (jsTruthy(seat)) {
        _rMap(sc['boards'])[jsStr(seat)] = <String, Object?>{
          'at': _rZero(p['at']),
          'count': asList(p['strokes']).length,
          'thumb': _rStr(p['thumb']),
        };
      }
      if (jsTruthy(p['self']) && p['strokes'] is List) {
        state['board'] = <String, Object?>{
          'strokes': roomClone(p['strokes']),
          'at': _rZero(p['at']),
        };
      }
      break;

    case RoomEvt.asset:
      if (state['scene'] is! Map) state['scene'] = _rEmptyScene();
      if (p['assets'] is List) {
        _rMap(state['scene'])['assets'] = roomClone(p['assets']);
      }
      break;

    // ---- P5 战斗 ----
    case RoomEvt.actor:
      final c = state['combat'];
      final actor = p['actor'];
      if (c is Map && actor is Map) {
        // ★ P16 KP-4①：combat.actor 的载荷是扁平 actor
        //   （{id,name,kind,dex,hp,hpMax,actionsPerRound[,armor]}），
        //   旧实现把它原样当 slot 写进 order，而 combatRows 只读 slot['public']
        //   → HP 恒显示 0。这里把 HP/dex 补成与 combatStart 同构的 public 嵌套。
        //
        //   ⚠️ 只在载荷**真的带**这些键时才补：部分更新载荷（只有 {id,name}
        //   这种形状，正是 action oracle 的 M:reduce:ACTOR 三例）保持旧版
        //   逐字节的扁平写入 —— 既不伪造空 public 块，也不改 oracle 的
        //   键集合契约（白名单全库恰好 2 条，禁止为此新增登记）。
        final slot = <String, Object?>{...asMap(roomClone(actor))};
        final nested = slot['public'] is Map;
        final pub = nested
            ? <String, Object?>{...asMap(slot['public'])}
            : <String, Object?>{};
        for (final k in const <String>['hp', 'hpMax', 'dex']) {
          if (!pub.containsKey(k) && slot.containsKey(k)) pub[k] = slot[k];
        }
        if (nested || pub.isNotEmpty) slot['public'] = pub;
        var found = false;
        final order = c['order'];
        if (order is List) {
          for (var i = 0; i < order.length; i++) {
            if (_rMap(order[i])['id'] == actor['id']) {
              order[i] = slot;
              found = true;
              break;
            }
          }
        }
        if (!found) {
          if (c['order'] is! List) c['order'] = <Object?>[];
          asList(c['order']).add(slot);
        }
      }
      break;

    case RoomEvt.turnstate:
      final c = state['combat'];
      if (c is Map) {
        if (p.containsKey('turn')) c['turn'] = p['turn'];
        if (p.containsKey('round')) c['round'] = p['round'];
        if (jsTruthy(p['order'])) c['order'] = roomClone(p['order']);
      }
      break;

    // ---- 检定（★ 可见性闸门 ③）----
    case RoomEvt.check:
      if (jsTruthy(p['summary'])) {
        final logs = asList(state['logs']);
        // vis 缺失（客户端 reduce / 旧调用）视为 PUBLIC → 行为不变
        final checkPublic = evt.vis == null || evt.vis == RoomVis.public;
        if (checkPublic) {
          final isOpposed = p['kind'] == 'opposed';
          logs.add(<String, Object?>{
            'seq': evt.seq,
            'seat': _rStr(p['seat']),
            'text': p['summary'],
            'at': _rZero(p['at']),
            'kind': 'check',
            'opp': isOpposed
                ? <String, Object?>{
                    'a': roomClone(p['a']),
                    'b': roomClone(p['b']),
                    'winner': p.containsKey('winner') ? p['winner'] : null,
                    'tie': jsTruthy(p['tie']),
                    'reaction': _rStr(p['reaction']),
                    'decidedBy': _rStr(p['decidedBy']),
                    'fallback': jsTruthy(p['fallback']),
                    'rounds': roomClone(asList(p['rounds'])),
                    'damage': jsTruthy(p['damage'])
                        ? roomClone(p['damage'])
                        : null,
                  }
                : null,
          });
        } else {
          // 只落脱敏行：完整结果由调用方经 EVT.PRIVATE 单独发给 KP。
          logs.add(<String, Object?>{
            'seq': evt.seq,
            'seat': '',
            'text': 'KP 秘密进行了一次检定',
            'at': _rZero(p['at']),
            'kind': 'check',
            'opp': null,
            'redacted': true,
          });
        }
        _rCap(logs, 2000);
      }
      break;

    // ---- 对抗申请 / 状态 ----
    case RoomEvt.opposed:
      final phase = p['phase'];
      state['opposed'] = (phase == 'await_kp' || phase == 'await_target')
          ? roomClone(p)
          : null;
      break;

    // ---- 场景检定步骤引擎 ----
    case RoomEvt.sceneCheck:
      state['sceneCheck'] = jsTruthy(p['id']) ? roomClone(p) : null;
      break;

    // ---- 角色卡状态写回（权威端 → 目标玩家，SEAT 单发）----
    case RoomEvt.state:
      state['lastState'] = <String, Object?>{
        'seat': _rStr(p['seat']),
        'seq': roomNumber(p['seq'], 0),
        'status': roomClone(jsTruthy(p['status']) ? p['status'] : const <String, Object?>{}),
        'at': _rZero(p['at']),
      };
      break;

    // ---- 存档推送结果（仅 KP 关心）----
    case RoomEvt.archive:
      state['archive'] = <String, Object?>{
        'seq': roomNumber(p['seq'], 0),
        'savedAt': _rZero(p['savedAt']),
        'ok': jsTruthy(p['ok']),
      };
      break;

    // ---- 轮次强提醒 ----
    case RoomEvt.turnAlert:
      state['alert'] = <String, Object?>{
        'kind': jsTruthy(p['kind']) ? p['kind'] : 'turn',
        // round / turn 同样是原样透传（没给就不落键）
        if (p.containsKey('round')) 'round': p['round'],
        if (p.containsKey('turn')) 'turn': p['turn'],
        'name': _rStr(p['name']),
        'seat': _rStr(p['seat']),
        'at': _rZero(p['at']),
      };
      break;

    // ---- KP 改我状态：待办增删 ----
    case RoomEvt.request:
      final self = jsTruthy(p['self']);
      if (self && jsTruthy(p['done'])) {
        // 处理完必须摘掉：否则 requests 只增不减，界面永远渲染第一张旧卡
        state['requests'] = asList(state['requests'])
            .where((r) => _rMap(r)['id'] != p['id'])
            .toList();
      } else if (self) {
        asList(state['requests']).add(<String, Object?>{
          'id': p['id'],
          'op': p['op'],
          'p': roomClone(jsTruthy(p['payload'])
              ? p['payload']
              : const <String, Object?>{}),
          'from': jsTruthy(p['from']) ? p['from'] : 'KP',
          'reason': _rStr(p['reason']),
          'at': _rZero(p['at']),
        });
      }
      break;

    // ---- 回退投票状态（Q6 休眠保留，供旧存档回放）----
    case RoomEvt.rewind:
      state['rewind'] = jsTruthy(p['rewind']) ? roomClone(p['rewind']) : null;
      break;

    // ---- 定向私密（★ 可见性闸门 ③）----
    case RoomEvt.private_:
      // SEAT 定向且收件人不是 KP → **不**归约进 KP 的公共私有栏
      if (evt.vis == RoomVis.seat && evt.to != null && evt.to != kHostSeat) {
        break;
      }
      final privates = asList(state['privates']);
      privates.add(<String, Object?>{
        'seq': evt.seq,
        'text': _rStr(p['text']),
        'at': _rZero(p['at']),
        'kind': jsTruthy(p['kind']) ? p['kind'] : 'info',
        'title': _rStr(p['title']),
      });
      _rCap(privates, 100);
      break;

    // ---- 生命周期三兄弟 ----
    case RoomEvt.closed:
      // ⚠️ CLOSED 语义不改：**不写** meta.ended（旧客户端把它当终止）
      meta['status'] = RoomStatus.closed;
      break;

    case RoomEvt.ended:
      meta['status'] = RoomStatus.closed;
      meta['ended'] = true;
      break;

    case RoomEvt.kick:
      meta['status'] = RoomStatus.closed;
      break;

    // TEMP_COMMIT / 未知类型：刻意不改任何键（Q6/Q8）
    default:
      break;
  }

  // 末尾**无条件**写序号：这条是「重放后 lastSeq 与事件一致」的唯一保证
  state['seq'] = evt.seq;
  return state;
}

/// 首次出现手绘板 / 素材时懒创建的 scene 骨架（键序与旧版一致）。
Map<String, Object?> _rEmptyScene() => <String, Object?>{
      'title': '',
      'image': '',
      'assets': <Object?>[],
      'marks': <Object?>[],
      'strokes': <Object?>[],
      'boards': <String, Object?>{},
    };
