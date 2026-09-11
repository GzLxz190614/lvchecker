import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../models/gate.dart';
import '../theme.dart';

/// 页面最下方的 BOSS 区块。
///
/// **只有达成解锁条件后才渲染**（未达成时整个 widget 不会被创建，
/// 而不是灰掉——这是明确要求）。
class BossSection extends StatelessWidget {
  const BossSection({super.key, required this.gate});

  final Gate gate;

  @override
  Widget build(BuildContext context) {
    final boss = gate.boss;
    if (boss == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.bossTint.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'BOSS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.bossTint),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                boss.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          boss.artist,
          maxLines: 2,
          style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
        ),
        const SizedBox(height: 10),
        _LevelChips(levels: boss.levels),
      ],
    );
  }
}

/// 难度等级：每个等级一个带颜色的胶囊，颜色用游戏内难度配色。
class _LevelChips extends StatelessWidget {
  const _LevelChips({required this.levels});

  final Map<String, String> levels;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final k in DifficultyStyle.order) {
      final v = levels[k];
      if (v == null || v.isEmpty) continue;
      final color = DifficultyStyle.color[k] ?? AppTheme.textDim;
      chips.add(
        Container(
          margin: const EdgeInsets.only(right: 6, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DifficultyStyle.label[k] ?? k.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.4),
              ),
              const SizedBox(width: 5),
              Text(
                v,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
      );
    }
    return Wrap(children: chips);
  }
}
