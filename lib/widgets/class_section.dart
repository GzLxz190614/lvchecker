import 'package:flutter/material.dart';

import '../data/progress_store.dart';
import '../models/class_course.dart';
import '../models/entry.dart';
import '../theme.dart';
import 'item_card.dart';

/// AIR 门的段位课程区（双层折叠框）。
///
/// 交互要点：**完成的目标是整个组曲**，不是逐首打勾。
/// 因为缎带条件是「通关组曲」，组曲内的 3 首只是告诉你这个组曲要打什么，
/// 所以它们是**只读展示**；点一下组曲标题那一行才算完成。
///
/// 当前段位课程还是占位数据（`classes.json` 的 placeholder 为 true），
/// 所以页面上会显示一条提醒，且门是否解锁仍以「手动确认」为准。
class ClassSection extends StatefulWidget {
  const ClassSection({
    super.key,
    required this.gateId,
    required this.data,
    required this.meta,
    required this.store,
  });

  final String gateId;
  final ClassData data;
  final MetaTable meta;
  final ProgressStore store;

  @override
  State<ClassSection> createState() => _ClassSectionState();
}

class _ClassSectionState extends State<ClassSection> {
  @override
  Widget build(BuildContext context) {
    final doneCourses = widget.store.courseDoneOf(widget.gateId);
    final ribbon = widget.data.ribbonAchieved(doneCourses);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.data.placeholder) const _PlaceholderBanner(),
        if (ribbon) const _RibbonBanner(),
        for (final tier in widget.data.tiers) _tierBlock(tier, doneCourses),
        const SizedBox(height: 4),
        const Text(
          '完成任一 CLASS 内的所有组曲即可获得缎带。'
          '组曲内 3 首仅作展示，点组曲标题即标记该组曲通关。',
          style: TextStyle(fontSize: 11, color: AppTheme.textFaint, height: 1.5),
        ),
      ],
    );
  }

  Widget _tierBlock(ClassTier tier, Set<String> doneCourses) {
    final done = widget.data.doneIn(tier, doneCourses);
    final total = tier.courses.length;
    final complete = widget.data.tierComplete(tier, doneCourses);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: tier.color, width: 4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // 去掉 ExpansionTile 默认的分隔线，避免和自定义边框打架
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          iconColor: AppTheme.textDim,
          collapsedIconColor: AppTheme.textFaint,
          title: Row(
            children: [
              Text(
                tier.label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: tier.color,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  total == 0 ? '（暂无组曲数据）' : '$done / $total 组曲',
                  style: TextStyle(
                    fontSize: 12,
                    color: complete ? AppTheme.accent : AppTheme.textDim,
                    fontWeight: complete ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (complete) const _Badge(text: '已达成缎带条件'),
            ],
          ),
          children: [
            for (final course in tier.courses)
              _courseBlock(tier, course, doneCourses.contains(course.key)),
          ],
        ),
      ),
    );
  }

  Widget _courseBlock(ClassTier tier, ClassCourse course, bool done) {
    final entries = <Entry>[];
    for (final k in course.songKeys) {
      final e = widget.meta[k];
      if (e != null) entries.add(e);
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: done ? AppTheme.accent.withValues(alpha: 0.45) : AppTheme.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          iconColor: AppTheme.textDim,
          collapsedIconColor: AppTheme.textFaint,
          title: Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: done ? AppTheme.accent : AppTheme.textFaint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  course.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: done ? AppTheme.accent : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          children: [
            // 只读展示这 3 首。用和曲目卡片一样的样式，保持视觉一致。
            IgnorePointer(
              child: ItemGrid(
                entries: entries,
                isDone: (_) => false,
                onTap: (_) {},
              ),
            ),
            const SizedBox(height: 4),
            // 难度标签
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < course.songKeys.length; i++)
                  if (i < course.difficulties.length && course.difficulties[i].isNotEmpty)
                    _DifficultyTag(course.difficulties[i]),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => widget.store.toggleCourse(widget.gateId, course.key),
              icon: Icon(done ? Icons.undo : Icons.check, size: 17),
              label: Text(done ? '取消标记' : '标记本组曲已通关'),
              style: OutlinedButton.styleFrom(
                foregroundColor: done ? AppTheme.textDim : AppTheme.accent,
                side: BorderSide(
                  color: done ? AppTheme.border : AppTheme.accent.withValues(alpha: 0.5),
                ),
                minimumSize: const Size.fromHeight(38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyTag extends StatelessWidget {
  const _DifficultyTag(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final key = name.toLowerCase();
    final color = DifficultyStyle.color[key] ?? AppTheme.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        DifficultyStyle.label[key] ?? name,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.3),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.accent),
      ),
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  const _PlaceholderBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: AppTheme.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '段位课程为占位数据，组曲名与曲目都还不是真的。\n'
              '等级与配色已按游戏设定填好。拿到课程数据后同步即可更新，不用重装。',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: AppTheme.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonBanner extends StatelessWidget {
  const _RibbonBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.workspace_premium, size: 16, color: AppTheme.accent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '已有一个 CLASS 的组曲全部完成，即已获得缎带。',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}
