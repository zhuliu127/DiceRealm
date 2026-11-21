// ============================================================
// sheets/sheet_kp_directives.dart — KP 定向 8 项（设计 §5 T04 / S4.5）
//
// ★ P17 / KP-6（v2.30.0）：从「只能选目标、没有输入效果」改成
//   「每个按钮各自一张小表单，填完再点目标行确认」。
//   · 载荷字段名逐条对齐老 APP 2.13.13 `web/js/ui/room-panels.js:2393-2416`；
//   · 「暗骰」（原 `kKpDirectives` 第 5 项）与「请求修改状态」（原
//     `kKpExtraDirectives` 第 2 项）已删：前者骰子工具弹层 / 工具栏已有入口，
//     后者玩家申请会直接弹窗，重复；
//   · 「SAN 大失败追加」按施工单 Q4 拍板**只追加最近一次**、不新增任何存储
//     结构，沿用 `sheet.sanloss{seat}`（权威端默认掷 1D10，老 APP 一键口径）；
//   · ⚠️ **用户口径 > 老 APP**（2026-11-14 裁决）：老 APP 没有「急救/医学检定
//     数值」「精神分析检定数值」，用户明确点了这两项，故 `aid.apply` /
//     `aid.psycho` 各补一个**可选** `base` 输入（留空则不写该键，权威端照旧
//     从角色卡取技能值 —— 老载荷路径逐字不变）。
//
// ★ 目标过滤（两道，都是纯函数，可脱离 widget 逐项断言）：
//   ① 已撕卡座位（死亡 / 永久疯狂）→ **全部指令**不进目标列表；
//   ② 疯狂发作中的座位 → 在「需其同意」的各项里被过滤；
//      另外 `sheet.sancheck` / `sheet.sanloss` 的权威端也有同款拒绝分支，
//      按 §7 K6「UI 判据必须与权威端拒绝文案逐条对齐」一并过滤。
//   两份名单都是文件级常量，改口径只需改一处，不散落在 widget 树里。
//
// ★ 只画、只发意图：零权威端引用、零权威状态赋值。
//   唯一的 domain 引用是 `CocRules.parseExpr`（**纯函数**，只做骰式语法校验，
//   不掷骰、不碰状态），用来在发包含骰式的载荷前给本机提示；权威端仍会二次校验。
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter,
        TextInputFormatter;

import '../../../domain/js_compat.dart' show asList, asMap;
import '../../../domain/room_rules.dart' show CocRules;
import '../room_keys.dart';
import '../room_scope.dart';
import '../view/member_view.dart' show targetBlocked;
import '../view/room_view.dart' show playersOf;
import '../widgets/room_panel_kit.dart' show RoomTap, SectionBox;
import 'room_sheet.dart' show showRoomSheet;
import '../room_text.dart';

/// 一条定向指令。
class KpDirective {
  const KpDirective({
    required this.op,
    required this.label,
    required this.icon,
  });

  final String op;
  final String label;
  final IconData icon;
}

/// PRD §5.8 的定向指令卡。P17 起 8 项（删「暗骰」，顺序与旧版一致）。
const List<KpDirective> kKpDirectives = <KpDirective>[
  KpDirective(op: 'sheet.damage', label: '造成伤害', icon: Icons.bolt),
  KpDirective(op: 'sheet.tempstatus', label: '临时状态', icon: Icons.label),
  KpDirective(op: 'sheet.item', label: '给物品', icon: Icons.card_giftcard),
  KpDirective(op: 'sheet.sancheck', label: 'SAN Check', icon: Icons.psychology),
  // P8：该操作现在同时清掉「不定疯狂」与「潜在疯狂」（见 madness_state
  // 的 cured 分支），文案必须覆盖两者，否则 KP 会以为潜在疯狂治不了。
  KpDirective(op: 'madness.cure', label: '治愈疯狂状态', icon: Icons.healing),
  KpDirective(op: 'sheet.healwound', label: '治愈重伤', icon: Icons.medical_services),
  KpDirective(op: 'aid.apply', label: '急救/医学', icon: Icons.medical_information),
  KpDirective(op: 'sheet.sanloss', label: 'SAN 大失败追加', icon: Icons.trending_down),
];

