// ============================================================
// room_model_host_intent.dart — 意图入口与权限执行链（D16，T04 · S4.2）
//
//   extension RoomHostIntent on RoomHost:
//     intent(seat, msg)  —— 13 个 INTENT 分支；isHost = (seat == 'host')
//     act / consent / confirmPending / stateSyncAck / applyAction
//     locked 全局操作锁白名单（room-model.js:1344-1369）
//     pending 去重（按 `by + op + jsonEncode(p)`，键序必须稳定）
//
// ⚠️ P0-M02：房主不在花名册里（`roster.get('host')` 恒 null），**必须按
//    seat 认 KP**，不能把查出来的空值当成旁观者。否则 `intent('host', CHAT)`
//    会被当成陌生人，「KP 说的话」走旁路、日志格式与玩家不一致。
//
// S4.3：`applyAction` 已把 61 个 POLICY action 的完整状态结算接上，
//    分发到 D17（房间/场景/素材/地图/手绘板）、D18（战斗/掷骰/检定）、
//    D19（卡/伤势/SAN/施救）三个 extension；`intent` / `act` 调用方
//    与权限闸门（needs / confirm / pending 去重 / locked 白名单）零改动。
//    未登记 action 由 dispatchXxx 全部返回 null → 默认空计划（不改状态），
//    且经 `act` 入口时已被 `needs()` 默认拒绝。
// ============================================================

import 'dart:convert';

import 'js_compat.dart';
import 'room_model_actions_combat.dart';
import 'room_model_actions_room.dart';
import 'room_model_actions_sheet.dart';
import 'room_model_host_core.dart';
import 'room_model_rollback.dart';
import 'room_model_save.dart';
import 'room_model_state.dart';
import 'room_types.dart';

/// 二次确认（`confirmPending`）的有效期：120 秒。
///
/// 来源：老 APP `room-model.js:1626` `CONFIRM_TTL_MS = 120000`（v2.13.6，
/// 用户报「KP 锁屏解锁后玩家被结团」）。安卓锁屏会让页面冻结/重载，一条
/// 排队中的「结团」可能几小时后才被点到；没有 TTL 的那一刻全桌人会被莫名
/// 结团。超过 2 分钟一律作废，必须重新操作。
const int kConfirmTtlMs = 120000;

/// ★ P20（需求 1）：确认载荷里「反击伤害骰式」的字符白名单。
///
/// 只做**轻校验**（非空 / ≤40 字符 / 字符集），真正的骰式合法性由
/// `rules.parseExpr` 在 `opposedAttackResolve` 里判（D2：非法则报错不结算）。
/// 白名单 = 数字 + `D`/`d` + `+`/`-` + 空白，与 `parseExpr` 支持的
/// `NdM`、纯数字、加减组合一一对应，拦掉明显脏数据但不越权解析。
final RegExp _reCounterDamage = RegExp(r'^[0-9Dd+\-\s]+$');

/// 公开信息栏优先角色名，其次昵称；KP 座位回落 meta.kpName / 'KP'。
String _nickOf(RoomHost h, Map<String, Object?>? m, String seat) {
  if (m != null && jsTruthy(m['charName'])) return jsStr(m['charName']);
  if (m != null && jsTruthy(m['nickname'])) return jsStr(m['nickname']);
  if (seat == kHostSeat) {
    final kp = asMap(h.state['meta'])['kpName'];
    return jsTruthy(kp) ? jsStr(kp) : 'KP';
  }
  return '某人';
}

/// 撕卡 / 疯狂发作 / 昏迷 / 濒死 → 全局操作锁（旧版 :1344-1345）。
bool _memberLocked(Map<String, Object?> mem) {
  final sheet = mem['sheet'];
  if (sheet is! Map) return false;
  final st = sheet['status'];
  if (st is Map) {
    if (st['body'] == '死亡') return true;
    if (jsTruthy(st['dying']) || jsTruthy(st['unconscious'])) return true;
  }
  final mental = asList(sheet['mental']);
  for (final v in mental) {
    final s = jsStr(v);
    if (s == '永久疯狂' || s == '临时疯狂' || s == '不定疯狂') return true;
  }
  return false;
}

