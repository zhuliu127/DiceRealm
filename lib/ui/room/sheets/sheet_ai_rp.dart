// ============================================================
// sheets/sheet_ai_rp.dart — AI RP 生成弹层（PRD P1-12）
//
// 用户在聊天输入行点魔棒图标 → 写一句「我想做什么」→ 生成一段 RP 文本 →
// **只填回输入框**，玩家自己改完再点发送。
//
// ★ 「不自动发送」是硬约束，原因不只是保守：
//   模型输出可能带设定错误、可能替 KP 宣布了裁定、可能 OOC。
//   自动发出去就等于替玩家做了发言决定，而且已经进了所有人可见的 chats。
//   「只填输入框」把最终决定权留在人手里。
//
// ★ 与旧版一致的三处默认值（都是为 RP 调过的）：
//   temperature 0.85（比车卡 0.9 稍稳，RP 要克制）、maxTokens 1200、
//   timeout 60s（RP 比车卡短，等太久反而折磨）。
//
// ★ AI 未配置时给的是「去设置里填」的明确指引，不是「生成失败」。
// ★ 纯 UI：不碰权威态、零发包（结果只回填本机输入框）。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap;
import '../../../domain/room_types.dart' show RoomRole;
import '../../../net/ai_client.dart' show AiClient, AiConfig, AiErrorKind, AiException;
import '../../../repo/repo_scope.dart' show SettingsScope;
import '../ai_rp_prompt.dart' show buildRpMessages, cleanRpText;
import '../room_text.dart' show roomText;
import '../room_scope.dart' show RoomScope;
import '../widgets/room_panel_kit.dart' show RoomTap;
import 'room_sheet.dart' show showRoomSheet;

/// AI RP 弹层内部稳定 key。
class AiRpKeys {
  const AiRpKeys._();

  static const Key root = ValueKey<String>('aiRp/root');
  static const Key idea = ValueKey<String>('aiRp/idea');
  static const Key generate = ValueKey<String>('aiRp/generate');
  static const Key status = ValueKey<String>('aiRp/status');
  static const Key hint = ValueKey<String>('aiRp/hint');
}

/// 打开 AI RP 弹层。
///
/// [onFilled] 拿到清洗后的 RP 文本 —— 调用方负责填进聊天输入框并聚焦，
/// **不要**在这里发送。
/// [client] 仅测试注入；生产从设置现建。
Future<void> openAiRpSheet(
  BuildContext context, {
  required void Function(String text) onFilled,
  AiClient? client,
}) => showRoomSheet<void>(
  context: context,
  title: 'AI RP',
  body: (BuildContext _) => AiRpSheet(onFilled: onFilled, client: client),
);

/// AI RP 弹层主体。
class AiRpSheet extends StatefulWidget {
  const AiRpSheet({super.key, required this.onFilled, this.client});

  final void Function(String text) onFilled;
  final AiClient? client;

  @override
  State<AiRpSheet> createState() => _AiRpSheetState();
}

class _AiRpSheetState extends State<AiRpSheet> {
  final TextEditingController _idea = TextEditingController();
  bool _busy = false;
  String _status = '';

  /// 现建或注入的客户端。生产路径**每次调用现读设置**（`AiConfig` 由
  /// configProvider 提供），所以玩家改完 Key 立刻生效。
  AiClient? _client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.client != null) {
      _client = widget.client;
      return;
    }
    if (_client != null) return;
    final settings = SettingsScope.read(context);
    _client = AiClient(
      configProvider: () => AiConfig(
        base: settings.aiBase,
        model: settings.aiModel,
        key: settings.aiKey,
      ),
    );
  }

  @override
  void dispose() {
    _idea.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_busy) return;
    final scope = RoomScope.read(context);
    final idea = _idea.text.trim();
    if (idea.isEmpty) {
      scope.local.showNotice('先写一句你想做什么');
      return;
    }
    final client = _client;
    if (client == null) {
      setState(() => _status = 'AI 模块没准备好，请重开这个弹层');
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在让 AI 写…（模型较慢时可能要十几秒）';
    });

    try {
      final messages = buildRpMessages(
        isKp: scope.session.role == RoomRole.kp,
        me: _meOf(scope),
        state: scope.session.state,
        idea: idea,
      );
      final result = await client.chat(
        messages,
        // 与旧版一致：RP 比车卡稍稳（0.85），长度与超时也按 RP 调过。
        temperature: 0.85,
        maxTokens: 1200,
        timeout: const Duration(seconds: 60),
      );
      final text = cleanRpText(result.text);
      if (text.isEmpty) {
        throw AiException(
          AiErrorKind.emptyContent,
          '模型返回了空内容，请再试一次',
        );
      }
      if (!mounted) return;
      widget.onFilled(text);
      // 只回填、不发送 —— 提示里必须说清这一点，否则用户会以为已经发出去了。
      scope.local.showNotice('已填入聊天框，改完再点「发送」');
      Navigator.of(context).maybePop();
      return;
    } on AiException catch (e) {
      setState(() => _status = e.message);
    } catch (e) {
      setState(() => _status = '生成失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 自己那条成员记录（`sheet` 用来自我介绍）。
  Map<String, Object?> _meOf(RoomScope scope) {
    final seat = scope.session.seat;
    for (final m in asList(scope.session.state['members'])) {
      // 用 roomText 不用 jsStr：这是 UI 层取值，seat 为 null 时应当当作空串
      // 去比较（jsStr 会给字面 'null'，可能误匹配一个叫 'null' 的座位）。
      if (roomText(asMap(m)['seat']) == seat) return asMap(m);
    }
    return const <String, Object?>{};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = RoomScope.of(context);
    final isKp = scope.session.role == RoomRole.kp;

    return Column(
      key: AiRpKeys.root,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          isKp
              ? '写一句你想描写的东西，AI 会写成场景描写或 NPC 反应。'
                    '结果只填进聊天框，不会自动发送。'
              : '写一句你想做的事，AI 会以你的调查员身份写成 RP。'
                    '结果只填进聊天框，不会自动发送。',
          key: AiRpKeys.hint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.secondary),
        ),
        const SizedBox(height: 8),
        TextField(
          key: AiRpKeys.idea,
          controller: _idea,
          enabled: !_busy,
          minLines: 3,
          maxLines: 5,
          style: theme.textTheme.bodySmall,
          decoration: InputDecoration(
            isDense: true,
            hintText: isKp
                ? '例如：玩家撬锁失败，我要写一下门后传来的动静'
                : '例如：我想先听听门后有没有动静，再慢慢推开',
            border: const OutlineInputBorder(),
          ),
        ),
        if (_status.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            _status,
            key: AiRpKeys.status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _busy
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            RoomTap(
              key: AiRpKeys.generate,
              icon: Icons.auto_awesome,
              label: _busy ? '生成中…' : '生成 RP 内容',
              hint: _busy ? '稍等' : '让 AI 写一段，只填进输入框',
              enabled: !_busy,
              minSize: const Size(150, 42),
              onTap: _generate,
            ),
          ],
        ),
      ],
    );
  }
}
