// ============================================================
// sheets/sheet_opposed.dart — 对抗全链路（P17 波3-B / KP-3 改造）
//
// 四条链路（老 APP `room-panels.js` / `room-model.js`）：
//   ① 通用对抗   `check.opposed {aSeat,aSkill,aBase,bSeat,bSkill,bBase}`
//   ② 攻击对抗   `check.opposed {attack:true, attacker, defender, weapon, armor}`
//   ③ 裁定申请   `check.opposed {reqId, attack:true, defender:{reaction,level,damage}}`
//   ④ 选伤害目标 `INTENT.opposed {phase:'target', targetId}`
//
// ★ P17 波3-B 口径（用户 Q2 拍板 + `_p17_oldapp_research.md` B1/B2/B3/B5）：
//   · 删掉自造的 `kind:'general'` 与裸 `base` —— 字段名逐字对齐老 APP；
//   · 「武器对抗」入口删除（`OpposedSheetKeys.weapon` 常量保留但不再渲染），
//     **但 `INTENT.OPPOSED` / domain `opposed()` 整条链路原样保留**（那就是
//     玩家战斗对抗本身），玩家侧只留「选伤害目标」这一个意图入口；
//   · 攻击方是玩家 → 下拉选**武器**，技能的检定值由权威端按武器的 `skill`
//     字段去人物卡取值（4 档归一 + 16 条别名已通，UI 不写任何反查）；
//   · 攻守双方都是无卡单位（怪物 / NPC）→ 各手输一项 **1–100 对抗值**
//     （甲 = 攻击技能点数、乙 = 反击 / 闪避技能点数，默认 50）；
//     防守方另选**反击 / 闪避**，反击再补**伤害骰式**（`2D6+D4+1`）。
//
// ★ 2.34.0 / KP-4（用户拍板 D1「数值优先、移除六档」）：
//   · **攻击对抗**不再渲染六档成功等级（删 `_levelRow('atk')`），乙方怪物
//     补 1–100 数值框 `OpposedSheetKeys.defenderBase`；
//   · `defender` 载荷改塞 `value`（契约 I3 冻结 `{side:'monster',
//     value:int 1..100, reaction, actorId}`，**不含 `level`**）；domain 的
//     `declared` 判定改「有 value 优先」，旧「只有 level」载荷仍走兜底；
//   · 六档常量 / `opposedLevelText` / `OpposedSheetKeys.level` / `_levelRow`
//     **全库 Grep 后刻意保留**：③「裁定待处理的对抗申请」UI（另一套
//     `RoomIntent.opposed` 状态机，本期 ★ 不动）仍在 `_levelRow('req')` 用。
//
// ★ 2.34.0 / PV-1b（契约 I11）：新增 `showPlayerOpposedRequestSheet<T>`，
//   玩家选对抗技能 + 目标，走 `RoomIntent.act` + `auto:true` + `RoomConfirm.kp`
//   审批链（与「申请治愈」同款）；技能值由权威端 `skillBaseOf(角色卡)` 读，
//   本弹层**不填技能点数**；不复用 ③ 的 KP 裁定 UI、不挂 `act/` 锚点。
//
// ★ 意图通道的 `opposed` 不经 POLICY（§7 K6），可点性用
//   [kpOpposedCanApply] 的「角色 + 战斗中 + 我的回合」显式布尔；
//   其余 ACT 入口的 enabled 恰好等于闸门结果（T-30 契约）。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用、零 emoji。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asList, asMap;
import '../../../domain/room_types.dart' show RoomIntent, RoomRole;
import '../room_keys.dart';
import '../room_scope.dart';
import '../room_text.dart' show roomText;
import '../view/combat_view.dart' show isMyTurn;
import '../view/room_view.dart' show isCombat, playersOf;
import '../widgets/room_button_size.dart' show clampBtnText;
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import '../widgets/unit_picker.dart'
    show kUnitAllValue, RoomUnitOption, UnitPickerField, unitValueToSeat;
import 'room_sheet.dart' show showRoomSheet;

/// 对抗弹层内部稳定 key。
class OpposedSheetKeys {
  const OpposedSheetKeys._();

  static const Key root = ValueKey<String>('opposedSheet');
  static const Key general = ValueKey<String>('opposedSheet/general');
  static const Key attack = ValueKey<String>('opposedSheet/attack');
  static const Key weapon = ValueKey<String>('opposedSheet/weapon');
  static const Key resolve = ValueKey<String>('opposedSheet/resolve');
  static const Key target = ValueKey<String>('opposedSheet/target');
  static const Key reqId = ValueKey<String>('opposedSheet/reqId');
  static const Key targetId = ValueKey<String>('opposedSheet/targetId');

  /// 无卡单位（怪物 / NPC）的 1–100 对抗值输入（KP-1 保留项）。
  static const Key reqBase = ValueKey<String>('opposedSheet/reqBase');
  static const Key targetBase = ValueKey<String>('opposedSheet/targetBase');

  // ---- P17 波3-B 新增：通用对抗甲乙两方 ----
  static const Key aSeat = ValueKey<String>('opposedSheet/aSeat');
  static const Key aSkill = ValueKey<String>('opposedSheet/aSkill');
  static const Key aBase = ValueKey<String>('opposedSheet/aBase');
  static const Key bSeat = ValueKey<String>('opposedSheet/bSeat');
  static const Key bSkill = ValueKey<String>('opposedSheet/bSkill');
  static const Key bBase = ValueKey<String>('opposedSheet/bBase');