/// ★ P17 起本弹层不再渲染的两项（施工单 KP-6）。
///
/// 只删 UI 条目，不动 key 与常量：`RoomKeys.action('dice.dark')` /
/// `RoomKeys.action('state.request')` 仍分别在 `sheet_dice_tools.dart` 与
/// `sheet_scene.dart` 挂锚点，T-30 锚点表因此不变；domain 的 POLICY /
/// handler 一行未改（这两个 op 仍可被其它入口发出）。
const Set<String> kKpRemovedDirectiveOps = <String>{
  'dice.dark', // 骰子工具弹层 / 工具栏已有入口，重复
  'state.request', // 玩家「申请修改状态」会直接弹窗，不需要 KP 按钮
};

/// ★ R2a：「需其同意」的 5 项。
///
/// 依据 §1.6 权限同源：POLICY 中 `confirm` 非空且属于 KP 定向 / 状态协商
/// 的 5 个动作（前三项 confirm:kp，`aid.psycho` confirm:kp，
/// `state.request` 是 `state.edit.other` 的等价别名、confirm:owner）。
/// ⚠️ `state.request` 的 UI 条目已删（见 [kKpRemovedDirectiveOps]），但它
/// 仍是 domain 的「需同意」动作，故本名单保留不动（长度与语义都不变）。
const Set<String> kKpConsentOps = <String>{
  'madness.cure',
  'sheet.healwound',
  'aid.apply',
  'aid.psycho',
  'state.request',
};

/// 与权威端「疯狂发作中」拒绝分支对齐的额外 2 项（§7 K6）。
const Set<String> kKpMadBoutExtraOps = <String>{
  'sheet.sancheck',
  'sheet.sanloss',
};

/// 弹层提供的全部定向入口（8 项主卡 + 1 项需同意的补充入口）。
const List<KpDirective> kKpExtraDirectives = <KpDirective>[
  // 老 APP 没有 KP 侧「精神分析」按钮（它是玩家侧申请），但本 APP P16 已提供，
  // 保留：选目标 + 可选「检定数值」（2026-11-14 裁决补），载荷
  // `{seat, targetSeat[, base]}`。
  KpDirective(op: 'aid.psycho', label: '精神分析', icon: Icons.psychology_alt),
];

/// 需要先填参数再确认的指令（其余「无输入，系统自动判定」）。
///
/// `aid.psycho` 原本「无数值」，2026-11-14 裁决后补了可选「检定数值」，
/// 因此也进本名单（只有它一项有表单、但没有技能下拉）。
const Set<String> kKpFormOps = <String>{
  'sheet.damage',
  'sheet.tempstatus',
  'sheet.item',
  'sheet.sancheck',
  'aid.apply',
  'aid.psycho',
};

/// 该指令是否属于 R2a 的「需其同意」5 项。
bool kpDirectiveNeedsConsent(String op) => kKpConsentOps.contains(op);

/// 该指令是否要过滤「疯狂发作中」的目标。
bool kpDirectiveBlocksMadBout(String op) =>
    kpDirectiveNeedsConsent(op) || kKpMadBoutExtraOps.contains(op);

/// 座位是否处于疯狂发作中（临时 / 不定疯狂）。
///
/// 只看角色卡的 mental 列表，与权威端 `raMemberMadActive` 同判据；
/// 已撕卡（永久疯狂）由 [targetBlocked] 单独处理，不在这里重复。
bool kpMadBout(Map<String, Object?> mem) {
  final mental = asList(asMap(mem['sheet'])['mental']);
  for (final v in mental) {
    final s = roomText(v);
    if (s == '临时疯狂' || s == '不定疯狂') return true;
  }
  return false;
}

