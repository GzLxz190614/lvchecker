import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../theme.dart';

/// 「图片 + 名称」通用卡片。**点一下即切换完成状态。**
///
/// 这是乐曲、角色、服装、段位组曲共用的唯一卡片样式。
///
/// 排行要点：
/// - 曲名最长 22 个全角字符、曲师名最长 44 字符，**不做字符数截断**，
///   由 Text 按真实可用宽度换行；文字区**可滚动**，所以再长也读得全。
/// - 图片加载失败时，错误提示里**带上资源路径**。之前出现过「全部显示图片丢失」
///   但不知道是哪个 key 的问题，把路径显示出来能一眼看出是路径错还是没打包进去。
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
          children: [
            // 图片区固定为接近正方形（0.82 能让文字区拿到约 55dp）。
            // 不写 1.0 是因为文字区必须留够高度，否则长曲名会把曲师挤出去。
            AspectRatio(
              aspectRatio: 0.82,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CardImage(path: entry.image),
                  if (done) const _DoneOverlay(),
                ],
              ),
            ),
            Expanded(child: _ScrollableText(entry: entry)),
          ],
        ),
      ),
    );
  }
}

/// 卡片的文字区。
///
/// 关键点：**没有省略号**。曲名最长有 25 个全角字符
/// （`今ぞ♡崇め奉れ☆オマエらよ！！～姫の秘メタル渇望～`），在卡片宽度下要占 3 行，
/// 会把曲师名挤掉。这里用两条约束同时解决：
///   1. 文字区可滚动（配右侧细滚动条），再长也读得全，且曲师永远在滚动范围内；
///   2. 底部加一道渐隐遮罩，暗示「下面还有内容」。
class _ScrollableText extends StatelessWidget {
  const _ScrollableText({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scrollbar(
          thumbVisibility: false,
          radius: const Radius.circular(3),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 曲名：完整换行，不截断
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.28,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (entry.caption.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  // 曲师：也完整换行。最长的曲师名有 29 个半角宽度
                  // （`あべにゅうぷろじぇくと feat.佐倉 紗織　produced by ave;new`）
                  Text(
                    entry.caption,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.32,
                      color: AppTheme.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 底部渐隐：提示内容还没到底
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 12,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.surface.withValues(alpha: 0.0),
                    AppTheme.surface.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
      // 图片缺失时不要炸掉整个页面，并把资源路径显示出来便于定位
      errorBuilder: (_, error, __) => Container(
        color: AppTheme.surfaceHigh,
        padding: const EdgeInsets.all(5),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, size: 18, color: Color(0xFF8A5A5A)),
            const SizedBox(height: 4),
            Text(
              path!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 8, color: Color(0xFF8A5A5A), height: 1.2),
            ),
          ],
        ),
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
/// **排序规则：未完成的在前，已完成的沉到最后**（同组内保持原顺序）。
/// 所以第一屏永远是「还差什么」，已完成的往下滚才看得到。
class ItemGrid extends StatelessWidget {
  const ItemGrid({
    super.key,
    required this.entries,
    required this.isDone,
    required this.onTap,
    this.onLongPress,
  });

  final List<Entry> entries;
  final bool Function(Entry) isDone;
  final void Function(Entry) onTap;
  final void Function(Entry)? onLongPress;

  /// 单张卡片的最小宽度（含间距）
  static const double _minTile = 104;
  static const double _gap = 10;

  /// 卡片宽高比。
  ///
  /// 取值考虑：图片区是 0.82 宽高比（见 ItemCard），剩下的高度归文字区。
  /// 0.62 时约 640dp 高的屏上，三列布局每张卡约 168dp 高，
  /// 文字区能拿到约 55dp —— 够放「曲名 2 行 + 曲师 1 行」，
  /// 更长的曲名靠滚动看，曲师不会被挤出去。
  static const double _childAspectRatio = 0.62;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    // 未完成在前。用「稳定分组」而不是 sort，保证同状态内顺序不变
    final pending = <Entry>[];
    final finished = <Entry>[];
    for (final e in entries) {
      (isDone(e) ? finished : pending).add(e);
    }
    final ordered = [...pending, ...finished];

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
            childAspectRatio: _childAspectRatio,
          ),
          itemCount: ordered.length,
          itemBuilder: (context, i) {
            final e = ordered[i];
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
