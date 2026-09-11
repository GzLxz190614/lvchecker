import 'package:flutter/material.dart';

import '../theme.dart';

/// 可折叠的信息区块，样式参考 mkdocs-material 的 admonitions：
/// 左侧色条 + 浅色底 + 标题 + 展开箭头。**默认折叠。**
///
/// 内容过长时**内部滚动**（不截断），最多 [maxContentHeight] 高。
class Admonition extends StatefulWidget {
  const Admonition({
    super.key,
    required this.title,
    required this.child,
    this.accent = AppTheme.border,
    this.initiallyExpanded = false,
    this.badge,
    this.trailing,
    this.maxContentHeight = 220,
  });

  final String title;
  final Widget child;
  final Color accent;
  final bool initiallyExpanded;

  /// 标题右侧的小徽章（例如「待确认」）
  final String? badge;

  /// 标题右侧的普通文字（例如「3/5 组曲」）
  final String? trailing;

  final double maxContentHeight;

  @override
  State<Admonition> createState() => _AdmonitionState();
}

class _AdmonitionState extends State<Admonition> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: widget.accent, width: 3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.textDim),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFC9CFE4),
                      ),
                    ),
                  ),
                  if (widget.badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.badge!,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.warning,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    Text(widget.trailing!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textFaint)),
                  ],
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxContentHeight),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(30, 0, 12, 12),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 纯文字段落（admonition 里最常用的内容）
class AdmonitionText extends StatelessWidget {
  const AdmonitionText(this.text, {super.key, this.dim = false});

  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.5,
        color: dim ? AppTheme.textDim : AppTheme.textSecondary,
      ),
    );
  }
}
