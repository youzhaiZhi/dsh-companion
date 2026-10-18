import 'package:dsh_companion/core/contracts.dart';
import 'package:dsh_companion/core/gateway/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PairingLink.parse', () {
    test('解析标准 dsh-mobile 配对链接', () {
      const raw =
          'https://192.168.0.198:3443/mobile-access/pair'
          '#instance=abc123def&token=-2lhzuFdc23tSfWksOrF';
      final link = PairingLink.parse(raw);
      expect(link.origin, Uri.parse('https://192.168.0.198:3443'));
      expect(link.instanceId, 'abc123def');
      expect(link.token, '-2lhzuFdc23tSfWksOrF');
    });

    test('缺少 token 时抛 pairing_link_invalid', () {
      expect(
        () => PairingLink.parse(
          'https://192.168.0.198:3443/mobile-access/pair#instance=abc',
        ),
        throwsA(
          isA<CompanionException>().having(
            (e) => e.code,
            'code',
            'pairing_link_invalid',
          ),
        ),
      );
    });

    test('非 https 链接被拒绝', () {
      expect(
        () => PairingLink.parse('ftp://example.com'),
        throwsA(isA<CompanionException>()),
      );
    });
  });

  group('证书工具', () {
    test('sha256Hex 稳定且为小写十六进制', () {
      final first = sha256Hex(<int>[1, 2, 3]);
      final second = sha256Hex(<int>[1, 2, 3]);
      expect(first, second);
      expect(first, hasLength(64));
      expect(first, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('derToPem 生成可解析的 PEM 包装', () {
      final pem = derToPem(<int>[1, 2, 3, 4]);
      expect(pem.startsWith('-----BEGIN CERTIFICATE-----'), isTrue);
      expect(pem.trimRight().endsWith('-----END CERTIFICATE-----'), isTrue);
    });
  });
}
