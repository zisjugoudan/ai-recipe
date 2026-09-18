enum ImportSourcePlatform { xiaohongshu, douyin, web }

enum ImportTaskStatus {
  queued,
  running,
  needsReview,
  completed,
  failed,
  cancelled,
}

enum ImportTaskStage {
  queued,
  fetching,
  extracting,
  ocr,
  transcribing,
  generating,
  review,
  completed,
  failed,
  cancelled,
}

enum ImportTaskErrorCode {
  invalidUrl,
  unsupportedPlatform,
  contentUnavailable,
  authorizationRequired,
  fetchFailed,
  extractionFailed,
  ocrFailed,
  asrFailed,
  llmFailed,
  schemaInvalid,
  networkUnavailable,
  timeout,
  interrupted,
  cancelled,
  storageFailure,
  unknown,
}

class ImportTaskInputException implements Exception {
  const ImportTaskInputException(this.code, this.message);

  final ImportTaskErrorCode code;
  final String message;

  @override
  String toString() => 'ImportTaskInputException(${code.name}): $message';
}

class ImportTaskTransitionException implements Exception {
  const ImportTaskTransitionException(this.message);

  final String message;

  @override
  String toString() => 'ImportTaskTransitionException: $message';
}

class ImportSourceLink {
  const ImportSourceLink({
    required this.sourceUrl,
    required this.normalizedUrl,
    required this.platform,
  });

  final String sourceUrl;
  final String normalizedUrl;
  final ImportSourcePlatform platform;

  static ImportSourceLink parse(String rawUrl) {
    final sourceUrl = rawUrl.trim();
    final uri = Uri.tryParse(sourceUrl);
    if (sourceUrl.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https')) {
      throw const ImportTaskInputException(
        ImportTaskErrorCode.invalidUrl,
        '链接必须是完整的 HTTP 或 HTTPS URL。',
      );
    }

    final host = uri.host.toLowerCase();
    final platform = switch (host) {
      'xiaohongshu.com' ||
      'www.xiaohongshu.com' ||
      'xhslink.com' ||
      'www.xhslink.com' => ImportSourcePlatform.xiaohongshu,
      'douyin.com' ||
      'www.douyin.com' ||
      'v.douyin.com' ||
      'iesdouyin.com' ||
      'www.iesdouyin.com' => ImportSourcePlatform.douyin,
      _
          when host.endsWith('.xiaohongshu.com') ||
              host.endsWith('.xhslink.com') =>
        ImportSourcePlatform.xiaohongshu,
      _ when host.endsWith('.douyin.com') || host.endsWith('.iesdouyin.com') =>
        ImportSourcePlatform.douyin,
      // 其他任意网页统一归为通用 web 平台，由浏览器内核（WebView）抓取。
      _ => ImportSourcePlatform.web,
    };

    final normalizedWithEmptyFragment = uri
        .replace(scheme: uri.scheme.toLowerCase(), host: host, fragment: '')
        .toString();
    final normalizedUrl = normalizedWithEmptyFragment.endsWith('#')
        ? normalizedWithEmptyFragment.substring(
            0,
            normalizedWithEmptyFragment.length - 1,
          )
        : normalizedWithEmptyFragment;
    return ImportSourceLink(
      sourceUrl: sourceUrl,
      normalizedUrl: normalizedUrl,
      platform: platform,
    );
  }
}

class ImportTask {
  ImportTask({
    required String id,
    required String sourceUrl,
    required String normalizedUrl,
    required this.sourcePlatform,
    required this.status,
    required this.stage,
    required this.progress,
    required this.attempt,
    required this.maxAttempts,
    this.errorCode,
    String? errorMessage,
    required this.retryable,
    // 进度详情（IMAGE-002 优化）：运行中实时展示当前操作说明，例如
    // “已获取到正文”“正在识别第 2/3 张图片”“识别为 3 份独立菜谱，
    // 正在生成第 1/3 份草稿”。仅展示用，不影响进度校验。
    String? progressDetail,
    String? resultRecipeId,
    List<String> additionalResultRecipeIds = const <String>[],
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.nextRetryAt,
    required this.localVersion,
    this.deletedAt,
  }) : id = _requireText(id, 'id'),
       sourceUrl = _requireText(sourceUrl, 'sourceUrl'),
       normalizedUrl = _requireText(normalizedUrl, 'normalizedUrl'),
       errorMessage = _optionalText(errorMessage),
       progressDetail = _optionalText(progressDetail),
       resultRecipeId = _optionalText(resultRecipeId),
       additionalResultRecipeIds =
           _normalizeAdditionalIds(resultRecipeId, additionalResultRecipeIds) {
    _validate();
  }

