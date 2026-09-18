import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/inventory/inventory_use_cases.dart';
import '../../domain/ingredient/ingredient_canonicalizer.dart';
import '../../domain/ingredient/ingredient_spec.dart';
import '../../domain/inventory/inventory_batch.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 库存批次新增/编辑页（UI-015，FRIDGE-002 / ADR-0022）。
///
/// 存放位置默认跟随用户点击的分区；数量为空保存为“数量未知”，不写 0；
/// 输入已存在的食材名时提示“已有同名批次”，但保存始终新增/编辑当前批次。
/// 食材规格采用渐进式录入：先输入名称，系统即时解析并给出可跳过的
/// 规格候选（精瘦肉/五花肉/半肥半瘦等），用户选择或跳过。
class FridgeBatchEditPage extends StatefulWidget {
  const FridgeBatchEditPage({
    super.key,
    required this.backend,
    this.initialZone,
    this.batch,
  });

  final AiRecipeBackendFacade backend;
  final InventoryZone? initialZone;
  final InventoryBatch? batch;

  @override
  State<FridgeBatchEditPage> createState() => _FridgeBatchEditPageState();
}

class _FridgeBatchEditPageState extends State<FridgeBatchEditPage> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  String? _unit;
  String? _category;
  late InventoryZone _zone;
  DateTime? _purchasedAt;
  DateTime? _expiresAt;
  var _saving = false;
  String? _errorMessage;
  var _showDuplicateHint = false;

  // ---- ADR-0022 渐进式规格选择 ----
  /// 用户选中的规格；null 表示“规格未设置”（可跳过）。
  IngredientKnowledgeEntry? _chosenSpec;

  /// 当前名称解析出的规格候选。
  List<IngredientKnowledgeEntry> _specOptions = const [];

  /// 当前名称的解析结果（用于展示“识别为：猪肉 · 精瘦”）。
  IngredientCanonicalization? _nameCanonical;

  bool get _isEditing => widget.batch != null;

  static const _zones = <(InventoryZone, String)>[
    (InventoryZone.chilled, '冷藏区'),
    (InventoryZone.frozen, '冷冻区'),
    (InventoryZone.roomTemperature, '常温区'),
    (InventoryZone.other, '其他区'),
  ];

  static const _units = <String>['个', '克 g', '毫升 ml', '枚', '颗', '盒', '袋', '把', '斤', 'kg'];
  static const _categories = <String>[
    '蔬菜',
    '肉禽水产',
    '蛋奶',
    '水果',
    '调味品',
    '米面粮油',
    '其他',
  ];

  /// 单位下拉项：当前值不在预设列表时补入，避免
  /// DropdownButtonFormField 因 value 不在 items 而断言崩溃。
  List<DropdownMenuItem<String>> _unitItems() {
    final values = <String>[..._units];
    if (_unit != null && !values.contains(_unit)) values.insert(0, _unit!);
    return <DropdownMenuItem<String>>[
      for (final value in values)
        DropdownMenuItem<String>(value: value, child: Text(value)),
    ];
  }

  /// 分类下拉项（同上，兼容历史数据中的自定义分类）。
  List<DropdownMenuItem<String>> _categoryItems() {
    final values = <String>[..._categories];
    if (_category != null && !values.contains(_category)) {
      values.insert(0, _category!);
    }
    return <DropdownMenuItem<String>>[
      for (final value in values)
        DropdownMenuItem<String>(value: value, child: Text(value)),
    ];
  }

  @override
  void initState() {
    super.initState();
    final batch = widget.batch;
    _zone = batch?.zone ?? widget.initialZone ?? InventoryZone.chilled;
    if (batch != null) {
      _nameController.text = batch.ingredientName;
      _quantityController.text = batch.quantity == null
          ? ''
          : _trimNumber(batch.quantity!);
      _unit = batch.unit;
      _category = batch.category;
      _purchasedAt = batch.purchasedAt;
      _expiresAt = batch.expiresAt;
      _noteController.text = batch.note ?? '';
      // 编辑回显：批次已有规格时构造为当前选择。
      if (batch.baseConceptId != null) {
        _chosenSpec = IngredientKnowledgeEntry(
          name: batch.ingredientName,
          baseConceptId: batch.baseConceptId!,
          baseConceptName: batch.baseConceptName ?? batch.ingredientName,
          cut: batch.cut,
          fatLevel: batch.fatLevel,
          form: batch.form,
          processing: batch.processing,
        );
      }
    }
    _nameController.addListener(_checkDuplicate);
    _nameController.addListener(_refreshSpecSuggestions);
    // 初次刷新候选（编辑场景回显候选列表）。
    _refreshSpecSuggestions();
  }

  @override
  void dispose() {
    _nameController.removeListener(_refreshSpecSuggestions);
    _nameController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 删除当前批次：先二次确认，再调用后端删除，成功后返回库存页。
  Future<void> _delete() async {
    final batch = widget.batch;
    if (batch == null) return;
    final confirmed = await showPixelConfirm(
      context: context,
      title: '删除批次',
      message: '删除「${batch.ingredientName}」这个批次？删除后不可恢复。',
      confirmLabel: '删除',
      confirmColor: AppColors.red,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await widget.backend.deleteInventoryBatch(batch.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = '删除失败，请稍后重试。';
      });
    }
  }

  /// 名称变化时即时解析并刷新规格候选（ADR-0022 渐进式录入）。
  void _refreshSpecSuggestions() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _specOptions = const [];
        _nameCanonical = null;
      });
      return;
    }
    final suggestion = widget.backend.suggestInventorySpec(name);
    // 名称变化导致基础食材变化时，清空已选的规格，避免错配。
    final baseChanged =
        _chosenSpec != null &&
        suggestion.canonical.canonicalIngredientId != null &&
        suggestion.canonical.canonicalIngredientId != _chosenSpec!.baseConceptId;
    setState(() {
      _specOptions = suggestion.specOptions;
      _nameCanonical = suggestion.canonical;
      if (baseChanged) _chosenSpec = null;
    });
  }

  /// 规格候选去重（等价规格只显示一次，如“半肥半瘦”与“半肥半瘦的猪肉”）。
  List<IngredientKnowledgeEntry> get _uniqueSpecOptions {
    final result = <IngredientKnowledgeEntry>[];
    for (final entry in _specOptions) {
      if (!result.any((existing) => existing.spec.isEquivalentTo(entry.spec))) {
        result.add(entry);
      }
    }
    return result;
  }

  /// 规格选择区的提示文案（ADR-0022）。
  String get _specHint {
    final canonical = _nameCanonical;
    if (canonical == null) return '';
    if (!canonical.isKnown) {
      return '暂未收录该食材，规格可以跳过，之后推荐时再确认。';
    }
    if (_chosenSpec != null) {
      return '识别为：${_chosenSpec!.spec.summary ?? canonical.canonicalName}';
    }
    return '识别为：${canonical.canonicalName}。可选更具体的规格，不选则按基础规格处理。';
  }

  void _checkDuplicate() {
    final name = _nameController.text.trim();
    if (!_isEditing && name.isNotEmpty) {
      // 通过“是否已有同名批次”的提示服务：存在同名时提示，但不强制合并。
      _showDuplicateHint = true;
    }
  }

  Future<void> _pickDate(bool isExpiry) async {
    final now = DateTime.now();
    final initial = (isExpiry ? _expiresAt : _purchasedAt) ?? now;
    DateTime? picked;
    try {
      picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 5),
        // 像素主题的切角/描边可能导致系统日期组件异常，这里用默认
        // Material 主题渲染日期面板，保证任何设备都能正常选择。
        builder: (context, child) => Theme(
          data: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.green,
            ),
          ),
          child: child!,
        ),
      );
    } catch (_) {
      // 日期面板异常时保持原值，不让用户卡在编辑页。
    }
    if (picked == null) return;
    setState(() {
      if (isExpiry) {
        _expiresAt = picked;
      } else {
        _purchasedAt = picked;
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = '请填写食材名称。');
      return;
    }
    final quantityText = _quantityController.text.trim();
    final quantity = quantityText.isEmpty
        ? null
        : double.tryParse(quantityText.replaceAll(',', '.'));
    if (quantityText.isNotEmpty && (quantity == null || quantity <= 0)) {
      setState(() => _errorMessage = '数量需要是大于 0 的数字，留空表示数量未知。');
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final input = InventoryBatchInput(
      ingredientName: name,
      quantity: quantity,
      unit: _unit,
      category: _category,
      zone: _zone,
      purchasedAt: _purchasedAt,
      expiresAt: _expiresAt,
      note: _noteController.text.trim(),
      // ADR-0022：把用户在录入页选定的规格传给用例层。
      baseConceptId: _chosenSpec?.baseConceptId,
      baseConceptName: _chosenSpec?.baseConceptName,
      cut: _chosenSpec?.cut,
      fatLevel: _chosenSpec?.fatLevel,
      form: _chosenSpec?.form,
      processing: _chosenSpec?.processing,
      specSource: _chosenSpec == null
          ? IngredientSpecSource.unknown
          : IngredientSpecSource.user,
    );
    try {
      final batch = widget.batch;
      if (batch == null) {
        await widget.backend.createInventoryBatch(input);
      } else {
        await widget.backend.updateInventoryBatch(batch.id, input);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = '保存失败，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? '编辑批次' : '添加食材';
    return Scaffold(
      appBar: PixelPageAppBar(
        title: title,
        eyebrow: '冰箱库存',
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          children: <Widget>[
            _Field(
              label: '食材名称（必填）',
              child: TextField(
                key: const Key('batchNameField'),
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: '比如：番茄',
                  prefixIcon: Icon(Icons.kitchen_outlined),
                ),
              ),
            ),
            if (_showDuplicateHint) ...<Widget>[
              const SizedBox(height: 8),
              PixelNotice(
                title: '已有同名食材的其他批次',
                message: '保存后会新增一个批次，不会自动合并。',
                icon: Icons.info_outline_rounded,
                tone: PixelNoticeTone.amber,
              ),
            ],
            if (_nameCanonical != null) ...<Widget>[
              const SizedBox(height: 14),
              _Field(
                label: '食材规格（可选）',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _specHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _SpecChip(
                          label: '不确定',
                          selected: _chosenSpec == null,
                          onTap: () => setState(() => _chosenSpec = null),
                        ),
                        for (final option in _uniqueSpecOptions)
                          _SpecChip(
                            label: option.spec.summary ?? option.name,
                            selected:
                                _chosenSpec != null &&
                                _chosenSpec!.spec.isEquivalentTo(option.spec),
                            onTap: () => setState(() => _chosenSpec = option),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _Field(
                    label: '数量（可为空）',
                    child: TextField(
                      key: const Key('batchQuantityField'),
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '比如：2',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Field(
                    label: '单位（可为空）',
                    child: DropdownButtonFormField<String>(
                      key: const Key('batchUnitField'),
                      value: _unit,
                      items: _unitItems(),
                      onChanged: (value) => setState(() => _unit = value),
                      decoration: const InputDecoration(hintText: '选择单位'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '数量为空时保存为「数量未知」，不会默认写 0。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            _Field(
              label: '分类',
              child: DropdownButtonFormField<String>(
                key: const Key('batchCategoryField'),
                value: _category,
                items: _categoryItems(),
                onChanged: (value) => setState(() => _category = value),
                decoration: const InputDecoration(hintText: '选择分类'),
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              label: '存放位置',
              child: Wrap(
                spacing: 8,
                children: _zones.map((entry) {
                  final (zone, label) = entry;
                  final selected = zone == _zone;
                  return Material(
                    color: selected ? AppColors.green : AppColors.paper2,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _zone = zone),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: selected ? Colors.white : AppColors.ink2,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '默认跟随你点击「添加」的分区，可修改。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Field(
                    label: '购买日期（可为空）',
                    child: _DateButton(
                      label: _purchasedAt == null
                          ? '未设置'
                          : _dateLabel(_purchasedAt!),
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Field(
                    label: '到期日期（可为空）',
                    child: _DateButton(
                      label: _expiresAt == null
                          ? '未设置则不提醒'
                          : _dateLabel(_expiresAt!),
                      onTap: () => _pickDate(true),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Field(
              label: '备注',
              child: TextField(
                key: const Key('batchNoteField'),
                controller: _noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '比如：菜市场买的小番茄，更甜',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              PixelNotice(
                title: '暂时无法保存',
                message: _errorMessage!,
                icon: Icons.warning_amber_rounded,
                tone: PixelNoticeTone.red,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('saveInventoryBatchButton'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const PixelLoader(size: 5, color: Colors.white)
                  : const Icon(Icons.check_rounded),
              label: Text(_isEditing ? '保存修改' : '保存批次'),
            ),
            // 编辑态提供删除入口：用户点进编辑时可直接删除该批次。
            if (_isEditing) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('deleteInventoryBatchButton'),
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除批次'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _trimNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  static String _dateLabel(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// 规格选择 chip（ADR-0022 渐进式录入第二步）。
class _SpecChip extends StatelessWidget {
  const _SpecChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.green : AppColors.paper2,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 15),
      label: Text(label),
    );
  }
}