  // ---- P17 波3-B 新增：攻击对抗 ----
  static const Key attacker = ValueKey<String>('opposedSheet/attacker');
  static const Key attackerWeapon =
      ValueKey<String>('opposedSheet/attackerWeapon');
  static const Key attackerSkill = ValueKey<String>('opposedSheet/attackerSkill');
  static const Key attackerBase = ValueKey<String>('opposedSheet/attackerBase');
  static const Key attackerDamage =
      ValueKey<String>('opposedSheet/attackerDamage');
  static const Key defender = ValueKey<String>('opposedSheet/defender');
  static const Key defenderSkill = ValueKey<String>('opposedSheet/defenderSkill');

  /// ★ KP-4（2.34.0）：防守方无卡单位的 1–100 对抗值（数值优先，取代六档）。
  static const Key defenderBase =
      ValueKey<String>('opposedSheet/defenderBase');
  static const Key counterDamage = ValueKey<String>('opposedSheet/counterDamage');
  static const Key armor = ValueKey<String>('opposedSheet/armor');

  // ---- P17 波3-B 新增：裁定申请的反击 / 闪避 + 等级 ----
  static const Key resolveCounterDamage =
      ValueKey<String>('opposedSheet/resolveCounterDamage');
  static const Key resolveArmor =
      ValueKey<String>('opposedSheet/resolveArmor');

  /// 防守方式二选一（`scope` = `atk` 攻击对抗 / `req` 裁定）。
  static Key reaction(String scope, String r) =>
      ValueKey<String>('opposedSheet/reaction/$scope/$r');

  /// 检定等级六档（`scope` = `atk` / `req`；`lv` = 5/4/3/2/0/-1）。
  static Key level(String scope, int lv) =>
      ValueKey<String>('opposedSheet/level/$scope/$lv');

  /// 武器下拉里的单个候选（`i` = 在人物卡武器列表里的下标）。
  static Key weaponOption(int i) =>
      ValueKey<String>('opposedSheet/weaponOption/$i');
}

/// 检定等级六档（与 `CocRules.LEVEL` 数值一一对应；UI 只发数字）。
///
/// ★ 2.34.0 / KP-4：**攻击对抗**已改「数值优先」不再渲染六档；但 ③
/// 「裁定待处理的对抗申请」UI（`_levelRow('req')`，另一套 `RoomIntent.opposed`
/// 状态机，本期 ★ 不动）仍在使用。全库 Grep 确认后本常量、
/// [opposedLevelText]、[OpposedSheetKeys.level] 三者**刻意保留**，不能删。
const List<int> kOpposedLevelValues = <int>[5, 4, 3, 2, 0, -1];

/// 等级数字 → 中文档位名（与 `CocRules.LEVEL_TEXT` 同文案）。
String opposedLevelText(int lv) {
  switch (lv) {
    case 5:
      return '大成功';
    case 4:
      return '极难成功';
    case 3:
      return '困难成功';
    case 2:
      return '常规成功';
    case 0:
      return '失败';
    case -1:
      return '大失败';
  }
  return '常规成功';
}

/// K6：`opposed` 意图的可点性 = 非旁观 + 战斗中 + 当前是我的回合。
bool kpOpposedCanApply({
  required Map<String, Object?> state,
  required String role,
  required String seat,
}) {
  return role != RoomRole.spectator &&
      isCombat(state) &&
      isMyTurn(state, seat);
}

/// 无卡单位（怪物 / NPC）没有人物卡 → 老 APP 口径：对抗值由 KP 手输 1–100。
bool _unitWithoutCard(RoomUnitOption? o) =>
    o != null && (o.kind == 'monster' || o.kind == 'npc');

/// 把输入夹到 1–100；空 / 非数字返回 null（不塞载荷）。
int? _parseBase(String text) {
  final n = int.tryParse(text.trim());
  if (n == null) return null;
  return n < 1 ? 1 : (n > 100 ? 100 : n);
}

/// 护甲值：0–99，空 / 非数字按 0（与老 APP `armor:{value}` 缺省一致）。
int _parseArmor(String text) {
  final n = int.tryParse(text.trim());
  if (n == null) return 0;
  return n < 0 ? 0 : (n > 99 ? 99 : n);
}

/// 对抗弹层。
class OpposedSheet extends StatefulWidget {
  const OpposedSheet({super.key});

  @override
  State<OpposedSheet> createState() => _OpposedSheetState();
}

class _OpposedSheetState extends State<OpposedSheet> {
  // ---- 通用对抗：甲乙双方 ----
  RoomUnitOption? _aUnit;
  RoomUnitOption? _bUnit;
  final TextEditingController _aSkill = TextEditingController(text: '格斗');
  final TextEditingController _bSkill = TextEditingController(text: '闪避');
  final TextEditingController _aBase = TextEditingController(text: '50');
  final TextEditingController _bBase = TextEditingController(text: '50');

  // ---- 攻击对抗：攻守双方 ----
  RoomUnitOption? _attUnit;
  RoomUnitOption? _defUnit;

  /// 攻击方是玩家时选中的武器（人物卡 `weapons` 里的一条真记录）。
  Map<String, Object?>? _weapon;
  final TextEditingController _attSkill = TextEditingController(text: '格斗');
  final TextEditingController _attBase = TextEditingController(text: '50');
  final TextEditingController _attDamage = TextEditingController(text: '1D6');
  final TextEditingController _defSkill = TextEditingController(text: '闪避');
  final TextEditingController _counterDamage =
      TextEditingController(text: '1D3');
  final TextEditingController _armor = TextEditingController(text: '0');

  /// ★ KP-4：防守方无卡单位的 1–100 对抗值（默认 50，与通用对抗一致）。
  final TextEditingController _defBase = TextEditingController(text: '50');

