import 'package:dsh_companion/app.dart';
import 'package:dsh_companion/core/contracts.dart';
import 'package:dsh_companion/ui/screens/sessions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fixtures/fake_controller.dart';

Widget _wrap(Widget child, FakeCompanionController controller) {
  return ChangeNotifierProvider<CompanionController>.value(
    value: controller,
    child: MaterialApp(home: child),
  );
}

void main() {
  group('SessionsScreen', () {
    testWidgets('空会话列表显示空状态', (tester) async {
      final controller = FakeCompanionController(
        activeDevice: DeviceRecord(
          instanceId: 'i',
          label: '书房电脑',
          origin: Uri.parse('https://192.168.1.2:3443'),
          deviceToken: 't',
          kind: GatewayKind.lan,
          deviceExpiresAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      await tester.pumpWidget(_wrap(const SessionsScreen(), controller));
      expect(find.text('这台电脑上还没有会话'), findsOneWidget);
      expect(find.text('书房电脑'), findsOneWidget);
    });

    testWidgets('渲染会话标题、状态与时间', (tester) async {
      final now = DateTime.now();
      final controller = FakeCompanionController(
        sessions: <SessionSummary>[
          SessionSummary(
            id: 's1',
            title: '重构搜索插件',
            status: SessionStatus.running,
            updatedAt: now,
          ),
          SessionSummary(
            id: 's2',
            title: '写周报',
            status: SessionStatus.waitingInput,
            updatedAt: now,
          ),
        ],
      );
      await tester.pumpWidget(_wrap(const SessionsScreen(), controller));
      expect(find.text('重构搜索插件'), findsOneWidget);
      expect(find.text('写周报'), findsOneWidget);
      expect(find.textContaining('进行中'), findsOneWidget);
      expect(find.textContaining('等待输入'), findsOneWidget);
    });

    testWidgets('连接错误时显示重试入口', (tester) async {
      final controller = FakeCompanionController(
        connectionError: '会话已过期，需要重新连接',
      );
      await tester.pumpWidget(_wrap(const SessionsScreen(), controller));
      expect(find.text('会话已过期，需要重新连接'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('describeError', () {
    test('CompanionException 展示 message', () {
      expect(
        describeError(const CompanionException('code', '对方电脑已拒绝')),
        '对方电脑已拒绝',
      );
    });

    test('普通异常回落到 toString', () {
      expect(describeError(StateError('boom')), contains('boom'));
    });
  });
}
