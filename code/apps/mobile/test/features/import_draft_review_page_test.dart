import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/features/importing/import_draft_review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    return harness;
  }

  Future<({Recipe recipe, ImportTask task})> seedReview(
    TestBackendHarness harness,
  ) async {
    final recipe = await harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '原始 AI 菜名',
        description: 'AI 自动整理',
        coverImage: 'https://example.com/cover.jpg',
        servings: 2,
        prepTimeMinutes: 5,
        cookTimeMinutes: 8,
        totalTimeMinutes: 13,
        difficulty: RecipeDifficulty.easy,
        notes: '保留备注',
        favorite: true,
        status: RecipeStatus.draft,
        tags: const <String>['快手'],
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(
            id: 'ingredient-1',
            name: '番茄',
            quantity: '2',
            unit: '个',
            preparation: '切块',
            confidence: 0.55,
          ),
        ],
        steps: const <RecipeStepInput>[
          RecipeStepInput(
            id: 'step-1',
            description: '大火翻炒',
            durationSeconds: 90,
            heatLevel: 'high',
            confidence: 0.92,
          ),
        ],
      ),
    );
    final source = ImportSourceLink.parse(
      'https://www.xiaohongshu.com/explore/3',
    );
    final task =
        ImportTask.queued(
              id: 'draft-review-task',
              source: source,
              now: harness.now,
            )
            .start(harness.now)
            .advance(
              nextStage: ImportTaskStage.generating,
              nextProgress: 0.95,
              now: harness.now,
            )
            .markNeedsReview(recipeId: recipe.id, now: harness.now);
    harness.importTaskRepository.tasks[task.id] = task;
    return (recipe: recipe, task: task);
  }

  Widget wrap(
    TestBackendHarness harness,
    String taskId, {
    ImportContent? evidence,
  }) => MaterialApp(
    theme: buildAiRecipeTheme(),
    home: ImportDraftReviewPage(
      backend: harness.root.backend,
      taskId: taskId,
      evidence: evidence,
      onDataChanged: () {},
    ),
  );

  testWidgets(
    'editing and confirming publishes recipe while preserving metadata',
    (tester) async {
      final harness = await createHarness(tester);
      final seeded = await seedReview(harness);
      await tester.pumpWidget(wrap(harness, seeded.task.id));
      await tester.pumpAndSettle();

      expect(find.text('发现 1 项低置信度内容'), findsOneWidget);
      expect(find.text('标记已核对'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('importDraftTitleField')),
        '番茄炒蛋确认版',
      );
      await tester.enterText(
        find.byKey(const Key('importIngredientName-0')),
        '熟番茄',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveImportDraftButton')));
      await tester.pumpAndSettle();

      final saved = await harness.root.backend.getRecipe(seeded.recipe.id);
      final task = await harness.root.backend.getImportTask(seeded.task.id);
      expect(saved.title, '番茄炒蛋确认版');
      expect(saved.ingredients.single.name, '熟番茄');
      expect(saved.ingredients.single.preparation, '切块');
      expect(saved.steps.single.heatLevel, 'high');
      expect(saved.coverImage, 'https://example.com/cover.jpg');
      expect(saved.tags, <String>['快手']);
      expect(saved.status, RecipeStatus.published);
      expect(task.status, ImportTaskStatus.completed);
    },
  );

  testWidgets('discard confirmation cancels task and moves draft to trash', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final seeded = await seedReview(harness);
    await tester.pumpWidget(wrap(harness, seeded.task.id));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('discardImportDraftButton')));
    await tester.pumpAndSettle();
    expect(find.text('放弃这份 AI 草稿？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDiscardImportDraftButton')));
    await tester.pumpAndSettle();

    final task = await harness.root.backend.getImportTask(seeded.task.id);
    final trashed = harness.recipeRepository.recipes[seeded.recipe.id]!;
    expect(task.status, ImportTaskStatus.cancelled);
    expect(trashed.deletedAt, isNotNull);
  });

  testWidgets('evidence panel explains session-only evidence limitation', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final seeded = await seedReview(harness);
    await tester.pumpWidget(wrap(harness, seeded.task.id));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('importEvidencePanel')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('importEvidencePanel')));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未提供字段与证据的一一映射'), findsOneWidget);
    expect(find.textContaining('完整原文片段未在本次会话中保留'), findsOneWidget);
  });

  testWidgets('regenerate button is disabled without session evidence', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final seeded = await seedReview(harness);
    // 不传 evidence，模拟重启后进入草稿确认页。
    await tester.pumpWidget(wrap(harness, seeded.task.id));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('regenerateImportDraftButton')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('regenerateImportDraftButton')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('原始内容已过期，无法重新生成'), findsOneWidget);

    // 禁用状态下点击不应弹出确认框。
    await tester.tap(find.byKey(const Key('regenerateImportDraftButton')));
    await tester.pumpAndSettle();
    expect(find.text('重新生成这份 AI 草稿？'), findsNothing);
  });

  testWidgets(
    'regenerate asks for confirmation and keeps the draft when LLM is '
    'not configured',
    (tester) async {
      final harness = await createHarness(tester);
      final seeded = await seedReview(harness);
      await tester.pumpWidget(
        wrap(harness, seeded.task.id, evidence: sampleEvidence()),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('regenerateImportDraftButton')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('regenerateImportDraftButton')));
      await tester.pumpAndSettle();
      expect(find.text('重新生成这份 AI 草稿？'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('confirmRegenerateImportDraftButton')),
      );
      await tester.pumpAndSettle();

      // 组合根未配置 LLM，重新生成应返回稳定错误，任务与旧草稿保持不变。
      expect(find.textContaining('请先配置 AI API 地址'), findsOneWidget);
      final task = await harness.root.backend.getImportTask(seeded.task.id);
      expect(task.status, ImportTaskStatus.needsReview);
      final recipe = await harness.root.backend.getRecipe(seeded.recipe.id);
      expect(recipe.title, '原始 AI 菜名');
    },
  );

  testWidgets('shows imported cover images on review and saves them', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final seeded = await seedReview(harness);
    // 模拟链接导入自动获取的本地配图（IMPORT-006 写入草稿）。
    harness.recipeRepository.recipes[seeded.recipe.id] = _recipeWithImages(
      seeded.recipe,
    );
    await tester.pumpWidget(wrap(harness, seeded.task.id));
    await tester.pumpAndSettle();

    // 草稿确认页直接展示配图数量徽标。
    expect(find.text('2 张'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveImportDraftButton')));
    await tester.pumpAndSettle();

    final saved = await harness.root.backend.getRecipe(seeded.recipe.id);
    expect(saved.images, <String>['/covers/draft-1/0.jpg', '/covers/draft-1/1.jpg']);
    expect(saved.coverImage, '/covers/draft-1/0.jpg');
  });

  testWidgets('groups ingredients by AI group name on review', (tester) async {
    final harness = await createHarness(tester);
    final seeded = await seedReview(harness);
    harness.recipeRepository.recipes[seeded.recipe.id] = _recipeWithGroups(
      seeded.recipe,
    );
    await tester.pumpWidget(wrap(harness, seeded.task.id));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('importIngredientName-0')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('主料'), findsWidgets);
    expect(find.text('调料'), findsOneWidget);
  });

  testWidgets('shows a notice when cover images could not be fetched', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final seeded = await seedReview(harness);
    // 原文包含图片，但草稿未获得本地封面（下载失败）时显示提示。
    await tester.pumpWidget(
      wrap(
        harness,
        seeded.task.id,
        evidence: sampleEvidenceWithImage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('笔记配图暂未获取'), findsOneWidget);
  });

  testWidgets('allows adding and editing ingredient group on review', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final seeded = await seedReview(harness);
    await tester.pumpWidget(wrap(harness, seeded.task.id));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('importIngredientGroup-0')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 点常用分组 chip 快速填入。
    await tester.tap(find.widgetWithText(ChoiceChip, '调料').first);
    await tester.pump();
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('importIngredientGroup-0')),
    );
    expect(field.controller!.text, '调料');

    // 保存后分组写入草稿。
    await tester.tap(find.byKey(const Key('saveImportDraftButton')));
    await tester.pumpAndSettle();
    final saved = await harness.root.backend.getRecipe(seeded.recipe.id);
    expect(saved.ingredients.single.groupName, '调料');
  });
}

