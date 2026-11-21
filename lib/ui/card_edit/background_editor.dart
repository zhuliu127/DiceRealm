// ============================================================
// background_editor.dart — 角色背景 8 项（车卡第 5 步与角色卡详情共用）
//
// 字段口径**逐字**照抄旧版 `ui/steps-d.js#background` 的 FIELDS 表：
//   description / ideology / significantPeople / meaningfulPlaces /
//   treasuredPossessions / traits / wounds / phobias
// 键名一个都没改（这些键在 `store.js#newCharacter().background` 里就有，
// 自创键名会让老版本读不回去）。
//
// 「重要之人」在旧版是**单个文本框**，但推荐格式是 `关系｜经过｜现状`
// （见 `core/preset.js#significantPeople`）。所以这里多给一个「分段填写」
// 折叠区：三段拼回同一个 `significantPeople` 键，用 `｜` 连接 ——
// 只是输入辅助，不新增任何键。
//
// 10 套预设背景与「疯狂表」按钮都来自 steps-d.js，一并移植。
//
// P2-B2 补齐同一页面的其余四块（旧版 steps-d.js 约 240-530 行）：
//   调查员经历 / 调查员伙伴 / 克苏鲁神话 / 已学法术 —— 分别在
//   background_history.dart 与 background_mythos.dart 里实现，
//   键名逐字照抄旧版，挂在这一页最后（折叠块，只看不展开不影响数据）。
// ============================================================

import 'package:flutter/material.dart';

import '../../domain/character.dart';
import '../../domain/js_compat.dart';
import '../../domain/madness.dart' as mad;
import '../../theme.dart';
import '../status_ops.dart';
import '../widgets.dart';
import 'background_history.dart';
import 'background_mythos.dart';
import 'madness_table_sheet.dart';
import '../notice.dart';

/// 背景字段定义（键名 / 标签 / 占位提示，全部来自 steps-d.js）
const List<Map<String, String>> backgroundFields = <Map<String, String>>[
  <String, String>{
    'k': 'description',
    'label': '个人描述',
    'ph': '外貌、身高、体型、穿着、发型、特征…',
  },
  <String, String>{
    'k': 'ideology',
    'label': '思想 / 信念',
    'ph': '信仰、人生观、价值观、政治观点、人生目标…',
  },
  <String, String>{
    'k': 'significantPeople',
    'label': '重要之人',
    'ph': '姓名 / 身份 / 与角色关系（关系｜经过｜现状）/ 简介…',
  },
  <String, String>{
    'k': 'meaningfulPlaces',
    'label': '意义非凡之地',
    'ph': '地点名称 / 描述 / 为什么重要…',
  },
  <String, String>{
    'k': 'treasuredPossessions',
    'label': '宝贵之物',
    'ph': '物品名称 / 描述 / 来源 / 为什么重要…',
  },
  <String, String>{
    'k': 'traits',
    'label': '特点（性格）',
    'ph': '例：固执、谨慎、喜欢喝咖啡、不相信警察…',
  },
  <String, String>{
    'k': 'wounds',
    'label': '伤口 / 疤痕',
    'ph': '身体伤口 / 旧伤 / 疤痕 / 来源…',
  },
  <String, String>{
    'k': 'phobias',
    'label': '疯狂症状',
    'ph': '恐惧症 / 狂躁症 / 疯狂发作…（可从「疯狂表」选择）',
  },
];

