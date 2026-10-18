import 'package:dsh_companion/core/contracts.dart';

/// UI 测试用的假控制器：状态手动设置，异步方法只记录调用。
class FakeCompanionController extends CompanionController {
  FakeCompanionController({
    List<DeviceRecord> devices = const <DeviceRecord>[],
    List<SessionSummary> sessions = const <SessionSummary>[],
    this.settings = const AppSettings(),
    this.phase = ConnectionPhase.disconnected,
    this.connectionError,
    this.activeDevice,
    this.activeFeed,
    this.initializing = false,
  }) : _devices = List<DeviceRecord>.from(devices),
       _sessions = List<SessionSummary>.from(sessions);

  final List<DeviceRecord> _devices;
  final List<SessionSummary> _sessions;

  @override
  AppSettings settings;

  @override
  ConnectionPhase phase;

  @override
  String? connectionError;

  @override
  DeviceRecord? activeDevice;

  @override
  SessionFeed? activeFeed;

  @override
  bool initializing;

  @override
  DateTime? sessionsUpdatedAt;

  @override
  List<ApprovalRequest> get pendingApprovals =>
      pendingApprovalsOverride ??
      activeFeed?.pendingApprovals ??
      const <ApprovalRequest>[];

  /// 直接指定待审批列表（测试 UI 横幅/卡片用）。
  List<ApprovalRequest>? pendingApprovalsOverride;

  /// 记录 UI 触发的调用，供断言。
  final List<String> calls = <String>[];

  /// 下一次调用抛出的错误（用于测试错误态）。
  Object? nextError;

  @override
  List<DeviceRecord> get devices => List<DeviceRecord>.unmodifiable(_devices);

  @override
  List<SessionSummary> get sessions =>
      List<SessionSummary>.unmodifiable(_sessions);

  void setDevices(List<DeviceRecord> devices) {
    _devices
      ..clear()
      ..addAll(devices);
    notifyListeners();
  }

  void setSessions(List<SessionSummary> sessions) {
    _sessions
      ..clear()
      ..addAll(sessions);
    notifyListeners();
  }

  void _record(String call) {
    calls.add(call);
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<void> initialize() async => _record('initialize');

  @override
  Future<PairingResult> pairWithLink(String link, {String? label}) async {
    _record('pairWithLink:$link');
    return _pairingResult;
  }

  @override
  Future<PairingResult> pairWithCode({
    required Uri origin,
    required String code,
    String? label,
  }) async {
    _record('pairWithCode:$origin:$code');
    return _pairingResult;
  }

  @override
  Future<void> connect(DeviceRecord device) async =>
      _record('connect:${device.label}');

  @override
  Future<void> disconnect() async => _record('disconnect');

  @override
  Future<void> removeDevice(String instanceId) async =>
      _record('removeDevice:$instanceId');

  @override
  Future<void> renameDevice(String instanceId, String label) async =>
      _record('renameDevice:$instanceId:$label');

  @override
  Future<void> refreshSessions() async => _record('refreshSessions');

  @override
  Future<void> openSession(String sessionId) async =>
      _record('openSession:$sessionId');

  @override
  Future<void> closeSession() async => _record('closeSession');

  @override
  Future<void> sendPrompt(String sessionId, String text) async =>
      _record('sendPrompt:$sessionId:$text');

  @override
  Future<void> decideApproval(
    ApprovalRequest request,
    ApprovalDecision decision, {
    List<String> selectedOptions = const <String>[],
  }) async {
    _record('decideApproval:${request.id}:${decision.name}');
  }

  @override
  Future<void> refreshPendingApprovals() async =>
      _record('refreshPendingApprovals');

  @override
  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    _record('updateSettings');
    notifyListeners();
  }

  @override
  Future<String> exportDiagnostics() async {
    _record('exportDiagnostics');
    return 'diagnostic line';
  }
}

final PairingResult _pairingResult = PairingResult(
  instanceId: 'instance-1',
  deviceId: 'device-1',
  deviceToken: 'token-1',
  deviceExpiresAt: DateTime.fromMillisecondsSinceEpoch(0),
  sessionExpiresAt: DateTime.fromMillisecondsSinceEpoch(0),
  csrfToken: 'csrf-1',
);

/// 会话事件流假实现。
class FakeSessionFeed extends SessionFeed {
  FakeSessionFeed({
    required this.sessionId,
    this.summary,
    List<SessionEvent> events = const <SessionEvent>[],
    List<ApprovalRequest> approvals = const <ApprovalRequest>[],
    this.phase = ConnectionPhase.connected,
    this.error,
  }) : _events = List<SessionEvent>.from(events),
       _approvals = List<ApprovalRequest>.from(approvals);

  @override
  final String sessionId;

  @override
  final SessionSummary? summary;

  final List<SessionEvent> _events;
  final List<ApprovalRequest> _approvals;

  @override
  ConnectionPhase phase;

  @override
  Object? error;

  @override
  List<SessionEvent> get events => List<SessionEvent>.unmodifiable(_events);

  @override
  List<ApprovalRequest> get pendingApprovals =>
      List<ApprovalRequest>.unmodifiable(_approvals);

  @override
  Future<void> reload() async {}

  @override
  Future<void> disposeFeed() async {}
}
