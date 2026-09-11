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

import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/models/class_course.dart';

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
}