/// ★ 目标列表过滤（K-02）：已撕卡一律剔除；需同意 / 权威端拒绝的
/// 指令额外剔除疯狂发作中的座位。返回新列表，绝不修改入参。
List<Map<String, Object?>> kpDirectiveTargets(
  List<Map<String, Object?>> members, {
  required String op,
}) {
  final blockMad = kpDirectiveBlocksMadBout(op);
  return <Map<String, Object?>>[
    for (final m in members)
      if (!targetBlocked(m) && !(blockMad && kpMadBout(m))) m,
  ];
}

/// 指令 → 合法载荷（字段名与 D19 / D18 的 handler 逐项对齐）。
///
/// [form] 是弹层表单填出来的值（键名与老 APP 输入项同名）。缺省时回落成
/// 各字段的「最小合法值」，因此不传 [form] 的调用点（既有测试、其它入口）
/// 行为与 P17 之前一致，不会发出缺字段载荷。
Map<String, Object?> kpDirectivePayload(
  String op,
  String seat, {
  Map<String, Object?> form = const <String, Object?>{},
}) {
  switch (op) {
    case 'sheet.damage':
      // amount 只收整数：权威端 `sheetDamage` 用 `raClampNumber`（0-9999），
      // 与老 APP `parseInt(amtI.value,10)` 一致，不接受骰式。
      return <String, Object?>{
        'seat': seat,
        'amount': form['amount'] ?? 1,
        'kind': form['kind'] ?? '',
      };
    case 'sheet.tempstatus':
      return <String, Object?>{
        'seat': seat,
        'text': form['text'] ?? '临时状态',
      };
    case 'sheet.item':
      return <String, Object?>{
        'seat': seat,
        'name': form['name'] ?? '物品',
        'qty': form['qty'] ?? 1,
        'note': form['note'] ?? '',
      };
    case 'sheet.sancheck':
      // 默认值对齐老 APP `sanForPlayer`（成功 0 / 失败 1D6），两栏都可含骰式。
      return <String, Object?>{
        'seat': seat,
        'okLoss': form['okLoss'] ?? '0',
        'loss': form['loss'] ?? '1D6',
        'reason': form['reason'] ?? '',
      };
    case 'dice.dark':
      // P17 起本弹层不再渲染（入口在骰子工具弹层）；case 保留，外部按 op 取值不炸。
      return <String, Object?>{
        'seat': seat,
        'sides': 100,
        'count': 1,
        'bonus': 0,
        'reason': '',
      };
    case 'sheet.sanloss':
      // Q4 拍板：只追加最近一次、不新增存储结构。房间状态里**没有**「最近一次
      // SC 大失败」的记录（`m.sheet.sanLoss` 是 SAN 上限永久减损，不是这次损失），
      // 故按老 APP 一键口径：不带数字，权威端默认掷 1D10。
      return <String, Object?>{'seat': seat, 'dice': '1D10'};
    case 'aid.apply':
      // ★ 用户口径 > 老 APP（施工单 §0.1 / 2026-11-14 裁决）：老 APP 没有
      //   「急救检定数值」，用户明确要求「急救/医学的检定数值」要能填，故补
      //   可选 `base`；**留空不加键**，权威端照旧从角色卡取技能值。
      //   老 APP 另有「施救者」下拉，此处沿用 P16 的「目标行 = 施救者 = 目标」。
      return <String, Object?>{
        'seat': seat,
        'targetSeat': seat,
        'skill': form['skill'] ?? '急救',
        if (form['base'] != null) 'base': form['base'],
      };
    case 'aid.psycho':
      // 同上：补可选 `base`（精神分析检定数值），留空不加键。
      return <String, Object?>{
        'seat': seat,
        'targetSeat': seat,
        if (form['base'] != null) 'base': form['base'],
      };
    case 'state.request':
      // P17 起本弹层不再渲染（玩家申请直接弹窗）；case 保留兼容。
      return <String, Object?>{
        'seat': seat,
        'change': <String, Object?>{},
        'reason': 'KP 请求修改状态',
      };
    case 'madness.cure':
    case 'sheet.healwound':
    default:
      return <String, Object?>{'seat': seat};
  }
}

