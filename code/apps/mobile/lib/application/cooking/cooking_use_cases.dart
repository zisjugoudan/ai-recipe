import '../../domain/cooking/cooking_session.dart';
import '../recipe/recipe_library_use_cases.dart';

typedef CookingIdGenerator = String Function();
typedef CookingClock = DateTime Function();

abstract class CookingException implements Exception {
  const CookingException();
}

class CookingSessionNotFoundException extends CookingException {
  const CookingSessionNotFoundException(this.id);

  final String id;
}

class CookingTimerNotFoundException extends CookingException {
  const CookingTimerNotFoundException(this.id);

  final String id;
}

class CookingValidationException extends CookingException {
  const CookingValidationException(this.message);

  final String message;
}

class CookingStorageException extends CookingException {
  const CookingStorageException();
}

class CookingUseCases {
  const CookingUseCases({
    required CookingRepository repository,
    required RecipeLibraryUseCases recipes,
    required CookingIdGenerator idGenerator,
    required CookingClock clock,
  }) : _repository = repository,
       _recipes = recipes,
       _idGenerator = idGenerator,
       _clock = clock;

  final CookingRepository _repository;
  final RecipeLibraryUseCases _recipes;
  final CookingIdGenerator _idGenerator;
  final CookingClock _clock;

  Future<CookingSession> startOrResume(String recipeId) async {
    final recipe = await _recipes.getRecipe(recipeId);
    try {
      final existing = await _repository.getActiveSessionForRecipe(recipe.id);
      if (existing != null) return _projectExpiredTimers(existing);
      final now = _clock();
      final session = CookingSession(
        id: _nextId(),
        recipeId: recipe.id,
        currentStepIndex: 0,
        status: CookingSessionStatus.active,
        startedAt: now,
        updatedAt: now,
      );
      await _repository.upsertSession(session);
      return session;
    } catch (error) {
      if (error is CookingException) rethrow;
      throw const CookingStorageException();
    }
  }

  Future<CookingSession> getSession(String sessionId) async {
    try {
      final session = await _repository.getSessionById(_requireId(sessionId));
      if (session == null) throw CookingSessionNotFoundException(sessionId);
      return _projectExpiredTimers(session);
    } on CookingException {
      rethrow;
    } catch (_) {
      throw const CookingStorageException();
    }
  }

  Future<CookingSession> setCurrentStep(String sessionId, int stepIndex) async {
    if (stepIndex < 0) {
      throw const CookingValidationException(
        'Step index must not be negative.',
      );
    }
    final session = await _requireActiveSession(sessionId);
    final recipe = await _recipes.getRecipe(session.recipeId);
    if (recipe.steps.isEmpty
        ? stepIndex != 0
        : stepIndex >= recipe.steps.length) {
      throw const CookingValidationException('Step index is out of range.');
    }
    return _save(
      _copySession(session, currentStepIndex: stepIndex, updatedAt: _clock()),
    );
  }

  Future<CookingSession> addTimer(
    String sessionId, {
    required String label,
    required int durationSeconds,
    bool startImmediately = true,
  }) async {
    final normalizedLabel = label.trim();
    if (normalizedLabel.isEmpty || durationSeconds <= 0) {
      throw const CookingValidationException(
        'Timer label and duration are required.',
      );
    }
    final session = await _requireActiveSession(sessionId);
    final now = _clock();
    final timer = CookingTimer(
      id: _nextId(),
      label: normalizedLabel,
      durationSeconds: durationSeconds,
      state: startImmediately
          ? CookingTimerState.running
          : CookingTimerState.paused,
      endsAt: startImmediately
          ? now.add(Duration(seconds: durationSeconds))
          : null,
      pausedRemainingSeconds: startImmediately ? null : durationSeconds,
      createdAt: now,
      updatedAt: now,
    );
    return _save(
      _copySession(
        session,
        timers: <CookingTimer>[...session.timers, timer],
        updatedAt: now,
      ),
    );
  }

  Future<CookingSession> pauseTimer(String sessionId, String timerId) async {
    final session = await _requireActiveSession(sessionId);
    final now = _clock();
    final timer = _requireTimer(session, timerId);
    if (timer.state != CookingTimerState.running) return session;
    final remaining = timer.remainingSecondsAt(now);
    final updatedTimer = remaining == 0
        ? _completeTimer(timer, now)
        : _copyTimer(
            timer,
            state: CookingTimerState.paused,
            clearEndsAt: true,
            pausedRemainingSeconds: remaining,
            updatedAt: now,
          );
    return _replaceTimer(session, updatedTimer, now);
  }

  Future<CookingSession> resumeTimer(String sessionId, String timerId) async {
    final session = await _requireActiveSession(sessionId);
    final timer = _requireTimer(session, timerId);
    if (timer.state != CookingTimerState.paused) return session;
    final remaining = timer.pausedRemainingSeconds ?? 0;
    final now = _clock();
    if (remaining <= 0) {
      return _replaceTimer(session, _completeTimer(timer, now), now);
    }
    return _replaceTimer(
      session,
      _copyTimer(
        timer,
        state: CookingTimerState.running,
        endsAt: now.add(Duration(seconds: remaining)),
        clearPausedRemainingSeconds: true,
        updatedAt: now,
      ),
      now,
    );
  }

