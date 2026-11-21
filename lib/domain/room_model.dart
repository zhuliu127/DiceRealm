// ============================================================
// room_model.dart — P4 房间层的**单行入口**（barrel）
//
// P5/P6 只需要 `import 'package:dice_realm/domain/room_model.dart';`
// 就能拿到常量、值对象、端口、规则服务与状态机。
//
// ⚠️ 本文件只做 export，不含任何实现（避免 barrel 里出现逻辑分叉）。
// ============================================================

export 'room_ports.dart';
export 'room_rules.dart';
export 'room_types.dart';

// 状态机（D10~D21）。逐文件 export，便于 P5/P6 需要时细粒度 import。
export 'room_model_actions_combat.dart';
export 'room_model_actions_room.dart';
export 'room_model_actions_sheet.dart';
export 'room_model_client.dart';
export 'room_model_envelope.dart';
export 'room_model_host_core.dart';
export 'room_model_host_intent.dart';
export 'room_model_log.dart';
export 'room_model_reduce.dart';
export 'room_model_rollback.dart';
export 'room_model_save.dart';
export 'room_model_state.dart';
