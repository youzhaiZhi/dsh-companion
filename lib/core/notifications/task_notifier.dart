import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知抽象：控制器只依赖它，测试里可以替换成记录器。
abstract class TaskNotifierApi {
  Future<void> initialize();

  Future<void> notifyTask({required String title, required String body});
}

/// Android 本地通知实现。
///
/// 只在 Android 上真正发通知；其他平台（含测试环境）静默降级，
/// 这样 widget/单元测试不需要平台通道。
class TaskNotifier implements TaskNotifierApi {
  TaskNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _providedPlugin = plugin;

  final FlutterLocalNotificationsPlugin? _providedPlugin;
  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;
  int _nextId = 1;

  static const String _channelId = 'dsh_companion_tasks';
  static const String _channelName = 'DSH 任务提醒';
  static const String _channelDescription = '任务完成、等待输入时的提醒';

  @override
  Future<void> initialize() async {
    if (_initialized || !Platform.isAndroid) {
      return;
    }
    final plugin = _providedPlugin ?? FlutterLocalNotificationsPlugin();
    _plugin = plugin;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(settings);
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.defaultImportance,
      ),
    );
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  @override
  Future<void> notifyTask({required String title, required String body}) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await initialize();
      final plugin = _plugin;
      if (plugin == null) {
        return;
      }
      await plugin.show(
        _nextId++,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            // 锁屏文本保持通用占位，不泄漏会话内容。
            category: AndroidNotificationCategory.progress,
          ),
        ),
      );
    } catch (_) {
      // 通知失败不打断会话。
    }
  }
}
