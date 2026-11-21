// ============================================================
// share_client.dart — 角色卡云分享的 HTTP 客户端
// 对应 `core/share.js` 的 create() / remove() / buildPayload()
//
// 后端接口约定（路由 / 响应与旧版逐字一致；data 内字段自 P7 起带规则标记）：
//   POST {base}/api/cards            body {name, visibility, data}
//                                    →  {id, url, delToken}
//   POST {base}/api/cards/<id>/del   body {token}
//                                    →  2xx 即成功
//
// 🔒 `delToken` 是「删除口令」：**只落本机**，不上传、不进导出、不进日志。
//    它出现在响应体里一次，之后只由 `ShareStore` 保管。
//
// ⚠️ 未配置 `shareBase` 时**不发请求**，直接抛 `unconfigured` —— 界面据此
//    引导去设置页，而不是让用户看到一个莫名其妙的网络错误。
//
// ★ P7 收尾（用户明确要求「云分享链接带规则徽标」）：生产载荷的 `data`
//   层新增 `ruleSystemId` / `ruleShortName`，这是**有意偏离旧版** wire
//   契约（`core/share.js#buildPayload` 没有这两个字段）。P3 冻结逐字节
//   预言机仍验旧版契约，靠 [legacySharePayloadForOracle] 开关隔离，
//   套路与上一批 `lib/domain/ai_caps.dart#legacyAttrCapForOracle` 一致。
// ============================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/character.dart';
import '../domain/js_compat.dart';
import '../domain/rule_registry.dart';
import '../domain/secret_mask.dart';
import 'http_io.dart';

/// 分享失败的分类
enum ShareErrorKind {
  /// 没配服务地址
  unconfigured,

  /// 本机没有该卡的分享记录（删除时）
  noRecord,

  /// 网络层失败（DNS / TLS / 超时）
  unreachable,

  /// 服务端返回非 2xx
  http,

  /// 返回不是 JSON / 缺字段
  badResponse,
}

