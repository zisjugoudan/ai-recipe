import 'package:flutter/services.dart';

import '../../domain/ocr/ocr_model_package.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import '../../domain/ocr/ocr_models.dart';

class OcrRuntimeProbe {
  const OcrRuntimeProbe({
    required this.runtimeAvailable,
    required this.recognitionSupported,
    this.runtimeVersion,
  });

  final bool runtimeAvailable;
  final bool recognitionSupported;
  final String? runtimeVersion;
}

abstract interface class OcrRuntimeBridge {
  Future<OcrRuntimeProbe> probe();

  Future<void> healthCheck(OcrInstalledModelPackage package);

  Future<OcrDocument> recognize({
    required OcrImageInput input,
    required OcrInstalledModelPackage package,
  });
}

class PlatformOcrRuntimeBridge implements OcrRuntimeBridge {
  PlatformOcrRuntimeBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('ai_recipe/local_ocr');

  final MethodChannel _channel;

  @override
  Future<OcrRuntimeProbe> probe() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('probe');
      final runtimeAvailable = result?['runtimeAvailable'];
      final recognitionSupported = result?['recognitionSupported'];
      if (runtimeAvailable is! bool || recognitionSupported is! bool) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Local OCR runtime probe returned an invalid response.',
        );
      }
      final version = result?['runtimeVersion'];
      return OcrRuntimeProbe(
        runtimeAvailable: runtimeAvailable,
        recognitionSupported: recognitionSupported,
        runtimeVersion: version is String && version.trim().isNotEmpty
            ? version.trim()
            : null,
      );
    } on PlatformException catch (error) {
      throw _providerExceptionFromPlatform(error);
    }
  }

  @override
  Future<void> healthCheck(OcrInstalledModelPackage package) async {
    try {
      await _channel.invokeMethod<void>('healthCheck', _packageArgs(package));
    } on PlatformException catch (error) {
      throw _providerExceptionFromPlatform(error);
    }
  }

  @override
  Future<OcrDocument> recognize({
    required OcrImageInput input,
    required OcrInstalledModelPackage package,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'recognize',
        <String, Object?>{
          ..._packageArgs(package),
          'image': <String, Object?>{
            'remoteUrl': input.remoteUrl,
            'localAssetId': input.localAssetId,
            'mimeType': input.mimeType,
            'width': input.width,
            'height': input.height,
            'order': input.order,
          },
        },
      );
      if (result == null) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidResponse,
          message: 'Local OCR returned an empty response.',
        );
      }
      return _documentFromJson(result);
    } on PlatformException catch (error) {
      throw _providerExceptionFromPlatform(error);
    } on OcrProviderException {
      rethrow;
    } on ArgumentError catch (_) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Local OCR returned invalid text geometry or confidence.',
      );
    }
  }

  static Map<String, Object?> _packageArgs(OcrInstalledModelPackage package) {
    return <String, Object?>{
      'modelDirectory': package.rootDirectory.path,
      'manifest': package.manifest.toJson(),
    };
  }

  static OcrDocument _documentFromJson(Map<String, Object?> json) {
    final providerId = json['providerId'];
    final modelVersion = json['modelVersion'];
    final language = json['language'];
    final blocksValue = json['blocks'];
    if (providerId is! String ||
        modelVersion is! String ||
        language is! String ||
        blocksValue is! List) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Local OCR returned an invalid document response.',
      );
    }
    return OcrDocument(
      providerId: providerId,
      modelVersion: modelVersion,
      language: language,
      durationMs: _optionalInt(json['durationMs']),
      blocks: blocksValue.map((value) {
        if (value is! Map) {
          throw const OcrProviderException(
            kind: OcrProviderErrorKind.invalidResponse,
            message: 'Local OCR returned an invalid text block.',
          );
        }
        return _blockFromJson(Map<String, Object?>.from(value));
      }),
    );
  }

  static OcrTextBlock _blockFromJson(Map<String, Object?> json) {
    final text = json['text'];
    final confidence = json['confidence'];
    final readingOrder = json['readingOrder'];
    if (text is! String || confidence is! num || readingOrder is! int) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Local OCR returned an invalid text block.',
      );
    }
    return OcrTextBlock(
      text: text,
      confidence: confidence.toDouble(),
      readingOrder: readingOrder,
      pageIndex: _optionalInt(json['pageIndex']) ?? 0,
      polygon: _optionalPolygon(json['polygon']),
    );
  }

  static List<OcrPoint>? _optionalPolygon(Object? value) {
    if (value == null) return null;
    if (value is! List || value.length != 4) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: 'Local OCR returned invalid text geometry.',
      );
    }
    return value
        .map((point) {
          if (point is! Map || point['x'] is! num || point['y'] is! num) {
            throw const OcrProviderException(
              kind: OcrProviderErrorKind.invalidResponse,
              message: 'Local OCR returned invalid text geometry.',
            );
          }
          return OcrPoint(
            x: (point['x'] as num).toDouble(),
            y: (point['y'] as num).toDouble(),
          );
        })
        .toList(growable: false);
  }

  static int? _optionalInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    throw const OcrProviderException(
      kind: OcrProviderErrorKind.invalidResponse,
      message: 'Local OCR returned an invalid numeric field.',
    );
  }

  static OcrProviderException _providerExceptionFromPlatform(
    PlatformException error,
  ) {
    final (kind, message) = switch (error.code) {
      'model_not_installed' => (
        OcrProviderErrorKind.modelNotInstalled,
        'Local OCR model package is not installed.',
      ),
      'runtime_unavailable' => (
        OcrProviderErrorKind.unavailable,
        'Local OCR runtime is unavailable.',
      ),
      'inference_not_implemented' => (
        OcrProviderErrorKind.unavailable,
        'Local OCR recognition is not available yet.',
      ),
      'invalid_input' => (
        OcrProviderErrorKind.invalidInput,
        'Local OCR input is invalid.',
      ),
      'invalid_response' => (
        OcrProviderErrorKind.invalidResponse,
        'Local OCR returned an invalid response.',
      ),
      'inference_failed' => (
        OcrProviderErrorKind.inferenceFailed,
        'Local OCR inference failed.',
      ),
      'cancelled' => (
        OcrProviderErrorKind.cancelled,
        'Local OCR operation was cancelled.',
      ),
      _ => (OcrProviderErrorKind.unknown, 'Local OCR is unavailable.'),
    };
    return OcrProviderException(kind: kind, message: message);
  }
}
