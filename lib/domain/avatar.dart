// ============================================================
// avatar.dart — 自动头像（复古徽章风格 SVG，dataURI 直存进卡的 avatar 字段）
// 逐行对应 `core/avatar.js`（106 行）
//
// 为什么不用外部图片：不占体积（一张约 1KB）、不发请求、按名字散列
// 配色 + 首字，所以「不同的人看起来不一样」，一列角色卡不会全是同一个灰底 ◈。
//
// ⚠️ 这不是「美化」代码，是**数据生成**代码：avatar 字符串会写进角色卡的
//    `avatar` 字段并参与导出/比对，所以每个字符都必须与 JS 一致 ——
//    包括 `(120 + 100*cos(ang)).toFixed(1)` 的取整与
//    `encodeURIComponent` 的转义集合。
// ============================================================

import 'dart:convert';
import 'dart:math' as math;

import 'js_compat.dart';

/// 配色：底色渐变 + 主色（描线与文字）
class _Palette {
  const _Palette(this.a, this.b, this.f);
  final String a;
  final String b;
  final String f;
}

const List<_Palette> _palettes = <_Palette>[
  _Palette('#233047', '#111a28', '#d4a94a'),
  _Palette('#2c3f3a', '#0f1d1a', '#57c2ab'),
  _Palette('#3a2733', '#1b1018', '#d98aa0'),
  _Palette('#2f2a3f', '#14111f', '#a99be8'),
  _Palette('#3d2f22', '#1d1510', '#e0b072'),
  _Palette('#22364a', '#0d161f', '#7fb2d8'),
  _Palette('#3b2b2b', '#1a1111', '#e08a6a'),
  _Palette('#33403f', '#141b1b', '#c8cfa8'),
];

/// 古早 / 神秘题材用暖调多一点
const List<int> _warm = <int>[4, 6, 0, 2, 7];

/// JS 的 `x >>> 0`（ToUint32）
int _toUint32(int v) => v & 0xFFFFFFFF;

/// JS 的 `x | 0`（ToInt32）
int _toInt32(int v) {
  final u = v & 0xFFFFFFFF;
  return u >= 0x80000000 ? u - 0x100000000 : u;
}

/// JS 的 `(a * b) >>> 0`，其中 `a` 是 int32。
///
/// ⚠️ 必须走 double 再截断：`hv * 16777619` 在 JS 里是**双精度乘法**，
///    结果可达 3.6e16，远超 2^53 —— JS 会先舍入到最近的可表示 double
///    再 TakeUint32。用整数乘法算会得到**不同的低 32 位**，
///    于是同一个名字在两边散列出不同的配色。
int _mulToUint32(int a, int b) {
  final prod = a.toDouble() * b.toDouble();
  if (!prod.isFinite) return 0;
  final truncated = prod.truncateToDouble();
  final m = truncated % 4294967296.0; // Dart 的 % 是欧几里得取模（结果非负）
  return m.toInt();
}

/// FNV-1a 变体（`avatar.js#strHash`）
int strHash(Object? s) {
  var hv = 2166136261; // 注意：这是 **Number**，不是 int32
  final str = jsTruthy(s) ? jsStr(s) : '';
  for (final c in str.codeUnits) {
    hv = _toInt32(hv) ^ c; // JS `^=` 会先把两侧转成 int32
    hv = _mulToUint32(hv, 16777619);
  }
  return _toUint32(hv);
}

