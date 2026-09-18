import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/recipe/recipe_library_commands.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/create_category_dialog.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../importing/import_image_picker.dart';

class RecipeEditPage extends StatefulWidget {
  const RecipeEditPage({
    super.key,
    required this.backend,
    this.initialRecipe,
    this.imagePicker,
  });

  final AiRecipeBackendFacade backend;
  final Recipe? initialRecipe;
  final ImportImagePicker? imagePicker;

  bool get isEditing => initialRecipe != null;

  @override
  State<RecipeEditPage> createState() => _RecipeEditPageState();
}

class _RecipeEditPageState extends State<RecipeEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _servingsController;
  late final TextEditingController _prepController;
  late final TextEditingController _cookController;
  late final TextEditingController _totalController;
  late final TextEditingController _tagsController;
  late final TextEditingController _notesController;
  late final List<_IngredientEditor> _ingredients;
  late final List<_StepEditor> _steps;
  late RecipeDifficulty _difficulty;
  late RecipeStatus _status;
  late bool _favorite;
  late Set<String> _selectedCategoryIds;
  late Future<List<RecipeCategory>> _categories;
  late final ImportImagePicker _imagePicker;
  late final String _coverContainerId;
  var _images = <String>[];
  var _pickingImages = false;
  var _saving = false;
  var _dirty = false;
  var _showRecipeAdvanced = false;

  @override
  void initState() {
    super.initState();
    final recipe = widget.initialRecipe;
    _titleController = TextEditingController(text: recipe?.title ?? '');
    _descriptionController = TextEditingController(
      text: recipe?.description ?? '',
    );
    _servingsController = TextEditingController(
      text: _intText(recipe?.servings),
    );
    _prepController = TextEditingController(
      text: _intText(recipe?.prepTimeMinutes),
    );
    _cookController = TextEditingController(
      text: _intText(recipe?.cookTimeMinutes),
    );
    _totalController = TextEditingController(
      text: _intText(recipe?.totalTimeMinutes),
    );
    _tagsController = TextEditingController(text: recipe?.tags.join('，') ?? '');
    _notesController = TextEditingController(text: recipe?.notes ?? '');
    _difficulty = recipe?.difficulty ?? RecipeDifficulty.unspecified;
    _status = recipe?.status ?? RecipeStatus.published;
    _favorite = recipe?.favorite ?? false;
    _selectedCategoryIds = recipe?.categoryIds.toSet() ?? <String>{};
    _ingredients = recipe == null || recipe.ingredients.isEmpty
        ? <_IngredientEditor>[_IngredientEditor()]
        : recipe.ingredients.map(_IngredientEditor.fromIngredient).toList();
    // 同分组食材归并相邻展示，避免出现两个相同分组标题。
    if (_ingredients.length > 1) _sortIngredientsByGroup(_ingredients);
    _steps = recipe == null || recipe.steps.isEmpty
        ? <_StepEditor>[_StepEditor()]
        : recipe.steps.map(_StepEditor.fromStep).toList();
    _categories = widget.backend.listCategories();
    _imagePicker = widget.imagePicker ?? DeviceImportImagePicker();
    _images = recipe?.images.toList() ?? <String>[];
    // 封面图片存放目录：编辑已有菜谱用其 ID；新建用临时唯一 ID。
    _coverContainerId = recipe?.id ?? 'new-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _servingsController.dispose();
    _prepController.dispose();
    _cookController.dispose();
    _totalController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (_dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  /// 从系统相册多选图片，复制到菜谱私有封面目录后追加到封面列表。
  Future<void> _pickImages() async {
    if (_pickingImages || _saving) return;
    setState(() {
      _pickingImages = true;
    });
    try {
      final picked = await _imagePicker.pickMultipleImages();
      if (picked.isEmpty || !mounted) return;
      final staged = await widget.backend.stageCoverImages(
        _coverContainerId,
        picked.map((image) => image.localAssetId).toList(),
      );
      if (!mounted) return;
      setState(() {
        _images = <String>[..._images, ...staged];
      });
      _markDirty();
    } on ImportImagePickerException catch (error) {
      _showError(error.message);
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('图片暂时无法添加，请稍后重试。');
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  /// 移除一张封面图，并 best-effort 清理对应的私有文件。
  Future<void> _removeImage(int index) async {
    if (_saving || index < 0 || index >= _images.length) return;
    final removed = _images[index];
    setState(() {
      _images = <String>[..._images]..removeAt(index);
    });
    unawaited(widget.backend.deleteCoverImage(removed));
    _markDirty();
  }

  /// 把指定图片设为封面：将其移动到列表首位（首图即封面）。
  void _setCover(int index) {
    if (_saving || index <= 0 || index >= _images.length) return;
    setState(() {
      final image = _images[index];
      final rest = <String>[..._images]..removeAt(index);
      _images = <String>[image, ...rest];
    });
    _markDirty();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final ingredientInputs = <RecipeIngredientInput>[];
    for (final item in _ingredients) {
      if (item.isEmpty) continue;
      if (item.name.text.trim().isEmpty) {
        _showError('每一项食材都需要填写名称。');
        return;
      }
      ingredientInputs.add(item.toInput());
    }

    final stepInputs = <RecipeStepInput>[];
    for (final item in _steps) {
      if (item.isEmpty) continue;
      if (item.description.text.trim().isEmpty) {
        _showError('每一个步骤都需要填写说明。');
        return;
      }
      stepInputs.add(item.toInput());
    }

    setState(() => _saving = true);
    try {
      final input = RecipeDraftInput(
        title: _titleController.text.trim(),
        description: _nullableText(_descriptionController.text),
        coverImage: _images.isEmpty ? null : _images.first,
        images: _images,
        servings: _nullableInt(_servingsController.text),
        prepTimeMinutes: _nullableInt(_prepController.text),
        cookTimeMinutes: _nullableInt(_cookController.text),
        totalTimeMinutes: _nullableInt(_totalController.text),
        difficulty: _difficulty,
        notes: _nullableText(_notesController.text),
        favorite: _favorite,
        status: _status,
        ingredients: ingredientInputs,
        steps: stepInputs,
        categoryIds: _selectedCategoryIds.toList(),
        tags: _parseTags(_tagsController.text),
      );
      if (widget.initialRecipe case final recipe?) {
        await widget.backend.updateRecipe(recipe.id, input);
      } else {
        await widget.backend.createRecipe(input);
      }
      if (!mounted) return;
      _popAfterClearingDirty(true);
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('菜谱保存失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _popAfterClearingDirty([Object? result]) {
    if (!mounted) return;
    setState(() => _dirty = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  Future<void> _requestExit() async {
    if (_saving || !mounted) return;
    if (!_dirty) {
      Navigator.of(context).maybePop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: PixelSurface(
          cut: PixelCut.lg,
          elevation: 2,
          color: AppColors.card,
          borderColor: AppColors.ink,
          borderWidth: 1.5,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '未保存修改',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '离开后，本次输入的菜名、食材和步骤将不会保留。',
                style: TextStyle(color: AppColors.ink2, fontSize: 12, height: 1.55),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton(
                    key: const Key('keepEditingRecipeButton'),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('继续编辑'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('discardRecipeChangesButton'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('放弃修改'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (discard != true || !mounted) return;
    _popAfterClearingDirty();
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(_IngredientEditor());
      _dirty = true;
    });
  }

  void _removeIngredient(int index) {
    setState(() {
      final removed = _ingredients.removeAt(index);
      removed.dispose();
      if (_ingredients.isEmpty) _ingredients.add(_IngredientEditor());
      _dirty = true;
    });
  }

  void _moveIngredient(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _ingredients.length) return;
    setState(() {
      final item = _ingredients.removeAt(index);
      _ingredients.insert(target, item);
      _dirty = true;
    });
  }

  void _addStep() {
    setState(() {
      _steps.add(_StepEditor());
      _dirty = true;
    });
  }

  void _removeStep(int index) {
    setState(() {
      final removed = _steps.removeAt(index);
      removed.dispose();
      if (_steps.isEmpty) _steps.add(_StepEditor());
      _dirty = true;
    });
  }

  void _moveStep(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _steps.length) return;
    setState(() {
      final item = _steps.removeAt(index);
      _steps.insert(target, item);
      _dirty = true;
    });
  }

  /// 拖拽重排食材（ReorderableListView 的 newIndex 在跨过被拖动项时多 1）。
  void _reorderIngredient(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _ingredients.removeAt(oldIndex);
      _ingredients.insert(newIndex, item);
      _dirty = true;
    });
  }

  /// 拖拽重排步骤。
  void _reorderStep(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _steps.removeAt(oldIndex);
      _steps.insert(newIndex, item);
      _dirty = true;
    });
  }

  /// 删除分组：清空该组全部食材的分组，分组标题随即消失。
  void _clearIngredientGroup(int index) {
    final group = _ingredients[index].group.text.trim();
    if (group.isEmpty) return;
    setState(() {
      for (final editor in _ingredients) {
        if (editor.group.text.trim() == group) {
          editor.group.text = '';
        }
      }
      _dirty = true;
    });
  }

  /// 判断第 [index] 个食材前是否需要显示分组标题：分组非空且与上一项不同。
  bool _showIngredientGroupHeader(int index) {
    final group = _ingredients[index].group.text.trim();
    if (group.isEmpty) return false;
    if (index == 0) return true;
    return _ingredients[index - 1].group.text.trim() != group;
  }

  Future<void> _createCategory() async {
    // 先读取现有分类用于同名提示；读取失败时仍允许打开对话框（跳过查重）。
    List<RecipeCategory> categories;
    try {
      categories = await _categories;
    } catch (_) {
      categories = const <RecipeCategory>[];
    }
    // await 之后页面可能已卸载，避免在 async gap 后继续使用 context。
    if (!mounted) return;
    // 输入控制器与校验由 CreateCategoryDialog 自持，避免关闭动画期间访问
    // 已释放控制器，并防止空名称、同名分类、超长名称与快速重复提交。
    final name = await CreateCategoryDialog.show(
      context,
      existingNames: categories.map((item) => item.name).toList(),
    );
    if (name == null || !mounted) return;
    try {
      final maxOrder = categories.fold<int>(
        -1,
        (value, item) => item.sortOrder > value ? item.sortOrder : value,
      );
      final category = await widget.backend.createCategory(
        RecipeCategoryInput(name: name, sortOrder: maxOrder + 1),
      );
      if (!mounted) return;
      setState(() {
        _selectedCategoryIds.add(category.id);
        _categories = widget.backend.listCategories();
        _dirty = true;
      });
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        appBar: PixelPageAppBar(
          title: widget.isEditing ? '编辑菜谱' : '新建菜谱',
          eyebrow: '菜谱编辑',
          onBack: () => unawaited(_requestExit()),
          actions: const <Widget>[
            Center(child: PixelBadge(label: '手动模式')),
            SizedBox(width: 14),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 118),
            children: <Widget>[
              const _EditorSectionTitle(
                title: '封面图片',
                eyebrow: '封面图片',
                icon: Icons.photo_library_rounded,
              ),
              const SizedBox(height: 12),
              _CoverImageEditor(
                images: _images,
                picking: _pickingImages,
                enabled: !_saving,
                onPick: _pickImages,
                onRemove: _removeImage,
                onSetCover: _setCover,
              ),
              const SizedBox(height: 18),
              const _EditorSectionTitle(
                title: '基础信息',
                eyebrow: '基本信息',
                icon: Icons.restaurant_menu_rounded,
              ),
              const SizedBox(height: 14),
              const PixelFieldLabel('菜名', required: true),
              _PixelTextField(
                fieldKey: const Key('recipeTitleField'),
                controller: _titleController,
                enabled: !_saving,
                hintText: '例如：番茄炖牛腩',
                textInputAction: TextInputAction.next,
                onChanged: (_) => _markDirty(),
                validator: (value) =>
                    value?.trim().isEmpty ?? true ? '请输入菜名' : null,
              ),
              const SizedBox(height: 14),
              const PixelFieldLabel('分类与状态'),
              FutureBuilder<List<RecipeCategory>>(
                future: _categories,
                builder: (context, state) {
                  if (state.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          PixelLoader(size: 6),
                          SizedBox(width: 12),
                          Text(
                            '正在读取分类…',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.ink2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (state.hasError) {
                    return AppErrorState(
                      message: '分类暂时无法读取，仍可继续保存菜谱。',
                      onRetry: () => setState(
                        () => _categories = widget.backend.listCategories(),
                      ),
                    );
                  }
                  final categories = state.requireData;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final category in categories)
                        _PixelChoiceChip(
                          label: category.name,
                          selected: _selectedCategoryIds.contains(category.id),
                          enabled: !_saving,
                          onPressed: () => setState(() {
                            if (_selectedCategoryIds.contains(category.id)) {
                              _selectedCategoryIds.remove(category.id);
                            } else {
                              _selectedCategoryIds.add(category.id);
                            }
                            _dirty = true;
                          }),
                        ),
                      _PixelChoiceChip(
                        label: '新建',
                        icon: Icons.add_rounded,
                        selected: false,
                        enabled: !_saving,
                        onPressed: () => unawaited(_createCategory()),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              const PixelFieldLabel('标签'),
              _PixelTextField(
                controller: _tagsController,
                enabled: !_saving,
                hintText: '宴客、秋冬暖胃',
                textInputAction: TextInputAction.next,
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _CompactField(
                      label: '份量',
                      child: _PixelTextField(
                        controller: _servingsController,
                        enabled: !_saving,
                        hintText: '3',
                        suffixText: '人份',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _markDirty(),
                        validator: _nonNegativeIntegerValidator,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactField(
                      label: '总耗时',
                      child: _PixelTextField(
                        controller: _totalController,
                        enabled: !_saving,
                        hintText: '70',
                        suffixText: '分钟',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _markDirty(),
                        validator: _nonNegativeIntegerValidator,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactField(
                      label: '难度',
                      child: _PixelDropdown<RecipeDifficulty>(
                        value: _difficulty,
                        enabled: !_saving,
                        items: RecipeDifficulty.values
                            .map(
                              (value) => DropdownMenuItem<RecipeDifficulty>(
                                value: value,
                                child: Text(
                                  _difficultyLabel(value),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _difficulty = value;
                            _dirty = true;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _EditorSectionTitle(
                key: const Key('ingredientsSectionTitle'),
                title: '所需食材',
                eyebrow: '食材',
                icon: Icons.shopping_basket_outlined,
                action: _SectionAddButton(
                  label: '添加',
                  onPressed: _saving ? null : _addIngredient,
                ),
              ),
              const SizedBox(height: 10),
              // 食材支持长按拖动手柄调整顺序，并按 AI 识别的分组（主料/腌料/
              // 调料等）分段展示，方便核对与整理。
              ReorderableListView.builder(
                key: const Key('recipeIngredientsReorderList'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _ingredients.length,
                onReorder: _reorderIngredient,
                itemBuilder: (context, index) {
                  final editor = _ingredients[index];
                  return Padding(
                    key: ValueKey(editor),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_showIngredientGroupHeader(index))
                          _IngredientGroupHeader(
                            label: editor.group.text.trim(),
                            onDelete: _saving
                                ? null
                                : () => _clearIngredientGroup(index),
                          ),
                        _IngredientEditorCard(
                          index: index,
                          editor: editor,
                          enabled: !_saving,
                          canMoveUp: index > 0,
                          canMoveDown: index < _ingredients.length - 1,
                          dragHandle: ReorderableDragStartListener(
                            index: index,
                            child: const _DragHandle(),
                          ),
                          onChanged: _markDirty,
                          // 分组变化时无条件重建父级，让分组标题即时刷新。
                          onGroupChanged: () => setState(() => _dirty = true),
                          onRemove: () => _removeIngredient(index),
                          onMoveUp: () => _moveIngredient(index, -1),
                          onMoveDown: () => _moveIngredient(index, 1),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              _EditorSectionTitle(
                key: const Key('stepsSectionTitle'),
                title: '操作步骤',
                eyebrow: '步骤',
                icon: Icons.format_list_numbered_rounded,
                action: _SectionAddButton(
                  label: '添加',
                  onPressed: _saving ? null : _addStep,
                ),
              ),
              const SizedBox(height: 10),
              // 步骤支持长按拖动手柄调整顺序。
              ReorderableListView.builder(
                key: const Key('recipeStepsReorderList'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _steps.length,
                onReorder: _reorderStep,
                itemBuilder: (context, index) {
                  final editor = _steps[index];
                  return Padding(
                    key: ValueKey(editor),
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _StepEditorCard(
                      index: index,
                      editor: editor,
                      enabled: !_saving,
                      canMoveUp: index > 0,
                      canMoveDown: index < _steps.length - 1,
                      dragHandle: ReorderableDragStartListener(
                        index: index,
                        child: const _DragHandle(),
                      ),
                      onChanged: _markDirty,
                      onRemove: () => _removeStep(index),
                      onMoveUp: () => _moveStep(index, -1),
                      onMoveDown: () => _moveStep(index, 1),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              PixelRowTile(
                title: '更多菜谱信息',
                subtitle: '简介、准备时间、烹饪时间、备注与保存状态',
                icon: Icons.tune_rounded,
                onTap: _saving
                    ? null
                    : () => setState(
                        () => _showRecipeAdvanced = !_showRecipeAdvanced,
                      ),
                trailing: Icon(
                  _showRecipeAdvanced
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.ink3,
                ),
              ),
              if (_showRecipeAdvanced) ...<Widget>[
                const SizedBox(height: 10),
                PixelSurface(
                  cut: 7,
                  elevation: 0,
                  color: AppColors.card2,
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const PixelFieldLabel('简介'),
                      _PixelTextField(
                        controller: _descriptionController,
                        enabled: !_saving,
                        hintText: '这道菜的特点、口味或适合场景',
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _CompactField(
                              label: '准备时间',
                              child: _PixelTextField(
                                controller: _prepController,
                                enabled: !_saving,
                                suffixText: '分钟',
                                keyboardType: TextInputType.number,
                                onChanged: (_) => _markDirty(),
                                validator: _nonNegativeIntegerValidator,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _CompactField(
                              label: '烹饪时间',
                              child: _PixelTextField(
                                controller: _cookController,
                                enabled: !_saving,
                                suffixText: '分钟',
                                keyboardType: TextInputType.number,
                                onChanged: (_) => _markDirty(),
                                validator: _nonNegativeIntegerValidator,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const PixelFieldLabel('备注'),
                      _PixelTextField(
                        controller: _notesController,
                        enabled: !_saving,
                        hintText: '替换食材、失败经验或下次调整建议',
                        minLines: 2,
                        maxLines: 5,
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: 12),
                      const PixelFieldLabel('分类与状态'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: RecipeStatus.values
                            .map(
                              (status) => _PixelChoiceChip(
                                label: _statusLabel(status),
                                selected: _status == status,
                                enabled: !_saving,
                                onPressed: () => setState(() {
                                  _status = status;
                                  _dirty = true;
                                }),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      _PixelToggleRow(
                        label: '收藏这道菜',
                        value: _favorite,
                        enabled: !_saving,
                        onChanged: (value) => setState(() {
                          _favorite = value;
                          _dirty = true;
                        }),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const _EditorSectionTitle(
                title: '来源链接',
                eyebrow: '来源',
                icon: Icons.link_rounded,
              ),
              const SizedBox(height: 10),
              PixelSurface(
                cut: 5,
                elevation: 0,
                color: AppColors.card2,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 12,
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: AppColors.ink3,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.initialRecipe?.sourceId == null
                            ? '手动创建 · 无来源链接'
                            : '已关联来源记录 · ${widget.initialRecipe!.sourceId}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: AppColors.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const PixelNotice(
                title: '手动创建不需要任何 AI 能力',
                message: '未保存离开时会二次确认，保存失败不会丢失已输入内容。',
                icon: Icons.info_outline_rounded,
              ),
            ],
          ),
        ),
        bottomNavigationBar: PixelBottomActionBar(
          child: Row(
            children: <Widget>[
              OutlinedButton(
                key: const Key('cancelRecipeEditButton'),
                onPressed: _saving ? null : () => unawaited(_requestExit()),
                child: const Text('取消'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('saveRecipeButton'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 28, child: PixelLoader(size: 5))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(_saving ? '保存中' : '保存菜谱'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IngredientEditor {
  _IngredientEditor({
    this.id,
    String name = '',
    String group = '',
    String quantity = '',
    String unit = '',
    String preparation = '',
    this.optional = false,
  }) : name = TextEditingController(text: name),
       group = TextEditingController(text: group),
       quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit),
       preparation = TextEditingController(text: preparation);

  factory _IngredientEditor.fromIngredient(Ingredient ingredient) =>
      _IngredientEditor(
        id: ingredient.id,
        name: ingredient.name,
        group: ingredient.groupName ?? '',
        quantity: ingredient.quantity ?? '',
        unit: ingredient.unit ?? '',
        preparation: ingredient.preparation ?? '',
        optional: ingredient.optional,
      );

  final String? id;
  final TextEditingController name;
  final TextEditingController group;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController preparation;
  bool optional;

  bool get isEmpty => <String>[
    name.text,
    group.text,
    quantity.text,
    unit.text,
    preparation.text,
  ].every((value) => value.trim().isEmpty);

  RecipeIngredientInput toInput() => RecipeIngredientInput(
    id: id,
    name: name.text.trim(),
    groupName: _nullableText(group.text),
    quantity: _nullableText(quantity.text),
    unit: _nullableText(unit.text),
    optional: optional,
    preparation: _nullableText(preparation.text),
  );

  void dispose() {
    name.dispose();
    group.dispose();
    quantity.dispose();
    unit.dispose();
    preparation.dispose();
  }
}

class _StepEditor {
  _StepEditor({
    this.id,
    String description = '',
    String durationMinutes = '',
    String temperature = '',
    String heatLevel = '',
    String cookware = '',
    String tips = '',
  }) : description = TextEditingController(text: description),
       durationMinutes = TextEditingController(text: durationMinutes),
       temperature = TextEditingController(text: temperature),
       heatLevel = TextEditingController(text: heatLevel),
       cookware = TextEditingController(text: cookware),
       tips = TextEditingController(text: tips);

  factory _StepEditor.fromStep(RecipeStep step) => _StepEditor(
    id: step.id,
    description: step.description,
    durationMinutes: step.durationSeconds == null
        ? ''
        : (step.durationSeconds! / 60).toStringAsFixed(
            step.durationSeconds! % 60 == 0 ? 0 : 1,
          ),
    temperature: step.temperature ?? '',
    heatLevel: step.heatLevel ?? '',
    cookware: step.cookware ?? '',
    tips: step.tips ?? '',
  );

  final String? id;
  final TextEditingController description;
  final TextEditingController durationMinutes;
  final TextEditingController temperature;
  final TextEditingController heatLevel;
  final TextEditingController cookware;
  final TextEditingController tips;

  bool get isEmpty => <String>[
    description.text,
    durationMinutes.text,
    temperature.text,
    heatLevel.text,
    cookware.text,
    tips.text,
  ].every((value) => value.trim().isEmpty);

  RecipeStepInput toInput() => RecipeStepInput(
    id: id,
    description: description.text.trim(),
    durationSeconds: _nullableMinutesToSeconds(durationMinutes.text),
    temperature: _nullableText(temperature.text),
    heatLevel: _nullableText(heatLevel.text),
    cookware: _nullableText(cookware.text),
    tips: _nullableText(tips.text),
  );

  void dispose() {
    description.dispose();
    durationMinutes.dispose();
    temperature.dispose();
    heatLevel.dispose();
    cookware.dispose();
    tips.dispose();
  }
}

class _IngredientEditorCard extends StatefulWidget {
  const _IngredientEditorCard({
    super.key,
    required this.index,
    required this.editor,
    required this.enabled,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.dragHandle,
    required this.onChanged,
    required this.onGroupChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final _IngredientEditor editor;
  final bool enabled;
  final bool canMoveUp;
  final bool canMoveDown;
  final Widget dragHandle;
  final VoidCallback onChanged;
  final VoidCallback onGroupChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  State<_IngredientEditorCard> createState() => _IngredientEditorCardState();
}

class _IngredientEditorCardState extends State<_IngredientEditorCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PixelSurface(
        cut: 5,
        elevation: 0,
        padding: const EdgeInsets.fromLTRB(8, 7, 7, 7),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                widget.dragHandle,
                const SizedBox(width: 6),
                Expanded(
                  child: _InlineTextField(
                    fieldKey: ValueKey(
                      'recipeIngredientNameField-${widget.index}',
                    ),
                    controller: editor.name,
                    enabled: widget.enabled,
                    hintText: '食材名称',
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                const _InlineDivider(),
                SizedBox(
                  width: 58,
                  child: _InlineTextField(
                    fieldKey: ValueKey(
                      'recipeIngredientQuantityField-${widget.index}',
                    ),
                    controller: editor.quantity,
                    enabled: widget.enabled,
                    hintText: '用量',
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                const _InlineDivider(),
                SizedBox(
                  width: 48,
                  child: _InlineTextField(
                    fieldKey: ValueKey(
                      'recipeIngredientUnitField-${widget.index}',
                    ),
                    controller: editor.unit,
                    enabled: widget.enabled,
                    hintText: '单位',
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                _PixelIconButton(
                  tooltip: '更多字段',
                  icon: _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  onPressed: widget.enabled
                      ? () => setState(() => _expanded = !_expanded)
                      : null,
                ),
                _PixelIconButton(
                  tooltip: '删除食材',
                  icon: Icons.close_rounded,
                  color: AppColors.red,
                  onPressed: widget.enabled ? widget.onRemove : null,
                ),
              ],
            ),
            // 分组常显：可输入自定义分组，或用常用分组快捷填入（主料/辅料等）。
            if (widget.enabled || editor.group.text.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.folder_outlined,
                          size: 14,
                          color: AppColors.greenDeep,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: _InlineTextField(
                            fieldKey: ValueKey(
                              'recipeIngredientGroupField-${widget.index}',
                            ),
                            controller: editor.group,
                            enabled: widget.enabled,
                            hintText: '输入新名称可创建新分组',
                            onChanged: (_) {
                              widget.onGroupChanged();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _commonIngredientGroups
                          .map(
                            (group) => _PixelChoiceChip(
                              label: group,
                              selected: editor.group.text.trim() == group,
                              enabled: widget.enabled,
                              onPressed: () {
                                setState(() => editor.group.text = group);
                                // 让父级重建，分组标题立即刷新。
                                widget.onGroupChanged();
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
            if (_expanded) ...<Widget>[
              const Divider(height: 13),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CompactField(
                      label: '预处理',
                      child: _PixelTextField(
                        controller: editor.preparation,
                        enabled: widget.enabled,
                        hintText: '切块、打散',
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  _PixelToggleRow(
                    compact: true,
                    label: '可选食材',
                    value: editor.optional,
                    enabled: widget.enabled,
                    onChanged: (value) {
                      setState(() => editor.optional = value);
                      widget.onChanged();
                    },
                  ),
                  const Spacer(),
                  _ReorderButtons(
                    enabled: widget.enabled,
                    canMoveUp: widget.canMoveUp,
                    canMoveDown: widget.canMoveDown,
                    onMoveUp: widget.onMoveUp,
                    onMoveDown: widget.onMoveDown,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepEditorCard extends StatefulWidget {
  const _StepEditorCard({
    super.key,
    required this.index,
    required this.editor,
    required this.enabled,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.dragHandle,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final _StepEditor editor;
  final bool enabled;
  final bool canMoveUp;
  final bool canMoveDown;
  final Widget dragHandle;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  State<_StepEditorCard> createState() => _StepEditorCardState();
}

class _StepEditorCardState extends State<_StepEditorCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: PixelSurface(
        cut: 6,
        elevation: 0,
        padding: const EdgeInsets.fromLTRB(8, 8, 7, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: widget.dragHandle,
                ),
                const SizedBox(width: 7),
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.greenDeep,
                    border: Border.fromBorderSide(
                      BorderSide(color: AppColors.ink, width: 1.2),
                    ),
                  ),
                  child: Text(
                    '${widget.index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '步骤 ${widget.index + 1}',
                        style: const TextStyle(
                          color: AppColors.ink2,
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _InlineTextField(
                        fieldKey: ValueKey(
                          'recipeStepDescriptionField-${widget.index}',
                        ),
                        controller: editor.description,
                        enabled: widget.enabled,
                        hintText: '描述本步骤的操作、状态和判断标准',
                        minLines: 2,
                        maxLines: 5,
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ],
                  ),
                ),
                _PixelIconButton(
                  tooltip: '更多字段',
                  icon: _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  onPressed: widget.enabled
                      ? () => setState(() => _expanded = !_expanded)
                      : null,
                ),
                _PixelIconButton(
                  tooltip: '删除步骤',
                  icon: Icons.close_rounded,
                  color: AppColors.red,
                  onPressed: widget.enabled ? widget.onRemove : null,
                ),
              ],
            ),
            if (_expanded) ...<Widget>[
              const Divider(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _CompactField(
                      label: '时长',
                      child: _PixelTextField(
                        controller: editor.durationMinutes,
                        enabled: widget.enabled,
                        hintText: '10',
                        suffixText: '分钟',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          final parsed = double.tryParse(text);
                          return parsed == null || parsed < 0 ? '请输入非负数' : null;
                        },
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactField(
                      label: '温度',
                      child: _PixelTextField(
                        controller: editor.temperature,
                        enabled: widget.enabled,
                        hintText: '180°C',
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _CompactField(
                      label: '火候',
                      child: _PixelTextField(
                        controller: editor.heatLevel,
                        enabled: widget.enabled,
                        hintText: '中小火',
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactField(
                      label: '厨具',
                      child: _PixelTextField(
                        controller: editor.cookware,
                        enabled: widget.enabled,
                        hintText: '炒锅',
                        onChanged: (_) => widget.onChanged(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _CompactField(
                label: '提示',
                child: _PixelTextField(
                  controller: editor.tips,
                  enabled: widget.enabled,
                  hintText: '例如：炒出香味后再进入下一步',
                  minLines: 1,
                  maxLines: 3,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: _ReorderButtons(
                  enabled: widget.enabled,
                  canMoveUp: widget.canMoveUp,
                  canMoveDown: widget.canMoveDown,
                  onMoveUp: widget.onMoveUp,
                  onMoveDown: widget.onMoveDown,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditorSectionTitle extends StatelessWidget {
  const _EditorSectionTitle({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.icon,
    this.action,
  });

  final String title;
  final String eyebrow;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Container(
          width: 31,
          height: 31,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.greenSoft,
            border: Border.fromBorderSide(
              BorderSide(color: AppColors.greenDeep, width: 1.2),
            ),
          ),
          child: Icon(icon, size: 17, color: AppColors.greenDeep),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PxLabel(eyebrow),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .3,
                ),
              ),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class _CoverImageEditor extends StatelessWidget {
  const _CoverImageEditor({
    required this.images,
    required this.picking,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
    required this.onSetCover,
  });

  final List<String> images;
  final bool picking;
  final bool enabled;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onSetCover;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      color: AppColors.card2,
      borderColor: AppColors.line2,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (images.isEmpty) ...<Widget>[
            const Text(
              '还没有封面图。可以从相册选择多张图片，保存后会在详情页轮播展示。',
              style: TextStyle(color: AppColors.ink2, height: 1.5),
            ),
            const SizedBox(height: 12),
          ] else ...<Widget>[
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => _CoverThumb(
                  path: images[index],
                  isCover: index == 0,
                  enabled: enabled,
                  onRemove: () => onRemove(index),
                  onSetCover: () => onSetCover(index),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            key: const Key('addRecipeCoverImagesButton'),
            onPressed: enabled && !picking ? onPick : null,
            icon: picking
                ? const SizedBox.square(
                    dimension: 16,
                    child: Center(child: PixelLoader(size: 3)),
                  )
                : const Icon(Icons.add_photo_alternate_rounded, size: 18),
            label: Text(picking ? '正在读取图片…' : '添加封面图（可多选）'),
          ),
        ],
      ),
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({
    required this.path,
    required this.isCover,
    required this.enabled,
    required this.onRemove,
    required this.onSetCover,
  });

  final String path;
  final bool isCover;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback onSetCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: AppColors.paper2,
                child: const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.ink3,
                    size: 26,
                  ),
                ),
              ),
            ),
            if (isCover)
              const Positioned(
                left: 0,
                top: 0,
                child: _CoverBadge(label: '封面'),
              )
            else
              Positioned(
                left: 0,
                top: 0,
                child: InkWell(
                  key: Key('setRecipeCoverImage-$path'),
                  onTap: enabled ? onSetCover : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    color: AppColors.amber.withValues(alpha: .92),
                    child: const Text(
                      '设为封面',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 2,
              top: 2,
              child: InkWell(
                key: Key('removeRecipeCoverImage-$path'),
                onTap: enabled ? onRemove : null,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  color: AppColors.ink.withValues(alpha: .55),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverBadge extends StatelessWidget {
  const _CoverBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: AppColors.greenDeep,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SectionAddButton extends StatelessWidget {
  const _SectionAddButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        elevation: 0,
      ),
      icon: const Icon(Icons.add_rounded, size: 15),
      label: Text(label),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[PixelFieldLabel(label), child],
    );
  }
}

class _PixelTextField extends StatelessWidget {
  const _PixelTextField({
    this.fieldKey,
    required this.controller,
    this.enabled = true,
    this.hintText,
    this.suffixText,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.textInputAction,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final String? hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: 4,
      elevation: 0,
      color: enabled ? AppColors.card : AppColors.paper2,
      padding: EdgeInsets.zero,
      child: TextFormField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        autofocus: false,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        validator: validator,
        onChanged: onChanged,
        textInputAction: textInputAction,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: hintText,
          suffixText: suffixText,
          suffixStyle: const TextStyle(
            color: AppColors.ink3,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 11,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          errorStyle: const TextStyle(
            color: AppColors.red,
            fontSize: 10,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _PixelDropdown<T> extends StatelessWidget {
  const _PixelDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: 4,
      elevation: 0,
      color: enabled ? AppColors.card : AppColors.paper2,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.unfold_more_rounded, size: 16),
          borderRadius: BorderRadius.zero,
          menuMaxHeight: 320,
          items: items,
          onChanged: enabled ? onChanged : null,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PixelChoiceChip extends StatelessWidget {
  const _PixelChoiceChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.greenInk : AppColors.ink2;
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: ClipPath(
        clipper: const PixelCutClipper(cut: 3),
        child: Material(
          color: selected ? AppColors.greenSoft : AppColors.card,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? AppColors.greenDeep : AppColors.line2,
                  width: selected ? 1.5 : 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 14, color: foreground),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelToggleRow extends StatelessWidget {
  const _PixelToggleRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 4 : 7),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: <Widget>[
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value ? AppColors.greenDeep : AppColors.card,
                  border: Border.all(color: AppColors.ink, width: 1.4),
                  boxShadow: value
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x3336403A),
                            offset: Offset(2, 2),
                          ),
                        ]
                      : null,
                ),
                child: value
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 11 : 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 常用食材分组，供编辑时快捷填入。
const List<String> _commonIngredientGroups = <String>[
  '主料',
  '辅料',
  '腌料',
  '调料',
  '酱汁',
];

/// 按分组稳定归并食材：同分组相邻（组内保持原顺序），未分组排在最后。
void _sortIngredientsByGroup(List<_IngredientEditor> ingredients) {
  if (ingredients.length < 2) return;
  final groups = <String>[];
  for (final editor in ingredients) {
    final group = editor.group.text.trim();
    if (group.isNotEmpty && !groups.contains(group)) groups.add(group);
  }
  final ordered = <_IngredientEditor>[];
  for (final group in groups) {
    ordered.addAll(
      ingredients.where((editor) => editor.group.text.trim() == group),
    );
  }
  ordered.addAll(
    ingredients.where((editor) => editor.group.text.trim().isEmpty),
  );
  ingredients
    ..clear()
    ..addAll(ordered);
}

class _IngredientGroupHeader extends StatelessWidget {
  const _IngredientGroupHeader({required this.label, this.onDelete});

  final String label;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 0, 6),
      child: Row(
        children: <Widget>[
          Icon(Icons.folder_outlined, size: 15, color: AppColors.greenDeep),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.greenDeep,
              letterSpacing: .3,
            ),
          ),
          const Spacer(),
          if (onDelete != null)
            IconButton(
              tooltip: '删除该分组',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 17,
                color: AppColors.ink2,
              ),
            ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 30,
      child: CustomPaint(painter: _DragHandlePainter()),
    );
  }
}

class _DragHandlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.ink3;
    for (var row = 0; row < 3; row += 1) {
      for (var column = 0; column < 2; column += 1) {
        canvas.drawRect(
          Rect.fromLTWH(2 + column * 6, 7 + row * 6, 3, 3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DragHandlePainter oldDelegate) => false;
}

class _InlineTextField extends StatelessWidget {
  const _InlineTextField({
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
    this.minLines,
    this.maxLines = 1,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;
  final int? minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.line),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.line),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.greenDeep, width: 2),
        ),
        disabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.line),
        ),
      ),
    );
  }
}

class _InlineDivider extends StatelessWidget {
  const _InlineDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 27,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: AppColors.line,
    );
  }
}

class _PixelIconButton extends StatelessWidget {
  const _PixelIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color = AppColors.ink2,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: onPressed == null ? AppColors.ink3 : color),
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 32),
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
    );
  }
}

class _ReorderButtons extends StatelessWidget {
  const _ReorderButtons({
    required this.enabled,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final bool enabled;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _PixelIconButton(
          tooltip: '上移',
          icon: Icons.keyboard_arrow_up_rounded,
          onPressed: enabled && canMoveUp ? onMoveUp : null,
        ),
        _PixelIconButton(
          tooltip: '下移',
          icon: Icons.keyboard_arrow_down_rounded,
          onPressed: enabled && canMoveDown ? onMoveDown : null,
        ),
      ],
    );
  }
}

String? _nonNegativeIntegerValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = int.tryParse(text);
  return parsed == null || parsed < 0 ? '请输入非负整数' : null;
}

String _intText(int? value) => value?.toString() ?? '';

String? _nullableText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _nullableInt(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : int.parse(trimmed);
}

int? _nullableMinutesToSeconds(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final minutes = double.parse(trimmed);
  if (minutes < 0) throw const FormatException('步骤时长不能小于 0。');
  return (minutes * 60).round();
}

List<String> _parseTags(String value) {
  final seen = <String>{};
  return value
      .split(RegExp(r'[,，、\n]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty && seen.add(tag))
      .toList(growable: false);
}

String _difficultyLabel(RecipeDifficulty value) => switch (value) {
  RecipeDifficulty.unspecified => '未指定',
  RecipeDifficulty.easy => '简单',
  RecipeDifficulty.medium => '中等',
  RecipeDifficulty.hard => '困难',
};

String _statusLabel(RecipeStatus value) => switch (value) {
  RecipeStatus.draft => '草稿',
  RecipeStatus.published => '已发布',
  RecipeStatus.archived => '已归档',
};
