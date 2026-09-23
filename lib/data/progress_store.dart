import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 打勾进度的本地存档。
///
/// **只存手机本地，永不上传。**
///
/// 存档按「门 id + 条目 linkId」关联，**不用数组下标**：
/// 以后更新 `gates.json`（加新门、改曲目）不会错位覆盖你的进度。
/// 数据层与存档层完全分离：同步数据**永远不碰**这里。
///
/// 存储键：
/// - `p:<gateId>`  条目打勾   -> `{"music:51": "ISO时间"}`
///   （PARADISE 那种「每位曲师任打一首」也用这个：每组里有一首打过即算该组完成）
/// - `m:<gateId>`  手动确认   -> `"ISO时间"`
/// - `c:<gateId>`  段位组曲   -> `{"III-1": "ISO时间"}`
class ProgressStore extends ChangeNotifier {
  ProgressStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _prefixItem = 'p:';
  static const _prefixManual = 'm:';
  static const _prefixCourse = 'c:';
  static const _keySchema = 'schemaVersion';

  // 段位缎带（落雪同步来的）。**独立的键，不复用 `m:` 前缀** ——
  // `m:` 是 `m:<gateId>` 形式的「手动确认门达成」，语义不同，
  // 混用会让 `isManualDone('')` 这类调用读到缎带数据。
  static const _keyRibbonBase = 'lxns.ribbon.base';
  static const _keyRibbonMedal = 'lxns.ribbon.medal';
  static const _keyRibbonAt = 'lxns.ribbon.fetchedAt';

  static const _currentSchema = 1;

