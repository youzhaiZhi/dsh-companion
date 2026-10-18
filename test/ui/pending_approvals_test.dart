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

ApprovalRequest _approval(String id, String sessionId) => ApprovalRequest(
  id: id,
  sessionId: sessionId,
  kind: ApprovalKind.tool,
  title: 'bash',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  toolName: 'bash',
);

void main() {
  group('待审批提示', () {
    testWidgets('没有审批时不显示横幅', (tester) async {
      final controller = FakeCompanionController();
      await tester.pumpWidget(_wrap(const SessionsScreen(), controller));
      expect(find.textContaining('等待你审批'), findsNothing);
    });

    testWidgets('有审批时显示数量与处理入口', (tester) async {
      final controller =
          FakeCompanionController()
            ..pendingApprovalsOverride = <ApprovalRequest>[
              _approval('e1', 's1'),
              _approval('e2', 's1'),
            ];
      await tester.pumpWidget(_wrap(const SessionsScreen(), controller));
      expect(find.text('有 2 个请求等待你审批'), findsOneWidget);
      expect(find.text('去处理'), findsOneWidget);
    });

    testWidgets('点击去处理会打开对应会话', (tester) async {
      final controller =
          FakeCompanionController()
            ..pendingApprovalsOverride = <ApprovalRequest>[
              _approval('e1', 's7'),
            ];
      await tester.pumpWidget(_wrap(const SessionsScreen(), controller));
      await tester.tap(find.text('去处理'));
      await tester.pumpAndSettle();
      expect(controller.calls, contains('openSession:s7'));
    });
  });
}
