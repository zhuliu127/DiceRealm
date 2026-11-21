// ============================================================
// sheets/card_sheet_payload.dart — 角色卡 → 房间角色卡摘要（**纯 Dart**）
//
// 房间侧的角色卡摘要（`sheet`）与单机车卡共用同一套 status 语义，
// 但键名不同：车卡是 `attributes` / `characterName`，房间侧是 `attrs` / `name`。
// 这里只做**键名搬运**，字段白名单 / 数值夹取 / 默认值一律交给 domain 的
// `sanitizeSheet`（`raSanitizeSheet` 的唯一入口）—— UI 不另立一套口径。
//
// ★ 纯函数、零 UI 框架依赖：弹层只负责画，键名搬运与白名单都在这里。
//   放在 sheets/ 而不是 view/：view/ 是「房间 state 的只读派生」，
//   本文件是「车卡 → 房间卡」的载荷搬运，两者不是一类。
// ============================================================

import '../../../domain/avatar.dart' show AvatarSpec, specFromSvg, specOf;
import '../../../domain/character.dart' show Character;
import '../../../domain/js_compat.dart' show asList, asMap, jsTruthy;
import '../../../domain/room_model_save.dart' show sanitizeSheet;
import '../../../repo/avatar_store.dart' show localAvatarRel;
import '../../../repo/avatar_thumb.dart' show avatarThumbEncoder;
import '../../widgets/auto_avatar_png.dart' show autoAvatarPngEncoder;

/// 数值兜底：`a` 是数字就用它，否则用 `b`，都不是则 0。
num _num(Object? a, [Object? b]) {
  if (a is num) return a;
  if (b is num) return b;
  return 0;
}

/// 职业名：车卡里有两个来源（`raw.occupationName` 是车卡器写下的快照，
/// `basicInfo.occupation` 是玩家手填的），谁有值用谁，都没有就空串。
String _occupationName(Character card) {
  final a = card.raw['occupationName'];
  if (a is String && a.trim().isNotEmpty) return a;
  final b = card.basicInfo['occupation'];
  if (b is String && b.trim().isNotEmpty) return b;
  return '';
}

/// 把一张车卡搬成房间角色卡摘要（供 `INTENT.CHAR` 的 `sheet` 字段用）。
///
/// 输出形状 = domain 白名单的产物，不是这里手写的字段表：
/// 这里只负责「哪个源键对应哪个目标键」。
Map<String, Object?> cardToRoomSheet(Character card) {
  final status = card.status;
  final derived = card.derivedStats;
  final mentalRaw = status['mental'];
  final mental = mentalRaw is List
      ? mentalRaw
      : <Object?>[if (mentalRaw is String && mentalRaw.isNotEmpty) mentalRaw];

  final candidate = <String, Object?>{
    'name': card.characterName,
    'avatar': card.raw['avatar'],
    'attrs': card.attributes,
    // 技能行：房卡要 `total`，老卡可能只有 `value`
    'skills': <Object?>[
      for (final raw in card.skills)
        <String, Object?>{
          'name': asMap(raw)['name'],
          'total': asMap(raw)['total'] ?? asMap(raw)['value'],
        },
    ],
    // 车卡 status 与房卡 status 同语义：现值 / 上限 / 身体 / 濒死 / 昏迷
    'status': <String, Object?>{
      'currentHP': _num(status['currentHP'], derived['maxHP']),
      'maxHP': _num(status['maxHP'], derived['maxHP']),
      'currentMP': _num(status['currentMP'], derived['maxMP']),
      'maxMP': _num(status['maxMP'], derived['maxMP']),
      'currentSAN': _num(status['currentSAN'], derived['maxSAN']),
      'maxSAN': _num(status['maxSAN'], derived['maxSAN']),
      'currentLuck': _num(status['currentLuck']),
      'body': status['body'],
      'dying': status['dying'],
      'unconscious': status['unconscious'],
    },
    'mental': mental,
    'madness': card.madnessList,
    'items': asList(card.raw['items']),
    'weapons': asList(card.raw['weapons']),

    // ---- P10 第 1 期 B1：让 KP 审卡看到「完整角色卡」----
    // 与候选卡 / 名册卡展示的是同一批**公开**字段（`summary_card.dart` 的
    // 同名来源），不含 `privates` / 明文 `p`；真正的截断与合法性仍由
    // domain 的 `sanitizeSheet` 白名单说了算。
    'gender': card.basicInfo['gender'],
    'age': card.basicInfo['age'],
    'era': asMap(card.basicInfo)['era'] == '自定义'
        ? card.basicInfo['eraCustom']
        : card.basicInfo['era'],
    'residence': card.basicInfo['residence'],
    'birthplace': card.basicInfo['birthplace'],
    'occupation': _occupationName(card),
    'world': card.raw['worldLabel'] ?? card.raw['worldName'] ?? '',
    'look': card.background['description'],
    'background': <String, Object?>{
      'ideology': card.background['ideology'],
      'significantPeople': card.background['significantPeople'],
      'meaningfulPlaces': card.background['meaningfulPlaces'],
      'treasuredPossessions': card.background['treasuredPossessions'],
      'traits': card.background['traits'],
      'wounds': card.background['wounds'],
      'phobias': card.background['phobias'],
    },
    'history': asList(card.raw['history']),
    'armors': asList(card.raw['armors']),
    'assets': card.assets,
    'eduProgress': card.eduProgress,
  };

  // ★ 键名搬完就交给 domain：白名单、夹取、默认值都在那边。
  return sanitizeSheet(candidate);
}

