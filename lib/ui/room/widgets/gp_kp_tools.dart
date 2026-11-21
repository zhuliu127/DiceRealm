// ============================================================
// widgets/gp_kp_tools.dart — 块 3：KP 工具窄栏（设计 §5 T04 / S4.1）
//
// 只做「工具态 + 发意图」两件事：
//   · 标记 / 画笔 / 橡皮 / 6 色 / 放置单位 / 放置玩家 / 清除（二次确认）；
//   · 素材公开切换 / 删除 / 上传走 `asset.*` 三条 action。
//
// ★ P16 KP-10：本栏**不再**渲染「增加怪物」内联表单 / 加怪按钮 / 候选列表，
//   也**不再**保留「上传素材」按钮 —— 两者都已在左窄栏
//   （`gp_kp_left.dart` 的「NPC·怪物」/「素材」tab）有唯一入口。
//   `GpKpToolsKeys` 里对应的 key 常量全部保留，避免既有测试编译断裂。
// ★ P16 KP-11：「放单位 / 放玩家」不再隐式取「第一个候选 / 第二个座位」，
//   改为先弹 `showUnitPicker` 让 KP 明确选一个，再进舞台待放态。
// ★ 加怪 `addLocalActor` 仍是**纯本地**：只进 `RoomUiLocal.pendingActors`，
//   绝不发任何包（候选池随开战才送）；P16 KP-8 起多接一个 `armor`。
//
// ★ 橡皮口径（P1-03）：手势期间只做**段级删除**的本地演算，
//   手势末尾才调用一次 [KpEraser.finish] → 一条 `map.strokes.set`（全量）。
//   本文件提供纯逻辑类 [KpEraser]，舞台（另一并行批次）按同一签名复用；
//   这样「一次提交」不是靠注释约定，而是靠类里唯一的 commit 出口。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap;
import '../room_scope.dart';
import '../room_theme.dart';
import '../room_ui_local.dart' show RoomToolMode, RoomUiLocal;
import '../view/scene_view.dart'
    show NormPoint, eraseStrokeSegments, strokesOf;
import 'room_button_size.dart'
    show RoomBtnSize, RoomTapTile, clampBtnText, roomTapWrap2;
import 'room_panel_kit.dart'
    show ConfirmTwice, MapStageController, SectionBox;
import 'unit_picker.dart' show RoomUnitOption, showUnitPicker;
import '../room_text.dart';

// ------------------------------------------------------------
// 稳定 key
// ------------------------------------------------------------

/// 工具窄栏内部稳定 key（容器 key 由页面挂在槽位上）。
class GpKpToolsKeys {
  const GpKpToolsKeys._();

  // ★ 与页面槽位 key（RoomKeys.gpKpTools）区分开（同 GpKpLeft 的理由）。
  static const Key root = ValueKey<String>('gpKpTools/root');

  /// ★ P16 KP-10 后本栏不再有「加怪」入口（改走左窄栏的加怪弹层），
  ///   以下 8 个 key（表单 5 项 + 类型 chip 2 项 + 加怪按钮）**不再有 UI
  ///   使用点**，常量保留给测试/兼容（删了会让既有测试编译失败）。
  static const Key actorName = ValueKey<String>('gpKpTools/actorName');
  static const Key addActor = ValueKey<String>('gpKpTools/addActor');
  static const Key mark = ValueKey<String>('gpKpTools/mark');
  static const Key draw = ValueKey<String>('gpKpTools/draw');
  static const Key erase = ValueKey<String>('gpKpTools/erase');
  static const Key placeActor = ValueKey<String>('gpKpTools/placeActor');
  static const Key placePlayer = ValueKey<String>('gpKpTools/placePlayer');

  /// ★ P16 KP-10 后「上传素材」只留在左窄栏素材 tab，本 key 无 UI 使用点。
  static const Key upload = ValueKey<String>('gpKpTools/upload');
  static const Key clear = ValueKey<String>('gpKpTools/clear');
  static const Key colors = ValueKey<String>('gpKpTools/colors');

