import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/inventory/inventory_batch.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 扣减确认页（FRIDGE-003，UI-016 扣减面板）。
///
/// 根据菜谱食材与库存批次自动生成预计消耗：默认选择到期更早的批次；
/// 用户可逐项勾选、修改数量或更换批次；确认后才更新库存并记录变更，
/// 数量未知/库存不足的批次不允许自动扣减，不产生负库存。
class InventoryDeductionPage extends StatefulWidget {
  const InventoryDeductionPage({
    super.key,
    required this.backend,
    required this.recipeId,
    required this.onDataChanged,
  });

  final AiRecipeBackendFacade backend;
  final String recipeId;
  final VoidCallback onDataChanged;

  @override
  State<InventoryDeductionPage> createState() => _InventoryDeductionPageState();
}

class _DeductionRow {
  _DeductionRow({
    required this.ingredientName,
    required this.quantity,
    required this.recipeUnit,
    required this.batches,
  });

  final String ingredientName;
  final double? quantity;

  /// 菜谱用量单位（可能与库存批次单位不一致，需提示用户确认）。
  final String? recipeUnit;

  /// 同名可扣减批次（按到期日升序，早到期优先）。
  final List<InventoryBatch> batches;

  bool selected = true;
  int selectedBatchIndex = 0;
  double? adjustedQuantity;

  InventoryBatch get targetBatch => batches[selectedBatchIndex];
  double get effectiveQuantity =>
      adjustedQuantity ?? quantity ?? 0;

  /// 菜谱用量单位与库存批次单位不同（均为非空）时，扣减数量按库存单位计，
  /// 需要用户确认。
  bool get unitMismatch {
    final recipeUnitValue = recipeUnit?.trim();
    final batchUnitValue = targetBatch.unit?.trim();
    return recipeUnitValue != null &&
        recipeUnitValue.isNotEmpty &&
        batchUnitValue != null &&
        batchUnitValue.isNotEmpty &&
        recipeUnitValue != batchUnitValue;
  }
}

