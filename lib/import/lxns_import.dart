/// 落雪成绩「辅助勾选」的判定逻辑。
///
/// 这一层**不联网、不碰存档**，纯函数 —— 所以能用单元测试把规则钉死。
/// 判定规则错的话，会给你一份「看起来很有道理但其实错了」的勾选建议，
/// 那比没有这个功能更糟，所以规则必须被测住。
///
/// ## 规则（按你的要求）
///
/// 对每个门里「需要打的每一首歌」：
///
/// | 情况 | 结果 | 处理 |
/// |---|---|---|
/// | 未勾选 + 存在开门**之后**的游玩记录 | [LxnsVerdict.confirmed] | 帮你勾上 + 提示 |
/// | 已勾选 + 找不到开门之后的游玩记录 | [LxnsVerdict.contradicted] | 只提示，**不改** |
/// | 未勾选 + 找不到开门之后的记录 | [LxnsVerdict.unknown] | 不动（本来就没勾） |
/// | 已勾选 + 有开门之后的记录 | [LxnsVerdict.consistent] | 不动（本来就对） |
///
/// ## ⚠️ 一个必须说清楚的限制
///
/// 落雪接口给的 `play_time` 是「**最好成绩那次**的时间」，不是最后游玩时间。
/// 所以「找不到开门之后的记录」**不等于**「开门后没打过」——
/// 完全可能是打了很多次但都没超过那次的成绩。因此这一档叫「无法确认」，
/// 只提示、不替你改任何状态。
library;

import '../models/gate.dart';
import 'lxns_models.dart';

/// 单首歌的判定结果。
enum LxnsVerdict {
  /// 有开门之后的记录，且当前未勾选 → 建议勾上
  confirmed,

  /// 已勾选，但找不到开门之后的记录 → 提示一下，不改
  contradicted,

  /// 始终无法确认（接口能力所限）
  unknown,

  /// 已勾选且有开门之后的记录，一致
  consistent;

  /// 是否要自动勾上
  bool get shouldTick => this == LxnsVerdict.confirmed;

  /// 是否只提示、不改状态
  bool get isNoticeOnly =>
      this == LxnsVerdict.contradicted || this == LxnsVerdict.unknown;
}

/// 单首歌的判定明细。
class LxnsSongResult {
  const LxnsSongResult({
    required this.gateId,
    required this.gateName,
    required this.entryKey,
    required this.title,
    required this.verdict,
    this.lastKnownPlay,
    this.cutoff,
  });

  final String gateId;

  /// 门的显示名（短名，如 ORIGIN）
  final String gateName;

  /// meta 的 linkId，如 `music:51`
  final String entryKey;

  final String title;

  final LxnsVerdict verdict;

  /// 用来比较的「这个谱面已知的游玩时间」（最好成绩那次）
  final DateTime? lastKnownPlay;

  /// 判定用的时间界线（开门时间）
  final DateTime? cutoff;
}

/// 整个导入的结果汇总。
class LxnsImportReport {
  const LxnsImportReport({
    required this.results,
    required this.scannedGates,
    required this.scoreCount,
    this.fetchedAt,
    this.cutoff,
  });

  final List<LxnsSongResult> results;
  final int scannedGates;

  /// 从接口拿到的成绩条数（一个谱面一条）
  final int scoreCount;

  final DateTime? fetchedAt;

  /// 这次用的基准时间（最早的已知开门日）。
  ///
  /// **null 表示没有基准，根本没做比较** —— 界面必须把这件事说出来，
  /// 否则用户看到「没有需要处理的曲目」会误以为「查过了，都没问题」，
  /// 而实际上是「没法查」。这两件事完全不同。
  final DateTime? cutoff;

  /// 是否真的做过比较
  bool get didCompare => cutoff != null;

  List<LxnsSongResult> of(LxnsVerdict v) =>
      results.where((r) => r.verdict == v).toList();

  int get confirmedCount => of(LxnsVerdict.confirmed).length;
  int get contradictedCount => of(LxnsVerdict.contradicted).length;
  int get unknownCount => of(LxnsVerdict.unknown).length;
  int get consistentCount => of(LxnsVerdict.consistent).length;

  /// 勾选建议：所有 confirmed 的条目 key
  Set<String> get keysToTick =>
      of(LxnsVerdict.confirmed).map((r) => r.entryKey).toSet();

  /// 按门分组（给弹窗显示用）
  Map<String, List<LxnsSongResult>> get byGate {
    final out = <String, List<LxnsSongResult>>{};
    for (final r in results) {
      out.putIfAbsent('${r.gateName}', () => []).add(r);
    }
    return out;
  }
}

/// 把成绩表索引成 `(songId, 难度) -> 成绩`。
///
/// 一个谱面可能返回多条（历史记录），取 `play_time` 最新的那条 ——
/// 因为我们要回答的是「有没有开门之后的记录」。
Map<(int, LxnsLevel), LxnsScore> indexScores(Iterable<LxnsScore> scores) {
  final out = <(int, LxnsLevel), LxnsScore>{};
  for (final s in scores) {
    final k = (s.songId, s.level);
    final prev = out[k];
    if (prev == null) {
      out[k] = s;
      continue;
    }
    final a = prev.playTime;
    final b = s.playTime;
    if (b != null && (a == null || b.isAfter(a))) out[k] = s;
  }
  return out;
}

