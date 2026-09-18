enum CookingSessionStatus { active, completed }

enum CookingTimerState { running, paused, completed }

class CookingTimer {
  CookingTimer({
    required this.id,
    required this.label,
    required this.durationSeconds,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.endsAt,
    this.pausedRemainingSeconds,
    this.completedAt,
  }) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (label.trim().isEmpty) throw ArgumentError.value(label, 'label');
    if (durationSeconds <= 0) {
      throw ArgumentError.value(durationSeconds, 'durationSeconds');
    }
    if (state == CookingTimerState.running && endsAt == null) {
      throw ArgumentError('A running timer requires endsAt.');
    }
    if (state == CookingTimerState.paused &&
        (pausedRemainingSeconds == null || pausedRemainingSeconds! < 0)) {
      throw ArgumentError('A paused timer requires remaining seconds.');
    }
  }

  final String id;
  final String label;
  final int durationSeconds;
  final CookingTimerState state;
  final DateTime? endsAt;
  final int? pausedRemainingSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  int remainingSecondsAt(DateTime now) {
    switch (state) {
      case CookingTimerState.completed:
        return 0;
      case CookingTimerState.paused:
        return pausedRemainingSeconds ?? 0;
      case CookingTimerState.running:
        final milliseconds = endsAt!.difference(now).inMilliseconds;
        if (milliseconds <= 0) return 0;
        return (milliseconds / 1000).ceil();
    }
  }
}

class CookingSession {
  CookingSession({
    required this.id,
    required this.recipeId,
    required this.currentStepIndex,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    this.completedAt,
    this.timers = const <CookingTimer>[],
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id');
    }
    if (recipeId.trim().isEmpty) {
      throw ArgumentError.value(recipeId, 'recipeId');
    }
    if (currentStepIndex < 0) {
      throw ArgumentError.value(currentStepIndex, 'currentStepIndex');
    }
  }

  final String id;
  final String recipeId;
  final int currentStepIndex;
  final CookingSessionStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final List<CookingTimer> timers;
}

abstract interface class CookingRepository {
  Future<void> upsertSession(CookingSession session);

  Future<CookingSession?> getSessionById(String id);

  Future<CookingSession?> getActiveSessionForRecipe(String recipeId);

  Future<void> deleteSession(String id);
}
