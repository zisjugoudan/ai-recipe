import 'app_capability.dart';
import 'app_session.dart';

abstract interface class AppSessionRepository {
  Future<AppSession> load();
  Future<void> save(AppSession session);
}

abstract interface class AppCapabilityRuntimeRepository {
  Future<AppCapabilityRuntime> load();
}
