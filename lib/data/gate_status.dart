import '../models/gate.dart';
import 'progress_store.dart';

/// 门的解锁判定。
///
/// 这个结果同时驱动两件事：
/// ① 顶栏显示「已解锁」；② 页面底部 BOSS 区块是否渲染。
class GateStatus {
  const GateStatus({required this.unlocked, required this.doneCount, required this.totalCount});

  final bool unlocked;
  final int doneCount;
  final int totalCount;

  String get progressLabel => totalCount == 0 ? '' : '$doneCount / $totalCount';
}

/// 计算某个门的解锁状态。
///
/// [statusOf] 用于递归解析前置门（X-VERSE / 奖励乐曲依赖「前面所有门」）。
/// 传入的函数应当是已经算好的前置门状态，避免循环依赖。
GateStatus evaluateGate(
  Gate gate,
  ProgressStore store, {
  bool Function(String gateId)? prerequisiteUnlocked,
}) {
  switch (gate.tracking) {
    case TrackingKind.songs:
      if (gate.requirement.type == 'playAnyOfEach') {
        final chosen = store.groupTickedOf(gate.id);
        var done = 0;
        for (final g in gate.requirement.groups) {
          if (chosen.containsKey(g.key)) done++;
        }
        final total = gate.requirement.groups.length;
        return GateStatus(unlocked: total > 0 && done == total, doneCount: done, totalCount: total);
      }
      final ticked = store.tickedOf(gate.id);
      final total = gate.requirement.songKeys.length;
      final done = gate.requirement.songKeys.where(ticked.contains).length;
      return GateStatus(unlocked: total > 0 && done == total, doneCount: done, totalCount: total);

    case TrackingKind.items:
      final ticked = store.tickedOf(gate.id);
      final total = gate.requirement.itemKeys.length;
      final done = gate.requirement.itemKeys.where(ticked.contains).length;
      return GateStatus(unlocked: total > 0 && done == total, doneCount: done, totalCount: total);

    case TrackingKind.classes:
      // 段位课程要等课程 XML（M5）。在此之前只按手动确认处理。
      final done = store.isManualDone(gate.id);
      return GateStatus(unlocked: done, doneCount: done ? 1 : 0, totalCount: 1);

    case TrackingKind.auto:
      // 前置门全部解锁即自动达成
      final prereq = gate.prerequisites;
      if (prereq.isEmpty) return const GateStatus(unlocked: false, doneCount: 0, totalCount: 0);
      var ok = 0;
      for (final id in prereq) {
        if (prerequisiteUnlocked?.call(id) ?? false) ok++;
      }
      return GateStatus(unlocked: ok == prereq.length, doneCount: ok, totalCount: prereq.length);

    case TrackingKind.remainingHp:
    case TrackingKind.manual:
      final done = store.isManualDone(gate.id);
      return GateStatus(unlocked: done, doneCount: done ? 1 : 0, totalCount: 1);
  }
}

/// 一次性算出所有门的状态。
///
/// 门数量固定且很少（14 个），直接迭代若干轮即可解析依赖，
/// 不需要引入图算法。
Map<String, GateStatus> evaluateAll(List<Gate> gates, ProgressStore store) {
  final result = <String, GateStatus>{};

  // 先算不依赖别的门的
  for (final g in gates) {
    if (g.tracking != TrackingKind.auto) {
      result[g.id] = evaluateGate(g, store);
    }
  }
  // auto 类型依赖前置门。按 order 升序迭代，最多跑 N 轮处理链式依赖
  // （例如 奖励乐曲 -> universe -> reverse -> xverse -> Stage 1 全部门）。
  final autos = gates.where((g) => g.tracking == TrackingKind.auto).toList();
  for (var round = 0; round < gates.length; round++) {
    var changed = false;
    for (final g in autos) {
      final s = evaluateGate(
        g,
        store,
        prerequisiteUnlocked: (id) => result[id]?.unlocked ?? false,
      );
      final prev = result[g.id];
      if (prev == null || prev.unlocked != s.unlocked || prev.doneCount != s.doneCount) {
        changed = true;
      }
      result[g.id] = s;
    }
    if (!changed) break;
  }
  return result;
}
