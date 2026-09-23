/// 落雪查分器（lxns.net）个人 API 客户端。
///
/// 只用**个人 API**（`X-User-Token` 请求头）：
///
///   `GET /api/v0/user/chunithm/player/scores`  →  `Score[]`（含 play_time）
///
/// 为什么不用开发者 API 的 `/player/{好友码}/scores`：那个返回的是
/// **简化后的 `SimpleScore[]`**，没有 `play_time` —— 而本功能全靠时间判断。
///
/// 接口文档：https://maimai.lxns.net/docs/api/chunithm
/// 鉴权说明：https://maimai.lxns.net/docs/developer-guide
///
/// ⚠️ 时间：接口返回**一律是 UTC**（文档明确：`2024-01-01T00:00:00Z`
/// 代表北京时间上午 8 时）。我们在 `LxnsScore.parseUtcToLocal` 里统一转本地，
/// 因为门的开放日期是本地时间语义 —— 不统一会差 8 小时判错。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lxns_models.dart';
import 'lxns_player.dart';

/// 拉取失败时抛这个，message 是给用户看的一句话。
class LxnsApiException implements Exception {
  const LxnsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LxnsClient {
  const LxnsClient({this.timeout = const Duration(seconds: 20)});

  final Duration timeout;

  static const String _base = 'https://maimai.lxns.net/api/v0';

  /// 拉取玩家全部成绩。
  ///
  /// 失败抛 [LxnsApiException]（带一句能直接显示的原因）。
  Future<List<LxnsScore>> fetchPlayerScores(String token) async {
    final uri = Uri.parse('$_base/user/chunithm/player/scores');
    final client = http.Client();
    try {
      final resp = await client.get(uri, headers: {
        'X-User-Token': token,
        'Accept': 'application/json',
      }).timeout(timeout);

      // 限流单独说清楚，否则用户只会看到「失败了」
      if (resp.statusCode == 429) {
        throw const LxnsApiException('请求过于频繁，触发了查分器限流（HTTP 429），等几分钟再试');
      }

      final body = _decode(resp.bodyBytes);
      final env = LxnsEnvelope.fromJson(body);

      if (resp.statusCode != 200 || !env.success) {
        // 401 是最常见的：密钥错/过期
        if (resp.statusCode == 401 || env.code == 401) {
          throw const LxnsApiException(
            '密钥无效或已过期（HTTP 401）。去查分器「账号详情」重新生成一个，再填进来',
          );
        }
        throw LxnsApiException(env.errorText);
      }

      final data = env.data;
      if (data is! List) {
        throw const LxnsApiException('查分器返回的成绩不是列表 —— 接口可能变了');
      }

      final out = <LxnsScore>[];
      for (final item in data) {
        if (item is! Map) continue;
        final s = LxnsScore.fromJson(item.cast<String, dynamic>());
        if (s != null) out.add(s);
      }
      return out;
    } on LxnsApiException {
      rethrow;
    } catch (e) {
      throw LxnsApiException(_shortError(e));
    } finally {
      client.close();
    }
  }

  /// 拉取玩家信息（段位缎带 `class_emblem` + 当前角色）。
  ///
  /// 为什么单独一个方法而不是塞进 [fetchPlayerScores]：这个接口小得多
  /// （581 字节 vs 全部成绩），而 AIR 门的缎带判定只需要它。
  /// 不想为了拿一个缎带就把几千条成绩拉下来。
  ///
  /// 用个人 API 的 `/user/chunithm/player`（和成绩同一个前缀）。
  /// ⚠️ 公开的 `/chunithm/player/{好友码}` 需要对方开
  /// `allow_third_party_fetch_player` 权限，实测（2026-09）返回 raw 404，
  /// 所以不用它。
  Future<LxnsPlayer> fetchPlayer(String token) async {
    final uri = Uri.parse('$_base/user/chunithm/player');
    final client = http.Client();
    try {
      final resp = await client.get(uri, headers: {
        'X-User-Token': token,
        'Accept': 'application/json',
      }).timeout(timeout);

      if (resp.statusCode == 429) {
        throw const LxnsApiException('请求过于频繁，触发了查分器限流（HTTP 429），等几分钟再试');
      }

      final body = _decode(resp.bodyBytes);
      final env = LxnsEnvelope.fromJson(body);

      if (resp.statusCode != 200 || !env.success) {
        if (resp.statusCode == 401 || env.code == 401) {
          throw const LxnsApiException(
            '密钥无效或已过期（HTTP 401）。去查分器「账号详情」重新生成一个，再填进来',
          );
        }
        throw LxnsApiException(env.errorText);
      }

      final data = env.data;
      if (data is! Map) {
        throw const LxnsApiException('查分器返回的玩家信息不是对象 —— 接口可能变了');
      }
      return LxnsPlayer.fromJson(data.cast<String, dynamic>());
    } on LxnsApiException {
      rethrow;
    } catch (e) {
      throw LxnsApiException(_shortError(e));
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _decode(List<int> bytes) {    final text = utf8.decode(bytes);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const LxnsApiException('查分器返回的不是 JSON 对象');
    }
    return decoded.cast<String, dynamic>();
  }

  /// 同样是「域名解析失败」这种最常见的情况，说人话。
  static String _shortError(Object e) {
    final s = e.toString();
    if (s.contains('Failed host lookup')) {
      final m = RegExp(r"Failed host lookup: '([^']+)'").firstMatch(s);
      return '连不上查分器（域名解析失败：${m?.group(1) ?? '?'}），检查手机网络';
    }
    if (s.contains('TimeoutException')) return '连接查分器超时';
    if (s.contains('Connection refused')) return '连接被查分器拒绝';
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