/// 10 套预设背景（`ui/steps-d.js#PRESETS` 逐字移植）
const List<Map<String, String>> backgroundPresets = <Map<String, String>>[
  <String, String>{
    'name': '落魄记者',
    'd': '衣着略显褶皱的风衣，领口别着一支钢笔。眼神锐利但眼下有淡淡的青色。',
    'id': '真相必须被记录，哪怕没有人愿意读。',
    'p': '主编老陈｜报社上司｜他给了我第一份工作｜严厉但护短。',
    'pl': '报社资料室｜堆满旧报纸的房间｜我在这里查到过改变一生的线索。',
    't': '祖父的钢笔｜笔身有裂痕｜祖父遗物｜提醒我为什么开始写作。',
    'tr': '固执、习惯性怀疑权威、咖啡成瘾',
    'w': '右手掌有一道旧烫伤。',
    'ph': '对密闭空间有轻微不适。',
  },
  <String, String>{
    'name': '退役军官',
    'd': '挺拔的身姿，短发，左眉上有一道疤痕。穿着剪裁利落的旧西装。',
    'id': '秩序高于一切，混乱只会带来更多死亡。',
    'p': '老战友哈里斯｜同袍｜我们在同一场战役中活了下来｜唯一可以托付后背的人。',
    'pl': '索姆河畔的旧战壕｜荒废的泥土工事｜我在那里失去了半个连队。',
    't': '勋章｜带弹痕的铜质勋章｜战功｜提醒我代价是什么。',
    'tr': '沉默、极度整洁、睡前必检查门锁',
    'w': '左腿旧伤，阴雨天会疼。',
    'ph': '听到类似炮声的声音会僵直。',
  },
  <String, String>{
    'name': '古董商',
    'd': '圆框眼镜，马甲口袋挂着怀表链。手指因常年擦拭器物而干净修长。',
    'id': '每一件旧物都藏着一段没人愿意讲的故事。',
    'p': '埃莉诺姑妈｜启蒙者｜教我辨认真伪｜已故，留下这间店铺。',
    'pl': '旧店铺的地下库房｜潮湿但有独特的木质气味｜所有收藏的起点。',
    't': '黄铜钥匙｜无锁可开｜来源不明｜我总觉得它会派上用场。',
    'tr': '谨慎、喜欢收集、对数字敏感',
    'w': '右手食指有一道小切口。',
    'ph': '无法忍受器物被粗暴对待。',
  },
  <String, String>{
    'name': '医学院学生',
    'd': '白大褂下是皱巴巴的衬衫，总带着淡淡的消毒水气味。',
    'id': '死亡是一种可以被理解的现象，仅此而已。',
    'p': '导师布莱克教授｜师长｜在解剖课上注意到了我｜鼓励我质疑权威。',
    'pl': '解剖实验室｜有福尔马林的气味｜我第一次意识到人体的脆弱。',
    't': '手术刀｜刻着名字｜父亲送的入学礼物｜提醒我为什么选择这条路。',
    'tr': '理性、好奇心过剩、睡眠不足',
    'w': '左手腕有一道练习时留下的浅疤。',
    'ph': '对血液在意外场合出现会短暂失神。',
  },
  <String, String>{
    'name': '落魄贵族',
    'd': '昂贵但不合时宜的礼服，袖口有磨损。谈吐优雅，眼神里藏着倦意。',
    'id': '家族的名誉比我的生命更重要。',
    'p': '老管家雷诺｜守护者｜服侍家族四十年｜唯一还留在宅邸的人。',
    'pl': '祖宅的书房｜三层楼梯尽头｜墙上挂着三代人的肖像。',
    't': '家族印章｜黄铜质地｜父亲遗物｜证明我仍然是谁。',
    'tr': '骄傲、讲究礼仪、不擅长说谎',
    'w': '无。',
    'ph': '害怕被人在公开场合认出落魄的样子。',
  },
  <String, String>{
    'name': '流浪画家',
    'd': '颜料沾在指缝与袖口，帽檐压得很低，背包里永远有速写本。',
    'id': '有些东西用语言说不出来，只能画出来。',
    'p': '同窗米娅｜旧友｜唯一买过我画的人｜现在住在巴黎。',
    'pl': '海边的悬崖｜风很大，光很好｜我在那里画出了最好的一张画。',
    't': '速写本｜已经用了七年｜一路的记录｜里面有几页我自己也不敢再看。',
    'tr': '敏感、厌恶重复、容易走神',
    'w': '膝盖有摔伤。',
    'ph': '对完全空白的地方会感到莫名不安。',
  },
  <String, String>{
    'name': '教堂司事',
    'd': '深色旧外套，脖子上挂着一枚磨得发亮的十字架。说话很慢。',
    'id': '我见过的东西不该存在于这个世界上，但我仍然相信有救赎。',
    'p': '老神父马丁｜引路人｜在我最糟的时候收留了我｜已故。',
    'pl': '旧教堂的地下室｜潮湿的石墙｜我在那里第一次听见不该有的声音。',
    't': '圣经｜扉页有别人写的字｜来源不明｜那句话始终没看懂。',
    'tr': '耐心、习惯祈祷、回避争执',
    'w': '手掌有常年握持留下的厚茧。',
    'ph': '对深夜的钟声极度不安。',
  },
  <String, String>{
    'name': '私家侦探',
    'd': '风衣口袋里塞着记事本和半包烟。习惯站在门口观察再进门。',
    'id': '真相往往不在别人愿意告诉你的地方。',
    'p': '老搭档路易斯｜前警探｜带我入行｜三年前失踪了。',
    'pl': '旧警局后巷｜下过雨的沥青路｜我最后见到路易斯的地方。',
    't': '他的打火机｜银色，有凹痕｜路易斯留下｜我一直在等他回来拿。',
    'tr': '多疑、观察力强、不爱说话',
    'w': '鼻梁有旧伤。',
    'ph': '对长时间无人应答的电话铃声不适。',
  },
  <String, String>{
    'name': '落魄作家',
    'd': '不修边幅，眼睛布满血丝，口袋里总有揉成团的稿纸。',
    'id': '如果我写下的东西是对的，那这个世界就有大问题。',
    'p': '编辑康拉德｜合作者｜唯一愿意读我稿子的人｜一直在催我交稿。',
    'pl': '城郊的小旅馆｜六号房间｜我写出那篇小说的房间。',
    't': '打字机｜二手，缺少一个键｜写作工具｜我怀疑它在夜里自己响过。',
    'tr': '失眠、强迫性记录、畏惧空白',
    'w': '无。',
    'ph': '对打字机的突然声响会剧烈心悸。',
  },
  <String, String>{
    'name': '神秘学者',
    'd': '书房里堆满书，手指上有墨迹。说话时眼神会飘向别处。',
    'id': '知识本身没有善恶，只有是否被承受得住。',
    'p': '已故导师惠特尼｜引路者｜把藏书留给了我｜死因不明。',
    'pl': '大学图书馆禁区｜铁栅栏后｜我在那里找到了导师的笔记。',
    't': '一本无名手稿｜缺页，用陌生文字写成｜导师遗留｜我不敢读完。',
    'tr': '专注、健忘、对日常琐事迟钝',
    'w': '无。',
    'ph': '对特定几何图案会产生眩晕。',
  },
];

