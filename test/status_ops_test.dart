// ============================================================
// status_ops_test.dart — 状态管理的写入通道（纯逻辑，无 widget）
//
// 每条用例的名字里都标了它钉住的是哪一条硬约束：
//   硬约束 1 空输入 ≠ 0
//   硬约束 2 改 HP 不得触发疯狂
//   硬约束 3 撕卡口径（SAN 归零 → 永久疯狂；HP 归零 → 二次确认后死亡）
//   硬约束 4 濒死角色不得被 recalc 悄悄治活
//
// QA 复核（IS_PASS=NO）后本文件补了 D1/D3/D4 的真测：
//   · 原来那条「从导入 / 外部写回」其实调的是 setStatusNumber（自带标记），
//     对导入路径零覆盖 —— 已换成**真的走 importIntoRepo + JSON 文本**（D3）。
//   · 新增「显式存在的值才标记」「LUCK 与属性相等时不标记」等 D1 语义用例。
//   · 新增 D4：'007' / ' 7 ' / '+7' 与 7 数值等价，不该被判成「改过」。
// ============================================================

import 'package:dice_realm/domain/character.dart';
import 'package:dice_realm/domain/engine.dart';
import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/madness.dart' as mad;
import 'package:dice_realm/domain/rules_coc7.dart';
import 'package:dice_realm/repo/card_transfer.dart';
import 'package:dice_realm/repo/character_repo.dart';
import 'package:dice_realm/ui/status_ops.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一张属性齐备、已初始化的卡（HP 10 / MP 10 / SAN 50 / LUCK 50）
Character _card() {
  final c = Character(newCharacter());
  for (final k in <String>[
    'str',
    'con',
    'siz',
    'dex',
    'app',
    'int',
    'pow',
    'edu',
    'luck',
  ]) {
    c.attributes[k] = 50;
  }
  recalc(c);
  return c;
}

