import 'package:ai_recipe/domain/activity/recipe_activity.dart';
import 'package:ai_recipe/domain/cooking/cooking_session.dart';
import 'package:ai_recipe/domain/settings/local_app_settings.dart';

class MemoryRecipeActivityRepository implements RecipeActivityRepository {
  final Map<String, RecipeRecentView> views = <String, RecipeRecentView>{};
  Object? error;
  int clearCount = 0;

  @override
  Future<void> recordRecipeView(String recipeId, DateTime viewedAt) async {
    _throwIfNeeded();
    views[recipeId] = RecipeRecentView(recipeId: recipeId, viewedAt: viewedAt);
  }

  @override
  Future<List<RecipeRecentView>> listRecentViews({int limit = 20}) async {
    _throwIfNeeded();
    final result = views.values.toList()
      ..sort((left, right) => right.viewedAt.compareTo(left.viewedAt));
    return result.take(limit).toList();
  }

  @override
  Future<void> clearRecipeHistory() async {
    _throwIfNeeded();
    clearCount += 1;
    views.clear();
  }

  void _throwIfNeeded() {
    if (error case final value?) throw value;
  }
}

class MemoryLocalAppSettingsRepository implements LocalAppSettingsRepository {
  LocalAppSettings? settings;
  Object? loadError;
  Object? saveError;
  int saveCount = 0;

  @override
  Future<LocalAppSettings?> load() async {
    if (loadError case final value?) throw value;
    return settings;
  }

  @override
  Future<void> save(LocalAppSettings value) async {
    if (saveError case final error?) throw error;
    saveCount += 1;
    settings = value;
  }
}

class MemoryCookingRepository implements CookingRepository {
  final Map<String, CookingSession> sessions = <String, CookingSession>{};
  Object? error;
  int upsertCount = 0;

  @override
  Future<void> upsertSession(CookingSession session) async {
    _throwIfNeeded();
    upsertCount += 1;
    sessions[session.id] = session;
  }

  @override
  Future<CookingSession?> getSessionById(String id) async {
    _throwIfNeeded();
    return sessions[id];
  }

  @override
  Future<CookingSession?> getActiveSessionForRecipe(String recipeId) async {
    _throwIfNeeded();
    final matches =
        sessions.values
            .where(
              (session) =>
                  session.recipeId == recipeId &&
                  session.status == CookingSessionStatus.active,
            )
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<void> deleteSession(String id) async {
    _throwIfNeeded();
    sessions.remove(id);
  }

  void _throwIfNeeded() {
    if (error case final value?) throw value;
  }
}