  /// ★ P12 KP-2b：「拖动素材」按钮的独立 Key。
  /// 全屏页窄栏用的是 `GpMapStageKeys.panTool`，两者字面量不同，
  /// 避免 `find.byKey` 在同一棵树里误伤 / `findsNWidgets(2)`。
  static const Key panTool = ValueKey<String>('gpKpTools/panTool');

  /// 第 [i] 个画笔色。
  static Key color(int i) => ValueKey<String>('gpKpTools/color/$i');

  // ★ P10 第 7 期 B：加怪 / NPC 内联小表单的稳定 key（老 APP 2.13.13 只有
  //   name / kind / dex / hp / actionsPerRound 五项，见 _p10_t7_research.md A2）。
  // ★ P16 KP-10：本组 key 不再有 UI 使用点，常量保留给测试/兼容。
  static const Key actorDex = ValueKey<String>('gpKpTools/actorDex');
  static const Key actorHp = ValueKey<String>('gpKpTools/actorHp');
  static const Key actorActions = ValueKey<String>('gpKpTools/actorActions');
  static const Key actorKind = ValueKey<String>('gpKpTools/actorKind');
  static const Key actorKindMonster =
      ValueKey<String>('gpKpTools/actorKind/monster');
  static const Key actorKindNpc = ValueKey<String>('gpKpTools/actorKind/npc');

  /// ★ P10 第 7 期：素材列表的公开切换 / 删除已从本栏**撤除渲染**
  ///   （统一收进左窄栏「素材」tab）。常量保留、不代表还有 UI 在用。
  static Key reveal(String id) => ValueKey<String>('gpKpTools/asset/reveal/$id');
  static Key delete(String id) => ValueKey<String>('gpKpTools/asset/del/$id');
}

// ------------------------------------------------------------
// 共享：加怪 / NPC 内联小表单（**已不在 UI 中使用**，保留给测试 / 兼容）
//
// ★ 老 APP 2.13.13 口径（_p10_t7_research.md A2）：**只有**
//   name / kind(怪物|NPC 二选一) / dex(默认 50) / hp(默认 10，同时写 hpMax) /
//   actionsPerRound(默认 1，静默夹 1–10)。明确没有 DB / 格斗 /
//   闪避 / MOV / 单独 HP 上限 / 怪物库 / 数值越界提示。
// ★ 非法输入走 int.tryParse ?? 默认值静默回落，不弹错；越界只静默夹取
//   （夹取在 addLocalActor 函数体里）。
// ★ P16 KP-7 / KP-8：加怪改走 `sheets/sheet_add_actor.dart` 的弹层，
//   本文件这套内联控件**三个类不再有任何 UI 使用点**。类定义一律保留
//   （既有测试 import 了 `ActorFieldKeys` / `ActorFields`，删了会让整个测试
//   套件编译失败）；KP-8 起补上第六个字段「护甲」以保持与弹层同口径。
// ------------------------------------------------------------

/// 表单里每个控件的稳定 key（两个窄栏各传一套自己的 key）。
class ActorFieldKeys {
  const ActorFieldKeys({
    required this.name,
    required this.kindRow,
    required this.kindMonster,
    required this.kindNpc,
    required this.dex,
    required this.hp,
    required this.actions,
    this.armor = const ValueKey<String>('actorField/armor'),
  });

  final Key name;
  final Key kindRow;
  final Key kindMonster;
  final Key kindNpc;
  final Key dex;
  final Key hp;
  final Key actions;

  /// ★ P16 KP-8：护甲（第六字段）。可选具名参数 + 默认 key，老调用点无需改。
  final Key armor;
}

/// 加怪表单草稿 + 提交取值。
///
/// 由父组件持有并 dispose；[ActorFields] 只负责画与回写 kind，
/// 点「加怪」时父组件从这里把 4 个值一起传给 [addLocalActor]。
class ActorFieldsController {
  ActorFieldsController({String name = '怪物'})
      : nameCtrl = TextEditingController(text: name);

