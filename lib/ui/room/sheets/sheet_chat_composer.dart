// ============================================================
// sheets/sheet_chat_composer.dart — 「编辑发言」全屏编辑器（P10 第 7 期 C 批 A）
//
// 用户原话：「点击文字输入框（焦点在输入框），输入框变为全屏，好让玩家可以
// 方便检查自己写了什么」。聊天输入行是单行 TextField，长发言写起来/回看都
// 很难受，所以点输入框（或旁边的「全屏」按钮）推一个整页的多行编辑器。
//
// ★ 与房间作用域解耦：本页**不**读 RoomScope。弹层/新路由是页面路由的兄弟，
//   RoomScope 在页面路由内部，直接读会命中断言。草稿同步与发包全由调用方
//   （ChatInputRow）以回调传入，本页只负责「编辑一段文本 + 返回给用户」。
// ★ 关闭语义：
//   · 「完成」/ 关闭按钮 → pop 回当前草稿文本（调用方写回原输入框）；
//   · 「发送」           → 先回调 onSend（复用原 _send 语义），再 pop null；
//   · 系统返回键        → pop null，调用方从 RoomUiLocal.chatDraft 回填
//                          （onChanged 已逐字同步，绝不丢草稿）。
// ★ 草稿不进事件流、不进存档：只经 RoomUiLocal.setChatDraft（纯本地态）。
// ============================================================

import 'package:flutter/material.dart';

import '../widgets/room_panel_kit.dart' show RoomTap;

/// 全屏编辑器内部稳定 key。
///
/// 常量字面量以 `gpFeeds/` 打头，保证与 [GpFeedsKeys] 里既有 key 同一命名空间，
/// 也让 `GpFeedsKeys.chatComposer*` 可以直接别名到此处而不产生循环 import。
class ChatComposerKeys {
  const ChatComposerKeys._();

  /// 整页根（Scaffold）。
  static const Key root = ValueKey<String>('gpFeeds/chatComposer');

  /// 多行输入框。
  static const Key field = ValueKey<String>('gpFeeds/chatComposerField');

  /// 「完成」按钮（写回草稿、不发送）。
  static const Key done = ValueKey<String>('gpFeeds/chatComposerDone');

  /// 「发送」按钮（立即发言）。
  static const Key send = ValueKey<String>('gpFeeds/chatComposerSend');

  /// AppBar 关闭按钮（与「完成」同义：保留草稿）。
  static const Key close = ValueKey<String>('gpFeeds/chatComposerClose');
}

/// 推一个全屏「编辑发言」页。
///
/// 返回 [String?]：非 null = 用户点「完成」/关闭时的草稿文本；null = 已经发送
/// 或系统返回（调用方需自行用 `RoomUiLocal.chatDraft` 对齐输入框）。
///
/// [onChanged] 每次输入都回调，调用方负责写 `setChatDraft`；
/// [onSend] 只在点「发送」时回调一次，调用方负责复用原有发送语义。
Future<String?> showChatComposer({
  required BuildContext context,
  required String initialText,
  required ValueChanged<String> onChanged,
  required ValueChanged<String> onSend,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (BuildContext _) => ChatComposerPage(
        initialText: initialText,
        onChanged: onChanged,
        onSend: onSend,
      ),
    ),
  );
}

/// 全屏编辑页本体。
///
/// [expands: true] + [maxLines: null] 让输入框吃掉 AppBar 与底栏之外的全部高度，
/// 长文本可以整段滚动查看；`autofocus` 保证打开即能继续打字。
class ChatComposerPage extends StatefulWidget {
  const ChatComposerPage({
    super.key,
    required this.initialText,
    required this.onChanged,
    required this.onSend,
  });

  /// 打开时的当前草稿。
  final String initialText;

  /// 逐字同步草稿到 `RoomUiLocal.chatDraft`。
  final ValueChanged<String> onChanged;

  /// 点「发送」：复用输入行原有的发送语义（trim / 空丢弃 / 清草稿 / 发 intent）。
  final ValueChanged<String> onSend;

  @override
  State<ChatComposerPage> createState() => _ChatComposerPageState();
}

class _ChatComposerPageState extends State<ChatComposerPage> {
  late final TextEditingController _draft;

  /// 防重复 pop：完成 / 发送 / 关闭三个入口只认第一次。
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(text: widget.initialText);
    _draft.selection =
        TextSelection.collapsed(offset: widget.initialText.length);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  /// 「完成」/ 关闭：把整段草稿交回调用方，由调用方写回原输入框。
  void _finish() {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop<String>(_draft.text);
  }

