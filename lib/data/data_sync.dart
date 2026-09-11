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
      return '同步失败：$failedCount 个文件取不到（离线时用本机缓存继续工作）';
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

  /// 源的顺序就是优先级，第一个可用即生效。
  ///
  /// 为什么第一个是 GitHub Pages：
  ///   实测在部分国内网络下，**GitHub 系域名整体不可达**——
  ///   raw.githubusercontent.com / raw.githack.com / cdn.jsdelivr.net 全部 DNS 解析失败。
  ///   而 `*.github.io` 是**另一个域名**，走的是另一套 CDN，在很多这类网络下能通。
  ///   所以数据会由 CI 额外发布一份到 Pages（见 .github/workflows/publish-pages.yml）。
  ///
  ///   注意 Pages 只能 serve 仓库根目录或 /docs，而数据在 data/ 下，
  ///   所以发布时把文件**平铺**到 Pages 根路径，URL 就是 .../lvchecker/data/meta.json。
  ///
  /// 仓库是 public，所有源都不需要 token。
  static const List<String> sources = [
    'https://gzlxz190614.github.io/lvchecker/data/',
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
  /// 失败时会把**每个源各自的失败原因**都记下来——之前只留最后一个源的错误，
  /// 结果看不出到底是哪一个源不通，排查时很吃亏。
  Future<SyncReport> sync() async {
    final client = http.Client();
    final results = <SyncResult>[];
    String? usedSource;

    try {
      for (final name in files) {
        var done = false;
        final errors = <String>[];

        for (final base in sources) {
          final url = '$base$name';
          final host = Uri.parse(url).host;
          try {
            final resp = await client.get(Uri.parse(url)).timeout(_timeout);
            if (resp.statusCode != 200) {
              errors.add('$host: HTTP ${resp.statusCode}');
              continue;
            }

            // 校验：必须是能解析的 JSON 对象，否则可能存在中间层错误页
            final text = utf8.decode(resp.bodyBytes);
            final decoded = jsonDecode(text);
            if (decoded is! Map) {
              errors.add('$host: 返回的不是 JSON 对象');
              continue;
            }

            // 与现有缓存比较，内容相同就不必重写（避免无意义地刷新 modified 时间）
            final target = cacheFile(name);
            if (target.existsSync() && target.readAsStringSync() == text) {
              results.add(SyncResult(file: name, outcome: SyncOutcome.unchanged));
              usedSource ??= host;
              done = true;
              break;
            }

            // 原子写入：先 .tmp 再 rename
            final tmp = File('${target.path}.tmp');
            await tmp.writeAsString(text, flush: true);
            await tmp.rename(target.path);

            results.add(SyncResult(file: name, outcome: SyncOutcome.updated));
            usedSource ??= host;
            done = true;
            break;
          } catch (e) {
            errors.add('$host: ${_shortError(e)}');
          }
        }

        if (!done) {
          results.add(SyncResult(
            file: name,
            outcome: SyncOutcome.failed,
            message: errors.isEmpty ? '没有可用的源' : errors.join('；'),
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

  /// 把异常压成一眼能看懂的一句。DNS 不通是最常见的情况，单独说清楚。
  static String _shortError(Object e) {
    final s = e.toString();
    if (s.contains('Failed host lookup')) {
      final m = RegExp(r"Failed host lookup: '([^']+)'").firstMatch(s);
      return '域名解析失败（${m?.group(1) ?? '?'}），本机网络访问不到这个域名';
    }
    if (s.contains('TimeoutException')) return '超时';
    if (s.contains('Connection refused')) return '连接被拒绝';
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  /// 逐个源做一次连通性测试，给设置页用。
  ///
  /// 目的：当所有源都失败时，能一眼看出**是全部域名都不通，还是只有某一个**。
  /// 探测的是 `data/gates.json`（体积小、必然存在）。
  Future<List<SourceProbe>> probeSources() async {
    final client = http.Client();
    final out = <SourceProbe>[];
    try {
      for (final base in sources) {
        final url = '${base}gates.json';
        final host = Uri.parse(url).host;
        final sw = Stopwatch()..start();
        try {
          final resp = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
          sw.stop();
          out.add(SourceProbe(
            host: host,
            ok: resp.statusCode == 200,
            detail: resp.statusCode == 200 ? '正常' : 'HTTP ${resp.statusCode}',
            millis: sw.elapsedMilliseconds,
          ));
        } catch (e) {
          sw.stop();
          out.add(SourceProbe(
            host: host,
            ok: false,
            detail: _shortError(e),
            millis: sw.elapsedMilliseconds,
          ));
        }
      }
    } finally {
      client.close();
    }
    return out;
  }

  /// 清空缓存（回到「用 APK 内置数据」的状态）
  Future<void> clearCache() async {
    for (final f in files) {
      final file = cacheFile(f);
      if (file.existsSync()) await file.delete();
    }
  }
}

/// 单个源的探测结果。
class SourceProbe {
  const SourceProbe({
    required this.host,
    required this.ok,
    required this.detail,
    required this.millis,
  });

  final String host;
  final bool ok;
  final String detail;
  final int millis;
}
