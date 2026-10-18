import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../contracts.dart';
import '../gateway/companion_gateway_impl.dart';
import '../gateway/events.dart';
import '../gateway/pairing.dart';
import '../notifications/task_notifier.dart';
import '../storage/stores.dart';
import 'session_logic.dart';

/// 诊断日志（环形缓冲，脱敏后供设置页查看）。
class Diagnostics {
  Diagnostics({this.capacity = 200});

  final int capacity;
  final Queue<String> _lines = Queue<String>();

  List<String> get lines => List<String>.unmodifiable(_lines);

  void log(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    _lines.add('$stamp $message');
    while (_lines.length > capacity) {
      _lines.removeFirst();
    }
  }

  String export() => _lines.join('\n');
}

class SessionFeedImpl extends ChangeNotifier implements SessionFeed {
  SessionFeedImpl({
    required this.sessionId,
    required LiveCompanionGateway gateway,
    required SessionSummary summary,
    required Diagnostics diagnostics,
    required this.onEvent,
  })  : _gateway = gateway,
        _diagnostics = diagnostics,
        _summary = summary;

  @override
  final String sessionId;

  final LiveCompanionGateway _gateway;
  final Diagnostics _diagnostics;
  final void Function(SessionEvent event)? onEvent;
  final List<SessionEvent> _events = <SessionEvent>[];
  final Map<String, ApprovalRequest> _approvals = <String, ApprovalRequest>{};
  SessionSummary _summary;
  ConnectionPhase _phase = ConnectionPhase.connecting;
  Object? _error;
  StreamSubscription<SessionEvent>? _subscription;

  @override
  SessionSummary? get summary => _summary;

  @override
  List<SessionEvent> get events => List<SessionEvent>.unmodifiable(_events);

  @override
  ConnectionPhase get phase => _phase;

  @override
  Object? get error => _error;

  @override
  List<ApprovalRequest> get pendingApprovals =>
      List<ApprovalRequest>.unmodifiable(_approvals.values);

  void updateSummary(SessionSummary summary) {
    _summary = summary;
    notifyListeners();
  }

  @override
  Future<void> reload() async {
    await _subscription?.cancel();
    _subscription = null;
    _phase = ConnectionPhase.connecting;
    _error = null;
    notifyListeners();
    try {
      _subscription = _gateway.watchSession(sessionId).listen(
        _handleEvent,
        onError: (Object error) {
          _phase = ConnectionPhase.failed;
          _error = error;
          _diagnostics.log('session stream error: $error');
          notifyListeners();
        },
        onDone: () {
          if (_phase == ConnectionPhase.connecting) {
            _phase = ConnectionPhase.connected;
          }
          notifyListeners();
        },
        cancelOnError: false,
      );
    } catch (error) {
      _phase = ConnectionPhase.failed;
      _error = error;
      notifyListeners();
    }
  }

  void _handleEvent(SessionEvent event) {
    if (_phase == ConnectionPhase.connecting) {
      _phase = ConnectionPhase.connected;
    }
    // 同一个 tool 卡片复用 id 时会原地更新。
    final index = _events.indexWhere((existing) => existing.id == event.id);
    if (index >= 0) {
      _events[index] = event;
    } else {
      _events.add(event);
    }
    if (event.kind == SessionEventKind.approvalRequest &&
        event.approvalId != null) {
      _approvals[event.approvalId!] = ApprovalRequest(
        id: event.approvalId!,
        sessionId: sessionId,
        kind: ApprovalKind.tool,
        title: event.toolName ?? '需要审批',
        detail: event.text,
        createdAt: event.at,
      );
    }
    onEvent?.call(event);
    notifyListeners();
  }

  void removeApproval(String approvalId) {
    if (_approvals.remove(approvalId) != null) {
      notifyListeners();
    }
  }

  @override
  Future<void> disposeFeed() async {
    await _subscription?.cancel();
    _subscription = null;
    dispose();
  }
}

