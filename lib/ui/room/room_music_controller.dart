// ============================================================
// room_music_controller.dart — 音乐控制台的纯逻辑控制器（P10 第 5 期 / A）
//
// 把「插槽配置 + 播放态 + 切场景编排」从 widget 里剥出来，好处有三：
//   1) 行为级用例可以脱离 widget，直接拿 Fake 端口断言调用序列；
//   2) 音乐控制台弹层与 KP 房间内快捷弹层各自建一个控制器，但共用同一个
//      全局 [musicPort]（同一个播放器实例），「先停旧再播新」始终成立；
//   3) 只有一份全局可变状态（端口），不引入多份状态互相竞争。
//
// ★ 切场景的硬约束（用户点名）：KP 点场景快捷键 → **先 stop 当前播放，
//   再切到新插槽播放**；旧音频不能与新音频叠播。空插槽 = 停旧的、不播新的。
//   这两步在 [switchScene] 里是**同步顺序调用**，Fake 端口能逐条记录。
// ★ 纯本机：整个文件零发包、零网络、零房间状态、零存档、零新增事件。
//
// ★★ 2.42.0 / P20 需求 4②（裁定 D10）：**播放态跨弹层共享**。
//   以前每个弹层各建控制器、各自 `_state = idle` 起步，于是「控制台在播 →
//   打开快捷弹层 → 点暂停」只提示「当前没有正在播放的 BGM」而音乐照放。
//   现在真源在端口：控制器构造时从 [MusicPort.playState] 对齐快照、并订阅
//   [MusicPort.stateStream] 跟随后续变化；`play()` 在「同一首且已暂停」时
//   走 [MusicPort.resume]（从暂停处继续），不再 stop+play 从头重放。
// ============================================================

import 'dart:async' show StreamSubscription;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'room_music_ports.dart'
    show
        MusicPlayState,
        MusicPort,
        MusicScene,
        MusicSlot,
        kMusicScenes,
        musicPort;

// ★ 兼容旧引用点：`MusicPlayState` 已上移到端口层（真源只能有一个），
//   但仍从本文件 re-export，既有 `import ... room_music_controller.dart
//   show MusicConsoleController, MusicPlayState;` 一字不改也能编译。
export 'room_music_ports.dart' show MusicPlayState;

/// 音乐控制台状态机。
///
/// [state] 是端口真源的投影：构造时同步对齐一次，之后靠端口流跟随。因此
/// 「音乐控制台在播 → 关掉 → 打开 BGM 场景快捷弹层」两个弹层看到的是同一
/// 个播放态，暂停 / 停止 / 续播都作用在那个唯一的全局播放器上。
class MusicConsoleController extends ChangeNotifier {
  MusicConsoleController({MusicPort? port, bool sharePortState = true})
      : _port = port ?? musicPort {
    // ★ 第一帧就与「实际在播什么」一致：不等流、不等 init()。
    _syncFromPort();
    if (sharePortState) _bindPortState();
  }

  final MusicPort _port;

  StreamSubscription<MusicPlayState>? _stateSub;

  final Map<String, MusicSlot> _slots = <String, MusicSlot>{};
  MusicPlayState _state = MusicPlayState.idle;
  String? _activeSceneId;
  bool _loaded = false;
  bool _disposed = false;
  String _notice =
      '先给场景绑定本机音频，再点「播放」；点场景快捷键会先停旧曲再切歌。';

  static final Set<String> _ids = <String>{
    for (final MusicScene s in kMusicScenes) s.id,
  };

  /// 场景 id → 槽位（只读快照）。
  Map<String, MusicSlot> get slots =>
      Map<String, MusicSlot>.unmodifiable(_slots);

  /// 播放态（端口真源的投影）。
  MusicPlayState get state => _state;

  String? get activeSceneId => _activeSceneId;
  String get notice => _notice;
  bool get loaded => _loaded;

  /// 端口此刻在放的音频相对路径（null = 什么都没放）。
  String? get playingRelPath => _port.playingRelPath;

  // ---- 按钮可用性（快捷弹层的三个控制键据此置灰，绝不摆假按钮） ----

  /// 「暂停」只在真的在播时可点。
  bool get canPause => _state == MusicPlayState.playing;

  /// 「停止」在播 / 暂停待续播时可点（停止后位置清空，没必要再点一次）。
  bool get canStop =>
      _state == MusicPlayState.playing || _state == MusicPlayState.paused;

  /// 「播放」在两种情形下可点：① 已暂停 → 从暂停处续播；② 已有选中且该
  /// 场景配置了音频 → 从头播。其余情形置灰（提示走 hint，不造假成功）。
  bool get canResume =>
      _state == MusicPlayState.paused &&
      _port.playingRelPath != null &&
      _port.playingRelPath!.isNotEmpty;

  bool get canPlay {
    if (canResume) return true;
    if (_state == MusicPlayState.playing) return false;
    final id = _activeSceneId;
    if (id == null) return false;
    return slotOf(id).configured;
  }

