import 'package:ai_recipe/data/device_onboarding_repository.dart';
import 'package:ai_recipe/domain/access/onboarding_state.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryOnboardingKeyValueStore implements OnboardingKeyValueStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool?> getBool(String key) async => values[key];

  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }
}

void main() {
  test('defaults to pending and persists completed/reset state', () async {
    final store = MemoryOnboardingKeyValueStore();
    final repository = DeviceOnboardingRepository(store: store);

    expect(await repository.load(), const OnboardingState.pending());

    await repository.save(const OnboardingState.completed());
    expect(store.values[DeviceOnboardingRepository.storageKey], isTrue);
    expect(await repository.load(), const OnboardingState.completed());

    await repository.save(const OnboardingState.pending());
    expect(await repository.load(), const OnboardingState.pending());
  });
}
