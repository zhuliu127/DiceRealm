// ============================================================
// room_request_watcher.dart — 推送要求的**全局居中弹窗**（P10 第 6 期 / 问题 5）
//
// 用户原话：「现在让 KP 和所有玩家收到的推送要求，直接弹窗显示在屏幕中间，
//   并可以按推送的内容操作（比如点同意）」。
//
// ★ 与状态条的分工：`gp_status.dart` 的卡片**原样保留**，作为「已读后再看」
//   入口；本文件只在**新请求第一次出现**时额外弹一个屏幕正中的对话框。
//   两者读的是同一份数据（KP：`hostRead.pending` / `requestsBySeat`；
//   玩家：自己裁剪态的 `state['requests']`），因此私密口径天然继承：
//   别人的请求根本不在这份视图里，不会被弹出来。
//
// ★ 去重：State 里 `Set<String> _seen`（= **已真弹过**的 id，同一 id 只弹
//   一次）。首次挂载把**当时已有的** id 记为已读（只弹之后新来的）；
//   **唯一例外是 KP 的「待我确认」（`hostRead.pending`）—— 挂载即入队弹一次**，
//   因为它本来就是必须 KP 处理的队列，被静默记账就会变成「玩家提交了、KP
//   一条都收不到」（P17 KP-1-b，见 `_p17_w1a_report.md §9`）。
//   弹窗被点同意 / 拒绝 / 点屏障关闭都不会再弹；请求被 `settleRequest` 处理后
//   从列表消失，也不影响第 4 期修的 REQUEST-done SEAT 定向 EVT（本文件不碰出站链路）。
//
// ★ 为什么用 `showGeneralDialog` 而不是 `showDialog`：项目门禁要求所有弹层
//   走统一入口、零裸 `showDialog`；`showGeneralDialog` 是它的底层居中版本，
//   既满足「屏幕正中、不是底部 sheet」，又不破坏既有门禁口径。
//
// ★ 只画、只发意图：零权威端引用、零状态写入、零规则调用、零新增事件。
//
// ★ P10 第 6 期收尾（本批修正）：
//   · 相对导入路径：`lib/ui/room/` 下回 `lib/domain/` 必须是 `../../domain/`
//     （原来写成 `../domain/` 会指向不存在的 `lib/ui/domain/`，整批编译失败）；
//   · 展示取文本统一走 `roomText`（null → ''）而非 `jsStr`（null → 'null'）：
//     `state.request` 会在 KP 的 `pending` 里留一条**没有 op 字段**的记账，
//     它的确认方是玩家（CONSENT）不是 KP（CONFIRM）。用 jsStr 会把它误判成
//     「待确认：null」并弹出来 —— 与 `GpStatus` 的 `roomText` 口径对齐后跳过；
//   · 详情行同时扫顶层与 `p` / `payload` 载荷袋，才能显示技能 / 骰式 / 说明；
//   · 控制器在 `didChangeDependencies` 里捕获，不依赖弹窗 context 能否向上
//     找到 `RoomScope`（生产路径的 RoomScope 可能挂在 Navigator 之下）；
//   · `SafeArea > Center > Dialog` 保证屏幕正中；`LayoutBuilder` 动态收窄，
//     窄屏不溢出；`_drain` 用 try/finally 保证 `_draining` 一定复位。
// ============================================================

import 'dart:async' show unawaited;
import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';

import '../../domain/js_compat.dart' show asList, asMap;
import '../../domain/room_types.dart' show RoomIntent, RoomRole;
import 'room_controller.dart' show RoomController;
import 'room_scope.dart' show RoomScope;
import 'room_session.dart' show RoomSession;
import 'room_text.dart' show roomText;
import 'sheets/room_sheet.dart' show showRoomSheet;
import 'sheets/sheet_opposed.dart'
    show MonsterValueResult, showMonsterValueSheet;
import 'widgets/room_panel_kit.dart' show RoomTap;

/// 推送弹窗内部稳定 key。
class RoomPushKeys {
  const RoomPushKeys._();

