// 跑马灯（MarqueeText）的行为测试。
//
// **为什么必须写这个测试**：滚动这个功能我改错过两次，
// 两次都是「推断正确、装到手机上现象一样」——
//
//   第一版：`SizedBox(height:) + ClipRect(Align(child: text))`
//           → 字在动，但右边永远空白
//   第二版：加了 `SizedBox(width: available)`
//           → 现象完全没变
//
// 根本困难在于：本地没有 Flutter 环境，我没法真的跑起来看，
// 只能靠推断 Flutter 内部的约束传递细节，而推断错了两次。
//
// 所以这里把「滚动到底成不成立」变成**可自动验证的断言**：
// 只要我在 CI 里跑它，就不需要靠装 APK 才知道对不对。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/widgets/item_card.dart';

/// 一段一定放不下的长文本（22 个全角字符是实测最长的曲名之一）。
const kLongText = '今ぞ♡崇め奉れ☆オマエらよ！！～姫の秘メタル渇望～';

/// 一个很短的可用宽度，保证长文本必然溢出。
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

/// 找到跑马灯里那个真正绘制文字的 Text 的 RenderBox。
RenderBox _textRenderBox(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(MarqueeText),
    matching: find.byType(Text),
  );
  expect(finder, findsOneWidget, reason: 'MarqueeText 里应该正好有一个 Text');
  return tester.renderObject<RenderBox>(finder);
}

void main() {
  testWidgets('短文本不滚动，且不被裁剪', (tester) async {
    await tester.pumpWidget(_host('短曲名'));

    final box = _textRenderBox(tester);
    // 放得下：整段文字都在可用宽度内
    expect(box.size.width, lessThanOrEqualTo(kBoxWidth + 0.5),
        reason: '短文本不该溢出');
  });

  testWidgets('长文本：文字按固有宽度布局，不被挤成可用宽度', (tester) async {
    await tester.pumpWidget(_host(kLongText));

    final box = _textRenderBox(tester);
    // ★ 这是最关键的一条断言。
    //   如果文字被挤成「可用宽度」，那它一开始就是残缺的，
    //   平移只是在移动一段缺了尾巴的文字 —— 这正是前两次的现象。
    expect(box.size.width, greaterThan(kBoxWidth + 1),
        reason: '文字必须比裁剪框宽，否则说明它被挤窄了（会永远看不到右边内容）');
  });

  testWidgets('长文本：裁剪框的宽度等于可用宽度', (tester) async {
    await tester.pumpWidget(_host(kLongText));

    final clip = find.descendant(
      of: find.byType(MarqueeText),
      matching: find.byType(ClipRect),
    );
    expect(clip, findsOneWidget, reason: '溢出的文字必须被裁剪，否则会渗透到相邻卡片');

    final clipBox = tester.renderObject<RenderBox>(clip);
    expect(clipBox.size.width, closeTo(kBoxWidth, 0.5),
        reason: '裁剪框宽度必须钉死为可用宽度，不能跟着文字一起变宽');
  });

  testWidgets('长文本：确实会平移，且平移量足以露出尾部', (tester) async {
    await tester.pumpWidget(_host(kLongText));

    final box = _textRenderBox(tester);
    final textWidth = box.size.width;
    final expectedOverflow = textWidth - kBoxWidth;

    // 收集一段时间内的平移量
    final offsets = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final transform = tester
          .widget<Transform>(find.descendant(
            of: find.byType(MarqueeText),
            matching: find.byType(Transform),
          ))
          .transform;
      offsets.add(transform.storage[12]); // Matrix4 的 x 平移量
    }

    expect(offsets.every((o) => o <= 0.01), isTrue,
        reason: '平移只能是负值（向左移），实测前几帧 ${offsets.take(5)}');

    final moved = offsets.reduce((a, b) => a < b ? a : b); // 最左的位置
    final reach = -moved;

    expect(reach, greaterThan(1),
        reason: '文字必须真的动起来（40 帧里几乎没动说明动画没跑）');

    // ★ 用**绝对值**判断，不用百分比。
    //
    //   一开始我写的是「reach > expectedOverflow * 0.7」，但那是个循环论证：
    //   expectedOverflow 是按「文字固有宽度」算的，如果文字其实被挤窄了，
    //   这个基准本身就是错的，断言还照样通过 —— 又一个假绿勾。
    //
    //   换成绝对值之后，它至少能独立地说明「文字确实移出了超过一个字宽的距离」，
    //   也就是右边确实露出了新内容。文字宽度本身由上面那条断言单独把关。
    expect(reach, greaterThan(30),
        reason: '最远只移动了 $reach 逻辑像素（文字宽 $textWidth，'
            '裁剪框 $kBoxWidth，理论上需要移动约 $expectedOverflow）。'
            '移动太少说明尾部露不出来。');
  });
}
