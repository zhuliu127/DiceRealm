// ============================================================
// test/qa_p4_fresh_oracle_test.dart — 独立复核：**现造**旧版对照
//
// 与 `room_sequences_test.dart` 的区别不是「多跑几例」，而是**谁选的场景**：
// 这里的 6 段随机 hostScript 由 `tool/qa/qa_p4_fresh_oracle.js` 用固定种子生成，
// 覆盖 emit/syncFor/intent/rollback/kick/close/end/save 的随机交织，
// 期望值由旧版 room-model.js 现算（不是工程师挑好的 121 例）。
// 严格逐字段比较 + randUsed 恒等（本对照不消耗随机数）。
//
// ⚠️ 重新生成：`node tool/qa/qa_p4_fresh_oracle.js`（种子固定，结果可复现）
// ============================================================

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/room_model_host_core.dart';
import 'package:dice_realm/domain/room_model_host_intent.dart';
import 'package:dice_realm/domain/room_model_rollback.dart';
import 'package:dice_realm/domain/room_model_save.dart';
import 'package:dice_realm/domain/room_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/room_fakes.dart';
import 'support/room_oracle.dart';

List<Map<String, Object?>> _plans(List<SendPlan> out) =>
    out.map((s) => s.toJson()).toList();

void main() {
  final fixture = RoomOracleFixture.load('qa_p4_fresh_oracle.json');

  fixture.run(<String, Object? Function(Map<String, Object?> args)>{
    'hostScript': (a) {
      final h = RoomHost(roomHostOpts(
        meta: asMap(a['meta']),
        snapshotEvery: (a['snapshotEvery'] as num?)?.toInt() ?? 20,
        logCap: (a['logCap'] as num?)?.toInt() ?? 400,
      ));
      final steps = <Object?>[];
      Map<String, Object?>? saveOut;
      for (final opRaw in asList(a['ops'])) {
        final op = asMap(opRaw);
        switch (jsStr(op['op'])) {
          case 'attach':
            steps.add(h.attachPeer(asMap(op['m'])).toJson());
            break;
          case 'detach':
            steps.add(_plans(h.detachPeer(jsStr(op['seat']))));
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
              'plan': jsTruthy(op['plan']) ? _plans(h.plan(rec)) : null,
            });
            break;
          case 'syncFor':
            steps.add(h.syncFor(jsStr(op['seat'])).toJson());
            break;
          case 'intent':
            steps.add(_plans(h.intent(jsStr(op['seat']), asMap(op['msg']))));
            break;
          case 'rollback':
            steps.add(h.rollback((op['before'] as num).toInt()).toJson());
            break;
          case 'setStatus':
            steps.add(_plans(h.setStatus(jsStr(op['s']))));
            break;
          case 'closeRoom':
            steps.add(_plans(h.closeRoom()));
            break;
          case 'endSession':
            steps.add(_plans(h.endSession()));
            break;
          case 'kick':
            steps.add(_plans(h.kick(jsStr(op['seat']))));
            break;
          case 'save':
            saveOut = h.save();
            steps.add(null);
            break;
          default:
            fail('未知 op: ${op['op']}');
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
    },
  });
}
