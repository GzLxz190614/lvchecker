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
/// ⚠️ **`playTime` 的语义必须先说清楚**，否则判定会想当然地错：
///
///   它是「**该谱面最好成绩**那次的时间」，**不是最后一次游玩时间**。
///   所以：
///     · playTime 在开门之后  → 确实在开门之后打过（最好成绩就是那时刷的）
///     · playTime 在开门之前  → **无法判断**开门后有没有打过
///       （可能打完那次之后再没碰，也可能打了很多次但都没超过它）
///     · 没有这条成绩        → 这个谱面**从来没打过**
///
///   API 现在没有提供「最后游玩时间」，所以上面第二种情况只能归到「无法判断」。
///   这是接口能力的上限，不是实现偷懒。
class LxnsScore {
  const LxnsScore({
    required this.songId,
    required this.level,
    required this.score,
    this.playTime,
  });

  final int songId;
  final LxnsLevel level;

  /// 分数值（如 1010000）
  final int score;

  /// 本地时区的游玩时间；null 表示接口没给。
  ///
  /// 接口返回的是 UTC（形如 `2024-01-09T16:00:00Z`），
  /// 这里**已经转成本地时间** —— 因为门的开放日期是本地时间语义，
  /// 两边不统一会差 8 小时（北京时间）从而判断错。
  final DateTime? playTime;

  static LxnsScore? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    final level = LxnsLevel.parse((json['level_index'] as num?)?.toInt());
    if (id == null || level == null) return null;
    return LxnsScore(
      songId: id,
      level: level,
      score: (json['score'] as num?)?.toInt() ?? 0,
      playTime: parseUtcToLocal(json['play_time'] as String?),
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
