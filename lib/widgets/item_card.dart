import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../theme.dart';

/// 「图片 + 名称」通用卡片。**点一下即切换完成状态。**
///
/// 这是乐曲、角色、服装、段位组曲共用的唯一卡片样式。
///
/// 排版要点（M0 预览时踩过的坑）：
/// 曲名最长可达 22 个全角字符，曲师名可达 44 字符。**绝不能按固定字符数截断**——
/// 实测 `今ぞ♡崇め奉れ☆オマエらよ！！～姫の秘メタル渇望～` 这种名字按字数截会读不全，
/// 按字数留宽又会溢出到相邻卡片。这里统一交给 Text 的 maxLines + ellipsis，
/// 由 Flutter 按真实可用宽度自己算。
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.entry,
    required this.done,
    required this.onTap,
    this.onLongPress,
  });

  final Entry entry;
  final bool done;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CardImage(path: entry.image),
                  if (done) const _DoneOverlay(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (entry.caption.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty) {
      return Container(
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child: const Text('无图', style: TextStyle(color: Color(0xFF666E88), fontSize: 13)),
      );
    }
    return Image.asset(
      path!,
      fit: BoxFit.cover,
      // 图片缺失时不要炸掉整个页面
      errorBuilder: (_, __, ___) => Container(
        color: AppTheme.surfaceHigh,
        alignment: Alignment.center,
        child: const Text('图片缺失', style: TextStyle(color: Color(0xFF666E88), fontSize: 12)),
      ),
    );
  }
}

/// 完成态遮罩：半透明白色 + 居中「已完成」
class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: const Text(
        '已完成',
        style: TextStyle(
          color: Color(0xFF1A1A24),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 自适应列数的卡片网格。
///
/// 列数由可用宽度算出来（按 300×300 曲绘的观感定最小宽度），
/// 不写死列数，这样不同屏宽都不会出现「卡片太扁」。
class ItemGrid extends StatelessWidget {
  const ItemGrid({super.key, required this.entries, required this.isDone, required this.onTap, this.onLongPress});

  final List<Entry> entries;
  final bool Function(Entry) isDone;
  final void Function(Entry) onTap;
  final void Function(Entry)? onLongPress;

  /// 单张卡片的最小宽度（含间距）
  static const double _minTile = 104;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var cols = ((width + _gap) / (_minTile + _gap)).floor();
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
            childAspectRatio: 0.72,
          ),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            return ItemCard(
              entry: e,
              done: isDone(e),
              onTap: () => onTap(e),
              onLongPress: onLongPress == null ? null : () => onLongPress!(e),
            );
          },
        );
      },
    );
  }
}

/// 区块标题：左侧标题 + 右侧进度
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing, this.trailingColor});

  final String title;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC9CFE4),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: trailingColor ?? AppTheme.textDim,
              ),
            ),
        ],
      ),
    );
  }
}

/// 分组小标题（PARADISE 门的每位曲师）
class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.label, required this.progress, required this.completed});

  final String label;
  final String progress;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.circle_outlined,
            size: 15,
            color: completed ? AppTheme.accent : AppTheme.textFaint,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: completed ? AppTheme.accent : const Color(0xFFC9CFE4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(progress, style: const TextStyle(fontSize: 12, color: AppTheme.textFaint)),
        ],
      ),
    );
  }
}