/// 定向指令弹层的稳定 key（P17 / KP-6）。
///
/// 命名沿用既有风格 `kpDirective/...`。目标行的「执行（确认）」按钮沿用 P16 的
/// `kpDirective/target/<op>/<seat>`（`room_ui_kp_test.dart` 已钉死该形态），
/// 这里只是把它收敛成工厂方法，字符串逐字不变。
class KpDirectiveKeys {
  const KpDirectiveKeys._();

  /// 目标行「执行 / 确认」按钮：每行一个座位，必须区分。
  static Key targetConfirm(String op, String seat) =>
      ValueKey<String>('kpDirective/target/$op/$seat');

  // ---- 造成伤害 ----
  static const Key damageAmount = ValueKey<String>('kpDirective/damage/amount');
  static const Key damageKind = ValueKey<String>('kpDirective/damage/kind');

  // ---- 临时状态 ----
  static const Key tempStatusText = ValueKey<String>('kpDirective/temp/text');

  // ---- 给物品 ----
  static const Key itemName = ValueKey<String>('kpDirective/item/name');
  static const Key itemQty = ValueKey<String>('kpDirective/item/qty');
  static const Key itemNote = ValueKey<String>('kpDirective/item/note');

  // ---- SAN Check ----
  static const Key sanCheckOkLoss = ValueKey<String>('kpDirective/san/okLoss');
  static const Key sanCheckLoss = ValueKey<String>('kpDirective/san/loss');
  static const Key sanCheckReason = ValueKey<String>('kpDirective/san/reason');

  // ---- 急救 / 医学（技能二选一） ----
  static Key aidSkill(String skill) =>
      ValueKey<String>('kpDirective/aid/skill/$skill');

  /// 急救 / 医学 / 精神分析的可选「检定数值」（留空 = 由角色卡技能值自动取）。
  static const Key aidBase = ValueKey<String>('kpDirective/aid/base');

  // ---- 表单校验提示 ----
  static const Key formError = ValueKey<String>('kpDirective/form/error');
}

/// 定向指令弹层。
///
/// [stateOverride] 供跨视角验数（注入裁剪后的玩家视图）；生产不传。
class KpDirectivesSheet extends StatefulWidget {
  const KpDirectivesSheet({super.key, this.stateOverride});

  final Map<String, Object?>? stateOverride;

  @override
  State<KpDirectivesSheet> createState() => _KpDirectivesSheetState();
}

class _KpDirectivesSheetState extends State<KpDirectivesSheet> {
  String _selectedOp = '';

  /// 表单校验未通过时显示的提示（空 = 无提示）。
  String _formError = '';

  // ---- 各指令的小表单草稿（默认值取自老 APP 输入项默认值） ----
  final TextEditingController _damageAmount = TextEditingController(text: '1');
  final TextEditingController _damageKind = TextEditingController();
  final TextEditingController _tempText = TextEditingController();
  final TextEditingController _itemName = TextEditingController();
  final TextEditingController _itemQty = TextEditingController(text: '1');
  final TextEditingController _itemNote = TextEditingController();
  final TextEditingController _okLoss = TextEditingController(text: '0');
  final TextEditingController _loss = TextEditingController(text: '1D6');
  final TextEditingController _sanReason = TextEditingController();

  /// 急救 / 医学：技能二选一。
  String _aidSkill = '急救';

  /// 急救 / 医学 / 精神分析的可选「检定数值」（留空 = 由角色卡技能值自动取）。
  final TextEditingController _aidBase = TextEditingController();

