// ============================================================
// sheets/sheet_music.dart — 音乐控制台（PRD P2-03：本机 BGM / P10 第 5 期 A）
//
// 旧版 `room-panels.js:4029-4051 musicSheet`：`<input type=file accept=audio/*>`
// + `new Audio(URL.createObjectURL(f))` + 三按钮「选择音频 / ▶播放 / ⏸暂停」，
// 明确「仅本机播放、不同步、不打包音频」。老 APP **没有场景插槽**。
//
// 本批按用户拍板落地：
//   · 解锁音频插件，真能在本机播放（端口封装，见 room_music_ports.dart）；
//   · 5 个场景插槽（日常 / 探索 / 悬疑 / 战斗 / 后日谈），配置落本机；
//   · 播放 / 暂停 / 停止 三个真按钮 + 如实状态文本；
//   · 场景快捷键：**先停旧曲，再播新曲**（编排在 MusicConsoleController）；
//   · KP 房间内快捷入口收进弹层（工具栏空间紧，见 room_game_page.dart）。
//
// ★ 纯本机边界一字未删：不打包音频、不联网、不同步给其他设备、不进房间
//   状态、不进存档、不发任何 intent。整个 widget 树只有说明文字与 RoomTap，
//   所有副作用都经 [MusicPort]（可注入），结构上就没有任何发包路径。
// ============================================================

import 'package:flutter/material.dart';

import '../room_music_controller.dart' show MusicConsoleController;
import '../room_music_ports.dart'
    show MusicPort, MusicScene, kMusicScenes;
import '../widgets/room_panel_kit.dart' show RoomTap;
import 'room_sheet.dart' show showRoomSheet;

/// 音乐控制台 / KP 快捷弹层的稳定 key。
///
/// 仍适用的旧 key（root / localOnly / statusLabel / status / howtoLabel /
/// howto / whyLabel / why）名字与值一字未改；本批新增的沿用同一命名风格。
class MusicSheetKeys {
  const MusicSheetKeys._();

  static const Key root = ValueKey<String>('music/root');
  static const Key localOnly = ValueKey<String>('music/localOnly');
  static const Key statusLabel = ValueKey<String>('music/statusLabel');
  static const Key status = ValueKey<String>('music/status');
  static const Key howtoLabel = ValueKey<String>('music/howtoLabel');
  static const Key howto = ValueKey<String>('music/howto');
  static const Key whyLabel = ValueKey<String>('music/whyLabel');
  static const Key why = ValueKey<String>('music/why');

  // ---- 本批新增 ----
  static const Key sceneQuickLabel = ValueKey<String>('music/sceneQuickLabel');
  static const Key sceneQuickRow = ValueKey<String>('music/sceneQuickRow');
  static Key scene(String id) => ValueKey<String>('music/scene/$id');

  static const Key notice = ValueKey<String>('music/notice');
  static const Key controls = ValueKey<String>('music/controls');
  static const Key play = ValueKey<String>('music/play');
  static const Key pause = ValueKey<String>('music/pause');
  static const Key stop = ValueKey<String>('music/stop');

  static const Key slotsLabel = ValueKey<String>('music/slotsLabel');
  static Key slot(String id) => ValueKey<String>('music/slot/$id');
  static Key slotName(String id) => ValueKey<String>('music/slotName/$id');
  static Key slotState(String id) => ValueKey<String>('music/slotState/$id');
  static Key pick(String id) => ValueKey<String>('music/pick/$id');

  /// 房间工具栏里 KP 专属的「BGM 场景」入口。
  static const Key roomSceneQuick = ValueKey<String>('music/roomSceneQuick');

  /// KP 房间内快捷弹层。
  static const Key quickRoot = ValueKey<String>('music/quickRoot');
  static const Key quickNotice = ValueKey<String>('music/quickNotice');
  static Key quickScene(String id) => ValueKey<String>('music/quickScene/$id');

  // ---- P20 需求 4②：快捷弹层自己的播放 / 暂停 / 停止三键 ----
  // 和音乐控制台的 `play` / `pause` / `stop` 是两个不同位置的入口，但背后
  // 是**同一份端口播放态**（见 room_music_ports.dart 的 D10 注释）。
  static const Key quickNow = ValueKey<String>('music/quickNow');
  static const Key quickStatus = ValueKey<String>('music/quickStatus');
  static const Key quickControls = ValueKey<String>('music/quickControls');
  static const Key quickPlay = ValueKey<String>('music/quickPlay');
  static const Key quickPause = ValueKey<String>('music/quickPause');
  static const Key quickStop = ValueKey<String>('music/quickStop');
}

/// 打开「音乐控制台」弹层。[port] 是测试注入点（生产为 null → 全局端口）。
Future<void> openMusicSheet(BuildContext context, {MusicPort? port}) =>
    showRoomSheet<void>(
      context: context,
      title: '音乐控制台 · 本机 BGM',
      body: (BuildContext _) => MusicSheet(port: port),
    );

