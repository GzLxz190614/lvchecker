import 'package:flutter/material.dart';

import '../data/gate_status.dart';
import '../data/progress_store.dart';
import '../models/entry.dart';
import '../models/gate.dart';
import '../theme.dart';
import '../widgets/admonition.dart';
import '../widgets/boss_section.dart';
import '../widgets/item_card.dart';

/// 单个门的页面。
///
/// 自上而下：① 门名 + 状态  ② 解锁条件（可折叠）  ③ 待完成条目卡片
///          ④ BOSS（**仅解锁后显示**）
class GatePage extends StatelessWidget {
  const GatePage({
    super.key,
    required this.gate,
    required this.meta,
    required this.store,
    required this.status,
    required this.statusOf,
  });

  final Gate gate;
  final MetaTable meta;
  final ProgressStore store;
  final GateStatus status;

  /// 取任意门的状态（用于 auto 类型显示前置门清单）
  final GateStatus Function(String gateId) statusOf;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _TitleRow(gate: gate, status: status),
        const SizedBox(height: 14),
        _ConditionBlock(gate: gate),
        _Body(gate: gate, meta: meta, store: store, status: status, statusOf: statusOf),
        if (status.unlocked) BossSection(gate: gate),
      ],
    );
  }
}

// ---------------------------------------------------------------- ① 标题行

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.gate, required this.status});

  final Gate gate;
  final GateStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusStyle();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                gate.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
              ),
              if (status.totalCount > 0 && !gate.isReward) ...[
                const SizedBox(height: 4),
                Text(
                  status.progressLabel,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textDim),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }

  (String, Color) _statusStyle() {
    if (status.unlocked) return ('已解锁', AppTheme.accent);
    switch (gate.releaseStatus) {
      case ReleaseStatus.open:
        return ('未完成', AppTheme.warning);
      case ReleaseStatus.locked:
        return ('锁定', AppTheme.warning);
      case ReleaseStatus.notYetOpen:
        return ('未更新', AppTheme.textDim);
    }
  }
}

// ---------------------------------------------------------------- ② 解锁条件

class _ConditionBlock extends StatelessWidget {
  const _ConditionBlock({required this.gate});

