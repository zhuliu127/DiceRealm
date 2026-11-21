// ============================================================
// room_music_ports.dart — 音乐控制台的可注入端口（P10 第 5 期 / A）
//
// 用户拍板的两项方案：① 解锁依赖，加音频播放插件；② 作用范围 = **KP 本机
// 播放**（不联网、不广播、不同步、不进房间状态、不进存档、不新增任何事件）。
//
// 沿用老 APP `ui/room-panels.js:4029-4051 musicSheet` 的口径：用户用文件
// 选择框挑一个**本机音频文件**，只在本机播放；不打包任何音频资源。老 APP
// 没有「场景插槽」，那是本批按用户描述新增的能力。
//
// ★ 单一全局可替换实例 [musicPort]：播放 / 暂停 / 停止 / 释放 / 选文件 /
//   复制落盘 / 读配置 / 写配置 **全部** 经这一个端口。测试注入 Fake 替身
//   并在 addTearDown 还原 —— 只存在一份全局可变状态，不存在多份互相竞争。
// ★ 与项目既有端口（图片选择器 / 导出动作）同一套理由：widget 测试跑在
//   fake-async 区域，平台通道与真实文件读写的 Future 永不完成。因此：
//     · 播放类方法同步返回 void（发起即返回），widget 里零 await；
//     · 配置读写 / 选文件返回 Future，但生产实现 catch 一切异常、永远
//       resolve；widget 用 .then 消费，初始态同步可用，绝不挂死。
// ★ 持久化只存「应用私有目录相对路径 + 显示名」，绝不存 content:// 之类的
//   临时授权 URI（Android 重启后失效）；音频字节复制到私有目录后才可播。
// ============================================================

import 'dart:async' show Stream, StreamController, unawaited;
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File, Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 播放态。**定义在端口层**，因为全库只有一个全局播放器（[musicPort]），
/// 「此刻在播什么 / 是否暂停」只能由端口说了算。
///
/// ★ 裁定 D10：早期版本把这个枚举放在 `room_music_controller.dart` 里、每个
///   弹层各持一份 `_state` ⇒ 状态不共享（音乐控制台在播，打开「BGM 场景」
///   快捷弹层时新控制器以为 `idle`，点「暂停」只提示「当前没有正在播放的
///   BGM」而音乐照放）。因此上移到端口层，控制器只做「读快照 + 订流」的
///   投影，不再发明第二份真源。
enum MusicPlayState { idle, playing, paused, stopped }

/// 一个 BGM 场景插槽（顺序即 UI 展示顺序）。
class MusicScene {
  const MusicScene(this.id, this.label);

  /// 稳定 id，同时用作私有目录里的音频文件名与持久化 Map 的键。
  final String id;

  /// 给 KP 看的中文名。
  final String label;
}

/// 5 个场景插槽：日常 / 探索 / 悬疑 / 战斗 / 后日谈。
const List<MusicScene> kMusicScenes = <MusicScene>[
  MusicScene('daily', '日常'),
  MusicScene('explore', '探索'),
  MusicScene('suspense', '悬疑'),
  MusicScene('combat', '战斗'),
  MusicScene('epilogue', '后日谈'),
];

/// 单个插槽的本机配置。
///
/// 只存 [relPath]（应用私有目录相对路径，形如 `music/combat.mp3`）与
/// [displayName]（用户选文件时的文件名）。二者都不含绝对路径、不含临时
/// 授权 URI，因此重启 App 后仍能拼出可播放的文件。
class MusicSlot {
  const MusicSlot({required this.relPath, required this.displayName});

  final String relPath;
  final String displayName;

  bool get configured => relPath.isNotEmpty;

  static const MusicSlot empty = MusicSlot(relPath: '', displayName: '');

  Map<String, Object?> toJson() => <String, Object?>{
        'relPath': relPath,
        'displayName': displayName,
      };

  /// 从持久化 JSON 还原；缺 relPath / 形状不对 → null（当作未配置）。
  static MusicSlot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rel = raw['relPath'];
    final name = raw['displayName'];
    if (rel is! String || rel.isEmpty) return null;
    if (rel.contains('..') || rel.contains('://')) return null;
    return MusicSlot(
      relPath: rel,
      displayName: name is String && name.isNotEmpty ? name : rel,
    );
  }
}

