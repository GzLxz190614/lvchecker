/// 落雪查分器（lxns.net）返回的成绩模型。
///
/// ⚠️ **这一层只负责解析，不做任何判定** —— 判定在 lxns_import.dart 里，
/// 那样才能单独测「比较逻辑对不对」，不用连网。
library;

/// 游戏内难度序号（`Score.level_index`）。
///
/// 0=BASIC 1=ADVANCED 2=EXPERT 3=MASTER 4=ULTIMA 5=WORLD'S END
enum LxnsLevel {
  basic,
  advanced,
  expert,
  master,
  ultima,
  worldsEnd;

  static LxnsLevel? parse(int? index) {
    switch (index) {
      case 0:
        return LxnsLevel.basic;
      case 1:
        return LxnsLevel.advanced;
      case 2:
        return LxnsLevel.expert;
      case 3:
        return LxnsLevel.master;
      case 4:
        return LxnsLevel.ultima;
      case 5:
        return LxnsLevel.worldsEnd;
      default:
        return null;
    }
  }

  /// 与我们 data 里 `difficulty` 字段的写法对齐
  /// （见 tools/gen_classes.py 的 DIFF_LABEL）。
  String get label {
    switch (this) {
      case LxnsLevel.basic:
        return 'BASIC';
      case LxnsLevel.advanced:
        return 'ADVANCED';
      case LxnsLevel.expert:
        return 'EXPERT';
      case LxnsLevel.master:
        return 'MASTER';
      case LxnsLevel.ultima:
        return 'ULTIMA';
      case LxnsLevel.worldsEnd:
        return "WORLD'S END";
    }
  }
}

/// 一条成绩（`Score`）。
///
/// ## 三个时间字段的区别（**这里错过一次，务必看清**）
///
/// 官方文档的 `Score` 结构体只写了两个时间字段：
///
/// | 字段 | 文档说明 | 实际语义 |
/// |---|---|---|
/// | `play_time` | 游玩的 UTC 时间 | **最好成绩那一次**的时间 |
/// | `upload_time` | 成绩被同步时的 UTC 时间 | 这条记录最后一次被同步 |
///
/// 但**实际响应里还有一个文档没写的字段**：
///
/// | 字段 | 实际语义 |
/// |---|---|---|
/// | `last_played_time` | **最后一次游玩**的时间 ← 判定就该用它 |
///
/// 这个字段是靠实际请求探查发现的（官方文档里没有）。发现过程值得一提：
/// 先按文档只用 `play_time`，结果实测「今天打过但没刷新最高分」的歌
/// `play_time` 还停在一年前；于是去扒更全的 API 列表 wiki，仍然只有那两个
/// 字段；最后是**打印真实响应的字段名**才看到它。
///
/// **教训：文档不全时，打印真实响应比反复读文档有效。**
///
/// 判定优先级：`lastPlayedTime` → 没有才退回 `playTime`
/// （退回时语义变弱，会把一些其实打过的判成「无法确认」，
/// 但**不会**误判成「打过了」—— 宁可漏报，不可误报）。
class LxnsScore {
  const LxnsScore({
    required this.songId,
    required this.level,
    required this.score,
    this.lastPlayedTime,
    this.playTime,
    this.uploadTime,
  });

  final int songId;
  final LxnsLevel level;

  /// 分数值（如 1010000）
  final int score;

  /// **最后一次游玩时间**（本地时区）。判定的首选依据。
  final DateTime? lastPlayedTime;

  /// 最好成绩那次的时间（本地时区）。
  final DateTime? playTime;

  /// 这条记录最后一次被同步的时间（本地时区）。
  ///
  /// ⚠️ **不能用来判断「打过」**：对最好成绩那条记录来说，
  /// 它只在刷新最高分时才变。留着只为排查用。
  final DateTime? uploadTime;

  /// 判定「这个谱面在某时间点之后有没有被游玩」时该用的时间。
  ///
  /// 优先 [lastPlayedTime]；没有才退回 [playTime]（语义更弱，见类文档）。
  DateTime? get comparableTime => lastPlayedTime ?? playTime;

  /// 用的是不是真正精确的「最后游玩时间」
  /// （false = 退化成了「最好成绩那次」，结论要相应弱化）
  bool get hasExactLastPlay => lastPlayedTime != null;

  static LxnsScore? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    final level = LxnsLevel.parse((json['level_index'] as num?)?.toInt());
    if (id == null || level == null) return null;
    return LxnsScore(
      songId: id,
      level: level,
      score: (json['score'] as num?)?.toInt() ?? 0,
      lastPlayedTime: parseUtcToLocal(json['last_played_time'] as String?),
      playTime: parseUtcToLocal(json['play_time'] as String?),
      uploadTime: parseUtcToLocal(json['upload_time'] as String?),
    );
  }

  /// 把接口的 UTC 时间串转成本地时间。解析失败返回 null。
  static DateTime? parseUtcToLocal(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    // 接口文档明确：时间均为 UTC，形如 2024-01-01T00:00:00Z。
    // 带 Z 时 tryParse 会给出 UTC 的 DateTime，转本地即可；
    // 万一将来不带 Z，也按 UTC 处理（宁可统一，不要随手机时区飘）。
    if (d == null) return null;
    return (d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second))
        .toLocal();
  }
}

/// 接口响应外壳：`{ success, code, message, data }`
class LxnsEnvelope {
  const LxnsEnvelope({required this.success, this.code, this.message, this.data});

  final bool success;
  final int? code;
  final String? message;
  final dynamic data;

  static LxnsEnvelope fromJson(Map<String, dynamic> json) => LxnsEnvelope(
        success: json['success'] == true,
        code: (json['code'] as num?)?.toInt(),
        message: json['message'] as String?,
        data: json['data'],
      );

  /// 给用户看的一句话失败原因。
  String get errorText {
    if (message != null && message!.trim().isNotEmpty) {
      return '${message!.trim()}（HTTP $code）';
    }
    switch (code) {
      case 401:
        return '密钥无效或已过期（HTTP 401）—— 去查分器「账号详情」重新生成';
      case 403:
        return '没有权限访问这个接口（HTTP 403）';
      case 429:
        return '请求过于频繁，触发了限流（HTTP 429），等一会儿再试';
      default:
        return '查分器返回失败（HTTP ${code ?? '?'}）';
    }
  }
}