  /// 该场景的槽位；未配置返回 [MusicSlot.empty]（绝不返回 null）。
  MusicSlot slotOf(String sceneId) => _slots[sceneId] ?? MusicSlot.empty;

  /// 场景 id 的显示名；未知 / 未选定给中性文案。
  static String sceneLabel(String? id) {
    if (id == null || id.isEmpty) return '未选定';
    for (final MusicScene s in kMusicScenes) {
      if (s.id == id) return s.label;
    }
    return id;
  }

  /// 路径尾段（槽位丢失时仍能显示「在放哪个文件」，不显示假场景名）。
  static String _fileNameOf(String relPath) {
    final parts = relPath.split('/');
    return parts.isEmpty ? relPath : parts.last;
  }

  /// 是否处于「有音频在走」的状态（在播 / 已暂停待续播）。
  bool get _inTransport =>
      _state == MusicPlayState.playing || _state == MusicPlayState.paused;

  /// 该显示哪个场景：在播 / 暂停时以**端口在放的文件**为准（选中态可能已被
  /// 用户改成别的场景，显示选中会让「播放中 · 某场景」撒谎）。
  String? get _displaySceneId {
    final playingId = _sceneOfPath(_port.playingRelPath);
    if (_inTransport && playingId != null) return playingId;
    return _activeSceneId;
  }

  /// 「当前曲目 / 场景」一行文本（快捷弹层顶部显示用）。
  String get currentTitle {
    final id = _displaySceneId;
    if (id != null) {
      final slot = slotOf(id);
      return slot.configured
          ? '${sceneLabel(id)} · ${slot.displayName}'
          : '${sceneLabel(id)} · 未配置音频';
    }
    final path = _port.playingRelPath;
    if (path != null && path.isNotEmpty) return _fileNameOf(path);
    return '尚未选定场景';
  }