/// 背景编辑区（8 项文本 + 预设 + 疯狂表入口）
class BackgroundEditor extends StatefulWidget {
  const BackgroundEditor({
    super.key,
    required this.card,
    required this.onChanged,
    this.showPresets = true,
    this.showMadnessTable = true,
    this.showPhobias = true,
    this.showExtraBlocks = true,
  });

  final Character card;
  final VoidCallback onChanged;

  /// 是否显示「快速套用预设背景」（车卡第 5 步显示；详情页编辑不显示）
  final bool showPresets;

  /// 是否显示「疯狂表」入口
  final bool showMadnessTable;

  /// 是否显示「疯狂症状」文本框（详情页单独有状态面板时可不显示）
  final bool showPhobias;

  /// 是否显示 P2-B2 的四块（经历 / 伙伴 / 克苏鲁神话 / 已学法术）
  final bool showExtraBlocks;

  @override
  State<BackgroundEditor> createState() => _BackgroundEditorState();
}

class _BackgroundEditorState extends State<BackgroundEditor> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  Character get _c => widget.card;

  @override
  void initState() {
    super.initState();
    for (final f in backgroundFields) {
      final k = f['k']!;
      _controllers[k] = TextEditingController(
        text: jsStr(_c.background[k] ?? ''),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 预设 / 疯狂表直接改了 `background`，输入框要跟着刷新
  void syncFromModel() {
    for (final f in backgroundFields) {
      final k = f['k']!;
      final text = jsStr(_c.background[k] ?? '');
      final ctrl = _controllers[k];
      if (ctrl != null && ctrl.text != text) ctrl.text = text;
    }
  }

  void _applyPreset(Map<String, String> p) {
    if (_c.characterName.isEmpty) _c.raw['characterName'] = p['name']!;
    _c.background['description'] = p['d']!;
    _c.background['ideology'] = '信仰 / 人生观 / 价值观 / 政治观点 / 人生目标：\n${p['id']!}';
    _c.background['significantPeople'] = p['p']!;
    _c.background['meaningfulPlaces'] = p['pl']!;
    _c.background['treasuredPossessions'] = p['t']!;
    _c.background['traits'] = p['tr']!;
    _c.background['wounds'] = p['w']!;
    _c.background['phobias'] = p['ph']!;
    // 预设里的恐惧症 / 狂躁症同样进结构化数组（认得出来的才进）
    mad.fromBackground(_c);
    syncFromModel();
    widget.onChanged();
    ScaffoldMessenger.of(context)
        .showSlot(SnackBar(content: Text('已套用预设：${p['name']!}')));
  }

  Future<void> _openMadnessTable() async {
    await showMadnessTableSheet(
      context,
      card: _c,
      onChanged: () {
        syncFromModel();
        widget.onChanged();
      },
    );
    syncFromModel();
  }

  @override
  Widget build(BuildContext context) {
    final fields = backgroundFields
        .where((f) => widget.showPhobias || f['k'] != 'phobias')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showPresets) ...<Widget>[
          SectionCard(
            title: '快速套用预设背景',
            subtitle: '10 套 · 会覆盖下面 8 项文本，可再逐项改',
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (var i = 0; i < backgroundPresets.length; i++)
                  InkWell(
                    key: Key('bg_preset_$i'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _applyPreset(backgroundPresets[i]),
                    child: Pill(text: backgroundPresets[i]['name']!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          title: '角色背景',
          subtitle: '都非必填，可稍后补充',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final f in fields) ...<Widget>[
                FieldLabel(f['label']!),
                TextField(
                  key: Key('bg_field_${f['k']}'),
                  controller: _controllers[f['k']],
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(hintText: f['ph']),
                  onChanged: (v) {
                    _c.background[f['k']!] = v;
                    widget.onChanged();
                  },
                ),
                if (f['k'] == 'significantPeople') ...<Widget>[
                  const SizedBox(height: 6),
                  _SegmentHelper(
                    value: jsStr(_c.background['significantPeople'] ?? ''),
                    onApply: (v) {
                      _c.background['significantPeople'] = v;
                      syncFromModel();
                      widget.onChanged();
                    },
                  ),
                ],
                const SizedBox(height: 14),
              ],
              if (widget.showMadnessTable) ...<Widget>[
                OutlinedButton.icon(
                  key: const Key('btn_madness_table'),
                  onPressed: _openMadnessTable,
                  icon: const Icon(Icons.casino_outlined, size: 16),
                  label: const Text('打开疯狂表 / 随机生成'),
                ),
                const SizedBox(height: 8),
                Text(
                  '选中症状会同时写进「疯狂症状」文本与状态里的结构化症状（${madnessCount(_c)} 条）。'
                  '「疯狂发作」是即时/总结症状（1-8），恐惧症 / 狂躁症来自 100 条子表。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Palette.textMute,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.showExtraBlocks) ...<Widget>[
          const SizedBox(height: 12),
          HistoryEditor(card: _c, onChanged: widget.onChanged),
          const SizedBox(height: 12),
          CompanionsEditor(card: _c, onChanged: widget.onChanged),
          const SizedBox(height: 12),
          MythosEditor(card: _c, onChanged: widget.onChanged),
          const SizedBox(height: 12),
          SpellsEditor(card: _c, onChanged: widget.onChanged),
        ],
      ],
    );
  }
}

/// 「重要之人」的分段填写助手：`关系｜经过｜现状` 三段拼回同一个键
class _SegmentHelper extends StatefulWidget {
  const _SegmentHelper({required this.value, required this.onApply});

  final String value;
  final void Function(String value) onApply;

  @override
  State<_SegmentHelper> createState() => _SegmentHelperState();
}

class _SegmentHelperState extends State<_SegmentHelper> {
  static const List<String> _labels = <String>['关系', '经过', '为何重要'];
  late List<TextEditingController> _ctrls;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctrls = _split().map((s) => TextEditingController(text: s)).toList();
  }

  List<String> _split() {
    final parts = widget.value.split('｜');
    return <String>[
      parts.isNotEmpty ? parts[0] : '',
      parts.length > 1 ? parts[1] : '',
      parts.length > 2 ? parts[2] : '',
    ];
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final joined = _ctrls.map((c) => c.text.trim()).join('｜');
    widget.onApply(joined);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          key: const Key('btn_bg_people_segments'),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _open ? '收起分段填写 ▴' : '分段填写（关系｜经过｜为何重要）▾',
              style: TextStyle(fontSize: 11.5, color: Palette.gold),
            ),
          ),
        ),
        if (_open) ...<Widget>[
          for (var i = 0; i < _ctrls.length; i++) ...<Widget>[
            TextField(
              key: Key('bg_people_seg_$i'),
              controller: _ctrls[i],
              decoration: InputDecoration(hintText: _labels[i], isDense: true),
              onChanged: (_) => _apply(),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }
}
