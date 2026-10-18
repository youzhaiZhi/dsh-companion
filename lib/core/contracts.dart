// DSH 伴侣（dsh-companion）架构契约。
//
// 这个文件是 UI 层与核心层之间唯一的共享入口：
//   * `ui/` 只允许依赖本文件（+ Flutter/第三方包），不得 import core 的实现文件。
//   * `core/` 提供 `CompanionController` / `SessionFeed` / `CompanionGateway` 的实现。
//
// 修改本文件属于架构变更：先在 docs/app-architecture.md 更新，再同步给 Lead。
//
// 设计原则：
//   * 纯数据模型（不可变，`@immutable`），不依赖 Flutter Material / 网络库。
//   * 异步操作抛 `CompanionException`；UI 只展示 `message`，`code` 用于日志与测试断言。
//   * 协议细节（JSON 字段、RPC 方法名）不属于契约，放在 core/gateway 里。

import 'package:flutter/foundation.dart';

/// 连接类型：局域网直连 / 远程通道。
enum GatewayKind { lan, remote }

/// 一台已配对的电脑（dsh-mobile 网关）。
@immutable
class DeviceRecord {
  const DeviceRecord({
    required this.instanceId,
    required this.label,
    required this.origin,
    required this.deviceToken,
    required this.kind,
    required this.deviceExpiresAt,
    this.caFingerprint,
    this.caPem,
    this.lastConnectedAt,
  });

  /// 稳定的 DSH 安装标识，用于地址变化时合并记录。
  final String instanceId;

  /// 用户可改的显示名。
  final String label;

  /// 网关 origin，例如 `https://192.168.0.198:3443`。
  final Uri origin;

  /// 长期设备令牌（敏感；只存安全存储，不打印、不入日志）。
  final String deviceToken;

  final GatewayKind kind;

  /// 设备令牌过期时间；过期后需要重新配对。
  final DateTime deviceExpiresAt;

  /// 局域网自签证书的 SHA-256 指纹（小写十六进制，无分隔符）。
  final String? caFingerprint;

  /// 配对时拿到的 CA 证书 PEM（可选，用于构建信任链）。
  final String? caPem;

  final DateTime? lastConnectedAt;

  DeviceRecord copyWith({
    String? label,
    Uri? origin,
    String? deviceToken,
    GatewayKind? kind,
    DateTime? deviceExpiresAt,
    String? caFingerprint,
    String? caPem,
    DateTime? lastConnectedAt,
  }) {
    return DeviceRecord(
      instanceId: instanceId,
      label: label ?? this.label,
      origin: origin ?? this.origin,
      deviceToken: deviceToken ?? this.deviceToken,
      kind: kind ?? this.kind,
      deviceExpiresAt: deviceExpiresAt ?? this.deviceExpiresAt,
      caFingerprint: caFingerprint ?? this.caFingerprint,
      caPem: caPem ?? this.caPem,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceRecord &&
      other.instanceId == instanceId &&
      other.label == label &&
      other.origin == origin &&
      other.deviceToken == deviceToken &&
      other.kind == kind &&
      other.deviceExpiresAt == deviceExpiresAt &&
      other.caFingerprint == caFingerprint &&
      other.caPem == caPem &&
      other.lastConnectedAt == lastConnectedAt;

  @override
  int get hashCode => Object.hash(
    instanceId,
    label,
    origin,
    deviceToken,
    kind,
    deviceExpiresAt,
    caFingerprint,
    caPem,
    lastConnectedAt,
  );

  /// 调试输出不含令牌。
  @override
  String toString() => 'DeviceRecord($label, $origin, $kind)';
}

/// 会话状态（UI 徽章用）。
enum SessionStatus {
  /// Agent 正在跑。
  running,

  /// 等待用户回答（提问 / 审批）。
  waitingInput,

  /// 空闲，可以继续发消息。
  idle,

  /// 本轮已完成（历史会话）。
  completed,

  /// 未知 / 未来新增。
  unknown,
}

/// 会话列表项。
@immutable
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.updatedAt,
    this.workspace,
    this.model,
    this.preview,
    this.unread = false,
  });

  final String id;
  final String title;
  final String? workspace;
  final String? model;

  /// 最近一条消息的摘要（单行）。
  final String? preview;

  final SessionStatus status;
  final DateTime updatedAt;
  final bool unread;

  SessionSummary copyWith({
    String? title,
    SessionStatus? status,
    DateTime? updatedAt,
    String? workspace,
    String? model,
    String? preview,
    bool? unread,
  }) {
    return SessionSummary(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      workspace: workspace ?? this.workspace,
      model: model ?? this.model,
      preview: preview ?? this.preview,
      unread: unread ?? this.unread,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionSummary &&
      other.id == id &&
      other.title == title &&
      other.status == status &&
      other.updatedAt == updatedAt &&
      other.workspace == workspace &&
      other.model == model &&
      other.preview == preview &&
      other.unread == unread;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    status,
    updatedAt,
    workspace,
    model,
    preview,
    unread,
  );
}

