// ============================================================
// room_model_actions_sheet.dart — S4.3 角色卡/伤势/SAN/施救动作（D19）
//
// extension RoomHostActionsSheet on RoomHost：
//   dispatchSheetAction(seat,p) + stateApply / stateSelf / stateRequest /
//   settleWounds / applyHpChange / sheetDamage / sheetSanCheck /
//   sheetTempStatus / sheetItem / sheetSanLoss / healWound / aidApply /
//   psychoAnalyze / advanceMadness / cureIndefinite / 判定助手。
//
// ⚠️ 纯 Dart：不得引入 Flutter 包、文件 I/O 或 UI 库（C1/K7）。
// ⚠️ 角色卡白名单（旧版 sanitizeSheet / sanitizeStatus）本体属 D21/S4.4；
//    本批在 D19 内以 raSanitizeSheet* 落地**动作侧调用契约**（真实的
//    逐字段白名单实现，不是替身/TODO），保证动作结算产出的 card 形状与
//    旧版一致；S4.4 落地 D21 后应收敛为单一来源。
// ⚠️ 所有权威状态变更走 emit/apply；成员表改动经 syncMembers 广播。
// ============================================================

import 'js_compat.dart';
import 'madness_state.dart' as mental_state;
import 'room_model_actions_combat.dart';
import 'room_model_actions_room.dart';
import 'room_model_host_core.dart';
import 'room_model_state.dart';
import 'room_types.dart';

// ============================================================
// 角色卡状态/摘要白名单（动作侧调用契约）
// ============================================================

/// 状态块白名单（旧版 `sanitizeStatus`，:7249-7277）。
/// `src` 为旧上报顶层（hp/mp/san/maxSAN 兜底）；`st` 为 status 块。
Map<String, Object?> raSanitizeStatus(Object? stRaw, Object? srcRaw) {
  final st = asMap(stRaw);
  final src = asMap(srcRaw);
  // 老卡一次性迁移必须在白名单收敛之前看原始 body。
  final raw = <String, Object?>{
    'body': st['body'],
    'dying': st['dying'],
    'unconscious': st['unconscious'],
    'currentHP': raPick(st['currentHP'], src['hp']),
    'hp': st['hp'],
    'maxHP': raPick(st['maxHP'], src['maxHP']),
  };
  migrateBodyStatus(raw);
  final body = cleanText(raw['body'], 8);
  return <String, Object?>{
    'currentHP': raClampNumberOrNull(raw['currentHP'], 0, 9999),
    'maxHP': raClampNumberOrNull(raw['maxHP'], 0, 9999),
    'currentMP': raClampNumberOrNull(raPick(st['currentMP'], src['mp']), 0, 9999),
    'maxMP': raClampNumberOrNull(raPick(st['maxMP'], src['maxMP']), 0, 9999),
    'currentSAN': raClampNumberOrNull(raPick(st['currentSAN'], src['san']), 0, 999),
    'maxSAN': raClampNumberOrNull(raPick(st['maxSAN'], src['maxSAN']), 0, 999),
    'currentLuck': raClampNumberOrNull(st['currentLuck'], 0, 999),
    'body': kRaBodyOk.contains(body) ? body : '正常',
    'dying': jsTruthy(raw['dying']),
    'unconscious': jsTruthy(raw['unconscious']),
  };
}

/// 角色卡摘要白名单（旧版 `sanitizeSheet`，:7297-7432）。
/// 只保留跑团真正需要的字段；数字一律夹区间，多余键直接丢弃。
Map<String, Object?> raSanitizeSheet(
  Object? pRaw,
  Map<String, Object?>? mem,
  int at,
) {
  final p = asMap(pRaw);
  final src = p['sheet'] is Map ? asMap(p['sheet']) : p;
  final avatarRaw = src['avatar'];
  final avatar = jsTruthy(avatarRaw) &&
          RegExp(r'^data:image/(png|jpe?g|webp);base64,')
              .hasMatch(jsStr(avatarRaw)) &&
          jsStr(avatarRaw).length <= 20000
      ? jsStr(avatarRaw)
      : '';

  final attrs = <String, Object?>{};
  final attrsRaw = asMap(src['attrs']);
  for (final k in kRaAttrKeys) {
    attrs[k] = raClampNumber(attrsRaw[k], 0, 999, 0);
  }

  final skills = <Object?>[];
  for (final sRaw in asList(src['skills'])) {
    if (skills.length >= 200) break;
    final s = asMap(sRaw);
    final name = cleanText(s['name'], 40);
    if (name.isEmpty) continue;
    skills.add(<String, Object?>{
      'name': name,
      'total': raClampNumber(s['total'], 0, 999, 0),
    });
  }

  final madness = <Object?>[];
  for (final mRaw in asList(src['madness'])) {
    if (madness.length >= 40) break;
    final m = asMap(mRaw);
    final type = m['type'];
    final name = cleanText(m['name'], 60);
    if (name.isEmpty) continue;
    final permanent = jsTruthy(m['permanent']);
    madness.add(<String, Object?>{
      'type': kRaMadTypes.contains(type) ? type : 'phobia',
      'name': name,
      'permanent': permanent,
      'rounds': permanent ? 0 : raClampNumber(m['rounds'], 0, 99, 0),
      'from': cleanText(m['from'], 12),
      'bg': jsTruthy(m['bg']),
      'sum': jsTruthy(m['sum']),
    });
  }

  // 精神状态（多选）：只留合法项；「正常」互斥；「永久疯狂」互斥。
  // P8：老值「不定疯狂（症状消失）」→「潜在疯狂」；「昏迷」不再属于精神状态。
  var mental = <Object?>[];
  for (final xRaw in asList(src['mental'])) {
    final x = mental_state.normalizeMentalValue(xRaw);
    if (x.isEmpty || mental.contains(x)) continue;
    mental.add(x);
  }
  if (mental.contains('正常')) {
    mental = <Object?>['正常'];
  } else if (mental.contains(kRaMentalPermanent)) {
    mental = <Object?>[kRaMentalPermanent];
  } else if (mental.contains(kRaMentalIndef) &&
      mental.contains(kRaMentalPotential)) {
    mental.remove(kRaMentalPotential); // 互斥：不定疯狂优先
  }
  if (mental.isEmpty) mental = <Object?>['正常'];

  // 背景症状归一化兜底（仅当整组都是背景条目时）。
  if (raOnlyBgSymptoms(madness) && !mental.contains(kRaMentalPermanent)) {
    final norm = <Object?>[];
    for (final x in mental) {
      if (x != '正常' &&
          x != '临时疯狂' &&
          x != kRaMentalIndef &&
          x != kRaMentalIndefFaded) {
        norm.add(x);
      }
    }
    if (!norm.contains(kRaMentalSymptom)) norm.add(kRaMentalSymptom);
    mental = norm;
  }

  final tempStatus = <Object?>[];
  for (final tRaw in asList(src['tempStatus'])) {
    if (tempStatus.length >= 20) break;
    final t = asMap(tRaw);
    final text = cleanText(t['text'], 80);
    if (text.isEmpty) continue;
    tempStatus.add(<String, Object?>{
      'text': text,
      'by': cleanText(t['by'], 8).isNotEmpty ? cleanText(t['by'], 8) : 'kp',
      'at': raClampNumber(t['at'], 0, 1e15, 0),
    });
  }

  final items = <Object?>[];
  for (final itRaw in asList(src['items'])) {
    if (items.length >= 60) break;
    final it = asMap(itRaw);
    final name = cleanText(it['name'], 40);
    if (name.isEmpty) continue;
    items.add(<String, Object?>{
      'id': cleanText(it['id'], 24),
      'name': name,
      'qty': raClampNumber(it['qty'], 0, 9999, 1),
      'note': cleanText(it['note'], 80),
    });
  }

  final weapons = <Object?>[];
  for (final wRaw in asList(src['weapons'])) {
    if (weapons.length >= 20) break;
    final w = asMap(wRaw);
    final name = cleanText(w['name'], 40);
    if (name.isEmpty) continue;
    weapons.add(<String, Object?>{
      'name': name,
      'skill': cleanText(w['skill'], 30),
      'damage': cleanText(w['damage'], 30),
      'pierce': cleanText(w['pierce'], 4) == '√' ? '√' : '×',
      'perRound': cleanText(w['perRound'], 12),
      'ammo': cleanText(w['ammo'], 20),
      'malfunction': cleanText(w['malfunction'], 8),
      'broken': jsTruthy(w['broken']),
    });
  }

  var name = cleanText(src['name'], 40);
  if (name.isEmpty) name = cleanText(p['name'], 40);
  if (name.isEmpty && mem != null && jsTruthy(mem['charName'])) {
    name = cleanText(mem['charName'], 40);
  }
  final charId = cleanText(
      jsTruthy(src['charId']) ? src['charId'] : p['id'], 64);

  // ---- P10 第 1 期 B1：审卡要能看「完整角色卡」 ----
  //
  // 上面那段白名单只覆盖**对局中会变**的字段（数值 / 技能 / 物品 / 状态），
  // 车卡器产出的 基本资料 / 背景 / 经历 / 装备与资产 / 教育进步 一直没能进入
  // 房卡摘要，于是 KP 在招募页点「详情」看到的是一张残卡。
  //
  // ★ 兼容红线（P4「旧版逐字段等价」256 例）：**只有源载荷真的带了这些键才输出**。
  //   老客户端 / 旧版夹具的 payload 里没有它们 → 输出键集合与旧版逐字节一致，
  //   等价用例不受影响；新客户端（`cardToRoomSheet`）带上了 → 自动多出这些字段。
  //   这与「无条件输出空串」有本质区别：后者会让每条旧载荷的输出都多 8 个键。
  //
  // ★ 隐私：这里只做「有长度上限的公开文本 + 有限枚举」，`privates` / 明文 `p`
  //   一个都不在此列；他人视图（`_cropMember`）也**不搬**这些键，只有 KP 与本人可见。
  final bg = asMap(src['background']);
  final assets = asMap(src['assets']);
  final edu = asMap(src['eduProgress']);
  final extras = <String, Object?>{};

  void pickText(String key, [int maxLen = 60]) {
    if (src.containsKey(key)) extras[key] = cleanText(src[key], maxLen);
  }

  pickText('gender', 20);
  if (src.containsKey('age')) {
    extras['age'] = raClampNumber(src['age'], 0, 999, 0);
  }
  pickText('era', 40);
  pickText('residence', 60);
  pickText('birthplace', 60);
  pickText('occupation', 60);
  pickText('world', 60);
  pickText('look', 400);

  if (src.containsKey('background')) {
    extras['background'] = <String, Object?>{
      'ideology': cleanText(bg['ideology'], 400),
      'significantPeople': cleanText(bg['significantPeople'], 400),
      'meaningfulPlaces': cleanText(bg['meaningfulPlaces'], 400),
      'treasuredPossessions': cleanText(bg['treasuredPossessions'], 400),
      'traits': cleanText(bg['traits'], 400),
      'wounds': cleanText(bg['wounds'], 400),
      'phobias': cleanText(bg['phobias'], 400),
    };
  }

  if (src.containsKey('history')) {
    final historyOut = <Object?>[];
    for (final hRaw in asList(src['history'])) {
      if (historyOut.length >= 30) break;
      final h = asMap(hRaw);
      final title = cleanText(h['title'], 60);
      final desc = cleanText(h['description'], 600);
      if (title.isEmpty && desc.isEmpty) continue;
      historyOut.add(<String, Object?>{
        'title': title,
        'date': cleanText(h['date'], 32),
        'description': desc,
        'notes': cleanText(h['notes'], 200),
      });
    }
    extras['history'] = historyOut;
  }

  if (src.containsKey('armors')) {
    final armorsOut = <Object?>[];
    for (final aRaw in asList(src['armors'])) {
      if (armorsOut.length >= 20) break;
      final armorName = cleanText(asMap(aRaw)['name'], 40);
      if (armorName.isNotEmpty) armorsOut.add(armorName);
    }
    extras['armors'] = armorsOut;
  }

  if (src.containsKey('assets')) {
    extras['assets'] = <String, Object?>{
      'creditRating': raClampNumber(assets['creditRating'], 0, 99, 0),
      'cash': raClampNumber(assets['cash'], 0, 1e9, 0),
      'spendingLevel': cleanText(assets['spendingLevel'], 20),
      'currency': cleanText(assets['currency'], 8),
      'description': cleanText(assets['assetsDescription'], 400),
    };
  }

  if (src.containsKey('eduProgress')) {
    extras['eduProgress'] = <String, Object?>{
      'checks': asList(edu['log']).length,
      'bonus': raClampNumber(edu['bonus'], 0, 99, 0),
    };
  }

  return <String, Object?>{
    'name': name,
    'charId': charId.isNotEmpty ? charId : null,
    'avatar': avatar,
    'attrs': attrs,
    'status': raSanitizeStatus(src['status'], src),
    'skills': skills,
    'madness': madness,
    'mental': mental,
    'sanLoss': raClampNumber(src['sanLoss'], 0, 99, 0),
    'maxSAN': raClampNumberOrNull(src['maxSAN'], 0, 99),
    'san': raClampNumberOrNull(src['san'], 0, 99),
    'hp': raClampNumberOrNull(src['hp'], 0, 999),
    'mp': raClampNumberOrNull(src['mp'], 0, 999),
    'tempStatus': tempStatus,
    'items': items,
    'weapons': weapons,
    'db': cleanText(src['db'], 10).isNotEmpty ? cleanText(src['db'], 10) : '0',
    'at': at,
    // B1 的增量字段：只在载荷真的带了的时候才出现（见上方兼容红线）
    ...extras,
  };
}