/// UI 唯一状态入口。
class CompanionControllerImpl extends CompanionController {
  CompanionControllerImpl({
    DeviceStore? deviceStore,
    SettingsStore? settingsStore,
    LiveCompanionGateway? gateway,
    TaskNotifierApi? notifier,
  })  : _deviceStore = deviceStore ?? DeviceStore(),
        _settingsStore = settingsStore ?? SettingsStore(),
        _gateway = gateway ?? LiveCompanionGateway(),
        _notifier = notifier ?? TaskNotifier();

  final DeviceStore _deviceStore;
  final SettingsStore _settingsStore;
  final LiveCompanionGateway _gateway;
  final TaskNotifierApi _notifier;
  final Diagnostics _diagnostics = Diagnostics();

  bool _initializing = true;
  List<DeviceRecord> _devices = <DeviceRecord>[];
  DeviceRecord? _activeDevice;
  ConnectionPhase _phase = ConnectionPhase.disconnected;
  String? _connectionError;
  List<SessionSummary> _sessions = <SessionSummary>[];
  DateTime? _sessionsUpdatedAt;
  SessionFeedImpl? _activeFeed;
  AppSettings _settings = const AppSettings();

  /// 待应答的审批/提问（来自 `$events` 瀑布）。
  final Map<String, ApprovalRequest> _approvals = <String, ApprovalRequest>{};
  StreamSubscription<HostEvent>? _eventsSubscription;

  @override
  bool get initializing => _initializing;

  @override
  List<DeviceRecord> get devices => List<DeviceRecord>.unmodifiable(_devices);

  @override
  DeviceRecord? get activeDevice => _activeDevice;

  @override
  ConnectionPhase get phase => _phase;

  @override
  String? get connectionError => _connectionError;

  @override
  List<SessionSummary> get sessions =>
      List<SessionSummary>.unmodifiable(_sessions);

  @override
  DateTime? get sessionsUpdatedAt => _sessionsUpdatedAt;

  @override
  SessionFeed? get activeFeed => _activeFeed;

  @override
  List<ApprovalRequest> get pendingApprovals =>
      List<ApprovalRequest>.unmodifiable(_approvals.values);

  @override
  AppSettings get settings => _settings;

  List<String> get diagnosticsLines => _diagnostics.lines;

