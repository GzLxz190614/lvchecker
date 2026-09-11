import 'entry.dart';

/// 某个门的解锁条件。
///
/// `gates.json` 里 `requirement.type` 的取值：
/// - `playAll`         所有 `songKeys` 各打一次（ORIGIN / AMAZON / SUN / VERSE / RE:VERSE）
/// - `playAnyOfEach`   每个 `groups` 里任打一首（PARADISE）
/// - `items`           所有 `itemKeys` 都达成（STAR / NEW / LUMINOUS）
/// - `anyClassAllCourses`  段位课程（AIR）—— M5 才实现，先只显示条件
/// - `clearAllPrev`    前置门全通关（X-VERSE / 奖励乐曲）
/// - `manualConfirm`   手动确认（CRYSTAL，条件未知）
/// - `remainingHp`     剩余血量（UNIVERSE）
class GateRequirement {
  const GateRequirement({
    required this.type,
    this.songKeys = const [],
    this.itemKeys = const [],
    this.groups = const [],
  });

  final String type;
  final List<String> songKeys;
  final List<String> itemKeys;
  final List<RequirementGroup> groups;

  static GateRequirement fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GateRequirement(type: 'unknown');

    List<String> keys(String field) {
      final raw = json[field];
      return raw is List ? raw.map((e) => e.toString()).toList() : const [];
    }

    final rawGroups = json['groups'];
    return GateRequirement(
      type: (json['type'] as String?) ?? 'unknown',
      songKeys: keys('songKeys'),
      itemKeys: keys('itemKeys'),
      groups: rawGroups is List
          ? rawGroups
              .whereType<Map>()
              .map((g) => RequirementGroup.fromJson(g.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

/// 门的开放状态。
enum ReleaseStatus {
  /// 已开放，可以开始挑战
  open,

  /// 尚未更新（国服还没开这个门）
  notYetOpen,

  /// 锁定（奖励乐曲专用：全部门通关后才出现）
  locked;

  static ReleaseStatus parse(String? raw) {
    switch (raw) {
      case 'open':
        return ReleaseStatus.open;
      case 'locked':
        return ReleaseStatus.locked;
      default:
        return ReleaseStatus.notYetOpen;
    }
  }
}

/// 用户在这个门上要做的事的类型。
/// 决定页面主体用什么 UI。
enum TrackingKind {
  /// 曲目清单卡片
  songs,

  /// 条目勾选卡片（角色/服装/地图等）
  items,

  /// 段位课程双层折叠（M5）
  classes,

  /// 无需操作，前置门全解锁即自动达成
  auto,

  /// 剩余血量，手动确认
  remainingHp,

  /// 手动确认
  manual;

  static TrackingKind parse(String? raw) {
    switch (raw) {
      case 'songs':
        return TrackingKind.songs;
      case 'items':
        return TrackingKind.items;
      case 'class':
        return TrackingKind.classes;
      case 'auto':
        return TrackingKind.auto;
      case 'universe':
        return TrackingKind.remainingHp;
      default:
        return TrackingKind.manual;
    }
  }
}

/// 一个门（或奖励乐曲页）。
class Gate {
  const Gate({
    required this.id,
    required this.order,
    required this.stage,
    required this.name,
    required this.releaseStatus,
    required this.tracking,
    required this.requirement,
    required this.conditionText,
    this.kind,
    this.boss,
    this.releaseDate,
    this.releaseNote = '',
    this.conditionSource = 'official',
    this.conditionOriginal,
    this.prerequisites = const [],
    this.unresolved,
  });

  final String id;
  final int order;
  final int stage;
  final String name;

  /// `"reward"` 表示这是奖励乐曲页，不计入门的进度统计
  final String? kind;

  final GateBoss? boss;
  final ReleaseStatus releaseStatus;
  final TrackingKind tracking;
  final GateRequirement requirement;

  /// 正式解锁条件描述（UI 默认折叠显示这个）
  final String conditionText;

  /// 游戏原文（你的 condition/*/条件.txt），作为二级折叠
  final String? conditionOriginal;

  /// official / user / estimated
  final String conditionSource;

  /// 门开放时间，形如 `2026-09-10T10:00`。**无时区后缀，按手机本地时间解析。**
  final String? releaseDate;

  final String releaseNote;
  final List<String> prerequisites;

  /// 已知的未确认事项（例如 RE:VERSE 的条件理解问题）
  final String? unresolved;

  bool get isReward => kind == 'reward';

  /// 这个页面上需要用户勾选的条目总数（reward / auto / manual 为 0）
  int get requiredCount {
    switch (tracking) {
      case TrackingKind.songs:
        if (requirement.type == 'playAnyOfEach') return requirement.groups.length;
        return requirement.songKeys.length;
      case TrackingKind.items:
        return requirement.itemKeys.length;
      default:
        return 0;
    }
  }

  static Gate fromJson(Map<String, dynamic> json) {
    final rawPrereq = json['prerequisites'];
    final rawBoss = json['boss'];
    return Gate(
      id: (json['id'] as String?) ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      stage: (json['stage'] as num?)?.toInt() ?? 1,
      name: (json['name'] as String?) ?? '',
      kind: json['kind'] as String?,
      boss: rawBoss is Map ? GateBoss.fromJson(rawBoss.cast<String, dynamic>()) : null,
      releaseStatus: ReleaseStatus.parse(json['releaseStatus'] as String?),
      tracking: TrackingKind.parse(json['tracking'] as String?),
      requirement: GateRequirement.fromJson((json['requirement'] as Map?)?.cast<String, dynamic>()),
      conditionText: (json['conditionText'] as String?) ?? '',
      conditionOriginal: json['conditionOriginal'] as String?,
      conditionSource: (json['conditionSource'] as String?) ?? 'official',
      releaseDate: json['releaseDate'] as String?,
      releaseNote: (json['releaseNote'] as String?) ?? '',
      prerequisites: rawPrereq is List ? rawPrereq.map((e) => e.toString()).toList() : const [],
      unresolved: json['unresolved'] as String?,
    );
  }
}

/// 整个 `gates.json`
class GateData {
  const GateData({
    required this.schemaVersion,
    required this.dataVersion,
    required this.gameVersion,
    required this.gates,
  });

  final int schemaVersion;
  final String dataVersion;
  final String gameVersion;
  final List<Gate> gates;

  /// 解锁条件门（不含奖励乐曲页），用于「已解锁 n/13」统计
  List<Gate> get conditionGates => gates.where((g) => !g.isReward).toList();

  static GateData fromJson(Map<String, dynamic> json) {
    final raw = json['gates'];
    final gates = raw is List
        ? raw.whereType<Map>().map((g) => Gate.fromJson(g.cast<String, dynamic>())).toList()
        : <Gate>[];
    gates.sort((a, b) => a.order.compareTo(b.order));
    return GateData(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      dataVersion: (json['dataVersion'] as String?) ?? 'unknown',
      gameVersion: (json['gameVersion'] as String?) ?? '',
      gates: gates,
    );
  }
}