  @override
  void dispose() {
    _damageAmount.dispose();
    _damageKind.dispose();
    _tempText.dispose();
    _itemName.dispose();
    _itemQty.dispose();
    _itemNote.dispose();
    _okLoss.dispose();
    _loss.dispose();
    _sanReason.dispose();
    _aidBase.dispose();
    super.dispose();
  }

  static String _labelOf(String op) {
    for (final KpDirective d in <KpDirective>[
      ...kKpDirectives,
      ...kKpExtraDirectives,
    ]) {
      if (d.op == op) return d.label;
    }
    return op;
  }

  /// 成功 / 失败损失：纯数字或可解析骰式（对齐老 APP `validLossSide`）。
  ///
  /// 复用 domain 的 `CocRules.parseExpr`（纯函数、不掷骰）；权威端
  /// `parseSanLoss` 仍会二次校验，这里只负责「本机立刻给提示、不发包」。
  static bool _isLossExpr(String x) =>
      x.isNotEmpty && const CocRules().parseExpr(x)['ok'] == true;

  /// 校验当前指令的表单。返回 null = 通过，否则为提示文案。
  String? _validate(String op) {
    switch (op) {
      case 'sheet.damage':
        final int? v = int.tryParse(_damageAmount.text.trim());
        if (v == null || v <= 0 || v > 9999) {
          return '伤害值必须是 1–9999 的整数';
        }
        return null;
      case 'sheet.tempstatus':
        if (_tempText.text.trim().isEmpty) return '临时状态内容不能为空';
        return null;
      case 'sheet.item':
        if (_itemName.text.trim().isEmpty) return '物品名不能为空';
        final int? q = int.tryParse(_itemQty.text.trim());
        if (q == null || q < 1 || q > 9999) return '数量必须是 1–9999 的整数';
        return null;
      case 'sheet.sancheck':
        if (!_isLossExpr(_okLoss.text.trim())) {
          return '成功损失要填数字或骰式（如 0、1D6）';
        }
        if (!_isLossExpr(_loss.text.trim())) {
          return '失败损失要填数字或骰式（如 1D6、1D10）';
        }
        return null;
      case 'aid.apply':
      case 'aid.psycho':
        // 检定数值可留空；填了就必须是 1–999 的整数（空 / 非法不发包）。
        final String rawBase = _aidBase.text.trim();
        if (rawBase.isEmpty) return null;
        final int? b = int.tryParse(rawBase);
        if (b == null || b < 1 || b > 999) return '检定数值要留空或填 1–999 的整数';
        return null;
      default:
        return null;
    }
  }

  /// 表单草稿 → 载荷覆盖字段（只含该 op 关心的键）。
  Map<String, Object?> _draftFor(String op) {
    switch (op) {
      case 'sheet.damage':
        return <String, Object?>{
          'amount': int.tryParse(_damageAmount.text.trim()) ?? 0,
          'kind': _damageKind.text.trim(),
        };
      case 'sheet.tempstatus':
        return <String, Object?>{'text': _tempText.text.trim()};
      case 'sheet.item':
        return <String, Object?>{
          'name': _itemName.text.trim(),
          'qty': int.tryParse(_itemQty.text.trim()) ?? 1,
          'note': _itemNote.text.trim(),
        };
      case 'sheet.sancheck':
        return <String, Object?>{
          'okLoss': _okLoss.text.trim(),
          'loss': _loss.text.trim(),
          'reason': _sanReason.text.trim(),
        };
      case 'aid.apply':
        return <String, Object?>{
          'skill': _aidSkill,
          if (int.tryParse(_aidBase.text.trim()) != null)
            'base': int.parse(_aidBase.text.trim()),
        };
      case 'aid.psycho':
        return <String, Object?>{
          if (int.tryParse(_aidBase.text.trim()) != null)
            'base': int.parse(_aidBase.text.trim()),
        };
      default:
        return const <String, Object?>{};
    }
  }