  /// 防守方式（`counter` 反击 / `dodge` 闪避）。老 APP 直发默认闪避。
  String _reaction = 'dodge';

  /// 防守方检定等级。★ KP-4 后攻击对抗改用数值（[_defBase]），本字段只剩
  /// `_levelRow('atk')` 的兜底路径；③ 裁定申请 UI 走 `_levelRow('req')` 用
  /// [_reqLevel]。保留是为了 `_levelRow` 的 atk 分支仍能编译，现已不再渲染。
  int _defLevel = 2;

  // ---- 裁定玩家申请 ----
  RoomUnitOption? _reqUnit;
  String _reqReaction = 'counter'; // 老 APP `opposedResolveSheet` 默认反击
  int _reqLevel = 2;
  final TextEditingController _reqCounterDamage =
      TextEditingController(text: '1D3');
  final TextEditingController _reqArmor = TextEditingController(text: '0');

  // ---- 选伤害目标 ----
  RoomUnitOption? _targetUnit;

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _aSkill,
      _bSkill,
      _aBase,
      _bBase,
      _attSkill,
      _attBase,
      _attDamage,
      _defSkill,
      _counterDamage,
      _armor,
      _defBase,
      _reqCounterDamage,
      _reqArmor,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 取某座位玩家的成员记录（用于读武器列表 / DB）。
  static Map<String, Object?>? _memberOf(
    Map<String, Object?> state,
    String seat,
  ) {
    for (final m in playersOf(state)) {
      if (roomText(m['seat']) == seat) return m;
    }
    return null;
  }

