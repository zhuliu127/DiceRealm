// ============================================================
// ui/room/resume_mode_dialog.dart — P20 续玩弹窗（N3，唯一新增弹窗文件）
//
// ★ 三个弹窗：
//   · [showResumeModeDialog]  「选择续玩方式」3 选项 + 取消；
//   · [showResumeFailedDialog]「连回失败」重试 / 仅本机离线副本 / 取消；
//   · [showCloudNewerDialog]  云端 seq > 本机 seq 时 KP 显式确认覆盖（K4）。
//
// ★ 硬约束（主理人裁决 + 设计 §4.4）：
//   · 独立 [ResumeDialogKeys] 命名空间（`resumeMode/*`），**绝不碰**
//     `RoomEntryKeys.*`；
//   · 弹窗**只回显房号 code**，绝不回显 hostToken / mtoken / deviceId /
//     房间密码 / 服务器地址；零 print / 日志；
//   · 固定尺寸控件（Radio / Icon / SizedBox / 按钮行）用
//     [MediaQuery.withClampedTextScaling] 以 `maxScaleFactor: 1.0` **只包该
//     控件子树**；弹窗主体用 `SingleChildScrollView` + Column(min) 承接
//     1.3 / 1.5 / 2.0 的高度增长；
//   · **禁 `ClipRect` 硬裁、禁页面级钳制**（对齐 clampBtnText 口径）。
// ============================================================

import 'package:flutter/material.dart';

/// 续玩方式。
enum ResumeMode { lan, cloud, offline }

/// 「连回失败」的三个动作。
enum ResumeFailAction { retry, offline, cancel }

/// 模式选择结果（[cancelled] = 用户取消 / 返回键，零副作用）。
class ResumeChoice {
  const ResumeChoice({required this.mode, this.cancelled = false});

  final ResumeMode mode;
  final bool cancelled;

  /// 取消的便捷构造。
  static const ResumeChoice cancelledChoice =
      ResumeChoice(mode: ResumeMode.offline, cancelled: true);
}

/// ★ 独立 key 命名空间：`resumeMode/*`，与 RoomEntryKeys 完全隔离。
class ResumeDialogKeys {
  const ResumeDialogKeys._();

  static const Key root = ValueKey<String>('resumeMode/root');
  static const Key title = ValueKey<String>('resumeMode/title');
  static const Key subtitle = ValueKey<String>('resumeMode/subtitle');
  static const Key lan = ValueKey<String>('resumeMode/lan');
  static const Key cloud = ValueKey<String>('resumeMode/cloud');
  static const Key offline = ValueKey<String>('resumeMode/offline');
  static const Key confirm = ValueKey<String>('resumeMode/confirm');
  static const Key cancel = ValueKey<String>('resumeMode/cancel');
  static const Key failRoot = ValueKey<String>('resumeMode/failRoot');
  static const Key failReason = ValueKey<String>('resumeMode/failReason');
  static const Key retry = ValueKey<String>('resumeMode/retry');
  static const Key failOffline = ValueKey<String>('resumeMode/failOffline');
  static const Key failCancel = ValueKey<String>('resumeMode/failCancel');
  static const Key newerRoot = ValueKey<String>('resumeMode/newerRoot');
  static const Key newerConfirm = ValueKey<String>('resumeMode/newerConfirm');
  static const Key newerKeep = ValueKey<String>('resumeMode/newerKeep');
}

/// 只钳固定尺寸控件子树（Radio / Icon / 定高 SizedBox），不影响正文。
/// maxScaleFactor 1.0：与 `clampBtnText`（room_button_size.dart:150）同口径。
Widget _clampFixed(Widget child) =>
    MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: child,
    );

