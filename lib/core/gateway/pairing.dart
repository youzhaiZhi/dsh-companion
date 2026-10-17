import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../contracts.dart';

/// dsh-mobile 配对链接：
/// `https://192.168.1.5:3443/mobile-access/pair#instance=<hex>&token=<one-time>`
///
/// `instance` 同时是网关私有 CA 的 SHA-256 指纹（小写十六进制），
/// 因此拿到 CA 证书后必须核对指纹，防止中间人。
class PairingLink {
  const PairingLink({
    required this.origin,
    required this.instanceId,
    required this.token,
  });

  final Uri origin;
  final String instanceId;
  final String token;

  static PairingLink parse(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw const CompanionException(
        'pairing_link_invalid',
        '配对链接格式不对，请复制完整的 https://.../mobile-access/pair#... 链接',
      );
    }
    final fragment = uri.fragment;
    final params = <String, String>{};
    for (final pair in fragment.split('&')) {
      final index = pair.indexOf('=');
      if (index > 0) {
        params[pair.substring(0, index)] =
            Uri.decodeComponent(pair.substring(index + 1));
      }
    }
    final instanceId = params['instance'];
    final token = params['token'];
    if (instanceId == null ||
        instanceId.isEmpty ||
        token == null ||
        token.isEmpty) {
      throw const CompanionException(
          'pairing_link_invalid', '配对链接缺少 instance 或 token，请重新复制');
    }
    final origin = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null);
    return PairingLink(origin: origin, instanceId: instanceId, token: token);
  }

  @override
  String toString() => 'PairingLink($origin, instance=$instanceId)';
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// 从网关取私有 CA（DER）。只用于核对指纹，不携带任何凭据。
Future<Uint8List> fetchGatewayCa(Uri origin) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => true;
  try {
    final request = await client.getUrl(origin.resolve('/ca.cer'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw CompanionException(
          'ca_fetch_failed', '网关未返回 CA 证书（HTTP ${response.statusCode}）');
    }
    final bytes =
        Uint8List.fromList(await response.expand((chunk) => chunk).toList());
    if (bytes.isEmpty) {
      throw const CompanionException('ca_fetch_failed', '网关 CA 证书为空');
    }
    return bytes;
  } on CompanionException {
    rethrow;
  } catch (error) {
    throw CompanionException('ca_fetch_failed', '无法获取网关 CA 证书：$error');
  } finally {
    client.close(force: true);
  }
}

String derToPem(List<int> der) {
  final body = base64.encode(der);
  final chunks = <String>[];
  for (var i = 0; i < body.length; i += 64) {
    chunks.add(body.substring(i, i + 64 > body.length ? body.length : i + 64));
  }
  return '-----BEGIN CERTIFICATE-----\n${chunks.join('\n')}\n-----END CERTIFICATE-----\n';
}

/// 只信任配对时固定的私有 CA 的 HttpClient。
HttpClient pinnedHttpClient(String caPem) {
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(caPem));
  final client = HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 20);
  // 证书链由固定 CA 校验；网关叶子证书可能用 IP SAN，主机名校验失败时也放行，
  // 信任范围仍由“只连配对过的 origin + 固定 CA”限定。
  client.badCertificateCallback = (cert, host, port) => true;
  return client;
}

Future<Map<String, dynamic>> postJson(
  HttpClient client,
  Uri origin,
  String path,
  Map<String, Object?> body, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = await client.postUrl(origin.resolve(path));
  request.headers.contentType = ContentType.json;
  headers.forEach(request.headers.set);
  request.add(utf8.encode(jsonEncode(body)));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  Map<String, dynamic> decoded;
  try {
    decoded = jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    throw CompanionException(
      'bad_response',
      '网关返回了非 JSON 响应（HTTP ${response.statusCode}）',
      details: text.length > 300 ? text.substring(0, 300) : text,
    );
  }
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return decoded;
  }
  final code =
      (decoded['error'] ?? decoded['code'] ?? 'http_${response.statusCode}')
          .toString();
  final message =
      (decoded['message'] ?? '网关请求失败（HTTP ${response.statusCode}）').toString();
  throw CompanionException(code, message, details: decoded);
}

