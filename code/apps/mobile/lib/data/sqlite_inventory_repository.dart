import 'package:sqflite/sqflite.dart';

import '../domain/ingredient/ingredient_spec.dart';
import '../domain/inventory/inventory_batch.dart';
import '../domain/inventory/inventory_repository.dart';
import 'local/app_database.dart';

/// SQLite 库存批次与变更记录仓库（FRIDGE-002/003）。
class SqliteInventoryRepository implements InventoryRepository {
  SqliteInventoryRepository(this._database);

  final AppDatabase _database;

  Future<Database> get _db => _database.database;

  @override
  Future<void> upsertBatch(
    InventoryBatch batch, {
    int? expectedLocalVersion,
  }) async {
    final db = await _db;
    final existing = expectedLocalVersion == null
        ? null
        : await db.query(
            'inventory_batches',
            columns: const <String>['local_version'],
            where: 'id = ?',
            whereArgs: <Object?>[batch.id],
          );
    if (expectedLocalVersion != null &&
        (existing == null || existing.isEmpty)) {
      throw StateError('库存批次不存在：${batch.id}');
    }
    await db.insert(
      'inventory_batches',
      _toMap(batch),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<InventoryBatch?> getBatchById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'inventory_batches',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<InventoryBatch>> listBatches({
    Set<InventoryZone>? zones,
    bool includeUsedUp = false,
    bool includeDiscarded = false,
  }) async {
    final db = await _db;
    final conditions = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (zones != null && zones.isNotEmpty) {
      conditions.add(
        'storage_location IN (${zones.map((_) => '?').join(',')})',
      );
      args.addAll(zones.map((zone) => zone.name));
    }
    if (!includeUsedUp) conditions.add("status != 'usedUp'");
    if (!includeDiscarded) conditions.add("status != 'discarded'");
    final rows = await db.query(
      'inventory_batches',
      where: conditions.join(' AND '),
      whereArgs: args,
      // 分区内按拖动排序权重，其次按创建时间。
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> permanentlyDeleteBatch(String id) async {
    final db = await _db;
    await db.delete(
      'inventory_batches',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> addChange(InventoryChange change) async {
    final db = await _db;
    await db.insert('inventory_changes', <String, Object?>{
      'id': change.id,
      'batch_id': change.batchId,
      'change_type': change.changeType.name,
      'quantity_delta': change.quantityDelta,
      'unit': change.unit,
      'related_recipe_id': change.relatedRecipeId,
      'confirmed_by_user': change.confirmedByUser ? 1 : 0,
      'created_at': change.createdAt.toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<List<InventoryChange>> listChanges({
    String? batchId,
    int? limit,
  }) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    if (batchId != null) {
      conditions.add('batch_id = ?');
      args.add(batchId);
    }
    final rows = await db.query(
      'inventory_changes',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_fromChangeRow).toList(growable: false);
  }

  static Map<String, Object?> _toMap(InventoryBatch batch) {
    return <String, Object?>{
      'id': batch.id,
      'ingredient_name': batch.ingredientName,
      'normalized_ingredient_name': batch.normalizedIngredientName,
      'quantity': batch.quantity,
      'unit': batch.unit,
      'category': batch.category,
      'storage_location': batch.zone.name,
      'purchased_at': batch.purchasedAt
          ?.toUtc()
          .millisecondsSinceEpoch,
      'expires_at': batch.expiresAt?.toUtc().millisecondsSinceEpoch,
      'note': batch.note,
      // ---- ADR-0022 规格落库 ----
      'base_concept_id': _emptyToNull(batch.baseConceptId),
      'base_concept_name': _emptyToNull(batch.baseConceptName),
      'cut': batch.cut?.wireName,
      'fat_level': batch.fatLevel?.wireName,
      'form': batch.form?.wireName,
      'processing': batch.processing?.wireName,
      'spec_source': batch.specSource.wireName,
      'sort_order': batch.sortOrder,
      'status': batch.status.name,
      'created_at': batch.createdAt.toUtc().millisecondsSinceEpoch,
      'updated_at': batch.updatedAt.toUtc().millisecondsSinceEpoch,
      'local_version': batch.localVersion,
      'deleted_at': batch.deletedAt?.toUtc().millisecondsSinceEpoch,
    };
  }

  static InventoryBatch _fromRow(Map<String, Object?> row) {
    return InventoryBatch(
      id: row['id']! as String,
      ingredientName: row['ingredient_name']! as String,
      normalizedIngredientName: row['normalized_ingredient_name'] as String?,
      quantity: (row['quantity'] as num?)?.toDouble(),
      unit: row['unit'] as String?,
      category: row['category'] as String?,
      zone: InventoryZone.fromWireName(row['storage_location']! as String),
      purchasedAt: _fromEpoch(row['purchased_at']),
      expiresAt: _fromEpoch(row['expires_at']),
      note: row['note'] as String?,
      // ---- ADR-0022 规格读取 ----
      baseConceptId: row['base_concept_id'] as String?,
      baseConceptName: row['base_concept_name'] as String?,
      cut: IngredientCut.fromWireName(row['cut'] as String?),
      fatLevel: IngredientFatLevel.fromWireName(row['fat_level'] as String?),
      form: IngredientForm.fromWireName(row['form'] as String?),
      processing: IngredientProcessing.fromWireName(
        row['processing'] as String?,
      ),
      specSource: IngredientSpecSource.fromWireName(
        row['spec_source'] as String?,
      ),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      status: InventoryBatchStatus.fromWireName(row['status']! as String),
      createdAt: _fromEpoch(row['created_at'])!,
      updatedAt: _fromEpoch(row['updated_at'])!,
      localVersion: row['local_version']! as int,
      deletedAt: _fromEpoch(row['deleted_at']),
    );
  }

  static InventoryChange _fromChangeRow(Map<String, Object?> row) {
    return InventoryChange(
      id: row['id']! as String,
      batchId: row['batch_id']! as String,
      changeType: InventoryChangeType.fromWireName(
        row['change_type']! as String,
      ),
      quantityDelta: (row['quantity_delta'] as num?)?.toDouble(),
      unit: row['unit'] as String?,
      relatedRecipeId: row['related_recipe_id'] as String?,
      confirmedByUser: (row['confirmed_by_user']! as int) == 1,
      createdAt: _fromEpoch(row['created_at'])!,
    );
  }

  static DateTime? _fromEpoch(Object? value) {
    if (value is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
