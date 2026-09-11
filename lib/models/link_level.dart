import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 判定（JUSTICE / ATTACK / MISS / JUSTICE CRITICAL）的伤害与颜色。
///
/// 颜色来自游戏内判定文字配色。注意 MISS 是纯黑 —— 在深色底上会看不见，
/// 所以 UI 里给它单独加了浅色描边（见 link_level_list.dart）。
class JudgeStyle {
  const JudgeStyle({required this.name, required this.damage, required this.colorHex});

  final String name;
  final int damage;
  final String colorHex;

  static JudgeStyle fromJson(String name, Map<String, dynamic> json) => JudgeStyle(
        name: name,
        damage: (json['damage'] as num?)?.toInt() ?? 0,
        colorHex: (json['color'] as String?) ?? '#888888',
      );
}

/// 某个 Link LEVEL（或 ∞ 档）的通关条件。
class LinkLevelTier {
  const LinkLevelTier({
    required this.level,
    required this.label,
    required this.minDifficulty,
    required this.life,
    required this.judges,
    this.from,
    this.source = 'user',
    this.note,
    this.requiredHp,
  });

  /// 数值等级。∞ 档为 0，用于排序（0 排最前，符合游戏内顺序）
  final int level;

  /// 显示用标签，例如 `V` / `∞`
  final String label;

  /// 最低难度：MASTER / EXPERT / BASIC / ULTIMA
  final String minDifficulty;

  /// 生命值（亚服/国服数值）
  final int life;

  /// 用到的判定名
  final List<String> judges;

  /// 该档生效日期，null 表示尚未公布（**不猜**）
  final String? from;

  /// official / user / estimated
  final String source;

  final String? note;

  /// UNIVERSE 门专用：要求通关 RE:VERSE 时的剩余血量
  final int? requiredHp;

  static LinkLevelTier fromJson(Map<String, dynamic> json) {
    final rawJudges = json['judges'];
    return LinkLevelTier(
      level: (json['level'] as num?)?.toInt() ?? 0,
      label: (json['label'] as String?) ?? '',
      minDifficulty: (json['minDifficulty'] as String?) ?? '',
      life: (json['life'] as num?)?.toInt() ?? 0,
      judges: rawJudges is List ? rawJudges.map((e) => e.toString()).toList() : const [],
      from: json['from'] as String?,
      source: (json['source'] as String?) ?? 'user',
      note: json['note'] as String?,
      requiredHp: (json['requiredHp'] as num?)?.toInt(),
    );
  }
}

/// 一个门的缓和表。
class GateLinkLevels {
  const GateLinkLevels({required this.tiers, this.note});

  /// 已按 level 降序排好（V -> I），∞ 档 level=0 自然排最前
  final List<LinkLevelTier> tiers;
  final String? note;
}

/// `linklevels.json` 的完整内容。
class LinkLevelData {
  const LinkLevelData({
    required this.judges,
    required this.gates,
    required this.defaultLevel,
  });

  /// 判定名 -> 样式
  final Map<String, JudgeStyle> judges;

  /// 门 id -> 缓和表
  final Map<String, GateLinkLevels> gates;

  /// 缓和日期未知时按哪一档显示（默认 5 = 最严）
  final int defaultLevel;

  static const empty = LinkLevelData(judges: {}, gates: {}, defaultLevel: 5);

  JudgeStyle? judge(String name) => judges[name];

  GateLinkLevels? forGate(String gateId) => gates[gateId];

  static LinkLevelData fromJson(Map<String, dynamic> json) {
    final judges = <String, JudgeStyle>{};
    final rawJudges = json['judges'];
    if (rawJudges is Map) {
      rawJudges.forEach((k, v) {
        if (v is Map) judges[k.toString()] = JudgeStyle.fromJson(k.toString(), v.cast<String, dynamic>());
      });
    }

    final gates = <String, GateLinkLevels>{};
    final rawGates = json['gates'];
    if (rawGates is Map) {
      rawGates.forEach((gateId, value) {
        if (value is! Map) return;
        final rawLevels = value['levels'];
        final tiers = <LinkLevelTier>[];
        if (rawLevels is List) {
          for (final t in rawLevels) {
            if (t is Map) tiers.add(LinkLevelTier.fromJson(t.cast<String, dynamic>()));
          }
        }
        // 按 level 降序：∞(0) 在最前，然后 V IV III II I。
        // 用「level 数值降序」会把 ∞ 排到最后，所以 ∞ 单独处理。
        tiers.sort((a, b) {
          if (a.level == 0 && b.level != 0) return -1;
          if (b.level == 0 && a.level != 0) return 1;
          return b.level.compareTo(a.level);
        });
        gates[gateId.toString()] =
            GateLinkLevels(tiers: tiers, note: value['note'] as String?);
      });
    }

    return LinkLevelData(
      judges: judges,
      gates: gates,
      defaultLevel: (json['defaultLevel'] as num?)?.toInt() ?? 5,
    );
  }

  static Future<LinkLevelData> loadFromAssets() async {
    final raw = await rootBundle.loadString('data/linklevels.json');
    return fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }
}

/// 找出「今天」生效的那一档。
///
/// 规则：在所有 `from` 已公布且不晚于今天的档位里，取 level 最小的那个
/// （level 越小条件越松，也就是最新的缓和结果）。
/// 若一档都没有公布日期，返回 null —— UI 会显示「缓和日期未公布」，
/// 而不是拿日服的日期瞎猜。
LinkLevelTier? currentTier(List<LinkLevelTier> tiers, {DateTime? now}) {
  final today = now ?? DateTime.now();
  LinkLevelTier? best;
  for (final t in tiers) {
    final d = _parse(t.from);
    if (d == null) continue;
    if (d.isAfter(today)) continue;
    if (best == null || _levelRank(t) < _levelRank(best)) best = t;
  }
  return best;
}

/// ∞ 档（level 0）视为「最严」，排序时 rank 最大。
int _levelRank(LinkLevelTier t) => t.level == 0 ? 999 : t.level;

DateTime? _parse(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim();
  return DateTime.tryParse(s) ?? DateTime.tryParse('${s}T00:00');
}
