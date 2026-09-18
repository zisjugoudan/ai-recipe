import '../../domain/settings/local_app_settings.dart';
import '../../domain/activity/recipe_activity.dart';

typedef LocalAppSettingsClock = DateTime Function();

class LocalAppSettingsInput {
  const LocalAppSettingsInput({
    required this.recordRecipeHistory,
    required this.allowTextUpload,
    required this.allowImageUpload,
    required this.allowVideoUpload,
    this.imageRecognitionMode = ImageRecognitionMode.auto,
  });

  final bool recordRecipeHistory;
  final bool allowTextUpload;
  final bool allowImageUpload;
  final bool allowVideoUpload;

  /// 图片识别方式（识图引擎，IMAGE-001）。
  final ImageRecognitionMode imageRecognitionMode;
}

class LocalAppSettingsException implements Exception {
  const LocalAppSettingsException();
}

class LocalAppSettingsUseCases {
  const LocalAppSettingsUseCases({
    required LocalAppSettingsRepository repository,
    required RecipeActivityRepository activityRepository,
    required LocalAppSettingsClock clock,
  }) : _repository = repository,
       _activityRepository = activityRepository,
       _clock = clock;

  final LocalAppSettingsRepository _repository;
  final RecipeActivityRepository _activityRepository;
  final LocalAppSettingsClock _clock;

  Future<LocalAppSettings> load() async {
    try {
      return await _repository.load() ?? LocalAppSettings(updatedAt: _clock());
    } catch (_) {
      throw const LocalAppSettingsException();
    }
  }

  Future<LocalAppSettings> save(LocalAppSettingsInput input) async {
    final settings = LocalAppSettings(
      recordRecipeHistory: input.recordRecipeHistory,
      allowTextUpload: input.allowTextUpload,
      allowImageUpload: input.allowImageUpload,
      allowVideoUpload: input.allowVideoUpload,
      imageRecognitionMode: input.imageRecognitionMode,
      updatedAt: _clock(),
    );
    try {
      await _repository.save(settings);
      if (!settings.recordRecipeHistory) {
        await _activityRepository.clearRecipeHistory();
      }
      return settings;
    } catch (_) {
      throw const LocalAppSettingsException();
    }
  }

  Future<void> clearRecipeHistory() async {
    try {
      await _activityRepository.clearRecipeHistory();
    } catch (_) {
      throw const LocalAppSettingsException();
    }
  }
}
