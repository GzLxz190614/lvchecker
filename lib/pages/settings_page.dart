import 'package:flutter/material.dart';

import '../data/data_loader.dart';
import '../data/data_sync.dart';
import '../data/progress_store.dart';
import '../models/gate.dart';
import '../theme.dart';
import '../util/time_util.dart';

/// 设置页。
///
/// M1 内容：关于 / 数据来源 / **热更新** / 重置进度。
/// M4 会再加「从落雪查分器导入」+ 密钥管理。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.gates,
    required this.store,
    required this.dataVersion,
    required this.gameVersion,
    required this.sync,
    required this.origin,
    required this.onDataRefreshed,
  });

  final List<Gate> gates;
  final ProgressStore store;
  final String dataVersion;
  final String gameVersion;
  final DataSync? sync;
  final DataOrigin origin;

  /// 同步成功后通知外层重新加载数据
  final Future<void> Function() onDataRefreshed;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _syncing = false;
  SyncReport? _lastReport;

  @override
  Widget build(BuildContext context) {
    final conditionGates = widget.gates.where((g) => !g.isReward).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionTitle('数据同步（热更新）'),
          _Card(children: _syncSection(context)),
          const SizedBox(height: 22),

          const _SectionTitle('关于'),
          _Card(
            children: [
              _kv('应用版本', '0.2.0 (M1)'),
              _kv('数据版本', widget.dataVersion),
              _kv('游戏版本', widget.gameVersion.isEmpty ? '—' : widget.gameVersion),
              _kv('当前数据来源', widget.origin.label),
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

  // ---------------------------------------------------------------- 同步区

  List<Widget> _syncSection(BuildContext context) {
    final sync = widget.sync;
    final last = sync?.lastSyncedAt;

    final children = <Widget>[
      const Text(
        '门的数据（曲目、解锁条件、开放日期、缓和表）都放在 GitHub 仓库的 data/*.json 里。'
        '同步后即可更新这些内容，**不需要重装 APK**。\n'
        '图片不参与热更新（已打包在 APK 内）。',
        style: TextStyle(fontSize: 13, height: 1.6, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 12),
      _kv('上次同步', last == null ? '从未同步（正在用 APK 内置数据）' : formatLocalDate(last)),
      _kv('缓存状态', sync == null ? '不可用（拿不到应用目录）' : (sync.hasCache ? '已有本机缓存' : '无缓存')),
    ];

    if (_lastReport != null) {
      final r = _lastReport!;
      children.add(const SizedBox(height: 10));
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (r.usedSource == null ? AppTheme.warning : AppTheme.accent)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: (r.usedSource == null ? AppTheme.warning : AppTheme.accent)
                  .withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.summary,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: r.usedSource == null ? AppTheme.warning : AppTheme.accent,
                ),
              ),
              const SizedBox(height: 4),
              for (final x in r.results)
                Text(
                  '· ${x.file}：${_outcomeLabel(x)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim, height: 1.5),
                ),
            ],
          ),
        ),
      );
    }

    children.add(const SizedBox(height: 12));
    children.add(
      FilledButton.icon(
        onPressed: (sync == null || _syncing) ? null : _doSync,
        icon: _syncing
            ? const SizedBox(
                width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync, size: 18),
        label: Text(_syncing ? '同步中…' : '立即同步数据'),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: const Color(0xFF14141C),
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    );

    // 注意：这里是**方法体**，不是集合字面量。
    // 所以不能用 collection-if 的展开写法 `if (cond) ...[a, b]`——
    // 那样 Dart 会把 `...[` 当成非法 token（会报 "Expected an identifier"）。
    if (sync != null && sync.hasCache) {
      children.add(const SizedBox(height: 8));
      children.add(
        OutlinedButton.icon(
          onPressed: _syncing ? null : _clearCache,
          icon: const Icon(Icons.layers_clear_outlined, size: 17),
          label: const Text('清除本机缓存（回到 APK 内置数据）'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textDim,
            side: const BorderSide(color: AppTheme.border),
            minimumSize: const Size.fromHeight(40),
          ),
        ),
      );
    }

    return children;
  }

  String _outcomeLabel(SyncResult r) {
    switch (r.outcome) {
      case SyncOutcome.updated:
        return '已更新';
      case SyncOutcome.unchanged:
        return '无变化';
      case SyncOutcome.failed:
        return '失败（${r.message ?? '未知原因'}）';
    }
  }

  Future<void> _doSync() async {
    final sync = widget.sync;
    if (sync == null) return;
    setState(() => _syncing = true);
    SyncReport report;
    try {
      report = await sync.sync();
    } catch (e) {
      report = SyncReport(
        results: [SyncResult(file: '(异常)', outcome: SyncOutcome.failed, message: '$e')],
        usedSource: null,
        finishedAt: DateTime.now(),
      );
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastReport = report;
    });
    if (report.updatedCount > 0) {
      await widget.onDataRefreshed();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(report.summary)));
  }

  Future<void> _clearCache() async {
    final sync = widget.sync;
    if (sync == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: const Text('清除本机缓存？', style: TextStyle(fontSize: 16)),
        content: const Text(
          '删除同步下来的数据，回到 APK 内置的版本。\n进度不受影响。',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('清除')),
        ],
      ),
    );
    if (ok != true) return;
    await sync.clearCache();
    await widget.onDataRefreshed();
    if (!mounted) return;
    setState(() => _lastReport = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除缓存，正在使用 APK 内置数据')),
    );
  }

  // ---------------------------------------------------------------- 重置

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
      await widget.store.resetGate(g.id);
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
              width: 92,
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
