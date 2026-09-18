import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/application/recipe/recipe_library_use_cases.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_recipe_library_repository.dart';

void main() {
  late MemoryRecipeLibraryRepository repository;
  late RecipeLibraryUseCases useCases;
  late DateTime now;
  late int idSequence;

  String nextId() => 'local-${idSequence++}';

  RecipeDraftInput draft({
    String title = '番茄炒蛋',
    bool favorite = false,
    RecipeStatus status = RecipeStatus.draft,
    List<String> categoryIds = const <String>[],
    List<String> tags = const <String>[],
    List<RecipeIngredientInput>? ingredients,
    List<RecipeStepInput>? steps,
  }) {
    return RecipeDraftInput(
      title: title,
      description: '快手家常菜',
      favorite: favorite,
      status: status,
      categoryIds: categoryIds,
      tags: tags,
      ingredients:
          ingredients ??
          <RecipeIngredientInput>[
            RecipeIngredientInput(
              name: '鸡蛋',
              quantity: '2',
              unit: '个',
              groupName: '主料',
              preparation: '打散',
            ),
          ],
      steps:
          steps ??
          const <RecipeStepInput>[
            RecipeStepInput(description: '炒至凝固', durationSeconds: 180),
          ],
    );
  }

  setUp(() {
    repository = MemoryRecipeLibraryRepository();
    now = DateTime.utc(2026, 7, 28, 8);
    idSequence = 1;
    useCases = RecipeLibraryUseCases(
      recipeRepository: repository,
      categoryRepository: repository,
      idGenerator: nextId,
      clock: () => now,
    );
  });

  test('guest creates a local draft with application-owned ids', () async {
    final category = await useCases.createCategory(
      const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
    );

    final recipe = await useCases.createRecipe(
      draft(categoryIds: <String>[category.id]),
    );

    expect(recipe.id, 'local-2');
    expect(recipe.userId, isNull);
    expect(recipe.status, RecipeStatus.draft);
    expect(recipe.createdAt, now);
    expect(recipe.updatedAt, now);
    expect(recipe.localVersion, 1);
    expect(recipe.ingredients.single.id, 'local-3');
    expect(recipe.ingredients.single.sortOrder, 0);
    expect(recipe.steps.single.id, 'local-4');
    expect(recipe.steps.single.stepNumber, 1);
    expect(recipe.categoryIds, <String>[category.id]);
    expect(await useCases.getRecipe(recipe.id), same(recipe));
  });

  test(
    'update preserves identity and creates ids only for new children',
    () async {
      final created = await useCases.createRecipe(
        draft(),
        sourceId: 'manual-source',
      );
      now = now.add(const Duration(minutes: 5));

      final updated = await useCases.updateRecipe(
        created.id,
        draft(
          title: '番茄炒蛋升级版',
          ingredients: <RecipeIngredientInput>[
            RecipeIngredientInput(
              id: created.ingredients.single.id,
              name: '鸡蛋',
            ),
            RecipeIngredientInput(name: '番茄', quantity: '3', unit: '个'),
          ],
          steps: <RecipeStepInput>[
            RecipeStepInput(id: created.steps.single.id, description: '加入番茄翻炒'),
          ],
        ),
      );

      expect(updated.id, created.id);
      expect(updated.createdAt, created.createdAt);
      expect(updated.updatedAt, now);
      expect(updated.sourceId, 'manual-source');
      expect(updated.localVersion, 2);
      expect(updated.ingredients.first.id, created.ingredients.first.id);
      expect(updated.ingredients.last.id, 'local-4');
      expect(updated.ingredients.map((item) => item.sortOrder), <int>[0, 1]);
      expect(updated.steps.single.id, created.steps.single.id);
    },
  );

  test('update rejects child ids that do not belong to the recipe', () async {
    final created = await useCases.createRecipe(draft());

    await expectLater(
      useCases.updateRecipe(
        created.id,
        draft(
          ingredients: <RecipeIngredientInput>[
            RecipeIngredientInput(id: 'foreign-id', name: '盐'),
          ],
        ),
      ),
      throwsA(isA<RecipeLibraryValidationException>()),
    );
  });

  test('updateRecipeStepDuration updates only the target step duration', () async {
    final created = await useCases.createRecipe(
      draft(
        steps: const <RecipeStepInput>[
          RecipeStepInput(description: '炒蛋', durationSeconds: 180),
          RecipeStepInput(description: '摆盘'),
        ],
      ),
    );
    final target = created.steps.last; // 无时长的步骤
    now = now.add(const Duration(minutes: 5));

    final updated = await useCases.updateRecipeStepDuration(
      created.id,
      target.id,
      90,
    );

    expect(updated.id, created.id);
    expect(updated.localVersion, 2);
    expect(updated.updatedAt, now);
    expect(updated.favorite, created.favorite);
    // 目标步骤时长被更新，其他步骤不变。
    final updatedTarget = updated.steps.singleWhere((step) => step.id == target.id);
    expect(updatedTarget.durationSeconds, 90);
    expect(updatedTarget.description, '摆盘');
    final untouched = updated.steps.singleWhere((step) => step.id != target.id);
    expect(untouched.durationSeconds, 180);
    // 持久化：重新读取仍是新时长。
    final reloaded = await useCases.getRecipe(created.id);
    expect(
      reloaded.steps.singleWhere((step) => step.id == target.id).durationSeconds,
      90,
    );
  });

  test('updateRecipeStepDuration rejects invalid duration', () async {
    final created = await useCases.createRecipe(draft());

    await expectLater(
      useCases.updateRecipeStepDuration(
        created.id,
        created.steps.single.id,
        0,
      ),
      throwsA(isA<RecipeLibraryValidationException>()),
    );
  });

  test('updateRecipeStepDuration rejects a step that does not belong', () async {
    final created = await useCases.createRecipe(draft());

    await expectLater(
      useCases.updateRecipeStepDuration(created.id, 'foreign-step', 60),
      throwsA(isA<RecipeLibraryValidationException>()),
    );
  });

  test(
    'missing and deleted categories are rejected before recipe write',
    () async {
      await expectLater(
        useCases.createRecipe(draft(categoryIds: const <String>['missing'])),
        throwsA(isA<RecipeCategoryNotFoundException>()),
      );

      final category = await useCases.createCategory(
        const RecipeCategoryInput(name: '早餐', sortOrder: 0),
      );
      await useCases.softDeleteCategory(category.id);

      await expectLater(
        useCases.createRecipe(draft(categoryIds: <String>[category.id])),
        throwsA(isA<RecipeCategoryUnavailableException>()),
      );
    },
  );

  test(
    'lists by search, favorite, status, category and deleted scope',
    () async {
      final category = await useCases.createCategory(
        const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
      );
      final tomato = await useCases.createRecipe(
        draft(
          favorite: true,
          status: RecipeStatus.published,
          categoryIds: <String>[category.id],
          ingredients: <RecipeIngredientInput>[
            RecipeIngredientInput(name: '鸡蛋'),
          ],
        ),
      );
      now = now.add(const Duration(minutes: 1));
      await useCases.createRecipe(
        draft(
          title: '咖喱鸡',
          ingredients: <RecipeIngredientInput>[
            RecipeIngredientInput(name: '咖喱块'),
          ],
        ),
      );

      expect(
        (await useCases.listRecipes(query: '鸡蛋')).map((item) => item.id),
        <String>[tomato.id],
      );
      expect(
        (await useCases.listRecipes(favorite: true)).map((item) => item.id),
        <String>[tomato.id],
      );
      expect(
        (await useCases.listRecipes(
          status: RecipeStatus.published,
        )).map((item) => item.id),
        <String>[tomato.id],
      );
      expect(
        (await useCases.listRecipes(
          categoryId: category.id,
        )).map((item) => item.id),
        <String>[tomato.id],
      );

      await useCases.softDeleteRecipe(tomato.id);
      expect(await useCases.listRecipes(), hasLength(1));
      expect(
        (await useCases.listRecipes(
          deletionFilter: RecipeLibraryDeletionFilter.deletedOnly,
        )).map((item) => item.id),
        <String>[tomato.id],
      );
    },
  );

  test('normalizes tags and searches them case-insensitively', () async {
    final tagged = await useCases.createRecipe(
      draft(
        tags: const <String>[
          '  quick  ',
          '',
          'breakfast',
          'quick',
          'BREAKFAST',
        ],
      ),
    );

    expect(tagged.tags, <String>['quick', 'breakfast']);
    expect(
      (await useCases.listRecipes(query: 'BREAKFAST')).map((item) => item.id),
      <String>[tagged.id],
    );
    expect(
      (await useCases.listRecipes(tag: ' breakfast ')).map((item) => item.id),
      <String>[tagged.id],
    );
  });

  test('copies a recipe with independent ids and draft defaults', () async {
    final source = await useCases.createRecipe(
      draft(
        title: 'Original recipe',
        favorite: true,
        status: RecipeStatus.published,
        tags: const <String>['dinner'],
      ),
      sourceId: 'source-task',
    );
    now = now.add(const Duration(minutes: 3));

    final copied = await useCases.copyRecipe(source.id);

    expect(copied.id, isNot(source.id));
    expect(copied.title, 'Original recipe \u526f\u672c');
    expect(copied.status, RecipeStatus.draft);
    expect(copied.favorite, isFalse);
    expect(copied.sourceId, source.sourceId);
    expect(copied.tags, source.tags);
    expect(copied.createdAt, now);
    expect(copied.ingredients.single.id, isNot(source.ingredients.single.id));
    expect(copied.steps.single.id, isNot(source.steps.single.id));
    expect(copied.ingredients.single.name, source.ingredients.single.name);
    expect(copied.steps.single.description, source.steps.single.description);
  });

  test('restores, permanently deletes and empties trash in batches', () async {
    final first = await useCases.createRecipe(draft(title: 'First'));
    final second = await useCases.createRecipe(draft(title: 'Second'));
    final third = await useCases.createRecipe(draft(title: 'Third'));
    await useCases.softDeleteRecipe(first.id);
    await useCases.softDeleteRecipe(second.id);
    await useCases.softDeleteRecipe(third.id);

    await useCases.restoreRecipes(<String>[first.id, first.id, second.id]);
    expect((await useCases.listRecipes()).map((item) => item.id).toSet(), {
      first.id,
      second.id,
    });

    await useCases.softDeleteRecipe(first.id);
    await useCases.softDeleteRecipe(second.id);
    await useCases.permanentlyDeleteRecipes(<String>[first.id, second.id]);
    await expectLater(
      useCases.getRecipe(first.id, includeDeleted: true),
      throwsA(isA<RecipeNotFoundException>()),
    );
    await expectLater(
      useCases.getRecipe(second.id, includeDeleted: true),
      throwsA(isA<RecipeNotFoundException>()),
    );

    expect(await useCases.emptyRecipeTrash(), 1);
    await expectLater(
      useCases.getRecipe(third.id, includeDeleted: true),
      throwsA(isA<RecipeNotFoundException>()),
    );
  });

  test('sets favorite and runs the recipe recycle-bin lifecycle', () async {
    final created = await useCases.createRecipe(draft());
    now = now.add(const Duration(minutes: 1));

    final favorite = await useCases.setRecipeFavorite(created.id, true);
    expect(favorite.favorite, isTrue);
    expect(favorite.localVersion, 2);

    await useCases.softDeleteRecipe(created.id);
    await expectLater(
      useCases.getRecipe(created.id),
      throwsA(isA<RecipeNotFoundException>()),
    );
    await useCases.restoreRecipe(created.id);
    expect((await useCases.getRecipe(created.id)).deletedAt, isNull);

    await expectLater(
      useCases.permanentlyDeleteRecipe(created.id),
      throwsA(isA<RecipeLibraryValidationException>()),
    );
    await useCases.softDeleteRecipe(created.id);
    await useCases.permanentlyDeleteRecipe(created.id);
    await expectLater(
      useCases.getRecipe(created.id, includeDeleted: true),
      throwsA(isA<RecipeNotFoundException>()),
    );
  });

  test('manages category sorting, updates and recycle bin', () async {
    final later = await useCases.createCategory(
      const RecipeCategoryInput(name: '晚餐', sortOrder: 2),
    );
    final first = await useCases.createCategory(
      const RecipeCategoryInput(name: '早餐', sortOrder: 0),
    );
    final recipe = await useCases.createRecipe(
      draft(categoryIds: <String>[first.id]),
    );

    expect((await useCases.listCategories()).map((item) => item.id), <String>[
      first.id,
      later.id,
    ]);

    now = now.add(const Duration(minutes: 1));
    final updated = await useCases.updateCategory(
      later.id,
      const RecipeCategoryInput(name: '早午餐', sortOrder: 1),
    );
    expect(updated.createdAt, later.createdAt);
    expect(updated.localVersion, 2);

    await useCases.softDeleteCategory(first.id);
    expect((await useCases.getRecipe(recipe.id)).categoryIds, isEmpty);
    expect(
      await useCases.listCategories(
        deletionFilter: RecipeLibraryDeletionFilter.deletedOnly,
      ),
      hasLength(1),
    );
    await useCases.restoreCategory(first.id);
    expect(await useCases.getCategory(first.id), isNotNull);
    expect((await useCases.getRecipe(recipe.id)).categoryIds, isEmpty);

    await expectLater(
      useCases.permanentlyDeleteCategory(first.id),
      throwsA(isA<RecipeLibraryValidationException>()),
    );
    await useCases.softDeleteCategory(first.id);
    await useCases.permanentlyDeleteCategory(first.id);
    await expectLater(
      useCases.getCategory(first.id, includeDeleted: true),
      throwsA(isA<RecipeCategoryNotFoundException>()),
    );
  });

  test(
    'maps invalid recipe and category inputs to validation errors',
    () async {
      await expectLater(
        useCases.createRecipe(draft(title: '   ')),
        throwsA(isA<RecipeLibraryValidationException>()),
      );
      await expectLater(
        useCases.createRecipe(
          draft(
            ingredients: <RecipeIngredientInput>[
              RecipeIngredientInput(name: '   '),
            ],
          ),
        ),
        throwsA(isA<RecipeLibraryValidationException>()),
      );
      await expectLater(
        useCases.createCategory(
          const RecipeCategoryInput(name: '   ', sortOrder: 0),
        ),
        throwsA(isA<RecipeLibraryValidationException>()),
      );
      await expectLater(
        useCases.createCategory(
          const RecipeCategoryInput(name: '分类', sortOrder: -1),
        ),
        throwsA(isA<RecipeLibraryValidationException>()),
      );
    },
  );

  test('rejects duplicate categories and invalid generated ids', () async {
    final category = await useCases.createCategory(
      const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
    );
    await expectLater(
      useCases.createRecipe(
        draft(categoryIds: <String>[category.id, ' ${category.id} ']),
      ),
      throwsA(isA<RecipeLibraryValidationException>()),
    );

    final emptyIdUseCases = RecipeLibraryUseCases(
      recipeRepository: repository,
      categoryRepository: repository,
      idGenerator: () => '   ',
      clock: () => now,
    );
    await expectLater(
      emptyIdUseCases.createRecipe(draft()),
      throwsA(isA<RecipeLibraryIdGenerationException>()),
    );

    final throwingIdUseCases = RecipeLibraryUseCases(
      recipeRepository: repository,
      categoryRepository: repository,
      idGenerator: () => throw StateError('internal generator failure'),
      clock: () => now,
    );
    await expectLater(
      throwingIdUseCases.createCategory(
        const RecipeCategoryInput(name: '早餐', sortOrder: 0),
      ),
      throwsA(isA<RecipeLibraryIdGenerationException>()),
    );
  });

  test(
    'no-op favorite and restore calls do not advance local versions',
    () async {
      final recipe = await useCases.createRecipe(draft());
      final category = await useCases.createCategory(
        const RecipeCategoryInput(name: '收藏夹', sortOrder: 0),
      );

      final unchanged = await useCases.setRecipeFavorite(recipe.id, false);
      expect(unchanged, same(recipe));
      expect(unchanged.localVersion, 1);

      await useCases.restoreRecipe(recipe.id);
      await useCases.restoreCategory(category.id);
      expect((await useCases.getRecipe(recipe.id)).localVersion, 1);
      expect((await useCases.getCategory(category.id)).localVersion, 1);
    },
  );
  test('masks repository failures behind a stable storage error', () async {
    repository.error = StateError('sqlite path and internal statement');

    await expectLater(
      useCases.listRecipes(),
      throwsA(
        isA<RecipeLibraryStorageException>().having(
          (error) => error.message,
          'message',
          isNot(contains('sqlite')),
        ),
      ),
    );
  });
}