/// 打开 KP 房间内的「BGM 场景快捷键」弹层。
///
/// 工具栏上只留一个入口按钮：5 个场景键收进弹层，避免把上批刚修好的
/// 自适应高度工具条挤爆（用户明确允许「放不下就调整布局」）。
Future<void> openMusicSceneQuickSheet(
  BuildContext context, {
  MusicPort? port,
}) =>
    showRoomSheet<void>(
      context: context,
      title: 'BGM 场景快捷键 · 仅 KP 本机',
      body: (BuildContext _) => MusicSceneQuickPanel(port: port),
    );

/// 音乐控制台主体：本机播放器 + 5 场景插槽 + 场景快捷键。
class MusicSheet extends StatefulWidget {
  const MusicSheet({super.key, this.port});

  final MusicPort? port;

  @override
  State<MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<MusicSheet> {
  late final MusicConsoleController _c;

  @override
  void initState() {
    super.initState();
    _c = MusicConsoleController(port: widget.port);
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (BuildContext ctx, Widget? _) => _body(ctx),
      );

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodySmall;
    final head = theme.textTheme.titleSmall;
    final dim = body?.copyWith(color: theme.colorScheme.secondary);

    return Column(
      key: MusicSheetKeys.root,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '本机 BGM：只在你这台设备上播放，不联网、不同步给房间里的其他设备、'
          '不进房间状态、不进存档，也不打包任何音频文件；曲目全部由你自备。',
          key: MusicSheetKeys.localOnly,
          style: body,
        ),
        const SizedBox(height: 10),
        Text(
          'KP 场景快捷键（点一下＝先停旧曲，再切到该场景的 BGM）',
          key: MusicSheetKeys.sceneQuickLabel,
          style: head,
        ),
        const SizedBox(height: 4),
        _sceneRow(),
        const SizedBox(height: 10),
        Text('当前状态', key: MusicSheetKeys.statusLabel, style: head),
        const SizedBox(height: 4),
        Text(_c.statusText, key: MusicSheetKeys.status, style: body),
        const SizedBox(height: 2),
        Text(_c.notice, key: MusicSheetKeys.notice, style: dim),
        const SizedBox(height: 6),
        Wrap(
          key: MusicSheetKeys.controls,
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            RoomTap(
              key: MusicSheetKeys.play,
              icon: Icons.play_arrow,
              // 暂停后这一键就是「续播」：底层从暂停处继续，不从头重放。
              label: _c.canResume ? '续播' : '播放',
              hint: _c.canResume
                  ? '从暂停处继续播放（不会从头重放）'
                  : '播放当前选中场景的音频（未选定 / 未配置会给真提示）',
              minSize: const Size(84, 36),
              onTap: _c.play,
            ),
            RoomTap(
              key: MusicSheetKeys.pause,
              icon: Icons.pause,
              label: '暂停',
              hint: '暂停当前播放',
              minSize: const Size(84, 36),
              onTap: _c.pause,
            ),
            RoomTap(
              key: MusicSheetKeys.stop,
              icon: Icons.stop,
              label: '停止',
              hint: '停止当前播放',
              minSize: const Size(84, 36),
              onTap: _c.stop,
            ),
          ],
        ),
        const Divider(height: 18),
        Text(
          '场景音频插槽（音频由你自备，配置只存本机）',
          key: MusicSheetKeys.slotsLabel,
          style: head,
        ),
        const SizedBox(height: 4),
        for (final MusicScene scene in kMusicScenes) _slotRow(context, scene),
        const Divider(height: 18),
        Text('怎么用 BGM', key: MusicSheetKeys.howtoLabel, style: head),
        const SizedBox(height: 4),
        Text(
          '① 在某个场景点「选文件」挑一个本机音频（会复制进应用私有目录）；\n'
          '② 点「播放」开始，或用上方场景快捷键一键切歌；\n'
          '③ 「暂停 / 停止」随时可用；暂停后再点播放是「续播」，从原位置继续，\n'
          '   不会从头重放；切场景会先停上一首，不会两首叠播。\n'
          '重启 App 后插槽配置仍在本机。音频由你自备，本应用不联网、不替你下载曲目。',
          key: MusicSheetKeys.howto,
          style: body,
        ),
        const SizedBox(height: 12),
        Text('边界说明', key: MusicSheetKeys.whyLabel, style: head),
        const SizedBox(height: 4),
        Text(
          '沿用旧版「选本机文件 + 只在本机播放、不打包音频、不联网」的口径；'
          '本批解锁了音频播放插件，才把真播放、暂停、停止与 5 个场景插槽补齐。'
          '所有动作都只作用在这台设备，不同步给房间里的其他人，也不写进存档。',
          key: MusicSheetKeys.why,
          style: dim,
        ),
      ],
    );
  }

  Widget _sceneRow() => Wrap(
        key: MusicSheetKeys.sceneQuickRow,
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          for (final MusicScene s in kMusicScenes)
            RoomTap(
              key: MusicSheetKeys.scene(s.id),
              label: s.label,
              hint: '切到${s.label}：先停旧曲再播该场景 BGM（未配置则只停不播）',
              minSize: const Size(64, 34),
              onTap: () => _c.switchScene(s.id),
            ),
        ],
      );

  Widget _slotRow(BuildContext context, MusicScene scene) {
    final theme = Theme.of(context);
    final slot = _c.slotOf(scene.id);
    final active = _c.activeSceneId == scene.id;
    final stateText = slot.configured
        ? '已配置 · ${slot.displayName}'
        : '未配置';
    return Padding(
      key: MusicSheetKeys.slot(scene.id),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          RoomTap(
            key: MusicSheetKeys.slotName(scene.id),
            label: scene.label,
            hint: '选中${scene.label}（只选中，不播放）',
            minSize: const Size(64, 34),
            onTap: () => _c.selectScene(scene.id),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              // P12：原来的「★ 」前缀是 emoji 观感，去掉后「正在播放」由
              // 下面这一行文字的颜色（primary）表达，信息量不减。
              stateText,
              key: MusicSheetKeys.slotState(scene.id),
              style: theme.textTheme.bodySmall?.copyWith(
                color: active ? theme.colorScheme.primary : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          RoomTap(
            key: MusicSheetKeys.pick(scene.id),
            icon: Icons.attach_file,
            label: '选文件',
            hint: '为${scene.label}选一个本机音频文件（只存本机）',
            minSize: const Size(76, 34),
            onTap: () => _c.pickFor(scene.id),
          ),
        ],
      ),
    );
  }
}