  static Future<ProgressStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keySchema)) {
      await prefs.setInt(_keySchema, _currentSchema);
    }
    return ProgressStore._(prefs);
  }

  // ---------------------------------------------------------------- 读

  Set<String> tickedOf(String gateId) {
    final raw = _prefs.getString('$_prefixItem$gateId');
    if (raw == null) return <String>{};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.keys.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  bool isTicked(String gateId, String itemKey) => tickedOf(gateId).contains(itemKey);

  bool isManualDone(String gateId) => _prefs.getString('$_prefixManual$gateId') != null;

  String? manualDoneAt(String gateId) => _prefs.getString('$_prefixManual$gateId');

  /// 段位：已完成的组曲 key 集合
  Set<String> courseDoneOf(String gateId) {
    final raw = _prefs.getString('$_prefixCourse$gateId');
    if (raw == null) return <String>{};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.keys.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  bool isCourseDone(String gateId, String courseKey) =>
      courseDoneOf(gateId).contains(courseKey);

  // ---------------------------------------------------------------- 写

  Future<void> toggle(String gateId, String itemKey) async {
    final map = _rawTicked(gateId);
    if (map.containsKey(itemKey)) {
      map.remove(itemKey);
    } else {
      map[itemKey] = _now();
    }
    await _prefs.setString('$_prefixItem$gateId', jsonEncode(map));
    notifyListeners();
  }

  /// 手动确认整个门达成（AIR 的段位 / CRYSTAL 的条件未知 / UNIVERSE 的剩余血量）
  Future<void> setManualDone(String gateId, bool done) async {
    if (done) {
      await _prefs.setString('$_prefixManual$gateId', _now());
    } else {
      await _prefs.remove('$_prefixManual$gateId');
    }
    notifyListeners();
  }

  /// 一次勾多首（RE:VERSE 的「整张地图已完成」快捷勾选）
  Future<void> tickAll(String gateId, Iterable<String> itemKeys) async {
    final map = _rawTicked(gateId);
    for (final k in itemKeys) {
      map[k] = _now();
    }
    await _prefs.setString('$_prefixItem$gateId', jsonEncode(map));
    notifyListeners();
  }

  // ------------------------------------------------------- 段位缎带（落雪同步）

  /// 保存从落雪查分器读到的段位缎带值。
  ///
  /// 为什么要存**原始数值**而不是一个布尔值：
  ///   * `base` 是段位序号（实测通 CLASS Ⅲ 得 3）。存下来以后如果要做
  ///     「你的缎带是哪个段位」这种显示，数据就已经在了，不用重新拉；
  ///   * 存布尔值会丢掉「有没有缎带」和「是哪个缎带」的区别，
  ///     而后者以后很可能要用。
  ///
  /// AIR 门的判定只读 [ribbonBase] > 0（见 [hasSyncedRibbon]）。
  Future<void> setRibbon({required int base, required int medal, String? fetchedAt}) async {
    await _prefs.setInt(_keyRibbonBase, base);
    await _prefs.setInt(_keyRibbonMedal, medal);
    await _prefs.setString(_keyRibbonAt, fetchedAt ?? _now());
    notifyListeners();
  }

  /// 清掉本机保存的缎带数据（换账号 / 密钥失效时用）。
  Future<void> clearRibbon() async {
    await _prefs.remove(_keyRibbonBase);
    await _prefs.remove(_keyRibbonMedal);
    await _prefs.remove(_keyRibbonAt);
    notifyListeners();
  }

  /// 落雪记录的缎带段位序号。**没同步过返回 null**（不是 0）。
  ///
  /// 「没同步过」和「同步过但值为 0（确认没缎带）」必须区分：
  /// 前者不能拿去判定，后者可以。混为一谈会让 AIR 门在没同步时
  /// 静默显示成「未解锁」，而用户其实可能已经拿到了。
  int? get ribbonBase => _prefs.getInt(_keyRibbonBase);

  /// 落雪记录的勋章值（通关任意一组），同样是 null = 没同步过。
  int? get ribbonMedal => _prefs.getInt(_keyRibbonMedal);

  /// 落雪上次同步缎带的时间。
  String? get ribbonFetchedAt => _prefs.getString(_keyRibbonAt);

  /// 是否**确认**已获得缎带（必须同步过，且 base > 0）。
  bool get hasSyncedRibbon => (ribbonBase ?? 0) > 0;

  /// 段位：一次把**多个组曲**标记为已完成。
  ///
  /// 为什么单独一个方法而不是复用 [tickAll]：段位组曲存在 `c:` 命名空间下
  /// （[courseDoneOf] 读的就是它），而复用 `p:` 的 [tickAll] 会写到另一个地方，
  /// 表现出「勾了但界面没反应」。两者的存储结构确实一样，但**语义不同**，
  /// 分开写能避免以后有人把其中一个的存储格式改了却忘了另一个。
  ///
  /// 只在**缺**的键上加时间戳，已有的保留原时间 —— 免得重复同步时
  /// 把「什么时候勾的」这个信息刷成现在。
  Future<void> tickAllCourses(String gateId, Iterable<String> courseKeys) async {
    final existing = courseDoneOf(gateId);
    final map = _rawCourse(gateId);
    var changed = false;
    for (final k in courseKeys) {
      if (existing.contains(k)) continue;
      map[k] = _now();
      changed = true;
    }
    if (!changed) return; // 没有变化就不要写、不要 notify，避免无谓重建
    await _prefs.setString('$_prefixCourse$gateId', jsonEncode(map));
    notifyListeners();
  }

  /// 读某个门的段位组曲原始 map（`{courseKey: 时间}`）
  Map<String, dynamic> _rawCourse(String gateId) {
    final raw = _prefs.getString('$_prefixCourse$gateId');
    if (raw == null) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 段位：切换某个组曲的完成状态
  Future<void> toggleCourse(String gateId, String courseKey) async {
    final map = _rawCourse(gateId);
    if (map.containsKey(courseKey)) {
      map.remove(courseKey);
    } else {
      map[courseKey] = _now();
    }
    await _prefs.setString('$_prefixCourse$gateId', jsonEncode(map));
    notifyListeners();
  }

  /// 清空某个门的进度
  Future<void> resetGate(String gateId) async {
    await _prefs.remove('$_prefixItem$gateId');
    await _prefs.remove('$_prefixManual$gateId');
    await _prefs.remove('$_prefixCourse$gateId');
    notifyListeners();
  }

  // ---------------------------------------------------------------- 内部

  Map<String, dynamic> _rawTicked(String gateId) {
    final raw = _prefs.getString('$_prefixItem$gateId');
    if (raw == null) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _now() => DateTime.now().toIso8601String();
}
