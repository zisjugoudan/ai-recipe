import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/llm/llm_connection_config.dart';
import 'llm_config_repository.dart';

/// 多模态 LLM 配置仓库（识图引擎，IMAGE-001）。
///
/// 与菜谱生成 LLM 配置（[DeviceLlmConfigRepository]）完全独立：独立存储
/// key 与独立密钥引用，互不影响。接口复用 [LlmConfigRepository]，
/// 因此多模态配置的保存/测试/清除可直接复用 [LlmSettingsUseCases]。
class DeviceMultimodalLlmConfigRepository implements LlmConfigRepository {
  DeviceMultimodalLlmConfigRepository({
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secureStorage,
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _configurationKey = 'active_multimodal_configuration_v1';

  final SharedPreferencesAsync _preferences;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<LlmConnectionConfig?> load() async {
    final raw = await _preferences.getString(_configurationKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('已保存的多模态 LLM 配置格式无效');
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