  /// 人物卡武器列表（老 APP `mem.sheet.weapons`）。
  static List<Map<String, Object?>> _weaponsOf(
    Map<String, Object?> state,
    String seat,
  ) {
    final mem = _memberOf(state, seat);
    if (mem == null) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final w in asList(asMap(mem['sheet'])['weapons'])) asMap(w),
    ];
  }

  /// 统一枚举 value → 裸 seat / 裸 actorId（domain 侧只认裸值）。
  static String _bareSeat(String value) => unitValueToSeat(value);

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;
    final session = scope.session;
    final state = session.state;
    final canApply = kpOpposedCanApply(
      state: state,
      role: session.role,
      seat: session.seat,
    );

    return Column(
      key: OpposedSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ----------------------------------------------------------
        // ① 通用对抗（技能 / 属性比高低）
        // ----------------------------------------------------------
        SectionBox(
          title: '通用对抗',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              UnitPickerField(
                key: OpposedSheetKeys.aSeat,
                label: '甲方',
                display: _aUnit?.label ?? '未选',
                title: '选择甲方单位',
                onPicked: (RoomUnitOption o) => setState(() => _aUnit = o),
              ),
              _skillField(
                key: OpposedSheetKeys.aSkill,
                ctl: _aSkill,
                label: '甲方技能 / 属性（可填别名，如 斗殴 / 侦察）',
              ),
              if (_unitWithoutCard(_aUnit))
                _baseField(
                  key: OpposedSheetKeys.aBase,
                  ctl: _aBase,
                  label: '甲方对抗值（1–100，仅无卡单位）',
                ),
              UnitPickerField(
                key: OpposedSheetKeys.bSeat,
                label: '乙方',
                display: _bUnit?.label ?? '未选',
                title: '选择乙方单位',
                onPicked: (RoomUnitOption o) => setState(() => _bUnit = o),
              ),
              _skillField(
                key: OpposedSheetKeys.bSkill,
                ctl: _bSkill,
                label: '乙方技能 / 属性（可填别名，如 闪避 / 图书馆）',
              ),
              if (_unitWithoutCard(_bUnit))
                _baseField(
                  key: OpposedSheetKeys.bBase,
                  ctl: _bBase,
                  label: '乙方对抗值（1–100，仅无卡单位）',
                ),
              RoomTap(
                key: RoomKeys.action('check.opposed'),
                label: '发起通用对抗',
                icon: Icons.sports_kabaddi,
                enabled: gate.can('check.opposed'),
                hint: gate.can('check.opposed')
                    ? '双方各出一项技能 / 属性比高低'
                    : '只有 KP 能发起通用对抗',
                onTap: () => _submitGeneral(context),
              ),
            ],
          ),
        ),

        // ----------------------------------------------------------
        // ② 攻击对抗（玩家武器 / 怪物反击闪避 + 自动伤害）
        // ----------------------------------------------------------
        SectionBox(
          title: '攻击对抗',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              UnitPickerField(
                key: OpposedSheetKeys.attacker,
                label: '攻击方',
                display: _attUnit?.label ?? '未选',
                title: '选择攻击方',
                onPicked: (RoomUnitOption o) => setState(() {
                  if (_attUnit?.value != o.value) _weapon = null;
                  _attUnit = o;
                }),
              ),
              if (_attUnit != null && !_unitWithoutCard(_attUnit))
                _weaponField(context, state)
              else if (_unitWithoutCard(_attUnit)) ...<Widget>[
                _skillField(
                  key: OpposedSheetKeys.attackerSkill,
                  ctl: _attSkill,
                  label: '攻击方技能（无卡单位手输，如 斗殴）',
                ),
                _baseField(
                  key: OpposedSheetKeys.attackerBase,
                  ctl: _attBase,
                  label: '攻击方对抗值（1–100）· 攻击技能点数',
                ),
                _skillField(
                  key: OpposedSheetKeys.attackerDamage,
                  ctl: _attDamage,
                  label: '攻击方伤害骰式（如 1D6 / 2D6+1）',
                ),
              ],
              UnitPickerField(
                key: OpposedSheetKeys.defender,
                label: '防守方',
                display: _defUnit?.label ?? '未选',
                title: '选择防守方',
                onPicked: (RoomUnitOption o) => setState(() => _defUnit = o),
              ),
              if (_defUnit != null && !_unitWithoutCard(_defUnit))
                _skillField(
                  key: OpposedSheetKeys.defenderSkill,
                  ctl: _defSkill,
                  label: '防守方技能（从人物卡取值，如 闪避）',
                )
              else if (_unitWithoutCard(_defUnit)) ...<Widget>[
                _reactionRow('atk'),
                // ★ KP-4 / D1：数值优先，移除六档 `_levelRow('atk')`，
                // 乙方怪物改手输 1–100（反击 / 闪避技能点数）。
                _baseField(
                  key: OpposedSheetKeys.defenderBase,
                  ctl: _defBase,
                  label: '防守方对抗值（1–100）· 反击 / 闪避技能点数',
                ),
                if (_reaction == 'counter')
                  _skillField(
                    key: OpposedSheetKeys.counterDamage,
                    ctl: _counterDamage,
                    label: '反击伤害骰式（如 1D3 / 2D6+D4+1）',
                  ),
              ],
              _baseField(
                key: OpposedSheetKeys.armor,
                ctl: _armor,
                label: '防守方护甲（扣除后最低 0）',
              ),
              RoomTap(
                key: OpposedSheetKeys.attack,
                label: '发起攻击对抗',
                icon: Icons.gavel,
                enabled: gate.can('check.opposed'),
                hint: gate.can('check.opposed')
                    ? '系统自动检定并结算伤害'
                    : '只有 KP 能发起攻击对抗',
                onTap: () => _submitAttack(context, state),
              ),
            ],
          ),
        ),

        // ----------------------------------------------------------
        // ③ 裁定玩家发来的对抗申请
        // ----------------------------------------------------------
        SectionBox(
          title: '裁定待处理的对抗申请',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              UnitPickerField(
                key: OpposedSheetKeys.reqId,
                label: '申请单位',
                display: _reqUnit?.label ?? '未选',
                title: '选择申请单位',
                onPicked: (RoomUnitOption o) => setState(() => _reqUnit = o),
              ),
              _reactionRow('req'),
              _levelRow('req'),
              if (_reqReaction == 'counter')
                _skillField(
                  key: OpposedSheetKeys.resolveCounterDamage,
                  ctl: _reqCounterDamage,
                  label: '反击伤害骰式（怪物反击命中时用）',
                ),
              _baseField(
                key: OpposedSheetKeys.resolveArmor,
                ctl: _reqArmor,
                label: '防守方护甲',
              ),
              RoomTap(
                key: OpposedSheetKeys.resolve,
                label: '裁定',
                enabled: gate.can('check.opposed'),
                hint: '对该申请给出反击 / 闪避的检定等级',
                onTap: () => _submitResolve(context, state),
              ),
            ],
          ),
        ),

        // ----------------------------------------------------------
        // ④ 玩家胜后选伤害目标（INTENT.OPPOSED phase:target）
        // ----------------------------------------------------------
        SectionBox(
          title: '选伤害目标',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              UnitPickerField(
                key: OpposedSheetKeys.targetId,
                label: '伤害目标',
                display: _targetUnit?.label ?? '未选',
                title: '选择伤害目标',
                onPicked: (RoomUnitOption o) =>
                    setState(() => _targetUnit = o),
              ),
              RoomTap(
                key: OpposedSheetKeys.target,
                label: '选定目标',
                enabled: canApply,
                hint: canApply ? '提交伤害目标' : '仅战斗中且轮到自己时可选',
                onTap: () => _submitTarget(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 表单小组件
  // ------------------------------------------------------------

  Widget _skillField({
    required Key key,
    required TextEditingController ctl,
    required String label,
  }) {
    return TextField(
      key: key,
      controller: ctl,
      decoration: InputDecoration(labelText: label, isDense: true),
      style: const TextStyle(fontSize: 12),
    );
  }

  Widget _baseField({
    required Key key,
    required TextEditingController ctl,
    required String label,
  }) {
    return TextField(
      key: key,
      controller: ctl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true),
      style: const TextStyle(fontSize: 12),
    );
  }

  /// 武器下拉：点开弹层列人物卡里的武器（老 APP `mem.sheet.weapons`）。
  /// 选中后技能的检定值由权威端按 `weapon.skill` 去卡里取（UI 不反查）。
  Widget _weaponField(BuildContext context, Map<String, Object?> state) {
    final seat = _bareSeat(_attUnit?.value ?? '');
    final list = _weaponsOf(state, seat);
    final cur = _weapon;
    final label = cur == null
        ? '武器：未选（点击选择）'
        : '武器：${roomText(cur['name'])}（${roomText(cur['damage'])}'
            '${roomText(cur['pierce']) == '√' ? ' 贯穿' : ''}）';
    return RoomTap(
      key: OpposedSheetKeys.attackerWeapon,
      label: label,
      hint: list.isEmpty ? '该玩家的人物卡里没有武器' : '选武器 → 技能自动检定',
      enabled: list.isNotEmpty,
      onTap: () async {
        final picked = await _pickWeapon(context, list);
        if (picked == null || !mounted) return;
        setState(() => _weapon = picked);
      },
    );
  }

  Future<Map<String, Object?>?> _pickWeapon(
    BuildContext context,
    List<Map<String, Object?>> list,
  ) {
    return showRoomSheet<Map<String, Object?>>(
      context: context,
      title: '选择武器',
      body: (BuildContext _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < list.length; i++)
            RoomTap(
              key: OpposedSheetKeys.weaponOption(i),
              label: '${roomText(list[i]['name'])}'
                  '（${roomText(list[i]['damage'])}'
                  '${roomText(list[i]['pierce']) == '√' ? ' 贯穿' : ''}'
                  '·技能 ${roomText(list[i]['skill'])}）',
              hint: '用这把武器发起攻击对抗',
              onTap: () => Navigator.of(context).pop<Map<String, Object?>>(
                list[i],
              ),
            ),
        ],
      ),
    );
  }

  /// 防守方式二选一：反击（同级攻方胜）/ 闪避（同级攻方败 / 免伤）。
  Widget _reactionRow(String scope) {
    final cur = scope == 'atk' ? _reaction : _reqReaction;
    void pick(String r) => setState(() {
          if (scope == 'atk') {
            _reaction = r;
          } else {
            _reqReaction = r;
          }
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('防守方式', style: TextStyle(fontSize: 12)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            RoomTap(
              key: OpposedSheetKeys.reaction(scope, 'counter'),
              label: '反击（同级攻方胜）${cur == 'counter' ? '·已选' : ''}',
              hint: '怪物反击：同级时攻方胜，命中则伤害打在攻击方身上',
              onTap: () => pick('counter'),
            ),
            RoomTap(
              key: OpposedSheetKeys.reaction(scope, 'dodge'),
              label: '闪避（同级免伤）${cur == 'dodge' ? '·已选' : ''}',
              hint: '怪物闪避：同级时攻方败（被躲开、免伤）',
              onTap: () => pick('dodge'),
            ),
          ],
        ),
      ],
    );
  }

  /// 检定等级六档（取代原来的 1–100 对抗值输入框）。
  Widget _levelRow(String scope) {
    final cur = scope == 'atk' ? _defLevel : _reqLevel;
    void pick(int lv) => setState(() {
          if (scope == 'atk') {
            _defLevel = lv;
          } else {
            _reqLevel = lv;
          }
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('防守方检定等级', style: TextStyle(fontSize: 12)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final lv in kOpposedLevelValues)
              RoomTap(
                key: OpposedSheetKeys.level(scope, lv),
                label: '${opposedLevelText(lv)}${cur == lv ? '·已选' : ''}',
                hint: '把防守方的检定结果判为${opposedLevelText(lv)}',
                onTap: () => pick(lv),
              ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // 提交
  // ------------------------------------------------------------

  /// ① 通用对抗：`check.opposed {aSeat,aSkill,aBase,bSeat,bSkill,bBase}`。
  void _submitGeneral(BuildContext context) {
    final ctl = RoomScope.of(context).controller;
    final a = _aUnit;
    final b = _bUnit;
    if (a == null || b == null) {
      ctl.notice('请先选择通用对抗的甲方与乙方单位');
      return;
    }
    // 有卡单位一律不塞 base：技能值必须由权威端从人物卡取（查不到要明确报错，
    // 不能被输入框里的残留值静默兜底）。
    final aBase = _unitWithoutCard(a) ? _parseBase(_aBase.text) : null;
    final bBase = _unitWithoutCard(b) ? _parseBase(_bBase.text) : null;
    if (_unitWithoutCard(a) && aBase == null) {
      ctl.notice('甲方是无卡单位，请填写 1–100 的对抗值');
      return;
    }
    if (_unitWithoutCard(b) && bBase == null) {
      ctl.notice('乙方是无卡单位，请填写 1–100 的对抗值');
      return;
    }
    ctl.hostAction('check.opposed', <String, Object?>{
      'aSeat': a.value,
      'aSkill': _aSkill.text.trim(),
      'aBase': ?aBase,
      'bSeat': b.value,
      'bSkill': _bSkill.text.trim(),
      'bBase': ?bBase,
    });
  }

  /// ② 攻击对抗：`check.opposed {attack:true, attacker, defender, weapon, armor}`。
  void _submitAttack(BuildContext context, Map<String, Object?> state) {
    final ctl = RoomScope.of(context).controller;
    final atk = _attUnit;
    final def = _defUnit;
    if (atk == null || def == null) {
      ctl.notice('请先选择攻击方与防守方单位');
      return;
    }
    // ---- 攻击方 ----
    Map<String, Object?> attacker;
    Map<String, Object?> weapon;
    if (_unitWithoutCard(atk)) {
      final base = _parseBase(_attBase.text);
      if (base == null) {
        ctl.notice('攻击方是无卡单位，请填写 1–100 的对抗值');
        return;
      }
      final dmg = _attDamage.text.trim();
      if (dmg.isEmpty) {
        ctl.notice('请填写攻击方伤害骰式（如 1D6 / 2D6+1）');
        return;
      }
      attacker = <String, Object?>{
        'side': 'monster',
        'actorId': _bareSeat(atk.value),
        'name': _unitName(atk),
        'skill': _attSkill.text.trim(),
        'value': base,
        'ranged': false,
      };
      weapon = <String, Object?>{
        'name': '',
        'damage': dmg,
        'pierce': '×',
        'db': '0',
        'perRound': '1',
      };
    } else {
      final w = _weapon;
      if (w == null) {
        ctl.notice('请先为攻击方选择武器（技能会按武器自动检定）');
        return;
      }
      final seat = _bareSeat(atk.value);
      final mem = _memberOf(state, seat);
      final wSkill = roomText(w['skill']).trim();
      if (wSkill.isEmpty) {
        ctl.notice('这把武器没有战斗技能，无法自动检定（请换一把武器）');
        return;
      }
      attacker = <String, Object?>{
        'side': 'pc',
        'seat': seat,
        'name': _unitName(atk),
        'skill': wSkill,
        'ranged': RegExp(r'射击|枪|弓|投掷|弩').hasMatch(wSkill),
      };
      weapon = <String, Object?>{
        'name': w['name'],
        'skill': w['skill'],
        'damage': w['damage'],
        'pierce': w['pierce'],
        'perRound': w['perRound'],
        // 伤害加值：玩家取人物卡 DB（老 APP `me.sheet.db`）。
        'db': roomText(asMap(mem?['sheet'])['db']).isEmpty
            ? '0'
            : roomText(asMap(mem?['sheet'])['db']),
      };
    }
    // ---- 防守方 ----
    Map<String, Object?> defender;
    if (_unitWithoutCard(def)) {
      // ★ KP-4 / 契约 I3：防守方怪物改塞 1–100 的 `value`，**不含 `level`**；
      // domain `declared` 已改「有 value 优先」，旧「只有 level」载荷仍兜底。
      final base = _parseBase(_defBase.text);
      if (base == null) {
        ctl.notice('防守方是无卡单位，请填写 1–100 的对抗值');
        return;
      }
      defender = <String, Object?>{
        'side': 'monster',
        'actorId': _bareSeat(def.value),
        'name': _unitName(def),
        'skill': _reaction == 'counter' ? '反击' : '闪避',
        'reaction': _reaction,
        'value': base,
        if (_reaction == 'counter') 'damage': _counterDamage.text.trim(),
      };
    } else {
      defender = <String, Object?>{
        'side': 'pc',
        'seat': _bareSeat(def.value),
        'name': _unitName(def),
        'skill': _defSkill.text.trim(),
        'reaction': _reaction,
      };
    }
    ctl.hostAction('check.opposed', <String, Object?>{
      'attack': true,
      'attacker': attacker,
      'defender': defender,
      'weapon': weapon,
      'armor': <String, Object?>{'value': _parseArmor(_armor.text)},
      'shots': 1,
    });
  }

  /// ③ 裁定玩家申请：`check.opposed {reqId, attack:true, defender, armor}`。
  void _submitResolve(BuildContext context, Map<String, Object?> state) {
    final ctl = RoomScope.of(context).controller;
    // 待办 id 只有 `state.opposed.id` 一个真源（老 APP 同口径）；
    // 没有待办时回落到选中值，保持既有 UI 行为不变。
    final pendingId = roomText(asMap(state['opposed'])['id']);
    final reqId =
        pendingId.isNotEmpty ? pendingId : (_reqUnit?.value ?? '');
    if (reqId.isEmpty) {
      ctl.notice('当前没有待处理的对抗申请（请先让玩家发起，或选择申请单位）');
      return;
    }
    ctl.hostAction('check.opposed', <String, Object?>{
      'reqId': reqId,
      'attack': true,
      'defender': <String, Object?>{
        'reaction': _reqReaction,
        'level': _reqLevel,
        if (_reqReaction == 'counter')
          'damage': _reqCounterDamage.text.trim(),
      },
      'armor': <String, Object?>{'value': _parseArmor(_reqArmor.text)},
    });
  }

  /// ④ 玩家胜后选伤害目标（意图通道；domain 只认裸 actorId）。
  void _submitTarget(BuildContext context) {
    final ctl = RoomScope.of(context).controller;
    final t = _targetUnit;
    if (t == null) {
      ctl.notice('请先选择伤害目标');
      return;
    }
    ctl.sendIntent(RoomIntent.opposed, <String, Object?>{
      'phase': 'target',
      'targetId': _bareSeat(t.value),
    });
  }

  /// 单位展示名去掉「（玩家）/（怪物）」后缀（载荷 name 只放纯名字）。
  static String _unitName(RoomUnitOption o) {
    final l = o.label;
    final i = l.lastIndexOf('（');
    return i > 0 ? l.substring(0, i) : l;
  }
}

/// 打开对抗弹层。
Future<T?> showOpposedSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: '对抗',
    body: (BuildContext _) => const OpposedSheet(),
  );
}

// ------------------------------------------------------------
// ★ PV-1b（2.34.0 / 契约 I11）：玩家主动对抗申请
// ------------------------------------------------------------

/// 玩家主动对抗申请弹层内部稳定 key（全部独立 [ValueKey]）。
///
/// ★ 契约 I12：**不挂** `RoomKeys.action('check.opposed')` —— 与「治疗」
/// `treatKey` 同款，只开本机弹层的按钮不挂 act/ 锚点，避免 T-30 探针误判；
/// T03 打开本弹层的按钮用的是 `RoomGamePage.playerOpposedKey`。
class PlayerOpposedRequestSheetKeys {
  const PlayerOpposedRequestSheetKeys._();

  static const Key root =
      ValueKey<String>('playerOpposedRequestSheet');
  static const Key skill =
      ValueKey<String>('playerOpposedRequestSheet/skill');
  static const Key target =
      ValueKey<String>('playerOpposedRequestSheet/target');
  static const Key submit =
      ValueKey<String>('playerOpposedRequestSheet/submit');
}

/// ★ 契约 I11：打开「玩家主动对抗申请」弹层。
///
/// 与「申请治愈」同链路（用户拍板 D3）：`check.opposed` POLICY 为
/// `[kp, player] + RoomConfirm.kp`（T01 已改），玩家提交后由 domain 的
/// `act()` 入 `pending`，`RoomRequestWatcher` 给 KP 弹「待确认」，KP 同意
/// 后 `checkOpposed` 的 `auto` 分支（T02）按 `skillBaseOf(角色卡)` 取技能值
/// 并自动掷骰；结果由权威端写 PUBLIC log，再经遮罩广播层显示。
///
/// ★ 技能值由权威端读卡，本弹层**不填任何技能点数**（用户拍板 D6）；
/// ★ 提交后只给本机「已提交，等待 KP 同意」反馈（`ctl.notice`，参考
///   `sheet_treat.dart:133`），**这不是结果播报**；
/// ★ 不复用 ③「裁定待处理的对抗申请」UI（那是 `RoomIntent.opposed`
///   状态机），不挂 `RoomKeys.action('check.opposed')`；
/// ★ 用 `showRoomSheet` 统一壳承载（全局壳禁改，C8）；body 子树用
///   `MediaQuery.withClampedTextScaling` 钳到 1.0（C7，只包子树）。
Future<T?> showPlayerOpposedRequestSheet<T>(BuildContext context) {
  return showRoomSheet<T>(
    context: context,
    title: '申请对抗检定',
    body: (BuildContext _) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: const PlayerOpposedRequestSheet(),
    ),
  );
}

