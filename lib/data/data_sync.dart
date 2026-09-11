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

  /// 数据源。
  ///
  /// 为什么要有两种类型：
  ///   实测在部分国内网络下，**githubusercontent 系域名整体不可达**
  ///   （raw.githubusercontent.com / raw.githack.com 以及 jsDelivr 全部 DNS 解析失败）。
  ///   但 `github.com` 本身与 **`api.github.com` 能解析**——
  ///   所以额外加一条走 GitHub Contents API 的通路，它返回 base64 内容，
  ///   完全不碰 githubusercontent 域名。
  ///
  ///   GitHub Pages（`*.github.io`）是另一个域名、另一套 CDN，也列在前面当主源，
  ///   但它需要**先在仓库设置里启用一次**，否则 CI 发布不了（GITHUB_TOKEN 无权创建站点）。
  static const List<DataSource> sources = [
    // ① Pages：最快，但需要先手动启用一次
    UrlSource('https://gzlxz190614.github.io/lvchecker/data/', 'GitHub Pages'),
    // ② GitHub Contents API：走 api.github.com，绕开被封的 raw 域名
    ApiSource('GzLxz190614/lvchecker', 'main', 'data', 'GitHub API'),
    // ③ ~ ⑤ 常见 CDN 与 raw（部分地区可用）
    UrlSource('https://cdn.jsdelivr.net/gh/GzLxz190614/lvchecker@main/data/', 'jsDelivr'),
    UrlSource('https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/', 'raw.githubusercontent'),
    UrlSource('https://raw.githack.com/GzLxz190614/lvchecker/main/data/', 'raw.githack'),
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

        for (final source in sources) {
          try {
            final text = await source.fetch(client, name, _timeout);
            if (text == null) {
              errors.add('${source.host}: 取不到（HTTP 非 200）');
              continue;
            }

            // 校验：必须是能解析的 JSON 对象，否则可能存在中间层错误页
            final decoded = jsonDecode(text);
            if (decoded is! Map) {
              errors.add('${source.host}: 返回的不是 JSON 对象');
              continue;
            }

            // 与现有缓存比较，内容相同就不必重写（避免无意义地刷新 modified 时间）
            final target = cacheFile(name);
            if (target.existsSync() && target.readAsStringSync() == text) {
              results.add(SyncResult(file: name, outcome: SyncOutcome.unchanged));
              usedSource ??= source.host;
              done = true;
              break;
            }

            // 原子写入：先 .tmp 再 rename
            final tmp = File('${target.path}.tmp');
            await tmp.writeAsString(text, flush: true);
            await tmp.rename(target.path);

            results.add(SyncResult(file: name, outcome: SyncOutcome.updated));
            usedSource ??= source.host;
            done = true;
            break;
          } catch (e) {
            errors.add('${source.host}: ${_shortError(e)}');
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
  /// 探测的是 `gates.json`（体积小、必然存在）。
  Future<List<SourceProbe>> probeSources() async {
    final client = http.Client();
    final out = <SourceProbe>[];
    try {
      for (final source in sources) {
        final sw = Stopwatch()..start();
        try {
          final text = await source.fetch(client, 'gates.json', const Duration(seconds: 8));
          sw.stop();
          if (text == null) {
            out.add(SourceProbe(
              host: source.host,
              label: source.label,
              ok: false,
              detail: '取不到（HTTP 非 200）',
              millis: sw.elapsedMilliseconds,
            ));
            continue;
          }
          // 内容也得像样，避免把一次错误页当成「通」
          final okJson = jsonDecode(text) is Map;
          out.add(SourceProbe(
            host: source.host,
            label: source.label,
            ok: okJson,
            detail: okJson ? '正常' : '返回的不是 JSON',
            millis: sw.elapsedMilliseconds,
          ));
        } catch (e) {
          sw.stop();
          out.add(SourceProbe(
            host: source.host,
            label: source.label,
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
    required this.label,
    required this.ok,
    required this.detail,
    required this.millis,
  });

  final String host;

  /// 显示名（例如「GitHub API」），比域名好认
  final String label;

  final bool ok;
  final String detail;
  final int millis;
}

/// 数据源。
abstract class DataSource {
  const DataSource(this.label);

  /// 显示用名字（设置页的连通性列表里会显示）
  final String label;

  /// 用于显示的主机名
  String get host;

  /// 取某个文件的内容；失败抛异常
  Future<String?> fetch(http.Client client, String fileName, Duration timeout);
}

/// 直接的 URL 模板源：`<base><fileName>`
class UrlSource extends DataSource {
  const UrlSource(this.base, super.label);

  final String base;

  @override
  String get host => Uri.parse(base).host;

  @override
  Future<String?> fetch(http.Client client, String fileName, Duration timeout) async {
    final resp = await client.get(Uri.parse('$base$fileName')).timeout(timeout);
    if (resp.statusCode != 200) return null;
    return utf8.decode(resp.bodyBytes);
  }
}

/// GitHub Contents API 源。
///
/// 端点：`https://api.github.com/repos/{owner}/{repo}/contents/{dir}/{file}?ref={branch}`
///
/// 好处是**只用 api.github.com 一个域名**，不碰被封的 githubusercontent 系。
/// 代价是未认证请求有速率限制（每小时 60 次），本 app 每次同步只发 4 个请求，
/// 且只在缓存过期或你手动点同步时才发，够用。
///
/// 取内容有两条路，**先试纯文本，失败再解 base64**：
///   ① 请求头 `Accept: application/vnd.github.raw` —— 直接拿到文件原文
///   ② 默认响应 —— 内容在 `content` 字段里，是 base64
/// 实测 api.github.com 偶尔会返回 504（GitHub 侧临时故障），
/// 所以两条路都留着，任一条成功即可。
class ApiSource extends DataSource {
  const ApiSource(this.repo, this.branch, this.dir, super.label);

  final String repo;
  final String branch;
  final String dir;

  @override
  String get host => 'api.github.com';

  Uri _uri(String fileName) =>
      Uri.parse('https://api.github.com/repos/$repo/contents/$dir/$fileName?ref=$branch');

  static const Map<String, String> _jsonHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  @override
  Future<String?> fetch(http.Client client, String fileName, Duration timeout) async {
    final uri = _uri(fileName);

    // ① 直接要 raw 原文
    try {
      final rawResp = await client.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github.raw',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(timeout);
      if (rawResp.statusCode == 200) {
        final text = utf8.decode(rawResp.bodyBytes);
        if (_looksLikeJsonObject(text)) return text;
      }
    } catch (_) {
      // 落到下面走 base64
    }

    // ② 退回 base64
    final resp = await client.get(uri, headers: _jsonHeaders).timeout(timeout);
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map) return null;
    final content = body['content'];
    if (content is! String) return null;
    // GitHub 的 base64 带换行，解码前要去掉空白
    final cleaned = content.replaceAll(RegExp(r'\s'), '');
    return utf8.decode(base64Decode(cleaned));
  }

  static bool _looksLikeJsonObject(String text) {
    final t = text.trimLeft();
    return t.startsWith('{');
  }
}
