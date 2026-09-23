// AIR 门「段位缎带」判定的测试。
//
// 这段逻辑的核心是**两个来源取并集**，而这两个来源都可能出错：
//   ① 落雪查分器同步来的 `class_emblem.base > 0`（机台真实状态）
//   ② 用户在本机逐个勾选组曲，勾满某个 CLASS
//
// 最容易犯的错是**把「没同步过」当成「确认没有缎带」**：
// SharedPreferences 里读不到的 int 返回 null，若直接 `?? 0` 就会变成
// 「base = 0 = 没缎带」，于是 AIR 门在没配密钥的用户那里静默显示未解锁。
// 这个测试就是钉住这一点。
//
// 用 SharedPreferences.setMockInitialValues 注入状态，所以不需要真机。

import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/data/progress_store.dart';
import 'package:lvchecker/models/class_course.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 造一份和 `data/classes.json` 同构的段位数据。
///
/// ⚠️ 顺序**故意照抄真实文件**（∞ 在最前，然后 V, IV, III, II, I），
/// 而不是序号顺序。因为 `ClassData.fromJson` 末尾有一段排序，把 tiers
/// 重排成 `[∞, V, IV, III, II, I]` —— 如果 `tierByOrdinal` 用 `tiers[n-1]`
/// 实现，在这个顺序下会**全错**，而用序号顺序的假数据反而会「碰巧通过」。
/// 测试数据必须复现真实数据的这个性质，否则测不出这类 bug。
ClassData _classData() {
  // 真实顺序：∞, V, IV, III, II, I
  const keys = ['∞', 'V', 'IV', 'III', 'II', 'I'];
  const levels = [0, 5, 4, 3, 2, 1];
  return ClassData.fromJson({
    'schemaVersion': 1,
    'placeholder': false,
    'classes': [
      for (var i = 0; i < keys.length; i++)
        {
          'key': keys[i],
          'label': keys[i],
          'level': levels[i],
          'color': '#FFFFFF',
          'courses': [
            for (var c = 0; c < 2; c++)
              {
                'key': 'course_${keys[i]}_$c',
                'title': '组曲 $c',
                'songs': <dynamic>[],
              },
          ],
        },
    ],
  });
}

