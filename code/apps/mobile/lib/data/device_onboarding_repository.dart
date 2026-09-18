import 'package:shared_preferences/shared_preferences.dart';

import '../domain/access/onboarding_state.dart';

abstract interface class OnboardingKeyValueStore {
  Future<bool?> getBool(String key);

  Future<void> setBool(String key, bool value);
}

class SharedPreferencesOnboardingKeyValueStore
    implements OnboardingKeyValueStore {
  SharedPreferencesOnboardingKeyValueStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences;

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _resolvedPreferences =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<bool?> getBool(String key) => _resolvedPreferences.getBool(key);

  @override
  Future<void> setBool(String key, bool value) async {
    await _resolvedPreferences.setBool(key, value);
  }
}

class DeviceOnboardingRepository implements OnboardingRepository {
  DeviceOnboardingRepository({OnboardingKeyValueStore? store})
    : _store = store ?? SharedPreferencesOnboardingKeyValueStore();

  static const storageKey = 'onboarding_completed_v1';

  final OnboardingKeyValueStore _store;

  @override
  Future<OnboardingState> load() async {
    final completed = await _store.getBool(storageKey);
    return OnboardingState(isCompleted: completed ?? false);
  }

  @override
  Future<void> save(OnboardingState state) {
    return _store.setBool(storageKey, state.isCompleted);
  }
}
