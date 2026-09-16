import 'package:flutter/material.dart';

import '../data/data_loader.dart';
import '../data/data_sync.dart';
import '../data/progress_store.dart';
import '../import/lxns_client.dart';
import '../import/lxns_credentials.dart';
import '../import/lxns_import.dart';
import '../models/entry.dart';
import '../models/gate.dart';
import '../theme.dart';
import '../util/time_util.dart';

/// 设置页。
///
/// 内容：关于 / 数据来源 / **热更新** / **落雪查分器导入** / 重置进度。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.gates,
    required this.meta,
    required this.store,
    required this.dataVersion,
    required this.gameVersion,
    required this.sync,
    required this.origin,
    required this.onDataRefreshed,
  });

  final List<Gate> gates;

  /// 用来把 `music:51` 解析成曲名（提示里要显示曲名而不是 id）
  final MetaTable meta;

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
  bool _probing = false;
  SyncReport? _lastReport;
  List<SourceProbe>? _probes;

  /// 本机缓存里各文件的 `dataVersion`。
  ///
  /// 缓存在 state 里而不是每次 build 都读盘：读盘是同步 IO，
  /// 放在 build 里会在滑动时反复读 4 个文件。同步完成/清缓存后主动刷新一次即可。
  Map<String, String?>? _cachedVersions;

  // ---- 落雪查分器 ----
  bool _lxnsBusy = false;
  bool _hasToken = false;

  /// 只用来显示打码形式（`abcd…wxyz`），不是完整密钥。
  /// 完整密钥只在真正请求时从加密存储里读一次。
  String _tokenPreview = '';

  @override
  void initState() {
    super.initState();
    _refreshCachedVersions();
    _refreshTokenState();
  }

  void _refreshCachedVersions() {
    final sync = widget.sync;
    _cachedVersions = sync == null ? null : sync.cachedVersions();
  }

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
          _Card(children: _lxnsSection(context)),
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
        '门的数据（曲目、解锁条件、开放日期、缓和表、段位课程）都放在仓库的 data/*.json 里。'
        '同步后即可更新这些内容，**不需要重装 APK**。\n'
        '图片不参与热更新（已打包在 APK 内）。',
        style: TextStyle(fontSize: 13, height: 1.6, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 12),
      _kv('上次同步', last == null ? '从未同步（正在用 APK 内置数据）' : formatLocalDate(last)),
      _kv('缓存状态', sync == null ? '不可用（拿不到应用目录）' : (sync.hasCache ? '已有本机缓存' : '无缓存')),
    ];

    // 本机缓存里的数据版本。
    //
    // 为什么要专门显示它：GitHub 和 Gitee 是**两个仓库**，很容易出现
    // 「GitHub 推了新数据、Gitee 还是旧的」。这时 Gitee 源是通的、只是内容旧，
    // 只看「成功/失败」根本看不出来。版本号摆在这里才能一眼发现漂移。
    final versions = _cachedVersions;
    if (versions != null && versions.isNotEmpty) {
      final present = versions.values.whereType<String>().toSet();
      String text;
      if (present.isEmpty) {
        text = '（数据里没有 dataVersion 字段）';
      } else if (present.length == 1) {
        text = present.first;
      } else {
        // 部分文件同步失败时会出现这种情况：缓存里混着两个版本。
        text = '不一致：${present.join(' / ')}';
      }
      // 标签是「本地缓存」而不是「数据版本」：下面「关于」区块里的「数据版本」
      // 指的是 **app 此刻实际在用**的那份（可能来自 APK 内置、也可能来自缓存），
      // 两者含义不同，名字必须分开。
      children.add(_kv('本地缓存', text));
    }

    if (_lastReport != null) {
      final r = _lastReport!;
      final good = r.anySuccess;
      children.add(const SizedBox(height: 10));
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (good ? AppTheme.accent : AppTheme.warning).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: (good ? AppTheme.accent : AppTheme.warning).withValues(alpha: 0.35),
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
                  color: good ? AppTheme.accent : AppTheme.warning,
                ),
              ),
              const SizedBox(height: 4),
              for (final x in r.results)
                Text(
                  '· ${x.file}：${_outcomeLabel(x)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim, height: 1.5),
                ),
              if (r.partial) ...[
                const SizedBox(height: 6),
                const Text(
                  '⚠️ 有文件没同步成功，缓存里可能混着两个版本的数据。'
                  '建议等网络稳定后重新同步一次。',
                  style: TextStyle(fontSize: 11, color: AppTheme.warning, height: 1.5),
                ),
              ],
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

    // 连通性测试。所有源都失败时，靠它区分「全部域名都不通」还是「只有某一个不通」。
    children.add(const SizedBox(height: 8));
    children.add(
      OutlinedButton.icon(
        onPressed: (sync == null || _probing) ? null : _doProbe,
        icon: _probing
            ? const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.network_check, size: 17),
        label: Text(_probing ? '测试中…' : '测试各数据源的连通性'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSecondary,
          side: const BorderSide(color: AppTheme.border),
          minimumSize: const Size.fromHeight(40),
        ),
      ),
    );

    if (_probes != null) {
      children.add(const SizedBox(height: 10));
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in _probes!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          p.ok ? Icons.check_circle : Icons.cancel,
                          size: 14,
                          color: p.ok ? AppTheme.accent : const Color(0xFFE57373),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  p.label,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    p.host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10, color: AppTheme.textFaint),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              p.ok
                                  ? '正常（${p.millis} ms）'
                                      '${p.dataVersion == null ? '' : ' · 数据版本 ${p.dataVersion}'}'
                                  : p.detail,
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textFaint, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 5),
              const Text(
                '全部不通说明本机网络访问不到这些域名（国内常见），'
                '此时热更新用不了，但 app 完全正常——会一直用 APK 内置数据。',
                style: TextStyle(fontSize: 11, color: AppTheme.textFaint, height: 1.45),
              ),
              // 跨源版本对比：发现「Gitee 镜像忘了推」这类漂移。
              if (_probeVersions.length > 1) ...[
                const SizedBox(height: 7),
                Text(
                  '⚠️ 各源的数据版本不一致：${_probeVersions.join('、')}。'
                  '说明有仓库没推最新数据（常见于 Gitee 镜像忘推），'
                  '同步会优先用排在前面的源。',
                  style: const TextStyle(fontSize: 11, color: AppTheme.warning, height: 1.45),
                ),
              ],
            ],
          ),
        ),
      );
    }

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
    final src = r.host == null ? '' : '（${r.host}${r.dataVersion == null ? '' : ' · ${r.dataVersion}'}）';
    switch (r.outcome) {
      case SyncOutcome.updated:
        return '已更新$src';
      case SyncOutcome.unchanged:
        return '无变化$src';
      case SyncOutcome.failed:
        return '失败（${r.message ?? '未知原因'}）';
    }
  }

  /// 各源返回的版本号，形如 `["2026.09.11-2（raw.x）", "2026.09.10-1（gitee.com）"]`。
  ///
  /// 长度 > 1 就说明**有仓库没推最新数据**。这是「Gitee 镜像忘推」唯一的可见信号：
  /// 那种情况下 Gitee 源是通的、只是内容旧，看成功/失败完全看不出来。
  List<String> get _probeVersions {
    final probes = _probes;
    if (probes == null) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final p in probes) {
      if (!p.ok || p.dataVersion == null) continue;
      final key = '${p.dataVersion}（${p.host}）';
      if (seen.add(key)) out.add(key);
    }
    return out;
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
        usedSources: const {},
        finishedAt: DateTime.now(),
      );
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastReport = report;
      // 同步可能改了缓存内容，版本号要重新读一次
      _refreshCachedVersions();
    });
    if (report.updatedCount > 0) {
      await widget.onDataRefreshed();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(report.summary)));
  }

  Future<void> _doProbe() async {
    final sync = widget.sync;
    if (sync == null) return;
    setState(() {
      _probing = true;
      _probes = null;
    });
    final probes = await sync.probeSources();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probes = probes;
    });
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
    setState(() {
      _lastReport = null;
      _refreshCachedVersions();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除缓存，正在使用 APK 内置数据')),
    );
  }

  // ---------------------------------------------------------------- 落雪查分器

  /// 密钥管理 + 导入入口。
  ///
  /// 设计的核心原则：**这个功能只做「辅助建议」，最终以你手动打勾为准。**
  /// 原因见 lib/import/lxns_import.dart 顶部的说明 —— 落雪接口给的
  /// `play_time` 是「最好成绩那次」的时间，不是最后游玩时间，
  /// 所以「没找到开门之后的记录」不能当成「没打过」。
  List<Widget> _lxnsSection(BuildContext context) {
    final children = <Widget>[
      const Text(
        '从落雪查分器读你的成绩，帮你找出「哪些歌在门开放后打过」。\n'
        '密钥存在手机的加密存储里（Android Keystore），不会上传到任何地方。',
        style: TextStyle(fontSize: 13, height: 1.6, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 10),
      _kv('密钥', _hasToken ? '已配置（${LxnsCredentials.mask(_tokenPreview)}）' : '未配置'),
    ];

    children.add(const SizedBox(height: 8));
    children.add(
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _lxnsBusy ? null : () => _editToken(context),
              icon: const Icon(Icons.key_outlined, size: 17),
              label: Text(_hasToken ? '更换密钥' : '填写密钥'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.border),
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ),
          if (_hasToken) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _lxnsBusy ? null : () => _forgetToken(context),
              icon: const Icon(Icons.delete_outline, size: 17),
              label: const Text('删除密钥'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE57373),
                side: const BorderSide(color: Color(0xFF5A2A2A)),
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ],
        ],
      ),
    );

    children.add(const SizedBox(height: 8));
    children.add(
      FilledButton.icon(
        onPressed: (!_hasToken || _lxnsBusy) ? null : () => _doImport(context),
        icon: _lxnsBusy
            ? const SizedBox(
                width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download_outlined, size: 18),
        label: Text(_lxnsBusy ? '获取中…' : '从查分器获取数据并比对'),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: const Color(0xFF14141C),
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    );

    children.add(const SizedBox(height: 8));
    children.add(
      const Text(
        '判定用的是查分器的「最后游玩时间」：在门开放之后打过、但你没勾的，'
        '会提示并可以一键勾上；\n'
        '已勾选却找不到「开放之后」记录的，只提示、**不会自动取消你的勾选**。',
        style: TextStyle(fontSize: 11, color: AppTheme.textFaint, height: 1.5),
      ),
    );

    return children;
  }

  /// 判定用的「开门时间」。
  ///
  /// 优先用门自己的 `releaseDate`（ORIGIN / AIR 有）。
  /// 国服其余 11 个门还没公布日期，于是退回**最早的已知开门日**
  /// （= 本次更新的开放日 2026-09-10）。
  ///
  /// 为什么可以这么退回：`conditionText` 全都是「2026-09-10 更新后，把这几首各打一次」，
  /// 所以「更新日之后打过」正是要判断的事。
  ///
  /// ⚠️ 退回是**偏保守**的：更新日 ≤ 该门真正开放的时间，
  ///    所以「更新日之后打过」不一定等于「该门开门之后打过」——
  ///    可能把一些其实已达标的歌判成「无法确认」。
  ///    宁可让你多点几下确认，也不要漏报「还没打」。
  ///
  /// 显式取所有已公布日期里**最早**的那个，不依赖列表顺序。
  DateTime? _cutoffFor(Gate gate) {
    final own = parseLocalDate(gate.releaseDate);
    if (own != null) return own;

    DateTime? earliest;
    for (final g in widget.gates) {
      final d = parseLocalDate(g.releaseDate);
      if (d == null) continue;
      if (earliest == null || d.isBefore(earliest)) earliest = d;
    }
    return earliest;
  }

  /// 给弹窗显示用：说明这次的基准时间是怎么来的。
  ///
  /// 必须显示出来 —— 用户看到「建议勾上」时要能知道**拿什么时间比的**，
  /// 否则这个建议是无法复核的。
  String _cutoffNote() {
    final all = widget.gates
        .map((g) => parseLocalDate(g.releaseDate))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (all.isEmpty) {
      return '⚠️ 数据里没有任何门的开放日期，无法判断「更新后」，本次不建议勾选。';
    }
    return '基准时间：${formatLocalDate(all.first)}（游戏更新日）。'
        '已公布开放日期的门（ORIGIN / AIR）用它们自己的日期。';
  }

  Future<void> _editToken(BuildContext context) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: const Text('落雪个人 API 密钥', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在查分器网页「账号详情」页生成个人 API 密钥，然后粘贴到这里。\n'
              '注意要的是**个人**密钥（X-User-Token），不是开发者密钥。',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '粘贴密钥',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final ok = await LxnsCredentials.saveToken(controller.text);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败：这台手机的安全存储不可用')),
      );
      return;
    }
    await _refreshTokenState();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('密钥已保存到加密存储')),
    );
  }

  /// 删除已保存的密钥。
  ///
  /// 二次确认是必须的：删掉就得回查分器网页重新生成、再复制粘贴一遍，
  /// 而清除按钮就在「更换密钥」旁边，误触代价不小。
  ///
  /// ⚠️ 这里只删**本机保存的密钥**，不会去查分器上注销那个密钥 ——
  ///    真要作废密钥得去查分器网页操作。这一点必须在弹窗里说清楚，
  ///    否则容易误以为「删了就安全了」。
  Future<void> _forgetToken(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: const Text('删除本机保存的密钥？', style: TextStyle(fontSize: 16)),
        content: const Text(
          '删除后本机不再保存密钥，想再用查分器导入就得重新填写一遍。\n\n'
          '⚠️ 这只删本机的，**查分器那边的密钥不会失效** —— '
          '要作废它请去查分器网页「账号详情」里操作。\n\n'
          '进度勾选不受影响。',
          style: TextStyle(fontSize: 13, height: 1.55, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFE57373))),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final gone = await LxnsCredentials.clearToken();
    await _refreshTokenState();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(gone ? '已删除本机保存的密钥' : '删除失败：密钥仍然存在，请再试一次'),
      ),
    );
  }

  Future<void> _refreshTokenState() async {
    final t = await LxnsCredentials.readToken();
    if (!mounted) return;
    setState(() {
      _hasToken = t != null && t.isNotEmpty;
      _tokenPreview = t ?? '';
    });
  }

  Future<void> _doImport(BuildContext context) async {
    final token = await LxnsCredentials.readToken();
    if (!context.mounted) return;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有配置密钥')),
      );
      return;
    }

    setState(() => _lxnsBusy = true);
    LxnsImportReport? lxReport;
    String? error;
    try {
      final scores = await const LxnsClient().fetchPlayerScores(token);
      lxReport = evaluateAllGates(
        gates: widget.gates,
        cutoffOf: _cutoffFor,
        scores: scores,
        isTicked: widget.store.isTicked,
        titleOf: (k) => widget.meta[k]?.title ?? k,
        songIdOf: (k) => k.split(':').last,
        fetchedAt: DateTime.now(),
      );
    } on LxnsApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() => _lxnsBusy = false);

    if (error != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 6)),
      );
      return;
    }
    if (!context.mounted || lxReport == null) return;
    await _showImportResult(context, lxReport);
  }

  /// 结果弹窗：列出「建议勾上」和「已勾选但没找到证据」，让用户决定。
  Future<void> _showImportResult(BuildContext context, LxnsImportReport report) async {
    final toTick = report.of(LxnsVerdict.confirmed);
    final contradicted = report.of(LxnsVerdict.contradicted);
    final unknown = report.of(LxnsVerdict.unknown);

    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        title: const Text('查分器比对结果', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '读到你 ${report.scoreCount} 个谱面的成绩，扫描了 ${report.scannedGates} 个门。',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
                const SizedBox(height: 4),
                Text(
                  report.didCompare
                      ? _cutoffNote()
                      : '⚠️ 数据里没有任何门的开放日期，**这次没有做比较** —— '
                          '下面的结果只是「读到了多少成绩」，不代表「都没问题」。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: report.didCompare ? AppTheme.textFaint : AppTheme.warning,
                  ),
                ),
                const SizedBox(height: 12),

                if (toTick.isNotEmpty) ...[
                  _resultHeader('✅ 建议勾上（${toTick.length} 首）', AppTheme.accent),
                  const Text(
                    '这些歌在开门时间之后有成绩记录，但你现在没勾：',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textDim, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  ...toTick.map((r) => _resultLine(r, showTime: true)),
                  const SizedBox(height: 14),
                ],

                if (contradicted.isNotEmpty) ...[
                  _resultHeader('⚠️ 已勾选，但没找到证据（${contradicted.length} 首）',
                      AppTheme.warning),
                  Text(
                    // 依据「最后游玩时间」时可以说得确定；退化成「最好成绩时间」时要放软。
                    // 两者混在一份结果里时就按弱的那种措辞。
                    contradicted.any((r) => r.basedOnExactLastPlay)
                        ? '查分器记录的**最后游玩时间**都在门开放之前。\n'
                            '如果确实打过，可能查分器还没同步到 —— 请自己确认一下。\n'
                            '**不会自动取消你的勾选**。'
                        : '这些记录里没有「最后游玩时间」字段，只能退而看「最好成绩那次」的时间，\n'
                            '而那个时间都在门开放之前。**这不代表你没打过** ——\n'
                            '最好成绩可能是很久以前刷的，之后打过但没超过它。\n'
                            '**不会自动取消你的勾选**，请自己确认。',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textDim, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  ...contradicted.map((r) => _resultLine(r, showTime: true)),
                  const SizedBox(height: 14),
                ],

                if (toTick.isEmpty && contradicted.isEmpty) ...[
                  const Text(
                    '没有需要处理的曲目。',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                ],

                if (unknown.isNotEmpty)
                  Text(
                    '另有 ${unknown.length} 首既没勾、也没找到开门之后的记录，未做处理。',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textFaint, height: 1.4),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('关闭'),
          ),
          if (toTick.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('勾上这 ${toTick.length} 首'),
            ),
        ],
      ),
    );

    if (apply != true) return;

    // 按门分组调用 tickAll —— 存档是按 gateId 分区的
    final byGate = <String, List<String>>{};
    for (final r in toTick) {
      byGate.putIfAbsent(r.gateId, () => []).add(r.entryKey);
    }
    for (final e in byGate.entries) {
      await widget.store.tickAll(e.key, e.value);
    }
    await widget.onDataRefreshed();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已勾上 ${toTick.length} 首')),
    );
  }

  Widget _resultHeader(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
      );

  Widget _resultLine(LxnsSongResult r, {bool showTime = false}) {
    final t = r.lastKnownPlay;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              r.title,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary, height: 1.35),
            ),
          ),
          if (showTime)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                t == null ? '无时间记录' : formatLocalDate(t),
                style: const TextStyle(fontSize: 11, color: AppTheme.textFaint),
              ),
            ),
        ],
      ),
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