  /// 固定宽度短字段：`isDense` + 只钳该控件子树的 textScaler（1.3/1.5/2.0 不溢出）。
  Widget _shortField({
    required Key key,
    required TextEditingController controller,
    required String label,
    double width = 108,
    bool digits = false,
    int? maxLength,
  }) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: SizedBox(
        width: width,
        child: TextField(
          key: key,
          controller: controller,
          keyboardType: digits ? TextInputType.number : TextInputType.text,
          inputFormatters: <TextInputFormatter>[
            if (digits) FilteringTextInputFormatter.digitsOnly,
            if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
          ],
          decoration: InputDecoration(labelText: label, isDense: true),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  /// 整行文本字段（高度随内容，不需要钳缩放）。
  Widget _wideField({
    required Key key,
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLength = 60,
  }) {
    return TextField(
      key: key,
      controller: controller,
      inputFormatters: <TextInputFormatter>[
        LengthLimitingTextInputFormatter(maxLength),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      ),
      style: const TextStyle(fontSize: 12),
    );
  }

  /// 当前指令的小表单（只有 [kKpFormOps] 才有）。
  Widget _form() {
    final String op = _selectedOp;
    final List<Widget> fields = <Widget>[];

    switch (op) {
      case 'sheet.damage':
        fields.add(Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _shortField(
              key: KpDirectiveKeys.damageAmount,
              controller: _damageAmount,
              label: '伤害值',
              digits: true,
              maxLength: 4,
            ),
            _shortField(
              key: KpDirectiveKeys.damageKind,
              controller: _damageKind,
              label: '伤害类型',
              width: 132,
              maxLength: 20,
            ),
          ],
        ));
        break;
      case 'sheet.tempstatus':
        fields.add(_wideField(
          key: KpDirectiveKeys.tempStatusText,
          controller: _tempText,
          label: '临时状态',
          hint: '如：中毒 3 轮 / 流血',
        ));
        break;
      case 'sheet.item':
        // 数量 + 物品名同排（老 APP 是「名称 / 数量 / 备注」三行，这里把短字段并排省高度）。
        fields.add(Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _shortField(
              key: KpDirectiveKeys.itemQty,
              controller: _itemQty,
              label: '数量',
              width: 88,
              digits: true,
              maxLength: 4,
            ),
            _shortField(
              key: KpDirectiveKeys.itemName,
              controller: _itemName,
              label: '物品名',
              width: 176,
              maxLength: 40,
            ),
          ],
        ));
        fields.add(_wideField(
          key: KpDirectiveKeys.itemNote,
          controller: _itemNote,
          label: '备注',
        ));
        break;
      case 'sheet.sancheck':
        fields.add(Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _shortField(
              key: KpDirectiveKeys.sanCheckOkLoss,
              controller: _okLoss,
              label: '成功损失',
              width: 116,
              maxLength: 12,
            ),
            _shortField(
              key: KpDirectiveKeys.sanCheckLoss,
              controller: _loss,
              label: '失败损失',
              width: 116,
              maxLength: 12,
            ),
          ],
        ));
        fields.add(_wideField(
          key: KpDirectiveKeys.sanCheckReason,
          controller: _sanReason,
          label: '原因',
          hint: '如：见到深潜者',
          maxLength: 40,
        ));
        break;
      case 'aid.apply':
        fields.add(Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final String skill in <String>['急救', '医学'])
              ChoiceChip(
                key: KpDirectiveKeys.aidSkill(skill),
                label: Text(skill, style: const TextStyle(fontSize: 11)),
                selected: _aidSkill == skill,
                onSelected: (_) => setState(() => _aidSkill = skill),
              ),
            _shortField(
              key: KpDirectiveKeys.aidBase,
              controller: _aidBase,
              label: '检定数值（可留空）',
              width: 152,
              digits: true,
              maxLength: 3,
            ),
          ],
        ));
        break;
      case 'aid.psycho':
        fields.add(Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _shortField(
              key: KpDirectiveKeys.aidBase,
              controller: _aidBase,
              label: '检定数值（可留空）',
              width: 152,
              digits: true,
              maxLength: 3,
            ),
          ],
        ));
        break;
      default:
        break;
    }

    // 校验提示（无提示时不占位）。
    if (_formError.isNotEmpty) {
      fields.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _formError,
          key: KpDirectiveKeys.formError,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...fields,
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('填好后点下方目标的「执行」',
              style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final ctl = scope.controller;
    final gate = ctl.gate;
    final state = widget.stateOverride ?? scope.session.state;
    final members = playersOf(state);
    final all = <KpDirective>[...kKpDirectives, ...kKpExtraDirectives];
    final rows = _selectedOp.isEmpty
        ? const <Map<String, Object?>>[]
        : kpDirectiveTargets(members, op: _selectedOp);
    final showForm = kKpFormOps.contains(_selectedOp);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionBox(
          title: '定向指令（8 项）',
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (final d in all)
                RoomTap(
                  key: RoomKeys.action(d.op),
                  label: d.label,
                  icon: d.icon,
                  enabled: gate.can(d.op),
                  hint: gate.can(d.op)
                      ? (kpDirectiveNeedsConsent(d.op)
                          ? '需目标玩家同意'
                          : '直接生效')
                      : '你没有权限执行该操作',
                  onTap: () => setState(() {
                    _selectedOp = d.op;
                    _formError = '';
                  }),
                ),
            ],
          ),
        ),
        // 只有需要填参数的指令才渲染表单（没有输入的指令保持「选目标 → 执行」两步）。
        if (showForm)
          SectionBox(
            title: '填写参数 · ${_labelOf(_selectedOp)}',
            child: _form(),
          ),
        SectionBox(
          title: _selectedOp.isEmpty
              ? '选择一条指令后显示目标'
              : '目标 · $_selectedOp',
          child: _targetList(context, scope, rows),
        ),
      ],
    );
  }

  Widget _targetList(
    BuildContext context,
    RoomScope scope,
    List<Map<String, Object?>> rows,
  ) {
    if (_selectedOp.isEmpty) {
      return const Text('尚未选择指令', style: TextStyle(fontSize: 12));
    }
    if (rows.isEmpty) {
      return const Text('没有可执行该指令的目标',
          style: TextStyle(fontSize: 12));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final m in rows)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${roomText(m['nickname'])}（${roomText(m['seat'])}）',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              RoomTap(
                key: KpDirectiveKeys.targetConfirm(
                    _selectedOp, roomText(m['seat'])),
                label: '执行',
                enabled: scope.controller.gate.can(_selectedOp),
                hint: '对该目标执行 $_selectedOp',
                onTap: () {
                  // 表单先校验：数值空 / 非法时只提示、不发包（KP-6 要求）。
                  final String? err = _validate(_selectedOp);
                  if (err != null) {
                    setState(() => _formError = err);
                    return;
                  }
                  if (_formError.isNotEmpty) {
                    setState(() => _formError = '');
                  }
                  scope.controller.hostAction(
                    _selectedOp,
                    kpDirectivePayload(
                      _selectedOp,
                      roomText(m['seat']),
                      form: _draftFor(_selectedOp),
                    ),
                  );
                },
              ),
            ],
          ),
      ],
    );
  }
}

/// 打开定向指令弹层。
Future<T?> showKpDirectivesSheet<T>(
  BuildContext context, {
  Map<String, Object?>? stateOverride,
}) {
  return showRoomSheet<T>(
    context: context,
    title: 'KP 定向指令',
    body: (BuildContext _) =>
        KpDirectivesSheet(stateOverride: stateOverride),
  );
}
