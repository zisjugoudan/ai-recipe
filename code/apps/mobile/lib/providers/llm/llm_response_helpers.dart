import 'dart:convert';

import '../../domain/llm/llm_provider_exception.dart';

Map<String, Object?> decodeJsonObject(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) throw const FormatException();
    return decoded;
  } on FormatException {
    throw const LlmProviderException(
      LlmProviderErrorKind.invalidResponse,
      '接口返回的不是有效 JSON 对象',
    );
  }
}

Never throwForStatus(int statusCode, String body) {
  var serverMessage = '';
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) {
      final error = decoded['error'];
      if (error is Map<String, Object?> && error['message'] is String) {
        serverMessage = (error['message'] as String).trim();
      } else if (error is String) {
        serverMessage = error.trim();
      }
    }
  } on FormatException {
    // Never expose an arbitrary response body in errors or logs.
  }

  final suffix = serverMessage.isEmpty ? '' : '：$serverMessage';
  if (statusCode == 401 || statusCode == 403) {
    throw LlmProviderException(
      LlmProviderErrorKind.unauthorized,
      '鉴权失败，请检查 API Key$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 404) {
    throw LlmProviderException(
      LlmProviderErrorKind.notFound,
      '接口或模型不存在，请检查地址、协议和模型$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 405) {
    throw LlmProviderException(
      LlmProviderErrorKind.methodNotAllowed,
      '接口类型错误，请检查是否填到了网页或错误的 API 路径$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 408 || statusCode == 504) {
    throw LlmProviderException(
      LlmProviderErrorKind.providerGatewayTimeout,
      '服务端或网关响应超时，请稍后重试或检查服务状态$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 409 || statusCode == 423) {
    throw LlmProviderException(
      LlmProviderErrorKind.modelBusy,
      '模型正在加载或资源被占用，请稍后重试$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 413) {
    throw LlmProviderException(
      LlmProviderErrorKind.payloadTooLarge,
      '请求体过大，请压缩图片或减少内容$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 415) {
    throw LlmProviderException(
      LlmProviderErrorKind.unsupportedMediaType,
      '图片类型不支持，请使用 JPG、PNG 或 WebP$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 429) {
    throw LlmProviderException(
      LlmProviderErrorKind.rateLimited,
      '请求过于频繁或额度不足，请稍后重试$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode == 400 || statusCode == 422) {
    throw LlmProviderException(
      LlmProviderErrorKind.badRequest,
      '请求参数与 Provider 协议不兼容，请核对图片字段、模型能力和地址$suffix',
      statusCode: statusCode,
    );
  }
  if (statusCode >= 500) {
    throw LlmProviderException(
      LlmProviderErrorKind.server,
      'LLM 服务暂时不可用$suffix',
      statusCode: statusCode,
    );
  }
  throw LlmProviderException(
    LlmProviderErrorKind.unknown,
    'LLM 请求失败（HTTP $statusCode）$suffix',
    statusCode: statusCode,
  );
}
