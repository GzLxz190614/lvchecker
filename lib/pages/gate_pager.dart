import 'package:flutter/material.dart';

import '../data/gate_status.dart';
import '../data/progress_store.dart';
// MetaTable 定义在这个文件里，一定要导入。
// （之前我按「未使用」把它删掉过一次，结果 MetaTable 变成未定义类型——
//  analyze 报 undefined_class，test 阶段直接编译失败。）
import '../models/entry.dart';
import '../models/class_course.dart';
import '../models/gate.dart';
import '../models/link_level.dart';
import '../theme.dart';
import 'gate_page.dart';

/// 主页面：每个门一页，左右滑动切换。
///
/// 显示哪些页：
/// - 13 个解锁条件门**始终显示**（未更新的门也要能看到条件，这是设计决定）
/// - 奖励乐曲页**只有在前 13 个门全部已解锁后才出现**
class GatePager extends StatefulWidget {
  const GatePager({
    super.key,
    required this.gates,
    required this.meta,
    required this.store,
    required this.linkLevels,
    required this.classData,
    required this.dataVersion,
    required this.onOpenSettings,
  });

  final List<Gate> gates;
  final MetaTable meta;
  final ProgressStore store;
  final LinkLevelData linkLevels;
  final ClassData classData;
  final String dataVersion;
  final VoidCallback onOpenSettings;

  @override
  State<GatePager> createState() => _GatePagerState();
}

class _GatePagerState extends State<GatePager> {
  final PageController _controller = PageController();

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onProgressChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onProgressChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onProgressChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final statuses = evaluateAll(widget.gates, widget.store, classData: widget.classData);

    final conditionGates = widget.gates.where((g) => !g.isReward).toList();
    final rewardGates = widget.gates.where((g) => g.isReward).toList();

    // 奖励页只在全部门解锁后出现
    final allCleared = conditionGates.isNotEmpty &&
        conditionGates.every((g) => statuses[g.id]?.unlocked ?? false);

    final visible = <Gate>[
      ...conditionGates,
      if (allCleared) ...rewardGates,
    ];

    final unlockedCount = conditionGates.where((g) => statuses[g.id]?.unlocked ?? false).length;

    // 页数变少时（理论上不会，因为只增不减）把控制器拉回合法范围
    if (_controller.hasClients && _controller.page != null) {
      final maxPage = (visible.length - 1).clamp(0, 1 << 30);
      if (_controller.page!.round() > maxPage) {
        _controller.jumpToPage(maxPage);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('连章进度  $unlockedCount / ${conditionGates.length}'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _PageDots(
            count: visible.length,
            controller: _controller,
            labels: visible.map((g) => g.name.replaceAll('Linked GATE ', '')).toList(),
          ),
          const Divider(height: 1),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final gate = visible[i];
                return GatePage(
                  gate: gate,
                  meta: widget.meta,
                  store: widget.store,
                  linkLevels: widget.linkLevels.forGate(gate.id),
                  classData: widget.classData,
                  status: statuses[gate.id] ??
                      const GateStatus(unlocked: false, doneCount: 0, totalCount: 0),
                  statusOf: (id) =>
                      statuses[id] ??
                      const GateStatus(unlocked: false, doneCount: 0, totalCount: 0),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部的页码指示条。门不多（最多 14），直接全部画出来，
/// 这样一眼能看到自己滑到哪、还剩几个门。
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.controller, required this.labels});

  final int count;
  final PageController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final page = (controller.hasClients && controller.page != null)
              ? controller.page!.round()
              : 0;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: count,
            itemBuilder: (context, i) {
              final active = i == page;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? AppTheme.accent.withValues(alpha: 0.16) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: active ? AppTheme.accent.withValues(alpha: 0.5) : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? AppTheme.accent : AppTheme.textDim,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
