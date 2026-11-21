// ============================================================
// ai_rp_prompt.dart — AI RP 的提示词构造与结果清洗
//
// 对应旧版 `room-ui.js:5313 cleanRpText` + `:5328 buildRpMessages`。
// 纯函数、零 Flutter 依赖 —— prompt 是最需要单测的地方（它决定 AI 输出
// 的质量与安全性），但真跑一遍要几十秒还要花 token。
//
// ★ 与旧版的一处刻意差异：上下文用 `state.chats` 而**不是** `state.logs`。
//   原因有两条：
//     1. K3 红线：`logs` 的 `p` 可能带明文，拼进 prompt 就等于发给了第三方
//        （即使 Q1 已脱敏，也不该把「脱敏后的日志」当素材外发）；
//     2. 裁剪口径：玩家视角的 `logs` 与 KP 不一致，用 `chats` 才是两边都
//        看得见、语义也对的「桌上最近发生了什么」。
//
// ★ 「只填输入框、不自动发送」是硬约束（PRD P1-12）：
//   这里只负责产出文本，发送仍由玩家自己点。
// ============================================================

import '../../domain/js_compat.dart' show asList, asMap;
import 'room_text.dart' show roomText;

/// 清洗模型输出：去掉常见的包装（「RP：」前缀、代码块、外层引号）。
///
/// 与旧版逐条对齐。模型很爱加这四类东西，不清洗就会出现
/// 聊天框里带着 `RP：` 或者整段被 ``` 包住。
String cleanRpText(Object? raw) {
  var x = roomText(raw).trim();
  // 「RP：」「角色扮演：」这类前缀
  x = x.replaceFirst(RegExp(r'^\s*(RP|rp|角色扮演)\s*[:：]\s*'), '');
  // 代码块围栏（``` 开头到第一个换行，以及结尾的 ```）
  x = x.replaceFirst(RegExp(r'^```[\s\S]*?\n'), '');
  x = x.replaceFirst(RegExp(r'```$'), '');
  // 整段被一对引号包住时剥掉（只剥一层，且长度要够，避免把一句话的引号吃掉）
  const pairs = <List<String>>[
    <String>['「', '」'],
    <String>['“', '”'],
    <String>['"', '"'],
    <String>["'", "'"],
  ];
  for (final p in pairs) {
    final a = p[0];
    final b = p[1];
    if (x.length > 2 && x.startsWith(a) && x.endsWith(b)) {
      x = x.substring(1, x.length - 1).trim();
    }
  }
  return x.trim();
}

/// 组装提示词：角色底稿 + 场景 + 最近聊天，交给模型写成一段 RP。
///
/// [me] 是**自己那条成员记录**（含 `sheet`）；[state] 是房间权威态快照。
/// 两者都只读，不改。
List<Map<String, String>> buildRpMessages({
  required bool isKp,
  required Map<String, Object?> me,
  required Map<String, Object?> state,
  required String idea,
}) {
  final sheet = asMap(me['sheet']);
  final scene = asMap(state['scene']);
  final lines = <String>[];

  // ---- 角色底稿
  final name = roomText(sheet['name']);
  if (name.isNotEmpty) {
    final occ = roomText(sheet['occupation']);
    lines.add('角色姓名：$name${occ.isEmpty ? '' : '（$occ）'}');
  }
  final status = asMap(sheet['status']);
  if (status['currentHP'] != null || status['currentSAN'] != null) {
    final hp = status['currentHP'] ?? '?';
    final maxHp = roomText(status['maxHP']);
    final san = status['currentSAN'] ?? '?';
    final body = roomText(status['body']);
    lines.add(
      '当前状态：HP $hp${maxHp.isEmpty ? '' : '/$maxHp'}'
      '，SAN $san'
      '${body.isEmpty || body == '正常' ? '' : '，身体：$body'}',
    );
  }
  final mental = asList(sheet['mental'])
      .map(roomText)
      .where((String s) => s.isNotEmpty)
      .toList();
  if (mental.isNotEmpty) lines.add('精神状态：${mental.join('、')}');

  // ---- 场景
  final title = roomText(scene['title']);
  if (title.isNotEmpty) lines.add('当前场景：$title');
  final desc = roomText(scene['desc']);
  if (desc.isNotEmpty) lines.add('场景说明：${_clip(desc, 200)}');

  // ---- 最近的桌上对话（见文件头：用 chats 不用 logs）
  final recent = asList(state['chats'])
      .map(asMap)
      .toList()
      .reversed // 最新的在最后几条，取尾部
      .take(5)
      .toList()
      .reversed
      .map((Map<String, Object?> c) => roomText(c['text']).trim())
      .where((String s) => s.length > 2)
      .toList();
  if (recent.isNotEmpty) {
    lines.add('最近的桌上对话：\n${recent.map((String s) => '· $s').join('\n')}');
  }

  const sys =
      '你是一位资深《克苏鲁的呼唤》第 7 版守秘人，也是一名擅长角色扮演的写手。\n'
      '任务：把玩家给出的「想法」改写成一段符合角色设定与世界观的简体中文 RP 文本。\n'
      '要求：\n'
      '1) 用角色的口吻说话、行动、思考，体现其性格、职业与时代感，绝不跳出角色；\n'
      '2) 60–180 字，1–3 句话，克制、有画面感，避免堆砌形容词；\n'
      '3) 不写掷骰、数值、规则术语，不替守秘人宣布「成功/失败」的裁定；\n'
      '4) 只输出这段 RP 文字本身：不要解释、不要加引号、不要写「好的」「以下是」这类开场。';

  final role = isKp
      ? '我是守秘人（KP）：请写成场景描写 / NPC 的台词与反应（也可以是某次检定的叙事化结果）。\n'
      : '我是玩家：请以我的调查员身份行动与发言。\n';
  final context = lines.isEmpty ? '' : '${lines.join('\n')}\n';
  final usr = '$role$context我的想法：${idea.trim()}';

  return <Map<String, String>>[
    <String, String>{'role': 'system', 'content': sys},
    <String, String>{'role': 'user', 'content': usr},
  ];
}

/// 截断到 [n] 个字符（不切碎代理对）。
String _clip(String s, int n) =>
    s.length <= n ? s : '${s.substring(0, n)}…';