/// 复制菜谱并携带本地配图，模拟链接导入自动获取的封面。
Recipe _recipeWithImages(Recipe recipe) => Recipe(
  id: recipe.id,
  userId: recipe.userId,
  title: recipe.title,
  description: recipe.description,
  coverImage: '/covers/draft-1/0.jpg',
  images: const <String>['/covers/draft-1/0.jpg', '/covers/draft-1/1.jpg'],
  servings: recipe.servings,
  prepTimeMinutes: recipe.prepTimeMinutes,
  cookTimeMinutes: recipe.cookTimeMinutes,
  totalTimeMinutes: recipe.totalTimeMinutes,
  difficulty: recipe.difficulty,
  notes: recipe.notes,
  favorite: recipe.favorite,
  status: recipe.status,
  sourceId: recipe.sourceId,
  ingredients: recipe.ingredients,
  steps: recipe.steps,
  categoryIds: recipe.categoryIds,
  tags: recipe.tags,
  createdAt: recipe.createdAt,
  updatedAt: recipe.updatedAt,
  localVersion: recipe.localVersion,
  deletedAt: recipe.deletedAt,
);

/// 复制菜谱并把食材改成带 AI 分组（主料/调料）。
Recipe _recipeWithGroups(Recipe recipe) => Recipe(
  id: recipe.id,
  userId: recipe.userId,
  title: recipe.title,
  description: recipe.description,
  coverImage: recipe.coverImage,
  images: recipe.images,
  servings: recipe.servings,
  prepTimeMinutes: recipe.prepTimeMinutes,
  cookTimeMinutes: recipe.cookTimeMinutes,
  totalTimeMinutes: recipe.totalTimeMinutes,
  difficulty: recipe.difficulty,
  notes: recipe.notes,
  favorite: recipe.favorite,
  status: recipe.status,
  sourceId: recipe.sourceId,
  ingredients: <Ingredient>[
    Ingredient(
      id: 'group-i-1',
      name: '鸡腿肉',
      groupName: '主料',
      quantity: '500',
      unit: 'g',
      sortOrder: 0,
    ),
    Ingredient(
      id: 'group-i-2',
      name: '盐',
      groupName: '调料',
      quantity: '1',
      unit: '勺',
      sortOrder: 1,
    ),
    Ingredient(
      id: 'group-i-3',
      name: '生抽',
      groupName: '调料',
      quantity: '2',
      unit: '勺',
      sortOrder: 2,
    ),
  ],
  steps: recipe.steps,
  categoryIds: recipe.categoryIds,
  tags: recipe.tags,
  createdAt: recipe.createdAt,
  updatedAt: recipe.updatedAt,
  localVersion: recipe.localVersion,
  deletedAt: recipe.deletedAt,
);

