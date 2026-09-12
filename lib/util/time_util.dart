/// 时间工具。
///
/// 重要约定：`gates.json` 里的 `releaseDate` **不带时区后缀**，形如
/// `2026-09-10T10:00`。按设计决定，它一律**按手机本地时间解析**，
/// 不做任何时区换算。这样你在机台前看到的判断和游戏内一致。
library;

import 'dart:core';

/// 把不规范的 ISO 时间补成 Dart 能解析的形式。
///
/// ⚠️ 为什么需要这个（真实踩过的坑）：
///
///   手工在 `linklevels.json` 里填 `"from": "2026-09-14T7:00"` 时，
///   界面**不显示日期**，只显示「缓和日期未公布」。原因是
///   `DateTime.tryParse` 严格遵守 ISO-8601 —— **小时必须是两位**，
///   `T7:00` 是非法的，于是返回 null，被当成「日期未公布」。
///
///   这种失败特别难查：JSON 是合法的、字段名是对的、值看着也像日期，
///   只是少了补零。所以这里统一容错，而不是要求手写时必须补零。
///
///   （不用 `DateTime.tryParse` 做「宽松解析」，是因为它没有宽松模式；
///     `.parse` 会直接抛异常，更不能用。）
String _normalizeIsoTime(String s) {
  // 只处理「日期 + T + 时间」这种形状；其它形式原样返回，交给 tryParse 判断。
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})[T ](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$')
      .firstMatch(s);
  if (m == null) return s;
  final date = m.group(1)!;
  final h = m.group(2)!.padLeft(2, '0');
  final mi = m.group(3)!.padLeft(2, '0');
  final sec = m.group(4);
  return sec == null ? '${date}T$h:$mi' : '${date}T$h:$mi:${sec.padLeft(2, '0')}';
}

/// 解析 `2026-09-10T10:00` / `2026-09-10T7:00`（缺零也认）/ `2026-09-10`。
/// 解析失败返回 null。
///
/// **所有需要解析日期的地方都应该用这个**，不要再各写一份
/// （这个函数的功能原先在 3 个文件里各抄了一遍，全都只认严格格式）。
DateTime? parseLocalDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;

  // ① 补零后按「日期 + 时间」解析 ② 再按「只有日期」解析
  return DateTime.tryParse(_normalizeIsoTime(s)) ?? DateTime.tryParse('${s}T00:00');
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