/// 锁死期间的定向提示（旧版 :1358-1368 的三句分流）。
///
/// · 撕卡（死亡 / 永久疯狂）→ 只能聊天；
/// · 昏迷 / 濒死（且不在发作中）→ 可申请治愈伤势或请队友施救；
/// · 临时 / 不定疯狂发作中 → 只能推进 1 轮或申请治愈。
String _lockedHint(Map<String, Object?> mem) {
  final sheet = mem['sheet'];
  final st = sheet is Map
      ? asMap(sheet['status'])
      : const <String, Object?>{};
  final mental = sheet is Map ? asList(sheet['mental']) : const <Object?>[];
  final ripped = st['body'] == '死亡' ||
      mental.any((v) => jsStr(v) == '永久疯狂');
  if (ripped) {
    return '你的角色已死亡或永久疯狂（撕卡），只能通过聊天框交流';
  }
  final inBout = mental.any(
      (v) => jsStr(v) == '临时疯狂' || jsStr(v) == '不定疯狂');
  final knock = jsTruthy(st['unconscious']) || jsTruthy(st['dying']);
  if (!inBout && knock) {
    return '你的角色正处于昏迷/濒死，无法进行该操作；可申请治愈伤势或请队友施救';
  }
  return '你的角色正处于疯狂发作中（临时/不定疯狂），只能「推进 1 轮」或申请治愈，其他操作暂不可用';
}

/// 锁死期间仍允许的自助操作白名单（旧版 :1353-1357）。
bool _passSelf(String op, Map<String, Object?> p) {
  if (op == RoomIntent.chat ||
      op == RoomIntent.sync ||
      op == RoomIntent.ready ||
      op == RoomIntent.stateSync ||
      op == RoomIntent.char) {
    return true;
  }
  if (op == RoomIntent.act) {
    final a = jsStr(p['op']);
    return a == 'madness.advance' ||
        a == 'madness.cure' ||
        a == 'sheet.healwound';
  }
  return false;
}

