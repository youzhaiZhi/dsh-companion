import 'dart:async';

import '../contracts.dart';
import 'pairing.dart';
import 'rpc.dart';

/// 真实网关：dsh-mobile HTTPS 网关 + DSH Remote RPC。
///
/// 承担：配对/续期、一元 RPC（POST /api）、流式 RPC（/api/remote.mux），
/// 以及把 DSH 的原始事件与列表行映射成 contracts 里的模型。
/// DSH 返回结构以 `docs/protocol.md` 为准；未知字段一律宽松处理。
class LiveCompanionGateway {
  LiveCompanionGateway();

  final PairingClient _pairing = const PairingClient();
  RpcClient? _rpc;
  MuxClient? _mux;
  DeviceRecord? _device;

  DeviceRecord? get device => _device;

  bool get isConnected => _rpc != null;

  /// 配对：校验 CA 指纹后换取长期设备令牌。
  Future<PairingOutcome> pair({
    required PairingLink link,
    String? label,
  }) {
    return _pairing.pair(
      origin: link.origin,
      instanceId: link.instanceId,
      token: link.token,
      label: label,
    );
  }

  /// 用已保存设备登录：续期短期会话并建立 RPC 通道。
  Future<void> connect(DeviceRecord device) async {
    await close();
    final renewed = await _pairing.renew(device: device);
    _device = device;
    final credentials = SessionCredentials(
      sessionToken: renewed.sessionToken,
      csrfToken: renewed.csrfToken,
      expiresAt: renewed.sessionExpiresAt,
    );
    final http = pinnedHttpClient(device.caPem!);
    _rpc = RpcClient(
        client: http, origin: device.origin, credentials: credentials);
    _mux = MuxClient(
        client: http, origin: device.origin, credentials: credentials);
  }

