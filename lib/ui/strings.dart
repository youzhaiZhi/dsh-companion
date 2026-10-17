import 'package:flutter/material.dart';

import '../core/contracts.dart';

/// 中文文案集中管理，方便以后做 i18n。
abstract final class AppStrings {
  static const String appTitle = 'DSH 伴侣';
  static const String devicesEmptyTitle = '还没有配对电脑';
  static const String devicesEmptyBody = '在电脑上打开 DSH → 设置 → 移动访问 → 局域网，创建配对密钥，把链接粘贴进来。';
  static const String addDevice = '配对电脑';
  static const String connect = '连接';
  static const String rename = '重命名';
  static const String delete = '删除';
  static const String settings = '设置';
  static const String pairTitle = '配对电脑';
  static const String pairLinkLabel = '配对链接';
  static const String pairLinkHint = 'https://192.168.x.x:3443/mobile-access/pair#instance=...';
  static const String pairPaste = '粘贴';
  static const String pairManual = '手动输入地址与配对码';
  static const String pairOriginLabel = '网关地址';
  static const String pairCodeLabel = '配对码';
  static const String pairSubmit = '配对';
  static const String pairWorking = '正在配对…';
  static const String pairSuccess = '配对成功';
  static const String sessionsTitle = '会话';
  static const String sessionsEmpty = '这台电脑上还没有会话';
  static const String refresh = '刷新';
  static const String retry = '重试';
  static const String sendHint = '发一句话让 Agent 继续…';
  static const String send = '发送';
  static const String approve = '允许';
  static const String deny = '拒绝';
  static const String noMessage = '暂无消息';
  static const String diagnostics = '诊断日志';
  static const String notifications = '任务通知';
  static const String notifyComplete = '任务完成时提醒';
  static const String notifyWaiting = '等待输入时提醒';
  static const String theme = '主题';
  static const String themeSystem = '跟随系统';
  static const String themeLight = '浅色';
  static const String themeDark = '深色';
  static const String connecting = '连接中…';
  static const String connected = '已连接';
  static const String disconnected = '未连接';
  static const String failed = '连接失败';
}

String statusLabel(SessionStatus status) => switch (status) {
      SessionStatus.running => '进行中',
      SessionStatus.waitingInput => '等待输入',
      SessionStatus.idle => '空闲',
      SessionStatus.completed => '已完成',
      SessionStatus.unknown => '未知',
    };

Color statusColor(BuildContext context, SessionStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    SessionStatus.running => scheme.primary,
    SessionStatus.waitingInput => scheme.tertiary,
    SessionStatus.idle => scheme.secondary,
    SessionStatus.completed => scheme.outline,
    SessionStatus.unknown => scheme.outline,
  };
}

String gatewayKindLabel(GatewayKind kind) => kind == GatewayKind.lan ? '局域网' : '远程';

String connectionLabel(ConnectionPhase phase) => switch (phase) {
      ConnectionPhase.connecting => AppStrings.connecting,
      ConnectionPhase.connected => AppStrings.connected,
      ConnectionPhase.reconnecting => '重连中…',
      ConnectionPhase.failed => AppStrings.failed,
      ConnectionPhase.disconnected => AppStrings.disconnected,
    };
