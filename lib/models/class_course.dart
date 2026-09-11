import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 段位组曲里一个槽的类型。
///
/// 来自 `Course.xml` 的 `CourseMusicDataInfo/type`：
/// - `fixed`（type=0）       固定曲目，有 `linkId` 与 `difficulty`
/// - `randomRange`（type=1） 按**等级**随机。只有 `levelFrom`，没有曲目。
///   实测「范围」就是这个等级本身（数据里没有 toLevel），
///   例如 CLASS Ⅰ 的三个槽是 Lv10 / Lv10+ / Lv11。
/// - `randomPool`（type=2）  按**指定曲池**随机。只有池大小，不列具体曲目。
enum ClassSlotKind {
  fixed,
  randomRange,
  randomPool;

  static ClassSlotKind parse(String? raw) {
    switch (raw) {
      case 'randomRange':
        return ClassSlotKind.randomRange;
      case 'randomPool':
        return ClassSlotKind.randomPool;
      default:
        return ClassSlotKind.fixed;
    }
  }
}

/// 段位组曲里的一个槽。
class ClassSlot {
  const ClassSlot({
    required this.order,
    required this.kind,
    this.linkId,
    this.difficulty,
    this.levelFrom,
    this.levelTo,
    this.poolSize,
    this.display,
    this.image,
  });

  final int order;
  final ClassSlotKind kind;

  /// kind == fixed 时才有：指向 meta.json 的 linkId
  final String? linkId;

  /// kind == fixed 时才有：要打哪个难度（MASTER / ULTIMA / EXPERT / ADVANCED / WORLD'S END）
  final String? difficulty;

  /// kind == randomRange 时才有
  final String? levelFrom;
  final String? levelTo;

  /// kind == randomPool 时才有
  final int? poolSize;

  /// 随机槽的显示文字（例：`11+` / `13+ ~ 14` / `范围内随机选择`）
  final String? display;

  /// 随机槽的封面（例：assets/img/class/range_cover.png）
  final String? image;

  bool get isFixed => kind == ClassSlotKind.fixed;

  /// 这张随机卡上要写的大字。
  ///
  /// - 等级随机 → 直接写游戏内等级（用户明确要求：「真正的等级是 Lv10」，
  ///   也就是 `11+` 这种，不要写内部 id 19/20/21）
  /// - 曲池随机 → 「范围内随机选择」（用户指定原文）
  String get headline {
    if (kind == ClassSlotKind.randomPool) return display ?? '范围内随机选择';
    final raw = display ?? _rangeFromLevels();
    // 兼容旧数据/手改数据里带 "Lv" 前缀或空值的情况
    final t = raw.replaceAll('Lv', '').trim();
    return t.isEmpty ? '等级随机' : t;
  }

  /// 小字说明：等级随机写「等级随机」，曲池随机写「N 选 1」。
  String get sublabel {
    if (kind != ClassSlotKind.randomPool) return '等级随机';
    return poolSize == null ? '曲池随机' : '$poolSize 选 1';
  }

  String _rangeFromLevels() {
    final a = levelFrom ?? '';
    final b = levelTo ?? a;
    if (a.isEmpty) return '';
    return a == b ? a : '$a ~ $b';
  }

  static ClassSlot fromJson(Map<String, dynamic> json) {
    return ClassSlot(
      order: (json['order'] as num?)?.toInt() ?? 0,
      kind: ClassSlotKind.parse(json['kind'] as String?),
      linkId: json['linkId'] as String?,
      difficulty: json['difficulty'] as String?,
      levelFrom: json['levelFrom'] as String?,
      levelTo: json['levelTo'] as String?,
      poolSize: (json['poolSize'] as num?)?.toInt(),
      display: json['display'] as String?,
      image: json['image'] as String?,
    );
  }
}

/// 一个段位组曲（固定 3 个槽）。
class ClassCourse {
  const ClassCourse({required this.key, required this.title, required this.slots});

  final String key;
  final String title;
  final List<ClassSlot> slots;

  /// 这个组曲里有几个「固定曲目」槽（随机槽不算，因为不知道具体曲目）
  int get fixedCount => slots.where((s) => s.isFixed).length;

  int get randomCount => slots.length - fixedCount;

  static ClassCourse fromJson(Map<String, dynamic> json) {
    final raw = json['songs'];
    return ClassCourse(
      key: (json['key'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      slots: raw is List
          ? raw
              .whereType<Map>()
              .map((s) => ClassSlot.fromJson(s.cast<String, dynamic>()))
              .toList()
          : const [],
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

  /// 是否为占位数据（UI 会显示提醒）。
  /// 现在已经换成真实的 36 个组曲，所以通常为 false。
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
  bool ribbonAchieved(Set<String> doneCourseKeys) =>
      tiers.any((t) => tierComplete(t, doneCourseKeys));

  static Future<ClassData> loadFromAssets() async {
    final raw = await rootBundle.loadString('data/classes.json');
    return fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }
}