/// 音乐控制台的唯一端口。
///
/// 生产实现 [SystemMusicPort] 封装 `audioplayers` + `file_picker` + 本机文件；
/// 测试实现放在测试侧（`FakeMusicPort`），逐条记录调用序列。
abstract class MusicPort {
  const MusicPort();

  // ---- 播放控制（同步 void：widget 零 await） ----

  /// 播放 [relPath] 指向的私有目录音频。生产实现内部先停当前源再播，
  /// 保证任何调用路径都不会叠播。
  void play(String relPath);

  void pause();

  void stop();

  /// 从**暂停处**续播（不清空播放位置）。
  ///
  /// 与 [play] 的区别：`play(relPath)` 内部先 `stop()` 再重新装载音频源，
  /// 播放位置归零（＝从头重放）；[resume] 让底层从暂停点继续，生产实现就是
  /// `AudioPlayer.resume()`（其文档明确：pause 之后 resume 从暂停处继续）。
  /// 只有「暂停 → 再点播放」这条路才用它，其余一律走 [play]。
  void resume();

  /// 释放底层播放器（供 App 退出 / 明确释放时用；UI 不放假按钮）。
  void release();

  // ---- 播放态真源（跨弹层共享的唯一来源，见裁定 D10） ----

  /// 播放态变更流。多个控制器可同时订阅（生产实现是 broadcast 流）。
  Stream<MusicPlayState> get stateStream;

  /// 播放态的同步快照：构造控制器 / 首帧 build 时不必等流。
  MusicPlayState get playState;

  /// 当前在播（或暂停待续播）的音频相对路径；什么都没放 → null。
  ///
  /// 控制器用它把「端口在放哪个文件」反查回场景 id，从而跨弹层还原「当前
  /// 场景」，不必再维护第二份全局场景状态。[resume] 本身不需要它（底层
  /// 播放器自己记得位置），它只服务 UI 显示与「是不是同一首」的判定。
  String? get playingRelPath;

  // ---- 配置持久化 ----

  /// 读本机配置。**任何异常都必须退化成干净空 Map，绝不抛**。
  Future<Map<String, MusicSlot>> loadSlots();

  /// 写本机配置（同步发起，异常由生产实现吞掉）。
  void saveSlots(Map<String, MusicSlot> slots);

  // ---- 选文件 + 落盘 ----

  /// 选一个本机音频文件 → 复制字节到私有目录 → 返回新槽位。
  /// 用户取消 / 读取失败 / 超限 → null（调用方给真提示，绝不造假状态）。
  Future<MusicSlot?> importAudio(String sceneId);
}

/// [MusicPort.playState] 的布尔便捷视图。
///
/// 写成 extension 而不是接口成员：测试替身用 `implements MusicPort` 时
/// 不必为它多写一行，也不会出现「两个实现口径跑偏」的可能。
extension MusicPortPlaying on MusicPort {
  /// 此刻底层是否真的在播（暂停 / 停止 / 空闲都是 false）。
  bool get isPlaying => playState == MusicPlayState.playing;
}

/// 全局可替换实例。测试 `musicPort = FakeMusicPort();` 后 addTearDown 还原。
MusicPort musicPort = SystemMusicPort();

/// 生产实现：唯一的全局默认端口。
///
/// 懒创建 [AudioPlayer]：构造本对象时零平台交互，因此即便 widget 测试没来
/// 得及注入也不会在构造期触发任何平台通道。
class SystemMusicPort implements MusicPort {
  SystemMusicPort();

  static const String _rootDir = 'dice_realm';
  static const String _musicDir = 'music';
  static const String _slotsFile = 'music_slots.json';
  static const String _formatTag = 'dice-realm.music-slots';
  static const int _formatVersion = 1;

  /// 单曲上限 64MB（超出拒绝并给真提示，避免把整块内存读进来）。
  static const int maxAudioBytes = 64 * 1024 * 1024;

  AudioPlayer? _player;

  /// 播放态真源：一条 broadcast 流，同时开几个弹层、几个控制器都能订。
  final StreamController<MusicPlayState> _stateCtrl =
      StreamController<MusicPlayState>.broadcast();

