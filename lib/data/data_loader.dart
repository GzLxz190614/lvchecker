import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/entry.dart';
import '../models/gate.dart';

/// 数据层加载器。
///
/// M1 只从 APK 内置资源读。M3 会在这里插入「本地缓存 → 在线同步」两级，
/// 但**永远不会碰用户存档**（那是 ProgressStore 的事）。
class DataLoader {
  const DataLoader();

  static const _gatesPath = 'data/gates.json';
  static const _metaPath = 'data/meta.json';

  Future<AppData> load() async {
    final gatesJson = jsonDecode(await rootBundle.loadString(_gatesPath));
    final metaJson = jsonDecode(await rootBundle.loadString(_metaPath));

    final gateData = GateData.fromJson((gatesJson as Map).cast<String, dynamic>());
    final meta = MetaTable.fromJson((metaJson as Map).cast<String, dynamic>());

    return AppData(gateData: gateData, meta: meta);
  }
}

/// 加载好的全部只读数据。
class AppData {
  const AppData({required this.gateData, required this.meta});

  final GateData gateData;
  final MetaTable meta;

  /// 按 id 找门
  Gate? gateById(String id) {
    for (final g in gateData.gates) {
      if (g.id == id) return g;
    }
    return null;
  }
}
