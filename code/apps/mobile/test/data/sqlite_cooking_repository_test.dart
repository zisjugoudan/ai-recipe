import 'dart:io';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_cooking_repository.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:ai_recipe/domain/cooking/cooking_session.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteCookingRepository repository;
  final startedAt = DateTime.utc(2026, 7, 30, 10);

  CookingSession session({
    CookingSessionStatus status = CookingSessionStatus.active,
    int currentStepIndex = 1,
    DateTime? updatedAt,
    DateTime? completedAt,
    List<CookingTimer>? timers,
  }) => CookingSession(
    id: 'session-1',
    recipeId: 'recipe-1',
    currentStepIndex: currentStepIndex,
    status: status,
    startedAt: startedAt,
    updatedAt: updatedAt ?? startedAt,
    completedAt: completedAt,
    timers:
        timers ??
        <CookingTimer>[
          CookingTimer(
            id: 'timer-running',
            label: 'Boil',
            durationSeconds: 120,
            state: CookingTimerState.running,
            endsAt: startedAt.add(const Duration(seconds: 120)),
            createdAt: startedAt,
            updatedAt: startedAt,
          ),
          CookingTimer(
            id: 'timer-paused',
            label: 'Rest',
            durationSeconds: 60,
            state: CookingTimerState.paused,
            pausedRemainingSeconds: 35,
            createdAt: startedAt.add(const Duration(seconds: 1)),
            updatedAt: startedAt.add(const Duration(seconds: 5)),
          ),
        ],
  );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_cooking_',
    );
    databasePath = path.join(temporaryDirectory.path, 'cooking.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    await SqliteRecipeRepository(appDatabase).upsertRecipe(
      Recipe(
        id: 'recipe-1',
        title: 'Recipe',
        createdAt: startedAt,
        updatedAt: startedAt,
      ),
    );
    repository = SqliteCookingRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('persists a session and multiple timers across reopen', () async {
    await repository.upsertSession(session());

    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteCookingRepository(appDatabase);

    final loaded = await repository.getSessionById('session-1');
    expect(loaded, isNotNull);
    expect(loaded!.currentStepIndex, 1);
    expect(loaded.status, CookingSessionStatus.active);
    expect(loaded.timers.map((timer) => timer.id), <String>[
      'timer-running',
      'timer-paused',
    ]);
    expect(
      loaded.timers.first.endsAt,
      startedAt.add(const Duration(seconds: 120)),
    );
    expect(loaded.timers.last.pausedRemainingSeconds, 35);
    expect(
      (await repository.getActiveSessionForRecipe('recipe-1'))!.id,
      'session-1',
    );
  });

  test('updates atomically replace the stored timer collection', () async {
    await repository.upsertSession(session());
    final updatedAt = startedAt.add(const Duration(minutes: 3));
    await repository.upsertSession(
      session(
        currentStepIndex: 2,
        updatedAt: updatedAt,
        timers: <CookingTimer>[
          CookingTimer(
            id: 'timer-completed',
            label: 'Done',
            durationSeconds: 20,
            state: CookingTimerState.completed,
            createdAt: startedAt,
            updatedAt: updatedAt,
            completedAt: updatedAt,
          ),
        ],
      ),
    );

    final loaded = await repository.getSessionById('session-1');
    expect(loaded!.currentStepIndex, 2);
    expect(loaded.timers.single.id, 'timer-completed');
    final database = await appDatabase.database;
    final oldCount = Sqflite.firstIntValue(
      await database.rawQuery(
        "SELECT COUNT(*) FROM cooking_timers WHERE id IN ('timer-running', 'timer-paused')",
      ),
    );
    expect(oldCount, 0);
  });

  test(
    'completed sessions are not active and delete cascades timers',
    () async {
      final completedAt = startedAt.add(const Duration(minutes: 5));
      await repository.upsertSession(
        session(
          status: CookingSessionStatus.completed,
          updatedAt: completedAt,
          completedAt: completedAt,
        ),
      );

      expect(await repository.getActiveSessionForRecipe('recipe-1'), isNull);
      await repository.deleteSession('session-1');
      expect(await repository.getSessionById('session-1'), isNull);
      final database = await appDatabase.database;
      expect(
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM cooking_timers'),
        ),
        0,
      );
    },
  );
}