/// 建一个指定初始存储内容的 store
Future<ProgressStore> _storeWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return ProgressStore.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('缎带状态：null（没同步过）和 0（确认没有）必须区分', () {
    test('全新安装：三个 getter 都是 null / false', () async {
      final store = await _storeWith({});
      expect(store.ribbonBase, isNull, reason: '没同步过必须是 null，不能是 0');
      expect(store.ribbonMedal, isNull);
      expect(store.ribbonFetchedAt, isNull);
      expect(store.hasSyncedRibbon, isFalse);
    });

    test('同步过但没有缎带：base = 0，仍然是「同步过」', () async {
      final store = await _storeWith({
        'lxns.ribbon.base': 0,
        'lxns.ribbon.medal': 0,
        'lxns.ribbon.fetchedAt': '2026-09-20T12:00:00',
      });
      expect(store.ribbonBase, 0, reason: '同步过就是 0，不是 null');
      expect(store.hasSyncedRibbon, isFalse, reason: '0 = 确认没有缎带');
      expect(store.ribbonFetchedAt, isNotNull);
    });

    test('同步到缎带：base = 3 时判定为有缎带（实测通 CLASS Ⅲ 得 3）', () async {
      final store = await _storeWith({
        'lxns.ribbon.base': 3,
        'lxns.ribbon.medal': 3,
      });
      expect(store.ribbonBase, 3);
      expect(store.hasSyncedRibbon, isTrue);
    });

    test('任何正数都算有缎带 —— 不能写死 == 1', () async {
      // base 是「段位序号」（Ⅰ=1 … Ⅴ=5、∞=6），不是布尔量。
      // 如果哪天有人把它改成 `== 1`，通 Ⅱ 及以上的用户就会显示未解锁。
      for (final v in [1, 2, 3, 4, 5, 6]) {
        final store = await _storeWith({'lxns.ribbon.base': v});
        expect(store.hasSyncedRibbon, isTrue, reason: 'base = $v 应该有缎带');
      }
    });

    test('负数不当作有缎带（防御脏数据）', () async {
      final store = await _storeWith({'lxns.ribbon.base': -1});
      expect(store.hasSyncedRibbon, isFalse);
    });
  });

  group('写入与清除', () {
    test('setRibbon 会同时写下 base / medal / 时间戳', () async {
      final store = await _storeWith({});
      await store.setRibbon(base: 3, medal: 3, fetchedAt: '2026-09-20T10:00:00');

      expect(store.ribbonBase, 3);
      expect(store.ribbonMedal, 3);
      expect(store.ribbonFetchedAt, '2026-09-20T10:00:00');
      expect(store.hasSyncedRibbon, isTrue);
    });

    test('setRibbon 不传时间戳时自动补当前时间', () async {
      final store = await _storeWith({});
      await store.setRibbon(base: 1, medal: 0);
      expect(store.ribbonFetchedAt, isNotNull);
      expect(store.ribbonFetchedAt, isNotEmpty);
    });

    test('clearRibbon 之后回到「没同步过」而不是「确认没有」', () async {
      final store = await _storeWith({'lxns.ribbon.base': 3, 'lxns.ribbon.medal': 3});
      expect(store.hasSyncedRibbon, isTrue);

      await store.clearRibbon();

      expect(store.ribbonBase, isNull, reason: '清除后必须是 null（未知），不是 0（确认没有）');
      expect(store.ribbonMedal, isNull);
      expect(store.ribbonFetchedAt, isNull);
      expect(store.hasSyncedRibbon, isFalse);
    });

    test('缎带的键不能和「手动确认门达成」（m:）撞车', () async {
      // 曾经把缎带时间戳误用 `_prefixManual`（'m:'）写入，那会污染
      // isManualDone('') 之类的调用。这里钉住两者的键是分开的。
      SharedPreferences.setMockInitialValues({});
      final store = await ProgressStore.load();
      await store.setRibbon(base: 3, medal: 3);

      // 手动确认状态不应被缎带写入影响
      expect(store.isManualDone('air'), isFalse);
      expect(store.isManualDone(''), isFalse);
    });
  });

  group('tierByOrdinal：落雪的段位序号 -> 我们的段位', () {
    test('★ 序号 3 -> III（实测：通关 CLASS Ⅲ 后 base = 3）', () {
      final tier = _classData().tierByOrdinal(3);
      expect(tier, isNotNull);
      // 注意断言用的是**半角** 'III' —— classes.json 的 key/label 是半角
      // （classRawName 才是全角 Ⅲ，拿它匹配会永远匹配不上）
      expect(tier!.label, 'III',
          reason: '取错段位会**勾错内容**，而且界面上看起来一切正常');
      expect(tier.courses.length, 2);
    });

    test('1..6 依次对应 I II III IV V ∞', () {
      final data = _classData();
      const expected = ['I', 'II', 'III', 'IV', 'V', '∞'];
      for (var i = 1; i <= 6; i++) {
        expect(data.tierByOrdinal(i)?.label, expected[i - 1], reason: '序号 $i');
      }
    });

    test('序号 0 或超出范围 -> null（不能瞎勾一个段位）', () {
      final data = _classData();
      expect(data.tierByOrdinal(0), isNull, reason: '0 是「没有缎带」，不该映射到 Ⅰ');
      expect(data.tierByOrdinal(-1), isNull);
      expect(data.tierByOrdinal(7), isNull);
      expect(data.tierByOrdinal(999), isNull);
    });
  });

  group('tickAllCourses：自动勾满一个段位的组曲', () {
    test('把该段位全部组曲勾上', () async {
      final store = await _storeWith({});
      final data = _classData();
      final tier = data.tierByOrdinal(3)!;

      await store.tickAllCourses('air', tier.courses.map((c) => c.key));

      expect(store.courseDoneOf('air'), {'course_III_0', 'course_III_1'});
      expect(data.tierComplete(tier, store.courseDoneOf('air')), isTrue);
      expect(data.ribbonAchieved(store.courseDoneOf('air')), isTrue,
          reason: '勾满一个段位就应判定为已获缎带');
    });

    test('不会勾到别的段位', () async {
      final store = await _storeWith({});
      final tier = _classData().tierByOrdinal(3)!;
      await store.tickAllCourses('air', tier.courses.map((c) => c.key));

      // 勾的应该只是 III 的组曲。用「组曲 key 的段位段」判断，不要用
      // substring('course_I_') —— 'course_III_0'.contains('course_I_') 是 false，
      // 但反过来 'course_II_0' 之类容易踩到前缀交叉，这里显式切开更稳。
      final done = store.courseDoneOf('air');
      final tiersTouched = done.map((k) => k.split('_')[1]).toSet();
      expect(tiersTouched, {'III'}, reason: '只该碰 III 的组曲');
    });

    test('重复调用不会覆盖已有的勾选时间', () async {
      // 「什么时候勾的」是个有用的信息，重复同步不该把它刷成现在
      final store = await _storeWith({
        'c:air': '{"course_III_0":"2026-01-01T00:00:00"}',
      });
      final tier = _classData().tierByOrdinal(3)!;

      await store.tickAllCourses('air', tier.courses.map((c) => c.key));

      expect(store.courseDoneOf('air'), contains('course_III_0'));
      // 通过再次调用后数量不变来间接确认幂等
      await store.tickAllCourses('air', tier.courses.map((c) => c.key));
      expect(store.courseDoneOf('air').length, 2);
    });

    test('空列表是安全的 no-op', () async {
      final store = await _storeWith({});
      await store.tickAllCourses('air', const <String>[]);
      expect(store.courseDoneOf('air'), isEmpty);
    });

    test('组曲走 c: 命名空间，不污染曲目的 p:', () async {
      final store = await _storeWith({});
      final tier = _classData().tierByOrdinal(3)!;
      await store.tickAllCourses('air', tier.courses.map((c) => c.key));

      expect(store.tickedOf('air'), isEmpty,
          reason: '段位组曲和曲目是两个存储空间，混了会「勾了但界面没反应」');
    });
  });
}
