enum ImportSourcePlatform { xiaohongshu, douyin }

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
      _ => throw const ImportTaskInputException(
        ImportTaskErrorCode.unsupportedPlatform,
        '当前只支持小红书和抖音链接。',
      ),
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
    String? resultRecipeId,
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
       resultRecipeId = _optionalText(resultRecipeId) {
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
  final String? resultRecipeId;
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

  ImportTask advance({
    required ImportTaskStage nextStage,
    required double nextProgress,
    required DateTime now,
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
      return this;
    }
    return _copy(
      stage: nextStage,
      progress: nextProgress,
      updatedAt: now,
      localVersion: localVersion + 1,
    );
  }

  ImportTask markNeedsReview({
    required String recipeId,
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
    if (attempt >= maxAttempts) {
      return fail(
        code: ImportTaskErrorCode.interrupted,
        message: '应用退出时任务仍在运行，且已达到最大尝试次数。',
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
}
