import 'package:ai_recipe/domain/inventory/inventory_batch.dart';
import 'package:ai_recipe/domain/inventory/inventory_repository.dart';

/// 内存库存仓库（测试用）：行为与 SQLite 实现对齐。
class MemoryInventoryRepository implements InventoryRepository {
  final _batches = <String, InventoryBatch>{};
  final _changes = <InventoryChange>[];

  @override
  Future<void> upsertBatch(
    InventoryBatch batch, {
    int? expectedLocalVersion,
  }) async {
    if (expectedLocalVersion != null) {
      final existing = _batches[batch.id];
      if (existing == null) {
        throw StateError('库存批次不存在：${batch.id}');
      }
      if (existing.localVersion != expectedLocalVersion) {
        throw StateError('库存批次写冲突：${batch.id}');
      }
    }
    _batches[batch.id] = batch;
  }

  @override
  Future<InventoryBatch?> getBatchById(String id) async => _batches[id];

  @override
  Future<List<InventoryBatch>> listBatches({
    Set<InventoryZone>? zones,
    bool includeUsedUp = false,
    bool includeDiscarded = false,
  }) async {
    final result = _batches.values.where((batch) {
      if (zones != null && zones.isNotEmpty && !zones.contains(batch.zone)) {
        return false;
      }
      if (!includeUsedUp && batch.status == InventoryBatchStatus.usedUp) {
        return false;
      }
      if (!includeDiscarded &&
          batch.status == InventoryBatchStatus.discarded) {
        return false;
      }
      return true;
    }).toList(growable: false);
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  @override
  Future<void> permanentlyDeleteBatch(String id) async {
    _batches.remove(id);
  }

  @override
  Future<void> addChange(InventoryChange change) async {
    _changes.add(change);
  }

  @override
  Future<List<InventoryChange>> listChanges({
    String? batchId,
    int? limit,
  }) async {
    var result = batchId == null
        ? _changes.toList()
        : _changes.where((change) => change.batchId == batchId).toList();
    result = result.reversed.toList();
    if (limit != null && result.length > limit) {
      result = result.sublist(0, limit);
    }
    return result;
  }
}
