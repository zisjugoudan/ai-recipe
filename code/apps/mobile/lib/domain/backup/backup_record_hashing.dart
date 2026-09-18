/// 备份记录规范化内容哈希（BACKUP-004 预检冲突比较）。
///
/// 用于判定"相同 UUID 且内容相同"（合并导入默认跳过）与
/// "不同 UUID 但内容完全相同"（可能重复）。哈希只覆盖业务内容：
/// - 排除封面/画廊图片的**设备路径**（跨设备路径必然不同）；
/// - 排除 updatedAt 与 localVersion（本地修改时间/版本不代表内容不同）；
/// - 保留 createdAt 与 deletedAt（软删除状态是菜谱库的一部分）。
///
/// 哈希输入是规范化 Map（键有序、值类型稳定），与设备、平台、序列化
/// 格式解耦，保证同一条记录跨设备得到相同哈希。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../recipe/recipe.dart';
import 'backup_records.dart';

/// 计算菜谱备份记录的规范化内容哈希（小写十六进制 SHA-256）。
String canonicalRecipeHash(RecipeBackupRecord record) {
  final map = <String, Object?>{
    'id': record.id,
    'title': record.title,
    'description': record.description,
    'servings': record.servings,
    'prepTimeMinutes': record.prepTimeMinutes,
    'cookTimeMinutes': record.cookTimeMinutes,
    'totalTimeMinutes': record.totalTimeMinutes,
    'difficulty': record.difficulty.wireName,
    'notes': record.notes,
    'favorite': record.favorite,
    'status': record.status.wireName,
    'sourceId': record.sourceId,
    'ingredients': record.ingredients
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'groupName': item.groupName,
            'name': item.name,
            'quantity': item.quantity,
            'unit': item.unit,
            'optional': item.optional,
            'preparation': item.preparation,
            'substitutes': item.substitutes,
            'sortOrder': item.sortOrder,
            'confidence': item.confidence,
            'baseConceptId': item.baseConceptId,
            'baseConceptName': item.baseConceptName,
            'cut': item.cut?.wireName,
            'fatLevel': item.fatLevel?.wireName,
            'form': item.form?.wireName,
            'processing': item.processing?.wireName,
            'specConfidence': item.specConfidence,
            'specSource': item.specSource.wireName,
            'importance': item.importance.wireName,
          },
        )
        .toList(),
    'steps': record.steps
        .map(
          (step) => <String, Object?>{
            'id': step.id,
            'stepNumber': step.stepNumber,
            'description': step.description,
            'durationSeconds': step.durationSeconds,
            'temperature': step.temperature,
            'heatLevel': step.heatLevel,
            'cookware': step.cookware,
            'tips': step.tips,
            'mediaUrl': step.mediaUrl,
            'confidence': step.confidence,
          },
        )
        .toList(),
    'categoryIds': record.categoryIds,
    'tags': record.tags,
    'createdAt': record.createdAt.millisecondsSinceEpoch,
    'deletedAt': record.deletedAt?.millisecondsSinceEpoch,
  };
  return _hash(map);
}

/// 计算分类备份记录的规范化内容哈希。
String canonicalCategoryHash(CategoryBackupRecord record) {
  final map = <String, Object?>{
    'id': record.id,
    'name': record.name,
    'sortOrder': record.sortOrder,
    'createdAt': record.createdAt.millisecondsSinceEpoch,
    'deletedAt': record.deletedAt?.millisecondsSinceEpoch,
  };
  return _hash(map);
}

/// 由当前库的 [Recipe] 领域对象直接计算规范化内容哈希（预检用）。
///
/// 与 [canonicalRecipeHash] 使用同一套规范化 Map（图片路径被剔除），
/// 保证当前库与备份记录同内容比较结果一致。
String canonicalRecipeHashFromDomain(Recipe recipe) {
  final map = <String, Object?>{
    'id': recipe.id,
    'title': recipe.title,
    'description': recipe.description,
    'servings': recipe.servings,
    'prepTimeMinutes': recipe.prepTimeMinutes,
    'cookTimeMinutes': recipe.cookTimeMinutes,
    'totalTimeMinutes': recipe.totalTimeMinutes,
    'difficulty': recipe.difficulty.wireName,
    'notes': recipe.notes,
    'favorite': recipe.favorite,
    'status': recipe.status.wireName,
    'sourceId': recipe.sourceId,
    'ingredients': recipe.ingredients
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'groupName': item.groupName,
            'name': item.name,
            'quantity': item.quantity,
            'unit': item.unit,
            'optional': item.optional,
            'preparation': item.preparation,
            'substitutes': item.substitutes,
            'sortOrder': item.sortOrder,
            'confidence': item.confidence,
            'baseConceptId': item.baseConceptId,
            'baseConceptName': item.baseConceptName,
            'cut': item.cut?.wireName,
            'fatLevel': item.fatLevel?.wireName,
            'form': item.form?.wireName,
            'processing': item.processing?.wireName,
            'specConfidence': item.specConfidence,
            'specSource': item.specSource.wireName,
            'importance': item.importance.wireName,
          },
        )
        .toList(),
    'steps': recipe.steps
        .map(
          (step) => <String, Object?>{
            'id': step.id,
            'stepNumber': step.stepNumber,
            'description': step.description,
            'durationSeconds': step.durationSeconds,
            'temperature': step.temperature,
            'heatLevel': step.heatLevel,
            'cookware': step.cookware,
            'tips': step.tips,
            'mediaUrl': step.mediaUrl,
            'confidence': step.confidence,
          },
        )
        .toList(),
    'categoryIds': recipe.categoryIds,
    'tags': recipe.tags,
    'createdAt': recipe.createdAt.millisecondsSinceEpoch,
    'deletedAt': recipe.deletedAt?.millisecondsSinceEpoch,
  };
  return _hash(map);
}

/// 由当前库的 [RecipeCategory] 领域对象直接计算规范化内容哈希。
String canonicalCategoryHashFromDomain(RecipeCategory category) {
  final map = <String, Object?>{
    'id': category.id,
    'name': category.name,
    'sortOrder': category.sortOrder,
    'createdAt': category.createdAt.millisecondsSinceEpoch,
    'deletedAt': category.deletedAt?.millisecondsSinceEpoch,
  };
  return _hash(map);
}

String _hash(Map<String, Object?> map) {
  final json = const JsonEncoder().convert(map);
  return sha256.convert(utf8.encode(json)).toString();
}
