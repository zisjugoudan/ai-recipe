class OnboardingState {
  const OnboardingState({required this.isCompleted});

  const OnboardingState.pending() : isCompleted = false;

  const OnboardingState.completed() : isCompleted = true;

  final bool isCompleted;

  @override
  bool operator ==(Object other) =>
      other is OnboardingState && other.isCompleted == isCompleted;

  @override
  int get hashCode => isCompleted.hashCode;
}

abstract interface class OnboardingRepository {
  Future<OnboardingState> load();

  Future<void> save(OnboardingState state);
}