extension RoomHostIntent on RoomHost {
  /// 玩家 / KP 的意图入口。**唯一按 seat 认 KP 的地方**。
  ///
  /// 所有对外方法返回 `List<SendPlan>`，不发包、不返回事件记录（K8）。
  List<SendPlan> intent(String seat, Map<String, Object?>? msg) {
    final out = <SendPlan>[];
    final mem = roster.get(seat);
    final isHost = seat == kHostSeat;
    // ⚠️ host 恒不在花名册里；只有「非 host 且查不到成员」才是旁观者。
    final role = isHost
        ? RoomRole.kp
        : (mem != null ? jsStr(mem['role']) : RoomRole.spectator);
    final p = msg == null ? <String, Object?>{} : asMap(msg['p']);
    final op = msg == null ? '' : jsStr(msg['op']);

    // 全局操作锁：撕卡 / 疯狂发作 / 昏迷 / 濒死的玩家只能自助操作。
    final locked = !isHost && mem != null && _memberLocked(mem);
    if (locked && !_passSelf(op, p)) {
      pushInto(out, sysTo(seat, _lockedHint(mem)));
      return out;
    }

    switch (op) {
      // 断线补拉：canFill 决定「增量补齐」还是「全量 sync」，二者不叠加。
      case RoomIntent.sync:
        final from = jsNum(p['lastSeq']);
        if (from > 0 && log.canFill(from)) {
          for (final rec in log.since(from)) {
            for (final part in plan(rec)) {
              if (part.to == '*' || part.to == seat) {
                out.add(SendPlan(seat, part.msg));
              }
            }
          }
          // 一条与己相关的事件都没有 → 仍要回一条全量，否则客户端会一直挂着补拉
          if (out.isEmpty) out.add(SendPlan(seat, syncFor(seat)));
        } else {
          out.add(SendPlan(seat, syncFor(seat)));
        }
        break;

      case RoomIntent.ready:
        if (role != RoomRole.player) {
          pushInto(out, sysTo(seat, '旁观者不能设准备状态'));
          break;
        }
        if (jsTruthy(p['ready']) &&
            !(mem != null && jsTruthy(mem['charId']))) {
          pushInto(out, sysTo(seat, '请先选择角色卡'));
          break;
        }
        if (mem != null) mem['ready'] = jsTruthy(p['ready']);
        out.addAll(syncMembers());
        pushInto(
          out,
          sys('${_nickOf(this, mem, seat)}'
              '${mem != null && jsTruthy(mem['ready']) ? ' 已准备' : ' 取消准备'}'),
        );
        break;

      // ★ P0-M02：KP 自己发言走**同一条路**，产生 1 条 `to:'*'` 广播。
      case RoomIntent.chat:
        final text = cleanText(p['text'], 600);
        if (text.isEmpty) break;
        pushInto(
          out,
          emit(
            RoomEvt.chat,
            <String, Object?>{
              'seat': seat,
              'nickname': _nickOf(this, mem, seat),
              'text': text,
              'at': now(),
              'kind': 'user',
            },
            vis: RoomVis.public,
          ),
        );
        break;

      case RoomIntent.char:
        // S4.4 / D21：整体覆盖 sheet 走 sanitizeSheet 白名单（客户端上报的
        // status / mental 一律经白名单收敛，绝不原始写入权威状态），贴回
        // 权威端产生的 tempStatus / items，并写 runtime 现值。
        out.addAll(shareSheet(role, seat, mem, p));
        break;

      case RoomIntent.dice:
        // ★ P11：花幸运 / 推动检定 —— 同一通道的两个**载荷变体**（不进 POLICY）。
        //   为什么挂在 DICE 通道而不是新增 action：13 个意图通道本来就不过
        //   needs()（§7 K6），而 `kRoomPolicy` 的 61 条被 fixture 覆盖矩阵锁死；
        //   两者都只作用于「自己刚掷出的那条检定」，在处理器里按 seat 自校验，
        //   权限面与事件面都不新增任何东西。
        if (jsTruthy(p['luck'])) {
          out.addAll(checkLuck(seat, p));
          break;
        }
        if (jsTruthy(p['push'])) {
          out.addAll(checkRepush(seat, p));
          break;
        }
        // ★ P4 补丁 B1（旧版 :1495-1509）：按 p.direct 分流。
        //   direct → 调 S4.3 已实现的 diceDirect：权威端用规则服务复算结果，
        //   经它的 emit(RoomEvt.dice, …, VIS.PUBLIC) 落状态并 to:'*' 广播；
        //   客户端自报的 p['result'] 根本不进这条路径（F4 的同一保证）。
        //   非 direct → 保持 S4.2 原有的「请求掷 X」日志，一字不动。
        //   ⚠️ 该分支不经 needs()/POLICY：旧版 Host.intent 只有 INTENT.ACT 走权限链。
        if (jsTruthy(p['direct'])) {
          out.addAll(diceDirect(seat, mem, role, p));
          break;
        }
        pushInto(
          out,
          emit(
            RoomEvt.log,
            <String, Object?>{
              'seat': seat,
              'text': '${_nickOf(this, mem, seat)} 请求掷 ${cleanText(p['expr'], 40)}',
              'at': now(),
              'kind': 'dice-request',
              'expr': cleanText(p['expr'], 40),
            },
            vis: RoomVis.public,
          ),
        );
        break;

      case RoomIntent.act:
        out.addAll(act(seat, mem, role, p));
        break;

      case RoomIntent.vote:
        // Q6 休眠：没有进行中的表决时旧版直接忽略。
        out.addAll(rollbackVote(seat, jsTruthy(p['agree'])));
        break;

      case RoomIntent.consent:
        out.addAll(consent(seat, p));
        break;

      case RoomIntent.confirm:
        out.addAll(confirmPending(seat, p));
        break;

      case RoomIntent.stateSync:
        out.addAll(stateSyncAck(seat, p));
        break;

      // ★ P4 补丁 B1（旧版 :1483-1494 / :1514-1517）：三个结算函数在
      //   S4.3 已实现，这里按旧版逐一接上，不再落到 default 空返回。
      //   三者和 diceDirect 一样，内部都走 emit() → apply() 单一写口，
      //   本层只汇总返回的 List<SendPlan>，不改 state、不绕开 apply。
      case RoomIntent.sanCheck:
        out.addAll(playerSanCheck(seat, mem, p));
        break;

      case RoomIntent.opposed:
        out.addAll(opposed(seat, mem, role, p));
        break;

      case RoomIntent.board:
        out.addAll(boardSelf(seat, p));
        break;

      default:
        break;
    }
    return out;
  }

