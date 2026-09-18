import 'package:ai_recipe/application/inventory/inventory_use_cases.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_canonicalizer.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
import 'package:ai_recipe/domain/inventory/inventory_batch.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_inventory_repository.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 8);

  (InventoryLibraryUseCases, MemoryInventoryRepository) build() {
    var id = 0;
    final repository = MemoryInventoryRepository();
    final useCases = InventoryLibraryUseCases(
      repository: repository,
      idGenerator: () => 'batch-${id += 1}',
      clock: () => now,
    );
    return (useCases, repository);
  }

  InventoryBatch sample({
    required String name,
    required InventoryZone zone,
    double? quantity,
    DateTime? expiresAt,
  }) {
    return InventoryBatch(
      id: 'batch-$name-$zone',
      ingredientName: name,
      quantity: quantity,
      zone: zone,
      status: InventoryBatchStatus.available,
      createdAt: now,
      updatedAt: now,
      localVersion: 1,
      expiresAt: expiresAt,
    );
  }

  test('creates batch and records create change', () async {
    final (useCases, repository) = build();
    final batch = await useCases.createBatch(
      const InventoryBatchInput(
        ingredientName: '番茄',
        quantity: 2,
        unit: '个',
        zone: InventoryZone.chilled,
      ),
    );
    expect(batch.status, InventoryBatchStatus.available);
    expect(batch.localVersion, 1);
    final changes = await repository.listChanges(batchId: batch.id);
    expect(changes.single.changeType, InventoryChangeType.create);
    expect(changes.single.confirmedByUser, isTrue);
  });

  test('empty quantity saves as unknown, never 0', () async {
    final (useCases, _) = build();
    final batch = await useCases.createBatch(
      const InventoryBatchInput(
        ingredientName: '冰糖',
        zone: InventoryZone.roomTemperature,
      ),
    );
    expect(batch.quantity, isNull);
    expect(batch.hasUnknownQuantity, isTrue);
  });

  test('summary counts soon, expired and unknown', () async {
    final (useCases, repository) = build();
    await repository.upsertBatch(
      sample(name: '牛奶', zone: InventoryZone.chilled, quantity: 1),
    );
    await repository.upsertBatch(
      sample(
        name: '番茄',
        zone: InventoryZone.chilled,
        quantity: 2,
        expiresAt: DateTime.utc(2026, 8, 5),
      ),
    );
    await repository.upsertBatch(
      sample(
        name: '菠菜',
        zone: InventoryZone.chilled,
        quantity: 1,
        expiresAt: DateTime.utc(2026, 8, 1),
      ),
    );
    await repository.upsertBatch(
      sample(name: '冰糖', zone: InventoryZone.roomTemperature),
    );
    final summary = await useCases.loadSummary();
    expect(summary.availableBatches, 4);
    expect(summary.soonExpiring, 1); // 番茄 08-05（now 08-04，临期）
    expect(summary.expired, 1); // 菠菜
    expect(summary.unknownQuantity, 1); // 冰糖
  });

  test('aggregates same-name batches and picks worst condition', () async {
    final (useCases, repository) = build();
    await repository.upsertBatch(
      sample(name: '番茄', zone: InventoryZone.chilled, quantity: 1),
    );
    await repository.upsertBatch(
      sample(
        name: '番茄',
        zone: InventoryZone.chilled,
        quantity: 2,
        expiresAt: DateTime.utc(2026, 8, 1),
      ),
    );
    final items = await useCases.loadAggregated();
    expect(items, hasLength(1));
    expect(items.single.batchCount, 2);
    expect(items.single.condition, InventoryItemCondition.expired);
    expect(items.single.summary, contains('2 批次'));
  });

  test('marks used up and discard record change', () async {
    final (useCases, repository) = build();
    final batch = await useCases.createBatch(
      const InventoryBatchInput(
        ingredientName: '鸡蛋',
        quantity: 6,
        unit: '枚',
        zone: InventoryZone.chilled,
      ),
    );
    final usedUp = await useCases.useUpBatch(batch.id);
    expect(usedUp.status, InventoryBatchStatus.usedUp);
    final changes = await repository.listChanges(batchId: batch.id);
    expect(changes.last.changeType, InventoryChangeType.usedUp);
  });

  group('recommendation', () {
    Ingredient ing(String name, {bool optional = false, String? quantity}) {
      return Ingredient(
        id: 'ing-$name',
        name: name,
        sortOrder: 0,
        optional: optional,
        quantity: quantity,
      );
    }

    Recipe recipe(String title, List<Ingredient> ingredients) {
      return Recipe(
        id: 'recipe-$title',
        title: title,
        ingredients: ingredients,
        status: RecipeStatus.published,
        createdAt: now,
        updatedAt: now,
        localVersion: 1,
      );
    }

    test('matches selected and in-fridge-not-selected ingredients', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '番茄', zone: InventoryZone.chilled, quantity: 2),
      );
      await repository.upsertBatch(
        sample(name: '鸡蛋', zone: InventoryZone.chilled, quantity: 6),
      );
      final recipes = <Recipe>[
        recipe('番茄炒蛋', <Ingredient>[ing('番茄'), ing('鸡蛋')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results, hasLength(1));
      final result = results.single;
      expect(result.selectedHit, <String>['番茄']);
      expect(result.inFridgeNotSelected, <String>['鸡蛋']);
      expect(result.missing, isEmpty);
      expect(result.missingCount, 0);
    });

    test('missing ingredient puts recipe into miss-1 group', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '番茄', zone: InventoryZone.chilled, quantity: 2),
      );
      final recipes = <Recipe>[
        recipe('番茄炒蛋', <Ingredient>[ing('番茄'), ing('鸡蛋')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.missing, <String>['鸡蛋']);
      expect(results.single.missingCount, 1);
    });

    test('optional ingredients and staples are not counted as missing',
        () async {
      final (useCases, repository) = build();
      final recipes = <Recipe>[
        recipe(
          '照烧鸡腿',
          <Ingredient>[
            ing('鸡腿'),
            ing('生抽'),
            ing('冰糖'),
            ing('芝麻', optional: true),
          ],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.missing, <String>['鸡腿']);
    });

    test('expired batches are not matched', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(
          name: '番茄',
          zone: InventoryZone.chilled,
          quantity: 2,
          expiresAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final recipes = <Recipe>[
        recipe('番茄炒蛋', <Ingredient>[ing('番茄'), ing('鸡蛋')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.missing, containsAll(<String>['番茄', '鸡蛋']));
    });

    test('matches synonyms 西红柿 ↔ 番茄 via canonical id', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '西红柿', zone: InventoryZone.chilled, quantity: 2),
      );
      final recipes = <Recipe>[
        recipe('番茄炒蛋', <Ingredient>[ing('番茄'), ing('鸡蛋')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'西红柿'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.selectedHit, <String>['番茄']);
      // 鸡蛋 未收录基础食材且冰箱无该批次 → 缺失（而非“冰箱未选”）。
      expect(result.missing, <String>['鸡蛋']);
      expect(result.inFridgeNotSelected, isEmpty);
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '番茄',
      );
      // 卡片解释：西红柿 → 番茄（同义词匹配）
      expect(detail.matchType, IngredientMatchType.exact);
      expect(detail.canonicalName, '番茄');
    });

    test('format normalization matches bracketed name', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '番茄', zone: InventoryZone.chilled, quantity: 2),
      );
      final recipes = <Recipe>[
        recipe('番茄炒蛋', <Ingredient>[ing('番茄（新鲜）'), ing('鸡蛋')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.missing, <String>['鸡蛋']);
    });

    test('similar ingredient 小番茄 does not satisfy 番茄', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '小番茄', zone: InventoryZone.chilled, quantity: 2),
      );
      final recipes = <Recipe>[
        recipe('番茄炒蛋', <Ingredient>[ing('番茄'), ing('鸡蛋')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'小番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.missing, containsAll(<String>['番茄', '鸡蛋']));
    });

    test('deduplicates ingredients by canonical id', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '西红柿', zone: InventoryZone.chilled, quantity: 2),
      );
      final recipes = <Recipe>[
        recipe(
          '番茄炒蛋',
          <Ingredient>[ing('番茄'), ing('西红柿'), ing('鸡蛋')],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'西红柿'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      // 番茄与西红柿映射到同一标准 ID，只计一种命中。
      expect(results.single.selectedHit.length, 1);
      // 鸡蛋 未收录基础食材且冰箱无该批次 → 缺失。
      expect(results.single.missing, <String>['鸡蛋']);
    });

    test('strictSelected treats unselected fridge ingredients as missing',
        () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '番茄', zone: InventoryZone.chilled, quantity: 2),
      );
      await repository.upsertBatch(
        sample(name: '鸡蛋', zone: InventoryZone.chilled, quantity: 6),
      );
      final recipes = <Recipe>[
        recipe('番茄炒蛋', <Ingredient>[ing('番茄'), ing('鸡蛋')]),
      ];
      final relaxed = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(relaxed.single.missing, isEmpty);
      expect(relaxed.single.inFridgeNotSelected, <String>['鸡蛋']);

      final strict = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
        strictSelected: true,
      );
      expect(strict.single.missing, <String>['鸡蛋']);
      expect(strict.single.selectedHit, <String>['番茄']);
    });

    test('marks insufficient stock and never claims ready', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '番茄', zone: InventoryZone.chilled, quantity: 1),
      );
      final recipes = <Recipe>[
        recipe(
          '番茄炒蛋',
          <Ingredient>[ing('番茄', quantity: '3 个'), ing('鸡蛋')],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.hasInsufficientStock, isTrue);
      expect(results.single.insufficientNames, <String>['番茄']);
      final detail = results.single.matchDetails.firstWhere(
        (d) => d.rawName == '番茄',
      );
      expect(detail.sufficiency, IngredientSufficiency.insufficient);
    });

    test('marks unknown quantity as needs confirmation', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        sample(name: '番茄', zone: InventoryZone.chilled),
      );
      final recipes = <Recipe>[
        recipe(
          '番茄炒蛋',
          <Ingredient>[ing('番茄', quantity: '3 个'), ing('鸡蛋')],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'番茄'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.quantityUncertain, isTrue);
      expect(results.single.quantityUnknownNames, <String>['番茄']);
    });

    // ---- ADR-0022：基础食材 + 属性规格 + 三值匹配 ----

    /// 带规格字段的批次（用户已在录入页选择规格）。
    InventoryBatch specBatch({
      required String name,
      String? baseConceptId,
      String? baseConceptName,
      IngredientFatLevel? fatLevel,
      IngredientCut? cut,
      IngredientForm? form,
      IngredientProcessing? processing,
      double? quantity,
    }) {
      return InventoryBatch(
        id: 'batch-$name',
        ingredientName: name,
        baseConceptId: baseConceptId,
        baseConceptName: baseConceptName,
        fatLevel: fatLevel,
        cut: cut,
        form: form,
        processing: processing,
        quantity: quantity,
        zone: InventoryZone.chilled,
        status: InventoryBatchStatus.available,
        createdAt: now,
        updatedAt: now,
        localVersion: 1,
      );
    }

    test('specific inventory satisfies generic requirement (精瘦肉→猪肉)',
        () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '精瘦肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          fatLevel: IngredientFatLevel.veryLean,
          quantity: 200,
        ),
      );
      final recipes = <Recipe>[
        recipe('青椒炒肉', <Ingredient>[ing('猪肉'), ing('青椒')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'精瘦肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.selectedHit, <String>['猪肉']);
      expect(result.missing, <String>['青椒']);
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '猪肉',
      );
      expect(detail.verdict, IngredientMatchVerdict.yes);
    });

    test('generic inventory against specific requirement enters maybe (猪肉→精瘦肉)',
        () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '猪肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          quantity: 200,
        ),
      );
      final recipes = <Recipe>[
        recipe('精瘦肉炒芹菜', <Ingredient>[ing('精瘦肉'), ing('芹菜')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'猪肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.maybeNames, <String>['精瘦肉']);
      expect(result.missing, <String>['芹菜']);
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '精瘦肉',
      );
      expect(detail.verdict, IngredientMatchVerdict.maybe);
    });

    test('strictSelected keeps MAYBE substitution as hit (猪肉→精瘦肉)', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '猪肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          quantity: 200,
        ),
      );
      final recipes = <Recipe>[
        recipe('精瘦肉炒芹菜', <Ingredient>[ing('精瘦肉'), ing('芹菜')]),
      ];
      // 开启“仅使用已选食材”且未选任何食材：替代（MAYBE）仍算命中，
      // 不因未选择而判缺失，展示仍为“替代 精瘦肉→猪肉”。
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
        strictSelected: true,
      );
      final result = results.single;
      expect(result.maybeNames, contains('精瘦肉'));
      expect(result.missing, <String>['芹菜']);
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '精瘦肉',
      );
      expect(detail.verdict, IngredientMatchVerdict.maybe);
      expect(detail.kind, RecommendationMatchKind.inFridgeNotSelected);
    });

    test('fatty meat cannot satisfy very lean requirement (规格冲突 NO)',
        () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '五花肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          cut: IngredientCut.belly,
          fatLevel: IngredientFatLevel.mixed,
          quantity: 500,
        ),
      );
      final recipes = <Recipe>[
        recipe('精瘦肉炒芹菜', <Ingredient>[ing('精瘦肉'), ing('芹菜')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'五花肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.noMatchNames, <String>['精瘦肉']);
      // 芹菜 未收录基础食材且冰箱无该批次 → 缺失。
      expect(result.missing, <String>['芹菜']);
      expect(result.shortageCount, 2);
    });

    test('generic minced meat against pork mince enters maybe (肉末→猪肉末)',
        () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '肉末',
          baseConceptId: 'ingredient.meat',
          baseConceptName: '肉',
          form: IngredientForm.minced,
          quantity: 300,
        ),
      );
      final recipes = <Recipe>[
        recipe('猪肉末蒸蛋', <Ingredient>[ing('猪肉末'), ing('鸡蛋')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'肉末'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.maybeNames, <String>['猪肉末']);
      expect(result.missing, <String>['鸡蛋']);
    });

    test('user chosen batch spec is persisted on create', () async {
      final (useCases, _) = build();
      final batch = await useCases.createBatch(
        const InventoryBatchInput(
          ingredientName: '猪肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          fatLevel: IngredientFatLevel.veryLean,
          zone: InventoryZone.chilled,
          specSource: IngredientSpecSource.user,
        ),
      );
      expect(batch.baseConceptId, 'ingredient.pork');
      expect(batch.fatLevel, IngredientFatLevel.veryLean);
      expect(batch.specSource, IngredientSpecSource.user);
    });

    test('confirmed base is treated as usable for this session', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '猪肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          quantity: 200,
        ),
      );
      final recipes = <Recipe>[
        recipe('精瘦肉炒芹菜', <Ingredient>[ing('精瘦肉'), ing('芹菜')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'猪肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
        confirmedBases: const <String>{'ingredient.pork'},
      );
      final result = results.single;
      expect(result.maybeNames, isEmpty);
      expect(result.missing, <String>['芹菜']);
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '精瘦肉',
      );
      expect(detail.verdict, IngredientMatchVerdict.yes);
    });

    test('staples like 水/花椒粉/小米辣 are never counted as missing', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '瘦肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          fatLevel: IngredientFatLevel.lean,
          quantity: 200,
        ),
      );
      await repository.upsertBatch(
        specBatch(name: '豆干', quantity: 300),
      );
      final recipes = <Recipe>[
        recipe(
          '香干炒肉',
          <Ingredient>[
            ing('瘦肉'),
            ing('豆干'),
            ing('青椒'),
            ing('水'),
            ing('花椒粉'),
            ing('小米辣'),
            ing('蒜'),
          ],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'瘦肉', '豆干'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      // 水/花椒粉/小米辣/蒜均为常备，不计缺失；只缺青椒。
      expect(result.missing, <String>['青椒']);
      expect(result.shortageCount, 1);
    });

    test('unresolved batch spec falls back to name resolution', () async {
      final (useCases, repository) = build();
      // 旧数据/未落库规格：批次 base 为空，名称仍可解析为 猪肉·瘦。
      await repository.upsertBatch(
        sample(name: '瘦肉', zone: InventoryZone.chilled, quantity: 200),
      );
      final recipes = <Recipe>[
        recipe('青椒炒瘦肉', <Ingredient>[ing('瘦肉'), ing('青椒')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'瘦肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.selectedHit, <String>['瘦肉']);
      expect(result.missing, <String>['青椒']);
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '瘦肉',
      );
      expect(detail.verdict, IngredientMatchVerdict.yes);
    });

    // ---- ADR-0023：食材家族与模糊匹配（通用，非针对单一食材）----

    test('capsicum family: 辣椒 may satisfy 青椒 (MAYBE)', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '辣椒',
          baseConceptId: 'ingredient.capsicum',
          baseConceptName: '辣椒',
          quantity: 2,
        ),
      );
      final recipes = <Recipe>[
        recipe('青椒肉丝', <Ingredient>[ing('青椒'), ing('猪肉')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'辣椒'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.maybeNames, contains('青椒'));
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '青椒',
      );
      expect(detail.verdict, IngredientMatchVerdict.maybe);
    });

    test('mushroom family: 蘑菇 vs 香菇 enters maybe', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '蘑菇',
          baseConceptId: 'ingredient.mushroom',
          baseConceptName: '蘑菇',
          quantity: 300,
        ),
      );
      final recipes = <Recipe>[
        recipe('香菇炖鸡', <Ingredient>[ing('香菇'), ing('鸡')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'蘑菇'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.maybeNames, contains('香菇'));
    });

    test('fish family: 鱼 vs 鲈鱼 enters maybe', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '鱼',
          baseConceptId: 'ingredient.fish',
          baseConceptName: '鱼',
          quantity: 1,
        ),
      );
      final recipes = <Recipe>[
        recipe('清蒸鲈鱼', <Ingredient>[ing('鲈鱼')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'鱼'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.maybeNames, contains('鲈鱼'));
    });

    test('leafy family: 青菜 vs 小白菜 enters maybe', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '青菜',
          baseConceptId: 'ingredient.leafy_green',
          baseConceptName: '青菜',
          quantity: 200,
        ),
      );
      final recipes = <Recipe>[
        recipe('小白菜炒肉', <Ingredient>[ing('小白菜'), ing('猪肉')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'青菜'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      expect(results.single.maybeNames, contains('小白菜'));
    });

    test('dried chili conflicts with fresh 青椒 requirement (NO)', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '干辣椒',
          baseConceptId: 'ingredient.hot_pepper',
          baseConceptName: '干辣椒',
          processing: IngredientProcessing.dried,
          quantity: 2,
        ),
      );
      final recipes = <Recipe>[
        recipe('青椒肉丝', <Ingredient>[ing('青椒'), ing('猪肉')]),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'干辣椒'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.noMatchNames, contains('青椒'));
      final detail = result.matchDetails.firstWhere(
        (d) => d.rawName == '青椒',
      );
      expect(detail.verdict, IngredientMatchVerdict.no);
    });

    test('optional ingredient is not counted as missing', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '瘦肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          fatLevel: IngredientFatLevel.lean,
          quantity: 200,
        ),
      );
      final recipes = <Recipe>[
        recipe(
          '瘦肉炒青椒',
          <Ingredient>[
            ing('瘦肉'),
            ing('青椒'),
            Ingredient(
              id: 'ing-香菜',
              name: '香菜',
              optional: true,
              importance: IngredientImportance.optional,
              sortOrder: 0,
            ),
          ],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'瘦肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.missing, <String>['青椒']);
      expect(result.shortageCount, 1);
    });

    // ---- 匹配优化：全局批次分配与精确库存优先（用户原则）----

    /// 带规格的菜谱食材（构造 猪肉 vs 五花肉 等分面需求用）。
    Ingredient specIng(
      String name, {
      String? baseConceptId,
      IngredientCut? cut,
      IngredientFatLevel? fatLevel,
      IngredientForm? form,
      String? quantity,
    }) {
      return Ingredient(
        id: 'ing-$name',
        name: name,
        baseConceptId: baseConceptId,
        cut: cut,
        fatLevel: fatLevel,
        form: form,
        sortOrder: 0,
        quantity: quantity,
      );
    }

    test('同一批次不能同时满足多个不同规格（原则 2）', () async {
      final (useCases, repository) = build();
      // 冰箱只有一份“未确认部位/肥瘦”的普通猪肉。
      await repository.upsertBatch(
        specBatch(
          name: '猪肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          quantity: 300,
        ),
      );
      final recipes = <Recipe>[
        recipe(
          '精瘦肉配瘦肉',
          <Ingredient>[
            specIng('精瘦肉', baseConceptId: 'ingredient.pork', fatLevel: IngredientFatLevel.veryLean),
            specIng('瘦肉', baseConceptId: 'ingredient.pork', fatLevel: IngredientFatLevel.lean),
          ],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'猪肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      // 更具体需求（精瘦肉）拿到这份库存的“可能可以做”，占用该批次。
      expect(result.maybeNames, <String>['精瘦肉']);
      // 同一份库存不能再同时“可能满足”另一个规格 → 瘦肉视为缺失。
      expect(result.missing, <String>['瘦肉']);
    });

    test('精确库存优先：五花肉不抢占普通猪肉（原则 3/4/5）', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '普通猪肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          quantity: 300,
        ),
      );
      await repository.upsertBatch(
        specBatch(
          name: '五花肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          cut: IngredientCut.belly,
          fatLevel: IngredientFatLevel.mixed,
          quantity: 200,
        ),
      );
      final recipes = <Recipe>[
        recipe(
          '猪肉炒肉',
          <Ingredient>[
            specIng('猪肉', baseConceptId: 'ingredient.pork'),
            specIng('五花肉', baseConceptId: 'ingredient.pork', cut: IngredientCut.belly),
          ],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'猪肉', '五花肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      // 猪肉、五花肉是独立需求，均身份命中，且各自占用专属批次（不互相抢占）。
      expect(result.selectedHit, containsAll(<String>['猪肉', '五花肉']));
      expect(result.selectedHit.length, 2);
      expect(result.missing, isEmpty);
    });

    test('数量只统计最终分配批次，不计所有候选批次（原则 6）', () async {
      final (useCases, repository) = build();
      await repository.upsertBatch(
        specBatch(
          name: '精瘦肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          fatLevel: IngredientFatLevel.veryLean,
          quantity: 200,
        ),
      );
      // 普通猪肉只是“候选”（对精瘦肉需求是 MAYBE），不应计入数量。
      await repository.upsertBatch(
        specBatch(
          name: '普通猪肉',
          baseConceptId: 'ingredient.pork',
          baseConceptName: '猪肉',
          quantity: 500,
        ),
      );
      final recipes = <Recipe>[
        recipe(
          '精瘦肉料理',
          <Ingredient>[
            specIng(
              '精瘦肉',
              baseConceptId: 'ingredient.pork',
              fatLevel: IngredientFatLevel.veryLean,
              quantity: '200 克',
            ),
          ],
        ),
      ];
      final results = InventoryRecommendationUseCases().recommend(
        selectedNames: const <String>{'精瘦肉'},
        recipes: recipes,
        batches: await useCases.loadAvailableBatches(),
        now: now,
      );
      final result = results.single;
      expect(result.selectedHit, <String>['精瘦肉']);
      final detail = result.matchDetails.firstWhere((d) => d.rawName == '精瘦肉');
      // 只统计身份分配到的 200g，普通猪肉的 500g 不混入。
      expect(detail.availableQuantity, 200);
      expect(detail.sufficiency, IngredientSufficiency.sufficient);
    });
  });

  group('consume', () {
    test('consumes quantity and keeps batch available when remaining > 0',
        () async {
      final (useCases, _) = build();
      final batch = await useCases.createBatch(
        const InventoryBatchInput(
          ingredientName: '番茄',
          quantity: 3,
          unit: '个',
          zone: InventoryZone.chilled,
        ),
      );
      final updated = await useCases.consumeBatch(batch.id, 1);
      expect(updated.quantity, 2);
      expect(updated.status, InventoryBatchStatus.available);
    });

    test('uses up batch when quantity reaches zero', () async {
      final (useCases, _) = build();
      final batch = await useCases.createBatch(
        const InventoryBatchInput(
          ingredientName: '牛奶',
          quantity: 1,
          unit: '盒',
          zone: InventoryZone.chilled,
        ),
      );
      final updated = await useCases.consumeBatch(batch.id, 1);
      expect(updated.status, InventoryBatchStatus.usedUp);
    });

    test('rejects consuming unknown quantity batch', () async {
      final (useCases, _) = build();
      final batch = await useCases.createBatch(
        const InventoryBatchInput(
          ingredientName: '冰糖',
          zone: InventoryZone.roomTemperature,
        ),
      );
      await expectLater(
        useCases.consumeBatch(batch.id, 1),
        throwsStateError,
      );
    });

    test('rejects consuming more than available (no negative inventory)',
        () async {
      final (useCases, _) = build();
      final batch = await useCases.createBatch(
        const InventoryBatchInput(
          ingredientName: '鸡蛋',
          quantity: 2,
          unit: '枚',
          zone: InventoryZone.chilled,
        ),
      );
      await expectLater(
        useCases.consumeBatch(batch.id, 5),
        throwsStateError,
      );
    });
  });
}
