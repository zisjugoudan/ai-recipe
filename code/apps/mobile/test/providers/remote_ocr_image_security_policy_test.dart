import 'dart:io';

import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/providers/ocr/remote_ocr_image_security_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = OcrRemoteImageSecurityPolicy();

  group('URL validation', () {
    for (final value in <String>[
      'http://example.com/a.png',
      'https://user:pass@example.com/a.png',
      'https://example.com/a.png#fragment',
      'https://example.com/a.png\nInjected: value',
    ]) {
      test('rejects $value', () {
        expect(() => policy.validateUrl(value), throwsA(_invalidInput));
      });
    }

    test('accepts a normal HTTPS URL', () {
      final uri = policy.validateUrl('https://example.com/path/a.png?size=2');
      expect(uri.scheme, 'https');
      expect(uri.host, 'example.com');
    });
  });

  group('resolved address validation', () {
    for (final value in <String>[
      '127.0.0.1',
      '10.0.0.1',
      '169.254.0.1',
      '192.168.1.1',
      '100.64.0.1',
      '::1',
      'fc00::1',
      'fe80::1',
      '2001:db8::1',
    ]) {
      test('rejects non-public address $value', () {
        expect(
          () => policy.validateResolvedAddresses(<InternetAddress>[
            InternetAddress(value),
          ]),
          throwsA(_invalidInput),
        );
      });
    }

    test('rejects a DNS answer containing public and private addresses', () {
      expect(
        () => policy.validateResolvedAddresses(<InternetAddress>[
          InternetAddress('8.8.8.8'),
          InternetAddress('10.0.0.1'),
        ]),
        throwsA(_invalidInput),
      );
    });

    test('accepts public IPv4 and globally routable IPv6', () {
      expect(
        () => policy.validateResolvedAddresses(<InternetAddress>[
          InternetAddress('8.8.8.8'),
          InternetAddress('1.1.1.1'),
          InternetAddress('2606:4700:4700::1111'),
        ]),
        returnsNormally,
      );
    });
  });
}

final Matcher _invalidInput = isA<OcrProviderException>().having(
  (error) => error.kind,
  'kind',
  OcrProviderErrorKind.invalidInput,
);
