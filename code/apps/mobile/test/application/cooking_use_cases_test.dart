import 'package:ai_recipe/application/cooking/cooking_use_cases.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/application/recipe/recipe_library_use_cases.dart';
import 'package:ai_recipe/domain/cooking/cooking_session.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_local_business_repositories.dart';
import '../support/fake_recipe_library_repository.dart';

void main() {
  late MemoryRecipeLibraryRepository recipeRepository;
  late MemoryCookingRepository cookingRepository;
  late RecipeLibraryUseCases recipes;
  late CookingUseCases useCases;
  late DateTime now;
  late int idSequence;
  late Recipe recipe;

  setUp(() async {
    recipeRepository = MemoryRecipeLibraryRepository();
    cookingRepository = MemoryCookingRepository();
    now = DateTime.utc(2026, 7, 30, 12);
    idSequence = 1;
    recipes = RecipeLibraryUseCases(
      recipeRepository: recipeRepository,
      categoryRepository: recipeRepository,
      idGenerator: () => 'recipe-id-${idSequence++}',
      clock: () => now,
    );
    recipe = await recipes.createRecipe(
      RecipeDraftInput(
        title: '三步菜谱',
        status: RecipeStatus.published,
        ingredients: <RecipeIngredientInput>[RecipeIngredientInput(name: '食材')],
        steps: const <RecipeStepInput>[
          RecipeStepInput(description: '第一步'),
          RecipeStepInput(description: '第二步'),
          RecipeStepInput(description: '第三步'),
        ],
      ),
    );
    idSequence = 1;
    useCases = CookingUseCases(
      repository: cookingRepository,
      recipes: recipes,
      idGenerator: () => 'cooking-id-${idSequence++}',
      clock: () => now,
    );
  });

  test('starts once and resumes the active session for a recipe', () async {
    final started = await useCases.startOrResume(recipe.id);
    now = now.add(const Duration(minutes: 2));
    final resumed = await useCases.startOrResume(recipe.id);

    expect(started.id, 'cooking-id-1');
    expect(started.currentStepIndex, 0);
    expect(started.status, CookingSessionStatus.active);
    expect(resumed.id, started.id);
    expect(cookingRepository.sessions, hasLength(1));
  });

  test('updates current step and rejects an out-of-range step', () async {
    final session = await useCases.startOrResume(recipe.id);
    now = now.add(const Duration(seconds: 10));

    final updated = await useCases.setCurrentStep(session.id, 2);

    expect(updated.currentStepIndex, 2);
    expect(updated.updatedAt, now);
    await expectLater(
      useCases.setCurrentStep(session.id, 3),
      throwsA(isA<CookingValidationException>()),
    );
  });

  test('keeps multiple independent timers in one session', () async {
    final session = await useCases.startOrResume(recipe.id);
    final withFirst = await useCases.addTimer(
      session.id,
      label: '焖煮',
      durationSeconds: 120,
    );
    now = now.add(const Duration(seconds: 5));
    final withSecond = await useCases.addTimer(
      session.id,
      label: '静置',
      durationSeconds: 30,
      startImmediately: false,
    );

    expect(withFirst.timers.single.endsAt, DateTime.utc(2026, 7, 30, 12, 2));
    expect(withSecond.timers, hasLength(2));
    expect(withSecond.timers.first.state, CookingTimerState.running);
    expect(withSecond.timers.last.state, CookingTimerState.paused);
    expect(withSecond.timers.last.pausedRemainingSeconds, 30);
  });

  test(
    'pause and resume preserve remaining time using absolute deadlines',
    () async {
      final session = await useCases.startOrResume(recipe.id);
      final withTimer = await useCases.addTimer(
        session.id,
        label: '计时',
        durationSeconds: 100,
      );
      final timerId = withTimer.timers.single.id;
      now = now.add(const Duration(seconds: 31));

      final paused = await useCases.pauseTimer(session.id, timerId);

      expect(paused.timers.single.state, CookingTimerState.paused);
      expect(paused.timers.single.pausedRemainingSeconds, 69);
      expect(paused.timers.single.endsAt, isNull);

      now = now.add(const Duration(minutes: 5));
      final resumed = await useCases.resumeTimer(session.id, timerId);

      expect(resumed.timers.single.state, CookingTimerState.running);
      expect(
        resumed.timers.single.endsAt,
        now.add(const Duration(seconds: 69)),
      );
      expect(resumed.timers.single.pausedRemainingSeconds, isNull);
    },
  );

  test(
    'projects an expired running timer to completed and persists it',
    () async {
      final session = await useCases.startOrResume(recipe.id);
      final withTimer = await useCases.addTimer(
        session.id,
        label: '短计时',
        durationSeconds: 3,
      );
      now = now.add(const Duration(seconds: 4));
      final writesBeforeRead = cookingRepository.upsertCount;

      final loaded = await useCases.getSession(session.id);

      expect(loaded.timers.single.state, CookingTimerState.completed);
      expect(loaded.timers.single.remainingSecondsAt(now), 0);
      expect(loaded.timers.single.endsAt, isNull);
      expect(cookingRepository.upsertCount, writesBeforeRead + 1);
      expect(
        cookingRepository.sessions[session.id]!.timers.single.state,
        CookingTimerState.completed,
      );
      expect(withTimer.timers.single.state, CookingTimerState.running);
    },
  );

  test(
    'completeSession completes every timer and blocks further edits',
    () async {
      final session = await useCases.startOrResume(recipe.id);
      final withTimer = await useCases.addTimer(
        session.id,
        label: '计时',
        durationSeconds: 20,
      );
      now = now.add(const Duration(seconds: 2));

      final completed = await useCases.completeSession(session.id);

      expect(completed.status, CookingSessionStatus.completed);
      expect(completed.completedAt, now);
      expect(completed.timers.single.state, CookingTimerState.completed);
      await expectLater(
        useCases.deleteTimer(session.id, withTimer.timers.single.id),
        throwsA(isA<CookingValidationException>()),
      );
    },
  );

  test('deletes timer and then deletes the session', () async {
    final session = await useCases.startOrResume(recipe.id);
    final withTimer = await useCases.addTimer(
      session.id,
      label: '计时',
      durationSeconds: 20,
    );

    final withoutTimer = await useCases.deleteTimer(
      session.id,
      '  ${withTimer.timers.single.id}  ',
    );
    await useCases.deleteSession(session.id);

    expect(withoutTimer.timers, isEmpty);
    expect(cookingRepository.sessions.containsKey(session.id), isFalse);
  });

  test('maps invalid ids, durations and storage failures', () async {
    final session = await useCases.startOrResume(recipe.id);

    await expectLater(
      useCases.getSession('missing'),
      throwsA(isA<CookingSessionNotFoundException>()),
    );
    await expectLater(
      useCases.addTimer(session.id, label: ' ', durationSeconds: 0),
      throwsA(isA<CookingValidationException>()),
    );
    await expectLater(
      useCases.pauseTimer(session.id, 'missing-timer'),
      throwsA(isA<CookingTimerNotFoundException>()),
    );

    cookingRepository.error = StateError('database implementation detail');
    await expectLater(
      useCases.getSession(session.id),
      throwsA(isA<CookingStorageException>()),
    );
  });
}
