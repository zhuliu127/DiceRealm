// ============================================================
// ai_create.dart — AI 车卡的「有网络」部分：调模型 → 重试 → 落地成卡
//
// 对应 `core/ai.js#AIGen.makeCharacter`。
//
// 🎯 整条链的核心不变式，写在这里是为了让它不可能被绕过：
//     模型只提供**创意字段**（是谁 / 什么职业 / 长什么样 / 有什么故事）；
//     属性、职业点、技能分配、装备、资产**全部**由 `preset_gen` 的规则引擎产出。
//   所以哪怕模型返回的是垃圾（缺字段、类型错、职业名瞎编、属性超范围），
//   落地出来的也一定是一张能过 `validate` / `checkList` 的卡 ——
//   因为规则引擎根本不看模型给的数值（除了「属性」这一项，而且还要过
//   `attrsFromAi` 的宽松区间检查 + 上限压缩）。
//
// 自适应重试（旧版踩过的坑，照抄）：
//   第一发用 6000 token。若 finish_reason=length（正文被硬截断）或解析失败，
//   用 16000 再发一次。推理型模型第一发经常把额度花在思考链上，
//   自动重发能省掉用户反复点「重新生成」。
// ============================================================

import '../domain/ai_caps.dart';
import '../domain/ai_gen.dart';
import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../domain/preset_gen.dart' as preset;
import '../domain/secret_mask.dart';
import 'ai_client.dart';

/// 一次 AI 车卡的结果
class AiCreateResult {
  const AiCreateResult({
    required this.character,
    required this.profile,
    required this.raw,
    required this.caps,
    required this.attrScaled,
  });

  final Character character;

  /// 清洗后的 profile（就是喂给规则引擎的那份）
  final Map<String, Object?> profile;

  /// 模型返回的原始 JSON（可能不是 Map —— 解析失败时已经抛过了）
  final Object? raw;

  /// 本次生效的房规上限
  final AiCaps caps;

  /// 模型给的属性超过总和上限，被本地按比例压过
  final bool attrScaled;
}

/// AI 车卡服务：把「模型」和「规则引擎」缝在一起
class AiCreateService {
  AiCreateService({required this.client, AiCaps Function()? capsProvider})
    : _caps = capsProvider ?? (() => capsFromSettings(preset.presetSettings));

  final AiClient client;
  final AiCaps Function() _caps;

  /// 中断当前生成（界面上的「取消」）
  void cancel() => client.cancel();

  /// 一句话 → 一张完整可用的角色卡
  ///
  /// @param desc 玩家的自然语言描述
  /// @param settingId 界面里显式选的世界设定（优先于模型自己选的）
  /// @param caps 覆盖本次的上限（不传则读设置）
  /// @param onStage 阶段回调 —— 界面据此显示「正在用更大额度重试…」
  Future<AiCreateResult> makeCharacter(
    String desc, {
    Object? settingId,
    AiCaps? caps,
    void Function(String message)? onStage,
  }) async {
    if (desc.trim().isEmpty) {
      throw AiException(AiErrorKind.badRequest, '先写一句你想创建什么样的调查员');
    }
    final c0 = caps ?? _caps();
    final messages = <Map<String, String>>[
      <String, String>{'role': 'system', 'content': aiSystemPrompt},
      <String, String>{'role': 'user', 'content': buildPrompt(desc, caps: c0)},
    ];

    var meta = const AiChatMeta();

    Future<String> attempt(int maxTokens) async {
      final r = await client.chat(
        messages,
        temperature: 0.9,
        maxTokens: maxTokens,
        onMeta: (m) => meta = m,
      );
      return r.text;
    }

    // ---- 第一发 ----
    final text1 = await attempt(aiDefaultMaxTokens);
    final meta1 = meta;
    Object? raw;
    String? parseErr;
    try {
      raw = parseJson(text1);
    } on AiGenException catch (e) {
      parseErr = e.message;
    }

    // 没被截断且解析成功 → 直接用
    if (raw != null && !meta1.truncated) {
      return _land(raw, desc, c0, settingId);
    }

    // ---- 被截断 或 解析失败 → 大额度重发一次 ----
    onStage?.call(
      meta1.truncated
          ? '模型回复被截断（思考链占用了太多额度），正在用更大额度重试…'
          : '模型返回的 JSON 不完整，正在重试…',
    );

    final text2 = await attempt(aiRetryMaxTokens);
    final meta2 = meta;
    try {
      raw = parseJson(text2);
    } on AiGenException catch (e) {
      /* 两次都不行：把第一次的原因也说清楚，别只丢一句「失败」 */
      if (meta2.truncated) {
        throw AiException(
          AiErrorKind.emptyContent,
          '模型两次都没能输出完整内容（连续被额度截断）。'
          '这通常是推理型模型思考链过长所致，建议：换用非推理型模型，或把描述写短一点。',
        );
      }
      // why 来自 parseJson / AiGenException：parseJson 会把「回复开头 / 末尾」
      // 片段拼进错误文案，若网关把请求头回显进非 JSON 响应，这段文本会带
      // 明文 Key。进 UI 前统一过一遍脱敏。
      final why = maskSecrets(parseErr ?? e.message);
      throw AiException(
        AiErrorKind.badResponse,
        '模型返回的内容无法解析为角色卡（$why）。可以点「重新生成」再试一次。',
      );
    }
    return _land(raw, desc, c0, settingId);
  }

  /// 把模型给的 JSON 落到一张合法的卡上
  AiCreateResult _land(
    Object? raw,
    String desc,
    AiCaps caps,
    Object? settingId,
  ) {
    final profile = toProfile(raw);

    /* 姓名纠偏：模型对姓名有顽固偏好（反复产出同一个名字），
       空 / 命中常见重复值 / 与上一次相同 → 换成本地随机名。
       其余创意字段仍完全采信模型。 */
    profile['name'] = ensureFreshInvestigatorName(jsStr(profile['name']));

    /* 属性上限：本地二次校准。
       提示词里已经要求过一次，但模型不照做是常态 ——
       这里压缩到上限内，保证「设置了就一定不超」。 */
    final scaled = applyAttrCap(profile, caps);

    // 显式选定的设定 > 模型选的（模型可能选了个不存在的标签，preset 会兜住）
    final sid = jsTruthy(settingId) ? settingId : profile['setting'];
    final c = preset.buildFrom(profile, sid, preset.PresetOptions(caps: caps));
    if (c == null) {
      throw AiException(AiErrorKind.badResponse, '角色生成失败，请重试一次');
    }
    if (scaled) c.raw['aiAttrScaled'] = true; // 界面提示「已按上限压缩」

    final log = asList(c.raw['changeLog']);
    log.add(<String, Object?>{
      'version': 'v1.0',
      'note':
          'AI 车卡：${desc.trim().isEmpty ? '' : desc.trim().substring(0, desc.trim().length > 30 ? 30 : desc.trim().length)}',
      'at': nowMillis(),
    });
    c.raw['changeLog'] = log;

    return AiCreateResult(
      character: c,
      profile: profile,
      raw: raw,
      caps: caps,
      attrScaled: scaled,
    );
  }
}