  static const Key root = ValueKey<String>('roomPush/root');
  static const Key title = ValueKey<String>('roomPush/title');
  static const Key details = ValueKey<String>('roomPush/details');
  static const Key agree = ValueKey<String>('roomPush/agree');
  static const Key reject = ValueKey<String>('roomPush/reject');
}

/// ★ P13：KP 同意后「防守方式」选择弹窗的稳定 key（独立前缀，避免与推送
///   弹窗的 `roomPush/*` 及怪物补值窗撞键）。
class RoomReactionKeys {
  const RoomReactionKeys._();

  static const Key root = ValueKey<String>('roomReaction/root');
  static const Key counter = ValueKey<String>('roomReaction/counter');
  static const Key dodge = ValueKey<String>('roomReaction/dodge');
  static const Key none = ValueKey<String>('roomReaction/none');
  static const Key confirm = ValueKey<String>('roomReaction/confirm');
}

/// 回应一条推送该走哪个意图通道。
enum RoomPushReply {
  /// `INTENT.CONSENT{id, agree}`（状态变更请求 / 需我同意）。
  consent,

  /// `INTENT.CONFIRM{op, by, agree}`（KP 待确认的高危动作）。
  confirm,
}

/// 一条可弹出的推送要求（纯数据，便于单测与跨视角验数）。
class RoomPushRequest {
  const RoomPushRequest({
    required this.id,
    required this.title,
    required this.details,
    required this.reply,
    required this.payload,
    this.source = const <String, Object?>{},
  });

  /// 去重键。pending 用 `pending:<op>:<by>:<入队时刻>:<参数签名>`，状态请求用其 `id`。
  final String id;

  final String title;

  /// 「谁发起 / 类型 / 说明 / 技能 …」，**源载荷带键才输出**，不臆造。
  final List<String> details;

  final RoomPushReply reply;

  /// 回应该请求时发给 `sendIntent` 的载荷（不含 `agree`）。
  final Map<String, Object?> payload;

  /// ★ P12 PL-1c：原始 pending 的 `p` 袋（只读）。
  /// 仅用于「同意」回调判断 `auto` + `defender.side=='monster'`；
  /// [payload] 仍严格是 `{op, by}` 契约，本字段不进出站。
  final Map<String, Object?> source;
}

/// 详情行的中文标签（只列这些键，其余一律不展示）。
const Map<String, String> _detailLabels = <String, String>{
  'id': '编号',
  'op': '类型',
  'by': '发起人',
  'from': '发起人',
  'seat': '座位',
  'reason': '说明',
  'skill': '技能',
  'expr': '骰式',
  'label': '名称',
  'text': '内容',
  'kind': '类别',
  'target': '目标',
  'note': '备注',
  'change': '变更',
};

String _fmt(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  try {
    return jsonEncode(v);
  } catch (_) {
    return '';
  }
}

/// 载荷签名：给去重键区分「同 op 同 by、参数不同」的两条待办。
///
/// `jsonEncode` 失败一律回空串 —— 弹窗链路绝不因为一条脏载荷整段抛
/// （与 [_fmt] 同一口径）。空串只会让「同 op + 同 by + 同毫秒 + 都不可编码」
/// 这种极端组合退化成撞键，比抛异常安全得多。
String _payloadSig(Object? v) {
  try {
    return jsonEncode(v);
  } catch (_) {
    return '';
  }
}

