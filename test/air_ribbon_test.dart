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
import 'package:shared_preferences/shared_preferences.dart';

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
}