  /// 通用动作权限闸门（旧版 `Host._act`，:1662-1699）。
  ///
  /// 权限表统一判定；越权不静默吞掉，回一条定向系统提示。
  /// 需要确认的动作先入 `pending`，按 `by + op + jsonEncode(p)` 去重
  /// （K2：`roomClone` / Map 字面量保序，签名才稳定）。
  List<SendPlan> act(
    String seat,
    Map<String, Object?>? mem,
    String role,
    Map<String, Object?> p,
  ) {
    final out = <SendPlan>[];
    final op = jsStr(p['op']);
    final verdict = needs(role, op);
    if (!verdict.allowed) {
      pushInto(out, sysTo(seat, '你没有权限执行该操作'));
      return out;
    }
    final confirm = verdict.confirm;
    if (confirm != null) {
      // KP 自己发起、且确认方就是 KP → 点击本身即确认，不再绕队列。
      if (confirm == RoomConfirm.kp && seat == kHostSeat) {
        return applyAction(seat, p);
      }
      final sig = jsonEncode(p);
      for (final q in pending) {
        if (q['by'] == seat &&
            q['op'] == op &&
            jsonEncode(q['p']) == sig) {
          pushInto(
            out,
            sysTo(
              seat,
              op == 'madness.cure'
                  ? '你的治愈申请已在等待 KP 同意，请勿重复提交'
                  : '该操作已在等待确认，请勿重复提交',
            ),
          );
          return out;
        }
      }
      pending.add(<String, Object?>{
        'by': seat,
        'op': op,
        'p': asMap(roomClone(p)),
        'need': confirm,
        'at': now(),
      });
      pushInto(
        out,
        sysTo(
          seat,
          op == 'madness.cure'
              ? '已向 KP 发起治愈申请，等待同意'
              : '已提交，等待确认',
        ),
      );
      return out;
    }
    return applyAction(seat, p);
  }

