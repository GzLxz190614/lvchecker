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

  /// 段位：切换某个组曲的完成状态
  Future<void> toggleCourse(String gateId, String courseKey) async {
    final raw = _prefs.getString('$_prefixCourse$gateId');
    Map<String, dynamic> map = <String, dynamic>{};
    if (raw != null) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        map = <String, dynamic>{};
      }
    }
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