/// 车卡在列表里的展示名：没填名字时退到「未命名」。
String cardDisplayName(Character card) {
  final name = card.characterName.trim();
  if (name.isNotEmpty) return name;
  final id = card.id.trim();
  return id.isEmpty ? '未命名角色' : '未命名角色（$id）';
}

/// 绑卡上报用的 `sheet`：在 [cardToRoomSheet] 的基础上把头像换成**跨设备缩略图**。
///
/// 对齐老 APP `room-ui.js#reportSheet`（v2.13.7）：
///   · 先把头像缩成 64px 正方形缩略 dataURI（[avatarThumbEncoder]，默认实现读
///     本机 `avatars/<cardId>.png` 再压）；
///   · 有缩略图 → `sheet.avatar = thumb`；
///   · **没有 → 删掉整个 `avatar` 键**（不是留空串）—— 空串也会进广播体积，
///     而老 APP 的注释写得很直白：「没有头像 → 不占广播体积」。
///
/// 为什么必须在这里换：`cardToRoomSheet` 里 `avatar` 是**本机相对路径**
/// （`avatars/xxx.png`），domain 的 `sanitizeSheet` 只收
/// `data:image/(png|jpe?g|webp);base64,` 且 ≤20000 字符，于是它会被白名单
/// 判成 `''` —— 这正是「远端玩家栏永远只有首字圆点」的真因。
Future<Map<String, Object?>> cardToRoomSheetForReport(Character card) async {
  final sheet = cardToRoomSheet(card);
  String thumb = '';
  try {
    // ★ P10 第 3 期 B：传**原始值**，不要先过 `localAvatarRel`。
    //   `avatarThumbOf` 自己就能解 `data:image/...;base64,`；如果这里先筛成
    //   「只认本机相对路径」，卡里已经是一条合法 PNG dataURI 时会被判成
    //   「没有头像」→ 删键，把本来可广播的缩略图丢掉（导入/迁移会踩）。
    thumb = await avatarThumbEncoder(card.raw['avatar']);
  } catch (_) {
    // 缩略图是「锦上添花」：生成失败也必须能正常绑卡
    thumb = '';
  }
  // ★ P10 第 3 期 A 批（补齐上一批欠账）：**没有上传头像的玩家**也要有一张
  //   能跨设备广播的头像。卡里存的自动头像是 svg dataURI，而广播判据只收
  //   png/jpeg/webp、引擎也不解码 svg —— 以前这里直接走到
  //   `sheet.remove('avatar')`，别人设备上永远只有首字圆点。
  //   现在补一步：把自动头像**同一份视觉参数**渲染成 PNG dataURI。
  if (thumb.isEmpty) {
    final autoSpec = autoAvatarSpecOf(card);
    if (autoSpec != null) {
      try {
        thumb = await autoAvatarPngEncoder(autoSpec);
      } catch (_) {
        thumb = '';
      }
    }
  }
  if (thumb.isEmpty) {
    // 仍然不放：裁到「没有可广播头像」就删键，不占广播体积
    sheet.remove('avatar');
  } else {
    sheet['avatar'] = thumb;
  }
  return sheet;
}

/// 这张卡该用哪一份自动头像视觉参数（null = 没有可用的自动头像）。
///
/// ① 卡里已有自动头像 SVG → **反解**出原来的取色/转角/点数（与老卡逐像素
///    同源，连 `warm` 调色都不丢）；
/// ② 卡里没有头像、但有名字 → 按名字现算一份（与 `avatar.ensure` 同源）。
AvatarSpec? autoAvatarSpecOf(Character card) {
  final raw = card.raw['avatar'];
  final fromSvg = specFromSvg(raw);
  if (fromSvg != null) return fromSvg;
  if (jsTruthy(raw)) {
    // 是玩家上传的图片 / 本机相对路径 —— 交给上方缩略链路，这里不越权生成
    final isLocalPath = localAvatarRel(raw) != null;
    if (isLocalPath) return null;
    if (!raw.toString().startsWith('data:image/')) {
      // 未知取值（emoji / 文本等旧占位）：按名字生成一张自动头像
      return specOf(card.characterName);
    }
    return null;
  }
  return specOf(card.characterName);
}