/// 从请求对象里挑「有键且有值」的详情行。
///
/// 顶层之外还扫两个常见载荷袋：ACT 入 pending 时把参数放在 `p`，
/// 定向 REQUEST 把参数放在 `payload` ——「技能 / 骰式 / 说明」等可读字段
/// 往往嵌在里面，只扫顶层会退化成「只显示一个 id」。同一行去重。
List<String> _detailsOf(
  Map<String, Object?> raw, {
  List<String> extra = const <String>[],
  String? initiatorName,
}) {
  final out = <String>[...extra];
  final sources = <Map<String, Object?>>[
    raw,
    asMap(raw['p']),
    asMap(raw['payload']),
  ];
  for (final src in sources) {
    for (final e in _detailLabels.entries) {
      if (!src.containsKey(e.key)) continue;
      var s = _fmt(src[e.key]);
      // ★ P12 KP-6：`by` / `from` 行仍叫「发起人」，但取值改成本机解析的
      //   角色名（不是裸 seat）。传 null = 旧行为；返回空串时下面
      //   `s.isEmpty` 会跳过该行（「空不出行」）。
      if (initiatorName != null && (e.key == 'by' || e.key == 'from')) {
        s = initiatorName;
      }
      if (s.isEmpty || s == '{}' || s == '[]' || s == 'null') continue;
      final line = '${e.value}：$s';
      if (out.contains(line)) continue;
      out.add(line);
    }
  }
  return out;
}

/// 收集当前视角「应该被弹窗提示」的请求。
///
/// 与 `GpStatus` 同源同口径：KP 读 `hostRead`（权威只读面），玩家 / 旁观
/// 读自己那份裁剪态（缺 `requests` 键 ≠ 有 0 条待办）。**不读别人的请求**，
/// 因此跨设备私密口径由数据层保证，不需要在这里二次隐藏。
/// ★ P12 KP-6：发起人显示名。回退链 `charName → nickname → seat`。
///
/// 角色名单一真源是 `members[].charName`；查不到成员 / 前两级全缺时回落到
/// 裸 seat。返回空串时 [_detailsOf] 会跳过「发起人」行（空不出行）。
/// 纯函数：不改入参、不读 RoomScope、不写权威 state。
String pushInitiatorOf(Map<String, Object?> state, String seat) {
  if (seat.isEmpty) return '';
  for (final Object? raw in asList(state['members'])) {
    final Map<String, Object?> m = asMap(raw);
    if (roomText(m['seat']) != seat) continue;
    final String charName = roomText(m['charName']);
    if (charName.isNotEmpty) return charName;
    final String nick = roomText(m['nickname']);
    if (nick.isNotEmpty) return nick;
    break;
  }
  return seat;
}

