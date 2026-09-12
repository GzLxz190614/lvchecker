// 跑马灯（MarqueeText）的行为测试。
//
// **为什么必须写这个测试**：滚动这个功能我改错过三次。
//
//   ① `SizedBox(height:) + ClipRect(Align(child: text))` → 字在动，右边永远空白
//   ② ① + `SizedBox(width: available)`                  → 现象完全没变
//   ③ `+ OverflowBox(maxWidth: ∞) + Transform`          → 文字整个不见了
//
// 三次都是「推断 Flutter 内部的约束传递行为」，而本地没有 Flutter 环境，
// 推断了三次错了三次，每次都靠你装一次 APK 才知道结果。这个循环必须打断。
//
// 现在断言的是**布局真实算出来的量**（ScrollPosition.maxScrollExtent），
// 不是我自己的 TextPainter 测量 —— 少一个可能算错的环节。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/widgets/item_card.dart';

/// 实测最长的曲名之一（22 个全角字符）。
const kLongText = '今ぞ♡崇め奉れ☆オマエらよ！！～姫の秘メタル渇望～';
const kShortText = '短曲名';

/// 故意很窄，保证长文本必然溢出。
const double kBoxWidth = 120;

Widget _host(String text, {double width = kBoxWidth}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: MarqueeText(
              text: text,
              style: const TextStyle(fontSize: 13, height: 1.25),
            ),
          ),
        ),
      ),
    );

/// 跑马灯里那个滚动视图的 position。第二帧之后才 attach。
ScrollPosition _scrollPosition(WidgetTester tester) {
  final state = tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(MarqueeText),
      matching: find.byType(Scrollable),
    ),
  );
  return state.position;
}

Future<ScrollPosition> _pumpAndSettleLayout(WidgetTester tester, String text) async {
  await tester.pumpWidget(_host(text));
  // 用**带时长**的 pump：不带时长时推进量是 0，动画控制器可能一步都没走。
  // 第一帧完成布局；_syncToLayout 挂在 post-frame 回调上，所以需要第二帧。
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
  return _scrollPosition(tester);
}

/// 动画时长上限是 9000ms（见 MarqueeText 的 clamp）。
/// 要在测试里走完一个单程，模拟时间必须超过它，所以这里用 200 帧 × 50ms = 10s。
const int _frames = 200;
const Duration _step = Duration(milliseconds: 50);

/// 跑马灯里那个真正绘制文字的 RenderBox。
RenderBox _textBox(WidgetTester tester) => tester.renderObject<RenderBox>(
      find.descendant(of: find.byType(MarqueeText), matching: find.byType(Text)),
    );

void main() {
  testWidgets('短文本：放得下，不滚动', (tester) async {
    final pos = await _pumpAndSettleLayout(tester, kShortText);

    // ★ 用布局算出来的溢出量，而不是我自己量的文字宽度
    expect(pos.maxScrollExtent, lessThanOrEqualTo(0.5),
        reason: '短文本不该需要滚动（maxScrollExtent=${pos.maxScrollExtent}）');
  });

  testWidgets('长文本：文字按固有宽度布局，没被挤成可用宽度', (tester) async {
    await _pumpAndSettleLayout(tester, kLongText);

    final box = _textBox(tester);
    // ★ 这是最关键的一条，也正是前三次栽掉的地方。
    //   如果文字被挤成「可用宽度」，它一开始就是残缺的，
    //   后面的滚动只是在移动一段缺了尾巴的文字 —— 右边当然永远空白。
    expect(box.size.width, greaterThan(kBoxWidth + 1),
        reason: '文字宽度 ${box.size.width} 必须大于可用宽度 $kBoxWidth，'
            '否则说明被挤窄了（会永远看不到右边内容）');
  });

  testWidgets('长文本：可以滚动，且滚动范围足够露出尾部', (tester) async {
    final pos = await _pumpAndSettleLayout(tester, kLongText);

    // ★ 用布局真实算出的 maxScrollExtent。前三次的 bug 就死在这里：
    //   技术上「能滚」，但没有任何东西保证滚出来的距离覆盖真正的溢出量。
    final textWidth = _textBox(tester).size.width;
    final expected = textWidth - kBoxWidth;

    expect(pos.maxScrollExtent, greaterThan(1),
        reason: '必须能滚（否则说明文字没超出容器）');
    expect(pos.maxScrollExtent, closeTo(expected, 1.0),
        reason: '可滚动距离 ${pos.maxScrollExtent} 应该约等于'
            '「文字宽度 - 可用宽度」= $expected');
  });

  testWidgets('长文本：确实会随时间滚动，并且会滚到尾部', (tester) async {
    final pos = await _pumpAndSettleLayout(tester, kLongText);
    final maxExtent = pos.maxScrollExtent;

    final seen = <double>[];
    for (var i = 0; i < _frames; i++) {
      await tester.pump(_step);
      seen.add(pos.pixels);
    }

    expect(seen.every((p) => p >= -0.01 && p <= maxExtent + 0.01), isTrue,
        reason: '滚动位置必须始终落在 [0, $maxExtent] 内，实测 ${seen.take(5)}');

    final furthest = seen.reduce((a, b) => a > b ? a : b);
    // ★ 到达尾部 = 右边被遮住的内容真的露出来了
    expect(furthest, greaterThan(maxExtent - 1),
        reason: '最远只滚到 $furthest / $maxExtent —— 没到尾部说明尾部内容仍看不到');
  });

  testWidgets('动画会往返（回到起点，首尾都能读到）', (tester) async {
    final pos = await _pumpAndSettleLayout(tester, kLongText);
    final maxExtent = pos.maxScrollExtent;

    final seen = <double>[];
    for (var i = 0; i < _frames; i++) {
      await tester.pump(_step);
      seen.add(pos.pixels);
    }

    final furthest = seen.reduce((a, b) => a > b ? a : b);
    final nearest = seen.reduce((a, b) => a < b ? a : b);

    expect(furthest, greaterThan(maxExtent - 1), reason: '要到过尾部');
    expect(nearest, lessThan(1), reason: '要回到过起点（reverse 往返）');
  });
}