// ============================================================
// 角色卡/伤势/SAN/施救动作
// ============================================================

/// 载荷可选 `base`（KP 手填「检定数值」）的覆盖值（P17 · KP-6 追加裁决）。
///
/// 口径（用户「急救/医学的检定数值」「精神分析的检定数值」）：
///   · **只有**「键存在、非 null、非空串、能解析成有限数」才算覆盖；
///   · 其余一切情况返回 null → 调用方回落 `skillBaseOf(...)`（角色卡技能值）。
/// 因此**不带 `base` 的老载荷路径逐字不变**（`oracle_*` / `fixtures` 不受影响）。
///
/// ⚠️ 只在发起者是 KP 时生效（调用点显式判 `bySeat == kHostSeat`）：
///   玩家走 `aid.apply` / `aid.psycho` 申请时不能自带技能值，否则等于
///   自选检定成功率，绕过角色卡。
num? raPayloadBaseOverride(Map<String, Object?> p) {
  if (!p.containsKey('base')) return null;
  final raw = p['base'];
  if (raw == null) return null;
  if (raw is String && raw.trim().isEmpty) return null;
  return raFinite(raw);
}

extension RoomHostActionsSheet on RoomHost {
  /// 卡/伤势/SAN/施救组动作分发。**返回 null 表示该 op 不属于本组**。
  List<SendPlan>? dispatchSheetAction(String seat, Map<String, Object?> p) {
    final op = jsStr(p['op']);
    switch (op) {
      // ---- 状态编辑 ----
      case 'state.edit.self':
      case 'state.self':
        return stateSelf(seat, p);
      case 'state.edit.other':
      case 'state.request':
        return stateRequest(seat, p);
      case 'state.apply':
        // consent 同意路径（旧版 :1599-1600 把 payload 译成 change）。
        return sheetActionConsentApply(seat, p);

      // ---- KP 定向指令 ----
      case 'sheet.damage':
        return sheetDamage(seat, p);
      case 'sheet.sancheck':
        return sheetSanCheck(seat, p);
      case 'sheet.tempstatus':
        return sheetTempStatus(seat, p);
      case 'sheet.item':
        return sheetItem(seat, p);
      case 'sheet.sanloss':
        return sheetSanLoss(seat, p);
      case 'sheet.healwound':
        return healWound(seat, p);

      // ---- 施救 / 精神分析 ----
      case 'aid.apply':
        return aidApply(seat, p);
      case 'aid.psycho':
        return psychoAnalyze(seat, p);

      // ---- 疯狂轮次 ----
      case 'madness.advance':
        return advanceMadness(seat, p);
      case 'madness.cure':
        return cureIndefinite(seat, p);
      default:
        return null;
    }
  }

