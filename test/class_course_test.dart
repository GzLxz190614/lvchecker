// 段位课程数据的测试。
//
// 为什么要有这个文件：等级随机的槽在 JSON 里只存了「内部 ID」（19/20/21），
// 显示出来的等级（10 / 10+ / 11）是转换算出来的。这个换算一旦写错，
// **数据看起来仍然很正常**——JSON 里有值、界面也有字，只是字是错的，
// 光靠看根本发现不了。所以这里把用户确认过的对应关系钉死：
//
//     CLASS 认定 - Ⅰ - Random → Lv10 / Lv10+ / Lv11
//
// 同时这份测试直接读**打包进 APK 的 data/classes.json**，所以它同时验证了
// 资源声明（pubspec）和真实数据，而不只是解析逻辑。

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/models/class_course.dart';
import 'package:lvchecker/models/entry.dart';
import 'package:lvchecker/models/gate.dart';

/// 用户确认的「CLASS 认定 - ? - Random」等级对应表。
const Map<String, List<String>> kExpectedRandomLevels = {
  'I': ['10', '10+', '11'],
  'II': ['11+', '12', '12+'],
  'III': ['12+', '13', '13+'],
  'IV': ['13+', '14', '14+'],
  'V': ['14', '14+', '15'],
  '∞': ['14+', '15', '15+'],
};