/// KP 房间内快捷弹层：5 个场景键 + 播放 / 暂停 / 停止 + 如实状态。
///
/// 与音乐控制台各自建控制器，但共用同一个全局 [MusicPort]（同一播放器）与
/// 同一份端口播放态：控制台在播（或已暂停）时打开本弹层，这里显示的就是
/// 那个真实的播放态，点「暂停 / 停止 / 续播」直接作用在同一个播放器上。
/// 两个弹层不会同时打开，故不存在两个控制器抢着改同一个播放器的问题。
class MusicSceneQuickPanel extends StatefulWidget {
  const MusicSceneQuickPanel({super.key, this.port});

  final MusicPort? port;

  @override
  State<MusicSceneQuickPanel> createState() => _MusicSceneQuickPanelState();
}

class _MusicSceneQuickPanelState extends State<MusicSceneQuickPanel> {
  late final MusicConsoleController _c;

  @override
  void initState() {
    super.initState();
    _c = MusicConsoleController(port: widget.port);
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (BuildContext ctx, Widget? _) {
          final theme = Theme.of(ctx);
          return Column(
            key: MusicSheetKeys.quickRoot,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '工具栏空间紧，KP 的 5 个场景快捷键收进这个弹层：点一下先停'
                '旧曲再切到该场景的 BGM。只在这台设备播放，不同步、不进存档。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final MusicScene s in kMusicScenes)
                    RoomTap(
                      key: MusicSheetKeys.quickScene(s.id),
                      label: s.label,
                      hint: '切到${s.label}：先停旧曲再播该场景 BGM',
                      minSize: const Size(64, 36),
                      onTap: () => _c.switchScene(s.id),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // ★ 需求 4②：播放 / 暂停 / 停止 就在这个弹层里，不再需要
              //   「请去音乐控制台」—— 那正是用户说的「缺控制按钮」。
              Wrap(
                key: MusicSheetKeys.quickControls,
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  RoomTap(
                    key: MusicSheetKeys.quickPlay,
                    icon: Icons.play_arrow,
                    label: _c.canResume ? '续播' : '播放',
                    hint: _c.canResume
                        ? '从暂停处继续播放（不会从头重放）'
                        : '播放当前场景的 BGM（先点场景键切歌）',
                    enabled: _c.canPlay,
                    minSize: const Size(84, 36),
                    onTap: _c.play,
                  ),
                  RoomTap(
                    key: MusicSheetKeys.quickPause,
                    icon: Icons.pause,
                    label: '暂停',
                    hint: '暂停当前播放（再点「续播」从原位置继续）',
                    enabled: _c.canPause,
                    minSize: const Size(84, 36),
                    onTap: _c.pause,
                  ),
                  RoomTap(
                    key: MusicSheetKeys.quickStop,
                    icon: Icons.stop,
                    label: '停止',
                    hint: '停止播放并清空播放位置',
                    enabled: _c.canStop,
                    minSize: const Size(84, 36),
                    onTap: _c.stop,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '当前：${_c.currentTitle}',
                key: MusicSheetKeys.quickNow,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                _c.statusText,
                key: MusicSheetKeys.quickStatus,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                _c.notice,
                key: MusicSheetKeys.quickNotice,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.secondary),
              ),
              const SizedBox(height: 6),
              Text(
                '播放 / 暂停 / 停止与音乐控制台共用同一个播放器：这里暂停，'
                '控制台那边也是「已暂停」；配置每个场景的音频请到「音乐控制台」。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      );
}
