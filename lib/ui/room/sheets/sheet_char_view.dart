// ============================================================
// sheets/sheet_char_view.dart — 人物卡只读弹层（设计 §5 T04 / S4.4）
//
// 全部字段走 T01 的纯视图函数（双源兼容 / 白名单收敛），不自己拼 status：
// `vitalsOf / attrRows / skillRows / charStatusText / mentalText /
//  tempStatusOf / itemsOf / weaponsOf / madnessOf`，
// P10 第 1 期 B1 追加：`basicsOf / backgroundOf / historyOf / armorsOf /
//  assetsOf / eduOf`。
//
// ★ P10 第 1 期 B1（用户报的问题）：招募页 KP 点「详情」只能看到
//   数值 / 属性 / 技能 / 精神 / 临时 / 物品 / 武器 / 疯狂，
//   车卡器产出的**基本资料 / 背景 / 经历 / 装备与资产 / 教育进步**全部缺失。
//   现在按 `lib/ui/create/steps/*` 与 `lib/ui/summary_card.dart` 的同一批
//   公开字段补齐，顺序也和车卡器一致（先人、再背景、再经历、再装备）。
//
// ★ 超屏可滑动：`showRoomSheet` 的 body 外套 `SingleChildScrollView` +
//   0.72 屏高上限，所以本文件只负责**把内容摊平**，不加任何内层滚动容器
//   （嵌套滚动会让手指在卡片上推不动）。
//
// ★ 人物卡**只读**：本文件没有任何写回路径（K11 唯一写口在控制器）。
// ★ 只画、只发意图：零权威端引用、零权威状态赋值、零规则调用。
// ★ 只读公开口径：不读 `privates` / 明文 `p`；他人视图里被裁掉的字段
//   这里显示「未公开」，绝不拿 0 冒充真实数值。
// ============================================================

import 'package:flutter/material.dart';

import '../../../domain/js_compat.dart' show asMap;
import '../room_scope.dart';
import '../view/room_view.dart' show memberOfSeat;
import '../view/sheet_view.dart'
    show
        KeyValue,
        armorsOf,
        gearAssetsOf,
        attrRows,
        backgroundOf,
        basicsOf,
        charStatusText,
        eduOf,
        historyOf,
        itemsOf,
        madnessOf,
        mentalText,
        skillRows,
        tempStatusOf,
        vitalsOf,
        weaponsOf;
import '../widgets/room_panel_kit.dart' show SectionBox;
import 'room_sheet.dart' show showRoomSheet;
import '../room_text.dart';

/// 人物卡弹层内部稳定 key。
///
/// ⚠️ 前九个是 P5 起就被用例按名依赖的 key，**不许改名**（B1 只许新增）。
class CharViewKeys {
  const CharViewKeys._();

  static const Key root = ValueKey<String>('charView');
  static const Key status = ValueKey<String>('charView/status');
  static const Key vitals = ValueKey<String>('charView/vitals');
  static const Key attrs = ValueKey<String>('charView/attrs');
  static const Key skills = ValueKey<String>('charView/skills');
  static const Key mental = ValueKey<String>('charView/mental');
  static const Key temp = ValueKey<String>('charView/temp');
  static const Key items = ValueKey<String>('charView/items');
  static const Key weapons = ValueKey<String>('charView/weapons');
  static const Key madness = ValueKey<String>('charView/madness');

  // ---- P10 第 1 期 B1 新增（只增不改）----
  static const Key basics = ValueKey<String>('charView/basics');
  static const Key background = ValueKey<String>('charView/background');
  static const Key history = ValueKey<String>('charView/history');
  static const Key assets = ValueKey<String>('charView/assets');
  static const Key education = ValueKey<String>('charView/education');

  /// 滚动容器上的 key（用例据此断言「超屏能滑动」）。
  static const Key scroll = ValueKey<String>('charView/scroll');
}

/// 只读人物卡。
class CharViewSheet extends StatelessWidget {
  const CharViewSheet({
    super.key,
    required this.seat,
    this.stateOverride,
  });

  final String seat;

  /// 跨视角验数用；生产不传。
  final Map<String, Object?>? stateOverride;

