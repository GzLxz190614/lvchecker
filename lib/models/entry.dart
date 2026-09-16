import 'package:flutter/material.dart' show Color;

/// 全局条目元数据。
///
/// `data/meta.json` 里的每个条目都长这样：
/// ```jsonc
/// "music:51": {
///   "type": "music", "id": 51,
///   "title": "My First Phone", "artist": "cubesato",
///   "genre": "ORIGINAL", "works": "[ORIGINAL] Ver. CHUNITHM",
///   "levels": { "basic": "2", "advanced": "6", "expert": "10", "master": "14" },
///   "image": "assets/img/music/51/jacket.png"
/// }
/// ```
///
/// `id` 是**落雪查分器的 song_id**，导入功能会拿它匹配成绩。
class Entry {
  const Entry({
    required this.key,
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.artist,
    this.genre,
    this.works,
    this.image,
    this.slot,
    this.levels = const {},
  });

  /// 全局唯一键，形如 `music:51` / `chara:24320` / `avatar:6104401`
  final String key;

  /// music / chara / avatar / mission / map
  final String type;

  /// 游戏内 id（music 的就是落雪 song_id）
  final int id;

  final String title;

  /// 手动条目才有（例：角色条目的「角色 · 需升到 RANK 15」）
  final String? subtitle;

  final String? artist;
  final String? genre;
  final String? works;

  /// 相对仓库根的资源路径，null 表示无图（UI 退化成纯文字卡片）
  final String? image;

  /// 服装槽位：wear / head / back
  final String? slot;

  /// 难度等级，键为 basic/advanced/expert/master/ultima，值为显示字符串（如 "14.5"）
  final Map<String, String> levels;

  static Entry fromJson(String key, Map<String, dynamic> json) {
    final rawLevels = json['levels'];
    return Entry(
      key: key,
      type: (json['type'] as String?) ?? 'unknown',
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? key,
      subtitle: json['subtitle'] as String?,
      artist: json['artist'] as String?,
      genre: json['genre'] as String?,
      works: json['works'] as String?,
      image: json['image'] as String?,
      slot: json['slot'] as String?,
      levels: rawLevels is Map
          ? rawLevels.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
    );
  }

  /// 卡片上显示的第二行：曲子显示曲师，手动条目显示副标题。
  String get caption {
    if (type == 'music') return artist ?? '';
    return subtitle ?? works ?? '';
  }
}

/// 全局元数据表。按 `linkId` 索引。
class MetaTable {
  const MetaTable(this._entries);

  final Map<String, Entry> _entries;

  Entry? operator [](String? key) => key == null ? null : _entries[key];

  Iterable<Entry> get all => _entries.values;

  static MetaTable fromJson(Map<String, dynamic> json) {
    final raw = json['entries'];
    if (raw is! Map) return const MetaTable({});
    return MetaTable(
      raw.map((k, v) => MapEntry(k.toString(), Entry.fromJson(k.toString(), (v as Map).cast<String, dynamic>()))),
    );
  }
}

/// BOSS 曲信息。达成解锁条件后才在页面底部显示。
class GateBoss {
  const GateBoss({
    required this.linkId,
    required this.title,
    required this.artist,
    this.levels = const {},
    this.hasUltima = false,
  });

  final String linkId;
  final String title;
  final String artist;
  final Map<String, String> levels;
  final bool hasUltima;

  static GateBoss? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final rawLevels = json['levels'];
    return GateBoss(
      linkId: (json['linkId'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      artist: (json['artist'] as String?) ?? '',
      levels: rawLevels is Map
          ? rawLevels.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      hasUltima: json['hasUltima'] == true,
    );
  }
}

/// 难度标签与配色。顺序与游戏内一致。
class DifficultyStyle {
  const DifficultyStyle._();

  static const List<String> order = ['basic', 'advanced', 'expert', 'master', 'ultima'];
  static const Map<String, String> label = {
    'basic': 'BASIC',
    'advanced': 'ADV',
    'expert': 'EXP',
    'master': 'MAS',
    'ultima': 'ULT',
  };
  static const Map<String, Color> color = {
    'basic': Color(0xFF4CAF50),
    'advanced': Color(0xFFFFB300),
    'expert': Color(0xFFE53935),
    'master': Color(0xFF8E24AA),
    'ultima': Color(0xFFB0BEC5),
  };

  /// 返回形如 `BASIC 6   ADV 10.5   EXP 14.5   MAS 15.6` 的字符串
  static String format(Map<String, String> levels) {
    final parts = <String>[];
    for (final k in order) {
      final v = levels[k];
      if (v != null && v.isNotEmpty) parts.add('${label[k]} $v');
    }
    return parts.join('   ');
  }
}

/// 门要求的条目分组（PARADISE 门的「每位曲师各一首」用这个）
class RequirementGroup {
  const RequirementGroup({required this.key, required this.itemKeys});

  final String key;
  final List<String> itemKeys;

  static RequirementGroup fromJson(Map<String, dynamic> json) {
    final raw = json['songKeys'];
    return RequirementGroup(
      key: (json['key'] as String?) ?? '',
      itemKeys: raw is List ? raw.map((e) => e.toString()).toList() : const [],
    );
  }
}

/// 需要**依次做完的多个步骤**中的一步。
///
/// 为什么需要这个：STAR 门的条件是
/// 「获得角色 X，**并**升到 RANK 15」—— 这是两件事，缺一不可。
/// 而 `itemKeys` 是「这些条目都要完成」，表达不了「步骤」。
/// 之前 STAR 只列了角色卡，勾上就算门通，RANK 15 完全没被表达
/// （只写在 [Entry.subtitle] 的文案里），判定是错的。
///
/// 所以 STAR 这类门改用 `steps`：每一步有自己的标题、说明和条目，
/// 界面上分区显示、各自带进度，门的达成条件是**所有步骤都完成**。
///
/// ⚠️ 各步的 `itemKeys` 必须**全局唯一**（进度是按 `itemKey` 存在 `SharedPreferences`
///    里的）。同一步内和跨步都不能重复，否则一个勾会影响另一处。
///    这个约束由 `tools/check_gates_schema.py` 校验。
class RequirementStep {
  const RequirementStep({
    required this.key,
    required this.label,
    this.note,
    this.itemKeys = const [],
  });

  /// 步骤短键（`obtain` / `rank`），用作稳定标识，不显示给用户
  final String key;

  /// 步骤标题，例如「获得角色」
  final String label;

  /// 这一步的补充说明，例如「升到 RANK 15」
  final String? note;

  /// 这一步要完成的条目（linkId）
  final List<String> itemKeys;

  bool get isEmpty => itemKeys.isEmpty;

  static RequirementStep fromJson(Map<String, dynamic> json) {
    final raw = json['itemKeys'];
    return RequirementStep(
      key: (json['key'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      note: json['note'] as String?,
      itemKeys: raw is List ? raw.map((e) => e.toString()).toList() : const [],
    );
  }
}
