// ============================================================
// test/support/music_fakes.dart — 音乐端口的内存替身（P10 第 5 期 / A）
//
// 与 `FakeImagePicker` 同一套路：widget 测试跑在 fake-async 区域，平台通道
// 与真实文件读写的 Future 永不完成。Fake 的 Future 全部立即完成，播放类
// 方法同步 void，所以面板在 fake-async 下能完整跑完并留下**可断言的调用
// 序列**（切场景「先 stop 再 play」、只有一条流、配置真的写盘等）。
//
// ★ 单一替身覆盖端口的全部方法（play/pause/resume/stop/release/选文件/
//   读配置/写配置 + 播放态真源），测试用 `musicPort = FakeMusicPort(...)`
//   + addTearDown 还原。
// ★ 2.42.0 / P20 需求 4②：端口新增了 `resume()` 与播放态真源
//   （`playState` / `playingRelPath` / `stateStream`），这里逐条同步实现，
//   否则 `implements MusicPort` 会让整个测试套件编译失败。行为口径：
//     · play  = 换源播放（位置归零）→ state=playing、playingPath=新路径；
//     · pause = 位置保留 → state=paused、playingPath 不清空；
//     · resume= 从暂停处续播 → state=playing、不重新记 play 调用；
//     · stop  = 位置清空 → state=stopped、playingPath=null；
//   既有用例断言的 `calls` 序列（`stop` / `play:xxx` / `pause` …）一字未变。
// ============================================================

import 'dart:async' show Stream, StreamController;

import 'package:dice_realm/ui/room/room_music_ports.dart'
    show MusicPlayState, MusicPort, MusicSlot;

/// 内存音乐端口：记录调用序列、维护「当前流」计数用于叠播断言。
class FakeMusicPort implements MusicPort {
  FakeMusicPort({
    Map<String, MusicSlot>? seedSlots,
    this.importResult,
    this.importReturnsNull = false,
  }) : _slots = <String, MusicSlot>{...?seedSlots};

  /// 按调用顺序记录的事件（形如 `stop` / `play:music/combat.mp3` /
  /// `resume` / `import:daily` / `save`）。
  final List<String> calls = <String>[];

  /// 最近一次 play 的相对路径。
  String lastPlayPath = '';

  /// 选文件动作的返回槽位；为 null 时自动造一个假槽位。
  MusicSlot? importResult;

  /// 模拟「用户取消 / 读取失败」。
  bool importReturnsNull;

  /// saveSlots 被调用次数（配置真的落本机才有意义）。
  int saveCalls = 0;

  /// 最近一次写入的配置快照。
  Map<String, MusicSlot> saved = <String, MusicSlot>{};

  /// 当前在播的流数量（0 或 1）；play 前若已有流则记一次叠播。
  int activeStreams = 0;

  /// 检测到「上一条没停就播下一条」的次数，必须恒为 0。
  int overlaps = 0;

  /// loadSlots 被调用次数。
  int loadCalls = 0;

  /// 播放态真源的本地快照（等价于生产端口的 `playState`）。
  MusicPlayState state = MusicPlayState.idle;

  /// 当前在播（或暂停待续播）音频的相对路径；stop / release 清空。
  String? playingPath;

  final StreamController<MusicPlayState> _stateCtrl =
      StreamController<MusicPlayState>.broadcast();

  Map<String, MusicSlot> _slots;

  /// 直接预置槽位（行为级用例构造场景用）。
  void seed(String sceneId, MusicSlot slot) => _slots[sceneId] = slot;

  int countOf(String prefix) =>
      calls.where((String c) => c == prefix || c.startsWith(prefix)).length;

  int firstIndexOf(String prefix) => calls.indexWhere(
        (String c) => c == prefix || c.startsWith(prefix),
      );

  // ---- 播放态真源（供控制器订阅 / 断言） ----

  @override
  Stream<MusicPlayState> get stateStream => _stateCtrl.stream;

  @override
  MusicPlayState get playState => state;

  @override
  String? get playingRelPath => playingPath;

  /// 由测试主动推一个状态（模拟平台侧变化，例如播完 / 被系统打断）。
  void emitState(MusicPlayState next) {
    state = next;
    if (!_stateCtrl.isClosed) _stateCtrl.add(next);
  }

  @override
  void play(String relPath) {
    calls.add('play:$relPath');
    lastPlayPath = relPath;
    if (activeStreams > 0) overlaps += 1;
    activeStreams = 1;
    playingPath = relPath;
    emitState(MusicPlayState.playing);
  }

  @override
  void pause() {
    calls.add('pause');
    // 暂停保留位置与在播路径（续播要判定「是不是同一首」）。
    emitState(MusicPlayState.paused);
  }

  @override
  void resume() {
    calls.add('resume');
    if (playingPath != null) activeStreams = 1;
    emitState(MusicPlayState.playing);
  }

  @override
  void stop() {
    calls.add('stop');
    activeStreams = 0;
    playingPath = null;
    emitState(MusicPlayState.stopped);
  }

  @override
  void release() {
    calls.add('release');
    activeStreams = 0;
    playingPath = null;
    emitState(MusicPlayState.idle);
  }

  @override
  Future<Map<String, MusicSlot>> loadSlots() async {
    calls.add('load');
    loadCalls += 1;
    return <String, MusicSlot>{..._slots};
  }

  @override
  void saveSlots(Map<String, MusicSlot> slots) {
    calls.add('save');
    saveCalls += 1;
    saved = <String, MusicSlot>{...slots};
    _slots = <String, MusicSlot>{...slots};
  }

  @override
  Future<MusicSlot?> importAudio(String sceneId) async {
    calls.add('import:$sceneId');
    if (importReturnsNull) return null;
    return importResult ??
        MusicSlot(
          relPath: 'music/$sceneId.mp3',
          displayName: 'fake_$sceneId.mp3',
        );
  }
}
