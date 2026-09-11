import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 一个数据文件的同步结果。
enum SyncOutcome { updated, unchanged, failed }

class SyncResult {
  const SyncResult({
    required this.file,
    required this.outcome,
    this.message,
    this.host,
    this.dataVersion,
  });

  final String file;
  final SyncOutcome outcome;
  final String? message;

  /// 这次是**哪个源**提供的这个文件（失败时为 null）
  final String? host;

  /// 该文件里的 `dataVersion`。
  ///
  /// 为什么要记它：GitHub 和 Gitee 是两个仓库，很容易出现
  /// 「GitHub 已经推了新数据、Gitee 还是旧的」。这时 Gitee 源是**通的**，
  /// 只是内容旧——光看「成功/失败」根本看不出来，必须把版本号摆到界面上。
  final String? dataVersion;

  bool get ok => outcome != SyncOutcome.failed;
}

/// 整体同步结果。
class SyncReport {
  const SyncReport({
    required this.results,
    required this.usedSources,
    required this.finishedAt,
    this.dataVersion,
  });

  final List<SyncResult> results;

  /// 本次实际生效的源（宿主机名）。4 个文件可能来自不同的源，
  /// 所以这里是一个集合而不是单个值——只取第一个会掩盖「部分文件回退了」这件事。
  final Set<String> usedSources;

  /// 本次同步后的数据版本（取所有成功文件里出现的版本）。
  final String? dataVersion;

  final DateTime finishedAt;

  bool get allOk => results.every((r) => r.ok);
  int get updatedCount => results.where((r) => r.outcome == SyncOutcome.updated).length;
  int get failedCount => results.where((r) => r.outcome == SyncOutcome.failed).length;

  bool get anySuccess => usedSources.isNotEmpty;

  /// 是否有文件在这一轮失败了（部分失败时缓存里可能混着两个版本的数据）
  bool get partial => anySuccess && failedCount > 0;

  String get summary {
    if (!anySuccess) {
      return '同步失败：$failedCount 个文件取不到（离线时用本机缓存继续工作）';
    }
    final src = usedSources.length == 1 ? usedSources.first : usedSources.join('、');
    final v = dataVersion == null ? '' : '，数据版本 $dataVersion';
    return '同步完成（源：$src$v），更新 $updatedCount 个文件'
        '${failedCount > 0 ? '，$failedCount 个失败' : ''}';
  }
}

/// 热更新服务：从 GitHub / Gitee 拉最新数据，缓存到本机。
///
/// 设计要点：
/// - **多源回退**。实测 `raw.githubusercontent.com` 在部分网络下取不到，
///   而 jsDelivr CDN 可以，所以按顺序试，任一成功即用。
/// - **只下载 JSON，不碰进度存档**。存档是 ProgressStore 的事，两者完全隔离。
/// - **图片不参与热更新**。图片在 APK 里（pubspec 逐文件声明），
///   因为 160 张图走网络得不偿失；热更新只更新数据（曲目、条件、日期、缓和表、段位）。
/// - **原子写入**：先写 .tmp 再改名，避免半途断网留下半个文件导致下次读崩。
class DataSync {
  DataSync._(this._dir);

  final Directory _dir;

  /// 要同步的文件名（都在 data/ 下）
  static const List<String> files = ['meta.json', 'gates.json', 'linklevels.json', 'classes.json'];

