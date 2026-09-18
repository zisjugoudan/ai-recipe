import 'package:ai_recipe/data/device_app_session_repository.dart';
import 'package:ai_recipe/domain/access/app_access_repository.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:ai_recipe/domain/access/onboarding_state.dart';

class FakeAppSessionRepository implements AppSessionRepository {
  FakeAppSessionRepository({this.session = const AppSession.guest()});

  AppSession session;
  Object? loadError;
  Object? saveError;
  int loadCount = 0;
  int saveCount = 0;

  @override
  Future<AppSession> load() async {
    loadCount += 1;
    if (loadError case final error?) throw error;
    return session;
  }

  @override
  Future<void> save(AppSession session) async {
    saveCount += 1;
    if (saveError case final error?) throw error;
    this.session = session;
  }
}

class FakeAppCapabilityRuntimeRepository
    implements AppCapabilityRuntimeRepository {
  FakeAppCapabilityRuntimeRepository({AppCapabilityRuntime? runtime})
    : runtime = runtime ?? AppCapabilityRuntime();

  AppCapabilityRuntime runtime;
  Object? loadError;

  @override
  Future<AppCapabilityRuntime> load() async {
    if (loadError case final error?) throw error;
    return runtime;
  }
}

class MemoryAppSessionKeyValueStore implements AppSessionKeyValueStore {
  final Map<String, String> values = <String, String>{};
  Object? getError;
  Object? setError;

  @override
  Future<String?> getString(String key) async {
    if (getError case final error?) throw error;
    return values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    if (setError case final error?) throw error;
    values[key] = value;
  }
}

class MemoryOnboardingRepository implements OnboardingRepository {
  MemoryOnboardingRepository({this.state = const OnboardingState.pending()});

  OnboardingState state;
  Object? loadError;
  Object? saveError;
  int loadCount = 0;
  int saveCount = 0;

  @override
  Future<OnboardingState> load() async {
    loadCount += 1;
    if (loadError case final error?) throw error;
    return state;
  }

  @override
  Future<void> save(OnboardingState state) async {
    saveCount += 1;
    if (saveError case final error?) throw error;
    this.state = state;
  }
}
