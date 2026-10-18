import 'package:dsh_companion/core/contracts.dart';
import 'package:dsh_companion/core/state/session_logic.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _session({SessionStatus status = SessionStatus.idle}) =>
    SessionSummary(
      id: 's1',
      title: '重构搜索插件',
      status: status,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

SessionEvent _event(SessionEventKind kind, {String? toolStatus}) =>
    SessionEvent(
      id: 'e-${kind.name}-${toolStatus ?? ''}',
      kind: kind,
      at: DateTime.fromMillisecondsSinceEpoch(0),
      toolStatus: toolStatus,
    );

void main() {
  group('sessionStatusAfterEvent', () {
    test('turn/start 事件 → running', () {
      expect(
        sessionStatusAfterEvent(
          SessionStatus.idle,
          _event(SessionEventKind.statusChange, toolStatus: 'running'),
        ),
        SessionStatus.running,
      );
    });

    test('turn/end 事件 → idle', () {
      expect(
        sessionStatusAfterEvent(
          SessionStatus.running,
          _event(SessionEventKind.statusChange, toolStatus: 'idle'),
        ),
        SessionStatus.idle,
      );
    });

    test('审批请求 → waitingInput', () {
      expect(
        sessionStatusAfterEvent(
          SessionStatus.running,
          _event(SessionEventKind.approvalRequest),
        ),
        SessionStatus.waitingInput,
      );
    });

    test('普通消息事件不改变状态', () {
      expect(
        sessionStatusAfterEvent(
          SessionStatus.running,
          _event(SessionEventKind.assistantMessage),
        ),
        SessionStatus.running,
      );
    });
  });

  group('taskNotificationFor', () {
    test('等待输入且开关开启 → 发通知', () {
      final notification = taskNotificationFor(
        session: _session(),
        nextStatus: SessionStatus.waitingInput,
        settings: const AppSettings(),
      );
      expect(notification, isNotNull);
      expect(notification!.title, contains('等待'));
      expect(notification.body, '重构搜索插件');
    });

    test('任务完成且开关开启 → 发通知', () {
      final notification = taskNotificationFor(
        session: _session(),
        nextStatus: SessionStatus.idle,
        settings: const AppSettings(),
      );
      expect(notification!.title, contains('完成'));
    });

    test('总开关关闭 → 不发通知', () {
      expect(
        taskNotificationFor(
          session: _session(),
          nextStatus: SessionStatus.idle,
          settings: const AppSettings(notificationsEnabled: false),
        ),
        isNull,
      );
    });

    test('单类开关关闭 → 只拦对应类型', () {
      const settings = AppSettings(notifyOnComplete: false);
      expect(
        taskNotificationFor(
          session: _session(),
          nextStatus: SessionStatus.idle,
          settings: settings,
        ),
        isNull,
      );
      expect(
        taskNotificationFor(
          session: _session(),
          nextStatus: SessionStatus.waitingInput,
          settings: settings,
        ),
        isNotNull,
      );
    });

    test('运行中不发通知', () {
      expect(
        taskNotificationFor(
          session: _session(),
          nextStatus: SessionStatus.running,
          settings: const AppSettings(),
        ),
        isNull,
      );
    });
  });
}
