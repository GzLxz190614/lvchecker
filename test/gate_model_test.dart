import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/models/gate.dart';

void main() {
  test('GateData 解析出 14 页，且奖励页排最后', () {
    final data = GateData.fromJson({
      'schemaVersion': 1,
      'dataVersion': 'test',
      'gameVersion': 'test',
      'gates': [
        {
          'id': 'origin',
          'order': 1,
          'stage': 1,
          'name': 'Linked GATE ORIGIN',
          'releaseStatus': 'open',
          'tracking': 'songs',
          'conditionText': '测试',
          'requirement': {
            'type': 'playAll',
            'songKeys': ['music:51', 'music:53'],
          },
        },
        {
          'id': 'reward',
          'order': 14,
          'stage': 3,
          'name': '奖励乐曲',
          'kind': 'reward',
          'releaseStatus': 'locked',
          'tracking': 'auto',
          'conditionText': '测试',
          'prerequisites': ['origin'],
          'requirement': {'type': 'clearAllPrev'},
        },
      ],
    });

    expect(data.gates.length, 2);
    expect(data.gates.first.id, 'origin');
    expect(data.gates.last.isReward, isTrue);
    expect(data.conditionGates.length, 1);
    expect(data.gates.first.requirement.songKeys.length, 2);
    expect(data.gates.first.releaseStatus, ReleaseStatus.open);
    expect(data.gates.last.releaseStatus, ReleaseStatus.locked);
  });

  test('TrackingKind 解析覆盖全部取值', () {
    expect(TrackingKind.parse('songs'), TrackingKind.songs);
    expect(TrackingKind.parse('items'), TrackingKind.items);
    expect(TrackingKind.parse('class'), TrackingKind.classes);
    expect(TrackingKind.parse('auto'), TrackingKind.auto);
    expect(TrackingKind.parse('universe'), TrackingKind.remainingHp);
    expect(TrackingKind.parse('manual'), TrackingKind.manual);
    expect(TrackingKind.parse(null), TrackingKind.manual);
  });

  test('playAnyOfEach 的 requiredCount 等于分组数，不是曲目数', () {
    final gate = Gate.fromJson({
      'id': 'paradise',
      'order': 6,
      'stage': 1,
      'name': 'Linked GATE PARADISE',
      'releaseStatus': 'notYetOpen',
      'tracking': 'songs',
      'conditionText': '测试',
      'requirement': {
        'type': 'playAnyOfEach',
        'groups': [
          {
            'key': 'Kai',
            'songKeys': ['music:629', 'music:788'],
          },
          {
            'key': '水野健治',
            'songKeys': ['music:2704'],
          },
        ],
      },
    });

    // 2 组 / 3 首 -> 只需要完成 2 项
    expect(gate.requirement.songKeys.length, 0);
    expect(gate.requirement.groups.length, 2);
    expect(gate.requiredCount, 2);
  });
}
