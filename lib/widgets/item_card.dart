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
/// ⚠️⚠️ 这个组件修过**三次**，前两次都错在「自己推断 Flutter 的约束传递行为」：
///
///   ① `SizedBox(height:) + ClipRect(Align(child: text))`
///      → 字在动，但右边永远空白
///   ② ① + `SizedBox(width: available)`
///      → 现象完全没变
///   ③ `SizedBox + ClipRect + OverflowBox(maxWidth: ∞) + Transform`
///      → **文字整个不见了**（比之前更糟）
///
/// 根本困难：本地没有 Flutter 环境，我没法真的跑起来看，只能靠推断，
/// 而约束传递是 Flutter 内部行为，推断了三次错了三次。
///
/// 所以现在**不再自己拼约束**，改用 Flutter 官方文档明确描述的做法：
///
///   SingleChildScrollView(scrollDirection: horizontal)
///     └ Row(mainAxisSize: MainAxisSize.min)
///         └ Text(maxLines: 1, softWrap: false)
///
/// 这里的关键**全部是文档写明的行为**，不是我推的：
///
/// - 横向 `SingleChildScrollView` 会给子项**无界宽度约束**。
/// - `Row` 在无界宽度下 + `MainAxisSize.min` → 按子项固有宽度装配。
/// - 因此 `Text` 拿到无界宽度 → `softWrap: false` 时**一定**排成完整一行，
///   不可能被挤成可用宽度。（前三版就是栽在「文字到底按多宽布局」上。）
/// - 滚动视图默认 `clipBehavior: Clip.hardEdge`，会按自身尺寸裁剪 ——
///   不再需要我手写 `ClipRect`。
///
/// 滚动位置由 [ScrollController] 手动驱动（不是手势滚动），
/// 这样不会和门页的上下滚动抢手势；动画是往返的，首尾都能读到。
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

  /// 驱动滚动位置：0 = 最左，1 = 最右
  late final Animation<double> _anim =
      Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.linear));

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _c.addListener(_applyScroll);
    // 首帧之后才知道真实的 maxScrollExtent，那时再决定「要不要滚、滚多久」。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToLayout());
  }

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToLayout());
    }
  }

  @override
  void dispose() {
    _c.removeListener(_applyScroll);
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 把动画进度映射成滚动位移。
  ///
  /// 取 min(1.0, ...) 是必要的：布局还没完成时 `position` 可能还没 attach，
  /// 或者 `maxScrollExtent` 还没算出来。
  void _applyScroll() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent * _c.value.clamp(0.0, 1.0));
  }

  /// 布局完成后决定：不需要滚就停，需要滚就设定时长并开始往返。
  void _syncToLayout() {
    if (!mounted || !_scroll.hasClients) return;
    // 这里拿到的 maxScrollExtent 是**布局真实算出来的溢出量**，
    // 不是我自己用 TextPainter 量的 —— 少一个可能算错的环节。
    final overflow = _scroll.position.maxScrollExtent;

    if (overflow <= 0.5) {
      if (_c.isAnimating) _c.stop();
      _c.value = 0;
      return;
    }

    final ms = (overflow / widget.velocity * 1000).round();
    final d = Duration(milliseconds: ms.clamp(900, 9000));
    if (_c.duration != d) _c.duration = d;
    if (!_c.isAnimating) {
      _c.value = 0;
      _c.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scroll,
      // 纯自动滚动：禁掉手势，避免和外层门页的上下滚动抢
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        // ★ 关键：无界宽度下按文字固有宽度装配，于是文字一定是完整的一行。
        //   `MainAxisSize.max` 会去撑满「无限宽」，那样文字反而被挤回可用宽度。
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: widget.style,
          ),
        ],
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

/// 区块标题：左侧标题（可带一行说明）+ 右侧进度
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.trailingColor,
    this.note,
  });

  final String title;
  final String? trailing;
  final Color? trailingColor;

  /// 标题下方的补充说明。用在 STAR 门的两个步骤上
  /// （例如第 2 步标题是「升到 RANK 15」，说明是「从地图 VERSE ep.STAR 获得后练级」）。
  final String? note;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
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
    );

    if (note == null || note!.isEmpty) {
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: heading);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 3),
          Text(
            note!,
            style: const TextStyle(fontSize: 12, height: 1.45, color: AppTheme.textFaint),
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