/// 事件流里的一条事件。
enum SessionEventKind {
  userMessage,
  assistantMessage,

  /// 工具的思考/调用开始。
  toolCall,

  /// 工具结果返回。
  toolResult,

  /// 需要用户审批 / 回答。
  approvalRequest,

  /// 会话状态变化（running/waiting/idle/completed）。
  statusChange,

  /// token / 步数等用量信息。
  usage,

  error,

  /// 未识别事件（保留原始 meta，UI 可折叠展示）。
  unknown,
}

/// 流式事件。
@immutable
class SessionEvent {
  const SessionEvent({
    required this.id,
    required this.kind,
    required this.at,
    this.text,
    this.toolName,
    this.toolStatus,
    this.toolDetail,
    this.approvalId,
    this.meta = const <String, Object?>{},
  });

  /// 事件内唯一 id（流内去重用）。
  final String id;
  final SessionEventKind kind;
  final DateTime at;

  /// 消息文本 / 工具结果的文本摘要。
  final String? text;

  final String? toolName;

  /// 工具调用状态：running / ok / error 等。
  final String? toolStatus;

  /// 工具参数或结果的展示文本。
  final String? toolDetail;

  /// 关联的审批请求 id（kind == approvalRequest 时）。
  final String? approvalId;

  /// 原始协议字段的兜底（UI 不直接依赖，调试/将来扩展用）。
  final Map<String, Object?> meta;

  SessionEvent copyWith({
    String? text,
    String? toolStatus,
    String? toolDetail,
    SessionEventKind? kind,
    Map<String, Object?>? meta,
  }) {
    return SessionEvent(
      id: id,
      kind: kind ?? this.kind,
      at: at,
      text: text ?? this.text,
      toolName: toolName,
      toolStatus: toolStatus ?? this.toolStatus,
      toolDetail: toolDetail ?? this.toolDetail,
      approvalId: approvalId,
      meta: meta ?? this.meta,
    );
  }

  @override
  String toString() => 'SessionEvent($kind, $id)';
}

/// 审批类型：工具调用 / 提问卡片。
enum ApprovalKind { tool, question }

/// 待用户处理的审批或提问。
@immutable
class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.detail,
    this.options = const <String>[],
    this.multiple = false,
    this.toolName,
  });

  final String id;
  final String sessionId;
  final ApprovalKind kind;

  /// 一行标题，例如工具名或问题标题。
  final String title;

  /// 详情正文（工具参数、问题描述、选项说明）。
  final String? detail;

  /// 提问卡片可选项；工具审批为空。
  final List<String> options;

  /// 是否多选。
  final bool multiple;

  final DateTime createdAt;
  final String? toolName;

  @override
  bool operator ==(Object other) => other is ApprovalRequest && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 审批结果。
enum ApprovalDecision {
  /// 允许工具执行（或确认）。
  allow,

  /// 拒绝。
  deny,

  /// 取消本轮 / 关闭卡片。
  cancel,
}

/// 配对结果。
@immutable
class PairingResult {
  const PairingResult({
    required this.instanceId,
    required this.deviceId,
    required this.deviceToken,
    required this.deviceExpiresAt,
    required this.sessionExpiresAt,
    this.csrfToken,
  });

  final String instanceId;
  final String deviceId;
  final String deviceToken;
  final DateTime deviceExpiresAt;
  final DateTime sessionExpiresAt;
  final String? csrfToken;
}

