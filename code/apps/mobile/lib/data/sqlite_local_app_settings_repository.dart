import 'package:sqflite/sqflite.dart';

import '../domain/settings/local_app_settings.dart';
import 'local/app_database.dart';

class SqliteLocalAppSettingsRepository implements LocalAppSettingsRepository {
  const SqliteLocalAppSettingsRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<LocalAppSettings?> load() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'local_app_settings',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return LocalAppSettings(
      recordRecipeHistory: row['record_recipe_history'] == 1,
      allowTextUpload: row['allow_text_upload'] == 1,
      allowImageUpload: row['allow_image_upload'] == 1,
      allowVideoUpload: row['allow_video_upload'] == 1,
      // 老库迁移前无该列时按默认值 auto（ImageRecognitionMode.fromWireName(null)）。
      imageRecognitionMode: ImageRecognitionMode.fromWireName(
        row['image_recognition_mode'] as String?,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at']! as int,
        isUtc: true,
      ),
    );
  }

  @override
  Future<void> save(LocalAppSettings settings) async {
    final database = await _appDatabase.database;
    await database.insert('local_app_settings', <String, Object?>{
      'id': 1,
      'record_recipe_history': settings.recordRecipeHistory ? 1 : 0,
      'allow_text_upload': settings.allowTextUpload ? 1 : 0,
      'allow_image_upload': settings.allowImageUpload ? 1 : 0,
      'allow_video_upload': settings.allowVideoUpload ? 1 : 0,
      'image_recognition_mode': settings.imageRecognitionMode.wireName,
      'updated_at': settings.updatedAt.toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
