import 'dart:convert';
import 'dart:typed_data';

import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_diagnostic.dart';
import '../../domain/llm/llm_models.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/llm/llm_provider_type.dart';
import '../../domain/llm/multimodal_llm_provider.dart';
import 'gemini_provider.dart';
import 'http_llm_transport.dart';
import 'llm_response_helpers.dart';
import 'llm_transport.dart';
import 'openai_compatible_provider.dart';
import 'vision_probe.dart';

/// 单张图片字节上限（8 MiB）。多模态请求把图片转 base64 后体积约放大
/// 1.37 倍，需要控制请求体大小，避免被网关或服务端拒绝。
const int multimodalMaxImageBytes = 8 * 1024 * 1024;

const List<String> _allowedImageMimeTypes = <String>[
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/bmp',
  'image/heic',
  'image/heif',
];

String? _resolveMimeType(List<int> bytes, String? declared) {
  final normalized = declared?.trim().toLowerCase();
  if (normalized != null &&
      normalized.isNotEmpty &&
      _allowedImageMimeTypes.contains(normalized)) {
    return normalized;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// OpenAI-compatible 视觉模型（image_url content 块）多模态实现。
///
/// 同时实现 [MultimodalLlmProvider]（图片识别）与 [LlmProvider]（纯文本
/// 生成，供连接测试），纯文本请求复用 [OpenAiCompatibleProvider]。
class OpenAiCompatibleMultimodalProvider extends MultimodalLlmProvider {
  OpenAiCompatibleMultimodalProvider(LlmTransport transport)
    : _transport = transport,
      _textProvider = OpenAiCompatibleProvider(transport);

  final LlmTransport _transport;
  final OpenAiCompatibleProvider _textProvider;

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) {
    return _textProvider.generate(
      config: config,
      apiKey: apiKey,
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  @override
  String? validateImageBytes({required List<int> bytes, String? mimeType}) {
    if (bytes.isEmpty) return '图片内容为空，无法识别。';
    if (bytes.length > multimodalMaxImageBytes) {
      return '图片过大，请选择不超过 8 MB 的图片。';
    }
    if (_resolveMimeType(bytes, mimeType) == null) {
      return '不支持的图片格式，请使用 JPG、PNG 或 WebP 图片。';
    }
    return null;
  }

  @override
  Future<LlmDiagnosticReport> diagnose({
    required LlmConnectionConfig config,
    required String apiKey,
    required bool imageProbe,
    LlmCancellationToken? cancellationToken,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    final Object content;
    if (imageProbe) {
      // 标准图探针：图片协议 + 视觉能力（文字与红色方块断言由上层完成）。
      content = <Object?>[
        <String, String>{'type': 'text', 'text': visionProbePrompt},
        <String, Object?>{
          'type': 'image_url',
          'image_url': <String, String>{
            'url': _imageDataUrl(
              MultimodalImageInput(
                bytes: visionProbeBytes,
                mimeType: 'image/png',
                order: 0,
              ),
            ),
          },
        },
      ];
    } else {
      // 基础连接：纯文本最小请求，验证地址/鉴权/模型。
      content = '请简短回复 OK 以确认连接正常。';
    }
    final payload = <String, Object?>{
      'model': config.model,
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': content},
      ],
    };
    return _transport.sendDiagnostic(
      LlmDiagnosticRequest(
        uri: _chatCompletionsEndpoint(config.baseUrl),
        headers: headers,
        body: jsonEncode(payload),
        totalTimeout: config.requestTimeout,
        // 基础请求首字节 15 秒；图片请求（冷启动/排队更长）45 秒。
        timeouts: LlmDiagnosticTimeouts(
          firstByte: imageProbe
              ? const Duration(seconds: 45)
              : const Duration(seconds: 15),
        ),
      ),
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<MultimodalRecognitionResult> recognizeImage({
    required LlmConnectionConfig config,
    required String apiKey,
    required MultimodalImageInput input,
    required String prompt,
    LlmCancellationToken? cancellationToken,
  }) async {
    final startedAt = DateTime.now();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    final payload = <String, Object?>{
      'model': config.model,
      'messages': <Map<String, Object?>>[
        <String, Object?>{
          'role': 'user',
          'content': <Object?>[
            <String, String>{'type': 'text', 'text': prompt},
            <String, Object?>{
              'type': 'image_url',
              'image_url': <String, String>{'url': _imageDataUrl(input)},
            },
          ],
        },
      ],
    };
    final response = await _transport.send(
      LlmHttpRequest(
        uri: _chatCompletionsEndpoint(config.baseUrl),
        headers: headers,
        body: jsonEncode(payload),
        timeout: config.requestTimeout,
      ),
      cancellationToken: cancellationToken,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throwForStatus(response.statusCode, response.body);
    }
    final text = _extractText(response.body);
    return MultimodalRecognitionResult(
      text: text,
      providerId: 'multimodal-openai-compatible',
      modelVersion: config.model,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
  }

  static Uri _chatCompletionsEndpoint(String baseUrl) {
    if (baseUrl.endsWith('/chat/completions')) return Uri.parse(baseUrl);
    return Uri.parse('$baseUrl/chat/completions');
  }

  static String _extractText(String body) {
    final decoded = decodeJsonObject(body);
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        '多模态服务响应缺少 choices',
      );
    }
    final first = choices.first;
    if (first is! Map<String, Object?>) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        '多模态服务响应中的 choice 无效',
      );
    }
    final message = first['message'];
    if (message is! Map<String, Object?>) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        '多模态服务响应缺少 message',
      );
    }
    final content = message['content'];
    final String text;
    if (content is String) {
      text = content;
    } else if (content is List<Object?>) {
      text = content
          .whereType<Map<String, Object?>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
    } else {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        '多模态服务响应缺少 message.content',
      );
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        '多模态服务响应内容为空',
      );
    }
    return trimmed;
  }
}

