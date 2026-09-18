import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/inventory/inventory_batch.dart';
import '../../domain/recipe/recipe.dart';
import 'inventory_use_cases.dart';

/// 推荐匹配计算执行器（解决方案.md 第六节）。
///
/// 纯匹配计算不应阻塞 UI 主线程：生产环境用后台 Isolate 执行；
/// 测试环境注入 [DirectRecommendationExecutor] 同步直算——Flutter Widget
/// 测试运行在 FakeAsync 时区里，Isolate 消息无法被 pumpAndSettle 等待，
/// 会导致测试挂起。
abstract interface class RecommendationExecutor {
  Future<List<RecipeRecommendation>> compute({
    required Set<String> selectedNames,
    required List<Recipe> recipes,
    required List<InventoryBatch> batches,
    required DateTime now,
    required bool strictSelected,
    required Set<String> confirmedBases,
  });
}

/// 后台 Isolate 执行（生产默认）：数据读取完成后把可序列化的轻量数据
/// 传给新 Isolate 计算，界面保持可滚动、可返回。
class IsolateRecommendationExecutor implements RecommendationExecutor {
  const IsolateRecommendationExecutor();

  @override
  Future<List<RecipeRecommendation>> compute({
    required Set<String> selectedNames,
    required List<Recipe> recipes,
    required List<InventoryBatch> batches,
    required DateTime now,
    required bool strictSelected,
    required Set<String> confirmedBases,
  }) async {
    if (kIsWeb) {
      // Web 平台不支持 Isolate，回退主线程直算。
      return _recommendDirect(
        selectedNames: selectedNames,
        recipes: recipes,
        batches: batches,
        now: now,
        strictSelected: strictSelected,
        confirmedBases: confirmedBases,
      );
    }
    return Isolate.run(
      () => _recommendDirect(
        selectedNames: selectedNames,
        recipes: recipes,
        batches: batches,
        now: now,
        strictSelected: strictSelected,
        confirmedBases: confirmedBases,
      ),
    );
  }
}

/// 同步直算（测试/Web 回退用）。
class DirectRecommendationExecutor implements RecommendationExecutor {
  const DirectRecommendationExecutor();

  @override
  Future<List<RecipeRecommendation>> compute({
    required Set<String> selectedNames,
    required List<Recipe> recipes,
    required List<InventoryBatch> batches,
    required DateTime now,
    required bool strictSelected,
    required Set<String> confirmedBases,
  }) async {
    return _recommendDirect(
      selectedNames: selectedNames,
      recipes: recipes,
      batches: batches,
      now: now,
      strictSelected: strictSelected,
      confirmedBases: confirmedBases,
    );
  }
}

/// 顶层纯计算函数：只依赖可发送的纯数据对象（Recipe/InventoryBatch 均为
/// 普通数据类），供 Isolate 入口使用。
List<RecipeRecommendation> _recommendDirect({
  required Set<String> selectedNames,
  required List<Recipe> recipes,
  required List<InventoryBatch> batches,
  required DateTime now,
  required bool strictSelected,
  required Set<String> confirmedBases,
}) {
  return InventoryRecommendationUseCases().recommend(
    selectedNames: selectedNames,
    recipes: recipes,
    batches: batches,
    now: now,
    strictSelected: strictSelected,
    confirmedBases: confirmedBases,
  );
}
