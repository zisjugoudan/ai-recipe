import '../../domain/access/onboarding_state.dart';

class OnboardingStorageException implements Exception {
  const OnboardingStorageException();
}

class OnboardingUseCases {
  const OnboardingUseCases({required OnboardingRepository repository})
    : _repository = repository;

  final OnboardingRepository _repository;

  Future<OnboardingState> load() => _read();

  Future<OnboardingState> complete() =>
      _write(const OnboardingState.completed());

  Future<OnboardingState> reset() => _write(const OnboardingState.pending());

  Future<OnboardingState> _read() async {
    try {
      return await _repository.load();
    } on OnboardingStorageException {
      rethrow;
    } catch (_) {
      throw const OnboardingStorageException();
    }
  }

  Future<OnboardingState> _write(OnboardingState state) async {
    try {
      await _repository.save(state);
      return state;
    } on OnboardingStorageException {
      rethrow;
    } catch (_) {
      throw const OnboardingStorageException();
    }
  }
}