class ShareException implements Exception {
  ShareException(this.kind, this.message);
  final ShareErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// 创建分享的返回值（`delToken` 只应交给 ShareStore）
class ShareCreateResult {
  const ShareCreateResult({
    required this.id,
    required this.url,
    required this.delToken,
  });
  final String id;
  final String url;
  final String delToken;
}

/// 服务地址规范化（去掉尾部斜杠）
String normalizeShareBase(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');

/// 地址看起来可用（设置页即时校验用；与旧版 `looksValid` 同口径）
bool looksValidShareBase(String u) => RegExp(
  r'^https?://[^\s/]+',
  caseSensitive: false,
).hasMatch(normalizeShareBase(u));

/// 头像体积大（data URL 可能几百 KB），且服务端不展示，剔除后再上传
Map<String, Object?> _slimSkill(Map<String, Object?> s) => <String, Object?>{
  'name': s['name'],
  'total': s['total'],
  'base': s['base'],
  'occ': s['occ'],
  'int': s['int'],
  'growth': s['growth'],
};

/// 旧版 wire 契约隔离开关（默认 **false** = 生产真发规则字段）。
///
/// P7 用户要求「云分享链接带规则徽标」，生产载荷的 `data` 层新增
/// `ruleSystemId` / `ruleShortName` —— 这是一次**有意偏离旧版** wire 契约。
/// 但 `test/qa_p3_h2_h3_test.dart` 与 `test/qa_p3_final_gate_test.dart`
/// 的冻结 fixture 抓自旧版 `core/share.js#buildPayload`，做的是逐字节比对，
/// 职责是证明「移植 == 旧版」，断言与 fixture 都不许动。故沿用上一批
/// `legacyAttrCapForOracle` 的「生产 / 预言机双路径」套路：开关只作用在
/// [ShareClient.create] 实际调用的**同一个** [buildSharePayload] 上，
/// 探针在 setUp 置 true 即逐字节回到旧版，生产与全部其它测试保持 false。
///
/// ⚠️ 绝不另写一个 `buildSharePayloadLegacy` 专供测试 —— 那会把预言机
/// 变成「测一个没人调用的死函数」，wire 级验证由
/// `test/p7_share_badge_test.dart` 打真实 FakeServer 补上。
bool legacySharePayloadForOracle = false;

/// 上传用的请求体（`share.js#buildPayload` + P7 规则标记）
///
/// ⚠️ 这是**精简视图**，不是完整存档：目的是让对方能看、不能改。
///    完整卡仍在本机，导出/导入走另一条路径（[card_transfer]）。
Map<String, Object?> buildSharePayload(Character c, {int? sharedAt}) {
  final raw = c.raw;
  // 旧版 `(c.basicInfo || {}).occupationName || ''`：老卡缺这个字段时给空串。
  // 不能用 jsStr(null)——那是字符串 'null'，会被当成职业名上传。
  final occ = c.basicInfo['occupationName'];
  final data = <String, Object?>{
    'characterName': raw['characterName'],
    'playerName': raw['playerName'],
    'basicInfo': c.basicInfo,
    'attributes': c.attributes,
    'derivedStats': c.derivedStats,
    'status': c.status,
    'assets': c.assets,
    'background': c.background,
    'skills': c.skills.map((s) => _slimSkill(asMap(s))).toList(),
    'weapons': asList(raw['weapons'])
        .map(
          (w) => <String, Object?>{
            'name': asMap(w)['name'],
            'skill': asMap(w)['skill'],
            'damage': asMap(w)['damage'],
            'range': asMap(w)['range'],
            'ammo': asMap(w)['ammo'],
          },
        )
        .toList(),
    'items': asList(raw['items'])
        .map(
          (i) => <String, Object?>{
            'name': asMap(i)['name'],
            'quantity': asMap(i)['quantity'],
            'description': asMap(i)['description'],
          },
        )
        .toList(),
    'mythos': raw['mythos'],
    'history': raw['history'],
    'unitName': jsTruthy(occ) ? jsStr(occ) : '',
    'sharedAt': sharedAt ?? nowMillis(),
  };

  if (!legacySharePayloadForOracle) {
    // ★ 一致性口径：先算「已开放规则 id」，再用该 id 取简称。
    //   不能对原始 id 直接 shortNameOf —— 老卡的 'null' / 空串 / 瞎填 /
    //   占位 id（'dnd5e'、'custom'）会让两个字段自相矛盾。effectiveId
    //   把这些一律收敛到 'coc7'，也保证绝不会把 jsStr(null) 的字符串
    //   'null' 写进载荷。
    final rid = RuleRegistry.effectiveId(c.ruleSystemId);
    data['ruleSystemId'] = rid;
    data['ruleShortName'] = RuleRegistry.shortNameOf(rid);
  }

  return <String, Object?>{
    'name': jsTruthy(raw['characterName']) ? raw['characterName'] : '未命名调查员',
    'visibility': jsTruthy(raw['shareVisibility'])
        ? raw['shareVisibility']
        : 'link',
    'data': data,
  };
}

/// 云分享的网络能力（抽出来是为了让 widget 测试能注入假实现 ——
/// fake-async 区域里真实 HTTP 永远不会完成）
abstract class ShareApi {
  /// 当前生效的地址（空串 = 未配置）
  String get base;

  bool get configured;

  Future<ShareCreateResult> create(Character c);
  Future<void> remove(String shareId, String token);
}

/// 云分享 HTTP 客户端
class ShareClient implements ShareApi {
  ShareClient({
    required String Function() baseProvider,
    this.timeout = const Duration(seconds: 30),
  }) : _base = baseProvider;

  final String Function() _base;
  final Duration timeout;

  @override
  String get base => normalizeShareBase(_base());

  @override
  bool get configured => base.isNotEmpty;

  /// 创建分享。成功后**只返回** id/url/delToken，不碰本地存储
  /// （落盘由 `ShareStore` 负责，职责分开才好测）。
  @override
  Future<ShareCreateResult> create(Character c) async {
    final b = base;
    if (b.isEmpty) {
      throw ShareException(ShareErrorKind.unconfigured, '还没配置分享服务地址');
    }
    final body = jsonEncode(buildSharePayload(c));
    final res = await httpRequest(
      '$b/api/cards',
      'POST',
      <String, String>{'Content-Type': 'application/json'},
      body,
      timeout: timeout,
    );
    if (res.error != null) {
      throw ShareException(
        ShareErrorKind.unreachable,
        maskSecrets('无法连接分享服务：${res.error}'),
      );
    }
    if (!res.ok) {
      final body =
          res.body.length > 140 ? res.body.substring(0, 140) : res.body;
      throw ShareException(
        ShareErrorKind.http,
        maskSecrets('服务器返回 ${res.status}：$body'),
      );
    }
    final j = decodeJsonOrNull(res.body);
    if (j is! Map) {
      throw ShareException(ShareErrorKind.badResponse, '分享服务返回的内容不是 JSON');
    }
    // ⚠️ 必须用 jsTruthy 判空，不能直接 jsStr：`jsStr(null)` 是字符串 'null'，
    //    会让「服务端少返回一个字段」变成「url 就叫 null」这种鬼结果。
    String field(Object? v) => jsTruthy(v) ? jsStr(v) : '';
    final id = field(j['id']);
    final url = field(j['url']);
    if (id.isEmpty || url.isEmpty) {
      throw ShareException(ShareErrorKind.badResponse, '分享服务没有返回 id / url');
    }
    return ShareCreateResult(id: id, url: url, delToken: field(j['delToken']));
  }

  /// 删除分享（需要 delToken）
  @override
  Future<void> remove(String shareId, String token) async {
    final b = base;
    if (b.isEmpty) {
      throw ShareException(ShareErrorKind.unconfigured, '还没配置分享服务地址');
    }
    final res = await httpRequest(
      '$b/api/cards/$shareId/del',
      'POST',
      <String, String>{'Content-Type': 'application/json'},
      jsonEncode(<String, Object?>{'token': token}),
      timeout: timeout,
    );
    if (res.error != null) {
      throw ShareException(
        ShareErrorKind.unreachable,
        maskSecrets('无法连接分享服务：${res.error}'),
      );
    }
    if (!res.ok) {
      throw ShareException(
        ShareErrorKind.http,
        maskSecrets('删除失败（${res.status}）'),
      );
    }
  }
}

/// 让「网络断开」这类异常也带上分类（方便 UI 统一处理）
@visibleForTesting
ShareException shareErrorFrom(Object e) {
  if (e is ShareException) return e;
  return ShareException(ShareErrorKind.unreachable, maskSecrets('$e'));
}