  /// 玩家对「KP 改我状态」的请求表态（同意 → 摘卡；拒绝 → 记一条系统消息）。
  List<SendPlan> consent(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final list = requestsBySeat[seat];
    if (list == null || list.isEmpty) {
      pushInto(out, sysTo(seat, '这条请求已经处理过了'));
      return out;
    }
    var idx = -1;
    for (var i = 0; i < list.length; i++) {
      if (list[i]['id'] == p['id']) idx = i;
    }
    if (idx < 0) {
      pushInto(out, sysTo(seat, '这条请求已经处理过了'));
      return out;
    }
    final req = list[idx];
    /* ★ P10 第 3 期 B（按老 APP 抹平差异）：检定请求走自己的路径。
       老 APP `room-model.js:1554-1566`（v2.1.0 缺陷 2 修复）：
         · 同意 → `_rollCheckRequest(seat, req)` 用**权威端存的技能值/难度**
           替该玩家掷一次 D100，结果 PUBLIC 广播全员，再摘卡；
         · 拒绝 → 只摘卡，不掷骰。
       改前本工程把 `check.request` 当成普通状态变更请求：玩家点「同意」
       之后只发一条「KP 调整了…的状态」日志，**没有任何检定结果**，
       `rollCheckRequest` 也就成了全库零调用点的死代码。
       ⚠️ 不能在这里先 `list.removeAt(idx)`：老 APP 的 `_settleRequest`
       负责摘卡（并发 REQUEST-done 定向事件），重复删会让它找不到卡片。 */
    if (req['op'] == 'check.request') {
      final skillRaw = cleanText(asMap(req['payload'])['skill'], 20);
      final sk = skillRaw.isNotEmpty ? skillRaw : '检定';
      final id = jsStr(req['id']);
      if (jsTruthy(p['agree'])) {
        out.addAll(rollCheckRequest(seat, req));
        out.addAll(settleRequest(seat, id, true, '同意并完成了「$sk」检定'));
      } else {
        out.addAll(settleRequest(seat, id, false, '忽略了检定请求'));
      }
      return out;
    }
    /* ★ P10 第 4 期（按老 APP 抹平差异）：状态变更请求走 `_settleRequest`
       等价收尾。老 `room-model.js:1569`：
         out = out.concat(this._settleRequest(seat, req.id, !!p.agree, null));
       `_settleRequest`（:3138-3151）= 摘卡 + 清 pending +
       `emit(EVT.REQUEST, {done:true}, VIS.SEAT, seat)` + 可选 verb。
       改前这里只有 `list.removeAt(idx)`：① 玩家端待办卡不消失（客户端
       `state.requests` 只由 `RoomEvt.request(self && done)` 裁剪，
       `syncMembers()` 碰不到它）；② 权威端 `pending` 残留一条
       `state.request` 记账。QA `qa_p10_5_report.md §8.2` 行为探针：
         「客户端剩余待办卡=1, 发了 REQUEST-done=false,
           权威端待办=0, pending=1」。
       ⚠️ verb 传 null ⇒ 不多发公共 sys，同意/拒绝的既有公共 LOG 文案
       与拒绝提示一字不动；摘卡与清 pending 只走 settleRequest 一处。 */
    final id = jsStr(req['id']);
    final agree = jsTruthy(p['agree']);
    out.addAll(settleRequest(seat, id, agree, null));
    if (!agree) {
      pushInto(
        out,
        sys('${_nickOf(this, roster.get(seat), seat)} 拒绝了状态变更请求'),
      );
      return out;
    }
    /* ★ P11 修复（P0）：同意后必须把请求载荷**真的落到角色卡上**。
       老 APP `room-model.js:1572-1610`（v2.6.0 / v2.8.0）：
         `req.payload` 形状 `{hp,san,mp}` → 译成 `{status:{currentHP,
         currentSAN,currentMP}}` → `stateApply(seat, change, {})`
         → `applyStatusJudgment(m, change, seat, {sanBefore,…})` → 再写日志。
       改前这里只有 `settleRequest` + `syncMembers` + 一条「KP 调整了…」：
       卡片消失、日志照发，但**一个字段都没写**（KP 请求扣 HP，玩家同意后
       HP 纹丝不动，归零也不判濒死）。
       ⚠️ change 在 `req['payload']` 里 —— **不是** `p['change']`：玩家点
       「同意」发出的只有 `{id, agree}`，`p` 里根本没有 change。
       ⚠️ `applyStatusJudgment` 的第 4 参数传 null 时读的是**改后**值
       （`prevBody = bodyView(status)`、`dyingBefore = status.dying`、
       `hpBefore = null ⇒ amountNow 恒 0`，且 `oSan == null` 会把「净减 SAN」
       整段跳过）——所以 before 必须在 `stateApply` **之前**取好，与老 APP
       的 sanBeforeConsent / hpBeforeConsent / bodyBeforeConsent /
       flagsBeforeConsent 一一对应。 */
    final ch = asMap(req['payload']);
    final m = roster.get(seat);
    if (m != null) {
      final stBefore = m['sheet'] is Map
          ? asMap(asMap(m['sheet'])['status'])
          : const <String, Object?>{};
      final sanBefore = raMemberStatusValue(m, 'currentSAN');
      final hpBefore = raMemberStatusValue(m, 'currentHP');
      final bodyBefore = bodyView(stBefore);
      final flagsBefore = <String, Object?>{
        'dying': jsTruthy(stBefore['dying']),
        'unconscious': jsTruthy(stBefore['unconscious']),
      };
      final stc = <String, Object?>{};
      for (final pair in <MapEntry<String, String>>[
        const MapEntry<String, String>('hp', 'currentHP'),
        const MapEntry<String, String>('san', 'currentSAN'),
        const MapEntry<String, String>('mp', 'currentMP'),
      ]) {
        final raw = ch[pair.key];
        if (raw == null) continue;
        final n = raFinite(raw);
        if (n != null) stc[pair.value] = n;
      }
      if (stc.isNotEmpty) {
        final change = <String, Object?>{'status': stc};
        out.addAll(stateApply(seat, change, <String, Object?>{}));
        out.addAll(applyStatusJudgment(m, change, seat, <String, Object?>{
          'sanBefore': sanBefore,
          'hpBefore': hpBefore,
          'bodyBefore': bodyBefore,
          'flagsBefore': flagsBefore,
        }));
      }
    }
    out.addAll(syncMembers());
    pushInto(
      out,
      emit(
        RoomEvt.log,
        <String, Object?>{
          'seat': '',
          'text': 'KP 调整了 ${_nickOf(this, roster.get(seat), seat)} 的状态',
          'at': now(),
          'kind': 'state',
        },
        vis: RoomVis.public,
      ),
    );
    return out;
  }