  factory ImportTask.queued({
    required String id,
    required ImportSourceLink source,
    required DateTime now,
    int maxAttempts = 3,
  }) {
    return ImportTask(
      id: id,
      sourceUrl: source.sourceUrl,
      normalizedUrl: source.normalizedUrl,
      sourcePlatform: source.platform,
      status: ImportTaskStatus.queued,
      stage: ImportTaskStage.queued,
      progress: 0,
      attempt: 1,
      maxAttempts: maxAttempts,
      retryable: false,
      createdAt: now,
      updatedAt: now,
      localVersion: 1,
    );
  }

  final String id;
  final String sourceUrl;
  final String normalizedUrl;
  final ImportSourcePlatform sourcePlatform;
  final ImportTaskStatus status;
  final ImportTaskStage stage;
  final double progress;
  final int attempt;
  final int maxAttempts;
  final ImportTaskErrorCode? errorCode;
  final String? errorMessage;
  final bool retryable;

  /// 进度详情：运行中实时展示的当前操作说明（仅展示，不影响进度校验）。
  final String? progressDetail;

  final String? resultRecipeId;

  /// 附加草稿 ID（多图“每张图独立菜谱”一次导入产出多个草稿，IMAGE-002）。
  final List<String> additionalResultRecipeIds;

  /// 任务关联的全部草稿 ID（主草稿 + 附加草稿）。
  List<String> get allResultRecipeIds =>
      <String>[if (resultRecipeId != null) resultRecipeId!, ...additionalResultRecipeIds];
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? nextRetryAt;
  final int localVersion;
  final DateTime? deletedAt;

  bool get isTerminal =>
      status == ImportTaskStatus.completed ||
      status == ImportTaskStatus.cancelled;

  bool get canRetry =>
      status == ImportTaskStatus.failed && retryable && attempt < maxAttempts;

