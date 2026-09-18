import 'package:ai_recipe/application/settings/local_app_settings_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_local_business_repositories.dart';

void main() {
  late MemoryLocalAppSettingsRepository repository;
  late MemoryRecipeActivityRepository activityRepository;
  late LocalAppSettingsUseCases useCases;
  late DateTime now;

  setUp(() {
    repository = MemoryLocalAppSettingsRepository();
    activityRepository = MemoryRecipeActivityRepository();
    now = DateTime.utc(2026, 7, 30, 11);
    useCases = LocalAppSettingsUseCases(
      repository: repository,
      activityRepository: activityRepository,
      clock: () => now,
    );
  });

  test('loads privacy-safe local defaults', () async {
    final settings = await useCases.load();

    expect(settings.recordRecipeHistory, isTrue);
    expect(settings.allowTextUpload, isTrue);
    expect(settings.allowImageUpload, isFalse);
    expect(settings.allowVideoUpload, isFalse);
    expect(settings.updatedAt, now);
  });

  test('saves every privacy switch with the current timestamp', () async {
    final settings = await useCases.save(
      const LocalAppSettingsInput(
        recordRecipeHistory: true,
        allowTextUpload: false,
        allowImageUpload: true,
        allowVideoUpload: true,
      ),
    );

    expect(repository.settings, same(settings));
    expect(settings.allowTextUpload, isFalse);
    expect(settings.allowImageUpload, isTrue);
    expect(settings.allowVideoUpload, isTrue);
    expect(settings.updatedAt, now);
    expect(activityRepository.clearCount, 0);
  });

  test('disabling history also clears existing recent views', () async {
    await activityRepository.recordRecipeView('recipe-1', now);

    await useCases.save(
      const LocalAppSettingsInput(
        recordRecipeHistory: false,
        allowTextUpload: true,
        allowImageUpload: false,
        allowVideoUpload: false,
      ),
    );

    expect(activityRepository.views, isEmpty);
    expect(activityRepository.clearCount, 1);
  });

  test('clears history manually without changing settings', () async {
    await activityRepository.recordRecipeView('recipe-1', now);

    await useCases.clearRecipeHistory();

    expect(activityRepository.views, isEmpty);
    expect(repository.saveCount, 0);
  });

  test('maps storage errors to LocalAppSettingsException', () async {
    repository.loadError = StateError('storage implementation detail');
    await expectLater(
      useCases.load(),
      throwsA(isA<LocalAppSettingsException>()),
    );

    repository.loadError = null;
    repository.saveError = StateError('secret path');
    await expectLater(
      useCases.save(
        const LocalAppSettingsInput(
          recordRecipeHistory: true,
          allowTextUpload: true,
          allowImageUpload: false,
          allowVideoUpload: false,
        ),
      ),
      throwsA(isA<LocalAppSettingsException>()),
    );
  });
}