  /// KP 对已排队的高危动作做二次确认（agree=false 直接丢弃待办）。
  List<SendPlan> confirmPending(String seat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    if (seat != kHostSeat) {
      pushInto(out, sysTo(seat, '你没有权限执行该操作'));
      return out;
    }
    final op = jsStr(p['op']);
    var idx = -1;
    for (var i = 0; i < pending.length; i++) {
      if (pending[i]['op'] == op && pending[i]['by'] == p['by']) {
        idx = i;
        /* ★ P17 KP-1②：摘到**第一条**匹配就必须停（原来这里没有 break，
           `idx` 会被循环覆写成最后一条匹配项）。
           为什么必须改：改前 UI 的去重键 `pending:<op>:<by>` 不含待办自身的
           区分信息，同一玩家两次同 op 的不同申请只弹一条，所以「只摘最后一条」
           一直没被用户看见；P17 把去重键改成唯一键后两条都会弹，
           此时点第一条「同意」却摘掉最后一条、点第二条再摘一条 →
           **第一条永久残留**（用户看到「弹了两条、同意了一条、另一条再也消不掉」）。
           为什么按 op+by 首条匹配而不是按唯一 id 精确匹配：CONFIRM 的载荷契约
           就是 `{op, by, agree}`（`RoomController.dangerAction:98-103` 与
           `gp_status.dart:142` / `gp_combat_list.dart:105-108` 三个调用点都这么发），
           待办项自身**没有** id 字段（`act()` 入队处只写 `by/op/p/need/at`，
           :324-330），加 id 就要同时改三个 UI 调用点 + 载荷契约，超出本批范围。
           首条匹配与弹窗顺序天然对齐：`collectRoomPushRequests` 按 `pending` 数组
           顺序产出、watcher 的 `_queue` 按入队顺序消费，所以「先弹的那条 = 先摘的
           那条」，FIFO 语义与用户看到的一致。 */
        break;
      }
    }
    if (idx < 0) {
      pushInto(out, sysTo(seat, '这条待办已经处理过了'));
      return out;
    }
    final entry = pending.removeAt(idx);
    /* ★ P11 修复（P0）：二次确认的 120 秒有效期闸门。
       老 APP `room-model.js:1643-1651`：`age = now() - num(task.at, 0)`，
       `age > CONFIRM_TTL_MS` → 直接丢弃该待办并回一条**私信**，**不执行**动作。
       改前本工程没有这道闸门：KP 昨天点过「解散房间」却没确认，待确认项
       会一直挂在 `pending` 里，今天随便点一下就真把房间结了
       （老 v2.13.6 专修过这个坑）。`at` 缺失按 0 处理 → 同样视为过期。
       ⚠️ 放在 `removeAt` 之后、`agree` 判定之前：过期项必须从队列里摘掉
       （否则每次点击都重复提示），且「拒绝过期项」与「同意过期项」同样作废。 */
    final age = now() - jsNum(entry['at']);
    if (age > kConfirmTtlMs) {
      pushInto(out, sysTo(seat, '这条确认已过期（超过 2 分钟），请重新操作'));
      return out;
    }
    if (!jsTruthy(p['agree'])) {
      pushInto(out, sys('KP 拒绝了待确认操作：$op'));
      return out;
    }
    // ★ Q-A（主理人 2026-11-15 批准 · v1.1 §1.4）：把 KP 第二段弹窗补输的
    //   守方技能点数合并进待办载荷的 defender 袋，再交给 applyAction。
    //   · 既有三键契约 `{op,by,agree}` / 首条 op+by 匹配 / removeAt / 120s
    //     TTL / agree 判定 / pending 结构全部逐字不动；
    //   · 三个既有 UI 确认调用点不传 `value` → payload 与旧口径完全等价；
    //   · 严格只接受 1–100 整数，非法值（字符串 / 小数 / 越界 / 缺失）
    //     一律忽略，绝不污染既有 action 载荷。
    final payload = <String, Object?>{...asMap(entry['p'])};
    final v = raFinite(p['value']);
    if (v != null && v >= 1 && v <= 100 && v == v.roundToDouble()) {
      payload['defender'] = <String, Object?>{
        ...asMap(payload['defender']),
        'value': v.toInt(),
        'side': 'monster',
      };
    }
    // ★ P13（主理人批准白名单）：KP 同意后新选的防守方式合并进 defender 袋，
    //   供 checkOpposed / opposedAttackResolve 读取（counter 反击 / dodge 闪避 /
    //   none 不防御）。
    //   · 严格只接受 counter / dodge / none 三种，非法值（含缺失）一律忽略，
    //     绝不污染既有 action 载荷；
    //   · {op,by,agree} 三键契约 / 首条 op+by 匹配 / removeAt / 120s TTL /
    //     agree 判定 / pending 结构全部逐字不动，不新增 action / 事件 / 意图；
    //   · reaction=='none' 时防守方不设防：结算器 `opposedAttackResolve` 走
    //     强制命中分支读的是**顶层** `noDefense`（不是 defender.reaction），
    //     故这里同步置位，否则 none 会因缺对抗值而结算失败。
    final Object? reaction = p['reaction'];
    if (reaction == 'counter' || reaction == 'dodge' || reaction == 'none') {
      payload['defender'] = <String, Object?>{
        ...asMap(payload['defender']),
        'reaction': reaction,
      };
      if (reaction == 'none') payload['noDefense'] = true;
    }
    // ★ P20（需求 1）：反击时 KP 在第二段窗里补输的「反击伤害骰式」合并进
    //   defender 袋的 `damage` 键，供 `opposedAttackResolve` 送进规则层
    //   （`room_rules_combat.dart:223-229` 的反击伤害式）。
    //   · 触发条件：确认载荷带了 `reaction == 'counter'` **且** 顶层 `damage`
    //     是非空 String —— 与既有 `value` / `reaction` 同款「顶层可选键」，
    //     不新增 RoomIntent / RoomEvt 成员、不改事件形状；
    //   · 只做轻校验（非空 / ≤40 字符 / 字符白名单 `[0-9Dd+\-\s]`），
    //     骰式合法性留给 domain 的 `rules.parseExpr`（非法由结算器报错不结算）；
    //   · 缺键 / 空串 / 非 String / 非法字符 → **一律忽略**，`payload` 与改前
    //     逐字等价（KP 直发链路与其它三条确认调用点零影响）。
    final Object? rawDamage = p['damage'];
    if (reaction == 'counter' && rawDamage is String) {
      final String expr = rawDamage.trim();
      if (expr.isNotEmpty &&
          expr.length <= 40 &&
          _reCounterDamage.hasMatch(expr)) {
        payload['defender'] = <String, Object?>{
          ...asMap(payload['defender']),
          'damage': expr,
        };
      }
    }
    return applyAction(jsStr(entry['by']), payload);
  }

