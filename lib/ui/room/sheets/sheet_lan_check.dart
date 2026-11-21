// ============================================================
// sheets/sheet_lan_check.dart — 局域网自检弹层
//
// 为什么需要它：局域网连不上时，用户能看到的只有「对方没反应」。
// 而这个功能的价值是**把「连不上」拆成几个可行动的原因**：
//   · 本机没起服务      → 先建房
//   · 服务活着但这个 IP 不通 → AP 隔离 / 防火墙 / 选错网卡
//   · 两次都超时        → 防火墙静默丢包
//   · 两次都失败        → 服务崩了 / 端口被占
//
// ★ 诊断要真发 HTTP，widget 测试里会卡在 FakeAsync —— 所以构造函数
//   允许注入 `diagnose`，测试传桩（生产路径走 `diagnoseLan`）。
// ★ 只读：不改任何权威态，零发包。
// ============================================================

import 'package:flutter/material.dart';

import '../../../net/lan_diagnose.dart';
import '../room_scope.dart' show RoomScope;
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import 'room_sheet.dart' show showRoomSheet;

/// 自检弹层内部稳定 key。
class LanCheckKeys {
  const LanCheckKeys._();

  static const Key root = ValueKey<String>('lanCheck/root');
  static const Key loading = ValueKey<String>('lanCheck/loading');
  static const Key verdict = ValueKey<String>('lanCheck/verdict');
  static const Key rerun = ValueKey<String>('lanCheck/rerun');
  static const Key ifaces = ValueKey<String>('lanCheck/ifaces');
  static const Key advice = ValueKey<String>('lanCheck/advice');

  /// 单步结果（`lanCheck/step/<序号>`）。
  static Key step(int i) => ValueKey<String>('lanCheck/step/$i');

  /// 单块网卡（`lanCheck/iface/<地址>`）。
  static Key iface(String addr) => ValueKey<String>('lanCheck/iface/$addr');
}

/// 诊断函数签名（便于测试注入桩）。
typedef LanDiagnoseFn = Future<LanDiagResult> Function(String lanBase);

/// 打开「局域网自检」弹层。
///
/// [diagnose] 不传则走真实探测；测试必须注入。
Future<void> openLanCheckSheet(
  BuildContext context, {
  LanDiagnoseFn? diagnose,
}) => showRoomSheet<void>(
  context: context,
  title: '局域网自检',
  body: (BuildContext _) => LanCheckSheet(diagnose: diagnose),
);

/// 自检弹层主体：打开即跑一次，可重跑。
class LanCheckSheet extends StatefulWidget {
  const LanCheckSheet({super.key, this.diagnose});

  final LanDiagnoseFn? diagnose;

  @override
  State<LanCheckSheet> createState() => _LanCheckSheetState();
}

class _LanCheckSheetState extends State<LanCheckSheet> {
  LanDiagResult? _result;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    // 首帧之后再跑：`initState` 里直接发起异步 I/O 可以，但 setState
    // 要等挂载完成；用 post-frame 最稳。
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() => _running = true);
    final base = RoomScope.read(context).session.lanBase ?? '';
    final fn = widget.diagnose ?? (String b) => diagnoseLan(lanBase: b);
    LanDiagResult r;
    try {
      r = await fn(base);
    } catch (e) {
      // 自检本身出错不能把弹层打崩 —— 降级成一条失败步骤。
      r = LanDiagResult(
        verdict: LanVerdict.lanDead,
        steps: <LanDiagStep>[
          LanDiagStep(name: '自检异常', ok: false, text: '$e'),
        ],
      );
    }
    if (!mounted) return;
    setState(() {
      _result = r;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;

    return Column(
      key: LanCheckKeys.root,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_running)
          Padding(
            key: LanCheckKeys.loading,
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: <Widget>[
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 10),
                Text('正在探测…', style: theme.textTheme.bodySmall),
              ],
            ),
          )
        else if (r != null) ...<Widget>[
          // ---- 结论：一句话说清「怎么回事」
          Container(
            key: LanCheckKeys.verdict,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: r.ok
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  r.ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: r.ok
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.verdictText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: r.ok
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ---- 分步结果：失败的那一步就是问题所在
          SectionBox(
            title: '探测步骤',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < r.steps.length; i++)
                  Padding(
                    key: LanCheckKeys.step(i),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          r.steps[i].ok
                              ? Icons.check
                              : Icons.remove_circle_outline,
                          size: 15,
                          color: r.steps[i].ok
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                r.steps[i].name,
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                r.steps[i].text,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ---- 网卡列表：选错网卡是最难自查的问题，必须摆出来
          if (r.ifaces.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            SectionBox(
              key: LanCheckKeys.ifaces,
              title: '网卡（该用哪块）',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final i in r.ifaces)
                    Padding(
                      key: LanCheckKeys.iface(i.address),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${i.chosen ? '▸ ' : '   '}${i.name} · ${i.address}'
                        '${i.usable ? '' : '（不可用：链路本地或 VPN 虚拟网卡）'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: i.chosen
                              ? theme.colorScheme.primary
                              : i.usable
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.error,
                          fontWeight: i.chosen ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '▸ 是实际选中的那块。分高的更适合局域网。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ---- 建议：不是「失败了」，而是「你该做什么」
          if (r.advice.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            SectionBox(
              key: LanCheckKeys.advice,
              title: '下一步',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final a in r.advice)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('· $a', style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              RoomTap(
                key: LanCheckKeys.rerun,
                icon: Icons.refresh,
                label: '重新探测',
                hint: '改完网络设置后点这里',
                enabled: !_running,
                minSize: const Size(110, 40),
                onTap: _run,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