  /// `state.apply` 别名：把 consent 的 `{hp,san,mp}` 译成 status 变更。
  List<SendPlan> sheetActionConsentApply(String seat, Map<String, Object?> p) {
    final ch = asMap(p['change']);
    final stc = <String, Object?>{};
    for (final pair in <MapEntry<String, String>>[
      const MapEntry<String, String>('hp', 'currentHP'),
      const MapEntry<String, String>('san', 'currentSAN'),
      const MapEntry<String, String>('mp', 'currentMP'),
    ]) {
      final raw = ch[pair.key];
      if (raw == null) continue;
      final n = raFinite(raw);
      if (n != null) stc[pair.value] = n;
    }
    if (stc.isEmpty) return const <SendPlan>[];
    final change = <String, Object?>{'status': stc};
    final out = <SendPlan>[];
    out.addAll(stateApply(seat, change, <String, Object?>{}));
    final m = roster.get(seat);
    if (m != null) out.addAll(applyStatusJudgment(m, change, seat, null));
    out.addAll(syncMembers());
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': 'KP 调整了 ${raNick(this, m, seat)} 的状态',
      'at': now(),
      'kind': 'state',
    }, vis: RoomVis.public));
    return out;
  }

  /// 角色卡状态写回：更新成员表 + 单发 EVT.STATE（旧版 :3983-4074）。
  /// 所有动作结算产出的 card 形状都经白名单收口。
  List<SendPlan> stateApply(
    String targetSeat,
    Map<String, Object?> change,
    Map<String, Object?> opts,
  ) {
    final out = <SendPlan>[];
    final m = roster.get(targetSeat);
    if (m == null) {
      pushInto(out, sysTo(kHostSeat, '找不到该玩家，无法写回状态'));
      return out;
    }
    if (m['runtime'] is! Map) m['runtime'] = <String, Object?>{};
    if (m['sheet'] is! Map) {
      m['sheet'] = raSanitizeSheet(<String, Object?>{}, m, now());
    }
    final sheet = asMap(m['sheet']);
    if (sheet['status'] is! Map) {
      sheet['status'] = raSanitizeStatus(<String, Object?>{}, sheet);
    }
    if (sheet['tempStatus'] is! List) sheet['tempStatus'] = <Object?>[];
    if (sheet['items'] is! List) sheet['items'] = <Object?>[];
    final status = asMap(sheet['status']);
    final runtime = asMap(m['runtime']);
    final st = asMap(change['status']);

    void writeField(String key, num lo, num hi, String runtimeKey) {
      final v = st[key];
      if (v == null) return;
      final n = raFinite(v);
      if (n == null) return;
      runtime[runtimeKey] = raClampToMax(
          raClampNumber(v, lo, hi, 0), status[capKey(key)]);
      status[key] = runtime[runtimeKey];
    }

    // 上限字段先写，现值以「本次写后的上限」夹取。
    for (final pair in <MapEntry<String, String>>[
      const MapEntry<String, String>('maxHP', 'maxHP'),
      const MapEntry<String, String>('maxMP', 'maxMP'),
      const MapEntry<String, String>('maxSAN', 'maxSAN'),
    ]) {
      final v = st[pair.key];
      if (v != null) {
        status[pair.value] =
            raClampNumber(v, 0, pair.key == 'maxSAN' ? 999 : 9999,
                raNum(status[pair.value], 0));
      }
    }
    writeField('currentHP', 0, 9999, 'hp');
    writeField('currentMP', 0, 9999, 'mp');
    writeField('currentSAN', 0, 999, 'san');
    if (st['currentLuck'] != null) {
      status['currentLuck'] =
          raClampNumber(st['currentLuck'], 0, 999, raNum(status['currentLuck'], 0));
    }
    if (st['body'] != null && st['body'] != '') {
      final b = cleanText(st['body'], 8);
      if (kRaBodyOk.contains(b)) status['body'] = b;
    }
    // false 也要写（显式解除）；undefined/null/'' 不动。
    if (st['dying'] != null && st['dying'] != '') {
      status['dying'] = jsTruthy(st['dying']);
    }
    if (st['unconscious'] != null && st['unconscious'] != '') {
      status['unconscious'] = jsTruthy(st['unconscious']);
    }
    for (final pair in <MapEntry<String, String>>[
      const MapEntry<String, String>('madness', 'madness'),
      const MapEntry<String, String>('mental', 'mental'),
      const MapEntry<String, String>('tempStatus', 'tempStatus'),
      const MapEntry<String, String>('items', 'items'),
      const MapEntry<String, String>('weapons', 'weapons'),
    ]) {
      final v = change[pair.key];
      if (v is List) {
        final clean = raSanitizeSheet(
            <String, Object?>{pair.key: v}, m, now());
        sheet[pair.value] = clean[pair.value] ?? <Object?>[];
      }
    }
    if (change['sanLoss'] != null) {
      sheet['sanLoss'] = raClampNumber(
          change['sanLoss'], 0, 99, raNum(sheet['sanLoss'], 0));
    }

    stateSeq += 1;
    final payload = <String, Object?>{
      'seq': stateSeq,
      'seat': targetSeat,
      'charId': m['charId'],
      'status': roomClone(status),
      'madness': roomClone(sheet['madness']),
      'mental': roomClone(sheet['mental']),
      'sanLoss': sheet['sanLoss'],
      'tempStatus': roomClone(sheet['tempStatus']),
      'items': roomClone(sheet['items']),
      'weapons': sheet['weapons'] is List
          ? roomClone(sheet['weapons'])
          : <Object?>[],
      'reason': cleanText(opts['reason'], 80),
      'at': now(),
    };
    pushInto(out,
        emit(RoomEvt.state, payload, vis: RoomVis.seat, to: targetSeat));
    out.addAll(syncMembers());
    if (jsTruthy(opts['reason'])) {
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': '${raNick(this, m, targetSeat)} 状态变化（${cleanText(opts['reason'], 80)}）',
        'at': now(),
        'kind': 'state',
      }, vis: RoomVis.public));
    }
    return out;
  }

  /// 状态现值对应的上限键名。
  String capKey(String key) => switch (key) {
        'currentHP' => 'maxHP',
        'currentSAN' => 'maxSAN',
        _ => 'maxMP',
      };

  /// 玩家自助修改自己的状态（免确认；旧版 :2055-2188）。
  List<SendPlan> stateSelf(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final target = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : (bySeat == kHostSeat ? '' : bySeat);
    if (bySeat != kHostSeat && target != bySeat) {
      pushInto(out, sysTo(bySeat, '只能修改自己的状态'));
      return out;
    }
    final m = roster.get(target);
    if (m == null) {
      pushInto(out, sysTo(bySeat, '找不到该玩家'));
      return out;
    }
    if (m['sheet'] is! Map) {
      m['sheet'] = raSanitizeSheet(<String, Object?>{}, m, now());
    }
    final sheet = asMap(m['sheet']);
    if (sheet['status'] is! Map) {
      sheet['status'] = raSanitizeStatus(<String, Object?>{}, sheet);
    }
    if (sheet['tempStatus'] is! List) sheet['tempStatus'] = <Object?>[];
    if (sheet['madness'] is! List) sheet['madness'] = <Object?>[];

    final status = asMap(sheet['status']);
    final st = asMap(p['status']);
    final stOut = <String, Object?>{};
    for (final k in <String>[
      'currentHP', 'currentMP', 'currentSAN', 'maxHP', 'maxMP', 'maxSAN',
      'currentLuck',
    ]) {
      final v = st[k];
      if (v == null || v == '') continue;
      final f = raFinite(v);
      if (f == null) continue;
      stOut[k] = jsRound(f);
    }
    // 玩家不得自行把重伤/濒死/昏迷降级或取消（旧版 :2098-2110）。
    final curWound = bodyView(status) == '重伤' ||
        jsTruthy(status['dying']) ||
        jsTruthy(status['unconscious']);
    if (bySeat != kHostSeat && curWound) {
      final nbRaw = (st['body'] != null && st['body'] != '')
          ? cleanText(st['body'], 8)
          : null;
      final clearMajor = nbRaw == '正常' || nbRaw == '轻伤';
      final clearDying = st['dying'] != null &&
          st['dying'] != '' &&
          !jsTruthy(st['dying']) &&
          jsTruthy(status['dying']);
      final clearUncon = st['unconscious'] != null &&
          st['unconscious'] != '' &&
          !jsTruthy(st['unconscious']) &&
          jsTruthy(status['unconscious']);
      if (clearMajor || clearDying || clearUncon) {
        pushInto(out, sysTo(bySeat,
            '当前处于「${bodyView(status)}」，不能自行取消该状态 —— 请用「🩹 治愈伤势（需 KP 同意）」或请 KP / 队友施救'));
        return out;
      }
    }
    if (st['body'] != null && st['body'] != '') {
      final bd = cleanText(st['body'], 8);
      if (kRaBodyOk.contains(bd)) stOut['body'] = bd;
    }
    if (st['dying'] != null && st['dying'] != '') {
      stOut['dying'] = jsTruthy(st['dying']);
    }
    if (st['unconscious'] != null && st['unconscious'] != '') {
      stOut['unconscious'] = jsTruthy(st['unconscious']);
    }
    if (stOut.isNotEmpty) {
      for (final k in <String>['currentHP', 'currentMP', 'currentSAN', 'currentLuck']) {
        if (stOut[k] != null) {
          stOut[k] = raClampNumber(stOut[k], 0, 9999, 0);
        }
      }
      final effMaxHP = stOut['maxHP'] ?? status['maxHP'];
      final effMaxSAN = stOut['maxSAN'] ?? status['maxSAN'];
      if (stOut['currentHP'] != null) {
        stOut['currentHP'] = raClampToMax(stOut['currentHP'], effMaxHP);
      }
      if (stOut['currentSAN'] != null) {
        stOut['currentSAN'] = raClampToMax(stOut['currentSAN'], effMaxSAN);
      }
    }

    final change = <String, Object?>{};
    if (stOut.isNotEmpty) change['status'] = stOut;
    final tsText = cleanText(p['tempStatus'], 80);
    if (tsText.isNotEmpty) {
      final tsList = List<Object?>.from(asList(sheet['tempStatus']));
      tsList.add(<String, Object?>{
        'text': tsText,
        'by': bySeat == kHostSeat ? 'kp' : 'self',
        'at': now(),
      });
      change['tempStatus'] = tsList;
    }
    final md = asMap(p['madness']);
    if (jsTruthy(md['name'])) {
      final mdList = List<Object?>.from(asList(sheet['madness']));
      mdList.add(<String, Object?>{
        'type': kRaMadTypes.contains(md['type']) ? md['type'] : 'phobia',
        'name': cleanText(md['name'], 60),
        'permanent': jsTruthy(md['permanent']),
        'rounds': jsTruthy(md['permanent'])
            ? 0
            : raClampNumber(md['rounds'], 0, 99, 0),
      });
      change['madness'] = mdList;
    }
    if (p['mental'] is List) change['mental'] = p['mental'];

    if (change.isEmpty) {
      pushInto(out, sysTo(bySeat, '没有要修改的内容'));
      return out;
    }
    final sanBefore = raMemberStatusValue(m, 'currentSAN');
    final hpBefore = raMemberStatusValue(m, 'currentHP');
    final bodyBefore = bodyView(status);
    final flagsBefore = <String, Object?>{
      'dying': jsTruthy(status['dying']),
      'unconscious': jsTruthy(status['unconscious']),
    };
    final selfReason = cleanText(p['reason'], 80).isNotEmpty
        ? cleanText(p['reason'], 80)
        : '${bySeat == kHostSeat ? 'KP' : '玩家自行'}修改状态';
    out.addAll(stateApply(target, change, <String, Object?>{'reason': selfReason}));
    out.addAll(applyStatusJudgment(m, change, bySeat, <String, Object?>{
      'sanBefore': sanBefore,
      'hpBefore': hpBefore,
      'bodyBefore': bodyBefore,
      'flagsBefore': flagsBefore,
    }));
    return out;
  }

  /// KP 请求修改玩家状态（需玩家同意；旧版 :3161-3178）。
  List<SendPlan> stateRequest(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final target = jsStr(p['seat']);
    if (!jsTruthy(p['seat'])) {
      pushInto(out, sysTo(bySeat, '要指定目标玩家'));
      return out;
    }
    localSeq += 1;
    final id = 'r$localSeq';
    // 旧版 `clone(p.change || {})`：没给 change 时 payload 必须是空对象，
    // 不能是 null（定向 REQUEST 事件里 null 会让客户端反序列化后判空失败）。
    final change = roomClone(asMap(p['change']));
    final reason = cleanText(p['reason'], 80);
    final at = now();
    final rec = <String, Object?>{
      'id': id,
      'from': bySeat,
      'op': 'state.apply',
      'payload': change,
      'reason': reason,
      'at': at,
    };
    requestsBySeat.putIfAbsent(target, () => <Map<String, Object?>>[]).add(rec);
    pending.add(<String, Object?>{
      'id': id,
      'kind': 'state.request',
      'by': bySeat,
      'to': target,
      'change': roomClone(change),
      'at': at,
    });
    pushInto(out, emit(RoomEvt.request, <String, Object?>{
      'self': true,
      'id': id,
      'op': 'state.apply',
      'payload': change,
      'from': raNick(this, roster.get(bySeat), bySeat),
      'reason': reason,
      'at': at,
    }, vis: RoomVis.seat, to: target));
    pushInto(out, sysTo(bySeat, '已发送变更请求，等待玩家确认'));
    return out;
  }

  /// 状态写入后的统一判定（HP 归零 / SAN 归零 / 净减 SAN / 撕卡；
  /// 旧版 :2208-2301）。
  List<SendPlan> applyStatusJudgment(
    Map<String, Object?> m,
    Map<String, Object?> change,
    String bySeat,
    Map<String, Object?>? opts,
  ) {
    final out = <SendPlan>[];
    final o = asMap(opts);
    final target = jsStr(m['seat'] ?? bySeat);
    final who = raNick(this, m, target);
    if (m['sheet'] is! Map) return out;
    final sheet = asMap(m['sheet']);
    if (sheet['status'] is! Map) {
      sheet['status'] = raSanitizeStatus(<String, Object?>{}, sheet);
    }
    final status = asMap(sheet['status']);
    final oSan = o['sanBefore'];
    final oHp = o['hpBefore'];
    final oBody = o['bodyBefore'];
    final flagsBefore = asMap(o['flagsBefore']);
    final hasFlags = o['flagsBefore'] is Map;

    final hpNow = raMemberStatusValue(m, 'currentHP');
    final hpBefore = (oHp == null) ? null : raFinite(oHp);
    final prevBody = (oBody == null || oBody == '')
        ? bodyView(status)
        : jsStr(oBody);
    final dyingBefore = hasFlags
        ? jsTruthy(flagsBefore['dying'])
        : jsTruthy(status['dying']);
    final unconsciousBefore = hasFlags
        ? jsTruthy(flagsBefore['unconscious'])
        : jsTruthy(status['unconscious']);
    final hpChanged = hpBefore == null || hpBefore != raNum(hpNow, 0);
    if (hpNow != null && hpChanged && status['body'] != '死亡') {
      var maxHPNow = raFinite(raMemberStatusValue(m, 'maxHP')) ?? 0;
      if (!(maxHPNow > 0)) maxHPNow = 0;
      final amountNow = hpBefore != null ? (hpBefore - raNum(hpNow, 0) > 0 ? hpBefore - raNum(hpNow, 0) : 0) : 0;
      final jd = raDeriveBodyFromHp(
          prevBody, amountNow, raNum(hpNow, 0), maxHPNow);
      Object? bodyJ = jd.containsKey('body') ? jd['body'] : kRaUnset;
      Object? dyingJ = jd.containsKey('dying') ? jd['dying'] : kRaUnset;
      Object? unconsciousJ =
          jd.containsKey('unconscious') ? jd['unconscious'] : kRaUnset;
      var jNote = '';
      if (jd['needCon'] == true) {
        final con = raMemberAttr(m, 'con');
        final chk = rules?.dyingRoundCheck(con ?? 50, rng);
        if (chk != null) {
          out.addAll(diceRoll(target, <String, Object?>{
            'expr': '1D100',
            'label': '重伤 CON 检定（避免昏迷，对 ${asMap(chk['check'])['base']}）',
            'result': chk['check'],
          }));
          jNote = jsStr(chk['summary']);
          if (chk['dead'] == true) unconsciousJ = true;
        }
      }
      final bodyChanged = !identical(bodyJ, kRaUnset) && bodyJ != status['body'];
      final dyingChanged =
          !identical(dyingJ, kRaUnset) && dyingJ != dyingBefore;
      final unconsciousChanged = !identical(unconsciousJ, kRaUnset) &&
          unconsciousJ != unconsciousBefore;
      if (bodyChanged || dyingChanged || unconsciousChanged) {
        final viewJ = bodyView(<String, Object?>{
          'body': !identical(bodyJ, kRaUnset) ? bodyJ : status['body'],
          'dying': !identical(dyingJ, kRaUnset) ? dyingJ : dyingBefore,
          'unconscious': !identical(unconsciousJ, kRaUnset)
              ? unconsciousJ
              : unconsciousBefore,
        });
        final patch = <String, Object?>{};
        if (!identical(bodyJ, kRaUnset)) patch['body'] = bodyJ;
        if (!identical(dyingJ, kRaUnset)) patch['dying'] = dyingJ;
        if (!identical(unconsciousJ, kRaUnset)) {
          patch['unconscious'] = unconsciousJ;
        }
        out.addAll(stateApply(target, <String, Object?>{'status': patch},
            <String, Object?>{
              'reason': 'HP 变动判定：$viewJ${jNote.isNotEmpty ? '　$jNote' : ''}',
            }));
      }
    }
    out.addAll(syncBodyToCombatSlot(m));

    final sanNow = raMemberStatusValue(m, 'currentSAN');
    final mentalNow = asList(sheet['mental']);
    if (sanNow != null &&
        sanNow <= 0 &&
        !mentalNow.contains(kRaMentalPermanent)) {
      out.addAll(stateApply(target,
          <String, Object?>{'mental': <Object?>[kRaMentalPermanent]},
          <String, Object?>{'reason': 'SAN 归零 → 永久疯狂'}));
    }
    if (oSan != null && sanNow != null && sanNow > 0) {
      final before = raFinite(oSan);
      if (before != null && sanNow < before) {
        out.addAll(afterSanLoss(m, before - sanNow, bySeat));
      }
    }
    if (raMemberRipped(m)) {
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': '$who 已${status['body'] == '死亡' ? '死亡' : '永久疯狂'} —— 撕卡，只能通过聊天框交流',
        'at': now(),
        'kind': 'warn',
      }, vis: RoomVis.public));
    }
    return out;
  }

  /// 伤害结算 + 死亡判定（旧版 :4539-4608）。
  List<SendPlan> settleWounds(
    Map<String, Object?> m,
    num amount,
    String reason,
    Map<String, Object?>? base,
  ) {
    final out = <SendPlan>[];
    final seat = jsStr(m['seat']);
    final who = raNick(this, m, seat);
    var maxHP = raMemberStatusValue(m, 'maxHP');
    var curHP = raMemberStatusValue(m, 'currentHP');
    final b = asMap(base);
    if (raFinite(b['maxHP']) != null && (raFinite(b['maxHP']) ?? 0) > 0) {
      maxHP = raFinite(b['maxHP']);
    }
    if (raFinite(b['currentHP']) != null) curHP = raFinite(b['currentHP']);
    curHP ??= maxHP;
    var hp = raNum(curHP, 0);
    if (hp < 0) hp = 0;
    var max = raNum(maxHP, 0);
    if (!(max > 0)) max = hp > 0 ? hp : 1;
    final after = (hp - amount) > 0 ? hp - amount : 0;
    var conNote = '';
    final prevBody = m['sheet'] is Map
        ? bodyView(asMap(asMap(m['sheet'])['status']))
        : '正常';
    final verdict = raDeriveBodyFromHp(prevBody, amount, after, max);
    Object? body = verdict.containsKey('body') ? verdict['body'] : kRaUnset;
    Object? dying = verdict.containsKey('dying') ? verdict['dying'] : kRaUnset;
    Object? unconscious =
        verdict.containsKey('unconscious') ? verdict['unconscious'] : kRaUnset;
    if (verdict['needCon'] == true) {
      final con = raMemberAttr(m, 'con');
      final chk = rules?.dyingRoundCheck(con ?? 50, rng);
      if (chk != null) {
        out.addAll(diceRoll(seat, <String, Object?>{
          'expr': '1D100',
          'label': '重伤 CON 检定（避免昏迷，对 ${asMap(chk['check'])['base']}）',
          'result': chk['check'],
        }));
        conNote = jsStr(chk['summary']);
        if (chk['dead'] == true) unconscious = true;
      }
    }
    final stPatch = <String, Object?>{'currentHP': after};
    if (!identical(body, kRaUnset)) stPatch['body'] = body;
    if (!identical(dying, kRaUnset)) stPatch['dying'] = dying;
    if (!identical(unconscious, kRaUnset)) {
      stPatch['unconscious'] = unconscious;
    }
    out.addAll(stateApply(seat, <String, Object?>{'status': stPatch},
        <String, Object?>{
          'reason': '$reason${conNote.isNotEmpty ? '　$conNote' : ''}',
        }));
    out.addAll(syncBodyToCombatSlot(m));
    final viewNow = m['sheet'] is Map
        ? bodyView(asMap(asMap(m['sheet'])['status']))
        : '';
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': '$who 受到 ${raNum(amount, 0).toInt()} 点伤害，HP ${hp.toInt()} → ${after.toInt()}'
          '${viewNow.isNotEmpty ? '，身体状态：$viewNow' : ''}'
          '${conNote.isNotEmpty ? '　·　$conNote' : ''}',
      'at': now(),
      'kind': 'damage',
    }, vis: RoomVis.public));
    if (body == '死亡') {
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': '$who 已死亡 —— 撕卡，该玩家只能通过聊天框交流',
        'at': now(),
        'kind': 'warn',
      }, vis: RoomVis.public));
    }
    return out;
  }

  /// HP 变动唯一收口：扣血委托 settleWounds，回血走 deriveBodyFromHp
  /// （旧版 :4623-4674）。
  List<SendPlan> applyHpChange(
    Map<String, Object?> m,
    num delta,
    String reason,
    Map<String, Object?> opts,
  ) {
    final out = <SendPlan>[];
    final d = raFinite(delta);
    if (d == null || d == 0) return out;
    if (d < 0) return settleWounds(m, -d, reason, asMap(opts['base']));
    if (m['sheet'] is! Map) {
      m['sheet'] = raSanitizeSheet(<String, Object?>{}, m, now());
    }
    final sheet = asMap(m['sheet']);
    if (sheet['status'] is! Map) {
      sheet['status'] = raSanitizeStatus(<String, Object?>{}, sheet);
    }
    final status = asMap(sheet['status']);
    final maxHPVal = raMemberStatusValue(m, 'maxHP');
    final curHP = raNum(raMemberStatusValue(m, 'currentHP'), 0);
    var max = raNum(maxHPVal, 0);
    if (!(max > 0)) max = curHP > 0 ? curHP : 0;
    final cap = max > 0 ? max : (curHP + d);
    final after = (curHP + d) < cap ? (curHP + d) : cap;
    if (after <= curHP) return out;
    final gain = after - curHP;
    final prevBody = bodyView(status);
    Object? body = kRaUnset;
    Object? vDying = kRaUnset;
    Object? vUnconscious = kRaUnset;
    if (jsTruthy(opts['forceBody'])) {
      body = opts['forceBody'];
    } else if (prevBody == '死亡') {
      body = '死亡';
    } else {
      final hv = raDeriveBodyFromHp(prevBody, 0, after, max);
      if (hv.containsKey('body')) body = hv['body'];
      if (hv.containsKey('dying')) vDying = hv['dying'];
      if (hv.containsKey('unconscious')) vUnconscious = hv['unconscious'];
    }
    final stPatch = <String, Object?>{'currentHP': after};
    if (!identical(body, kRaUnset)) stPatch['body'] = body;
    if (!identical(vDying, kRaUnset)) stPatch['dying'] = vDying;
    if (!identical(vUnconscious, kRaUnset)) {
      stPatch['unconscious'] = vUnconscious;
    }
    out.addAll(stateApply(jsStr(m['seat']),
        <String, Object?>{'status': stPatch},
        <String, Object?>{'reason': reason.isNotEmpty ? reason : '恢复生命'}));
    out.addAll(syncBodyToCombatSlot(m));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': '${raNick(this, m, jsStr(m['seat']))} 恢复 ${gain.toInt()} 点生命，'
          'HP ${curHP.toInt()} → ${after.toInt()}，身体状态：${bodyView(status)}',
      'at': now(),
      'kind': 'state',
    }, vis: RoomVis.public));
    return out;
  }

  /// 把成员身体状态同步到战斗槽 public.down/state/hp（旧版 :4689-4702）。
  List<SendPlan> syncBodyToCombatSlot(Map<String, Object?> m) {
    final out = <SendPlan>[];
    if (state['combat'] is! Map) return out;
    final c = asMap(state['combat']);
    final order = asList(c['order']);
    if (order.isEmpty) return out;
    if (m['sheet'] is! Map) return out;
    for (var i = 0; i < order.length; i++) {
      final slotRaw = order[i];
      final slot = asMap(slotRaw);
      if (slot['kind'] != 'pc' || slot['seat'] != m['seat']) continue;
      if (stampSlotBody(slot, m)) {
        order[i] = slot;
        pushInto(out, emit(RoomEvt.actor, <String, Object?>{
          'actor': roomClone(slot),
        }, vis: RoomVis.public));
      }
    }
    return out;
  }

  /// 写入单个战斗槽（纯写，不发事件；旧版 :4712-4727）。
  bool stampSlotBody(Map<String, Object?> slot, Map<String, Object?> m) {
    if (m['sheet'] is! Map) return false;
    final status = asMap(asMap(m['sheet'])['status']);
    final body = bodyView(status);
    final hp = raMemberStatusValue(m, 'currentHP');
    if (slot['public'] is! Map) slot['public'] = <String, Object?>{};
    final pub = asMap(slot['public']);
    const slotState = <String, String>{
      '死亡': 'dead',
      '濒死': 'dying',
      '昏迷': 'unconscious',
      '重伤': 'majorWound',
    };
    final down = body == '死亡' ||
        body == '濒死' ||
        body == '昏迷' ||
        (hp != null &&
            (raFinite(pub['hpMax']) ?? 0) > 0 &&
            raNum(hp, 0) <= 0);
    final st = slotState[body] ?? '';
    var changed = false;
    if (jsTruthy(pub['down']) != down) {
      pub['down'] = down;
      changed = true;
    }
    if (st.isNotEmpty && pub['state'] != st) {
      pub['state'] = st;
      changed = true;
    }
    if (hp != null && raNum(pub['hp'], double.nan) != raNum(hp, 0)) {
      pub['hp'] = raNum(hp, 0) > 0 ? raNum(hp, 0) : 0;
      changed = true;
    }
    return changed;
  }

  /// 把所有 PC 槽按各自成员 body 同步（纯写；旧版 :4735-4745）。
  void stampAllPcSlots() {
    if (state['combat'] is! Map) return;
    for (final sRaw in asList(asMap(state['combat'])['order'])) {
      final s = asMap(sRaw);
      if (s['kind'] != 'pc' || !jsTruthy(s['seat'])) continue;
      final m = roster.get(jsStr(s['seat']));
      if (m != null) stampSlotBody(s, m);
    }
  }

  /// 目标展开：`'*'` → 全部在线玩家（旧版 :4460-4480）。
  List<SendPlan> forEachTarget(
    String bySeat,
    Object? seatSpec,
    String what,
    List<SendPlan> Function(Map<String, Object?> m) fn,
  ) {
    final out = <SendPlan>[];
    final spec = cleanText(seatSpec, 64);
    if (spec == '*') {
      final list = roster.onlinePlayers();
      if (list.isEmpty) {
        pushInto(out, sysTo(bySeat, '房间里没有在线玩家，无法$what'));
        return out;
      }
      for (final m in list) {
        out.addAll(fn(m));
      }
      pushInto(out, sys('「全部玩家」指令：$what → 已作用于 ${list.length} 名在线玩家'));
      return out;
    }
    if (spec.isEmpty) {
      pushInto(out, sysTo(bySeat, '请先选择生效目标（不会默认作用于自己）'));
      return out;
    }
    final one = roster.get(spec);
    if (one == null) {
      pushInto(out, sysTo(bySeat, '找不到该玩家，无法$what'));
      return out;
    }
    return out..addAll(fn(one));
  }

  bool isDying(Map<String, Object?>? m) =>
      m != null && m['sheet'] is Map && jsTruthy(asMap(asMap(m['sheet'])['status'])['dying']);

  bool isUnconscious(Map<String, Object?>? m) => m != null &&
      m['sheet'] is Map &&
      jsTruthy(asMap(asMap(m['sheet'])['status'])['unconscious']);

  bool memberRipped(Map<String, Object?>? m) => raMemberRipped(m);

  bool memberInBout(Map<String, Object?>? m) => raMemberInBout(m);

  // ---- KP 定向指令 ----

  /// 指定玩家受到伤害（旧版 :5448-5468）。
  List<SendPlan> sheetDamage(String bySeat, Map<String, Object?> p) {
    final amount = raClampNumber(p['amount'], 0, 9999, 0);
    if (amount <= 0) {
      return <SendPlan>[
        ...pushInto(<SendPlan>[], sysTo(bySeat, '伤害值要大于 0')),
      ];
    }
    final kind = cleanText(p['kind'], 20);
    return forEachTarget(bySeat, p['seat'], '施加伤害', (m) {
      if (raMemberRipped(m)) {
        return <SendPlan>[
          ...pushInto(<SendPlan>[], sysTo(bySeat,
              '「${raNick(this, m, jsStr(m['seat']))}」已撕卡，无法施加伤害')),
        ];
      }
      return applyHpChange(m, -amount,
          '受到伤害 ${amount.toInt()}${kind.isNotEmpty ? '（$kind）' : ''}',
          <String, Object?>{});
    });
  }

  /// 指定玩家做 SAN Check（各自独立结算；旧版 :5484-5506）。
  List<SendPlan> sheetSanCheck(String bySeat, Map<String, Object?> p) {
    return forEachTarget(bySeat, p['seat'], '做 SAN Check', (m) {
      if (raMemberRipped(m)) {
        return <SendPlan>[
          ...pushInto(<SendPlan>[], sysTo(bySeat,
              '「${raNick(this, m, jsStr(m['seat']))}」已撕卡，无法做 SAN Check')),
        ];
      }
      if (raMemberMadActive(m)) {
        return <SendPlan>[
          ...pushInto(<SendPlan>[], sysTo(bySeat,
              '「${raNick(this, m, jsStr(m['seat']))}」正处于疯狂发作中，不能做 SAN Check')),
        ];
      }
      return settleSanCheck(m, p, bySeat);
    });
  }

  /// 结算一名成员的 SAN Check（KP 定向 / 玩家自助共用；旧版 :5621-5736）。
  List<SendPlan> settleSanCheck(
    Map<String, Object?> m,
    Map<String, Object?> p,
    String bySeat,
  ) {
    final out = <SendPlan>[];
    final seat = jsStr(m['seat']);
    var san = raMemberStatusValue(m, 'currentSAN');
    final maxSan = raMemberStatusValue(m, 'maxSAN');
    var usedFallback = false;
    if (san == null) {
      if (maxSan != null) {
        san = maxSan;
        usedFallback = true;
      } else {
        pushInto(out,
            sysTo(bySeat, '该玩家还没有理智值（未绑定角色卡），无法做 SAN Check'));
        return out;
      }
    }
    san = raClampNumber(san, 0, 99, 0);
    final maxSanVal =
        (maxSan == null || !(maxSan > 0)) ? 99 : raClampNumber(maxSan, 1, 99, 99);
    final okExpr = raNormLossPart(p['okLoss'], '0');
    final failExpr = raNormLossPart(p['loss'], '1D6');
    final lossExpr = '$okExpr/$failExpr';

    final parsed = rules?.parseSanLoss(lossExpr) ?? <String, Object?>{'ok': false};
    if (parsed['ok'] != true) {
      pushInto(out, sysTo(bySeat,
          '理智损失格式不合法：${jsStr(parsed['reason'])}（应形如 0/1D6）'));
      return out;
    }
    final ro = ruleOptsOf(asMap(state['meta']));
    final rr = rules?.resolveSanCheck(<String, Object?>{
      'currentSan': san,
      'maxSan': maxSanVal,
      'lossExpr': lossExpr,
      ...ro,
    });
    if (rr == null || rr['ok'] != true) {
      pushInto(out, sysTo(bySeat,
          '理智检定结算失败：${jsStr(rr?['reason'] ?? '未知原因')}'));
      return out;
    }
    final checkRes = asMap(rr['check']);
    final loss = raClampNumber(rr['loss'], 0, 99, 0);
    final branchText = jsStr(rr['branchText']);
    final branch = rr['usedBranch'] == 'onSuccess' ? okExpr : failExpr;
    final roll = raNum(checkRes['value'], 0);
    final levelText = jsStr(checkRes['levelText'] ?? checkRes['levelKey'] ?? '');

    out.addAll(diceRoll(seat, <String, Object?>{
      'expr': '1D100',
      'label': 'SAN Check（对 ${san.toInt()}）',
      'result': checkRes,
    }));
    var after = (san - loss) > 0 ? san - loss : 0;
    if (maxSanVal >= san && after > maxSanVal) after = maxSanVal;
    final lossText = loss > 0
        ? '，理智损失 ${loss.toInt()}，SAN ${san.toInt()} → ${after.toInt()}'
        : '，无理智损失（SAN 保持不变）';
    final fumbleNote = jsTruthy(checkRes['fumble'])
        ? '　·　⚠ 大失败：KP 可按规则书追加 1D10 理智损失（KP 工具 → 🧾 SAN 大失败追加，不自动扣）'
        : '';
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': seat,
      'text': '${raNick(this, m, seat)} 做 SAN Check：目标 SAN ${san.toInt()}，'
          '掷 ${roll.toInt()}${levelText.isNotEmpty ? '（$levelText）' : ''} → '
          '$branchText 支 $branch$lossText'
          '${usedFallback ? '（未上报当前 SAN，暂以上限判定）' : ''}$fumbleNote',
      'at': now(),
      'kind': 'check',
    }, vis: RoomVis.public));
    if (loss > 0) {
      out.addAll(stateApply(seat,
          <String, Object?>{'status': <String, Object?>{'currentSAN': after}},
          <String, Object?>{
            'reason': 'SAN Check $branchText -${loss.toInt()}'
                '${jsTruthy(p['reason']) ? '（${cleanText(p['reason'], 40)}）' : ''}',
          }));
      out.addAll(afterSanLoss(m, loss, bySeat));
    }
    return out;
  }

  /// SAN 损失后的自动疯狂判定（旧版 :5160-5271）。
  List<SendPlan> afterSanLoss(Map<String, Object?> m, num loss, String bySeat) {
    final out = <SendPlan>[];
    final seat = jsStr(m['seat']);
    final who = raNick(this, m, seat);
    var san = raNum(raMemberStatusValue(m, 'currentSAN'), 0);
    final sheet = asMap(m['sheet']);
    final mentalNow = asList(sheet['mental']);
    /* P8（需求 6）：临时 / 不定疯狂期间**不获得新疯狂症**。
       正常入口（SAN Check）已被 raMemberMadActive 挡住，但「直接改 SAN 状态」
       与「精神分析失败扣 SAN」这两条旁路仍会走到这里 —— 这里再守一道。 */
    final madActive = mental_state.blockedByMadness(mentalNow);
    final isPotential = mental_state.isPotentialMadness(mentalNow);
    if (san <= 0) {
      out.addAll(stateApply(seat,
          <String, Object?>{'mental': <Object?>[kRaMentalPermanent]},
          <String, Object?>{'reason': 'SAN 归零 → 永久疯狂'}));
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': '$who 的 SAN 归零，判定为永久疯狂 —— 撕卡，只能通过聊天框交流',
        'at': now(),
        'kind': 'warn',
      }, vis: RoomVis.public));
      return out;
    }
    /* P11 修复：累计**必须在 `madActive` 早退之前**。
       P8（需求 6）的原文是「临时 / 不定疯狂期间**不获得新疯狂症**」——
       它约束的是「发不发症状」，不是「记不记 SAN 损失」。改前把整段累计
       放在早退之后，疯狂期受的损失一条都不进 `sanLostThisRound`，
       于是 ④ 的「不定疯狂阈值 = ceil(maxSAN/5)」基于错的累计，
       「症状消退 → 潜在疯狂 → 复发」这条链上阈值跨回合漂移、隔一回合才显形。
       顺序对齐老 APP `room-model.js:5155-5271`：
       ① 归零 → ② 累计 → ③ 临时疯狂（INT）→ ④ 不定疯狂；
       本工程的 `madActive` 早退插在 ② 与 ③ 之间（老 APP 靠入口拦，这里再守一道）。
       `san <= 0`（① 永久疯狂）**不累计**，与老 APP :5169-5176 一致：
       撕卡后角色已不参与回合判定，阈值分母（maxSAN）也失去意义。 */
    final lossTotal = (sanLostThisRound[seat] ?? 0) + loss.toInt();
    sanLostThisRound[seat] = lossTotal;
    if (!(roundStartSan.containsKey(seat)) ||
        (roundStartSan[seat] ?? 0) <= 0) {
      roundStartSan[seat] = san.toInt() + lossTotal;
    }
    if (madActive) {
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': '$who 正处于临时 / 不定疯狂，本次不获得新的疯狂症（需症状消退或被治愈后才恢复）',
        'at': now(),
        'kind': 'warn',
      }, vis: RoomVis.public));
      return out;
    }
    // ② 单次损失 ≥ 5 → INT 检定判是否理解。
    // ★ P10 第 3 期 B（按老 APP 2.13.13 抹平差异）：
    //   老 `room-model.js:5198` 是 `if (loss >= 5 && !isFaded)`，注释写明
    //   「FADED（不定疯狂症状消失 = 新名『潜在疯狂』）态损失 SAN 只走 ④ 复发，
    //   不再额外触发 ② 的临时疯狂路径，避免一次性获得 2 个症并叠加临时疯狂标签」。
    //   改前本工程漏了 `!isFaded`：潜在疯狂的角色单次掉 ≥5 SAN 会同时
    //   触发「临时疯狂 INT 检定 + 可能新症」与「不定疯狂复发 + 新症」两条路径。
    if (loss >= 5 && !isPotential) {
      final intVal = raMemberAttr(m, 'int');
      final intChk = rules?.temporaryInsanityCheck(intVal ?? 50, rng);
      if (intChk != null) {
        out.addAll(diceRoll(seat, <String, Object?>{
          'expr': '1D100',
          'label': '临时疯狂 INT 检定（对 ${asMap(intChk['check'])['base']}）',
          'result': intChk['check'],
        }));
        pushInto(out, emit(RoomEvt.log, <String, Object?>{
          'seat': '',
          'text': '$who：${jsStr(intChk['summary'])}',
          'at': now(),
          'kind': 'warn',
        }, vis: RoomVis.public));
        if (intChk['understood'] == true) {
          final symptom = raRollSymptom(madness);
          if (symptom != null) {
            out.addAll(addSymptom(m, symptom, '临时疯狂',
                '临时疯狂发作：${jsStr(symptom['name'])}（持续 ${symptom['rounds']} 轮）',
                bySeat, null));
          } else {
            pushInto(out, emit(RoomEvt.log, <String, Object?>{
              'seat': '',
              'text': '$who：临时疯狂发作（症状表未加载，请 KP 手动补症状）',
              'at': now(),
              'kind': 'warn',
            }, vis: RoomVis.public));
          }
        }
      }
    }
    // ④ 不定疯狂判定（统一式）。
    final maxSanForIndef = raMemberStatusValue(m, 'maxSAN');
    final fadedArmed = fadedArm[seat] != false;
    final oneFifth = (maxSanForIndef != null && maxSanForIndef > 0)
        ? (maxSanForIndef / 5).ceil()
        : 0;
    final relapseNow = loss > 0 &&
        ((isPotential && fadedArmed) || (oneFifth > 0 && lossTotal >= oneFifth));
    if (relapseNow) {
      /* 状态迁移走唯一实现 madness_state#nextMentalState：
         「潜在疯狂 + 掉 SAN → 不定疯狂 + 新症状」不是这里另写一份 if。 */
      final transition = mental_state.nextMentalState(
        mentalNow,
        mental_state.MentalEvent.sanLost,
      );
      final reEntryMental = isPotential ? transition.mental : null;
      final relapseWord = isPotential ? '不定疯狂复发' : '不定性疯狂';
      /* 「潜在疯狂 → 不定疯狂」必须**同时**新生成一条症状；是否生成由
         状态机的 spawnSymptom 决定，避免这里再写一份判据。 */
      final reSym = (!isPotential || transition.spawnSymptom)
          ? raRollSymptom(madness)
          : null;
      if (reSym != null) {
        out.addAll(addSymptom(m, reSym, kRaMentalIndef,
            '$relapseWord：${jsStr(reSym['name'])}（发作 ${reSym['rounds']} 轮；状态需治愈才解除）',
            bySeat, reEntryMental));
      } else {
        out.addAll(stateApply(seat, <String, Object?>{
          'mental': reEntryMental ?? mentalWithTag(m, kRaMentalIndef),
        }, <String, Object?>{
          'reason': '$relapseWord（症状表未加载，请 KP 手动补症状）',
        }));
      }
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': '',
        'text': isPotential
            ? '$who 处于「潜在疯狂」，再损失 SAN —— 立即复发为不定疯狂并新增一条疯狂症'
            : '$who：本回合累计理智损失 $lossTotal 点，达到最大理智值（${maxSanForIndef ?? 0}）的五分之一 —— 判定为不定性疯狂'
                '${reSym != null ? '（${jsStr(reSym['name'])}，发作 ${reSym['rounds']} 轮）' : ''}'
                '，「不定疯狂」状态需治愈才解除',
        'at': now(),
        'kind': 'warn',
      }, vis: RoomVis.public));
    }
    return out;
  }

  /// 给成员追加一条疯狂症状并同步精神状态（旧版 :5124-5145）。
  List<SendPlan> addSymptom(
    Map<String, Object?> m,
    Map<String, Object?> symptom,
    String? mentalTag,
    String reason,
    String bySeat,
    List<Object?>? mentalOverride,
  ) {
    final sheet = asMap(m['sheet']);
    final mdList = List<Object?>.from(asList(sheet['madness']));
    final permanent = jsTruthy(symptom['permanent']);
    mdList.add(<String, Object?>{
      'type': kRaMadTypes.contains(symptom['type'])
          ? symptom['type']
          : 'phobia',
      'name': cleanText(symptom['name'], 60),
      'permanent': permanent,
      'rounds': permanent ? 0 : raClampNumber(symptom['rounds'], 0, 99, 0),
      'from': cleanText(mentalTag, 12),
    });
    var mental = mentalOverride != null
        ? List<Object?>.from(mentalOverride)
        : List<Object?>.from(asList(sheet['mental']));
    mental = mental
        .where((x) => x != '正常' && x != kRaMentalPermanent)
        .toList();
    if (mentalTag != null &&
        mentalTag.isNotEmpty &&
        !mental.contains(mentalTag)) {
      mental.add(mentalTag);
    }
    /* P8（需求 7）：「疯狂症状」只标记**背景**疯狂表选中的症状，
       跑团里临时 / 不定疯狂发作获得的症状不再派生这个标记。 */
    return stateApply(jsStr(m['seat']), <String, Object?>{
      'madness': mdList,
      'mental': mental,
    }, <String, Object?>{'reason': reason});
  }

  /// 精神状态追加一个标签（踢掉互斥的「正常」）。
  List<Object?> mentalWithTag(Map<String, Object?> m, String tag) {
    final mental = asList(asMap(m['sheet'])['mental'])
        .where((x) => x != '正常')
        .toList();
    if (!mental.contains(tag)) mental.add(tag);
    return mental;
  }

  /// 给指定玩家追加临时状态（旧版 :5745-5766）。
  List<SendPlan> sheetTempStatus(String bySeat, Map<String, Object?> p) {
    final text = cleanText(p['text'], 80);
    if (text.isEmpty) {
      return <SendPlan>[
        ...pushInto(<SendPlan>[], sysTo(bySeat, '临时状态内容不能为空')),
      ];
    }
    return forEachTarget(bySeat, p['seat'], '附加临时状态', (m) {
      if (raMemberRipped(m)) {
        return <SendPlan>[
          ...pushInto(<SendPlan>[], sysTo(bySeat,
              '「${raNick(this, m, jsStr(m['seat']))}」已撕卡，无法附加临时状态')),
        ];
      }
      final list = List<Object?>.from(asList(asMap(m['sheet'])['tempStatus']));
      list.add(<String, Object?>{'text': text, 'by': 'kp', 'at': now()});
      return stateApply(jsStr(m['seat']),
          <String, Object?>{'tempStatus': list},
          <String, Object?>{'reason': 'KP 附加临时状态：$text'});
    });
  }

  /// 给指定玩家一个物品道具（旧版 :5774-5799）。
  List<SendPlan> sheetItem(String bySeat, Map<String, Object?> p) {
    final name = cleanText(p['name'], 40);
    if (name.isEmpty) {
      return <SendPlan>[
        ...pushInto(<SendPlan>[], sysTo(bySeat, '物品名不能为空')),
      ];
    }
    final qty = raClampNumber(p['qty'], 1, 9999, 1);
    final note = cleanText(p['note'], 80);
    return forEachTarget(bySeat, p['seat'], '给予物品', (m) {
      if (raMemberRipped(m)) {
        return <SendPlan>[
          ...pushInto(<SendPlan>[], sysTo(bySeat,
              '「${raNick(this, m, jsStr(m['seat']))}」已撕卡，无法给予物品')),
        ];
      }
      final list = List<Object?>.from(asList(asMap(m['sheet'])['items']));
      localSeq += 1;
      list.add(<String, Object?>{
        'id': 'i$localSeq',
        'name': name,
        'qty': qty,
        'note': note,
      });
      return stateApply(jsStr(m['seat']), <String, Object?>{'items': list},
          <String, Object?>{'reason': 'KP 给予物品：$name'});
    });
  }

  /// SAN 大失败追加理智损失（掷 1D10，不自动扣；旧版 :5517-5558）。
  List<SendPlan> sheetSanLoss(String bySeat, Map<String, Object?> p) {
    final dice = cleanText(p['dice'], 12).isNotEmpty
        ? cleanText(p['dice'], 12)
        : '1D10';
    return forEachTarget(bySeat, p['seat'], '追加理智损失', (m) {
      final out = <SendPlan>[];
      if (raMemberRipped(m)) {
        pushInto(out, sysTo(bySeat,
            '「${raNick(this, m, jsStr(m['seat']))}」已撕卡，无法追加理智损失'));
        return out;
      }
      if (raMemberMadActive(m)) {
        pushInto(out, sysTo(bySeat,
            '「${raNick(this, m, jsStr(m['seat']))}」正处于疯狂发作中，不能追加理智损失'));
        return out;
      }
      final rolled = rules?.rollExpr(dice, rng);
      final loss = (rolled != null && rolled['ok'] == true)
          ? (raNum(rolled['total'], 0) > 0 ? raNum(rolled['total'], 0) : 0)
          : 0;
      if (loss <= 0) {
        pushInto(out, sysTo(bySeat, '追加理智损失骰无效：$dice'));
        return out;
      }
      var san = raMemberStatusValue(m, 'currentSAN');
      san ??= raMemberStatusValue(m, 'maxSAN');
      if (san == null) {
        pushInto(out, sysTo(bySeat,
            '该玩家还没有理智值（未绑定角色卡），无法追加理智损失'));
        return out;
      }
      final after = (san - loss) > 0 ? san - loss : 0;
      final who = raNick(this, m, jsStr(m['seat']));
      out.addAll(diceRoll(jsStr(m['seat']), <String, Object?>{
        'expr': dice,
        'label': 'SAN 大失败追加理智损失',
        'result': <String, Object?>{
          'rolls': rolled?['rolls'] ?? <Object?>[],
          'value': loss,
          'detail': rolled?['detail'] ?? '',
        },
      }));
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': jsStr(m['seat']),
        'kind': 'check',
        'text': '$who SAN 大失败，按规则书追加理智损失：$dice = ${loss.toInt()}，'
            'SAN ${san.toInt()} → ${after.toInt()}',
        'at': now(),
      }, vis: RoomVis.public));
      out.addAll(stateApply(jsStr(m['seat']),
          <String, Object?>{'status': <String, Object?>{'currentSAN': after}},
          <String, Object?>{'reason': 'SAN 大失败追加 $dice -${loss.toInt()}'}));
      if (loss > 0) out.addAll(afterSanLoss(m, loss, bySeat));
      return out;
    });
  }

  /// 治愈伤势（旧版 :4782-4836）。
  List<SendPlan> healWound(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final target = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : (bySeat == kHostSeat ? '' : bySeat);
    if (bySeat != kHostSeat && target != bySeat) {
      pushInto(out, sysTo(bySeat, '只能申请治愈自己的伤势'));
      return out;
    }
    final m = roster.get(target);
    if (m == null) {
      pushInto(out, sysTo(bySeat, '找不到该玩家'));
      return out;
    }
    if (raMemberRipped(m)) {
      pushInto(out, sysTo(bySeat,
          '「${raNick(this, m, target)}」已撕卡（死亡/永久疯狂），无法治愈'));
      return out;
    }
    if (m['sheet'] is! Map) {
      m['sheet'] = raSanitizeSheet(<String, Object?>{}, m, now());
    }
    final sheet = asMap(m['sheet']);
    if (sheet['status'] is! Map) {
      sheet['status'] = raSanitizeStatus(<String, Object?>{}, sheet);
    }
    final st = asMap(sheet['status']);
    final viewBefore = bodyView(st);
    if (st['body'] != '重伤' &&
        !jsTruthy(st['dying']) &&
        !jsTruthy(st['unconscious'])) {
      pushInto(out, sysTo(bySeat,
          '「${raNick(this, m, target)}」当前没有需要治愈的伤势（$viewBefore），无需治愈'));
      return out;
    }
    var curHP = raMemberStatusValue(m, 'currentHP');
    curHP ??= 0;
    if (curHP <= 0) {
      out.addAll(applyHpChange(m, 1 - curHP, '治愈伤势：恢复至 1 点生命',
          <String, Object?>{}));
    }
    var hpNow = raMemberStatusValue(m, 'currentHP');
    hpNow ??= curHP > 0 ? curHP : 1;
    final maxHP = raMemberStatusValue(m, 'maxHP');
    final newBody = (maxHP != null && maxHP > 0 && hpNow >= maxHP)
        ? '正常'
        : '轻伤';
    out.addAll(stateApply(target, <String, Object?>{
      'status': <String, Object?>{
        'body': newBody,
        'dying': false,
        'unconscious': false,
      },
    }, <String, Object?>{'reason': '治愈伤势'}));
    out.addAll(syncBodyToCombatSlot(m));
    pending.removeWhere((q) => q['op'] == 'sheet.healwound' &&
        (q['by'] == target || asMap(q['p'])['seat'] == target));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': '${raNick(this, m, target)} 的伤势（$viewBefore）已被治愈'
          '（${bySeat == kHostSeat ? 'KP 裁定' : 'KP 同意'}），身体状态：$newBody',
      'at': now(),
      'kind': 'state',
    }, vis: RoomVis.public));
    return out;
  }

  /// 队友施救（急救 / 医学；旧版 :4856-4958）。
  List<SendPlan> aidApply(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final healerSeat = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : bySeat;
    final targetSeat = cleanText(p['targetSeat'], 64);
    final skill = cleanText(p['skill'], 8);
    if (skill != '急救' && skill != '医学') {
      pushInto(out, sysTo(bySeat, '施救技能只能是「急救」或「医学」'));
      return out;
    }
    if (targetSeat.isEmpty) {
      pushInto(out, sysTo(bySeat, '请先选择施救目标'));
      return out;
    }
    final healer = roster.get(healerSeat);
    final target = roster.get(targetSeat);
    if (healer == null) {
      pushInto(out, sysTo(bySeat, '找不到施救者'));
      return out;
    }
    if (target == null) {
      pushInto(out, sysTo(bySeat, '找不到施救目标'));
      return out;
    }
    if (raMemberRipped(healer)) {
      pushInto(out, sysTo(bySeat,
          '施救者「${raNick(this, healer, healerSeat)}」已撕卡（死亡/永久疯狂），无法施救'));
      return out;
    }
    if (raMemberRipped(target)) {
      pushInto(out, sysTo(bySeat,
          '「${raNick(this, target, targetSeat)}」已撕卡（死亡/永久疯狂），无法施救'));
      return out;
    }
    // P17（KP-6 追加裁决）：KP 表单手填的「检定数值」优先；不带 `base`
    // （老载荷 / 玩家申请）时原样回落角色卡技能值，行为逐字不变。
    final base = (bySeat == kHostSeat
            ? raPayloadBaseOverride(p)
            : null) ??
        skillBaseOf(healer, skill, null);
    if (base == null) {
      pushInto(out, sysTo(bySeat,
          '施救者还没有登记「$skill」技能值（请先绑定角色卡）'));
      return out;
    }
    final chk = rules?.check(<String, Object?>{
      'base': raNum(base, 0),
      'difficulty': 'regular',
      'kind': 'skill',
      'label': '$skill 检定',
      'rng': rng,
    });
    if (chk == null) {
      pushInto(out, sysTo(bySeat, '规则服务不可用，施救未结算'));
      return out;
    }
    final healerWho = raNick(this, healer, healerSeat);
    final targetWho = raNick(this, target, targetSeat);
    out.addAll(diceRoll(healerSeat, <String, Object?>{
      'expr': '1D100',
      'label': '施救·$skill 检定（对 ${raNum(base, 0).toInt()}）',
      'result': chk,
    }));
    if (chk['passed'] != true) {
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': healerSeat,
        'text': '$healerWho 对 $targetWho 使用「$skill」失败'
            '（${jsStr(chk['levelText'] ?? '失败')}），没有效果'
            '${chk['value'] != null ? '（掷 ${jsStr(chk['value'])}）' : ''}',
        'at': now(),
        'kind': 'check',
      }, vis: RoomVis.public));
      return out;
    }
    num heal = 1;
    if (skill == '医学') {
      final rr = rules?.rollExpr('1D3', rng);
      heal = (rr != null && rr['ok'] == true)
          ? (raNum(rr['total'], 1) > 1 ? raNum(rr['total'], 1) : 1)
          : 1;
    }
    final stBefore = asMap(asMap(target['sheet'])['status']);
    final dyingBefore = jsTruthy(stBefore['dying']);
    final unconsciousBefore = jsTruthy(stBefore['unconscious']);
    var gainNote = '，恢复 ${heal.toInt()} 点生命';
    out.addAll(applyHpChange(target, heal, '$skill（$healerWho 施救）',
        <String, Object?>{}));
    if (dyingBefore) {
      final bodyNow = jsStr(asMap(asMap(target['sheet'])['status'])['body']);
      if (bodyNow != '死亡') {
        out.addAll(stateApply(targetSeat, <String, Object?>{
          'status': <String, Object?>{'body': '重伤', 'dying': false},
        }, <String, Object?>{'reason': '$skill 稳定濒死伤势'}));
        out.addAll(syncBodyToCombatSlot(target));
        gainNote += '，已脱离濒死（稳定为重伤）';
      }
    } else if (unconsciousBefore) {
      var hW = raMemberStatusValue(target, 'currentHP');
      hW ??= 0;
      if (hW <= 0) {
        out.addAll(applyHpChange(target, 1 - hW,
            '$skill 唤醒昏迷：恢复至 1 点生命', <String, Object?>{}));
        hW = raMemberStatusValue(target, 'currentHP') ?? 1;
      }
      final mxW = raMemberStatusValue(target, 'maxHP');
      final bodyW = (mxW != null && mxW > 0 && hW >= mxW) ? '正常' : '轻伤';
      out.addAll(stateApply(targetSeat, <String, Object?>{
        'status': <String, Object?>{'body': bodyW, 'unconscious': false},
      }, <String, Object?>{'reason': '$skill 唤醒昏迷'}));
      out.addAll(syncBodyToCombatSlot(target));
      gainNote += '，已唤醒（$bodyW）';
    }
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': healerSeat,
      'text': '$healerWho 对 $targetWho 使用「$skill」成功$gainNote'
          '${chk['value'] != null ? '（掷 ${jsStr(chk['value'])}）' : ''}',
      'at': now(),
      'kind': 'check',
    }, vis: RoomVis.public));
    return out;
  }

  /// 精神分析（治愈不定疯狂 + 回 SAN；旧版 :4979-5111）。
  List<SendPlan> psychoAnalyze(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final srcSeat = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : bySeat;
    final targetSeat = cleanText(p['targetSeat'], 64);
    if (targetSeat.isEmpty) {
      pushInto(out, sysTo(bySeat, '请先选择精神分析目标'));
      return out;
    }
    final src = roster.get(srcSeat);
    final target = roster.get(targetSeat);
    if (src == null) {
      pushInto(out, sysTo(bySeat, '找不到发起者'));
      return out;
    }
    if (target == null) {
      pushInto(out, sysTo(bySeat, '找不到精神分析目标'));
      return out;
    }
    if (raMemberRipped(src)) {
      pushInto(out, sysTo(bySeat,
          '发起者「${raNick(this, src, srcSeat)}」已撕卡（死亡/永久疯狂），无法进行精神分析'));
      return out;
    }
    if (raMemberRipped(target)) {
      pushInto(out, sysTo(bySeat,
          '「${raNick(this, target, targetSeat)}」已撕卡（死亡/永久疯狂），无法作为精神分析目标'));
      return out;
    }
    final meta = asMap(state['meta']);
    if (meta['psychoRound'] is! Map) meta['psychoRound'] = <String, Object?>{};
    final psychoRound = asMap(meta['psychoRound']);
    final curRound = raNum(meta['round'], 0);
    final lastRound = raFinite(psychoRound[targetSeat]);
    if (lastRound != null && (curRound - lastRound) < 5) {
      final left = 5 - (curRound - lastRound);
      pushInto(out, sysTo(bySeat,
          '「${raNick(this, target, targetSeat)}」仍处于精神治疗冷却（还需 ${left.toInt()} 回合）'));
      return out;
    }
    final targetSheet = asMap(target['sheet']);
    final ml = asList(targetSheet['mental']);
    final alreadyMad = asList(targetSheet['madness']).isNotEmpty ||
        ml.contains('临时疯狂') ||
        ml.contains(kRaMentalIndef) ||
        ml.contains(kRaMentalIndefFaded) ||
        ml.contains(kRaMentalPermanent);
    // P17（KP-6 追加裁决）：同 `aidApply`——KP 手填检定数值优先，老载荷零变化。
    final base = (bySeat == kHostSeat
            ? raPayloadBaseOverride(p)
            : null) ??
        skillBaseOf(src, '精神分析', null);
    if (base == null) {
      pushInto(out, sysTo(bySeat,
          '发起者还没有登记「精神分析」技能值（请先绑定角色卡）'));
      return out;
    }
    final chk = rules?.check(<String, Object?>{
      'base': raNum(base, 0),
      'difficulty': 'regular',
      'kind': 'skill',
      'label': '精神分析 检定',
      'rng': rng,
    });
    if (chk == null) {
      pushInto(out, sysTo(bySeat, '规则服务不可用，精神分析未结算'));
      return out;
    }
    final srcWho = raNick(this, src, srcSeat);
    final targetWho = raNick(this, target, targetSeat);
    out.addAll(diceRoll(srcSeat, <String, Object?>{
      'expr': '1D100',
      'label': '精神分析 检定（对 ${raNum(base, 0).toInt()}）',
      'result': chk,
    }));
    if (chk['passed'] != true) {
      final lossRoll = rules?.rollExpr('1D6', rng);
      final sanLoss = (lossRoll != null && lossRoll['ok'] == true)
          ? (raNum(lossRoll['total'], 1) > 1 ? raNum(lossRoll['total'], 1) : 1)
          : 1;
      /* P8（需求 6）：目标处于临时 / 不定疯狂时**不受任何 SAN 减损**。 */
      final targetMadActive =
          mental_state.blockedByMadness(asList(targetSheet['mental']));
      var sanBefore = raMemberStatusValue(target, 'currentSAN');
      sanBefore ??= raMemberStatusValue(target, 'maxSAN');
      sanBefore ??= 0;
      final appliedLoss = targetMadActive ? 0 : sanLoss;
      final sanAfter =
          (sanBefore - appliedLoss) > 0 ? sanBefore - appliedLoss : 0;
      if (appliedLoss > 0) {
        out.addAll(stateApply(targetSeat, <String, Object?>{
          'status': <String, Object?>{'currentSAN': sanAfter},
        }, <String, Object?>{'reason': '$srcWho 精神分析失败：${appliedLoss.toInt()} SAN'}));
      }
      pushInto(out, emit(RoomEvt.log, <String, Object?>{
        'seat': srcSeat,
        'kind': 'check',
        'text': '$srcWho 对 $targetWho 进行精神分析失败'
            '（${jsStr(chk['levelText'] ?? '失败')}，掷 ${jsStr(chk['value'] ?? '?')}），'
            '${targetMadActive ? '$targetWho 正处于临时 / 不定疯狂，本次不受 SAN 减损' : '$targetWho 失去 ${appliedLoss.toInt()} 点理智'
                '（SAN ${sanBefore.toInt()} → ${sanAfter.toInt()}）'}'
            '${alreadyMad ? '，因已处于疯狂状态不新增疯狂症' : ''}',
        'at': now(),
      }, vis: RoomVis.public));
      if (!alreadyMad) {
        out.addAll(afterSanLoss(target, appliedLoss, bySeat));
      }
      return out;
    }
    // 成功：治愈临时/不定疯狂 + 本次发作症状，回 1D3 SAN。
    final mental = List<Object?>.from(asList(targetSheet['mental']));
    final md = List<Object?>.from(asList(targetSheet['madness']));
    final hadTemp = mental.contains('临时疯狂');
    final hadIndef = mental.contains(kRaMentalIndef) ||
        mental.contains(kRaMentalIndefFaded);
    final mdCured = md
        .where((x) => !(x is Map &&
            (asMap(x)['from'] == '临时疯狂' ||
                asMap(x)['from'] == kRaMentalIndef)))
        .toList();
    final curedSymptomCount = md.length - mdCured.length;
    final curedAny = hadTemp || hadIndef || curedSymptomCount > 0;
    final curedParts = <String>[];
    if (hadTemp) curedParts.add('临时疯狂');
    if (hadIndef) curedParts.add('不定疯狂');
    if (curedSymptomCount > 0) curedParts.add('$curedSymptomCount 项疯狂症状');
    if (!curedAny) {
      pushInto(out, sysTo(bySeat,
          '「$targetWho」当前没有可治愈的精神状态（无临时/不定疯狂、无本次发作症状），精神分析未产生治愈效果（仍结算 SAN）'));
    } else {
      var nextMental = mental
          .where((x) => x != '临时疯狂' &&
              x != kRaMentalIndef &&
              x != kRaMentalIndefFaded)
          .toList();
      if (nextMental.isEmpty) nextMental = <Object?>['正常'];
      if (mdCured.isEmpty) {
        nextMental = nextMental.where((x) => x != kRaMentalSymptom).toList();
      }
      out.addAll(stateApply(targetSeat, <String, Object?>{
        'mental': nextMental,
        'madness': mdCured,
      }, <String, Object?>{
        'reason': '$srcWho 精神分析治愈：${curedParts.join('、')}',
      }));
    }
    var sanNow = raMemberStatusValue(target, 'currentSAN');
    sanNow ??= raMemberStatusValue(target, 'maxSAN');
    sanNow ??= 0;
    final sanMax = raMemberStatusValue(target, 'maxSAN');
    final restore = rules?.rollExpr('1D3', rng);
    final gain = (restore != null && restore['ok'] == true)
        ? (raNum(restore['total'], 1) > 1 ? raNum(restore['total'], 1) : 1)
        : 1;
    final sanAfter2 = (sanMax != null && sanMax > 0)
        ? (raNum(sanNow, 0) + gain < sanMax ? raNum(sanNow, 0) + gain : sanMax)
        : (raNum(sanNow, 0) + gain);
    var sanRecovered = '';
    if (sanAfter2 > raNum(sanNow, 0)) {
      sanRecovered = '，恢复 ${(sanAfter2 - raNum(sanNow, 0)).toInt()} 点理智';
      out.addAll(stateApply(targetSeat, <String, Object?>{
        'status': <String, Object?>{'currentSAN': sanAfter2},
      }, <String, Object?>{'reason': '$srcWho 精神分析恢复理智'}));
    }
    psychoRound[targetSeat] = curRound.toInt();
    sanLostThisRound[targetSeat] = 0;
    roundStartSan.remove(targetSeat);
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': srcSeat,
      'kind': 'state',
      'text': '$srcWho 对 $targetWho 进行精神分析成功'
          '（掷 ${jsStr(chk['value'] ?? '?')}）'
          '${curedAny ? '，治愈其${curedParts.join('、')}' : ''}'
          '$sanRecovered（每 5 回合限一次）',
      'at': now(),
    }, vis: RoomVis.public));
    return out;
  }

  /// 推进 1 轮：消除临时疯狂症状倒计时（旧版 :5292-5363）。
  List<SendPlan> advanceMadness(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final target = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : (bySeat == kHostSeat ? '' : bySeat);
    if (bySeat != kHostSeat && target != bySeat) {
      pushInto(out, sysTo(bySeat, '只能推进自己的疯狂轮次'));
      return out;
    }
    final m = roster.get(target);
    if (m == null) {
      pushInto(out, sysTo(bySeat, '找不到该玩家'));
      return out;
    }
    if (m['sheet'] is! Map) {
      m['sheet'] = raSanitizeSheet(<String, Object?>{}, m, now());
    }
    final sheet = asMap(m['sheet']);
    if (sheet['madness'] is! List) sheet['madness'] = <Object?>[];
    final md = List<Object?>.from(asList(sheet['madness']));
    final faded = <Map<String, Object?>>[];
    for (var i = md.length - 1; i >= 0; i--) {
      final x = asMap(md[i]);
      if (jsTruthy(x['permanent']) || jsTruthy(x['bg'])) continue;
      final copy = <String, Object?>{...x};
      final oldRounds = raFinite(copy['rounds']);
      copy['rounds'] = oldRounds == null ? 1 : (oldRounds - 1);
      if (raNum(copy['rounds'], 0) <= 0) {
        faded.add(copy);
        md.removeAt(i);
      } else {
        md[i] = copy;
      }
    }
    final rawMental = sheet['mental'];
    var mental = rawMental is List
        ? List<Object?>.from(rawMental)
        : (rawMental == null ? <Object?>[] : <Object?>[rawMental]);
    // 老存档兼容：旧名 → 潜在疯狂
    mental = mental
        .map((x) => x == kRaMentalLegacyPotential ? kRaMentalPotential : x)
        .toList();
    final hasTempBout = md.any((x) =>
        !jsTruthy(asMap(x)['permanent']) &&
        asMap(x)['from'] == '临时疯狂');
    if (!hasTempBout && mental.contains('临时疯狂')) {
      // 临时疯狂：症状随轮次消退 → 回正常（不产生潜在疯狂）
      mental = mental_state
          .nextMentalState(mental, mental_state.MentalEvent.symptomFaded)
          .mental
          .cast<Object?>();
    }
    final hadIndefSymptom =
        faded.any((x) => x['from'] == kRaMentalIndef);
    final stillIndefSymptom =
        md.any((x) => asMap(x)['from'] == kRaMentalIndef);
    if (hadIndefSymptom &&
        !stillIndefSymptom &&
        mental.contains(kRaMentalIndef)) {
      // 不定疯狂：症状随轮次消退 → 潜在疯狂（掉 SAN 会立刻复发）
      mental = mental_state
          .nextMentalState(
            mental,
            mental_state.MentalEvent.symptomFaded,
            fromIndefinite: true,
          )
          .mental
          .cast<Object?>();
      fadedArm[target] = true;
    }
    if (md.isEmpty) {
      mental = mental.where((x) => x != kRaMentalSymptom).toList();
    }
    if (mental.isEmpty) mental = <Object?>['正常'];
    final who = raNick(this, m, target);
    var reason = '推进 1 轮';
    if (faded.isNotEmpty) {
      reason += '，${faded.map((x) => jsStr(x['name'])).join('、')} 消退';
    }
    out.addAll(stateApply(target, <String, Object?>{
      'madness': md,
      'mental': mental,
    }, <String, Object?>{'reason': reason}));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': '$who 推进 1 轮'
          '${faded.isNotEmpty ? '：${faded.map((x) => jsStr(x['name'])).join('、')} 已消退' : ''}',
      'at': now(),
      'kind': 'state',
    }, vis: RoomVis.public));
    return out;
  }

  /// 治愈不定疯狂（旧版 :5371-5439）。
  List<SendPlan> cureIndefinite(String bySeat, Map<String, Object?> p) {
    final out = <SendPlan>[];
    final target = cleanText(p['seat'], 64).isNotEmpty
        ? cleanText(p['seat'], 64)
        : (bySeat == kHostSeat ? '' : bySeat);
    if (bySeat != kHostSeat && target != bySeat) {
      pushInto(out, sysTo(bySeat, '只能治愈自己的不定疯狂'));
      return out;
    }
    final m = roster.get(target);
    if (m == null) {
      pushInto(out, sysTo(bySeat, '找不到该玩家'));
      return out;
    }
    if (raMemberRipped(m)) {
      pushInto(out, sysTo(bySeat,
          '「${raNick(this, m, target)}」已撕卡（死亡/永久疯狂），无法治愈'));
      return out;
    }
    final sheet = asMap(m['sheet']);
    /* P8（需求 6）：治愈按钮同时取消「不定疯狂」与「潜在疯狂」；
       「疯狂症状」（背景标记）与「永久疯狂」（撕卡级）不在此列。 */
    final mental = List<Object?>.from(asList(sheet['mental']))
        .map((x) => x == kRaMentalLegacyPotential ? kRaMentalPotential : x)
        .toList();
    final onlyBg = raOnlyBgSymptoms(sheet['madness']);
    final hasIndefOrPotential =
        mental.contains(kRaMentalIndef) || mental.contains(kRaMentalPotential);
    if (!hasIndefOrPotential) {
      if (onlyBg) {
        pushInto(out, sysTo(bySeat,
            '「${raNick(this, m, target)}」的『疯狂症状』来自角色背景，不可治愈、不可取消'));
      } else if (mental.contains('临时疯狂')) {
        pushInto(out, sysTo(bySeat,
            '临时疯狂不需要治愈：它会随症状消退自动消失（请点「推进 1 轮」）。只有「不定疯狂 / 潜在疯狂」才需治愈。'));
      } else {
        pushInto(out, sysTo(bySeat, '当前没有「不定疯狂 / 潜在疯狂」状态'));
      }
      return out;
    }
    final next = mental_state
        .nextMentalState(mental, mental_state.MentalEvent.cured)
        .mental
        .cast<Object?>();
    if (next.isEmpty) next.add('正常');
    sanLostThisRound[target] = 0;
    roundStartSan.remove(target);
    out.addAll(stateApply(target, <String, Object?>{'mental': next},
        <String, Object?>{'reason': '治愈不定 / 潜在疯狂'}));
    pending.removeWhere((q) => q['op'] == 'madness.cure' &&
        (q['by'] == target || asMap(q['p'])['seat'] == target));
    pushInto(out, emit(RoomEvt.log, <String, Object?>{
      'seat': '',
      'text': '${raNick(this, m, target)} 的不定 / 潜在疯狂已被治愈'
          '（${bySeat == kHostSeat ? 'KP 裁定' : 'KP 同意'}）',
      'at': now(),
      'kind': 'state',
    }, vis: RoomVis.public));
    return out;
  }
}
