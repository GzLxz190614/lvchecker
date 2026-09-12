// parseLocalDate 的测试。
//
// 这个测试来自一个**真实踩过的坑**：手工在 linklevels.json 里填
//   "from": "2026-09-14T7:00"
// 时，界面上不显示日期，只显示「缓和日期未公布」。
//
// 原因：`DateTime.tryParse` 严格遵守 ISO-8601，**小时必须是两位**，
// `T7:00` 是非法的 → 返回 null → 被当成「日期未公布」。
//
// 这种失败极难查：JSON 合法、字段名对、值看着也像日期，只是少了补零。
// 所以把它钉成测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/util/time_util.dart';

void main() {
  group('parseLocalDate 能解析规范格式', () {
    test('日期 + 两位时间', () {
      final d = parseLocalDate('2026-09-10T10:00');
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 9);
      expect(d.day, 10);
      expect(d.hour, 10);
      expect(d.minute, 0);
    });

    test('只有日期', () {
      final d = parseLocalDate('2026-09-10');
      expect(d, isNotNull);
      expect(d!.hour, 0);
      expect(d.minute, 0);
    });
  });

  group('parseLocalDate 容忍不补零的时间（就是这个坑）', () {
    test('T7:00 —— 小时一位', () {
      final d = parseLocalDate('2026-09-14T7:00');
      expect(d, isNotNull, reason: 'T7:00 必须能解析，否则界面会显示「日期未公布」');
      expect(d!.year, 2026);
      expect(d.month, 9);
      expect(d.day, 14);
      expect(d.hour, 7);
      expect(d.minute, 0);
    });

    test('T07:5 —— 分钟一位', () {
      final d = parseLocalDate('2026-09-14T07:5');
      expect(d, isNotNull);
      expect(d!.hour, 7);
      expect(d.minute, 5);
    });

    test('T7:5 —— 两个都一位', () {
      final d = parseLocalDate('2026-09-14T7:5');
      expect(d, isNotNull);
      expect(d!.hour, 7);
      expect(d.minute, 5);
    });

    test('带秒且秒一位', () {
      final d = parseLocalDate('2026-09-14T7:5:3');
      expect(d, isNotNull);
      expect(d!.hour, 7);
      expect(d.minute, 5);
      expect(d.second, 3);
    });

    test('用空格分隔而不是 T', () {
      final d = parseLocalDate('2026-09-14 7:00');
      expect(d, isNotNull);
      expect(d!.hour, 7);
    });

    test('两段式时间都能解析成同一个时刻', () {
      final a = parseLocalDate('2026-09-14T7:00');
      final b = parseLocalDate('2026-09-14T07:00');
      expect(a, isNotNull);
      expect(a, equals(b));
    });
  });

  group('parseLocalDate 的失败与边界情况', () {
    test('null / 空串 / 纯空白都返回 null', () {
      expect(parseLocalDate(null), isNull);
      expect(parseLocalDate(''), isNull);
      expect(parseLocalDate('   '), isNull);
    });

    test('真的不是日期的字符串返回 null（不能瞎猜）', () {
      expect(parseLocalDate('未公布'), isNull);
      expect(parseLocalDate('2026/09/10'), isNull);
      expect(parseLocalDate('2026-13-45'), isNull);
    });

    test('首尾空白会被忽略', () {
      final d = parseLocalDate('  2026-09-14T7:00  ');
      expect(d, isNotNull);
      expect(d!.day, 14);
    });
  });

  group('isReleasedNow 用同一套解析', () {
    test('缺零的日期也能正确判断「已开放」', () {
      // 2020 年的日期显然已经过了
      expect(isReleasedNow('2020-01-01T7:00'), isTrue);
    });

    test('未来日期判为未开放', () {
      expect(
        isReleasedNow('2099-01-01T7:00', now: DateTime(2026, 1, 1)),
        isFalse,
      );
    });

    test('解析不了时按「未开放」处理，不猜', () {
      expect(isReleasedNow('未公布'), isFalse);
      expect(isReleasedNow(null), isFalse);
    });
  });
}