  /// 数据源。**顺序就是优先级**：先 GitHub 系，最后 Gitee。
  ///
  /// 为什么要有两种类型：
  ///   实测在部分国内网络下，**githubusercontent 系域名整体不可达**
  ///   （raw.githubusercontent.com / raw.githack.com 以及 jsDelivr 全部 DNS 解析失败）。
  ///   但 `github.com` 本身与 **`api.github.com` 能解析**——
  ///   所以额外加一条走 GitHub Contents API 的通路，它返回 base64 内容，
  ///   完全不碰 githubusercontent 域名。
  ///
  ///   Gitee 放在最后：它是国内域名、基本必然可达，而且是**兜底**而不是主源。
  ///   往前的每一条都是 GitHub 系（你自己在 GitHub 上开发和发 APK，数据以那边为准），
  ///   只有前面都不通时才会用到 Gitee 镜像。
  static const List<DataSource> sources = [
    // ① Pages：最快，但需要先手动启用一次
    UrlSource('https://gzlxz190614.github.io/lvchecker/data/', 'GitHub Pages'),
    // ② GitHub Contents API：走 api.github.com，绕开被封的 raw 域名
    ApiSource('GzLxz190614/lvchecker', 'main', 'data', 'GitHub API'),
    // ③ ~ ⑤ 常见 CDN 与 raw（部分地区可用）
    UrlSource('https://cdn.jsdelivr.net/gh/GzLxz190614/lvchecker@main/data/', 'jsDelivr'),
    UrlSource('https://raw.githubusercontent.com/GzLxz190614/lvchecker/main/data/', 'raw.githubusercontent'),
    UrlSource('https://raw.githack.com/GzLxz190614/lvchecker/main/data/', 'raw.githack'),
    // ⑥ Gitee 镜像（国内兜底）。见 GiteeSource 的说明。
    //
    // ⚠️ 分支名是 **main**，不是 Gitee 传统的 master。
    //    Gitee 建仓库时默认是 master，但这个仓库已经在网页上把默认分支改成 main 了，
    //    实测 `raw.giteeusercontent.com/.../raw/main/data/gates.json` 返回 200 + 正确的 dataVersion。
    //    如果哪天在 Gitee 上又改了默认分支名，**这里必须同步改**，否则 app 会一直 404。
    GiteeSource('gzlxz190614/lvchecker', 'main', 'data', 'Gitee 镜像'),
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
    final usedSources = <String>{};
    final versions = <String>{};

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

            final remoteVer = decoded['dataVersion'] as String?;
            if (remoteVer != null) versions.add(remoteVer);

            final target = cacheFile(name);
            final sameText = target.existsSync() && target.readAsStringSync() == text;

            if (sameText) {
              results.add(SyncResult(
                file: name,
                outcome: SyncOutcome.unchanged,
                host: source.host,
                dataVersion: remoteVer,
              ));
            } else {
              // 与缓存里的版本号对比，区分「真的更新了」和「只是格式/换行变了」。
              // 目的是让设置页显示的「已更新/无变化」反映**数据**有没有变，
              // 而不是字节有没有变。
              final cachedVer = _cachedVersion(name);
              final outcome = (remoteVer != null && cachedVer == remoteVer)
                  ? SyncOutcome.unchanged
                  : SyncOutcome.updated;

              // 原子写入：先 .tmp 再 rename
              final tmp = File('${target.path}.tmp');
              await tmp.writeAsString(text, flush: true);
              await tmp.rename(target.path);

              results.add(SyncResult(
                file: name,
                outcome: outcome,
                host: source.host,
                dataVersion: remoteVer,
              ));
            }

            usedSources.add(source.host);
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
      usedSources: usedSources,
      finishedAt: DateTime.now(),
      // 多个文件版本不一致时不硬凑一个值，交给界面显示「不一致」
      dataVersion: versions.length == 1 ? versions.first : null,
    );
  }

  /// 读本机缓存里某个文件的 `dataVersion`（读不出来返回 null）
  String? _cachedVersion(String name) {
    final f = cacheFile(name);
    if (!f.existsSync()) return null;
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      return decoded is Map ? decoded['dataVersion'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// 本机缓存里各文件的版本号（给设置页显示「缓存里的数据版本」用）
  Map<String, String?> cachedVersions() =>
      {for (final f in files) f: _cachedVersion(f)};

  /// 把异常压成一眼能看懂的一句。DNS 不通是最常见的情况，单独说清楚。
  static String _shortError(Object e) {
    // Gitee 的失败说明是我们自己拼的多行诊断，别被下面的长度截断切掉后半段
    // （「哪条通路不通」正是关键信息）。
    if (e is _GiteeUnreachable) return e.message;

    final s = e.toString();
    if (s.contains('Failed host lookup')) {
      final m = RegExp(r"Failed host lookup: '([^']+)'").firstMatch(s);
      return '域名解析失败（${m?.group(1) ?? '?'}），本机网络访问不到这个域名';
    }
    if (s.contains('TimeoutException')) return '超时';
    if (s.contains('Connection refused')) return '连接被拒绝';
    // 去掉 Dart 异常类型前缀，能省一点宽度给真正有用的内容
    final trimmed = s.replaceFirst(RegExp(r'^(SocketException|ClientException|HttpException):\s*'), '');
    return trimmed.length > 90 ? '${trimmed.substring(0, 90)}…' : trimmed;
  }

  /// 逐个源做一次连通性测试，给设置页用。
  ///
  /// 目的：当所有源都失败时，能一眼看出**是全部域名都不通，还是只有某一个**。
  /// 探测的是 `gates.json`（体积小、必然存在）。
  ///
  /// 顺带把每个源返回的 `dataVersion` 也带出来。这是**发现两个仓库漂移的唯一手段**：
  /// 如果 GitHub 显示 `2026.09.11-2` 而 Gitee 显示 `2026.09.10-1`，
  /// 说明 Gitee 镜像忘了推——此时 Gitee 源是「通的但内容旧」，只看成功/失败看不出来。
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
          final decoded = jsonDecode(text);
          final okJson = decoded is Map;
          final ver = okJson ? decoded['dataVersion'] as String? : null;
          out.add(SourceProbe(
            host: source.host,
            label: source.label,
            ok: okJson,
            detail: okJson ? '正常' : '返回的不是 JSON',
            millis: sw.elapsedMilliseconds,
            dataVersion: ver,
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
    this.dataVersion,
  });

  final String host;

  /// 显示名（例如「GitHub API」），比域名好认
  final String label;

  final bool ok;
  final String detail;
  final int millis;

  /// 这个源返回的数据版本。用来发现「源通了但内容旧」的漂移。
  final String? dataVersion;
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

/// Gitee 仓库的 raw 源（国内兜底）。
///
/// 端点：`https://gitee.com/{owner}/{repo}/raw/{branch}/{dir}/{file}`
///
/// ⚠️ 三个必须知道的点：
///
/// 1. **公开仓库的 raw 会被强制重定向**到独立域名 `raw.giteeusercontent.com`
///    （[Gitee 帮助中心](https://help.gitee.com/repository/file-operate/raw) 明确写了，也实测确认）。
///    也就是说 `gitee.com/.../raw/...` 并不是真正的文件地址，只是一次跳转。
///    为了让「哪个域名不通」这件事可诊断，这里**先把两条路都试一遍**：
///    ① gitee.com 的 raw 端点（http 包会自动跟随重定向）
///    ② raw.giteeusercontent.com 的最终地址（直达）
///    哪条通用哪条；两条都记进错误信息里。
///
/// 2. **分支名跟 Gitee 仓库的默认分支走**。这个仓库用的是 `main`
///    （Gitee 建仓库的传统默认是 `master`，但这里在网页上改过）。
///    分支名写错的表现是稳定的 404，不是「偶尔失败」——所以排查时先确认这个。
///
/// 3. **没有 GitHub Contents API 那种匿名配额**（GitHub 是 60 次/小时/IP，
///    在运营商 NAT 下很容易被别的用户耗光）。Gitee 的 raw 是普通 GET + CDN 缓存
///    （Cache-Control 60~300 秒），所以同一个源可以被反复请求而不会「用着用着就 403」。
///    这也是加 Gitee 的主要理由之一，不只是「换个域名试试」。
class GiteeSource extends DataSource {
  const GiteeSource(this.repo, this.branch, this.dir, super.label);

  /// `owner/repo`
  final String repo;
  final String branch;
  final String dir;

  @override
  String get host => 'gitee.com';

  /// ① 会 302 到独立域名
  Uri _redirectingUri(String fileName) =>
      Uri.parse('https://gitee.com/$repo/raw/$branch/$dir/$fileName');

  /// ② 重定向的落点（直连，省掉一次跳转）
  Uri _directUri(String fileName) =>
      Uri.parse('https://raw.giteeusercontent.com/$repo/raw/$branch/$dir/$fileName');

  @override
  Future<String?> fetch(http.Client client, String fileName, Duration timeout) async {
    final problems = <String>[];

    // ⚠️ Gitee 是**最后一个**源，所以它花的时间会直接加在同步总时长上
    // （前面 5 个源每个都可能先超时 12 秒）。两段请求各分一半超时，
    // 保证这一整个源的开销不超过调用方给的一份超时，不让最坏情况翻倍。
    final half = Duration(milliseconds: timeout.inMilliseconds ~/ 2);
    final sub = half.inMilliseconds >= 2000 ? half : timeout;

    // ① 走 gitee.com。http 包默认跟随后端重定向，所以 302 会被自动吃掉：
    //    成功就拿到内容，失败则抛出**提到 raw.giteeusercontent.com 的异常**——
    //    这正好把「是国内域名不通还是那个独立域名不通」区分开了。
    try {
      final resp = await client.get(_redirectingUri(fileName)).timeout(sub);
      if (resp.statusCode == 200) {
        final text = utf8.decode(resp.bodyBytes);
        if (ApiSource._looksLikeJsonObject(text)) return text;
        problems.add('gitee.com 回的不是 JSON');
      } else if (resp.statusCode == 404) {
        problems.add('gitee.com 404（镜像过期？$branch 分支下没有 $dir/$fileName）');
      } else {
        problems.add('gitee.com ${resp.statusCode}');
      }
    } catch (e) {
      problems.add('gitee.com ${DataSync._shortError(e)}');
    }

    // ② 直接打重定向的落点。这一步的价值在于：
    //    把「重定向链路」排除掉，单独确认独立域名本身通不通。
    try {
      final resp = await client.get(_directUri(fileName)).timeout(sub);
      if (resp.statusCode == 200) {
        final text = utf8.decode(resp.bodyBytes);
        if (ApiSource._looksLikeJsonObject(text)) return text;
        problems.add('raw.giteeusercontent.com 回的不是 JSON');
      } else {
        problems.add('raw.giteeusercontent.com ${resp.statusCode}');
      }
    } catch (e) {
      problems.add('raw.giteeusercontent.com ${DataSync._shortError(e)}');
    }

    // 两条都不行：把**两条通路各自的原因**都抛出去。
    // 不能只 `return null`——那样 sync() 只会记一句「HTTP 非 200」，
    // 而「Gitee 到底是 404（忘了推镜像）还是域名不通」正是排查时最想知道的事。
    throw _GiteeUnreachable(problems.join(' / '));
  }
}

/// 内部异常：Gitee 的两条通路都失败，message 里带着各自的原因。
class _GiteeUnreachable implements Exception {
  const _GiteeUnreachable(this.message);

  final String message;

  @override
  String toString() => 'Gitee：$message';
}

