// ============================================================
// test/support/room_host_script.dart — `hostScript` 用例的**共用执行器**
//
// 为什么抽出来：`room_sequences_test.dart` 里那份 runner 是内联的，复核要拿
// 同一份语义去算 `actual`（白名单自证测试必须用**与正式用例完全相同**的执行
// 路径，否则证明不了任何东西）。抽成 support 后：
//   · 正式 fixture（room_sequences.json）与 QA 现造对照（qa_p4_fresh_oracle.json）
//     共用同一份 op 词表；
//   · 复核用例可以绕开白名单直接比 `actual` vs `expect`。
//
// ⚠️ 只读：不改任何 state，不碰网络；op 词表与 dump_p4_room.js:943-992 对齐。
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';

import 'room_fakes.dart';

/// 发送计划列表 → 旧版 `J(out)` 的同形状 JSON。
List<Map<String, Object?>> plansJson(List<SendPlan> out) =>
    out.map((s) => s.toJson()).toList();

/// 构造与 `runHostScript` 里 `new M.Host(args)` 一致的权威端。
RoomHost hostFromArgs(Map<String, Object?> a) => RoomHost(roomHostOpts(
      meta: asMap(a['meta']),
      snapshotEvery: (a['snapshotEvery'] as num?)?.toInt() ?? 20,
      logCap: (a['logCap'] as num?)?.toInt() ?? 400,
    ));

/// 跑一段 `hostScript`，返回与 fixture `expect` 同形状的结果对象。
///
/// 键集合/键序与 `dump_p4_room.js#runHostScript` 完全一致：
/// `steps / state / logSeq / log / warnings / snapshotSeqs / roundStarts /
///  save / saveKeys`。
Map<String, Object?> runHostScript(Map<String, Object?> a) {
  final h = hostFromArgs(a);
  final steps = <Object?>[];
  Map<String, Object?>? saveOut;
  for (final opRaw in asList(a['ops'])) {
    final op = asMap(opRaw);
    switch (jsStr(op['op'])) {
      case 'attach':
        steps.add(h.attachPeer(asMap(op['m'])).toJson());
        break;
      case 'detach':
        steps.add(plansJson(h.detachPeer(jsStr(op['seat']))));
        break;
      case 'emit':
        final rec = h.emit(
          jsStr(op['t']),
          op['p'] == null ? <String, Object?>{} : asMap(op['p']),
          vis: op['vis'] == null ? RoomVis.public : jsStr(op['vis']),
          to: op['to'] == null ? null : jsStr(op['to']),
        );
        steps.add(<String, Object?>{
          'seq': rec.seq,
          'plan': jsTruthy(op['plan']) ? plansJson(h.plan(rec)) : null,
        });
        break;
      case 'emitLocal':
        final rec = h.emitLocal(
          jsStr(op['t']),
          op['p'] == null ? <String, Object?>{} : asMap(op['p']),
        );
        steps.add(<String, Object?>{
          'seq': rec.seq,
          'evt': asMap(rec.toWireJson())['evt'],
        });
        break;
      case 'syncFor':
        steps.add(h.syncFor(jsStr(op['seat'])).toJson());
        break;
      case 'makeSync':
        steps.add(h.makeSync(jsStr(op['seat'])).toJson());
        break;
      case 'intent':
        steps.add(plansJson(h.intent(jsStr(op['seat']), asMap(op['msg']))));
        break;
      case 'rollback':
        steps.add(h.rollback((op['before'] as num).toInt()).toJson());
        break;
      case 'rollbackPlan':
        steps.add(plansJson(h.rollbackPlan((op['before'] as num).toInt())));
        break;
      case 'setStatus':
        steps.add(plansJson(h.setStatus(jsStr(op['s']))));
        break;
      case 'closeRoom':
        steps.add(plansJson(h.closeRoom()));
        break;
      case 'endSession':
        steps.add(plansJson(h.endSession()));
        break;
      case 'kick':
        steps.add(plansJson(h.kick(jsStr(op['seat']))));
        break;
      case 'nextTurn':
        steps.add(plansJson(h.nextTurn()));
        break;
      case 'applyAction':
        steps.add(plansJson(h.applyAction(
          jsStr(op['seat']),
          op['p'] == null ? <String, Object?>{} : asMap(op['p']),
        )));
        break;
      case 'save':
        saveOut = h.save();
        steps.add(null);
        break;
      default:
        throw ArgumentError('未知 host op ${op['op']}');
    }
  }
  return <String, Object?>{
    'steps': steps,
    'state': h.state,
    'logSeq': h.log.seq,
    'log': h.log.items
        .map((r) => <String, Object?>{
              'seq': r.seq,
              't': r.evt.t,
              'vis': r.evt.vis,
              'to': r.evt.to,
            })
        .toList(),
    'warnings': h.warnings.map((w) => w.toJson()).toList(),
    'snapshotSeqs': h.snapshots.map((s) => s.seq).toList(),
    'roundStarts': h.roundStarts,
    'save': saveOut,
    'saveKeys': saveOut?.keys.toList(),
  };
}

/// 收集 `actual` 与 `expected` 的**全部差异路径**（与比较器的 `$.a.b[2].c` 同语法）。
///
/// 这是复核侧的独立实现（不复用生产比较器），用来做「一条不多、一条不少」的
/// 白名单消费量核算。规则：
///   · 键只在单侧存在 → 记该键的完整路径（对应比较器的键集合差集）；
///   · 数组长度不同 → 记数组自身的路径（比较器同样在此处 fail，不再逐个下标）；
///   · 标量不等 / 类型不同 → 记该标量路径。
void collectDiffPaths(
  Object? actual,
  Object? expected,
  String path,
  Set<String> out,
) {
  if (expected is Map) {
    if (actual is! Map) {
      out.add(path);
      return;
    }
    final ek = expected.keys.map((k) => '$k').toSet();
    final ak = actual.keys.map((k) => '$k').toSet();
    for (final k in ek.difference(ak)) {
      out.add('$path.$k');
    }
    for (final k in ak.difference(ek)) {
      out.add('$path.$k');
    }
    for (final k in ek.intersection(ak)) {
      collectDiffPaths(actual[k], expected[k], '$path.$k', out);
    }
    return;
  }
  if (expected is List) {
    if (actual is! List) {
      out.add(path);
      return;
    }
    if (actual.length != expected.length) {
      out.add(path);
      return;
    }
    for (var i = 0; i < expected.length; i++) {
      collectDiffPaths(actual[i], expected[i], '$path[$i]', out);
    }
    return;
  }
  if (actual != expected) out.add(path);
}
