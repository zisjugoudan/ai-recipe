import '../../domain/access/app_capability.dart';
import '../../domain/access/app_session.dart';
import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/importing/import_task_repository.dart';
import '../../domain/ocr/ocr_model_manifest.dart';
import '../../domain/ocr/ocr_model_package.dart';
import '../../domain/ocr/ocr_model_package_exception.dart';
import '../../domain/recipe/recipe.dart';
import '../access/app_access_use_cases.dart';
import '../importing/import_task_runner.dart';
import '../importing/import_task_use_cases.dart';
import '../importing/single_import_task_dispatcher.dart';
import '../ocr/local_ocr_model_use_cases.dart';
import '../recipe/recipe_library_commands.dart';
import '../recipe/recipe_library_use_cases.dart';
import 'import_execution_plan.dart';
import 'import_task_runner_factory.dart';

enum AiRecipeBackendErrorCode {
  invalidInput,
  importTaskNotFound,
  importDraftNotFound,
  invalidTaskState,
  providerRouteUnavailable,
  storageUnavailable,
  insufficientStorage,
  operationCancelled,
  operationFailed,
  componentNotInstalled,
  componentInstallationFailed,
  componentIncompatible,
}

class AiRecipeBackendException implements Exception {
  const AiRecipeBackendException({required this.code, required this.message});

  final AiRecipeBackendErrorCode code;
  final String message;

  @override
  String toString() => 'AiRecipeBackendException(${code.name}): $message';
}

class ImportDraftConfirmation {
  const ImportDraftConfirmation({required this.task, required this.recipe});

  final ImportTask task;
  final Recipe recipe;
}

class AiRecipeBackendFacade {
  const AiRecipeBackendFacade({
    required this.access,
    required this.recipes,
    required ImportTaskRepository importTaskRepository,
    required ImportTaskRunnerFactory runnerFactory,
    required ImportTaskIdGenerator importTaskIdGenerator,
    required ImportTaskClock clock,
    this.localOcrModels,
  }) : _importTaskRepository = importTaskRepository,
       _runnerFactory = runnerFactory,
       _importTaskIdGenerator = importTaskIdGenerator,
       _clock = clock;

  final AppAccessUseCases access;
  final RecipeLibraryUseCases recipes;
  final ImportTaskRepository _importTaskRepository;
  final ImportTaskRunnerFactory _runnerFactory;
  final ImportTaskIdGenerator _importTaskIdGenerator;
  final ImportTaskClock _clock;
  final LocalOcrModelUseCases? localOcrModels;

  Future<AppSession> loadSession() => access.loadSession();

  Future<AppCapabilitySnapshot> loadCapabilities() => access.loadCapabilities();

