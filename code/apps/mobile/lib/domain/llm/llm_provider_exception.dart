enum LlmProviderErrorKind {
  invalidConfiguration,
  unauthorized,
  notFound,
  rateLimited,
  timeout,
  cancelled,
  server,
  invalidResponse,
  network,
  unknown,

  /// 请求体、图片字段或模型参数与 Provider 协议不兼容（HTTP 400/422）。
  badRequest,

  /// 接口类型错误（HTTP 405）。
  methodNotAllowed,

  /// 请求体过大（HTTP 413）。
  payloadTooLarge,

  /// 图片 MIME 不支持（HTTP 415）。
  unsupportedMediaType,

  /// Provider 或网关明确返回超时（HTTP 408/504），与客户端计时器分开。
  providerGatewayTimeout,

  /// 模型加载中或资源被锁定（HTTP 409/423）。
  modelBusy,

  /// 已建立连接并收到响应头，但超过首字节时限仍未收到正文数据。
  firstByteDeadline,

  /// 已开始返回正文，但连续超过正文空闲时限没有新数据。
  bodyIdleDeadline,

  /// 流式响应没有以 Provider 明确终止标记结束。
  streamNotTerminated,

  /// 标准诊断图断言失败（文字或红色方块未同时满足）。
  imageNotObserved,

  /// 视觉专用模型明确拒绝纯文本请求，但服务与鉴权已通过。
  textCapabilityUnconfirmed,
}

class LlmProviderException implements Exception {
  const LlmProviderException(this.kind, this.message, {this.statusCode});

  final LlmProviderErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