/// 「选择续玩方式」三选项弹窗。
///
/// 返回 [ResumeChoice]；取消 / 点遮罩 / 返回键返回 `cancelled: true`。
/// [code] 只用于回显房号，绝不回显任何令牌或地址。
Future<ResumeChoice> showResumeModeDialog(
  BuildContext context, {
  required String code,
  required ResumeMode defaultMode,
}) async {
  ResumeMode selected = defaultMode;
  final ResumeChoice? result = await showDialog<ResumeChoice>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setState) {
          return AlertDialog(
            key: ResumeDialogKeys.root,
            title: const Text('选择续玩方式', key: ResumeDialogKeys.title),
            // SingleChildScrollView + Column(min)：正文随 textScaler 增长，
            // 不做页面级钳制、不用 ClipRect 硬裁。
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '这条存档来自房间 $code。可以连回原房间（身份不变），'
                    '也可以只看本机存档。',
                    key: ResumeDialogKeys.subtitle,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _modeTile(
                    dialogContext,
                    key: ResumeDialogKeys.lan,
                    value: ResumeMode.lan,
                    groupValue: selected,
                    title: '局域网重连',
                    subtitle: '需 KP 与你在同一 WiFi，且 KP 已打开原房间',
                    onChanged: (ResumeMode? v) {
                      if (v != null) setState(() => selected = v);
                    },
                  ),
                  _modeTile(
                    dialogContext,
                    key: ResumeDialogKeys.cloud,
                    value: ResumeMode.cloud,
                    groupValue: selected,
                    title: '公网重连',
                    subtitle: '通过服务器连回，可在云端同步进度',
                    onChanged: (ResumeMode? v) {
                      if (v != null) setState(() => selected = v);
                    },
                  ),
                  _modeTile(
                    dialogContext,
                    key: ResumeDialogKeys.offline,
                    value: ResumeMode.offline,
                    groupValue: selected,
                    title: '仅本机离线副本',
                    subtitle: '不联网，进度不会与同伴同步（原行为）',
                    onChanged: (ResumeMode? v) {
                      if (v != null) setState(() => selected = v);
                    },
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              _clampFixed(
                TextButton(
                  key: ResumeDialogKeys.cancel,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(ResumeChoice.cancelledChoice),
                  child: const Text('取消'),
                ),
              ),
              _clampFixed(
                FilledButton(
                  key: ResumeDialogKeys.confirm,
                  onPressed: () => Navigator.of(dialogContext).pop(
                    ResumeChoice(mode: selected),
                  ),
                  child: const Text('确定'),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  return result ?? ResumeChoice.cancelledChoice;
}

/// 单个选项行：固定尺寸的选中指示器（Icon）单独钳制，主/副文案正常跟随
/// 系统字号。用 Icon 而非 Radio：既避免新版 SDK 的 `groupValue/onChanged`
/// 废弃告警，也让 1.3/1.5/2.0 档下指示器尺寸恒定、不撑破行高。
Widget _modeTile(
  BuildContext context, {
  required Key key,
  required ResumeMode value,
  required ResumeMode groupValue,
  required String title,
  required String subtitle,
  required ValueChanged<ResumeMode?> onChanged,
}) {
  final bool selected = value == groupValue;
  return InkWell(
    key: key,
    onTap: () => onChanged(value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _clampFixed(
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 「连回失败」弹窗：原因 + 重试 / 仅本机离线副本 / 取消。
///
/// [reason] 是 `CloudBackupService.resumeErrorText` 产出的中文口径；
/// 绝不出现「已连回 / 已同步」字样（R-09）。
Future<ResumeFailAction> showResumeFailedDialog(
  BuildContext context, {
  required String code,
  required String reason,
}) async {
  final ResumeFailAction? result = await showDialog<ResumeFailAction>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext ctx) {
      return AlertDialog(
        key: ResumeDialogKeys.failRoot,
        title: Text('没能连回房间 $code'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(reason, key: ResumeDialogKeys.failReason),
            ],
          ),
        ),
        actions: <Widget>[
          _clampFixed(
            TextButton(
              key: ResumeDialogKeys.failCancel,
              onPressed: () =>
                  Navigator.of(ctx).pop(ResumeFailAction.cancel),
              child: const Text('取消'),
            ),
          ),
          _clampFixed(
            TextButton(
              key: ResumeDialogKeys.failOffline,
              onPressed: () =>
                  Navigator.of(ctx).pop(ResumeFailAction.offline),
              child: const Text('仅本机离线副本'),
            ),
          ),
          _clampFixed(
            FilledButton(
              key: ResumeDialogKeys.retry,
              onPressed: () =>
                  Navigator.of(ctx).pop(ResumeFailAction.retry),
              child: const Text('重试'),
            ),
          ),
        ],
      );
    },
  );
  return result ?? ResumeFailAction.cancel;
}

/// K4：云端 seq > 本机 seq，必须 KP **显式确认**才 adoptSave。
/// 返回 false（含取消）时不覆盖、不伪造成功、不偷偷抬 seq。
Future<bool> showCloudNewerDialog(
  BuildContext context, {
  required int cloudSeq,
  required int localSeq,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext ctx) {
      return AlertDialog(
        key: ResumeDialogKeys.newerRoot,
        title: const Text('云端有更新的进度'),
        content: SingleChildScrollView(
          child: Text(
            '云端是第 $cloudSeq 版，本机是第 $localSeq 版。'
            '用云端存档覆盖本机？未确认前不会覆盖本机进度。',
          ),
        ),
        actions: <Widget>[
          _clampFixed(
            TextButton(
              key: ResumeDialogKeys.newerKeep,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('保留本机'),
            ),
          ),
          _clampFixed(
            FilledButton(
              key: ResumeDialogKeys.newerConfirm,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('用云端覆盖'),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