  /// 「发送」：先复用原语义发包，再以 null 结果关闭（调用方不再回填）。
  ///
  /// ★ P17 KP-5（用户：点发送没有任何反应、文字还在）：
  ///   `widget.onSend` **可能抛**（改前的闭包会写底层 `ChatInputRow` 的
  ///   `_text`，全屏打开期间那个 State 若被重建销毁，赋值即
  ///   used-after-dispose）。改前是「先回调、再 `Navigator.pop`」，回调一抛
  ///   异常，`pop` 就被整行跳过 → 弹层不关、文字还在、包也没发出去。
  ///   所以 `pop` 放进 `finally`：**不依赖具体抛点**的无条件兜底 ——
  ///   debug 有 assert、release 包 assert 被裁后抛点可能换地方，兜底不能
  ///   靠猜某个具体异常。
  ///   异常本身**不静默吞**：照常上报（测试里 `tester.takeException()` 可见）。
  void _send() {
    if (_closed) return;
    _closed = true;
    try {
      widget.onSend(_draft.text);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'dice_realm/room',
        context: ErrorDescription('全屏编辑发言：发送回调抛异常'),
      ));
    } finally {
      Navigator.of(context).pop<String>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // ★ P17 KP-5 / B2-2（真机层）：软键盘弹起时「发送」必须还在命中区。
    //   改前 `Scaffold` 没显式设 `resizeToAvoidBottomInset`、底部 Row 直接躺在
    //   不可滚动的 Column 里 —— 横屏手机 + 高键盘会把 body 压到只剩几十 dp，
    //   固定高度的按钮行被挤出可视区（用户「点了没反应」的真机成因之一）。
    //   三处加固（都不改任何 key、不改按钮文字与尺寸）：
    //   · 显式 `resizeToAvoidBottomInset: true`：键盘弹起时压缩 body，而不是
    //     把底部盖住；
    //   · 编辑区高度**按可用高算**（可用高 - 上下 padding - 间距 - 按钮行），
    //     极小档兜底 96dp，整页由 `SingleChildScrollView` 兜住 —— 按钮行滚
    //     一下一定够得着，绝不会半截落在键盘命中区里；
    //   · 按钮行自己吃底部安全区（`SafeArea(bottom: true)`）：滚动内容可以
    //     贴到手势条，按钮不会被盖。
    return Scaffold(
      key: ChatComposerKeys.root,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('编辑发言'),
        leading: IconButton(
          key: ChatComposerKeys.close,
          icon: const Icon(Icons.close),
          tooltip: '关闭并保留草稿',
          onPressed: _finish,
        ),
      ),
      // ★ P12 KP-3：body 外层的 GestureDetector 兜底 —— 点编辑区以外
      //   （含 AppBar 下方空白）也收起软键盘，与 TextField.onTapOutside
      //   构成双保险（多位置 tap / 连续 tap 不复焦）。`deferToChild`
      //   让子控件优先命中，绝不抢任何按钮 / 输入框点击。
      //   ⚠️ Scaffold 自身（含 :168 `resizeToAvoidBottomInset:true`）与
      //   `room_game_page.dart:428` 的 `false` 两个独立 Scaffold 逐字不动。
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
        // 底部安全区交给下面那层 SafeArea（按钮行）自己吃。
        bottom: false,
        child: LayoutBuilder(
          builder: (BuildContext ctx, BoxConstraints c) {
            const double pad = 12;
            const double gap = 10;
            const double barHeight = 44;
            final double fieldHeight = (c.maxHeight - pad * 2 - gap - barHeight)
                .clamp(96.0, double.infinity);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: fieldHeight,
                    child: TextField(
                      key: ChatComposerKeys.field,
                      controller: _draft,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        hintText: '在这里写你要说的话，写多长都能看全…',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: widget.onChanged,
                      // ★ P12 KP-3：点输入框以外立刻失焦（viewInsets.bottom
                      //   归零），不弹模态、不改草稿、不动 autofocus 语义。
                      onTapOutside: (_) => FocusScope.of(ctx).unfocus(),
                    ),
                  ),
                  const SizedBox(height: gap),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        RoomTap(
                          key: ChatComposerKeys.done,
                          label: '完成',
                          icon: Icons.check,
                          hint: '写回聊天输入框，稍后再自己点发送',
                          minSize: const Size(96, 44),
                          onTap: _finish,
                        ),
                        const SizedBox(width: 8),
                        RoomTap(
                          key: ChatComposerKeys.send,
                          label: '发送',
                          icon: Icons.send,
                          hint: '立刻发出这段发言',
                          minSize: const Size(96, 44),
                          onTap: _send,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}
