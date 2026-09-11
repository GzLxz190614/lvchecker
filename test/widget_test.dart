// 注意：这个文件名必须和 flutter create 生成的模板一致（test/widget_test.dart）。
//
// 原因：`flutter create` 会生成一个引用 `MyApp` 的模板 widget 测试，
// 如果仓库里没有同名文件，它就会被创建出来，然后在 test 阶段编译失败
// （`The name 'MyApp' isn't a class`）。
// 我们在这里放自己的版本，flutter create 看到文件已存在就不会覆盖。
//
// 这个测试刻意保持「轻」：只验证 app 能构建、启动时进入加载态。
// 真正的数据加载需要 rootBundle + SharedPreferences，
// 在 widget 测试里搭那套环境的收益不如把逻辑测在模型层（见 gate_model_test.dart）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lvchecker/main.dart';

void main() {
  testWidgets('应用可以构建，启动时显示加载态', (tester) async {
    await tester.pumpWidget(const LvCheckerApp());

    // 首帧应该是加载指示器（数据是异步加载的）
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 不要 pumpAndSettle：数据加载依赖真实资源包，
    // 让它自然停在加载态即可，避免测试挂起。
  });
}