/// 玩家主动对抗申请弹层主体：选对抗技能 + 目标 → 提交（等 KP 同意）。
class PlayerOpposedRequestSheet extends StatefulWidget {
  const PlayerOpposedRequestSheet({super.key});

  @override
  State<PlayerOpposedRequestSheet> createState() =>
      _PlayerOpposedRequestSheetState();
}

class _PlayerOpposedRequestSheetState
    extends State<PlayerOpposedRequestSheet> {
  /// 对抗技能名（**只填名字**；数值由权威端 `skillBaseOf` 从角色卡读取）。
  final TextEditingController _skill =
      TextEditingController(text: '侦查');

  /// 目标：统一枚举 value（`p:<seat>` / `a:<id>` / `*`），默认全体。
  String _targetSeat = kUnitAllValue;
  String _targetLabel = '全体';

  @override
  void dispose() {
    _skill.dispose();
    super.dispose();
  }

  /// 契约 I5 冻结载荷：`RoomIntent.act` 的
  /// `p = {op:'check.opposed', auto:true, skill, targetSeat, by}`。
  /// `by` 用当前 seat；`targetSeat` 经 [unitValueToSeat] 剥成裸 seat / '*'。
  void _submit(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final skill = _skill.text.trim();
    if (skill.isEmpty) {
      ctl.notice('请填写对抗技能名（技能值由角色卡自动读取）');
      return;
    }
    final payload = <String, Object?>{
      'op': 'check.opposed',
      'auto': true,
      'skill': skill,
      'targetSeat': unitValueToSeat(_targetSeat),
      'by': scope.session.seat,
    };
    // ★ P12 PL-1c（契约 I5 扩展）：目标是可见怪物 / NPC 时补**可选**
    //   `defender` 袋，既有 5 键逐字不动。玩家态 `state['actors']` 只含
    //   `visibleToPlayers == true` 的记录，故 `a:` 项必为可见怪；
    //   `actorId` 保留不带前缀的原 id，供 KP 同意后第二段窗补值。
    if (_targetSeat.startsWith('a:')) {
      payload['defender'] = <String, Object?>{
        'side': 'monster',
        'actorId': _targetSeat.substring(2),
      };
    }
    ctl.sendIntent(RoomIntent.act, payload);
    // 与 `sheet_treat.dart:133` 同款的本机反馈；真失败时 controller 的
    // `notice('操作失败：…')` 走微任务晚于本行，会覆盖它，不会盖住错误。
    // ★ 这不是结果播报：结果由权威端 PUBLIC log + 遮罩广播层呈现。
    ctl.notice('已提交对抗申请，等待 KP 同意');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canApply =
        RoomScope.of(context).controller.gate.can('check.opposed');
    return Column(
      key: PlayerOpposedRequestSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: '申请对抗检定',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: PlayerOpposedRequestSheetKeys.skill,
                controller: _skill,
                decoration: const InputDecoration(
                  labelText: '对抗技能（技能值由角色卡自动读取，不用填数值）',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              UnitPickerField(
                key: PlayerOpposedRequestSheetKeys.target,
                label: '对抗目标（* = 全体）',
                display: _targetLabel,
                title: '选择对抗目标',
                allowAll: true,
                onPicked: (RoomUnitOption o) => setState(() {
                  _targetSeat = o.value;
                  _targetLabel = o.label;
                }),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: RoomTap(
                  key: PlayerOpposedRequestSheetKeys.submit,
                  label: '提交申请（等 KP 同意）',
                  icon: Icons.send,
                  enabled: canApply,
                  hint: canApply
                      ? '提交后需 KP 同意，系统按角色卡技能值自动检定'
                      : '当前角色不能发起对抗申请',
                  onTap: () => _submit(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// ★ P12 PL-1c：KP 同意后补输怪物技能点数的第二段弹窗
// ------------------------------------------------------------

/// 第二段弹窗内部稳定 key（§7.1，独立 `ValueKey<String>`，不挂 act/ 锚点）。
class MonsterValueSheetKeys {
  const MonsterValueSheetKeys._();

  static const Key root = ValueKey<String>('monsterValueSheet/root');
  static const Key field = ValueKey<String>('monsterValueSheet/field');
  static const Key submit = ValueKey<String>('monsterValueSheet/submit');
  static const Key cancel = ValueKey<String>('monsterValueSheet/cancel');

  /// ★ P20（需求 1）：反击伤害骰式输入框（仅 `needCounterDamage == true` 时存在）。
  static const Key damage = ValueKey<String>('monsterValueSheet/damage');
}

/// ★ P20（需求 1）：[showMonsterValueSheet] 的返回值。
///
/// 改前只返回 `int`（守方技能点数）；玩家攻击对抗选「反击」时 KP 还要补一个
/// 「反击伤害骰式」，因此升级为「数值 + 骰式」两项。
///
/// ★ [damage] 为空串表示「本次不需要反击伤害式」——只有 `needCounterDamage
///   == false`（闪避 / 不防御 / 非反击路径）才会出现；需要时留空已由本弹窗
///   兜底成裁定 D2 的默认 `1D3`。调用方仍按「非空才带键」处理，便于其它
///   调用点逐字保持旧行为。
class MonsterValueResult {
  const MonsterValueResult({required this.value, this.damage = ''});

  /// 守方技能点数（1–100 整数）。
  final int value;

  /// 反击伤害骰式（如 `1D6+2`）。非反击路径恒为空串。
  final String damage;
}

/// KP 同意「目标为可见怪的 auto 对抗」后弹出的第二段窗。
///
/// 返回 [MonsterValueResult]；取消 / 点外部 / 返回键 → `null`。
/// ★ 取消 = **不发 confirm、不结算、pending 保留**；调用方
///   （`RoomRequestWatcher._reply`）会保留原推送弹窗，可再次点同意重触发。
/// ★ 本函数只返回数值（与可选的伤害骰式），不组装载荷、不写权威 state、
///   不新增协议。
/// ★ P20：新增可选开关 [needCounterDamage]。为 true 时在 1–100 输入框下方
///   追加「反击伤害骰式」输入框（稳定 key [MonsterValueSheetKeys.damage]），
///   留空时返回值里的 `damage` 用裁定 D2 的默认值 `1D3`。
Future<MonsterValueResult?> showMonsterValueSheet({
  required BuildContext context,
  required String actorId,
  bool needCounterDamage = false,
}) {
  return showRoomSheet<MonsterValueResult>(
    context: context,
    title: '输入怪物技能点数',
    body: (BuildContext _) => MonsterValueSheet(
      actorId: actorId,
      needCounterDamage: needCounterDamage,
    ),
  );
}

/// 第二段弹窗主体：1–100 整数，空 / 非法禁用「确定」。
class MonsterValueSheet extends StatefulWidget {
  const MonsterValueSheet({
    super.key,
    required this.actorId,
    this.needCounterDamage = false,
  });

  /// 目标怪物 / NPC 的 id（仅用于提示文案，不参与校验）。
  final String actorId;

  /// ★ P20：是否额外要求「反击伤害骰式」（仅玩家攻击对抗选反击时为 true）。
  final bool needCounterDamage;

  @override
  State<MonsterValueSheet> createState() => _MonsterValueSheetState();
}

class _MonsterValueSheetState extends State<MonsterValueSheet> {
  final TextEditingController _value = TextEditingController();

  /// ★ P20：反击伤害骰式草稿。无论是否展示都建（`dispose` 统一释放），
  ///   避免「按需创建 / 条件释放」带来的泄漏风险。
  final TextEditingController _damage = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    _damage.dispose();
    super.dispose();
  }

  /// 严格 1–100 整数；空 / 小数 / 越界 / 非数字一律 null。
  int? _parsed() {
    final raw = _value.text.trim();
    if (raw.isEmpty) return null;
    final n = int.tryParse(raw);
    if (n == null || n < 1 || n > 100) return null;
    return n;
  }

  /// 反击伤害骰式：留空 → 裁定 D2 的默认 `1D3`（保住老口径，反击不会是 0 伤害）。
  ///
  /// 只做 trim，不做语法校验 —— 骰式的唯一真源是 domain 的 `rules.parseExpr`，
  /// 非法式由 `opposedAttackResolve` 报错且不结算（D2）。
  String _damageExpr() {
    if (!widget.needCounterDamage) return '';
    final String raw = _damage.text.trim();
    return raw.isEmpty ? '1D3' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final int? value = _parsed();
    return Column(
      key: MonsterValueSheetKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.actorId.isEmpty
              ? '请输入守方技能点数（1–100 整数）'
              : '目标 ${widget.actorId} · 守方技能点数（1–100 整数）',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          key: MonsterValueSheetKeys.field,
          controller: _value,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '技能点数',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: (String _) => setState(() {}),
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
        ),
        // ★ P20（需求 1）：反击时由 KP 补「反击伤害骰式」；留空走 `1D3`。
        if (widget.needCounterDamage) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            key: MonsterValueSheetKeys.damage,
            controller: _damage,
            decoration: const InputDecoration(
              labelText: '反击伤害骰式（如 1D6+2，留空默认 1D3）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 12),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ],
        const SizedBox(height: 10),
        clampBtnText(
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              RoomTap(
                key: MonsterValueSheetKeys.submit,
                label: '确定',
                icon: Icons.check,
                enabled: value != null,
                hint: value == null ? '请输入 1–100 的整数' : '确认并发起自动结算',
                onTap: () {
                  final int? v = _parsed();
                  if (v != null) {
                    Navigator.of(context).pop<MonsterValueResult>(
                      MonsterValueResult(value: v, damage: _damageExpr()),
                    );
                  }
                },
              ),
              RoomTap(
                key: MonsterValueSheetKeys.cancel,
                label: '取消',
                icon: Icons.close,
                hint: '取消补值（不结算，申请保留）',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
