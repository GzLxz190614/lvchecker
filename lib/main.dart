import 'package:flutter/material.dart';

import 'data/data_loader.dart';
import 'data/data_sync.dart';
import 'data/progress_store.dart';
import 'pages/gate_pager.dart';
import 'pages/settings_page.dart';
import 'theme.dart';

void main() {
  runApp(const LvCheckerApp());
}

class LvCheckerApp extends StatelessWidget {
  const LvCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linked VERSE Checker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const _Boot(),
    );
  }
}

/// 启动结果：数据 + 存档 + 同步器。
class _BootResult {
  const _BootResult({
    required this.data,
    required this.store,
    required this.sync,
    this.autoSyncReport,
  });

  final LoadedData data;
  final ProgressStore store;

  /// 同步器。**可以为 null** —— 拿不到应用私有目录时（或初始化抛异常）
  /// 就没法做热更新，此时 app 退回用 APK 内置数据，功能不受影响。
  final DataSync? sync;

  /// 启动时自动同步的结果。null 表示这次没同步（数据还新鲜）。
  final SyncReport? autoSyncReport;
}

/// 启动页：先尝试热更新数据，再加载数据与本地存档，然后进主页面。
///
/// 顺序刻意如此：**先同步再加载**，这样启动后看到的立刻是最新数据，
/// 不会出现「先显示旧数据、闪一下变新」的跳动。
///
/// 同步失败不影响启动：加载器会自动降级到本机缓存 / APK 内置数据。
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<_BootResult> _future = _init();

  /// 数据新鲜度阈值：超过这个时间才在启动时自动同步。
  /// 太频繁没必要（数据变化很慢），也会无谓地打网络。
  static const Duration _freshFor = Duration(hours: 12);

  static const Duration _syncTimeout = Duration(seconds: 12);

  Future<_BootResult> _init() async {
    final store = await ProgressStore.load();

    DataSync? sync;
    SyncReport? report;
    try {
      sync = await DataSync.create();
      // 只有缓存过期时才自动同步，并且加超时——绝不能因为网络卡住启动
      if (sync.isStale(_freshFor)) {
        report = await sync.sync().timeout(
              _syncTimeout,
              onTimeout: () => SyncReport(
                results: const [
                  SyncResult(file: '(超时)', outcome: SyncOutcome.failed, message: '启动同步超时'),
                ],
                usedSources: const {},
                finishedAt: DateTime.now(),
              ),
            );
      }
    } catch (_) {
      // 拿不到目录或网络异常都无所谓，退回内置数据
      sync = null;
    }

    final data = await const DataLoader().load(sync: sync);
    return _BootResult(data: data, store: store, sync: sync, autoSyncReport: report);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFE57373), size: 40),
                    const SizedBox(height: 14),
                    const Text('数据加载失败',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final r = snap.data!;
        return _Home(result: r);
      },
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.result});

  final _BootResult result;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late _BootResult _r = widget.result;

  @override
  void initState() {
    super.initState();
    // 启动时自动同步过就提示一句（成功/失败都说清，避免用户以为是 bug）
    final report = _r.autoSyncReport;
    if (report != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(report.summary),
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SettingsPage(
          gates: _r.data.gateData.gates,
          meta: _r.data.meta,
          store: _r.store,
          dataVersion: _r.data.gateData.dataVersion,
          gameVersion: _r.data.gateData.gameVersion,
          sync: _r.sync,
          origin: _r.data.origin,
          onDataRefreshed: _reload,
        ),
      ),
    );
    if (changed == true) await _reload();
  }

  /// 设置页同步成功后重新加载数据（不重启 app）
  Future<void> _reload() async {
    // 先取成局部变量：Dart 的类型提升只对「局部变量」生效，
    // 对 `_r.sync` 这种「对象的字段」不生效（会报 argument_type_not_assignable）。
    // 提升之后，三元表达式的 yes 分支里 sync 已经是非空，可以直接传给 load()。
    final sync = _r.sync;
    final data =
        sync == null ? await const DataLoader().load() : await const DataLoader().load(sync: sync);
    if (!mounted) return;
    setState(() {
      _r = _BootResult(
        data: data,
        store: _r.store,
        sync: _r.sync,
        autoSyncReport: null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GatePager(
      gates: _r.data.gateData.gates,
      meta: _r.data.meta,
      store: _r.store,
      linkLevels: _r.data.linkLevels,
      classData: _r.data.classData,
      dataVersion: _r.data.gateData.dataVersion,
      onOpenSettings: _openSettings,
    );
  }
}
