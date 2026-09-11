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
/// 课程数据来自 `condition/class/course/*/Course.xml`（真实数据，36 个组曲），
/// 不再是占位符；只有当 `classes.json` 的 `placeholder` 为 true 时才显示提醒条。
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
              _courseBlock(course, doneCourses.contains(course.key)),
          ],
        ),
      ),
    );
  }

  // 组曲的槽有三种：固定曲目（能显示曲绘）、等级随机、曲池随机。
  // 后两种没有具体曲目，改用「class/random」「class/random in range」下那两张封面 + 文字说明。
  //
  // 遍历顺序就是 slots 的顺序（游戏里 1→2→3），**没有**按「先固定曲再随机槽」重排。
  // 渲染时固定曲走 ItemGrid、随机槽走 _RandomSlotGrid（原因见 _slotGrid 的注释），
  // 所以万一某组曲是混排的（当前 36 个组曲都不是），会显示成「先全部固定曲、再全部随机槽」，
  // 但每一类内部仍保持原始相对顺序。
  Widget _courseBlock(ClassCourse course, bool done) {
    final entries = <Entry>[];
    final randomSlots = <ClassSlot>[];
    final diffs = <String>[];
    for (final slot in course.slots) {
      if (slot.isFixed) {
        final key = slot.linkId;
        final e = key == null ? null : widget.meta[key];
        if (e != null) entries.add(e); // 数据缺失就跳过，别渲染成空白卡
        diffs.add(slot.difficulty ?? '');
      } else {
        randomSlots.add(slot);
      }
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
              if (course.randomCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '${course.fixedCount}+${course.randomCount}随机',
                    style: const TextStyle(fontSize: 10.5, color: AppTheme.textFaint),
                  ),
                ),
            ],
          ),
          children: [
            _slotGrid(entries, randomSlots),
            const SizedBox(height: 8),
            // 难度标签
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < diffs.length; i++)
                  if (diffs[i].isNotEmpty) _DifficultyTag(diffs[i]),
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

  /// 组曲内的槽卡片（只读）。
  ///
  /// 为什么不用一个 `Wrap` 把固定曲和随机卡混排：`ItemCard` 内部用了 `Expanded`
  /// （文字区自适应高度），而 `Wrap` 给子项的纵向约束是 unbounded，
  /// `Expanded` 在没有高度上限时会直接抛异常。
  /// 所以这里复用 `ItemGrid`——它用 `childAspectRatio` 给每张卡算出确定高度。
  ///
  /// `ItemGrid` 内部会「未完成在前」，但传入的 `isDone` 永远返回 false，
  /// 分组结果就是原始顺序，正好符合「槽 1→2→3」的要求。
  Widget _slotGrid(List<Entry> entries, List<ClassSlot> randomSlots) {
    if (entries.isEmpty && randomSlots.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entries.isNotEmpty)
            ItemGrid(entries: entries, isDone: (_) => false, onTap: (_) {}),
          if (entries.isNotEmpty && randomSlots.isNotEmpty) const SizedBox(height: 10),
          if (randomSlots.isNotEmpty)
            _RandomSlotGrid(slots: randomSlots, childAspectRatio: _randomAspect),
        ],
      ),
    );
  }

  /// 随机槽卡片的宽高比。比 `ItemGrid` 的 0.62 略大，因为随机卡没有曲名/曲师两行文字，
  /// 只需要一行小字。保持接近是为了和固定曲卡视觉一致。
  static const double _randomAspect = 0.78;
}

/// 随机槽的小网格。列数与 `ItemGrid` 用同一套算法，保证随机卡和固定曲卡上下对齐。
class _RandomSlotGrid extends StatelessWidget {
  const _RandomSlotGrid({required this.slots, required this.childAspectRatio});

  final List<ClassSlot> slots;
  final double childAspectRatio;

  static const double _minTile = 104;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var cols = ((constraints.maxWidth + _gap) / (_minTile + _gap)).floor();
        if (cols < 2) cols = 2;
        if (cols > 6) cols = 6;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: _gap,
            mainAxisSpacing: _gap,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: slots.length,
          itemBuilder: (context, i) => _RandomSlotCard(slot: slots[i]),
        );
      },
    );
  }
}

/// 随机槽的卡片：用 `class/random` 与 `class/random in range` 的封面 + 文字。
///
/// - 等级随机（`randomRange`）→ 大字写**游戏内等级**（`11+` / `13+ ~ 14`），
///   小字写「等级随机」。用户明确要求：写真实等级，不要写内部 id（19/20/21）。
/// - 曲池随机（`randomPool`）→ 大字写「范围内随机选择」（用户指定原文），
///   小字写「N 选 1」。
///
/// 结构故意和 `ItemCard` 一致（封面 + 下方文字区都靠 `Expanded` 撑），
/// 这样和固定曲卡放在同一个网格体系里高度相同、看起来是一套东西。
class _RandomSlotCard extends StatelessWidget {
  const _RandomSlotCard({required this.slot});

  final ClassSlot slot;

  @override
  Widget build(BuildContext context) {
    // 等级随机用强调色（等级是要记住的信息），曲池随机用弱化色（只知道「范围内随机」）
    final accent =
        slot.kind == ClassSlotKind.randomRange ? AppTheme.accent : AppTheme.textDim;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            // 与 ItemCard 的封面比例一致（0.82），保证文字区高度也对得上
            aspectRatio: 0.82,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (slot.image == null)
                  ColoredBox(color: AppTheme.surfaceHigh)
                else
                  Image.asset(
                    slot.image!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(color: AppTheme.surfaceHigh),
                  ),
                // 封面图上半部是「!」/「?」图标，所以文字压在下半部，
                // 并加一层半透明底，避免盖住图标也避免文字看不清。
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    color: AppTheme.bg.withValues(alpha: 0.72),
                    child: Text(
                      slot.headline,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: slot.kind == ClassSlotKind.randomPool ? 10 : 13,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  slot.sublabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, height: 1.25, color: AppTheme.textFaint),
                ),
              ),
            ),
          ),
        ],
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
              '正常情况下不会看到这条——它只在 classes.json 的 placeholder 为 true 时出现，'
              '说明同步到的是旧数据或生成失败。',
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
