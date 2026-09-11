/// 时间工具。
///
/// 重要约定：`gates.json` 里的 `releaseDate` **不带时区后缀**，形如
/// `2026-09-10T10:00`。按设计决定，它一律**按手机本地时间解析**，
/// 不做任何时区换算。这样你在机台前看到的判断和游戏内一致。
library;

/// 解析 `2026-09-10T10:00` 或 `2026-09-10`。解析失败返回 null。
DateTime? parseLocalDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  // 先按「日期 + 时间」试，再按「只有日期」试
  return DateTime.tryParse(s) ?? DateTime.tryParse('${s}T00:00');
}

/// 格式化成 `2026-09-10 10:00` 这种给人看的形式。
String formatLocalDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = (d.hour == 0 && d.minute == 0) ? '' : ' ${two(d.hour)}:${two(d.minute)}';
  return '${d.year}-${two(d.month)}-${two(d.day)}$hm';
}

/// 门现在是否已经开放。
///
/// - `releaseDate` 为 null（国服还没公布）-> 未开放
/// - `releaseDate` 晚于当前时间 -> 未开放
/// - 否则已开放
bool isReleasedNow(String? releaseDate, {DateTime? now}) {
  final d = parseLocalDate(releaseDate);
  if (d == null) return false;
  return !d.isAfter(now ?? DateTime.now());
}