/// 判断「这个谱面在 [cutoff] 之后有游玩记录」。
///
/// `cutoff` 为 null 时无法比较 → 返回 false（归入「无法确认」）。
bool playedAfter(DateTime? playTime, DateTime? cutoff) {
  if (playTime == null || cutoff == null) return false;
  // 用「不早于」：正好等于开门时刻也算打过（游戏里开门瞬间就能打）
  return !playTime.isBefore(cutoff);
}

/// 对单个门做判定。
///
/// [cutoff] 是这个门的「开门时间」—— 由调用方给出（门的开放日期，
/// 拿不到时退回游戏更新日）。为 null 表示无从比较。
LxnsImportReport evaluateGate({
  required Gate gate,
  required DateTime? cutoff,
  required Map<(int, LxnsLevel), LxnsScore> scores,
  required bool Function(String entryKey) isTicked,
  required String Function(String entryKey) titleOf,
  required String Function(String entryKey) songIdOf,
}) {
  final results = <LxnsSongResult>[];

  // 只处理「需要打特定歌曲」的门。items / class / manual / auto 这些
  // 不是「打歌」语义，落雪成绩帮不上忙。
  final keys = <String>[
    ...gate.requirement.songKeys,
    for (final g in gate.requirement.groups) ...g.itemKeys,
  ];

  for (final key in keys) {
    final songId = int.tryParse(songIdOf(key));
    final ticked = isTicked(key);

    // 落雪成绩是按 (songId, 难度) 存的，而我们只关心「打没打过这首歌」，
    // 不限难度 —— 所以取这首歌所有难度里最新的那条记录。
    LxnsScore? best;
    if (songId != null) {
      for (final lv in LxnsLevel.values) {
        final s = scores[(songId, lv)];
        if (s == null) continue;
        final a = best?.playTime;
        final b = s.playTime;
        if (best == null || (b != null && (a == null || b.isAfter(a)))) best = s;
      }
    }

    final play = best?.playTime;

    LxnsVerdict verdict;
    if (cutoff == null) {
      // ⚠️ 没有基准时间 → **根本没做过比较**，不能说「没找到证据」。
      //
      // 这个区分很重要：如果把「没比较」也归成 contradicted，那么当数据里
      // 一个门的开放日期都没有时，弹窗会给**每一首已勾选的歌**都发一条
      // 「已勾选，但没找到证据」——纯噪音，而且是在没查的情况下吓唬你。
      // 所以这里只分「已勾选（无从比较，保持原样）」和「未勾选（无从判断）」。
      verdict = ticked ? LxnsVerdict.consistent : LxnsVerdict.unknown;
    } else if (playedAfter(play, cutoff)) {
      verdict = ticked ? LxnsVerdict.consistent : LxnsVerdict.confirmed;
    } else {
      verdict = ticked ? LxnsVerdict.contradicted : LxnsVerdict.unknown;
    }

    results.add(LxnsSongResult(
      gateId: gate.id,
      gateName: gate.name,
      entryKey: key,
      title: titleOf(key),
      verdict: verdict,
      lastKnownPlay: play,
      cutoff: cutoff,
    ));
  }

  return LxnsImportReport(
    results: results,
    scannedGates: 1,
    scoreCount: scores.length,
  );
}

/// 对**所有门**做判定，合并成一份报告。
///
/// 每个门的「开门时间」怎么定（[cutoffOf] 由调用方给）：
/// 门自己的 `releaseDate` 优先；拿不到（国服多数门还没公布日期）时
/// **退回游戏更新日** —— 因为 `conditionText` 都是「2026-09-10 更新后…」，
/// 用更新日当基准比「没有基准」有用得多。
///
/// ⚠️ 退回更新日这件事会**偏保守**：更新日 ≤ 该门真正开放的时间，
///    于是「更新日之后打过」不等于「开门之后打过」，可能把一些
///    其实已经达标的歌标成「无法确认」。这是有意为之 ——
///    宁可让你多点几下手动确认，也不要漏报「还没打」。
LxnsImportReport evaluateAllGates({
  required List<Gate> gates,
  required DateTime? Function(Gate gate) cutoffOf,
  required Iterable<LxnsScore> scores,
  required bool Function(String gateId, String entryKey) isTicked,
  required String Function(String entryKey) titleOf,
  required String Function(String entryKey) songIdOf,
  DateTime? fetchedAt,
}) {
  final idx = indexScores(scores);
  final all = <LxnsSongResult>[];
  var scanned = 0;

  // 报告里带一份「这次用的基准」，界面要据此区分
  // 「查过了没问题」和「没法查」。取所有门基准里最早的那个。
  DateTime? reportCutoff;

  for (final gate in gates) {
    if (gate.isReward) continue;
    final cutoff = cutoffOf(gate);
    if (cutoff != null && (reportCutoff == null || cutoff.isBefore(reportCutoff))) {
      reportCutoff = cutoff;
    }
    // auto / manual 这类没有需要打的歌，跳过（evaluateGate 也会返回空）
    final r = evaluateGate(
      gate: gate,
      cutoff: cutoff,
      scores: idx,
      isTicked: (k) => isTicked(gate.id, k),
      titleOf: titleOf,
      songIdOf: songIdOf,
    );
    if (r.results.isEmpty) continue;
    scanned++;
    all.addAll(r.results);
  }

  return LxnsImportReport(
    results: all,
    scannedGates: scanned,
    scoreCount: idx.length,
    fetchedAt: fetchedAt,
    cutoff: reportCutoff,
  );
}
