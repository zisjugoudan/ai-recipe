import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
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
    // 诊断（IMAGE-002）：记录一次 LLM HTTP 请求的总耗时与响应大小，
    // 用于区分“服务端生成慢”还是“网络传输慢”。
    final startedAt = DateTime.now();
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
      debugPrint(
        '[AIRecipe][Http] LLM 请求耗时=${DateTime.now().difference(startedAt).inMilliseconds}ms '
        'status=${response.statusCode} bodyBytes=${response.bodyBytes.length}',
      );
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

  @override
  Future<LlmDiagnosticReport> sendDiagnostic(
    LlmDiagnosticRequest request, {
    LlmCancellationToken? cancellationToken,
  }) async {
    final startedAt = DateTime.now();
    final records = <LlmDiagnosticStageRecord>[];
    int elapsedMs() => DateTime.now().difference(startedAt).inMilliseconds;

    void add(
      LlmDiagnosticStage stage,
      LlmDiagnosticStageResult result, {
      int? httpStatus,
      String? messageKey,
      String? nextAction,
    }) {
      records.add(
        LlmDiagnosticStageRecord(
          stage: stage,
          result: result,
          elapsedMs: elapsedMs(),
          httpStatus: httpStatus,
          messageKey: messageKey,
          nextAction: nextAction,
        ),
      );
    }

    LlmDiagnosticReport report({
      required bool succeeded,
      required LlmProviderErrorKind? failureKind,
      int? failureStatus,
      String? responseBody,
    }) => LlmDiagnosticReport(
      records: List<LlmDiagnosticStageRecord>.unmodifiable(records),
      totalElapsedMs: elapsedMs(),
      succeeded: succeeded,
      failureKind: failureKind,
      failureStatus: failureStatus,
      responseBody: responseBody,
    );

    // ---- config_validation：URL 协议合法性（不发网络请求）----
    final scheme = request.uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      add(
        LlmDiagnosticStage.configValidation,
        LlmDiagnosticStageResult.failed,
        messageKey: 'invalid_config',
        nextAction: '修正地址或协议',
      );
      return report(
        succeeded: false,
        failureKind: LlmProviderErrorKind.invalidConfiguration,
      );
    }
    add(LlmDiagnosticStage.configValidation, LlmDiagnosticStageResult.passed);
    // URI 已可解析（endpoint_resolution 通过；DNS 精确指标依赖平台能力）。
    add(LlmDiagnosticStage.endpointResolution, LlmDiagnosticStageResult.passed);
    add(LlmDiagnosticStage.connectionOpen, LlmDiagnosticStageResult.skipped);

    final totalDeadline = startedAt.add(request.totalTimeout);
    Duration remaining() {
      final left = totalDeadline.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }

    final client = http.Client();
    try {
      final httpRequest = http.Request('POST', request.uri)
        ..headers.addAll(request.headers)
        ..body = request.body;

      // ---- connection_open + request_accepted：连接建立到响应头 ----
      final connectWait = remaining() < request.timeouts.connect
          ? remaining()
          : request.timeouts.connect;
      if (connectWait == Duration.zero) {
        add(
          LlmDiagnosticStage.requestAccepted,
          LlmDiagnosticStageResult.failed,
          messageKey: 'first_byte_deadline',
          nextAction: '服务未在总时限内返回，检查服务状态或调大超时',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.timeout,
        );
      }
      final sendFuture = Future.any<http.StreamedResponse>([
        client.send(httpRequest),
        if (cancellationToken != null)
          cancellationToken.whenCancelled.then<http.StreamedResponse>((_) {
            throw const LlmProviderException(
              LlmProviderErrorKind.cancelled,
              '请求已取消',
            );
          }),
      ]).timeout(connectWait);

      final http.StreamedResponse response;
      try {
        response = await sendFuture;
      } on LlmProviderException {
        rethrow;
      } on TimeoutException {
        if (cancellationToken?.isCancelled ?? false) {
          throw const LlmProviderException(
            LlmProviderErrorKind.cancelled,
            '请求已取消',
          );
        }
        add(
          LlmDiagnosticStage.connectionOpen,
          LlmDiagnosticStageResult.failed,
          messageKey: 'network_unreachable',
          nextAction: '检查地址、网络或服务状态',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.network,
        );
      } on SocketException {
        add(
          LlmDiagnosticStage.connectionOpen,
          LlmDiagnosticStageResult.failed,
          messageKey: 'network_unreachable',
          nextAction: '检查地址、网络或端口',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.network,
        );
      } on HandshakeException {
        add(
          LlmDiagnosticStage.connectionOpen,
          LlmDiagnosticStageResult.failed,
          messageKey: 'network_unreachable',
          nextAction: '检查证书或改用正确的 https 地址',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.network,
        );
      } on http.ClientException {
        if (cancellationToken?.isCancelled ?? false) {
          throw const LlmProviderException(
            LlmProviderErrorKind.cancelled,
            '请求已取消',
          );
        }
        add(
          LlmDiagnosticStage.connectionOpen,
          LlmDiagnosticStageResult.failed,
          messageKey: 'network_unreachable',
          nextAction: '检查地址与网络',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.network,
        );
      }

      add(
        LlmDiagnosticStage.connectionOpen,
        LlmDiagnosticStageResult.passed,
        httpStatus: response.statusCode,
      );
      add(
        LlmDiagnosticStage.requestAccepted,
        LlmDiagnosticStageResult.passed,
        httpStatus: response.statusCode,
      );

      // ---- authentication / model_validation：按 HTTP 状态分类 ----
      final statusKind = _statusError(response.statusCode);
      if (statusKind != null) {
        final (stage, kind, messageKey, nextAction) = statusKind;
        add(
          stage,
          LlmDiagnosticStageResult.failed,
          httpStatus: response.statusCode,
          messageKey: messageKey,
          nextAction: nextAction,
        );
        return report(
          succeeded: false,
          failureKind: kind,
          failureStatus: response.statusCode,
        );
      }

      // ---- first_byte：收到首个正文数据 ----
      final iterator = StreamIterator(response.stream);
      final firstByteWait = remaining() < request.timeouts.firstByte
          ? remaining()
          : request.timeouts.firstByte;
      if (firstByteWait == Duration.zero) {
        await iterator.cancel();
        add(
          LlmDiagnosticStage.firstByte,
          LlmDiagnosticStageResult.failed,
          httpStatus: response.statusCode,
          messageKey: 'first_byte_deadline',
          nextAction: '调大总时限或检查服务状态',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.firstByteDeadline,
          failureStatus: response.statusCode,
        );
      }
      final bool hasFirst;
      try {
        hasFirst = await iterator
            .moveNext()
            .timeout(firstByteWait);
      } on TimeoutException {
        await iterator.cancel();
        if (cancellationToken?.isCancelled ?? false) {
          throw const LlmProviderException(
            LlmProviderErrorKind.cancelled,
            '请求已取消',
          );
        }
        add(
          LlmDiagnosticStage.firstByte,
          LlmDiagnosticStageResult.failed,
          httpStatus: response.statusCode,
          messageKey: 'first_byte_deadline',
          nextAction: '服务已接收请求但未开始返回，检查排队、冷启动或模型能力',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.firstByteDeadline,
          failureStatus: response.statusCode,
        );
      }
      if (!hasFirst) {
        await iterator.cancel();
        add(
          LlmDiagnosticStage.firstByte,
          LlmDiagnosticStageResult.failed,
          httpStatus: response.statusCode,
          messageKey: 'invalid_response',
          nextAction: '服务返回了空正文',
        );
        return report(
          succeeded: false,
          failureKind: LlmProviderErrorKind.invalidResponse,
          failureStatus: response.statusCode,
        );
      }
      add(
        LlmDiagnosticStage.firstByte,
        LlmDiagnosticStageResult.passed,
        httpStatus: response.statusCode,
      );

      // ---- body_complete：正文连续读取，空闲超时分类为正文卡住 ----
      final bytes = BytesBuilder();
      bytes.add(iterator.current);
      while (true) {
        final bodyIdleWait = remaining() < request.timeouts.bodyIdle
            ? remaining()
            : request.timeouts.bodyIdle;
        if (bodyIdleWait == Duration.zero) {
          await iterator.cancel();
          add(
            LlmDiagnosticStage.bodyComplete,
            LlmDiagnosticStageResult.failed,
            httpStatus: response.statusCode,
            messageKey: 'body_idle_deadline',
            nextAction: '响应中断或流未结束，检查流式兼容性',
          );
          return report(
            succeeded: false,
            failureKind: LlmProviderErrorKind.bodyIdleDeadline,
            failureStatus: response.statusCode,
          );
        }
        final bool hasNext;
        try {
          hasNext = await iterator.moveNext().timeout(bodyIdleWait);
        } on TimeoutException {
          await iterator.cancel();
          if (cancellationToken?.isCancelled ?? false) {
            throw const LlmProviderException(
              LlmProviderErrorKind.cancelled,
              '请求已取消',
            );
          }
          add(
            LlmDiagnosticStage.bodyComplete,
            LlmDiagnosticStageResult.failed,
            httpStatus: response.statusCode,
            messageKey: 'body_idle_deadline',
            nextAction: '正文返回后长时间无新数据，响应可能中断或流未结束',
          );
          return report(
            succeeded: false,
            failureKind: LlmProviderErrorKind.bodyIdleDeadline,
            failureStatus: response.statusCode,
          );
        }
        if (!hasNext) break;
        bytes.add(iterator.current);
      }
      add(
        LlmDiagnosticStage.bodyComplete,
        LlmDiagnosticStageResult.passed,
        httpStatus: response.statusCode,
      );

      // response_parse 与 image_assertion 由调用方（Facade/Provider）完成，
      // Transport 只保证正文完整取得后把 body 提供给上层。
      return report(
        succeeded: true,
        failureKind: null,
        responseBody: utf8.decode(bytes.toBytes(), allowMalformed: true),
      );
    } finally {
      client.close();
    }
  }

  /// 按 HTTP 状态码返回诊断失败阶段、稳定错误分类、messageKey 与下一步建议。
  static (LlmDiagnosticStage, LlmProviderErrorKind, String, String)?
  _statusError(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return (
        LlmDiagnosticStage.authentication,
        LlmProviderErrorKind.unauthorized,
        'unauthorized',
        '检查 API Key 与模型权限',
      );
    }
    if (statusCode == 404) {
      return (
        LlmDiagnosticStage.modelValidation,
        LlmProviderErrorKind.notFound,
        'not_found',
        '检查 API 地址、路径与模型名称',
      );
    }
    if (statusCode == 405) {
      return (
        LlmDiagnosticStage.modelValidation,
        LlmProviderErrorKind.methodNotAllowed,
        'method_not_allowed',
        '检查是否填到了网页或错误路径',
      );
    }
    if (statusCode == 408 || statusCode == 504) {
      return (
        LlmDiagnosticStage.requestAccepted,
        LlmProviderErrorKind.providerGatewayTimeout,
        'provider_gateway_timeout',
        '查询服务状态或稍后重试',
      );
    }
    if (statusCode == 409 || statusCode == 423) {
      return (
        LlmDiagnosticStage.modelValidation,
        LlmProviderErrorKind.modelBusy,
        'model_busy',
        '等待模型加载完成后重试',
      );
    }
    if (statusCode == 413) {
      return (
        LlmDiagnosticStage.requestAccepted,
        LlmProviderErrorKind.payloadTooLarge,
        'payload_too_large',
        '压缩图片或减少请求内容',
      );
    }
    if (statusCode == 415) {
      return (
        LlmDiagnosticStage.requestAccepted,
        LlmProviderErrorKind.unsupportedMediaType,
        'unsupported_media_type',
        '转为 JPG、PNG 或 WebP',
      );
    }
    if (statusCode == 429) {
      return (
        LlmDiagnosticStage.authentication,
        LlmProviderErrorKind.rateLimited,
        'rate_limited',
        '等待限流恢复或检查配额',
      );
    }
    if (statusCode == 400 || statusCode == 422) {
      return (
        LlmDiagnosticStage.requestAccepted,
        LlmProviderErrorKind.badRequest,
        'request_incompatible',
        '核对图片字段、模型能力与协议',
      );
    }
    if (statusCode >= 500) {
      return (
        LlmDiagnosticStage.requestAccepted,
        LlmProviderErrorKind.server,
        'server_error',
        '稍后重试或切换备用服务',
      );
    }
    return null;
  }
}
