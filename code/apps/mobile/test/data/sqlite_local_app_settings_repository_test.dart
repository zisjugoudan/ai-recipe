import 'dart:io';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_local_app_settings_repository.dart';
import 'package:ai_recipe/domain/settings/local_app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteLocalAppSettingsRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_settings_',
    );
    databasePath = path.join(temporaryDirectory.path, 'settings.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteLocalAppSettingsRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('returns null before settings are saved', () async {
    expect(await repository.load(), isNull);
  });

  test('overwrites the singleton and survives database reopen', () async {
    await repository.save(
      LocalAppSettings(
        recordRecipeHistory: true,
        allowTextUpload: true,
        allowImageUpload: false,
        allowVideoUpload: false,
        updatedAt: DateTime.utc(2026, 7, 30, 9),
      ),
    );
    final updatedAt = DateTime.utc(2026, 7, 30, 9, 30);
    await repository.save(
      LocalAppSettings(
        recordRecipeHistory: false,
        allowTextUpload: false,
        allowImageUpload: true,
        allowVideoUpload: true,
        updatedAt: updatedAt,
      ),
    );

    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteLocalAppSettingsRepository(appDatabase);

    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.recordRecipeHistory, isFalse);
    expect(loaded.allowTextUpload, isFalse);
    expect(loaded.allowImageUpload, isTrue);
    expect(loaded.allowVideoUpload, isTrue);
    expect(loaded.updatedAt, updatedAt);
  });
}
