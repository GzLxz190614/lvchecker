import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../models/class_course.dart';
import '../models/entry.dart';
import '../models/gate.dart';
import '../models/link_level.dart';
import 'data_sync.dart';

/// 某份数据是从哪来的。
enum DataOrigin {
  /// APK 内置（首次安装、且还没同步过）
  bundled,

  /// 本机缓存（同步成功过，之后离线也能用）
  cache;

  String get label => this == DataOrigin.bundled ? 'APK 内置' : '本机缓存';
}

/// 加载结果：数据 + 来源信息（设置页会显示，便于排查）。
class LoadedData {
  const LoadedData({
    required this.gateData,
    required this.meta,
    required this.linkLevels,
    required this.classData,
    required this.origin,
  });

  final GateData gateData;
  final MetaTable meta;
  final LinkLevelData linkLevels;
  final ClassData classData;
  final DataOrigin origin;
}

/// 数据层加载器。
///
/// 三级加载，优先用最新的：
///   ① **本机缓存**（热更新下来的，最新）
///   ② **APK 内置**（首次安装或缓存损坏时兜底）
/// 每一级都先验证能解析，解析失败就降级到下一级——
/// 这样即使某一级的数据文件坏了，app 也能起来，不会白屏。
///
/// 注意：**永远不会碰用户存档**（那是 ProgressStore 的事）。
class DataLoader {
  const DataLoader();

  static const _gate = 'gates.json';
  static const _meta = 'meta.json';
  static const _link = 'linklevels.json';
  static const _classes = 'classes.json';

  /// 从缓存或内置资源读一份 JSON 文本。
  ///
  /// 返回值附带来源，用于在设置页显示「当前数据来自哪」。
  Future<(Map<String, dynamic>, DataOrigin)> _read(
    DataSync? sync,
    String name,
  ) async {
    // ① 本机缓存
    if (sync != null) {
      final f = sync.cacheFile(name);
      if (f.existsSync()) {
        try {
          final decoded = jsonDecode(await f.readAsString());
          if (decoded is Map) {
            return ((decoded).cast<String, dynamic>(), DataOrigin.cache);
          }
        } on FormatException {
          // 缓存坏了（比如写到一半断网），删掉它并降级
          try {
            await f.delete();
          } on FileSystemException {
            // 删不掉也无所谓，下次同步会覆盖
          }
        }
      }
    }

    // ② APK 内置
    final bundled = await rootBundle.loadString('data/$name');
    return ((jsonDecode(bundled) as Map).cast<String, dynamic>(), DataOrigin.bundled);
  }

  Future<LoadedData> load({DataSync? sync}) async {
    final (gatesJson, o1) = await _read(sync, _gate);
    final (metaJson, o2) = await _read(sync, _meta);
    final (linkJson, o3) = await _read(sync, _link);
    final (classJson, o4) = await _read(sync, _classes);

    // 来源以 gates.json 为准（热更新是整批下载的，正常不会只有一半新）
    final origin = o1;
    final mixed = {o1, o2, o3, o4}.length > 1;

    return LoadedData(
      gateData: GateData.fromJson(gatesJson),
      meta: MetaTable.fromJson(metaJson),
      linkLevels: LinkLevelData.fromJson(linkJson),
      classData: ClassData.fromJson(classJson),
      origin: mixed ? DataOrigin.cache : origin,
    );
  }
}

/// 兼容旧调用点的别名。
typedef AppData = LoadedData;
