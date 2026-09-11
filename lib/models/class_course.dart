import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 一个段位组曲（3 首固定曲目）。
class ClassCourse {
  const ClassCourse({required this.key, required this.title, required this.songKeys, required this.difficulties});

  final String key;
  final String title;
  final List<String> songKeys;

  /// 与 songKeys 一一对应，显示用的难度标签
  final List<String> difficulties;

  static ClassCourse fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'];
    final keys = <String>[];
    final diffs = <String>[];
    if (rawSongs is List) {
      for (final s in rawSongs) {
        if (s is Map) {
          keys.add((s['linkId'] as String?) ?? '');
          diffs.add((s['difficulty'] as String?) ?? '');
        }
      }
    }
    return ClassCourse(
      key: (json['key'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      songKeys: keys,
      difficulties: diffs,
    );
  }
}

/// 一个段位等级（I / II / III / IV / V / ∞）。
class ClassTier {
  const ClassTier({
    required this.key,
    required this.label,
    required this.level,
    required this.colorHex,
    required this.courses,
  });

  final String key;
  final String label;

  /// 数值等级。∞ 为 0。
  final int level;

  final String colorHex;
  final List<ClassCourse> courses;

  Color get color {
    var h = colorHex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF888888) : Color(v);
  }

  static ClassTier fromJson(Map<String, dynamic> json) {
    final raw = json['courses'];
    return ClassTier(
      key: (json['key'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      level: (json['level'] as num?)?.toInt() ?? 0,
      colorHex: (json['color'] as String?) ?? '#888888',
      courses: raw is List
          ? raw.whereType<Map>().map((c) => ClassCourse.fromJson(c.cast<String, dynamic>())).toList()
          : const [],
    );
  }
}

/// `data/classes.json`
class ClassData {
  const ClassData({
    required this.tiers,
    required this.placeholder,
    required this.unlockRuleText,
    required this.note,
  });

  final List<ClassTier> tiers;

  /// 是否为占位数据（UI 会显示提醒）
  final bool placeholder;

  final String unlockRuleText;
  final String? note;

  static ClassData fromJson(Map<String, dynamic> json) {
    final raw = json['classes'];
    final tiers = raw is List
        ? raw.whereType<Map>().map((c) => ClassTier.fromJson(c.cast<String, dynamic>())).toList()
        : <ClassTier>[];
    // ∞(0) 排最前，然后 V..I
    tiers.sort((a, b) {
      if (a.level == 0 && b.level != 0) return -1;
      if (b.level == 0 && a.level != 0) return 1;
      return b.level.compareTo(a.level);
    });
    final rule = json['unlockRule'];
    return ClassData(
      tiers: tiers,
      placeholder: json['placeholder'] == true,
      unlockRuleText: rule is Map ? ((rule['text'] as String?) ?? '') : '',
      note: json['note'] as String?,
    );
  }

  /// 某个等级里已完成组曲数
  int doneIn(ClassTier tier, Set<String> doneCourseKeys) =>
      tier.courses.where((c) => doneCourseKeys.contains(c.key)).length;

  /// 某个等级是否全部组曲已完成
  bool tierComplete(ClassTier tier, Set<String> doneCourseKeys) =>
      tier.courses.isNotEmpty && tier.courses.every((c) => doneCourseKeys.contains(c.key));

  /// 是否已达成缎带条件：**任一**等级的所有组曲都完成
  ///
  /// 注意这是 AIR 门的真正解锁条件。不过当前段位课程还是占位数据，
  /// 所以门是否解锁仍以「手动确认」为准（见 gate_status.dart）。
  bool ribbonAchieved(Set<String> doneCourseKeys) =>
      tiers.any((t) => tierComplete(t, doneCourseKeys));

  static Future<ClassData> loadFromAssets() async {
    final raw = await rootBundle.loadString('data/classes.json');
    return fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }
}
