import 'package:flutter/material.dart';

import '../data/progress_store.dart';
import '../models/gate.dart';
import '../theme.dart';

/// 设置页。
///
/// M1 只放「关于 / 数据版本 / 重置进度」。
/// M3 会在这里加「立即同步数据」，M4 加「从落雪查分器导入」+ 密钥管理。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.gates,
    required this.store,
    required this.dataVersion,
    required this.gameVersion,
  });

  final List<Gate> gates;
  final ProgressStore store;
  final String dataVersion;
  final String gameVersion;

  @override
  Widget build(BuildContext context) {
    final conditionGates = gates.where((g) => !g.isReward).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionTitle('关于'),
          _Card(
            children: [
              _kv('应用版本', '0.1.0 (M1)'),
              _kv('数据版本', dataVersion),
              _kv('游戏版本', gameVersion.isEmpty ? '—' : gameVersion),
              _kv('数据来源', 'APK 内置'),
            ],
          ),
          const SizedBox(height: 22),

          const _SectionTitle('数据同步'),
          _Card(
            children: [
              const Text(
                '尚未开放。\n计划从 GitHub 拉取最新的 data/*.json，'
                '这样更新门的数据不需要重装 APK；离线时自动用本地缓存。',
                style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('立即同步数据'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
              ),
            ],
          ),
          const SizedBox(height: 22),

          const _SectionTitle('落雪查分器导入'),
          _Card(
            children: [
              const Text(
                '尚未开放。\n导入只是「辅助建议」：查分器对很多曲目查不到游玩时间，'
                '所以无法判断是否在更新后打过，最终仍以你手动打勾为准。',
                style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('从查分器获取数据'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
              ),
            ],
          ),
          const SizedBox(height: 22),

          const _SectionTitle('重置进度'),
          _Card(
            children: [
              const Text(
                '进度只存在这台手机上，不会上传。重置后无法恢复。',
                style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textDim),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _resetAll(context, conditionGates),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空全部进度'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE57373),
                  side: const BorderSide(color: Color(0xFF5A2A2A)),
                  minimumSize: const Size.fromHeight(42),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _resetAll(BuildContext context, List<Gate> gates) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: const Text('清空全部进度？', style: TextStyle(fontSize: 16)),
        content: const Text(
          '所有门的打勾记录都会被删除，且无法恢复。',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空', style: TextStyle(color: Color(0xFFE57373))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final g in gates) {
      await store.resetGate(g.id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空全部进度')),
      );
    }
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(k, style: const TextStyle(fontSize: 13, color: AppTheme.textFaint)),
            ),
            Expanded(
              child: Text(v, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textDim,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
