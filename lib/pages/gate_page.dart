import 'package:flutter/material.dart';

import '../data/gate_status.dart';
import '../data/progress_store.dart';
import '../models/class_course.dart';
import '../models/entry.dart';
import '../models/gate.dart';
import '../models/link_level.dart';
import '../theme.dart';
import '../util/time_util.dart';
import '../widgets/admonition.dart';
import '../widgets/boss_section.dart';
import '../widgets/class_section.dart';
import '../widgets/item_card.dart';

/// 单个门的页面。
///
/// 自上而下：
///   ① 门名 + 解锁状态 + 开放状态
///   ② 解锁条件（默认折叠）
///   ③ 待完成条目卡片
///   ④ BOSS + 通关条件（**仅解锁后显示**）
class GatePage extends StatelessWidget {
  const GatePage({
    super.key,
    required this.gate,
    required this.meta,
    required this.store,
    required this.status,
    required this.statusOf,
    required this.linkLevels,
    required this.classData,
  });

  final Gate gate;
  final MetaTable meta;
  final ProgressStore store;
  final GateStatus status;

  /// 取任意门的状态（用于 auto 类型显示前置门清单）
  final GateStatus Function(String gateId) statusOf;

  /// 这个门的 Link LEVEL 缓和表（可能为 null）
  final GateLinkLevels? linkLevels;

  /// 段位课程数据（AIR 门用）
  final ClassData classData;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _TitleRow(gate: gate, status: status),
        const SizedBox(height: 12),
        _AvailabilityRow(gate: gate),
        const SizedBox(height: 12),
        _ConditionBlock(gate: gate),
        _Body(
          gate: gate,
          meta: meta,
          store: store,
          status: status,
          statusOf: statusOf,
          classData: classData,
        ),
        if (status.unlocked) BossSection(gate: gate, linkLevels: linkLevels),
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

/// 开放状态：门开了没有 / 什么时候开。
class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({required this.gate});

  final Gate gate;

