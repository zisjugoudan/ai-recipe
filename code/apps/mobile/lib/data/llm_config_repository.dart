import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/llm/llm_connection_config.dart';

abstract interface class LlmConfigRepository {
  Future<LlmConnectionConfig?> load();
  Future<void> save(LlmConnectionConfig config, {String? apiKey});
  Future<String> readApiKey(String secretRef);
  Future<void> clearApiKey(String secretRef);
}

class DeviceLlmConfigRepository implements LlmConfigRepository {
  DeviceLlmConfigRepository({
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secureStorage,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _configurationKey = 'active_llm_configuration_v1';

  final SharedPreferencesAsync _preferences;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<LlmConnectionConfig?> load() async {
    final raw = await _preferences.getString(_configurationKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('已保存的 LLM 配置格式无效');
    }
    return LlmConnectionConfig.fromJson(decoded);
  }

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {
    if (apiKey != null) {
      if (apiKey.trim().isEmpty) {
        await _secureStorage.delete(key: config.secretRef);
      } else {
        await _secureStorage.write(key: config.secretRef, value: apiKey.trim());
      }
    }
    await _preferences.setString(
      _configurationKey,
      jsonEncode(config.toJson()),
    );
  }

  @override
  Future<String> readApiKey(String secretRef) async {
    return await _secureStorage.read(key: secretRef) ?? '';
  }

  @override
  Future<void> clearApiKey(String secretRef) {
    return _secureStorage.delete(key: secretRef);
  }
}
