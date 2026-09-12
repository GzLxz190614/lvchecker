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
/// 曲名和曲师名都用 [MarqueeText]：卡片很窄，长名字放不下。
///
/// 之前只有曲名滚动、曲师名最多两行 ellipsis 截断，结果是
/// `あべにゅうぷろじぇくと feat.佐倉 紗織　produced by ave;new`（44 字符）
/// 这类曲师名永远读不全。既然滚动机制已经有了，没理由只给曲名用。
class _ScrollableText extends StatelessWidget {
  const _ScrollableText({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MarqueeText(
            text: entry.title,
            style: const TextStyle(
              fontSize: 13,
              height: 1.25,
              color: AppTheme.textPrimary,
            ),
          ),
          if (entry.caption.isNotEmpty) ...[
            const SizedBox(height: 4),
            MarqueeText(
              text: entry.caption,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.25,
                color: AppTheme.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一行文字，放不下就**自动左右循环滚动**（跑马灯）。
///
/// 为什么不用横向滚动条：卡片很窄，手动左右滑很难精确操作，
/// 而且会和外面门页的上下滚动抢手势。自动循环更适合「一眼看全曲名」。
///
/// 实现要点：
/// - 用 [TextPainter] 量出文字真实宽度，只有**超出可用宽度**时才启动动画；
///   放得下就静止显示，不会平白动起来。
/// - 动作用 [AnimationController.repeat] 的 `reverse: true`：
///   一条 0→1 的直线动画镜像播放，等于「推到末尾再弹回起点」，
///   首尾都能读到，语义也比手动 forward/reverse 清晰。
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.velocity = 22,
  });

  final String text;
  final TextStyle style;

  /// 滚动速度（逻辑像素 / 秒），用来把溢出距离换算成时长
  final double velocity;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  /// 已缓存的测量结果，只为 (text, style, 可用宽度) 组合算一次
  TextPainter? _tp;
  double _measuredForWidth = -1;
  double _overflow = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _tp = null;
      _measuredForWidth = -1;
    }
  }

  /// 返回溢出宽度。同一宽度下复用缓存，不在 build 里反复测量。
  double _measure(double availableWidth) {
    var tp = _tp;
    if (tp == null || (_measuredForWidth - availableWidth).abs() > 0.5) {
      tp = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      _tp = tp;
      _measuredForWidth = availableWidth;
      _overflow = (tp.width - availableWidth).clamp(0.0, double.infinity);

      if (_overflow > 0.5) {
        final ms = (_overflow / widget.velocity * 1000).round();
        _c.duration = Duration(milliseconds: ms.clamp(900, 9000));
        if (!_c.isAnimating) _c.repeat(reverse: true);
      } else if (_c.isAnimating) {
        _c.stop();
        _c.value = 0;
      }
    }
    return _overflow;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflow = _measure(constraints.maxWidth);
        final available = constraints.maxWidth;

        final text = AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Transform.translate(
            offset: Offset(-overflow * _c.value, 0),
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              style: widget.style,
            ),
          ),
        );

        if (overflow <= 0.5) {
          // 放得下：静止显示，不裁剪
          return Align(alignment: Alignment.centerLeft, child: text);
        }

        // ⚠️ 这里的宽度必须是**可用宽度**，不能让它收缩到文字宽度。
        //
        // 之前的写法是 `SizedBox(height: lineHeight, child: ClipRect(child: Align(...)))`，
        // 只限了高度没限宽度，而 `Align` 在**有界**约束下会收缩到子项的固有宽度
        // （只有在无界约束下才扩展到最大）。于是 ClipRect 被撑成了整段文字的宽度，
        // 裁剪框跟着文字一起平移 —— 表现就是「字在动，但右边永远是空白，
        // 看不到被遮挡的部分」。给 SizedBox 显式定宽之后，裁剪框才会固定在
        // 可用宽度上，文字在里面平移，右边的字才会真正露出来。
        //
        // 高度不用手写：maxLines: 1 + softWrap: false 保证渲染就是一行，
        // 高度由子项决定（写死反而可能和实际行高差一点，导致上下被切）。
        return SizedBox(
          width: available,
          child: ClipRect(
            child: Align(alignment: Alignment.centerLeft, child: text),
          ),
        );
      },
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
    this.childAspectRatio = _childAspectRatio,
    this.minTile = _minTile,
  });

  final List<Entry> entries;
  final bool Function(Entry) isDone;
  final void Function(Entry) onTap;
  final void Function(Entry)? onLongPress;

  /// 每张卡的宽高比。默认 0.62（见下面的说明）；段位随机槽那类「没有曲名/曲师」的卡片
  /// 可以传更大的值，免得文字区空一大块。
  final double childAspectRatio;

  /// 单张卡片的最小宽度（含间距）
  final double minTile;

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
        var cols = ((width + _gap) / (minTile + _gap)).floor();
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