  MusicPlayState _state = MusicPlayState.idle;

  /// 当前在播音频的相对路径；[stop] / 播放失败 / [release] 时清空。
  /// 暂停**不清空**（还要靠它判定「是不是同一首」好续播）。
  String? _playingRelPath;

  /// 是否已把 `onPlayerStateChanged` 接到 [_stateCtrl]。[AudioPlayer] 是懒
  /// 创建的（构造本端口时零平台交互），所以只在第一次真要播时接一次。
  bool _stateWired = false;

  /// `_play` 内「先 stop 再 play」期间的进行计数。
  ///
  /// 为什么需要：[play] 内部会先 `stop()` 旧源，播放器随之报一个 `stopped`；
  /// 那是**同一个播放动作的一半**，不能当成「用户按了停止」广播出去，
  /// 否则另一个弹层的控制器会闪一下「已停止」。计数 > 0 时丢弃这类中间态。
  int _playInFlight = 0;

  String get _sep => Platform.pathSeparator;

  /// 懒创建播放器，并顺手把平台侧状态变化接进端口真源。
  AudioPlayer _ensurePlayer() {
    final p = _player ??= AudioPlayer();
    if (!_stateWired) {
      _stateWired = true;
      // 平台侧的真实跃迁（含播完 completed、被系统打断）一律转成端口播放态；
      // Dart 侧只做映射，不猜、不覆盖真实结果。
      p.onPlayerStateChanged.listen(
        _applyPlayerState,
        onError: (Object _) {
          // 平台流报错不影响 Dart 侧状态（不把异常变成假状态）。
        },
      );
    }
    return p;
  }

  /// `audioplayers` 的 5 个状态 → 端口 4 态。
  static MusicPlayState _mapPlayerState(PlayerState s) => switch (s) {
        PlayerState.playing => MusicPlayState.playing,
        PlayerState.paused => MusicPlayState.paused,
        PlayerState.stopped => MusicPlayState.stopped,
        // 播完 = 这条流结束了，位置不可续播；对外与「已停止」同义。
        PlayerState.completed => MusicPlayState.stopped,
        PlayerState.disposed => MusicPlayState.idle,
      };

  /// 把播放器的真实跃迁映射成端口播放态。
  ///
  /// [_playInFlight] > 0 时的 `stopped` 是「换源播放」的内部前奏，直接丢弃。
  void _applyPlayerState(PlayerState s) {
    final mapped = _mapPlayerState(s);
    if (_playInFlight > 0 && mapped == MusicPlayState.stopped) return;
    _emit(mapped);
  }

  /// 更新快照并广播。端口被释放后 `_stateCtrl` 仍可用（不 close），
  /// 因此这里只挡 isClosed 的极端情形。
  void _emit(MusicPlayState next) {
    _state = next;
    if (!_stateCtrl.isClosed) _stateCtrl.add(next);
  }

  @override
  Stream<MusicPlayState> get stateStream => _stateCtrl.stream;

  @override
  MusicPlayState get playState => _state;

  @override
  String? get playingRelPath => _playingRelPath;

  Future<String> _resolve(String relPath) async {
    final docs = await getApplicationDocumentsDirectory();
    final tail = relPath.split('/').join(_sep);
    return '${docs.path}$_sep$_rootDir$_sep$tail';
  }