  @override
  Future<void> initialize() async {
    try {
      _devices = await _deviceStore.load();
      _settings = await _settingsStore.load();
      _diagnostics.log('loaded ${_devices.length} device(s)');
    } catch (error) {
      _diagnostics.log('initialize failed: $error');
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  @override
  Future<PairingResult> pairWithLink(String link, {String? label}) async {
    final parsed = PairingLink.parse(link);
    return _pair(parsed, label: label);
  }

  @override
  Future<PairingResult> pairWithCode({
    required Uri origin,
    required String code,
    String? label,
  }) async {
    final caDer = await fetchGatewayCa(origin);
    final fingerprint = sha256Hex(caDer);
    final parsed = PairingLink(
        origin: origin, instanceId: fingerprint, token: code.trim());
    return _pair(parsed, label: label);
  }

  Future<PairingResult> _pair(PairingLink link, {String? label}) async {
    _connectionError = null;
    final outcome = await _gateway.pair(link: link, label: label ?? '我的电脑');
    final device = DeviceRecord(
      instanceId: outcome.instanceId,
      label: label ?? '我的电脑',
      origin: link.origin,
      deviceToken: outcome.deviceToken,
      kind: GatewayKind.lan,
      deviceExpiresAt: outcome.deviceExpiresAt,
      caFingerprint: outcome.caFingerprint,
      caPem: outcome.caPem,
    );
    _diagnostics.log('paired ${device.origin}');
    final updated = <DeviceRecord>[
      ..._devices.where((existing) =>
          existing.instanceId != device.instanceId ||
          existing.origin != device.origin),
      device,
    ];
    _devices = updated;
    await _deviceStore.save(updated);
    notifyListeners();
    await connect(device);
    return PairingResult(
      instanceId: outcome.instanceId,
      deviceId: outcome.deviceId,
      deviceToken: outcome.deviceToken,
      deviceExpiresAt: outcome.deviceExpiresAt,
      sessionExpiresAt: outcome.sessionExpiresAt,
      csrfToken: outcome.csrfToken,
    );
  }

  @override
  Future<void> connect(DeviceRecord device) async {
    _phase = ConnectionPhase.connecting;
    _connectionError = null;
    _activeDevice = device;
    notifyListeners();
    try {
      await _gateway.connect(device);
      _phase = ConnectionPhase.connected;
      _diagnostics.log('connected ${device.origin}');
      final index = _devices.indexWhere((existing) =>
          existing.instanceId == device.instanceId &&
          existing.origin == device.origin);
      if (index >= 0) {
        final touched = device.copyWith(lastConnectedAt: DateTime.now());
        _devices[index] = touched;
        _activeDevice = touched;
        await _deviceStore.save(_devices);
      }
      notifyListeners();
      _startEventSubscription();
      await refreshSessions();
    } catch (error) {
      _phase = ConnectionPhase.failed;
      _connectionError = error is CompanionException ? error.message : '$error';
      _diagnostics.log('connect failed: $_connectionError');
      notifyListeners();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _approvals.clear();
    await _gateway.close();
    await _activeFeed?.disposeFeed();
    _activeFeed = null;
    _activeDevice = null;
    _phase = ConnectionPhase.disconnected;
    _sessions = <SessionSummary>[];
    notifyListeners();
  }

  @override
  Future<void> refreshSessions() async {
    if (!_gateway.isConnected) {
      return;
    }
    try {
      _sessions = await _gateway.listSessions();
      _sessionsUpdatedAt = DateTime.now();
      _connectionError = null;
      notifyListeners();
    } on CompanionException catch (error) {
      if (error.code == 'unauthorized') {
        await _renew();
        _sessions = await _gateway.listSessions();
        _sessionsUpdatedAt = DateTime.now();
        notifyListeners();
        return;
      }
      _connectionError = error.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _renew() async {
    final device = _activeDevice;
    if (device == null) {
      return;
    }
    await _gateway.connect(device);
  }

  @override
  Future<void> openSession(String sessionId) async {
    final summary = _sessions.firstWhere(
      (session) => session.id == sessionId,
      orElse: () => SessionSummary(
          id: sessionId,
          title: sessionId,
          status: SessionStatus.unknown,
          updatedAt: DateTime.now()),
    );
    await _activeFeed?.disposeFeed();
    final feed = SessionFeedImpl(
      sessionId: sessionId,
      gateway: _gateway,
      summary: summary,
      diagnostics: _diagnostics,
      onEvent: (event) => _onFeedEvent(sessionId, event),
    );
    _activeFeed = feed;
    notifyListeners();
    await feed.reload();
    notifyListeners();
  }

  void _onFeedEvent(String sessionId, SessionEvent event) =>
      applySessionEvent(sessionId, event);

  /// 把一个会话事件并进列表状态（状态徽章 + 通知）。
  ///
  /// 供 SessionFeed 回调与测试驱动使用：只做状态折叠与通知，不发网络请求。
  void applySessionEvent(String sessionId, SessionEvent event) {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index < 0) {
      return;
    }
    final current = _sessions[index];
    final nextStatus = sessionStatusAfterEvent(current.status, event);
    if (nextStatus != current.status) {
      _sessions[index] =
          current.copyWith(status: nextStatus, updatedAt: DateTime.now());
      notifyListeners();
      _maybeNotify(current, nextStatus);
    }
  }

  /// 任务完成 / 等待输入时提醒；只在状态真的变化时触发一次。
  void _maybeNotify(SessionSummary session, SessionStatus nextStatus) {
    final notification = taskNotificationFor(
      session: session,
      nextStatus: nextStatus,
      settings: _settings,
    );
    if (notification == null) {
      return;
    }
    unawaited(_notifier.notifyTask(
        title: notification.title, body: notification.body));
  }

  @override
  Future<void> closeSession() async {
    await _activeFeed?.disposeFeed();
    _activeFeed = null;
    notifyListeners();
  }

  @override
  Future<void> sendPrompt(String sessionId, String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    await _gateway.sendPrompt(sessionId, text.trim());
    _diagnostics.log('prompt sent to $sessionId');
  }

  @override
  Future<void> decideApproval(
    ApprovalRequest request,
    ApprovalDecision decision, {
    List<String> selectedOptions = const <String>[],
  }) async {
    await _gateway.decideApproval(request, decision,
        selectedOptions: selectedOptions);
    _approvals.remove(request.id);
    _activeFeed?.removeApproval(request.id);
    notifyListeners();
  }

  @override
  Future<void> refreshPendingApprovals() async {
    _syncApprovalsFromGateway();
    notifyListeners();
  }

  /// 事件流里的 waterfall 帧 → 待审批列表 + 会话状态 + 通知。
  void _syncApprovalsFromGateway() {
    final pending = _gateway.pendingApprovals;
    final next = <String, ApprovalRequest>{
      for (final approval in pending)
        approval.eventId: approval.toApprovalRequest(),
    };
    final added = next.keys.where((id) => !_approvals.containsKey(id)).toList();
    final removed =
        _approvals.keys.where((id) => !next.containsKey(id)).toList();
    if (added.isEmpty && removed.isEmpty) {
      return;
    }
    _approvals
      ..removeWhere((id, _) => removed.contains(id))
      ..addAll(next);
    for (final request in _approvals.values) {
      final index =
          _sessions.indexWhere((session) => session.id == request.sessionId);
      if (index >= 0 && _sessions[index].status != SessionStatus.waitingInput) {
        final current = _sessions[index];
        _sessions[index] = current.copyWith(
          status: SessionStatus.waitingInput,
          updatedAt: DateTime.now(),
        );
        _maybeNotify(current, SessionStatus.waitingInput);
      }
    }
    for (final request in added.map((id) => next[id]!)) {
      _diagnostics.log('approval pending ${request.title}');
      // 没有对应会话行时也提醒一次（例如会话列表尚未刷新）。
      if (!_sessions.any((session) => session.id == request.sessionId)) {
        unawaited(_notifier.notifyTask(
          title: 'DSH 等待你的审批',
          body: request.title,
        ));
      }
    }
  }

  void _startEventSubscription() {
    unawaited(_eventsSubscription?.cancel());
    _gateway.ensureEventsSubscribed();
    _eventsSubscription = _gateway.hostEvents.listen(
      (event) {
        if (event is HostWaterfallEvent || event is HostCancelEvent) {
          _syncApprovalsFromGateway();
          notifyListeners();
        }
      },
      onError: (Object error) => _diagnostics.log('event stream error: $error'),
    );
  }

  @override
  Future<void> removeDevice(String instanceId) async {
    _devices = _devices
        .where((device) => device.instanceId != instanceId)
        .toList(growable: false);
    await _deviceStore.save(_devices);
    if (_activeDevice?.instanceId == instanceId) {
      await disconnect();
    }
    notifyListeners();
  }

  @override
  Future<void> renameDevice(String instanceId, String label) async {
    _devices = _devices
        .map((device) => device.instanceId == instanceId
            ? device.copyWith(label: label)
            : device)
        .toList(growable: false);
    await _deviceStore.save(_devices);
    notifyListeners();
  }

  @override
  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _settingsStore.save(settings);
    notifyListeners();
  }

  @override
  Future<String> exportDiagnostics() async => _diagnostics.export();
}