  @override
  Widget build(BuildContext context) {
    final opened = isReleasedNow(gate.releaseDate);
    final when = parseLocalDate(gate.releaseDate);
    // locked 是奖励乐曲专用的状态，不算「门」
    final isReward = gate.isReward;

    final IconData icon;
    final Color color;
    final String text;

    if (opened) {
      icon = Icons.lock_open_outlined;
      color = AppTheme.accent;
      text = '已开放${when != null ? '（${formatLocalDate(when)} 起）' : ''}';
    } else if (isReward) {
      icon = Icons.lock_outline;
      color = AppTheme.warning;
      text = '锁定：全部门通关后显示';
    } else if (when != null) {
      icon = Icons.schedule;
      color = AppTheme.warning;
      text = '未开放（${formatLocalDate(when)} 起）';
    } else {
      icon = Icons.help_outline;
      color = AppTheme.textDim;
      text = '未更新：国服尚未开放，日期未知';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- ② 解锁条件

class _ConditionBlock extends StatelessWidget {
  const _ConditionBlock({required this.gate});

  final Gate gate;

  @override
  Widget build(BuildContext context) {
    return Admonition(
      title: '解锁条件',
      accent: gate.releaseStatus == ReleaseStatus.open ? AppTheme.accent : AppTheme.border,
      badge: gate.conditionSource != 'official' ? '待确认' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdmonitionText(gate.conditionText),
          if (gate.releaseNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            AdmonitionText('⚠️ ${gate.releaseNote}'),
          ],
          if (gate.unresolved != null) ...[
            const SizedBox(height: 8),
            AdmonitionText('⚠️ ${gate.unresolved!}'),
          ],
        ],
      ),
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
    required this.classData,
  });

  final Gate gate;
  final MetaTable meta;
  final ProgressStore store;
  final GateStatus status;
  final GateStatus Function(String gateId) statusOf;
  final ClassData classData;

  @override
  Widget build(BuildContext context) {
    switch (gate.tracking) {
      case TrackingKind.songs:
        if (gate.requirement.type == 'playAnyOfEach') return _buildGrouped(context);
        return _buildFlat(context);
      case TrackingKind.items:
        return _buildFlat(context);
      case TrackingKind.classes:
        return _buildClasses(context);
      case TrackingKind.auto:
        return _buildPrerequisites(context);
      case TrackingKind.remainingHp:
      case TrackingKind.manual:
        return _buildManualConfirm(context, hint: null);
    }
  }

  /// AIR 门：段位课程区 + 手动确认（当前课程是占位数据，门的解锁以手动确认为准）
  Widget _buildClasses(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '段位课程',
          trailing: status.unlocked ? '已解锁' : '未达成',
          trailingColor: status.unlocked ? AppTheme.accent : AppTheme.textDim,
        ),
        ClassSection(
          gateId: gate.id,
          data: classData,
          meta: meta,
          store: store,
        ),
        const SizedBox(height: 18),
        _buildManualConfirm(
          context,
          hint: '课程的组曲勾选只是记录进度，方便你看清还差哪几组。\n'
              '因为段位课程还是占位数据，AIR 门是否已解锁请以这个开关为准。',
        ),
      ],
    );
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
          onLongPress: (e) => showEntryDetail(context, e),
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

  /// 分组卡片：PARADISE 的「每位曲师任打一首」。
  ///
  /// 注意：**每组可以打多首**，只要该组里有一首打过就算这组完成。
  /// 所以这里是普通的多选，不是「每组只能选一个」。
  Widget _buildGrouped(BuildContext context) {
    final ticked = store.tickedOf(gate.id);
    final blocks = <Widget>[];

    for (final group in gate.requirement.groups) {
      final entries = _resolve(group.itemKeys);
      if (entries.isEmpty) continue;
      final doneCount = entries.where((e) => ticked.contains(e.key)).length;
      final completed = doneCount > 0;

      blocks.add(
        GroupHeader(
          label: group.key,
          progress: completed ? '已打 $doneCount 首' : '还没打过',
          completed: completed,
        ),
      );
      blocks.add(
        ItemGrid(
          entries: entries,
          isDone: (e) => ticked.contains(e.key),
          // 和普通曲目一样：点一下打勾，再点取消
          onTap: (e) => store.toggle(gate.id, e.key),
          onLongPress: (e) => showEntryDetail(context, e),
        ),
      );
      blocks.add(const SizedBox(height: 18));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '每位曲师任打一首（可多打）',
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
                  gateShortName(id),
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

  /// 手动确认：AIR（段位）/ CRYSTAL（条件未知）/ UNIVERSE（剩余血量）
  Widget _buildManualConfirm(BuildContext context, {required String? hint}) {
    final done = store.isManualDone(gate.id);

    final String body;
    if (hint != null) {
      body = hint;
    } else if (gate.id == 'crystal') {
      body = '国服没有队伍功能，这个门的解锁条件与日服不同，目前无法确定。\n'
          '请在实际开门后打开此开关。';
    } else if (gate.id == 'universe') {
      body = '通关 RE:VERSE 时，剩余血量需要达到指定值才算通关门。\n'
          '该指定值按日期缓和，请在达成后打开此开关。';
    } else {
      body = '请确认已满足上面的解锁条件后，打开此开关。';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '达成后标记'),
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
                body,
                style: const TextStyle(fontSize: 13, height: 1.6, color: AppTheme.textSecondary),
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

// ---------------------------------------------------------------- 共用

/// 前置门清单里只显示短名。
String gateShortName(String id) {
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

/// 长按卡片看详情
void showEntryDetail(BuildContext context, Entry e) {
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
            if (e.artist != null && e.artist!.isNotEmpty) _detailRow('曲师', e.artist!),
            if (e.works != null && e.works!.isNotEmpty) _detailRow('作品', e.works!),
            if (e.genre != null && e.genre!.isNotEmpty) _detailRow('分类', e.genre!),
            if (e.levels.isNotEmpty) _detailRow('难度', DifficultyStyle.format(e.levels)),
            // 落雪查分器的 song_id，导入功能要拿它匹配成绩
            _detailRow('linkId', e.key),
            _detailRow('游戏内 id', '${e.id}'),
            // 图片资源路径。排查「图片丢失」时就是靠它定位的
            _detailRow('图片', e.image ?? '（无）'),
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

Widget _detailRow(String label, String value) {
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
          child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        ),
      ],
    ),
  );
}
