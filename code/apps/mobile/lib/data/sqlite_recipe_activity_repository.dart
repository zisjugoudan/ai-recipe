import 'package:sqflite/sqflite.dart';

import '../domain/activity/recipe_activity.dart';
import 'local/app_database.dart';

class SqliteRecipeActivityRepository implements RecipeActivityRepository {
  const SqliteRecipeActivityRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<void> recordRecipeView(String recipeId, DateTime viewedAt) async {
    final database = await _appDatabase.database;
    await database.insert('recipe_recent_views', <String, Object?>{
      'recipe_id': recipeId,
      'viewed_at': viewedAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<RecipeRecentView>> listRecentViews({int limit = 20}) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'recipe_recent_views',
      orderBy: 'viewed_at DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => RecipeRecentView(
            recipeId: row['recipe_id']! as String,
            viewedAt: DateTime.fromMillisecondsSinceEpoch(
              row['viewed_at']! as int,
              isUtc: true,
            ),
          ),
        )
        .toList();
  }

  @override
  Future<void> clearRecipeHistory() async {
    final database = await _appDatabase.database;
    await database.delete('recipe_recent_views');
  }
}
