// 落雪导入的**判定规则**测试。
//
// 为什么这个测试最重要：判定错了会给你一份「看起来很有道理但其实错了」
// 的勾选建议 —— 那比没有这个功能更糟。而判定逻辑是纯函数，
// 完全可以在这里钉死，不用连网、不用装 APK。
//
// 另外这里也钉住一个**限制**：落雪给的 play_time 是「最好成绩那次」的时间，
// 不是最后游玩时间。所以「没有开门之后的记录」必须归类为「无法确认」，
// 绝不能当成「没打过」去自动取消你的勾选。

import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/import/lxns_import.dart';
import 'package:lvchecker/import/lxns_models.dart';
import 'package:lvchecker/models/gate.dart';

/// 造一个「打固定几首歌」的门
Gate _songsGate({required List<String> songKeys, String id = 'origin'}) =>
    Gate.fromJson({
      'id': id,
      'order': 1,
      'stage': 1,
      'name': 'Linked GATE ORIGIN',
      'releaseStatus': 'open',
      'tracking': 'songs',
      'conditionText': '测试',
      'requirement': {'type': 'playAll', 'songKeys': songKeys},
    });

/// 造一个「每位曲师任打一首」的门
Gate _groupedGate({required List<List<String>> groups}) => Gate.fromJson({
      'id': 'paradise',
      'order': 6,
      'stage': 1,
      'name': 'Linked GATE PARADISE',
      'releaseStatus': 'notYetOpen',
      'tracking': 'songs',
      'conditionText': '测试',
      'requirement': {
        'type': 'playAnyOfEach',
        'groups': [
          for (var i = 0; i < groups.length; i++)
            {'key': 'g$i', 'songKeys': groups[i]},
        ],
      },
    });

LxnsScore _score(int songId, LxnsLevel level, String? playTime) => LxnsScore(
      songId: songId,
      level: level,
      score: 1000000,
      playTime: playTime == null ? null : DateTime.parse(playTime),
    );

/// 判定一个门，返回「条目 key -> 判定」
Map<String, LxnsVerdict> _run({
  required Gate gate,
  required DateTime? cutoff,
  required List<LxnsScore> scores,
  Set<String> ticked = const {},
}) {
  final report = evaluateGate(
    gate: gate,
    cutoff: cutoff,
    scores: indexScores(scores),
    isTicked: ticked.contains,
    titleOf: (k) => 'title-$k',
    // linkId 形如 music:51 -> 取 id
    songIdOf: (k) => k.split(':').last,
  );
  return {for (final r in report.results) r.entryKey: r.verdict};
}

