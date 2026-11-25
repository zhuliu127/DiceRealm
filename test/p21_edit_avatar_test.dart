// ============================================================
// test/p21_edit_avatar_test.dart — 编辑已保存角色卡时可更换头像
//
// 需求（用户 m03520）：修改已保存角色卡时无法更换头像，需支持。
// 根因：card_edit/basics_editor.dart 里根本没有头像控件。
// 修法：在「基本资料」编辑区顶部加 AvatarPicker（keyPrefix edit_avatar），
//       写回 raw['avatar']，随详情页「保存」落库。
//
// 复用 p10_avatar_test.dart 的依赖注入套路：
//   avatarPicker / avatarImageImporter / avatarCropper 换成假实现，
//   避免 fake-async 区域里平台通道 / 引擎解码 Future 永不完成。
// ============================================================

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dice_realm/repo/avatar_store.dart';
import 'package:dice_realm/ui/widgets/avatar_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// 造一张纯色 PNG（真字节，可被 dart:ui 解码）。
Future<Uint8List> _makePng(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFFB23A3A),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 假选图：返回预置字节（null = 用户取消）。
class _FakeAvatarPicker implements AvatarPickerPort {
  _FakeAvatarPicker(this.bytes);
  Uint8List? bytes;
  int calls = 0;

  @override
  Future<Uint8List?> pickImageBytes({String? title, int maxBytes = 0}) async {
    calls++;
    return bytes;
  }
}

/// 假落盘：只记参数、直接给路径（真编解码在 p10/p21 crop 里覆盖）。
class _FakeImporter {
  final List<String> cardIds = <String>[];
  String? result = 'avatars/edit_replaced.png';

  Future<String?> call(Uint8List bytes, String cardId) async {
    cardIds.add(cardId);
    return result;
  }
}

/// 装一套假选图 + 假落盘 + 恒等裁切（用例结束自动还原）。
_FakeImporter _useFakePick(Uint8List bytes, String rel) {
  final fakeImporter = _FakeImporter()..result = rel;
  final prevPicker = avatarPicker;
  final prevImporter = avatarImageImporter;
  final prevCropper = avatarCropper;
  avatarPicker = _FakeAvatarPicker(bytes);
  avatarImageImporter = fakeImporter.call;
  avatarCropper = (BuildContext _, Uint8List b) async => b; // 恒等裁切
  addTearDown(() {
    avatarPicker = prevPicker;
    avatarImageImporter = prevImporter;
    avatarCropper = prevCropper;
  });
  return fakeImporter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List srcPng;
  setUpAll(() async {
    // 真编解码须在 widget 的 fake-async 区域之外做（否则 toImage Future 永不完成）。
    srcPng = await _makePng(48, 48);
  });

  group('P21 编辑已保存卡：更换头像', () {
    testWidgets('编辑态出现头像控件；选图 → 保存后 raw[avatar] 落库且带替换路径', (
      tester,
    ) async {
      final fake = _useFakePick(srcPng, 'avatars/edit_replaced.png');

      final repo = await pumpCardDetail(tester);
      expect(repo.get('card0001')!.raw['avatar'], '', reason: '初始无头像');

      await tapKey(tester, 'btn_edit');
      // 头像控件在编辑态可见（keyPrefix edit_avatar）
      await scrollTo(tester, 'edit_avatar');
      expect(find.byKey(const Key('edit_avatar')), findsOneWidget);
      expect(find.byKey(const Key('edit_avatar_pick')), findsOneWidget);

      // 点「选择图片」→ 假选图 → 假落盘
      await tapKey(tester, 'edit_avatar_pick');
      await tester.pumpAndSettle();
      expect(fake.cardIds, isNotEmpty, reason: '应该走落盘');
      // 落盘用的 cardId 应是这张卡的 id
      expect(fake.cardIds.last, 'card0001');

      // 保存
      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();

      final saved = repo.get('card0001')!;
      expect(
        saved.raw['avatar'],
        'avatars/edit_replaced.png',
        reason: '换的头像路径要写回仓库',
      );
    });

    testWidgets('编辑态取消编辑：选的头像不落库（一个字节都不写）', (tester) async {
      _useFakePick(srcPng, 'avatars/edit_should_not_save.png');

      final repo = await pumpCardDetail(tester);
      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'edit_avatar');
      await tapKey(tester, 'edit_avatar_pick');
      await tester.pumpAndSettle();

      // 取消编辑
      await tapKey(tester, 'btn_cancel_edit');

      expect(
        repo.get('card0001')!.raw['avatar'],
        '',
        reason: '取消编辑 = 不写回头像',
      );
    });

    testWidgets('编辑态移除头像：保存后 raw[avatar] 清空', (tester) async {
      _useFakePick(srcPng, 'avatars/edit_should_not_save2.png');

      // 造一张已有头像的卡
      final withAvatar = validCard(id: 'card0001', name: '测试调查员');
      withAvatar.raw['avatar'] = 'avatars/existing.png';
      final repo = await pumpCardDetail(tester, card: withAvatar);
      expect(repo.get('card0001')!.raw['avatar'], 'avatars/existing.png');

      await tapKey(tester, 'btn_edit');
      await scrollTo(tester, 'edit_avatar');
      // 已有头像 → 有移除按钮
      expect(find.byKey(const Key('edit_avatar_clear')), findsOneWidget);
      await tapKey(tester, 'edit_avatar_clear');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_save')));
      await tester.pumpAndSettle();

      expect(repo.get('card0001')!.raw['avatar'], '', reason: '移除后清空');
    });
  });
}