/// Gemini（inline_data 图片 part）多模态实现。
///
/// 纯文本请求复用 [GeminiProvider]。
class GeminiMultimodalProvider extends MultimodalLlmProvider {
  GeminiMultimodalProvider(LlmTransport transport)
    : _transport = transport,
      _textProvider = GeminiProvider(transport);

  final LlmTransport _transport;
  final GeminiProvider _textProvider;

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) {
    return _textProvider.generate(
      config: config,
      apiKey: apiKey,
      request: request,
      cancellationToken: cancellationToken,
    );
  }

  @override
  String? validateImageBytes({required List<int> bytes, String? mimeType}) {
    if (bytes.isEmpty) return '图片内容为空，无法识别。';
    if (bytes.length > multimodalMaxImageBytes) {
      return '图片过大，请选择不超过 8 MB 的图片。';
    }
    if (_resolveMimeType(bytes, mimeType) == null) {
      return '不支持的图片格式，请使用 JPG、PNG 或 WebP 图片。';
    }
    return null;
  }

  @override
  Future<LlmDiagnosticReport> diagnose({
    required LlmConnectionConfig config,
    required String apiKey,
    required bool imageProbe,
    LlmCancellationToken? cancellationToken,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['x-goog-api-key'] = apiKey.trim();
    }
    final parts = <Object?>[
      <String, String>{
        'text': imageProbe ? visionProbePrompt : '请简短回复 OK 以确认连接正常。',
      },
    ];
    if (imageProbe) {
      // 标准图探针：inline_data 图片 part，视觉断言由上层完成。
      final (mimeType, base64) = _imageInlineData(
        MultimodalImageInput(
          bytes: visionProbeBytes,
          mimeType: 'image/png',
          order: 0,
        ),
      );
      parts.add(<String, Object>{
        'inline_data': <String, String>{'mime_type': mimeType, 'data': base64},
      });
    }
    final payload = <String, Object?>{
      'contents': <Map<String, Object?>>[
        <String, Object?>{'role': 'user', 'parts': parts},
      ],
    };
    return _transport.sendDiagnostic(
      LlmDiagnosticRequest(
        uri: _generateContentEndpoint(config.baseUrl, config.model),
        headers: headers,
        body: jsonEncode(payload),
        totalTimeout: config.requestTimeout,
        timeouts: LlmDiagnosticTimeouts(
          firstByte: imageProbe
              ? const Duration(seconds: 45)
              : const Duration(seconds: 15),
        ),
      ),
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<MultimodalRecognitionResult> recognizeImage({
    required LlmConnectionConfig config,
    required String apiKey,
    required MultimodalImageInput input,
    required String prompt,
    LlmCancellationToken? cancellationToken,
  }) async {
    final startedAt = DateTime.now();
    final (mimeType, base64) = _imageInlineData(input);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['x-goog-api-key'] = apiKey.trim();
    }
    final payload = <String, Object?>{
      'contents': <Map<String, Object?>>[
        <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, String>{'text': prompt},
            <String, Object>{
              'inline_data': <String, String>{
                'mime_type': mimeType,
                'data': base64,
              },
            },
          ],
        },
      ],
    };
    final response = await _transport.send(
      LlmHttpRequest(
        uri: _generateContentEndpoint(config.baseUrl, config.model),
        headers: headers,
        body: jsonEncode(payload),
        timeout: config.requestTimeout,
      ),
      cancellationToken: cancellationToken,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throwForStatus(response.statusCode, response.body);
    }
    final text = _extractText(response.body);
    return MultimodalRecognitionResult(
      text: text,
      providerId: 'multimodal-gemini',
      modelVersion: config.model,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
  }

  static Uri _generateContentEndpoint(String baseUrl, String model) {
    if (baseUrl.endsWith(':generateContent')) return Uri.parse(baseUrl);
    final normalizedModel = model.startsWith('models/')
        ? model.substring('models/'.length)
        : model;
    return Uri.parse(
      '$baseUrl/models/${Uri.encodeComponent(normalizedModel)}:generateContent',
    );
  }

  static String _extractText(String body) {
    final decoded = decodeJsonObject(body);
    final candidates = decoded['candidates'];
    if (candidates is! List<Object?> || candidates.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini 多模态响应缺少 candidates',
      );
    }
    final first = candidates.first;
    if (first is! Map<String, Object?>) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini candidate 无效',
      );
    }
    final content = first['content'];
    if (content is! Map<String, Object?> ||
        content['parts'] is! List<Object?>) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini 多模态响应缺少 content.parts',
      );
    }
    final texts = (content['parts'] as List<Object?>)
        .whereType<Map<String, Object?>>()
        .map((part) => part['text'])
        .whereType<String>()
        .toList(growable: false);
    if (texts.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini 多模态响应没有文本内容',
      );
    }
    return texts.join().trim();
  }
}

/// 把多模态图片输入转成 OpenAI-compatible 的 data URL。
String _imageDataUrl(MultimodalImageInput input) {
  final bytes = input.bytes;
  final mimeType = _resolveMimeType(bytes, input.mimeType) ?? 'image/jpeg';
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// 把多模态图片输入转成 Gemini 的 inline_data（mime_type + base64）。
(String, String) _imageInlineData(MultimodalImageInput input) {
  final bytes = input.bytes;
  final mimeType = _resolveMimeType(bytes, input.mimeType) ?? 'image/jpeg';
  return (mimeType, base64Encode(bytes));
}

/// 多模态 LLM Provider 工厂：按配置类型创建对应实现。
class MultimodalLlmProviderFactory {
  const MultimodalLlmProviderFactory({this.transport = const HttpLlmTransport()});

  final LlmTransport transport;

  MultimodalLlmProvider create(LlmProviderType type) {
    return switch (type) {
      LlmProviderType.openAiCompatible =>
        OpenAiCompatibleMultimodalProvider(transport),
      LlmProviderType.gemini => GeminiMultimodalProvider(transport),
    };
  }
}
