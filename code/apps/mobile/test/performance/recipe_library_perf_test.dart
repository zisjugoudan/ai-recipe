import 'dart:io';

import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/application/recipe/recipe_library_use_cases.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 菜谱库读取性能测试：插入 1000 条 mock 菜谱，测量读取耗时。
///
/// 运行方式（项目负责人执行）：
/// ```sh
/// flutter test --no-pub test/performance/recipe_library_perf_test.dart
/// ```
/// 或只跑性能组：`flutter test --no-pub --tags perf ...`。
///
/// 耗时只打印不做环境相关硬断言；正确性（条数/过滤命中）做断言。
void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteRecipeRepository repository;
  late RecipeLibraryUseCases useCases;
  late DateTime now;
  var idSequence = 1;

  String nextId() => 'perf-${idSequence++}';

  RecipeLibraryUseCases buildUseCases() {
    return RecipeLibraryUseCases(
      recipeRepository: repository,
      categoryRepository: repository,
      idGenerator: nextId,
      clock: () => now,
    );
  }

  /// 构造第 [index] 条 mock 菜谱（偶数条收藏，便于过滤测试）。
  RecipeDraftInput draft(int index) {
    return RecipeDraftInput(
      title: '性能测试菜谱 $index',
      description: '用于读取效率测试的第 $index 道菜谱',
      notes: '性能测试用数据',
      favorite: index.isEven,
      status: RecipeStatus.published,
      categoryIds: const <String>[],
      tags: const <String>['perf'],
      ingredients: <RecipeIngredientInput>[
        RecipeIngredientInput(
          name: '食材$index',
          quantity: '$index',
          unit: '克',
          groupName: '主料',
          preparation: '洗净',
          substitutes: const <String>[],
        ),
      ],
      steps: const <RecipeStepInput>[
        RecipeStepInput(
          description: '步骤一',
          durationSeconds: 60,
          heatLevel: '中火',
          cookware: '炒锅',
        ),
        RecipeStepInput(
          description: '步骤二',
          durationSeconds: 120,
          heatLevel: '小火',
          cookware: '炒锅',
        ),
      ],
    );
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_perf_',
    );
    databasePath = path.join(temporaryDirectory.path, 'recipes.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteRecipeRepository(appDatabase);
    now = DateTime.utc(2026, 8, 5, 10);
    idSequence = 1;
    useCases = buildUseCases();
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('插入 1000 条菜谱并测量 listRecipes 读取耗时', () async {
    const count = 1000;

    // 插入 1000 条 published 菜谱，记录总耗时。
    final insertWatch = Stopwatch()..start();
    for (var index = 0; index < count; index++) {
      await useCases.createRecipe(draft(index));
    }
    insertWatch.stop();
    print(
      '[Perf][RecipeLibrary] 插入 $count 条耗时：'
      '${insertWatch.elapsedMilliseconds} ms',
    );

    // 全量读取：首次（冷）+ 后续 4 次取平均。
    final readTimes = <int>[];
    for (var round = 0; round < 5; round++) {
      final watch = Stopwatch()..start();
      final recipes = await useCases.listRecipes();
      watch.stop();
      readTimes.add(watch.elapsedMilliseconds);
      // 正确性：1000 条全部读出且未丢失。
      expect(recipes.length, count, reason: '全量读取应返回 $count 条');
    }
    final first = readTimes.first;
    final warmed = readTimes.skip(1);
    final average = warmed.reduce((a, b) => a + b) ~/ warmed.length;
    print(
      '[Perf][RecipeLibrary] listRecipes 全量：首次 $first ms，'
      '预热后平均 $average ms，5 次明细=$readTimes',
    );

    // 收藏过滤：偶数条为收藏，应命中 500 条。
    final favoriteWatch = Stopwatch()..start();
    final favorites = await useCases.listRecipes(favorite: true);
    favoriteWatch.stop();
    expect(favorites.length, count ~/ 2);
    print(
      '[Perf][RecipeLibrary] listRecipes(favorite: true) 耗时：'
      '${favoriteWatch.elapsedMilliseconds} ms，命中 ${favorites.length} 条',
    );

    // 关键词搜索：精确命中 1 条。
    final searchWatch = Stopwatch()..start();
    final searched = await useCases.listRecipes(query: '性能测试菜谱 500');
    searchWatch.stop();
    expect(searched.length, 1);
    print(
      '[Perf][RecipeLibrary] listRecipes(query) 耗时：'
      '${searchWatch.elapsedMilliseconds} ms，命中 ${searched.length} 条',
    );
  }, tags: const <String>['perf']);

  test('摘要分页与总数（解决方案.md：列表页不再读取完整聚合）', () async {
    const count = 1000;
    for (var index = 0; index < count; index++) {
      await useCases.createRecipe(draft(index));
    }

    // 第一页摘要（40 条）+ 总数。
    final firstWatch = Stopwatch()..start();
    final first = await useCases.listRecipeSummaries(limit: 40);
    final total = await useCases.countRecipes();
    firstWatch.stop();
    expect(first.items.length, 40);
    expect(first.hasMore, isTrue);
    expect(total, count);
    print(
      '[Perf][RecipeLibrary] 摘要第一页 40 条 + 总数耗时：'
      '${firstWatch.elapsedMilliseconds} ms，total=$total',
    );

    // 游标翻页 25 次读完 1000 条（keyset pagination）。
    var page = first;
    var loaded = page.items.length;
    var cursor = page.nextCursor;
    final pageWatch = Stopwatch()..start();
    while (page.hasMore && cursor != null) {
      page = await useCases.listRecipeSummaries(limit: 40, after: cursor);
      loaded += page.items.length;
      cursor = page.nextCursor;
    }
    pageWatch.stop();
    expect(loaded, count, reason: '游标翻页应读完全部 $count 条');
    print(
      '[Perf][RecipeLibrary] 游标翻页读完全部 $count 条耗时：'
      '${pageWatch.elapsedMilliseconds} ms（页数 ${(loaded / 40).ceil()}）',
    );

    // 名称排序（title COLLATE NOCASE）首屏。
    final titleWatch = Stopwatch()..start();
    final titlePage = await useCases.listRecipeSummaries(
      limit: 40,
      sort: RecipeSort.title,
    );
    titleWatch.stop();
    expect(titlePage.items, hasLength(40));
    print(
      '[Perf][RecipeLibrary] 名称排序第一页耗时：'
      '${titleWatch.elapsedMilliseconds} ms',
    );
  }, tags: const <String>['perf']);
}
