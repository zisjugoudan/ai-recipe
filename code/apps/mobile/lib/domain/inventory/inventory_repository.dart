import 'inventory_batch.dart';

/// 库存批次与变更记录仓库（FRIDGE-002/003）。
abstract interface class InventoryRepository {
  /// 新增或更新批次；[expectedLocalVersion] 用于并发写冲突检测（与 ImportTask 一致）。
  Future<void> upsertBatch(
    InventoryBatch batch, {
    int? expectedLocalVersion,
  });

  Future<InventoryBatch?> getBatchById(String id);

  /// 列出批次。默认只返回可用批次；[includeUsedUp]/[includeDiscarded]
  /// 控制是否包含已用完/已丢弃批次。
  Future<List<InventoryBatch>> listBatches({
    Set<InventoryZone>? zones,
    bool includeUsedUp = false,
    bool includeDiscarded = false,
  });

  Future<void> permanentlyDeleteBatch(String id);

  Future<void> addChange(InventoryChange change);

  Future<List<InventoryChange>> listChanges({
    String? batchId,
    int? limit,
  });
}