void main() {
  final cutoff = DateTime.parse('2026-09-10T10:00');

  group('未勾选 + 有开门之后的记录 → 建议勾上', () {
    test('成绩时间晚于开门时间', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [_score(51, LxnsLevel.master, '2026-09-11T01:00')],
      );
      expect(v['music:51'], LxnsVerdict.confirmed);
    });

    test('成绩时间正好等于开门时间也算（开门瞬间就能打）', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [_score(51, LxnsLevel.master, '2026-09-10T10:00')],
      );
      expect(v['music:51'], LxnsVerdict.confirmed);
    });

    test('难度不限：任意难度有记录就算', () {
      for (final lv in LxnsLevel.values) {
        final v = _run(
          gate: _songsGate(songKeys: ['music:51']),
          cutoff: cutoff,
          scores: [_score(51, lv, '2026-09-11T01:00')],
        );
        expect(v['music:51'], LxnsVerdict.confirmed, reason: '难度 $lv 应该也算');
      }
    });

    test('多个难度都有记录时，取最新那条', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [
          // 旧的（开门前）
          _score(51, LxnsLevel.expert, '2026-01-01T00:00'),
          // 新的（开门后）—— 只要有一条在开门后就算
          _score(51, LxnsLevel.master, '2026-09-12T00:00'),
        ],
      );
      expect(v['music:51'], LxnsVerdict.confirmed);
    });
  });

  group('已勾选 + 找不到开门之后的记录 → 只提示，不改', () {
    test('只有开门之前的记录', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [_score(51, LxnsLevel.master, '2026-01-01T00:00')],
        ticked: {'music:51'},
      );
      expect(v['music:51'], LxnsVerdict.contradicted);
    });

    test('完全没有这首歌的记录', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: const [],
        ticked: {'music:51'},
      );
      expect(v['music:51'], LxnsVerdict.contradicted);
    });

    test('有记录但接口没给时间 —— 仍然算「无法确认」，不能当成没打过', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [_score(51, LxnsLevel.master, null)],
        ticked: {'music:51'},
      );
      expect(v['music:51'], LxnsVerdict.contradicted,
          reason: 'play_time 缺失时无法证明「开门后打过」，但也不该自动取消勾选');
    });
  });

  group('未勾选 + 找不到开门之后的记录 → 不动', () {
    test('只有旧记录', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [_score(51, LxnsLevel.master, '2026-01-01T00:00')],
      );
      expect(v['music:51'], LxnsVerdict.unknown);
    });

    test('完全没有记录', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: const [],
      );
      expect(v['music:51'], LxnsVerdict.unknown);
    });
  });

  group('已勾选 + 有开门之后的记录 → 一致，不动', () {
    test('一致', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [_score(51, LxnsLevel.master, '2026-09-11T01:00')],
        ticked: {'music:51'},
      );
      expect(v['music:51'], LxnsVerdict.consistent);
    });
  });

  group('边界情况', () {
    test('cutoff 为 null（门没公布开放日期）时一律「无法确认」，不瞎猜', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: null,
        scores: [_score(51, LxnsLevel.master, '2099-01-01T00:00')],
      );
      expect(v['music:51'], LxnsVerdict.unknown,
          reason: '没有比较基准时不能建议勾选');
    });

    test('cutoff 为 null 时，已勾选的曲目不会被报成「没找到证据」', () {
      // ⚠️ 这条来自一次真实失败：原先无论有没有基准，已勾选 + 没命中
      //    都会归成 contradicted。于是当数据里一个开放日期都没有时，
      //    弹窗会给**每一首已勾选的歌**发一条「已勾选，但没找到证据」——
      //    而实际上根本没查过。这是两件完全不同的事：
      //      · 查过了、没证据  → contradicted（值得提示）
      //      · 根本没法查      → 保持原样，不提示
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: null,
        scores: [_score(51, LxnsLevel.master, '2099-01-01T00:00')],
        ticked: {'music:51'},
      );
      expect(v['music:51'], LxnsVerdict.consistent,
          reason: '没有基准 = 没比较过，不能反过来提示「已勾选但没证据」');
      expect(v['music:51']!.isNoticeOnly, isFalse,
          reason: '不该出现在「需要你确认」的提示列表里');
    });

    test('report.cutoff 为 null 时 didCompare 也是 false（界面据此说明「没比较」）', () {
      final report = evaluateAllGates(
        gates: [_songsGate(songKeys: ['music:51'])],
        cutoffOf: (_) => null,
        scores: const [],
        isTicked: (_, __) => false,
        titleOf: (k) => k,
        songIdOf: (k) => k.split(':').last,
      );
      expect(report.didCompare, isFalse,
          reason: '界面要能区分「查过了没问题」和「没法查」');
    });

    test('report.cutoff 取所有门基准里最早的那个', () {
      final report = evaluateAllGates(
        gates: [
          _songsGate(songKeys: ['music:51'], id: 'a'),
          _songsGate(songKeys: ['music:53'], id: 'b'),
        ],
        cutoffOf: (g) => g.id == 'a'
            ? DateTime.parse('2026-09-20T10:00')
            : DateTime.parse('2026-09-10T10:00'),
        scores: const [],
        isTicked: (_, __) => false,
        titleOf: (k) => k,
        songIdOf: (k) => k.split(':').last,
      );
      expect(report.didCompare, isTrue);
      expect(report.cutoff, DateTime.parse('2026-09-10T10:00'));
    });

    test('score 里的 songId 对不上时不算命中', () {
      final v = _run(
        gate: _songsGate(songKeys: ['music:51']),
        cutoff: cutoff,
        scores: [_score(999, LxnsLevel.master, '2026-09-11T01:00')],
      );
      expect(v['music:51'], LxnsVerdict.unknown);
    });

    test('playAnyOfEach（PARADISE）里所有候选曲都被扫描到', () {
      final v = _run(
        gate: _groupedGate(groups: [
          ['music:629', 'music:788'],
          ['music:2704'],
        ]),
        cutoff: cutoff,
        scores: [_score(788, LxnsLevel.master, '2026-09-11T01:00')],
      );
      expect(v.keys.toSet(), {'music:629', 'music:788', 'music:2704'});
      expect(v['music:788'], LxnsVerdict.confirmed);
      expect(v['music:629'], LxnsVerdict.unknown);
      expect(v['music:2704'], LxnsVerdict.unknown);
    });

    test('不该打歌的门（items / manual）不产生任何条目', () {
      final itemsGate = Gate.fromJson({
        'id': 'star',
        'order': 3,
        'stage': 1,
        'name': 'STAR',
        'releaseStatus': 'notYetOpen',
        'tracking': 'items',
        'conditionText': '测试',
        'requirement': {
          'type': 'items',
          'itemKeys': ['chara:24320'],
        },
      });
      final v = _run(
        gate: itemsGate,
        cutoff: cutoff,
        scores: const [],
      );
      expect(v, isEmpty, reason: '角色/服装/地图不是打歌，落雪成绩帮不上忙');
    });
  });

  group('汇总与勾选建议', () {
    test('keysToTick 只包含 confirmed 的条目', () {
      final report = evaluateGate(
        gate: _songsGate(songKeys: ['music:51', 'music:53', 'music:59']),
        cutoff: cutoff,
        scores: indexScores([
          _score(51, LxnsLevel.master, '2026-09-11T01:00'), // confirmed
          _score(53, LxnsLevel.master, '2026-01-01T00:00'), // unknown
        ]),
        isTicked: (_) => false,
        titleOf: (k) => k,
        songIdOf: (k) => k.split(':').last,
      );

      expect(report.keysToTick, {'music:51'});
      expect(report.confirmedCount, 1);
      expect(report.unknownCount, 2);
      expect(report.contradictedCount, 0);
      expect(report.consistentCount, 0);
    });

    test('索引同一谱面的多条记录时取最新的时间', () {
      final idx = indexScores([
        _score(51, LxnsLevel.master, '2026-01-01T00:00'),
        _score(51, LxnsLevel.master, '2026-09-11T01:00'),
      ]);
      expect(idx[(51, LxnsLevel.master)]!.playTime, DateTime.parse('2026-09-11T01:00'));
    });

    test('索引时 null 时间不会把已知时间覆盖掉', () {
      final idx = indexScores([
        _score(51, LxnsLevel.master, '2026-09-11T01:00'),
        _score(51, LxnsLevel.master, null),
      ]);
      expect(idx[(51, LxnsLevel.master)]!.playTime, isNotNull);
    });
  });
}
