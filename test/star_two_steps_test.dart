// STAR 门「两步条件」的判定测试。
//
// 为什么必须测这个：STAR 的条件是
//     「获得角色 X，**并**升到 RANK 15」
// 而改之前 requirement 只有 `itemKeys: ["chara:24320"]`，界面渲染一张角色卡，
// **勾上就算门通** —— RANK 15 完全没有被判定，只写在卡片副标题的文案里。
// 也就是说：角色只有 RANK 1 时勾一下，App 会显示 STAR 已解锁。
//
// 这类 bug 不会崩、不会报错，只是「判定悄悄错了」，肉眼几乎看不出来
// （STAR 还没开放，你也不会去核对）。所以必须用测试钉住。
//
// 这里用的是纯函数 `itemsStatus(gate, ticked)`，不需要 SharedPreferences。

import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/data/gate_status.dart';
import 'package:lvchecker/models/gate.dart';

/// 造一个两步条件的门（结构同 data/gates.json 里的 star）
Gate _twoStepGate() => Gate.fromJson({
      'id': 'star',
      'order': 3,
      'stage': 1,
      'name': 'Linked GATE STAR',
      'releaseStatus': 'notYetOpen',
      'tracking': 'items',
      'conditionText': '从地图 VERSE ep.STAR 获得角色，并升到 RANK 15',
      'requirement': {
        'type': 'itemsInSteps',
        'itemKeys': ['chara:24320', 'chara:24320.rank15'],
        'steps': [
          {
            'key': 'obtain',
            'label': '获得角色',
            'note': '从地图 VERSE ep.STAR 获得',
            'itemKeys': ['chara:24320'],
          },
          {
            'key': 'rank',
            'label': '升到 RANK 15',
            'note': '角色练到 RANK 15 即达成',
            'itemKeys': ['chara:24320.rank15'],
          },
        ],
      },
    });

/// 造一个普通 items 门（结构同 NEW）
Gate _flatItemsGate() => Gate.fromJson({
      'id': 'new',
      'order': 7,
      'stage': 1,
      'name': 'Linked GATE NEW',
      'releaseStatus': 'notYetOpen',
      'tracking': 'items',
      'conditionText': '获得 3 件企鹅服装',
      'requirement': {
        'type': 'items',
        'itemKeys': ['avatar:6104401', 'avatar:6204401', 'avatar:6704401'],
      },
    });

void main() {
  group('模型解析', () {
    test('steps 被正确解析，且 allStepItemKeys 把各步条目前后拼起来', () {
      final g = _twoStepGate();
      expect(g.requirement.type, 'itemsInSteps');
      expect(g.requirement.steps.length, 2);
      expect(g.requirement.steps[0].key, 'obtain');
      expect(g.requirement.steps[1].key, 'rank');
      expect(g.requirement.steps[0].label, '获得角色');
      expect(g.requirement.steps[1].note, '角色练到 RANK 15 即达成');
      expect(g.requirement.allStepItemKeys, ['chara:24320', 'chara:24320.rank15']);
    });

    test('requiredCount 数的是两步的条目总数（2），不是 1', () {
      expect(_twoStepGate().requiredCount, 2);
    });

    test('顶层 itemKeys 平铺后与 allStepItemKeys 一致（冗余字段要保持同步）', () {
      final g = _twoStepGate();
      expect(g.requirement.itemKeys, g.requirement.allStepItemKeys);
    });
  });

  group('STAR 两步判定（改这个测试之前先读文件头的说明）', () {
    test('什么都没勾 → 未解锁 0/2', () {
      final s = itemsStatus(_twoStepGate(), <String>{});
      expect(s.unlocked, isFalse);
      expect(s.doneCount, 0);
      expect(s.totalCount, 2);
      expect(s.progressLabel, '0 / 2');
    });

    test('★ 只勾了「获得角色」→ 仍未解锁 1/2', () {
      // 这一条就是那个 bug 的核心：只获得角色、还没升到 RANK 15，
      // 门**不能**算通。改之前这里会返回 unlocked == true。
      final s = itemsStatus(_twoStepGate(), {'chara:24320'});
      expect(s.unlocked, isFalse, reason: '获得角色但没升到 RANK 15，门不该通');
      expect(s.doneCount, 1);
      expect(s.totalCount, 2);
    });

    test('★ 只勾了「升到 RANK 15」→ 仍未解锁 1/2', () {
      // 防御「第 2 步的 key 和角色 key 撞了」这类问题。
      // 如果两步共用一个 key，勾第 2 步会同时把第 1 步算上，
      // 于是这里会错误地变成已解锁。
      final s = itemsStatus(_twoStepGate(), {'chara:24320.rank15'});
      expect(s.unlocked, isFalse, reason: '两步的 key 不能互相影响');
      expect(s.doneCount, 1);
      expect(s.totalCount, 2);
    });

    test('两步都勾 → 已解锁 2/2', () {
      final s = itemsStatus(_twoStepGate(), {'chara:24320', 'chara:24320.rank15'});
      expect(s.unlocked, isTrue);
      expect(s.doneCount, 2);
      expect(s.totalCount, 2);
      expect(s.progressLabel, '2 / 2');
    });

    test('勾了无关的条目不影响结果', () {
      final s = itemsStatus(_twoStepGate(), {'music:2838', 'chara:24320'});
      expect(s.unlocked, isFalse);
      expect(s.doneCount, 1);
    });
  });

  group('普通 items 门不受影响（回归）', () {
    test('三个服装勾两个 → 未解锁 2/3', () {
      final s = itemsStatus(_flatItemsGate(), {'avatar:6104401', 'avatar:6204401'});
      expect(s.unlocked, isFalse);
      expect(s.doneCount, 2);
      expect(s.totalCount, 3);
    });

    test('三个服装全勾 → 已解锁', () {
      final s = itemsStatus(
          _flatItemsGate(), {'avatar:6104401', 'avatar:6204401', 'avatar:6704401'});
      expect(s.unlocked, isTrue);
      expect(s.progressLabel, '3 / 3');
    });
  });

  group('空条目不能判定为已解锁', () {
    test('itemsInSteps 但 steps 是空的 → 未解锁（不能因为是 0==0 就认为完成）', () {
      final broken = Gate.fromJson({
        'id': 'broken',
        'order': 1,
        'stage': 1,
        'name': '坏数据',
        'releaseStatus': 'notYetOpen',
        'tracking': 'items',
        'conditionText': '测试',
        'requirement': {'type': 'itemsInSteps', 'steps': <dynamic>[]},
      });
      final s = itemsStatus(broken, <String>{});
      expect(s.unlocked, isFalse, reason: 'total == 0 时必须判未解锁，否则坏数据会显示门已通');
      expect(s.totalCount, 0);
    });

    test('items 且 itemKeys 为空 → 未解锁', () {
      final broken = Gate.fromJson({
        'id': 'broken',
        'order': 1,
        'stage': 1,
        'name': '坏数据',
        'releaseStatus': 'notYetOpen',
        'tracking': 'items',
        'conditionText': '测试',
        'requirement': {'type': 'items', 'itemKeys': <dynamic>[]},
      });
      expect(itemsStatus(broken, <String>{}).unlocked, isFalse);
    });
  });
}
