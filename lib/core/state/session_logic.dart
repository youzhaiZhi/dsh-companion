import 'package:dsh_companion/core/contracts.dart';
import 'package:dsh_companion/core/state/companion_controller.dart';

/// 一条待发的任务通知。
class TaskNotification {
  const TaskNotification({required this.title, required this.body});

  final String title;
  final String body;
}

/// 由会话事件推导新的状态；未知事件保持原状态。
SessionStatus sessionStatusAfterEvent(
    SessionStatus current, SessionEvent event) {
  switch (event.kind) {
    case SessionEventKind.statusChange:
      return event.toolStatus == 'running'
          ? SessionStatus.running
          : SessionStatus.idle;
    case SessionEventKind.approvalRequest:
      return SessionStatus.waitingInput;
    case SessionEventKind.error:
      return SessionStatus.idle;
    default:
      return current;
  }
}

/// 状态变化时该发什么通知；不该发时返回 null。
///
/// 只通知「完成任务」与「等待输入」两种，且遵守设置开关。
TaskNotification? taskNotificationFor({
  required SessionSummary session,
  required SessionStatus nextStatus,
  required AppSettings settings,
}) {
  if (!settings.notificationsEnabled) {
    return null;
  }
  switch (nextStatus) {
    case SessionStatus.waitingInput when settings.notifyOnWaiting:
      return TaskNotification(title: 'DSH 等待你的输入', body: session.title);
    case SessionStatus.idle when settings.notifyOnComplete:
      return TaskNotification(title: 'DSH 任务已完成', body: session.title);
    default:
      return null;
  }
}