class _InventoryDeductionPageState extends State<InventoryDeductionPage> {
  Recipe? _recipe;
  List<_DeductionRow> _rows = <_DeductionRow>[];
  var _loading = true;
  var _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recipe = await widget.backend.getRecipe(widget.recipeId);
      final batches = await widget.backend.listInventoryBatches();
      if (!mounted) return;
      final rows = _buildRows(recipe, batches);
      setState(() {
        _recipe = recipe;
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '预计消耗暂时无法生成，请稍后重试。';
      });
    }
  }

  static List<_DeductionRow> _buildRows(
    Recipe recipe,
    List<InventoryBatch> batches,
  ) {
    final byName = <String, List<InventoryBatch>>{};
    for (final batch in batches) {
      if (!batch.isAvailable) continue;
      byName.putIfAbsent(batch.ingredientName.trim(), () => <InventoryBatch>[])
          .add(batch);
    }
    for (final list in byName.values) {
      list.sort((a, b) {
        final aDate = a.expiresAt ?? DateTime(9999);
        final bDate = b.expiresAt ?? DateTime(9999);
        return aDate.compareTo(bDate);
      });
    }
    final rows = <_DeductionRow>[];
    for (final ingredient in recipe.ingredients) {
      if (ingredient.optional) continue;
      final name = ingredient.name.trim();
      final candidates = byName[name];
      if (candidates == null || candidates.isEmpty) continue;
      rows.add(
        _DeductionRow(
          ingredientName: name,
          quantity: _parseQuantity(ingredient.quantity),
          recipeUnit: ingredient.unit,
          batches: candidates,
        ),
      );
    }
    return rows;
  }

  static double? _parseQuantity(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final items = <InventoryConsumptionItem>[
      for (final row in _rows)
        if (row.selected && row.effectiveQuantity > 0)
          InventoryConsumptionItem(
            batchId: row.targetBatch.id,
            delta: row.effectiveQuantity,
            relatedRecipeId: widget.recipeId,
          ),
    ];
    if (items.isEmpty) {
      setState(() => _errorMessage = '没有可确认的消耗项。');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.backend.confirmInventoryConsumption(items);
      widget.onDataChanged();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = '更新失败，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelPageAppBar(title: '扣减确认', eyebrow: '下厨后更新冰箱'),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: PixelLoader(size: 7))
            : _errorMessage != null && _rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                      children: <Widget>[
                        PixelNotice(
                          title: _recipe == null
                              ? '确认本次消耗'
                              : '「${_recipe!.title}」已完成！',
                          message:
                              '确认本次消耗的食材后，才会更新冰箱库存。未确认时库存保持不变。',
                          icon: Icons.check_circle_outline_rounded,
                          tone: PixelNoticeTone.green,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '预计消耗 · ${_rows.where((r) => r.selected).length}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        PixelSurface(
                          cut: 5,
                          elevation: 0,
                          color: AppColors.card,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: _rows.map((row) {
                              return _buildRow(row);
                            }).toList(),
                          ),
                        ),
                        if (_errorMessage != null) ...<Widget>[
                          const SizedBox(height: 12),
                          PixelNotice(
                            title: '暂时无法更新',
                            message: _errorMessage!,
                            icon: Icons.warning_amber_rounded,
                            tone: PixelNoticeTone.red,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          '可逐项取消、修改数量或更换批次；数量未知或库存不足的批次无法自动扣减。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _submitting
                                  ? null
                                  // 暂不更新也视为烹饪流程正常结束，库存保持不变。
                                  : () => Navigator.of(context).pop(true),
                              child: const Text('暂不更新'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              key: const Key('confirmDeductionButton'),
                              onPressed: _submitting ? null : _submit,
                              icon: _submitting
                                  ? const PixelLoader(size: 5, color: Colors.white)
                                  : const Icon(Icons.check_rounded),
                              label: const Text('确认并更新冰箱'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRow(_DeductionRow row) {
    final target = row.targetBatch;
    final qty = row.quantity;
    final quantityKnown = qty != null && qty > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => row.selected = !row.selected),
            child: Icon(
              row.selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: row.selected ? AppColors.greenDeep : AppColors.ink3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.ingredientName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!quantityKnown)
                  Text(
                    '数量未知，请确认用量',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.amber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (row.unitMismatch) ...<Widget>[
                  Text(
                    '菜谱用量单位「${row.recipeUnit}」与库存单位「${row.targetBatch.unit}」'
                    '不一致，请按库存单位确认数量',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.amber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  value: row.selectedBatchIndex,
                  isExpanded: true,
                  items: <DropdownMenuItem<int>>[
                    for (var index = 0; index < row.batches.length; index++)
                      DropdownMenuItem<int>(
                        value: index,
                        child: Text(
                          _batchLabel(row.batches[index]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => row.selectedBatchIndex = value);
                    }
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: TextField(
              key: Key('deductQuantity_${row.ingredientName}'),
              enabled: row.selected,
              controller: TextEditingController(
                text: quantityKnown ? _trimNumber(qty!) : '',
              ),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                // 扣减以库存批次单位为准（与冰箱显示保持一致）。
                suffixText: row.targetBatch.unit,
                hintText: '用量',
              ),
              onChanged: (value) {
                final parsed = double.tryParse(
                  value.trim().replaceAll(',', '.'),
                );
                row.adjustedQuantity = parsed;
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _batchLabel(InventoryBatch batch) {
    final zone = switch (batch.zone) {
      InventoryZone.chilled => '冷藏',
      InventoryZone.frozen => '冷冻',
      InventoryZone.roomTemperature => '常温',
      InventoryZone.other => '其他',
    };
    final date = batch.expiresAt == null
        ? '无日期'
        : '到期 ${batch.expiresAt!.toLocal().month}-${batch.expiresAt!.toLocal().day}';
    return '$zone · $date';
  }

  static String _trimNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }
}
