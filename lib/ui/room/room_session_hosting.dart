// ============================================================
// ui/room/room_session_hosting.dart — KP 侧「本机 + 网络」双投递会话
//
// P6 接线的最小侵入点。
//
// 问题：KP 建房后，`host.intent()` 产出的 `List<SendPlan>` 原本只喂本机
//       注册的 client（LocalLoopback 的玩法）。现在还要发到网络上。
//       如果去改 `LocalLoopbackSession.pumpPlans` 本体，就等于往 P5 的
//       成熟代码里插分支 —— 一旦网络出错会连累单机玩法。
//
// 做法：继承 + 在 `super.pumpPlans()` 之后补一次网络投递。
//       · 单机路径 (super) 完全不变，网络挂了也不影响本地视角；
//       · 网络投递失败由 LanServer 内部吞掉（连接断了就不发）。
//
// 唯一风险是「泵被调两次」导致重复发包 —— 所以这里不做任何额外泵，
// 只是把同一份 plans 多投一遍到 socket。
// ============================================================

import '../../domain/room_types.dart' show SendPlan;
import '../../net/lan_room_host.dart';

import 'room_session_local.dart';

/// KP 视角 + 同时对局域网投递。
class HostingLocalSession extends LocalLoopbackSession {
  HostingLocalSession({
    required super.host,
    required super.seat,
    required super.role,
    required this.server,
    super.client,
    super.hub,
  }) {
    // ★ 让服务端收到的远端动作/加入也能刷新**本机 UI**。
    //   不挂这个的话：远端玩家进来了、发消息了，服务端数据已经变，
    //   但 KP 的界面永远停在「成员（0）」—— 真机联调时就踩到了这个。
    server.onHostPlans = pumpPlans;
  }

  final LanRoomHost server;

  /// 服务地址（界面「邀请同伴」要展示这个）。
  @override
  String get lanBase => server.base;

  /// 是否真的连了局域网（false ⇒ 只有自己能进，必须提示）。
  bool get lanWifi => server.wifi;

  int get lanPeers => server.peerCount;

  @override
  void pumpPlans(List<SendPlan> plans) {
    // 先走本机（保证单机玩法永不因网络问题退化），再发网络。
    super.pumpPlans(plans);
    server.pump(plans);
  }

  /// 房间人数/状态变化后主动推一次广播，让别人的列表立刻更新。
  void announceNow() => server.announceNow();

  /// 关房：先停网络再销毁本机会话（顺序反了会让 socket 里还留着旧连接）。
  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    await server.stop();
    super.dispose();
  }

  bool _closed = false;

  /// ★ 幂等，且**必须**在这里也发起停服务：
  ///   UI 走的是 `State.dispose()`（同步），不会 await shutdown()；
  ///   如果只靠 shutdown 停服务，页面一销毁就会留下幽灵房。
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    // 同步上下文里不方便 await，但不能不发起 —— 停服务本身是幂等的。
    server.stop();
    super.dispose();
  }
}