  Future<CookingSession> completeTimer(String sessionId, String timerId) async {
    final session = await _requireActiveSession(sessionId);
    final now = _clock();
    return _replaceTimer(
      session,
      _completeTimer(_requireTimer(session, timerId), now),
      now,
    );
  }

  Future<CookingSession> deleteTimer(String sessionId, String timerId) async {
    final session = await _requireActiveSession(sessionId);
    final target = _requireTimer(session, timerId);
    return _save(
      _copySession(
        session,
        timers: session.timers.where((timer) => timer.id != target.id).toList(),
        updatedAt: _clock(),
      ),
    );
  }

  Future<CookingSession> completeSession(String sessionId) async {
    final session = await _requireActiveSession(sessionId);
    final now = _clock();
    return _save(
      _copySession(
        session,
        status: CookingSessionStatus.completed,
        completedAt: now,
        timers: session.timers
            .map((timer) => _completeTimer(timer, now))
            .toList(),
        updatedAt: now,
      ),
    );
  }

  Future<void> deleteSession(String sessionId) async {
    await getSession(sessionId);
    try {
      await _repository.deleteSession(_requireId(sessionId));
    } catch (_) {
      throw const CookingStorageException();
    }
  }

  Future<CookingSession> _requireActiveSession(String id) async {
    final session = await getSession(id);
    if (session.status != CookingSessionStatus.active) {
      throw const CookingValidationException('Cooking session is completed.');
    }
    return session;
  }

  Future<CookingSession> _projectExpiredTimers(CookingSession session) async {
    final now = _clock();
    var changed = false;
    final timers = session.timers.map((timer) {
      if (timer.state == CookingTimerState.running &&
          timer.remainingSecondsAt(now) == 0) {
        changed = true;
        return _completeTimer(timer, now);
      }
      return timer;
    }).toList();
    if (!changed) return session;
    return _save(_copySession(session, timers: timers, updatedAt: now));
  }

  Future<CookingSession> _replaceTimer(
    CookingSession session,
    CookingTimer timer,
    DateTime now,
  ) => _save(
    _copySession(
      session,
      timers: session.timers
          .map((item) => item.id == timer.id ? timer : item)
          .toList(),
      updatedAt: now,
    ),
  );

  Future<CookingSession> _save(CookingSession session) async {
    try {
      await _repository.upsertSession(session);
      return session;
    } catch (_) {
      throw const CookingStorageException();
    }
  }

  static CookingTimer _requireTimer(CookingSession session, String id) {
    final normalized = _requireId(id);
    for (final timer in session.timers) {
      if (timer.id == normalized) return timer;
    }
    throw CookingTimerNotFoundException(id);
  }

  String _nextId() {
    final id = _idGenerator().trim();
    if (id.isEmpty) {
      throw const CookingValidationException('Generated ID must not be empty.');
    }
    return id;
  }

  static String _requireId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const CookingValidationException('ID must not be empty.');
    }
    return normalized;
  }

  static CookingSession _copySession(
    CookingSession session, {
    int? currentStepIndex,
    CookingSessionStatus? status,
    DateTime? updatedAt,
    DateTime? completedAt,
    List<CookingTimer>? timers,
  }) => CookingSession(
    id: session.id,
    recipeId: session.recipeId,
    currentStepIndex: currentStepIndex ?? session.currentStepIndex,
    status: status ?? session.status,
    startedAt: session.startedAt,
    updatedAt: updatedAt ?? session.updatedAt,
    completedAt: completedAt ?? session.completedAt,
    timers: timers ?? session.timers,
  );

  static CookingTimer _completeTimer(CookingTimer timer, DateTime now) =>
      _copyTimer(
        timer,
        state: CookingTimerState.completed,
        clearEndsAt: true,
        clearPausedRemainingSeconds: true,
        completedAt: timer.completedAt ?? now,
        updatedAt: now,
      );

  static CookingTimer _copyTimer(
    CookingTimer timer, {
    CookingTimerState? state,
    DateTime? endsAt,
    bool clearEndsAt = false,
    int? pausedRemainingSeconds,
    bool clearPausedRemainingSeconds = false,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) => CookingTimer(
    id: timer.id,
    label: timer.label,
    durationSeconds: timer.durationSeconds,
    state: state ?? timer.state,
    endsAt: clearEndsAt ? null : endsAt ?? timer.endsAt,
    pausedRemainingSeconds: clearPausedRemainingSeconds
        ? null
        : pausedRemainingSeconds ?? timer.pausedRemainingSeconds,
    createdAt: timer.createdAt,
    updatedAt: updatedAt ?? timer.updatedAt,
    completedAt: completedAt ?? timer.completedAt,
  );
}
