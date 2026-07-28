import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/access/app_access_repository.dart';
import '../domain/access/app_session.dart';

abstract interface class AppSessionKeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPreferencesAppSessionKeyValueStore
    implements AppSessionKeyValueStore {
  SharedPreferencesAppSessionKeyValueStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }
}

class DeviceAppSessionRepository implements AppSessionRepository {
  DeviceAppSessionRepository({AppSessionKeyValueStore? store})
    : _store = store ?? SharedPreferencesAppSessionKeyValueStore();

  static const storageKey = 'app_session_metadata_v1';
  static const _schemaVersion = 1;
  static const _allowedFields = <String>{
    'schemaVersion',
    'kind',
    'userId',
    'displayName',
    'signedInAt',
  };

  final AppSessionKeyValueStore _store;

  @override
  Future<AppSession> load() async {
    final raw = await _store.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const AppSession.guest();
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Session metadata must be an object.');
    }
    final json = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('Session metadata keys must be strings.');
      }
      json[entry.key as String] = entry.value as Object?;
    }
    _validateFields(json);

    if (json['schemaVersion'] != _schemaVersion) {
      throw const FormatException('Unsupported session metadata schema.');
    }
    final kind = json['kind'];
    if (kind == 'guest') {
      if (json.keys.any((key) => key != 'schemaVersion' && key != 'kind')) {
        throw const FormatException('Guest session contains identity fields.');
      }
      return const AppSession.guest();
    }
    if (kind != 'authenticated') {
      throw const FormatException('Unknown session kind.');
    }

    final userId = json['userId'];
    final displayName = json['displayName'];
    final signedInAt = json['signedInAt'];
    if (userId is! String || userId.trim().isEmpty) {
      throw const FormatException('Authenticated session userId is invalid.');
    }
    if (displayName != null && displayName is! String) {
      throw const FormatException('Authenticated displayName is invalid.');
    }
    if (signedInAt is! String || signedInAt.trim().isEmpty) {
      throw const FormatException('Authenticated signedInAt is invalid.');
    }
    final parsedSignedInAt = DateTime.tryParse(signedInAt);
    if (parsedSignedInAt == null) {
      throw const FormatException('Authenticated signedInAt is invalid.');
    }
    return AppSession.authenticated(
      userId: userId,
      displayName: displayName as String?,
      signedInAt: parsedSignedInAt,
    );
  }

  @override
  Future<void> save(AppSession session) {
    return _store.setString(storageKey, jsonEncode(session.toJson()));
  }

  static void _validateFields(Map<String, Object?> json) {
    for (final key in json.keys) {
      if (!_allowedFields.contains(key)) {
        throw const FormatException(
          'Session metadata contains unknown fields.',
        );
      }
    }
    if (json['schemaVersion'] is! int || json['kind'] is! String) {
      throw const FormatException('Session metadata header is invalid.');
    }
  }
}
