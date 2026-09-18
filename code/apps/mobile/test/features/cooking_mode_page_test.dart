import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/cooking/cooking_session.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/features/cooking/cooking_mode_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    final harness = TestBackendHarness(now: DateTime.utc(2026, 7, 30, 12));
    addTearDown(harness.close);
    return harness;
  }

  Future<Recipe> seedRecipe(
    TestBackendHarness harness, {
    bool longContent = false,
  }) {
    return harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: 'Weeknight chicken',
        status: RecipeStatus.published,
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(name: 'Chicken', quantity: '300', unit: 'g'),
          RecipeIngredientInput(name: 'Salt', quantity: '2', unit: 'g'),
        ],
        steps: <RecipeStepInput>[
          RecipeStepInput(
            description: longContent
                ? 'Chicken is mixed slowly with seasoning while the cook keeps checking texture, moisture, heat, and timing so this deliberately long instruction wraps across many lines on a compact phone.'
                : 'Mix Chicken with seasoning.',
            durationSeconds: 120,
            cookware: 'Bowl',
            tips: 'Coat every piece.',
          ),
          const RecipeStepInput(
            description: 'Sear Chicken until golden.',
            durationSeconds: 180,
            temperature: '200 C',
            heatLevel: 'High',
          ),
          const RecipeStepInput(
            description: 'Rest and serve.',
            durationSeconds: 60,
          ),
        ],
      ),
    );
  }

  /// 第二步骤不带时长，用于验证「自定义本步计时」。
  Future<Recipe> seedRecipeWithUndefinedStep(TestBackendHarness harness) {
    return harness.root.backend.createRecipe(
      const RecipeDraftInput(
        title: 'No timing',
        status: RecipeStatus.published,
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(name: 'Egg', quantity: '2', unit: '个'),
        ],
        steps: <RecipeStepInput>[
          RecipeStepInput(
            description: 'Beat Egg.',
            durationSeconds: 60,
          ),
          RecipeStepInput(
            description: 'Cook Egg slowly until done.',
          ),
        ],
      ),
    );
  }

  Widget wrap(
    TestBackendHarness harness,
    Recipe recipe,
    CookingSession session,
  ) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      initialRoute: '/cooking',
      routes: <String, WidgetBuilder>{
        '/': (context) => const Scaffold(body: Text('Recipe detail')),
        '/cooking': (context) => CookingModePage(
          backend: harness.root.backend,
          recipeId: recipe.id,
          sessionId: session.id,
          clock: () => harness.now,
        ),
      },
    );
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 220);
  }

  testWidgets('restores the saved step and multiple timer states', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    session = await harness.root.backend.setCookingStep(session.id, 1);
    session = await harness.root.backend.addCookingTimer(
      session.id,
      label: 'Pan',
      durationSeconds: 120,
    );
    session = await harness.root.backend.addCookingTimer(
      session.id,
      label: 'Sauce',
      durationSeconds: 90,
      startImmediately: false,
    );

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    expect(find.text('STEP 2 / 3'), findsOneWidget);
    expect(find.text('Sear Chicken until golden.'), findsOneWidget);
    expect(session.timers, hasLength(2));
    for (final timer in session.timers) {
      final timerCard = find.byKey(Key('cookingTimer-${timer.id}'));
      await scrollTo(tester, timerCard);
      expect(timerCard, findsOneWidget);
    }
    final paused = session.timers.singleWhere(
      (timer) => timer.state == CookingTimerState.paused,
    );
    expect(find.byKey(Key('resumeCookingTimer-${paused.id}')), findsOneWidget);
  });

  testWidgets('persists step navigation and full timer lifecycle', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nextCookingStepButton')));
    await tester.pumpAndSettle();
    session = await harness.root.backend.getCookingSession(session.id);
    expect(session.currentStepIndex, 1);

    await scrollTo(tester, find.byKey(const Key('startStepTimerButton')));
    await tester.tap(find.byKey(const Key('startStepTimerButton')));
    await tester.pumpAndSettle();
    session = await harness.root.backend.getCookingSession(session.id);
    expect(session.timers, hasLength(1));
    final timerId = session.timers.single.id;

    await scrollTo(tester, find.byKey(Key('pauseCookingTimer-$timerId')));
    await tester.tap(find.byKey(Key('pauseCookingTimer-$timerId')));
    await tester.pumpAndSettle();
    session = await harness.root.backend.getCookingSession(session.id);
    expect(session.timers.single.state, CookingTimerState.paused);

    await tester.tap(find.byKey(Key('resumeCookingTimer-$timerId')));
    await tester.pumpAndSettle();
    session = await harness.root.backend.getCookingSession(session.id);
    expect(session.timers.single.state, CookingTimerState.running);

    await tester.tap(find.byKey(Key('completeCookingTimer-$timerId')));
    await tester.pumpAndSettle();
    session = await harness.root.backend.getCookingSession(session.id);
    expect(session.timers.single.state, CookingTimerState.completed);

    await tester.tap(find.byKey(Key('deleteCookingTimer-$timerId')));
    await tester.pumpAndSettle();
    session = await harness.root.backend.getCookingSession(session.id);
    expect(session.timers, isEmpty);

    await tester.tap(find.byKey(const Key('previousCookingStepButton')));
    await tester.pumpAndSettle();
    session = await harness.root.backend.getCookingSession(session.id);
    expect(session.currentStepIndex, 0);
  });

  testWidgets('exit confirmation keeps active timers and session state', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    session = await harness.root.backend.addCookingTimer(
      session.id,
      label: 'Keep running',
      durationSeconds: 300,
    );

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('exitCookingButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmExitCookingButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancelExitCookingButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('currentCookingStepText')), findsOneWidget);

    await tester.tap(find.byKey(const Key('exitCookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmExitCookingButton')));
    await tester.pumpAndSettle();

    expect(find.text('Recipe detail'), findsOneWidget);
    final saved = await harness.root.backend.getCookingSession(session.id);
    expect(saved.status, CookingSessionStatus.active);
    expect(saved.timers.single.state, CookingTimerState.running);
  });

  testWidgets('finishes the last step and closes the active session', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    session = await harness.root.backend.setCookingStep(session.id, 2);

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('finishCookingSessionButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirmFinishCookingSessionButton')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recipe detail'), findsOneWidget);
    final saved = await harness.root.backend.getCookingSession(session.id);
    expect(saved.status, CookingSessionStatus.completed);
    expect(saved.completedAt, isNotNull);
  });

  testWidgets('reconciles expired running timers from absolute endsAt', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    session = await harness.root.backend.addCookingTimer(
      session.id,
      label: 'Fast timer',
      durationSeconds: 1,
    );
    final timerId = session.timers.single.id;

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    harness.now = harness.now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final saved = await harness.root.backend.getCookingSession(session.id);
    expect(saved.timers.single.state, CookingTimerState.completed);
    expect(find.byKey(Key('deleteCookingTimer-$timerId')), findsOneWidget);
    expect(find.textContaining('Fast timer'), findsWidgets);
  });

  testWidgets('long steps and several timers stay usable on a compact screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness, longContent: true);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    for (var index = 0; index < 4; index += 1) {
      session = await harness.root.backend.addCookingTimer(
        session.id,
        label: 'Timer $index with a readable label',
        durationSeconds: 90 + index,
        startImmediately: index.isEven,
      );
    }

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('currentCookingStepText')), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('startStepTimerButton')));
    expect(find.byKey(const Key('startStepTimerButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('steps without duration show a custom timer button', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipeWithUndefinedStep(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    session = await harness.root.backend.setCookingStep(session.id, 1);

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    expect(find.text('STEP 2 / 2'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('customStepTimerButton')));
    expect(find.byKey(const Key('customStepTimerButton')), findsOneWidget);
    // 无时长步骤不应出现「启动本步计时」按钮。
    expect(find.byKey(const Key('startStepTimerButton')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom timer creates a timer and syncs duration to the recipe', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipeWithUndefinedStep(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    session = await harness.root.backend.setCookingStep(session.id, 1);

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const Key('customStepTimerButton')));
    await tester.tap(find.byKey(const Key('customStepTimerButton')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('customTimerMinutesField')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('customTimerMinutesField')),
      '2',
    );
    await tester.enterText(
      find.byKey(const Key('customTimerSecondsField')),
      '30',
    );
    await tester.tap(find.byKey(const Key('confirmCustomTimerButton')));
    await tester.pumpAndSettle();

    // 会话中创建了「步骤 2」计时器，时长为 2 分 30 秒。
    final savedSession = await harness.root.backend.getCookingSession(
      session.id,
    );
    expect(savedSession.timers, hasLength(1));
    expect(savedSession.timers.single.label, '步骤 2');
    expect(savedSession.timers.single.durationSeconds, 150);

    // 自定义时长已同步到菜谱步骤。
    final savedRecipe = await harness.root.backend.getRecipe(recipe.id);
    final step = savedRecipe.steps.singleWhere((item) => item.stepNumber == 2);
    expect(step.durationSeconds, 150);

    expect(find.text('已创建计时器，并将时长同步到菜谱。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the custom timer dialog leaves everything unchanged', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipeWithUndefinedStep(harness);
    var session = await harness.root.backend.startOrResumeCooking(recipe.id);
    session = await harness.root.backend.setCookingStep(session.id, 1);

    await tester.pumpWidget(wrap(harness, recipe, session));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const Key('customStepTimerButton')));
    await tester.tap(find.byKey(const Key('customStepTimerButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelCustomTimerButton')));
    await tester.pumpAndSettle();

    final savedSession = await harness.root.backend.getCookingSession(
      session.id,
    );
    expect(savedSession.timers, isEmpty);
    final savedRecipe = await harness.root.backend.getRecipe(recipe.id);
    expect(
      savedRecipe.steps.singleWhere((item) => item.stepNumber == 2)
          .durationSeconds,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
