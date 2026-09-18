import 'package:ai_recipe/application/inventory/inventory_use_cases.dart';
import 'package:ai_recipe/domain/inventory/inventory_batch.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

/// 推荐匹配计算性能测试（解决方案.md 第七节目标：1000 条菜谱首批 ≤1s）。
///
/// 直接在内存构造 1000 道菜谱 + 100 个库存批次，测量纯匹配耗时。
/// 该测试走 [InventoryRecommendationUseCases.recommend]（直算），
/// 不含数据库读取与 Isolate 开销；耗时只打印不做环境硬断言，
/// 正确性（能命中番茄炒蛋类菜谱）做断言。
///
/// 运行方式（项目负责人执行）：
/// ```sh
/// flutter test --no-pub test/performance/recommendation_perf_test.dart
/// ```
void main() {
  final now = DateTime.utc(2026, 8, 5, 10);
  var id = 0;

  String nextId() => 'perf-reco-${id += 1}';

  /// 构造一道菜谱：标题含主食材名，食材里包含 2~3 个公共食材
  /// （鸡蛋/盐 等，用于验证标准化器缓存与缺 1/缺 2 分组）。
  Recipe recipe(String title, List<String> ingredients) {
    final now2 = now.add(Duration(minutes: id));
    return Recipe(
      id: nextId(),
      title: title,
      status: RecipeStatus.published,
      ingredients: ingredients
          .indexed
          .map(
            (entry) => Ingredient(
              id: nextId(),
              name: entry.$2,
              quantity: '${(entry.$1 % 5) + 1} 份',
              sortOrder: entry.$1,
            ),
          )
          .toList(),
      steps: const <RecipeStep>[],
      createdAt: now2,
      updatedAt: now2,
    );
  }

  InventoryBatch batch(String name) {
    return InventoryBatch(
      id: nextId(),
      ingredientName: name,
      quantity: 10,
      unit: '份',
      zone: InventoryZone.chilled,
      status: InventoryBatchStatus.available,
      createdAt: now,
      updatedAt: now,
      localVersion: 1,
    );
  }

  test('1000 条菜谱 + 100 个库存批次的纯匹配耗时', () {
    // 100 个库存批次（含常见食材，覆盖别名/规格/家族解析路径）。
    final batches = <InventoryBatch>[
      for (var i = 0; i < 100; i++) batch('库存食材$i'),
      batch('鸡蛋'),
      batch('番茄'),
      batch('精瘦肉'),
      batch('青椒'),
      batch('香菇'),
      batch('鲈鱼'),
      batch('小白菜'),
      batch('盐'),
      batch('油'),
      batch('姜'),
    ];

    // 1000 道菜谱：每道含 1 个特有食材 + 若干公共食材（鸡蛋/盐/油/姜…）。
    const common = <String>['鸡蛋', '盐', '油', '姜', '葱', '蒜'];
    final recipes = <Recipe>[
      for (var i = 0; i < 1000; i++)
        recipe(
          '性能测试菜$i',
          <String>[
            '特有食材$i',
            ...common.take(3 + (i % 3)),
          ],
        ),
      // 确保"番茄炒蛋"能真正命中：选中番茄+鸡蛋后应出现在结果里。
      recipe('番茄炒蛋', <String>['番茄', '鸡蛋', '盐', '油']),
      recipe('青椒炒肉', <String>['青椒', '精瘦肉', '盐', '油']),
      recipe('香菇炖鸡', <String>['香菇', '鸡肉', '盐', '姜']),
    ];

    // 冷启动一次（构建词典/正则），不计入测量。
    InventoryRecommendationUseCases().recommend(
      selectedNames: const <String>{'鸡蛋', '番茄'},
      recipes: <Recipe>[recipes.last],
      batches: batches,
      now: now,
    );

    // 测量：选中番茄+鸡蛋（公共食材多，命中面大）。
    final watch = Stopwatch()..start();
    final results = InventoryRecommendationUseCases().recommend(
      selectedNames: const <String>{'鸡蛋', '番茄'},
      recipes: recipes,
      batches: batches,
      now: now,
    );
    watch.stop();

    // 正确性：番茄炒蛋应命中且不是缺失。
    final tomatoEgg = results.firstWhere((r) => r.recipe.title == '番茄炒蛋');
    expect(tomatoEgg.shortageCount, 0);

    print(
      '[Perf][Recommendation] 1000 道菜谱匹配耗时：'
      '${watch.elapsedMilliseconds} ms，结果 ${results.length} 条'
      '（番茄炒蛋 missing=${tomatoEgg.missingCount}）',
    );
  }, tags: const <String>['perf']);
}