  final TextEditingController nameCtrl;
  final TextEditingController dexCtrl = TextEditingController(text: '50');
  final TextEditingController hpCtrl = TextEditingController(text: '10');
  final TextEditingController actionsCtrl = TextEditingController(text: '1');

  /// ★ P16 KP-8：护甲，默认 0（COC7th：战斗检定按 max(0, 伤害 − 护甲) 结算）。
  final TextEditingController armorCtrl = TextEditingController(text: '0');

  /// `'monster'` 或 `'npc'`。
  String kind = 'monster';

  void selectKind(String k) => kind = k == 'npc' ? 'npc' : 'monster';

  String get nameValue => nameCtrl.text;
  String get kindValue => kind == 'npc' ? 'npc' : 'monster';

  int get dexValue => int.tryParse(dexCtrl.text.trim()) ?? 50;
  int get hpValue => int.tryParse(hpCtrl.text.trim()) ?? 10;
  int get actionsValue => int.tryParse(actionsCtrl.text.trim()) ?? 1;

  /// 非法输入回落 0，负值夹到 0（与 `sheet_add_actor.dart` 同口径）。
  int get armorValue {
    final raw = int.tryParse(armorCtrl.text.trim()) ?? 0;
    return raw < 0 ? 0 : raw;
  }

  void dispose() {
    nameCtrl.dispose();
    dexCtrl.dispose();
    hpCtrl.dispose();
    actionsCtrl.dispose();
    armorCtrl.dispose();
  }
}

/// 候选行的字段展示（两个窄栏共用，避免两套文本漂移）。
///
/// `名称（kind） · DEX n · HP n`，`actionsPerRound > 1` 时再追加
/// `· 每轮 k 次`（老 APP ui/room-panels.js:4112-4130 口径）。
String actorSummaryText(Map<String, Object?> actor) {
  final name = roomText(actor['name']);
  final kind = roomText(actor['kind']);
  final dex = roomText(actor['dex']);
  final hp = roomText(actor['hp']);
  final ap = int.tryParse(roomText(actor['actionsPerRound'])) ?? 1;
  final buf = StringBuffer('$name（$kind） · DEX $dex · HP $hp');
  if (ap > 1) buf.write(' · 每轮 $ap 次');
  return buf.toString();
}

/// 内联小表单：名称 / 类型 / DEX / HP / 每轮行动次数。
///
/// 窄栏里用 [Wrap] 自动换行，不新增弹层；类型用两个 ChoiceChip。
/// 组件本身**不**挂「加怪」按钮：按钮归父组件（T-30：它的 `enabled`
/// 必须恰好恒等 `gate.can('combat.start')`，不许叠加任何表单前置条件）。
class ActorFields extends StatefulWidget {
  const ActorFields({
    super.key,
    required this.controller,
    required this.keys,
  });

  final ActorFieldsController controller;
  final ActorFieldKeys keys;

  @override
  State<ActorFields> createState() => _ActorFieldsState();
}

