import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 某个门的完成状态。
///
/// 存档设计要点：
/// - 用「门 id + 条目 linkId」关联，**不用数组下标**。
///   这样以后更新 `gates.json`（加新门、改曲目）不会错位覆盖你的进度。
/// - 数据层与存档层完全分离：同步数据**永远不碰**这里。
class GateProgress {
  const GateProgress({
    this.ticked = const {},
    this.groupTicked = const {},
    this.manualDone = false,
    this.manualDoneAt,
  });

  /// 已完成的条目：linkId -> 完成时间
  final Map<String, String> ticked;

  /// `playAnyOfEach` 类型：组 key -> 该组已选的 linkId
  final Map<String, String> groupTicked;

  /// 整个门手动确认完成（CRYSTAL / UNIVERSE）
  final bool manualDone;
  final String? manualDoneAt;
}

/// 打勾进度的本地存档。
///
/// **只存手机本地，永不上传。**
class ProgressStore extends ChangeNotifier {
  ProgressStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _prefixItem = 'p:'; // 条目打勾    p:<gateId>      -> {"music:51": "ISO时间"}
  static const _prefixGroup = 'g:'; // 分组选择    g:<gateId>      -> {"光吉猛修": "music:180"}
  static const _prefixManual = 'm:'; // 手动确认    m:<gateId>      -> "ISO时间"
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

  Map<String, String> groupTickedOf(String gateId) {
    final raw = _prefs.getString('$_prefixGroup$gateId');
    if (raw == null) return <String, String>{};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  String? groupChoice(String gateId, String groupKey) => groupTickedOf(gateId)[groupKey];

  bool isManualDone(String gateId) => _prefs.getString('$_prefixManual$gateId') != null;

  String? manualDoneAt(String gateId) => _prefs.getString('$_prefixManual$gateId');

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

  /// `playAnyOfEach`：选中某组里的一首。再点同一首则取消。
  Future<void> selectInGroup(String gateId, String groupKey, String itemKey) async {
    final map = groupTickedOf(gateId);
    if (map[groupKey] == itemKey) {
      map.remove(groupKey);
    } else {
      map[groupKey] = itemKey;
    }
    await _prefs.setString('$_prefixGroup$gateId', jsonEncode(map));
    notifyListeners();
  }

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

  /// 清空某个门的进度
  Future<void> resetGate(String gateId) async {
    await _prefs.remove('$_prefixItem$gateId');
    await _prefs.remove('$_prefixGroup$gateId');
    await _prefs.remove('$_prefixManual$gateId');
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
