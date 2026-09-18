import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/recipe/recipe_library_commands.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';

class ImportDraftReviewResult {
  const ImportDraftReviewResult.saved(this.recipe) : discarded = false;

  const ImportDraftReviewResult.discarded() : recipe = null, discarded = true;

  final Recipe? recipe;
  final bool discarded;
}

class ImportDraftReviewPage extends StatefulWidget {
  const ImportDraftReviewPage({
    super.key,
    required this.backend,
    required this.taskId,
    required this.onDataChanged,
    this.evidence,
    this.recipeId,
  });

  final AiRecipeBackendFacade backend;
  final String taskId;
  final VoidCallback onDataChanged;
  final ImportContent? evidence;

  /// 指定要审阅的草稿 ID（多草稿任务的附加草稿，IMAGE-002）；为空时使用
  /// 任务主草稿。
  final String? recipeId;

  @override
  State<ImportDraftReviewPage> createState() => _ImportDraftReviewPageState();
}

class _ImportDraftReviewPageState extends State<ImportDraftReviewPage> {
  static const _lowConfidenceThreshold = 0.7;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _servingsController = TextEditingController();
  final _prepController = TextEditingController();
  final _cookController = TextEditingController();
  final _totalController = TextEditingController();
  final _confirmedFields = <String>{};
  final _ingredients = <_IngredientEditor>[];
  final _steps = <_StepEditor>[];