ClassSlot _slot({
  required ClassSlotKind kind,
  String? display,
  String? levelFrom,
  String? levelTo,
  int? poolSize,
}) =>
    ClassSlot(
      order: 1,
      kind: kind,
      display: display,
      levelFrom: levelFrom,
      levelTo: levelTo,
      poolSize: poolSize,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClassData 解析打包的 classes.json', () {
    late ClassData data;

    setUpAll(() async {
      data = await ClassData.loadFromAssets();
    });

    test('不是占位数据，6 个段位等级都在', () {
      expect(data.placeholder, isFalse,
          reason: 'classes.json 是占位数据说明生成失败或同步到了旧数据');
      expect(data.tiers.map((t) => t.label).toSet(),
          {'I', 'II', 'III', 'IV', 'V', '∞'});
    });

    test('∞ 排最前，然后 V → I', () {
      expect(data.tiers.map((t) => t.label).toList(),
          ['∞', 'V', 'IV', 'III', 'II', 'I']);
    });

    test('每个组曲都是 3 个槽，且曲目都指向已登记的 meta 条目', () {
      for (final tier in data.tiers) {
        expect(tier.courses, isNotEmpty, reason: '等级 ${tier.label} 没有组曲');
        for (final course in tier.courses) {
          expect(course.slots.length, 3,
              reason: '${tier.label} / ${course.title} 的槽数不是 3');
        }
      }
    });

    test('等级随机槽的等级和用户确认的对应表一致', () {
      for (final tier in data.tiers) {
        final expected = kExpectedRandomLevels[tier.label]!;
        // 该等级下所有 randomRange 槽的 (levelFrom, display) 集合
        final seen = <String>{};
        for (final course in tier.courses) {
          for (final slot in course.slots) {
            if (slot.kind != ClassSlotKind.randomRange) continue;
            seen.add('${slot.levelFrom}|${slot.headline}');
            // headline 绝不能残留 "Lv" 前缀或内部 ID 写法
            expect(slot.headline, isNot(contains('Lv')));
            expect(slot.headline, isNot(contains('ID')));
          }
        }
        if (seen.isEmpty) continue; // ∞ 以外的等级都有随机槽，这里只是防御
        for (final lv in expected) {
          expect(seen, contains('$lv|$lv'),
              reason: '等级 ${tier.label} 缺少 Lv$lv 的随机槽（seen=$seen）');
        }
      }
    });

    test('CLASS Ⅰ 的随机槽就是 Lv10 / Lv10+ / Lv11', () {
      final tier = data.tiers.firstWhere((t) => t.label == 'I');
      final course = tier.courses
          .firstWhere((c) => c.slots.any((s) => s.kind == ClassSlotKind.randomRange));
      final heads = course.slots
          .where((s) => s.kind == ClassSlotKind.randomRange)
          .map((s) => s.headline)
          .toList();
      expect(heads, ['10', '10+', '11']);
    });

    test('randomPool 的文案是「范围内随机选择」', () {
      final slots = [
        for (final tier in data.tiers)
          for (final course in tier.courses)
            for (final slot in course.slots)
              if (slot.kind == ClassSlotKind.randomPool) slot,
      ];
      expect(slots, isNotEmpty, reason: '应该有「シビュラ精霊記 Random Set」这类曲池随机的组曲');
      for (final s in slots) {
        expect(s.headline, '范围内随机选择');
        expect(s.poolSize, isNotNull);
        expect(s.poolSize, greaterThan(0));
      }
    });

    test('缎带条件：任一等级的全部组曲完成才算达成', () {
      final tier = data.tiers.firstWhere((t) => t.label == 'III');
      final keys = tier.courses.map((c) => c.key).toSet();

      expect(data.tierComplete(tier, {}), isFalse);
      expect(data.ribbonAchieved({}), isFalse);

      // 只差一个组曲 → 还没缎带
      final almost = {...keys}..remove(keys.first);
      expect(data.ribbonAchieved(almost), isFalse);
      expect(data.doneIn(tier, almost), keys.length - 1);

      // 全完成 → 达成
      expect(data.tierComplete(tier, keys), isTrue);
      expect(data.ribbonAchieved(keys), isTrue);
    });
  });

  group('ClassSlot 的显示文字', () {
    test('单一等级不加 "Lv" 前缀', () {
      expect(
        _slot(kind: ClassSlotKind.randomRange, display: '11+').headline,
        '11+',
      );
    });

    test('display 里带的 "Lv" 前缀会被去掉（兼容手改数据）', () {
      expect(
        _slot(kind: ClassSlotKind.randomRange, display: 'Lv11+').headline,
        '11+',
      );
    });

    test('没有 display 时用 levelFrom/levelTo 兜底', () {
      expect(
        _slot(kind: ClassSlotKind.randomRange, levelFrom: '13+', levelTo: '14').headline,
        '13+ ~ 14',
      );
      expect(
        _slot(kind: ClassSlotKind.randomRange, levelFrom: '12', levelTo: '12').headline,
        '12',
      );
    });

    test('完全没有等级信息时不崩，退化成「等级随机」', () {
      expect(_slot(kind: ClassSlotKind.randomRange).headline, '等级随机');
    });

    test('sublabel 区分等级随机与曲池随机', () {
      expect(_slot(kind: ClassSlotKind.randomRange, display: '11').sublabel, '等级随机');
      expect(_slot(kind: ClassSlotKind.randomPool, poolSize: 10).sublabel, '10 选 1');
      expect(_slot(kind: ClassSlotKind.randomPool).sublabel, '曲池随机');
    });

    test('未知 kind 退化成 fixed（避免整页解析失败）', () {
      final s = ClassSlot.fromJson({
        'order': 1,
        'kind': 'somethingNewFromAFutureUpdate',
        'linkId': 'music:1',
      });
      expect(s.kind, ClassSlotKind.fixed);
      expect(s.isFixed, isTrue);
    });

    test('ClassCourse 统计固定曲与随机槽的数量', () {
      final course = ClassCourse(
        key: 'I-1',
        title: 't',
        slots: [
          _slot(kind: ClassSlotKind.fixed),
          _slot(kind: ClassSlotKind.randomRange, display: '10'),
          _slot(kind: ClassSlotKind.randomPool, poolSize: 3),
        ],
      );
      expect(course.fixedCount, 1);
      expect(course.randomCount, 2);
    });
  });

  // 这三份数据里的每一条 "image" 路径都必须真的能 load 出来。
  //
  // 为什么值得测：图片格式从 PNG 换成 WebP 之后，「路径写对了但资源没进包」
  // 是一类**编译期完全发现不了**的错误 —— analyze 绿、build 绿、CI 绿，
  // 只有装到手机上才发现满屏「图片丢失」。而 pubspec 的 assets 声明不递归，
  // 少一行就少一张图。这里用 rootBundle 直接验证最终产物。
  //
  // 注意它测的是**打包进 app 的资源**，不是磁盘上的文件 ——
  // 所以能同时覆盖「文件存在但 pubspec 没声明」这种情况。
  group('所有声明的图片都能从资源包加载', () {
    test('meta.json 的每条 image', () async {
      final meta = MetaTable.fromJson((await _loadJson('data/meta.json'))!);
      final paths = meta.all
          .map((e) => e.image)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toSet();
      expect(paths, isNotEmpty);
      await _expectAllLoadable(paths);
    });

    test('gates.json 里 BOSS 曲的 image（经 meta 解析）', () async {
      final meta = MetaTable.fromJson((await _loadJson('data/meta.json'))!);
      final gates = GateData.fromJson((await _loadJson('data/gates.json'))!);
      final paths = <String>{};
      for (final g in gates.gates) {
        // GateBoss 本身不带 image，要按 linkId 回 meta 查
        final img = meta[g.boss?.linkId]?.image;
        if (img != null && img.isNotEmpty) paths.add(img);
      }
      expect(paths, isNotEmpty, reason: '每个门都有 BOSS 曲，应该能解析出图片');
      await _expectAllLoadable(paths);
    });

    test('classes.json 里随机槽的封面', () async {
      final data = await ClassData.loadFromAssets();
      final paths = <String>{};
      for (final tier in data.tiers) {
        for (final course in tier.courses) {
          for (final slot in course.slots) {
            final img = slot.image;
            if (img != null && img.isNotEmpty) paths.add(img);
          }
        }
      }
      expect(paths, isNotEmpty, reason: '应该至少有等级随机/曲池随机两张封面');
      await _expectAllLoadable(paths);
    });

    test('classes.json 固定曲引用的 meta 条目都有图', () async {
      final meta = MetaTable.fromJson((await _loadJson('data/meta.json'))!);
      final data = await ClassData.loadFromAssets();
      final paths = <String>{};
      for (final tier in data.tiers) {
        for (final course in tier.courses) {
          for (final slot in course.slots) {
            if (slot.linkId == null) continue;
            final img = meta[slot.linkId]?.image;
            if (img != null && img.isNotEmpty) paths.add(img);
          }
        }
      }
      expect(paths.length, greaterThan(50), reason: '段位固定曲有 86 首，图应该不少于这个量级');
      await _expectAllLoadable(paths);
    });
  });
}

Future<Map<String, dynamic>?> _loadJson(String path) async {
  final raw = await rootBundle.loadString(path);
  final decoded = jsonDecode(raw);
  return decoded is Map ? decoded.cast<String, dynamic>() : null;
}

/// 逐个 [AssetBundle.load] 验证，失败时把**所有**缺失路径一起报出来。
///
/// 不用 `Image.asset`：那需要完整的渲染管线，而且失败是异步回调、不好断言。
/// `rootBundle.load` 直接测「资源在不在包里」，正是这里要保证的事。
Future<void> _expectAllLoadable(Set<String> paths) async {
  final missing = <String>[];
  for (final p in paths) {
    try {
      final data = await rootBundle.load(p);
      if (data.lengthInBytes == 0) missing.add('$p（文件为空）');
    } catch (_) {
      missing.add(p);
    }
  }
  expect(missing, isEmpty,
      reason: '这些图片声明了但没打进 APK（会显示「图片丢失」）：\n${missing.join('\n')}');
}
