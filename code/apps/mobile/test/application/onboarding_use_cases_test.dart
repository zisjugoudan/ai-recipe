import 'package:ai_recipe/application/access/onboarding_use_cases.dart';
import 'package:ai_recipe/domain/access/onboarding_state.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryOnboardingRepository implements OnboardingRepository {
  OnboardingState state = const OnboardingState.pending();
  Object? error;

  @override
  Future<OnboardingState> load() async {
    if (error case final value?) throw value;
    return state;
  }

  @override
  Future<void> save(OnboardingState state) async {
    if (error case final value?) throw value;
    this.state = state;
  }
}

void main() {
  test('complete and reset keep onboarding independent from session', () async {
    final repository = MemoryOnboardingRepository();
    final useCases = OnboardingUseCases(repository: repository);

    expect(await useCases.load(), const OnboardingState.pending());
    expect(await useCases.complete(), const OnboardingState.completed());
    expect(await useCases.load(), const OnboardingState.completed());
    expect(await useCases.reset(), const OnboardingState.pending());
  });

  test('maps repository failures to onboarding storage exception', () async {
    final repository = MemoryOnboardingRepository()..error = StateError('disk');
    final useCases = OnboardingUseCases(repository: repository);

    await expectLater(
      useCases.load(),
      throwsA(isA<OnboardingStorageException>()),
    );
    await expectLater(
      useCases.complete(),
      throwsA(isA<OnboardingStorageException>()),
    );
  });
}