  /// 玩家回执「我已把状态写入本机角色卡」：权威端只记账，幂等落点在 Client。
  ///
  /// ★ P11 修复（P1）：老 APP `room-model.js:3967-3970`：
  ///   `var m = this.roster.get(seat); if (m) m.stateAckSeq = num(p && p.seq, 0);`
  /// 改前这里是 `stateSeq += 1` —— `stateSeq` 是**权威端状态版本号**
  /// （`stateApply` 每写一次卡才 +1），回执把它 +1 会让所有客户端以为
  /// 又有一版新状态；而「该成员已确认到哪一版」的记账 `stateAckSeq`
  /// 从来没有被写过（全库无该字段）。两者语义完全不同，不能混用。
  List<SendPlan> stateSyncAck(String seat, Map<String, Object?> p) {
    final m = roster.get(seat);
    if (m != null) m['stateAckSeq'] = jsNum(p['seq']);
    return const <SendPlan>[];
  }

  /// 动作分发入口（S4.3 全量接线）。
  ///
  /// 三组 extension 依次尝试；每组返回 `null` 表示「该 op 不属于本组」。
  /// 三组都不认 → 未登记 action，返回空计划（不改权威状态）；该 action
  /// 若经 [act] 进入，早在 `needs()` 就被默认拒绝并回一条定向 sysTo。
  ///
  /// ⚠️ 调用方 [intent] / [act] 与权限闸门零改动；本方法只负责把
  ///    `p['op']` 路由到 D17 / D18 / D19 的真实结算处理器。
  List<SendPlan> applyAction(String seat, Map<String, Object?> p) {
    final room = dispatchRoomAction(seat, p);
    if (room != null) return room;
    final combat = dispatchCombatAction(seat, p);
    if (combat != null) return combat;
    final sheet = dispatchSheetAction(seat, p);
    if (sheet != null) return sheet;
    return const <SendPlan>[];
  }
}