  Future<List<SessionSummary>> listSessions() async {
    final value = await _requireRpc().call('session/list');
    final sessions = <SessionSummary>[];
    for (final row in _extractRows(value)) {
      final id = (row['sessionId'] ?? row['id'] ?? '').toString();
      if (id.isEmpty) {
        continue;
      }
      sessions.add(SessionSummary(
        id: id,
        title: (row['title'] ?? row['displayTitle'] ?? row['cwd'] ?? id)
            .toString(),
        workspace: row['cwd']?.toString(),
        model: row['model']?.toString(),
        preview: row['preview']?.toString(),
        status: _statusOf(row),
        updatedAt:
            _time(row['updatedAt'] ?? row['lastPromptAt']) ?? DateTime.now(),
      ));
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  /// 会话事件流（`session/follow`）。opening 与增量都按事件映射。
  Stream<SessionEvent> watchSession(String sessionId) {
    final stream = _requireMux()
        .open('session/follow', <String, Object?>{'sessionId': sessionId});
    return stream.expand<Object?>(_flattenFollowers).map(_toEvent);
  }

  Future<void> sendPrompt(String sessionId, String text) async {
    await _requireRpc().call('session/prompt', <String, Object?>{
      'sessionId': sessionId,
      'requestId': newRpcId(),
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    });
  }

  /// 审批/提问应答。方法名按 DSH approval 端点约定，未确认时由 UI 显示错误。
  /// 审批应答。
  ///
  /// ⚠️ 尚未接通：DSH 的审批不是普通 RPC，而是 `$events` 瀑布事件：
  /// Host 经 `$events` 下发 `{type:'event', event:'approval/request', eventId, ...}`，
  /// 客户端必须用同一条流的 `clientId` + `eventId` 调 `$events/result`
  /// （`{clientId, eventId, outcome:{kind:'result', value:'allowed-once'|'rejected'}}`）。
  /// 详见 docs/protocol.md 第 6 节。这里先明确失败，避免发出不存在的 RPC。
  Future<void> decideApproval(
    ApprovalRequest request,
    ApprovalDecision decision, {
    List<String> selectedOptions = const <String>[],
  }) async {
    throw const CompanionException(
      'approval_not_wired',
      '审批应答还在接入中：DSH 通过 \$events 瀑布下发审批，需要先建立事件订阅。',
    );
  }

  Future<void> close() async {
    await _mux?.close();
    _mux = null;
    _rpc?.close();
    _rpc = null;
  }

  // ---- helpers ----

  RpcClient _requireRpc() {
    final rpc = _rpc;
    if (rpc == null) {
      throw const CompanionException('not_connected', '尚未连接电脑');
    }
    return rpc;
  }

  MuxClient _requireMux() {
    final mux = _mux;
    if (mux == null) {
      throw const CompanionException('not_connected', '尚未连接电脑');
    }
    return mux;
  }

  Iterable<Map<String, dynamic>> _extractRows(Object? value) sync* {
    if (value is List) {
      for (final item in value) {
        if (item is Map<String, dynamic>) {
          yield item;
        }
      }
      return;
    }
    if (value is Map<String, dynamic>) {
      for (final key in const <String>['rows', 'sessions', 'items', 'list']) {
        final nested = value[key];
        if (nested is List) {
          yield* _extractRows(nested);
          return;
        }
      }
    }
  }

  Iterable<Object?> _flattenFollowers(Object? value) sync* {
    if (value is Map<String, dynamic>) {
      final entries = value['events'];
      if (value['type'] == 'event' && value['event'] != null) {
        yield value['event'];
        return;
      }
      if (entries is List) {
        yield* entries.cast<Object?>();
        return;
      }
    }
    yield value;
  }

  SessionEvent _toEvent(Object? raw) {
    final now = DateTime.now();
    if (raw is! Map<String, dynamic>) {
      return SessionEvent(
          id: newRpcId(),
          kind: SessionEventKind.unknown,
          at: now,
          text: raw?.toString());
    }
    final type = (raw['type'] ?? 'unknown').toString();
    final data = raw['data'] is Map<String, dynamic>
        ? raw['data']! as Map<String, dynamic>
        : const <String, dynamic>{};
    final seq = raw['seq'];
    final id = seq != null ? '$type-$seq' : newRpcId();

    switch (type) {
      case 'user/message':
        return SessionEvent(
            id: id,
            kind: SessionEventKind.userMessage,
            at: now,
            text: _textOf(data['message'] ?? data));
      case 'assistant/message':
        return SessionEvent(
            id: id,
            kind: SessionEventKind.assistantMessage,
            at: now,
            text: _textOf(data['message'] ?? data));
      case 'tool/call':
        return SessionEvent(
          id: id,
          kind: SessionEventKind.toolCall,
          at: now,
          toolName: data['name']?.toString(),
          toolStatus: 'running',
          toolDetail: data['arguments']?.toString(),
        );
      case 'tool/result':
        return SessionEvent(
          id: id,
          kind: SessionEventKind.toolResult,
          at: now,
          toolName: data['name']?.toString(),
          toolStatus: data['error'] == null ? 'ok' : 'error',
          toolDetail: _textOf(data['message'] ?? data['content']),
        );
      case 'approval/asked':
        return SessionEvent(
          id: id,
          kind: SessionEventKind.approvalRequest,
          at: now,
          approvalId: data['id']?.toString(),
          toolName: data['toolName']?.toString(),
          text: data['reason']?.toString(),
        );
      case 'turn/start':
        return SessionEvent(
            id: id,
            kind: SessionEventKind.statusChange,
            at: now,
            toolStatus: 'running');
      case 'turn/end':
        return SessionEvent(
          id: id,
          kind: SessionEventKind.statusChange,
          at: now,
          toolStatus: 'idle',
          text: data['reason']?.toString(),
        );
      case 'error':
        return SessionEvent(
            id: id,
            kind: SessionEventKind.error,
            at: now,
            text: data['message']?.toString() ?? type);
      default:
        return SessionEvent(
            id: id,
            kind: SessionEventKind.unknown,
            at: now,
            text: type,
            meta: data);
    }
  }

  String? _textOf(Object? value) {
    if (value is String) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      final content = value['content'];
      if (content is String) {
        return content;
      }
      if (content is List) {
        final joined = content
            .whereType<Map<Object?, Object?>>()
            .map((part) => part['text'] ?? part['content'])
            .whereType<String>()
            .join();
        if (joined.isNotEmpty) {
          return joined;
        }
      }
      final text = value['text'];
      if (text is String) {
        return text;
      }
    }
    return value?.toString();
  }

  DateTime? _time(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      final ms = int.tryParse(value);
      return ms != null
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : DateTime.tryParse(value);
    }
    return null;
  }

  SessionStatus _statusOf(Map<String, dynamic> row) {
    final state = row['running'] ?? row['status'] ?? row['agentStatus'];
    if (state == true || state == 'running') {
      return SessionStatus.running;
    }
    if (state == 'waiting' ||
        state == 'waiting-input' ||
        row['waitingForInput'] == true) {
      return SessionStatus.waitingInput;
    }
    if (row['agentAvailable'] == false) {
      return SessionStatus.completed;
    }
    return SessionStatus.idle;
  }
}