  ImportTask start(DateTime now) {
    _requireStatus(ImportTaskStatus.queued, '只有排队任务可以开始。');
    _requireCurrentTime(now);
    return _copy(
      status: ImportTaskStatus.running,
      stage: ImportTaskStage.fetching,
      updatedAt: now,
      startedAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask startWithFallback(DateTime now) {
    // 允许三类任务用内容运行：排队任务（快速导入"拍照选图/剪贴板"新建的
    // 占位任务，IMPORT-009）与失败/已取消任务（人工降级输入）。
    // 排队任务直接进入 extracting（跳过 fetching，不抓取公开链接），
    // 图片/文本内容由调用方通过 runImportWithLocalImage / runImportWithText 提供。
    if (status != ImportTaskStatus.queued &&
        status != ImportTaskStatus.failed &&
        status != ImportTaskStatus.cancelled) {
      throw const ImportTaskTransitionException(
        '只有排队、失败或已取消的任务可以使用内容运行。',
      );
    }
    _requireCurrentTime(now);
    return _copy(
      status: ImportTaskStatus.running,
      stage: ImportTaskStage.extracting,
      progress: 0.25,
      errorCode: null,
      errorMessage: null,
      retryable: false,
      resultRecipeId: null,
      progressDetail: null,
      updatedAt: now,
      startedAt: now,
      completedAt: null,
      cancelledAt: null,
      nextRetryAt: null,
      localVersion: localVersion + 1,
    );
  }

  ImportTask advance({
    required ImportTaskStage nextStage,
    required double nextProgress,
    required DateTime now,
    // 进度详情（可选）：更新当前操作说明；不传则保留已有详情。
    String? progressDetail,
  }) {
    _requireStatus(ImportTaskStatus.running, '只有运行中的任务可以推进阶段。');
    _requireCurrentTime(now);
    if (!_processingStages.contains(nextStage)) {
      throw const ImportTaskTransitionException('目标阶段不是可运行的处理阶段。');
    }
    if (_stageRank(nextStage) < _stageRank(stage)) {
      throw const ImportTaskTransitionException('处理阶段不能倒退。');
    }
    if (nextProgress < progress) {
      throw const ImportTaskTransitionException('任务进度不能倒退。');
    }
    if (nextProgress < 0 || nextProgress > 1) {
      throw const ImportTaskTransitionException('任务进度必须在 0 到 1 之间。');
    }
    if (nextStage == stage && nextProgress == progress) {
      // 进度与阶段不变：仅当详情有变化时才生成新版本，否则原样返回。
      final detailChanged = progressDetail != null &&
          progressDetail != this.progressDetail;
      if (!detailChanged) return this;
      return _copy(
        progressDetail: progressDetail,
        updatedAt: now,
        localVersion: localVersion + 1,
      );
    }
    return _copy(
      stage: nextStage,
      progress: nextProgress,
      progressDetail: progressDetail,
      updatedAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask markNeedsReview({
    required String recipeId,
    List<String> additionalRecipeIds = const <String>[],
    required DateTime now,
  }) {
    _requireStatus(ImportTaskStatus.running, '只有运行中的任务可以进入待确认状态。');
    _requireCurrentTime(now);
    if (stage != ImportTaskStage.generating) {
      throw const ImportTaskTransitionException('完成结构化生成后才能进入待确认状态。');
    }
    return _copy(
      status: ImportTaskStatus.needsReview,
      stage: ImportTaskStage.review,
      progress: 1,
      resultRecipeId: _requireText(recipeId, 'recipeId'),
      additionalResultRecipeIds: additionalRecipeIds,
      updatedAt: now,
      localVersion: localVersion + 1,
    );
  }

  /// 待确认任务更换关联草稿（用于“重新生成”）。
  ///
  /// 只允许在 `needsReview` 状态调用：任务阶段保持 review、进度保持 1，
  /// 仅更新 resultRecipeId、附加草稿、updatedAt 和 localVersion。
  ImportTask reassignResultRecipe({
    required String recipeId,
    List<String> additionalRecipeIds = const <String>[],
    required DateTime now,
  }) {
    _requireStatus(ImportTaskStatus.needsReview, '只有待确认任务可以更换草稿。');
    _requireCurrentTime(now);
    return _copy(
      resultRecipeId: _requireText(recipeId, 'recipeId'),
      additionalResultRecipeIds: additionalRecipeIds,
      updatedAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask complete(DateTime now) {
    _requireStatus(ImportTaskStatus.needsReview, '只有待确认任务可以完成。');
    _requireCurrentTime(now);
    return _copy(
      status: ImportTaskStatus.completed,
      stage: ImportTaskStage.completed,
      progress: 1,
      updatedAt: now,
      completedAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask fail({
    required ImportTaskErrorCode code,
    String? message,
    required bool canRetry,
    DateTime? nextRetryAt,
    required DateTime now,
  }) {
    if (isTerminal) {
      throw const ImportTaskTransitionException('终态任务不能标记失败。');
    }
    _requireCurrentTime(now);
    final effectiveRetryable = canRetry && attempt < maxAttempts;
    final retryAt = effectiveRetryable ? nextRetryAt : null;
    if (retryAt != null && retryAt.isBefore(now)) {
      throw const ImportTaskTransitionException('下次重试时间不能早于当前时间。');
    }
    return _copy(
      status: ImportTaskStatus.failed,
      stage: ImportTaskStage.failed,
      errorCode: code,
      errorMessage: _optionalText(message),
      retryable: effectiveRetryable,
      resultRecipeId: null,
      progressDetail: null,
      completedAt: null,
      cancelledAt: null,
      nextRetryAt: retryAt,
      updatedAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask cancel(DateTime now) {
    if (status == ImportTaskStatus.cancelled) {
      return this;
    }
    if (status == ImportTaskStatus.completed) {
      throw const ImportTaskTransitionException('已完成任务不能取消。');
    }
    _requireCurrentTime(now);
    return _copy(
      status: ImportTaskStatus.cancelled,
      stage: ImportTaskStage.cancelled,
      errorCode: null,
      errorMessage: null,
      retryable: false,
      resultRecipeId: null,
      progressDetail: null,
      nextRetryAt: null,
      updatedAt: now,
      cancelledAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask retry(DateTime now) {
    if (!canRetry) {
      throw const ImportTaskTransitionException('任务当前不可重试或已达到最大尝试次数。');
    }
    _requireCurrentTime(now);
    if (nextRetryAt != null && now.isBefore(nextRetryAt!)) {
      throw const ImportTaskTransitionException('尚未到达允许重试的时间。');
    }
    return _copy(
      status: ImportTaskStatus.queued,
      stage: ImportTaskStage.queued,
      progress: 0,
      attempt: attempt + 1,
      errorCode: null,
      errorMessage: null,
      retryable: false,
      resultRecipeId: null,
      progressDetail: null,
      startedAt: null,
      completedAt: null,
      cancelledAt: null,
      nextRetryAt: null,
      updatedAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask recoverAfterRestart(DateTime now) {
    if (status != ImportTaskStatus.running) {
      return this;
    }
    _requireCurrentTime(now);
    if (stage != ImportTaskStage.fetching) {
      return fail(
        code: ImportTaskErrorCode.interrupted,
        message: '人工降级处理已中断，请重新选择输入方式。',
        canRetry: false,
        now: now,
      );
    }
    if (attempt >= maxAttempts) {
      return fail(
        code: ImportTaskErrorCode.interrupted,
        message: '公开内容导入已中断，且已达到最大尝试次数。',
        canRetry: false,
        now: now,
      );
    }
    return _copy(
      status: ImportTaskStatus.queued,
      stage: ImportTaskStage.queued,
      progress: 0,
      attempt: attempt + 1,
      errorCode: null,
      errorMessage: null,
      retryable: false,
      resultRecipeId: null,
      progressDetail: null,
      startedAt: null,
      completedAt: null,
      cancelledAt: null,
      nextRetryAt: null,
      updatedAt: now,
      localVersion: localVersion + 1,
    );
  }

  void _validate() {
    if (progress < 0 || progress > 1) {
      throw ArgumentError.value(progress, 'progress', '必须在 0 到 1 之间');
    }
    if (attempt < 1 || maxAttempts < 1 || attempt > maxAttempts) {
      throw ArgumentError('attempt 必须在 1 到 maxAttempts 之间。');
    }
    if (localVersion < 1) {
      throw ArgumentError.value(localVersion, 'localVersion', '必须大于等于 1');
    }
    if (updatedAt.isBefore(createdAt)) {
      throw ArgumentError('updatedAt 不能早于 createdAt。');
    }
    for (final timestamp in <DateTime?>[
      startedAt,
      completedAt,
      cancelledAt,
      nextRetryAt,
      deletedAt,
    ]) {
      if (timestamp != null && timestamp.isBefore(createdAt)) {
        throw ArgumentError('任务时间字段不能早于 createdAt。');
      }
    }
    final expectedStage = switch (status) {
      ImportTaskStatus.queued => stage == ImportTaskStage.queued,
      ImportTaskStatus.running => _processingStages.contains(stage),
      ImportTaskStatus.needsReview => stage == ImportTaskStage.review,
      ImportTaskStatus.completed => stage == ImportTaskStage.completed,
      ImportTaskStatus.failed => stage == ImportTaskStage.failed,
      ImportTaskStatus.cancelled => stage == ImportTaskStage.cancelled,
    };
    if (!expectedStage) {
      throw ArgumentError('status 与 stage 不匹配。');
    }
    if (status == ImportTaskStatus.failed) {
      if (errorCode == null) {
        throw ArgumentError('失败任务必须包含 errorCode。');
      }
    } else if (errorCode != null || errorMessage != null) {
      throw ArgumentError('非失败任务不能保留错误信息。');
    }
    if (retryable && status != ImportTaskStatus.failed) {
      throw ArgumentError('只有失败任务可以标记为可重试。');
    }
    if (nextRetryAt != null && !retryable) {
      throw ArgumentError('只有可重试任务可以设置 nextRetryAt。');
    }
    final requiresRecipe =
        status == ImportTaskStatus.needsReview ||
        status == ImportTaskStatus.completed;
    if (requiresRecipe && resultRecipeId == null) {
      throw ArgumentError('待确认和已完成任务必须包含 resultRecipeId。');
    }
    if (!requiresRecipe && resultRecipeId != null) {
      throw ArgumentError('当前状态不能包含 resultRecipeId。');
    }
    if ((status == ImportTaskStatus.completed) != (completedAt != null)) {
      throw ArgumentError('completedAt 只允许用于已完成任务。');
    }
    if ((status == ImportTaskStatus.cancelled) != (cancelledAt != null)) {
      throw ArgumentError('cancelledAt 只允许用于已取消任务。');
    }
  }

  ImportTask _copy({
    ImportTaskStatus? status,
    ImportTaskStage? stage,
    double? progress,
    int? attempt,
    Object? errorCode = _notProvided,
    Object? errorMessage = _notProvided,
    bool? retryable,
    Object? resultRecipeId = _notProvided,
    Object? additionalResultRecipeIds = _notProvided,
    Object? progressDetail = _notProvided,
    DateTime? updatedAt,
    Object? startedAt = _notProvided,
    Object? completedAt = _notProvided,
    Object? cancelledAt = _notProvided,
    Object? nextRetryAt = _notProvided,
    int? localVersion,
  }) {
    return ImportTask(
      id: id,
      sourceUrl: sourceUrl,
      normalizedUrl: normalizedUrl,
      sourcePlatform: sourcePlatform,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      attempt: attempt ?? this.attempt,
      maxAttempts: maxAttempts,
      errorCode: identical(errorCode, _notProvided)
          ? this.errorCode
          : errorCode as ImportTaskErrorCode?,
      errorMessage: identical(errorMessage, _notProvided)
          ? this.errorMessage
          : errorMessage as String?,
      retryable: retryable ?? this.retryable,
      resultRecipeId: identical(resultRecipeId, _notProvided)
          ? this.resultRecipeId
          : resultRecipeId as String?,
      additionalResultRecipeIds: identical(
        additionalResultRecipeIds,
        _notProvided,
      )
          ? this.additionalResultRecipeIds
          : additionalResultRecipeIds as List<String>,
      progressDetail: identical(progressDetail, _notProvided)
          ? this.progressDetail
          : progressDetail as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: identical(startedAt, _notProvided)
          ? this.startedAt
          : startedAt as DateTime?,
      completedAt: identical(completedAt, _notProvided)
          ? this.completedAt
          : completedAt as DateTime?,
      cancelledAt: identical(cancelledAt, _notProvided)
          ? this.cancelledAt
          : cancelledAt as DateTime?,
      nextRetryAt: identical(nextRetryAt, _notProvided)
          ? this.nextRetryAt
          : nextRetryAt as DateTime?,
      localVersion: localVersion ?? this.localVersion,
      deletedAt: deletedAt,
    );
  }

  void _requireStatus(ImportTaskStatus expected, String message) {
    if (status != expected) {
      throw ImportTaskTransitionException(message);
    }
  }

  void _requireCurrentTime(DateTime now) {
    if (now.isBefore(updatedAt)) {
      throw const ImportTaskTransitionException('状态更新时间不能倒退。');
    }
  }

  static const Object _notProvided = Object();

  static int _stageRank(ImportTaskStage value) => switch (value) {
    ImportTaskStage.fetching => 1,
    ImportTaskStage.extracting => 2,
    ImportTaskStage.ocr => 3,
    ImportTaskStage.transcribing => 4,
    ImportTaskStage.generating => 5,
    _ => -1,
  };

  static const Set<ImportTaskStage> _processingStages = <ImportTaskStage>{
    ImportTaskStage.fetching,
    ImportTaskStage.extracting,
    ImportTaskStage.ocr,
    ImportTaskStage.transcribing,
    ImportTaskStage.generating,
  };

  static String _requireText(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, field, '不能为空');
    }
    return trimmed;
  }

  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 规范化附加草稿 ID：去空白、去重、排除与主草稿相同的 ID。
  static List<String> _normalizeAdditionalIds(
    String? primary,
    List<String> additional,
  ) {
    final result = <String>[];
    for (final id in additional) {
      final trimmed = id.trim();
      if (trimmed.isEmpty || trimmed == primary) continue;
      if (result.contains(trimmed)) continue;
      result.add(trimmed);
    }
    return List<String>.unmodifiable(result);
  }
}