List<RoomPushRequest> collectRoomPushRequests(RoomSession session) {
  final out = <RoomPushRequest>[];
  final state = session.state;
  final read = session.hostRead;
  if (session.role == RoomRole.kp && read != null) {
    // ① KP 待确认的高危动作。
    for (final q in read.pending) {
      final op = roomText(q['op']);
      final by = roomText(q['by']);
      // ★ 与 GpStatus 完全同源：`state.request` 会在 pending 里留一条
      //   **没有 op 字段**的记账（确认方是玩家，走 CONSENT 而不是 KP 的
      //   CONFIRM）。roomText(null) → '' → 这里跳过，避免误弹「待确认：null」。
      if (op.isEmpty) continue;
      /* ★ P17 KP-1①（本批主修）：去重键必须带 pending 项**自身的区分信息**。
         改前只用 `op + by`：同一玩家连续两次同名高危动作（例如两次
         `aid.apply`、只是 targetSeat / skill 不同）会真的在 `pending` 里留两条
         （`room_model_host_intent.dart:307-330` 的防重复只按
         `by+op+jsonEncode(p)` 判重，参数不同就不算重复），但两条 id 撞成
         一个 → `_seen.add`（`_onSession`，本文件 :299）第二次返回 false → **第二条申请永不弹窗**。
         可用键只有 `act()` 入队处写入的那五个
         （`room_model_host_intent.dart:324-330`）：`by` / `op` / `p` / `need` /
         `at`（入队毫秒）。pending 项**没有** `id` 字段 —— 只有 `state.request`
         那条有 `r$localSeq`（`room_model_actions_sheet.dart:665-666`），而它没有
         `op`、已被上面 `op.isEmpty` 跳过，所以不能照抄 `q['id']`。
         因此取「op + by + 入队时刻 + 参数载荷签名」：`at` 区分先后，签名兜住
         同一毫秒入队（同签名不可能两条共存，故这组键在 pending 里必然唯一）。
         ⚠️ `payload` 仍必须是 `{op, by}`：domain 的 `confirmPending` 按 op+by
         定位待办，加字段会让确认链路对不上。 */
      final sig = _payloadSig(asMap(q['p']));
      // ★ P12 KP-6：删「来自 …」整行（extra 改空表）；「发起人」行保留，
      //   但取值由裸 seat 改成角色名。`_detailLabels` 一个条目都不删。
      final initiator = pushInitiatorOf(state, by);
      out.add(RoomPushRequest(
        id: 'pending:$op:$by:${roomText(q['at'])}:$sig',
        title: '待确认：$op',
        details: _detailsOf(q, initiatorName: initiator),
        reply: RoomPushReply.confirm,
        // ★ P12 PL-1c：`payload` 仍严格 `{op,by}`，原始 p 袋另存于 source。
        payload: <String, Object?>{'op': op, 'by': by},
        source: asMap(q['p']),
      ));
    }
    // ② 玩家提交的状态变更请求（逐 seat 汇总）。
    for (final entry in read.requestsBySeat.entries) {
      // ★ P12 KP-6：同上，删「来自」行、发起人取角色名。
      final initiator = pushInitiatorOf(state, entry.key);
      for (final r in entry.value) {
        final id = roomText(r['id']);
        if (id.isEmpty) continue;
        out.add(RoomPushRequest(
          id: id,
          title: '状态变更请求',
          details: _detailsOf(r, initiatorName: initiator),
          reply: RoomPushReply.consent,
          payload: <String, Object?>{'id': id},
        ));
      }
    }
  } else {
    // ③ 玩家 / 旁观：只读自己那份裁剪态。
    for (final raw in asList(session.state['requests'])) {
      final r = asMap(raw);
      final id = roomText(r['id']);
      if (id.isEmpty) continue;
      out.add(RoomPushRequest(
        id: id,
        title: '需我同意',
        details: _detailsOf(r),
        reply: RoomPushReply.consent,
        payload: <String, Object?>{'id': id},
      ));
    }
  }
  return out;
}

/// 页面级全局监听：把 [child] 原样画出来，额外负责弹「新推送」。
///
/// 挂在 `RoomGamePage` 根节点外层，因此游戏内任何栏位触发的请求都能覆盖；
/// 本身不引入任何 RenderObject，不改变 `LayoutBuilder` 的约束与几何。
class RoomRequestWatcher extends StatefulWidget {
  const RoomRequestWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<RoomRequestWatcher> createState() => _RoomRequestWatcherState();
}

class _RoomRequestWatcherState extends State<RoomRequestWatcher> {
  RoomSession? _session;

  /// 页面级捕获的控制器：弹窗 route 的 context 不保证能向上找到 RoomScope，
  /// 所以回应时不用 `RoomScope.read(dialogCtx).controller`。
  RoomController? _controller;

  /// 已**真的弹出去过**的 id。语义与 P10 一致：同一 id 只弹一次。
  ///
  /// ★ P17 KP-1-b：改前这里记的是「已**见过**」——在 `_onSession` 里先
  /// `_seen.add` 再入队，一旦这条最终没能弹出来（弹窗期异常 / 页面已卸载 /
  /// 入队后被清空），这条 id 就永久被判成「已弹过」，之后无论 session 怎么
  /// 变化都不再弹 → 用户看到的是「申请丢了、KP 无法同意」。现在改成
  /// **出队后、真正 `showGeneralDialog` 之前**才记账，中间用 [_queued] 防重复
  /// 入队。所有「同一 id 只弹一次」的既有断言口径不变。
  final Set<String> _seen = <String>{};

  /// 已入队、还没轮到弹的 id。只用于防同一帧内重复入队，
  /// 出队时立刻转进 [_seen]（见 [_drain]）。
  final Set<String> _queued = <String>{};