  @override
  Widget build(BuildContext context) {
    final scope = RoomScope.of(context);
    final state = stateOverride ?? scope.session.state;
    final mem = memberOfSeat(state, seat);
    if (mem == null) {
      return const Text('找不到该成员', style: TextStyle(fontSize: 12));
    }
    final v = vitalsOf(mem);
    final sheet = asMap(mem['sheet']);
    final name = roomText(mem['nickname']).isEmpty
        ? seat
        : roomText(mem['nickname']);
    final basics = basicsOf(mem);
    final background = backgroundOf(mem);
    final history = historyOf(mem);
    final armors = armorsOf(mem);
    final assets = gearAssetsOf(mem);
    final (eduChecks, eduBonus) = eduOf(mem);

    // ★ 超屏可滑动：这一层是**滚动容器**，长度随内容走；
    //   直接放在 showRoomSheet 的 body 里（它自己已经套了 ScrollView，
    //   这里用 shrinkWrap 的 ListView 会和外层抢手势，所以只用一个
    //   SingleChildScrollView —— 见下面的 packaging）。
    final Widget body = Column(
      key: CharViewKeys.root,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('$name · ${charStatusText(mem)}',
            key: CharViewKeys.status,
            style: Theme.of(context).textTheme.titleSmall),
        // ---- 基本资料（B1）----
        if (basics.isNotEmpty)
          SectionBox(
            title: '基本资料',
            child: Column(
              key: CharViewKeys.basics,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[_kvs(basics)],
            ),
          ),
        SectionBox(
          title: '数值',
          child: Text(
            'HP ${v.hp}/${v.hpMax} · MP ${v.mp}/${v.mpMax} · '
            'SAN ${v.san}/${v.sanMax} · 幸运 ${v.luck}',
            key: CharViewKeys.vitals,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SectionBox(
          title: '属性',
          child: Wrap(
            key: CharViewKeys.attrs,
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final r in attrRows(mem))
                Text('${r.k} ${r.v}',
                    style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        SectionBox(
          title: '技能',
          child: Wrap(
            key: CharViewKeys.skills,
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final s in skillRows(sheet))
                Text('${s.name} ${s.value}',
                    style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        // ---- 背景八项 + 外貌（B1）----
        if (background.isNotEmpty)
          SectionBox(
            title: '背景',
            child: Column(
              key: CharViewKeys.background,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[_kvs(background)],
            ),
          ),
        // ---- 经历（B1）----
        SectionBox(
          title: '经历',
          child: Column(
            key: CharViewKeys.history,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final h in history) _historyItem(h),
              if (history.isEmpty)
                const Text('未填写', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        SectionBox(
          title: '精神',
          child: Text(
            mentalText(mem),
            key: CharViewKeys.mental,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SectionBox(
          title: '临时状态',
          child: Column(
            key: CharViewKeys.temp,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final t in tempStatusOf(mem))
                Text(roomText(t['text']),
                    style: const TextStyle(fontSize: 11)),
              if (tempStatusOf(mem).isEmpty)
                const Text('无', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        SectionBox(
          title: '物品',
          child: Column(
            key: CharViewKeys.items,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final it in itemsOf(mem))
                Text('${roomText(it['name'])} ×${roomText(it['qty'])}',
                    style: const TextStyle(fontSize: 11)),
              if (itemsOf(mem).isEmpty)
                const Text('无', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        SectionBox(
          title: '武器',
          child: Column(
            key: CharViewKeys.weapons,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final w in weaponsOf(mem))
                Text('${roomText(w['name'])} · ${roomText(w['damage'])}',
                    style: const TextStyle(fontSize: 11)),
              if (weaponsOf(mem).isEmpty)
                const Text('无', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        // ---- 装备与资产（B1：防具 + 信用/现金/资产说明）----
        SectionBox(
          title: '装备与资产',
          child: Column(
            key: CharViewKeys.assets,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (armors.isNotEmpty)
                Text('防具：${armors.join('、')}',
                    style: const TextStyle(fontSize: 11)),
              if (assets.isNotEmpty) _kvs(assets),
              if (armors.isEmpty && assets.isEmpty)
                const Text('未填写', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        // ---- 教育进步（B1）----
        SectionBox(
          title: '教育进步',
          child: Text(
            eduChecks <= 0 && eduBonus <= 0
                ? '无（未做教育进步检定）'
                : '教育进步检定 $eduChecks 次 · 教育 +$eduBonus',
            key: CharViewKeys.education,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        SectionBox(
          title: '疯狂',
          child: Column(
            key: CharViewKeys.madness,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final m in madnessOf(mem))
                Text(roomText(m['name']),
                    style: const TextStyle(fontSize: 11)),
              if (madnessOf(mem).isEmpty)
                const Text('无', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    );

    // ★ 超屏可滑动由**宿主**负责：`showRoomSheet` 的 body 外套
    //   `SingleChildScrollView` + 0.72 屏高上限，滚动只有那一层。
    //   这里**故意不再套一层** —— 嵌套同向滚动容器会抢手势，
    //   表现就是「手指在卡片上推不动」（P5 踩过一次）。
    //   用例的验法是：卡片高度 > 视口时，在卡面上拖动能让内容真的滚动。
    return body;
  }

  /// 一行键值（标签 + 值，值可换行）。
  static Widget _kvs(List<KeyValue> rows) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${r.k}：${r.v}',
              style: const TextStyle(fontSize: 11, height: 1.5),
            ),
          ),
      ],
    );
  }

  /// 一条经历：标题（加粗）+ 正文（可换行）。
  static Widget _historyItem(Map<String, Object?> h) {
    final title = roomText(h['title']);
    final date = roomText(h['date']);
    final desc = roomText(h['description']);
    final notes = roomText(h['notes']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title.isNotEmpty)
            Text(
              date.isEmpty ? title : '$title（$date）',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          if (desc.isNotEmpty)
            Text(desc, style: const TextStyle(fontSize: 11, height: 1.5)),
          if (notes.isNotEmpty)
            Text('备注：$notes',
                style: const TextStyle(fontSize: 11, height: 1.5)),
        ],
      ),
    );
  }
}

/// 打开人物卡只读弹层。
Future<T?> showCharViewSheet<T>(
  BuildContext context, {
  required String seat,
  Map<String, Object?>? stateOverride,
}) {
  return showRoomSheet<T>(
    context: context,
    title: '人物卡',
    body: (BuildContext _) => CharViewSheet(
      seat: seat,
      stateOverride: stateOverride,
    ),
  );
}
