import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contracts.dart';

/// 设备记录存储。
///
/// 设备令牌与固定 CA 属于敏感数据，统一放 `flutter_secure_storage`
/// （Android 走 Keystore 加密），不落到普通 SharedPreferences。
class DeviceStore {
  DeviceStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  static const String _key = 'dsh_companion_devices_v1';

  Future<List<DeviceRecord>> load() async {
    final raw = await _secure.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return <DeviceRecord>[];
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .toList(growable: false);
    } catch (_) {
      return <DeviceRecord>[];
    }
  }

  Future<void> save(List<DeviceRecord> devices) async {
    final payload = jsonEncode(devices.map(_toJson).toList(growable: false));
    await _secure.write(key: _key, value: payload);
  }

  Future<void> clear() => _secure.delete(key: _key);

  static Map<String, Object?> _toJson(DeviceRecord device) => <String, Object?>{
        'instanceId': device.instanceId,
        'label': device.label,
        'origin': device.origin.toString(),
        'deviceToken': device.deviceToken,
        'kind': device.kind.name,
        'deviceExpiresAt': device.deviceExpiresAt.millisecondsSinceEpoch,
        'caFingerprint': device.caFingerprint,
        'caPem': device.caPem,
        'lastConnectedAt': device.lastConnectedAt?.millisecondsSinceEpoch,
      };

  static DeviceRecord _fromJson(Map<String, dynamic> json) => DeviceRecord(
        instanceId: json['instanceId'] as String? ?? '',
        label: json['label'] as String? ?? '电脑',
        origin:
            Uri.parse(json['origin'] as String? ?? 'https://127.0.0.1:3443'),
        deviceToken: json['deviceToken'] as String? ?? '',
        kind: (json['kind'] as String?) == GatewayKind.remote.name
            ? GatewayKind.remote
            : GatewayKind.lan,
        deviceExpiresAt: DateTime.fromMillisecondsSinceEpoch(
            (json['deviceExpiresAt'] as num?)?.toInt() ?? 0),
        caFingerprint: json['caFingerprint'] as String?,
        caPem: json['caPem'] as String?,
        lastConnectedAt: json['lastConnectedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['lastConnectedAt'] as num).toInt()),
      );
}

/// 非敏感设置。
class SettingsStore {
  SettingsStore({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  static const String _key = 'dsh_companion_settings_v1';

  Future<AppSettings> load() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      return const AppSettings();
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings(
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        notifyOnComplete: json['notifyOnComplete'] as bool? ?? true,
        notifyOnWaiting: json['notifyOnWaiting'] as bool? ?? true,
        themeMode: AppThemeMode.values.firstWhere(
          (mode) => mode.name == json['themeMode'],
          orElse: () => AppThemeMode.system,
        ),
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(<String, Object?>{
        'notificationsEnabled': settings.notificationsEnabled,
        'notifyOnComplete': settings.notifyOnComplete,
        'notifyOnWaiting': settings.notifyOnWaiting,
        'themeMode': settings.themeMode.name,
      }),
    );
  }
}