  Future<File> _slotsPath() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}$_sep$_rootDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}$_sep$_slotsFile');
  }

  @override
  void play(String relPath) {
    // 意图先落快照：跨弹层「当前在放哪个文件」必须同步可见，不能等平台回调
    // （widget 测试的 fake-async 区域里平台回调可能永不发生）。
    _playingRelPath = relPath;
    unawaited(_play(relPath));
  }

  Future<void> _play(String relPath) async {
    _playInFlight += 1;
    try {
      final abs = await _resolve(relPath);
      final p = _ensurePlayer();
      // 双保险：即便调用方忘了先 stop，也不会出现两条流叠播。
      await p.stop();
      await p.play(DeviceFileSource(abs));
      _emit(MusicPlayState.playing);
    } catch (_) {
      // 平台不可用 / 文件已被删：不抛。可见状态由控制器如实表达意图，
      // 这里不把「发起失败」伪装成「播放成功」：清掉在播路径并回到空闲。
      _playingRelPath = null;
      _emit(MusicPlayState.idle);
    } finally {
      _playInFlight -= 1;
    }
  }

  @override
  void pause() => unawaited(_pause());

  Future<void> _pause() async {
    try {
      final p = _player;
      if (p == null) return; // 从没播过 ⇒ 没有「已暂停」可言
      await p.pause();
      _emit(MusicPlayState.paused);
    } catch (_) {
      // 同上：平台异常不外抛。
    }
  }

  @override
  void resume() => unawaited(_resume());

  Future<void> _resume() async {
    try {
      final p = _player;
      if (p == null) return; // 从没播过 ⇒ 没有可续播的位置
      await p.resume();
      _emit(MusicPlayState.playing);
    } catch (_) {
      // 同上：平台异常不外抛。
    }
  }

  @override
  void stop() => unawaited(_stop());

  Future<void> _stop() async {
    try {
      await _player?.stop();
    } catch (_) {
      // 同上：平台异常不外抛。
    }
    // `stop()` 会重置播放位置 ⇒ 之后无法续播，在播路径必须一并清掉。
    _playingRelPath = null;
    _emit(MusicPlayState.stopped);
  }

  @override
  void release() => unawaited(_release());

  Future<void> _release() async {
    final p = _player;
    _player = null;
    _stateWired = false;
    _playingRelPath = null;
    _emit(MusicPlayState.idle);
    try {
      await p?.dispose();
    } catch (_) {
      // 同上：平台异常不外抛。
    }
  }

  @override
  Future<Map<String, MusicSlot>> loadSlots() async {
    try {
      final file = await _slotsPath();
      if (!await file.exists()) return <String, MusicSlot>{};
      final text = await file.readAsString();
      if (text.trim().isEmpty) return <String, MusicSlot>{};
      final decoded = jsonDecode(text);
      if (decoded is! Map) return <String, MusicSlot>{};
      final raw = decoded['slots'];
      if (raw is! Map) return <String, MusicSlot>{};
      final out = <String, MusicSlot>{};
      raw.forEach((Object? k, Object? v) {
        if (k is! String || k.isEmpty) return;
        final slot = MusicSlot.fromJson(v);
        if (slot != null) out[k] = slot;
      });
      return out;
    } catch (_) {
      return <String, MusicSlot>{};
    }
  }

  @override
  void saveSlots(Map<String, MusicSlot> slots) =>
      unawaited(_saveSlots(slots));

  Future<void> _saveSlots(Map<String, MusicSlot> slots) async {
    try {
      final file = await _slotsPath();
      final body = <String, Object?>{
        'format': _formatTag,
        'version': _formatVersion,
        'slots': <String, Object?>{
          for (final e in slots.entries) e.key: e.value.toJson(),
        },
      };
      // 先写临时文件再 rename：中途被杀不会留下半截 JSON。
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(body), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // 写不进去不该崩页面；下次读盘会退回空配置。
    }
  }

  @override
  Future<MusicSlot?> importAudio(String sceneId) async {
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: '选择本机音频（仅本机播放）',
        type: FileType.audio,
      );
      if (picked == null) return null; // 用户取消
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return null;
      if (maxAudioBytes > 0 && bytes.length > maxAudioBytes) return null;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}$_sep$_rootDir$_sep$_musicDir');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = _safeExt(picked.extension);
      final file = File('${dir.path}$_sep$sceneId.$ext');
      await file.writeAsBytes(bytes, flush: true);
      return MusicSlot(
        relPath: '$_musicDir/$sceneId.$ext',
        displayName: picked.name,
      );
    } catch (_) {
      return null;
    }
  }

  /// 扩展名安全化：只留小写字母数字，挡掉路径穿越与奇怪后缀。
  static String _safeExt(String? raw) {
    final e = (raw ?? '').toLowerCase();
    if (e.isEmpty || e.length > 8) return 'audio';
    for (final unit in e.codeUnits) {
      final digit = unit >= 0x30 && unit <= 0x39;
      final lower = unit >= 0x61 && unit <= 0x7A;
      if (!digit && !lower) return 'audio';
    }
    return e;
  }
}
