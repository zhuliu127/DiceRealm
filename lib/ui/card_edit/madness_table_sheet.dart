// ============================================================
// madness_table_sheet.dart — 「疯狂表」弹层（车卡第 5 步与状态面板共用）
//
// 逐字对齐旧版 `ui/steps-d.js#madnessSheet`（v2.1.9 用户第 3 项）：
//   · 主表 = 即时症状（掷 1D10，发作时）+ 总结症状（独处 / 事后）两列，各 10 行
//   · 1-8 是**行为层面的结果**（直接选中），9 / 10 展开 100 条子表
//   · 「🎲 随机」严格按规则走 `rollTable()`：先 1D10，命中 9/10 再掷 1D100
//
// 选中一条症状 = 往 `background.phobias` 追加一行 `【类型】名字：描述`
// **并且**把它写进结构化 `madness` 数组（永久 / 背景语义）。
// 两条写入路径合并成一处，避免出现「背景写着、状态里没有」的老问题。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/character.dart';
import '../../domain/js_compat.dart';
import '../../domain/madness.dart' as mad;
import '../../theme.dart';
import '../notice.dart';

/// 打开疯狂表
Future<void> showMadnessTableSheet(
  BuildContext context, {
  required Character card,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    builder: (_) => _MadnessTableSheet(card: card, onChanged: onChanged),
  );
}

/// 把一条症状同时写进「疯狂症状」文本与结构化数组（旧版 `applySymptom`）
///
/// 返回本次真正新增的结构化条数（0 表示状态里已经有了）。
int applySymptomToBackground(
  Character card,
  String kind,
  String name,
  String desc, {
  bool isSum = false,
}) {
  final line = '【$kind】$name：${desc.isEmpty ? '' : desc}';
  final prev = jsStr(card.background['phobias'] ?? '');
  card.background['phobias'] = prev.trim().isEmpty
      ? line
      : '${prev.replaceFirst(RegExp(r'\s*$'), '')}\n$line';
  return mad.fromPicked(card, <Object?>[
    <String, Object?>{'kind': kind, 'name': name, 'desc': desc, 'sum': isSum},
  ]);
}

class _MadnessTableSheet extends StatelessWidget {
   const _MadnessTableSheet({required this.card, required this.onChanged});

  final Character card;
  final VoidCallback onChanged;

  void _pick(
    BuildContext context,
    String kind,
    Map<String, Object?> src, {
    bool isSum = false,
  }) {
    final name = jsStr(src['name']);
    final desc = jsStr(src['desc']);
    final n = applySymptomToBackground(card, kind, name, desc, isSum: isSum);
    onChanged();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSlot(
      SnackBar(
        content: Text(
          n > 0 ? '已选择：$name（已写入「疯狂症状」）' : '已选择：$name（状态里已有，未重复添加）',
        ),
      ),
    );
  }

  Future<void> _random(BuildContext context) async {
    final hit = mad.rollTable();
    final kind = jsStr(hit['kind']);
    final src = asMap(hit['src']);
    _pick(
      context,
      kind == 'bout' ? '疯狂发作' : (kind == 'mania' ? '狂躁症' : '恐惧症'),
      src,
    );
  }

  Future<void> _openSub(BuildContext context, String kind) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (_) =>
          _SubTableSheet(card: card, kind: kind, onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < 10; i++) {
      final bout = mad.boutTable[i];
      final sum = mad.summaryTable[i];
      rows.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Palette.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                  ),
                ),
              ),
              Expanded(
                child: _cell(
                  context,
                  bout,
                  false,
                  Key('madness_bout_${i + 1}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cell(context, sum, true, Key('madness_sum_${i + 1}')),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Palette.surface3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: <Widget>[
                const Text(
                  '疯狂表',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '持有 ${mad.list(card).length} 条',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('btn_madness_random'),
                  onPressed: () => _random(context),
                  icon: const Icon(Icons.casino_outlined, size: 16),
                  label: const Text('随机', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '掷 1D10：1-8 取即时症状；9 恐惧症 / 10 狂躁症再掷 1D100',
                    style: TextStyle(
                      fontSize: 11,
                      color: Palette.textMute,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 22,
                  child: Text(
                    '#',
                    style: TextStyle(fontSize: 11, color: Palette.textMute),
                  ),
                ),
                Expanded(
                  child: Text(
                    '即时症状（掷 1D10）',
                    style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '总结症状（独处时）',
                    style: TextStyle(fontSize: 11.5, color: Palette.textMute),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: rows,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              '即时症状在发作时按轮扮演；总结症状在独自一人时由 KP 陈述。'
              '第 9 / 10 条可展开 100 条恐惧症 / 狂躁症子表，点条目即选中。',
              style: TextStyle(
                fontSize: 11,
                color: Palette.textMute,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    Map<String, Object?> item,
    bool isSum,
    Key key,
  ) {
    final no = jsNum(item['no']);
    final isLink = no == 9 || no == 10;
    final name = jsStr(item['name']);
    return InkWell(
      key: key,
      onTap: () {
        if (isLink) {
          _openSub(context, no == 10 ? 'mania' : 'phobia');
          return;
        }
        _pick(context, '疯狂发作', item, isSum: isSum);
      },
      child: Text(
        isLink ? '$name ›' : name,
        style: TextStyle(
          fontSize: 12.5,
          color: isLink ? Palette.gold : Palette.textDim,
          height: 1.35,
        ),
      ),
    );
  }
}

/// 100 条恐惧症 / 狂躁症子表
class _SubTableSheet extends StatelessWidget {
   const _SubTableSheet({
    required this.card,
    required this.kind,
    required this.onChanged,
  });

  final Character card;
  final String kind;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final isMania = kind == 'mania';
    final label = isMania ? '狂躁症' : '恐惧症';
    final arr = isMania ? mad.manias() : mad.phobias();

    void apply(Map<String, Object?> src) {
      final n = applySymptomToBackground(
        card,
        label,
        jsStr(src['name']),
        jsStr(src['desc']),
      );
      onChanged();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSlot(
        SnackBar(
          content: Text(
            n > 0
                ? '已选择：${jsStr(src['name'])}'
                : '已选择：${jsStr(src['name'])}（已存在）',
          ),
        ),
      );
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Palette.surface3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: <Widget>[
                Text(
                  '$label表（100 条）',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: Key('btn_madness_sub_random_$kind'),
                  onPressed: () {
                    final pick = arr[(nowRng() * arr.length).floor()];
                    apply(pick);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.casino_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '随机$label',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: arr.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: Palette.border),
              itemBuilder: (context, i) {
                final it = arr[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    jsStr(it['name']),
                    style: TextStyle(
                      fontSize: 13,
                      color: Palette.textDim,
                    ),
                  ),
                  subtitle: Text(
                    jsStr(it['desc']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Palette.textMute,
                    ),
                  ),
                  onTap: () => apply(it),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