  final Gate gate;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      AdmonitionText(gate.conditionText),
      if (gate.releaseNote.isNotEmpty) ...[
        const SizedBox(height: 8),
        AdmonitionText('⚠️ ${gate.releaseNote}'),
      ],
      if (gate.unresolved != null) ...[
        const SizedBox(height: 8),
        AdmonitionText('⚠️ ${gate.unresolved!}'),
      ],
      if (gate.conditionOriginal != null && gate.conditionOriginal!.trim().isNotEmpty) ...[
        const SizedBox(height: 10),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 6),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            iconColor: AppTheme.textDim,
            collapsedIconColor: AppTheme.textFaint,
            title: const Text(
              '查看游戏原文',
              style: TextStyle(fontSize: 12, color: AppTheme.textFaint),
            ),
            children: [AdmonitionText(gate.conditionOriginal!, dim: true)],
          ),
        ),
      ],
    ];

    return Admonition(
      title: '解锁条件',
      accent: gate.releaseStatus == ReleaseStatus.open ? AppTheme.accent : AppTheme.border,
      badge: gate.conditionSource != 'official' ? '待确认' : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

// ---------------------------------------------------------------- ③ 主体

class _Body extends StatelessWidget {
  const _Body({
    required this.gate,
    required this.meta,
    required this.store,
    required this.status,
    required this.statusOf,
  });

  final Gate gate;
  final MetaTable meta;
  final ProgressStore store;
  final GateStatus status;
  final GateStatus Function(String gateId) statusOf;

  @override
  Widget build(BuildContext context) {
    switch (gate.tracking) {
      case TrackingKind.songs:
        if (gate.requirement.type == 'playAnyOfEach') return _buildGrouped(context);
        return _buildFlat(context);
      case TrackingKind.items:
        return _buildFlat(context);
      case TrackingKind.classes:
        return const _PlaceholderBody(
          text: '段位课程数据尚未提供。\n在拿到课程清单之前，这个门请在机台上确认后手动标记。',
        );
      case TrackingKind.auto:
        return _buildPrerequisites(context);
      case TrackingKind.remainingHp:
      case TrackingKind.manual:
        return _buildManual(context);
    }
  }

  List<Entry> _resolve(List<String> keys) {
    final list = <Entry>[];
    for (final k in keys) {
      final e = meta[k];
      if (e != null) list.add(e);
    }
    return list;
  }

  /// 单组卡片：playAll / items
  Widget _buildFlat(BuildContext context) {
    final keys =
        gate.tracking == TrackingKind.items ? gate.requirement.itemKeys : gate.requirement.songKeys;
    final entries = _resolve(keys);
    if (entries.isEmpty) {
      return const _PlaceholderBody(text: '这个门没有需要勾选的条目。');
    }

    // RE:VERSE 的 11 首是「拿到地图内所有歌」——实际通关地图就等于全打了，
    // 所以给一个快捷全勾，省得逐首点。
    final showTickAll = gate.id == 'reverse';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: gate.tracking == TrackingKind.items ? '需要完成的条目' : '需要完成的曲目',
          trailing: status.progressLabel,
          trailingColor: status.unlocked ? AppTheme.accent : AppTheme.textDim,
        ),
        ItemGrid(
          entries: entries,
          isDone: (e) => store.isTicked(gate.id, e.key),
          onTap: (e) => store.toggle(gate.id, e.key),
          onLongPress: (e) => _showDetail(context, e),
        ),
        if (showTickAll) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => store.tickAll(gate.id, keys),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('整张地图已完成（一次勾上全部）'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              side: const BorderSide(color: AppTheme.border),
              minimumSize: const Size.fromHeight(42),
            ),
          ),
        ],
      ],
    );
  }

  /// 分组卡片：PARADISE 的「每位曲师各选一首」
  Widget _buildGrouped(BuildContext context) {
    final chosen = store.groupTickedOf(gate.id);
    final blocks = <Widget>[];

    for (final group in gate.requirement.groups) {
      final entries = _resolve(group.itemKeys);
      if (entries.isEmpty) continue;
      final picked = chosen[group.key];
      final completed = picked != null;

      blocks.add(
        GroupHeader(
          label: group.key,
          progress: completed ? '已选 1' : '未选',
          completed: completed,
        ),
      );
      blocks.add(
        ItemGrid(
          entries: entries,
          // 该组已选中的那首显示为完成态
          isDone: (e) => e.key == picked,
          onTap: (e) => store.selectInGroup(gate.id, group.key, e.key),
          onLongPress: (e) => _showDetail(context, e),
        ),
      );
      blocks.add(const SizedBox(height: 18));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '每位曲师任选一首',
          trailing: status.progressLabel,
          trailingColor: status.unlocked ? AppTheme.accent : AppTheme.textDim,
        ),
        ...blocks,
      ],
    );
  }

  /// 前置门清单：X-VERSE / 奖励乐曲
  Widget _buildPrerequisites(BuildContext context) {
    final rows = <Widget>[];
    for (final id in gate.prerequisites) {
      final s = statusOf(id);
      final name = _gateName(id);
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(
                s.unlocked ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 17,
                color: s.unlocked ? AppTheme.accent : AppTheme.textFaint,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: s.unlocked ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              ),
              if (!s.unlocked && s.totalCount > 0)
                Text(s.progressLabel,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textFaint)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '前置门',
          trailing: status.progressLabel,
          trailingColor: status.unlocked ? AppTheme.accent : AppTheme.textDim,
        ),
        ...rows,
      ],
    );
  }

  /// 手动确认：CRYSTAL（条件未知）/ UNIVERSE（剩余血量）
  Widget _buildManual(BuildContext context) {
    final done = store.isManualDone(gate.id);
    final isUnknown = gate.id == 'crystal';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: isUnknown ? '在机台上确认后标记' : '达成后标记'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUnknown
                    ? '国服没有队伍功能，这个门的解锁条件与日服不同，目前无法确定。\n请在实际开门后打开此开关。'
                    : '请确认已满足上述条件后打开此开关。',
                style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      done ? '已标记为达成' : '尚未达成',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: done ? AppTheme.accent : AppTheme.textDim,
                      ),
                    ),
                  ),
                  Switch(
                    value: done,
                    // 不用 activeColor / activeThumbColor：
                    // 前者在 Flutter 3.31 起弃用，后者要 3.35 才有。
                    // thumbColor + WidgetStateProperty 在 3.19 之后都可用。
                    thumbColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppTheme.accent
                          : const Color(0xFF8A90A8),
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? AppTheme.accent.withValues(alpha: 0.35)
                          : AppTheme.surfaceHigh,
                    ),
                    onChanged: (v) => store.setManualDone(gate.id, v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _gateName(String id) {
    // 前置门清单里只显示短名。用 meta 里查不到，所以直接做一层映射，
    // 兜底回退到 id 本身。
    const short = {
      'origin': 'ORIGIN',
      'air': 'AIR',
      'star': 'STAR',
      'amazon': 'AMAZON',
      'crystal': 'CRYSTAL',
      'paradise': 'PARADISE',
      'new': 'NEW',
      'sun': 'SUN',
      'luminous': 'LUMINOUS',
      'verse': 'VERSE',
      'xverse': 'X-VERSE',
      'reverse': 'RE:VERSE',
      'universe': 'UNIVERSE',
    };
    return short[id] ?? id;
  }

  void _showDetail(BuildContext context, Entry e) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: Text(e.title, style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.artist != null && e.artist!.isNotEmpty) _row('曲师', e.artist!),
              if (e.works != null && e.works!.isNotEmpty) _row('作品', e.works!),
              if (e.genre != null && e.genre!.isNotEmpty) _row('分类', e.genre!),
              if (e.levels.isNotEmpty) _row('难度', DifficultyStyle.format(e.levels)),
              // 落雪查分器的 song_id，导入功能要用它匹配成绩
              _row('linkId', e.key),
              _row('游戏内 id', '${e.id}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textFaint)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderBody extends StatelessWidget {
  const _PlaceholderBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, height: 1.6, color: AppTheme.textSecondary),
      ),
    );
  }
}
