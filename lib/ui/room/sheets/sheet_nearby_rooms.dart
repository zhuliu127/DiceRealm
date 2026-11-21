// ============================================================
// sheets/sheet_nearby_rooms.dart — 附近的房间（UDP 扫描结果列表）
//
// 旧版对应 `room-ui.js:1604` 的「附近的房间」。价值在于：用户不必
// 挨个问房号，打开就能看到同一 WiFi 下正在招募的房间。
//
// ★ 弹层只负责「选一个」，不负责加入 —— 加入涉及会话创建和路由跳转，
//   由入口页统一处理（弹层返回选中的 `RoomAnnounce`）。
// ★ 扫描要真跑 UDP，widget 测试里会卡在 FakeAsync —— 构造函数允许注入
//   `scan`，测试传桩。
// ============================================================

import 'package:flutter/material.dart';

import '../../../net/lan_discovery.dart' show RoomAnnounce;
import '../room_net_factory.dart' show RoomNetFactory;
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import 'room_sheet.dart' show showRoomSheet;

/// 附近房间弹层内部稳定 key。
class NearbyKeys {
  const NearbyKeys._();

  static const Key root = ValueKey<String>('nearby/root');
  static const Key loading = ValueKey<String>('nearby/loading');
  static const Key empty = ValueKey<String>('nearby/empty');
  static const Key rerun = ValueKey<String>('nearby/rerun');

  /// 一行房间（`nearby/row/<房号>`）。
  static Key row(String code) => ValueKey<String>('nearby/row/$code');

  /// 该行的「加入」。
  static Key join(String code) => ValueKey<String>('nearby/join/$code');
}

/// 扫描函数签名（便于测试注入桩）。
typedef LanScanFn = Future<List<RoomAnnounce>> Function(Duration timeout);

/// 打开「附近的房间」。
///
/// 返回用户选中的房间；用户直接关闭则返回 `null`。
Future<RoomAnnounce?> showNearbyRoomsSheet(
  BuildContext context, {
  LanScanFn? scan,
  Duration timeout = const Duration(milliseconds: 1600),
}) => showRoomSheet<RoomAnnounce>(
  context: context,
  title: '附近的房间',
  body: (BuildContext _) => NearbyRoomsSheet(scan: scan, timeout: timeout),
);

/// 附近的房间主体。
class NearbyRoomsSheet extends StatefulWidget {
  const NearbyRoomsSheet({
    super.key,
    this.scan,
    this.timeout = const Duration(milliseconds: 1600),
  });

  final LanScanFn? scan;
  final Duration timeout;

  @override
  State<NearbyRoomsSheet> createState() => _NearbyRoomsSheetState();
}

class _NearbyRoomsSheetState extends State<NearbyRoomsSheet> {
  List<RoomAnnounce>? _rooms;
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() => _scanning = true);
    List<RoomAnnounce> rooms;
    try {
      final fn = widget.scan ?? _defaultScan;
      rooms = await fn(widget.timeout);
    } catch (_) {
      // 扫描失败按「没找到」处理 —— 用户还能手输房号，不该卡在这里。
      rooms = const <RoomAnnounce>[];
    }
    if (!mounted) return;
    setState(() {
      _rooms = rooms;
      _scanning = false;
    });
  }

  static Future<List<RoomAnnounce>> _defaultScan(Duration timeout) =>
      RoomNetFactory.nearby(timeout: timeout);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = _rooms;

    return Column(
      key: NearbyKeys.root,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_scanning)
          Padding(
            key: NearbyKeys.loading,
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: <Widget>[
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 10),
                Text('正在搜寻同一 WiFi 下的房间…', style: theme.textTheme.bodySmall),
              ],
            ),
          )
        else if (rooms == null || rooms.isEmpty)
          SectionBox(
            key: NearbyKeys.empty,
            title: '没找到房间',
            child: Text(
              '确认：① 两台设备连的是同一个 WiFi；'
              '② KP 已经「创建并进入」房间；'
              '③ WiFi 没开「AP 隔离」（访客网络通常隔离设备）。'
              '仍然找不到时，让对方把「服务地址」发给你，在加入区手输。',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          SectionBox(
            title: '找到 ${rooms.length} 间房',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final r in rooms)
                  Padding(
                    key: NearbyKeys.row(r.code),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                r.name.isEmpty ? '未命名房间' : r.name,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                '${r.code} · ${r.status == 'IN_GAME' ? '进行中' : '招募中'}'
                                ' · 玩家 ${r.players}/${r.maxPlayers}'
                                '${r.kpName.isEmpty ? '' : ' · KP ${r.kpName}'}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        RoomTap(
                          key: NearbyKeys.join(r.code),
                          icon: Icons.login,
                          label: '加入',
                          hint: '加入 ${r.code}',
                          minSize: const Size(76, 38),
                          // 进行中的房也能进（旁观/中途加入是 PRD 允许的），
                          // 但明说状态，别让用户以为能从头开始。
                          onTap: () => Navigator.of(context).pop(r),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            RoomTap(
              key: NearbyKeys.rerun,
              icon: Icons.refresh,
              label: '重新搜寻',
              hint: '再扫一次',
              enabled: !_scanning,
              minSize: const Size(110, 40),
              onTap: _run,
            ),
          ],
        ),
      ],
    );
  }
}
