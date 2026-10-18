import 'package:dsh_companion/core/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionSummary', () {
    test('copyWith 只改指定字段', () {
      final base = SessionSummary(
        id: 's1',
        title: '旧标题',
        status: SessionStatus.idle,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final next = base.copyWith(title: '新标题', status: SessionStatus.running);
      expect(next.id, 's1');
      expect(next.title, '新标题');
      expect(next.status, SessionStatus.running);
      expect(next.updatedAt, base.updatedAt);
    });

    test('相等性按值比较', () {
      final time = DateTime.fromMillisecondsSinceEpoch(42);
      final a = SessionSummary(
        id: 's',
        title: 't',
        status: SessionStatus.idle,
        updatedAt: time,
      );
      final b = SessionSummary(
        id: 's',
        title: 't',
        status: SessionStatus.idle,
        updatedAt: time,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('DeviceRecord', () {
    test('toString 不泄漏设备令牌', () {
      final device = DeviceRecord(
        instanceId: 'i',
        label: '书房电脑',
        origin: Uri.parse('https://192.168.1.2:3443'),
        deviceToken: 'super-secret-token',
        kind: GatewayKind.lan,
        deviceExpiresAt: DateTime.fromMillisecondsSinceEpoch(1),
      );
      expect(device.toString(), isNot(contains('super-secret-token')));
    });
  });

  group('AppSettings', () {
    test('copyWith 保留未指定字段', () {
      const settings = AppSettings();
      final updated = settings.copyWith(themeMode: AppThemeMode.dark);
      expect(updated.themeMode, AppThemeMode.dark);
      expect(updated.notificationsEnabled, settings.notificationsEnabled);
    });
  });

  group('SessionEvent', () {
    test('copyWith 更新工具状态', () {
      final event = SessionEvent(
        id: 'e1',
        kind: SessionEventKind.toolCall,
        at: DateTime.fromMillisecondsSinceEpoch(5),
        toolName: 'bash',
        toolStatus: 'running',
      );
      final done = event.copyWith(toolStatus: 'ok');
      expect(done.toolStatus, 'ok');
      expect(done.toolName, 'bash');
      expect(done.id, 'e1');
    });
  });
}
