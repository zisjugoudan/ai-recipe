import 'llm_provider_exception.dart';

/// 多模态连接诊断的阶段（BUG-006，ADR-0028）。
///
/// 诊断不再把地址、鉴权、模型、图片协议、首字节、正文结束和解析混成一
/// 次黑盒请求；每次诊断按阶段记录成功/失败/跳过/警告、耗时、HTTP 状态和
/// 下一步建议，UI 逐项展示，不再统一显示"链接超时"。
enum LlmDiagnosticStage {
  /// 配置格式校验（URL、协议、模型、Key、超时必填）。
  configValidation,

  /// URI 组合与地址解析。
  endpointResolution,

  /// TCP/TLS/HTTP 连接建立。
  connectionOpen,

  /// 鉴权（服务明确接受或拒绝凭证）。
  authentication,

  /// 模型存在性/可用性校验。
  modelValidation,

  /// 服务收到请求并返回 HTTP 响应头。
  requestAccepted,

  /// 收到首个响应正文数据。
  firstByte,

  /// 非流式 JSON 完整结束，或流式响应收到终止标记。
  bodyComplete,

  /// 响应符合 Provider Schema。
  responseParse,

  /// 标准诊断图断言（文字与红色方块同时通过）。
  imageAssertion,
}

enum LlmDiagnosticStageResult { passed, failed, skipped, warning }

/// 单个诊断阶段记录。
class LlmDiagnosticStageRecord {
  const LlmDiagnosticStageRecord({
    required this.stage,
    required this.result,
    required this.elapsedMs,
    this.httpStatus,
    this.providerErrorCode,
    this.messageKey,
    this.nextAction,
  });

  final LlmDiagnosticStage stage;
  final LlmDiagnosticStageResult result;
  final int elapsedMs;
  final int? httpStatus;

  /// 截断、脱敏的 Provider 错误码。
  final String? providerErrorCode;

  /// 稳定中文 messageKey（UI 映射，不直接显示服务端正文）。
  final String? messageKey;
  final String? nextAction;
}

/// 一次完整诊断的结果。
///
/// 失败时不抛异常（取消除外）：调用方通过 [succeeded] 与 [failureKind] 判断
/// 结果，并把 [records] 展示给用户，保证阶段信息不丢失。
class LlmDiagnosticReport {
  const LlmDiagnosticReport({
    required this.records,
    required this.totalElapsedMs,
    required this.succeeded,
    this.failureKind,
    this.failureStatus,
    this.responseBody,
  });

  final List<LlmDiagnosticStageRecord> records;
  final int totalElapsedMs;
  final bool succeeded;

  /// 失败时对应的稳定错误分类；[succeeded] 为 true 时为 null。
  final LlmProviderErrorKind? failureKind;
  final int? failureStatus;

  /// 成功且正文完整时的响应正文（供上层解析/断言；失败时通常为 null）。
  final String? responseBody;

  /// 结果中所有 failed 阶段。
  List<LlmDiagnosticStageRecord> get failedRecords =>
      records.where((record) => record.result == LlmDiagnosticStageResult.failed).toList(growable: false);
}

/// 诊断分层时限（BUG-006）。
///
/// 用户配置的"请求超时"是总上限，内部再拆分为连接建立、首字节和正文空闲
/// 三个观察窗口，达到哪个窗口就只报告对应阶段。
class LlmDiagnosticTimeouts {
  const LlmDiagnosticTimeouts({
    this.connect = const Duration(seconds: 8),
    this.firstByte = const Duration(seconds: 45),
    this.bodyIdle = const Duration(seconds: 15),
  });

  /// 连接建立（DNS/TCP/TLS 到响应头）时限，默认 8 秒。
  final Duration connect;

  /// 图片请求首字节时限，默认 45 秒（基础请求可传 15 秒）。
  final Duration firstByte;

  /// 正文空闲时限，默认 15 秒：已开始返回后连续多久没有新数据。
  final Duration bodyIdle;
}

/// 诊断用 HTTP 请求（与 [LlmHttpRequest] 分开，携带分层时限）。
class LlmDiagnosticRequest {
  const LlmDiagnosticRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.totalTimeout,
    this.timeouts = const LlmDiagnosticTimeouts(),
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;

  /// 总时限（用户配置的请求超时，默认 60 秒，上限 120 秒）。
  final Duration totalTimeout;
  final LlmDiagnosticTimeouts timeouts;
}

/// 多模态连接诊断的最终结果（BUG-006，Facade 返回给设置页）。
///
/// 包含分阶段报告；基础连接与图片能力测试还会携带各自的补充结论。
class MultimodalDiagnosticOutcome {
  const MultimodalDiagnosticOutcome({
    required this.report,
    required this.providerId,
    this.modelVersion,
    this.textCapabilityUnconfirmed = false,
    this.imageProbePassed,
    this.observedText,
    this.assertionDetail,
  });

  final LlmDiagnosticReport report;
  final String providerId;
  final String? modelVersion;

  /// 基础连接：视觉专用模型明确拒绝纯文本，但服务与鉴权已通过。
  final bool textCapabilityUnconfirmed;

  /// 图片能力测试：标准图两个断言是否同时通过。
  final bool? imageProbePassed;

  /// 模型返回的响应文本（截断，供真实图片测试展示）。
  final String? observedText;

  /// 标准图断言失败的具体差异描述。
  final String? assertionDetail;
}
