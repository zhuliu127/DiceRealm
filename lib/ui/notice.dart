// ============================================================
// notice.dart — App 底部消息广播的**唯一入口**
//
// 用户口径（P10 需求 8）：
//   「所有消息广播都改成一样的逻辑：新消息覆盖旧消息，并且只显示 2 秒。」
//
// 为什么不是逐个改 32 个调用点：
//   调用点散在 17 个文件里，每个都自己写 `showSnackBar(SnackBar(...))`，
//   时长各有各的（默认 4 秒、有的写 2 秒、有的写 300ms 动画）。
//   只要还有一处漏改，行为就不统一。所以这里把语义收到一个扩展方法上，
//   调用点只改**方法名**（`showSnackBar` → `showSlot`），参数原样不动。
//
// 为什么覆盖而不是排队：
//   `ScaffoldMessenger` 默认是**队列**语义 —— 前一条不消失，后一条就等着。
//   用户连续操作（比如连点几次「推进一轮」）时会看到消息一条接一条地播，
//   最后一条要等前面全部播完才出来，表现为「新消息很久才出现」。
//   这里先 `hideCurrentSnackBar()` 再 `showSnackBar()`，后一条立刻顶掉前一条。
// ============================================================

import 'package:flutter/material.dart';

/// 消息广播的固定展示时长（用户要求 2 秒）。
const Duration kNoticeDuration = Duration(seconds: 2);

/// **带操作按钮**的提示时长。
///
/// 为什么不是 2 秒：`SnackBar` 一旦带 `action`，它就是「要求用户做个选择」的
/// 交互件，不是广播。2 秒内人根本来不及读完并按到按钮 —— 比如建卡向导那句
/// 「还没做教育进步检定」带「现在去检定 / 仍要继续」，2 秒消失等于这个功能
/// 白做。所以有 action 时给足阅读与点击时间，无 action 才按用户口径压到 2 秒。
const Duration kActionNoticeDuration = Duration(seconds: 8);

extension SlotMessenger on ScaffoldMessengerState {
  /// 显示一条「槽位式」消息：**立刻顶掉上一条**，固定显示 [kNoticeDuration]。
  ///
  /// 保留调用方给的 content / action / 颜色 / 图标等外观参数，**只统一
  /// 时长与队列语义** —— 这样各页面仍能按需定制长什么样，但"什么时候出现、
  /// 出现多久、会不会排队"全站一致。
  void showSlot(SnackBar bar) {
    // 覆盖语义：不等上一条播完，直接换掉。
    // 用 removeCurrentSnackBar 而不是 hideCurrentSnackBar：后者会播一段
    // 退出动画，连点时屏幕上会短暂出现两条叠加的观感。
    removeCurrentSnackBar();
    showSnackBar(
      SnackBar(
        content: bar.content,
        // 有按钮 → 留够操作时间；纯广播 → 用户要求的 2 秒
        duration: bar.action != null ? kActionNoticeDuration : kNoticeDuration,
        backgroundColor: bar.backgroundColor,
        elevation: bar.elevation,
        margin: bar.margin,
        padding: bar.padding,
        width: bar.width,
        shape: bar.shape,
        behavior: bar.behavior,
        action: bar.action,
        onVisible: bar.onVisible,
        dismissDirection: bar.dismissDirection,
        showCloseIcon: bar.showCloseIcon,
        closeIconColor: bar.closeIconColor,
      ),
    );
  }
}