  final List<RoomPushRequest> _queue = <RoomPushRequest>[];
  bool _draining = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = RoomScope.of(context);
    final s = scope.session;
    if (identical(s, _session)) {
      // 会话未变但作用域重建（换视角 / 换控制器）时刷新引用即可，
      // **不要**重置 _seen，否则历史待办会被重新弹一遍。
      _controller = scope.controller;
      return;
    }
    _session?.removeListener(_onSession);
    _session = s;
    _controller = scope.controller;
    s.addListener(_onSession);
    // ★ 首次挂载（或换会话）：把当时已有的请求记为「已读」，只弹之后新到的。
    //   否则一进房间（或切视角重建）就会把历史待办全弹一遍。
    //
    //   ⚠️ P17 KP-1-b 例外：**「待我确认」这一类（[RoomPushReply.confirm]，
    //   即 KP 的 `hostRead.pending`）不记账，改为入队弹一次**。
    //   实测链路（静态逐段核查见 `_p17_w1a_report.md §9`）：玩家发起的
    //   `aid.apply` 这类 `RoomConfirm.kp` 动作确实进了 `host.pending`，
    //   但 KP 常常是**在玩家提交之后**才进入房间页（先在大厅看成员 / 切过
    //   视角 / 断线重连重建页面）——旧逻辑会把这条待办在挂载瞬间记成「已读」，
    //   于是「玩家点了治疗，KP 这边一条推送都没有、无法同意」。
    //   待确认待办本来就是**必须 KP 处理**的队列，挂载即弹是正确口径；
    //   玩家侧「需我同意」（consent）保持原口径不弹历史。
    //
    //   ★ P20（需求 3④）：玩家 / 旁观视角 **同样不预置 consent 类历史**。
    //   为什么必须扩：玩家 dock 的 `gpStatus` 卡片被删（D6「只看弹窗通道」），
    //   若挂载时仍把「已存在的请求」记成已读，那条请求就**两条通道都断了**
    //   （弹窗不弹、状态卡片又没了）→ 玩家永远点不到同意。改成挂载即入队弹
    //   一次，与 KP 待确认完全同口径。
    //   ⚠️ `_seen` 语义不变（同一 id 只弹一次，出队前才记账）。
    //   KP 视角（`role == kp`，**含 hostRead 缺失的退化情况**）的预置 / 入队
    //   分支与改前**逐字等价**，所以 KP 侧零回归；只有玩家 / 旁观的口径变了。
    final bool kpView = s.role == RoomRole.kp;
    final all = collectRoomPushRequests(s);
    _seen
      ..clear()
      ..addAll(all
          .where((RoomPushRequest r) =>
              kpView && r.reply != RoomPushReply.confirm)
          .map((RoomPushRequest r) => r.id));
    _queue.clear();
    _queued.clear();
    for (final r in all) {
      // KP 视角：只把「待我确认」入队（其余按历史记账）；玩家 / 旁观：全入队。
      if (kpView && r.reply != RoomPushReply.confirm) continue;
      if (_queued.add(r.id)) _queue.add(r);
    }
    _schedule();
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    final s = _session;
    if (s == null) return;
    for (final r in collectRoomPushRequests(s)) {
      // `_seen` = 已弹过；`_queued` = 已排队等弹。两者任一命中都不重复入队。
      if (_seen.contains(r.id) || !_queued.add(r.id)) continue;
      _queue.add(r);
    }
    _schedule();
  }

  /// 排一次「帧后开弹」。已经在弹（[_draining]）时不再重复排 ——
  /// 正在跑的那一轮 `_drain` 会自己把 `_queue` 吃空。
  ///
  /// ★ P17 KP-1-b：`room_request_watcher` 是页面根节点，首帧就可能在
  /// `didChangeDependencies` 里带着「KP 待确认」的入队项进来，
  /// 所以调度逻辑抽成一处，挂载路径与新请求路径共用。
  void _schedule() {
    if (_queue.isEmpty || _draining) return;
    _draining = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        // 页面在帧前被销毁：复位闸门，别把 State 永久锁死。
        _draining = false;
        return;
      }
      unawaited(_drain());
    });
  }

  /// 一次弹一条；上一条关闭后才弹下一条，绝不叠弹。
  ///
  /// try/finally 保证任何异常（如页面在弹窗打开时被销毁）后 `_draining`
  /// 都会复位，不会把监听永久卡死。
  ///
  /// ★ P17 KP-1-b 两处加固：
  ///   ① **单条弹窗异常不拖垮整条流水线**：改前 `showGeneralDialog` 一抛，
  ///      整轮 `_drain` 直接跳出（当前这条已被 `removeAt` 吃掉、后面排队
  ///      的全丢），用户看到的就是「之后的申请再也不弹」；
  ///   ② `finally` 里若队列还有残留就补排一次（异常路径 / 弹窗期间新到的
  ///      请求都可能落到这里），保证「有一条没弹完 → 一定还有人接着弹」。
  Future<void> _drain() async {
    try {
      while (mounted && _queue.isNotEmpty) {
        final r = _queue.removeAt(0);
        _queued.remove(r.id);
        // 记账点放在**开弹之前一跳**（不是入队时）：这一条确实要被呈现了，
        // 「同一 id 只弹一次」到此生效（既有 5D 口径不变）。
        _seen.add(r.id);
        try {
          await showGeneralDialog<void>(
            context: context,
            // ★ P20（需求 3④）：玩家 / 旁观侧的「需我同意」弹窗是**唯一**通道
            //   （dock 的 `gpStatus` 状态卡片已按 D6 删除，折叠档 / 大厅的卡片
            //   不是游戏内主视图），而 `_seen` 在弹出前（:442）就已记账 ⇒
            //   屏障可关会让玩家点一下外面就把这条请求**永久丢掉**
            //   （不会再弹、卡片也没了，只剩「重新进页面」一条路）。
            //   因此 consent 类强制二选一；KP 的 confirm 类保持可关闭
            //   （KP 侧仍有 `gpStatus` 卡片兜底，关掉弹窗是他的自由）。
            //   `barrierDismissible == false` 时 Flutter 要求 barrierLabel 非空，
            //   下一行的 `'推送要求'` 已满足。
            barrierDismissible: r.reply == RoomPushReply.confirm,
            barrierLabel: '推送要求',
            transitionDuration: const Duration(milliseconds: 150),
            pageBuilder: (BuildContext ctx, Animation<double> _,
                    Animation<double> _) =>
                SafeArea(
                  child: Center(
                    child: Dialog(
                      insetPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      child: _body(ctx, r),
                    ),
                  ),
                ),
          );
        } catch (e, st) {
          // 不吞：走 FlutterError 上报（debug 会打成红字 / 测试里进
          // `takeException`），但**不中断**后面的排队项。
          FlutterError.reportError(FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'room_request_watcher',
            context: ErrorDescription('弹推送要求弹窗失败：${r.title}'),
          ));
        }
      }
    } finally {
      _draining = false;
      if (mounted && _queue.isNotEmpty) _schedule();
    }
  }

  Widget _body(BuildContext ctx, RoomPushRequest r) {
    final theme = Theme.of(ctx);
    // 窄屏（如 320dp）不溢出：宽度取「可用宽」与 340 的较小值，
    // 高度上限 440 且内部可滚动；不写死 340 造成 RenderFlex 溢出。
    return LayoutBuilder(
      builder: (BuildContext c, BoxConstraints box) {
        final double maxW = box.maxWidth.isFinite
            ? box.maxWidth.clamp(0.0, 340.0).toDouble()
            : 340.0;
        return Container(
          key: RoomPushKeys.root,
          width: maxW,
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: 440),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('推送要求', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(r.title,
                    key: RoomPushKeys.title,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Column(
                  key: RoomPushKeys.details,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final d in r.details)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(d, style: theme.textTheme.bodySmall),
                      ),
                    if (r.details.isEmpty)
                      Text('（无附加说明）', style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    RoomTap(
                      key: RoomPushKeys.reject,
                      label: '拒绝',
                      icon: Icons.close,
                      hint: '拒绝这条推送要求',
                      minSize: const Size(72, 40),
                      onTap: () => unawaited(_reply(ctx, r, false)),
                    ),
                    const SizedBox(width: 8),
                    RoomTap(
                      key: RoomPushKeys.agree,
                      label: '同意',
                      icon: Icons.check,
                      hint: '同意这条推送要求',
                      minSize: const Size(72, 40),
                      onTap: () => unawaited(_reply(ctx, r, true)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 点「同意 / 拒绝」→ 发对应 intent 并关弹窗；不弹假成功提示。
  ///
  /// ★ P12 PL-1c：仅当该 pending 是「目标为可见怪的 auto 对抗」且点同意时，
  ///   先弹第二段「输入怪物技能点数」窗。取消 = 不发 confirm、不结算、
  ///   pending 保留（原推送弹窗不关，可再次点同意重触发）；确定后发
  ///   `RoomIntent.confirm` 带可选 `value`（1–100 int），走 T02 的
  ///   `confirmPending` 合并到 `defender.value`。
  ///   其余 pending 一律走原路径零回归（`_seen` / `_queued` / `_drain`
  ///   去重语义与 `payload:{op,by}` 契约都不变）。
  ///
  /// ★ P13（本批）：玩家发起的攻击对抗（`p.attack==true` 且
  ///   `defender.side=='monster'`）改走新时序 —— KP 同意后**先弹防守方式**
  ///   （反击 / 闪避 / 不防御），counter/dodge 再弹检定值窗、none 不补值；
  ///   取消任一窗都不发 confirm、原推送弹窗常驻、pending 保留可重触发。
  ///   最终 confirm 载荷在既有 `{op,by,agree}` 上加 `reaction` 与可选 `value`。
  Future<void> _reply(BuildContext ctx, RoomPushRequest r, bool agree) async {
    final op = r.reply == RoomPushReply.confirm
        ? RoomIntent.confirm
        : RoomIntent.consent;
    final src = r.source;
    final def = asMap(src['defender']);

    // ★ P13：玩家攻击对抗优先识别（它也带 auto:true，会与下面的 monsterAuto
    //   重合，故必须先判、先返回），由 KP 同意后选防守方式。
    final bool playerAttack = agree &&
        r.reply == RoomPushReply.confirm &&
        src['attack'] == true &&
        roomText(def['side']) == 'monster';
    if (playerAttack) {
      await _replyPlayerAttack(ctx, r, op, def);
      return;
    }

    final bool monsterAuto = agree &&
        r.reply == RoomPushReply.confirm &&
        src['auto'] == true &&
        roomText(def['side']) == 'monster';
    if (!monsterAuto) {
      _controller?.sendIntent(
        op,
        <String, Object?>{...r.payload, 'agree': agree},
      );
      Navigator.of(ctx).pop();
      return;
    }
    final MonsterValueResult? mv = await showMonsterValueSheet(
      context: ctx,
      actorId: roomText(def['actorId']),
    );
    // 取消 / 点外部 / 返回键：零副作用，原推送弹窗常驻，pending 保留。
    if (mv == null) return;
    _controller?.sendIntent(
      op,
      <String, Object?>{
        ...r.payload,
        'agree': true,
        'value': mv.value,
      },
    );
    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  /// ★ P13：玩家攻击对抗的 KP 同意链路。
  ///
  /// ① 先弹防守方式选择窗（counter / dodge / none）；
  /// ② counter/dodge 再弹 1–100 检定值窗；none 不补值；
  /// ③ 发 `RoomIntent.confirm`，载荷 `{op,by,agree:true,reaction,value?,damage?}`；
  /// ④ 任一窗取消：零副作用返回，原推送弹窗常驻、pending 保留可重触发。
  ///
  /// ★ P20（需求 1）：反击（`counter`）时第二段窗**多要一个「反击伤害骰式」**，
  ///   结果随 confirm 载荷的**顶层可选键** `damage` 一起上来
  ///   （`reaction` / `value` 同款写法），由 `confirmPending` 合并进
  ///   `defender.damage` 再交给 `opposedAttackResolve`。
  ///   ⚠️ [RoomPushRequest.payload] 仍严格是 `{op, by}` —— domain 的
  ///   `confirmPending` 按 op+by 定位待办，给 `r.payload` 加字段会让确认链路
  ///   对不上（见 [collectRoomPushRequests] 里 pending 分支的硬约束注释），
  ///   所以只在本方法新建的载荷 Map 里追加键。
  Future<void> _replyPlayerAttack(
    BuildContext ctx,
    RoomPushRequest r,
    String op,
    Map<String, Object?> def,
  ) async {
    final String? reaction = await _showReactionSheet(ctx);
    // 取消防守方式窗：不发 confirm、不结算，原推送弹窗不 pop。
    if (reaction == null) return;

    // ★ P20：只有反击才需要伤害骰式（闪避 / 不防御不造成伤害）。
    final bool needDamage = reaction == 'counter';
    MonsterValueResult? mv;
    if (reaction != 'none') {
      mv = await showMonsterValueSheet(
        context: ctx,
        actorId: roomText(def['actorId']),
        needCounterDamage: needDamage,
      );
      // 取消检定值窗：同样不发 confirm、原推送弹窗不 pop。
      if (mv == null) return;
    }
    final int? value = mv?.value;
    // 反击伤害骰式：弹层留空时 `_damageExpr()` 已兜底 `1D3`（裁定 D2）；
    // 这里再兜一层 —— 保证 counter 一定带出**非空**骰式，否则 domain 会走
    // 「非 declared 且无伤害式」的老回退（拿攻击方玩家武器伤害去打玩家）。
    final String rawDmg = (mv?.damage ?? '').trim();
    final String damage =
        needDamage ? (rawDmg.isEmpty ? '1D3' : rawDmg) : '';

    _controller?.sendIntent(
      op,
      <String, Object?>{
        ...r.payload,
        'agree': true,
        'reaction': reaction,
        if (value != null) 'value': value,
        if (damage.isNotEmpty) 'damage': damage,
      },
    );
    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  /// 弹「防守方式」选择窗，返回 counter / dodge / none；取消返回 null。
  Future<String?> _showReactionSheet(BuildContext ctx) {
    return showRoomSheet<String>(
      context: ctx,
      title: '选择防守方式',
      body: (BuildContext _) => const ReactionChoiceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ★ P13：KP 同意后「防守方式」选择窗主体（独立 ValueKey 见
///   [RoomReactionKeys]，纯选择、零权威写入）。
class ReactionChoiceSheet extends StatefulWidget {
  const ReactionChoiceSheet({super.key});

  @override
  State<ReactionChoiceSheet> createState() => _ReactionChoiceSheetState();
}

class _ReactionChoiceSheetState extends State<ReactionChoiceSheet> {
  /// 默认选反击；KP 可改选闪避 / 不防御。三值之一，绝无第四种。
  String _reaction = 'counter';

  Widget _option(String value, String label, Key key) => RoomTap(
        key: key,
        label: label,
        icon: _reaction == value
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        hint: '选择$label',
        onTap: () => setState(() => _reaction = value),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: RoomReactionKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('防守方如何防守？确定后由系统结算对抗结果。',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _option('counter', '反击', RoomReactionKeys.counter),
            _option('dodge', '闪避', RoomReactionKeys.dodge),
            _option('none', '不防御', RoomReactionKeys.none),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: RoomTap(
            key: RoomReactionKeys.confirm,
            label: '确定',
            icon: Icons.check,
            hint: '确定防守方式',
            minSize: const Size(72, 40),
            onTap: () => Navigator.of(context).pop(_reaction),
          ),
        ),
      ],
    );
  }
}
