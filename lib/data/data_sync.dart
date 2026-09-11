import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 一个数据文件的同步结果。
enum SyncOutcome { updated, unchanged, failed }

class SyncResult {
  const SyncResult({required this.file, required this.outcome, this.message});

  final String file;
  final SyncOutcome outcome;
  final String? message;

  bool get ok => outcome != SyncOutcome.failed;
}

/// 整体同步结果。
class SyncReport {
  const SyncReport({
    required this.results,
    required this.usedSource,
    required this.finishedAt,
  });

  final List<SyncResult> results;

  /// 本次实际生效的源（宿主机名），全部失败时为 null
  final String? usedSource;
  final DateTime finishedAt;

  bool get allOk => results.every((r) => r.ok);
  int get updatedCount => results.where((r) => r.outcome == SyncOutcome.updated).length;
  int get failedCount => results.where((r) => r.outcome == SyncOutcome.failed).length;

  String get summary {
    if (usedSource == null) {
      return '同步失败：${failedCount} 个文件取不到（离线时用本机缓存继续工作）';
    }
    return '同步完成（源：$usedSource），更新 $updatedCount 个文件'
        '${failedCount > 0 ? '，$failedCount 个失败' : ''}';
  }
}

/// 热更新服务：从 GitHub 拉最新数据，缓存到本机。
///
/// 设计要点：
/// - **多源回退**。实测 `raw.githubusercontent.com` 在部分网络下取不到，
///   而 jsDelivr CDN 可以，所以按顺序试，任一成功即用。
/// - **只下载 JSON，不碰进度存档**。存档是 ProgressStore 的事，两者完全隔离。
/// - **图片不参与热更新**。图片在 APK 里（pubspec 逐文件声明），
///   因为 82 张图走网络得不偿失；热更新只更新数据（曲目、条件、日期、缓和表）。
/// - **原子写入**：先写 .tmp 再改名，避免半途断网留下半个文件导致下次读崩。
class DataSync {
  DataSync._(this._dir);

  final Directory _dir;

  /// 要同步的文件名（都在 data/ 下）
  static const List<String> files = ['meta.json', 'gates.json', 'linklevels.json', 'classes.json'];

  /// 源的顺序就是优先级。第一个可用即生效。
  ///
  /// 仓库是 public，所以 raw 与 jsDelivr 都不需要 token。
  static const List<String> sources = [
    'https://cdn.jsdelivr.net/gh/GzLxz190614/lvchecker@main/data/',
    'https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/',
    'https://raw.githack.com/GzLxz190614/lvchecker/main/data/',
  ];

  static const Duration _timeout = Duration(seconds: 12);

  static Future<DataSync> create() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/data_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return DataSync._(dir);
  }

  Directory get cacheDir => _dir;

  File cacheFile(String name) => File('${_dir.path}/$name');

  /// 本机缓存是否已有全部文件
  bool get hasCache => files.every((f) => cacheFile(f).existsSync());

  /// 最近一次成功同步的时间（取缓存文件里最新的修改时间），无缓存返回 null
  DateTime? get lastSyncedAt {
    DateTime? latest;
    for (final f in files) {
      final file = cacheFile(f);
      if (!file.existsSync()) continue;
      final t = file.lastModifiedSync();
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    return latest;
  }

  /// 缓存是否已经过期（超过 [maxAge]）
  bool isStale(Duration maxAge) {
    final t = lastSyncedAt;
    if (t == null) return true;
    return DateTime.now().difference(t) > maxAge;
  }

  /// 执行同步。
  ///
  /// 逐文件尝试所有源：某个文件在源 A 失败就换源 B，全部失败则保留本机缓存不动。
  Future<SyncReport> sync() async {
    final client = http.Client();
    final results = <SyncResult>[];
    String? usedSource;

    try {
      for (final name in files) {
        var done = false;
        String? lastError;

        for (final base in sources) {
          final url = '$base$name';
          try {
            final resp = await client.get(Uri.parse(url)).timeout(_timeout);
            if (resp.statusCode != 200) {
              lastError = 'HTTP ${resp.statusCode}';
              continue;
            }

            // 校验：必须是能解析的 JSON 对象，否则可能存在中间层错误页
            final text = utf8.decode(resp.bodyBytes);
            final decoded = jsonDecode(text);
            if (decoded is! Map) {
              lastError = '返回的不是 JSON 对象';
              continue;
            }

            // 与现有缓存比较，内容相同就不必重写（避免无意义地刷新 modified 时间）
            final target = cacheFile(name);
            if (target.existsSync() && target.readAsStringSync() == text) {
              results.add(SyncResult(file: name, outcome: SyncOutcome.unchanged));
              usedSource ??= Uri.parse(url).host;
              done = true;
              break;
            }

            // 原子写入：先 .tmp 再 rename
            final tmp = File('${target.path}.tmp');
            await tmp.writeAsString(text, flush: true);
            await tmp.rename(target.path);

            results.add(SyncResult(file: name, outcome: SyncOutcome.updated));
            usedSource ??= Uri.parse(url).host;
            done = true;
            break;
          } catch (e) {
            lastError = e.toString();
          }
        }

        if (!done) {
          results.add(SyncResult(
            file: name,
            outcome: SyncOutcome.failed,
            message: lastError ?? '所有源都取不到',
          ));
        }
      }
    } finally {
      client.close();
    }

    return SyncReport(
      results: results,
      usedSource: usedSource,
      finishedAt: DateTime.now(),
    );
  }

  /// 清空缓存（回到「用 APK 内置数据」的状态）
  Future<void> clearCache() async {
    for (final f in files) {
      final file = cacheFile(f);
      if (file.existsSync()) await file.delete();
    }
  }
}
