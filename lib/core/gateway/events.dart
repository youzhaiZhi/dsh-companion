import 'dart:async';
import 'dart:convert';

import '../contracts.dart';
import 'rpc.dart';

/// Host 转发事件流（`$events`）里的一条帧。
sealed class HostEvent {
  const HostEvent();
}

/// opening 帧：后续应答都要带这个 clientId。
class HostEventsReady extends HostEvent {
  const HostEventsReady({required this.clientId, required this.home});

  final String clientId;
  final String home;
}

/// 普通广播事件（只读，不可应答）。
class HostEmitEvent extends HostEvent {
  const HostEmitEvent({required this.event, required this.args});

  final String event;
  final List<Object?> args;
}

/// 瀑布事件：可应答，审批/提问走这条。
class HostWaterfallEvent extends HostEvent {
  const HostWaterfallEvent({
    required this.event,
    required this.eventId,
    required this.agentId,
    required this.request,
  });

  final String event;
  final String eventId;
  final String agentId;
  final Map<String, Object?> request;
}

/// Host 撤回了某条待应答的瀑布事件。
class HostCancelEvent extends HostEvent {
  const HostCancelEvent({required this.eventId});

  final String eventId;
}

/// 一条等待用户作答的审批（UI 与通知都基于它）。
class PendingApproval {
  const PendingApproval({
    required this.eventId,
    required this.agentId,
    required this.toolName,
    required this.reason,
    required this.callId,
  });

  final String eventId;

  /// Host 侧的 Agent 身份；用于把审批关联回会话。
  final String agentId;
  final String toolName;
  final String? reason;
  final String? callId;

  /// 转成 UI 契约里的审批请求。sessionId 用 agentId 兜底，
  /// 会话与 agent 的精确映射等真机联调时再收紧。
  ApprovalRequest toApprovalRequest() => ApprovalRequest(
    id: eventId,
    sessionId: agentId,
    kind: ApprovalKind.tool,
    title: toolName.isEmpty ? '需要审批' : toolName,
    detail: reason,
    createdAt: DateTime.now(),
    toolName: toolName,
  );
}

/// 解析 `$events` 的一帧；不认识的结构返回 null（前向兼容）。
HostEvent? parseHostEvent(Object? raw) {
  if (raw is! Map<String, Object?>) {
    return null;
  }
  switch (raw['type']) {
    case 'ready':
      final clientId = raw['clientId'];
      final host = raw['host'];
      if (clientId is! String || clientId.isEmpty) {
        return null;
      }
      final home = host is Map<String, Object?> ? host['home'] : null;
      return HostEventsReady(
        clientId: clientId,
        home: home is String ? home : '',
      );
    case 'emit':
      final event = raw['event'];
      final args = raw['args'];
      if (event is! String || args is! List) {
        return null;
      }
      return HostEmitEvent(event: event, args: args);
    case 'waterfall':
      final event = raw['event'];
      final eventId = raw['eventId'];
      final agentId = raw['agentId'];
      final request = raw['request'];
      if (event is! String || eventId is! String || agentId is! String) {
        return null;
      }
      return HostWaterfallEvent(
        event: event,
        eventId: eventId,
        agentId: agentId,
        request:
            request is Map<String, Object?>
                ? request
                : const <String, Object?>{},
      );
    case 'cancel':
      final eventId = raw['eventId'];
      return eventId is String ? HostCancelEvent(eventId: eventId) : null;
    default:
      return null;
  }
}

/// 把 `approval/request` 瀑布事件映射成待审批项。
PendingApproval? approvalFromWaterfall(HostWaterfallEvent frame) {
  if (frame.event != 'approval/request') {
    return null;
  }
  final request = frame.request;
  final toolName = request['toolName'];
  return PendingApproval(
    eventId: frame.eventId,
    agentId: frame.agentId,
    toolName: toolName is String ? toolName : '工具调用',
    reason: request['reason'] is String ? request['reason']! as String : null,
    callId: request['callId'] is String ? request['callId']! as String : null,
  );
}