/// 连接阶段（UI 顶部状态条）。
enum ConnectionPhase {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

/// 应用设置。
@immutable
class AppSettings {
  const AppSettings({
    this.notificationsEnabled = true,
    this.notifyOnComplete = true,
    this.notifyOnWaiting = true,
    this.themeMode = AppThemeMode.system,
  });

  final bool notificationsEnabled;
  final bool notifyOnComplete;
  final bool notifyOnWaiting;
  final AppThemeMode themeMode;

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? notifyOnComplete,
    bool? notifyOnWaiting,
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
      notifyOnWaiting: notifyOnWaiting ?? this.notifyOnWaiting,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

enum AppThemeMode { system, light, dark }

/// 统一异常：UI 只展示 message。
class CompanionException implements Exception {
  const CompanionException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'CompanionException($code): $message';
}

/// 单个会话的实时事件流（UI 观察它渲染详情页）。
abstract class SessionFeed extends ChangeNotifier {
  String get sessionId;

  /// 会话摘要（标题/状态可能随事件更新）。
  SessionSummary? get summary;

  /// 当前已收到的事件（按时间正序）。
  List<SessionEvent> get events;

  /// 该会话事件流的连接阶段。
  ConnectionPhase get phase;

  /// 最近一次错误（可空）。
  Object? get error;

  /// 该会话待处理的审批/提问。
  List<ApprovalRequest> get pendingApprovals;

  /// 主动重新拉取一次（断线恢复后调用）。
  Future<void> reload();

  /// 停止事件流并释放资源。
  Future<void> disposeFeed();
}

/// UI 的唯一状态入口（core 实现并注入）。
abstract class CompanionController extends ChangeNotifier {
  // ---- 状态 ----
  bool get initializing;

  List<DeviceRecord> get devices;

  DeviceRecord? get activeDevice;

  ConnectionPhase get phase;

  String? get connectionError;

  List<SessionSummary> get sessions;

  DateTime? get sessionsUpdatedAt;

  SessionFeed? get activeFeed;

  List<ApprovalRequest> get pendingApprovals;

  AppSettings get settings;

  // ---- 生命周期 ----
  Future<void> initialize();

  // ---- 配对 / 设备 ----
  /// 粘贴 dsh-mobile 配对链接完成配对。
  Future<PairingResult> pairWithLink(String link, {String? label});

  /// 手动地址 + 配对码完成配对（origin 形如 https://192.168.1.5:3443）。
  Future<PairingResult> pairWithCode({
    required Uri origin,
    required String code,
    String? label,
  });

  Future<void> connect(DeviceRecord device);

  Future<void> disconnect();

  Future<void> removeDevice(String instanceId);

  Future<void> renameDevice(String instanceId, String label);

  // ---- 会话 ----
  Future<void> refreshSessions();

  Future<void> openSession(String sessionId);

  Future<void> closeSession();

  Future<void> sendPrompt(String sessionId, String text);

  // ---- 审批 ----
  Future<void> decideApproval(
    ApprovalRequest request,
    ApprovalDecision decision, {
    List<String> selectedOptions,
  });

  Future<void> refreshPendingApprovals();

  // ---- 设置 / 诊断 ----
  Future<void> updateSettings(AppSettings settings);

  /// 返回最近的诊断日志文本（不含令牌）。
  Future<String> exportDiagnostics();
}

/// 网关抽象：core 实现（真实网关 / mock），便于单测替换。
abstract class CompanionGateway {
  Future<PairingResult> pair({
    required Uri origin,
    required String pairingToken,
    String? label,
    String? caFingerprint,
  });

  Future<PairingResult> renew(DeviceRecord device);

  Future<List<SessionSummary>> listSessions();

  Stream<SessionEvent> watchSession(String sessionId);

  Future<void> sendPrompt(String sessionId, String text);

  Future<void> respondApproval(
    ApprovalRequest request,
    ApprovalDecision decision, {
    List<String> selectedOptions,
  });

  Future<List<ApprovalRequest>> pendingApprovals();

  Future<void> logout(DeviceRecord device);

  Future<void> close();
}
