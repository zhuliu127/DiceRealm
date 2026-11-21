// ============================================================
// sheets/sheet_add_actor.dart — 新增怪物 / NPC 弹层（P16 波1-A · KP-7 / KP-8）
//
// ★ 契约：openAddActorSheet(context) → Future<Map<String,Object?>?>，
//   确定返回 name/kind/dex/hp/actionsPerRound/**armor**/visibleToPlayers
//   七字段，取消返回 null。
//
// ★ 刻意**不 import** `gp_kp_tools.dart` 的 `ActorFields` 系列：那属于波2
//   独占文件（KP-8 会大改、KP-10 会删内联表单）。本弹层把需要的 7 个
//   字段在本文件内自绘，避免波1 并发期跨组 import 编译断裂；由波2 接线时
//   决定是否复用同一份草稿口径。
//
// ★ 字段口径对齐现有 addLocalActor / 老 APP addActorSheet：
//   name 空 → '单位'；kind 只认 monster/npc；hp 同值即 hpMax；
//   actionsPerRound 静默夹 1–10；armor 默认 0、夹 >= 0（KP-8 新增）。
//
// ★ 固定宽度字段用 MediaQuery.withClampedTextScaling(maxScaleFactor:1.0)
//   只包该字段子树，textScaler 1.3/1.5/2.0 下不溢出。
// ★ 只画、只返回草稿：零发包、零权威状态赋值、零 emoji、零 jsStr。
// ============================================================

import 'package:flutter/material.dart';

import '../widgets/room_button_size.dart' show clampBtnText;
import '../widgets/room_panel_kit.dart' show RoomTap;
import 'room_sheet.dart' show showRoomSheet;

/// 加怪弹层内部稳定 key。
class AddActorSheetKeys {
  const AddActorSheetKeys._();

  static const Key root = ValueKey<String>('addActorSheet');
  static const Key name = ValueKey<String>('addActorSheet/name');
  static const Key kindRow = ValueKey<String>('addActorSheet/kindRow');
  static const Key kindMonster =
      ValueKey<String>('addActorSheet/kind/monster');
  static const Key kindNpc = ValueKey<String>('addActorSheet/kind/npc');
  static const Key dex = ValueKey<String>('addActorSheet/dex');
  static const Key hp = ValueKey<String>('addActorSheet/hp');
  static const Key actions = ValueKey<String>('addActorSheet/actions');
  static const Key armor = ValueKey<String>('addActorSheet/armor');
  static const Key confirm = ValueKey<String>('addActorSheet/confirm');
  static const Key cancel = ValueKey<String>('addActorSheet/cancel');

  /// ★ P12 PL-1a：「是否显示给玩家」勾选（默认不勾，防泄露）。
  static const Key visibleToPlayers =
      ValueKey<String>('addActorSheet/visibleToPlayers');
}

/// ★ 契约：打开「新增怪物 / NPC」弹层。
///
/// 确定 → 返回六字段草稿 map；取消 / 点击外部 / 返回键 → 返回 null。
/// 本函数**只返回草稿**，不写 RoomUiLocal、不发包；入列表由调用方
/// （波2 接线的左栏入口）用返回的 map 决定走哪条 action。
Future<Map<String, Object?>?> openAddActorSheet(BuildContext context) {
  return showRoomSheet<Map<String, Object?>>(
    context: context,
    title: '新增怪物 / NPC',
    body: (BuildContext _) => const AddActorSheet(
      key: ValueKey<String>('addActorSheet/body'),
    ),
  );
}

/// 加怪弹层主体（七字段自绘）。
class AddActorSheet extends StatefulWidget {
  const AddActorSheet({super.key});

  @override
  State<AddActorSheet> createState() => _AddActorSheetState();
}

class _AddActorSheetState extends State<AddActorSheet> {
  final TextEditingController _name = TextEditingController(text: '怪物');
  final TextEditingController _dex = TextEditingController(text: '50');
  final TextEditingController _hp = TextEditingController(text: '10');
  final TextEditingController _actions = TextEditingController(text: '1');
  final TextEditingController _armor = TextEditingController(text: '0');

  /// `'monster'` 或 `'npc'`。
  String _kind = 'monster';

  /// ★ P12 PL-1a：默认不勾（防泄露）；只进草稿，不发包、不写权威 state。
  bool _visibleToPlayers = false;

  @override
  void dispose() {
    _name.dispose();
    _dex.dispose();
    _hp.dispose();
    _actions.dispose();
    _armor.dispose();
    super.dispose();
  }