  Recipe? _recipe;
  ImportTask? _task;
  RecipeDifficulty _difficulty = RecipeDifficulty.unspecified;
  var _loading = true;
  var _saving = false;
  var _regenerating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _servingsController.dispose();
    _prepController.dispose();
    _cookController.dispose();
    _totalController.dispose();
    for (final editor in _ingredients) {
      editor.dispose();
    }
    for (final editor in _steps) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        widget.backend.getImportDraft(widget.taskId, recipeId: widget.recipeId),
        widget.backend.getImportTask(widget.taskId),
      ]);
      final recipe = results[0] as Recipe;
      final task = results[1] as ImportTask;
      if (!mounted) return;
      // 重新生成后需要重建表单：先释放旧的行编辑器，再重建。
      for (final editor in _ingredients) {
        editor.dispose();
      }
      for (final editor in _steps) {
        editor.dispose();
      }
      _ingredients.clear();
      _steps.clear();
      _confirmedFields.clear();
      _titleController.text = recipe.title;
      _descriptionController.text = recipe.description ?? '';
      _servingsController.text = _numberText(recipe.servings);
      _prepController.text = _numberText(recipe.prepTimeMinutes);
      _cookController.text = _numberText(recipe.cookTimeMinutes);
      _totalController.text = _numberText(recipe.totalTimeMinutes);
      _ingredients.addAll(
        recipe.ingredients.map(_IngredientEditor.fromIngredient),
      );
      // 同分组食材归并相邻展示，避免出现两个相同分组标题。
      if (_ingredients.length > 1) _sortReviewIngredientsByGroup(_ingredients);
      _steps.addAll(recipe.steps.map(_StepEditor.fromStep));
      setState(() {
        _recipe = recipe;
        _task = task;
        _difficulty = recipe.difficulty;
        _loading = false;
      });
    } on AiRecipeBackendException catch (error) {
      _showLoadError(error.message);
    } catch (_) {
      _showLoadError('AI 草稿暂时无法读取，请稍后重试。');
    }
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _errorMessage = message;
    });
  }

  void _addIngredient() {
    setState(() => _ingredients.add(_IngredientEditor.empty()));
  }

  void _removeIngredient(int index) {
    final editor = _ingredients.removeAt(index);
    editor.dispose();
    setState(() {});
  }

  void _addStep() {
    setState(() => _steps.add(_StepEditor.empty()));
  }

  void _removeStep(int index) {
    final editor = _steps.removeAt(index);
    editor.dispose();
    setState(() {});
  }

  /// 删除分组：清空该组全部食材的分组，分组标题随即消失。
  void _clearReviewGroup(String group) {
    final normalized = group.trim();
    if (normalized.isEmpty) return;
    setState(() {
      for (final editor in _ingredients) {
        if (editor.group.text.trim() == normalized) {
          editor.group.text = '';
        }
      }
    });
  }

  void _confirmField(String key) {
    setState(() => _confirmedFields.add(key));
  }

  Future<void> _save() async {
    if (_saving || _recipe == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final original = _recipe!;
    try {
      final confirmation = await widget.backend.confirmImportDraft(
        widget.taskId,
        // 多草稿任务（IMAGE-002）：保存当前审阅的草稿；任务在其他草稿
        // 未确认时保持 needsReview，确认页返回后由进度页继续下一份。
        recipeId: widget.recipeId,
        editedDraft: RecipeDraftInput(
          title: _titleController.text.trim(),
          description: _optionalText(_descriptionController.text),
          coverImage: original.coverImage,
          images: original.images,
          servings: _optionalInt(_servingsController.text),
          prepTimeMinutes: _optionalInt(_prepController.text),
          cookTimeMinutes: _optionalInt(_cookController.text),
          totalTimeMinutes: _optionalInt(_totalController.text),
          difficulty: _difficulty,
          notes: original.notes,
          favorite: original.favorite,
          status: original.status,
          categoryIds: original.categoryIds,
          tags: original.tags,
          ingredients: _ingredients
              .map((editor) => editor.toInput())
              .toList(growable: false),
          steps: _steps
              .map((editor) => editor.toInput())
              .toList(growable: false),
        ),
      );
      widget.onDataChanged();
      // 保存完成后须用 context.mounted 判断（而非仅 State.mounted）：路由退场
      // 过渡期 Element 已 deactivate 但 State.mounted 仍为 true，此时 pop 会触发
      // framework 断言（_elements.contains(element) / deactivated widget's ancestor）。
      if (!context.mounted) return;
      Navigator.of(
        context,
      ).pop(ImportDraftReviewResult.saved(confirmation.recipe));
    } on AiRecipeBackendException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '保存失败，请检查草稿后重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    if (_saving) return;
    final confirmed = await showPixelConfirm(
      context: context,
      title: '放弃这份 AI 草稿？',
      message: '草稿会移入本机回收站，导入任务将标记为已取消。',
      confirmLabel: '确认放弃',
      cancelLabel: '继续检查',
      confirmKey: const Key('confirmDiscardImportDraftButton'),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await widget.backend.discardImportDraft(widget.taskId);
      widget.onDataChanged();
      // 同 _save：用 context.mounted 覆盖路由退场过渡期，避免在已 deactivate 的
      // Element 上 pop 触发 framework 断言。
      if (!context.mounted) return;
      Navigator.of(context).pop(const ImportDraftReviewResult.discarded());
    } on AiRecipeBackendException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 使用会话内保存的原文重新生成草稿。
  ///
  /// 需要二次确认；成功后重建表单为新草稿，失败保留旧草稿并显示稳定错误。
  Future<void> _regenerate() async {
    if (_saving || _regenerating || widget.evidence == null) return;
    final confirmed = await showPixelConfirm(
      context: context,
      title: '重新生成这份 AI 草稿？',
      message: '将使用同一原文重新生成，当前已做的编辑会被替换。',
      confirmLabel: '确认重新生成',
      cancelLabel: '继续编辑',
      confirmKey: const Key('confirmRegenerateImportDraftButton'),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _regenerating = true;
      _errorMessage = null;
    });
    try {
      await widget.backend.regenerateImportDraft(
        widget.taskId,
        content: widget.evidence!,
      );
      if (!mounted) return;
      await _load();
    } on AiRecipeBackendException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '重新生成失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PixelPageAppBar(
        title: '确认草稿',
        eyebrow: 'AI 草稿确认',
        actions: _recipe == null
            ? null
            : const <Widget>[
                Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Center(
                    child: PixelBadge(
                      label: '待确认',
                      icon: Icons.fact_check_outlined,
                      tone: PixelNoticeTone.amber,
                    ),
                  ),
                ),
              ],
      ),
      body: _loading
          ? const AppLoadingState(label: '正在读取 AI 草稿…')
          : _recipe == null
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: _DraftLoadFailure(message: _errorMessage, onRetry: _load),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 124),
                children: <Widget>[
                  _ReviewIntro(
                    task: _task!,
                    recipe: _recipe!,
                    lowConfidenceCount: _lowConfidenceCount,
                  ),
                  const SizedBox(height: 16),
                  _RegenerateAction(
                    enabled: !_saving && !_regenerating && widget.evidence != null,
                    busy: _regenerating,
                    evidenceAvailable: widget.evidence != null,
                    onPressed: _regenerate,
                  ),
                  // 原文有配图但草稿未获得本地封面时，明确提示下载未成功。
                  if (_evidenceHasImages && _recipe!.images.isEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    const PixelNotice(
                      title: '笔记配图暂未获取',
                      message: '原文包含图片但下载未成功，保存后可在编辑页手动添加封面。',
                      icon: Icons.image_not_supported_outlined,
                      tone: PixelNoticeTone.amber,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _SectionCard(
                    label: 'BASIC INFO',
                    title: '基础信息',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const PixelFieldLabel('菜名', required: true),
                        TextFormField(
                          key: const Key('importDraftTitleField'),
                          controller: _titleController,
                          enabled: !_saving,
                          decoration: const InputDecoration(hintText: '请输入菜名'),
                          validator: _requiredValidator,
                        ),
                        const SizedBox(height: 12),
                        const PixelFieldLabel('简介'),
                        TextFormField(
                          controller: _descriptionController,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: '简单描述口味、特色或来源说明',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: _NumberField(
                                controller: _servingsController,
                                label: '份量',
                                suffix: '人份',
                                enabled: !_saving,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  const PixelFieldLabel('难度'),
                                  DropdownButtonFormField<RecipeDifficulty>(
                                    initialValue: _difficulty,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                    ),
                                    items: RecipeDifficulty.values
                                        .map(
                                          (value) =>
                                              DropdownMenuItem<
                                                RecipeDifficulty
                                              >(
                                                value: value,
                                                child: Text(
                                                  _difficultyLabel(value),
                                                ),
                                              ),
                                        )
                                        .toList(growable: false),
                                    onChanged: _saving
                                        ? null
                                        : (value) => setState(
                                            () => _difficulty =
                                                value ??
                                                RecipeDifficulty.unspecified,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: _NumberField(
                                controller: _prepController,
                                label: '备菜',
                                suffix: '分钟',
                                enabled: !_saving,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NumberField(
                                controller: _cookController,
                                label: '烹饪',
                                suffix: '分钟',
                                enabled: !_saving,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _NumberField(
                                controller: _totalController,
                                label: '总计',
                                suffix: '分钟',
                                enabled: !_saving,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionHeader(
                    'INGREDIENTS · ${_ingredients.length}',
                    '食材',
                    '检查名称、用量和低置信度项',
                    _addIngredient,
                  ),
                  // 按 AI 识别的分组（主料/腌料/调料等）分段展示，方便核对。
                  ...List<Widget>.generate(
                    _ingredients.length,
                    (index) {
                      final editor = _ingredients[index];
                      final group = editor.group.text.trim();
                      final showHeader =
                          group.isNotEmpty &&
                          (index == 0 ||
                              _ingredients[index - 1].group.text.trim() !=
                                  group);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (showHeader)
                            _ReviewGroupHeader(
                              label: group,
                              onDelete: _saving
                                  ? null
                                  : () => _clearReviewGroup(group),
                            ),
                          _IngredientEditorCard(
                            key: ValueKey('importIngredient-$index'),
                            backend: widget.backend,
                            index: index,
                            editor: editor,
                            enabled: !_saving,
                            confirmed: _confirmedFields.contains(
                              'ingredient-$index',
                            ),
                            // 分组变化时重建父级，分组标题即时刷新。
                            onChanged: () => setState(() {}),
                            onConfirm: () =>
                                _confirmField('ingredient-$index'),
                            onRemove: () => _removeIngredient(index),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _sectionHeader(
                    'STEPS · ${_steps.length}',
                    '操作步骤',
                    '检查顺序、描述和预计时长',
                    _addStep,
                  ),
                  ...List<Widget>.generate(
                    _steps.length,
                    (index) => _StepEditorCard(
                      key: ValueKey('importStep-$index'),
                      index: index,
                      editor: _steps[index],
                      enabled: !_saving,
                      confirmed: _confirmedFields.contains('step-$index'),
                      onConfirm: () => _confirmField('step-$index'),
                      onRemove: () => _removeStep(index),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _EvidencePanel(evidence: widget.evidence),
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ReviewError(message: _errorMessage!),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: _recipe == null
          ? null
          : PixelBottomActionBar(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('discardImportDraftButton'),
                      onPressed: _saving ? null : _discard,
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: const Text('放弃草稿'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const Key('saveImportDraftButton'),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: Center(child: PixelLoader(size: 3)),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(_saving ? '保存中' : '保存菜谱'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  int get _lowConfidenceCount =>
      _ingredients.where((item) => item.isLowConfidence).length +
      _steps.where((item) => item.isLowConfidence).length;

  /// 会话原文是否包含图片（用于判断配图下载失败提示）。
  bool get _evidenceHasImages =>
      widget.evidence?.media
              .any((media) => media.kind == ImportMediaKind.image) ??
      false;

  Widget _sectionHeader(
    String label,
    String title,
    String subtitle,
    VoidCallback onAdd,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PxLabel(label),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : onAdd,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

class _RegenerateAction extends StatelessWidget {
  const _RegenerateAction({
    required this.enabled,
    required this.busy,
    required this.evidenceAvailable,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final bool evidenceAvailable;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      color: AppColors.card2,
      borderColor: AppColors.line2,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PxLabel('重新生成'),
          const SizedBox(height: 8),
          Text(
            evidenceAvailable
                ? '对这份 AI 结果不满意？'
                : '原始内容已过期，无法重新生成',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            '重新生成会使用同一原文再次交给 AI 整理，已做的编辑会被替换。',
            style: TextStyle(color: AppColors.ink2, height: 1.45),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('regenerateImportDraftButton'),
            onPressed: enabled ? onPressed : null,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: Center(child: PixelLoader(size: 3)),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 17),
            label: Text(busy ? '正在重新生成…' : '重新生成'),
          ),
        ],
      ),
    );
  }
}

class _ReviewIntro extends StatelessWidget {
  const _ReviewIntro({
    required this.task,
    required this.recipe,
    required this.lowConfidenceCount,
  });

  final ImportTask task;
  final Recipe recipe;
  final int lowConfidenceCount;

  @override
  Widget build(BuildContext context) {
    final tone = lowConfidenceCount == 0
        ? PixelNoticeTone.green
        : PixelNoticeTone.amber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PixelSurface(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              // 封面区：链接导入自动获取的配图在这里直接展示（首图），
              // 无图时回退像素插画；多图时右下角显示数量徽标。
              _DraftCover(recipe: recipe),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        PixelBadge(
                          label: _platformLabel(task.sourcePlatform),
                          icon: Icons.link_rounded,
                          tone: PixelNoticeTone.green,
                        ),
                        Text(
                          task.normalizedUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            color: AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PixelNotice(
          title: lowConfidenceCount == 0
              ? 'AI 已完成结构化整理'
              : '发现 $lowConfidenceCount 项低置信度内容',
          message: lowConfidenceCount == 0
              ? '食材与步骤均达到当前置信度阈值，请保存前再快速复核。'
              : 'AI 可能识别错误，请检查食材和步骤；低置信度项可以标记已核对。',
          icon: lowConfidenceCount == 0
              ? Icons.verified_outlined
              : Icons.warning_amber_rounded,
          tone: tone,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: <Widget>[
            ...recipe.tags
                .take(2)
                .map(
                  (tag) => PixelBadge(label: tag, tone: PixelNoticeTone.green),
                ),
            if (recipe.servings != null)
              PixelBadge(
                label: '${recipe.servings} 人份',
                icon: Icons.people_alt_outlined,
              ),
            if (recipe.totalTimeMinutes != null)
              PixelBadge(
                label: '约 ${recipe.totalTimeMinutes} 分钟',
                icon: Icons.schedule_rounded,
              ),
            PixelBadge(label: '${_difficultyLabel(recipe.difficulty)}难度'),
          ],
        ),
      ],
    );
  }
}

/// 草稿确认页封面：链接导入自动获取的配图在这里直接展示（首图），
/// 无图时回退像素插画；多图时右下角显示数量徽标。
class _DraftCover extends StatelessWidget {
  const _DraftCover({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final cover = recipe.coverImage;
    final hasCover = cover != null && cover.trim().isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox.square(
            dimension: 64,
            child: hasCover
                ? Image.file(
                    File(cover!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(),
                  )
                : _placeholder(),
          ),
        ),
        if (recipe.images.length > 1)
          Positioned(
            right: -5,
            bottom: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.greenDeep,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.ink, width: 1),
              ),
              child: Text(
                '${recipe.images.length} 张',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder() {
    return PixelSurface(
      cut: 4,
      elevation: 0,
      color: _draftCoverColor(recipe.id),
      child: SizedBox.square(
        dimension: 64,
        child: Icon(
          _draftCoverIcon(recipe.title),
          size: 34,
          color: AppColors.greenDeep,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.label,
    required this.title,
    required this.child,
  });
  final String label;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PxLabel(label),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// 常用食材分组，供草稿确认时快捷填入。
const List<String> _reviewCommonGroups = <String>[
  '主料',
  '辅料',
  '腌料',
  '调料',
  '酱汁',
];

/// 按分组稳定归并食材：同分组相邻（组内保持原顺序），未分组排在最后。
void _sortReviewIngredientsByGroup(List<_IngredientEditor> ingredients) {
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

/// 草稿确认页食材分组标题（主料/腌料/调料等）。
class _ReviewGroupHeader extends StatelessWidget {
  const _ReviewGroupHeader({required this.label, this.onDelete});

  final String label;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 0, 6),
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

class _IngredientEditorCard extends StatefulWidget {
  const _IngredientEditorCard({
    super.key,
    required this.backend,
    required this.index,
    required this.editor,
    required this.enabled,
    required this.confirmed,
    required this.onChanged,
    required this.onConfirm,
    required this.onRemove,
  });

  final AiRecipeBackendFacade backend;
  final int index;
  final _IngredientEditor editor;
  final bool enabled;
  final bool confirmed;
  final VoidCallback onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onRemove;

  @override
  State<_IngredientEditorCard> createState() => _IngredientEditorCardState();
}

class _IngredientEditorCardState extends State<_IngredientEditorCard> {
  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final editor = widget.editor;
    final enabled = widget.enabled;
    final confirmed = widget.confirmed;
    final needsReview = editor.isLowConfidence && !confirmed;
    // ADR-0022 轻量标识：名称未被本地词典识别时提示“种类待确认”。
    final specUnresolved = !widget.backend.isIngredientNameKnown(
      editor.name.text,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PixelSurface(
        color: needsReview ? AppColors.amberSoft : AppColors.card,
        borderColor: needsReview ? AppColors.amber : AppColors.line2,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _EditorHeader(
              title: '食材 ${index + 1}',
              confidence: editor.confidence,
              lowConfidence: editor.isLowConfidence,
              specBadge: specUnresolved ? '种类待确认' : null,
              confirmed: confirmed,
              onConfirm: widget.onConfirm,
              onRemove: widget.onRemove,
              enabled: enabled,
            ),
            const SizedBox(height: 10),
            const PixelFieldLabel('名称', required: true),
            TextFormField(
              key: Key('importIngredientName-$index'),
              controller: editor.name,
              enabled: enabled,
              decoration: const InputDecoration(hintText: '例如：番茄'),
              validator: _requiredValidator,
            ),
            const SizedBox(height: 10),
            // 分组常显：可输入自定义分组，或点常用分组快捷填入。
            const PixelFieldLabel('分组'),
            TextFormField(
              key: Key('importIngredientGroup-$index'),
              controller: editor.group,
              enabled: enabled,
              decoration: const InputDecoration(hintText: '输入新名称可创建新分组'),
              onChanged: (_) => widget.onChanged(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _reviewCommonGroups
                  .map(
                    (group) => ChoiceChip(
                      label: Text(
                        group,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: editor.group.text.trim() == group,
                      onSelected: enabled
                          ? (_) {
                              setState(() => editor.group.text = group);
                              // 让父级重建，分组标题立即刷新。
                              widget.onChanged();
                            }
                          : null,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _LabeledTextField(
                    controller: editor.quantity,
                    enabled: enabled,
                    label: '用量',
                    hintText: '例如：500',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LabeledTextField(
                    controller: editor.unit,
                    enabled: enabled,
                    label: '单位',
                    hintText: '例如：g / 个',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepEditorCard extends StatelessWidget {
  const _StepEditorCard({
    super.key,
    required this.index,
    required this.editor,
    required this.enabled,
    required this.confirmed,
    required this.onConfirm,
    required this.onRemove,
  });

  final int index;
  final _StepEditor editor;
  final bool enabled;
  final bool confirmed;
  final VoidCallback onConfirm;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final needsReview = editor.isLowConfidence && !confirmed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PixelSurface(
        color: needsReview ? AppColors.amberSoft : AppColors.card,
        borderColor: needsReview ? AppColors.amber : AppColors.line2,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PixelSurface(
              cut: 3,
              elevation: 0,
              color: AppColors.greenSoft,
              borderColor: AppColors.greenDeep,
              child: SizedBox.square(
                dimension: 32,
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w900,
                      color: AppColors.greenInk,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _EditorHeader(
                    title: '步骤 ${index + 1}',
                    confidence: editor.confidence,
                    lowConfidence: editor.isLowConfidence,
                    confirmed: confirmed,
                    onConfirm: onConfirm,
                    onRemove: onRemove,
                    enabled: enabled,
                  ),
                  const SizedBox(height: 10),
                  const PixelFieldLabel('操作说明', required: true),
                  TextFormField(
                    key: Key('importStepDescription-$index'),
                    controller: editor.description,
                    enabled: enabled,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(hintText: '请输入本步骤的具体做法'),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    controller: editor.durationSeconds,
                    label: '预计时长',
                    suffix: '秒',
                    enabled: enabled,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.title,
    required this.confidence,
    required this.lowConfidence,
    this.specBadge,
    required this.confirmed,
    required this.onConfirm,
    required this.onRemove,
    required this.enabled,
  });

  final String title;
  final double? confidence;
  final bool lowConfidence;

  /// ADR-0022 轻量规格标识（如“种类待确认”）。
  final String? specBadge;
  final bool confirmed;
  final VoidCallback onConfirm;
  final VoidCallback onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (specBadge != null)
              PixelBadge(
                label: specBadge!,
                icon: Icons.help_outline_rounded,
                tone: PixelNoticeTone.amber,
              ),
            if (confidence != null)
              PixelBadge(
                label: '${(confidence! * 100).round()}%',
                icon: lowConfidence
                    ? Icons.warning_amber_rounded
                    : Icons.verified_outlined,
                tone: lowConfidence
                    ? PixelNoticeTone.amber
                    : PixelNoticeTone.green,
              ),
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
            ),
          ],
        ),
        if (lowConfidence)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: enabled && !confirmed ? onConfirm : null,
              icon: Icon(
                confirmed ? Icons.check_rounded : Icons.fact_check_outlined,
                size: 15,
              ),
              label: Text(confirmed ? '已核对' : '标记已核对'),
              style: TextButton.styleFrom(
                foregroundColor: confirmed
                    ? AppColors.greenDeep
                    : AppColors.amber,
              ),
            ),
          ),
      ],
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({required this.evidence});

  final ImportContent? evidence;

  @override
  Widget build(BuildContext context) {
    final fragments = evidence?.textFragments ?? const <ImportTextFragment>[];
    return PixelSurface(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: const Key('importEvidencePanel'),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.source_outlined, color: AppColors.greenDeep),
        title: const Text(
          '原始内容依据',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          fragments.isEmpty
              ? '本次会话未保留完整原文片段'
              : '本次会话保留 ${fragments.length} 条文本片段',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: <Widget>[
          const PixelNotice(
            title: '依据映射限制',
            message: '当前后端尚未提供字段与证据的一一映射。系统不会伪造某个字段的来源依据。',
            icon: Icons.info_outline_rounded,
            tone: PixelNoticeTone.blue,
          ),
          const SizedBox(height: 10),
          if (fragments.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('完整原文片段未在本次会话中保留。请根据来源链接检查低置信度内容。'),
            )
          else ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('copyEvidenceButton'),
                onPressed: () => _copyEvidence(context, fragments),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制全部原文'),
              ),
            ),
            const SizedBox(height: 4),
            ...fragments.map(
              (fragment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PixelSurface(
                  cut: 4,
                  elevation: 0,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      PxLabel(_fragmentMeta(fragment)),
                      const SizedBox(height: 6),
                      SelectableText(fragment.text),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 一键复制全部文本片段拼接后的完整原文。
  Future<void> _copyEvidence(
    BuildContext context,
    List<ImportTextFragment> fragments,
  ) async {
    final text = fragments.map((fragment) => fragment.text).join('\n\n');
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制原始内容')),
      );
    }
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.hintText,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String hintText;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      PixelFieldLabel(label),
      TextFormField(
        controller: controller,
        enabled: enabled,
        decoration: InputDecoration(hintText: hintText),
      ),
    ],
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PixelFieldLabel(label),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: suffix),
          validator: (value) {
            final fieldText = value?.trim() ?? '';
            if (fieldText.isEmpty) return null;
            final parsed = int.tryParse(fieldText);
            if (parsed == null || parsed < 0) return '请输入非负整数';
            return null;
          },
        ),
      ],
    );
  }
}

class _ReviewError extends StatelessWidget {
  const _ReviewError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PixelNotice(
      title: '保存草稿失败',
      message: message,
      icon: Icons.error_outline_rounded,
      tone: PixelNoticeTone.red,
    );
  }
}

class _DraftLoadFailure extends StatelessWidget {
  const _DraftLoadFailure({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppErrorState(message: message ?? 'AI 草稿暂时无法读取。', onRetry: onRetry);
  }
}

Color _draftCoverColor(String seed) {
  final colors = <Color>[
    AppColors.greenSoft,
    AppColors.amberSoft,
    AppColors.blueSoft,
    AppColors.redSoft,
  ];
  return colors[seed.hashCode.abs() % colors.length];
}

IconData _draftCoverIcon(String title) {
  if (title.contains('面') || title.contains('粉')) {
    return Icons.ramen_dining_rounded;
  }
  if (title.contains('汤')) return Icons.soup_kitchen_rounded;
  if (title.contains('饭')) return Icons.rice_bowl_rounded;
  return Icons.restaurant_rounded;
}

class _IngredientEditor {
  _IngredientEditor({
    required this.id,
    required String name,
    required String quantity,
    required String unit,
    required String groupName,
    required this.optional,
    required this.preparation,
    required this.substitutes,
    required this.confidence,
  }) : name = TextEditingController(text: name),
       quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit),
       group = TextEditingController(text: groupName);

  factory _IngredientEditor.fromIngredient(Ingredient ingredient) =>
      _IngredientEditor(
        id: ingredient.id,
        name: ingredient.name,
        quantity: ingredient.quantity ?? '',
        unit: ingredient.unit ?? '',
        groupName: ingredient.groupName ?? '',
        optional: ingredient.optional,
        preparation: ingredient.preparation,
        substitutes: ingredient.substitutes,
        confidence: ingredient.confidence,
      );

  factory _IngredientEditor.empty() => _IngredientEditor(
    id: null,
    name: '',
    quantity: '',
    unit: '',
    groupName: '',
    optional: false,
    preparation: null,
    substitutes: const <String>[],
    confidence: null,
  );

  final String? id;
  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController group;
  final bool optional;
  final String? preparation;
  final List<String> substitutes;
  final double? confidence;

  bool get isLowConfidence =>
      confidence != null &&
      confidence! < _ImportDraftReviewPageState._lowConfidenceThreshold;

  RecipeIngredientInput toInput() => RecipeIngredientInput(
    id: id,
    name: name.text.trim(),
    groupName: _optionalText(group.text),
    quantity: _optionalText(quantity.text),
    unit: _optionalText(unit.text),
    optional: optional,
    preparation: preparation,
    substitutes: substitutes,
    confidence: confidence,
  );

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    group.dispose();
  }
}

class _StepEditor {
  _StepEditor({
    required this.id,
    required String description,
    required String durationSeconds,
    required this.temperature,
    required this.heatLevel,
    required this.cookware,
    required this.tips,
    required this.mediaUrl,
    required this.confidence,
  }) : description = TextEditingController(text: description),
       durationSeconds = TextEditingController(text: durationSeconds);

  factory _StepEditor.fromStep(RecipeStep step) => _StepEditor(
    id: step.id,
    description: step.description,
    durationSeconds: _numberText(step.durationSeconds),
    temperature: step.temperature,
    heatLevel: step.heatLevel,
    cookware: step.cookware,
    tips: step.tips,
    mediaUrl: step.mediaUrl,
    confidence: step.confidence,
  );

  factory _StepEditor.empty() => _StepEditor(
    id: null,
    description: '',
    durationSeconds: '',
    temperature: null,
    heatLevel: null,
    cookware: null,
    tips: null,
    mediaUrl: null,
    confidence: null,
  );

  final String? id;
  final TextEditingController description;
  final TextEditingController durationSeconds;
  final String? temperature;
  final String? heatLevel;
  final String? cookware;
  final String? tips;
  final String? mediaUrl;
  final double? confidence;

  bool get isLowConfidence =>
      confidence != null &&
      confidence! < _ImportDraftReviewPageState._lowConfidenceThreshold;

  RecipeStepInput toInput() => RecipeStepInput(
    id: id,
    description: description.text.trim(),
    durationSeconds: _optionalInt(durationSeconds.text),
    temperature: temperature,
    heatLevel: heatLevel,
    cookware: cookware,
    tips: tips,
    mediaUrl: mediaUrl,
    confidence: confidence,
  );

  void dispose() {
    description.dispose();
    durationSeconds.dispose();
  }
}

String? _requiredValidator(String? value) =>
    (value?.trim().isEmpty ?? true) ? '此项不能为空' : null;

String? _optionalText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _optionalInt(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : int.parse(normalized);
}

String _numberText(int? value) => value?.toString() ?? '';

String _difficultyLabel(RecipeDifficulty difficulty) => switch (difficulty) {
  RecipeDifficulty.unspecified => '未指定',
  RecipeDifficulty.easy => '简单',
  RecipeDifficulty.medium => '中等',
  RecipeDifficulty.hard => '困难',
};

String _platformLabel(ImportSourcePlatform platform) => switch (platform) {
  ImportSourcePlatform.xiaohongshu => '小红书',
  ImportSourcePlatform.douyin => '抖音',
  ImportSourcePlatform.web => '网页',
};

String _fragmentMeta(ImportTextFragment fragment) {
  final parts = <String>[
    _fragmentKindLabel(fragment.kind),
    _sourceTypeLabel(fragment.sourceType),
  ];
  if (fragment.confidence != null) {
    parts.add('置信度 ${(fragment.confidence! * 100).round()}%');
  }
  if (fragment.sourceStartMs != null && fragment.sourceEndMs != null) {
    parts.add(
      '${_durationLabel(fragment.sourceStartMs!)}–${_durationLabel(fragment.sourceEndMs!)}',
    );
  }
  if (fragment.sourceProvider != null) {
    parts.add(fragment.sourceProvider!);
  }
  return parts.join(' · ');
}

/// 证据来源类型中文标签（BUG-006，ADR-0028）。
String _sourceTypeLabel(ImportTextFragmentSourceType type) => switch (type) {
  ImportTextFragmentSourceType.authorText => '作者原文',
  ImportTextFragmentSourceType.ocr => 'OCR 文字',
  ImportTextFragmentSourceType.subtitle => '平台字幕',
  ImportTextFragmentSourceType.asr => '语音转写',
  ImportTextFragmentSourceType.visionObservation => '视觉观察',
  ImportTextFragmentSourceType.inference => '模型推断',
};

String _fragmentKindLabel(ImportTextFragmentKind kind) => switch (kind) {
  ImportTextFragmentKind.title => '标题',
  ImportTextFragmentKind.description => '简介',
  ImportTextFragmentKind.body => '正文',
  ImportTextFragmentKind.caption => '字幕',
  ImportTextFragmentKind.altText => '图片说明',
  ImportTextFragmentKind.metadata => '元数据',
};

String _durationLabel(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
