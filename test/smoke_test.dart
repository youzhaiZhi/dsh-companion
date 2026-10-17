import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bootstrap app renders its title', (tester) async {
    await tester.pumpWidget(const _BootstrapAppForTest());
    expect(find.text('DSH 伴侣'), findsOneWidget);
  });
}

/// 临时冒烟测试：验证 Flutter 测试环境可用；真实页面测试由 test/ui 覆盖。
class _BootstrapAppForTest extends StatelessWidget {
  const _BootstrapAppForTest();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('DSH 伴侣'))),
    );
  }
}