  /// 如实状态文本：播放态 + 当前场景 + 文件名。
  String get statusText {
    final prefix = switch (_state) {
      MusicPlayState.idle => '未播放',
      MusicPlayState.playing => '播放中',
      MusicPlayState.paused => '已暂停',
      MusicPlayState.stopped => '已停止',
    };
    final id = _displaySceneId;
    if (id != null) {
      final slot = slotOf(id);
      final file = slot.configured ? slot.displayName : '未配置音频';
      return '$prefix · ${sceneLabel(id)} · $file';
    }
    // 槽位还没加载完 / 文件不是任何插槽绑的：仍如实说出在放哪个文件，
    // 而不是假装「尚未选定场景」。
    final path = _port.playingRelPath;
    if (path != null && path.isNotEmpty && _inTransport) {
      return '$prefix · ${_fileNameOf(path)}';
    }
    return '$prefix · 尚未选定场景';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 从端口快照对齐播放态 / 在播场景（构造与 init 完成后各调一次）。
  void _syncFromPort() {
    _state = _port.playState;
    _adoptPortScene();
  }

  /// 端口在放某个文件时，把它反查回场景 id —— 跨弹层的「当前场景」由此
  /// 恢复，不需要第二份全局场景状态。
  void _adoptPortScene() {
    final id = _sceneOfPath(_port.playingRelPath);
    if (id != null) _activeSceneId = id;
  }

  /// 播放路径 → 场景 id（未匹配返回 null）。
  String? _sceneOfPath(String? relPath) {
    if (relPath == null || relPath.isEmpty) return null;
    for (final MapEntry<String, MusicSlot> e in _slots.entries) {
      if (e.value.relPath == relPath) return e.key;
    }
    return null;
  }

  /// 订阅端口播放态：别的弹层（或平台侧）改了播放状态，本控制器跟着刷新。
  void _bindPortState() {
    try {
      _stateSub = _port.stateStream.listen(
        _onPortState,
        onError: (Object _) {
          // 端口流报错不影响本控制器的意图状态。
        },
      );
    } catch (_) {
      // 替身 / 已关闭的流：拿不到推送也不影响本地意图状态。
      _stateSub = null;
    }
  }

  void _onPortState(MusicPlayState next) {
    if (_disposed || next == _state) return;
    _state = next;
    if (next == MusicPlayState.playing) _adoptPortScene();
    _notify();
  }

  /// 读本机持久化配置。不 await：初始态同步可用，完成后再刷新一次。
  ///
  /// 生产端口对任何异常都返回空 Map，Fake 端口返回立即完成的 Future，
  /// 因此 widget 测试（fake-async 区域）既不会挂死也不会留下未处理异常。
  void init() {
    _port.loadSlots().then(
      (Map<String, MusicSlot> loaded) {
        if (_disposed) return;
        _slots
          ..clear()
          ..addAll(loaded);
        _loaded = true;
        // 槽位到齐后才有 relPath → 场景 id 的映射，这里补一次对齐。
        _adoptPortScene();
        _notify();
      },
      onError: (Object _) {
        if (_disposed) return;
        _loaded = true;
        _notice = '读取本机配置失败，已按「未配置」显示。';
        _notify();
      },
    );
  }

  /// 选中场景（只改选中态，不播放）。播放按钮据此知道要播哪一槽。
  void selectScene(String sceneId) {
    if (!_ids.contains(sceneId)) return;
    _activeSceneId = sceneId;
    final slot = slotOf(sceneId);
    _notice = slot.configured
        ? '已选中${sceneLabel(sceneId)}（${slot.displayName}）；点「播放」开始。'
        : '已选中${sceneLabel(sceneId)}，但该场景还没绑定音频：先点「选文件」。';
    _notify();
  }

  /// 选文件并绑定到插槽。取消 / 失败 / 超限都给**真提示**，绝不造假状态。
  void pickFor(String sceneId) {
    if (!_ids.contains(sceneId)) return;
    _notice = '正在为${sceneLabel(sceneId)}选择本机音频…';
    _notify();
    _port.importAudio(sceneId).then(
      (MusicSlot? slot) {
        if (_disposed) return;
        if (slot == null) {
          _notice = '没有选到音频（已取消 / 读取失败 / 超过上限），插槽保持原样。';
          _notify();
          return;
        }
        _slots[sceneId] = slot;
        _activeSceneId = sceneId;
        _port.saveSlots(<String, MusicSlot>{..._slots});
        _notice =
            '已绑定${sceneLabel(sceneId)}：${slot.displayName}（已保存到本机）。';
        _notify();
      },
      onError: (Object _) {
        if (_disposed) return;
        _notice = '读取音频失败，插槽保持原样。';
        _notify();
      },
    );
  }

  /// 播放当前选中场景。没选中 / 没配置 → 真提示，不许点了没反应。
  ///
  /// ★ 续播分支：当前是「同一首且已暂停」时调 [MusicPort.resume]（从暂停处
  ///   继续）；否则按原逻辑 [MusicPort.play]（内部 stop + 装载源 = 从头播）。
  void play() {
    final id = _activeSceneId;
    if (id == null) {
      _notice = '请先点一个场景（或先给场景绑定音频），再点「播放」。';
      _notify();
      return;
    }
    final slot = slotOf(id);
    if (!slot.configured) {
      _notice = '${sceneLabel(id)} 还没有绑定音频：先点「选文件」。';
      _notify();
      return;
    }

    if (_state == MusicPlayState.paused &&
        _port.playingRelPath == slot.relPath) {
      _port.resume();
      _state = MusicPlayState.playing;
      _notice = '从暂停处继续播放${sceneLabel(id)}：${slot.displayName}';
      _notify();
      return;
    }

    _port.play(slot.relPath);
    _state = MusicPlayState.playing;
    _notice = '开始播放${sceneLabel(id)}：${slot.displayName}';
    _notify();
  }

  void pause() {
    if (_state != MusicPlayState.playing) {
      _notice = '当前没有正在播放的 BGM，无需暂停。';
      _notify();
      return;
    }
    _port.pause();
    _state = MusicPlayState.paused;
    _notice = '已暂停${sceneLabel(_activeSceneId)}的 BGM。';
    _notify();
  }

  void stop() {
    _port.stop();
    _state = MusicPlayState.stopped;
    _notice = _activeSceneId == null
        ? '已停止播放。'
        : '已停止${sceneLabel(_activeSceneId)}的 BGM。';
    _notify();
  }

  /// ★ 切场景：**先 stop 当前播放，再播新插槽**；空插槽只停不播。
  ///
  /// 顺序是同步的、显式的：Fake 端口会记到 `stop` 严格早于 `play`，且
  /// 任一时刻只有一条流在播（见测试里的 overlap 计数）。
  void switchScene(String sceneId) {
    if (!_ids.contains(sceneId)) return;

    // ① 无论上一场景是否真的在播，都显式停一次 —— 旧音频不许残留。
    _port.stop();
    _activeSceneId = sceneId;

    final slot = slotOf(sceneId);
    if (!slot.configured) {
      _state = MusicPlayState.stopped;
      _notice = '已停掉上一首；${sceneLabel(sceneId)} 未配置音频，先点「选文件」。';
      _notify();
      return; // ★ 空插槽 = 停旧的、不播新的
    }

    // ② 旧流已停，才播新的。
    _port.play(slot.relPath);
    _state = MusicPlayState.playing;
    _notice = '已切到${sceneLabel(sceneId)}：${slot.displayName}（先停旧曲再播放）。';
    _notify();
  }

  /// 释放底层播放器（供 App 退出 / 明确释放时用；UI 不摆假按钮）。
  void releasePlayer() {
    _port.release();
    _state = MusicPlayState.idle;
    _notice = '已释放本机播放器。';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _stateSub = null;
    super.dispose();
  }
}
