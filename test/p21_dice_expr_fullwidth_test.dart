// ============================================================
// test/p21_dice_expr_fullwidth_test.dart — 骰式全角符号容错验收
//
// 背景（用户原话）：「我尝试用自定义骰子输入 d6+d10，如果 + 是全角符号（中文）
//   则无法识别公式，改为全角符号也可以解析。」
//
// 根因：`_parseExpr` 只在开头 `toUpperCase`，而分词正则 `[+-]?[^+-]+` 只认
//   半角 `+`/`-`；全角 `＋`（U+FF0B）不被当作分隔符，整串 `D6＋D10` 被
//   当成一个 token → 「骰式里有无法识别的片段」。
//
// 修复：`_parseExpr` 入口先做全角→半角归一化（`_normalizeExprInput`），
//   覆盖全角 ASCII 区（`＋ － ０-９ Ｄ ｄ` 等）、全角空格、以及破折号变体
//   `— – − ～`。只做字符映射，不改解析语义。
// ============================================================
import 'package:dice_realm/domain/room_rules.dart' show CocRules;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const CocRules rules = CocRules();

  Map<String, Object?> parse(String e) => rules.parseExpr(e);

  group('P21 骰式全角符号容错', () {
    test('半角基线：d6+d10 可解析（两个骰子项）', () {
      final r = parse('d6+d10');
      expect(r['ok'], true, reason: '半角表达式必须可用：$r');
      expect((r['terms'] as List).length, 2);
    });

    test('全角加号：d6＋d10（U+FF0B）可解析', () {
      final r = parse('d6＋d10');
      expect(r['ok'], true, reason: '全角 ＋ 也必须识别：$r');
      expect((r['terms'] as List).length, 2);
      final t0 = (r['terms'] as List)[0] as Map;
      final t1 = (r['terms'] as List)[1] as Map;
      expect(t0['sides'], 6);
      expect(t1['sides'], 10);
    });

    test('全角减号：2d6－1（U+FF0D）→ 第二个项为负常数', () {
      final r = parse('2d6－1');
      expect(r['ok'], true, reason: '全角 － 也必须识别：$r');
      final terms = r['terms'] as List;
      expect(terms.length, 2);
      expect((terms[1] as Map)['sign'], -1);
    });

    test('全角数字与字母：Ｄ６＋ｄ１０ 可解析', () {
      final r = parse('Ｄ６＋ｄ１０');
      expect(r['ok'], true, reason: '全角数字/字母也必须识别：$r');
      final terms = r['terms'] as List;
      expect((terms[0] as Map)['sides'], 6);
      expect((terms[1] as Map)['sides'], 10);
    });

    test('数学减号 U+2212 与破折号变体也归一化为减号', () {
      for (final String dash in <String>['−', '—', '–', '～']) {
        final r = parse('1d6${dash}1');
        expect(r['ok'], true, reason: '减号变体「$dash」也必须识别：$r');
        expect((r['terms'] as List)[1] as Map,
            containsPair('sign', -1));
      }
    });

    test('全角空格不破坏解析', () {
      final r = parse('1d6\u3000+\u30001d4');
      expect(r['ok'], true, reason: '全角空格也必须容忍：$r');
      expect((r['terms'] as List).length, 2);
    });

    test('脏字符仍被拒（回归：归一化不放宽非法输入）', () {
      expect(parse('d6+abc')['ok'], false);
      expect(parse('d6**2')['ok'], false);
    });
  });
}