  static int _int(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  /// 七字段草稿（键名即契约键名；前六键逐字不动）。
  Map<String, Object?> _payload() {
    final rawName = _name.text.trim();
    final hp = _int(_hp, 10);
    final ap = _int(_actions, 1);
    final armor = _int(_armor, 0);
    return <String, Object?>{
      'name': rawName.isEmpty ? '单位' : rawName,
      'kind': _kind == 'npc' ? 'npc' : 'monster',
      'dex': _int(_dex, 50),
      'hp': hp,
      'actionsPerRound': ap < 1 ? 1 : (ap > 10 ? 10 : ap),
      'armor': armor < 0 ? 0 : armor,
      // ★ P12 PL-1a：第 7 字段。既有 6 键逐字不动；
      //   与 `gp_kp_tools.addLocalActor` 的同名字段口径一致。
      'visibleToPlayers': _visibleToPlayers,
    };
  }

  /// 固定宽度数字框：clamp 文字缩放只包该控件子树。
  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    double width = 60,
  }) {
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
    return Column(
      key: AddActorSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            // 名称（固定宽度，同样 clamp）。
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: SizedBox(
                width: 92,
                child: TextField(
                  key: AddActorSheetKeys.name,
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            // 类型：怪物 / NPC。
            Wrap(
              key: AddActorSheetKeys.kindRow,
              spacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                ChoiceChip(
                  key: AddActorSheetKeys.kindMonster,
                  label: const Text('怪物', style: TextStyle(fontSize: 11)),
                  selected: _kind == 'monster',
                  onSelected: (_) => setState(() => _kind = 'monster'),
                ),
                ChoiceChip(
                  key: AddActorSheetKeys.kindNpc,
                  label: const Text('NPC', style: TextStyle(fontSize: 11)),
                  selected: _kind == 'npc',
                  onSelected: (_) => setState(() => _kind = 'npc'),
                ),
              ],
            ),
            _numberField(
                key: AddActorSheetKeys.dex,
                controller: _dex,
                label: 'DEX'),
            _numberField(
                key: AddActorSheetKeys.hp,
                controller: _hp,
                label: 'HP'),
            _numberField(
              key: AddActorSheetKeys.actions,
              controller: _actions,
              label: '每轮',
              width: 68,
            ),
            // KP-8：护甲（新增第六字段）。
            _numberField(
              key: AddActorSheetKeys.armor,
              controller: _armor,
              label: '护甲',
              width: 68,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ★ P12 PL-1a：是否显示给玩家（默认不勾）。只有勾了才会进入
        //   玩家裁剪态 `makeSync.actors` 视图；未勾选者完全不下发。
        //   独立 ValueKey，不挂 `act/` 锚点；clampBtnText 只包这棵子树。
        clampBtnText(
          Row(
            key: AddActorSheetKeys.visibleToPlayers,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                value: _visibleToPlayers,
                onChanged: (bool? v) =>
                    setState(() => _visibleToPlayers = v == true),
              ),
              const Text('是否显示给玩家', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // ★ P16 修复：「确定 / 取消」改成整行两个等宽大按钮。
        //
        //   改前是 `Wrap` + 两个裸 `RoomTap`：`RoomTap` 内部 `Align(widthFactor:1)`
        //   会按**内容**收紧，于是「确定」的可点宽度只有「✓ 确定」约 70dp，
        //   两按钮间距也只有 6dp；真机上按坐标点容易落到按钮之间的空隙，而
        //   弹层外的遮罩是 dismissible 的 —— 点偏一下整个弹层就关了，用户以为
        //   「点了没反应」。
        //
        //   改后 `Row` + 两个 `Expanded`：每个按钮吃满一半可用宽（热区翻倍），
        //   间距固定 8、高度 48（≥48dp 触控口径）。`Expanded` 给的是**紧宽**，
        //   `Align(widthFactor:1)` 在紧约束下不收缩 ⇒ 天然等宽填满。
        //   两个语义 key（confirm / cancel）原样挂在内部 `RoomTap` 上，测试与
        //   探针 `find.byKey(...)` 逐字不变。
        //   `clampBtnText` 把按钮子树文字钳到 1.0：定宽按钮在 1.3/1.5/2.0 三档
        //   系统字号下不会被撑破（不用 `ClipRect` 硬裁）。
        clampBtnText(
          Row(
            children: <Widget>[
              Expanded(
                child: RoomTap(
                  key: AddActorSheetKeys.confirm,
                  label: '确定',
                  icon: Icons.check,
                  minSize: const Size(96, 48),
                  hint: '按以上数值生成单位草稿',
                  onTap: () => Navigator.of(context)
                      .pop<Map<String, Object?>>(_payload()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RoomTap(
                  key: AddActorSheetKeys.cancel,
                  label: '取消',
                  icon: Icons.close,
                  minSize: const Size(96, 48),
                  hint: '放弃本次输入',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
        // 底部留白 4dp：按钮不贴着弹层下边缘，且不影响上面的字段几何。
        const SizedBox(height: 4),
      ],
    );
  }
}
