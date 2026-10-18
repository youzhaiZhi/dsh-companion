import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../contracts.dart';

/// 网关会话凭据（native-pair / native-renew 返回的短期会话）。
class SessionCredentials {
  SessionCredentials({
    required this.sessionToken,
    required this.csrfToken,
    required this.expiresAt,
  });

  final String sessionToken;
  final String csrfToken;
  final DateTime expiresAt;

  static const String _sessionCookie = '__Host-dsh_ma_session';
  static const String _csrfCookie = '__Host-dsh_ma_csrf';
  static const String csrfHeader = 'x-dsh-mobile-csrf';

  Map<String, String> requestHeaders({bool mutating = false}) {
    return <String, String>{
      'Cookie': '$_sessionCookie=$sessionToken; $_csrfCookie=$csrfToken',
      if (mutating) csrfHeader: csrfToken,
    };
  }
}

final Random _random = Random.secure();

String newRpcId() {
  // 26 字符 base36，足够避免碰撞（与 DSH 客户端风格一致即可）。
  final buffer = StringBuffer();
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  for (var i = 0; i < 26; i += 1) {
    buffer.write(alphabet[_random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// 一元 RPC：POST /api，信封 `{type, rpcId, method, payload:{args}}`。
class RpcClient {
  RpcClient({
    required this.client,
    required this.origin,
    required SessionCredentials credentials,
  }) : _credentials = credentials;

  final HttpClient client;
  final Uri origin;
  SessionCredentials _credentials;

  void updateCredentials(SessionCredentials credentials) =>
      _credentials = credentials;

  Future<Object?> call(
    String endpoint, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) async {
    final rpcId = newRpcId();
    final request = await client.postUrl(origin.resolve('/api'));
    request.headers.contentType = ContentType.json;
    _credentials.requestHeaders(mutating: true).forEach(request.headers.set);
    request.add(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'type': 'client-request',
          'rpcId': rpcId,
          'method': endpoint,
          'payload': <String, Object?>{'args': args},
        }),
      ),
    );

    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode == 401) {
      throw const CompanionException('unauthorized', '会话已过期，需要重新连接');
    }
    if (response.statusCode != 200) {
      throw CompanionException(
        'http_${response.statusCode}',
        'RPC 失败（HTTP ${response.statusCode}）',
        details: text,
      );
    }
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    if (decoded['type'] != 'server-response') {
      throw const CompanionException('bad_response', '网关返回了非 RPC 响应');
    }
    final result =
        decoded['result'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    if (result['ok'] == true) {
      return result['value'];
    }
    final error =
        result['error'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    throw CompanionException(
      (error['code'] ?? 'rpc_error').toString(),
      (error['message'] ?? 'DSH 返回错误').toString(),
      details: error['details'],
    );
  }

  void close() => client.close(force: true);
}

/// 流式 RPC：WebSocket `/api/remote.mux`。
///
/// 帧（与 DSH `@deepseek-ai/dsh-api-gateway` 的 stream-protocol 一致）：
///   client -> host: {type:'open', streamId, endpoint, payload:{args}}
///                   {type:'item', streamId, value}
///                   {type:'end', streamId} / {type:'cancel', streamId}
///   host -> client: {type:'item', streamId, value}
///                   {type:'end', streamId}
///                   {type:'error', streamId, error}
class MuxClient {
  MuxClient({
    required this.client,
    required this.origin,
    required SessionCredentials credentials,
  }) : _credentials = credentials;

  final HttpClient client;
  final Uri origin;
  SessionCredentials _credentials;
  WebSocket? _socket;
  final Map<String, StreamController<Object?>> _streams =
      <String, StreamController<Object?>>{};
  Future<WebSocket>? _connecting;

  void updateCredentials(SessionCredentials credentials) =>
      _credentials = credentials;

  Future<WebSocket> _ensureSocket() {
    final existing = _socket;
    if (existing != null && existing.readyState == WebSocket.open) {
      return Future<WebSocket>.value(existing);
    }
    return _connecting ??= WebSocket.connect(
          origin.replace(scheme: 'wss', path: '/api/remote.mux').toString(),
          headers: _credentials.requestHeaders(),
          customClient: client,
          compression: CompressionOptions.compressionOff,
        )
        .then((socket) {
          _socket = socket;
          _connecting = null;
          socket.listen(
            _onFrame,
            onDone:
                () => _failAll(
                  const CompanionException('stream_closed', '事件流连接已断开'),
                ),
            onError:
                (Object error) => _failAll(
                  CompanionException('stream_error', '事件流出错：$error'),
                ),
            cancelOnError: false,
          );
          return socket;
        })
        .catchError((Object error) {
          _connecting = null;
          throw CompanionException('stream_connect_failed', '无法连接事件流：$error');
        });
  }

  void _onFrame(dynamic data) {
    if (data is! String) {
      return;
    }
    late final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final streamId = frame['streamId'];
    if (streamId is! String) {
      return;
    }
    final controller = _streams[streamId];
    if (controller == null) {
      return;
    }
    switch (frame['type']) {
      case 'item':
        controller.add(frame['value']);
      case 'end':
        _streams.remove(streamId);
        unawaited(controller.close());
      case 'error':
        final error =
            frame['error'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        _streams.remove(streamId);
        controller.addError(
          CompanionException(
            (error['code'] ?? 'stream_error').toString(),
            (error['message'] ?? '事件流错误').toString(),
          ),
        );
        unawaited(controller.close());
    }
  }

  void _failAll(CompanionException error) {
    _socket = null;
    final streams = List<StreamController<Object?>>.from(_streams.values);
    _streams.clear();
    for (final controller in streams) {
      controller.addError(error);
      unawaited(controller.close());
    }
  }

  /// 打开一条逻辑流，返回 Host 下行项。
  Stream<Object?> open(
    String endpoint, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) {
    final streamId = newRpcId();
    final controller = StreamController<Object?>();
    _streams[streamId] = controller;
    controller.onCancel = () {
      _streams.remove(streamId);
      final socket = _socket;
      if (socket != null && socket.readyState == WebSocket.open) {
        socket.add(
          jsonEncode(<String, Object?>{'type': 'cancel', 'streamId': streamId}),
        );
      }
    };
    unawaited(() async {
      try {
        final socket = await _ensureSocket();
        socket.add(
          jsonEncode(<String, Object?>{
            'type': 'open',
            'streamId': streamId,
            'endpoint': endpoint,
            'payload': <String, Object?>{'args': args},
          }),
        );
      } catch (error) {
        if (_streams.remove(streamId) != null) {
          controller.addError(
            error is CompanionException
                ? error
                : CompanionException('stream_connect_failed', '$error'),
          );
          await controller.close();
        }
      }
    }());
    return controller.stream;
  }

  Future<void> close() async {
    _failAll(const CompanionException('stream_closed', '事件流已关闭'));
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }
}