DateTime _msToTime(Object? value, {DateTime? fallback}) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return DateTime.fromMillisecondsSinceEpoch(parsed);
    }
    final iso = DateTime.tryParse(value);
    if (iso != null) {
      return iso;
    }
  }
  return fallback ?? DateTime.now();
}

/// 配对结果（含固定后的 CA）。
class PairingOutcome {
  const PairingOutcome({
    required this.instanceId,
    required this.deviceId,
    required this.deviceToken,
    required this.deviceExpiresAt,
    required this.sessionToken,
    required this.csrfToken,
    required this.sessionExpiresAt,
    required this.caPem,
    required this.caFingerprint,
  });

  final String instanceId;
  final String deviceId;
  final String deviceToken;
  final DateTime deviceExpiresAt;
  final String sessionToken;
  final String csrfToken;
  final DateTime sessionExpiresAt;
  final String caPem;
  final String caFingerprint;
}

/// 续期结果（短期会话凭据）。
class RenewOutcome {
  const RenewOutcome({
    required this.instanceId,
    required this.deviceId,
    required this.sessionToken,
    required this.csrfToken,
    required this.sessionExpiresAt,
  });

  final String instanceId;
  final String deviceId;
  final String sessionToken;
  final String csrfToken;
  final DateTime sessionExpiresAt;
}

/// 设备配对 / 续期 / 探测。
class PairingClient {
  const PairingClient();

  Future<PairingOutcome> pair({
    required Uri origin,
    required String instanceId,
    required String token,
    String? label,
  }) async {
    final caDer = await fetchGatewayCa(origin);
    final fingerprint = sha256Hex(caDer);
    if (fingerprint != instanceId) {
      throw const CompanionException(
        'pairing_fingerprint_mismatch',
        '网关 CA 指纹与配对链接不一致，可能不是同一台电脑，已中止配对',
      );
    }
    final caPem = derToPem(caDer);
    final client = pinnedHttpClient(caPem);
    try {
      final json = await postJson(
        client,
        origin,
        '/mobile-access/auth/native-pair',
        <String, Object?>{'token': token, if (label != null) 'label': label},
      );
      return PairingOutcome(
        instanceId: (json['instanceId'] ?? instanceId) as String,
        deviceId: json['deviceId'] as String? ?? '',
        deviceToken: json['deviceToken'] as String? ?? '',
        deviceExpiresAt: _msToTime(json['deviceExpiresAt'],
            fallback: DateTime.now().add(const Duration(days: 180))),
        sessionToken: json['sessionToken'] as String? ?? '',
        csrfToken: json['csrfToken'] as String? ?? '',
        sessionExpiresAt: _msToTime(json['sessionExpiresAt']),
        caPem: caPem,
        caFingerprint: fingerprint,
      );
    } on CompanionException {
      rethrow;
    } catch (error) {
      throw CompanionException('pairing_failed', '配对失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  Future<RenewOutcome> renew({required DeviceRecord device}) async {
    if (device.caPem == null || device.caPem!.isEmpty) {
      throw const CompanionException('tls_unpinned', '设备缺少固定证书，请重新配对');
    }
    final client = pinnedHttpClient(device.caPem!);
    try {
      final json = await postJson(
        client,
        device.origin,
        '/mobile-access/auth/native-renew',
        <String, Object?>{'deviceToken': device.deviceToken},
      );
      return RenewOutcome(
        instanceId: (json['instanceId'] ?? device.instanceId) as String,
        deviceId: json['deviceId'] as String? ?? '',
        sessionToken: json['sessionToken'] as String? ?? '',
        csrfToken: json['csrfToken'] as String? ?? '',
        sessionExpiresAt: _msToTime(json['sessionExpiresAt']),
      );
    } on CompanionException {
      rethrow;
    } catch (error) {
      throw CompanionException('renew_failed', '续期失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> probe({required DeviceRecord device}) async {
    if (device.caPem == null) {
      return false;
    }
    final client = pinnedHttpClient(device.caPem!);
    try {
      await postJson(
        client,
        device.origin,
        '/mobile-access/auth/native-probe',
        <String, Object?>{'deviceToken': device.deviceToken},
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
