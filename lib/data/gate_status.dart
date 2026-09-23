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

/// 条目型条件的判定，**不依赖 ProgressStore**（只看「哪些条目已勾选」）。
///
/// 抽成独立函数是为了能**纯函数式地测**：STAR 门的「两步都要完成」这条规则
/// 之前是错的（只判了角色卡），需要一个不碰 SharedPreferences 的入口来钉住它。
/// [evaluateGate] 内部从 store 取出勾选集合后调用这里。
///
/// 两种条件的条目来源不同：
///   - `itemsInSteps`（STAR）：把所有 step 的 itemKeys 拼起来 —— 两步都要完成；
///   - `items`（NEW / LUMINOUS）：直接用 itemKeys。
///
/// ⚠️ `total > 0` 这个前提不能去掉：条目全为空时（例如 steps 写错了）
/// 若只判 `done == total`，会得到 `0 == 0` → **门被判定为已解锁**。
GateStatus itemsStatus(Gate gate, Set<String> ticked) {
  final itemKeys = gate.requirement.type == 'itemsInSteps'
      ? gate.requirement.allStepItemKeys
      : gate.requirement.itemKeys;
  final total = itemKeys.length;
  final done = itemKeys.where(ticked.contains).length;
  return GateStatus(unlocked: total > 0 && done == total, doneCount: done, totalCount: total);
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
      // STAR 是「先获得角色，再升到 RANK 15」两步条件，两步都要完成门才通。
      // 判定上它和普通 items 一样是「这些条目全部完成」——
      // 区别只在**显示**（分区、各自带进度），所以这里共用同一段逻辑，
      // 只是条目来源从 itemKeys 换成把各步的 itemKeys 拼起来。
      //
      // 为什么不能只判 itemKeys：那样 STAR 会退化成「勾上角色卡 = 门通」，
      // 角色只有 RANK 1 也算过 —— 这正是之前的问题。
      return itemsStatus(gate, ticked);

    case TrackingKind.classes:
      // AIR 门的解锁条件是「拿到一个缎带」= **任一** CLASS 内所有组曲通关。
      //
      // 有两个独立来源能证明「有缎带」，取并集：
      //   ① 落雪查分器同步来的 class_emblem.base > 0 —— 机台的真实状态；
      //   ② 用户在本机逐个勾选组曲，勾满某个 CLASS。
      //
      // 为什么要两个都要：①是权威的，但需要配置密钥并同步过；
      // ②在没同步时仍然可用（也是这次改造之前唯一的办法）。
      // 只用①会让没配密钥的人完全没法标记；只用②就会出现
      // 「机台上明明通关了、App 里还得手动勾 5 个组曲」。
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
      // 落雪确认有缎带时，进度也显示成「满」：
      // 否则会出现「已解锁但有缎带 0/5」这种自相矛盾的界面。
      final synced = store.hasSyncedRibbon;
      return GateStatus(
        unlocked: synced || classData.ribbonAchieved(doneCourses),
        doneCount: synced ? total : (bestDone < 0 ? 0 : bestDone),
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
