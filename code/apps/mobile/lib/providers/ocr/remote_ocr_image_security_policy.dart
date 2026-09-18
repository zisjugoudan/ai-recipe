import 'dart:io';

import '../../domain/ocr/ocr_provider_exception.dart';

class OcrRemoteImageSecurityPolicy {
  const OcrRemoteImageSecurityPolicy();

  Uri validateUrl(String rawUrl) {
    final normalized = rawUrl.trim();
    if (normalized.isEmpty || normalized.length > 4096) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidInput,
        message: 'Remote OCR image URL is invalid.',
      );
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port <= 0 ||
        uri.port > 65535 ||
        _containsControlCharacter(normalized)) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidInput,
        message: 'Remote OCR images must use a valid HTTPS URL.',
      );
    }
    return uri;
  }

  void validateResolvedAddresses(List<InternetAddress> addresses) {
    if (addresses.isEmpty || addresses.any((item) => !isPublicAddress(item))) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidInput,
        message: 'Remote OCR image host is not publicly routable.',
      );
    }
  }

  bool isPublicAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      return _isPublicIpv4(bytes);
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      return _isPublicIpv6(bytes);
    }
    return false;
  }

  static bool _containsControlCharacter(String value) {
    return value.codeUnits.any((unit) => unit <= 0x1f || unit == 0x7f);
  }

  static bool _isPublicIpv4(List<int> bytes) {
    final a = bytes[0];
    final b = bytes[1];
    final c = bytes[2];
    if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
    if (a == 100 && b >= 64 && b <= 127) return false;
    if (a == 169 && b == 254) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && b == 0 && c == 0) return false;
    if (a == 192 && b == 0 && c == 2) return false;
    if (a == 192 && b == 88 && c == 99) return false;
    if (a == 192 && b == 168) return false;
    if (a == 198 && (b == 18 || b == 19)) return false;
    if (a == 198 && b == 51 && c == 100) return false;
    if (a == 203 && b == 0 && c == 113) return false;
    return true;
  }

  static bool _isPublicIpv6(List<int> bytes) {
    if (bytes.every((value) => value == 0)) return false;
    final isLoopback =
        bytes.take(15).every((value) => value == 0) && bytes[15] == 1;
    if (isLoopback) return false;
    final isIpv4Mapped =
        bytes.take(10).every((value) => value == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (isIpv4Mapped) return _isPublicIpv4(bytes.sublist(12));
    if (bytes.take(12).every((value) => value == 0)) return false;
    if ((bytes[0] & 0xfe) == 0xfc) return false;
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return false;
    if (bytes[0] == 0xff) return false;
    final isDocumentation =
        bytes[0] == 0x20 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x0d &&
        bytes[3] == 0xb8;
    if (isDocumentation) return false;
    final isBenchmark =
        bytes[0] == 0x20 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x02;
    if (isBenchmark) return false;
    return (bytes[0] & 0xe0) == 0x20;
  }
}