/// `approval/request` 的唯一合法授权是 `allowed-once`，其余一律拒绝。
String approvalOutcomeFor(ApprovalDecision decision) => switch (decision) {
  ApprovalDecision.allow => 'allowed-once',
  ApprovalDecision.deny => 'rejected',
  ApprovalDecision.cancel => 'cancelled',
};

/// 订阅 Host 转发事件流，并负责回送瀑布事件的应答。
class HostEventsClient {
  HostEventsClient({required MuxClient mux, required RpcClient rpc})
    : _mux = mux,
      _rpc = rpc;

  final MuxClient _mux;
  final RpcClient _rpc;

  final List<HostWaterfallEvent> _pending = <HostWaterfallEvent>[];
  final StreamController<HostEvent> _controller =
      StreamController<HostEvent>.broadcast();
  StreamSubscription<Object?>? _subscription;
  String? _clientId;
  bool _disposed = false;

  /// 已建立订阅并拿到 clientId。
  bool get isReady => _clientId != null;

  String? get clientId => _clientId;

  /// 当前待应答的瀑布事件（审批/提问）。
  List<HostWaterfallEvent> get pending =>
      List<HostWaterfallEvent>.unmodifiable(_pending);

  Stream<HostEvent> get events => _controller.stream;

  /// 打开 `$events` 流；可重复调用（会先断开旧的）。
  void start() {
    if (_disposed) {
      return;
    }
    unawaited(_subscription?.cancel());
    _pending.clear();
    _clientId = null;
    _subscription = _mux
        .open(r'$events')
        .listen(
          _onFrame,
          onError: (Object error) {
            _clientId = null;
            if (!_controller.isClosed) {
              _controller.addError(error);
            }
          },
          onDone: () {
            _clientId = null;
          },
          cancelOnError: false,
        );
  }

  void _onFrame(Object? raw) {
    final event = parseHostEvent(raw);
    if (event == null) {
      return;
    }
    switch (event) {
      case HostEventsReady():
        _clientId = event.clientId;
      case HostCancelEvent():
        _pending.removeWhere((frame) => frame.eventId == event.eventId);
      case HostWaterfallEvent():
        _pending.add(event);
      case HostEmitEvent():
        break;
    }
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// 应答一条待审批的瀑布事件。
  ///
  /// DSH 的审批只能通过 `$events/result` 回送：
  /// `{clientId, eventId, outcome:{kind:'result', value:'allowed-once'|'rejected'|'cancelled'}}`。
  Future<void> respond(String eventId, ApprovalDecision decision) async {
    final clientId = _clientId;
    if (clientId == null) {
      throw const CompanionException(
        'approval_not_subscribed',
        '事件流尚未就绪，请稍后重试',
      );
    }
    await _rpc.call(r'$events/result', <String, Object?>{
      'clientId': clientId,
      'eventId': eventId,
      'outcome': <String, Object?>{
        'kind': 'result',
        'value': approvalOutcomeFor(decision),
      },
    });
    _pending.removeWhere((frame) => frame.eventId == eventId);
  }

  /// 把一条瀑布事件交给下一个监听者（本 App 不处理时）。
  Future<void> pass(String eventId) async {
    final clientId = _clientId;
    if (clientId == null) {
      return;
    }
    await _rpc.call(r'$events/result', <String, Object?>{
      'clientId': clientId,
      'eventId': eventId,
      'outcome': <String, Object?>{'kind': 'next'},
    });
    _pending.removeWhere((frame) => frame.eventId == eventId);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }
}

/// 便于调试：把帧转成一行可读文本。
String describeHostEvent(HostEvent event) => switch (event) {
  HostEventsReady() => 'ready client=${event.clientId} home=${event.home}',
  HostEmitEvent() =>
    'emit ${event.event} args=${jsonEncode(event.args).length}B',
  HostWaterfallEvent() =>
    'waterfall ${event.event} id=${event.eventId} agent=${event.agentId}',
  HostCancelEvent() => 'cancel ${event.eventId}',
};