void main() {
  group('硬约束 1：空输入 ≠ 0', () {
    test('清空 HP 输入框（空串 / 纯空白）不写入模型，数值不变', () {
      final c = _card();
      final before = jsNum(c.status['currentHP']);
      expect(before, 10);

      expect(commitStatusNumber(c, 'currentHP', ''), isFalse);
      expect(commitStatusNumber(c, 'currentHP', '   '), isFalse);
      recalc(c);

      expect(jsNum(c.status['currentHP']), before, reason: '清空只是"没提交"，不是归零');
      expect(isRippedCard(c), isFalse, reason: '卡必须仍然存活');
    });

    test('非数字输入同样不写入', () {
      final c = _card();
      expect(commitStatusNumber(c, 'currentSAN', 'abc'), isFalse);
      expect(jsNum(c.status['currentSAN']), 50);
    });

    test('真输入 0 才会写进模型（并打上「用户改过」标记）', () {
      final c = _card();
      expect(commitStatusNumber(c, 'currentHP', '0'), isTrue);
      expect(jsNum(c.status['currentHP']), 0);
      expect(jsTruthy(c.status['_hpTouched']), isTrue);
    });

    test('数值被夹到 0..上限（输入 999 不会写进 999）', () {
      final c = _card();
      expect(commitStatusNumber(c, 'currentHP', '999'), isTrue);
      expect(jsNum(c.status['currentHP']), jsNum(c.status['maxHP']));
    });
  });

  group('硬约束 4：濒死角色不得被 recalc 悄悄治活（P0 报告坑 B）', () {
    test('写入 HP=0 → recalc → 仍然是 0', () {
      final c = _card();
      setStatusNumber(c, 'currentHP', 0);
      recalc(c);
      expect(jsNum(c.status['currentHP']), 0, reason: '打了 _hpTouched 就该保持 0');
    });

    test('D3：真的走 importIntoRepo（JSON 文本）把 HP=0 导进来 → recalc 两次仍为 0', () async {
      // 造一张「跑团里被打到 0 血」的卡，并**刻意不带** _hpTouched（模拟外部来源）
      final src = _card();
      src.raw['id'] = 'imported01';
      src.raw['characterName'] = '濒死者';
      recalc(src);
      src.status['currentHP'] = 0;
      src.status.remove('_hpTouched');
      final json = exportCardJson(src);

      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final c = (await importIntoRepo(repo, json)).single;

      expect(
        jsNum(c.status['currentHP']),
        0,
        reason: '导入的濒死卡被 recalc 补满 = 被治活',
      );
      recalc(c);
      recalc(c);
      expect(jsNum(c.status['currentHP']), 0, reason: 'recalc 连跑后仍应为 0');
      expect(jsNum(c.status['currentMP']), 10, reason: '其他字段不受影响');
    });

    test('D3 独立用例：setStatusNumber 自身会打标记（与导入路径语义不同，不许合并）', () {
      final c = _card();
      setStatusNumber(c, 'currentHP', 0);
      expect(jsTruthy(c.status['_hpTouched']), isTrue);
      recalc(c);
      expect(jsNum(c.status['currentHP']), 0);
    });

    test('反面证明：不打标记时 recalc 确实会把 0 补满（所以标记是必需的）', () {
      final c = _card();
      c.status['currentHP'] = 0; // 绕过通道，不写 _hpTouched
      recalc(c);
      expect(
        jsNum(c.status['currentHP']),
        jsNum(c.status['maxHP']),
        reason: '这正是「濒死被 recalc 治活」的老 bug，通道必须打标记来避免它',
      );
    });

    test('SAN 归零同样不被 recalc 补回', () {
      final c = _card();
      setStatusNumber(c, 'currentSAN', 0);
      recalc(c);
      expect(jsNum(c.status['currentSAN']), 0);
      expect(jsTruthy(c.status['_sanTouched']), isTrue);
    });
  });

  group('硬约束 3：撕卡口径', () {
    test('HP 归零只报 hpDown（→ 死亡），不带 sanDown', () {
      final c = _card();
      setStatusNumber(c, 'currentHP', 0);
      recalc(c);
      final p = ripPending(c);
      expect(p.hit, isTrue);
      expect(p.hpDown, isTrue);
      expect(p.sanDown, isFalse);
      expect(p.reasons.single, contains('死亡'));
    });

    test('SAN 归零只报 sanDown（→ 永久疯狂）', () {
      final c = _card();
      setStatusNumber(c, 'currentSAN', 0);
      recalc(c);
      final p = ripPending(c);
      expect(p.hit, isTrue);
      expect(p.hpDown, isFalse);
      expect(p.sanDown, isTrue);
      expect(p.reasons.single, contains('永久疯狂'));
    });

    test('没走到 applyRip 之前，卡不算撕卡（HP=0 只是「待判定」）', () {
      final c = _card();
      setStatusNumber(c, 'currentHP', 0);
      recalc(c);
      expect(ripPending(c).hit, isTrue);
      expect(isRippedCard(c), isFalse, reason: '撕卡要玩家二次确认后才写');
    });

    test('applyRip：hpDown → body=死亡；sanDown → mental=[永久疯狂]', () {
      final hp = _card();
      setStatusNumber(hp, 'currentHP', 0);
      recalc(hp);
      applyRip(hp, ripPending(hp));
      expect(jsStr(hp.status['body']), '死亡');
      expect(isRippedCard(hp), isTrue);
      expect(isRippedCard(hp), isTrue, reason: 'body===死亡 是既有判据，不放宽不收紧');

      final san = _card();
      setStatusNumber(san, 'currentSAN', 0);
      recalc(san);
      applyRip(san, ripPending(san));
      expect(asList(san.status['mental']).map(jsStr).toList(), <String>[
        mentalPermanent,
      ]);
      expect(isRippedCard(san), isTrue);
      expect(jsStr(san.status['body']), '正常', reason: 'SAN 归零不该判成死亡');
    });

    test('SAN 上限减损到 0 也算 sanDown（旧版同一口径）', () {
      final c = _card();
      setSanLoss(c, jsNum(c.status['baseMaxSAN']));
      expect(jsNum(c.status['maxSAN']), 0);
      final p = ripPending(c);
      expect(p.sanDown, isTrue);
    });

    test('已显式标记「死亡」的卡：ripPending.flagged 为真', () {
      final c = _card();
      setBody(c, '死亡');
      final p = ripPending(c);
      expect(p.flagged, isTrue);
      expect(p.hpDown, isFalse, reason: 'HP 还满着，只是被标记了');
    });
  });

  group('硬约束 2：改 HP 不得触发疯狂', () {
    test('只改 HP、SAN 不动 → mental 无新增、madness 无新增', () {
      final c = _card();
      final mentalBefore = asList(c.status['mental']).map(jsStr).toList();
      final madBefore = mad.list(c).length;

      setStatusNumber(c, 'currentHP', 3);
      recalc(c);
      final p = prepareStatusSave(c);

      expect(p.hit, isFalse, reason: 'HP 还没到 0，不该有任何撕卡判定');
      expect(asList(c.status['mental']).map(jsStr).toList(), mentalBefore);
      expect(mad.list(c).length, madBefore, reason: '绝不能因为改 HP 就 append 一条疯狂');
    });

    test('真掉 SAN 到 0 → 疯狂逻辑仍然正常（反面断言）', () {
      final c = _card();
      setStatusNumber(c, 'currentSAN', 0);
      final p = prepareStatusSave(c);
      expect(p.sanDown, isTrue);
      applyRip(c, p);
      expect(asList(c.status['mental']).map(jsStr), contains(mentalPermanent));
      expect(isRippedCard(c), isTrue);
    });

    test('疯狂列表只由显式操作改变：toggleMental 不碰 madness', () {
      final c = _card();
      final before = mad.list(c).length;
      applyMentalToggle(c, '临时疯狂');
      expect(mad.list(c).length, before);
    });
  });

  group('精神状态互斥规则（旧版 mentalSelect 口径）', () {
    test('「正常」互斥：选它只剩它', () {
      final c = _card();
      c.status['mental'] = <Object?>['临时疯狂', '不定疯狂'];
      expect(applyMentalToggle(c, mentalNormal), isTrue);
      expect(asList(c.status['mental']).map(jsStr).toList(), <String>[
        mentalNormal,
      ]);
    });

    test('「永久疯狂」互斥：选它只剩它，再点取消回「正常」', () {
      final c = _card();
      c.status['mental'] = <Object?>['临时疯狂'];
      expect(applyMentalToggle(c, mentalPermanent), isTrue);
      expect(asList(c.status['mental']).map(jsStr).toList(), <String>[
        mentalPermanent,
      ]);
      expect(applyMentalToggle(c, mentalPermanent), isTrue);
      expect(asList(c.status['mental']).map(jsStr).toList(), <String>[
        mentalNormal,
      ]);
    });

    test('「疯狂症状」是派生项：点它不改数组', () {
      final c = _card();
      c.status['mental'] = <Object?>['临时疯狂'];
      expect(applyMentalToggle(c, mentalSymptom), isFalse);
      expect(asList(c.status['mental']).map(jsStr).toList(), <String>['临时疯狂']);
    });
  });

  group('幸运 / 减损', () {
    test('未手动改过时幸运跟随属性；改过之后不再被 recalc 覆盖', () {
      final c = _card();
      expect(jsNum(c.status['currentLuck']), 50);
      setStatusNumber(c, 'currentLuck', 33);
      recalc(c);
      expect(jsNum(c.status['currentLuck']), 33);
    });

    test('SAN 上限减损折算进 maxSAN = 意志 − 减损', () {
      final c = _card();
      final base = jsNum(c.status['baseMaxSAN']);
      setSanLoss(c, 10);
      expect(jsNum(c.status['maxSAN']), base - 10);
      expect(jsNum(c.raw['sanLoss']), 10);
    });
  });

  group('D1：导入 / 外部回写不得把濒死卡治活（走 repo.save 通道）', () {
    /// 造一张指定状态的卡并导出成 JSON 文本（模拟「外部来源的卡」）
    String exportWith(void Function(Character c) mutate) {
      final c = _card();
      c.raw['id'] = 'ext00001';
      c.raw['characterName'] = '外部卡';
      recalc(c);
      mutate(c);
      return exportCardJson(c);
    }

    Future<Character> importText(String json) async {
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      return (await importIntoRepo(repo, json)).single;
    }

    test('导入 HP=0 的卡 → recalc 两次仍为 0', () async {
      final json = exportWith((c) {
        c.status['currentHP'] = 0;
        c.status.remove('_hpTouched');
      });
      final c = await importText(json);
      expect(jsNum(c.status['currentHP']), 0);
      recalc(c);
      recalc(c);
      expect(jsNum(c.status['currentHP']), 0);
    });

    test('导入 HP=0 且 body=死亡 的卡 → 仍是 0，且 isRippedCard / 进英灵殿', () async {
      final json = exportWith((c) {
        c.status['currentHP'] = 0;
        c.status['body'] = '死亡';
        c.status.remove('_hpTouched');
      });
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final c = (await importIntoRepo(repo, json)).single;
      expect(jsNum(c.status['currentHP']), 0);
      expect(isRippedCard(c), isTrue);
      // 导入会重新分配 id（不覆盖原卡），所以这里按导入后的 id 断言
      expect(repo.fallen.map((x) => x.id), contains(c.id));
      expect(repo.alive, isEmpty);
    });

    test('导入 SAN=0 + 永久疯狂 的卡 → SAN 仍为 0，mental 保持「永久疯狂」', () async {
      final json = exportWith((c) {
        c.status['currentSAN'] = 0;
        c.status['mental'] = <Object?>[mentalPermanent];
        c.status.remove('_sanTouched');
      });
      final c = await importText(json);
      expect(
        jsNum(c.status['currentSAN']),
        0,
        reason: '永久疯狂卡的 SAN 被补回 —— 同一处守卫的另一面',
      );
      expect(asList(c.status['mental']).map(jsStr), contains(mentalPermanent));
      expect(jsTruthy(c.status['_sanTouched']), isTrue);
    });

    test('反面：导入一张完全正常的卡（HP=7/10）→ 仍是 7，不进英灵殿', () async {
      final json = exportWith((c) {
        c.status['currentHP'] = 7;
        c.status.remove('_hpTouched');
      });
      final repo = CharacterRepo(storage: MemoryStorage());
      await repo.load();
      final c = (await importIntoRepo(repo, json)).single;
      expect(jsNum(c.status['currentHP']), 7);
      expect(isRippedCard(c), isFalse);
      expect(repo.alive.length, 1, reason: '别把活人送进英灵殿');
    });

    test('反面：不打标记直接 recalc → 仍然补满（证明 recalc 的守卫还在、没被改没）', () {
      final c = _card();
      recalc(c);
      c.status['currentHP'] = 0;
      c.status.remove('_hpTouched');
      recalc(c);
      expect(
        jsNum(c.status['currentHP']),
        greaterThan(0),
        reason: '守卫一旦被改没，上面那几条「没有意义地通过」',
      );
    });

    test('status 里根本没有 currentHP 键的老卡 → 导入后按旧版语义补满，不误判死亡', () async {
      final c = _card();
      c.raw['id'] = 'noHp0001';
      recalc(c);
      (c.raw['status']! as Map).remove('currentHP');
      (c.raw['status']! as Map).remove('_hpTouched');
      final json = exportCardJson(c);

      final imported = await importText(json);
      expect(
        jsNum(imported.status['currentHP']),
        jsNum(imported.status['maxHP']),
        reason: '没有显式值 → 按旧版初始化补满',
      );
      expect(
        jsTruthy(imported.status['_hpTouched']),
        isNot(isTrue),
        reason: '没有显式值就不许打「用户改过」标记',
      );
      expect(isRippedCard(imported), isFalse);
    });

    test('标记只针对「会被 recalc 覆盖」的显式值：LUCK 33（属性 50）保留，LUCK==属性 不打标记', () async {
      final keep = await importText(
        exportWith((c) => c.status['currentLuck'] = 33),
      );
      expect(jsNum(keep.status['currentLuck']), 33, reason: '玩家改过的幸运不能被属性覆盖');
      expect(jsTruthy(keep.status['_luckTouched']), isTrue);

      final follow = await importText(
        exportWith((c) => c.status['currentLuck'] = 50),
      );
      expect(jsNum(follow.status['currentLuck']), 50);
      expect(
        jsTruthy(follow.status['_luckTouched']),
        isNot(isTrue),
        reason: '与 LUCK 属性相同 → 视为未改过，保留「幸运跟随属性」的旧语义',
      );
    });

    test('applyExplicitStatusMarks 幂等：连跑两次标记结果不变', () {
      final c = _card();
      c.status['currentHP'] = 0;
      c.status.remove('_hpTouched');
      applyExplicitStatusMarks(c);
      final first = c.status['_hpTouched'];
      applyExplicitStatusMarks(c);
      expect(c.status['_hpTouched'], first);
      expect(first, isTrue);
    });
  });

  group('D4：输入框「值没变」按数值比较', () {
    test("'007' / ' 7 ' / '+7' 与 7 数值等价 → 不打标记", () {
      for (final raw in <String>['7', '007', ' 7 ', '+7']) {
        expect(statusTextEquals(raw, 7), isTrue, reason: '$raw 与 7 应等价');
      }
      expect(statusTextEquals('8', 7), isFalse);
      expect(statusTextEquals('', 7), isFalse, reason: '空串不是 7');
      expect(statusTextEquals('abc', 7), isFalse);
      expect(statusTextEquals('0', 0), isTrue);
    });

    test('真实路径：模型 7 时输入 007 不会打 _luckTouched', () {
      final c = _card();
      c.status['currentLuck'] = 7;
      c.status.remove('_luckTouched');
      // 模拟 _commit 的判断：文本与模型数值相等 → 直接 return，不写、不标记
      if (!statusTextEquals('007', c.status['currentLuck'])) {
        commitStatusNumber(c, 'currentLuck', '007');
      }
      expect(jsTruthy(c.status['_luckTouched']), isNot(isTrue));
      recalc(c);
      expect(jsNum(c.status['currentLuck']), 50, reason: '幸运仍跟随属性（未被冻结）');
    });
  });
}