/// 构造与种子任务来源匹配的会话原文证据。
ImportContent sampleEvidence() {
  final source = ImportSourceLink.parse(
    'https://www.xiaohongshu.com/explore/3',
  );
  return ImportContent(
    source: source,
    resolvedUrl: source.normalizedUrl,
    contentType: ImportContentType.article,
    title: '原始 AI 菜名',
    capturedAt: DateTime.utc(2026, 8, 2, 10),
    textFragments: <ImportTextFragment>[
      ImportTextFragment(
        kind: ImportTextFragmentKind.body,
        text: '番茄切块，热油翻炒。',
        order: 0,
      ),
    ],
    media: const <ImportMediaReference>[],
    warnings: const <ImportContentWarning>{},
  );
}

/// 带配图的会话原文证据（用于配图下载失败提示测试）。
ImportContent sampleEvidenceWithImage() {
  final source = ImportSourceLink.parse(
    'https://www.xiaohongshu.com/explore/3',
  );
  return ImportContent(
    source: source,
    resolvedUrl: source.normalizedUrl,
    contentType: ImportContentType.mixed,
    title: '原始 AI 菜名',
    capturedAt: DateTime.utc(2026, 8, 2, 10),
    textFragments: <ImportTextFragment>[
      ImportTextFragment(
        kind: ImportTextFragmentKind.body,
        text: '番茄切块，热油翻炒。',
        order: 0,
      ),
    ],
    media: <ImportMediaReference>[
      ImportMediaReference(
        kind: ImportMediaKind.image,
        remoteUrl: 'https://example.com/note-cover.jpg',
        order: 0,
      ),
    ],
    warnings: const <ImportContentWarning>{},
  );
}
