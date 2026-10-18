import 'package:dsh_companion/core/contracts.dart';
import 'package:dsh_companion/core/gateway/events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHostEvent', () {
    test('ready 帧带出 clientId 与 home', () {
      final event = parseHostEvent(<String, Object?>{
        'type': 'ready',
        'clientId': 'client-1',
        'host': <String, Object?>{'home': '/home/me'},
      });
      expect(event, isA<HostEventsReady>());
      final ready = event! as HostEventsReady;
      expect(ready.clientId, 'client-1');
      expect(ready.home, '/home/me');
    });

    test('emit 帧解析事件名与参数', () {
      final event = parseHostEvent(<String, Object?>{
        'type': 'emit',
        'event': 'session/title',
        'args': <Object?>['s1', '新标题'],
      });
      final emit = event! as HostEmitEvent;
      expect(emit.event, 'session/title');
      expect(emit.args, <Object?>['s1', '新标题']);
    });

    test('waterfall 帧解析审批关联字段', () {
      final event = parseHostEvent(<String, Object?>{
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': 'evt-1',
        'agentId': 'agent-1',
        'request': <String, Object?>{
          'toolName': 'bash',
          'reason': '需要执行命令',
          'callId': 'call-1',
        },
      });
      final waterfall = event! as HostWaterfallEvent;
      expect(waterfall.eventId, 'evt-1');
      expect(waterfall.agentId, 'agent-1');
      expect(waterfall.request['toolName'], 'bash');
    });

    test('cancel 帧带出要撤回的 eventId', () {
      final event = parseHostEvent(<String, Object?>{
        'type': 'cancel',
        'eventId': 'evt-9',
      });
      expect((event! as HostCancelEvent).eventId, 'evt-9');
    });

    test('未知帧与畸形帧返回 null（前向兼容）', () {
      expect(parseHostEvent(null), isNull);
      expect(parseHostEvent(<String, Object?>{'type': 'mystery'}), isNull);
      expect(parseHostEvent('not-a-map'), isNull);
      expect(
        parseHostEvent(<String, Object?>{'type': 'ready'}),
        isNull,
        reason: '缺 clientId 不该当成 ready',
      );
    });
  });

  group('approvalFromWaterfall', () {
    HostWaterfallEvent frame({
      String event = 'approval/request',
      Map<String, Object?> request = const <String, Object?>{
        'toolName': 'bash'
      },
    }) =>
        HostWaterfallEvent(
          event: event,
          eventId: 'evt-1',
          agentId: 'agent-1',
          request: request,
        );

    test('approval/request 映射成待审批项', () {
      final approval = approvalFromWaterfall(frame(
        request: <String, Object?>{
          'toolName': 'bash',
          'reason': '要跑命令',
          'callId': 'call-7',
        },
      ));
      expect(approval, isNotNull);
      expect(approval!.toolName, 'bash');
      expect(approval.reason, '要跑命令');
      expect(approval.callId, 'call-7');
      expect(approval.eventId, 'evt-1');
    });

    test('其他事件不产生审批项', () {
      expect(approvalFromWaterfall(frame(event: 'question/request')), isNull);
    });

    test('转成 UI 契约时保留会话与工具信息', () {
      final approval = approvalFromWaterfall(frame())!;
      final request = approval.toApprovalRequest();
      expect(request.id, 'evt-1');
      expect(request.sessionId, 'agent-1');
      expect(request.kind, ApprovalKind.tool);
      expect(request.title, 'bash');
      expect(request.toolName, 'bash');
    });

    test('缺 toolName 时给可读兜底标题', () {
      final approval = approvalFromWaterfall(
        frame(request: const <String, Object?>{}),
      )!;
      expect(approval.toolName, '工具调用');
      expect(approval.toApprovalRequest().title, '工具调用');
    });
  });

  group('approvalOutcomeFor', () {
    test('只有允许是 allowed-once，其余都不授权', () {
      expect(approvalOutcomeFor(ApprovalDecision.allow), 'allowed-once');
      expect(approvalOutcomeFor(ApprovalDecision.deny), 'rejected');
      expect(approvalOutcomeFor(ApprovalDecision.cancel), 'cancelled');
    });
  });

  group('describeHostEvent', () {
    test('每种帧都能给出可读描述且不抛异常', () {
      expect(
        describeHostEvent(const HostEventsReady(clientId: 'c', home: '/h')),
        contains('ready'),
      );
      expect(
        describeHostEvent(const HostEmitEvent(event: 'e', args: <Object?>[])),
        contains('emit'),
      );
      expect(
        describeHostEvent(const HostWaterfallEvent(
          event: 'approval/request',
          eventId: 'e1',
          agentId: 'a1',
          request: <String, Object?>{},
        )),
        contains('waterfall'),
      );
      expect(
        describeHostEvent(const HostCancelEvent(eventId: 'e2')),
        contains('cancel'),
      );
    });
  });
}
