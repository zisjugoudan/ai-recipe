import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_provider_exception.dart';
import 'llm_transport.dart';

class HttpLlmTransport implements LlmTransport {
  const HttpLlmTransport();

  @override
  Future<LlmHttpResponse> send(
    LlmHttpRequest request, {
    LlmCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final client = http.Client();
    try {
      final responseFuture = client
          .post(request.uri, headers: request.headers, body: request.body)
          .timeout(request.timeout);
      final http.Response response;
      if (cancellationToken == null) {
        response = await responseFuture;
      } else {
        response = await Future.any<http.Response>(<Future<http.Response>>[
          responseFuture,
          cancellationToken.whenCancelled.then<http.Response>((_) {
            client.close();
            throw const LlmProviderException(
              LlmProviderErrorKind.cancelled,
              '请求已取消',
            );
          }),
        ]);
      }
      return LlmHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(response.bodyBytes),
      );
    } on TimeoutException {
      throw const LlmProviderException(
        LlmProviderErrorKind.timeout,
        '请求超时，请检查 API 地址、网络或超时设置',
      );
    } on SocketException {
      throw const LlmProviderException(
        LlmProviderErrorKind.network,
        '无法连接到 API 地址，请检查地址和网络',
      );
    } on http.ClientException {
      if (cancellationToken?.isCancelled ?? false) {
        throw const LlmProviderException(
          LlmProviderErrorKind.cancelled,
          '请求已取消',
        );
      }
      throw const LlmProviderException(
        LlmProviderErrorKind.network,
        '网络请求失败，请检查 API 地址和网络',
      );
    } finally {
      client.close();
    }
  }
}
