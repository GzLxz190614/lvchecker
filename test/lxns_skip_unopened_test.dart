// 「同步时出现两个怒槌」这个 bug 的回归测试。
//
// ## 问题
//
// 用户报告：从查分器同步乐曲时，会看到**两个「怒槌」**；手动勾完 30 首后
// 再同步，还会提示怒槌没勾；把 30 首全取消再同步，多出来的那个就消失了。
//
// ## 根因
//
// `怒槌`（`music:180`）**同时属于 ORIGIN 和 PARADISE 两个门**。而勾选状态
// 是**按门分开存**的（`p:origin` / `p:paradise`），所以：
//
//   1. 用户在 ORIGIN 里勾了怒槌 -> 只写进 `p:origin`；
//   2. `evaluateAllGates` 遍历**所有门**且不检查 `releaseStatus`，
//      于是 PARADISE 的怒槌也被判定，它**仍然是未勾**的；
//   3. 弹窗里就出现了第二个怒槌，提示「这个没勾」——
//      看起来像 App 有 bug，其实是**给一个还没开放的门提打歌建议**。
//
// ## 修法
//
// 跳过还没开放的门（没有 `releaseDate` 或日期未到），和门页显示的
// 「未更新」口径一致。依据是**门是否开放**，不是硬编码门 id ——
// PARADISE 以后开放了会自动重新参与判定。

import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/import/lxns_import.dart';
import 'package:lvchecker/import/lxns_models.dart';
import 'package:lvchecker/models/gate.dart';

/// 造一个门。`releaseDate` 为 null 表示国服还没公布日期（= 未开放）。
Gate _gate({
  required String id,
  required String name,
  required List<String> songKeys,
  String? releaseDate,
}) =>
    Gate.fromJson({
      'id': id,
      'order': 1,
      'stage': 1,
      'name': name,
      'releaseStatus': releaseDate == null ? 'notYetOpen' : 'open',
      'tracking': 'songs',
      'conditionText': '测试',
      if (releaseDate != null) 'releaseDate': releaseDate,
      'requirement': {'type': 'playAll', 'songKeys': songKeys},
    });

LxnsScore _score(int songId, String lastPlayed) => LxnsScore(
      songId: songId,
      level: LxnsLevel.master,
      score: 1000000,
      lastPlayedTime: DateTime.parse(lastPlayed),
    );

/// 就是用户遇到的那两个门：ORIGIN（已开）和 PARADISE（未开），
/// 都收录了 `music:180`（怒槌）。
List<Gate> _originAndParadise() => [
      _gate(
        id: 'origin',
        name: 'Linked GATE ORIGIN',
        songKeys: ['music:180', 'music:53'],
        releaseDate: '2026-09-10T10:00',
      ),
      _gate(
        id: 'paradise',
        name: 'Linked GATE PARADISE',
        songKeys: ['music:180', 'music:629'],
        // 没有 releaseDate = 未开放
      ),
    ];

const _cutoff = '2026-09-10T10:00';

void main() {
  group('skipNotYetOpen：未开放的门不参与判定（两个怒槌的根因）', () {
    test('★ 默认跳过未开放的门：怒槌只出现一次（来自 ORIGIN）', () {
      final report = evaluateAllGates(
        gates: _originAndParadise(),
        cutoffOf: (_) => DateTime.parse(_cutoff),
        // 怒槌在开门后有成绩，且只在 ORIGIN 里勾了
        scores: [_score(180, '2026-09-16T10:00')],
        isTicked: (gateId, key) => gateId == 'origin' && key == 'music:180',
        titleOf: (k) => k == 'music:180' ? '怒槌' : k,
        songIdOf: (k) => k.split(':').last,
      );

      final nazuchi = report.results.where((r) => r.entryKey == 'music:180').toList();

      expect(nazuchi.length, 1,
          reason: 'PARADISE 还没开放，不该再为同一个 key 产生第二条结果 '
              '—— 这就是用户看到的「两个怒槌」');
      expect(nazuchi.single.gateId, 'origin');
      expect(report.skippedNotOpen, 1, reason: '应当报告跳过了 1 个未开放的门');
      expect(report.scannedGates, 1);
    });

    test('未开放的门如果出现在结果里，就会产生「已勾选但没证据」的假提示', () {
      // 关掉跳过 -> 复现 bug。这个测试同时证明了「跳过」确实是修复：
      // 它断言在旧行为下确实会多出一条。
      final report = evaluateAllGates(
        gates: _originAndParadise(),
        cutoffOf: (_) => DateTime.parse(_cutoff),
        scores: [_score(180, '2026-09-16T10:00')],
        isTicked: (gateId, key) => gateId == 'origin' && key == 'music:180',
        titleOf: (k) => k,
        songIdOf: (k) => k.split(':').last,
        skipNotYetOpen: false,
      );

      final nazuchi = report.results.where((r) => r.entryKey == 'music:180').toList();
      expect(nazuchi.length, 2, reason: '关掉跳过就会回到「两个怒槌」的旧行为');
      expect(nazuchi.map((r) => r.gateId).toSet(), {'origin', 'paradise'});
    });

    test('releaseDate 还没到 -> 跳过', () {
      final future = DateTime.now().add(const Duration(days: 30));
      final report = evaluateAllGates(
        gates: [
          _gate(
            id: 'future',
            name: '未来门',
            songKeys: ['music:1'],
            releaseDate: '${future.year}-'
                '${future.month.toString().padLeft(2, '0')}-'
                '${future.day.toString().padLeft(2, '0')}T10:00',
          ),
        ],
        cutoffOf: (_) => DateTime.parse(_cutoff),
        scores: [_score(1, '2026-09-16T10:00')],
        isTicked: (_, __) => false,
        titleOf: (k) => k,
        songIdOf: (k) => k.split(':').last,
      );
      expect(report.results, isEmpty);
      expect(report.skippedNotOpen, 1);
    });

    test('releaseDate 已过 -> 照常判定', () {
      final report = evaluateAllGates(
        gates: [
          _gate(
            id: 'origin',
            name: 'Linked GATE ORIGIN',
            songKeys: ['music:180'],
            releaseDate: '2026-09-10T10:00', // 已过
          ),
        ],
        cutoffOf: (_) => DateTime.parse(_cutoff),
        scores: [_score(180, '2026-09-16T10:00')],
        isTicked: (_, __) => false,
        titleOf: (k) => k,
        songIdOf: (k) => k.split(':').last,
      );
      expect(report.skippedNotOpen, 0);
      expect(report.results.length, 1);
      expect(report.results.single.verdict, LxnsVerdict.confirmed);
    });

    test('奖励页（isReward）不受影响，照旧被跳过且不计入 skippedNotOpen', () {
      final reward = Gate.fromJson({
        'id': 'reward',
        'order': 14,
        'stage': 3,
        'name': '奖励乐曲',
        'kind': 'reward',
        'releaseStatus': 'locked',
        'tracking': 'auto',
        'conditionText': '测试',
        'requirement': {'type': 'clearAllPrev'},
      });
      final report = evaluateAllGates(
        gates: [reward],
        cutoffOf: (_) => null,
        scores: const [],
        isTicked: (_, __) => false,
        titleOf: (k) => k,
        songIdOf: (k) => k.split(':').last,
      );
      expect(report.results, isEmpty);
      expect(report.skippedNotOpen, 0, reason: '奖励页不是「未开放的门」，不该计入');
    });
  });
}