class _ActorFieldsState extends State<ActorFields> {
  void _selectKind(String kind) {
    if (widget.controller.kind == kind) return;
    setState(() => widget.controller.selectKind(kind));
  }

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    double width = 60,
  }) {
    // ★ 固定宽 + 放大字号 = RenderFlex overflow。只钳**这一个控件子树**
    //   （1.3/1.5/2.0 三档都不溢出），不抬到页面 / Theme 层。
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: SizedBox(
        width: width,
        child: TextField(
          key: key,
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, isDense: true),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final k = widget.keys;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.0,
          child: SizedBox(
            width: 92,
            child: TextField(
              key: k.name,
              controller: c.nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        Wrap(
          key: k.kindRow,
          spacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ChoiceChip(
              key: k.kindMonster,
              label: const Text('怪物', style: TextStyle(fontSize: 11)),
              selected: c.kind == 'monster',
              onSelected: (_) => _selectKind('monster'),
            ),
            ChoiceChip(
              key: k.kindNpc,
              label: const Text('NPC', style: TextStyle(fontSize: 11)),
              selected: c.kind == 'npc',
              onSelected: (_) => _selectKind('npc'),
            ),
          ],
        ),
        _numberField(key: k.dex, controller: c.dexCtrl, label: 'DEX'),
        _numberField(key: k.hp, controller: c.hpCtrl, label: 'HP'),
        _numberField(
          key: k.actions,
          controller: c.actionsCtrl,
          label: '每轮',
          width: 68,
        ),
        // ★ P16 KP-8：护甲（默认 0，<0 夹 0）。提示写在下方一行小字里，
        //   不塞进 InputDecoration.helperText —— 定宽输入框里 helperText 会
        //   把整行高度抬高一档，改变既有表单的排版。
        _numberField(
          key: k.armor,
          controller: c.armorCtrl,
          label: '护甲',
          width: 68,
        ),
        const Text(
          'COC7th：战斗检定按 max(0, 伤害 − 护甲) 结算',
          style: TextStyle(fontSize: 10),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// 纯逻辑：本地加怪 + 橡皮一次提交
// ------------------------------------------------------------

String _nextLocalActorId(List<Map<String, Object?>> rows) {
  var max = 0;
  for (final r in rows) {
    final raw = roomText(r['id']);
    final n = int.tryParse(raw.startsWith('la') ? raw.substring(2) : raw) ?? 0;
    if (n > max) max = n;
  }
  return 'la${max + 1}';
}

/// ★ 本地加怪：只写 `RoomUiLocal.pendingActors`，**不发包**。
///
/// 返回新建的候选记录（调用方可继续用它做「放置单位」的目标）。
/// `setTool` 在这里只用来触发一次局部重建，模式本身不变。
///
/// ★ P16 KP-8：新增可选具名参数 `armor`（默认 0，负值夹 0），写进返回记录。
///   其余键的取值口径一字未改（`id`/`name`/`kind`/`hp`/`hpMax`/`dex`/
///   `actionsPerRound`）；`armor` 追加在 `actionsPerRound` 之后。
Map<String, Object?> addLocalActor(
  RoomUiLocal local, {
  required String name,
  String kind = 'monster',
  num hp = 10,
  num dex = 50,
  int actionsPerRound = 1,
  int armor = 0,
  bool visibleToPlayers = false,
}) {
  final trimmed = name.trim();
  final rec = <String, Object?>{
    'id': _nextLocalActorId(local.pendingActors),
    'name': trimmed.isEmpty ? '单位' : trimmed,
    'kind': kind == 'npc' ? 'npc' : 'monster',
    'hp': hp,
    'hpMax': hp,
    'dex': dex,
    'actionsPerRound': actionsPerRound < 1
        ? 1
        : (actionsPerRound > 10 ? 10 : actionsPerRound),
    'armor': armor < 0 ? 0 : armor,
    // ★ P12 PL-1a：默认 false（防泄露）。总是写这一键，让候选池在
    //   任一入口加入后都带显式可见性标记 —— 权威端 `makeSync`
    //   的 `_visibleActorsView()` 靠「显式带键」判断要不要下发 actors。
    //   与 `sheet_add_actor._payload()` 的第 7 字段同口径。
    'visibleToPlayers': visibleToPlayers,
  };
  local.pendingActors.add(rec);
  local.setTool(local.toolMode);
  return rec;
}

/// 橡皮的一次提交会话。
///
/// [begin] 起手拷一份笔迹快照；[move] 每次只做段级删除的本地演算，
/// 不产生任何发送；[finish] 是**唯一**的提交出口，只发一次全量载荷。
class KpEraser {
  KpEraser({
    required this.commit,
    this.tolerance = 0.02,
  });

  /// 手势末尾调一次：入参是段级删除后的全量笔迹。
  final Future<void> Function(List<Map<String, Object?>> strokes) commit;

  /// 命中容差（归一化坐标），与 `view/scene_view.dart` 的纯函数同口径。
  final double tolerance;

  List<Map<String, Object?>>? _working;

  /// 已提交次数（测试据此断言「恰好一次」）。
  int commits = 0;

  bool get active => _working != null;

  /// 手势起手：拷贝当前笔迹，绝不修改权威快照。
  void begin(List<Map<String, Object?>> strokes) {
    _working = <Map<String, Object?>>[
      for (final s in strokes) <String, Object?>{...s},
    ];
  }

  /// 手势经过一个点：段级删除，无发送。
  void move(NormPoint p) {
    final current = _working;
    if (current == null) return;
    _working = eraseStrokeSegments(
      current,
      <NormPoint>[p],
      tol: tolerance,
    );
  }

  /// 手势末尾：一次 `map.strokes.set`（全量），随后本会话失效。
  Future<void> finish() async {
    final current = _working;
    if (current == null) return;
    _working = null;
    commits += 1;
    await commit(current);
  }

  /// 取消手势：丢弃本地演算，不提交。
  void cancel() => _working = null;
}

// ------------------------------------------------------------
// 块 3
// ------------------------------------------------------------

/// KP 工具窄栏。
///
/// [stage] 是素材舞台的控制面（§3.9），由接线方注入；不注入时按钮
/// 仍然能改本地工具态，便于独立 pump 验收。
/// [eraser] 可注入以观察提交载荷；不注入时自动绑定到当前会话控制器。
class GpKpTools extends StatefulWidget {
  const GpKpTools({
    super.key,
    this.stage,
    this.eraser,
    this.onActorAdded,
  });

  final MapStageController? stage;
  final KpEraser? eraser;

  /// ★ P16 KP-10：本栏**不再**加怪（改由左窄栏的加怪弹层入口），
  ///   这个回调不再有 UI 触发点。参数保留给测试 / 兼容。
  final void Function(Map<String, Object?> actor)? onActorAdded;

  @override
  State<GpKpTools> createState() => _GpKpToolsState();
}

class _GpKpToolsState extends State<GpKpTools> {
  KpEraser? _ownedEraser;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.eraser == null && _ownedEraser == null) {
      final ctl = RoomScope.read(context).controller;
      _ownedEraser = KpEraser(
        commit: (List<Map<String, Object?>> strokes) => ctl.hostAction(
          'map.strokes.set',
          <String, Object?>{'strokes': strokes},
        ),
      );
    }
  }

  KpEraser get eraser => widget.eraser ?? _ownedEraser!;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;
    final local = scope.local;
    final session = scope.session;

    return ListenableBuilder(
      listenable: local,
      builder: (BuildContext ctx, Widget? _) {
        return SectionBox(
          key: GpKpToolsKeys.root,
          title: '工具窄栏',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- 工具模式 ----
              // ★ P16 KP-10：本栏原有的「增加怪物」整块（内联表单 + 加怪按钮 +
              //   候选单位展示）已删除 —— 左窄栏「NPC·怪物」tab 是同一功能的
              //   唯一入口（P16 起走加怪弹层）。
              // ★ P16：5 个工具按钮统一 90×48 并排成 **2 列网格**
              //   （`roomTapWrap2`：`Wrap` + 定宽 tile，栏宽不足自动掉 1 列）。
              //   3 列要 `3×90+8 = 278`，[下限] 格宽 212 装不下 → 只能 2 列。
              //   `ConfirmTwice` 保持**默认尺寸**（它是「特殊」的那一个：
              //   按下后文案从 4 字变 6 字，宽 86↔112，本批不加 minSize）。
              roomTapWrap2(<Widget>[
                RoomTapTile(
                  roomKey: GpKpToolsKeys.mark,
                  size: RoomBtnSize.toolsTile,
                  label: '标点',
                  icon: Icons.place,
                  enabled: gate.can('map.mark'),
                  hint: '下一次点击落标点',
                  onTap: () {
                    widget.stage?.beginMark(kind: 'dot', label: '标记');
                    local.setTool(RoomToolMode.mark, icon: 'mark');
                  },
                ),
                RoomTapTile(
                  roomKey: GpKpToolsKeys.draw,
                  size: RoomBtnSize.toolsTile,
                  label: '画笔',
                  icon: Icons.brush,
                  enabled: gate.can('map.stroke'),
                  hint: '画笔模式',
                  onTap: () => _enterDraw(local),
                ),
                RoomTapTile(
                  roomKey: GpKpToolsKeys.erase,
                  size: RoomBtnSize.toolsTile,
                  label: '橡皮',
                  icon: Icons.backspace,
                  enabled: gate.can('map.strokes.set'),
                  hint: '段级擦除，手势末尾一次提交',
                  onTap: () {
                    widget.stage?.beginErase();
                    eraser.begin(strokesOf(session.state));
                    local.setTool(RoomToolMode.erase, icon: 'erase');
                  },
                ),
                RoomTapTile(
                  roomKey: GpKpToolsKeys.placeActor,
                  size: RoomBtnSize.toolsTile,
                  label: '放单位',
                  icon: Icons.person_pin,
                  enabled: gate.can('map.mark'),
                  hint: '先选单位，再点舞台落点',
                  // ★ P16 KP-11：不再隐式取「第一个候选」，先让 KP 明确选一个。
                  onTap: () async {
                    final RoomUnitOption? opt =
                        await showUnitPicker(ctx, title: '选择要放置的单位');
                    if (opt == null || !mounted) return;
                    final String name =
                        _unitDisplayName(session.state, local, opt);
                    local.setPendingActorName(name);
                    widget.stage?.beginPlace(actorName: name);
                    local.setTool(RoomToolMode.placeActor, icon: 'placeActor');
                  },
                ),
                // ★ P12 KP-2a：「放玩家」按钮删除（R9：`GpKpToolsKeys.placePlayer`
                //   常量与 `RoomToolMode.placePlayer` 枚举成员一律保留，
                //   删符号会让既有测试编译期假红）。
                // ★ P12 KP-2b：原位置新增「拖动素材」。激活态由只读 getter
                //   `local.panArmed` 派生（互斥工具态单一真源），严禁写
                //   `local.panArmed = true`。只读写本机态，不产生任何
                //   hostAction / SendPlan / RoomEvt，不同步玩家侧。
                RoomTapTile(
                  roomKey: GpKpToolsKeys.panTool,
                  size: RoomBtnSize.toolsTile,
                  label: '拖动素材',
                  icon: local.panArmed ? Icons.pan_tool : Icons.open_with,
                  enabled: gate.can('map.mark'),
                  hint: local.panArmed
                      ? '拖动素材已激活，再点一次取消（仅本机显示）'
                      : '拖动素材（仅本机显示，不与玩家同步）',
                  onTap: () => local.setTool(
                    local.panArmed ? RoomToolMode.none : RoomToolMode.pan,
                  ),
                ),
                // ★ P12 KP-2c：「清除笔迹」→「清除标记」。domain 的
                //   `map.clear{strokesOnly:false}` 已精确等价于「清
                //   scene.strokes + scene.marks、不动 scene.assets」；
                //   二次确认文案明确列三类（笔迹 / 标点 / 单位标记），
                //   不含素材图。
                ConfirmTwice(
                  key: GpKpToolsKeys.clear,
                  label: '清除标记',
                  confirmLabel: '再点：笔迹+标点+单位标记',
                  onConfirmed: () => ctl.hostAction(
                    'map.clear',
                    const <String, Object?>{'strokesOnly': false},
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              // ---- 画笔 6 色（索引进 kDrawColors） ----
              // ★ 2.34.0 KP-2：标签「画笔颜色」独占一行；6 个 chip 用
              //   LayoutBuilder 按可用宽等分成「一行恰好 3 个」，从而把 Wrap
              //   钉死在 3+3 **固定 2 排**（不放任它自然长高），并补 runSpacing；
              //   排内定宽等高、整体对齐。
              // ★ 整组子树只钳文字缩放（clampBtnText 范式，见
              //   room_button_size.dart:144-153）：textScaler 1.3 / 1.5 / 2.0
              //   三档下标签与圆点都不放大、不截断、不溢出；禁 ClipRect 硬裁、
              //   禁抬到页面 / Theme 层。窄栏一屏可看全 6 色、无需滚动。
              // ★ 档位判定只看宽度（room_game_page.dart 的 tooNarrow），
              //   这里只增加一行高度，不触发 dock / folded 翻档。
              clampBtnText(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text('画笔颜色', style: TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    LayoutBuilder(
                      builder: (BuildContext ctx, BoxConstraints c) {
                        // 一行恰好 3 个：3*w + 2*gap <= avail，且第 4 个必换行。
                        // -0.5 抵消浮点误差，保证第 3 个不会被挤到第二排。
                        final double avail =
                            c.hasBoundedWidth ? c.maxWidth : 240.0;
                        final double w =
                            (avail - 2 * RoomBtnSize.gap) / 3 - 0.5;
                        return Wrap(
                          key: GpKpToolsKeys.colors,
                          spacing: RoomBtnSize.gap,
                          runSpacing: RoomBtnSize.gap,
                          children: <Widget>[
                            for (var i = 0; i < kDrawColors.length; i++)
                              SizedBox(
                                // 防御极端窄约束下 w 为负（正常窄栏 w≈72）。
                                width: w > 16 ? w : 16,
                                height: 32,
                                child: ActionChip(
                                  key: GpKpToolsKeys.color(i),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  labelPadding: EdgeInsets.zero,
                                  label: Center(
                                    child: Text(
                                      '●',
                                      style: TextStyle(
                                        color:
                                            Color(RoomTheme.drawColorArgb(i)),
                                        fontSize: 18,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                  backgroundColor:
                                      local.toolColorIndex == i
                                          ? Theme.of(ctx)
                                              .colorScheme
                                              .primaryContainer
                                          : null,
                                  onPressed: () {
                                    local.setTool(RoomToolMode.draw,
                                        colorIndex: i);
                                    _enterDraw(local);
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              // ★ P16 KP-10：本栏「上传素材」按钮已删除 —— 左窄栏「素材」tab
              //   的上传入口是唯一入口（P16 起 `asset.add` 只从那里发）。
            ],
          ),
        );
      },
    );
  }

  /// ★ P16 KP-11：从选中项反推**纯单位名**（不带「（怪物）」这类类型后缀）。
  ///
  /// 舞台 `beginPlace(actorName:)` 落的标记文案就是这个名字，带后缀会画成
  /// 「哥布林（怪物）」这种不该出现在舞台上的文字。
  /// 查找顺序：本地候选池 → `state['actors']` → `combat.order` → 退回 label
  /// → 最后兜底 `'单位'`。
  String _unitDisplayName(
    Map<String, Object?> state,
    RoomUiLocal local,
    RoomUnitOption opt,
  ) {
    final String value = opt.value;
    if (value.startsWith('a:')) {
      final String id = value.substring(2);
      final List<List<Map<String, Object?>>> groups =
          <List<Map<String, Object?>>>[
        local.pendingActors,
        <Map<String, Object?>>[
          for (final Object? raw in asList(state['actors'])) asMap(raw),
        ],
        <Map<String, Object?>>[
          for (final Object? raw
              in asList(asMap(state['combat'])['order']))
            asMap(raw),
        ],
      ];
      for (final List<Map<String, Object?>> rows in groups) {
        for (final Map<String, Object?> rec in rows) {
          if (roomText(rec['id']) != id) continue;
          final String n = roomText(rec['name']);
          if (n.isNotEmpty) return n;
        }
      }
    }
    final String label = opt.label.trim();
    return label.isEmpty ? '单位' : label;
  }

  /// 进入画笔模式：颜色取当前本地色号，宽度固定 3（归一化笔迹不乘缩放）。
  void _enterDraw(RoomUiLocal local) {
    widget.stage?.beginStroke(
      color: RoomTheme.drawColor(local.toolColorIndex),
      width: 3,
    );
    local.setTool(RoomToolMode.draw, icon: 'draw');
  }
}
