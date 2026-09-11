import '../models/class_course.dart';
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
  ClassData? classData,
}) {
  switch (gate.tracking) {
    case TrackingKind.songs:
      if (gate.requirement.type == 'playAnyOfEach') {
        // 每组可以打多首，只要该组里**有一首**打过就算这组完成。
        // 所以和普通曲目共用同一份打勾记录（store.tickedOf），
        // 判定的是「有几组已经至少打过一首」。
        final ticked = store.tickedOf(gate.id);
        var done = 0;
        for (final g in gate.requirement.groups) {
          if (g.itemKeys.any(ticked.contains)) done++;
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
      // AIR 门的解锁条件是「拿到一个缎带」= **任一** CLASS 内所有组曲通关。
      // 按段位组曲的勾选自动判定（不再用手动确认开关）。
      if (classData == null || classData.tiers.isEmpty) {
        return const GateStatus(unlocked: false, doneCount: 0, totalCount: 0);
      }
      final doneCourses = store.courseDoneOf(gate.id);
      // 找「最接近完成」的那个等级来显示进度，这样一眼知道该补哪个
      ClassTier? best;
      var bestDone = -1;
      for (final t in classData.tiers) {
        final d = classData.doneIn(t, doneCourses);
        if (d > bestDone) {
          bestDone = d;
          best = t;
        }
      }
      final total = best?.courses.length ?? 0;
      return GateStatus(
        unlocked: classData.ribbonAchieved(doneCourses),
        doneCount: bestDone < 0 ? 0 : bestDone,
        totalCount: total,
      );

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
Map<String, GateStatus> evaluateAll(
  List<Gate> gates,
  ProgressStore store, {
  ClassData? classData,
}) {
  final result = <String, GateStatus>{};

  // 先算不依赖别的门的
  for (final g in gates) {
    if (g.tracking != TrackingKind.auto) {
      result[g.id] = evaluateGate(g, store, classData: classData);
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
        classData: classData,
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
