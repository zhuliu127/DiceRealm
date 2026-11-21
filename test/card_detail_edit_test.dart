// ============================================================
// card_detail_edit_test.dart — 角色卡详情页的编辑 / 删除 / 导入导出（widget 级）
//
// 每条用例名里都标了它钉住的是哪一条硬约束：
//   硬约束 1 空输入 ≠ 0
//   硬约束 2 改 HP 不得触发疯狂
//   硬约束 3 撕卡口径（HP 归零二次确认 → 死亡；SAN 归零 → 永久疯狂）
//   硬约束 5 导入导出 round-trip 等价
//   硬约束 6 卡片数据契约不变（能直接吃旧版导出）
// ============================================================

import 'dart:io';

import 'package:dice_realm/domain/js_compat.dart';
import 'package:dice_realm/domain/rules_coc7.dart';
import 'package:dice_realm/repo/card_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

String _legacyFixture() =>
    File('test/fixtures/legacy_card_export.json').readAsStringSync();

void main() {
  group('编辑 → 保存（对齐 store.js#beginEdit / commitEdit）', () {
    testWidgets('改姓名 / 居住地 / 背景 → 保存后写回仓库', (tester) async {
      final repo = await pumpCardDetail(tester);
      expect(find.text('测试调查员'), findsWidgets);

      await tapKey(tester, 'btn_edit');
      expect(find.textContaining('正在编辑'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('edit_field_name')), '改过的名字');
      await tester.enterText(
        find.byKey(const Key('edit_field_residence')),
        '阿卡姆',
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, 'bg_field_ideology');
      await tester.enterText(
        find.byKey(const Key('bg_field_ideology')),
        '真相必须被记录。',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();

      final saved = repo.get('card0001')!;
      expect(saved.characterName, '改过的名字');
      expect(jsStr(saved.basicInfo['residence']), '阿卡姆');
      expect(jsStr(saved.background['ideology']), '真相必须被记录。');
      expect(find.text('改过的名字'), findsWidgets, reason: '保存后回到只读态');
    });

    testWidgets('取消编辑：角色卡恢复原样（一个字都不写）', (tester) async {
      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'btn_edit');
      await tester.enterText(
        find.byKey(const Key('edit_field_name')),
        '不该保存的名字',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'btn_cancel_edit');

      expect(repo.get('card0001')!.characterName, '测试调查员');
      expect(find.text('测试调查员'), findsWidgets);
    });
  });

  group('硬约束 1：空输入 ≠ 0', () {
    testWidgets('清空 HP 输入框后保存：卡仍存活、HP 数值不变', (tester) async {
      final repo = await pumpCardDetail(tester);
      final before = jsNum(repo.get('card0001')!.status['currentHP']);
      expect(before, 10);

      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'status_hp');
      await tester.enterText(find.byKey(const Key('status_hp')), '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();

      // 没有撕卡弹窗
      expect(find.text('确认撕卡'), findsNothing);

      final saved = repo.get('card0001')!;
      expect(
        jsNum(saved.status['currentHP']),
        before,
        reason: '清空只是"没提交"，不是归零',
      );
      expect(jsStr(saved.status['body']), '正常');
      expect(repo.fallen, isEmpty, reason: '卡必须仍然存活');
    });
  });

  group('硬约束 3：撕卡口径与二次确认', () {
    testWidgets('真输入 HP=0 → 保存弹二次确认 → 确认后 body=死亡并进英灵殿', (tester) async {
      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'status_hp');
      await tester.enterText(find.byKey(const Key('status_hp')), '0');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();

      // 必须先出现二次确认
      expect(find.text('确认撕卡'), findsOneWidget);
      await tapKey(tester, 'confirm_rip');

      final saved = repo.get('card0001')!;
      expect(jsStr(saved.status['body']), '死亡');
      expect(repo.alive, isEmpty);
      expect(repo.fallen.length, 1, reason: '撕卡后进英灵殿');
    });

    testWidgets('取消撕卡确认 → 什么都不写，留在编辑态', (tester) async {
      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'status_hp');
      await tester.enterText(find.byKey(const Key('status_hp')), '0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'cancel_rip');

      final stored = repo.get('card0001')!;
      expect(jsStr(stored.status['body']), '正常', reason: '取消 = 不写撕卡');
      expect(jsNum(stored.status['currentHP']), 10, reason: '原卡纹丝不动');
      expect(find.text('确认撕卡'), findsNothing);
    });

    testWidgets('SAN 归零 → 确认后永久疯狂（不是死亡）', (tester) async {
      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'status_san');
      await tester.enterText(find.byKey(const Key('status_san')), '0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('永久疯狂'), findsWidgets);
      await tapKey(tester, 'confirm_rip');

      final saved = repo.get('card0001')!;
      expect(
        asList(saved.status['mental']).map(jsStr),
        contains(mentalPermanent),
      );
      expect(jsStr(saved.status['body']), '正常', reason: 'SAN 归零不等于身体死亡');
      expect(repo.fallen.length, 1);
    });
  });

  group('硬约束 2：改 HP 不得触发疯狂', () {
    testWidgets('只改 HP、SAN 不动 → 保存后 mental 无新增、madness 不新增', (tester) async {
      final repo = await pumpCardDetail(tester);
      final before = asList(repo.get('card0001')!.status['mental'])
          .map(jsStr)
          .toList();
      final madBefore = asList(repo.get('card0001')!.raw['madness']).length;

      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'status_hp');
      await tester.enterText(find.byKey(const Key('status_hp')), '4');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();

      expect(find.text('确认撕卡'), findsNothing, reason: 'HP 4 还没到 0');
      final saved = repo.get('card0001')!;
      expect(jsNum(saved.status['currentHP']), 4);
      expect(
        asList(saved.status['mental']).map(jsStr).toList(),
        before,
        reason: '改 HP 绝不能顺手 append 疯狂症状（旧版 v2.1.8 的 bug）',
      );
      expect(asList(saved.raw['madness']).length, madBefore);
    });

    testWidgets('掷临时疯狂是显式操作：只在玩家点按钮时新增', (tester) async {
      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'btn_roll_madness');
      await tapKey(tester, 'btn_roll_madness');
      expect(
        asList(repo.get('card0001')!.raw['madness']).length,
        0,
        reason: '还没保存',
      );

      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();
      expect(asList(repo.get('card0001')!.raw['madness']).length, 1);
    });
  });

  group('删除角色卡', () {
    testWidgets('菜单 → 删除 → 二次确认 → 仓库删除并回首页', (tester) async {
      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'card_menu');
      await tester.tap(find.text('删除角色'));
      await tester.pumpAndSettle();
      expect(find.textContaining('此操作不可恢复'), findsOneWidget);

      await tapKey(tester, 'confirm_delete');

      expect(repo.all, isEmpty);
      // ★ P8：详情页是从「角色档案」名册页点进来的，删完自然回到名册页，
      //   名册页此时给空态；再返回一次才回首页。断言强度没变（依旧验证
      //   「删干净了」+「能回到首页」），只是多了一跳。
      expect(find.text('还没有角色卡，从上方「按流程车卡」开始'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('骰境TRPG'), findsOneWidget, reason: '回到首页');
    });

    testWidgets('删除对话框点取消：卡还在', (tester) async {
      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'card_menu');
      await tester.tap(find.text('删除角色'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'cancel_delete');
      expect(repo.get('card0001'), isNotNull);
    });
  });

  group('导入 / 导出', () {
    testWidgets('硬约束 5：详情页导出 → JSON 能被再导入且逐字段相等（除 id）', (tester) async {
      final io = useFakeTransferIo();
      await pumpCardDetail(tester);

      await tapKey(tester, 'card_menu');
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();

      expect(io.exportCount, 1);
      expect(io.lastFileName, 'coc7-测试调查员.json');
      final json = io.lastJson!;

      // 形状与旧版一致
      expect(
        json.startsWith(
          '{\n  "format": "coc7-card",\n  "version": 1,\n  "data": {',
        ),
        isTrue,
      );

      // round-trip：再导入解析出的卡，除 id 外与原卡逐字段相等
      final back = parseCardImport(json).cards.first;
      final original = Map<String, Object?>.from(
        parseCardImport(json).cards.first,
      );
      expect(back['id'], original['id']);
      expect(back['characterName'], '测试调查员');
      expect(jsNum((back['status']! as Map)['currentHP']), 10);
    });

    testWidgets('硬约束 6：首页导入旧版真实导出的 JSON → 新增一张卡，原卡还在', (tester) async {
      final io = useFakeTransferIo(importPayload: _legacyFixture());
      final repo = await pumpApp(tester);
      await repo.save(validCard());
      await tester.pumpAndSettle();

      await tapKey(tester, 'home_menu');
      await tester.tap(find.text('导入角色 JSON'));
      await tester.pumpAndSettle();

      expect(io.importPayload, isNotNull);
      expect(repo.all.length, 2, reason: '导入是新增，不是覆盖');
      final imported = repo.all.firstWhere((c) => c.characterName == '旧版调查员');
      expect(imported.id, isNot('legacy01'), reason: '导入后必须重新分配 id');
      expect(repo.get('card0001'), isNotNull, reason: '原卡还在');
      // ★ P8：卡片收进二级页「角色档案」，进名册确认新卡真的上屏
      await tapKey(tester, 'home_roster_entry');
      expect(find.text('旧版调查员'), findsOneWidget);
    });

    testWidgets('导入失败给出可读错误（不静默吞掉）', (tester) async {
      useFakeTransferIo(importPayload: '{"playerName":"缺名字"}');
      final repo = await pumpApp(tester);

      await tapKey(tester, 'home_menu');
      await tester.tap(find.text('导入角色 JSON'));
      await tester.pumpAndSettle();

      expect(repo.all, isEmpty);
      expect(find.textContaining('导入失败'), findsOneWidget);
    });

    testWidgets('全量导出：首页菜单写出 coc7-bundle 形状', (tester) async {
      final io = useFakeTransferIo();
      final repo = await pumpApp(tester);
      await repo.save(validCard());
      await tester.pumpAndSettle();

      await tapKey(tester, 'home_menu');
      await tester.tap(find.text('导出全部角色'));
      await tester.pumpAndSettle();

      expect(io.lastFileName, 'coc7-characters.json');
      final parsed = parseCardImport(io.lastJson!);
      expect(parsed.bundle, isTrue);
      expect(parsed.count, 1);
      expect(parsed.cards.first['characterName'], '测试调查员');
    });
  });

  group('撕卡不可编辑（旧版 v2.1.8 同款约束）', () {
    testWidgets('已死亡的卡没有「编辑」按钮，但能导出 / 删除', (tester) async {
      final dead = validCard(id: 'dead0001', name: '长眠者');
      dead.status['body'] = '死亡';
      await pumpCardDetail(tester, card: dead);

      expect(find.byKey(const Key('btn_edit')), findsNothing);
      expect(find.byKey(const Key('card_menu')), findsOneWidget);
      expect(find.textContaining('已经死亡'), findsOneWidget);
    });
  });
}
