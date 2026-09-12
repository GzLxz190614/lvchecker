import 'package:flutter/material.dart';

import '../models/link_level.dart';
import '../theme.dart';
import '../util/time_util.dart' show parseLocalDate;

/// 通关条件列表（BOSS 挑战那一层）。
///
/// 三态显示：
/// - **已过时**（`from` 早于今天）：灰色，可点开看历史
/// - **当前**（今天生效的那一档）：彩色高亮 + 左侧实心竖条 + 「当前」标签
/// - **未开启**（`from` 为 null 或晚于今天）：虚线观感 + 灰字
///   `from` 为 null 时显示「缓和日期未公布」，**不猜日期**
///
/// 未开启的档位**不隐藏**——能看到「以后会放宽到什么程度」对规划有用，
/// 但视觉上明显弱于当前档，避免误读。
class LinkLevelList extends StatelessWidget {
  const LinkLevelList({
    super.key,
    required this.tiers,
    required this.judges,
    this.note,
  });

  final List<LinkLevelTier> tiers;
  final Map<String, JudgeStyle> judges;
  final String? note;

  @override
  Widget build(BuildContext context) {
    if (tiers.isEmpty) {
      return const Text(
        '通关条件数据尚未提供。',
        style: TextStyle(fontSize: 13, color: AppTheme.textDim),
      );
    }

    final current = currentTier(tiers);
    final rows = <Widget>[];

    for (final t in tiers) {
      final state = _stateOf(t, current);
      rows.add(_TierRow(tier: t, state: state, judges: judges));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note != null && note!.isNotEmpty) ...[
          Text(note!, style: const TextStyle(fontSize: 12, color: AppTheme.textDim, height: 1.5)),
          const SizedBox(height: 10),
        ],
        ...rows,
        const SizedBox(height: 4),
        const Text(
          '条件随 Link LEVEL 按日期缓和。日期未公布的档位不做推测。',
          style: TextStyle(fontSize: 11, color: AppTheme.textFaint, height: 1.5),
        ),
      ],
    );
  }

  _TierState _stateOf(LinkLevelTier t, LinkLevelTier? current) {
    if (identical(t, current)) return _TierState.current;
    final d = parseLocalDate(t.from);
    if (d == null) return _TierState.notYet;
    if (d.isAfter(DateTime.now())) return _TierState.notYet;
    return _TierState.past;
  }
}


enum _TierState { past, current, notYet }

/// 血量门槛表（UNIVERSE 门专用）。
///
/// 这是**独立于难度缓和**的另一套要求：通关 RE:VERSE 时剩余血量要 ≥ 指定值。
/// UNIVERSE 门自己的门槛也按日期缓和，所以同样是多段。
///
/// 血量门槛越低越新（缓和方向是放宽），所以按 requiredHp 升序排列，
/// 最小的一段视为最新。
class HpRequirementList extends StatelessWidget {
  const HpRequirementList({super.key, required this.tiers, this.note});

  final List<HpTier> tiers;
  final String? note;

  @override
  Widget build(BuildContext context) {
    if (tiers.isEmpty) return const SizedBox.shrink();

    final sorted = [...tiers]..sort((a, b) => a.requiredHp.compareTo(b.requiredHp));
    final current = currentHpTier(sorted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note != null && note!.isNotEmpty) ...[
          Text(note!, style: const TextStyle(fontSize: 12, color: AppTheme.textDim, height: 1.5)),
          const SizedBox(height: 10),
        ],
        for (final t in sorted) _hpRow(t, identical(t, current)),
        const SizedBox(height: 4),
        const Text(
          '血量门槛同样按日期缓和。日期未公布的档位不做推测。',
          style: TextStyle(fontSize: 11, color: AppTheme.textFaint, height: 1.5),
        ),
      ],
    );
  }

  Widget _hpRow(HpTier t, bool isCurrent) {
    final from = parseLocalDate(t.from);
    final fg = isCurrent ? AppTheme.textPrimary : AppTheme.textDim;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.surfaceHigh : AppTheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border(
          left: BorderSide(
            color: isCurrent ? AppTheme.accent : const Color(0xFF3A3A4D),
            width: isCurrent ? 3 : 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isCurrent ? AppTheme.accent : fg,
              ),
            ),
          ),
          Text(
            '剩余血量 ≥ ${t.requiredHp}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isCurrent ? AppTheme.textPrimary : fg,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            from == null
                ? '缓和日期未公布'
                : '${from.year}-${_two(from.month)}-${_two(from.day)} 起',
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textFaint),
          ),
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

class _TierRow extends StatelessWidget {
  const _TierRow({required this.tier, required this.state, required this.judges});

  final LinkLevelTier tier;
  final _TierState state;
  final Map<String, JudgeStyle> judges;

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _TierState.current;
    final isPast = state == _TierState.past;

    final Color fg = isCurrent
        ? AppTheme.textPrimary
        : isPast
            ? AppTheme.textFaint
            : AppTheme.textDim;

    final Color bar = isCurrent
        ? AppTheme.accent
        : isPast
            ? const Color(0xFF3A3A4D)
            : AppTheme.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.surfaceHigh : AppTheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border(left: BorderSide(color: bar, width: isCurrent ? 3 : 2)),
      ),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Link LEVEL ${tier.label}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isCurrent ? AppTheme.accent : fg,
                  letterSpacing: 0.3,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    '当前',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.accent),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                _fromLabel(),
                style: TextStyle(
                  fontSize: 11,
                  color: isCurrent ? AppTheme.textSecondary : AppTheme.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _chip('难度', tier.minDifficulty, fg),
              const SizedBox(width: 8),
              _chip('生命', '${tier.life}', fg),
            ],
          ),
          if (tier.judges.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: tier.judges.map((name) {
                final j = judges[name];
                return _JudgeChip(
                  name: name.replaceAll('_', ' '),
                  damage: j?.damage ?? 0,
                  colorHex: j?.colorHex ?? '#888888',
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _fromLabel() {
    final d = parseLocalDate(tier.from);
    if (d == null) return '缓和日期未公布';
    return '${d.year}-${_two(d.month)}-${_two(d.day)} 起';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  Widget _chip(String label, String value, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textFaint)),
          const SizedBox(width: 5),
          Text(value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/// 判定胶囊。MISS 的配色是纯黑，在深色底上会消失，所以这里加了浅色描边。
class _JudgeChip extends StatelessWidget {
  const _JudgeChip({required this.name, required this.damage, required this.colorHex});

  final String name;
  final int damage;
  final String colorHex;

  @override
  Widget build(BuildContext context) {
    final c = _parseHex(colorHex);
    final isVeryDark = c.computeLuminance() < 0.06;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: isVeryDark ? 0.85 : 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isVeryDark ? const Color(0xFF8A90A8) : c.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: isVeryDark ? Border.all(color: const Color(0xFF8A90A8)) : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              // 深色底上用浅字，浅色底上用深字
              color: isVeryDark ? const Color(0xFFE8E8F0) : c,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$damage',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isVeryDark ? const Color(0xFFE8E8F0) : c,
            ),
          ),
        ],
      ),
    );
  }

  static Color _parseHex(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF888888) : Color(v);
  }
}