/// 取姓名的首字：中文取第一个汉字；西文译名取第一段的第一个字母
String initialOf(Object? name) {
  final n = jsTruthy(name) ? jsStr(name).trim() : '';
  if (n.isEmpty) return '？';
  for (final ch in n.codeUnits) {
    if (ch >= 0x4E00 && ch <= 0x9FA5) return String.fromCharCode(ch);
  }
  // JS `n.charAt(0).toUpperCase()`：单个 UTF-16 code unit 再转大写
  return String.fromCharCode(n.codeUnits.first).toUpperCase();
}

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// ECMAScript `encodeURIComponent` 的转义集合：
/// 保留 `A-Za-z0-9` 与 `- _ . ! ~ * ' ( )`，其余按 UTF-8 逐字节 %XX（大写十六进制）。
///
/// 自己实现而不是用 `Uri.encodeComponent`：后者依赖 Dart SDK 的 unreserved 表，
/// 万一版本间有差就会让 avatar 字符串整体不等（导出比对立刻红）。
String _encodeUriComponent(String s) {
  final out = StringBuffer();
  for (final b in utf8.encode(s)) {
    final isAlnum =
        (b >= 0x30 && b <= 0x39) ||
        (b >= 0x41 && b <= 0x5A) ||
        (b >= 0x61 && b <= 0x7A);
    final isSafe =
        b == 0x2D || // -
        b == 0x5F || // _
        b == 0x2E || // .
        b == 0x21 || // !
        b == 0x7E || // ~
        b == 0x2A || // *
        b == 0x27 || // '
        b == 0x28 || // (
        b == 0x29; // )
    if (isAlnum || isSafe) {
      out.writeCharCode(b);
    } else {
      out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// 自动头像的**视觉参数**（与 [make] 产生的 SVG 完全同源）。
///
/// 为什么要把参数抽出来：SVG 版只够本机显示 —— Flutter 的引擎不解码 SVG，
/// 于是「没上传头像的玩家」跨设备只能退化成首字圆点。P10 第 3 期 A 批
/// 在 UI 层用 `PictureRecorder` 把同一份参数画成 PNG dataURI 送广播。
/// 两份实现必须画同一个东西，所以**取色 / 散列参数只在这里算一次**：
/// SVG 与 PNG 都读 [AvatarSpec]，不可能再散开成两套调色板。
class AvatarSpec {
  const AvatarSpec({
    required this.bgTop,
    required this.bgBottom,
    required this.foreground,
    required this.initial,
    required this.rotationDegrees,
    required this.dots,
  });

  /// 渐变底色（`#RRGGBB`）。
  final String bgTop;
  final String bgBottom;

  /// 主色：描线 / 圆点 / 首字。
  final String foreground;

  /// 首字（已按 [initialOf] 取好，**未**做 XML 转义 —— 转义是 SVG 的事）。
  final String initial;

  /// 那段弧的旋转角（度，0..359）。
  final int rotationDegrees;

  /// 外圈圆点个数（6..10）。
  final int dots;
}

/// 取 [name] / [flavor] 对应的视觉参数（[make] 的唯一真相）。
AvatarSpec specOf(Object? name, [String flavor = '']) {
  final hv = strHash(jsTruthy(name) ? name : 'x');
  final _Palette pal;
  if (flavor == 'warm') {
    pal = _palettes[_warm[hv % _warm.length]];
  } else {
    pal = _palettes[hv % _palettes.length];
  }
  return AvatarSpec(
    bgTop: pal.a,
    bgBottom: pal.b,
    foreground: pal.f,
    initial: initialOf(name),
    rotationDegrees: hv % 360,
    dots: 6 + (hv % 5),
  );
}

/// 生成头像 dataURI（`avatar.js#make`）
///
/// @param name   角色名（决定首字与配色）
/// @param flavor `'warm'` 走暖色调（古代 / 1920 年代），其余按散列取
String make(Object? name, [String flavor = '']) {
  final spec = specOf(name, flavor);
  final ch = _escapeXml(spec.initial);
  final rot = spec.rotationDegrees;
  final dots = spec.dots;
  final pal = _Palette(spec.bgTop, spec.bgBottom, spec.foreground);

  final ring = StringBuffer();
  for (var i = 0; i < dots; i++) {
    final ang = (math.pi * 2 * i) / dots;
    final x = (120 + 100 * math.cos(ang)).toStringAsFixed(1);
    final y = (120 + 100 * math.sin(ang)).toStringAsFixed(1);
    ring.write(
      '<circle cx="$x" cy="$y" r="2.2" fill="${pal.f}" fill-opacity=".55"/>',
    );
  }

  final svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" '
      'width="240" height="240">'
      '<defs>'
      '<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">'
      '<stop offset="0" stop-color="${pal.a}"/>'
      '<stop offset="1" stop-color="${pal.b}"/>'
      '</linearGradient>'
      '</defs>'
      '<rect width="240" height="240" fill="url(#bg)"/>'
      '<circle cx="120" cy="120" r="104" fill="none" stroke="${pal.f}" '
      'stroke-opacity=".16" stroke-width="1"/>'
      '<circle cx="120" cy="120" r="88" fill="none" stroke="${pal.f}" '
      'stroke-opacity=".42" stroke-width="2"/>'
      '<path d="M60 120 A60 60 0 0 1 180 120" fill="none" stroke="${pal.f}" '
      'stroke-opacity=".22" stroke-width="6" stroke-linecap="round" '
      'transform="rotate($rot 120 120)"/>'
      '${ring.toString()}'
      '<text x="120" y="124" text-anchor="middle" dominant-baseline="middle" '
      'font-family="serif" font-size="98" font-weight="700" fill="${pal.f}">$ch</text>'
      '</svg>';

  return 'data:image/svg+xml;charset=utf-8,${_encodeUriComponent(svg)}';
}

/// 只在没有头像时填一张，已有就原样返回（`avatar.js#ensure`）
String ensure(Map<String, Object?> card, [String flavor = '']) {
  final cur = card['avatar'];
  if (jsTruthy(cur)) return jsStr(cur);
  final made = make(card['characterName'], flavor);
  card['avatar'] = made;
  return made;
}

/// 是否是本模块生成的自动头像（`data:image/svg+xml;charset=utf-8,`）。
///
/// 判据只认这一个前缀 + 我们自己写进去的 `viewBox="0 0 240 240"`：
/// 玩家上传的头像是 `data:image/(png|jpeg|webp);base64,`，绝不会命中。
bool isAutoAvatarSvg(Object? uri) {
  if (uri is! String) return false;
  final s = uri.trim();
  if (!s.startsWith('data:image/svg+xml;charset=utf-8,')) return false;
  try {
    return Uri.decodeComponent(s.substring(_kAutoSvgPrefixLen))
        .contains('viewBox="0 0 240 240"');
  } catch (_) {
    return false;
  }
}

const int _kAutoSvgPrefixLen = 34; // 'data:image/svg+xml;charset=utf-8,'.length

final RegExp _reStop = RegExp(r'stop-color="(#[0-9a-fA-F]{6})"');
final RegExp _reStroke = RegExp(r'stroke="(#[0-9a-fA-F]{6})"');
final RegExp _reRotate = RegExp(r'rotate\((\d+) 120 120\)');
final RegExp _reText = RegExp(r'>([^<>]*)</text>');
final RegExp _reDot = RegExp(r'<circle cx="[\d.]+" cy="[\d.]+" r="2\.2"');

/// 从自动头像 SVG 里**反解**视觉参数（老卡兼容用）。
///
/// 为什么需要反解：角色卡里只存了那条 SVG dataURI；而广播必须换成 PNG
/// （引擎不解码 SVG）。用名字 + 默认 flavor 重算虽然也能画，但会丢掉
/// `warm` 调色（`specOf(name, 'warm')` 与 `specOf(name)` 是不同颜色），
/// 于是同一个角色在本机（SVG）和别人设备上（PNG）会长得不一样。
/// 直接读回原串里的取色 / 转角 / 点数 → 两边**逐像素同源**。
///
/// 不是自动头像 / 格式不符 → null（调用方退回 [specOf]）。
AvatarSpec? specFromSvg(Object? uri) {
  if (!isAutoAvatarSvg(uri)) return null;
  final String svg;
  try {
    svg = Uri.decodeComponent(jsStr(uri).trim().substring(_kAutoSvgPrefixLen));
  } catch (_) {
    return null;
  }
  final stops = _reStop.allMatches(svg).toList();
  final strokes = _reStroke.allMatches(svg).toList();
  final rot = _reRotate.firstMatch(svg);
  final text = _reText.firstMatch(svg);
  if (stops.length < 2 || strokes.isEmpty || rot == null || text == null) {
    return null;
  }
  return AvatarSpec(
    bgTop: stops[0].group(1)!,
    bgBottom: stops[1].group(1)!,
    foreground: strokes.first.group(1)!,
    initial: _unescapeXml(text.group(1) ?? ''),
    rotationDegrees: int.tryParse(rot.group(1)!) ?? 0,
    dots: _reDot.allMatches(svg).length,
  );
}

String _unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&');