  Future<OcrModelPackageStatus> getLocalOcrModelStatus(String packageId) async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      return await useCases.getStatus(packageId);
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  Future<OcrModelPackageStatus> installLocalOcrModel(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  }) async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      return await useCases.install(
        manifest,
        onStatusChanged: onStatusChanged,
        cancellationToken: cancellationToken,
      );
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  Future<void> deleteLocalOcrModel(String packageId) async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      await useCases.delete(packageId);
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  Future<void> recoverLocalOcrModelInstallation() async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      await useCases.recoverInterruptedInstallations();
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  Future<ImportTask> createImportTask(
    String sourceUrl, {
    int maxAttempts = 3,
  }) async {
    await access.requireCapability(AppCapability.publicContentImport);
    try {
      return await CreateImportTask(
        repository: _importTaskRepository,
        idGenerator: _importTaskIdGenerator,
        clock: _clock,
      )(sourceUrl, maxAttempts: maxAttempts);
    } on ImportTaskInputException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法保存，请稍后重试。',
      );
    }
  }

  Future<ImportTask> getImportTask(String id) async {
    final normalizedId = _requireId(id, '导入任务 ID');
    try {
      final task = await _importTaskRepository.getTaskById(normalizedId);
      if (task == null) throw _taskNotFound();
      return task;
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法读取，请稍后重试。',
      );
    }
  }

  Future<List<ImportTask>> listImportTasks({
    Set<ImportTaskStatus>? statuses,
    bool includeDeleted = false,
    int? limit,
  }) async {
    if (limit != null && limit <= 0) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '任务数量限制必须大于 0。',
      );
    }
    try {
      return await _importTaskRepository.listTasks(
        statuses: statuses,
        includeDeleted: includeDeleted,
        limit: limit,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务列表暂时无法读取，请稍后重试。',
      );
    }
  }

  Future<ImportTaskRunResult> runImportTask(
    String id, {
    ImportExecutionPlan plan = const ImportExecutionPlan(),
    ImportCancellationToken? cancellationToken,
  }) async {
    await _requirePlanCapabilities(plan);
    final session = await access.loadSession();
    try {
      final runner = await _runnerFactory.create(plan, userId: session.userId);
      return await runner.run(
        _requireId(id, '导入任务 ID'),
        cancellationToken: cancellationToken,
      );
    } on ImportTaskRunnerFactoryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: error.message,
      );
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '导入任务暂时无法运行，请稍后重试。',
      );
    }
  }

  Future<ImportDispatchReport> dispatchPendingImports({
    ImportExecutionPlan plan = const ImportExecutionPlan(),
    int? limit,
    ImportCancellationToken? cancellationToken,
  }) async {
    await _requirePlanCapabilities(plan);
    final session = await access.loadSession();
    try {
      final runner = await _runnerFactory.create(plan, userId: session.userId);
      return await SingleImportTaskDispatcher(
        repository: _importTaskRepository,
        runner: runner,
      ).dispatchPending(limit: limit, cancellationToken: cancellationToken);
    } on ImportTaskRunnerFactoryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: error.message,
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '任务数量限制必须大于 0。',
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '待处理任务暂时无法调度，请稍后重试。',
      );
    }
  }

  Future<ImportTask> cancelImportTask(String id) {
    return _changeTask(() async {
      return CancelImportTask(repository: _importTaskRepository, clock: _clock)(
        _requireId(id, '导入任务 ID'),
      );
    });
  }

  Future<ImportTask> retryImportTask(String id) {
    return _changeTask(() async {
      return RetryImportTask(repository: _importTaskRepository, clock: _clock)(
        _requireId(id, '导入任务 ID'),
      );
    });
  }

  Future<List<ImportTask>> recoverInterruptedImports() async {
    try {
      return await RecoverInterruptedImportTasks(
        repository: _importTaskRepository,
        clock: _clock,
      )();
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务恢复失败，请稍后重试。',
      );
    }
  }

  Future<Recipe> getImportDraft(String taskId) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview &&
        task.status != ImportTaskStatus.completed) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '当前导入任务没有可查看的菜谱。',
      );
    }
    return _loadDraft(task, includeDeleted: false);
  }

  Future<ImportDraftConfirmation> confirmImportDraft(
    String taskId, {
    RecipeDraftInput? editedDraft,
  }) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '只有待确认的导入任务可以保存菜谱。',
      );
    }

    var recipe = await _loadDraft(task, includeDeleted: false);
    if (recipe.status != RecipeStatus.published) {
      final source = editedDraft ?? _inputFromRecipe(recipe);
      try {
        recipe = await recipes.updateRecipe(recipe.id, _publishedInput(source));
      } on RecipeNotFoundException {
        throw _draftNotFound();
      } on RecipeLibraryValidationException catch (error) {
        throw AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.invalidInput,
          message: error.message,
        );
      } on RecipeLibraryException {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.storageUnavailable,
          message: '菜谱草稿暂时无法保存，请稍后重试。',
        );
      }
    }

    final completed = await _changeTask(() async {
      return CompleteImportTask(
        repository: _importTaskRepository,
        clock: _clock,
      )(task.id);
    });
    return ImportDraftConfirmation(task: completed, recipe: recipe);
  }

  Future<ImportTask> discardImportDraft(String taskId) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '只有待确认的导入任务可以放弃草稿。',
      );
    }
    final recipe = await _loadDraft(task, includeDeleted: true);
    if (recipe.deletedAt == null) {
      try {
        await recipes.softDeleteRecipe(recipe.id);
      } on RecipeNotFoundException {
        throw _draftNotFound();
      } on RecipeLibraryException {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.storageUnavailable,
          message: '菜谱草稿暂时无法移入回收站，请稍后重试。',
        );
      }
    }
    return cancelImportTask(task.id);
  }

  LocalOcrModelUseCases _requireLocalOcrModelUseCases() {
    final useCases = localOcrModels;
    if (useCases == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.componentNotInstalled,
        message: 'Local OCR model management is not available.',
      );
    }
    return useCases;
  }

  static AiRecipeBackendException _mapOcrModelPackageException(
    OcrModelPackageException error,
  ) {
    final code = switch (error.kind) {
      OcrModelPackageErrorKind.incompatiblePlatform ||
      OcrModelPackageErrorKind.incompatibleAppVersion =>
        AiRecipeBackendErrorCode.componentIncompatible,
      OcrModelPackageErrorKind.invalidPackage =>
        AiRecipeBackendErrorCode.invalidInput,
      OcrModelPackageErrorKind.insufficientStorage =>
        AiRecipeBackendErrorCode.insufficientStorage,
      OcrModelPackageErrorKind.cancelled =>
        AiRecipeBackendErrorCode.operationCancelled,
      OcrModelPackageErrorKind.storageUnavailable =>
        AiRecipeBackendErrorCode.storageUnavailable,
      _ => AiRecipeBackendErrorCode.componentInstallationFailed,
    };
    return AiRecipeBackendException(code: code, message: error.message);
  }

  Future<void> _requirePlanCapabilities(ImportExecutionPlan plan) async {
    for (final capability in plan.requiredCapabilities) {
      await access.requireCapability(capability);
    }
  }

  Future<Recipe> _loadDraft(
    ImportTask task, {
    required bool includeDeleted,
  }) async {
    final recipeId = task.resultRecipeId;
    if (recipeId == null || recipeId.trim().isEmpty) throw _draftNotFound();
    try {
      return await recipes.getRecipe(recipeId, includeDeleted: includeDeleted);
    } on RecipeNotFoundException {
      throw _draftNotFound();
    } on RecipeLibraryException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '菜谱草稿暂时无法读取，请稍后重试。',
      );
    }
  }

  Future<ImportTask> _changeTask(
    Future<ImportTask> Function() operation,
  ) async {
    try {
      return await operation();
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法更新，请稍后重试。',
      );
    }
  }

  static RecipeDraftInput _inputFromRecipe(Recipe recipe) {
    return RecipeDraftInput(
      title: recipe.title,
      description: recipe.description,
      coverImage: recipe.coverImage,
      servings: recipe.servings,
      prepTimeMinutes: recipe.prepTimeMinutes,
      cookTimeMinutes: recipe.cookTimeMinutes,
      totalTimeMinutes: recipe.totalTimeMinutes,
      difficulty: recipe.difficulty,
      notes: recipe.notes,
      favorite: recipe.favorite,
      status: recipe.status,
      ingredients: recipe.ingredients
          .map(
            (item) => RecipeIngredientInput(
              id: item.id,
              name: item.name,
              groupName: item.groupName,
              quantity: item.quantity,
              unit: item.unit,
              optional: item.optional,
              preparation: item.preparation,
              substitutes: item.substitutes,
              confidence: item.confidence,
            ),
          )
          .toList(),
      steps: recipe.steps
          .map(
            (item) => RecipeStepInput(
              id: item.id,
              description: item.description,
              durationSeconds: item.durationSeconds,
              temperature: item.temperature,
              heatLevel: item.heatLevel,
              cookware: item.cookware,
              tips: item.tips,
              mediaUrl: item.mediaUrl,
              confidence: item.confidence,
            ),
          )
          .toList(),
      categoryIds: recipe.categoryIds,
    );
  }

  static RecipeDraftInput _publishedInput(RecipeDraftInput input) {
    return RecipeDraftInput(
      title: input.title,
      description: input.description,
      coverImage: input.coverImage,
      servings: input.servings,
      prepTimeMinutes: input.prepTimeMinutes,
      cookTimeMinutes: input.cookTimeMinutes,
      totalTimeMinutes: input.totalTimeMinutes,
      difficulty: input.difficulty,
      notes: input.notes,
      favorite: input.favorite,
      status: RecipeStatus.published,
      ingredients: input.ingredients,
      steps: input.steps,
      categoryIds: input.categoryIds,
    );
  }

  static String _requireId(String id, String fieldName) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '$fieldName 不能为空。',
      );
    }
    return normalized;
  }

  static AiRecipeBackendException _taskNotFound() {
    return const AiRecipeBackendException(
      code: AiRecipeBackendErrorCode.importTaskNotFound,
      message: '没有找到对应的导入任务。',
    );
  }

  static AiRecipeBackendException _draftNotFound() {
    return const AiRecipeBackendException(
      code: AiRecipeBackendErrorCode.importDraftNotFound,
      message: '没有找到对应的菜谱草稿。',
    );
  }
}
